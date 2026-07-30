import Foundation

enum CalibrationTiming {
    static let timeoutSeconds: TimeInterval = 20

    static func remainingSeconds(deadline: TimeInterval, now: TimeInterval) -> Int {
        max(0, Int(ceil(deadline - now)))
    }
}

enum HardwareCalibrationError: LocalizedError {
    case timedOut
    case changedSignal
    case unsupported

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return L10n.text("读取超时。请确认按下的是当前设备的目标按键。如果 DPI± 仍是默认私有功能，请先在 Windows 板载配置中改成普通键值；本软件不会写入鼠标。")
        case .changedSignal:
            return L10n.text("三次按键产生了不同信号，请重新录入。板载宏或文本不能作为稳定来源。")
        case .unsupported:
            return L10n.text("只支持单键、修饰键+单键、中键、额外鼠标键及系统功能键；物理左键和右键不能录入。")
        }
    }
}

final class HardwareCalibrationManager {
    static let shared = HardwareCalibrationManager()

    private struct Sample: Equatable {
        let hid: LearnedHIDEvent
        let cg: LearnedCGEvent
    }

    private var buttonIndex: Int?
    private var expectedDeviceKey: String?
    private var hidEvents: [LearnedHIDEvent] = []
    private var cgEvents: [LearnedCGEvent] = []
    private var samples: [Sample] = []
    private var timeoutWorkItem: DispatchWorkItem?
    private var progress: ((Int, Int) -> Void)?
    private var completion: ((Result<HardwareKey, Error>) -> Void)?
    private var persistsResult = true

    private init() {}

