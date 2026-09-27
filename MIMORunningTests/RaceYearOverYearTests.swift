import Testing
import Foundation
@testable import MIMORunning

@Suite("대회 해마다 비교", .korean)
struct RaceYearOverYearTests {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    private func entry(_ name: String, _ d: Date, km: Double, sec: TimeInterval,
                       series: String? = nil, temp: Double? = nil, id: UUID = UUID()) -> RaceYearOverYear.Entry {
        RaceYearOverYear.Entry(activityID: id, raceName: name, date: d, distanceKm: km,
                               durationSec: sec, tempC: temp, series: series)
    }

    /// 오늘: 2026 춘천마라톤 3:52:10
    private var today: RaceYearOverYear.Entry {
        entry("2026 춘천마라톤", date(2026, 10, 25), km: 42.195, sec: 13_930, series: "c", temp: 18)
    }

    // MARK: - 같은 대회

    @Test func sameRaceLastYearFaster() {
        let past = entry("2025 춘천마라톤", date(2025, 10, 25), km: 42.195, sec: 14_182, series: "c", temp: 24)
        let c = RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal)
        #expect(c.sameRace.count == 1)
        #expect(c.sameRace[0].delta == .time(seconds: 252))
        #expect(c.headline == "작년보다 4분 12초 빨라요")
        #expect(c.today.isToday)
        #expect(c.today.tempC == 18)
    }

    @Test(.english) func sameRaceLastYearFasterInEnglish() {
        let past = entry("2025 춘천마라톤", date(2025, 10, 25), km: 42.195, sec: 14_182, series: "c")
        #expect(RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal).headline
                == "4:12 faster than last year")
    }

    @Test func sameRaceTwoYearsAgoFaster() {
        let past = entry("2024 춘천마라톤", date(2024, 10, 27), km: 42.195, sec: 14_182, series: "c")
        #expect(RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal).headline
                == "2024년보다 4분 12초 빨라요")
    }

    @Test func sameRaceEarlierThisYearUsesLastWording() {
        let past = entry("2026 춘천마라톤", date(2026, 1, 25), km: 42.195, sec: 14_182, series: "c")
        #expect(RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal).headline
                == "지난 춘천마라톤보다 4분 12초 빨라요")
    }

    @Test func sameRaceSlowerStatesLastRecordOnly() {
        let past = entry("2025 춘천마라톤", date(2025, 10, 25), km: 42.195, sec: 13_800, series: "c")
        let c = RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal)
        #expect(c.headline == "작년 춘천마라톤 3:50:00")
        #expect(c.sameRace[0].delta == .time(seconds: -130))
    }

    @Test func equalTimeIsNotFaster() {
        let past = entry("2025 춘천마라톤", date(2025, 10, 25), km: 42.195, sec: 13_930, series: "c")
        #expect(RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal).headline
                == "작년 춘천마라톤 3:52:10")
    }

    @Test func oneSecondFasterCounts() {
        let past = entry("2025 춘천마라톤", date(2025, 10, 25), km: 42.195, sec: 13_931, series: "c")
        #expect(RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal).headline
                == "작년보다 1초 빨라요")
    }

    @Test func sameSeriesDifferentEventIsNotSameRace() {
        // 작년 같은 대회 10K — 오늘 풀과 같은 대회로도, 같은 거리로도 보지 않는다
        let past = entry("2025 춘천마라톤", date(2025, 10, 25), km: 10, sec: 3_000, series: "c")
        let c = RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal)
        #expect(c.isEmpty)
        #expect(c.headline == nil)
    }

    // MARK: - 같은 거리

    @Test func sameDistanceExactUsesTime() {
        let past = entry("2026 서울마라톤", date(2026, 3, 15), km: 42.195, sec: 14_320, series: "s")
        let c = RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal)
        #expect(c.sameRace.isEmpty)
        #expect(c.sameDistance.map(\.title) == ["서울마라톤"])
        #expect(c.headline == "지난 서울마라톤보다 6분 30초 빨라요")
    }

    @Test func sameDistanceOtherEventUsesPace() {
        let half = entry("2026 서울하프", date(2026, 4, 26), km: 21.0975, sec: 6_300, series: "h")
        let past = entry("2025 ○○", date(2025, 11, 2), km: 20.0, sec: 6_130, series: "x")
        let c = RaceYearOverYear.compare(today: half, confirmed: [past], calendar: cal)
        #expect(c.sameDistance.map(\.title) == ["○○ 20K"])
        #expect(c.sameDistance[0].delta == .pace(secondsPerKm: 8))
        #expect(c.headline == "지난 ○○ 20K보다 km당 8초 빨라요")
    }

    @Test func sameDistanceSlowerStatesLastRecord() {
        let past = entry("2026 서울마라톤", date(2026, 3, 15), km: 42.195, sec: 13_000, series: "s")
        #expect(RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal).headline
                == "지난 서울마라톤 3:36:40")
    }

    @Test func sameRaceWinsHeadlineOverSameDistance() {
        let race = entry("2025 춘천마라톤", date(2025, 10, 25), km: 42.195, sec: 14_182, series: "c")
        let dist = entry("2026 서울마라톤", date(2026, 3, 15), km: 42.195, sec: 14_320, series: "s")
        let c = RaceYearOverYear.compare(today: today, confirmed: [dist, race], calendar: cal)
        #expect(c.headline == "작년보다 4분 12초 빨라요")
        #expect(c.sameRace.count == 1)
        #expect(c.sameDistance.count == 1)
    }

    @Test func tenPercentDistanceWindow() {
        let tenK = entry("2026 ○○10K", date(2026, 5, 3), km: 10, sec: 3_000)
        let eleven = entry("A", date(2026, 4, 1), km: 11.0, sec: 3_400)
        let elevenHalf = entry("B", date(2026, 3, 1), km: 11.5, sec: 3_500)
        let c = RaceYearOverYear.compare(today: tenK, confirmed: [eleven, elevenHalf], calendar: cal)
        #expect(c.sameDistance.map(\.title) == ["A 11K"])
    }

    @Test func excludesTodayAndFutureAndKeepsFiveNewest() {
        let later = entry("2027 서울마라톤", date(2027, 3, 21), km: 42.195, sec: 14_000)
        let selfEntry = entry("2026 춘천마라톤", date(2026, 10, 25), km: 42.195, sec: 13_930, id: today.activityID)
        let olds = (1...7).map { i in entry("대회\(i)", date(2026, i, 1), km: 42.195, sec: 14_000) }
        let c = RaceYearOverYear.compare(today: today, confirmed: [later, selfEntry] + olds, calendar: cal)
        #expect(c.sameDistance.map(\.title) == ["대회7", "대회6", "대회5", "대회4", "대회3"])
    }

    @Test func noPastRaceMeansEmptyAndNoHeadline() {
        let c = RaceYearOverYear.compare(today: today, confirmed: [], calendar: cal)
        #expect(c.isEmpty)
        #expect(c.headline == nil)
    }

    // MARK: - 표 차이 문구

    @Test func deltaTexts() {
        #expect(RaceYearOverYear.deltaText(.time(seconds: 252)) == "+4:12")
        #expect(RaceYearOverYear.deltaText(.time(seconds: -65)) == "−1:05")
        #expect(RaceYearOverYear.deltaText(.time(seconds: 3_725)) == "+1:02:05")
        #expect(RaceYearOverYear.deltaText(.time(seconds: 0)) == "±0:00")
        #expect(RaceYearOverYear.deltaText(.pace(secondsPerKm: 5)) == "km당 +5초")
        #expect(inEnglish { RaceYearOverYear.deltaText(.pace(secondsPerKm: -3)) } == "−3 s/km")
    }
}
