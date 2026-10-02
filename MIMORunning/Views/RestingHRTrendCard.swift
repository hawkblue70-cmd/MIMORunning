import SwiftUI
import Charts

/// 성장 탭 '안정시 심박' — 큰 숫자는 최근 90일 중앙값, 선은 달마다 중앙값, 점선은 기준(러닝 시작 전 또는 조회 창 첫 90일).
/// 값은 엔진(`mrRestingHRTrend`)이 내고 여기선 그리기만. 표본 부족이면 GrowthView가 카드를 빼낸다.
/// 카드 모양은 `ThresholdTrendCard`(바탕·모서리·제목·본문·근거 글자)와 같게.
struct RestingHRTrendCard: View {
    let trend: MRRestingHRTrend

    private var baselineLabel: String? {
        let L = AppLanguage.shared
        switch trend.baselineKind {
        case .beforeRunning: return L.s("러닝 시작 전", "Before running")
        case .windowStart:
            let m = trend.monthsSinceBaseline(asOf: Date()) ?? 0
            return L.s("\(m)개월 전", "\(m) mo ago")
        case nil: return nil
        }
    }

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
                if let b = trend.baseline, let label = baselineLabel {
                    Text(L.s(" · \(label) \(Int(b.rounded()))", " · \(label) \(Int(b.rounded()))"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mrInk3)
                }
            }

            if let s = trend.sentence(asOf: Date()) {
                Text(s)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.positive)
            }

            chart
                .frame(height: 100)

            Text(L.s("선: 달마다 안정시 심박 중앙값\(baselineLabel.map { " · 점선: \($0)" } ?? "") · 계절과 훈련량에 따라 몇 bpm씩 움직입니다",
                     "Line: monthly resting HR median\(baselineLabel.map { " · dashed: \($0)" } ?? "") · varies a few bpm with season and training load"))
                .font(.system(size: 11))
                .foregroundStyle(Color.mrInk3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// y축 — 선과 기준이 모두 들어오게, 최소 ±5bpm(문헌 효과 4~6bpm이 눈에 보이되 과장되지 않는 폭).
    private var yDomain: ClosedRange<Double> {
        let v = trend.months.map(\.median) + [trend.baseline].compactMap { $0 }
        guard let lo = v.min(), let hi = v.max() else { return 0...1 }
        let mid = (lo + hi) / 2, half = max((hi - lo) / 2 + 1, 5)
        return (mid - half)...(mid + half)
    }

    private var chart: some View {
        Chart {
            if let b = trend.baseline {
                RuleMark(y: .value("baseline", b))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(trend.months, id: \.month) { m in
                LineMark(x: .value("month", m.month), y: .value("bpm", m.median))
                    .foregroundStyle(Theme.heartRate)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("month", m.month), y: .value("bpm", m.median))
                    .foregroundStyle(Theme.heartRate)
                    .symbolSize(Theme.sparkHaloCoreSizeCompact)
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
