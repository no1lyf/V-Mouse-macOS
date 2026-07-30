import Cocoa
import QuartzCore

final class GlassyBatteryView: NSView {
    // Battery level 0-100 (nil = unknown)
    var level: Int? {
        didSet {
            guard oldValue != level else { return }
            update(animated: true)
        }
    }

    private let gradient = CAGradientLayer()
    private let backgroundLayer = CALayer()
    private let borderLayer = CALayer()

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
        layer = CALayer()
        layer?.masksToBounds = false

        // Background tint (subtle) + border for edge definition
        backgroundLayer.backgroundColor = UIStyle.cardFillColor.cgColor
        borderLayer.borderColor = UIStyle.cardBorderColor.cgColor
        borderLayer.borderWidth = 1
        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(borderLayer)

        // Gradient fill
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.masksToBounds = true
        layer?.addSublayer(gradient)

        update(animated: false)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .appThemeDidChange,
            object: nil
        )
    }

    @objc private func themeDidChange() {
        update(animated: false)
    }

    // Colors are resolved to CGColor outside the draw cycle, so a system
    // light/dark switch must re-resolve them explicitly.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            self?.update(animated: false)
        }
    }

    override func layout() {
        super.layout()
        let r = bounds
        let radius = r.height / 2
        layer?.cornerRadius = radius
        backgroundLayer.frame = r
        backgroundLayer.cornerRadius = radius
        borderLayer.frame = r
        borderLayer.cornerRadius = radius

        // Width based on level
        let pct: CGFloat
        if let lvl = level { pct = max(0, min(100, CGFloat(lvl))) / 100.0 } else { pct = 0 }
        let w = max(0, r.width * pct)
        gradient.frame = CGRect(x: r.minX, y: r.minY, width: w, height: r.height)
        gradient.cornerRadius = radius
    }

    private func update(animated: Bool) {
        // A plain layer is deliberately used here. NSVisualEffectView can ask
        // an NSPopover to lay itself out again while the parent is already in
        // layout, which AppKit reports as illegal layout recursion.
        backgroundLayer.backgroundColor = UIStyle.cardFillColor.cgColor

        // Colors based on level
        let colors: [CGColor]
        let lvl = level ?? 0
        if lvl >= 60 {
            colors = [UIStyle.successColor.withAlphaComponent(0.9).cgColor,
                      UIStyle.successColor.withAlphaComponent(0.6).cgColor]
        } else if lvl >= 30 {
            colors = [NSColor.systemYellow.withAlphaComponent(0.9).cgColor,
                      NSColor.systemYellow.withAlphaComponent(0.6).cgColor]
        } else {
            colors = [UIStyle.dangerColor.withAlphaComponent(0.95).cgColor,
                      UIStyle.dangerColor.withAlphaComponent(0.7).cgColor]
        }
        if animated {
            let colorAnim = CABasicAnimation(keyPath: "colors")
            colorAnim.duration = 0.3
            colorAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            gradient.add(colorAnim, forKey: "colors")
        }
        gradient.colors = colors

        // Pulse when low
        if let l = level, l <= 20 {
            if gradient.animation(forKey: "pulse") == nil {
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 1.0
                a.toValue = 0.6
                a.autoreverses = true
                a.repeatCount = .infinity
                a.duration = 0.8
                gradient.add(a, forKey: "pulse")
            }
        } else {
            gradient.removeAnimation(forKey: "pulse")
        }

        // Animate width change
        if animated {
            let widthAnim = CABasicAnimation(keyPath: "bounds.size.width")
            widthAnim.duration = 0.3
            widthAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            widthAnim.fromValue = gradient.presentation()?.bounds.width
            widthAnim.toValue = nil // final will be applied in layout
            gradient.add(widthAnim, forKey: "width")
        }

        needsLayout = true
    }
}
