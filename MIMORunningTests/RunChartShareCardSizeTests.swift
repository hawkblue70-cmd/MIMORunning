import XCTest
import SwiftUI
@testable import MIMORunning

/// 종합 차트 공유 카드는 다크·라이트가 **같은 크기**로 내보내져야 한다.
///
/// 예전에는 헤더가 테마마다 다른 레이아웃이라(라이트만 3행) 라이트가 43pt 길었다(369 vs 326).
/// 같은 카드가 테마에 따라 크기가 달라지면 안 된다 — §5.8.
@MainActor
final class RunChartShareCardSizeTests: XCTestCase {

    private func sampleData() -> RunChartData {
        let totalKm = 6.07, n = 80
        func mk(_ layer: RunChartLayer, _ base: Double, _ amp: Double,
                _ lo: Double, _ hi: Double, _ avg: Double) -> RunChartSeries {
            let pts: [RunChartPoint] = (0..<n).map { i in
                let norm = 0.5 + 0.3 * sin(Double(i) / 9)
                return RunChartPoint(km: Double(i) / Double(n - 1) * totalKm, value: base + norm * amp, norm: norm)
            }
            return RunChartSeries(layer: layer, points: pts, minValue: lo, maxValue: hi, avgValue: avg, lastValue: avg)
        }
        return RunChartData(
            totalKm: totalKm,
            series: [.heartRate: mk(.heartRate, 120, 30, 127, 138, 134),
                     .cadence:   mk(.cadence, 160, 20, 154, 178, 169),
                     .power:     mk(.power, 180, 40, 176, 210, 195)],
            hrZoneBands: [(zone: 2, lowerBPM: 120, upperBPM: 140), (zone: 3, lowerBPM: 140, upperBPM: 160)],
            hrMin: 110, hrMax: 178,
            availableLayers: [.heartRate, .cadence, .power])
    }

    private func render(_ palette: ShareChartPalette) throws -> CGSize {
        let card = RunChartShareCard(
            data: sampleData(), enabledLayers: [.heartRate, .cadence, .power],
            distanceText: "6.07 km", durationText: "39:41",
            weatherText: "25°C", weatherIcon: "cloud.sun.fill",
            dateText: "2026. 9. 11", weekdayText: "금", startTimeText: "오후 5:02",
            shoeText: "아디제로보스턴12", paceText: "6'32\"", palette: palette)
        let r = ImageRenderer(content: card)
        r.scale = 2
        _ = r.uiImage   // ImageRenderer 워밍업
        return try XCTUnwrap(r.uiImage).size
    }

    func testLightAndDarkExportSameSize() throws {
        let light = try render(.light)
        let dark  = try render(.dark)
        XCTAssertEqual(light.width,  dark.width,  "다크·라이트 내보내기 폭이 다르다")
        XCTAssertEqual(light.height, dark.height, "다크·라이트 내보내기 높이가 다르다 — 헤더 레이아웃이 갈라졌다")
    }
}
