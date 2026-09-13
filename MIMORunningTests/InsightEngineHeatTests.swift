import Testing
import Foundation
@testable import MIMORunning

/// 안전 메모(같은 페이스대 심박 상승)를 15°C 기준 심박으로 판정한다.
/// 더위로 다 설명되면 침묵, 보정 후에도 남는 초과분은 "(기온 감안)" 표기와 함께 발화한다.
@MainActor
@Suite("기온 보정 심박 — 안전 메모", .serialized)
struct InsightEngineHeatTests {
    private func run(_ daysAgo: Int, pace: Double, hr: Int, temp: Double?, id: UUID = UUID()) -> Activity {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return Activity(id: id, type: .running, date: d, duration: pace * 10, distance: 10_000,
                        calories: nil, avgHeartRate: hr, temperatureC: temp, humidityPercent: nil)
    }

    /// 학습형 모델 0.8 bpm/°C (폴백과 계수는 같고 톤만 다름 — isFallback=false)
    private var learned: MRHeatHRModel {
        var m = MRHeatHRModel.fallback()
        m.isFallback = false
        m.tempMaxC = 35
        return m
    }

    @Test func hrElevatedNoteIsSuppressedWhenHeatExplains() {
        AppLanguage.shared.isEnglish = false
        // 오늘 160bpm @25°C → 보정 152bpm. 과거 8회 148bpm @15°C(보정 없음, 평균 148).
        // 152 / 148 ≈ +2.7% (<8%) → 안전 메모가 뜨면 안 된다.
        let today = run(0, pace: 360, hr: 160, temp: 25)
        let hist = (1...8).map { run($0 * 3, pace: 360, hr: 148, temp: 15) }
        let r = InsightEngine.compute(activity: today, history: hist, heatHR: learned)
        #expect(r.theme != .safety, "보정 후 8% 미만이면 안전 메모가 뜨면 안 된다: \(r.title) / \(r.detail)")
    }

    @Test func hrElevatedNoteStillFiresWhenAboveAdjusted() {
        AppLanguage.shared.isEnglish = false
        // 오늘 170bpm @25°C → 보정 162bpm. 과거 8회 148bpm @15°C(평균 148).
        // 162 / 148 ≈ +9.5% (≥8%) → 보정 후에도 남는 초과분은 발화하고, "(기온 감안)"을 덧붙인다.
        let today = run(0, pace: 360, hr: 170, temp: 25)
        let hist = (1...8).map { run($0 * 3, pace: 360, hr: 148, temp: 15) }
        let r = InsightEngine.compute(activity: today, history: hist, heatHR: learned)
        #expect(r.theme == .safety, "보정 후에도 8% 이상이면 안전 메모가 떠야 한다: \(r.title) / \(r.detail)")
        #expect(r.detail.contains("(기온 감안)"), "보정이 적용됐음을 알려야 한다: \(r.detail)")
    }

    @Test func hrElevatedNoteDirectNilWhenHeatExplains() {
        AppLanguage.shared.isEnglish = false
        // hrElevatedNote를 직접 호출 — compute()의 우선순위 체계를 거치지 않고 함수 단독으로 확인.
        let today = run(0, pace: 360, hr: 160, temp: 25)
        let hist = (1...8).map { run($0 * 3, pace: 360, hr: 148, temp: 15) }
        let r = InsightEngine.hrElevatedNote(today, hist, heatHR: learned)
        #expect(r == nil, "보정 후 8% 미만이면 hrElevatedNote 자체가 nil이어야 한다: \(String(describing: r))")
    }

    @Test func tradeoffEfficiencyNeedsRawDrop() {
        AppLanguage.shared.isEnglish = false
        // 오늘 150bpm @28°C(보정 139.6, 과거 대비 −6.9% ≥5%)이지만 원본은 과거와 동일(150) — 원본 드롭이
        // 없으므로 "심폐가 단단해지는 러닝"(효율 향상 트레이드오프)이 뜨면 안 된다.
        let today = run(0, pace: 360, hr: 150, temp: 28)
        let hist = (1...10).map { run($0 * 3, pace: 360, hr: 150, temp: 15) }
        let r = InsightEngine.compute(activity: today, history: hist, heatHR: learned)
        #expect(r.title != "심폐가 단단해지는 러닝", "원본 드롭이 없으면 효율 향상 트레이드오프가 뜨면 안 된다: \(r.theme) / \(r.title)")
    }

    @Test func hrElevatedNoteUsesRawWhenPriorLacksTemps() {
        AppLanguage.shared.isEnglish = false
        // 과거 기록에 기온이 전혀 없음 → 기온 커버리지 미달 → 양쪽 다 원본 심박으로 비교한다.
        // 오늘 170bpm vs 과거 148bpm 원본 비교 = +14.9%(≥8%) → 발화하되 "(기온 감안)"은 붙지 않는다.
        let today = run(0, pace: 360, hr: 170, temp: 25)
        let hist = (1...8).map { run($0 * 3, pace: 360, hr: 148, temp: nil) }
        let r = InsightEngine.compute(activity: today, history: hist, heatHR: learned)
        #expect(r.theme == .safety, "기온 커버리지가 없어도 원본 비교로 발화해야 한다: \(r.title) / \(r.detail)")
        #expect(!r.detail.contains("(기온 감안)"), "원본 비교일 땐 기온 감안 표기를 붙이면 안 된다: \(r.detail)")
    }
}
