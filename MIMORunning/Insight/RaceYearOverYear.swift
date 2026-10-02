import Foundation

/// 대회 해마다 비교(A단계) — 같은 대회의 지난해, 같은 거리의 지난 대회와 결과를 비교한다.
///
/// 순수 로직(HealthKit·SwiftUI 의존 없음). 설계 `2026-09-27-race-year-over-year-design.md`.
///  · 같은 대회: 시리즈가 같고 공식 종목 거리가 ±2% 안.
///  · 같은 거리: 나머지 중 종목 거리가 10% 안, 최신 5개.
///  · 차이: 종목 거리가 ±2% 안이면 완주 시간, 아니면 km당 페이스. 더위 보정 없음.
///  · 부연 줄: 같은 대회 최신 > 같은 거리 최신. 1초 이상 빨라졌을 때만 차이를 말한다(하락은 조용히).
enum RaceYearOverYear {

    /// 확정된 대회 러닝 하나.
    struct Entry: Equatable {
        let activityID: UUID
        let raceName: String
        let date: Date
        /// 공식 종목 거리(km)
        let distanceKm: Double
        let durationSec: TimeInterval
        let tempC: Double?
        let series: String?
    }

    enum Delta: Equatable {
        /// 과거 − 오늘 완주 시간(초). +면 오늘이 빠르다.
        case time(seconds: Int)
        /// 과거 − 오늘 km당 페이스(초). +면 오늘이 빠르다.
        case pace(secondsPerKm: Int)

        var isTodayFaster: Bool {
            switch self {
            case .time(let s):         return s >= 1
            case .pace(let s):         return s >= 1
            }
        }
    }

    struct Row: Identifiable, Equatable {
        let id: UUID
        let date: Date
        /// 표시 이름. 오늘과 종목 거리가 다르면 "○○ 20K"처럼 종목을 붙인다.
        let title: String
        let durationSec: TimeInterval
        let tempC: Double?
        /// nil = 오늘 행
        let delta: Delta?

        var isToday: Bool { delta == nil }
    }

    /// 같은 시리즈 지난 해 대회로 보이지만 확신이 부족한 러닝 — 대회 탭에서 한 번 묻는다.
    struct Question: Identifiable, Equatable {
        let activityID: UUID
        /// 표시 이름(연도·회차 제거)
        let raceName: String
        let year: Int
        let runDate: Date
        var id: UUID { activityID }
    }

    struct Comparison: Equatable {
        let today: Row
        let sameRace: [Row]
        let sameDistance: [Row]
        /// 인사이트 카드 부연 줄. 비교할 과거 대회가 없으면 nil.
        let headline: String?

        var isEmpty: Bool { sameRace.isEmpty && sameDistance.isEmpty }
    }

    static let exactDistanceTolerance = 0.02
    static let sameDistanceTolerance = 0.10
    static let maxSameDistanceRows = 5

    // MARK: - 비교

    static func compare(today: Entry, confirmed: [Entry], calendar: Calendar = .current) -> Comparison {
        let past = confirmed
            .filter { $0.activityID != today.activityID && $0.date < today.date }
            .sorted { $0.date > $1.date }

        let sameRaceEntries = past.filter { e in
            guard let s = today.series, !s.isEmpty, e.series == s else { return false }
            return isSameEvent(e.distanceKm, today.distanceKm)
        }
        let raceIDs = Set(sameRaceEntries.map(\.activityID))
        let sameDistanceEntries = Array(past.filter { e in
            !raceIDs.contains(e.activityID)
            && abs(e.distanceKm - today.distanceKm) / max(today.distanceKm, 0.001) <= sameDistanceTolerance + 1e-9
        }.prefix(maxSameDistanceRows))

        let headline: String?
        if let e = sameRaceEntries.first {
            headline = sentence(target: e, today: today, sameRace: true, calendar: calendar)
        } else if let e = sameDistanceEntries.first {
            headline = sentence(target: e, today: today, sameRace: false, calendar: calendar)
        } else {
            headline = nil
        }

        return Comparison(
            today: Row(id: today.activityID, date: today.date, title: RaceDisplayName.short(today.raceName),
                       durationSec: today.durationSec, tempC: today.tempC, delta: nil),
            sameRace: sameRaceEntries.map { row(for: $0, today: today) },
            sameDistance: sameDistanceEntries.map { row(for: $0, today: today) },
            headline: headline)
    }

