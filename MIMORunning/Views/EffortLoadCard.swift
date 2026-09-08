import SwiftUI

/// 성장 탭 — 최근 7일(롤링) sRPE 부하. 일별 막대(색 = 그날 평균 강도), 합계·커버리지, 이전 7일 대비, 하단 문장 1개.
/// 달력 주가 아니라 롤링 창을 쓰는 이유: 월요일에 러닝 1건이면 "지난주 대비 -91%"처럼 부분 주와 완전한 주를 비교하게 된다.
struct EffortLoadCard: View {
    let summary: EffortLoad.RollingSummary

    private var L: AppLanguage { AppLanguage.shared }
    private var current: EffortLoad.WindowLoad { summary.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            if current.daily.count == 7, current.dailyMeanEffort.count == 7, current.dayStarts.count == 7 {
                bars
            }
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
            if let delta = summary.weekOverWeek {
                let pct = Int((delta * 100).rounded())
                let sign = pct > 0 ? "+" : ""
                Text(L.s("이전 7일 대비 \(sign)\(pct)%", "vs prior 7 days \(sign)\(pct)%"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    /// 요일 첫 글자 — 롤링 창이므로 매일 순서가 달라진다. 마지막(오늘)만 밝게.
    private var dayLabels: [String] {
        let cal = Calendar.current
        let ko = Array("일월화수목금토")
        return current.dayStarts.map { d in
            let idx = cal.component(.weekday, from: d) - 1     // 1(일)~7(토) → 0~6
            guard idx >= 0, idx < 7 else { return "" }
            if L.isEnglish {
                let sym = cal.shortWeekdaySymbols.indices.contains(idx) ? cal.shortWeekdaySymbols[idx] : ""
                return String(sym.prefix(1))
            }
            return String(ko[idx])
        }
    }

    private var bars: some View {
        let maxAU = max(current.daily.max() ?? 0, 1)
        let labels = dayLabels
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
                    Text(labels.indices.contains(i) ? labels[i] : "")
                        .font(.system(size: 9, weight: i == 6 ? .bold : .medium))
                        .foregroundStyle(i == 6 ? Color.white.opacity(0.9) : Color.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.s("최근 7일 일별 부하", "Daily load, last 7 days"))
        .accessibilityValue(barsAccessibilityValue(labels: labels))
    }

    /// 부하가 있는 날만 "월 280, 토 270" 형태로 읽어 준다.
    private func barsAccessibilityValue(labels: [String]) -> String {
        let parts = (0..<7).compactMap { i -> String? in
            guard current.daily[i] > 0 else { return nil }
            let label = labels.indices.contains(i) ? labels[i] : ""
            return "\(label) \(Int(current.daily[i].rounded()))"
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
