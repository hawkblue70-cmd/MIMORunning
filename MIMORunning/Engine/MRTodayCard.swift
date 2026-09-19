import Foundation

/// 오늘의 러닝 카드 — 두 층.
///
///   ① 쌓인 것      조용한 기록자. 오늘 하루가 아니라 누적을 보여준다.
///   ② 오늘 + 연결  동행자. 오늘 달렸으면 기록을, 안 달렸으면 이번 주 요약을.
///
/// 원칙:
///  · 0회 같은 숫자를 그대로 노출하지 않는다. 0은 사람을 찌른다.
///  · 세션 해석(LT1 기반 강도 판정)은 러닝 상세의 강도·페이스 카드에 있다.
///    홈에 두면 아래 목록과 같은 이야기를 두 번 하는 중복이 된다.
struct MRTodayCard {
    /// 거리 칸 하나 — 이번 주 / 이번 달 / 올해 / 누적. 값은 km, 표시 단위(km·mi)는 뷰가 정한다.
    struct DistanceCell: Equatable {
        let label: String
        let km: Double
    }

    let streakLine: String           // ①
    let distanceCells: [DistanceCell] // ① 0km인 칸은 빠져 있다. 누적은 항상 있다.
    let sessionLine: String?         // ② 오늘 뛰었으면 기록 한 줄, 아니면 이번 주 요약
    let linkLine: String?            // ②

    /// 러닝 기록 줄을 "오늘"로 치는 시간 — 러닝 **종료** 후 이만큼. 달력상 자정이 아니다.
    /// 이 안에 다시 뛰면 가장 최근 러닝으로 교체된다(`runs.last`).
    static let sessionLineWindow: TimeInterval = 12 * 3600
}

/// 연속으로 한 번 이상 달린 주의 수. ISO 주(월요일 시작) 기준.
///
/// ⚠ Calendar의 주 경계는 로케일에 따라 일요일 시작이 될 수 있어
///   `date(from:)`에 의존하면 어긋난다. ISO 주 번호를 직접 비교한다.
func mrActiveWeekStreak(runs: [MRWorkout], asOf: Date) -> Int {
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = .current

    func key(_ d: Date) -> Int {
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return (c.yearForWeekOfYear ?? 0) * 100 + (c.weekOfYear ?? 0)
    }

    let weeksWithRuns = Set(runs.map { key($0.date) })
    var streak = 0
    var cursor = cal.startOfDay(for: asOf)
    // 이번 주에 러닝이 아직 없으면 지난 주부터 카운트를 시작한다.
    // (주 초(월요일)에 아직 달리기 전이어도 직전 연속이 유지됨)
    if !weeksWithRuns.contains(key(cursor)),
       let prev = cal.date(byAdding: .day, value: -7, to: cursor) {
        cursor = prev
    }
    while weeksWithRuns.contains(key(cursor)) {
        streak += 1
        guard let prev = cal.date(byAdding: .day, value: -7, to: cursor) else { break }
        cursor = prev
        if streak > 1000 { break }
    }
    return streak
}

/// 홈 거리 행 — 이번 주(ISO 주, 월요일 시작) · 이번 달 · 올해 · 누적.
///
/// 회수가 아니라 거리다: 러너가 관리하는 단위는 주간 마일리지고, 누적 km는 레벨의 숫자다(NRC 블랙 = 5,000km).
/// 0km인 칸은 넣지 않는다 — 월요일 아침 "이번 주 0km", 1일 아침 "이번 달 0km"는 사람을 찌른다.
/// 누적은 러닝이 하나라도 있으면 항상 있다.
func mrDistanceCells(runs: [MRWorkout], asOf: Date) -> [MRTodayCard.DistanceCell] {
    let L = AppLanguage.shared
    var iso = Calendar(identifier: .iso8601)
    iso.timeZone = .current
    let cal = Calendar.current

    func sum(_ f: (MRWorkout) -> Bool) -> Double {
        runs.filter(f).compactMap(\.distanceKm).reduce(0, +)
    }
    let week  = sum { iso.isDate($0.start, equalTo: asOf, toGranularity: .weekOfYear) }
    let month = sum { cal.isDate($0.start, equalTo: asOf, toGranularity: .month) }
    let year  = sum { cal.isDate($0.start, equalTo: asOf, toGranularity: .year) }
    let total = sum { _ in true }

    var cells: [MRTodayCard.DistanceCell] = []
    if week  > 0 { cells.append(.init(label: L.s("이번 주", "This week"),  km: week)) }
    if month > 0 { cells.append(.init(label: L.s("이번 달", "This month"), km: month)) }
    if year  > 0 { cells.append(.init(label: L.s("올해",   "This year"),  km: year)) }
    cells.append(.init(label: L.s("누적", "Total"), km: total))
    return cells
}

