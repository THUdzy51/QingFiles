import AppKit
import Foundation

final class FileBrowserWindow: NSWindow {
    var onMouseDown: ((NSPoint) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if onMouseDown?(event.locationInWindow) == false { return }
        default:
            break
        }
        super.sendEvent(event)
    }
}

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
    weak var menuButton: BreadcrumbButton? {
        didSet {
            let stack = subviews.first as? NSStackView
            stack?.arrangedSubviews.forEach { $0.needsDisplay = true }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.045).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override func resetCursorRects() {
        let start = subviews.first?.frame.maxX ?? bounds.minX
        let editingArea = NSRect(x: start, y: bounds.minY,
                                 width: max(0, bounds.maxX - start), height: bounds.height)
        addCursorRect(editingArea, cursor: .iBeam)
    }

    override func mouseDown(with event: NSEvent) { onEdit?() }
}

private final class BreadcrumbButton: NSButton {
    static let labelFont = NSFont.systemFont(ofSize: 12)
    var location: URL?
    weak var bar: BreadcrumbBar?
    private var hoverTracking: NSTrackingArea?
    private var hovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [
            .inVisibleRect, .mouseEnteredAndExited, .activeInKeyWindow
        ], owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if showsHighlight {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
    }

    private var showsHighlight: Bool {
        if let menuButton = bar?.menuButton { return menuButton === self }
        guard hovered, let window, window.isKeyWindow else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
}

private final class BreadcrumbMenuPlacement: NSObject, NSMenuDelegate {
    let origin: NSPoint

    init(button: NSView, bar: NSView, window: NSWindow) {
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let barFrame = window.convertToScreen(bar.convert(bar.bounds, to: nil))
        origin = NSPoint(x: buttonFrame.minX, y: barFrame.minY - 6)
    }

    func confinementRect(for menu: NSMenu, on screen: NSScreen?) -> NSRect {
        guard let frame = screen?.visibleFrame, origin.y > frame.minY else { return .zero }
        return NSRect(x: frame.minX, y: frame.minY, width: frame.width,
                      height: min(origin.y, frame.maxY) - frame.minY)
    }
}

private final class FilenameField: NSTextField {
    var nameHitWidth: CGFloat { min(bounds.width, attributedStringValue.size().width + 4) }

    override func accessibilityFrame() -> NSRect {
        var frame = super.accessibilityFrame()
        // The accessible name target matches the clickable text, not row whitespace.
        if !isEditable { frame.size.width = nameHitWidth }
        return frame
    }
}

private final class FileListTable: NSTableView {
    weak var pane: FilePane?
    var didBeginDragging = false

    override func mouseDown(with event: NSEvent) {
        pane?.cancelPendingRename()
        pane?.activate()
        didBeginDragging = false
        super.mouseDown(with: event)
        guard !didBeginDragging else { return }
        pane?.filenameClickEnded(at: convert(event.locationInWindow, from: nil),
                                 clickCount: event.clickCount, modifiers: event.modifierFlags)
    }

