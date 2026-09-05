import XCTest
import CoreLocation
@testable import MIMORunning

/// 스탬프 자연 폭 측정 — 콘솔의 "[StampMeasure]" 줄을 StampTemplate.naturalWidth 상수표에 옮긴다.
final class StampMeasureTests: XCTestCase {
    @MainActor
    func testMeasureNaturalWidths() {
        let wide = StampData(
            distance: "10.06", distanceUnit: "KM", pace: "6'43\"", time: "1:07:35",
            heartRate: "148", calories: "451", dateText: "SEP 04", locationText: "ANSAN · KR", weekday: "FRI",
            heartRateMax: "172", hrZoneLabel: "Z4", hrZoneIndex: 3, hrZoneName: "THRESHOLD",
            cadence: "182", elevGain: "142",
            elevSeries: StampData.sample.elevSeries, hrSeries: StampData.sample.hrSeries,
            placeName: "ANSAN", placeRegion: "GYEONGGI", coordText: "37.32°N 126.83°E",
            routeCoordinates: StampData.sample.routeCoordinates
        )
        var out = ""
        for t in StampTemplate.allCases {
            let s = StampCard.measureNaturalSize(template: t, data: wide)
            out += String(format: "%@ %.1f x %.1f\n", t.rawValue, s.width, s.height)
        }
        print(out)
    }
}
