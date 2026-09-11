import XCTest
import CoreLocation
@testable import MIMORunning

/// 상세 화면 "러닝 상세 데이터" 격자와 "구간 러닝 데이터" 카드가 함께 쓰는 항목 목록.
final class RunMetricListTests: XCTestCase {

    private func fullDetail() -> ActivityDetail {
        ActivityDetail(
            routeCoordinates: [CLLocationCoordinate2D(latitude: 37.3, longitude: 126.8)],
            routeTimeOffsets: [0], elevationGain: 142,
            avgPower: 227, avgCadence: 178, splits: [], hrZones: [],
            intervalSegments: [], workoutType: .general,
            avgGroundContactTime: 238, avgStrideLength: 1.12,
            avgVerticalOscillation: 8.4, vo2Max: 45.3,
            altitudeProfile: [], altitudeTimeProfile: [], isIndoorWorkout: false)
    }

    private func fullActivity() -> Activity {
        Activity(id: UUID(), type: .running, date: Date(), duration: 3308, distance: 10_060,
                 calories: 451, avgHeartRate: 148)
    }

    func testFullDataProducesEveryItem() {
        let items = RunMetricItem.list(activity: fullActivity(), detail: fullDetail(),
                                       age: 45, isMale: true)
        XCTAssertEqual(items.count, 12, "데이터가 다 있으면 12개 항목이 모두 나와야 한다")
    }

    /// LazyVGrid가 셀을 버리지 않으려면 같은 입력에 같은 식별자가 나와야 한다.
    /// 예전에는 `let id = UUID()`라 목록을 다시 만들 때마다 전부 달라졌다.
    func testIDsAreStableAcrossRebuilds() {
        let act = fullActivity()
        let det = fullDetail()
        let first  = RunMetricItem.list(activity: act, detail: det, age: 45, isMale: true).map(\.id)
        let second = RunMetricItem.list(activity: act, detail: det, age: 45, isMale: true).map(\.id)
        XCTAssertEqual(first, second, "같은 데이터로 만든 목록의 식별자가 매번 달라지면 안 된다")
    }

    func testIDsAreUnique() {
        let items = RunMetricItem.list(activity: fullActivity(), detail: fullDetail(),
                                       age: 45, isMale: true)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "식별자가 겹치면 셀이 하나로 합쳐진다")
    }

    func testMissingDetailDropsOnlyDetailItems() {
        let items = RunMetricItem.list(activity: fullActivity(), detail: nil, age: 45, isMale: true)
        // 거리·시간·페이스·심박·칼로리는 활동에서 오므로 상세가 없어도 남는다
        XCTAssertEqual(items.count, 5)
    }
}
