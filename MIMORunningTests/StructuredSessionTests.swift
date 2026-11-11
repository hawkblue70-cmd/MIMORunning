import Testing
import Foundation
@testable import MIMORunning

/// 몸 풀기 → 본 구간 → 마무리 구성 인식(2026-11-11 사용자 러닝: 몸 풀기 2km · 하프 대회 페이스 2km · 마무리 1km)
@Suite struct StructuredSessionTests {
    private func split(_ id: Int, pace: Double, hr: Int? = 140, m: Double = 1000) -> SplitData {
        SplitData(id: id, distanceM: m, duration: pace * m / 1000, avgHeartRate: hr, avgCadence: nil, avgPower: nil,
                  avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil)
    }

    @Test func warmupRacePaceCooldownIsRecognised() throws {
        // 6'21" · 6'00" · 5'22" · 5'24" · 6'42"(1.03km)
        let s = [split(1, pace: 381, hr: 128), split(2, pace: 360, hr: 140), split(3, pace: 322, hr: 152),
                 split(4, pace: 324, hr: 156), split(5, pace: 402, hr: 138, m: 1030)]
        let x = try #require(MRStructuredSession.detect(s))
        #expect(x.main.map(\.id) == [3, 4])          // 6'00" km는 본 구간에 넣지 않는다(안쪽 차 20초 초과)
        #expect(x.warmup.map(\.id) == [1, 2])
        #expect(x.cooldown.map(\.id) == [5])
        #expect(x.mainHR == 154)
        #expect(MRStructuredSession.splitsWithoutCooldown(s).map(\.id) == [1, 2, 3, 4])
    }

    @Test func evenRunOrBuildUpIsNotStructured() {
        // 고른 러닝
        #expect(MRStructuredSession.detect((1...6).map { split($0, pace: 370) }) == nil)
        // 빌드업(마무리 없음) — 빌드업 판정이 맡는다
        #expect(MRStructuredSession.detect([split(1, pace: 390), split(2, pace: 380), split(3, pace: 340), split(4, pace: 335)]) == nil)
        // 빠른 km가 하나뿐
        #expect(MRStructuredSession.detect([split(1, pace: 390), split(2, pace: 330), split(3, pace: 390), split(4, pace: 395)]) == nil)
    }
}
