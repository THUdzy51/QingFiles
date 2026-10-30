import AppKit
import Foundation

private final class PaneContainerView: NSView {
    var onActivate: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        onActivate?()
        super.mouseDown(with: event)
    }
}

private final class FileListTable: NSTableView {
    weak var pane: FilePane?

    override func mouseDown(with event: NSEvent) {
        pane?.activate()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        pane?.activate()
        let clicked = row(at: convert(event.locationInWindow, from: nil))
        if clicked >= 0 && !selectedRowIndexes.contains(clicked) {
            selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        } else if clicked < 0 {
            deselectAll(nil)
        }
        super.rightMouseDown(with: event)
    }

    @objc func copy(_ sender: Any?) { pane?.performAction("copy") }
    @objc func cut(_ sender: Any?) { pane?.performAction("cut") }
    @objc func paste(_ sender: Any?) { pane?.performAction("paste") }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) || item.action == #selector(cut(_:)) {
            return !(pane?.selectedURLs.isEmpty ?? true)
        }
        if item.action == #selector(paste(_:)) { return true }
        return true
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags.contains(.command) {
            switch key {
            case "c": pane?.performAction(flags.contains(.option) ? "copyToOther" : (flags.contains(.shift) ? "copyPath" : "copy")); return
            case "x": pane?.performAction("cut"); return
            case "v": pane?.performAction(flags.contains(.option) ? "pasteMove" : "paste"); return
            case "r": if flags.contains(.shift) { pane?.performAction("rename") } else { pane?.refresh() }; return
            case "f": pane?.focusSearch(); return
            default: break
            }
            if event.keyCode == 126 { pane?.goUp(); return }
            if event.keyCode == 125 { pane?.openSelection(); return }
            if event.keyCode == 51 { pane?.performAction("trash"); return }
        }
        if !flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option) {
            if event.keyCode == 49 { pane?.performAction("preview"); return }
            if event.keyCode == 36 || event.keyCode == 76 { pane?.openSelection(); return }
            if event.keyCode == 51 { pane?.goUp(); return }
        }
        super.keyDown(with: event)
    }
}

/// An independent browser pane. Filesystem mutations are deliberately delegated to the owner.
final class FilePane: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate {
    private(set) var currentDirectory: URL
    var isLoading: Bool { loading }
    let paneTitle: String

    var onActivate: ((FilePane) -> Void)?
    var onDirectoryChanged: ((FilePane) -> Void)?
    var onSelectionChanged: ((FilePane) -> Void)?
    var onAction: ((FilePane, String) -> Void)?

    var isActive = false {
        didSet { if isViewLoaded { updateActiveAppearance() } }
    }
    var showsHidden = false {
        didSet { if oldValue != showsHidden && isViewLoaded { refresh() } }
    }
    var selectedURLs: [URL] {
        guard isViewLoaded, !loading else { return [] }
        return table.selectedRowIndexes.compactMap { index in
            visibleEntries.indices.contains(index) ? visibleEntries[index].url : nil
        }
    }

