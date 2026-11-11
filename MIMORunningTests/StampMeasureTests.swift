import XCTest
import CoreLocation
@testable import MIMORunning

/// 스탬프 자연 폭 측정 — 콘솔의 "[StampMeasure]" 줄을 StampTemplate.naturalWidth 상수표에 옮긴다.
final class StampMeasureTests: XCTestCase {
    @MainActor
    func testMeasureNaturalWidths() {
        var wide = StampData(
            distance: "10.06", distanceUnit: "KM", pace: "6'43\"", time: "1:07:35",
            heartRate: "148", calories: "451", dateText: "SEP 04", locationText: "ANSAN · KR", weekday: "FRI",
            heartRateMax: "172", hrZoneLabel: "Z4", hrZoneIndex: 3, hrZoneName: "THRESHOLD",
            cadence: "182", elevGain: "142",
            elevSeries: StampData.sample.elevSeries, hrSeries: StampData.sample.hrSeries,
            placeName: "ANSAN", placeRegion: "GYEONGGI", coordText: "37.32°N 126.83°E",
            routeCoordinates: StampData.sample.routeCoordinates
        )
        // 밸런스 스탬프 2종 — BalanceSnapshotTests.base()와 같은 입력 + 케이던스↓·접지↑(빨간 점·저울 기울기가 보이게)
        func stat(_ median: Double, _ sd: Double) -> FormStat {
            FormStat(median: median, sd: sd, count: 30, p10: nil, p90: nil)
        }
        wide.balance = BalanceSnapshot.make(BalanceSnapshot.Input(
            workoutType: .easy, paceSecPerKm: 360, hasForm: true, isReferenceBand: false,
            heartRate: 150, heartRateStat: stat(150, 5),
            cadence: 166, cadenceStat: stat(172, 3),
            stride: 1.0, strideStat: stat(1.0, 0.03),
            groundContact: 270, groundContactStat: stat(250, 8),
            verticalOsc: 8.0, verticalOscStat: stat(8.0, 0.4),
            effort: 5, effortTypeMedian: 5,
            sleepHours: 7, usualSleepHours: 7, hrvLevel: .good, hrvDisplay: "좋음", load: .steady,
            vo2: 48, vo2SixMonths: [47, 49]))
        XCTAssertEqual(wide.balance?.mode, .full)
        var out = ""
        for t in StampTemplate.allCases {
            let s = StampCard.measureNaturalSize(template: t, data: wide)
            out += String(format: "%@ %.1f x %.1f\n", t.rawValue, s.width, s.height)
        }
        print(out)
    }
}
