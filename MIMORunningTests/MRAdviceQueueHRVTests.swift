import Testing
import Foundation
@testable import MIMORunning

@Suite("MRAdviceQueue 수면 HRV 조언", .korean)
struct MRAdviceQueueHRVTests {

    private let cal = Calendar.current

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: Date())!)
    }

    private func run(daysAgo: Int, hr: Double = 140, interval: Bool = false) -> MRWorkout {
        MRWorkout(start: day(-daysAgo).addingTimeInterval(7 * 3600), durationMin: 50, distanceKm: 8,
                  hrAvg: hr, hrMax: 170, tempC: 15, humidity: nil, indoor: false, isInterval: interval)
    }

    /// 14일 동안 이지런 6회(2~3일 간격), 마지막은 어제.
    private func easyBlock() -> [MRWorkout] {
        [13, 11, 8, 6, 3, 1].map { run(daysAgo: $0) }   // 이미 오래된 것 → 최신 순(runs.last = 어제)
    }

    private func trend(state: MRHRVTrend.State, volatile: Bool = false) -> MRHRVTrend {
        MRHRVTrend(state: state, isVolatile: volatile, sevenDayMean: 37, baseline: 30, baselineSD: 3,
                   sevenDayCV: 0.05, baselineCV: 0.06, sevenDayNights: 7, baselineNights: 28)
    }

    private var phys: MRPhysiology {
        var p = MRPhysiology()
        p.lt1HR = MRInference(value: 150, confidence: .high, basis: [])
        return p
    }

    private func build(runs: [MRWorkout], trend: MRHRVTrend?) -> [MRAdvice] {
        mrBuildAdvice(runs: runs, phys: phys, plans: [], races: [], gaps: [], strengthPerWeek: 2,
                      fatigue: [], cadenceShift: nil, hrvTrend: trend, log: MRAdviceLog(), asOf: Date())
    }

    private func hrvAdvice(_ a: [MRAdvice]) -> MRAdvice? { a.first { $0.key == "hrvReady" } }

    @Test func readyHighAfterEasyBlockGivesAdvice() {
        let a = hrvAdvice(build(runs: easyBlock(), trend: trend(state: .above)))
        #expect(a != nil)
        #expect(a?.slot == "todayRun")
        #expect(a?.grade == "B")
        #expect(a?.text == "지난 2주는 이지런 위주였고 수면 HRV 7일 평균이 4주 기준선 위로 안정적이에요. 이번 주 강도 세션 하나 넣기 좋은 때예요.")
        #expect(a?.rationale == "HRV 7일 37ms · 4주 기준선 30ms · 14일 고강도 0회 · Vesterinen 2016(HRV 기반 강도 조절) · 회복 지표이지 체력 지표는 아님")
    }

    @Test func noAdviceWhenTrendMissing() {
        #expect(hrvAdvice(build(runs: easyBlock(), trend: nil)) == nil)
    }

    @Test func noAdviceWhenVolatile() {
        #expect(hrvAdvice(build(runs: easyBlock(), trend: trend(state: .above, volatile: true))) == nil)
    }

    @Test func noAdviceWhenWithinOrBelow() {
        #expect(hrvAdvice(build(runs: easyBlock(), trend: trend(state: .within))) == nil)
        #expect(hrvAdvice(build(runs: easyBlock(), trend: trend(state: .below))) == nil)
    }

    @Test func noAdviceWhenTwoHardRunsInFourteenDays() {
        var runs = easyBlock()
        runs[1] = run(daysAgo: 11, interval: true)
        runs[3] = run(daysAgo: 6, hr: 160)
        #expect(hrvAdvice(build(runs: runs, trend: trend(state: .above))) == nil)
    }

    @Test func oneHardRunStillCountsAsEasyBlock() {
        var runs = easyBlock()
        runs[2] = run(daysAgo: 8, interval: true)
        let a = hrvAdvice(build(runs: runs, trend: trend(state: .above)))
        #expect(a != nil)
        #expect(a?.rationale.contains("14일 고강도 1회") == true)
    }

    @Test func noAdviceWhenFewerThanFourRuns() {
        let runs = [run(daysAgo: 9), run(daysAgo: 5), run(daysAgo: 1)]
        #expect(hrvAdvice(build(runs: runs, trend: trend(state: .above))) == nil)
    }

    @Test func noAdviceWhenLastRunOlderThanThreeDays() {
        let runs = [13, 11, 9, 7, 5, 4].map { run(daysAgo: $0) }
        #expect(hrvAdvice(build(runs: runs, trend: trend(state: .above))) == nil)
    }

    @Test func lastRunExactlyThreeDaysAgoStillGivesAdvice() {
        let runs = [13, 11, 9, 7, 5, 3].map { run(daysAgo: $0) }
        #expect(hrvAdvice(build(runs: runs, trend: trend(state: .above))) != nil)
    }
}
