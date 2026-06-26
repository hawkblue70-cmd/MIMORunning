import Foundation
import CoreLocation

// MARK: - Sleep score

enum SleepGrade {
    case excellent, good, fair, insufficient, poor

    var label: String {
        let L = AppLanguage.shared
        return switch self {
        case .excellent:    L.s("매우높음", "Excellent")
        case .good:         L.s("높음",     "Good")
        case .fair:         L.s("보통",     "Fair")
        case .insufficient: L.s("낮음",     "Poor")
        case .poor:         L.s("매우낮음", "Very Poor")
        }
    }
}

/// 0–100 composite sleep quality score built from three weighted components.
/// Labelled "수면상태" (not "수면 점수") to distinguish it from Apple Health's
/// proprietary sleep score — values will differ.
struct SleepScore {
    let score: Int         // 0–100
    let grade: SleepGrade
    let sleepHours: Double // underlying duration, used by InsightEngine

    static let displayName = "수면상태"

    var isInsufficient: Bool { score < 55 }
    var chipLabel: String { grade.label }

    // MARK: Factory

    static func compute(durationHours: Double, consistencyPts: Int, interruptionPts: Int) -> SleepScore {
        let durPts = durationScore(hours: durationHours)
        let total  = max(0, min(100, durPts + consistencyPts + interruptionPts))
        let grade: SleepGrade
        switch total {
        case 85...: grade = .excellent
        case 70..<85: grade = .good
        case 55..<70: grade = .fair
        case 40..<55: grade = .insufficient
        default: grade = .poor
        }
        return SleepScore(score: total, grade: grade, sleepHours: durationHours)
    }

    // 0 pts at ≤4h, 50 pts at ≥7.5h, linear between
    static func durationScore(hours: Double) -> Int {
        let pts = (hours - 4.0) / (7.5 - 4.0) * 50.0
        return max(0, min(50, Int(pts.rounded())))
    }
}

// MARK: - Models

struct WeatherSnapshot {
    let tempC: Double
    let precipitation: Double   // mm in the hour
    let windKmh: Double

    var isHot:     Bool { tempC >= 28 }
    var isCold:    Bool { tempC <= 2 }
    var isRainy:   Bool { precipitation > 0.1 }
    var isWindy:   Bool { windKmh >= 20 }
    var isAdverse: Bool { isHot || isCold || isRainy || isWindy }

    var systemIcon: String {
        if isRainy { return "cloud.rain.fill" }
        if isHot   { return "sun.max.fill" }
        if isCold  { return "snowflake" }
        if isWindy { return "wind" }
        return "cloud.sun.fill"
    }

    var formattedTemp: String { String(format: "%.0f°C", tempC) }
}

struct ActivityCondition {
    var weather: WeatherSnapshot?
    var sleepScore: SleepScore?

    var hasAdverseSignal: Bool {
        weather?.isAdverse == true
    }
}

// MARK: - Weather fetch (Open-Meteo archive — free, no API key)

struct ConditionService {

    /// Fetches hourly weather for the run date and location.
    /// Uses the forecast API for runs within the last 7 days (no archive lag),
    /// falls back to the historical archive for older runs.
    /// Returns nil when: no coordinate, network error.
    static func fetchWeather(
        date: Date,
        coordinate: CLLocationCoordinate2D?
    ) async -> WeatherSnapshot? {
        guard let coord = coordinate else { return nil }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        let dateStr = df.string(from: date)

        // Forecast API covers today back ~7 days with no processing lag.
        // Archive API covers older dates but has a ~5-day quality lag.
        let daysSince = Date().timeIntervalSince(date) / 86400
        let baseURL = daysSince < 7
            ? "https://api.open-meteo.com/v1/forecast"
            : "https://archive-api.open-meteo.com/v1/archive"
        var comps = URLComponents(string: baseURL)!
        comps.queryItems = [
            URLQueryItem(name: "latitude",        value: String(format: "%.4f", coord.latitude)),
            URLQueryItem(name: "longitude",       value: String(format: "%.4f", coord.longitude)),
            URLQueryItem(name: "start_date",      value: dateStr),
            URLQueryItem(name: "end_date",        value: dateStr),
            URLQueryItem(name: "hourly",          value: "temperature_2m,precipitation,wind_speed_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timezone",        value: "UTC"),
        ]
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return parseHourlyResponse(data: data, date: date)
    }

    private static func parseHourlyResponse(data: Data, date: Date) -> WeatherSnapshot? {
        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hourly  = json["hourly"] as? [String: Any],
              let times   = hourly["time"]           as? [String],
              let temps   = hourly["temperature_2m"] as? [Double],
              let precips = hourly["precipitation"]  as? [Double],
              let winds   = hourly["wind_speed_10m"] as? [Double],
              !times.isEmpty else { return nil }

        // Match the hour closest to the run start (UTC)
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let runHour = utcCal.component(.hour, from: date)

        var bestIdx = 0, bestDiff = 24
        for (i, t) in times.enumerated() {
            let parts = t.split(separator: "T")
            guard parts.count == 2,
                  let hStr = parts[1].split(separator: ":").first,
                  let h    = Int(hStr) else { continue }
            let diff = abs(h - runHour)
            if diff < bestDiff { bestDiff = diff; bestIdx = i }
        }

        guard bestIdx < temps.count, bestIdx < precips.count, bestIdx < winds.count else { return nil }
        return WeatherSnapshot(
            tempC: temps[bestIdx],
            precipitation: precips[bestIdx],
            windKmh: winds[bestIdx]
        )
    }
}
