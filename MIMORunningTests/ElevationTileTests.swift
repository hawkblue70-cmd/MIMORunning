import XCTest
@testable import MIMORunning

/// 종합 차트의 고도 타일 — 선은 해발(코스 모양), 숫자는 누적 상승.
/// 지표 그리드의 "고도 획득"과 같은 값을 가리켜야 한다.
final class ElevationTileTests: XCTestCase {

    func testElevationTileHidesAltitudeRange() {
        XCTAssertFalse(RunChartLayer.elevation.showsRange,
                       "타일 숫자가 누적 상승인데 해발 범위를 같이 두면 서로 다른 걸 가리킨다")
    }

    func testOtherLayersStillShowRange() {
        XCTAssertTrue(RunChartLayer.heartRate.showsRange)
        XCTAssertTrue(RunChartLayer.pace.showsRange)
        XCTAssertTrue(RunChartLayer.power.showsRange)
        XCTAssertFalse(RunChartLayer.calories.showsRange, "값 전용 타일은 원래 범위가 없다")
    }

    func testDisplayValuePrefersTileValue() {
        let points = [RunChartPoint(km: 0, value: 100, norm: 0.2), RunChartPoint(km: 1, value: 153, norm: 0.8)]
        let withTile = RunChartSeries(layer: .elevation, points: points,
                                      minValue: 100, maxValue: 153, avgValue: 124,
                                      lastValue: 130, tileValue: 132)
        XCTAssertEqual(withTile.displayValue, 132, "고도는 누적 상승을 보여야 한다")

        let withoutTile = RunChartSeries(layer: .heartRate, points: points,
                                         minValue: 120, maxValue: 160, avgValue: 152,
                                         lastValue: 150)
        XCTAssertEqual(withoutTile.displayValue, 152, "지정이 없으면 평균값")
    }

    func testWithAvgKeepsTileValue() {
        let points = [RunChartPoint(km: 0, value: 100, norm: 0.2), RunChartPoint(km: 1, value: 153, norm: 0.8)]
        let s = RunChartSeries(layer: .elevation, points: points,
                               minValue: 100, maxValue: 153, avgValue: 124,
                               lastValue: 130, tileValue: 132)
        XCTAssertEqual(s.withAvg(126).displayValue, 132,
                       "평균을 갈아끼워도 누적 상승은 유지돼야 한다")
    }

    func testLabelSaysGain() {
        XCTAssertTrue(RunChartLayer.elevation.shortLabel.contains("획득")
                      || RunChartLayer.elevation.shortLabel.lowercased().contains("gain"))
    }
}
