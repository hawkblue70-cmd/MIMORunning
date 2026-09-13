import Testing
import Foundation
@testable import MIMORunning

/// 초·중·말 3단계 폼 형태 판정. 문장 검사는 `AppLanguage.shared`를 건드리므로 직렬 실행.
@Suite("FormPhase 3단계 폼 형태", .serialized)
struct FormPhaseTests {

    // MARK: 픽스처

    /// 1km 스플릿. 기본값은 평소 범위 한가운데.
    private func split(_ id: Int, pace: Double = 375,
                       cad: Int? = 175, sl: Double? = 0.92, gct: Double? = 255, vo: Double? = 8.4) -> SplitData {
        SplitData(id: id, distanceM: 1000, duration: pace,
                  avgHeartRate: 150, avgCadence: cad, avgPower: nil,
                  avgGroundContactTime: gct, avgStrideLength: sl, avgVerticalOscillation: vo)
    }

    private func stat(_ median: Double, sd: Double) -> FormStat {
        FormStat(median: median, sd: sd, count: 30, p10: nil, p90: nil)
    }

    /// 평소 범위(±1.2SD, 반올림): 케이던스 171~179 · 보폭 0.88~0.96 · 접지 245~265
    private var band: FormPhase.BandStats {
        FormPhase.BandStats(cadence: stat(175, sd: 3), stride: stat(0.92, sd: 0.03), groundContact: stat(255, sd: 8))
    }

    private func classify(_ splits: [SplitData]) -> FormPhase.Result? {
        FormPhase.classify(splits: splits, bandFor: { _ in band })
    }

    // MARK: 분할

    @Test func sixSplitsSplitTwoTwoTwo() {
        let p = FormPhase.phases((1...6).map { split($0) })
        #expect(p?.early.splitCount == 2)
        #expect(p?.mid.splitCount == 2)
        #expect(p?.late.splitCount == 2)
        #expect(p?.early.endKm == 2)
        #expect(p?.late.startKm == 4)
    }

    @Test func sixteenSplitsUseThirtySeventyByDistance() {
        let p = FormPhase.phases((1...16).map { split($0) })
        #expect(p?.early.splitCount == 5)
        #expect(p?.mid.splitCount == 6)
        #expect(p?.late.splitCount == 5)
        #expect(p?.early.endKm == 5)
        #expect(p?.late.startKm == 11)
        #expect(p?.late.endKm == 16)
    }

    @Test func fewerThanSixSplitsIsSilent() {
        #expect(FormPhase.phases((1...5).map { split($0) }) == nil)
        #expect(classify((1...5).map { split($0) }) == nil)
    }

    @Test func phaseStatsAveragePaceAndMetrics() {
        let s = [split(1, pace: 400, cad: 170), split(2, pace: 380, cad: 172)] + (3...6).map { split($0) }
        let p = FormPhase.phases(s)
        #expect(p?.early.paceSecPerKm == 390)
        #expect(p?.early.cadence == 171)
    }

    // MARK: 말기 패턴

    @Test func allInRangeIsHeld() {
        let r = classify((1...10).map { split($0) })
        #expect(r?.late == .held)
        #expect(r?.early == nil)
        #expect(r?.mid == nil)
        #expect(r?.isHeld == true)
    }

    @Test func lateStrideDownAndGCTUpIsHeavier() {
        // 10개: 말기 = 8~10km. 수직진폭은 그대로(8.4) → 보폭이 줄어 비율만 올라도 verticalOsc 신호는 붙지 않는다
        let s = (1...7).map { split($0) } + (8...10).map { split($0, sl: 0.85, gct: 272) }
        let r = classify(s)
        #expect(r?.late == .heavier([.stride, .groundContact]))
        #expect(r?.lateStartKm == 7)
        #expect(r?.totalKm == 10)
    }

    @Test func lateCadenceDropAloneIsHeavierWithCadenceSignal() {
        let s = (1...7).map { split($0) } + (8...10).map { split($0, cad: 166) }
        #expect(classify(s)?.late == .heavier([.cadence]))
    }

    @Test func slowedLateWithStrideDownButCadenceHeldIsCadenceDefended() {
        let s = (1...7).map { split($0, pace: 375) } + (8...10).map { split($0, pace: 395, cad: 175, sl: 0.85) }
        #expect(classify(s)?.late == .cadenceDefended)
    }

    @Test func strideDownWithVerticalRatioUpIsBouncier() {
        // 중기 8.4cm·비율 8.4/92 = 9.1% → 말기 9.6cm(+1.2)·비율 9.6/85 = 11.3% (+2.2%p), 접지는 범위 안
        let s = (1...7).map { split($0) } + (8...10).map { split($0, sl: 0.85, vo: 9.6) }
        #expect(classify(s)?.late == .bouncier)
    }

    @Test func heavierGainsVerticalOscSignalWhenRatioRises() {
        // 보폭↓ + 접지↑ + 비율↑ → [.stride, .groundContact, .verticalOsc]
        let s = (1...7).map { split($0) } + (8...10).map { split($0, sl: 0.85, gct: 272, vo: 9.6) }
        #expect(classify(s)?.late == .heavier([.stride, .groundContact, .verticalOsc]))
    }

    // MARK: 초기·중기 패턴

    @Test func earlyOffRangeThenInRangeIsWarmup() {
        let s = (1...3).map { split($0, pace: 400, sl: 0.85, gct: 270) } + (4...10).map { split($0) }
        let r = classify(s)
        #expect(r?.early == .warmup)
        #expect(r?.late == .held)
        #expect(r?.earlyEndKm == 3)
    }

    @Test func earlyAndMidBothOffRangeIsNotWarmup() {
        let s = (1...7).map { split($0, sl: 0.85) } + (8...10).map { split($0) }
        #expect(classify(s)?.early == nil)
    }

    @Test func midFasterWithLongerStrideIsStrideDriven() {
        // 초기 400 → 중기 375 (25초 빨라짐), 보폭 0.88 → 0.94, 케이던스 고정
        let s = (1...3).map { split($0, pace: 400, sl: 0.88) } + (4...7).map { split($0, pace: 375, sl: 0.94) } + (8...10).map { split($0, pace: 375, sl: 0.94) }
        #expect(classify(s)?.mid == .strideDriven)
    }

    @Test func midFasterWithQuickerStepsIsCadenceDriven() {
        let s = (1...3).map { split($0, pace: 400, cad: 172) } + (4...10).map { split($0, pace: 375, cad: 176) }
        #expect(classify(s)?.mid == .cadenceDriven)
    }

    @Test func midFasterWithBothIsBoth() {
        let s = (1...3).map { split($0, pace: 400, cad: 172, sl: 0.88) } + (4...10).map { split($0, pace: 375, cad: 176, sl: 0.94) }
        #expect(classify(s)?.mid == .both)
    }

    @Test func midNotFasterHasNoMidPattern() {
        let s = (1...3).map { split($0, sl: 0.88) } + (4...10).map { split($0, sl: 0.94) }
        #expect(classify(s)?.mid == nil)
    }

    // MARK: 침묵 조건

    @Test func noBandForAnyPhaseIsSilent() {
        #expect(FormPhase.classify(splits: (1...10).map { split($0) }, bandFor: { _ in nil }) == nil)
    }

    @Test func lateNeedsTwoKnownMetrics() {
        // 말기 보폭·접지 결측 → 케이던스 하나만 알면 침묵
        let s = (1...7).map { split($0) } + (8...10).map { split($0, sl: nil, gct: nil) }
        #expect(classify(s) == nil)
    }
}
