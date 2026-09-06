import Testing
import Foundation
@testable import MIMORunning

@Suite("MRAdviceQueue 내구성·근력·케이던스 조언")
struct MRAdviceQueueDurabilityTests {

    private let cal = Calendar.current

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: Date())!)
    }

    private func runs(count: Int = 12) -> [MRWorkout] {
        (0..<count).map { i in
            MRWorkout(start: day(-i * 3), durationMin: 60, distanceKm: 10,
                      hrAvg: 150, hrMax: 170, tempC: 15, humidity: nil,
                      indoor: false, isInterval: false)
        }.reversed()
    }

    private func fatigue(drop: Double, daysAgo: Int) -> MRLongRunFatigue {
        MRLongRunFatigue(id: UUID(), start: day(-daysAgo), distanceKm: 16, durationMin: 105,
                         q1PaceSecPerKm: 400, q4PaceSecPerKm: 400,
                         q1Cadence: 170, q4Cadence: 170 * (1 - drop),
                         firstHalfAvgHR: nil, cadenceCoverage: 1.0)
    }

    private var triggeredFatigue: [MRLongRunFatigue] {
        [fatigue(drop: 0.05, daysAgo: 0), fatigue(drop: 0.04, daysAgo: 7), fatigue(drop: 0.0, daysAgo: 14)]
    }

    private func cadenceShift(delta: Double) -> MRFormShift {
        let m = mrFormMetrics.first { $0.key == "cadence" }!
        return MRFormShift(metric: m, recentMean: 0, baseMean: 0, delta: delta,
                           mdc: 1.0, weeksConsistent: 5, r2: nil)
    }

    private func build(fatigue: [MRLongRunFatigue] = [], races: [MRTargetRace] = [],
                       gaps: [MRGap] = [], strength: Double = 2.0,
                       cadenceShift: MRFormShift? = nil, runs r: [MRWorkout]? = nil) -> [MRAdvice] {
        mrBuildAdvice(runs: r ?? runs(), phys: MRPhysiology(), plans: [], races: races,
                      gaps: gaps, strengthPerWeek: strength, fatigue: fatigue,
                      cadenceShift: cadenceShift, log: MRAdviceLog(), asOf: Date())
    }

    private func keys(_ a: [MRAdvice]) -> Set<String> { Set(a.map(\.key)) }

    // MARK: durability

    @Test func durabilityFiresOnTriggeredFatigueWithExercises() throws {
        let a = build(fatigue: triggeredFatigue)
        let d = try #require(a.first { $0.key == "durability" })
        #expect(d.slot == "todayRun")          // 최신 롱런이 오늘
        #expect(abs(d.timeliness - 0.8) < 0.001)
        #expect(!d.exercises.isEmpty)
        #expect(d.grade == "B")
    }

    @Test func durabilityWeeklyWhenLatestLongRunNotToday() throws {
        let fs = [fatigue(drop: 0.05, daysAgo: 2), fatigue(drop: 0.04, daysAgo: 9)]
        let d = try #require(build(fatigue: fs).first { $0.key == "durability" })
        #expect(d.slot == "weekly")
        #expect(abs(d.timeliness - 0.4) < 0.001)
    }

    @Test func durabilityTimelinessBumpsWhenNoStrengthSessions() throws {
        let d = try #require(build(fatigue: triggeredFatigue, strength: 0.5).first { $0.key == "durability" })
        #expect(abs(d.timeliness - 0.9) < 0.001)
    }

    @Test func durabilitySuppressesStrength() {
        let k = keys(build(fatigue: triggeredFatigue, strength: 0.0))
        #expect(k.contains("durability"))
        #expect(!k.contains("strength"))
    }

    @Test func strengthStillFiresWithoutDurability() {
        let k = keys(build(strength: 0.0))
        #expect(k.contains("strength"))
        #expect(!k.contains("durability"))
    }

    @Test func noDurabilityWhenNotTriggered() {
        let fs = [fatigue(drop: 0.05, daysAgo: 0), fatigue(drop: 0.0, daysAgo: 7), fatigue(drop: 0.0, daysAgo: 14)]
        #expect(!keys(build(fatigue: fs)).contains("durability"))
    }

    // MARK: 억제

    @Test func allThreeSuppressedDuringTaper() {
        let half = MRTargetRace(date: day(10), distanceM: MRDistance.dH, name: "하프")
        let k = keys(build(fatigue: triggeredFatigue, races: [half], strength: 0.0,
                           cadenceShift: cadenceShift(delta: -3)))
        #expect(!k.contains("durability"))
        #expect(!k.contains("strength"))
        #expect(!k.contains("cadenceCue"))
    }

    @Test func notSuppressedByTenKTaper() {
        let tenK = MRTargetRace(date: day(10), distanceM: MRDistance.d10, name: "10K")
        #expect(keys(build(fatigue: triggeredFatigue, races: [tenK])).contains("durability"))
    }

    @Test func suppressedDuringRecoveryAfterFinishedRace() {
        // 7일 전 하프 완주 기록 (21.1km)
        var r = runs()
        r.append(MRWorkout(start: day(-7), durationMin: 110, distanceKm: 21.1,
                           hrAvg: 165, hrMax: 185, tempC: 15, humidity: nil,
                           indoor: false, isInterval: false))
        let half = MRTargetRace(date: day(-7), distanceM: MRDistance.dH, name: "하프")
        let k = keys(build(fatigue: triggeredFatigue, races: [half], strength: 0.0, runs: r))
        #expect(!k.contains("durability"))
        #expect(!k.contains("strength"))
    }

    @Test func notSuppressedByPastRaceWithoutFinishRecord() {
        let half = MRTargetRace(date: day(-7), distanceM: MRDistance.dH, name: "하프")
        #expect(keys(build(fatigue: triggeredFatigue, races: [half])).contains("durability"))
    }

    @Test func suppressedWithinThreeWeeksOfGapReturn() {
        let g = MRGap(start: day(-40), end: day(-10), days: 30, cause: "동기 저하",
                      preSpike: false, stepsDropped: false)
        let k = keys(build(fatigue: triggeredFatigue, gaps: [g], strength: 0.0))
        #expect(!k.contains("durability"))
        #expect(!k.contains("strength"))
    }

    // MARK: cadenceCue

    @Test func cadenceCueFiresOnRealCadenceDropWithoutS1() throws {
        let fs = [fatigue(drop: 0.0, daysAgo: 2), fatigue(drop: 0.0, daysAgo: 9)]
        let c = try #require(build(fatigue: fs, cadenceShift: cadenceShift(delta: -3)).first { $0.key == "cadenceCue" })
        #expect(c.slot == "weekly")
        #expect(!c.exercises.isEmpty)
    }

    @Test func cadenceCueSilentWhenAnyS1Positive() {
        let fs = [fatigue(drop: 0.05, daysAgo: 2), fatigue(drop: 0.0, daysAgo: 9)]
        #expect(!keys(build(fatigue: fs, cadenceShift: cadenceShift(delta: -3))).contains("cadenceCue"))
    }

    @Test func cadenceCueSilentWhenShiftIsUpwardOrNotReal() {
        #expect(!keys(build(cadenceShift: cadenceShift(delta: +3))).contains("cadenceCue"))
        let m = mrFormMetrics.first { $0.key == "cadence" }!
        let weak = MRFormShift(metric: m, recentMean: 0, baseMean: 0, delta: -0.5,
                               mdc: 1.0, weeksConsistent: 5, r2: nil)   // isPractical 실패
        #expect(!keys(build(cadenceShift: weak)).contains("cadenceCue"))
    }
}
