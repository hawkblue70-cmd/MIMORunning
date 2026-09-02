import XCTest
@testable import MIMORunning

final class MRAdviceLogTests: XCTestCase {

    // nil(미기록) = 최초 표시 허용.
    // 이게 실패하면 "기록 없는 사용자가 영원히 못 본다"는 버그가 재발한 것이다.
    func testCanShowAllowsFirstTime() {
        let log = MRAdviceLog()
        let (ok, _) = log.canShow("new.key", minDays: 28)
        XCTAssertTrue(ok)
    }

    func testCanShowBlocksWithinMinDays() {
        var log = MRAdviceLog()
        let now = Date()
        log.markShown("test.key", asOf: now)
        let tenDaysLater = now.addingTimeInterval(86400 * 10)
        let (ok, _) = log.canShow("test.key", minDays: 28, asOf: tenDaysLater)
        XCTAssertFalse(ok)
    }

    func testCanShowAllowsAfterMinDays() {
        var log = MRAdviceLog()
        let now = Date()
        log.markShown("test.key", asOf: now)
        let twentyNineDaysLater = now.addingTimeInterval(86400 * 29)
        let (ok, _) = log.canShow("test.key", minDays: 28, asOf: twentyNineDaysLater)
        XCTAssertTrue(ok)
    }

    func testCanShowExactlyAtMinDays() {
        var log = MRAdviceLog()
        let now = Date()
        log.markShown("test.key", asOf: now)
        let cal = Calendar.current
        let exactDay = cal.date(byAdding: .day, value: 28, to: now)!
        let (ok, _) = log.canShow("test.key", minDays: 28, asOf: exactDay)
        XCTAssertTrue(ok)
    }
}
