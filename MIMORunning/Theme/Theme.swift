import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

/// 프리뷰 카드 크기 — 스토리 카드(4:5)와 통일. 영상/슬라이드도 동일 크기로 표시.
/// 실제 export는 VideoExportService/PhotoSlideComposition에서 독립적으로 1080×1920 사용.
enum CardPreviewFrame {
    static let width:  CGFloat = OneLinerCard.cardWidth   // 300
    static let height: CGFloat = OneLinerCard.cardHeight  // 375
}

enum Theme {
    // Brand
    static let violet = Color(hex: "7C5CFC")
    static let background = Color(hex: "111111")
    static let cardBackground = Color(hex: "1C1C1E")

    // Metric meaning colors (Apple convention)
    static let time = Color.yellow
    static let pace = Color.cyan
    static let heartRate = Color.red
    static let elevation = Color.green
    static let power = Color(hex: "A3E635")   // lime
    static let calories = Color.pink
    static let runningForm = Color.teal      // 러닝 다이내믹스 3종 (민트/청록 계열)
    static let cadence = Color(hex: "5CE5D5") // 케이던스 (Apple Fitness 틸 계열)

    /// HR 존 색상 (Z1..Z5) — 지도 경로, HR 차트, 카드 렌더러가 공유하는 팔레트.
    static let hrZoneColors: [Color] = [
        Color(red: 0.30, green: 0.60, blue: 1.00),  // Z1 Blue
        Color(red: 0.20, green: 0.85, blue: 0.85),  // Z2 Cyan
        Color(red: 0.70, green: 1.00, blue: 0.10),  // Z3 Lime
        Color(red: 1.00, green: 0.60, blue: 0.15),  // Z4 Orange
        Color(red: 1.00, green: 0.30, blue: 0.55),  // Z5 Pink
    ]

    static func hrZoneColor(_ zoneID: Int) -> Color {
        hrZoneColors[min(max(zoneID - 1, 0), 4)]
    }
}

