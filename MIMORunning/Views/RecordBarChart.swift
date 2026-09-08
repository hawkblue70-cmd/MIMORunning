import SwiftUI
import Charts

/// 성장 탭 "기록 카드" — 거리·강도 부하·페이스 **세 줄을 하나의 x축** 위에 겹쳐 보여 준다.
/// 지표 토글 없이 항상 셋 다 보이고, 한 번의 탭이 세 줄을 동시에 강조한다.
/// 막대 색은 그날(그 주/그 달)의 평균 강도. 강도 기록이 없으면 회색.
/// 페이스 줄은 기간 자체의 거리 가중 평균 페이스를 0선으로, 위로 갈수록 빠르다.
struct RecordBarChart: View {
    let bars: [RecordBar]
    let period: RecordPeriod
    let start: Date
    let end: Date
    let paceBaseline: Double?
    /// 표시할 기록이 없을 때 문구 (nil이면 기본 문구)
    var emptyMessage: String? = nil

    /// 세 줄이 공유하는 단 하나의 선택 상태 — 세 Chart 모두 이 값에 바인딩한다.
    @State private var selected: Date? = nil

    private var L: AppLanguage { AppLanguage.shared }

    // MARK: - 레이아웃 상수 (§5.8 — 값은 여기 한 곳에서만)

    private enum Lane {
        static let distanceHeight: CGFloat = 110
        static let loadHeight: CGFloat = 60
        static let paceHeight: CGFloat = 70
        static let yLabelWidth: CGFloat = 34   // 세 줄의 플롯 시작점을 맞춘다
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

    /// 페이스 점이 있는 버킷만 (선은 이들 사이만 잇는다)
    private var pacedBars: [RecordBar] {
        guard paceBaseline != nil else { return [] }
        return bars.filter { $0.paceSec != nil }
    }

    private var hasPace: Bool { !pacedBars.isEmpty }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if hasData {
                lane(title: L.s("거리", "Distance"), trailing: distanceTotals) {
                    distanceLane
                }
                lane(title: L.s("강도 부하", "Load"), trailing: loadTotals) {
                    loadLane
                }
                lane(title: L.s("페이스", "Pace"), trailing: paceTotals) {
                    paceLane
                }
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

    // MARK: - 줄(레인) 껍데기 — 제목 + 기간 합계 + 차트

    private func lane<Content: View>(title: String,
                                     trailing: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 6)
                Text(trailing)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            content()
        }
    }

