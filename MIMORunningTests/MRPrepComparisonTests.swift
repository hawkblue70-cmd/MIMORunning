import Testing
import Foundation
@testable import MIMORunning

@Suite("대회 준비 비교", .korean)
struct MRPrepComparisonTests {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    /// 로컬(서울) 날짜+시각
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// 대회 DB·등록 대회처럼 "yyyy-MM-dd"를 UTC 자정으로
    private func utc(_ s: String) -> Date {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s)!
    }

    private func past(_ name: String, _ day: String, km: Double, series: String?) -> MRPrepComparison.PastRace {
        MRPrepComparison.PastRace(name: name, date: utc(day), distanceKm: km, series: series)
    }

    private func run(_ d: Date, _ km: Double) -> MRPrepComparison.RunPoint {
        MRPrepComparison.RunPoint(date: d, km: km)
    }

    private func result(weeklyNow: Double = 12, weeklyPast: Double = 10,
                        longNow: Double = 28, longPast: Double = 24,
                        nowPred: Double? = 235, pastPred: Double? = 242,
                        same: Bool = true, years: Int = 1, pastYear: Int = 2025,
                        name: String = "제46회 조선일보 춘천마라톤", km: Double = 42.195) -> MRPrepComparison.Result {
        MRPrepComparison.Result(
            target: past(name, "2025-10-25", km: km, series: same ? "c" : "s"),
            isSameRace: same, daysLeft: 21, yearsAgo: years, pastYear: pastYear,
            now: .init(weeklyKm: weeklyNow, longestKm: longNow),
            past: .init(weeklyKm: weeklyPast, longestKm: longPast),
            nowPredictedMin: nowPred, pastPredictedMin: pastPred)
    }

    // MARK: - 대상

    @Test func sameRaceIsPreferred() {
        let t = MRPrepComparison.target(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c",
            confirmed: [past("제46회 조선일보 춘천마라톤", "2025-10-25", km: 42.195, series: "c"),
                        past("2026 서울마라톤", "2026-03-15", km: 42.195, series: "s")],
            calendar: cal)
        #expect(t?.race.name == "제46회 조선일보 춘천마라톤")
        #expect(t?.isSameRace == true)
    }

    @Test func sameRaceNeedsSameEvent() {
        let t = MRPrepComparison.target(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c",
            confirmed: [past("제46회 조선일보 춘천마라톤", "2025-10-25", km: 10, series: "c")],
            calendar: cal)
        #expect(t == nil)
    }

    @Test func fallsBackToNewestSameDistance() {
        let t = MRPrepComparison.target(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c",
            confirmed: [past("2025 JTBC 서울마라톤", "2025-11-02", km: 42.195, series: "j"),
                        past("2026 서울마라톤", "2026-03-15", km: 42.195, series: "s"),
                        past("2026 ○○ 32K", "2026-04-12", km: 32, series: nil)],
            calendar: cal)
        #expect(t?.race.name == "2026 서울마라톤")
        #expect(t?.isSameRace == false)
    }

    @Test func ignoresRacesOnOrAfterRaceDay() {
        let t = MRPrepComparison.target(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c",
            confirmed: [past("2026 JTBC 마라톤", "2026-11-01", km: 42.195, series: "j"),
                        past("2026 춘천마라톤", "2026-10-25", km: 42.195, series: "c")],
            calendar: cal)
        #expect(t == nil)
    }

    @Test func tenPercentDistanceWindow() {
        let half = MRPrepComparison.target(
            raceDate: utc("2026-10-25"), raceDistanceKm: 21.0975, raceSeries: nil,
            confirmed: [past("2025 ○○ 20K", "2025-11-02", km: 20, series: nil)], calendar: cal)
        #expect(half?.race.distanceKm == 20)
        let tenK = MRPrepComparison.target(
            raceDate: utc("2026-10-25"), raceDistanceKm: 10, raceSeries: nil,
            confirmed: [past("2025 ○○", "2025-11-02", km: 11.5, series: nil)], calendar: cal)
        #expect(tenK == nil)
    }

    // MARK: - 시점 · 지표

    @Test func daysLeftAndPastPoint() {
        let n = MRPrepComparison.daysLeft(raceDate: utc("2026-10-25"), today: date(2026, 10, 4, 8), calendar: cal)
        #expect(n == 21)
        let p = MRPrepComparison.pastPoint(pastRaceDate: utc("2025-10-25"), daysLeft: 21, calendar: cal)
        #expect(p == date(2025, 10, 4, 0))
    }

    @Test func metricsWindowExcludesPointDay() {
        let runs = [run(date(2025, 9, 5), 20),      // 창 밖(29일 전)
                    run(date(2025, 9, 6), 10),
                    run(date(2025, 9, 20), 24),
                    run(date(2025, 10, 3, 6), 6),
                    run(date(2025, 10, 4, 7), 30)]  // 시점 당일 — 제외
        let m = MRPrepComparison.metrics(runs: runs, before: date(2025, 10, 4, 0), calendar: cal)
        #expect(m == MRPrepComparison.Metrics(weeklyKm: 10, longestKm: 24))
    }

    @Test func metricsNilWhenWindowEmpty() {
        #expect(MRPrepComparison.metrics(runs: [run(date(2025, 1, 1), 10)],
                                         before: date(2025, 10, 4, 0), calendar: cal) == nil)
    }

    @Test func buildFullResult() {
        var askedAt: Date? = nil
        let runs = [run(date(2025, 9, 6), 10), run(date(2025, 9, 20), 24), run(date(2025, 10, 3, 6), 6),
                    run(date(2026, 9, 10), 12), run(date(2026, 9, 27), 28), run(date(2026, 10, 2), 8)]
        let r = MRPrepComparison.build(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c",
            confirmed: [past("제46회 조선일보 춘천마라톤", "2025-10-25", km: 42.195, series: "c")],
            runs: runs, today: date(2026, 10, 4, 8),
            nowPredictedMin: 235, predictionAt: { askedAt = $0; return 242 }, calendar: cal)
        #expect(r?.daysLeft == 21)
        #expect(r?.isSameRace == true)
        #expect(r?.yearsAgo == 1)
        #expect(r?.pastYear == 2025)
        #expect(r?.now == MRPrepComparison.Metrics(weeklyKm: 12, longestKm: 28))
        #expect(r?.past == MRPrepComparison.Metrics(weeklyKm: 10, longestKm: 24))
        #expect(r?.nowPredictedMin == 235)
        #expect(r?.pastPredictedMin == 242)
        #expect(askedAt == date(2025, 10, 4, 0))
    }

    @Test func buildNilOnRaceDayOrWithoutPastRuns() {
        let target = [past("제46회 조선일보 춘천마라톤", "2025-10-25", km: 42.195, series: "c")]
        let onRaceDay = MRPrepComparison.build(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c", confirmed: target,
            runs: [run(date(2025, 9, 20), 24)], today: date(2026, 10, 25, 6),
            nowPredictedMin: nil, predictionAt: { _ in nil }, calendar: cal)
        #expect(onRaceDay == nil)
        let noPastRuns = MRPrepComparison.build(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c", confirmed: target,
            runs: [run(date(2026, 9, 20), 24)], today: date(2026, 10, 4, 8),
            nowPredictedMin: nil, predictionAt: { _ in nil }, calendar: cal)
        #expect(noPastRuns == nil)
    }

    // MARK: - 나 탭 블록

    @Test func titleAndLines() {
        let r = result()
        #expect(MRPrepComparison.title(r) == "작년 조선일보 춘천마라톤 D-21 시점과 비교")
        #expect(MRPrepComparison.lines(r) == [
            .init(label: "주간 거리", now: "12km", past: "작년 10km", gain: "+20%"),
            .init(label: "최장 롱런", now: "28km", past: "작년 24km", gain: "+17%"),
            .init(label: "예상 기록", now: "3:55:00", past: "작년 4:02:00", gain: "−7:00"),
        ])
    }

    @Test func gainNeedsTenPercentForDistance() {
        #expect(MRPrepComparison.lines(result(weeklyNow: 10.9))[0].gain == nil)
        #expect(MRPrepComparison.lines(result(weeklyNow: 11.0))[0].gain == "+10%")
    }

    @Test func slowerPredictionHasNoGainAndMissingPredictionDropsLine() {
        #expect(MRPrepComparison.lines(result(nowPred: 245))[2].gain == nil)
        #expect(MRPrepComparison.lines(result(pastPred: nil)).count == 2)
    }

    @Test func sameDistanceAndTwoYearTitles() {
        let dist = result(same: false, years: 0, pastYear: 2026, name: "2026 서울마라톤")
        #expect(MRPrepComparison.title(dist) == "지난 서울마라톤 풀 D-21 시점과 비교")
        #expect(MRPrepComparison.lines(dist)[0].past == "지난 10km")
        let two = result(years: 2, pastYear: 2024)
        #expect(MRPrepComparison.title(two) == "2024년 조선일보 춘천마라톤 D-21 시점과 비교")
        #expect(MRPrepComparison.lines(two)[0].past == "2024년 10km")
    }

    // MARK: - 홈 한 줄

    @Test func homeLines() {
        #expect(MRPrepComparison.homeLine(result()) == "작년 이맘때보다 주간 거리 20% 많아요 · 12km / 10km")
        #expect(MRPrepComparison.homeLine(result(weeklyNow: 9)) == "작년 이맘때 주간 10km · 지금 9km")
        #expect(MRPrepComparison.homeLine(result(same: false, years: 0, pastYear: 2026, name: "2026 서울마라톤"))
                == "지난 서울마라톤 이맘때보다 주간 거리 20% 많아요 · 12km / 10km")
        #expect(MRPrepComparison.homeLine(result(years: 2, pastYear: 2024)) == "2024년 이맘때보다 주간 거리 20% 많아요 · 12km / 10km")
    }

    @Test(.english) func homeLinesInEnglish() {
        #expect(MRPrepComparison.homeLine(result()) == "Weekly distance 20% higher than this point last year · 12 km / 10 km")
        #expect(MRPrepComparison.homeLine(result(weeklyNow: 9)) == "This point last year: 10 km/wk · now 9 km")
    }
}
