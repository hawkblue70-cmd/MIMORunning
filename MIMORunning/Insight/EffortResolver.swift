import Foundation

/// Apple HealthKit 운동 강도 — 수동(`workoutEffortScore`)·추정(`estimatedWorkoutEffortScore`). 1~10.
struct AppleEffort: Codable, Equatable {
    var manual: Double?
    var estimated: Double?
    var fetchedAt: Date

    /// 피트니스 앱과 동일 규칙: 수동값이 있으면 수동, 없으면 추정.
    var effective: Double? { manual ?? estimated }

    /// fetchedAt을 무시한 값 비교 — 캐시 갱신 여부 판단용.
    func hasSameValues(as other: AppleEffort) -> Bool {
        manual == other.manual && estimated == other.estimated
    }
}

enum EffortSource: Equatable {
    case user, appleManual, appleEstimated
}

struct ResolvedEffort: Equatable {
    let value: Int          // 1...10
    let source: EffortSource
}

/// 우선순위: 내 입력 > Apple 수동 > Apple 추정 > nil. 심박 기반 추정은 하지 않는다.
enum EffortResolver {
    static func clamp(_ v: Int) -> Int { min(10, max(1, v)) }
    static func clamp(_ v: Double) -> Int { clamp(Int(v.rounded())) }

    static func resolve(userValue: Int?, apple: AppleEffort?) -> ResolvedEffort? {
        if let u = userValue { return ResolvedEffort(value: clamp(u), source: .user) }
        if let m = apple?.manual { return ResolvedEffort(value: clamp(m), source: .appleManual) }
        if let e = apple?.estimated { return ResolvedEffort(value: clamp(e), source: .appleEstimated) }
        return nil
    }
}

/// 뷰·엔진이 들고 다니는 조회 인덱스 — 사용자 입력(workoutID 문자열 키) + Apple 값(UUID 키).
struct EffortIndex {
    let user: [String: Int]
    let apple: [UUID: AppleEffort]

    init(user: [String: Int], apple: [UUID: AppleEffort]) {
        self.user = user
        self.apple = apple
    }

    /// WorkoutStory 목록에서 사용자 입력만 추린다.
    init(stories: [WorkoutStory], apple: [UUID: AppleEffort]) {
        var u: [String: Int] = [:]
        for s in stories { if let r = s.effortRPE { u[s.workoutID] = r } }
        self.init(user: u, apple: apple)
    }

    func resolve(_ id: UUID) -> ResolvedEffort? {
        EffortResolver.resolve(userValue: user[id.uuidString], apple: apple[id])
    }
}
