import Foundation

enum InputCoordinatorState: Equatable {
    case idle
    case preparing
    case waitingForDevice
    case active
    case scrollOnly
    case scrollOnlyMappingUnavailable(reason: String)
    case calibrating
    case unavailable(reason: String)

    var displayText: String {
        switch self {
        case .idle: return L10n.text("按键映射未启用")
        case .preparing: return L10n.text("正在启动鼠标判源与拦截…")
        case .waitingForDevice: return L10n.text("等待连接所选输入设备…")
        case .active: return L10n.text("映射已启用（HID 时间戳精确判源）")
        case .scrollOnly: return L10n.text("按键映射关闭；鼠标滚轮增强已运行")
        case .scrollOnlyMappingUnavailable(let reason): return L10n.format("滚轮增强已运行；按键映射不可用：%@", reason)
        case .calibrating: return L10n.text("正在读取板载鼠标按键定义…")
        case .unavailable(let reason): return L10n.format("输入功能不可用：%@", reason)
        }
    }
}

final class InputCoordinator {
    static let shared = InputCoordinator()
    static let stateDidChangeNotification = Notification.Name("NagaController.InputCoordinator.stateDidChange")

    private(set) var isRequestedEnabled = false
    private(set) var state: InputCoordinatorState = .idle
    private var isCalibrating = false
    private var resumeAfterCalibration = false
    private var deviceObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?

    private init() {
        EventTapManager.shared.onFailure = { [weak self] reason in
            self?.fail(reason)
        }
        deviceObserver = NotificationCenter.default.addObserver(
            forName: HIDListener.deviceStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let connected = notification.userInfo?["connected"] as? Bool ?? false
            self?.handleDeviceStateChanged(connected: connected)
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: ConfigManager.runtimeSettingsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isCalibrating else { return }
            self.reconcileRuntime()
        }
    }

