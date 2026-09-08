import SwiftUI
import Charts

/// 성장 탭 "기록 카드" — **두 줄을 위아래로 쌓아** 각자 **실제 축**으로 보여 준다.
///
/// 1. 거리 — 막대(색 = 그 구간 평균 강도), y축 km
/// 2. 페이스 — 선 + 점(색 = 강도), y축 실제 페이스(**뒤집어서 위 = 빠름**), 평균 점선
///
/// 정규화·칩·부하 선·심박 줄은 없다. 부하는 막대 길이 × 색이, 심박은 페이스가 대체로 말해 준다(정확한 bpm은 말풍선).
/// 두 줄은 같은 x 스케일·같은 축 여백을 쓰고, **한 번의 탭이 두 줄을 동시에 강조**한다.
struct RecordBarChart: View {
    let bars: [RecordBar]
    let period: RecordPeriod
    let start: Date
    let end: Date
    /// 표시할 기록이 없을 때 문구 (nil이면 기본 문구)
    var emptyMessage: String? = nil

    /// 세 줄이 함께 보는 단 하나의 선택 상태
    @State private var selected: Date? = nil

    private var L: AppLanguage { AppLanguage.shared }

    // MARK: - 레이아웃 상수 (§5.8 — 값은 여기 한 곳에서만)

    private enum Metrics {
        static let distanceHeight: CGFloat = 110
        static let trendHeight: CGFloat = 70
        /// 세 줄의 y축 라벨 폭 — 같아야 줄이 세로로 정렬된다.
        static let gutter: CGFloat = 40
        static let symbolSize: CGFloat = 26
        static let lineWidth: CGFloat = 1.5
        static let lineOpacity: Double = 0.6
        static let dimmed: Double = 0.55
        /// 페이스 축 위아래 여유 (초/km)
        static let pacePad: Double = 10
    }

    // MARK: - 파생 값

    private var summary: RecordSeries.Summary { RecordSeries.summary(bars) }

    private var hasData: Bool { bars.contains { $0.runCount > 0 } }

