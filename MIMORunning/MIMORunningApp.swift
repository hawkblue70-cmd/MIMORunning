import SwiftUI
import SwiftData
import OSLog

@main
struct MIMORunningApp: App {
    @State private var raceDetector = RaceDetector()
    @State private var miniMeStore = CustomMiniMeStore()
    @StateObject private var engine = MREngineStore()

    init() {
        FontLoader.registerBundledFonts()
        MRCacheMaintenance.purgeStale()
        MIMORunningApp.migrateFormStable()
        MIMORunningApp.mergeAndPurgeStaleWorkoutTypeKey()
        MIMORunningApp.backfillWorkoutTypeCacheFromDisk()
        #if DEBUG
        InsightEngine.auditTitlePools()
        #endif
    }

    /// m2_mimo.workoutTypeCache.v1(prefix 잘못 붙인 버전)의 데이터를
    /// 원래 키로 머지한 뒤 삭제한다. 삭제만 했던 이전 버전의 오류를 방어.
    // TODO: remove after v1.x ships (migration no longer needed)
    private static func mergeAndPurgeStaleWorkoutTypeKey() {
        let staleKey = "m2_mimo.workoutTypeCache.v1"
        let baseKey  = "mimo.workoutTypeCache.v1"
        guard let staleDict = UserDefaults.standard.dictionary(forKey: staleKey) as? [String: String] else { return }
        var current = UserDefaults.standard.dictionary(forKey: baseKey) as? [String: String] ?? [:]
        for (k, v) in staleDict { current[k] = v }
        UserDefaults.standard.set(current, forKey: baseKey)
        UserDefaults.standard.removeObject(forKey: staleKey)
        #if DEBUG
        print("[마이그레이션] \(staleKey) → \(baseKey) 머지 완료 (\(staleDict.count)건)")
        #endif
    }

    /// m2_ 키가 이미 삭제된 경우를 대비해 디스크 캐시(v7_*.json)에서 workoutType을 복원한다.
    /// 백그라운드 실행 — UI 차단 없음.
    // TODO: remove after v1.x ships (migration no longer needed)
    private static func backfillWorkoutTypeCacheFromDisk() {
        let migKey = "mimo.migration.workoutTypeBackfill.v7"
        guard !UserDefaults.standard.bool(forKey: migKey) else { return }
        Task.detached(priority: .background) {
            let baseKey = "mimo.workoutTypeCache.v1"
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("mimo_detail", isDirectory: true)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else {
                UserDefaults.standard.set(true, forKey: migKey)
                return
            }
            var dict = UserDefaults.standard.dictionary(forKey: baseKey) as? [String: String] ?? [:]
            var added = 0
            for file in files {
                let name = file.lastPathComponent
                guard name.hasPrefix("v7_"), name.hasSuffix(".json") else { continue }
                let uuidStr = String(name.dropFirst(3).dropLast(5))
                guard UUID(uuidString: uuidStr) != nil else { continue }
                guard let data = try? Data(contentsOf: file),
                      let detail = try? JSONDecoder().decode(ActivityDetail.self, from: data) else { continue }
                dict[uuidStr] = detail.workoutType.rawValue
                added += 1
            }
            UserDefaults.standard.set(dict, forKey: baseKey)
            UserDefaults.standard.set(true, forKey: migKey)
            #if DEBUG
            let intervals = dict.values.filter { $0 == "interval" }.count
            print("[마이그레이션] workoutTypeCache 디스크 백필 완료: \(added)건 복원 / 인터벌 \(intervals)건")
            #endif
        }
    }

    /// form.stable이 판정 시점(화면 표시 전)에 기록되던 버그를 수정하면서
    /// 이미 오염된 엔트리를 1회 삭제한다. 다음 버전 배포 후 제거 가능.
    // TODO: remove after v1.x ships (migration no longer needed)
    private static func migrateFormStable() {
        let migrationKey = "mimo.migration.formStable.v2"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        var log = MRAdviceLogStore.load()
        log.entries.removeValue(forKey: "form.stable")
        MRAdviceLogStore.save(log)
        UserDefaults.standard.set(true, forKey: migrationKey)
        #if DEBUG
        print("[마이그레이션] form.stable 엔트리 삭제 완료")
        #endif
    }

    private static let container: ModelContainer = {
        let schema = Schema([
            WorkoutStory.self, StoryPhoto.self, Shoe.self,
            OneLinerEntry.self, PersistedRaceMatchRecord.self, MyPlannedRace.self
        ])
        let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MIMORunning", category: "CloudKit")
        do {
            let c = try ModelContainer(for: schema,
                                       configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic))
            UserDefaults.standard.set(true, forKey: "cloudKitSyncAvailable")
            log.info("[CloudKit] main container = 동기화 활성")
            return c
        } catch {
            log.warning("[CloudKit] main container = 폴백(로컬) — 사유: \(error.localizedDescription, privacy: .public)")
            UserDefaults.standard.set(false, forKey: "cloudKitSyncAvailable")
            do {
                return try ModelContainer(for: schema)
            } catch let fallbackError {
                fatalError("ModelContainer 초기화 실패: \(fallbackError)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            PhoneWidthWrapper {
                ContentView()
                    .environmentObject(engine)
                    .environment(raceDetector)
                    .environment(miniMeStore)
                    .task { await engine.refresh() }
                    .preferredColorScheme(.dark)
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
