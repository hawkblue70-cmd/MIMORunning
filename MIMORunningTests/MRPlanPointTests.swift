import Testing
import Foundation
@testable import MIMORunning

@Suite("포인트 훈련 — 모델·양·페이스", .korean)
struct MRPlanPointTests {

    @Test func speedRepsAreEightPercentOfWeeklyClampedThreeToSix() throws {
        let a = try #require(MRPlanPoint.make(kind: .speed, weeklyKm: 30, longRunKm: 14, raceDistanceM: MRDistance.dH, paceSecPerKm: 300))
        #expect(a.reps == 3)                       // 2.4 → 2 → 하한 3
        #expect(abs(a.totalKm - 7.0) < 0.01)       // 2 + 3×1 + 2×0.5(3분) + 1
        let b = try #require(MRPlanPoint.make(kind: .speed, weeklyKm: 60, longRunKm: 18, raceDistanceM: MRDistance.dH, paceSecPerKm: 300))
        #expect(b.reps == 5)                       // 4.8 → 5
        let c = try #require(MRPlanPoint.make(kind: .speed, weeklyKm: 100, longRunKm: 28, raceDistanceM: MRDistance.dF, paceSecPerKm: 300))
        #expect(c.reps == 6)                       // 8 → 상한 6
    }

    @Test func tempoIsTenPercentOfWeeklyClampedThreeToEight() throws {
        let a = try #require(MRPlanPoint.make(kind: .tempo, weeklyKm: 30, longRunKm: 14, raceDistanceM: nil, paceSecPerKm: 300))
        #expect(a.sustainedKm == 3)
        #expect(abs(a.totalKm - 6) < 0.01)         // 2 + 3 + 1
        let b = try #require(MRPlanPoint.make(kind: .tempo, weeklyKm: 50, longRunKm: 16, raceDistanceM: nil, paceSecPerKm: 300))
        #expect(b.sustainedKm == 5)
        let c = try #require(MRPlanPoint.make(kind: .tempo, weeklyKm: 100, longRunKm: 28, raceDistanceM: nil, paceSecPerKm: 300))
        #expect(c.sustainedKm == 8)
    }

    @Test func buildUpDistanceByRaceCappedBySeventyPercentOfLongRun() throws {
        let half = try #require(MRPlanPoint.make(kind: .buildUp, weeklyKm: 40, longRunKm: 16, raceDistanceM: MRDistance.dH, paceSecPerKm: 310))
        #expect(half.totalKm == 10)                // min(10, 11)
        #expect(abs((half.sustainedKm ?? 0) - 3.3) < 0.01)
        let full = try #require(MRPlanPoint.make(kind: .buildUp, weeklyKm: 50, longRunKm: 16, raceDistanceM: MRDistance.dF, paceSecPerKm: 330))
        #expect(full.totalKm == 11)                // min(14, 11.2 내림 11)
        let tenK = try #require(MRPlanPoint.make(kind: .buildUp, weeklyKm: 30, longRunKm: 12, raceDistanceM: MRDistance.d10, paceSecPerKm: 290))
        #expect(tenK.totalKm == 8)
        let noRace = try #require(MRPlanPoint.make(kind: .buildUp, weeklyKm: 40, longRunKm: 18, raceDistanceM: nil, paceSecPerKm: 310))
        #expect(noRace.totalKm == 10)
        // 롱런 6km → 4.2 내림 4 < 5 → 없음
        #expect(MRPlanPoint.make(kind: .buildUp, weeklyKm: 20, longRunKm: 6, raceDistanceM: MRDistance.dH, paceSecPerKm: 310) == nil)
    }

    @Test func racePaceShortIsThreeByOneKm() throws {
        let p = try #require(MRPlanPoint.make(kind: .racePaceShort, weeklyKm: 25, longRunKm: 10, raceDistanceM: MRDistance.dH, paceSecPerKm: 312))
        #expect(p.reps == 3)
        #expect(abs(p.totalKm - 6.3) < 0.01)       // 2 + 3 + 2×0.15(1분) + 1
    }

    @Test func zeroPaceMakesNoPoint() {
        #expect(MRPlanPoint.make(kind: .tempo, weeklyKm: 40, longRunKm: 14, raceDistanceM: nil, paceSecPerKm: 0) == nil)
    }

    @Test func pacesComeFromHalfEquivalentByRiegel() throws {
        let p = try #require(mrPointPaces(halfEquivMin: 110))
        #expect(abs(p.half - 312.8) < 0.2)         // 110×60/21.0975
        #expect(p.fiveK < p.tenK && p.tenK < p.half)
        #expect(p.tempo > p.tenK && p.tempo < p.half)
        #expect(mrPointPaces(halfEquivMin: 5) == nil)
    }

    @Test func kindFollowsPlanPhase() {
        #expect(mrPointKind(phase: "늘리기") == .speed)
        #expect(mrPointKind(phase: "유지") == .tempo)
        #expect(mrPointKind(phase: "대회 페이스") == .buildUp)
        #expect(mrPointKind(phase: "테이퍼") == .racePaceShort)
        #expect(mrPointKind(phase: "회복") == nil)
        #expect(mrPointKind(phase: "대회 주") == nil)
        #expect(mrPointKind(phase: "10K 계획") == nil)
    }

