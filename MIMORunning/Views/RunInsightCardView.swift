import SwiftUI

// MARK: - Category Icon

extension InsightCategory {
    var icon: String {
        switch self {
        case .cardio:      return "lungs.fill"
        case .intensity:   return "gauge.with.needle"
        case .form:        return "figure.run"
        case .endurance:   return "chart.line.uptrend.xyaxis"
        case .efficiency:  return "bolt.heart"
        case .environment: return "thermometer.medium"
        case .load:        return "calendar"
        }
    }
}

// MARK: - Tone Color

extension InsightTone {
    var color: Color {
        switch self {
        case .good:    return Theme.elevation
        case .neutral: return Theme.pace
        case .caution: return Color.orange
        }
    }
}

// MARK: - Individual Card

struct RunInsightCard: View {
    let insight: RunInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Header row
            HStack(spacing: 7) {
                Image(systemName: insight.category.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(insight.tone.color)
                Text(insight.category.rawValue)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(insight.badge)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(insight.tone.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(insight.tone.color.opacity(0.15))
                    .clipShape(Capsule())
            }
            // Body with highlighted keywords
            Text(attributedMessage)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .foregroundStyle(Color.primary.opacity(0.85))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private var attributedMessage: AttributedString {
        var attributed = AttributedString(insight.message)
        for kw in insight.highlights where !kw.isEmpty {
            if let r = attributed.range(of: kw) {
                attributed[r].foregroundColor = insight.tone.color
                attributed[r].font = .system(size: 12.5, weight: .medium)
            }
        }
        return attributed
    }
}

// MARK: - Section

struct RunInsightSection: View {
    let insights: [RunInsight]

    var body: some View {
        if !insights.isEmpty {
            let L = AppLanguage.shared
            VStack(alignment: .leading, spacing: 8) {
                Text(L.s("오늘의 러닝", "Today's Run"))
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)

                VStack(spacing: 8) {
                    ForEach(insights) { insight in
                        RunInsightCard(insight: insight)
                    }
                }
                .padding(.horizontal, 16)

                // 면책 문구 — 반드시 포함
                Text(L.s(
                    "참고용 피트니스 인사이트입니다. 연령대 평균과 추정 최대심박은 개인차가 큰 추정치이며 의학적 판단이 아니에요.",
                    "Reference-only fitness insights. Age-group norms and estimated max HR are rough estimates with high individual variation and are not medical advice."
                ))
                .font(.system(size: 9.5))
                .foregroundStyle(Color.secondary)
                .lineSpacing(2)
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let samples: [RunInsight] = [
        RunInsight(
            category: .cardio,
            tone: .good,
            badge: "평균 이상",
            message: "유산소 피트니스 48.5는 같은 연령대 기준 평균 이상에 해당해요. (추정값)",
            highlights: ["48.5", "평균 이상"]
        ),
        RunInsight(
            category: .intensity,
            tone: .neutral,
            badge: "강도 확인",
            message: "평균 심박 152은 추정 최대심박의 약 82% — 고강도이에요. 페이스 편차 12초로 안정적이었어요.",
            highlights: ["152", "82%"]
        ),
        RunInsight(
            category: .endurance,
            tone: .good,
            badge: "후반 유지",
            message: "전반 대비 후반 페이스 편차 1.8% — 끝까지 잘 유지했어요.",
            highlights: ["1.8%"]
        ),
        RunInsight(
            category: .environment,
            tone: .caution,
            badge: "날씨 감안",
            message: "27°C · 습도 78% — 더위와 습도가 높아 체감 부담이 있었을 거예요.",
            highlights: ["27°C · 습도 78%"]
        ),
    ]

    ScrollView {
        RunInsightSection(insights: samples)
            .padding(.vertical, 20)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
