import Cocoa
import ApplicationServices

/// Small value-type registry used by EventTapManager and regression tests.
/// Several physical sources may occupy one CG key/button code concurrently.
struct MultiSourceRegistry<Source: Hashable> {
    private(set) var sourcesByCode: [Int: Set<Source>] = [:]

    mutating func insert(_ source: Source, for code: Int) -> Bool {
        sourcesByCode[code, default: []].insert(source).inserted
    }

    mutating func remove(_ source: Source, for code: Int) {
        guard var sources = sourcesByCode[code] else { return }
        sources.remove(source)
        if sources.isEmpty { sourcesByCode.removeValue(forKey: code) }
        else { sourcesByCode[code] = sources }
    }

    mutating func remove(for code: Int, where predicate: (Source) -> Bool) {
        guard let sources = sourcesByCode[code] else { return }
        let remaining = Set(sources.filter { !predicate($0) })
        if remaining.isEmpty { sourcesByCode.removeValue(forKey: code) }
        else { sourcesByCode[code] = remaining }
    }

    mutating func removeAll(where predicate: (Source) -> Bool) {
        for code in Array(sourcesByCode.keys) { remove(for: code, where: predicate) }
    }

    @discardableResult
    mutating func removeAll(for code: Int) -> Bool {
        sourcesByCode.removeValue(forKey: code) != nil
    }

    mutating func removeAll() { sourcesByCode.removeAll() }
    func isActive(_ code: Int) -> Bool { sourcesByCode[code]?.isEmpty == false }
}

enum LearnedCGEventKind: Equatable {
    case keyboard(keyCode: Int, modifierFlags: UInt64)
    case mouse(buttonNumber: Int)
    case horizontalScroll(direction: Int)
    case systemDefined
}

struct LearnedCGEvent: Equatable {
    let kind: LearnedCGEventKind
    let timestampNs: UInt64
}

/// Blocks only a CGEvent that consumes a one-shot token produced by the exact
/// Naga HID device. It never waits in the callback and never treats a bare
/// keyCode as proof of mouse origin.
final class EventTapManager {
    static let shared = EventTapManager()
    private static let systemDefinedType = CGEventType(rawValue: 14)!

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isListeningOnly = true
    /// A consumed mapped hold: which device's button occupies this key/button
    /// code, so release routes back to the same device's action table.
    private struct MappedHold: Hashable {
        let buttonIndex: Int
        let deviceKey: String?
    }

    /// One CG key/button code can be produced by several mapped sources at the
    /// same time. Keep every source identity instead of letting the second one
    /// overwrite (mouse) or get ignored (keyboard).
    private var activeKeyboardButtons = MultiSourceRegistry<MappedHold>()
    private var activeMouseButtons = MultiSourceRegistry<MappedHold>()
    // Uncorrelated downs from other pointing devices that passed through while
    // a Naga hold occupies the same button number. Their later up/dragged
    // events belong to that device and must never be swallowed.
    private var foreignMouseDowns: [Int: Int] = [:]
    // Key codes whose uncorrelated (physical-keyboard) down passed through
    // while a Naga hold shares the same key code — their autorepeats belong
    // to the keyboard and must not be swallowed.
    private var foreignKeyDowns: Set<Int> = []
    private var activeModifierKeyCodes: Set<Int> = []
    private var learningCallback: ((LearnedCGEvent) -> Void)?
    private var hardwareObserver: NSObjectProtocol?
    var onFailure: ((String) -> Void)?

    private init() {
        hardwareObserver = NotificationCenter.default.addObserver(
            forName: ConfigManager.runtimeRoutingDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearActiveState(reason: "hardware routing changed")
        }
    }

    deinit {
        if let hardwareObserver { NotificationCenter.default.removeObserver(hardwareObserver) }
    }

    @discardableResult
    func start(listenOnly: Bool) -> Bool {
        precondition(Thread.isMainThread)
        stop()
        isListeningOnly = listenOnly

        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .scrollWheel,
            Self.systemDefinedType
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: listenOnly ? .listenOnly : .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return true
    }

    func stop() {
        precondition(Thread.isMainThread)
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        learningCallback = nil
        clearActiveState(reason: "event tap stopped")
    }

    func beginLearning(_ callback: @escaping (LearnedCGEvent) -> Void) {
        precondition(Thread.isMainThread)
        learningCallback = callback
    }

    func endLearning() {
        precondition(Thread.isMainThread)
        learningCallback = nil
    }

