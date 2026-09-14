import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @State private var manager = HealthKitManager()
    @EnvironmentObject private var engine: MREngineStore
    @Environment(RaceDetector.self) private var raceDetector
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            ActivityListView(manager: manager)
                .tabItem {
                    Image(systemName: "figure.run").imageScale(.large)
                    Text(AppLanguage.shared.s("기록", "Log"))
                }

            GrowthView(manager: manager)
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis").imageScale(.large)
                    Text(AppLanguage.shared.s("성장", "Growth"))
                }

            CrewTabView(manager: manager)
                .tabItem {
                    Image(systemName: "person.2.fill").imageScale(.large)
                    Text(AppLanguage.shared.s("크루", "Crew"))
                }

            MeView(manager: manager)
                .tabItem {
                    Image(systemName: "person").imageScale(.large)
                    Text(AppLanguage.shared.s("나", "Me"))
                }
        }
        .tint(Theme.violet)
        .preferredColorScheme(.dark)
        .task {
            await manager.checkAuthorizationStatus()
            await raceDetector.setup(context: modelContext)
            await migrateStoryPhotoThumbnails()
        }
        .task(id: manager.activities.count) {
            await revalidateRaceMatchesIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // 홈 오늘 카드는 시간에 따라 바뀐다(러닝 종료 후 12시간까지만 기록 줄 표시).
            // 엔진 전체 refresh는 앱 시작 때만 돌므로, 백그라운드에서 돌아올 때 캐시된 러닝으로
            // 카드만 다시 계산한다 — HealthKit 재읽기 없음, 순수 계산.
            engine.recomputeTodayCard()
            guard manager.authorizationStatus == .authorized else { return }
            Task { await manager.fetchActivities() }
        }
        .background(KeyboardDismissInstaller())
    }

    // MARK: Private helpers

    /// 예전 느슨한 기준으로 자동 확정된 대회 매칭을 현재 게이트로 다시 검사한다.
    /// 대상은 보통 한 자릿수이고 detail은 디스크 캐시를 타므로 HealthKit 재읽기는 사실상 없다.
    /// 아직 활동 목록에 없는 건은 건너뛰고 다음 기회에 다시 시도한다.
    private func revalidateRaceMatchesIfNeeded() async {
        guard raceDetector.isReady else { return }
        let pending = raceDetector.idsNeedingRevalidation
        guard !pending.isEmpty, !manager.activities.isEmpty else { return }

        let byID = Dictionary(manager.activities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var inputs: [RaceRevalidationInput] = []
        for id in pending {
            guard let activity = byID[id] else { continue }
            let coords = await manager.fetchDetail(for: id)?.routeCoordinates ?? []
            inputs.append(RaceRevalidationInput(
                activityID: id,
                date: activity.date,
                distanceKm: activity.distance / 1000,
                startCoord: coords.first
            ))
        }
        let dropped = raceDetector.revalidateAutoMatches(inputs)
        #if DEBUG
        print("[대회매칭] 재검증 \(inputs.count)건 — 확정 해제 \(dropped.count)건")
        #endif
    }

    // 앱 시작 시: imageData > 300 KB인 StoryPhoto를 800px 썸네일로 재압축.
    // 300 KB 초과 결과는 write-back하지 않아 다음 시작 시 자동 재시도.
    private func migrateStoryPhotoThumbnails() async {
        let descriptor = FetchDescriptor<StoryPhoto>()
        guard let photos = try? modelContext.fetch(descriptor) else { return }
        let oversized = photos.filter { $0.imageData.count > 300 * 1024 }
        #if DEBUG
        if oversized.isEmpty { print("[PhotoMigration] 대상 0건 — 이미 최적화됨"); return }
        print("[PhotoMigration] 대상 \(oversized.count)건 재압축 시작")
        #else
        guard !oversized.isEmpty else { return }
        #endif
        var successCount = 0
        var failCount    = 0
        for photo in oversized {
            let beforeKB = photo.imageData.count / 1024
            // thumbnailData(from: Data) 오버로드: UIImage 디코딩 → 800px 리사이즈 → JPEG 0.7
            guard let data = StoryPhoto.thumbnailData(from: photo.imageData) else { continue }
            let afterKB = data.count / 1024
            if data.count > 300 * 1024 {
                // 300 KB 초과: write-back 생략 → 다음 시작 시 재시도
                failCount += 1
                #if DEBUG
                print("[PhotoMigration] 실패 \(beforeKB) kB → \(afterKB) kB (재시도 예정)")
                #endif
            } else {
                photo.imageData = data
                successCount += 1
                #if DEBUG
                print("[PhotoMigration] \(successCount)번째: \(beforeKB) kB → \(afterKB) kB ✓300KB 이하")
                #endif
            }
        }
        if successCount > 0 { try? modelContext.save() }
        #if DEBUG
        let failNote = failCount > 0 ? ", 실패 \(failCount)건 재시도 예정" : ""
        print("[PhotoMigration] 완료 \(successCount)/\(oversized.count)건\(failNote)")
        #endif
    }
}

// MARK: - KeyboardDismissInstaller
//
// 창(Window) 레벨에서 탭 제스처를 설치해 텍스트 필드 외 영역 터치 시 키보드를 전역 해제.
// cancelsTouchesInView = false 로 다른 제스처를 방해하지 않음.
// .background()에 사용하면 ContentView 생명주기와 일치.

private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> _KeyboardDismissHelperView {
        _KeyboardDismissHelperView()
    }
    func updateUIView(_ uiView: _KeyboardDismissHelperView, context: Context) {}
}

private final class _KeyboardDismissHelperView: UIView {
    private weak var installedGesture: UITapGestureRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let prev = installedGesture {
            prev.view?.removeGestureRecognizer(prev)
            installedGesture = nil
        }
        guard let window else { return }
        let rec = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        rec.cancelsTouchesInView = false
        window.addGestureRecognizer(rec)
        installedGesture = rec
    }

    @objc private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}
