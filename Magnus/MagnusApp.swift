import SwiftUI
import SwiftData

@main
struct MagnusApp: App {
    init() {
        Theme.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .tint(Theme.red)
        }
        .modelContainer(for: [
            WorkoutPlan.self,
            WorkoutDay.self,
            Exercise.self,
            WorkoutSession.self,
            SetLog.self
        ])
    }
}
