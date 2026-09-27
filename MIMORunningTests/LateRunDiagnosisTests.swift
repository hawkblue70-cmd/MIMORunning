import Testing
import Foundation
@testable import MIMORunning

/// 후반 진단(다리·심박·에너지·둘 다·유지) + 롱런 후반 패턴 조언.
/// 12km 러닝 픽스처 — 거리 비율 분할: 초반 1~4km · 중반 5~8km · 후반 9~12km.
@Suite("LateRunDiagnosis 후반 진단", .korean)
struct LateRunDiagnosisTests {

    // MARK: 픽스처

    private func split(_ id: Int, pace: Double = 375, cad: Int? = 175, sl: Double? = 0.92,
                       gct: Double? = 255, hr: Int? = 150) -> SplitData {
        SplitData(id: id, distanceM: 1000, duration: pace,
                  avgHeartRate: hr, avgCadence: cad, avgPower: nil,
                  avgGroundContactTime: gct, avgStrideLength: sl, avgVerticalOscillation: 8.4)
    }

    /// 후반(9~12km)만 바꾼 12km 러닝
    private func run(latePace: Double = 375, lateHR: Int? = 150, lateCad: Int? = 175,
                     midHR: Int? = 150) -> [SplitData] {
        (1...12).map { i in
            if i >= 9 { return split(i, pace: latePace, cad: lateCad, hr: lateHR) }
            return split(i, hr: i >= 5 ? midHR : 150)
        }
    }

    private func stat(_ median: Double, sd: Double) -> FormStat {
        FormStat(median: median, sd: sd, count: 30, p10: nil, p90: nil)
    }

    /// 평소 범위(±1.2SD): 케이던스 171~179 · 보폭 0.88~0.96 · 접지 245~265
    private func form(_ splits: [SplitData]) -> FormPhase.Result? {
        let band = FormPhase.BandStats(cadence: stat(175, sd: 3), stride: stat(0.92, sd: 0.03),
                                       groundContact: stat(255, sd: 8))
        return FormPhase.classify(splits: splits, bandFor: { _ in band })
    }

    private func diagnose(_ s: [SplitData], minutes: Double = 75, withForm: Bool = true) -> LateRunDiagnosis.Result? {
        LateRunDiagnosis.diagnose(splits: s, durationMin: minutes, form: withForm ? form(s) : nil)
    }

    // MARK: 유형

    @Test func sameEffortToTheEndIsHeld() throws {
        let r = try #require(diagnose(run()))
        #expect(r.kind == .held)
        #expect(abs(r.decouplingPct ?? 99) < 0.01)
        #expect(LateRunDiagnosis.state(r) == "끝까지 유지")
    }

    @Test func hrRisingAtSamePaceIsCardio() throws {
        // 150 → 162 at same pace = 효율 7.4% 하락
        let r = try #require(diagnose(run(lateHR: 162)))
        #expect(r.kind == .cardio)
        #expect((r.decouplingPct ?? 0) > LateRunDiagnosis.decouplingThresholdPct)
    }

    @Test func smallHRRiseStaysHeld() throws {
        // 150 → 155 = 3.2% — 5% 문턱 아래
        #expect(try #require(diagnose(run(lateHR: 155))).kind == .held)
    }

    @Test func heavierFormWithSteadyHRIsLegs() throws {
        let r = try #require(diagnose(run(lateCad: 166)))
        #expect(r.kind == .legs)
        #expect(r.legMetrics == [.cadence])
    }

    @Test func heavierFormAndRisingHRIsCombined() throws {
        #expect(try #require(diagnose(run(lateHR: 162, lateCad: 166))).kind == .combined)
    }

    @Test func paceAndHRDroppingTogetherAfter90MinIsEnergy() throws {
        // 6'15 → 7'00, 심박 150 → 138 — 효율은 오히려 좋아짐(심박 신호 아님)
        let r = try #require(diagnose(run(latePace: 420, lateHR: 138), minutes: 100))
        #expect(r.kind == .energy)
        #expect(LateRunDiagnosis.evidence(r).contains("추정"))
    }

    @Test func sameSlowdownUnder90MinIsSilent() {
        #expect(diagnose(run(latePace: 420, lateHR: 138), minutes: 75) == nil)
    }

    @Test func fastFinishIsNotCardio() throws {
        // 후반 6'15 → 5'45, 심박 150 → 168 — 계획된 가속
        let r = try #require(diagnose(run(latePace: 345, lateHR: 168)))
        #expect(r.kind == .held)
        #expect(r.isFastFinish)
        #expect(LateRunDiagnosis.next(r) == nil)
    }

    @Test func noHeartRateCannotClaimHeld() {
        let s = (1...12).map { split($0, hr: nil) }
        #expect(diagnose(s) == nil)
    }

    // MARK: 기준선 없을 때 원값 다리 신호

    @Test func rawLegsWhenPaceSimilar() throws {
        // 175 → 166 = −5.1% (3% 문턱 초과), 페이스 같음
        let r = try #require(diagnose(run(lateCad: 166), withForm: false))
        #expect(r.kind == .legs)
    }

