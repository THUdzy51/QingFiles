import AppKit

final class SettingsWindow: NSWindowController {
    private let setting: WeChatRevealSetting
    private let finderFolderOpening: FinderFolderOpening
    private let finderToggle = NSButton(checkboxWithTitle: "Open folders from Finder and the desktop in QingFiles", target: nil, action: nil)
    private let finderStatus = NSTextField(wrappingLabelWithString: "")
    private let toggle = NSButton(checkboxWithTitle: "Use QingFiles for Show in Finder in WeChat", target: nil, action: nil)
    private let message = NSTextField(wrappingLabelWithString: "")
    private let queue = DispatchQueue(label: "local.qingfiles.settings", qos: .userInitiated)

    init(finderFolderOpening: FinderFolderOpening, setting: WeChatRevealSetting = WeChatRevealSetting()) {
        self.setting = setting
        self.finderFolderOpening = finderFolderOpening
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 350),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings — QingFiles"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let folderTitle = QingTheme.label("Folder opening", size: 20, weight: .semibold)
        finderToggle.target = self
        finderToggle.action = #selector(finderToggleChanged)
        finderStatus.font = .systemFont(ofSize: 12)
        finderStatus.textColor = .secondaryLabelColor
        let title = QingTheme.label("File reveal", size: 20, weight: .semibold)
        let description = NSTextField(wrappingLabelWithString: "Choose Show in Finder on an attachment to reveal it in QingFiles. Turning this off restores the previous file viewer. Fully quit and reopen WeChat after changing this setting.")
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [folderTitle, finderToggle, finderStatus, title, toggle, description, message])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            finderStatus.widthAnchor.constraint(equalTo: stack.widthAnchor),
            description.widthAnchor.constraint(equalTo: stack.widthAnchor),
            message.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        updateSetting(to: nil)
        finderFolderOpening.refresh()
        updateFinderFolderStatus()
    }

    func updateFinderFolderStatus() {
        finderToggle.state = finderFolderOpening.isEnabled ? .on : .off
        switch finderFolderOpening.status {
        case .off: finderStatus.stringValue = "Double-clicks are handled by Finder."
        case .needsAccessibility:
            finderStatus.stringValue = "Allow QingFiles in System Settings → Privacy & Security → Accessibility, then return to QingFiles."
        case .unavailable:
            finderStatus.stringValue = "Finder integration is unavailable. Reopen QingFiles and check Accessibility access."
        case .active:
            finderStatus.stringValue = "Folder double-clicks open in QingFiles while it is running."
        }
    }

    @objc private func finderToggleChanged() {
        finderFolderOpening.setEnabled(finderToggle.state == .on)
        updateFinderFolderStatus()
    }

    @objc private func toggleChanged() { updateSetting(to: toggle.state == .on) }

    private func updateSetting(to enabled: Bool?) {
        toggle.isEnabled = false
        message.stringValue = enabled == nil ? "Reading WeChat settings…" : "Saving…"
        queue.async { [weak self] in
            guard let self else { return }
            do {
                if let enabled { try self.setting.setEnabled(enabled) }
                let active = try self.setting.isEnabled()
                DispatchQueue.main.async {
                    self.toggle.state = active ? .on : .off
                    self.toggle.isEnabled = true
                    self.message.textColor = .secondaryLabelColor
                    self.message.stringValue = enabled == nil ? "" : "Saved. Fully quit and reopen WeChat to apply this change."
                }
            } catch {
                let active = try? self.setting.isEnabled()
                DispatchQueue.main.async {
                    self.toggle.state = active == true ? .on : .off
                    self.toggle.isEnabled = true
                    self.message.textColor = .systemRed
                    self.message.stringValue = error.localizedDescription
                }
            }
        }
    }
}
