import Cocoa
import UniformTypeIdentifiers

private final class KeyCaptureField: NSTextField {
    var onKeyCaptured: ((NSEvent) -> Void)?
    var onFocusChanged: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            currentEditor()?.selectAll(nil)
            onFocusChanged?(true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onFocusChanged?(false)
        }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        onKeyCaptured?(event)
    }

    override func flagsChanged(with event: NSEvent) {
        onKeyCaptured?(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder == self {
            onKeyCaptured?(event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

final class ActionEditorViewController: NSViewController {
    private let buttonIndex: Int
    private let onComplete: (ActionType?) -> Void

    private let segmented = NSSegmentedControl(labels: ["按键", "鼠标", "mac快捷键", "打开", "命令", "文本", "配置"].map(L10n.text), trackingMode: .selectOne, target: nil, action: nil)

    // Common
    private let descriptionField = NSTextField(string: "")

    // Key Sequence
    private let keyField = KeyCaptureField()
    private let modCmd = NSButton(checkboxWithTitle: "⌘", target: nil, action: nil)
    private let modAlt = NSButton(checkboxWithTitle: "⌥", target: nil, action: nil)
    private let modCtrl = NSButton(checkboxWithTitle: "⌃", target: nil, action: nil)
    private let modShift = NSButton(checkboxWithTitle: "⇧", target: nil, action: nil)
    private let modFn = NSButton(checkboxWithTitle: "fn", target: nil, action: nil)

    // Mouse
    private let mousePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    // macOS shortcuts (Mos grouping, excluding features already represented
    // by the dedicated Mouse, Open and Key sections).
    private let macShortcutPopup = NSPopUpButton(frame: .zero, pullsDown: true)
    private var selectedMacShortcutIdentifier: String?
    
    // Virtual Keyboard
    private let virtualKeyBtn = NSButton(title: L10n.text("虚拟键盘..."), target: nil, action: nil)

    // Application

    private let openTargetField = NSTextField(string: "")

    // Command
    private let commandView = NSTextView(frame: .zero)
    private let commandScroll = NSScrollView(frame: .zero)

    // Profile Switch
    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    // Text Snippet
    private let textSnippetView = NSTextView(frame: .zero)
    private let textSnippetScroll = NSScrollView(frame: .zero)

    private let saveButton = NSButton(title: L10n.text("保存"), target: nil, action: nil)
    private let cancelButton = NSButton(title: L10n.text("取消"), target: nil, action: nil)

    private let contentStack = NSStackView()

    private var recordedKeyCode: UInt16?
    private var recordedKeyIdentifier: String?
    private let macroWarningLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: L10n.text("当前为宏动作，此编辑器暂不支持编辑宏；保存其它类型会覆盖它。"))
        label.font = Typography.bodySecondary
        label.textColor = DesignSystem.Colors.warningText
        label.isHidden = true
        return label
    }()

    /// The profile this editor reads and previews. Passing it explicitly
    /// keeps the prefill aligned with the table the caller will write to.
    private let targetProfileName: String?
    /// Scopes the profile-switch action's choices to one device's profiles.
    private let targetDeviceKey: String?

    init(buttonIndex: Int, profileName: String? = nil, deviceKey: String? = nil, onComplete: @escaping (ActionType?) -> Void) {
        self.buttonIndex = buttonIndex
        self.targetProfileName = profileName
        self.targetDeviceKey = deviceKey
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 760, height: 480)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        self.view = NSView()
        let background = UIStyle.makeBackground(material: .sheet)
        background.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(background)

        let header = NSTextField(labelWithString: L10n.format("编辑动作 — %@", InputSourceCatalog.mappingName(for: buttonIndex)))
        header.font = .systemFont(ofSize: 17, weight: .semibold)

        segmented.target = self
        segmented.action = #selector(segmentedChanged)
        segmented.selectedSegment = 0
        segmented.segmentDistribution = .fillProportionally
        segmented.segmentStyle = .automatic

        // Description
        let descLabel = NSTextField(labelWithString: L10n.text("描述 (可选):"))
        descriptionField.placeholderString = L10n.text("例如: 复制")

        // Key UI
        keyField.translatesAutoresizingMaskIntoConstraints = false
        keyField.placeholderString = L10n.text("按下一个键")
        keyField.alignment = .center
        keyField.isEditable = false
        keyField.drawsBackground = false
        keyField.isBordered = false
        keyField.font = .systemFont(ofSize: 18, weight: .medium)
        keyField.wantsLayer = true
        keyField.layer?.cornerRadius = 8
        keyField.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        keyField.layer?.borderColor = NSColor.separatorColor.cgColor
        keyField.layer?.borderWidth = 1
        keyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        keyField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        keyField.setContentCompressionResistancePriority(.required, for: .horizontal)
        keyField.onKeyCaptured = { [weak self] event in
            self?.capture(event: event)
        }
        keyField.onFocusChanged = { [weak keyField, weak self] focused in
            keyField?.layer?.borderColor = (focused ? NSColor.systemBlue.cgColor : NSColor.separatorColor.cgColor)
            keyField?.layer?.borderWidth = focused ? 2 : 1
            if focused {
                self?.saveButton.keyEquivalent = ""
                self?.cancelButton.keyEquivalent = ""
            } else {
                self?.saveButton.keyEquivalent = "\r"
                self?.cancelButton.keyEquivalent = "\u{1b}"
            }
        }

        [modCmd, modAlt, modCtrl, modShift, modFn].forEach { button in
            button.target = self
            button.action = #selector(modifierCheckboxChanged(_:))
        }

        virtualKeyBtn.target = self
        virtualKeyBtn.action = #selector(showVirtualKeyboard(_:))
        
        let keyRow = NSStackView(views: [NSTextField(labelWithString: L10n.text("按键:")), keyField, virtualKeyBtn, NSView()])
        keyRow.spacing = 8
        let modsRow = NSStackView(views: [NSTextField(labelWithString: L10n.text("修饰键:")), modCmd, modAlt, modCtrl, modShift, modFn, NSView()])
        modsRow.spacing = 8
        let keyHint = NSTextField(labelWithString: L10n.text("点击上方的捕获框，然后按下您要录制的键盘快捷键 (例如 ⇧⌘4)。"))
        keyHint.font = .systemFont(ofSize: 13)
        keyHint.textColor = .secondaryLabelColor
        keyHint.lineBreakMode = .byWordWrapping
        keyHint.maximumNumberOfLines = 2
        let keyGroup = group(L10n.text("按键序列"), views: [keyRow, modsRow, keyHint])

        // Mouse UI. Keep the existing compact popup layout and merge the
        // three Mos scroll controls into the same action list.
        let mouseItems: [(String, String)] = [
            (L10n.text("左键"), "mouse:0"),
            (L10n.text("右键"), "mouse:1"),
            (L10n.text("中键"), "mouse:2"),
            (L10n.text("前进"), "mouse:3"),
            (L10n.text("后退"), "mouse:4")
        ]
        for (title, identifier) in mouseItems {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = identifier
            mousePopup.menu?.addItem(item)
        }
        mousePopup.menu?.addItem(.separator())
        for role in ScrollControlRole.allCases {
            let item = NSMenuItem(title: role.displayName, action: nil, keyEquivalent: "")
            item.representedObject = "scroll:\(role.rawValue)"
            mousePopup.menu?.addItem(item)
        }
        let mouseRow = NSStackView(views: [NSTextField(labelWithString: L10n.text("鼠标动作:")), mousePopup, NSView()])
        mouseRow.spacing = 8
        let mouseHint = NSTextField(wrappingLabelWithString: L10n.text("滚轮动作按住时生效；松开、停用映射、Event Tap 失效或鼠标断开时都会强制清除状态。"))
        mouseHint.font = .systemFont(ofSize: 13)
        mouseHint.textColor = .secondaryLabelColor
        let mouseGroup = group(L10n.text("鼠标"), views: [mouseRow, mouseHint])

        configureMacShortcutMenu()
        let macShortcutRow = NSStackView(views: [NSTextField(labelWithString: L10n.text("快捷键:")), macShortcutPopup, NSView()])
        macShortcutRow.spacing = 8
        let macShortcutHint = NSTextField(wrappingLabelWithString: L10n.text("分组与 Mos 按键绑定一致；纯修饰键在按住鼠标来源期间保持，松开后立即释放。"))
        macShortcutHint.font = .systemFont(ofSize: 13)
        macShortcutHint.textColor = .secondaryLabelColor
        let macShortcutGroup = group(L10n.text("mac快捷键"), views: [macShortcutRow, macShortcutHint])

        // App UI
        let browse = NSButton(title: L10n.text("浏览..."), target: self, action: #selector(browseApp))
        browse.image = UIStyle.symbol("folder", size: 13)
        browse.imagePosition = .imageLeading
        openTargetField.placeholderString = L10n.text("应用、文件、文件夹路径，或 https:// 网址")
        openTargetField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        openTargetField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let targetRow = NSStackView(views: [NSTextField(labelWithString: L10n.text("目标:")), openTargetField, browse])
        targetRow.spacing = 8
        targetRow.translatesAutoresizingMaskIntoConstraints = false
        targetRow.widthAnchor.constraint(greaterThanOrEqualToConstant: 620).isActive = true
        let appGroup = group(L10n.text("打开目标"), views: [targetRow])

        // Command UI
        commandView.isAutomaticQuoteSubstitutionEnabled = false
        commandView.isAutomaticDashSubstitutionEnabled = false
        commandView.isAutomaticLinkDetectionEnabled = false
        commandView.isRichText = false
        commandView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        commandView.textContainerInset = NSSize(width: 6, height: 6)
        commandView.backgroundColor = .textBackgroundColor
        commandView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        commandView.isVerticallyResizable = true
        commandView.isHorizontallyResizable = false
        commandView.textContainer?.widthTracksTextView = true

        commandScroll.documentView = commandView
        commandScroll.hasVerticalScroller = true
        commandScroll.borderType = .bezelBorder
        commandScroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            commandScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 620),
            commandScroll.heightAnchor.constraint(equalToConstant: 140)
        ])

        let commandHint = NSTextField(labelWithString: L10n.text("例如: say Hello 或 osascript ..."))
        commandHint.font = .systemFont(ofSize: 13)
        commandHint.textColor = .secondaryLabelColor
        let cmdGroup = group(L10n.text("系统命令"), views: [commandScroll, commandHint])

        // Text Snippet UI
        textSnippetView.isAutomaticQuoteSubstitutionEnabled = false
        textSnippetView.isAutomaticDashSubstitutionEnabled = false
        textSnippetView.isAutomaticLinkDetectionEnabled = false
        textSnippetView.isRichText = false
        textSnippetView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textSnippetView.textContainerInset = NSSize(width: 6, height: 6)
        textSnippetView.backgroundColor = .textBackgroundColor
        textSnippetView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textSnippetView.isVerticallyResizable = true
        textSnippetView.isHorizontallyResizable = false
        textSnippetView.textContainer?.widthTracksTextView = true

        textSnippetScroll.documentView = textSnippetView
        textSnippetScroll.hasVerticalScroller = true
        textSnippetScroll.borderType = .bezelBorder
        textSnippetScroll.translatesAutoresizingMaskIntoConstraints = false
        textSnippetScroll.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let textHint = NSTextField(labelWithString: L10n.text("输入希望该按钮输出的文本。按下按钮时将原样发送。"))
        textHint.font = .systemFont(ofSize: 13)
        textHint.textColor = .secondaryLabelColor
        textHint.lineBreakMode = .byWordWrapping
        textHint.maximumNumberOfLines = 2
        let textGroup = group(L10n.text("文本片段"), views: [textSnippetScroll, textHint])

        // Profile UI
        let profLabel = NSTextField(labelWithString: L10n.text("配置文件:"))
        if let targetDeviceKey {
            profilePopup.addItems(withTitles: ConfigManager.shared.profileNames(forDeviceKey: targetDeviceKey))
        } else {
            profilePopup.addItems(withTitles: ConfigManager.shared.availableProfiles())
        }
        let profRow = NSStackView(views: [profLabel, profilePopup])
        profRow.spacing = 8
        let profGroup = group(L10n.text("切换配置文件"), views: [profRow])

        // Content stack
        contentStack.orientation = .vertical
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let descStack = NSStackView(views: [descLabel, descriptionField])
        descStack.spacing = 6

        let buttonsStack = NSStackView()
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 8
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.image = UIStyle.symbol("xmark.circle", size: 14)
        cancelButton.imagePosition = .imageLeading
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.toolTip = L10n.text("关闭而不保存")

        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.image = UIStyle.symbol("tray.and.arrow.down", size: 14, weight: .semibold)
        saveButton.imagePosition = .imageLeading
        saveButton.keyEquivalent = "\r"
        saveButton.toolTip = L10n.text("保存更改")
        buttonsStack.addArrangedSubview(macroWarningLabel)
        buttonsStack.addArrangedSubview(NSView())
        buttonsStack.addArrangedSubview(cancelButton)
        buttonsStack.addArrangedSubview(saveButton)

        let footerHint = UIStyle.makeFooter(L10n.text("编辑动作说明：选择一种动作类型并保存；按住型动作会在松开鼠标来源时立即释放。"))

        view.addSubview(header)
        view.addSubview(segmented)
        view.addSubview(descStack)
        view.addSubview(contentStack)
        view.addSubview(footerHint)
        view.addSubview(buttonsStack)

        for v in [header, segmented, descStack, contentStack, footerHint, buttonsStack] { v.translatesAutoresizingMaskIntoConstraints = false }

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            background.topAnchor.constraint(equalTo: view.topAnchor),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),

            segmented.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            segmented.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            segmented.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),

            descStack.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 10),
            descStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            descStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            contentStack.topAnchor.constraint(equalTo: descStack.bottomAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            footerHint.topAnchor.constraint(greaterThanOrEqualTo: contentStack.bottomAnchor, constant: 12),
            footerHint.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            footerHint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            buttonsStack.topAnchor.constraint(equalTo: footerHint.bottomAnchor, constant: 10),
            buttonsStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            buttonsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            buttonsStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 680),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 420)
        ])

        // Add groups and show first
        contentStack.addArrangedSubview(keyGroup)
        contentStack.addArrangedSubview(mouseGroup)
        contentStack.addArrangedSubview(macShortcutGroup)
        contentStack.addArrangedSubview(appGroup)
        contentStack.addArrangedSubview(cmdGroup)
        contentStack.addArrangedSubview(textGroup)
        contentStack.addArrangedSubview(profGroup)
        selectGroup(index: 0)

        preloadCurrent()
    }

    private func group(_ title: String, views: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        stack.addArrangedSubview(titleLabel)
        views.forEach { stack.addArrangedSubview($0) }
        return stack
    }

    private func configureMacShortcutMenu() {
        macShortcutPopup.removeAllItems()
        macShortcutPopup.addItem(withTitle: L10n.text("选择 mac 快捷键"))
        macShortcutPopup.item(at: 0)?.isEnabled = false

        for category in SystemActionDefinition.categories {
            let categoryItem = NSMenuItem(title: category, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: category)
            for definition in SystemActionDefinition.definitions(in: category) {
                let item = NSMenuItem(
                    title: definition.name,
                    action: #selector(macShortcutSelected(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = definition.identifier
                submenu.addItem(item)
            }
            categoryItem.submenu = submenu
            macShortcutPopup.menu?.addItem(categoryItem)
        }

        if let first = SystemActionDefinition.all.first {
            selectMacShortcut(identifier: first.identifier)
        }
    }

    @objc private func macShortcutSelected(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        selectMacShortcut(identifier: identifier)
    }

    private func selectMacShortcut(identifier: String) {
        guard let definition = SystemActionDefinition.definition(for: identifier) else { return }
        selectedMacShortcutIdentifier = definition.identifier
        macShortcutPopup.item(at: 0)?.title = "\(definition.category) · \(definition.name)"
        macShortcutPopup.toolTip = definition.stroke.formattedShortcut()
    }

    private func selectMouseAction(identifier: String) {
        guard let index = mousePopup.itemArray.firstIndex(where: {
            $0.representedObject as? String == identifier
        }) else { return }
        mousePopup.selectItem(at: index)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if segmented.selectedSegment == 0 {
            view.window?.makeFirstResponder(keyField)
        } else if segmented.selectedSegment == 3 {
            view.window?.makeFirstResponder(openTargetField)
        } else if segmented.selectedSegment == 4 {
            view.window?.makeFirstResponder(commandView)
        } else if segmented.selectedSegment == 5 {
            view.window?.makeFirstResponder(textSnippetView)
        }
    }

    @objc private func showVirtualKeyboard(_ sender: NSButton) {
        let kbView = MacKeyboardView(frame: NSRect(x: 0, y: 0, width: 680, height: 300))
        let vc = NSViewController()
        vc.view = kbView
        
        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        
        kbView.onKeySelected = { [weak self, weak popover] stroke in
            guard let self = self else { return }
            
            // Uncheck all first
            self.modCmd.state = .off
            self.modAlt.state = .off
            self.modCtrl.state = .off
            self.modShift.state = .off
            self.modFn.state = .off

            for m in stroke.modifiers {
                switch m.lowercased() {
                case "cmd", "command": self.modCmd.state = .on
                case "opt", "alt", "option": self.modAlt.state = .on
                case "ctrl", "control": self.modCtrl.state = .on
                case "shift": self.modShift.state = .on
                case "fn": self.modFn.state = .on
                default: break
                }
            }
            
            if let keyCode = stroke.keyCode {
                let canonical = KeyStroke.canonicalKeyString(for: keyCode, characters: nil)
                self.recordedKeyCode = keyCode
                self.recordedKeyIdentifier = canonical
            } else {
                self.recordedKeyCode = KeyStroke.keyCode(for: stroke.key)
                self.recordedKeyIdentifier = stroke.key
            }
            self.updateKeyFieldDisplay()
            popover?.close()
        }
        
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private func segmentedChanged() {
        selectGroup(index: segmented.selectedSegment)
        if segmented.selectedSegment == 0 {
            view.window?.makeFirstResponder(keyField)
        } else if segmented.selectedSegment == 3 {
            view.window?.makeFirstResponder(openTargetField)
        } else if segmented.selectedSegment == 4 {
            view.window?.makeFirstResponder(commandView)
        } else if segmented.selectedSegment == 5 {
            view.window?.makeFirstResponder(textSnippetView)
        }
    }

    private func selectGroup(index: Int) {
        for (i, v) in contentStack.arrangedSubviews.enumerated() {
            v.isHidden = (i != index)
        }
    }

    private func preloadCurrent() {
        let sourceProfile = targetProfileName ?? ConfigManager.shared.currentProfileName
        let current = ConfigManager.shared.mappingForProfile(named: sourceProfile)[buttonIndex]
        recordedKeyCode = nil
        recordedKeyIdentifier = nil
        updateKeyFieldDisplay()
        applyModifiers(from: [])
        textSnippetView.string = ""
        switch current {
        case .keySequence(let keys, let d):
            if let first = keys.first {
                recordedKeyIdentifier = first.key
                recordedKeyCode = first.keyCode ?? KeyStroke.keyCode(for: first.key)
                applyModifiers(from: first.modifiers)
                updateKeyFieldDisplay()
            }
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 0
            selectGroup(index: 0)
        case .mouseClick(let button, let d):
            selectMouseAction(identifier: "mouse:\(min(max(button, 0), 4))")
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 1
            selectGroup(index: 1)
        case .application(let path, let d):
            setOpenTarget(path)
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 3
            selectGroup(index: 3)
        case .systemCommand(let cmd, let d):
            commandView.string = cmd
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 4
            selectGroup(index: 4)
        case .textSnippet(let text, let d):
            textSnippetView.string = text
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 5
            selectGroup(index: 5)
        case .profileSwitch(let profile, let d):
            profilePopup.selectItem(withTitle: profile)
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 6
            selectGroup(index: 6)
        case .systemAction(let identifier, let d):
            selectMacShortcut(identifier: identifier)
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 2
            selectGroup(index: 2)
        case .scrollControl(let role, let d):
            selectMouseAction(identifier: "scroll:\(role.rawValue)")
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 1
            selectGroup(index: 1)
        case .openTarget(let target, let d):
            setOpenTarget(target)
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 3
            selectGroup(index: 3)
        case .macro:
            // Editing macros is not supported in this lightweight editor.
            // Surface that instead of silently showing an empty key page.
            macroWarningLabel.isHidden = false
        case .none:
            break
        }
    }

    @objc private func cancelTapped() {
        dismiss(self)
        onComplete(nil)
    }

    @objc private func saveTapped() {
        let desc = descriptionField.stringValue.isEmpty ? nil : descriptionField.stringValue
        switch segmented.selectedSegment {
        case 0:
            guard let identifier = recordedKeyIdentifier, !identifier.isEmpty else {
                // Nothing recorded yet — keep the sheet open instead of
                // silently discarding, so the user knows the save did nothing.
                NSSound.beep()
                view.window?.makeFirstResponder(keyField)
                return
            }
            let mods = currentModifiers()
            let code = recordedKeyCode ?? KeyStroke.keyCode(for: identifier)
            let stroke = KeyStroke(key: identifier, modifiers: mods, keyCode: code)
            onComplete(.keySequence(keys: [stroke], description: desc))
        case 1:
            guard let identifier = mousePopup.selectedItem?.representedObject as? String else {
                onComplete(nil)
                break
            }
            if identifier.hasPrefix("mouse:"),
               let button = Int(identifier.dropFirst("mouse:".count)) {
                onComplete(.mouseClick(button: button, description: desc))
            } else if identifier.hasPrefix("scroll:"),
                      let role = ScrollControlRole(rawValue: String(identifier.dropFirst("scroll:".count))) {
                onComplete(.scrollControl(role: role, description: desc))
            } else {
                onComplete(nil)
            }
        case 2:
            guard let identifier = selectedMacShortcutIdentifier else { onComplete(nil); break }
            onComplete(.systemAction(identifier: identifier, description: desc))
        case 3:
            let target = openTargetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            // Empty input keeps the sheet open (beep + focus) rather than
            // silently closing as if the empty action were saved.
            guard !target.isEmpty else { NSSound.beep(); view.window?.makeFirstResponder(openTargetField); return }
            onComplete(.openTarget(target: target, description: desc))
        case 4:
            let cmd = commandView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cmd.isEmpty else { NSSound.beep(); view.window?.makeFirstResponder(commandView); return }
            onComplete(.systemCommand(command: cmd, description: desc))
        case 5:
            let snippet = textSnippetView.string
            guard !snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                NSSound.beep(); view.window?.makeFirstResponder(textSnippetView); return
            }
            onComplete(.textSnippet(text: snippet, description: desc))
        case 6:
            if let title = profilePopup.titleOfSelectedItem { onComplete(.profileSwitch(profile: title, description: desc)) } else { onComplete(nil) }
        default:
            onComplete(nil)
        }
        dismiss(self)
    }

    private func set(mod: NSButton, from on: Bool) { mod.state = on ? .on : .off }

    private func capture(event: NSEvent) {
        if event.type == .flagsChanged {
            applyModifiers(from: event.modifierFlags)
            updateKeyFieldDisplay()
            return
        }

        guard event.type == .keyDown else { return }
        if event.isARepeat { return }

        applyModifiers(from: event.modifierFlags)

        let keyCode = UInt16(event.keyCode)
        let canonical = KeyStroke.canonicalKeyString(for: keyCode, characters: event.charactersIgnoringModifiers)
        guard !canonical.isEmpty else {
            NSSound.beep()
            return
        }

        recordedKeyCode = keyCode
        recordedKeyIdentifier = canonical
        updateKeyFieldDisplay()
    }

    private func updateKeyFieldDisplay() {
        if let identifier = recordedKeyIdentifier, !identifier.isEmpty {
            let mods = currentModifiers()
            let code = recordedKeyCode ?? KeyStroke.keyCode(for: identifier)
            let stroke = KeyStroke(key: identifier, modifiers: mods, keyCode: code)
            let display = stroke.formattedShortcut()
            keyField.stringValue = display
            keyField.toolTip = display
        } else {
            keyField.stringValue = ""
            keyField.toolTip = nil
        }
    }

    private func applyModifiers(from flags: NSEvent.ModifierFlags) {
        set(mod: modCmd, from: flags.contains(.command))
        set(mod: modAlt, from: flags.contains(.option))
        set(mod: modCtrl, from: flags.contains(.control))
        set(mod: modShift, from: flags.contains(.shift))
        // .function is NOT read from events: macOS sets it implicitly for
        // arrow/F-keys, which would spuriously check fn during capture. The
        // fn checkbox is driven only by the user, the virtual keyboard, or a
        // previously saved stroke.
        updateKeyFieldDisplay()
    }

    private func applyModifiers(from identifiers: [String]) {
        let lower = Set(identifiers.map { $0.lowercased() })
        set(mod: modCmd, from: lower.contains("cmd") || lower.contains("command"))
        set(mod: modAlt, from: lower.contains("alt") || lower.contains("option"))
        set(mod: modCtrl, from: lower.contains("ctrl") || lower.contains("control"))
        set(mod: modShift, from: lower.contains("shift"))
        set(mod: modFn, from: lower.contains("fn"))
        updateKeyFieldDisplay()
    }

    private func currentModifiers() -> [String] {
        var result: [String] = []
        if modCmd.state == .on { result.append("cmd") }
        if modAlt.state == .on { result.append("alt") }
        if modCtrl.state == .on { result.append("ctrl") }
        if modShift.state == .on { result.append("shift") }
        if modFn.state == .on { result.append("fn") }
        return result
    }

    @objc private func modifierCheckboxChanged(_ sender: NSButton) {
        updateKeyFieldDisplay()
    }

    @objc private func browseApp() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.beginSheetModal(for: self.view.window!) { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            self?.setOpenTarget(url.path)
        }
    }

    private func setOpenTarget(_ target: String) {
        openTargetField.stringValue = target
        openTargetField.toolTip = target
    }
}
