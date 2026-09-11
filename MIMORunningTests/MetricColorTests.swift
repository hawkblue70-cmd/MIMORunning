import XCTest
import SwiftUI
@testable import MIMORunning

/// 지표 의미색이 서로, 그리고 심박 존 색과 겹치지 않는지.
///
/// 예전에는 케이던스가 `5CE5D5`로 **심박 존 2와 같은 색**이었고, 지면접촉 `A78BFA`가
/// 종합 차트의 파워선과 **같은 값**이었다. 한 화면에서 같은 색이 다른 뜻이 되면 안 된다.
final class MetricColorTests: XCTestCase {

    private func rgb(_ c: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f-%.3f-%.3f", r, g, b)
    }

    /// 같은 카드/화면에 함께 나오는 색들 — 값이 같으면 안 된다.
    func testNoMetricColorCollidesWithAnother() {
        let named: [(String, Color)] = [
            ("케이던스", Theme.cadence), ("보폭", Theme.strideLength),
            ("지면접촉", Theme.groundContact), ("수직진폭", Theme.verticalOsc),
            ("파워", Theme.chartPower), ("페이스", Theme.chartPace), ("고도", Theme.chartElev),
        ]
        var seen: [String: String] = [:]
        for (name, color) in named {
            let key = rgb(color)
            if let dup = seen[key] { XCTFail("\(name) 와 \(dup) 의 색 값이 같다") }
            seen[key] = name
        }
    }

    /// 지표 의미색이 심박 존 다섯 색과 같으면 안 된다 — 존 색은 강도를 뜻한다.
    func testMetricColorsDoNotReuseHRZoneColors() {
        let zoneKeys = Set(Theme.hrZoneColors.map(rgb))
        let named: [(String, Color)] = [
            ("케이던스", Theme.cadence), ("보폭", Theme.strideLength),
            ("수직진폭", Theme.verticalOsc), ("파워", Theme.chartPower),
        ]
        for (name, color) in named {
            XCTAssertFalse(zoneKeys.contains(rgb(color)), "\(name) 이 심박 존 색과 같다")
        }
    }

    /// 케이던스는 앱 어디서나 한 색이어야 한다.
    func testCadenceHasOneColor() {
        XCTAssertEqual(rgb(Theme.cadence), rgb(Theme.chartCadence),
                       "지표 그리드와 종합 차트의 케이던스 색이 다르다")
    }
}
