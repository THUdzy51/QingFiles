import AppKit

@main
struct PaneOpenWithTests {
    static func main() throws {
        _ = NSApplication.shared
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("QingFiles-OpenWith-\(UUID())", isDirectory: true)
        let folder = directory.appendingPathComponent("Folder", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let files = ["First file.txt", "第二个文件.txt"].map { directory.appendingPathComponent($0) }
        for file in files { try Data("Fixture".utf8).write(to: file) }

        let pane = FilePane(directory: directory, title: "Left")
        let table = descendants(pane.view).compactMap { $0 as? NSTableView }.first!
        let menu = table.menu!
        let openWith = menu.item(withTitle: "Open With")!
        let apps = openWith.submenu!
        let deadline = Date().addingTimeInterval(5)
        while pane.isLoading && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(!pane.isLoading && table.numberOfRows == 3)

        pane.menuNeedsUpdate(menu)
        precondition(openWith.isHidden, "Open With was shown with no selection")
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        pane.menuNeedsUpdate(menu)
        precondition(openWith.isHidden, "Open With was shown for an ordinary folder")

        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        pane.menuNeedsUpdate(menu)
        precondition(!openWith.isHidden, "Open With was missing for a file")
        pane.menuNeedsUpdate(apps)
        precondition(apps.items.last?.title == "Other…", "The application chooser was missing")
        let selected = pane.selectedURLs[0]
        if let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: selected) {
            let name = fm.displayName(atPath: defaultApp.path)
            precondition(apps.items.first?.title == "\(name) (Default)", "The default app was not shown first")
        }

        table.selectRowIndexes(IndexSet(integersIn: 1..<3), byExtendingSelection: false)
        pane.menuNeedsUpdate(menu)
        pane.menuNeedsUpdate(apps)
        precondition(!openWith.isHidden && apps.items.last?.title == "Other…")
        let common = Set(NSWorkspace.shared.urlsForApplications(toOpen: files[0])).intersection(NSWorkspace.shared.urlsForApplications(toOpen: files[1]))
        let shown = Set(apps.items.compactMap(\.toolTip))
        precondition(shown == Set(common.map(\.standardizedFileURL.path)), "The application list did not match the selection")

        table.selectRowIndexes(IndexSet(integersIn: 0..<2), byExtendingSelection: false)
        pane.menuNeedsUpdate(menu)
        precondition(openWith.isHidden, "Open With was shown for a selection containing an ordinary folder")
        pane.refresh()
        pane.menuNeedsUpdate(menu)
        precondition(openWith.isHidden, "A stale selection exposed Open With while the pane reloaded")
        print("SUCCESS: Open With lists compatible applications and Other for selected local files.")
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
