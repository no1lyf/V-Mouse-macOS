import Cocoa

final class DeviceIdentityRuleViewController: NSViewController {
    private let baseKey: String
    private let facts: DeviceIdentityObservedFacts
    private let originalOverride: DeviceIdentityRule?
    private let enableToggle = NSButton(checkboxWithTitle: L10n.text("启用增强识别"), target: nil, action: nil)
    private let conditionCountLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(wrappingLabelWithString: "")
    private var conditionButtons: [DeviceIdentityConditionField: NSButton] = [:]
    private var conditionValues: [DeviceIdentityConditionField: String] = [:]
    private var discriminatorButtons: [DeviceIdentityDiscriminatorField: NSButton] = [:]
    var onSaved: (() -> Void)?

    init(deviceKey: String) {
        let resolvedBaseKey = DeviceIdentityPolicy.baseKey(from: deviceKey)
        baseKey = resolvedBaseKey
        let candidates = HIDListener.shared.deviceCandidates.filter { $0.baseDeviceKey == resolvedBaseKey }
        let live = candidates.first { $0.deviceKey == deviceKey && $0.codecIdentifier != nil }
            ?? candidates.first { $0.deviceKey == deviceKey }
            ?? candidates.first { $0.codecIdentifier != nil }
            ?? candidates.first
        let configuration = ConfigManager.shared.getDeviceConfigurations()[deviceKey]
            ?? ConfigManager.shared.getDeviceConfigurations()[baseKey]
        let parts = resolvedBaseKey.split(separator: ":")
        let vendor = parts.first.flatMap { Int($0, radix: 16) } ?? configuration?.vendorID ?? 0
        let product = parts.dropFirst().first.flatMap { Int($0, radix: 16) } ?? configuration?.productID ?? 0
        facts = live?.observedIdentityFacts ?? DeviceIdentityObservedFacts(
            vendorID: vendor,
            productID: product,
            productName: configuration?.displayName ?? "",
            serialNumber: configuration?.serialNumber ?? "",
            descriptorFingerprint: configuration?.descriptorFingerprint ?? "",
            maximumInputReportSize: 0,
            primaryUsagePage: 0,
            primaryUsage: 0,
            transport: configuration?.transport ?? "",
            codecIdentifier: configuration?.codecBacked == true ? "persistedCodec" : nil
        )
        originalOverride = DeviceIdentityRuleStore.shared.overrideRule(for: resolvedBaseKey)
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 680, height: 610)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        let background = UIStyle.makeBackground(material: .sheet)
        background.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(background)

        let title = NSTextField(labelWithString: L10n.text("设备身份识别规则"))
        title.font = Typography.windowTitle
        let explanation = NSTextField(wrappingLabelWithString: L10n.text("VID/PID 是不可删除的基础条件。启用的增强条件必须全部匹配；任何一项不匹配或缺失时，安全回退到 VID/PID。"))
        explanation.textColor = DesignSystem.Colors.textSecondary
        explanation.font = Typography.bodyNormal

