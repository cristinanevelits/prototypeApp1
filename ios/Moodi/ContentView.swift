import Charts
import SwiftUI
import WidgetKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var bluetooth = BLEManager()
    @StateObject private var health = HealthManager()
    @AppStorage("moodi.startThreshold", store: SharedSettings.defaults) private var startThreshold = 100
    @AppStorage("moodi.stopThreshold", store: SharedSettings.defaults) private var stopThreshold = 90
    @AppStorage("moodi.thresholdPending", store: SharedSettings.defaults) private var thresholdPending = false
    @State private var thresholdSend: DispatchWorkItem?
    @AppStorage("calmpulse.mode", store: SharedSettings.defaults) private var responseMode = "auto"
    @AppStorage("moodi.modePending", store: SharedSettings.defaults) private var modePending = false
    @State private var lastWidgetRevision = 0

    private let background = Color(red: 0.06, green: 0.07, blue: 0.10)
    private let card = Color(red: 0.12, green: 0.13, blue: 0.17)
    private let accent = Color(red: 0.84, green: 0.53, blue: 0.72)

    private var vibrationBinding: Binding<Bool> {
        Binding(get: { responseMode != "off" }, set: { enabled in
            let mode = enabled ? "auto" : "off"
            responseMode = mode
            modePending = true
            if bluetooth.controlsReady { bluetooth.setMode(mode) }
            refreshWidget()
        })
    }

    private func changeStart(by amount: Int) {
        let next = startThreshold + amount
        guard (41...220).contains(next), stopThreshold < next else { return }
        startThreshold = next
        scheduleThresholdSend()
        refreshWidget()
    }

    private func changeStop(by amount: Int) {
        let next = stopThreshold + amount
        guard (40..<startThreshold).contains(next) else { return }
        stopThreshold = next
        scheduleThresholdSend()
        refreshWidget()
    }

    private func scheduleThresholdSend() {
        thresholdPending = true
        thresholdSend?.cancel()
        let work = DispatchWorkItem {
            if bluetooth.controlsReady {
                bluetooth.setThresholds(start: startThreshold, stop: stopThreshold)
            }
        }
        thresholdSend = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func refreshWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "MoodiControlsWidget")
    }

    private func applyWidgetChanges() {
        let settings = SharedSettings.defaults
        let revision = settings.integer(forKey: SharedSettings.revisionKey)
        guard revision != lastWidgetRevision else { return }
        lastWidgetRevision = revision
        startThreshold = SharedSettings.start
        stopThreshold = SharedSettings.stop
        responseMode = SharedSettings.vibrationOn ? "auto" : "off"
        thresholdPending = settings.bool(forKey: SharedSettings.pendingKey)
        modePending = settings.bool(forKey: SharedSettings.modePendingKey)
        if bluetooth.controlsReady {
            if modePending { bluetooth.setMode(responseMode) }
            if thresholdPending { bluetooth.setThresholds(start: startThreshold, stop: stopThreshold) }
        }
        refreshWidget()
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let fresh = bluetooth.lastUpdate.map { timeline.date.timeIntervalSince($0) < 5 } ?? false
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("moodi").font(.system(size: 34, weight: .semibold, design: .rounded))
                            Text("A gentle pulse companion").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle().fill(bluetooth.connected ? .green : .gray)
                            .frame(width: 11, height: 11)
                            .accessibilityLabel(bluetooth.connected ? "Connected" : "Disconnected")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("LIVE HEART RATE").font(.caption.weight(.bold)).tracking(2).foregroundStyle(accent)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(fresh && bluetooth.bpm != nil ? "\(bluetooth.bpm!)" : "—")
                                .font(.system(size: 96, weight: .light, design: .rounded)).contentTransition(.numericText())
                            Text("BPM").font(.headline).foregroundStyle(.secondary)
                        }
                        Text(readingCaption(fresh: fresh)).font(.subheadline).foregroundStyle(.secondary)
                        if let status = bluetooth.status, status.active {
                            Label(status.remainingSeconds > 0 ? "Heartbeat response · at least \(status.remainingSeconds)s remaining" : "Gentle heartbeat response", systemImage: "waveform.path")
                                .foregroundStyle(accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24).background(card, in: RoundedRectangle(cornerRadius: 24))

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent pulse").font(.headline)
                            Spacer()
                            Text("one point / minute").font(.caption).foregroundStyle(.secondary)
                        }
                        if bluetooth.minuteSamples.count > 1 {
                            Chart(bluetooth.minuteSamples) { sample in
                                LineMark(x: .value("Time", sample.date), y: .value("BPM", sample.bpm))
                                    .foregroundStyle(accent).interpolationMethod(.catmullRom)
                                PointMark(x: .value("Time", sample.date), y: .value("BPM", sample.bpm))
                                    .foregroundStyle(accent)
                            }
                            .frame(height: 135)
                        } else {
                            Text("The minute-by-minute graph appears after two valid readings.")
                                .font(.subheadline).foregroundStyle(.secondary).frame(height: 100)
                        }
                    }
                    .padding(20).background(card, in: RoundedRectangle(cornerRadius: 22))

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Device").font(.headline)
                        Text(bluetooth.connection).font(.subheadline).foregroundStyle(.secondary)
                        if let reason = bluetooth.lastDisconnectReason {
                            Text("Last Bluetooth drop: \(reason)")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Button(bluetooth.connected ? "Disconnect" : "Connect to XIAO") {
                            bluetooth.connected ? bluetooth.disconnect() : bluetooth.connect()
                        }
                        .buttonStyle(.borderedProminent).tint(accent)
                        if let status = bluetooth.status, !status.driverFound {
                            Label("Motor driver not detected by the XIAO", systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        if let error = bluetooth.lastCommandError {
                            Text(error).font(.footnote).foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20).background(card, in: RoundedRectangle(cornerRadius: 22))

                    VStack(alignment: .leading, spacing: 17) {
                        Text("Response settings").font(.headline)
                        Toggle("Vibration on/off", isOn: vibrationBinding)
                            .tint(accent)
                        Text("On allows the automatic heartbeat response above your BPM threshold. Off stops it immediately. This switch never selects the XIAO's continuous manual mode.")
                            .font(.caption).foregroundStyle(.secondary)
                        if modePending || thresholdPending {
                            Label(bluetooth.controlsReady ? "Waiting for wearable confirmation" : (bluetooth.connected ? "Saved on phone — CalmPulse controls unavailable" : "Saved on phone — connect CalmPulse to apply"), systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption).foregroundStyle(accent)
                        }
                        HStack {
                            Text("Start at")
                            Spacer()
                            Button { changeStart(by: -1) } label: { Image(systemName: "minus") }
                                .disabled(startThreshold <= 41 || startThreshold - 1 <= stopThreshold)
                                .accessibilityLabel("Decrease start BPM")
                            Text("\(startThreshold) BPM").monospacedDigit().frame(minWidth: 76)
                            Button { changeStart(by: 1) } label: { Image(systemName: "plus") }
                                .disabled(startThreshold >= 220)
                                .accessibilityLabel("Increase start BPM")
                        }
                        .buttonStyle(.bordered).tint(accent)
                        HStack {
                            Text("Reset below")
                            Spacer()
                            Button { changeStop(by: -1) } label: { Image(systemName: "minus") }
                                .disabled(stopThreshold <= 40)
                                .accessibilityLabel("Decrease reset BPM")
                            Text("\(stopThreshold) BPM").monospacedDigit().frame(minWidth: 76)
                            Button { changeStop(by: 1) } label: { Image(systemName: "plus") }
                                .disabled(stopThreshold + 1 >= startThreshold)
                                .accessibilityLabel("Increase reset BPM")
                        }
                        .buttonStyle(.bordered).tint(accent)
                        if let status = bluetooth.status {
                            Text("Wearable setting: start \(status.startBpm) · reset below \(status.stopBpm) BPM")
                                .font(.caption).foregroundStyle(.secondary)
                            if let contact = status.contactDetected, let valid = status.readingValid {
                                Text("Sensor: \(contact ? "contact" : "no contact") · \(valid ? "valid pulse" : "no valid pulse")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("Use the arrows to change one BPM at a time. The app sends the settled values automatically; they are saved on the phone if disconnected.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !bluetooth.controlsReady {
                            Text(bluetooth.connected ? "Pulse is connected, but this device has no CalmPulse control service." : "Mode and threshold changes are saved on the phone until CalmPulse connects.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(20).background(card, in: RoundedRectangle(cornerRadius: 22))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Apple Health workout context").font(.headline)
                        Text(health.summary).font(.subheadline)
                        if !health.source.isEmpty { Text(health.source).font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            if !health.authorizationRequested {
                                Button("Connect Health") { health.connect() }
                            } else {
                                Button("Refresh workouts") { health.refresh() }
                            }
                        }
                        .buttonStyle(.bordered)
                        if health.authorizationRequested {
                            Text("Health request completed. You can review workout access in the Health app.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Recorded workouts are not a reliable live exercise signal. Choose Off above while exercising.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20).background(card, in: RoundedRectangle(cornerRadius: 22))

                    Text("Prototype only. Elevated pulse can have many causes; moodi does not detect anxiety or provide medical advice. Data remains on this phone and the wearable.")
                        .font(.caption).foregroundStyle(.secondary).padding(.bottom, 24)
                }
                .padding(18)
            }
            .background(background).foregroundStyle(.white)
            .onReceive(bluetooth.$status) { status in
                guard let status else { return }
                if thresholdPending {
                    if status.startBpm == startThreshold && status.stopBpm == stopThreshold {
                        thresholdPending = false
                    }
                } else {
                    startThreshold = status.startBpm
                    stopThreshold = status.stopBpm
                }
                if status.mode == "on" {
                    // An older app or BLE client may have selected continuous manual On.
                    // This UI only supports automatic On, so leave that mode safely.
                    if !modePending {
                        responseMode = "auto"
                        modePending = true
                        if bluetooth.controlsReady { bluetooth.setMode("auto") }
                    }
                    return
                }
                if modePending {
                    if status.mode == responseMode { modePending = false }
                } else { responseMode = status.mode }
                refreshWidget()
            }
            .onReceive(bluetooth.$controlsReady) { ready in
                guard ready else {
                    // Keep the phone's choices and resend them after a reconnect.
                    thresholdPending = true
                    return
                }
                if modePending { bluetooth.setMode(responseMode) }
                if thresholdPending {
                    thresholdSend?.cancel()
                    bluetooth.setThresholds(start: startThreshold, stop: stopThreshold)
                }
            }
            .onAppear {
                // Older app builds accepted values that the Schematik program rejects.
                if !(41...220).contains(startThreshold) || !(40..<startThreshold).contains(stopThreshold) {
                    startThreshold = 50
                    stopThreshold = 40
                    thresholdPending = true
                }
                if responseMode == "on" {
                    responseMode = "auto"
                    modePending = true
                }
                if health.authorizationRequested { health.refresh() }
                applyWidgetChanges()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { applyWidgetChanges() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: SharedSettings.defaults)) { _ in
                applyWidgetChanges()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func readingCaption(fresh: Bool) -> String {
        if !bluetooth.connected { return "Connect your wearable to see your pulse." }
        if !fresh { return "Waiting for a fresh sensor reading…" }
        if bluetooth.bpm == nil { return "Adjust sensor contact; reading not reliable yet." }
        return "Live reading · the wearable checks continuously"
    }
}

