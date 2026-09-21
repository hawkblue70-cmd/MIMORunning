import XCTest
import CoreGraphics
@testable import MIMORunning

final class CGImageAlphaBoundsTests: XCTestCase {
    private func image(size: CGSize, rect: CGRect?) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(origin: .zero, size: size))
        if let r = rect {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            // CGContext는 y=0이 아래 — 테스트는 UIKit 좌표(y=0 위)로 검사하므로 뒤집어 그린다
            ctx.fill(CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height))
        }
        return ctx.makeImage()!
    }

    func testFindsOpaqueRectInTopLeftCoordinates() throws {
        let img = image(size: CGSize(width: 100, height: 200), rect: CGRect(x: 30, y: 120, width: 40, height: 50))
        let box = try XCTUnwrap(img.alphaBoundingBox())
        XCTAssertEqual(box.minX, 30, accuracy: 1)
        XCTAssertEqual(box.minY, 120, accuracy: 1)
        XCTAssertEqual(box.width, 40, accuracy: 1)
        XCTAssertEqual(box.height, 50, accuracy: 1)
    }

    func testFullyTransparentReturnsNil() {
        XCTAssertNil(image(size: CGSize(width: 20, height: 20), rect: nil).alphaBoundingBox())
    }
}
