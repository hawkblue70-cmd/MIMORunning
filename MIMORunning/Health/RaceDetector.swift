import Foundation
import CoreLocation
import Observation
import SwiftData

// MARK: - Race model

struct BundledRace: Identifiable {
    let name: String
    let dateString: String
    let region: String
    let start: String
    let startLatitude: Double?
    let startLongitude: Double?
    let geoPrecision: String
    let distancesKm: [Double]
    let nonStandard: Bool
    let startTimeString: String?

    var id: String { name + dateString }

    var date: Date? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        return df.date(from: dateString)
    }

    var startCoordinate: CLLocationCoordinate2D? {
        guard let lat = startLatitude, let lng = startLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    func matchesDistance(_ km: Double) -> Bool {
        guard !distancesKm.isEmpty else { return false }
        return distancesKm.contains { abs($0 - km) / max($0, 0.001) <= 0.05 }
    }

    func bestMatchingDistance(_ km: Double) -> Double? {
        guard let closest = distancesKm.min(by: { abs($0 - km) < abs($1 - km) }) else { return nil }
        return (abs(closest - km) / max(closest, 0.001)) <= 0.05 ? closest : nil
    }

    /// 출발점 매칭 반경 — 좌표 정밀도에 따라 차등.
    /// `city`는 시(市) 중심점이라 넓게 잡을 수밖에 없고, 그만큼 자동 확정도 허용하지 않는다.
    var matchRadiusKm: Double {
        switch geoPrecision {
        case "venue":    1.5    // 특정 장소(운동장·광장) — 출발선이 실제로 여기
        case "district": 3.0    // 구/군 단위
        default:         5.0    // city 등 시 중심점
        }
    }

    /// "HH:MM" → 자정 기준 분. 값이 없거나 형식이 어긋나면 nil.
    var startMinutesOfDay: Int? {
        guard let s = startTimeString?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }
}

// MARK: - Match result

enum MatchStrength {
    case strong   // venue 정밀도 + 거리·시각·종료점 전부 일치, 후보 1개 → 자동 확정 가능
    case weak     // 게이트는 통과했지만 확신 부족 → 제안 배너로 사용자 확인
}

struct RaceSuggestion {
    let primary: BundledRace
    let strength: MatchStrength
    let alternatives: [BundledRace]
}

// MARK: - Persisted match

struct PersistedRaceMatch: Codable, Equatable, Sendable {
    let activityID: UUID
    var raceName: String
    var distanceKm: Double
    var raceDate: Date
    var isConfirmed: Bool
    var isDismissed: Bool
    var isManual: Bool
    /// 이 매칭이 어느 게이트 기준으로 확정됐는지. nil/낮은 값이면 재검증 대상.
    var gateVersion: Int?
}

/// 기존 확정 매칭을 새 게이트로 다시 검사할 때 필요한 활동 정보.
struct RaceRevalidationInput {
    let activityID: UUID
    let date: Date
    let distanceKm: Double
    let startCoord: CLLocationCoordinate2D?
}

// MARK: - RaceDetector

@Observable
final class RaceDetector {
    private(set) var races: [BundledRace] = []
    private(set) var matches: [String: PersistedRaceMatch] = [:]
    private(set) var isReady: Bool = false

    private static let matchesKey = "raceDetector.matches.v1"
    /// 매칭 게이트 기준 버전. 기준이 바뀌면 올린다 →
    /// 이보다 낮은 버전으로 자동 확정된 기록은 `revalidateAutoMatches`에서 다시 검사한다.
    /// v2: 거리 ±5% · 출발 시각 ±90분 · 정밀도별 반경(1.5/3/5km) 게이트 도입.
    static let gateVersion = 2
    private var modelContext: ModelContext?

    // MARK: - Setup

    func setup(context: ModelContext) async {
        modelContext = context
        await loadMatchesFromSwiftData(context)
        races = Self.loadRacesFromCSV()
        isReady = true
    }

    // MARK: - Assessment

    /// Returns a race suggestion for the activity, or nil.
    /// GPS required — treadmill runs never match.
    ///
    /// 하드 게이트(전부 통과해야 후보): 같은 날짜 · 공식 종목 거리 ±5% ·
    /// 출발 시각 ±90분 · 출발점이 대회 좌표 반경 안(정밀도별 1.5/3/5km).
    /// 자동 확정(.strong)은 후보가 1개이고 venue 정밀도 + 시각 ±45분 +
    /// 종료점까지 대회장 근처일 때만. 나머지는 .weak → 사용자 확인.
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

        guard let sc = startCoord else { return nil }

        let gated: [(race: BundledRace, distKm: Double)] = races.compactMap { race in
            guard passesHardGate(race: race, date: date,
                                 distanceKm: distanceKm, startCoord: sc),
                  let lat = race.startLatitude, let lng = race.startLongitude
            else { return nil }
            return (race, Self.haversineKm(sc.latitude, sc.longitude, lat, lng))
        }
        guard !gated.isEmpty else { return nil }
        if wasDismissed { return nil }

