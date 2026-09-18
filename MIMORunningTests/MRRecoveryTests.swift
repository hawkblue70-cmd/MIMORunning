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
}
