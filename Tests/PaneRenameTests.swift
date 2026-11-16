import AppKit

// Keep focus deterministic when the test executable runs behind a terminal.
private final class RenameTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

@main
struct PaneRenameTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
        print("PASS: \(message)")
    }

    static func pump(_ duration: TimeInterval = 0.05) {
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    }

    static func waitUntil(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { pump(0.01) }
        guard condition() else { fatalError("Timed out waiting for inline rename") }
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    static func main() throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("QingFiles-Rename-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        for name in ["notes_V0.3.md", "中文 😀 文档.txt", "README", ".env", "existing.md", "New Document.txt"] {
            try Data("original \(name)".utf8).write(to: root.appendingPathComponent(name))
        }
        try fm.createDirectory(at: root.appendingPathComponent("Folder.v1"), withIntermediateDirectories: false)
        let pane = FilePane(directory: root, title: "Left")
        pane.onActivate = { $0.isActive = true }
        pane.showsHidden = true
        let window = RenameTestWindow(contentRect: NSRect(x: 0, y: 0, width: 475, height: 400),
                                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = pane.view
        pane.view.frame = NSRect(x: 0, y: 0, width: 475, height: 400)
        pane.view.autoresizingMask = [.width, .height]
        pane.view.widthAnchor.constraint(equalToConstant: 475).isActive = true
        pane.activate()
        defer { window.orderOut(nil) }
        let controls = descendants(pane.view)
        let table = controls.compactMap { $0 as? NSTableView }.first!
        let search = controls.compactMap { $0 as? NSSearchField }.first!
        waitUntil { !pane.isLoading && window.isKeyWindow }
        expect(pane.view.bounds.width == 475, "inline naming is exercised at minimum pane width")

        func field(_ name: String) -> (Int, NSTextField) {
            pane.view.layoutSubtreeIfNeeded()
            for row in 0..<table.numberOfRows {
                let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as! NSTableCellView
                if cell.textField?.stringValue == name { return (row, cell.textField!) }
            }
            fatalError("Missing row: \(name)")
        }
        func click(_ name: String, count: Int = 1, modifiers: NSEvent.ModifierFlags = [], icon: Bool = false) {
            let (row, label) = field(name)
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            window.makeFirstResponder(table)
            let point = label.convert(NSPoint(x: icon ? -20 : 8, y: label.bounds.midY), to: table)
            pane.filenameClickEnded(at: point, clickCount: count, modifiers: modifiers)
        }
        func begin(_ name: String) -> (NSTextField, NSTextView) {
            click(name)
            waitUntil { field(name).1.currentEditor() != nil }
            let label = field(name).1
            return (label, label.currentEditor() as! NSTextView)
        }
        func cancel(_ label: NSTextField, _ editor: NSTextView) {
            _ = pane.control(label, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
            waitUntil { !pane.isLoading && label.currentEditor() == nil }
        }
        func replace(_ editor: NSTextView, with name: String) {
            editor.insertText(name, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        }
        func commit(_ label: NSTextField, _ editor: NSTextView, name: String) {
            replace(editor, with: name)
            _ = pane.control(label, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
            waitUntil { !pane.isLoading && label.currentEditor() == nil }
            pump()
            waitUntil { !pane.isLoading }
        }

        click("notes_V0.3.md", icon: true)
        pump(NSEvent.doubleClickInterval + 0.05)
        expect(!(window.firstResponder is NSTextView), "clicking an icon only selects the row")
        for flags: NSEvent.ModifierFlags in [.command, .shift, .option, .control] {
            click("notes_V0.3.md", modifiers: flags)
            pump(NSEvent.doubleClickInterval + 0.05)
            expect(!(window.firstResponder is NSTextView), "modifier clicks do not start renaming")
        }
        click("notes_V0.3.md", count: 2)
        pump(NSEvent.doubleClickInterval + 0.05)
        expect(!(window.firstResponder is NSTextView), "double-click completion does not schedule naming")
        click("notes_V0.3.md")
        let otherRow = field("README").0
        table.selectRowIndexes(IndexSet(integer: otherRow), byExtendingSelection: false)
        pump(NSEvent.doubleClickInterval + 0.05)
        expect(!(window.firstResponder is NSTextView), "changing selection cancels delayed naming")
        pane.allowsInlineRename = { false }
        click("notes_V0.3.md")
        pump(NSEvent.doubleClickInterval + 0.05)
        expect(!(window.firstResponder is NSTextView), "busy file operations can block inline naming")
        pane.allowsInlineRename = nil
        click("notes_V0.3.md")
        pane.focusSearch()
        pump(NSEvent.doubleClickInterval + 0.05)
        expect(search.currentEditor() != nil, "pending naming cannot steal search focus")

        let (label, editor) = begin("notes_V0.3.md")
        expect(editor.string == "notes_V0.3.md" && editor.selectedRange() == NSRange(location: 0, length: 10),
               "a filename click shows the extension and selects only the stem")
        editor.insertText("z renamed", replacementRange: editor.selectedRange())
        expect(editor.string == "z renamed.md", "typing over the stem preserves its extension")
        commit(label, editor, name: editor.string)
        expect(pane.selectedURLs.map(\.lastPathComponent) == ["z renamed.md"], "renamed items stay selected after sorting")
        let renamedContents = try Data(contentsOf: root.appendingPathComponent("z renamed.md"))
        expect(renamedContents == Data("original notes_V0.3.md".utf8),
               "renaming preserves document contents")

        for name in ["中文 😀 文档.txt", "README", ".env", "Folder.v1"] {
            let (label, editor) = begin(name)
            let stem = name == "中文 😀 文档.txt" ? "中文 😀 文档" : name
            expect(editor.selectedRange() == NSRange(location: 0, length: stem.utf16.count),
                   "stem selection handles Unicode, extensionless names, dotfiles, and dotted folders")
            replace(editor, with: "cancelled")
            cancel(label, editor)
            expect(fm.fileExists(atPath: root.appendingPathComponent(name).path), "Escape preserves the original item")
        }

        var (activeLabel, activeEditor) = begin("README")
        replace(activeEditor, with: "read me")
        pane.view.layoutSubtreeIfNeeded()
        let header = activeLabel.convert(NSPoint(x: 0, y: -100), to: nil)
        expect(pane.dismissEditors(clickAt: header), "blank-header clicks commit a valid filename")
        pump()
        waitUntil { !pane.isLoading }
        expect(pane.selectedURLs.map(\.lastPathComponent) == ["read me"], "outside-click rename remains selected")

        (activeLabel, activeEditor) = begin("read me")
        replace(activeEditor, with: "renamed readme")
        _ = pane.dismissEditors(clickAt: header)
        click("existing.md")
        pump()
        waitUntil { field("existing.md").1.currentEditor() != nil }
        expect(pane.selectedURLs.map(\.lastPathComponent) == ["existing.md"],
               "clicking another filename commits, preserves the new selection, and starts its editor")
        let nextLabel = field("existing.md").1
        cancel(nextLabel, nextLabel.currentEditor() as! NSTextView)

        (activeLabel, activeEditor) = begin("z renamed.md")
        replace(activeEditor, with: "existing.md")
        expect(!window.makeFirstResponder(table), "name collisions keep the inline editor active")
        expect(fm.fileExists(atPath: root.appendingPathComponent("z renamed.md").path), "collision preserves the source")
        let destinationContents = try Data(contentsOf: root.appendingPathComponent("existing.md"))
        expect(destinationContents == Data("original existing.md".utf8),
               "collision preserves the destination")
        func dismissError() {
            guard let sheet = window.attachedSheet else { fatalError("Missing rename error") }
            window.endSheet(sheet)
            sheet.orderOut(nil)
            pump()
        }
        dismissError()
        expect(activeLabel.currentEditor() === activeEditor && fm.fileExists(atPath: root.appendingPathComponent("z renamed.md").path),
               "dismissing an error does not silently commit the rejected attempt")
        for invalid in ["", ".", "..", "bad/name", "bad\0name"] {
            replace(activeEditor, with: invalid)
            expect(!pane.dismissEditors(clickAt: header), "invalid names block outside clicks and allow retry")
            dismissError()
        }
        cancel(activeLabel, activeEditor)

        // A real filesystem permission failure must also leave the source intact.
        (activeLabel, activeEditor) = begin("z renamed.md")
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        replace(activeEditor, with: "permission.md")
        let blocked = !window.makeFirstResponder(table)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        expect(blocked, "read-only folders keep naming active on failure")
        dismissError()
        commit(activeLabel, activeEditor, name: "retried.md")
        expect(fm.fileExists(atPath: root.appendingPathComponent("retried.md").path), "a failed rename can be retried")

        pane.focusSearch()
        search.stringValue = "retried"
        _ = search.sendAction(search.action!, to: search.target)
        (activeLabel, activeEditor) = begin("retried.md")
        commit(activeLabel, activeEditor, name: "unfiltered.md")
        expect(search.stringValue.isEmpty && pane.selectedURLs.map(\.lastPathComponent) == ["unfiltered.md"],
               "renaming beyond the current filter clears it to keep the item visible")

        for (old, new) in [(".env", ".settings"), ("Folder.v1", "Folder v2"), ("中文 😀 文档.txt", "更新 文档.txt")] {
            (activeLabel, activeEditor) = begin(old)
            commit(activeLabel, activeEditor, name: new)
            expect(pane.selectedURLs.map(\.lastPathComponent) == [new] && fm.fileExists(atPath: root.appendingPathComponent(new).path),
                   "dotfiles, folders, and Unicode files rename in place and stay selected")
        }

        pane.revealCreatedItem(root.appendingPathComponent("New Document.txt"))
        waitUntil { window.firstResponder is NSTextView && !pane.isLoading }
        let newLabel = field("New Document.txt").1
        let newEditor = newLabel.currentEditor() as! NSTextView
        expect(newEditor.string == "New Document.txt" && newEditor.selectedRange().length == 12,
               "new documents share stem-only selection with a visible extension")
        cancel(newLabel, newEditor)

        for index in 0..<45 { try Data().write(to: root.appendingPathComponent("row-\(index).txt")) }
        pane.refresh()
        waitUntil { !pane.isLoading }
        (activeLabel, activeEditor) = begin("unfiltered.md")
        commit(activeLabel, activeEditor, name: "a renamed.md")
        expect(table.rows(in: table.visibleRect).contains(table.selectedRow),
               "re-sorting a long listing scrolls the renamed selection into view")

        print("SUCCESS: \(checks) inline rename checks passed.")
    }
}
