import Testing
import Foundation
@testable import MIMORunning

/// 계획의 '지금 나가면'은 대회 거리 직접 예측과 같아야 한다 — 나 탭 대회 비교의 예상 기록과 한 숫자.
@Suite("계획 예상 기록 — 직접 예측에 맞춤", .korean)
struct MRPlanProjectionScaleTests {

    private func plan(nowRefMin: Double?) -> MRRacePlan? {
        var pr = MRProfile()
        pr.weeklyKm4w = 30; pr.longestRun16wKm = 14
        pr.maxWeeklyKm52w = 45; pr.runsPerWeek = 4; pr.marathonFinishes = 0
        let today = Date()
        let race = Calendar.current.date(byAdding: .day, value: 7 * 10, to: today)!
        return mrBuildPlan(raceDate: race, distanceM: MRDistance.d10, today: today,
                           profile: pr, halfEquivMin: 115, easyPaceSecPerKm: 400,
                           heat: MRHeatModel(), raceTempC: 15, runsPerWeek: 4,
                           nowRefMin: nowRefMin)
    }

    @Test func nowMatchesDirectAndFinalMovesTogether() throws {
        let base = try #require(plan(nowRefMin: nil))
        let direct = base.projectedNow - 0.35            // 21초 빠른 직접 예측
        let p = try #require(plan(nowRefMin: direct))
        #expect(abs(p.projectedNow - direct) < 1e-9)
        let k = direct / base.projectedNow
        #expect(abs(p.projectionScale - k) < 1e-9)
        #expect(abs(p.projectedFinal - base.projectedFinal * k) < 1e-6)
        for (a, b) in zip(p.weeks, base.weeks) {
            #expect(abs(a.projectedMin - b.projectedMin * k) < 1e-6)
        }
    }

    @Test func noDirectPredictionKeepsOldValues() throws {
        let p = try #require(plan(nowRefMin: nil))
        #expect(p.projectionScale == 1.0)
    }
}
