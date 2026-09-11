import SwiftUI
import Charts

// MARK: - Growth Trend Chart (compact, standalone — safe for ImageRenderer)

struct GrowthTrendChart: View {
    let metric: TrendMetric
    let selectedRange: TrendRange
    let dataPoints: [(date: Date, value: Double)]
    let age: Int?
    let isMale: Bool?
    var gridColor: Color       = Color.white.opacity(0.12)
    var axisLabelColor: Color  = Color.white.opacity(0.45)
    var lineColor: Color       = Theme.violet

    var body: some View {
        if metric == .vo2Max, let a = age, let m = isMale {
            vo2MaxChartCore(age: a, isMale: m)
        } else {
            baseChartCore
        }
    }

    private var baseChartCore: some View {
        Chart {
            ForEach(dataPoints, id: \.date) { pt in
                LineMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .foregroundStyle(lineColor)
                    .interpolationMethod(.catmullRom)
                // 점은 화면(성장 탭 스파크라인)과 같은 모양 — 흰 테두리 + 선 색 속. 프리뷰 = 출력
                PointMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .foregroundStyle(Color.white)
                    .symbolSize(Theme.sparkHaloSizeCompact)
                PointMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .foregroundStyle(lineColor)
                    .symbolSize(Theme.sparkHaloCoreSizeCompact)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(gridColor)
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: xLabelFormat)
                            .font(.system(size: 8))
                            .foregroundStyle(axisLabelColor)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(gridColor)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(metric == .easyEffortPace ? EffortPaceTrend.axisLabel(v) : v.formatted(.number))
                            .font(.system(size: 8))
                            .foregroundStyle(axisLabelColor)
                    }
                }
            }
        }
    }

    private func vo2MaxChartCore(age: Int, isMale: Bool) -> some View {
        let vals = dataPoints.map(\.value)
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
                .foregroundStyle(band.color.opacity(0.12))
            }
            ForEach(dataPoints, id: \.date) { pt in
                LineMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .foregroundStyle(lineColor)
                    .interpolationMethod(.catmullRom)
                // 점은 화면(성장 탭 스파크라인)과 같은 모양 — 흰 테두리 + 선 색 속. 프리뷰 = 출력
                PointMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .foregroundStyle(Color.white)
                    .symbolSize(Theme.sparkHaloSizeCompact)
                PointMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .foregroundStyle(lineColor)
                    .symbolSize(Theme.sparkHaloCoreSizeCompact)
            }
        }
        .chartYScale(domain: yMin...yMax)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(gridColor)
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: xLabelFormat)
                            .font(.system(size: 8))
                            .foregroundStyle(axisLabelColor)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(gridColor)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(metric == .easyEffortPace ? EffortPaceTrend.axisLabel(v) : v.formatted(.number))
                            .font(.system(size: 8))
                            .foregroundStyle(axisLabelColor)
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
}

// MARK: - Growth Share Card (renderable — dark / light / photo modes)

struct GrowthShareCard: View {
    let metric: TrendMetric
    let selectedRange: TrendRange
    let dataPoints: [(date: Date, value: Double)]
    let currentValue: Double?
    let age: Int?
    let isMale: Bool?
    var photo: UIImage? = nil
    var theme: ShareTheme = .dark

    private var p: SummaryCardPalette { theme == .light ? .light : .dark }

    var body: some View {
        if let ph = photo {
            photoCard(photo: ph)
        } else {
            themedCard
        }
    }

    // MARK: - Themed card (dark or light)

