import SwiftUI

extension Color {
    // 잉크 3단계 — 다크 카드 위 텍스트 명도 표준 (0.45 하한)
    static let mrInk1 = Color.white                     // 값·제목
    static let mrInk2 = Color.white.opacity(0.72)       // 본문
    static let mrInk3 = Color.white.opacity(0.45)       // 라벨·각주 (하한)

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
    // 시간은 노랑 계열이되 케이던스 노랑(FFE000)과 벌려 둔다 — 시스템 옐로는 색상환에서 5° 차이라
    // 지표 격자에서 두 라벨이 같은 색으로 보였다. 앰버 쪽으로 한 칸 내린다.
    static let time = Color(hex: "FFB020")
    static let pace = Color.cyan
    static let heartRate = Color.red
    static let elevation = Color.green
    static let power = Color(hex: "A3E635")   // lime
    static let calories = Color.pink
    static let runningForm = Color.teal      // 러닝 다이내믹스 3종 (민트/청록 계열)
    // ⚠ 케이던스는 예전에 5CE5D5(청록)였는데 그 값이 심박 존 2 색이기도 해서 뜻이 겹쳤다.
    //   종합 차트의 케이던스 선과 같은 노랑으로 통일한다. 비워진 청록은 지면접촉이 받는다.
    //   지면접촉의 보라(A78BFA)는 종합 차트의 파워선과 같은 값이라 한 화면에서 충돌했다.
    static let cadence       = Color(hex: "FFE000") // 케이던스 — 노랑
    static let strideLength  = Color(hex: "FFA94D") // 보폭 — 주황
    static let groundContact = Color(hex: "5CE5D5") // 지면접촉 — 청록
    static let verticalOsc   = Color(hex: "A9B6C4") // 수직진폭 — 밝은 한색 회색
    static let elevationFill = Color(hex: "B98A3A") // 고도 채움 — 갈색

    /// "좋음 · 개선" 초록. 지표가 아니라 **판정**을 뜻한다 — 범위 안에 들었다, 나아졌다, 높다.
    /// ⚠ 예전에는 7FD98A와 5CE08A 두 값이 같은 뜻으로 43곳에 섞여 있었다.
    ///   고도·이지런의 초록(`elevation`, 34C759)과는 뜻이 달라 따로 둔다.
    static let positive = Color(hex: "5CE08A")

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

// MARK: - 작은 선차트의 점 (폼 카드 미니 차트 · 성장 탭 스파크라인 공용)
extension Theme {
    /// 선 위의 데이터 점. 두 차트가 같은 값을 써야 한다 — 예전에는 성장 탭이 속 빈 원 28,
    /// 폼 카드가 채운 점 12(45%)로 달라 같은 지표가 화면마다 다르게 보였다.
    static let sparkDotSize: CGFloat = 12
    static let sparkDotOpacity: Double = 0.45
    /// 강조 점 — 흰 테두리(halo) 위에 선 색 속. 폼 카드는 평소 범위를 벗어난 구간에 쓰고,
    /// 성장 탭 스파크라인은 모든 점을 이 모양으로 그린다.
    static let sparkHaloSize: CGFloat = 64
    static let sparkHaloCoreSize: CGFloat = 32
    /// 성장 탭 스파크라인용 — 같은 모양이되 지름 2/3. 높이 36pt에 점이 최대 14개라 64는 붙어 보였다.
    /// symbolSize는 넓이(pt²)라 지름 2/3 = 넓이 4/9: 64 → 28, 32 → 14.
    static let sparkHaloSizeCompact: CGFloat = 28
    static let sparkHaloCoreSizeCompact: CGFloat = 14
}

// MARK: - Chart-specific palette (RunCombinedChartView 전용)
extension Theme {
    // ⚠ 종합 차트 레이어 색 규칙 — 검은 배경에서 선끼리 색상환이 겹치지 않게.
    //   심박은 존 색(파랑·청록·라임·주황·핑크)을 쓰므로 다른 선은 그 다섯과 멀어야 한다.
    //   예전 값: 파워 하늘파랑(=페이스·Z1과 충돌) · 보폭 코랄(=심박과 충돌) · 고도 라임(=Z3·케이던스와 충돌).
    static let chartPace     = Color(hex: "00D8FF")  // 전기 시안 (막대)
    static let chartCadence  = Theme.cadence         // 순수 옐로 — 지표 의미색과 같은 값
    // 선은 전부 형광 톤 — 검은 배경에서 라벤더(A78BFA)·시스템 초록(34C759)만 한 단계 어두워
    //   심박(존 색)·케이던스(순노랑)·진폭(마젠타) 옆에서 가라앉아 보였다.
    static let chartPower    = Color(hex: "C77DFF")  // 형광 바이올렛 (브랜드 계열)
    static let chartElev     = Color(hex: "00E676")  // 형광 스프링 그린 (라임 아님 — Z3·케이던스와 분리)
    static let chartElevFill = Color(hex: "00E676")  // 고도 fill
    static let chartStride   = Color(hex: "F2F2F7")  // 화이트 (검은 배경에서 가장 뚜렷)
    // 지면접촉은 지표 의미색이 청록(5CE5D5)이지만 차트에서는 못 쓴다 — 심박 선이 Z2에서 아쿠아(4DFFF0)라
    //   이지런 대부분 구간에서 두 선이 같은 색이 된다. 존 다섯·노랑·바이올렛·마젠타·초록 사이 빈 자리인
    //   페리윙클(파랑 211°와 바이올렛 285° 사이)을 쓴다.
    static let chartGroundContact = Color(hex: "7B87FF")
    static let chartVertOsc  = Color(hex: "F050FF")  // 형광 마젠타
    static let chartAerobic  = Color(hex: "AEB2BC")  // 값 전용 타일 — 선을 그리지 않으므로 중립 회색(밝게)
    static let chartValueOnly = Color(hex: "AEB2BC") // 값 전용 타일 공통 (유산소·칼로리)

    static let chartHRZones: [Color] = [
        Color(hex: "3D9BFF"),  // Z1 블루
        Color(hex: "4DFFF0"),  // Z2 아쿠아
        Color(hex: "B4FF3D"),  // Z3 라임
        Color(hex: "FFB43D"),  // Z4 오렌지
        Color(hex: "FF5247"),  // Z5 레드
    ]
}

