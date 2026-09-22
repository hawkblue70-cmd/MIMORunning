import Foundation

// MARK: - 아침 러닝 제안 (오늘 강도 게이트)
//
// HRV 기반 훈련 연구(Vesterinen 2016, Javaloyes 2019)는 아침 값으로 그날 강도를 정한다 —
// 정상 범위 안이면 계획대로, 아래면 저강도·휴식. HRV는 종류(인터벌/템포)를 고르지 않는다.
// 이 판정은 "오늘 강도를 내도 되는가"만 답한다. 제안이지 지시가 아니다.

struct MRReadiness: Equatable {
    enum Level: Equatable { case go, easy, rest }
    let level: Level
    /// 근거 조각 — 순서대로 " · "로 이어 붙인다
    let reasons: [String]
    /// 오늘 키의 밤이 아직 없다(워치 동기화 전) — 판정은 어제까지 자료로 그대로 한다
    let hrvPending: Bool

    var line: String {
        let L = AppLanguage.shared
        let head: String
        switch level {
        case .go:   head = L.s("오늘은 강도 OK", "Today: hard is OK")
        case .easy: head = L.s("오늘은 이지런", "Today: easy run")
        case .rest: head = L.s("오늘은 휴식이나 짧은 이지", "Today: rest or a short easy run")
        }
        var parts = [head] + reasons
        if hrvPending { parts.append(L.s("어젯밤 HRV 동기화 전", "last night's HRV not synced yet")) }
        return parts.joined(separator: " · ")
    }

    static let spikeRatio = 1.3
    static let risingRatio = 1.15
    static let restConsecutiveDays = 4
    /// 범위 안 HRV에서 강도 OK로 보는 마지막 고강도 최소 일수
    static let normalHRVGoMinDays = 3
    /// 어젯밤 단일 값이 "유독 낮음"인 기준 — 기준선 − 1.0 × SD_eff
    /// 어젯밤 한 밤을 "낮음"으로 보는 문턱 — 기준선 − max(1.5·SD, 기준선의 15%).
    /// 1.0·SD(하한 10%)는 기준선 25ms에서 3~4ms 낮은 밤도 걸렸는데, 그 폭은 하룻밤 잡음 안이다(2026-09-22 사용자 결정).
    static let lastNightLowSD = 1.5
    static let lastNightLowMinFraction = 0.15

    /// 어젯밤 한 밤이 4주 기준선에서 얼마나 벗어났나 — −1 낮음 · 0 평소 범위 · +1 높음. 아침 제안과 총평 근거가 같은 규칙을 쓴다.
    static func lastNightDeviation(_ v: Double, trend t: MRHRVTrend) -> Int {
        let sdEff = max(t.baselineSD, t.baseline * MRHRVTrend.sdFloorFraction)
        let drop = max(lastNightLowSD * sdEff, t.baseline * lastNightLowMinFraction)
        if v < t.baseline - drop { return -1 }
        if v > t.baseline + drop { return 1 }
        return 0
    }
}

/// 오늘 또는 어제로 끝나는 연속 러닝 일수. 오늘·어제 모두 러닝이 없으면 0.
func mrConsecutiveRunDays(runs: [MRWorkout], asOf: Date, calendar: Calendar = .current) -> Int {
    let today = calendar.startOfDay(for: asOf)
    let days = Set(runs.map { calendar.dateComponents([.day], from: $0.date, to: today).day ?? Int.min })
    var cursor = days.contains(0) ? 0 : (days.contains(1) ? 1 : -1)
    guard cursor >= 0 else { return 0 }
    var n = 0
    while days.contains(cursor) { n += 1; cursor += 1 }
    return n
}

/// 분 기준 급성:만성 — 최근 7일 분 합 ÷ (직전 28일(−34…−7) 분 합 ÷ 4). 28일에 러닝이 없으면 ratio nil.
/// `rising` = 최근 7일 ≥ 직전 7일(−13…−7) × 1.15 (직전 7일이 0이면 false).
func mrDurationAcuteChronic(runs: [MRWorkout], asOf: Date,
                            calendar: Calendar = .current) -> (ratio: Double?, rising: Bool) {
    let today = calendar.startOfDay(for: asOf)
    var acute = 0.0, previous = 0.0
    var weekly = [0.0, 0.0, 0.0, 0.0]   // 7…13 / 14…20 / 21…27 / 28…34
    for w in runs {
        let d = calendar.dateComponents([.day], from: w.date, to: today).day ?? Int.min
        if d >= 0 && d <= 6 { acute += w.durationMin }
        else if d >= 7 && d <= 34 {
            weekly[(d - 7) / 7] += w.durationMin
            if d <= 13 { previous += w.durationMin }
        }
    }
    // 만성은 4주 중 3주 이상 러닝이 있어야 센다(EffortLoad.minChronicWeeks와 같은 규칙). 빈 주는 0으로 넣어 4로 나눈다 —
    // 한 주가 비면 평균이 깎여 평소 부하도 급증처럼 보이므로, 자료가 모자라면 아예 판정하지 않는다.
    let validWeeks = weekly.filter { $0 > 0 }.count
    let chronic = weekly.reduce(0, +)
    let ratio: Double? = (validWeeks >= 3 && chronic > 0) ? acute / (chronic / 4) : nil
    let rising = previous > 0 && acute >= previous * MRReadiness.risingRatio
    return (ratio, rising)
}

