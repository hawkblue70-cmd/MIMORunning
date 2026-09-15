import Testing
import Foundation
import CoreLocation
@testable import MIMORunning

/// 대회 매칭 하드 게이트 — 날짜 · 거리 ±5% · 출발 시각 ±90분 · 정밀도별 반경.
@Suite("RaceDetector 매칭 게이트", .korean)
struct RaceDetectorGateTests {

    // 뚝섬 한강공원 수변무대 — 김대중 평화 마라톤 출발지
    private static let ttukseom = CLLocationCoordinate2D(latitude: 37.5297, longitude: 127.0668)

    private func race(
        name: String = "테스트 대회",
        dateString: String = "2026-09-06",
        startTime: String? = "08:00",
        lat: Double? = 37.5297,
        lng: Double? = 127.0668,
        precision: String = "venue",
        distances: [Double] = [5.0, 10.0, 21.0975]
    ) -> BundledRace {
        BundledRace(name: name, dateString: dateString, region: "서울", start: "뚝섬",
                    startLatitude: lat, startLongitude: lng, geoPrecision: precision,
                    distancesKm: distances, nonStandard: false, startTimeString: startTime)
    }

    /// 로컬 시간대 기준으로 날짜+시각을 만든다 (게이트가 Calendar.current를 쓰므로).
    private func localDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return Calendar.current.date(from: c)!
    }

    private func coord(fromKmNorthOf base: CLLocationCoordinate2D, _ km: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: base.latitude + km / 111.0, longitude: base.longitude)
    }

    // MARK: - 통과해야 하는 경우

    @Test func actualRacePasses() {
        let d = RaceDetector()
        #expect(d.passesHardGate(race: race(), date: localDate(2026, 9, 6, 8, 5),
                                 distanceKm: 10.1, startCoord: Self.ttukseom))
    }

    @Test func routelessActivityStillCheckedByDistanceAndTime() {
        // 경로 좌표가 없으면 위치 검증만 생략 — 거리·시각은 그대로 검사한다
        let d = RaceDetector()
        #expect(d.passesHardGate(race: race(), date: localDate(2026, 9, 6, 8, 0),
                                 distanceKm: 10.0, startCoord: nil))
        #expect(!d.passesHardGate(race: race(), date: localDate(2026, 9, 6, 19, 0),
                                  distanceKm: 10.0, startCoord: nil))
    }

    // MARK: - 막아야 하는 경우 (예전 기준으로는 전부 통과했던 것들)

    @Test func trainingRunOfWrongDistanceIsRejected() {
        // 대회 당일 대회장 바로 앞에서 7km 조깅 — 공식 종목(5/10/21.0975) 어디에도 안 맞음
        let d = RaceDetector()
        #expect(!d.passesHardGate(race: race(), date: localDate(2026, 9, 6, 8, 0),
                                  distanceKm: 7.0, startCoord: Self.ttukseom))
    }

    @Test func eveningRunOnRaceDayIsRejected() {
        // 거리·장소는 맞지만 저녁 7시 출발 — 08:00 대회일 수 없다
        let d = RaceDetector()
        #expect(!d.passesHardGate(race: race(), date: localDate(2026, 9, 6, 19, 0),
                                  distanceKm: 10.0, startCoord: Self.ttukseom))
    }

    @Test func venueRadiusIsTightenedToOnePointFiveKm() {
        let d = RaceDetector()
        let at3km = coord(fromKmNorthOf: Self.ttukseom, 3.0)   // 예전 5km 기준이면 통과했던 거리
        #expect(!d.passesHardGate(race: race(), date: localDate(2026, 9, 6, 8, 0),
                                  distanceKm: 10.0, startCoord: at3km))
        let at1km = coord(fromKmNorthOf: Self.ttukseom, 1.0)
        #expect(d.passesHardGate(race: race(), date: localDate(2026, 9, 6, 8, 0),
                                 distanceKm: 10.0, startCoord: at1km))
    }

    @Test func cityPrecisionKeepsWiderRadius() {
        // 시 중심 좌표는 좁힐 수 없으므로 5km 유지 (대신 자동 확정은 안 함)
        let d = RaceDetector()
        let at4km = coord(fromKmNorthOf: Self.ttukseom, 4.0)
        #expect(d.passesHardGate(race: race(precision: "city"), date: localDate(2026, 9, 6, 8, 0),
                                 distanceKm: 10.0, startCoord: at4km))
        #expect(!d.passesHardGate(race: race(precision: "city"), date: localDate(2026, 9, 6, 8, 0),
                                  distanceKm: 10.0, startCoord: coord(fromKmNorthOf: Self.ttukseom, 6.0)))
    }

    @Test func differentDayIsRejected() {
        let d = RaceDetector()
        #expect(!d.passesHardGate(race: race(), date: localDate(2026, 9, 7, 8, 0),
                                  distanceKm: 10.0, startCoord: Self.ttukseom))
    }

    @Test func raceWithoutCoordinatesNeverMatches() {
        let d = RaceDetector()
        #expect(!d.passesHardGate(race: race(lat: nil, lng: nil, precision: "none"),
                                  date: localDate(2026, 9, 6, 8, 0),
                                  distanceKm: 10.0, startCoord: Self.ttukseom))
    }

    // MARK: - 시각 창 경계

    @Test func startTimeWindowIsNinetyMinutes() {
        let d = RaceDetector()
        // 웨이브 출발·늦은 종목 시작을 감안해 ±90분까지 허용
        #expect(d.passesHardGate(race: race(), date: localDate(2026, 9, 6, 9, 25),
                                 distanceKm: 10.0, startCoord: Self.ttukseom))
        #expect(!d.passesHardGate(race: race(), date: localDate(2026, 9, 6, 9, 35),
                                  distanceKm: 10.0, startCoord: Self.ttukseom))
    }

    @Test func missingRaceStartTimeSkipsTimeGate() {
        let d = RaceDetector()
        #expect(d.passesHardGate(race: race(startTime: nil), date: localDate(2026, 9, 6, 19, 0),
                                 distanceKm: 10.0, startCoord: Self.ttukseom))
    }

    // MARK: - 정밀도별 반경 값

    @Test func matchRadiusByPrecision() {
        #expect(race(precision: "venue").matchRadiusKm == 1.5)
        #expect(race(precision: "district").matchRadiusKm == 3.0)
        #expect(race(precision: "city").matchRadiusKm == 5.0)
    }

    @Test func startMinutesOfDayParsing() {
        #expect(race(startTime: "08:00").startMinutesOfDay == 480)
        #expect(race(startTime: "09:30").startMinutesOfDay == 570)
        #expect(race(startTime: "").startMinutesOfDay == nil)
        #expect(race(startTime: "미정").startMinutesOfDay == nil)
        #expect(race(startTime: nil).startMinutesOfDay == nil)
    }
}
