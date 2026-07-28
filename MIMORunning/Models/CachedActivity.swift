import Foundation
import SwiftData

/// SwiftData cache for HealthKit enrichment results (calories + HR + distance fallback).
/// Avoids re-querying HealthKit for every workout on every launch.
@Model
final class CachedActivity {
    @Attribute(.unique) var workoutID: String
    var typeRaw:      String
    var date:         Date
    var duration:     Double
    var distance:     Double
    var avgHeartRate:    Int?
    var calories:        Double?
    var cachedAt:        Date
    var metricsChecked:  Bool = false  // true = HealthKit에서 HR 유무 확정 완료, 재시도 불필요
    var temperatureC:    Double?       // nil-safe for existing rows without weather data
    var humidityPercent: Double?

    init(from activity: Activity) {
        self.workoutID       = activity.id.uuidString
        self.typeRaw         = activity.type.rawValue
        self.date            = activity.date
        self.duration        = activity.duration
        self.distance        = activity.distance
        self.avgHeartRate    = activity.avgHeartRate
        self.calories        = activity.calories
        self.cachedAt        = Date()
        self.temperatureC    = activity.temperatureC
        self.humidityPercent = activity.humidityPercent
    }

    func toActivity() -> Activity {
        Activity(
            id:              UUID(uuidString: workoutID) ?? UUID(),
            type:            ActivityType(rawValue: typeRaw) ?? .running,
            date:            date,
            duration:        duration,
            distance:        distance,
            calories:        calories,
            avgHeartRate:    avgHeartRate,
            temperatureC:    temperatureC,
            humidityPercent: humidityPercent
        )
    }
}
