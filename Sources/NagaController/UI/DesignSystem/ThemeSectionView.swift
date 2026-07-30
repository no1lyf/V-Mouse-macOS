import Cocoa

class ThemeSectionView: NSView {
    let contentStack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "")
    
    init(title: String) {
        super.init(frame: .zero)
        titleLabel.stringValue = title
        setup()
        
        let wrapper = NSStackView()
        wrapper.orientation = .vertical
        wrapper.spacing = 8
        wrapper.alignment = .centerX
        
        titleLabel.font = Typography.sectionTitle
        titleLabel.textColor = DesignSystem.Colors.textPrimary
        
        contentStack.orientation = .vertical
        contentStack.spacing = 8
        contentStack.alignment = .centerX
        
        wrapper.addArrangedSubview(titleLabel)
        wrapper.addArrangedSubview(contentStack)
        contentStack.widthAnchor.constraint(equalTo: wrapper.widthAnchor).isActive = true
        
        addSubview(wrapper)
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrapper.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            wrapper.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            wrapper.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            wrapper.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    var titleText: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    /// Turns the section title into an editable field styled like the label.
    /// The placeholder shows the default name; clearing the field restores it.
    func makeTitleEditable(placeholder: String, tag: Int, tooltip: String? = nil, target: AnyObject?, action: Selector) {
        titleLabel.toolTip = tooltip
        titleLabel.isEditable = true
        titleLabel.isSelectable = true
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.focusRingType = .exterior
        titleLabel.alignment = .center
        titleLabel.placeholderString = placeholder
        titleLabel.tag = tag
        titleLabel.target = target
        titleLabel.action = action
        // Commit on focus loss too, matching the per-key name fields.
        (titleLabel.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        // Keep a usable click/edit target even while the text is empty.
        titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
    }

    var isTitleBeingEdited: Bool { titleLabel.currentEditor() != nil }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = DesignSystem.Radius.card
        
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .appThemeDidChange, object: nil)
    }
    
    @objc private func themeDidChange() {
        titleLabel.textColor = DesignSystem.Colors.textSecondary
        needsDisplay = true
        updateLayer()
    }
    
    override func updateLayer() {
        super.updateLayer()
        guard let layer = self.layer else { return }
        
        layer.backgroundColor = DesignSystem.Colors.sectionBackground.cgColor
        layer.borderWidth = 1
        layer.borderColor = DesignSystem.Colors.borderSubtle.cgColor
    }
}
