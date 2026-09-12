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
}
