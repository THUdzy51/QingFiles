import Foundation
import Darwin

@main
struct RemoteServiceTests {
    static var count = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
        guard try condition() else { throw RemoteError.message("FAIL: \(label)") }
        count += 1; print("PASS: \(label)")
    }
    static func rejects(_ label: String, _ action: () throws -> Void) throws {
        do { try action() } catch { count += 1; print("PASS: \(label)"); return }
        throw RemoteError.message("FAIL: \(label)")
    }
    static func main() throws {
        setbuf(stdout, nil)
        try expect(try RemotePath.clean("/a/../b//c") == "/b/c", "remote path normalization")
        try rejects("reject batch command injection") { _ = try RemotePath.clean("/a\nrm /") }
        try rejects("reject listing traversal") { _ = try RemotePath.child("../escape", in: "/") }
        try rejects("reject host option injection") { _ = try RemoteProfile(host: "-oProxyCommand=bad", username: "demo").validated() }
        try rejects("reject username command syntax") { _ = try RemoteProfile(host: "localhost", username: "demo;bad").validated() }
        let quoted = try RemotePath.sftpQuote("/folder/a [1]*\".txt")
        try expect(quoted.contains("[1]*") && quoted.contains("\\\""), "quote literal glob and quote characters")
        let mlsd = try RemoteListing.mlsd("type=cdir; .\r\ntype=dir; child folder\r\ntype=file;size=12; report one.txt\r\n")
        try expect(mlsd.count == 2 && mlsd[0].isDirectory && mlsd[1].name == "report one.txt" && mlsd[1].size == 12, "MLSD directory and spaced filename parsing")
        try rejects("reject non-MLSD FTP response") { _ = try RemoteListing.mlsd("a nonstandard listing") }
        let listed = try RemoteListing.sftp("sftp> ls -lan \"/\"\n-rw-r--r-- 1 1000 1000 18 Oct 30 10:00 report one.txt\ndrwxr-xr-x 2 1000 1000 4096 Oct 30 2026 folder\n")
        try expect(listed.count == 2 && listed[0].isDirectory && listed[1].name == "report one.txt", "SFTP listing retains spaces")
        let unknownLinks = try RemoteListing.sftp("-rw-r--r--    ? 501 20 18 Oct 30 15:27 /folder with spaces/report [1].txt\n")
        try expect(unknownLinks.first?.name == "report [1].txt", "SFTP unknown link count and absolute filename")
        let hostFile = FileManager.default.temporaryDirectory.appendingPathComponent("qingfiles-test-known-hosts-\(UUID().uuidString)")
        let backend = try RemoteService(profile: RemoteProfile(host: "localhost", username: "demo"), password: "never-in-script", knownHosts: hostFile)
        try expect(backend.terminalScript().contains("StrictHostKeyChecking=yes") && !backend.terminalScript().contains("never-in-script"), "terminal script verifies host and excludes password")
        let token = RemoteCancellation(); token.cancel()
        try rejects("cancel before process spawn") { _ = try RemoteCommand.run("/usr/bin/true", [], cancellation: token) }
        let runningToken = RemoteCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { runningToken.cancel() }
        try rejects("cancel running process") { _ = try RemoteCommand.run("/bin/sleep", ["5"], timeout: 3, cancellation: runningToken) }
        try rejects("enforce process timeout") { _ = try RemoteCommand.run("/bin/sleep", ["5"], timeout: 0.15) }
        if CommandLine.arguments.count > 1 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let config = try JSONSerialization.jsonObject(with: data) as! [String:Any]
            let base = URL(fileURLWithPath: config["workspace"] as! String)
            let helper = URL(fileURLWithPath: config["askpass"] as! String)
            let pass = config["password"] as! String
            for scheme in ["FTP", "FTPS", "SFTP"] {
                let port = config[scheme.lowercased() + "Port"] as! Int
                let profile = RemoteProfile(kind: scheme, host: "127.0.0.1", port: port, username: "demo")
                let keys = base.appendingPathComponent("known hosts with spaces")
                let remote = try RemoteService(profile: profile, password: pass, knownHosts: keys, askpass: helper)
                if scheme == "SFTP" {
                    try rejects("untrusted SSH host rejected") { _ = try remote.list("/") }
                    let scan = try remote.hostKeyScan()
                    try expect(scan.fingerprints.contains("SHA256:"), "host key fingerprint scan")
                    try remote.trustHostKeys(scan.keys)
                }
                let listing = try remote.list("/")
                try expect(listing.contains { $0.name == "server sample.txt" }, "\(scheme) authenticated directory listing")
                let source = base.appendingPathComponent("\(scheme) upload [1]*.txt")
                try Data("round-trip \(scheme) ✓".utf8).write(to: source)
                try remote.upload(source, to: "/", cancellation: RemoteCancellation())
                try rejects("\(scheme) upload collision preserves existing item") { try remote.upload(source, to: "/", cancellation: RemoteCancellation()) }
                let after = try remote.list("/")
                guard let entry = after.first(where: { $0.name == source.lastPathComponent }) else { throw RemoteError.message("Uploaded file missing") }
                let destination = base.appendingPathComponent("download-\(scheme)")
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                let downloaded = try remote.download(entry, from: "/", to: destination, cancellation: RemoteCancellation())
                let received = try Data(contentsOf: downloaded), original = try Data(contentsOf: source)
                try expect(received == original, "\(scheme) upload/download byte equality")
                try rejects("\(scheme) local collision blocked") { _ = try remote.download(entry, from: "/", to: destination, cancellation: RemoteCancellation()) }
                let bad = try RemoteService(profile: profile, password: "incorrect-test-password", knownHosts: keys, askpass: helper)
                try rejects("\(scheme) wrong password rejected") { _ = try bad.list("/") }
            }
        }
        print("SUCCESS: \(count) remote checks passed.")
    }
}
