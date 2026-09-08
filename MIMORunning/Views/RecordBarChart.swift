import SwiftUI
import Charts

/// 성장 탭 "기록 카드" — **하나의 차트**에 거리 막대(색 = 그 구간 평균 강도)와
/// 페이스 ● · 강도 부하 ▲ · 평균 심박 ■ 세 선을 겹쳐 보여 준다.
///
/// 선은 각자 단위가 다르므로 **최근 12개월 개인 범위(`RecordSeries.MetricRanges`)로 0~1 정규화**한 뒤
/// 막대와 같은 km 좌표계에 올린다 → 축이 하나뿐이라 화면이 조용하다.
/// 페이스는 뒤집어(위 = 빠름) 그린다. 정확한 값은 헤더 칩(기간 요약)과 탭 말풍선(구간별)에 있다.
struct RecordBarChart: View {
    let bars: [RecordBar]
    let period: RecordPeriod
    let start: Date
    let end: Date
    /// 선 정규화 기준 — 최근 12개월 개인 범위
    let ranges: RecordSeries.MetricRanges
    /// 표시할 기록이 없을 때 문구 (nil이면 기본 문구)
    var emptyMessage: String? = nil

    /// 막대·세 선이 함께 보는 단 하나의 선택 상태
    @State private var selected: Date? = nil

    @AppStorage("growth.record.showPace") private var showPace = true
    @AppStorage("growth.record.showLoad") private var showLoad = true
    @AppStorage("growth.record.showHR")   private var showHR = true

    private var L: AppLanguage { AppLanguage.shared }

    // MARK: - 레이아웃 상수 (§5.8 — 값은 여기 한 곳에서만)

    private enum Metrics {
        static let plotHeight: CGFloat = 180
        /// 선이 차지하는 세로 띠 — 막대 꼭대기·바닥에 붙지 않게 여유를 둔다.
        static let lineFloor: Double = 0.08
        static let lineSpan: Double = 0.84
        static let symbolSize: CGFloat = 28
        static let lineWidth: CGFloat = 1.5
        static let lineOpacity: Double = 0.85
        static let dimmed: Double = 0.55
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

    /// 막대 y축 꼭대기 — 선도 이 좌표계 안에 산다.
    private var kmAxisTop: Double { max(1, bars.map(\.km).max() ?? 0) }

    private var yDomain: ClosedRange<Double> { 0...(kmAxisTop * 1.08) }

    // MARK: - 선 정의

    private struct LinePoint: Identifiable {
        let id: Date
        let y: Double        // 이미 km 좌표로 환산된 값
    }

    private struct LineSpec: Identifiable {
        let id: String       // 계열 이름 (= 범례 라벨)
        let color: Color
        let symbol: BasicChartSymbolShape
        let points: [LinePoint]
    }

    /// 0~1 정규화 값을 막대 좌표계(km)로 옮긴다.
    private func toKmSpace(_ unit: Double) -> Double {
        kmAxisTop * (Metrics.lineFloor + Metrics.lineSpan * unit)
    }

    private func points(_ value: @escaping (RecordBar) -> Double?,
                        range: ClosedRange<Double>?,
                        inverted: Bool) -> [LinePoint] {
        guard let range else { return [] }
        return bars.compactMap { bar in
            guard let v = value(bar) else { return nil }
            return LinePoint(id: bar.id,
                             y: toKmSpace(RecordSeries.normalized(v, in: range, inverted: inverted)))
        }
    }

    private var paceName: String { L.s("페이스", "Pace") }
    private var loadName: String { L.s("부하", "Load") }
    private var hrName: String { L.s("심박", "HR") }

    private var pacePoints: [LinePoint] {
        points({ $0.paceSec }, range: ranges.pace, inverted: true)
    }

    private var loadPoints: [LinePoint] {
        points({ $0.au > 0 ? $0.au : nil }, range: ranges.au, inverted: false)
    }

    private var hrPoints: [LinePoint] {
        points({ $0.avgHR }, range: ranges.hr, inverted: false)
    }

