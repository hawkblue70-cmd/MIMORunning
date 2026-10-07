import Foundation

// MARK: - 월 기록 공유 카드 — 시간·평균 페이스·훈련 구성·이번 달 기록·계획 수행 (2026-10-07)
//
// 성장 탭 러닝 흐름 → 월 보기 공유(`MileageStreakShareCard`)에 싣는 숫자. 판정은 앱이 이미 쓰는 것만:
// 강도 훈련 = 실제 강도(`intenseRuns`) 또는 강도 훈련 유형(`MRPlanPoint.pointWorkoutTypes`),
// 롱런 = 평소 롱런(`mrUsualLongRunKm`)의 80% 이상(`MRPlanWeekContext.longRunDoneFraction`), 나머지 이지.
// ⚠ 진행률·남은 km·지난달 비교는 넣지 않는다(2026-09-22·09-30 결정). 계획 수행은 끝난 주 기호 요약만.

struct MRMonthShareSummary: Equatable {
    var totalMin = 0.0
    var paceSecPerKm: Double? = nil
    var longRuns = 0
    var hardRuns = 0
    var easyRuns = 0
    var longestKm = 0.0
    /// 5km 이상 러닝(인터벌 제외) 가운데 가장 빠른 평균 페이스와 그 거리
    var fastestPace: Double? = nil
    var fastestKm: Double? = nil
    /// 월간 계획을 쓴 끝난 주의 수행 기호 개수 — 없으면 빈 배열
    var planSymbols: [(symbol: String, count: Int)] = []

    static func == (a: Self, b: Self) -> Bool {
        a.totalMin == b.totalMin && a.paceSecPerKm == b.paceSecPerKm && a.longRuns == b.longRuns
            && a.hardRuns == b.hardRuns && a.easyRuns == b.easyRuns && a.longestKm == b.longestKm
            && a.fastestPace == b.fastestPace && a.fastestKm == b.fastestKm
            && a.planSymbols.map(\.symbol) == b.planSymbols.map(\.symbol)
            && a.planSymbols.map(\.count) == b.planSymbols.map(\.count)
    }

    static func make(runs: [MRWorkout], start: Date, end: Date,
                     intenseStarts: Set<Date>, pointTypes: [Date: WorkoutType],
                     frozenWeeks: [MRMonthlyFrozenWeek], now: Date = Date(),
                     calendar cal: Calendar = .current) -> MRMonthShareSummary? {
        let month = runs.filter { $0.start >= start && $0.start < end }
        guard !month.isEmpty else { return nil }
        var s = MRMonthShareSummary()
        s.totalMin = month.map(\.durationMin).reduce(0, +)
        let withDist = month.filter { ($0.distanceKm ?? 0) > 0 }
        let km = withDist.compactMap(\.distanceKm).reduce(0, +)
        if km > 0 { s.paceSecPerKm = withDist.map(\.durationMin).reduce(0, +) * 60 / km }
        s.longestKm = month.compactMap(\.distanceKm).max() ?? 0

        // 평소 롱런 — 이 달 마지막 날 기준 앞 4주(달이 진행 중이면 오늘 기준)
        let usualLong = mrUsualLongRunKm(runs: runs, asOf: min(end, now), calendar: cal)
        for r in month {
            let hard = intenseStarts.contains(r.start)
                || (pointTypes[r.start].map { MRPlanPoint.pointWorkoutTypes.contains($0) } ?? false)
            if hard { s.hardRuns += 1; continue }
            if let u = usualLong, (r.distanceKm ?? 0) >= u * MRPlanWeekContext.longRunDoneFraction {
                s.longRuns += 1
            } else {
                s.easyRuns += 1
            }
        }

        if let f = month.filter({ !$0.isInterval && ($0.distanceKm ?? 0) >= 5 })
            .min(by: { ($0.paceSecPerKm ?? .infinity) < ($1.paceSecPerKm ?? .infinity) }),
           let p = f.paceSecPerKm {
            s.fastestPace = p
            s.fastestKm = f.distanceKm
        }

        // 계획 수행 — 이 달과 겹치는 끝난 주 가운데 월간 계획이 고정된 주만. 대회 주차표와 같은 기호(`weekSymbol`).
        let today = cal.startOfDay(for: now)
        var counts: [String: Int] = [:]
        for f in frozenWeeks {
            let mon = cal.startOfDay(for: f.monday)
            guard let weekEnd = cal.date(byAdding: .day, value: 7, to: mon),
                  weekEnd > start, mon < end, weekEnd <= today else { continue }
            let ws = runs.filter { $0.start >= mon && $0.start < weekEnd }
            let sym = weekSymbol(plan: f.summary, actualLong: ws.compactMap(\.distanceKm).max() ?? 0,
                                 actualWeekly: ws.compactMap(\.distanceKm).reduce(0, +))
            counts[sym, default: 0] += 1
        }
        s.planSymbols = [symbolOver, symbolBoth, symbolOne, symbolNone].compactMap { sym in
            counts[sym].map { (sym, $0) }
        }
        return s
    }
}
