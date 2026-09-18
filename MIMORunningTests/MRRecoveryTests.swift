import Testing
import Foundation
@testable import MIMORunning

@Suite("MRRecovery 운동 후 심박 회복", .korean)
struct MRRecoveryTests {

    private func post(_ pairs: [(Double, Int)]) -> [MRRecoveryPoint] {
        pairs.map { MRRecoveryPoint(offset: $0.0, bpm: $0.1) }
    }

    @Test func endHRIsMeanOfLastThirtySeconds() {
        let series: [(offset: TimeInterval, bpm: Int)] = [(0, 100), (3560, 150), (3580, 154), (3600, 152)]
        // duration 3600 → [3570, 3600] 안의 154·152 평균
        #expect(MRRecovery.endHR(series: series, duration: 3600) == 153)
        #expect(MRRecovery.endHR(series: [(0, 100)], duration: 3600) == nil)
    }

    @Test func hrAtUsesMedianWithinTolerance() {
        let p = post([(50, 130), (58, 122), (62, 118), (70, 116), (100, 110)])
        // 60±15 → 50·58·62·70 → 정렬 116,118,122,130 → 중앙값 120
        #expect(MRRecovery.hr(at: 60, post: p) == 120)
        // 120±15 → 없음
        #expect(MRRecovery.hr(at: 120, post: p) == nil)
    }

    @Test func eligibilityUsesEightyPercentOrFallback() {
        #expect(MRRecovery.isEligible(endHR: 152, maxHR: 190))     // 152 이상
        #expect(!MRRecovery.isEligible(endHR: 151, maxHR: 190))
        #expect(MRRecovery.isEligible(endHR: 130, maxHR: nil))
        #expect(!MRRecovery.isEligible(endHR: 129, maxHR: nil))
    }

    @Test func computeRequiresSixtySecondSample() {
        let p = post([(55, 125), (65, 121), (118, 110), (125, 108)])
        let r = MRRecovery.compute(endHR: 150, post: p)
        #expect(r?.hrr1 == 27)
        #expect(r?.hrr2 == 41)
        #expect(MRRecovery.compute(endHR: 150, post: post([(120, 110)])) == nil)
    }

    @Test func residualsRemoveEndHREffect() {
        // hrr1 = 0.5×endHR − 40 정확히 → 잔차 전부 0
        let cal = Calendar.current
        let obs: [MRRecovery.Obs] = (0..<20).map { i in
            let end = 140.0 + Double(i)
            return MRRecovery.Obs(date: cal.date(byAdding: .day, value: -i * 5, to: Date())!,
                                  endHR: end, hrr1: 0.5 * end - 40)
        }
        let r = MRRecovery.residuals(obs: obs, asOf: Date())
        #expect(r.count == 20)
        #expect(r.allSatisfy { abs($0.value) < 1e-6 })
        // 16개 미만이면 빈 배열
        #expect(MRRecovery.residuals(obs: Array(obs.prefix(10)), asOf: Date()).isEmpty)
    }

    @Test func residualsUseTemperatureWhenAvailable() {
        // hrr1 = 0.5×endHR − 0.4×temp − 20 정확히 → 기온 모델 잔차 0, 기온 무시 모델은 0이 아님
        let cal = Calendar.current
        let obs: [MRRecovery.Obs] = (0..<24).map { i in
            let end = 140.0 + Double(i % 12)
            let temp = Double((i * 7) % 30)
            return MRRecovery.Obs(date: cal.date(byAdding: .day, value: -i * 4, to: Date())!,
                                  endHR: end, hrr1: 0.5 * end - 0.4 * temp - 20, tempC: temp)
        }
        let withTemp = MRRecovery.residuals(obs: obs, asOf: Date())
        #expect(withTemp.count == 24)
        #expect(withTemp.allSatisfy { abs($0.value) < 1e-6 })
        let noTemp = MRRecovery.residuals(obs: obs, asOf: Date(), useTemp: false)
        #expect(noTemp.contains { abs($0.value) > 0.5 })
        // 기온 있는 관측이 16개 미만이면 종료심박만으로 (기온 없는 러닝도 포함해 24개)
        let sparse = obs.enumerated().map { i, o in
            MRRecovery.Obs(date: o.date, endHR: o.endHR, hrr1: o.hrr1, tempC: i < 10 ? o.tempC : nil)
        }
        #expect(MRRecovery.residuals(obs: sparse, asOf: Date()).count == 24)
    }

