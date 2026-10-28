import Foundation

enum SharedSettings {
    static let suiteName = "group.studio.rehm.moodi.prototype"
    static let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    static let startKey = "moodi.startThreshold"
    static let stopKey = "moodi.stopThreshold"
    static let pendingKey = "moodi.thresholdPending"
    static let modeKey = "calmpulse.mode"
    static let modePendingKey = "moodi.modePending"
    static let revisionKey = "moodi.widgetRevision"
    static let widgetStateKey = "moodi.widgetState"
    static let widgetMessageKey = "moodi.widgetMessage"

    static func migrateFromAppDefaults() {
        let old = UserDefaults.standard
        for key in [startKey, stopKey, pendingKey, modeKey] where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    static var start: Int { defaults.object(forKey: startKey) as? Int ?? 100 }
    static var stop: Int { defaults.object(forKey: stopKey) as? Int ?? 90 }
    static var vibrationOn: Bool { (defaults.string(forKey: modeKey) ?? "auto") != "off" }

    @discardableResult
    static func adjust(_ field: String, by delta: Int) -> Bool {
        let start = self.start
        let stop = self.stop
        if field == "start" {
            let next = start + delta
            guard (41...220).contains(next), next > stop else { return false }
            defaults.set(next, forKey: startKey)
        } else if field == "stop" {
            let next = stop + delta
            guard (40..<start).contains(next) else { return false }
            defaults.set(next, forKey: stopKey)
        } else { return false }
        defaults.set(true, forKey: pendingKey)
        defaults.set("sending", forKey: widgetStateKey)
        defaults.set("", forKey: widgetMessageKey)
        defaults.set(defaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
        return true
    }

    static func markWidgetResult(_ status: String, message: String = "") {
        defaults.set(status, forKey: widgetStateKey)
        defaults.set(message, forKey: widgetMessageKey)
    }

    static func toggleVibration() {
        defaults.set(vibrationOn ? "off" : "auto", forKey: modeKey)
        defaults.set(true, forKey: modePendingKey)
        defaults.set(defaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}
