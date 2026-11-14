import AppKit
import Foundation

private final class PaneContainerView: NSView {
    var onActivate: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        onActivate?()
        super.mouseDown(with: event)
    }
}

private final class BreadcrumbBar: NSView {
    static let editingSpace: CGFloat = 28
    var onEdit: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.045).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override func resetCursorRects() {
        let editingArea = NSRect(x: bounds.maxX - Self.editingSpace, y: 0,
                                 width: Self.editingSpace, height: bounds.height)
        addCursorRect(editingArea, cursor: .iBeam)
    }

    override func mouseDown(with event: NSEvent) { onEdit?() }
}

private final class BreadcrumbPathControl: NSPathControl {
    var onEdit: (() -> Void)?
    var onOverflow: (() -> Void)?
    private var hoverTracking: NSTrackingArea?
    private var pointerInside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [
            .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow
        ], owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        pointerInside = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        pointerInside = false
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        pointerInside = true
        needsDisplay = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let pathCell = cell as? NSPathCell,
              let last = pathCell.pathComponentCells.last else { return }
        let lastFrame = pathCell.rect(of: last, withFrame: bounds, in: self)
        if lastFrame.maxX < bounds.maxX {
            let emptySpace = NSRect(x: lastFrame.maxX, y: bounds.minY,
                                    width: bounds.maxX - lastFrame.maxX, height: bounds.height)
            addCursorRect(emptySpace, cursor: .iBeam)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if pointerInside, let window, window.isKeyWindow, let pathCell = cell as? NSPathCell {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(point),
               let component = pathCell.pathComponentCell(at: point, withFrame: bounds, in: self) {
                let frame = pathCell.rect(of: component, withFrame: bounds, in: self).insetBy(dx: 0, dy: 2)
                NSColor.labelColor.withAlphaComponent(0.10).setFill()
                NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4).fill()
            }
        }
        super.draw(dirtyRect)
    }

    /// Give the path cell a square image while keeping the original symbol's proportions inside it.
    static func icon(_ name: String) -> NSImage? {
        guard let symbol = QingTheme.symbol(name, size: 14) else { return nil }
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { bounds in
            let scale = 20 / max(symbol.size.width, symbol.size.height)
            let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            symbol.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                   width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true
        return image
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let pathCell = cell as? NSPathCell {
            guard let component = pathCell.pathComponentCell(at: point, withFrame: bounds, in: self) else {
                onEdit?()
                return
            }
            if component.url == nil {
                onOverflow?()
                return
            }
        }
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

    private let accent = QingTheme.accent
    private let table = FileListTable()
    private let folderLabel = NSTextField(labelWithString: "")
    private let pathField = NSTextField(string: "")
    private let breadcrumbControl = BreadcrumbPathControl()
    private let pathPresentation = BreadcrumbBar()
    private var pathEditing = false
    private var breadcrumbWidth: CGFloat = -1
    private var breadcrumbDirectory: String?
    private var overflowLocations: [URL] = []
    private let searchField = NSSearchField()
    private let pathContent = NSStackView()
    private var searchButton: NSButton!
    private var searchWidth: NSLayoutConstraint!
    private var searchExpanded = false
    private let statusLabel = NSTextField(labelWithString: "Loading…")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var entries: [FileEntry] = []
    private var visibleEntries: [FileEntry] = []
    private var backHistory: [URL] = []
    private var forwardHistory: [URL] = []
    private var pendingNewURL: URL?
    private var inlineURL: URL?
    private var inlineExtension = ""
    private weak var inlineField: NSTextField?
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
        root.layer?.cornerRadius = 0
        root.layer?.masksToBounds = true
        root.onActivate = { [weak self] in self?.activate() }
        view = root

        root.setAccessibilityLabel("\(paneTitle) file pane")
        folderLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        backButton = iconButton("chevron.left", tooltip: "Back", action: #selector(backClicked))
        forwardButton = iconButton("chevron.right", tooltip: "Forward", action: #selector(forwardClicked))
        let upButton = iconButton("arrow.up", tooltip: "Parent Folder", action: #selector(upClicked))
        let refreshButton = iconButton("arrow.clockwise", tooltip: "Refresh", action: #selector(refreshClicked))
        let navigation = NSStackView(views: [backButton, forwardButton, upButton, refreshButton])
        navigation.spacing = 1
        pathField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.usesSingleLineMode = true
        pathField.isEditable = true
        pathField.isSelectable = true
        pathField.bezelStyle = .roundedBezel
        pathField.focusRingType = .none
        pathField.placeholderString = "Enter a path, e.g. / or ~/Documents"
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

        pathField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathContent.orientation = .horizontal
        pathContent.spacing = 6
        pathContent.detachesHiddenViews = true
        breadcrumbControl.pathStyle = .standard
        breadcrumbControl.controlSize = .small
        breadcrumbControl.isEditable = false
        breadcrumbControl.backgroundColor = .clear
        breadcrumbControl.target = self
        breadcrumbControl.action = #selector(breadcrumbClicked)
        breadcrumbControl.onEdit = { [weak self] in self?.focusPath() }
        breadcrumbControl.onOverflow = { [weak self] in self?.showPathOverflow() }
        breadcrumbControl.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        breadcrumbControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        breadcrumbControl.setAccessibilityLabel("Folder path")
        pathPresentation.onEdit = breadcrumbControl.onEdit
        pathPresentation.toolTip = "Click empty space to edit the path, or press ⌘L"
        pathPresentation.addSubview(breadcrumbControl)
        breadcrumbControl.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pathPresentation.heightAnchor.constraint(equalToConstant: 27),
            breadcrumbControl.leadingAnchor.constraint(equalTo: pathPresentation.leadingAnchor, constant: 5),
            breadcrumbControl.trailingAnchor.constraint(equalTo: pathPresentation.trailingAnchor, constant: -BreadcrumbBar.editingSpace),
            breadcrumbControl.topAnchor.constraint(equalTo: pathPresentation.topAnchor),
            breadcrumbControl.bottomAnchor.constraint(equalTo: pathPresentation.bottomAnchor)
        ])
        pathContent.addArrangedSubview(pathPresentation)
        pathContent.addArrangedSubview(pathField)
        pathContent.addArrangedSubview(searchField)
        pathField.isHidden = true
        searchField.isHidden = true
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        searchWidth = searchField.widthAnchor.constraint(equalToConstant: 200)
        searchWidth.priority = .defaultHigh
        searchButton = iconButton("magnifyingglass", tooltip: "Search Current Folder · ⌘F", action: #selector(toggleSearch))
        let navigationRow = NSStackView(views: [navigation, pathContent, searchButton])
        navigationRow.orientation = .horizontal
        navigationRow.alignment = .centerY
        navigationRow.spacing = 6
        pathContent.setContentHuggingPriority(.defaultLow, for: .horizontal)

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
        for subview in [folderLabel, navigationRow, divider, scroll, emptyLabel, footer] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            folderLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            folderLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            folderLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            folderLabel.heightAnchor.constraint(equalToConstant: 20),
            navigationRow.topAnchor.constraint(equalTo: folderLabel.bottomAnchor, constant: 8),
            navigationRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            navigationRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            navigationRow.heightAnchor.constraint(equalToConstant: 27),
            pathField.heightAnchor.constraint(equalToConstant: 27),
            searchField.heightAnchor.constraint(equalToConstant: 27),
            divider.topAnchor.constraint(equalTo: navigationRow.bottomAnchor, constant: 10),
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
        updateSearchLayout()
        pathContent.layoutSubtreeIfNeeded()
        updateBreadcrumbs()
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
        guard view.window?.makeFirstResponder(nil) != false else { return }
        guard newURL.path != currentDirectory.path else { refresh(); return }
        backHistory.append(currentDirectory)
        forwardHistory.removeAll()
        changeDirectory(newURL)
    }

    private func changeDirectory(_ directory: URL) {
        guard view.window?.makeFirstResponder(nil) != false else { return }
        pendingNewURL = nil
        currentDirectory = directory
        _ = view
        searchField.stringValue = ""
        searchExpanded = false
        updateSearchLayout()
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
        guard view.window?.makeFirstResponder(nil) != false else { return }
        guard let previous = backHistory.popLast() else { return }
        forwardHistory.append(currentDirectory)
        changeDirectory(previous)
    }

    func goForward() {
        activate()
        guard view.window?.makeFirstResponder(nil) != false else { return }
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
        guard view.window?.makeFirstResponder(nil) != false else { return }
        activate()
        guard closeSearch() else { return }
        pathEditing = true
        pathField.stringValue = currentDirectory.path
        updateSearchLayout()
        pathField.selectText(nil)
    }

    func focusSearch() {
        _ = view
        guard view.window?.makeFirstResponder(nil) != false else { return }
        activate()
        searchExpanded = true
        updateSearchLayout()
        searchField.selectText(nil)
    }

    @objc private func toggleSearch() {
        if searchExpanded { _ = closeSearch() }
        else { focusSearch() }
    }

    @discardableResult
    private func closeSearch() -> Bool {
        guard searchExpanded else { return true }
        guard view.window?.makeFirstResponder(table) != false else { return false }
        activate()
        searchField.stringValue = ""
        searchExpanded = false
        updateSearchLayout()
        applyFilter(restoring: Set(selectedURLs.map(\.path)))
        return true
    }

    private func updateSearchLayout() {
        guard searchButton != nil else { return }
        let sharesPath = searchExpanded && view.bounds.width >= 640
        let hidesPath = searchExpanded && !sharesPath
        pathPresentation.isHidden = hidesPath || pathEditing
        pathField.isHidden = hidesPath || !pathEditing
        searchField.isHidden = !searchExpanded
        searchWidth.isActive = sharesPath
        let symbol = searchExpanded ? "xmark" : "magnifyingglass"
        let description = searchExpanded ? "Close Search" : "Search Current Folder"
        searchButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        searchButton.toolTip = searchExpanded ? "Clear and close search · Esc" : "Search Current Folder · ⌘F"
    }

    func refresh(selecting preferredSelection: Set<String>? = nil) {
        guard isViewLoaded, inlineURL == nil else { return }
        requestGeneration += 1
        let generation = requestGeneration
        let directory = currentDirectory
        let hidden = showsHidden
        let selection = preferredSelection ?? Set(selectedURLs.map(\.path))
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
                if let url = self.pendingNewURL {
                    self.pendingNewURL = nil
                    self.selectNewItem(url)
                }
            }
        }
    }

    func revealCreatedItem(_ url: URL) {
        guard url.deletingLastPathComponent().standardizedFileURL.path == currentDirectory.standardizedFileURL.path else { return }
        searchField.stringValue = ""
        pendingNewURL = url
        refresh()
    }

    private func selectNewItem(_ url: URL) {
        guard let row = visibleEntries.firstIndex(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        guard isActive, view.window?.isKeyWindow == true,
              let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField else { return }
        inlineURL = url
        inlineExtension = visibleEntries[row].isDirectory ? "" : url.pathExtension
        inlineField = field
        field.isEditable = true
        field.isSelectable = true
        field.delegate = self
        field.stringValue = inlineExtension.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        field.selectText(nil)
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
        if !pathEditing { pathField.stringValue = currentDirectory.path }
        updateBreadcrumbs()
        pathField.toolTip = currentDirectory.path
        backButton?.isEnabled = !backHistory.isEmpty
        forwardButton?.isEnabled = !forwardHistory.isEmpty
    }

    private func updateActiveAppearance() {
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.borderColor = (isActive ? accent.withAlphaComponent(0.7) : NSColor.separatorColor.withAlphaComponent(0.45)).cgColor
        view.layer?.borderWidth = 0
        folderLabel.textColor = isActive ? accent : .labelColor
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
            ("New", "new"), ("Rename…", "rename"), ("Move to Trash…", "trash"), ("", ""),
            ("Copy Full Path", "copyPath"), ("Favorite Current Folder", "favorite"), ("Open Folder in Terminal", "terminal")
        ]
        for (title, action) in definitions {
            if title.isEmpty { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: title, action: #selector(contextAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            if action == "new" {
                let submenu = NSMenu(title: "New")
                for kind in NewItemKind.allCases {
                    let child = NSMenuItem(title: kind.title, action: #selector(contextAction(_:)), keyEquivalent: "")
                    child.target = self
                    child.representedObject = "newItem:" + kind.rawValue
                    submenu.addItem(child)
                }
                item.submenu = submenu
            }
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
    @objc private func breadcrumbClicked() {
        guard let item = breadcrumbControl.clickedPathItem else { return }
        if let url = item.url {
            activate()
            navigate(to: url)
        } else {
            showPathOverflow()
        }
    }

    private func showPathOverflow() {
        let menu = NSMenu(title: "Parent Folders")
        for url in overflowLocations {
            let entry = NSMenuItem(title: url.lastPathComponent, action: #selector(overflowPathClicked(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = url
            entry.toolTip = url.path
            menu.addItem(entry)
        }
        // Return from the path control's accessibility action before tracking a menu.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.view.window?.isKeyWindow == true else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: self.breadcrumbControl.bounds.maxY), in: self.breadcrumbControl)
        }
    }

    @objc private func overflowPathClicked(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        activate()
        navigate(to: url)
    }

    private func updateBreadcrumbs() {
        let width = breadcrumbControl.bounds.width
        guard breadcrumbDirectory != currentDirectory.path || breadcrumbWidth != width else { return }
        breadcrumbDirectory = currentDirectory.path
        breadcrumbWidth = width
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let insideHome = currentDirectory.path == home.path || currentDirectory.path.hasPrefix(home.path + "/")
        let anchor = insideHome ? home : URL(fileURLWithPath: "/", isDirectory: true)
        var locations = [currentDirectory]
        while let first = locations.first, first.path != anchor.path {
            locations.insert(first.deletingLastPathComponent(), at: 0)
        }
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        func title(_ url: URL) -> String {
            if url.path == home.path { return "~" }
            return url.path == "/" ? "/" : url.lastPathComponent
        }
        func estimatedWidth(_ url: URL) -> CGFloat {
            (title(url) as NSString).size(withAttributes: [.font: font]).width + 32
        }
        var visible = locations
        overflowLocations = []
        var total = visible.reduce(CGFloat(0)) { $0 + estimatedWidth($1) }
        while total + (overflowLocations.isEmpty ? 0 : 30) > width && visible.count > 2 {
            let removed = visible.remove(at: 1)
            overflowLocations.append(removed)
            total -= estimatedWidth(removed)
        }
        breadcrumbControl.url = currentDirectory
        let nativeItems = breadcrumbControl.pathItems
        var items = visible.compactMap { url -> NSPathControlItem? in
            guard let item = nativeItems.first(where: { $0.url?.path == url.path }) else { return nil }
            item.title = title(url)
            item.image = url.path == home.path ? Self.homePathIcon : Self.folderPathIcon
            return item
        }
        if !overflowLocations.isEmpty {
            let more = NSPathControlItem()
            more.title = "…"
            items.insert(more, at: 1)
        }
        breadcrumbControl.pathItems = items
        breadcrumbControl.toolTip = currentDirectory.path
        breadcrumbControl.window?.invalidateCursorRects(for: breadcrumbControl)
    }

    private static let homePathIcon = BreadcrumbPathControl.icon("house")
    private static let folderPathIcon = BreadcrumbPathControl.icon("folder")

    @objc private func pathSubmitted() {
        let input = pathField.stringValue
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusLabel.stringValue = "Enter a folder path."
            NSSound.beep()
            return
        }
        let expanded = (input as NSString).expandingTildeInPath
        let target = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded, isDirectory: true) : currentDirectory.appendingPathComponent(expanded, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            statusLabel.stringValue = "Folder not found or inaccessible. Edit the path to try again."
            NSSound.beep()
            return
        }
        activate()
        navigate(to: target)
        view.window?.makeFirstResponder(table)
    }

    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        guard let field = inlineField, control === field, let url = inlineURL else { return true }
        let base = fieldEditor.string
        // Validate the editable stem before appending its protected extension.
        guard !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              base != ".", base != "..", !base.contains("/"), !base.contains("\0") else {
            showNamingError("Enter a nonempty name other than . or .., without a slash or null character.")
            return false
        }
        let name = inlineExtension.isEmpty ? base : base + "." + inlineExtension
        do {
            inlineURL = try FileService.rename(url, to: name)
            return true
        } catch {
            showNamingError(error.localizedDescription)
            return false
        }
    }

    private func showNamingError(_ message: String) {
        guard let window = view.window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Cannot Rename Item"
        alert.informativeText = message
        alert.beginSheetModal(for: window) { [weak self] _ in
            guard let field = self?.inlineField else { return }
            field.window?.makeFirstResponder(field)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === pathField {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                view.window?.makeFirstResponder(table)
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                pathSubmitted()
                return true
            }
        }
        if control === searchField, commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            return closeSearch()
        }
        guard control === inlineField else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)), let url = inlineURL {
            textView.string = inlineExtension.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            view.window?.makeFirstResponder(table)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            view.window?.makeFirstResponder(table)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field === pathField {
            pathEditing = false
            pathField.stringValue = currentDirectory.path
            updateSearchLayout()
            updateStatus()
            return
        }
        guard let field = obj.object as? NSTextField, field === inlineField, let url = inlineURL else { return }
        field.stringValue = url.lastPathComponent
        field.isEditable = false
        field.isSelectable = false
        field.delegate = nil
        inlineField = nil
        inlineURL = nil
        inlineExtension = ""
        refresh(selecting: [url.path])
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
