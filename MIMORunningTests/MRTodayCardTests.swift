import XCTest
@testable import MIMORunning

/// 홈 오늘 카드의 러닝 기록 줄이 언제 보이는가 — 달력이 아니라 **러닝 종료 후 12시간**.
///
/// 자정 기준이면 밤 11시에 뛰고 자정 넘어 열었을 때 방금 뛴 게 벌써 없었다.
/// 다음 러닝까지 두면 사흘 쉰 날에도 사흘 전 기록이 큰 글씨로 남아 아래 목록과 중복됐다.
final class MRTodayCardTests: XCTestCase {

    private func run(start: Date, minutes: Double = 40, km: Double = 6.07) -> MRWorkout {
        MRWorkout(start: start, durationMin: minutes, distanceKm: km, hrAvg: 134, hrMax: 150,
                  tempC: nil, humidity: nil, indoor: false, isInterval: false)
    }

    private func card(runs: [MRWorkout], asOf: Date) -> MRTodayCard? {
        mrTodayCard(runs: runs, phys: MRPhysiology(), plans: [], raceDayCardVisible: false,
                    advice: [], asOf: asOf)
    }

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    // MARK: - 거리 행 (이번 주 · 이번 달 · 올해 · 누적)

    private func L(_ ko: String, _ en: String) -> String { AppLanguage.shared.s(ko, en) }

    // 2026-09-15(화) 기준: 이번 주 = 9/14(월)~, 이번 달 = 9월, 올해 = 2026
    func testDistanceCellsSumEachPeriod() throws {
        let runs = [
            run(start: date("2025-12-30 07:00"), km: 10),   // 작년 → 누적만
            run(start: date("2026-08-20 07:00"), km: 8),    // 올해, 지난달
            run(start: date("2026-09-10 07:00"), km: 6),    // 이번 달, 지난주
            run(start: date("2026-09-14 07:00"), km: 5),    // 이번 주(월)
        ]
        let c = try XCTUnwrap(card(runs: runs, asOf: date("2026-09-15 09:00")))
        XCTAssertEqual(c.distanceCells.map(\.km), [5, 11, 19, 29])
        XCTAssertEqual(c.distanceCells.map(\.label), [L("이번 주", "This week"), L("이번 달", "This month"), L("올해", "This year"), L("누적", "Total")])
    }

    // 월요일 아침, 이번 주 러닝 전 → "이번 주" 칸이 없다 (0km는 찌른다). 누적은 항상 있다.
    func testZeroWeekCellIsOmitted() throws {
        let runs = [run(start: date("2026-09-10 07:00"), km: 6)]
        let c = try XCTUnwrap(card(runs: runs, asOf: date("2026-09-14 08:00")))
        XCTAssertEqual(c.distanceCells.map(\.label), [L("이번 달", "This month"), L("올해", "This year"), L("누적", "Total")])
        XCTAssertEqual(c.distanceCells.last?.km, 6)
    }

    // 1월 1일 아침, 작년 기록만 → 누적 하나만
    func testNewYearMorningShowsOnlyTotal() throws {
        let runs = [run(start: date("2025-12-28 07:00"), km: 12)]
        let c = try XCTUnwrap(card(runs: runs, asOf: date("2026-01-01 08:00")))
        XCTAssertEqual(c.distanceCells.map(\.label), [L("누적", "Total")])
        XCTAssertEqual(c.distanceCells.first?.km, 12)
    }

    // 주 경계는 ISO(월요일 시작) — 일요일 러닝은 다음 주(월)에는 "이번 주"가 아니다
    func testWeekStartsOnMonday() throws {
        let runs = [run(start: date("2026-09-13 07:00"), km: 7)]   // 일요일
        let c = try XCTUnwrap(card(runs: runs, asOf: date("2026-09-14 20:00")))   // 월요일 저녁
        XCTAssertFalse(c.distanceCells.contains { $0.label == L("이번 주", "This week") })
    }

    // 오후 5시 러닝(40분, 5:40 종료) → 다음 날 새벽 5시 전까지는 보인다
    func testEveningRunStillShownEarlyNextMorning() {
        let r = run(start: date("2026-09-11 17:00"))
        XCTAssertNotNil(card(runs: [r], asOf: date("2026-09-12 04:00"))?.sessionLine,
                        "자정을 넘겨도 종료 후 12시간 안이면 보여야 한다")
        XCTAssertNil(card(runs: [r], asOf: date("2026-09-12 06:00"))?.sessionLine,
                     "종료 후 12시간이 지나면 사라져야 한다")
    }

