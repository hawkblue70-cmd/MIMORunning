import Foundation
import HealthKit

/// 러닝별 상승 고도(m) — 운동 기록 메타데이터(`HKMetadataKeyElevationAscended`)에서 읽어 둔다.
/// 지난 러닝은 경로(상세)를 다시 조회하지 않으므로, 같은 페이스 심박 비교의 "오르내림이 많은 코스" 판단에 이 값을 쓴다(2026-11-07).
/// 기기 안 UserDefaults에만 둔다(운동 ID → 정수 m).
final class WorkoutElevationStore: @unchecked Sendable {
    static let shared = WorkoutElevationStore()
    private static let key = "mimo.workoutElevation.v1"
    private let lock = NSLock()
    private var cache: [String: Int]

    private init() {
        cache = (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Int]) ?? [:]
    }

    func gain(_ id: UUID) -> Double? {
        lock.lock(); defer { lock.unlock() }
        return cache[id.uuidString].map(Double.init)
    }

    /// 조회한 운동들의 상승 고도를 기록 — 메타데이터가 없는 운동은 건너뛴다
    func record(_ workouts: [HKWorkout]) {
        var changed = false
        lock.lock()
        for w in workouts {
            guard let q = w.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity,
                  q.is(compatibleWith: .meter()) else { continue }
            let m = Int(q.doubleValue(for: .meter()).rounded())
            guard m >= 0, cache[w.uuid.uuidString] != m else { continue }
            cache[w.uuid.uuidString] = m
            changed = true
        }
        let snapshot = changed ? cache : nil
        lock.unlock()
        if let snapshot { UserDefaults.standard.set(snapshot, forKey: Self.key) }
    }

    #if DEBUG
    /// 테스트 전용 — 값 직접 넣기
    func setForTesting(_ id: UUID, _ m: Int?) {
        lock.lock(); cache[id.uuidString] = m; lock.unlock()
    }
    #endif
}
