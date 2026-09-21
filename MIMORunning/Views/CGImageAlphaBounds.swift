import CoreGraphics
import Foundation

extension CGImage {
    /// 알파가 있는 픽셀들의 경계 상자 — **UIKit 좌표(y=0 위)**, 픽셀 단위. 전부 투명이면 nil.
    /// 경로 영상 출력이 "줄만 그린" 오버레이에서 회차 보드의 줄 영역을 찾는 데 쓴다(레이아웃 좌표를 SwiftUI에서 꺼내지 않고).
    func alphaBoundingBox(threshold: UInt8 = 8) -> CGRect? {
        let w = width, h = height
        guard w > 0, h > 0 else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { return nil }
        let data = raw.assumingMemoryBound(to: UInt8.self)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let rowBase = y * w * 4
            for x in 0..<w where data[rowBase + x * 4 + 3] > threshold {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        // CGContext.draw는 y=0이 아래 — UIKit 좌표로 뒤집는다
        let topY = h - 1 - maxY
        return CGRect(x: minX, y: topY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
