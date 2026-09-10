import XCTest
@testable import MIMORunning

/// 지도 km 마커 간격 — 촘촘해지면 2km·3km로 넓어지는지 검증.
final class MapMarkerStepTests: XCTestCase {

    func testShortRunsMarkEveryKilometer() {
        XCTAssertEqual(mapMarkerStepKm(totalMeters: 5_000), 1)
        XCTAssertEqual(mapMarkerStepKm(totalMeters: 10_000), 1, "10km까지는 1km마다 = 마커 10개")
    }

    func testCrowdedDistancesWiden() {
        XCTAssertEqual(mapMarkerStepKm(totalMeters: 12_000), 2, "1km면 12개라 촘촘 → 2km")
        XCTAssertEqual(mapMarkerStepKm(totalMeters: 20_000), 2, "2km면 10개 — 아직 2km 유지")
        XCTAssertEqual(mapMarkerStepKm(totalMeters: 21_097), 3, "하프는 2km면 10개를 넘어 3km")
        XCTAssertEqual(mapMarkerStepKm(totalMeters: 30_000), 3)
    }

    func testVeryLongRunsWidenFurther() {
        XCTAssertEqual(mapMarkerStepKm(totalMeters: 42_195), 5, "풀코스는 3km면 14개라 5km")
        XCTAssertEqual(mapMarkerStepKm(totalMeters: 100_000), 10)
        XCTAssertEqual(mapMarkerStepKm(totalMeters: 250_000), 10, "그 이상도 10km에서 멈춘다")
    }

    /// 어떤 거리에서도 마커가 10개를 크게 넘지 않는다 (10km 간격 상한에 걸리는 초장거리 제외)
    func testMarkerCountStaysReadable() {
        for km in stride(from: 1.0, through: 100.0, by: 0.5) {
            let step = mapMarkerStepKm(totalMeters: km * 1000)
            XCTAssertLessThanOrEqual(Int(km / step), 10, "\(km)km에서 마커가 너무 많다 (간격 \(step)km)")
        }
    }
}
