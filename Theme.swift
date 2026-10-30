import AppKit

final class TopAlignedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

enum QingTheme {
    static let accent = NSColor(srgbRed: 0.12, green: 0.51, blue: 0.46, alpha: 1)
    static let background = NSColor(srgbRed: 0.945, green: 0.956, blue: 0.957, alpha: 1)
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
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 7, yRadius: 7).fill()
        }
        super.draw(dirtyRect)
    }
}
