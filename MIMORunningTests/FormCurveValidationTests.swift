import XCTest
@testable import MIMORunning

/// 개인 속도-폼 곡선 검증 하네스(DEBUG 전용) 자체가 맞게 계산하는지 합성 데이터로 확인.
/// 설계: docs/superpowers/specs/2026-10-21-form-speed-curve-validation.md
@MainActor
final class FormCurveValidationTests: XCTestCase {

    private let asOf = Date(timeIntervalSince1970: 1_792_000_000)

    private func day(_ offset: Int) -> Date { asOf.addingTimeInterval(Double(offset) * 86400) }

    /// 페이스(초/km)에서 케이던스×보폭이 실제 속도와 맞는 샘플.
    private func sample(daysAgo: Int, pace: Double, cadence: Double,
                        gct: Double? = 270, vo: Double? = 8.6) -> FormCurveSample {
        let speed = 60000.0 / pace
        return FormCurveSample(date: day(-daysAgo), paceSecPerKm: pace, effectivePaceSecPerKm: pace,
                               cadence: cadence, stride: speed / cadence, gct: gct, vo: vo)
    }

    private let cutoffs = PaceBandCutoffs(jogMax: 440, verySlowMax: 480, fastMin: 300,
                                          jogMin: 410, dailyMin: 390, tempoMin: 370, mergedBands: [])

    // ① 2차 관계 복원
    func testFitCurveRecoversQuadratic() {
        let truth: (Double) -> Double = { s in 280 - 0.5 * (s - 150) + 0.01 * (s - 150) * (s - 150) }
        let pts = stride(from: 130.0, through: 180.0, by: 1.0).enumerated().map { i, s in
            (date: day(-i), speed: s, value: truth(s))
        }
        let fit = try! XCTUnwrap(FormCurveValidation.fitCurve(pts, asOf: asOf))
        XCTAssertEqual(fit.predict(speed: 140), truth(140), accuracy: 0.01)
        XCTAssertEqual(fit.predict(speed: 172), truth(172), accuracy: 0.01)
        XCTAssertEqual(fit.residualSD, 0, accuracy: 1e-6)
    }

    func testFitCurveNeedsMinimumPoints() {
        let pts = (0..<24).map { (date: day(-$0), speed: 150.0 + Double($0), value: 270.0) }
        XCTAssertNil(FormCurveValidation.fitCurve(pts, asOf: asOf))
    }

    // ② walk-forward에 미래 러닝이 섞이지 않음
    func testCurveFitIgnoresRunsAfterTarget() {
        var all = (10..<60).map { sample(daysAgo: $0, pace: 360 + Double($0 % 20) * 3, cadence: 170, gct: 270) }
        let target = sample(daysAgo: 5, pace: 390, cadence: 170, gct: 270)
        let before = try! XCTUnwrap(FormCurveValidation.curveFit(for: target, metric: .gct, samples: all + [target]))
        all.append(sample(daysAgo: 1, pace: 390, cadence: 170, gct: 400))   // 미래 극단값
        let after = try! XCTUnwrap(FormCurveValidation.curveFit(for: target, metric: .gct, samples: all + [target]))
        XCTAssertEqual(before.predict(speed: target.effectiveSpeedMPerMin),
                       after.predict(speed: target.effectiveSpeedMPerMin), accuracy: 1e-9)
        XCTAssertEqual(before.n, 50)   // target 자신도 빠진다
    }

    // ③ 외삽 고정
    func testPredictClampsOutsideObservedSpeed() {
        let curve: (Double) -> Double = { s in
            let x = s - 150
            return 300 - 2 * x + 0.3 * x * x
        }
        let pts = stride(from: 140.0, through: 160.0, by: 0.5).enumerated().map { i, s in
            (date: day(-i), speed: s, value: curve(s))
        }
        let fit = try! XCTUnwrap(FormCurveValidation.fitCurve(pts, asOf: asOf))
        XCTAssertEqual(fit.predict(speed: 200), fit.predict(speed: 160), accuracy: 1e-9)
        XCTAssertEqual(fit.predict(speed: 100), fit.predict(speed: 140), accuracy: 1e-9)
    }

