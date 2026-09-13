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
}
