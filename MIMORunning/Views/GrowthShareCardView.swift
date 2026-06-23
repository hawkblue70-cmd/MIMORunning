import SwiftUI
import Charts

// MARK: - Growth Trend Chart (compact, standalone — safe for ImageRenderer)

struct GrowthTrendChart: View {
    let metric: TrendMetric
    let selectedRange: TrendRange
    let dataPoints: [(date: Date, value: Double)]
    let age: Int?
    let isMale: Bool?
    var gridColor: Color = Color.white.opacity(0.12)

    var body: some View {
        Group {
            if metric == .vo2Max, let a = age, let m = isMale {
                vo2MaxChartCore(age: a, isMale: m)
            } else {
                baseChartCore
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
                            .foregroundStyle(Color.white.opacity(0.40))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(gridColor)
                AxisValueLabel()
                    .font(.system(size: 8))
                    .foregroundStyle(Color.white.opacity(0.40))
            }
        }
    }

    private var baseChartCore: some View {
        Chart {
            ForEach(dataPoints, id: \.date) { pt in
                LineMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .foregroundStyle(Theme.violet)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .symbol(HollowCircle())
                    .foregroundStyle(Theme.violet)
                    .symbolSize(dataPoints.count > 15 ? 12 : 28)
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
                    .foregroundStyle(Theme.violet)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .symbol(HollowCircle())
                    .foregroundStyle(Theme.violet)
                    .symbolSize(dataPoints.count > 15 ? 12 : 28)
            }
        }
        .chartYScale(domain: yMin...yMax)
    }

    private var xLabelFormat: Date.FormatStyle {
        switch selectedRange {
        case .week, .month:    return .dateTime.month(.abbreviated).day()
        case .sixMonth, .year: return .dateTime.month(.abbreviated)
        }
    }
}

// MARK: - Growth Share Card (renderable — dark + photo modes)

struct GrowthShareCard: View {
    let metric: TrendMetric
    let selectedRange: TrendRange
    let dataPoints: [(date: Date, value: Double)]
    let currentValue: Double?
    let age: Int?
    let isMale: Bool?
    var photo: UIImage? = nil

    var body: some View {
        if let p = photo {
            photoCard(photo: p)
        } else {
            darkCard
        }
    }

    // MARK: - Dark card (no photo)

    private var darkCard: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                wordmarkRow
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                Rectangle()
                    .fill(Theme.violet.opacity(0.35))
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
                    isMale: isMale
                )
                .frame(height: 112)
                .padding(.horizontal, 16)

                Spacer()

                statsBlock
                    .padding(.horizontal, 20)

                Spacer(minLength: 10)

                footerRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
            }
        }
    }

    // MARK: - Photo card

    private func photoCard(photo: UIImage) -> some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()

            // Scrim so the panel text is readable
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
                // Wordmark pill at top
                wordmarkRow
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                Spacer()

                // Glass-style stats panel
                VStack(alignment: .leading, spacing: 8) {
                    metricTitle

                    GrowthTrendChart(
                        metric: metric,
                        selectedRange: selectedRange,
                        dataPoints: dataPoints,
                        age: age,
                        isMale: isMale,
                        gridColor: .white.opacity(0.08)
                    )
                    .frame(height: 88)

                    Rectangle()
                        .fill(Color.white.opacity(0.20))
                        .frame(height: 0.5)

                    statsBlock
                    footerRow
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
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 0) {
                Text("MIMO")
                    .font(.system(size: 11, weight: .black))
                    .tracking(2)
                    .foregroundStyle(.white)
                Text(" RUNNING")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.violet)
            }
            Spacer()
            Text(Date(), format: .dateTime.month(.abbreviated).day())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var metricTitle: some View {
        Text("\(metric.koreanLabel) · \(selectedRange.label)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.65))
    }

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(currentDisplayValue)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
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
                    .foregroundStyle(Theme.violet)
            }
        }
    }

    private var footerRow: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color(hex: "3DFF7A").opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "figure.run")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Color(hex: "3DFF7A"))
            }
            Spacer()
            Text("mimorunning")
                .font(.system(size: 8, weight: .medium))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.18))
        }
    }

    // MARK: - Computed helpers

    private var currentDisplayValue: String {
        if let cur = currentValue { return metric.formattedValue(cur) }
        if let last = dataPoints.last { return metric.formattedValue(last.value) }
        return "—"
    }

    private var periodChange: Double? {
        guard dataPoints.count >= 2 else { return nil }
        return dataPoints.last!.value - dataPoints.first!.value
    }

    private var periodChangeString: String? {
        guard let change = periodChange, abs(change) > 0.01 else { return nil }
        let positive = change > 0
        let sign = positive ? "+" : ""
        let arrow = positive ? "↑" : "↓"
        let absChange = abs(change)
        switch metric {
        case .cadence, .power, .groundContactTime:
            return "\(sign)\(Int(absChange.rounded())) \(arrow)"
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
        guard let change = periodChange else { return .white }
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

    @State private var shareURL: URL?
    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @Environment(\.dismiss) private var dismiss

    private let cardW: CGFloat = 300
    private let cardH: CGFloat = 375

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Live card preview
                    GrowthShareCard(
                        metric: metric,
                        selectedRange: selectedRange,
                        dataPoints: dataPoints,
                        currentValue: currentValue,
                        age: age,
                        isMale: isMale
                    )
                    .frame(width: cardW, height: cardH)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Theme.violet.opacity(0.30), radius: 28, y: 10)

                    Spacer(minLength: 24)

                    shareCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }
            }
            .navigationTitle(AppLanguage.shared.s("성장 카드 공유", "Growth Card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Theme.violet)
                }
            }
        }
        .task { await renderCard() }
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
        } else if let url = shareURL, let img = previewImage {
            ShareLink(
                item: url,
                preview: SharePreview(AppLanguage.shared.s("\(metric.koreanLabel) 추세", "\(metric.koreanLabel) Trend"), image: Image(uiImage: img))
            ) {
                Label(AppLanguage.shared.s("공유하기", "Share"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
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
        shareURL = nil
        previewImage = nil

        let renderer = ImageRenderer(content: renderableCard())
        renderer.scale = 3

        guard let img = renderer.uiImage, let data = img.pngData() else {
            isRendering = false
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_growth_\(metric.rawValue).png")
        try? data.write(to: url)
        previewImage = img
        shareURL = url
        isRendering = false
    }

    private func renderableCard() -> some View {
        GrowthShareCard(
            metric: metric,
            selectedRange: selectedRange,
            dataPoints: dataPoints,
            currentValue: currentValue,
            age: age,
            isMale: isMale
        )
        .frame(width: cardW, height: cardH)
    }
}