func mrTodayCard(runs: [MRWorkout],
                 phys: MRPhysiology,
                 plans: [MRRacePlan],
                 raceDayCardVisible: Bool,
                 advice: [MRAdvice],
                 asOf: Date) -> MRTodayCard? {

    guard let last = runs.last else { return nil }
    let cal = Calendar.current

    // ── ① 쌓인 것
    let L = AppLanguage.shared
    let streak = mrActiveWeekStreak(runs: runs, asOf: asOf)
    let streakLine = streak >= 2
        ? L.s("\(streak)주 연속으로 달리고 있어요", "\(streak)-week streak")
        : L.s("오늘도 나오셨네요", "Great to see you today")

    let distanceCells = mrDistanceCells(runs: runs, asOf: asOf)

    // ── ② 오늘 뛰었는가
    // ⚠ 주간 요약은 성장 탭이 담당한다. 홈에 두면 중복이다.
    //   성장 탭 히트맵의 "18주간"과 홈의 "21주 연속"이 나란히 뜨면
    //   어느 게 맞는지 헷갈린다.
    //
    //   홈의 큰 글씨는 하나여야 한다:
    //     오늘 뛴 날 → 오늘 러닝이 주인공 (sessionLine)
    //     안 뛴 날   → streakLine(21주 연속)이 주인공
    //
    // "오늘"의 기준은 달력이 아니라 **러닝이 끝난 뒤 12시간**이다.
    //   달력 기준(자정)이면 밤 11시에 뛰고 자정 넘어 열었을 때 방금 뛴 게 벌써 없다.
    //   반대로 다음 러닝까지 계속 두면 사흘 쉰 날에도 사흘 전 기록이 큰 글씨로 남아
    //   아래 목록과 중복되고, 쉬는 날의 주인공이어야 할 streakLine을 밀어낸다.
    //   12시간: 오후 5시 러닝은 다음 날 새벽 5시까지, 밤 11시 러닝은 다음 날 11시까지.
    let sessionEnd = last.start.addingTimeInterval(last.durationMin * 60)
    let sinceEnd = asOf.timeIntervalSince(sessionEnd)
    let ranToday = sinceEnd >= 0 && sinceEnd < MRTodayCard.sessionLineWindow
    var sessionLine: String? = nil
    if ranToday {
        let dist = last.distanceKm.map { String(format: "%.2fkm", $0) } ?? "—"
        // 한 시간을 넘으면 시:분:초 — "100:41"처럼 분이 세 자리로 늘면 아래 목록의 "1:40:41"과 어긋난다.
        // (Activity.formattedDuration과 같은 규칙. mrFormatDisplay는 "분 초" 표기라 이 줄에 안 맞는다)
        let durSec = Int((last.durationMin * 60).rounded())
        let dur = durSec >= 3600
            ? String(format: "%d:%02d:%02d", durSec / 3600, (durSec % 3600) / 60, durSec % 60)
            : String(format: "%d:%02d", durSec / 60, durSec % 60)
        let pace = last.paceSecPerKm.map { mrFormatPace($0) + "/km" } ?? "—"
        sessionLine = "\(dist) · \(dur) · \(pace)"
    }

    // ⚠ "지금 상태"가 아니라 "계획대로 쌓았을 때"를 보여준다.
    // ⚠ D-day 카드가 바로 위에 떠 있으면 링크 줄을 그리지 않는다.
    //   같은 화면에서 "D-13"과 "다음 대회까지 7주"가 나란히 뜨면
    //   서로 다른 대회를 가리키는 것으로 읽힌다(실제로 그렇게 나왔다).
    var linkLine: String? = nil
    // 미래 대회만 대상 — 날짜가 지난 대회는 카운트다운에서 제외
    let futurePlans = plans.filter { $0.raceDate > asOf }
    if !raceDayCardVisible, let next = futurePlans.min(by: { $0.raceDate < $1.raceDate }) {
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: asOf),
                                   to: cal.startOfDay(for: next.raceDate)).day ?? 0
        let weeks = d / 7
        linkLine = weeks >= 2
            ? L.s(
                "다음 대회까지 \(weeks)주 — 오늘 같은 날이 쌓이면 \(mrFormatDisplay(next.projectedFinal))입니다",
                "\(weeks) weeks to race day — keep this up for \(mrFormatDisplay(next.projectedFinal))"
              )
            : L.s(
                "대회가 \(d)일 남았어요. 이제는 쌓는 게 아니라 아끼는 시기입니다",
                "\(d) days to race day — time to taper, not to push"
              )
    }

    return MRTodayCard(streakLine: streakLine, distanceCells: distanceCells,
                       sessionLine: sessionLine, linkLine: linkLine)
}
