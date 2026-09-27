import Foundation

/// 대회 준비 비교(B단계) — 등록 대회의 D-N 시점과, 지난 대회(같은 대회 우선, 없으면 같은 거리)의
/// 같은 D-N 시점의 준비 상태를 비교한다. 순수 로직.
/// 설계 `docs/superpowers/specs/2026-09-27-race-prep-comparison-design.md`.
enum MRPrepComparison {

    /// 비교 대상이 될 수 있는 확정 대회 하나.
    struct PastRace: Equatable {
        let name: String
        /// 대회 날짜 — 확정 매칭의 raceDate(대회 DB 날짜의 UTC 자정)
        let date: Date
        /// 공식 종목 거리(km)
        let distanceKm: Double
        let series: String?
    }

    struct Target: Equatable {
        let race: PastRace
        let isSameRace: Bool
    }

    /// 러닝 한 번 — 날짜와 거리(km)
    struct RunPoint {
        let date: Date
        let km: Double
    }

    /// 시점 직전 28일의 준비 지표
    struct Metrics: Equatable {
        let weeklyKm: Double
        let longestKm: Double
    }

    struct Result: Equatable {
        let target: PastRace
        let isSameRace: Bool
        /// D-N의 N
        let daysLeft: Int
        /// 등록 대회 연도 − 지난 대회 연도
        let yearsAgo: Int
        let pastYear: Int
        let now: Metrics
        let past: Metrics
        let nowPredictedMin: Double?
        let pastPredictedMin: Double?
    }

    /// 나 탭 블록 한 줄
    struct Line: Equatable {
        let label: String
        let now: String
        let past: String
        /// 지금이 앞설 때만 — "+20%" · "−7:00"
        let gain: String?
    }

    static let sameEventTolerance = 0.02
    static let sameDistanceTolerance = 0.10
    /// 거리 지표를 "많아요"로 말하는 문턱 — 10% 이상
    static let gainThreshold = 0.10
    static let windowDays = 28

    // MARK: - 대상

    /// 같은 대회(같은 시리즈·같은 종목 ±2%) 최신 > 같은 거리(10%) 최신. 등록 대회 날짜보다 이른 것만.
    static func target(raceDate: Date, raceDistanceKm: Double, raceSeries: String?,
                       confirmed: [PastRace], calendar: Calendar = .current) -> Target? {
        let raceDay = calendar.startOfDay(for: raceDate)
        let earlier = confirmed
            .filter { calendar.startOfDay(for: $0.date) < raceDay }
            .sorted { $0.date > $1.date }
        func ratio(_ km: Double) -> Double { abs(km - raceDistanceKm) / max(raceDistanceKm, 0.001) }
        if let s = raceSeries, !s.isEmpty,
           let same = earlier.first(where: { $0.series == s && ratio($0.distanceKm) <= sameEventTolerance }) {
            return Target(race: same, isSameRace: true)
        }
        if let dist = earlier.first(where: { ratio($0.distanceKm) <= sameDistanceTolerance + 1e-9 }) {
            return Target(race: dist, isSameRace: false)
        }
        return nil
    }

    // MARK: - 시점 · 지표

