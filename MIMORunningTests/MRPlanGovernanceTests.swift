import Testing
import Foundation
@testable import MIMORunning

@Suite("MRPlanGovernance 이번 주를 다스리는 계획", .korean)
struct MRPlanGovernanceTests {

    private let cal = Calendar.current

    /// 오늘이 속한 주의 월요일 + `offset`주
    private func monday(_ offset: Int) -> Date {
        let base = MRPlanGovernance.weekMonday(of: Date())
        return cal.date(byAdding: .weekOfYear, value: offset, to: base)!
    }

    private func week(idx: Int, monday: Date, weeklyKm: Double, phase: String = "늘리기") -> MRPlanWeek {
        MRPlanWeek(idx: idx, monday: monday, phase: phase, longRunKm: weeklyKm * 0.35,
                   longRunMin: 60, weeklyKm: weeklyKm, projectedMin: 50, isNewMax: false,
                   breakdown: "bd\(idx)")
    }

    /// `firstMonday`부터 `count`주, 대회는 마지막 주 토요일
    private func plan(distanceM: Double, firstMonday: Date, count: Int, weeklyKm: (Int) -> Double) -> MRRacePlan {
        let lastMonday = cal.date(byAdding: .weekOfYear, value: count - 1, to: firstMonday)!
        let raceDate = cal.date(byAdding: .day, value: 5, to: lastMonday)!
        var p = MRRacePlan(raceDate: raceDate, distanceM: distanceM)
        p.weeks = (0..<count).map { i in
            week(idx: i + 1, monday: cal.date(byAdding: .weekOfYear, value: i, to: firstMonday)!, weeklyKm: weeklyKm(i))
        }
        return p
    }

    // 10K: 이번 주 −2 ~ +1 (4주, 대회 = +1주 토요일) · 하프: 이번 주 −2 ~ +7 (10주)
    private var tenK: MRRacePlan { plan(distanceM: MRDistance.d10, firstMonday: monday(-2), count: 4) { _ in 48 } }
    private var half: MRRacePlan { plan(distanceM: MRDistance.dH, firstMonday: monday(-2), count: 10) { _ in 41 } }

    @Test func earliestRaceGovernsWhileBothPlansHaveTheWeek() throws {
        // 하프를 먼저 넣어도 대회일이 이른 10K가 다스린다
        let g = try #require(MRPlanGovernance.governingWeek(plans: [half, tenK], monday: monday(0)))
        #expect(abs(g.plan.distanceM - MRDistance.d10) < 1)
        #expect(g.week.weeklyKm == 48)
    }

    @Test func raceWeekStillBelongsToTheEarlierRace() throws {
        // 10K 대회 주(+1) — 그 주 월요일은 대회일 이전이므로 10K가 다스린다
        let g = try #require(MRPlanGovernance.governingWeek(plans: [tenK, half], monday: monday(1)))
        #expect(abs(g.plan.distanceM - MRDistance.d10) < 1)
    }

    @Test func afterTheEarlierRaceTheNextPlanGoverns() throws {
        // 10K 대회(+1주 토) 이후 주(+2)는 10K 주차가 없으니 하프
        let g = try #require(MRPlanGovernance.governingWeek(plans: [tenK, half], monday: monday(2)))
        #expect(abs(g.plan.distanceM - MRDistance.dH) < 1)
        #expect(g.week.weeklyKm == 41)
    }

    @Test func earlierRaceDoesNotGovernPastItsRaceDateEvenIfWeeksExist() throws {
        // 10K 주차가 대회일 뒤까지 이어져 있어도(비정상 데이터) 대회가 지난 주는 다스리지 않는다
        var stale = tenK
        stale.weeks.append(week(idx: 5, monday: monday(2), weeklyKm: 99))
        let g = try #require(MRPlanGovernance.governingWeek(plans: [stale, half], monday: monday(2)))
        #expect(abs(g.plan.distanceM - MRDistance.dH) < 1)
    }

    @Test func singlePlan() throws {
        let g = try #require(MRPlanGovernance.governingWeek(plans: [half], monday: monday(3)))
        #expect(abs(g.plan.distanceM - MRDistance.dH) < 1)
        #expect(g.week.idx == 6)
    }

    @Test func noPlanForThatMondayIsNil() {
        #expect(MRPlanGovernance.governingWeek(plans: [tenK, half], monday: monday(-5)) == nil)
        #expect(MRPlanGovernance.governingWeek(plans: [], monday: monday(0)) == nil)
    }

    @Test func anyDateInTheWeekResolvesToItsMonday() throws {
        let wednesday = cal.date(byAdding: .day, value: 2, to: monday(0))!
        let g = try #require(MRPlanGovernance.governingWeek(plans: [half, tenK], monday: wednesday))
        #expect(cal.isDate(g.week.monday, inSameDayAs: monday(0)))
    }

    // MARK: - 스냅샷 덮어쓰기

    @Test func snapshotOverridesLiveWeekValues() {
        let live = tenK.weeks   // 48
        let snap = [MRPlanWeekSummary(idx: 3, monday: monday(0), phase: "유지",
                                      longRunKm: 14, weeklyKm: 52, breakdown: "snap")]
        let out = MRPlanGovernance.applyingSnapshot(live, snapshot: snap, easyPaceSecPerKm: 360)
        let w = out.first { cal.isDate($0.monday, inSameDayAs: monday(0)) }!
        #expect(w.weeklyKm == 52)
        #expect(w.longRunKm == 14)
        #expect(w.phase == "유지")
        #expect(w.breakdown == "snap")
        #expect(w.longRunMin == 84)          // 14km × 6분
        // 스냅샷에 없는 주는 그대로
        #expect(out.filter { $0.weeklyKm == 48 }.count == live.count - 1)
        #expect(MRPlanGovernance.applyingSnapshot(live, snapshot: [], easyPaceSecPerKm: nil).map(\.weeklyKm) == live.map(\.weeklyKm))
    }