    /// 세 줄이 공유하는 차트 껍데기 — 축·도메인·선택을 한 곳에서만 정의한다(§5.8).
    @ViewBuilder
    private func laneChart<C: ChartContent>(height: CGFloat,
                                            yDomain: ClosedRange<Double>,
                                            showXAxis: Bool,
                                            yLabel: @escaping (Double) -> String,
                                            accessibility: String,
                                            @ChartContentBuilder content: () -> C) -> some View {
        let base = Chart { content() }
            .frame(height: height)
            .chartXScale(domain: start...end)
            .chartYScale(domain: yDomain)
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        Text(yLabel(value.as(Double.self) ?? 0))
                            .font(.system(size: 9))
                            .frame(width: Lane.yLabelWidth, alignment: .trailing)
                    }
                    AxisGridLine()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibility)

        if showXAxis {
            base.chartXAxis {
                AxisMarks(values: xAxisValues) { value in
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(xLabel(d)).font(.caption2)
                        }
                    }
                }
            }
        } else {
            base.chartXAxis(.hidden)
        }
    }

    // MARK: - ① 거리

    private var distanceLane: some View {
        let top = max(1, (bars.map(\.km).max() ?? 0) * 1.15)
        return laneChart(height: Lane.distanceHeight,
                         yDomain: 0...top,
                         showXAxis: false,
                         yLabel: { String(format: "%.0f", $0) },
                         accessibility: L.s("거리(km)", "Distance (km)")) {
            ForEach(bars) { bar in
                BarMark(
                    x: .value(L.s("기간", "Period"), bar.id, unit: xUnit),
                    yStart: .value(L.s("기준", "Base"), 0),
                    yEnd: .value(L.s("거리(km)", "Distance (km)"), bar.km)
                )
                .foregroundStyle(barColor(bar).gradient)
                .opacity(barOpacity(bar))
                .cornerRadius(2)
            }
        }
    }

    // MARK: - ② 강도 부하

    private var loadLane: some View {
        let top = max(10, (bars.map(\.au).max() ?? 0) * 1.15)
        return laneChart(height: Lane.loadHeight,
                         yDomain: 0...top,
                         showXAxis: false,
                         yLabel: { $0.rounded().formatted(.number.grouping(.automatic)) },
                         accessibility: L.s("강도 부하(AU)", "Load (AU)")) {
            ForEach(bars) { bar in
                BarMark(
                    x: .value(L.s("기간", "Period"), bar.id, unit: xUnit),
                    yStart: .value(L.s("기준", "Base"), 0),
                    yEnd: .value(L.s("부하(AU)", "Load (AU)"), bar.au)
                )
                .foregroundStyle(barColor(bar).gradient)
                .opacity(barOpacity(bar))
                .cornerRadius(2)
            }
        }
    }

    // MARK: - ③ 페이스 (평균 0선 대비, 위 = 빠름)

    private var paceLane: some View {
        let base = paceBaseline
        let deltas = pacedBars.compactMap { b -> Double? in
            guard let base else { return nil }
            return RecordSeries.paceDelta(b, baseline: base)
        }
        let span = max(10, (deltas.map(abs).max() ?? 0) * 1.2)
        return laneChart(height: Lane.paceHeight,
                         yDomain: (-span)...span,
                         showXAxis: true,
                         yLabel: paceAxisLabel,
                         accessibility: L.s("평균 대비 페이스(초)", "Pace vs average (s)")) {
            RuleMark(y: .value(L.s("평균", "Average"), 0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .annotation(position: .top, alignment: .trailing, spacing: 1) {
                    if let base {
                        Text(L.s("평균 \(paceText(base))", "avg \(paceText(base))"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            ForEach(pacedBars) { bar in
                if let base, let d = RecordSeries.paceDelta(bar, baseline: base) {
                    LineMark(
                        x: .value(L.s("기간", "Period"), bar.id, unit: xUnit),
                        y: .value(L.s("평균 대비(초)", "vs average (s)"), d)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Theme.pace.opacity(0.6))
                }
            }
            ForEach(pacedBars) { bar in
                if let base, let d = RecordSeries.paceDelta(bar, baseline: base) {
                    PointMark(
                        x: .value(L.s("기간", "Period"), bar.id, unit: xUnit),
                        y: .value(L.s("평균 대비(초)", "vs average (s)"), d)
                    )
                    .symbolSize(36)
                    .foregroundStyle(barColor(bar))
                    .opacity(barOpacity(bar))
                }
            }
        }
    }

    // MARK: - 색·강조

    private func barColor(_ bar: RecordBar) -> Color {
        guard let mean = bar.meanEffort else { return Color.secondary.opacity(0.45) }
        return EffortPalette.color(for: EffortResolver.clamp(mean))
    }

    /// 선택된 버킷만 진하게 — 세 줄 모두 같은 selected를 본다.
    private func barOpacity(_ bar: RecordBar) -> Double {
        guard let sel = selectedBar else { return 1 }
        return sel.id == bar.id ? 1 : 0.55
    }

    // MARK: - 기간 합계 (각 줄 오른쪽)

    private var distanceTotals: String {
        let s = summary
        guard s.runCount > 0 else { return L.s("기록 없음", "No runs") }
        return [kmText(s.totalKm),
                minutesText(s.totalMinutes),
                L.s("\(s.runCount)회", "\(s.runCount) runs")]
            .joined(separator: " · ")
    }

    private var loadTotals: String {
        let s = summary
        guard s.totalAU > 0 else {
            return L.s("강도 기록 없음", "No effort ratings")
        }
        let au = s.totalAU.rounded().formatted(.number.grouping(.automatic))
        return L.s("\(au) AU · \(s.runCount)회 중 \(s.ratedCount)회 강도 있음",
                   "\(au) AU · \(s.ratedCount) of \(s.runCount) runs rated")
    }

    private var paceTotals: String {
        let s = summary
        guard hasPace, let mean = s.meanPaceSec, let best = s.bestPaceSec else {
            return L.s("페이스 기록 없음", "No pace data")
        }
        return L.s("평균 \(paceText(mean)) · 가장 빠른 \(paceText(best))",
                   "Avg \(paceText(mean)) · Best \(paceText(best))")
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

    private func paceAxisLabel(_ v: Double) -> String {
        let s = Int(v.rounded())
        if s == 0 { return "0" }
        return s > 0 ? "+\(s)s" : "−\(-s)s"
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

    private func kmText(_ km: Double) -> String {
        km >= 100 ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
    }

    private func minutesText(_ mins: Double) -> String {
        let total = Int(mins.rounded())
        let h = total / 60, m = total % 60
        if L.isEnglish { return h > 0 ? "\(h)h \(m)m" : "\(m)m" }
        return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
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
