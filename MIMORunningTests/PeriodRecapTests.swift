import Testing
import Foundation
@testable import MIMORunning

/// 기간별 결산 공유 묶음 — 리듬·PR·대회·VO2·기간 제목 판정
@MainActor
@Suite("기간별 결산 묶음", .korean)
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
                                 vo2Samples: [], useMiles: false, now: now)
        #expect(r == nil)
    }

    @Test func dayAndWeekStreaks() {
        // 10/1~10/3 사흘 연속, 10/10 · 10/17 — 9/28 주(10/1 포함)부터 10/26 주까지 5주 중 3주 연속 + 끊김
        let runs = [run(2026, 10, 1), run(2026, 10, 2), run(2026, 10, 3), run(2026, 10, 10), run(2026, 10, 17)]
        let r = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: runs, races: [],
                                 vo2Samples: [], useMiles: false, now: now)!
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
                                   vo2Samples: [], useMiles: false, now: now)!
        #expect(oct.prs.count == 1)
        #expect(oct.prs.first?.isFirst == false)
        #expect(oct.title == "한계를 미는 러닝")
        let sep = PeriodRecap.make(span: .month(year: 2026, month: 9), runs: runs, races: [],
                                   vo2Samples: [], useMiles: false, now: now)!
        #expect(sep.prs.first?.isFirst == true)
    }

    @Test func slowerRunIsNotPR() {
        let runs = [run(2026, 9, 5, km: 10, min: 50), run(2026, 10, 5, km: 10, min: 52)]
        let oct = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: runs, races: [],
                                   vo2Samples: [], useMiles: false, now: now)!
        #expect(oct.prs.isEmpty)
    }

    @Test func firstHalfBeatsPRInTitle() {
        let runs = [run(2026, 9, 5, km: 10, min: 55),
                    run(2026, 10, 5, km: 10, min: 52), run(2026, 10, 19, km: 21.1, min: 118)]
        let oct = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: runs, races: [],
                                   vo2Samples: [], useMiles: false, now: now)!
        #expect(oct.title == "문을 연 러닝")
        #expect(oct.detail.contains("하프"))
    }

    @Test func confirmedRaceOnly() {
        let a = run(2026, 10, 19, km: 10, min: 50)
        let b = run(2026, 10, 26, km: 10, min: 51)
        let m1 = PersistedRaceMatch(activityID: a.id, raceName: "춘천 10K", distanceKm: 10, raceDate: a.date,
                                    isConfirmed: true, isDismissed: false, isManual: false, gateVersion: nil)
        let m2 = PersistedRaceMatch(activityID: b.id, raceName: "미확정", distanceKm: 10, raceDate: b.date,
                                    isConfirmed: false, isDismissed: false, isManual: false, gateVersion: nil)
        let r = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: [a, b], races: [m1, m2],
                                 vo2Samples: [], useMiles: false, now: now)!
        #expect(r.races.map(\.name) == ["춘천 10K"])
    }

    @Test func vo2NeedsSpan() {
        let runs = [run(2026, 10, 5)]
        let short = [(date: date(2026, 10, 1), value: 48.0), (date: date(2026, 10, 10), value: 49.0)]
        let long  = [(date: date(2026, 10, 1), value: 48.0), (date: date(2026, 10, 20), value: 49.5)]
        let a = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: runs, races: [],
                                 vo2Samples: short, useMiles: false, now: now)!
        let b = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: runs, races: [],
                                 vo2Samples: long, useMiles: false, now: now)!
        #expect(a.vo2 == nil)
        #expect(abs((b.vo2?.delta ?? 0) - 1.5) < 0.001)
    }

    @Test func distanceUpTitle() {
        // 9월 10km → 10월 15km(5K 기록·최장 거리는 9월 그대로, 연속 주 1)
        let runs = [run(2026, 9, 5, km: 5), run(2026, 9, 6, km: 5),
                    run(2026, 10, 5, km: 5, min: 40), run(2026, 10, 12, km: 5, min: 40), run(2026, 10, 26, km: 5, min: 40)]
        let oct = PeriodRecap.make(span: .month(year: 2026, month: 10), runs: runs, races: [],
                                   vo2Samples: [], useMiles: false, now: now)!
        #expect(oct.title == "자산 축적 러닝")
        #expect(oct.detail == "지난달보다 5.0km 더 달렸습니다.")
    }

    @Test func yearWeeksStopAtToday() {
        let r = PeriodRecap.make(span: .year(2026), runs: [run(2026, 3, 5)], races: [],
                                 vo2Samples: [], useMiles: false, now: now)!
        // 2025-12-29 주(1/1 포함) ~ 2026-10-26 주
        #expect(r.weekKm.count == 44)
    }
}
