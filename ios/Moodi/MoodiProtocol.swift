import CoreBluetooth
import Foundation

enum MoodiProtocol {
    static let heartService = CBUUID(string: "180D")
    static let heartMeasurement = CBUUID(string: "2A37")
    static let service = CBUUID(string: "8F941100-B6B1-4F96-9F4D-356DB1FE7A10")
    static let status = CBUUID(string: "8F941101-B6B1-4F96-9F4D-356DB1FE7A10")
    static let control = CBUUID(string: "8F941102-B6B1-4F96-9F4D-356DB1FE7A10")
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
    let valid: Bool
    let vibrating: Bool
    let automatic: Bool
    let workoutOverride: Bool
    let sensorFound: Bool
    let driverFound: Bool
    let motorApproved: Bool
    let startBpm: Int
    let stopBpm: Int

    init?(data: Data) {
        guard data.count == 5, data[0] == 1 else { return nil }
        let flags = data[1]
        valid = flags & 1 != 0
        vibrating = flags & 2 != 0
        automatic = flags & 4 != 0
        workoutOverride = flags & 8 != 0
        sensorFound = flags & 16 != 0
        driverFound = flags & 32 != 0
        motorApproved = flags & 64 != 0
        startBpm = Int(data[3])
        stopBpm = Int(data[4])
    }
}

struct MinuteSample: Identifiable {
    let id = UUID()
    let date: Date
    let bpm: Int
}

