import CoreBluetooth
import Foundation

enum MoodiProtocol {
    static let heartService = CBUUID(string: "180D")
    static let heartMeasurement = CBUUID(string: "2A37")
    static let service = CBUUID(string: "8A7E1000-6F34-4C9A-9F30-2B739074F001")
    static let control = CBUUID(string: "8A7E1001-6F34-4C9A-9F30-2B739074F001")
    static let status = CBUUID(string: "8A7E1002-6F34-4C9A-9F30-2B739074F001")
}

struct HeartMeasurement {
    let bpm: Int?
    let contactDetected: Bool

    init?(data: Data) {
        guard data.count >= 2 else { return nil }
        let flags = data[0]
        let is16Bit = flags & 0x01 != 0
        guard data.count >= (is16Bit ? 3 : 2) else { return nil }
        let value = is16Bit ? Int(data[1]) | Int(data[2]) << 8 : Int(data[1])
        contactDetected = flags & 0x06 == 0x06
        bpm = contactDetected && value > 0 ? value : nil
    }
}

struct DeviceStatus {
    let sequence: Int
    let active: Bool
    let mode: String
    let driverFound: Bool
    let contactDetected: Bool?
    let readingValid: Bool?
    let remainingSeconds: Int
    let error: String
    let startBpm: Int
    let stopBpm: Int

    init?(data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sequence = object["seq"] as? Int,
              let start = object["start"] as? Int,
              let stop = object["stop"] as? Int,
              let mode = object["mode"] as? String,
              ["auto", "on", "off"].contains(mode),
              let active = object["active"] as? Bool,
              let driver = object["driver"] as? Bool,
              let remaining = object["remaining"] as? Int,
              let error = object["error"] as? String else { return nil }
        self.sequence = sequence
        self.startBpm = start
        self.stopBpm = stop
        self.mode = mode
        self.active = active
        self.driverFound = driver
        self.contactDetected = object["contact"] as? Bool
        self.readingValid = object["valid"] as? Bool
        self.remainingSeconds = remaining
        self.error = error
    }
}

struct MinuteSample: Identifiable {
    let id = UUID()
    let date: Date
    let bpm: Int
}

