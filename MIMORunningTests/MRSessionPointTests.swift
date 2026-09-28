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

    @Test func goOnThursdaySuggestsPoint() throws {
        let s = try #require(mrSessionSuggestion(level: .go, plan: plan(point: pt), runs: history(), asOf: day(3)))
        #expect(s.isPoint)
        #expect(s.session == "포인트 속도 1km × 4회 5'05\"")
        #expect(s.progress.contains("포인트 아직"))
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
        #expect(s.progress.contains("포인트 완료"))
        #expect(s.progress.contains("이지 0/2회"))
    }

    @Test func noPointInPlanKeepsOldProgress() throws {
        let s = try #require(mrSessionSuggestion(level: .go, plan: plan(point: nil), runs: history(), asOf: day(3)))
        #expect(!s.isPoint)
        #expect(!s.progress.contains("포인트"))
    }

    @Test func readinessLineForPointSessionKeepsVerdictHead() {
        var r = MRReadiness(level: .go, reasons: [], hrvPending: false)
        r.session = "포인트 속도 1km × 4회 5'05\""
        r.sessionIsPoint = true
        #expect(r.line == "오늘은 강도 OK · 포인트 속도 1km × 4회 5'05\"")
    }
}
