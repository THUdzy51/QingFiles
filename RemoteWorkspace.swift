import AppKit
import UniformTypeIdentifiers

final class RemoteWorkspace: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    let remoteView = NSView()
    var onConnectionChanged: (() -> Void)?
    var canTransfer: (() -> Bool)?
    var isConnected: Bool { service != nil }
    var isBusy: Bool { working }
    var hasFocus: Bool {
        let responder = remoteView.window?.firstResponder
        if let editor = responder as? NSTextView, editor.isFieldEditor {
            return (editor.delegate as? NSView)?.isDescendant(of: remoteView) == true
        }
        return (responder as? NSView)?.isDescendant(of: remoteView) == true
    }

    private let local: FilePane
    private let table = NSTableView()
    private let profilePicker = NSPopUpButton()
    private let kind = NSPopUpButton()
    private let name = NSTextField(string: "New Connection")
    private let host = NSTextField(string: "")
    private let port = NSTextField(string: "22")
    private let username = NSTextField(string: "")
    private let password = NSSecureTextField(string: "")
    private let identity = NSTextField(string: "")
    private let initialPath = NSTextField(string: "/")
    private let path = NSTextField(string: "/")
    private let remember = NSButton(checkboxWithTitle: "Save password in Keychain", target: nil, action: nil)
    private let connectionMessage = QingTheme.label("", size: 11, color: .secondaryLabelColor)
    private let remoteMessage = QingTheme.label("", size: 11, color: .secondaryLabelColor)
    private let remoteTitle = QingTheme.label("Remote")
    private let progress = NSProgressIndicator()
    private let hidden = NSButton(checkboxWithTitle: "Hidden items", target: nil, action: nil)
    private lazy var cancel = button("Cancel Transfer", "xmark.circle", #selector(cancelAction))
    private var remoteControls: [NSControl] = []
    private var formControls: [NSControl] = []
    private var allEntries: [RemoteEntry] = []
    private var entries: [RemoteEntry] = []
    private var profiles: [RemoteProfile] = []
    private var profileID = UUID().uuidString
    private var service: RemoteService?
    private var cancellation: RemoteCancellation?
    private let queue = DispatchQueue(label: "local.qingfiles.remote", qos: .userInitiated)
    private var working = false
    private var remoteDirectory = "/"
    private let preferencesKey = "remoteConnections.v1"
    private static let remoteFile = NSPasteboard.PasteboardType("local.qingfiles.remote-file")

    init(local: FilePane) {
        self.local = local
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 700, height: 274),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Connect to Server"
        panel.backgroundColor = QingTheme.background
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self
        if let data = UserDefaults.standard.data(forKey: preferencesKey) {
            profiles = (try? JSONDecoder().decode([RemoteProfile].self, from: data)) ?? []
        }
        buildConnectionForm(in: panel)
        buildRemotePane()
        updateControls()
        local.registerRemoteDropType(Self.remoteFile)
        local.prepareRemoteDrop = { [weak self] info in self?.prepareDownload(info) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showConnectionForm(over parent: NSWindow) {
        guard let window else { return }
        if !window.isVisible {
            if !profiles.isEmpty, profilePicker.indexOfSelectedItem > 0 { loadProfile(nil) }
            let parentFrame = parent.frame
            window.setFrameOrigin(NSPoint(x: parentFrame.midX - window.frame.width / 2,
                                          y: parentFrame.midY - window.frame.height / 2))
        }
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if working {
            if let cancellation {
                cancellation.cancel()
                setMessage("Cancelling the connection…")
            }
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        password.stringValue = ""
    }

    private func buildConnectionForm(in window: NSWindow) {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = QingTheme.background.cgColor
        window.contentView = root
        profilePicker.target = self
        profilePicker.action = #selector(loadProfile)
        updatePicker()
        kind.addItems(withTitles: ["SFTP", "FTPS", "FTP"])
        kind.target = self
        kind.action = #selector(protocolChanged)
        host.placeholderString = "server.example.com"
        password.placeholderString = "Password or key passphrase"
        identity.placeholderString = "Optional, e.g. ~/.ssh/id_ed25519"
        let form = NSGridView(views: [
            [QingTheme.label("Saved connection"), profilePicker, QingTheme.label("Protocol"), kind],
            [QingTheme.label("Name"), name, QingTheme.label("Port"), port],
            [QingTheme.label("Host"), host, QingTheme.label("Username"), username],
            [QingTheme.label("Password"), password, QingTheme.label("Identity file"), identity],
            [QingTheme.label("Remote folder"), initialPath, remember, NSGridCell.emptyContentView]
        ])
        form.mergeCells(inHorizontalRange: NSRange(location: 2, length: 2), verticalRange: NSRange(location: 4, length: 1))
        form.rowSpacing = 9
        form.columnSpacing = 10
        form.xPlacement = .fill
        form.column(at: 0).xPlacement = .leading
        form.column(at: 2).xPlacement = .leading
        form.column(at: 0).width = 114
        form.column(at: 2).width = 88
        for field in [name, host, port, username, password, identity, initialPath, path] {
            field.bezelStyle = .roundedBezel
            field.usesSingleLineMode = true
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        host.widthAnchor.constraint(equalTo: username.widthAnchor).isActive = true
        let save = button("Save Connection", "square.and.arrow.down", #selector(saveProfile))
        let verify = button("Verify SSH Host…", "checkmark.shield", #selector(verifyHost))
        let terminal = button("SSH Terminal", "terminal", #selector(openTerminal))
        let close = button("Cancel", nil, #selector(closeForm))
        close.keyEquivalent = "\u{1b}"
        let connect = button("Connect", "network", #selector(connectAction))
        connect.keyEquivalent = "\r"
        let spacer = NSView()
        let controls = NSStackView(views: [save, verify, terminal, spacer, close, connect])
        controls.spacing = 8
        let note = QingTheme.label("Plain FTP sends credentials and file data without encryption.", size: 11, color: .secondaryLabelColor)
        connectionMessage.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [form, note, controls, connectionMessage] {
            root.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            form.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            form.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            note.topAnchor.constraint(equalTo: form.bottomAnchor, constant: 12),
            note.leadingAnchor.constraint(equalTo: form.leadingAnchor),
            connectionMessage.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 8),
            connectionMessage.leadingAnchor.constraint(equalTo: form.leadingAnchor),
            connectionMessage.trailingAnchor.constraint(equalTo: form.trailingAnchor),
            controls.topAnchor.constraint(greaterThanOrEqualTo: connectionMessage.bottomAnchor, constant: 8),
            controls.leadingAnchor.constraint(equalTo: form.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: form.trailingAnchor),
            controls.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -15)
        ])
        formControls = [profilePicker, kind, name, host, port, username, password, identity, initialPath, remember, save, verify, connect, terminal]
        window.initialFirstResponder = host
    }

    private func buildRemotePane() {
        remoteView.wantsLayer = true
        remoteView.layer?.backgroundColor = QingTheme.surface.cgColor
        remoteView.setAccessibilityLabel("Remote file pane")
        let up = navigationButton("arrow.up", title: "Remote parent folder", action: #selector(upAction))
        let refresh = navigationButton("arrow.clockwise", title: "Refresh remote folder", action: #selector(refreshAction))
        path.target = self
        path.action = #selector(goAction)
        path.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        path.lineBreakMode = .byTruncatingMiddle
        path.toolTip = "Enter a remote path and press Return"
        path.setAccessibilityLabel("Remote path")
        let navigation = NSStackView(views: [up, refresh, path])
        navigation.spacing = 4
        let header = PaneHeaderView(title: remoteTitle, controls: navigation)
        hidden.target = self
        hidden.action = #selector(filterEntries)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 35
        table.style = .plain
        table.allowsMultipleSelection = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.target = self
        table.doubleAction = #selector(openRemote)
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.setDraggingSourceOperationMask([], forLocal: false)
        for (id, text, width) in [("name", "Name", 310.0), ("size", "Size", 90.0)] {
            let column = NSTableColumn(identifier: .init(id))
            column.title = text
            column.width = width
            column.minWidth = id == "name" ? 100 : 65
            table.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let upload = button("Upload →", "arrow.up.doc", #selector(uploadAction))
        let download = button("← Download", "arrow.down.doc", #selector(downloadAction))
        let controls = NSStackView(views: [upload, download, cancel, hidden])
        controls.spacing = 6
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        remoteMessage.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let status = NSStackView(views: [progress, remoteMessage])
        status.spacing = 6
        for view in [header, scroll, controls, status] {
            remoteView.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: remoteView.topAnchor),
            header.leadingAnchor.constraint(equalTo: remoteView.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: remoteView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: remoteView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: remoteView.trailingAnchor),
            controls.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            controls.leadingAnchor.constraint(equalTo: remoteView.leadingAnchor, constant: 10),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: remoteView.trailingAnchor, constant: -10),
            status.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 4),
            status.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: remoteView.trailingAnchor, constant: -10),
            status.bottomAnchor.constraint(equalTo: remoteView.bottomAnchor, constant: -8)
        ])
        remoteControls = [path, hidden, upload, download, up, refresh, table]
    }

    private func navigationButton(_ symbol: String, title: String, action: Selector) -> NSButton {
        let result = button("", symbol, action)
        result.isBordered = false
        result.contentTintColor = .secondaryLabelColor
        result.toolTip = title
        result.setAccessibilityLabel(title)
        result.widthAnchor.constraint(equalToConstant: 25).isActive = true
        return result
    }

    @objc private func closeForm(_ sender: Any?) { window?.performClose(nil) }
    private func button(_ title: String, _ symbol: String?, _ action: Selector) -> NSButton { QingTheme.button(title, symbol: symbol, target: self, action: action) }
    private func setMessage(_ value: String) {
        for label in [connectionMessage, remoteMessage] {
            label.stringValue = value
            label.toolTip = value
        }
    }
    private func profile() throws -> RemoteProfile {
        guard let value = Int(port.stringValue) else { throw RemoteError.message("Port must be a number from 1 to 65535.") }
        return try RemoteProfile(id: profileID, name: name.stringValue.isEmpty ? host.stringValue : name.stringValue, kind: kind.titleOfSelectedItem ?? "SFTP", host: host.stringValue.trimmingCharacters(in: .whitespaces), port: value, username: username.stringValue.trimmingCharacters(in: .whitespaces), directory: initialPath.stringValue, identityFile: identity.stringValue).validated()
    }
    private func makeService() throws -> RemoteService { try RemoteService(profile: profile(), password: password.stringValue) }
    private func updatePicker() { profilePicker.removeAllItems(); profilePicker.addItems(withTitles: ["New connection…"] + profiles.map { "\($0.name) · \($0.kind)" }) }
    @objc private func loadProfile(_ sender: Any?) {
        setMessage("")
        let index = profilePicker.indexOfSelectedItem - 1
        guard profiles.indices.contains(index) else {
            profileID = UUID().uuidString; name.stringValue = "New Connection"; host.stringValue = ""; username.stringValue = ""; password.stringValue = ""; identity.stringValue = ""; initialPath.stringValue = "/"; remember.state = .off
            kind.selectItem(withTitle: "SFTP"); protocolChanged(nil); return
        }
        let p = profiles[index]; profileID = p.id; name.stringValue = p.name; kind.selectItem(withTitle: p.kind); host.stringValue = p.host; port.stringValue = String(p.port); username.stringValue = p.username; initialPath.stringValue = p.directory; identity.stringValue = p.identityFile
        password.stringValue = RemoteCredentials.password(for: p.id) ?? ""; remember.state = password.stringValue.isEmpty ? .off : .on
    }
    @objc private func protocolChanged(_ sender: Any?) { port.stringValue = kind.titleOfSelectedItem == "SFTP" ? "22" : "21" }
    @objc private func saveProfile(_ sender: Any?) {
        do {
            let p = try profile()
            // Preserve saved passwords only with explicit opt-in.
            try RemoteCredentials.save(remember.state == .on ? password.stringValue : "", for: p.id)
            profiles.removeAll { $0.id == p.id }; profiles.append(p)
            UserDefaults.standard.set(try JSONEncoder().encode(profiles), forKey: preferencesKey)
            updatePicker(); profilePicker.selectItem(at: profiles.count); setMessage("Connection saved. Password storage: \(remember.state == .on ? "Keychain" : "session only").")
        } catch { showError(error) }
    }
    @objc private func connectAction(_ sender: Any?) {
        guard !working, !isConnected else { return }
        do {
            let backend = try makeService()
            let directory = try RemotePath.clean(backend.profile.directory)
            withVerifiedHost(backend) { [weak self] in self?.load(directory, using: backend) }
        } catch { showError(error) }
    }

    func disconnect() {
        guard isConnected, !working else { return }
        service = nil
        entries = []
        allEntries = []
        table.reloadData()
        setMessage("")
        updateControls()
        onConnectionChanged?()
    }

    private func load(_ directory: String, using backend: RemoteService, completionMessage: String? = nil) {
        run("Opening \(directory)…", work: { token in try backend.list(directory, cancellation: token) }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let items):
                let firstListing = !self.isConnected
                self.service = backend
                self.remoteDirectory = directory
                self.path.stringValue = directory
                self.allEntries = items
                self.filterEntries(nil)
                self.remoteTitle.stringValue = "Remote · \(backend.profile.host)"
                self.setMessage(completionMessage ?? "\(backend.profile.kind) · \(self.entries.count) items")
                if firstListing {
                    self.window?.makeFirstResponder(nil)
                    self.password.stringValue = ""
                    self.window?.orderOut(nil)
                    self.onConnectionChanged?()
                }
            case .failure(let error):
                self.path.stringValue = self.remoteDirectory
                self.showError(error)
            }
        }
    }
    @objc private func goAction(_ sender: Any?) { guard let service else { setMessage("Connect to a server first."); return }; do { load(try RemotePath.clean(path.stringValue), using: service) } catch { showError(error) } }
    @objc private func upAction(_ sender: Any?) { guard let service else { return }; load((remoteDirectory as NSString).deletingLastPathComponent.isEmpty ? "/" : (remoteDirectory as NSString).deletingLastPathComponent, using: service) }
    @objc private func refreshAction(_ sender: Any?) { if let service { load(remoteDirectory, using: service) } }
    @objc private func filterEntries(_ sender: Any?) { entries = allEntries.filter { hidden.state == .on || !$0.name.hasPrefix(".") }; table.deselectAll(nil); table.reloadData() }
    @objc private func openRemote(_ sender: Any?) {
        let index = table.clickedRow
        guard !working, entries.indices.contains(index), let service else { return }
        let entry = entries[index]
        if entry.isDirectory, let target = try? RemotePath.child(entry.name, in: remoteDirectory) { load(target, using: service) }
        else { setMessage("Select the file and click Download. Remote symbolic links are not followed.") }
    }
    @objc private func uploadAction(_ sender: Any?) {
        guard let backend = transferService() else { return }
        let files = local.selectedURLs
        guard !files.isEmpty, files.allSatisfy(isRegularFile) else {
            setMessage("Select one or more regular files in the local pane.")
            return
        }
        upload(files, to: remoteDirectory, using: backend)
    }

    @objc private func downloadAction(_ sender: Any?) {
        guard let backend = transferService() else { return }
        let selected = table.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
        guard !selected.isEmpty, selected.allSatisfy(isRegularFile) else {
            setMessage("Select one or more regular files in the remote pane.")
            return
        }
        download(selected, from: remoteDirectory, to: local.currentDirectory, using: backend)
    }

    private func transferService(reportErrors: Bool = true) -> RemoteService? {
        guard let service, !working, remoteView.window?.attachedSheet == nil else { return nil }
        guard canTransfer?() != false else {
            if reportErrors { setMessage("Wait for the local operation to finish before transferring.") }
            return nil
        }
        guard (try? RemotePath.clean(path.stringValue)) == remoteDirectory else {
            if reportErrors { setMessage("Press Return to open the edited path before transferring.") }
            return nil
        }
        return service
    }

    private func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func isRegularFile(_ entry: RemoteEntry) -> Bool {
        !entry.isDirectory && !entry.isSymbolicLink
    }

    private func upload(_ files: [URL], to directory: String, using backend: RemoteService) {
        transfer("Uploading", names: files.map(\.lastPathComponent), operation: { index, token in
            try backend.upload(files[index], to: directory, cancellation: token)
        }, completion: { [weak self] message in
            guard let self, directory == self.remoteDirectory else { return }
            self.load(directory, using: backend, completionMessage: message)
        })
    }

    private func download(_ files: [RemoteEntry], from directory: String, to destination: URL, using backend: RemoteService) {
        transfer("Downloading", names: files.map(\.name), operation: { index, token in
            _ = try backend.download(files[index], from: directory, to: destination, cancellation: token)
        }, completion: { [weak self] _ in self?.local.refresh() })
    }

    private func transfer(_ label: String, names: [String], operation: @escaping (Int, RemoteCancellation) throws -> Void,
                          completion: @escaping (String) -> Void) {
        let total = names.count
        var completed = 0
        run("\(label) \(total) file(s)…", work: { [weak self] token in
            for (index, name) in names.enumerated() {
                if token.isCancelled { throw RemoteError.message("Transfer cancelled.") }
                DispatchQueue.main.async { self?.setMessage("\(label) \(index + 1)/\(total) · \(name)") }
                try operation(index, token)
                completed += 1
            }
        }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                let message = "Completed \(completed) file(s)."
                self.setMessage(message)
                completion(message)
            case .failure(let error):
                self.local.refresh()
                self.showError(RemoteError.message("Completed \(completed) of \(total) file(s) before stopping.\n\n\(error.localizedDescription)\n\nRefresh the destination before retrying. An interrupted upload may leave a partial remote file."))
            }
        }
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard transferService(reportErrors: false) != nil, entries.indices.contains(row), isRegularFile(entries[row]) else { return nil }
        if table.selectedRowIndexes.contains(row),
           table.selectedRowIndexes.contains(where: { !isRegularFile(entries[$0]) }) { return nil }
        let item = NSPasteboardItem()
        item.setString(entries[row].name, forType: Self.remoteFile)
        return item
    }

    private func prepareDownload(_ info: NSDraggingInfo) -> ((URL) -> Void)? {
        guard (info.draggingSource as? NSTableView) === table, info.draggingSourceOperationMask.contains(.copy),
              let backend = transferService(reportErrors: false), let items = info.draggingPasteboard.pasteboardItems,
              !items.isEmpty else { return nil }
        let names = Set(items.compactMap { $0.string(forType: Self.remoteFile) })
        let selected = entries.filter { names.contains($0.name) && isRegularFile($0) }
        guard selected.count == items.count else { return nil }
        let directory = remoteDirectory
        return { [weak self] destination in
            self?.download(selected, from: directory, to: destination, using: backend)
        }
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard transferService(reportErrors: false) != nil, localDragURLs(info) != nil else { return [] }
        tableView.setDropRow(uploadTarget(row: row, operation: operation).row, dropOperation: .on)
        return .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation operation: NSTableView.DropOperation) -> Bool {
        guard let backend = transferService(reportErrors: false), let urls = localDragURLs(info) else { return false }
        upload(urls, to: uploadTarget(row: row, operation: operation).directory, using: backend)
        return true
    }

    private func localDragURLs(_ info: NSDraggingInfo) -> [URL]? {
        guard local.isDragSource(info), info.draggingSourceOperationMask.contains(.copy),
              let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                  options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty,
              urls.allSatisfy(isRegularFile) else { return nil }
        return urls
    }

    private func uploadTarget(row: Int, operation: NSTableView.DropOperation) -> (directory: String, row: Int) {
        if operation == .on, entries.indices.contains(row), entries[row].isDirectory, !entries[row].isSymbolicLink,
           let directory = try? RemotePath.child(entries[row].name, in: remoteDirectory) {
            return (directory, row)
        }
        return (remoteDirectory, -1)
    }
    @objc private func cancelAction(_ sender: Any?) { cancellation?.cancel(); setMessage("Cancelling…") }
    @objc private func verifyHost(_ sender: Any?) {
        do {
            let backend = try makeService()
            guard backend.profile.kind == "SFTP" else { setMessage("Host-key verification applies to SSH/SFTP. FTPS uses system certificate verification."); return }
            requestHostTrust(for: backend) { [weak self] in self?.setMessage("Host keys saved. Click Connect to authenticate.") }
        } catch { showError(error) }
    }
    private func withVerifiedHost(_ backend: RemoteService, completion: @escaping () -> Void) {
        guard backend.profile.kind == "SFTP" else { completion(); return }
        run("Checking saved SSH host keys…", work: { token in try backend.hasTrustedHost(cancellation: token) }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(true): completion()
            case .success(false): self.requestHostTrust(for: backend, completion: completion)
            case .failure(let error): self.showError(error)
            }
        }
    }
    private func requestHostTrust(for backend: RemoteService, completion: @escaping () -> Void) {
        run("Reading SSH host fingerprints…", work: { token in try backend.hostKeyScan(cancellation: token) }) { [weak self] result in
            guard let self, let window = self.window else { return }
            switch result {
            case .failure(let error): self.showError(error)
            case .success(let scan):
                self.working = true; self.updateControls()
                let alert = NSAlert(); alert.messageText = "Trust SSH host \(backend.profile.host)?"
                alert.informativeText = "Compare these SHA-256 fingerprints with your server administrator before trusting them. Key scanning alone does not authenticate the server.\n\n\(scan.fingerprints)\nChanged keys are never accepted automatically."
                alert.addButton(withTitle: "Trust Host"); alert.addButton(withTitle: "Cancel")
                alert.beginSheetModal(for: window) { response in
                    self.working = false; self.updateControls()
                    if response == .alertFirstButtonReturn {
                        do { try backend.trustHostKeys(scan.keys); completion() }
                        catch { self.showError(error) }
                    } else {
                        self.setMessage("SSH host verification cancelled.")
                    }
                }
            }
        }
    }
    @objc private func openTerminal(_ sender: Any?) {
        do {
            let backend = try makeService()
            guard backend.profile.kind == "SFTP" else { setMessage("Select SFTP to open an SSH terminal for this host."); return }
            withVerifiedHost(backend) { [weak self] in self?.launchTerminal(using: backend) }
        } catch { showError(error) }
    }
    private func launchTerminal(using backend: RemoteService) {
        do {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QingFiles/Terminal Sessions")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
            let script = directory.appendingPathComponent("SSH-\(UUID().uuidString).command")
            // The script contains connection arguments only, never a password.
            try backend.terminalScript().write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions:0o700], ofItemAtPath: script.path)
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { throw RemoteError.message("Terminal.app was not found.") }
            NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
            setMessage("SSH session opened in Terminal. Terminal handles its own password/passphrase prompt.")
        } catch { showError(error) }
    }
    private func run<T>(_ label: String, work: @escaping (RemoteCancellation) throws -> T, completion: @escaping (Result<T,Error>)->Void) {
        guard !working else { return }
        working = true; setMessage(label); progress.startAnimation(nil)
        let token = RemoteCancellation(); cancellation = token
        updateControls()
        queue.async {
            let result = Result { try work(token) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.working = false; self.progress.stopAnimation(nil); self.cancellation = nil
                completion(result)
                self.updateControls()
            }
        }
    }
    private func updateControls() {
        formControls.forEach { $0.isEnabled = !working }
        remoteControls.forEach { $0.isEnabled = isConnected && !working }
        cancel.isEnabled = cancellation != nil
    }

    private func showError(_ error: Error) {
        setMessage(error.localizedDescription)
        let parent = isConnected ? remoteView.window : window
        guard let parent, parent.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Connection or transfer could not complete"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: parent)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row), let tableColumn else { return nil }
        let entry = entries[row]
        if tableColumn.identifier.rawValue == "name" {
            let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView
                ?? makeNameCell(identifier: tableColumn.identifier)
            let type = entry.isDirectory ? UTType.folder : UTType(filenameExtension: (entry.name as NSString).pathExtension) ?? .data
            cell.imageView?.image = NSWorkspace.shared.icon(for: type)
            cell.textField?.stringValue = entry.name + (entry.isSymbolicLink ? " (link)" : "")
            cell.toolTip = entry.name
            return cell
        }
        let text = entry.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
        let cell = QingTheme.label(text, size: 11, color: .secondaryLabelColor)
        cell.alignment = .right
        return cell
    }

    private func makeNameCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyDown
        let label = QingTheme.label("", size: 12)
        for view in [icon, label] {
            cell.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        cell.imageView = icon
        cell.textField = label
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -3),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}
