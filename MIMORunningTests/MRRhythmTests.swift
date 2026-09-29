import Testing
import Foundation
@testable import MIMORunning

@Suite("아침 제안 — 대회 없을 때 2주 리듬", .korean)
struct MRRhythmTests {

    private let cal = Calendar.current
    /// 2026-10-12(월) 주. 오프셋 0=월 … 6=일.
    private func day(_ offset: Int, hour: Int = 8) -> Date {
        let mon = cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        return cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: mon)!)!
    }
    private func run(_ offset: Int, km: Double) -> MRWorkout {
        MRWorkout(start: day(offset, hour: 7), durationMin: km * 6, distanceKm: km, hrAvg: 140, hrMax: 170,
                  tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }
    /// 지난 8주 화·목 8km, 토 16km(습관 토요일). `skipLastSaturday`면 지난 토요일(−2) 롱런을 뺀다.
    private func history(skipLastSaturday: Bool = false) -> [MRWorkout] {
        (1...8).flatMap { w -> [MRWorkout] in
            let sat = run(-7 * w + 5, km: 16)
            let keepSat = !(skipLastSaturday && w == 1)
            return [run(-7 * w + 1, km: 8), run(-7 * w + 3, km: 8)] + (keepSat ? [sat] : [])
        }.sorted { $0.start < $1.start }
    }
    private func ctx(runs: Double = 4, types: [Date: WorkoutType] = [:], raceDaysAgo: Int? = nil) -> MRRhythmContext {
        var c = MRRhythmContext(runsPerWeek: runs, paces: mrPointPaces(halfEquivMin: 110), pointTypes: types)
        if let d = raceDaysAgo { c.recentRaceName = "춘천마라톤"; c.recentRaceDate = day(-d) }
        return c
    }

    @Test func usualLongRunIsMedianOfWeeklyLongest() {
        #expect(mrUsualLongRunKm(runs: history(), asOf: day(2)) == 16)
        let short = (1...4).flatMap { w in [run(-7 * w + 1, km: 5), run(-7 * w + 5, km: 7)] }
        #expect(mrUsualLongRunKm(runs: short, asOf: day(2)) == nil)   // 8km 미만
    }

    @Test func postRaceTwoWeeksIsEasyEvenWhenGo() throws {
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(raceDaysAgo: 5), runs: history(), hardStarts: [], asOf: day(2)))
        #expect(s.session == "이지런")
        #expect(!s.isPoint && !s.isLongRun)
        #expect(s.whyNote?.contains("회복") == true)
    }

    @Test func postRaceIsRecoveryAndRaceDayIsNot() throws {
        let s = try #require(mrRhythmSuggestion(level: .easy, ctx: ctx(raceDaysAgo: 3), runs: history(), hardStarts: [], asOf: day(2)))
        #expect(s.isRecovery)
        // 대회 당일(0일) 아침은 "0일 뒤"가 아니다 — 회복 규칙이 아니라 평소 리듬
        // ctx(raceDaysAgo:)는 월요일(day(0)) 기준 — 수요일(day(2)) 당일 대회는 −2
        let t = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(raceDaysAgo: -2), runs: history(), hardStarts: [], asOf: day(2)))
        #expect(!t.isRecovery)
        #expect(t.whyNote?.contains("0일 뒤") != true)
    }

    @Test func recoveryLineDoesNotSayRoomForIntensity() {
        var r = MRReadiness(level: .go, reasons: [], hrvPending: false)
        r.session = "이지런"
        r.sessionIsRecovery = true
        #expect(r.line == "오늘은 이지런 · 대회 뒤 회복")
    }

    @Test func longRunDueOnHabitualDay() throws {
        // 토요일(5), 지난 토요일 롱런 없음 → 마지막 롱런 14일 전
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(), runs: history(skipLastSaturday: true), hardStarts: [], asOf: day(5)))
        #expect(s.isLongRun)
        #expect(s.session == "롱런 16km")
    }

    @Test func pointDueRotatesAfterInterval() throws {
        // 지난주 화(−6)가 인터벌 → 수요일(2) 기준 8일 전, 주 4회 간격 7 → 다음은 템포
        let hist = history()
        let lastTue = try #require(hist.first { cal.isDate($0.start, inSameDayAs: day(-6)) })
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(types: [lastTue.start: .interval]), runs: hist,
                                                hardStarts: [], asOf: day(2)))
        #expect(s.isPoint)
        #expect(s.session?.hasPrefix("템포런") == true)
        #expect(s.whyNote?.contains("인터벌") == true)
    }

    @Test func noPointHistorySuggestsBuildUp() throws {
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(), runs: history(), hardStarts: [], asOf: day(2)))
        #expect(s.session?.hasPrefix("빌드업") == true)
    }

    @Test func dayBeforeHabitualLongRunNoPoint() throws {
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(), runs: history(), hardStarts: [], asOf: day(4)))
        #expect(!s.isPoint)
    }

    @Test func threeRunsPerWeekNeedsFourteenDays() throws {
        let hist = history()
        let lastTue = try #require(hist.first { cal.isDate($0.start, inSameDayAs: day(-6)) })
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(runs: 3, types: [lastTue.start: .interval]), runs: hist,
                                                hardStarts: [], asOf: day(2)))
        #expect(!s.isPoint)   // 8일 < 14일
    }

    @Test func twoRunsPerWeekNeverPoint() throws {
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(runs: 2), runs: history(), hardStarts: [], asOf: day(2)))
        #expect(!s.isPoint)
    }

    @Test func easyLevelHasNoSessionButShowsRhythm() throws {
        let s = try #require(mrRhythmSuggestion(level: .easy, ctx: ctx(), runs: history(), hardStarts: [], asOf: day(2)))
        #expect(s.session == nil)
        #expect(s.progress.contains("마지막 롱런 4일 전"))
    }
}
