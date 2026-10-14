import Testing
import Foundation
@testable import MIMORunning

/// 폼 카드 판정 추출(카드 = 요약 단일 출처) + 폼 블록 신호
@Suite("TabDigestForm 폼 판정·신호", .korean)
@MainActor
struct TabDigestFormTests {

    // 8km · 3000초 = 6'15"/km → 보통(daily) 구간
    private func activity() -> Activity {
        Activity(id: UUID(), type: .running, date: Date(), duration: 3000, distance: 8000,
                 calories: nil, avgHeartRate: nil)
    }

    private func stat(_ median: Double, sd: Double) -> FormStat {
        FormStat(median: median, sd: sd, count: 30, p10: nil, p90: nil)
    }

    /// 보통 구간: 케이던스 172±3.6 · 지면접촉 240±9.6 (판정 가능)
    private func baseline() -> RunningFormBaseline {
        let daily = BandBaseline(band: .daily, isJudgeable: true, sampleCount: 30, windowMonths: 6, paceMin: 360, paceMax: 390,
                                 cadence: stat(172, sd: 3), strideLength: nil, groundContact: stat(240, sd: 8),
                                 verticalOsc: nil, heartRate: nil,
                                 cadenceStrideR: nil, cadenceResidualP10: nil, cadenceResidualP25: nil,
                                 cadenceResidualP75: nil, cadenceResidualP90: nil, strideResidualP10: nil,
                                 strideResidualP25: nil, strideResidualP75: nil, strideResidualP90: nil, recentSamples: [])
        let cut = PaceBandCutoffs(jogMax: 420, verySlowMax: 480, fastMin: 300, jogMin: 390, dailyMin: 360,
                                  tempoMin: 330, mergedBands: [])
        return RunningFormBaseline(version: RunningFormBaseline.currentVersion, computedAt: Date(), cutoffs: cut,
                                   bands: [.daily: daily], cadenceHRDiag: nil, gctBaselineResidualMean: nil, allFormSamples: [])
    }

    private func inputs(workoutType: WorkoutType = .easy, cadence: Int? = nil, gct: Double? = nil,
                        baseline: RunningFormBaseline? = nil, fatigue: String? = nil,
                        segments: [IntervalSegment] = [], phase: FormPhase.Result? = nil) -> TabDigestForm.Inputs {
        TabDigestForm.Inputs(activity: activity(), splits: [], avgCadence: cadence, avgStrideLength: nil,
                             avgGroundContactTime: gct, avgVerticalOscillation: nil, altitudeProfile: [],
                             baseline: baseline, workoutType: workoutType, intervalSegments: segments,
                             typicalKm: nil, formShifts: [], fatigueContext: fatigue, phase: phase)
    }

    // MARK: 추출 회귀 — 카드가 내던 문장 그대로

    @Test func easyHeavyLegsNarrativeIsProblem() {
        let x = inputs(cadence: 165, gct: 265, baseline: baseline(), fatigue: "5일 연속 · 최근 7일 부하 +134%")
        #expect(TabDigestForm.narrative(x) == "같은 페이스 평소보다 지면접촉이 265ms로 길고 케이던스가 165spm으로 낮았습니다. 다리가 무거운 날의 패턴입니다 — 5일 연속 · 최근 7일 부하 +134%.")
        #expect(TabDigestForm.narrativeIsProblem(x))
    }

    @Test func allInRangeNarrativeIsNotProblem() {
        let x = inputs(cadence: 172, gct: 240, baseline: baseline())
        #expect(TabDigestForm.narrative(x) == "케이던스 172spm으로 평소와 같은 편한 폼이었습니다.")
        #expect(TabDigestForm.narrativeIsProblem(x) == false)
    }

    @Test func lowCadenceNarrativeIsProblem() {
        let x = inputs(cadence: 155)
        #expect(TabDigestForm.narrative(x) == "케이던스가 155spm입니다. 보폭이 큰 편입니다.")
        #expect(TabDigestForm.narrativeIsProblem(x))
    }

    // MARK: 신호

    private func rep(_ id: Int, start: Date, seconds: TimeInterval, meters: Double, label: String) -> IntervalSegment {
        IntervalSegment(id: id, startDate: start, endDate: start.addingTimeInterval(seconds), distanceM: meters,
                        avgHeartRate: 160, avgCadence: 180, stepLabel: label)
    }

    @Test func testIntervalUsesFatigueCardPair() {
        var t = Date(timeIntervalSince1970: 0)
        var segs: [IntervalSegment] = []
        for i in 0..<4 {
            segs.append(rep(segs.count + 1, start: t, seconds: 240, meters: 1000, label: "운동")); t += 240
            if i < 3 { segs.append(rep(segs.count + 1, start: t, seconds: 90, meters: 200, label: "회복")); t += 90 }
        }
        // 마무리 문장·3단계 문장이 나올 재료가 있어도 인터벌은 피로 카드 한 쌍만
        let x = inputs(workoutType: .interval, cadence: 180, gct: 240, baseline: baseline(), segments: segs,
                       phase: .stub(late: .faded(paceDropSec: 25)))
        let pair = TabDigestForm.intervalPair(x)
        #expect(pair?.interpretation == "보폭이 끝까지 유지됐습니다. 다리 힘이 남아 있었습니다.")
        #expect(pair?.suggestion == nil)
        let s = TabDigestForm.signals(x, lines: [])
        #expect(s.count == 1)
        #expect(s.first?.kind == .good)
        #expect(s.first?.text == pair?.interpretation)
    }

