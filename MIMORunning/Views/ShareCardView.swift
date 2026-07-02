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
        let L = AppLanguage.shared
        return switch self {
        case .pace:      L.s("페이스",     "Pace")
        case .duration:  L.s("시간",       "Time")
        case .heartRate: L.s("심박",       "HR")
        case .cadence:   L.s("케이던스",   "Cadence")
        case .vo2Max:    L.s("유산소",     "VO₂max")
        case .calories:  L.s("칼로리",     "Cals")
        case .power:     L.s("파워",       "Power")
        case .elevation: L.s("고도",       "Elev.")
        case .intervals: L.s("반복",       "Intervals")
        case .bestPace:  L.s("최고 페이스", "Best Pace")
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
    case .fantastic: Theme.power
    case .great:     Theme.violet
    case .okay:      Theme.time
    case .tough:     Color.orange
    case .terrible:  Theme.heartRate
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
    case map                 = "경로"
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

    var label: String {
        let L = AppLanguage.shared
        return switch self {
        case .map:                  L.s("경로",    "Route")
        case .splits:               L.s("스플릿",  "Splits")
        case .heartRate:            L.s("심박수",  "HR")
        case .cadence:              L.s("케이던스", "Cadence")
        case .groundContact:        L.s("지면접촉", "Gnd Contact")
        case .strideLength:         L.s("보폭",    "Stride")
        case .power:                L.s("파워",    "Power")
        case .verticalOscillation:  L.s("수직진폭", "Vert. Osc.")
        case .elevation:            L.s("고도",    "Elevation")
        case .intervals:            L.s("인터벌",  "Intervals")
        }
    }
}

// MARK: - Shared overlay constants (cards + video, single source of truth)

enum CardVisual {
    /// Top scrim: black 20% at top edge, fades to clear by 22% of height. Shared by photo and video.
    static var topScrim: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.07), .clear],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.22)
        )
    }
    /// Bottom scrim for photo cards: black 50%, clears at 60% from top.
    static var bottomScrim: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.18), .clear],
            startPoint: .bottom,
            endPoint: UnitPoint(x: 0.5, y: 0.40)
        )
    }
    /// Bottom scrim for video cards: lighter (40%) and narrower — clears at 70% from top.
    static var videoBottomScrim: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.18), .clear],
            startPoint: .bottom,
            endPoint: UnitPoint(x: 0.5, y: 0.30)
        )
    }
    static let textShadowColor:             Color   = .black.opacity(0.70)
    static let textShadowRadius:            CGFloat = 5
    static let largeTextShadowRadius:       CGFloat = 6
    static let textShadowY:                 CGFloat = 1
    static let videoLargeTextShadowColor:   Color   = .black.opacity(0.75)
    /// Photo background brightness correction (+0.03).
    static let photoBrightnessBoost:        Double  = 0.03
    /// Video background brightness correction (+0.10).
    static let videoBrightnessBoost:        Double  = 0.10
    static let videoSaturationBoost:        Double  = 1.05
    static let videoBrightenLayerOpacity:   Float   = 0.10  // white CALayer opacity for AVFoundation path
    /// Route line art shadow: black 55%, radius 3, y 1.
    static let routeShadowColor:  Color   = .black.opacity(0.55)
    static let routeShadowRadius: CGFloat = 3
    static let routeShadowY:      CGFloat = 1
}

extension View {
    /// Drop-shadow for overlay text (small labels, wordmark, insight title).
    func cardTextShadow() -> some View {
        shadow(color: CardVisual.textShadowColor,
               radius: CardVisual.textShadowRadius,
               x: 0, y: CardVisual.textShadowY)
    }
    /// Stronger drop-shadow for large distance numbers and stat values.
    func cardLargeTextShadow() -> some View {
        shadow(color: CardVisual.textShadowColor,
               radius: CardVisual.largeTextShadowRadius,
               x: 0, y: CardVisual.textShadowY)
    }
    /// Strengthened shadow for video distance/stats numbers (75% black, radius 6).
    func cardVideoLargeTextShadow() -> some View {
        shadow(color: CardVisual.videoLargeTextShadowColor,
               radius: CardVisual.largeTextShadowRadius,
               x: 0, y: CardVisual.textShadowY)
    }
    /// Drop-shadow for route line art. Pass a scaled radius for size variants.
    func cardRouteShadow(radius: CGFloat = CardVisual.routeShadowRadius) -> some View {
        shadow(color: CardVisual.routeShadowColor,
               radius: radius,
               x: 0, y: CardVisual.routeShadowY)
    }
}

// MARK: - Shared chart panel components (used by all card styles)

struct CardChartPanelView: View {
    let panel: CardChartPanel
    var splits: [SplitData] = []
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    var hrZones: [HRZoneData] = []
    var workoutSeries: [(offset: TimeInterval, value: Double)] = []
    var intervalSegments: [IntervalSegment] = []

    var body: some View {
        switch panel {
        case .splits where !splits.isEmpty:
            SplitsPanelChart(splits: splits, compact: true)
                .frame(width: 130, height: 83).clipped()
        case .intervals where !intervalSegments.isEmpty:
            CardIntervalChart(segments: intervalSegments)
        case .heartRate where !hrSamples.isEmpty:
            HRSeriesPanelChart(samples: hrSamples, zones: hrZones, compact: true)
                .frame(width: 130, height: 83).clipped()
        case .cadence, .groundContact, .strideLength, .power, .verticalOscillation, .elevation
             where !workoutSeries.isEmpty:
            CardWorkoutSeriesChart(samples: workoutSeries, panel: panel)
                .frame(width: 130, height: 83).clipped()
        default:
            EmptyView()
        }
    }
}

