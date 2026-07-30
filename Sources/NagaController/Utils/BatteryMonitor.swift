import Foundation
import CoreBluetooth

final class BatteryMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BatteryMonitor()
    static let didUpdateNotification = Notification.Name("BatteryMonitor.didUpdateBattery")

    private let queue = DispatchQueue(label: "BatteryMonitor.queue")
    private var central: CBCentralManager!
    private var target: CBPeripheral?
    private var batteryCharacteristic: CBCharacteristic?
    private var retryWorkItem: DispatchWorkItem?
    private var scanBackoffWorkItem: DispatchWorkItem?

    // Latest battery percentage 0-100
    private(set) var batteryLevel: Int? {
        didSet {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: BatteryMonitor.didUpdateNotification, object: self)
            }
        }
    }

    // Heuristic to pick the right device when multiple peripherals expose 0x180F
    private let preferredNameSubstrings = ["naga", "razer"]

    private override init() {
        super.init()
        // Create central on our private queue; delegate callbacks will arrive on that queue
        central = CBCentralManager(delegate: self, queue: queue)
        NSLog("[BLE] BatteryMonitor initialized")
    }

    func start() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.central.state == .poweredOn {
                self.startScan()
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let t = self.target {
                self.central.cancelPeripheralConnection(t)
            }
            self.cancelScanBackoff()
            self.central.stopScan()
            self.target = nil
            self.batteryCharacteristic = nil
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        NSLog("[BLE] Central state updated: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            // First, try to grab an already-connected Razer/Naga peripheral
            // exposing Battery Service. Never fall back to an arbitrary
            // device: headsets and keyboards expose 0x180F too, and adopting
            // one would display the wrong battery level.
            let batteryService = CBUUID(string: "180F")
            let connected = central.retrieveConnectedPeripherals(withServices: [batteryService])
            if let preferred = connected.first(where: { peripheral in
                let lower = (peripheral.name ?? "").lowercased()
                return preferredNameSubstrings.contains(where: lower.contains)
            }) {
                NSLog("[BLE] Found connected peripheral with Battery Service: \(preferred.name ?? "<unnamed>") — using it")
                target = preferred
                target?.delegate = self
                // Always request a (re)connect to ensure callbacks flow through this central
                NSLog("[BLE] Ensuring connection to retrieved peripheral (state=\(preferred.state.rawValue))…")
                central.connect(preferred, options: nil)
                scheduleDiscoveryRetry(for: preferred)
            } else {
                startScan()
            }
        default:
            // Clear state if BT turned off, etc.
            target = nil
            batteryCharacteristic = nil
            batteryLevel = nil
        }
    }

    private func startScan() {
        guard central.state == .poweredOn else { return }
        // Broad scan: some devices do not advertise 0x180F but still expose it after connection
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        NSLog("[BLE] Scanning for peripherals (broad scan)…")
        scheduleScanBackoff()
    }

    /// A broad scan is battery-hungry. If nothing matching is found within a
    /// minute, pause scanning and retry every five minutes instead of
    /// scanning forever.
    private func scheduleScanBackoff() {
        scanBackoffWorkItem?.cancel()
        let pause = DispatchWorkItem { [weak self] in
            guard let self, self.target == nil else { return }
            NSLog("[BLE] No matching peripheral after 60s — pausing scan for 5 minutes")
            self.central.stopScan()
            let resume = DispatchWorkItem { [weak self] in
                guard let self, self.target == nil else { return }
                self.startScan()
            }
            self.scanBackoffWorkItem = resume
            self.queue.asyncAfter(deadline: .now() + 300, execute: resume)
        }
        scanBackoffWorkItem = pause
        queue.asyncAfter(deadline: .now() + 60, execute: pause)
    }

    private func cancelScanBackoff() {
        scanBackoffWorkItem?.cancel()
        scanBackoffWorkItem = nil
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Prefer devices whose name mentions Naga/Razer, or which advertise the Battery Service
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let lower = name.lowercased()
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        // Advertising Battery Service alone is NOT enough to be a candidate:
        // headsets and keyboards expose 0x180F too. Only a Razer/Naga name
        // qualifies; anything else keeps the scan running.
        let isPreferred = preferredNameSubstrings.contains(where: { lower.contains($0) })
        if !services.isEmpty {
            NSLog("[BLE] Adv services for '\(name)': \(services.map{ $0.uuidString }.joined(separator: ", "))) ")
        }

        // If we don't have a target yet, or we found a preferred match, select and connect
        if target == nil && isPreferred {
            NSLog("[BLE] Discovered peripheral: name='\(name)', RSSI=\(RSSI). Preferred=\(isPreferred)")
            target = peripheral
            target?.delegate = self
            cancelScanBackoff()
            central.stopScan()
            central.connect(peripheral, options: nil)
            NSLog("[BLE] Connecting to '" + name + "'…")
        } else {
            if !isPreferred {
                NSLog("[BLE] Skipping non-preferred peripheral: '\(name)'")
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        NSLog("[BLE] Connected to peripheral: \(peripheral.name ?? "<unnamed>")")
        let batteryService = CBUUID(string: "180F")
        peripheral.delegate = self
        peripheral.discoverServices([batteryService])
        scheduleDiscoveryRetry(for: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // Retry scan on failure
        self.target = nil
        self.batteryCharacteristic = nil
        NSLog("[BLE] Failed to connect: \(error?.localizedDescription ?? "<no error>")")
        startScan()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral == target {
            target = nil
            batteryCharacteristic = nil
            batteryLevel = nil
            NSLog("[BLE] Disconnected: \(error?.localizedDescription ?? "<no error>") — restarting scan")
            cancelRetry()
            startScan()
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { NSLog("[BLE] didDiscoverServices error: \(error!.localizedDescription)"); return }
        let batteryServiceUUID = CBUUID(string: "180F")
        let batteryLevelUUID = CBUUID(string: "2A19")
        if let services = peripheral.services, !services.isEmpty {
            NSLog("[BLE] Discovered services: \(services.map{ $0.uuid.uuidString }.joined(separator: ", "))")
        }
        if let service = peripheral.services?.first(where: { $0.uuid == batteryServiceUUID }) {
            NSLog("[BLE] Battery service found — discovering characteristics (0x2A19)")
            peripheral.discoverCharacteristics([batteryLevelUUID], for: service)
        } else {
            NSLog("[BLE] Battery service (0x180F) not found on this peripheral")
            // Not our target — disconnect and resume scanning
            if peripheral == target {
                target = nil
            }
            // Fallback: try a full service discovery once before giving up
            if peripheral.services == nil || peripheral.services?.isEmpty == true {
                NSLog("[BLE] Trying full service discovery before disconnect…")
                peripheral.discoverServices(nil)
                scheduleDiscoveryRetry(for: peripheral)
            } else {
                self.central.cancelPeripheralConnection(peripheral)
                startScan()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { NSLog("[BLE] didDiscoverCharacteristics error: \(error!.localizedDescription)"); return }
        let batteryLevelUUID = CBUUID(string: "2A19")
        if let chars = service.characteristics, !chars.isEmpty {
            NSLog("[BLE] Discovered chars for service \(service.uuid.uuidString): \(chars.map{ $0.uuid.uuidString }.joined(separator: ", "))")
        }
        if let ch = service.characteristics?.first(where: { $0.uuid == batteryLevelUUID }) {
            batteryCharacteristic = ch
            peripheral.readValue(for: ch)
            NSLog("[BLE] Reading Battery Level (0x2A19)…")
            if ch.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: ch)
                NSLog("[BLE] Subscribed to Battery Level notifications")
            }
            cancelRetry()
        } else {
            NSLog("[BLE] Battery Level characteristic (0x2A19) not found — trying to discover all characteristics")
            peripheral.discoverCharacteristics(nil, for: service)
            scheduleDiscoveryRetry(for: peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { NSLog("[BLE] didUpdateValue error: \(error!.localizedDescription)"); return }
        if characteristic.uuid == CBUUID(string: "2A19"), let data = characteristic.value, let first = data.first {
            let percent = Int(first)
            batteryLevel = max(0, min(100, percent))
            NSLog("[BLE] Battery Level updated: \(batteryLevel ?? -1)%")
            cancelRetry()
        }
    }

    // MARK: - Retry logic
    private func scheduleDiscoveryRetry(for peripheral: CBPeripheral) {
        cancelRetry()
        let item = DispatchWorkItem { [weak self, weak peripheral] in
            guard let self = self, let p = peripheral else { return }
            if self.batteryLevel == nil && self.batteryCharacteristic == nil {
                NSLog("[BLE] Discovery timeout — retrying service discovery or reconnect")
                let batteryService = CBUUID(string: "180F")
                if p.state == .connected {
                    p.discoverServices([batteryService])
                } else if let t = self.target {
                    self.central.connect(t, options: nil)
                } else {
                    self.startScan()
                }
            }
        }
        retryWorkItem = item
        queue.asyncAfter(deadline: .now() + 5, execute: item)
    }

    private func cancelRetry() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
    }
}