    private var lineSpecs: [LineSpec] {
        var specs: [LineSpec] = []
        if showPace, !pacePoints.isEmpty {
            specs.append(LineSpec(id: paceName, color: Theme.pace, symbol: .circle, points: pacePoints))
        }
        if showLoad, !loadPoints.isEmpty {
            specs.append(LineSpec(id: loadName, color: Theme.violet, symbol: .triangle, points: loadPoints))
        }
        if showHR, !hrPoints.isEmpty {
            specs.append(LineSpec(id: hrName, color: Theme.heartRate, symbol: .square, points: hrPoints))
        }
        return specs
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            calloutRow
            chipRow
            if hasData {
                chart
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

    // MARK: - 헤더 ① 선택 말풍선

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

    // MARK: - 헤더 ② 선 토글 칩 + 강도 색 범례

    private var chipRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                chip(symbol: "●", name: paceName, value: paceChipValue,
                     color: Theme.pace, isOn: showPace, enabled: !pacePoints.isEmpty) {
                    showPace.toggle()
                }
                chip(symbol: "▲", name: loadName, value: loadChipValue,
                     color: Theme.violet, isOn: showLoad, enabled: !loadPoints.isEmpty) {
                    showLoad.toggle()
                }
                chip(symbol: "■", name: hrName, value: hrChipValue,
                     color: Theme.heartRate, isOn: showHR, enabled: !hrPoints.isEmpty) {
                    showHR.toggle()
                }
                Spacer(minLength: 0)
            }
            effortLegend
        }
    }

    private func chip(symbol: String, name: String, value: String?,
                      color: Color, isOn: Bool, enabled: Bool,
                      action: @escaping () -> Void) -> some View {
        let active = isOn && enabled
        return Button(action: action) {
            HStack(spacing: 3) {
                Text(symbol).font(.system(size: 8))
                Text(name).font(.system(size: 10, weight: .semibold))
                Text(value ?? "—")
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(active ? color : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background((active ? color : Color.secondary).opacity(active ? 0.16 : 0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel("\(name) \(value ?? "")")
        .accessibilityValue(active ? L.s("켬", "on") : L.s("끔", "off"))
    }

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
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 7, height: 7)
                Text(L.s("기록 없음", "Not rated"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var paceChipValue: String? {
        guard let mean = summary.meanPaceSec else { return nil }
        return paceText(mean)
    }

    private var loadChipValue: String? {
        guard summary.totalAU > 0 else { return nil }
        return "\(summary.totalAU.rounded().formatted(.number.grouping(.automatic))) AU"
    }

    private var hrChipValue: String? {
        guard let hr = summary.meanHR else { return nil }
        return "\(Int(hr.rounded())) bpm"
    }

    // MARK: - 차트 (막대 + 세 선 = 하나)

    private var chart: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value(L.s("기간", "Period"), bar.id, unit: xUnit),
                    yStart: .value(L.s("기준", "Base"), 0),
                    yEnd: .value(L.s("거리(km)", "Distance (km)"), bar.km)
                )
                .foregroundStyle(barColor(bar).gradient)
                .opacity(dim(bar.id))
                .cornerRadius(2)
            }

            if let sel = selectedBar {
                RuleMark(x: .value(L.s("기간", "Period"), sel.id, unit: xUnit))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }

            ForEach(lineSpecs) { spec in
                ForEach(spec.points) { p in
                    LineMark(
                        x: .value(L.s("기간", "Period"), p.id, unit: xUnit),
                        y: .value(spec.id, p.y),
                        series: .value(L.s("계열", "Series"), spec.id)
                    )
                    .foregroundStyle(spec.color.opacity(Metrics.lineOpacity))
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
                ForEach(spec.points) { p in
                    PointMark(
                        x: .value(L.s("기간", "Period"), p.id, unit: xUnit),
                        y: .value(spec.id, p.y)
                    )
                    .symbol(spec.symbol)
                    .symbolSize(Metrics.symbolSize)
                    .foregroundStyle(spec.color)
                    .opacity(dim(p.id))
                }
            }
        }
        .frame(height: Metrics.plotHeight)
        .chartXScale(domain: start...end)
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    Text(kmAxisLabel(value.as(Double.self) ?? 0))
                        .font(.system(size: 9))
                }
                AxisGridLine()
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(xLabel(d)).font(.caption2)
                    }
                }
            }
        }
    }

    private var footnote: some View {
        Text(L.s("선은 최근 12개월 개인 범위로 정규화한 추세예요 · 페이스는 위가 빠름",
                 "Lines are trends normalized to your 12-month range · pace: higher = faster"))
            .font(.system(size: 8.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 색·강조

    private func barColor(_ bar: RecordBar) -> Color {
        guard let mean = bar.meanEffort else { return Color.secondary.opacity(0.45) }
        return EffortPalette.color(for: EffortResolver.clamp(mean))
    }

    /// 선택된 구간만 진하게 — 막대와 세 선이 함께 흐려진다.
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
        let s = summary
        var parts = [L.s("거리 막대와 페이스·부하·심박 추세선",
                         "Distance bars with pace, load and heart-rate trend lines"),
                     kmText(s.totalKm),
                     L.s("\(s.runCount)회", "\(s.runCount) runs")]
        if let p = paceChipValue { parts.append(L.s("평균 페이스 \(p)", "average pace \(p)")) }
        if let l = loadChipValue { parts.append(l) }
        if let h = hrChipValue { parts.append(L.s("평균 심박 \(h)", "average heart rate \(h)")) }
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
