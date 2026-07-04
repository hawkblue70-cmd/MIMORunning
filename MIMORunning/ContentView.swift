import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var manager = HealthKitManager()
    @Environment(RaceDetector.self) private var raceDetector
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

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
            await raceDetector.setup(context: modelContext)
            await migrateStoryPhotoThumbnails()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, manager.authorizationStatus == .authorized else { return }
            Task { await manager.fetchActivities() }
        }
    }

    // 앱 시작 시 1회: imageData > 300 KB인 기존 StoryPhoto를 800px 썸네일로 재압축
    private func migrateStoryPhotoThumbnails() async {
        let descriptor = FetchDescriptor<StoryPhoto>()
        guard let photos = try? modelContext.fetch(descriptor) else { return }
        let oversized = photos.filter { $0.imageData.count > 300 * 1024 }
        guard !oversized.isEmpty else { return }
        var count = 0
        for photo in oversized {
            guard let img = UIImage(data: photo.imageData),
                  let data = StoryPhoto.thumbnailData(from: img) else { continue }
            photo.imageData = data
            count += 1
        }
        guard count > 0 else { return }
        try? modelContext.save()
        #if DEBUG
        print("StoryPhoto 시작 마이그레이션: \(count)건 재압축 완료")
        #endif
    }
}
