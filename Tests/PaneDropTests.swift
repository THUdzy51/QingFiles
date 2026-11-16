import AppKit

private final class FileDrag: NSObject, NSDraggingInfo {
    let draggingPasteboard = NSPasteboard.withUniqueName()
    let draggingSource: Any?
    let draggingDestinationWindow: NSWindow?
    let draggingSourceOperationMask: NSDragOperation
    let draggingLocation = NSPoint.zero
    let draggedImageLocation = NSPoint.zero
    let draggedImage: NSImage? = nil
    let draggingSequenceNumber = 0
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    let springLoadingHighlight: NSSpringLoadingHighlight = .none

    init(_ files: [URL], source: NSTableView, mask: NSDragOperation) {
        draggingSource = source
        draggingDestinationWindow = source.window
        draggingSourceOperationMask = mask
        super.init()
        precondition(draggingPasteboard.writeObjects(files.map { $0 as NSURL }))
    }

    deinit { draggingPasteboard.releaseGlobally() }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

@main
struct PaneDropTests {
    static func main() throws {
        _ = NSApplication.shared
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("QingFiles-DropTests-\(UUID())")
        let from = root.appendingPathComponent("Source")
        let to = root.appendingPathComponent("Destination")
        let child = to.appendingPathComponent("Subfolder")
        try fm.createDirectory(at: from, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: child, withIntermediateDirectories: true)
        let file = from.appendingPathComponent("档案 file.txt")
        let copy = from.appendingPathComponent("copy.txt")
        let original = Data("contents".utf8)
        try original.write(to: file)
        try original.write(to: copy)

        let left = FilePane(directory: from, title: "Left")
        let right = FilePane(directory: to, title: "Right")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 950, height: 450),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let row = NSStackView(views: [left.view, right.view])
        row.distribution = .fillEqually
        window.contentView = row
        row.layoutSubtreeIfNeeded()
        let source = table(in: left.view)!
        let destination = table(in: right.view)!
        let deadline = Date().addingTimeInterval(5)
        while (left.isLoading || right.isLoading) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(!left.isLoading && destination.numberOfRows == 1)
        var report = FileOperationReport()
        right.allowsFileDrop = { true }
        right.onFileDrop = { report = FileService.transfer($0, to: $1, mode: $2) }

        let move = FileDrag([file], source: source, mask: [.move])
        precondition(right.tableView(destination, validateDrop: move, proposedRow: 1, proposedDropOperation: .above) == .move)
        precondition(right.tableView(destination, acceptDrop: move, row: -1, dropOperation: .on))
        precondition(report.succeeded.count == 1 && !fm.fileExists(atPath: file.path))
        precondition(fm.fileExists(atPath: to.appendingPathComponent(file.lastPathComponent).path))

        let copying = FileDrag([copy], source: source, mask: [.copy])
        precondition(right.tableView(destination, validateDrop: copying, proposedRow: 0, proposedDropOperation: .on) == .copy)
        precondition(right.tableView(destination, acceptDrop: copying, row: 0, dropOperation: .on))
        precondition(report.succeeded.count == 1 && fm.fileExists(atPath: copy.path))
        let copied = try Data(contentsOf: child.appendingPathComponent(copy.lastPathComponent))
        precondition(copied == original)

        let selfDrop = FileDrag([child], source: destination, mask: [.move])
        precondition(right.tableView(destination, validateDrop: selfDrop, proposedRow: 0, proposedDropOperation: .on).isEmpty)
        right.allowsFileDrop = { false }
        precondition(!right.tableView(destination, acceptDrop: copying, row: 0, dropOperation: .on))
        print("SUCCESS: cross-pane moves, folder-row copies, self-drop rejection, and operation gating.")
    }

    private static func table(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { table(in: $0) }.first
    }
}
