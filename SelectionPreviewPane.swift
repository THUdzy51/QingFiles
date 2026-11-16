import AppKit
import ImageIO
import QuickLookThumbnailing
import QuickLookUI
import UniformTypeIdentifiers

final class SelectionPreviewPane: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private final class Node {
        let name: String
        let path: String
        let isDirectory: Bool
        let localURL: URL?
        let canPreviewLocalFile: Bool
        let member: ArchivePreview.Member?
        let contentType: UTType
        let isMediaFile: Bool
        var children: [Node] = []

        init(path: [String], isDirectory: Bool, localURL: URL? = nil, canPreviewLocalFile: Bool = false,
             member: ArchivePreview.Member? = nil) {
            name = path.last ?? ""
            self.path = path.joined(separator: "/")
            self.isDirectory = isDirectory
            self.localURL = localURL
            self.canPreviewLocalFile = canPreviewLocalFile
            self.member = member
            let ext = (name as NSString).pathExtension
            let type = ext.isEmpty ? nil : UTType(filenameExtension: ext)
            contentType = isDirectory ? .folder : type ?? .data
            isMediaFile = !isDirectory && (canPreviewLocalFile || member?.isRegularFile == true) &&
                (contentType.conforms(to: .image) || contentType.conforms(to: .movie))
        }
    }

    private struct Contents {
        var roots: [Node] = []
        var media: [Node] = []
        var isPartial = false
    }

    private final class EntryCell: NSTableCellView {
        var representedNode: Node?
        var request: QLThumbnailGenerator.Request?
        var thumbnailView: NSImageView?
        let lock = NSImageView(image: QingTheme.symbol("lock.fill", size: 11) ?? NSImage())

        func setThumbnail(_ image: NSImage?) {
            thumbnailView?.image = image
            thumbnailView?.isHidden = image == nil
            imageView?.isHidden = image != nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { cancelThumbnail() }
        }

        func cancelThumbnail() {
            if let request { QLThumbnailGenerator.shared.cancel(request) }
            request = nil
        }
    }

    private final class PreviewOutlineView: NSOutlineView {
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53, selectedRow >= 0 {
                deselectAll(nil)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    private let nameLabel = QingTheme.label("Preview")
    private let detailLabel = QingTheme.label("", size: 11, color: .secondaryLabelColor)
    private let mode = NSSegmentedControl(labels: ["Structure", "Media"], trackingMode: .selectOne,
                                          target: nil, action: nil)
    private let content = NSView()
    private let outline = PreviewOutlineView()
    private let scroll = NSScrollView()
    private let viewer = NSView()
    private let viewerDivider = NSBox()
    private let previewSurface = NSView()
    private let imagePreview = NSImageView()
    private var quickLook: QLPreviewView?
    private let message = NSTextField(wrappingLabelWithString: "")
    private lazy var listHeight = scroll.heightAnchor.constraint(equalTo: content.heightAnchor, multiplier: 0.60)
    private lazy var fullListHeight = scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)
    private lazy var emptyListHeight = scroll.heightAnchor.constraint(equalToConstant: 0)
    private var contents: Contents?
    private var selection: URL?
    private var includesHidden = false
    private var temporaryFile: URL?
    private var listingOperation: BlockOperation?
    private var entryOperation: BlockOperation?
    private let work: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private var isMedia: Bool { mode.selectedSegment == 1 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        setAccessibilityLabel("Selection Preview")
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.alignment = .right
        mode.target = self
        mode.action = #selector(changePreviewMode)
        mode.segmentStyle = .rounded
        mode.selectedSegment = 0
        mode.isHidden = true
        mode.setAccessibilityLabel("Preview contents")
        detailLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        mode.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let controls = NSStackView(views: [mode, detailLabel])
        controls.alignment = .centerY
        controls.distribution = .fill
        controls.spacing = 10
        let header = PaneHeaderView(title: nameLabel, controls: controls)
        message.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: 13)
        message.alignment = .center
        message.isSelectable = true
        message.maximumNumberOfLines = 5

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("PreviewEntry"))
        column.title = "Name"
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.intercellSpacing = NSSize(width: 8, height: 0)
        outline.backgroundColor = .controlBackgroundColor
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.style = .plain
        outline.indentationPerLevel = 15
        outline.dataSource = self
        outline.delegate = self
        outline.setAccessibilityLabel("Preview files")
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.backgroundColor = .controlBackgroundColor

        for subview in [header, content] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        for subview in [scroll, viewer] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }
        viewerDivider.boxType = .separator
        for subview in [previewSurface, message, viewerDivider] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            viewer.addSubview(subview)
        }
        previewSurface.wantsLayer = true
        previewSurface.layer?.masksToBounds = true
        imagePreview.frame = previewSurface.bounds
        imagePreview.autoresizingMask = [.width, .height]
        imagePreview.imageScaling = .scaleProportionallyUpOrDown
        imagePreview.setAccessibilityLabel("Image preview")
        imagePreview.isHidden = true
        previewSurface.addSubview(imagePreview)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: header.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 5),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -5),
            viewer.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            viewer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            viewer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            viewer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            previewSurface.topAnchor.constraint(equalTo: viewer.topAnchor, constant: 8),
            previewSurface.leadingAnchor.constraint(equalTo: viewer.leadingAnchor, constant: 8),
            previewSurface.trailingAnchor.constraint(equalTo: viewer.trailingAnchor, constant: -8),
            previewSurface.bottomAnchor.constraint(equalTo: viewer.bottomAnchor, constant: -8),
            viewerDivider.topAnchor.constraint(equalTo: viewer.topAnchor),
            viewerDivider.leadingAnchor.constraint(equalTo: viewer.leadingAnchor),
            viewerDivider.trailingAnchor.constraint(equalTo: viewer.trailingAnchor),
            message.centerYAnchor.constraint(equalTo: viewer.centerYAnchor),
            message.centerXAnchor.constraint(equalTo: viewer.centerXAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: viewer.widthAnchor, constant: -40)
        ])
        show(nil, includeHidden: false, refresh: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        work.cancelAllOperations()
        quickLook?.close()
        if let temporaryFile { try? FileManager.default.removeItem(at: temporaryFile.deletingLastPathComponent()) }
    }

    func show(_ url: URL?, includeHidden: Bool, refresh: Bool = false) {
        if !refresh, selection == url, includesHidden == includeHidden { return }
        listingOperation?.cancel()
        listingOperation = nil
        clearEntry()
        selection = url
        includesHidden = includeHidden
        contents = nil
        mode.isHidden = true
        outline.deselectAll(nil)
        outline.reloadData()
        layoutBody(list: false, preview: true)
        nameLabel.stringValue = url?.lastPathComponent ?? "Preview"
        nameLabel.toolTip = url?.path
        detailLabel.stringValue = ""
        guard let url else {
            setMessage("Select a file or folder in the left pane.")
            return
        }
        setMessage("Loading preview…")
        let operation = BlockOperation()
        listingOperation = operation
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation else { return }
            let result = Result { try Self.load(url, includeHidden: includeHidden, cancelled: { operation.isCancelled }) }
            DispatchQueue.main.async { [weak self, weak operation] in
                guard let self, let operation, self.listingOperation === operation, !operation.isCancelled else { return }
                self.listingOperation = nil
                switch result {
                case .success(.some(let contents)):
                    self.contents = contents
                    self.mode.isHidden = false
                    self.changePreviewMode()
                case .success(.none):
                    self.display(url)
                case .failure(let error):
                    self.setMessage(error.localizedDescription)
                }
            }
        }
        work.addOperation(operation)
    }

    private static func load(_ url: URL, includeHidden: Bool, cancelled: () -> Bool) throws -> Contents? {
        let limit = 10_000
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isRegularFileKey]
        let resolved = url.resolvingSymlinksInPath()
        let selected = try resolved.resourceValues(forKeys: keys)
        var items: [(path: [String], node: Node)] = []
        var isPartial = false
        if selected.isDirectory == true, selected.isPackage != true {
            let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [.skipsPackageDescendants] : [.skipsPackageDescendants, .skipsHiddenFiles]
            var enumerationError: Error?
            guard let enumerator = FileManager.default.enumerator(
                at: resolved, includingPropertiesForKeys: Array(keys), options: options,
                errorHandler: { _, error in enumerationError = error; return false }
            ) else { throw FileServiceError.invalid("Cannot list this folder.") }
            var path: [String] = []
            for case let file as URL in enumerator {
                if cancelled() { throw CancellationError() }
                if items.count == limit { isPartial = true; break }
                let values = try file.resourceValues(forKeys: keys)
                path = Array(path.prefix(enumerator.level - 1))
                path.append(file.lastPathComponent)
                let isFolder = values.isDirectory == true && values.isPackage != true && values.isSymbolicLink != true
                let canPreview = values.isSymbolicLink != true && (values.isRegularFile == true || values.isPackage == true)
                items.append((path, Node(path: path, isDirectory: isFolder, localURL: file, canPreviewLocalFile: canPreview)))
            }
            if let enumerationError { throw enumerationError }
        } else if selected.isRegularFile == true, ArchivePreview.supports(url) {
            let listing = try ArchivePreview.list(url, limit: limit, cancelled: cancelled)
            isPartial = listing.isPartial
            items = listing.members.map { ($0.path, Node(path: $0.path, isDirectory: $0.isDirectory, member: $0)) }
        } else { return nil }

        let root = Node(path: [], isDirectory: true)
        var directories: [[String]: Node] = [[]: root]
        var media: [Node] = []
        for (path, node) in items {
            if cancelled() { throw CancellationError() }
            var prefix: [String] = []
            var parent = root
            for component in path.dropLast() {
                prefix.append(component)
                if let directory = directories[prefix] { parent = directory; continue }
                let directory = Node(path: prefix, isDirectory: true)
                directories[prefix] = directory
                parent.children.append(directory)
                parent = directory
            }
            if node.isDirectory {
                guard directories[path] == nil else { continue }
                directories[path] = node
            }
            if node.isMediaFile { media.append(node) }
            parent.children.append(node)
        }
        for directory in directories.values {
            directory.children.sort { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
        media.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return Contents(roots: root.children, media: media, isPartial: isPartial)
    }

    @objc private func changePreviewMode() {
        guard let contents else { return }
        clearEntry()
        outline.deselectAll(nil)
        outline.rowHeight = isMedia ? 50 : 35
        outline.reloadData()
        let hasItems = !(isMedia ? contents.media : contents.roots).isEmpty
        let count = contents.media.count
        detailLabel.stringValue = "\(count) media item\(count == 1 ? "" : "s")" + (contents.isPartial ? " · First 10,000 entries" : "")
        layoutBody(list: hasItems, preview: !hasItems)
        if hasItems {
            layoutSubtreeIfNeeded()
            let top = -(outline.headerView?.frame.height ?? 0)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: top))
            scroll.reflectScrolledClipView(scroll.contentView)
        } else { setMessage(isMedia ? "No images or videos in this selection." : "This selection is empty.") }
    }

    private func layoutBody(list: Bool, preview: Bool) {
        let height = list ? (preview ? listHeight : fullListHeight) : emptyListHeight
        if !height.isActive {
            NSLayoutConstraint.deactivate([listHeight, fullListHeight, emptyListHeight])
            height.isActive = true
        }
        scroll.isHidden = !list
        viewer.isHidden = !preview
        viewerDivider.isHidden = !(list && preview)
    }

    private func updateEntryLayout(selectedRow: Int?) {
        let showsEntry = selectedRow != nil
        guard listHeight.isActive != showsEntry else { return }
        let clip = scroll.contentView
        let origin = clip.bounds.origin
        layoutBody(list: true, preview: showsEntry)
        layoutSubtreeIfNeeded()
        if clip.bounds.origin != origin {
            var target = clip.bounds
            target.origin = origin
            clip.scroll(to: clip.constrainBoundsRect(target).origin)
            scroll.reflectScrolledClipView(clip)
        }
        if let selectedRow { outline.scrollRowToVisible(selectedRow) }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Node)?.children.count ?? (isMedia ? contents?.media.count : contents?.roots.count) ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? Node { return node.children[index] }
        let roots = isMedia ? contents?.media : contents?.roots
        return roots![index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !isMedia && (item as? Node)?.children.isEmpty == false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let id = NSUserInterfaceItemIdentifier(isMedia ? "Media" : "Structure")
        let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? EntryCell) ?? makeCell(id)
        cell.cancelThumbnail()
        cell.setThumbnail(nil)
        cell.representedNode = node
        cell.textField?.stringValue = node.name
        (cell.viewWithTag(1) as? NSTextField)?.stringValue = node.path
        cell.toolTip = node.path
        if let url = node.localURL { cell.imageView?.image = NSWorkspace.shared.icon(forFile: url.path) }
        else { cell.imageView?.image = NSWorkspace.shared.icon(for: node.contentType) }
        cell.lock.isHidden = node.member?.isEncrypted != true
        if isMedia, node.canPreviewLocalFile, let url = node.localURL {
            requestThumbnail(url, for: node, in: cell)
        }
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> EntryCell {
        let cell = EntryCell()
        cell.identifier = id
        let imageSlot = NSView()
        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        imageSlot.addSubview(icon)
        let title = QingTheme.label("", size: 12, weight: isMedia ? .medium : .regular)
        let text = NSStackView(views: [title])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        if isMedia {
            let thumbnail = NSImageView()
            thumbnail.imageScaling = .scaleProportionallyDown
            thumbnail.translatesAutoresizingMaskIntoConstraints = false
            imageSlot.addSubview(thumbnail)
            NSLayoutConstraint.activate([
                thumbnail.leadingAnchor.constraint(equalTo: imageSlot.leadingAnchor),
                thumbnail.trailingAnchor.constraint(equalTo: imageSlot.trailingAnchor),
                thumbnail.topAnchor.constraint(equalTo: imageSlot.topAnchor),
                thumbnail.bottomAnchor.constraint(equalTo: imageSlot.bottomAnchor)
            ])
            cell.thumbnailView = thumbnail
            let path = QingTheme.label("", size: 10, color: .secondaryLabelColor)
            path.tag = 1
            text.addArrangedSubview(path)
        }
        cell.textField = title
        cell.imageView = icon
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.lock.contentTintColor = .secondaryLabelColor
        cell.lock.toolTip = "Password required"
        cell.lock.setAccessibilityLabel("Password required")
        let row = NSStackView(views: [imageSlot, text, cell.lock])
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageSlot.widthAnchor.constraint(equalToConstant: isMedia ? 64 : 22),
            imageSlot.heightAnchor.constraint(equalToConstant: isMedia ? 42 : 22),
            icon.centerXAnchor.constraint(equalTo: imageSlot.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: imageSlot.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22)
        ])
        return cell
    }

    private func requestThumbnail(_ url: URL, for node: Node, in cell: EntryCell) {
        cell.cancelThumbnail()
        let request = QLThumbnailGenerator.Request(fileAt: url, size: NSSize(width: 64, height: 42),
                                                   scale: window?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        cell.request = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak cell] thumbnail, _ in
            DispatchQueue.main.async {
                guard let cell, cell.request === request, cell.representedNode === node else { return }
                cell.request = nil
                cell.setThumbnail(thumbnail?.nsImage)
            }
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        clearEntry()
        let row = outline.selectedRow
        guard contents != nil else { return }
        guard row >= 0, let node = outline.item(atRow: row) as? Node, !node.isDirectory else {
            updateEntryLayout(selectedRow: nil)
            return
        }
        updateEntryLayout(selectedRow: row)
        if node.canPreviewLocalFile, let url = node.localURL { display(url); return }
        guard let member = node.member, let selection, member.isRegularFile else {
            setMessage("This entry is a link or a special file.")
            return
        }
        setMessage("Reading archive entry…")
        let operation = BlockOperation()
        entryOperation = operation
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation else { return }
            let result = Result { try ArchivePreview.materialize(member, in: selection, cancelled: { operation.isCancelled }) }
            DispatchQueue.main.async { [weak self, weak operation] in
                guard let self, let operation, self.entryOperation === operation, !operation.isCancelled else {
                    if case .success(let file) = result { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
                    return
                }
                self.entryOperation = nil
                switch result {
                case .success(let file):
                    self.temporaryFile = file
                    self.display(file)
                    if self.isMedia, let cell = self.outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? EntryCell {
                        self.requestThumbnail(file, for: node, in: cell)
                    }
                case .failure(let error):
                    self.setMessage(error.localizedDescription)
                }
            }
        }
        work.addOperation(operation)
    }

    private func setMessage(_ text: String) {
        message.stringValue = text
        message.isHidden = false
    }

    private func display(_ url: URL) {
        guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true else {
            displayQuickLook(url)
            return
        }
        setMessage("Loading preview…")
        let operation = BlockOperation()
        entryOperation = operation
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            let image = Self.stillImage(at: url)
            DispatchQueue.main.async { [weak self, weak operation] in
                guard let self, let operation, self.entryOperation === operation, !operation.isCancelled else { return }
                self.entryOperation = nil
                if let image {
                    self.message.isHidden = true
                    self.imagePreview.image = NSImage(cgImage: image, size: .zero)
                    self.imagePreview.isHidden = false
                } else {
                    self.displayQuickLook(url)
                }
            }
        }
        work.addOperation(operation)
    }

    private static func stillImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1 else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private func displayQuickLook(_ url: URL) {
        guard let preview = QLPreviewView(frame: previewSurface.bounds, style: .normal) else {
            setMessage("Quick Look is unavailable.")
            return
        }
        message.isHidden = true
        quickLook = preview
        preview.shouldCloseWithWindow = false
        preview.autostarts = false
        preview.autoresizingMask = [.width, .height]
        previewSurface.addSubview(preview)
        preview.previewItem = url as NSURL
    }

    private func clearEntry() {
        entryOperation?.cancel()
        entryOperation = nil
        quickLook?.close()
        quickLook?.removeFromSuperview()
        quickLook = nil
        imagePreview.image = nil
        imagePreview.isHidden = true
        if let temporaryFile { try? FileManager.default.removeItem(at: temporaryFile.deletingLastPathComponent()) }
        temporaryFile = nil
    }
}
