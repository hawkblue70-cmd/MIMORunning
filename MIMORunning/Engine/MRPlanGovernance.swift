import Foundation

// MARK: - 이번 주를 "다스리는" 계획 하나 고르기
//
// 계획이 둘 이상 겹치는 주(10K 계획 + 하프 계획)에 "이번 주 목표"를 묻는 곳은 전부 여기를 거친다.
// 규칙: 그 월요일에 주차가 있는 계획 가운데 **대회일이 가장 이른** 계획이 다스린다 —
// 그 대회 주까지(대회 주 포함). 대회가 지나면 다음 계획이 이어받는다.
// 플래너가 A 계획의 겹치는 주를 앞 대회 계획 숫자로 맞추므로(mrBuildPlan `followed`),
// 어느 쪽을 골라도 숫자는 같아야 한다. 라벨("10K 계획")을 위해 계획을 함께 돌려준다.

enum MRPlanGovernance {

    /// `monday`가 속한 주를 다스리는 (계획, 주차). 그 주에 주차를 가진 계획이 없으면 nil.
    /// `monday`는 임의의 날짜여도 된다 — 그 날짜가 속한 주의 월요일로 정규화한다.
    static func governingWeek(plans: [MRRacePlan], monday: Date,
                              calendar: Calendar = .current) -> (plan: MRRacePlan, week: MRPlanWeek)? {
        let mon = weekMonday(of: monday, calendar: calendar)
        var best: (plan: MRRacePlan, week: MRPlanWeek)? = nil
        for plan in plans {
            // 대회가 이미 지난 주는 그 계획이 다스리지 않는다 (대회 주까지만).
            guard mon <= calendar.startOfDay(for: plan.raceDate) else { continue }
            guard let week = plan.weeks.first(where: { calendar.startOfDay(for: $0.monday) == mon }) else { continue }
            if let b = best, b.plan.raceDate <= plan.raceDate { continue }
            best = (plan, week)
        }
        return best
    }

    /// 날짜가 속한 주의 월요일 00:00.
    static func weekMonday(of date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
        return calendar.startOfDay(for: start)
    }

    /// 스냅샷(확정 계획)이 있는 주차는 스냅샷 값이 단일 소스다 — 주차표가 보여주는 숫자와 같아야 한다.
    /// 라이브 재계산 값(오늘 프로필로 다시 만든 것)은 스냅샷과 어긋날 수 있으므로,
    /// 월요일이 같은 주는 단계·롱런·주간·실행 안내를 스냅샷으로 덮는다. 스냅샷에 없는 주는 그대로.
    static func applyingSnapshot(_ weeks: [MRPlanWeek], snapshot: [MRPlanWeekSummary],
                                 easyPaceSecPerKm: Double?,
                                 calendar: Calendar = .current) -> [MRPlanWeek] {
        guard !snapshot.isEmpty else { return weeks }
        let byMonday = Dictionary(snapshot.map { (calendar.startOfDay(for: $0.monday), $0) },
                                  uniquingKeysWith: { a, _ in a })
        return weeks.map { w in
            guard let s = byMonday[calendar.startOfDay(for: w.monday)] else { return w }
            let mins = s.longRunKm * (easyPaceSecPerKm ?? 420) / 60.0
            // 포인트도 스냅샷 값 — 옛 스냅샷의 이번 주(nil)에 라이브 포인트가 새어 들지 않게(설계 6절 "이번 주 공백")
            // 단 테이퍼 강도 훈련의 페이스만은 라이브(대회 예상 평균과 같은 숫자, 2026-11-02) — 저장값 갱신 전에도 화면이 맞게
            var point = s.point
            if let sp = s.point, sp.kind == .racePaceShort, let lp = w.point, lp.kind == .racePaceShort,
               abs(lp.paceSecPerKm - sp.paceSecPerKm) >= 0.5 {
                point = MRPlanPoint(kind: sp.kind, totalKm: sp.totalKm, reps: sp.reps, repKm: sp.repKm,
                                    sustainedKm: sp.sustainedKm, paceSecPerKm: lp.paceSecPerKm)
            }
            return MRPlanWeek(idx: w.idx, monday: w.monday, phase: s.phase,
                              longRunKm: s.longRunKm, longRunMin: mins.rounded(),
                              weeklyKm: s.weeklyKm, projectedMin: w.projectedMin,
                              isNewMax: w.isNewMax, isVolRecord: w.isVolRecord,
                              breakdown: s.breakdown.isEmpty ? w.breakdown : s.breakdown,
                              point: point)
        }
    }

    /// "다른 계획을 따르는" 주의 단계 문자열 — 주차표에서 짧게 보이도록 "10K 계획" 꼴.
    static func followingPhase(distanceM: Double) -> String {
        "\(mrLabelFor(distanceM: distanceM)) 계획"
    }

    /// 단계 문자열이 "○○ 계획"(다른 계획을 따르는 주)인가.
    static func isFollowingPhase(_ phase: String) -> Bool {
        phase.hasSuffix(" 계획")
    }

    /// 따르는 계획의 그 주가 테이퍼·회복(의도적 저하)인가 — 정점 계산에서 제외할 주.
    static func isTaperLike(_ phase: String) -> Bool {
        phase == "테이퍼" || phase == "회복"
    }
}
