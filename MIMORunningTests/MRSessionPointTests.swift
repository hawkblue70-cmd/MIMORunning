import Testing
import Foundation
@testable import MIMORunning

@Suite("아침 제안 — 계획 포인트", .korean)
struct MRSessionPointTests {

    private let cal = Calendar.current
    /// 2026-10-12(월) 주. 요일 오프셋 0=월 … 6=일.
    private func day(_ offset: Int, hour: Int = 8) -> Date {
        let mon = cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        return cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: mon)!)!
    }
    private func run(_ offset: Int, km: Double) -> MRWorkout {
        MRWorkout(start: day(offset, hour: 7), durationMin: km * 6, distanceKm: km, hrAvg: 140, hrMax: 170,
                  tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }
    /// 지난 8주 화·목 8km, 토 16km → 습관 롱런 요일 토요일(7)
    private func history() -> [MRWorkout] {
        (1...8).flatMap { w in [run(-7 * w + 1, km: 8), run(-7 * w + 3, km: 8), run(-7 * w + 5, km: 16)] }
            .sorted { $0.start < $1.start }
    }
    private let pt = MRPlanPoint(kind: .speed, totalKm: 7.2, reps: 4, repKm: 1, sustainedKm: nil, paceSecPerKm: 305)
    private func plan(point: MRPlanPoint?) -> MRPlanWeekContext {
        var c = MRPlanWeekContext(phase: "늘리기", longRunKm: 16, weeklyKm: 40, easyRuns: point == nil ? 3 : 2,
                                  racePaceSecPerKm: nil, racePaceSegmentMin: nil, daysToRace: 60, easyKm: 8.4)
        c.point = point
        return c
    }

    @Test func planEasyDaySuggestsLongRunOnHabitualDay() throws {
        // 테이퍼 주처럼 계획 때문에 이지인 날 — 습관 롱런 요일(토)이면 롱런을 권한다(2026-11-02).
        // 몸 상태로 이지인 날(planEasy false)은 그대로 이지.
        let tempo = run(0, km: 5)   // 월요일 강도 훈련(템포)
        let runs = (history() + [tempo]).sorted { $0.start < $1.start }
        let types: [Date: WorkoutType] = [tempo.start: .tempo]
        let s = try #require(mrSessionSuggestion(level: .easy, plan: plan(point: pt), runs: runs, asOf: day(5),
                                                 pointTypes: types, planEasy: true))
        #expect(s.isLongRun)
        #expect(s.session == "롱런 16km")
        let body = try #require(mrSessionSuggestion(level: .easy, plan: plan(point: pt), runs: runs, asOf: day(5), pointTypes: types))
        #expect(!body.isLongRun)
    }

    @Test func goOnThursdaySuggestsPoint() throws {
        let s = try #require(mrSessionSuggestion(level: .go, plan: plan(point: pt), runs: history(), asOf: day(3)))
        #expect(s.isPoint)
        #expect(s.session == "인터벌 1km × 4회 5'05\"")
        #expect(s.progress.contains("강도 훈련 아직"))
    }

    @Test func dayBeforeHabitualLongRunIsEasyNotPoint() throws {
        // 금요일(4) — 내일이 습관 롱런 요일(토)
        let s = try #require(mrSessionSuggestion(level: .go, plan: plan(point: pt), runs: history(), asOf: day(4)))
        #expect(!s.isPoint)
        #expect(!s.isLongRun)
    }

    @Test func habitualDayStillLongRunFirst() throws {
        let s = try #require(mrSessionSuggestion(level: .go, plan: plan(point: pt), runs: history(), asOf: day(5)))
        #expect(s.isLongRun)
        // 토요일 남은 날 2 → 포인트는 건너뛰어도 된다
        #expect(s.progress.contains("건너뛰어도"))
    }

    @Test func pointDoneThisWeekCountsAndEasyCountExcludesIt() throws {
        let hardTue = run(1, km: 8)
        let runs = history() + [hardTue]
        let s = try #require(mrSessionSuggestion(level: .go, plan: plan(point: pt), runs: runs, asOf: day(3),
                                                 hardStarts: [hardTue.start]))
        #expect(!s.isPoint)
        #expect(s.progress.contains("강도 훈련 완료"))
        #expect(s.progress.contains("이지 0번 · 계획 2번"))
    }

    @Test func noPointInPlanKeepsOldProgress() throws {
        let s = try #require(mrSessionSuggestion(level: .go, plan: plan(point: nil), runs: history(), asOf: day(3)))
        #expect(!s.isPoint)
        #expect(!s.progress.contains("강도 훈련"))
    }

    @Test func readinessLineForPointSessionKeepsVerdictHead() {
        var r = MRReadiness(level: .go, reasons: [], hrvPending: false)
        r.session = "인터벌 1km × 4회 5'05\""
        r.sessionIsPoint = true
        #expect(r.line == "오늘은 강도 OK · 인터벌 1km × 4회 5'05\"")
    }
}
