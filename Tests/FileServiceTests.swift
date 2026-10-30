import Foundation

@main
struct FileServiceTests {
    static var passed = 0

    static func expect(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
        guard try condition() else { throw TestError.failed(label) }
        passed += 1
        print("PASS: \(label)")
    }

    enum TestError: Error { case failed(String) }

    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("QingFiles-Tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let source = try FileService.createDirectory(named: "source", in: root)
        let target = try FileService.createDirectory(named: "target", in: root)
        let payload = source.appendingPathComponent("data.txt")
        try Data("original contents".utf8).write(to: payload)
        let hidden = source.appendingPathComponent(".settings")
        try Data("hidden".utf8).write(to: hidden)
        let attributeHidden = source.appendingPathComponent("attribute-hidden")
        try Data("hidden by flag".utf8).write(to: attributeHidden)
        var hiddenURL = attributeHidden
        var hiddenValues = URLResourceValues()
        hiddenValues.isHidden = true
        try hiddenURL.setResourceValues(hiddenValues)
        let folder = try FileService.createDirectory(named: "folder", in: source)
        let nested = folder.appendingPathComponent("child.txt")
        try Data("nested".utf8).write(to: nested)

        let visible = try FileService.list(source, showHidden: false)
        try expect(visible.map(\.name) == ["folder", "data.txt"], "listing sorts folders first and hides dot/flagged files")
        let all = try FileService.list(source, showHidden: true)
        try expect(all.count == 4, "show-hidden reveals both hidden kinds")
        try expect(all.first(where: { $0.name == "data.txt" })?.size == 17, "metadata preserves file byte size")

        for name in ["", "   ", ".", "..", "bad/name", "nul\0name"] {
            do { _ = try FileService.createDirectory(named: name, in: source); throw TestError.failed("invalid name accepted") }
            catch is FileServiceError { passed += 1 }
        }
        print("PASS: six invalid names rejected")
        do { _ = try FileService.createDirectory(named: "folder", in: source); throw TestError.failed("existing directory accepted") }
        catch is FileServiceError { passed += 1; print("PASS: create directory does not reuse existing names") }

        let copied = FileService.transfer([payload], to: target, mode: .copy)
        try expect(copied.succeeded.count == 1 && copied.failures.isEmpty, "file copy succeeds")
        let targetFile = target.appendingPathComponent("data.txt")
        try expect(try Data(contentsOf: targetFile) == Data("original contents".utf8), "copy preserves contents")
        try Data("source changed".utf8).write(to: payload)
        let collision = FileService.transfer([payload], to: target, mode: .copy)
        try expect(collision.succeeded.isEmpty && collision.failures.count == 1, "copy collision is reported")
        try expect(try Data(contentsOf: targetFile) == Data("original contents".utf8), "collision never overwrites destination")
        let moveCollision = FileService.transfer([payload], to: target, mode: .move)
        try expect(moveCollision.failures.count == 1 && fm.fileExists(atPath: payload.path), "move collision preserves source")

        let partial = FileService.transfer([payload, hidden], to: target, mode: .copy)
        try expect(partial.succeeded.count == 1 && partial.failures.count == 1, "batch reports partial success")
        let selfCopy = FileService.transfer([payload], to: source, mode: .copy)
        try expect(selfCopy.succeeded.isEmpty && selfCopy.failures.count == 1, "same-source destination rejected")
        let childCopy = FileService.transfer([folder], to: folder, mode: .copy)
        try expect(childCopy.succeeded.isEmpty && childCopy.failures.count == 1, "folder copy into itself rejected")
        let deep = try FileService.createDirectory(named: "deep", in: folder)
        let descendant = FileService.transfer([folder], to: deep, mode: .copy)
        try expect(descendant.succeeded.isEmpty && descendant.failures.count == 1, "folder copy into descendant rejected")

        let alias = root.appendingPathComponent("deep-link")
        try fm.createSymbolicLink(at: alias, withDestinationURL: deep)
        let viaAlias = FileService.transfer([folder], to: alias, mode: .move)
        try expect(viaAlias.succeeded.isEmpty && viaAlias.failures.count == 1 && fm.fileExists(atPath: folder.path), "symlink cannot bypass descendant guard")
        let rootEntries = try FileService.list(root, showHidden: true)
        try expect(rootEntries.first(where: { $0.name == "deep-link" })?.isDirectory == true, "directory symlinks are navigable")
        try expect(rootEntries.first(where: { $0.name == "deep-link" })?.isSymbolicLink == true, "directory symlinks remain identifiable")

        let repeated = FileService.transfer([folder, folder], to: target, mode: .copy)
        try expect(repeated.succeeded.isEmpty && repeated.failures.count == 2, "duplicate selection rejected before mutations")
        let overlapping = FileService.transfer([folder, nested], to: target, mode: .move)
        try expect(overlapping.succeeded.isEmpty && overlapping.failures.count == 2 && fm.fileExists(atPath: nested.path), "parent-child selections preserve both sources")

        let renamed = try FileService.rename(payload, to: "renamed.txt")
        try expect(renamed.lastPathComponent == "renamed.txt" && !fm.fileExists(atPath: payload.path), "rename updates path without losing data")
        do { _ = try FileService.rename(renamed, to: ".settings"); throw TestError.failed("rename overwrite accepted") }
        catch is FileServiceError { passed += 1; print("PASS: rename collision rejected") }
        try expect(try Data(contentsOf: hidden) == Data("hidden".utf8), "rename conflict preserves destination contents")
        let moved = FileService.transfer([renamed], to: target, mode: .move)
        try expect(moved.succeeded.count == 1 && moved.failures.isEmpty && !fm.fileExists(atPath: renamed.path), "move completes and removes original path")
        try expect(try Data(contentsOf: target.appendingPathComponent("renamed.txt")) == Data("source changed".utf8), "move preserves contents")
        let treeCopy = FileService.transfer([folder], to: target, mode: .copy)
        try expect(treeCopy.succeeded.count == 1 && fm.fileExists(atPath: target.appendingPathComponent("folder/child.txt").path), "directory tree copies normally")

        let dangling = target.appendingPathComponent("dangling")
        try fm.createSymbolicLink(at: dangling, withDestinationURL: root.appendingPathComponent("missing-target"))
        let danglingSource = source.appendingPathComponent("dangling")
        try Data("do not overwrite a broken link".utf8).write(to: danglingSource)
        let brokenCollision = FileService.transfer([danglingSource], to: target, mode: .copy)
        try expect(brokenCollision.failures.count == 1 && brokenCollision.succeeded.isEmpty, "broken destination symlink counts as an existing item")
        try expect(try fm.destinationOfSymbolicLink(atPath: dangling.path) == root.appendingPathComponent("missing-target").path, "broken symlink remains unchanged")

        let missing = FileService.transfer([source.appendingPathComponent("does-not-exist")], to: target, mode: .copy)
        try expect(missing.failures.count == 1, "missing source is reported")
        let nonlocal = FileService.transfer([URL(string: "https://example.invalid/file")!], to: target, mode: .copy)
        try expect(nonlocal.failures.count == 1, "remote URLs rejected")
        let noDestination = FileService.transfer([hidden], to: root.appendingPathComponent("missing"), mode: .copy)
        try expect(noDestination.failures.count == 1 && fm.fileExists(atPath: hidden.path), "missing target folder preserves source")
        let rootTrash = FileService.trash([URL(fileURLWithPath: "/")])
        try expect(rootTrash.succeeded.isEmpty && rootTrash.failures.count == 1, "filesystem root trash rejected without mutation")
        print("SUCCESS: \(passed) checks passed; all test data removed from private temporary directory.")
    }
}
