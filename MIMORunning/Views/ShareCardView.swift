import SwiftUI
import Charts
import CoreLocation
import HealthKit
import PhotosUI
import SwiftData

// MARK: - Share Metric model

enum ShareMetric: String, Hashable {
    case pace, duration, heartRate, cadence, vo2Max, calories, power, elevation, intervals, bestPace

    var chipLabel: String {
        switch self {
        case .pace:      "페이스"
        case .duration:  "시간"
        case .heartRate: "심박"
        case .cadence:   "케이던스"
        case .vo2Max:    "유산소"
        case .calories:  "칼로리"
        case .power:     "파워"
        case .elevation: "고도"
        case .intervals: "반복"
        case .bestPace:  "최고 페이스"
        }
    }
}

struct ShareMetricItem: Identifiable {
    let id: ShareMetric
    let value: String
    let label: String   // unit label shown on card
    let color: Color
}

private func moodCardColor(_ mood: Mood) -> Color {
    switch mood {
    case .great: Theme.violet
    case .okay:  Theme.time
    case .tough: Theme.heartRate
    }
}

// ≤3: single row. ≥4: two rows (3+3, 3+2, 2+2).
private func metricsRows(_ items: [ShareMetricItem]) -> [[ShareMetricItem]] {
    let capped = Array(items.prefix(6))
    switch capped.count {
    case 0:       return []
    case 1, 2, 3: return [capped]
    case 4, 5:    return [capped]
    default:      return [Array(capped.prefix(3)), Array(capped.suffix(3))]
    }
}

// Photo/video grid: ≤3→1 row, 4→2×2, 5→3+2, 6→3×2.
private func photoMetricsRows(_ items: [ShareMetricItem]) -> [[ShareMetricItem]] {
    switch items.count {
    case 0:       return []
    case 1, 2, 3: return [items]
    case 4:       return [Array(items.prefix(2)), Array(items.suffix(2))]
    case 5:       return [Array(items.prefix(3)), Array(items.suffix(2))]
    default:      return [Array(items.prefix(3)), Array(items.suffix(3))]
    }
}

// MARK: - Card Chart Panel

enum CardChartPanel: String, CaseIterable, Equatable {
    case map                 = "지도"
    case splits              = "스플릿"
    case heartRate           = "심박수"
    case cadence             = "케이던스"
    case groundContact       = "지면접촉"
    case strideLength        = "보폭"
    case power               = "파워"
    case verticalOscillation = "수직진폭"
    case elevation           = "고도"
    case intervals           = "인터벌"

    var icon: String {
        switch self {
        case .map:                  "map"
        case .splits:               "chart.bar.fill"
        case .heartRate:            "heart.fill"
        case .cadence:              "figure.run"
        case .groundContact:        "stopwatch"
        case .strideLength:         "arrow.left.and.right"
        case .power:                "bolt.fill"
        case .verticalOscillation:  "arrow.up.and.down"
        case .elevation:            "mountain.2.fill"
        case .intervals:            "repeat"
        }
    }
}

// MARK: - Athletic card (record-only mode, no photo)

struct ShareCardView: View {
    let activity: Activity
    let routeCoordinates: [CLLocationCoordinate2D]
    let insightTitle: String
    let metrics: [ShareMetricItem]
    var raceName: String? = nil
    var miniMeVariant: MiniMeVariant? = nil
    var customMiniMeImage: UIImage? = nil
    var story: WorkoutStory? = nil
    var showMood: Bool = false
    var showMemo: Bool = false
    var chartPanel: CardChartPanel = .map
    var chartSplits: [SplitData] = []
    var chartHRSamples: [(offset: TimeInterval, bpm: Int)] = []
    var chartWorkoutSeries: [(offset: TimeInterval, value: Double)] = []
    var chartIntervalSegments: [IntervalSegment] = []
    var weather: WeatherSnapshot? = nil
    var shoeName: String? = nil

    private var hasMiniMe: Bool { customMiniMeImage != nil || miniMeVariant != nil }

    private var distanceValue: String {
        let km = activity.distance / 1000
        return km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
    }

