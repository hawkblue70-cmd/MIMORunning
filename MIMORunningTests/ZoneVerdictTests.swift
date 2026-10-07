import Testing
import Foundation
@testable import MIMORunning

/// 심박 판정 존 — Zone 4+5 합이 가장 큰 존 이상(35%↑)이면 고강도. 존이 고르게 흩어진 빌드업이
/// "템포 구간에 머물렀다"로 읽히던 결함(2026-10-08) 회귀 방지.
@Suite("심박 판정 존 · Zone 4+5 합산", .korean)
struct ZoneVerdictTests {

    @Test("Z3 25% · Z4 22% · Z5 22% → 고강도(Zone 4·5 44%)")
    func spreadBuildUpIsHigh() {
        let v = FormNarrative.verdictZone(fractions: [1: 0.07, 2: 0.24, 3: 0.25, 4: 0.22, 5: 0.22])
        #expect(v?.zone == 4)
        #expect(v?.isHighCombined == true)
        #expect(Int(((v?.frac ?? 0) * 100).rounded()) == 44)
    }

    @Test("Z3 50% · Z4 20% · Z5 5% → 템포(Zone 3)")
    func tempoStaysTempo() {
        let v = FormNarrative.verdictZone(fractions: [2: 0.25, 3: 0.50, 4: 0.20, 5: 0.05])
        #expect(v?.zone == 3)
        #expect(v?.isHighCombined == false)
    }

    @Test("Z4+5 합이 커도 35% 미만이면 합산하지 않음")
    func smallHighShareIgnored() {
        let v = FormNarrative.verdictZone(fractions: [1: 0.30, 2: 0.20, 3: 0.18, 4: 0.17, 5: 0.15])
        #expect(v?.zone == 1)
        #expect(v?.isHighCombined == false)
    }

    @Test("Z4가 이미 최다면 그대로 Zone 4")
    func dominantZ4Unchanged() {
        let v = FormNarrative.verdictZone(fractions: [3: 0.20, 4: 0.60, 5: 0.20])
        #expect(v?.zone == 4)
        #expect(v?.isHighCombined == false)
    }

    @Test("총평 심박 줄 — 흩어진 빌드업은 '의도한 고강도', 근거는 Zone 4·5")
    func summaryLineUsesCombinedHigh() {
        var i = RunSummaryInput()
        i.zoneFractions = [1: 0.07, 2: 0.24, 3: 0.25, 4: 0.22, 5: 0.22]
        i.workoutType = .buildUp
        let line = RunSummary.lines(i).first { $0.axis == "심박" }
        #expect(line?.state == "의도한 고강도")
        #expect(line?.evidence?.hasPrefix("Zone 4·5 44%") == true)
    }
}
