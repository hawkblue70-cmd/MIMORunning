import XCTest
import SwiftUI
@testable import MIMORunning

/// "가로 3열" 스탬프가 카드 안에 한 줄로 들어가는지 실제 렌더로 검증한다.
///
/// 회귀 대상: StampCard의 `.fixedSize()` 아래에서 SwiftUI가 이 뷰의 이상적 폭을 실제보다
/// 좁게 잡아 거리("10.0")가 "10." / "0"으로 줄바꿈되고, 늘어난 높이만큼 푸터(심박·칼로리)가
/// 카드 아래로 밀려 잘렸다. 각 Text에 lineLimit(1) + fixedSize()로 고정해 해결.
final class StampInlineTripleLayoutTests: XCTestCase {

    private static let cardW: CGFloat = 300
    private static let cardH: CGFloat = 375
    private static let bottomPadding: CGFloat = 12   // StampCard의 스탬프 하단 여백
    private static let renderScale: CGFloat = 2

    @MainActor
    func testInlineTripleFitsInsideCardAtEverySize() throws {
        var data = StampData(distance: "10.0", distanceUnit: "KM", pace: "5'29\"", time: "55:08",
                             heartRate: "152", calories: "634",
                             dateText: "2026. 9. 10", locationText: "KR", weekday: "THU")
        data.date = Date()

        for level in [TextSizeLevel.small, .medium, .large, .xlarge] {
            let view = ZStack(alignment: .top) {
                Color(hex: "3A4038")
                StampCard(data: data, template: .inlineTriple, colorMode: .auto,
                          position: .bottomLeading, sizeLevel: level, isBrightBackground: false,
                          showHeartRate: true, showCalories: true, showTextOutline: true,
                          wordmarkTopInset: 42, renderOnlyStamp: true)
            }
            .frame(width: Self.cardW, height: Self.cardH)

            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = .init(width: Self.cardW, height: Self.cardH)
            renderer.scale = Self.renderScale
            _ = renderer.uiImage   // ImageRenderer 워밍업 (첫 렌더는 레이아웃 미정착)
            _ = renderer.uiImage
            let img = try XCTUnwrap(renderer.uiImage)

            let bottom = try XCTUnwrap(bottomInkY(in: img), "\(level) — 스탬프가 렌더되지 않았다")
            let limit = (Self.cardH - Self.bottomPadding + 1) * Self.renderScale
            XCTAssertLessThanOrEqual(
                bottom, limit,
                "\(level): 스탬프 잉크가 하단 여백(\(Self.bottomPadding)pt) 밖까지 내려갔다 — 줄바꿈으로 푸터가 밀려난 상태"
            )
        }
    }

    /// 배경보다 밝은 픽셀이 있는 가장 아래 y 좌표(픽셀).
    @MainActor
    private func bottomInkY(in image: UIImage) -> CGFloat? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        for y in stride(from: h - 1, through: 0, by: -1) {
            var bright = 0
            for x in 0..<w {
                let i = (y * w + x) * 4
                let lum = 0.299 * Double(px[i]) + 0.587 * Double(px[i+1]) + 0.114 * Double(px[i+2])
                if lum > 140 { bright += 1 }
            }
            if bright > 2 { return CGFloat(y) }
        }
        return nil
    }
}
