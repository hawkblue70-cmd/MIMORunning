import XCTest
import UIKit
@testable import MIMORunning

/// km 마커 라벨 — 경로 영상과 지도 스냅샷이 공용으로 쓰는 이미지.
final class KmMarkerLabelTests: XCTestCase {

    @MainActor
    func testLabelRendersAtRequestedScale() throws {
        let one = try XCTUnwrap(makeKmMarkerLabelImage(km: 3, renderScale: 1))
        // 12pt bold "3km" + 좌우 패딩 5 → 대략 40×20pt 안쪽
        XCTAssertGreaterThan(one.width, 20)
        XCTAssertLessThan(one.width, 60)
        XCTAssertGreaterThan(one.height, 12)
        XCTAssertLessThan(one.height, 26)

        // renderScale은 영상용 확대 배율 — 3배면 각 변도 약 3배
        let three = try XCTUnwrap(makeKmMarkerLabelImage(km: 3, renderScale: 3))
        XCTAssertEqual(Double(three.width) / Double(one.width), 3, accuracy: 0.35)
        XCTAssertEqual(Double(three.height) / Double(one.height), 3, accuracy: 0.35)
    }

    @MainActor
    func testTwoDigitLabelIsWider() throws {
        let one  = try XCTUnwrap(makeKmMarkerLabelImage(km: 5, renderScale: 1))
        let two  = try XCTUnwrap(makeKmMarkerLabelImage(km: 40, renderScale: 1))
        XCTAssertGreaterThan(two.width, one.width, "두 자리 km는 라벨이 더 넓어야 한다")
        XCTAssertEqual(two.height, one.height, "높이는 같아야 지도에서 줄이 흔들리지 않는다")
    }

    /// 지도에 그릴 때 쓰는 크기로 실제 렌더해 눈으로 확인할 수 있게 저장
    @MainActor
    func testExportSampleStrip() throws {
        let size = CGSize(width: 300, height: 40)
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(red: 0.14, green: 0.15, blue: 0.16, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            var x: CGFloat = 12
            for km in [1, 2, 10, 40] {
                let dotR: CGFloat = 3.5
                let y: CGFloat = 20
                UIColor.white.withAlphaComponent(0.85).setFill()
                UIBezierPath(ovalIn: CGRect(x: x - dotR, y: y - dotR,
                                            width: dotR * 2, height: dotR * 2)).fill()
                if let label = makeKmMarkerLabelImage(km: km, renderScale: 1) {
                    let lw = CGFloat(label.width), lh = CGFloat(label.height)
                    UIImage(cgImage: label, scale: 1, orientation: .up)
                        .draw(in: CGRect(x: x + dotR + 5, y: y - lh / 2, width: lw, height: lh))
                    x += dotR + 5 + lw + 14
                }
            }
            // 도착점 골드 마커 (경로 영상과 같은 치수)
            let gold = UIColor(red: 1.0, green: 0xC7 / 255.0, blue: 0x4D / 255.0, alpha: 1)
            let fx = x + 6, fy: CGFloat = 20
            gold.withAlphaComponent(0.40).setFill()
            UIBezierPath(ovalIn: CGRect(x: fx - 9, y: fy - 9, width: 18, height: 18)).fill()
            gold.setFill()
            UIBezierPath(ovalIn: CGRect(x: fx - 5, y: fy - 5, width: 10, height: 10)).fill()
        }
        try XCTUnwrap(img.pngData()).write(to: URL(fileURLWithPath: "/tmp/km_marker_sample.png"))
    }
}
