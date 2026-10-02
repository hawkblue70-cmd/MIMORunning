import Testing
import Foundation
@testable import MIMORunning

@Suite("나 탭 참가 대회 기록", .korean)
struct RaceRecordListTests {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func run(_ name: String, km: Double, _ d: Date, minutes: Double,
                     id: UUID = UUID()) -> RaceRecordList.RunInput {
        RaceRecordList.RunInput(activityID: id, raceName: name, distanceKm: km,
                                date: d, durationSec: minutes * 60)
    }

    private func archive(_ index: Int, _ name: String, _ d: Date, km: Double,
                         hasResult: Bool = false, actualMin: Double = 0,
                         hasDetail: Bool = true) -> RaceRecordList.ArchiveInput {
        RaceRecordList.ArchiveInput(index: index, raceName: name, raceDate: d, distanceM: km * 1000,
                                    hasResult: hasResult, actualMin: actualMin,
                                    hasDetail: hasDetail)
    }

    private func prediction(_ d: Date, km: Double, predicted: Double,
                            errorPct: Double = 1.0, inBand: Bool = true,
                            vo2ErrorPct: Double? = nil,
                            vo2PredictedMin: Double? = nil) -> RaceRecordList.PredictionInput {
        RaceRecordList.PredictionInput(date: d, distanceKm: km, predictedMin: predicted,
                                       errorPct: errorPct, inBand: inBand, vo2ErrorPct: vo2ErrorPct,
                                       vo2PredictedMin: vo2PredictedMin)
    }

    // MARK: - 행 만들기

    @Test func confirmedRunBecomesTappableRow() {
        let id = UUID()
        let rows = RaceRecordList.rows(
            runs: [run("2026 춘천마라톤", km: 42.195, date(2026, 10, 25), minutes: 232, id: id)],
            archives: [], predictions: [], calendar: cal)
        #expect(rows.count == 1)
        #expect(rows[0].source == .run(activityID: id))
        #expect(rows[0].name == "춘천마라톤")
        #expect(rows[0].distanceLabel == "풀")
        #expect(rows[0].finishMin == 232)
        #expect(rows[0].opensRun)
    }

    @Test func runAndArchiveOnSameDayMergeIntoOneRow() {
        let d = date(2026, 10, 25)
        let rows = RaceRecordList.rows(
            runs: [run("2026 춘천마라톤", km: 42.195, d, minutes: 232)],
            archives: [archive(3, "2026 춘천마라톤", date(2026, 10, 25, hour: 0), km: 42.195)],
            predictions: [], calendar: cal)
        #expect(rows.count == 1)
        #expect(rows[0].opensRun)
        #expect(rows[0].archiveIndex == 3)
        #expect(rows[0].hasPlan)
    }

    @Test func archiveWithoutWeeklyDetailHasNoPlanButton() {
        let d = date(2026, 10, 25)
        let rows = RaceRecordList.rows(
            runs: [run("2026 춘천마라톤", km: 42.195, d, minutes: 232)],
            archives: [archive(0, "2026 춘천마라톤", d, km: 42.195, hasDetail: false)],
            predictions: [], calendar: cal)
        #expect(rows[0].archiveIndex == 0)
        #expect(rows[0].hasPlan == false)
    }

    @Test func archiveOnlyDayIsDimRowWithoutRun() {
        let rows = RaceRecordList.rows(
            runs: [],
            archives: [archive(0, "2025 ○○마라톤", date(2025, 10, 5), km: 21.0975),
                       archive(1, "2025 △△마라톤", date(2025, 4, 6), km: 10, hasResult: true, actualMin: 55)],
            predictions: [], calendar: cal)
        #expect(rows.count == 2)
        #expect(rows[0].source == .archiveOnly)
        #expect(rows[0].opensRun == false)
        #expect(rows[0].finishMin == nil)
        #expect(rows[1].finishMin == 55)
    }

