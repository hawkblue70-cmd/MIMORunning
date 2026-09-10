import Testing
import Foundation
@testable import MIMORunning

/// 폼 카드 추세 문단(케이던스+지면접촉 결합) — 보폭 방향은 케이던스에서, 탄력은 지면·공중 시간에서 읽는다.
/// 언어는 `AppLanguage.$override`(태스크 로컬)로 주입해 전역 설정을 건드리지 않는다.
@Suite("MRFormStyle 추세 문단", .korean)
struct FormTrendParagraphTests {

    private let cadMetric = mrFormMetrics.first { $0.key == "cadence" }!
    private let gctMetric = mrFormMetrics.first { $0.key == "gct" }!

    private func cad(_ delta: Double, recentMean: Double = 0, weeks: Int = 4) -> MRFormShift {
        MRFormShift(metric: cadMetric, recentMean: recentMean, baseMean: recentMean - delta,
                    delta: delta, mdc: 1.0, weeksConsistent: weeks, r2: nil)
    }
    private func gct(_ delta: Double, weeks: Int = 4) -> MRFormShift {
        MRFormShift(metric: gctMetric, recentMean: delta, baseMean: 0,
                    delta: delta, mdc: 2.0, weeksConsistent: weeks, r2: nil)
    }

    private func ko(_ shifts: [MRFormShift], refCadence: Int? = 170, run: Double? = nil) -> String {
        AppLanguage.$override.withValue(false) {
            mrFormObservation(shifts, refCadence: refCadence, runCadenceResidual: run)?.text ?? ""
        }
    }
    private func en(_ shifts: [MRFormShift], refCadence: Int? = 170, run: Double? = nil) -> String {
        AppLanguage.$override.withValue(true) {
            mrFormObservation(shifts, refCadence: refCadence, runCadenceResidual: run)?.text ?? ""
        }
    }

    // MARK: - 버그 2: 보폭은 케이던스 방향, 탄력은 지면·공중 시간

    /// cad +3 · gct −8 @170 → 걸음 주기 −6.2ms, 공중 +1.8ms → 잦은 걸음 + 탄력. "더 큰 한 걸음"은 나오면 안 된다.
    @Test func cadenceUpGctDown_isQuickerAndSpringy() {
        let t = ko([cad(3), gct(-8)])
        #expect(t == "같은 페이스에서 케이던스가 3개월 새 3spm 올라가고, 지면접촉이 8ms 짧아졌어요.\n조금 더 잦은 걸음이 되고 공중 시간은 2ms 늘었어요.\n같은 페이스를 더 가볍고 탄력 있게 만들고 있다는 뜻이에요.")
        #expect(t.contains("잦은"))
        #expect(t.contains("탄력"))
        #expect(!t.contains("더 큰"))
        #expect(t.split(separator: "\n").count == 3)
    }

    /// cad −3 · gct +8 → 공중 −1.8ms → 큰 걸음 + "오래 딛고". 탄력·위험 표현 없음.
    @Test func cadenceDownGctUp_isLongerStepsAndLongerContact() {
        let t = ko([cad(-3), gct(8)])
        #expect(t.contains("큰 걸음"))
        #expect(t.contains("지면에 머무는 시간이 늘었어요"))
        #expect(t.contains("조금 더 오래 딛고"))
        #expect(!t.contains("탄력"))
        #expect(!t.contains("잦은"))
        #expect(!t.contains("부상") && !t.contains("위험"))
    }

    /// 케이던스 변화 |Δ| < 1 spm → 실증 아님 → 결합 문단 대신 GCT 단독 문장. 보폭 표현 없음.
    @Test func cadenceFlat_noStrideWording() {
        let t = ko([cad(0.4), gct(-8)])
        #expect(!t.isEmpty)
        #expect(!t.contains("잦은 걸음") && !t.contains("큰 걸음") && !t.contains("더 큰 한 걸음"))
    }

