import Foundation
import Security
import Darwin

struct RemoteProfile: Codable, Equatable {
    var id = UUID().uuidString
    var name = "New Connection"
    var kind = "SFTP"
    var host = ""
    var port = 22
    var username = ""
    var directory = "/"
    var identityFile = ""
    func validated() throws -> RemoteProfile {
        guard ["SFTP", "FTP", "FTPS"].contains(kind), (1...65535).contains(port),
              host.range(of: "^[A-Za-z0-9][A-Za-z0-9.:%_-]*$", options: .regularExpression) != nil,
              username.range(of: "^[A-Za-z0-9_][A-Za-z0-9._-]*$", options: .regularExpression) != nil else {
            throw RemoteError.message("Enter a valid host, username, and port (1–65535). Do not include a URL or user@ prefix in Host.")
        }
        _ = try RemotePath.clean(directory)
        guard !identityFile.contains("\n"), !identityFile.contains("\r"), !identityFile.contains("\0") else { throw RemoteError.message("Invalid identity file path.") }
        return self
    }
}

enum RemoteError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum RemotePath {
    static func clean(_ path: String) throws -> String {
        guard path.hasPrefix("/"), !path.contains("\n"), !path.contains("\r"), !path.contains("\0") else { throw RemoteError.message("Use an absolute remote path without control characters.") }
        var parts: [String] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(String(part))
        }
        return "/" + parts.joined(separator: "/")
    }
    static func child(_ name: String, in directory: String) throws -> String {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\n"), !name.contains("\r"), !name.contains("\0") else { throw RemoteError.message("The server returned an unsupported filename.") }
        return try clean(directory + "/" + name)
    }
    // SFTP batch uses its own quoting and globbing grammar, not a shell.
    static func sftpQuote(_ path: String) throws -> String {
        guard !path.contains("\n"), !path.contains("\r"), !path.contains("\0") else { throw RemoteError.message("Paths with control characters are not supported.") }
        var value = ""
        for c in path { if "\\\"".contains(c) { value += "\\" }; value.append(c) }
        return "\"" + value + "\""
    }
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

struct RemoteEntry {
    var name: String
    var isDirectory: Bool
    var isSymbolicLink: Bool
    var size: Int64
    var modified: Date?
}

enum RemoteListing {
    static func mlsd(_ text: String) throws -> [RemoteEntry] {
        var result: [RemoteEntry] = []
        for raw in text.components(separatedBy: .newlines) where !raw.isEmpty {
            guard let split = raw.firstIndex(of: " ") else { throw RemoteError.message("Unsupported FTP directory listing. The server must support MLSD.") }
            let factsString = raw[..<split]
            let name = String(raw[raw.index(after: split)...])
            var facts: [String:String] = [:]
            for field in factsString.split(separator: ";") {
                let pair = field.split(separator: "=", maxSplits: 1)
                if pair.count == 2 { facts[pair[0].lowercased()] = String(pair[1]) }
            }
            guard let type = facts["type"]?.lowercased() else { throw RemoteError.message("FTP server did not return an MLSD listing.") }
            if type == "cdir" || type == "pdir" || name == "." || name == ".." { continue }
            _ = try RemotePath.child(name, in: "/")
            result.append(RemoteEntry(name: name, isDirectory: type == "dir", isSymbolicLink: type.contains("slink"), size: Int64(facts["size"] ?? "0") ?? 0, modified: nil))
        }
        return sorted(result)
    }
    static func sftp(_ text: String) throws -> [RemoteEntry] {
        let regex = try NSRegularExpression(pattern: "^([dl-][rwxstST-]{9})[+@.]?\\s+[0-9?]+\\s+\\S+\\s+\\S+\\s+(\\d+)\\s+\\S+\\s+\\S+\\s+\\S+\\s+(.*)$")
        var result: [RemoteEntry] = []
        for line in text.components(separatedBy: .newlines) {
            if line.isEmpty || line.hasPrefix("sftp>") || line.hasPrefix("total ") { continue }
            let ns = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { throw RemoteError.message("Unsupported SFTP long listing. Server filenames containing newlines or a nonstandard listing are not supported.") }
            let permissions = ns.substring(with: match.range(at: 1))
            let symlink = permissions.hasPrefix("l")
            let displayed = ns.substring(with: match.range(at: 3))
            let listedName = symlink ? (displayed.components(separatedBy: " -> ").first ?? displayed) : displayed
            let name = listedName.hasPrefix("/") ? (listedName as NSString).lastPathComponent : listedName
            if name == "." || name == ".." { continue }
            _ = try RemotePath.child(name, in: "/")
            result.append(RemoteEntry(name: name, isDirectory: permissions.hasPrefix("d"), isSymbolicLink: symlink, size: Int64(ns.substring(with: match.range(at: 2))) ?? 0, modified: nil))
        }
        return sorted(result)
    }
    private static func sorted(_ entries: [RemoteEntry]) -> [RemoteEntry] {
        entries.sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

final class RemoteCancellation {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; let p = process; lock.unlock(); if p?.isRunning == true { p?.terminate() } }
    func attach(_ p: Process?) { lock.lock(); process = p; let stop = cancelled; lock.unlock(); if stop, p?.isRunning == true { p?.terminate() } }
}

struct CommandOutput { var output: String; var error: String; var status: Int32 }
enum RemoteCommand {
    static func run(_ executable: String, _ arguments: [String], input: String = "", environment: [String:String] = [:], timeout: TimeInterval = 60, cancellation: RemoteCancellation = RemoteCancellation()) throws -> CommandOutput {
        signal(SIGPIPE, SIG_IGN)
        if cancellation.isCancelled { throw RemoteError.message("Cancelled.") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let output = Pipe(), errors = Pipe(), stdin = Pipe()
        process.standardOutput = output; process.standardError = errors; process.standardInput = stdin
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run(); cancellation.attach(process)
        defer { cancellation.attach(nil) }
        let capture = Capture()
        let group = DispatchGroup()
        for (pipe, isError) in [(output, false), (errors, true)] {
            group.enter()
            DispatchQueue.global().async {
                var collected = Data()
                while true {
                    let chunk = pipe.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    if collected.count + chunk.count <= 8 * 1024 * 1024 { collected.append(chunk) } else { capture.overflow = true }
                }
                capture.set(collected, error: isError); group.leave()
            }
        }
        try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)); try? stdin.fileHandleForWriting.close()
        if done.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            throw RemoteError.message("The operation timed out. Refresh the destination before retrying; a partial transfer may remain.")
        }
        _ = group.wait(timeout: .now() + 3)
        if cancellation.isCancelled { throw RemoteError.message("Cancelled. A partial remote transfer may remain; refresh before retrying.") }
        if capture.overflow { throw RemoteError.message("Directory output exceeds the 8 MB limit.") }
        return CommandOutput(output: capture.string(error: false), error: capture.string(error: true), status: process.terminationStatus)
    }
    private final class Capture {
        private let lock = NSLock(); private var out = Data(); private var err = Data(); private var excess = false
        var overflow: Bool { get { lock.lock(); defer { lock.unlock() }; return excess } set { lock.lock(); excess = newValue; lock.unlock() } }
        func set(_ data: Data, error: Bool) { lock.lock(); defer { lock.unlock() }; if error { err = data } else { out = data } }
        func string(error: Bool) -> String { lock.lock(); defer { lock.unlock() }; return String(decoding: error ? err : out, as: UTF8.self) }
    }
}

