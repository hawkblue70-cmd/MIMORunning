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
    /// 왜 그 판정인지 한두 문장 — 둘째 줄 앞부분
    var why: String = ""
    /// 판정과 무관하게 항상 보여주는 데이터 조각(HRV 어젯밤·이번 주·평소, 마지막 고강도, 연속일) — 둘째 줄 뒷부분
    var data: [String] = []

    /// 대회 훈련 계획이 있을 때 오늘 세션 — "롱런 14km, 마지막 15분 5'22"" / "이지 8km". 없으면 nil.
    var session: String? = nil
    /// 이번 주 계획 진행 — "이번 주 롱런 아직 · 이지 2/3회". 둘째 줄과 떨어진 셋째 줄(`planLine`)로 그린다.
    var progress: String? = nil
    /// 세션이 롱런인가 — 강도 OK인데 이지를 권하는 날은 판정 줄을 "오늘은 이지 Nkm · 강도 여유 있음"으로 바꾼다
    var sessionIsLongRun: Bool = false

    /// 둘째 줄 — "왜" 문장 뒤에 데이터 조각을 " · "로 붙인다(계획 진행은 셋째 줄로 따로)
    var detail: String {
        data.isEmpty ? why : (why.isEmpty ? data.joined(separator: " · ") : why + " " + data.joined(separator: " · "))
    }

    /// 셋째 줄 — 이번 주 계획 진행. 계획이 없으면 nil.
    var planLine: String? { progress }

    var line: String {
        let L = AppLanguage.shared
        let head: String
        switch level {
        case .go:   head = L.s("오늘은 강도 OK", "Today: hard is OK")
        case .easy: head = L.s("오늘은 이지런", "Today: easy run")
        case .rest: head = L.s("오늘은 휴식이나 짧은 이지", "Today: rest or a short easy run")
        }
        // 세션이 있으면 판정어 · 세션 — 근거는 둘째 줄의 "왜" 문장이 이미 담고 있다.
        // 강도 OK인데 오늘 세션이 이지면 "강도 OK · 이지"가 앞뒤로 부딪힌다 → "오늘은 이지 Nkm · 강도 여유 있음"
        var parts: [String]
        if level == .go, let sess = session, !sessionIsLongRun {
            parts = [L.s("오늘은 \(sess)", "Today: \(sess)"), L.s("강도 여유 있음", "room for intensity")]
        } else {
            parts = session.map { [head, $0] } ?? ([head] + reasons)
        }
        if hrvPending { parts.append(L.s("어젯밤 HRV 동기화 전", "last night's HRV not synced yet")) }
        return parts.joined(separator: " · ")
    }

    static let spikeRatio = 1.3
    static let risingRatio = 1.15
    /// 연속 러닝 일수 문턱의 하한·상한 — 실제 문턱은 본인 평소 연속일 + 1을 이 사이로 자른다(`mrConsecutiveThreshold`)
    static let consecutiveThresholdMin = 4
    static let consecutiveThresholdMax = 6
    /// 범위 안 HRV에서 강도 OK로 보는 마지막 고강도 최소 일수
    static let normalHRVGoMinDays = 3
    /// 어젯밤 단일 값이 "유독 낮음"인 기준 — 기준선 − 1.0 × SD_eff
    /// 어젯밤 한 밤을 "낮음/높음"으로 보는 문턱 — 4주 기준선의 ±15%. 표준편차는 쓰지 않는다:
    /// 4주가 원래 출렁이는 사람(SD 4.5 on 25ms)은 1.5·SD가 27%라 19ms(−24%)도 "보통"이 되고,
    /// 아주 고른 사람은 1·SD가 2~3ms라 잡음도 걸렸다. 비율 하나가 두 경우 모두 설명이 된다(2026-09-22 사용자 결정).
    static let lastNightDeviationFraction = 0.15

    /// 어젯밤 한 밤이 4주 기준선에서 얼마나 벗어났나 — −1 낮음 · 0 평소 범위 · +1 높음. 아침 제안과 총평 근거가 같은 규칙을 쓴다.
    static func lastNightDeviation(_ v: Double, trend t: MRHRVTrend) -> Int {
        guard t.baseline > 0 else { return 0 }
        let ratio = (v - t.baseline) / t.baseline
        if ratio < -lastNightDeviationFraction { return -1 }
        if ratio > lastNightDeviationFraction { return 1 }
        return 0
    }
}

