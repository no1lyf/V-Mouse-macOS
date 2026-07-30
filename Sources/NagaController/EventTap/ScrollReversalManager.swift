import Cocoa
import ApplicationServices

enum ScrollReversalState: Equatable {
    case stopped
    case active
    case unavailable(String)

    var displayText: String {
        switch self {
        case .stopped: return L10n.text("滚轮增强未启用")
        case .active: return L10n.text("鼠标滚轮增强已运行（触控板不受影响）")
        case .unavailable(let reason): return L10n.format("滚轮增强不可用：%@", reason)
        }
    }
}

struct ScrollEventCharacteristics: Equatable {
    let isContinuous: Bool
    let scrollPhase: Double
    let momentumPhase: Double
    let scrollCount: Int64

    /// Mos uses phase, momentum and scroll metadata instead of
    /// correlating the CGEvent with a second HID timestamp. Keeping this as a
    /// pure function makes the mouse/trackpad boundary regression-testable.
    var isTrackpadLike: Bool {
        // Naga wheel events can carry isContinuous=1 even though they are
        // physical wheel ticks. Mos does not use isContinuous as a hard
        // trackpad test. Phase/momentum remain the reliable gesture boundary;
        // scrollCount is also not a hard exclusion because mouse drivers may
        // use it for acceleration.
        scrollPhase != 0 || momentumPhase != 0
    }
}

/// A dedicated scroll Event Tap. It is intentionally independent from Naga
/// button observation: scroll reversal needs Accessibility only and remains
/// useful even when Input Monitoring or the Naga HID reader is unavailable.
final class ScrollReversalManager {
    static let shared = ScrollReversalManager()
    static let stateDidChangeNotification = Notification.Name("NagaController.ScrollReversal.stateDidChange")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var settings = ScrollSettings.defaults
    private var controlSources: [ScrollControlRole: Set<String>] = [:]
    private(set) var state: ScrollReversalState = .stopped
    private(set) var reversedEventCount: UInt64 = 0
    private(set) var lastOriginalVerticalDelta: Double?
    private(set) var lastReversedVerticalDelta: Double?

    private init() {}

    @discardableResult
    func start() -> Bool {
        precondition(Thread.isMainThread)
        let latestSettings = ConfigManager.shared.getScrollSettings()
        if case .active = state, eventTap != nil {
            if settings != latestSettings {
                // Applying a new curve/direction in the middle of an old
                // momentum stream would mix two configurations. End it and
                // clear held controls before adopting the new snapshot.
                ScrollSmoothingEngine.shared.stop()
                controlSources.removeAll()
                ScrollSmoothingEngine.shared.setShiftAxis(false)
                settings = latestSettings
            }
            return true
        }
        stop()
        settings = latestSettings

        let mask = (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            setState(.unavailable(L10n.text("无法创建滚轮 Event Tap，请检查辅助功能权限")))
            return false
        }

        eventTap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            eventTap = nil
            setState(.unavailable(L10n.text("无法创建滚轮监听运行源")))
            return false
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        setState(.active)
        return true
    }

    func stop() {
        precondition(Thread.isMainThread)
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        ScrollSmoothingEngine.shared.stop()
        controlSources.removeAll()
        ScrollSmoothingEngine.shared.setShiftAxis(false)
        setState(.stopped)
    }

    func handleMappedControl(_ role: ScrollControlRole, isDown: Bool, buttonIndex: Int, deviceKey: String? = nil) {
        // The source key carries the device so two mice holding the same
        // button index cannot release each other's control.
        DispatchQueue.main.async { [weak self] in
            self?.setControl(role, isDown: isDown, source: "mapping.\(deviceKey ?? "global").\(buttonIndex)")
        }
    }