        let sorted = gated.sorted { $0.distKm < $1.distKm }
        let primary = sorted[0].race
        let strength: MatchStrength =
            (sorted.count == 1 && qualifiesForAutoConfirm(race: primary, date: date,
                                                          distanceKm: distanceKm,
                                                          endCoord: routeCoords.last))
            ? .strong : .weak
        return RaceSuggestion(primary: primary, strength: strength,
                              alternatives: sorted.dropFirst().map(\.race))
    }

    // MARK: - Gates

    /// 후보가 되기 위한 최소 조건. 하나라도 어긋나면 대회로 보지 않는다.
    /// `startCoord`가 nil이면 위치 검증만 생략한다(경로 없는 기존 기록 재검증용).
    func passesHardGate(
        race: BundledRace,
        date: Date,
        distanceKm: Double,
        startCoord: CLLocationCoordinate2D?
    ) -> Bool {
        // ① 같은 날짜
        guard let rd = race.date, Calendar.current.isDate(date, inSameDayAs: rd) else { return false }
        // ② 좌표 없는 대회는 매칭 불가
        guard race.geoPrecision != "none",
              let lat = race.startLatitude, let lng = race.startLongitude else { return false }
        // ③ 공식 종목 거리 ±5%
        guard race.matchesDistance(distanceKm) else { return false }
        // ④ 출발 시각 ±90분 (대회 시각이 CSV에 있을 때만)
        if let raceMin = race.startMinutesOfDay,
           Self.minuteGap(from: date, toMinutesOfDay: raceMin) > 90 { return false }
        // ⑤ 출발점 반경 — 정밀도별
        if let sc = startCoord {
            guard Self.haversineKm(sc.latitude, sc.longitude, lat, lng) <= race.matchRadiusKm else { return false }
        }
        return true
    }

    /// 사용자 확인 없이 확정해도 되는 수준인지.
    private func qualifiesForAutoConfirm(
        race: BundledRace,
        date: Date,
        distanceKm: Double,
        endCoord: CLLocationCoordinate2D?
    ) -> Bool {
        // 출발선이 특정된 대회만 — city/district 중심 좌표는 확신할 수 없다
        guard race.geoPrecision == "venue" else { return false }
        // 출발 시각을 아는 대회만, 그것도 ±45분 안
        guard let raceMin = race.startMinutesOfDay,
              Self.minuteGap(from: date, toMinutesOfDay: raceMin) <= 45 else { return false }
        // 종료점도 대회장 권역 안 — 지점간(point-to-point) 코스를 감안해 거리 비례로 넉넉히
        guard let ec = endCoord,
              let lat = race.startLatitude, let lng = race.startLongitude else { return false }
        let endGap = Self.haversineKm(ec.latitude, ec.longitude, lat, lng)
        return endGap <= max(race.matchRadiusKm, distanceKm * 0.35)
    }

    /// 활동 시작 시각(로컬)과 대회 출발 시각(분) 사이의 간격. 자정을 넘겨도 최단 거리로.
    private static func minuteGap(from date: Date, toMinutesOfDay raceMin: Int) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let actMin = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let diff = abs(actMin - raceMin)
        return min(diff, 1440 - diff)
    }

    func matchFor(activityID: UUID) -> PersistedRaceMatch? {
        matches[activityID.uuidString]
    }

    // MARK: - Revalidation

    /// 예전(느슨한) 기준으로 자동 확정된 매칭들. 직접 등록한 대회는 건드리지 않는다.
    var idsNeedingRevalidation: [UUID] {
        guard isReady else { return [] }
        return matches.values
            .filter { $0.isConfirmed && !$0.isManual && ($0.gateVersion ?? 0) < Self.gateVersion }
            .map(\.activityID)
    }

    /// 기존 자동 확정 매칭을 현재 게이트로 다시 검사한다.
    /// 하드 게이트를 통과하면 버전만 올려 그대로 두고, 통과 못 하면 확정을 해제한다
    /// (삭제 → 다음에 활동을 열 때 새 기준으로 다시 판정되고, 애매하면 제안 배너가 뜬다).
    /// - Returns: 확정 해제된 활동 ID
    @discardableResult
    func revalidateAutoMatches(_ inputs: [RaceRevalidationInput]) -> [UUID] {
        guard isReady, !inputs.isEmpty else { return [] }
        var dropped: [UUID] = []
        var changed = false

        for input in inputs {
            let key = input.activityID.uuidString
            guard var match = matches[key],
                  match.isConfirmed, !match.isManual,
                  (match.gateVersion ?? 0) < Self.gateVersion else { continue }

            let survives = races.contains { race in
                race.name == match.raceName
                && passesHardGate(race: race, date: input.date,
                                  distanceKm: input.distanceKm, startCoord: input.startCoord)
            }

            if survives {
                match.gateVersion = Self.gateVersion
                matches[key] = match
            } else {
                matches.removeValue(forKey: key)
                dropped.append(input.activityID)
                #if DEBUG
                print("[대회매칭] 확정 해제 — \(match.raceName) (\(String(format: "%.2f", input.distanceKm))km, \(input.date))")
                #endif
            }
            changed = true
        }

        if changed { saveMatches() }
        return dropped
    }

    // MARK: - Mutations

    func confirm(activityID: UUID, race: BundledRace, activityDistanceKm: Double) {
        let km = race.bestMatchingDistance(activityDistanceKm) ?? activityDistanceKm
        matches[activityID.uuidString] = PersistedRaceMatch(
            activityID: activityID, raceName: race.name, distanceKm: km,
            raceDate: race.date ?? Date(),
            isConfirmed: true, isDismissed: false, isManual: false,
            gateVersion: Self.gateVersion)
        saveMatches()
    }

    func addManual(activityID: UUID, name: String, distanceKm: Double, date: Date) {
        matches[activityID.uuidString] = PersistedRaceMatch(
            activityID: activityID, raceName: name, distanceKm: distanceKm,
            raceDate: date, isConfirmed: true, isDismissed: false, isManual: true,
            gateVersion: Self.gateVersion)
        saveMatches()
    }

    func markAsNotRace(activityID: UUID) {
        matches[activityID.uuidString] = PersistedRaceMatch(
            activityID: activityID, raceName: "", distanceKm: 0,
            raceDate: Date(), isConfirmed: false, isDismissed: true, isManual: false,
            gateVersion: Self.gateVersion)
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

    // MARK: - Persistence

    private func loadMatchesFromSwiftData(_ context: ModelContext) async {
        let descriptor = FetchDescriptor<PersistedRaceMatchRecord>()
        if let records = try? context.fetch(descriptor), !records.isEmpty {
            matches = Dictionary(records.compactMap { r in
                r.asPersistedRaceMatch.map { (r.activityID, $0) }
            }, uniquingKeysWith: { _, new in new })
            return
        }
        guard let data = UserDefaults.standard.data(forKey: Self.matchesKey),
              let saved = try? JSONDecoder().decode([String: PersistedRaceMatch].self, from: data),
              !saved.isEmpty
        else { return }
        matches = saved
        syncMatchesToSwiftData(context)
        UserDefaults.standard.removeObject(forKey: Self.matchesKey)
    }

    private func saveMatches() {
        if let ctx = modelContext {
            syncMatchesToSwiftData(ctx)
        } else {
            guard let data = try? JSONEncoder().encode(matches) else { return }
            UserDefaults.standard.set(data, forKey: Self.matchesKey)
        }
    }

    private func syncMatchesToSwiftData(_ ctx: ModelContext) {
        let descriptor = FetchDescriptor<PersistedRaceMatchRecord>()
        if let existing = try? ctx.fetch(descriptor) { existing.forEach { ctx.delete($0) } }
        for (_, match) in matches { ctx.insert(PersistedRaceMatchRecord(from: match)) }
        try? ctx.save()
    }

    // MARK: - CSV loading

    private static func loadRacesFromCSV() -> [BundledRace] {
        let lines = racesCSV.components(separatedBy: "\n")
        guard lines.count > 1 else { return [] }
        var result: [BundledRace] = []
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let f = parseCSVRow(trimmed)
            guard f.count >= 11 else { continue }
            let lat = f[5].isEmpty ? nil : Double(f[5])
            let lng = f[6].isEmpty ? nil : Double(f[6])
            result.append(BundledRace(
                name: f[0], dateString: f[1], region: f[3], start: f[4],
                startLatitude: lat, startLongitude: lng, geoPrecision: f[7],
                distancesKm: parseDoubleArray(f[8]),
                nonStandard: f[10].lowercased() == "true",
                startTimeString: f[2]
            ))
        }
        return result
    }

    private static func parseCSVRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuote = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if inQuote {
                if c == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" {
                        current.append("\"")
                        i = next
                    } else {
                        inQuote = false
                    }
                } else {
                    current.append(c)
                }
            } else {
                if c == "\"" {
                    inQuote = true
                } else if c == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(c)
                }
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }

    private static func parseDoubleArray(_ s: String) -> [Double] {
        let inner = s
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty else { return [] }
        return inner.components(separatedBy: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func haversineKm(
        _ lat1: Double, _ lon1: Double,
        _ lat2: Double, _ lon2: Double
    ) -> Double {
        let R = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    // MARK: - Embedded CSV (공공데이터포털 "문화체육관광부_국내마라톤대회 정보", 2024–2026)
    private static let racesCSV = #"""
name,date,startTime,region,start,lat,lng,geoPrecision,distancesKm,tags,nonStandard
제45회 조선일보 춘천마라톤,2024-10-27,09:00,강원,공지천 인조잔디구장,37.878,127.726,venue,"[10.0, 42.195]",[],FALSE
2025 평창 대관령 알몸 마라톤,2025-02-01,08:00,강원,대관령면 횡계리 일원,37.677,128.715,district,"[10.0, 21.0975, 42.195]",[],FALSE
대구 붕어빵트레일,2025-02-02,08:00,대구,대구 일원 (트레일),35.8714,128.6014,city,[],"[""트레일""]",TRUE
2025 전마협 광주 첨단 무료 훈련마라톤,2025-02-08,08:00,광주,광주 첨단 일원,35.217,126.847,district,"[10.0, 21.0975, 42.195]",[],FALSE
2025 전마협 새해맞이 보성마라톤,2025-02-08,08:00,전남,보성 일원,34.7714,127.08,city,"[10.0, 21.0975, 42.195]",[],FALSE
서울 북한산트레일,2025-02-09,08:00,서울,북한산 일원,37.6584,126.9776,district,[],"[""트레일""]",TRUE
제22회 제주MBC 국제평화마라톤,2025-02-09,08:00,제주,제주종합경기장,33.504,126.509,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2025 런콥 브레이킹 PB 30K,2025-02-15,08:00,경기,경기 일원,37.2636,127.0286,city,[30.0],[],FALSE
2025 전마협 청주 무심천 마라톤대회,2025-02-15,08:00,충북,청주 무심천 둔치,36.63,127.485,district,"[10.0, 21.0975, 42.195]",[],FALSE
부산 영도 태종대 트레일,2025-02-16,08:00,부산,영도 태종대 일원,35.059,129.086,district,[],"[""트레일""]",TRUE
희망드림 제22회 동계국제마라톤,2025-02-16,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 대구마라톤,2025-02-23,08:00,대구,대구 일원,35.8714,128.6014,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 챌린지 레이스,2025-02-23,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 21.0975, 42.195]",[],FALSE
고구려 마라톤 2025,2025-02-23,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 21.0975, 42.195]",[],FALSE
더 레이스 서울 21K,2025-02-23,08:00,서울,서울 일원,37.5665,126.978,city,[21.0975],[],FALSE
제21회 밀양아리랑마라톤대회,2025-02-23,08:00,경남,밀양 일원,35.5038,128.7467,city,"[10.0, 21.0975, 42.195]",[],FALSE
제7회 산불조심 한국서울마라톤,2025-02-23,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 21.0975, 42.195]",[],FALSE
3.1절 기념 제74회 단축마라톤,2025-03-01,08:00,경기,경기 일원,37.2636,127.0286,city,[],"[""단축""]",TRUE
머니투데이방송 31절 마라톤대회,2025-03-01,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 21.0975, 42.195]",[],FALSE
제26회 3.1절 건강달리기,2025-03-01,08:00,강원,강원 일원,37.8813,127.7298,city,"[5.0, 10.0]",[],FALSE
2025 구미박정희마라톤,2025-03-02,08:00,경북,구미 일원,36.1195,128.3446,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 수원국제하프마라톤,2025-03-02,08:00,경기,수원 일원,37.2636,127.0286,city,"[10.0, 21.0975]",[],FALSE
서울 관악산트레일,2025-03-02,08:00,서울,관악산 일원,37.4429,126.961,district,[],"[""트레일""]",TRUE
제60회 광주일보 3.1절 전국마라톤,2025-03-02,08:00,전남,광주 일원,35.1595,126.8526,city,"[10.0, 21.0975, 42.195]",[],FALSE
제20회 부산 비치울트라 마라톤,2025-03-08,08:00,부산,부산 해운대 일원,35.1587,129.1604,district,[],"[""울트라""]",TRUE
2025 MBN 블루레이스 거제,2025-03-09,08:00,경남,거제 일원,34.8806,128.6211,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 성주 참외 전국마라톤,2025-03-09,08:00,경북,성주 일원,35.919,128.283,city,"[10.0, 21.0975, 42.195]",[],FALSE
정읍동학마라톤대회,2025-03-09,08:00,전북,정읍 일원,35.5699,126.856,city,"[10.0, 21.0975, 42.195]",[],FALSE
제15회 여의도 벚꽃마라톤대회,2025-03-09,08:00,서울,여의도 한강공원,37.5284,126.9327,venue,"[10.0, 21.0975, 42.195]",[],FALSE
제19회 창녕부곡온천마라톤,2025-03-15,08:00,경남,창녕 부곡 일원,35.4258,128.596,district,"[10.0, 21.0975, 42.195]",[],FALSE
2025 서울마라톤 (제95회 동아마라톤),2025-03-16,08:00,서울,광화문광장,37.5716,126.9767,venue,"[10.0, 42.195]",[],FALSE
2025 성남런페스티벌,2025-03-22,08:00,경기,성남 일원,37.42,127.1265,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 지리산 봄꽃레이스,2025-03-22,08:00,전남,지리산 일원,35.202,127.463,city,[],"[""트레일""]",TRUE
2025 전마협 금산마라톤대회,2025-03-23,08:00,충남,금산 일원,36.1086,127.4881,city,"[10.0, 21.0975, 42.195]",[],FALSE
제12회 남산우정 마라톤 대회,2025-03-23,08:00,서울,남산 일원,37.5512,126.9882,district,"[10.0, 21.0975, 42.195]",[],FALSE
제23회 성우하이텍배 KNN 환경마라톤,2025-03-23,08:00,부산,부산 일원,35.1796,129.0756,city,"[10.0, 21.0975, 42.195]",[],FALSE
제32회 315마라톤,2025-03-23,08:00,경남,마산 일원,35.197,128.568,city,"[10.0, 21.0975, 42.195]",[],FALSE
제22회 태화강 국제마라톤,2025-03-29,08:00,울산,태화강 둔치,35.547,129.305,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2025 은평 불광천 벚꽃마라톤,2025-03-30,08:00,서울,불광천 일원,37.596,126.915,district,"[10.0, 21.0975, 42.195]",[],FALSE
2025 전마협 무안 해변마라톤,2025-03-30,08:00,전남,무안 해변 일원,34.9904,126.4816,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 한강 벚꽃마라톤,2025-03-30,08:00,서울,한강 일원,37.5284,126.9327,city,"[10.0, 21.0975, 42.195]",[],FALSE
제19회 정남진 장흥마라톤,2025-03-30,08:00,전남,장흥 일원,34.6816,126.907,city,"[10.0, 21.0975, 42.195]",[],FALSE
제24회 합천벚꽃마라톤,2025-03-30,08:00,경남,합천 일원,35.5665,128.1659,city,"[10.0, 21.0975, 42.195]",[],FALSE
제25회 인천국제하프마라톤,2025-03-30,08:00,인천,인천 일원,37.4563,126.7052,city,"[10.0, 21.0975]",[],FALSE
제10회 기적의 마라톤,2025-04-05,08:00,대전,대전 일원,36.3504,127.3845,city,"[10.0, 21.0975, 42.195]",[],FALSE
제32회 경주벚꽃마라톤,2025-04-05,08:00,경북,경주 보문단지,35.842,129.282,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2025 고양특례시 하프마라톤,2025-04-06,08:00,경기,고양종합운동장,37.6703,126.7433,venue,"[10.0, 21.0975]",[],FALSE
2025 군산새만금마라톤,2025-04-06,08:00,전북,군산 새만금 일원,35.9,126.6,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 대구국제마라톤,2025-04-06,08:00,대구,두류공원 야외음악당,35.854,128.563,venue,"[10.0, 21.0975, 42.195]",[],FALSE
목포 유달산 마라톤,2025-04-06,08:00,전남,목포 유달산 일원,34.79,126.37,district,"[10.0, 21.0975, 42.195]",[],FALSE
제12회 메르세데스 벤츠 기브앤레이스,2025-04-06,08:00,부산,부산 일원,35.1796,129.0756,city,"[10.0, 21.0975, 42.195]",[],FALSE
제21회 예산윤봉길전국마라톤,2025-04-06,08:00,충남,예산 일원,36.6826,126.8449,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 경기마라톤대회,2025-04-13,08:00,경기,수원월드컵경기장,37.2863,127.037,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2025 제주 벚꽃 마라톤,2025-04-13,08:00,제주,제주시 탑동광장,33.519,126.522,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2025 인천마라톤,2025-04-20,08:00,인천,인천종합경기장,37.4353,126.69,district,"[10.0, 21.0975, 42.195]",[],FALSE
2025 서울하프마라톤,2025-04-27,08:00,서울,광화문광장,37.5716,126.9767,venue,"[10.0, 21.0975]",,
2025 광주마라톤,2025-04-27,08:00,광주,광주월드컵경기장,35.1338,126.875,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2025 서울 한강 하프마라톤,2025-05-04,08:00,서울,한강시민공원,37.5284,126.9327,city,"[10.0, 21.0975]",[],FALSE
2025 전주마라톤,2025-05-11,08:00,전북,전주종합경기장,35.8395,127.1287,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2025 강릉마라톤,2025-05-18,08:00,강원,강릉 일원,37.7519,128.8761,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 이천마라톤,2025-05-25,08:00,경기,이천종합운동장,36.2638,127.4423,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2025 한강울트라마라톤,2025-06-01,08:00,서울,한강 일원,37.5284,126.9327,city,[42.195],"[""울트라""]",FALSE
2025 DMZ 평화마라톤,2025-06-08,08:00,경기,철원 DMZ 일원,38.1466,127.3132,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 자연특별시 무주 전마협 무료 초청 훈련 마라톤,2025-07-05,08:00,전북,무주 일원,36.0069,127.6608,city,"[10.0, 21.0975, 42.195]",[],FALSE
군포수리산 한반도트레일,2025-07-06,08:00,경기,군포 수리산 도립공원,37.341,126.919,district,[],"[""트레일""]",TRUE
2025 울릉도 국제트레일러닝 UiiT 40K,2025-07-13,08:00,경북(울릉도),울릉도 도동항,37.484,130.908,venue,[40.0],[],FALSE
2025 전마협 별들의 전쟁 & 꽃들의 전쟁,2025-07-13,08:00,충남,충남 일원,36.6015,126.661,city,"[5.0, 10.0]",[],FALSE
2025 제15회 태종대 전국마라톤대회,2025-07-20,08:00,부산,태종대유원지,35.059,129.086,venue,"[10.0, 21.0975, 42.195]",[],FALSE
제7회 안산 인왕산 북악산 CLIMBATHON,2025-07-20,08:00,서울,인왕산 기슭,37.5826,126.9576,district,[],"[""클라이마톤""]",TRUE
2025 나이트레이스 인 부산,2025-08-02,08:00,부산,광안리해수욕장,35.1532,129.1187,venue,"[5.0, 10.0]",[],FALSE
2025 한강나이트워크 42K,2025-08-02,08:00,서울,한강 여의도공원,37.5254,126.9236,venue,[42.0],[],FALSE
제2회 쿨밸리 트레일레이스,2025-08-02,08:00,전북,전북 일원,35.8242,127.148,city,[],"[""트레일""]",TRUE
2025 815런 잘될거야 대한민국,2025-08-15,08:00,미정,미정,,,none,"[5.0, 10.0]",[],FALSE
2025 순천 야광레이스 in 동천야광축제,2025-08-16,08:00,전남,순천 동천 일원,34.955,127.487,district,"[5.0, 10.0]",[],FALSE
2025 Happy700 평창 대관령 전국 하프마라톤,2025-08-17,08:00,강원,대관령면 횡계리,37.677,128.715,district,"[10.0, 21.0975]",[],FALSE
2025 부산나이트워크 42K,2025-08-23,08:00,부산,광안리해수욕장,35.1532,129.1187,venue,[42.0],[],FALSE
미즈노 LIGHT LAP 2025 정선 하이원,2025-08-23,08:00,강원,정선 하이원리조트,37.208,128.825,venue,"[5.0, 10.0]",[],FALSE
2025 금수산트레일 러닝대회,2025-08-24,08:00,충북,단양 금수산 일원,36.976,128.253,district,[],"[""트레일""]",TRUE
제2회 고대관령트레일런,2025-08-24,08:00,강원,대관령 일원,37.677,128.718,district,[],"[""트레일""]",TRUE
포항 호미반도트레일,2025-08-24,08:00,경북,포항 호미곶 광장,36.077,129.566,venue,[],"[""트레일""]",TRUE
2025 단양 달빛레이스,2025-08-30,08:00,충북,단양 일원,36.9846,128.3655,city,"[5.0, 10.0]",[],FALSE
무한도전 Run with 쿠팡플레이 in 부산,2025-08-30,08:00,부산,부산 일원,35.1796,129.0756,city,"[5.0, 10.0]",[],FALSE
제2회 삼척시장배 단방산 숲길 마라톤,2025-08-30,08:00,강원,삼척 단방산 일원,37.4499,129.1652,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 다이나핏 태백 트레일,2025-09-06,08:00,강원,태백 일원,37.164,128.9856,city,[],"[""트레일""]",TRUE
2025 정선 동강마라톤,2025-09-06,08:00,강원,정선 동강 일원,37.38,128.66,city,"[10.0, 21.0975, 42.195]",[],FALSE
제19회 순천만울트라마라톤,2025-09-06,08:00,전남,순천만 일원,34.885,127.509,district,[],"[""울트라""]",TRUE
2025 창원그란페스타 러닝,2025-09-07,08:00,경남,창원 일원,35.228,128.6811,city,"[10.0, 21.0975, 42.195]",[],FALSE
RUN SEOUL RUN 2025 (런서울런),2025-09-07,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 21.0975, 42.195]",[],FALSE
지리산 릿지 레이스,2025-09-07,08:00,전남,지리산 일원,35.202,127.463,city,[],"[""트레일""]",TRUE
2025 양양 강변 전국마라톤,2025-09-13,08:00,강원,양양 강변 일원,38.074,128.619,district,"[10.0, 21.0975, 42.195]",[],FALSE
2025 영덕블루로드 & 코리아둘레길 트레일런,2025-09-13,08:00,경북,영덕 일원,36.415,129.366,city,[],"[""트레일""]",TRUE
2025 금산인삼축제 마라톤,2025-09-14,08:00,충남,금산 일원,36.1086,127.4881,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 마블런 서울,2025-09-14,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0]",[],FALSE
2025 울진금강송배 전국마라톤대회,2025-09-14,08:00,경북,울진 일원,36.993,129.4,city,"[10.0, 21.0975, 42.195]",[],FALSE
대구 한티가는길 트레일런,2025-09-14,08:00,대구,대구 일원,35.8714,128.6014,city,[],"[""트레일""]",TRUE
제4회 울산 동구 염포산 전국마라톤,2025-09-14,08:00,울산,울산 동구 일원,35.504,129.417,city,"[10.0, 21.0975, 42.195]",[],FALSE
서울 100K,2025-09-20,08:00,서울,서울 한강 일원,37.5284,126.9327,city,[100.0],[],FALSE
제25회 홍성마라톤,2025-09-20,08:00,충남,홍성 일원,36.6015,126.661,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 춘천 스카이레이스,2025-09-21,08:00,강원,춘천 일원,37.8813,127.7298,city,[],"[""스카이"", ""트레일""]",TRUE
2025 강화 평화마라톤,2025-10-05,08:00,인천,강화 일원,37.747,126.488,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 수원화성마라톤,2025-10-05,08:00,경기,수원화성 일원,37.2816,127.0137,district,"[10.0, 21.0975, 42.195]",[],FALSE
2025 고양마라톤,2025-10-12,08:00,경기,고양 일원,37.6584,126.832,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 서울달리기대회,2025-10-12,08:00,서울,여의도 한강공원,37.5284,126.9327,venue,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
2025 안양시장배 마라톤,2025-10-19,08:00,경기,안양 일원,37.3943,126.9568,city,"[10.0, 21.0975, 42.195]",[],FALSE
제33회 경주국제마라톤,2025-10-19,08:00,경북,경주시민운동장,35.857,129.218,venue,"[10.0, 21.0975, 42.195]",[],FALSE
제46회 조선일보 춘천마라톤,2025-10-25,08:00,강원,춘천시민체육관,37.87,127.72,district,"[10.0, 42.195]",[],FALSE
2025 부산 바다 마라톤,2025-10-26,08:00,부산,광안리 해수욕장,35.1532,129.1187,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2025 JTBC 서울마라톤,2025-11-02,08:00,서울,잠실종합운동장,37.5121,127.0719,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2025 천안마라톤,2025-11-02,08:00,충남,천안 일원,36.8151,127.1139,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 대전마라톤,2025-11-09,08:00,대전,대전 일원,36.3504,127.3845,city,"[10.0, 21.0975, 42.195]",[],FALSE
2025 제주 감귤 마라톤,2025-11-09,08:00,제주,서귀포 강정천 일원,33.247,126.482,district,"[10.0, 21.0975, 42.195]",[],FALSE
2025 울산마라톤,2025-11-16,08:00,울산,태화강 둔치,35.547,129.305,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2025 화성행궁마라톤,2025-11-16,08:00,경기,화성행궁 광장,37.2816,127.0137,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2025 인천마라톤대회,2025-11-23,08:00,인천,인천문학경기장,37.4353,126.69,venue,"[5.0, 10.0, 42.195]",[],FALSE
2025 전마협 진주마라톤,2025-11-23,08:00,경남,진주 남강 일원,35.19,128.081,district,"[10.0, 21.0975, 42.195]",[],FALSE
2025 청주마라톤,2025-11-23,08:00,충북,청주 무심천 둔치,36.63,127.485,district,"[10.0, 21.0975, 42.195]",[],FALSE
2025 의정부마라톤,2025-11-30,08:00,경기,의정부 일원,37.7381,127.0338,city,"[10.0, 21.0975, 42.195]",[],FALSE
겨울왕국 레이스,2025-12-06,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0]",[],FALSE
양산 전국 하프마라톤,2025-12-06,08:00,경남,양산 일원,35.335,129.037,city,"[10.0, 21.0975]",[],FALSE
한강시민 마라톤,2025-12-06,08:00,서울,한강 일원,37.5284,126.9327,city,"[10.0, 21.0975, 42.195]",[],FALSE
서울 사랑 마라톤,2025-12-07,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 21.0975, 42.195]",[],FALSE
시즌마감 마라톤대회,2025-12-13,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 21.0975, 42.195]",[],FALSE
월미 알몸 마라톤대회,2025-12-14,08:00,인천,월미도 일원,37.474,126.597,district,"[10.0, 21.0975, 42.195]",[],FALSE
2026 새해 일출런,2026-01-01,08:00,서울,신정교하부 육상트랙구장,37.515,126.868,district,"[5.0, 10.0]",[],FALSE
2026 선양 맨몸마라톤,2026-01-01,08:00,대전,대전 일원,36.3504,127.3845,city,[7.0],[],FALSE
제2회 새해맞이 거제 산방산 임도런,2026-01-03,08:00,경남,거제 산방산 일원,34.863,128.576,district,"[15.0, 25.0, 35.0]",[],FALSE
2026 전마협 새해 맞이 마라톤,2026-01-04,08:00,충남,충남 일원,36.6015,126.661,city,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
제18회 전국새해알몸마라톤,2026-01-04,08:00,대구,대구 일원,35.8714,128.6014,city,"[5.0, 10.0]",[],FALSE
2026 미즈노 페스타,2026-01-10,08:00,경기,경기 일원,37.2636,127.0286,city,[],[],TRUE
제18회 의림지삼한초록길알몸마라톤,2026-01-11,08:00,충북,제천 의림지 일원,37.16,128.211,venue,[7.0],[],FALSE
제20회 여수해양마라톤,2026-01-11,08:00,전남,여수 일원,34.7604,127.6622,city,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
2026 코리아 스노우 트레일,2026-01-17,08:00,강원,강원 일원,37.8813,127.7298,city,"[13.0, 30.0]",[],FALSE
2026 전마협 제주 4Full 마라톤,2026-01-23,08:00,제주,제주 일원,33.4996,126.5312,city,[42.195],[],FALSE
2026 똥바람 알통구보대회,2026-01-24,08:00,강원,강원 일원,37.8813,127.7298,city,[6.32],[],FALSE
2026 전마협 제주 10km 마라톤,2026-01-25,08:00,제주,제주 일원,33.4996,126.5312,city,[10.0],[],FALSE
제2회 한강 서울 하프 마라톤,2026-01-25,08:00,서울,상암 월드컵공원 평화광장,37.5697,126.8973,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 인사이더런 W,2026-01-31,08:00,경기,경기 일원,37.2636,127.0286,city,[10.0],[],FALSE
2026 화성 궁평항 동계 훈련 마라톤,2026-01-31,08:00,경기,화성 궁평항 일원,37.115,126.681,district,"[10.0, 21.0975, 32.0]",[],FALSE
2026 인사이더런 W (2월),2026-02-01,08:00,경기,경기 일원,37.2636,127.0286,city,[10.0],[],FALSE
2026 전마협 별들의 전쟁 & 꽃들의 전쟁 클럽대항전,2026-02-08,08:00,충남,충남 일원,36.6015,126.661,city,[20.0],[],FALSE
제3회 산들소리향기마라톤,2026-02-08,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0, 21.0975]",[],FALSE
2026 평창 대관령 알몸 마라톤,2026-02-14,08:00,강원,대관령면 횡계리 일원,37.677,128.715,district,"[5.0, 10.0]",[],FALSE
2026 순천만국가정원 윷놀이런,2026-02-18,08:00,전남,순천만국가정원,34.93,127.505,venue,"[3.0, 10.0]",[],FALSE
2026 전마협 청주 무심천 투데이 마라톤 (토),2026-02-21,08:00,충북,청주 무심천 둔치,36.63,127.485,district,"[5.0, 10.0, 21.0975]",[],FALSE
2026 청춘릴레이 마라톤,2026-02-21,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0, 21.0975]",[],FALSE
제7회 휴먼레이스,2026-02-21,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0, 21.0975]",[],FALSE
희망드림 제23회 동계 국제 마라톤,2026-02-21,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0, 21.0975, 32.0]",[],FALSE
2026 경기수원국제하프마라톤,2026-02-22,08:00,경기,수원 일원,37.2636,127.0286,city,"[5.0, 10.0, 21.0975]",[],FALSE
2026 고구려 마라톤,2026-02-22,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 21.0975, 32.0, 42.195]",[],FALSE
2026 대구국제마라톤 (대구마라톤),2026-02-22,08:00,대구,대구스타디움 일원,35.8296,128.6893,venue,"[5.3, 10.9, 42.195]",[],FALSE
2026 전마협 청주 무심천 투데이 마라톤 (일),2026-02-22,08:00,충북,청주 무심천 둔치,36.63,127.485,district,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
2026 제주MBC 국제평화마라톤,2026-02-22,08:00,제주,제주 일원,33.4996,126.5312,city,"[10.0, 21.0975]",[],FALSE
2026 챌린지 레이스,2026-02-22,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 21.0975, 32.0, 42.195]",[],FALSE
제22회 밀양아리랑마라톤,2026-02-22,08:00,경남,밀양 일원,35.5038,128.7467,city,"[5.0, 10.0, 21.0975]",[],FALSE
제9회 산불조심 한국서울마라톤,2026-02-22,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
2026 보스턴 영웅 마라톤,2026-02-28,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0, 21.0975]",[],FALSE
3.1절 기념 제19회 120km 무박만세걷기,2026-02-28,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 32.0, 60.0, 120.0]",[],FALSE
JUST RUN10 세종,2026-02-28,08:00,세종,세종 일원,36.4801,127.289,city,"[5.0, 10.0]",[],FALSE
2026 구미 박정희 마라톤,2026-03-01,08:00,경북,구미 일원,36.1195,128.3446,city,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
2026 머니투데이방송 삼일절 마라톤,2026-03-01,08:00,서울,뚝섬한강공원 수변무대,37.5297,127.0668,venue,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
2026 환경사랑부산 K-런,2026-03-01,08:00,부산,부산 일원,35.1796,129.0756,city,"[5.0, 10.0]",[],FALSE
3.1절 107주년 기념 단축 마라톤,2026-03-01,08:00,인천,인천 일원,37.4563,126.7052,city,"[5.0, 10.0, 21.0975]",[],FALSE
3.1절기념 제27회 건강달리기,2026-03-01,08:00,강원,강원 일원,37.8813,127.7298,city,"[5.0, 10.0]",[],FALSE
삼일절 컴포트 선언 러닝,2026-03-01,08:00,서울,서울 일원,37.5665,126.978,city,[19.19],[],FALSE
제13회 안중근 평화 마라톤,2026-03-01,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0, 21.0975]",[],FALSE
제61회 광주일보 3.1절 전국마라톤,2026-03-01,08:00,전남,광주 일원,35.1595,126.8526,city,"[10.0, 21.0975]",[],FALSE
2026 Run your way HALF RACE SEOUL,2026-03-02,08:00,서울,서울 일원,37.5665,126.978,city,[21.0975],[],FALSE
대전트레일 스피드런,2026-03-07,08:00,대전,대전 일원,36.3504,127.3845,city,"[16.0, 30.0]",[],FALSE
제21회 부산 비치울트라 마라톤,2026-03-07,08:00,부산,부산 해운대 일원,35.1587,129.1604,district,"[50.0, 100.0]",[],FALSE
제2회 서울경기육상연합 하프 마라톤,2026-03-07,08:00,경기,경기 일원,37.2636,127.0286,city,"[5.0, 10.0, 21.0975]",[],FALSE
제4회 코리아오픈 레이스,2026-03-07,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0, 21.0975]",[],FALSE
2026 MBN 블루레이스 거제,2026-03-08,08:00,경남,거제 일원,34.8806,128.6211,city,"[4.0, 10.0, 21.0975]",[],FALSE
2026 고양특례시 하프마라톤,2026-03-08,08:00,경기,고양 일원,37.6584,126.832,city,"[5.0, 10.0, 21.0975]",[],FALSE
2026 부천국제10km로드레이스,2026-03-08,08:00,경기,부천 일원,37.5034,126.766,city,"[3.5, 10.0]",[],FALSE
2026 성주참외 전국마라톤,2026-03-08,08:00,경북,성주 일원,35.919,128.283,city,"[5.0, 10.0, 21.0975, 30.0]",[],FALSE
2026 전국민 러닝크루 패밀리 마라톤,2026-03-08,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0, 21.0975]",[],FALSE
제12회 여수시장배 트레일레이스,2026-03-08,08:00,전남,여수 일원,34.7604,127.6622,city,[14.0],[],FALSE
제16회 여의도 벚꽃 마라톤,2026-03-08,08:00,서울,여의도 한강공원,37.5284,126.9327,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 금산 인삼 마라톤,2026-03-14,08:00,충남,금산 일원,36.1086,127.4881,city,"[5.0, 10.0, 21.0975]",[],FALSE
2026 제1회 보은 보청천 마라톤,2026-03-14,08:00,충북,보은 보청천 일원,36.489,127.729,district,"[5.0, 10.0, 21.0975]",[],FALSE
제20회 창녕부곡 온천마라톤,2026-03-14,08:00,경남,창녕 부곡 일원,35.4258,128.596,district,"[5.0, 10.0, 21.0975]",[],FALSE
2026 서울마라톤 (제96회 동아마라톤),2026-03-15,08:00,서울,광화문광장,37.5716,126.9767,venue,"[10.0, 42.195]",[],FALSE
2026 JUST RUN10 청주,2026-03-21,08:00,충북,청주 일원,36.6424,127.489,city,"[5.0, 10.0]",[],FALSE
2026 남해트레일레이스,2026-03-21,08:00,경남,남해 일원,34.8376,127.8925,city,[40.0],[],FALSE
2026 내포마라톤,2026-03-21,08:00,충남,충남 내포 일원,36.659,126.673,district,"[5.0, 10.0, 21.0975]",[],FALSE
2026 지리산봄꽃레이스,2026-03-21,08:00,전남,지리산 일원,35.202,127.463,city,"[13.0, 24.0]",[],FALSE
제1회 춘천 소양강마라톤,2026-03-21,08:00,강원,춘천 소양강 일원,37.9,127.718,district,"[5.0, 10.0]",[],FALSE
제6회 2026 버킷런,2026-03-21,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0]",[],FALSE
2026 HEAT & RUN,2026-03-22,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0]",[],FALSE
2026 산불조심 한국남산우정마라톤,2026-03-22,08:00,서울,남산 일원,37.5512,126.9882,district,"[8.0, 16.0]",[],FALSE
2026 정읍동학마라톤,2026-03-22,08:00,전북,정읍 일원,35.5699,126.856,city,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
서울 K-마라톤대회,2026-03-22,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 21.0975]",[],FALSE
제24회 성우하이텍배 KNN 환경마라톤,2026-03-22,08:00,부산,부산 일원,35.1796,129.0756,city,"[5.0, 10.0]",[],FALSE
제26회 인천국제하프마라톤,2026-03-22,08:00,인천,인천문학경기장,37.4353,126.69,venue,"[5.0, 10.0, 21.0975]",[],FALSE
제2회 영광 광풍 마라톤,2026-03-22,08:00,전남,전남 영광 일원,35.277,126.512,city,"[5.0, 10.0, 21.0975]",[],FALSE
제3회 불패마라톤,2026-03-22,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0, 21.0975]",[],FALSE
2026 금강울트라마라톤,2026-03-28,08:00,세종,세종 금강 일원,36.48,127.289,city,"[50.0, 100.0]",[],FALSE
2026 봄바람 유러닝페스타,2026-03-28,08:00,경기,경기 일원,37.2636,127.0286,city,"[5.0, 10.0, 21.0975]",[],FALSE
2026 여수 영취산 진달래 트레일레이스,2026-03-28,08:00,전남,여수 영취산 일원,34.789,127.685,district,[12.0],[],FALSE
2026 제3회 구리시 걷기&트레일런,2026-03-28,08:00,경기,경기 구리 망우산둘레길,37.599,127.106,district,"[6.4, 9.0]",[],FALSE
2026 팀 K리그 런,2026-03-28,08:00,서울,서울 일원,37.5665,126.978,city,[10.0],[],FALSE
제23회 태화강 마라톤,2026-03-28,08:00,울산,태화강 둔치,35.547,129.305,venue,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
제28회 서귀포 유채꽃국제걷기대회,2026-03-28,08:00,제주,서귀포 일원,33.2541,126.56,city,"[5.0, 12.0, 22.0]",[],FALSE
제2회 의성마늘마라톤,2026-03-28,08:00,경북,의성 일원,36.3526,128.697,city,"[5.0, 10.0]",[],FALSE
제42회 코오롱구간마라톤대회,2026-03-28,08:00,경북,경북 일원,36.576,128.5056,city,[],[],TRUE
2026 무주반딧불 하프마라톤,2026-03-29,08:00,전북,무주 일원,36.0069,127.6608,city,"[5.0, 10.0, 21.0975]",[],FALSE
제20회 정남진장흥 전국마라톤,2026-03-29,08:00,전남,장흥 일원,34.6816,126.907,city,"[5.0, 10.0, 21.0975]",[],FALSE
제25회 합천벚꽃마라톤,2026-03-29,08:00,경남,합천 일원,35.5665,128.1659,city,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
제33회 315마라톤,2026-03-29,08:00,경남,경남 창원 마산 일원,35.197,128.568,city,"[5.0, 10.0]",[],FALSE
제33회 경주벚꽃마라톤,2026-04-04,08:00,경북,경주 보덕동행정복지센터 헬기장,35.848,129.286,district,"[5.0, 10.0, 21.0975]",[],FALSE
2026 대구국제마라톤,2026-04-05,08:00,대구,대구스타디움,35.8296,128.6893,venue,"[5.3, 10.9, 42.195]",[],FALSE
2026 인천마라톤 (상반기),2026-04-11,08:00,인천,인천문학경기장,37.4353,126.69,venue,"[5.0, 10.0, 42.195]",[],FALSE
2026 광주마라톤,2026-04-12,08:00,광주,광주월드컵경기장,35.1338,126.875,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2026 DMZ 평화마라톤,2026-04-19,08:00,경기,임진각 평화누리,37.8895,126.7404,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 군산새만금마라톤,2026-04-19,08:00,전북,군산 새만금 일원,35.9,126.6,city,"[10.0, 21.0975, 42.195]",[],FALSE
2026 서울하프마라톤 (조선일보),2026-04-26,08:00,서울,광화문광장,37.5716,126.9767,venue,"[10.0, 21.0975]",[],FALSE
2026 제주국제마라톤 (평화의섬),2026-04-26,08:00,제주,제주대학교 대운동장,33.456,126.562,venue,"[10.0, 21.0975, 42.195]",[],FALSE
불수사도북 트레일런,2026-05-03,08:00,서울,공릉동 백세문,37.6259,127.0855,district,[],"[""트레일""]",TRUE
2026 전주마라톤,2026-05-10,08:00,전북,전주종합경기장,35.8395,127.1287,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2026 서울신문 하프마라톤,2026-05-16,08:00,서울,상암 평화의공원 평화광장,37.5697,126.8973,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 강릉마라톤,2026-05-17,08:00,강원,강릉 일원,37.7519,128.8761,city,"[10.0, 21.0975, 42.195]",[],FALSE
2026 물사랑 낙동강 200km 울트라마라톤,2026-06-05,21:00,부산 사하구,을숙도물문화센터,35.105,128.946,venue,"[100.0, 200.0]",[],FALSE
2026 도시가스 트레일 온 런 강원,2026-06-06,09:00,강원 강릉시,강릉경포호수광장,37.7953,128.8964,venue,"[4.4, 12.0, 24.0]","[""트레일""]",FALSE
2026 명품-FAAB 한강 브릿지런,2026-06-06,08:00,경기 구리시,구리 한강시민공원,37.5806,127.1258,venue,[60.0],"[""울트라""]",FALSE
2026 춘천봄내마라톤,2026-06-06,09:00,강원 춘천시,춘천시청 호반광장 일원,37.8813,127.73,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 푸른하늘런,2026-06-06,08:00,서울 마포구,상암 월드컵공원 평화광장,37.5697,126.8973,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 한라산 트레일러닝,2026-06-06,05:00,제주 서귀포시,서귀포 돈내코 야영장,33.284,126.569,venue,"[10.0, 36.0, 50.0, 100.0, 160.9]","[""트레일""]",FALSE
NAMHAE 250K - RUN TO SEA,2026-06-06,06:00,경남 남해군,남해 송정솔바람해변,34.7238,128.06,venue,"[10.0, 20.0]",[],FALSE
제28회 양평이봉주마라톤,2026-06-06,08:30,경기 양평군,양평강상체육공원,37.4838,127.487,district,"[4.0, 10.0, 21.0975]",[],FALSE
제9회 남한산성 트레일러닝,2026-06-06,09:00,서울 송파구,마천역 1번출구,37.4949,127.1527,venue,"[8.0, 15.0]","[""트레일""]",FALSE
2026 THE RACE DAEGU 10K,2026-06-07,08:00,대구 수성구,대구스타디움 동편광장,35.83,128.691,venue,[10.0],[],FALSE
2026 iM뱅크 코리아 오픈 마라톤,2026-06-07,07:30,서울 영등포구,여의도공원 문화의마당,37.5254,126.9236,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 마인드마라톤,2026-06-07,07:30,서울 중구,서울광장,37.5657,126.9779,venue,"[5.0, 10.0, 21.0975]",[],FALSE
제11회 너릿재마라톤,2026-06-07,08:00,전남 화순군,화순 셀레브 카페 입구,35.0645,126.9864,city,"[8.0, 16.0, 24.0]",[],FALSE
제30회 제주관광마라톤 축제,2026-06-07,08:00,제주 제주시,구좌종합운동장,33.522,126.856,district,"[10.0, 21.0975, 42.195]",[],FALSE
2026 강릉헌화로11K Run,2026-06-13,08:00,강원,강릉 헌화로 일원,37.676,129.048,district,[11.0],[],FALSE
2026 성남마라톤,2026-06-13,08:00,경기,성남 일원,37.42,127.1265,city,"[5.0, 10.0, 21.0975]",[],FALSE
2026 운탄고도 스카이레이스,2026-06-13,08:00,강원,강원 탄광지대 일원,37.164,128.9856,city,[21.0975],[],FALSE
2026 제23회 빛고을 울트라마라톤,2026-06-13,08:00,광주,광주 일원,35.1595,126.8526,city,"[50.0, 100.0]",[],FALSE
2026 컬처런,2026-06-13,09:00,인천 중구,영종도 씨사이드파크 일원,37.488,126.556,venue,"[10.0, 21.0975]",[],FALSE
제12회 시각장애인과 함께하는 어울림 마라톤,2026-06-13,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0, 21.0975]",[],FALSE
제22회 설악국제트레킹페스티벌,2026-06-13,08:00,강원,설악산 일원,38.1732,128.478,district,"[5.0, 10.0, 20.0]",[],FALSE
2026 김해숲길마라톤,2026-06-14,08:30,경남 김해시,김해종합운동장 및 숲길 일원,35.225,128.876,district,"[5.0, 10.0, 21.0975]",[],FALSE
2026 대전월드런마라톤축제,2026-06-14,08:00,대전,대전 일원,36.3504,127.3845,city,"[5.0, 10.0, 21.0975]",[],FALSE
2026 제21회 울릉도전국마라톤,2026-06-14,05:00,경북 울릉군,울릉예술문화체험장,37.4844,130.9057,city,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
제22회 영덕해변전국마라톤,2026-06-14,08:30,경북 영덕군,고래불해수욕장,36.554,129.411,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 웰메이드런,2026-06-20,07:30,경기 남양주시,남양주한강공원 삼패지구,37.573,127.172,venue,"[5.0, 10.0, 21.0975]",[],FALSE
JUST RUN 10 성남,2026-06-20,08:00,경기,성남 일원,37.42,127.1265,city,"[5.0, 10.0]",[],FALSE
제16회 국민행복마라톤,2026-06-20,09:00,서울 광진구,서울 뚝섬한강공원 수변광장,37.5297,127.0668,venue,"[5.0, 10.0, 21.0975]",[],FALSE
제25회 충주마라톤,2026-06-20,07:30,충북 충주시,충주종합운동장,36.974,127.935,district,"[5.0, 10.0, 21.0975]",[],FALSE
제2회 희망 서울 마라톤,2026-06-20,08:00,서울 영등포구,여의도공원 문화의마당,37.5254,126.9236,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 람사르습지 밤섬런,2026-06-21,08:00,서울 영등포구,여의도 한강공원 물빛무대,37.527,126.931,venue,"[5.0, 10.0]",[],FALSE
2026 보은 속리산 말티재 힐링 알몸 마라톤,2026-06-21,07:50,충북 보은군,보은군 속리산 말티고개,36.523,127.776,venue,"[5.0, 10.0]",[],FALSE
2026 참행복나눔 마라톤,2026-06-21,08:00,서울 마포구,상암 월드컵공원 평화광장,37.5697,126.8973,venue,"[5.0, 10.0, 21.0975]",[],FALSE
월리를 찾아라런 in 서울 2026,2026-06-21,07:30,서울 영등포구,여의도공원 문화의마당,37.5254,126.9236,venue,"[5.0, 10.0]",[],FALSE
제11회 소백산 국망봉 트레일,2026-06-21,08:00,경북,소백산 국망봉 일원,36.956,128.48,district,"[10.0, 28.0]",[],FALSE
2026 순천 치유 미식 트레일런,2026-06-27,08:00,전남,순천 일원,34.9506,127.4872,city,"[7.0, 14.0]",[],FALSE
2026 큰별 하프 마라톤,2026-06-27,08:00,서울 마포구,상암 월드컵공원 평화광장,37.5697,126.8973,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 서울런,2026-06-28,08:00,서울 영등포구,여의도공원 문화의마당,37.5254,126.9236,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 울산남구청장배 육상대회,2026-06-28,08:30,울산 남구,태화강둔치 (태화다리 밑),35.55,129.31,venue,"[5.0, 10.0]",[],FALSE
2026 전국블루베리마라톤축제,2026-06-28,08:00,전북 정읍시,정읍 대흥무지개센터,35.5699,126.856,city,"[5.0, 10.0]",[],FALSE
THE PACER SERIES,2026-06-28,08:00,충북 청주시,청남대 (청주시 상당구 문의면),36.462,127.49,venue,"[5.0, 10.0]",[],FALSE
송도 이봉주 마라톤,2026-06-28,08:00,인천 연수구,인천대학교 송도캠퍼스,37.375,126.632,venue,"[5.0, 10.0]",[],FALSE
제1회 리프레시런,2026-06-28,08:00,경기 하남시,하남 미사경정공원,37.5931,127.18,venue,"[5.0, 10.0]",[],FALSE
제20회 강북구청장배 마라톤,2026-06-28,08:30,서울 강북구,강북구 도봉로102길 21,37.638,127.025,district,"[5.0, 10.0]",[],FALSE
2026 전마협 하계 무료 훈련 마라톤,2026-07-04,08:00,충남,충남 일원,36.6015,126.661,city,"[5.0, 10.0]",[],FALSE
IRON RUN 2026,2026-07-04,08:00,경북 포항시,포항 영일대해수욕장 장미광장,36.06,129.38,venue,"[3.8, 7.87, 15.38]",[],FALSE
제10회 노원구청장배 겸 회장배마라톤,2026-07-05,08:30,서울 노원구,창동교 나눔의 광장,37.647,127.048,district,"[5.0, 10.0]",[],FALSE
제8회 인왕산 서울 트레일런,2026-07-05,08:00,서울,인왕산 일원,37.5826,126.9576,district,[10.0],[],FALSE
2026 전마협 무주 풀코스 마라톤,2026-07-11,06:30,전북 무주군,무주 소이나루 공원,36.006,127.665,district,"[4.0, 8.0, 12.0, 24.0, 42.195]",[],FALSE
2026 광제산 트레일 런,2026-07-12,09:10,경남 진주시,홍지소류지 (진주 명석면 계원리),35.235,128.028,district,"[5.0, 10.0, 21.0975]","[""트레일""]",FALSE
2026 울릉도 국제 트레일러닝,2026-07-12,08:00,경북(울릉도),울릉도 일원,37.4844,130.9057,city,"[27.0, 40.0]",[],FALSE
2026 코리아 나이트 런 태백,2026-07-18,17:00,강원 태백시,O2 리조트,37.181,128.941,venue,"[7.0, 17.0, 28.0]",[],FALSE
제2회 울릉나이트런,2026-07-18,08:00,경북(울릉도),울릉도 일원,37.4844,130.9057,city,[10.0],[],FALSE
2026 청계산.인릉산 트레일런,2026-07-19,08:00,서울 서초구,청계산 옛골 (화물터미널),37.43,127.06,district,"[12.0, 21.0975]","[""트레일""]",FALSE
2026 쿨밸리트레일레이스,2026-07-19,08:00,전북,전북 일원,35.8242,127.148,city,[18.0],[],FALSE
제16회 태종대혹서기전국마라톤,2026-07-19,06:00,부산 영도구,태종대공원,35.059,129.086,venue,"[7.0, 10.0, 21.0975]",[],FALSE
사우나런 in 올림픽공원,2026-07-31,08:00,서울 송파구,올림픽공원 인근,37.5209,127.1215,venue,"[5.0, 10.0]",[],FALSE
2026 인사이더런 S,2026-08-01,09:30,경기,"일산 킨텍스 제2전시장 7,8",37.6668,126.7457,venue,[10.0],[],FALSE
제1회 테마임도 트레일런,2026-08-08,07:00,부산 금정구,부산스포원,35.268,129.094,venue,[50.0],"[""트레일""]",FALSE
2026 815런,2026-08-15,08:00,서울,서울 일원,37.5665,126.978,city,[8.15],[],FALSE
2026 안양천 달빛 나이트런,2026-08-15,18:30,서울 양천구,신정교 하부 영롱이 억새구장,37.516,126.869,district,"[5.0, 10.0]",[],FALSE
2026 장수 나이트 트레일,2026-08-15,19:00,전북 장수군,장수종합경기장,35.647,127.521,district,[38.0],"[""트레일""]",FALSE
영남알프스9봉 트레일 레이스,2026-08-15,14:00,경남 밀양시,청운산장,35.5038,128.7467,city,[87.0],"[""트레일""]",FALSE
제38회 지리산화대종주 UTMB,2026-08-15,03:00,전남 구례군,화엄사주차장,35.252,127.494,venue,"[40.0, 48.0]",[],FALSE
2026 금수산트레일러닝대회,2026-08-23,08:00,충북 제천시,청풍리조트,37.01,128.171,venue,"[13.0, 22.0]",[],FALSE
2026 대구세계마스터즈 10km대회,2026-08-23,07:00,대구 수성구,대구스타디움 일원,35.8296,128.6893,venue,[10.0],[],FALSE
2026 단양달빛레이스,2026-08-29,19:00,충북 단양군,단양생태체육공원,36.987,128.359,venue,"[5.0, 10.0]",[],FALSE
2026 대구세계마스터즈 하프마라톤대회,2026-08-30,07:00,대구 수성구,신천동로 일원,35.86,128.61,district,[21.0975],[],FALSE
제3회 GO대관령 국제 트레일런,2026-08-30,07:30,강원 평창군,평창동계올림픽기념공원,37.668,128.709,venue,"[10.0, 20.18, 44.0]","[""트레일""]",FALSE
제3회 한강 서울 하프 마라톤,2026-08-30,08:00,서울 영등포구,여의도 한강공원 물빛광장,37.529,126.933,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 다이나핏 태백 트레일,2026-09-05,06:00,강원 태백시,태백 소원지 오토캠핑장,37.164,128.9856,city,"[32.0, 50.0]","[""트레일""]",FALSE
2026 하반기 JUST RUN10 세종,2026-09-05,08:00,세종특별자치시,세종마루공원 밑 금강변,36.478,127.285,district,"[5.0, 10.0]",[],FALSE
제12회 I LOVE 방송대 마라톤,2026-09-05,08:00,서울 마포구,상암동 평화광장,37.5697,126.8973,venue,"[5.0, 10.0]",[],FALSE
제20회 순천만울트라마라톤대회,2026-09-05,08:00,전남,순천만 일원,34.885,127.509,district,[102.0],[],FALSE
제23회 철원DMZ국제평화마라톤,2026-09-05,09:00,강원 철원군,철원 고석정,38.1786,127.2759,venue,"[10.0, 21.0975, 42.195]",[],FALSE
제2회 2026 Vrun,2026-09-05,09:00,서울 양천구,신정교하부 육상트랙구장,37.515,126.868,district,"[5.0, 10.0]",[],FALSE
2026 봉화송이 전국마라톤,2026-09-06,10:00,경북 봉화군,봉화공설운동장,36.8931,128.7326,district,"[5.0, 10.0, 21.0975]",[],FALSE
2026 샌드런 IN 영덕,2026-09-06,10:00,경북 영덕군,영덕 대진해수욕장,36.533,129.419,venue,"[4.0, 8.0]",[],FALSE
2026 전마협회장배 청주마라톤,2026-09-06,07:30,충북 청주시,청주 무심천 체육공원,36.62,127.483,district,"[5.0, 10.0]",[],FALSE
제11회 김대중 평화 마라톤 대회,2026-09-06,08:00,서울 광진구,뚝섬 한강공원 수변무대,37.5297,127.0668,venue,"[5.0, 10.0, 21.0975]",[],FALSE
제9회 인천 서구청장배 단축마라톤,2026-09-06,08:30,인천 서구,청라호수공원 멀티프라자 트랙,37.533,126.655,venue,"[4.3, 10.0]",[],FALSE
희망드림 제23회 새벽강변 국제마라톤,2026-09-06,07:30,서울 양천구,목동운동장,37.5309,126.8752,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 양양 강변 전국 마라톤,2026-09-12,10:00,강원 양양군,양양군 웰컴센터,38.075,128.625,district,"[5.0, 10.0, 21.0975]",[],FALSE
빵트레일런 2026,2026-09-12,08:00,강원 정선군,정선 하이원리조트,37.208,128.825,venue,"[10.0, 20.0, 30.0]","[""트레일""]",FALSE
제2회 초록우산 런웨이 마라톤,2026-09-12,08:00,대전 유성구,대전엑스포시민광장,36.3745,127.389,venue,"[3.0, 5.0, 10.0, 21.0975]",[],FALSE
2026 런서울런,2026-09-13,07:30,서울 중구,서울광장,37.5657,126.9779,venue,"[10.0, 21.0975]",[],FALSE
2026 울진금강송힐링마라톤,2026-09-13,09:00,경북 울진군,울진종합운동장,36.986,129.398,district,"[5.0, 10.0, 21.0975]",[],FALSE
2026 포항이차전지전국마라톤,2026-09-13,08:00,경북 포항시,포항운하관주차장,36.0215,129.3675,venue,"[5.0, 10.0, 21.0975]",[],FALSE
제14회 설악산 공룡능선 UTMB,2026-09-13,08:00,강원,설악산 일원,38.1732,128.478,district,"[22.0, 27.0]",[],FALSE
제16회 스마일 런 페스티벌,2026-09-13,08:00,서울,서울 일원,37.5665,126.978,city,"[5.0, 10.0, 21.0975]",[],FALSE
제26회 강화해변마라톤대회,2026-09-13,08:30,인천 강화군,강화함상공원,37.747,126.488,city,"[5.0, 10.0, 21.0975]",[],FALSE
2026 금산인삼축제 마라톤,2026-09-19,08:30,충남 금산군,금산세계인삼엑스포주차장,36.102,127.486,venue,"[4.0, 10.0, 21.0975]",[],FALSE
서울수복 75주년 기념 아라뱃길 나이트워크,2026-09-19,08:00,인천,인천 아라뱃길 일원,37.567,126.65,city,"[5.0, 20.0, 30.0, 66.0]",[],FALSE
제18회 사이버 영토 수호 마라톤,2026-09-19,08:00,서울 영등포구,여의도 물빛무대 앞 광장,37.527,126.931,venue,"[3.0, 5.0, 10.0, 21.0975]",[],FALSE
2026 인천송도국제마라톤,2026-09-20,07:30,인천 연수구,인천대학교 송도캠퍼스 정문,37.375,126.632,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 공주마라톤,2026-09-20,08:00,충남 공주시,공주시민운동장,36.4465,127.1189,city,"[10.0, 21.0975, 32.0, 42.195]",[],FALSE
2026 동대문마라톤,2026-09-20,08:30,서울 동대문구,중랑천 제1수변공원,37.58,127.06,district,"[5.0, 10.0, 21.0975]",[],FALSE
2026 한돈런,2026-09-20,08:00,경기 하남시,미사경정공원 조정경기장,37.5931,127.18,venue,"[5.0, 10.0]",[],FALSE
2026(20회) 선사마라톤 축제,2026-09-20,09:00,서울 강동구,서울 암사동 유적 앞 특설무대,37.551,127.131,venue,"[5.0, 10.0, 21.0975]",[],FALSE
제19회 가평자라섬 전국마라톤,2026-09-20,08:30,경기 가평군,가평종합운동장,37.825,127.512,district,"[5.0, 10.0, 21.0975]",[],FALSE
제2회 마포구청장배 마라톤 대회,2026-09-20,08:30,서울 마포구,상암 월드컵공원 평화광장,37.5697,126.8973,venue,"[5.0, 10.0]",[],FALSE
2026 서산 코스모스 황금들녘 마라톤 대회,2026-10-03,09:00,충남 서산시,서산스포츠테마파크,36.7848,126.4503,city,"[5.0, 10.0, 21.0975]",[],FALSE
2026 완주트레일런,2026-10-03,07:00,전북 완주군,완주군 고산자연휴양림,35.975,127.245,venue,[36.0],"[""트레일""]",FALSE
2026 천사데이기념 동두천천사마라톤,2026-10-03,09:00,경기 동두천시,동두천 캠프보산,37.913,127.056,district,"[5.0, 10.0]",[],FALSE
제25회 김제새만금 지평선 전국마라톤,2026-10-03,09:00,전북 김제시,김제시민운동장 일원,35.8036,126.8809,district,"[5.0, 10.0, 21.0975]",[],FALSE
제25회 앵봉산 서울트레일러닝,2026-10-03,08:00,서울,앵봉산 일원,37.618,126.921,district,"[5.0, 18.0]",[],FALSE
2026 YTN 서울투어마라톤,2026-10-04,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 21.0975]",[],FALSE
2026 뉴발란스 런 유어 웨이 서울 10K,2026-10-04,07:30,서울,여의도공원 문화의마당,37.5285,126.9245,venue,[10.0],[],FALSE
2026 안동마라톤,2026-10-04,08:00,경북 안동시,안동시민운동장,36.565,128.712,district,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
2026 파주북시티마라톤,2026-10-04,08:40,경기 파주시,파주출판도시,37.711,126.689,venue,"[3.0, 5.0, 10.0]",[],FALSE
2026 홍천사랑마라톤,2026-10-04,09:00,강원 홍천군,홍천종합운동장,37.69,127.89,district,"[5.0, 10.0, 21.0975]",[],FALSE
제20회 달서하프마라톤,2026-10-04,08:30,대구 달서구,대구 달서구 호림강나루공원,35.8383,128.509,district,"[5.0, 10.0, 21.0975]",[],FALSE
2026 서울오픈마라톤,2026-10-05,07:30,서울 종로구,광화문광장,37.5716,126.9767,venue,"[10.0, 21.0975]",[],FALSE
제26회 홍성마라톤,2026-10-09,08:00,충남 홍성군,홍주종합경기장,36.595,126.668,district,"[5.0, 10.0, 21.0975]",[],FALSE
2026 경포마라톤,2026-10-10,08:30,강원 강릉시,강릉 경포해변,37.8054,128.9077,venue,"[5.0, 10.0, 21.0975]",[],FALSE
제5회 무등산지오마라톤,2026-10-10,07:00,전남 화순군,화순 금호스파리조트,35.0645,126.9864,city,"[5.0, 10.0, 21.0975, 30.0]",[],FALSE
제7회 천안삼거리 흥타령울트라마라톤,2026-10-10,08:00,충남,천안 일원,36.8151,127.1139,city,"[60.0, 100.0]",[],FALSE
제9회 거제시장배 섬꽃 전국 마라톤,2026-10-10,08:30,경남 거제시,거제스포츠파크,34.895,128.63,district,"[4.0, 10.0, 21.0975]",[],FALSE
2026 MBN 전국 나주 마라톤대회,2026-10-11,08:00,전남 나주시,나주종합스포츠파크,35.019,126.706,district,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
2026 서울레이스,2026-10-11,07:30,서울 중구,서울광장,37.5657,126.9779,venue,"[10.0, 21.0975]",[],FALSE
2026 평택항마라톤,2026-10-11,09:00,경기 평택시,평택항 엠에스로지스틱 일원,36.968,126.835,district,"[5.0, 10.0, 21.0975]",[],FALSE
제10회 가을철 산불조심마라톤,2026-10-11,08:00,서울 강남구,광평교운동장,37.4867,127.0797,district,"[5.0, 10.0, 21.0975, 31.0, 42.195]",[],FALSE
2026 서울달리기대회,2026-10-17,08:00,서울,여의도 한강공원,37.5284,126.9327,venue,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
2026 정선동강 마라톤,2026-10-17,09:00,강원 정선군,정선생태체험학습장,37.379,128.66,district,"[5.0, 10.0, 21.0975]",[],FALSE
제24회 청원생명쌀대청호마라톤,2026-10-17,08:40,충북 청주시,문의체육공원,36.515,127.49,district,"[5.0, 10.0, 21.0975, 42.195]",[],FALSE
2026 대전마라톤,2026-10-18,08:00,대전,대전 일원,36.3504,127.3845,city,"[10.0, 21.0975, 42.195]",[],FALSE
그린스텝 2026,2026-10-18,09:00,전남 해남군,해남 솔라시도,34.605,126.375,district,"[5.0, 10.0, 21.0975]",[],FALSE
제22회 대구 북구사랑 마라톤,2026-10-18,09:00,대구 북구,금호강 산격야영장,35.895,128.605,district,"[5.0, 10.0]",[],FALSE
제23회 여주 세종대왕 마라톤,2026-10-18,08:30,경기 여주시,여주 현암지구공원,37.306,127.628,district,"[4.0, 10.0, 21.0975]",[],FALSE
제25회 대청호마라톤,2026-10-18,09:00,대전 대덕구,대청공원,36.477,127.48,district,"[5.0, 10.0, 21.0975]",[],FALSE
제34회 경주국제마라톤,2026-10-18,08:00,경북,경주시민운동장,35.857,129.218,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2026 제3회 감성런,2026-10-24,09:00,서울 양천구,신정교하부 육상트랙구장,37.515,126.868,district,"[5.0, 10.0]",[],FALSE
2026 청송사과트레일런,2026-10-25,10:00,경북 청송군,청송군민운동장,36.436,129.057,district,"[5.0, 10.0, 21.0975]","[""트레일""]",FALSE
2026 춘천마라톤,2026-10-25,09:00,강원 춘천시,춘천 공지천공원,37.872,127.718,venue,"[10.0, 42.195]",[],FALSE
K-RUN 챌린지,2026-10-25,09:00,서울 광진구,서울 뚝섬한강공원 수변광장,37.5297,127.0668,venue,"[5.0, 10.0, 21.0975]",[],FALSE
제19회 청도반시 전국마라톤,2026-10-25,09:30,경북 청도군,청도공설운동장,35.6474,128.7336,district,"[5.9, 10.0, 21.0975]",[],FALSE
2026 JTBC 마라톤,2026-11-01,08:00,서울 마포구,상암 월드컵공원 평화광장,37.5697,126.8973,venue,"[10.0, 42.195]",[],FALSE
2026 김천전국마라톤대회,2026-11-01,09:30,경북 김천시,김천종합스포츠타운,36.128,128.11,district,"[5.0, 10.0, 21.0975]",[],FALSE
2026 무안 해안 노을길 걷기 및 마라톤,2026-11-01,08:00,전남,무안낙지공원,34.9904,126.4816,city,"[5.0, 10.0]",[],FALSE
제21회 울산인권마라톤,2026-11-01,09:30,울산 중구,태화강 둔치 (태화교 일원),35.552,129.312,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 영천댐 마라톤,2026-11-07,09:40,경북 영천시,영천댐 하류공원,35.9733,128.9386,city,"[5.0, 10.0, 21.0975]",[],FALSE
2026 양산 배내골 애플 런,2026-11-08,09:00,경남 양산시,배내골 장선마을회관 앞 운동장,35.44,128.99,district,"[5.0, 10.0]",[],FALSE
2026 인천마라톤 (하반기),2026-11-08,08:00,인천,인천문학경기장,37.4353,126.69,venue,"[5.0, 10.0, 42.195]",[],FALSE
2026 제주 감귤 마라톤,2026-11-08,08:00,제주,서귀포 강정천 일원,33.247,126.482,district,"[10.0, 21.0975, 42.195]",[],FALSE
제11회 송파구청장배 마라톤,2026-11-08,09:00,서울 송파구,송파구 여성축구장,37.498,127.108,district,"[5.0, 10.0]",[],FALSE
2026 포항마라톤챔피언십,2026-11-14,09:00,경북 포항시,영일대해상누각,36.0568,129.3785,venue,"[5.0, 10.0]",[],FALSE
2026 MBN 서울마라톤,2026-11-15,07:30,서울 종로구,광화문광장 (출발) / 잠실종합운동장 (도착),37.5716,126.9767,venue,"[10.0, 21.0975]",[],FALSE
2026 가민런 코리아,2026-11-15,08:00,경기 고양시,고양종합운동장,37.6703,126.7433,venue,"[10.0, 21.0975]",[],FALSE
제24회 고창고인돌마라톤,2026-11-15,10:00,전북 고창군,고창공설운동장,35.4358,126.702,district,"[5.0, 10.0, 21.0975]",[],FALSE
제24회 대모산 구룡산 트레일런,2026-11-15,08:00,서울,수서역 7번출구 광장,37.4871,127.1017,venue,[10.0],[],FALSE
제24회 상주 곶감 마라톤 대회,2026-11-15,09:00,경북 상주시,상주시민운동장,36.4109,128.159,district,"[4.4, 10.0, 21.0975, 42.195]",[],FALSE
제2회 세종특별자치시 전국 마라톤,2026-11-15,09:30,세종특별자치시,세종시민운동장,36.601,127.293,district,"[5.0, 10.0]",[],FALSE
제3회 무등산더블하트국제트레일런,2026-11-15,08:00,광주,조선대학교,35.1397,126.9327,venue,"[16.0, 36.0]",[],FALSE
제4회 영남알프스 전국 하프마라톤,2026-11-15,09:00,울산 울주군,울주 영남알프스 복합웰컴센터,35.562,129.008,venue,"[5.0, 10.0, 21.0975]",[],FALSE
2026 울산마라톤,2026-11-22,08:00,울산,태화강 둔치,35.547,129.305,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2026 화성행궁마라톤,2026-11-22,08:00,경기,화성행궁 광장,37.2816,127.0137,venue,"[10.0, 21.0975, 42.195]",[],FALSE
2026 여수 일레븐 브리지 마라톤,2026-11-29,08:00,전남,여수 일원,34.7604,127.6622,city,"[10.0, 21.0975, 42.195]",[],FALSE
2026 황영조와 함께하는 전국 로드레이스,2026-11-29,08:00,전남,전남 일원,34.8161,126.4629,city,[],[],TRUE
2026 양산 전국 하프마라톤,2026-12-05,08:00,경남,양산 일원,35.335,129.037,city,"[10.0, 21.0975]",[],FALSE
2026 시즌마감 마라톤대회,2026-12-12,08:00,서울,서울 일원,37.5665,126.978,city,"[10.0, 21.0975, 42.195]",[],FALSE
2027 서울마라톤,2027-03-21,07:30,서울,광화문광장 (풀코스 출발) / 잠실종합운동장 (10km 도착),37.5720,126.9769,venue,"[10.0, 42.195]",[],FALSE
"""#
}