    @Test func rawLegsOffWhenSlowed() {
        // 페이스가 12% 느려지면 케이던스 하락은 속도로 설명된다 → 다리 신호 없음, 심박도 그대로라 효율 하락 → 심박형
        let r = diagnose(run(latePace: 420, lateCad: 166), withForm: false)
        #expect(r?.legMetrics.isEmpty == true)
    }

    // MARK: 대상

    @Test func appliesOnlyToLongNonStructuredRuns() {
        #expect(LateRunDiagnosis.applies(to: .longRun, durationMin: 60))
        #expect(LateRunDiagnosis.applies(to: .race, durationMin: 90))
        #expect(!LateRunDiagnosis.applies(to: .longRun, durationMin: 59))
        #expect(!LateRunDiagnosis.applies(to: .interval, durationMin: 90))
        #expect(!LateRunDiagnosis.applies(to: .buildUp, durationMin: 90))
        #expect(!LateRunDiagnosis.applies(to: .tempo, durationMin: 90))
    }

    // MARK: 총평 줄

    @Test func summaryLineSitsBetweenHeartRateAndLoad() throws {
        var i = RunSummaryInput()
        i.lateRun = try #require(diagnose(run(lateHR: 162)))
        let line = try #require(RunSummary.lines(i).first { $0.axis == "후반" })
        #expect(line.state == "심박이 먼저 오름")
        #expect(line.tone == .neutral)
        #expect(line.next != nil)
    }

    @Test func raceNextTalksAboutNextRace() throws {
        let r = try #require(diagnose(run(lateHR: 162)))
        #expect(LateRunDiagnosis.next(r, isRace: true)?.contains("다음 대회") == true)
    }

    @Test func legsNextDoesNotPrescribeLongerRuns() throws {
        let r = try #require(diagnose(run(lateCad: 166)))
        let text = try #require(LateRunDiagnosis.next(r))
        #expect(text.contains("근력"))
        #expect(!text.contains("2~3회"))
    }
}

@Suite("롱런 후반 패턴 조언", .korean)
struct MRLateRunPatternAdviceTests {

    private let cal = Calendar.current

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: Date())!)
    }

    private func runs() -> [MRWorkout] {
        (0..<12).map { i in
            MRWorkout(start: day(-i * 3), durationMin: 60, distanceKm: 10,
                      hrAvg: 150, hrMax: 170, tempC: 15, humidity: nil,
                      indoor: false, isInterval: false)
        }.reversed()
    }

    /// 케이던스는 그대로(S1 미발동) — 후반 유형만 바꾼다
    private func fatigue(_ kind: LateRunDiagnosis.Kind?, daysAgo: Int) -> MRLongRunFatigue {
        var f = MRLongRunFatigue(id: UUID(), start: day(-daysAgo), distanceKm: 18, durationMin: 110,
                                 q1PaceSecPerKm: 380, q4PaceSecPerKm: 380,
                                 q1Cadence: 172, q4Cadence: 172,
                                 firstHalfAvgHR: nil, cadenceCoverage: 1.0)
        f.lateKind = kind
        return f
    }

    private func keys(_ kinds: [LateRunDiagnosis.Kind?]) -> Set<String> {
        let fs = kinds.enumerated().map { fatigue($1, daysAgo: $0 * 7) }
        return Set(mrBuildAdvice(runs: runs(), phys: MRPhysiology(), plans: [], races: [],
                                 gaps: [], strengthPerWeek: 2.0, fatigue: fs,
                                 log: MRAdviceLog(), asOf: Date()).map(\.key))
    }

    @Test func twoOfThreeDecidesPattern() {
        let v = MRLateRunPattern.aggregate(fatigue: [fatigue(.cardio, daysAgo: 0), fatigue(.legs, daysAgo: 7),
                                                     fatigue(.cardio, daysAgo: 14)], asOf: Date())
        #expect(v.dominant == .cardio)
        #expect(v.dominantCount == 2)
        #expect(v.latestIsTodayAndDominant)
    }

    @Test func oneOffIsNotAPattern() {
        let v = MRLateRunPattern.aggregate(fatigue: [fatigue(.cardio, daysAgo: 0), fatigue(.legs, daysAgo: 7),
                                                     fatigue(.energy, daysAgo: 14)], asOf: Date())
        #expect(v.dominant == nil)
    }

    @Test func undiagnosedRunsDoNotCount() {
        let v = MRLateRunPattern.aggregate(fatigue: [fatigue(nil, daysAgo: 0), fatigue(.cardio, daysAgo: 7)], asOf: Date())
        #expect(v.evaluated == 1)
        #expect(v.dominant == nil)
    }

    @Test func cardioPatternGivesCardioAdvice() {
        #expect(keys([.cardio, .cardio, .held]).contains("lateCardio"))
    }

    @Test func legsPatternJoinsDurability() {
        let k = keys([.legs, .held, .legs])
        #expect(k.contains("durability"))
        #expect(!k.contains("strength"))
    }

    @Test func energyPatternGivesFuelingPractice() {
        #expect(keys([.energy, .energy]).contains("lateEnergy"))
    }

    @Test func combinedPatternGivesCombinedAdvice() {
        #expect(keys([.combined, .combined]).contains("lateCombined"))
    }

    @Test func heldPatternWithoutPlanSuggestsGoalPaceFinish() {
        #expect(keys([.held, .held, .cardio]).contains("lateHeld"))
    }
}
