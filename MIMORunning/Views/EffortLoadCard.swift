import SwiftUI

/// 성장 탭 — 이번 주 sRPE 부하. 일별 막대(색 = 그날 평균 강도), 합계·커버리지, 지난주 대비, 하단 문장 1개.
struct EffortLoadCard: View {
    let current: EffortLoad.WeekLoad
    let previous: [EffortLoad.WeekLoad]     // 직전 4주 중 존재하는 주(오래된→최신)

    private var L: AppLanguage { AppLanguage.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.s("훈련 강도 부하", "Training Load (Effort)"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(L.s("강도 × 시간(분)", "effort × minutes"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            headline
            if current.daily.count == 7, current.dailyMeanEffort.count == 7 {
                bars
            }
            if let kind = EffortLoad.sentenceKind(current: current, previous: previous) {
                Text(sentence(kind))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var headline: some View {
        HStack(spacing: 8) {
            Text(L.s("이번 주 \(Int(current.total.rounded())) AU", "This week \(Int(current.total.rounded())) AU"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(L.s("러닝 \(current.runCount)회 중 \(current.coveredCount)회 강도 있음",
                     "\(current.coveredCount) of \(current.runCount) runs rated"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if let delta = EffortLoad.weekOverWeek(current: current, previous: previous.last) {
                Text(String(format: "%@%.0f%%", delta >= 0 ? "+" : "", delta * 100))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(delta >= 0 ? Theme.violet : .secondary)
            }
        }
    }

    private var bars: some View {
        let maxAU = max(current.daily.max() ?? 0, 1)
        let labels = L.isEnglish ? ["M", "T", "W", "T", "F", "S", "S"] : ["월", "화", "수", "목", "금", "토", "일"]
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05))
                        if current.daily[i] > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(EffortPalette.color(for: Int((current.dailyMeanEffort[i] ?? 5).rounded())))
                                .frame(height: max(4, 56 * current.daily[i] / maxAU))
                        }
                    }
                    .frame(height: 56)
                    Text(labels[i])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sentence(_ kind: EffortLoad.SentenceKind) -> String {
        switch kind {
        case .monotony: return L.s("휴식일 없이 비슷한 부하가 이어졌어요. 쉬운 날과 힘든 날을 나눠 보세요.",
                                   "Similar load every day with no rest. Try separating easy and hard days.")
        case .veryHigh: return L.s("최근 4주 평균보다 부하가 많이 높은 주예요.", "A much heavier week than your 4-week average.")
        case .high:     return L.s("평소보다 조금 높은 주예요.", "A slightly heavier week than usual.")
        case .low:      return L.s("회복 쪽으로 기운 주예요.", "A lighter, recovery-leaning week.")
        }
    }
}
