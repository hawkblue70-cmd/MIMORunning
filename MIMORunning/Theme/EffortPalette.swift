import SwiftUI
import UIKit

/// Apple 피트니스 어휘의 4구간 (2차 소스 기준: Easy 1–3 · Moderate 4–6 · Hard 7–8 · All Out 9–10)
enum EffortBand: CaseIterable, Equatable, Hashable {
    case easy, moderate, hard, allOut

    init(value: Int) {
        switch value {
        case ...3:   self = .easy
        case 4...6:  self = .moderate
        case 7...8:  self = .hard
        default:     self = .allOut
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .easy:     1...3
        case .moderate: 4...6
        case .hard:     7...8
        case .allOut:   9...10
        }
    }

    var label: String {
        let L = AppLanguage.shared
        return switch self {
        case .easy:     L.s("쉬움", "Easy")
        case .moderate: L.s("보통", "Moderate")
        case .hard:     L.s("힘듦", "Hard")
        case .allOut:   L.s("전력", "All Out")
        }
    }
}

/// `Theme.hrZoneColors`(파랑→빨강 5색)를 10단계로 선형 보간. index 0 = 강도 1.
enum EffortPalette {
    struct RGBA { let r: CGFloat; let g: CGFloat; let b: CGFloat; let a: CGFloat }

    static let colors: [Color] = (1...10).map { color(for: $0) }

    static func color(for value: Int) -> Color {
        let stops = Theme.hrZoneColors.map { UIColor($0) }
        let v = min(10, max(1, value))
        let t = Double(v - 1) / 9.0 * Double(stops.count - 1)     // 0...4
        let i = min(stops.count - 2, Int(t))
        let f = t - Double(i)
        return Color(uiColor: blend(stops[i], stops[i + 1], f))
    }

    static func rgba(_ color: Color) -> RGBA {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: r, g: g, b: b, a: a)
    }

    private static func blend(_ a: UIColor, _ b: UIColor, _ f: Double) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(f)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: 1)
    }
}
