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
    static let cadence      = Color(hex: "5CE5D5") // 케이던스 (Apple Fitness 틸 계열)
    static let strideLength  = Color(hex: "38BDF8") // 보폭 — 스카이블루
    static let verticalOsc   = Color(hex: "C084FC") // 수직진폭 — 라벤더
    static let elevationFill = Color(hex: "B98A3A") // 고도 채움 — 갈색

    /// HR 존 색상 (Z1..Z5) — 지도 경로, HR 차트, 카드 렌더러가 공유하는 팔레트.
    static let hrZoneColors: [Color] = [
        Color(hex: "3B82F6"),  // Z1 Blue
        Color(hex: "5CE5D5"),  // Z2 Cyan
        Color(hex: "C6FF00"),  // Z3 Lime
        Color(hex: "FF9A1F"),  // Z4 Orange
        Color(hex: "FF2E6B"),  // Z5 Pink
    ]

    static func hrZoneColor(_ zoneID: Int) -> Color {
        hrZoneColors[min(max(zoneID - 1, 0), 4)]
    }
}

// MARK: - Chart-specific palette (RunCombinedChartView 전용)
extension Theme {
    static let chartPace     = Color(hex: "4DD0F5")  // 시안 (dark 기준)
    static let chartCadence  = Color(hex: "F0D840")  // 옐로
    static let chartPower    = Color(hex: "5AA9FF")  // 파랑
    static let chartElev     = Color(hex: "8FE04D")  // 라임 그린
    static let chartElevFill = Color(hex: "8FE04D")  // 고도 fill (chartElev 와 동일)
    static let chartStride   = Color(hex: "FFA84D")  // 주황
    static let chartVertOsc  = Color(hex: "D97FF0")  // 마젠타
    static let chartAerobic  = Color(hex: "40C0FF")  // 하늘색 (유산소 효율)

    static let chartHRZones: [Color] = [
        Color(hex: "3D9BFF"),  // Z1 블루
        Color(hex: "4DFFF0"),  // Z2 아쿠아
        Color(hex: "B4FF3D"),  // Z3 라임
        Color(hex: "FFB43D"),  // Z4 오렌지
        Color(hex: "FF5247"),  // Z5 레드
    ]
}

