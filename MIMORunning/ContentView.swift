import SwiftUI

struct ContentView: View {
    @State private var manager = HealthKitManager()
    @Environment(RaceDetector.self) private var raceDetector

    var body: some View {
        TabView {
            ActivityListView(manager: manager)
                .tabItem { Label("기록", systemImage: "figure.run") }

            GrowthView(manager: manager)
                .tabItem { Label("성장", systemImage: "chart.line.uptrend.xyaxis") }

            MeView(manager: manager)
                .tabItem { Label("나", systemImage: "person") }
        }
        .tint(Theme.violet)
        .preferredColorScheme(.dark)
        .task {
            await manager.checkAuthorizationStatus()
            await raceDetector.setup()   // geocode races (cached after first run)
        }
    }
}
