import Foundation
import IOKit.hid

struct LearnedHIDEvent: Equatable {
    let usagePage: UInt32
    let usage: UInt32
    let timestampNs: UInt64
    let valueDirection: Int
    /// Stable key of the device that emitted the signal, so learned
    /// definitions land in that device's own configuration group.
    let deviceKey: String

    init(usagePage: UInt32, usage: UInt32, timestampNs: UInt64, valueDirection: Int = 0, deviceKey: String = "") {
        self.usagePage = usagePage
        self.usage = usage
        self.timestampNs = timestampNs
        self.valueDirection = valueDirection
        self.deviceKey = deviceKey
    }
}

/// Observes reports from the exact audited Naga without seizing it. Runtime
/// suppression is performed by EventTapManager only after a one-shot token from
/// this device is matched by type, phase and hardware timestamp.
final class HIDListener {
    static let shared = HIDListener()
    static let deviceStateDidChangeNotification = Notification.Name("NagaController.HIDListener.deviceStateDidChange")
    static let candidateStateDidChangeNotification = Notification.Name("NagaController.HIDListener.candidateStateDidChange")
    private static let selectedCandidateDefaultsKey = "selectedHIDDeviceCandidateIdentifier"
    private static let enabledStandardDevicesDefaultsKey = "enabledStandardDeviceKeys"
    private static let disabledCodecDevicesDefaultsKey = "disabledCodecDeviceKeys"

    private struct DeviceState {
        var pointerButtons: UInt8 = 0
        var consumerUsage: UInt32 = 0
        var systemUsages: Set<UInt32> = []
        var keyboardModifiers: UInt8 = 0
        var keyboardUsages: Set<UInt32> = []
        // Route selected by the non-modifier key in the current keyboard
        // chord. This lets the per-button pass-through switch apply to the
        // chord's modifier transitions as well as its main key.
        var keyboardInterceptionActive: Bool?
    }

    struct Binding {
        let buttonIndex: Int
        let key: HardwareKey
    }

    private struct CandidateRecord {
        let summary: HIDDeviceCandidateSummary
        let codec: NagaHIDCodec?
    }

    private struct StandardEventKey: Hashable {
        let deviceKey: String
        let page: UInt32
        let usage: UInt32
        let pressed: Bool
    }

    private let queue = DispatchQueue(label: "NagaController.HIDListener", qos: .userInteractive)
    private let queueKey = DispatchSpecificKey<Void>()
    private var manager: IOHIDManager?
    private var supportedDevices: [IOHIDDevice: NagaHIDCodec] = [:]
    private var candidateRecords: [IOHIDDevice: CandidateRecord] = [:]
    /// Standard-HID devices the user explicitly enabled, by stable deviceKey.
    /// Codec-backed devices are always consumed and never appear here.
    private var enabledStandardKeysStorage: Set<String> = []
    /// Codec-backed devices the user explicitly paused, by stable deviceKey.
    private var disabledCodecKeysStorage: Set<String> = []
    private var selectedStandardDevices: Set<IOHIDDevice> = []
    private var standardArrayUsages: [IOHIDDevice: [IOHIDElementCookie: UInt32]] = [:]
    private var recentStandardEvents: [StandardEventKey: UInt64] = [:]
    private var deviceStates: [IOHIDDevice: DeviceState] = [:]
    /// Per-device binding tables: each consumed device resolves signatures
    /// against its own configuration group's learned table.
    private var bindingsByDevice: [String: [HIDUsageSignature: Binding]] = [:]
    /// The device that most recently produced a mapped-relevant signal;
    /// the mapping UI uses it as the default editing scope. Written on the
    /// HID queue, read via the queue-synchronized accessor below.
    private var lastInputDeviceKeyStorage: String?

    var lastInputDeviceKey: String? {
        onQueueSync { lastInputDeviceKeyStorage }
    }
    private var isButtonMappingActive = false
    private var learningCallback: ((LearnedHIDEvent) -> Void)?
    private var configurationObserver: NSObjectProtocol?

