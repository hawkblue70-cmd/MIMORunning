import Testing
import Foundation
@testable import MIMORunning

@Suite("EffortPaceTrend 같은 강도 페이스 추이")
struct EffortPaceTrendTests {
    /// MRFormShift memberwise init(metric·recentMean·baseMean·delta·mdc·weeksConsistent·r2).
    /// isReal = (|delta| > mdc || weeksConsistent ≥ 4) && isPractical(easyPace 키는 항상 true).
    private func shift(delta: Double, real: Bool) -> MRFormShift {
        MRFormShift(metric: EffortPaceTrend.metric, recentMean: 360 + delta, baseMean: 360, delta: delta,
                    mdc: real ? 1.0 : 999, weeksConsistent: real ? 4 : 0, r2: nil)
    }

    @Test func easyRangeIsTwoToFour() {
        #expect(EffortPaceTrend.easyRange.contains(2))
        #expect(EffortPaceTrend.easyRange.contains(4))
        #expect(!EffortPaceTrend.easyRange.contains(5))
        #expect(!EffortPaceTrend.easyRange.contains(1))
    }

    @Test func residualsPassThrough() {
        let d = Date()
        let r = EffortPaceTrend.residuals(points: [(date: d, value: 360), (date: d.addingTimeInterval(86400), value: 350)])
        #expect(r.count == 2)
        #expect(r[1].value == 350)
    }

    @Test func observationOnlyWhenFaster() {
        let faster = shift(delta: -12, real: true)
        #expect(faster.isReal)
        #expect(EffortPaceTrend.observation(shift: faster)?.text.contains("12") == true)
        #expect(EffortPaceTrend.observation(shift: shift(delta: 12, real: true)) == nil)
        #expect(EffortPaceTrend.observation(shift: shift(delta: -12, real: false)) == nil)
    }

    @Test func formatsPace() {
        #expect(TrendMetric.easyEffortPace.formattedValue(372) == "6'12\" /km")
        #expect(TrendMetric.easyEffortPace.lowerIsBetter)
    }
}
