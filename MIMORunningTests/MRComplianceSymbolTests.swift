import XCTest
@testable import MIMORunning

final class MRComplianceSymbolTests: XCTestCase {

    // 고정 월요일 날짜 (테스트용)
    private let monday: Date = {
        var comps = DateComponents(year: 2025, month: 1, day: 6) // 2025-01-06 월요일
        return Calendar.current.date(from: comps)!
    }()

    private func plan(longRunKm: Double, weeklyKm: Double) -> MRPlanWeekSummary {
        MRPlanWeekSummary(idx: 1, monday: monday, phase: "구축",
                          longRunKm: longRunKm, weeklyKm: weeklyKm)
    }

    func testComplianceSymbols() {
        // 기준: 계획 롱런 18km / 주간 40km
        let p = plan(longRunKm: 18, weeklyKm: 40)

        // (19, 42) → ● 둘 다 충족. 19 <= 18*1.10=19.8 이므로 ▲ 아님
        XCTAssertEqual(weekSymbol(plan: p, actualLong: 19, actualWeekly: 42), "●")

        // (19, 35) → ◐ 롱런만 충족
        XCTAssertEqual(weekSymbol(plan: p, actualLong: 19, actualWeekly: 35), "◐")

        // (15, 35) → ○ 둘 다 미달
        XCTAssertEqual(weekSymbol(plan: p, actualLong: 15, actualWeekly: 35), "○")

        // (21, 42) → ▲ 롱런이 계획+10% 초과 (21 > 18*1.10=19.8)
        XCTAssertEqual(weekSymbol(plan: p, actualLong: 21, actualWeekly: 42), "▲")

        // 회복주: 계획 롱런 11 / 주간 26, 실제 (15, 38) → ▲ (15 > 11*1.10=12.1)
        let recovery = plan(longRunKm: 11, weeklyKm: 26)
        XCTAssertEqual(weekSymbol(plan: recovery, actualLong: 15, actualWeekly: 38), "▲")
    }

    func testSymbolBoundary() {
        // 정확히 +10% 경계: 18 * 1.10 = 19.8 → 19.8은 ▲ 아님 (strictly greater than)
        let p = plan(longRunKm: 18, weeklyKm: 40)
        XCTAssertEqual(weekSymbol(plan: p, actualLong: 19.8, actualWeekly: 40), "●")
        // 19.81 → ▲
        XCTAssertEqual(weekSymbol(plan: p, actualLong: 19.81, actualWeekly: 40), "▲")
    }

    func testSymbolWithWeeklyOnlyMet() {
        // 롱런 미달, 주간만 충족 → ◐
        let p = plan(longRunKm: 18, weeklyKm: 40)
        XCTAssertEqual(weekSymbol(plan: p, actualLong: 15, actualWeekly: 42), "◐")
    }
}
