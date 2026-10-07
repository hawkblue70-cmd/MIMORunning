import Testing
import Foundation
@testable import MIMORunning

@Suite("월 기록 공유 카드 — 시간·훈련 구성·계획 수행", .korean)
struct MRMonthShareSummaryTests {

    private let cal = Calendar.current
    private func d(_ m: Int, _ day: Int, _ h: Int = 7) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: day, hour: h))!
    }
    private func run(_ date: Date, km: Double) -> MRWorkout {
        MRWorkout(start: date, durationMin: km * 6, distanceKm: km, hrAvg: 140, hrMax: 170,
                  tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }
    /// 10월 네 주 — 화 8 · 목 8(템포런) · 토 16
    private var runs: [MRWorkout] {
        [5, 12, 19, 26].flatMap { mon in
            [run(d(10, mon + 1), km: 8), run(d(10, mon + 3), km: 8), run(d(10, mon + 5), km: 16)]
        }
    }

    @Test func totalsCompositionAndPlan() throws {
        let thursdays = Set(runs.filter { cal.component(.weekday, from: $0.start) == 5 }.map(\.start))
        let types = Dictionary(uniqueKeysWithValues: thursdays.map { ($0, WorkoutType.tempo) })
        let frozen = [MRMonthlyFrozenWeek(monday: cal.startOfDay(for: d(10, 12)), goalKm: 140,
                                          summary: MRPlanWeekSummary(idx: 2, monday: cal.startOfDay(for: d(10, 12)),
                                                                     phase: "유지", longRunKm: 16, weeklyKm: 32))]
        let m = try #require(MRMonthShareSummary.make(runs: runs, start: d(10, 1, 0), end: d(11, 1, 0),
                                                      intenseStarts: [], pointTypes: types,
                                                      frozenWeeks: frozen, now: d(11, 2)))
        #expect(m.totalMin == 32 * 6 * 4)
        #expect(m.paceSecPerKm == 360)
        #expect(m.longRuns == 4)
        #expect(m.hardRuns == 4)
        #expect(m.easyRuns == 4)
        #expect(m.longestKm == 16)
        #expect(m.planSymbols.map(\.symbol) == [symbolBoth])
        #expect(m.planSymbols.first?.count == 1)
    }

    @Test func noRunsNoSummary() {
        #expect(MRMonthShareSummary.make(runs: runs, start: d(12, 1, 0), end: d(12, 31, 0),
                                         intenseStarts: [], pointTypes: [:], frozenWeeks: []) == nil)
    }

    @Test func hmsFormat() {
        #expect(MileageStreakShareCard.hms(792.67) == "13:12:40")
        #expect(MileageStreakShareCard.hms(52.5) == "52:30")
    }
}
