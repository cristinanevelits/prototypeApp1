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
    @Published private(set) var controlsReady = false

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?
    private var foundHeartMeasurement = false
    private var foundStatus = false
    private var hasMoodiService = false
    private var scanTimeout: DispatchWorkItem?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var connected: Bool { peripheral?.state == .connected }

    func connect() {
        guard central.state == .poweredOn else {
            connection = "Turn on Bluetooth to connect"
            return
        }
        guard !connected else { return }
        stopScanning()
        // A device already connected in iOS Settings may no longer advertise.
        let moodiConnected = central.retrieveConnectedPeripherals(withServices: [MoodiProtocol.service])
        let heartConnected = central.retrieveConnectedPeripherals(withServices: [MoodiProtocol.heartService])
        if let match = moodiConnected.first ?? heartConnected.first(where: { isMoodi($0, advertisementData: nil) }) {
            connect(to: match)
            return
        }
        connection = "Searching for moodi…"
        // Older CalmPulse firmware advertises only the standard Heart Rate service.
        // Scan without a service filter, but connect only to a known device name or
        // one advertising Moodi's unique service UUID.
        central.scanForPeripherals(withServices: nil, options: nil)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.central.isScanning else { return }
            self.central.stopScan()
            self.connection = "No moodi found — check XIAO power and Bluetooth, then retry"
        }
        scanTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
    }

    func disconnect() {
        stopScanning()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        else { connection = "Disconnected — tap Connect" }
    }

    func setAutomatic(_ enabled: Bool) { send([1, enabled ? 1 : 0]) }
    func setWorkoutOverride(_ enabled: Bool) { send([2, enabled ? 1 : 0]) }
    func setThresholds(start: Int, stop: Int) {
        guard (50...200).contains(start), (40..<start).contains(stop) else { return }
        send([3, UInt8(start), UInt8(stop)])
    }
    func stopNow() { send([4]) }

    private func send(_ bytes: [UInt8]) {
        guard controlsReady, let peripheral, let controlCharacteristic, peripheral.state == .connected else {
            lastCommandError = "Device controls are unavailable until connected."
            return
        }
        lastCommandError = nil
        peripheral.writeValue(Data(bytes), for: controlCharacteristic, type: .withResponse)
    }

    private func clearReading() {
        bpm = nil
        lastUpdate = nil
        status = nil
        controlCharacteristic = nil
        foundHeartMeasurement = false
        foundStatus = false
        hasMoodiService = false
        controlsReady = false
    }

    private func isMoodi(_ peripheral: CBPeripheral, advertisementData: [String: Any]?) -> Bool {
        let advertisedName = advertisementData?[CBAdvertisementDataLocalNameKey] as? String
        let name = (advertisedName ?? peripheral.name ?? "").lowercased()
        if name == "moodi" || name == "calmpulse" { return true }
        let services = advertisementData?[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        return services.contains(MoodiProtocol.service)
    }

    private func connect(to peripheral: CBPeripheral) {
        stopScanning()
        clearReading()
        self.peripheral = peripheral
        peripheral.delegate = self
        connection = "Connecting to \(peripheral.name ?? "moodi")…"
        central.connect(peripheral, options: nil)
    }

    private func stopScanning() {
        scanTimeout?.cancel()
        scanTimeout = nil
        if central.isScanning { central.stopScan() }
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: connection = "Ready to connect"
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
        connection = "Connected · discovering services"
        peripheral.discoverServices([MoodiProtocol.heartService, MoodiProtocol.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connection = "Connection failed: \(error?.localizedDescription ?? "retry")"
        self.peripheral = nil
        clearReading()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connection = "Disconnected — tap Connect"
        self.peripheral = nil
        clearReading()
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
        hasMoodiService = services.contains(where: { $0.uuid == MoodiProtocol.service })
        connection = hasMoodiService ? "Connected · discovering Moodi controls" : "Connected · pulse only (different firmware)"
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
        } else if foundHeartMeasurement && !hasMoodiService {
            connection = "Connected · pulse only (upload matching Moodi firmware for controls)"
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
            status = DeviceStatus(data: data)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { lastCommandError = "Setting was not sent: \(error.localizedDescription)" }
    }
}

