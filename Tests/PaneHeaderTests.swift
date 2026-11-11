import AppKit

/// Run with ./test-ui.sh on a Mac with a logged-in desktop session.
@main
struct PaneHeaderTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
        print("PASS: \(message)")
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    static func main() throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("QingFiles-Header-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Fixture")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        let pane = FilePane(directory: folder, title: "Left")
        pane.onActivate = { $0.isActive = true }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 475, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = pane.view
        pane.view.frame = NSRect(x: 0, y: 0, width: 475, height: 200)
        pane.view.layoutSubtreeIfNeeded()
        let controls = descendants(pane.view)
        let fields = controls.compactMap { $0 as? NSTextField }
        let path = fields.first { $0.placeholderString?.hasPrefix("Enter a path") == true }!
        let search = fields.compactMap { $0 as? NSSearchField }.first!
        let buttons = controls.compactMap { $0 as? NSButton }
        let toggle = buttons.first { $0.toolTip == "Search Current Folder · ⌘F" }!
        expect(!fields.contains { $0.stringValue == "Left" }, "positional label is absent")
        expect(fields.contains { $0.stringValue == "Fixture" }, "folder title remains")
        expect(search.isHidden && !path.isHidden, "search starts collapsed")
        let pathFrame = pane.view.convert(path.bounds, from: path)
        for name in ["Back", "Forward", "Parent Folder", "Refresh"] {
            let button = buttons.first { $0.toolTip == name }!
            let frame = pane.view.convert(button.bounds, from: button)
            expect(frame.maxX <= pathFrame.minX && abs(frame.midY - pathFrame.midY) < 4, "\(name) sits to the left of the path")
        }
        toggle.performClick(nil)
        pane.view.layoutSubtreeIfNeeded()
        expect(!search.isHidden && path.isHidden, "search button expands in the narrow path area")
        expect(search.frame.width > 100, "search remains usable at minimum pane width")
        search.stringValue = "retained query"
        _ = window.makeFirstResponder(nil)
        expect(!search.isHidden && search.stringValue == "retained query", "blur keeps the filter visible")
        _ = pane.control(search, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        expect(search.isHidden && search.stringValue.isEmpty && !path.isHidden, "Escape clears and collapses search")
        pane.focusSearch()
        expect(!search.isHidden, "Command-F entry point expands search")
        search.stringValue = "old query"
        pane.goUp()
        expect(search.isHidden && search.stringValue.isEmpty && pane.currentDirectory.path == root.path, "navigation resets search and updates the directory")
        pane.focusSearch()
        search.stringValue = "query"
        pane.focusPath()
        expect(search.isHidden && search.stringValue.isEmpty && !path.isHidden, "Command-L restores an unfiltered path editor")
        window.setContentSize(NSSize(width: 800, height: 300))
        pane.view.layoutSubtreeIfNeeded()
        pane.focusSearch()
        pane.view.layoutSubtreeIfNeeded()
        expect(!path.isHidden && !search.isHidden, "wide panes share the row between path and search")
        let searchFrame = pane.view.convert(search.bounds, from: search)
        expect(searchFrame.maxX <= pane.view.bounds.maxX, "wide search stays inside the pane")
        print("SUCCESS: \(checks) pane header checks passed.")
    }
}
