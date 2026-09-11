import XCTest
@testable import MIMORunning

/// 누적 상승 계산 — 화면의 "고도 획득"과 고도 배경 판정이 같이 쓰는 값.
final class ElevationGainTests: XCTestCase {

    func testCountsOnlyAscent() {
        // 0 → 10 → 0 → 10 : 오른 건 20m
        XCTAssertEqual(ElevationGain.cumulative([0, 10, 0, 10]), 20, accuracy: 0.01)
    }

    func testFlatIsZero() {
        XCTAssertEqual(ElevationGain.cumulative([30, 30, 30, 30]), 0, accuracy: 0.01)
        XCTAssertEqual(ElevationGain.cumulative([]), 0, accuracy: 0.01)
        XCTAssertEqual(ElevationGain.cumulative([30]), 0, accuracy: 0.01)
    }

    /// GPS 떨림은 세지 않는다 — 이게 없으면 평지에서도 큰 값이 쌓인다
    func testIgnoresGpsJitter() {
        var noisy: [Double] = []
        for i in 0..<2000 { noisy.append(30 + (i % 2 == 0 ? 1.2 : -1.2)) }
        XCTAssertEqual(ElevationGain.cumulative(noisy), 0, accuracy: 0.01,
                       "±1.2m 떨림이 상승으로 쌓이면 안 된다")
    }

    /// 떨림 속에 묻힌 실제 오르막은 잡아낸다
    func testFindsRealClimbUnderJitter() {
        var alt: [Double] = []
        for i in 0..<600 {
            let real = 30 + Double(i) * 0.05            // 600 샘플 동안 30m 상승
            alt.append(real + (i % 2 == 0 ? 1.2 : -1.2))
        }
        let gain = ElevationGain.cumulative(alt)
        XCTAssertGreaterThan(gain, 24, "실제 30m 상승을 놓치면 안 된다")
        XCTAssertLessThan(gain, 36, "떨림까지 더해 부풀면 안 된다")
    }

    /// 임계값 미만의 완만한 변화가 쌓여 실제로 올라간 경우도 반영된다
    func testSlowClimbBelowStepStillCounts() {
        // 1m씩 30번 = 30m 상승 (각 단계는 임계값 3m 미만)
        let alt = (0...30).map { 100 + Double($0) }
        XCTAssertEqual(ElevationGain.cumulative(alt), 30, accuracy: 3)
    }

    func testCustomStep() {
        let alt: [Double] = [0, 2, 4, 6]
        XCTAssertEqual(ElevationGain.cumulative(alt, minStep: 1), 6, accuracy: 0.01)
        XCTAssertEqual(ElevationGain.cumulative(alt, minStep: 10), 0, accuracy: 0.01)
    }

    /// 완만한 기복(진폭 2m)이 통째로 사라지면 안 된다 — 3m 임계값만 쓰던 때의 문제
    func testGentleRollingCourseIsNotFlattened() {
        var alt: [Double] = []
        for i in 0..<3000 {
            let t = Double(i) / 3000
            alt.append(30 + 2 * sin(t * 2 * .pi * 8))   // 8회 오르내림, 실제 상승 32m
        }
        let gain = ElevationGain.cumulative(alt)
        XCTAssertGreaterThan(gain, 24, "완만한 기복을 놓치면 도심 러닝이 전부 평지가 된다")
        XCTAssertLessThan(gain, 40)
    }
}

/// 트랙·평지에서 고도 항목이 사라지지 않고 0으로 남는지.
/// "값이 없다(실내런)"와 "값이 0이다(평지)"는 다른 정보다.
final class FlatCourseElevationTests: XCTestCase {

    private func detail(elevationGain: Double?) -> ActivityDetail {
        ActivityDetail(routeCoordinates: [], routeTimeOffsets: [], elevationGain: elevationGain,
                       avgPower: nil, avgCadence: 175, splits: [], hrZones: [],
                       intervalSegments: [], workoutType: .general,
                       avgGroundContactTime: nil, avgStrideLength: nil,
                       avgVerticalOscillation: nil, vo2Max: nil,
                       altitudeProfile: [], altitudeTimeProfile: [])
    }

    private var activity: Activity {
        Activity(id: UUID(), type: .running, date: Date(), duration: 3000,
                 distance: 10_000, calories: 500, avgHeartRate: 150)
    }

    func testFlatCourseKeepsElevationRowAsZero() {
        let items = RunMetricItem.list(activity: activity, detail: detail(elevationGain: 0),
                                       age: 50, isMale: true)
        let elev = items.first { $0.kind == .elevation }
        XCTAssertNotNil(elev, "평지라고 고도 칸이 사라지면 평지였다는 사실을 알 수 없다")
        XCTAssertEqual(elev?.value, "0 m")
    }

    func testIndoorRunHasNoElevationRow() {
        let items = RunMetricItem.list(activity: activity, detail: detail(elevationGain: nil),
                                       age: 50, isMale: true)
        XCTAssertNil(items.first { $0.kind == .elevation },
                     "경로가 없으면 고도 데이터 자체가 없다 — 0으로 꾸며내면 안 된다")
    }

    /// 트랙 한 바퀴처럼 오르내림이 없는 고도열은 0이 나온다
    func testTrackAltitudesGiveZeroGain() {
        var track: [Double] = []
        for i in 0..<1200 { track.append(12 + (i % 3 == 0 ? 0.8 : -0.4)) }
        XCTAssertEqual(ElevationGain.cumulative(track), 0, accuracy: 0.01)
    }
}
