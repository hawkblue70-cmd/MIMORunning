import SwiftUI
import Charts

// MARK: - Hollow circle symbol (outline-only point, shared across chart views)

struct HollowCircle: ChartSymbolShape {
    let perceptualUnitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    func path(in rect: CGRect) -> Path {
        let lw: CGFloat = 1.5
        return Path(ellipseIn: rect.insetBy(dx: lw / 2, dy: lw / 2))
            .strokedPath(StrokeStyle(lineWidth: lw))
    }
}

// MARK: - Cardio Fitness Classifier (internal — shared with ActivityDetailView)
// Thresholds from FRIEND database (Kaminsky et al. 2015, Mayo Clin Proc).
// Bands = P25 / P50 / P75 percentiles by age & sex (mL/kg·min).
// Male P50/P75 verified against Apple Health image; female from published table.

enum CardioFitnessClassifier {
    struct Band: Identifiable {
        var id: String { label }
        let label: String
        let color: Color
        let low: Double
        let high: Double
    }

    struct Thresholds {
        let belowAvg: Double
        let aboveAvg: Double
        let high: Double
    }

    static func rating(vo2: Double, age: Int?, isMale: Bool?) -> String? {
        guard let age, let isMale else { return nil }
        let L = AppLanguage.shared
        let t = thresholds(age: age, isMale: isMale)
        switch vo2 {
        case ..<t.belowAvg: return L.s("낮음",      "Low")
        case ..<t.aboveAvg: return L.s("평균 이하", "Below Avg")
        case ..<t.high:     return L.s("평균 이상", "Above Avg")
        default:            return L.s("높음",      "High")
        }
    }

    static func bands(age: Int, isMale: Bool, yMin: Double, yMax: Double) -> [Band] {
        let L = AppLanguage.shared
        let t = thresholds(age: age, isMale: isMale)
        return [
            Band(label: L.s("낮음",      "Low"),       color: Color(hex: "FF453A"), low: yMin,       high: t.belowAvg),
            Band(label: L.s("평균 이하", "Below Avg"), color: Color(hex: "FF9F0A"), low: t.belowAvg, high: t.aboveAvg),
            Band(label: L.s("평균 이상", "Above Avg"), color: Color(hex: "FFD60A"), low: t.aboveAvg, high: t.high),
            Band(label: L.s("높음",      "High"),      color: Color(hex: "30D158"), low: t.high,     high: yMax),
        ]
    }

    static func thresholds(age: Int, isMale: Bool) -> Thresholds {
        if isMale {
            // FRIEND 기반 (낮음/평균이하/평균이상/높음 경계, mL/kg·min)
            switch age {
            case ..<30:   return Thresholds(belowAvg: 37, aboveAvg: 48, high: 57)
            case 30..<40: return Thresholds(belowAvg: 34, aboveAvg: 42, high: 52)
            case 40..<50: return Thresholds(belowAvg: 30, aboveAvg: 38, high: 47)
            case 50..<60: return Thresholds(belowAvg: 26, aboveAvg: 33, high: 41)
            case 60..<70: return Thresholds(belowAvg: 22, aboveAvg: 28, high: 36)
            default:      return Thresholds(belowAvg: 19, aboveAvg: 24, high: 33)
            }
        } else {
            // FRIEND 기반 (여성, mL/kg·min)
            switch age {
            case ..<30:   return Thresholds(belowAvg: 27, aboveAvg: 37, high: 45)
            case 30..<40: return Thresholds(belowAvg: 24, aboveAvg: 30, high: 38)
            case 40..<50: return Thresholds(belowAvg: 21, aboveAvg: 27, high: 34)
            case 50..<60: return Thresholds(belowAvg: 19, aboveAvg: 23, high: 29)
            case 60..<70: return Thresholds(belowAvg: 16, aboveAvg: 20, high: 25)
            default:      return Thresholds(belowAvg: 15, aboveAvg: 18, high: 22)
            }
        }
    }
}

// MARK: - Trend Range

enum TrendRange: String, CaseIterable, Identifiable {
    case week     = "주"
    case month    = "1개월"
    case sixMonth = "6개월"
    case year     = "1년"

    var id: String { rawValue }

    var label: String {
        let L = AppLanguage.shared
        switch self {
        case .week:     return L.s("주",    "1W")
        case .month:    return L.s("1개월", "1M")
        case .sixMonth: return L.s("6개월", "6M")
        case .year:     return L.s("1년",   "1Y")
        }
    }

