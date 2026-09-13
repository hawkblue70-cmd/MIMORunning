import Testing
import Foundation
@testable import MIMORunning

@MainActor
@Suite("기온 보정 심박 — 러닝 인사이트", .serialized)
struct HeatAdjustedHRInsightTests {
    private func run(_ daysAgo: Int, pace: Double, hr: Int, temp: Double?, id: UUID = UUID()) -> Activity {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return Activity(id: id, type: .running, date: d, duration: pace * 10, distance: 10_000,
                        calories: nil, avgHeartRate: hr, temperatureC: temp, humidityPercent: nil)
    }
    /// 학습형 모델 0.8 bpm/°C (폴백과 계수는 같고 톤만 다름)
    private var learned: MRHeatHRModel { var m = MRHeatHRModel.fallback(); m.isFallback = false; m.tempMaxC = 35; return m }

    @Test func heatExplainsTheWholeDifference() {
        AppLanguage.shared.isEnglish = false
        let today = run(0, pace: 376, hr: 149, temp: 25)                  // 보정 −8 → 141
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 146, temp: 15) }
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: learned)
        #expect(r?.badge == "기온 감안")
        #expect(r?.message == "비슷한 페이스 최근 5회 대비 심박이 3 bpm 높지만 25°C 기온을 감안하면 평소 수준이에요.")
        #expect(r?.tone == .neutral)
    }

    @Test func fallbackModelUsesReferenceTone() {
        AppLanguage.shared.isEnglish = false
        let today = run(0, pace: 376, hr: 149, temp: 25)
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 146, temp: 15) }
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: .fallback())
        #expect(r?.badge == "참고")
        #expect(r?.message == "비슷한 페이스 최근 5회 대비 심박이 3 bpm 높지만 일반적인 더위 영향(25°C)을 감안하면 평소 수준으로 보여요.")
    }

    @Test func stillHigherAfterAdjustment() {
        AppLanguage.shared.isEnglish = false
        let today = run(0, pace: 376, hr: 160, temp: 25)                  // 보정 152, 과거 146 → +6
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 146, temp: 15) }
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: learned)
        #expect(r?.message == "25°C 기온을 감안해도 비슷한 페이스 최근 5회 대비 심박이 6 bpm 높아요. 오늘 컨디션을 반영한 것일 수 있어요.")
    }

    @Test func hotHistoryIsAdjustedToo() {
        AppLanguage.shared.isEnglish = false
        let today = run(0, pace: 376, hr: 142, temp: 15)
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 150, temp: 28) } // 과거 더운 날 → 보정 139.6
        // 보정 후 오늘 142 vs 과거 139.6 → 2.4 < 3 → 침묵 (원본 비교였다면 "8 bpm 낮음"으로 과장)
        #expect(RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: learned) == nil)
    }

    @Test func largeRawGapStillExplainedByHeat() {
        AppLanguage.shared.isEnglish = false
        // 원본 +10(146→156)이지만 보정하면 148 vs 146 → 2bpm(<3) 차이로 사라진다 → 여전히 "설명됨"
        let today = run(0, pace: 376, hr: 156, temp: 25)
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 146, temp: 15) }
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: learned)
        #expect(r?.badge == "기온 감안")
        #expect(r?.message == "비슷한 페이스 최근 5회 대비 심박이 10 bpm 높지만 25°C 기온을 감안하면 평소 수준이에요.")
    }

    @Test func hotHistoryDoesNotGetFalseReassurance() {
        AppLanguage.shared.isEnglish = false
        // 오늘도 과거도 더웠던 경우 — 양쪽 다 보정하면 여전히 6bpm 높다. 더위가 "통째로 설명"하지 않는다.
        var model = learned
        model.tempMaxC = 35
        let today = run(0, pace: 376, hr: 158, temp: 35)
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 150, temp: 33) }
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: model)
        #expect(r?.message == "35°C 기온을 감안해도 비슷한 페이스 최근 5회 대비 심박이 6 bpm 높아요. 오늘 컨디션을 반영한 것일 수 있어요.")
    }

    @Test func fallbackToneOnStillHigher() {
        AppLanguage.shared.isEnglish = false
        let today = run(0, pace: 376, hr: 160, temp: 25)
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 146, temp: 15) }
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: .fallback())
        #expect(r?.message.hasPrefix("일반적인 더위 영향(25°C)을 감안해도 ") == true)
    }

    @Test func hotTodayWithEqualRawHRMakesNoImprovementClaim() {
        AppLanguage.shared.isEnglish = false
        // 원본 심박은 과거와 완전히 같음(0) — 보정만으로는 +8(10.4bpm) "개선"처럼 보이지만
        // 원본 비교가 뒷받침하지 않으므로 개선을 말하지 않는다.
        let today = run(0, pace: 376, hr: 146, temp: 28)
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 146, temp: 15) }
        #expect(RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: learned) == nil)
    }

    @Test func improvementReportsAdjustedDifference() {
        AppLanguage.shared.isEnglish = false
        // 원본 11bpm 낮음(148→138) + 보정 149−8=141 → 3bpm 낮음 — 둘 다 개선을 뒷받침
        let today = run(0, pace: 376, hr: 138, temp: 15)
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 149, temp: 25) }
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: learned)
        #expect(r?.message == "비슷한 페이스 최근 5회 대비 심박이 3 bpm 낮아요 — 심폐 효율이 개선되고 있어요.")
        #expect(r?.tone == .good)
    }

    @Test func lowTemperatureCoverageComparesRawAndOnlyHints() {
        AppLanguage.shared.isEnglish = false
        let today = run(0, pace: 376, hr: 149, temp: 25)
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 146, temp: nil) } // 과거 기온 없음 → 커버리지 0%
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: learned)
        #expect(r?.badge == "참고")
        #expect(r?.message == "비슷한 페이스 최근 5회 대비 심박이 3 bpm 높아요. 25°C 더위 영향일 수 있어요.")
    }

    @Test func todayWithoutTemperatureComparesRaw() {
        AppLanguage.shared.isEnglish = false
        // 오늘 기온이 없으면 보정 자체가 불가능 — 과거 기온이 다 있어도 원본으로 비교한다.
        let today = run(0, pace: 376, hr: 146, temp: nil)
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 150, temp: 30) }
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: learned)
        #expect(r?.message == "비슷한 페이스 최근 5회 대비 심박이 4 bpm 낮아요 — 심폐 효율이 개선되고 있어요.")
    }

    @Test func coolTodayVersusHotHistoryExplainsTheAdjustment() {
        AppLanguage.shared.isEnglish = false
        // 오늘은 안 더워서(15°C) heatExplains는 false지만, 과거 기록이 더웠던 만큼(28°C) 보정폭이 크다
        // → "더운 날이 많았던 최근 기록을 15°C 기준으로 맞추면" 문구로 그 사실을 밝힌다.
        let today = run(0, pace: 376, hr: 148, temp: 15)
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 150, temp: 28) } // 보정 139.6
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: learned)
        #expect(r?.message == "더운 날이 많았던 최근 기록을 15°C 기준으로 맞추면 비슷한 페이스 최근 5회 대비 심박이 8 bpm 높아요. 오늘 컨디션을 반영한 것일 수 있어요.")
    }

    @Test func historyIsPointInTime() {
        AppLanguage.shared.isEnglish = false
        let today = run(10, pace: 376, hr: 149, temp: 15)
        let future = (0...4).map { run($0, pace: 376, hr: 130, temp: 15) }   // 이 러닝 이후 기록
        #expect(RunInsightEngine.efficiencyInsight(activity: today, history: future, heatHR: learned) == nil)
    }

    @Test func driftNoteMentionsHeatWhenHot() {
        AppLanguage.shared.isEnglish = false
        // pace 360 → duration 3600s == 샘플 구간 길이, 앞/뒤 60개씩 정확히 절반 — 143/155 경계와 일치시킨다.
        // (pace 376이면 duration/2=1880이 샘플 60번째(offset 1800) 뒤에 걸려 앞쪽에 155가 3개 섞여
        //  전반 평균이 흐려지고 드리프트가 11bpm으로 반올림된다.)
        let today = run(0, pace: 360, hr: 149, temp: 26)
        let samples: [(offset: TimeInterval, bpm: Int)] = (0..<120).map { i in (Double(i) * 30, i < 60 ? 143 : 155) }
        let r = RunInsightEngine.cardiacDriftInsight(activity: today, hrSamples: samples, category: .efficiency, heatHR: learned)
        #expect(r?.message == "후반 심박이 전반보다 12bpm 올랐어요. 26°C에서는 흔한 폭이에요.")
        let cool = run(0, pace: 360, hr: 149, temp: 12)
        let r2 = RunInsightEngine.cardiacDriftInsight(activity: cool, hrSamples: samples, category: .efficiency, heatHR: learned)
        #expect(r2?.message == "후반 심박이 전반보다 12bpm 올랐어요.")
    }

    @Test func hrDropIsNotReportedAsRise() {
        AppLanguage.shared.isEnglish = false
        // 후반에 심박이 뚝 떨어지는 경우 — "올랐어요"로 잘못 읽히면 안 되고 드리프트 적음으로 처리한다.
        let today = run(0, pace: 360, hr: 149, temp: 20)
        let samples: [(offset: TimeInterval, bpm: Int)] = (0..<120).map { i in (Double(i) * 30, i < 60 ? 155 : 143) }
        let r = RunInsightEngine.cardiacDriftInsight(activity: today, hrSamples: samples, category: .efficiency, heatHR: learned)
        #expect(r?.message == "전반/후반 심박 차이 12bpm — 카디악 드리프트 적어요.")
        #expect(r?.tone == .good)
    }

    @Test func easyOverpaceUsesAdjustedHR() {
        AppLanguage.shared.isEnglish = false
        // 최대 170 · 관측 130(76%) · 25°C → 보정 122(72%) → 여유 있는 강도
        let today = run(0, pace: 420, hr: 130, temp: 25)
        let r = RunInsightEngine.easyOverpaceInsight(activity: today, age: nil, hrMax: 170, heatHR: learned)
        #expect(r?.tone == .good)
        #expect(r?.message == "심박 72%로 여유 있는 강도의 이지런이었어요. (25°C 감안)")
    }
}