struct CardChartLabeledPanel: View {
    let panel: CardChartPanel
    var splits: [SplitData] = []
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    var hrZones: [HRZoneData] = []
    var workoutSeries: [(offset: TimeInterval, value: Double)] = []
    var intervalSegments: [IntervalSegment] = []

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: panel.icon).font(.system(size: 7))
                Text(panel.label)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.3)
                if panel == .intervals, let s = intervalSegments.workSummaryText {
                    Text(s)
                        .font(.system(size: 8, weight: .semibold).monospacedDigit())
                }
            }
            .foregroundStyle(Color.white.opacity(0.55))
            CardChartPanelView(
                panel: panel, splits: splits, hrSamples: hrSamples,
                hrZones: hrZones, workoutSeries: workoutSeries,
                intervalSegments: intervalSegments
            )
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
    var chartHRZones: [HRZoneData] = []
    var chartWorkoutSeries: [(offset: TimeInterval, value: Double)] = []
    var chartIntervalSegments: [IntervalSegment] = []
    var weather: WeatherSnapshot? = nil
    var shoeName: String? = nil
    var photo: UIImage? = nil

    private var hasMiniMe: Bool { customMiniMeImage != nil || miniMeVariant != nil }

    private var distanceValue: String {
        let km = activity.distance / 1000
        return km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
    }

    private var startDateTimeString: String { activity.date.cardDateTimeString }

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
                CardChartLabeledPanel(
                    panel: chartPanel, splits: chartSplits, hrSamples: chartHRSamples,
                    hrZones: chartHRZones, workoutSeries: chartWorkoutSeries,
                    intervalSegments: chartIntervalSegments
                )
                .padding(.trailing, 20)
            }
            .padding(.top, 6)
            .padding(.bottom, 6)
        }
    }

    var body: some View {
        ZStack {
            if let photo = photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 300, height: 375)
                    .clipped()
                CardVisual.topScrim
                CardVisual.bottomScrim
            } else {
                LinearGradient(
                    colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

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
                        if !insightTitle.isEmpty {
                            Text(insightTitle)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.90))
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
                                .font(.system(size: 10, weight: .regular, design: .serif).italic())
                                .foregroundStyle(.white.opacity(0.78))
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

                    HStack(spacing: 0) {
                        HStack(spacing: 3) {
                            Text(activity.date.cardDateString)
                            Text(activity.date.weekdayCharKo).foregroundStyle(Theme.time)
                            Text(activity.date.cardTimeString)
                        }
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.80))
                        if let w = weather {
                            HStack(spacing: 3) {
                                Image(systemName: w.systemIcon)
                                    .font(.system(size: 8))
                                Text(w.formattedTemp)
                                    .font(.system(size: 8, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(.leading, 6)
                        }
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
        .frame(width: 300, height: 375)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Compact card charts



struct CardWorkoutSeriesChart: View {
    let samples: [(offset: TimeInterval, value: Double)]
    let panel: CardChartPanel

    private var barColor: Color {
        switch panel {
        case .cadence:  Theme.cadence
        case .power:    Theme.power
        case .elevation: Theme.elevation
        default:        Theme.runningForm
        }
    }

    private var validMin: Double {
        switch panel {
        case .cadence: return 130.0
        case .power:   return 5.0
        default:       return 0.0
        }
    }

    private var useRangeBar: Bool {
        switch panel {
        case .power, .groundContact, .strideLength, .verticalOscillation: return true
        default: return false
        }
    }

    private func yLabel(_ v: Double) -> String {
        switch panel {
        case .strideLength:        return String(format: "%.2f", v)
        case .verticalOscillation: return String(format: "%.1f", v)
        default:                   return "\(Int(v.rounded()))"
        }
    }

    private struct Bucket: Identifiable {
        let id: Int; let midMin: Double; let avg: Double; let minV: Double; let maxV: Double
    }

    private var buckets: [Bucket] {
        let filtered = samples.filter { $0.value > validMin }
        guard !filtered.isEmpty else { return [] }
        let total = max(filtered.map(\.offset).max() ?? 1, 1)
        let count = 40
        let size = total / Double(count)
        return (0..<count).compactMap { i in
            let lo = Double(i) * size, hi = lo + size
            let vals = filtered
                .filter { $0.offset >= lo && ($0.offset < hi || (i == count - 1 && $0.offset <= hi)) }
                .map(\.value)
            guard !vals.isEmpty else { return nil }
            let avg = vals.reduce(0, +) / Double(vals.count)
            return Bucket(id: i, midMin: (lo + hi) / 2 / 60,
                          avg: avg, minV: vals.min() ?? 0, maxV: vals.max() ?? 0)
        }
    }

    private var domainLo: Double {
        if useRangeBar {
            guard let lo = buckets.map(\.minV).min() else { return 0 }
            return max(lo - (lo * 0.02), 0)
        }
        guard let lo = buckets.map(\.avg).min() else { return 0 }
        return max(lo - 15, 0)
    }

    private var domainHi: Double {
        if useRangeBar {
            return (buckets.map(\.maxV).max() ?? 1) * 1.05
        }
        return (buckets.map(\.avg).max() ?? 1) + 10
    }

    var body: some View {
        let lo = domainLo, hi = domainHi
        Chart {
            ForEach(buckets) { b in
                if panel == .elevation {
                    AreaMark(
                        x: .value("분", b.midMin),
                        yStart: .value("바닥", lo),
                        yEnd: .value("고도", b.avg)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [barColor.opacity(0.55), barColor.opacity(0.10)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("분", b.midMin),
                        y: .value("고도", b.avg)
                    )
                    .foregroundStyle(barColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                } else {
                    BarMark(
                        x: .value("분", b.midMin),
                        yStart: .value("lo", useRangeBar ? b.minV : lo),
                        yEnd: .value("hi", useRangeBar ? b.maxV : b.avg),
                        width: .fixed(2)
                    )
                    .foregroundStyle(barColor.opacity(0.85))
                }
            }
        }
        .chartYScale(domain: lo...hi)
        .chartXScale(domain: 0...((buckets.last?.midMin ?? 1) + 0.5))
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.10))
                AxisValueLabel {
                    if let v = val.as(Double.self) {
                        Text(yLabel(v)).font(.system(size: 6.5)).foregroundStyle(Color.white.opacity(0.80))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { val in
                AxisValueLabel {
                    if let t = val.as(Double.self) {
                        Text(AppLanguage.shared.s("\(Int(t))분", "\(Int(t))m")).font(.system(size: 6)).foregroundStyle(Color.white.opacity(0.75))
                    }
                }
            }
        }
    }
}

// MARK: - Interval work summary helper

extension Array where Element == IntervalSegment {
    private static let standardDistances = [100, 200, 300, 400, 500, 600, 800, 1000, 1200, 1500, 1600, 2000, 3000, 4000, 5000]

    var workSummaryText: String? {
        let paces = compactMap(\.paceSecPerKm).sorted()
        let median = paces.isEmpty ? nil : paces[paces.count / 2]
        let workSegs = filter { seg in
            if let label = seg.stepLabel { return label == "운동" }
            guard let p = seg.paceSecPerKm, let m = median else { return seg.id % 2 == 1 }
            return p < m
        }
        guard !workSegs.isEmpty else { return nil }
        let distances = workSegs.compactMap(\.distanceM)
        guard distances.count == workSegs.count else { return nil }
        let snapped = distances.map { d -> Int in
            let t = 0.08
            if let s = Self.standardDistances.first(where: { abs(Double($0) - d) / Double($0) <= t }) { return s }
            return d >= 200 ? Int((d / 100).rounded()) * 100 : Int((d / 50).rounded()) * 50
        }
        let counts = Dictionary(grouping: snapped, by: { $0 }).mapValues(\.count)
        guard let (dist, cnt) = counts.max(by: { $0.value < $1.value }), cnt > 1 || counts.count == 1 else { return nil }
        let label = dist >= 1000
            ? (dist % 1000 == 0 ? "\(dist / 1000)km" : String(format: "%.1fkm", Double(dist) / 1000))
            : "\(dist)m"
        return AppLanguage.shared.s("\(label)×\(cnt)회", "\(label)×\(cnt)")
    }
}

struct CardIntervalChart: View {
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
                        .position(x: labelX[id] ?? 0, y: 5)
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
    var chartHRZones: [HRZoneData] = []
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
    private var startDateTimeString: String { activity.date.cardDateTimeString }
    private var hasMiniMe: Bool { customMiniMeImage != nil || miniMeVariant != nil }

    var body: some View {
        let max = maxOffset(for: CGSize(width: 300, height: 375))
        ZStack {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 300, height: 375)
                .offset(photoOffset)
                .brightness(CardVisual.photoBrightnessBoost)

            CardVisual.topScrim
            CardVisual.bottomScrim

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
                            .frame(width: 110, height: 110)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
                } else if chartPanel != .map {
                    HStack {
                        Spacer()
                        CardChartLabeledPanel(
                            panel: chartPanel, splits: chartSplits, hrSamples: chartHRSamples,
                            hrZones: chartHRZones, workoutSeries: chartWorkoutSeries,
                            intervalSegments: chartIntervalSegments
                        )
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
                }

                HStack(spacing: 0) {
                    HStack(spacing: 3) {
                        Text(activity.date.cardDateString)
                        Text(activity.date.weekdayCharKo).foregroundStyle(Theme.time)
                        Text(activity.date.cardTimeString)
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.80))
                    if let w = weather {
                        HStack(spacing: 3) {
                            Image(systemName: w.systemIcon)
                                .font(.system(size: 8))
                            Text(w.formattedTemp)
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.leading, 6)
                    }
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
                    .cardLargeTextShadow()

                    if !metrics.isEmpty {
                        Rectangle()
                            .fill(.white.opacity(0.25))
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
                .padding(.horizontal, 18)
                .padding(.top, 3)
                .padding(.bottom, 8)

            }
            .cardTextShadow()
            .frame(width: 300, height: 375, alignment: .topLeading)

            if max.width > 1 || max.height > 1 {
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                // Pass horizontal swipes through to the parent TabView
                                let h = abs(value.translation.width)
                                let v = abs(value.translation.height)
                                guard v > h else { return }
                                photoOffset = CGSize(
                                    width: min(max.width, Swift.max(-max.width,
                                               gestureStart.width + value.translation.width)),
                                    height: min(max.height, Swift.max(-max.height,
                                                gestureStart.height + value.translation.height))
                                )
                            }
                            .onEnded { value in
                                let h = abs(value.translation.width)
                                let v = abs(value.translation.height)
                                if v > h { gestureStart = photoOffset }
                            }
                    )
            }
        }
        .clipped()
        .frame(width: 300, height: 375)
        .clipShape(RoundedRectangle(cornerRadius: 20))
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

struct RouteLineArt: View {
    let coordinates: [CLLocationCoordinate2D]
    var lineColor: Color = Theme.violet.opacity(0.85)
    var lineWidth: CGFloat = 1.5

    var body: some View {
        Canvas { ctx, size in
            ctx.stroke(
                buildPath(in: CGRect(origin: .zero, size: size)),
                with: .color(lineColor),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
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

    var label: String {
        let L = AppLanguage.shared
        return switch self {
        case .athletic:   L.s("애슬레틱",  "Athletic")
        case .story:      L.s("스토리",    "Story")
        case .video:      L.s("영상",      "Video")
        case .routeVideo: L.s("경로 영상", "Route Video")
        }
    }
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
    var chartHRZones: [HRZoneData] = []
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
    private var startDateTimeString: String { activity.date.cardDateTimeString }

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
                            .frame(width: 110, height: 110)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                } else if chartPanel != .map {
                    HStack {
                        Spacer()
                        CardChartLabeledPanel(
                            panel: chartPanel, splits: chartSplits, hrSamples: chartHRSamples,
                            hrZones: chartHRZones, workoutSeries: chartWorkoutSeries,
                            intervalSegments: chartIntervalSegments
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                HStack(spacing: 0) {
                    HStack(spacing: 3) {
                        Text(activity.date.cardDateString)
                        Text(activity.date.weekdayCharKo).foregroundStyle(Theme.time)
                        Text(activity.date.cardTimeString)
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.80))
                    if let w = weather {
                        HStack(spacing: 3) {
                            Image(systemName: w.systemIcon)
                                .font(.system(size: 8))
                            Text(w.formattedTemp)
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.leading, 6)
                    }
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
        .frame(width: 300, height: 375)
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
    var mood: Mood? = nil
    var memoText: String? = nil
    let chartPanel: CardChartPanel
    let chartSplits: [SplitData]
    let chartHRSamples: [(offset: TimeInterval, bpm: Int)]
    var chartHRZones: [HRZoneData] = []
    let chartWorkoutSeries: [(offset: TimeInterval, value: Double)]
    let chartIntervalSegments: [IntervalSegment]
    let weather: WeatherSnapshot?

    private var startDateTimeString: String { date.cardDateTimeString }

    var body: some View {
        ZStack {
            Color.clear

            CardVisual.videoBottomScrim
            CardVisual.topScrim

            VStack(alignment: .leading, spacing: 0) {

                // ── TOP: Wordmark + Insight + MiniMe (mirrors Athletic layout) ──
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
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
                        if let m = mood {
                            HStack(spacing: 3) {
                                Image(systemName: m.sfSymbol)
                                    .font(.system(size: 10, weight: .medium))
                                Text(m.label)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(m.cardColor)
                        }
                        if let memo = memoText, !memo.isEmpty {
                            Text(memo)
                                .font(.system(size: 11, weight: .regular, design: .serif).italic())
                                .foregroundStyle(.white.opacity(0.80))
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
                                Text(chartPanel.label)
                                    .font(.system(size: 7, weight: .semibold))
                                    .tracking(0.3)
                                if chartPanel == .intervals, let s = chartIntervalSegments.workSummaryText {
                                    Text(s)
                                        .font(.system(size: 7, weight: .semibold).monospacedDigit())
                                }
                            }
                            .foregroundStyle(Color.white.opacity(0.55))
                            CardChartPanelView(
                                panel: chartPanel, splits: chartSplits, hrSamples: chartHRSamples,
                                hrZones: chartHRZones, workoutSeries: chartWorkoutSeries,
                                intervalSegments: chartIntervalSegments
                            )
                        }
                    }
                    .padding(.bottom, 3)
                }

                // ── BOTTOM: weather · date · divider · stats ──
                HStack(spacing: 0) {
                    HStack(spacing: 2) {
                        Text(date.cardDateString)
                        Text(date.weekdayCharKo).foregroundStyle(Theme.time)
                        Text(date.cardTimeString)
                    }
                    .font(.system(size: 6, weight: .medium))
                    .foregroundStyle(.white.opacity(0.80))
                    if let w = weather {
                        HStack(spacing: 2) {
                            Image(systemName: w.systemIcon)
                                .font(.system(size: 6))
                            Text(w.formattedTemp)
                                .font(.system(size: 6, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.leading, 5)
                    }
                }
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
                    .cardVideoLargeTextShadow()

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
            .cardTextShadow()
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
    @State private var selectedPhotoIndex: Int = 0
    @State private var allPickedPhotos: [UIImage] = []   // in-memory source of truth for sharing
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showStoryPhotoPicker = false
    @State private var photoOffset: CGSize = .zero
    @State private var photoOffsets: [Int: CGSize] = [:]
    @State private var template: ShareTemplate = .athletic
    @State private var enabledMetrics: Set<ShareMetric>
    @State private var showInsightOnCard = true
    @State private var showRaceOnCard = true
    @State private var showMiniMe = true
    @State private var showMoodOnCard = true
    @State private var showMemoOnCard = true
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
    // Card index (0 = template card, 1 = big number)
    @State private var cardIndex = 0
    @State private var cardPhotoIndex: [Int: Int] = [:]
    @State private var heroMetric: HeroMetric = .distance
    @State private var bigNumberShowMood: Bool = true
    @State private var bigNumberShowMemo: Bool = true
    @State private var bigNumberAccent: CardAccent = .violet

    private var isBigNumber: Bool { cardIndex == 2 }
    private var isPlaceable: Bool { cardIndex == 1 }
    private var isSky: Bool      { cardIndex == 3 }
    private var isECG: Bool      { cardIndex == 4 }

    // Binding<Int?> used by scrollPosition(id:); reads/writes cardIndex directly
    // so programmatic cardIndex changes scroll the card, and user swipes update cardIndex.
    private var scrollCardBinding: Binding<Int?> {
        Binding(get: { cardIndex }, set: { if let v = $0 { cardIndex = v } })
    }

    @State private var placeableMetricsPosition: CardPosition = .topLeading
    @State private var placeableAccent: CardAccent = .gold
    @State private var placeableSize:   PlaceableSize = .large
    // ECG card
    @State private var paceWaveform:     ECGWaveform? = nil
    @State private var hrWaveform:       ECGWaveform? = nil
    @State private var ecgShowPace:      Bool         = true
    @State private var ecgDataAvailable: Bool?        = nil
    @State private var ecgAccent:        CardAccent   = .violet
    // Sky card
    @State private var skyAccent:        CardAccent   = .none

    private var routeCoords: [CLLocationCoordinate2D] { detail?.routeCoordinates ?? [] }
    private var distanceKmString: String {
        let km = activity.distance / 1000
        return km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
    }
    private var insightTitle: String { insight?.title ?? AppLanguage.shared.s("오늘의 러닝", "Today's Run") }
    private var displayInsightTitle: String { showInsightOnCard ? insightTitle : "" }
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
        items.append(ShareMetricItem(id: .duration, value: activity.formattedDuration, label: AppLanguage.shared.s("시간", "TIME"), color: Theme.time))
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
        return d
    }

    private func photoFor(_ cIdx: Int) -> UIImage? {
        guard !storyPhotos.isEmpty else { return selectedPhoto }
        let idx = cardPhotoIndex[cIdx] ?? 0
        return idx < storyPhotos.count ? storyPhotos[idx] : storyPhotos.first
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(storyPhotos.indices, id: \.self) { i in
                    let isSelected = (cardPhotoIndex[cardIndex] ?? 0) == i
                    Button {
                        cardPhotoIndex[cardIndex] = i
                        Task { await renderCard(showSpinner: false) }
                    } label: {
                        Image(uiImage: storyPhotos[i])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Theme.violet : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 5, matching: .images, photoLibrary: .shared()) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 46, height: 46)
                        Image(systemName: storyPhotos.isEmpty ? "photo.badge.plus" : "plus")
                            .font(.system(size: storyPhotos.isEmpty ? 20 : 16))
                            .foregroundStyle(Theme.violet)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Chip toggle rows

    private var chipRow: some View {
        VStack(alignment: .leading, spacing: 3) {
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
                            Text(AppLanguage.shared.s("인사이트", "Insight"))
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
                                Text(AppLanguage.shared.s("느낌", "Mood"))
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
                                    Text(AppLanguage.shared.s("메모", "Memo"))
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
                                Text(AppLanguage.shared.s("미니미", "Mini-Me"))
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
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isOn ? Theme.violet : Color.white.opacity(0.15))
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
                                Text(panel.label)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(
                                available ? Color.white : Color.white.opacity(0.18)
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? Theme.violet
                                : Color.white.opacity(available ? 0.15 : 0.04)
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

    @ViewBuilder
    private var bigNumberCardPreview: some View {
        if template == .routeVideo, let snap = routeSnapshot {
            BigNumberRouteVideoFrameView(
                snapshot: snap,
                snapshotPoints: routeSnapshotPoints,
                routeProgress: routePreviewProgress,
                activity: activity, detail: detail, heroMetric: heroMetric,
                mood: bigNumberShowMood ? story?.mood : nil,
                memoText: bigNumberShowMemo && !(story?.memo.isEmpty ?? true) ? story?.memo : nil,
                weatherText: condition?.weather?.formattedTemp,
                weatherIcon: condition?.weather?.systemIcon,
                date: activity.date,
                shoeName: displayShoeName
            )
            .frame(width: 300, height: 375)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        } else {
            BigNumberCard(
                activity: activity, detail: detail, heroMetric: heroMetric,
                mood: bigNumberShowMood ? story?.mood : nil,
                memoText: bigNumberShowMemo && story?.memo.isEmpty == false ? story?.memo : nil,
                weatherText: condition?.weather?.formattedTemp,
                weatherIcon: condition?.weather?.systemIcon,
                date: activity.date,
                shoeName: displayShoeName,
                photo: template == .video ? videoPreviewImage : template == .story ? photoFor(2) : nil,
                chartPanel: .map,
                routeCoordinates: [],
                accent: bigNumberAccent
            )
        }
    }

    private var placeableCardPreview: some View {
        PlaceableCard(
            activity: activity,
            detail: detail,
            routeCoords: routeCoords.isEmpty ? nil : routeCoords,
            photo: template == .video ? videoPreviewImage : photoFor(1),
            date: activity.date,
            metricsPosition: placeableMetricsPosition,
            accent: placeableAccent,
            shoeName: displayShoeName,
            weather: condition?.weather,
            size: placeableSize
        )
    }

    private var skyCardPreview: some View {
        SkyCard(
            activity: activity,
            weather: condition?.weather,
            shoeName: displayShoeName,
            accent: skyAccent
        )
    }

    @ViewBuilder
    private var ecgCardPreview: some View {
        let activeWaveform = ecgShowPace ? (paceWaveform ?? hrWaveform) : (hrWaveform ?? paceWaveform)
        if let waveform = activeWaveform {
            ECGSignatureCard(
                activity: activity,
                waveform: waveform,
                weather: condition?.weather,
                shoeName: displayShoeName,
                accent: ecgAccent
            )
        } else {
            ZStack {
                Color(hex: "0D0D12")
                if ecgDataAvailable == nil {
                    ProgressView().tint(Theme.violet)
                } else {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.violet.opacity(0.4))
                }
            }
        }
    }

    private var cardSection: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    cardPreview
                        .frame(width: 300, height: 375)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.3), radius: 28, y: 10)
                        .animation(.easeInOut(duration: 0.2), value: template)
                        .frame(width: w, height: 375)
                        .id(0)
                    placeableCardPreview
                        .frame(width: 300, height: 375)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.3), radius: 28, y: 10)
                        .frame(width: w, height: 375)
                        .id(1)
                    bigNumberCardPreview
                        .frame(width: 300, height: 375)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.3), radius: 28, y: 10)
                        .frame(width: w, height: 375)
                        .id(2)
                    skyCardPreview
                        .frame(width: 300, height: 375)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Color(hex: "1B2A4A").opacity(0.5), radius: 28, y: 10)
                        .frame(width: w, height: 375)
                        .id(3)
                    if ecgDataAvailable != false {
                        ecgCardPreview
                            .frame(width: 300, height: 375)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: Theme.violet.opacity(0.2), radius: 28, y: 10)
                            .frame(width: w, height: 375)
                            .id(4)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: scrollCardBinding)
            .frame(width: w, height: 375)
        }
        .frame(height: 375)
    }

    private var cardPageDots: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(cardIndex == 0 ? Theme.violet : Color(hex: "6E6E78"))
                .frame(width: 6, height: 6)
            Circle()
                .fill(cardIndex == 1 ? Theme.violet : Color(hex: "6E6E78"))
                .frame(width: 6, height: 6)
            Circle()
                .fill(cardIndex == 2 ? Theme.violet : Color(hex: "6E6E78"))
                .frame(width: 6, height: 6)
            Circle()
                .fill(cardIndex == 3 ? Theme.violet : Color(hex: "6E6E78"))
                .frame(width: 6, height: 6)
            if ecgDataAvailable != false {
                Circle()
                    .fill(cardIndex == 4 ? Theme.violet : Color(hex: "6E6E78"))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Big Number chip row (cardIndex == 2)

    @ViewBuilder
    private func lockedChip(_ label: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon).font(.system(size: 10))
            }
            Text(label).font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color(hex: "6E6E78"))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func activeChip(_ label: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            if let icon = icon {
                Image(systemName: icon).font(.system(size: 10))
            }
            Text(label).font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.violet)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func availableChip(_ label: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon).font(.system(size: 10))
            }
            Text(label).font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.15))
        .clipShape(Capsule())
    }

    private var bigNumberChipRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Row 1: content chips — all locked
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    lockedChip(AppLanguage.shared.s("인사이트", "Insight"), icon: "sparkles")
                    if let s = story {
                        Button {
                            bigNumberShowMood.toggle()
                            Task { await renderCard(showSpinner: false) }
                        } label: {
                            if bigNumberShowMood {
                                activeChip(AppLanguage.shared.s("느낌", "Mood"), icon: s.mood.sfSymbol)
                            } else {
                                availableChip(AppLanguage.shared.s("느낌", "Mood"), icon: s.mood.sfSymbol)
                            }
                        }
                        .buttonStyle(.plain)
                        if !s.memo.isEmpty {
                            Button {
                                bigNumberShowMemo.toggle()
                                Task { await renderCard(showSpinner: false) }
                            } label: {
                                if bigNumberShowMemo {
                                    activeChip(AppLanguage.shared.s("메모", "Memo"))
                                } else {
                                    availableChip(AppLanguage.shared.s("메모", "Memo"))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if canShowMiniMe {
                        lockedChip(AppLanguage.shared.s("미니미", "Mini-Me"))
                    }
                    if let shoe = activeShoe {
                        lockedChip(shoe.displayName, icon: "shoe.fill")
                    }
                    if let race = confirmedRace {
                        lockedChip(race.raceName, icon: "flag.checkered")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
            }
            // Row 2: HeroMetric radio chips (거리/페이스/시간/심박) + non-hero locked chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HeroMetric.allCases) { m in
                        let available = m.isAvailable(activity: activity, detail: detail)
                        let isSelected = heroMetric == m
                        Button {
                            guard available else { return }
                            heroMetric = m
                        } label: {
                            HStack(spacing: 4) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text(m.shortName).font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(
                                !available ? Color(hex: "6E6E78")
                                    : Color.white
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                !available ? Color.white.opacity(0.04)
                                    : (isSelected ? Theme.violet : Color.white.opacity(0.15))
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                    }
                    // Non-hero metric chips (cadence, VO₂max, calories) — locked
                    ForEach(allMetricItems.filter {
                        $0.id != .pace && $0.id != .duration && $0.id != .heartRate
                    }) { item in
                        lockedChip(item.id.chipLabel)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
            }
            bigNumberAccentRow
        }
    }

    private var bigNumberAccentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                bigNumberAccentChip(.none,   AppLanguage.shared.s("없음",     "None"),   Color.white)
                bigNumberAccentChip(.violet, AppLanguage.shared.s("바이올렛", "Violet"), Color(hex: "9B7DFF"))
                bigNumberAccentChip(.gold,   AppLanguage.shared.s("골드",     "Gold"),   Color(hex: "FFC74D"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
        }
    }

    private func bigNumberAccentChip(_ accent: CardAccent, _ label: String, _ color: Color) -> some View {
        let isSelected = bigNumberAccent == accent
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { bigNumberAccent = accent }
            Task { await renderCard(showSpinner: false) }
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                }
                if accent != .none {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                Text(label).font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? (accent == .none ? Color(hex: "3A3A44") : color.opacity(0.25))
                    : Color.white.opacity(0.08)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Placeable card chip row (position grid + size + accent chips)

    private var placeableChipRow: some View {
        let rows: [[CardPosition]] = [
            [.topLeading, .top, .topTrailing],
            [.leading, .center, .trailing],
            [.bottomLeading, .bottom, .bottomTrailing]
        ]
        let accents: [(CardAccent, String, Color)] = [
            (.none,   AppLanguage.shared.s("없음",     "None"),   Color.white),
            (.violet, AppLanguage.shared.s("바이올렛", "Violet"), Color(hex: "9B7DFF")),
            (.gold,   AppLanguage.shared.s("골드",     "Gold"),   Color(hex: "FFC74D"))
        ]
        let sizes: [(PlaceableSize, String)] = [
            (.large, AppLanguage.shared.s("크게", "Large")),
            (.small, AppLanguage.shared.s("작게", "Small"))
        ]
        return HStack(alignment: .center, spacing: 20) {
            // 3×3 position grid
            VStack(spacing: 4) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(rows[row].indices, id: \.self) { col in
                            let pos = rows[row][col]
                            let isSelected = placeableMetricsPosition == pos
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    placeableMetricsPosition = pos
                                }
                                Task { await renderCard(showSpinner: false) }
                            } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isSelected ? Theme.violet : Color(hex: "26262E"))
                                    .frame(width: 23, height: 23)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            // Size + Accent stacked vertically
            VStack(alignment: .leading, spacing: 6) {
                // Size chips (크게 / 작게)
                HStack(spacing: 8) {
                    ForEach(sizes.indices, id: \.self) { i in
                        let (sz, label) = sizes[i]
                        let isSelected = placeableSize == sz
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { placeableSize = sz }
                            Task { await renderCard(showSpinner: false) }
                        } label: {
                            HStack(spacing: 6) {
                                if isSelected {
                                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                }
                                Text(label).font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color(hex: "3A3A44") : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Accent chips
                HStack(spacing: 8) {
                    ForEach(accents.indices, id: \.self) { i in
                        let (accent, label, color) = accents[i]
                        let isSelected = placeableAccent == accent
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { placeableAccent = accent }
                            Task { await renderCard(showSpinner: false) }
                        } label: {
                            HStack(spacing: 6) {
                                if isSelected {
                                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                }
                                if accent != .none {
                                    Circle().fill(color).frame(width: 8, height: 8)
                                }
                                Text(label).font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isSelected
                                    ? (accent == .none ? Color(hex: "3A3A44") : color.opacity(0.25))
                                    : Color.white.opacity(0.08)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }

    // Chip row for placeholder cards: all chips shown but locked/gray
    private var lockedAllChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                lockedChip(AppLanguage.shared.s("인사이트", "Insight"), icon: "sparkles")
                if canShowMiniMe {
                    lockedChip(AppLanguage.shared.s("미니미", "Mini-Me"))
                }
                ForEach(allMetricItems) { item in
                    lockedChip(item.id.chipLabel)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
        }
    }

    // Chip row for sky card: locked content chips + time-range accent selector
    private var skyChipRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    lockedChip(AppLanguage.shared.s("인사이트", "Insight"), icon: "sparkles")
                    if canShowMiniMe {
                        lockedChip(AppLanguage.shared.s("미니미", "Mini-Me"))
                    }
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
                    ForEach(allMetricItems) { item in
                        lockedChip(item.id.chipLabel)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
            }
            skyAccentRow
        }
    }

    private var skyAccentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                skyAccentChip(.none,   AppLanguage.shared.s("자동", "Auto"),   .white)
                skyAccentChip(.violet, AppLanguage.shared.s("바이올렛", "Violet"), Color(hex: "9B7DFF"))
                skyAccentChip(.gold,   AppLanguage.shared.s("골드",     "Gold"),   Color(hex: "FFC74D"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
        }
    }

    private func skyAccentChip(_ accent: CardAccent, _ label: String, _ color: Color) -> some View {
        let isSelected = skyAccent == accent
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { skyAccent = accent }
            Task { await renderCard(showSpinner: false) }
        } label: {
            HStack(spacing: 6) {
                if isSelected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                if accent != .none { Circle().fill(color).frame(width: 8, height: 8) }
                Text(label).font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? (accent == .none ? Color(hex: "3A3A44") : color.opacity(0.25))
                    : Color.white.opacity(0.08)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // Chip row for ECG card: pace / HR source radio + accent selector
    private var ecgChipRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ecgSourceChip(label: AppLanguage.shared.s("페이스", "Pace"), icon: "figure.run", isPace: true)
                    ecgSourceChip(label: AppLanguage.shared.s("심박", "HR"),  icon: "heart.fill",  isPace: false)
                        .opacity(hrWaveform == nil ? 0.4 : 1.0)
                        .disabled(hrWaveform == nil)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
            }
            ecgAccentRow
        }
    }

    private var ecgAccentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ecgAccentChip(.violet, AppLanguage.shared.s("바이올렛", "Violet"), Color(hex: "9B7DFF"))
                ecgAccentChip(.gold,   AppLanguage.shared.s("골드",     "Gold"),   Color(hex: "FFC74D"))
                ecgAccentChip(.none,   AppLanguage.shared.s("없음",     "None"),   .white)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
        }
    }

    private func ecgAccentChip(_ accent: CardAccent, _ label: String, _ color: Color) -> some View {
        let isSelected = ecgAccent == accent
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { ecgAccent = accent }
            Task { await renderCard(showSpinner: false) }
        } label: {
            HStack(spacing: 6) {
                if isSelected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                if accent != .none { Circle().fill(color).frame(width: 8, height: 8) }
                Text(label).font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? (accent == .none ? Color(hex: "3A3A44") : color.opacity(0.25))
                    : Color.white.opacity(0.08)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func ecgSourceChip(label: String, icon: String, isPace: Bool) -> some View {
        let isSelected = ecgShowPace == isPace
        let available  = isPace ? true : hrWaveform != nil
        return Button {
            guard available else { return }
            withAnimation(.easeInOut(duration: 0.15)) { ecgShowPace = isPace }
            Task { await renderCard(showSpinner: false) }
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                }
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Theme.violet : Color.white.opacity(available ? 0.08 : 0.04))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var templatePicker: some View {
        HStack(spacing: 0) {
            ForEach(ShareTemplate.allCases, id: \.self) { t in
                let available = (!isPlaceable || t == .story || t == .video)
                             && (!(isSky || isECG) || t == .athletic)
                let selected  = template == t
                Button {
                    guard available else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { template = t }
                } label: {
                    HStack(spacing: 4) {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        Text(t.label)
                            .font(.system(size: 13, weight: selected ? .semibold : (available ? .semibold : .regular)))
                    }
                    .foregroundStyle(
                        selected  ? Color.white       :
                        available ? Color.white       :
                                    Color(hex: "6E6E78")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        selected
                            ? RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.violet.opacity(0.18))
                            : nil
                    )
                }
                .disabled(!available)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var bottomControls: some View {
        if template == .video {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    PhotosPicker(selection: $videoPickerItem, matching: .videos, photoLibrary: .shared()) {
                        Label(sourceVideoURL == nil ? AppLanguage.shared.s("영상 선택", "Select Video") : AppLanguage.shared.s("영상 변경", "Change Video"),
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
                Text(AppLanguage.shared.s("최대 30초 · 영상 길이에 따라 합성 시간이 소요됩니다", "Max 30s · Processing time varies by length"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(.bottom, 8)
        } else {
            Color.clear.frame(height: 20)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 8)
                    cardSection
                    cardPageDots
                    Color.clear.frame(height: 10)
                    Group {
                        if isBigNumber { bigNumberChipRow }
                        else if isPlaceable { placeableChipRow }
                        else if isSky { skyChipRow }
                        else if isECG { ecgChipRow }
                        else { chipRow }
                    }.padding(.bottom, 3)
                    templatePicker
                    if template == .story {
                        photoStrip
                            .padding(.bottom, 8)
                    }
                    bottomControls
                    Color.clear.frame(height: 8)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            shareCTA
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .background(Theme.background.ignoresSafeArea())
        }
        .navigationTitle(AppLanguage.shared.s("공유", "Share"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStoryPhotoPicker) {
            let pickerPhotos = allPickedPhotos.isEmpty ? storyPhotos : allPickedPhotos
            StoryPhotoPickerSheet(photos: pickerPhotos, selected: selectedPhoto) { picked, idx in
                selectedPhoto = picked
                selectedPhotoIndex = idx
                showStoryPhotoPicker = false
                Task { await renderCard() }
            }
        }
        .task {
            // Restore selected photo from stored data on re-entry (e.g. after app restart).
            // Without this, selectedPhoto stays nil and the legacy all-cards branch fires.
            if !storyPhotos.isEmpty {
                for i in 0..<3 where cardPhotoIndex[i] == nil {
                    cardPhotoIndex[i] = 0
                }
            }
            // Auto-select first available panel when no route
            if routeCoords.isEmpty && cardPanel == .map {
                cardPanel = CardChartPanel.allCases.first { isChartPanelAvailable($0) } ?? .splits
            }
            await renderCard()
            await loadECGWaveforms()
        }
        .onChange(of: pickerItems) { _, newItems in
            photoOffset = .zero
            photoOffsets = [:]
            Task {
                guard !newItems.isEmpty else { return }
                var newImages: [UIImage] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        newImages.append(image)
                    }
                }
                guard !newImages.isEmpty else { return }
                let existing = allPickedPhotos.isEmpty ? storyPhotos : allPickedPhotos
                let merged = Array((existing + newImages).prefix(5))
                selectedPhoto = merged[0]
                allPickedPhotos = merged
                persistStoryPhotos(merged)
                // Point current card to the first newly added photo
                cardPhotoIndex[cardIndex] = min(existing.count, merged.count - 1)
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
            routeVideoFile = nil
            exportedVideoFile = nil
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
        .onChange(of: cardIndex) { _, newIndex in
            // Reset exported video files so each card manages its own export
            routeVideoFile = nil
            exportedVideoFile = nil
            // PlaceableCard only supports story/video — auto-switch if incompatible
            if newIndex == 1, template != .story && template != .video {
                template = .story
            }
            // Sky/ECG only support athletic — switch away from any other template
            if (newIndex == 3 || newIndex == 4), template != .athletic {
                template = .athletic
            }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: heroMetric) { _, _ in
            guard isBigNumber else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: bigNumberShowMood) { _, _ in
            guard isBigNumber else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: bigNumberShowMemo) { _, _ in
            guard isBigNumber else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: bigNumberAccent) { _, _ in
            guard isBigNumber else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: placeableMetricsPosition) { _, _ in
            guard isPlaceable else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: placeableAccent) { _, _ in
            guard isPlaceable else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: placeableSize) { _, _ in
            guard isPlaceable else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: ecgAccent) { _, _ in
            guard isECG else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: skyAccent) { _, _ in
            guard isSky else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .task(id: template) { await animateRouteVideoPreview() }
    }

    private func animateRouteVideoPreview() async {
        guard template == .routeVideo else { return }
        routePreviewProgress = 0.0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)  // 10Hz — preview only, no need for 20Hz
            routePreviewProgress += 2.0 / 60.0
            if routePreviewProgress > 1.0 { routePreviewProgress = 0.0 }
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
        CardChartPanelView(
            panel: cardPanel,
            splits: detail?.splits ?? [],
            hrSamples: shareHRSamples,
            hrZones: detail?.hrZones ?? [],
            workoutSeries: shareWorkoutSeries,
            intervalSegments: detail?.intervalSegments ?? []
        )
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
                          chartHRZones: detail?.hrZones ?? [],
                          chartWorkoutSeries: shareWorkoutSeries,
                          chartIntervalSegments: detail?.intervalSegments ?? [],
                          weather: condition?.weather,
                          shoeName: displayShoeName,
                          photo: nil)
        case .story:
            if let photo = photoFor(0) {
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
                                   chartHRZones: detail?.hrZones ?? [],
                                   chartWorkoutSeries: shareWorkoutSeries,
                                   chartIntervalSegments: detail?.intervalSegments ?? [],
                                   weather: condition?.weather,
                                   shoeName: displayShoeName,
                                   photoOffset: $photoOffset)
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
                                   chartHRZones: detail?.hrZones ?? [],
                                   chartWorkoutSeries: shareWorkoutSeries,
                                   chartIntervalSegments: detail?.intervalSegments ?? [],
                                   weather: condition?.weather,
                                   shoeName: displayShoeName)
            } else {
                ShareCardView(activity: activity, routeCoordinates: routeCoords,
                              insightTitle: displayInsightTitle, metrics: enabledMetricItems,
                              raceName: activeRaceName, miniMeVariant: activeMiniMeVariant,
                              customMiniMeImage: activeMiniMeImage,
                              story: story, showMood: showMoodOnCard, showMemo: showMemoOnCard,
                              chartPanel: cardPanel,
                              chartSplits: detail?.splits ?? [],
                              chartHRSamples: shareHRSamples,
                              chartHRZones: detail?.hrZones ?? [],
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
                    Text(AppLanguage.shared.s("야외 경로 없음", "No outdoor route"))
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
                mood: showMoodOnCard ? story?.mood : nil,
                memoText: showMemoOnCard && !(story?.memo.isEmpty ?? true) ? story?.memo : nil,
                distanceKm: distanceKmString,
                duration: activity.formattedDuration,
                date: activity.date,
                weather: condition?.weather,
                shoeName: displayShoeName,
                chartPanel: cardPanel,
                chartSplits: detail?.splits ?? [],
                chartHRSamples: shareHRSamples,
                chartHRZones: detail?.hrZones ?? [],
                chartWorkoutSeries: shareWorkoutSeries,
                chartIntervalSegments: detail?.intervalSegments ?? []
            )
        } else {
            ZStack {
                Color(hex: "0D0D12")
                VStack(spacing: 10) {
                    ProgressView().tint(Theme.violet)
                    Text(AppLanguage.shared.s("경로 준비 중…", "Loading route…"))
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
                    .frame(width: 300, height: 375)
                    .clipped()
            } else {
                Color(hex: "0D0D12")
                if !isExportingVideo {
                    VStack(spacing: 10) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.violet)
                        Text(AppLanguage.shared.s("영상을 선택해 주세요", "Select a video"))
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
                                .font(.system(size: 9, weight: .black))
                                .tracking(2)
                                .foregroundStyle(.white)
                            Text(" RUNNING")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(Theme.violet)
                        }

                        if !displayInsightTitle.isEmpty {
                            Text(displayInsightTitle)
                                .font(.system(size: 15, weight: .bold))
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
                        if showMoodOnCard, let m = story?.mood {
                            HStack(spacing: 4) {
                                Image(systemName: m.sfSymbol)
                                    .font(.system(size: 10))
                                Text(m.label)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(m.cardColor)
                        }
                        if showMemoOnCard, let memo = story?.memo, !memo.isEmpty {
                            Text(memo)
                                .font(.system(size: 11, weight: .regular, design: .serif).italic())
                                .foregroundStyle(.white.opacity(0.80))
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

                if cardPanel == .map, !routeCoords.isEmpty {
                    HStack {
                        Spacer()
                        RouteLineArt(coordinates: routeCoords)
                            .frame(width: 110, height: 110)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 3)
                } else if cardPanel != .map {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 3) {
                                Image(systemName: cardPanel.icon)
                                    .font(.system(size: 6))
                                Text(cardPanel.label)
                                    .font(.system(size: 7, weight: .semibold))
                                    .tracking(0.3)
                                if cardPanel == .intervals,
                                   let s = (detail?.intervalSegments ?? []).workSummaryText {
                                    Text(s)
                                        .font(.system(size: 7, weight: .semibold).monospacedDigit())
                                }
                            }
                            .foregroundStyle(Color.white.opacity(0.55))
                            videoChartContent
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 3)
                }

                HStack(spacing: 0) {
                    HStack(spacing: 3) {
                        Text(activity.date.cardDateString)
                        Text(activity.date.weekdayCharKo).foregroundStyle(Theme.time)
                        Text(activity.date.cardTimeString)
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.80))
                    if let w = condition?.weather {
                        HStack(spacing: 3) {
                            Image(systemName: w.systemIcon)
                                .font(.system(size: 8))
                            Text(w.formattedTemp)
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.leading, 6)
                    }
                    if let shoe = displayShoeName {
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "shoe.fill").font(.system(size: 8))
                            Text(shoe).font(.system(size: 9, weight: .medium)).lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 3)

                Rectangle()
                    .fill(Theme.violet.opacity(0.30))
                    .frame(height: 0.5)
                    .padding(.horizontal, 10)

                HStack(alignment: .center, spacing: 0) {
                    let distW: CGFloat = enabledMetricItems.count >= 5 ? 70 : 96
                    let distPt: CGFloat = enabledMetricItems.count >= 5 ? 28 : 38
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(distStr)
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

                    if !enabledMetricItems.isEmpty {
                        Rectangle()
                            .fill(.white.opacity(0.07))
                            .frame(width: 0.5, height: 36)

                        let rows = metricsRows(enabledMetricItems)
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
                .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Export progress overlay
            if isExportingVideo {
                Color.black.opacity(0.55)
                VStack(spacing: 8) {
                    ProgressView().tint(.white).scaleEffect(1.2)
                    Text(AppLanguage.shared.s("합성 중...", "Processing..."))
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
                    Text(AppLanguage.shared.s("영상 합성 중...", "Exporting video..."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else if let vf = exportedVideoFile {
                ShareLink(item: vf, preview: SharePreview(AppLanguage.shared.s("러닝 영상", "Running Video"))) {
                    Label(AppLanguage.shared.s("영상 공유하기", "Share Video"), systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else if sourceVideoURL == nil {
                Text(AppLanguage.shared.s("영상을 선택하면 자동으로 합성돼요", "Select a video to begin export"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                Text(AppLanguage.shared.s("합성 실패 — 다시 시도해 주세요", "Export failed — please try again"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
        } else if template == .routeVideo {
            if routeCoords.isEmpty {
                Text(AppLanguage.shared.s("야외 러닝 경로가 있을 때\n사용할 수 있어요", "Available when an outdoor route exists"))
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
                    Text(AppLanguage.shared.s("경로 영상 만드는 중… \(Int(routeVideoProgress * 100))%", "Creating route video… \(Int(routeVideoProgress * 100))%"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else if let vf = routeVideoFile {
                ShareLink(item: vf, preview: SharePreview(AppLanguage.shared.s("경로 영상", "Route Video"))) {
                    Label(AppLanguage.shared.s("경로 영상 공유하기", "Share Route Video"), systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Button {
                    Task { await exportRouteVideo() }
                } label: {
                    Label(AppLanguage.shared.s("경로 영상 만들기", "Create Route Video"), systemImage: "film")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(!routeSnapshotPoints.isEmpty ? Theme.violet : Color.gray.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(routeSnapshotPoints.isEmpty)
            }
        } else if isBigNumber {
            // BigNumber card: always share as image (video/routeVideo handled above via exportVideo/exportRouteVideo)
            if isRendering {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.violet)
                    Text(AppLanguage.shared.s("카드 만드는 중...", "Creating card..."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else if let img = previewImage {
                Button { showShareSheet = true } label: {
                    Label(AppLanguage.shared.s("공유하기", "Share"), systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(images: [img])
                }
            } else {
                Text(AppLanguage.shared.s("카드 생성에 실패했어요", "Card creation failed"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
        } else if isRendering {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.violet)
                Text(AppLanguage.shared.s("카드 만드는 중...", "Creating card..."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        } else if storyShareImages.count > 1 {
            VStack(spacing: 10) {
                Button { showShareSheet = true } label: {
                    Label(AppLanguage.shared.s("공유하기", "Share"), systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(images: storyShareImages)
                }
            }
        } else if let img = previewImage {
            Button { showShareSheet = true } label: {
                Label(AppLanguage.shared.s("공유하기", "Share"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(images: [img])
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
    private func makeBigNumberOverlayView() -> BigNumberVideoOverlayView {
        BigNumberVideoOverlayView(
            activity: activity, detail: detail, heroMetric: heroMetric,
            mood: bigNumberShowMood ? story?.mood : nil,
            memoText: bigNumberShowMemo && !(story?.memo.isEmpty ?? true) ? story?.memo : nil,
            weatherText: condition?.weather?.formattedTemp,
            weatherIcon: condition?.weather?.systemIcon,
            date: activity.date,
            shoeName: displayShoeName
        )
    }

    @MainActor
    private func exportVideo() async {
        guard let url = sourceVideoURL else { return }
        isExportingVideo = true
        exportedVideoFile = nil

        if isBigNumber {
            // Render transparent overlay at 216×384 @5x → 1080×1920 px (same as VideoOverlayCard)
            let overlayRenderer = ImageRenderer(content:
                makeBigNumberOverlayView().frame(width: 216, height: 384)
            )
            overlayRenderer.scale = 5.0
            guard let overlayImage = overlayRenderer.uiImage else {
                isExportingVideo = false; return
            }
            if let out = try? await VideoExportService.exportVideo(sourceURL: url, overlay: overlayImage) {
                exportedVideoFile = SharableVideoFile(url: out)
            }
            isExportingVideo = false
            return
        }

        if isPlaceable {
            // PlaceableCard overlay: transparent background, scaled to fit 216×384 video frame
            let scale: CGFloat = 216.0 / PlaceableCard.cardWidth  // 0.72
            let scaledH = PlaceableCard.cardHeight * scale          // ~270pt
            let overlayContent = PlaceableCard(
                activity: activity,
                detail: detail,
                routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                photo: nil,
                date: activity.date,
                metricsPosition: placeableMetricsPosition,
                accent: placeableAccent,
                showBackground: false,
                shoeName: displayShoeName,
                weather: condition?.weather
            )
            .frame(width: PlaceableCard.cardWidth, height: PlaceableCard.cardHeight)
            .scaleEffect(scale, anchor: .center)
            .frame(width: 216, height: scaledH)
            .frame(width: 216, height: 384)  // center vertically in video frame

            let overlayRenderer = ImageRenderer(content: overlayContent)
            overlayRenderer.scale = 5.0
            guard let overlayImage = overlayRenderer.uiImage else {
                isExportingVideo = false; return
            }
            if let out = try? await VideoExportService.exportVideo(sourceURL: url, overlay: overlayImage) {
                exportedVideoFile = SharableVideoFile(url: out)
            }
            isExportingVideo = false
            return
        }

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
            mood: showMoodOnCard ? story?.mood : nil,
            memoText: showMemoOnCard && !(story?.memo.isEmpty ?? true) ? story?.memo : nil,
            chartPanel: cardPanel,
            chartSplits: detail?.splits ?? [],
            chartHRSamples: shareHRSamples,
            chartHRZones: detail?.hrZones ?? [],
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
            let url: URL
            if isBigNumber {
                // BigNumber: single-pass render (map + route animation + BigNumber overlay)
                url = try await RouteVideoExportService.exportBigNumber(
                    snapshot: snap,
                    snapshotPoints: routeSnapshotPoints,
                    activity: activity,
                    detail: detail,
                    heroMetric: heroMetric,
                    mood: bigNumberShowMood ? story?.mood : nil,
                    memoText: bigNumberShowMemo && !(story?.memo.isEmpty ?? true) ? story?.memo : nil,
                    weatherText: condition?.weather?.formattedTemp,
                    weatherIcon: condition?.weather?.systemIcon,
                    date: activity.date,
                    shoeName: displayShoeName,
                    progressHandler: { p in routeVideoProgress = p }
                )
            } else {
                url = try await RouteVideoExportService.export(
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
                    mood: showMoodOnCard ? story?.mood : nil,
                    memoText: showMemoOnCard && !(story?.memo.isEmpty ?? true) ? story?.memo : nil,
                    weather: condition?.weather,
                    chartPanel: cardPanel,
                    chartSplits: detail?.splits ?? [],
                    chartHRSamples: shareHRSamples,
                    chartHRZones: detail?.hrZones ?? [],
                    chartWorkoutSeries: shareWorkoutSeries,
                    chartIntervalSegments: detail?.intervalSegments ?? [],
                    progressHandler: { p in routeVideoProgress = p }
                )
            }
            routeVideoFile = SharableVideoFile(url: url)
        } catch { }
        isExportingRouteVideo = false
    }

    @MainActor
    private func loadECGWaveforms() async {
        guard let mgr = manager else { ecgDataAvailable = false; return }
        async let pace = ECGWaveform.fromPace(activity: activity, using: mgr)
        async let hr   = ECGWaveform.fromHeartRate(activity: activity, using: mgr)
        let p = await pace
        let h = await hr
        paceWaveform      = p
        hrWaveform        = h
        ecgDataAvailable  = (p != nil || h != nil)
        if paceWaveform == nil, hrWaveform != nil { ecgShowPace = false }
        if ecgDataAvailable == false && cardIndex == 4 { withAnimation { cardIndex = 3 } }
        if isECG { await renderCard(showSpinner: false) }
    }

    @MainActor
    private func renderCard(showSpinner: Bool = true) async {
        // Placeable card: always render as static image
        if cardIndex == 1 {
            if showSpinner { isRendering = true }
            storyShareImages = []
            previewImage = nil
            let card = PlaceableCard(
                activity: activity,
                detail: detail,
                routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                photo: template == .video ? videoPreviewImage : photoFor(1),
                date: activity.date,
                metricsPosition: placeableMetricsPosition,
                accent: placeableAccent,
                shoeName: displayShoeName,
                weather: condition?.weather,
                size: placeableSize
            )
            let renderer = ImageRenderer(content: card.frame(width: 300, height: 375))
            renderer.scale = 3
            previewImage = renderer.uiImage
            isRendering = false
            return
        }

        // BigNumber card: render regardless of template (video/routeVideo don't block it)
        if cardIndex == 2 {
            if showSpinner { isRendering = true }
            storyShareImages = []
            previewImage = nil
            let bnPhoto: UIImage? = template == .video ? videoPreviewImage
                : template == .routeVideo ? routeSnapshot
                : template == .story ? photoFor(2)
                : nil
            let bnCard = BigNumberCard(
                activity: activity, detail: detail, heroMetric: heroMetric,
                mood: bigNumberShowMood ? story?.mood : nil,
                memoText: bigNumberShowMemo && story?.memo.isEmpty == false ? story?.memo : nil,
                weatherText: condition?.weather?.formattedTemp,
                weatherIcon: condition?.weather?.systemIcon,
                date: activity.date,
                shoeName: displayShoeName,
                photo: bnPhoto,
                chartPanel: .map,
                routeCoordinates: [],
                accent: bigNumberAccent
            )
            let renderer = ImageRenderer(content: bnCard.frame(width: 300, height: 375))
            renderer.scale = 3
            previewImage = renderer.uiImage
            isRendering = false
            return
        }

        // Sky card — "그날의 하늘"
        if cardIndex == 3 {
            if showSpinner { isRendering = true }
            storyShareImages = []
            previewImage = nil
            let card = SkyCard(
                activity: activity,
                weather: condition?.weather,
                shoeName: displayShoeName,
                accent: skyAccent
            )
            let renderer = ImageRenderer(content: card.frame(width: 300, height: 375))
            renderer.scale = 3
            previewImage = renderer.uiImage
            isRendering = false
            return
        }

        // ECG card — "심전도 시그니처"
        if cardIndex == 4 {
            let activeWaveform = ecgShowPace ? (paceWaveform ?? hrWaveform) : (hrWaveform ?? paceWaveform)
            guard let waveform = activeWaveform else { isRendering = false; return }
            if showSpinner { isRendering = true }
            storyShareImages = []
            previewImage = nil
            let card = ECGSignatureCard(
                activity: activity,
                waveform: waveform,
                weather: condition?.weather,
                shoeName: displayShoeName,
                accent: ecgAccent
            )
            let renderer = ImageRenderer(content: card.frame(width: 300, height: 375))
            renderer.scale = 3
            previewImage = renderer.uiImage
            isRendering = false
            return
        }

        guard template != .video && template != .routeVideo else { return }
        if showSpinner { isRendering = true }
        storyShareImages = []
        previewImage = nil

        // Use in-memory array if available (avoids @Query timing gap); fall back to disk on restart.
        let photos = allPickedPhotos.isEmpty ? storyPhotos : allPickedPhotos

        // Story + selected photo: render data card, rest are plain images
        if template == .story, let selPhoto = photoFor(0) {
            let renderer = ImageRenderer(content:
                PhotoShareCardView(activity: activity, photo: selPhoto,
                                   insightTitle: displayInsightTitle,
                                   metrics: enabledMetricItems, raceName: activeRaceName,
                                   story: story, showMood: showMoodOnCard, showMemo: showMemoOnCard,
                                   miniMeVariant: activeMiniMeVariant,
                                   customMiniMeImage: activeMiniMeImage,
                                   routeCoordinates: routeCoords,
                                   chartPanel: cardPanel,
                                   chartSplits: detail?.splits ?? [],
                                   chartHRSamples: shareHRSamples,
                                   chartHRZones: detail?.hrZones ?? [],
                                   chartWorkoutSeries: shareWorkoutSeries,
                                   chartIntervalSegments: detail?.intervalSegments ?? [],
                                   weather: condition?.weather,
                                   shoeName: displayShoeName,
                                   photoOffset: .constant(photoOffset))
                    .frame(width: 300, height: 375)
            )
            renderer.scale = 3
            guard let cardImg = renderer.uiImage else { isRendering = false; return }
            previewImage = cardImg
            let selIdx = cardPhotoIndex[0] ?? 0
            let plainPhotos = photos.enumerated()
                .filter { $0.offset != selIdx }
                .map { $0.element }
            if !plainPhotos.isEmpty {
                storyShareImages = [cardImg] + plainPhotos
            }
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
                          chartHRZones: detail?.hrZones ?? [],
                          chartWorkoutSeries: shareWorkoutSeries,
                          chartIntervalSegments: detail?.intervalSegments ?? [],
                          weather: condition?.weather,
                          shoeName: displayShoeName,
                          photo: nil)
                .frame(width: 300, height: 375)
        case .story:
            if let photo = photoFor(0) {
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
                                   chartHRZones: detail?.hrZones ?? [],
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
                                   chartHRZones: detail?.hrZones ?? [],
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
                              chartHRZones: detail?.hrZones ?? [],
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

    private func persistStoryPhotos(_ images: [UIImage]) {
        let capped = Array(images.prefix(5))
        guard !capped.isEmpty else { return }
        if let s = story {
            for photo in s.photos ?? [] { modelContext.delete(photo) }
            s.photos = nil
            let newPhotos = capped.enumerated().compactMap { idx, img -> StoryPhoto? in
                guard let data = img.jpegData(compressionQuality: 0.75) else { return nil }
                return StoryPhoto(data: data, index: idx)
            }
            newPhotos.forEach { modelContext.insert($0) }
            s.photos = newPhotos.isEmpty ? nil : newPhotos
            s.updatedAt = Date()
        } else {
            let s = WorkoutStory(workoutID: activity.id.uuidString)
            modelContext.insert(s)
            let newPhotos = capped.enumerated().compactMap { idx, img -> StoryPhoto? in
                guard let data = img.jpegData(compressionQuality: 0.75) else { return nil }
                return StoryPhoto(data: data, index: idx)
            }
            newPhotos.forEach { modelContext.insert($0) }
            s.photos = newPhotos
        }
        try? modelContext.save()
    }

    private func clearStoryPhoto() {
        if let s = story {
            for photo in s.photos ?? [] { modelContext.delete(photo) }
            s.photos = nil
            s.updatedAt = Date()
            try? modelContext.save()
        }
    }

}

// MARK: - Story photo picker sheet (stored photos only)

private struct StoryPhotoPickerSheet: View {
    let photos: [UIImage]
    let selected: UIImage?
    let onSelect: (UIImage, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { idx, photo in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(photo, idx) }

                            if photo == selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Theme.violet)
                                    .background(Circle().fill(.white).padding(2))
                                    .padding(6)
                            }
                        }
                    }
                }
                .padding(4)
            }
            .navigationTitle(AppLanguage.shared.s("사진 선택", "Select Photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.shared.s("취소", "Cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - UIActivityViewController wrapper

// UIImage를 직접 전달 — Instagram은 파일 URL(특히 PNG)을 거부하므로 UIImage 객체를 전달해야 함
struct ShareSheet: UIViewControllerRepresentable {
    let images: [UIImage]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: images, applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
