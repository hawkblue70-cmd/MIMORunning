import Testing
import Foundation
@testable import MIMORunning

/// 전반·후반 순 고도 변화 — 심박 캡션("후반 오르막")·폼 전후반 비교 생략이 같이 쓴다.
@Suite struct HalvesNetClimbTests {
    private func profile(_ alts: [Double], step: Double = 0.1) -> [(x: Double, altitude: Double)] {
        alts.enumerated().map { (x: Double($0.offset) * step, altitude: $0.element) }
    }

    @Test func downThenUpCourseSplitsIntoOppositeHalves() throws {
        // 5km: 앞 2.5km 60m 내려가고 뒤 2.5km 60m 올라옴 (다른 러너의 V자 코스)
        let down = (0...25).map { 100 - Double($0) * 2.4 }
        let up = (1...25).map { 40 + Double($0) * 2.4 }
        let c = try #require(GradeAdjustedPace.halvesNetClimb(profile(down + up)))
        #expect(c.first < -40)
        #expect(c.second > 40)
        #expect(c.second - c.first >= GradeAdjustedPace.halvesClimbGapM)
    }

    @Test func flatTrackNoiseIsNotAHill() {
        // 평지 트랙 GPS 고도 흔들림(±3m) — 순 변화 10m 미만이면 nil
        let noisy = (0...50).map { 30 + (($0 % 4 < 2) ? 3.0 : -3.0) }
        #expect(GradeAdjustedPace.halvesNetClimb(profile(noisy)) == nil)
    }

    @Test func steadyClimbHasBalancedHalves() throws {
        // 처음부터 끝까지 같은 경사로 40m 오름 — 두 반의 차이가 작아 비교를 막지 않는다
        let climb = (0...50).map { Double($0) * 0.8 }
        let c = try #require(GradeAdjustedPace.halvesNetClimb(profile(climb)))
        #expect(abs(c.second - c.first) < GradeAdjustedPace.halvesClimbGapM)
    }
}
