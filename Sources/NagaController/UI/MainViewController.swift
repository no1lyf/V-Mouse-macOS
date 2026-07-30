import Cocoa

private final class FlippedMainDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class MainViewController: NSViewController {
    var onLanguageChanged: (() -> Void)?
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: AppIdentity.productName)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        return label
    }()

    private let statusLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: L10n.text("仅监听模式"))
        label.font = .systemFont(ofSize: 14)
        label.textColor = UIStyle.secondaryTextColor
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()


    private let toggle = ThemeToggleView(title: L10n.text("启用按键自定义"))
    private let launchAtLoginToggle = ThemeToggleView(title: L10n.text("开机自动启动"))
    private let builtInTrackpadToggle = ThemeToggleView(title: L10n.text("连接外接鼠标时停用内置触控板"))
    private let reverseScrollToggle = ThemeToggleView(title: L10n.text("启用滚轮增强"))
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    /// One row per physical device (by stable key): codec devices are always
    /// on; standard devices carry a user switch; unsupported ones show why.
    private let deviceListStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }()
    private var deviceRowKeys: [Int: String] = [:]
    private var deviceRowLabelKeys: [ObjectIdentifier: String] = [:]
    private var deviceRowCodecFlags: [Int: Bool] = [:]
    private let rescanDevicesButton: ThemeButton = {
        let button = ThemeButton(title: L10n.text("搜索设备"), target: nil, action: nil)
        button.buttonType = .normal
        button.image = UIStyle.symbol("magnifyingglass", size: 12, weight: .medium)
        button.imagePosition = .imageLeading
        button.toolTip = L10n.text("重新枚举当前连接的输入设备")
        return button
    }()
    private let deviceStatusLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = UIStyle.secondaryTextColor
        label.maximumNumberOfLines = 2
        return label
    }()
    private let scrollStatusLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: L10n.text("滚轮增强未启用"))
        label.font = .systemFont(ofSize: 12)
        label.textColor = UIStyle.secondaryTextColor
        return label
    }()

    private let configureButton: ThemeButton = {
        let b = ThemeButton(title: L10n.text("配置按键映射..."), target: nil, action: nil)
        b.buttonType = .primary
        b.image = UIStyle.symbol("slider.horizontal.3", size: 14, weight: .semibold)
        b.imagePosition = .imageLeading
        b.toolTip = L10n.text("打开按键映射编辑器")
        return b
    }()

    private let scrollSettingsButton: ThemeButton = {
        let button = ThemeButton(title: L10n.text("滚轮设置..."), target: nil, action: nil)
        button.buttonType = .normal
        button.image = UIStyle.symbol("computermouse", size: 14, weight: .semibold)
        button.imagePosition = .imageLeading
        button.toolTip = L10n.text("打开平滑、方向、速度和快捷键设置")
        return button
    }()

    private let quitButton: ThemeButton = {
        let b = ThemeButton(title: L10n.text("退出"), target: nil, action: nil)
        b.image = UIStyle.symbol("power", size: 14, weight: .semibold)
        b.imagePosition = .imageLeading
        b.buttonType = .normal
        return b
    }()

    private let tutorialButton: ThemeButton = {
        let button = ThemeButton(title: L10n.text("帮助中心..."), target: nil, action: nil)
        button.buttonType = .normal
        button.image = UIStyle.symbol("questionmark.circle", size: 14)
        button.imagePosition = .imageLeading
        return button
    }()

    private var batteryObserver: NSObjectProtocol?
    private var permissionObserver: NSObjectProtocol?
    private var inputStateObserver: NSObjectProtocol?
    private var scrollStateObserver: NSObjectProtocol?
    private var deviceCandidateObserver: NSObjectProtocol?
    private var mappingChangeObservers: [NSObjectProtocol] = []
    private var languageObserver: NSObjectProtocol?

    private func reloadThemePopup() {
        let selected = ThemeManager.shared.currentMode
        themePopup.removeAllItems()
        themePopup.addItems(withTitles: ThemeMode.allCases.map(\.displayName))
        themePopup.selectItem(at: ThemeMode.allCases.firstIndex(of: selected) ?? 0)
    }

    private let permissionHeaderLabel: NSTextField = {
        let label = NSTextField(labelWithString: L10n.text("权限"))
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        if #available(macOS 10.14, *) {
            label.textColor = DesignSystem.Colors.textPrimary
        }
        return label
    }()

    private let accessibilityStatusLabel: NSTextField = {
        let label = NSTextField(labelWithString: L10n.text("检查中..."))
        label.font = .systemFont(ofSize: 14)
        label.alignment = .right
        return label
    }()

    private let inputMonitoringStatusLabel: NSTextField = {
        let label = NSTextField(labelWithString: L10n.text("检查中..."))
        label.font = .systemFont(ofSize: 14)
        label.alignment = .right
        return label
    }()

    override func loadView() {
        // Native popover material follows the user's Light/Dark appearance.
        let container = UIStyle.makeBackground(material: .popover)
        self.view = container

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8

        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))

        launchAtLoginToggle.target = self
        launchAtLoginToggle.action = #selector(launchAtLoginToggleChanged(_:))
        launchAtLoginToggle.state = LaunchAtLoginManager.isEnabled ? .on : .off

        reverseScrollToggle.target = self
        reverseScrollToggle.action = #selector(reverseScrollToggleChanged(_:))

        builtInTrackpadToggle.target = self
        builtInTrackpadToggle.action = #selector(builtInTrackpadToggleChanged(_:))
        builtInTrackpadToggle.state = BuiltInTrackpadManager.stopsTrackpadWhenExternalMousePresent ? .on : .off
        builtInTrackpadToggle.toolTip = L10n.text("开启后，仅在 V-Mouse 运行且外接鼠标或无线触控板存在时停用内置触控板；退出 V-Mouse 后自动恢复")

        languagePopup.addItems(withTitles: AppLanguage.allCases.map(\.displayName))
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: L10n.language) ?? 0)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))

        reloadThemePopup()
        themePopup.target = self
        themePopup.action = #selector(themeChanged(_:))
        // Belt and suspenders: even if the popover rebuild path ever misses a
        // language change, the theme titles re-localize in place.
        languageObserver = NotificationCenter.default.addObserver(
            forName: .appLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.reloadThemePopup() }

        rescanDevicesButton.target = self
        rescanDevicesButton.action = #selector(rescanDevicesTapped)
        refreshDeviceCandidates()

        configureButton.target = self
        configureButton.action = #selector(openMappings)
        scrollSettingsButton.target = self
        scrollSettingsButton.action = #selector(openScrollSettings)

        quitButton.target = self
        quitButton.action = #selector(quitApp)
        tutorialButton.target = self
        tutorialButton.action = #selector(openTutorial)

        updateInputState()

        let initialSettings = ConfigManager.shared.getScrollSettings()
        reverseScrollToggle.state = initialSettings.enabled ? .on : .off

        // ── Toggles card ──
        let togglesCard = ThemeCardView()
        togglesCard.translatesAutoresizingMaskIntoConstraints = false
        let togglesInner = NSStackView()
        togglesInner.orientation = .vertical
        togglesInner.spacing = 9
        togglesInner.alignment = .leading
        togglesInner.translatesAutoresizingMaskIntoConstraints = false
        // Key-mapping group, then the scroll group: the three scroll toggles
        // sit directly above the scroll-settings button.
        togglesInner.addArrangedSubview(toggle)
        togglesInner.addArrangedSubview(configureButton)
        togglesInner.setCustomSpacing(14, after: configureButton)
        togglesInner.addArrangedSubview(builtInTrackpadToggle)
        togglesInner.setCustomSpacing(14, after: builtInTrackpadToggle)
        // Direction reversal lives in the scroll-settings window; the popover
        // keeps only the enhancement master switch and a link into settings.
        togglesInner.addArrangedSubview(reverseScrollToggle)
        togglesInner.addArrangedSubview(scrollStatusLabel)
        togglesInner.setCustomSpacing(12, after: scrollStatusLabel)
        togglesInner.addArrangedSubview(scrollSettingsButton)

        togglesCard.addSubview(togglesInner)
        NSLayoutConstraint.activate([
            togglesInner.leadingAnchor.constraint(equalTo: togglesCard.leadingAnchor, constant: 14),
            togglesInner.trailingAnchor.constraint(equalTo: togglesCard.trailingAnchor, constant: -14),
            togglesInner.topAnchor.constraint(equalTo: togglesCard.topAnchor, constant: 12),
            togglesInner.bottomAnchor.constraint(equalTo: togglesCard.bottomAnchor, constant: -12)
        ])

        let deviceLabel = NSTextField(labelWithString: L10n.text("输入设备"))
        deviceLabel.font = .systemFont(ofSize: 14)
        let deviceRow = NSStackView(views: [deviceLabel, NSView(), rescanDevicesButton])
        deviceRow.orientation = .horizontal
        deviceRow.alignment = .centerY
        deviceRow.spacing = 8
        let deviceStack = NSStackView(views: [deviceRow, deviceListStack, deviceStatusLabel])
        deviceStack.orientation = .vertical
        deviceStack.alignment = .leading
        deviceStack.spacing = 5

        // ── Permissions card ──
        let permissionsCard = ThemeCardView()
        permissionsCard.translatesAutoresizingMaskIntoConstraints = false
        let permissionsInner = NSStackView()
        permissionsInner.orientation = .vertical
        permissionsInner.spacing = 8
        permissionsInner.alignment = .leading
        permissionsInner.translatesAutoresizingMaskIntoConstraints = false

        let p1 = makePermissionRow(title: L10n.text("辅助功能"), statusLabel: accessibilityStatusLabel, selector: #selector(openAccessibilitySettings))
        let p2 = makePermissionRow(title: L10n.text("输入监控"), statusLabel: inputMonitoringStatusLabel, selector: #selector(openInputMonitoringSettings))
        permissionsInner.addArrangedSubview(permissionHeaderLabel)
        permissionsInner.addArrangedSubview(p1)
        permissionsInner.addArrangedSubview(p2)
        p1.widthAnchor.constraint(equalTo: permissionsInner.widthAnchor).isActive = true
        p2.widthAnchor.constraint(equalTo: permissionsInner.widthAnchor).isActive = true

        permissionsCard.addSubview(permissionsInner)
        NSLayoutConstraint.activate([
            permissionsInner.leadingAnchor.constraint(equalTo: permissionsCard.leadingAnchor, constant: 14),
            permissionsInner.trailingAnchor.constraint(equalTo: permissionsCard.trailingAnchor, constant: -14),
            permissionsInner.topAnchor.constraint(equalTo: permissionsCard.topAnchor, constant: 12),
            permissionsInner.bottomAnchor.constraint(equalTo: permissionsCard.bottomAnchor, constant: -12)
        ])

        let languageLabel = NSTextField(labelWithString: L10n.text("语言"))
        languageLabel.font = .systemFont(ofSize: 14)
        let themeLabel = NSTextField(labelWithString: L10n.text("界面"))
        themeLabel.font = .systemFont(ofSize: 14)
        let languageRow = NSStackView(views: [languageLabel, NSView(), languagePopup])
        languageRow.orientation = .horizontal
        languageRow.alignment = .centerY
        languageRow.spacing = 8
        let themeRow = NSStackView(views: [themeLabel, NSView(), themePopup])
        themeRow.orientation = .horizontal
        themeRow.alignment = .centerY
        themeRow.spacing = 8
        let preferencesStack = NSStackView(views: [launchAtLoginToggle, languageRow, themeRow])
        preferencesStack.orientation = .vertical
        preferencesStack.alignment = .leading
        preferencesStack.spacing = 8
        let bottomActionsRow = NSStackView(views: [tutorialButton, NSView(), quitButton])
        bottomActionsRow.orientation = .horizontal
        bottomActionsRow.alignment = .centerY
        bottomActionsRow.spacing = 8

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(deviceStack)
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(togglesCard)
        stack.setCustomSpacing(10, after: togglesCard)
        stack.addArrangedSubview(permissionsCard)
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(preferencesStack)
        stack.addArrangedSubview(bottomActionsRow)
        stack.addArrangedSubview(UIStyle.makeFooter(L10n.text("按键自定义总开关决定已配置的 Mac 自定义键值是否运行；滚轮增强与按键自定义相互独立。")))

        togglesCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        permissionsCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        languageRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        themeRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        deviceRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        deviceStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        deviceListStack.widthAnchor.constraint(equalTo: deviceStack.widthAnchor).isActive = true


        let document = FlippedMainDocumentView()
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = document
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalToConstant: DesignSystem.Size.popoverWidth)
        ])

        view.layoutSubtreeIfNeeded()
        let visibleHeight = (NSScreen.main?.visibleFrame.height ?? 700) - 96
        preferredContentSize = NSSize(
            width: DesignSystem.Size.popoverWidth + 40,
            height: min(max(360, stack.fittingSize.height + 40), visibleHeight)
        )

        // Initialize battery label and subscribe to updates
        updateBattery()
        batteryObserver = NotificationCenter.default.addObserver(forName: BatteryMonitor.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateBattery()
        }

        permissionObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshPermissionStatuses()
            // Returning from System Settings after granting a permission
            // should retry initialization without a manual toggle cycle.
            InputCoordinator.shared.refreshPermissions()
        }
        inputStateObserver = NotificationCenter.default.addObserver(
            forName: InputCoordinator.stateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateInputState() }
        scrollStateObserver = NotificationCenter.default.addObserver(
            forName: ScrollReversalManager.stateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateScrollState() }
        deviceCandidateObserver = NotificationCenter.default.addObserver(
            forName: HIDListener.candidateStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.refreshDeviceCandidates() }
        // Bound-profile suffixes in the device rows must follow binding edits
        // made in the mapping window while the popover stays open.
        for name in [
            ConfigManager.presentationDidChangeNotification,
            ConfigManager.profileStructureDidChangeNotification,
            ConfigManager.runtimeRoutingDidChangeNotification
        ] {
            mappingChangeObservers.append(NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.refreshDeviceCandidates() })
        }
        refreshPermissionStatuses()
        updateScrollState()
    }

    // ThemeToggleView forwards target/action to its inner NSSwitch, so the
    // sender delivered here is the NSSwitch — typing it as ThemeToggleView
    // reads garbage memory and crashes. Read state from the switch itself.
    @objc private func toggleChanged(_ sender: NSSwitch) {
        let enabled = (sender.state == .on)
        InputCoordinator.shared.setRemappingEnabled(enabled)
        updateInputState()
    }

    /// Registration can be denied by the system (or the app isn't in
    /// /Applications); reflect the ACTUAL resulting state rather than
    /// trusting the switch the user just flipped.
    @objc private func launchAtLoginToggleChanged(_ sender: NSSwitch) {
        let requested = sender.state == .on
        LaunchAtLoginManager.setEnabled(requested)
        sender.state = LaunchAtLoginManager.isEnabled ? .on : .off
    }

    @objc private func reverseScrollToggleChanged(_ sender: NSSwitch) {
        let enabled = (sender.state == .on)
        InputCoordinator.shared.setReverseScrollEnabled(enabled)
        updateInputState()
        updateScrollState()
    }

    @objc private func builtInTrackpadToggleChanged(_ sender: NSSwitch) {
        let requested = sender.state == .on
        if !BuiltInTrackpadManager.setStopsTrackpadWhenExternalMousePresent(requested) {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.text("无法更新触控板设置")
            alert.informativeText = L10n.text("macOS 没有把更改应用到内置触控板。请在系统设置 → 辅助功能 → 指针控制中手动确认该选项。")
            alert.addButton(withTitle: L10n.text("打开系统设置"))
            alert.addButton(withTitle: L10n.text("取消"))
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?PointerControl") {
                NSWorkspace.shared.open(url)
            }
        }
        sender.state = BuiltInTrackpadManager.stopsTrackpadWhenExternalMousePresent ? .on : .off
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard AppLanguage.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        L10n.setLanguage(AppLanguage.allCases[sender.indexOfSelectedItem])
        // Production refresh is driven by AppDelegate's .appLanguageDidChange
        // observer; the callback remains for standalone UI previews only.
        if let onLanguageChanged {
            DispatchQueue.main.async(execute: onLanguageChanged)
        }
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        guard ThemeMode.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        ThemeManager.shared.setTheme(ThemeMode.allCases[sender.indexOfSelectedItem])
    }

    @objc private func deviceToggled(_ sender: NSSwitch) {
        guard let deviceKey = deviceRowKeys[sender.tag] else { return }
        let enabled = sender.state == .on
        if deviceRowCodecFlags[sender.tag] == true {
            HIDListener.shared.setCodecDevice(deviceKey: deviceKey, enabled: enabled)
        } else if !HIDListener.shared.setStandardDevice(deviceKey: deviceKey, enabled: enabled) {
            refreshDeviceCandidates()
            return
        }
        InputCoordinator.shared.refreshPermissions()
        refreshDeviceCandidates()
    }

    @objc private func rescanDevicesTapped() {
        rescanDevicesButton.isEnabled = false
        deviceStatusLabel.stringValue = L10n.text("正在搜索输入设备…")
        deviceStatusLabel.textColor = UIStyle.secondaryTextColor
        HIDListener.shared.rescanDevices { [weak self] in
            guard let self else { return }
            self.rescanDevicesButton.isEnabled = true
            self.refreshDeviceCandidates()
            let usable = HIDListener.shared.deviceCandidateGroups.filter(\.isSupported).count
            self.deviceStatusLabel.stringValue = L10n.format("搜索完成：发现 %d 个可用输入设备", usable)
        }
    }

    private func deviceDisplayName(_ group: HIDPhysicalDeviceCandidateGroup) -> String {
        group.product.isEmpty ? L10n.text("未命名设备") : group.product
    }

    /// Device rows wrap onto a second line for overlong names instead of
    /// pushing the layout sideways; anything beyond two lines truncates.
    private static func makeDeviceRowLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.maximumNumberOfLines = 2
        label.cell?.truncatesLastVisibleLine = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    /// IOKit transport strings are verbose ("Bluetooth Low Energy") — reduce
    /// them to a short, localized connection type. Shared with the mapping
    /// window so both surfaces name a connection identity identically.
    private func shortTransport(_ raw: String) -> String {
        ConfigManager.transportLabel(raw) ?? raw
    }

    /// The BLE battery service belongs to the Razer mouse; prefix its level
    /// in front of the matching device rows.
    private func batteryPrefix(for group: HIDPhysicalDeviceCandidateGroup) -> String {
        guard let level = BatteryMonitor.shared.batteryLevel else { return "" }
        let lower = group.product.lowercased()
        guard lower.contains("naga") || lower.contains("razer") else { return "" }
        return "\(level)% · "
    }

    private func deviceRowTitle(_ group: HIDPhysicalDeviceCandidateGroup) -> String {
        var title = batteryPrefix(for: group) + deviceDisplayName(group)
        if !group.transport.isEmpty { title += " · \(shortTransport(group.transport))" }
        if let active = ConfigManager.shared.effectiveProfileName(forDeviceKey: group.deviceKey) {
            title += L10n.format(" · 启用「%@」", active)
        } else {
            title += " · " + L10n.text("未启用配置")
        }
        return title
    }

    @objc private func deviceRowLabelClicked(_ sender: NSClickGestureRecognizer) {
        guard let label = sender.view,
              let deviceKey = deviceRowLabelKeys[ObjectIdentifier(label)] else { return }
        MappingWindowController.shared.show(selectingDeviceKey: deviceKey)
    }

    private func refreshDeviceCandidates() {
        let listener = HIDListener.shared
        let groups = listener.deviceCandidateGroups
        let enabledKeys = listener.enabledStandardDeviceKeys
        deviceListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        deviceRowKeys.removeAll()
        deviceRowLabelKeys.removeAll()
        deviceRowCodecFlags.removeAll()

        // Two identical mice (same VID:PID) form multiple runtime groups but a
        // single row: they share one configuration by design. Every codec
        // device is consumed automatically; standard devices carry a switch.
        var listedKeys: Set<String> = []
        var rowTag = 0
        var consumedCount = 0
        let disabledCodecKeys = listener.disabledCodecDeviceKeys
        for group in groups.filter(\.isSupported)
            where !listedKeys.contains(group.deviceKey)
                && !ConfigManager.shared.isDeviceArchived(group.deviceKey) {
            listedKeys.insert(group.deviceKey)
            let toggle = NSSwitch()
            toggle.controlSize = .mini
            toggle.tag = rowTag
            toggle.target = self
            toggle.action = #selector(deviceToggled(_:))
            deviceRowKeys[rowTag] = group.deviceKey
            rowTag += 1
            if group.hasCodec {
                let enabled = !disabledCodecKeys.contains(group.deviceKey)
                toggle.state = enabled ? .on : .off
                toggle.toolTip = L10n.text("专用协议设备默认启用，可暂停")
                deviceRowCodecFlags[toggle.tag] = true
                if enabled { consumedCount += 1 }
            } else {
                let enabled = enabledKeys.contains(group.deviceKey)
                toggle.state = enabled ? .on : .off
                deviceRowCodecFlags[toggle.tag] = false
                if enabled { consumedCount += 1 }
            }
            let label = Self.makeDeviceRowLabel(deviceRowTitle(group))
            // The row text is a deep link into the mapping editor with this
            // device pre-selected — one canonical editing surface instead of
            // two drifting displays.
            label.toolTip = L10n.text("点击打开按键映射并选中此设备")
            deviceRowLabelKeys[ObjectIdentifier(label)] = group.deviceKey
            label.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(deviceRowLabelClicked(_:))))
            let row = NSStackView(views: [toggle, label])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            deviceListStack.addArrangedSubview(row)
            // Pin the row to the list width: an overlong device name must wrap
            // onto a second line instead of pushing the whole card sideways.
            row.widthAnchor.constraint(equalTo: deviceListStack.widthAnchor).isActive = true
        }

        // Unsupported external devices stay visible with the reason, so a
        // missing mouse is diagnosable instead of silently absent.
        var listedUnsupported: Set<String> = []
        for group in groups.filter({ !$0.isSupported }) where !listedUnsupported.contains(group.deviceKey) {
            listedUnsupported.insert(group.deviceKey)
            let reason = group.unsupportedReason?.displayText ?? L10n.text("协议未知")
            let label = Self.makeDeviceRowLabel(
                L10n.format("%@ · 不支持：%@", deviceDisplayName(group), reason)
            )
            label.textColor = DesignSystem.Colors.textDisabled
            deviceListStack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: deviceListStack.widthAnchor).isActive = true
        }

        if listedKeys.isEmpty && listedUnsupported.isEmpty {
            deviceStatusLabel.stringValue = L10n.text("未发现可用输入设备")
            deviceStatusLabel.textColor = UIStyle.secondaryTextColor
        } else if consumedCount > 0 {
            deviceStatusLabel.stringValue = L10n.format("正在使用 %d 台输入设备", consumedCount)
            deviceStatusLabel.textColor = UIStyle.successColor
        } else {
            deviceStatusLabel.stringValue = L10n.text("尚未启用任何输入设备")
            deviceStatusLabel.textColor = UIStyle.warningColor
        }
    }

    @objc private func openMappings() {
        MappingWindowController.shared.show()
    }

    @objc private func openScrollSettings() {
        ScrollSettingsWindowController.shared.show()
    }

    @objc private func openTutorial() {
        TutorialWindowController.shared.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func updateBattery() {
        // Battery now lives inline in the device rows.
        refreshDeviceCandidates()
    }

    private func updateInputState() {
        let coordinator = InputCoordinator.shared
        let state = coordinator.state
        toggle.state = coordinator.isRequestedEnabled ? .on : .off
        statusLabel.stringValue = state.displayText
        switch state {
        case .preparing, .calibrating:
            toggle.isEnabled = false
        default:
            toggle.isEnabled = true
        }
        if #available(macOS 10.14, *) {
            switch state {
            case .active, .scrollOnly, .scrollOnlyMappingUnavailable: statusLabel.textColor = UIStyle.successColor
            case .unavailable: statusLabel.textColor = UIStyle.warningColor
            default: statusLabel.textColor = UIStyle.secondaryTextColor
            }
        }
    }

    private func updateScrollState() {
        let settings = ConfigManager.shared.getScrollSettings()
        reverseScrollToggle.state = settings.enabled ? .on : .off
        let manager = ScrollReversalManager.shared
        scrollStatusLabel.stringValue = manager.state.displayText
        switch manager.state {
        case .active: scrollStatusLabel.textColor = UIStyle.successColor
        case .unavailable: scrollStatusLabel.textColor = UIStyle.warningColor
        case .stopped: scrollStatusLabel.textColor = UIStyle.secondaryTextColor
        }
    }

    func refreshPermissionStatuses() {
        updateStatus(label: accessibilityStatusLabel, granted: PermissionManager.shared.hasAccessibilityPermission())
        updateStatus(label: inputMonitoringStatusLabel, granted: PermissionManager.shared.hasInputMonitoringPermission())
    }

    private func updateStatus(label: NSTextField, granted: Bool) {
        label.stringValue = granted ? L10n.text("已授权") : L10n.text("未授权")
        if #available(macOS 10.14, *) {
            label.textColor = granted ? UIStyle.successColor : UIStyle.warningColor
        } else {
            label.textColor = granted ? UIStyle.successColor : UIStyle.warningColor
        }
    }

    private func makePermissionRow(title: String, statusLabel: NSTextField, selector: Selector) -> NSStackView {
        let row = NSStackView()
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 8

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14)
        if #available(macOS 10.14, *) {
            titleLabel.textColor = .labelColor
        }

        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8
        let spacer = NSView()

        let button = ThemeButton(title: L10n.text("打开设置"), target: self, action: selector)
        button.buttonType = .normal
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)

        statusLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        statusRow.addArrangedSubview(titleLabel)
        statusRow.addArrangedSubview(spacer)
        statusRow.addArrangedSubview(statusLabel)
        row.addArrangedSubview(statusRow)
        row.addArrangedSubview(button)
        statusRow.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true

        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return row
    }

    private func makeSeparator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    @objc private func openAccessibilitySettings() {
        PermissionManager.shared.openAccessibilityPreferences()
    }

    @objc private func openInputMonitoringSettings() {
        PermissionManager.shared.openInputMonitoringPreferences()
    }

    deinit {
        if let obs = batteryObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = permissionObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = inputStateObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = scrollStateObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = deviceCandidateObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        mappingChangeObservers.forEach { NotificationCenter.default.removeObserver($0) }
        if let obs = languageObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}
