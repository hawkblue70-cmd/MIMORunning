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
    let streakLine: String           // ①
    let cumulativeLine: String       // ①
    let sessionLine: String?         // ② 오늘 뛰었으면 기록 한 줄, 아니면 이번 주 요약
    let linkLine: String?            // ②
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

    let totalKm = runs.compactMap(\.distanceKm).reduce(0, +)

    // ── ② 오늘 뛰었는가
    // ⚠ 주간 요약은 성장 탭이 담당한다. 홈에 두면 중복이다.
    //   성장 탭 히트맵의 "18주간"과 홈의 "21주 연속"이 나란히 뜨면
    //   어느 게 맞는지 헷갈린다.
    //
    //   홈의 큰 글씨는 하나여야 한다:
    //     오늘 뛴 날 → 오늘 러닝이 주인공 (sessionLine)
    //     안 뛴 날   → streakLine(21주 연속)이 주인공
    let ranToday = cal.isDate(last.date, inSameDayAs: asOf)
    var sessionLine: String? = nil
    let cumulativeLine: String
    if ranToday {
        let dist = last.distanceKm.map { String(format: "%.2fkm", $0) } ?? "—"
        let durSec = Int((last.durationMin * 60).rounded())
        let dur = String(format: "%d:%02d", durSec / 60, durSec % 60)
        let pace = last.paceSecPerKm.map { mrFormatPace($0) + "/km" } ?? "—"
        sessionLine = "\(dist) · \(dur) · \(pace)"
        let monthIdx = runs.filter {
            cal.isDate($0.start, equalTo: last.start, toGranularity: .month)
            && $0.start <= last.start
        }.count
        cumulativeLine = L.s(
            "이번 달 \(monthIdx)번째 · 누적 \(runs.count)회 \(Int(totalKm))km",
            "Run \(monthIdx) this month · \(runs.count) total · \(Int(totalKm))km"
        )
    } else {
        cumulativeLine = L.s(
            "누적 \(runs.count)회 \(Int(totalKm))km",
            "\(runs.count) runs · \(Int(totalKm))km"
        )
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

    return MRTodayCard(streakLine: streakLine, cumulativeLine: cumulativeLine,
                       sessionLine: sessionLine, linkLine: linkLine)
}