    @Test func predictionAttachesOnlyForSameDayAndSameDistance() {
        let d = date(2026, 3, 15)
        let half = RaceRecordList.rows(
            runs: [run("2026 서울하프", km: 21.0975, d, minutes: 110)],
            predictions: [prediction(d, km: 10, predicted: 50)], calendar: cal)
        #expect(half[0].prediction == nil)

        let matched = RaceRecordList.rows(
            runs: [run("2026 서울하프", km: 21.0975, d, minutes: 110)],
            predictions: [prediction(d, km: 21.0975, predicted: 112, inBand: false)], calendar: cal)
        #expect(matched[0].prediction == RaceRecordList.Prediction(predictedMin: 112, inBand: false))
    }

    @Test func predictionAlwaysFromEngine() {
        let d = date(2026, 10, 25)
        let rows = RaceRecordList.rows(
            runs: [run("2026 춘천마라톤", km: 42.195, d, minutes: 232)],
            archives: [archive(0, "2026 춘천마라톤", d, km: 42.195)],
            predictions: [prediction(d, km: 42.195, predicted: 240)], calendar: cal)
        #expect(rows[0].prediction?.predictedMin == 240)
    }

    @Test func trainingEffortWithoutConfirmedRaceIsNotListed() {
        let rows = RaceRecordList.rows(
            runs: [], archives: [],
            predictions: [prediction(date(2026, 5, 3), km: 10, predicted: 50)], calendar: cal)
        #expect(rows.isEmpty)
    }

    @Test func nonStandardRaceHasRowWithoutPrediction() {
        let d = date(2026, 4, 12)
        let rows = RaceRecordList.rows(
            runs: [run("2026 ○○ 32K", km: 32, d, minutes: 180)],
            predictions: [prediction(d, km: 42.195, predicted: 240)], calendar: cal)
        #expect(rows[0].distanceLabel == "32K")
        #expect(rows[0].prediction == nil)
    }

