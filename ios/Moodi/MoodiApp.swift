import SwiftUI

@main
struct MoodiApp: App {
    init() { SharedSettings.migrateFromAppDefaults() }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

