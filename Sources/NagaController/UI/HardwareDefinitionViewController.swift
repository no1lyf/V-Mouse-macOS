import Cocoa

private final class FlippedDefinitionStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class HardwareDefinitionViewController: NSViewController {
    var onComplete: (() -> Void)?
    private let previewMode: Bool

    private let summaryLabel = NSTextField(labelWithString: L10n.text("尚未读取侧键"))
    private let statusLabel = NSTextField(labelWithString: L10n.text("选择一个输入，然后在 20 秒内连续按下三次。"))
    private let progressIndicator = NSProgressIndicator()
    private let devicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var definitionLabels: [Int: NSTextField] = [:]
    private var nameFields: [Int: NSTextField] = [:]
    private var recordButtons: [Int: NSButton] = [:]
    private var clearButtons: [Int: NSButton] = [:]
    private var interceptToggles: [Int: NSButton] = [:]
    private var deleteButtons: [Int: NSButton] = [:]
    private var groupPopups: [Int: NSPopUpButton] = [:]
    private var groupTitleFields: [String: NSTextField] = [:]
    private var groupAddButtons: [String: NSButton] = [:]
    private var groupDeleteButtons: [String: NSButton] = [:]
    private var groupOrderButtons: [NSButton] = []
    private var rowCards: [Int: NSBox] = [:]
    private var addGroupButton: NSButton?
    /// Rebuilt whenever the device or its custom-source list changes.
    private let rowsStack = FlippedDefinitionStackView()
    private lazy var columnHeaderView = makeColumnHeader()
    private lazy var restoreButton: NSButton = {
        let b = NSButton(title: L10n.text("恢复默认输入"), target: self, action: #selector(restoreDefaultsTapped))
        b.toolTip = L10n.text("重新显示此设备被移除的标准按键（侧键 1–12、DPI±、滚轮左右）")
        UIStyle.styleSecondaryButton(b)
        return b
    }()
    private var didBeginSession = false
    private var activeRecordingIndex: Int?
    private var pendingCustomInput: PendingCustomInput?
    private var recordingProgress = 0
    private var recordingTotal = 3
    private var recordingDeadline: TimeInterval?
    private var countdownTimer: Timer?
    private var configObservers: [NSObjectProtocol] = []
    /// Snapshots only for devices this sheet actually edits. Cancel must not
    /// rewind unrelated devices that connected or changed while it was open.
    private var openingDeviceSnapshots: [String: DeviceConfiguration] = [:]
    private var openingMissingDeviceKeys: Set<String> = []
    private let openingCorrelationOffsetNs: Int64
    private let openingCorrelationToleranceNs: UInt64

    deinit {
        configObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    init(previewMode: Bool = false) {
        self.previewMode = previewMode
        self.openingCorrelationOffsetNs = ConfigManager.shared.getCorrelationOffsetNs()
        self.openingCorrelationToleranceNs = ConfigManager.shared.getCorrelationToleranceNs()
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 820, height: 620)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        let background = UIStyle.makeBackground(material: .sheet)
        background.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(background)

        let title = NSTextField(labelWithString: L10n.text("读取板载鼠标按键定义"))
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let subtitle = NSTextField(wrappingLabelWithString:
            L10n.text("读取默认按键或自定义分组中的新输入。每个来源都使用三次一致性校验，每次限时 20 秒；只读取信号，不写入鼠标配置。")
        )
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = UIStyle.secondaryTextColor

        let warning = NSTextField(wrappingLabelWithString:
            L10n.text("默认 DPI 私有功能不要求识别；请先在 Windows 中把 DPI± 写成需要的普通板载键值，再回到这里录入。滚轮左右倾斜可读取普通键值、鼠标键或默认横向滚轮信号。")
        )
        warning.font = .systemFont(ofSize: 13, weight: .medium)
        warning.textColor = UIStyle.warningColor

        summaryLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        summaryLabel.textColor = UIStyle.razerGreen

        let header = UIStyle.makeCard()
        let headerStack = NSStackView(views: [title, subtitle, warning, summaryLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 7
        header.addSubview(headerStack)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            headerStack.topAnchor.constraint(equalTo: header.topAnchor, constant: 14),
            headerStack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -14)
        ])

        // Which device's table this sheet reads and edits.
        devicePopup.target = self
        devicePopup.action = #selector(deviceSelectionChanged(_:))
        devicePopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let deviceLabel = NSTextField(labelWithString: L10n.text("读取设备:"))
        deviceLabel.font = .systemFont(ofSize: 14, weight: .medium)
        let deviceRow = NSStackView(views: [deviceLabel, devicePopup, NSView()])
        deviceRow.orientation = .horizontal
        deviceRow.alignment = .centerY
        deviceRow.spacing = 8
        headerStack.addArrangedSubview(deviceRow)
        reloadDeviceSelector()

        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = .labelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 3
        progressIndicator.doubleValue = 0
        progressIndicator.controlSize = .small
        progressIndicator.isHidden = true
        progressIndicator.widthAnchor.constraint(equalToConstant: 170).isActive = true

        let statusCard = UIStyle.makeCard()
        statusCard.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.08)
        let statusRow = NSStackView(views: [statusLabel, NSView(), progressIndicator])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 10
        statusCard.addSubview(statusRow)
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusRow.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 12),
            statusRow.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -12),
            statusRow.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 9),
            statusRow.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -9)
        ])

        rowsStack.orientation = .vertical
        rowsStack.spacing = 7
        rebuildRows()

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = rowsStack
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let addGroup = NSButton(title: L10n.text("+ 新建自定义分组"), target: self, action: #selector(addGroupTapped))
        addGroup.toolTip = L10n.text("创建一个可命名的输入分组，然后在分组中读取新按键")
        UIStyle.styleSecondaryButton(addGroup)
        addGroupButton = addGroup

        let cancelRecording = NSButton(title: L10n.text("取消当前录入"), target: self, action: #selector(cancelRecordingTapped))
        UIStyle.styleSecondaryButton(cancelRecording)

        let cancelAll = NSButton(title: L10n.text("取消"), target: self, action: #selector(cancelAllTapped))
        UIStyle.styleSecondaryButton(cancelAll)
        cancelAll.toolTip = L10n.text("放弃本次打开以来的全部改动（读取、改名、拦截与清除）")

        let close = NSButton(title: L10n.text("完成"), target: self, action: #selector(closeTapped))
        close.image = UIStyle.symbol("checkmark", size: 12, weight: .semibold)
        close.imagePosition = .imageLeading
        UIStyle.stylePrimaryButton(close)

        let footer = NSStackView(views: [addGroup, restoreButton, cancelRecording, NSView(), cancelAll, close])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        let footerHint = UIStyle.makeFooter(L10n.text("读取说明：每个来源需在 20 秒内连续按三次；本页只读取，不写入鼠标板载配置。"))
        let stack = NSStackView(views: [header, statusCard, scroll, footerHint, footer])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let preferredScrollHeight = scroll.heightAnchor.constraint(equalToConstant: 420)
        preferredScrollHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            background.topAnchor.constraint(equalTo: view.topAnchor),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            preferredScrollHeight,
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 720),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 480)
        ])
        refreshDefinitions()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !previewMode else { return }
        guard !didBeginSession else { return }
        didBeginSession = true
        captureOpeningStateIfNeeded(for: ConfigManager.shared.editingDeviceKey)
        for name in [ConfigManager.presentationDidChangeNotification, ConfigManager.runtimeRoutingDidChangeNotification] {
            configObservers.append(NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reloadDeviceSelector()
                self?.refreshDefinitions()
            })
        }
        if !InputCoordinator.shared.beginCalibration() {
            showError(InputCoordinator.shared.state.displayText)
            dismiss(nil)
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        guard !previewMode else { return }
        stopCountdown()
        HardwareCalibrationManager.shared.cancelCalibration()
        InputCoordinator.shared.endCalibration()
    }

    private func makeColumnHeader() -> NSView {
        let number = headerLabel(L10n.text("输入"), width: 72)
        let value = headerLabel(L10n.text("当前板载键值"), width: 250)
        let group = headerLabel(L10n.text("所属分组"), width: 108)
        let intercept = headerLabel(L10n.text("运行方式"), width: 116)
        let actions = headerLabel(L10n.text("操作"), width: 170)
        let row = NSStackView(views: [number, value, NSView(), group, intercept, actions])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        return row
    }

    private func headerLabel(_ text: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = UIStyle.secondaryTextColor
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func makeRow(index: Int) -> NSView {
        let card = UIStyle.makeCard()
        rowCards[index] = card

        let number = NSTextField(labelWithString: InputSourceCatalog.compactLabel(for: index))
        number.font = .monospacedDigitSystemFont(ofSize: 17, weight: .bold)
        number.textColor = UIStyle.razerGreen
        number.alignment = .center
        number.widthAnchor.constraint(equalToConstant: 38).isActive = true

        // Editable: users rename "侧键1" to whatever matches their workflow.
        let name = NSTextField(string: inputName(index))
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.isBordered = false
        name.drawsBackground = false
        name.focusRingType = .exterior
        name.placeholderString = InputSourceCatalog.mappingName(for: index)
        name.toolTip = L10n.text("点击可自定义键名，清空恢复默认")
        name.tag = index
        name.target = self
        name.action = #selector(nameEdited(_:))
        // Commit on focus loss too — Enter-only committing silently drops
        // renames when the user clicks elsewhere.
        (name.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        name.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        name.widthAnchor.constraint(lessThanOrEqualToConstant: 140).isActive = true
        nameFields[index] = name

        let definition = NSTextField(labelWithString: L10n.text("尚未读取"))
        definition.font = .systemFont(ofSize: 14, weight: .medium)
        definition.lineBreakMode = .byTruncatingTail
        definition.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        // The definition text is the row's payload — it must win the space
        // fight against the trailing spacer so it never truncates while
        // free space remains.
        definition.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        definitionLabels[index] = definition

        let intercept = NSButton(
            checkboxWithTitle: L10n.text("拦截板载键值"),
            target: self,
            action: #selector(interceptToggled(_:))
        )
        intercept.tag = index
        intercept.font = .systemFont(ofSize: 13)
        intercept.contentTintColor = .controlAccentColor
        intercept.widthAnchor.constraint(greaterThanOrEqualToConstant: 116).isActive = true
        intercept.toolTip = L10n.text("开启：拦截已读取的板载键值并执行 Mac 自定义键值；关闭：板载键值直接通过")
        interceptToggles[index] = intercept

        let groupPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        groupPopup.tag = index
        groupPopup.target = self
        groupPopup.action = #selector(sourceGroupChanged(_:))
        groupPopup.toolTip = L10n.text("将此输入移动到其他分组")
        groupPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 108).isActive = true
        for group in currentInputGroups() {
            let item = NSMenuItem(title: ConfigManager.shared.inputGroupTitle(group), action: nil, keyEquivalent: "")
            item.representedObject = group.id
            groupPopup.menu?.addItem(item)
            if group.sourceIndices.contains(index) { groupPopup.select(item) }
        }
        groupPopups[index] = groupPopup

        let record = NSButton(title: L10n.text("读取"), target: self, action: #selector(recordTapped(_:)))
        record.tag = index
        record.image = UIStyle.symbol("waveform", size: 11)
        record.imagePosition = .imageLeading
        recordButtons[index] = record
        UIStyle.stylePrimaryButton(record)

        let clear = NSButton(title: L10n.text("清除"), target: self, action: #selector(clearTapped(_:)))
        clear.tag = index
        clear.contentTintColor = .systemRed
        clearButtons[index] = clear
        UIStyle.styleSecondaryButton(clear)

        // Any row can be deleted so a device shows exactly the buttons it has
        // (a custom source disappears; a standard one is hidden, restorable
        // via "恢复默认输入").
        let delete = NSButton(title: "", target: self, action: #selector(deleteSourceTapped(_:)))
        delete.image = UIStyle.symbol("xmark.circle", size: 13, weight: .regular)
        delete.tag = index
        delete.contentTintColor = .systemRed
        delete.toolTip = ConfigManager.isCustomSourceIndex(index)
            ? L10n.text("删除此自定义输入")
            : L10n.text("从此设备移除这个按键")
        UIStyle.styleSecondaryButton(delete)
        deleteButtons[index] = delete

        let row = NSStackView(views: [number, name, definition, NSView(), groupPopup, intercept, record, clear, delete])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        card.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
        return card
    }

    @objc private func recordTapped(_ sender: NSButton) {
        captureOpeningStateIfNeeded(for: ConfigManager.shared.editingDeviceKey)
        startRecording(index: sender.tag, persistResult: true, pending: nil)
    }

    private func startRecording(index: Int, persistResult: Bool, pending: PendingCustomInput?) {
        activeRecordingIndex = index
        pendingCustomInput = pending
        setControlsEnabled(false)
        progressIndicator.isHidden = false
        progressIndicator.doubleValue = 0
        updateActiveRow(index)
        statusLabel.textColor = .labelColor
        startCountdown()

        HardwareCalibrationManager.shared.startCalibration(
            for: index,
            expectedDeviceKey: ConfigManager.shared.editingDeviceKey,
            persistResult: persistResult,
            progress: { [weak self] count, total in
                guard let self else { return }
                self.progressIndicator.doubleValue = Double(count)
                self.recordingProgress = count
                self.recordingTotal = total
                self.updateCountdownLabel()
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.stopCountdown()
                self.activeRecordingIndex = nil
                let pending = self.pendingCustomInput
                self.pendingCustomInput = nil
                self.progressIndicator.isHidden = true
                self.updateActiveRow(nil)
                self.setControlsEnabled(true)
                switch result {
                case .success(let key):
                    if let pending, let deviceKey = ConfigManager.shared.editingDeviceKey {
                        guard ConfigManager.shared.commitCustomInput(pending, learnedKey: key, forDeviceKey: deviceKey) else {
                            self.statusLabel.stringValue = L10n.text("新输入保存失败，请重新读取。")
                            self.statusLabel.textColor = UIStyle.warningColor
                            self.rebuildRows()
                            return
                        }
                        self.rebuildRows()
                    }
                    self.statusLabel.stringValue = L10n.format("%@ 已确认：“%@”", self.inputName(index), key.displayString)
                    self.statusLabel.textColor = UIStyle.successColor
                    self.refreshDefinitions()
                    self.onComplete?()
                case .failure(let error):
                    self.statusLabel.stringValue = L10n.format("%@ 读取失败，请重试", self.inputName(index))
                    self.statusLabel.textColor = UIStyle.warningColor
                    self.showError(error.localizedDescription)
                }
            }
        )
    }

    @objc private func cancelRecordingTapped() {
        guard activeRecordingIndex != nil else { return }
        HardwareCalibrationManager.shared.cancelCalibration()
        stopCountdown()
        activeRecordingIndex = nil
        pendingCustomInput = nil
        progressIndicator.isHidden = true
        updateActiveRow(nil)
        setControlsEnabled(true)
        statusLabel.stringValue = L10n.text("已取消当前录入。")
        statusLabel.textColor = UIStyle.secondaryTextColor
    }

    @objc private func clearTapped(_ sender: NSButton) {
        captureOpeningStateIfNeeded(for: ConfigManager.shared.editingDeviceKey)
        var mapping = ConfigManager.shared.getHardwareMapping()
        mapping.removeValue(forKey: String(sender.tag))
        ConfigManager.shared.setHardwareMapping(mapping)
        statusLabel.stringValue = L10n.format("已清除%@的板载定义。", inputName(sender.tag))
        statusLabel.textColor = UIStyle.secondaryTextColor
        refreshDefinitions()
        onComplete?()
    }

    @objc private func interceptToggled(_ sender: NSButton) {
        captureOpeningStateIfNeeded(for: ConfigManager.shared.editingDeviceKey)
        // Interception no longer requires a Mac custom value: without one it
        // simply blocks the onboard key (pure suppression); with one it also
        // runs the custom value.
        guard let deviceKey = ConfigManager.shared.editingDeviceKey else { return }
        let canonicalIndex = ConfigManager.shared.signalCanonicalSourceIndex(
            forDeviceKey: deviceKey,
            index: sender.tag
        )
        ConfigManager.shared.setSignalInterceptEnabled(
            sender.state == .on,
            forDeviceKey: deviceKey,
            index: sender.tag
        )
        let hasCustomValue = ConfigManager.shared.editingEffectiveMapping()[canonicalIndex] != nil
        if sender.state == .on {
            statusLabel.stringValue = hasCustomValue
                ? L10n.format("%@：已拦截板载键值并执行 Mac 自定义键值。", inputName(sender.tag))
                : L10n.format("%@：已拦截并屏蔽板载键值（未设置 Mac 自定义键值）。", inputName(sender.tag))
            statusLabel.textColor = UIStyle.successColor
        } else {
            statusLabel.stringValue = L10n.format("%@：板载键值直接通过。", inputName(sender.tag))
            statusLabel.textColor = UIStyle.warningColor
        }
        refreshDefinitions()
        onComplete?()
    }

    @objc private func closeTapped() {
        dismiss(nil)
    }

    /// Discard every change made since the sheet opened: learned definitions,
    /// renames, intercept switches and clears all roll back together.
    @objc private func cancelAllTapped() {
        if activeRecordingIndex != nil {
            HardwareCalibrationManager.shared.cancelCalibration()
            stopCountdown()
            activeRecordingIndex = nil
        }
        ConfigManager.shared.restoreDeviceConfigurations(
            existing: openingDeviceSnapshots,
            removing: openingMissingDeviceKeys
        )
        ConfigManager.shared.setCorrelationTiming(
            offsetNs: openingCorrelationOffsetNs,
            toleranceNs: openingCorrelationToleranceNs
        )
        onComplete?()
        dismiss(nil)
    }

    @objc private func deviceSelectionChanged(_ sender: NSPopUpButton) {
        guard let key = sender.selectedItem?.representedObject as? String else { return }
        ConfigManager.shared.setEditingDevice(key: key)
        captureOpeningStateIfNeeded(for: key)
        rebuildRows()
        refreshDefinitions()
    }

    /// The input rows the current device shows: the fixed 1–16 layout plus its
    /// own custom sources.
    private func currentSourceIndices() -> [Int] {
        ConfigManager.shared.sourceIndices(forDeviceKey: ConfigManager.shared.editingDeviceKey)
    }

    /// Rebuild every row for the current device. Cards are cheap and the row
    /// set changes only on device switch or add/delete, so a full rebuild
    /// keeps the per-index view dictionaries simple and correct.
    private func rebuildRows() {
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        definitionLabels.removeAll()
        nameFields.removeAll()
        recordButtons.removeAll()
        clearButtons.removeAll()
        interceptToggles.removeAll()
        deleteButtons.removeAll()
        groupPopups.removeAll()
        groupTitleFields.removeAll()
        groupAddButtons.removeAll()
        groupDeleteButtons.removeAll()
        groupOrderButtons.removeAll()
        rowCards.removeAll()
        rowsStack.addArrangedSubview(columnHeaderView)
        for group in currentInputGroups() {
            rowsStack.addArrangedSubview(makeGroupHeader(group))
            for index in group.sourceIndices { rowsStack.addArrangedSubview(makeRow(index: index)) }
        }
        let deviceKey = ConfigManager.shared.editingDeviceKey
        restoreButton.isHidden = deviceKey.map { !ConfigManager.shared.hasRemovedStandardSources(forDeviceKey: $0) } ?? true
    }

    private func currentInputGroups() -> [DeviceInputGroup] {
        ConfigManager.shared.inputGroups(forDeviceKey: ConfigManager.shared.editingDeviceKey)
    }

    private func makeGroupHeader(_ group: DeviceInputGroup) -> NSView {
        let title = NSTextField(string: ConfigManager.shared.inputGroupTitle(group))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.isBordered = false
        title.drawsBackground = false
        title.identifier = NSUserInterfaceItemIdentifier(group.id)
        title.target = self
        title.action = #selector(groupTitleEdited(_:))
        (title.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        title.toolTip = L10n.text("点击可修改分组名称")
        title.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        title.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
        groupTitleFields[group.id] = title

        var views: [NSView] = [title, NSView()]
        let groups = currentInputGroups()
        let position = groups.firstIndex(where: { $0.id == group.id }) ?? 0
        for (symbol, offset, enabled) in [
            ("chevron.up", -1, position > 0),
            ("chevron.down", 1, position + 1 < groups.count)
        ] {
            let order = NSButton(title: "", target: self, action: #selector(moveGroupTapped(_:)))
            order.identifier = NSUserInterfaceItemIdentifier(group.id)
            order.tag = offset
            order.image = UIStyle.symbol(symbol, size: 11)
            order.toolTip = offset < 0 ? L10n.text("上移分组") : L10n.text("下移分组")
            order.isEnabled = enabled
            UIStyle.styleSecondaryButton(order)
            groupOrderButtons.append(order)
            views.append(order)
        }
        let add = NSButton(title: L10n.text("读取新输入"), target: self, action: #selector(recordNewInputTapped(_:)))
        add.identifier = NSUserInterfaceItemIdentifier(group.id)
        add.image = UIStyle.symbol("waveform.badge.plus", size: 11)
        add.imagePosition = .imageLeading
        UIStyle.stylePrimaryButton(add)
        groupAddButtons[group.id] = add
        views.append(add)

        let remove = NSButton(title: "", target: self, action: #selector(deleteGroupTapped(_:)))
        remove.identifier = NSUserInterfaceItemIdentifier(group.id)
        remove.image = UIStyle.symbol("trash", size: 12)
        remove.contentTintColor = .systemRed
        remove.toolTip = group.sourceIndices.isEmpty
            ? L10n.text("删除这个空分组")
            : L10n.text("分组中仍有输入，移走或删除全部输入后才能删除")
        remove.isEnabled = group.sourceIndices.isEmpty
        UIStyle.styleSecondaryButton(remove)
        groupDeleteButtons[group.id] = remove
        views.append(remove)
        let header = NSStackView(views: views)
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top: 12, left: 10, bottom: 3, right: 8)
        return header
    }

    @objc private func addGroupTapped() {
        guard let deviceKey = ConfigManager.shared.editingDeviceKey else {
            statusLabel.stringValue = L10n.text("请先选择要录入的设备。")
            statusLabel.textColor = UIStyle.warningColor
            return
        }
        captureOpeningStateIfNeeded(for: deviceKey)
        let groupID = ConfigManager.shared.addInputGroup(forDeviceKey: deviceKey)
        rebuildRows()
        refreshDefinitions()
        if let field = groupTitleFields[groupID] {
            view.window?.makeFirstResponder(field)
            field.selectText(nil)
        }
        onComplete?()
    }

    @objc private func recordNewInputTapped(_ sender: NSButton) {
        guard let deviceKey = ConfigManager.shared.editingDeviceKey,
              let groupID = sender.identifier?.rawValue,
              let pending = ConfigManager.shared.pendingCustomInput(forDeviceKey: deviceKey, groupID: groupID) else { return }
        captureOpeningStateIfNeeded(for: deviceKey)
        startRecording(index: pending.sourceIndex, persistResult: false, pending: pending)
    }

    @objc private func groupTitleEdited(_ sender: NSTextField) {
        guard let deviceKey = ConfigManager.shared.editingDeviceKey,
              let groupID = sender.identifier?.rawValue else { return }
        captureOpeningStateIfNeeded(for: deviceKey)
        ConfigManager.shared.renameInputGroup(groupID, title: sender.stringValue, forDeviceKey: deviceKey)
        if let group = currentInputGroups().first(where: { $0.id == groupID }) {
            sender.stringValue = ConfigManager.shared.inputGroupTitle(group)
        }
    }

    @objc private func deleteGroupTapped(_ sender: NSButton) {
        guard let deviceKey = ConfigManager.shared.editingDeviceKey,
              let groupID = sender.identifier?.rawValue else { return }
        captureOpeningStateIfNeeded(for: deviceKey)
        if ConfigManager.shared.removeInputGroup(groupID, forDeviceKey: deviceKey) {
            rebuildRows()
            refreshDefinitions()
            onComplete?()
        }
    }

    @objc private func moveGroupTapped(_ sender: NSButton) {
        guard let deviceKey = ConfigManager.shared.editingDeviceKey,
              let groupID = sender.identifier?.rawValue else { return }
        captureOpeningStateIfNeeded(for: deviceKey)
        ConfigManager.shared.moveInputGroup(groupID, offset: sender.tag, forDeviceKey: deviceKey)
        rebuildRows()
        refreshDefinitions()
        onComplete?()
    }

    @objc private func sourceGroupChanged(_ sender: NSPopUpButton) {
        guard let deviceKey = ConfigManager.shared.editingDeviceKey,
              let groupID = sender.selectedItem?.representedObject as? String else { return }
        captureOpeningStateIfNeeded(for: deviceKey)
        ConfigManager.shared.moveSource(sender.tag, toGroupID: groupID, forDeviceKey: deviceKey)
        rebuildRows()
        refreshDefinitions()
        onComplete?()
    }

    @objc private func deleteSourceTapped(_ sender: NSButton) {
        guard let deviceKey = ConfigManager.shared.editingDeviceKey else { return }
        captureOpeningStateIfNeeded(for: deviceKey)
        ConfigManager.shared.removeSource(forDeviceKey: deviceKey, index: sender.tag)
        rebuildRows()
        refreshDefinitions()
        onComplete?()
    }

    @objc private func restoreDefaultsTapped() {
        guard let deviceKey = ConfigManager.shared.editingDeviceKey else { return }
        captureOpeningStateIfNeeded(for: deviceKey)
        ConfigManager.shared.restoreDefaultSources(forDeviceKey: deviceKey)
        rebuildRows()
        refreshDefinitions()
        onComplete?()
    }

    private func promptForText(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        let tf = NSTextField(string: defaultValue)
        tf.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = tf
        alert.addButton(withTitle: L10n.text("确定"))
        alert.addButton(withTitle: L10n.text("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return tf.stringValue
    }

    @objc private func nameEdited(_ sender: NSTextField) {
        guard let deviceKey = ConfigManager.shared.editingDeviceKey else { return }
        captureOpeningStateIfNeeded(for: deviceKey)
        ConfigManager.shared.setCustomName(sender.stringValue, forDeviceKey: deviceKey, index: sender.tag)
    }

    private func captureOpeningStateIfNeeded(for deviceKey: String?) {
        guard let deviceKey,
              openingDeviceSnapshots[deviceKey] == nil,
              !openingMissingDeviceKeys.contains(deviceKey) else { return }
        if let configuration = ConfigManager.shared.getDeviceConfigurations()[deviceKey] {
            openingDeviceSnapshots[deviceKey] = configuration
        } else {
            openingMissingDeviceKeys.insert(deviceKey)
        }
    }

    private func reloadDeviceSelector() {
        let known = ConfigManager.shared.knownDeviceKeys()
        if ConfigManager.shared.editingDeviceKey == nil
            || !known.contains(ConfigManager.shared.editingDeviceKey ?? "") {
            let fallback = HIDListener.shared.lastInputDeviceKey
                ?? HIDListener.shared.consumedDeviceKeys.sorted().first
                ?? known.first
            ConfigManager.shared.setEditingDevice(key: fallback)
        }
        devicePopup.removeAllItems()
        for key in known {
            let item = NSMenuItem(
                title: ConfigManager.shared.deviceDisplayName(forKey: key),
                action: nil,
                keyEquivalent: ""
            )
            item.representedObject = key
            devicePopup.menu?.addItem(item)
        }
        devicePopup.isEnabled = !known.isEmpty && activeRecordingIndex == nil
        if let editing = ConfigManager.shared.editingDeviceKey,
           let item = devicePopup.itemArray.first(where: { ($0.representedObject as? String) == editing }) {
            devicePopup.select(item)
        }
    }

    private func refreshDefinitions() {
        let mapping = ConfigManager.shared.getHardwareMapping()
        var interceptedCount = 0
        for index in currentSourceIndices() {
            if let field = nameFields[index], field.currentEditor() == nil {
                field.stringValue = inputName(index)
            }
            if let key = mapping[String(index)] {
                let canonicalIndex = ConfigManager.shared.signalCanonicalSourceIndex(
                    forDeviceKey: ConfigManager.shared.editingDeviceKey,
                    index: index
                )
                definitionLabels[index]?.stringValue = canonicalIndex == index
                    ? key.displayString
                    : L10n.format("%@ · 与%@共享映射", key.displayString, inputName(canonicalIndex))
                definitionLabels[index]?.textColor = key.isIntercepted ? .labelColor : UIStyle.warningColor
                recordButtons[index]?.title = L10n.text("重读")
                clearButtons[index]?.isEnabled = activeRecordingIndex == nil
                // Interception is available once a key is learned, with or
                // without a Mac custom value (without one it blocks the key).
                interceptToggles[index]?.isEnabled = activeRecordingIndex == nil
                interceptToggles[index]?.state = key.isIntercepted ? .on : .off
                if key.isIntercepted { interceptedCount += 1 }
            } else {
                definitionLabels[index]?.stringValue = L10n.text("尚未读取")
                definitionLabels[index]?.textColor = UIStyle.secondaryTextColor
                recordButtons[index]?.title = L10n.text("读取")
                clearButtons[index]?.isEnabled = false
                interceptToggles[index]?.isEnabled = false
                interceptToggles[index]?.state = .off
            }
        }
        let sideCount = mapping.keys.compactMap(Int.init).filter { (1...12).contains($0) }.count
        let extraCount = mapping.keys.compactMap(Int.init).filter { (13...16).contains($0) }.count
        let customCount = mapping.keys.compactMap(Int.init).filter { $0 >= 17 }.count
        summaryLabel.stringValue = L10n.format("侧键已读取 %d/12 · 功能键已读取 %d/4 · 自定义键已读取 %d · 已开启拦截 %d 个", sideCount, extraCount, customCount, interceptedCount)
    }

    private func setControlsEnabled(_ enabled: Bool) {
        recordButtons.values.forEach { $0.isEnabled = enabled }
        devicePopup.isEnabled = enabled
        nameFields.values.forEach { $0.isEnabled = enabled }
        // Adding or deleting inputs mid-recording would rebuild the rows out
        // from under the active capture, so lock those out too.
        addGroupButton?.isEnabled = enabled
        groupAddButtons.values.forEach { $0.isEnabled = enabled }
        let groupByID = Dictionary(uniqueKeysWithValues: currentInputGroups().map { ($0.id, $0) })
        for (id, button) in groupDeleteButtons {
            button.isEnabled = enabled && (groupByID[id]?.sourceIndices.isEmpty == true)
        }
        groupPopups.values.forEach { $0.isEnabled = enabled }
        groupTitleFields.values.forEach { $0.isEnabled = enabled }
        let orderedGroups = currentInputGroups()
        for button in groupOrderButtons {
            guard enabled, let id = button.identifier?.rawValue,
                  let position = orderedGroups.firstIndex(where: { $0.id == id }) else {
                button.isEnabled = false
                continue
            }
            button.isEnabled = button.tag < 0 ? position > 0 : position + 1 < orderedGroups.count
        }
        restoreButton.isEnabled = enabled
        deleteButtons.values.forEach { $0.isEnabled = enabled }
        if enabled { refreshDefinitions() }
        else {
            clearButtons.values.forEach { $0.isEnabled = false }
            interceptToggles.values.forEach { $0.isEnabled = false }
        }
    }

    private func updateActiveRow(_ index: Int?) {
        for (rowIndex, card) in rowCards {
            card.fillColor = rowIndex == index
                ? NSColor.controlAccentColor.withAlphaComponent(0.12)
                : UIStyle.cardFillColor
            card.borderColor = rowIndex == index
                ? NSColor.controlAccentColor.withAlphaComponent(0.8)
                : UIStyle.cardBorderColor
        }
    }

    private func startCountdown() {
        stopCountdown()
        recordingProgress = 0
        recordingTotal = 3
        recordingDeadline = Date.timeIntervalSinceReferenceDate + CalibrationTiming.timeoutSeconds
        updateCountdownLabel()

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateCountdownLabel()
        }
        countdownTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        recordingDeadline = nil
    }

    private func updateCountdownLabel(now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        guard let index = activeRecordingIndex, let deadline = recordingDeadline else { return }
        let seconds = CalibrationTiming.remainingSeconds(deadline: deadline, now: now)
        let name = pendingCustomInput.map { L10n.format("自定义键%d", $0.ordinal) } ?? inputName(index)
        statusLabel.stringValue = L10n.format("正在读取%@：请连续按三次（%d/%d）· 剩余 %d 秒", name, recordingProgress, recordingTotal, seconds)
    }

    private func inputName(_ index: Int) -> String {
        ConfigManager.shared.buttonDisplayName(
            forDeviceKey: ConfigManager.shared.editingDeviceKey,
            index: index
        )
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.text("读取鼠标按键定义失败")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("确定"))
        alert.runModal()
    }
}
