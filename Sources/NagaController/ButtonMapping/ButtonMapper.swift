import Cocoa
import Carbon.HIToolbox

struct OnboardKeyTransform: Equatable {
    let keyCode: CGKeyCode
    let modifierFlags: UInt64

    static func swappingCommandAndControl(key: HardwareKey) -> OnboardKeyTransform? {
        guard key.usesCommandControlTransform, (0...Int(UInt16.max)).contains(key.keyCode) else { return nil }
        var flags = CGEventFlags(rawValue: key.modifierFlags ?? 0)
        let hadCommand = flags.contains(.maskCommand)
        let hadControl = flags.contains(.maskControl)
        flags.remove([.maskCommand, .maskControl])
        if hadCommand { flags.insert(.maskControl) }
        if hadControl { flags.insert(.maskCommand) }
        return OnboardKeyTransform(keyCode: CGKeyCode(key.keyCode), modifierFlags: flags.rawValue)
    }
}

/// Serializes every mapped action and owns all synthetic key/button state.
/// No other component is allowed to post a held input directly.
final class ButtonMapper {
    static let shared = ButtonMapper()

    private let executor = DispatchQueue(label: "NagaController.ActionExecutor", qos: .userInitiated)
    private let executorKey = DispatchSpecificKey<Void>()
    private let generationLock = NSLock()

    // A release build starts with no implicit actions. User mappings are
    // loaded explicitly by ConfigManager.
    private var mapping: [Int: ActionType] = [:]

    private struct KeyHold {
        let keyCodesInPressOrder: [CGKeyCode]
    }

    /// Composite hold identity: several mice may hold the same button index
    /// at the same time, each resolving through its own profile.
    private struct HoldKey: Hashable {
        let deviceKey: String?
        let buttonIndex: Int
    }

    /// Per-device action tables (device's bound profile). A device without an
    /// entry falls back to `mapping` (the globally selected profile).
    private var deviceMappings: [String: [Int: ActionType]] = [:]
    /// Device-owned onboard shortcut transforms. A table contains only sources
    /// whose ordinary mapping interception is off, so configured Mac actions
    /// always keep precedence.
    private var deviceOnboardTransforms: [String: [Int: OnboardKeyTransform]] = [:]

    private var activeKeyHolds: [HoldKey: KeyHold] = [:]
    private var activeMouseHolds: [HoldKey: Int] = [:]
    private var activeScrollHolds: [HoldKey: ScrollControlRole] = [:]
    private var keyDownReferenceCounts: [CGKeyCode: Int] = [:]
    /// Mirrors keyDownReferenceCounts for mouse buttons: the OS has one state
    /// per physical button, so two sources holding the same mapped button must
    /// reference-count — the button releases only when the last holder lets go.
    private var mouseDownReferenceCounts: [Int: Int] = [:]
    private var executionGeneration: UInt64 = 0

    private init() {
        executor.setSpecific(key: executorKey, value: ())
    }

    func updateMapping(_ newMapping: [Int: ActionType]) {
        cancelQueuedActions()
        onExecutorSync {
            releaseAllNow(reason: "mapping update")
            mapping = newMapping
            NSLog("[Mapping] Updated mapping for \(newMapping.count) button(s)")
        }
    }

    /// Per-device action tables from each device's bound profile. Devices
    /// without an entry keep resolving through the global mapping above.
    func updateDeviceRuntime(
        mappings newMappings: [String: [Int: ActionType]],
        onboardTransforms newTransforms: [String: [Int: OnboardKeyTransform]]
    ) {
        cancelQueuedActions()
        onExecutorSync {
            releaseAllNow(reason: "device mapping update")
            deviceMappings = newMappings
            deviceOnboardTransforms = newTransforms
        }
    }

    private func action(deviceKey: String?, buttonIndex: Int) -> ActionType? {
        if let deviceKey, let table = deviceMappings[deviceKey] {
            return table[buttonIndex]
        }
        return mapping[buttonIndex]
    }

    private func onboardTransform(deviceKey: String?, buttonIndex: Int) -> OnboardKeyTransform? {
        guard let deviceKey else { return nil }
        return deviceOnboardTransforms[deviceKey]?[buttonIndex]
    }

