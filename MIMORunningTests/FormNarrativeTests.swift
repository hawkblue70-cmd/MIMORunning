import Testing
import Foundation
@testable import MIMORunning

/// 폼 카드 마무리 문장 — 유형 프레임(이지·빠른·일반)별 톤. 문자열 검사는 `AppLanguage.shared`를 건드리므로 직렬 실행.
@Suite("FormNarrative 폼 마무리 문장", .serialized)
struct FormNarrativeTests {

    private typealias S = FormNarrative.Status

    private func input(cad: S = .inRange, gct: S = .inRange, sl: S = .inRange,
                       cadStr: String = "176", gctStr: String? = "240", slStr: String? = "1.12",
                       paceStr: String = "5'30") -> FormNarrative.Input {
        FormNarrative.Input(cad: cad, gct: gct, sl: sl, cadStr: cadStr, gctStr: gctStr, slStr: slStr, paceStr: paceStr)
    }

    private func ko(_ i: FormNarrative.Input, _ f: FormNarrative.Frame) -> String {
        AppLanguage.shared.isEnglish = false
        return FormNarrative.sentence(i, frame: f)
    }

    private func en(_ i: FormNarrative.Input, _ f: FormNarrative.Frame) -> String {
        AppLanguage.shared.isEnglish = true
        defer { AppLanguage.shared.isEnglish = false }
        return FormNarrative.sentence(i, frame: f)
    }

    // MARK: - 프레임 매핑 (9 유형 전부)

    @Test func frameMappingCoversAllTypes() {
        #expect(FormNarrative.frame(for: .easy) == .easy)
        #expect(FormNarrative.frame(for: .tempo) == .fast)
        #expect(FormNarrative.frame(for: .buildUp) == .fast)
        #expect(FormNarrative.frame(for: .race) == .fast)
        #expect(FormNarrative.frame(for: .distanceRun) == .fast)
        #expect(FormNarrative.frame(for: .general) == .general)
        // 롱런·LSD·인터벌은 카드가 따로 처리 — 도달해도 일반 프레임
        #expect(FormNarrative.frame(for: .longRun) == .general)
        #expect(FormNarrative.frame(for: .lsd) == .general)
        #expect(FormNarrative.frame(for: .interval) == .general)
    }

    // MARK: - general

    @Test func generalCadenceBelowAndStrideBelowNoLongerSaysStrideCarriedPace() {
        let i = input(cad: .below, sl: .below)
        #expect(ko(i, .general) == "케이던스와 보폭이 평소보다 조금 작았어요.")
        #expect(en(i, .general) == "Cadence and stride were both a little below your usual.")
    }

    @Test func generalCadenceBelowStrideInRangeKeepsOldSentence() {
        let i = input(cad: .below, sl: .inRange)
        #expect(ko(i, .general) == "발걸음이 평소보다 느렸어요. 보폭 1.12m으로 페이스를 만들었어요.")
        // 보폭 미상도 옛 문장 유지
        let noSl = input(cad: .below, sl: .unknown, slStr: nil)
        #expect(ko(noSl, .general) == "발걸음이 평소보다 느렸어요. 보폭으로 페이스를 만들었어요.")
    }

    @Test func generalAllInRangeUnchanged() {
        #expect(ko(input(), .general) == "케이던스 176spm, 보폭 1.12m로 평소와 비슷한 5'30 페이스가 나왔어요.")
        #expect(ko(input(sl: .unknown, slStr: nil), .general) == "케이던스 176spm으로 평소와 비슷하게 5'30 페이스를 달렸어요.")
    }

    @Test func generalGctBelowCadenceInRangeUnchanged() {
        #expect(ko(input(gct: .below), .general) == "평소 리듬대로 176spm을 유지했고, 지면접촉이 240ms로 짧았어요.")
    }

    // MARK: - easy

    @Test func easyBothBelow() {
        let i = input(cad: .below, sl: .below)
        #expect(ko(i, .easy) == "발걸음도 보폭도 평소보다 조금 작았어요. 편하게 뛴 날이에요.")
        #expect(en(i, .easy) == "Both cadence and stride were a little below your usual. A relaxed day.")
    }

    @Test func easyCadenceBelowStrideNotBelow() {
        #expect(ko(input(cad: .below), .easy) == "발걸음이 평소보다 느렸어요. 편한 날엔 자연스러운 변화예요.")
        #expect(ko(input(cad: .below, sl: .above), .easy) == "발걸음이 평소보다 느렸어요. 편한 날엔 자연스러운 변화예요.")
    }

    @Test func easyGctAboveWithStrideClause() {
        let i = input(gct: .above, sl: .below, gctStr: "268")
        #expect(ko(i, .easy) == "지면접촉이 268ms로 평소보다 길었어요. 회복이 덜 된 날일 수 있어요. 보폭이 1.12m로 평소보다 작았어요.")
        #expect(ko(input(gct: .above, gctStr: "268"), .easy) == "지면접촉이 268ms로 평소보다 길었어요. 회복이 덜 된 날일 수 있어요.")
    }

