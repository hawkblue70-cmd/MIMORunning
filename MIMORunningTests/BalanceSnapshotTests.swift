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
                sleepHours: 7, usualSleepHours: 7, hrvLevel: .good, load: .steady,
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
}