    func handle(buttonIndex: Int, deviceKey: String? = nil) {
        let generation = currentGeneration()
        executor.async { [weak self] in
            guard let self, self.isCurrent(generation),
                  let action = self.action(deviceKey: deviceKey, buttonIndex: buttonIndex) else { return }
            self.performNow(action: action, generation: generation, deviceKey: deviceKey)
        }
    }

    func handlePress(buttonIndex: Int, deviceKey: String? = nil) {
        let generation = currentGeneration()
        executor.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            self.handlePressNow(buttonIndex: buttonIndex, deviceKey: deviceKey, generation: generation)
        }
    }

    func handleRelease(buttonIndex: Int, deviceKey: String? = nil) {
        executor.async { [weak self] in
            self?.handleReleaseNow(buttonIndex: buttonIndex, deviceKey: deviceKey)
        }
    }

    /// Releases only inputs posted by this process. Physical keyboard state is never modified.
    func releaseAllSyntheticInputs(reason: String, wait: Bool = false) {
        cancelQueuedActions()
        if wait {
            onExecutorSync { releaseAllNow(reason: reason) }
        } else {
            executor.async { [weak self] in self?.releaseAllNow(reason: reason) }
        }
    }

    /// Releases only the holds owned by one device — unplugging one mouse
    /// must not drop a key another mouse is still holding.
    func releaseSyntheticInputs(forDeviceKey deviceKey: String, reason: String) {
        executor.async { [weak self] in
            guard let self else { return }
            let holds = Set(
                self.activeKeyHolds.keys.filter { $0.deviceKey == deviceKey } +
                self.activeMouseHolds.keys.filter { $0.deviceKey == deviceKey } +
                self.activeScrollHolds.keys.filter { $0.deviceKey == deviceKey }
            )
            guard !holds.isEmpty else { return }
            for hold in holds {
                self.handleReleaseNow(buttonIndex: hold.buttonIndex, deviceKey: hold.deviceKey)
            }
            NSLog("[Mapping] Released %d hold(s) for device %@: %@", holds.count, deviceKey, reason)
        }
    }

    private func handlePressNow(buttonIndex: Int, deviceKey: String?, generation: UInt64) {
        let holdKey = HoldKey(deviceKey: deviceKey, buttonIndex: buttonIndex)
        guard activeKeyHolds[holdKey] == nil,
              activeMouseHolds[holdKey] == nil,
              activeScrollHolds[holdKey] == nil else {
            return
        }
        if let transform = onboardTransform(deviceKey: deviceKey, buttonIndex: buttonIndex) {
            let codes = modifierKeyCodes(fromRawFlags: transform.modifierFlags) + [transform.keyCode]
            for code in codes { retainKeyDown(code) }
            activeKeyHolds[holdKey] = KeyHold(keyCodesInPressOrder: codes)
            NSLog("[Mapping] Onboard Command/Control transform start for button \(buttonIndex)")
            return
        }
        guard let action = action(deviceKey: deviceKey, buttonIndex: buttonIndex) else {
            NSLog("[Mapping] No action mapped for button \(buttonIndex).")
            return
        }

        switch action {
        case .keySequence(let keys, _) where keys.count == 1:
            guard let stroke = keys.first, let keyCode = effectiveKeyCode(for: stroke) else {
                for stroke in keys { sendKeyStrokeNow(stroke) }
                return
            }
            let codes = modifierKeyCodes(from: stroke.modifiers) + [keyCode]
            for code in codes { retainKeyDown(code) }
            activeKeyHolds[holdKey] = KeyHold(keyCodesInPressOrder: codes)
            NSLog("[Mapping] Hold start for button \(buttonIndex) -> key=\(stroke.displayLabel)")

        case .systemAction(let identifier, _):
            guard let definition = SystemActionDefinition.definition(for: identifier) else { return }
            guard definition.executionMode == .stateful else {
                performNow(action: action, generation: generation, deviceKey: deviceKey)
                return
            }
            let stroke = definition.stroke
            guard let keyCode = effectiveKeyCode(for: stroke) else { return }
            let codes = modifierKeyCodes(from: stroke.modifiers) + [keyCode]
            for code in codes { retainKeyDown(code) }
            activeKeyHolds[holdKey] = KeyHold(keyCodesInPressOrder: codes)
            NSLog("[Mapping] mac shortcut hold start for button \(buttonIndex) -> \(definition.name)")

        case .mouseClick(let button, _):
            guard retainMouseDown(button) else { return }
            activeMouseHolds[holdKey] = button
            NSLog("[Mapping] Mouse hold start for button \(buttonIndex) -> mouseBtn=\(button)")

        case .scrollControl(let role, _):
            activeScrollHolds[holdKey] = role
            ScrollReversalManager.shared.handleMappedControl(role, isDown: true, buttonIndex: buttonIndex, deviceKey: deviceKey)
            NSLog("[Mapping] Scroll control start for button \(buttonIndex) -> \(role.rawValue)")

        default:
            performNow(action: action, generation: generation, deviceKey: deviceKey)
        }
    }

    private func handleReleaseNow(buttonIndex: Int, deviceKey: String?) {
        let holdKey = HoldKey(deviceKey: deviceKey, buttonIndex: buttonIndex)
        if let hold = activeKeyHolds.removeValue(forKey: holdKey) {
            for code in hold.keyCodesInPressOrder.reversed() { releaseKeyDown(code) }
            NSLog("[Mapping] Hold end for button \(buttonIndex)")
        }
        if let button = activeMouseHolds.removeValue(forKey: holdKey) {
            releaseMouseDown(button)
            NSLog("[Mapping] Mouse hold end for button \(buttonIndex)")
        }
        if let role = activeScrollHolds.removeValue(forKey: holdKey) {
            ScrollReversalManager.shared.handleMappedControl(role, isDown: false, buttonIndex: buttonIndex, deviceKey: deviceKey)
            NSLog("[Mapping] Scroll control end for button \(buttonIndex)")
        }
    }

    private func performNow(action: ActionType, generation: UInt64, deviceKey: String? = nil) {
        switch action {
        case .keySequence(let keys, _):
            for stroke in keys { sendKeyStrokeNow(stroke) }

        case .application(let path, _):
            let url = URL(fileURLWithPath: path)
            DispatchQueue.main.async {
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: NSWorkspace.OpenConfiguration(),
                    completionHandler: nil
                )
            }

        case .systemCommand(let command, _):
            runShell(command)

        case .textSnippet(let text, _):
            pasteTextPreservingClipboard(text)

        case .macro(let steps, _):
            runMacroNow(steps, generation: generation)

        case .profileSwitch(let profile, _):
            // Device-first: the switch applies to the device that pressed the
            // button; events without a device identity fall back to the
            // legacy global switch.
            DispatchQueue.main.async {
                if let deviceKey {
                    ConfigManager.shared.setActiveProfile(profile, forDeviceKey: deviceKey)
                } else {
                    ConfigManager.shared.setCurrentProfile(profile)
                }
            }

        case .mouseClick(let button, _):
            // Discrete click through the same ref-count, so it doesn't drop a
            // button another source is holding.
            if retainMouseDown(button) {
                releaseMouseDown(button)
            }

        case .systemAction(let identifier, _):
            guard let definition = SystemActionDefinition.definition(for: identifier) else { return }
            sendKeyStrokeNow(definition.stroke)

        case .openTarget(let target, _):
            DispatchQueue.main.async {
                let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
                let url: URL?
                if let webURL = URL(string: trimmed), webURL.scheme != nil {
                    url = webURL
                } else {
                    url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
                }
                if let url { NSWorkspace.shared.open(url) }
            }

        case .scrollControl(let role, _):
            ScrollReversalManager.shared.handleMappedControl(role, isDown: true, buttonIndex: -1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                ScrollReversalManager.shared.handleMappedControl(role, isDown: false, buttonIndex: -1)
            }
        }
    }

    /// Returns false only when the first physical down actually failed to post.
    @discardableResult
    private func retainMouseDown(_ button: Int) -> Bool {
        let oldCount = mouseDownReferenceCounts[button] ?? 0
        mouseDownReferenceCounts[button] = oldCount + 1
        guard oldCount == 0 else { return true }
        guard postMouse(button: button, down: true) else {
            // No active hold will be recorded by the caller on failure, so the
            // speculative count must be rolled back here. Otherwise every
            // later press incorrectly assumes the OS button is already down.
            mouseDownReferenceCounts.removeValue(forKey: button)
            return false
        }
        return true
    }

    private func releaseMouseDown(_ button: Int) {
        guard let oldCount = mouseDownReferenceCounts[button], oldCount > 0 else { return }
        if oldCount > 1 {
            mouseDownReferenceCounts[button] = oldCount - 1
            return
        }
        mouseDownReferenceCounts.removeValue(forKey: button)
        _ = postMouse(button: button, down: false)
    }

    private func retainKeyDown(_ keyCode: CGKeyCode) {
        let oldCount = keyDownReferenceCounts[keyCode] ?? 0
        keyDownReferenceCounts[keyCode] = oldCount + 1
        guard oldCount == 0 else { return }
        postKey(keyCode, down: true, flags: currentModifierFlags())
    }

    private func releaseKeyDown(_ keyCode: CGKeyCode) {
        guard let oldCount = keyDownReferenceCounts[keyCode], oldCount > 0 else { return }
        if oldCount > 1 {
            keyDownReferenceCounts[keyCode] = oldCount - 1
            return
        }
        keyDownReferenceCounts.removeValue(forKey: keyCode)
        postKey(keyCode, down: false, flags: currentModifierFlags())
    }

    private func postKey(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .privateState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else {
            return
        }
        event.flags = flags
        event.setIntegerValueField(.keyboardEventKeyboardType, value: 43)
        SyntheticEventMarker.mark(event)
        event.post(tap: .cghidEventTap)
    }

    private func sendKeyStrokeNow(_ stroke: KeyStroke) {
        guard let keyCode = effectiveKeyCode(for: stroke) else { return }
        let codes = modifierKeyCodes(from: stroke.modifiers) + [keyCode]
        for code in codes { retainKeyDown(code) }
        usleep(2_000)
        for code in codes.reversed() { releaseKeyDown(code) }
    }

    private func effectiveKeyCode(for stroke: KeyStroke) -> CGKeyCode? {
        if let code = stroke.keyCode { return CGKeyCode(code) }
        return KeyStroke.keyCode(for: stroke.key).map { CGKeyCode($0) }
    }

    private func modifierKeyCodes(from modifiers: [String]) -> [CGKeyCode] {
        var result: [CGKeyCode] = []
        for modifier in modifiers.map({ $0.lowercased() }) {
            let code: CGKeyCode?
            switch modifier {
            case "cmd", "command": code = 55
            case "shift": code = 56
            case "alt", "option": code = 58
            case "ctrl", "control": code = 59
            case "fn": code = 63
            default: code = nil
            }
            if let code, !result.contains(code) { result.append(code) }
        }
        return result
    }

    private func modifierKeyCodes(fromRawFlags rawValue: UInt64) -> [CGKeyCode] {
        let flags = CGEventFlags(rawValue: rawValue)
        var result: [CGKeyCode] = []
        if flags.contains(.maskCommand) { result.append(55) }
        if flags.contains(.maskShift) { result.append(56) }
        if flags.contains(.maskAlternate) { result.append(58) }
        if flags.contains(.maskControl) { result.append(59) }
        if flags.contains(.maskSecondaryFn) { result.append(63) }
        return result
    }

    private func currentModifierFlags() -> CGEventFlags {
        var flags: CGEventFlags = []
        for (code, count) in keyDownReferenceCounts where count > 0 {
            switch code {
            case 54, 55: flags.insert(.maskCommand)
            case 56, 60: flags.insert(.maskShift)
            case 58, 61: flags.insert(.maskAlternate)
            case 59, 62: flags.insert(.maskControl)
            case 63: flags.insert(.maskSecondaryFn)
            default: break
            }
        }
        return flags
    }

    private func isModifierKeyCode(_ code: CGKeyCode) -> Bool {
        MacKeyCodes.isModifier(Int(code))
    }

    private func postMouse(button: Int, down: Bool) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let location = CGEvent(source: source)?.location else { return false }
        let pair = mouseEventType(for: button, down: down)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: pair.type,
            mouseCursorPosition: location,
            mouseButton: pair.button
        ) else { return false }
        SyntheticEventMarker.mark(event)
        event.post(tap: .cghidEventTap)
        return true
    }

    private func mouseEventType(for button: Int, down: Bool) -> (type: CGEventType, button: CGMouseButton) {
        let mouseButton: CGMouseButton
        switch button {
        case 0: mouseButton = .left
        case 1: mouseButton = .right
        case 2: mouseButton = .center
        default: mouseButton = CGMouseButton(rawValue: UInt32(button)) ?? .center
        }
        switch (button, down) {
        case (0, true): return (.leftMouseDown, mouseButton)
        case (0, false): return (.leftMouseUp, mouseButton)
        case (1, true): return (.rightMouseDown, mouseButton)
        case (1, false): return (.rightMouseUp, mouseButton)
        case (_, true): return (.otherMouseDown, mouseButton)
        case (_, false): return (.otherMouseUp, mouseButton)
        }
    }

    private func runShell(_ command: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", command]
        do {
            try task.run()
        } catch {
            NSLog("[Mapping] Failed to run command: \(error.localizedDescription)")
        }
    }

    func runMacro(_ steps: [MacroStep]) {
        let generation = currentGeneration()
        executor.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            self.runMacroNow(steps, generation: generation)
        }
    }

    private func runMacroNow(_ steps: [MacroStep], generation: UInt64, startingAt startIndex: Int = 0) {
        var index = startIndex
        while index < steps.count {
            guard isCurrent(generation) else { return }
            let step = steps[index]
            switch step.type {
            case "key":
                if let stroke = step.keyStroke { sendKeyStrokeNow(stroke) }
            case "text":
                if let text = step.text { pasteTextPreservingClipboard(text) }
            case "delay":
                let delay = max(0, min(step.delayMs ?? 0, 60_000))
                let nextIndex = index + 1
                executor.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak self] in
                    guard let self, self.isCurrent(generation) else { return }
                    self.runMacroNow(steps, generation: generation, startingAt: nextIndex)
                }
                return
            default:
                break
            }
            index += 1
        }
    }

    private func pasteTextPreservingClipboard(_ text: String) {
        // NSPasteboard is AppKit state; snapshot and mutate it on the main
        // thread even though mapped actions are serialized on our executor.
        let snapshot: ([NSPasteboardItem]?, Int) = onMainSync {
            let pasteboard = NSPasteboard.general
            let oldItems = pasteboard.pasteboardItems?.map(clonePasteboardItem)
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return (oldItems, pasteboard.changeCount)
        }
        sendKeyStrokeNow(KeyStroke(key: "v", modifiers: ["cmd"]))
        // Some targets read the pasteboard after handling the key event. Keep
        // ownership long enough for slow first-responder/application hops.
        usleep(300_000)
        onMainSync {
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount == snapshot.1 {
                pasteboard.clearContents()
                if let oldItems = snapshot.0, !oldItems.isEmpty { pasteboard.writeObjects(oldItems) }
            }
        }
    }

    private func onMainSync<T>(_ operation: () -> T) -> T {
        if Thread.isMainThread { return operation() }
        return DispatchQueue.main.sync(execute: operation)
    }

    private func clonePasteboardItem(_ item: NSPasteboardItem) -> NSPasteboardItem {
        let copy = NSPasteboardItem()
        for type in item.types {
            if let data = item.data(forType: type) { copy.setData(data, forType: type) }
        }
        return copy
    }

    private func releaseAllNow(reason: String) {
        for button in Set(mouseDownReferenceCounts.keys) {
            _ = postMouse(button: button, down: false)
        }
        mouseDownReferenceCounts.removeAll()
        activeMouseHolds.removeAll()
        activeScrollHolds.removeAll()
        ScrollReversalManager.shared.releaseAllMappedControls()
        activeKeyHolds.removeAll()

        let downCodes = Array(keyDownReferenceCounts.keys)
        let ordinaryCodes = downCodes.filter { !isModifierKeyCode($0) }.sorted(by: >)
        let modifierCodes = downCodes.filter(isModifierKeyCode).sorted(by: >)
        for code in ordinaryCodes + modifierCodes {
            keyDownReferenceCounts.removeValue(forKey: code)
            postKey(code, down: false, flags: currentModifierFlags())
        }
        keyDownReferenceCounts.removeAll()

        if !downCodes.isEmpty {
            NSLog("[Mapping] Released \(downCodes.count) synthetic key(s): \(reason)")
        }
    }

    private func onExecutorSync(_ body: () -> Void) {
        if DispatchQueue.getSpecific(key: executorKey) != nil {
            body()
        } else {
            executor.sync(execute: body)
        }
    }

    private func currentGeneration() -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        return executionGeneration
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        currentGeneration() == generation
    }

    private func cancelQueuedActions() {
        generationLock.lock()
        executionGeneration &+= 1
        generationLock.unlock()
    }
}
