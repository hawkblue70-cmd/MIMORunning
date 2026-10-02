import SwiftUI
import Charts

/// 성장 탭 '안정시 심박' — 큰 숫자는 최근 90일 중앙값, 선은 달마다 중앙값, 점선은 12개월 이동평균(계절을 지운 추세).
/// 방향 판정은 하지 않는다 — 오르내림의 일반 원인만 늘 같은 문장으로(앱은 부상·생활을 모른다, 2026-10-02 사용자 결정).
/// 값은 엔진(`mrRestingHRTrend`)이 내고 여기선 그리기만. 표본 부족이면 GrowthView가 카드를 빼낸다.
/// 카드 모양은 `ThresholdTrendCard`(바탕·모서리·제목·본문·근거 글자)와 같게.
struct RestingHRTrendCard: View {
    let trend: MRRestingHRTrend

    var body: some View {
        let L = AppLanguage.shared
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "heart")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mrInk3)
                Text(L.s("안정시 심박", "Resting HR"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(trend.recent.rounded()))bpm")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.heartRate)
                Text(L.s(" · 최근 90일 중앙값", " · last 90-day median"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mrInk2)
                if let ly = trend.recentLY {
                    Text(L.s(" · 1년 전 같은 기간 \(Int(ly.rounded()))", " · same period last yr \(Int(ly.rounded()))"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mrInk3)
                }
            }

            // 판정 없이 일반 원인만 — 부상·생활은 앱이 모르니 본인이 그래프와 맞춰 본다(2026-10-02 사용자 결정)
            Text(MRRestingHRTrend.explainer)
                .font(.system(size: 12))
                .foregroundStyle(Color.mrInk2)
                .fixedSize(horizontal: false, vertical: true)

            chart
                .frame(height: 100)

            Text(L.s("선: 달마다 안정시 심박 중앙값\(trend.rolling.isEmpty ? "" : " · 점선: 12개월 평균(계절 영향을 지운 추세)") · 겨울에 몇 bpm 오르는 계절 흔들림이 있습니다",
                     "Line: monthly resting HR median\(trend.rolling.isEmpty ? "" : " · dashed: 12-month average (season removed)") · it rises a few bpm in winter"))
                .font(.system(size: 11))
                .foregroundStyle(Color.mrInk3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// y축 — 선과 이동평균이 모두 들어오게, 최소 ±5bpm(문헌 효과 4~6bpm이 눈에 보이되 과장되지 않는 폭).
    private var yDomain: ClosedRange<Double> {
        let v = trend.months.map(\.median) + trend.rolling.map(\.bpm)
        guard let lo = v.min(), let hi = v.max() else { return 0...1 }
        let mid = (lo + hi) / 2, half = max((hi - lo) / 2 + 1, 5)
        return (mid - half)...(mid + half)
    }

    private var chart: some View {
        Chart {
            ForEach(trend.months, id: \.month) { m in
                LineMark(x: .value("month", m.month), y: .value("bpm", m.median),
                         series: .value("s", "monthly"))
                    .foregroundStyle(Theme.heartRate)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("month", m.month), y: .value("bpm", m.median))
                    .foregroundStyle(Theme.heartRate)
                    .symbolSize(Theme.sparkHaloCoreSizeCompact)
            }
            ForEach(trend.rolling, id: \.date) { p in
                LineMark(x: .value("month", p.date), y: .value("bpm", p.bpm),
                         series: .value("s", "rolling"))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text("\(Int(d))").font(.system(size: 9)).foregroundStyle(Color.mrInk3)
                    }
                }
            }
        }
        .chartXScale(range: .plotDimension(padding: 14))
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: trend.months.count > 12 ? 4 : 2)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.mrInk3)
            }
        }
    }
}
