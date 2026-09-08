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

    @Test func cutoffAndFallback() {
        #expect(EffortPaceTrend.easyCutoff(easyRunEfforts: [5, 6, 6]) == 6)
        #expect(EffortPaceTrend.isEasy(effort: 6, cutoff: 6))
        #expect(!EffortPaceTrend.isEasy(effort: 7, cutoff: 6))
        // 3건 미만 → nil → 고정 4 폴백
        #expect(EffortPaceTrend.easyCutoff(easyRunEfforts: [5, 6]) == nil)
        #expect(EffortPaceTrend.isEasy(effort: 4, cutoff: nil))
        #expect(!EffortPaceTrend.isEasy(effort: 5, cutoff: nil))
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
        #expect(EffortPaceTrend.observation(shift: faster, cutoff: 4, isPersonal: false)?.text.contains("12") == true)
        #expect(EffortPaceTrend.observation(shift: shift(delta: 12, real: true), cutoff: 4, isPersonal: false) == nil)
        #expect(EffortPaceTrend.observation(shift: shift(delta: -12, real: false), cutoff: 4, isPersonal: false) == nil)
    }

    @Test func observationSkipsSubSecondDelta() {
        #expect(EffortPaceTrend.observation(shift: shift(delta: -0.4, real: true), cutoff: 4, isPersonal: false) == nil)
    }

    @Test func observationMentionsPersonalCutoff() {
        let faster = shift(delta: -12, real: true)
        let marker = AppLanguage.shared.s("본인 이지런 기준", "your easy-run level")
        let personal = EffortPaceTrend.observation(shift: faster, cutoff: 6, isPersonal: true)!
        #expect(personal.text.contains(marker))
        #expect(personal.text.contains("6"))
        // 폴백(고정 4)일 때는 괄호 설명을 붙이지 않는다
        let fixed = EffortPaceTrend.observation(shift: faster, cutoff: 4, isPersonal: false)!
        #expect(!fixed.text.contains(marker))
    }

    @Test func axisLabelFormatsPace() {
        #expect(EffortPaceTrend.axisLabel(372) == "6'12\"")
        #expect(EffortPaceTrend.axisLabel(600) == "10'00\"")
    }

    @Test func formatsPace() {
        #expect(TrendMetric.easyEffortPace.formattedValue(372) == "6'12\" /km")
        #expect(TrendMetric.easyEffortPace.lowerIsBetter)
    }
}
