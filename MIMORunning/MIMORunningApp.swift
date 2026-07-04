import SwiftUI
import SwiftData
import OSLog

@main
struct MIMORunningApp: App {
    @State private var raceDetector = RaceDetector()
    @State private var miniMeStore = CustomMiniMeStore()

    init() {
        FontLoader.registerBundledFonts()
        #if DEBUG
        InsightEngine.auditTitlePools()
        #endif
    }

    private static let container: ModelContainer = {
        let schema = Schema([
            WorkoutStory.self, StoryPhoto.self, Shoe.self,
            OneLinerEntry.self, PersistedRaceMatchRecord.self
        ])
        if let c = try? ModelContainer(for: schema,
                                       configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)) {
            UserDefaults.standard.set(true, forKey: "cloudKitSyncAvailable")
            return c
        }
        let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MIMORunning", category: "CloudKit")
        log.warning("CloudKit ModelContainer 초기화 실패 — 로컬 전용으로 강등")
        UserDefaults.standard.set(false, forKey: "cloudKitSyncAvailable")
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("ModelContainer 초기화 실패: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            PhoneWidthWrapper {
                ContentView()
                    .environment(raceDetector)
                    .environment(miniMeStore)
                    .environment(AppLanguage.shared)
            }
        }
        .modelContainer(Self.container)
    }
}

// iPad에서 폰 너비(430pt)로 중앙 표시, iPhone은 전체 사용
private struct PhoneWidthWrapper<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        if sizeClass == .regular {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                content()
                    .environment(\.horizontalSizeClass, .compact)
                    .frame(width: 430)
                    .clipped()
                Spacer(minLength: 0)
            }
            .background(Color.black)
            .preferredColorScheme(.dark)
            .ignoresSafeArea()
        } else {
            content()
        }
    }
}