        let baseCard = UIStyle.makeCard()
        let baseText = NSTextField(labelWithString: L10n.format("基础条件（2 项）：VID/PID = %@", baseKey.uppercased()))
        baseText.font = Typography.cardTitle
        baseCard.addSubview(baseText)
        baseText.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            baseText.leadingAnchor.constraint(equalTo: baseCard.leadingAnchor, constant: 14),
            baseText.trailingAnchor.constraint(equalTo: baseCard.trailingAnchor, constant: -14),
            baseText.topAnchor.constraint(equalTo: baseCard.topAnchor, constant: 12),
            baseText.bottomAnchor.constraint(equalTo: baseCard.bottomAnchor, constant: -12)
        ])

        enableToggle.target = self
        enableToggle.action = #selector(ruleChanged)
        enableToggle.font = Typography.cardTitle

        let effective = originalOverride
            ?? DeviceIdentityRuleStore.shared.effectiveRule(for: facts)
            ?? DeviceIdentityRule(baseKey: baseKey, enhancedRecognitionEnabled: false, conditions: [], discriminatorFields: [.serialNumber])
        enableToggle.state = effective.enhancedRecognitionEnabled ? .on : .off

        let conditionsTitle = sectionTitle(L10n.text("增强认证条件（全部必须匹配）"))
        let conditionsStack = NSStackView()
        conditionsStack.orientation = .vertical
        conditionsStack.alignment = .leading
        conditionsStack.spacing = 7
        for field in DeviceIdentityConditionField.allCases {
            let existing = effective.conditions.first { $0.field == field }?.expectedValue
            let observed = facts.conditionValue(field)
            let value = existing ?? observed
            if let value { conditionValues[field] = value }
            let text = value.map { "\(field.displayName) = \($0)" }
                ?? L10n.format("%@：当前设备未报告", field.displayName)
            let button = NSButton(checkboxWithTitle: text, target: self, action: #selector(ruleChanged))
            button.state = existing == nil ? .off : .on
            button.isEnabled = value != nil
            button.font = Typography.bodyNormal
            conditionButtons[field] = button
            conditionsStack.addArrangedSubview(button)
        }

        let discriminatorsTitle = sectionTitle(L10n.text("同型号实例区分字段"))
        let discriminatorStack = NSStackView()
        discriminatorStack.orientation = .vertical
        discriminatorStack.alignment = .leading
        discriminatorStack.spacing = 7
        for field in DeviceIdentityDiscriminatorField.allCases {
            let available = facts.discriminatorValue(field) != nil
            let button = NSButton(
                checkboxWithTitle: available
                    ? field.displayName
                    : L10n.format("%@（当前不可用）", field.displayName),
                target: self,
                action: #selector(ruleChanged)
            )
            button.state = effective.discriminatorFields.contains(field) ? .on : .off
            button.isEnabled = available || effective.discriminatorFields.contains(field)
            button.font = Typography.bodyNormal
            discriminatorButtons[field] = button
            discriminatorStack.addArrangedSubview(button)
        }

        conditionCountLabel.font = Typography.cardTitle
        previewLabel.font = Typography.bodyNormal
        previewLabel.textColor = DesignSystem.Colors.accentText

        let restore = ThemeButton(title: L10n.text("恢复默认规则"), target: self, action: #selector(restoreTapped))
        let cancel = ThemeButton(title: L10n.text("取消"), target: self, action: #selector(cancelTapped))
        let save = ThemeButton(title: L10n.text("保存规则"), target: self, action: #selector(saveTapped))
        save.buttonType = .primary
        let buttons = NSStackView(views: [restore, NSView(), cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [
            title, explanation, baseCard, enableToggle,
            conditionsTitle, conditionsStack,
            discriminatorsTitle, discriminatorStack,
            conditionCountLabel, previewLabel, buttons
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            background.topAnchor.constraint(equalTo: view.topAnchor),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            baseCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -44),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -44)
        ])
        updateRulePreview()
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Typography.sectionTitle
        return label
    }

    private func draftRule() -> DeviceIdentityRule {
        let conditions = DeviceIdentityConditionField.allCases.compactMap { field -> DeviceIdentityCondition? in
            guard conditionButtons[field]?.state == .on, let value = conditionValues[field] else { return nil }
            return DeviceIdentityCondition(field: field, expectedValue: value)
        }
        let discriminators = DeviceIdentityDiscriminatorField.allCases.filter {
            discriminatorButtons[$0]?.state == .on
        }
        return DeviceIdentityRule(
            baseKey: baseKey,
            enhancedRecognitionEnabled: enableToggle.state == .on,
            conditions: conditions,
            discriminatorFields: discriminators
        )
    }

    @objc private func ruleChanged() { updateRulePreview() }

    private func updateRulePreview() {
        let rule = draftRule()
        let enabled = rule.enhancedRecognitionEnabled
        conditionButtons.values.forEach { $0.isEnabled = enabled && !$0.title.contains(L10n.text("当前设备未报告")) }
        discriminatorButtons.values.forEach { $0.isEnabled = enabled && !$0.title.contains(L10n.text("当前不可用")) }
        conditionCountLabel.stringValue = L10n.format(
            "识别条件：基础 2 项 + 增强 %d 项 = %d 项（全部必须匹配）",
            rule.conditions.count,
            rule.totalConditionCount
        )
        previewLabel.stringValue = L10n.format(
            "当前设备身份预览：%@",
            DeviceIdentityRuleEvaluator.deviceKey(facts: facts, rule: rule)
        )
    }

    @objc private func saveTapped() {
        let rule = draftRule()
        if rule.enhancedRecognitionEnabled && rule.discriminatorFields.isEmpty {
            showError(L10n.text("启用增强识别时，至少选择一个实例区分字段。"))
            return
        }
        do {
            try ConfigManager.shared.applyIdentityRuleOverride(rule, forBaseKey: baseKey)
            onSaved?()
            dismiss(nil)
        } catch ConfigManager.IdentityRuleMigrationError.conflictingConfigurations(let oldKey, let newKey) {
            resolveConflictAndSave(rule: rule, oldKey: oldKey, newKey: newKey)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func restoreTapped() {
        do {
            try ConfigManager.shared.applyIdentityRuleOverride(nil, forBaseKey: baseKey)
            onSaved?()
            dismiss(nil)
        } catch ConfigManager.IdentityRuleMigrationError.conflictingConfigurations(let oldKey, let newKey) {
            resolveConflictAndSave(rule: nil, oldKey: oldKey, newKey: newKey)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func cancelTapped() { dismiss(nil) }

    private func resolveConflictAndSave(rule: DeviceIdentityRule?, oldKey: String, newKey: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("设备配置合并冲突")
        alert.informativeText = L10n.format(
            "「%@」与「%@」的配置不同。选择保留哪一份，或取消保存。",
            oldKey,
            newKey
        )
        alert.addButton(withTitle: L10n.text("保留原身份配置"))
        alert.addButton(withTitle: L10n.text("保留目标身份配置"))
        alert.addButton(withTitle: L10n.text("取消"))
        let response = alert.runModal()
        let resolution: ConfigManager.IdentityRuleConflictResolution
        switch response {
        case .alertFirstButtonReturn: resolution = .keepSource
        case .alertSecondButtonReturn: resolution = .keepDestination
        default: return
        }
        do {
            try ConfigManager.shared.applyIdentityRuleOverride(
                rule,
                forBaseKey: baseKey,
                conflictResolution: resolution
            )
            onSaved?()
            dismiss(nil)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("无法保存身份规则")
        alert.informativeText = message
        alert.runModal()
    }
}