    @Test func easyGctBelowWithCadenceInRangeOrAbove() {
        #expect(ko(input(gct: .below), .easy) == "평소 리듬대로 176spm을 유지했고, 지면접촉이 240ms로 짧았어요. 가볍게 뛴 날이에요.")
        #expect(ko(input(cad: .above, gct: .below), .easy)
                == "발걸음이 빠르게 돌고 지면접촉이 240ms로 짧았어요. 편한 날엔 리듬을 조금 늦춰도 괜찮아요.")
    }

    @Test func easyQuickShortSteps() {
        #expect(ko(input(cad: .above, sl: .below), .easy) == "잰걸음이었어요. 편한 날엔 리듬을 조금 늦춰도 괜찮아요.")
        #expect(ko(input(cad: .above, sl: .above), .easy) == "발걸음이 평소보다 빨랐어요. 보폭이 1.12m로 평소보다 컸어요.")
    }

    @Test func easyAllInRangeWithAndWithoutStride() {
        #expect(ko(input(), .easy) == "케이던스 176spm, 보폭 1.12m로 평소와 같은 편한 폼이었어요.")
        #expect(ko(input(sl: .unknown, slStr: nil), .easy) == "케이던스 176spm으로 평소와 같은 편한 폼이었어요.")
    }

    // MARK: - fast

    @Test func fastCadenceBelowStrideAbove() {
        let i = input(cad: .below, sl: .above, slStr: "1.31")
        #expect(ko(i, .fast) == "보폭 1.31m로 속도를 냈어요. 빠른 날엔 발걸음을 조금 더 빨리 돌리는 쪽이 부담이 덜해요.")
        #expect(en(i, .fast) == "You made the pace with a 1.31 m stride. On fast days, turning your feet over a little quicker is easier on the body.")
    }

    @Test func fastCadenceBelowOtherCombos() {
        #expect(ko(input(cad: .below, sl: .below), .fast) == "발걸음과 보폭이 모두 평소보다 작아 페이스가 덜 나온 날이에요.")
        #expect(ko(input(cad: .below), .fast) == "발걸음이 평소보다 느렸어요. 빠른 날엔 발걸음을 조금 더 빨리 돌리는 쪽이 부담이 덜해요.")
    }

    @Test func fastGctAbove() {
        let i = input(gct: .above, gctStr: "262")
        #expect(ko(i, .fast) == "속도를 냈는데 지면접촉이 262ms로 길었어요. 다리가 무거운 날이었을 수 있어요.")
        #expect(en(i, .fast) == "You pushed the pace, but ground contact ran long at 262 ms. Your legs may have felt heavy.")
    }

    @Test func fastGctBelow() {
        #expect(ko(input(gct: .below, gctStr: "228"), .fast) == "평소 리듬 176spm에 지면접촉이 228ms로 짧았어요. 빠른 페이스에 맞는 폼이에요.")
        #expect(ko(input(cad: .above, gct: .below, gctStr: "228"), .fast)
                == "발걸음이 빠르게 돌고 지면접촉도 228ms로 짧았어요. 빠른 페이스에 맞는 폼이에요.")
    }

    @Test func fastCadenceAbove() {
        #expect(ko(input(cad: .above), .fast) == "발걸음이 평소보다 빨랐어요. 보폭은 평소 범위였고요.")
        #expect(ko(input(cad: .above, sl: .above, slStr: "1.30"), .fast) == "발걸음이 평소보다 빨랐어요. 보폭이 1.30m로 평소보다 컸어요.")
    }

    @Test func fastAllInRangeWithAndWithoutStride() {
        let i = input(cadStr: "182", slStr: "1.28", paceStr: "4'20")
        #expect(ko(i, .fast) == "케이던스 182spm, 보폭 1.28m로 평소와 같은 폼으로 4'20 페이스를 냈어요.")
        #expect(en(i, .fast) == "Cadence 182 spm and stride 1.28 m — your usual form carried a 4'20 pace.")
        #expect(ko(input(sl: .unknown, cadStr: "182", slStr: nil, paceStr: "4'20"), .fast)
                == "케이던스 182spm으로 평소와 같은 폼으로 4'20 페이스를 냈어요.")
    }

    // MARK: - 보폭 구절 억제

    @Test func strideClauseSuppressedWhenCadenceAndGctBothDeviate() {
        // 케이던스 above + GCT above + 보폭 above → 보폭 구절 생략 (3개 나열 방지)
        for f in [FormNarrative.Frame.general, .easy, .fast] {
            let s = ko(input(cad: .above, gct: .above, sl: .above), f)
            #expect(!s.contains("보폭"), "\(f): \(s)")
        }
        // 케이던스는 범위 안, GCT above, 보폭 above → 보폭 구절 붙음
        #expect(ko(input(gct: .above, sl: .above), .general) == "지면접촉이 240ms로 평소보다 길었어요. 보폭이 1.12m로 평소보다 컸어요.")
    }

    @Test func strideClauseSkippedWhenStrideStringMissing() {
        // 보폭 status가 이탈이라도 문자열이 없으면 구절 없음
        #expect(ko(input(gct: .above, sl: .above, slStr: nil), .general) == "지면접촉이 240ms로 평소보다 길었어요.")
    }
}
