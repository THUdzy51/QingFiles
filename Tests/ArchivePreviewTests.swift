import Foundation

@main
struct ArchivePreviewTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("QingFiles-ArchiveTests-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let directory = root.appendingPathComponent("图像")
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        let name = "photo\n1.png"
        let source = directory.appendingPathComponent(name)
        let payload = Data("preview payload".utf8)
        try payload.write(to: source)
        try fm.createSymbolicLink(at: root.appendingPathComponent("alias.png"), withDestinationURL: source)

        let fixtures: [(String, [String])] = [
            ("test.zip", ["--format", "zip"]),
            ("test.7z", ["--format", "7zip"]),
            ("test.tar", []),
            ("test.tgz", ["-z"]),
            ("test.tar.bz2", ["-j"]),
            ("test.tar.xz", ["-J"]),
            ("test.cpio", ["--format", "cpio"]),
            ("test.xar", ["--format", "xar"])
        ]
        for (filename, options) in fixtures {
            let archive = root.appendingPathComponent(filename)
            try run("/usr/bin/bsdtar", options + ["-cf", filename, "图像", "alias.png"], in: root)
            let listing = try ArchivePreview.list(archive, limit: 10, cancelled: { false })
            guard let member = listing.members.first(where: { $0.path == ["图像", name] }),
                  !listing.isPartial, member.isRegularFile, !member.isEncrypted else {
                fatalError("Missing regular file or Unicode path in \(filename)")
            }
            precondition(listing.members.contains { $0.path == ["alias.png"] && !$0.isRegularFile })
            let materialized = try ArchivePreview.materialize(member, in: archive, cancelled: { false })
            defer { try? fm.removeItem(at: materialized.deletingLastPathComponent()) }
            let bytes = try Data(contentsOf: materialized)
            precondition(bytes == payload && materialized.pathExtension == "png")
            let limited = try ArchivePreview.list(archive, limit: 1, cancelled: { false })
            precondition(limited.isPartial && limited.members.count <= 1)
            print("PASS \(filename) lists paths and reads a single entry")
        }

        let single = root.appendingPathComponent("single.png.gz")
        fm.createFile(atPath: single.path, contents: nil)
        let output = try FileHandle(forWritingTo: single)
        try run("/usr/bin/gzip", ["-c", source.path], in: root, output: output)
        try output.close()
        let stream = try ArchivePreview.list(single, limit: 10, cancelled: { false })
        precondition(stream.members.map(\.path) == [["single.png"]])
        let rawFile = try ArchivePreview.materialize(stream.members[0], in: single, cancelled: { false })
        defer { try? fm.removeItem(at: rawFile.deletingLastPathComponent()) }
        let rawBytes = try Data(contentsOf: rawFile)
        precondition(rawBytes == payload)

        let traversal = root.appendingPathComponent("traversal.tar")
        try run("/usr/bin/bsdtar", ["-cf", traversal.path, "-s", "|.*|../outside.png|", "图像/\(name)"], in: root)
        let unsafePaths = try ArchivePreview.list(traversal, limit: 10, cancelled: { false })
        precondition(unsafePaths.members.isEmpty)

        let misleading = root.appendingPathComponent("not-really.gz")
        try payload.write(to: misleading)
        do {
            _ = try ArchivePreview.list(misleading, limit: 10, cancelled: { false })
            fatalError("An uncompressed file was accepted as a compressed stream")
        } catch is FileServiceError {}

        let locked = root.appendingPathComponent("locked.zip")
        try run("/usr/bin/zip", ["-q", "-P", "fixture-password", locked.path, "图像/\(name)"], in: root)
        let protected = try ArchivePreview.list(locked, limit: 10, cancelled: { false })
        precondition(protected.members.first?.isEncrypted == true)
        do {
            _ = try ArchivePreview.materialize(protected.members[0], in: locked, cancelled: { false })
            fatalError("Encrypted entry was read without a password")
        } catch is FileServiceError {}
        do {
            _ = try ArchivePreview.list(locked, limit: 10, cancelled: { true })
            fatalError("Cancelled archive scan succeeded")
        } catch is CancellationError {}
        print("PASS raw compressed stream, unsafe path rejection, password protection, and cancellation")
    }

    private static func run(_ path: String, _ arguments: [String], in directory: URL,
                            output: FileHandle? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        if let output { process.standardOutput = output }
        try process.run()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0, "Cannot create archive fixture: \(arguments)")
    }
}
