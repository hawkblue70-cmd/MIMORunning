import Testing
import Foundation
@testable import MIMORunning

/// 기간별 결산 공유 카드 — 리듬·PR·대회·VO2 판정
@MainActor
@Suite("기간별 결산 카드", .korean)
struct PeriodRecapTests {
    private let cal = InsightEngine.weekCalendar

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 7))!
    }

    private func run(_ y: Int, _ m: Int, _ d: Int, km: Double = 6, min: Double = 36, id: UUID = UUID()) -> Activity {
        Activity(id: id, type: .running, date: date(y, m, d), duration: min * 60, distance: km * 1000,
                 calories: nil, avgHeartRate: 140, temperatureC: 15, humidityPercent: nil)
    }

    private let now = Calendar(identifier: .iso8601).date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12))!

    @Test func emptyPeriodIsNil() {
        let r = PeriodRecap.make(span: .month(year: 2026, month: 9), runs: [run(2026, 8, 3)], races: [],
                                 vo2Samples: [], now: now)
        #expect(r == nil)
    }

    @Test func dayAndWeekStreaks() {
        // 10/1~10/3 사흘 연속, 10/10 · 10/17 — 9/28 주(10/1 포함)부터 10/26 주까지 5주 중 3주 연속 + 끊김
        let runs = [run(2026, 10, 1), run(2026, 10, 2), run(2026, 10, 3), run(2026, 10, 10), run(2026, 10, 17)]
        let r = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: runs, races: [],
                                 vo2Samples: [], now: now)!
        #expect(r.longestDayStreak == 3)
        #expect(r.runDays == 5)
        #expect(r.weekKm.count == 5)          // 9/28 · 10/5 · 10/12 · 10/19 · 10/26 주
        #expect(r.longestWeekStreak == 3)
        #expect(r.weeksRan == 3)
    }

    @Test func prOnlyWhenBestFallsInPeriod() {
        // 9월 10K 55분, 10월 10K 52분 → 10월 PR(첫 완주 아님), 9월 기준으론 9월 기록이 PR(첫 완주)
        let runs = [run(2026, 9, 5, km: 10, min: 55), run(2026, 10, 5, km: 10, min: 52)]
        let oct = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: runs, races: [],
                                   vo2Samples: [], now: now)!
        #expect(oct.prs.count == 1)
        #expect(oct.prs.first?.isFirst == false)
        let sep = PeriodRecap.make(span: .month(year: 2026, month: 9), runs: runs, races: [],
                                   vo2Samples: [], now: now)!
        #expect(sep.prs.first?.isFirst == true)
    }

    @Test func slowerRunIsNotPR() {
        let runs = [run(2026, 9, 5, km: 10, min: 50), run(2026, 10, 5, km: 10, min: 52)]
        let oct = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: runs, races: [],
                                   vo2Samples: [], now: now)!
        #expect(oct.prs.isEmpty)
    }

    @Test func confirmedRaceOnly() {
        let a = run(2026, 10, 19, km: 10, min: 50)
        let b = run(2026, 10, 26, km: 10, min: 51)
        let m1 = PersistedRaceMatch(activityID: a.id, raceName: "춘천 10K", distanceKm: 10, raceDate: a.date,
                                    isConfirmed: true, isDismissed: false, isManual: false, gateVersion: nil)
        let m2 = PersistedRaceMatch(activityID: b.id, raceName: "미확정", distanceKm: 10, raceDate: b.date,
                                    isConfirmed: false, isDismissed: false, isManual: false, gateVersion: nil)
        let r = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: [a, b], races: [m1, m2],
                                 vo2Samples: [], now: now)!
        #expect(r.races.map(\.name) == ["춘천 10K"])
    }

    @Test func prOnRaceRunMergesIntoRaceRow() {
        // 10월 대회 10K가 곧 10K 최고 기록 → 기록 줄은 대회 한 줄
        let a = run(2026, 10, 4, km: 10, min: 53)
        let m = PersistedRaceMatch(activityID: a.id, raceName: "서울 10K", distanceKm: 10, raceDate: a.date,
                                   isConfirmed: true, isDismissed: false, isManual: false, gateVersion: nil)
        let r = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: [run(2026, 9, 5, km: 10, min: 55), a],
                                 races: [m], vo2Samples: [], now: now)!
        #expect(r.prs.count == 1)
        #expect(r.standalonePRs.isEmpty)
        #expect(r.pr(for: r.races[0]) != nil)
        #expect(r.recordRowCount == 1)
    }

    @Test func vo2ComparesMonthlyAverages() {
        // 9월 평균 48.0 · 10월 평균 49.0 → +1.0. 한쪽이라도 표본 2개 미만이면 없음
        let runs = [run(2026, 10, 5)]
        let both = [(date: date(2026, 9, 3), value: 47.5), (date: date(2026, 9, 20), value: 48.5),
                    (date: date(2026, 10, 2), value: 48.5), (date: date(2026, 10, 20), value: 49.5)]
        let onlyOneSep = [(date: date(2026, 9, 3), value: 47.5),
                          (date: date(2026, 10, 2), value: 48.5), (date: date(2026, 10, 20), value: 49.5)]
        let a = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: runs, races: [],
                                 vo2Samples: both, now: now)!
        let b = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: runs, races: [],
                                 vo2Samples: onlyOneSep, now: now)!
        #expect(abs((a.vo2?.delta ?? 0) - 1.0) < 0.001)
        #expect(b.vo2 == nil)
    }

    @Test func yearWeeksStopAtToday() {
        let r = PeriodRecap.make(span: .year(2026), runs: [run(2026, 3, 5)], races: [],
                                 vo2Samples: [], now: now)!
        // 2025-12-29 주(1/1 포함) ~ 2026-10-26 주
        #expect(r.weekKm.count == 44)
    }
}
