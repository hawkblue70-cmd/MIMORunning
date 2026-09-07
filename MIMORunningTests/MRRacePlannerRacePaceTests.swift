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

@Suite("MRRacePlanner 앞선 대회 회복 블록")
struct MRRacePlannerPriorRaceTests {

    private func profile() -> MRProfile {
        var p = MRProfile()
        p.weeklyKm4w = 35; p.longestRun16wKm = 16
        p.maxWeeklyKm52w = 60; p.runsPerWeek = 4; p.marathonFinishes = 1
        return p
    }

    private func build(distanceM: Double, weeks: Int,
                       prior: (weeksBefore: Int, distanceM: Double)?) -> MRRacePlan? {
        let cal = Calendar.current
        let today = Date()
        let race = cal.date(byAdding: .day, value: 7 * weeks, to: today)!
        let priorTuple = prior.map { pr -> (date: Date, name: String, distanceM: Double, peakLong: Double, peakVol: Double) in
            (date: cal.date(byAdding: .day, value: -7 * pr.weeksBefore, to: race)!,
             name: "앞대회", distanceM: pr.distanceM, peakLong: 16, peakVol: 40)
        }
        return mrBuildPlan(raceDate: race, distanceM: distanceM, today: today,
                           profile: profile(), halfEquivMin: 110, easyPaceSecPerKm: 400,
                           heat: MRHeatModel(), raceTempC: 15, runsPerWeek: 4,
                           priorRace: priorTuple)
    }

    @Test func tenKSixWeeksBeforeHalfDoesNotBlockThePlan() throws {
        // 11/15 하프 사례: 10주 뒤 하프, 6주 전 10K → 회복 블록 없이 지금부터 계획
        let plan = try #require(build(distanceM: MRDistance.dH, weeks: 10, prior: (6, MRDistance.d10)))
        #expect(plan.startDate == nil || plan.startNote.isEmpty)
        #expect(!plan.startNote.contains("회복"))
        #expect(plan.weeks.first?.phase != "회복")
    }

    @Test func halfBeforeFullGetsOneRecoveryWeek() throws {
        let plan = try #require(build(distanceM: MRDistance.dF, weeks: 20, prior: (12, MRDistance.dH)))
        #expect(plan.startNote.contains("회복 1주"))
        #expect(plan.weeks.first?.phase == "회복")
        #expect(plan.weeks.dropFirst().first?.phase != "회복")
    }

    @Test func fullBeforeFullGetsThreeRecoveryWeeks() throws {
        let plan = try #require(build(distanceM: MRDistance.dF, weeks: 24, prior: (14, MRDistance.dF)))
        #expect(plan.startNote.contains("회복 3주"))
        #expect(plan.weeks.prefix(3).allSatisfy { $0.phase == "회복" })
    }
}

@Suite("MRRacePlanner 튠업 대회 주")
struct MRRacePlannerTuneUpTests {

    private let cal = Calendar.current

    private func profile() -> MRProfile {
        var p = MRProfile()
        p.weeklyKm4w = 35; p.longestRun16wKm = 16
        p.maxWeeklyKm52w = 60; p.runsPerWeek = 4; p.marathonFinishes = 1
        return p
    }

    private func build(distanceM: Double, weeks: Int, tuneUps: [(weeksBefore: Int, distanceM: Double)]) -> MRRacePlan? {
        let today = Date()
        let race = cal.date(byAdding: .day, value: 7 * weeks, to: today)!
        let tus = tuneUps.map { t in
            MRTuneUpRace(date: cal.date(byAdding: .day, value: -7 * t.weeksBefore, to: race)!,
                         name: "튠업", distanceM: t.distanceM)
        }
        return mrBuildPlan(raceDate: race, distanceM: distanceM, today: today,
                           profile: profile(), halfEquivMin: 110, easyPaceSecPerKm: 400,
                           heat: MRHeatModel(), raceTempC: 15, runsPerWeek: 4, tuneUps: tus)
    }