    override func rightMouseDown(with event: NSEvent) {
        pane?.cancelPendingRename()
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
        pane?.cancelPendingRename()
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

    override func scrollWheel(with event: NSEvent) {
        pane?.cancelPendingRename()
        super.scrollWheel(with: event)
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
    var allowsInlineRename: (() -> Bool)?

    var isActive = false {
        didSet {
            if !isActive { cancelPendingRename() }
            if isViewLoaded { updateActiveAppearance() }
        }
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
    private let breadcrumbStack = NSStackView()
    private let breadcrumbQueue = DispatchQueue(label: "local.qingfiles.breadcrumbs", qos: .userInitiated, attributes: .concurrent)
    private var breadcrumbMenuRequest = UUID()
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
    private var revealedPaths: Set<String> = []
    private var pendingRevealSelection: Set<String>?
    private var inlineURL: URL?
    private var inlineEntry: FileEntry?
    private var inlineCancelled = false
    private weak var inlineField: NSTextField?
    private var renameTimer: Timer?
    private var pendingRenameURL: URL?
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
        breadcrumbStack.orientation = .horizontal
        breadcrumbStack.alignment = .centerY
        breadcrumbStack.spacing = 0
        breadcrumbStack.translatesAutoresizingMaskIntoConstraints = false
        pathPresentation.onEdit = { [weak self] in self?.focusPath() }
        pathPresentation.toolTip = "Click empty space to edit the path, or press ⌘L"
        pathPresentation.addSubview(breadcrumbStack)
        NSLayoutConstraint.activate([
            pathPresentation.heightAnchor.constraint(equalToConstant: 27),
            breadcrumbStack.leadingAnchor.constraint(equalTo: pathPresentation.leadingAnchor, constant: 4),
            breadcrumbStack.trailingAnchor.constraint(lessThanOrEqualTo: pathPresentation.trailingAnchor, constant: -BreadcrumbBar.editingSpace),
            breadcrumbStack.centerYAnchor.constraint(equalTo: pathPresentation.centerYAnchor)
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

    func navigate(to directory: URL, selecting paths: Set<String> = []) {
        guard directory.isFileURL else { return }
        let newURL = directory.standardizedFileURL
        guard view.window?.makeFirstResponder(table) != false else { return }
        guard newURL.path != currentDirectory.path else {
            revealedPaths = paths
            pendingRevealSelection = paths.isEmpty ? nil : paths
            refresh()
            return
        }
        backHistory.append(currentDirectory)
        forwardHistory.removeAll()
        changeDirectory(newURL, selecting: paths)
    }

    private func changeDirectory(_ directory: URL, selecting paths: Set<String> = []) {
        guard view.window?.makeFirstResponder(table) != false else { return }
        pendingNewURL = nil
        revealedPaths = paths
        pendingRevealSelection = paths.isEmpty ? nil : paths
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

    func revealFiles(_ urls: [URL]) throws {
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else {
            throw FileServiceError.invalid("Choose one or more local files to reveal.")
        }
        let files = urls.map(\.standardizedFileURL)
        let directory = files[0].deletingLastPathComponent()
        guard files.allSatisfy({ $0.deletingLastPathComponent().path == directory.path }) else {
            throw FileServiceError.invalid("Choose files from one folder at a time.")
        }
        for file in files {
            _ = try FileManager.default.attributesOfItem(atPath: file.path)
        }
        var isDirectory: ObjCBool = false
        let opensFolder = files.count == 1 &&
            FileManager.default.fileExists(atPath: files[0].path, isDirectory: &isDirectory) &&
            isDirectory.boolValue && !NSWorkspace.shared.isFilePackage(atPath: files[0].path)
        _ = view
        guard view.window?.makeFirstResponder(table) != false else {
            throw FileServiceError.invalid("Finish naming the current item before revealing another file.")
        }
        activate()
        pendingNewURL = nil
        searchField.stringValue = ""
        searchExpanded = false
        updateSearchLayout()
        if opensFolder {
            navigate(to: files[0])
        } else {
            navigate(to: directory, selecting: Set(files.map(\.path)))
        }
        view.window?.makeFirstResponder(table)
    }

    func goBack() {
        activate()
        guard view.window?.makeFirstResponder(table) != false else { return }
        guard let previous = backHistory.popLast() else { return }
        forwardHistory.append(currentDirectory)
        changeDirectory(previous)
    }

    func goForward() {
        activate()
        guard view.window?.makeFirstResponder(table) != false else { return }
        guard let next = forwardHistory.popLast() else { return }
        backHistory.append(currentDirectory)
        changeDirectory(next)
    }

    func goUp() {
        activate()
        navigate(to: currentDirectory.deletingLastPathComponent())
    }

    func focusPath() {
        cancelPendingRename()
        _ = view
        guard view.window?.makeFirstResponder(table) != false else { return }
        activate()
        guard closeSearch() else { return }
        breadcrumbMenuRequest = UUID()
        pathEditing = true
        pathField.stringValue = currentDirectory.path
        updateSearchLayout()
        pathField.selectText(nil)
    }

    func dismissPathEditor(clickAt point: NSPoint? = nil) {
        guard pathEditing, let window = pathField.window else { return }
        if let point, pathField.bounds.contains(pathField.convert(point, from: nil)) { return }
        window.makeFirstResponder(nil)
    }

    /// End naming even when blank areas or non-focusing controls are clicked.
    @discardableResult
    func dismissEditors(clickAt point: NSPoint) -> Bool {
        cancelPendingRename()
        dismissPathEditor(clickAt: point)
        guard let field = inlineField, let window = field.window else { return true }
        if field.bounds.contains(field.convert(point, from: nil)) { return true }
        return window.makeFirstResponder(table)
    }

    func focusSearch() {
        cancelPendingRename()
        _ = view
        guard view.window?.makeFirstResponder(table) != false else { return }
        activate()
        breadcrumbMenuRequest = UUID()
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
        cancelPendingRename()
        guard isViewLoaded, inlineURL == nil else { return }
        requestGeneration += 1
        let generation = requestGeneration
        let directory = currentDirectory
        let hidden = showsHidden
        let revealed = revealedPaths
        let selection = pendingRevealSelection ?? preferredSelection ?? Set(selectedURLs.map(\.path))
        loading = true
        loadError = nil
        spinner.startAnimation(nil)
        statusLabel.stringValue = "Loading…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try FileService.list(directory, showHidden: hidden || !revealed.isEmpty)
                    .filter { hidden || !$0.isHidden || revealed.contains($0.url.path) }
            }
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
                if self.pendingRevealSelection != nil {
                    self.pendingRevealSelection = nil
                    if let row = self.table.selectedRowIndexes.first {
                        self.table.scrollRowToVisible(row)
                    } else if self.loadError == nil {
                        self.statusLabel.stringValue = "The requested files are no longer in this folder."
                    }
                }
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
        beginInlineRename(at: row)
    }

    fileprivate func cancelPendingRename() {
        renameTimer?.invalidate()
        renameTimer = nil
        pendingRenameURL = nil
    }

    /// The name, rather than its icon or the rest of the row, is the edit target.
    func filenameClickEnded(at point: NSPoint, clickCount: Int, modifiers: NSEvent.ModifierFlags) {
        cancelPendingRename()
        let row = table.row(at: point)
        guard clickCount == 1, modifiers.intersection([.command, .shift, .control, .option]).isEmpty,
              !loading, inlineURL == nil, visibleEntries.indices.contains(row),
              table.selectedRowIndexes == IndexSet(integer: row),
              let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let field = cell.textField as? FilenameField else { return }
        var nameRect = field.convert(field.bounds, to: table)
        nameRect.size.width = field.nameHitWidth
        guard nameRect.insetBy(dx: 0, dy: -3).contains(point) else { return }
        scheduleInlineRename(visibleEntries[row].url)
    }

    private func scheduleInlineRename(_ url: URL) {
        cancelPendingRename()
        pendingRenameURL = url
        // Wait for a possible second click before installing the field editor.
        renameTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.doubleClickInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.renameTimer = nil
            self.pendingRenameURL = nil
            guard self.view.window?.firstResponder === self.table,
                  self.selectedURLs == [url],
                  let row = self.visibleEntries.firstIndex(where: { $0.url == url }),
                  self.table.rows(in: self.table.visibleRect).contains(row) else { return }
            self.beginInlineRename(at: row)
        }
    }

    private func beginInlineRename(at row: Int) {
        cancelPendingRename()
        guard !loading, inlineURL == nil, allowsInlineRename?() != false,
              visibleEntries.indices.contains(row) else { return }
        guard isActive, view.window?.isKeyWindow == true,
              let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField else { return }
        let entry = visibleEntries[row]
        inlineURL = entry.url
        inlineEntry = entry
        inlineCancelled = false
        inlineField = field
        field.isEditable = true
        field.isSelectable = true
        field.delegate = self
        field.stringValue = entry.name
        field.selectText(nil)
        let stem = entry.isDirectory ? entry.name : entry.url.deletingPathExtension().lastPathComponent
        (field.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: 0, length: stem.utf16.count))
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
    @objc private func breadcrumbClicked(_ sender: BreadcrumbButton) {
        guard let url = sender.location else { return }
        activate()
        navigate(to: url)
    }

    @objc private func showPathOverflow(_ sender: BreadcrumbButton) {
        activate()
        breadcrumbMenuRequest = UUID()
        let menu = breadcrumbMenu(title: "Parent Folders", folders: overflowLocations)
        // Let the button action return before AppKit starts tracking the menu.
        DispatchQueue.main.async { [weak self, weak sender] in
            guard let sender else { return }
            self?.presentBreadcrumbMenu(menu, from: sender)
        }
    }

    @objc private func showSubfolders(_ sender: BreadcrumbButton) {
        guard let folder = sender.location else { return }
        activate()
        let request = UUID()
        breadcrumbMenuRequest = request
        let showHidden = showsHidden
        breadcrumbQueue.async { [weak self, weak sender] in
            let folders = Result {
                try FileService.list(folder, showHidden: showHidden)
                    .filter { $0.isDirectory && !NSWorkspace.shared.isFilePackage(atPath: $0.url.path) }
                    .map(\.url)
            }
            DispatchQueue.main.async { [weak self, weak sender] in
                guard let self, let sender, self.breadcrumbMenuRequest == request,
                      self.showsHidden == showHidden else { return }
                let menu: NSMenu
                switch folders {
                case .success(let urls):
                    menu = self.breadcrumbMenu(title: "Subfolders", folders: urls,
                                               emptyMessage: "No Subfolders")
                case .failure:
                    menu = self.breadcrumbMenu(title: "Subfolders", folders: [],
                                               emptyMessage: "Cannot Read Folder")
                }
                self.presentBreadcrumbMenu(menu, from: sender)
            }
        }
    }

    private func breadcrumbMenu(title: String, folders: [URL], emptyMessage: String = "No Folders") -> NSMenu {
        let menu = NSMenu(title: title)
        for url in folders {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(breadcrumbMenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            menu.addItem(item)
        }
        if folders.isEmpty {
            menu.addItem(NSMenuItem(title: emptyMessage, action: nil, keyEquivalent: ""))
        }
        return menu
    }

    private func presentBreadcrumbMenu(_ menu: NSMenu, from button: BreadcrumbButton) {
        guard isActive, let window = button.window, window.isVisible,
              NSApp.keyWindow == nil || NSApp.keyWindow === window,
              !button.isHiddenOrHasHiddenAncestor else { return }
        // Anchor the menu to the arrow's leading edge and below the entire path bar.
        let placement = BreadcrumbMenuPlacement(button: button, bar: pathPresentation, window: window)
        menu.delegate = placement
        let closedImage = button.image
        // Menu tracking can delay mouse-exit events. Repaint every segment before it begins.
        pathPresentation.menuButton = button
        if button.location != nil { button.image = QingTheme.symbol("chevron.down", size: 10) }
        defer {
            button.image = closedImage
            pathPresentation.menuButton = nil
        }
        pathPresentation.displayIfNeeded()
        let anchor = button.convert(window.convertPoint(fromScreen: placement.origin), from: nil)
        withExtendedLifetime(placement) {
            _ = menu.popUp(positioning: nil, at: anchor, in: button)
        }
    }

    @objc private func breadcrumbMenuItemClicked(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        activate()
        navigate(to: url)
    }

    private func updateBreadcrumbs() {
        guard !pathPresentation.isHidden, pathPresentation.bounds.width > 0 else { return }
        let width = pathPresentation.bounds.width
        guard breadcrumbDirectory != currentDirectory.path || breadcrumbWidth != width else { return }
        breadcrumbDirectory = currentDirectory.path
        breadcrumbWidth = width
        breadcrumbMenuRequest = UUID()
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let insideHome = currentDirectory.path == home.path || currentDirectory.path.hasPrefix(home.path + "/")
        let anchor = insideHome ? home : URL(fileURLWithPath: "/", isDirectory: true)
        var locations = [currentDirectory]
        while let first = locations.first, first.path != anchor.path {
            locations.insert(first.deletingLastPathComponent(), at: 0)
        }
        func title(_ url: URL) -> String {
            if url.path == home.path { return "~" }
            return url.path == "/" ? "/" : url.lastPathComponent
        }
        let arrowWidth: CGFloat = 17
        let overflowWidth: CGFloat = 22
        func nameWidth(_ url: URL) -> CGFloat {
            let textWidth = (title(url) as NSString).size(withAttributes: [.font: BreadcrumbButton.labelFont]).width
            return ceil(textWidth) + 22
        }
        let available = max(0, width - BreadcrumbBar.editingSpace - 4)
        var visible = locations
        overflowLocations = []
        var total = visible.reduce(CGFloat(0)) { $0 + nameWidth($1) + arrowWidth }
        while visible.count > 2 {
            let required = total + (overflowLocations.isEmpty ? 0 : overflowWidth)
            // Shorten the current folder label slightly to keep the nearest parent available.
            let truncation = visible.count == 3 ? min(22, max(0, nameWidth(currentDirectory) - 64)) : 0
            if required - truncation <= available { break }
            let removed = visible.remove(at: 1)
            overflowLocations.append(removed)
            total -= nameWidth(removed) + arrowWidth
        }

        breadcrumbStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, url) in visible.enumerated() {
            let name = makeBreadcrumbButton(title(url), action: #selector(breadcrumbClicked(_:)))
            name.location = url
            name.toolTip = url.path
            name.image = QingTheme.symbol(url.path == home.path ? "house" : "folder", size: 13)
            name.imagePosition = .imageLeading
            name.imageHugsTitle = true
            name.imageScaling = .scaleProportionallyDown
            name.lineBreakMode = .byTruncatingMiddle
            name.setAccessibilityLabel(title(url))
            addBreadcrumbButton(name, width: nameWidth(url), flexible: index == visible.count - 1)

            let arrow = makeBreadcrumbButton("", action: #selector(showSubfolders(_:)))
            arrow.location = url
            arrow.image = QingTheme.symbol("chevron.right", size: 10)
            let description = "Show subfolders of \(title(url))"
            arrow.toolTip = description
            arrow.setAccessibilityLabel(description)
            addBreadcrumbButton(arrow, width: arrowWidth)

            if index == 0 && !overflowLocations.isEmpty {
                let overflow = makeBreadcrumbButton("…", action: #selector(showPathOverflow(_:)))
                overflow.toolTip = "Show parent folders"
                overflow.setAccessibilityLabel("Show parent folders")
                addBreadcrumbButton(overflow, width: overflowWidth)
            }
        }
        breadcrumbStack.layoutSubtreeIfNeeded()
        pathPresentation.window?.invalidateCursorRects(for: pathPresentation)
    }

    private func makeBreadcrumbButton(_ title: String, action: Selector) -> BreadcrumbButton {
        let button = BreadcrumbButton(frame: .zero)
        button.title = title
        button.target = self
        button.action = action
        button.font = BreadcrumbButton.labelFont
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.contentTintColor = .labelColor
        button.focusRingType = .default
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func addBreadcrumbButton(_ button: BreadcrumbButton, width: CGFloat, flexible: Bool = false) {
        button.bar = pathPresentation
        breadcrumbStack.addArrangedSubview(button)
        let widthConstraint = button.widthAnchor.constraint(equalToConstant: width)
        if flexible {
            widthConstraint.priority = .defaultHigh
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        NSLayoutConstraint.activate([widthConstraint, button.heightAnchor.constraint(equalToConstant: 23)])
    }

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
        guard !inlineCancelled else { return true }
        do {
            inlineURL = try FileService.rename(url, to: fieldEditor.string)
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
            // Refocus the existing editor. Focusing its control would try to end
            // editing again, potentially committing a previously rejected name.
            if let editor = field.currentEditor() { field.window?.makeFirstResponder(editor) }
            else { field.selectText(nil) }
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
            inlineCancelled = true
            textView.string = url.lastPathComponent
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
        guard let field = obj.object as? NSTextField, field === inlineField,
              let url = inlineURL, let original = inlineEntry else { return }
        field.stringValue = url.lastPathComponent
        field.isEditable = false
        field.isSelectable = false
        field.delegate = nil
        inlineField = nil
        inlineURL = nil
        inlineEntry = nil
        guard url != original.url else { return }
        let renamed = FileEntry(url: url, name: url.lastPathComponent, isDirectory: original.isDirectory,
                                isHidden: (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden ?? url.lastPathComponent.hasPrefix("."),
                                isSymbolicLink: original.isSymbolicLink, size: original.size, modifiedDate: original.modifiedDate)
        entries = entries.map { $0.url == original.url ? renamed : $0 }
        visibleEntries = visibleEntries.map { $0.url == original.url ? renamed : $0 }
        if renamed.isHidden { revealedPaths.insert(url.path) }
        // Let the click that ended editing select its target before re-sorting rows.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.inlineURL == nil else { return }
            if self.selectedURLs.contains(url),
               !url.lastPathComponent.localizedCaseInsensitiveContains(self.searchField.stringValue) {
                self.searchField.stringValue = ""
            }
            let nextRename = self.pendingRenameURL
            self.applyFilter(restoring: Set(self.selectedURLs.map(\.path)))
            if self.selectedURLs.contains(url), let row = self.table.selectedRowIndexes.first {
                self.table.scrollRowToVisible(row)
            }
            self.onSelectionChanged?(self)
            if let nextRename, self.selectedURLs == [nextRename] {
                self.scheduleInlineRename(nextRename)
            }
        }
    }

    func controlTextDidBeginEditing(_ obj: Notification) { activate() }

    func numberOfRows(in tableView: NSTableView) -> Int { visibleEntries.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        cancelPendingRename()
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

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        table.didBeginDragging = true
        cancelPendingRename()
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
                let label = FilenameField(labelWithString: "")
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
