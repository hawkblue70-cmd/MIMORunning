import XCTest
import CoreLocation
@testable import MIMORunning

/// 상세 데이터를 "완성"으로 보고 디스크에 저장할지 판단하는 규칙.
///
/// 야외 러닝인데 경로가 비어 있으면 완성이 아니다 — 예전에는 splits만 있어도 저장해 버려서,
/// HealthKit 경로 조회가 한 번 실패하면 지도·고도가 영구히 사라졌다.
final class DetailCompletenessTests: XCTestCase {

    private func detail(route: [CLLocationCoordinate2D], splits: Int, indoor: Bool,
                        hasMetrics: Bool = true) -> ActivityDetail {
        ActivityDetail(
            routeCoordinates: route, routeTimeOffsets: [], elevationGain: nil,
            avgPower: hasMetrics ? 227 : nil, avgCadence: hasMetrics ? 178 : nil,
            splits: (0..<splits).map {
                SplitData(id: $0 + 1, distanceM: 1000, duration: 330, avgHeartRate: 150,
                          avgCadence: 178, avgPower: 227, avgGroundContactTime: nil,
                          avgStrideLength: nil, avgVerticalOscillation: nil)
            },
            hrZones: [], intervalSegments: [], workoutType: .general,
            avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil,
            vo2Max: nil, altitudeProfile: [], altitudeTimeProfile: [],
            isIndoorWorkout: indoor)
    }

    private let coords = [CLLocationCoordinate2D(latitude: 37.3, longitude: 126.8),
                          CLLocationCoordinate2D(latitude: 37.31, longitude: 126.81)]

    func testOutdoorRunWithoutRouteIsIncomplete() {
        XCTAssertFalse(detail(route: [], splits: 10, indoor: false).isComplete,
                       "야외 러닝인데 경로가 없으면 아직 못 받아온 것 — 저장하면 안 된다")
    }

    func testOutdoorRunWithRouteIsComplete() {
        XCTAssertTrue(detail(route: coords, splits: 10, indoor: false).isComplete)
    }

    func testIndoorRunWithoutRouteIsComplete() {
        XCTAssertTrue(detail(route: [], splits: 10, indoor: true).isComplete,
                      "트레드밀은 경로가 없는 게 정상 — 매번 재조회하면 낭비다")
    }

    func testIndoorRunWithNothingIsIncomplete() {
        XCTAssertFalse(detail(route: [], splits: 0, indoor: true, hasMetrics: false).isComplete,
                       "실내라도 아무 데이터가 없으면 완성이 아니다")
    }
}
