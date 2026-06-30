import Foundation
import CoreLocation
import Observation

// MARK: - JSON race model

struct BundledRace: Identifiable, Codable {
    let name: String
    let dateString: String      // "date" in JSON → "yyyy-MM-dd"
    let region: String
    let start: String           // venue text; may contain "일원" (vague)
    let distancesKm: [Double]
    let tags: [String]
    let nonStandard: Bool
    var startTimeString: String?
    var startLatitude: Double?
    var startLongitude: Double?

    // Stable computed ID — unique per race name+date combination
    var id: String { name + dateString }

    enum CodingKeys: String, CodingKey {
        case name, region, start, distancesKm, tags, nonStandard
        case dateString = "date"
        case startTimeString = "startTime"
        // startLatitude/startLongitude: runtime-only, not in JSON
    }

    var date: Date? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone  = TimeZone(identifier: "UTC")
        return df.date(from: dateString)
    }

    var startHour: Int? {
        guard let t = startTimeString, t.count >= 2,
              let h = Int(t.prefix(2)) else { return nil }
        return h
    }

    var startCoordinate: CLLocationCoordinate2D? {
        guard let lat = startLatitude, let lon = startLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // "일원" = general area → cannot reliably geocode
    var isVagueLocation: Bool {
        start.contains("일원") || start.hasPrefix("미정") || start == "미정"
    }

    // If start is "성남 일원", returns "성남" so we can reject cross-city false matches.
    // Returns nil for broad province/geographic terms that can't narrow down a city.
    var cityHint: String? {
        guard start.contains("일원") else { return nil }
        let broadTerms: Set<String> = [
            "서울", "경기", "부산", "대구", "인천", "광주", "대전", "울산", "세종",
            "강원", "충북", "충남", "전북", "전남", "경북", "경남", "제주",
            "한강", "낙동강", "금강", "섬진강", "지리산", "한라산", "설악산", "무등산"
        ]
        let first = start.components(separatedBy: " ").first ?? ""
        return (!first.isEmpty && !broadTerms.contains(first)) ? first : nil
    }

    // ±5 % of any listed distance
    func matchesDistance(_ km: Double) -> Bool {
        guard !distancesKm.isEmpty else { return false }
        return distancesKm.contains { abs($0 - km) / max($0, 0.001) <= 0.05 }
    }

    func bestMatchingDistance(_ km: Double) -> Double? {
        guard let closest = distancesKm.min(by: { abs($0 - km) < abs($1 - km) }) else { return nil }
        return (abs(closest - km) / max(closest, 0.001)) <= 0.05 ? closest : nil
    }
}

// MARK: - Match result

enum MatchStrength {
    case strong   // specific location ≤ 1.5 km, single candidate → auto-confirm
    case weak     // vague/multiple/no-GPS → suggest only, user must confirm
}

struct RaceSuggestion {
    let primary: BundledRace
    let strength: MatchStrength
    let alternatives: [BundledRace]    // other candidates (weak multi-match)
}

// MARK: - Persisted match

struct PersistedRaceMatch: Codable, Equatable {
    let activityID: UUID
    var raceName: String
    var distanceKm: Double
    var raceDate: Date
    var isConfirmed: Bool
    var isDismissed: Bool
    var isManual: Bool
}

// MARK: - GeocoderService (rate-limited, serialized)
// Apple's geocoding limit is 50 requests / 60 s. Enforcing 1.3 s minimum gap stays
// safely under that even if multiple callers share this actor simultaneously.

private actor GeocoderService {
    private let geocoder = CLGeocoder()
    private var lastRequestTime: Date = .distantPast
    private let minInterval: TimeInterval = 1.3

    func geocodeAddress(_ address: String) async -> CLLocationCoordinate2D? {
        await throttle()
        return await withCheckedContinuation { cont in
            geocoder.geocodeAddressString(address) { placemarks, _ in
                cont.resume(returning: placemarks?.first?.location?.coordinate)
            }
        }
    }

    func reverseGeocodeLocation(_ location: CLLocation) async -> [CLPlacemark]? {
        await throttle()
        return await withCheckedContinuation { cont in
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                cont.resume(returning: placemarks)
            }
        }
    }

    private func throttle() async {
        let wait = minInterval - Date().timeIntervalSince(lastRequestTime)
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        lastRequestTime = Date()
    }
}

// MARK: - RaceDetector

@Observable
final class RaceDetector {
    private(set) var isGeocoding = false
    private(set) var races: [BundledRace] = []
    private(set) var matches: [String: PersistedRaceMatch] = [:]   // activityID.uuidString → match

    private static let geocacheKey = "raceDetector.geocache.v2"
    private static let matchesKey  = "raceDetector.matches.v1"
    private var regionCache: [String: [String]] = [:]          // "lat,lon" → [province, city, …]
    private var cityHintCoordCache: [String: CLLocationCoordinate2D] = [:]  // "성남_경기" → coord
    private let geocoderService = GeocoderService()

    // MARK: - Setup (call once at app start)

    func setup() async {
        loadMatches()
        await loadAndGeocodeRaces()
    }

    // MARK: - Core assessment