    @Test func testFadedTakesLatePaceFamily() {
        let x = inputs(workoutType: .general, phase: .stub(late: .faded(paceDropSec: 25)))
        let next = "다음엔 중반을 10초/km 늦게 시작해 보세요."
        let lines = [RunSummaryLine(axis: RunHeadline.Axis.form.label!, state: "후반 페이스 떨어짐", tone: .neutral, next: next)]
        let s = TabDigestForm.signals(x, lines: lines)
        let faded = s.first { $0.kind == .problem && $0.priority == 1 }
        #expect(faded?.family == .latePace)
        #expect(faded?.direction == next)
        #expect(faded?.text.contains("페이스가 25초/km 떨어졌는데") == true)
    }

    @Test func testSoftCadenceOnlyIsGood() {
        let x = inputs(workoutType: .easy, phase: .stub(late: .heavier([.cadence]), easyFrame: true))
        let s = TabDigestForm.signals(x, lines: [])
        #expect(s.contains { $0.kind == .problem } == false)
        let g = s.first { $0.kind == .good }
        #expect(g?.priority == 2)
        #expect(g?.text.contains("편한 날엔 자연스러운 변화입니다") == true)
    }

    // MARK: 마무리 문장 문제의 순서·방향 (F2·F8)

    @Test func easyHeavyLegsProblemIsF2WithFormNext() {
        let x = inputs(cadence: 165, gct: 265, baseline: baseline(), fatigue: "5일 연속 · 최근 7일 부하 +134%")
        let next = "다음 이지런은 지면접촉을 짧게 의식해 보세요."
        let lines = [RunSummaryLine(axis: RunHeadline.Axis.form.label!, state: "다리 무거움", tone: .neutral, next: next)]
        let p = TabDigestForm.signals(x, lines: lines).first { $0.kind == .problem }
        #expect(p?.priority == 2)
        #expect(p?.direction == next)
    }

    @Test func lowCadenceProblemIsF8AfterOtherFormProblems() {
        let x = inputs(cadence: 155)
        let p = TabDigestForm.signals(x, lines: []).first { $0.kind == .problem }
        #expect(p?.priority == 8)
        #expect(p?.direction == nil)   // 케이던스-심박 권고 재료 없음
    }

    // MARK: 후반 폼(.lateForm) — 리듬 R3 '다리 먼저'와 폼 F6이 같은 사실

    @Test func lateLegsAndFormHeavierOnlyFormBlockStatesIt() {
        func stats(_ s: Double, _ e: Double) -> FormPhase.PhaseStats {
            FormPhase.PhaseStats(splitCount: 4, startKm: s, endKm: e, paceSecPerKm: 360,
                                 cadence: 170, stride: nil, groundContact: nil, verticalOsc: nil, avgHR: nil)
        }
        var i = RunSummaryInput(); i.workoutType = .longRun; i.distKm = 16
        i.lateRun = LateRunDiagnosis.Result(kind: .legs, mid: stats(4, 12), late: stats(12, 16), decouplingPct: nil,
                                            legMetrics: [.cadence], durationMin: 100)
        let rhythm = TabDigestRhythm.signals(context: .stub(workoutType: .longRun), input: i, lines: [])
        let r3 = rhythm.first { $0.priority == 3 && $0.kind == .problem }
        #expect(r3?.family == .lateForm)

        let form = TabDigestForm.signals(inputs(workoutType: .general, phase: .stub(late: .bouncier)), lines: [])
        let f6 = form.first { $0.priority == 6 && $0.kind == .problem }
        #expect(f6?.family == .lateForm)

        let blocks = TabDigest.make(rhythm + form)
        let r3Text = r3?.text ?? "-"
        #expect(blocks.first { $0.tab == .rhythm }?.statements.contains { $0.text == r3Text } != true)
        #expect(blocks.first { $0.tab == .form }?.statements.contains { $0.text == f6?.text } == true)
    }

    /// 폼에 후반 폼 신호가 없으면 리듬 R3 '다리 먼저'는 리듬 블록에 남는다
    @Test func lateLegsStaysInRhythmWithoutFormSignal() {
        func stats(_ s: Double, _ e: Double) -> FormPhase.PhaseStats {
            FormPhase.PhaseStats(splitCount: 4, startKm: s, endKm: e, paceSecPerKm: 360,
                                 cadence: 170, stride: nil, groundContact: nil, verticalOsc: nil, avgHR: nil)
        }
        var i = RunSummaryInput(); i.workoutType = .longRun; i.distKm = 16
        i.lateRun = LateRunDiagnosis.Result(kind: .legs, mid: stats(4, 12), late: stats(12, 16), decouplingPct: nil,
                                            legMetrics: [.cadence], durationMin: 100)
        let rhythm = TabDigestRhythm.signals(context: .stub(workoutType: .longRun), input: i, lines: [])
        let r3 = rhythm.first { $0.priority == 3 && $0.kind == .problem }
        #expect(r3 != nil)
        let blocks = TabDigest.make(rhythm)
        #expect(blocks.first { $0.tab == .rhythm }?.statements.contains { $0.text == r3?.text } == true)
    }
}
