import XCTest
@testable import MIMORunning

/// 심박 차트 뒤 고도 배경을 언제 그리는지.
/// 평지 환산(5초/km 보정)과는 다른 축으로 판단하되, 평지 환산이 떴을 땐 근거로 반드시 그린다.
final class ElevationBackdropRuleTests: XCTestCase {

    func testHillyCourseDrawsBackdrop() {
        // 언덕 훈련 3.35km / 상승 132m = km당 39m
        XCTAssertTrue(shouldDrawElevationBackdrop(cumulativeGainM: 132, distanceKm: 3.35,
                                                  showsFlatEquivalent: false))
    }

    func testFlatCourseSkipsBackdrop() {
        // 10km / 상승 43m = km당 4.3m — GPS 노이즈와 구분되지 않는 수준
        XCTAssertFalse(shouldDrawElevationBackdrop(cumulativeGainM: 43, distanceKm: 10,
                                                   showsFlatEquivalent: false))
    }

    /// 기준 미달이어도 평지 환산이 떴다면 그린다 — 보정의 근거를 볼 수 있어야 한다
    func testFlatEquivalentForcesBackdrop() {
        XCTAssertTrue(shouldDrawElevationBackdrop(cumulativeGainM: 43, distanceKm: 10,
                                                  showsFlatEquivalent: true))
        XCTAssertTrue(shouldDrawElevationBackdrop(cumulativeGainM: 0, distanceKm: 10,
                                                  showsFlatEquivalent: true))
    }

    /// 비율만 보면 짧은 러닝이 쉽게 통과한다 — 절대값도 넘어야 한다
    func testShortRunNeedsAbsoluteGainToo() {
        // 1km / 15m = km당 15m (비율은 통과) 하지만 총 15m < 20m
        XCTAssertFalse(shouldDrawElevationBackdrop(cumulativeGainM: 15, distanceKm: 1,
                                                   showsFlatEquivalent: false))
        // 2km / 25m = km당 12.5m, 총 25m — 둘 다 통과
        XCTAssertTrue(shouldDrawElevationBackdrop(cumulativeGainM: 25, distanceKm: 2,
                                                  showsFlatEquivalent: false))
    }

    func testBoundaryIsInclusive() {
        // 정확히 km당 10m + 총 20m
        XCTAssertTrue(shouldDrawElevationBackdrop(cumulativeGainM: 20, distanceKm: 2,
                                                  showsFlatEquivalent: false))
        // 바로 아래
        XCTAssertFalse(shouldDrawElevationBackdrop(cumulativeGainM: 19.9, distanceKm: 2,
                                                   showsFlatEquivalent: false))
    }

    func testNoDistanceIsSafe() {
        XCTAssertFalse(shouldDrawElevationBackdrop(cumulativeGainM: 100, distanceKm: 0,
                                                   showsFlatEquivalent: false))
    }
}
