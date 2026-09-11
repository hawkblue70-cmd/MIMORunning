import XCTest
import UIKit
@testable import MIMORunning

/// km 라벨을 진행 방향 오른쪽에 놓는 계산.
/// 왕복 코스에서 갈 때와 올 때 라벨이 경로 양쪽으로 갈라지는지가 핵심.
final class KmLabelPlacementTests: XCTestCase {

    private let label = CGSize(width: 40, height: 12)
    private let gap: CGFloat = 3
    private let origin = CGPoint(x: 100, y: 100)

    func testEastwardPutsLabelBelow() {
        // 화면 오른쪽(동쪽)으로 달리면 진행 방향 오른쪽 = 화면 아래
        let c = kmLabelCenter(at: origin, direction: CGVector(dx: 1, dy: 0),
                              labelSize: label, gap: gap)
        XCTAssertEqual(c.x, origin.x, accuracy: 0.01)
        XCTAssertEqual(c.y, origin.y + label.height / 2 + gap, accuracy: 0.01)
    }

    func testWestwardPutsLabelAbove() {
        let c = kmLabelCenter(at: origin, direction: CGVector(dx: -1, dy: 0),
                              labelSize: label, gap: gap)
        XCTAssertEqual(c.x, origin.x, accuracy: 0.01)
        XCTAssertEqual(c.y, origin.y - label.height / 2 - gap, accuracy: 0.01)
    }

    func testNorthwardPutsLabelRight() {
        // 화면 위(북쪽)로 달리면 오른쪽 = 화면 오른쪽. 가로로 긴 라벨이라 폭 절반만큼 밀린다
        let c = kmLabelCenter(at: origin, direction: CGVector(dx: 0, dy: -1),
                              labelSize: label, gap: gap)
        XCTAssertEqual(c.x, origin.x + label.width / 2 + gap, accuracy: 0.01)
        XCTAssertEqual(c.y, origin.y, accuracy: 0.01)
    }

    /// 왕복 구간 — 같은 지점을 반대 방향으로 지나면 라벨이 경로 반대편에 놓여 겹치지 않는다
    func testOutAndBackLabelsDoNotOverlap() {
        let out  = kmLabelCenter(at: origin, direction: CGVector(dx: 1, dy: 0),
                                 labelSize: label, gap: gap)
        let back = kmLabelCenter(at: origin, direction: CGVector(dx: -1, dy: 0),
                                 labelSize: label, gap: gap)
        let outRect  = CGRect(x: out.x - label.width / 2,  y: out.y - label.height / 2,
                              width: label.width, height: label.height)
        let backRect = CGRect(x: back.x - label.width / 2, y: back.y - label.height / 2,
                              width: label.width, height: label.height)
        XCTAssertFalse(outRect.intersects(backRect), "왕복 라벨이 겹치면 배치 규칙이 무의미하다")
        XCTAssertGreaterThan(out.y, back.y, "갈 때는 아래, 올 때는 위")
    }

    func testDiagonalStaysOnRightSide() {
        // 오른쪽 아래로 달리면 오른쪽 법선은 왼쪽 아래를 향한다
        let c = kmLabelCenter(at: origin, direction: CGVector(dx: 1, dy: 1),
                              labelSize: label, gap: gap)
        XCTAssertLessThan(c.x, origin.x, "진행 방향 오른쪽이면 x는 줄어든다")
        XCTAssertGreaterThan(c.y, origin.y)
    }

    /// 왕복 경로를 실제 배치대로 그려 눈으로 확인할 수 있게 저장
    @MainActor
    func testExportOutAndBackSample() throws {
        let size = CGSize(width: 420, height: 150)
        let outY: CGFloat = 72, backY: CGFloat = 78     // 같은 길을 되돌아오는 상황
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(red: 0.14, green: 0.15, blue: 0.16, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

            // 경로 — 오른쪽으로 갔다가(위 선) 왼쪽으로 돌아옴(아래 선)
            let violet = UIColor(red: 0x7C / 255.0, green: 0x5C / 255.0, blue: 0xFC / 255.0, alpha: 1)
            violet.setStroke()
            for y in [outY, backY] {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 30, y: y))
                path.addLine(to: CGPoint(x: 390, y: y))
                path.lineWidth = 1.5
                path.stroke()
            }

            let screenScale: CGFloat = 3
            func place(km: Int, x: CGFloat, y: CGFloat, dir: CGVector) {
                guard let cg = makeKmMarkerLabelImage(km: km, renderScale: 0.65 * screenScale,
                                                      style: .light) else { return }
                let ui = UIImage(cgImage: cg, scale: screenScale, orientation: .up)
                let c = kmLabelCenter(at: CGPoint(x: x, y: y), direction: dir,
                                      labelSize: ui.size, gap: 3)
                ui.draw(in: CGRect(x: c.x - ui.size.width / 2, y: c.y - ui.size.height / 2,
                                   width: ui.size.width, height: ui.size.height))
            }
            // 갈 때(동쪽) 1·2·3km — 라벨이 경로 아래로
            for (i, x) in [90.0, 190.0, 290.0].enumerated() {
                place(km: i + 1, x: x, y: outY, dir: CGVector(dx: 1, dy: 0))
            }
            // 올 때(서쪽) 4·5·6km — 라벨이 경로 위로
            for (i, x) in [290.0, 190.0, 90.0].enumerated() {
                place(km: i + 4, x: x, y: backY, dir: CGVector(dx: -1, dy: 0))
            }
        }
        try XCTUnwrap(img.pngData()).write(to: URL(fileURLWithPath: "/tmp/km_outback_sample.png"))
    }

    func testZeroDirectionFallsBackBelow() {
        let c = kmLabelCenter(at: origin, direction: CGVector(dx: 0, dy: 0),
                              labelSize: label, gap: gap)
        XCTAssertEqual(c.y, origin.y + label.height / 2 + gap, accuracy: 0.01)
    }
}
