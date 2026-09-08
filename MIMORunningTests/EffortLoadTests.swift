import Testing
import Foundation
@testable import MIMORunning

@Suite("EffortLoad sRPE 주간 부하")
struct EffortLoadTests {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Seoul")!; return c }
    // 2026-09-07 (월) 00:00 KST
    private var monday: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 7))! }
    private func day(_ offset: Int, hour: Int = 7) -> Date { cal.date(byAdding: .hour, value: offset * 24 + hour, to: monday)! }
    private func run(_ dayOffset: Int, min: Double, effort: Int?) -> EffortLoad.Run {
        .init(date: day(dayOffset), durationMin: min, effort: effort)
    }

    @Test func sessionAU() {
        #expect(EffortLoad.sessionAU(effort: 6, durationMin: 50) == 300)
    }

    @Test func mondayStart() {
        // 수요일 → 그 주 월요일
        #expect(EffortLoad.mondayStart(of: day(2), calendar: cal) == monday)
        #expect(EffortLoad.mondayStart(of: monday, calendar: cal) == monday)
    }

    @Test func weeklyTotalsDailyCoverageMean() {
        let runs = [run(0, min: 40, effort: 4), run(0, min: 20, effort: 6),   // 월: 160 + 120
                    run(2, min: 60, effort: nil),                              // 수: 강도 없음
                    run(5, min: 90, effort: 3),                                // 토: 270
                    .init(date: day(7), durationMin: 30, effort: 9)]           // 다음 주 → 제외
        let w = EffortLoad.weekly(runs: runs, weekStart: monday, calendar: cal)!
        #expect(w.total == 550)
        #expect(w.daily == [280, 0, 0, 0, 0, 270, 0])
        #expect(w.runCount == 4)
        #expect(w.coveredCount == 3)
        #expect(abs(w.coverage - 0.75) < 0.0001)
        #expect(abs((w.meanEffort ?? 0) - 13.0 / 3.0) < 0.0001)
        #expect(w.dailyMeanEffort[0] == 5)
        #expect(w.dailyMeanEffort[2] == nil)
    }

    @Test func weeklyNilWhenNoRuns() {
        #expect(EffortLoad.weekly(runs: [], weekStart: monday, calendar: cal) == nil)
        #expect(EffortLoad.weekly(runs: [run(9, min: 30, effort: 5)], weekStart: monday, calendar: cal) == nil)
    }

    @Test func monotony() {
        #expect(EffortLoad.monotony(daily: [100, 100, 100, 100, 100, 100, 100]) == nil)   // sd 0
        let m = EffortLoad.monotony(daily: [200, 0, 200, 0, 200, 0, 200])!
        // mean 114.29, pop sd 98.97 → 1.155
        #expect(abs(m - 1.1547) < 0.001)
    }

    @Test func ratioLabels() {
        #expect(EffortLoad.ratioLabel(0.79) == .low)
        #expect(EffortLoad.ratioLabel(0.8) == .steady)
        #expect(EffortLoad.ratioLabel(1.3) == .steady)
        #expect(EffortLoad.ratioLabel(1.31) == .high)
        #expect(EffortLoad.ratioLabel(1.5) == .high)
        #expect(EffortLoad.ratioLabel(1.51) == .veryHigh)
    }

    private func week(_ total: Double, coverage: Double) -> EffortLoad.WeekLoad {
        let covered = Int((coverage * 4).rounded())
        return .init(weekStart: monday, total: total, daily: [total, 0, 0, 0, 0, 0, 0],
                     dailyMeanEffort: [5, nil, nil, nil, nil, nil, nil],
                     runCount: 4, coveredCount: covered, meanEffort: 5)
    }

    @Test func acuteChronicNeedsThreeCoveredWeeks() {
        let cur = week(1200, coverage: 1)
        #expect(EffortLoad.acuteChronic(current: cur, previous: [week(800, coverage: 1), week(800, coverage: 1)]) == nil)
        let ok = EffortLoad.acuteChronic(current: cur, previous: [week(800, coverage: 1), week(800, coverage: 0.25), week(800, coverage: 1), week(800, coverage: 0.5)])!
        #expect(abs(ok.ratio - 1.5) < 0.0001)
        #expect(ok.label == .high)
        // 이번 주 커버리지 미달
        #expect(EffortLoad.acuteChronic(current: week(1200, coverage: 0.25), previous: [week(800, coverage: 1), week(800, coverage: 1), week(800, coverage: 1)]) == nil)
    }

    @Test func weekOverWeek() {
        #expect(abs(EffortLoad.weekOverWeek(current: week(1180, coverage: 1), previous: week(1000, coverage: 0.5))! - 0.18) < 0.0001)
        #expect(EffortLoad.weekOverWeek(current: week(1180, coverage: 1), previous: week(1000, coverage: 0.25)) == nil)
        #expect(EffortLoad.weekOverWeek(current: week(1180, coverage: 1), previous: nil) == nil)
    }

    @Test func sentenceKindPriority() {
        // 단조도 ≥ 2 & coverage 1 → monotony
        let flat = EffortLoad.WeekLoad(weekStart: monday, total: 700, daily: [100, 100, 100, 100, 100, 100, 110],
                                       dailyMeanEffort: Array(repeating: 5, count: 7), runCount: 7, coveredCount: 7, meanEffort: 5)
        #expect(EffortLoad.sentenceKind(current: flat, previous: [week(300, coverage: 1), week(300, coverage: 1), week(300, coverage: 1)]) == .monotony)
        // 단조도 미달 → 비율 라벨
        let spiky = week(1200, coverage: 1)
        #expect(EffortLoad.sentenceKind(current: spiky, previous: [week(600, coverage: 1), week(600, coverage: 1), week(600, coverage: 1)]) == .veryHigh)
        #expect(EffortLoad.sentenceKind(current: week(600, coverage: 1), previous: [week(600, coverage: 1), week(600, coverage: 1), week(600, coverage: 1)]) == nil)
        #expect(EffortLoad.sentenceKind(current: week(400, coverage: 1), previous: [week(600, coverage: 1), week(600, coverage: 1), week(600, coverage: 1)]) == .low)
    }

    @Test func weeksSeriesOldestToNewest() {
        let runs = [run(-14, min: 30, effort: 5), run(0, min: 30, effort: 5)]
        let ws = EffortLoad.weeks(runs: runs, endingAt: monday, count: 3, calendar: cal)
        #expect(ws.count == 3)
        #expect(ws[0]?.total == 150)
        #expect(ws[1] == nil)
        #expect(ws[2]?.total == 150)
    }

    @Test func recoveryWeekJudgement() {
        #expect(EffortLoad.isRecoveryPhase("회복"))
        #expect(EffortLoad.isRecoveryPhase("테이퍼"))
        #expect(!EffortLoad.isRecoveryPhase("기초"))
        #expect(EffortLoad.recoveryWeekExceeds(meanEffort: 6.2, coverage: 0.6, eightWeekEfforts: [4, 5, 5, 6]))
        #expect(!EffortLoad.recoveryWeekExceeds(meanEffort: 5.9, coverage: 0.6, eightWeekEfforts: [4, 5, 5, 6]))
        #expect(!EffortLoad.recoveryWeekExceeds(meanEffort: 8, coverage: 0.4, eightWeekEfforts: [4, 5, 5]))
        #expect(!EffortLoad.recoveryWeekExceeds(meanEffort: 8, coverage: 1, eightWeekEfforts: [4, 5]))
    }
}
