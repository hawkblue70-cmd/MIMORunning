import Foundation

// MARK: - 앞 대회 뒤 재개 보정 (2026-11-23)
//
// 하프(11/15) 다음 주 시작 풀 계획이 대회가 끝나자 "회복 블록 · 60% 재시작"을 잃고 하프 거리(21.3km)에서 +10%로 다시 계산돼
// 회복 주(12.6km) 다음 주 롱런이 26km로 스냅샷에 들어갔다. 플래너가 시작 뒤에도 회복 블록을 쓰도록 고친 뒤(`continuesAfterPrior`),
// 이미 잘못 굳은 이번 주 이후 미래 주를 라이브 계획으로 한 번만 바꾼다. 지난 주는 건드리지 않는다.

/// 스냅샷의 이번 주 이후 주를 라이브 주로 교체한다(롱런·주간·단계·실행 안내·강도 훈련). 지난 주(월요일이 이번 주 월요일 앞)는 그대로.
func mrResumeFutureWeeks(snapshot: [MRPlanWeekSummary], live: [MRPlanWeek], thisMonday: Date,
                         calendar cal: Calendar = .current) -> (weeks: [MRPlanWeekSummary], changed: Int) {
    let liveByMonday = Dictionary(live.map { (cal.startOfDay(for: $0.monday), $0) }, uniquingKeysWith: { a, _ in a })
    let thisMon = cal.startOfDay(for: thisMonday)
    var changed = 0
    let weeks = snapshot.map { s -> MRPlanWeekSummary in
        let mon = cal.startOfDay(for: s.monday)
        guard mon >= thisMon, let l = liveByMonday[mon] else { return s }
        guard l.phase != s.phase || abs(l.longRunKm - s.longRunKm) > 0.05 || abs(l.weeklyKm - s.weeklyKm) > 0.05 else { return s }
        changed += 1
        return MRPlanWeekSummary(idx: s.idx, monday: s.monday, phase: l.phase, longRunKm: l.longRunKm,
                                 weeklyKm: l.weeklyKm, breakdown: l.breakdown, point: l.point)
    }
    return (weeks, changed)
}

/// 이미 평가한 계획 — 한 번만 돈다(그 뒤 프로필이 흔들려도 진행 중인 계획을 다시 바꾸지 않는다).
enum MRPriorResumeStore {
    private static let key = "mimo.priorResumeFixed.v1"
    static func isDone(_ planKey: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(planKey)
    }
    static func markDone(_ planKey: String) {
        var v = UserDefaults.standard.stringArray(forKey: key) ?? []
        if !v.contains(planKey) { v.append(planKey); UserDefaults.standard.set(v, forKey: key) }
    }
}
