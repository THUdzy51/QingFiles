import AppKit

/// Remote operations live in an explicit local/remote workspace so local file actions
/// can never accidentally treat a server path as a local filesystem URL.
final class RemoteWorkspace: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
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
    private let path = NSTextField(string: "/")
    private let remember = NSButton(checkboxWithTitle: "Save password in Keychain", target: nil, action: nil)
    private let message = QingTheme.label("Choose a connection or enter server details.", size: 12, color: .secondaryLabelColor)
    private let progress = NSProgressIndicator()
    private let hidden = NSButton(checkboxWithTitle: "Hidden items", target: nil, action: nil)
    private var actionButtons: [NSButton] = []
    private var formControls: [NSControl] = []
    private var allEntries: [RemoteEntry] = []
    private var entries: [RemoteEntry] = []
    private var profiles: [RemoteProfile] = []
    private var profileID = UUID().uuidString
    private var service: RemoteService?
    private var cancellation: RemoteCancellation?
    private let queue = DispatchQueue(label: "local.qingfiles.remote", qos: .userInitiated)
    private var working = false
    var isBusy: Bool { working }
    private var remoteDirectory = "/"
    private let preferencesKey = "remoteConnections.v1"

    init(localDirectory: URL) {
        local = FilePane(directory: localDirectory, title: "LOCAL")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 840), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Connections — QingFiles"; window.minSize = NSSize(width: 1080, height: 760)
        window.backgroundColor = QingTheme.background; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        if let data = UserDefaults.standard.data(forKey: preferencesKey) { profiles = (try? JSONDecoder().decode([RemoteProfile].self, from: data)) ?? [] }
        build()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if working { cancellation?.cancel(); setMessage("Cancelling the operation. Close again when it finishes."); return false }
        return true
    }

    func windowWillClose(_ notification: Notification) { if !working { disconnectAction(nil) } }

    private func build() {
        guard let window else { return }
        let root = NSView(); root.wantsLayer = true; root.layer?.backgroundColor = QingTheme.background.cgColor; window.contentView = root
        let title = QingTheme.label("Connections", size: 24, weight: .semibold)
        let subtitle = QingTheme.label("Local files. Remote servers. One workspace.", size: 12, color: .secondaryLabelColor)
        profilePicker.target = self; profilePicker.action = #selector(loadProfile)
        updatePicker()
        kind.addItems(withTitles: ["SFTP", "FTPS", "FTP"]); kind.target = self; kind.action = #selector(protocolChanged)
        host.placeholderString = "server.example.com"; username.placeholderString = "Username"
        password.placeholderString = "Password / key passphrase (optional)"
        identity.placeholderString = "Optional key file, e.g. ~/.ssh/id_ed25519"
        path.placeholderString = "Remote folder, e.g. /home/user"
        let form = NSGridView(views: [
            [QingTheme.label("Saved connection"), profilePicker, QingTheme.label("Protocol"), kind],
            [QingTheme.label("Name"), name, QingTheme.label("Port"), port],
            [QingTheme.label("Host"), host, QingTheme.label("Username"), username],
            [QingTheme.label("Password"), password, QingTheme.label("Identity file"), identity]
        ])
        form.rowSpacing = 10; form.columnSpacing = 12; form.xPlacement = .fill
        form.column(at: 0).xPlacement = .leading; form.column(at: 2).xPlacement = .leading
        form.column(at: 0).width = 110; form.column(at: 2).width = 90
        host.widthAnchor.constraint(equalTo: username.widthAnchor).isActive = true
        kind.widthAnchor.constraint(equalTo: username.widthAnchor).isActive = true
        profilePicker.widthAnchor.constraint(equalTo: host.widthAnchor).isActive = true
        for field in [name, host, port, username, password, identity, path] { field.bezelStyle = .roundedBezel; field.usesSingleLineMode = true }
        profilePicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        identity.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        let save = button("Save Connection", "square.and.arrow.down", #selector(saveProfile))
        let verify = button("Verify SSH Host…", "checkmark.shield", #selector(verifyHost))
        let connect = button("Connect", "network", #selector(connectAction)); connect.keyEquivalent = "\r"
        let disconnect = button("Disconnect", "eject", #selector(disconnectAction))
        let terminal = button("SSH Terminal", "terminal", #selector(openTerminal))
        let controls = NSStackView(views: [remember, save, verify, connect, disconnect, terminal]); controls.spacing = 12
        actionButtons += [save, verify, connect, disconnect, terminal]
        let note = QingTheme.label("SFTP uses SSH encryption. FTPS requires TLS. Plain FTP sends credentials and file data unencrypted.", size: 11, color: .secondaryLabelColor)
        let header = NSStackView(views: [title, subtitle, form, controls, note]); header.orientation = .vertical; header.alignment = .leading; header.spacing = 12
        local.onActivate = { pane in pane.isActive = true }
        local.isActive = true
        local.onAction = { [weak self] _, action in
            guard let self else { return }
            if action == "copyToOther" { self.uploadAction(nil) }
            else if action == "terminal" { self.openTerminal(nil) }
            else { self.setMessage("Use the main QingFiles window for local file actions; use Upload here to transfer selected files.") }
        }
        let remote = NSView(); remote.wantsLayer = true; remote.layer?.backgroundColor = QingTheme.surface.cgColor; remote.layer?.cornerRadius = 0
        let remoteTitle = QingTheme.label("REMOTE", size: 11, weight: .semibold, color: .secondaryLabelColor)
        let up = button("", "arrow.up", #selector(upAction)); up.toolTip = "Remote parent folder"
        let refresh = button("", "arrow.clockwise", #selector(refreshAction)); refresh.toolTip = "Refresh remote folder"
        let go = button("Go", nil, #selector(goAction))
        path.target = self; path.action = #selector(goAction)
        let navigation = NSStackView(views: [up, path, go, refresh]); navigation.spacing = 8
        hidden.target = self; hidden.action = #selector(filterEntries)
        table.dataSource = self; table.delegate = self; table.rowHeight = 34; table.style = .plain
        table.allowsMultipleSelection = true; table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.target = self; table.doubleAction = #selector(openRemote)
        for (id, text, width) in [("name","Name",310.0), ("size","Size",90.0)] {
            let column = NSTableColumn(identifier: .init(id)); column.title = text; column.width = width; column.minWidth = id == "name" ? 170 : 65; table.addTableColumn(column)
        }
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        for v in [remoteTitle, navigation, hidden, scroll] { remote.addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            remoteTitle.topAnchor.constraint(equalTo: remote.topAnchor, constant: 18), remoteTitle.leadingAnchor.constraint(equalTo: remote.leadingAnchor, constant: 18),
            navigation.topAnchor.constraint(equalTo: remoteTitle.bottomAnchor, constant: 12), navigation.leadingAnchor.constraint(equalTo: remote.leadingAnchor, constant: 14), navigation.trailingAnchor.constraint(equalTo: remote.trailingAnchor, constant: -14),
            hidden.topAnchor.constraint(equalTo: navigation.bottomAnchor, constant: 10), hidden.leadingAnchor.constraint(equalTo: navigation.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: hidden.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: remote.leadingAnchor, constant: 8), scroll.trailingAnchor.constraint(equalTo: remote.trailingAnchor, constant: -8), scroll.bottomAnchor.constraint(equalTo: remote.bottomAnchor, constant: -12)
        ])
        let browsers = NSStackView(views: [local.view, remote]); browsers.orientation = .horizontal; browsers.distribution = .fillEqually; browsers.spacing = 1
        browsers.wantsLayer = true; browsers.layer?.backgroundColor = QingTheme.hairline.cgColor; browsers.layer?.cornerRadius = QingTheme.panelRadius; browsers.layer?.masksToBounds = true
        let upload = button("Upload →", "arrow.up.doc", #selector(uploadAction))
        let download = button("← Download", "arrow.down.doc", #selector(downloadAction))
        let cancel = button("Cancel Transfer", "xmark.circle", #selector(cancelAction))
        actionButtons += [upload, download, up, refresh, go]
        let transferControls = NSStackView(views: [upload, download, cancel]); transferControls.spacing = 10
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        let status = NSStackView(views: [progress, message]); status.spacing = 8
        for v in [header, browsers, transferControls, status] { root.addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 22), header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            form.widthAnchor.constraint(equalTo: header.widthAnchor),
            browsers.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20), browsers.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), browsers.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            transferControls.topAnchor.constraint(equalTo: browsers.bottomAnchor, constant: 14), transferControls.leadingAnchor.constraint(equalTo: browsers.leadingAnchor),
            status.topAnchor.constraint(equalTo: transferControls.bottomAnchor, constant: 12), status.leadingAnchor.constraint(equalTo: browsers.leadingAnchor), status.trailingAnchor.constraint(equalTo: browsers.trailingAnchor), status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        formControls = [profilePicker, kind, name, host, port, username, password, identity, remember, path]
    }
    private func button(_ title: String, _ symbol: String?, _ action: Selector) -> NSButton { QingTheme.button(title, symbol: symbol, target: self, action: action) }
    private func setMessage(_ value: String) { message.stringValue = value; message.toolTip = value }
    private func profile() throws -> RemoteProfile {
        guard let value = Int(port.stringValue) else { throw RemoteError.message("Port must be a number from 1 to 65535.") }
        return try RemoteProfile(id: profileID, name: name.stringValue.isEmpty ? host.stringValue : name.stringValue, kind: kind.titleOfSelectedItem ?? "SFTP", host: host.stringValue.trimmingCharacters(in: .whitespaces), port: value, username: username.stringValue.trimmingCharacters(in: .whitespaces), directory: path.stringValue, identityFile: identity.stringValue).validated()
    }
    private func makeService() throws -> RemoteService { try RemoteService(profile: profile(), password: password.stringValue) }
    private func updatePicker() { profilePicker.removeAllItems(); profilePicker.addItems(withTitles: ["New connection…"] + profiles.map { "\($0.name) · \($0.kind)" }) }
    @objc private func loadProfile(_ sender: Any?) {
        disconnectAction(nil)
        let index = profilePicker.indexOfSelectedItem - 1
        guard profiles.indices.contains(index) else {
            profileID = UUID().uuidString; name.stringValue = "New Connection"; host.stringValue = ""; username.stringValue = ""; password.stringValue = ""; identity.stringValue = ""; path.stringValue = "/"; remember.state = .off; return
        }
        let p = profiles[index]; profileID = p.id; name.stringValue = p.name; kind.selectItem(withTitle: p.kind); host.stringValue = p.host; port.stringValue = String(p.port); username.stringValue = p.username; path.stringValue = p.directory; identity.stringValue = p.identityFile
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
        do { let backend = try makeService(); service = nil; allEntries = []; entries = []; table.reloadData(); load(try RemotePath.clean(path.stringValue), using: backend) }
        catch { showError(error) }
    }
    @objc private func disconnectAction(_ sender: Any?) { cancellation?.cancel(); service = nil; entries = []; allEntries = []; table.reloadData(); password.stringValue = ""; setMessage("Disconnected. Saved profiles and Keychain passwords are retained."); updateControls() }
    private func load(_ directory: String, using backend: RemoteService) {
        let previous = remoteDirectory
        run("Connecting / listing \(directory)…", work: { token in try backend.list(directory, cancellation: token) }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let items): self.service = backend; self.remoteDirectory = directory; self.path.stringValue = directory; self.allEntries = items; self.filterEntries(nil); self.setMessage("\(backend.profile.kind) · \(backend.profile.host) · \(items.count) items. Select regular files to transfer.")
            case .failure(let error): self.path.stringValue = previous; self.showError(error)
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
        guard let service else { setMessage("Connect to a server before uploading."); return }
        guard (try? RemotePath.clean(path.stringValue)) == remoteDirectory else { setMessage("Press Go to navigate to the edited remote path before transferring."); return }
        let sources = local.selectedURLs, directory = remoteDirectory
        guard !sources.isEmpty else { setMessage("Select one or more regular files in the local pane."); return }
        transfer("Uploading", total: sources.count) { token, update in
            for (index, url) in sources.enumerated() {
                if token.isCancelled { throw RemoteError.message("Transfer cancelled.") }
                update(index + 1, url.lastPathComponent)
                try service.upload(url, to: directory, cancellation: token)
            }
        }
    }
    @objc private func downloadAction(_ sender: Any?) {
        guard let service else { setMessage("Connect to a server before downloading."); return }
        guard (try? RemotePath.clean(path.stringValue)) == remoteDirectory else { setMessage("Press Go to navigate to the edited remote path before transferring."); return }
        let selected = table.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
        let directory = remoteDirectory, destination = local.currentDirectory
        guard !selected.isEmpty else { setMessage("Select regular files in the remote pane."); return }
        transfer("Downloading", total: selected.count) { token, update in
            for (index, entry) in selected.enumerated() {
                if token.isCancelled { throw RemoteError.message("Transfer cancelled.") }
                update(index + 1, entry.name)
                _ = try service.download(entry, from: directory, to: destination, cancellation: token)
            }
        }
    }
    private func transfer(_ label: String, total: Int, work: @escaping (RemoteCancellation, @escaping (Int,String)->Void) throws -> Void) {
        var finished = 0
        run("\(label) \(total) file(s)…", work: { [weak self] token -> Int in
            try work(token) { index, name in
                finished = index - 1
                DispatchQueue.main.async { self?.setMessage("\(label) \(index)/\(total): \(name)") }
            }
            return total
        }) { [weak self] result in
            guard let self else { return }
            self.local.refresh()
            switch result {
            case .success(let count): self.setMessage("Completed \(count) file(s). Refresh the remote pane to see uploads.")
            case .failure(let error): self.showError(RemoteError.message("Completed \(finished) of \(total) file(s) before stopping.\n\n\(error.localizedDescription)\n\nRefresh both locations before retrying. A partial remote upload may remain."))
            }
        }
    }
    @objc private func cancelAction(_ sender: Any?) { cancellation?.cancel(); setMessage("Cancelling…") }
    @objc private func verifyHost(_ sender: Any?) {
        do {
            let backend = try makeService()
            guard backend.profile.kind == "SFTP" else { setMessage("Host-key verification applies to SSH/SFTP. FTPS uses system certificate verification."); return }
            run("Reading SSH host fingerprints…", work: { _ in try backend.hostKeyScan() }) { [weak self] result in
                guard let self, let window = self.window else { return }
                switch result {
                case .failure(let error): self.showError(error)
                case .success(let scan):
                    let alert = NSAlert(); alert.messageText = "Trust SSH host \(backend.profile.host)?"
                    alert.informativeText = "Compare these SHA-256 fingerprints with your server administrator before trusting them. Key scanning alone does not authenticate the server.\n\n\(scan.fingerprints)\nChanged keys are never accepted automatically."
                    alert.addButton(withTitle: "Trust Host"); alert.addButton(withTitle: "Cancel")
                    alert.beginSheetModal(for: window) { response in
                        if response == .alertFirstButtonReturn {
                            do { try backend.trustHostKeys(scan.keys); self.setMessage("Host keys saved. Click Connect to authenticate.") }
                            catch { self.showError(error) }
                        }
                    }
                }
            }
        } catch { showError(error) }
    }
    @objc private func openTerminal(_ sender: Any?) {
        do {
            let backend = try makeService()
            guard backend.profile.kind == "SFTP" else { setMessage("Select SFTP to open an SSH terminal for this host."); return }
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
        actionButtons.forEach { $0.isEnabled = false }; formControls.forEach { $0.isEnabled = false }; table.isEnabled = false
        let token = RemoteCancellation(); cancellation = token
        queue.async {
            let result = Result { try work(token) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.working = false; self.progress.stopAnimation(nil); self.cancellation = nil
                self.actionButtons.forEach { $0.isEnabled = true }; self.formControls.forEach { $0.isEnabled = true }; self.table.isEnabled = true
                completion(result)
                self.updateControls()
            }
        }
    }
    private func updateControls() {
        actionButtons.forEach { $0.isEnabled = !working }
        for control in formControls {
            let mayEditConnected = control === path || control === name || control === remember || control === profilePicker
            control.isEnabled = !working && (service == nil || mayEditConnected)
        }
        table.isEnabled = !working
    }

    private func showError(_ error: Error) {
        setMessage(error.localizedDescription)
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = "Connection or transfer could not complete"; alert.informativeText = error.localizedDescription; alert.addButton(withTitle: "OK"); alert.beginSheetModal(for: window)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row), let tableColumn else { return nil }
        let entry = entries[row]
        let text = tableColumn.identifier.rawValue == "name" ? ((entry.isDirectory ? "▸  " : "") + entry.name + (entry.isSymbolicLink ? " (link)" : "")) : (entry.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
        let cell = NSTextField(labelWithString: text); cell.font = .systemFont(ofSize: 12); cell.lineBreakMode = .byTruncatingMiddle; cell.toolTip = entry.name
        return cell
    }
}