    var startDate: Date {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .week:     return cal.date(byAdding: .day,   value: -7,  to: now) ?? now
        case .month:    return cal.date(byAdding: .month, value: -1,  to: now) ?? now
        case .sixMonth: return cal.date(byAdding: .month, value: -6,  to: now) ?? now
        case .year:     return cal.date(byAdding: .year,  value: -1,  to: now) ?? now
        }
    }

    /// 0 = 개별 런, 1 = 1주 평균, 2 = 2주 평균
    var bucketWeeks: Int {
        switch self {
        case .week, .month:    return 0
        case .sixMonth:        return 1
        case .year:            return 2
        }
    }
    var granularity: Granularity {
        bucketWeeks == 0 ? .day : .week
    }
    enum Granularity { case day, week }
}

// MARK: - MetricTrendView

struct MetricTrendView: View {
    let metric: TrendMetric
    let currentValue: Double?
    let manager: HealthKitManager
    let age: Int?
    let isMale: Bool?

    @State private var selectedRange: TrendRange = .month
    @State private var fullYearPoints: [(date: Date, value: Double)] = []
    @State private var dataPoints: [(date: Date, value: Double)] = []
    @State private var isLoading = true
    @State private var showShareCard = false
    @AppStorage("distanceUnitMiles") private var useMiles = false
    @Environment(\.dismiss) private var dismiss

    private var effectiveCurrent: Double? { currentValue ?? dataPoints.last?.value }

    private var periodAverage: Double? {
        guard !dataPoints.isEmpty else { return nil }
        return dataPoints.map(\.value).reduce(0, +) / Double(dataPoints.count)
    }

    /// 6개월/년은 주별 평균으로 집계, 주/월은 개별 런 그대로
    private var displayPoints: [(date: Date, value: Double)] {
        let bw = selectedRange.bucketWeeks
        guard bw > 0 else { return dataPoints }
        return averaged(dataPoints, bucketWeeks: bw)
    }

