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
}