    @Test func observationOnlyWhenImproved() {
        let m = MRRecovery.metric
        let up   = MRFormShift(metric: m, recentMean: 3, baseMean: -3, delta: 6, mdc: 3, weeksConsistent: 5, r2: nil)
        let down = MRFormShift(metric: m, recentMean: -3, baseMean: 3, delta: -6, mdc: 3, weeksConsistent: 5, r2: nil)
        let weak = MRFormShift(metric: m, recentMean: 1, baseMean: 0, delta: 1, mdc: 3, weeksConsistent: 1, r2: nil)
        #expect(MRRecovery.observation(shift: up)?.text.contains("6") == true)
        #expect(MRRecovery.observation(shift: down) == nil)
        #expect(MRRecovery.observation(shift: weak) == nil)
    }

    // MARK: 회복 곡선 모양 (τ)

    /// HR(t) = HR∞ + (endHR − HR∞)·e^(−t/τ) 로 만든 값에서 τ와 HR∞가 되돌아오는지
    @Test func decayRecoversTauAndAsymptote() {
        let endHR = 170.0, asym = 110.0, tau = 60.0
        let hr60  = asym + (endHR - asym) * exp(-60 / tau)
        let hr120 = asym + (endHR - asym) * exp(-120 / tau)
        let d = MRRecovery.decay(endHR: endHR, hr60: hr60, hr120: hr120)
        #expect(d != nil)
        #expect(abs((d?.tau ?? 0) - tau) < 2)
        #expect(abs((d?.asymptote ?? 0) - asym) < 3)
        // x = 2분째 낙폭 / 1분째 낙폭 = e^(−60/τ)
        #expect(abs((d?.ratio ?? 0) - exp(-1)) < 0.02)
    }

    /// 종료심박이 달라도 같은 곡선 모양이면 τ가 같다 — 강도 교란이 x에서 소거되는지
    @Test func decayIsIndependentOfEndHR() {
        let tau = 70.0
        func make(_ endHR: Double, _ asym: Double) -> Double? {
            let hr60  = asym + (endHR - asym) * exp(-60 / tau)
            let hr120 = asym + (endHR - asym) * exp(-120 / tau)
            return MRRecovery.decay(endHR: endHR, hr60: hr60, hr120: hr120)?.tau
        }
        let a = make(185, 115), b = make(150, 100)
        #expect(a != nil && b != nil)
        #expect(abs((a ?? 0) - (b ?? 1)) < 1)
    }

    @Test func decayFromStoredHRR1MatchesDirectForm() {
        // 캐시는 hr60을 저장하지 않는다 — endHR·hrr1로 되돌린 값이 같아야 한다.
        let endHR = 170.0, hr60 = 132.0, hr120 = 118.0
        let direct = MRRecovery.decay(endHR: endHR, hr60: hr60, hr120: hr120)
        let restored = MRRecovery.decay(endHR: endHR, hrr1: endHR - hr60, hr120: hr120)
        #expect(direct?.tau == restored?.tau)
        #expect(direct?.ratio == restored?.ratio)
        #expect(restored != nil)
    }

