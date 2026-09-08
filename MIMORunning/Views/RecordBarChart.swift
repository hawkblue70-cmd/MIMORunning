import SwiftUI
import Charts

/// 성장 탭 "기록 카드" — **거리와 페이스를 한 차트에**, 각자 **실제 축**으로 보여 준다.
///
/// - 막대 = 거리, **오른쪽(trailing) 축 = km** (막대 색 = 그 구간 평균 강도)
/// - 선 + 점 = 페이스, **왼쪽(leading) 축 = 실제 페이스**(`m'ss"`, **위 = 빠름**), 평균 점선
///
/// Swift Charts는 차트당 y 스케일이 하나뿐이라 **페이스를 km 도메인 위로 매핑**한다.
/// `kmTop = max(1, 최대 km) × 1.08`, 페이스 범위 `[fast, slow]`에 대해
/// `y(pace) = kmTop × (slow − pace) / (slow − fast)` — 빠를수록 위.
/// 왼쪽 축 눈금은 이 매핑의 **역함수**로 다시 페이스 글자로 되돌려 찍는다.
///
/// 정규화·칩·부하 선·심박 줄은 없다. 부하는 막대 길이 × 색이, 심박은 페이스가 대체로 말해 준다(정확한 bpm은 말풍선).
struct RecordBarChart: View {
    let bars: [RecordBar]
    let period: RecordPeriod
    let start: Date
    let end: Date
    /// 표시할 기록이 없을 때 문구 (nil이면 기본 문구)
    var emptyMessage: String? = nil
    /// 공유 카드 내보내기 모드 — 탭 안내·선택 상호작용을 빼고 더 작게 그린다.
    /// (§5.8 — 카드용 레이아웃을 따로 만들지 않고 **이 컴포넌트 하나**를 그대로 재사용한다)
    var exportMode: Bool = false
    /// 좁은 열(퍼포먼스 카드 35:65 행의 오른쪽)용 축소 모드 — 축 머리·각주를 빼고 범례·축 글자를 줄인다.
    /// 상호작용은 `exportMode`와 같이 꺼진다. (§5.8 — 별도 레이아웃을 만들지 않고 **파라미터로만** 줄인다)
    var compact: Bool = false
    /// 카드 배경색 오버라이드 (공유 카드의 라이트/다크 테마 색을 그대로 쓰기 위해).
    /// `.clear`를 주면 배경 없이 상위 카드에 녹아든다 (패딩은 유지).
    var cardBackground: Color? = nil
    /// 미리 강조할 날짜 — 이 날짜가 든 버킷을 **선택된 것처럼** 그린다(나머지 흐리게 + 세로 점선).
    /// 내보내기 모드와 함께 쓰며 말풍선은 나오지 않는다. (퍼포먼스 카드의 "이 러닝 날")
    var highlightDate: Date? = nil
    /// 차트 아래 흐름 문장 — 상태 한 줄 + 방향 한 줄(`RecordFlowInsight`).
    /// 앱 화면 전용: compact·내보내기 모드에서는 그리지 않는다.
    var flowComment: RecordFlowInsight.Result? = nil

    /// 막대와 점이 함께 보는 단 하나의 선택 상태
    @State private var selected: Date? = nil

    private var L: AppLanguage { AppLanguage.shared }

    // MARK: - 레이아웃 상수 (§5.8 — 값은 여기 한 곳에서만)

    private enum Metrics {
        static let plotHeight: CGFloat = 180
        /// 공유 카드용 축소 높이
        static let exportPlotHeight: CGFloat = 130
        /// 좁은 열(compact)용 축소 높이
        static let compactPlotHeight: CGFloat = 120
        static let padding: CGFloat = 14
        static let exportPadding: CGFloat = 12
        static let compactPadding: CGFloat = 4
        /// y축 라벨 폭
        static let gutter: CGFloat = 40
        static let compactGutter: CGFloat = 30
        /// 강도 범례 색 조각
        static let legendSwatch: CGFloat = 7
        static let compactLegendSwatch: CGFloat = 6
        static let symbolSize: CGFloat = 26
        /// 색 점 아래 깔리는 어두운 테두리 점 (막대 위에서도 점이 보이게)
        static let symbolStrokeSize: CGFloat = 46
        static let lineWidth: CGFloat = 1.5
        static let lineOpacity: Double = 0.9
        static let dimmed: Double = 0.55
        /// 페이스 축 위아래 여유 (초/km)
        static let pacePad: Double = 10
        /// 극단값이 나머지를 눌러 앉히지 않도록 백분위로 자르기 시작하는 표본 수
        static let paceClipMinCount: Int = 8
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

