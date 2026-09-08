import SwiftUI

/// 성장 탭 — 이번 주 sRPE 부하. 일별 막대(색 = 그날 평균 강도), 합계·커버리지, 지난주 대비, 하단 문장 1개.
struct EffortLoadCard: View {
    let current: EffortLoad.WeekLoad
    let previous: [EffortLoad.WeekLoad?]    // 직전 4주, 오래된→최신. nil = 러닝 없는 주

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
        let totalText = current.total.rounded().formatted(.number.grouping(.automatic))
        return HStack(spacing: 8) {
            Text(L.s("이번 주 \(totalText) AU", "This week \(totalText) AU"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(L.s("러닝 \(current.runCount)회 중 \(current.coveredCount)회 강도 있음",
                     "\(current.coveredCount) of \(current.runCount) runs rated"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            // 직전 주 = previous의 마지막 원소(러닝 없는 주면 nil)
            if let delta = EffortLoad.weekOverWeek(current: current, previous: previous.last ?? nil) {
                let pct = Int((delta * 100).rounded())
                let sign = pct > 0 ? "+" : ""
                Text(L.s("지난주 대비 \(sign)\(pct)%", "vs last week \(sign)\(pct)%"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
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
                                .fill(EffortPalette.color(for: EffortResolver.clamp(current.dailyMeanEffort[i] ?? 5)))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.s("요일별 부하", "Daily load"))
        .accessibilityValue(barsAccessibilityValue(labels: labels))
    }

    /// 부하가 있는 날만 "월 280, 토 270" 형태로 읽어 준다.
    private func barsAccessibilityValue(labels: [String]) -> String {
        let parts = (0..<7).compactMap { i -> String? in
            guard current.daily[i] > 0 else { return nil }
            return "\(labels[i]) \(Int(current.daily[i].rounded()))"
        }
        return parts.isEmpty ? L.s("기록 없음", "No load") : parts.joined(separator: ", ")
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
