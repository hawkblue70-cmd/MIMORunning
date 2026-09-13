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
            // 페이스·거리를 살짝 흔든다 — 둘 다 고정이면 speed/durationMin 열이 절편과
            // 완전히 비례해 설계행렬이 특이(singular)해지고 lstsq가 nil을 반환한다.
            let km = 8.0 + Double(i % 3)
            let pace = paceSecPerKm + Double(i % 4) * 5
            return MRWorkout(start: d, durationMin: km * pace / 60, distanceKm: km,
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

    func testNoHotDaysFallsBackToLiterature() {
        let runs = makeRuns(count: 60, temps: [4, 8, 12, 17], slope: 0.9)
        let m = mrFitHeatHRModel(runs: runs, asOf: Date())
        XCTAssertTrue(m.ok)
        XCTAssertTrue(m.isFallback)
        XCTAssertEqual(m.bpmPerC, MRHeatHRModel.fallbackBpmPerC, accuracy: 0.001)
        XCTAssertFalse(m.rejectReason.isEmpty)
    }

    func testFewHotRowsFallsBack() {
        // 60개 중 20°C 이상(더운 날)은 딱 4개 — 최고 기온은 25°C를 넘지만 더운 쪽 표본이 부족하다.
        var temps = (0..<56).map { [5.0, 10.0, 15.0][$0 % 3] }
        temps.append(contentsOf: [28, 28, 28, 28])
        let runs = makeRuns(count: 60, temps: temps, slope: 0.9)
        let m = mrFitHeatHRModel(runs: runs, asOf: Date())
        XCTAssertTrue(m.isFallback)
        XCTAssertFalse(m.rejectReason.isEmpty)
    }

    func testTooFewRunsFallsBack() {
        let runs = makeRuns(count: 10, temps: [5, 15, 25, 30], slope: 0.9)
        XCTAssertTrue(mrFitHeatHRModel(runs: runs, asOf: Date()).isFallback)
    }

    func testImplausibleSlopeFallsBack() {
        // 기온이 올라갈수록 심박이 내려가는(음수 기울기) 데이터 → 회귀가 더위를 못 잡음 → 폴백
        let runs = makeRuns(count: 60, temps: [5, 10, 15, 20, 25, 30], slope: -1.0)
        let m = mrFitHeatHRModel(runs: runs, asOf: Date())
        XCTAssertTrue(m.isFallback)
    }

    func testSmallPositiveSlopeIsAcceptedAsLearned() {
        let runs = makeRuns(count: 60, temps: [5, 10, 15, 20, 25, 30], slope: 0.1)
        let m = mrFitHeatHRModel(runs: runs, asOf: Date())
        XCTAssertTrue(m.ok)
        XCTAssertFalse(m.isFallback)
        XCTAssertEqual(m.bpmPerC, 0.1, accuracy: 0.1)
    }

    func testLearnedModelClampsAboveMaxTemp() {
        let runs = makeRuns(count: 60, temps: [5, 10, 15, 20, 25, 30], slope: 0.9)
        let m = mrFitHeatHRModel(runs: runs, asOf: Date())
        XCTAssertTrue(m.ok)
        XCTAssertFalse(m.isFallback)
        XCTAssertEqual(m.rawDelta(35), m.rawDelta(30), accuracy: 0.001, "학습 최고 기온 밖은 외삽하지 않는다")
        XCTAssertGreaterThan(MRHeatHRModel.fallback().rawDelta(35), MRHeatHRModel.fallback().rawDelta(30),
                             "폴백은 문헌 곡선이라 40°C까지는 외삽을 허용한다")
    }

    func testRawDeltaIgnoresOk() {
        var m = MRHeatHRModel()
        m.bpmPerC = 1.0
        m.tempMaxC = 30
        XCTAssertEqual(m.rawDelta(25), 10, accuracy: 0.001)
        XCTAssertEqual(m.delta(25), 0, accuracy: 0.001, "ok=false면 delta는 0이어야 한다")
    }

    func testRowFilterExcludesIndoorShortAndNoTemp() {
        let cal = Calendar.current
        var runs = makeRuns(count: 60, temps: [5, 10, 15, 20, 25, 30], slope: 0.9)

        // 실내 20건 — 제외돼야 한다
        for i in 0..<20 {
            let d = cal.date(byAdding: .day, value: -(1000 + i), to: Date())!
            runs.append(MRWorkout(start: d, durationMin: 40, distanceKm: 8,
                                  hrAvg: 150, hrMax: 175, tempC: 25, humidity: nil,
                                  indoor: true, isInterval: false))
        }
        // 기온 없음 20건 — 제외돼야 한다
        for i in 0..<20 {
            let d = cal.date(byAdding: .day, value: -(2000 + i), to: Date())!
            runs.append(MRWorkout(start: d, durationMin: 40, distanceKm: 8,
                                  hrAvg: 150, hrMax: 175, tempC: nil, humidity: nil,
                                  indoor: false, isInterval: false))
        }
        // 20분 미만 20건 — 제외돼야 한다
        for i in 0..<20 {
            let d = cal.date(byAdding: .day, value: -(3000 + i), to: Date())!
            runs.append(MRWorkout(start: d, durationMin: 10, distanceKm: 8,
                                  hrAvg: 150, hrMax: 175, tempC: 25, humidity: nil,
                                  indoor: false, isInterval: false))
        }

        let m = mrFitHeatHRModel(runs: runs, asOf: Date())
        XCTAssertFalse(m.isFallback)
        XCTAssertEqual(m.n, 60)
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
