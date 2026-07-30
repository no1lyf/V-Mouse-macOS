import Cocoa

private final class ScrollHotkeyField: NSTextField {
    var onCapture: ((ScrollHotkey) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) { capture(event) }
    override func flagsChanged(with event: NSEvent) { capture(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder == self { capture(event); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    private func capture(_ event: NSEvent) {
        guard event.type == .keyDown || event.type == .flagsChanged, !event.isARepeat else { return }
        let code = UInt16(event.keyCode)
        if event.type == .flagsChanged,
           ![54, 55, 56, 58, 59, 60, 61, 62, 63].contains(code) { return }
        var modifiers: [String] = []
        if event.type == .keyDown {
            if event.modifierFlags.contains(.command) { modifiers.append("cmd") }
            if event.modifierFlags.contains(.option) { modifiers.append("alt") }
            if event.modifierFlags.contains(.control) { modifiers.append("ctrl") }
            if event.modifierFlags.contains(.shift) { modifiers.append("shift") }
        }
        onCapture?(ScrollHotkey(keyCode: code, modifiers: modifiers))
    }
}

final class ScrollSettingsWindowController: ThemedWindowController {
    static let shared = ScrollSettingsWindowController()

    private init() {
        let controller = ScrollSettingsViewController()
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "\(AppIdentity.productName) — \(L10n.text("滚轮设置"))"
        window.setContentSize(NSSize(width: 650, height: 720))
        window.contentMinSize = NSSize(width: 480, height: 400)
        window.setFrameAutosaveName("NagaController.ScrollSettingsWindow")
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func makeContentViewController() -> NSViewController { ScrollSettingsViewController() }
    override func makeTitle() -> String { "\(AppIdentity.productName) — \(L10n.text("滚轮设置"))" }
    override func willShow() {
        (window?.contentViewController as? ScrollSettingsViewController)?.reload()
    }
}

final class ScrollSettingsViewController: NSViewController {
    private let enabled = ThemeToggleView(title: L10n.text("启用滚轮增强"))
    private let smooth = ThemeToggleView(title: L10n.text("平滑滚动"))
    private let smoothVertical = ThemeToggleView(title: L10n.text("平滑垂直轴"))
    private let smoothHorizontal = ThemeToggleView(title: L10n.text("平滑水平轴"))
    private let simulateTrackpad = ThemeToggleView(title: L10n.text("模拟触控板滚动阶段"))
    private let reverse = ThemeToggleView(title: L10n.text("反向滚动"))
    private let reverseVertical = ThemeToggleView(title: L10n.text("反向垂直轴"))
    private let reverseHorizontal = ThemeToggleView(title: L10n.text("反向水平轴"))
    private let step = NSSlider(value: 33.6, minValue: 1, maxValue: 120, target: nil, action: nil)
    private let speed = NSSlider(value: 2.7, minValue: 0.1, maxValue: 8, target: nil, action: nil)
    private let duration = NSSlider(value: 4.35, minValue: 0.1, maxValue: 5, target: nil, action: nil)
    private let deadZone = NSSlider(value: 1, minValue: 0.05, maxValue: 5, target: nil, action: nil)
    private let stepValue = NSTextField(labelWithString: "")
    private let speedValue = NSTextField(labelWithString: "")
    private let durationValue = NSTextField(labelWithString: "")
    private let deadZoneValue = NSTextField(labelWithString: "")
    private let dashField = ScrollHotkeyField(string: "")
    private let shiftField = ScrollHotkeyField(string: "")
    private let blockField = ScrollHotkeyField(string: "")
    private var working = ScrollSettings.defaults

    override func loadView() {
        view = NSView()
        let background = UIStyle.makeBackground(material: .windowBackground)
        background.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(background)
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)

        let title = NSTextField(labelWithString: L10n.text("滚轮设置"))
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.alignment = .left
        let subtitle = NSTextField(wrappingLabelWithString: L10n.text("参考 Mos 的滚动模型。设置只处理鼠标滚轮；带滚动阶段或惯性阶段的触控板事件保持原样。"))
        subtitle.alignment = .left
        subtitle.textColor = .secondaryLabelColor
        content.addArrangedSubview(title)
        content.addArrangedSubview(subtitle)
        subtitle.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -44).isActive = true

        for control in [enabled, smooth, smoothVertical, smoothHorizontal, simulateTrackpad,
                        reverse, reverseVertical, reverseHorizontal] {
            control.target = self
            control.action = #selector(optionChanged)
        }
        let masterCard = card(L10n.text("总开关"), [enabled])
        let smoothCard = card(L10n.text("平滑"), [smooth, indented(smoothVertical), indented(smoothHorizontal), indented(simulateTrackpad)])
        let directionCard = card(L10n.text("方向"), [reverse, indented(reverseVertical), indented(reverseHorizontal)])
        [masterCard, smoothCard, directionCard].forEach {
            content.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -44).isActive = true
        }

        for slider in [step, speed, duration, deadZone] {
            slider.target = self
            slider.action = #selector(sliderChanged)
            slider.isContinuous = true
        }
        let feelCard = card(L10n.text("手感"), [
            sliderRow(L10n.text("步长"), slider: step, value: stepValue, hint: L10n.text("每个物理刻度输入的最小距离")),
            sliderRow(L10n.text("速度"), slider: speed, value: speedValue, hint: L10n.text("总滚动距离倍率")),
            sliderRow(L10n.text("持续时间"), slider: duration, value: durationValue, hint: L10n.text("越大越柔和；模拟触控板时固定为 4.75")),
            sliderRow(L10n.text("死区"), slider: deadZone, value: deadZoneValue, hint: L10n.text("停止时忽略的微小残余"))
        ])
        content.addArrangedSubview(feelCard)
        feelCard.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -44).isActive = true

        configureHotkey(dashField, role: .accelerate)
        configureHotkey(shiftField, role: .shiftAxis)
        configureHotkey(blockField, role: .blockSmooth)
        let hotkeyCard = card(L10n.text("按住型快捷键"), [
            hotkeyRow(L10n.text("加速"), field: dashField, tag: 0),
            hotkeyRow(L10n.text("纵向转横向"), field: shiftField, tag: 1),
            hotkeyRow(L10n.text("临时禁用平滑"), field: blockField, tag: 2)
        ])
        content.addArrangedSubview(hotkeyCard)
        hotkeyCard.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -44).isActive = true

