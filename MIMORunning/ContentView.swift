import SwiftUI

struct ContentView: View {
    @State private var manager = HealthKitManager()
    @Environment(RaceDetector.self) private var raceDetector
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ActivityListView(manager: manager)
                .tabItem { Label(AppLanguage.shared.s("기록", "Log"), systemImage: "figure.run") }

            GrowthView(manager: manager)
                .tabItem { Label(AppLanguage.shared.s("성장", "Growth"), systemImage: "chart.line.uptrend.xyaxis") }

            MeView(manager: manager)
                .tabItem { Label(AppLanguage.shared.s("나", "Me"), systemImage: "person") }
        }
        .tint(Theme.violet)
        .preferredColorScheme(.dark)
        .task {
            await manager.checkAuthorizationStatus()
            await raceDetector.setup()   // geocode races (cached after first run)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, manager.authorizationStatus == .authorized else { return }
            Task { await manager.fetchActivities() }
        }
    }
}
