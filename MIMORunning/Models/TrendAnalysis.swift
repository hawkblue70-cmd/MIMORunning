import Foundation

enum TrendDirection {
    case up, down, flat, insufficient
}

enum TrendSentiment {
    case good, neutral, bad
}

/// 선형회귀 기울기를 평균으로 정규화해 추세 방향을 판정.
/// values = dataPoints.map(\.value) 형태로 넘길 것.
// values는 반드시 시간순(오래된→최신). 최신순 배열을 넘기면 모든 방향 판정이 반전된다. 호출부에서 .reversed() 확인할 것.
func trendDirection(values: [Double]) -> (direction: TrendDirection, changeRatio: Double) {
    let n = values.count
    guard n >= 4 else { return (.insufficient, 0) }
    let mean = values.reduce(0, +) / Double(n)
    guard mean != 0 else { return (.insufficient, 0) }

    let xs = (0..<n).map(Double.init)
    let xMean = xs.reduce(0, +) / Double(n)
    let num = zip(xs, values).reduce(0.0) { $0 + ($1.0 - xMean) * ($1.1 - mean) }
    let den = xs.reduce(0.0) { $0 + pow($1 - xMean, 2) }
    guard den != 0 else { return (.insufficient, 0) }
    let slope = num / den
    let changeRatio = (slope * Double(n - 1)) / mean

    let threshold = 0.02   // 2% — 점검 후 조정
    if changeRatio >= threshold  { return (.up,   changeRatio) }
    if changeRatio <= -threshold { return (.down, changeRatio) }
    return (.flat, changeRatio)
}

/// lowerIsBetter는 TrendMetric.lowerIsBetter(Activity.swift line 303)를 그대로 사용.
/// 체중·체지방 등 중립 지표는 호출부에서 isNeutral: true 로 전달.
func trendSentiment(direction: TrendDirection, lowerIsBetter: Bool, isNeutral: Bool = false) -> TrendSentiment {
    if isNeutral { return .neutral }
    switch direction {
    case .insufficient, .flat: return .neutral
    case .up:   return lowerIsBetter ? .bad  : .good
    case .down: return lowerIsBetter ? .good : .bad
    }
}
