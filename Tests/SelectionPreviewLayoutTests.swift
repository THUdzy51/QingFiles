import AppKit
import QuickLookUI
import UniformTypeIdentifiers

@main
struct SelectionPreviewLayoutTests {
    static func main() throws {
        _ = NSApplication.shared
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("QingFiles-PreviewLayout-\(UUID())", isDirectory: true)
        let nested = directory.appendingPathComponent("Nested", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 900, bitsPerSample: 8,
                                     samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: nested.appendingPathComponent("sample.png"))
        for index in 0..<150 {
            try Data("Fixture".utf8).write(to: nested.appendingPathComponent("File \(index).txt"))
        }

        let filePane = FilePane(directory: directory, title: "Left")
        let preview = SelectionPreviewPane()
        let row = NSStackView(views: [filePane.view, preview])
        row.distribution = .fillEqually
        row.alignment = .height
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 950, height: 490),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = row

        let fileHeader = filePane.view.subviews.compactMap { $0 as? PaneHeaderView }.first!
        let previewHeader = preview.subviews.compactMap { $0 as? PaneHeaderView }.first!
        let title = previewHeader.subviews.compactMap { $0 as? NSTextField }.first!
        let controls = previewHeader.subviews.compactMap { $0 as? NSStackView }.first!
        let mode = controls.arrangedSubviews.compactMap { $0 as? NSSegmentedControl }.first!
        let fileTable = descendants(filePane.view).compactMap { $0 as? NSTableView }.first!
        let outline = descendants(preview).compactMap { $0 as? NSOutlineView }.first!
        let scroll = outline.enclosingScrollView!
        let picture = descendants(preview).compactMap { $0 as? NSImageView }.first!

        func wait(_ until: () -> Bool) {
            let deadline = Date().addingTimeInterval(5)
            while !until() && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            precondition(until(), "Timed out waiting for the preview")
        }

        func verifyHeaders() {
            row.layoutSubtreeIfNeeded()
            for type in [NSTextField.self as NSView.Type, NSStackView.self, NSBox.self] {
                let left = fileHeader.subviews.first { $0.isKind(of: type) }!
                let right = previewHeader.subviews.first { $0.isKind(of: type) }!
                let leftRect = row.convert(left.bounds, from: left)
                let rightRect = row.convert(right.bounds, from: right)
                precondition(abs(leftRect.minY - rightRect.minY) < 0.5 &&
                             abs(leftRect.maxY - rightRect.maxY) < 0.5, "Pane headers drifted out of alignment")
            }
        }

        func verifyListHeaders() {
            let left = fileTable.headerView!
            let right = outline.headerView!
            let leftRect = row.convert(left.bounds, from: left)
            let rightRect = row.convert(right.bounds, from: right)
            precondition(leftRect.height > 0 && abs(leftRect.minY - rightRect.minY) < 0.5 &&
                         abs(leftRect.maxY - rightRect.maxY) < 0.5, "List column headings are misaligned")
            let firstRow = row.convert(outline.rect(ofRow: 0), from: outline)
            precondition(firstRow.maxY <= rightRect.minY + 0.5, "The column heading covers the first row")
        }

        verifyHeaders()
        precondition(title.stringValue == "Preview" && mode.isHidden)
        preview.show(directory, includeHidden: false)
        verifyHeaders()
        wait { !mode.isHidden && !filePane.isLoading }
        verifyHeaders()
        verifyListHeaders()
        precondition(!mode.isHidden && outline.rowHeight == fileTable.rowHeight)
        let folder = preview.outlineView(outline, viewFor: outline.tableColumns[0], item: outline.item(atRow: 0)!) as? NSTableCellView
        let systemIcon = NSWorkspace.shared.icon(forFile: nested.path)
        precondition(folder?.textField?.stringValue == "Nested",
                     "Unexpected first row: \(folder?.textField?.stringValue ?? "<empty>"), \(outline.numberOfRows) total")
        guard let previewIcon = folder?.imageView?.image else { preconditionFailure("The folder icon was missing") }
        precondition(previewIcon.isTemplate == systemIcon.isTemplate && previewIcon.size == systemIcon.size,
                     "The preview did not use the native folder icon")

        outline.expandItem(outline.item(atRow: 0))
        precondition(outline.numberOfRows == 152)
        row.layoutSubtreeIfNeeded()
        let originalWindow = window.frame
        let fullListFrame = scroll.frame
        precondition(picture.isHiddenOrHasHiddenAncestor && fullListFrame.minY == 0, "The empty preview reserves space")
        outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        row.layoutSubtreeIfNeeded()
        precondition(picture.isHiddenOrHasHiddenAncestor && scroll.frame == fullListFrame, "A folder opened the file preview")

