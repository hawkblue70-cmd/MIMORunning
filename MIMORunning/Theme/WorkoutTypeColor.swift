import SwiftUI

/// 러닝 유형 막대 색 — 한 곳에서만 정한다.
///
/// 계열은 의미를 따른다: 따뜻한 색 = 강한 훈련 · 차가운 색 = 길게 가는 훈련 ·
/// 무채색 = 유형을 모르는 러닝. 단, **계열 안에서도 확실히 벌린다** —
/// 예전에는 9종이 네 덩어리로 뭉쳐 템포/빌드업이 같은 금색, 이지런/일반이 같은 회색,
/// LSD/롱런이 같은 보라였고, 대회는 롱런과 색 값이 **완전히 같았다**(둘 다 7C5CFC).
///
/// `WorkoutTypeColorTests`가 모든 쌍이 눈으로 갈리는지 검사한다.
enum WorkoutTypeColor {
    static func color(for type: WorkoutType) -> Color {
        switch type {
        case .interval:    return Color(hex: "FF3B30")   // 빨강 — 가장 강함
        case .tempo:       return Color(hex: "FF9A3C")   // 주황
        case .buildUp:     return Color(hex: "FF2D92")   // 마젠타 — 대회 금색과 노랑이 겹쳐 옮겼다
        case .race:        return Color(hex: "FFD700")   // 금색 — 특별한 날
        case .distanceRun: return Color(hex: "5BB8FF")   // 하늘
        case .longRun:     return Color(hex: "7C5CFC")   // 보라
        case .lsd:         return Color(hex: "C4B5FD")   // 밝은 라벤더 — 롱런과 명도 차
        case .easy:        return Color(hex: "34C759")   // 초록 — 회복
        case .general:     return Color(hex: "8A8A92")   // 회색 — 유형 모름
        }
    }
}