    /// HID release is authoritative for output lifetime. If the matching CG
    /// release is lost, discard the local fallback state quickly so a later
    /// physical-key release cannot be mistaken for the mouse's release.
    func expireActiveSource(kind: CorrelatedEventKind, buttonIndex: Int?, deviceKey: String? = nil) {
        precondition(Thread.isMainThread)
        switch kind {
        case .keyboard(let keyCode):
            if let buttonIndex {
                if deviceKey == nil {
                    activeKeyboardButtons.remove(for: keyCode) { $0.buttonIndex == buttonIndex }
                } else {
                    activeKeyboardButtons.remove(MappedHold(buttonIndex: buttonIndex, deviceKey: deviceKey), for: keyCode)
                }
                foreignKeyDowns.remove(keyCode)
            }
        case .mouse(let button):
            if let buttonIndex {
                if deviceKey == nil {
                    activeMouseButtons.remove(for: button) { $0.buttonIndex == buttonIndex }
                } else {
                    activeMouseButtons.remove(MappedHold(buttonIndex: buttonIndex, deviceKey: deviceKey), for: button)
                }
                foreignMouseDowns.removeValue(forKey: button)
            }
        case .modifier(let keyCode):
            activeModifierKeyCodes.remove(keyCode)
        default:
            break
        }
    }

    /// One consumed device disappeared: drop only ITS holds so a second mouse
    /// held at the same moment keeps its synthetic output intact.
    func handleSourceDisconnected(deviceKey: String? = nil) {
        precondition(Thread.isMainThread)
        guard let deviceKey else {
            clearActiveState(reason: "Naga disconnected")
            return
        }
        activeKeyboardButtons.removeAll { $0.deviceKey == deviceKey }
        activeMouseButtons.removeAll { $0.deviceKey == deviceKey }
        foreignKeyDowns = Set(foreignKeyDowns.filter { activeKeyboardButtons.isActive($0) })
        foreignMouseDowns = foreignMouseDowns.filter { activeMouseButtons.isActive($0.key) }
        ButtonMapper.shared.releaseSyntheticInputs(
            forDeviceKey: deviceKey,
            reason: "HID source disconnected"
        )
    }

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if SyntheticEventMarker.isMarked(event) { return Unmanaged.passUnretained(event) }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            clearActiveState(reason: "event tap disabled")
            // Keep the callback small, release every synthetic hold first, and
            // immediately re-enable the same tap. This avoids both leaked
            // original events and stuck modifiers after a WindowServer timeout.
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if let learningCallback, let learned = learnedEvent(type: type, event: event) {
            DispatchQueue.main.async { learningCallback(learned) }
            return Unmanaged.passUnretained(event)
        }
        guard !isListeningOnly else { return Unmanaged.passUnretained(event) }

        let timestamp = event.timestamp
        switch type {
        case .flagsChanged:
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            guard Self.isModifierKeyCode(keyCode) else { return Unmanaged.passUnretained(event) }
            let preferredPressed = !activeModifierKeyCodes.contains(keyCode)
            let preferred = EventCorrelationBroker.shared.consume(
                kind: .modifier(keyCode),
                pressed: preferredPressed,
                eventTimestampNs: timestamp
            )
            let fallback = preferred == nil
                ? EventCorrelationBroker.shared.consume(
                    kind: .modifier(keyCode),
                    pressed: !preferredPressed,
                    eventTimestampNs: timestamp
                )
                : nil
            if preferred != nil || fallback != nil {
                let pressed = preferred != nil ? preferredPressed : !preferredPressed
                if pressed { activeModifierKeyCodes.insert(keyCode) }
                else { activeModifierKeyCodes.remove(keyCode) }
                return nil
            }

        case .keyDown:
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if let match = EventCorrelationBroker.shared.consume(kind: .keyboard(keyCode), pressed: true, eventTimestampNs: timestamp) {
                if let button = match.buttonIndex {
                    let hold = MappedHold(buttonIndex: button, deviceKey: match.deviceKey)
                    let inserted = activeKeyboardButtons.insert(hold, for: keyCode)
                    if inserted { ButtonMapper.shared.handlePress(buttonIndex: button, deviceKey: match.deviceKey) }
                }
                return nil
            }
            if activeKeyboardButtons.isActive(keyCode) {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    foreignKeyDowns.insert(keyCode)
                } else if !foreignKeyDowns.contains(keyCode) {
                    return nil
                }
            }

