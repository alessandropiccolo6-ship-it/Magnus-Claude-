import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            PlanView()
                .tabItem { Label("Scheda", systemImage: "doc.text.image") }

            WorkoutView()
                .tabItem { Label("Allena", systemImage: "dumbbell.fill") }

            ProgressDashboardView()
                .tabItem { Label("Progressi", systemImage: "chart.line.uptrend.xyaxis") }

            HistoryView()
                .tabItem { Label("Storico", systemImage: "calendar") }
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
