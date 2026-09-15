import Testing
import Foundation
@testable import MIMORunning

@Suite("EffortLoad sRPE 주간 부하", .korean)
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

    @Test func restWeeksCountAsZeroInChronic() {
        let cur = week(1200, coverage: 1)
        // 800, 휴식, 800, 800 → chronic 600 → ratio 2.0 veryHigh
        let r = EffortLoad.acuteChronic(current: cur, previous: [week(800, coverage: 1), nil, week(800, coverage: 1), week(800, coverage: 1)])!
        #expect(abs(r.ratio - 2.0) < 0.0001)
        #expect(r.label == .veryHigh)
        // 휴식 주도 유효 주로 센다: 800, nil, nil → 3주 유효, chronic 266.7
        #expect(EffortLoad.acuteChronic(current: cur, previous: [week(800, coverage: 1), nil, nil]) != nil)
        // 러닝은 있는데 커버리지 미달인 주는 제외
        #expect(EffortLoad.acuteChronic(current: cur, previous: [week(800, coverage: 0.25), nil, nil]) == nil)
    }

    @Test func weeksCountZeroIsEmpty() {
        #expect(EffortLoad.weeks(runs: [], endingAt: monday, count: 0, calendar: cal).isEmpty)
    }

    @Test func monotonySingleActiveDayIsLow() {
        let m = EffortLoad.monotony(daily: [700, 0, 0, 0, 0, 0, 0])!
        #expect(m < 1.0)
    }

    @Test func recoveryWeekExceedsAtExactBoundary() {
        // median 5 → 임계 6.0
        #expect(EffortLoad.recoveryWeekExceeds(meanEffort: 6.0, coverage: 1, eightWeekEfforts: [4, 5, 6]))
        #expect(!EffortLoad.recoveryWeekExceeds(meanEffort: 5.99, coverage: 1, eightWeekEfforts: [4, 5, 6]))
    }

    @Test func runsMapperKeepsRunningOnly() {
        let id = UUID()
        let acts = [Activity(id: id, type: .running, date: monday, duration: 1800, distance: 5000, calories: nil, avgHeartRate: nil),
                    Activity(id: UUID(), type: .walking, date: monday, duration: 1800, distance: 2000, calories: nil, avgHeartRate: nil)]
        let idx = EffortIndex(user: [id.uuidString: 4], apple: [:])
        let runs = EffortLoad.runs(from: acts, index: idx)
        #expect(runs.count == 1)
        #expect(runs[0].durationMin == 30)
        #expect(runs[0].effort == 4)
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

    // MARK: 롤링 7일

    @Test func lastSevenDaysCoversTodayAndSixPriorDays() {
        let asOf = day(2, hour: 10)   // 수요일 10:00
        let runs = [run(2, min: 30, effort: 5),      // 오늘 07:00 → 포함
                    run(-4, min: 30, effort: 5),     // 오늘−6일 → 포함
                    run(-5, min: 30, effort: 5),     // 오늘−7일 → 제외
                    run(3, min: 30, effort: 5)]      // 내일 → 제외
        let w = EffortLoad.lastSevenDays(runs: runs, asOf: asOf, calendar: cal)
        #expect(w.runCount == 2)
        #expect(w.total == 300)
        #expect(w.dayStarts.count == 7)
        #expect(w.dayStarts.first == cal.startOfDay(for: day(-4)))
        #expect(w.dayStarts.last == cal.startOfDay(for: day(2)))
        #expect(w.daily.first == 150)   // 오늘−6일
        #expect(w.daily.last == 150)    // 오늘
        // 러닝이 없어도 nil이 아니다
        let empty = EffortLoad.lastSevenDays(runs: [], asOf: asOf, calendar: cal)
        #expect(empty.total == 0)
        #expect(empty.runCount == 0)
        #expect(empty.coverage == 0)
    }

    @Test func rollingWeekOverWeekComparesAdjacentWindows() {
        let asOf = day(2, hour: 10)
        // 최근 7일 600 AU, 직전 7일 500 AU → +20%
        let runs = [run(0, min: 100, effort: 6), run(-7, min: 100, effort: 5)]
        #expect(abs(EffortLoad.rollingWeekOverWeek(runs: runs, asOf: asOf, calendar: cal)! - 0.2) < 0.0001)
        // 직전 창에 러닝은 있는데 강도 커버리지 < 0.5 → nil
        let lowCoverage = runs + [run(-8, min: 60, effort: nil), run(-9, min: 60, effort: nil)]
        #expect(EffortLoad.rollingWeekOverWeek(runs: lowCoverage, asOf: asOf, calendar: cal) == nil)
    }

    @Test func rollingAcuteChronicTreatsEmptyWindowsAsZero() {
        let asOf = day(2, hour: 10)
        // 이번 창 1200 · 이전 4창 800, 없음, 800, 800 → chronic 600 → 2.0
        let runs = [run(0, min: 240, effort: 5),
                    run(-7, min: 160, effort: 5),     // 이전 1창
                    run(-21, min: 160, effort: 5),    // 이전 3창
                    run(-28, min: 160, effort: 5)]    // 이전 4창
        let r = EffortLoad.rollingAcuteChronic(runs: runs, asOf: asOf, calendar: cal)!
        #expect(abs(r.ratio - 2.0) < 0.0001)
        #expect(r.label == .veryHigh)
    }

    @Test func rollingAcuteChronicYesterdayShiftsWindowOneDay() {
        let asOf = day(2, hour: 10)   // 수요일
        // 이전 4창 각 600 AU. 7일 전(−5) 고강도 1,200 AU는 오늘 7일 창(−4…2)에서 빠졌지만 어제 창(−5…1)에는 들어 있다.
        let base = [run(-9, min: 120, effort: 5), run(-16, min: 120, effort: 5),
                    run(-23, min: 120, effort: 5), run(-30, min: 120, effort: 5)]
        let runs = [run(2, min: 40, effort: 4), run(-5, min: 240, effort: 5)] + base
        let today = EffortLoad.rollingAcuteChronic(runs: runs, asOf: asOf, calendar: cal)!
        let yesterday = EffortLoad.rollingAcuteChronicYesterday(runs: runs, asOf: asOf, calendar: cal)!
        #expect(today.label == .low)
        #expect(yesterday.label == .veryHigh)
        #expect(yesterday == EffortLoad.rollingAcuteChronic(runs: runs, asOf: day(1, hour: 10), calendar: cal)!)
    }

    @Test func rollingSentencePriority() {
        let asOf = day(2, hour: 10)
        // 7일 모두 비슷한 부하 + 커버리지 1 → 단조도
        let flat = (-4...2).map { run($0, min: $0 == 2 ? 22 : 20, effort: 5) }
        #expect(EffortLoad.rollingSentenceKind(runs: flat, asOf: asOf, calendar: cal) == .monotony)
        // 급증 → veryHigh
        let base = [run(-7, min: 120, effort: 5), run(-14, min: 120, effort: 5),
                    run(-21, min: 120, effort: 5), run(-28, min: 120, effort: 5)]   // 이전 4창 각 600
        let spike = [run(0, min: 240, effort: 5)] + base
        #expect(EffortLoad.rollingSentenceKind(runs: spike, asOf: asOf, calendar: cal) == .veryHigh)
        // 유지 → 침묵
        let steady = [run(0, min: 120, effort: 5)] + base
        #expect(EffortLoad.rollingSentenceKind(runs: steady, asOf: asOf, calendar: cal) == nil)
    }

    @Test func rollingSummaryPartialWeekIsNotPenalised() {
        let asOf = day(0, hour: 10)   // 월요일 — 달력 주로는 오늘 1건뿐
        let runs = [run(0, min: 21.8, effort: 5),                                  // 오늘 109 AU
                    run(-1, min: 40, effort: 5), run(-3, min: 40, effort: 5),      // 최근 7일 안의 지난 주 러닝
                    run(-5, min: 40, effort: 5), run(-6, min: 60, effort: 5),      // 합 900
                    run(-8, min: 60, effort: 5), run(-10, min: 60, effort: 5),     // 직전 7일 창 1000
                    run(-13, min: 80, effort: 5)]
        let s = EffortLoad.rollingSummary(runs: runs, asOf: asOf, calendar: cal)
        #expect(abs(s.current.total - 1009) < 0.0001)
        #expect(abs(s.previous.total - 1000) < 0.0001)
        // 롤링 창은 지난 주 러닝을 포함하므로 증감이 작다
        #expect(abs(s.weekOverWeek!) < 0.2)
        // 같은 데이터를 달력 주로 보면 -80% 이하로 왜곡된다 (이 변경의 이유)
        let curWeek = EffortLoad.weekly(runs: runs, weekStart: monday, calendar: cal)!
        let prevWeek = EffortLoad.weekly(runs: runs, weekStart: cal.date(byAdding: .day, value: -7, to: monday)!, calendar: cal)!
        #expect(EffortLoad.weekOverWeek(current: curWeek, previous: prevWeek)! < -0.8)
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