    private var startDateTimeString: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "yyyy. M. d  a h:mm"
        return df.string(from: activity.date)
    }

    // map only — floats in Spacer area
    @ViewBuilder
    private var chartMiddleSection: some View {
        if chartPanel == .map, !routeCoordinates.isEmpty {
            HStack {
                Spacer()
                RouteLineArt(coordinates: routeCoordinates)
                    .frame(width: 110, height: 110)
                    .padding(.trailing, 20)
            }
            .padding(.bottom, 12)
        }
    }

    // non-map chart — anchored inside the bottom VStack, above the divider
    @ViewBuilder
    private var chartAboveDivider: some View {
        if chartPanel != .map {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: chartPanel.icon)
                            .font(.system(size: 7))
                        Text(chartPanel.rawValue)
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(0.3)
                    }
                    .foregroundStyle(Color.white.opacity(0.55))
                    chartContent
                }
                .padding(.trailing, 20)
            }
            .padding(.top, 6)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var chartContent: some View {
        switch chartPanel {
        case .splits where !chartSplits.isEmpty:
            CardSplitsChart(splits: chartSplits)
        case .intervals where !chartIntervalSegments.isEmpty:
            CardIntervalChart(segments: chartIntervalSegments)
        case .heartRate where !chartHRSamples.isEmpty:
            CardHRChart(samples: chartHRSamples)
                .frame(width: 130, height: 83).clipped()
        case .cadence, .groundContact, .strideLength, .power, .verticalOscillation, .elevation
             where !chartWorkoutSeries.isEmpty:
            CardWorkoutSeriesChart(samples: chartWorkoutSeries, panel: chartPanel)
                .frame(width: 130, height: 83).clipped()
        default:
            EmptyView()
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {

                // ── TOP: Wordmark + Insight + MiniMe ─────────────
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 0) {
                            Text("MIMO")
                                .font(.system(size: 9, weight: .black))
                                .tracking(2)
                                .foregroundStyle(.white)
                            Text(" RUNNING")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(Theme.violet)
                        }
                        Text(insightTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.90))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        if let race = raceName {
                            HStack(spacing: 4) {
                                Image(systemName: "flag.checkered")
                                    .font(.system(size: 8, weight: .semibold))
                                Text(race)
                                    .font(.system(size: 9, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.violet.opacity(0.18))
                            .clipShape(Capsule())
                        }
                        if showMood, let s = story {
                            HStack(spacing: 4) {
                                Image(systemName: s.mood.sfSymbol)
                                    .font(.system(size: 10))
                                    .foregroundStyle(moodCardColor(s.mood))
                                Text(s.mood.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(moodCardColor(s.mood))
                            }
                        }
                        if showMemo, let s = story, !s.memo.isEmpty {
                            Text(s.memo)
                                .font(.system(size: 11, weight: .regular, design: .serif).italic())
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    if hasMiniMe {
                        MiniMeOrCustomImage(customImage: customMiniMeImage, variant: miniMeVariant, size: 54)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Spacer()

                // ── MIDDLE: map / chart — right-aligned, same spot ──
                chartMiddleSection

                // ── BOTTOM: Date · Divider · Stats ──
                VStack(alignment: .leading, spacing: 0) {
                    chartAboveDivider

                    if let w = weather {
                        HStack(spacing: 3) {
                            Image(systemName: w.systemIcon)
                                .font(.system(size: 8))
                            Text(w.formattedTemp)
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.80))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 2)
                    }
                    HStack {
                        Text(startDateTimeString)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.80))
                        if let shoe = shoeName {
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: "shoe.fill").font(.system(size: 8))
                                Text(shoe).font(.system(size: 9, weight: .medium)).lineLimit(1)
                            }
                            .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 3)

                    Rectangle()
                        .fill(Theme.violet.opacity(0.30))
                        .frame(height: 0.5)
                        .padding(.horizontal, 20)

                    HStack(alignment: .center, spacing: 0) {
                        let distW: CGFloat = metrics.count >= 5 ? 70 : 96
                        let distPt: CGFloat = metrics.count >= 5 ? 28 : 38
                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text(distanceValue)
                                .font(.system(size: distPt, weight: .black).width(.condensed))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            Text("KM")
                                .font(.system(size: 10, weight: .bold).width(.condensed))
                                .foregroundStyle(Theme.violet)
                                .padding(.bottom, 2)
                        }
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(width: distW, alignment: .leading)
                        .padding(.leading, 20)

                        if !metrics.isEmpty {
                            Rectangle()
                                .fill(.white.opacity(0.07))
                                .frame(width: 0.5, height: 36)

                            let rows = metricsRows(metrics)
                            VStack(spacing: rows.count > 1 ? 3 : 0) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                    HStack(spacing: 0) {
                                        ForEach(row) { m in
                                            CardMetric(value: m.value, label: m.label, color: m.color,
                                                       valueSize: row.count >= 5 ? 11 : 12, labelSize: 8)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)

                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Compact card charts

private struct CardSplitsChart: View {
    let splits: [SplitData]
    @State private var labelX: [Int: CGFloat] = [:]

    var body: some View {
        let paces = splits.map(\.paceSecPerKm)
        let lo = (paces.min() ?? 240) * 0.86
        let sorted = paces.sorted()
        let p90 = sorted[(sorted.count - 1) * 9 / 10]
        let rawHi = paces.max() ?? 360
        let hi = rawHi > p90 * 1.5 ? p90 * 1.18 : rawHi * 1.06
        let n = splits.count
        let step: Int = n <= 6 ? 1 : n <= 15 ? 2 : n <= 30 ? 5 : 10
        let chartW: CGFloat = 130
        let barW: CGFloat = n <= 6 ? 7 : n <= 12 ? 5 : n <= 20 ? 4 : 3
        VStack(spacing: 1) {
            Chart {
                ForEach(splits) { split in
                    BarMark(x: .value("km", split.id), y: .value("pace", split.paceSecPerKm),
                            width: .fixed(barW))
                        .foregroundStyle(Theme.pace.gradient)
                        .cornerRadius(2)
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXScale(domain: 0.5...(Double(n) + 0.5))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.10))
                    AxisValueLabel {
                        if let sec = val.as(Double.self) {
                            Text(String(format: "%d'%02d\"", Int(sec) / 60, Int(sec) % 60))
                                .font(.system(size: 6.5))
                                .foregroundStyle(Color.white.opacity(0.80))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                Color.clear.onAppear {
                    var positions: [Int: CGFloat] = [:]
                    for id in 1...n where id % step == 0 {
                        if let x = proxy.position(forX: id) { positions[id] = x }
                    }
                    labelX = positions
                }
            }
            .frame(width: chartW, height: 63)
            .clipped()

            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(Array(labelX.keys.sorted()), id: \.self) { id in
                    Text("\(id)")
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .fixedSize()
                        .position(x: labelX[id]!, y: 5)
                }
            }
            .frame(width: chartW, height: 10)
        }
    }
}

private struct CardHRChart: View {
    let samples: [(offset: TimeInterval, bpm: Int)]

    private var displaySamples: [(offset: TimeInterval, bpm: Int)] {
        guard samples.count > 60 else { return samples }
        let step = samples.count / 60
        return samples.enumerated().filter { $0.offset % step == 0 }.map(\.element)
    }

    var body: some View {
        let pts = displaySamples
        let vals = pts.map { Double($0.bpm) }
        let lo = (vals.min() ?? 60) - 8
        let hi = (vals.max() ?? 180) + 8
        Chart {
            ForEach(Array(pts.enumerated()), id: \.offset) { _, s in
                AreaMark(x: .value("t", s.offset), yStart: .value("", lo), yEnd: .value("bpm", Double(s.bpm)))
                    .foregroundStyle(Theme.heartRate.opacity(0.18))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("t", s.offset), y: .value("bpm", Double(s.bpm)))
                    .foregroundStyle(Theme.heartRate)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.0))
            }
        }
        .chartYScale(domain: lo...hi)
        .chartXScale(domain: 0...(Double(pts.last?.offset ?? 1)))
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.10))
                AxisValueLabel {
                    if let v = val.as(Double.self) {
                        Text("\(Int(v))")
                            .font(.system(size: 6.5))
                            .foregroundStyle(Color.white.opacity(0.80))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { val in
                AxisValueLabel {
                    if let t = val.as(Double.self) {
                        Text("\(Int(t / 60))분")
                            .font(.system(size: 6))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                }
            }
        }
    }
}

private struct CardWorkoutSeriesChart: View {
    let samples: [(offset: TimeInterval, value: Double)]
    let panel: CardChartPanel

    private var lineColor: Color {
        switch panel {
        case .elevation: Theme.elevation
        case .power:     Theme.power
        default:         Theme.runningForm
        }
    }

    private func yLabel(_ v: Double) -> String {
        switch panel {
        case .strideLength:        return String(format: "%.2f", v)
        case .verticalOscillation: return String(format: "%.1f", v)
        default:                   return "\(Int(v.rounded()))"
        }
    }

    // Filter outliers, then bucket into ≤60 windows and average — removes zero-spikes and shows flow
    private var displaySamples: [(offset: TimeInterval, value: Double)] {
        let minVal: Double
        switch panel {
        case .cadence: minVal = 50.0   // < 50 spm = not running (artifact)
        case .power:   minVal = 5.0
        default:       minVal = 0.0
        }
        let filtered = samples.filter { $0.value > minVal }
        guard filtered.count > 1 else { return filtered }
        let total = filtered.last!.offset
        guard total > 0 else { return filtered }
        let n = min(60, filtered.count)
        let bSize = total / Double(n)
        var result: [(offset: TimeInterval, value: Double)] = []
        for i in 0..<n {
            let lo = Double(i) * bSize
            let hi = lo + bSize
            let vals = filtered.filter { $0.offset >= lo && $0.offset < hi }.map(\.value)
            guard !vals.isEmpty else { continue }
            result.append((offset: lo + bSize / 2, value: vals.reduce(0, +) / Double(vals.count)))
        }
        return result
    }

    var body: some View {
        let pts = displaySamples
        let vals = pts.map(\.value)
        let spread = (vals.max() ?? 100) - (vals.min() ?? 0)
        let pad = max(spread * 0.08, 1.0)
        let lo: Double = panel == .strideLength ? 0.5 : (vals.min() ?? 0) - pad
        let hi = (vals.max() ?? 100) + pad
        Chart {
            ForEach(Array(pts.enumerated()), id: \.offset) { _, s in
                AreaMark(x: .value("t", s.offset), yStart: .value("", lo), yEnd: .value("v", s.value))
                    .foregroundStyle(lineColor.opacity(0.18))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("t", s.offset), y: .value("v", s.value))
                    .foregroundStyle(lineColor)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.0))
            }
        }
        .chartYScale(domain: lo...hi)
        .chartXScale(domain: 0...(pts.last?.offset ?? 1))
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.10))
                AxisValueLabel {
                    if let v = val.as(Double.self) {
                        Text(yLabel(v))
                            .font(.system(size: 6.5))
                            .foregroundStyle(Color.white.opacity(0.80))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { val in
                AxisValueLabel {
                    if let t = val.as(Double.self) {
                        Text("\(Int(t / 60))분")
                            .font(.system(size: 6))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                }
            }
        }
    }
}

private struct CardIntervalChart: View {
    let segments: [IntervalSegment]
    @State private var labelX: [Int: CGFloat] = [:]

    var body: some View {
        let paces = segments.compactMap(\.paceSecPerKm).filter { $0 > 0 }
        let lo = (paces.min() ?? 240) * 0.86
        let sorted = paces.sorted()
        let p90 = sorted[(sorted.count - 1) * 9 / 10]
        let rawHi = paces.max() ?? 360
        let hi = rawHi > p90 * 1.5 ? p90 * 1.18 : rawHi * 1.06
        let n = segments.count
        let step: Int = n <= 6 ? 1 : n <= 15 ? 2 : n <= 30 ? 5 : 10
        let chartW: CGFloat = 130
        let barW: CGFloat = n <= 6 ? 7 : n <= 12 ? 5 : n <= 20 ? 4 : 3
        VStack(spacing: 1) {
            Chart {
                ForEach(segments) { seg in
                    let pace = seg.paceSecPerKm ?? hi
                    let isWork = seg.stepLabel == "운동"
                    BarMark(x: .value("구간", seg.id), y: .value("pace", pace),
                            width: .fixed(barW))
                        .foregroundStyle((isWork ? Theme.violet : Color.white.opacity(0.25)).gradient)
                        .cornerRadius(2)
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXScale(domain: 0.5...(Double(n) + 0.5))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.10))
                    AxisValueLabel {
                        if let sec = val.as(Double.self) {
                            Text(String(format: "%d'%02d\"", Int(sec) / 60, Int(sec) % 60))
                                .font(.system(size: 6.5))
                                .foregroundStyle(Color.white.opacity(0.80))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                Color.clear.onAppear {
                    var positions: [Int: CGFloat] = [:]
                    for id in 1...n where id % step == 0 {
                        if let x = proxy.position(forX: id) { positions[id] = x }
                    }
                    labelX = positions
                }
            }
            .frame(width: chartW, height: 63)
            .clipped()

            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(Array(labelX.keys.sorted()), id: \.self) { id in
                    Text("\(id)")
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .fixedSize()
                        .position(x: labelX[id]!, y: 5)
                }
            }
            .frame(width: chartW, height: 10)
        }
    }
}


// MARK: - Photo card (photo background, unified athletic + story)

private struct PhotoShareCardView: View {
    let activity: Activity
    let photo: UIImage
    let insightTitle: String
    let metrics: [ShareMetricItem]
    var raceName: String? = nil
    var story: WorkoutStory? = nil
    var showMood: Bool = false
    var showMemo: Bool = false
    var miniMeVariant: MiniMeVariant? = nil
    var customMiniMeImage: UIImage? = nil
    var routeCoordinates: [CLLocationCoordinate2D] = []
    var chartPanel: CardChartPanel = .map
    var chartSplits: [SplitData] = []
    var chartHRSamples: [(offset: TimeInterval, bpm: Int)] = []
    var chartWorkoutSeries: [(offset: TimeInterval, value: Double)] = []
    var chartIntervalSegments: [IntervalSegment] = []
    var weather: WeatherSnapshot? = nil
    var shoeName: String? = nil
    @Binding var photoOffset: CGSize
    @State private var gestureStart: CGSize = .zero