    /// 공중 시간 부호 수식은 그대로: Δairtime = −60000/cad² × Δcad − Δgct.
    /// cad +6 @170 → 걸음 주기 −12.5ms, gct −8 → 공중 −4.5ms → "줄었어요" + 케이던스 방향 결론.
    @Test func airtimeSignMath_unchanged() {
        let t = ko([cad(6), gct(-8)])
        #expect(t.contains("공중 시간은 4ms 줄었어요"))
        #expect(t.contains("같은 페이스를 더 잦은 걸음으로 만들고 있다는 뜻이에요"))
        #expect(!t.contains("탄력"))
        // 기준 케이던스가 낮으면 걸음 주기 변화가 커진다: @150 → −16ms, 공중 −8ms
        let t2 = ko([cad(6), gct(-8)], refCadence: 150)
        #expect(t2.contains("공중 시간은 8ms 줄었어요"))
    }

    /// cad −4 · gct −3 → 걸음 주기 +8.3ms, 공중 +11.3ms → 큰 걸음이면서 지면↓·공중↑ → 탄력 결론. (gct는 |Δ| ≥ 3ms여야 실증)
    @Test func cadenceDownGctDown_isLongerStepsAndSpringy() {
        let t = ko([cad(-4), gct(-3)])
        #expect(t.contains("큰 걸음"))
        #expect(t.contains("공중 시간은 11ms 늘었어요"))
        #expect(t.contains("탄력"))
    }

    @Test func englishVariant() {
        let t = en([cad(3), gct(-8)])
        #expect(t == "At similar pace, cadence over 3 months rose 3 spm, contact shortened 8 ms.\nSteps got a little quicker, and airtime rose ~2 ms.\nAt the same pace, you're getting lighter and springier.")
        let t2 = en([cad(-3), gct(8)])
        #expect(t2.contains("Steps got a little longer, and time on the ground went up."))
        #expect(t2.contains("spending a little longer on each footstrike"))
        #expect(!t2.contains("bigger strides"))
    }

    // MARK: - 항목 8: 이 러닝의 위치에 따라 마무리가 달라진다

    @Test func runOnTrend_appendsOnTrendTail() {
        let t = ko([cad(3, recentMean: 2.0), gct(-8)], run: 1.5)   // ≥ 끝점 − 1
        #expect(t.hasSuffix("만들고 있다는 뜻이에요. 이 러닝도 그 흐름 위에 있어요."))
        #expect(t.split(separator: "\n").count == 3)
        let e = en([cad(3, recentMean: 2.0), gct(-8)], run: 4.0)
        #expect(e.hasSuffix("This run sits right on that trend."))
    }

    @Test func runBelowTrend_appendsRelaxedTail() {
        let t = ko([cad(3, recentMean: 2.0), gct(-8)], run: -0.5)  // < 끝점 − 2
        #expect(t.hasSuffix("이 러닝은 그 흐름보다 조금 느긋했어요."))
        let e = en([cad(3, recentMean: 2.0), gct(-8)], run: -0.5)
        #expect(e.hasSuffix("This run was a little more relaxed than that trend."))
    }

    @Test func runSlightlyBelow_noTail() {
        let t = ko([cad(3, recentMean: 2.0), gct(-8)], run: 0.5)   // 끝점 − 2 ≤ r < 끝점 − 1
        #expect(t.hasSuffix("만들고 있다는 뜻이에요."))
        #expect(!t.contains("이 러닝"))
    }

    /// 러닝별 값이 없고 8주 이상 이어진 추세 → 사실 + 결론 2줄로 축약.
    @Test func noRunValue_longTrend_shortensToTwoLines() {
        let t = ko([cad(3, weeks: 9), gct(-8, weeks: 9)])
        #expect(t.split(separator: "\n").count == 2)
        #expect(t.hasPrefix("같은 페이스에서 케이던스가"))
        #expect(t.hasSuffix("탄력 있게 만들고 있다는 뜻이에요."))
        // 러닝별 값이 있으면 오래된 추세여도 3줄 유지
        let t3 = ko([cad(3, recentMean: 2.0, weeks: 9), gct(-8, weeks: 9)], run: 2.0)
        #expect(t3.split(separator: "\n").count == 3)
    }

    @Test func runResidualLookup_byDay() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let rs = [MRFormResidual(date: yesterday, value: -1.0),
                  MRFormResidual(date: today, value: 2.5)]
        #expect(mrFormRunResidual(rs, on: Date()) == 2.5)
        #expect(mrFormRunResidual(rs, on: cal.date(byAdding: .day, value: -3, to: today)!) == nil)
    }
}
