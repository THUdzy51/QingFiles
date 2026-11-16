import AppKit

final class SettingsWindow: NSWindowController {
    private let setting: WeChatRevealSetting
    private let toggle = NSButton(checkboxWithTitle: "Use QingFiles for Show in Finder in WeChat", target: nil, action: nil)
    private let message = NSTextField(wrappingLabelWithString: "")
    private let queue = DispatchQueue(label: "local.qingfiles.settings", qos: .userInitiated)

    init(setting: WeChatRevealSetting = WeChatRevealSetting()) {
        self.setting = setting
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 240),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings — QingFiles"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let title = QingTheme.label("File reveal", size: 20, weight: .semibold)
        let description = NSTextField(wrappingLabelWithString: "Choose Show in Finder on an attachment to reveal it in QingFiles. Turning this off restores the previous file viewer. Fully quit and reopen WeChat after changing this setting.")
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, toggle, description, message])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
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
