import AppKit
import Quartz

@main
struct QingFilesMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = QingAppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

final class QingAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var window: NSWindow!
    private var root = NSView()
    private var sidebarStack = TopAlignedStackView()
    private var paneContainer = NSStackView()
    private var sidebarButtons: [SidebarButton] = []
    private var panes: [FilePane] = []
    private var activeIndex = 0
    private var layoutSwitch: NSSegmentedControl!
    private var hiddenButton: NSButton!
    private var statusLabel = QingTheme.label("Ready", size: 11, color: .secondaryLabelColor)
    private var activityIndicator = NSProgressIndicator()
    private var operationBusy = false
    private var clipboardCutChangeCount: Int?
    private var previewURLs: [URL] = []
    private var previewPanel: QLPreviewPanel?
    private var userFavorites: [String] = []
    private var remoteWorkspace: RemoteWorkspace?
    private var isPreview: Bool { argument("--preview") != nil }
    private var fourPanes = false
    private let worker = DispatchQueue(label: "local.qingfiles.operations", qos: .userInitiated)
    private var activePane: FilePane { panes[activeIndex] }
    private var otherPane: FilePane { panes[activeIndex ^ 1] }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        buildMenu()
        if !isPreview { userFavorites = UserDefaults.standard.stringArray(forKey: "favorites") ?? [] }
        createWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if isPreview { schedulePreview() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !operationBusy { panes.forEach { $0.refresh() } }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if operationBusy || remoteWorkspace?.isBusy == true {
            showMessage("File operation in progress", "Wait for the current operation to finish before quitting.")
            return .terminateCancel
        }
        saveState()
        return .terminateNow
    }

    func windowWillClose(_ notification: Notification) { saveState() }

    private func saveState() {
        guard !isPreview else { return }
        UserDefaults.standard.set(panes.map { $0.currentDirectory.path }, forKey: "locations")
        UserDefaults.standard.set(fourPanes, forKey: "fourPanes")
        UserDefaults.standard.set(hiddenButton.state == .on, forKey: "showHidden")
    }

    private func argument(_ flag: String) -> String? {
        if let index = CommandLine.arguments.firstIndex(of: flag), CommandLine.arguments.indices.contains(index + 1) {
            return CommandLine.arguments[index + 1]
        }
        // A separately packaged QA copy can start fixtures through Launch Services.
        if flag == "--preview" { return Bundle.main.object(forInfoDictionaryKey: "QingPreviewPath") as? String }
        if flag == "--snapshot" { return Bundle.main.object(forInfoDictionaryKey: "QingSnapshotPath") as? String }
        return nil
    }

    private func createWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "QingFiles"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = QingTheme.background
        window.minSize = NSSize(width: 1180, height: 640)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        if !isPreview { window.setFrameAutosaveName("QingFiles.Main") }
        root.wantsLayer = true
        root.layer?.backgroundColor = QingTheme.background.cgColor
        window.contentView = root

        let header = makeHeader()
        root.addSubview(header)
        let sidebarScroll = NSScrollView()
        sidebarScroll.drawsBackground = false
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.autohidesScrollers = true
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 4
        sidebarStack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 20, right: 14)
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.documentView = sidebarStack
        root.addSubview(sidebarScroll)
        sidebarStack.widthAnchor.constraint(equalTo: sidebarScroll.widthAnchor).isActive = true
        paneContainer.orientation = .vertical
        paneContainer.alignment = .leading
        paneContainer.distribution = .fillEqually
        paneContainer.spacing = 1
        paneContainer.wantsLayer = true
        paneContainer.layer?.cornerRadius = QingTheme.panelRadius
        paneContainer.layer?.masksToBounds = true
        paneContainer.layer?.backgroundColor = QingTheme.hairline.cgColor
        root.addSubview(paneContainer)
        let footer = makeFooter()
        root.addSubview(footer)
        for view in [header, sidebarScroll, paneContainer, footer] { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor), header.leadingAnchor.constraint(equalTo: root.leadingAnchor), header.trailingAnchor.constraint(equalTo: root.trailingAnchor), header.heightAnchor.constraint(equalToConstant: 62),
            sidebarScroll.topAnchor.constraint(equalTo: header.bottomAnchor), sidebarScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), sidebarScroll.widthAnchor.constraint(equalToConstant: 198), sidebarScroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            paneContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2), paneContainer.leadingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor, constant: 4), paneContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16), paneContainer.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor), footer.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor), footer.bottomAnchor.constraint(equalTo: root.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 30)
        ])
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaults = [home, home.appendingPathComponent("Downloads"), home.appendingPathComponent("Documents"), URL(fileURLWithPath: "/")]
        let saved = isPreview ? [] : (UserDefaults.standard.stringArray(forKey: "locations") ?? [])
        let fixture = argument("--preview").map { URL(fileURLWithPath: $0) }
        for index in 0..<4 {
            let candidate: URL
            if let fixture { candidate = fixture.appendingPathComponent(["Workspace", "Library", "Workspace/Climate Research", "Library/Paper Notes"][index]) }
            else if saved.indices.contains(index) { candidate = URL(fileURLWithPath: saved[index]) }
            else { candidate = defaults[index] }
            var isDirectory: ObjCBool = false
            let initial = FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) && isDirectory.boolValue ? candidate : home
            let pane = FilePane(directory: initial, title: ["Left", "Right", "Bottom Left", "Bottom Right"][index])
            pane.onActivate = { [weak self] selected in self?.activate(selected) }
            pane.onDirectoryChanged = { [weak self] _ in self?.updateLocations(); self?.saveState() }
            pane.onSelectionChanged = { [weak self] _ in self?.updateStatus() }
            pane.onAction = { [weak self] pane, action in self?.activate(pane); self?.handle(action) }
            panes.append(pane)
            _ = pane.view
            pane.showsHidden = hiddenButton.state == .on
        }
        rebuildSidebar()
        fourPanes = !isPreview && UserDefaults.standard.bool(forKey: "fourPanes")
        layoutSwitch.selectedSegment = fourPanes ? 1 : 0
        rebuildPanes()
        activate(panes[0])
    }

    private func makeHeader() -> NSView {
        let header: NSView
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency { header = NSView() }
        else { let material = NSVisualEffectView(); material.material = .headerView; material.blendingMode = .behindWindow; header = material }
        let icon = NSImageView(image: QingTheme.symbol("rectangle.split.2x2.fill", size: 26) ?? NSImage())
        icon.contentTintColor = QingTheme.accent
        let title = QingTheme.label("QingFiles", size: 21, weight: .semibold)
        let subtitle = QingTheme.label("LOCAL & REMOTE", size: 9, weight: .semibold, color: .secondaryLabelColor)
        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical; titleStack.alignment = .leading; titleStack.spacing = 1
        let brand = NSStackView(views: [icon, titleStack]); brand.spacing = 10
        header.addSubview(brand)
        layoutSwitch = NSSegmentedControl(labels: ["2 Panes", "4 Panes"], trackingMode: .selectOne, target: self, action: #selector(changeLayout))
        layoutSwitch.segmentStyle = .rounded
        layoutSwitch.setWidth(67, forSegment: 0); layoutSwitch.setWidth(67, forSegment: 1)
        let newFolder = QingTheme.button("New Folder", symbol: "folder.badge.plus", target: self, action: #selector(newFolderAction))
        let copyAcross = QingTheme.button("Copy Across", symbol: "doc.on.doc", target: self, action: #selector(copyOtherAction))
        let moveAcross = QingTheme.button("Move", symbol: "arrow.right.square", target: self, action: #selector(moveOtherAction))
        moveAcross.toolTip = "Move selected items to the folder in the paired pane"
        let preview = QingTheme.button("Preview", symbol: "eye", target: self, action: #selector(previewAction))
        hiddenButton = QingTheme.button("Hidden", symbol: "eye.slash", target: self, action: #selector(toggleHidden))
        hiddenButton.setButtonType(.toggle)
        hiddenButton.state = !isPreview && UserDefaults.standard.bool(forKey: "showHidden") ? .on : .off
        hiddenButton.toolTip = "Show or hide hidden items · ⌘⇧."
        let connect = QingTheme.button("Connect", symbol: "network", target: self, action: #selector(connectionsAction))
        connect.contentTintColor = QingTheme.accent
        let refresh = QingTheme.button("", symbol: "arrow.clockwise", target: self, action: #selector(refreshAction))
        refresh.toolTip = "Refresh the current folder · ⌘R"
        let toolbar = NSStackView(views: [layoutSwitch, copyAcross, moveAcross, newFolder, preview, hiddenButton, connect, refresh])
        toolbar.spacing = 8
        header.addSubview(toolbar)
        brand.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([brand.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 22), brand.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: -2), toolbar.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16), toolbar.centerYAnchor.constraint(equalTo: header.centerYAnchor), toolbar.leadingAnchor.constraint(greaterThanOrEqualTo: brand.trailingAnchor, constant: 20)])
        return header
    }

    private func makeFooter() -> NSView {
        let footer = NSView()
        activityIndicator.style = .spinning; activityIndicator.controlSize = .small; activityIndicator.isDisplayedWhenStopped = false
        let stack = NSStackView(views: [activityIndicator, statusLabel]); stack.spacing = 6
        footer.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        let hint = QingTheme.label("Space to preview  ·  ⌘L to edit path", size: 10, color: .tertiaryLabelColor)
        footer.addSubview(hint); hint.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor), stack.centerYAnchor.constraint(equalTo: footer.centerYAnchor), hint.trailingAnchor.constraint(equalTo: footer.trailingAnchor), hint.centerYAnchor.constraint(equalTo: footer.centerYAnchor), stack.trailingAnchor.constraint(lessThanOrEqualTo: hint.leadingAnchor, constant: -12)])
        return footer
    }

    private func rebuildSidebar() {
        sidebarStack.arrangedSubviews.forEach { sidebarStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        sidebarButtons.removeAll()
        func section(_ text: String) {
            let label = QingTheme.label(text, size: 10, weight: .semibold, color: .secondaryLabelColor)
            let spacer = NSView(); spacer.translatesAutoresizingMaskIntoConstraints = false; spacer.heightAnchor.constraint(equalToConstant: 12).isActive = true
            sidebarStack.addArrangedSubview(spacer); sidebarStack.addArrangedSubview(label)
            sidebarStack.setCustomSpacing(8, after: label)
        }
        func location(_ title: String, _ symbol: String, _ url: URL, custom: Bool = false) {
            let button = SidebarButton(frame: .zero)
            button.title = "  " + title
            button.image = QingTheme.symbol(symbol)
            button.location = url; button.target = self; button.action = #selector(sidebarClick(_:))
            button.toolTip = url.path
            if custom {
                let menu = NSMenu()
                let item = NSMenuItem(title: "Remove Favorite", action: #selector(removeFavorite(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = url.path; menu.addItem(item); button.menu = menu
            }
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor, constant: -28).isActive = true
            sidebarButtons.append(button)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        section("Locations")
        location("Home", "house", home)
        location("Desktop", "desktopcomputer", home.appendingPathComponent("Desktop"))
        location("Documents", "doc.text", home.appendingPathComponent("Documents"))
        location("Downloads", "arrow.down.circle", home.appendingPathComponent("Downloads"))
        location("Applications", "square.grid.2x2", URL(fileURLWithPath: "/Applications"))
        section("Devices & System")
        location("Root  /", "internaldrive", URL(fileURLWithPath: "/"))
        location("Volumes", "externaldrive", URL(fileURLWithPath: "/Volumes"))
        location("User Library", "books.vertical", home.appendingPathComponent("Library"))
        section("Favorites")
        if isPreview, let fixture = argument("--preview") {
            location("Workspace", "folder", URL(fileURLWithPath: fixture).appendingPathComponent("Workspace"))
            location("Library", "folder", URL(fileURLWithPath: fixture).appendingPathComponent("Library"))
        } else if userFavorites.isEmpty {
            let label = QingTheme.label("Open a folder, then click Favorite", size: 10, color: .tertiaryLabelColor)
            label.maximumNumberOfLines = 2; sidebarStack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalToConstant: 170).isActive = true
        } else {
            for path in userFavorites {
                let url = URL(fileURLWithPath: path)
                location(url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent, "folder", url, custom: true)
            }
        }
        updateLocations()
    }

    private func rebuildPanes() {
        panes.forEach { $0.view.removeFromSuperview() }
        paneContainer.arrangedSubviews.forEach { paneContainer.removeArrangedSubview($0); $0.removeFromSuperview() }
        for rowIndex in 0..<(fourPanes ? 2 : 1) {
            let row = NSStackView(views: [panes[rowIndex * 2].view, panes[rowIndex * 2 + 1].view])
            row.orientation = .horizontal; row.distribution = .fillEqually; row.alignment = .height; row.spacing = 1
            paneContainer.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: paneContainer.widthAnchor).isActive = true
        }
        if !fourPanes && activeIndex >= 2 { activeIndex = 0 }
        activate(panes[activeIndex])
    }

    private func activate(_ pane: FilePane) {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return }
        activeIndex = index
        for (i, pane) in panes.enumerated() { pane.isActive = i == index }
        updateLocations(); updateStatus()
    }

    private func updateLocations() {
        guard !panes.isEmpty else { return }
        for button in sidebarButtons { button.selectedLocation = button.location?.standardizedFileURL == activePane.currentDirectory.standardizedFileURL }
        window?.representedURL = activePane.currentDirectory
    }

    private func updateStatus() {
        guard !panes.isEmpty, !operationBusy else { return }
        let count = activePane.selectedURLs.count
        statusLabel.stringValue = count > 0 ? "\(count) selected · Paired destination: \(otherPane.currentDirectory.lastPathComponent)" : "Local workspace · Click a pane to start browsing"
    }

    @objc private func connectionsAction(_ sender: Any?) {
        if remoteWorkspace == nil { remoteWorkspace = RemoteWorkspace(localDirectory: activePane.currentDirectory) }
        remoteWorkspace?.showWindow(nil)
        remoteWorkspace?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func sidebarClick(_ sender: SidebarButton) { if let url = sender.location { activePane.navigate(to: url) } }
    @objc private func changeLayout(_ sender: Any?) { fourPanes = layoutSwitch.selectedSegment == 1; rebuildPanes(); saveState() }
    @objc private func toggleHidden(_ sender: Any?) {
        if !(sender is NSButton) { hiddenButton.state = hiddenButton.state == .on ? .off : .on }
        panes.forEach { $0.showsHidden = hiddenButton.state == .on }; saveState()
    }
    @objc private func refreshAction(_ sender: Any?) { activePane.refresh() }
    @objc private func focusPathAction(_ sender: Any?) { activePane.focusPath() }
    @objc private func focusSearchAction(_ sender: Any?) { activePane.focusSearch() }
    @objc private func rootAction(_ sender: Any?) { activePane.navigate(to: URL(fileURLWithPath: "/")) }
    @objc private func homeAction(_ sender: Any?) { activePane.navigate(to: FileManager.default.homeDirectoryForCurrentUser) }
    @objc private func backAction(_ sender: Any?) { activePane.goBack() }
    @objc private func forwardAction(_ sender: Any?) { activePane.goForward() }
    @objc private func upAction(_ sender: Any?) { activePane.goUp() }
    @objc private func newFolderAction(_ sender: Any?) { handle("newFolder") }
    @objc private func renameAction(_ sender: Any?) { handle("rename") }
    @objc private func trashAction(_ sender: Any?) { handle("trash") }
    @objc private func previewAction(_ sender: Any?) { handle("preview") }
    @objc private func openAction(_ sender: Any?) { handle("open") }
    @objc private func copyOtherAction(_ sender: Any?) { handle("copyToOther") }
    @objc private func moveOtherAction(_ sender: Any?) { handle("moveToOther") }
    @objc private func copyPathAction(_ sender: Any?) { handle("copyPath") }
    @objc private func favoriteAction(_ sender: Any?) { handle("favorite") }
    @objc func copy(_ sender: Any?) { handle("copy") }
    @objc func cut(_ sender: Any?) { handle("cut") }
    @objc func paste(_ sender: Any?) { handle("paste") }
    @objc private func pasteMove(_ sender: Any?) { pasteFiles(forceMove: true) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard !panes.isEmpty else { return false }
        if let keyWindow = NSApp.keyWindow, keyWindow !== window { return false }
        if window.attachedSheet != nil { return false }
        let fileActions: [Selector] = [#selector(trashAction), #selector(renameAction), #selector(pasteMove), #selector(copyOtherAction), #selector(moveOtherAction), #selector(openAction), #selector(previewAction)]
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
           let action = menuItem.action, fileActions.contains(action) { return false }
        let mutations: [Selector] = [#selector(trashAction), #selector(renameAction), #selector(pasteMove), #selector(copyOtherAction), #selector(moveOtherAction), #selector(newFolderAction)]
        if operationBusy, let action = menuItem.action, mutations.contains(action) { return false }
        let needsSelection: [Selector] = [#selector(trashAction), #selector(renameAction), #selector(copyOtherAction), #selector(moveOtherAction), #selector(openAction), #selector(previewAction)]
        if let action = menuItem.action, needsSelection.contains(action), activePane.selectedURLs.isEmpty { return false }
        if menuItem.action == #selector(renameAction) { return activePane.selectedURLs.count == 1 }
        return true
    }

    private func handle(_ action: String) {
        guard window.attachedSheet == nil, NSApp.keyWindow === window else { return }
        let selected = activePane.selectedURLs
        switch action {
        case "open":
            guard let url = selected.first else { NSSound.beep(); return }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue, !NSWorkspace.shared.isFilePackage(atPath: url.path) { activePane.navigate(to: url) }
            else { NSWorkspace.shared.open(url) }
        case "preview": showPreview(selected)
        case "copy", "cut":
            guard !selected.isEmpty else { NSSound.beep(); return }
            let board = NSPasteboard.general
            board.clearContents(); board.writeObjects(selected.map { $0 as NSURL })
            clipboardCutChangeCount = action == "cut" ? board.changeCount : nil
            statusLabel.stringValue = action == "cut" ? "Ready to move \(selected.count) item(s). Press ⌘V in the destination." : "Copied \(selected.count) item(s). Press ⌘V in the destination."
        case "paste": pasteFiles(forceMove: false)
        case "pasteMove": pasteFiles(forceMove: true)
        case "copyToOther", "moveToOther":
            guard !selected.isEmpty else { NSSound.beep(); return }
            transfer(selected, to: otherPane.currentDirectory, mode: action == "copyToOther" ? .copy : .move)
        case "copyPath":
            let paths = (selected.isEmpty ? [activePane.currentDirectory] : selected).map(\.path).joined(separator: "\n")
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(paths, forType: .string)
            clipboardCutChangeCount = nil; statusLabel.stringValue = "Path copied"
        case "newFolder":
            guard !operationBusy else { NSSound.beep(); return }
            let parent = activePane.currentDirectory
            askName(title: "New Folder", message: "Location: \(parent.path)", value: "Untitled Folder") { [weak self] name in
                do { _ = try FileService.createDirectory(named: name, in: parent); self?.refreshAll() }
                catch { self?.showMessage("Cannot Create Folder", error.localizedDescription) }
            }
        case "rename":
            guard !operationBusy, selected.count == 1, let source = selected.first else { NSSound.beep(); return }
            askName(title: "Rename", message: source.lastPathComponent, value: source.lastPathComponent) { [weak self] name in
                do { _ = try FileService.rename(source, to: name); self?.refreshAll() }
                catch { self?.showMessage("Cannot Rename Item", error.localizedDescription) }
            }
        case "trash":
            guard !operationBusy, !selected.isEmpty else { NSSound.beep(); return }
            let alert = NSAlert(); alert.messageText = "Move \(selected.count) item(s) to Trash?"
            alert.informativeText = selected.prefix(8).map(\.lastPathComponent).joined(separator: "\n") + (selected.count > 8 ? "\n…" : "") + "\n\nItems can be restored from Trash in Finder."
            alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn { self?.runOperation("Moving to Trash…") { FileService.trash(selected) } }
            }
        case "favorite":
            let path = activePane.currentDirectory.path
            if !userFavorites.contains(path) { userFavorites.append(path) }
            if !isPreview { UserDefaults.standard.set(userFavorites, forKey: "favorites") }
            rebuildSidebar(); statusLabel.stringValue = "Current folder added to Favorites"
        case "terminal":
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
            NSWorkspace.shared.open([activePane.currentDirectory], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        default: break
        }
    }

    private func pasteFiles(forceMove: Bool) {
        let board = NSPasteboard.general
        guard let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { NSSound.beep(); return }
        let moving = forceMove || clipboardCutChangeCount == board.changeCount
        transfer(urls, to: activePane.currentDirectory, mode: moving ? .move : .copy, clipboard: moving)
    }

    private func transfer(_ sources: [URL], to destination: URL, mode: FileTransferMode, clipboard: Bool = false) {
        let moving = mode == .move
        let originalBoardCount = NSPasteboard.general.changeCount
        runOperation("\(moving ? "Moving" : "Copying") \(sources.count) item(s) → \(destination.lastPathComponent)…", completion: { [weak self] report in
            guard clipboard, NSPasteboard.general.changeCount == originalBoardCount else { return }
            let board = NSPasteboard.general
            board.clearContents()
            if !report.failures.isEmpty {
                board.writeObjects(report.failures.map { $0.source as NSURL }); self?.clipboardCutChangeCount = board.changeCount
            } else { self?.clipboardCutChangeCount = nil }
        }) { FileService.transfer(sources, to: destination, mode: mode) }
    }

    private func runOperation(_ message: String, completion: ((FileOperationReport) -> Void)? = nil, work: @escaping () -> FileOperationReport) {
        guard !operationBusy else { NSSound.beep(); return }
        operationBusy = true; statusLabel.stringValue = message; activityIndicator.startAnimation(nil)
        worker.async { [weak self] in
            let report = work()
            DispatchQueue.main.async {
                guard let self else { return }
                self.operationBusy = false; self.activityIndicator.stopAnimation(nil)
                completion?(report); self.refreshAll()
                self.statusLabel.stringValue = "Completed \(report.succeeded.count) item(s)" + (report.failures.isEmpty ? "" : " · \(report.failures.count) failed")
                if !report.failures.isEmpty {
                    let detail = report.failures.prefix(12).map { "\($0.source.lastPathComponent): \($0.message)" }.joined(separator: "\n\n")
                    self.showMessage("Some items could not be processed", detail + (report.failures.count > 12 ? "\n\n\(report.failures.count - 12) additional item(s) failed." : ""))
                }
            }
        }
    }

    private func refreshAll() { panes.forEach { $0.refresh() } }
    private func askName(title: String, message: String, value: String, completion: @escaping (String) -> Void) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        let field = NSTextField(string: value); field.frame = NSRect(x: 0, y: 0, width: 380, height: 26)
        alert.accessoryView = field; alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { completion(field.stringValue) } }
    }
    private func showMessage(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message; alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }
    @objc private func removeFavorite(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        userFavorites.removeAll { $0 == path }
        if !isPreview { UserDefaults.standard.set(userFavorites, forKey: "favorites") }
        rebuildSidebar()
    }

    private func showPreview(_ urls: [URL]) {
        guard !urls.isEmpty else { NSSound.beep(); return }
        if previewPanel?.isVisible == true { previewPanel?.orderOut(nil); return }
        previewURLs = urls
        previewPanel = QLPreviewPanel.shared()
        previewPanel?.makeKeyAndOrderFront(nil)
        previewPanel?.updateController()
        if previewPanel?.currentController as AnyObject? === self { previewPanel?.reloadData() }
    }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self; panel.delegate = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { previewURLs[index] as NSURL }

    private func buildMenu() {
        let menu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); item.title = title
            let sub = NSMenu(title: title); item.submenu = sub; menu.addItem(item); return sub
        }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", _ flags: NSEvent.ModifierFlags = [.command], responder: Bool = false) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.keyEquivalentModifierMask = flags
            item.target = responder ? nil : self; menu.addItem(item)
        }
        let app = submenu("QingFiles")
        item(app, "About QingFiles", #selector(aboutAction))
        app.addItem(.separator())
        let quit = NSMenuItem(title: "Quit QingFiles", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); quit.target = NSApp; app.addItem(quit)
        let file = submenu("File")
        item(file, "Open", #selector(openAction), "o")
        item(file, "Quick Look", #selector(previewAction), "y")
        item(file, "New Folder…", #selector(newFolderAction), "n", [.command, .shift])
        item(file, "Rename…", #selector(renameAction), "r", [.command, .shift])
        file.addItem(.separator())
        item(file, "Copy Across", #selector(copyOtherAction), "c", [.command, .option])
        item(file, "Move Across", #selector(moveOtherAction), "m", [.command, .option])
        item(file, "Move to Trash…", #selector(trashAction), "\u{8}")
        let edit = submenu("Edit")
        item(edit, "Cut", #selector(cut(_:)), "x", responder: true)
        item(edit, "Copy", #selector(copy(_:)), "c", responder: true)
        item(edit, "Paste", #selector(paste(_:)), "v", responder: true)
        item(edit, "Move Pasted Files", #selector(pasteMove), "v", [.command, .option])
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a", responder: true)
        edit.addItem(.separator())
        item(edit, "Copy Path", #selector(copyPathAction), "c", [.command, .shift])
        let view = submenu("View")
        item(view, "Show/Hide Hidden Items", #selector(toggleHidden), ".", [.command, .shift])
        item(view, "Refresh", #selector(refreshAction), "r")
        item(view, "Search Current Folder", #selector(focusSearchAction), "f")
        let connections = submenu("Connections")
        item(connections, "Remote Workspace…", #selector(connectionsAction), "k", [.command, .shift])
        let go = submenu("Go")
        item(go, "Edit Path", #selector(focusPathAction), "l")
        item(go, "Root", #selector(rootAction), "/", [.command, .shift])
        item(go, "Home", #selector(homeAction), "h", [.command, .shift])
        item(go, "Parent Folder", #selector(upAction), String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command])
        item(go, "Back", #selector(backAction), "[")
        item(go, "Forward", #selector(forwardAction), "]")
        item(go, "Favorite Current Folder", #selector(favoriteAction), "d")
        let win = submenu("Window")
        let close = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"); win.addItem(close)
        let min = NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"); win.addItem(min)
        NSApp.windowsMenu = win
        NSApp.mainMenu = menu
    }
    @objc private func aboutAction(_ sender: Any?) {
        showMessage("QingFiles 1.2", "A free native file manager for macOS.\n\nTwo or four panes, path navigation, hidden files, and Quick Look.\n\nBuilt with Swift and AppKit. No third-party dependencies. File operations run locally.\nSource code is available under the MIT License.")
    }

    // Only used by the build's UI smoke test; it renders the real AppKit views.
    private func schedulePreview() {
        guard let output = argument("--snapshot") else { return }
        afterPanesLoad { [weak self] in
            guard let self else { return }
            self.window.makeFirstResponder(nil)
            self.saveSnapshot(output)
            self.layoutSwitch.selectedSegment = 1; self.changeLayout(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.saveSnapshot((output as NSString).deletingPathExtension + "-four.png")
                if let fixture = self.argument("--preview") {
                    self.showPreview([URL(fileURLWithPath: fixture).appendingPathComponent("Workspace/README.md")])
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let previewOK = self.previewPanel?.isVisible == true && (self.previewPanel?.currentController as AnyObject? === self)
                    self.previewPanel?.orderOut(nil)
                    self.layoutSwitch.selectedSegment = 0; self.changeLayout(nil)
                    self.afterPanesLoad {
                        self.window.makeFirstResponder(nil)
                        self.saveSnapshot(output)
                        if Bundle.main.object(forInfoDictionaryKey: "QingSnapshotConnections") as? Bool == true {
                            self.connectionsAction(nil)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                if let view = self.remoteWorkspace?.window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                                    view.layoutSubtreeIfNeeded(); view.cacheDisplay(in: view.bounds, to: bitmap)
                                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: (output as NSString).deletingPathExtension + "-connections.png"))
                                }
                            }
                        }
                    }
                    let report = "UI smoke: double-pane and four-pane rendered; Quick Look controller=\(previewOK); frame=\(self.window.frame.size)\n"
                    try? report.write(toFile: (output as NSString).deletingPathExtension + "-check.txt", atomically: true, encoding: .utf8)
                    print(report)
                    if Bundle.main.object(forInfoDictionaryKey: "QingPreviewStayOpen") as? Bool != true { NSApp.terminate(nil) }
                }
            }
        }
    }
    private func afterPanesLoad(attempt: Int = 0, action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if self.panes.contains(where: { $0.isLoading }), attempt < 100 {
                self.afterPanesLoad(attempt: attempt + 1, action: action)
            } else { action() }
        }
    }
    private func saveSnapshot(_ path: String) {
        root.layoutSubtreeIfNeeded(); root.displayIfNeeded()
        guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { print("SNAPSHOT_FAILED"); return }
        root.cacheDisplay(in: root.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            do { try data.write(to: URL(fileURLWithPath: path)); print("SNAPSHOT_OK \(path)") }
            catch { print("SNAPSHOT_FAILED \(error.localizedDescription)") }
        }
    }
}