    static func daysLeft(raceDate: Date, today: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: today),
                                to: calendar.startOfDay(for: raceDate)).day ?? 0
    }

    /// 지난 대회일(자정) − N일
    static func pastPoint(pastRaceDate: Date, daysLeft: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -daysLeft, to: calendar.startOfDay(for: pastRaceDate))
            ?? pastRaceDate
    }

    /// 시점 직전 28일(시점 당일 제외). 창에 러닝이 없으면 nil.
    static func metrics(runs: [RunPoint], before point: Date, calendar: Calendar = .current) -> Metrics? {
        let end = calendar.startOfDay(for: point)
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: end) else { return nil }
        let inWindow = runs.filter { $0.date >= start && $0.date < end && $0.km > 0 }
        guard !inWindow.isEmpty else { return nil }
        let total = inWindow.map(\.km).reduce(0, +)
        return Metrics(weeklyKm: total / Double(windowDays / 7),
                       longestKm: inWindow.map(\.km).max() ?? 0)
    }

    /// 등록 대회 하나의 결과. D-N ≥ 1이고 대상이 있고 지난 창에 러닝이 있을 때만.
    /// - predictionAt: 그 시점 전날까지 데이터로 낸 예상 기록(분). 엔진이 제공.
    static func build(raceDate: Date, raceDistanceKm: Double, raceSeries: String?,
                      confirmed: [PastRace], runs: [RunPoint], today: Date,
                      nowPredictedMin: Double?, predictionAt: (Date) -> Double?,
                      calendar: Calendar = .current) -> Result? {
        let n = daysLeft(raceDate: raceDate, today: today, calendar: calendar)
        guard n >= 1,
              let t = target(raceDate: raceDate, raceDistanceKm: raceDistanceKm, raceSeries: raceSeries,
                             confirmed: confirmed, calendar: calendar) else { return nil }
        let point = pastPoint(pastRaceDate: t.race.date, daysLeft: n, calendar: calendar)
        guard let past = metrics(runs: runs, before: point, calendar: calendar) else { return nil }
        let now = metrics(runs: runs, before: today, calendar: calendar) ?? Metrics(weeklyKm: 0, longestKm: 0)
        let pastYear = calendar.component(.year, from: t.race.date)
        return Result(target: t.race, isSameRace: t.isSameRace, daysLeft: n,
                      yearsAgo: calendar.component(.year, from: raceDate) - pastYear,
                      pastYear: pastYear, now: now, past: past,
                      nowPredictedMin: nowPredictedMin, pastPredictedMin: predictionAt(point))
    }

    // MARK: - 나 탭 블록

    /// "작년 ○○" · "2024년 ○○" · "지난 ○○"(같은 해) · 같은 거리는 "지난 ○○ 10K"
    static func targetName(_ r: Result) -> String {
        let L = AppLanguage.shared
        let name = RaceDisplayName.short(r.target.name)
        guard r.isSameRace else {
            let label = RaceDisplayName.distanceLabel(km: r.target.distanceKm)
            return L.s("지난 \(name) \(label)", "your last \(name) \(label)")
        }
        if r.yearsAgo == 1 { return L.s("작년 \(name)", "last year's \(name)") }
        if r.yearsAgo >= 2 { return L.s("\(r.pastYear)년 \(name)", "\(name) \(r.pastYear)") }
        return L.s("지난 \(name)", "your last \(name)")
    }

    static func title(_ r: Result) -> String {
        AppLanguage.shared.s("\(targetName(r)) D-\(r.daysLeft) 시점과 비교",
                             "Compared with \(targetName(r)) at D-\(r.daysLeft)")
    }

    /// 지난 값 앞에 붙는 열 이름 — 작년 · 2024년 · 지난
    static func pastColumn(_ r: Result) -> String {
        let L = AppLanguage.shared
        guard r.isSameRace else { return L.s("지난", "last") }
        if r.yearsAgo == 1 { return L.s("작년", "last yr") }
        if r.yearsAgo >= 2 { return L.s("\(r.pastYear)년", "\(r.pastYear)") }
        return L.s("지난", "last")
    }

    static func lines(_ r: Result) -> [Line] {
        let L = AppLanguage.shared
        let col = pastColumn(r)
        func km(_ v: Double) -> String { "\(Int(v.rounded()))km" }
        func gain(_ now: Double, _ past: Double) -> String? {
            guard past > 0, now >= past * (1 + gainThreshold) - 1e-9 else { return nil }
            return "+\(Int(((now / past - 1) * 100).rounded()))%"
        }
        var out = [
            Line(label: L.s("주간 거리", "Weekly"), now: km(r.now.weeklyKm),
                 past: "\(col) \(km(r.past.weeklyKm))", gain: gain(r.now.weeklyKm, r.past.weeklyKm)),
            Line(label: L.s("최장 롱런", "Longest"), now: km(r.now.longestKm),
                 past: "\(col) \(km(r.past.longestKm))", gain: gain(r.now.longestKm, r.past.longestKm)),
        ]
        if let n = r.nowPredictedMin, let p = r.pastPredictedMin {
            let faster = Int(((p - n) * 60).rounded())
            out.append(Line(label: L.s("예상 기록", "Predicted"), now: mrFormatDisplay(n),
                            past: "\(col) \(mrFormatDisplay(p))",
                            gain: faster >= 1 ? "−" + RaceYearOverYear.clockDuration(faster) : nil))
        }
        return out
    }

    // MARK: - 홈 한 줄

    static func homeLine(_ r: Result) -> String {
        let L = AppLanguage.shared
        let nowKm = Int(r.now.weeklyKm.rounded()), pastKm = Int(r.past.weeklyKm.rounded())
        let name = RaceDisplayName.short(r.target.name)
        let subjectKo: String, subjectEn: String
        if r.isSameRace && r.yearsAgo == 1 {
            subjectKo = "작년 이맘때"; subjectEn = "this point last year"
        } else if r.isSameRace && r.yearsAgo >= 2 {
            subjectKo = "\(r.pastYear)년 이맘때"; subjectEn = "this point in \(r.pastYear)"
        } else {
            subjectKo = "지난 \(name) 이맘때"; subjectEn = "this point before your last \(name)"
        }
        if r.past.weeklyKm > 0, r.now.weeklyKm >= r.past.weeklyKm * (1 + gainThreshold) - 1e-9 {
            let pct = Int(((r.now.weeklyKm / r.past.weeklyKm - 1) * 100).rounded())
            return L.s("\(subjectKo)보다 주간 거리 \(pct)% 많아요 · \(nowKm)km / \(pastKm)km",
                       "Weekly distance \(pct)% higher than \(subjectEn) · \(nowKm) km / \(pastKm) km")
        }
        let subjectEnCap = subjectEn.prefix(1).uppercased() + subjectEn.dropFirst()
        return L.s("\(subjectKo) 주간 \(pastKm)km · 지금 \(nowKm)km",
                   "\(subjectEnCap): \(pastKm) km/wk · now \(nowKm) km")
    }
}
