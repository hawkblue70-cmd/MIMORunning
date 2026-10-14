import XCTest
@testable import MIMORunning

final class TabDigestTests: XCTestCase {
    typealias S = TabDigest.Signal
    func testProblemsCappedAtTwoAndGoodSuppressed() {
        let b = TabDigest.make([
            S(tab: .rhythm, kind: .problem, priority: 3, family: .unique, text: "c", tone: .caution),
            S(tab: .rhythm, kind: .problem, priority: 1, family: .unique, text: "a", tone: .caution, direction: "da"),
            S(tab: .rhythm, kind: .problem, priority: 2, family: .unique, text: "b", tone: .caution),
            S(tab: .rhythm, kind: .good, priority: 1, family: .unique, text: "g", tone: .good),
        ])
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b[0].statements.map(\.text), ["a", "b"])
        XCTAssertEqual(b[0].direction, "da")
    }
    func testGoodOnlyTabShowsOneLine() {
        let b = TabDigest.make([
            S(tab: .form, kind: .good, priority: 2, family: .unique, text: "g2", tone: .good),
            S(tab: .form, kind: .good, priority: 1, family: .unique, text: "g1", tone: .good),
        ], defaults: .init(directions: [.form: "df"]))
        XCTAssertEqual(b.first?.statements.map(\.text), ["g1"])
        XCTAssertEqual(b.first?.direction, "df")
    }
    func testEmptyTabsAreOmitted() {
        let b = TabDigest.make([S(tab: .rhythm, kind: .good, priority: 1, family: .unique, text: "g", tone: .good)],
                               defaults: .init(directions: [.form: "df", .performance: "dp"]))
        XCTAssertEqual(b.map(\.tab), [.rhythm])
    }
    func testLateHRFamilyOwnedByPerformanceWhenPresent() {
        let b = TabDigest.make([
            S(tab: .rhythm, kind: .problem, priority: 4, family: .lateHR, text: "후반에 심박이 올랐습니다", tone: .caution),
            S(tab: .performance, kind: .problem, priority: 3, family: .lateHR, text: "디커플링", tone: .caution),
        ])
        XCTAssertEqual(b.map(\.tab), [.performance])
    }
    func testLateHRFallsBackToRhythm() {
        let b = TabDigest.make([S(tab: .rhythm, kind: .problem, priority: 4, family: .lateHR, text: "r", tone: .caution)])
        XCTAssertEqual(b.map(\.tab), [.rhythm])
    }
    func testDuplicateDirectionDroppedInLaterBlock() {
        let b = TabDigest.make([
            S(tab: .rhythm, kind: .problem, priority: 1, family: .unique, text: "r", tone: .caution, direction: "쉬세요"),
            S(tab: .performance, kind: .problem, priority: 2, family: .unique, text: "p", tone: .caution, direction: "쉬세요"),
        ])
        XCTAssertEqual(b[0].direction, "쉬세요")
        XCTAssertNil(b[1].direction)
    }
    func testExtraAppendedAfterStatements() {
        let b = TabDigest.make([
            S(tab: .form, kind: .good, priority: 1, family: .unique, text: "held", tone: .good),
            S(tab: .form, kind: .extra, priority: 1, family: .unique, text: "trend"),
        ])
        XCTAssertEqual(b[0].statements.map(\.text), ["held", "trend"])
    }
    func testBlocksInTabOrder() {
        let b = TabDigest.make([
            S(tab: .performance, kind: .good, priority: 1, family: .unique, text: "p", tone: .good),
            S(tab: .rhythm, kind: .good, priority: 1, family: .unique, text: "r", tone: .good),
            S(tab: .form, kind: .good, priority: 1, family: .unique, text: "f", tone: .good),
        ])
        XCTAssertEqual(b.map(\.tab), [.rhythm, .form, .performance])
    }
    func testMakePrefersShortOverText() {
        let b = TabDigest.make([
            S(tab: .rhythm, kind: .problem, priority: 1, family: .unique, text: "긴 카드 문장입니다", tone: .caution, short: "짧은 개조식"),
            S(tab: .rhythm, kind: .problem, priority: 2, family: .unique, text: "short 없음", tone: .caution),
        ])
        XCTAssertEqual(b[0].statements.map(\.text), ["짧은 개조식", "short 없음"])
    }
}