    private func maxOffset(for cardSize: CGSize) -> CGSize {
        let s = photo.size
        guard s.width > 0, s.height > 0 else { return .zero }
        let scale = max(cardSize.width / s.width, cardSize.height / s.height)
        return CGSize(
            width: max(0, (s.width * scale - cardSize.width) / 2),
            height: max(0, (s.height * scale - cardSize.height) / 2)
        )
    }

    private var distanceValue: String {
        let km = activity.distance / 1000
        return km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
    }
    private var startDateTimeString: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "yyyy. M. d  a h:mm"
        return df.string(from: activity.date)
    }
    private var hasMiniMe: Bool { customMiniMeImage != nil || miniMeVariant != nil }

    @ViewBuilder private var chartContent: some View {
        switch chartPanel {
        case .splits where !chartSplits.isEmpty:
            CardSplitsChart(splits: chartSplits)
        case .intervals where !chartIntervalSegments.isEmpty:
            CardIntervalChart(segments: chartIntervalSegments)
        case .heartRate where !chartHRSamples.isEmpty:
            CardHRChart(samples: chartHRSamples)
                .frame(width: 120, height: 70).clipped()
        case .cadence, .groundContact, .strideLength, .power, .verticalOscillation, .elevation
             where !chartWorkoutSeries.isEmpty:
            CardWorkoutSeriesChart(samples: chartWorkoutSeries, panel: chartPanel)
                .frame(width: 120, height: 70).clipped()
        default:
            EmptyView()
        }
    }

    var body: some View {
        GeometryReader { proxy in
        let max = maxOffset(for: proxy.size)
        ZStack {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .offset(photoOffset)

            LinearGradient(
                colors: [Color.black.opacity(0.60), Color.clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.30)
            )

            LinearGradient(
                colors: [Color.black.opacity(0.90), Color.black.opacity(0.65), Color.clear],
                startPoint: .bottom,
                endPoint: UnitPoint(x: 0.5, y: 0.65)
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 0) {
                            Text("MIMO")
                                .font(.system(size: 9, weight: .black))
                                .tracking(2)
                                .foregroundStyle(.white)
                            Text(" RUNNING")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(Theme.violet)
                        }

                        if !insightTitle.isEmpty {
                            Text(insightTitle)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white.opacity(0.90))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }

                        let hasBadges = raceName != nil || (showMood && story != nil)
                        if hasBadges {
                            HStack(spacing: 6) {
                                if let race = raceName {
                                    HStack(spacing: 3) {
                                        Image(systemName: "flag.checkered")
                                            .font(.system(size: 8, weight: .semibold))
                                        Text(race)
                                            .font(.system(size: 8.5, weight: .semibold))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(Theme.violet)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Theme.violet.opacity(0.22))
                                    .clipShape(Capsule())
                                }
                                if showMood, let s = story {
                                    HStack(spacing: 3) {
                                        Image(systemName: s.mood.sfSymbol)
                                            .font(.system(size: 8))
                                            .foregroundStyle(moodCardColor(s.mood))
                                        Text(s.mood.label)
                                            .font(.system(size: 8.5, weight: .medium))
                                            .foregroundStyle(moodCardColor(s.mood))
                                    }
                                }
                            }
                        }

                        if showMemo, let s = story, !s.memo.isEmpty {
                            Text(s.memo)
                                .font(.system(size: 11, weight: .regular, design: .serif).italic())
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 8)

                    if hasMiniMe {
                        MiniMeOrCustomImage(customImage: customMiniMeImage, variant: miniMeVariant, size: 54)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)

                Spacer()

                if chartPanel == .map, !routeCoordinates.isEmpty {
                    HStack {
                        Spacer()
                        RouteLineArt(coordinates: routeCoordinates)
                            .frame(width: 120, height: 120)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
                } else if chartPanel != .map {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 3) {
                                Image(systemName: chartPanel.icon)
                                    .font(.system(size: 7))
                                Text(chartPanel.rawValue)
                                    .font(.system(size: 8, weight: .semibold))
                                    .tracking(0.3)
                            }
                            .foregroundStyle(Color.white.opacity(0.55))
                            chartContent
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
                }

                if let w = weather {
                    HStack(spacing: 3) {
                        Image(systemName: w.systemIcon)
                            .font(.system(size: 8))
                        Text(w.formattedTemp)
                            .font(.system(size: 8, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.80))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 2)
                }
                HStack {
                    Text(startDateTimeString)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.80))
                    if let shoe = shoeName {
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "shoe.fill").font(.system(size: 8))
                            Text(shoe).font(.system(size: 9, weight: .medium)).lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 3)

                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(height: 0.5)
                    .padding(.horizontal, 18)

                HStack(alignment: .center, spacing: 0) {
                    let distW: CGFloat = metrics.count >= 5 ? 60 : 80
                    let distPt: CGFloat = metrics.count >= 5 ? 23 : 32
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(distanceValue)
                            .font(.system(size: distPt, weight: .black).width(.condensed))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("KM")
                            .font(.system(size: 8.5, weight: .bold).width(.condensed))
                            .foregroundStyle(Theme.violet)
                            .padding(.bottom, 1)
                    }
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(width: distW, alignment: .leading)

                    if !metrics.isEmpty {
                        Rectangle()
                            .fill(.white.opacity(0.25))
                            .frame(width: 0.5, height: 26)

                        let rows = metricsRows(metrics)
                        VStack(spacing: rows.count > 1 ? 2 : 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 0) {
                                    ForEach(row) { m in
                                        PhotoCardMetric(value: m.value, label: m.label, color: m.color)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.top, 1)
                .padding(.bottom, 8)

            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)

            if max.width > 1 || max.height > 1 {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                photoOffset = CGSize(
                                    width: min(max.width, Swift.max(-max.width,
                                               gestureStart.width + value.translation.width)),
                                    height: min(max.height, Swift.max(-max.height,
                                                gestureStart.height + value.translation.height))
                                )
                            }
                            .onEnded { _ in gestureStart = photoOffset }
                    )
            }
        }
        .clipped()
        }
        .onChange(of: photoOffset) { _, new in
            if new == .zero { gestureStart = .zero }
        }
    }
}

// MARK: - Metric column (athletic mode)

private struct CardMetric: View {
    let value: String
    let label: String
    let color: Color
    var valueSize: CGFloat = 14
    var labelSize: CGFloat = 9

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: labelSize, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Metric column (photo mode)

private struct PhotoCardMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Route line art (Canvas)

private struct RouteLineArt: View {
    let coordinates: [CLLocationCoordinate2D]

