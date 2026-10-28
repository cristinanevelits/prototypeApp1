import CoreBluetooth
import Foundation

/// A short, one-shot BLE exchange for a widget tap. It does not maintain a connection.
@available(iOS 17.0, *)
// Delegate callbacks and mutable state are confined to the main queue.
final class WidgetBLEClient: NSObject, @unchecked Sendable {
    enum Action {
        case readStatus
        case setThresholds(Int, Int)
    }

    enum ConnectionError: LocalizedError {
        case bluetoothOff, notFound, noControls, badStatus, rejected(String), timedOut

        var errorDescription: String? {
            switch self {
            case .bluetoothOff: "Turn on Bluetooth"
            case .notFound: "CalmPulse not found"
            case .noControls: "CalmPulse controls unavailable"
            case .badStatus: "Could not verify wearable settings"
            case .rejected(let message): "Wearable rejected change: \(message)"
            case .timedOut: "CalmPulse did not respond"
            }
        }
    }

    private let action: Action
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var control: CBCharacteristic?
    private var status: CBCharacteristic?
    private var continuation: CheckedContinuation<DeviceStatus, Error>?
    private var timeout: DispatchWorkItem?
    private var writeCompleted = false
    private var readAttempts = 0
    private var finished = false

    private init(action: Action) { self.action = action }

    static func run(_ action: Action) async throws -> DeviceStatus {
        let client = WidgetBLEClient(action: action)
        let result = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                client.continuation = continuation
                client.start()
            }
        }
        withExtendedLifetime(client) {}
        return result
    }

    private func start() {
        let work = DispatchWorkItem { [weak self] in self?.finish(.failure(ConnectionError.timedOut)) }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    private func findDevice() {
        let controlled = central.retrieveConnectedPeripherals(withServices: [MoodiProtocol.service])
        let heart = central.retrieveConnectedPeripherals(withServices: [MoodiProtocol.heartService])
        if let match = controlled.first ?? heart.first(where: { $0.name?.lowercased() == "calmpulse" }) {
            connect(match)
        } else {
            central.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    private func connect(_ device: CBPeripheral) {
        central.stopScan()
        peripheral = device
        device.delegate = self
        central.connect(device, options: nil)
    }

    private func readyToExchange() {
        guard let peripheral, let status else { return }
        switch action {
        case .readStatus:
            peripheral.readValue(for: status)
        case .setThresholds(let start, let stop):
            guard let control,
                  let data = try? JSONSerialization.data(withJSONObject: ["start": start, "stop": stop]) else {
                finish(.failure(ConnectionError.noControls))
                return
            }
            peripheral.setNotifyValue(true, for: status)
            peripheral.writeValue(data, for: control, type: .withResponse)
        }
    }

    private func finish(_ result: Result<DeviceStatus, Error>) {
        guard !finished else { return }
        finished = true
        timeout?.cancel()
        if central?.isScanning == true { central.stopScan() }
        if let peripheral, peripheral.state == .connected { central.cancelPeripheralConnection(peripheral) }
        continuation?.resume(with: result)
        continuation = nil
    }
}

@available(iOS 17.0, *)
extension WidgetBLEClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !finished else { return }
        if central.state == .poweredOn { findDevice() }
        else if central.state == .poweredOff || central.state == .unauthorized || central.state == .unsupported {
            finish(.failure(ConnectionError.bluetoothOff))
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover device: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? device.name ?? "").lowercased()
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard name == "calmpulse" || services.contains(MoodiProtocol.service) else { return }
        connect(device)
    }

    func centralManager(_ central: CBCentralManager, didConnect device: CBPeripheral) {
        device.discoverServices([MoodiProtocol.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect device: CBPeripheral, error: Error?) {
        finish(.failure(error ?? ConnectionError.notFound))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral device: CBPeripheral, error: Error?) {
        if !finished { finish(.failure(error ?? ConnectionError.notFound)) }
    }
}

@available(iOS 17.0, *)
extension WidgetBLEClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == MoodiProtocol.service }) else {
            finish(.failure(error ?? ConnectionError.noControls))
            return
        }
        peripheral.discoverCharacteristics([MoodiProtocol.control, MoodiProtocol.status], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { finish(.failure(error!)); return }
        control = service.characteristics?.first(where: { $0.uuid == MoodiProtocol.control })
        status = service.characteristics?.first(where: { $0.uuid == MoodiProtocol.status })
        guard status != nil else { finish(.failure(ConnectionError.noControls)); return }
        readyToExchange()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == MoodiProtocol.control else { return }
        if let error { finish(.failure(error)); return }
        writeCompleted = true
        if let status { peripheral.readValue(for: status) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == MoodiProtocol.status else { return }
        if let error { finish(.failure(error)); return }
        guard let data = characteristic.value, let parsed = DeviceStatus(data: data) else {
            finish(.failure(ConnectionError.badStatus)); return
        }
        switch action {
        case .readStatus:
            finish(.success(parsed))
        case .setThresholds(let start, let stop):
            guard writeCompleted else { return }
            if !parsed.error.isEmpty { finish(.failure(ConnectionError.rejected(parsed.error))) }
            else if parsed.startBpm == start && parsed.stopBpm == stop { finish(.success(parsed)) }
            else if readAttempts < 4 {
                readAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self, !self.finished, let status = self.status else { return }
                    peripheral.readValue(for: status)
                }
            } else { finish(.failure(ConnectionError.badStatus)) }
        }
    }
}