    /// Returns the best race suggestion for an activity, or nil if no candidates.
    /// Strong match → auto-confirm in caller. Weak match → show suggestion banner.
    func assess(
        activityID: UUID,
        date: Date,
        distanceKm: Double,
        startCoord: CLLocationCoordinate2D?,
        routeCoords: [CLLocationCoordinate2D] = []
    ) async -> RaceSuggestion? {
        let existing = matches[activityID.uuidString]
        if existing?.isConfirmed == true { return nil }
        let wasDismissed = existing?.isDismissed == true

        let cal = Calendar.current

        // Step 1: date + distance filter (no geocoding needed — run immediately)
        let sameDay = races.filter { race in
            guard let rd = race.date else { return false }
            return cal.isDate(date, inSameDayAs: rd)
        }
        let workoutHour = cal.component(.hour, from: date)
        let dateDist = sameDay.filter { race in
            guard race.matchesDistance(distanceKm) else { return false }
            if let raceHour = race.startHour {
                return abs(workoutHour - raceHour) <= 3
            }
            return true
        }
        guard !dateDist.isEmpty else { return nil }

        // Step 2: region filter — user reverse geocode only (does NOT need venue geocoding)
        var candidates = dateDist
        if let sc = startCoord {
            let runTokens = await reverseGeocodeRegion(sc)
            if !runTokens.isEmpty {
                let regionFiltered = dateDist.filter { regionMatches($0, runTokens) }
                if !regionFiltered.isEmpty {
                    candidates = regionFiltered
                } else {
                    // Confirmed city mismatch (e.g. 성남 race + 안산 run) — don't fall back
                    let activeCityMismatch = runTokens.count > 1
                        && dateDist.contains { $0.cityHint != nil }
                    if activeCityMismatch { return nil }
                }
            }
        }

        // Step 2.5: city-coordinate proximity check for vague-location (일원) candidates.
        // Even when the text filter passes (or was skipped due to no city token from geocoder),
        // geocoding the cityHint gives an approximate city-center and we reject if the user
        // ran more than 20 km away — e.g. 성남 race vs 안산 run (~35 km apart).
        if let sc = startCoord, candidates.contains(where: { $0.isVagueLocation && $0.cityHint != nil }) {
            var coordFiltered: [BundledRace] = []
            for race in candidates {
                guard race.isVagueLocation, let hint = race.cityHint else {
                    coordFiltered.append(race); continue
                }
                if let cc = await cityHintCoordinate(hint: hint, region: race.region) {
                    let distKm = CLLocation(latitude: sc.latitude, longitude: sc.longitude)
                        .distance(from: CLLocation(latitude: cc.latitude, longitude: cc.longitude)) / 1000.0
                    if distKm <= 20.0 { coordFiltered.append(race) }
                } else {
                    coordFiltered.append(race)  // geocoding failed → keep candidate
                }
            }
            if !coordFiltered.isEmpty {
                candidates = coordFiltered
            } else {
                return nil
            }
        }

        // Wait for venue geocoding only AFTER region filter narrows candidates.
        // Moving the wait here avoids blocking the first open when the city filter
        // would have eliminated all candidates anyway.
        while isGeocoding {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        // Step 3: single candidate — vague locations (일원) have no venue coordinates
        // so we cannot confirm by proximity; require user confirmation (weak).
        if candidates.count == 1 {
            let race = candidates[0]
            let strength: MatchStrength = race.isVagueLocation ? .weak : .strong
            return RaceSuggestion(primary: race, strength: strength, alternatives: [])
        }

        // Step 4: multiple candidates — coordinate check with route-aware 5 km threshold
        if let sc = startCoord {
            let nearby = candidates.filter { race in
                guard !race.isVagueLocation else { return false }
                guard let rc = race.startCoordinate else { return false }
                let distKm = minDistance(from: sc, to: rc, routeCoords: routeCoords) / 1000.0
                return distKm <= 5.0
            }
            if nearby.count == 1 {
                return RaceSuggestion(primary: nearby[0], strength: .strong, alternatives: [])
            }
            if nearby.count > 1 {
                if wasDismissed { return nil }
                return RaceSuggestion(primary: nearby[0], strength: .weak,
                                      alternatives: Array(nearby.dropFirst()))
            }
        }

        // Weak fallback: sort specific locations first, vague last
        let sorted = candidates.sorted { !$0.isVagueLocation && $1.isVagueLocation }
        if wasDismissed { return nil }
        return RaceSuggestion(primary: sorted[0], strength: .weak,
                              alternatives: sorted.count > 1 ? Array(sorted.dropFirst()) : [])
    }

    func matchFor(activityID: UUID) -> PersistedRaceMatch? {
        matches[activityID.uuidString]
    }

    // MARK: - Mutations

    func confirm(activityID: UUID, race: BundledRace, activityDistanceKm: Double) {
        let km = race.bestMatchingDistance(activityDistanceKm) ?? activityDistanceKm
        matches[activityID.uuidString] = PersistedRaceMatch(
            activityID: activityID, raceName: race.name, distanceKm: km,
            raceDate: race.date ?? Date(),
            isConfirmed: true, isDismissed: false, isManual: false)
        saveMatches()
    }

    func addManual(activityID: UUID, name: String, distanceKm: Double, date: Date) {
        matches[activityID.uuidString] = PersistedRaceMatch(
            activityID: activityID, raceName: name, distanceKm: distanceKm,
            raceDate: date, isConfirmed: true, isDismissed: false, isManual: true)
        saveMatches()
    }

    func markAsNotRace(activityID: UUID) {
        matches[activityID.uuidString] = PersistedRaceMatch(
            activityID: activityID, raceName: "", distanceKm: 0,
            raceDate: Date(), isConfirmed: false, isDismissed: true, isManual: false)
        saveMatches()
    }

    func removeMatch(activityID: UUID) {
        matches.removeValue(forKey: activityID.uuidString)
        saveMatches()
    }

    func resetDismissed(activityID: UUID) {
        matches.removeValue(forKey: activityID.uuidString)
        saveMatches()
    }

    // MARK: - Region helpers

    // Returns province token + city token so race regions like "수원시" also match.
    private func reverseGeocodeRegion(_ coord: CLLocationCoordinate2D) async -> [String] {
        let key = String(format: "%.4f,%.4f", coord.latitude, coord.longitude)
        if let cached = regionCache[key] { return cached }
        let placemarks = await geocoderService.reverseGeocodeLocation(
            CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        )
        var tokens: [String] = []
        if let pm = placemarks?.first {
            if let prov = Self.normalizeRegion(pm.administrativeArea) { tokens.append(prov) }
            if let city = pm.locality, !city.isEmpty { tokens.append(city) }
        }
        if !tokens.isEmpty { regionCache[key] = tokens }
        return tokens
    }

    private static func normalizeRegion(_ adminArea: String?) -> String? {
        guard let raw = adminArea else { return nil }
        let map: [(String, String)] = [
            ("서울특별시", "서울"), ("부산광역시", "부산"), ("대구광역시", "대구"),
            ("인천광역시", "인천"), ("광주광역시", "광주"), ("대전광역시", "대전"),
            ("울산광역시", "울산"), ("세종특별자치시", "세종"), ("경기도", "경기"),
            ("강원특별자치도", "강원"), ("강원도", "강원"), ("충청북도", "충북"),
            ("충청남도", "충남"), ("전북특별자치도", "전북"), ("전라북도", "전북"),
            ("전라남도", "전남"), ("경상북도", "경북"), ("경상남도", "경남"),
            ("제주특별자치도", "제주"),
        ]
        for (full, short) in map { if raw.hasPrefix(full) { return short } }
        return raw
    }

    private func regionMatches(_ race: BundledRace, _ runTokens: [String]) -> Bool {
        // Province-level check (unchanged logic)
        let raceRegion = race.region
        let provinceMatch = runTokens.contains {
            raceRegion == $0
                || raceRegion.hasPrefix($0)
                || $0.hasPrefix(raceRegion)
                || raceRegion.contains($0)
                || $0.contains(raceRegion)
        }
        guard provinceMatch else { return false }

        // City-level check: "성남 일원" → hint "성남".
        // If we have a user city token AND a race city hint, they must overlap.
        // Prevents same-province cross-city false matches (e.g. 성남 race ≠ 안산 run).
        if let hint = race.cityHint, runTokens.count > 1 {
            let userCity = runTokens.dropFirst().joined()
            let stripped = userCity
                .replacingOccurrences(of: "시", with: "")
                .replacingOccurrences(of: "군", with: "")
                .replacingOccurrences(of: "구", with: "")
            return hint.contains(stripped) || stripped.contains(hint)
                || userCity.contains(hint) || hint.contains(userCity)
        }
        return true
    }

    /// Geocodes a city hint (e.g. "성남", region "경기") to an approximate city-center
    /// coordinate. Cached in memory so subsequent calls are instant.
    private func cityHintCoordinate(hint: String, region: String) async -> CLLocationCoordinate2D? {
        let key = "\(hint)_\(region)"
        if let cached = cityHintCoordCache[key] { return cached }
        let coord = await geocode("\(hint) \(region)")
        if let c = coord { cityHintCoordCache[key] = c }
        return coord
    }

    private func minDistance(
        from start: CLLocationCoordinate2D,
        to venue: CLLocationCoordinate2D,
        routeCoords: [CLLocationCoordinate2D]
    ) -> Double {
        let venueLoc = CLLocation(latitude: venue.latitude, longitude: venue.longitude)
        var minDist = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: venueLoc)
        if !routeCoords.isEmpty {
            let step = max(1, routeCoords.count / 100)
            for i in Swift.stride(from: 0, to: routeCoords.count, by: step) {
                let d = CLLocation(latitude: routeCoords[i].latitude,
                                   longitude: routeCoords[i].longitude).distance(from: venueLoc)
                if d < minDist { minDist = d }
            }
        }
        return minDist
    }

    // MARK: - Persistence

    private func loadMatches() {
        guard let data = UserDefaults.standard.data(forKey: Self.matchesKey),
              let saved = try? JSONDecoder().decode([String: PersistedRaceMatch].self, from: data)
        else { return }
        matches = saved
    }

    private func saveMatches() {
        guard let data = try? JSONEncoder().encode(matches) else { return }
        UserDefaults.standard.set(data, forKey: Self.matchesKey)
    }

    // MARK: - JSON loading + geocoding

    private struct RaceFile: Decodable { let races: [BundledRace] }

    private func loadAndGeocodeRaces() async {
        var all: [BundledRace] = []

        // 1. Embedded 2025 + 2026 data (always available)
        var embeddedCount = 0
        for json in [Self.embedded2025JSON, Self.embedded2026JSON] {
            if let data = json.data(using: .utf8),
               let file = try? JSONDecoder().decode(RaceFile.self, from: data) {
                embeddedCount += file.races.count
                all.append(contentsOf: file.races)
            }
        }

        // 2. Additional races_YYYY.json from app bundle (future years)
        var bundleFileCount = 0
        var bundleRaceCount = 0
        if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) {
            for url in urls where url.lastPathComponent.hasPrefix("races_") {
                if let data = try? Data(contentsOf: url),
                   let file = try? JSONDecoder().decode(RaceFile.self, from: data) {
                    bundleFileCount += 1
                    bundleRaceCount += file.races.count
                    all.append(contentsOf: file.races)
                }
            }
        }

        guard !all.isEmpty else { return }

        // Restore geocache
        var cache: [String: [Double]] = [:]
        if let data = UserDefaults.standard.data(forKey: Self.geocacheKey),
           let cached = try? JSONDecoder().decode([String: [Double]].self, from: data) {
            cache = cached
        }
        for i in all.indices {
            if let coords = cache[all[i].id] {
                all[i].startLatitude  = coords[0]
                all[i].startLongitude = coords[1]
            }
        }
        races = all

        // Geocode non-vague locations without coordinates
        let toGeocode = all.filter { !$0.isVagueLocation && $0.startLatitude == nil }
        guard !toGeocode.isEmpty else { return }