    private init() {
        queue.setSpecific(key: queueKey, value: ())
        var enabled = Set(
            (UserDefaults.standard.array(forKey: Self.enabledStandardDevicesDefaultsKey) as? [String]) ?? []
        )
        // The pre-0.3.6 single-selection model migrates into the enabled set:
        // a previously selected standard device stays usable, a codec device
        // is consumed automatically anyway (harmless surplus entry).
        if let legacySelection = Self.migrateSelectionToDeviceKey(
            UserDefaults.standard.string(forKey: Self.selectedCandidateDefaultsKey)
        ) {
            enabled.insert(legacySelection)
            UserDefaults.standard.removeObject(forKey: Self.selectedCandidateDefaultsKey)
            UserDefaults.standard.set(Array(enabled).sorted(), forKey: Self.enabledStandardDevicesDefaultsKey)
        }
        enabledStandardKeysStorage = enabled
        disabledCodecKeysStorage = Set(
            (UserDefaults.standard.array(forKey: Self.disabledCodecDevicesDefaultsKey) as? [String]) ?? []
        )
        configurationObserver = NotificationCenter.default.addObserver(
            forName: ConfigManager.runtimeRoutingDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in self?.queue.async { self?.reloadBindings() } }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    func start(wait: Bool = false) {
        let operation: () -> Void = { [weak self] in self?.startNow() }
        if wait { onQueueSync(operation) }
        else { queue.async(execute: operation) }
    }

    func stop(wait: Bool = false) {
        let operation: () -> Void = { [weak self] in self?.stopNow() }
        if wait { onQueueSync(operation) }
        else { queue.async(execute: operation) }
    }

    func setRuntimeActivity(buttonMapping: Bool) {
        queue.async { [weak self] in
            self?.isButtonMappingActive = buttonMapping
            if !buttonMapping {
                EventCorrelationBroker.shared.clear()
            }
        }
    }

    func beginLearning(_ callback: @escaping (LearnedHIDEvent) -> Void) {
        queue.async { [weak self] in
            self?.learningCallback = callback
        }
    }

    func endLearning() {
        queue.async { [weak self] in
            self?.learningCallback = nil
        }
    }

    var hasSupportedDevice: Bool {
        onQueueSync { !supportedDevices.isEmpty || !selectedStandardDevices.isEmpty }
    }

    var deviceCandidates: [HIDDeviceCandidateSummary] {
        onQueueSync {
            candidateRecords.values.map(\.summary).sorted {
                if $0.isSupported != $1.isSupported { return $0.isSupported && !$1.isSupported }
                if $0.product != $1.product { return $0.product < $1.product }
                return $0.identifier < $1.identifier
            }
        }
    }

    /// Stable keys of user-enabled standard-HID devices.
    var enabledStandardDeviceKeys: Set<String> {
        onQueueSync { enabledStandardKeysStorage }
    }

    /// Stable keys of codec-backed devices the user explicitly paused.
    var disabledCodecDeviceKeys: Set<String> {
        onQueueSync { disabledCodecKeysStorage }
    }

    /// Pauses or resumes a codec-backed device. Codec devices default to
    /// enabled; pausing also keeps the group's standard interfaces off.
    func setCodecDevice(deviceKey: String, enabled: Bool) {
        onQueueSync {
            if enabled {
                disabledCodecKeysStorage.remove(deviceKey)
                disabledCodecKeysStorage.remove(DeviceIdentityPolicy.baseKey(from: deviceKey))
            } else {
                disabledCodecKeysStorage.insert(deviceKey)
            }
            UserDefaults.standard.set(
                Array(disabledCodecKeysStorage).sorted(),
                forKey: Self.disabledCodecDevicesDefaultsKey
            )
            prepareForDeviceSelectionChange()
            reconcileSupportedDevices()
        }
    }

    /// Stable keys of every device group currently being consumed.
    var consumedDeviceKeys: Set<String> {
        onQueueSync { consumedDeviceKeysLocked() }
    }

    /// Older builds persisted "vvvv:pppp:location:fingerprint". The location
    /// changes with the USB port, which silently orphaned the selection after
    /// replugging. Reduce any legacy value to the stable "vvvv:pppp" key.
    /// Pure parsing — the caller decides how to persist the result.
    static func migrateSelectionToDeviceKey(_ stored: String?) -> String? {
        guard let stored, !stored.isEmpty else { return nil }
        let parts = stored.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        return "\(parts[0]):\(parts[1])"
    }

    var deviceCandidateGroups: [HIDPhysicalDeviceCandidateGroup] {
        onQueueSync {
            let grouped = Dictionary(grouping: candidateRecords.values.map(\.summary), by: \.physicalGroupIdentifier)
            return grouped.map { identifier, candidates in
                let sorted = candidates.sorted {
                    if $0.codecIdentifier != nil && $1.codecIdentifier == nil { return true }
                    if $0.codecIdentifier == nil && $1.codecIdentifier != nil { return false }
                    return $0.identifier < $1.identifier
                }
                let representative = sorted[0]
                return HIDPhysicalDeviceCandidateGroup(
                    identifier: identifier,
                    product: representative.product,
                    transport: representative.transport,
                    locationID: representative.locationID,
                    candidates: sorted
                )
            }.sorted {
                if $0.isSupported != $1.isSupported { return $0.isSupported && !$1.isSupported }
                if $0.product != $1.product { return $0.product < $1.product }
                return $0.identifier < $1.identifier
            }
        }
    }

    /// Enables or disables one standard-HID device by its stable key. Codec
    /// devices are always consumed and ignore this switch. Vendor-private
    /// elements remain ignored regardless.
    @discardableResult
    func setStandardDevice(deviceKey: String, enabled: Bool) -> Bool {
        onQueueSync {
            if enabled {
                guard candidateRecords.values.contains(where: {
                    $0.summary.deviceKey == deviceKey && $0.summary.isSupported
                }) else { return false }
                enabledStandardKeysStorage.insert(deviceKey)
            } else {
                enabledStandardKeysStorage.remove(deviceKey)
                enabledStandardKeysStorage.remove(DeviceIdentityPolicy.baseKey(from: deviceKey))
            }
            UserDefaults.standard.set(
                Array(enabledStandardKeysStorage).sorted(),
                forKey: Self.enabledStandardDevicesDefaultsKey
            )
            prepareForDeviceSelectionChange()
            reconcileSupportedDevices()
            return true
        }
    }

    /// Re-enumerates every HID device the manager can currently see, prunes
    /// records whose device has silently disappeared, and republishes the
    /// candidate list. Manual entry point behind the UI's "search devices".
    func rescanDevices(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            defer { if let completion { DispatchQueue.main.async(execute: completion) } }
            guard let self else { return }
            if self.manager == nil { self.startNow() }
            guard let manager = self.manager else { return }
            var live: Set<IOHIDDevice> = []
            if let devices = IOHIDManagerCopyDevices(manager) {
                for case let device as IOHIDDevice in devices as NSSet {
                    live.insert(device)
                    self.deviceMatched(device)
                }
            }
            let stale = self.candidateRecords.keys.filter { !live.contains($0) }
            for device in stale { self.deviceRemoved(device) }
            self.reconcileSupportedDevices()
            self.notifyCandidateStateChanged()
        }
    }

