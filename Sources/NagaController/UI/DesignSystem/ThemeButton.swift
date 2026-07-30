import Cocoa

enum ThemeButtonType {
    case normal
    case primary
    case danger
}

class ThemeButton: NSButton {
    var buttonType: ThemeButtonType = .normal {
        didSet {
            updateAppearance()
        }
    }
    
    private var isHovered = false {
        didSet {
            guard oldValue != isHovered else { return }
            updateAppearance()
        }
    }
    
    private var trackingArea: NSTrackingArea?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        wantsLayer = true
        isBordered = false
        layer?.cornerRadius = DesignSystem.Radius.smallButton
        font = Typography.buttonText

        // Swap in a cell that applies real content insets
        let oldTitle = title
        let oldFont = font
        let paddedCell = ThemeButtonCell()
        paddedCell.title = oldTitle
        paddedCell.font = oldFont
        paddedCell.imageScaling = .scaleProportionallyDown
        paddedCell.isBordered = false
        self.cell = paddedCell
        
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .appThemeDidChange, object: nil)
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        // extra width is already handled by ThemeButtonCell.titleRect; add a fixed minimum
        size.width = max(size.width, 60)
        size.height = max(size.height, 28)
        return size
    }
    
    @objc private func themeDidChange() {
        updateAppearance()
    }
    
    override var title: String {
        didSet {
            updateAppearance()
        }
    }
    
    override func viewWillDraw() {
        super.viewWillDraw()
        // Ensure layer is updated before drawing
        updateLayerAppearance()
    }
    
    private func updateAppearance() {
        let isPressed = self.cell?.isHighlighted ?? false
        
        var textColor: NSColor
        switch buttonType {
        case .normal:
            textColor = DesignSystem.Colors.textPrimary
        case .primary:
            textColor = DesignSystem.Colors.textOnAccent
        case .danger:
            if isPressed {
                textColor = .white
            } else if isHovered {
                textColor = .white
            } else {
                textColor = DesignSystem.Colors.dangerText
            }
        }
        
        if self.title.count > 0 {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: textColor,
                .font: self.font ?? Typography.buttonText,
                .paragraphStyle: paragraphStyle
            ]
            let newAttrStr = NSAttributedString(string: self.title, attributes: attrs)
            if self.attributedTitle != newAttrStr {
                self.attributedTitle = newAttrStr
            }
        }
        
        updateLayerAppearance()
    }
    
    private func updateLayerAppearance() {
        guard let layer = self.layer else { return }
        let isPressed = self.cell?.isHighlighted ?? false
        
        switch buttonType {
        case .normal:
            layer.borderWidth = 1
            layer.borderColor = DesignSystem.Colors.borderNormal.cgColor
            if isPressed {
                layer.backgroundColor = DesignSystem.Colors.controlPressedBackground.cgColor
            } else if isHovered {
                layer.backgroundColor = DesignSystem.Colors.controlHoverBackground.cgColor
            } else {
                layer.backgroundColor = DesignSystem.Colors.controlBackground.cgColor
            }
            
        case .primary:
            layer.borderWidth = 0
            if isPressed {
                layer.backgroundColor = DesignSystem.Colors.accentPressed.cgColor
            } else if isHovered {
                layer.backgroundColor = DesignSystem.Colors.accentHover.cgColor
            } else {
                layer.backgroundColor = DesignSystem.Colors.accentFill.cgColor
            }
            
        case .danger:
            layer.borderWidth = 1
            layer.borderColor = DesignSystem.Colors.dangerBorder.cgColor
            if isPressed {
                layer.backgroundColor = DesignSystem.Colors.dangerFill.cgColor
            } else if isHovered {
                layer.backgroundColor = DesignSystem.Colors.dangerHover.cgColor
            } else {
                layer.backgroundColor = DesignSystem.Colors.dangerBackground.cgColor
            }
        }
    }
    
    override func updateLayer() {
        // Do not call super.updateLayer() if we are completely drawing our own layer
        updateLayerAppearance()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        if let ta = trackingArea { addTrackingArea(ta) }
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
    
    // Catch highlight changes to trigger appearance update
    override var cell: NSCell? {
        didSet {
            updateAppearance()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        updateAppearance()
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        updateAppearance()
    }
}

// MARK: - ThemeButtonCell
/// Custom cell that injects horizontal and vertical padding so text/icon never touches the border.
private final class ThemeButtonCell: NSButtonCell {
    private let hPad: CGFloat = 12
    private let vPad: CGFloat = 4

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var r = super.titleRect(forBounds: rect)
        r.origin.x    += hPad
        r.size.width  -= hPad * 2
        r.origin.y    += vPad
        r.size.height -= vPad * 2
        return r
    }

    override func imageRect(forBounds rect: NSRect) -> NSRect {
        var r = super.imageRect(forBounds: rect)
        r.origin.x += hPad
        return r
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        return rect.insetBy(dx: hPad, dy: vPad)
    }

    override func cellSize(forBounds rect: NSRect) -> NSSize {
        var s = super.cellSize(forBounds: rect)
        s.width  += hPad * 2
        s.height += vPad * 2
        return s
    }
}