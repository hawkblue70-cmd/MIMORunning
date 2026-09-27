import Testing
import Foundation
import CoreLocation
@testable import MIMORunning

/// 대회 해마다 비교 — 확정 매칭의 시리즈와 지난 해 후보 러닝 판정.
@Suite("대회 지난 해 찾기", .korean)
@MainActor
struct RacePastYearTests {

    private func race(_ name: String, _ date: String, _ time: String?,
                      _ lat: Double, _ lng: Double, _ precision: String, series: String?) -> BundledRace {
        BundledRace(name: name, dateString: date, region: "강원", start: "춘천",
                    startLatitude: lat, startLongitude: lng, geoPrecision: precision,
                    distancesKm: [10.0, 42.195], nonStandard: false, startTimeString: time,
                    series: series)
    }

    private var r26: BundledRace { race("2026 춘천마라톤", "2026-10-25", "09:00", 37.872, 127.718, "venue", series: "c") }
    private var r25: BundledRace { race("제46회 조선일보 춘천마라톤", "2025-10-25", "08:00", 37.87, 127.72, "district", series: "c") }
    private var r24: BundledRace { race("제45회 조선일보 춘천마라톤", "2024-10-27", "09:00", 37.878, 127.726, "venue", series: "c") }
    private var spring: BundledRace { race("2026 춘천봄내마라톤", "2026-06-06", "09:00", 37.8813, 127.73, "venue", series: "b") }

    /// 로컬 시간대 기준 날짜+시각(게이트가 Calendar.current를 쓰므로).
    private func localDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private let todayID = UUID()
    private let id25 = UUID()
    private let id24 = UUID()

    private var todayMatch: PersistedRaceMatch {
        PersistedRaceMatch(activityID: todayID, raceName: "2026 춘천마라톤", distanceKm: 42.195,
                           raceDate: r26.date!, isConfirmed: true, isDismissed: false,
                           isManual: false, gateVersion: RaceDetector.gateVersion)
    }

    private func run(_ id: UUID, _ date: Date, km: Double) -> Activity {
        Activity(id: id, type: .running, date: date, duration: 14_000, distance: km * 1000,
                 calories: nil, avgHeartRate: nil)
    }

    private var runs: [Activity] {
        [run(id25, localDate(2025, 10, 25, 8, 2), km: 42.3),
         run(id24, localDate(2024, 10, 27, 9, 3), km: 42.4)]
    }

    private func detector(matches: [PersistedRaceMatch] = []) -> RaceDetector {
        let d = RaceDetector()
        d.loadRacesForTesting([r26, r25, r24, spring])
        d.loadMatchesForTesting(matches)
        return d
    }

    /// 러닝별 출발·도착 좌표 — 각 대회 출발점에서 출발해 같은 곳에 도착.
    private func ends(_ id: UUID) -> (start: CLLocationCoordinate2D, end: CLLocationCoordinate2D?)? {
        switch id {
        case id25: return (r25.startCoordinate!, r25.startCoordinate!)
        case id24: return (r24.startCoordinate!, r24.startCoordinate!)
        default:   return nil
        }
    }

    // MARK: - 매칭 → DB 줄 · 시리즈

    @Test func matchResolvesToBundledRaceAndSeries() {
        let d = detector()
        #expect(d.bundledRace(for: todayMatch)?.name == "2026 춘천마라톤")
        #expect(d.series(for: todayMatch) == "c")
    }

    @Test func manualRaceHasNoSeries() {
        let manual = PersistedRaceMatch(activityID: UUID(), raceName: "우리 동네 10K", distanceKm: 10,
                                        raceDate: localDate(2026, 5, 1, 8, 0), isConfirmed: true,
                                        isDismissed: false, isManual: true, gateVersion: RaceDetector.gateVersion)
        #expect(detector().series(for: manual) == nil)
    }

    // MARK: - 지난 해 후보

    @Test func findsWeakAndStrongCandidatesNewestFirst() async {
        let found = await detector().pastYearCandidates(for: todayMatch, runs: runs) { self.ends($0) }
        #expect(found.map(\.race.name) == ["제46회 조선일보 춘천마라톤", "제45회 조선일보 춘천마라톤"])
        #expect(found.map(\.activityID) == [id25, id24])
        // 2025는 district 정밀도라 자동 확정 불가 → 질문, 2024는 venue·시각·도착 모두 맞음 → 자동 확정
        #expect(found.map(\.strength) == [.weak, .strong])
    }

    @Test func skipsRunAlreadyMarkedNotRace() async {
        let dismissed = PersistedRaceMatch(activityID: id25, raceName: "", distanceKm: 0, raceDate: Date(),
                                           isConfirmed: false, isDismissed: true, isManual: false,
                                           gateVersion: RaceDetector.gateVersion)
        let found = await detector(matches: [dismissed]).pastYearCandidates(for: todayMatch, runs: runs) { self.ends($0) }
        #expect(found.map(\.activityID) == [id24])
    }

    @Test func skipsRaceAlreadyConfirmedWithAnotherRun() async {
        let other = PersistedRaceMatch(activityID: UUID(), raceName: r25.name, distanceKm: 42.195,
                                       raceDate: r25.date!, isConfirmed: true, isDismissed: false,
                                       isManual: false, gateVersion: RaceDetector.gateVersion)
        let found = await detector(matches: [other]).pastYearCandidates(for: todayMatch, runs: runs) { self.ends($0) }
        #expect(found.map(\.activityID) == [id24])
    }

    @Test func requiresSameEventDistanceAsToday() async {
        // 2025 대회 날 10K를 뛰었다 — 그 대회에 10K 종목이 있어도 오늘(풀)과 비교할 러닝이 아니다
        let tenK = [run(id25, localDate(2025, 10, 25, 8, 2), km: 10.1)]
        let found = await detector().pastYearCandidates(for: todayMatch, runs: tenK) { self.ends($0) }
        #expect(found.isEmpty)
    }

    @Test func runWithoutRouteIsSkipped() async {
        let found = await detector().pastYearCandidates(for: todayMatch, runs: runs) { _ in nil }
        #expect(found.isEmpty)
    }

    @Test func raceWithoutSeriesHasNoCandidates() async {
        let manual = PersistedRaceMatch(activityID: todayID, raceName: "우리 동네 풀", distanceKm: 42.195,
                                        raceDate: localDate(2026, 10, 25, 9, 0), isConfirmed: true,
                                        isDismissed: false, isManual: true, gateVersion: RaceDetector.gateVersion)
        let found = await detector().pastYearCandidates(for: manual, runs: runs) { self.ends($0) }
        #expect(found.isEmpty)
    }
}
