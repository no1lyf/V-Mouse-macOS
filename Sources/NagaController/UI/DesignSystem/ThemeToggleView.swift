import Cocoa

class ThemeToggleView: NSStackView {
    let switchControl = NSSwitch()
    let label = NSTextField(labelWithString: "")
    
    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }
    
    var state: NSControl.StateValue {
        get { switchControl.state }
        set { switchControl.state = newValue }
    }
    
    var target: AnyObject? {
        get { switchControl.target }
        set { switchControl.target = newValue }
    }
    
    var action: Selector? {
        get { switchControl.action }
        set { switchControl.action = newValue }
    }
    
    var isEnabled: Bool {
        get { switchControl.isEnabled }
        set { 
            switchControl.isEnabled = newValue 
            label.alphaValue = newValue ? 1.0 : 0.5
        }
    }
    
    init(title: String) {
        super.init(frame: .zero)
        self.orientation = .horizontal
        self.alignment = .centerY
        self.spacing = 8
        
        self.title = title
        label.font = Typography.bodyNormal
        
        addArrangedSubview(switchControl)
        addArrangedSubview(label)
        
        updateTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(updateTheme), name: .appThemeDidChange, object: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    @objc private func updateTheme() {
        label.textColor = DesignSystem.Colors.textPrimary
    }
}