    @Test func followingPhaseLabel() {
        #expect(MRPlanGovernance.followingPhase(distanceM: MRDistance.d10) == "10K 계획")
        #expect(MRPlanGovernance.isFollowingPhase("10K 계획"))
        #expect(!MRPlanGovernance.isFollowingPhase("대회 주"))
    }

    // MARK: - 플래너: 하프의 겹치는 주가 10K 자기 계획 숫자를 그대로 따른다

    private func makeProfile() -> MRProfile {
        var p = MRProfile()
        p.weeklyKm4w = 30; p.longestRun16wKm = 14
        p.maxWeeklyKm52w = 45; p.runsPerWeek = 4; p.marathonFinishes = 0
        return p
    }

    @Test func halfPlanFollowsTenKOwnPlanOnEveryOverlappingWeekIncludingRaceWeek() throws {
        let today = Date()
        let anchor = monday(-2)                                  // 10K 계획은 2주 전에 시작(스냅샷 앵커)
        let tenKDate = cal.date(byAdding: .day, value: 5, to: monday(3))!   // 5주 뒤 토요일
        let halfDate = cal.date(byAdding: .day, value: 5, to: monday(11))!  // 13주 뒤 토요일
        let tenKPlan = try #require(mrBuildPlan(raceDate: tenKDate, distanceM: MRDistance.d10, today: today,
                                                profile: makeProfile(), halfEquivMin: 110,
                                                easyPaceSecPerKm: 400, heat: MRHeatModel(), raceTempC: 15,
                                                runsPerWeek: 4, forcedMonday: anchor))
        // 스냅샷에서 온 숫자라고 가정 — 라이브와 다른 값을 덮어 A 계획이 그 값을 따르는지 본다
        let snapshot = tenKPlan.weeks.map { w in
            MRPlanWeekSummary(idx: w.idx, monday: w.monday, phase: w.phase,
                              longRunKm: w.longRunKm + 1, weeklyKm: w.weeklyKm + 7, breakdown: "S\(w.idx)")
        }
        let own = MRPlanGovernance.applyingSnapshot(tenKPlan.weeks, snapshot: snapshot, easyPaceSecPerKm: 400)
        let tune = MRTuneUpRace(date: tenKDate, name: "10K", distanceM: MRDistance.d10,
                                hasOwnPlan: true, ownPlanWeeks: own)
        let halfPlan = try #require(mrBuildPlan(raceDate: halfDate, distanceM: MRDistance.dH, today: today,
                                                profile: makeProfile(), halfEquivMin: 110,
                                                easyPaceSecPerKm: 400, heat: MRHeatModel(), raceTempC: 15,
                                                runsPerWeek: 4, tuneUps: [tune]))
        let halfByMonday = Dictionary(halfPlan.weeks.map { (cal.startOfDay(for: $0.monday), $0) },
                                      uniquingKeysWith: { a, _ in a })
        // 10K 계획에 있는 주 가운데 하프 계획에도 있는 주(오늘 이후)는 전부 같은 숫자 · "10K 계획" 단계
        var checked = 0
        for w in own where cal.startOfDay(for: w.monday) <= cal.startOfDay(for: tenKDate) {
            guard let h = halfByMonday[cal.startOfDay(for: w.monday)] else { continue }
            checked += 1
            #expect(h.weeklyKm == w.weeklyKm, "W\(w.idx) 주간")
            #expect(h.longRunKm == w.longRunKm, "W\(w.idx) 롱런")
            #expect(h.longRunMin == w.longRunMin, "W\(w.idx) 롱런 분")
            #expect(h.phase == "10K 계획", "W\(w.idx) 단계 = \(h.phase)")
            #expect(h.breakdown.contains("계획을 따릅니다") || h.breakdown.contains("Follows the"))
            #expect(h.breakdown.hasSuffix(w.breakdown))
        }
        // 하프는 이번 주(0)부터 시작하므로 0·+1·+2 세 주가 겹친다 (10K 주차는 대회 전 주까지)
        #expect(checked >= 3)
        // 10K 주차표에 없는 대회 주(+3)는 기존 튠업 규칙("대회 주") — 따를 숫자가 없다
        let raceWeek = try #require(halfByMonday[cal.startOfDay(for: monday(3))])
        #expect(raceWeek.phase == "대회 주")
        // 10K 이후 주는 하프 고유 진행
        let after = try #require(halfByMonday[cal.startOfDay(for: monday(4))])
        #expect(after.phase != "10K 계획")
        // 어느 계획을 물어도 같은 숫자
        let g = try #require(MRPlanGovernance.governingWeek(plans: [halfPlan, tenKPlan], monday: monday(1)))
        #expect(abs(g.plan.distanceM - MRDistance.d10) < 1)
        let hw = try #require(halfByMonday[cal.startOfDay(for: monday(1))])
        #expect(hw.weeklyKm == own.first { cal.isDate($0.monday, inSameDayAs: monday(1)) }!.weeklyKm)
    }
}
