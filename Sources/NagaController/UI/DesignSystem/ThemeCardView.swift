import Cocoa

enum CardVisualState {
    case normal
    case hovered
    case pressed
    case selected
    case disabled
}

class ThemeCardView: NSView {
    var visualState: CardVisualState = .normal {
        didSet {
            guard oldValue != visualState else { return }
            needsDisplay = true
            updateLayer()
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
        layer?.cornerRadius = DesignSystem.Radius.card
        layer?.borderWidth = 1
        layer?.shadowColor = DesignSystem.Colors.shadowColor.cgColor
        layer?.shadowOpacity = 1.0 // opacity is handled by the color's alpha
        layer?.shadowRadius = 3
        layer?.shadowOffset = CGSize(width: 0, height: 1)
        
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .appThemeDidChange, object: nil)
    }
    
    @objc private func themeDidChange() {
        needsDisplay = true
        updateLayer()
    }
    
    override func updateLayer() {
        super.updateLayer()
        guard let layer = self.layer else { return }
        
        layer.shadowColor = DesignSystem.Colors.shadowColor.cgColor
        
        switch visualState {
        case .normal:
            layer.backgroundColor = DesignSystem.Colors.cardBackground.cgColor
            layer.borderColor = DesignSystem.Colors.borderNormal.cgColor
            layer.borderWidth = 1
        case .hovered:
            layer.backgroundColor = DesignSystem.Colors.cardHoverBackground.cgColor
            layer.borderColor = DesignSystem.Colors.borderNormal.cgColor
            layer.borderWidth = 1
        case .pressed:
            layer.backgroundColor = DesignSystem.Colors.cardPressedBackground.cgColor
            layer.borderColor = DesignSystem.Colors.borderNormal.cgColor
            layer.borderWidth = 1
        case .selected:
            layer.backgroundColor = DesignSystem.Colors.cardSelectedBackground.cgColor
            layer.borderColor = DesignSystem.Colors.focusRing.cgColor
            layer.borderWidth = 2
        case .disabled:
            layer.backgroundColor = DesignSystem.Colors.controlBackground.cgColor
            layer.borderColor = DesignSystem.Colors.borderSubtle.cgColor
            layer.borderWidth = 1
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        if let ta = trackingArea {
            addTrackingArea(ta)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        if visualState == .normal {
            visualState = .hovered
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if visualState == .hovered {
            visualState = .normal
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        // We only change to pressed if it's currently hovered or normal
        if visualState == .hovered || visualState == .normal {
            visualState = .pressed
        }
        super.mouseDown(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        if visualState == .pressed {
            let loc = convert(event.locationInWindow, from: nil)
            visualState = bounds.contains(loc) ? .hovered : .normal
        }
        super.mouseUp(with: event)
    }
}
