import Charts
import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = BLEManager()
    @StateObject private var health = HealthManager()
    @State private var startThreshold = 100
    @State private var stopThreshold = 90
    @State private var exercising = false
    @State private var automatic = true

    private let background = Color(red: 0.06, green: 0.07, blue: 0.10)
    private let card = Color(red: 0.12, green: 0.13, blue: 0.17)
    private let accent = Color(red: 0.84, green: 0.53, blue: 0.72)

    private var automaticBinding: Binding<Bool> {
        Binding(get: { automatic }, set: { enabled in
            automatic = enabled
            bluetooth.setAutomatic(enabled)
        })
    }

    private var exercisingBinding: Binding<Bool> {
        Binding(get: { exercising }, set: { enabled in
            exercising = enabled
            bluetooth.setWorkoutOverride(enabled)
        })
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
                        if fresh, let status = bluetooth.status, status.vibrating {
                            Label("Gentle heartbeat response", systemImage: "waveform.path")
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
                        Button(bluetooth.connected ? "Disconnect" : "Connect to XIAO") {
                            bluetooth.connected ? bluetooth.disconnect() : bluetooth.connect()
                        }
                        .buttonStyle(.borderedProminent).tint(accent)
                        if let status = bluetooth.status, !status.motorApproved {
                            Label("Motor output locked until its rating is verified", systemImage: "lock.shield")
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
                        Toggle("Automatic heartbeat response", isOn: automaticBinding)
                            .disabled(!bluetooth.controlsReady)
                        Toggle("I'm exercising — pause automatic response", isOn: exercisingBinding)
                            .disabled(!bluetooth.controlsReady)
                        Stepper("Start at \(startThreshold) BPM", value: $startThreshold, in: 50...200)
                        Stepper("Reset below \(stopThreshold) BPM", value: $stopThreshold, in: 40...199)
                        Button("Send thresholds") {
                            bluetooth.setThresholds(start: startThreshold, stop: stopThreshold)
                        }
                        .disabled(stopThreshold >= startThreshold || !bluetooth.controlsReady)
                        Button("Stop vibration and disable automatic response", role: .destructive) {
                            automatic = false
                            bluetooth.stopNow()
                        }
                        .disabled(!bluetooth.controlsReady)
                    }
                    .padding(20).background(card, in: RoundedRectangle(cornerRadius: 22))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Apple Health workout context").font(.headline)
                        Text(health.summary).font(.subheadline)
                        if !health.source.isEmpty { Text(health.source).font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button("Connect Health") { health.connect() }
                            Button("Refresh") { health.refresh() }
                        }
                        .buttonStyle(.bordered)
                        Text("Recorded workouts are not a reliable live exercise signal. Use the exercise switch above when active.")
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
                startThreshold = status.startBpm
                stopThreshold = status.stopBpm
                automatic = status.automatic
                exercising = status.workoutOverride
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

