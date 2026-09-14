import SwiftUI

/// 지표 종류 — 표시 색을 매체(앱 화면 / 공유 카드 라이트·다크)별로 고르는 데 쓴다.
enum RunMetricKind {
    case distance, time, pace, heartRate, cadence, power
    case form          // 지면접촉 · 보폭 · 수직 진폭
    case cardio        // 유산소 피트니스(VO2max)
    case calories, elevation
}

extension RunMetricKind {
    /// 공유 카드의 지표 색 — 라이트·다크 두 벌을 **여기 한 곳**에서만 정한다.
    ///
    /// ⚠ 예전에는 구간 카드와 경로 카드가 각자 색을 정해, 같은 러닝의 케이던스가 한쪽은 검정
    ///   한쪽은 노랑이고 보폭이 한쪽은 보라 한쪽은 청록이었다. 경로 카드는 라이트 배경인데
    ///   다크용 색(노랑·라임)을 그대로 써서 흰 바탕에 거의 안 보였다.
    ///
    /// 라이트 값은 흰 배경에서 읽히도록 어둡게 잡은 짝이다. 밝은 노랑·라임·청록을 그대로
    /// 쓰면 안 된다.
    func shareColor(isLight: Bool, textPrimary: Color) -> Color {
        guard isLight else {
            switch self {
            case .distance:  return textPrimary
            case .time:      return Theme.time
            case .pace:      return Theme.pace
            case .heartRate: return Theme.heartRate
            case .cadence:   return Theme.cadence
            case .power:     return Theme.power
            case .form:      return Theme.runningForm
            case .cardio:    return Color(hex: "4FC3F7")   // 파랑 — 고도 초록과 분리
            case .calories:  return Theme.calories
            case .elevation: return Theme.elevation
            }
        }
        switch self {
        case .distance:  return textPrimary
        case .time:      return Color(hex: "C25E00")   // 번트 오렌지 — 케이던스 금색과 벌린다
        case .pace:      return Color(hex: "0E7C8A")
        case .heartRate: return Color(hex: "C62828")
        case .cadence:   return Color(hex: "A07400")   // 짙은 금색 — 예전에는 색 없이 검정이었다
        case .power:     return Color(hex: "4F7A00")   // 라임 → 짙은 올리브
        case .form:      return Color(hex: "5B3FD9")
        case .cardio:    return Color(hex: "1565C0")   // 파랑 — 고도 초록과 같은 색이었다
        case .calories:  return Color(hex: "C2185B")
        case .elevation: return Color(hex: "1B7F3B")
        }
    }
}

/// 활동 상세 상단 지표 그리드와 "구간 러닝 데이터" 공유 카드가 **함께 쓰는** 지표 목록.
/// 두 곳이 같은 항목·같은 표기를 쓰도록 목록은 여기서만 만든다 — 별도 목록 작성 금지.
struct RunMetricItem: Identifiable {
    /// ForEach 식별자 — 라벨은 목록 안에서 유일하다.
    ///
    /// ⚠ UUID를 쓰면 안 된다. `list(...)`는 computed property에서 호출돼 body가 평가될 때마다
    /// 항목을 새로 만드는데, UUID면 그때마다 식별자가 전부 바뀐다. LazyVGrid는 식별자가 바뀐
    /// 셀을 버리고 다시 만들기 때문에 셀이 비거나 사라져 보인다.
    var id: String { label }
    let kind: RunMetricKind
    let icon: String
    let label: String
    let value: String
    let color: Color
    var note: String? = nil
    var trendMetric: TrendMetric? = nil
    var compactValue: Bool = false   // true → title3, false → title2 (앱 화면 전용)

    /// 색만 바꾼 복제 — 카드마다 배경이 달라 같은 항목에 다른 색을 입혀야 한다.
    func recolored(_ newColor: Color) -> RunMetricItem {
        RunMetricItem(kind: kind, icon: icon, label: label, value: value, color: newColor,
                      note: note, trendMetric: trendMetric, compactValue: compactValue)
    }

    static func list(activity: Activity,
                     detail: ActivityDetail?,
                     age: Int?,
                     isMale: Bool?) -> [RunMetricItem] {
        let L = AppLanguage.shared
        var list: [RunMetricItem] = [
            RunMetricItem(kind: .distance, icon: "ruler", label: L.s("거리", "Dist."),
                          value: activity.formattedDistance, color: .white),
            RunMetricItem(kind: .time, icon: "clock", label: L.s("시간", "Time"),
                          value: activity.formattedDuration, color: Theme.time),
        ]
        if let pace = activity.formattedPace {
            list.append(RunMetricItem(kind: .pace, icon: "timer", label: L.s("페이스", "Pace"),
                                      value: pace, color: Theme.pace))
        }
        if let hr = activity.avgHeartRate {
            list.append(RunMetricItem(kind: .heartRate, icon: "heart.fill", label: L.s("평균 심박", "Avg HR"),
                                      value: "\(hr) bpm", color: Theme.heartRate))
        }
        if activity.type == .running {
            if let cadence = detail?.avgCadence {
                list.append(RunMetricItem(kind: .cadence, icon: "figure.run", label: L.s("케이던스", "Cadence"),
                                          value: "\(cadence) spm", color: .white, trendMetric: .cadence))
            }
            if let power = detail?.avgPower {
                list.append(RunMetricItem(kind: .power, icon: "bolt.fill", label: L.s("파워", "Power"),
                                          value: "\(power) W", color: Theme.power, trendMetric: .power))
            }
            if let gct = detail?.avgGroundContactTime {
                list.append(RunMetricItem(kind: .form, icon: "stopwatch", label: L.s("지면접촉", "Gnd Contact"),
                                          value: "\(Int(gct.rounded())) ms", color: Theme.runningForm,
                                          trendMetric: .groundContactTime))
            }
            if let stride = detail?.avgStrideLength {
                list.append(RunMetricItem(kind: .form, icon: "arrow.left.and.right", label: L.s("보폭", "Stride"),
                                          value: String(format: "%.2f m", stride), color: Theme.runningForm,
                                          trendMetric: .strideLength))
            }
            if let vo = detail?.avgVerticalOscillation {
                list.append(RunMetricItem(kind: .form, icon: "arrow.up.and.down", label: L.s("수직 진폭", "Vert. Osc."),
                                          value: String(format: "%.1f cm", vo), color: Theme.runningForm,
                                          trendMetric: .verticalOscillation))
            }
            if let vo2 = detail?.vo2Max {
                let rating = CardioFitnessClassifier.rating(vo2: vo2, age: age, isMale: isMale)
                let note = rating.map { L.s("현재 추정 · \($0)", "Curr. Est. · \($0)") } ?? L.s("현재 추정", "Curr. Est.")
                list.append(RunMetricItem(kind: .cardio, icon: "lungs.fill",
                                          label: L.s("유산소 피트니스", "Cardio Fitness"),
                                          value: String(format: "%.1f mL/kg·min", vo2),
                                          color: Theme.elevation, note: note,
                                          trendMetric: .vo2Max, compactValue: true))
            }
        }
        if let cal = activity.calories {
            list.append(RunMetricItem(kind: .calories, icon: "flame.fill", label: L.s("칼로리", "Cals"),
                                      value: String(format: "%.0f kcal", cal), color: Theme.calories))
        }
        if let elev = detail?.elevationGain {
            list.append(RunMetricItem(kind: .elevation, icon: "arrow.up.right", label: L.s("고도 획득", "Elev. Gain"),
                                      value: String(format: "%.0f m", elev), color: Theme.elevation))
        }
        return list
    }
}