// MARK: - 대회 훈련 계획의 이번 주 구성 → 오늘 세션

/// 스토어가 `governingPlanWeek`에서 조립해 넘기는 이번 주 계획. 플랜은 주 단위라 요일 배정이 없다 —
/// "오늘 무엇"은 이번 주에 남은 것 + 오늘 판정 + 본인 롱런 요일 습관으로 추론한다.
struct MRPlanWeekContext: Equatable {
    let phase: String
    let longRunKm: Double
    let weeklyKm: Double
    /// 이지 횟수 — 본인 최근 4주 빈도에서 max(round(n) − 1, 1)
    let easyRuns: Int
    /// 대회 페이스 주일 때만(예측 기록 기준, 목표 기록이 아니다)
    let racePaceSecPerKm: Double?
    let racePaceSegmentMin: Int?
    let daysToRace: Int
    /// 훈련일지에 보이는 이지 1회 거리 — 있으면 계산값 대신 이걸 쓴다(두 화면 숫자가 같아야 한다)
    var easyKm: Double? = nil

    static let longRunDoneFraction = 0.8
    /// 대회 주(D-7 이내)는 D-day 카드가 담당 — 두 카드가 다른 말을 하면 안 된다
    static let raceWeekDays = 7
}

struct MRSessionSuggestion: Equatable {
    let session: String?
    let progress: String
    var isLongRun: Bool = false
    /// "왜" 문장 뒤에 덧붙일 한 문장 — 강도 여유가 있는데 이지를 권하는 날, 그 여유를 어디에 쓸지
    var whyNote: String? = nil
}

/// 요일 이름(Gregorian 1=일…7=토)
func mrWeekdayName(_ wd: Int) -> String {
    let ko = ["일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"]
    let en = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    let i = min(max(wd - 1, 0), 6)
    return AppLanguage.shared.s(ko[i], en[i])
}