    @Test func tenKInsideHalfPlanBecomesRaceWeekAndKeepsLongRun() throws {
        let plan = try #require(build(distanceM: MRDistance.dH, weeks: 10, tuneUps: [(4, MRDistance.d10)]))
        let base = try #require(build(distanceM: MRDistance.dH, weeks: 10, tuneUps: []))
        let idx = try #require(plan.weeks.firstIndex { $0.phase == "대회 주" })
        let w = plan.weeks[idx]
        #expect(w.breakdown.contains("10K") && w.breakdown.contains("롱런"))
        // 롱런은 흡수 전과 같다(유지), 주간 거리는 줄어든다
        #expect(abs(w.longRunKm - base.weeks[idx].longRunKm) < 0.01)
        #expect(w.weeklyKm < base.weeks[idx].weeklyKm)
        #expect(plan.absorbedTuneUpDates.count == 1)
        // 대회 주 이후 진행은 계속된다 — 다음 주 롱런이 대회 주보다 작지 않다 (회복 주가 아니면)
        if idx + 1 < plan.weeks.count, plan.weeks[idx + 1].phase != "회복" {
            #expect(plan.weeks[idx + 1].longRunKm >= w.longRunKm - 0.01)
        }
    }

    @Test func halfInsideFullPlanIsTheLongRunAndNextWeekRecovers() throws {
        let plan = try #require(build(distanceM: MRDistance.dF, weeks: 24, tuneUps: [(10, MRDistance.dH)]))
        let idx = try #require(plan.weeks.firstIndex { $0.phase == "대회 주" })
        #expect(abs(plan.weeks[idx].longRunKm - 21.1) < 0.2)
        #expect(plan.weeks[idx].breakdown.contains("하프"))
        #expect(plan.weeks[idx + 1].phase == "회복")
        #expect(plan.notes.contains { $0.contains("2주 늦어집니다") })
    }

    @Test func tuneUpBeforePlanStartIsNotAbsorbed() throws {
        // 20주 뒤 하프 — 필요 기간이 짧아 시작이 뒤로 밀린다. 그 대기 구간의 10K는 흡수되지 않는다.
        let plan = try #require(build(distanceM: MRDistance.dH, weeks: 20, tuneUps: [(19, MRDistance.d10)]))
        #expect(plan.startDate != nil)
        #expect(plan.absorbedTuneUpDates.isEmpty)
        #expect(!plan.weeks.contains { $0.phase == "대회 주" })
    }

    @Test func candidatesExcludeFullAndOutOfRange() {
        let today = Date()
        func race(_ days: Int, _ d: Double, _ n: String) -> MRTargetRace {
            MRTargetRace(date: cal.date(byAdding: .day, value: days, to: today)!, distanceM: d, name: n)
        }
        let a = race(70, MRDistance.dH, "A하프")
        let all = [race(28, MRDistance.d10, "10K"), race(35, MRDistance.dF, "풀"), race(80, MRDistance.d5, "뒤5K"),
                   race(-3, MRDistance.d10, "지난10K"), race(40, MRDistance.dH, "다른하프"), a]
        let c = mrTuneUpCandidates(for: a, among: all, today: today)
        #expect(c.map(\.name) == ["10K"])          // 풀·범위 밖·하프(A가 하프일 때) 제외
        let full = race(150, MRDistance.dF, "A풀")
        let c2 = mrTuneUpCandidates(for: full, among: all + [full], today: today)
        #expect(c2.map(\.name).contains("다른하프") && c2.map(\.name).contains("A하프"))
    }
}

@Suite("MRRacePlanner 자기 계획 있는 튠업의 전 주 테이퍼")
struct MRRacePlannerOwnPlanTuneUpTests {
    private let cal = Calendar.current

