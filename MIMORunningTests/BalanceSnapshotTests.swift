import Testing
import Foundation
@testable import MIMORunning

@Suite("밸런스 탭 판정", .korean)
struct BalanceSnapshotTests {

    private func stat(_ median: Double, _ sd: Double) -> FormStat {
        FormStat(median: median, sd: sd, count: 30, p10: nil, p90: nil)
    }
    private typealias S = BalanceSnapshot

    /// 모든 값이 평소 중앙인 기본 입력.
    private func base() -> S.Input {
        S.Input(workoutType: .easy, paceSecPerKm: 360, hasForm: true, isReferenceBand: false,
                heartRate: 150, heartRateStat: stat(150, 5),
                cadence: 172, cadenceStat: stat(172, 3),
                stride: 1.0, strideStat: stat(1.0, 0.03),
                groundContact: 250, groundContactStat: stat(250, 8),
                verticalOsc: 8.0, verticalOscStat: stat(8.0, 0.4),
                effort: 5, effortTypeMedian: 5,
                sleepHours: 7, usualSleepHours: 7, hrvLevel: .good, hrvDisplay: "좋음", load: .steady,
                vo2: 48, vo2SixMonths: [47, 49])
    }

    @Test func sleepLevels() {
        #expect(S.sleepLevel(hours: 7, usual: 7) == .good)
        #expect(S.sleepLevel(hours: 6.6, usual: 7) == .good)
        #expect(S.sleepLevel(hours: 6.2, usual: 7) == .normal)
        #expect(S.sleepLevel(hours: 5.9, usual: 7) == .bad)
    }

    @Test func loadLevels() {
        #expect(S.loadLevel(.steady) == .good)
        #expect(S.loadLevel(.low) == .normal)
        #expect(S.loadLevel(.high) == .bad)
        #expect(S.loadLevel(.veryHigh) == .bad)
    }

    @Test func vo2Levels() {
        #expect(S.vo2Level(current: 48, sixMonths: []) == nil)
        #expect(S.vo2Level(current: 48, sixMonths: [47, 49]) == .good)
        #expect(S.vo2Level(current: 46.5, sixMonths: [47, 49]) == .bad)
    }

    @Test func allInRangeIsLevel() throws {
        let s = try #require(S.make(base()))
        #expect(s.mode == .full)
        #expect(s.inputScore == 0)
        #expect(s.outputScore == 0)
        #expect(s.tilt == 0)
    }

    @Test func heavyLegsTiltsLeft() throws {
        var i = base()
        i.heartRate = 160
        i.cadence = 166
        i.sleepHours = 5
        let s = try #require(S.make(i))
        #expect(s.inputScore == 2)
        #expect(s.outputScore == -1)
        #expect(s.tilt == 0.75)
        #expect(s.axes.first { $0.kind == .cadence }?.status == .below)
    }

    @Test func formAxesUseGivenStats() throws {
        var i = base()
        i.stride = 1.05
        let s = try #require(S.make(i))
        let expected = FormNarrative.status(rawValue: 1.05, stat: stat(1.0, 0.03), metric: .stride)
        #expect(expected == .above)
        #expect(s.axes.first { $0.kind == .stride }?.status == expected)
    }

    @Test func referenceBandDoesNotScore() throws {
        var i = base()
        i.isReferenceBand = true
        i.heartRate = 170
        i.cadence = 160
        let s = try #require(S.make(i))
        #expect(s.axes.count == 5)
        #expect(s.axes.allSatisfy { $0.status == .unknown })
        #expect(s.inputScore == 0)
        #expect(s.outputScore == 0)
    }

    @Test func intervalShowsBodyOnly() throws {
        var i = base()
        i.workoutType = .interval
        let s = try #require(S.make(i))
        #expect(s.mode == .bodyOnly)
        #expect(s.axes.isEmpty)
        i.sleepHours = nil; i.usualSleepHours = nil; i.hrvLevel = nil; i.load = nil
        i.vo2 = nil; i.vo2SixMonths = []
        #expect(S.make(i) == nil)
    }