    private var themedCard: some View {
        ZStack {
            if theme == .light {
                p.background
            } else {
                LinearGradient(
                    colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                wordmarkRow
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                Rectangle()
                    .fill(p.divider)
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                metricTitle
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Spacer()

                GrowthTrendChart(
                    metric: metric,
                    selectedRange: selectedRange,
                    dataPoints: dataPoints,
                    age: age,
                    isMale: isMale,
                    gridColor: p.gridLine,
                    axisLabelColor: p.axisLabel,
                    lineColor: metric.sparkColor
                )
                .frame(height: 112)
                .padding(.horizontal, 16)

                Spacer()

                statsBlock
                    .padding(.horizontal, 20)

                Spacer(minLength: 18)
            }
        }
    }

    // MARK: - Photo card (always dark overlay — theme doesn't apply)

    private func photoCard(photo: UIImage) -> some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.92),
                    Color.black.opacity(0.60),
                    Color.clear
                ],
                startPoint: .bottom,
                endPoint: UnitPoint(x: 0.5, y: 0.18)
            )

            VStack(spacing: 0) {
                wordmarkRow
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    metricTitle

                    GrowthTrendChart(
                        metric: metric,
                        selectedRange: selectedRange,
                        dataPoints: dataPoints,
                        age: age,
                        isMale: isMale,
                        gridColor: .white.opacity(0.08),
                        axisLabelColor: .white.opacity(0.45),
                        lineColor: metric.sparkColor
                    )
                    .frame(height: 88)

                    Rectangle()
                        .fill(Color.white.opacity(0.20))
                        .frame(height: 0.5)

                    statsBlock
                }
                .padding(14)
                .background(Color(red: 0.06, green: 0.03, blue: 0.12, opacity: 0.80))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .clipped()
    }

    // MARK: - Shared subviews

    private var wordmarkRow: some View {
        HStack(alignment: .center) {
            MIMOWordmark(size: 9, strokeMIMO: theme == .light)
            Spacer()
            Text(Date(), format: .dateTime.month(.abbreviated).day())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(p.textSecondary)
        }
    }

    private var metricTitle: some View {
        Text("\(metric.koreanLabel) · \(selectedRange.label)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(p.textSecondary)
    }

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(currentDisplayValue)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let change = periodChangeString {
                    Text(change)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(changeColor)
                }
            }
            if let grade = vo2Grade {
                Text(grade)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(p.brand)
            }
        }
    }

    // MARK: - Computed helpers

    private var currentDisplayValue: String {
        if let cur = currentValue { return metric.formattedValue(cur) }
        if let last = dataPoints.last { return metric.formattedValue(last.value) }
        return "—"
    }

    private var periodChange: Double? {
        guard dataPoints.count >= 2,
              let first = dataPoints.first, let last = dataPoints.last else { return nil }
        return last.value - first.value
    }

    private var periodChangeString: String? {
        guard let change = periodChange, abs(change) > 0.01 else { return nil }
        let positive = change > 0
        let sign = positive ? "+" : ""
        let arrow = positive ? "↑" : "↓"
        let absChange = abs(change)
        switch metric {
        case .cadence, .power, .groundContactTime, .hrRecovery1:
            return "\(sign)\(Int(absChange.rounded())) \(arrow)"
        case .easyEffortPace:
            return "\(sign)\(Int(absChange.rounded()))s \(arrow)"
        case .strideLength:
            return "\(sign)\(String(format: "%.2f", absChange)) \(arrow)"
        case .verticalOscillation, .vo2Max:
            return "\(sign)\(String(format: "%.1f", absChange)) \(arrow)"
        case .bodyMass:
            return "\(sign)\(String(format: "%.1f", absChange)) \(arrow)"
        case .bodyFatPercentage:
            return "\(sign)\(String(format: "%.1f", absChange))% \(arrow)"
        }
    }

    private var changeColor: Color {
        guard let change = periodChange else { return p.textPrimary }
        let positive = change > 0
        return (metric.lowerIsBetter ? !positive : positive)
            ? Color.green : Color(red: 1, green: 0.4, blue: 0.4)
    }

    private var vo2Grade: String? {
        guard metric == .vo2Max else { return nil }
        let val = currentValue ?? dataPoints.last?.value
        guard let val else { return nil }
        return CardioFitnessClassifier.rating(vo2: val, age: age, isMale: isMale)
    }
}

// MARK: - Growth Share Card Screen

struct GrowthShareCardScreen: View {
    let metric: TrendMetric
    let currentValue: Double?
    let dataPoints: [(date: Date, value: Double)]
    let selectedRange: TrendRange
    let age: Int?
    let isMale: Bool?

    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @State private var showShareSheet = false
    @State private var cardTheme: ShareTheme = .dark
    @Environment(\.dismiss) private var dismiss

    private let cardW: CGFloat = 300
    private let cardH: CGFloat = 375

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Live card preview — same component as export
                    GrowthShareCard(
                        metric: metric,
                        selectedRange: selectedRange,
                        dataPoints: dataPoints,
                        currentValue: currentValue,
                        age: age,
                        isMale: isMale,
                        theme: cardTheme
                    )
                    .environment(\.colorScheme, cardTheme == .dark ? .dark : .light)
                    .frame(width: cardW, height: cardH)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Theme.violet.opacity(0.30), radius: 28, y: 10)

                    Spacer(minLength: 20)

                    themeToggle
                        .padding(.horizontal, 24)

                    Spacer(minLength: 12)

                    shareCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }
            }
            .navigationTitle(AppLanguage.shared.s("\(metric.koreanLabel) 내보내기", "\(metric.koreanLabel) Export"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Theme.violet)
                }
            }
        }
        .task { await renderCard() }
        .onChange(of: cardTheme) { Task { await renderCard() } }
    }

    // MARK: - Theme toggle

    private var themeToggle: some View {
        HStack(spacing: 0) {
            themeSegment(label: AppLanguage.shared.s("다크", "Dark"),
                         selected: cardTheme == .dark) { cardTheme = .dark }
            themeSegment(label: AppLanguage.shared.s("라이트", "Light"),
                         selected: cardTheme == .light) { cardTheme = .light }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func themeSegment(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Theme.violet : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Theme.violet.opacity(0.22) : Color.white.opacity(0.08))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }

    // MARK: - Share CTA

    @ViewBuilder
    private var shareCTA: some View {
        if isRendering {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.violet)
                Text(AppLanguage.shared.s("카드 만드는 중...", "Creating card..."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        } else if previewImage != nil {
            Button { showShareSheet = true } label: {
                Label(AppLanguage.shared.s("내보내기", "Export"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .sheet(isPresented: $showShareSheet) {
                if let img = previewImage { ShareSheet(images: [img]) }
            }
        } else {
            Text(AppLanguage.shared.s("카드 생성에 실패했어요", "Card creation failed"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
    }

    // MARK: - Render

    @MainActor
    private func renderCard() async {
        isRendering = true
        previewImage = nil
        let renderer = ImageRenderer(content:
            GrowthShareCard(
                metric: metric,
                selectedRange: selectedRange,
                dataPoints: dataPoints,
                currentValue: currentValue,
                age: age,
                isMale: isMale,
                theme: cardTheme
            )
            .environment(\.colorScheme, cardTheme == .dark ? .dark : .light)
            .frame(width: cardW, height: cardH)
        )
        renderer.scale = 3
        previewImage = renderer.uiImage
        isRendering = false
    }
}
