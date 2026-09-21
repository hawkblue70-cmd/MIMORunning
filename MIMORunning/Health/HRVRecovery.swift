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

// MARK: - HRV Recovery (deprecated)
//
// ⚠ 더 이상 계산하지 않는다. 조건 캐시(`ActivityCondition.hrvRecovery`) 디코딩 호환용으로만 남긴다.
//   수면 HRV는 엔진 스토어가 60일을 한 번에 가져와 `mrHRVTrend`(7일 vs 4주 기준선)로 본다 — Engine/MRHRVTrend.swift.

struct HRVRecovery: Codable {
    let todayValue: Double   // ms — 지난밤 수면 HRV 중앙값
    let baseline: Double     // ms — 직전 7일 일별 중앙값의 중앙값 (insufficient이면 0)
    let sd: Double           // ms — 직전 7일 일별 중앙값의 표준편차 (insufficient이면 0)
    let level: RecoveryLevel
}
