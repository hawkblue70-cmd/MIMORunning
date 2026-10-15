import SwiftUI

/// 인사이트 카드(리듬·폼·퍼포먼스)의 촘촘한 세로 간격 — 내보내기(미리보기 = 출력) 경로에서만 켠다.
/// 글자 크기·차트 크기는 그대로 두고 섹션 간격·여백·줄 간격만 줄인다(§5.8: 같은 컴포넌트, 값만 분기).
private struct InsightCompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var insightCompact: Bool {
        get { self[InsightCompactKey.self] }
        set { self[InsightCompactKey.self] = newValue }
    }
}

// MARK: - 라이트 테마(인사이트 내보내기 전용)

/// 인사이트 카드(리듬·폼·퍼포먼스·대회) 내보내기의 라이트 테마 스위치.
/// 기본 false = 기존 다크 색 그대로 → 앱 화면은 이 값을 넣지 않으므로 겉모습이 바뀌지 않는다.
/// 뷰는 이 값으로 **색만** 고른다(크기·여백·배치는 같음 — §5.8).
private struct InsightLightKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var insightLight: Bool {
        get { self[InsightLightKey.self] }
        set { self[InsightLightKey.self] = newValue }
    }
}

/// 인사이트 카드 색 — `light == false`면 **기존 다크 값 그대로** 돌려준다.
/// 라이트 짝은 차트 내보내기(`ShareChartPalette.light`)·러닝 하루 카드(`RunCardLight`)와 같은 계열.
struct InsightInk {
    let light: Bool

    static let ink1 = Color(hex: "1A1A1A")

    /// 다크의 `.white` 자리 — 라이트에서 본문 검정.
    var primary: Color { light ? Self.ink1 : .white }

    /// 다크의 `Color.white.opacity(o)` 자리 — 흰 배경에서 같은 위계.
    /// 0.85↑ 본문 · 0.6~0.85 흐린 글자 · 0.35~0.6 더 흐린 글자 · 그 아래(면·선) 검정 반투명.
    func fg(_ o: Double) -> Color {
        guard light else { return Color.white.opacity(o) }
        // 2026-10-15 시인성: 흰 바탕에서 흐린 글자·격자가 묻혀 한 단계씩 진하게
        switch o {
        case 0.85...:     return Self.ink1
        case 0.6..<0.85:  return Color(hex: "3A3A3C")
        case 0.35..<0.6:  return Color(hex: "5C5C60")
        default:          return Self.ink1.opacity(min(0.4, o * 1.6))
        }
    }

    /// 글자로 쓰는 지표색 — 라이트에서 노랑·주황 계열 글자는 흰 바탕에서 묻혀 한 단계 짙게(선·점은 원래 짝 그대로).
    /// 다크는 받은 값 그대로.
    func metricText(_ c: Color) -> Color {
        guard light else { return c }
        switch c {
        case cadence:       return Color(hex: "B8860B")
        case strideLength:  return Color(hex: "B85500")
        case time:          return Color(hex: "A88400")
        case verticalOsc:   return Color(hex: "4A5666")
        default:            return c
        }
    }

    /// 다크·라이트 짝을 직접 고를 때 — 다크 값은 원래 리터럴 그대로 둔다.
    func pick(_ dark: Color, _ lightColor: Color) -> Color { light ? lightColor : dark }

    // 바탕
    var card: Color { light ? .white : Theme.cardBackground }

    // 브랜드·판정
    var violet: Color     { light ? Color(hex: "5B3FD9") : Theme.violet }
    var violetText: Color { light ? Color(hex: "5B3FD9") : Theme.violetText }
    var positive: Color   { light ? Color(hex: "2FA84F") : Theme.positive }
    var caution: Color    { light ? Color(hex: "E07800") : Theme.caution }

    // 지표 의미색
    var heartRate: Color     { light ? ShareChartPalette.light.hrRepColor : Theme.heartRate }   // E0242B
    var pace: Color          { light ? ShareChartPalette.light.pace : Theme.pace }              // 0E7C8A
    var time: Color          { light ? Color(hex: "D4A700") : Theme.time }
    var cadence: Color       { light ? Color(hex: "E0A800") : Theme.cadence }
    var strideLength: Color  { light ? Color(hex: "D96A00") : Theme.strideLength }
    var groundContact: Color { light ? Color(hex: "5B4BFF") : Theme.groundContact }
    var verticalOsc: Color   { light ? Color(hex: "5F6E80") : Theme.verticalOsc }
    var power: Color         { light ? Color(hex: "9B3BFF") : Theme.power }

    /// 정적 데이터에 담긴 지표 의미색(`Theme.cadence` 등)을 라이트 짝으로 — 다크는 받은 값 그대로.
    func metric(_ c: Color) -> Color {
        guard light else { return c }
        switch c {
        case Theme.cadence:       return cadence
        case Theme.strideLength:  return strideLength
        case Theme.groundContact: return groundContact
        case Theme.verticalOsc:   return verticalOsc
        case Theme.heartRate:     return heartRate
        case Theme.pace:          return pace
        case Theme.positive:      return positive
        case Theme.caution:       return caution
        default:                  return c
        }
    }

    // 심박 존
    var hrZoneColors: [Color] { light ? ShareChartPalette.light.hrZones : Theme.hrZoneColors }
    func hrZoneColor(_ zoneID: Int) -> Color { hrZoneColors[min(max(zoneID - 1, 0), 4)] }
}
