import Foundation

// MARK: - Recovery Level

enum RecoveryLevel: String, Codable {
    case low, normal, high, insufficient

    var label: String {
        let L = AppLanguage.shared
        return switch self {
        case .low:          L.s("평소보다 낮음", "Below Normal")
        case .normal:       L.s("정상 범위",     "Normal")
        case .high:         L.s("평소보다 높음", "Above Normal")
        case .insufficient: L.s("데이터 부족",   "Insufficient Data")
        }
    }

    var systemIcon: String {
        switch self {
        case .low:          "arrow.down.heart.fill"
        case .normal:       "checkmark.circle.fill"
        case .high:         "arrow.up.heart.fill"
        case .insufficient: "questionmark.circle"
        }
    }
}

// MARK: - HRV Recovery

/// 수면 HRV(SDNN) 기반 회복 등급.
/// 직전 7일 일별 중앙값을 baseline으로 삼아 오늘 밤 값과 ±1 SD로 비교.
struct HRVRecovery: Codable {
    let todayValue: Double   // ms — 지난밤 수면 HRV 중앙값
    let baseline: Double     // ms — 직전 7일 일별 중앙값의 중앙값 (insufficient이면 0)
    let sd: Double           // ms — 직전 7일 일별 중앙값의 표준편차 (insufficient이면 0)
    let level: RecoveryLevel
}

// MARK: - Stat helpers (internal, used by HealthKitManager)

func hrvMedian(_ values: [Double]) -> Double {
    let s = values.sorted()
    let n = s.count
    return n % 2 == 0 ? (s[n/2 - 1] + s[n/2]) / 2.0 : s[n/2]
}

func hrvSD(_ values: [Double]) -> Double {
    guard values.count >= 2 else { return 0 }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count - 1)
    return variance.squareRoot()
}