    // 밤 11시 러닝 → 자정 직후에도, 다음 날 오전에도 보인다 (달력 기준이었으면 자정에 사라졌다)
    func testLateNightRunSurvivesMidnight() {
        let r = run(start: date("2026-09-11 23:00"))
        XCTAssertNotNil(card(runs: [r], asOf: date("2026-09-12 00:10"))?.sessionLine)
        XCTAssertNotNil(card(runs: [r], asOf: date("2026-09-12 10:00"))?.sessionLine)
        XCTAssertNil(card(runs: [r], asOf: date("2026-09-12 12:00"))?.sessionLine)
    }

    // 사흘 쉬면 사라진다 — 다음 러닝까지 남기지 않는다
    func testOldRunIsNotCarriedUntilNextRun() {
        let r = run(start: date("2026-09-08 17:00"))
        XCTAssertNil(card(runs: [r], asOf: date("2026-09-11 09:00"))?.sessionLine)
    }

    // 12시간 안에 다시 뛰면 가장 최근 러닝으로 교체된다
    func testSecondRunWithinWindowReplacesTheLine() throws {
        let morning = run(start: date("2026-09-11 07:00"), minutes: 30, km: 5.0)
        let evening = run(start: date("2026-09-11 18:00"), minutes: 40, km: 6.07)
        let line = try XCTUnwrap(card(runs: [morning, evening], asOf: date("2026-09-11 19:00"))?.sessionLine)
        XCTAssertTrue(line.hasPrefix("6.07km"), "저녁 러닝이 줄을 차지해야 한다: \(line)")
        XCTAssertFalse(line.contains("5.00km"))
    }

    // 한 시간 넘는 러닝은 시:분:초 — 100분을 "100:41"로 적지 않는다 (아래 목록은 "1:40:41")
    func testDurationOverAnHourUsesHoursField() throws {
        let r = run(start: date("2026-09-12 13:00"), minutes: 100 + 41.0 / 60, km: 16.03)
        let line = try XCTUnwrap(card(runs: [r], asOf: date("2026-09-12 15:00"))?.sessionLine)
        XCTAssertTrue(line.contains("1:40:41"), line)
        XCTAssertFalse(line.contains("100:41"), line)
    }

    // 한 시간 미만은 분:초 그대로
    func testDurationUnderAnHourStaysMinutesSeconds() throws {
        let r = run(start: date("2026-09-12 13:00"), minutes: 39 + 41.0 / 60)
        let line = try XCTUnwrap(card(runs: [r], asOf: date("2026-09-12 14:00"))?.sessionLine)
        XCTAssertTrue(line.contains("39:41"), line)
    }

    // 미래 시각의 러닝(시계 오류 등)은 "오늘"로 치지 않는다
    func testFutureRunIsNotShown() {
        let r = run(start: date("2026-09-12 09:00"))
        XCTAssertNil(card(runs: [r], asOf: date("2026-09-11 20:00"))?.sessionLine)
    }

    // MARK: - 아침 제안 줄

    /// HRV 밤 시계열과 심박 모델을 넘기면 연속 줄 아래 제안 줄이 채워진다. 오늘 뛴 날엔 nil.
    func testReadinessLineFilledInTheMorningAndNilAfterRunningToday() throws {
        let cal = Calendar.current
        let morning = date("2026-09-15 08:00")
        func d(_ off: Int) -> Date { cal.startOfDay(for: cal.date(byAdding: .day, value: off, to: morning)!) }
        // 만성 부하(−34…−7)가 4주 모두 자료가 있어야 급증으로 오판되지 않는다(9회만 있으면 acwr 1.33 > 1.3로 rest).
        let runs = [34, 32, 29, 27, 25, 22, 20, 18, 15, 13, 11, 8, 6, 3, 1].map { run(start: d(-$0).addingTimeInterval(7 * 3600)) }
        var nights: [(date: Date, value: Double)] = []
        for i in 0..<28 { nights.append((d(-34 + i), 30 + (i % 2 == 0 ? 1 : -1))) }
        for i in 0..<7 { nights.append((d(-6 + i), 37)) }

        let c = try XCTUnwrap(mrTodayCard(runs: runs, phys: MRPhysiology(), plans: [], raceDayCardVisible: false,
                                          advice: [], asOf: morning, heatHR: MRHeatHRModel(), hrvNights: nights, planPhase: nil))
        XCTAssertEqual(c.readinessLevel, .go)
        XCTAssertEqual(c.readinessLine, L("오늘은 강도 OK · HRV 좋음", "Today: hard is OK · HRV good"))

        let ranToday = runs + [run(start: date("2026-09-15 07:00"))]
        let c2 = try XCTUnwrap(mrTodayCard(runs: ranToday, phys: MRPhysiology(), plans: [], raceDayCardVisible: false,
                                           advice: [], asOf: date("2026-09-15 09:00"), heatHR: MRHeatHRModel(), hrvNights: nights, planPhase: nil))
        XCTAssertNil(c2.readinessLine)
    }
}
