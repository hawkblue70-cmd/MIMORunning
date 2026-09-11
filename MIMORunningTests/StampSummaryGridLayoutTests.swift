import XCTest
import SwiftUI
@testable import MIMORunning

/// "요약 그리드" 스탬프가 가장 좁은 렌더 폭(211pt · 영상/슬라이드 논리 폭) 안에 들어가는지 실제 렌더로 검증한다.
///
/// 이 스탬프는 3열 고정 격자라 폭이 크기 배율표에 직접 매여 있다. 배율을 올리거나 열 폭·폰트를
/// 건드리면 조용히 카드 밖으로 삐져나가므로, 잉크의 실제 경계를 재서 여백 안에 있는지 본다.
/// (가로 3열 스탬프에서 겪은 줄바꿈 회귀와 같은 부류 — StampCard가 `.fixedSize()`로 감싼다.)
final class StampSummaryGridLayoutTests: XCTestCase {

    private static let cardW: CGFloat = 211
    private static let cardH: CGFloat = 375
    private static let renderScale: CGFloat = 2
    /// StampCard가 스탬프에 주는 좌우 여백 — 워드마크 잉크 왼쪽 선과 같은 기준
    private static var sideInset: CGFloat { 14 + MIMOWordmark.inkLeadingInset(size: 11) }
    private static let bottomPadding: CGFloat = 12

    @MainActor
    func testSummaryGridFitsInsideCardAtEverySize() throws {
        var data = StampData(distance: "10.06", distanceUnit: "KM", pace: "6'43\"", time: "1:07:35",
                             heartRate: "148", calories: "451",
                             dateText: "2026. 9. 11", locationText: "KR", weekday: "FRI",
                             cadence: "182", elevGain: "142")
        data.date = Date()

        for level in [TextSizeLevel.small, .medium, .large, .xlarge] {
            let view = ZStack(alignment: .top) {
                Color(hex: "3A4038")
                StampCard(data: data, template: .summaryGrid, colorMode: .auto,
                          position: .topLeading, sizeLevel: level, isBrightBackground: false,
                          showHeartRate: true, showCalories: true, showTextOutline: true,
                          renderOnlyStamp: true)
            }
            .frame(width: Self.cardW, height: Self.cardH)

            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = .init(width: Self.cardW, height: Self.cardH)
            renderer.scale = Self.renderScale
            _ = renderer.uiImage   // ImageRenderer 워밍업 (첫 렌더는 레이아웃 미정착)
            _ = renderer.uiImage
            let img = try XCTUnwrap(renderer.uiImage)

            let box = try XCTUnwrap(inkBounds(in: img), "\(level) — 스탬프가 렌더되지 않았다")
            let rightLimit  = (Self.cardW - Self.sideInset + 1) * Self.renderScale
            let bottomLimit = (Self.cardH - Self.bottomPadding + 1) * Self.renderScale
            XCTAssertLessThanOrEqual(box.maxX, rightLimit,
                "\(level): 격자가 오른쪽 여백 밖으로 나갔다 — 배율 또는 열 폭이 너무 크다")
            XCTAssertLessThanOrEqual(box.maxY, bottomLimit,
                "\(level): 스탬프가 아래 여백 밖으로 나갔다")
        }
    }

    /// 배경보다 밝은 픽셀들의 경계 상자(픽셀 좌표).
    @MainActor
    private func inkBounds(in image: UIImage) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let lum = 0.299 * Double(px[i]) + 0.587 * Double(px[i+1]) + 0.114 * Double(px[i+2])
                guard lum > 140 else { continue }
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
