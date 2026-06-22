import Foundation
import CoreLocation

enum ActivityType: String {
    case walking, running, hiking, cycling, swimming

    var icon: String {
        switch self {
        case .walking:  "figure.walk"
        case .running:  "figure.run"
        case .hiking:   "figure.hiking"
        case .cycling:  "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        }
    }

    var label: String {
        switch self {
        case .walking:  "걷기"
        case .running:  "러닝"
        case .hiking:   "하이킹"
        case .cycling:  "자전거"
        case .swimming: "수영"
        }
    }
}

struct Activity: Identifiable, Hashable {
    let id: UUID
    let type: ActivityType
    let date: Date
    let duration: TimeInterval
    let distance: Double        // meters
    let calories: Double?
    let avgHeartRate: Int?

    var formattedDistance: String {
        let km = distance / 1000
        return km >= 10
            ? String(format: "%.1f km", km)
            : String(format: "%.2f km", km)
    }

    var formattedDuration: String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        let s = Int(duration) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    var formattedPace: String? {
        guard distance > 0 else { return nil }
        let secPerKm = duration / (distance / 1000)
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d'%02d\"", m, s)
    }

    var paceSecPerKm: Double? {
        guard distance > 0 else { return nil }
        return duration / (distance / 1000)
    }

    var avgSpeedKmh: Double? {
        guard duration > 0, distance > 0 else { return nil }
        return (distance / 1000) / (duration / 3600)
    }

    var formattedSpeed: String? {
        guard let speed = avgSpeedKmh else { return nil }
        return String(format: "%.1f", speed)
    }

    var formattedPace100m: String? {
        guard distance > 0, duration > 0 else { return nil }
        let sec = duration / (distance / 100)
        return String(format: "%d'%02d\"", Int(sec) / 60, Int(sec) % 60)
    }
}

// MARK: - Workout Type

enum WorkoutType: String {
    case interval  // 인터벌/스피드
    case longRun   // 롱런
    case easy      // 이지/회복런
    case tempo     // 템포런
    case general   // 일반

    var koreanLabel: String {
        switch self {
        case .interval: "인터벌"
        case .longRun:  "롱런"
        case .easy:     "회복런"
        case .tempo:    "템포런"
        case .general:  "일반 러닝"
        }
    }
}

// MARK: - Activity Detail

struct ActivityDetail {
    let routeCoordinates: [CLLocationCoordinate2D]
    let elevationGain: Double?
    let avgSpeed: Double?            // km/h — cycling
    let avgPower: Int?
    let avgCadence: Int?
    let splits: [SplitData]
    let hrZones: [HRZoneData]
    let intervalSegments: [IntervalSegment]
    let workoutType: WorkoutType       // classified from splits + history
    // Running dynamics — Watch only, nil when unavailable
    let avgGroundContactTime: Double?  // ms
    let avgStrideLength: Double?       // m
    let avgVerticalOscillation: Double? // cm
    let vo2Max: Double?                // mL/kg·min — most recent estimate at/before this run
    let poolLength: Double?          // m — swimming
    let swimmingStrokeCount: Int?    // total strokes — swimming
    let swimLapCount: Int?           // number of laps — swimming
    let swolfScore: Double?          // avg per length (strokes + seconds) — swimming
    let altitudeProfile: [(distanceKm: Double, altitude: Double)]  // elevation chart data
    let altitudeTimeProfile: [(offset: TimeInterval, altitude: Double)]  // time-based for share card
}

struct IntervalSegment: Identifiable {
    let id: Int           // 1-based index
    let startDate: Date
    let endDate: Date
    let distanceM: Double?
    let avgHeartRate: Int?
    let stepLabel: String?  // "준비운동" / "운동" / "회복" / "정리운동", nil if plan unavailable

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    var paceSecPerKm: Double? {
        guard let d = distanceM, d > 0, duration > 0 else { return nil }
        return duration / (d / 1000)
    }

    var formattedPace: String? {
        guard let sec = paceSecPerKm else { return nil }
        return String(format: "%d'%02d\"", Int(sec) / 60, Int(sec) % 60)
    }

    var formattedDistance: String? {
        guard let d = distanceM else { return nil }
        return d >= 1000
            ? String(format: "%.2f km", d / 1000)
            : String(format: "%.0f m", d)
    }

    var formattedDuration: String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct SplitData: Identifiable {
    let id: Int              // 1-based km number
    let distanceM: Double    // meters (< 1000 for last partial split)
    let duration: TimeInterval
    let avgHeartRate: Int?
    let avgCadence: Int?     // spm — nil when Watch data unavailable
    let avgPower: Int?       // W  — nil when Watch data unavailable

    var paceSecPerKm: Double { duration / (distanceM / 1000) }

    var formattedPace: String {
        let sec = Int(paceSecPerKm)
        return String(format: "%d'%02d\"", sec / 60, sec % 60)
    }

    var formattedDuration: String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct HRZoneData: Identifiable {
    let id: Int              // 1–5
    let name: String
    let minBPM: Int
    let maxBPM: Int
    let seconds: TimeInterval
    let fraction: Double     // proportion of total tracked HR time (0.0–1.0)
}

// MARK: - Trend Metric

enum TrendMetric: String, CaseIterable, Identifiable {
    case cadence, power, groundContactTime, strideLength, verticalOscillation, vo2Max
    case bodyMass, bodyFatPercentage

    var id: String { rawValue }

    var koreanLabel: String {
        switch self {
        case .cadence:             "케이던스"
        case .power:               "파워"
        case .groundContactTime:   "지면 접촉 시간"
        case .strideLength:        "보폭"
        case .verticalOscillation: "수직 진폭"
        case .vo2Max:              "유산소 피트니스"
        case .bodyMass:            "체중"
        case .bodyFatPercentage:   "체지방률"
        }
    }

    var unit: String {
        switch self {
        case .cadence:             "spm"
        case .power:               "W"
        case .groundContactTime:   "ms"
        case .strideLength:        "m"
        case .verticalOscillation: "cm"
        case .vo2Max:              "mL/kg·min"
        case .bodyMass:            "kg"
        case .bodyFatPercentage:   "%"
        }
    }

    var lowerIsBetter: Bool {
        self == .groundContactTime || self == .verticalOscillation
    }

    func formattedValue(_ val: Double, usePounds: Bool = false) -> String {
        switch self {
        case .cadence, .power, .groundContactTime:
            return "\(Int(val.rounded())) \(unit)"
        case .strideLength:
            return String(format: "%.2f \(unit)", val)
        case .verticalOscillation, .vo2Max:
            return String(format: "%.1f \(unit)", val)
        case .bodyMass:
            return usePounds
                ? String(format: "%.1f lb", val * 2.20462)
                : String(format: "%.1f kg", val)
        case .bodyFatPercentage:
            return String(format: "%.1f%%", val)
        }
    }
}
