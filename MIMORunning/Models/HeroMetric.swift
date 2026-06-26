import Foundation

enum HeroMetric: String, CaseIterable, Identifiable {
    case distance
    case pace
    case duration
    case heartRate

    var id: String { rawValue }

    var contextLabel: String {
        switch self {
        case .distance:  return "오늘의 거리"
        case .pace:      return "평균 페이스"
        case .duration:  return "운동 시간"
        case .heartRate: return "평균 심박"
        }
    }

    var unit: String {
        switch self {
        case .distance:  return "KM"
        case .pace:      return "/km"
        case .duration:  return ""
        case .heartRate: return "bpm"
        }
    }

    var shortName: String {
        switch self {
        case .distance:  return "거리"
        case .pace:      return "페이스"
        case .duration:  return "시간"
        case .heartRate: return "심박"
        }
    }

    func isAvailable(activity: Activity, detail: ActivityDetail?) -> Bool {
        switch self {
        case .distance:  return activity.distance > 0
        case .pace:      return (activity.paceSecPerKm ?? 0) > 0
        case .duration:  return activity.duration > 0
        case .heartRate: return (activity.avgHeartRate ?? 0) > 0
        }
    }

    func formattedValue(activity: Activity, detail: ActivityDetail?) -> String {
        switch self {
        case .distance:
            return String(format: "%.2f", activity.distance / 1000.0)
        case .pace:
            return activity.formattedPace ?? "-"
        case .duration:
            return activity.formattedDuration
        case .heartRate:
            return "\(activity.avgHeartRate ?? 0)"
        }
    }
}