    private let accent = NSColor(red: 0.12, green: 0.53, blue: 0.48, alpha: 1)
    private let table = FileListTable()
    private let folderLabel = NSTextField(labelWithString: "")
    private let paneLabel = NSTextField(labelWithString: "")
    private let pathField = NSTextField(string: "")
    private let searchField = NSSearchField()
    private let statusLabel = NSTextField(labelWithString: "Loading…")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var entries: [FileEntry] = []
    private var visibleEntries: [FileEntry] = []
    private var backHistory: [URL] = []
    private var forwardHistory: [URL] = []
    private var requestGeneration = 0
    private var loadError: String?
    private var loading = false
    private var sortKey = "name"
    private var sortAscending = true
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    init(directory: URL, title: String) {
        self.currentDirectory = directory.standardizedFileURL
        self.paneTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let root = PaneContainerView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        root.onActivate = { [weak self] in self?.activate() }
        view = root

        paneLabel.stringValue = paneTitle
        paneLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        paneLabel.textColor = .secondaryLabelColor
        paneLabel.setContentHuggingPriority(.required, for: .horizontal)
        folderLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let titleStack = NSStackView(views: [paneLabel, folderLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3
        backButton = iconButton("chevron.left", tooltip: "Back", action: #selector(backClicked))
        forwardButton = iconButton("chevron.right", tooltip: "Forward", action: #selector(forwardClicked))
        let upButton = iconButton("arrow.up", tooltip: "Parent Folder", action: #selector(upClicked))
        let refreshButton = iconButton("arrow.clockwise", tooltip: "Refresh", action: #selector(refreshClicked))
        let navigation = NSStackView(views: [backButton, forwardButton, upButton, refreshButton])
        navigation.spacing = 1
        let header = NSStackView(views: [titleStack, navigation])
        header.alignment = .centerY
        header.spacing = 6
        titleStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        pathField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.usesSingleLineMode = true
        pathField.isEditable = true
        pathField.isSelectable = true
        pathField.bezelStyle = .roundedBezel
        pathField.focusRingType = .none
        pathField.placeholderString = "Enter a path, e.g. / or ~/Documents"
        pathField.target = self
        pathField.action = #selector(pathSubmitted)
        pathField.delegate = self
        pathField.toolTip = "Enter a path and press Return; ~ represents your home folder"

        searchField.placeholderString = "Search Current Folder"
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.focusRingType = .none
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.delegate = self

        table.pane = self
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 35
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .controlBackgroundColor
        table.selectionHighlightStyle = .regular
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.style = .plain
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)

        let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        name.title = "Name"
        name.width = 240
        name.minWidth = 115
        name.resizingMask = [.autoresizingMask, .userResizingMask]
        name.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        table.addTableColumn(name)
        let modified = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("modified"))
        modified.title = "Modified"
        modified.width = 92
        modified.minWidth = 78
        modified.maxWidth = 150
        modified.resizingMask = [.userResizingMask]
        modified.sortDescriptorPrototype = NSSortDescriptor(key: "modified", ascending: false)
        table.addTableColumn(modified)
        let size = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        size.title = "Size"
        size.width = 72
        size.minWidth = 64
        size.maxWidth = 120
        size.resizingMask = [.userResizingMask]
        size.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: false)
        table.addTableColumn(size)
        table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        table.menu = makeContextMenu()

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .controlBackgroundColor
        scroll.documentView = table

        emptyLabel.alignment = .center
        emptyLabel.font = NSFont.systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isSelectable = true
        emptyLabel.isHidden = true

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        let footer = NSStackView(views: [statusLabel, spinner])
        footer.alignment = .centerY
        footer.spacing = 8
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let divider = NSBox()
        divider.boxType = .separator
        for subview in [header, pathField, searchField, divider, scroll, emptyLabel, footer] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 13),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            header.heightAnchor.constraint(equalToConstant: 36),
            pathField.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 9),
            pathField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            pathField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            pathField.heightAnchor.constraint(equalToConstant: 27),
            searchField.topAnchor.constraint(equalTo: pathField.bottomAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: pathField.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: pathField.trailingAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 25),
            divider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 5),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -5),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -4),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -9),
            footer.heightAnchor.constraint(equalToConstant: 18),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: scroll.widthAnchor, constant: -40)
        ])
        updateDirectoryChrome()
        updateActiveAppearance()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refresh()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // The name column absorbs width changes; date and size remain readable in four-pane mode.
        if let name = table.tableColumns.first {
            let others = table.tableColumns.dropFirst().reduce(CGFloat(0)) { $0 + $1.width + 8 }
            name.width = max(name.minWidth, table.bounds.width - others - 12)
        }
    }

    func activate() { onActivate?(self) }

    func navigate(to directory: URL) {
        guard directory.isFileURL else { return }
        let newURL = directory.standardizedFileURL
        guard newURL != currentDirectory else { refresh(); return }
        backHistory.append(currentDirectory)
        forwardHistory.removeAll()
        changeDirectory(newURL)
    }

    private func changeDirectory(_ directory: URL) {
        currentDirectory = directory
        _ = view
        searchField.stringValue = ""
        table.deselectAll(nil)
        entries.removeAll()
        visibleEntries.removeAll()
        table.reloadData()
        emptyLabel.isHidden = true
        updateDirectoryChrome()
        refresh()
        onDirectoryChanged?(self)
    }

    func goBack() {
        activate()
        guard let previous = backHistory.popLast() else { return }
        forwardHistory.append(currentDirectory)
        changeDirectory(previous)
    }

    func goForward() {
        activate()
        guard let next = forwardHistory.popLast() else { return }
        backHistory.append(currentDirectory)
        changeDirectory(next)
    }

    func goUp() {
        activate()
        navigate(to: currentDirectory.deletingLastPathComponent())
    }

    func focusPath() {
        _ = view
        activate()
        view.window?.makeFirstResponder(pathField)
        pathField.selectText(nil)
    }

    func focusSearch() {
        _ = view
        activate()
        view.window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func refresh() {
        guard isViewLoaded else { return }
        requestGeneration += 1
        let generation = requestGeneration
        let directory = currentDirectory
        let hidden = showsHidden
        let selection = Set(selectedURLs.map(\.path))
        loading = true
        loadError = nil
        spinner.startAnimation(nil)
        statusLabel.stringValue = "Loading…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try FileService.list(directory, showHidden: hidden) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requestGeneration == generation else { return }
                self.loading = false
                self.spinner.stopAnimation(nil)
                switch result {
                case .success(let items):
                    self.entries = items
                    self.loadError = nil
                case .failure(let error):
                    self.entries = []
                    self.loadError = error.localizedDescription
                }
                self.applyFilter(restoring: selection)
                self.onSelectionChanged?(self)
            }
        }
    }

    func performAction(_ action: String) {
        activate()
        let rowActions: Set<String> = ["open", "preview", "copy", "cut", "copyToOther", "moveToOther", "rename", "trash", "copyPath"]
        guard !loading || !rowActions.contains(action) else { return }
        if action == "open" { openSelection() }
        else { onAction?(self, action) }
    }

    func openSelection() {
        activate()
        guard !loading, let first = selectedURLs.first else { return }
        if let entry = visibleEntries.first(where: { $0.url == first }), entry.isDirectory {
            // Application and document packages open with their owning application.
            if NSWorkspace.shared.isFilePackage(atPath: first.path) { NSWorkspace.shared.open(first) }
            else { navigate(to: first) }
        } else {
            NSWorkspace.shared.open(first)
        }
    }

    private func applyFilter(restoring selection: Set<String>? = nil) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleEntries = entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        visibleEntries.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let comparison: ComparisonResult
            switch sortKey {
            case "size":
                comparison = a.size == b.size ? a.name.localizedStandardCompare(b.name) : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case "modified":
                let ad = a.modifiedDate ?? .distantPast
                let bd = b.modifiedDate ?? .distantPast
                comparison = ad == bd ? a.name.localizedStandardCompare(b.name) : ad.compare(bd)
            default: comparison = a.name.localizedStandardCompare(b.name)
            }
            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        table.reloadData()
        if let selection {
            let indexes = IndexSet(visibleEntries.indices.filter { selection.contains(visibleEntries[$0].url.path) })
            table.selectRowIndexes(indexes, byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
        if let error = loadError {
            emptyLabel.stringValue = "Cannot read this folder.\n\n\(error)\n\nCheck the path and file access permissions."
        } else if visibleEntries.isEmpty {
            emptyLabel.stringValue = query.isEmpty ? "This folder is empty" : "No items match \"\(query)\"."
        }
        emptyLabel.isHidden = !visibleEntries.isEmpty
        updateStatus()
    }

    private func updateDirectoryChrome() {
        folderLabel.stringValue = currentDirectory.path == "/" ? "Root" : currentDirectory.lastPathComponent
        folderLabel.toolTip = currentDirectory.path
        pathField.stringValue = (currentDirectory.path as NSString).abbreviatingWithTildeInPath
        pathField.toolTip = currentDirectory.path
        backButton?.isEnabled = !backHistory.isEmpty
        forwardButton?.isEnabled = !forwardHistory.isEmpty
    }

    private func updateActiveAppearance() {
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.borderColor = (isActive ? accent.withAlphaComponent(0.7) : NSColor.separatorColor.withAlphaComponent(0.45)).cgColor
        view.layer?.borderWidth = isActive ? 1.5 : 1
        paneLabel.textColor = isActive ? accent : .secondaryLabelColor
    }

    private func updateStatus() {
        guard !loading else { return }
        if loadError != nil { statusLabel.stringValue = "Could not read folder · Edit the path to try again"; return }
        let selected = selectedURLs.count
        let filtering = !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var text = filtering ? "\(visibleEntries.count) / \(entries.count) items" : "\(entries.count) items"
        if selected > 0 { text += " · \(selected) selected" }
        if showsHidden { text += " · Including hidden items" }
        statusLabel.stringValue = text
    }

    private func iconButton(_ name: String, tooltip: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: tooltip) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 25), button.heightAnchor.constraint(equalToConstant: 27)])
        return button
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let definitions: [(String, String)] = [
            ("Open", "open"), ("Quick Look", "preview"), ("", ""),
            ("Copy", "copy"), ("Cut", "cut"), ("Paste Here", "paste"),
            ("Copy Across", "copyToOther"), ("Move Across", "moveToOther"), ("", ""),
            ("New Folder…", "newFolder"), ("Rename…", "rename"), ("Move to Trash…", "trash"), ("", ""),
            ("Copy Full Path", "copyPath"), ("Favorite Current Folder", "favorite"), ("Open Folder in Terminal", "terminal")
        ]
        for (title, action) in definitions {
            if title.isEmpty { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: title, action: #selector(contextAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            menu.addItem(item)
        }
        return menu
    }

    @objc private func backClicked() { goBack() }
    @objc private func forwardClicked() { goForward() }
    @objc private func upClicked() { goUp() }
    @objc private func refreshClicked() { activate(); refresh() }
    @objc private func doubleClicked() { if table.clickedRow >= 0 { openSelection() } }
    @objc private func searchChanged() { activate(); applyFilter() }
    @objc private func contextAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? String else { return }
        performAction(action)
    }
    @objc private func pathSubmitted() {
        activate()
        let input = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { updateDirectoryChrome(); return }
        let expanded = (input as NSString).expandingTildeInPath
        let target: URL
        if expanded.hasPrefix("/") { target = URL(fileURLWithPath: expanded, isDirectory: true) }
        else { target = currentDirectory.appendingPathComponent(expanded, isDirectory: true) }
        navigate(to: target)
        view.window?.makeFirstResponder(table)
    }

    func controlTextDidBeginEditing(_ obj: Notification) { activate() }

    func numberOfRows(in tableView: NSTableView) -> Int { visibleEntries.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateStatus()
        onSelectionChanged?(self)
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first else { return }
        sortKey = descriptor.key ?? "name"
        sortAscending = descriptor.ascending
        applyFilter(restoring: Set(selectedURLs.map(\.path)))
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard !loading, visibleEntries.indices.contains(row) else { return nil }
        return visibleEntries[row].url as NSURL
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleEntries.indices.contains(row), let column = tableColumn else { return nil }
        let entry = visibleEntries[row]
        let identifier = column.identifier
        if identifier.rawValue == "name" {
            let cell: NSTableCellView
            if let recycled = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
                cell = recycled
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let icon = NSImageView()
                icon.imageScaling = .scaleProportionallyDown
                icon.translatesAutoresizingMaskIntoConstraints = false
                let label = NSTextField(labelWithString: "")
                label.font = NSFont.systemFont(ofSize: 12)
                label.lineBreakMode = .byTruncatingMiddle
                label.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(icon)
                cell.addSubview(label)
                cell.imageView = icon
                cell.textField = label
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 22), icon.heightAnchor.constraint(equalToConstant: 22),
                    label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -3),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            cell.imageView?.image = NSWorkspace.shared.icon(forFile: entry.url.path)
            cell.textField?.stringValue = entry.name
            cell.textField?.textColor = entry.isHidden ? .secondaryLabelColor : .labelColor
            cell.toolTip = entry.url.path
            return cell
        }
        let cell: NSTableCellView
        if let recycled = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = recycled
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -3),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        if identifier.rawValue == "size" {
            cell.textField?.alignment = .right
            cell.textField?.stringValue = entry.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
        } else {
            cell.textField?.alignment = .left
            cell.textField?.stringValue = entry.modifiedDate.map { dateFormatter.string(from: $0) } ?? "—"
        }
        return cell
    }
}