    private func build(ownPlan: Bool) -> MRRacePlan? {
        var p = MRProfile()
        p.weeklyKm4w = 35; p.longestRun16wKm = 16; p.maxWeeklyKm52w = 60; p.runsPerWeek = 4
        let today = Date()
        let race = cal.date(byAdding: .day, value: 70, to: today)!
        let tu = MRTuneUpRace(date: cal.date(byAdding: .day, value: -28, to: race)!,
                              name: "10K", distanceM: MRDistance.d10, hasOwnPlan: ownPlan)
        return mrBuildPlan(raceDate: race, distanceM: MRDistance.dH, today: today,
                           profile: p, halfEquivMin: 110, easyPaceSecPerKm: 400,
                           heat: MRHeatModel(), raceTempC: 15, runsPerWeek: 4, tuneUps: [tu])
    }

    @Test func weekBeforeOwnPlanRaceBecomesTaper() throws {
        let plan = try #require(build(ownPlan: true))
        let raceIdx = try #require(plan.weeks.firstIndex { $0.breakdown.contains("10K 대회 +") })
        let pre = plan.weeks[raceIdx - 1]
        #expect(pre.phase == "대회 주")
        #expect(pre.breakdown.contains("대회 전 주"))
        #expect(pre.weeklyKm < plan.weeks[raceIdx - 2].weeklyKm * 0.7)
        #expect(pre.longRunKm < plan.weeks[raceIdx - 2].longRunKm)
    }

    @Test func weekBeforeAbsorbedRaceStaysNormal() throws {
        let plan = try #require(build(ownPlan: false))
        let raceIdx = try #require(plan.weeks.firstIndex { $0.breakdown.contains("10K 대회 +") })
        #expect(plan.weeks[raceIdx - 1].phase != "대회 주")
        #expect(!plan.weeks[raceIdx - 1].breakdown.contains("대회 전 주"))
    }

    @Test func candidatesMarkOwnPlanByArchiveKey() {
        let today = Date()
        let a = MRTargetRace(date: cal.date(byAdding: .day, value: 70, to: today)!, distanceM: MRDistance.dH, name: "하프")
        let t = MRTargetRace(date: cal.date(byAdding: .day, value: 42, to: today)!, distanceM: MRDistance.d10, name: "10K")
        let key = mrArchiveKey(raceDate: t.date, distanceM: t.distanceM)
        #expect(mrTuneUpCandidates(for: a, among: [a, t], today: today, plannedKeys: [key]).first?.hasOwnPlan == true)
        #expect(mrTuneUpCandidates(for: a, among: [a, t], today: today).first?.hasOwnPlan == false)
    }
}

@Suite("MRRacePlanner 앞선 대회 타임라인")
struct MRRacePlannerBridgeRowTests {
    @Test func fullAfterHalfShowsHalfInTimeline() throws {
        let cal = Calendar.current
        var p = MRProfile()
        p.weeklyKm4w = 35; p.longestRun16wKm = 16; p.maxWeeklyKm52w = 60; p.runsPerWeek = 4; p.marathonFinishes = 1
        let today = Date()
        let race = cal.date(byAdding: .day, value: 7 * 28, to: today)!
        let half = cal.date(byAdding: .day, value: 7 * 10, to: today)!
        let plan = try #require(mrBuildPlan(raceDate: race, distanceM: MRDistance.dF, today: today,
                                            profile: p, halfEquivMin: 110, easyPaceSecPerKm: 400,
                                            heat: MRHeatModel(), raceTempC: 15, runsPerWeek: 4,
                                            priorRace: (date: half, name: "가을하프", distanceM: MRDistance.dH,
                                                        peakLong: 21, peakVol: 56)))
        #expect(plan.bridgeRows.count == 3)
        #expect(plan.bridgeRows[0].text.contains("가을하프"))
        #expect(plan.bridgeRows[1].text.hasPrefix("대회 주"))
        #expect(plan.bridgeRows[2].text.hasPrefix("이 계획 시작"))
        #expect(plan.weeks.first?.phase == "회복")
    }
}
