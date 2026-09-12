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
            ("지면접촉(차트)", Theme.chartGroundContact), ("진폭(차트)", Theme.chartVertOsc),
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

    /// "좋음" 초록은 하나만 쓴다 — 예전에는 7FD98A와 5CE08A가 같은 뜻으로 43곳에 섞여 있었다.
    func testPositiveGreenIsNotHardcodedAnywhere() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MIMORunning")
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return XCTFail("소스 폴더를 찾지 못했다")
        }
        var offenders: [String] = []
        var scanned = 0
        for case let url as URL in walker where url.pathExtension == "swift" {
            // Theme.swift가 유일한 정의처
            if url.lastPathComponent == "Theme.swift" { continue }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            scanned += 1
            if text.contains("7FD98A") || text.contains("5CE08A") {
                offenders.append(url.lastPathComponent)
            }
        }
        // 경로가 틀려 아무것도 안 읽고 통과하는 일이 없게
        XCTAssertGreaterThan(scanned, 50, "소스를 제대로 훑지 못했다 — 경로 확인 필요")
        XCTAssertTrue(offenders.isEmpty,
            "좋음 초록을 직접 박아 쓴 파일: \(offenders.joined(separator: ", ")) — Theme.positive를 쓸 것")
    }

    /// 판정 초록(좋음)과 지표 초록(고도)은 뜻이 달라 값도 달라야 한다.
    func testPositiveGreenDiffersFromElevationGreen() {
        XCTAssertNotEqual(rgb(Theme.positive), rgb(Theme.chartElev),
                          "좋음 초록과 고도 초록이 같은 값이면 뜻이 섞인다")
    }

    /// 시간과 케이던스는 둘 다 노랑 계열이라 색상이 붙기 쉽다 — 지표 격자에 나란히 뜬다.
    /// 예전에는 시스템 옐로(48°)와 FFE000(53°)로 5° 차이였다.
    func testTimeAndCadenceHuesAreApart() {
        func hue(_ c: Color) -> CGFloat {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(c).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return h * 360
        }
        var d = abs(hue(Theme.time) - hue(Theme.cadence))
        if d > 180 { d = 360 - d }
        XCTAssertGreaterThanOrEqual(d, 12,
            "시간과 케이던스 색상이 \(String(format: "%.1f", d))° 차이 — 격자에서 같은 노랑으로 보인다")
    }

    /// 케이던스는 앱 어디서나 한 색이어야 한다.
    func testCadenceHasOneColor() {
        XCTAssertEqual(rgb(Theme.cadence), rgb(Theme.chartCadence),
                       "지표 그리드와 종합 차트의 케이던스 색이 다르다")
    }
}