    @Test func decayGuardsRejectBadShapes() {
        // 1분 낙폭 7bpm → 거부, 8bpm → 통과
        #expect(MRRecovery.decay(endHR: 150, hr60: 143, hr120: 140) == nil)
        #expect(MRRecovery.decay(endHR: 150, hr60: 142, hr120: 139) != nil)
        // 2분째에 심박이 되오름 → 거부
        #expect(MRRecovery.decay(endHR: 170, hr60: 130, hr120: 134) == nil)
        // 2분 낙폭 0 → 거부
        #expect(MRRecovery.decay(endHR: 170, hr60: 130, hr120: 130) == nil)
        // x ≥ 1 (2분째가 더 크게 떨어짐) → 거부
        #expect(MRRecovery.decay(endHR: 170, hr60: 150, hr120: 125) == nil)
        // τ < 20초 (거의 즉시 바닥) → 거부. x = e^(−60/20) = 0.0498 보다 작은 x
        #expect(MRRecovery.decay(endHR: 190, hr60: 120, hr120: 117) == nil)
        // τ > 300초 → 거부. x = e^(−60/300) = 0.8187 보다 큰 x
        #expect(MRRecovery.decay(endHR: 170, hr60: 140, hr120: 114) == nil)
    }

    @Test func computeAttachesDecayWhenTwoMinuteSampleExists() {
        // τ=60, HR∞=110, endHR=170 → hr60 132, hr120 118
        let p = post([(58, 132), (62, 132), (118, 118), (122, 118)])
        let r = MRRecovery.compute(endHR: 170, post: p)
        #expect(r?.hrr1 == 38)
        #expect(r?.hrr2 == 52)
        #expect(r?.decay != nil)
        #expect(abs((r?.decay?.tau ?? 0) - 60) < 3)
    }

    @Test func computeHasNoDecayWithoutTwoMinuteSample() {
        let r = MRRecovery.compute(endHR: 170, post: post([(58, 132), (62, 132)]))
        #expect(r?.hrr1 == 38)      // 기존 동작 불변
        #expect(r?.hrr2 == nil)
        #expect(r?.decay == nil)
    }

    /// 같은 심박으로 끝낸 러닝만 써야 한다 — 170에서 끝낸 러닝은 낙폭이 커서 섞이면 띠가 위로 끌린다.
    @Test func bandsMatchOnEndHR() {
        var h: [MRRecoveryDropPoint] = []
        for i in 0..<10 { h.append(MRRecoveryDropPoint(endHR: 148.0 + Double(i % 5), hrr1: 20.0 + Double(i % 5), hrr2: 30.0)) }
        for _ in 0..<10 { h.append(MRRecoveryDropPoint(endHR: 175.0, hrr1: 45.0, hrr2: 60.0)) }
        let b = MRRecovery.bands(endHR: 150, history: h)
        #expect(b.minute1?.n == 10)            // 175로 끝낸 10건은 제외된다
        #expect((b.minute1?.hi ?? 99) < 30)    // 45가 섞였다면 상한이 훨씬 높아진다
        #expect(b.minute2?.lo == 30)
    }

    @Test func bandsNeedEightMatchingRuns() {
        var seven: [MRRecoveryDropPoint] = []
        for _ in 0..<7 { seven.append(MRRecoveryDropPoint(endHR: 150.0, hrr1: 22.0)) }
        #expect(MRRecovery.bands(endHR: 150, history: seven).isEmpty)
        var eight = seven
        eight.append(MRRecoveryDropPoint(endHR: 150.0, hrr1: 22.0))
        #expect(MRRecovery.bands(endHR: 150, history: eight).minute1 != nil)
        // hrr2가 없는 점만 8개면 1분 띠만 생긴다
        #expect(MRRecovery.bands(endHR: 150, history: eight).minute2 == nil)
        // 표본이 많아도 종료심박이 다 멀면 nil
        var far: [MRRecoveryDropPoint] = []
        for _ in 0..<20 { far.append(MRRecoveryDropPoint(endHR: 170.0, hrr1: 40.0)) }
        #expect(MRRecovery.bands(endHR: 150, history: far).isEmpty)
    }

    @Test func tauPercentileNeedsEightSamples() {
        let seven = [40.0, 45, 50, 55, 60, 65, 70]
        #expect(MRRecovery.tauPercentile(52, history: seven) == nil)
        #expect(MRRecovery.tauPercentile(52, history: seven + [75]) != nil)
    }

