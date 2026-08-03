import XCTest
@testable import MIMORunning

final class MRFormulasTests: XCTestCase {

    func testVO2Cost() {
        XCTAssertEqual(vo2Cost(178.6), 31.2687, accuracy: 0.001)
    }

    func testPctMax() {
        XCTAssertEqual(pctMax(55.98), 0.892649, accuracy: 0.000001)
    }

    func testVDOT() {
        XCTAssertEqual(vdot(distanceM: 10000, timeMin: 55.98),
                       35.0377, accuracy: 0.001)
    }

    func testPaceForVDOT() {
        XCTAssertEqual(paceForVDOT(40, 0.67), 379.67, accuracy: 0.01)
    }

    func testFormat() {
        XCTAssertEqual(mrFormatHMS(295.95), "4:55:57")
        XCTAssertEqual(mrFormatHMS(117.883), "1:57:53")
        XCTAssertEqual(mrFormatPace(379.67), "6'19\"")  // 버림(Int) + '/" 기호
    }
}
