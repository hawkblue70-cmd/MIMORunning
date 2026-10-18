import Foundation

/// sRPE 부하(Foster 2001: RPE × 분) · 주간 합 · 단조도 · 7일/28일 비교 · 회복 주 판정.
/// 러닝만, 강도 있는 런만 합산. "부상·위험" 표현은 쓰지 않는다(Impellizzeri 2020).
enum EffortLoad {

    struct Run {
        let date: Date
        let durationMin: Double
        let effort: Int?          // nil = 강도 없음 → 부하 미합산, runCount에는 포함
        /// 거리(km) — 부하 비율의 절대량 안전장치(최근 7일 거리가 지난 12주 최고 주간 거리 아래면 '크게 높음' 한 단계 낮춤)
        var distanceKm: Double? = nil
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
            .map { Run(date: $0.date, durationMin: $0.duration / 60, effort: index.resolve($0.id)?.value,
                       distanceKm: $0.distance / 1000) }
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

    // MARK: 롤링 창(최근 7일)

    /// 롤링 창 부하 — `end`(exclusive, 보통 오늘 자정+1일)에서 `days`일 전까지. 러닝이 없어도 nil이 아니다(부하 0, runCount 0).
    struct WindowLoad: Equatable {
        let start: Date                 // 창 시작(자정)
        let end: Date                   // 창 끝(exclusive)
        let dayStarts: [Date]           // 각 일자의 자정, 오래된→최신
        let daily: [Double]             // AU
        let dailyMeanEffort: [Double?]
        let runCount: Int
        let coveredCount: Int
        let total: Double
        let meanEffort: Double?
        var coverage: Double { runCount == 0 ? 0 : Double(coveredCount) / Double(runCount) }
    }

    static func window(runs: [Run], endingBefore end: Date, days: Int = 7, calendar: Calendar = .current) -> WindowLoad {
        let endDay = calendar.startOfDay(for: end)
        let start = calendar.date(byAdding: .day, value: -days, to: endDay) ?? endDay
        let dayStarts: [Date] = (0..<days).map { calendar.date(byAdding: .day, value: $0, to: start) ?? start }
        let inWindow = runs.filter { $0.date >= start && $0.date < endDay }
        var daily = Array(repeating: 0.0, count: days)
        var dailyEfforts = Array(repeating: [Int](), count: days)
        var covered = 0
        var effortSum = 0
        for r in inWindow {
            guard let e = r.effort else { continue }
            let idx = min(days - 1, max(0, calendar.dateComponents([.day], from: start, to: r.date).day ?? 0))
            daily[idx] += sessionAU(effort: e, durationMin: r.durationMin)
            dailyEfforts[idx].append(e)
            covered += 1
            effortSum += e
        }
        let dailyMean: [Double?] = dailyEfforts.map { $0.isEmpty ? nil : Double($0.reduce(0, +)) / Double($0.count) }
        return WindowLoad(start: start,
                          end: endDay,
                          dayStarts: dayStarts,
                          daily: daily,
                          dailyMeanEffort: dailyMean,
                          runCount: inWindow.count,
                          coveredCount: covered,
                          total: daily.reduce(0, +),
                          meanEffort: covered > 0 ? Double(effortSum) / Double(covered) : nil)
    }

