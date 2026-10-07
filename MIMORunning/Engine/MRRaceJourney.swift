import Foundation

// MARK: - 대회 준비 공유 카드 — 계획에서 완주까지 (2026-10-07)
//
// 끝난 대회의 계획 스냅샷 + 실제 러닝 + 예측(계획 시작 · 대회 전 앱) + 워치 VO2max 환산표를 한 장에.
// 러닝 종류는 **앱에 저장된 러닝 종류**(템포런·인터벌·롱런…)로 — 심박 기반 '실제 강도'로 칠하면
// 심박이 높은 러너는 거의 모든 러닝이 강도 훈련이 된다(2026-10-07 실기기: 43회 중 대부분 주황).
//   대회 = 대회일 가장 긴 러닝 · 강도 = 인터벌·템포런·빌드업 · 롱런 = 롱런·LSD·거리주,
//   종류가 없으면 그 주 계획 롱런의 80% 이상 → 롱런, 아니면 이지.
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
        /// "템포런 8 · 롱런 16 · 이지 3회" — 이지가 아닌 러닝은 이름과 km, 이지는 횟수
        let detail: String
        var totalKm: Double { km.values.reduce(0, +) }
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

    static func kind(of t: WorkoutType) -> Kind {
        switch t {
        case .race: return .race
        case .interval, .tempo, .buildUp: return .hard
        case .longRun, .lsd, .distanceRun: return .long
        case .easy, .general: return .easy
        }
    }

    /// - types: 러닝 시작 시각 → 앱 저장 종류(전부). 없으면 거리로 롱런·이지만 나눈다.
    /// - hardStarts·pointTypes: 강도 훈련 완료 판정만(주차표와 같은 기준).
    static func make(raceName: String, raceDate: Date, distanceM: Double, actualMin: Double,
                     planWeeks: [MRPlanWeekSummary], planStartPredMin: Double?,
                     appPredMin: Double?, vo2Samples: [(date: Date, value: Double)],
                     runs: [MRWorkout], types: [Date: WorkoutType],
                     hardStarts: Set<Date>, pointTypes: [Date: WorkoutType],
                     calendar cal: Calendar = .current) -> MRRaceJourney? {
        let weeksSorted = planWeeks.sorted { $0.monday < $1.monday }
        guard let first = weeksSorted.first, actualMin > 0 else { return nil }
        let start = cal.startOfDay(for: first.monday)
        guard let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: raceDate)) else { return nil }
        let span = runs.filter { $0.start >= start && $0.start < end }.sorted { $0.start < $1.start }
        let raceRun = span.filter { cal.isDate($0.start, inSameDayAs: raceDate) }
            .max { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }?.start
        let L = AppLanguage.shared

        var weeks: [Week] = []
        var hardDone = 0, hardPlanned = 0
        for w in weeksSorted {
            let mon = cal.startOfDay(for: w.monday)
            guard let wEnd = cal.date(byAdding: .day, value: 7, to: mon) else { continue }
            let ws = span.filter { $0.start >= mon && $0.start < wEnd }
            var km: [Kind: Double] = [:]
            var named: [String] = []
            var easyCount = 0
            for r in ws {
                let d = r.distanceKm ?? 0
                let k: Kind
                let name: String
                if r.start == raceRun {
                    k = .race; name = L.s("대회", "Race", ja: "レース")
                } else if let t = types[r.start], t != .race {
                    k = kind(of: t); name = t.koreanLabel
                } else if w.longRunKm > 0 && d >= w.longRunKm * MRPlanWeekContext.longRunDoneFraction {
                    k = .long; name = L.s("롱런", "Long Run", ja: "ロング走")
                } else {
                    k = .easy; name = ""
                }
                km[k, default: 0] += d
                if k == .easy { easyCount += 1 } else { named.append("\(name) \(mrPointKmString((d * 10).rounded() / 10))") }
            }
            if easyCount > 0 { named.append(L.s("이지 \(easyCount)회", "easy ×\(easyCount)", ja: "イージー\(easyCount)回")) }
            let sym = weekSymbol(plan: w, actualLong: ws.compactMap(\.distanceKm).max() ?? 0,
                                 actualWeekly: ws.compactMap(\.distanceKm).reduce(0, +))
            weeks.append(Week(monday: mon, plannedKm: w.weeklyKm, km: km, symbol: sym,
                              detail: named.isEmpty ? L.s("러닝 없음", "No runs", ja: "ランなし") : named.joined(separator: " · ")))
            if w.point != nil {
                hardPlanned += 1
                if mrPointRun(weekRuns: ws, longRunKm: w.longRunKm, hardStarts: hardStarts, pointTypes: pointTypes) != nil {
                    hardDone += 1
                }
            }
        }

        let vo2 = mrVO2Before(vo2Samples, raceDate: raceDate, calendar: cal)
        return MRRaceJourney(
            raceName: raceName, raceDate: raceDate, distanceM: distanceM, actualMin: actualMin,
            planStartPredMin: planStartPredMin.flatMap { $0 > 0 ? $0 : nil },
            appPredMin: appPredMin,
            appErrPct: appPredMin.map { ($0 - actualMin) / actualMin * 100 },
            vo2: vo2?.value,
            vo2PredMin: vo2.flatMap { mrTimeForVDOT($0.value, distanceM: distanceM) },
            weeks: weeks, runCount: span.count,
            totalKm: span.compactMap(\.distanceKm).reduce(0, +),
            longestKm: span.filter { $0.start != raceRun }.compactMap(\.distanceKm).max() ?? 0,
            hardDone: hardDone, hardPlanned: hardPlanned)
    }
}
