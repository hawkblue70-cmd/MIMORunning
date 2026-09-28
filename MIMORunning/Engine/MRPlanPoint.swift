import Foundation

// MARK: - 포인트 훈련 (설계: docs/superpowers/specs/2026-09-29-plan-point-session-design.md)
//
// 한 주에 한 번, 강도를 의도적으로 올리는 날. 나머지는 이지.
// 강도 분리 자체의 근거: Stöggl & Sperlich 2014 (Front Physiol 5:33) — 9주 양극화 훈련이
//   역치 위주·고강도 위주·볼륨 위주보다 향상이 컸다.
// ⚠ 단계별 종류 배정·회수·거리는 코칭 관행이다. 통제 연구로 정해진 값이 아니다.
//   인터벌 빠른 구간 ≤ 주간 8% · 역치 구간 ≤ 주간 10%는 Daniels' Running Formula의 관행.

struct MRPlanPoint: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case speed, tempo, buildUp, racePaceShort }

    let kind: Kind
    /// 워밍업·쿨다운 포함 총 거리
    let totalKm: Double
    /// speed · racePaceShort 반복 횟수
    let reps: Int?
    /// 반복 1회 거리 (1.0)
    let repKm: Double?
    /// tempo 지속 거리 · buildUp 마지막 3분의 1
    let sustainedKm: Double?
    /// 빠른 구간 페이스 (초/km) — 예측 기록 기준, 기온 보정 전
    let paceSecPerKm: Double

    static let warmupKm = 2.0
    static let cooldownKm = 1.0
    /// 반복 사이 2분 조깅·400m — ⚠ 임의로 정함
    static let jogBetweenKm = 0.4

    /// 포인트로 세는 앱 저장 유형 — 고강도 판정(`RunSummaryBuilder.isHardRun`)의 종류 규칙과 같다.
    static let pointWorkoutTypes: Set<WorkoutType> = [.interval, .tempo, .buildUp, .distanceRun, .race]

    /// 종류와 이번 주 주간·롱런으로 양을 정한다. 만들 수 없으면 nil(페이스 없음·빌드업이 5km 미만).
    static func make(kind: Kind, weeklyKm: Double, longRunKm: Double,
                     raceDistanceM: Double?, paceSecPerKm: Double) -> MRPlanPoint? {
        guard paceSecPerKm > 0 else { return nil }
        func r1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
        switch kind {
        case .speed:
            let reps = min(max(Int((weeklyKm * 0.08).rounded()), 3), 6)
            let total = warmupKm + Double(reps) + Double(reps - 1) * jogBetweenKm + cooldownKm
            return MRPlanPoint(kind: .speed, totalKm: r1(total), reps: reps, repKm: 1.0,
                               sustainedKm: nil, paceSecPerKm: paceSecPerKm)
        case .tempo:
            let t = Double(min(max(Int((weeklyKm * 0.10).rounded()), 3), 8))
            return MRPlanPoint(kind: .tempo, totalKm: r1(warmupKm + t + cooldownKm), reps: nil, repKm: nil,
                               sustainedKm: t, paceSecPerKm: paceSecPerKm)
        case .buildUp:
            // ⚠ 임의로 정함 — 10K 이하 8km · 하프 10km · 풀 14km · 대회 없음 10km, 롱런의 70% 이하
            let base: Double
            if let d = raceDistanceM {
                base = d >= MRDistance.dF ? 14 : (d >= MRDistance.dH ? 10 : 8)
            } else {
                base = 10
            }
            let b = min(base, (longRunKm * 0.7).rounded(.down))
            guard b >= 5 else { return nil }
            return MRPlanPoint(kind: .buildUp, totalKm: b, reps: nil, repKm: nil,
                               sustainedKm: r1(b / 3), paceSecPerKm: paceSecPerKm)
        case .racePaceShort:
            let total = warmupKm + 3 + 2 * jogBetweenKm + cooldownKm
            return MRPlanPoint(kind: .racePaceShort, totalKm: r1(total), reps: 3, repKm: 1.0,
                               sustainedKm: nil, paceSecPerKm: paceSecPerKm)
        }
    }

    /// 대회 없을 때 번갈이 — 속도 → 템포 → 빌드업 → 속도. 지난 포인트를 모르면 빌드업(가장 부담이 적다).
    static func nextKind(after last: WorkoutType?) -> Kind {
        switch last {
        case .interval: return .tempo
        case .tempo: return .buildUp
        case .buildUp, .distanceRun: return .speed
        default: return .buildUp
        }
    }

    /// 주차표·아침 제안 공용 문구 — "속도 1km × 4회 5'05\"".
    var text: String {
        let L = AppLanguage.shared
        let pace = mrFormatPace(paceSecPerKm)
        switch kind {
        case .speed:
            let n = reps ?? 0
            return L.s("속도 1km × \(n)회 \(pace)", "Speed 1km × \(n) at \(pace)")
        case .tempo:
            let t = mrPointKmString(sustainedKm ?? 0)
            return L.s("템포 \(t)km \(pace)", "Tempo \(t)km at \(pace)")
        case .buildUp:
            let b = mrPointKmString(totalKm), s = mrPointKmString(sustainedKm ?? 0)
            return L.s("빌드업 \(b)km · 마지막 \(s)km \(pace)", "Build-up \(b)km · last \(s)km at \(pace)")
        case .racePaceShort:
            let n = reps ?? 0
            return L.s("대회 페이스 1km × \(n)회 \(pace)", "Race pace 1km × \(n) at \(pace)")
        }
    }
}

