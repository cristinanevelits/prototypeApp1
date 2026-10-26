import CoreBluetooth
import Combine
import Foundation

final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var connection = "Bluetooth starting…"
    @Published private(set) var bpm: Int?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var status: DeviceStatus?
    @Published private(set) var minuteSamples: [MinuteSample] = []
    @Published private(set) var lastCommandError: String?
    @Published private(set) var lastDisconnectReason: String?
    @Published private(set) var controlsReady = false

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?
    private var foundHeartMeasurement = false
    private var foundStatus = false
    private var hasControlService = false
    private var scanTimeout: DispatchWorkItem?
    private var reconnectTask: DispatchWorkItem?
    private var wantsConnection = false
    private var shortDisconnects = 0
    private var connectedAt: Date?
    private var pendingWrites: [Data] = []
    private var writeInFlight = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var connected: Bool { peripheral?.state == .connected }

    func connect() {
        wantsConnection = true
        reconnectTask?.cancel()
        reconnectTask = nil
        guard central.state == .poweredOn else {
            connection = "Turn on Bluetooth to connect"
            return
        }
        guard !connected else { return }
        stopScanning()
        // A device already connected in iOS Settings may no longer advertise.
        let controlConnected = central.retrieveConnectedPeripherals(withServices: [MoodiProtocol.service])
        let heartConnected = central.retrieveConnectedPeripherals(withServices: [MoodiProtocol.heartService])
        if let match = controlConnected.first ?? heartConnected.first(where: { isMoodi($0, advertisementData: nil) }) {
            connect(to: match)
            return
        }
        connection = "Searching for CalmPulse…"
        // CalmPulse advertises the standard Heart Rate service, not the custom one.
        // Scan without a service filter, but connect only to a known device name or
        // one advertising Moodi's unique service UUID.
        central.scanForPeripherals(withServices: nil, options: nil)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.central.isScanning else { return }
            self.central.stopScan()
            self.connection = "No CalmPulse found — check XIAO power and Bluetooth, then retry"
        }
        scanTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
    }

    func disconnect() {
        wantsConnection = false
        lastDisconnectReason = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        stopScanning()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        else { connection = "Disconnected — tap Connect" }
    }

    func setMode(_ mode: String) {
        guard ["auto", "on", "off"].contains(mode) else { return }
        sendJSON(["mode": mode])
    }
    func setThresholds(start: Int, stop: Int) {
        guard (41...220).contains(start), (40..<start).contains(stop) else { return }
        sendJSON(["start": start, "stop": stop])
    }
    private func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object), data.count <= 128 else { return }
        send(data)
    }

    private func send(_ data: Data) {
        guard controlsReady, let peripheral, controlCharacteristic != nil, peripheral.state == .connected else {
            lastCommandError = "Device controls are unavailable until connected."
            return
        }
        lastCommandError = nil
        pendingWrites.append(data)
        sendNext()
    }

    private func sendNext() {
        guard !writeInFlight, !pendingWrites.isEmpty,
              let peripheral, let controlCharacteristic, peripheral.state == .connected else { return }
        writeInFlight = true
        peripheral.writeValue(pendingWrites[0], for: controlCharacteristic, type: .withResponse)
    }

    private func clearReading() {
        bpm = nil
        lastUpdate = nil
        status = nil
        controlCharacteristic = nil
        foundHeartMeasurement = false
        foundStatus = false
        hasControlService = false
        controlsReady = false
        pendingWrites.removeAll()
        writeInFlight = false
    }

    private func isMoodi(_ peripheral: CBPeripheral, advertisementData: [String: Any]?) -> Bool {
        let advertisedName = advertisementData?[CBAdvertisementDataLocalNameKey] as? String
        let name = (advertisedName ?? peripheral.name ?? "").lowercased()
        if name == "calmpulse" || name == "moodi" { return true }
        let services = advertisementData?[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        return services.contains(MoodiProtocol.service)
    }

    private func connect(to peripheral: CBPeripheral) {
        reconnectTask?.cancel()
        reconnectTask = nil
        stopScanning()
        clearReading()
        self.peripheral = peripheral
        peripheral.delegate = self
        connection = "Connecting to \(peripheral.name ?? "CalmPulse")…"
        central.connect(peripheral, options: nil)
    }

    private func stopScanning() {
        scanTimeout?.cancel()
        scanTimeout = nil
        if central.isScanning { central.stopScan() }
    }

    private func reconnect(to device: CBPeripheral, reason: String) {
        guard wantsConnection else { return }
        lastDisconnectReason = reason
        shortDisconnects = min(shortDisconnects + 1, 5)
        let seconds = min(1 << shortDisconnects, 30)
        connection = "Connection dropped (\(reason)); retrying in \(seconds)s…"
        reconnectTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.wantsConnection, self.central.state == .poweredOn else { return }
            self.connect(to: device)
        }
        reconnectTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: task)
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connection = "Ready to connect"
            if wantsConnection && !connected { connect() }
        case .poweredOff:
            stopScanning()
            clearReading()
            connection = "Bluetooth is off"
        case .unauthorized:
            stopScanning()
            clearReading()
            connection = "Bluetooth permission needed"
        default:
            stopScanning()
            clearReading()
            connection = "Bluetooth unavailable"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isMoodi(peripheral, advertisementData: advertisementData) else { return }
        connect(to: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedAt = Date()
        connection = "Connected · discovering services"
        peripheral.discoverServices([MoodiProtocol.heartService, MoodiProtocol.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        clearReading()
        if wantsConnection {
            reconnect(to: peripheral, reason: error?.localizedDescription ?? "could not connect")
        } else {
            connection = "Disconnected — tap Connect"
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let connectedAt, Date().timeIntervalSince(connectedAt) > 30 {
            shortDisconnects = 0
            lastDisconnectReason = nil
        }
        connectedAt = nil
        self.peripheral = nil
        clearReading()
        if wantsConnection {
            reconnect(to: peripheral, reason: error?.localizedDescription ?? "device disconnected")
        } else {
            connection = "Disconnected — tap Connect"
        }
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            connection = "Could not discover services"
            return
        }
        guard services.contains(where: { $0.uuid == MoodiProtocol.heartService }) else {
            connection = "Device has no Heart Rate service (180D)"
            central.cancelPeripheralConnection(peripheral)
            return
        }
        hasControlService = services.contains(where: { $0.uuid == MoodiProtocol.service })
        connection = hasControlService ? "Connected · discovering CalmPulse controls" : "Connected · pulse only (different firmware)"
        for service in services {
            if service.uuid == MoodiProtocol.heartService {
                peripheral.discoverCharacteristics([MoodiProtocol.heartMeasurement], for: service)
            } else if service.uuid == MoodiProtocol.service {
                peripheral.discoverCharacteristics([MoodiProtocol.status, MoodiProtocol.control], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            connection = "Could not discover \(service.uuid == MoodiProtocol.heartService ? "heart rate" : "device controls")"
            return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == MoodiProtocol.heartMeasurement || characteristic.uuid == MoodiProtocol.status {
                if characteristic.uuid == MoodiProtocol.heartMeasurement { foundHeartMeasurement = true }
                if characteristic.uuid == MoodiProtocol.status { foundStatus = true }
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            } else if characteristic.uuid == MoodiProtocol.control {
                controlCharacteristic = characteristic
            }
        }
        if foundHeartMeasurement && foundStatus && controlCharacteristic != nil {
            controlsReady = true
            connection = "Connected"
        } else if foundHeartMeasurement && !hasControlService {
            connection = "Connected · pulse only (CalmPulse controls unavailable)"
        } else if service.uuid == MoodiProtocol.heartService && !foundHeartMeasurement {
            connection = "Connected device has no heart-rate measurement (2A37)"
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        if characteristic.uuid == MoodiProtocol.heartMeasurement,
           let measurement = HeartMeasurement(data: data) {
            bpm = measurement.bpm
            lastUpdate = Date()
            if let bpm, minuteSamples.last.map({ Date().timeIntervalSince($0.date) >= 60 }) ?? true {
                minuteSamples.append(MinuteSample(date: Date(), bpm: bpm))
                if minuteSamples.count > 60 { minuteSamples.removeFirst() }
            }
        } else if characteristic.uuid == MoodiProtocol.status {
            if let parsed = DeviceStatus(data: data) {
                status = parsed
                lastCommandError = parsed.error.isEmpty ? nil : "Wearable rejected command: \(parsed.error)"
            } else {
                lastCommandError = "Could not read CalmPulse control status."
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, characteristic.uuid == MoodiProtocol.control else { return }
        if let error {
            lastCommandError = "Setting was not sent: \(error.localizedDescription)"
            pendingWrites.removeAll()
            writeInFlight = false
            return
        }
        if !pendingWrites.isEmpty { pendingWrites.removeFirst() }
        writeInFlight = false
        // Let the XIAO's main loop consume this command before the next write.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.sendNext() }
    }
}

