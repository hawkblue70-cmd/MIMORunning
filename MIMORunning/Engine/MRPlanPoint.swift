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
    /// 반복 사이 회복은 **시간**으로 안내한다 — 트랙 없이도 시계로 맞출 수 있고, 도로 GPS는 짧은 거리를 잘 못 잰다.
    /// 인터벌 사이 3분: Daniels 관행(5K 페이스 반복의 회복 ≈ 달린 시간과 같거나 조금 짧게, 1km ≈ 5분)을 초·중수 쪽으로.
    /// 대회 페이스 반복 사이 1분: 대회 페이스는 역치 아래라 짧은 휴식으로 충분. ⚠ 둘 다 임의로 정함.
    static let intervalJogMin = 3
    static let racePaceJogMin = 1
    /// 총 거리 계산용 회복 조깅 거리 — 3분 ≈ 0.5km · 1분 ≈ 0.15km (6~7분/km 조깅)
    static let intervalJogKm = 0.5
    static let racePaceJogKm = 0.15

    /// 포인트로 세는 앱 저장 유형 — 고강도 판정(`RunSummaryBuilder.isHardRun`)의 종류 규칙과 같다.
    static let pointWorkoutTypes: Set<WorkoutType> = [.interval, .tempo, .buildUp, .distanceRun, .race]

    /// 종류와 이번 주 주간·롱런으로 양을 정한다. 만들 수 없으면 nil(페이스 없음·빌드업이 5km 미만).
    static func make(kind: Kind, weeklyKm: Double, longRunKm: Double,
                     raceDistanceM: Double?, paceSecPerKm: Double) -> MRPlanPoint? {
        guard paceSecPerKm > 0 else { return nil }
        func r1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
        switch kind {
        case .speed:
            // 반복 한 번 ≈ 4분(Daniels 인터벌 3~5분의 가운데)을 본인 5K 페이스로 거리로 — 200m 단위, 400~1200m.
            // 빠른 러너 1km, 5'07" 러너 800m, 6'30" 러너 600m. 회수는 빠른 구간 합이 주간 8%에 들게(3~6회).
            let repKm = mrIntervalRepKm(paceSecPerKm: paceSecPerKm)
            let reps = min(max(Int((weeklyKm * 0.08 / repKm).rounded()), 3), 6)
            let total = warmupKm + Double(reps) * repKm + Double(reps - 1) * intervalJogKm + cooldownKm
            return MRPlanPoint(kind: .speed, totalKm: r1(total), reps: reps, repKm: repKm,
                               sustainedKm: nil, paceSecPerKm: paceSecPerKm)
        case .tempo:
            let t = Double(min(max(Int((weeklyKm * 0.10).rounded()), 3), 8))
            return MRPlanPoint(kind: .tempo, totalKm: r1(warmupKm + t + cooldownKm), reps: nil, repKm: nil,
                               sustainedKm: t, paceSecPerKm: paceSecPerKm)
        case .buildUp:
            // ⚠ 임의로 정함 — 10K 이하 8km · 하프·풀·대회 없음 10km, 롱런의 70% 이하.
            //   풀도 10km(2026-09-29): 대회 페이스 주는 롱런 후반에도 대회 페이스가 있어 14km면 한 주에 긴 러닝이 둘이 된다.
            let base: Double
            if let d = raceDistanceM {
                base = d >= MRDistance.dH ? 10 : 8
            } else {
                base = 10
            }
            let b = min(base, (longRunKm * 0.7).rounded(.down))
            guard b >= 5 else { return nil }
            return MRPlanPoint(kind: .buildUp, totalKm: b, reps: nil, repKm: nil,
                               sustainedKm: r1(b / 3), paceSecPerKm: paceSecPerKm)
        case .racePaceShort:
            let total = warmupKm + 3 + 2 * racePaceJogKm + cooldownKm
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

    /// 주차표·아침 제안 공용 문구 — "인터벌 1km × 4회 5'05\"". 이름은 앱 러닝 종류 분류명과 같게(인터벌·템포런·빌드업).
    var text: String {
        let L = AppLanguage.shared
        let pace = mrFormatPace(paceSecPerKm)
        switch kind {
        case .speed:
            let n = reps ?? 0
            let rep = mrRepDistanceString(repKm ?? 1)
            return L.s("인터벌 \(rep) × \(n)회 \(pace)", "Intervals \(rep) × \(n) at \(pace)")
        case .tempo:
            let t = mrPointKmString(sustainedKm ?? 0)
            return L.s("템포런 \(t)km 지속 \(pace)", "Tempo run \(t)km steady at \(pace)")
        case .buildUp:
            let b = mrPointKmString(totalKm), s = mrPointKmString(sustainedKm ?? 0)
            return L.s("빌드업 \(b)km · 마지막 \(s)km \(pace)", "Build-up \(b)km · last \(s)km at \(pace)")
        case .racePaceShort:
            let n = reps ?? 0
            return L.s("대회 페이스 1km × \(n)회 \(pace)", "Race pace 1km × \(n) at \(pace)")
        }
    }
}

extension MRPlanPoint {
    /// 어떻게 뛰는지 — 주차표에서 `text` 뒤에 붙인다. "1km × 4회"만으로는 이지에 섞는 건지, 따로 뛰는 건지 알 수 없었다.
    var howTo: String {
        let L = AppLanguage.shared
        let total = mrPointKmString(totalKm)
        switch kind {
        case .speed:
            return L.s("사이 \(Self.intervalJogMin)분 천천히 조깅 · 앞뒤 조깅 포함 총 \(total)km", "\(Self.intervalJogMin)-min easy jog between · \(total) km total incl. warm-up/cool-down")
        case .tempo:
            return L.s("앞 2km·뒤 1km 조깅 포함 총 \(total)km", "\(total) km total incl. 2 km warm-up and 1 km cool-down")
        case .buildUp:
            return L.s("편하게 시작해 점점 올리기", "start easy, build steadily")
        case .racePaceShort:
            return L.s("사이 \(Self.racePaceJogMin)분 조깅 · 앞뒤 조깅 포함 총 \(total)km", "\(Self.racePaceJogMin)-min jog between · \(total) km total incl. warm-up/cool-down")
        }
    }
}

/// 인터벌 반복 한 번의 목표 시간(초) — Daniels' Running Formula: 인터벌(I) 반복은 3~5분.
/// 산소 섭취가 최고치 가까이 오르는 데 약 2분이 걸려 3분은 되어야 최고 구간에 머물고, 5분을 넘으면 페이스를 못 지킨다.
/// ⚠ 코칭 관행(생리학에서 끌어낸 처방) — 3분·5분을 직접 비교한 통제 연구는 아니다. 4분은 그 가운데로 임의로 정함.
let MR_INTERVAL_REP_SEC = 240.0

/// 반복 거리(km) — 4분 × 5K 페이스를 200m 단위로 반올림, 400~1200m.
func mrIntervalRepKm(paceSecPerKm: Double) -> Double {
    guard paceSecPerKm > 0 else { return 1.0 }
    let meters = (MR_INTERVAL_REP_SEC / paceSecPerKm * 1000 / 200).rounded() * 200
    return min(max(meters, 400), 1200) / 1000
}

/// 반복 거리 표기 — 1km 이상은 "1km"·"1.2km", 그 아래는 "800m".
func mrRepDistanceString(_ km: Double) -> String {
    km >= 1 ? "\(mrPointKmString(km))km" : "\(Int((km * 1000).rounded()))m"
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

/// 본인 강도 훈련 습관 간격(주) — 이번 주 앞 12주 중 러닝이 있던 주에서, 그 주 최장 러닝(롱런)을 뺀 고강도·포인트 유형
/// 러닝(`mrPointRun`)이 있던 주의 비율로. 1 매주 · 2 격주 · 3 3주에 한 번. 러닝 있는 주 6주 미만이면 nil(폴백).
/// 비율 0(강도 훈련을 거의 안 해 옴)이면 3 — 천천히 들인다. 설계 2026-09-29 "본인 데이터에서 출발" 2절.
func mrHabitualPointEveryWeeks(runs: [MRWorkout], pointTypes: [Date: WorkoutType], hardStarts: Set<Date>,
                               asOf: Date, calendar: Calendar = .current) -> Int? {
    let thisMonday = MRPlanGovernance.weekMonday(of: asOf, calendar: calendar)
    guard let from = calendar.date(byAdding: .day, value: -84, to: thisMonday) else { return nil }
    var byWeek: [Date: [MRWorkout]] = [:]
    for w in runs where w.start >= from && w.start < thisMonday {
        byWeek[MRPlanGovernance.weekMonday(of: w.start, calendar: calendar), default: []].append(w)
    }
    guard byWeek.count >= 6 else { return nil }   // ⚠ 임의로 정함 — 습관으로 보기에 최소한의 주 수
    let withPoint = byWeek.values.filter { ws in
        let longest = ws.compactMap(\.distanceKm).max() ?? 0
        return mrPointRun(weekRuns: ws, longRunKm: longest, hardStarts: hardStarts, pointTypes: pointTypes) != nil
    }.count
    let ratio = Double(withPoint) / Double(byWeek.count)
    guard ratio > 0 else { return 3 }
    return min(max(Int((1 / ratio).rounded()), 1), 3)
}

/// 적용 간격(주) — 주당 러닝 횟수 규칙(4회↑ 1 · 3회 2 · 2회↓ 없음)과 본인 습관 중 더 드문 쪽.
func mrPointEveryWeeks(runsPerWeek: Double, habit: Int?) -> Int? {
    guard let days = mrPointIntervalDays(runsPerWeek: runsPerWeek) else { return nil }
    let byRuns = days / 7
    return max(byRuns, habit ?? byRuns)
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

/// 트리거 5 — 이미 시작한 계획의 스냅샷에 포인트 칸 채우기(설계 6절). 이미 채운 미래 주는 규칙이 바뀌었을 때만 다시 잰다.
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
        // 이미 채운 미래 주 — 규칙(반복 거리·회복 시간)이 바뀌었으면 저장된 페이스 그대로 다시 잰다. 이지 횟수는 그대로.
        // 페이스를 라이브로 바꾸지 않아 예측이 조금씩 움직일 때마다 스냅샷을 다시 쓰지 않는다.
        if let sp = s.point {
            guard mon > thisMon else { return s }
            let long = s.longRunKm.rounded()
            // 종류 규칙이 바뀌었으면(늘리기 인터벌·템포런 번갈이 등) 같은 단계 라이브 주의 종류·페이스를 따른다
            let live = liveByMonday[mon].flatMap { lw in lw.phase == s.phase ? lw.point : nil }
            let (kind, pace) = (live.map { $0.kind != sp.kind } ?? false)
                ? (live!.kind, live!.paceSecPerKm) : (sp.kind, sp.paceSecPerKm)
            guard let np = MRPlanPoint.make(kind: kind, weeklyKm: s.weeklyKm, longRunKm: long,
                                            raceDistanceM: raceDistanceM, paceSecPerKm: pace),
                  np != sp else { return s }
            let parsed = mrParsePlanBreakdown(s.breakdown)
            guard let runs = parsed.easyRuns, runs >= 1, parsed.easyKm != nil else { return s }
            let easyKm = ((s.weeklyKm - long - np.totalKm) / Double(runs) * 10).rounded() / 10
            guard easyKm >= 1.5, let bd = mrBreakdownReplacingEasy(s.breakdown, easyKm: easyKm, runs: runs) else { return s }
            filled += 1
            var out = s
            out.breakdown = bd
            out.point = np
            return out
        }
        guard mon > thisMon,
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
    /// 본인 강도 훈련 습관 간격(주) — nil이면 주당 러닝 횟수 규칙만
    var habitEveryWeeks: Int? = nil

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
    // 당일(0일)은 제외 — 대회 날 아침에 "0일 뒤"라고 하지 않는다
    if let rd = ctx.recentRaceDate, (1..<MRRhythmContext.postRaceEasyDays).contains(daysAgo(rd)) {
        let n = daysAgo(rd)
        let name = ctx.recentRaceName ?? L.s("대회", "the race")
        let note = L.s("\(name) \(n)일 뒤 — 2주는 이지로 회복해요.", "\(n) days after \(name) — keep two weeks easy to recover.")
        return MRSessionSuggestion(session: level == .rest ? nil : L.s("이지런", "Easy run"), progress: "",
                                   isRecovery: level != .rest, whyNote: note)
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
    let interval = mrPointEveryWeeks(runsPerWeek: ctx.runsPerWeek, habit: ctx.habitEveryWeeks).map { $0 * 7 }

    var pieces: [String] = []
    if usualLong != nil, let l = lastLong {
        pieces.append(L.s("마지막 롱런 \(daysAgo(l.start))일 전", "last long run \(daysAgo(l.start)) days ago"))
    }
    if interval != nil, let p = lastPoint {
        pieces.append(L.s("마지막 강도 훈련 \(daysAgo(p.start))일 전", "last hard session \(daysAgo(p.start)) days ago"))
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
                why = L.s("지난 강도 훈련은 \(md.string(from: lp.start))\(label), \(daysAgo(lp.start))일 전이에요.",
                          "Last hard session:\(label) \(daysAgo(lp.start)) days ago.")
            } else {
                why = L.s("최근 강도 훈련이 없어요.", "No recent hard session.")
            }
            return MRSessionSuggestion(session: pt.text,
                                       progress: progress, isPoint: true, whyNote: why)
        }
    }

    let note: String? = longDue
        ? habitual.map { L.s("여유는 \(mrWeekdayName($0)) 롱런에 쓰세요.", "Save it for \(mrWeekdayName($0))'s long run.") }
        : nil
    return MRSessionSuggestion(session: L.s("이지런", "Easy run"), progress: progress, whyNote: note)
}

/// 계획 문구 + 포인트 — D-day 카드처럼 이번 주 계획을 한 줄로 말하는 곳. 포인트가 없으면 문구 그대로.
/// (안내 문구는 포인트가 있으면 이지 횟수가 하나 줄어 있어, 포인트를 빼고 말하면 합이 주간 km와 안 맞는다)
func mrBreakdownWithPoint(_ w: MRPlanWeek) -> String {
    guard let pt = w.point else { return w.breakdown }
    return w.breakdown + AppLanguage.shared.s(" + 강도 훈련 ", " + hard session: ") + pt.text
}
