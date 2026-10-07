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
        /// 계획 단계(늘리기·유지·회복·테이퍼·대회 페이스·대회 주·"10K 계획") — 스냅샷 그대로
        let phase: String
        let plannedKm: Double
        let km: [Kind: Double]
        let symbol: String?
        /// "템포런 3회 21.4km · 거리주 1회 11.1km · 이지 2회 10km" — 같은 종류는 묶어 **언제나 횟수와 km 합**(2026-10-07 사용자:
        /// 1회일 때 숫자가 거리인지 헷갈림 · 이지도 같은 형식). 이지런·일반·종류 없는 짧은 러닝은 "이지" 하나로.
        /// 순서: 대회 → 강도 → 롱런 계열 → 이지(같은 묶음 안에서는 처음 나온 순서).
        let detail: String
        /// 진행 중 계획(2026-10-07 사용자: 아직 안 한 주도 예정으로 표시) — 다음 주부터 · 이번 주
        var isFuture: Bool = false
        var isCurrent: Bool = false
        /// detail을 종류별로 나눈 조각 — 카드가 막대와 같은 색으로 칠한다(2026-10-07 사용자 요청)
        var parts: [(text: String, kind: Kind)] = []
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

    /// 월간 계획 훈련일지(2026-10-07) — 있으면 카드 머리가 대회 대신 월·목표·실제 거리. 대회 칸(이름·기록·예측)은 비어 있다.
    struct Month {
        let title: String        // "10월 훈련일지"
        let start: Date          // 1일
        let end: Date            // 다음 달 1일
        let goalKm: Double?
        let planTotalKm: Double  // 월간 계획 합계(이번 달 날짜 비율)
        let monthKm: Double      // 이번 달 날짜의 실제 합계
        let monthRuns: Int
        /// 러닝 흐름 월 차트(막대 = 거리, 색 = 강도 · 선 = 페이스) — 성장 탭과 같은 집계(RecordSeries, 일 단위)
        var bars: [RecordBar] = []
    }
    var month: Month? = nil

    /// 진행 중인 대회 계획(2026-10-07) — 있으면 머리가 기록 대신 D-day·지금까지 거리·목표·지금 예측.
    struct Progress {
        let daysLeft: Int
        let weekNumber: Int      // 이번 주가 몇 주차인지
        let totalWeeks: Int
        let goalMin: Double?
        let projectedMin: Double?
    }
    var progress: Progress? = nil

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

        let built = buildWeeks(weeksSorted, span: span, raceRun: raceRun, types: types,
                               hardStarts: hardStarts, pointTypes: pointTypes, calendar: cal)
        let weeks = built.weeks, hardDone = built.hardDone, hardPlanned = built.hardPlanned

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

    /// 주별 막대·설명·수행 기호·강도 훈련 완료 — 대회 준비와 월간 훈련일지가 같이 쓴다.
    static func buildWeeks(_ weeksSorted: [MRPlanWeekSummary], span: [MRWorkout], raceRun: Date?,
                           types: [Date: WorkoutType], hardStarts: Set<Date>, pointTypes: [Date: WorkoutType],
                           today: Date? = nil,
                           calendar cal: Calendar) -> (weeks: [Week], hardDone: Int, hardPlanned: Int) {
        let L = AppLanguage.shared
        var weeks: [Week] = []
        var hardDone = 0, hardPlanned = 0
        for w in weeksSorted {
            let mon = cal.startOfDay(for: w.monday)
            guard let wEnd = cal.date(byAdding: .day, value: 7, to: mon) else { continue }
            let ws = span.filter { $0.start >= mon && $0.start < wEnd }
            var km: [Kind: Double] = [:]
            var groups: [(name: String, kind: Kind, n: Int, km: Double)] = []
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
                let label = k == .easy ? L.s("이지", "Easy", ja: "イージー") : name
                km[k, default: 0] += d
                if let i = groups.firstIndex(where: { $0.name == label }) {
                    groups[i].n += 1; groups[i].km += d
                } else {
                    groups.append((label, k, 1, d))
                }
            }
            let parts: [(text: String, kind: Kind)] = groups.enumerated()
                .sorted { ($0.element.kind.rawValue, -$0.offset) > ($1.element.kind.rawValue, -$1.offset) }
                .map { g in
                    let kmStr = mrPointKmString((g.element.km * 10).rounded() / 10)
                    return (L.s("\(g.element.name) \(g.element.n)회 \(kmStr)km", "\(g.element.name) ×\(g.element.n) \(kmStr)km",
                                ja: "\(g.element.name) \(g.element.n)回 \(kmStr)km"), g.element.kind)
                }
            let named = parts.map(\.text)
            // 다음 주부터는 예정 — 실행 안내(계획 문구)와 강도 훈련만, 기호·실제 없음
            if let t = today, mon > t {
                var plan = w.breakdown
                if let pt = w.point { plan += (plan.isEmpty ? "" : " · ") + pt.text }
                weeks.append(Week(monday: mon, phase: w.phase, plannedKm: w.weeklyKm, km: [:], symbol: nil,
                                  detail: L.s("예정", "Planned", ja: "予定") + (plan.isEmpty ? "" : " · " + plan),
                                  isFuture: true))
                continue
            }
            let isCurrent = today.map { t in mon <= t && wEnd > t } ?? false
            var sym: String? = weekSymbol(plan: w, actualLong: ws.compactMap(\.distanceKm).max() ?? 0,
                                          actualWeekly: ws.compactMap(\.distanceKm).reduce(0, +))
            // 이번 주는 다 채웠을 때만(●·▲) — 대회 주차표와 같은 규칙
            if isCurrent && sym != symbolBoth && sym != symbolOver { sym = nil }
            weeks.append(Week(monday: mon, phase: w.phase, plannedKm: w.weeklyKm, km: km, symbol: sym,
                              detail: named.isEmpty ? L.s("러닝 없음", "No runs", ja: "ランなし") : named.joined(separator: " · "),
                              isCurrent: isCurrent, parts: parts))
            if w.point != nil {
                hardPlanned += 1
                if mrPointRun(weekRuns: ws, longRunKm: w.longRunKm, hardStarts: hardStarts, pointTypes: pointTypes) != nil {
                    hardDone += 1
                }
            }
        }

        return (weeks, hardDone, hardPlanned)
    }

    /// 월간 계획 훈련일지 — 고정된 주차(지난 주·이번 주) + 그 기간 러닝. 이번 주 이후 주는 넣지 않는다.
    static func makeMonth(title: String, monthStart: Date, monthEnd: Date, goalKm: Double?, planTotalKm: Double,
                          planWeeks: [MRPlanWeekSummary], bars: [RecordBar] = [], now: Date = Date(),
                          runs: [MRWorkout], types: [Date: WorkoutType],
                          hardStarts: Set<Date>, pointTypes: [Date: WorkoutType],
                          calendar cal: Calendar = .current) -> MRRaceJourney? {
        let today = cal.startOfDay(for: now)
        let weeksSorted = planWeeks.filter { cal.startOfDay(for: $0.monday) <= today }.sorted { $0.monday < $1.monday }
        guard let first = weeksSorted.first, let last = weeksSorted.last,
              let lastEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: last.monday)),
              let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return nil }
        let start = cal.startOfDay(for: first.monday)
        let end = min(lastEnd, tomorrow)
        let span = runs.filter { $0.start >= start && $0.start < end }.sorted { $0.start < $1.start }
        let inMonth = span.filter { $0.start >= monthStart && $0.start < monthEnd }
        guard !inMonth.isEmpty else { return nil }
        let built = buildWeeks(weeksSorted, span: span, raceRun: nil, types: types,
                               hardStarts: hardStarts, pointTypes: pointTypes, calendar: cal)
        var j = MRRaceJourney(
            raceName: "", raceDate: monthStart, distanceM: 0, actualMin: 0,
            planStartPredMin: nil, appPredMin: nil, appErrPct: nil, vo2: nil, vo2PredMin: nil,
            weeks: built.weeks, runCount: span.count,
            totalKm: span.compactMap(\.distanceKm).reduce(0, +),
            longestKm: span.compactMap(\.distanceKm).max() ?? 0,
            hardDone: built.hardDone, hardPlanned: built.hardPlanned)
        j.month = Month(title: title, start: monthStart, end: monthEnd, goalKm: goalKm, planTotalKm: planTotalKm,
                        monthKm: inMonth.compactMap(\.distanceKm).reduce(0, +), monthRuns: inMonth.count, bars: bars)
        return j
    }

    /// 러닝 시작 시각 → 앱 저장 종류 — Activity를 시작 시각으로 찾아 읽는다. 대회 상세·월간 계획이 같이 쓴다.
    @MainActor
    static func runTypes(manager: HealthKitManager?, runs: [MRWorkout], from: Date, to: Date,
                         fallback: [Date: WorkoutType]) -> [Date: WorkoutType] {
        guard let m = manager else { return fallback }
        let lookup = m.workoutTypeLookup()
        var out: [Date: WorkoutType] = [:]
        for a in m.activities where a.type == .running && a.date >= from && a.date < to {
            guard let t = lookup(a.id),
                  let r = runs.first(where: { abs($0.start.timeIntervalSince(a.date)) < 1 }) else { continue }
            out[r.start] = t
        }
        return out
    }

    /// 진행 중인 대회 계획 — 계획 시작부터 이번 주까지. 대회 전이라 기록·오차·VO2 줄은 없다.
    static func makeInProgress(raceName: String, raceDate: Date, distanceM: Double,
                               planWeeks: [MRPlanWeekSummary], goalMin: Double?, projectedMin: Double?,
                               now: Date = Date(), runs: [MRWorkout], types: [Date: WorkoutType],
                               hardStarts: Set<Date>, pointTypes: [Date: WorkoutType],
                               calendar cal: Calendar = .current) -> MRRaceJourney? {
        let today = cal.startOfDay(for: now)
        let all = planWeeks.sorted { $0.monday < $1.monday }
        let weeksSorted = all.filter { cal.startOfDay(for: $0.monday) <= today }
        guard let first = all.first, !weeksSorted.isEmpty,
              let tomorrow = cal.date(byAdding: .day, value: 1, to: today),
              today < cal.startOfDay(for: raceDate) else { return nil }
        let start = cal.startOfDay(for: first.monday)
        let span = runs.filter { $0.start >= start && $0.start < tomorrow }.sorted { $0.start < $1.start }
        // 아직 안 한 주까지 모두 — 다음 주부터는 예정으로(2026-10-07 사용자 요청)
        let built = buildWeeks(all, span: span, raceRun: nil, types: types,
                               hardStarts: hardStarts, pointTypes: pointTypes, today: today, calendar: cal)
        var j = MRRaceJourney(
            raceName: raceName, raceDate: raceDate, distanceM: distanceM, actualMin: 0,
            planStartPredMin: nil, appPredMin: nil, appErrPct: nil, vo2: nil, vo2PredMin: nil,
            weeks: built.weeks, runCount: span.count,
            totalKm: span.compactMap(\.distanceKm).reduce(0, +),
            longestKm: span.compactMap(\.distanceKm).max() ?? 0,
            hardDone: built.hardDone, hardPlanned: built.hardPlanned)
        j.progress = Progress(
            daysLeft: cal.dateComponents([.day], from: today, to: cal.startOfDay(for: raceDate)).day ?? 0,
            weekNumber: weeksSorted.count, totalWeeks: all.count,
            goalMin: goalMin.flatMap { $0 > 0 ? $0 : nil }, projectedMin: projectedMin.flatMap { $0 > 0 ? $0 : nil })
        return j
    }
}
