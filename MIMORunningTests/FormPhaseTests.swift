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

    /// 거리·시간을 직접 지정하는 스플릿 — 혼합 거리·부분 스플릿 테스트용.
    private func rawSplit(_ id: Int, distanceM: Double, duration: Double,
                          cad: Int? = 175, sl: Double? = 0.92, gct: Double? = 255, vo: Double? = 8.4) -> SplitData {
        SplitData(id: id, distanceM: distanceM, duration: duration,
                  avgHeartRate: 150, avgCadence: cad, avgPower: nil,
                  avgGroundContactTime: gct, avgStrideLength: sl, avgVerticalOscillation: vo)
    }

    // MARK: 기준선 픽스처 (FormReferenceBandTests와 동일 패턴)

    private func makeActivity(date: Date, distanceM: Double, paceSecPerKm: Double) -> Activity {
        Activity(id: UUID(), type: .running, date: date,
                 duration: paceSecPerKm * distanceM / 1000,
                 distance: distanceM, calories: 600, avgHeartRate: 150)
    }

    private func makeDetail(cadence: Int, stride: Double, gct: Double, vo: Double) -> ActivityDetail {
        ActivityDetail(routeCoordinates: [], routeTimeOffsets: [], elevationGain: 40,
                       avgPower: 227, avgCadence: cadence, splits: [], hrZones: [],
                       intervalSegments: [], workoutType: .general,
                       avgGroundContactTime: gct, avgStrideLength: stride,
                       avgVerticalOscillation: vo, vo2Max: 45.3,
                       altitudeProfile: [], altitudeTimeProfile: [])
    }

    /// 이지런(6'40~7'20)만 30회 쌓인 기준선
    @MainActor
    private func easyOnlyBaseline() -> RunningFormBaseline {
        let cal = Calendar.current
        let today = Date()
        var inputs: [FormInput] = []
        for i in 1...30 {
            let d = cal.date(byAdding: .day, value: -i * 5, to: today)!
            let act = makeActivity(date: d, distanceM: 7500, paceSecPerKm: 400.0 + Double((i * 7) % 41))
            let det = makeDetail(cadence: 166 + ((i * 3) % 7),
                                 stride: 0.87 + Double((i * 5) % 9) * 0.01,
                                 gct: 240.0 + Double((i * 11) % 13),
                                 vo: 8.1 + Double((i * 4) % 7) * 0.06)
            if let fi = FormInput(activity: act, detail: det) { inputs.append(fi) }
        }
        return FormBaselineEngine.compute(from: inputs)
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

    // MARK: 문장

    private func ko(_ r: FormPhase.Result, long: Bool = false) -> String {
        AppLanguage.shared.isEnglish = false
        return FormPhase.sentence(r, isLongDistance: long)
    }
    private func en(_ r: FormPhase.Result, long: Bool = false) -> String {
        AppLanguage.shared.isEnglish = true
        defer { AppLanguage.shared.isEnglish = false }
        return FormPhase.sentence(r, isLongDistance: long)
    }
    private func result(early: FormPhase.Early? = nil, mid: FormPhase.Mid? = nil, late: FormPhase.Late,
                        earlyEnd: Double = 4, lateStart: Double = 12, total: Double = 16) -> FormPhase.Result {
        FormPhase.Result(early: early, mid: mid, late: late, earlyEndKm: earlyEnd, lateStartKm: lateStart, totalKm: total)
    }

    @Test func heldAloneIsOneClause() {
        #expect(ko(result(late: .held)) == "끝까지 폼을 유지했어요.")
        #expect(en(result(late: .held)) == "Your form held to the finish.")
    }

    @Test func warmupAccelerationHeldJoinsThreeClauses() {
        let r = result(early: .warmup, mid: .strideDriven, late: .held)
        #expect(ko(r) == "처음 4km는 몸을 풀고, 중반엔 보폭으로 속도를 냈고, 끝까지 폼을 유지했어요.")
    }

    @Test func englishThreeClausesUseAnd() {
        let r = result(early: .warmup, mid: .strideDriven, late: .held)
        #expect(en(r) == "The first 4 km were a warm-up, you sped up mid-run with a longer stride, and your form held to the finish.")
    }

    @Test func heavierListsSignalsWithLastKm() {
        let r = result(late: .heavier([.stride, .groundContact]))
        #expect(ko(r) == "마지막 4km엔 보폭이 줄고 접지가 길어졌어요.")
        #expect(en(r) == "Over the last 4 km stride shortened and ground contact lengthened.")
    }

    @Test func heavierThreeSignals() {
        let r = result(late: .heavier([.cadence, .stride, .verticalOsc]))
        #expect(ko(r) == "마지막 4km엔 케이던스가 내려가고 보폭이 줄고 위아래 움직임이 늘었어요.")
    }

    @Test func cadenceDefendedAndBouncier() {
        #expect(ko(result(late: .cadenceDefended)) == "마지막 4km엔 속도가 떨어졌지만 발 회전은 지켰어요.")
        #expect(ko(result(late: .bouncier)) == "마지막 4km엔 앞보다 위로 가는 움직임이 늘었어요.")
    }

    @Test func longDistanceAppendsCommonNoteOnlyWhenNotHeld() {
        #expect(ko(result(late: .heavier([.stride])), long: true) == "마지막 4km엔 보폭이 줄었어요. 16km 후반엔 흔한 변화예요.")
        #expect(ko(result(late: .held), long: true) == "끝까지 폼을 유지했어요.")
    }

    @Test func midVariants() {
        #expect(ko(result(mid: .cadenceDriven, late: .held)) == "중반엔 발 회전으로 속도를 냈고, 끝까지 폼을 유지했어요.")
        #expect(ko(result(mid: .both, late: .held)) == "중반엔 보폭과 회전을 함께 올려 속도를 냈고, 끝까지 폼을 유지했어요.")
    }

    @Test func shortStates() {
        AppLanguage.shared.isEnglish = false
        #expect(FormPhase.shortState(result(late: .held)) == "끝까지 유지")
        #expect(FormPhase.shortState(result(late: .heavier([.stride]))) == "마지막 4km 살짝 무거워짐")
        #expect(FormPhase.shortState(result(late: .cadenceDefended)) == "후반 회전은 유지")
        #expect(FormPhase.shortState(result(late: .bouncier)) == "후반 위로 튐")
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

    // MARK: 리뷰 반영 — 분할 방어

    @Test func mixedDistancesGroupByDistanceFraction() {
        // 9×1000m + 1×950m(총 9950m). 30%=2985m·70%=6965m 경계로 3/4/3 분할
        let s = (1...9).map { split($0) } + [rawSplit(10, distanceM: 950, duration: 356)]
        let p = FormPhase.phases(s)
        #expect(p?.early.splitCount == 3)
        #expect(p?.late.startKm == 7)
        guard let endKm = p?.late.endKm else {
            Issue.record("late phase missing")
            return
        }
        #expect(abs(endKm - 9.95) < 0.001)
    }

    @Test func partialTailSplitIsIgnored() {
        let ten = (1...10).map { split($0) }
        let eleven = ten + [rawSplit(11, distanceM: 300, duration: 113)]
        let p10 = FormPhase.phases(ten)
        let p11 = FormPhase.phases(eleven)
        #expect(p11?.late.endKm == 10)
        #expect(p11?.late.splitCount == 3)
        #expect(p11?.early == p10?.early)
        #expect(p11?.mid == p10?.mid)
        #expect(p11?.late == p10?.late)
    }

    @Test func unsortedInputIsSortedById() {
        let sorted = (1...10).map { split($0) }
        let reversed = Array(sorted.reversed())
        let sortedResult = classify(sorted)
        let reversedResult = classify(reversed)
        #expect(reversedResult == sortedResult)
        #expect(reversedResult?.late == .held)
        #expect(reversedResult?.earlyEndKm == 3)
    }

    @Test func boundaryTiesAtFifteenSplits() {
        // 15km: 30% 지점(4.5km)의 중간값은 mid로, 70% 지점(10.5km)의 중간값은 late로 붙는다
        let p = FormPhase.phases((1...15).map { split($0) })
        #expect(p?.early.splitCount == 4)
        #expect(p?.mid.splitCount == 6)
        #expect(p?.late.splitCount == 5)
    }

    @Test func cadenceDeadZoneGivesNoMidPattern() {
        // 케이던스 +2.5spm — "고정"(<2.0)도 "상승"(≥3.0)도 아닌 사각지대 → 패턴 없음
        let early = (1...2).map { split($0, pace: 400, cad: 172, sl: 0.90) }
        let mid = [split(3, pace: 375, cad: 174, sl: 0.90), split(4, pace: 375, cad: 175, sl: 0.90)]
        let late = (5...6).map { split($0) }
        #expect(classify(early + mid + late)?.mid == nil)
    }

    @Test func cadenceDefendedRequiresGCTNotAbove() {
        // slowedLateWithStrideDownButCadenceHeldIsCadenceDefended와 동일하나 접지도 이탈 → 피로로 재분류
        let s = (1...7).map { split($0, pace: 375) } + (8...10).map { split($0, pace: 395, cad: 175, sl: 0.85, gct: 272) }
        #expect(classify(s)?.late == .heavier([.stride, .groundContact]))
    }

    @Test func warmupNeedsKnownMid() {
        // 중기 밴드를 조회할 수 없으면(판정불가) 초기 이탈이 있어도 몸풀기로 단정하지 않는다
        let s = (1...3).map { split($0, pace: 375, sl: 0.85) }
              + (4...7).map { split($0, pace: 380) }
              + (8...10).map { split($0, pace: 375) }
        let r = FormPhase.classify(splits: s, bandFor: { pace in pace == 380 ? nil : band })
        #expect(r?.early == nil)
    }

    @Test func paceScaleIsAppliedToBandLookup() {
        var received: [Double] = []
        let s = (1...10).map { split($0, pace: 375) }
        _ = FormPhase.classify(splits: s, paceScale: 0.8, bandFor: { pace in
            received.append(pace)
            return band
        })
        #expect(!received.isEmpty)
        #expect(received.allSatisfy { abs($0 - 300) < 0.001 })
    }

    @Test func accelerationBelowTwentySecondsHasNoMidPattern() {
        // 15초 차이 — 후반 둔화 문턱(10초)은 넘지만 가속 문턱(20초)엔 못 미친다
        let s = (1...3).map { split($0, pace: 390, sl: 0.88) } + (4...10).map { split($0, pace: 375, sl: 0.94) }
        #expect(classify(s)?.mid == nil)
    }

    @Test @MainActor func bandStatsLooksUpJudgeableBandAndAdjustsGCT() {
        let baseline = easyOnlyBaseline()
        let inBand = FormPhase.bandStats(in: baseline, paceSecPerKm: 420, gctShift: nil)
        #expect(inBand != nil)
        #expect(inBand?.cadence != nil)
        let outOfBand = FormPhase.bandStats(in: baseline, paceSecPerKm: 200, gctShift: nil)
        #expect(outOfBand == nil)
    }
}