    /// 오늘을 포함하는 최근 7일(자정 기준: [today−6d 00:00, tomorrow 00:00))
    static func lastSevenDays(runs: [Run], asOf: Date, calendar: Calendar = .current) -> WindowLoad {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: asOf)) ?? asOf
        return window(runs: runs, endingBefore: tomorrow, days: 7, calendar: calendar)
    }

    /// 직전 7일(최근 7일 바로 앞)
    static func previousSevenDays(runs: [Run], asOf: Date, calendar: Calendar = .current) -> WindowLoad {
        let current = lastSevenDays(runs: runs, asOf: asOf, calendar: calendar)
        return window(runs: runs, endingBefore: current.start, days: 7, calendar: calendar)
    }

    /// 롤링 7일 대 이전 4×7일. 이전 창 중 runCount == 0 → 부하 0으로 유효, 러닝은 있는데 coverage < 0.5 → 제외.
    /// 유효 3개 이상, 이번 창 coverage ≥ 0.5.
    static func rollingAcuteChronic(runs: [Run], asOf: Date, calendar: Calendar = .current) -> (ratio: Double, label: RatioLabel)? {
        let current = lastSevenDays(runs: runs, asOf: asOf, calendar: calendar)
        guard current.coverage >= minCoverage else { return nil }
        var end = current.start
        var valid: [Double] = []
        for _ in 0..<4 {
            let w = window(runs: runs, endingBefore: end, days: 7, calendar: calendar)
            if w.runCount == 0 {
                valid.append(0)                       // 러닝 없는 창 = 부하 0
            } else if w.coverage >= minCoverage {
                valid.append(w.total)
            }
            end = w.start
        }
        guard valid.count >= minChronicWeeks else { return nil }
        let chronic = valid.reduce(0, +) / Double(valid.count)
        guard chronic > 0 else { return nil }
        let r = current.total / chronic
        return (r, ratioLabel(r))
    }

    // MARK: 지수 가중 부하 비율 (2026-10-19)

    /// 부하 비율 결과 — 라벨과 함께 근거에 적을 주간 환산 값(AU/주).
    struct LoadRatio: Equatable {
        let ratio: Double
        let label: RatioLabel
        /// 최근 흐름(7일 지수 가중 평균 × 7)
        let acuteWeeklyAU: Double
        /// 지난 4주 흐름(28일 지수 가중 평균 × 7)
        let chronicWeeklyAU: Double
        /// 절대량 안전장치로 '크게 높음'에서 한 단계 내려왔는가
        let cappedByMaxWeek: Bool
    }

    /// 7일·4주 지수 가중 평균(EWMA, Williams 2017: λ = 2/(N+1)) 비율.
    /// ⚠ 예전 롤링 창(최근 7일 합 ÷ 이전 4×7일 평균)은 큰 하루가 7일 창에 있는 동안 매일 같은 '크게 높음'을 내다가
    ///   7일째 창에서 빠지는 날 비율이 뚝 떨어졌다 — 큰 날 뒤 한 주 내내 "1~2일 쉬세요"가 반복됐다(2026-10-19 사용자 검토).
    ///   지수 가중은 지난 날의 무게가 매일 조금씩 줄어 절벽이 없다.
    /// 자료: 첫 기록이 21일 이상 전이어야 한다(`ewma`). 최근 7일 강도 커버리지 0.5 미만이면 nil.
    /// 절대량 안전장치: '크게 높음'인데 최근 7일 거리가 지난 12주(최근 7일 제외) 최고 7일 거리 이하면 '높음'으로 —
    ///   쉬었다 돌아와 기준이 낮아진 뒤의 평범한 주가 과하게 울리지 않게.
    static func loadRatio(runs: [Run], asOf: Date, calendar: Calendar = .current) -> LoadRatio? {
        let current = lastSevenDays(runs: runs, asOf: asOf, calendar: calendar)
        guard current.coverage >= minCoverage else { return nil }
        guard let daily = dailySeries(runs: runs, asOf: asOf, calendar: calendar, value: { r in
            r.effort.map { sessionAU(effort: $0, durationMin: r.durationMin) }
        }), let (acute, chronic) = ewma(daily: daily) else { return nil }
        guard chronic > 0 else { return nil }
        let r = acute / chronic
        var label = ratioLabel(r)
        var capped = false
        if label == .veryHigh {
            let km = { (w: WindowLoad) -> Double in
                runs.filter { $0.date >= w.start && $0.date < w.end }.compactMap(\.distanceKm).reduce(0, +)
            }
            let curKm = km(current)
            var end = current.start
            var maxKm = 0.0
            for _ in 0..<78 {   // 12주 동안 하루씩 밀며 7일 창 거리의 최댓값
                let w = window(runs: runs, endingBefore: end, days: 7, calendar: calendar)
                maxKm = max(maxKm, km(w))
                end = calendar.date(byAdding: .day, value: -1, to: end) ?? w.start
            }
            if curKm > 0, maxKm > 0, curKm <= maxKm { label = .high; capped = true }
        }
        return LoadRatio(ratio: r, label: label, acuteWeeklyAU: acute * 7, chronicWeeklyAU: chronic * 7, cappedByMaxWeek: capped)
    }

    /// 오늘로 끝나는 일별 값(최대 84일, 오래된→최신). 첫 기록이 21일 이상 전이 아니면 nil.
    /// `value`가 nil인 러닝(강도 없음)은 0으로 — 롤링 창과 같은 규칙. 아침 제안(분)·총평(AU)이 같이 쓴다.
    static func dailySeries<R>(runs: [R], asOf: Date, calendar: Calendar = .current,
                               date: (R) -> Date, value: (R) -> Double?) -> [Double]? {
        let today = calendar.startOfDay(for: asOf)
        guard let first = runs.map(date).min().map({ calendar.startOfDay(for: $0) }),
              let need = calendar.date(byAdding: .day, value: -21, to: today), first <= need else { return nil }
        let day0 = max(first, calendar.date(byAdding: .day, value: -83, to: today) ?? first)
        let n = (calendar.dateComponents([.day], from: day0, to: today).day ?? 0) + 1
        guard n >= 22 else { return nil }
        var daily = Array(repeating: 0.0, count: n)
        for r in runs {
            guard let v = value(r) else { continue }
            let i = calendar.dateComponents([.day], from: day0, to: calendar.startOfDay(for: date(r))).day ?? -1
            if i >= 0 && i < n { daily[i] += v }
        }
        return daily
    }
    static func dailySeries(runs: [Run], asOf: Date, calendar: Calendar = .current, value: (Run) -> Double?) -> [Double]? {
        dailySeries(runs: runs, asOf: asOf, calendar: calendar, date: { $0.date }, value: value)
    }

    /// 7일·28일 지수 가중 평균(일 단위) — 아침 제안과 총평이 같은 함수(λ = 2/(N+1)).
    /// 마지막 7일은 반드시 굴리도록, 앞쪽(최대 28일) 평균으로 두 평균을 함께 시작한다. 22일 미만이면 nil.
    static func ewma(daily: [Double]) -> (acute: Double, chronic: Double)? {
        let n = daily.count
        guard n >= 22 else { return nil }
        let seedEnd = min(28, n - 7)
        let seed = daily[0..<seedEnd].reduce(0, +) / Double(seedEnd)
        var acute = seed, chronic = seed
        let la = 2.0 / 8.0, lc = 2.0 / 29.0
        for i in seedEnd..<n {
            acute = la * daily[i] + (1 - la) * acute
            chronic = lc * daily[i] + (1 - lc) * chronic
        }
        return (acute, chronic)
    }

    /// 하루 전 기준 지수 가중 비율 — 총평 훈련부하 줄의 저장 없는 히스테리시스용.
    static func loadRatioYesterday(runs: [Run], asOf: Date, calendar: Calendar = .current) -> LoadRatio? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: asOf) else { return nil }
        return loadRatio(runs: runs, asOf: yesterday, calendar: calendar)
    }

    /// 하루 전 기준(asOf −1일)의 롤링 4주 평균 대비 — 총평 훈련부하 줄의 저장 없는 히스테리시스용.
    /// 오늘 창에서 8일 전 고강도 하루가 빠져 라벨이 내려온 날을 "회복 완료"로 오판하지 않게 어제 라벨을 함께 본다.
    static func rollingAcuteChronicYesterday(runs: [Run], asOf: Date, calendar: Calendar = .current) -> (ratio: Double, label: RatioLabel)? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: asOf) else { return nil }
        return rollingAcuteChronic(runs: runs, asOf: yesterday, calendar: calendar)
    }

    /// 최근 7일 vs 직전 7일 증감. 두 창 모두 coverage ≥ 0.5, 직전 총합 > 0.
    static func rollingWeekOverWeek(runs: [Run], asOf: Date, calendar: Calendar = .current) -> Double? {
        let current = lastSevenDays(runs: runs, asOf: asOf, calendar: calendar)
        let previous = previousSevenDays(runs: runs, asOf: asOf, calendar: calendar)
        guard current.coverage >= minCoverage, previous.coverage >= minCoverage, previous.total > 0 else { return nil }
        return current.total / previous.total - 1
    }

    /// 우선순위: 단조도(최근 7일 daily, coverage == 1, ≥ 2.0) → 롤링 28일 비율(유지는 nil)
    static func rollingSentenceKind(runs: [Run], asOf: Date, calendar: Calendar = .current) -> SentenceKind? {
        let current = lastSevenDays(runs: runs, asOf: asOf, calendar: calendar)
        if current.coverage >= 1.0, let m = monotony(daily: current.daily), m >= monotonyThreshold {
            return .monotony
        }
        guard let ac = loadRatio(runs: runs, asOf: asOf, calendar: calendar) else { return nil }
        switch ac.label {
        case .low:      return .low
        case .steady:   return nil
        case .high:     return .high
        case .veryHigh: return .veryHigh
        }
    }

    /// 카드용 묶음
    struct RollingSummary: Equatable {
        let current: WindowLoad
        let previous: WindowLoad
        let weekOverWeek: Double?
        let sentence: SentenceKind?
    }

    static func rollingSummary(runs: [Run], asOf: Date, calendar: Calendar = .current) -> RollingSummary {
        RollingSummary(current: lastSevenDays(runs: runs, asOf: asOf, calendar: calendar),
                       previous: previousSevenDays(runs: runs, asOf: asOf, calendar: calendar),
                       weekOverWeek: rollingWeekOverWeek(runs: runs, asOf: asOf, calendar: calendar),
                       sentence: rollingSentenceKind(runs: runs, asOf: asOf, calendar: calendar))
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
