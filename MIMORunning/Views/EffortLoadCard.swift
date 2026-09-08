import SwiftUI

/// 성장 탭 — 최근 7일(롤링) sRPE 부하 상태 카드. 막대 없음(일별 막대는 성장 탭 기록 카드(`RecordBarChart` 부하 모드)가 담당).
/// 합계·커버리지 → 4주 평균 대비 상태(없으면 이전 7일 대비 %) → 문장 1개.
/// 달력 주가 아니라 롤링 창을 쓰는 이유: 월요일에 러닝 1건이면 "지난주 대비 -91%"처럼 부분 주와 완전한 주를 비교하게 된다.
struct EffortLoadCard: View {
    let summary: EffortLoad.RollingSummary
    /// 최근 7일 ÷ 직전 4×7일 평균 — 주 비교 문구. 유효 창이 모자라면 nil.
    let acuteChronic: (ratio: Double, label: EffortLoad.RatioLabel)?

    init(summary: EffortLoad.RollingSummary,
         acuteChronic: (ratio: Double, label: EffortLoad.RatioLabel)? = nil) {
        self.summary = summary
        self.acuteChronic = acuteChronic
    }

    private var L: AppLanguage { AppLanguage.shared }
    private var current: EffortLoad.WindowLoad { summary.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.s("훈련 강도 부하", "Training Load (Effort)"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(L.s("강도 × 시간(분) · 최근 7일", "effort × minutes · last 7 days"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            headline
            comparison
            if let kind = summary.sentence {
                Text(sentence(kind))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var headline: some View {
        let totalText = current.total.rounded().formatted(.number.grouping(.automatic))
        return HStack(spacing: 8) {
            Text(L.s("최근 7일 \(totalText) AU", "Last 7 days \(totalText) AU"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(L.s("러닝 \(current.runCount)회 중 \(current.coveredCount)회 강도 있음",
                     "\(current.coveredCount) of \(current.runCount) runs rated"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// 1순위: 4주 평균 대비 상태. 없으면 이전 7일 대비 %.
    @ViewBuilder
    private var comparison: some View {
        if let ac = acuteChronic {
            Text(ratioText(ac.label))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ratioColor(ac.label))
        } else if let delta = summary.weekOverWeek {
            let pct = Int((delta * 100).rounded())
            let sign = pct > 0 ? "+" : ""
            Text(L.s("이전 7일 대비 \(sign)\(pct)%", "vs prior 7 days \(sign)\(pct)%"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func ratioText(_ label: EffortLoad.RatioLabel) -> String {
        switch label {
        case .low:      return L.s("4주 평균 대비 낮음", "vs 4-week avg: lower")
        case .steady:   return L.s("4주 평균 대비 유지", "vs 4-week avg: steady")
        case .high:     return L.s("4주 평균 대비 높음", "vs 4-week avg: higher")
        case .veryHigh: return L.s("4주 평균 대비 크게 높음", "vs 4-week avg: much higher")
        }
    }

    private func ratioColor(_ label: EffortLoad.RatioLabel) -> Color {
        switch label {
        case .low:      return .secondary
        case .steady:   return .white.opacity(0.85)
        case .high:     return Color(hex: "FFD166")
        case .veryHigh: return Color(hex: "FF9A1F")
        }
    }

    private func sentence(_ kind: EffortLoad.SentenceKind) -> String {
        switch kind {
        case .monotony: return L.s("부하 편차가 거의 없었어요. 쉬운 날과 힘든 날을 나눠 보세요.",
                                   "Very little variation in load. Try separating easy and hard days.")
        case .veryHigh: return L.s("최근 4주 평균보다 부하가 많이 높은 주예요.", "A much heavier week than your 4-week average.")
        case .high:     return L.s("평소보다 조금 높은 주예요.", "A slightly heavier week than usual.")
        case .low:      return L.s("회복 쪽으로 기운 주예요.", "A lighter, recovery-leaning week.")
        }
    }
}