    private var xUnit: Calendar.Component {
        switch period {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    private var selectedBar: RecordBar? {
        guard let s = selected else { return nil }
        return bars.first { s >= $0.id && s < $0.end }
    }

    // MARK: - 줄 정의

    private enum Lane { case distance, pace }

    /// x 라벨은 **맨 아래 보이는 줄에만** 붙는다.
    private var bottomLane: Lane {
        if paceDomain != nil { return .pace }
        return .distance
    }

    private struct TrendPoint: Identifiable {
        let id: Date
        let y: Double
        let color: Color
    }

    /// 값이 이어지는 구간만 선으로 잇는다 (빈 버킷을 건너뛰며 잇지 않는다).
    private struct TrendSegment: Identifiable {
        let id: Int
        let points: [TrendPoint]
    }

    private func segments(_ value: (RecordBar) -> Double?) -> [TrendSegment] {
        var result: [TrendSegment] = []
        var current: [TrendPoint] = []
        for bar in bars {
            if let v = value(bar) {
                current.append(TrendPoint(id: bar.id, y: v, color: barColor(bar)))
            } else if !current.isEmpty {
                result.append(TrendSegment(id: result.count, points: current))
                current = []
            }
        }
        if !current.isEmpty { result.append(TrendSegment(id: result.count, points: current)) }
        return result
    }

    // MARK: - 축 범위

    private var kmDomain: ClosedRange<Double> {
        0...(max(1, bars.map(\.km).max() ?? 0) * 1.08)
    }

    private var paceValues: [Double] { bars.compactMap(\.paceSec) }

    /// **페이스 축 뒤집기** — 값은 `-paceSec`로 그리고 라벨은 `abs`로 되돌린다.
    /// 그래서 위로 갈수록 초/km가 작아진다 = 빠르다.
    private var paceDomain: ClosedRange<Double>? {
        guard let fastest = paceValues.min(), let slowest = paceValues.max() else { return nil }
        return (-slowest - Metrics.pacePad)...(-fastest + Metrics.pacePad)
    }


    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasData {
                calloutRow
                effortLegend
                distanceLane
                paceLane
                footnote
            } else {
                Text(emptyMessage ?? L.s("이 기간에 기록이 없어요", "No records in this period"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - 헤더 ① 선택 말풍선 (세 줄이 함께 쓰는 하나)

    private var calloutRow: some View {
        HStack(alignment: .top, spacing: 8) {
            if let bar = selectedBar, bar.runCount > 0 {
                Text(calloutText(bar))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                Text(L.s("구간을 탭하면 정확한 값이 보여요", "Tap a bucket for exact values"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
        }
    }

    // MARK: - 헤더 ② 강도 색 범례

    private var effortLegend: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                Text(L.s("강도", "Effort"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
                ForEach(Array(EffortPalette.colors.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(c)
                        .frame(width: 7, height: 7)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 줄 하나를 만드는 단 하나의 빌더 (§5.8 — 축·선택·강조 코드는 여기에만)

    private func lane<C: ChartContent>(title: String,
                                       trailing: String?,
                                       height: CGFloat,
                                       yDomain: ClosedRange<Double>,
                                       yLabel: @escaping (Double) -> String,
                                       showsXAxis: Bool,
                                       @ChartContentBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Chart {
                content()
                if let sel = selectedBar {
                    RuleMark(x: .value(periodName, sel.id, unit: xUnit))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
            }
            .frame(height: height)
            .chartXScale(domain: start...end)
            .chartYScale(domain: yDomain)
            .chartLegend(.hidden)
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        Text(yLabel(value.as(Double.self) ?? 0))
                            .font(.system(size: 9))
                            .frame(width: Metrics.gutter, alignment: .trailing)
                    }
                    AxisGridLine()
                }
            }
            .modifier(LaneXAxis(shows: showsXAxis, values: xAxisValues, label: xLabel))
        }
    }

    /// x 라벨은 맨 아래 줄에만 — 위 줄은 축 자체를 숨긴다.
    private struct LaneXAxis: ViewModifier {
        let shows: Bool
        let values: AxisMarkValues
        let label: (Date) -> String

        func body(content: Content) -> some View {
            if shows {
                content.chartXAxis {
                    AxisMarks(values: values) { value in
                        AxisValueLabel {
                            if let d = value.as(Date.self) {
                                Text(label(d)).font(.caption2)
                            }
                        }
                    }
                }
            } else {
                content.chartXAxis(.hidden)
            }
        }
    }

    // MARK: - 줄 ① 거리

    private var distanceLane: some View {
        lane(title: L.s("거리", "Distance"),
             trailing: distanceTrailing,
             height: Metrics.distanceHeight,
             yDomain: kmDomain,
             yLabel: kmAxisLabel,
             showsXAxis: bottomLane == .distance) {
            ForEach(bars) { bar in
                BarMark(
                    x: .value(periodName, bar.id, unit: xUnit),
                    yStart: .value(L.s("기준", "Base"), 0),
                    yEnd: .value(L.s("거리(km)", "Distance (km)"), bar.km)
                )
                .foregroundStyle(barColor(bar).gradient)
                .opacity(dim(bar.id))
                .cornerRadius(2)
            }
        }
    }

    // MARK: - 줄 ② 페이스 (뒤집힌 실제 축)

    @ViewBuilder
    private var paceLane: some View {
        if let domain = paceDomain {
            lane(title: L.s("페이스", "Pace"),
                 trailing: paceTrailing,
                 height: Metrics.trendHeight,
                 yDomain: domain,
                 yLabel: { paceText(abs($0)) },
                 showsXAxis: bottomLane == .pace) {
                trendMarks(segments { $0.paceSec.map { -$0 } },
                           seriesName: L.s("페이스", "Pace"),
                           lineColor: Theme.pace.opacity(Metrics.lineOpacity),
                           baseline: RecordSeries.paceBaseline(bars).map { -$0 },
                           baselineLabel: paceBaselineLabel)
            }
        }
    }

    /// 페이스 줄의 마크 묶음 — 평균 점선 + 이어진 구간 선 + 강도색 점.
    @ChartContentBuilder
    private func trendMarks(_ segs: [TrendSegment],
                            seriesName: String,
                            lineColor: Color,
                            baseline: Double?,
                            baselineLabel: String) -> some ChartContent {
        if let baseline {
            RuleMark(y: .value(seriesName, baseline))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary.opacity(0.45))
                .annotation(position: .top, alignment: .trailing, spacing: 1) {
                    Text(baselineLabel)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                }
        }
        ForEach(segs) { seg in
            ForEach(seg.points) { p in
                LineMark(
                    x: .value(periodName, p.id, unit: xUnit),
                    y: .value(seriesName, p.y),
                    series: .value(L.s("구간", "Segment"), seg.id)
                )
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
        }
        ForEach(segs) { seg in
            ForEach(seg.points) { p in
                PointMark(
                    x: .value(periodName, p.id, unit: xUnit),
                    y: .value(seriesName, p.y)
                )
                .symbolSize(Metrics.symbolSize)
                .foregroundStyle(p.color)
                .opacity(dim(p.id))
            }
        }
    }

    private var footnote: some View {
        Text(L.s("막대·점 색 = 강도 · 페이스는 위가 빠름",
                 "Bar and dot color = effort · pace: higher = faster"))
            .font(.system(size: 8.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 줄 오른쪽 요약

    private var distanceTrailing: String {
        "\(kmText(summary.totalKm)) · \(L.s("\(summary.runCount)회", "\(summary.runCount) runs"))"
    }

    private var paceTrailing: String? {
        guard let mean = summary.meanPaceSec else { return nil }
        var parts = [L.s("평균 \(paceText(mean))", "avg \(paceText(mean))")]
        if let best = summary.bestPaceSec {
            parts.append(L.s("가장 빠른 \(paceText(best))", "best \(paceText(best))"))
        }
        return parts.joined(separator: " · ")
    }

    private var paceBaselineLabel: String {
        guard let mean = RecordSeries.paceBaseline(bars) else { return "" }
        return L.s("평균 \(paceText(mean))", "avg \(paceText(mean))")
    }

    // MARK: - 색·강조

    private var periodName: String { L.s("기간", "Period") }

    private func barColor(_ bar: RecordBar) -> Color {
        guard let mean = bar.meanEffort else { return Color.secondary.opacity(0.45) }
        return EffortPalette.color(for: EffortResolver.clamp(mean))
    }

    /// 선택된 구간만 진하게 — 세 줄이 함께 흐려진다.
    private func dim(_ id: Date) -> Double {
        guard let sel = selectedBar else { return 1 }
        return sel.id == id ? 1 : Metrics.dimmed
    }

    // MARK: - 축 라벨

    private var xAxisValues: AxisMarkValues {
        switch period {
        case .day:   return .stride(by: .day, count: 7)
        case .week:  return .stride(by: .weekOfYear, count: 1)
        case .month: return .stride(by: .month, count: 1)
        }
    }

    private func xLabel(_ d: Date) -> String {
        let cal = Calendar.current
        switch period {
        case .day, .week:
            let c = cal.dateComponents([.month, .day], from: d)
            return "\(c.month ?? 1)/\(c.day ?? 1)"
        case .month:
            let m = cal.component(.month, from: d)
            if L.isEnglish {
                let df = DateFormatter(); df.locale = Locale(identifier: "en_US"); df.dateFormat = "MMM"
                return df.string(from: d)
            }
            return "\(m)월"
        }
    }

    private func kmAxisLabel(_ v: Double) -> String {
        v < 10 && v != v.rounded() ? String(format: "%.1f", v) : String(format: "%.0f", v)
    }

    // MARK: - 말풍선

    private func calloutText(_ bar: RecordBar) -> String {
        var parts: [String] = [dateLabel(bar)]
        if period == .day {
            if bar.km > 0 { parts.append(String(format: "%.2fkm", bar.km)) }
            if bar.minutes > 0 { parts.append(clockText(bar.minutes)) }
            if let e = bar.meanEffort {
                parts.append(L.s("강도 \(effortText(e))", "effort \(effortText(e))"))
            }
            if bar.au > 0 { parts.append("\(Int(bar.au.rounded())) AU") }
            if let p = bar.paceSec { parts.append(paceText(p)) }
        } else {
            if bar.km > 0 { parts.append(kmText(bar.km)) }
            if bar.runCount > 0 { parts.append(L.s("\(bar.runCount)회", "\(bar.runCount) runs")) }
            if bar.au > 0 {
                let au = bar.au.rounded().formatted(.number.grouping(.automatic))
                parts.append("\(au) AU")
            }
            if let p = bar.paceSec {
                parts.append(L.s("평균 \(paceText(p))", "avg \(paceText(p))"))
            }
        }
        if let hr = bar.avgHR { parts.append("\(Int(hr.rounded())) bpm") }
        return parts.joined(separator: " · ")
    }

    private func dateLabel(_ bar: RecordBar) -> String {
        let cal = Calendar.current
        switch period {
        case .day:
            let c = cal.dateComponents([.month, .day], from: bar.id)
            return "\(c.month ?? 1)/\(c.day ?? 1)"
        case .week:
            let last = cal.date(byAdding: .day, value: -1, to: bar.end) ?? bar.end
            let a = cal.dateComponents([.month, .day], from: bar.id)
            let b = cal.dateComponents([.month, .day], from: last)
            return "\(a.month ?? 1)/\(a.day ?? 1)–\(b.month ?? 1)/\(b.day ?? 1)"
        case .month:
            return xLabel(bar.id)
        }
    }

    // MARK: - 접근성

    private var accessibilitySummary: String {
        guard hasData else {
            return emptyMessage ?? L.s("이 기간에 기록이 없어요", "No records in this period")
        }
        var parts = [L.s("거리 막대 · 페이스 두 줄 차트",
                         "Two stacked lanes: distance bars and pace"),
                     distanceTrailing]
        if let p = paceTrailing { parts.append(L.s("페이스 \(p)", "pace \(p)")) }
        return parts.joined(separator: ", ")
    }

    // MARK: - 표기

    private func effortText(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
    }

    private func kmText(_ km: Double) -> String {
        km >= 100 ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
    }

    /// 하루 말풍선용 실제 시계 표기 — 36:18 / 1:02:04
    private func clockText(_ mins: Double) -> String {
        let total = Int((mins * 60).rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func paceText(_ sec: Double) -> String {
        let t = Int(sec.rounded())
        return String(format: "%d'%02d\"", t / 60, t % 60)
    }
}
