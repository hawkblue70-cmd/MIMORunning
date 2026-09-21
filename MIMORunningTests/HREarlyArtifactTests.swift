import Testing
import Foundation
@testable import MIMORunning

/// 출발 직후 광학 심박 오독 구간 검출(`hrEarlyArtifactCount`)
@Suite struct HREarlyArtifactTests {
    /// 10초 간격 표본 — 구간별 bpm을 받아 시계열을 만든다
    private func series(_ segments: [(seconds: Double, bpm: Int)]) -> [(offset: TimeInterval, bpm: Int)] {
        var out: [(offset: TimeInterval, bpm: Int)] = []
        var t: TimeInterval = 0
        for seg in segments {
            let n = Int(seg.seconds / 10)
            for _ in 0..<n { out.append((offset: t, bpm: seg.bpm)); t += 10 }
        }
        return out
    }

    @Test func spikeAtStartThatNeverReturnsIsArtifact() {
        // 48분 러닝: 첫 5분 158, 이후 137~142 (다른 러너의 7km 이지런 모양)
        let s = series([(300, 158), (1200, 137), (1200, 140), (180, 142)])
        let n = hrEarlyArtifactCount(s)
        #expect(n != nil)
        #expect((n ?? 0) >= 25 && (n ?? 0) <= 30)   // 첫 10% ≈ 288초 → 표본 28~29개
    }

    @Test func buildUpStartingLowIsNotArtifact() {
        let s = series([(600, 130), (1200, 145), (1200, 158)])
        #expect(hrEarlyArtifactCount(s) == nil)
    }

    @Test func spikeFollowedByLaterReturnToThatLevelIsNotArtifact() {
        // 초반 165 → 140으로 떨어졌지만 후반에 다시 163까지 올라오면 오독이 아니라 실제 강도 변화
        let s = series([(300, 165), (1200, 140), (900, 163)])
        #expect(hrEarlyArtifactCount(s) == nil)
    }

    @Test func shortRunIsNotJudged() {
        let s = series([(120, 160), (300, 135)])
        #expect(hrEarlyArtifactCount(s) == nil)
    }
}
