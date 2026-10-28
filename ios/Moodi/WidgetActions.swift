import AppIntents
import WidgetKit

@available(iOS 17.0, *)
struct AdjustThresholdIntent: AppIntent {
    static var title: LocalizedStringResource = "Adjust Moodi threshold"
    static var openAppWhenRun = false

    @Parameter(title: "Threshold") var field: String
    @Parameter(title: "Change") var delta: Int

    init() {}
    init(field: String, delta: Int) {
        self.field = field
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        guard SharedSettings.adjust(field, by: delta) else { return .result() }
        await sendThresholds()
        return .result()
    }
}

@available(iOS 17.0, *)
struct ConnectMoodiIntent: AppIntent {
    static var title: LocalizedStringResource = "Connect to CalmPulse"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        SharedSettings.markWidgetResult("sending")
        if SharedSettings.defaults.bool(forKey: SharedSettings.pendingKey) {
            await sendThresholds()
        } else {
            do {
                let status = try await WidgetBLEClient.run(.readStatus)
                SharedSettings.defaults.set(status.startBpm, forKey: SharedSettings.startKey)
                SharedSettings.defaults.set(status.stopBpm, forKey: SharedSettings.stopKey)
                SharedSettings.markWidgetResult("ready")
            } catch {
                SharedSettings.markWidgetResult("unavailable", message: error.localizedDescription)
            }
            WidgetCenter.shared.reloadTimelines(ofKind: "MoodiControlsWidget")
        }
        return .result()
    }
}

@available(iOS 17.0, *)
private func sendThresholds() async {
    let start = SharedSettings.start
    let stop = SharedSettings.stop
    let revision = SharedSettings.defaults.integer(forKey: SharedSettings.revisionKey)
    do {
        let status = try await WidgetBLEClient.run(.setThresholds(start, stop))
        guard status.startBpm == start && status.stopBpm == stop else {
            SharedSettings.markWidgetResult("unavailable", message: "Wearable did not confirm thresholds")
            WidgetCenter.shared.reloadTimelines(ofKind: "MoodiControlsWidget")
            return
        }
        if SharedSettings.defaults.integer(forKey: SharedSettings.revisionKey) == revision {
            SharedSettings.defaults.set(false, forKey: SharedSettings.pendingKey)
            SharedSettings.markWidgetResult("ready")
        }
    } catch {
        SharedSettings.markWidgetResult("unavailable", message: error.localizedDescription)
    }
    WidgetCenter.shared.reloadTimelines(ofKind: "MoodiControlsWidget")
}
