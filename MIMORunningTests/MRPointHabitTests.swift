import Testing
import Foundation
@testable import MIMORunning

@Suite("강도 훈련 — 본인 빈도 습관", .korean)
struct MRPointHabitTests {

    private let cal = Calendar.current
    /// 2026-10-12(월) 주가 "이번 주". 오프셋 0=월.
    private func day(_ offset: Int, hour: Int = 7) -> Date {
        let mon = cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        return cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: mon)!)!
    }
    private func run(_ offset: Int, km: Double) -> MRWorkout {
        MRWorkout(start: day(offset), durationMin: km * 6, distanceKm: km, hrAvg: 140, hrMax: 170,
                  tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }
    /// 지난 12주 화 8km · 목 8km · 토 16km. `pointEvery` 주마다 목요일을 인터벌로 표시(0이면 없음).
    private func history(pointEvery: Int, weeks: Int = 12) -> (runs: [MRWorkout], types: [Date: WorkoutType]) {
        var runs: [MRWorkout] = []
        var types: [Date: WorkoutType] = [:]
        for w in 1...weeks {
            let thu = run(-7 * w + 3, km: 8)
            runs += [run(-7 * w + 1, km: 8), thu, run(-7 * w + 5, km: 16)]
            if pointEvery > 0 && w % pointEvery == 0 { types[thu.start] = .interval }
        }
        return (runs.sorted { $0.start < $1.start }, types)
    }

    @Test func weeklyHabitIsOne() {
        let h = history(pointEvery: 1)
        #expect(mrHabitualPointEveryWeeks(runs: h.runs, intenseStarts: Set(h.types.keys), asOf: day(2)) == 1)
    }

    @Test func everyOtherWeekIsTwo() {
        let h = history(pointEvery: 2)
        #expect(mrHabitualPointEveryWeeks(runs: h.runs, intenseStarts: Set(h.types.keys), asOf: day(2)) == 2)
    }

    @Test func everyThirdWeekIsThree() {
        let h = history(pointEvery: 3)
        #expect(mrHabitualPointEveryWeeks(runs: h.runs, intenseStarts: Set(h.types.keys), asOf: day(2)) == 3)
    }

    @Test func noHardSessionsStartsSlowlyAtThree() {
        let h = history(pointEvery: 0)
        #expect(mrHabitualPointEveryWeeks(runs: h.runs, intenseStarts: Set(h.types.keys), asOf: day(2)) == 3)
    }

    @Test func intenseLongRunDoesNotCountAsHardSession() {
        // 토요일 롱런만 힘들었으면 강도 훈련이 아니다(롱런으로 셈)
        var h = history(pointEvery: 0)
        for r in h.runs where (r.distanceKm ?? 0) >= 16 { h.types[r.start] = .buildUp }
        #expect(mrHabitualPointEveryWeeks(runs: h.runs, intenseStarts: Set(h.types.keys), asOf: day(2)) == 3)
    }

    @Test func fewerThanSixWeeksIsNil() {
        let h = history(pointEvery: 1, weeks: 5)
        #expect(mrHabitualPointEveryWeeks(runs: h.runs, intenseStarts: Set(h.types.keys), asOf: day(2)) == nil)
    }

    @Test func appliedIntervalIsTheRarerOfRunsRuleAndHabit() {
        #expect(mrPointEveryWeeks(runsPerWeek: 4.2, habit: nil) == 1)
        #expect(mrPointEveryWeeks(runsPerWeek: 4.2, habit: 2) == 2)
        #expect(mrPointEveryWeeks(runsPerWeek: 3, habit: 1) == 2)
        #expect(mrPointEveryWeeks(runsPerWeek: 5, habit: 3) == 3)
        #expect(mrPointEveryWeeks(runsPerWeek: 2, habit: 1) == nil)
    }

    private func plan(habit: Int?) -> MRRacePlan? {
        var p = MRProfile()
        p.weeklyKm4w = 30; p.longestRun16wKm = 14; p.maxWeeklyKm52w = 45; p.runsPerWeek = 5
        let today = Date()
        let race = cal.date(byAdding: .day, value: 7 * 20, to: today)!
        return mrBuildPlan(raceDate: race, distanceM: MRDistance.dH, today: today, profile: p, halfEquivMin: 110,
                           easyPaceSecPerKm: 400, heat: MRHeatModel(), raceTempC: 15, runsPerWeek: 5,
                           pointHabitEveryWeeks: habit)
    }

    @Test func planSpacesPointsByHabit() throws {
        for habit in [2, 3] {
            let p = try #require(plan(habit: habit))
            // 테이퍼를 뺀 강도 훈련 종류 주의 순번에서, 강도 훈련이 든 주끼리 habit 주 이상 떨어져 있다
            let eligible = p.weeks.filter { mrPointKind(phase: $0.phase).map { $0 != .racePaceShort } ?? false }
            let idx = eligible.indices.filter { eligible[$0].point != nil }
            #expect(!idx.isEmpty)
            for (a, b) in zip(idx, idx.dropFirst()) { #expect(b - a >= habit) }
        }
    }

    @Test func rhythmUsesHabitInterval() throws {
        // 주 4회라도 습관 2주면 8일 전 강도 훈련 뒤에는 아직 아니다
        let h = history(pointEvery: 1)
        let lastTue = try #require(h.runs.first { cal.isDate($0.start, inSameDayAs: day(-6)) })
        var ctx = MRRhythmContext(runsPerWeek: 4, paces: mrPointPaces(halfEquivMin: 110), pointTypes: [lastTue.start: .interval])
        ctx.habitEveryWeeks = 2
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx, runs: h.runs, hardStarts: [], asOf: day(2)))
        #expect(!s.isPoint)
    }

    private func zone(_ id: Int, sec: Double) -> HRZoneData {
        HRZoneData(id: id, name: "Z\(id)", minBPM: 0, maxBPM: 0, seconds: sec, fraction: 0)
    }

    private func eff(_ v: Int, _ src: EffortSource) -> ResolvedEffort { ResolvedEffort(value: v, source: src) }

    @Test func actualIntensityByEffortOrZoneFourPlusTime() {
        #expect(mrActualIntensity(effort: eff(7, .user), zones: nil) == "강도 7")
        // 존4 400초 + 존5 300초 = 700초 → 12분
        #expect(mrActualIntensity(effort: eff(5, .user), zones: [zone(3, sec: 1200), zone(4, sec: 400), zone(5, sec: 300)]) == "존4+ 12분")
        // 존3에 오래 머문 "애매하게 빠른" 러닝 — 존4 이상 5분 → 아님
        #expect(mrActualIntensity(effort: nil, zones: [zone(3, sec: 1800), zone(4, sec: 300)]) == nil)
        #expect(mrActualIntensity(effort: eff(6, .user), zones: nil) == nil)
    }

    private func zoneB(_ id: Int, min: Int, max: Int, sec: Double) -> HRZoneData {
        HRZoneData(id: id, name: "Z\(id)", minBPM: min, maxBPM: max, seconds: sec, fraction: 0)
    }

    @Test func heatShiftTrimsZoneFourTime() {
        // 존4 150~165bpm 720초, 존5 0초. 기온으로 +9bpm → 존4 위쪽 6/15만 남음 = 288초
        let zs = [zoneB(4, min: 150, max: 165, sec: 720), zoneB(5, min: 165, max: 185, sec: 0)]
        #expect(abs(mrHeatAdjustedZ4PlusSec(zs, shiftBpm: 9) - 288) < 0.5)
        #expect(mrHeatAdjustedZ4PlusSec(zs, shiftBpm: 0) == 720)
        #expect(mrActualIntensity(effort: nil, zones: zs, heatShiftBpm: 9) == nil)         // 12분 → 보정 뒤 5분
        #expect(mrActualIntensity(effort: nil, zones: zs, heatShiftBpm: 0) == "존4+ 12분")
        // 존4 넘게 오르면 존5도 깎인다: +25bpm → 존5(20bpm 폭)의 위 10/20만
        let hot = [zoneB(4, min: 150, max: 165, sec: 600), zoneB(5, min: 165, max: 185, sec: 800)]
        #expect(abs(mrHeatAdjustedZ4PlusSec(hot, shiftBpm: 25) - 400) < 0.5)
    }

    @Test func estimatedEffortCountsOnlyWithoutZones() {
        let cool = [zoneB(4, min: 150, max: 165, sec: 120)]
        #expect(mrActualIntensity(effort: eff(7, .appleEstimated), zones: cool, heatShiftBpm: 10) == nil)   // 존 있으면 존으로만
        #expect(mrActualIntensity(effort: eff(7, .appleEstimated), zones: nil) == "강도 7(추정)")
        #expect(mrActualIntensity(effort: eff(8, .appleManual), zones: cool, heatShiftBpm: 10) == "강도 8")  // 직접 입력은 그대로
    }

    @Test func heatReasonShownWhenShiftIsMeaningful() {
        let zs = [zoneB(4, min: 150, max: 170, sec: 900), zoneB(5, min: 170, max: 190, sec: 300)]
        // +5bpm → 존4 900×(15/20)=675 + 300 = 975초 → 16분
        #expect(mrActualIntensity(effort: nil, zones: zs, heatShiftBpm: 5) == "존4+ 16분, 기온 −5bpm")
    }
}