/// km 표기 — 정수면 "8", 아니면 "6.4". 계획 문구(eachStr)와 같은 규칙.
func mrPointKmString(_ km: Double) -> String {
    km == km.rounded() ? String(format: "%.0f", km) : String(format: "%.1f", km)
}

/// 포인트 페이스 — 예측 하프 등가에서 Riegel 1.06(`mrProjectedRefMin`과 같은 지수)으로.
struct MRPointPaces: Equatable, Sendable {
    let fiveK: Double
    let tenK: Double
    let half: Double
    /// Daniels T 페이스 ≈ 1시간 대회 페이스. 일반 러너에게 1시간은 대략 10K와 하프 사이 — ⚠ 임의로 정함(중간값)
    var tempo: Double { (tenK + half) / 2 }
}

func mrPointPaces(halfEquivMin: Double) -> MRPointPaces? {
    guard halfEquivMin > 10 else { return nil }
    func pace(_ dM: Double) -> Double { halfEquivMin * pow(dM / MRDistance.dH, 1.06) * 60 / (dM / 1000) }
    return MRPointPaces(fiveK: pace(MRDistance.d5), tenK: pace(MRDistance.d10), half: pace(MRDistance.dH))
}

/// 계획 단계 → 포인트 종류. 회복·대회 주·따르는 주(○○ 계획)는 nil.
func mrPointKind(phase: String) -> MRPlanPoint.Kind? {
    switch phase {
    case "늘리기": return .speed
    case "유지": return .tempo
    case "대회 페이스": return .buildUp
    case "테이퍼": return .racePaceShort
    default: return nil
    }
}

/// 포인트 간격(일) — 최근 주당 러닝 4회 이상 7일 · 3회 14일 · 그 아래 nil(포인트 없음).
/// 엔진에 비공개 레벨이 없어 주당 횟수로 대신한다(설계 4절).
func mrPointIntervalDays(runsPerWeek: Double) -> Int? {
    let n = Int(runsPerWeek.rounded())
    if n >= 4 { return 7 }
    if n == 3 { return 14 }
    return nil
}

