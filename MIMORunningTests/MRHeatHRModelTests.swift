import XCTest
@testable import MIMORunning

/// 관측 심박 → 15°C 환산. 기온이 없거나 모델이 못 쓰면 항등이어야 한다.
final class MRHeatHRModelTests: XCTestCase {

    /// 기온·심박이 함께 변하는 합성 러닝. hr = base + slope × max(0, temp−15) + 잡음(결정적).
    private func makeRuns(count: Int, temps: [Double], slope: Double, baseHR: Double = 140,
                          paceSecPerKm: Double = 360) -> [MRWorkout] {
        let cal = Calendar.current
        return (0..<count).map { i in
            let t = temps[i % temps.count]
            let noise = Double((i * 7) % 5) - 2.0          // −2…+2, 결정적
            let hr = baseHR + slope * max(0, t - MR_REF_TEMP) + noise
            let d = cal.date(byAdding: .day, value: -(i * 3 + 1), to: Date())!
            // 페이스를 살짝 흔든다 — 고정 페이스면 speed/durationMin 열이 절편과
            // 완전히 비례해 설계행렬이 특이(singular)해지고 lstsq가 nil을 반환한다.
            let pace = paceSecPerKm + Double(i % 4) * 5
            return MRWorkout(start: d, durationMin: 8 * pace / 60, distanceKm: 8,
                             hrAvg: hr, hrMax: hr + 25, tempC: t, humidity: nil,
                             indoor: false, isInterval: false)
        }
    }

    func testFitsSlopeFromOwnRuns() {
        let runs = makeRuns(count: 60, temps: [5, 10, 15, 20, 25, 30], slope: 0.9)
        let m = mrFitHeatHRModel(runs: runs, asOf: Date())
        XCTAssertTrue(m.ok)
        XCTAssertFalse(m.isFallback)
        XCTAssertEqual(m.bpmPerC, 0.9, accuracy: 0.15)
        XCTAssertEqual(m.toRef(150, tempC: 25), 150 - m.bpmPerC * 10, accuracy: 0.001)
        XCTAssertEqual(m.toRef(150, tempC: 10), 150, accuracy: 0.001, "15°C 아래는 보정하지 않는다")
    }

    func testNarrowTemperatureSpanFallsBackToLiterature() {
        let runs = makeRuns(count: 60, temps: [14, 15, 16, 17], slope: 0.9)
        let m = mrFitHeatHRModel(runs: runs, asOf: Date())
        XCTAssertTrue(m.ok)
        XCTAssertTrue(m.isFallback)
        XCTAssertEqual(m.bpmPerC, MRHeatHRModel.fallbackBpmPerC, accuracy: 0.001)
        XCTAssertFalse(m.rejectReason.isEmpty)
    }

    func testTooFewRunsFallsBack() {
        let runs = makeRuns(count: 10, temps: [5, 15, 25, 30], slope: 0.9)
        XCTAssertTrue(mrFitHeatHRModel(runs: runs, asOf: Date()).isFallback)
    }

    func testImplausibleSlopeFallsBack() {
        // 기온이 올라갈수록 심박이 내려가는(음수 기울기) 데이터 → 문헌 범위 밖 → 폴백
        let runs = makeRuns(count: 60, temps: [5, 10, 15, 20, 25, 30], slope: -1.0)
        let m = mrFitHeatHRModel(runs: runs, asOf: Date())
        XCTAssertTrue(m.isFallback)
    }

    func testNilTemperatureIsIdentity() {
        let m = MRHeatHRModel.fallback()
        XCTAssertEqual(m.toRef(150, tempC: nil), 150, accuracy: 0.001)
        XCTAssertEqual(m.delta(nil), 0, accuracy: 0.001)
    }

    func testUnusableModelIsIdentity() {
        let m = MRHeatHRModel()          // ok=false
        XCTAssertEqual(m.toRef(150, tempC: 30), 150, accuracy: 0.001)
        XCTAssertEqual(m.delta(30), 0, accuracy: 0.001)
    }

    func testExplainsNeedsAtLeastThreeBpm() {
        let m = MRHeatHRModel.fallback()  // 0.8 bpm/°C
        XCTAssertFalse(m.explains(tempC: 18))   // +2.4
        XCTAssertTrue(m.explains(tempC: 19))    // +3.2
        XCTAssertFalse(m.explains(tempC: nil))
    }

    func testRefHRForActivity() {
        let m = MRHeatHRModel.fallback()
        let a = Activity(id: UUID(), type: .running, date: Date(), duration: 3600, distance: 10_000,
                         calories: nil, avgHeartRate: 150, temperatureC: 25, humidityPercent: nil)
        XCTAssertEqual(m.refHR(of: a)!, 150 - 8, accuracy: 0.001)
        let noHR = Activity(id: UUID(), type: .running, date: Date(), duration: 3600, distance: 10_000,
                            calories: nil, avgHeartRate: nil, temperatureC: 25, humidityPercent: nil)
        XCTAssertNil(m.refHR(of: noHR))
    }
}
