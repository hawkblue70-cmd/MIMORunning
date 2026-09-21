import Foundation
import CoreLocation

// MARK: - Sleep score

enum SleepGrade: String, Codable {
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

    // 수면 등급별 러닝 의견 (숫자 없이 등급만 표시하는 칩 옆에 노출)
    var runningComment: String {
        let L = AppLanguage.shared
        return switch self {
        case .excellent:    L.s("오늘 힘껏 달려도 좋아요",     "Great day to push hard")
        case .good:         L.s("컨디션이 좋아요",             "Good condition today")
        case .fair:         L.s("무리하지 않게 달리세요",       "Keep it comfortable")
        case .insufficient: L.s("가볍게 달리는 걸 추천해요",   "Easy run recommended")
        case .poor:         L.s("충분한 휴식 후 달리세요",     "Rest up before running")
        }
    }
}

/// 애플 수면 점수와 동일한 3요소 구조(시간 50 / 일관성 30 / 중단 20)를
/// 따르되, 애플의 실제 알고리즘은 비공개이므로 값은 일치하지 않는다.
/// 관측 오차 범위: 대체로 ±10점, 수면이 분절된 날은 더 벌어질 수 있음.
/// 앱 내부에서 일관된 상대 비교 지표로 사용한다.
/// Labelled "수면상태" (not "수면 점수") to distinguish from Apple's proprietary score.
struct SleepScore: Codable {
    let score: Int         // 0–100
    let grade: SleepGrade
    let sleepHours: Double // underlying duration, used by InsightEngine

    static let displayName = "수면상태"

    var isInsufficient: Bool { score < 61 }  // 낮음(41-60) + 매우낮음(≤40) 모두 경고
    var chipLabel: String { grade.label }

    // MARK: Factory

    static func compute(durationHours: Double, consistencyPts: Int, interruptionPts: Int) -> SleepScore {
        let durPts = durationScore(hours: durationHours, goalHours: sleepGoalHours())
        let total  = max(0, min(100, durPts + consistencyPts + interruptionPts))
        let grade: SleepGrade
        // iOS 26.2 기준: 80=보통, 81=높음 / 95=높음, 96=매우높음
        switch total {
        case 96...: grade = .excellent      // 매우높음: ≥96
        case 81..<96: grade = .good         // 높음: 81–95
        case 61..<81: grade = .fair         // 보통: 61–80
        case 41..<61: grade = .insufficient // 낮음: 41–60
        default: grade = .poor              // 매우낮음: ≤40
        }
        // 디버그 로그는 querySleepScore 에서 출력 (편차·이력 수·각성 횟수까지 포함)
        return SleepScore(score: total, grade: grade, sleepHours: durationHours)
    }

    /// 수면 목표 대비 비선형 배점 (0–50점). Apple 역산 기반 구간.
    static func durationScore(hours: Double, goalHours: Double = 8.0) -> Int {
        let ratio = hours / goalHours
        switch ratio {
        case 0.95...:     return 50
        case 0.85..<0.95: return 44 + Int(((ratio - 0.85) / 0.10 * 6).rounded())
        case 0.75..<0.85: return 37 + Int(((ratio - 0.75) / 0.10 * 7).rounded())
        case 0.65..<0.75: return 29 + Int(((ratio - 0.65) / 0.10 * 8).rounded())
        case 0.50..<0.65: return 16 + Int(((ratio - 0.50) / 0.15 * 13).rounded())
        default:          return max(0, Int((ratio / 0.50 * 16).rounded()))
        }
    }

    /// HealthKit 수면 스케줄 → UserDefaults → 기본 8시간 순으로 목표 시간 조회.
    static func sleepGoalHours() -> Double {
        // TODO: iOS 17+ HKSleepScheduleQuery 지원 시 HealthKit 우선 조회로 교체
        return UserDefaults.standard.object(forKey: "sleepGoalHours") as? Double ?? 8.0
    }
}

// MARK: - Models

struct WeatherSnapshot: Codable {
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

struct ActivityCondition: Codable {
    var weather: WeatherSnapshot?
    var sleepScore: SleepScore?
    var hrvRecovery: HRVRecovery?
    /// 수면 조회를 완료했음을 표시(HRV는 더 이상 여기서 보지 않는다 — MRHRVTrend). 이전 캐시는 false로 디코딩되어 1회 재조회 후 true로 갱신.
    var sleepChecked: Bool = false
    /// 수면 점수 계산 공식 버전. 공식 변경 시 올려서 기존 캐시를 자동 무효화.
    /// 이전 캐시는 필드 없으므로 0으로 디코딩 → 자동 재계산 트리거.
    var sleepVersion: Int = 0

    static let currentSleepVersion = 19  // v19: 과보정 롤백 — asleep 합산·순환편차·26.2 등급만 유지

    nonisolated init(weather: WeatherSnapshot? = nil, sleepScore: SleepScore? = nil, hrvRecovery: HRVRecovery? = nil, sleepChecked: Bool = false, sleepVersion: Int = 0) {
        self.weather = weather
        self.sleepScore = sleepScore
        self.hrvRecovery = hrvRecovery
        self.sleepChecked = sleepChecked
        self.sleepVersion = sleepVersion
    }

    var hasAdverseSignal: Bool {
        weather?.isAdverse == true
    }
}

// MARK: - Condition cache (memory + disk, keyed by activity UUID)

actor ConditionCache {
    static let shared = ConditionCache()
    private init() {}

    private var store: [UUID: ActivityCondition] = [:]

    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MIMOCondition", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func cacheURL(_ id: UUID) -> URL {
        Self.cacheDir.appendingPathComponent("condition_\(id.uuidString).json")
    }

    /// Checks memory first, then disk on miss. Returns nil only if truly unavailable.
    func condition(for activityID: UUID) -> ActivityCondition? {
        if let hit = store[activityID] { return hit }
        guard let data = try? Data(contentsOf: cacheURL(activityID)),
              let disk = try? JSONDecoder().decode(ActivityCondition.self, from: data)
        else { return nil }
        store[activityID] = disk
        return disk
    }

    /// Saves to memory and disk atomically.
    func cache(_ condition: ActivityCondition, for activityID: UUID) {
        store[activityID] = condition
        guard let data = try? JSONEncoder().encode(condition) else { return }
        try? data.write(to: cacheURL(activityID), options: .atomic)
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
        guard var comps = URLComponents(string: baseURL) else { return nil }
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
        utcCal.timeZone = TimeZone(identifier: "UTC") ?? .current
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