    static func delta(past: Entry, today: Entry) -> Delta {
        if isSameEvent(past.distanceKm, today.distanceKm) {
            return .time(seconds: Int((past.durationSec - today.durationSec).rounded()))
        }
        let pastPace = past.durationSec / max(past.distanceKm, 0.001)
        let todayPace = today.durationSec / max(today.distanceKm, 0.001)
        return .pace(secondsPerKm: Int((pastPace - todayPace).rounded()))
    }

    static func isSameEvent(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) / max(b, 0.001) <= exactDistanceTolerance
    }

    // MARK: - 문장

    /// 부연 줄 한 문장. 빨라졌으면 차이, 아니면 지난 기록만.
    static func sentence(target e: Entry, today: Entry, sameRace: Bool, calendar: Calendar = .current) -> String {
        let L = AppLanguage.shared
        let d = delta(past: e, today: today)
        let name = title(e, today: today)
        let yearsAgo = calendar.component(.year, from: today.date) - calendar.component(.year, from: e.date)
        let year = calendar.component(.year, from: e.date)
        let record = mrFormatDisplay(e.durationSec / 60)

        if d.isTodayFaster {
            let amount: String
            switch d {
            case .time(let s): amount = L.s(koreanDuration(s), clockDuration(s))
            case .pace(let s): amount = L.s("km당 \(s)초", "\(s) s/km")
            }
            if sameRace && yearsAgo == 1 { return L.s("작년보다 \(amount) 빠릅니다", "\(amount) faster than last year") }
            if sameRace && yearsAgo >= 2 { return L.s("\(year)년보다 \(amount) 빠릅니다", "\(amount) faster than \(year)") }
            return L.s("지난 \(name)보다 \(amount) 빠릅니다", "\(amount) faster than your last \(name)")
        }
        if sameRace && yearsAgo == 1 { return L.s("작년 \(name) \(record)", "Last year's \(name): \(record)") }
        if sameRace && yearsAgo >= 2 { return L.s("\(year)년 \(name) \(record)", "\(name) \(year): \(record)") }
        return L.s("지난 \(name) \(record)", "Last \(name): \(record)")
    }

    /// 표의 차이 칸 — "+4:12" · "−1:05" · "±0:00" · "km당 +5초"(영어 "+5 s/km").
    static func deltaText(_ d: Delta) -> String {
        func sign(_ v: Int) -> String { v > 0 ? "+" : (v < 0 ? "−" : "±") }
        switch d {
        case .time(let s):
            return sign(s) + clockDuration(abs(s))
        case .pace(let s):
            return AppLanguage.shared.s("km당 \(sign(s))\(abs(s))초", "\(sign(s))\(abs(s)) s/km")
        }
    }

    // MARK: - 내부

    private static func row(for e: Entry, today: Entry) -> Row {
        Row(id: e.activityID, date: e.date, title: title(e, today: today),
            durationSec: e.durationSec, tempC: e.tempC, delta: delta(past: e, today: today))
    }

    private static func title(_ e: Entry, today: Entry) -> String {
        let name = RaceDisplayName.short(e.raceName)
        return isSameEvent(e.distanceKm, today.distanceKm)
            ? name
            : "\(name) \(RaceDisplayName.distanceLabel(km: e.distanceKm))"
    }

    /// "4분 12초" · "1시간 2분 5초" · "30초"
    private static func koreanDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)시간") }
        if m > 0 { parts.append("\(m)분") }
        if s > 0 || parts.isEmpty { parts.append("\(s)초") }
        return parts.joined(separator: " ")
    }

    /// "4:12" · "1:02:05" — 표의 기록 칸도 이 형식(언어 무관, 좁은 칸에 맞게).
    static func clockDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