    var body: some View {
        Canvas { ctx, size in
            ctx.stroke(
                buildPath(in: CGRect(origin: .zero, size: size)),
                with: .color(Theme.violet.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func buildPath(in rect: CGRect) -> Path {
        guard coordinates.count > 1 else { return Path() }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return Path() }

        let latRange = max(maxLat - minLat, 0.0001)
        let lonRange = max(maxLon - minLon, 0.0001)
        let inset: CGFloat = 4
        let draw = rect.insetBy(dx: inset, dy: inset)
        let scale = min(draw.width / CGFloat(lonRange), draw.height / CGFloat(latRange))
        let ox = draw.minX + (draw.width  - CGFloat(lonRange) * scale) / 2
        let oy = draw.minY + (draw.height - CGFloat(latRange)  * scale) / 2

        let step = max(1, coordinates.count / 300)
        return Path { path in
            var moved = false
            for i in Swift.stride(from: 0, to: coordinates.count, by: step) {
                let c = coordinates[i]
                let pt = CGPoint(
                    x: ox + CGFloat(c.longitude - minLon) * scale,
                    y: oy + CGFloat(maxLat - c.latitude) * scale
                )
                if !moved { path.move(to: pt); moved = true }
                else { path.addLine(to: pt) }
            }
        }
    }
}

// MARK: - MiniMe or custom image

private struct MiniMeOrCustomImage: View {
    var customImage: UIImage?
    var variant: MiniMeVariant?
    var size: CGFloat

    var body: some View {
        if let img = customImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if let v = variant {
            MiniMeView(variant: v, size: size)
        }
    }
}

// MARK: - Share Template

private enum ShareTemplate: String, CaseIterable {
    case athletic    = "애슬레틱"
    case story       = "스토리"
    case video       = "영상"
    case routeVideo  = "경로 영상"
}

// MARK: - Story Share Card (no photo — dark card)

private struct StoryShareCardView: View {
    let activity: Activity
    let routeCoordinates: [CLLocationCoordinate2D]
    let story: WorkoutStory
    let insightTitle: String
    var metrics: [ShareMetricItem] = []
    var raceName: String? = nil
    var miniMeVariant: MiniMeVariant? = nil
    var customMiniMeImage: UIImage? = nil
    var showMood: Bool = true
    var showMemo: Bool = true
    var chartPanel: CardChartPanel = .map
    var chartSplits: [SplitData] = []
    var chartHRSamples: [(offset: TimeInterval, bpm: Int)] = []
    var chartWorkoutSeries: [(offset: TimeInterval, value: Double)] = []
    var chartIntervalSegments: [IntervalSegment] = []
    var weather: WeatherSnapshot? = nil
    var shoeName: String? = nil

    private var distanceValue: String {
        let km = activity.distance / 1000
        return km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
    }
    private var moodColor: Color { moodCardColor(story.mood) }
    private var hasMiniMe: Bool { customMiniMeImage != nil || miniMeVariant != nil }
    private var startDateTimeString: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "yyyy. M. d  a h:mm"
        return df.string(from: activity.date)
    }

    @ViewBuilder private var chartContent: some View {
        switch chartPanel {
        case .splits where !chartSplits.isEmpty:
            CardSplitsChart(splits: chartSplits)
        case .intervals where !chartIntervalSegments.isEmpty:
            CardIntervalChart(segments: chartIntervalSegments)
        case .heartRate where !chartHRSamples.isEmpty:
            CardHRChart(samples: chartHRSamples)
                .frame(width: 130, height: 83).clipped()
        case .cadence, .groundContact, .strideLength, .power, .verticalOscillation, .elevation
             where !chartWorkoutSeries.isEmpty:
            CardWorkoutSeriesChart(samples: chartWorkoutSeries, panel: chartPanel)
                .frame(width: 130, height: 83).clipped()
        default:
            EmptyView()
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1E1428"), Color(hex: "0D0912")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 0) {
                            Text("MIMO")
                                .font(.system(size: 9, weight: .black))
                                .tracking(2)
                                .foregroundStyle(.white)
                            Text(" RUNNING")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(Theme.violet)
                        }

                        if !insightTitle.isEmpty {
                            Text(insightTitle)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white.opacity(0.90))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }

                        let hasBadges = raceName != nil || showMood
                        if hasBadges {
                            HStack(spacing: 6) {
                                if let race = raceName {
                                    HStack(spacing: 3) {
                                        Image(systemName: "flag.checkered")
                                            .font(.system(size: 8, weight: .semibold))
                                        Text(race)
                                            .font(.system(size: 8.5, weight: .semibold))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(Theme.violet)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Theme.violet.opacity(0.18))
                                    .clipShape(Capsule())
                                }
                                if showMood {
                                    HStack(spacing: 3) {
                                        Image(systemName: story.mood.sfSymbol)
                                            .font(.system(size: 9))
                                            .foregroundStyle(moodColor)
                                        Text(story.mood.label)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(moodColor)
                                    }
                                }
                            }
                        }

                        if showMemo, !story.memo.isEmpty {
                            Text("\u{201C}\(story.memo)\u{201D}")
                                .font(.system(size: 15, weight: .regular, design: .serif).italic())
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 8)

                    if hasMiniMe {
                        MiniMeOrCustomImage(customImage: customMiniMeImage, variant: miniMeVariant, size: 54)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Spacer()

                if chartPanel == .map, !routeCoordinates.isEmpty {
                    HStack {
                        Spacer()
                        RouteLineArt(coordinates: routeCoordinates)
                            .frame(width: 130, height: 130)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                } else if chartPanel != .map {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 3) {
                                Image(systemName: chartPanel.icon)
                                    .font(.system(size: 7))
                                Text(chartPanel.rawValue)
                                    .font(.system(size: 8, weight: .semibold))
                                    .tracking(0.3)
                            }
                            .foregroundStyle(Color.white.opacity(0.55))
                            chartContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                if let w = weather {
                    HStack(spacing: 3) {
                        Image(systemName: w.systemIcon)
                            .font(.system(size: 8))
                        Text(w.formattedTemp)
                            .font(.system(size: 8, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.80))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 2)
                }
                HStack {
                    Text(startDateTimeString)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.80))
                    if let shoe = shoeName {
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "shoe.fill").font(.system(size: 8))
                            Text(shoe).font(.system(size: 9, weight: .medium)).lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 3)

                Rectangle()
                    .fill(Theme.violet.opacity(0.30))
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)

                HStack(alignment: .center, spacing: 0) {
                    let distW: CGFloat = metrics.count >= 5 ? 70 : 96
                    let distPt: CGFloat = metrics.count >= 5 ? 28 : 38
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(distanceValue)
                            .font(.system(size: distPt, weight: .black).width(.condensed))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("KM")
                            .font(.system(size: 10, weight: .bold).width(.condensed))
                            .foregroundStyle(Theme.violet)
                            .padding(.bottom, 2)
                    }
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(width: distW, alignment: .leading)

                    if !metrics.isEmpty {
                        Rectangle()
                            .fill(.white.opacity(0.07))
                            .frame(width: 0.5, height: 36)

                        let rows = metricsRows(metrics)
                        VStack(spacing: rows.count > 1 ? 3 : 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 0) {
                                    ForEach(row) { m in
                                        CardMetric(value: m.value, label: m.label, color: m.color,
                                                   valueSize: row.count >= 5 ? 11 : 12, labelSize: 8)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 3)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Video Overlay Card (rendered via ImageRenderer at 216×384pt × scale 5 → 1080×1920px)

private struct VideoOverlayCard: View {
    let insightTitle: String
    let distanceKm: String
    let date: Date
    let metrics: [ShareMetricItem]
    let raceName: String?
    let miniMeVariant: MiniMeVariant?
    let miniMeImage: UIImage?
    let chartPanel: CardChartPanel
    let chartSplits: [SplitData]
    let chartHRSamples: [(offset: TimeInterval, bpm: Int)]
    let chartWorkoutSeries: [(offset: TimeInterval, value: Double)]
    let chartIntervalSegments: [IntervalSegment]
    let weather: WeatherSnapshot?

    private var startDateTimeString: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "yyyy. M. d  a h:mm"
        return df.string(from: date)
    }

    @ViewBuilder private var chartContent: some View {
        switch chartPanel {
        case .splits where !chartSplits.isEmpty:
            CardSplitsChart(splits: chartSplits)
        case .intervals where !chartIntervalSegments.isEmpty:
            CardIntervalChart(segments: chartIntervalSegments)
        case .heartRate where !chartHRSamples.isEmpty:
            CardHRChart(samples: chartHRSamples)
                .frame(width: 110, height: 55).clipped()
        case .cadence, .groundContact, .strideLength, .power, .verticalOscillation, .elevation
             where !chartWorkoutSeries.isEmpty:
            CardWorkoutSeriesChart(samples: chartWorkoutSeries, panel: chartPanel)
                .frame(width: 110, height: 55).clipped()
        default:
            EmptyView()
        }
    }

    var body: some View {
        ZStack {
            Color.clear

            // Bottom scrim (weather/date/stats area)
            LinearGradient(
                colors: [Color.black.opacity(0.92), Color.black.opacity(0.70), Color.clear],
                startPoint: .bottom,
                endPoint: UnitPoint(x: 0.5, y: 0.50)
            )

            // Top scrim (wordmark/insight/MiniMe area)
            LinearGradient(
                colors: [Color.black.opacity(0.65), Color.black.opacity(0.25), Color.clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.30)
            )

            VStack(alignment: .leading, spacing: 0) {

                // ── TOP: Wordmark + Insight + MiniMe (mirrors Athletic layout) ──
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 0) {
                            Text("MIMO")
                                .font(.system(size: 6, weight: .black))
                                .tracking(2)
                                .foregroundStyle(.white)
                            Text(" RUNNING")
                                .font(.system(size: 6, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(Theme.violet)
                        }
                        if !insightTitle.isEmpty {
                            Text(insightTitle)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.90))
                                .lineLimit(2)
                        }
                        if let race = raceName {
                            HStack(spacing: 2) {
                                Image(systemName: "flag.checkered")
                                    .font(.system(size: 6, weight: .semibold))
                                Text(race)
                                    .font(.system(size: 6.5, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.violet.opacity(0.20))
                            .clipShape(Capsule())
                        }
                    }
                    Spacer(minLength: 4)
                    if miniMeVariant != nil || miniMeImage != nil {
                        MiniMeOrCustomImage(customImage: miniMeImage, variant: miniMeVariant, size: 38)
                    }
                }
                .padding(.top, 12)

                Spacer()

                // ── MIDDLE: chart (right-aligned) ──
                if chartPanel != .map {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 3) {
                                Image(systemName: chartPanel.icon)
                                    .font(.system(size: 6))
                                Text(chartPanel.rawValue)
                                    .font(.system(size: 7, weight: .semibold))
                                    .tracking(0.3)
                            }
                            .foregroundStyle(Color.white.opacity(0.55))
                            chartContent
                        }
                    }
                    .padding(.bottom, 3)
                }

                // ── BOTTOM: weather · date · divider · stats ──
                if let w = weather {
                    HStack(spacing: 2) {
                        Image(systemName: w.systemIcon)
                            .font(.system(size: 5.5))
                        Text(w.formattedTemp)
                            .font(.system(size: 5.5, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.80))
                    .padding(.bottom, 1)
                }
                Text(startDateTimeString)
                    .font(.system(size: 6, weight: .medium))
                    .foregroundStyle(.white.opacity(0.80))
                    .padding(.bottom, 2)

                Rectangle()
                    .fill(Theme.violet.opacity(0.30))
                    .frame(height: 0.5)

                HStack(alignment: .center, spacing: 0) {
                    let distW: CGFloat = metrics.count >= 5 ? 49 : 67
                    let distPt: CGFloat = metrics.count >= 5 ? 20 : 27
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(distanceKm)
                            .font(.system(size: distPt, weight: .black).width(.condensed))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("KM")
                            .font(.system(size: 7, weight: .bold).width(.condensed))
                            .foregroundStyle(Theme.violet)
                            .padding(.bottom, 1)
                    }
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(width: distW, alignment: .leading)

                    if !metrics.isEmpty {
                        Rectangle()
                            .fill(.white.opacity(0.07))
                            .frame(width: 0.5, height: 25)

                        let rows = metricsRows(metrics)
                        VStack(spacing: rows.count > 1 ? 2 : 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 0) {
                                    ForEach(row) { m in
                                        VStack(spacing: 1) {
                                            Text(m.value)
                                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.6)
                                            Text(m.label)
                                                .font(.system(size: 5.5, weight: .semibold))
                                                .foregroundStyle(m.color)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 5)
                        .frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - ShareCardScreen

struct ShareCardScreen: View {
    let activity: Activity
    let detail: ActivityDetail?
    let insight: InsightResult?
    var manager: HealthKitManager? = nil
    var condition: ActivityCondition? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(RaceDetector.self) private var raceDetector
    @Environment(CustomMiniMeStore.self) private var miniMeStore
    @Query private var allStories: [WorkoutStory]
    @Query private var allShoes: [Shoe]
    private var story: WorkoutStory? { allStories.first { $0.workoutID == activity.id.uuidString } }
    private var activeShoe: Shoe? {
        guard let sid = story?.shoeID else { return nil }
        return allShoes.first { $0.id.uuidString == sid }
    }
    private var storyPhotos: [UIImage] { story?.allPhotoImages ?? [] }
    private var storyPhoto: UIImage? { storyPhotos.first }

    private var confirmedRace: PersistedRaceMatch? {
        guard let m = raceDetector.matchFor(activityID: activity.id), m.isConfirmed else { return nil }
        return m
    }
    private var activeRaceName: String? { showRaceOnCard ? confirmedRace?.raceName : nil }

    // MiniMe — shown only in record-only (no photo) mode
    private var computedMiniMeVariant: MiniMeVariant {
        MiniMeVariant.from(theme: insight?.theme ?? .default, workoutType: insight?.workoutType ?? .general)
    }
    private var canShowMiniMe: Bool { true }
    private var activeMiniMeVariant: MiniMeVariant? { (showMiniMe && canShowMiniMe) ? computedMiniMeVariant : nil }
    private var activeMiniMeImage: UIImage? { (showMiniMe && canShowMiniMe) ? miniMeStore.image : nil }

    @State private var storyShareImages: [UIImage] = []
    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @State private var showShareSheet = false
    @State private var selectedPhoto: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoOffset: CGSize = .zero
    @State private var photoOffsets: [Int: CGSize] = [:]
    @State private var template: ShareTemplate = .athletic
    @State private var enabledMetrics: Set<ShareMetric>
    @State private var showInsightOnCard = true
    @State private var showRaceOnCard = true
    @State private var showMiniMe = true
    @State private var showMoodOnCard = false
    @State private var showMemoOnCard = false
    @State private var showShoeOnCard = true
    @State private var carouselPage = 0
    // Video
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var sourceVideoURL: URL?
    @State private var videoPreviewImage: UIImage?
    @State private var isExportingVideo = false
    @State private var exportedVideoFile: SharableVideoFile?
    // Route video
    @State private var routeSnapshot: UIImage?
    @State private var routeSnapshotPoints: [CGPoint] = []
    @State private var routeVideoFile: SharableVideoFile?
    @State private var isExportingRouteVideo = false
    @State private var routeVideoProgress: Double = 0
    @State private var routePreviewProgress: CGFloat = 0
    // Chart panel
    @State private var cardPanel: CardChartPanel = .map
    @State private var shareHRSamples: [(offset: TimeInterval, bpm: Int)] = []
    @State private var shareWorkoutSeries: [(offset: TimeInterval, value: Double)] = []

    private var routeCoords: [CLLocationCoordinate2D] { detail?.routeCoordinates ?? [] }
    private var distanceKmString: String {
        let km = activity.distance / 1000
        return km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
    }
    private var insightTitle: String { insight?.title ?? "오늘의 러닝" }
    private var displayInsightTitle: String { showInsightOnCard ? insightTitle : "" }
    private var startDateTimeString: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "yyyy. M. d  a h:mm"
        return df.string(from: activity.date)
    }
    private var storyHasContent: Bool { story?.hasContent == true }
    private var displayShoeName: String? { (showShoeOnCard && activeShoe != nil) ? activeShoe?.displayName : nil }

    init(activity: Activity, detail: ActivityDetail?, insight: InsightResult?, manager: HealthKitManager? = nil, condition: ActivityCondition? = nil) {
        self.activity = activity
        self.detail = detail
        self.insight = insight
        self.manager = manager
        self.condition = condition
        _enabledMetrics = State(initialValue: Self.computeDefaultMetrics(activity: activity, detail: detail))
    }

    // MARK: - Metric computation

    private var allMetricItems: [ShareMetricItem] {
        var items: [ShareMetricItem] = []
        if let pace = activity.formattedPace {
            items.append(ShareMetricItem(id: .pace, value: pace, label: "/km", color: Theme.pace))
        }
        items.append(ShareMetricItem(id: .duration, value: activity.formattedDuration, label: "시간", color: Theme.time))
        if let hr = activity.avgHeartRate {
            items.append(ShareMetricItem(id: .heartRate, value: "\(hr)", label: "bpm", color: Theme.heartRate))
        }
        if let cad = detail?.avgCadence {
            items.append(ShareMetricItem(id: .cadence, value: "\(cad)", label: "spm", color: Theme.runningForm))
        }
        if let vo2 = detail?.vo2Max {
            items.append(ShareMetricItem(id: .vo2Max, value: String(format: "%.0f", vo2), label: "VO₂max", color: Theme.violet))
        }
        if let cal = activity.calories {
            items.append(ShareMetricItem(id: .calories, value: String(format: "%.0f", cal), label: "kcal", color: Theme.calories))
        }
        return items
    }

    private var enabledMetricItems: [ShareMetricItem] {
        allMetricItems.filter { enabledMetrics.contains($0.id) }
    }

    private func workIntervals(from segs: [IntervalSegment]) -> [IntervalSegment] {
        let labeled = segs.filter { $0.stepLabel == "운동" }
        return labeled.isEmpty ? segs : labeled
    }

    private func isChartPanelAvailable(_ panel: CardChartPanel) -> Bool {
        switch panel {
        case .map:                  !routeCoords.isEmpty
        case .splits:               !(detail?.splits.isEmpty ?? true)
        case .heartRate:            activity.avgHeartRate != nil && manager != nil
        case .cadence:              detail?.avgCadence != nil && manager != nil
        case .groundContact:        detail?.avgGroundContactTime != nil && manager != nil
        case .strideLength:         detail?.avgStrideLength != nil && manager != nil
        case .power:                detail?.avgPower != nil && manager != nil
        case .verticalOscillation:  detail?.avgVerticalOscillation != nil && manager != nil
        case .elevation:            !(detail?.altitudeTimeProfile.isEmpty ?? true)
        case .intervals:            !(detail?.intervalSegments.isEmpty ?? true)
        }
    }

    private static func computeDefaultMetrics(activity: Activity, detail: ActivityDetail?) -> Set<ShareMetric> {
        var d: Set<ShareMetric> = [.pace, .duration]
        if activity.avgHeartRate != nil { d.insert(.heartRate) }
        if detail?.avgCadence != nil   { d.insert(.cadence) }
        if detail?.vo2Max != nil       { d.insert(.vo2Max) }
        if activity.calories != nil    { d.insert(.calories) }
        return d
    }

    // MARK: - Chip toggle rows

    private var chipRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            // ── Row 1: content chips ──────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Insight chip (always shown)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showInsightOnCard.toggle() }
                        Task { await renderCard(showSpinner: false) }
                    } label: {
                        HStack(spacing: 4) {
                            if showInsightOnCard {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                            Text("인사이트")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(showInsightOnCard ? Color.white : Color.white.opacity(0.4))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(showInsightOnCard ? Theme.violet : Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // Story mood + memo chips
                    if let s = story {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { showMoodOnCard.toggle() }
                            Task { await renderCard(showSpinner: false) }
                        } label: {
                            HStack(spacing: 4) {
                                if showMoodOnCard {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Image(systemName: s.mood.sfSymbol)
                                    .font(.system(size: 10))
                                Text("느낌")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(showMoodOnCard ? Color.white : Color.white.opacity(0.4))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(showMoodOnCard ? Theme.violet : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        if !s.memo.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { showMemoOnCard.toggle() }
                                Task { await renderCard(showSpinner: false) }
                            } label: {
                                HStack(spacing: 4) {
                                    if showMemoOnCard {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    Text("메모")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(showMemoOnCard ? Color.white : Color.white.opacity(0.4))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(showMemoOnCard ? Theme.violet : Color.white.opacity(0.08))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // MiniMe chip
                    if canShowMiniMe {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { showMiniMe.toggle() }
                            Task { await renderCard(showSpinner: false) }
                        } label: {
                            HStack(spacing: 4) {
                                if showMiniMe {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text("미니미")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(showMiniMe ? Color.white : Color.white.opacity(0.4))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(showMiniMe ? Theme.violet : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // Shoe chip
                    if let shoe = activeShoe {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { showShoeOnCard.toggle() }
                            Task { await renderCard(showSpinner: false) }
                        } label: {
                            HStack(spacing: 4) {
                                if showShoeOnCard {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Image(systemName: "shoe.fill")
                                    .font(.system(size: 10))
                                Text(shoe.displayName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(showShoeOnCard ? Color.white : Color.white.opacity(0.4))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(showShoeOnCard ? Theme.violet : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // Race chip
                    if let race = confirmedRace {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { showRaceOnCard.toggle() }
                            Task { await renderCard(showSpinner: false) }
                        } label: {
                            HStack(spacing: 4) {
                                if showRaceOnCard {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Image(systemName: "flag.checkered")
                                    .font(.system(size: 10))
                                Text(race.raceName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(showRaceOnCard ? Color.white : Color.white.opacity(0.4))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(showRaceOnCard ? Theme.violet : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
            }

            // ── Row 2: metric chips ───────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allMetricItems) { item in
                        let isOn = enabledMetrics.contains(item.id)
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if isOn { enabledMetrics.remove(item.id) }
                                else    { enabledMetrics.insert(item.id) }
                            }
                            Task { await renderCard(showSpinner: false) }
                        } label: {
                            HStack(spacing: 4) {
                                if isOn {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text(item.id.chipLabel)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.4))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isOn ? Theme.violet : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
            }

            // ── Row 3: chart panel chips ───
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CardChartPanel.allCases, id: \.self) { panel in
                        let available = isChartPanelAvailable(panel)
                        let isSelected = cardPanel == panel
                        Button {
                            guard available else { return }
                            cardPanel = panel
                        } label: {
                            HStack(spacing: 4) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Image(systemName: panel.icon)
                                    .font(.system(size: 10))
                                Text(panel.rawValue)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(
                                available
                                    ? (isSelected ? Color.white : Color.white.opacity(0.4))
                                    : Color.white.opacity(0.18)
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? Theme.violet
                                : Color.white.opacity(available ? 0.08 : 0.04)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Body helpers

    private var cardSection: some View {
        let isNarrow = template == .video || template == .routeVideo
        let w: CGFloat = isNarrow ? 216 : 300
        let h: CGFloat = isNarrow ? 384 : 375
        let r: CGFloat = isNarrow ? 14 : 20
        return cardPreview
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: r))
            .shadow(color: Theme.violet.opacity(0.3), radius: 28, y: 10)
            .animation(.easeInOut(duration: 0.2), value: template)
    }

    @ViewBuilder
    private var carouselDots: some View {
        if template == .story, storyPhotos.count > 1 {
            HStack(spacing: 5) {
                ForEach(0..<storyPhotos.count, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(i == carouselPage ? 1.0 : 0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 6)
        }
    }

    private var templatePicker: some View {
        Picker("", selection: $template) {
            ForEach(ShareTemplate.allCases, id: \.self) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var bottomControls: some View {
        if template == .story {
            HStack(spacing: 14) {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(selectedPhoto == nil ? "사진 추가" : "사진 변경",
                          systemImage: selectedPhoto == nil ? "photo.badge.plus" : "photo")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.violet)
                }
                if selectedPhoto != nil {
                    Button {
                        selectedPhoto = nil; pickerItem = nil
                        clearStoryPhoto(); Task { await renderCard() }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
                    }
                }
            }
            .padding(.bottom, 20)
        } else if template == .video {
            HStack(spacing: 14) {
                PhotosPicker(selection: $videoPickerItem, matching: .videos, photoLibrary: .shared()) {
                    Label(sourceVideoURL == nil ? "영상 선택" : "영상 변경",
                          systemImage: sourceVideoURL == nil ? "video.badge.plus" : "video")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.violet)
                }
                if sourceVideoURL != nil {
                    Button {
                        sourceVideoURL = nil; videoPickerItem = nil
                        videoPreviewImage = nil; exportedVideoFile = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
                    }
                }
            }
            .padding(.bottom, 20)
        } else {
            Spacer(minLength: 20)
        }
        // routeVideo has no bottom picker
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                cardSection
                carouselDots
                Spacer(minLength: 20)
                chipRow.padding(.bottom, 12)
                templatePicker
                bottomControls
                shareCTA.padding(.horizontal, 24).padding(.bottom, 36)
            }
        }
        .navigationTitle("공유")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if selectedPhoto == nil, let sp = storyPhoto { selectedPhoto = sp }
            // Auto-select first available panel when no route
            if routeCoords.isEmpty && cardPanel == .map {
                cardPanel = CardChartPanel.allCases.first { isChartPanelAvailable($0) } ?? .splits
            }
            await renderCard()
        }
        .onChange(of: pickerItem) { _, newItem in
            photoOffset = .zero
            photoOffsets = [:]
            Task {
                guard let item = newItem,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                selectedPhoto = image
                persistStoryPhoto(image)
                await renderCard()
            }
        }
        .onChange(of: videoPickerItem) { _, newItem in
            Task {
                guard let item = newItem,
                      let result = try? await item.loadTransferable(type: VideoPickerResult.self)
                else { return }
                sourceVideoURL = result.url
                videoPreviewImage = await VideoExportService.firstFrame(of: result.url)
                await exportVideo()
            }
        }
        .onChange(of: template) { _, _ in
            if template == .routeVideo, routeSnapshot == nil, !routeCoords.isEmpty {
                Task {
                    if let result = try? await RouteVideoExportService.mapSnapshot(coordinates: routeCoords) {
                        routeSnapshot = result.image
                        routeSnapshotPoints = result.points
                    }
                }
            }
            Task { await renderCard() }
        }
        .onChange(of: cardPanel) { _, newPanel in
            Task {
                await loadChartData(for: newPanel)
                await renderCard(showSpinner: false)
            }
        }
        .task(id: template) {
            guard template == .routeVideo else { return }
            routePreviewProgress = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)   // ~20 fps preview
                routePreviewProgress += 1.0 / 60.0
                if routePreviewProgress > 1.0 { routePreviewProgress = 0 }
            }
        }
    }

    // MARK: - Chart data loading

    private func loadChartData(for panel: CardChartPanel) async {
        guard let mgr = manager else { return }
        shareWorkoutSeries = []
        switch panel {
        case .heartRate:
            shareHRSamples = await mgr.fetchHRTimeSeries(for: activity.id)
        case .cadence:
            shareWorkoutSeries = await mgr.fetchCadenceTimeSeries(for: activity.id)
        case .power:
            shareWorkoutSeries = await mgr.fetchWorkoutTimeSeries(for: activity.id,
                identifier: .runningPower, unit: .watt())
        case .groundContact:
            shareWorkoutSeries = await mgr.fetchWorkoutTimeSeries(for: activity.id,
                identifier: .runningGroundContactTime, unit: .secondUnit(with: .milli))
        case .strideLength:
            shareWorkoutSeries = await mgr.fetchWorkoutTimeSeries(for: activity.id,
                identifier: .runningStrideLength, unit: .meter())
        case .verticalOscillation:
            shareWorkoutSeries = await mgr.fetchWorkoutTimeSeries(for: activity.id,
                identifier: .runningVerticalOscillation, unit: .meterUnit(with: .centi))
        case .elevation:
            shareWorkoutSeries = (detail?.altitudeTimeProfile ?? [])
                .map { (offset: $0.offset, value: $0.altitude) }
        default:
            break
        }
    }

    // MARK: - Video chart content

    @ViewBuilder private var videoChartContent: some View {
        switch cardPanel {
        case .splits where !(detail?.splits.isEmpty ?? true):
            CardSplitsChart(splits: detail?.splits ?? [])
        case .intervals where !(detail?.intervalSegments.isEmpty ?? true):
            CardIntervalChart(segments: detail?.intervalSegments ?? [])
        case .heartRate where !shareHRSamples.isEmpty:
            CardHRChart(samples: shareHRSamples)
                .frame(width: 110, height: 55).clipped()
        case .cadence, .groundContact, .strideLength, .power, .verticalOscillation, .elevation
             where !shareWorkoutSeries.isEmpty:
            CardWorkoutSeriesChart(samples: shareWorkoutSeries, panel: cardPanel)
                .frame(width: 110, height: 55).clipped()
        default:
            EmptyView()
        }
    }

    // MARK: - Card preview

    @ViewBuilder
    private var cardPreview: some View {
        switch template {
        case .athletic:
            ShareCardView(activity: activity, routeCoordinates: routeCoords,
                          insightTitle: displayInsightTitle, metrics: enabledMetricItems,
                          raceName: activeRaceName, miniMeVariant: activeMiniMeVariant,
                          customMiniMeImage: activeMiniMeImage,
                          story: story, showMood: showMoodOnCard, showMemo: showMemoOnCard,
                          chartPanel: cardPanel,
                          chartSplits: detail?.splits ?? [],
                          chartHRSamples: shareHRSamples,
                          chartWorkoutSeries: shareWorkoutSeries,
                          chartIntervalSegments: detail?.intervalSegments ?? [],
                          weather: condition?.weather,
                          shoeName: displayShoeName)
        case .story:
            if let photo = selectedPhoto {
                PhotoShareCardView(activity: activity, photo: photo,
                                   insightTitle: displayInsightTitle,
                                   metrics: enabledMetricItems, raceName: activeRaceName,
                                   story: story, showMood: showMoodOnCard, showMemo: showMemoOnCard,
                                   miniMeVariant: activeMiniMeVariant,
                                   customMiniMeImage: activeMiniMeImage,
                                   routeCoordinates: routeCoords,
                                   chartPanel: cardPanel,
                                   chartSplits: detail?.splits ?? [],
                                   chartHRSamples: shareHRSamples,
                                   chartWorkoutSeries: shareWorkoutSeries,
                                   chartIntervalSegments: detail?.intervalSegments ?? [],
                                   weather: condition?.weather,
                                   shoeName: displayShoeName,
                                   photoOffset: $photoOffset)
            } else if let s = story {
                let photos = storyPhotos
                if photos.count > 1 {
                    TabView(selection: $carouselPage) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { idx, photo in
                            PhotoShareCardView(activity: activity, photo: photo,
                                              insightTitle: displayInsightTitle,
                                              metrics: enabledMetricItems, raceName: activeRaceName,
                                              story: s, showMood: showMoodOnCard, showMemo: showMemoOnCard,
                                              miniMeVariant: activeMiniMeVariant,
                                              customMiniMeImage: activeMiniMeImage,
                                              routeCoordinates: routeCoords,
                                              chartPanel: cardPanel,
                                              chartSplits: detail?.splits ?? [],
                                              chartHRSamples: shareHRSamples,
                                              chartWorkoutSeries: shareWorkoutSeries,
                                              chartIntervalSegments: detail?.intervalSegments ?? [],
                                              weather: condition?.weather,
                                              shoeName: displayShoeName,
                                              photoOffset: Binding(
                                                  get: { photoOffsets[idx, default: .zero] },
                                                  set: { photoOffsets[idx] = $0 }
                                              ))
                                .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                } else {
                    StoryShareCardView(activity: activity, routeCoordinates: routeCoords,
                                       story: s, insightTitle: displayInsightTitle,
                                       metrics: enabledMetricItems,
                                       raceName: activeRaceName, miniMeVariant: activeMiniMeVariant,
                                       customMiniMeImage: activeMiniMeImage,
                                       showMood: showMoodOnCard, showMemo: showMemoOnCard,
                                       chartPanel: cardPanel,
                                       chartSplits: detail?.splits ?? [],
                                       chartHRSamples: shareHRSamples,
                                       chartWorkoutSeries: shareWorkoutSeries,
                                       chartIntervalSegments: detail?.intervalSegments ?? [],
                                       weather: condition?.weather,
                                       shoeName: displayShoeName)
                }
            } else {
                ShareCardView(activity: activity, routeCoordinates: routeCoords,
                              insightTitle: displayInsightTitle, metrics: enabledMetricItems,
                              raceName: activeRaceName, miniMeVariant: activeMiniMeVariant,
                              customMiniMeImage: activeMiniMeImage,
                              story: story, showMood: showMoodOnCard, showMemo: showMemoOnCard,
                              chartPanel: cardPanel,
                              chartSplits: detail?.splits ?? [],
                              chartHRSamples: shareHRSamples,
                              chartWorkoutSeries: shareWorkoutSeries,
                              chartIntervalSegments: detail?.intervalSegments ?? [],
                              weather: condition?.weather,
                              shoeName: displayShoeName)
            }
        case .video:
            videoPreviewCard
        case .routeVideo:
            routeVideoPreviewCard
        }
    }

    // MARK: - Route video preview card

    @ViewBuilder
    private var routeVideoPreviewCard: some View {
        if routeCoords.isEmpty {
            ZStack {
                Color(hex: "0D0D12")
                VStack(spacing: 10) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.violet)
                    Text("야외 경로 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let snap = routeSnapshot {
            RouteVideoFrameView(
                snapshot: snap,
                snapshotPoints: routeSnapshotPoints,
                routeProgress: routePreviewProgress,
                insightTitle: displayInsightTitle,
                metrics: enabledMetricItems,
                raceName: activeRaceName,
                miniMeVariant: activeMiniMeVariant,
                customMiniMeImage: activeMiniMeImage,
                distanceKm: distanceKmString,
                duration: activity.formattedDuration,
                date: activity.date,
                weather: condition?.weather
            )
        } else {
            ZStack {
                Color(hex: "0D0D12")
                VStack(spacing: 10) {
                    ProgressView().tint(Theme.violet)
                    Text("지도 준비 중…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Video preview card (9:16 placeholder with overlay preview)

    private var videoPreviewCard: some View {
        let km = activity.distance / 1000
        let distStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)

        return ZStack {
            // Background: first frame or dark placeholder
            if let preview = videoPreviewImage {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(hex: "0D0D12")
                if !isExportingVideo {
                    VStack(spacing: 10) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.violet)
                        Text("영상을 선택해 주세요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            LinearGradient(
                colors: [Color.black.opacity(0.60), Color.clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.30)
            )

            LinearGradient(
                colors: [Color.black.opacity(0.92), Color.black.opacity(0.70), Color.clear],
                startPoint: .bottom,
                endPoint: UnitPoint(x: 0.5, y: 0.55)
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 0) {
                            Text("MIMO")
                                .font(.system(size: 6, weight: .black))
                                .tracking(2)
                                .foregroundStyle(.white)
                            Text(" RUNNING")
                                .font(.system(size: 6, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(Theme.violet)
                        }

                        if !displayInsightTitle.isEmpty {
                            Text(displayInsightTitle)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.90))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }

                        if let race = activeRaceName {
                            HStack(spacing: 2) {
                                Image(systemName: "flag.checkered")
                                    .font(.system(size: 6, weight: .semibold))
                                Text(race)
                                    .font(.system(size: 6.5, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.violet.opacity(0.20))
                            .clipShape(Capsule())
                        }
                    }

                    Spacer(minLength: 4)

                    if activeMiniMeVariant != nil || activeMiniMeImage != nil {
                        MiniMeOrCustomImage(customImage: activeMiniMeImage, variant: activeMiniMeVariant, size: 38)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)

                Spacer()

                if cardPanel != .map {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 3) {
                                Image(systemName: cardPanel.icon)
                                    .font(.system(size: 6))
                                Text(cardPanel.rawValue)
                                    .font(.system(size: 7, weight: .semibold))
                                    .tracking(0.3)
                            }
                            .foregroundStyle(Color.white.opacity(0.55))
                            videoChartContent
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 3)
                }

                if let w = condition?.weather {
                    HStack(spacing: 2) {
                        Image(systemName: w.systemIcon)
                            .font(.system(size: 5.5))
                        Text(w.formattedTemp)
                            .font(.system(size: 5.5, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.80))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 1)
                }
                Text(startDateTimeString)
                    .font(.system(size: 6, weight: .medium))
                    .foregroundStyle(.white.opacity(0.80))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)

                Rectangle()
                    .fill(Theme.violet.opacity(0.30))
                    .frame(height: 0.5)
                    .padding(.horizontal, 10)

                HStack(alignment: .center, spacing: 0) {
                    let distW: CGFloat = enabledMetricItems.count >= 5 ? 49 : 67
                    let distPt: CGFloat = enabledMetricItems.count >= 5 ? 20 : 27
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(distStr)
                            .font(.system(size: distPt, weight: .black).width(.condensed))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("KM")
                            .font(.system(size: 7, weight: .bold).width(.condensed))
                            .foregroundStyle(Theme.violet)
                            .padding(.bottom, 1)
                    }
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(width: distW, alignment: .leading)

                    if !enabledMetricItems.isEmpty {
                        Rectangle()
                            .fill(.white.opacity(0.07))
                            .frame(width: 0.5, height: 25)

                        let rows = metricsRows(enabledMetricItems)
                        VStack(spacing: rows.count > 1 ? 2 : 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 0) {
                                    ForEach(row) { m in
                                        VStack(spacing: 1) {
                                            Text(m.value)
                                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.6)
                                            Text(m.label)
                                                .font(.system(size: 5.5, weight: .semibold))
                                                .foregroundStyle(m.color)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 5)
                        .frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Export progress overlay
            if isExportingVideo {
                Color.black.opacity(0.55)
                VStack(spacing: 8) {
                    ProgressView().tint(.white).scaleEffect(1.2)
                    Text("합성 중...")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .clipped()
    }

    // MARK: - Share CTA

    @ViewBuilder
    private var shareCTA: some View {
        if template == .video {
            if isExportingVideo {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.violet)
                    Text("영상 합성 중...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else if let vf = exportedVideoFile {
                ShareLink(item: vf, preview: SharePreview("러닝 영상")) {
                    Label("영상 공유하기", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else if sourceVideoURL == nil {
                Text("영상을 선택하면 자동으로 합성돼요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                Text("합성 실패 — 다시 시도해 주세요")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
        } else if template == .routeVideo {
            if routeCoords.isEmpty {
                Text("야외 러닝 경로가 있을 때\n사용할 수 있어요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else if isExportingRouteVideo {
                VStack(spacing: 10) {
                    ProgressView(value: routeVideoProgress)
                        .tint(Theme.violet)
                        .padding(.horizontal, 4)
                    Text("경로 영상 만드는 중… \(Int(routeVideoProgress * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else if let vf = routeVideoFile {
                ShareLink(item: vf, preview: SharePreview("경로 영상")) {
                    Label("경로 영상 공유하기", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Button {
                    Task { await exportRouteVideo() }
                } label: {
                    Label("경로 영상 만들기", systemImage: "film")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(!routeSnapshotPoints.isEmpty ? Theme.violet : Color.gray.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(routeSnapshotPoints.isEmpty)
            }
        } else if isRendering {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.violet)
                Text("카드 만드는 중...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        } else if storyShareImages.count > 1 {
            Button { showShareSheet = true } label: {
                Label("공유하기 (\(storyShareImages.count)장)", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: storyShareImages)
            }
        } else if let img = previewImage {
            Button { showShareSheet = true } label: {
                Label("공유하기", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [img])
            }
        } else {
            Text("카드 생성에 실패했어요")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
    }

    // MARK: - Render

    @MainActor
    private func exportVideo() async {
        guard let url = sourceVideoURL else { return }
        isExportingVideo = true
        exportedVideoFile = nil

        let km = activity.distance / 1000
        let distStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)

        let overlayView = VideoOverlayCard(
            insightTitle: displayInsightTitle,
            distanceKm: distStr,
            date: activity.date,
            metrics: Array(enabledMetricItems.prefix(6)),
            raceName: activeRaceName,
            miniMeVariant: activeMiniMeVariant,
            miniMeImage: activeMiniMeImage,
            chartPanel: cardPanel,
            chartSplits: detail?.splits ?? [],
            chartHRSamples: shareHRSamples,
            chartWorkoutSeries: shareWorkoutSeries,
            chartIntervalSegments: detail?.intervalSegments ?? [],
            weather: condition?.weather
        )
        .frame(width: 216, height: 384)

        let overlayRenderer = ImageRenderer(content: overlayView)
        overlayRenderer.scale = 5.0   // 216 × 5 = 1080 px, 384 × 5 = 1920 px

        guard let overlayImage = overlayRenderer.uiImage else {
            isExportingVideo = false
            return
        }

        if let outputURL = try? await VideoExportService.exportVideo(sourceURL: url, overlay: overlayImage) {
            exportedVideoFile = SharableVideoFile(url: outputURL)
        }
        isExportingVideo = false
    }

    @MainActor
    private func exportRouteVideo() async {
        guard let snap = routeSnapshot, !routeSnapshotPoints.isEmpty else { return }
        isExportingRouteVideo = true
        routeVideoProgress = 0
        routeVideoFile = nil
        do {
            let url = try await RouteVideoExportService.export(
                snapshot: snap,
                snapshotPoints: routeSnapshotPoints,
                insightTitle: displayInsightTitle,
                distanceKm: distanceKmString,
                duration: activity.formattedDuration,
                date: activity.date,
                metrics: Array(enabledMetricItems.prefix(6)),
                raceName: activeRaceName,
                miniMeVariant: activeMiniMeVariant,
                customMiniMeImage: activeMiniMeImage,
                weather: condition?.weather,
                progressHandler: { p in routeVideoProgress = p }
            )
            routeVideoFile = SharableVideoFile(url: url)
        } catch { }
        isExportingRouteVideo = false
    }

    @MainActor
    private func renderCard(showSpinner: Bool = true) async {
        guard template != .video && template != .routeVideo else { return }
        if showSpinner { isRendering = true }
        storyShareImages = []
        previewImage = nil

        let photos = storyPhotos
        if template == .story, selectedPhoto == nil, let s = story, photos.count > 1 {
            var imgs: [UIImage] = []
            for (idx, photo) in photos.enumerated() {
                let renderer = ImageRenderer(content:
                    PhotoShareCardView(activity: activity, photo: photo,
                                       insightTitle: displayInsightTitle,
                                       metrics: enabledMetricItems, raceName: activeRaceName,
                                       story: s, showMood: showMoodOnCard, showMemo: showMemoOnCard,
                                       miniMeVariant: activeMiniMeVariant,
                                       customMiniMeImage: activeMiniMeImage,
                                       routeCoordinates: routeCoords,
                                       chartPanel: cardPanel,
                                       chartSplits: detail?.splits ?? [],
                                       chartHRSamples: shareHRSamples,
                                       chartWorkoutSeries: shareWorkoutSeries,
                                       chartIntervalSegments: detail?.intervalSegments ?? [],
                                       weather: condition?.weather,
                                       shoeName: displayShoeName,
                                       photoOffset: .constant(photoOffsets[idx, default: .zero]))
                        .frame(width: 300, height: 375)
                )
                renderer.scale = 3
                if let img = renderer.uiImage {
                    if idx == 0 { previewImage = img }
                    imgs.append(img)
                }
                await Task.yield()
            }
            storyShareImages = imgs
            isRendering = false
            return
        }

        let renderer = ImageRenderer(content: renderableCard())
        renderer.scale = 3
        guard let img = renderer.uiImage else {
            isRendering = false
            return
        }
        previewImage = img
        isRendering = false
    }

    @ViewBuilder
    private func renderableCard() -> some View {
        switch template {
        case .athletic:
            ShareCardView(activity: activity, routeCoordinates: routeCoords,
                          insightTitle: displayInsightTitle, metrics: enabledMetricItems,
                          raceName: activeRaceName, miniMeVariant: activeMiniMeVariant,
                          customMiniMeImage: activeMiniMeImage,
                          story: story, showMood: showMoodOnCard, showMemo: showMemoOnCard,
                          chartPanel: cardPanel,
                          chartSplits: detail?.splits ?? [],
                          chartHRSamples: shareHRSamples,
                          chartWorkoutSeries: shareWorkoutSeries,
                          chartIntervalSegments: detail?.intervalSegments ?? [],
                          weather: condition?.weather,
                          shoeName: displayShoeName)
                .frame(width: 300, height: 375)
        case .story:
            if let photo = selectedPhoto {
                PhotoShareCardView(activity: activity, photo: photo,
                                   insightTitle: displayInsightTitle,
                                   metrics: enabledMetricItems, raceName: activeRaceName,
                                   story: story, showMood: showMoodOnCard, showMemo: showMemoOnCard,
                                   miniMeVariant: activeMiniMeVariant,
                                   customMiniMeImage: activeMiniMeImage,
                                   routeCoordinates: routeCoords,
                                   chartPanel: cardPanel,
                                   chartSplits: detail?.splits ?? [],
                                   chartHRSamples: shareHRSamples,
                                   chartWorkoutSeries: shareWorkoutSeries,
                                   chartIntervalSegments: detail?.intervalSegments ?? [],
                                   weather: condition?.weather,
                                   shoeName: displayShoeName,
                                   photoOffset: .constant(photoOffset))
                    .frame(width: 300, height: 375)
            } else if let s = story {
                StoryShareCardView(activity: activity, routeCoordinates: routeCoords,
                                   story: s, insightTitle: displayInsightTitle,
                                   metrics: enabledMetricItems,
                                   raceName: activeRaceName, miniMeVariant: activeMiniMeVariant,
                                   customMiniMeImage: activeMiniMeImage,
                                   showMood: showMoodOnCard, showMemo: showMemoOnCard,
                                   chartPanel: cardPanel,
                                   chartSplits: detail?.splits ?? [],
                                   chartHRSamples: shareHRSamples,
                                   chartWorkoutSeries: shareWorkoutSeries,
                                   chartIntervalSegments: detail?.intervalSegments ?? [],
                                   weather: condition?.weather,
                                   shoeName: displayShoeName)
                    .frame(width: 300, height: 375)
            } else {
                ShareCardView(activity: activity, routeCoordinates: routeCoords,
                              insightTitle: displayInsightTitle, metrics: enabledMetricItems,
                              raceName: activeRaceName, miniMeVariant: activeMiniMeVariant,
                              customMiniMeImage: activeMiniMeImage,
                              story: story, showMood: showMoodOnCard, showMemo: showMemoOnCard,
                              chartPanel: cardPanel,
                              chartSplits: detail?.splits ?? [],
                              chartHRSamples: shareHRSamples,
                              chartWorkoutSeries: shareWorkoutSeries,
                              chartIntervalSegments: detail?.intervalSegments ?? [],
                              weather: condition?.weather,
                              shoeName: displayShoeName)
                    .frame(width: 300, height: 375)
            }
        case .video, .routeVideo:
            EmptyView()
        }
    }

    // MARK: - Photo persistence

    private func persistStoryPhoto(_ image: UIImage) {
        guard let filename = WorkoutStory.savePhoto(image, workoutID: activity.id.uuidString, index: 0) else { return }
        if let s = story {
            var filenames = s.photoFilenames
            if filenames.isEmpty {
                filenames = [filename]
            } else {
                filenames[0] = filename
            }
            s.photoFilenames = filenames
            s.photoData = nil
            s.updatedAt = Date()
        } else {
            modelContext.insert(WorkoutStory(workoutID: activity.id.uuidString, photoFilenames: [filename]))
        }
        try? modelContext.save()
    }

    private func clearStoryPhoto() {
        if let s = story {
            if !s.photoFilenames.isEmpty {
                WorkoutStory.deletePhoto(named: s.photoFilenames[0])
                s.photoFilenames.remove(at: 0)
            }
            s.photoData = nil
            s.updatedAt = Date()
            try? modelContext.save()
        }
    }

}

// MARK: - UIActivityViewController wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
