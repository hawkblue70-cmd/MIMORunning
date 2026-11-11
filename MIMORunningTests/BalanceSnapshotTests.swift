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
        #expect(s.tilt == 0.25)     // 왼쪽 빨강 2(심박·수면) − 오른쪽 빨강 1(케이던스)
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
        var b = base()          // 몸 상태·체감은 있지만 폼·심박 없음 → 탭 숨김
        b.hasForm = false
        b.heartRate = nil; b.heartRateStat = nil
        #expect(S.make(b) == nil)
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

    // MARK: - 그리기 재료 (Task 3)

    @Test func radiusScale() {
        let st = stat(100, 10)   // 하한 88 · 상한 112
        #expect(S.radius(value: 100, stat: st) == 0.5)
        #expect(abs(S.radius(value: 112, stat: st) - 0.75) < 1e-9)
        #expect(abs(S.radius(value: 88, stat: st) - 0.25) < 1e-9)
        #expect(S.radius(value: 200, stat: st) == 1.0)
        #expect(S.radius(value: 0, stat: st) == 0.1)
    }

    @Test func adverseDirections() {
        #expect(S.isAdverse(.heartRate, .above))
        #expect(!S.isAdverse(.heartRate, .below))
        #expect(S.isAdverse(.cadence, .below))
        #expect(S.isAdverse(.stride, .below))
        #expect(S.isAdverse(.groundContact, .above))
        #expect(!S.isAdverse(.groundContact, .below))
        #expect(!S.isAdverse(.verticalOsc, .above))
        #expect(!S.isAdverse(.verticalOsc, .below))
        #expect(!S.isAdverse(.cadence, .unknown))
    }

    @Test func blocksAllUsualOnLevelDay() throws {
        let s = try #require(S.make(base()))
        #expect(s.inputBlocks.map(\.kind) == [.heartRate, .effort, .sleep, .hrv, .load])
        #expect(s.outputBlocks.map(\.kind) == [.cadence, .stride, .groundContact])
        #expect(s.inputBlocks.filter { [.heartRate, .effort].contains($0.kind) }.allSatisfy { $0.tone == .usual && $0.height == 0.5 })
        #expect(s.outputBlocks.allSatisfy { $0.tone == .usual && $0.height == 0.5 })
    }

    @Test func blocksHeavyLegs() throws {
        var i = base()
        i.heartRate = 160; i.cadence = 166; i.groundContact = 270; i.effort = 8
        let s = try #require(S.make(i))
        let inB = Dictionary(uniqueKeysWithValues: s.inputBlocks.map { ($0.kind, $0) })
        let outB = Dictionary(uniqueKeysWithValues: s.outputBlocks.map { ($0.kind, $0) })
        #expect(inB[.heartRate]?.tone == .bad)
        #expect(inB[.effort]?.tone == .bad)
        #expect(outB[.cadence]?.tone == .bad)
        #expect(outB[.groundContact]?.tone == .bad)
        // 접지가 길면 나온 것 블록은 작아진다(눈금 뒤집힘)
        #expect((outB[.groundContact]?.height ?? 1) < 0.5)
    }

    @Test func referenceBandBlocksStayGray() throws {
        var i = base()
        i.isReferenceBand = true
        i.heartRate = 170; i.cadence = 160
        let s = try #require(S.make(i))
        #expect(s.axes.allSatisfy { !S.isAdverse($0.kind, $0.status) })
        #expect(s.inputBlocks.first { $0.kind == .heartRate }?.tone == .usual)
        #expect(s.outputBlocks.allSatisfy { $0.tone == .usual })
    }

    @Test func scaleOnlyNeedsHeartRateValue() {
        var i = base()
        i.hasForm = false
        i.heartRate = nil
        i.effort = nil; i.effortTypeMedian = nil
        i.sleepHours = nil; i.usualSleepHours = nil; i.hrvLevel = nil; i.load = nil
        #expect(S.make(i) == nil)
    }

    @Test func longDistanceDoesNotScoreFormOrHR() throws {
        var i = base()
        i.isLongDistance = true
        i.heartRate = 170; i.cadence = 160; i.stride = 0.8; i.groundContact = 290
        let s = try #require(S.make(i))
        #expect(s.mode == .full)
        #expect(s.axes.count == 5)                               // 축은 그린다
        #expect(s.axes.allSatisfy { $0.status == .unknown })     // 판정·빨간 점 없음
        #expect(s.inputScore == 0)
        #expect(s.outputScore == 0)
        #expect(s.isReference)
        #expect(s.inputBlocks.first { $0.kind == .heartRate }?.tone == .usual)
    }

    @Test func zeroWidthStatIsUnknown() throws {
        var i = base()
        i.heartRate = 160; i.heartRateStat = stat(150, 0)   // 상한 = 하한
        let s = try #require(S.make(i))
        #expect(s.axes.first { $0.kind == .heartRate }?.status == .unknown)
        #expect(s.inputScore == 0)
    }

    // MARK: 한 줄 해석

    @Test func summaryLineHeavyLegs() throws {
        // 11/9 이지런 모양 — 들인 것 평소, 케이던스 낮고 접지 김
        var i = base()
        i.cadence = 166
        i.groundContact = 270
        let s = try #require(S.make(i))
        #expect(s.summaryLine == "심박·몸 상태는 평소였지만, 같은 페이스를 낮은 케이던스·긴 접지로 달렸습니다.")
    }

    @Test func summaryLineAllUsualAndBothSides() throws {
        #expect(try #require(S.make(base())).summaryLine == "몸 상태·부담도 움직임도 평소 범위였습니다.")
        var i = base()
        i.sleepHours = 5
        i.heartRate = 160
        #expect(try #require(S.make(i)).summaryLine == "심박이 높았고 잠이 짧았지만, 움직임은 평소 범위였습니다.")
        i.cadence = 166
        #expect(try #require(S.make(i)).summaryLine == "심박이 높았고 잠이 짧았고, 같은 페이스를 낮은 케이던스로 달렸습니다.")
    }

    @Test func summaryLineReferenceAndInterval() throws {
        var i = base()
        i.isReferenceBand = true
        #expect(try #require(S.make(i)).summaryLine == "폼·심박은 참고로 표시합니다. 몸 상태는 평소였습니다.")
        var iv = base()
        iv.workoutType = .interval
        #expect(try #require(S.make(iv)).summaryLine == nil)
    }

    @Test func problemSideGoesDown() throws {
        // 11/9 모양 — 들인 것 모두 평소, 나온 것 케이던스·접지 빨강 → 오른쪽이 내려간다
        var i = base()
        i.cadence = 166
        i.groundContact = 270
        #expect(try #require(S.make(i)).tilt == -0.5)
        // 좋은 쪽 이탈(심박 낮음·케이던스 높음)은 기울이지 않는다
        var g = base()
        g.heartRate = 140
        g.cadence = 180
        #expect(try #require(S.make(g)).tilt == 0)
    }

    @Test func favorableDeviationIsGreenButDoesNotTilt() throws {
        var i = base()
        i.heartRate = 140      // 평소보다 낮음
        i.cadence = 180        // 평소보다 높음
        i.groundContact = 235  // 평소보다 짧음
        i.effort = 2           // 평소보다 2 낮음
        let s = try #require(S.make(i))
        #expect(s.inputBlocks.first { $0.kind == .heartRate }?.tone == .good)
        #expect(s.inputBlocks.first { $0.kind == .effort }?.tone == .good)
        #expect(s.outputBlocks.first { $0.kind == .cadence }?.tone == .good)
        #expect(s.outputBlocks.first { $0.kind == .groundContact }?.tone == .good)
        #expect(s.tilt == 0)
        #expect(S.isFavorable(.verticalOsc, .above) == false)
    }
}
