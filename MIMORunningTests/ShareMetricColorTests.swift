import XCTest
import SwiftUI
@testable import MIMORunning

/// 공유 카드 지표 색 — 구간 카드와 경로 카드가 같은 값을 쓰는지, 라이트 배경에서 읽히는지.
///
/// 예전에는 두 카드가 각자 색을 정해 같은 러닝의 케이던스가 한쪽은 검정, 한쪽은 노랑이었고,
/// 경로 카드는 라이트 배경인데 다크용 노랑·라임을 그대로 써서 흰 바탕에 거의 안 보였다.
final class ShareMetricColorTests: XCTestCase {

    private let allKinds: [RunMetricKind] = [
        .distance, .time, .pace, .heartRate, .cadence, .power, .form, .cardio, .calories, .elevation
    ]

    private func rgb(_ c: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    /// WCAG 상대 휘도
    private func luminance(_ c: Color) -> CGFloat {
        let (r, g, b) = rgb(c)
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private func contrast(_ a: Color, _ b: Color) -> CGFloat {
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// 라이트 카드 배경은 흰색에 가깝다. 작은 라벨이라 3:1은 넘어야 읽힌다.
    func testLightColorsAreReadableOnWhite() {
        let white = Color.white
        for kind in allKinds {
            let c = kind.shareColor(isLight: true, textPrimary: Color(hex: "111111"))
            XCTAssertGreaterThanOrEqual(contrast(c, white), 3.0,
                "\(kind) 라이트 색이 흰 배경에서 대비 부족 (\(String(format: "%.2f", contrast(c, white))):1)")
        }
    }

    /// 다크 카드 배경 위에서도 같은 기준.
    func testDarkColorsAreReadableOnDarkCard() {
        let bg = Theme.cardBackground
        for kind in allKinds {
            let c = kind.shareColor(isLight: false, textPrimary: .white)
            XCTAssertGreaterThanOrEqual(contrast(c, bg), 3.0,
                "\(kind) 다크 색이 카드 배경에서 대비 부족 (\(String(format: "%.2f", contrast(c, bg))):1)")
        }
    }

    /// 같은 카드에 함께 뜨는 지표끼리 색이 같으면 안 된다 — 거리(무채색)는 제외.
    func testNoTwoKindsShareTheSameColor() {
        for isLight in [true, false] {
            var seen: [String: RunMetricKind] = [:]
            for kind in allKinds where kind != .distance {
                let c = kind.shareColor(isLight: isLight, textPrimary: isLight ? Color(hex: "111111") : .white)
                let (r, g, b) = rgb(c)
                let key = String(format: "%.3f-%.3f-%.3f", r, g, b)
                if let dup = seen[key] {
                    XCTFail("\(isLight ? "라이트" : "다크"): \(kind) 와 \(dup) 의 색이 같다")
                }
                seen[key] = kind
            }
        }
    }
}
