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
    static let lastNightLowSD = 1.0
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
    var acute = 0.0, chronic = 0.0, previous = 0.0
    for w in runs {
        let d = calendar.dateComponents([.day], from: w.date, to: today).day ?? Int.min
        if d >= 0 && d <= 6 { acute += w.durationMin }
        else if d >= 7 && d <= 34 {
            chronic += w.durationMin
            if d <= 13 { previous += w.durationMin }
        }
    }
    let ratio: Double? = chronic > 0 ? acute / (chronic / 4) : nil
    let rising = previous > 0 && acute >= previous * MRReadiness.risingRatio
    return (ratio, rising)
}

func mrReadiness(runs: [MRWorkout], phys: MRPhysiology, heatHR: MRHeatHRModel,
                 hrvNights: [(date: Date, value: Double)], planPhase: String?,
                 asOf: Date, calendar: Calendar = .current) -> MRReadiness? {
    let L = AppLanguage.shared
    let today = calendar.startOfDay(for: asOf)
    guard !runs.isEmpty else { return nil }
    // 규칙 0 — 이미 뛴 날은 제안하지 않는다(오늘 기록 줄이 주인공)
    if runs.contains(where: { calendar.isDate($0.start, inSameDayAs: asOf) }) { return nil }

    let hard = mrRecentHardRunCount(runs: runs, phys: phys, heatHR: heatHR, days: 14, asOf: asOf, calendar: calendar)
    let consecutive = mrConsecutiveRunDays(runs: runs, asOf: asOf, calendar: calendar)
    let load = mrDurationAcuteChronic(runs: runs, asOf: asOf, calendar: calendar)
    let trend = mrHRVTrend(nights: hrvNights, asOf: asOf, calendar: calendar)
    let todayNight = hrvNights.last.flatMap { calendar.isDate($0.date, inSameDayAs: today) ? $0.value : nil }
    let pending = todayNight == nil
    let lastNightLow: Bool = {
        guard let t = trend, let v = todayNight else { return false }
        let sdEff = max(t.baselineSD, t.baseline * MRHRVTrend.sdFloorFraction)
        return v < t.baseline - MRReadiness.lastNightLowSD * sdEff
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
    // 규칙 3 — HRV 억제 · 어젯밤 유독 낮음
    if let t = trend, t.isSuppressed {
        return make(.rest, [t.isVolatile ? L.s("HRV 불안정", "HRV unstable") : L.s("HRV 낮음", "HRV low")])
    }
    if lastNightLow { return make(.rest, [L.s("어젯밤 HRV 유독 낮음", "last night's HRV unusually low")]) }
    // 규칙 4 — 어제 고강도
    if let d = hard.lastHardDaysAgo, d <= 1 { return make(.easy, [L.s("어제 고강도", "hard run yesterday")]) }
    // 규칙 5 — 부하 오르는 중(HRV가 좋으면 통과)
    let ready = trend?.isReadyHigh == true
    if load.rising && !ready { return make(.easy, [L.s("부하 오르는 중", "load rising")]) }
    // 규칙 6 — HRV 좋음
    if ready { return make(.go, [L.s("HRV 좋음", "HRV good")] + [lastHardPiece()].compactMap { $0 }) }
    // 규칙 7 — 범위 안 또는 자료 없음: 부하 쪽이 넉넉할 때만 강도 OK
    let roomy = hard.lastHardDaysAgo.map { $0 >= MRReadiness.normalHRVGoMinDays } ?? true
    if roomy {
        var reasons: [String] = []
        if trend != nil { reasons.append(L.s("HRV 보통", "HRV normal")) }
        if let p = lastHardPiece() { reasons.append(p) }
        return make(.go, reasons)
    }
    let d = hard.lastHardDaysAgo ?? 0
    return make(.easy, [L.s("고강도 \(d)일 전", "hard run \(d) days ago"), L.s("하루 더 여유", "one more easy day")])
}
