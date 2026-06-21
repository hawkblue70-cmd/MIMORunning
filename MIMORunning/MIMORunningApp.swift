import SwiftUI
import SwiftData

@main
struct MIMORunningApp: App {
    @State private var raceDetector = RaceDetector()
    @State private var miniMeStore = CustomMiniMeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(raceDetector)
                .environment(miniMeStore)
        }
        .modelContainer(for: [WorkoutStory.self, Shoe.self])
    }
}