    /// Rebuild candidate summaries after a persisted identity rule changes.
    /// Codec authorization is recalculated from the immutable registry and is
    /// never influenced by user-editable identity conditions.
    func refreshIdentityRules(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            defer { if let completion { DispatchQueue.main.async(execute: completion) } }
            guard let self else { return }
            self.prepareForDeviceSelectionChange()
            for device in Array(self.candidateRecords.keys) {
                let identity = Self.identity(for: device)
                self.candidateRecords[device] = CandidateRecord(
                    summary: NagaHIDCodecRegistry.summary(for: identity),
                    codec: NagaHIDCodecRegistry.codec(for: identity)
                )
            }
            self.reconcileSupportedDevices()
            self.notifyCandidateStateChanged()
        }
    }

    private func prepareForDeviceSelectionChange() {
        EventCorrelationBroker.shared.clear()
        ButtonMapper.shared.releaseAllSyntheticInputs(reason: "HID device selection changed")
        deviceStates.removeAll()
        standardArrayUsages.removeAll()
        recentStandardEvents.removeAll()
    }

    private func startNow() {
        guard manager == nil else { return }
        reloadBindings()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Enumerate all HID devices so the UI can offer external standard-HID
        // candidates. Raw reports still remain gated by the exact codec registry.
        IOHIDManagerSetDeviceMatching(manager, nil)
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemovedCallback, context)
        IOHIDManagerRegisterInputReportWithTimeStampCallback(manager, Self.reportCallback, context)
        IOHIDManagerRegisterInputValueCallback(manager, Self.inputValueCallback, context)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            NSLog("[HID] Unable to open IOHIDManager")
            return
        }
        IOHIDManagerSetDispatchQueue(manager, queue)
        self.manager = manager
        if let devices = IOHIDManagerCopyDevices(manager) {
            for case let device as IOHIDDevice in devices as NSSet { deviceMatched(device) }
        }
        IOHIDManagerActivate(manager)
    }

    private func stopNow() {
        learningCallback = nil
        isButtonMappingActive = false
        EventCorrelationBroker.shared.clear()
        supportedDevices.removeAll()
        bindingsByDevice.removeAll()
        candidateRecords.removeAll()
        selectedStandardDevices.removeAll()
        standardArrayUsages.removeAll()
        recentStandardEvents.removeAll()
        deviceStates.removeAll()
        guard let manager else { return }
        IOHIDManagerCancel(manager)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    private func reloadBindings() {
        // Archived devices leave the runtime entirely: they neither intercept
        // onboard keys nor execute mapped actions until unarchived.
        let deviceKeys = consumedDeviceKeysLocked()
            .filter { !ConfigManager.shared.isDeviceArchived($0) }
        var updatedByDevice: [String: [HIDUsageSignature: Binding]] = [:]
        var transformsByDevice: [String: [Int: OnboardKeyTransform]] = [:]
        for deviceKey in deviceKeys {
            let mapping = ConfigManager.shared.runtimeHardwareMapping(forDeviceKey: deviceKey)
            updatedByDevice[deviceKey] = Self.buildBindingTable(from: mapping)
            transformsByDevice[deviceKey] = Dictionary(uniqueKeysWithValues: mapping.compactMap { index, key in
                guard let sourceIndex = Int(index),
                      let transform = OnboardKeyTransform.swappingCommandAndControl(key: key) else { return nil }
                return (sourceIndex, transform)
            })
        }
        bindingsByDevice = updatedByDevice
        // Keep ButtonMapper's per-device action tables in lockstep so a
        // bound profile applies without touching the global selection.
        ButtonMapper.shared.updateDeviceRuntime(
            mappings: ConfigManager.shared.deviceActionMappings(forDeviceKeys: Array(deviceKeys)),
            onboardTransforms: transformsByDevice
        )
    }

    static func buildBindingTable(from mapping: [String: HardwareKey]) -> [HIDUsageSignature: Binding] {
        var updated: [HIDUsageSignature: Binding] = [:]
        for (indexString, key) in mapping.sorted(by: {
            (Int($0.key) ?? Int.max) < (Int($1.key) ?? Int.max)
        }) {
            // Accept the fixed 1–16 layout and user-added custom sources (17+).
            guard let index = Int(indexString), index >= 1 else { continue }
            let signature = HIDUsageSignature(
                page: key.usagePage,
                usage: key.usage,
                direction: key.valueDirection ?? 0
            )
            if signature.page == 0x09 && signature.usage <= 2 { continue }
            if updated[signature] == nil {
                updated[signature] = Binding(buttonIndex: index, key: key)
            }
        }
        return updated
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        guard candidateRecords[device] == nil else { return }
        let identity = Self.identity(for: device)
        guard !identity.isBuiltIn else { return }
        let summary = NagaHIDCodecRegistry.summary(for: identity)
        let codec = NagaHIDCodecRegistry.codec(for: identity)
        candidateRecords[device] = CandidateRecord(summary: summary, codec: codec)
        NSLog(
            "[HID] Candidate %04x:%04x '%@' transport=%@ location=%x max=%d descriptor=%@ codec=%@",
            identity.vendorID, identity.productID, identity.product, identity.transport,
            identity.locationID, identity.maximumInputReportSize,
            summary.descriptorFingerprint, codec?.rawValue ?? "unsupported"
        )
        reconcileSupportedDevices()
        notifyCandidateStateChanged()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let wasConnected = supportedDevices[device] != nil || selectedStandardDevices.contains(device)
        let removedKey = candidateRecords[device]?.summary.deviceKey
        candidateRecords.removeValue(forKey: device)
        supportedDevices.removeValue(forKey: device)
        deviceStates.removeValue(forKey: device)
        standardArrayUsages.removeValue(forKey: device)
        if wasConnected {
            EventCorrelationBroker.shared.clear()
            // Scope the cleanup to the device that actually left: another
            // mouse holding a key at this moment keeps its output.
            if let removedKey,
               candidateRecords.values.contains(where: { $0.summary.deviceKey == removedKey }) == false {
                ButtonMapper.shared.releaseSyntheticInputs(forDeviceKey: removedKey, reason: "device disconnected")
                DispatchQueue.main.async { EventTapManager.shared.handleSourceDisconnected(deviceKey: removedKey) }
            } else if removedKey == nil {
                ButtonMapper.shared.releaseAllSyntheticInputs(reason: "device disconnected")
                DispatchQueue.main.async { EventTapManager.shared.handleSourceDisconnected() }
            }
        }
        reconcileSupportedDevices()
        notifyCandidateStateChanged()
    }

    private func consumedDeviceKeysLocked() -> Set<String> {
        var keys = Set(supportedDevices.keys.compactMap { candidateRecords[$0]?.summary.deviceKey })
        keys.formUnion(selectedStandardDevices.compactMap { candidateRecords[$0]?.summary.deviceKey })
        return keys
    }

    /// Multi-device consumption: every codec-backed device is always consumed;
    /// standard-HID devices are consumed when the user enabled their key.
    /// Within one physical group a codec interface wins over the standard
    /// interfaces so the same physical device is never consumed twice.
    private func reconcileSupportedDevices() {
        let previousConnected = !supportedDevices.isEmpty || !selectedStandardDevices.isEmpty
        var updated: [IOHIDDevice: NagaHIDCodec] = [:]
        var standardDevices: Set<IOHIDDevice> = []

        let groupsWithCodec = Set(
            candidateRecords.values
                .filter { $0.codec != nil }
                .map(\.summary.physicalGroupIdentifier)
        )

        for (device, record) in candidateRecords {
            if let codec = record.codec {
                // Codec devices are on by default but can be paused by the user.
                guard !disabledCodecKeysStorage.contains(record.summary.deviceKey),
                      !disabledCodecKeysStorage.contains(record.summary.baseDeviceKey) else { continue }
                updated[device] = codec
                if deviceStates[device] == nil { deviceStates[device] = DeviceState() }
                continue
            }
            guard record.summary.supportsStandardHID,
                  (enabledStandardKeysStorage.contains(record.summary.deviceKey)
                    || enabledStandardKeysStorage.contains(record.summary.baseDeviceKey)),
                  !groupsWithCodec.contains(record.summary.physicalGroupIdentifier) else { continue }
            // Standard HID stays opt-in per device key. Private vendor
            // elements are ignored downstream regardless.
            standardDevices.insert(device)
        }
        for device in supportedDevices.keys where updated[device] == nil {
            deviceStates.removeValue(forKey: device)
        }
        supportedDevices = updated
        selectedStandardDevices = standardDevices
        reloadBindings()
        let connected = !supportedDevices.isEmpty || !selectedStandardDevices.isEmpty
        if previousConnected != connected { notifyDeviceStateChanged(connected: connected) }
        notifyDevicesSeen()
    }

    /// Per-consumed-device book-keeping on the main thread: product names,
    /// one-shot legacy table migration. No profile switching — actions are
    /// resolved per device at press time.
    private func notifyDevicesSeen() {
        let consumed = consumedDeviceKeysLocked()
        let seen: [(HIDDeviceCandidateSummary, Bool)] = candidateRecords.values.compactMap { record in
            guard consumed.contains(record.summary.deviceKey) else { return nil }
            return (record.summary, record.codec != nil)
        }
        guard !seen.isEmpty else { return }
        DispatchQueue.main.async {
            for (summary, codecBacked) in seen {
                ConfigManager.shared.noteDeviceSeen(summary: summary, codecBacked: codecBacked)
            }
        }
    }

    private func handleStandardValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard selectedStandardDevices.contains(device),
              let deviceKey = candidateRecords[device]?.summary.deviceKey else { return }
        let page = UInt32(IOHIDElementGetUsagePage(element))
        let declaredUsage = UInt32(IOHIDElementGetUsage(element))
        let integerValue = IOHIDValueGetIntegerValue(value)
        let timestamp = IOHIDValueGetTimeStamp(value)

        switch page {
        case 0x09:
            guard declaredUsage >= 3 else { return }
            handleStandardSource(
                deviceKey: deviceKey,
                page: page,
                usage: declaredUsage,
                pressed: integerValue != 0,
                timestamp: timestamp
            )
        case 0x07, 0x0c, 0x01:
            if declaredUsage == 0 || declaredUsage == UInt32.max || declaredUsage == 0xffff {
                handleStandardArrayValue(
                    device: device,
                    deviceKey: deviceKey,
                    element: element,
                    page: page,
                    integerValue: integerValue,
                    timestamp: timestamp
                )
            } else {
                // Generic Desktop is restricted to System Control usages.
                if page == 0x01 && !(0x81...0x83).contains(declaredUsage) { return }
                handleStandardSource(
                    deviceKey: deviceKey,
                    page: page,
                    usage: declaredUsage,
                    pressed: integerValue != 0,
                    timestamp: timestamp
                )
            }
        default:
            // Vendor-defined and all other pages are intentionally fail-closed.
            return
        }
    }

    private func handleStandardSource(
        deviceKey: String,
        page: UInt32,
        usage: UInt32,
        pressed: Bool,
        timestamp: UInt64
    ) {
        // Deduplication is per physical device: interfaces of one composite
        // device repeat events within ~1 ms, but two DIFFERENT mice pressing
        // the same usage nearly simultaneously are both legitimate.
        let key = StandardEventKey(deviceKey: deviceKey, page: page, usage: usage, pressed: pressed)
        let timestampNs = MonotonicClock.nanoseconds(fromMachAbsolute: timestamp)
        if let previous = recentStandardEvents[key],
           timestampNs >= previous,
           timestampNs - previous <= 1_000_000 {
            return
        }
        recentStandardEvents[key] = timestampNs
        if recentStandardEvents.count > 128 {
            recentStandardEvents = recentStandardEvents.filter {
                timestampNs >= $0.value && timestampNs - $0.value <= 100_000_000
            }
        }
        handleSource(deviceKey: deviceKey, page: page, usage: usage, pressed: pressed, timestamp: timestamp)
    }

    private func handleStandardArrayValue(
        device: IOHIDDevice,
        deviceKey: String,
        element: IOHIDElement,
        page: UInt32,
        integerValue: CFIndex,
        timestamp: UInt64
    ) {
        let cookie = IOHIDElementGetCookie(element)
        let previous = standardArrayUsages[device]?[cookie] ?? 0
        let next = integerValue > 0 && integerValue <= Int(UInt32.max)
            ? UInt32(integerValue)
            : 0
        guard previous != next else { return }
        if previous != 0 {
            handleStandardSource(deviceKey: deviceKey, page: page, usage: previous, pressed: false, timestamp: timestamp)
        }
        if next != 0 {
            handleStandardSource(deviceKey: deviceKey, page: page, usage: next, pressed: true, timestamp: timestamp)
        }
        standardArrayUsages[device, default: [:]][cookie] = next
    }

    private func handleReport(
        device: IOHIDDevice,
        result: IOReturn,
        reportID: UInt32,
        report: UnsafePointer<UInt8>,
        length: Int,
        timestamp: UInt64
    ) {
        guard result == kIOReturnSuccess, let codec = supportedDevices[device],
              let deviceKey = candidateRecords[device]?.summary.deviceKey else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        guard let decoded = codec.decode(reportID: reportID, bytes: bytes) else { return }
        var state = deviceStates[device] ?? DeviceState()

        switch decoded {
        case .pointer(let nextButtons, let horizontalPanDirection):
            for bit in 2...5 {
                let mask = UInt8(1 << bit)
                let wasPressed = state.pointerButtons & mask != 0
                let isPressed = nextButtons & mask != 0
                if wasPressed != isPressed {
                    handleSource(deviceKey: deviceKey, page: 0x09, usage: UInt32(bit + 1), pressed: isPressed, timestamp: timestamp)
                }
            }
            state.pointerButtons = nextButtons
            if let direction = horizontalPanDirection {
                handlePulseSource(
                    deviceKey: deviceKey,
                    page: 0x0c,
                    usage: 0x0238,
                    direction: direction,
                    timestamp: timestamp
                )
            }

        case .consumer(let next):
            if state.consumerUsage != next {
                if state.consumerUsage != 0 {
                    handleSource(deviceKey: deviceKey, page: 0x0c, usage: state.consumerUsage, pressed: false, timestamp: timestamp)
                }
                if next != 0 { handleSource(deviceKey: deviceKey, page: 0x0c, usage: next, pressed: true, timestamp: timestamp) }
                state.consumerUsage = next
            }

        case .system(let next):
            for usage in state.systemUsages.subtracting(next) {
                handleSource(deviceKey: deviceKey, page: 0x01, usage: usage, pressed: false, timestamp: timestamp)
            }
            for usage in next.subtracting(state.systemUsages) {
                handleSource(deviceKey: deviceKey, page: 0x01, usage: usage, pressed: true, timestamp: timestamp)
            }
            state.systemUsages = next

        case .keyboard(let nextModifiers, let nextUsages):

            // A Naga side button can expose an onboard shortcut such as
            // Command-C. The switch belongs to that complete shortcut, not to
            // the individual modifier usage. Prefer the newly pressed main
            // key and retain its route through releases. Any report containing
            // a regular key always resolves a route from its bindings, so the
            // final fallback is reached only for modifier-only chords, which
            // have no binding to leak — pass them through so an onboard Shift
            // or Command side key keeps its native behavior.
            let pressedUsages = nextUsages.subtracting(state.keyboardUsages)
            let chordRoute = keyboardInterceptionRoute(deviceKey: deviceKey, for: pressedUsages)
                ?? keyboardInterceptionRoute(deviceKey: deviceKey, for: nextUsages)
                ?? state.keyboardInterceptionActive
                ?? keyboardInterceptionRoute(deviceKey: deviceKey, for: state.keyboardUsages)
                ?? false

            for bit in 0..<8 {
                let mask = UInt8(1 << bit)
                let wasPressed = state.keyboardModifiers & mask != 0
                let isPressed = nextModifiers & mask != 0
                guard wasPressed != isPressed else { continue }
                let usage = UInt32(0xe0 + bit)
                handleSource(
                    deviceKey: deviceKey,
                    page: 0x07,
                    usage: usage,
                    pressed: isPressed,
                    timestamp: timestamp,
                    interceptionOverride: chordRoute
                )
            }
            for usage in state.keyboardUsages.subtracting(nextUsages) {
                handleSource(deviceKey: deviceKey, page: 0x07, usage: usage, pressed: false, timestamp: timestamp)
            }
            for usage in nextUsages.subtracting(state.keyboardUsages) {
                handleSource(deviceKey: deviceKey, page: 0x07, usage: usage, pressed: true, timestamp: timestamp)
            }
            state.keyboardModifiers = nextModifiers
            state.keyboardUsages = nextUsages
            state.keyboardInterceptionActive = (nextModifiers != 0 || !nextUsages.isEmpty) ? chordRoute : nil

        }
        deviceStates[device] = state
    }

    private func handleSource(
        deviceKey: String,
        page: UInt32,
        usage: UInt32,
        pressed: Bool,
        timestamp: UInt64,
        interceptionOverride: Bool? = nil
    ) {
        let signature = HIDUsageSignature(page: page, usage: usage)
        let binding = bindingsByDevice[deviceKey]?[signature]
        if pressed { lastInputDeviceKeyStorage = deviceKey }

        if pressed, let learningCallback, !HIDUsageKeyCodeMap.isModifier(usage) {
            let event = LearnedHIDEvent(
                usagePage: page,
                usage: usage,
                timestampNs: MonotonicClock.nanoseconds(fromMachAbsolute: timestamp),
                deviceKey: deviceKey
            )
            DispatchQueue.main.async { learningCallback(event) }
        }
        guard isButtonMappingActive else { return }
        guard Self.shouldCreateRuntimeToken(
            page: page,
            usage: usage,
            hasBinding: binding != nil,
            bindingIntercepted: binding?.key.requiresRuntimeInterception ?? false,
            interceptionOverride: interceptionOverride
        ) else { return }

        let kind: CorrelatedEventKind?
        switch page {
        case 0x07:
            let learnedCode = binding.map { $0.key.keyCode & 0xffff }
            let code = learnedCode ?? HIDUsageKeyCodeMap.keyCode(for: usage)
            if let code {
                kind = HIDUsageKeyCodeMap.isModifier(usage) ? .modifier(code) : .keyboard(code)
            } else {
                kind = nil
            }
        case 0x09 where usage >= 3:
            // An unbound physical middle button must keep its normal behavior.
            // Once usage 3 is explicitly learned, the user accepts that the
            // physical middle button and simulated-middle side key are linked.
            kind = (binding != nil || usage > 3) ? .mouse(Int(usage - 1)) : nil
        case 0x0c, 0x01:
            kind = .systemDefined
        default:
            kind = nil
        }

        if let kind {
            EventCorrelationBroker.shared.enqueue(
                kind: kind,
                pressed: pressed,
                buttonIndex: binding?.buttonIndex,
                deviceKey: deviceKey,
                hidTimestamp: timestamp,
                offsetNs: binding?.key.timestampOffsetNs,
                toleranceNs: binding?.key.timestampToleranceNs
            )
            if !pressed {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) {
                    EventTapManager.shared.expireActiveSource(
                        kind: kind,
                        buttonIndex: binding?.buttonIndex,
                        deviceKey: deviceKey
                    )
                }
            }
        }
        if !pressed, let binding, binding.key.requiresRuntimeInterception {
            ButtonMapper.shared.handleRelease(buttonIndex: binding.buttonIndex, deviceKey: deviceKey)
        }
    }

    private func handlePulseSource(deviceKey: String, page: UInt32, usage: UInt32, direction: Int, timestamp: UInt64) {
        let signature = HIDUsageSignature(page: page, usage: usage, direction: direction)
        let binding = bindingsByDevice[deviceKey]?[signature]
        let timestampNs = MonotonicClock.nanoseconds(fromMachAbsolute: timestamp)
        lastInputDeviceKeyStorage = deviceKey

        if let learningCallback {
            let event = LearnedHIDEvent(
                usagePage: page,
                usage: usage,
                timestampNs: timestampNs,
                valueDirection: direction,
                deviceKey: deviceKey
            )
            DispatchQueue.main.async { learningCallback(event) }
        }

        guard isButtonMappingActive, let binding, binding.key.isIntercepted else { return }
        // The Razer wheel tilt is a vendor pan field that macOS never turns
        // into a scroll CGEvent, so there is nothing to correlate against and
        // nothing to suppress — fire the mapped action directly on the HID
        // pulse. (For a standard AC-Pan mouse a real scroll event would exist;
        // that codec path is not used here.)
        ButtonMapper.shared.handle(buttonIndex: binding.buttonIndex, deviceKey: deviceKey)
    }

    /// Returns nil when the set provides no routing evidence. If a malformed
    /// report contains multiple side-key sources with conflicting switches,
    /// interception wins: leaking an enabled original shortcut is the less
    /// recoverable failure mode.
    private func keyboardInterceptionRoute(deviceKey: String, for usages: Set<UInt32>) -> Bool? {
        guard !usages.isEmpty else { return nil }
        let table = bindingsByDevice[deviceKey]
        let decisions = Set(usages.map { usage -> Bool in
            table?[HIDUsageSignature(page: 0x07, usage: usage)]?.key.requiresRuntimeInterception ?? false
        })
        return decisions == [false] ? false : true
    }

    /// A normal source must be explicitly learned and enabled. Modifier HID
    /// usages are the sole exception: they have no independent binding and
    /// follow the route selected by the main key in the same mouse report.
    static func shouldCreateRuntimeToken(
        page: UInt32,
        usage: UInt32,
        hasBinding: Bool,
        bindingIntercepted: Bool,
        interceptionOverride: Bool?
    ) -> Bool {
        if page == 0x07 && HIDUsageKeyCodeMap.isModifier(usage) {
            return interceptionOverride == true
        }
        return hasBinding && bindingIntercepted
    }

    private func onQueueSync<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return operation() }
        return queue.sync(execute: operation)
    }

    /// The connected flag must include manually selected standard-HID devices:
    /// recomputing it from supportedDevices alone told InputCoordinator that a
    /// freshly selected Logitech-class device was "disconnected" and tore the
    /// mapping pipeline right back down.
    private func notifyDeviceStateChanged(connected: Bool) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.deviceStateDidChangeNotification,
                object: self,
                userInfo: ["connected": connected]
            )
        }
    }

    private func notifyCandidateStateChanged() {
        let summaries = candidateRecords.values.map(\.summary)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.candidateStateDidChangeNotification,
                object: self,
                userInfo: ["candidates": summaries]
            )
        }
    }

    private static func identity(for device: IOHIDDevice) -> HIDDeviceIdentity {
        HIDDeviceIdentity(
            vendorID: integerProperty(device, key: kIOHIDVendorIDKey) ?? -1,
            productID: integerProperty(device, key: kIOHIDProductIDKey) ?? -1,
            product: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "",
            serialNumber: IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? "",
            descriptor: IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data ?? Data(),
            maximumInputReportSize: integerProperty(device, key: kIOHIDMaxInputReportSizeKey) ?? 0,
            transport: IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "",
            locationID: integerProperty(device, key: kIOHIDLocationIDKey) ?? 0,
            primaryUsagePage: integerProperty(device, key: kIOHIDPrimaryUsagePageKey) ?? 0,
            primaryUsage: integerProperty(device, key: kIOHIDPrimaryUsageKey) ?? 0,
            isBuiltIn: (IOHIDDeviceGetProperty(device, "Built-In" as CFString) as? Bool) ?? false
        )
    }

    private static func integerProperty(_ device: IOHIDDevice, key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private static let deviceMatchedCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<HIDListener>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
    }

    private static let deviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<HIDListener>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
    }

    private static let reportCallback: IOHIDReportWithTimeStampCallback = {
        context, result, sender, _, reportID, report, reportLength, timestamp in
        guard let context, let sender else { return }
        let device = unsafeBitCast(sender, to: IOHIDDevice.self)
        Unmanaged<HIDListener>.fromOpaque(context).takeUnretainedValue().handleReport(
            device: device,
            result: result,
            reportID: reportID,
            report: report,
            length: Int(reportLength),
            timestamp: timestamp
        )
    }

    private static let inputValueCallback: IOHIDValueCallback = { context, result, _, value in
        guard result == kIOReturnSuccess, let context else { return }
        Unmanaged<HIDListener>.fromOpaque(context).takeUnretainedValue().handleStandardValue(value)
    }

}
