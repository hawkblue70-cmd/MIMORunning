import Foundation

/// sRPE 부하(Foster 2001: RPE × 분) · 주간 합 · 단조도 · 7일/28일 비교 · 회복 주 판정.
/// 러닝만, 강도 있는 런만 합산. "부상·위험" 표현은 쓰지 않는다(Impellizzeri 2020).
enum EffortLoad {

    struct Run {
        let date: Date
        let durationMin: Double
        let effort: Int?          // nil = 강도 없음 → 부하 미합산, runCount에는 포함
    }

    struct WeekLoad: Equatable {
        let weekStart: Date
        let total: Double                 // AU
        let daily: [Double]               // 월~일 7개, AU
        let dailyMeanEffort: [Double?]    // 월~일 7개, 색상용
        let runCount: Int
        let coveredCount: Int
        let meanEffort: Double?
        var coverage: Double { runCount == 0 ? 0 : Double(coveredCount) / Double(runCount) }
    }

    enum RatioLabel: Equatable { case low, steady, high, veryHigh }
    enum SentenceKind: Equatable { case monotony, low, high, veryHigh }

    static let minCoverage = 0.5
    static let minChronicWeeks = 3
    static let monotonyThreshold = 2.0

    static func sessionAU(effort: Int, durationMin: Double) -> Double {
        Double(effort) * durationMin
    }

    /// 월요일 00:00
    static func mondayStart(of date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.startOfDay(for: cal.date(from: comps) ?? date)
    }

    static func weekly(runs: [Run], weekStart: Date, calendar: Calendar = .current) -> WeekLoad? {
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
        let inWeek = runs.filter { $0.date >= weekStart && $0.date < weekEnd }
        guard !inWeek.isEmpty else { return nil }
        var daily = Array(repeating: 0.0, count: 7)
        var dailyEfforts = Array(repeating: [Int](), count: 7)
        var covered = 0
        var effortSum = 0
        for r in inWeek {
            guard let e = r.effort else { continue }
            let dayIdx = min(6, max(0, calendar.dateComponents([.day], from: weekStart, to: r.date).day ?? 0))
            daily[dayIdx] += sessionAU(effort: e, durationMin: r.durationMin)
            dailyEfforts[dayIdx].append(e)
            covered += 1
            effortSum += e
        }
        let dailyMean: [Double?] = dailyEfforts.map { $0.isEmpty ? nil : Double($0.reduce(0, +)) / Double($0.count) }
        return WeekLoad(weekStart: weekStart,
                        total: daily.reduce(0, +),
                        daily: daily,
                        dailyMeanEffort: dailyMean,
                        runCount: inWeek.count,
                        coveredCount: covered,
                        meanEffort: covered > 0 ? Double(effortSum) / Double(covered) : nil)
    }

    /// count주, 오래된→최신. 마지막 원소가 `endingAt` 주. 러닝 없는 주는 nil.
    static func weeks(runs: [Run], endingAt lastWeekStart: Date, count: Int, calendar: Calendar = .current) -> [WeekLoad?] {
        guard count > 0 else { return [] }
        return (0..<count).reversed().map { back in
            guard let ws = calendar.date(byAdding: .day, value: -7 * back, to: lastWeekStart) else { return nil }
            return weekly(runs: runs, weekStart: ws, calendar: calendar)
        }
    }

    /// 러닝 활동 → Run. 걷기·하이킹은 제외.
    static func runs(from activities: [Activity], index: EffortIndex) -> [Run] {
        activities.filter { $0.type == .running }
            .map { Run(date: $0.date, durationMin: $0.duration / 60, effort: index.resolve($0.id)?.value) }
    }

    /// 평균 ÷ 모표준편차(모집단 기준). 임계값 2.0은 이 정의(모표준편차)에 맞춰 고른 값이다. sd 0이면 nil.
    static func monotony(daily: [Double]) -> Double? {
        guard !daily.isEmpty else { return nil }
        let mean = daily.reduce(0, +) / Double(daily.count)
        let variance = daily.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(daily.count)
        let sd = variance.squareRoot()
        guard sd > 0 else { return nil }
        return mean / sd
    }

    static func ratioLabel(_ ratio: Double) -> RatioLabel {
        if ratio < 0.8 { return .low }
        if ratio <= 1.3 { return .steady }
        if ratio <= 1.5 { return .high }
        return .veryHigh
    }

    /// 이번 주 ÷ 직전 4주 평균. nil 주(러닝 없음)는 부하 0으로 세고, 러닝은 있는데 강도 커버리지 < 0.5인 주만 제외한다.
    /// 유효 주가 3개 이상이어야 한다.
    static func acuteChronic(current: WeekLoad, previous: [WeekLoad?]) -> (ratio: Double, label: RatioLabel)? {
        guard current.coverage >= minCoverage else { return nil }
        let valid: [Double] = previous.compactMap { w in
            guard let w else { return 0 }            // 러닝 없는 주 = 부하 0
            return w.coverage >= minCoverage ? w.total : nil
        }
        guard valid.count >= minChronicWeeks else { return nil }
        let chronic = valid.reduce(0, +) / Double(valid.count)
        guard chronic > 0 else { return nil }
        let r = current.total / chronic
        return (r, ratioLabel(r))
    }

    /// 지난주(바로 직전 주) 대비 증감률. 지난주에 러닝이 없거나 커버리지 미달이면 nil.
    static func weekOverWeek(current: WeekLoad, previous: WeekLoad?) -> Double? {
        guard let p = previous, p.coverage >= minCoverage, current.coverage >= minCoverage, p.total > 0 else { return nil }
        return current.total / p.total - 1
    }

    /// 카드 하단 문장 우선순위: 단조도 → 28일 비교(유지는 침묵) → nil
    static func sentenceKind(current: WeekLoad, previous: [WeekLoad?]) -> SentenceKind? {
        if current.coverage >= 1.0, let m = monotony(daily: current.daily), m >= monotonyThreshold {
            return .monotony
        }
        guard let ac = acuteChronic(current: current, previous: previous) else { return nil }
        switch ac.label {
        case .low:      return .low
        case .steady:   return nil
        case .high:     return .high
        case .veryHigh: return .veryHigh
        }
    }

    // MARK: 플래너 연동

    static func isRecoveryPhase(_ phase: String) -> Bool {
        phase == "회복" || phase == "테이퍼"
    }

    /// 이번 주 평균 강도가 최근 8주 강도 중앙값 + 1 이상 (커버리지 ≥ 0.5, 표본 3개 이상)
    static func recoveryWeekExceeds(meanEffort: Double?, coverage: Double, eightWeekEfforts: [Int]) -> Bool {
        guard let mean = meanEffort, coverage >= minCoverage, eightWeekEfforts.count >= 3 else { return false }
        let median = WorkoutTypeClassifier.median(eightWeekEfforts.map(Double.init))
        return mean >= median + 1
    }
}
