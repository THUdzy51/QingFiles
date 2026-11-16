import AppKit

final class TopAlignedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class PaneHeaderView: NSView {
    init(title: NSTextField, controls: NSView) {
        super.init(frame: .zero)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let divider = NSBox()
        divider.boxType = .separator
        for view in [title, controls, divider] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            title.heightAnchor.constraint(equalToConstant: 20),
            controls.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            controls.heightAnchor.constraint(equalToConstant: 27),
            divider.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

enum QingTheme {
    static let accent = NSColor(srgbRed: 0, green: 113.0/255, blue: 227.0/255, alpha: 1)
    static let background = NSColor(srgbRed: 245.0/255, green: 245.0/255, blue: 247.0/255, alpha: 1)
    static let surface = NSColor.white
    static let panelRadius: CGFloat = 22
    static var hairline: NSColor { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .separatorColor : NSColor.black.withAlphaComponent(0.07) }
    static let secondary = NSColor.secondaryLabelColor
    static func symbol(_ name: String, size: CGFloat = 15) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    }
    static func label(_ string: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }
    static func button(_ title: String, symbol: String? = nil, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .medium)
        if let symbol { button.image = self.symbol(symbol); button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading }
        return button
    }
}

final class SidebarButton: NSButton {
    var location: URL?
    var selectedLocation = false { didSet { needsDisplay = true; contentTintColor = selectedLocation ? QingTheme.accent : .secondaryLabelColor } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        alignment = .left
        font = .systemFont(ofSize: 13, weight: .medium)
        imagePosition = .imageLeading
        imageHugsTitle = true
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 34).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        if selectedLocation {
            QingTheme.accent.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}
