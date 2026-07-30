import Cocoa

enum UIStyle {
    static var razerGreen: NSColor {
        return DesignSystem.Colors.successText
    }

    static var primaryTextColor: NSColor {
        return DesignSystem.Colors.textPrimary
    }

    static var secondaryTextColor: NSColor {
        return DesignSystem.Colors.textSecondary
    }

    static var warningColor: NSColor {
        return DesignSystem.Colors.warningText
    }

    static var successColor: NSColor {
        return DesignSystem.Colors.successText
    }

    static var dangerColor: NSColor {
        return DesignSystem.Colors.dangerText
    }

    static var hoverBorderColor: NSColor {
        return DesignSystem.Colors.focusRing
    }

    static var cardFillColor: NSColor {
        return DesignSystem.Colors.cardBackground
    }

    static var cardBorderColor: NSColor {
        return DesignSystem.Colors.borderNormal
    }

    static func makeCard() -> NSBox {
        return ThemeCardBox()
    }

    static func makeBackground(material: NSVisualEffectView.Material = .windowBackground) -> NSView {
        return ThemeBackgroundView(material: material)
    }

    static func makeFooter(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = Typography.bodySecondary
        label.textColor = UIStyle.secondaryTextColor
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        return label
    }

    static func symbol(_ name: String, size: CGFloat = 16, weight: NSFont.Weight = .regular) -> NSImage? {
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }
        return nil
    }

    static func stylePrimaryButton(_ b: NSButton) {
        b.isBordered = true
        b.bezelStyle = .rounded
    }

    static func styleSecondaryButton(_ b: NSButton) {
        b.isBordered = true
        b.bezelStyle = .rounded
    }

    static func styleDangerButton(_ b: NSButton) {
        b.isBordered = true
        b.bezelStyle = .rounded
        if #available(macOS 11.0, *) {
            b.bezelColor = .systemRed
        }
    }
}

final class ThemeBackgroundView: NSView {
    let effectView = NSVisualEffectView()
    let solidView = NSView()

    init(material: NSVisualEffectView.Material = .windowBackground) {
        super.init(frame: .zero)

        effectView.frame = bounds
        effectView.autoresizingMask = [.width, .height]
        addSubview(effectView)

        solidView.frame = bounds
        solidView.autoresizingMask = [.width, .height]
        solidView.wantsLayer = true
        addSubview(solidView)

        updateTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(updateTheme), name: .appThemeDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func updateTheme() {
        effectView.isHidden = false
        solidView.isHidden = true

        if #available(macOS 10.14, *) {
            switch ThemeManager.shared.currentMode {
            case .light:
                effectView.appearance = NSAppearance(named: .vibrantLight)
            case .dark:
                effectView.appearance = NSAppearance(named: .vibrantDark)
            case .system:
                effectView.appearance = nil
            }
        }
    }
}

final class ThemeCardBox: NSBox {
    init() {
        super.init(frame: .zero)
        self.boxType = .custom
        self.borderWidth = 1
        self.cornerRadius = DesignSystem.Radius.card
        self.translatesAutoresizingMaskIntoConstraints = false
        updateTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(updateTheme), name: .appThemeDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func updateTheme() {
        self.fillColor = DesignSystem.Colors.cardBackground
        self.borderColor = DesignSystem.Colors.borderNormal
    }
}
