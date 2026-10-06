import Testing
import Foundation
@testable import MIMORunning

@Suite("월간 거리 목표 → 주차 계획", .korean)
struct MRMonthlyPlannerTests {

    private let cal = Calendar.current
    /// 2026-10-12(월) 06시가 "오늘". 10월 주 = 9/28 · 10/5 · 10/12 · 10/19 · 10/26.
    private var today: Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 6))!
    }
    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .hour, value: 7, to: cal.date(byAdding: .day, value: offset,
                                                         to: cal.startOfDay(for: today))!)!
    }
    private func run(_ offset: Int, km: Double) -> MRWorkout {
        MRWorkout(start: day(offset), durationMin: km * 6, distanceKm: km, hrAvg: 140, hrMax: 170,
                  tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }
    /// 지난 `weeks`주 — 주마다 (요일 오프셋, km). 이번 주(10/12~)에는 러닝 없음.
    private func history(weeks: Int, pattern: [(Int, Double)]) -> [MRWorkout] {
        (1...weeks).flatMap { w in pattern.map { run(-7 * w + $0.0, km: $0.1) } }
            .sorted { $0.start < $1.start }
    }
    /// 화 8 · 목 8 · 토 16 = 주 32km, 3회
    private var three: [(Int, Double)] { [(1, 8), (3, 8), (5, 16)] }
    /// 화 8 · 수 8 · 목 8 · 토 16 = 주 40km, 4회
    private var four: [(Int, Double)] { [(1, 8), (2, 8), (3, 8), (5, 16)] }

    private func sumMatches(_ w: MRMonthlyWeek) -> Bool {
        guard let p = w.plannedKm else { return true }
        let total = w.longRunKm + w.easyKm * Double(w.easyRuns) + (w.point?.totalKm ?? 0)
        return abs(total - p) < 0.3
    }

    @Test func basisFromOwnRecords() {
        let b = MRMonthlyPlanner.basis(runs: history(weeks: 52, pattern: three), asOf: today)
        #expect(abs(b.baseWeeklyKm - 32) < 0.01)
        #expect(b.usualRuns == 3)
        #expect(abs(b.maxWeeklyKm52w - 32) < 0.01)
        #expect(b.maxRuns52w == 3)
        #expect(b.easyCapKm == 8)
        #expect(b.longest16wKm == 16)
    }

    @Test func tooFewWeeksGivesNoPlan() {
        #expect(MRMonthlyPlanner.build(goalKm: 150, runs: history(weeks: 4, pattern: three), asOf: today) == nil)
    }

    @Test func pastWeeksShowActualOnly() throws {
        let plan = try #require(MRMonthlyPlanner.build(goalKm: nil, runs: history(weeks: 52, pattern: three), asOf: today))
        #expect(plan.weeks.count == 5)
        #expect(plan.weeks.prefix(2).allSatisfy { $0.isPast && $0.plannedKm == nil })
        #expect(plan.weeks[2].isCurrent)
        #expect(plan.weeks.dropFirst(2).allSatisfy { $0.plannedKm != nil })
        #expect(plan.weeks[0].daysInMonth == 4)   // 10/1~10/4
        #expect(plan.weeks[4].daysInMonth == 6)   // 10/26~10/31
    }

    @Test func noGoalStaysInsideExperienceAndSplitsAddUp() throws {
        let plan = try #require(MRMonthlyPlanner.build(goalKm: nil, runs: history(weeks: 52, pattern: three), asOf: today))
        for w in plan.weeks where w.plannedKm != nil {
            #expect(w.plannedKm! <= 32 * 1.1 + 0.05)
            #expect(w.easyKm <= 8.05)
            #expect(sumMatches(w))
        }
        #expect(plan.limits.isEmpty)
        #expect(plan.maxMonthKm >= plan.maintainMonthKm - 1)
    }

    @Test func modestGoalIsKeptWithoutCarryOver() throws {
        // 130km/31일 = 주 29.4km — 지금(32)보다 낮아 그대로. 지난 주가 모자라도 얹지 않는다.
        let plan = try #require(MRMonthlyPlanner.build(goalKm: 130, runs: history(weeks: 52, pattern: three), asOf: today))
        let rate = 130.0 * 7 / 31
        #expect(plan.limits.isEmpty)
        for w in plan.weeks where w.plannedKm != nil {
            #expect(w.plannedKm! <= rate + 0.05)
            #expect(sumMatches(w))
        }
        #expect(plan.nextMonthKm == nil)
    }

    @Test func tooBigGoalIsLoweredWithReasonAndNextMonth() throws {
        // 1년 전엔 주 40(4회), 최근 6주는 주 32(3회) — 목표 250은 이번 달 불가, 다음 달 경로를 말한다
        let old = (7...30).flatMap { w in four.map { run(-7 * w + $0.0, km: $0.1) } }
        let plan = try #require(MRMonthlyPlanner.build(goalKm: 250, runs: old + history(weeks: 6, pattern: three), asOf: today))
        #expect(plan.limits.contains(.growth))
        #expect(plan.projectedMonthKm < 250)
        let next = try #require(plan.nextMonthKm)
        #expect(next > plan.projectedMonthKm)
        // 경험 밖으로는 한 달에 12개월 최대 × 1.1까지
        #expect(plan.weeks.compactMap(\.plannedKm).allSatisfy { $0 <= 40 * 1.1 + 0.05 })
    }

    @Test func returningRunnerGrowsFasterInsideExperience() throws {
        // 1년 전엔 주 40(4회), 최근 6주는 주 32(3회) — 경험 범위 안이라 +15%
        let old = (7...30).flatMap { w in four.map { run(-7 * w + $0.0, km: $0.1) } }
        let recent = history(weeks: 6, pattern: three)
        let plan = try #require(MRMonthlyPlanner.build(goalKm: nil, runs: old + recent, asOf: today))
        let first = try #require(plan.weeks.first { $0.isCurrent }?.plannedKm)
        #expect(first > 32 * 1.10 + 0.05)
        #expect(first <= 32 * 1.15 + 0.05)
    }

    @Test func extraRunSuggestedBeforeLongerEasyRuns() throws {
        // 평소 3회지만 12개월 안에 4회 주가 있다 — 이지 상한(8)을 넘기 전에 한 번 더
        let old = (7...30).flatMap { w in four.map { run(-7 * w + $0.0, km: $0.1) } }
        let recent = history(weeks: 6, pattern: three)
        let plan = try #require(MRMonthlyPlanner.build(goalKm: 170, runs: old + recent, asOf: today))
        let planned = plan.weeks.filter { $0.plannedKm != nil }
        #expect(planned.contains { $0.addedRun && $0.runs == 4 })
        #expect(planned.allSatisfy { $0.easyKm <= plan.easyCapKm + 0.05 })
    }

    @Test func frequencyCeilingLowersWeekAndSaysOneMore() throws {
        // 늘 3회 · 12개월 최대 주 32 → 목표 180이면 횟수 천장
        let plan = try #require(MRMonthlyPlanner.build(goalKm: 180, runs: history(weeks: 52, pattern: three), asOf: today))
        let freq = plan.limits.first { if case .frequency = $0 { return true }; return false }
        guard case .frequency(let n, let maxKm, let plusOne)? = freq else {
            Issue.record("횟수 천장 이유가 없음: \(plan.limits)"); return
        }
        #expect(n == 3)
        #expect(maxKm > 32)
        #expect((plusOne ?? 0) > maxKm)
    }

    @Test func pointEveryWeekWhenHoldingButSpacedWhenGrowing() throws {
        let paces = mrPointPaces(halfEquivMin: 110)
        let input = MRMonthlyPlanner.PointInput(habitEveryWeeks: 1, paces: paces)
        // 유지(주 40 ≈ 177km/31일) — 4회라 매주
        let hold = try #require(MRMonthlyPlanner.build(goalKm: 40 * 31 / 7, runs: history(weeks: 52, pattern: four),
                                                       asOf: today, point: input))
        #expect(hold.weeks.filter { $0.plannedKm != nil }.allSatisfy { $0.point != nil })
        #expect(hold.weeks.allSatisfy(sumMatches))
        // 늘림 — 최근 주 30(4회), 12개월 최대 40. 늘리는 주는 간격 +1주라 이번 주 다음 주에는 없다
        let old = (7...52).flatMap { w in four.map { run(-7 * w + $0.0, km: $0.1) } }
        let recent = history(weeks: 6, pattern: [(1, 6), (2, 6), (3, 6), (5, 12)])
        let grow = try #require(MRMonthlyPlanner.build(goalKm: 240, runs: old + recent, asOf: today, point: input))
        let planned = grow.weeks.filter { $0.plannedKm != nil }
        #expect(planned[0].point != nil)
        #expect(planned[1].point == nil)
        #expect(grow.weeks.allSatisfy(sumMatches))
    }

    @Test func recentPointDelaysNextOne() throws {
        let runs = history(weeks: 52, pattern: [(1, 6), (3, 10), (5, 16)])   // 3회 → 격주, 이지 상한 10
        let input = MRMonthlyPlanner.PointInput(habitEveryWeeks: 2, paces: mrPointPaces(halfEquivMin: 110),
                                                lastPointStart: day(-4), lastPointType: .interval)
        let plan = try #require(MRMonthlyPlanner.build(goalKm: 32 * 31 / 7, runs: runs, asOf: today, point: input))
        let planned = plan.weeks.filter { $0.plannedKm != nil }
        #expect(planned[0].point == nil)                    // 지난주(10/8)에 했다 → 이번 주 없음
        #expect(planned[1].point?.kind == .tempo)           // 인터벌 다음은 템포런
    }
}