        isGeocoding = true
        for race in toGeocode {
            let query = race.start + " " + race.region
            if let coord = await geocode(query) {
                cache[race.id] = [coord.latitude, coord.longitude]
                if let idx = races.firstIndex(where: { $0.id == race.id }) {
                    races[idx].startLatitude  = coord.latitude
                    races[idx].startLongitude = coord.longitude
                }
            }
            // Rate limiting is handled inside GeocoderService (1.3 s per request)
        }
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: Self.geocacheKey)
        }
        isGeocoding = false
    }

    private func geocode(_ address: String) async -> CLLocationCoordinate2D? {
        await geocoderService.geocodeAddress(address)
    }

    // MARK: - Embedded race data (문화체육관광부 국내마라톤대회 정보, 2025년)
    // Source: 공공데이터포털 "문화체육관광부_국내마라톤대회 정보"
    // Additional years: add races_2026.json (etc.) to the app bundle — auto-merged on startup.

    // MARK: - Embedded race data (문화체육관광부 국내마라톤대회 정보, 2026년)
    private static let embedded2026JSON = #"""
    {"year":2026,"count":255,"races":[
    {"name":"2026 새해 일출런","date":"2026-01-01","startTime":"08:00","region":"서울","start":"신정교하부 육상트랙구장","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 선양 맨몸마라톤","date":"2026-01-01","startTime":"08:00","region":"대전","start":"대전 일원","distancesKm":[7.0],"tags":[],"nonStandard":false},
    {"name":"제2회 새해맞이 거제 산방산 임도런","date":"2026-01-03","startTime":"08:00","region":"경남","start":"거제 산방산 일원","distancesKm":[15.0,25.0,35.0],"tags":[],"nonStandard":false},
    {"name":"2026 전마협 새해 맞이 마라톤","date":"2026-01-04","startTime":"08:00","region":"충남","start":"충남 일원","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제18회 전국새해알몸마라톤","date":"2026-01-04","startTime":"08:00","region":"대구","start":"대구 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 미즈노 페스타","date":"2026-01-10","startTime":"08:00","region":"경기","start":"경기 일원","distancesKm":[],"tags":[],"nonStandard":true},
    {"name":"제18회 의림지삼한초록길알몸마라톤","date":"2026-01-11","startTime":"08:00","region":"충북","start":"제천 의림지 일원","distancesKm":[7.0],"tags":[],"nonStandard":false},
    {"name":"제20회 여수해양마라톤","date":"2026-01-11","startTime":"08:00","region":"전남","start":"여수 일원","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 코리아 스노우 트레일","date":"2026-01-17","startTime":"08:00","region":"강원","start":"강원 일원","distancesKm":[13.0,30.0],"tags":[],"nonStandard":false},
    {"name":"2026 전마협 제주 4Full 마라톤","date":"2026-01-23","startTime":"08:00","region":"제주","start":"제주 일원","distancesKm":[42.195],"tags":[],"nonStandard":false},
    {"name":"2026 똥바람 알통구보대회","date":"2026-01-24","startTime":"08:00","region":"강원","start":"강원 일원","distancesKm":[6.32],"tags":[],"nonStandard":false},
    {"name":"2026 전마협 제주 10km 마라톤","date":"2026-01-25","startTime":"08:00","region":"제주","start":"제주 일원","distancesKm":[10.0],"tags":[],"nonStandard":false},
    {"name":"제2회 한강 서울 하프 마라톤","date":"2026-01-25","startTime":"08:00","region":"서울","start":"상암 월드컵공원 평화광장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 인사이더런 W","date":"2026-01-31","startTime":"08:00","region":"경기","start":"경기 일원","distancesKm":[10.0],"tags":[],"nonStandard":false},
    {"name":"2026 화성 궁평항 동계 훈련 마라톤","date":"2026-01-31","startTime":"08:00","region":"경기","start":"화성 궁평항 일원","distancesKm":[10.0,21.0975,32.0],"tags":[],"nonStandard":false},
    {"name":"2026 인사이더런 W (2월)","date":"2026-02-01","startTime":"08:00","region":"경기","start":"경기 일원","distancesKm":[10.0],"tags":[],"nonStandard":false},
    {"name":"2026 전마협 별들의 전쟁 & 꽃들의 전쟁 클럽대항전","date":"2026-02-08","startTime":"08:00","region":"충남","start":"충남 일원","distancesKm":[20.0],"tags":[],"nonStandard":false},
    {"name":"제3회 산들소리향기마라톤","date":"2026-02-08","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 평창 대관령 알몸 마라톤","date":"2026-02-14","startTime":"08:00","region":"강원","start":"대관령면 횡계리 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 순천만국가정원 윷놀이런","date":"2026-02-18","startTime":"08:00","region":"전남","start":"순천만국가정원","distancesKm":[3.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 전마협 청주 무심천 투데이 마라톤 (토)","date":"2026-02-21","startTime":"08:00","region":"충북","start":"청주 무심천 둔치","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 청춘릴레이 마라톤","date":"2026-02-21","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제7회 휴먼레이스","date":"2026-02-21","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"희망드림 제23회 동계 국제 마라톤","date":"2026-02-21","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0,21.0975,32.0],"tags":[],"nonStandard":false},
    {"name":"2026 경기수원국제하프마라톤","date":"2026-02-22","startTime":"08:00","region":"경기","start":"수원 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 고구려 마라톤","date":"2026-02-22","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,21.0975,32.0,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 대구국제마라톤 (대구마라톤)","date":"2026-02-22","startTime":"08:00","region":"대구","start":"대구스타디움 일원","distancesKm":[5.3,10.9,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 전마협 청주 무심천 투데이 마라톤 (일)","date":"2026-02-22","startTime":"08:00","region":"충북","start":"청주 무심천 둔치","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 제주MBC 국제평화마라톤","date":"2026-02-22","startTime":"08:00","region":"제주","start":"제주 일원","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 챌린지 레이스","date":"2026-02-22","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,21.0975,32.0,42.195],"tags":[],"nonStandard":false},
    {"name":"제22회 밀양아리랑마라톤","date":"2026-02-22","startTime":"08:00","region":"경남","start":"밀양 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제9회 산불조심 한국서울마라톤","date":"2026-02-22","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 보스턴 영웅 마라톤","date":"2026-02-28","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"3.1절 기념 제19회 120km 무박만세걷기","date":"2026-02-28","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,32.0,60.0,120.0],"tags":[],"nonStandard":false},
    {"name":"JUST RUN10 세종","date":"2026-02-28","startTime":"08:00","region":"세종","start":"세종 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 구미 박정희 마라톤","date":"2026-03-01","startTime":"08:00","region":"경북","start":"구미 일원","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 머니투데이방송 삼일절 마라톤","date":"2026-03-01","startTime":"08:00","region":"서울","start":"뚝섬한강공원 수변무대","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 환경사랑부산 K-런","date":"2026-03-01","startTime":"08:00","region":"부산","start":"부산 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"3.1절 107주년 기념 단축 마라톤","date":"2026-03-01","startTime":"08:00","region":"인천","start":"인천 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"3.1절기념 제27회 건강달리기","date":"2026-03-01","startTime":"08:00","region":"강원","start":"강원 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"삼일절 컴포트 선언 러닝","date":"2026-03-01","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[19.19],"tags":[],"nonStandard":false},
    {"name":"제13회 안중근 평화 마라톤","date":"2026-03-01","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제61회 광주일보 3.1절 전국마라톤","date":"2026-03-01","startTime":"08:00","region":"전남","start":"광주 일원","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 Run your way HALF RACE SEOUL","date":"2026-03-02","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[21.0975],"tags":[],"nonStandard":false},
    {"name":"대전트레일 스피드런","date":"2026-03-07","startTime":"08:00","region":"대전","start":"대전 일원","distancesKm":[16.0,30.0],"tags":[],"nonStandard":false},
    {"name":"제21회 부산 비치울트라 마라톤","date":"2026-03-07","startTime":"08:00","region":"부산","start":"부산 해운대 일원","distancesKm":[50.0,100.0],"tags":[],"nonStandard":false},
    {"name":"제2회 서울경기육상연합 하프 마라톤","date":"2026-03-07","startTime":"08:00","region":"경기","start":"경기 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제4회 코리아오픈 레이스","date":"2026-03-07","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 MBN 블루레이스 거제","date":"2026-03-08","startTime":"08:00","region":"경남","start":"거제 일원","distancesKm":[4.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 고양특례시 하프마라톤","date":"2026-03-08","startTime":"08:00","region":"경기","start":"고양 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 부천국제10km로드레이스","date":"2026-03-08","startTime":"08:00","region":"경기","start":"부천 일원","distancesKm":[3.5,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 성주참외 전국마라톤","date":"2026-03-08","startTime":"08:00","region":"경북","start":"성주 일원","distancesKm":[5.0,10.0,21.0975,30.0],"tags":[],"nonStandard":false},
    {"name":"2026 전국민 러닝크루 패밀리 마라톤","date":"2026-03-08","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제12회 여수시장배 트레일레이스","date":"2026-03-08","startTime":"08:00","region":"전남","start":"여수 일원","distancesKm":[14.0],"tags":[],"nonStandard":false},
    {"name":"제16회 여의도 벚꽃 마라톤","date":"2026-03-08","startTime":"08:00","region":"서울","start":"여의도 한강공원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 금산 인삼 마라톤","date":"2026-03-14","startTime":"08:00","region":"충남","start":"금산 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 제1회 보은 보청천 마라톤","date":"2026-03-14","startTime":"08:00","region":"충북","start":"보은 보청천 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제20회 창녕부곡 온천마라톤","date":"2026-03-14","startTime":"08:00","region":"경남","start":"창녕 부곡 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 서울마라톤 (제96회 동아마라톤)","date":"2026-03-15","startTime":"08:00","region":"서울","start":"광화문광장","distancesKm":[10.0,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 JUST RUN10 청주","date":"2026-03-21","startTime":"08:00","region":"충북","start":"청주 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 남해트레일레이스","date":"2026-03-21","startTime":"08:00","region":"경남","start":"남해 일원","distancesKm":[40.0],"tags":[],"nonStandard":false},
    {"name":"2026 내포마라톤","date":"2026-03-21","startTime":"08:00","region":"충남","start":"충남 내포 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 지리산봄꽃레이스","date":"2026-03-21","startTime":"08:00","region":"전남","start":"지리산 일원","distancesKm":[13.0,24.0],"tags":[],"nonStandard":false},
    {"name":"제1회 춘천 소양강마라톤","date":"2026-03-21","startTime":"08:00","region":"강원","start":"춘천 소양강 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제6회 2026 버킷런","date":"2026-03-21","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 HEAT & RUN","date":"2026-03-22","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 산불조심 한국남산우정마라톤","date":"2026-03-22","startTime":"08:00","region":"서울","start":"남산 일원","distancesKm":[8.0,16.0],"tags":[],"nonStandard":false},
    {"name":"2026 정읍동학마라톤","date":"2026-03-22","startTime":"08:00","region":"전북","start":"정읍 일원","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"서울 K-마라톤대회","date":"2026-03-22","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제24회 성우하이텍배 KNN 환경마라톤","date":"2026-03-22","startTime":"08:00","region":"부산","start":"부산 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제26회 인천국제하프마라톤","date":"2026-03-22","startTime":"08:00","region":"인천","start":"인천문학경기장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제2회 영광 광풍 마라톤","date":"2026-03-22","startTime":"08:00","region":"전남","start":"전남 영광 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제3회 불패마라톤","date":"2026-03-22","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 금강울트라마라톤","date":"2026-03-28","startTime":"08:00","region":"세종","start":"세종 금강 일원","distancesKm":[50.0,100.0],"tags":[],"nonStandard":false},
    {"name":"2026 봄바람 유러닝페스타","date":"2026-03-28","startTime":"08:00","region":"경기","start":"경기 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 여수 영취산 진달래 트레일레이스","date":"2026-03-28","startTime":"08:00","region":"전남","start":"여수 영취산 일원","distancesKm":[12.0],"tags":[],"nonStandard":false},
    {"name":"2026 제3회 구리시 걷기&트레일런","date":"2026-03-28","startTime":"08:00","region":"경기","start":"경기 구리 망우산둘레길","distancesKm":[6.4,9.0],"tags":[],"nonStandard":false},
    {"name":"2026 팀 K리그 런","date":"2026-03-28","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0],"tags":[],"nonStandard":false},
    {"name":"제23회 태화강 마라톤","date":"2026-03-28","startTime":"08:00","region":"울산","start":"태화강 둔치","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제28회 서귀포 유채꽃국제걷기대회","date":"2026-03-28","startTime":"08:00","region":"제주","start":"서귀포 일원","distancesKm":[5.0,12.0,22.0],"tags":[],"nonStandard":false},
    {"name":"제2회 의성마늘마라톤","date":"2026-03-28","startTime":"08:00","region":"경북","start":"의성 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제42회 코오롱구간마라톤대회","date":"2026-03-28","startTime":"08:00","region":"경북","start":"경북 일원","distancesKm":[],"tags":[],"nonStandard":true},
    {"name":"2026 무주반딧불 하프마라톤","date":"2026-03-29","startTime":"08:00","region":"전북","start":"무주 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제20회 정남진장흥 전국마라톤","date":"2026-03-29","startTime":"08:00","region":"전남","start":"장흥 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제25회 합천벚꽃마라톤","date":"2026-03-29","startTime":"08:00","region":"경남","start":"합천 일원","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제33회 315마라톤","date":"2026-03-29","startTime":"08:00","region":"경남","start":"경남 창원 마산 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제33회 경주벚꽃마라톤","date":"2026-04-04","startTime":"08:00","region":"경북","start":"경주 보덕동행정복지센터 헬기장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 대구국제마라톤","date":"2026-04-05","startTime":"08:00","region":"대구","start":"대구스타디움","distancesKm":[5.3,10.9,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 인천마라톤 (상반기)","date":"2026-04-11","startTime":"08:00","region":"인천","start":"인천문학경기장","distancesKm":[5.0,10.0,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 광주마라톤","date":"2026-04-12","startTime":"08:00","region":"광주","start":"광주월드컵경기장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 DMZ 평화마라톤","date":"2026-04-19","startTime":"08:00","region":"경기","start":"임진각 평화누리","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 군산새만금마라톤","date":"2026-04-19","startTime":"08:00","region":"전북","start":"군산 새만금 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 서울하프마라톤 (조선일보)","date":"2026-04-26","startTime":"08:00","region":"서울","start":"광화문광장","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 제주국제마라톤 (평화의섬)","date":"2026-04-26","startTime":"08:00","region":"제주","start":"제주대학교 대운동장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"불수사도북 트레일런","date":"2026-05-03","startTime":"08:00","region":"서울","start":"공릉동 백세문","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"2026 전주마라톤","date":"2026-05-10","startTime":"08:00","region":"전북","start":"전주종합경기장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 서울신문 하프마라톤","date":"2026-05-16","startTime":"08:00","region":"서울","start":"상암 평화의공원 평화광장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 강릉마라톤","date":"2026-05-17","startTime":"08:00","region":"강원","start":"강릉 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 물사랑 낙동강 200km 울트라마라톤","date":"2026-06-05","startTime":"21:00","region":"부산 사하구","start":"을숙도물문화센터","distancesKm":[100.0,200.0],"tags":[],"nonStandard":false},
    {"name":"2026 도시가스 트레일 온 런 강원","date":"2026-06-06","startTime":"09:00","region":"강원 강릉시","start":"강릉경포호수광장","distancesKm":[4.4,12.0,24.0],"tags":["트레일"],"nonStandard":false},
    {"name":"2026 명품-FAAB 한강 브릿지런","date":"2026-06-06","startTime":"08:00","region":"경기 구리시","start":"구리 한강시민공원","distancesKm":[60.0],"tags":["울트라"],"nonStandard":false},
    {"name":"2026 춘천봄내마라톤","date":"2026-06-06","startTime":"09:00","region":"강원 춘천시","start":"춘천시청 호반광장 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 푸른하늘런","date":"2026-06-06","startTime":"08:00","region":"서울 마포구","start":"상암 월드컵공원 평화광장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 한라산 트레일러닝","date":"2026-06-06","startTime":"05:00","region":"제주 서귀포시","start":"서귀포 돈내코 야영장","distancesKm":[10.0,36.0,50.0,100.0,160.9],"tags":["트레일"],"nonStandard":false},
    {"name":"NAMHAE 250K - RUN TO SEA","date":"2026-06-06","startTime":"06:00","region":"경남 남해군","start":"남해 송정솔바람해변","distancesKm":[10.0,20.0],"tags":[],"nonStandard":false},
    {"name":"제28회 양평이봉주마라톤","date":"2026-06-06","startTime":"08:30","region":"경기 양평군","start":"양평강상체육공원","distancesKm":[4.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제9회 남한산성 트레일러닝","date":"2026-06-06","startTime":"09:00","region":"서울 송파구","start":"마천역 1번출구","distancesKm":[8.0,15.0],"tags":["트레일"],"nonStandard":false},
    {"name":"2026 THE RACE DAEGU 10K","date":"2026-06-07","startTime":"08:00","region":"대구 수성구","start":"대구스타디움 동편광장","distancesKm":[10.0],"tags":[],"nonStandard":false},
    {"name":"2026 iM뱅크 코리아 오픈 마라톤","date":"2026-06-07","startTime":"07:30","region":"서울 영등포구","start":"여의도공원 문화의마당","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 마인드마라톤","date":"2026-06-07","startTime":"07:30","region":"서울 중구","start":"서울광장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제11회 너릿재마라톤","date":"2026-06-07","startTime":"08:00","region":"전남 화순군","start":"화순 셀레브 카페 입구","distancesKm":[8.0,16.0,24.0],"tags":[],"nonStandard":false},
    {"name":"제30회 제주관광마라톤 축제","date":"2026-06-07","startTime":"08:00","region":"제주 제주시","start":"구좌종합운동장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 강릉헌화로11K Run","date":"2026-06-13","startTime":"08:00","region":"강원","start":"강릉 헌화로 일원","distancesKm":[11.0],"tags":[],"nonStandard":false},
    {"name":"2026 성남마라톤","date":"2026-06-13","startTime":"08:00","region":"경기","start":"성남 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 운탄고도 스카이레이스","date":"2026-06-13","startTime":"08:00","region":"강원","start":"강원 탄광지대 일원","distancesKm":[21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 제23회 빛고을 울트라마라톤","date":"2026-06-13","startTime":"08:00","region":"광주","start":"광주 일원","distancesKm":[50.0,100.0],"tags":[],"nonStandard":false},
    {"name":"2026 컬처런","date":"2026-06-13","startTime":"09:00","region":"인천 중구","start":"영종도 씨사이드파크 일원","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제12회 시각장애인과 함께하는 어울림 마라톤","date":"2026-06-13","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제22회 설악국제트레킹페스티벌","date":"2026-06-13","startTime":"08:00","region":"강원","start":"설악산 일원","distancesKm":[5.0,10.0,20.0],"tags":[],"nonStandard":false},
    {"name":"2026 김해숲길마라톤","date":"2026-06-14","startTime":"08:30","region":"경남 김해시","start":"김해종합운동장 및 숲길 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 대전월드런마라톤축제","date":"2026-06-14","startTime":"08:00","region":"대전","start":"대전 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 제21회 울릉도전국마라톤","date":"2026-06-14","startTime":"05:00","region":"경북 울릉군","start":"울릉예술문화체험장","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제22회 영덕해변전국마라톤","date":"2026-06-14","startTime":"08:30","region":"경북 영덕군","start":"고래불해수욕장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 웰메이드런","date":"2026-06-20","startTime":"07:30","region":"경기 남양주시","start":"남양주한강공원 삼패지구","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"JUST RUN 10 성남","date":"2026-06-20","startTime":"08:00","region":"경기","start":"성남 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제16회 국민행복마라톤","date":"2026-06-20","startTime":"09:00","region":"서울 광진구","start":"서울 뚝섬한강공원 수변광장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제25회 충주마라톤","date":"2026-06-20","startTime":"07:30","region":"충북 충주시","start":"충주종합운동장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제2회 희망 서울 마라톤","date":"2026-06-20","startTime":"08:00","region":"서울 영등포구","start":"여의도공원 문화의마당","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 람사르습지 밤섬런","date":"2026-06-21","startTime":"08:00","region":"서울 영등포구","start":"여의도 한강공원 물빛무대","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 보은 속리산 말티재 힐링 알몸 마라톤","date":"2026-06-21","startTime":"07:50","region":"충북 보은군","start":"보은군 속리산 말티고개","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 참행복나눔 마라톤","date":"2026-06-21","startTime":"08:00","region":"서울 마포구","start":"상암 월드컵공원 평화광장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"월리를 찾아라런 in 서울 2026","date":"2026-06-21","startTime":"07:30","region":"서울 영등포구","start":"여의도공원 문화의마당","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제11회 소백산 국망봉 트레일","date":"2026-06-21","startTime":"08:00","region":"경북","start":"소백산 국망봉 일원","distancesKm":[10.0,28.0],"tags":[],"nonStandard":false},
    {"name":"2026 순천 치유 미식 트레일런","date":"2026-06-27","startTime":"08:00","region":"전남","start":"순천 일원","distancesKm":[7.0,14.0],"tags":[],"nonStandard":false},
    {"name":"2026 큰별 하프 마라톤","date":"2026-06-27","startTime":"08:00","region":"서울 마포구","start":"상암 월드컵공원 평화광장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 서울런","date":"2026-06-28","startTime":"08:00","region":"서울 영등포구","start":"여의도공원 문화의마당","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 울산남구청장배 육상대회","date":"2026-06-28","startTime":"08:30","region":"울산 남구","start":"태화강둔치 (태화다리 밑)","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 전국블루베리마라톤축제","date":"2026-06-28","startTime":"08:00","region":"전북 정읍시","start":"정읍 대흥무지개센터","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"THE PACER SERIES","date":"2026-06-28","startTime":"08:00","region":"충북 청주시","start":"청남대 (청주시 상당구 문의면)","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"송도 이봉주 마라톤","date":"2026-06-28","startTime":"08:00","region":"인천 연수구","start":"인천대학교 송도캠퍼스","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제1회 리프레시런","date":"2026-06-28","startTime":"08:00","region":"경기 하남시","start":"하남 미사경정공원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제20회 강북구청장배 마라톤","date":"2026-06-28","startTime":"08:30","region":"서울 강북구","start":"강북구 도봉로102길 21","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 전마협 하계 무료 훈련 마라톤","date":"2026-07-04","startTime":"08:00","region":"충남","start":"충남 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"IRON RUN 2026","date":"2026-07-04","startTime":"08:00","region":"경북 포항시","start":"포항 영일대해수욕장 장미광장","distancesKm":[3.8,7.87,15.38],"tags":[],"nonStandard":false},
    {"name":"제10회 노원구청장배 겸 회장배마라톤","date":"2026-07-05","startTime":"08:30","region":"서울 노원구","start":"창동교 나눔의 광장","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제8회 인왕산 서울 트레일런","date":"2026-07-05","startTime":"08:00","region":"서울","start":"인왕산 일원","distancesKm":[10.0],"tags":[],"nonStandard":false},
    {"name":"2026 전마협 무주 풀코스 마라톤","date":"2026-07-11","startTime":"06:30","region":"전북 무주군","start":"무주 소이나루 공원","distancesKm":[4.0,8.0,12.0,24.0,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 광제산 트레일 런","date":"2026-07-12","startTime":"09:10","region":"경남 진주시","start":"홍지소류지 (진주 명석면 계원리)","distancesKm":[5.0,10.0,21.0975],"tags":["트레일"],"nonStandard":false},
    {"name":"2026 울릉도 국제 트레일러닝","date":"2026-07-12","startTime":"08:00","region":"경북(울릉도)","start":"울릉도 일원","distancesKm":[27.0,40.0],"tags":[],"nonStandard":false},
    {"name":"2026 코리아 나이트 런 태백","date":"2026-07-18","startTime":"17:00","region":"강원 태백시","start":"O2 리조트","distancesKm":[7.0,17.0,28.0],"tags":[],"nonStandard":false},
    {"name":"제2회 울릉나이트런","date":"2026-07-18","startTime":"08:00","region":"경북(울릉도)","start":"울릉도 일원","distancesKm":[10.0],"tags":[],"nonStandard":false},
    {"name":"2026 청계산.인릉산 트레일런","date":"2026-07-19","startTime":"08:00","region":"서울 서초구","start":"청계산 옛골 (화물터미널)","distancesKm":[12.0,21.0975],"tags":["트레일"],"nonStandard":false},
    {"name":"2026 쿨밸리트레일레이스","date":"2026-07-19","startTime":"08:00","region":"전북","start":"전북 일원","distancesKm":[18.0],"tags":[],"nonStandard":false},
    {"name":"제16회 태종대혹서기전국마라톤","date":"2026-07-19","startTime":"06:00","region":"부산 영도구","start":"태종대공원","distancesKm":[7.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"사우나런 in 올림픽공원","date":"2026-07-31","startTime":"08:00","region":"서울 송파구","start":"올림픽공원 인근","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제1회 테마임도 트레일런","date":"2026-08-08","startTime":"07:00","region":"부산 금정구","start":"부산스포원","distancesKm":[50.0],"tags":["트레일"],"nonStandard":false},
    {"name":"2026 815런","date":"2026-08-15","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[8.15],"tags":[],"nonStandard":false},
    {"name":"2026 안양천 달빛 나이트런","date":"2026-08-15","startTime":"18:30","region":"서울 양천구","start":"신정교 하부 영롱이 억새구장","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 장수 나이트 트레일","date":"2026-08-15","startTime":"19:00","region":"전북 장수군","start":"장수종합경기장","distancesKm":[38.0],"tags":["트레일"],"nonStandard":false},
    {"name":"영남알프스9봉 트레일 레이스","date":"2026-08-15","startTime":"14:00","region":"경남 밀양시","start":"청운산장","distancesKm":[87.0],"tags":["트레일"],"nonStandard":false},
    {"name":"제38회 지리산화대종주 UTMB","date":"2026-08-15","startTime":"03:00","region":"전남 구례군","start":"화엄사주차장","distancesKm":[40.0,48.0],"tags":[],"nonStandard":false},
    {"name":"2026 금수산트레일러닝대회","date":"2026-08-23","startTime":"08:00","region":"충북 제천시","start":"청풍리조트","distancesKm":[13.0,22.0],"tags":[],"nonStandard":false},
    {"name":"2026 대구세계마스터즈 10km대회","date":"2026-08-23","startTime":"07:00","region":"대구 수성구","start":"대구스타디움 일원","distancesKm":[10.0],"tags":[],"nonStandard":false},
    {"name":"2026 단양달빛레이스","date":"2026-08-29","startTime":"19:00","region":"충북 단양군","start":"단양생태체육공원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 대구세계마스터즈 하프마라톤대회","date":"2026-08-30","startTime":"07:00","region":"대구 수성구","start":"신천동로 일원","distancesKm":[21.0975],"tags":[],"nonStandard":false},
    {"name":"제3회 GO대관령 국제 트레일런","date":"2026-08-30","startTime":"07:30","region":"강원 평창군","start":"평창동계올림픽기념공원","distancesKm":[10.0,20.18,44.0],"tags":["트레일"],"nonStandard":false},
    {"name":"제3회 한강 서울 하프 마라톤","date":"2026-08-30","startTime":"08:00","region":"서울 영등포구","start":"여의도 한강공원 물빛광장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 다이나핏 태백 트레일","date":"2026-09-05","startTime":"06:00","region":"강원 태백시","start":"태백 소원지 오토캠핑장","distancesKm":[32.0,50.0],"tags":["트레일"],"nonStandard":false},
    {"name":"2026 하반기 JUST RUN10 세종","date":"2026-09-05","startTime":"08:00","region":"세종특별자치시","start":"세종마루공원 밑 금강변","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제12회 I LOVE 방송대 마라톤","date":"2026-09-05","startTime":"08:00","region":"서울 마포구","start":"상암동 평화광장","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제20회 순천만울트라마라톤대회","date":"2026-09-05","startTime":"08:00","region":"전남","start":"순천만 일원","distancesKm":[102.0],"tags":[],"nonStandard":false},
    {"name":"제23회 철원DMZ국제평화마라톤","date":"2026-09-05","startTime":"09:00","region":"강원 철원군","start":"철원 고석정","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제2회 2026 Vrun","date":"2026-09-05","startTime":"09:00","region":"서울 양천구","start":"신정교하부 육상트랙구장","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 봉화송이 전국마라톤","date":"2026-09-06","startTime":"10:00","region":"경북 봉화군","start":"봉화공설운동장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 샌드런 IN 영덕","date":"2026-09-06","startTime":"10:00","region":"경북 영덕군","start":"영덕 대진해수욕장","distancesKm":[4.0,8.0],"tags":[],"nonStandard":false},
    {"name":"2026 전마협회장배 청주마라톤","date":"2026-09-06","startTime":"07:30","region":"충북 청주시","start":"청주 무심천 체육공원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제11회 김대중 평화 마라톤 대회","date":"2026-09-06","startTime":"08:00","region":"서울 광진구","start":"뚝섬 한강공원 수변무대","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제9회 인천 서구청장배 단축마라톤","date":"2026-09-06","startTime":"08:30","region":"인천 서구","start":"청라호수공원 멀티프라자 트랙","distancesKm":[4.3,10.0],"tags":[],"nonStandard":false},
    {"name":"희망드림 제23회 새벽강변 국제마라톤","date":"2026-09-06","startTime":"07:30","region":"서울 양천구","start":"목동운동장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 양양 강변 전국 마라톤","date":"2026-09-12","startTime":"10:00","region":"강원 양양군","start":"양양군 웰컴센터","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"빵트레일런 2026","date":"2026-09-12","startTime":"08:00","region":"강원 정선군","start":"정선 하이원리조트","distancesKm":[10.0,20.0,30.0],"tags":["트레일"],"nonStandard":false},
    {"name":"제2회 초록우산 런웨이 마라톤","date":"2026-09-12","startTime":"08:00","region":"대전 유성구","start":"대전엑스포시민광장","distancesKm":[3.0,5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 런서울런","date":"2026-09-13","startTime":"07:30","region":"서울 중구","start":"서울광장","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 울진금강송힐링마라톤","date":"2026-09-13","startTime":"09:00","region":"경북 울진군","start":"울진종합운동장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 포항이차전지전국마라톤","date":"2026-09-13","startTime":"08:00","region":"경북 포항시","start":"포항운하관주차장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제14회 설악산 공룡능선 UTMB","date":"2026-09-13","startTime":"08:00","region":"강원","start":"설악산 일원","distancesKm":[22.0,27.0],"tags":[],"nonStandard":false},
    {"name":"제16회 스마일 런 페스티벌","date":"2026-09-13","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제26회 강화해변마라톤대회","date":"2026-09-13","startTime":"08:30","region":"인천 강화군","start":"강화함상공원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 금산인삼축제 마라톤","date":"2026-09-19","startTime":"08:30","region":"충남 금산군","start":"금산세계인삼엑스포주차장","distancesKm":[4.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"서울수복 75주년 기념 아라뱃길 나이트워크","date":"2026-09-19","startTime":"08:00","region":"인천","start":"인천 아라뱃길 일원","distancesKm":[5.0,20.0,30.0,66.0],"tags":[],"nonStandard":false},
    {"name":"제18회 사이버 영토 수호 마라톤","date":"2026-09-19","startTime":"08:00","region":"서울 영등포구","start":"여의도 물빛무대 앞 광장","distancesKm":[3.0,5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 공주마라톤","date":"2026-09-20","startTime":"08:00","region":"충남 공주시","start":"공주시민운동장","distancesKm":[10.0,21.0975,32.0,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 동대문마라톤","date":"2026-09-20","startTime":"08:30","region":"서울 동대문구","start":"중랑천 제1수변공원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 한돈런","date":"2026-09-20","startTime":"08:00","region":"경기 하남시","start":"미사경정공원 조정경기장","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026(20회) 선사마라톤 축제","date":"2026-09-20","startTime":"09:00","region":"서울 강동구","start":"서울 암사동 유적 앞 특설무대","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제19회 가평자라섬 전국마라톤","date":"2026-09-20","startTime":"08:30","region":"경기 가평군","start":"가평종합운동장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제2회 마포구청장배 마라톤 대회","date":"2026-09-20","startTime":"08:30","region":"서울 마포구","start":"상암 월드컵공원 평화광장","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 서산 코스모스 황금들녘 마라톤 대회","date":"2026-10-03","startTime":"09:00","region":"충남 서산시","start":"서산스포츠테마파크","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 완주트레일런","date":"2026-10-03","startTime":"07:00","region":"전북 완주군","start":"완주군 고산자연휴양림","distancesKm":[36.0],"tags":["트레일"],"nonStandard":false},
    {"name":"2026 천사데이기념 동두천천사마라톤","date":"2026-10-03","startTime":"09:00","region":"경기 동두천시","start":"동두천 캠프보산","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제25회 김제새만금 지평선 전국마라톤","date":"2026-10-03","startTime":"09:00","region":"전북 김제시","start":"김제시민운동장 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제25회 앵봉산 서울트레일러닝","date":"2026-10-03","startTime":"08:00","region":"서울","start":"앵봉산 일원","distancesKm":[5.0,18.0],"tags":[],"nonStandard":false},
    {"name":"2026 YTN 서울투어마라톤","date":"2026-10-04","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 안동마라톤","date":"2026-10-04","startTime":"08:00","region":"경북 안동시","start":"안동시민운동장","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 파주북시티마라톤","date":"2026-10-04","startTime":"08:40","region":"경기 파주시","start":"파주출판도시","distancesKm":[3.0,5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 홍천사랑마라톤","date":"2026-10-04","startTime":"09:00","region":"강원 홍천군","start":"홍천종합운동장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제20회 달서하프마라톤","date":"2026-10-04","startTime":"08:30","region":"대구 달서구","start":"대구 달서구 호림강나루공원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 서울오픈마라톤","date":"2026-10-05","startTime":"07:30","region":"서울 종로구","start":"광화문광장","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제26회 홍성마라톤","date":"2026-10-09","startTime":"08:00","region":"충남 홍성군","start":"홍주종합경기장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 경포마라톤","date":"2026-10-10","startTime":"08:30","region":"강원 강릉시","start":"강릉 경포해변","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제5회 무등산지오마라톤","date":"2026-10-10","startTime":"07:00","region":"전남 화순군","start":"화순 금호스파리조트","distancesKm":[5.0,10.0,21.0975,30.0],"tags":[],"nonStandard":false},
    {"name":"제7회 천안삼거리 흥타령울트라마라톤","date":"2026-10-10","startTime":"08:00","region":"충남","start":"천안 일원","distancesKm":[60.0,100.0],"tags":[],"nonStandard":false},
    {"name":"제9회 거제시장배 섬꽃 전국 마라톤","date":"2026-10-10","startTime":"08:30","region":"경남 거제시","start":"거제스포츠파크","distancesKm":[4.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 MBN 전국 나주 마라톤대회","date":"2026-10-11","startTime":"08:00","region":"전남 나주시","start":"나주종합스포츠파크","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 서울레이스","date":"2026-10-11","startTime":"07:30","region":"서울 중구","start":"서울광장","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 평택항마라톤","date":"2026-10-11","startTime":"09:00","region":"경기 평택시","start":"평택항 엠에스로지스틱 일원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제10회 가을철 산불조심마라톤","date":"2026-10-11","startTime":"08:00","region":"서울 강남구","start":"광평교운동장","distancesKm":[5.0,10.0,21.0975,31.0,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 서울달리기대회","date":"2026-10-17","startTime":"08:00","region":"서울","start":"여의도 한강공원","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 정선동강 마라톤","date":"2026-10-17","startTime":"09:00","region":"강원 정선군","start":"정선생태체험학습장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제24회 청원생명쌀대청호마라톤","date":"2026-10-17","startTime":"08:40","region":"충북 청주시","start":"문의체육공원","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 대전마라톤","date":"2026-10-18","startTime":"08:00","region":"대전","start":"대전 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"그린스텝 2026","date":"2026-10-18","startTime":"09:00","region":"전남 해남군","start":"해남 솔라시도","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제22회 대구 북구사랑 마라톤","date":"2026-10-18","startTime":"09:00","region":"대구 북구","start":"금호강 산격야영장","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제23회 여주 세종대왕 마라톤","date":"2026-10-18","startTime":"08:30","region":"경기 여주시","start":"여주 현암지구공원","distancesKm":[4.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제25회 대청호마라톤","date":"2026-10-18","startTime":"09:00","region":"대전 대덕구","start":"대청공원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제34회 경주국제마라톤","date":"2026-10-18","startTime":"08:00","region":"경북","start":"경주시민운동장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 제3회 감성런","date":"2026-10-24","startTime":"09:00","region":"서울 양천구","start":"신정교하부 육상트랙구장","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 청송사과트레일런","date":"2026-10-25","startTime":"10:00","region":"경북 청송군","start":"청송군민운동장","distancesKm":[5.0,10.0,21.0975],"tags":["트레일"],"nonStandard":false},
    {"name":"2026 춘천마라톤","date":"2026-10-25","startTime":"09:00","region":"강원 춘천시","start":"춘천 공지천공원","distancesKm":[10.0,42.195],"tags":[],"nonStandard":false},
    {"name":"K-RUN 챌린지","date":"2026-10-25","startTime":"09:00","region":"서울 광진구","start":"서울 뚝섬한강공원 수변광장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제19회 청도반시 전국마라톤","date":"2026-10-25","startTime":"09:30","region":"경북 청도군","start":"청도공설운동장","distancesKm":[5.9,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 JTBC 마라톤","date":"2026-11-01","startTime":"08:00","region":"서울 마포구","start":"상암 월드컵공원 평화광장","distancesKm":[10.0,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 김천전국마라톤대회","date":"2026-11-01","startTime":"09:30","region":"경북 김천시","start":"김천종합스포츠타운","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 무안 해안 노을길 걷기 및 마라톤","date":"2026-11-01","startTime":"08:00","region":"전남","start":"무안낙지공원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제21회 울산인권마라톤","date":"2026-11-01","startTime":"09:30","region":"울산 중구","start":"태화강 둔치 (태화교 일원)","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 영천댐 마라톤","date":"2026-11-07","startTime":"09:40","region":"경북 영천시","start":"영천댐 하류공원","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 양산 배내골 애플 런","date":"2026-11-08","startTime":"09:00","region":"경남 양산시","start":"배내골 장선마을회관 앞 운동장","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 인천마라톤 (하반기)","date":"2026-11-08","startTime":"08:00","region":"인천","start":"인천문학경기장","distancesKm":[5.0,10.0,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 제주 감귤 마라톤","date":"2026-11-08","startTime":"08:00","region":"제주","start":"서귀포 강정천 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제11회 송파구청장배 마라톤","date":"2026-11-08","startTime":"09:00","region":"서울 송파구","start":"송파구 여성축구장","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 포항마라톤챔피언십","date":"2026-11-14","startTime":"09:00","region":"경북 포항시","start":"영일대해상누각","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2026 MBN 서울마라톤","date":"2026-11-15","startTime":"07:30","region":"서울 종로구","start":"광화문광장 (출발) / 잠실종합운동장 (도착)","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 가민런 코리아","date":"2026-11-15","startTime":"08:00","region":"경기 고양시","start":"고양종합운동장","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제24회 고창고인돌마라톤","date":"2026-11-15","startTime":"10:00","region":"전북 고창군","start":"고창공설운동장","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제24회 대모산 구룡산 트레일런","date":"2026-11-15","startTime":"08:00","region":"서울","start":"수서역 7번출구 광장","distancesKm":[10.0],"tags":[],"nonStandard":false},
    {"name":"제24회 상주 곶감 마라톤 대회","date":"2026-11-15","startTime":"09:00","region":"경북 상주시","start":"상주시민운동장","distancesKm":[4.4,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제2회 세종특별자치시 전국 마라톤","date":"2026-11-15","startTime":"09:30","region":"세종특별자치시","start":"세종시민운동장","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제3회 무등산더블하트국제트레일런","date":"2026-11-15","startTime":"08:00","region":"광주","start":"조선대학교","distancesKm":[16.0,36.0],"tags":[],"nonStandard":false},
    {"name":"제4회 영남알프스 전국 하프마라톤","date":"2026-11-15","startTime":"09:00","region":"울산 울주군","start":"울주 영남알프스 복합웰컴센터","distancesKm":[5.0,10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 울산마라톤","date":"2026-11-22","startTime":"08:00","region":"울산","start":"태화강 둔치","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 화성행궁마라톤","date":"2026-11-22","startTime":"08:00","region":"경기","start":"화성행궁 광장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 여수 일레븐 브리지 마라톤","date":"2026-11-29","startTime":"08:00","region":"전남","start":"여수 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2026 황영조와 함께하는 전국 로드레이스","date":"2026-11-29","startTime":"08:00","region":"전남","start":"전남 일원","distancesKm":[],"tags":[],"nonStandard":true},
    {"name":"2026 양산 전국 하프마라톤","date":"2026-12-05","startTime":"08:00","region":"경남","start":"양산 일원","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2026 시즌마감 마라톤대회","date":"2026-12-12","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false}
    ]}
    """#

    // MARK: - Embedded race data (문화체육관광부 국내마라톤대회 정보, 2025년)
    private static let embedded2025JSON = #"""
    {"year":2025,"count":122,"races":[
    {"name":"2025 평창 대관령 알몸 마라톤","date":"2025-02-01","startTime":"08:00","region":"강원","start":"대관령면 횡계리 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"대구 붕어빵트레일","date":"2025-02-02","startTime":"08:00","region":"대구","start":"대구 일원 (트레일)","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"2025 전마협 광주 첨단 무료 훈련마라톤","date":"2025-02-08","startTime":"08:00","region":"광주","start":"광주 첨단 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 전마협 새해맞이 보성마라톤","date":"2025-02-08","startTime":"08:00","region":"전남","start":"보성 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"서울 북한산트레일","date":"2025-02-09","startTime":"08:00","region":"서울","start":"북한산 일원","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"제22회 제주MBC 국제평화마라톤","date":"2025-02-09","startTime":"08:00","region":"제주","start":"제주종합경기장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 런콥 브레이킹 PB 30K","date":"2025-02-15","startTime":"08:00","region":"경기","start":"경기 일원","distancesKm":[30.0],"tags":[],"nonStandard":false},
    {"name":"2025 전마협 청주 무심천 마라톤대회","date":"2025-02-15","startTime":"08:00","region":"충북","start":"청주 무심천 둔치","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"부산 영도 태종대 트레일","date":"2025-02-16","startTime":"08:00","region":"부산","start":"영도 태종대 일원","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"희망드림 제22회 동계국제마라톤","date":"2025-02-16","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 대구마라톤","date":"2025-02-23","startTime":"08:00","region":"대구","start":"대구 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 챌린지 레이스","date":"2025-02-23","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"고구려 마라톤 2025","date":"2025-02-23","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"더 레이스 서울 21K","date":"2025-02-23","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[21.0975],"tags":[],"nonStandard":false},
    {"name":"제21회 밀양아리랑마라톤대회","date":"2025-02-23","startTime":"08:00","region":"경남","start":"밀양 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제7회 산불조심 한국서울마라톤","date":"2025-02-23","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"3.1절 기념 제74회 단축마라톤","date":"2025-03-01","startTime":"08:00","region":"경기","start":"경기 일원","distancesKm":[],"tags":["단축"],"nonStandard":true},
    {"name":"머니투데이방송 31절 마라톤대회","date":"2025-03-01","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제26회 3.1절 건강달리기","date":"2025-03-01","startTime":"08:00","region":"강원","start":"강원 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2025 구미박정희마라톤","date":"2025-03-02","startTime":"08:00","region":"경북","start":"구미 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 수원국제하프마라톤","date":"2025-03-02","startTime":"08:00","region":"경기","start":"수원 일원","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"서울 관악산트레일","date":"2025-03-02","startTime":"08:00","region":"서울","start":"관악산 일원","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"제60회 광주일보 3.1절 전국마라톤","date":"2025-03-02","startTime":"08:00","region":"전남","start":"광주 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제20회 부산 비치울트라 마라톤","date":"2025-03-08","startTime":"08:00","region":"부산","start":"부산 해운대 일원","distancesKm":[],"tags":["울트라"],"nonStandard":true},
    {"name":"2025 MBN 블루레이스 거제","date":"2025-03-09","startTime":"08:00","region":"경남","start":"거제 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 성주 참외 전국마라톤","date":"2025-03-09","startTime":"08:00","region":"경북","start":"성주 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"정읍동학마라톤대회","date":"2025-03-09","startTime":"08:00","region":"전북","start":"정읍 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제15회 여의도 벚꽃마라톤대회","date":"2025-03-09","startTime":"08:00","region":"서울","start":"여의도 한강공원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제19회 창녕부곡온천마라톤","date":"2025-03-15","startTime":"08:00","region":"경남","start":"창녕 부곡 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 서울마라톤 (제95회 동아마라톤)","date":"2025-03-16","startTime":"08:00","region":"서울","start":"광화문광장","distancesKm":[10.0,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 성남런페스티벌","date":"2025-03-22","startTime":"08:00","region":"경기","start":"성남 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 지리산 봄꽃레이스","date":"2025-03-22","startTime":"08:00","region":"전남","start":"지리산 일원","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"2025 전마협 금산마라톤대회","date":"2025-03-23","startTime":"08:00","region":"충남","start":"금산 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제12회 남산우정 마라톤 대회","date":"2025-03-23","startTime":"08:00","region":"서울","start":"남산 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제23회 성우하이텍배 KNN 환경마라톤","date":"2025-03-23","startTime":"08:00","region":"부산","start":"부산 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제32회 315마라톤","date":"2025-03-23","startTime":"08:00","region":"경남","start":"마산 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제22회 태화강 국제마라톤","date":"2025-03-29","startTime":"08:00","region":"울산","start":"태화강 둔치","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 은평 불광천 벚꽃마라톤","date":"2025-03-30","startTime":"08:00","region":"서울","start":"불광천 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 전마협 무안 해변마라톤","date":"2025-03-30","startTime":"08:00","region":"전남","start":"무안 해변 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 한강 벚꽃마라톤","date":"2025-03-30","startTime":"08:00","region":"서울","start":"한강 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제19회 정남진 장흥마라톤","date":"2025-03-30","startTime":"08:00","region":"전남","start":"장흥 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제24회 합천벚꽃마라톤","date":"2025-03-30","startTime":"08:00","region":"경남","start":"합천 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제25회 인천국제하프마라톤","date":"2025-03-30","startTime":"08:00","region":"인천","start":"인천 일원","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"제10회 기적의 마라톤","date":"2025-04-05","startTime":"08:00","region":"대전","start":"대전 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제32회 경주벚꽃마라톤","date":"2025-04-05","startTime":"08:00","region":"경북","start":"경주 보문단지","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 고양특례시 하프마라톤","date":"2025-04-06","startTime":"08:00","region":"경기","start":"고양종합운동장","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2025 군산새만금마라톤","date":"2025-04-06","startTime":"08:00","region":"전북","start":"군산 새만금 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 대구국제마라톤","date":"2025-04-06","startTime":"08:00","region":"대구","start":"두류공원 야외음악당","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"목포 유달산 마라톤","date":"2025-04-06","startTime":"08:00","region":"전남","start":"목포 유달산 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제12회 메르세데스 벤츠 기브앤레이스","date":"2025-04-06","startTime":"08:00","region":"부산","start":"부산 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제21회 예산윤봉길전국마라톤","date":"2025-04-06","startTime":"08:00","region":"충남","start":"예산 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 경기마라톤대회","date":"2025-04-13","startTime":"08:00","region":"경기","start":"수원월드컵경기장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 제주 벚꽃 마라톤","date":"2025-04-13","startTime":"08:00","region":"제주","start":"제주시 탑동광장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 인천마라톤","date":"2025-04-20","startTime":"08:00","region":"인천","start":"인천종합경기장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 광주마라톤","date":"2025-04-27","startTime":"08:00","region":"광주","start":"광주월드컵경기장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 서울 한강 하프마라톤","date":"2025-05-04","startTime":"08:00","region":"서울","start":"한강시민공원","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2025 전주마라톤","date":"2025-05-11","startTime":"08:00","region":"전북","start":"전주종합경기장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 강릉마라톤","date":"2025-05-18","startTime":"08:00","region":"강원","start":"강릉 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 이천마라톤","date":"2025-05-25","startTime":"08:00","region":"경기","start":"이천종합운동장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 한강울트라마라톤","date":"2025-06-01","startTime":"08:00","region":"서울","start":"한강 일원","distancesKm":[42.195],"tags":["울트라"],"nonStandard":false},
    {"name":"2025 DMZ 평화마라톤","date":"2025-06-08","startTime":"08:00","region":"경기","start":"철원 DMZ 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 자연특별시 무주 전마협 무료 초청 훈련 마라톤","date":"2025-07-05","startTime":"08:00","region":"전북","start":"무주 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"군포수리산 한반도트레일","date":"2025-07-06","startTime":"08:00","region":"경기","start":"군포 수리산 도립공원","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"2025 울릉도 국제트레일러닝 UiiT 40K","date":"2025-07-13","startTime":"08:00","region":"경북(울릉도)","start":"울릉도 도동항","distancesKm":[40.0],"tags":[],"nonStandard":false},
    {"name":"2025 전마협 별들의 전쟁 & 꽃들의 전쟁","date":"2025-07-13","startTime":"08:00","region":"충남","start":"충남 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2025 제15회 태종대 전국마라톤대회","date":"2025-07-20","startTime":"08:00","region":"부산","start":"태종대유원지","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제7회 안산 인왕산 북악산 CLIMBATHON","date":"2025-07-20","startTime":"08:00","region":"서울","start":"인왕산 기슭","distancesKm":[],"tags":["클라이마톤"],"nonStandard":true},
    {"name":"2025 나이트레이스 인 부산","date":"2025-08-02","startTime":"08:00","region":"부산","start":"광안리해수욕장","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2025 한강나이트워크 42K","date":"2025-08-02","startTime":"08:00","region":"서울","start":"한강 여의도공원","distancesKm":[42.0],"tags":[],"nonStandard":false},
    {"name":"제2회 쿨밸리 트레일레이스","date":"2025-08-02","startTime":"08:00","region":"전북","start":"전북 일원","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"2025 815런 잘될거야 대한민국","date":"2025-08-15","startTime":"08:00","region":"미정","start":"미정","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2025 순천 야광레이스 in 동천야광축제","date":"2025-08-16","startTime":"08:00","region":"전남","start":"순천 동천 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2025 Happy700 평창 대관령 전국 하프마라톤","date":"2025-08-17","startTime":"08:00","region":"강원","start":"대관령면 횡계리","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"2025 부산나이트워크 42K","date":"2025-08-23","startTime":"08:00","region":"부산","start":"광안리해수욕장","distancesKm":[42.0],"tags":[],"nonStandard":false},
    {"name":"미즈노 LIGHT LAP 2025 정선 하이원","date":"2025-08-23","startTime":"08:00","region":"강원","start":"정선 하이원리조트","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2025 금수산트레일 러닝대회","date":"2025-08-24","startTime":"08:00","region":"충북","start":"단양 금수산 일원","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"제2회 고대관령트레일런","date":"2025-08-24","startTime":"08:00","region":"강원","start":"대관령 일원","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"포항 호미반도트레일","date":"2025-08-24","startTime":"08:00","region":"경북","start":"포항 호미곶 광장","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"2025 단양 달빛레이스","date":"2025-08-30","startTime":"08:00","region":"충북","start":"단양 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"무한도전 Run with 쿠팡플레이 in 부산","date":"2025-08-30","startTime":"08:00","region":"부산","start":"부산 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"제2회 삼척시장배 단방산 숲길 마라톤","date":"2025-08-30","startTime":"08:00","region":"강원","start":"삼척 단방산 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 다이나핏 태백 트레일","date":"2025-09-06","startTime":"08:00","region":"강원","start":"태백 일원","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"2025 정선 동강마라톤","date":"2025-09-06","startTime":"08:00","region":"강원","start":"정선 동강 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제19회 순천만울트라마라톤","date":"2025-09-06","startTime":"08:00","region":"전남","start":"순천만 일원","distancesKm":[],"tags":["울트라"],"nonStandard":true},
    {"name":"2025 창원그란페스타 러닝","date":"2025-09-07","startTime":"08:00","region":"경남","start":"창원 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"RUN SEOUL RUN 2025 (런서울런)","date":"2025-09-07","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"지리산 릿지 레이스","date":"2025-09-07","startTime":"08:00","region":"전남","start":"지리산 일원","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"2025 양양 강변 전국마라톤","date":"2025-09-13","startTime":"08:00","region":"강원","start":"양양 강변 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 영덕블루로드 & 코리아둘레길 트레일런","date":"2025-09-13","startTime":"08:00","region":"경북","start":"영덕 일원","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"2025 금산인삼축제 마라톤","date":"2025-09-14","startTime":"08:00","region":"충남","start":"금산 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 마블런 서울","date":"2025-09-14","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"2025 울진금강송배 전국마라톤대회","date":"2025-09-14","startTime":"08:00","region":"경북","start":"울진 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"대구 한티가는길 트레일런","date":"2025-09-14","startTime":"08:00","region":"대구","start":"대구 일원","distancesKm":[],"tags":["트레일"],"nonStandard":true},
    {"name":"제4회 울산 동구 염포산 전국마라톤","date":"2025-09-14","startTime":"08:00","region":"울산","start":"울산 동구 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"서울 100K","date":"2025-09-20","startTime":"08:00","region":"서울","start":"서울 한강 일원","distancesKm":[100.0],"tags":[],"nonStandard":false},
    {"name":"제25회 홍성마라톤","date":"2025-09-20","startTime":"08:00","region":"충남","start":"홍성 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 춘천 스카이레이스","date":"2025-09-21","startTime":"08:00","region":"강원","start":"춘천 일원","distancesKm":[],"tags":["스카이","트레일"],"nonStandard":true},
    {"name":"제46회 조선일보 춘천마라톤 (예년 기준)","date":"2025-09-28","startTime":"08:00","region":"강원","start":"춘천시민체육관","distancesKm":[10.0,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 강화 평화마라톤","date":"2025-10-05","startTime":"08:00","region":"인천","start":"강화 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 수원화성마라톤","date":"2025-10-05","startTime":"08:00","region":"경기","start":"수원화성 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 고양마라톤","date":"2025-10-12","startTime":"08:00","region":"경기","start":"고양 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 서울달리기대회","date":"2025-10-12","startTime":"08:00","region":"서울","start":"여의도 한강공원","distancesKm":[5.0,10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 안양시장배 마라톤","date":"2025-10-19","startTime":"08:00","region":"경기","start":"안양 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제33회 경주국제마라톤","date":"2025-10-19","startTime":"08:00","region":"경북","start":"경주시민운동장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"제46회 조선일보 춘천마라톤","date":"2025-10-25","startTime":"08:00","region":"강원","start":"춘천시민체육관","distancesKm":[10.0,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 부산 바다 마라톤","date":"2025-10-26","startTime":"08:00","region":"부산","start":"광안리 해수욕장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 JTBC 서울마라톤","date":"2025-11-02","startTime":"08:00","region":"서울","start":"잠실종합운동장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 천안마라톤","date":"2025-11-02","startTime":"08:00","region":"충남","start":"천안 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 대전마라톤","date":"2025-11-09","startTime":"08:00","region":"대전","start":"대전 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 제주 감귤 마라톤","date":"2025-11-09","startTime":"08:00","region":"제주","start":"서귀포 강정천 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 울산마라톤","date":"2025-11-16","startTime":"08:00","region":"울산","start":"태화강 둔치","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 화성행궁마라톤","date":"2025-11-16","startTime":"08:00","region":"경기","start":"화성행궁 광장","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 인천마라톤대회","date":"2025-11-23","startTime":"08:00","region":"인천","start":"인천문학경기장","distancesKm":[5.0,10.0,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 전마협 진주마라톤","date":"2025-11-23","startTime":"08:00","region":"경남","start":"진주 남강 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 청주마라톤","date":"2025-11-23","startTime":"08:00","region":"충북","start":"청주 무심천 둔치","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"2025 의정부마라톤","date":"2025-11-30","startTime":"08:00","region":"경기","start":"의정부 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"겨울왕국 레이스","date":"2025-12-06","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[5.0,10.0],"tags":[],"nonStandard":false},
    {"name":"양산 전국 하프마라톤","date":"2025-12-06","startTime":"08:00","region":"경남","start":"양산 일원","distancesKm":[10.0,21.0975],"tags":[],"nonStandard":false},
    {"name":"한강시민 마라톤","date":"2025-12-06","startTime":"08:00","region":"서울","start":"한강 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"서울 사랑 마라톤","date":"2025-12-07","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"시즌마감 마라톤대회","date":"2025-12-13","startTime":"08:00","region":"서울","start":"서울 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false},
    {"name":"월미 알몸 마라톤대회","date":"2025-12-14","startTime":"08:00","region":"인천","start":"월미도 일원","distancesKm":[10.0,21.0975,42.195],"tags":[],"nonStandard":false}
    ]}
    """#
}