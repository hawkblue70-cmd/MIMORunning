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

    @Test func wallWithFallingHRIsNotCardio() throws {
        // 풀코스 벽: 6'41 → 8'32, 심박 155 → 147 — 효율 수치는 크게 나빠지지만 심박은 내려갔다
        let s = (1...12).map { i in
            i >= 9 ? split(i, pace: 512, cad: 158, hr: 147) : split(i, pace: 401, hr: i >= 5 ? 155 : 150)
        }
        let r = try #require(diagnose(s, minutes: 298, withForm: false))
        #expect((r.decouplingPct ?? 0) > LateRunDiagnosis.decouplingThresholdPct)
        #expect(r.kind == .energy)
    }

    @Test func wallFormIsUndeterminedWithoutBaseline() throws {
        let s = (1...12).map { i in i >= 9 ? split(i, pace: 512, cad: 158) : split(i, pace: 401) }
        let sig = try #require(LateRunDiagnosis.legSignal(splits: s, form: nil))
        #expect(sig.metrics == nil)
        #expect(sig.late.cadence != nil)
    }

    // MARK: 기준선 페이스→폼 추세 — 평소 범위 밖으로 느려진 후반

    /// 구간 중심 페이스 → 케이던스 중앙값: 330→176, 390→172, 450→168 (1초/km당 −0.067spm)
    private func trendBaseline() -> RunningFormBaseline {
        func band(_ b: PaceBand, _ lo: Double, _ hi: Double, cad: Double) -> BandBaseline {
            BandBaseline(band: b, isJudgeable: true, sampleCount: 30, windowMonths: 6, paceMin: lo, paceMax: hi,
                         cadence: stat(cad, sd: 3), strideLength: nil, groundContact: nil, verticalOsc: nil, heartRate: nil,
                         cadenceStrideR: nil, cadenceResidualP10: nil, cadenceResidualP25: nil,
                         cadenceResidualP75: nil, cadenceResidualP90: nil, strideResidualP10: nil,
                         strideResidualP25: nil, strideResidualP75: nil, strideResidualP90: nil, recentSamples: [])
        }
        let cut = PaceBandCutoffs(jogMax: 420, verySlowMax: 480, fastMin: 300, jogMin: 390, dailyMin: 360,
                                  tempoMin: 330, mergedBands: [])
        return RunningFormBaseline(version: RunningFormBaseline.currentVersion, computedAt: Date(), cutoffs: cut,
                                   bands: [.tempo: band(.tempo, 300, 360, cad: 176),
                                           .daily: band(.daily, 360, 420, cad: 172),
                                           .verySlow: band(.verySlow, 420, 480, cad: 168)],
                                   cadenceHRDiag: nil, gctBaselineResidualMean: nil, allFormSamples: [])
    }

    /// 6'41 → 8'32 (+111초): 추세로 예상되는 케이던스 변화 ≈ −7.4spm
    private func wall(lateCad: Int) -> [SplitData] {
        (1...12).map { i in
            i >= 9 ? split(i, pace: 512, cad: lateCad, sl: nil, gct: nil, hr: 147)
                   : split(i, pace: 401, cad: 169, sl: nil, gct: nil, hr: i >= 5 ? 155 : 150)
        }
    }

    @Test func paceTrendSlope() throws {
        let t = try #require(LateRunDiagnosis.paceTrend(trendBaseline(), \.cadence))
        #expect(abs(t.slope - (-8.0 / 120.0)) < 0.0001)
    }

    @Test func wallCadenceDropBeyondSlowdownIsLegs() throws {
        // 169 → 153 = −16spm, 속도 몫 −7.4 → 초과 −8.6 (문턱 −5.1)
        let s = wall(lateCad: 153)
        let sig = try #require(LateRunDiagnosis.legSignal(splits: s, form: nil, baseline: trendBaseline()))
        #expect(sig.metrics == [.cadence])
        #expect(sig.method == .paceTrend)
        let r = try #require(LateRunDiagnosis.diagnose(splits: s, durationMin: 298, form: nil, baseline: trendBaseline()))
        #expect(r.kind == .legs)
        #expect(LateRunDiagnosis.evidence(r).contains("보급 부족"))
    }

    @Test func wallCadenceDropExplainedBySlowdownIsHeld() throws {
        // 169 → 163 = −6spm, 속도 몫 −7.4 안쪽 → 다리 신호 없음 → 90분↑ 페이스·심박 동반 하락 → 에너지
        let s = wall(lateCad: 163)
        #expect(try #require(LateRunDiagnosis.legSignal(splits: s, form: nil, baseline: trendBaseline())).metrics == [])
        #expect(try #require(LateRunDiagnosis.diagnose(splits: s, durationMin: 298, form: nil, baseline: trendBaseline())).kind == .energy)
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

    // MARK: 시작 지점 — 페이스보다 심박이 먼저

    /// 20km: 11km부터 심박이 오르고(페이스 그대로), 17km부터 페이스가 떨어진다
    private var driftingRun: [SplitData] {
        (1...20).map { i in
            let hr = i >= 11 ? 150 + (i - 10) * 3 : 150
            let pace: Double = i >= 17 ? 400 : 375
            return split(i, pace: pace, hr: hr)
        }
    }

    @Test func efficiencySlipsBeforePace() throws {
        let on = LateRunDiagnosis.onsets(full: driftingRun, altitudeProfile: [])
        let e = try #require(on.efficiencyKm)
        let p = try #require(on.paceKm)
        #expect(e < p)
        #expect(e >= 9 && e <= 12)
        #expect(p >= 15 && p <= 17)
    }

    @Test func onsetShowsInEvidence() throws {
        let r = try #require(diagnose(driftingRun, minutes: 130))
        #expect(r.kind == .cardio)
        let ev = LateRunDiagnosis.evidence(r)
        #expect(ev.contains("심박 효율"))
        #expect(ev.contains("페이스는"))
    }

    @Test func steadyRunHasNoOnset() {
        let on = LateRunDiagnosis.onsets(full: (1...20).map { split($0) }, altitudeProfile: [])
        #expect(on.efficiencyKm == nil)
        #expect(on.paceKm == nil)
    }

    @Test func singleBadKmIsNotAnOnset() {
        // 14km 한 구간만 느리고 심박 높음(신호 대기·언덕) — 3km 이동 평균 연속 3번 조건에 걸리지 않는다
        let s = (1...20).map { i in i == 14 ? split(i, pace: 420, hr: 170) : split(i) }
        let on = LateRunDiagnosis.onsets(full: s, altitudeProfile: [])
        #expect(on.efficiencyKm == nil)
        #expect(on.paceKm == nil)
    }

    // MARK: 폼 유지력(대회 카드) — 다리 신호만

    @Test func legSignalMatchesDiagnosisLegs() throws {
        let s = run(lateHR: 162, lateCad: 166)
        let sig = try #require(LateRunDiagnosis.legSignal(splits: s, form: form(s)))
        #expect(sig.metrics == [.cadence])
        #expect(try #require(diagnose(s)).legMetrics == sig.metrics)
    }

    @Test func legSignalHeldIsEmpty() throws {
        let s = run(lateHR: 162)
        #expect(try #require(LateRunDiagnosis.legSignal(splits: s, form: form(s))).metrics?.isEmpty == true)
    }

    @Test func legSignalUnjudgeableWithoutBaselineWhenPaceChanged() throws {
        #expect(try #require(LateRunDiagnosis.legSignal(splits: run(latePace: 420, lateCad: 166), form: nil)).metrics == nil)
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

@Suite("후반 내구성 카드 요약", .korean)
struct LateRunPointTests {
    private func pt(_ kind: LateRunDiagnosis.Kind, _ pct: Double?, day: Int) -> LateRunPoint {
        LateRunPoint(id: UUID(), date: Date(timeIntervalSince1970: Double(day) * 86_400), distanceKm: 18,
                     kind: kind, decouplingPct: pct, efficiencyOnsetKm: nil)
    }

    @Test func summaryPicksMostFrequentRecentKind() throws {
        let pts = [pt(.held, 2, day: 1), pt(.cardio, 7, day: 8), pt(.legs, 3, day: 15), pt(.cardio, 6, day: 22)]
        let s = try #require(LateRunPoint.summary(pts))
        #expect(s.kind == .cardio)
        #expect(s.count == 2)
        #expect(LateRunPoint.sentence(pts)?.contains("심박이 먼저") == true)
    }

    @Test func allSameKindSaysAll() {
        let pts = [pt(.held, 2, day: 1), pt(.held, 3, day: 8), pt(.held, 1, day: 15)]
        #expect(LateRunPoint.sentence(pts) == "최근 60분 이상 러닝 3번 모두 후반까지 달리기를 남겼어요.")
    }

    @Test func singleRunHasNoSummary() {
        #expect(LateRunPoint.summary([pt(.held, 2, day: 1)]) == nil)
    }

    @Test func fallingDecouplingIsImprovement() throws {
        let pts = [pt(.cardio, 8, day: 1), pt(.cardio, 7, day: 8), pt(.held, 3, day: 15), pt(.held, 2, day: 22)]
        #expect(try #require(LateRunPoint.trendDelta(pts)) > 0)
        #expect(LateRunPoint.trendSentence(pts)?.contains("좋아지고") == true)
    }

    @Test func trendNeedsFourPoints() {
        #expect(LateRunPoint.trendDelta([pt(.held, 2, day: 1), pt(.held, 3, day: 8), pt(.held, nil, day: 15)]) == nil)
    }

    @Test func fastFinishShowsAsFaster() {
        var p = pt(.held, nil, day: 1)
        p.isFastFinish = true
        #expect(LateRunDurabilityCard.shortName(p) == "가속")
        #expect(LateRunDurabilityCard.shortName(pt(.held, 2, day: 2)) == "유지")
    }
}

@Suite("후반 페이스 롱런 인식", .korean)
struct FastFinishLongRunTests {
    private func run(_ paces: [Double]) -> [SplitData] {
        paces.enumerated().map { i, p in
            SplitData(id: i + 1, distanceM: 1000, duration: p, avgHeartRate: 150, avgCadence: 172,
                      avgPower: nil, avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil)
        }
    }

    @Test func easyBodyThenGoalPaceFinish() {
        // 16km: 6'30 × 12 → 5'50 × 4
        #expect(WorkoutTypeClassifier.isFastFinish(splits: run(Array(repeating: 390, count: 12) + Array(repeating: 350, count: 4))))
    }

    @Test func lastKmSprintIsNot() {
        #expect(!WorkoutTypeClassifier.isFastFinish(splits: run(Array(repeating: 390, count: 15) + [340])))
    }

    @Test func slightlyFasterFinishIsNot() {
        // 마지막 3km가 2%만 빠름 — 연속 구간(3%) 조건에 못 미침
        #expect(!WorkoutTypeClassifier.isFastFinish(splits: run(Array(repeating: 390, count: 13) + Array(repeating: 382, count: 3))))
    }

    @Test func evenRunIsNot() {
        #expect(!WorkoutTypeClassifier.isFastFinish(splits: run(Array(repeating: 390, count: 16))))
    }

    @Test func shortRunIsNot() {
        #expect(!WorkoutTypeClassifier.isFastFinish(splits: run([390, 390, 390, 390, 390, 350, 350])))
    }

    @Test func labelOnlyForEasyBodiedTypes() {
        #expect(WorkoutType.fastFinishLabelTypes.contains(.longRun))
        #expect(!WorkoutType.fastFinishLabelTypes.contains(.distanceRun))
        #expect(!WorkoutType.fastFinishLabelTypes.contains(.buildUp))
    }
}
