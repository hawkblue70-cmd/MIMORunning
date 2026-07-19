import SwiftUI
import SwiftData
import UIKit

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
        .background(KeyboardDismissInstaller())
    }

    // MARK: Private helpers

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
