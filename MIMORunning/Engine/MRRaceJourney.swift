import Foundation

// MARK: - 대회 준비 공유 카드 — 계획에서 완주까지 (2026-10-07)
//
// 끝난 대회의 계획 스냅샷 + 실제 러닝 + 예측(계획 시작 · 대회 전 앱) + 워치 VO2max 환산표를 한 장에.
// 러닝 종류: 대회(대회일 가장 긴 러닝) · 강도 훈련(실제 강도 또는 강도 훈련 유형) · 롱런(그 주 계획 롱런의 80% 이상) · 이지.
// 수행 기호는 대회 주차표와 같은 `weekSymbol`, 강도 훈련 완료는 같은 `mrPointRun`.
// ⚠ VO2max 환산표는 비교로만 — 절댓값 예측으로 내세우지 않는다([VO2예측] 2026-10-02). 앱이 져도 사실대로.

struct MRRaceJourney: Identifiable {
    var id: Date { raceDate }
    enum Kind: Int { case easy, long, hard, race }

    struct Week {
        let monday: Date
        let plannedKm: Double
        let km: [Kind: Double]
        let symbol: String?
        var totalKm: Double { km.values.reduce(0, +) }
    }

    struct Day {
        let date: Date
        let kind: Kind?   // nil = 쉰 날
    }

    let raceName: String
    let raceDate: Date
    let distanceM: Double
    let actualMin: Double
    /// 계획 시작 때 앱 예측(0이면 없음)
    let planStartPredMin: Double?
    /// 대회 전 앱 예측(백테스트)과 오차 %
    let appPredMin: Double?
    let appErrPct: Double?
    /// 대회 전 60일 안 워치 VO2max와 그 환산표 예측
    let vo2: Double?
    let vo2PredMin: Double?
    var vo2ErrPct: Double? { vo2PredMin.map { ($0 - actualMin) / actualMin * 100 } }

    let weeks: [Week]
    let days: [Day]
    let runCount: Int
    let totalKm: Double
    let longestKm: Double
    let hardDone: Int
    let hardPlanned: Int
    var symbolCounts: [(symbol: String, count: Int)] {
        [symbolOver, symbolBoth, symbolOne, symbolNone].compactMap { s in
            let n = weeks.filter { $0.symbol == s }.count
            return n > 0 ? (s, n) : nil
        }
    }

    static func make(raceName: String, raceDate: Date, distanceM: Double, actualMin: Double,
                     planWeeks: [MRPlanWeekSummary], planStartPredMin: Double?,
                     appPredMin: Double?, vo2Samples: [(date: Date, value: Double)],
                     runs: [MRWorkout], hardStarts: Set<Date>, pointTypes: [Date: WorkoutType],
                     calendar cal: Calendar = .current) -> MRRaceJourney? {
        let weeksSorted = planWeeks.sorted { $0.monday < $1.monday }
        guard let first = weeksSorted.first, actualMin > 0 else { return nil }
        let start = cal.startOfDay(for: first.monday)
        guard let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: raceDate)) else { return nil }
        let span = runs.filter { $0.start >= start && $0.start < end }.sorted { $0.start < $1.start }

        let raceRun = span.filter { cal.isDate($0.start, inSameDayAs: raceDate) }
            .max { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }?.start
        func isHard(_ r: MRWorkout) -> Bool {
            hardStarts.contains(r.start)
                || (pointTypes[r.start].map { MRPlanPoint.pointWorkoutTypes.contains($0) && $0 != .race } ?? false)
        }

        var kindOf: [Date: Kind] = [:]
        var weeks: [Week] = []
        var hardDone = 0, hardPlanned = 0
        for w in weeksSorted {
            let mon = cal.startOfDay(for: w.monday)
            guard let wEnd = cal.date(byAdding: .day, value: 7, to: mon) else { continue }
            let ws = span.filter { $0.start >= mon && $0.start < wEnd }
            var km: [Kind: Double] = [:]
            for r in ws {
                let k: Kind
                if r.start == raceRun { k = .race }
                else if isHard(r) { k = .hard }
                else if (r.distanceKm ?? 0) >= w.longRunKm * MRPlanWeekContext.longRunDoneFraction && w.longRunKm > 0 { k = .long }
                else { k = .easy }
                kindOf[r.start] = k
                km[k, default: 0] += r.distanceKm ?? 0
            }
            let sym = weekSymbol(plan: w, actualLong: ws.compactMap(\.distanceKm).max() ?? 0,
                                 actualWeekly: ws.compactMap(\.distanceKm).reduce(0, +))
            weeks.append(Week(monday: mon, plannedKm: w.weeklyKm, km: km, symbol: sym))
            if w.point != nil {
                hardPlanned += 1
                if mrPointRun(weekRuns: ws, longRunKm: w.longRunKm, hardStarts: hardStarts, pointTypes: pointTypes) != nil {
                    hardDone += 1
                }
            }
        }

        // 날짜 격자 — 하루에 여러 번이면 가장 센 종류(대회 > 강도 > 롱런 > 이지)
        var days: [Day] = []
        var d = start
        while d < end {
            let ks = span.filter { cal.isDate($0.start, inSameDayAs: d) }.compactMap { kindOf[$0.start] }
            days.append(Day(date: d, kind: ks.max { $0.rawValue < $1.rawValue }))
            d = cal.date(byAdding: .day, value: 1, to: d) ?? end
        }

        let vo2 = mrVO2Before(vo2Samples, raceDate: raceDate, calendar: cal)
        return MRRaceJourney(
            raceName: raceName, raceDate: raceDate, distanceM: distanceM, actualMin: actualMin,
            planStartPredMin: planStartPredMin.flatMap { $0 > 0 ? $0 : nil },
            appPredMin: appPredMin,
            appErrPct: appPredMin.map { ($0 - actualMin) / actualMin * 100 },
            vo2: vo2?.value,
            vo2PredMin: vo2.flatMap { mrTimeForVDOT($0.value, distanceM: distanceM) },
            weeks: weeks, days: days, runCount: span.count,
            totalKm: span.compactMap(\.distanceKm).reduce(0, +),
            longestKm: span.filter { $0.start != raceRun }.compactMap(\.distanceKm).max() ?? 0,
            hardDone: hardDone, hardPlanned: hardPlanned)
    }
}
