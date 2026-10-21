import XCTest
@testable import MIMORunning

/// 보폭 평소 범위를 개인 속도 곡선으로 — 폴백·변환·느린 날 판정.
/// 설계: docs/superpowers/specs/2026-10-21-stride-speed-curve-design.md
@MainActor
final class FormSpeedCurveTests: XCTestCase {

    private let asOf = Date(timeIntervalSince1970: 1_792_000_000)

    /// 보폭 = 0.90 + 0.004 × (속도 − 150) 에 ±0.005 흔들림, 속도 140~160m/min (6'15"~7'09")
    private func strideCurve() -> FormSpeedCurve {
        let pts = (0..<60).map { i -> (date: Date, speed: Double, value: Double) in
            let speed = 140 + Double(i % 21)
            let wobble = Double((i * 7) % 3 - 1) * 0.005
            return (asOf.addingTimeInterval(-Double(i) * 86400), speed, 0.90 + 0.004 * (speed - 150) + wobble)
        }
        return FormSpeedCurve.fit(pts, asOf: asOf)!
    }

    private func band(judgeable: Bool = true, stride: FormStat? = FormStat(median: 0.90, sd: 0.012, count: 34, p10: nil, p90: nil)) -> BandBaseline {
        BandBaseline(band: .daily, isJudgeable: judgeable, sampleCount: 34, windowMonths: 6, paceMin: 383, paceMax: 400,
                     cadence: nil, strideLength: stride, groundContact: nil, verticalOsc: nil, heartRate: nil,
                     cadenceStrideR: nil, cadenceResidualP10: nil, cadenceResidualP25: nil,
                     cadenceResidualP75: nil, cadenceResidualP90: nil, strideResidualP10: nil,
                     strideResidualP25: nil, strideResidualP75: nil, strideResidualP90: nil, recentSamples: [])
    }

    private func baseline(curve: FormSpeedCurve?) -> RunningFormBaseline {
        let cut = PaceBandCutoffs(jogMax: 420, verySlowMax: 480, fastMin: 300, jogMin: 400, dailyMin: 380,
                                  tempoMin: 350, mergedBands: [])
        return RunningFormBaseline(version: RunningFormBaseline.currentVersion, computedAt: asOf, cutoffs: cut,
                                   bands: [.daily: band()], cadenceHRDiag: nil, gctBaselineResidualMean: nil,
                                   allFormSamples: [], strideCurve: curve)
    }

    func testFitNeedsMinimumPoints() {
        let pts = (0..<24).map { (date: asOf, speed: 140 + Double($0), value: 0.9) }
        XCTAssertNil(FormSpeedCurve.fit(pts, asOf: asOf))
    }

    // 외삽 금지 — 관측 속도 범위 밖이면 nil
    func testStatOutsideObservedSpeedIsNil() {
        let c = strideCurve()
        XCTAssertNotNil(c.stat(atPace: 400))          // 150m/min
        XCTAssertNil(c.stat(atPace: 300))             // 200m/min
        XCTAssertNil(c.stat(atPace: 480))             // 125m/min
        XCTAssertNil(c.stat(atPace: 0))
    }

    // FormStat 변환 — 기대값 ± 1.2 × 잔차 SD, p10/p90 없음
    func testStatConversion() {
        let c = strideCurve()
        let st = c.stat(atPace: 400)!
        XCTAssertEqual(st.median, c.predict(speed: 150), accuracy: 1e-12)
        XCTAssertEqual(st.median, 0.90, accuracy: 0.003)
        XCTAssertEqual(st.lower, st.median - 1.2 * c.residualSD, accuracy: 1e-12)
        XCTAssertEqual(st.upper, st.median + 1.2 * c.residualSD, accuracy: 1e-12)
        XCTAssertNil(st.p10)
        XCTAssertNil(st.p90)
        XCTAssertEqual(st.count, 60)
    }

    func testStrideStatUsesCurveWhenJudgeableAndCovered() {
        let bl = baseline(curve: strideCurve())
        let st = bl.strideStat(band(), paceSecPerKm: 400)
        XCTAssertTrue(bl.usesStrideCurve(band(), paceSecPerKm: 400))
        XCTAssertNil(st?.p10)
        XCTAssertNotEqual(st?.sd, 0.012)
    }

    // 폴백 — 곡선 없음 · 판정불가 구간 · 범위 밖 속도 · 구간 보폭 없음
    func testStrideStatFallsBackToBand() {
        let withCurve = baseline(curve: strideCurve())
        XCTAssertEqual(baseline(curve: nil).strideStat(band(), paceSecPerKm: 400)?.sd, 0.012)
        XCTAssertEqual(withCurve.strideStat(band(judgeable: false), paceSecPerKm: 400)?.sd, 0.012)
        XCTAssertEqual(withCurve.strideStat(band(), paceSecPerKm: 300)?.sd, 0.012)
        XCTAssertEqual(withCurve.strideStat(band(), paceSecPerKm: nil)?.sd, 0.012)
        XCTAssertNil(withCurve.strideStat(band(stride: nil), paceSecPerKm: 400))
        XCTAssertNil(withCurve.strideStat(nil, paceSecPerKm: 400))
        XCTAssertFalse(withCurve.usesStrideCurve(band(judgeable: false), paceSecPerKm: 400))
    }

    // 같은 구간 안 느린 러닝(7'00" = 142.9m/min): 구간 중앙값으론 '아래', 곡선으론 '범위'
    func testSlowRunInsideBandIsInRangeOnCurve() {
        let bl = baseline(curve: strideCurve())
        let todayStride = 0.90 + 0.004 * (60000.0 / 420 - 150)     // ≈ 0.871
        let bandStatus = FormNarrative.status(rawValue: todayStride, stat: band().strideLength, metric: .stride)
        let curveStatus = FormNarrative.status(rawValue: todayStride,
                                               stat: bl.strideStat(band(), paceSecPerKm: 420), metric: .stride)
        XCTAssertEqual(bandStatus, .below)
        XCTAssertEqual(curveStatus, .inRange)
    }

    // 옛 캐시(strideCurve 키 없음)도 디코딩되고 곡선은 nil
    func testDecodesCacheWithoutStrideCurve() throws {
        var bl = baseline(curve: nil)
        bl.strideCurve = nil
        let data = try JSONEncoder().encode(bl)
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "strideCurve")
        obj["version"] = 17
        let old = try JSONDecoder().decode(RunningFormBaseline.self,
                                           from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.strideCurve)
        XCTAssertNotEqual(old.version, RunningFormBaseline.currentVersion)   // 버전 불일치 → 재계산
    }
}
