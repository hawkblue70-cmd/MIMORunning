import SwiftUI
import Charts

/// 성장 탭 "기록 카드" — 거리·시간·부하·페이스를 **하나의 x축** 위에서 지표 토글로 전환한다.
/// 막대 색은 항상 그날(그 주/그 달)의 평균 강도. 강도 기록이 없으면 회색.
/// 페이스 모드는 기간 자체의 거리 가중 평균 페이스를 0선으로, 위로 갈수록 빠르다.
struct RecordBarChart: View {
    let bars: [RecordBar]
    let metric: RecordMetric
    let period: RecordPeriod
    let start: Date
    let end: Date
    let paceBaseline: Double?
    /// 표시할 기록이 없을 때 문구 (nil이면 기본 문구)
    var emptyMessage: String? = nil

    @State private var selected: Date? = nil

    private var L: AppLanguage { AppLanguage.shared }

    // MARK: - 값

    private func value(_ bar: RecordBar) -> Double? {
        switch metric {
        case .distance: return bar.km
        case .time:     return bar.minutes
        case .load:     return bar.au
        case .pace:
            guard let base = paceBaseline else { return nil }
            return RecordSeries.paceDelta(bar, baseline: base)
        }
    }

    private var hasData: Bool {
        switch metric {
        case .distance: return bars.contains { $0.km > 0 }
        case .time:     return bars.contains { $0.minutes > 0 }
        case .load:     return bars.contains { $0.au > 0 }
        case .pace:     return paceBaseline != nil && bars.contains { $0.paceSec != nil }
        }
    }

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

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if hasData {
                chart
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
    }

    // MARK: - 헤더 (선택 말풍선 + 강도 범례)

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            if let bar = selectedBar, bar.runCount > 0 {
                Text(calloutText(bar))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else if metric == .pace, let base = paceBaseline {
                Text(L.s("기간 평균 \(paceText(base))", "Period average \(paceText(base))"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text(" ").font(.system(size: 11))
            }
            Spacer(minLength: 6)
            legend
        }
    }

    private var legend: some View {
        VStack(alignment: .trailing, spacing: 3) {
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
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 7, height: 7)
                Text(L.s("기록 없음", "Not rated"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 차트

    private var chart: some View {
        Chart {
            ForEach(bars) { bar in
                if let v = value(bar) {
                    BarMark(
                        x: .value(L.s("기간", "Period"), bar.id, unit: xUnit),
                        yStart: .value(L.s("기준", "Base"), 0),
                        yEnd: .value(metricAxisName, v)
                    )
                    .foregroundStyle(barColor(bar).gradient)
                    .opacity(barOpacity(bar))
                    .cornerRadius(2)
                }
            }
            if metric == .pace {
                RuleMark(y: .value(L.s("평균", "Average"), 0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
        }
        .frame(height: 180)
        .chartXScale(domain: start...end)
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(xLabel(d)).font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    Text(yLabel(value.as(Double.self) ?? 0)).font(.caption2)
                }
                AxisGridLine()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metricAxisName)
    }

    private func barColor(_ bar: RecordBar) -> Color {
        guard let mean = bar.meanEffort else { return Color.secondary.opacity(0.45) }
        return EffortPalette.color(for: EffortResolver.clamp(mean))
    }

    private func barOpacity(_ bar: RecordBar) -> Double {
        guard let sel = selectedBar else { return 1 }
        return sel.id == bar.id ? 1 : 0.55
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

    private func yLabel(_ v: Double) -> String {
        switch metric {
        case .distance, .time:
            return String(format: "%.0f", v)
        case .load:
            return v.rounded().formatted(.number.grouping(.automatic))
        case .pace:
            let s = Int(v.rounded())
            return s == 0 ? "0" : String(format: "%+ds", s)
        }
    }

    private var metricAxisName: String {
        switch metric {
        case .distance: return L.s("거리(km)", "Distance (km)")
        case .time:     return L.s("시간(분)", "Time (min)")
        case .load:     return L.s("부하(AU)", "Load (AU)")
        case .pace:     return L.s("평균 대비(초)", "vs average (s)")
        }
    }

    // MARK: - 말풍선

    private func calloutText(_ bar: RecordBar) -> String {
        var parts: [String] = [dateLabel(bar)]
        if bar.km > 0 { parts.append(String(format: "%.2fkm", bar.km)) }
        if bar.minutes > 0 { parts.append(minutesText(bar.minutes)) }
        if let p = bar.paceSec { parts.append(paceText(p)) }
        if let e = bar.meanEffort {
            parts.append(L.s("강도 \(effortText(e))", "effort \(effortText(e))"))
        }
        if bar.au > 0 { parts.append("\(Int(bar.au.rounded())) AU") }
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

    private func effortText(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
    }

    private func minutesText(_ mins: Double) -> String {
        let total = Int(mins.rounded())
        let h = total / 60, m = total % 60
        if L.isEnglish { return h > 0 ? "\(h)h \(m)m" : "\(m)m" }
        return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
    }

    private func paceText(_ sec: Double) -> String {
        let t = Int(sec.rounded())
        return String(format: "%d'%02d\"", t / 60, t % 60)
    }
}