    /// 탭 선택보다 `highlightDate`가 우선 — 강조 코드는 이 하나만 본다(§5.8, 경로 분기 없음).
    private var effectiveSelection: Date? { highlightDate ?? selected }

    private var selectedBar: RecordBar? {
        guard let s = effectiveSelection else { return nil }
        return bars.first { s >= $0.id && s < $0.end }
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

    /// 이 간격(일) 이상 비면 선을 끊는다 — 부상·여행 같은 긴 공백은 이어 그리지 않는다. 그보다 짧은 쉬는 날은 잇는다.
    private static let lineBreakGapDays = 14

    private func segments(_ value: (RecordBar) -> Double?) -> [TrendSegment] {
        var result: [TrendSegment] = []
        var current: [TrendPoint] = []
        var lastDate: Date? = nil
        let cal = Calendar.current
        for bar in bars {
            guard let v = value(bar) else { continue }   // 기록 없는 구간은 건너뛰고 잇는다
            if let last = lastDate,
               let gap = cal.dateComponents([.day], from: last, to: bar.id).day,
               gap >= Self.lineBreakGapDays, !current.isEmpty {
                result.append(TrendSegment(id: result.count, points: current))
                current = []
            }
            current.append(TrendPoint(id: bar.id, y: v, color: barColor(bar)))
            lastDate = bar.id
        }
        if !current.isEmpty { result.append(TrendSegment(id: result.count, points: current)) }
        return result
    }

    // MARK: - 축 범위 · 페이스 ↔ km 매핑

    /// 막대 폭(슬롯 대비). 구간이 적을수록(7일 창) 막대가 넓어지므로 좁혀서 범례·축 머리와 균형을 맞춘다.
    private var barWidthRatio: CGFloat {
        switch bars.count {
        case ...8:   return compact ? 0.34 : 0.42   // 7일 창 · 압축 모드(반폭)에서는 더 가늘게
        case 9...16: return 0.6
        default:     return 0.78
        }
    }

    /// 하나뿐인 y 스케일. 막대(km)가 기준이고 페이스는 여기 위로 접힌다.
    private var kmTop: Double {
        max(1, bars.map(\.km).max() ?? 0) * 1.08
    }

    private var paceValues: [Double] { bars.compactMap(\.paceSec) }

    /// 페이스 축 범위(초/km). 표본이 충분하면 5~95 백분위로 잘라 극단값이 나머지를 눌러 앉히지 않게 한다.
    private var paceRange: (fast: Double, slow: Double)? {
        let vals = paceValues.sorted()
        guard let lo = vals.first, let hi = vals.last else { return nil }
        var fast = lo, slow = hi
        if vals.count >= Metrics.paceClipMinCount {
            let last = Double(vals.count - 1)
            fast = vals[Int((last * 0.05).rounded())]
            slow = vals[Int((last * 0.95).rounded())]
        }
        fast -= Metrics.pacePad
        slow += Metrics.pacePad
        if slow - fast < 1 { slow = fast + 1 }   // 0 나눗셈 방지
        return (fast, slow)
    }

    /// 페이스(초/km) → y (빠를수록 위). 범위를 벗어난 값은 축 끝에 붙인다.
    private func yForPace(_ pace: Double) -> Double? {
        guard let r = paceRange else { return nil }
        let t = (r.slow - pace) / (r.slow - r.fast)
        return min(max(t, 0), 1) * kmTop
    }

    /// y → 페이스(초/km). 왼쪽 축 라벨은 이 역함수로 만든다.
    private func paceForY(_ y: Double) -> Double {
        guard let r = paceRange else { return 0 }
        return r.slow - (y / kmTop) * (r.slow - r.fast)
    }

    /// 왼쪽 축 눈금 3개 — 10초 단위로 반올림한 "보기 좋은" 페이스를 y로 옮긴 값.
    private var paceTickYs: [Double] {
        guard let r = paceRange else { return [] }
        let fastTick = (r.fast / 10).rounded(.up) * 10
        let slowTick = (r.slow / 10).rounded(.down) * 10
        guard slowTick > fastTick else { return [] }
        let midTick = ((fastTick + slowTick) / 20).rounded() * 10
        var seen = Set<Int>()
        return [slowTick, midTick, fastTick].compactMap { pace in
            guard seen.insert(Int(pace)).inserted else { return nil }
            return yForPace(pace)
        }
    }

    // MARK: - Body

    /// 상호작용(말풍선·탭 선택)을 끄는 조건 — compact는 export를 함의한다.
    private var isExport: Bool { exportMode || compact }

    private var plotHeight: CGFloat {
        compact ? Metrics.compactPlotHeight
                : (exportMode ? Metrics.exportPlotHeight : Metrics.plotHeight)
    }

    private var cardPadding: CGFloat {
        compact ? Metrics.compactPadding
                : (exportMode ? Metrics.exportPadding : Metrics.padding)
    }

    /// y축 라벨 폭 (왼쪽 페이스 축)
    private var gutter: CGFloat { compact ? Metrics.compactGutter : Metrics.gutter }

    /// 축 라벨 글꼴 — 양쪽 축이 같은 값을 쓴다.
    private var axisFont: Font { .system(size: compact ? 8 : 9) }

    /// x축 라벨 글꼴 — compact에서만 축 글꼴에 맞춰 줄인다.
    private var xAxisFont: Font { compact ? axisFont : .caption2 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            if hasData {
                if !isExport { calloutRow }
                effortLegend
                if !compact { axisHeader }
                chart
                if !compact { footnote }
                if !compact, let flow = flowComment { flowCommentView(flow) }   // 공유 카드(export)에도 붙인다
            } else {
                Text(emptyMessage ?? L.s("이 기간에 기록이 없어요", "No records in this period"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(cardPadding)
        .background(cardBackground ?? Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - 헤더 ① 선택 말풍선

    private var calloutRow: some View {
        HStack(alignment: .top, spacing: 8) {
            if let bar = selectedBar, bar.runCount > 0 {
                // 값마다 지표 색 — 흰색 한 덩어리면 구분이 안 된다
                let segs = calloutSegments(bar)
                HStack(spacing: 0) {
                    ForEach(Array(segs.enumerated()), id: \.offset) { i, seg in
                        if i > 0 {
                            Text(" · ").foregroundStyle(.secondary)
                        }
                        Text(seg.text).foregroundStyle(seg.color)
                    }
                }
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .accessibilityLabel(calloutText(bar))
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
        let swatch: CGFloat = compact ? Metrics.compactLegendSwatch : Metrics.legendSwatch
        return HStack(spacing: 6) {
            HStack(spacing: compact ? 1.5 : 2) {
                Text(L.s("강도", "Effort"))
                    .font(axisFont)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
                ForEach(Array(EffortPalette.colors.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(c)
                        .frame(width: swatch, height: swatch)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 헤더 ③ 양쪽 축이 무엇인지 (왼쪽 페이스 · 오른쪽 km)

    private var axisHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if let p = paceTrailing {
                    Text(p)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(L.s("거리 km", "Distance km"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(distanceTrailing)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    // MARK: - 차트 하나 (§5.8 — 축·선택·강조 코드는 여기에만)

    private var chart: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value(periodName, bar.id, unit: xUnit),
                    yStart: .value(L.s("기준", "Base"), 0),
                    yEnd: .value(L.s("거리(km)", "Distance (km)"), bar.km),
                    width: .ratio(barWidthRatio)
                )
                .foregroundStyle(barColor(bar).gradient)
                .opacity(dim(bar.id))
                .cornerRadius(2)
            }
            paceMarks
            if let sel = selectedBar {
                RuleMark(x: .value(periodName, sel.id, unit: xUnit))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.55))
            }
        }
        .frame(height: plotHeight)
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...kmTop)
        .chartLegend(.hidden)
        .modifier(TapSelection(enabled: !isExport, selected: $selected))
        .modifier(DualYAxis(paceTickYs: paceTickYs,
                            paceLabel: { paceText(paceForY($0)) },
                            kmLabel: kmAxisLabel,
                            gutter: gutter,
                            font: axisFont))
        .chartOverlay { proxy in
            // 축선 3개 — 페이스 라벨 오른쪽(플롯 왼쪽 변) · km 라벨 왼쪽(플롯 오른쪽 변) · 날짜 위(플롯 아래 변)
            GeometryReader { geo in
                if let anchor = proxy.plotFrame {
                    let plot = geo[anchor]
                    Path { p in
                        p.move(to: CGPoint(x: plot.minX, y: plot.minY)); p.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
                        p.move(to: CGPoint(x: plot.maxX, y: plot.minY)); p.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                        p.move(to: CGPoint(x: plot.minX, y: plot.maxY)); p.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                    }
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                    .allowsHitTesting(false)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(xLabel(d)).font(xAxisFont).fixedSize()   // 마지막 라벨이 "…"로 잘리지 않게
                    }
                }
            }
        }
    }

    /// 탭 선택은 앱 화면에서만 — 내보내기 모드에서는 붙이지 않는다.
    private struct TapSelection: ViewModifier {
        let enabled: Bool
        @Binding var selected: Date?

        func body(content: Content) -> some View {
            if enabled {
                content.chartXSelection(value: $selected)
            } else {
                content
            }
        }
    }

    /// 왼쪽 = 실제 페이스(매핑의 역함수), 오른쪽 = km.
    /// 페이스가 하나도 없으면 평범한 단일 축 차트로 — km이 왼쪽으로 간다.
    private struct DualYAxis: ViewModifier {
        let paceTickYs: [Double]
        let paceLabel: (Double) -> String
        let kmLabel: (Double) -> String
        let gutter: CGFloat
        let font: Font

        func body(content: Content) -> some View {
            if paceTickYs.isEmpty {
                content.chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel {
                            Text(kmLabel(value.as(Double.self) ?? 0))
                                .font(font)
                                .frame(width: gutter, alignment: .trailing)
                        }
                        AxisGridLine()
                    }
                }
            } else {
                content.chartYAxis {
                    AxisMarks(position: .leading, values: paceTickYs) { value in
                        AxisValueLabel {
                            Text(paceLabel(value.as(Double.self) ?? 0))
                                .font(font)
                                .frame(width: gutter, alignment: .trailing)
                        }
                        AxisGridLine()
                            .foregroundStyle(Color.secondary.opacity(0.20))
                    }
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel {
                            Text(kmLabel(value.as(Double.self) ?? 0))
                                .font(font)
                        }
                    }
                }
            }
        }
    }

    /// 페이스 마크 묶음 — 평균 점선 + 이어진 구간 선 + 강도색 점(어두운 테두리).
    @ChartContentBuilder
    private var paceMarks: some ChartContent {
        let seriesName = L.s("페이스", "Pace")
        if let baseline = RecordSeries.paceBaseline(bars).flatMap({ yForPace($0) }) {
            // 평균 점선 — 값 라벨은 축 머리("평균 6'18\"")에 있으므로 차트 안에는 두지 않는다(오른쪽 막대와 겹침)
            RuleMark(y: .value(seriesName, baseline))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary.opacity(0.45))
        }
        let segs = segments { $0.paceSec.flatMap { yForPace($0) } }
        ForEach(segs) { seg in
            ForEach(seg.points) { p in
                LineMark(
                    x: .value(periodName, p.id, unit: xUnit),
                    y: .value(seriesName, p.y),
                    series: .value(L.s("구간", "Segment"), seg.id)
                )
                .foregroundStyle(Theme.pace.opacity(Metrics.lineOpacity))
                .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
        }
        // 어두운 테두리를 먼저 깔고 그 위에 색 점 — 막대 위에서도 점이 묻히지 않는다.
        ForEach(segs) { seg in
            ForEach(seg.points) { p in
                PointMark(
                    x: .value(periodName, p.id, unit: xUnit),
                    y: .value(seriesName, p.y)
                )
                .symbolSize(Metrics.symbolStrokeSize)
                .foregroundStyle(Color.black.opacity(0.5))
                .opacity(dim(p.id))
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
        Text(L.s("막대 = 거리(색 = 강도) · 선 = 페이스, 위가 빠름 · 왼쪽 축 페이스 · 오른쪽 축 km",
                 "Bars = distance (color = effort) · line = pace, higher = faster · left axis pace · right axis km"))
            .font(.system(size: 8.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 흐름 문장 (상태 한 줄 + 방향 한 줄)

    private func flowCommentView(_ flow: RecordFlowInsight.Result) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("✦ " + flow.status)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
            if let direction = flow.direction {
                Text(direction)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    // MARK: - 축 머리 요약

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

    // MARK: - 색·강조

    private var periodName: String { L.s("기간", "Period") }

    private func barColor(_ bar: RecordBar) -> Color {
        guard let mean = bar.meanEffort else { return Color.secondary.opacity(0.45) }
        return EffortPalette.color(for: EffortResolver.clamp(mean))
    }

    /// 선택된 구간만 진하게 — 막대와 점이 함께 흐려진다.
    private func dim(_ id: Date) -> Double {
        guard let sel = selectedBar else { return 1 }
        return sel.id == id ? 1 : Metrics.dimmed
    }

    // MARK: - 축 라벨

    private var xAxisValues: AxisMarkValues {
        switch period {
        // 좁은 열의 7일 창(≤8 버킷)은 7일 간격이면 라벨이 한두 개뿐 → 이틀 간격으로
        case .day:   return .stride(by: .day, count: (compact && bars.count <= 8) ? 2 : 7)
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

    /// 말풍선 조각 + 지표 색: 날짜 흰색 · 거리 흰색 · 시간 노랑 · 강도 강도색 · 부하 바이올렛 · 페이스 청록 · 심박 빨강
    private func calloutSegments(_ bar: RecordBar) -> [(text: String, color: Color)] {
        var segs: [(text: String, color: Color)] = [(dateLabel(bar), .white)]
        if period == .day {
            if bar.km > 0 { segs.append((String(format: "%.2fkm", bar.km), .white.opacity(0.9))) }
            if bar.minutes > 0 { segs.append((clockText(bar.minutes), Theme.time)) }
            if let e = bar.meanEffort {
                segs.append((L.s("강도 \(effortText(e))", "effort \(effortText(e))"),
                             EffortPalette.color(for: EffortResolver.clamp(e))))
            }
            if bar.au > 0 { segs.append(("\(Int(bar.au.rounded())) AU", Theme.violet)) }
            if let p = bar.paceSec { segs.append((paceText(p), Theme.pace)) }
        } else {
            if bar.km > 0 { segs.append((kmText(bar.km), .white.opacity(0.9))) }
            if bar.runCount > 0 { segs.append((L.s("\(bar.runCount)회", "\(bar.runCount) runs"), .white.opacity(0.9))) }
            if bar.au > 0 {
                let au = bar.au.rounded().formatted(.number.grouping(.automatic))
                segs.append(("\(au) AU", Theme.violet))
            }
            if let p = bar.paceSec { segs.append((L.s("평균 \(paceText(p))", "avg \(paceText(p))"), Theme.pace)) }
        }
        if let hr = bar.avgHR { segs.append(("\(Int(hr.rounded())) bpm", Theme.heartRate)) }
        return segs
    }

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
        var parts = [L.s("거리 막대와 페이스 선을 한 차트에 — 오른쪽 축 km, 왼쪽 축 페이스",
                         "One chart: distance bars (right axis, km) and pace line (left axis)"),
                     distanceTrailing]
        if let p = paceTrailing { parts.append(L.s("페이스 \(p)", "pace \(p)")) }
        if !compact, let flow = flowComment {
            parts.append(flow.status)
            if let direction = flow.direction { parts.append(direction) }
        }
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
