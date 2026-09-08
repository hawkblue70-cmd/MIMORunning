import Testing
import Foundation
@testable import MIMORunning

@Suite("RecordSeries 기록 카드 집계")
struct RecordSeriesTests {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Seoul")!; return c }
    /// 2026-09-07 (월) 00:00 KST
    private var monday: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 7))! }
    private func day(_ offset: Int, hour: Int = 7) -> Date { cal.date(byAdding: .hour, value: offset * 24 + hour, to: monday)! }

    /// km·분으로 러닝 하나 만들기 (페이스 = 분×60 ÷ km)
    private func run(_ dayOffset: Int, km: Double, min: Double, hr: Int? = nil, id: UUID = UUID()) -> Activity {
        Activity(id: id, type: .running, date: day(dayOffset), duration: min * 60,
                 distance: km * 1000, calories: nil, avgHeartRate: hr)
    }

    private func none(_ id: UUID) -> Int? { nil }

    // MARK: - 버킷 구성

    @Test func dayBucketsCoverWindowAndSumPerDay() {
        let start = monday
        let end = cal.date(byAdding: .day, value: 5, to: monday)!
        let runs = [run(0, km: 5, min: 30), run(0, km: 3, min: 18), run(3, km: 10, min: 60)]
        let bars = RecordSeries.bars(activities: runs, effortOf: none, start: start, end: end,
                                     period: .day, calendar: cal)
        #expect(bars.count == 5)
        #expect(bars[0].id == monday)
        #expect(abs(bars[0].km - 8) < 0.0001)
        #expect(abs(bars[0].minutes - 48) < 0.0001)
        #expect(bars[0].runCount == 2)
        #expect(bars[1].km == 0)
        #expect(bars[1].runCount == 0)
        #expect(abs(bars[3].km - 10) < 0.0001)
        // 마지막 버킷 끝은 창 끝과 같다
        #expect(bars[4].end == end)
    }

    @Test func weekBucketsStartOnMonday() {
        // 창을 수요일에서 시작해도 첫 버킷은 그 주 월요일
        let start = day(2)                                    // 수요일 07시
        let end = cal.date(byAdding: .day, value: 21, to: monday)!
        let bars = RecordSeries.bars(activities: [run(9, km: 12, min: 70)], effortOf: none,
                                     start: start, end: end, period: .week, calendar: cal)
        #expect(bars.count == 3)
        #expect(bars[0].id == monday)
        #expect(bars[1].id == cal.date(byAdding: .day, value: 7, to: monday)!)
        #expect(bars[2].id == cal.date(byAdding: .day, value: 14, to: monday)!)
        // 9일차(다음 주 수요일) 러닝은 두 번째 주 버킷
        #expect(abs(bars[1].km - 12) < 0.0001)
        #expect(bars[0].km == 0)
    }

    @Test func monthBucketsStartOnFirst() {
        let start = cal.date(from: DateComponents(year: 2026, month: 7, day: 15))!
        let end = cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let sep = run(0, km: 7, min: 42)                       // 2026-09-07
        let bars = RecordSeries.bars(activities: [sep], effortOf: none, start: start, end: end,
                                     period: .month, calendar: cal)
        #expect(bars.count == 3)
        #expect(bars[0].id == cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!)
        #expect(bars[2].id == cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!)
        #expect(bars[2].end == end)
        #expect(abs(bars[2].km - 7) < 0.0001)
    }

    // MARK: - 페이스

    @Test func paceBaselineIsDistanceWeighted() {
        // 10km @ 360초/km(60분) + 2km @ 300초/km(10분) → 350초/km
        let runs = [run(0, km: 10, min: 60), run(1, km: 2, min: 10)]
        let bars = RecordSeries.bars(activities: runs, effortOf: none, start: monday,
                                     end: cal.date(byAdding: .day, value: 3, to: monday)!,
                                     period: .day, calendar: cal)
        let baseline = RecordSeries.paceBaseline(bars)
        #expect(baseline != nil)
        #expect(abs(baseline! - 350) < 0.0001)
        // 같은 날에 몰아넣어도 버킷 자체 페이스가 거리 가중이다
        let sameDay = RecordSeries.bars(activities: [run(0, km: 10, min: 60), run(0, km: 2, min: 10)],
                                        effortOf: none, start: monday,
                                        end: cal.date(byAdding: .day, value: 1, to: monday)!,
                                        period: .day, calendar: cal)
        #expect(abs(sameDay[0].paceSec! - 350) < 0.0001)
    }

    // MARK: - 평균 심박

    @Test func avgHRIsDurationWeighted() {
        // 30분 @ 140 + 60분 @ 150 → (140×30 + 150×60) / 90 = 146.67
        let runs = [run(0, km: 5, min: 30, hr: 140), run(0, km: 10, min: 60, hr: 150)]
        let bars = RecordSeries.bars(activities: runs, effortOf: none, start: monday,
                                     end: cal.date(byAdding: .day, value: 1, to: monday)!,
                                     period: .day, calendar: cal)
        #expect(abs(bars[0].avgHR! - 146.6666) < 0.001)
        // 심박 없는 러닝은 가중치에서 빠진다
        let mixed = RecordSeries.bars(activities: [run(0, km: 5, min: 30, hr: 140), run(0, km: 10, min: 60)],
                                      effortOf: none, start: monday,
                                      end: cal.date(byAdding: .day, value: 1, to: monday)!,
                                      period: .day, calendar: cal)
        #expect(abs(mixed[0].avgHR! - 140) < 0.0001)
        // 아무도 심박이 없으면 nil
        let noHR = RecordSeries.bars(activities: [run(0, km: 5, min: 30)], effortOf: none, start: monday,
                                     end: cal.date(byAdding: .day, value: 1, to: monday)!,
                                     period: .day, calendar: cal)
        #expect(noHR[0].avgHR == nil)
    }

    // MARK: - 심박 평균선

    @Test func hrBaselineIsDurationWeighted() {
        // 60분 @ 150(월) + 10분 @ 140(화) → (150×60 + 140×10) / 70 = 148.571
        let runs = [run(0, km: 10, min: 60, hr: 150), run(1, km: 2, min: 10, hr: 140)]
        let bars = RecordSeries.bars(activities: runs, effortOf: none, start: monday,
                                     end: cal.date(byAdding: .day, value: 3, to: monday)!,
                                     period: .day, calendar: cal)
        let hr = RecordSeries.hrBaseline(bars)
        #expect(hr != nil)
        #expect(abs(hr! - 148.5714) < 0.001)
        // 요약도 같은 값을 쓴다 (중복 계산 없음)
        #expect(RecordSeries.summary(bars).meanHR == hr)

        // 심박 없는 버킷은 가중치에 안 들어간다 — 심박 있는 버킷만으로 평균
        let mixed = RecordSeries.bars(activities: [run(0, km: 10, min: 60, hr: 150), run(1, km: 20, min: 200)],
                                      effortOf: none, start: monday,
                                      end: cal.date(byAdding: .day, value: 3, to: monday)!,
                                      period: .day, calendar: cal)
        #expect(abs(RecordSeries.hrBaseline(mixed)! - 150) < 0.0001)

        // 아무 버킷도 심박이 없으면 nil
        let noHR = RecordSeries.bars(activities: [run(0, km: 5, min: 30)], effortOf: none, start: monday,
                                     end: cal.date(byAdding: .day, value: 1, to: monday)!,
                                     period: .day, calendar: cal)
        #expect(RecordSeries.hrBaseline(noHR) == nil)
    }

    // MARK: - 강도·부하

    @Test func loadAndEffortUseRatedRunsOnly() {
        let rated = UUID(), unrated = UUID()
        let runs = [run(0, km: 8, min: 50, id: rated), run(0, km: 5, min: 30, id: unrated)]
        let bars = RecordSeries.bars(activities: runs,
                                     effortOf: { $0 == rated ? 6 : nil },
                                     start: monday,
                                     end: cal.date(byAdding: .day, value: 1, to: monday)!,
                                     period: .day, calendar: cal)
        #expect(bars.count == 1)
        #expect(bars[0].runCount == 2)          // 강도 없는 러닝도 runCount에는 들어간다
        #expect(bars[0].ratedCount == 1)        // ratedCount에는 안 들어간다
        #expect(abs(bars[0].au - 300) < 0.0001) // 6 × 50분
        #expect(abs(bars[0].meanEffort! - 6) < 0.0001)
        #expect(abs(bars[0].minutes - 80) < 0.0001)
    }

    @Test func meanEffortIsNilWithoutRatings() {
        let bars = RecordSeries.bars(activities: [run(0, km: 5, min: 30)], effortOf: none,
                                     start: monday, end: cal.date(byAdding: .day, value: 1, to: monday)!,
                                     period: .day, calendar: cal)
        #expect(bars[0].meanEffort == nil)
        #expect(bars[0].au == 0)
    }

    // MARK: - 요약

    @Test func summaryTotals() {
        let rated = UUID()
        let runs = [run(0, km: 10, min: 60, hr: 150, id: rated), run(1, km: 2, min: 10, hr: 140)]
        let bars = RecordSeries.bars(activities: runs, effortOf: { $0 == rated ? 5 : nil },
                                     start: monday, end: cal.date(byAdding: .day, value: 3, to: monday)!,
                                     period: .day, calendar: cal)
        let s = RecordSeries.summary(bars)
        #expect(abs(s.totalKm - 12) < 0.0001)
        #expect(abs(s.totalMinutes - 70) < 0.0001)
        #expect(abs(s.totalAU - 300) < 0.0001)   // 5 × 60분
        #expect(s.runCount == 2)
        #expect(s.ratedCount == 1)
        #expect(abs(s.meanPaceSec! - 350) < 0.0001)
        #expect(abs(s.bestPaceSec! - 300) < 0.0001)
        // 심박도 시간 가중 — (150×60 + 140×10) / 70 = 148.571
        #expect(abs(s.meanHR! - 148.5714) < 0.001)
    }

    // MARK: - 빈 창

    @Test func emptyWindowGivesZeroBarsAndNilBaseline() {
        let bars = RecordSeries.bars(activities: [], effortOf: none, start: monday,
                                     end: cal.date(byAdding: .day, value: 7, to: monday)!,
                                     period: .day, calendar: cal)
        #expect(bars.count == 7)
        #expect(bars.allSatisfy { $0.km == 0 && $0.minutes == 0 && $0.au == 0 && $0.runCount == 0 })
        #expect(bars.allSatisfy { $0.paceSec == nil && $0.meanEffort == nil && $0.avgHR == nil })
        #expect(RecordSeries.paceBaseline(bars) == nil)
        let s = RecordSeries.summary(bars)
        #expect(s.totalKm == 0 && s.runCount == 0 && s.meanPaceSec == nil && s.bestPaceSec == nil)
        #expect(s.meanHR == nil)
    }

    @Test func invertedWindowGivesNoBars() {
        let bars = RecordSeries.bars(activities: [], effortOf: none,
                                     start: cal.date(byAdding: .day, value: 3, to: monday)!,
                                     end: monday, period: .day, calendar: cal)
        #expect(bars.isEmpty)
    }
}
