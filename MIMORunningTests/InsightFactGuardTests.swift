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

    // 실제로 났던 일 2 — 예시의 자리표시 ○를 베끼고 진짜 숫자 6'16"을 떨어뜨림
    func testPlaceholderGlyphIsRejected() {
        XCTAssertFalse(InsightFactGuard.numbersAreGrounded(
            output: "최근 같은 거리 중 가장 빠른 페이스 ○'○",
            source: "최근 동일 거리 중 가장 빠른 페이스 6'16\""))
    }

    // 원문의 숫자를 빼먹어도 안 된다 — 부연의 존재 이유가 그 숫자다
    func testDroppingSourceNumberIsRejected() {
        XCTAssertFalse(InsightFactGuard.numbersAreGrounded(
            output: "이 거리에서 가장 빨랐어요",
            source: "최근 동일 거리 중 가장 빠른 페이스 6'16\""))
    }

    // 원문에 숫자가 없으면 결과에도 없어야 통과
    func testNoNumbersOnBothSidesPasses() {
        XCTAssertTrue(InsightFactGuard.numbersAreGrounded(
            output: "꾸준히 이어지는 달리기예요",
            source: "연속 달리기 중"))
    }

    func testDigitRunsSplitOnSeparators() {
        XCTAssertEqual(InsightFactGuard.digitRuns(in: "1:40:41 · 12.3km · 178bpm"),
                       ["1", "40", "41", "12", "3", "178"])
    }

    /// 말투 예시를 베껴 원문에 없는 "이번 달 가장 긴 거리"를 주장하면 막는다(숫자는 원문 그대로라 숫자 검사는 통과).
    func testClaimCopiedFromStyleExampleIsRejected() {
        let source = "임계 페이스 근처를 꾸준히 지켰어요, 7.20 km"
        let output = "이번 달 가장 긴 거리를 달렸어요, 7.20 km"
        XCTAssertTrue(InsightFactGuard.numbersAreGrounded(output: output, source: source))
        XCTAssertFalse(InsightFactGuard.claimsAreGrounded(output: output, source: source))
    }

    /// 원문이 실제로 같은 주장을 하면 통과한다.
    func testClaimPresentInSourceIsAllowed() {
        let source = "이번 달 가장 긴 거리예요 · 16.0 km"
        let output = "이번 달 가장 긴 거리를 달렸어요, 16.0 km"
        XCTAssertTrue(InsightFactGuard.claimsAreGrounded(output: output, source: source))
    }
}
