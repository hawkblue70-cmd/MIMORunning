import Testing
import Foundation
@testable import MIMORunning

/// 러닝 중간 광학 심박 튐(`hrMidRunSpikeRanges`·`hrMidRunSpikeCleaned`)
@Suite struct HRMidRunSpikeTests {
    /// 5초 간격 표본 — (구간 초, 시작 bpm, 끝 bpm) 선형으로 이어 붙인다
    private func series(_ segs: [(seconds: Double, from: Int, to: Int)]) -> [(offset: TimeInterval, bpm: Int)] {
        var out: [(offset: TimeInterval, bpm: Int)] = []
        var t: TimeInterval = 0
        for seg in segs {
            let n = max(1, Int(seg.seconds / 5))
            for k in 0..<n {
                let f = Double(k) / Double(n)
                out.append((offset: t, bpm: Int((Double(seg.from) + f * Double(seg.to - seg.from)).rounded())))
                t += 5
            }
        }
        return out
    }

    @Test func abruptMidRunJumpIsCleaned() {
        // 72분 이지런: 140 유지, 40분쯤 3분 동안 한 표본 만에 175로 튐 (다른 러너 6km 구간)
        let s = series([(2400, 140, 140), (180, 175, 175), (1740, 140, 140)])
        #expect(hasHRMidRunSpike(s))
        let cleaned = hrMidRunSpikeCleaned(s)
        #expect((cleaned.map(\.bpm).max() ?? 0) <= 145)
        #expect(cleaned.count == s.count)
    }

    @Test func gradualHillRiseIsKept() {
        // 오르막: 2분에 걸쳐 140→162로 오르고 3분 머문 뒤 2분에 걸쳐 내려옴 — 생리적 반응
        let s = series([(2400, 140, 140), (120, 140, 162), (180, 162, 162), (120, 162, 140), (1500, 140, 140)])
        #expect(!hasHRMidRunSpike(s))
        #expect(hrMidRunSpikeCleaned(s).map(\.bpm) == s.map(\.bpm))
    }

    @Test func repeatedEffortsAreKept() {
        // 인터벌 8회: 한 표본 만에 오르더라도 3개 이상이면 반복 노력으로 보고 손대지 않는다
        var segs: [(seconds: Double, from: Int, to: Int)] = [(600, 130, 130)]
        for _ in 0..<8 { segs += [(120, 168, 168), (180, 138, 138)] }
        segs.append((600, 130, 130))
        #expect(!hasHRMidRunSpike(series(segs)))
    }

    @Test func shortRunIsNotJudged() {
        #expect(!hasHRMidRunSpike(series([(240, 140, 140), (60, 175, 175), (240, 140, 140)])))
    }
}
