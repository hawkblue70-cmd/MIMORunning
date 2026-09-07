import Testing
import Foundation
@testable import MIMORunning

@Suite("EffortRules 라벨 vs 몸 · 더위 · 스플릿")
struct EffortRulesTests {

    private func split(_ id: Int, km: Double = 1.0, pace: Double) -> SplitData {
        SplitData(id: id, distanceM: km * 1000, duration: pace * km, avgHeartRate: nil, avgCadence: nil,
                  avgPower: nil, avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil)
    }
    private func input(effort: Int, source: EffortSource = .user, type: WorkoutType, baseline: Int?,
                       splits: [SplitData] = [], temp: Double? = nil, hum: Double? = nil) -> EffortRuleInput {
        EffortRuleInput(effort: ResolvedEffort(value: effort, source: source), type: type, baseline: baseline,
                        splits: splits, temperatureC: temp, humidityPercent: hum)
    }
    private func badges(_ o: EffortRuleOutput) -> [String] { o.insights.map(\.badge) }

    // A 계열은 하나만
    @Test func easyRunTooHardAgainstBaseline() {
        let o = EffortRules.evaluate(input(effort: 7, type: .easy, baseline: 5))
        #expect(o.insights.count == 1)
        #expect(o.insights[0].tone == .caution)
        #expect(o.insights[0].category == .intensity)
    }

    @Test func easyRunAbsoluteEightWithoutBaselineGap() {
        // baseline 7이면 +2 미달이지만 절대 8 이상 → caution
        let o = EffortRules.evaluate(input(effort: 8, type: .lsd, baseline: 7))
        #expect(o.insights.count == 1)
        #expect(o.insights[0].tone == .caution)
    }

    @Test func noBaselineOnlyAbsoluteRuleFires() {
        #expect(EffortRules.evaluate(input(effort: 7, type: .easy, baseline: nil)).insights.count == 1)
        #expect(EffortRules.evaluate(input(effort: 6, type: .easy, baseline: nil)).insights.isEmpty)
        // baseline 없으면 B·C도 침묵
        let hotFade = input(effort: 9, type: .easy, baseline: nil,
                            splits: [split(1, pace: 360), split(2, pace: 360), split(3, pace: 380), split(4, pace: 380)],
                            temp: 30)
        let o = EffortRules.evaluate(hotFade)
        #expect(o.insights.count == 1)
        #expect(o.replacesEnvironment == false)
    }

    @Test func hardTypeBelowBaselineIsNeutral_andMatchedIsGood() {
        let easyDay = EffortRules.evaluate(input(effort: 5, type: .tempo, baseline: 7))
        #expect(easyDay.insights.count == 1)
        #expect(easyDay.insights[0].tone == .neutral)
        let matched = EffortRules.evaluate(input(effort: 7, type: .tempo, baseline: 7))
        #expect(matched.insights.count == 1)
        #expect(matched.insights[0].tone == .good)
        let general = EffortRules.evaluate(input(effort: 5, type: .general, baseline: 5))
        #expect(general.insights.count == 1)
        #expect(general.insights[0].tone == .good)
    }

    @Test func heatRules() {
        let higher = EffortRules.evaluate(input(effort: 6, type: .general, baseline: 5, temp: 26))
        #expect(higher.replacesEnvironment)
        #expect(higher.insights.contains { $0.category == .environment && $0.tone == .neutral })
        let held = EffortRules.evaluate(input(effort: 5, type: .general, baseline: 5, hum: 80))
        #expect(held.replacesEnvironment)
        #expect(held.insights.contains { $0.category == .environment && $0.tone == .good })
        let mild = EffortRules.evaluate(input(effort: 6, type: .general, baseline: 5, temp: 20, hum: 50))
        #expect(!mild.replacesEnvironment)
        #expect(!mild.insights.contains { $0.category == .environment })
    }

    @Test func secondHalfSlowdownMath() {
        // 전반 360·360, 후반 380·380 → 380/360 − 1 = +5.6%
        let s = [split(1, pace: 360), split(2, pace: 360), split(3, pace: 380), split(4, pace: 380)]
        let v = EffortRules.secondHalfSlowdown(splits: s)!
        #expect(abs(v - 0.0556) < 0.001)
        // 부분 스플릿(1km 미만) 제외 → 3개 남아 nil
        let partial = [split(1, pace: 360), split(2, pace: 360), split(3, pace: 380), split(4, km: 0.4, pace: 380)]
        #expect(EffortRules.secondHalfSlowdown(splits: partial) == nil)
        // 5개(홀수) → 가운데 제외: 전반 1·2, 후반 4·5
        let five = [split(1, pace: 360), split(2, pace: 360), split(3, pace: 900), split(4, pace: 360), split(5, pace: 360)]
        #expect(abs(EffortRules.secondHalfSlowdown(splits: five)!) < 0.0001)
    }

    @Test func splitRulesOnlyForEasyTypesAboveBaseline() {
        let fade = [split(1, pace: 360), split(2, pace: 360), split(3, pace: 380), split(4, pace: 380)]
        let surge = [split(1, pace: 380), split(2, pace: 380), split(3, pace: 360), split(4, pace: 360)]
        let fadeOut = EffortRules.evaluate(input(effort: 6, type: .easy, baseline: 5, splits: fade))
        #expect(fadeOut.insights.contains { $0.category == .intensity && $0.message.contains("초반") })
        let surgeOut = EffortRules.evaluate(input(effort: 6, type: .easy, baseline: 5, splits: surge))
        #expect(surgeOut.insights.contains { $0.message.contains("후반") })
        // 템포는 스플릿 규칙 없음
        let tempo = EffortRules.evaluate(input(effort: 8, type: .tempo, baseline: 7, splits: fade))
        #expect(!tempo.insights.contains { $0.message.contains("초반") })
        // 기준선 이하면 없음
        let calm = EffortRules.evaluate(input(effort: 5, type: .easy, baseline: 5, splits: fade))
        #expect(!calm.insights.contains { $0.message.contains("초반") })
    }

    @Test func atMostThreeInsights() {
        let fade = [split(1, pace: 360), split(2, pace: 360), split(3, pace: 380), split(4, pace: 380)]
        let o = EffortRules.evaluate(input(effort: 8, type: .easy, baseline: 5, splits: fade, temp: 30, hum: 80))
        #expect(o.insights.count == 3)
    }
}
