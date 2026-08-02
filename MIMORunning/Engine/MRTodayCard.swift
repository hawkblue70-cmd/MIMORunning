import Foundation

/// 오늘의 러닝 카드 — 세 층.
///
///   ① 쌓인 것        조용한 기록자. 오늘 하루가 아니라 누적을 보여준다.
///   ② 오늘 + 연결     동행자. 오늘을 목표에 잇는다.
///   ③ 짚어보기        코치. 매일 나오되 **판정이 아니라 관찰**로 쓴다.
///
/// 원칙:
///  · ③은 "부족하다"가 아니라 "이렇게 하면 이렇게 된다"로 쓴다.
///  · 0회 같은 숫자를 그대로 노출하지 않는다. 0은 사람을 찌른다.
///  · ③에 올릴 게 없으면 **그리지 않는다**. "특별한 조언 없음"을 쓰지 말 것.
struct MRTodayCard {
    let streakLine: String          // ①
    let cumulativeLine: String      // ①
    let headline: String            // ②
    let linkLine: String?           // ②
    let observation: String?        // ③
    let observationBasis: String?   // ③ 탭하면 보이는 근거
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
    let streak = mrActiveWeekStreak(runs: runs, asOf: asOf)
    let streakLine = streak >= 2
        ? "\(streak)주 연속으로 달리고 있어요"
        : "오늘도 나오셨네요"

    let totalKm = runs.compactMap(\.distanceKm).reduce(0, +)
    let monthIdx = runs.filter {
        cal.isDate($0.start, equalTo: last.start, toGranularity: .month)
        && $0.start <= last.start
    }.count
    let cumulativeLine = "이번 달 \(monthIdx)번째 · 누적 \(runs.count)회 \(String(format: "%.0f", totalKm))km"

    // ── ② 오늘 + 목표 연결
    // ⚠ 바로 아래 러닝 목록과 같은 화면에 있으므로 반올림이 어긋나면 안 된다.
    //   duration을 분 단위로 먼저 반올림한 뒤 페이스를 계산하면
    //   목록의 6'28"과 카드의 6:29가 달라진다.
    //   페이스는 **원본 초 단위**로 계산하고, 시간은 mm:ss로 보여준다.
    let dist = last.distanceKm.map { String(format: "%.2fkm", $0) } ?? "—"
    let durSec = Int((last.durationMin * 60).rounded())
    let dur = String(format: "%d:%02d", durSec / 60, durSec % 60)
    let pace = last.paceSecPerKm.map { mrFormatPace($0) + "/km" } ?? "—"
    let headline = "\(dist) · \(dur) · \(pace)"

    // ⚠ "지금 상태"가 아니라 "계획대로 쌓았을 때"를 보여준다.
    //   오늘 하루가 목표에 기여한다는 감각이 이 앱의 목적이다.
    // ⚠ D-day 카드가 바로 위에 떠 있으면 링크 줄을 그리지 않는다.
    //   같은 화면에서 "D-13"과 "다음 대회까지 7주"가 나란히 뜨면
    //   서로 다른 대회를 가리키는 것으로 읽힌다(실제로 그렇게 나왔다).
    var linkLine: String? = nil
    if !raceDayCardVisible, let next = plans.min(by: { $0.raceDate < $1.raceDate }) {
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: asOf),
                                   to: cal.startOfDay(for: next.raceDate)).day ?? 0
        let weeks = d / 7
        linkLine = weeks >= 2
            ? "다음 대회까지 \(weeks)주 — 오늘 같은 날이 쌓이면 \(mrFormatDisplay(next.projectedFinal))입니다"
            : "대회가 \(d)일 남았어요. 이제는 쌓는 게 아니라 아끼는 시기입니다"
    }

    // ── ③ 짚어보기
    //
    // 우선순위: 심박이 있으면 오늘 것부터 — 방금 뛰고 온 것에 대한 반응이
    // 지난 4주 통계보다 먼저다. 없으면 큐 1위로 내려온다.
    var observation: String? = nil
    var basis: String? = nil

    if let ceil = phys.easyCeilingHR, let hr = last.hrAvg, let lt1 = phys.lt1HR {
        if hr < ceil {
            observation = "유산소 구간 안에서 달리셨어요. 이런 날이 오래 가는 다리를 만듭니다."
            basis = String(format: "평균 심박 %.0f · 유산소 상한 %.0f (LT1 %.0f±%.0f)",
                           hr, ceil, lt1.value, phys.lt1SD)
        } else if hr < lt1.value + phys.lt1SD {
            observation = "이지보다 템포에 가까운 날이었습니다. 나쁜 건 아니고, 다음 한 번을 조금 느리게 잡아두면 균형이 맞아요."
            basis = String(format: "평균 심박 %.0f · 유산소 상한 %.0f (LT1 %.0f±%.0f)",
                           hr, ceil, lt1.value, phys.lt1SD)
        } else {
            observation = "오늘은 꽤 강하게 밀어붙이셨네요. 다음 한 번은 편하게 달려두는 게 좋아요."
            basis = String(format: "평균 심박 %.0f · 유산소 상한 %.0f (LT1 %.0f±%.0f)",
                           hr, ceil, lt1.value, phys.lt1SD)
        }
    } else if let top = advice.first(where: { $0.slot == "todayRun" }) {
        observation = top.text
        basis = top.rationale
    }

    return MRTodayCard(streakLine: streakLine, cumulativeLine: cumulativeLine,
                       headline: headline, linkLine: linkLine,
                       observation: observation, observationBasis: basis)
}