enum RemoteCredentials {
    static func password(for id: String) -> String? {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"QingFiles Remote", kSecAttrAccount as String:id, kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ password: String, for id: String) throws {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"QingFiles Remote", kSecAttrAccount as String:id]
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }
        let item = query.merging([kSecValueData as String:Data(password.utf8), kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlocked]) { _, n in n }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw RemoteError.message("Could not save the password in Keychain (\(status)).") }
    }
}

final class RemoteService {
    let profile: RemoteProfile
    private let password: String
    let knownHosts: URL
    private let askpass: URL
    init(profile: RemoteProfile, password: String, knownHosts: URL? = nil, askpass: URL? = nil) throws {
        self.profile = try profile.validated(); self.password = password
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QingFiles", isDirectory: true)
        self.knownHosts = knownHosts ?? support.appendingPathComponent("known_hosts")
        self.askpass = askpass ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/QingFilesAskpass")
    }
    var sshArguments: [String] {
        var args = ["-F", "/dev/null", "-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=\"\(knownHosts.path)\"", "-o", "ConnectTimeout=12", "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=2", "-o", "NumberOfPasswordPrompts=1", "-o", "ForwardAgent=no", "-o", "ClearAllForwardings=yes"]
        if !profile.identityFile.isEmpty { args += ["-i", (profile.identityFile as NSString).expandingTildeInPath] }
        return args
    }
    private func sftp(_ commands: String, cancellation: RemoteCancellation, timeout: TimeInterval = 60) throws -> String {
        let destinationHost = profile.host.contains(":") ? "[\(profile.host)]" : profile.host
        let env = ["SSH_ASKPASS":askpass.path, "SSH_ASKPASS_REQUIRE":"force", "DISPLAY":"QingFiles:0", "QINGFILES_PASSWORD":password, "LC_ALL":"C"]
        let result = try RemoteCommand.run("/usr/bin/sftp", ["-o", "BatchMode=no", "-o", "PreferredAuthentications=publickey,password,keyboard-interactive", "-b", "-", "-P", String(profile.port)] + sshArguments + ["\(profile.username)@\(destinationHost)"], input: commands + "\n", environment: env, timeout: timeout, cancellation: cancellation)
        try check(result)
        return result.output
    }
    private func ftpURL(_ path: String, directory: Bool) throws -> String {
        let path = try RemotePath.clean(path)
        var components = URLComponents(); components.scheme = "ftp"; components.host = profile.host; components.port = profile.port
        components.path = "/" + path + (directory && path != "/" ? "/" : "")
        guard let url = components.url?.absoluteString else { throw RemoteError.message("Invalid FTP URL.") }
        return url
    }
    private func ftp(_ path: String, arguments: [String], directory: Bool, cancellation: RemoteCancellation, timeout: TimeInterval = 60) throws -> String {
        func configQuote(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") }
        var args = ["--disable", "--silent", "--show-error", "--fail", "--globoff", "--connect-timeout", "12", "--max-time", String(Int(timeout)), "--config", "-", "--url", try ftpURL(path, directory: directory)]
        if profile.kind == "FTPS" { args += ["--ssl-reqd"] }
        args += arguments
        let result = try RemoteCommand.run("/usr/bin/curl", args, input: "user = \"\(configQuote(profile.username + ":" + password))\"\n", timeout: timeout + 5, cancellation: cancellation)
        try check(result); return result.output
    }
    private func check(_ result: CommandOutput) throws {
        guard result.status == 0 else {
            var detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            if !password.isEmpty { detail = detail.replacingOccurrences(of: password, with: "[redacted]") }
            throw RemoteError.message(detail.isEmpty ? "Remote command failed (\(result.status))." : String(detail.prefix(3000)))
        }
    }
    func list(_ path: String, cancellation: RemoteCancellation = RemoteCancellation()) throws -> [RemoteEntry] {
        if profile.kind == "SFTP" { return try RemoteListing.sftp(sftp("ls -lan \(RemotePath.sftpQuote(RemotePath.clean(path)))", cancellation: cancellation)) }
        return try RemoteListing.mlsd(ftp(path, arguments: ["--request", "MLSD"], directory: true, cancellation: cancellation))
    }
    func upload(_ local: URL, to directory: String, cancellation: RemoteCancellation) throws {
        let metadata = try local.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard metadata.isRegularFile == true, metadata.isSymbolicLink != true else { throw RemoteError.message("Upload supports regular files only. Folder and symbolic-link transfer is not available yet.") }
        let target = try RemotePath.child(local.lastPathComponent, in: directory)
        let existing = try list(directory, cancellation: cancellation)
        guard !existing.contains(where: { $0.name == local.lastPathComponent }) else { throw RemoteError.message("The remote destination already contains \(local.lastPathComponent). Skipped.") }
        if profile.kind == "SFTP" { _ = try sftp("put \(RemotePath.sftpQuote(local.path)) \(RemotePath.sftpQuote(target))", cancellation: cancellation, timeout: 3600) }
        else { _ = try ftp(target, arguments: ["--upload-file", local.path], directory: false, cancellation: cancellation, timeout: 3600) }
    }
    func download(_ entry: RemoteEntry, from directory: String, to localDirectory: URL, cancellation: RemoteCancellation) throws -> URL {
        guard !entry.isDirectory, !entry.isSymbolicLink else { throw RemoteError.message("Download supports regular files only. Select a file rather than a folder or link.") }
        let path = try RemotePath.child(entry.name, in: directory)
        let target = localDirectory.appendingPathComponent(entry.name)
        if (try? FileManager.default.attributesOfItem(atPath: target.path)) != nil { throw RemoteError.message("A local item named \(entry.name) already exists. Skipped.") }
        let staging = localDirectory.appendingPathComponent(".qingfiles-\(UUID().uuidString).part")
        defer { try? FileManager.default.removeItem(at: staging) }
        if profile.kind == "SFTP" { _ = try sftp("get \(RemotePath.sftpQuote(path)) \(RemotePath.sftpQuote(staging.path))", cancellation: cancellation, timeout: 3600) }
        else { _ = try ftp(path, arguments: ["--output", staging.path], directory: false, cancellation: cancellation, timeout: 3600) }
        try FileManager.default.moveItem(at: staging, to: target)
        return target
    }
    func hostKeyScan() throws -> (keys: String, fingerprints: String) {
        let result = try RemoteCommand.run("/usr/bin/ssh-keyscan", ["-T", "8", "-p", String(profile.port), profile.host], timeout: 12)
        guard !result.output.isEmpty else { throw RemoteError.message("No SSH host keys were returned. Check the host and SSH port.") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("qingfiles-key-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try result.output.write(to: url, atomically: true, encoding: .utf8)
        let fingerprints = try RemoteCommand.run("/usr/bin/ssh-keygen", ["-lf", url.path, "-E", "sha256"]).output
        return (result.output, fingerprints)
    }
    func trustHostKeys(_ keys: String) throws {
        try FileManager.default.createDirectory(at: knownHosts.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
        // Explicit user consent is required before this method is called.
        let old = (try? String(contentsOf: knownHosts, encoding: .utf8)) ?? ""
        try (old + (old.hasSuffix("\n") || old.isEmpty ? "" : "\n") + keys).write(to: knownHosts, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath: knownHosts.path)
    }
    func terminalScript() -> String {
        let args = sshArguments + ["-p", String(profile.port), "-l", profile.username, profile.host]
        return "#!/bin/sh\nexec /usr/bin/ssh " + args.map(RemotePath.shellQuote).joined(separator: " ") + "\n"
    }
}
