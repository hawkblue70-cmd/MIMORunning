import Testing
import Foundation
@testable import MIMORunning

/// 계획 카드의 숫자가 서로 같은 기준인지 — 2027 서울마라톤 화면(2026-11-02)에서 나온 세 가지.
@Suite("목표 점검·계획 예상 — 같은 기준", .korean)
struct MRGoalCheckConsistencyTests {

    private func profile(maxWeekly: Double = 60) -> MRProfile {
        var p = MRProfile()
        p.weeklyKm4w = 35; p.longestRun16wKm = 16
        p.maxWeeklyKm52w = maxWeekly; p.runsPerWeek = 4; p.marathonFinishes = 1
        return p
    }

    private func fullPlan(weeks: Int, prior: (weeksBefore: Int, peakLong: Double, peakVol: Double)? = nil,
                          nowRefMin: Double? = nil, maxWeekly: Double = 60) -> MRRacePlan? {
        let cal = Calendar.current
        let today = Date()
        let race = cal.date(byAdding: .day, value: 7 * weeks, to: today)!
        let priorTuple = prior.map { pr -> (date: Date, name: String, distanceM: Double, peakLong: Double, peakVol: Double) in
            (date: cal.date(byAdding: .day, value: -7 * pr.weeksBefore, to: race)!,
             name: "앞대회", distanceM: MRDistance.dH, peakLong: pr.peakLong, peakVol: pr.peakVol)
        }
        return mrBuildPlan(raceDate: race, distanceM: MRDistance.dF, today: today,
                           profile: profile(maxWeekly: maxWeekly), halfEquivMin: 110, easyPaceSecPerKm: 400,
                           heat: MRHeatModel(), raceTempC: 15, runsPerWeek: 4,
                           priorRace: priorTuple, nowRefMin: nowRefMin)
    }

    /// 앞 대회 뒤 재시작(롱런 60%·주간 70%)은 처방이지 몸의 후퇴가 아니다 —
    /// '늘리기' 주 예상이 앞 대회 정점 상태보다 느리면 안 된다(회복 4:36:40 → 늘리기 4:37:58).
    @Test func buildWeeksAfterPriorRaceDoNotProjectSlowerThanPriorPeak() throws {
        let plan = try #require(fullPlan(weeks: 24, prior: (12, 16, 40)))
        #expect(plan.weeks.first?.phase == "회복")
        let ref = mrProjectedRefMin(halfEquivMin: 110, distanceM: MRDistance.dF,
                                    weeklyKm: 40, longestKm: 16, finishes: 1) * plan.projectionScale
        let build = plan.weeks.filter { $0.phase != "회복" && $0.phase != "테이퍼" }
        #expect(!build.isEmpty)
        #expect(build.allSatisfy { $0.projectedMin <= ref + 0.01 })
        #expect(plan.projectionWeeklyKm >= 40 - 1e-9)
        #expect(plan.projectionLongKm >= max(plan.reachableLongKm, 16) - 1e-9)
    }

    /// 레버는 계획후(projectedFinal)와 같은 보정 배율로 — 롱런 효과는 28km에서 끝나므로
    /// 28km에 닿은 계획에 "롱런 32km"가 더 빠른 값으로 나오면 안 된다(32km → 4:08:18 vs 계획후 4:17:59).
    @Test func leversUseProjectionScaleAndVerdictMatchesLevers() throws {
        let base = try #require(fullPlan(weeks: 24))
        let plan = try #require(fullPlan(weeks: 24, nowRefMin: base.projectedNow * 1.04))
        #expect(abs(plan.projectionScale - 1.04) < 1e-6)
        let goalMin = plan.projectedFinal * 0.95          // 약 5% 모자람 → '조금 모자랍니다' 구간
        let race = MRTargetRace(date: plan.raceDate, distanceM: MRDistance.dF, name: "테스트")
        let check = mrCheckGoal(race: race, plan: plan,
                                goals: MRGoals(fullSec: Int(goalMin * 60)),
                                profile: profile(), halfEquivMin: 110,
                                heat: MRHeatModel(), raceTempC: 15)
        if plan.reachableLongKm >= 28 - 0.1 {
            #expect(!check.levers.contains { $0.contains("32km") })
        }
        // 레버는 모두 이 계획 밖(⚠)이다 → '아래를 바꾸면 메워집니다'라고 하지 않는다
        #expect(check.levers.allSatisfy { $0.contains("⚠") })
        #expect(!check.verdict.contains("메워집니다"))
        #expect(check.verdict.contains("더 줄일 항목이 없습니다"))
    }

    /// 풀 계획은 주간 거리를 지난 1년 최고치까지만 올린다 — 그 위의 레버는 기간 탓이 아니다.
    /// '주 60km → 18주로는 도달 불가'는 틀린 이유였다(지난 1년 최고 아래로 막힌 것).
    @Test func weeklyLeverAboveYearHighSaysPlanCeilingNotWeeks() throws {
        let plan = try #require(fullPlan(weeks: 24, maxWeekly: 45))
        #expect(abs(plan.weeklyCapKm - 45) < 0.5)
        let goalMin = plan.projectedFinal * 0.95
        let race = MRTargetRace(date: plan.raceDate, distanceM: MRDistance.dF, name: "테스트")
        let check = mrCheckGoal(race: race, plan: plan,
                                goals: MRGoals(fullSec: Int(goalMin * 60)),
                                profile: profile(maxWeekly: 45), halfEquivMin: 110,
                                heat: MRHeatModel(), raceTempC: 15)
        let weekly = check.levers.filter { $0.hasPrefix("주 ") }
        #expect(!weekly.isEmpty)
        #expect(weekly.allSatisfy { $0.contains("계획 상한(지난 1년 최고 45km)") && !$0.contains("도달 불가") })
    }
}
