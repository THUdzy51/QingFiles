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
        let window = FileBrowserWindow(contentRect: NSRect(x: 0, y: 0, width: 475, height: 250), styleMask: [.titled], backing: .buffered, defer: false)
        window.onMouseDown = { [weak pane] point in pane?.dismissPathEditor(clickAt: point) }
        window.isReleasedWhenClosed = false
        window.contentView = pane.view
        pane.view.frame = NSRect(x: 0, y: 0, width: 475, height: 250)
        pane.view.layoutSubtreeIfNeeded()
        let controls = descendants(pane.view)
        let bar = controls.first { $0.toolTip == "Click empty space to edit the path, or press ⌘L" }!
        let breadcrumbs = bar.subviews.compactMap { $0 as? NSStackView }.first!
        func names() -> [NSButton] {
            breadcrumbs.arrangedSubviews.compactMap { $0 as? NSButton }
                .filter { $0.action == NSSelectorFromString("breadcrumbClicked:") }
        }
        let field = controls.compactMap { $0 as? NSTextField }.first { $0.placeholderString?.hasPrefix("Enter a path") == true }!
        expect(bar.bounds.width >= 250, "breadcrumb control uses the available narrow-pane width")
        expect(field.isHidden && !bar.isHiddenOrHasHiddenAncestor, "paths initially use breadcrumb mode")
        expect(names().last?.toolTip == nested.path, "last segment represents the displayed folder")
        expect(names().dropLast().last?.toolTip == nested.deletingLastPathComponent().path, "available width preserves the nearest parent segment")
        expect(breadcrumbs.arrangedSubviews.compactMap { $0 as? NSButton }.contains { $0.title == "…" }, "narrow paths expose an overflow item")
        expect(names().first?.toolTip == "/", "external paths retain the filesystem root")
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
        pane.focusPath()
        let outsideEditor = field.currentEditor() as! NSTextView
        outsideEditor.string = root.path
        field.stringValue = root.path
        pane.view.layoutSubtreeIfNeeded()
        let headerPoint = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.maxY + 12), to: nil)
        let headerClick = NSEvent.mouseEvent(with: .leftMouseDown, location: headerPoint, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        window.sendEvent(headerClick)
        expect(field.isHidden && !bar.isHidden && pane.currentDirectory.path == parent.path,
               "clicking blank header space restores breadcrumbs and discards unsubmitted input")
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
        expect(names().last?.toolTip == link.path, "symlink breadcrumbs retain the logical location")
        pane.navigate(to: URL(fileURLWithPath: "/", isDirectory: true))
        expect(names().count == 1 && names().first?.toolTip == "/", "root has one clickable segment")
        pane.navigate(to: fm.homeDirectoryForCurrentUser)
        expect(names().count == 1 && names().first?.title == "~", "home has a compact clickable anchor")
        let arrow = breadcrumbs.arrangedSubviews.compactMap { $0 as? NSButton }.last!
        expect(arrow.action == NSSelectorFromString("showSubfolders:") &&
               names()[0].action != arrow.action, "directory name and arrow have separate actions")
        let point = bar.convert(NSPoint(x: breadcrumbs.frame.maxX + 2, y: bar.bounds.midY), to: nil)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        bar.mouseDown(with: event)
        expect(!field.isHidden && field.stringValue == fm.homeDirectoryForCurrentUser.path, "unused path space enters full-path editing")
        _ = pane.control(field, textView: field.currentEditor() as! NSTextView, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        pane.view.layoutSubtreeIfNeeded()
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
