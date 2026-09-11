import XCTest
import SwiftUI
@testable import MIMORunning

/// 러닝 유형 막대 색이 서로 구분되는지 — 색상환 거리로 검사한다.
///
/// 예전에는 9종이 네 덩어리로 뭉쳐 있었다. 템포/빌드업이 같은 금색, 이지런/일반이 같은 회색,
/// LSD/롱런이 같은 보라였고 대회는 롱런과 **완전히 같은 값**(둘 다 7C5CFC)이었다.
/// 색을 손볼 때 같은 일이 다시 생기지 않게 고정한다.
final class WorkoutTypeColorTests: XCTestCase {

    private func hsb(_ c: Color) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h * 360, s, b)
    }

    /// 두 색이 사람 눈에 갈리는가 — 색상이 충분히 벌어졌거나, 채도·명도 중 하나가 크게 다르면 통과.
    ///
    /// 기준값은 실제로 문제였던 쌍에서 잡았다. 못 갈리던 쌍은 색상 차가 8°(F5C542/FFD166),
    /// 12°(8B7FF0/7C5CFC), 0°(대회/롱런 동일)였고, 갈리는 쌍은 20°(주황/금색)였다.
    /// 그래서 색상 18°를 선으로 둔다. 색상이 같아도 채도나 명도가 크게 다르면 갈린다
    /// (롱런 보라 vs LSD 라벤더가 그 경우).
    private func distinguishable(_ a: Color, _ b: Color) -> Bool {
        let x = hsb(a), y = hsb(b)
        var dh = abs(x.h - y.h)
        if dh > 180 { dh = 360 - dh }
        // 무채색끼리는 색상이 의미 없으므로 명도로만 본다
        if x.s < 0.12 && y.s < 0.12 { return abs(x.b - y.b) >= 0.18 }
        if dh >= 18 { return true }
        return abs(x.s - y.s) >= 0.30 || abs(x.b - y.b) >= 0.25
    }

    func testEveryTypePairIsDistinguishable() {
        let types = WorkoutType.allCases
        let colors = types.map { (type: $0, color: WorkoutTypeColor.color(for: $0)) }
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                XCTAssertTrue(distinguishable(colors[i].color, colors[j].color),
                    "\(colors[i].type) 와 \(colors[j].type) 의 색이 구분되지 않는다")
            }
        }
    }

    func testNoTwoTypesShareTheExactColor() {
        var seen: [String: WorkoutType] = [:]
        for t in WorkoutType.allCases {
            let c = UIColor(WorkoutTypeColor.color(for: t))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            let key = String(format: "%.3f-%.3f-%.3f", r, g, b)
            if let dup = seen[key] { XCTFail("\(t) 와 \(dup) 의 색 값이 같다") }
            seen[key] = t
        }
    }
}