    @Test func modeByAvailableData() throws {
        var i = base()
        i.hasForm = false
        #expect(S.make(i)?.mode == .scaleOnly)
        var e = base()
        e.hasForm = false
        e.heartRate = nil; e.heartRateStat = nil
        e.effort = nil; e.effortTypeMedian = nil
        e.sleepHours = nil; e.usualSleepHours = nil; e.hrvLevel = nil; e.load = nil
        #expect(S.make(e) == nil)
        var v = base()
        v.verticalOsc = 12
        let s = try #require(S.make(v))
        #expect(s.outputScore == 0)
    }

    private func trend(_ st: MRHRVTrend.State = .within, volatile: Bool = false,
                       mean: Double = 50, base: Double = 50, cv7: Double = 0.1, cvBase: Double = 0.1) -> MRHRVTrend {
        MRHRVTrend(state: st, isVolatile: volatile, sevenDayMean: mean, baseline: base, baselineSD: 5,
                   sevenDayCV: cv7, baselineCV: cvBase, sevenDayNights: 7, baselineNights: 28)
    }

    @Test func hrvLevels() {
        #expect(S.hrvLevel(nil, lastNightLow: false) == nil)
        #expect(S.hrvLevel(trend(volatile: true), lastNightLow: false) == .bad)
        #expect(S.hrvLevel(trend(.below), lastNightLow: false) == .bad)
        #expect(S.hrvLevel(trend(.above), lastNightLow: true) == .bad)
        #expect(S.hrvLevel(trend(.above), lastNightLow: false) == .good)
        #expect(S.hrvLevel(trend(.within), lastNightLow: false) == .normal)
    }

    @Test func bodiesOrderAndDisplay() throws {
        var i = base()
        i.sleepHours = 5.0; i.hrvLevel = .bad; i.hrvDisplay = "불안정"; i.load = .high
        var s = try #require(S.make(i))
        #expect(s.bodies.map(\.kind) == [.sleep, .hrv, .load, .vo2])
        #expect(s.bodies.map(\.display) == ["5h", "불안정", "높음", "48.0"])
        i.sleepHours = 6.5
        s = try #require(S.make(i))
        #expect(s.bodies[0].display == "6.5h")
        i.hrvDisplay = nil
        s = try #require(S.make(i))
        #expect(!s.bodies.contains { $0.kind == .hrv })
    }

    @Test func effortScoring() throws {
        var i = base()
        i.effort = 7
        #expect(try #require(S.make(i)).inputScore == 1)
        i.effort = 3
        #expect(try #require(S.make(i)).inputScore == -1)
        i.effort = 6
        #expect(try #require(S.make(i)).inputScore == 0)
    }

    @Test func groundContactDirection() throws {
        var i = base()
        i.groundContact = 230
        #expect(try #require(S.make(i)).outputScore == 1)
        i.groundContact = 270
        #expect(try #require(S.make(i)).outputScore == -1)
    }

    @Test func intervalBadSleepAddsInput() throws {
        var i = base()
        i.workoutType = .interval
        i.sleepHours = 5
        let s = try #require(S.make(i))
        #expect(s.mode == .bodyOnly)
        #expect(s.inputScore == 1)
    }

    @MainActor @Test func usualSleepMedianExcludesTodayAndNeedsSeven() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 8))!
        func night(_ daysAgo: Int, _ h: Double) -> (date: Date, value: Double) {
            (cal.date(byAdding: .day, value: -daysAgo, to: today)!, h)
        }
        // 6밤뿐이면 nil
        let few = (1...6).map { night($0, 7) }
        #expect(MREngineStore.usualSleepHours(nights: few, asOf: today, calendar: cal) == nil)
        // 10밤(6·7·8 섞음) + 그날 밤 3시간 — 그날 값은 중앙값에 안 들어감
        let hours: [Double] = [6, 7, 8, 6, 7, 8, 7, 7, 6, 8]
        var nights = hours.enumerated().map { night($0.offset + 1, $0.element) }
        nights.append(night(0, 3))
        #expect(MREngineStore.usualSleepHours(nights: nights, asOf: today, calendar: cal) == 7)
    }
}