    @Test func intervalDaysFromRunsPerWeek() {
        #expect(mrPointIntervalDays(runsPerWeek: 4.2) == 7)
        #expect(mrPointIntervalDays(runsPerWeek: 5) == 7)
        #expect(mrPointIntervalDays(runsPerWeek: 3.4) == 14)
        #expect(mrPointIntervalDays(runsPerWeek: 2.6) == 14)   // 반올림 3
        #expect(mrPointIntervalDays(runsPerWeek: 2.4) == nil)
    }

    @Test func rotationSpeedTempoBuildUp() {
        #expect(MRPlanPoint.nextKind(after: .interval) == .tempo)
        #expect(MRPlanPoint.nextKind(after: .tempo) == .buildUp)
        #expect(MRPlanPoint.nextKind(after: .buildUp) == .speed)
        #expect(MRPlanPoint.nextKind(after: .distanceRun) == .speed)
        #expect(MRPlanPoint.nextKind(after: nil) == .buildUp)
        #expect(MRPlanPoint.nextKind(after: .race) == .buildUp)
    }

    @Test func koreanText() {
        let s = MRPlanPoint(kind: .speed, totalKm: 8.2, reps: 4, repKm: 1, sustainedKm: nil, paceSecPerKm: 305)
        #expect(s.text == "인터벌 1km × 4회 5'05\"")
        let t = MRPlanPoint(kind: .tempo, totalKm: 8, reps: nil, repKm: nil, sustainedKm: 5, paceSecPerKm: 320)
        #expect(t.text == "템포런 5km 5'20\"")
        let b = MRPlanPoint(kind: .buildUp, totalKm: 10, reps: nil, repKm: nil, sustainedKm: 3.3, paceSecPerKm: 330)
        #expect(b.text == "빌드업 10km · 마지막 3.3km 5'30\"")
        let r = MRPlanPoint(kind: .racePaceShort, totalKm: 6.8, reps: 3, repKm: 1, sustainedKm: nil, paceSecPerKm: 312)
        #expect(r.text == "대회 페이스 1km × 3회 5'12\"")
    }

    @Test func breakdownEasyNumbersReplacedKeepingLanguage() {
        #expect(mrBreakdownReplacingEasy("롱런 16km + 이지 6.4km × 3회", easyKm: 7, runs: 2) == "롱런 16km + 이지 7km × 2회")
        #expect(mrBreakdownReplacingEasy("Long run 16km + Easy 6.4km × 3x", easyKm: 5.5, runs: 2) == "Long run 16km + Easy 5.5km × 2x")
        #expect(mrBreakdownReplacingEasy("롱런 18km · 마지막 15분은 5'12\"/km + 이지 6km × 3회", easyKm: 4.2, runs: 2)
                == "롱런 18km · 마지막 15분은 5'12\"/km + 이지 4.2km × 2회")
        #expect(mrBreakdownReplacingEasy("롱런 10km + 짧게 3.5km × 3회 · 강도는 그대로", easyKm: 3, runs: 2)
                == "롱런 10km + 짧게 3km × 2회 · 강도는 그대로")
        #expect(mrBreakdownReplacingEasy("롱런 8km + 이지 3회", easyKm: 2, runs: 2) == nil)
    }

    private func run(_ day: Int, km: Double) -> MRWorkout {
        let start = Date(timeIntervalSince1970: 1_791_000_000 + Double(day) * 86_400)
        return MRWorkout(start: start, durationMin: km * 6, distanceKm: km, hrAvg: 145, hrMax: 170,
                         tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }

    @Test func pointRunExcludesTheLongRunAndUsesHardOrType() {
        let easy = run(0, km: 8), hard = run(2, km: 9), long = run(5, km: 16)
        // 고강도 판정으로
        #expect(mrPointRun(weekRuns: [easy, hard, long], longRunKm: 16, hardStarts: [hard.start], pointTypes: [:])?.start == hard.start)
        // 저장 유형으로
        #expect(mrPointRun(weekRuns: [easy, hard, long], longRunKm: 16, hardStarts: [], pointTypes: [hard.start: .tempo])?.start == hard.start)
        // 롱런 · 빌드업 하나만 — 롱런이 우선, 포인트는 미완료
        #expect(mrPointRun(weekRuns: [easy, long], longRunKm: 16, hardStarts: [long.start], pointTypes: [long.start: .buildUp]) == nil)
        // 포인트 유형이 아니면 아님
        #expect(mrPointRun(weekRuns: [easy, hard], longRunKm: 16, hardStarts: [], pointTypes: [hard.start: .easy]) == nil)
        // 롱런 없는 주(0)면 제외 없음
        #expect(mrPointRun(weekRuns: [long], longRunKm: 0, hardStarts: [long.start], pointTypes: [:])?.start == long.start)
    }

    @Test func breakdownWithPointAppendsPointText() {
        let mon = Date(timeIntervalSince1970: 1_791_000_000)
        let pt = MRPlanPoint(kind: .racePaceShort, totalKm: 6.8, reps: 3, repKm: 1, sustainedKm: nil, paceSecPerKm: 312)
        let w = MRPlanWeek(idx: 1, monday: mon, phase: "테이퍼", longRunKm: 12, longRunMin: 80, weeklyKm: 22,
                           projectedMin: 110, isNewMax: false, breakdown: "롱런 12km + 짧게 1.6km × 2회 · 강도는 그대로", point: pt)
        #expect(mrBreakdownWithPoint(w) == "롱런 12km + 짧게 1.6km × 2회 · 강도는 그대로 + 강도 훈련 대회 페이스 1km × 3회 5'12\"")
        var noPoint = w; noPoint.point = nil
        #expect(mrBreakdownWithPoint(noPoint) == noPoint.breakdown)
    }
}