/// 계획 문구의 마지막 "이지(짧게/Easy/Short) Xkm × N회(x)"에서 숫자만 바꾼다. 언어·나머지 문구는 그대로. 못 찾으면 nil.
/// (`mrParsePlanBreakdown`과 같은 패턴)
func mrBreakdownReplacingEasy(_ text: String, easyKm: Double, runs: Int) -> String? {
    guard let re = try? NSRegularExpression(pattern: #"(?:이지|짧게|Easy|Short) ([0-9]+(?:\.[0-9]+)?)km × ([0-9]+)(?:회|x)"#) else { return nil }
    let ns = text as NSString
    guard let m = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else { return nil }
    // 뒤쪽(횟수)부터 바꿔야 앞쪽(거리) 범위가 밀리지 않는다
    let replacedRuns = ns.replacingCharacters(in: m.range(at: 2), with: "\(runs)") as NSString
    return replacedRuns.replacingCharacters(in: m.range(at: 1), with: mrPointKmString(easyKm))
}

/// 트리거 5 — 이미 시작한 계획의 스냅샷에 포인트 칸 채우기(설계 6절).
/// 다음 주(thisMonday 뒤)부터, 스냅샷 주에 point가 없고 같은 월요일 라이브 주가 **같은 단계**로 point를 가질 때만.
/// 종류·페이스는 라이브, 양은 스냅샷 자신의 주간·롱런으로 다시 잰다. 이지 문구는 숫자만 바꾼다.
/// 이지 1회가 1.5km 아래로 내려가거나 문구를 못 읽으면 그 주는 건너뛴다. 지난 주·이번 주는 건드리지 않는다.
func mrFillSnapshotPoints(snapshot: [MRPlanWeekSummary], live: [MRPlanWeek], thisMonday: Date,
                          raceDistanceM: Double, calendar: Calendar = .current) -> (weeks: [MRPlanWeekSummary], filled: Int) {
    let liveByMonday = Dictionary(live.map { (calendar.startOfDay(for: $0.monday), $0) },
                                  uniquingKeysWith: { a, _ in a })
    let thisMon = calendar.startOfDay(for: thisMonday)
    var filled = 0
    let weeks = snapshot.map { s -> MRPlanWeekSummary in
        let mon = calendar.startOfDay(for: s.monday)
        guard s.point == nil, mon > thisMon,
              let lw = liveByMonday[mon], lw.phase == s.phase, let lp = lw.point else { return s }
        let parsed = mrParsePlanBreakdown(s.breakdown)
        guard let runs = parsed.easyRuns, runs >= 2, parsed.easyKm != nil else { return s }
        let long = s.longRunKm.rounded()   // 플래너 문구와 같은 표기값(lrDisplay)
        guard let pt = MRPlanPoint.make(kind: lp.kind, weeklyKm: s.weeklyKm, longRunKm: long,
                                        raceDistanceM: raceDistanceM, paceSecPerKm: lp.paceSecPerKm) else { return s }
        let easyKm = ((s.weeklyKm - long - pt.totalKm) / Double(runs - 1) * 10).rounded() / 10
        guard easyKm >= 1.5, let bd = mrBreakdownReplacingEasy(s.breakdown, easyKm: easyKm, runs: runs - 1) else { return s }
        filled += 1
        var out = s
        out.breakdown = bd
        out.point = pt
        return out
    }
    return (weeks, filled)
}

/// 그 주 포인트를 했는가 — 롱런으로 센 러닝(거리 ≥ 롱런×0.8 중 가장 긴 것 하나)을 뺀 나머지 중
/// 고강도 판정(`hardStarts`, 앱 판정 최근 15일)이거나 저장 유형이 포인트 유형(`pointTypes`, 최근 180일)인 러닝.
/// 가장 이른 것을 돌려준다. 주차표와 아침 제안이 같이 쓴다(설계 7절).
func mrPointRun(weekRuns: [MRWorkout], longRunKm: Double, hardStarts: Set<Date>,
                pointTypes: [Date: WorkoutType]) -> MRWorkout? {
    let longCounted: Date? = longRunKm > 0
        ? weekRuns.filter { ($0.distanceKm ?? 0) >= longRunKm * MRPlanWeekContext.longRunDoneFraction }
                  .max { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }?.start
        : nil
    return weekRuns
        .filter { $0.start != longCounted }
        .filter { w in
            hardStarts.contains(w.start)
                || (pointTypes[w.start].map { MRPlanPoint.pointWorkoutTypes.contains($0) } ?? false)
        }
        .min { $0.start < $1.start }
}

// MARK: - 대회가 없을 때 — 2주 리듬 (설계 9절)

/// 대회 계획이 오늘을 덮지 않을 때의 입력. 스토어가 조립한다.
struct MRRhythmContext: Equatable {
    let runsPerWeek: Double
    let paces: MRPointPaces?
    /// 앱 저장 유형이 포인트 유형인 러닝(최근 180일) — 번갈이·마지막 포인트
    let pointTypes: [Date: WorkoutType]
    /// 최근 14일 안에 끝난 대회 — 이름·날짜. 없으면 nil.
    var recentRaceName: String? = nil
    var recentRaceDate: Date? = nil

    static let longRunEveryDays = 7
    /// ⚠ 코칭 관행 — 대회 거리별로 나누지 않는다
    static let postRaceEasyDays = 14
    static let minUsualLongKm = 8.0
}

/// 평소 롱런 — 이번 주 앞의 4주(월~일) 각 주 최장 러닝의 중앙값. 러닝 있는 주 2개 미만이거나 8km 미만이면 nil.
/// 늘리지 않는다 — 대회가 없을 때 목적은 유지다(설계 9.1).
func mrUsualLongRunKm(runs: [MRWorkout], asOf: Date, calendar: Calendar = .current) -> Double? {
    let thisMonday = MRPlanGovernance.weekMonday(of: asOf, calendar: calendar)
    guard let from = calendar.date(byAdding: .day, value: -28, to: thisMonday) else { return nil }
    var byWeek: [Date: Double] = [:]
    for w in runs where w.start >= from && w.start < thisMonday {
        let mon = MRPlanGovernance.weekMonday(of: w.start, calendar: calendar)
        byWeek[mon] = max(byWeek[mon] ?? 0, w.distanceKm ?? 0)
    }
    guard byWeek.count >= 2 else { return nil }
    let l = mrMedian(Array(byWeek.values))
    return l >= MRRhythmContext.minUsualLongKm ? l : nil
}

/// 대회 계획이 오늘을 덮지 않을 때 — 마지막으로 한 날을 보고 빠진 것을 권한다(설계 9.4).
/// 강도 OK: 대회 뒤 14일 → 이지 · 롱런 7일↑ + 습관 요일(또는 습관 없음) → 롱런 · 포인트 간격↑ + 롱런 요일 전날 아님 → 포인트(번갈이) · 그 외 이지.
/// 이지·휴식 날은 세션 없이 리듬 상태만. 이지 거리는 말하지 않는다(주간 목표가 없다).
func mrRhythmSuggestion(level: MRReadiness.Level, ctx: MRRhythmContext, runs: [MRWorkout],
                        hardStarts: Set<Date>, asOf: Date, calendar: Calendar = .current) -> MRSessionSuggestion? {
    let L = AppLanguage.shared
    let today = calendar.startOfDay(for: asOf)
    let past = runs.filter { $0.start < today }
    func daysAgo(_ d: Date) -> Int { calendar.dateComponents([.day], from: calendar.startOfDay(for: d), to: today).day ?? 0 }
    let md: DateFormatter = { let f = DateFormatter(); f.dateFormat = "M/d"; return f }()

    // 대회 뒤 2주 — 포인트도 롱런도 권하지 않는다
    if let rd = ctx.recentRaceDate, (0..<MRRhythmContext.postRaceEasyDays).contains(daysAgo(rd)) {
        let n = daysAgo(rd)
        let name = ctx.recentRaceName ?? L.s("대회", "the race")
        let note = L.s("\(name) \(n)일 뒤 — 2주는 이지로 회복해요.", "\(n) days after \(name) — keep two weeks easy to recover.")
        return MRSessionSuggestion(session: level == .go ? L.s("이지런", "Easy run") : nil, progress: "", whyNote: note)
    }

    let usualLong = mrUsualLongRunKm(runs: runs, asOf: asOf, calendar: calendar)
    func isLong(_ w: MRWorkout) -> Bool {
        guard let l = usualLong else { return false }
        return (w.distanceKm ?? 0) >= l * MRPlanWeekContext.longRunDoneFraction
    }
    let lastLong = past.filter(isLong).max { $0.start < $1.start }
    let lastPoint = past
        .filter { !isLong($0) }
        .filter { w in
            hardStarts.contains(w.start)
                || (ctx.pointTypes[w.start].map { MRPlanPoint.pointWorkoutTypes.contains($0) } ?? false)
        }
        .max { $0.start < $1.start }
    let interval = mrPointIntervalDays(runsPerWeek: ctx.runsPerWeek)

    var pieces: [String] = []
    if usualLong != nil, let l = lastLong {
        pieces.append(L.s("마지막 롱런 \(daysAgo(l.start))일 전", "last long run \(daysAgo(l.start)) days ago"))
    }
    if interval != nil, let p = lastPoint {
        pieces.append(L.s("마지막 포인트 \(daysAgo(p.start))일 전", "last workout \(daysAgo(p.start)) days ago"))
    }
    let progress = pieces.joined(separator: " · ")

    guard level == .go else { return MRSessionSuggestion(session: nil, progress: progress) }

    let habitual = mrHabitualLongRunWeekday(runs: runs, asOf: asOf, calendar: calendar)
    let todayWD = calendar.component(.weekday, from: asOf)
    let longDue = usualLong != nil
        && (lastLong.map { daysAgo($0.start) >= MRRhythmContext.longRunEveryDays } ?? true)
    if let l = usualLong, longDue, habitual == nil || habitual == todayWD {
        return MRSessionSuggestion(session: L.s("롱런 \(Int(l.rounded()))km", "Long run \(Int(l.rounded()))km"),
                                   progress: progress, isLongRun: true)
    }

    let tomorrowWD = todayWD % 7 + 1
    if let iv = interval, let paces = ctx.paces, habitual != tomorrowWD,
       lastPoint.map({ daysAgo($0.start) >= iv }) ?? true {
        let lastType = lastPoint.flatMap { ctx.pointTypes[$0.start] }
        let weekly = past.filter { daysAgo($0.start) <= 28 }.compactMap(\.distanceKm).reduce(0, +) / 4
        func make(_ kind: MRPlanPoint.Kind) -> MRPlanPoint? {
            let pace = kind == .speed ? paces.fiveK : (kind == .tempo ? paces.tempo : paces.half)
            return MRPlanPoint.make(kind: kind, weeklyKm: weekly, longRunKm: usualLong ?? 0,
                                    raceDistanceM: nil, paceSecPerKm: pace)
        }
        // 빌드업이 안 되면(평소 롱런이 짧음) 속도로
        if let pt = make(MRPlanPoint.nextKind(after: lastType)) ?? make(.speed) {
            let why: String
            if let lp = lastPoint {
                let label = lastType.map { " " + $0.koreanLabel } ?? ""
                why = L.s("지난 포인트는 \(md.string(from: lp.start))\(label), \(daysAgo(lp.start))일 전이에요.",
                          "Last workout:\(label) \(daysAgo(lp.start)) days ago.")
            } else {
                why = L.s("최근 포인트가 없어요.", "No recent workout.")
            }
            return MRSessionSuggestion(session: L.s("포인트 추천: \(pt.text)", "Workout: \(pt.text)"),
                                       progress: progress, isPoint: true, whyNote: why)
        }
    }

    let note: String? = longDue
        ? habitual.map { L.s("여유는 \(mrWeekdayName($0)) 롱런에 쓰세요.", "Save it for \(mrWeekdayName($0))'s long run.") }
        : nil
    return MRSessionSuggestion(session: L.s("이지런", "Easy run"), progress: progress, whyNote: note)
}
