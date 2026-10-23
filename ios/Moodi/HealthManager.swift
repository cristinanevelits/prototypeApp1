import Foundation
import Combine
import HealthKit

final class HealthManager: ObservableObject {
    @Published private(set) var summary = "Connect Health to show recent recorded workouts."
    @Published private(set) var source = ""

    private let store = HKHealthStore()

    func connect() {
        guard HKHealthStore.isHealthDataAvailable() else {
            summary = "Health data is unavailable on this device."
            return
        }
        store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()]) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error { self?.summary = "Health permission error: \(error.localizedDescription)" }
                else { self?.refresh() }
            }
        }
    }

    func refresh() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let since = Date().addingTimeInterval(-24 * 60 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                  limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, error in
            DispatchQueue.main.async {
                if let error {
                    self?.summary = "Could not read workouts: \(error.localizedDescription)"
                    return
                }
                guard let workout = samples?.first as? HKWorkout else {
                    // HealthKit intentionally doesn't reveal whether read permission was denied.
                    self?.summary = "No recorded workout available in the last 24 hours."
                    self?.source = "This does not prove you are not exercising."
                    return
                }
                self?.summary = "Last recorded workout ended \(workout.endDate.formatted(date: .abbreviated, time: .shortened))."
                self?.source = "Source: \(workout.sourceRevision.source.name). Not a live workout signal."
            }
        }
        store.execute(query)
    }
}

