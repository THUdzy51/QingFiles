import AppKit

@main
struct FileRevealServiceTests {
    static func main() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let files = [URL(fileURLWithPath: "/tmp/中文 空格.pdf"), URL(fileURLWithPath: "/tmp/Folder")]
        pasteboard.writeObjects(files.map { $0 as NSURL })
        let decoded = try FileRevealService.fileURLs(from: pasteboard)
        precondition(decoded.map(\.path) == files.map(\.path), "file URL decoding changed filenames")
        print("PASS: service receives multiple file and folder URLs with Unicode and spaces")

        pasteboard.clearContents()
        pasteboard.setPropertyList(files.map(\.path), forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        let legacy = try FileRevealService.fileURLs(from: pasteboard)
        precondition(legacy.map(\.path) == files.map(\.path), "legacy filename decoding failed")
        print("PASS: service accepts legacy filename pasteboards")

        for content in ["", "https://example.com/file.pdf", "/tmp/plain text"] {
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
            do {
                _ = try FileRevealService.fileURLs(from: pasteboard)
                fatalError("text-only pasteboard was accepted as a file selection")
            } catch {
                print("PASS: service rejects a pasteboard without selected local files")
            }
        }
        print("SUCCESS: 5 file service checks passed.")
    }
}