func mrReadiness(runs: [MRWorkout], phys: MRPhysiology, heatHR: MRHeatHRModel,
                 hrvNights: [(date: Date, value: Double)], planPhase: String?,
                 asOf: Date, hardRunStarts: Set<Date> = [],
                 calendar: Calendar = .current) -> MRReadiness? {
    let L = AppLanguage.shared
    let today = calendar.startOfDay(for: asOf)
    guard !runs.isEmpty else { return nil }
    // 규칙 0 — 이미 뛴 날은 제안하지 않는다(오늘 기록 줄이 주인공)
    if runs.contains(where: { calendar.isDate($0.start, inSameDayAs: asOf) }) { return nil }

    let hard = mrRecentHardRunCount(runs: runs, phys: phys, heatHR: heatHR, days: 14, asOf: asOf,
                                    extraHardStarts: hardRunStarts, calendar: calendar)
    let consecutive = mrConsecutiveRunDays(runs: runs, asOf: asOf, calendar: calendar)
    let load = mrDurationAcuteChronic(runs: runs, asOf: asOf, calendar: calendar)
    let trend = mrHRVTrend(nights: hrvNights, asOf: asOf, calendar: calendar)
    // 마지막 원소가 아니라 '오늘 키'를 찾는다 — 낮 15시 이후 샘플은 내일 키로 묶이므로 last가 내일일 수 있다
    let todayNight = hrvNights.last(where: { calendar.isDate($0.date, inSameDayAs: today) })?.value
    // "동기화 전"은 HRV 자료가 있는 사용자에게만 — 자료가 아예 없으면 HRV를 말하지 않는다
    let pending = !hrvNights.isEmpty && todayNight == nil
    let lastNightLow: Bool = {
        guard let t = trend, let v = todayNight else { return false }
        return MRReadiness.lastNightDeviation(v, trend: t) < 0
    }()

    func lastHardPiece() -> String? {
        guard let d = hard.lastHardDaysAgo else { return nil }
        return L.s("마지막 고강도 \(d)일 전", "last hard run \(d) days ago")
    }
    func make(_ level: MRReadiness.Level, _ reasons: [String]) -> MRReadiness {
        MRReadiness(level: level, reasons: reasons, hrvPending: pending)
    }

    // 규칙 1 — 대회 계획의 회복·테이퍼 주
    if planPhase == "회복" { return make(.easy, [L.s("대회 계획 회복 주", "race plan: recovery week")]) }
    if planPhase == "테이퍼" { return make(.easy, [L.s("대회 계획 테이퍼 주", "race plan: taper week")]) }
    // 규칙 2 — 부하 급증 · 장기 연속
    if let r = load.ratio, r > MRReadiness.spikeRatio { return make(.rest, [L.s("부하 급증", "load spike")]) }
    if consecutive >= MRReadiness.restConsecutiveDays {
        return make(.rest, [L.s("\(consecutive)일 연속", "\(consecutive) days in a row")])
    }
    // 규칙 3 — HRV 억제 · 어젯밤 유독 낮음. 어제 고강도였으면 그 사실을 앞에 붙인다 — 고강도 다음 밤 HRV가 눌리는 건
    // 정상 반응이라, 원인을 같이 말해야 "몸에 문제가 있나" 하고 놀라지 않는다. 판정(휴식)은 그대로.
    let hardYesterday: [String] = (hard.lastHardDaysAgo.map { $0 <= 1 } ?? false)
        ? [L.s("어제 고강도", "hard run yesterday")] : []
    if let t = trend, t.isSuppressed {
        return make(.rest, hardYesterday + [t.isVolatile ? L.s("HRV 불안정", "HRV unstable") : L.s("HRV 낮음", "HRV low")])
    }
    // 7일이 고른데 어젯밤만 크게 떨어지면 변동계수도 같이 뛰어 위(불안정)에서 먼저 잡히는 일이 많다 — 여기는 4주가 원래 출렁이는 사람용
    if lastNightLow, let t = trend, let v = todayNight {
        // 숫자를 같이 적는다 — 저녁 총평 근거(7일·4주 평균)만 보면 한 밤의 하락이 보이지 않아 "매우 낮다더니 숫자는 같다"가 된다.
        // "유독"은 뺀다: 1표준편차(하한 기준선 10%)면 기준선 25ms에서 3~4ms 낮은 밤도 걸리는데, 그 폭은 하룻밤 잡음 안이다.
        let vStr = Int(v.rounded()), bStr = Int(t.baseline.rounded())
        return make(.rest, hardYesterday + [L.s("어젯밤 HRV \(vStr)ms, 4주 \(bStr)ms보다 낮음",
                                                "last night's HRV \(vStr)ms, below 4-wk \(bStr)ms")])
    }
    // 규칙 4 — 어제 고강도
    if let d = hard.lastHardDaysAgo, d <= 1 { return make(.easy, [L.s("어제 고강도", "hard run yesterday")]) }
    // 규칙 5 — 부하 오르는 중(HRV가 좋으면 통과)
    let ready = trend?.isReadyHigh == true
    if load.rising && !ready { return make(.easy, [L.s("부하 오르는 중", "load rising")]) }
    // 규칙 6 — HRV 좋음
    if ready { return make(.go, [L.s("HRV 좋음", "HRV good")] + [lastHardPiece()].compactMap { $0 }) }
    // 규칙 7 — 범위 안 또는 자료 없음: 부하 쪽이 넉넉할 때만 강도 OK
    if let d = hard.lastHardDaysAgo, d < MRReadiness.normalHRVGoMinDays {
        return make(.easy, [L.s("고강도 \(d)일 전", "hard run \(d) days ago"), L.s("하루 더 여유", "one more easy day")])
    }
    var reasons: [String] = []
    if trend != nil { reasons.append(L.s("HRV 보통", "HRV normal")) }
    if let p = lastHardPiece() { reasons.append(p) }
    return make(.go, reasons)
}
