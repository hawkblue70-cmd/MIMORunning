import SwiftUI

// MARK: - Category Localization

extension InsightCategory {
    var localizedLabel: String {
        let L = AppLanguage.shared
        switch self {
        case .cardio:          return L.s("심폐 컨디션",    "Cardio")
        case .intensity:       return L.s("강도 · 페이스",  "Intensity")
        case .form:            return L.s("주법",           "Form")
        case .endurance:       return L.s("지구력 · 후반부","Endurance")
        case .efficiency:      return L.s("심박 효율",      "Efficiency")
        case .environment:     return L.s("환경",           "Environment")
        case .load:            return L.s("훈련량",         "Load")
        case .intervalQuality: return L.s("인터벌 수행",    "Intervals")
        case .recovery:        return L.s("회복",           "Recovery")
        case .fadeCause:       return L.s("후반 감속 원인", "Fade Cause")
        }
    }
}

// MARK: - Category Icon

extension InsightCategory {
    var icon: String {
        switch self {
        case .cardio:      return "lungs.fill"
        case .intensity:   return "gauge.with.needle"
        case .form:        return "figure.run"
        case .endurance:   return "chart.line.uptrend.xyaxis"
        case .efficiency:  return "bolt.heart"
        case .environment:     return "thermometer.medium"
        case .load:            return "calendar"
        case .intervalQuality: return "repeat"
        case .recovery:        return "arrow.down.heart"
        case .fadeCause:       return "arrow.down.right.circle"
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
                Text(insight.category.localizedLabel)
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
    var workoutTypeLabel: String? = nil
    var isAutoDetected: Bool = false

    // Additional inputs for the tab card
    var activity: Activity? = nil
    var detail: ActivityDetail? = nil
    var history: [Activity] = []
    var age: Int? = nil
    var isMale: Bool? = nil
    var hrZones: [HRZoneData] = []
    var workoutTypeFn: ((UUID) -> WorkoutType?)? = nil
    var hrZonesFn: ((UUID) -> [HRZoneData]?)? = nil
    var isBackfilling: Bool = false
    var isClassifying: Bool = false
    var cadenceSeries: [(offset: TimeInterval, value: Double)] = []
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    var formBaseline: RunningFormBaseline? = nil
    var formBackfillProgress: (done: Int, total: Int)? = nil
    var heatModel: MRHeatModel? = nil
    var heatHRModel: MRHeatHRModel? = nil
    var formShifts: [MRFormShift] = []
    /// 이 러닝의 케이던스 잔차 — 폼 카드 추세 문단 마무리용
    var formRunCadenceResidual: Double? = nil
    var weatherSnapshot: WeatherSnapshot? = nil
    var confirmedRace: PersistedRaceMatch? = nil
    var confirmedRaces: [PersistedRaceMatch] = []
    var raceDetailFn: ((UUID) -> ActivityDetail?)? = nil
    /// 강도(sRPE) 조회 인덱스 — 퍼포먼스 탭의 7일 강도 부하용. 없으면 해당 반쪽 생략.
    var effortIndex: EffortIndex? = nil
    /// 이지 페이스 조회값 — 총평 심박 줄이 다음 이지런 페이스를 숫자로 제안할 때 쓴다.
    var easyPaceLookup: MRHRPaceLookup? = nil
    /// 이번 주 대회 플랜 단계("회복"/"테이퍼"/…) — 총평 훈련부하 줄의 다음 행동을 우선한다.
    var planPhase: String? = nil

    var body: some View {
        if !insights.isEmpty, let act = activity {
            RunInsightTabCard(
                activity: act,
                detail: detail,
                history: history,
                age: age,
                isMale: isMale,
                hrZones: hrZones,
                insights: insights,
                workoutTypeLabel: workoutTypeLabel,
                isAutoDetected: isAutoDetected,
                workoutTypeFn: workoutTypeFn,
                isBackfilling: isBackfilling,
                isClassifying: isClassifying,
                cadenceSeries: cadenceSeries,
                hrSamples: hrSamples,
                formBaseline: formBaseline,
                formBackfillProgress: formBackfillProgress,
                heatModel: heatModel,
                heatHRModel: heatHRModel,
                formShifts: formShifts,
                formRunCadenceResidual: formRunCadenceResidual,
                weatherSnapshot: weatherSnapshot,
                confirmedRace: confirmedRace,
                confirmedRaces: confirmedRaces,
                raceDetailFn: raceDetailFn,
                hrZonesFn: hrZonesFn,
                effortIndex: effortIndex,
                easyPaceLookup: easyPaceLookup,
                planPhase: planPhase
            )
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
