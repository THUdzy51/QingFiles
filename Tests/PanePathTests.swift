import AppKit

@main
struct PanePathTests {
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
        let root = fm.temporaryDirectory.appendingPathComponent("QingFiles-Path-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("中文 空格/Parent Folder/Deep Folder")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let pane = FilePane(directory: nested, title: "Left")
        pane.onActivate = { $0.isActive = true }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 475, height: 250), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = pane.view
        pane.view.frame = NSRect(x: 0, y: 0, width: 475, height: 250)
        pane.view.layoutSubtreeIfNeeded()
        let controls = descendants(pane.view)
        let breadcrumbs = controls.compactMap { $0 as? NSPathControl }.first!
        let field = controls.compactMap { $0 as? NSTextField }.first { $0.placeholderString?.hasPrefix("Enter a path") == true }!
        expect(breadcrumbs.bounds.width >= 250, "breadcrumb control uses the available narrow-pane width")
        expect(field.isHidden && !breadcrumbs.isHiddenOrHasHiddenAncestor, "paths initially use breadcrumb mode")
        expect(breadcrumbs.pathItems.last?.url?.path == nested.path, "last segment represents the displayed folder")
        expect(breadcrumbs.pathItems.dropLast().last?.url?.path == nested.deletingLastPathComponent().path, "available width preserves the nearest parent segment")
        expect(breadcrumbs.pathItems.contains { $0.title == "…" && $0.url == nil }, "narrow paths expose an overflow item")
        expect(breadcrumbs.pathItems.first?.url?.path == "/", "external paths retain the filesystem root")
        pane.focusPath()
        expect(!field.isHidden && field.stringValue == nested.path, "editing exposes the full absolute path")
        let editor = field.currentEditor() as! NSTextView
        expect(editor.selectedRange() == NSRange(location: 0, length: nested.path.utf16.count), "editing selects the entire path")
        editor.string = root.appendingPathComponent("missing folder").path
        field.stringValue = editor.string
        _ = pane.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        expect(pane.currentDirectory.path == nested.path && !field.isHidden, "invalid paths keep the current folder and editor")
        _ = pane.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        expect(pane.currentDirectory.path == nested.path && field.isHidden, "Escape cancels without navigating")
        pane.focusPath()
        let nextEditor = field.currentEditor() as! NSTextView
        let parent = nested.deletingLastPathComponent()
        field.stringValue = parent.path
        nextEditor.string = parent.path
        _ = pane.control(field, textView: nextEditor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        expect(pane.currentDirectory.path == parent.path && field.isHidden, "Return navigates to a Unicode and space-containing path")
        pane.focusPath()
        let blurEditor = field.currentEditor() as! NSTextView
        blurEditor.string = root.path
        field.stringValue = root.path
        _ = window.makeFirstResponder(nil)
        expect(field.isHidden && pane.currentDirectory.path == parent.path, "blur discards unsubmitted input without navigating")
        pane.goBack()
        expect(pane.currentDirectory.path == nested.path, "path navigation adds one history entry")
        pane.goForward()
        expect(pane.currentDirectory.path == parent.path, "forward history restores the submitted path")
        let link = root.appendingPathComponent("Link Folder")
        try fm.createSymbolicLink(at: link, withDestinationURL: parent)
        pane.focusPath()
        let linkEditor = field.currentEditor() as! NSTextView
        field.stringValue = link.path
        linkEditor.string = link.path
        _ = pane.control(field, textView: linkEditor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        expect(pane.currentDirectory.path == link.path, "symlink navigation preserves the entered path spelling")
        expect(breadcrumbs.pathItems.last?.url?.path == link.path, "symlink breadcrumbs retain the logical location")
        pane.navigate(to: URL(fileURLWithPath: "/", isDirectory: true))
        expect(breadcrumbs.pathItems.count == 1 && breadcrumbs.pathItems.first?.url?.path == "/", "root has one clickable segment")
        pane.navigate(to: fm.homeDirectoryForCurrentUser)
        expect(breadcrumbs.pathItems.count == 1 && breadcrumbs.pathItems.first?.title == "~", "home has a compact clickable anchor")
        let point = breadcrumbs.convert(NSPoint(x: breadcrumbs.bounds.maxX - 2, y: breadcrumbs.bounds.midY), to: nil)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        breadcrumbs.mouseDown(with: event)
        expect(!field.isHidden && field.stringValue == fm.homeDirectoryForCurrentUser.path, "unused path space enters full-path editing")
        _ = pane.control(field, textView: field.currentEditor() as! NSTextView, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        pane.view.layoutSubtreeIfNeeded()
        let bar = breadcrumbs.superview!
        let trailingSpace = bar.bounds.maxX - breadcrumbs.frame.maxX
        expect(trailingSpace >= 24, "the path bar reserves empty space for editing long paths")
        let trailingPoint = bar.convert(NSPoint(x: bar.bounds.maxX - 2, y: bar.bounds.midY), to: nil)
        let trailingClick = NSEvent.mouseEvent(with: .leftMouseDown, location: trailingPoint, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        bar.mouseDown(with: trailingClick)
        let trailingEditor = field.currentEditor() as? NSTextView
        expect(trailingEditor?.selectedRange() == NSRange(location: 0, length: fm.homeDirectoryForCurrentUser.path.utf16.count), "clicking the reserved space selects the complete path")
        print("SUCCESS: \(checks) path interaction checks passed.")
    }
}