    deinit {
        if let deviceObserver { NotificationCenter.default.removeObserver(deviceObserver) }
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    func start() {
        precondition(Thread.isMainThread)
        isRequestedEnabled = ConfigManager.shared.getRemappingEnabled()
        reconcileRuntime()
    }

    /// Re-evaluate TCC and device state after a system permission decision or
    /// after the app returns from System Settings. This avoids requiring the
    /// user to toggle remapping merely to retry initialization.
    func refreshPermissions() {
        precondition(Thread.isMainThread)
        guard !isCalibrating else { return }
        reconcileRuntime()
    }

    func setRemappingEnabled(_ enabled: Bool) {
        precondition(Thread.isMainThread)
        isRequestedEnabled = enabled
        ConfigManager.shared.setRemappingEnabled(enabled)
        if enabled {
            guard !isCalibrating else {
                resumeAfterCalibration = true
                return
            }
            reconcileRuntime()
        } else {
            resumeAfterCalibration = false
            reconcileRuntime()
        }
    }

    /// Scroll reversal is intentionally independent from button remapping and
    /// therefore requires Accessibility only, not Input Monitoring or HID.
    func setReverseScrollEnabled(_ enabled: Bool) {
        precondition(Thread.isMainThread)
        var settings = ConfigManager.shared.getScrollSettings()
        settings.enabled = enabled
        ConfigManager.shared.setScrollSettings(settings)
    }

    func setScrollSettings(_ settings: ScrollSettings) {
        precondition(Thread.isMainThread)
        ConfigManager.shared.setScrollSettings(settings)
    }

    func beginCalibration() -> Bool {
        precondition(Thread.isMainThread)
        guard PermissionManager.shared.hasInputMonitoringPermission() else {
            fail(L10n.text("缺少输入监控权限"))
            return false
        }
        HIDListener.shared.start(wait: true)
        guard HIDListener.shared.hasSupportedDevice else {
            setState(.unavailable(reason: L10n.text("未检测到可用的输入设备")))
            return false
        }
        resumeAfterCalibration = isRequestedEnabled
        isCalibrating = true
        HIDListener.shared.setRuntimeActivity(buttonMapping: false)
        EventTapManager.shared.stop()
        ButtonMapper.shared.releaseAllSyntheticInputs(reason: "hardware definition opened", wait: true)
        guard EventTapManager.shared.start(listenOnly: true) else {
            isCalibrating = false
            fail(L10n.text("无法创建手动读取所需的只监听 Event Tap"))
            return false
        }
        setState(.calibrating)
        return true
    }

    func endCalibration() {
        precondition(Thread.isMainThread)
        guard isCalibrating else { return }
        HIDListener.shared.endLearning()
        EventTapManager.shared.endLearning()
        EventTapManager.shared.stop()
        isCalibrating = false
        isRequestedEnabled = resumeAfterCalibration
        reconcileRuntime()
    }

    func stop(wait: Bool) {
        precondition(Thread.isMainThread)
        isRequestedEnabled = false
        isCalibrating = false
        EventTapManager.shared.stop()
        ScrollReversalManager.shared.stop()
        HIDListener.shared.setRuntimeActivity(buttonMapping: false)
        HIDListener.shared.stop(wait: wait)
        ButtonMapper.shared.releaseAllSyntheticInputs(reason: "application termination", wait: true)
        setState(.idle)
    }

    private func reconcileRuntime() {
        precondition(Thread.isMainThread)
        let wantsScroll = ConfigManager.shared.getScrollSettings().enabled
        let scrollIsActive: Bool
        if wantsScroll {
            if PermissionManager.shared.hasAccessibilityPermission() {
                scrollIsActive = ScrollReversalManager.shared.start()
            } else {
                ScrollReversalManager.shared.stop()
                scrollIsActive = false
            }
        } else {
            ScrollReversalManager.shared.stop()
            scrollIsActive = false
        }

        guard isRequestedEnabled else {
            deactivateButtonMapping()
            if scrollIsActive {
                setState(.scrollOnly)
            } else if wantsScroll {
                setState(.unavailable(reason: L10n.text("滚轮增强缺少辅助功能权限")))
            } else {
                setState(.idle)
            }
            return
        }
        activateButtonMapping(scrollIsActive: scrollIsActive)
    }

    private func activateButtonMapping(scrollIsActive: Bool) {
        setState(.preparing)
        guard PermissionManager.shared.hasAccessibilityPermission() else {
            mappingUnavailable(L10n.text("缺少辅助功能权限"), scrollIsActive: scrollIsActive)
            return
        }
        // Trigger the native Input Monitoring consent dialog on first use
        // instead of forcing the user to add the app manually.
        guard PermissionManager.shared.requestInputMonitoringPermissionIfNeeded() else {
            mappingUnavailable(L10n.text("缺少输入监控权限"), scrollIsActive: scrollIsActive)
            return
        }
        HIDListener.shared.start(wait: true)
        guard HIDListener.shared.hasSupportedDevice else {
            setState(scrollIsActive
                ? .scrollOnlyMappingUnavailable(reason: L10n.text("等待连接所选输入设备"))
                : .waitingForDevice)
            return
        }
        guard EventTapManager.shared.start(listenOnly: false) else {
            mappingUnavailable(L10n.text("无法创建可拦截 Event Tap"), scrollIsActive: scrollIsActive)
            return
        }
        HIDListener.shared.setRuntimeActivity(buttonMapping: true)
        ConfigManager.shared.setRemappingEnabled(isRequestedEnabled)
        setState(.active)
    }

    private func handleDeviceStateChanged(connected: Bool) {
        precondition(Thread.isMainThread)
        guard !isCalibrating else { return }
        if connected {
            if isRequestedEnabled { reconcileRuntime() }
        } else if isRequestedEnabled {
            EventTapManager.shared.stop()
            HIDListener.shared.setRuntimeActivity(buttonMapping: false)
            ButtonMapper.shared.releaseAllSyntheticInputs(reason: "Naga disconnected", wait: true)
            let scrollActive = ScrollReversalManager.shared.state == .active
            setState(scrollActive
                ? .scrollOnlyMappingUnavailable(reason: L10n.text("等待连接所选输入设备"))
                : .waitingForDevice)
        }
    }

    private func deactivateButtonMapping() {
        HIDListener.shared.setRuntimeActivity(buttonMapping: false)
        EventTapManager.shared.stop()
        EventCorrelationBroker.shared.clear()
        ButtonMapper.shared.releaseAllSyntheticInputs(reason: "remapping disabled", wait: true)
        // Keep non-exclusive HID discovery alive so the main panel can list
        // and select devices even while button customization is off.
    }

    private func fail(_ reason: String) {
        precondition(Thread.isMainThread)
        resumeAfterCalibration = false
        isCalibrating = false
        deactivateButtonMapping()
        setState(.unavailable(reason: reason))
    }

    private func mappingUnavailable(_ reason: String, scrollIsActive: Bool) {
        deactivateButtonMapping()
        setState(scrollIsActive
            ? .scrollOnlyMappingUnavailable(reason: reason)
            : .unavailable(reason: reason))
    }

    private func setState(_ newState: InputCoordinatorState) {
        state = newState
        NotificationCenter.default.post(name: Self.stateDidChangeNotification, object: self)
    }
}