        let note = NSTextField(wrappingLabelWithString: L10n.text("提示：这三项也可以直接绑定到鼠标侧键。键盘快捷键只改变滚轮状态，不会拦截物理键盘原键。"))
        note.font = .systemFont(ofSize: 13)
        note.textColor = .secondaryLabelColor
        content.addArrangedSubview(note)
        content.addArrangedSubview(UIStyle.makeFooter(L10n.text("滚轮设置说明：只处理鼠标滚轮，触控板保持原样；修改后点击“保存并应用”。")))

        let reset = ThemeButton(title: L10n.text("恢复默认设置"), target: self, action: #selector(resetDefaults))
        reset.buttonType = .normal
        let cancel = ThemeButton(title: L10n.text("取消"), target: self, action: #selector(cancelTapped))
        cancel.buttonType = .normal
        let save = ThemeButton(title: L10n.text("保存并应用"), target: self, action: #selector(saveTapped))
        save.buttonType = .primary
        save.keyEquivalent = "\r"
        let buttons = NSStackView(views: [reset, NSView(), cancel, save])
        buttons.spacing = 8
        content.addArrangedSubview(buttons)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = content
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            background.topAnchor.constraint(equalTo: view.topAnchor),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        reload()
        DispatchQueue.main.async {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func reload() {
        guard isViewLoaded else { return }
        working = ConfigManager.shared.getScrollSettings()
        syncControls()
    }

    private func card(_ title: String, _ views: [NSView]) -> NSView {
        let section = ThemeSectionView(title: title)
        views.forEach { section.contentStack.addArrangedSubview($0) }
        return section
    }

    private func indented(_ view: NSView) -> NSView {
        let row = NSStackView(views: [NSView(), view])
        row.views[0].widthAnchor.constraint(equalToConstant: 18).isActive = true
        return row
    }

    private func sliderRow(_ name: String, slider: NSSlider, value: NSTextField, hint: String) -> NSView {
        value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let label = NSTextField(labelWithString: name)
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 95).isActive = true
        let row = NSStackView(views: [label, slider, value])
        row.spacing = 8
        row.toolTip = hint
        return row
    }

    private func configureHotkey(_ field: ScrollHotkeyField, role: ScrollControlRole) {
        field.isEditable = false
        field.alignment = .center
        field.placeholderString = L10n.text("点击后按一个键")
        field.onCapture = { [weak self, weak field] hotkey in
            guard let self else { return }
            self.setHotkey(hotkey, role: role)
            field?.stringValue = hotkey.displayText
            self.view.window?.makeFirstResponder(nil)
        }
    }

    private func hotkeyRow(_ name: String, field: ScrollHotkeyField, tag: Int) -> NSView {
        let label = NSTextField(labelWithString: name)
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        let clear = ThemeButton(title: L10n.text("清除"), target: self, action: #selector(clearHotkey(_:)))
        clear.buttonType = .normal
        clear.tag = tag
        return NSStackView(views: [label, field, clear])
    }

    @objc private func optionChanged() {
        readControls()
        syncEnabledStates()
    }

    @objc private func sliderChanged() {
        readControls()
        syncValues()
    }

    @objc private func clearHotkey(_ sender: NSButton) {
        switch sender.tag {
        case 0: working.dashHotkey = nil
        case 1: working.shiftAxisHotkey = nil
        default: working.blockSmoothHotkey = nil
        }
        syncHotkeys()
    }

    @objc private func resetDefaults() {
        var defaults = ScrollSettings.defaults
        defaults.enabled = true
        defaults.smooth = true
        defaults.reverseHorizontal = true
        working = defaults
        syncControls()
    }

    @objc private func cancelTapped() { view.window?.close() }

    @objc private func saveTapped() {
        readControls()
        InputCoordinator.shared.setScrollSettings(working)
        view.window?.close()
    }

    private func readControls() {
        working.enabled = enabled.state == .on
        working.smooth = smooth.state == .on
        working.smoothVertical = smoothVertical.state == .on
        working.smoothHorizontal = smoothHorizontal.state == .on
        working.simulateTrackpad = simulateTrackpad.state == .on
        working.reverse = reverse.state == .on
        working.reverseVertical = reverseVertical.state == .on
        working.reverseHorizontal = reverseHorizontal.state == .on
        working.step = step.doubleValue
        working.speed = speed.doubleValue
        working.duration = working.simulateTrackpad ? 4.75 : duration.doubleValue
        working.deadZone = deadZone.doubleValue
    }

    private func syncControls() {
        enabled.state = working.enabled ? .on : .off
        smooth.state = working.smooth ? .on : .off
        smoothVertical.state = working.smoothVertical ? .on : .off
        smoothHorizontal.state = working.smoothHorizontal ? .on : .off
        simulateTrackpad.state = working.simulateTrackpad ? .on : .off
        reverse.state = working.reverse ? .on : .off
        reverseVertical.state = working.reverseVertical ? .on : .off
        reverseHorizontal.state = working.reverseHorizontal ? .on : .off
        step.doubleValue = working.step
        speed.doubleValue = working.speed
        duration.doubleValue = working.simulateTrackpad ? 4.75 : working.duration
        deadZone.doubleValue = working.deadZone
        syncValues()
        syncHotkeys()
        syncEnabledStates()
    }

    private func syncValues() {
        stepValue.stringValue = String(format: "%.1f", step.doubleValue)
        speedValue.stringValue = String(format: "%.2f", speed.doubleValue)
        durationValue.stringValue = String(format: "%.2f", working.simulateTrackpad ? 4.75 : duration.doubleValue)
        deadZoneValue.stringValue = String(format: "%.2f", deadZone.doubleValue)
    }

    private func syncHotkeys() {
        dashField.stringValue = working.dashHotkey?.displayText ?? L10n.text("未设置")
        shiftField.stringValue = working.shiftAxisHotkey?.displayText ?? L10n.text("未设置")
        blockField.stringValue = working.blockSmoothHotkey?.displayText ?? L10n.text("未设置")
    }

    private func syncEnabledStates() {
        let on = enabled.state == .on
        smooth.isEnabled = on
        reverse.isEnabled = on
        smoothVertical.isEnabled = on && smooth.state == .on
        smoothHorizontal.isEnabled = on && smooth.state == .on
        simulateTrackpad.isEnabled = on && smooth.state == .on
        reverseVertical.isEnabled = on && reverse.state == .on
        reverseHorizontal.isEnabled = on && reverse.state == .on
        for slider in [step, speed, deadZone] { slider.isEnabled = on && smooth.state == .on }
        duration.isEnabled = on && smooth.state == .on && simulateTrackpad.state == .off
        if simulateTrackpad.state == .on {
            working.duration = 4.75
            duration.doubleValue = 4.75
            syncValues()
        }
    }

    private func setHotkey(_ hotkey: ScrollHotkey, role: ScrollControlRole) {
        switch role {
        case .accelerate: working.dashHotkey = hotkey
        case .shiftAxis: working.shiftAxisHotkey = hotkey
        case .blockSmooth: working.blockSmoothHotkey = hotkey
        }
    }
}