/// 훈련일지 이번 주 문구("롱런 19km + 이지 6.4km × 4회", "… + 이지 4회", "짧게 5km × 3회", 영어 "Easy 6.4km × 4x")에서
/// 이지 횟수·1회 거리를 읽는다. 계획이 만들어질 때의 러닝 빈도로 적힌 숫자라, 오늘 빈도로 다시 계산하면 어긋난다.
func mrParsePlanBreakdown(_ text: String) -> (easyRuns: Int?, easyKm: Double?) {
    func lastMatch(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        return (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }
    // "이지 6.4km × 4회" / "짧게 5km × 3회" / "Easy 6.4km × 4x"
    if let g = lastMatch(#"(?:이지|짧게|Easy|Short) ([0-9]+(?:\.[0-9]+)?)km × ([0-9]+)(?:회|x)"#), g.count == 2 {
        return (Int(g[1]), Double(g[0]))
    }
    // "이지 4회" / "Easy 4x"
    if let g = lastMatch(#"(?:이지|Easy) ([0-9]+)(?:회|x)"#), g.count == 1 {
        return (Int(g[0]), nil)
    }
    return (nil, nil)
}

/// 최근 8주(이번 주 제외)에서 러닝 2회 이상인 주의 최장 러닝 요일(Gregorian 1=일…7=토) 최빈값. 표본 3주 미만이면 nil.
func mrHabitualLongRunWeekday(runs: [MRWorkout], asOf: Date, calendar: Calendar = .current) -> Int? {
    let thisMonday = MRPlanGovernance.weekMonday(of: asOf, calendar: calendar)
    guard let from = calendar.date(byAdding: .day, value: -56, to: thisMonday) else { return nil }
    var byWeek: [Date: [MRWorkout]] = [:]
    for w in runs where w.start >= from && w.start < thisMonday {
        byWeek[MRPlanGovernance.weekMonday(of: w.start, calendar: calendar), default: []].append(w)
    }
    var counts: [Int: Int] = [:]
    for (_, ws) in byWeek where ws.count >= 2 {
        guard let longest = ws.max(by: { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }) else { continue }
        counts[calendar.component(.weekday, from: longest.start), default: 0] += 1
    }
    guard counts.values.reduce(0, +) >= 3 else { return nil }
    return counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
}

/// 오늘 판정 + 이번 주 계획 → 오늘 세션과 진행. 대회 주면 nil(D-day 카드 담당).
func mrSessionSuggestion(level: MRReadiness.Level, plan: MRPlanWeekContext, runs: [MRWorkout],
                         asOf: Date, calendar: Calendar = .current) -> MRSessionSuggestion? {
    let L = AppLanguage.shared
    guard plan.daysToRace > MRPlanWeekContext.raceWeekDays else { return nil }
    let today = calendar.startOfDay(for: asOf)
    let monday = MRPlanGovernance.weekMonday(of: asOf, calendar: calendar)
    guard let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) else { return nil }
    let week = runs.filter { $0.start >= monday && $0.start < nextMonday }
    let longDone = plan.longRunKm > 0 && week.contains { ($0.distanceKm ?? 0) >= plan.longRunKm * MRPlanWeekContext.longRunDoneFraction }
    let easyDone = min(max(week.count - (longDone ? 1 : 0), 0), plan.easyRuns)
    let daysLeft = max(7 - (calendar.dateComponents([.day], from: monday, to: today).day ?? 0), 1)   // 오늘 포함, 일요일이면 1
    let longLeft = plan.longRunKm > 0 && !longDone

    // 이지 1회 거리 — 훈련일지 문구에서 읽은 값이 우선
    let easyKm = plan.easyKm ?? (max(plan.weeklyKm - plan.longRunKm, 0) / Double(max(plan.easyRuns, 1)))
    // 일지와 같은 자릿수 — 정수면 "8km", 아니면 "6.4km"
    let easyKmStr = abs(easyKm - easyKm.rounded()) < 0.05 ? String(format: "%.0f", easyKm) : String(format: "%.1f", easyKm)
    let easyText = easyKm >= 1.5
        ? L.s("이지 \(easyKmStr)km", "Easy \(easyKmStr)km")
        : L.s("이지런", "Easy run")
    var longText = L.s("롱런 \(Int(plan.longRunKm.rounded()))km", "Long run \(Int(plan.longRunKm.rounded()))km")
    if let pace = plan.racePaceSecPerKm, let seg = plan.racePaceSegmentMin, pace > 0 {
        longText += L.s(", 마지막 \(seg)분 \(mrFormatPace(pace))", ", last \(seg) min at \(mrFormatPace(pace))")
    }

    // 진행
    var progress: [String] = []
    if plan.longRunKm > 0 {
        progress.append(longDone ? L.s("이번 주 롱런 완료", "long run done this week") : L.s("이번 주 롱런 아직", "long run still to do this week"))
    }
    progress.append(L.s("이지 \(easyDone)/\(plan.easyRuns)회", "easy \(easyDone)/\(plan.easyRuns)"))

    // 세션
    let allDone = !longLeft && easyDone >= plan.easyRuns
    if allDone {
        return MRSessionSuggestion(session: nil, progress: L.s("이번 주 계획 완료", "this week's plan is done"))
    }
    switch level {
    case .rest:
        if longLeft && daysLeft <= 2 {
            progress.append(L.s("롱런은 이번 주 못 하면 다음 주로", "if the long run doesn't fit this week, move it to next week"))
        }
        return MRSessionSuggestion(session: nil, progress: progress.joined(separator: " · "))
    case .go:
        let habitual = mrHabitualLongRunWeekday(runs: runs, asOf: asOf, calendar: calendar)
        let todayWD = calendar.component(.weekday, from: asOf)
        if longLeft && (habitual == todayWD || daysLeft <= 2) {
            return MRSessionSuggestion(session: longText, progress: progress.joined(separator: " · "), isLongRun: true)
        }
        // 강도 여유는 있지만 오늘은 롱런 날이 아니다 — 여유를 이번 주 롱런에 남겨 두라고 말한다
        let note: String? = longLeft
            ? (habitual.map { L.s("여유는 \(mrWeekdayName($0)) 롱런에 쓰세요.", "Save it for \(mrWeekdayName($0))'s long run.") }
               ?? L.s("여유는 이번 주 롱런에 쓰세요.", "Save it for this week's long run."))
            : nil
        return MRSessionSuggestion(session: easyText, progress: progress.joined(separator: " · "), whyNote: note)
    case .easy:
        if longLeft { progress.append(L.s("\(daysLeft)일 남음", "\(daysLeft) days left")) }
        return MRSessionSuggestion(session: easyText, progress: progress.joined(separator: " · "))
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

/// 최근 28일(오늘 제외)의 연속 러닝 구간 길이들의 중앙값 — 본인이 평소 며칠씩 이어 뛰는지. 구간이 2개 미만이면 nil.
/// 오늘로 이어지는 현재 구간은 뺀다(자기 자신으로 문턱을 올리지 않게).
func mrTypicalStreakDays(runs: [MRWorkout], asOf: Date, calendar: Calendar = .current) -> Int? {
    let today = calendar.startOfDay(for: asOf)
    let days = Set(runs.compactMap { w -> Int? in
        let d = calendar.dateComponents([.day], from: w.date, to: today).day ?? Int.min
        return (d >= 1 && d <= 28) ? d : nil
    })
    guard !days.isEmpty else { return nil }
    // 현재 구간(어제부터 이어지는 연속)은 제외
    var cursor = 1
    var current = Set<Int>()
    while days.contains(cursor) { current.insert(cursor); cursor += 1 }
    let past = days.subtracting(current)
    var lengths: [Int] = []
    var d = 28
    while d >= 1 {
        guard past.contains(d) else { d -= 1; continue }
        var n = 0
        while d >= 1 && past.contains(d) { n += 1; d -= 1 }
        lengths.append(n)
    }
    guard lengths.count >= 2 else { return nil }
    return Int(mrMedian(lengths.map(Double.init)).rounded())
}

/// 연속일 판정 문턱 — 본인 평소 연속일 + 1, 4~6일로 자른다. 평소 자료가 없으면 4.
func mrConsecutiveThreshold(typicalStreak: Int?) -> Int {
    guard let t = typicalStreak else { return MRReadiness.consecutiveThresholdMin }
    return min(MRReadiness.consecutiveThresholdMax, max(MRReadiness.consecutiveThresholdMin, t + 1))
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
                 planWeek: MRPlanWeekContext? = nil,
                 calendar: Calendar = .current) -> MRReadiness? {
    let L = AppLanguage.shared
    let today = calendar.startOfDay(for: asOf)
    guard !runs.isEmpty else { return nil }
    // 규칙 0 — 이미 뛴 날은 제안하지 않는다(오늘 기록 줄이 주인공)
    if runs.contains(where: { calendar.isDate($0.start, inSameDayAs: asOf) }) { return nil }

    let hard = mrRecentHardRunCount(runs: runs, phys: phys, heatHR: heatHR, days: 14, asOf: asOf,
                                    extraHardStarts: hardRunStarts, calendar: calendar)
    let consecutive = mrConsecutiveRunDays(runs: runs, asOf: asOf, calendar: calendar)
    let streakThreshold = mrConsecutiveThreshold(typicalStreak: mrTypicalStreakDays(runs: runs, asOf: asOf, calendar: calendar))
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

    // ── 데이터 조각 — 판정과 무관하게 둘째 줄에 항상. 총평 근거 줄과 같은 라벨(어젯밤·이번 주·평소·상태어).
    var data: [String] = []
    if let t = trend {
        let seven = Int(t.sevenDayMean.rounded()), base = Int(t.baseline.rounded())
        if let v = todayNight {
            let night = Int(v.rounded())
            let dev = MRReadiness.lastNightDeviation(v, trend: t)
            // 평소 범위일 때도 괄호를 붙인다 — 비어 있으면 "판정을 안 한 건가"로 읽힌다
            let note = dev < 0 ? L.s("(평소보다 낮음)", " (below usual)") : (dev > 0 ? L.s("(평소보다 높음)", " (above usual)") : L.s("(평소 범위)", " (usual range)"))
            // 상태어는 이번 주 판정 — 이번 주 숫자 바로 뒤 괄호(총평 근거 줄과 같은 형식)
            data.append(L.s("HRV 어젯밤 \(night)\(note) · 7일 평균 \(seven)(\(t.gradeLabel)) · 4주 평균 \(base)ms",
                            "HRV last night \(night)\(note) · 7-day avg \(seven) (\(t.gradeLabel)) · 4-wk avg \(base)ms"))
        } else {
            data.append(L.s("HRV 7일 평균 \(seven)(\(t.gradeLabel)) · 4주 평균 \(base)ms",
                            "HRV 7-day avg \(seven) (\(t.gradeLabel)) · 4-wk avg \(base)ms"))
        }
    }
    if let p = lastHardPiece() { data.append(p) }
    if consecutive >= 2 { data.append(L.s("\(consecutive)일 연속", "\(consecutive) days in a row")) }

    func make(_ level: MRReadiness.Level, _ reasons: [String], why: String) -> MRReadiness {
        var r = MRReadiness(level: level, reasons: reasons, hrvPending: pending)
        r.why = why
        r.data = data
        // 대회 훈련 계획이 있으면 오늘 세션·이번 주 진행을 붙인다 — 종류는 플랜이 정한다
        if let plan = planWeek, let s = mrSessionSuggestion(level: level, plan: plan, runs: runs, asOf: asOf, calendar: calendar) {
            r.session = s.session
            r.progress = s.progress
            r.sessionIsLongRun = s.isLongRun
            if let note = s.whyNote { r.why = r.why.isEmpty ? note : r.why + " " + note }
        }
        return r
    }

    // 규칙 1 — 대회 계획의 회복·테이퍼 주
    if planPhase == "회복" {
        return make(.easy, [L.s("대회 계획 회복 주", "race plan: recovery week")],
                    why: L.s("대회 계획상 이번 주는 부하를 낮추는 주예요. 이지런으로 다리를 아끼세요.",
                             "Your race plan has this as a recovery week. Keep it easy and save your legs."))
    }
    if planPhase == "테이퍼" {
        return make(.easy, [L.s("대회 계획 테이퍼 주", "race plan: taper week")],
                    why: L.s("대회 계획상 테이퍼 주예요. 강도보다 신선함이 남는 게 이득이에요.",
                             "Your race plan has this as a taper week. Freshness beats one more hard session."))
    }
    // 규칙 2 — 부하 급증 · 장기 연속
    if let r = load.ratio, r > MRReadiness.spikeRatio {
        let ratioStr = String(format: "%.1f", r)
        return make(.rest, [L.s("부하 급증", "load spike")],
                    why: L.s("최근 7일 부하가 평소의 \(ratioStr)배예요. 급히 늘린 부하는 쉬는 날에 흡수돼요.",
                             "Your last 7 days carry \(ratioStr)× your usual load. A sudden jump needs a rest day to absorb."))
    }
    // 연속일은 휴식이 아니라 강도를 빼라는 신호 — 이지런이면 괜찮다(2026-09-23 사용자 결정). 문턱은 본인 평소 연속일 + 1.
    if consecutive >= streakThreshold {
        return make(.easy, [L.s("\(consecutive)일 연속", "\(consecutive) days in a row")],
                    why: L.s("\(consecutive)일 내리 달렸어요. 평소보다 긴 연속이라 오늘은 강도를 빼고 이지런으로 가세요.",
                             "\(consecutive) days in a row — longer than your usual streak. Keep today easy and skip the intensity."))
    }
    // 규칙 3 — HRV 억제 · 어젯밤 유독 낮음. 어제 고강도였으면 그 사실을 앞에 붙인다 — 고강도 다음 밤 HRV가 눌리는 건
    // 정상 반응이라, 원인을 같이 말해야 "몸에 문제가 있나" 하고 놀라지 않는다. 판정(휴식)은 그대로.
    let wasHardYesterday = hard.lastHardDaysAgo.map { $0 <= 1 } ?? false
    let hardYesterday: [String] = wasHardYesterday ? [L.s("어제 고강도", "hard run yesterday")] : []
    let afterHardWhy = L.s("어제 고강도 뒤라 HRV가 눌린 건 정상 반응이에요. 오늘 쉬면 돌아와요.",
                           "HRV dips after a hard day — that's normal. A rest day brings it back.")
    if let t = trend, t.isSuppressed {
        let why = wasHardYesterday ? afterHardWhy : (t.isVolatile
            ? L.s("이번 주 HRV가 평소보다 크게 흔들려요. 몸이 아직 안정되지 않은 신호예요.",
                  "Your HRV is swinging far more than usual this week — a sign the body hasn't settled.")
            : L.s("이번 주 HRV가 평소 아래예요. 회복이 덜 된 신호라 강도는 미루는 게 좋아요.",
                  "Your HRV is below usual this week — recovery isn't done yet, so hold the hard session."))
        return make(.rest, hardYesterday + [t.isVolatile ? L.s("HRV 불안정", "HRV unstable") : L.s("HRV 낮음", "HRV low")], why: why)
    }
    // 7일이 고른데 어젯밤만 크게 떨어지면 변동계수도 같이 뛰어 위(불안정)에서 먼저 잡히는 일이 많다 — 여기는 4주가 원래 출렁이는 사람용
    if lastNightLow, let t = trend, let v = todayNight {
        // 숫자를 같이 적는다 — 저녁 총평 근거(7일·4주 평균)만 보면 한 밤의 하락이 보이지 않아 "매우 낮다더니 숫자는 같다"가 된다.
        // "유독"은 뺀다: 1표준편차(하한 기준선 10%)면 기준선 25ms에서 3~4ms 낮은 밤도 걸리는데, 그 폭은 하룻밤 잡음 안이다.
        let vStr = Int(v.rounded()), bStr = Int(t.baseline.rounded())
        let pct = Int(((t.baseline - v) / t.baseline * 100).rounded())
        let why = wasHardYesterday ? afterHardWhy
            : L.s("어젯밤 HRV가 평소보다 \(pct)% 낮아요. 하룻밤이지만 오늘은 가볍게 가는 편이 안전해요.",
                  "Last night's HRV was \(pct)% below usual. One night, but an easy day is the safer call.")
        return make(.rest, hardYesterday + [L.s("어젯밤 HRV \(vStr)ms, 평소 \(bStr)ms보다 낮음",
                                                "last night's HRV \(vStr)ms, below usual \(bStr)ms")], why: why)
    }
    // 규칙 4 — 어제 고강도
    if let d = hard.lastHardDaysAgo, d <= 1 {
        return make(.easy, [L.s("어제 고강도", "hard run yesterday")],
                    why: L.s("고강도 다음 날은 쉬운 날이어야 몸이 적응해요. 이틀 연속 강도는 피하세요.",
                             "The day after a hard session should be easy — that's when the body adapts. Avoid back-to-back hard days."))
    }
    // 규칙 5 — 부하 오르는 중(HRV가 좋으면 통과)
    let ready = trend?.isReadyHigh == true
    if load.rising && !ready {
        return make(.easy, [L.s("부하 오르는 중", "load rising")],
                    why: L.s("직전 7일보다 부하가 늘었어요. 여기에 강도까지 얹으면 급증이 돼요.",
                             "Load is up on the previous 7 days. Adding a hard session on top would make it a spike."))
    }
    // 규칙 6 — HRV 좋음
    if ready {
        return make(.go, [L.s("HRV 좋음", "HRV good")] + [lastHardPiece()].compactMap { $0 },
                    why: L.s("이번 주 HRV가 평소 위로 안정적이에요. 강도를 소화할 준비가 된 신호예요.",
                             "Your HRV is steadily above usual this week — a sign you're ready to absorb a hard session."))
    }
    // 규칙 7 — 범위 안 또는 자료 없음: 부하 쪽이 넉넉할 때만 강도 OK
    if let d = hard.lastHardDaysAgo, d < MRReadiness.normalHRVGoMinDays {
        return make(.easy, [L.s("고강도 \(d)일 전", "hard run \(d) days ago"), L.s("하루 더 여유", "one more easy day")],
                    why: L.s("고강도 뒤 사흘은 두는 게 좋아요. 그 사이 강도를 더하면 회복이 밀려요.",
                             "Leave about three days after a hard session. Stacking another one pushes recovery back."))
    }
    var reasons: [String] = []
    if trend != nil { reasons.append(L.s("HRV 보통", "HRV normal")) }
    if let p = lastHardPiece() { reasons.append(p) }
    let why = trend != nil
        ? L.s("HRV는 평소 범위이고 마지막 고강도도 충분히 지났어요. 계획한 강도를 넣어도 돼요.",
              "HRV is in your usual range and the last hard session is far enough back. Your planned hard session is fine.")
        : L.s("부하가 안정돼 있어요. 계획한 강도를 넣어도 돼요.",
              "Load is steady. Your planned hard session is fine.")
    return make(.go, reasons, why: why)
}
