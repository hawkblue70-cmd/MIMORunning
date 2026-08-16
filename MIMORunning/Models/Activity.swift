import Foundation
import CoreLocation
import SwiftUI

enum ActivityType: String {
    case walking, running, hiking

    var icon: String {
        switch self {
        case .walking:  "figure.walk"
        case .running:  "figure.run"
        case .hiking:   "figure.hiking"
        }
    }

    var label: String {
        let L = AppLanguage.shared
        return switch self {
        case .walking:  L.s("걷기",   "Walk")
        case .running:  L.s("러닝",   "Run")
        case .hiking:   L.s("하이킹", "Hike")
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
    let temperatureC: Double?    // 섭씨, HKMetadataKeyWeatherTemperature
    let humidityPercent: Double? // 0~100, HKMetadataKeyWeatherHumidity

    init(id: UUID, type: ActivityType, date: Date, duration: TimeInterval,
         distance: Double, calories: Double?, avgHeartRate: Int?,
         temperatureC: Double? = nil, humidityPercent: Double? = nil) {
        self.id              = id
        self.type            = type
        self.date            = date
        self.duration        = duration
        self.distance        = distance
        self.calories        = calories
        self.avgHeartRate    = avgHeartRate
        self.temperatureC    = temperatureC
        self.humidityPercent = humidityPercent
    }

    var weatherBadgeText: String? {
        switch (temperatureC, humidityPercent) {
        case let (t?, h?):  return "\(Int(t.rounded()))° · 습도 \(Int(h.rounded()))%"
        case let (t?, nil): return "\(Int(t.rounded()))°"
        case let (nil, h?): return "습도 \(Int(h.rounded()))%"
        case (nil, nil):    return nil
        }
    }

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

    var paceSecPerKm: Double? {
        guard distance > 0 else { return nil }
        return duration / (distance / 1000)
    }

    var formattedPace: String? {
        guard let sec = paceSecPerKm else { return nil }
        let s = Int(sec)
        return String(format: "%d'%02d\"", s / 60, s % 60)
    }

    var avgSpeedKmh: Double? {
        guard duration > 0, distance > 0 else { return nil }
        return (distance / 1000) / (duration / 3600)
    }

    var formattedSpeed: String? {
        guard let speed = avgSpeedKmh else { return nil }
        return String(format: "%.1f", speed)
    }

}

// MARK: - Workout Type

enum WorkoutType: String, Codable {
    case interval    // 인터벌/스피드
    case longRun     // 롱런
    case easy        // 이지/회복런
    case tempo       // 템포런
    case buildUp     // 빌드업 (점진적 가속 구조)
    case lsd         // LSD — long slow distance
    case distanceRun // 거리주 (레이스페이스 장거리)
    case general     // 일반

    var koreanLabel: String {
        let L = AppLanguage.shared
        return switch self {
        case .interval:    L.s("인터벌",   "Interval")
        case .longRun:     L.s("롱런",     "Long Run")
        case .easy:        L.s("회복런",   "Easy Run")
        case .tempo:       L.s("템포런",   "Tempo Run")
        case .buildUp:     L.s("빌드업",   "Build-Up")
        case .lsd:         L.s("LSD",      "LSD")
        case .distanceRun: L.s("거리주",   "Distance Run")
        case .general:     L.s("일반 러닝", "General Run")
        }
    }
}

// MARK: - Activity Detail

struct ActivityDetail {
    let routeCoordinates: [CLLocationCoordinate2D]
    let routeTimeOffsets: [TimeInterval]           // 워크아웃 시작 기준 각 좌표의 초(seconds)
    let elevationGain: Double?
    let avgPower: Int?
    let avgCadence: Int?
    let splits: [SplitData]
    var hrZones: [HRZoneData]
    let intervalSegments: [IntervalSegment]
    let workoutType: WorkoutType       // classified from splits + history
    // Running dynamics — Watch only, nil when unavailable
    let avgGroundContactTime: Double?  // ms
    let avgStrideLength: Double?       // m
    let avgVerticalOscillation: Double? // cm
    let vo2Max: Double?                // mL/kg·min — most recent estimate at/before this run
    let altitudeProfile: [(distanceKm: Double, altitude: Double)]  // elevation chart data
    let altitudeTimeProfile: [(offset: TimeInterval, altitude: Double)]  // time-based for share card

    /// True when HealthKit returned at least one major data field.
    /// An incomplete cache (all empty) means HealthKit hadn't finished processing — re-fetch needed.
    var isComplete: Bool {
        !routeCoordinates.isEmpty || !splits.isEmpty || !hrZones.isEmpty ||
        avgPower != nil || avgCadence != nil
    }
}

struct IntervalSegment: Identifiable, Codable {
    let id: Int           // 1-based index
    let startDate: Date
    let endDate: Date
    let distanceM: Double?
    let avgHeartRate: Int?
    let avgCadence: Int?    // spm — nil when Watch data unavailable
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

struct SplitData: Identifiable, Codable {
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

struct HRZoneData: Identifiable, Codable {
    let id: Int              // 1–5
    let name: String
    let minBPM: Int
    let maxBPM: Int
    let seconds: TimeInterval
    let fraction: Double     // proportion of total tracked HR time (0.0–1.0)
}

// MARK: - ActivityDetail Codable (manual — handles CLLocationCoordinate2D and named tuples)

extension ActivityDetail: Codable {
    private enum CodingKeys: String, CodingKey {
        case routeLat, routeLon, routeTimeOffsets
        case elevationGain, avgPower, avgCadence
        case splits, hrZones, intervalSegments, workoutType
        case avgGroundContactTime, avgStrideLength, avgVerticalOscillation
        case vo2Max
        case altProfileDist, altProfileAlt
        case altTimeOffset, altTimeAlt
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lats = try c.decode([Double].self, forKey: .routeLat)
        let lons = try c.decode([Double].self, forKey: .routeLon)
        routeCoordinates = zip(lats, lons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
        routeTimeOffsets = (try? c.decode([TimeInterval].self, forKey: .routeTimeOffsets)) ?? []
        elevationGain           = try c.decodeIfPresent(Double.self, forKey: .elevationGain)
        avgPower                = try c.decodeIfPresent(Int.self,    forKey: .avgPower)
        avgCadence              = try c.decodeIfPresent(Int.self,    forKey: .avgCadence)
        splits                  = try c.decode([SplitData].self,       forKey: .splits)
        hrZones                 = try c.decode([HRZoneData].self,      forKey: .hrZones)
        intervalSegments        = try c.decode([IntervalSegment].self, forKey: .intervalSegments)
        workoutType             = try c.decode(WorkoutType.self,       forKey: .workoutType)
        avgGroundContactTime    = try c.decodeIfPresent(Double.self, forKey: .avgGroundContactTime)
        avgStrideLength         = try c.decodeIfPresent(Double.self, forKey: .avgStrideLength)
        avgVerticalOscillation  = try c.decodeIfPresent(Double.self, forKey: .avgVerticalOscillation)
        vo2Max                  = try c.decodeIfPresent(Double.self, forKey: .vo2Max)
        let dists   = try c.decode([Double].self, forKey: .altProfileDist)
        let alts    = try c.decode([Double].self, forKey: .altProfileAlt)
        altitudeProfile = zip(dists, alts).map { (distanceKm: $0, altitude: $1) }
        let offsets = try c.decode([Double].self, forKey: .altTimeOffset)
        let tAlts   = try c.decode([Double].self, forKey: .altTimeAlt)
        altitudeTimeProfile = zip(offsets, tAlts).map { (offset: $0, altitude: $1) }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(routeCoordinates.map(\.latitude),  forKey: .routeLat)
        try c.encode(routeCoordinates.map(\.longitude), forKey: .routeLon)
        try c.encode(routeTimeOffsets,                  forKey: .routeTimeOffsets)
        try c.encodeIfPresent(elevationGain,          forKey: .elevationGain)
        try c.encodeIfPresent(avgPower,               forKey: .avgPower)
        try c.encodeIfPresent(avgCadence,             forKey: .avgCadence)
        try c.encode(splits,           forKey: .splits)
        try c.encode(hrZones,          forKey: .hrZones)
        try c.encode(intervalSegments, forKey: .intervalSegments)
        try c.encode(workoutType,      forKey: .workoutType)
        try c.encodeIfPresent(avgGroundContactTime,   forKey: .avgGroundContactTime)
        try c.encodeIfPresent(avgStrideLength,        forKey: .avgStrideLength)
        try c.encodeIfPresent(avgVerticalOscillation, forKey: .avgVerticalOscillation)
        try c.encodeIfPresent(vo2Max,                 forKey: .vo2Max)
        try c.encode(altitudeProfile.map(\.distanceKm), forKey: .altProfileDist)
        try c.encode(altitudeProfile.map(\.altitude),   forKey: .altProfileAlt)
        try c.encode(altitudeTimeProfile.map(\.offset),   forKey: .altTimeOffset)
        try c.encode(altitudeTimeProfile.map(\.altitude), forKey: .altTimeAlt)
    }
}

// MARK: - Trend Metric

enum TrendMetric: String, CaseIterable, Identifiable {
    case cadence, power, groundContactTime, strideLength, verticalOscillation, vo2Max
    case bodyMass, bodyFatPercentage

    var id: String { rawValue }

    var koreanLabel: String {
        let L = AppLanguage.shared
        return switch self {
        case .cadence:             L.s("케이던스",     "Cadence")
        case .power:               L.s("파워",         "Power")
        case .groundContactTime:   L.s("지면 접촉 시간", "Gnd Contact")
        case .strideLength:        L.s("보폭",         "Stride Length")
        case .verticalOscillation: L.s("수직 진폭",   "Vert. Osc.")
        case .vo2Max:              L.s("유산소 피트니스", "Cardio Fitness")
        case .bodyMass:            L.s("체중",         "Body Weight")
        case .bodyFatPercentage:   L.s("체지방률",     "Body Fat")
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

    var sparkColor: Color {
        switch self {
        case .cadence:             Theme.cadence
        case .power:               Theme.power
        case .groundContactTime:   Theme.time
        case .strideLength:        Theme.strideLength
        case .verticalOscillation: Theme.verticalOsc
        case .vo2Max:              Theme.elevation
        case .bodyMass:            Color(hex: "8A8A92")
        case .bodyFatPercentage:   Color(hex: "8A8A92")
        }
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