    @Test func editionCountFromSeriesKey() {
        let a = run("제45회 조선일보 춘천마라톤", km: 42.195, date(2024, 10, 27), minutes: 240)
        let b = run("제46회 조선일보 춘천마라톤", km: 42.195, date(2025, 10, 25), minutes: 236)
        let c = run("2026 춘천마라톤", km: 42.195, date(2026, 10, 25), minutes: 232)
        let other = run("2026 서울마라톤", km: 42.195, date(2026, 3, 15), minutes: 238)
        let key: (RaceRecordList.RunInput) -> String? = { $0.raceName.contains("춘천") ? "chuncheon-marathon" : nil }
        let rows = RaceRecordList.rows(runs: [a, b, c, other], seriesKey: key, calendar: cal)
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.date, $0.editionCount) })
        #expect(byName[c.date] == .some(3))
        #expect(byName[b.date] == .some(2))
        #expect(byName[a.date] == .some(nil))
        #expect(byName[other.date] == .some(nil))
    }

    @Test func noSeriesKeyMeansNoEditionCount() {
        let rows = RaceRecordList.rows(
            runs: [run("2025 춘천마라톤", km: 42.195, date(2025, 10, 25), minutes: 236),
                   run("2026 춘천마라톤", km: 42.195, date(2026, 10, 25), minutes: 232)],
            calendar: cal)
        #expect(rows.allSatisfy { $0.editionCount == nil })
    }

    @Test func twoRunsSameDayKeepLongest() {
        let d = date(2026, 10, 25)
        let rows = RaceRecordList.rows(
            runs: [run("2026 춘천마라톤", km: 42.195, d, minutes: 230),
                   run("2026 춘천마라톤", km: 42.195, d, minutes: 240)],
            calendar: cal)
        #expect(rows.count == 1)
        #expect(rows[0].finishMin == 240)
    }

    @Test func twoArchivesSameDayWithoutRunMakeOneRow() {
        let d = date(2026, 10, 25)
        let rows = RaceRecordList.rows(
            runs: [],
            archives: [archive(0, "2026 ○○10K", d, km: 10),
                       archive(1, "2026 춘천마라톤", d, km: 42.195, hasResult: true, actualMin: 250)],
            predictions: [], calendar: cal)
        #expect(rows.count == 1)
        #expect(rows[0].archiveIndex == 1)
        #expect(rows[0].finishMin == 250)
    }

    @Test func runPicksArchiveWithMatchingDistance() {
        let d = date(2026, 10, 25)
        let rows = RaceRecordList.rows(
            runs: [run("2026 춘천마라톤", km: 42.195, d, minutes: 232)],
            archives: [archive(0, "2026 ○○10K", d, km: 10),
                       archive(1, "2026 춘천마라톤", d, km: 42.195)],
            predictions: [prediction(d, km: 42.195, predicted: 240)], calendar: cal)
        #expect(rows[0].archiveIndex == 1)
        #expect(rows[0].prediction?.predictedMin == 240)
    }

    @Test func runFallsBackToOtherDistanceArchiveForPlan() {
        let d = date(2026, 4, 5)
        let rows = RaceRecordList.rows(
            runs: [run("2026 ○○10K", km: 10, d, minutes: 50)],
            archives: [archive(0, "2026 ○○하프", d, km: 21.0975)],
            predictions: [prediction(d, km: 10, predicted: 52)], calendar: cal)
        #expect(rows[0].prediction?.predictedMin == 52)
        #expect(rows[0].archiveIndex == 0)
        #expect(rows[0].hasPlan == true)
    }

    @Test func editionCountIgnoresSameDayDuplicate() {
        let d2025 = date(2025, 10, 25)
        let d2026 = date(2026, 10, 25)
        let a = run("2025 춘천마라톤", km: 42.195, d2025, minutes: 236)
        let b = run("2026 춘천마라톤", km: 42.195, d2026, minutes: 232)
        let bDup = run("2026 춘천마라톤", km: 42.195, d2026, minutes: 100)
        let rows = RaceRecordList.rows(runs: [a, b, bDup], seriesKey: { _ in "chuncheon-marathon" }, calendar: cal)
        #expect(rows.count == 2)
        #expect(rows[0].editionCount == 2)
    }

    @Test func rowsAreNewestFirst() {
        let rows = RaceRecordList.rows(
            runs: [run("A", km: 10, date(2025, 4, 6), minutes: 50),
                   run("B", km: 10, date(2026, 4, 5), minutes: 49)],
            archives: [archive(0, "C", date(2025, 11, 2), km: 10)],
            calendar: cal)
        #expect(rows.map(\.name) == ["B", "C", "A"])
    }

    // MARK: - 예측 정확도

    @Test func accuracyCountsOnlyConfirmedRaceDays() {
        let d1 = date(2026, 3, 15), d2 = date(2026, 10, 25), effortDay = date(2026, 5, 3)
        let acc = RaceRecordList.accuracy(
            runs: [run("서울", km: 42.195, d1, minutes: 238), run("춘천", km: 42.195, d2, minutes: 232)],
            predictions: [prediction(d1, km: 42.195, predicted: 245, errorPct: 3.0, inBand: true),
                          prediction(d2, km: 42.195, predicted: 250, errorPct: -5.0, inBand: false),
                          prediction(effortDay, km: 10, predicted: 50, errorPct: 20, inBand: false)],
            calendar: cal)
        #expect(acc == RaceRecordList.Accuracy(hit: 1, count: 2, meanAbsErrorPct: 4.0))
    }

    @Test func accuracyUsesDedupedRuns() {
        let d = date(2026, 10, 25)
        let acc = RaceRecordList.accuracy(
            runs: [run("춘천", km: 42.195, d, minutes: 230),
                   run("춘천", km: 42.195, d, minutes: 240)],
            predictions: [prediction(d, km: 42.195, predicted: 245, errorPct: 2.0, inBand: true)],
            calendar: cal)
        #expect(acc?.count == 1)
    }

    @Test func accuracyIsNilWithoutPredictions() {
        let acc = RaceRecordList.accuracy(
            runs: [run("서울", km: 42.195, date(2026, 3, 15), minutes: 238)],
            predictions: [], calendar: cal)
        #expect(acc == nil)
    }

    // MARK: - 워치 VO2max 환산표 비교

    @Test func rowCarriesVO2TablePrediction() {
        let d = date(2025, 11, 23)
        let rows = RaceRecordList.rows(
            runs: [run("A", km: 42.195, d, minutes: 296)],
            predictions: [prediction(d, km: 42.195, predicted: 284, vo2PredictedMin: 208)],
            calendar: cal)
        #expect(rows.first?.prediction?.vo2PredictedMin == 208)
    }

    @Test func vo2ComparisonNeedsTwoPairedRaces() {
        let d1 = date(2026, 3, 15), d2 = date(2026, 10, 25)
        let acc = RaceRecordList.accuracy(
            runs: [run("서울", km: 42.195, d1, minutes: 238), run("춘천", km: 42.195, d2, minutes: 232)],
            predictions: [prediction(d1, km: 42.195, predicted: 245, errorPct: 3.0, vo2ErrorPct: -20),
                          prediction(d2, km: 42.195, predicted: 240, errorPct: 2.0)],
            calendar: cal)
        #expect(acc?.vo2 == nil)
    }

    @Test func vo2ComparisonOnSameRaces() {
        let d1 = date(2025, 4, 6), d2 = date(2025, 11, 23)
        let acc = RaceRecordList.accuracy(
            runs: [run("A", km: 21.0975, d1, minutes: 118), run("B", km: 42.195, d2, minutes: 296)],
            predictions: [prediction(d1, km: 21.0975, predicted: 124, errorPct: 3.0, vo2ErrorPct: -10),
                          prediction(d2, km: 42.195, predicted: 284, errorPct: -5.0, vo2ErrorPct: -20)],
            calendar: cal)
        let v = acc?.vo2
        #expect(v == RaceRecordList.VO2Comparison(count: 2, appMeanAbsErrorPct: 4.0, vo2MeanAbsErrorPct: 15.0,
                                                  allFaster: true, allSlower: false))
        #expect(RaceRecordList.vo2Sentence(acc!, english: false)
                == "VO2max 환산표: 평균 오차 15.0% · 2건 모두 실제보다 빠름")
    }

    // VO2max가 일부 대회에만 있으면 그 대회들의 앱 오차를 따로 밝힌다 — 다른 묶음끼리 비교하지 않게
    @Test func vo2ComparisonOnSubsetStatesAppErrorForSameRaces() {
        let d1 = date(2025, 3, 2), d2 = date(2025, 4, 27), d3 = date(2025, 11, 23)
        let acc = RaceRecordList.accuracy(
            runs: [run("A", km: 10, d1, minutes: 56), run("B", km: 10, d2, minutes: 54),
                   run("C", km: 42.195, d3, minutes: 296)],
            predictions: [prediction(d1, km: 10, predicted: 56, errorPct: 1.0, vo2ErrorPct: -12),
                          prediction(d2, km: 10, predicted: 55, errorPct: -3.0, vo2ErrorPct: 4),
                          prediction(d3, km: 42.195, predicted: 284, errorPct: -9.0)],
            calendar: cal)
        #expect(acc?.vo2 == RaceRecordList.VO2Comparison(count: 2, appMeanAbsErrorPct: 2.0, vo2MeanAbsErrorPct: 8.0,
                                                         allFaster: false, allSlower: false))
        #expect(RaceRecordList.vo2Sentence(acc!, english: false)
                == "VO2max 환산표(VO2max 있는 2건): 평균 오차 8.0% · 같은 2건 앱 2.0%")
    }

    // MARK: - 토글 기본값

    @Test func defaultModeIsPlannedWhenUpcomingRaceExists() {
        let today = date(2026, 9, 27)
        #expect(RaceRecordList.defaultMode(plannedDates: [date(2026, 10, 25)], today: today, calendar: cal) == .planned)
        #expect(RaceRecordList.defaultMode(plannedDates: [date(2026, 9, 27, hour: 0)], today: today, calendar: cal) == .planned)
        #expect(RaceRecordList.defaultMode(plannedDates: [nil], today: today, calendar: cal) == .planned)
    }

    @Test func defaultModeIsRecordsWithoutUpcomingRace() {
        let today = date(2026, 9, 27)
        #expect(RaceRecordList.defaultMode(plannedDates: [], today: today, calendar: cal) == .records)
        #expect(RaceRecordList.defaultMode(plannedDates: [date(2026, 9, 26)], today: today, calendar: cal) == .records)
    }
}