    func releaseAllMappedControls() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for role in ScrollControlRole.allCases {
                let mappedSources = (self.controlSources[role] ?? []).filter { $0.hasPrefix("mapping.") }
                for source in mappedSources {
                    self.setControl(role, isDown: false, source: source)
                }
            }
        }
    }

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            ScrollSmoothingEngine.shared.stop()
            controlSources.removeAll()
            ScrollSmoothingEngine.shared.setShiftAxis(false)
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                setState(.active)
            } else {
                setState(.unavailable(L10n.text("滚轮 Event Tap 被系统停用且无法恢复")))
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown || type == .keyUp || type == .flagsChanged {
            handleHotkey(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown {
            ScrollSmoothingEngine.shared.stop()
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel, !SyntheticEventMarker.isMarked(event) else {
            return Unmanaged.passUnretained(event)
        }

        let characteristics = ScrollEventCharacteristics(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhase: event.getDoubleValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getDoubleValueField(.scrollWheelEventMomentumPhase),
            scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount)
        )
        guard !characteristics.isTrackpadLike else { return Unmanaged.passUnretained(event) }

        let original = Self.preferredDelta(axis: 1, event: event)
        let shiftAxis = isControlActive(.shiftAxis)
        let reverseVertical = shiftAxis ? settings.reverseHorizontal : settings.reverseVertical
        if settings.reverse && reverseVertical { Self.reverse(axis: 1, event: event) }
        if settings.reverse && settings.reverseHorizontal { Self.reverse(axis: 2, event: event) }

        let y = Self.preferredDelta(axis: 1, event: event) ?? 0
        let x = Self.preferredDelta(axis: 2, event: event) ?? 0
        let smoothEnabled = settings.smooth && !isControlActive(.blockSmooth)
        let shiftsVerticalToHorizontal = shiftAxis && y != 0 && x == 0
        // A shifted vertical tick becomes horizontal output, so its smoothing
        // switch follows the destination axis rather than the source axis.
        let smoothY = smoothEnabled
            && (shiftsVerticalToHorizontal ? settings.smoothHorizontal : settings.smoothVertical)
            && y != 0
        let smoothX = smoothEnabled && settings.smoothHorizontal && x != 0
        if smoothY || smoothX {
            let smoothedY = smoothY ? Self.normalized(y, step: settings.step) : 0
            let smoothedX = smoothX ? Self.normalized(x, step: settings.step) : 0
            ScrollSmoothingEngine.shared.update(
                settings: settings,
                y: smoothedY,
                x: smoothedX,
                amplification: isControlActive(.accelerate) ? 5 : 1,
                shiftAxis: shiftAxis
            )
            if smoothY { Self.clear(axis: 1, event: event) }
            if smoothX { Self.clear(axis: 2, event: event) }
        }
        if shiftsVerticalToHorizontal && !smoothY {
            // Mos' Shift-axis behavior is independent of smoothing. Preserve
            // all three CoreGraphics delta representations for compatibility
            // with applications that read different scroll fields.
            Self.moveVerticalDeltaToHorizontal(event)
        }
        reversedEventCount &+= 1
        lastOriginalVerticalDelta = original
        lastReversedVerticalDelta = Self.preferredDelta(axis: 1, event: event)
        if (y == 0 || smoothY) && (x == 0 || smoothX) && (smoothY || smoothX) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private static func preferredDelta(axis: Int, event: CGEvent) -> Double? {
        let fields: (CGEventField, CGEventField, CGEventField) = axis == 2
            ? (.scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventDeltaAxis2)
            : (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventDeltaAxis1)
        let point = event.getDoubleValueField(fields.0)
        if point != 0 { return point }
        let fixed = event.getDoubleValueField(fields.1)
        if fixed != 0 { return fixed }
        let integer = event.getIntegerValueField(fields.2)
        return integer == 0 ? nil : Double(integer)
    }

    private static func normalized(_ value: Double, step: Double) -> Double {
        value.sign == .minus ? -max(abs(value), step) : max(abs(value), step)
    }

    private static func clear(axis: Int, event: CGEvent) {
        let integer: CGEventField = axis == 2 ? .scrollWheelEventDeltaAxis2 : .scrollWheelEventDeltaAxis1
        let point: CGEventField = axis == 2 ? .scrollWheelEventPointDeltaAxis2 : .scrollWheelEventPointDeltaAxis1
        let fixed: CGEventField = axis == 2 ? .scrollWheelEventFixedPtDeltaAxis2 : .scrollWheelEventFixedPtDeltaAxis1
        event.setIntegerValueField(integer, value: 0)
        event.setDoubleValueField(point, value: 0)
        event.setDoubleValueField(fixed, value: 0)
    }

    static func moveVerticalDeltaToHorizontal(_ event: CGEvent) {
        event.setIntegerValueField(
            .scrollWheelEventDeltaAxis2,
            value: event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        )
        event.setDoubleValueField(
            .scrollWheelEventPointDeltaAxis2,
            value: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        )
        event.setDoubleValueField(
            .scrollWheelEventFixedPtDeltaAxis2,
            value: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        )
        clear(axis: 1, event: event)
    }

    private func isControlActive(_ role: ScrollControlRole) -> Bool {
        !(controlSources[role] ?? []).isEmpty
    }

    private func setControl(_ role: ScrollControlRole, isDown: Bool, source: String) {
        let wasActive = isControlActive(role)
        var sources = controlSources[role] ?? []
        if isDown { sources.insert(source) } else { sources.remove(source) }
        controlSources[role] = sources
        let isActive = !sources.isEmpty
        if role == .blockSmooth, !wasActive, isActive {
            ScrollSmoothingEngine.shared.stop()
        } else if role == .shiftAxis, wasActive != isActive {
            ScrollSmoothingEngine.shared.setShiftAxis(isActive)
        }
    }

    private func handleHotkey(type: CGEventType, event: CGEvent) {
        let bindings: [(ScrollControlRole, ScrollHotkey?)] = [
            (.accelerate, settings.dashHotkey),
            (.shiftAxis, settings.shiftAxisHotkey),
            (.blockSmooth, settings.blockSmoothHotkey)
        ]
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        for (role, binding) in bindings {
            guard let binding, binding.keyCode == code else { continue }
            let source = "hotkey.\(role.rawValue).\(code)"
            if type == .flagsChanged {
                guard Self.isModifierKey(code) else { continue }
                let aggregateIsDown = Self.modifierIsDown(code, flags: event.flags)
                // flags are aggregate across left/right variants. If this
                // exact code was already held and another variant keeps the
                // aggregate flag set, a flagsChanged for this code is its
                // release and must still clear our source.
                let exactSourceWasDown = (controlSources[role] ?? []).contains(source)
                setControl(role, isDown: aggregateIsDown && !exactSourceWasDown, source: source)
            } else if type == .keyDown {
                guard Self.flags(event.flags, include: binding.modifiers) else { continue }
                setControl(role, isDown: true, source: source)
            } else if type == .keyUp {
                setControl(role, isDown: false, source: source)
            }
        }
    }

    private static func flags(_ flags: CGEventFlags, include modifiers: [String]) -> Bool {
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "cmd", "command": if !flags.contains(.maskCommand) { return false }
            case "shift": if !flags.contains(.maskShift) { return false }
            case "alt", "option": if !flags.contains(.maskAlternate) { return false }
            case "ctrl", "control": if !flags.contains(.maskControl) { return false }
            default: break
            }
        }
        return true
    }

    private static func isModifierKey(_ code: UInt16) -> Bool {
        MacKeyCodes.isModifier(Int(code))
    }

    private static func modifierIsDown(_ code: UInt16, flags: CGEventFlags) -> Bool {
        switch code {
        case 54, 55: return flags.contains(.maskCommand)
        case 56, 60: return flags.contains(.maskShift)
        case 58, 61: return flags.contains(.maskAlternate)
        case 59, 62: return flags.contains(.maskControl)
        case 63: return flags.contains(.maskSecondaryFn)
        default: return false
        }
    }

    /// Reverse all representations of one axis using the API type associated
    /// with that field. Fixed-point fields are exposed by CoreGraphics through
    /// the double-value API; treating them as integers loses fractional input.
    static func reverse(axis: Int, event: CGEvent) {
        let integerField: CGEventField
        let pointField: CGEventField
        let fixedField: CGEventField
        switch axis {
        case 2:
            integerField = .scrollWheelEventDeltaAxis2
            pointField = .scrollWheelEventPointDeltaAxis2
            fixedField = .scrollWheelEventFixedPtDeltaAxis2
        default:
            integerField = .scrollWheelEventDeltaAxis1
            pointField = .scrollWheelEventPointDeltaAxis1
            fixedField = .scrollWheelEventFixedPtDeltaAxis1
        }
        let integer = event.getIntegerValueField(integerField)
        let point = event.getDoubleValueField(pointField)
        let fixed = event.getDoubleValueField(fixedField)
        if integer != 0 { event.setIntegerValueField(integerField, value: -integer) }
        if point != 0 { event.setDoubleValueField(pointField, value: -point) }
        if fixed != 0 { event.setDoubleValueField(fixedField, value: -fixed) }
    }

    private func setState(_ newState: ScrollReversalState) {
        guard state != newState else { return }
        state = newState
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.stateDidChangeNotification, object: self)
        }
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        return Unmanaged<ScrollReversalManager>.fromOpaque(context).takeUnretainedValue()
            .process(type: type, event: event)
    }
}
