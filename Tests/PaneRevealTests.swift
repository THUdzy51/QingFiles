import AppKit

@main
struct PaneRevealTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
        print("PASS: \(message)")
    }

    static func waitUntil(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        expect(condition(), "asynchronous reveal completes")
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    static func main() throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("QingFiles-Reveal-\(UUID().uuidString)")
        let source = root.appendingPathComponent("中文 空格")
        let other = root.appendingPathComponent("Other")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: other, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let file = source.appendingPathComponent("z 文档.pdf")
        let second = source.appendingPathComponent("second.txt")
        let hidden = source.appendingPathComponent(".hidden.txt")
        for url in [file, second, hidden] {
            try Data("original".utf8).write(to: url)
        }
        for index in 0..<80 {
            try Data().write(to: source.appendingPathComponent("row-\(index).txt"))
        }
        let pane = FilePane(directory: other, title: "Left")
        pane.onActivate = { $0.isActive = true }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 475, height: 260), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = pane.view
        pane.view.frame = NSRect(x: 0, y: 0, width: 475, height: 260)
        pane.view.layoutSubtreeIfNeeded()
        let controls = descendants(pane.view)
        let table = controls.compactMap { $0 as? NSTableView }.first!
        let search = controls.compactMap { $0 as? NSSearchField }.first!
        let status = controls.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Loading…" }!
        pane.focusSearch()
        search.stringValue = "no matches"
        try pane.revealFiles([file])
        pane.refresh()
        pane.refresh()
        waitUntil { pane.selectedURLs == [file] }
        expect(pane.currentDirectory.path == source.path && search.isHidden && search.stringValue.isEmpty,
               "external reveal clears search and navigates to the original containing folder")
        let selectedRow = table.selectedRowIndexes.first!
        expect(table.rows(in: table.visibleRect).contains(selectedRow), "reveal scrolls the selected row into view")
        expect(!(window.firstResponder is NSTextView), "reveal selects without starting inline naming")
        let contents = try Data(contentsOf: file)
        expect(contents == Data("original".utf8), "reveal preserves file contents")

        try pane.revealFiles([file, second])
        waitUntil { Set(pane.selectedURLs) == Set([file, second]) }
        expect(pane.currentDirectory.path == source.path, "multiple files in one folder are selected together")
        pane.revealCreatedItem(second)
        try pane.revealFiles([file])
        waitUntil { pane.selectedURLs == [file] }
        expect(!(window.firstResponder is NSTextView), "external reveal supersedes pending new-item naming")
        try pane.revealFiles([hidden])
        waitUntil { pane.selectedURLs == [hidden] }
        expect(!pane.showsHidden, "explicit hidden-file reveal preserves the pane hidden-item preference")
        pane.refresh()
        waitUntil { pane.selectedURLs == [hidden] }
        expect(pane.selectedURLs == [hidden], "activation refresh retains explicitly revealed hidden files")

        let link = root.appendingPathComponent("Folder Link")
        try fm.createSymbolicLink(at: link, withDestinationURL: source)
        let linkedFile = link.appendingPathComponent(file.lastPathComponent)
        try pane.revealFiles([linkedFile])
        waitUntil { pane.selectedURLs == [linkedFile] }
        expect(pane.currentDirectory.path == link.path, "reveal preserves the logical symlink path")

        for urls in [[source.appendingPathComponent("missing.pdf")],
                     [file, other.appendingPathComponent("missing.txt")],
                     [URL(string: "https://example.com/file.pdf")!], []] {
            do {
                try pane.revealFiles(urls)
                fatalError("invalid request was accepted")
            } catch {
                expect(pane.currentDirectory.path == link.path, "invalid reveal leaves the current location intact")
            }
        }

        try pane.revealFiles([file])
        pane.navigate(to: other)
        waitUntil { pane.currentDirectory.path == other.path && status.stringValue == "0 items" }
        expect(pane.selectedURLs.isEmpty, "a stale listing cannot select files after navigation")
        try pane.revealFiles([source])
        waitUntil { status.stringValue != "Loading…" }
        expect(pane.currentDirectory.path == source.path && table.numberOfRows > 0,
               "opening a folder browses its contents directly")
        print("SUCCESS: \(checks) external reveal checks passed.")
    }
}
