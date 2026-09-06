import Testing
import Foundation
@testable import MIMORunning

@Suite("MRRacePlanner 대회 페이스 단계")
struct MRRacePlannerRacePaceTests {

    @Test func segmentMinutesIs15ForLongRunsAnd10ForShort() {
        #expect(mrRacePaceSegmentMinutes(longRunMin: 140) == 15)
        #expect(mrRacePaceSegmentMinutes(longRunMin: 60) == 15)
        #expect(mrRacePaceSegmentMinutes(longRunMin: 59) == 10)
    }

    @Test func trainingRacePaceForHalfIgnoresHeatAndTaper() {
        // 하프 등가 110분 → 110×60/21.0975 = 312.8 초/km
        let p = mrTrainingRacePaceSecPerKm(halfEquivMin: 110, distanceM: MRDistance.dH,
                                           weeklyKm: 40, longestKm: 21, finishes: 0)
        #expect(abs(p - 312.8) < 0.2)
    }

    @Test func trainingRacePaceForFullUsesMarathonModel() {
        let b = bMarathonModel(weeklyKm: 50, longestKm: 28, finishes: 1).b
        let expected = 110 * pow(2.0, b) * 60 / 42.195
        let p = mrTrainingRacePaceSecPerKm(halfEquivMin: 110, distanceM: MRDistance.dF,
                                           weeklyKm: 50, longestKm: 28, finishes: 1)
        #expect(abs(p - expected) < 0.01)
    }

    private func makeProfile() -> MRProfile {
        var p = MRProfile()
        p.weeklyKm4w = 30; p.longestRun16wKm = 14
        p.maxWeeklyKm52w = 45; p.runsPerWeek = 4; p.marathonFinishes = 0
        return p
    }

    private func buildPlan(distanceM: Double, weeks: Int = 20) -> MRRacePlan? {
        let today = Date()
        let race = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: today)!
        return mrBuildPlan(raceDate: race, distanceM: distanceM, today: today,
                           profile: makeProfile(), halfEquivMin: 110,
                           easyPaceSecPerKm: 400, heat: MRHeatModel(), raceTempC: 15,
                           runsPerWeek: 4)
    }

    @Test func halfPlanGetsRacePaceWeeksWithSegmentText() throws {
        let plan = try #require(buildPlan(distanceM: MRDistance.dH))
        let rp = plan.weeks.filter { $0.phase == "대회 페이스" }
        #expect(!rp.isEmpty)
        // 문구에 구간 길이(15)와 페이스(/km)가 들어간다. 언어 무관 토큰만 검사.
        #expect(rp.allSatisfy {
            ($0.breakdown.contains("15분") || $0.breakdown.contains("15 min")) && $0.breakdown.contains("/km")
        })
        // 대회 페이스가 아닌 모든 주에는 구간 문구가 없다
        let rest = plan.weeks.filter { $0.phase != "대회 페이스" }
        #expect(rest.allSatisfy { !$0.breakdown.contains("/km") })
    }

    @Test func projectedRefMinMatchesLoopProjection() throws {
        // 기온 모델 꺼짐 → 보정 없음. 하프는 weeklyKm/longestKm를 쓰지 않으므로 아무 값이나 된다.
        let plan = try #require(buildPlan(distanceM: MRDistance.dH))
        let ref = mrProjectedRefMin(halfEquivMin: 110, distanceM: MRDistance.dH,
                                    weeklyKm: 0, longestKm: 0, finishes: 0)
        let nonTaper = plan.weeks.filter { $0.phase != "테이퍼" }
        #expect(!nonTaper.isEmpty)
        #expect(nonTaper.allSatisfy { abs($0.projectedMin - ref) < 0.01 })
    }

    @Test func tenKPlanHasNoRacePaceWeeks() throws {
        let plan = try #require(buildPlan(distanceM: MRDistance.d10))
        #expect(plan.weeks.allSatisfy { $0.phase != "대회 페이스" })
    }

    @Test func fullPlanRacePaceWeeksAlsoGetSegmentText() throws {
        var p = makeProfile()
        p.weeklyKm4w = 45; p.longestRun16wKm = 22; p.maxWeeklyKm52w = 60
        let today = Date()
        let race = Calendar.current.date(byAdding: .day, value: 7 * 24, to: today)!
        let plan = try #require(mrBuildPlan(raceDate: race, distanceM: MRDistance.dF, today: today,
                                            profile: p, halfEquivMin: 110, easyPaceSecPerKm: 400,
                                            heat: MRHeatModel(), raceTempC: 15, runsPerWeek: 4))
        let rp = plan.weeks.filter { $0.phase == "대회 페이스" }
        #expect(!rp.isEmpty)
        #expect(rp.allSatisfy { $0.breakdown.contains("/km") })
    }
}