    // ④ 페이스 폭 60초 미만이면 H3 판정 불가
    func testGearShareNotJudgeableWhenPaceSpreadNarrow() {
        let s = (0..<40).map { sample(daysAgo: $0, pace: 380 + Double($0 % 10) * 4, cadence: 170) }
        let h3 = FormCurveValidation.gearShare(samples: s)
        XCTAssertFalse(h3.isJudgeable)
        XCTAssertNil(h3.cadenceShare)
        XCTAssertFalse(h3.passes)
    }

    // H3 — 케이던스 ∝ 속도^0.3이면 케이던스 몫 0.3
    func testGearShareRecoversElasticity() {
        let s = (0..<60).map { i -> FormCurveSample in
            let pace = 300 + Double(i) * 2.5          // 5'00"~7'27"
            let speed = 60000 / pace
            return sample(daysAgo: i, pace: pace, cadence: 30 * pow(speed, 0.3))
        }
        let h3 = FormCurveValidation.gearShare(samples: s)
        XCTAssertTrue(h3.isJudgeable)
        XCTAssertEqual(try XCTUnwrap(h3.cadenceShare), 0.3, accuracy: 1e-6)
        XCTAssertTrue(h3.passes)
    }

    // ⑤ β 부호 복원 — 같은 속도에서 케이던스 1spm 낮으면 접지 2ms 길다
    func testTradeOffRecoversNegativeBeta() {
        let s = (0..<60).map { i -> FormCurveSample in
            let pace = 370 + Double(i % 12) * 5
            let cadOffset = Double((i * 7) % 9) - 4          // −4~+4, 속도와 무관
            let cad = 172 - (pace - 400) * 0.1 + cadOffset
            let gct = 265 + (pace - 400) * 0.4 - 2 * cadOffset
            return sample(daysAgo: i, pace: pace, cadence: cad, gct: gct)
        }
        let h2 = try! XCTUnwrap(FormCurveValidation.tradeOff(samples: s, asOf: asOf))
        XCTAssertEqual(h2.beta, -2, accuracy: 0.05)
        XCTAssertLessThan(h2.r, -0.9)
        XCTAssertTrue(h2.passes)
        XCTAssertEqual(h2.examples.count, 3)
    }

    // 케이던스 반감 같은 산출 이상은 제외
    func testCadenceStrideOutlierExcluded() {
        let ok = sample(daysAgo: 1, pace: 390, cadence: 170)
        let halved = FormCurveSample(date: day(-2), paceSecPerKm: 390, effectivePaceSecPerKm: 390,
                                     cadence: 85, stride: ok.stride, gct: 270, vo: 8.6)
        XCTAssertFalse(ok.isCadenceStrideOutlier)
        XCTAssertTrue(halved.isCadenceStrideOutlier)
        let r = FormCurveValidation.run(samples: [ok, halved], cutoffs: cutoffs, asOf: asOf)
        XCTAssertEqual(r.totalRuns, 2)
        XCTAssertEqual(r.outlierRuns, 1)
    }

    // H1 — 페이스에 따라 접지가 연속으로 변하면 곡선이 구간 중앙값보다 잘 맞힌다
    func testWalkForwardCurveBeatsBandOnSmoothRelation() {
        let s = (0..<200).map { i -> FormCurveSample in
            let pace = 360 + Double((i * 13) % 80)          // 6'00"~7'19"
            return sample(daysAgo: i, pace: pace, cadence: 172 - (pace - 400) * 0.1,
                          gct: 265 + (pace - 400) * 0.6)
        }
        let (metrics, _) = FormCurveValidation.walkForward(samples: s, cutoffs: cutoffs, asOf: asOf)
        let gct = try! XCTUnwrap(metrics.first { $0.metric == .gct })
        XCTAssertGreaterThan(gct.n, 0)
        XCTAssertLessThan(gct.curveMAE, gct.bandMAE)
        XCTAssertFalse(FormCurveValidation.logLines(
            FormCurveValidation.run(samples: s, cutoffs: cutoffs, asOf: asOf)).isEmpty)
    }
}
