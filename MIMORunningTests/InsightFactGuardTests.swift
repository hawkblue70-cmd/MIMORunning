import XCTest
@testable import MIMORunning

/// AI가 다시 쓴 인사이트 부연에 원문에 없는 숫자가 섞이면 걸러야 한다.
final class InsightFactGuardTests: XCTestCase {

    // 실제로 났던 일 — 16km 러닝의 "동일 거리"를 예시의 "5km"로 베껴 씀
    func testCopiedExampleDistanceIsRejected() {
        XCTAssertFalse(InsightFactGuard.numbersAreGrounded(
            output: "최근 5km 중 가장 빠른 페이스 6'16",
            source: "최근 동일 거리 중 가장 빠른 페이스 6'16\""))
    }

    func testRewordingWithSameNumbersPasses() {
        XCTAssertTrue(InsightFactGuard.numbersAreGrounded(
            output: "같은 거리에서 가장 빠른 6'16\"",
            source: "최근 동일 거리 중 가장 빠른 페이스 6'16\""))
    }

    func testNoNumbersAtAllPasses() {
        XCTAssertTrue(InsightFactGuard.numbersAreGrounded(
            output: "이 거리에서 가장 빨랐어요",
            source: "최근 동일 거리 중 가장 빠른 페이스 6'16\""))
    }

    func testDigitRunsSplitOnSeparators() {
        XCTAssertEqual(InsightFactGuard.digitRuns(in: "1:40:41 · 12.3km · 178bpm"),
                       ["1", "40", "41", "12", "3", "178"])
    }
}