    @Test func tauPercentileCountsSamplesBelow() {
        let h = [40.0, 45, 50, 55, 60, 65, 70, 75]   // 8개
        #expect(MRRecovery.tauPercentile(39, history: h) == 0.0)     // 전부 위
        #expect(MRRecovery.tauPercentile(76, history: h) == 1.0)     // 전부 아래
        #expect(MRRecovery.tauPercentile(57, history: h) == 0.5)     // 4/8
    }

    @Test func shapeCaptionSaysFasterSameSlower() {
        func shape(_ tau: Double, _ history: [Double]) -> MRRecoveryShape {
            MRRecoveryShape(hrr1: 38, hrr2: 52,
                            decay: MRRecoveryDecay(ratio: exp(-60 / tau), tau: tau, asymptote: 110),
                            percentile: MRRecovery.tauPercentile(tau, history: history))
        }
        let h = [40.0, 45, 50, 55, 60, 65, 70, 75]
        #expect(MRRecovery.shapeCaption(shape(39, h)) == "평소보다 빠르게 안정됐어요")
        #expect(MRRecovery.shapeCaption(shape(57, h)) == "평소대로 내려왔어요")
        #expect(MRRecovery.shapeCaption(shape(76, h)) == "2분 뒤에도 계속 내려오는 중이었어요")
        // 사분위 문구의 영문판도 한 건은 덮는다 — 폴백 제거로 없어진 영문 커버리지를 여기로 옮김
        inEnglish {
            #expect(MRRecovery.shapeCaption(shape(39, h)) == "Settled faster than usual")
        }
    }

    @Test func shapeCaptionIsSilentWithoutEnoughHistory() {
        // 과거 표본이 8개 미만이면 percentile이 nil → 카드는 그 줄을 아예 그리지 않는다.
        // 원시 숫자 폴백은 없앤다: 같은 숫자를 상세 화면 심박 패널이 이미 보여주고, 표시 여부가
        // 120초 샘플과 무관한 τ 성립 조건에 갈리는 줄은 이유를 말하지 않는 한 없느니만 못하다.
        let s = MRRecoveryShape(hrr1: 38, hrr2: 52,
                                decay: MRRecoveryDecay(ratio: 0.37, tau: 60, asymptote: 110),
                                percentile: nil)
        #expect(MRRecovery.shapeCaption(s) == nil)
    }

    @Test func shapeCaptionBucketsAreSymmetricAtQuartiles() {
        let h = [40.0, 45, 50, 55, 60, 65, 70, 75]
        func caption(_ tau: Double) -> String? {
            MRRecovery.shapeCaption(MRRecoveryShape(
                hrr1: 38, hrr2: 52,
                decay: MRRecoveryDecay(ratio: exp(-60 / tau), tau: tau, asymptote: 110),
                percentile: MRRecovery.tauPercentile(tau, history: h)))
        }
        // 47 → 40·45 두 개가 아래 → p = 0.25 (하위 사분위에 포함)
        #expect(MRRecovery.tauPercentile(47, history: h) == 0.25)
        #expect(caption(47) == "평소보다 빠르게 안정됐어요")
        // 67 → 40~65 여섯 개가 아래 → p = 0.75
        #expect(MRRecovery.tauPercentile(67, history: h) == 0.75)
        #expect(caption(67) == "2분 뒤에도 계속 내려오는 중이었어요")
    }

    @Test func shapeInitRequiresDecayAndHRR2() {
        let noTwoMinute = MRRecovery.compute(endHR: 170, post: post([(58, 132), (62, 132)]))
        #expect(noTwoMinute != nil)
        #expect(MRRecoveryShape(noTwoMinute!, percentile: nil) == nil)

        let withTwoMinute = MRRecovery.compute(endHR: 170, post: post([(58, 132), (62, 132), (118, 118), (122, 118)]))
        #expect(withTwoMinute != nil)
        let shape = MRRecoveryShape(withTwoMinute!, percentile: nil)
        #expect(shape != nil)
        #expect(shape?.hrr2 == 52)
    }
}