    private func averaged(_ pts: [(date: Date, value: Double)], bucketWeeks: Int) -> [(date: Date, value: Double)] {
        guard bucketWeeks > 0, !pts.isEmpty else { return pts }
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2  // Monday
        // 전체 기간의 첫 월요일을 epoch로 삼아 bucketWeeks 단위로 나눔
        guard let firstMonday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: pts.first!.date)) else { return pts }
        let bucketSecs = TimeInterval(bucketWeeks * 7 * 86400)
        var buckets: [Int: [Double]] = [:]
        for pt in pts {
            let idx = Int(pt.date.timeIntervalSince(firstMonday) / bucketSecs)
            buckets[idx, default: []].append(pt.value)
        }
        return buckets
            .map { idx, vals -> (date: Date, value: Double) in
                let bucketStart = firstMonday.addingTimeInterval(Double(idx) * bucketSecs)
                return (date: bucketStart, value: vals.reduce(0, +) / Double(vals.count))
            }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    rangePicker
                    if isLoading {
                        Spacer()
                        ProgressView().tint(Theme.violet)
                        Spacer()
                    } else if dataPoints.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            VStack(spacing: 16) {
                                chartCard
                                statsCard
                                Spacer(minLength: 24)
                            }
                            .padding(.top, 12)
                        }
                    }
                }
            }
            .navigationTitle(metric.koreanLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isLoading && !dataPoints.isEmpty {
                        Button(AppLanguage.shared.s("내보내기", "Export")) {
                            showShareCard = true
                        }
                        .foregroundStyle(Theme.violet)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Theme.violet)
                }
            }
        }
        .presentationDetents([.large])
        .task {
            // 1년치 전부 1회 로드 — 이후 범위 변경은 메모리 필터만 실행
            isLoading = true
            fullYearPoints = await manager.fetchMetricHistory(metric, from: TrendRange.year.startDate, usePounds: useMiles)
            dataPoints = fullYearPoints.filter { $0.date >= selectedRange.startDate }
            isLoading = false
        }
        .onChange(of: selectedRange) {
            dataPoints = fullYearPoints.filter { $0.date >= selectedRange.startDate }
        }
        .sheet(isPresented: $showShareCard) {
            GrowthShareCardScreen(
                metric: metric,
                currentValue: currentValue,
                dataPoints: displayPoints,
                selectedRange: selectedRange,
                age: age,
                isMale: isMale
            )
        }
    }

    // MARK: - Subviews

    private var rangePicker: some View {
        Picker(AppLanguage.shared.s("기간", "Period"), selection: $selectedRange) {
            ForEach(TrendRange.allCases) { r in Text(r.label).tag(r) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var chartCard: some View {
        let L = AppLanguage.shared
        let countLabel: String = {
            let bw = selectedRange.bucketWeeks
            if bw == 2 {
                return L.s("\(displayPoints.count)개 구간 (2주 평균)", "\(displayPoints.count) periods (2w avg)")
            } else if bw == 1 {
                return L.s("\(displayPoints.count)주 평균", "\(displayPoints.count)w avg")
            } else {
                return L.s("\(dataPoints.count)개 기록", "\(dataPoints.count) records")
            }
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Text(countLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            chartView
                .frame(height: 200)
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var chartView: some View {
        if metric == .vo2Max, let a = age, let m = isMale {
            vo2MaxChartWithBands(age: a, isMale: m)
        } else {
            baseChart
        }
    }

    private var baseChart: some View {
        let pts = displayPoints
        let sz: CGFloat = pts.count > 30 ? 10 : pts.count > 15 ? 20 : 35
        return Chart {
            ForEach(pts, id: \.date) { pt in
                LineMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .foregroundStyle(metric.sparkColor)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .symbol(HollowCircle())
                    .foregroundStyle(metric.sparkColor)
                    .symbolSize(sz)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: xLabelFormat)
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(metric == .easyEffortPace ? EffortPaceTrend.axisLabel(v) : v.formatted(.number))
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
    }

    private func vo2MaxChartWithBands(age: Int, isMale: Bool) -> some View {
        let pts = displayPoints
        let sz: CGFloat = pts.count > 30 ? 10 : pts.count > 15 ? 20 : 35
        let vals = pts.map(\.value)
        let dMin = vals.min() ?? 20.0
        let dMax = vals.max() ?? 55.0
        let t = CardioFitnessClassifier.thresholds(age: age, isMale: isMale)
        let yMin = min(dMin - 2, t.belowAvg - 5)
        let yMax = max(dMax + 2, t.high + 5)
        let bands = CardioFitnessClassifier.bands(age: age, isMale: isMale, yMin: yMin, yMax: yMax)

        return Chart {
            ForEach(bands) { band in
                RectangleMark(
                    xStart: .value("", selectedRange.startDate),
                    xEnd: .value("", Date()),
                    yStart: .value("", band.low),
                    yEnd: .value("", band.high)
                )
                .foregroundStyle(band.color.opacity(0.18))
            }
            ForEach(pts, id: \.date) { pt in
                LineMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .foregroundStyle(metric.sparkColor)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .symbol(HollowCircle())
                    .foregroundStyle(metric.sparkColor)
                    .symbolSize(sz)
            }
        }
        .chartYScale(domain: yMin...yMax)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: xLabelFormat)
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(metric == .easyEffortPace ? EffortPaceTrend.axisLabel(v) : v.formatted(.number))
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
    }

    private var xLabelFormat: Date.FormatStyle {
        switch selectedRange {
        case .week, .month:    return .dateTime.month(.abbreviated).day()
        case .sixMonth, .year: return .dateTime.month(.abbreviated)
        }
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            if let cur = effectiveCurrent {
                statCell(label: AppLanguage.shared.s("현재값", "Current"), value: metric.formattedValue(cur, usePounds: useMiles), color: metric.sparkColor)
                if periodAverage != nil {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)
                        .padding(.vertical, 12)
                }
            }
            if let avg = periodAverage {
                statCell(
                    label: AppLanguage.shared.s("기간 평균 (\(dataPoints.count)회)", "Period avg (\(dataPoints.count))"),
                    value: avgDisplayString(avg),
                    color: avgDisplayColor(avg)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func statCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(AppLanguage.shared.s("데이터 없음", "No Data"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(AppLanguage.shared.s("이 기간에 기록된 \(metric.koreanLabel) 데이터가 없어요", "No \(metric.koreanLabel) data for this period"))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func avgDisplayString(_ avg: Double) -> String {
        let arrow = trendArrow(avg: avg)
        return metric.formattedValue(avg, usePounds: useMiles) + (arrow.map { " \($0)" } ?? "")
    }

    private func avgDisplayColor(_ avg: Double) -> Color {
        guard let arrow = trendArrow(avg: avg) else { return .white }
        return trendColor(arrow)
    }

    private func trendArrow(avg: Double) -> String? {
        guard let c = effectiveCurrent, avg > 0 else { return nil }
        let delta = (c - avg) / avg
        guard abs(delta) > 0.01 else { return nil }
        return delta > 0 ? "↑" : "↓"
    }

    private func trendColor(_ arrow: String) -> Color {
        let up = arrow == "↑"
        return (metric.lowerIsBetter ? !up : up) ? Color(hex: "30D158") : Color(hex: "FF453A")
    }
}