    func startCalibration(
        for buttonIndex: Int,
        expectedDeviceKey: String? = nil,
        persistResult: Bool = true,
        progress: @escaping (Int, Int) -> Void,
        completion: @escaping (Result<HardwareKey, Error>) -> Void
    ) {
        precondition(Thread.isMainThread)
        cancelCalibration(notify: false)
        // Accept the fixed 1–16 layout plus user-added custom sources (17+).
        guard InputSourceCatalog.supportedIndices.contains(buttonIndex) || buttonIndex >= 17 else {
            completion(.failure(HardwareCalibrationError.unsupported))
            return
        }
        self.buttonIndex = buttonIndex
        self.expectedDeviceKey = expectedDeviceKey
        self.persistsResult = persistResult
        self.progress = progress
        self.completion = completion
        progress(0, 3)

        HIDListener.shared.beginLearning { [weak self] event in self?.receive(hid: event) }
        EventTapManager.shared.beginLearning { [weak self] event in self?.receive(cg: event) }

        let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(HardwareCalibrationError.timedOut)) }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(
            deadline: .now() + CalibrationTiming.timeoutSeconds,
            execute: timeout
        )
    }

    func cancelCalibration() {
        cancelCalibration(notify: false)
    }

    private func receive(hid: LearnedHIDEvent) {
        precondition(Thread.isMainThread)
        guard buttonIndex != nil else { return }
        if let expectedDeviceKey, hid.deviceKey != expectedDeviceKey { return }
        if hid.usagePage == 0x09 && hid.usage <= 2 { return }
        hidEvents.append(hid)
        // The Razer wheel tilt reports horizontal pan as a VENDOR field, which
        // macOS never turns into a scroll CGEvent — so no CG pair would ever
        // arrive and the pan was unlearnable. Self-pair it: synthesize the
        // matching horizontal-scroll CG sample from the HID pan itself, keyed
        // to the HID timestamp so the existing correlation machinery completes.
        if hid.usagePage == 0x0c, hid.usage == 0x0238, hid.valueDirection != 0,
           !cgEvents.contains(where: { $0.timestampNs == hid.timestampNs && $0.kind == .horizontalScroll(direction: hid.valueDirection > 0 ? 1 : -1) }) {
            cgEvents.append(LearnedCGEvent(
                kind: .horizontalScroll(direction: hid.valueDirection > 0 ? 1 : -1),
                timestampNs: hid.timestampNs
            ))
        }
        pairPendingEvents()
    }

    private func receive(cg: LearnedCGEvent) {
        precondition(Thread.isMainThread)
        guard buttonIndex != nil else { return }
        cgEvents.append(cg)
        pairPendingEvents()
    }

    private func pairPendingEvents() {
        while let pair = closestCompatiblePair() {
            let hid = hidEvents.remove(at: pair.hidIndex)
            let cg = cgEvents.remove(at: pair.cgIndex)
            let sample = Sample(hid: hid, cg: cg)
            if let first = samples.first, !sameDefinition(first, sample) {
                finish(.failure(HardwareCalibrationError.changedSignal))
                return
            }
            samples.append(sample)
            progress?(samples.count, 3)
            if samples.count == 3 {
                completeFromSamples()
                return
            }
        }
        let now = MonotonicClock.nowNanoseconds()
        let cutoff = now > 500_000_000 ? now - 500_000_000 : 0
        hidEvents.removeAll { $0.timestampNs < cutoff }
        cgEvents.removeAll { $0.timestampNs < cutoff }
    }

    private func closestCompatiblePair() -> (hidIndex: Int, cgIndex: Int)? {
        var result: (Int, Int)?
        var bestDistance = UInt64.max
        for (hidIndex, hid) in hidEvents.enumerated() {
            for (cgIndex, cg) in cgEvents.enumerated() where compatible(hid, cg) {
                let distance = hid.timestampNs >= cg.timestampNs
                    ? hid.timestampNs - cg.timestampNs
                    : cg.timestampNs - hid.timestampNs
                guard distance <= 100_000_000, distance < bestDistance else { continue }
                result = (hidIndex, cgIndex)
                bestDistance = distance
            }
        }
        return result
    }

    private func compatible(_ hid: LearnedHIDEvent, _ cg: LearnedCGEvent) -> Bool {
        switch (hid.usagePage, cg.kind) {
        case (0x07, .keyboard):
            return !HIDUsageKeyCodeMap.isModifier(hid.usage)
        case (0x09, .mouse(let buttonNumber)):
            return hid.usage >= 3 && Int(hid.usage - 1) == buttonNumber
        case (0x0c, .horizontalScroll):
            return hid.usage == 0x0238 && hid.valueDirection != 0
        case (0x0c, .systemDefined), (0x01, .systemDefined):
            return true
        default:
            return false
        }
    }

    private func sameDefinition(_ lhs: Sample, _ rhs: Sample) -> Bool {
        // All three samples must come from the same physical device: with
        // several mice consumed at once, mixing signals from two devices
        // would write a definition into the wrong configuration group.
        guard lhs.hid.deviceKey == rhs.hid.deviceKey,
              lhs.hid.usagePage == rhs.hid.usagePage,
              lhs.hid.usage == rhs.hid.usage,
              lhs.hid.valueDirection == rhs.hid.valueDirection else { return false }
        switch (lhs.cg.kind, rhs.cg.kind) {
        case let (.keyboard(lCode, lFlags), .keyboard(rCode, rFlags)):
            return lCode == rCode && lFlags == rFlags
        case let (.mouse(lButton), .mouse(rButton)):
            return lButton == rButton
        case let (.horizontalScroll(lDirection), .horizontalScroll(rDirection)):
            return lDirection == rDirection
        case (.systemDefined, .systemDefined):
            return true
        default:
            return false
        }
    }

    private func completeFromSamples() {
        guard let buttonIndex, let first = samples.first else {
            finish(.failure(HardwareCalibrationError.unsupported))
            return
        }
        // The definition belongs to the device that emitted the signals, not
        // to whichever group the mapping window happens to be editing.
        let sourceDeviceKey = first.hid.deviceKey
        let existing = sourceDeviceKey.isEmpty
            ? ConfigManager.shared.getHardwareMapping()
            : ConfigManager.shared.hardwareMapping(
                forConfigKey: ConfigManager.shared.configKey(forDeviceKey: sourceDeviceKey)
            )
        let deltas = samples.map { sample -> Int64 in
            Int64(clamping: sample.cg.timestampNs) - Int64(clamping: sample.hid.timestampNs)
        }.sorted()
        let median = deltas[deltas.count / 2]
        let maximumDeviation = deltas.map { UInt64(($0 - median).magnitude) }.max() ?? 0
        let tolerance = min(max(maximumDeviation + 1_000_000, 3_000_000), 10_000_000)

        let keyCode: Int
        let modifierFlags: UInt64
        let display: String
        let eventDirection: Int?
        switch first.cg.kind {
        case .keyboard(let code, let flags):
            keyCode = code
            modifierFlags = flags
            display = HardwareKeyDisplay.keyboard(keyCode: code, modifierFlags: flags)
            eventDirection = nil
        case .mouse(let button):
            guard button >= 2 else {
                finish(.failure(HardwareCalibrationError.unsupported))
                return
            }
            keyCode = 1000 + button
            modifierFlags = 0
            display = button == 2
                ? L10n.text("中键（滚轮按下）")
                : L10n.format("鼠标按键 %d（额外鼠标键）", button + 1)
            eventDirection = nil
        case .horizontalScroll(let direction):
            keyCode = direction > 0 ? 4001 : 4000
            modifierFlags = 0
            display = first.hid.valueDirection > 0
                ? L10n.text("横向滚轮（硬件方向 +）")
                : L10n.text("横向滚轮（硬件方向 −）")
            eventDirection = direction
        case .systemDefined:
            keyCode = 3000
            modifierFlags = 0
            display = HardwareKeyDisplay.system(
                usagePage: first.hid.usagePage,
                usage: first.hid.usage
            )
            eventDirection = nil
        }

        ConfigManager.shared.setCorrelationTiming(offsetNs: median, toleranceNs: tolerance)
        let key = HardwareKey(
            usagePage: first.hid.usagePage,
            usage: first.hid.usage,
            keyCode: keyCode,
            displayString: display,
            groupId: nil,
            // Learning identifies the physical source only. Interception is a
            // separate, explicit choice after a Mac custom value is assigned.
            interceptEnabled: false,
            modifierFlags: modifierFlags,
            timestampOffsetNs: median,
            timestampToleranceNs: tolerance,
            valueDirection: first.hid.valueDirection == 0 ? nil : first.hid.valueDirection,
            eventDirection: eventDirection
        )
        if persistsResult {
            var mapping = existing
            mapping[String(buttonIndex)] = key
            if sourceDeviceKey.isEmpty {
                ConfigManager.shared.setHardwareMapping(mapping)
            } else {
                ConfigManager.shared.setHardwareMapping(mapping, forDeviceKey: sourceDeviceKey)
                // Show the freshly learned definition immediately: the editor
                // windows follow the editing scope, so point it at the device
                // that actually produced the signals.
                ConfigManager.shared.setEditingDevice(key: sourceDeviceKey)
            }
        }
        finish(.success(key))
    }

    private func finish(_ result: Result<HardwareKey, Error>) {
        precondition(Thread.isMainThread)
        let callback = completion
        cancelCalibration(notify: false)
        callback?(result)
    }

    private func cancelCalibration(notify: Bool) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        HIDListener.shared.endLearning()
        EventTapManager.shared.endLearning()
        buttonIndex = nil
        expectedDeviceKey = nil
        hidEvents.removeAll()
        cgEvents.removeAll()
        samples.removeAll()
        progress = nil
        if notify { completion?(.failure(HardwareCalibrationError.timedOut)) }
        completion = nil
        persistsResult = true
    }
}