        outline.scrollRowToVisible(100)
        row.layoutSubtreeIfNeeded()
        let beforeOpening = scroll.contentView.bounds.origin
        outline.selectRowIndexes(IndexSet(integer: 100), byExtendingSelection: false)
        wait { descendants(preview).contains { $0 is QLPreviewView && !$0.isHiddenOrHasHiddenAncestor } }
        row.layoutSubtreeIfNeeded()
        let originalList = scroll.frame
        let originalScroll = scroll.contentView.bounds.origin
        let originalPreview = row.convert(picture.bounds, from: picture)
        precondition(originalList.height < fullListFrame.height && originalPreview.height > 0, "The file preview did not open")
        precondition(originalScroll.y >= beforeOpening.y && originalScroll.y - beforeOpening.y <= fullListFrame.height - originalList.height + 1,
                     "The preview scrolled more than needed to keep the file visible")
        precondition(outline.visibleRect.contains(outline.rect(ofRow: 100)), "The selected file was scrolled out of view")

        func verifyStablePreview() {
            row.layoutSubtreeIfNeeded()
            precondition(window.frame == originalWindow, "Selecting a file resized the window")
            precondition(scroll.frame == originalList, "Selecting a file resized the list")
            precondition(scroll.contentView.bounds.origin == originalScroll, "Selecting a file scrolled the list")
            precondition(row.convert(picture.bounds, from: picture) == originalPreview, "The preview viewport resized")
        }
        verifyStablePreview()
        outline.selectRowIndexes(IndexSet(integer: 99), byExtendingSelection: false)
        verifyStablePreview()
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                      charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        outline.keyDown(with: escape)
        row.layoutSubtreeIfNeeded()
        precondition(outline.selectedRow == -1 && picture.isHiddenOrHasHiddenAncestor && scroll.frame == fullListFrame,
                     "Escape did not restore the full list")
        precondition(scroll.contentView.bounds.origin == originalScroll && window.frame == originalWindow)

        mode.selectedSegment = 1
        precondition(NSApp.sendAction(mode.action!, to: mode.target, from: mode), "Could not switch to Media")
        verifyHeaders()
        precondition(outline.rowHeight == 50, "Media did not use thumbnail row heights")
        let hasMediaTypes = UTType(filenameExtension: "png")?.conforms(to: .image) == true
        if hasMediaTypes {
            precondition(outline.numberOfRows == 1, "The media list did not show the image")
            verifyListHeaders()
            let mediaListFrame = scroll.frame
            outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            wait { picture.image != nil }
            row.layoutSubtreeIfNeeded()
            precondition(scroll.frame.height < mediaListFrame.height && window.frame == originalWindow)
            precondition(picture.imageScaling == .scaleProportionallyUpOrDown)
            precondition(picture.image?.size == NSSize(width: 1600, height: 800), "Preview scaling changed the image aspect ratio")
            precondition(!picture.isHidden && picture.frame == picture.superview?.bounds, "The image escaped its fixed viewport")
            outline.deselectAll(nil)
            row.layoutSubtreeIfNeeded()
            precondition(picture.isHiddenOrHasHiddenAncestor && scroll.frame == mediaListFrame)
        } else {
            print("Launch Services image types unavailable in this session. Checked Media title and controls.")
        }
        window.setContentSize(NSSize(width: 1280, height: 650))
        verifyHeaders()
        if hasMediaTypes { verifyListHeaders() }

        let archive = directory.appendingPathComponent("sample.zip")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        tar.currentDirectoryURL = nested
        tar.arguments = ["--format", "zip", "-cf", archive.path, "File 0.txt"]
        try tar.run()
        tar.waitUntilExit()
        precondition(tar.terminationStatus == 0)
        mode.selectedSegment = 0
        preview.show(archive, includeHidden: false)
        wait { !mode.isHidden && outline.numberOfRows == 1 }
        row.layoutSubtreeIfNeeded()
        let fullArchiveList = scroll.frame
        precondition(picture.isHiddenOrHasHiddenAncestor)
        outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        wait { descendants(preview).contains { $0 is QLPreviewView && !$0.isHiddenOrHasHiddenAncestor } }
        row.layoutSubtreeIfNeeded()
        precondition(scroll.frame.height < fullArchiveList.height)
        outline.deselectAll(nil)
        row.layoutSubtreeIfNeeded()
        precondition(scroll.frame == fullArchiveList && picture.isHiddenOrHasHiddenAncestor)
        print("SUCCESS: the list fills the pane until a file is selected, selections stay visible, and Escape restores the full list.")
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