        case .keyUp:
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if let match = EventCorrelationBroker.shared.consume(kind: .keyboard(keyCode), pressed: false, eventTimestampNs: timestamp) {
                if let button = match.buttonIndex {
                    activeKeyboardButtons.remove(MappedHold(buttonIndex: button, deviceKey: match.deviceKey), for: keyCode)
                }
                return nil
            }
            // Uncorrelated key-up: the physical keyboard released this code.
            foreignKeyDowns.remove(keyCode)
            // Never use active mouse-key state to swallow an uncorrelated
            // key-up: it may belong to the physical keyboard and suppressing
            // it can leave that key logically stuck. HID release performs the
            // authoritative mapped-output cleanup and expires fallback state.

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            if let match = EventCorrelationBroker.shared.consume(kind: .mouse(button), pressed: true, eventTimestampNs: timestamp) {
                if let buttonIndex = match.buttonIndex {
                    let hold = MappedHold(buttonIndex: buttonIndex, deviceKey: match.deviceKey)
                    let inserted = activeMouseButtons.insert(hold, for: button)
                    if inserted { ButtonMapper.shared.handlePress(buttonIndex: buttonIndex, deviceKey: match.deviceKey) }
                }
                return nil
            }
            if activeMouseButtons.isActive(button) {
                foreignMouseDowns[button, default: 0] += 1
            }

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            if let match = EventCorrelationBroker.shared.consume(kind: .mouse(button), pressed: false, eventTimestampNs: timestamp) {
                if let buttonIndex = match.buttonIndex {
                    activeMouseButtons.remove(MappedHold(buttonIndex: buttonIndex, deviceKey: match.deviceKey), for: button)
                }
                return nil
            }
            if let pending = foreignMouseDowns[button], pending > 0 {
                foreignMouseDowns[button] = pending == 1 ? nil : pending - 1
                break
            }
            if activeMouseButtons.removeAll(for: button) { return nil }

        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            if activeMouseButtons.isActive(button), (foreignMouseDowns[button] ?? 0) == 0 { return nil }

        case .scrollWheel:
            guard let direction = Self.horizontalDirection(event) else {
                return Unmanaged.passUnretained(event)
            }
            if let match = EventCorrelationBroker.shared.consume(
                kind: .horizontalScroll(direction),
                pressed: true,
                eventTimestampNs: timestamp
            ) {
                if let button = match.buttonIndex {
                    ButtonMapper.shared.handle(buttonIndex: button, deviceKey: match.deviceKey)
                }
                return nil
            }

        case let value where value == Self.systemDefinedType:
            let down = EventCorrelationBroker.shared.consume(kind: .systemDefined, pressed: true, eventTimestampNs: timestamp)
            let up = down == nil
                ? EventCorrelationBroker.shared.consume(kind: .systemDefined, pressed: false, eventTimestampNs: timestamp)
                : nil
            if let match = down ?? up {
                if let button = match.buttonIndex {
                    if match.pressed {
                        ButtonMapper.shared.handlePress(buttonIndex: button, deviceKey: match.deviceKey)
                    } else {
                        ButtonMapper.shared.handleRelease(buttonIndex: button, deviceKey: match.deviceKey)
                    }
                }
                return nil
            }

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func learnedEvent(type: CGEventType, event: CGEvent) -> LearnedCGEvent? {
        switch type {
        case .keyDown:
            return LearnedCGEvent(
                kind: .keyboard(
                    keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                    modifierFlags: event.flags.intersection([
                        .maskCommand, .maskShift, .maskAlternate, .maskControl,
                        .maskSecondaryFn, .maskAlphaShift
                    ]).rawValue
                ),
                timestampNs: event.timestamp
            )
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return LearnedCGEvent(
                kind: .mouse(buttonNumber: Int(event.getIntegerValueField(.mouseEventButtonNumber))),
                timestampNs: event.timestamp
            )
        case .scrollWheel:
            guard let direction = Self.horizontalDirection(event) else { return nil }
            return LearnedCGEvent(kind: .horizontalScroll(direction: direction), timestampNs: event.timestamp)
        case let value where value == Self.systemDefinedType:
            return LearnedCGEvent(kind: .systemDefined, timestampNs: event.timestamp)
        default:
            return nil
        }
    }

    private func clearActiveState(reason: String) {
        activeKeyboardButtons.removeAll()
        activeMouseButtons.removeAll()
        foreignMouseDowns.removeAll()
        foreignKeyDowns.removeAll()
        activeModifierKeyCodes.removeAll()
        EventCorrelationBroker.shared.clear()
        ButtonMapper.shared.releaseAllSyntheticInputs(reason: reason)
    }


    private static func isModifierKeyCode(_ keyCode: Int) -> Bool {
        MacKeyCodes.isModifier(keyCode)
    }

    private static func horizontalDirection(_ event: CGEvent) -> Int? {
        let integer = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        if integer > 0 { return 1 }
        if integer < 0 { return -1 }
        let point = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        if point > 0 { return 1 }
        if point < 0 { return -1 }
        let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        if fixed > 0 { return 1 }
        if fixed < 0 { return -1 }
        return nil
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        return Unmanaged<EventTapManager>.fromOpaque(context).takeUnretainedValue().process(type: type, event: event)
    }
}
