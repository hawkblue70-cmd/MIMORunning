import SwiftUI
import Charts
import CoreLocation
import HealthKit
import PhotosUI
import Photos
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

func moodCardColor(_ mood: Mood) -> Color {
    switch mood {
    case .fantastic: Theme.power
    case .great:     Theme.violet
    case .okay:      Theme.time
    case .tough:     Color.orange
    case .terrible:  Theme.heartRate
    }
}

// ≤3: single row. ≥4: two rows (3+3, 3+2, 2+2).
func metricsRows(_ items: [ShareMetricItem]) -> [[ShareMetricItem]] {
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
    /// Top scrim (short block, ≤2 lines): black 20% at top edge, fades to clear at 22% of height.
    static var topScrim: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.20), .clear],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.22)
        )
    }
    /// Top scrim (tall block, 3+ lines with memo): black 35%, fades to clear at 30% of height.
    static var topScrimWide: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.35), .clear],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.30)
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
    /// Video brightness: white CALayer overlay opacity in AVFoundation export path.
    static let videoBrightenLayerOpacity:   Float   = 0.10  // white CALayer opacity for AVFoundation path
    /// Video brightness for SwiftUI frames (RouteVideoService map snapshots).
    static let videoBrightnessBoost:        Double  = 0.10
    /// Saturation multiplier for video frames. 눈 튜닝: 1.05(원본) → 1.03 → 1.02 … 단계 조절.
    /// 상수 한 곳에서 관리 — RouteVideoService 미리보기·export 공유.
    static let videoSaturationBoost:        Double  = 1.05
    /// Route line art shadow: black 55%, radius 3, y 1.
    static let routeShadowColor:  Color   = .black.opacity(0.55)
    static let routeShadowRadius: CGFloat = 3
    static let routeShadowY:      CGFloat = 1

    // Instagram safe zones for all 9:16 video cards (1080×1920 px).
    // Top: Reels account name + audio row — 260px (≈13.5%).
    // Bottom: Reels like/comment/share action bar — 270px (≈14%). Reply bar is ~220px but
    //   the full action cluster on Reels extends to ~270px. Raised from 220 to fix clip.
    // Horizontal: 60px.
    static let videoSafeTop:    CGFloat = 260
    static let videoSafeBottom: CGFloat = 270
    static let videoSafeHoriz:  CGFloat = 60
    // Reference pt values at scale=1.0 (300pt card width over 1080px output).
    static var videoSafeTopRef:    CGFloat { videoSafeTop    * 300 / 1080 }  // ≈ 72.2 pt
    static var videoSafeBottomRef: CGFloat { videoSafeBottom * 300 / 1080 }  // ≈ 61.1 pt
    static var videoSafeHorizRef:  CGFloat { videoSafeHoriz  * 300 / 1080 }  // ≈ 16.7 pt
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
    var chartSize: CGSize = CGSize(width: 130, height: 83)
    var labelScale: CGFloat = 1.0

    var body: some View {
        switch panel {
        case .splits where !splits.isEmpty:
            SplitsPanelChart(splits: splits, compact: true, labelScale: labelScale)
                .frame(width: chartSize.width, height: chartSize.height).clipped()
        case .intervals where !intervalSegments.isEmpty:
            CardIntervalChart(segments: intervalSegments, labelScale: labelScale)
        case .heartRate where !hrSamples.isEmpty:
            HRSeriesPanelChart(samples: hrSamples, zones: hrZones, compact: true, labelScale: labelScale)
                .frame(width: chartSize.width, height: chartSize.height).clipped()
        case .cadence, .groundContact, .strideLength, .power, .verticalOscillation, .elevation
             where !workoutSeries.isEmpty:
            CardWorkoutSeriesChart(samples: workoutSeries, panel: panel, labelScale: labelScale)
                .frame(width: chartSize.width, height: chartSize.height).clipped()
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
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
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
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
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
    var labelScale: CGFloat = 1.0

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
                        Text(yLabel(v)).font(.system(size: 6.5 * labelScale)).foregroundStyle(Color.white.opacity(0.80))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { val in
                AxisValueLabel {
                    if let t = val.as(Double.self) {
                        Text(AppLanguage.shared.s("\(Int(t))분", "\(Int(t))m")).font(.system(size: 6 * labelScale)).foregroundStyle(Color.white.opacity(0.75))
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
    var labelScale: CGFloat = 1.0
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
        let chartW: CGFloat = 130 * labelScale
        let barW: CGFloat = labelScale * (n <= 6 ? 7 : n <= 12 ? 5 : n <= 20 ? 4 : 3)
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
                                .font(.system(size: 6.5 * labelScale))
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
            .frame(width: chartW, height: 63 * labelScale)
            .clipped()

            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(Array(labelX.keys.sorted()), id: \.self) { id in
                    Text("\(id)")
                        .font(.system(size: 6.5 * labelScale))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .fixedSize()
                        .position(x: labelX[id] ?? 0, y: 5 * labelScale)
                }
            }
            .frame(width: chartW, height: 10 * labelScale)
        }
    }
}


// PhotoShareCardView → PhotoCard.swift

// MARK: - Metric column (athletic mode)

struct CardMetric: View {
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
    // Gradient mode
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    var workoutDuration: TimeInterval = 0
    var zoneBounds: [(id: Int, minBPM: Int)] = []
    var showHRGradient: Bool = false

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            if showHRGradient && !hrSamples.isEmpty && !zoneBounds.isEmpty {
                let mapped = mappedPoints(in: rect)
                guard mapped.count > 1 else { return }
                let sorted = zoneBounds.sorted { $0.minBPM < $1.minBPM }
                // Glow pass
                for i in 0..<(mapped.count - 1) {
                    let midOff = (mapped[i].1 + mapped[i+1].1) / 2
                    let color = gradientColor(bpm: smoothedBPM(at: midOff), sorted: sorted)
                    var seg = Path(); seg.move(to: mapped[i].0); seg.addLine(to: mapped[i+1].0)
                    ctx.stroke(seg, with: .color(color.opacity(0.35)),
                               style: StrokeStyle(lineWidth: lineWidth * 2.5, lineCap: .round))
                }
                // Core pass
                for i in 0..<(mapped.count - 1) {
                    let midOff = (mapped[i].1 + mapped[i+1].1) / 2
                    let color = gradientColor(bpm: smoothedBPM(at: midOff), sorted: sorted)
                    var seg = Path(); seg.move(to: mapped[i].0); seg.addLine(to: mapped[i+1].0)
                    ctx.stroke(seg, with: .color(color),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            } else {
                ctx.stroke(buildPath(in: rect), with: .color(lineColor),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }

    // Returns (screenPoint, timeOffset) pairs for gradient mapping
    private func mappedPoints(in rect: CGRect) -> [(CGPoint, TimeInterval)] {
        guard coordinates.count > 1 else { return [] }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return [] }
        let latRange = max(maxLat - minLat, 0.0001)
        let lonRange = max(maxLon - minLon, 0.0001)
        let inset: CGFloat = 4
        let draw = rect.insetBy(dx: inset, dy: inset)
        let scale = min(draw.width / CGFloat(lonRange), draw.height / CGFloat(latRange))
        let ox = draw.minX + (draw.width  - CGFloat(lonRange) * scale) / 2
        let oy = draw.minY + (draw.height - CGFloat(latRange)  * scale) / 2
        let step = max(1, coordinates.count / 300)
        let total = coordinates.count
        var result: [(CGPoint, TimeInterval)] = []
        for i in Swift.stride(from: 0, to: total, by: step) {
            let c = coordinates[i]
            result.append((
                CGPoint(x: ox + CGFloat(c.longitude - minLon) * scale,
                        y: oy + CGFloat(maxLat - c.latitude) * scale),
                workoutDuration > 0 ? Double(i) / Double(max(total - 1, 1)) * workoutDuration : 0
            ))
        }
        return result
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
                let pt = CGPoint(x: ox + CGFloat(c.longitude - minLon) * scale,
                                 y: oy + CGFloat(maxLat - c.latitude) * scale)
                if !moved { path.move(to: pt); moved = true } else { path.addLine(to: pt) }
            }
        }
    }

    private func smoothedBPM(at offset: TimeInterval) -> Int {
        let window = hrSamples.filter { abs($0.offset - offset) <= 2.5 }
        if window.isEmpty {
            return hrSamples.min(by: { abs($0.offset - offset) < abs($1.offset - offset) })?.bpm ?? 120
        }
        return window.reduce(0) { $0 + $1.bpm } / window.count
    }

    private func gradientColor(bpm: Int, sorted: [(id: Int, minBPM: Int)]) -> Color {
        let colors = Theme.hrZoneColors
        guard sorted.count >= 2, !colors.isEmpty else { return Theme.violet }
        if bpm <= sorted[0].minBPM { return colors[0] }
        for i in 0..<(sorted.count - 1) {
            let lo = sorted[i].minBPM, hi = sorted[i+1].minBPM
            guard hi > lo, bpm < hi else { continue }
            return lerpColor(colors[min(i, colors.count-1)], colors[min(i+1, colors.count-1)],
                             Double(bpm - lo) / Double(hi - lo))
        }
        return colors[min(sorted.count-1, colors.count-1)]
    }

    private func lerpColor(_ a: Color, _ b: Color, _ t: Double) -> Color {
        var r1: CGFloat=0, g1: CGFloat=0, b1: CGFloat=0, a1: CGFloat=0
        var r2: CGFloat=0, g2: CGFloat=0, b2: CGFloat=0, a2: CGFloat=0
        UIColor(a).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(b).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let tc = CGFloat(max(0, min(1, t)))
        return Color(red: Double(r1+(r2-r1)*tc), green: Double(g1+(g2-g1)*tc), blue: Double(b1+(b2-b1)*tc))
    }
}

// MARK: - MiniMe or custom image

struct MiniMeOrCustomImage: View {
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

enum ShareTemplate: String, CaseIterable {
    case athletic    = "애슬레틱"
    case story       = "스토리"
    case video       = "영상"
    case slide       = "슬라이드"
    case routeVideo  = "경로 영상"

    var label: String {
        let L = AppLanguage.shared
        return switch self {
        case .athletic:   L.s("애슬레틱",  "Athletic")
        case .story:      L.s("스토리",    "Story")
        case .video:      L.s("영상",      "Video")
        case .slide:      L.s("슬라이드",  "Slide")
        case .routeVideo: L.s("경로 영상", "Route Video")
        }
    }
}

// MARK: - Share Card (카드별 지원 템플릿 단일 소스)

enum HorizGridMode { case text, route }

enum ShareCard: Int {
    case placeable = 0
    case oneLiner  = 1
    case athletic  = 2
    case bigNumber = 3
    case sky       = 4
    case ecg       = 5
    case ticket    = 6

    /// 이 카드에서 활성화(탭 가능·흰색)로 표시할 템플릿 집합.
    /// templatePicker 활성화, onCardIndexChanged 자동전환, renderCard 분기의 단일 소스.
    var supportedTemplates: Set<ShareTemplate> {
        switch self {
        case .placeable: return [.story, .video, .slide]
        case .oneLiner:  return [.story, .video, .slide]
        case .athletic:  return [.athletic, .story, .video, .routeVideo]
        case .bigNumber: return [.athletic, .story, .video, .routeVideo]
        case .sky:       return [.athletic]
        case .ecg:       return [.athletic]
        case .ticket:    return [.athletic]
        }
    }

    /// 카드 진입 시 현재 템플릿이 미지원이면 이 값으로 자동 전환.
    var defaultTemplate: ShareTemplate {
        switch self {
        case .placeable, .oneLiner: return .story
        default:                    return .athletic
        }
    }
}

// StoryShareCardView → StoryCard.swift

// VideoOverlayCard → VideoOverlayCard.swift

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
    @Query private var allOneLinerEntries: [OneLinerEntry]
    private var story: WorkoutStory? { allStories.first { $0.workoutID == activity.id.uuidString } }
    private var activeShoe: Shoe? {
        guard let sid = story?.shoeID else { return nil }
        return allShoes.first { $0.id.uuidString == sid }
    }
    private var storyPhotos: [UIImage] { allPickedPhotos.isEmpty ? (story?.allPhotoImages ?? []) : allPickedPhotos }
    private var storyPhoto: UIImage? { storyPhotos.first }
    private var oneLinerEntries: [OneLinerEntry] {
        OneLinerEntry.visible(from: allOneLinerEntries, workoutID: activity.id.uuidString)
    }

    private var confirmedRace: PersistedRaceMatch? {
        guard let m = raceDetector.matchFor(activityID: activity.id), m.isConfirmed else { return nil }
        return m
    }
    // Look up the BundledRace matching the confirmed match to get startTimeString
    private var confirmedBundledRace: BundledRace? {
        guard let match = confirmedRace else { return nil }
        return raceDetector.races.first {
            $0.name == match.raceName &&
            Calendar.current.isDate($0.date ?? .distantPast, inSameDayAs: match.raceDate)
        }
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
    @AppStorage("mapHRZoneMode") private var mapHRZoneMode: Bool = true

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
    @State private var template: ShareTemplate = .story
    @State private var enabledMetrics: Set<ShareMetric>
    @State private var showInsightOnCard = true
    @State private var showRaceOnCard = true
    @State private var showMiniMe = true
    @State private var showMoodOnCard = true
    @State private var showMemoOnCard = true
    @State private var showShoeOnCard = true
    @State private var carouselPage = 0
    // Placeable card ViewModel (cardIndex == 0 전용)
    @State var placeableVM = PlaceableViewModel()
    // OneLiner card ViewModel (cardIndex == 1 전용)
    @State var oneLinerVM = OneLinerViewModel()
    // Athletic card ViewModel (cardIndex == 2; athleticClipRecipes는 BigNumber와 공유)
    @State var athleticVM = AthleticViewModel()
    // BigNumber card ViewModel (cardIndex == 3)
    @State var bigNumberVM = BigNumberViewModel()
    // Sky card ViewModel (cardIndex == 4)
    @State var skyVM = SkyViewModel()
    // ECG card ViewModel (cardIndex == 5)
    @State var ecgVM = ECGViewModel()
    // Ticket card ViewModel (cardIndex == 6)
    @State var ticketVM = TicketViewModel()
    // Video
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var sourceVideoURL: URL?
    @State private var videoPreviewImage: UIImage?
    @State private var isExportingVideo = false
    @State private var exportedVideoFile: SharableVideoFile?
    @State private var videoExportError: String?
    @State private var showVideoExportError = false
    @State private var isBatchExporting = false
    @State private var showExportedVideoWarning = false
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
    @State private var chartSeriesData: [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:]
    // Card index (0 = template card, 1 = big number)
    @State private var cardIndex = 0
    @State private var cardPhotoIndex: [Int: Int] = [:]
    @State private var heroMetric: HeroMetric = .distance

    private var isPlaceable: Bool  { cardIndex == 0 }
    private var isOneLiner: Bool   { cardIndex == 1 }
    /// 현재 Placeable 카드에서 보여주는 사진 인덱스 (photoStrip 탭 기반)
    private var placeableCurrentPhotoIdx: Int { cardPhotoIndex[0] ?? 0 }
    /// 현재 사진에 연결된 Placeable 문구
    private var placeableCurrentText: String { placeableVM.placeableStoryTexts[placeableCurrentPhotoIdx] ?? "" }
    // cardIndex == 2: Athletic (기본 템플릿 카드, 별도 판별 불필요)
    private var isBigNumber: Bool  { cardIndex == 3 }

    /// Metric chips injected into MultiClipEditorView for the running day OneLiner.
    private var oneLinerAvailableMetrics: [MetricItem] {
        var m: [MetricItem] = []
        let km = activity.distance / 1000
        let distVal = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
        m.append(MetricItem(id: "distance", value: distVal, label: "km",
                            color: Theme.violet, uiColor: UIColor(red: 0x7C/255, green: 0x5C/255,
                                                                   blue: 0xFC/255, alpha: 1)))
        if let pace = activity.formattedPace {
            m.append(MetricItem(id: "pace", value: pace, label: "/km",
                                color: Color.cyan, uiColor: UIColor.systemCyan))
        }
        // T = 소요시간
        let dur = Int(activity.duration)
        let timeVal = dur >= 3600
            ? String(format: "%d:%02d:%02d", dur / 3600, (dur % 3600) / 60, dur % 60)
            : String(format: "%d:%02d", dur / 60, dur % 60)
        m.append(MetricItem(id: "time", value: timeVal, label: "",
                            color: Color.yellow, uiColor: UIColor.systemYellow))
        // B = 평균 심박수
        if let hr = activity.avgHeartRate {
            m.append(MetricItem(id: "heartrate", value: "\(hr)", label: "bpm",
                                color: Theme.heartRate, uiColor: UIColor.systemRed))
        }
        return m
    }

    /// id → VideoMetricChip 조회 (클립별 P/D/T 오버레이용)
    private var oneLinerMetricLookup: [String: VideoMetricChip] {
        Dictionary(uniqueKeysWithValues: oneLinerAvailableMetrics.map {
            ($0.id, VideoMetricChip(value: $0.value, label: $0.label, uiColor: $0.uiColor))
        })
    }

    /// VideoMetricChip array for export — only enabled IDs, in display order.
    private var oneLinerActiveMetricChips: [VideoMetricChip] {
        oneLinerAvailableMetrics
            .filter { oneLinerVM.oneLinerEnabledMetricIDs.contains($0.id) }
            .map { $0.asVideoChip }
    }

    /// 슬라이드 레시피의 per-clip 메트릭 설정을 VideoMetricChip 배열로 변환.
    /// 한 클립이라도 해당 메트릭을 켜면 슬라이드 전체에 표시.
    private func metricChipsFromSlideRecipes(_ recipes: [ClipRecipe]) -> [VideoMetricChip] {
        let hasPace     = recipes.contains { $0.metricPace }
        let hasDistance = recipes.contains { $0.metricDistance }
        let hasTime     = recipes.contains { $0.metricTime }
        let lookup      = oneLinerMetricLookup
        var chips: [VideoMetricChip] = []
        if hasDistance, let c = lookup["distance"] { chips.append(c) }
        if hasPace,     let c = lookup["pace"]     { chips.append(c) }
        if hasTime,     let c = lookup["time"]     { chips.append(c) }
        return chips
    }

    /// Story/Slide 정적 카드용: photoIndex번 사진의 ClipRecipe를 entry에서 직접 읽어 반환.
    /// v3slide\n JSON 포맷 및 레거시 플레인텍스트 포맷 모두 지원.
    private func photoRecipe(at photoIndex: Int, prefix: String = "photo:") -> ClipRecipe? {
        guard photoIndex < oneLinerVM.storyPhotoUUIDs.count else { return nil }
        let ref = "\(prefix)\(oneLinerVM.storyPhotoUUIDs[photoIndex])"
        guard let entry = oneLinerEntries.first(where: { $0.mediaRef == ref }),
              !entry.text.isEmpty else { return nil }

        var recipe = ClipRecipe(url: URL(fileURLWithPath: "/dev/null"), fullDuration: 4.0)
        if entry.text.hasPrefix("v3slide\n"),
           let data = entry.text.dropFirst("v3slide\n".count).data(using: .utf8),
           let desc = try? JSONDecoder().decode(SavedClipDescriptor.self, from: data) {
            recipe.lines      = desc.lines.map { line in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("v3slide") || t.hasPrefix("v3recipes")
                    || t.hasPrefix("v4recipes") || t.hasPrefix("v2clips")
                    || (t.count > 30 && t.hasPrefix("{") && t.hasSuffix("}")) { return "" }
                return line
            }
            recipe.fontChoice = OneLinerFont.migrate(desc.fontID)
            recipe.textColor  = desc.colorID.flatMap { OneLinerTextColor(rawValue: $0) } ?? .white
            if let aIdx = desc.anchorIdx, CardPosition.allCases.indices.contains(aIdx) {
                recipe.position = CardPosition.allCases[aIdx]
            }
            recipe.sizeLevel  = desc.sizeID.flatMap { TextSizeLevel(rawValue: $0) } ?? .large
            if let eid = desc.effectID, eid.contains("|") {
                let parts = eid.split(separator: "|", maxSplits: 3).map(String.init)
                recipe.appearanceMode = parts.count > 0 ? (AppearanceMode(rawValue: parts[0]) ?? .typing) : .typing
                recipe.decorEffect    = parts.count > 1 ? (DecorEffect(rawValue: parts[1]) ?? .none) : .none
                if parts.count > 2 {
                    recipe.hasBorder = parts[2].contains("B1")
                    recipe.plateOn   = parts[2].contains("P1")
                }
                recipe.flyDirection = parts.count > 3 ? (FlyInDirection(rawValue: parts[3]) ?? .trailing) : .trailing
            }
            recipe.plateColorPreset = desc.plateColorID.flatMap { PlateColorPreset(rawValue: $0) } ?? .blackWhite
            recipe.metricPace      = desc.metricPace
            recipe.metricDistance  = desc.metricDistance
            recipe.metricTime      = desc.metricTime
            recipe.metricHeartRate = desc.metricHeartRate
            if let idx = desc.pdtAnchorIdx, CardPosition.allCases.indices.contains(idx) {
                recipe.pdtPosition = CardPosition.allCases[idx]
            }
            // 차트 오버레이 복원: chartTypeID 우선, 없으면 레거시 fallback
            if let ct = desc.chartTypeID, let type = ChartOverlayType(rawValue: ct) {
                recipe.chartOverlayType = type
            } else if desc.showRoute {
                recipe.chartOverlayType = .route
            } else if desc.showHRChart {
                recipe.chartOverlayType = .hrChart
            }
            if let idx = desc.routeAnchorIdx, CardPosition.allCases.indices.contains(idx) {
                recipe.routePosition = CardPosition.allCases[idx]
            }
            if let ps = desc.pdtSizeID2, let size = TextSizeLevel(rawValue: ps) {
                recipe.pdtSizeLevel = size
            }
            if let de = desc.dataEffectID, let mode = AppearanceMode(rawValue: de) {
                recipe.dataAppearanceMode = mode
            }
        } else {
            recipe.lines      = entry.text.components(separatedBy: "\n")
            recipe.fontChoice = entry.font
            recipe.textColor  = entry.textColor
            recipe.position   = entry.position
        }
        return recipe
    }

    private var slideStaticRecipe: ClipRecipe? {
        photoRecipe(at: cardPhotoIndex[1] ?? 0, prefix: "slide:")
    }

    /// 스토리 카드 차트 예약 높이 — captionMode 텍스트·PDT칩이 차트와 겹치지 않도록.
    /// OneLinerCard.genericChartOverlay / HRLineChart 모두 botPad=10 기준으로 통일.
    private func storyChartBottomReserved(for recipe: ClipRecipe?) -> CGFloat {
        guard let r = recipe else { return 0 }
        let cH: CGFloat = OneLinerCard.cardHeight  // 375
        let botPad: CGFloat = 10
        if r.showHRChart && !shareHRSamples.isEmpty { return cH * 0.264 + botPad }
        if r.chartOverlayType == .route, !routeCoords.isEmpty { return cH * 0.264 + botPad }
        if r.chartOverlayType == .intervals {
            let segs = detail?.intervalSegments ?? []
            if !segs.isEmpty {
                let displayCount = segs.count > 10 ? (segs.count + 1) / 2 : segs.count
                let panH: CGFloat = 16 + 8 + CGFloat(displayCount) * 6.5 + 10
                return panH + botPad
            }
        }
        if r.chartOverlayType == .splits {
            let fc = (detail?.splits ?? []).filter { $0.distanceM >= 900 }.count
            if fc >= 2 {
                let displayCount = fc > 21 ? (fc / 2) : fc
                // titleH(16) + colHH(8) + rows*rowH(7) + vPad*2(10) — splitsChartPanel과 동일
                let panH: CGFloat = 16 + 8 + CGFloat(displayCount) * 7 + 10
                return panH + botPad
            }
        }
        let gt = r.chartOverlayType
        if ![ChartOverlayType.none, .route, .hrChart, .splits, .intervals].contains(gt),
           let s = chartSeriesData[gt], s.count >= 2 { return cH * 0.264 + botPad }
        return 0
    }

    private var isSky: Bool        { cardIndex == 4 }
    private var isECG: Bool        { cardIndex == 5 }
    private var isTicket: Bool     { cardIndex == 6 }

    // Binding<Int?> used by scrollPosition(id:); reads/writes cardIndex directly
    // so programmatic cardIndex changes scroll the card, and user swipes update cardIndex.
    private var scrollCardBinding: Binding<Int?> {
        Binding(get: { cardIndex }, set: { if let v = $0 { cardIndex = v } })
    }

    // Placeable story text overlay
    // OneLiner card
    @FocusState private var oneLinerFieldFocused: Bool
    @FocusState private var oneLinerFocusedLine: Int?
    @FocusState private var placeableStoryFocused: Bool

    private var oneLinerIsPhotoSlide: Bool { template == .slide }
    /// 슬라이드 = storyPhotos, 영상 = oneLinerVM.oneLinerClipRecipes 기반 '사진/클립 있음' 여부
    private var oneLinerHasPhotos: Bool {
        oneLinerIsPhotoSlide ? !storyPhotos.isEmpty : !oneLinerVM.oneLinerClipRecipes.isEmpty
    }
    @State private var previewPlayer: OneLinerPreviewPlayer    = OneLinerPreviewPlayer()

    private var routeCoords: [CLLocationCoordinate2D] { detail?.routeCoordinates ?? [] }

    private var showHRGradientForRoute: Bool {
        mapHRZoneMode && activity.avgHeartRate != nil && shareHRSamples.count >= 10
    }

    private var shareZoneBounds: [(id: Int, minBPM: Int)] {
        guard !shareHRSamples.isEmpty else { return [] }
        if let mgr = manager {
            let k = mgr.computeHRZonesFromSamples(shareHRSamples)
            if !k.isEmpty { return k.sorted { $0.minBPM < $1.minBPM }.map { (id: $0.id, minBPM: $0.minBPM) } }
        }
        let peak = min(220, Int(Double(shareHRSamples.map(\.bpm).max() ?? 180) / 0.90))
        return [(1,0),(2,Int(Double(peak)*0.60)),(3,Int(Double(peak)*0.70)),
                (4,Int(Double(peak)*0.80)),(5,Int(Double(peak)*0.90))]
    }

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
        // PHAsset-loaded high-res photo takes priority over SwiftData thumbnail
        if let hq = oneLinerVM.highQualityStoryPhotos[idx] { return hq }
        return idx < storyPhotos.count ? storyPhotos[idx] : storyPhotos.first
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(storyPhotos.indices, id: \.self) { i in
                    let isSelected = (cardPhotoIndex[cardIndex] ?? 0) == i
                    ZStack(alignment: .topTrailing) {
                        Button {
                            // 원라이너 스토리·슬라이드 모드: 탭 → 카드를 해당 사진으로 즉시 전환 후 ClipTrimSheet 열기
                            if isOneLiner, template == .story || template == .slide {
                                for ci in [0, 1, 2, 3] { cardPhotoIndex[ci] = i }
                                let isSlide = (template == .slide)
                                oneLinerVM.storyClipEditIsSlide = isSlide
                                oneLinerVM.storyClipEditRecipes = makeStoryClipRecipes(isSlide: isSlide)
                                oneLinerVM.storyClipEditIndex = i
                                oneLinerVM.showStoryClipEdit = true
                            } else {
                                // 통일 선택: 모든 카드(Placeable/OneLiner/Athletic/BigNumber) 동시 적용
                                if isOneLiner {
                                    saveOneLinerSettings()
                                    oneLinerFieldFocused = false
                                    for ci in [0, 1, 2, 3] { cardPhotoIndex[ci] = i }
                                    loadOneLinerSettingsFor(photoIndex: i)
                                } else {
                                    for ci in [0, 1, 2, 3] { cardPhotoIndex[ci] = i }
                                }
                                Task { await renderCard(showSpinner: false) }
                            }
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
                                .overlay {
                                    if oneLinerVM.deletedPhotoIndices.contains(i) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.55))
                                            Image(systemName: "icloud.slash")
                                                .font(.system(size: 12)).foregroundStyle(.white)
                                        }
                                    }
                                }
                                // 슬라이드 모드: 좌하단 duration 배지
                                .overlay(alignment: .bottomLeading) {
                                    if template == .slide {
                                        let sec = isPlaceable
                                            ? PhotoSlideComposition.placeableSlideDuration
                                            : PhotoSlideComposition.photoDuration
                                        Text("\(Int(sec))s")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4).padding(.vertical, 2)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                            .padding(3)
                                    }
                                }
                                // 한마디 연결 여부 표시: 문구 있는 사진은 우하단 바이올렛 도트
                                .overlay(alignment: .bottomTrailing) {
                                    if isOneLiner, template != .slide, i < oneLinerVM.storyPhotoUUIDs.count {
                                        let ref = "photo:\(oneLinerVM.storyPhotoUUIDs[i])"
                                        let hasText = oneLinerEntries.contains {
                                            $0.mediaRef == ref &&
                                            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        }
                                        if hasText {
                                            Circle()
                                                .fill(Theme.violet)
                                                .frame(width: 9, height: 9)
                                                .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1))
                                                .offset(x: 3, y: 3)
                                        }
                                    } else if isPlaceable, template == .story {
                                        if !(placeableVM.placeableStoryTexts[i] ?? "").isEmpty {
                                            Circle()
                                                .fill(Theme.violet)
                                                .frame(width: 9, height: 9)
                                                .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1))
                                                .offset(x: 3, y: 3)
                                        }
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        // X 삭제 버튼
                        Button { deleteStoryPhoto(at: i) } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "1A1A28").opacity(0.90))
                                    .frame(width: 18, height: 18)
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }
                if storyPhotos.isEmpty {
                    // 빈 상태: 사진 아이콘 + 텍스트 캡슐 버튼
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 5, matching: .images, photoLibrary: .shared()) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 17))
                            Text(AppLanguage.shared.s("사진 선택", "Select Photos"))
                                .font(.subheadline)
                        }
                        .foregroundStyle(Color.white.opacity(0.55))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                } else {
                    // 비어있지 않으면: 썸네일 바로 옆 + 버튼
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 5, matching: .images, photoLibrary: .shared()) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 46, height: 46)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.violet)
                            )
                    }
                    .buttonStyle(.plain)
                }
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
                mood: bigNumberVM.bigNumberShowMood ? story?.mood : nil,
                memoText: bigNumberVM.bigNumberShowMemo && !(story?.memo.isEmpty ?? true) ? story?.memo : nil,
                weatherText: condition?.weather?.formattedTemp,
                weatherIcon: condition?.weather?.systemIcon,
                date: activity.date,
                shoeName: displayShoeName,
                accent: bigNumberVM.bigNumberAccent,
                hrSamplesForRoute: shareHRSamples,
                routeWorkoutDuration: activity.duration,
                routeZoneBounds: shareZoneBounds,
                showHRGradient: showHRGradientForRoute
            )
            .frame(width: 300, height: 375)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        } else {
            BigNumberCard(
                activity: activity, detail: detail, heroMetric: heroMetric,
                mood: bigNumberVM.bigNumberShowMood ? story?.mood : nil,
                memoText: bigNumberVM.bigNumberShowMemo && story?.memo.isEmpty == false ? story?.memo : nil,
                weatherText: condition?.weather?.formattedTemp,
                weatherIcon: condition?.weather?.systemIcon,
                date: activity.date,
                shoeName: displayShoeName,
                photo: template == .video ? videoPreviewImage : template == .story ? photoFor(3) : nil,
                chartPanel: .map,
                routeCoordinates: routeCoords,
                accent: bigNumberVM.bigNumberAccent,
                showHRGradient: showHRGradientForRoute,
                hrSamplesForRoute: shareHRSamples,
                routeWorkoutDuration: activity.duration,
                routeZoneBounds: shareZoneBounds
            )
        }
    }

    // MARK: - Placeable 슬라이드 미리보기 (별도 프로퍼티로 분리 — ZStack 복잡도 제한 회피)

    @ViewBuilder
    private var placeableSlidePreview: some View {
        let previewW: CGFloat  = cardSectionH * 9.0 / 16.0
        let pvScale:  CGFloat  = previewW / PlaceableCard.cardWidth
        let overlayH: CGFloat  = PlaceableCard.cardHeight * pvScale
        let cardH:    CGFloat  = cardSectionH
        let topMargin: CGFloat = cardH * 0.03
        let botMargin: CGFloat = cardH * 0.03
        let firstText: String  = placeableVM.placeableStoryTexts[0] ?? ""

        if !storyPhotos.isEmpty {
            // 레터박스 배경
            Color.black

            if previewPlayer.isReady && previewPlayer.isPlaying,
               let sp = previewPlayer.player,
               let sl = previewPlayer.contentLayer {
                // 재생 중 — 슬라이드 애니메이션 플레이어
                OneLinerPreviewView(player: sp, contentLayer: sl,
                                    renderSize: previewPlayer.renderSize)
                    .frame(width: previewW, height: cardH)
                    .overlay(alignment: .bottom) {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Theme.violet)
                                .frame(width: geo.size.width * previewPlayer.progress, height: 3)
                        }
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 10)
                    }
            } else {
                // 비재생(첫 진입·일시정지) — 첫 번째 사진 정적 포스터
                Image(uiImage: storyPhotos[0])
                    .resizable()
                    .scaledToFill()
                    .frame(width: previewW, height: cardH)
                    .clipped()

                // 상·하단 비네트
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: previewW, height: 24)
                    .frame(width: previewW, height: cardH, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    .frame(width: previewW, height: 24)
                    .frame(width: previewW, height: cardH, alignment: .bottom)

                // 로고
                HStack(spacing: 0) {
                    Text("MIMO")
                        .font(.system(size: 9 * pvScale, weight: .black))
                        .tracking(2)
                        .foregroundStyle(.white)
                    Text(" RUNNING")
                        .font(.system(size: 9 * pvScale, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.violet)
                }
                .shadow(color: .black.opacity(0.50), radius: 4, x: 0, y: 2)
                .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 1)
                .padding(.top, topMargin)
                .padding(.leading, 14 * pvScale)
                .frame(width: previewW, height: cardH, alignment: .topLeading)

                // 데이터·날짜 오버레이 (로고 제외)
                PlaceableCard(
                    activity: activity,
                    detail: detail,
                    routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                    photo: nil,
                    date: activity.date,
                    metricsPosition: placeableVM.placeableMetricsPosition,
                    accent: placeableVM.placeableAccent,
                    showBackground: false,
                    showWordmark: false,
                    shoeName: displayShoeName,
                    weather: condition?.weather,
                    size: placeableVM.placeableSize,
                    layout: placeableVM.placeableLayout,
                    horizTextRow: placeableVM.placeableHorizTextRow,
                    horizRoutePos: placeableVM.placeableHorizRoutePos
                )
                .frame(width: PlaceableCard.cardWidth, height: PlaceableCard.cardHeight)
                .scaleEffect(pvScale, anchor: .center)
                .frame(width: previewW, height: overlayH)
                .padding(.bottom, botMargin)
                .frame(width: previewW, height: cardH, alignment: .bottom)

                // 첫 번째 슬라이드 문구
                if !firstText.isEmpty {
                    OneLinerCard(
                        activity: activity,
                        text: firstText,
                        position: placeableVM.placeableStoryPosition,
                        textColor: placeableVM.placeableStoryColor,
                        fontChoice: placeableVM.placeableStoryFont,
                        sizeLevel: placeableVM.placeableStorySize,
                        appearanceMode: placeableVM.placeableSlideAppearance,
                        hasBorder: placeableVM.placeableStoryHasBorder,
                        plateOn: placeableVM.placeableStoryPlateOn,
                        plateColorPreset: placeableVM.placeableStoryPlatePreset,
                        showDate: false,
                        showBackground: false,
                        showWordmark: false,
                        chartBottomReserved: placeableVM.storyBottomReserved,
                        chartTopReserved: placeableVM.storyTopReserved
                    )
                    .frame(width: PlaceableCard.cardWidth, height: PlaceableCard.cardHeight)
                    .scaleEffect(pvScale, anchor: .center)
                    .frame(width: previewW, height: cardH)
                }
            }

            // 재생/일시정지 버튼 (빌드 중이면 로딩 표시)
            if previewPlayer.isBuilding {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else {
                Button { previewPlayer.togglePlayPause() } label: {
                    Image(systemName: previewPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(previewPlayer.isPlaying ? 0 : 0.85))
                        .shadow(color: .black.opacity(0.5), radius: 8)
                }
                .buttonStyle(.plain)
            }
        } else {
            // 사진 없음 — PlaceableCard 배경 + 안내
            PlaceableCard(
                activity: activity, detail: detail,
                routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                photo: nil, date: activity.date,
                metricsPosition: placeableVM.placeableMetricsPosition, accent: placeableVM.placeableAccent,
                shoeName: displayShoeName, weather: condition?.weather,
                size: placeableVM.placeableSize, layout: placeableVM.placeableLayout,
                horizTextRow: placeableVM.placeableHorizTextRow, horizRoutePos: placeableVM.placeableHorizRoutePos
            )
            if !previewPlayer.isBuilding {
                VStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.violet.opacity(0.7))
                    Text(AppLanguage.shared.s("사진을 추가해 슬라이드 영상을 만들어보세요",
                                              "Add photos to create a slide video"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
    }

    private var placeableCardPreview: some View {
        AnyView(
            Group {
                if template == .slide {
                    ZStack { placeableSlidePreview }
                } else {
                    placeableNonSlideCardPreview
                }
            }
            .onTapGesture {
                if template == .video, previewPlayer.isReady {
                    previewPlayer.togglePlayPause()
                } else if template == .slide, previewPlayer.isReady {
                    previewPlayer.togglePlayPause()
                }
            }
        )
    }

    @ViewBuilder
    private var placeableNonSlideCardPreview: some View {
        ZStack {
            if template == .video, previewPlayer.isReady, previewPlayer.isPlaying,
               let vp = previewPlayer.player, let contentLayer = previewPlayer.contentLayer {
                // 4:5 슬롯(375pt) 내 9:16 필러박스: previewW=211pt, pvScale≈0.703
                // 좌우 44.5pt 검정 여백, 위아래 55.7pt 그라디언트 비네트
                let previewW: CGFloat   = cardSectionH * 9.0 / 16.0
                let pvScale:  CGFloat   = previewW / PlaceableCard.cardWidth
                let overlayH: CGFloat   = PlaceableCard.cardHeight * pvScale
                let cardH:    CGFloat   = cardSectionH
                let topMargin: CGFloat  = cardH * 0.03
                let botMargin: CGFloat  = cardH * 0.03

                Color.black  // 레터박스 배경 (ZStack 전체 300×375 채움)

                // 9:16 영상 + CALayer 텍스트 애니메이션 (AVSynchronizedLayer)
                // 텍스트 레이어는 buildVideoPreviewItem이 ClipRecipe 당 생성 — OneLiner 영상과 동일 경로
                OneLinerPreviewView(player: vp, contentLayer: contentLayer,
                                    renderSize: previewPlayer.renderSize)
                    .frame(width: previewW, height: cardH)
                    .overlay(alignment: .bottom) {
                        // 진행바
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Theme.violet)
                                .frame(width: geo.size.width * previewPlayer.progress, height: 3)
                        }
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 10)
                    }

                // 상·하단 엣지 비네트 (얇게)
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: previewW, height: 24)
                    .frame(width: previewW, height: cardH, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    .frame(width: previewW, height: 24)
                    .frame(width: previewW, height: cardH, alignment: .bottom)

                // 로고 — 항상 표시 (CALayer에 wordmark 없음)
                HStack(spacing: 0) {
                    Text("MIMO")
                        .font(.system(size: 9 * pvScale, weight: .black))
                        .tracking(2)
                        .foregroundStyle(.white)
                    Text(" RUNNING")
                        .font(.system(size: 9 * pvScale, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.violet)
                }
                .shadow(color: .black.opacity(0.50), radius: 4, x: 0, y: 2)
                .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 1)
                .padding(.top, topMargin)
                .padding(.leading, 14 * pvScale)
                .frame(width: previewW, height: cardH, alignment: .topLeading)

                // 데이터·날짜 (로고 제외) — SwiftUI PlaceableCard 오버레이 유지
                PlaceableCard(
                    activity: activity,
                    detail: detail,
                    routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                    photo: nil,
                    date: activity.date,
                    metricsPosition: placeableVM.placeableMetricsPosition,
                    accent: placeableVM.placeableAccent,
                    showBackground: false,
                    showWordmark: false,
                    shoeName: displayShoeName,
                    weather: condition?.weather,
                    size: placeableVM.placeableSize,
                    layout: placeableVM.placeableLayout,
                    horizTextRow: placeableVM.placeableHorizTextRow,
                    horizRoutePos: placeableVM.placeableHorizRoutePos
                )
                .frame(width: PlaceableCard.cardWidth, height: PlaceableCard.cardHeight)
                .scaleEffect(pvScale, anchor: .center)
                .frame(width: previewW, height: overlayH)
                .padding(.bottom, botMargin)
                .frame(width: previewW, height: cardH, alignment: .bottom)

                // 재생 중: CALayer 텍스트 애니메이션(fade/flyIn/typing) 표시
                // 정지 중: else 블록의 정적 OneLinerCard가 텍스트를 표시
            } else {
                PlaceableCard(
                    activity: activity,
                    detail: detail,
                    routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                    photo: template == .video ? videoPreviewImage : photoFor(0),
                    date: activity.date,
                    metricsPosition: placeableVM.placeableMetricsPosition,
                    accent: placeableVM.placeableAccent,
                    shoeName: displayShoeName,
                    weather: condition?.weather,
                    size: placeableVM.placeableSize,
                    layout: placeableVM.placeableLayout,
                    horizTextRow: placeableVM.placeableHorizTextRow,
                    horizRoutePos: placeableVM.placeableHorizRoutePos
                )
                if template == .story, !placeableCurrentText.isEmpty {
                    OneLinerCard(
                        activity: activity,
                        text: placeableCurrentText,
                        position: placeableVM.placeableStoryPosition,
                        textColor: placeableVM.placeableStoryColor,
                        fontChoice: placeableVM.placeableStoryFont,
                        sizeLevel: placeableVM.placeableStorySize,
                        appearanceMode: .typing,
                        hasBorder: placeableVM.placeableStoryHasBorder,
                        plateOn: placeableVM.placeableStoryPlateOn,
                        plateColorPreset: placeableVM.placeableStoryPlatePreset,
                        showDate: false,
                        showBackground: false,
                        showWordmark: false,
                        chartBottomReserved: placeableVM.storyBottomReserved,
                        chartTopReserved: placeableVM.storyTopReserved
                    )
                    .frame(width: 300, height: 375)
                }
                if template == .video {
                    let safeIdx_v = min(max(0, placeableVM.selectedPlaceableClipIndex), placeableVM.placeableClipRecipes.count - 1)
                    let vText = placeableVM.placeableClipRecipes.indices.contains(safeIdx_v)
                        ? (placeableVM.placeableClipRecipes[safeIdx_v].lines.first ?? "")
                        : ""
                    if !vText.isEmpty {
                        OneLinerCard(
                            activity: activity,
                            text: vText,
                            position: placeableVM.placeableStoryPosition,
                            textColor: placeableVM.placeableStoryColor,
                            fontChoice: placeableVM.placeableStoryFont,
                            sizeLevel: placeableVM.placeableStorySize,
                            appearanceMode: .typing,
                            hasBorder: placeableVM.placeableStoryHasBorder,
                            plateOn: placeableVM.placeableStoryPlateOn,
                            plateColorPreset: placeableVM.placeableStoryPlatePreset,
                            showDate: false,
                            showBackground: false,
                            showWordmark: false,
                            chartBottomReserved: placeableVM.storyBottomReserved,
                            chartTopReserved: placeableVM.storyTopReserved
                        )
                        .frame(width: PlaceableCard.cardWidth, height: PlaceableCard.cardHeight)
                    }

                    // 재생/빌드 버튼 (정지 상태일 때만 표시)
                    if previewPlayer.isBuilding {
                        ProgressView().tint(.white)
                            .padding(14)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                    } else if previewPlayer.isReady {
                        Button { previewPlayer.play() } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.5), radius: 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // Static export helper — .typing mode so text is fully visible in ImageRenderer.
    // text: 사진별 문구. nil이면 placeableCurrentText(현재 선택 사진 문구) 사용.
    @ViewBuilder
    private func placeableExportView(photo: UIImage?, text: String? = nil) -> some View {
        let overlayText = text ?? placeableCurrentText
        ZStack {
            PlaceableCard(
                activity: activity,
                detail: detail,
                routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                photo: photo,
                date: activity.date,
                metricsPosition: placeableVM.placeableMetricsPosition,
                accent: placeableVM.placeableAccent,
                shoeName: displayShoeName,
                weather: condition?.weather,
                size: placeableVM.placeableSize,
                layout: placeableVM.placeableLayout,
                horizTextRow: placeableVM.placeableHorizTextRow,
                horizRoutePos: placeableVM.placeableHorizRoutePos
            )
            if (template == .story || template == .video), !overlayText.isEmpty {
                OneLinerCard(
                    activity: activity,
                    text: overlayText,
                    position: placeableVM.placeableStoryPosition,
                    textColor: placeableVM.placeableStoryColor,
                    fontChoice: placeableVM.placeableStoryFont,
                    sizeLevel: placeableVM.placeableStorySize,
                    appearanceMode: .typing,
                    hasBorder: placeableVM.placeableStoryHasBorder,
                    plateOn: placeableVM.placeableStoryPlateOn,
                    plateColorPreset: placeableVM.placeableStoryPlatePreset,
                    showDate: false,
                    showBackground: false,
                    chartBottomReserved: placeableVM.storyBottomReserved,
                    chartTopReserved: placeableVM.storyTopReserved
                )
            }
        }
        .frame(width: 300, height: 375)
    }

    // Text overlay chips for Placeable story template.
    // [문구|데이터] 탭 기반 chip row — 플레이서블 스토리 템플릿 전용
    // → PlaceableControls.swift: PlaceableStoryModeChipRowView
    private var placeableStoryModeChipRow: some View {
        PlaceableStoryModeChipRowView(
            vm:               placeableVM,
            template:         template,
            onRender:         { await renderCard(showSpinner: false) },
            onSaveVideoClips: { savePlaceableVideoClips() },
            onLoadPreview:    { await loadPlaceablePreview() }
        )
    }
    private var placeableStoryTextField: some View {
        PlaceableStoryTextFieldView(
            vm:               placeableVM,
            photoIndex:       placeableCurrentPhotoIdx,
            storyPhotosCount: storyPhotos.count,
            focused:          $placeableStoryFocused
        )
    }

    // → PlaceableControls.swift: PlaceableTrimRowView
    @ViewBuilder private var placeableTrimRow: some View {
        PlaceableTrimRowView(
            vm:               placeableVM,
            onSaveVideoClips: { savePlaceableVideoClips() },
            onLoadPreview:    { await loadPlaceablePreview() }
        )
    }

    private var skyCardPreview: some View {
        SkyCard(
            activity: activity,
            weather: condition?.weather,
            shoeName: displayShoeName,
            accent: skyVM.skyAccent
        )
    }

    @ViewBuilder
    private var ecgCardPreview: some View {
        let activeWaveform = ecgVM.ecgShowPace ? (ecgVM.paceWaveform ?? ecgVM.hrWaveform) : (ecgVM.hrWaveform ?? ecgVM.paceWaveform)
        if let waveform = activeWaveform {
            ECGSignatureCard(
                activity: activity,
                waveform: waveform,
                weather: condition?.weather,
                shoeName: displayShoeName,
                accent: ecgVM.ecgAccent
            )
        } else {
            ZStack {
                Color(hex: "0D0D12")
                if ecgVM.ecgDataAvailable == nil {
                    ProgressView().tint(Theme.violet)
                } else {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.violet.opacity(0.4))
                }
            }
        }
    }

    private var ticketCardPreview: some View {
        TicketCard(
            activity: activity,
            routeCoordinates: routeCoords,
            splits: detail?.splits ?? [],
            raceName: confirmedRace?.raceName,
            shoeName: displayShoeName,
            departureName: ticketVM.ticketDepartureName,
            raceDistanceKm: confirmedRace?.distanceKm,
            raceStartTimeString: confirmedBundledRace?.startTimeString,
            accent: ticketVM.ticketAccent
        )
    }

    @ViewBuilder
    private var oneLinerCardPreview: some View {
        if template == .video {
            // 9:16 → 4:5 높이(375pt)에 비례 축소 (≈211×375pt)
            let pH: CGFloat = CardPreviewFrame.width * 16 / 9
            let scale: CGFloat = CardPreviewFrame.height / pH
            let previewW: CGFloat = CardPreviewFrame.height * 9.0 / 16.0
            if previewPlayer.isReady, previewPlayer.isPlaying,
               let pl = previewPlayer.player, let cl = previewPlayer.contentLayer {
                // 재생 중: 실제 영상 + CALayer 애니메이션
                OneLinerPreviewView(player: pl, contentLayer: cl, renderSize: previewPlayer.renderSize)
                    .frame(width: previewW, height: CardPreviewFrame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .bottom) {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Theme.violet)
                                .frame(width: geo.size.width * previewPlayer.progress, height: 3)
                                .animation(.linear(duration: 0.1), value: previewPlayer.progress)
                        }
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                    .overlay {
                        Button { previewPlayer.togglePlayPause() } label: {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.white.opacity(0))
                        }
                        .buttonStyle(.plain)
                    }
                    .onTapGesture { previewPlayer.togglePlayPause() }
            } else {
                // 정지·빌드 전: 정적 프리뷰 — 현재 설정(텍스트·칩·폰트·색상)을 항상 표시
                oneLinerVideoPreviewCard
                    .frame(width: CardPreviewFrame.width, height: pH)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .bottom) {
                        // 빌드 완료 상태면 진행 바 표시 (정지 위치 유지)
                        if previewPlayer.isReady {
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Theme.violet)
                                    .frame(width: geo.size.width * previewPlayer.progress, height: 3)
                            }
                            .frame(height: 3)
                            .clipShape(RoundedRectangle(cornerRadius: 1.5))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                        }
                    }
                    .overlay {
                        if previewPlayer.isBuilding {
                            ProgressView().tint(.white)
                                .padding(14)
                                .background(.black.opacity(0.45))
                                .clipShape(Circle())
                        } else if previewPlayer.isReady {
                            // 빌드 완료, 정지 중 — 재생 버튼
                            Button { previewPlayer.play() } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .shadow(color: .black.opacity(0.5), radius: 8)
                            }
                            .buttonStyle(.plain)
                        } else if !oneLinerVM.oneLinerClipRecipes.isEmpty {
                            // 미빌드 — 빌드 + 재생 버튼
                            Button { buildPreview() } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .shadow(color: .black.opacity(0.5), radius: 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scaleEffect(scale)
                    .frame(width: previewW, height: CardPreviewFrame.height)
            }
        } else if template == .slide, oneLinerHasPhotos {
            // 슬라이드: 준비된 경우 animated preview, 아닌 경우 정적 카드 + ▶ 버튼(수동)
            if previewPlayer.isReady,
               let pl = previewPlayer.player, let cl = previewPlayer.contentLayer {
                // 9:16 → 4:5 높이(375pt)에 비례 축소 (≈211×375pt)
                let previewW: CGFloat = CardPreviewFrame.height * 9.0 / 16.0
                OneLinerPreviewView(player: pl, contentLayer: cl, renderSize: previewPlayer.renderSize)
                    .frame(width: previewW, height: CardPreviewFrame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .bottom) {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Theme.violet)
                                .frame(width: geo.size.width * previewPlayer.progress, height: 3)
                                .animation(.linear(duration: 0.1), value: previewPlayer.progress)
                        }
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                    .overlay {
                        Button { previewPlayer.togglePlayPause() } label: {
                            Image(systemName: previewPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.white.opacity(previewPlayer.isPlaying ? 0 : 0.85))
                                .shadow(color: .black.opacity(0.5), radius: 8)
                        }
                        .buttonStyle(.plain)
                    }
                    .onTapGesture { previewPlayer.togglePlayPause() }
            } else {
                // 슬라이드 정적 대기 카드: 9:16(533pt) 렌더 → 4:5 높이(375pt)에 비례 축소
                let idx   = cardPhotoIndex[1]
                let photo = idx.flatMap { storyPhotos.indices.contains($0) ? storyPhotos[$0] : nil }
                let sr    = slideStaticRecipe
                let sPH: CGFloat = CardPreviewFrame.width * 16 / 9
                let sScale: CGFloat = CardPreviewFrame.height / sPH
                OneLinerCard(
                    activity: activity,
                    backgroundPhoto: photo,
                    text: sr?.lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n") ?? "",
                    position: sr?.position ?? oneLinerVM.oneLinerPosition,
                    textColor: sr?.textColor ?? oneLinerVM.oneLinerColor,
                    fontChoice: sr?.fontChoice ?? oneLinerVM.oneLinerFont,
                    sizeLevel: sr?.sizeLevel ?? .large,
                    appearanceMode: sr?.appearanceMode ?? .typing,
                    decorEffect: sr?.decorEffect ?? .none,
                    hasBorder: sr?.hasBorder ?? false,
                    plateOn: sr?.plateOn ?? false,
                    plateColorPreset: sr?.plateColorPreset ?? .blackWhite,
                    showDate: oneLinerVM.oneLinerShowDate,
                    captionMode: true,
                    videoTitle: oneLinerVM.oneLinerVideoTitle,
                    titleStyle: oneLinerVM.oneLinerTitleStyle,
                    cardHeightOverride: sPH,
                    metricPace: false,
                    metricDistance: false,
                    metricTime: false,
                    metricHeartRate: false,
                    pdtPosition: sr?.pdtPosition ?? .bottomLeading,
                    pdtSizeLevel: sr?.pdtSizeLevel ?? .medium,
                    availableMetrics: oneLinerAvailableMetrics,
                    showRoute: false,
                    routeCoords: [],
                    routePosition: sr?.routePosition ?? .bottomTrailing,
                    showHRChart: false,
                    hrSamples: [],
                    hrZones: [],
                    chartOverlayType: .none,
                    chartSeriesData: [:],
                    chartSplits: [],
                    intervalSegments: []
                )
                .frame(width: CardPreviewFrame.width, height: sPH)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    if previewPlayer.isBuilding {
                        ProgressView().tint(.white)
                            .padding(14)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                    } else {
                        Button { buildPreview() } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.55), radius: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scaleEffect(sScale)
                .frame(width: CardPreviewFrame.width * sScale, height: CardPreviewFrame.height)
            }
        } else {
            let idx   = cardPhotoIndex[1]
            let photo = idx.flatMap { storyPhotos.indices.contains($0) ? storyPhotos[$0] : nil }
                     ?? (!storyPhotos.isEmpty ? storyPhotos[0] : nil)
            // @Query 갱신 타이밍 이슈 우회: 편집 직후엔 oneLinerVM.cachedStoryRecipes 사용 (클로저로 계산)
            let pr: ClipRecipe? = {
                let i = idx ?? 0
                if !oneLinerVM.cachedStoryRecipes.isEmpty, oneLinerVM.cachedStoryRecipes.indices.contains(i) {
                    return oneLinerVM.cachedStoryRecipes[i]
                }
                return photoRecipe(at: i, prefix: "photo:")
            }()
            OneLinerCard(
                activity: activity,
                backgroundPhoto: photo,
                text: pr?.lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n") ?? oneLinerVM.oneLinerText,
                position: pr?.position ?? oneLinerVM.oneLinerPosition,
                textColor: pr?.textColor ?? oneLinerVM.oneLinerColor,
                fontChoice: pr?.fontChoice ?? oneLinerVM.oneLinerFont,
                sizeLevel: pr?.sizeLevel ?? .large,
                appearanceMode: pr?.appearanceMode ?? .typing,
                decorEffect: pr?.decorEffect ?? .none,
                hasBorder: pr?.hasBorder ?? false,
                plateOn: pr?.plateOn ?? false,
                plateColorPreset: pr?.plateColorPreset ?? .blackWhite,
                showDate: oneLinerVM.oneLinerShowDate,
                captionMode: true,
                chartBottomReserved: storyChartBottomReserved(for: pr),
                metricPace: pr?.metricPace ?? false,
                metricDistance: pr?.metricDistance ?? false,
                metricTime: pr?.metricTime ?? false,
                metricHeartRate: pr?.metricHeartRate ?? false,
                pdtPosition: pr?.pdtPosition ?? .bottomLeading,
                pdtSizeLevel: pr?.pdtSizeLevel ?? .medium,
                availableMetrics: oneLinerAvailableMetrics,
                showRoute: pr?.showRoute ?? false,
                routeCoords: routeCoords,
                routePosition: pr?.routePosition ?? .bottomTrailing,
                showHRChart: pr?.showHRChart ?? false,
                hrSamples: shareHRSamples,
                hrZones: detail?.hrZones ?? [],
                chartOverlayType: pr?.chartOverlayType ?? .none,
                chartSeriesData: chartSeriesData,
                chartSplits: detail?.splits ?? [],
                intervalSegments: detail?.intervalSegments ?? []
            )
        }
    }

    private var oneLinerVideoPreviewCard: some View {
        // 9:16 preview — exact coordinate mapping to export (1080×1920 px).
        //
        // Bug fixed: old code used OneLinerCard(300×375pt) offset by safeTopPt, which put
        // text ~24pt above the export position for .top and ~25pt above for .bottom.
        // Root cause: card height (375pt) ≠ safe-zone content height (≈400pt).
        //
        // Fix: use a safeZoneH container (pH - safeTopPt - safeBottomPt ≈ 400pt).
        // SwiftUI alignment within the container maps 1-to-1 to the export pixel math:
        //   .top    → container top  + 4pt  == export: safeTop + 4px
        //   .bottom → container bottom      == export: H - safeBottom
        //   .center → container midpoint    == export: (safeTop + H - safeBottom) / 2
        let pW:          CGFloat = 300
        let pH:          CGFloat = pW * 16 / 9           // ≈ 533.33
        let scale:       CGFloat = pW / 1080             // 300/1080 ≈ 0.2778
        let safeTopPt    = CardVisual.videoSafeTop    * scale  // ≈ 72.2pt (safe zone guide visual)
        let safeBottomPt = CardVisual.videoSafeBottom * scale  // ≈ 75pt (date padding + safe zone guide)

        // 정적 프리뷰는 per-clip recipe에서 스타일 읽기 (재생 전에도 현재 설정이 보여야 함)
        let clipRecipe   = oneLinerVM.oneLinerClipRecipes.first
        let clipFont     = clipRecipe?.fontChoice ?? oneLinerVM.oneLinerFont
        let clipColor    = clipRecipe?.textColor  ?? oneLinerVM.oneLinerColor
        let clipPos      = clipRecipe?.position   ?? oneLinerVM.oneLinerPosition
        let clipText     = clipRecipe?.lines
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n") ?? oneLinerVM.oneLinerText
        let fontSize     = 24 * clipFont.sizeScale
        let lineSpacing  = fontSize * 0.4
        let multiAlign: TextAlignment = {
            switch clipPos {
            case .topTrailing, .trailing, .bottomTrailing: return .trailing
            case .topLeading,  .leading,  .bottomLeading:  return .leading
            default: return .center
            }
        }()

        let df = DateFormatter()
        df.dateFormat = "yyyy. M. d."
        let dateStr = df.string(from: activity.date)

        #if DEBUG
        let previewY: CGFloat = clipPos.isTop
            ? (CardVisual.videoSafeTop + 4) * scale
            : clipPos.isBottom ? pH - CardVisual.videoSafeBottom * scale
            : pH / 2
        let exportY:  CGFloat = (clipPos.isTop  ? max(31.6 + 4, CardVisual.videoSafeTop + 4) :
                                  clipPos.isBottom ? 1920 - CardVisual.videoSafeBottom :
                                  (CardVisual.videoSafeTop + 1920 - CardVisual.videoSafeBottom) / 2) * scale
        Swift.print(String(format: "[VideoLayout] pos=%@ 프리뷰앵커Y=%.1fpt 합성앵커Y=%.1fpt 세이프존적용=예",
                           "\(clipPos)", previewY, exportY))
        #endif

        return ZStack(alignment: .top) {
            // ── Background / placeholder ──────────────────────────────
            if let preview = videoPreviewImage {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: pW, height: pH)
                    .clipped()
            } else {
                Color(hex: "0D0D12")
                    .frame(width: pW, height: pH)
                if !isExportingVideo {
                    VStack(spacing: 10) {
                        Image(systemName: oneLinerVM.oneLinerPhAssetDeleted ? "video.slash" : "video.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(oneLinerVM.oneLinerPhAssetDeleted ? .orange : Theme.violet)
                        Text(oneLinerVM.oneLinerPhAssetDeleted
                             ? AppLanguage.shared.s("원본이 삭제되었어요", "Original deleted")
                             : AppLanguage.shared.s("영상을 선택해 주세요", "Select a video"))
                            .font(.caption)
                            .foregroundStyle(oneLinerVM.oneLinerPhAssetDeleted ? .orange : .secondary)
                        if oneLinerVM.oneLinerPhAssetDeleted {
                            Text(AppLanguage.shared.s("한마디는 유지됩니다", "Your text is preserved"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: pW, height: pH)
                }
            }

            // ── Wordmark: y=12pt matches export wMarkTopPad (12 * vScale * scale = 12pt)
            // Placed above the safe zone (in danger zone) — same as the actual export.
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
            .cardTextShadow()
            .frame(width: pW, alignment: .leading)
            .padding(.leading, 14)
            .offset(y: 12)
            .allowsHitTesting(false)

            // ── Text: safe-zone anchored — mirrors export pixel coordinates ─────
            // oneLinerVideoTitle이 있으면 그쪽이 제목 역할 → clipText 숨김 (중복 렌더 방지)
            if !clipText.isEmpty, oneLinerVM.oneLinerVideoTitle.isEmpty {
                Text(clipText)
                    .font(.custom(clipFont.fontName, size: fontSize))
                    .lineSpacing(lineSpacing)
                    .multilineTextAlignment(multiAlign)
                    .foregroundStyle(clipColor.color)
                    .shadow(color: .black.opacity(0.55), radius: 5, x: 1, y: 2)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                    .padding(.top, clipPos.isTop ? (CardVisual.videoSafeTop + 4) * scale : 0)
                    .padding(.bottom, clipPos.isBottom ? CardVisual.videoSafeBottom * scale : 0)
                    .frame(width: pW, height: pH, alignment: clipPos.alignment)
                    .allowsHitTesting(false)
            }

            // ── Full-video title: mirrors export safe-zone positioning ─────────
            if !oneLinerVM.oneLinerVideoTitle.isEmpty {
                let tFontSize = 20 * oneLinerVM.oneLinerTitleStyle.fontChoice.sizeScale * oneLinerVM.oneLinerTitleStyle.sizeLevel.scale
                Text(oneLinerVM.oneLinerVideoTitle)
                    .font(oneLinerVM.oneLinerTitleStyle.fontChoice.swiftUIFont(size: tFontSize))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(oneLinerVM.oneLinerTitleStyle.textColor.color)
                    .shadow(color: .black.opacity(0.55), radius: 5, x: 1, y: 2)
                    .shadow(color: .black.opacity(oneLinerVM.oneLinerTitleStyle.outline ? 0.55 : 0), radius: 0.5, x:  1.5, y: 0)
                    .shadow(color: .black.opacity(oneLinerVM.oneLinerTitleStyle.outline ? 0.55 : 0), radius: 0.5, x: -1.5, y: 0)
                    .shadow(color: .black.opacity(oneLinerVM.oneLinerTitleStyle.outline ? 0.55 : 0), radius: 0.5, x: 0, y:  1.5)
                    .shadow(color: .black.opacity(oneLinerVM.oneLinerTitleStyle.outline ? 0.55 : 0), radius: 0.5, x: 0, y: -1.5)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.top, oneLinerVM.oneLinerTitleStyle.position.isTop ? CardVisual.videoSafeTop * 0.6 * scale : 0)
                    .padding(.bottom, oneLinerVM.oneLinerTitleStyle.position.isBottom ? CardVisual.videoSafeBottom * scale : 0)
                    .frame(width: pW, height: pH, alignment: oneLinerVM.oneLinerTitleStyle.position.alignment)
                    .allowsHitTesting(false)
            }

            // ── Date: safe-zone bottom - 14pt ────────────────────────────────
            if oneLinerVM.oneLinerShowDate {
                Text(dateStr)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .frame(width: pW - 28, alignment: .trailing)
                    .padding(.bottom, safeBottomPt + 14)
                    .frame(width: pW, height: pH, alignment: .bottom)
                    .allowsHitTesting(false)
            }

            // ── PDT chips (첫 클립 recipe) ────────────────────────────────────
            if let recipe = oneLinerVM.oneLinerClipRecipes.first,
               recipe.metricPace || recipe.metricDistance || recipe.metricTime || recipe.metricHeartRate {
                let lookup = Dictionary(uniqueKeysWithValues: oneLinerAvailableMetrics.map { ($0.id, $0) })
                let items: [MetricItem] = [
                    recipe.metricDistance  ? lookup["distance"]  : nil,
                    recipe.metricPace      ? lookup["pace"]       : nil,
                    recipe.metricTime      ? lookup["time"]       : nil,
                    recipe.metricHeartRate ? lookup["heartrate"]  : nil,
                ].compactMap { $0 }
                if !items.isEmpty {
                    let sz = recipe.pdtSizeLevel.scale
                    let topPad: CGFloat = {
                        guard recipe.pdtPosition.isTop else { return 0 }
                        let base = (CardVisual.videoSafeTop + 4) * scale
                        // 제목이 상단에 있으면 제목 하단 아래로 칩을 밀어냄 (export 동일 기준)
                        guard !oneLinerVM.oneLinerVideoTitle.isEmpty, oneLinerVM.oneLinerTitleStyle.position.isTop else { return base }
                        let tFontSize = 20 * oneLinerVM.oneLinerTitleStyle.fontChoice.sizeScale * oneLinerVM.oneLinerTitleStyle.sizeLevel.scale
                        let titleH = tFontSize * 1.4 * 2 + 8  // 최대 2줄 여유
                        let titleEndY = CardVisual.videoSafeTop * 0.6 * scale + titleH
                        return max(base, titleEndY + 4)
                    }()
                    let botPad: CGFloat = recipe.pdtPosition.isBottom ? CardVisual.videoSafeBottom * scale : 0
                    HStack(spacing: 6 * sz) {
                        ForEach(items) { m in
                            HStack(spacing: 3 * sz) {
                                Text(m.value)
                                    .font(.system(size: 11 * sz, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.white)
                                if !m.label.isEmpty {
                                    Text(m.label)
                                        .font(.system(size: 9 * sz))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                            .padding(.horizontal, 8 * sz)
                            .padding(.vertical, 4 * sz)
                            .background(RoundedRectangle(cornerRadius: 8 * sz).fill(m.color.opacity(0.30)))
                            .overlay(RoundedRectangle(cornerRadius: 8 * sz)
                                .strokeBorder(m.color.opacity(0.55), lineWidth: 0.5))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, topPad)
                    .padding(.bottom, botPad)
                    .frame(width: pW, height: pH, alignment: recipe.pdtPosition.alignment)
                    .allowsHitTesting(false)
                }
            }

            // ── Route minimap (첫 클립 recipe) ───────────────────────────────
            if let recipe = oneLinerVM.oneLinerClipRecipes.first, recipe.showRoute,
               recipe.chartOverlayType != .route, !routeCoords.isEmpty {
                let topPad: CGFloat = recipe.routePosition.isTop    ? (CardVisual.videoSafeTop + 4) * scale : 0
                let botPad: CGFloat = recipe.routePosition.isBottom ? CardVisual.videoSafeBottom * scale : 0
                RouteMiniMap(coords: routeCoords)
                    .frame(width: 54, height: 54)
                    .padding(.horizontal, 18)
                    .padding(.top, topPad)
                    .padding(.bottom, botPad)
                    .frame(width: pW, height: pH, alignment: recipe.routePosition.alignment)
                    .allowsHitTesting(false)
            }

            // ── Safe zone guides ──────────────────────────────────────
            // 오늘의 한마디(카드2)는 쉬는날과 동일하게 "인스타 UI 영역" 가이드 미표시
            if !isOneLiner {
            VStack(spacing: 0) {
                // Top danger zone (Instagram UI — profile, icons)
                ZStack(alignment: .bottomLeading) {
                    Color.black.opacity(0.30)
                    Text(AppLanguage.shared.s("인스타 UI 영역", "Instagram UI"))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.leading, 8)
                        .padding(.bottom, 4)
                    Canvas { ctx, size in
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: size.height - 0.5))
                        path.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                        ctx.stroke(path, with: .color(.white.opacity(0.45)),
                                   style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .frame(width: pW, height: safeTopPt)

                Spacer()

                // Bottom danger zone (reply bar / caption)
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.30)
                    Text(AppLanguage.shared.s("인스타 UI 영역", "Instagram UI"))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.leading, 8)
                        .padding(.top, 4)
                    Canvas { ctx, size in
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: 0.5))
                        path.addLine(to: CGPoint(x: size.width, y: 0.5))
                        ctx.stroke(path, with: .color(.white.opacity(0.45)),
                                   style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .frame(width: pW, height: safeBottomPt)
            }
            .frame(width: pW, height: pH)
            .allowsHitTesting(false)
            }

            // ── Export progress ───────────────────────────────────────
            if isExportingVideo {
                Color.black.opacity(0.55)
                    .frame(width: pW, height: pH)
                VStack(spacing: 8) {
                    ProgressView().tint(.white).scaleEffect(1.2)
                    Text(AppLanguage.shared.s("합성 중...", "Processing..."))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                }
                .frame(width: pW, height: pH)
            }
        }
        .frame(width: pW, height: pH)
        .clipped()
    }

    private var cardSection: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // 0: Placeable — 영상 템플릿은 9:16 넓게(480pt), 그 외 375pt
                    placeableCardPreview
                        .frame(width: 300, height: cardSectionH)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.3), radius: 28, y: 10)
                        .frame(width: w, height: cardSectionH)
                        .id(0)
                    // 1: OneLiner (한마디) — 영상 선택 시 9:16 확장
                    AnyView(oneLinerCardPreview)
                        .frame(width: 300, height: oneLinerCardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.1), radius: 28, y: 10)
                        .frame(width: w, height: oneLinerCardHeight)
                        .id(1)
                    // 2: Athletic (기본 템플릿 카드)
                    AnyView(cardPreview)
                        .frame(width: 300, height: 375)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.3), radius: 28, y: 10)
                        .animation(.easeInOut(duration: 0.2), value: template)
                        .frame(width: w, height: 375)
                        .id(2)
                    // 3: BigNumber
                    AnyView(bigNumberCardPreview)
                        .frame(width: 300, height: 375)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.3), radius: 28, y: 10)
                        .frame(width: w, height: 375)
                        .id(3)
                    // 4: Sky
                    AnyView(skyCardPreview)
                        .frame(width: 300, height: 375)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Color(hex: "1B2A4A").opacity(0.5), radius: 28, y: 10)
                        .frame(width: w, height: 375)
                        .id(4)
                    // 5: ECG (데이터 없으면 숨김)
                    if ecgVM.ecgDataAvailable != false {
                        AnyView(ecgCardPreview)
                            .frame(width: 300, height: 375)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: Theme.violet.opacity(0.2), radius: 28, y: 10)
                            .frame(width: w, height: 375)
                            .id(5)
                    }
                    // 6: Ticket
                    AnyView(ticketCardPreview)
                        .frame(width: 300, height: 375)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.15), radius: 28, y: 10)
                        .frame(width: w, height: 375)
                        .id(6)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: scrollCardBinding)
            .frame(width: w, height: cardSectionH)
        }
        .frame(height: cardSectionH)
        .animation(.easeInOut(duration: 0.3), value: cardSectionH)
    }

    private var cardPageDots: some View {
        // 탭 가능: 카드2(인라인 편집)에서 캐러셀이 숨겨질 때도 다른 카드로 이동 가능하게.
        HStack(spacing: 7) {
            pageDot(0) // Placeable
            pageDot(1) // OneLiner
            pageDot(2) // Athletic
            pageDot(3) // BigNumber
            pageDot(4) // Sky
            if ecgVM.ecgDataAvailable != false { pageDot(5) } // ECG
            pageDot(6) // Ticket
        }
        .padding(.top, 6)
    }

    private func pageDot(_ i: Int) -> some View {
        let names    = ["Placeable", "One Liner", "Athletic", "Big Number", "Sky", "ECG", "Ticket"]
        let isActive = cardIndex == i
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { cardIndex = i }
        } label: {
            if isActive {
                Text(i < names.count ? names[i] : "")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.violet)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.violet.opacity(0.15)))
            } else {
                Circle()
                    .fill(Color(hex: "6E6E78"))
                    .frame(width: 6, height: 6)
                    .frame(width: 11, height: 18)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    // MARK: - Big Number chip row (cardIndex == 3)

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
                            bigNumberVM.bigNumberShowMood.toggle()
                            Task { await renderCard(showSpinner: false) }
                        } label: {
                            if bigNumberVM.bigNumberShowMood {
                                activeChip(AppLanguage.shared.s("느낌", "Mood"), icon: s.mood.sfSymbol)
                            } else {
                                availableChip(AppLanguage.shared.s("느낌", "Mood"), icon: s.mood.sfSymbol)
                            }
                        }
                        .buttonStyle(.plain)
                        if !s.memo.isEmpty {
                            Button {
                                bigNumberVM.bigNumberShowMemo.toggle()
                                Task { await renderCard(showSpinner: false) }
                            } label: {
                                if bigNumberVM.bigNumberShowMemo {
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

    // → BigNumberControls.swift: BigNumberAccentRowView
    private var bigNumberAccentRow: some View {
        BigNumberAccentRowView(vm: bigNumberVM, onRender: { await renderCard(showSpinner: false) })
    }

    // MARK: - Placeable card horizontal mode helpers

    // MARK: - Placeable card chip row (position grid + size + accent chips)

    // → PlaceableControls.swift: PlaceableChipRowView
    private var placeableChipRow: some View {
        PlaceableChipRowView(
            vm:       placeableVM,
            template: template,
            onRender: { await renderCard(showSpinner: false) }
        )
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

    // → SkyControls.swift: SkyAccentRowView
    private var skyAccentRow: some View {
        SkyAccentRowView(vm: skyVM, onRender: { await renderCard(showSpinner: false) })
    }

    // Chip row selector — extracted from body to keep the body's type-check surface small.
    @ViewBuilder private var activeChipRow: some View {
        if isBigNumber                          { bigNumberChipRow }
        else if isPlaceable { placeableStoryModeChipRow }
        else if isSky                           { skyChipRow }
        else if isECG                           { ecgChipRow }
        else if isTicket                        { ticketChipRowContent }
        else if isOneLiner                      { oneLinerChipRow }
        else                                    { chipRow }
    }

    // Resolved chip row for ticket card slot — extracted so the Group if-else chain stays shallow.
    @ViewBuilder private var ticketChipRowContent: some View {
        if confirmedRace == nil { ticketAccentRow }
        // Race ticket → EmptyView (gold fixed, no accent selection needed)
    }

    // → TicketControls.swift: TicketAccentRowView
    // Race ticket hides this row entirely (confirmedRace != nil) — gold is always fixed.
    private var ticketAccentRow: some View {
        TicketAccentRowView(vm: ticketVM, onRender: { await renderCard(showSpinner: false) })
    }

    // Height of the card section: 9:16 (≈533pt) for slide/video templates, 375pt otherwise.
    private var oneLinerCardHeight: CGFloat {
        CardPreviewFrame.height  // 모든 템플릿 375pt — 영상/슬라이드 9:16은 비례 축소(≈211×375)
    }

    /// 카드 섹션 전체 높이 — 모든 카드 375pt (9:16 영상은 내부 필러박스)
    private var cardSectionH: CGFloat {
        oneLinerCardHeight
    }

    // 문구가 연결된 사진(story template) 개수 — 2장 이상이면 일괄 저장 모드.
    private var linkedOneLinerPhotoCount: Int {
        guard isOneLiner, template == .story else { return 0 }
        return oneLinerVM.storyPhotoUUIDs.indices.filter { i in
            let ref = "photo:\(oneLinerVM.storyPhotoUUIDs[i])"
            return oneLinerEntries.contains {
                $0.mediaRef == ref &&
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }.count
    }

    // MARK: - OneLiner chip row (cardIndex == 1)

    // Layout (top→bottom):
    //   [9-grid | font 3-chips (VStack) / color 3-chips]
    //   [재사용 칩 — 이 미디어에 entry가 없고 다른 entry가 있을 때만 표시]
    //   [text input field full-width]
    // 다른 카드와 동일하게 인라인 편집 — 쉬는날과 같은 MultiClipEditorView(스토리/영상/슬라이드 공용)
    private var oneLinerChipRow: some View {
        MultiClipEditorView(
            recipes: Bindable(oneLinerVM).oneLinerClipRecipes,
            isPhotoSlideMode: Binding<Bool>(get: { template == .slide || template == .story }, set: { _ in }),
            muteAudio: Bindable(oneLinerVM).oneLinerMuteAudio,
            selectedClipIndex: Bindable(oneLinerVM).currentOneLinerClipIndex,
            savedClipLines: [],
            availableMetrics: oneLinerAvailableMetrics,
            enabledMetricIDs: Bindable(oneLinerVM).oneLinerEnabledMetricIDs,
            routeCoords: routeCoords,
            hrSamples: shareHRSamples,
            splits: detail?.splits ?? [],
            chartSeriesData: chartSeriesData,
            hrZones: detail?.hrZones ?? [],
            intervalSegments: detail?.intervalSegments ?? [],
            onSave: {
                if previewPlayer.isReady || previewPlayer.isBuilding {
                    previewPlayer.pause()
                    previewPlayer.invalidate()
                }
                // 영상 템플릿: 첫 클립 썸네일 정적 배경 세팅 + 자동 라이브 프리뷰 빌드
                if template == .video {
                    if let thumb = oneLinerVM.oneLinerClipRecipes.first?.thumbnail {
                        videoPreviewImage = thumb
                    }
                    if !oneLinerVM.oneLinerClipRecipes.isEmpty {
                        buildPreview()
                    }
                }
                // 설정 변경 → 이전 export 캐시 무효화 (onSave는 모든 클립 편집 완료 시 호출)
                exportedVideoFile = nil
                // 영상 모드에서만 저장 — 스토리/슬라이드 전환 시 빈 배열로 덮어쓰기 방지
                if template == .video { saveOneLinerClipRecipes() }
            },
            isStoryMode: template == .story,
            showPickerButton: template != .story && template != .slide,
            showTitleEvenWhenEmpty: template == .slide && !storyPhotos.isEmpty,
            videoTitle: Bindable(oneLinerVM).oneLinerVideoTitle,
            titleStyle: Bindable(oneLinerVM).oneLinerTitleStyle
        )
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }

    // 2번째 카드 = 쉬는날 편집화면을 인라인으로 이식(embedded). 미리보기·편집폼·저장 모두 쉬는날과 동일.
    // 러닝 데이터(P/D/T/M/H)는 클립 편집 그리드 다음에 노출.
    private var oneLinerRestDayEditor: some View {
        RestDayOneLinerSheet(
            date: activity.date,
            activity: activity,
            availableMetrics: oneLinerAvailableMetrics,
            routeCoords: routeCoords,
            hrSamples: shareHRSamples,
            splits: detail?.splits ?? [],
            chartSeriesData: chartSeriesData,
            hrZones: detail?.hrZones ?? [],
            intervalSegments: detail?.intervalSegments ?? [],
            embedded: true,
            belowPreview: AnyView(cardPageDots)
        )
        .frame(maxWidth: .infinity)
        .frame(minHeight: 520)
    }

    // 메인 편집(클립 추가·스타일·데이터)은 쉬는날 방식 전용 시트로
    private var oneLinerEditButton: some View {
        Button { oneLinerVM.showOneLinerSheet = true } label: {
            Label(AppLanguage.shared.s("한마디 편집", "Edit one-liner"), systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Theme.violet)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    // → OneLinerControls.swift: OneLinerVideoSlotInputView
    @ViewBuilder
    private var oneLinerVideoSlotInput: some View {
        OneLinerVideoSlotInputView(
            vm: oneLinerVM,
            onSave:   { saveOneLinerSettings() },
            onRender: { await renderCard(showSpinner: false) }
        )
    }

    // 이 러닝의 고유 문구 풀 (같은 텍스트 중복 제거, 최신순).
    // 칩 줄 상시 표시에 사용.
    private var uniqueOneLinerEntries: [OneLinerEntry] {
        var seen = Set<String>()
        var result: [OneLinerEntry] = []
        for entry in oneLinerEntries.reversed() {   // reversed() = 최신 먼저
            let key = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && seen.insert(key).inserted {
                result.append(entry)
            }
        }
        return result   // 최신순 유지
    }

    // 문구 칩 줄: entry가 1개 이상이면 상시 표시.
    // · 현재 사진에 이미 적용된 문구 칩에는 체크 표시.
    // · 탭 → 현재 사진의 entry를 해당 문구로 교체(upsert 저장).
    // · 다중 사진 연재 모드(사진 2장 이상)에서는 숨김 — 각 사진마다 독립 입력이 의도된 설계.
    @ViewBuilder
    private var oneLinerReuseChipRow: some View {
        let isMultiPhotoStory = template == .story && oneLinerVM.storyPhotoUUIDs.count > 1
        if !uniqueOneLinerEntries.isEmpty && !isMultiPhotoStory {
            let currentText = oneLinerVM.oneLinerText.trimmingCharacters(in: .whitespacesAndNewlines)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(uniqueOneLinerEntries) { entry in
                        let isCurrent = entry.text.trimmingCharacters(in: .whitespacesAndNewlines) == currentText
                        Button {
                            oneLinerVM.oneLinerText     = entry.text
                            oneLinerVM.oneLinerFont     = entry.font
                            oneLinerVM.oneLinerColor    = entry.textColor
                            oneLinerVM.oneLinerPosition = entry.position
                            oneLinerVM.oneLinerShowDate = entry.showDate
                            saveOneLinerSettings()           // 현재 사진 entry에 upsert
                            Task { await renderCard(showSpinner: false) }
                        } label: {
                            HStack(spacing: 5) {
                                if isCurrent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text(entry.text.count > 10
                                     ? String(entry.text.prefix(10)) + "…"
                                     : entry.text)
                                    .font(.custom(entry.font.fontName, size: 13))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isCurrent ? Theme.violet : entry.textColor.color.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isCurrent ? Theme.violet.opacity(0.12) : Color(hex: "1E1E28"))
                            .overlay(Capsule().strokeBorder(
                                isCurrent ? Theme.violet.opacity(0.55) : Color.white.opacity(0.15),
                                lineWidth: 1
                            ))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // → OneLinerControls.swift: OneLinerGridAndChipsView
    private var oneLinerGridAndChips: some View {
        OneLinerGridAndChipsView(
            vm:             oneLinerVM,
            template:       template,
            hasSourceVideo: sourceVideoURL != nil || !oneLinerVM.oneLinerClipRecipes.isEmpty,
            onSave:         { saveOneLinerSettings() },
            onRender:       { await renderCard(showSpinner: false) }
        )
    }

    // → OneLinerControls.swift: OneLinerTextFieldView
    @ViewBuilder
    private var oneLinerTextField: some View {
        OneLinerTextFieldView(
            vm:          oneLinerVM,
            focusedLine: $oneLinerFocusedLine,
            onSave:      { saveOneLinerSettings() },
            onRender:    { await renderCard(showSpinner: false) }
        )
    }

    // → ECGControls.swift: ECGChipRowView
    private var ecgChipRow: some View {
        ECGChipRowView(vm: ecgVM, onRender: { await renderCard(showSpinner: false) })
    }

    // Placeable·OneLiner는 3탭(스토리/영상/슬라이드)만, 그 외 카드는 전체 목록.
    private var templateTabs: [ShareTemplate] {
        if isOneLiner || isPlaceable { return [.story, .video, .slide] }
        return ShareTemplate.allCases
    }

    private var templatePicker: some View {
        HStack(spacing: 0) {
            ForEach(templateTabs, id: \.self) { t in
                let available = ShareCard(rawValue: cardIndex)?.supportedTemplates.contains(t) ?? true
                let selected  = template == t
                Button {
                    guard available else { return }
                    if isOneLiner {
                        previewPlayer.pause()
                    }
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
            Text(AppLanguage.shared.s("영상 선택과 공유시 영상 길이에 따라 시간이 소요됩니다.", "Processing time varies by video length."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.bottom, 8)
        } else {
            Color.clear.frame(height: 20)
        }
    }

    // MARK: - Body helpers (extracted to prevent @ViewBuilder stack overflow)

    @ViewBuilder
    private var oneLinerControlPanel: some View {
        AnyView(templatePicker)
        Color.clear.frame(height: 8)
        AnyView(activeChipRow)
        if template == .story || template == .slide {
            AnyView(photoStrip.padding(.bottom, storyPhotos.isEmpty ? 4 : 0))
            if template == .story, !storyPhotos.isEmpty {
                Text(AppLanguage.shared.s("사진 \(storyPhotos.count)장 · 탭하면 편집", "\(storyPhotos.count) photo(s) · Tap to edit"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
            }
            if template == .slide, !storyPhotos.isEmpty {
                let totalSec = Int(Double(storyPhotos.count) * PhotoSlideComposition.placeableSlideDuration)
                Text(AppLanguage.shared.s("클립 \(storyPhotos.count)개 · \(totalSec)초 · 탭하면 편집", "\(storyPhotos.count) clips · \(totalSec)s · Tap to edit"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
            }
        }
        AnyView(bottomControls)
    }

    @ViewBuilder
    private var placeableControlPanel: some View {
        AnyView(templatePicker)
        AnyView(activeChipRow.padding(.bottom, 3))
        if isPlaceable, template == .story || template == .slide {
            AnyView(placeableStoryTextField)
        }
        if isPlaceable, template == .video, !placeableVM.placeableClipRecipes.isEmpty {
            AnyView(placeableTrimRow)
        }
        if template == .story {
            AnyView(photoStrip.padding(.bottom, 8))
        }
        if isPlaceable, template == .slide {
            AnyView(photoStrip.padding(.bottom, storyPhotos.isEmpty ? 4 : 0))
            if !storyPhotos.isEmpty {
                let clipCnt = storyPhotos.count
                let totalSec = Int(Double(clipCnt) * PhotoSlideComposition.placeableSlideDuration)
                Text(AppLanguage.shared.s(
                    "사진 \(clipCnt)장 · \(totalSec)초",
                    "\(clipCnt) photo(s) · \(totalSec)s"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
            }
        }
        if template == .video {
            if isPlaceable {
                AnyView(MultiClipEditorView(
                    recipes: Bindable(placeableVM).placeableClipRecipes,
                    isPhotoSlideMode: .constant(false),
                    muteAudio: Bindable(placeableVM).placeableMuteAudio,
                    selectedClipIndex: $placeableVM.selectedPlaceableClipIndex,
                    savedClipLines: [],
                    availableMetrics: [],
                    enabledMetricIDs: Bindable(placeableVM).placeableEnabledMetricIDs,
                    onSave: {
                        savePlaceableVideoClips()
                        Task { await loadPlaceablePreview() }
                    },
                    showTitle: false,
                    openEditOnTap: false,
                    videoTitle: Bindable(placeableVM).placeableVideoTitle,
                    titleStyle: Bindable(placeableVM).placeableTitleStyle
                )
                .padding(.horizontal, 24))
            } else {
                // Athletic 영상: 멀티 클립 (최대 5개) + 개별 트림 바
                AnyView(VStack(alignment: .leading, spacing: 10) {
                    // 썸네일 row
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Bindable(athleticVM).athleticClipRecipes) { $recipe in
                                ZStack(alignment: .topTrailing) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Group {
                                            if let thumb = recipe.thumbnail {
                                                Image(uiImage: thumb)
                                                    .resizable().scaledToFill()
                                            } else {
                                                Rectangle()
                                                    .fill(Color.white.opacity(0.12))
                                            }
                                        }
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Theme.violet, lineWidth: 2.5))
                                        let sec = recipe.trimEnd - recipe.trimStart
                                        Text(sec >= 10 ? "\(Int(sec))s" : String(format: "%.1fs", sec))
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4).padding(.vertical, 2)
                                            .background(Color.black.opacity(0.65))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                            .padding(3)
                                    }
                                    Button {
                                        let rid = recipe.id
                                        athleticVM.athleticClipRecipes.removeAll { $0.id == rid }
                                        if athleticVM.athleticClipRecipes.isEmpty {
                                            sourceVideoURL    = nil
                                            videoPreviewImage = nil
                                        } else {
                                            sourceVideoURL    = athleticVM.athleticClipRecipes.first?.url
                                            videoPreviewImage = athleticVM.athleticClipRecipes.first?.thumbnail
                                        }
                                        exportedVideoFile = nil
                                    } label: {
                                        ZStack {
                                            Circle().fill(Color.black.opacity(0.65)).frame(width: 18, height: 18)
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 5, y: -5)
                                }
                            }
                            // + 추가 버튼 (최대 5개)
                            if athleticVM.athleticClipRecipes.count < 5 {
                                PhotosPicker(
                                    selection: Bindable(athleticVM).athleticPickerItems,
                                    maxSelectionCount: 5 - athleticVM.athleticClipRecipes.count,
                                    matching: .videos,
                                    photoLibrary: .shared()
                                ) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 52, height: 52)
                                        .overlay(Image(systemName: "plus")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Theme.violet))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    // 음소거 토글
                    Button {
                        athleticVM.athleticMuted.toggle()
                        athleticVM.athleticVideoState.player?.isMuted = athleticVM.athleticMuted
                        exportedVideoFile = nil
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: athleticVM.athleticMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .medium))
                            Text(AppLanguage.shared.s(
                                athleticVM.athleticMuted ? "음소거" : "소리 켜짐",
                                athleticVM.athleticMuted ? "Muted" : "Sound On"
                            ))
                            .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(athleticVM.athleticMuted ? .secondary : Theme.violet)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(athleticVM.athleticMuted ? Color.white.opacity(0.08) : Theme.violet.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 클립별 트림 바
                    ForEach(Bindable(athleticVM).athleticClipRecipes) { $recipe in
                        let idx    = athleticVM.athleticClipRecipes.firstIndex(where: { $0.id == recipe.id }) ?? 0
                        let maxSec = min(recipe.fullDuration, VideoExportService.trimDuration)
                        let used   = max(0, recipe.trimEnd - recipe.trimStart)
                        VStack(spacing: 4) {
                            if athleticVM.athleticClipRecipes.count > 1 {
                                Text(AppLanguage.shared.s("클립 \(idx + 1)", "Clip \(idx + 1)"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.violet)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text(AppLanguage.shared.s(
                                "\(trimFormatSec(recipe.trimStart)) – \(trimFormatSec(recipe.trimEnd))  ·  \(trimFormatSec(used)) 사용",
                                "\(trimFormatSec(recipe.trimStart)) – \(trimFormatSec(recipe.trimEnd))  ·  \(trimFormatSec(used)) used"
                            ))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            TrimBarView(
                                duration: maxSec,
                                trimStart: $recipe.trimStart,
                                trimEnd:   $recipe.trimEnd,
                                onEditingEnded: { exportedVideoFile = nil }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8))
            }
        }
        AnyView(bottomControls)
    }

    // MARK: - Body

    // Extracted to keep the body modifier chain within Swift's type-check budget.
    private var bodyContent: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 4)
                    cardSection
                    cardPageDots
                    Color.clear.frame(height: 6)
                    if isOneLiner {
                        oneLinerControlPanel
                    } else {
                        placeableControlPanel
                    }
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
        .navigationTitle(AppLanguage.shared.s("공유 카드", "Share Card"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // bodyWithSheets: sheet 표시 모디파이어를 분리해 타입체커 부담 감소
    private var bodyWithSheets: some View {
        bodyContent
        .sheet(isPresented: $showStoryPhotoPicker) {
            let pickerPhotos = allPickedPhotos.isEmpty ? storyPhotos : allPickedPhotos
            StoryPhotoPickerSheet(photos: pickerPhotos, selected: selectedPhoto) { picked, idx in
                selectedPhoto = picked
                selectedPhotoIndex = idx
                showStoryPhotoPicker = false
                Task { await renderCard() }
            }
        }
        .sheet(isPresented: Bindable(oneLinerVM).showStoryClipEdit, onDismiss: onStoryClipEditDismiss) {
            ClipTrimSheet(
                recipes: Bindable(oneLinerVM).storyClipEditRecipes,
                selectedClipIndex: Bindable(oneLinerVM).storyClipEditIndex,
                hideTimePicker: template == .story,
                isStoryMode: template == .story,
                isPhotoSlideMode: template == .slide,
                availableMetrics: oneLinerAvailableMetrics,
                routeCoords: routeCoords,
                hrSamples: shareHRSamples,
                splits: detail?.splits ?? [],
                chartSeriesData: chartSeriesData,
                hrZones: detail?.hrZones ?? [],
                intervalSegments: detail?.intervalSegments ?? [],
                videoTitle: oneLinerVM.oneLinerVideoTitle,
                titleStyle: oneLinerVM.oneLinerTitleStyle
            )
        }
    }

    // bodyWithPickerHandlers: picker/template/card 변경 핸들러 (타입체커 분산)
    private var bodyWithPickerHandlers: some View {
        bodyWithSheets
        .task { await onAppear() }
        .onChange(of: pickerItems) { _, newItems in onPickerItemsChanged(newItems) }
        .onChange(of: videoPickerItem) { _, newItem in onVideoPickerItemChanged(newItem) }
        .onChange(of: athleticVM.athleticPickerItems) { _, newItems in onAthleticPickerItemsChanged(newItems) }
        .onChange(of: template) { old, new in syncOneLinerVideoBacking(from: old, to: new); onTemplateChanged() }
        .onChange(of: cardPanel) { _, newPanel in
            Task {
                await loadChartData(for: newPanel)
                await renderCard(showSpinner: false)
            }
        }
        .onChange(of: cardIndex) { _, newIndex in onCardIndexChanged(newIndex) }
    }

    // bodyWithEventHandlers attaches onChange/task handlers; split from body to reduce
    // the modifier chain the Swift type-checker must evaluate in a single expression.
    private var bodyWithEventHandlers: some View {
        bodyWithPickerHandlers
        // Athletic 클립 변경 시 미리보기 플레이어 리셋
        .onChange(of: athleticVM.athleticClipRecipes.count) { _, _ in athleticVM.athleticVideoState.invalidate() }
        // OneLiner 설정 변경 시 기존 export 무효화 — .video와 .slide 모두 포함
        .onChange(of: oneLinerVM.oneLinerText) { _, _ in
            guard isOneLiner, template == .video || template == .slide else { return }
            exportedVideoFile = nil
        }
        .onChange(of: oneLinerVM.oneLinerPosition) { _, _ in
            guard isOneLiner, template == .video || template == .slide else { return }
            exportedVideoFile = nil
        }
        .onChange(of: oneLinerVM.oneLinerColor) { _, _ in
            guard isOneLiner, template == .video || template == .slide else { return }
            exportedVideoFile = nil
        }
        .onChange(of: oneLinerVM.oneLinerFont) { _, _ in
            guard isOneLiner, template == .video || template == .slide else { return }
            exportedVideoFile = nil
        }
        .onChange(of: oneLinerVM.oneLinerShowDate) { _, _ in
            guard isOneLiner, template == .video || template == .slide else { return }
            exportedVideoFile = nil
        }
        .onChange(of: oneLinerVM.oneLinerClipRecipes.count) { _, _ in
            previewPlayer.invalidate()
            exportedVideoFile = nil
        }
        // OneLiner 카드(index 1)의 사진이 바뀌면 새 사진의 entry 로드.
        // 저장은 Button 액션에서 cardPhotoIndex 변경 전에 처리.
        // Button 액션이 loadOneLinerSettingsFor를 먼저 호출하지만, 포커스 해제 타이밍에 따라
        // onChange도 발화할 수 있어 방어적으로 유지 — 중복 로드는 무해함.
        .onChange(of: cardPhotoIndex) { old, new in
            guard isOneLiner, template == .story, old[1] != new[1] else { return }
            loadOneLinerSettingsFor(photoIndex: new[1] ?? 0)
        }
    }

    // Placeable story overlay state 변경 → UserDefaults 저장. body에서 분리해 타입 체커 부담 경감.
    private var bodyWithStoryOverlayHandlers: some View {
        bodyWithEventHandlers
            .onChange(of: placeableVM.placeableStoryTexts)    { _, _ in savePlaceableStoryOverlay(); if isPlaceable { exportedVideoFile = nil }; Task { await renderCard(showSpinner: false) } }
            .onChange(of: placeableVM.placeableStoryFont)     { _, _ in savePlaceableStoryOverlay(); applyStyleToVideoClips(); rebuildPlaceableSlidePreview(); if isPlaceable { exportedVideoFile = nil } }
            .onChange(of: placeableVM.placeableStoryColor)    { _, _ in savePlaceableStoryOverlay(); applyStyleToVideoClips(); rebuildPlaceableSlidePreview(); if isPlaceable { exportedVideoFile = nil } }
            .onChange(of: placeableVM.placeableStorySize)     { _, _ in savePlaceableStoryOverlay(); applyStyleToVideoClips(); rebuildPlaceableSlidePreview(); if isPlaceable { exportedVideoFile = nil } }
            .onChange(of: placeableVM.placeableStoryPosition) { _, _ in savePlaceableStoryOverlay(); applyStyleToVideoClips(); rebuildPlaceableSlidePreview(); if isPlaceable { exportedVideoFile = nil } }
            .onChange(of: placeableVM.placeableStoryHasBorder)   { _, _ in savePlaceableStoryOverlay(); applyStyleToVideoClips(); rebuildPlaceableSlidePreview(); if isPlaceable { exportedVideoFile = nil } }
            .onChange(of: placeableVM.placeableStoryPlateOn)     { _, _ in savePlaceableStoryOverlay(); applyStyleToVideoClips(); rebuildPlaceableSlidePreview(); if isPlaceable { exportedVideoFile = nil } }
            .onChange(of: placeableVM.placeableStoryPlatePreset) { _, _ in savePlaceableStoryOverlay(); applyStyleToVideoClips(); rebuildPlaceableSlidePreview(); if isPlaceable { exportedVideoFile = nil } }
            .onChange(of: placeableVM.placeableMuteAudio) { _, newVal in
                guard isPlaceable, template == .video else { return }
                // 토글 즉시 live player에 반영 — 재빌드 불필요
                previewPlayer.setMuted(newVal)
                savePlaceableVideoClips()
            }
            .onChange(of: placeableVM.placeableClipRecipes.count) { _, _ in
                exportedVideoFile = nil
                applyAnimationToVideoClips()
                applyStyleToVideoClips()
                savePlaceableVideoClips()
                Task { await loadPlaceablePreview() }
            }
            .onChange(of: storyPhotos.count) { _, _ in
                guard isPlaceable else { return }
                exportedVideoFile = nil
                // previewPlayer는 영상·슬라이드 공유 — 슬라이드 템플릿일 때만 빌드.
                guard template == .slide else { return }
                let photos = storyPhotos
                if !photos.isEmpty {
                    Task {
                        let overlay = makePlaceableDataOverlay()
                        let recipes = makePlaceableSlideRecipes(for: photos)
                        await previewPlayer.buildForPhotoSlides(
                            photos: photos, recipes: recipes,
                            activityDate: activity.date, showDate: false,
                            dataOverlayImage: overlay)
                    }
                } else {
                    previewPlayer.invalidate()
                }
            }
            .onChange(of: placeableVM.placeableSlideAppearance) { _, _ in
                guard isPlaceable, template == .slide else { return }
                exportedVideoFile = nil
                let photos = storyPhotos
                guard !photos.isEmpty else { return }
                Task {
                    let overlay = makePlaceableDataOverlay()
                    let recipes = makePlaceableSlideRecipes(for: photos)
                    await previewPlayer.buildForPhotoSlides(
                        photos: photos, recipes: recipes,
                        activityDate: activity.date, showDate: false,
                        dataOverlayImage: overlay)
                }
            }
            .onChange(of: placeableVM.selectedPlaceableClipIndex) { _, _ in
                // 단일 클립만: 선택 변경 → 해당 클립 로드. 멀티클립은 합쳐진 미리보기 유지.
                guard isPlaceable, template == .video, placeableVM.placeableClipRecipes.count <= 1 else { return }
                Task { await loadPlaceablePreview() }
            }
    }

    private var bodyWithSlideHandlers: some View {
        bodyWithStoryOverlayHandlers
            .onChange(of: placeableVM.slideDecorEffect) { _, _ in
                guard isPlaceable, template == .slide, placeableVM.placeableSlideAppearance == .fade else { return }
                exportedVideoFile = nil
                let photos = storyPhotos
                guard !photos.isEmpty else { return }
                Task {
                    let overlay = makePlaceableDataOverlay()
                    let recipes = makePlaceableSlideRecipes(for: photos)
                    await previewPlayer.buildForPhotoSlides(
                        photos: photos, recipes: recipes,
                        activityDate: activity.date, showDate: false,
                        dataOverlayImage: overlay)
                }
            }
            .onChange(of: placeableVM.slideFlyDirection) { _, _ in
                guard isPlaceable, template == .slide, placeableVM.placeableSlideAppearance == .flyIn else { return }
                exportedVideoFile = nil
                let photos = storyPhotos
                guard !photos.isEmpty else { return }
                Task {
                    let overlay = makePlaceableDataOverlay()
                    let recipes = makePlaceableSlideRecipes(for: photos)
                    await previewPlayer.buildForPhotoSlides(
                        photos: photos, recipes: recipes,
                        activityDate: activity.date, showDate: false,
                        dataOverlayImage: overlay)
                }
            }
    }

    private var bodyWithVideoAnimHandlers: some View {
        bodyWithSlideHandlers
            .onChange(of: placeableVM.placeableSlideAppearance) { _, _ in
                guard isPlaceable, template == .video else { return }
                exportedVideoFile = nil
                applyAnimationToVideoClips()
                Task { await loadPlaceablePreview() }
            }
            .onChange(of: placeableVM.slideDecorEffect) { _, _ in
                guard isPlaceable, template == .video, placeableVM.placeableSlideAppearance == .fade else { return }
                exportedVideoFile = nil
                applyAnimationToVideoClips()
                Task { await loadPlaceablePreview() }
            }
            .onChange(of: placeableVM.slideFlyDirection) { _, _ in
                guard isPlaceable, template == .video, placeableVM.placeableSlideAppearance == .flyIn else { return }
                exportedVideoFile = nil
                applyAnimationToVideoClips()
                Task { await loadPlaceablePreview() }
            }
    }

    var body: some View {
        bodyWithVideoAnimHandlers
        .onChange(of: heroMetric) { _, _ in
            guard isBigNumber else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: bigNumberVM.bigNumberShowMood) { _, _ in
            guard isBigNumber else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: bigNumberVM.bigNumberShowMemo) { _, _ in
            guard isBigNumber else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: bigNumberVM.bigNumberAccent) { _, _ in
            guard isBigNumber else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: placeableVM.placeableMetricsPosition) { _, _ in
            guard isPlaceable else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: placeableVM.placeableAccent) { _, _ in
            guard isPlaceable else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: placeableVM.placeableSize) { _, _ in
            guard isPlaceable else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: placeableVM.placeableLayout) { _, _ in
            guard isPlaceable else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: ecgVM.ecgAccent) { _, _ in
            guard isECG else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: skyVM.skyAccent) { _, _ in
            guard isSky else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: ticketVM.ticketAccent) { _, _ in
            guard isTicket else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: oneLinerVM.oneLinerVideoTitle) { _, _ in previewPlayer.invalidate(); if isOneLiner { exportedVideoFile = nil } }
        .onChange(of: oneLinerVM.oneLinerTitleStyle) { _, _ in previewPlayer.invalidate(); if isOneLiner { exportedVideoFile = nil } }
        .interactiveDismissDisabled(previewPlayer.isBuilding)
        .task(id: template) { await animateRouteVideoPreview() }
        .alert(AppLanguage.shared.s("이미 내보낸 영상이에요", "Already exported video"),
               isPresented: $showExportedVideoWarning) {
            Button(AppLanguage.shared.s("확인", "OK"), role: .cancel) { }
        } message: {
            Text(AppLanguage.shared.s(
                "원본 영상을 선택해 주세요. 내보낸 영상을 다시 선택하면 내용이 두 번 나타납니다.",
                "Please select the original video. Selecting an exported video again will duplicate the overlay."
            ))
        }
        .alert(AppLanguage.shared.s("내보내기 실패", "Export Failed"),
               isPresented: $showVideoExportError) {
            Button(AppLanguage.shared.s("확인", "OK"), role: .cancel) { showVideoExportError = false }
        } message: {
            Text(videoExportError ?? "")
        }
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

    // MARK: - Event handler helpers (extracted to keep body type-check budget manageable)

    private func onPickerItemsChanged(_ newItems: [PhotosPickerItem]) {
        photoOffset = .zero
        photoOffsets = [:]
        Task {
            guard !newItems.isEmpty else { return }
            var newImages: [UIImage] = []
            var newItemIDs: [String] = []
            for item in newItems {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    newImages.append(image)
                    // Prefer PHAsset localIdentifier if available; else generate a stable UUID
                    newItemIDs.append(item.itemIdentifier ?? UUID().uuidString)
                }
            }
            guard !newImages.isEmpty else { return }
            let existing = allPickedPhotos.isEmpty ? storyPhotos : allPickedPhotos
            let merged = Array((existing + newImages).prefix(5))
            selectedPhoto = merged[0]
            allPickedPhotos = merged
            // Extend oneLinerVM.storyPhotoUUIDs: preserve existing, append new
            let existingUUIDs = oneLinerVM.storyPhotoUUIDs.isEmpty
                ? (story?.sortedPhotoUUIDs ?? (0..<existing.count).map { _ in UUID().uuidString })
                : oneLinerVM.storyPhotoUUIDs
            let mergedUUIDs = Array((existingUUIDs + newItemIDs).prefix(5))
            oneLinerVM.storyPhotoUUIDs = mergedUUIDs
            persistStoryPhotos(merged, uuids: mergedUUIDs)
            let newIdx = min(existing.count, merged.count - 1)
            for ci in [0, 1, 2, 3] { cardPhotoIndex[ci] = newIdx }
            if template == .slide { previewPlayer.invalidate() }
            await renderCard()
        }
    }

    private func onVideoPickerItemChanged(_ newItem: PhotosPickerItem?) {
        Task {
            guard let item = newItem,
                  let result = try? await item.loadTransferable(type: VideoPickerResult.self)
            else { return }

            // Block if this video was already exported by MIMORunning — re-using it
            // as a source would bake a second overlay on top of the first.
            if isOneLiner, await VideoExportService.isMIMOOneLinerExport(url: result.url) {
                showExportedVideoWarning = true
                videoPickerItem = nil
                return
            }

            sourceVideoURL = result.url

            // OneLiner 영상: 영상 길이에서 슬롯 수 자동 계산 (~3.5초/슬롯, 최소 2, 최대 20)
            if isOneLiner {
                let dur = (try? await AVURLAsset(url: result.url).load(.duration).seconds) ?? 7.0
                let count = max(2, min(20, Int(ceil(dur / 3.5))))
                let existing = oneLinerVM.oneLinerVideoSlotTexts
                oneLinerVM.oneLinerVideoSlotCount = count
                oneLinerVM.oneLinerVideoSlotTexts = (0..<count).map { i in
                    i < existing.count ? existing[i] : ""
                }
            }

            // PHAsset ID가 확정된 후 해당 영상의 저장된 OneLiner 설정 로드
            if isOneLiner { loadOneLinerSettings() }
            videoPreviewImage = await VideoExportService.firstFrame(of: result.url)
            // Placeable 영상: 프리뷰는 placeableVM.placeableClipRecipes.count onChange → loadPlaceablePreview() 에서 처리
            // 자동 합성 안 함 — 사용자가 미리보기로 배치 확인 후 직접 합성 버튼 탭
        }
    }

    private func onStoryClipEditDismiss() {
        saveStoryClipEdits(oneLinerVM.storyClipEditRecipes, isSlide: oneLinerVM.storyClipEditIsSlide)
        exportedVideoFile = nil
        for i in 0..<4 { cardPhotoIndex[i] = oneLinerVM.storyClipEditIndex }
    }

    private func onAthleticPickerItemsChanged(_ newItems: [PhotosPickerItem]) {
        guard !newItems.isEmpty else { return }
        Task {
            var isFirst = true
            for item in newItems {
                guard let result = try? await item.loadTransferable(type: VideoPickerResult.self) else { continue }
                let url = result.url
                let dur = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 30.0
                let thumb = await VideoExportService.firstFrame(of: url)
                var r = ClipRecipe(url: url, fullDuration: dur, thumbnail: thumb)
                r.trimEnd = min(dur, VideoExportService.trimDuration)
                athleticVM.athleticClipRecipes.append(r)
                // 첫 번째 클립 처리 직후 프리뷰 즉시 업데이트 (전체 루프 끝까지 기다리지 않음)
                if isFirst {
                    isFirst = false
                    if let t = thumb { videoPreviewImage = t }
                    sourceVideoURL = url
                    if template != .video { template = .video }
                }
            }
            athleticVM.athleticPickerItems = []
            // 프리뷰가 아직 없으면 레시피 첫 항목 썸네일로 보완
            if videoPreviewImage == nil {
                videoPreviewImage = athleticVM.athleticClipRecipes.first?.thumbnail
                sourceVideoURL    = athleticVM.athleticClipRecipes.first?.url
                if template != .video { template = .video }
            }
            exportedVideoFile = nil
            athleticVM.athleticVideoState.invalidate()
        }
    }

    @MainActor
    private func buildAthleticPreview() async {
        guard !athleticVM.athleticClipRecipes.isEmpty, !athleticVM.athleticPreviewBuilding else { return }
        athleticVM.athleticPreviewBuilding = true
        defer { athleticVM.athleticPreviewBuilding = false }
        athleticVM.athleticVideoState.invalidate()
        if let result = try? await VideoExportService.buildConcatenatedPreviewItem(recipes: athleticVM.athleticClipRecipes) {
            athleticVM.athleticVideoState.loadPlayerItem(result.playerItem, duration: result.duration)
            athleticVM.athleticVideoState.player?.isMuted = athleticVM.athleticMuted
            athleticVM.athleticVideoState.togglePlayPause()
        }
    }

    private func onTemplateChanged() {
        routeVideoFile = nil
        // Placeable 영상(.video) 합성 결과는 .video 안에서만 유지; 다른 템플릿 전환 시 초기화
        if isPlaceable {
            if template != .video { exportedVideoFile = nil }
        } else {
            exportedVideoFile = nil
        }
        // Stop preview when leaving clip modes (story has no preview)
        if isOneLiner, template == .story { previewPlayer.pause() }
        // Placeable 영상 진입 시 문구 탭 기본 선택, 벗어날 때 플레이어 정지
        if isPlaceable, template == .video {
            placeableVM.placeableStoryTabIsText = true
            let hadClips = !placeableVM.placeableClipRecipes.isEmpty
            loadPlaceableVideoClips()
            // 클립이 이미 로드된 상태였으면 count 변화 없음 → onChange 미발화 → 수동 재빌드
            if hadClips { Task { await loadPlaceablePreview() } }
        }
        if isPlaceable, template != .video { previewPlayer.pause() }
        // Athletic 영상 템플릿 진입 시 레시피 복원 — sourceVideoURL이 있는데 recipes가 비어 있으면 재구성
        if !isPlaceable, !isOneLiner, template == .video,
           let url = sourceVideoURL, athleticVM.athleticClipRecipes.isEmpty {
            Task {
                let dur = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 30.0
                var r = ClipRecipe(url: url, fullDuration: dur, thumbnail: videoPreviewImage)
                r.trimEnd = min(dur, VideoExportService.trimDuration)
                athleticVM.athleticClipRecipes = [r]
            }
        }
        // Placeable 슬라이드: 항상 재빌드 (previewPlayer가 영상과 공유되므로 isReady 체크 불가)
        if isPlaceable, template == .slide {
            let photos = storyPhotos
            if !photos.isEmpty {
                Task {
                    let overlay = makePlaceableDataOverlay()
                    let recipes = makePlaceableSlideRecipes(for: photos)
                    await previewPlayer.buildForPhotoSlides(
                        photos: photos, recipes: recipes,
                        activityDate: activity.date, showDate: false,
                        dataOverlayImage: overlay)
                }
            } else {
                previewPlayer.invalidate()
            }
        }
        if isPlaceable, template != .slide { previewPlayer.pause() }
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

    private func onCardIndexChanged(_ newIndex: Int) {
        routeVideoFile = nil
        exportedVideoFile = nil
        // 새 카드가 현재 템플릿을 지원하지 않으면 그 카드의 기본 템플릿으로 자동 전환.
        if let card = ShareCard(rawValue: newIndex),
           !card.supportedTemplates.contains(template) {
            template = card.defaultTemplate
        }
        // OneLiner 카드 진입 시 현재 미디어(그라데이션 포함) 저장값 로드 (인라인 편집, 모달 없음)
        if newIndex == 1 { loadOneLinerSettings() }
        // Placeable 카드 복귀 시 클립 복원 + 미리보기 로드
        if newIndex == 0 {
            if template == .video { loadPlaceableVideoClips() }
            if !placeableVM.placeableClipRecipes.isEmpty { Task { await loadPlaceablePreview() } }
        }
        // Athletic 카드 진입 시 — 이전 영상 설정이 있으면 영상 템플릿 복원, 레시피 없으면 재구성
        if newIndex == 2 {
            if !athleticVM.athleticClipRecipes.isEmpty {
                template = .video   // 영상을 이미 설정한 적 있으면 영상 모드 복원
            } else if let url = sourceVideoURL {
                Task {
                    let dur = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 30.0
                    var r = ClipRecipe(url: url, fullDuration: dur, thumbnail: videoPreviewImage)
                    r.trimEnd = min(dur, VideoExportService.trimDuration)
                    athleticVM.athleticClipRecipes = [r]
                }
            }
        }
        Task { await renderCard(showSpinner: false) }
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
                          photo: nil,
)
        case .story:
            if let photo = photoFor(2) {
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
                              photo: photo)
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
                                   shoeName: displayShoeName,
)
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
        case .video, .slide:
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
                chartIntervalSegments: detail?.intervalSegments ?? [],
                hrSamplesForRoute: shareHRSamples,
                routeWorkoutDuration: activity.duration,
                routeZoneBounds: shareZoneBounds,
                showHRGradient: showHRGradientForRoute
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

    @ViewBuilder
    private var videoPreviewCard: some View {
        let km = activity.distance / 1000
        let distStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)

        // OneLiner: 카드 1(oneLinerCardPreview)이 contentLayer를 독점 소유.
        // 카드 2는 항상 정적 미리보기 + ▶ 버튼만 표시 → contentLayer 충돌(검은 화면) 방지.
        if isOneLiner, oneLinerHasPhotos {
            // 재생 전에도 실제 라이브 프리뷰와 동일한 9:16 한마디 카드 표시 → 창·크기 일치
            // oneLinerVideoPreviewCard는 고정 300pt 폭 → 컨테이너 폭에 맞춰 스케일(라이브의 aspectRatio fit과 동일 크기)
            GeometryReader { geo in
                oneLinerVideoPreviewCard
                    .scaleEffect(geo.size.width / 300, anchor: .topLeading)
            }
            .aspectRatio(9/16, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay {
                    if isExportingVideo {
                        ZStack {
                            Color.black.opacity(0.55)
                            VStack(spacing: 8) {
                                ProgressView().tint(.white).scaleEffect(1.2)
                                Text(AppLanguage.shared.s("합성 중...", "Processing..."))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else if previewPlayer.isBuilding {
                        ProgressView().tint(.white)
                            .padding(14)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                    } else {
                        Button { buildPreview() } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.55), radius: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
        } else {
            let vidW: CGFloat    = 375.0 * 9.0 / 16.0   // 9:16 영상 폭 ≈211pt
            let pvScale: CGFloat = vidW / 300.0          // 요소 크기 스케일
            ZStack {
                // Background: 레터박스 + 9:16 필러박스 영상
                Color.black
                // 영상이 준비된 경우 RawVideoPlayerView를 썸네일 대신 배경으로 사용
                // (VideoOverlayCard 아래 배치하여 데이터 오버레이가 항상 위에 표시되도록)
                if !isOneLiner, athleticVM.athleticVideoState.isReady, let avPlayer = athleticVM.athleticVideoState.player {
                    RawVideoPlayerView(player: avPlayer)
                        .frame(width: vidW, height: 375)
                } else {
                    let previewThumb = videoPreviewImage ?? athleticVM.athleticClipRecipes.first?.thumbnail
                    if let preview = previewThumb {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: vidW, height: 375)
                            .clipped()
                    } else if !isExportingVideo {
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

                // 데이터 오버레이: 9:16 영역(vidW×375) 안에 배치
                // BigNumber: 자체 오버레이(히어로 넘버 중앙), Athletic: VideoOverlayCard(상·하 5% 여백)
                if isBigNumber {
                    makeBigNumberOverlayView()
                        .frame(width: vidW, height: 375)
                } else {
                    let inset: CGFloat = 375 * 0.05   // 18.75pt
                    VideoOverlayCard(
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
                        weather: condition?.weather,
                        shoeName: displayShoeName,
                        scale: pvScale,
                        topInset: inset,
                        bottomInset: inset
                    )
                    .frame(width: vidW, height: 375)
                }

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

                // ▶ play button for OneLiner multi-clip preview
                if isOneLiner, oneLinerHasPhotos, !isExportingVideo {
                    if previewPlayer.isBuilding {
                        ProgressView().tint(.white)
                            .padding(14)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                    } else {
                        Button { buildPreview() } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.55), radius: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // ▶ Athletic 멀티클립 미리보기 컨트롤 (플레이어는 배경 레이어에 있음)
                if !isOneLiner, !athleticVM.athleticClipRecipes.isEmpty, !isExportingVideo {
                    if athleticVM.athleticVideoState.isReady {
                        Button {
                            athleticVM.athleticVideoState.togglePlayPause()
                        } label: {
                            Image(systemName: athleticVM.athleticVideoState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(athleticVM.athleticVideoState.isPlaying ? 0 : 0.85))
                                .shadow(color: .black.opacity(0.55), radius: 10)
                        }
                        .buttonStyle(.plain)
                    } else if athleticVM.athleticPreviewBuilding {
                        ProgressView().tint(.white)
                            .padding(14)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                    } else {
                        Button {
                            Task { await buildAthleticPreview() }
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.55), radius: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .clipped()
        }
    }

    // MARK: - Share CTA

    @ViewBuilder
    private var shareCTA: some View {
        if template == .video || template == .slide {
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
            } else if template == .slide, storyPhotos.isEmpty {
                Text(AppLanguage.shared.s("사진을 선택해 주세요", "Select photos first"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                Button {
                    Task { await exportVideo() }
                } label: {
                    // 쉬는날과 동일 문구: 오늘의 한마디는 "공유하기"
                    Label(isOneLiner ? AppLanguage.shared.s("공유하기", "Share")
                                     : AppLanguage.shared.s("합성하기", "Export Video"),
                          systemImage: isOneLiner ? "square.and.arrow.up" : "film")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
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
            if isOneLiner && isBatchExporting {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.violet)
                    Text(AppLanguage.shared.s("저장 중...", "Saving..."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else if isOneLiner && template == .story && !oneLinerVM.storyPhotoUUIDs.isEmpty {
                // 사진 연결 OneLiner: 문구 있는 사진 수 기준 저장 버튼
                // · 2장 이상: "N장 저장" / 1장: "저장" / 0장: 비활성
                let count = linkedOneLinerPhotoCount
                let btnLabel = count >= 2
                    ? AppLanguage.shared.s("\(count)장 저장(사진첩)", "Save \(count) to Photos")
                    : AppLanguage.shared.s("저장(사진첩)", "Save to Photos")
                let btnIcon = count >= 2 ? "photo.on.rectangle.angled" : "square.and.arrow.down"
                Button { Task { await batchExportOneLinerCards() } } label: {
                    Label(btnLabel, systemImage: btnIcon)
                        .font(.headline)
                        .foregroundStyle(count == 0 ? Color.white.opacity(0.4) : .white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(count == 0 ? Theme.violet.opacity(0.35) : Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(count == 0)
            } else {
                let shareDisabled = isOneLiner && oneLinerVM.oneLinerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button { showShareSheet = true } label: {
                    Label(AppLanguage.shared.s("공유하기", "Share"), systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(shareDisabled ? Color.white.opacity(0.4) : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(shareDisabled ? Theme.violet.opacity(0.35) : Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(shareDisabled)
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(images: [img])
                }
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
            mood: bigNumberVM.bigNumberShowMood ? story?.mood : nil,
            memoText: bigNumberVM.bigNumberShowMemo && !(story?.memo.isEmpty ?? true) ? story?.memo : nil,
            weatherText: condition?.weather?.formattedTemp,
            weatherIcon: condition?.weather?.systemIcon,
            date: activity.date,
            shoeName: displayShoeName
        )
    }

    private func buildPreview() {
        guard !previewPlayer.isBuilding else { return }
        Task {
            if oneLinerIsPhotoSlide {
                // 슬라이드: 쉬는날 카드와 동일하게 라이브 인메모리 레시피 우선 사용.
                // storyClipEditRecipes가 비어있으면(첫 실행·세션 재진입) SwiftData에서 복원.
                let photos = storyPhotos
                guard !photos.isEmpty else { return }
                let slideRecipes  = (oneLinerVM.storyClipEditRecipes.isEmpty || oneLinerVM.storyClipEditRecipes.count != photos.count)
                    ? makeStoryClipRecipes(isSlide: true)
                    : oneLinerVM.storyClipEditRecipes
                await previewPlayer.buildForPhotoSlides(
                    photos: photos, recipes: slideRecipes,
                    activityDate: activity.date, showDate: oneLinerVM.oneLinerShowDate,
                    metricLookup: oneLinerMetricLookup,
                    routeCoords: routeCoords,
                    hrSamples: shareHRSamples,
                    splits: detail?.splits ?? [],
                    chartSeriesData: chartSeriesData,
                    hrZones: detail?.hrZones ?? [],
                    intervalSegments: detail?.intervalSegments ?? [],
                    videoTitle: oneLinerVM.oneLinerVideoTitle, titleStyle: oneLinerVM.oneLinerTitleStyle)
            } else {
                // 영상: 실제 클립 재생 (export와 동일한 필믹 파이프라인 — resolvedAsset 사용)
                await previewPlayer.buildForVideoClips(
                    recipes: oneLinerVM.oneLinerClipRecipes,
                    activityDate: activity.date, showDate: oneLinerVM.oneLinerShowDate,
                    muteAudio: oneLinerVM.oneLinerMuteAudio,
                    metricChips: oneLinerActiveMetricChips,
                    metricLookup: oneLinerMetricLookup,
                    routeCoords: routeCoords,
                    hrSamples: shareHRSamples,
                    splits: detail?.splits ?? [],
                    chartSeriesData: chartSeriesData,
                    hrZones: detail?.hrZones ?? [],
                    intervalSegments: detail?.intervalSegments ?? [],
                    videoTitle: oneLinerVM.oneLinerVideoTitle, titleStyle: oneLinerVM.oneLinerTitleStyle)
            }
            previewPlayer.play()
        }
    }

    private func presentShareSheet(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = scene.keyWindow?.rootViewController else { return }
        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }
        topVC.present(activityVC, animated: true)
    }

    @MainActor
    private func exportVideo() async {
        guard !isExportingVideo else { return }
        isExportingVideo = true
        exportedVideoFile = nil

        // ── OneLiner 슬라이드 (storyPhotos 기반) ────────────────────────────
        if isOneLiner, oneLinerIsPhotoSlide {
            let photos = storyPhotos
            guard !photos.isEmpty else { isExportingVideo = false; return }
            do {
                // 편집된 문구·스타일 — 라이브 인메모리 우선, 없으면 SwiftData 복원
                let slideRecipes = (oneLinerVM.storyClipEditRecipes.isEmpty || oneLinerVM.storyClipEditRecipes.count != photos.count)
                    ? makeStoryClipRecipes(isSlide: true)
                    : oneLinerVM.storyClipEditRecipes
                let out = try await PhotoSlideComposition.exportSlideWithText(
                    photos: photos, recipes: slideRecipes,
                    fontChoice: oneLinerVM.oneLinerFont, textColor: oneLinerVM.oneLinerColor,
                    position: oneLinerVM.oneLinerPosition,
                    activityDate: activity.date, showDate: oneLinerVM.oneLinerShowDate,
                    metricLookup: oneLinerMetricLookup,
                    routeCoords: routeCoords,
                    hrSamples: shareHRSamples,
                    splits: detail?.splits ?? [],
                    chartSeriesData: chartSeriesData,
                    hrZones: detail?.hrZones ?? [],
                    intervalSegments: detail?.intervalSegments ?? [],
                    videoTitle: oneLinerVM.oneLinerVideoTitle, titleStyle: oneLinerVM.oneLinerTitleStyle)
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } catch { /* fall through */ }
            isExportingVideo = false
            return
        }

        // ── OneLiner multi-clip path (영상, running day) ────────────────────
        if isOneLiner, !oneLinerVM.oneLinerClipRecipes.isEmpty {
            do {
                var recipes = oneLinerVM.oneLinerClipRecipes
                // URL이 없는 클립은 resolvedAsset이나 assetIdentifier로 재해석
                for i in recipes.indices {
                    guard !FileManager.default.fileExists(atPath: recipes[i].url.path) else { continue }
                    if recipes[i].resolvedAsset != nil { continue }
                    if let assetID = recipes[i].assetIdentifier {
                        recipes[i].resolvedAsset = try await MultiClipComposition.resolveAVAsset(assetID: assetID)
                    }
                }
                let chips   = oneLinerActiveMetricChips
                // resolvedAsset이 있으면 반드시 composeAndExport 경로 사용 (URL 직접 사용 금지)
                let hasResolvedAssets = recipes.contains { $0.resolvedAsset != nil }
                let needsCompose = recipes.count > 1 || recipes.contains { $0.isTrimmed }
                    || recipes.contains { abs($0.speed - 1.0) > 0.01 } || hasResolvedAssets
                let exportSrc: URL
                var cleanup: URL? = nil
                if needsCompose {
                    let (composed, _) = try await MultiClipComposition.composeAndExport(
                        recipes: recipes, muteAudio: oneLinerVM.oneLinerMuteAudio)
                    exportSrc = composed; cleanup = composed
                } else {
                    exportSrc = recipes[0].url
                }
                defer { cleanup.map { try? FileManager.default.removeItem(at: $0) } }
                let isMuted = oneLinerVM.oneLinerMuteAudio
                let out = try await VideoExportService.exportOneLinerClipBoundVideo(
                    sourceURL: exportSrc, recipes: recipes,
                    fontChoice: oneLinerVM.oneLinerFont, textColor: oneLinerVM.oneLinerColor,
                    position: oneLinerVM.oneLinerPosition,
                    activityDate: activity.date, showDate: oneLinerVM.oneLinerShowDate,
                    muteAudio: isMuted, metricChips: chips,
                    metricLookup: oneLinerMetricLookup,
                    routeCoords: routeCoords,
                    hrSamples: shareHRSamples,
                    splits: detail?.splits ?? [],
                    hrZones: detail?.hrZones ?? [],
                    intervalSegments: detail?.intervalSegments ?? [],
                    chartSeriesData: chartSeriesData,
                    videoTitle: oneLinerVM.oneLinerVideoTitle, titleStyle: oneLinerVM.oneLinerTitleStyle)
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } catch {
                videoExportError = AppLanguage.shared.s(
                    "내보내기 중 오류가 발생했습니다: \(error.localizedDescription)",
                    "Export error: \(error.localizedDescription)")
                showVideoExportError = true
            }
            isExportingVideo = false
            return
        }

        // ── Placeable 슬라이드 (storyPhotos 기반 사진 슬라이드 영상) ──────────
        if isPlaceable, template == .slide {
            let photos = storyPhotos
            guard !photos.isEmpty else { isExportingVideo = false; return }
            do {
                let overlay = makePlaceableDataOverlay()
                let recipes = makePlaceableSlideRecipes(for: photos)
                let out = try await PhotoSlideComposition.exportSlideWithText(
                    photos: photos, recipes: recipes,
                    fontChoice: placeableVM.placeableStoryFont, textColor: placeableVM.placeableStoryColor,
                    position: placeableVM.placeableStoryPosition,
                    activityDate: activity.date, showDate: false,
                    metricLookup: [:], routeCoords: [],
                    hrSamples: [], splits: [], chartSeriesData: [:],
                    hrZones: [], intervalSegments: [],
                    videoTitle: "", titleStyle: OneLinerTitleStyle(),
                    dataOverlayImage: overlay)
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } catch {
                videoExportError = AppLanguage.shared.s(
                    "내보내기 중 오류가 발생했습니다: \(error.localizedDescription)",
                    "Export error: \(error.localizedDescription)")
                showVideoExportError = true
            }
            isExportingVideo = false
            return
        }

        // ── Placeable 영상 합성 (sourceVideoURL 불필요 — 클립별 URL 직접 해석) ──
        if isPlaceable {
            guard !placeableVM.placeableClipRecipes.isEmpty else { isExportingVideo = false; return }

            // PlaceableCard overlay: 로고 상단 7.5%, 데이터·날짜 하단 7.5% 배치
            let scale: CGFloat = 216.0 / PlaceableCard.cardWidth  // 0.72
            let scaledH = PlaceableCard.cardHeight * scale          // ~270pt

            // 정적 오버레이: 그라디언트 + PlaceableCard 데이터 패널 (문구·워드마크 제외)
            // 워드마크는 textLayer(buildClipTextContentLayer)가 처리하므로 여기서는 렌더링하지 않음.
            let staticOverlayContent = ZStack {
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: 216, height: 24).frame(width: 216, height: 384, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    .frame(width: 216, height: 24).frame(width: 216, height: 384, alignment: .bottom)
                PlaceableCard(
                    activity: activity, detail: detail,
                    routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                    photo: nil, date: activity.date,
                    metricsPosition: placeableVM.placeableMetricsPosition, accent: placeableVM.placeableAccent,
                    showBackground: false, showWordmark: false,
                    shoeName: displayShoeName, weather: condition?.weather,
                    size: placeableVM.placeableSize, layout: placeableVM.placeableLayout,
                    horizTextRow: placeableVM.placeableHorizTextRow, horizRoutePos: placeableVM.placeableHorizRoutePos
                )
                .frame(width: PlaceableCard.cardWidth, height: PlaceableCard.cardHeight)
                .scaleEffect(scale, anchor: .center)
                .frame(width: 216, height: scaledH)
                .padding(.bottom, 384 * 0.03)
                .frame(width: 216, height: 384, alignment: .bottom)
            }
            .frame(width: 216, height: 384)
            let staticRenderer = ImageRenderer(content: staticOverlayContent)
            staticRenderer.scale = 5.0
            let staticOverlay = staticRenderer.uiImage

            // 문구 텍스트 safe zone — 내보내기 좌표계(1080×1920 px) 기준
            // vScale = 1080/300 = 3.6 (카드 pt → 내보내기 px 변환비)
            let exportVScale: CGFloat = VideoExportService.targetSize.width / PlaceableCard.cardWidth
            let overlayBottomPadPx:   CGFloat = 384 * 0.03 * 5.0  // 오버레이 하단 여백 57.5px
            let safeBotPx = max(CardVisual.videoSafeBottom,
                                overlayBottomPadPx + placeableVM.storyBottomReserved * exportVScale)
            let safeTopPx = max(CardVisual.videoSafeTop,
                                overlayBottomPadPx + placeableVM.storyTopReserved    * exportVScale)

            // 클립별 오버레이 적용 후 연결
            // URL 해석 우선순위: 임시파일(PHPicker) → resolvedAsset(PHImageManager) → assetIdentifier 재해석
            var processedURLs: [URL] = []
            for recipe in placeableVM.placeableClipRecipes {
                var srcURL: URL = recipe.url
                if !FileManager.default.fileExists(atPath: recipe.url.path) {
                    if let urlAsset = recipe.resolvedAsset as? AVURLAsset {
                        srcURL = urlAsset.url
                    } else if let assetID = recipe.assetIdentifier,
                              let resolved = try? await MultiClipComposition.resolveAVAsset(assetID: assetID),
                              let urlAsset = resolved as? AVURLAsset {
                        srcURL = urlAsset.url
                    } else {
                        continue
                    }
                }
                // 클립 길이 = 트림 구간 / 배속
                let clipDur = recipe.trimmedDuration / max(0.1, recipe.speed)
                // 문구 애니메이션 CALayer — 빈 text도 레이어 생성(내용 없음으로 처리)
                let textLayer = VideoExportService.buildClipTextContentLayer(
                    recipes: [recipe],
                    renderSize: VideoExportService.targetSize,
                    totalDuration: clipDur,
                    activityDate: activity.date,
                    showDate: false,
                    safeTopOverride: safeTopPx,
                    safeBotOverride: safeBotPx)
                if let processed = try? await VideoExportService.exportPlaceableClipAnimated(
                    sourceURL: srcURL,
                    staticOverlay: staticOverlay,
                    textLayer: textLayer,
                    trimStart: recipe.trimStart, trimEnd: recipe.trimEnd,
                    muteAudio: placeableVM.placeableMuteAudio, speed: recipe.speed) {
                    processedURLs.append(processed)
                }
            }
            let exportedURL: URL?
            if processedURLs.count > 1 {
                exportedURL = try? await VideoExportService.concatenateURLs(processedURLs)
            } else {
                exportedURL = processedURLs.first
            }
            if let out = exportedURL {
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } else {
                videoExportError = AppLanguage.shared.s("영상 합성에 실패했습니다.", "Video export failed.")
                showVideoExportError = true
            }
            isExportingVideo = false
            return
        }

        // ── Athletic 멀티 클립 합성 (athleticVM.athleticClipRecipes 기반) ──────────────
        if !isOneLiner, !isPlaceable, !isBigNumber, template == .video, !athleticVM.athleticClipRecipes.isEmpty {
            let km = activity.distance / 1000
            let distStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
            // 미리보기와 동일한 9:16 비율(216×384pt)로 오버레이 렌더링
            // topInset/bottomInset = 5% (384 * 0.05 = 19.2pt) → 미리보기(375 * 0.05 = 18.75pt)와 동일 비율
            let exportH: CGFloat = 384
            let exportInset: CGFloat = exportH * 0.05
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
                weather: condition?.weather,
                shoeName: displayShoeName,
                scale: 216.0 / 300.0,
                topInset: exportInset,
                bottomInset: exportInset
            )
            .frame(width: 216, height: exportH)
            let overlayRenderer = ImageRenderer(content: overlayView)
            overlayRenderer.scale = 5.0
            guard let overlayImage = overlayRenderer.uiImage else {
                isExportingVideo = false; return
            }
            var processedURLs: [URL] = []
            for recipe in athleticVM.athleticClipRecipes {
                var srcURL = recipe.url
                if !FileManager.default.fileExists(atPath: srcURL.path) {
                    if let urlAsset = recipe.resolvedAsset as? AVURLAsset {
                        srcURL = urlAsset.url
                    } else if let assetID = recipe.assetIdentifier,
                              let resolved = try? await MultiClipComposition.resolveAVAsset(assetID: assetID),
                              let urlAsset = resolved as? AVURLAsset {
                        srcURL = urlAsset.url
                    } else {
                        continue
                    }
                }
                if let u = try? await VideoExportService.exportClipWithOverlay(
                    sourceURL: srcURL, overlay: overlayImage,
                    trimStart: recipe.trimStart, trimEnd: recipe.trimEnd,
                    muteAudio: athleticVM.athleticMuted) {
                    processedURLs.append(u)
                }
            }
            let exportedURL: URL?
            if processedURLs.count > 1 {
                exportedURL = try? await VideoExportService.concatenateURLs(processedURLs)
            } else {
                exportedURL = processedURLs.first
            }
            if let out = exportedURL {
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } else {
                videoExportError = AppLanguage.shared.s("영상 합성에 실패했습니다.", "Video export failed.")
                showVideoExportError = true
            }
            isExportingVideo = false
            return
        }

        // ── Single-source typing path (existing) ────────────────────────────
        guard let url = sourceVideoURL else { isExportingVideo = false; return }

        if isOneLiner {
            // Multi-slot mode (3+ slots = 2+ pages): group into pages of 2 and use multi-page export
            let filledSlots = oneLinerVM.oneLinerVideoSlotTexts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if oneLinerVM.oneLinerVideoSlotCount >= 3 && filledSlots.contains(where: { !$0.isEmpty }) {
                var pages: [[String]] = []
                var i = 0
                while i < filledSlots.count {
                    let s1 = filledSlots[i]
                    let s2 = i + 1 < filledSlots.count ? filledSlots[i + 1] : ""
                    let pair = [s1, s2].filter { !$0.isEmpty }
                    if !pair.isEmpty { pages.append(pair) }
                    i += 2
                }
                if pages.count > 1 {
                    if let out = try? await VideoExportService.exportOneLinerMultiPageVideo(
                        sourceURL: url,
                        pages: pages,
                        fontChoice: oneLinerVM.oneLinerFont,
                        textColor: oneLinerVM.oneLinerColor,
                        position: oneLinerVM.oneLinerPosition,
                        activityDate: activity.date,
                        showDate: oneLinerVM.oneLinerShowDate) {
                        exportedVideoFile = SharableVideoFile(url: out)
                    }
                    isExportingVideo = false
                    return
                }
            }
            // Single-text fallback: 2 slots or fewer, or all content resolves to 1 page
            if let out = try? await VideoExportService.exportOneLinerTypingVideo(
                sourceURL: url,
                text: oneLinerVM.oneLinerText,
                fontChoice: oneLinerVM.oneLinerFont,
                textColor: oneLinerVM.oneLinerColor,
                position: oneLinerVM.oneLinerPosition,
                activityDate: activity.date,
                showDate: oneLinerVM.oneLinerShowDate) {
                exportedVideoFile = SharableVideoFile(url: out)
            }
            isExportingVideo = false
            return
        }

        // ── BigNumber 멀티 클립 합성 (athleticVM.athleticClipRecipes 공유) ──────────────
        if isBigNumber, !athleticVM.athleticClipRecipes.isEmpty {
            let overlayRenderer = ImageRenderer(content:
                makeBigNumberOverlayView().frame(width: 216, height: 384)
            )
            overlayRenderer.scale = 5.0
            guard let overlayImage = overlayRenderer.uiImage else {
                isExportingVideo = false; return
            }
            var processedURLs: [URL] = []
            for recipe in athleticVM.athleticClipRecipes {
                var srcURL = recipe.url
                if !FileManager.default.fileExists(atPath: srcURL.path) {
                    if let urlAsset = recipe.resolvedAsset as? AVURLAsset {
                        srcURL = urlAsset.url
                    } else if let assetID = recipe.assetIdentifier,
                              let resolved = try? await MultiClipComposition.resolveAVAsset(assetID: assetID),
                              let urlAsset = resolved as? AVURLAsset {
                        srcURL = urlAsset.url
                    } else {
                        continue
                    }
                }
                if let u = try? await VideoExportService.exportClipWithOverlay(
                    sourceURL: srcURL, overlay: overlayImage,
                    trimStart: recipe.trimStart, trimEnd: recipe.trimEnd,
                    muteAudio: athleticVM.athleticMuted) {
                    processedURLs.append(u)
                }
            }
            let exportedURL: URL?
            if processedURLs.count > 1 {
                exportedURL = try? await VideoExportService.concatenateURLs(processedURLs)
            } else {
                exportedURL = processedURLs.first
            }
            if let out = exportedURL {
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } else {
                videoExportError = AppLanguage.shared.s("영상 합성에 실패했습니다.", "Video export failed.")
                showVideoExportError = true
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
            weather: condition?.weather,
            shoeName: displayShoeName,
            scale: 216.0 / 300.0   // proportional to 300pt preview (= 0.72)
        )
        .frame(width: 216, height: 384)

        let overlayRenderer = ImageRenderer(content: overlayView)
        overlayRenderer.scale = 5.0   // 216 × 5 = 1080 px, 384 × 5 = 1920 px

        guard let overlayImage = overlayRenderer.uiImage else {
            isExportingVideo = false
            return
        }

        let trimStart = athleticVM.athleticClipRecipes.first?.trimStart ?? 0
        let trimEnd   = athleticVM.athleticClipRecipes.first?.trimEnd
        if let outputURL = try? await VideoExportService.exportVideo(
            sourceURL: url, overlay: overlayImage,
            startTime: trimStart, endTime: trimEnd) {
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
                url = try await RouteVideoExportService.exportBigNumberFast(
                    snapshot: snap,
                    snapshotPoints: routeSnapshotPoints,
                    activity: activity,
                    detail: detail,
                    heroMetric: heroMetric,
                    mood: bigNumberVM.bigNumberShowMood ? story?.mood : nil,
                    memoText: bigNumberVM.bigNumberShowMemo && !(story?.memo.isEmpty ?? true) ? story?.memo : nil,
                    weatherText: condition?.weather?.formattedTemp,
                    weatherIcon: condition?.weather?.systemIcon,
                    date: activity.date,
                    shoeName: displayShoeName,
                    totalDistanceM: activity.distance,
                    hrSamplesForRoute: shareHRSamples,
                    routeWorkoutDuration: activity.duration,
                    showHRGradient: showHRGradientForRoute,
                    miniMeImage: activeMiniMeImage,
                    accent: bigNumberVM.bigNumberAccent,
                    progressHandler: { p in routeVideoProgress = p }
                )
            } else {
                url = try await RouteVideoExportService.exportFast(
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
                    shoeName: displayShoeName,
                    chartPanel: cardPanel,
                    chartSplits: detail?.splits ?? [],
                    chartHRSamples: shareHRSamples,
                    chartHRZones: detail?.hrZones ?? [],
                    chartWorkoutSeries: shareWorkoutSeries,
                    chartIntervalSegments: detail?.intervalSegments ?? [],
                    totalDistanceM: activity.distance,
                    hrSamplesForRoute: shareHRSamples,
                    routeWorkoutDuration: activity.duration,
                    showHRGradient: showHRGradientForRoute,
                    progressHandler: { p in routeVideoProgress = p }
                )
            }
            routeVideoFile = SharableVideoFile(url: url)
        } catch { }
        isExportingRouteVideo = false
    }

    @MainActor
    private func loadECGWaveforms() async {
        guard let mgr = manager else { ecgVM.ecgDataAvailable = false; return }
        async let pace = ECGWaveform.fromPace(activity: activity, using: mgr)
        async let hr   = ECGWaveform.fromHeartRate(activity: activity, using: mgr)
        let p = await pace
        let h = await hr
        ecgVM.paceWaveform      = p
        ecgVM.hrWaveform        = h
        ecgVM.ecgDataAvailable  = (p != nil || h != nil)
        if ecgVM.paceWaveform == nil, ecgVM.hrWaveform != nil { ecgVM.ecgShowPace = false }
        if ecgVM.ecgDataAvailable == false && cardIndex == 5 { withAnimation { cardIndex = 4 } }
        if isECG { await renderCard(showSpinner: false) }
    }

    // Extracted from .task {} to keep the closure trivial and avoid type-checker timeouts.
    @MainActor
    private func onAppear() async {
        // Restore selected photo from stored data on re-entry (e.g. after app restart).
        // Without this, selectedPhoto stays nil and the legacy all-cards branch fires.
        if !storyPhotos.isEmpty {
            // 사진 선택을 지원하는 카드 인덱스: Placeable(0), OneLiner(1), Athletic(2), BigNumber(3)
            for i in [0, 1, 2, 3] where cardPhotoIndex[i] == nil {
                cardPhotoIndex[i] = 0
            }
        }
        // Load stable photo UUIDs from SwiftData (used by OneLinerEntry cross-references)
        if oneLinerVM.storyPhotoUUIDs.isEmpty {
            oneLinerVM.storyPhotoUUIDs = story?.sortedPhotoUUIDs ?? []
        }
        // Pre-populate oneLinerVM.cachedStoryRecipes from disk so preview shows saved state immediately,
        // avoiding a visible flash before the first edit dismiss populates the cache.
        if oneLinerVM.cachedStoryRecipes.isEmpty, !oneLinerVM.storyPhotoUUIDs.isEmpty {
            oneLinerVM.cachedStoryRecipes = makeStoryClipRecipes()
        }
        // Auto-select first available panel when no route
        if routeCoords.isEmpty && cardPanel == .map {
            let first = CardChartPanel.allCases.first { isChartPanelAvailable($0) }
            cardPanel = first ?? .splits
        }
        deduplicateOneLinerEntries()
        loadOneLinerSettings()
        loadPlaceableStoryOverlay()
        if isPlaceable, template == .video { loadPlaceableVideoClips() }
        await loadHighQualityPhotos()
        // Placeable 슬라이드 프리뷰 미리 빌드 (스토리→슬라이드 전환 즉시화)
        // onChange(of: storyPhotos.count)는 초기값엔 발화 안 하므로 여기서 별도 처리.
        // previewPlayer는 영상·슬라이드가 공유 — 슬라이드 템플릿일 때만 빌드.
        if isPlaceable, template == .slide, !storyPhotos.isEmpty, !previewPlayer.isReady {
            let photos = storyPhotos
            Task {
                let overlay = makePlaceableDataOverlay()
                let recipes = makePlaceableSlideRecipes(for: photos)
                await previewPlayer.buildForPhotoSlides(photos: photos, recipes: recipes,
                    activityDate: activity.date, showDate: false,
                    dataOverlayImage: overlay)
            }
        }
        // HR 시계열 미리 로드 — 공유 카드 경로 그라데이션용 (패널 무관)
        if activity.avgHeartRate != nil, let mgr = manager, shareHRSamples.isEmpty {
            shareHRSamples = await mgr.fetchHRTimeSeries(for: activity.id)
        }
        // 차트 시계열 fetch (케이던스·지면접촉·보폭·수직진폭·파워 + 고도)
        if chartSeriesData.isEmpty, let mgr = manager {
            async let cadence = mgr.fetchCadenceTimeSeries(for: activity.id)
            async let stride  = mgr.fetchWorkoutTimeSeries(for: activity.id, identifier: .runningStrideLength, unit: .meter())
            async let vo      = mgr.fetchWorkoutTimeSeries(for: activity.id, identifier: .runningVerticalOscillation, unit: .meterUnit(with: .centi))
            var newData: [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:]
            let (cad, strRes, voRes) = await (cadence, stride, vo)
            if cad.count    >= 2 { newData[.cadence]             = cad    }
            if strRes.count >= 2 { newData[.strideLength]        = strRes }
            if voRes.count  >= 2 { newData[.verticalOscillation] = voRes  }
            // 고도: ActivityDetail에서 바로 가져옴
            if let alt = detail?.altitudeTimeProfile, alt.count >= 2 {
                newData[.elevation] = alt.map { (offset: $0.offset, value: $0.altitude) }
            }
            chartSeriesData = newData
        }
        await renderCard()
        await loadECGWaveforms()
        await loadTicketDepartureName()
    }

    private func loadTicketDepartureName() async {
        guard let coord = routeCoords.first else { return }
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let geocoder = CLGeocoder()
        guard let placemarks = try? await geocoder.reverseGeocodeLocation(location),
              let pm = placemarks.first else { return }
        let name = pm.subLocality ?? pm.locality ?? pm.administrativeArea ?? "RUN"
        ticketVM.ticketDepartureName = name
        if isTicket { await renderCard(showSpinner: false) }
    }

    // MARK: - OneLiner persistence (SwiftData, per media ref)

    /// mediaRef key for the currently active OneLiner entry.
    private func computeOneLinerMediaRef() -> String? {
        guard isOneLiner else { return nil }
        if template == .video, let assetID = videoPickerItem?.itemIdentifier {
            return "video:\(assetID)"
        }
        if template == .story {
            let idx = cardPhotoIndex[1] ?? 0
            if idx < oneLinerVM.storyPhotoUUIDs.count { return "photo:\(oneLinerVM.storyPhotoUUIDs[idx])" }
        }
        return nil   // gradient
    }

    private func findOrCreateOneLinerEntry(for mediaRef: String?) -> OneLinerEntry {
        if let existing = oneLinerEntries.first(where: { $0.mediaRef == mediaRef }) {
            return existing
        }
        let entry = OneLinerEntry(workoutID: activity.id.uuidString, mediaRef: mediaRef)
        modelContext.insert(entry)
        return entry
    }

    // MARK: - OneLiner 클립 저장/복원 (영상 템플릿 전용)

    private var oneLinerClipsEntry: OneLinerEntry? {
        oneLinerEntries.first { $0.mediaRef == "oneliner:clips" }
    }

    private func saveOneLinerClipRecipes() {
        let validRecipes = oneLinerVM.oneLinerClipRecipes.filter {
            $0.assetIdentifier != nil || $0.clipVideoRef != nil || $0.storedPhotoRef != nil
        }
        if validRecipes.isEmpty {
            if let entry = oneLinerClipsEntry {
                modelContext.delete(entry)
                try? modelContext.save()
            }
            return
        }
        let descs = validRecipes.map { r in
            SavedClipDescriptor(
                assetID: r.assetIdentifier, clipVideoRef: r.clipVideoRef,
                photoRef: r.storedPhotoRef, thumbRef: r.thumbRef,
                trimStart: r.trimStart, trimEnd: r.trimEnd, fullDuration: r.fullDuration,
                lines: r.lines,
                fontID: r.fontChoice.rawValue, colorID: r.textColor.rawValue,
                anchorIdx: CardPosition.allCases.firstIndex(of: r.position),
                sizeID: r.sizeLevel.rawValue,
                effectID: "\(r.appearanceMode.rawValue)|\(r.decorEffect.rawValue)|B\(r.hasBorder ? 1 : 0)P\(r.plateOn ? 1 : 0)|\(r.flyDirection.rawValue)",
                plateColorID: r.plateColorPreset.rawValue, speed: r.speed,
                metricPace: r.metricPace, metricDistance: r.metricDistance, metricTime: r.metricTime,
                metricHeartRate: r.metricHeartRate,
                pdtAnchorIdx: CardPosition.allCases.firstIndex(of: r.pdtPosition),
                showRoute: r.showRoute,
                routeAnchorIdx: CardPosition.allCases.firstIndex(of: r.routePosition),
                showHRChart: r.showHRChart,
                chartTypeID:  r.chartOverlayType == .none ? nil : r.chartOverlayType.rawValue,
                pdtSizeID2:   r.pdtSizeLevel.rawValue,
                dataEffectID: r.dataAppearanceMode.rawValue)
        }
        let saved = SavedRecipeSet(
            isPhotoSlide: false, muteAudio: oneLinerVM.oneLinerMuteAudio, clips: descs,
            videoTitle: oneLinerVM.oneLinerVideoTitle,
            titleAnchorIdx: CardPosition.allCases.firstIndex(of: oneLinerVM.oneLinerTitleStyle.position),
            titleFontID: oneLinerVM.oneLinerTitleStyle.fontChoice.rawValue,
            titleColorID: oneLinerVM.oneLinerTitleStyle.textColor.rawValue,
            titleSizeID: oneLinerVM.oneLinerTitleStyle.sizeLevel.rawValue,
            titleOutline: oneLinerVM.oneLinerTitleStyle.outline)
        guard let data = try? JSONEncoder().encode(saved),
              let json = String(data: data, encoding: .utf8) else { return }
        let payload = "v4recipes\n" + json
        if let existing = oneLinerClipsEntry {
            existing.text = payload
        } else {
            let entry = OneLinerEntry(workoutID: activity.id.uuidString, mediaRef: "oneliner:clips")
            entry.text = payload
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }

    private func loadOneLinerClipRecipes() {
        guard let entry = oneLinerClipsEntry,
              entry.text.hasPrefix("v4recipes\n"),
              let data = entry.text.dropFirst("v4recipes\n".count).data(using: .utf8),
              let saved = try? JSONDecoder().decode(SavedRecipeSet.self, from: data),
              !saved.clips.isEmpty else { return }
        oneLinerVM.oneLinerMuteAudio  = saved.muteAudio
        oneLinerVM.oneLinerVideoTitle = saved.videoTitle
        var style = OneLinerTitleStyle()
        if let idx = saved.titleAnchorIdx, CardPosition.allCases.indices.contains(idx) {
            style.position = CardPosition.allCases[idx]
        }
        if let fid = saved.titleFontID  { style.fontChoice = OneLinerFont.migrate(fid) }
        if let cid = saved.titleColorID { style.textColor  = OneLinerTextColor(rawValue: cid) ?? .white }
        if let sid = saved.titleSizeID  { style.sizeLevel  = TextSizeLevel(rawValue: sid) ?? .medium }
        style.outline = saved.titleOutline
        oneLinerVM.oneLinerTitleStyle = style
        var restored: [ClipRecipe] = []
        for desc in saved.clips {
            let thumb: UIImage?
            if let pr = desc.photoRef { thumb = OneLinerPhotoStore.load(mediaRef: pr) }
            else if let tr = desc.thumbRef { thumb = ClipThumbStore.load(ref: tr) }
            else { thumb = nil }
            let recipeURL: URL
            if let ref = desc.clipVideoRef,
               let stableURL = ClipVideoStore.fileURL(ref: ref),
               FileManager.default.fileExists(atPath: stableURL.path) {
                recipeURL = stableURL
            } else {
                recipeURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mimo_placeholder_\(UUID().uuidString)")
            }
            var recipe = ClipRecipe(url: recipeURL, fullDuration: desc.fullDuration, thumbnail: thumb)
            recipe.trimStart       = desc.trimStart
            recipe.trimEnd         = desc.trimEnd
            recipe.lines           = desc.lines.map { line in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("v3slide") || t.hasPrefix("v3recipes")
                    || t.hasPrefix("v4recipes") || t.hasPrefix("v2clips")
                    || (t.count > 30 && t.hasPrefix("{") && t.hasSuffix("}")) { return "" }
                return line
            }
            recipe.assetIdentifier = desc.assetID
            recipe.clipVideoRef    = desc.clipVideoRef
            recipe.storedPhotoRef  = desc.photoRef
            recipe.thumbRef        = desc.thumbRef
            recipe.fontChoice      = OneLinerFont.migrate(desc.fontID)
            recipe.textColor       = desc.colorID.flatMap { OneLinerTextColor(rawValue: $0) } ?? oneLinerVM.oneLinerColor
            if let idx = desc.anchorIdx, CardPosition.allCases.indices.contains(idx) {
                recipe.position = CardPosition.allCases[idx]
            } else {
                recipe.position = oneLinerVM.oneLinerPosition
            }
            recipe.sizeLevel = desc.sizeID.flatMap { TextSizeLevel(rawValue: $0) } ?? .medium
            if let eid = desc.effectID, eid.contains("|") {
                let parts = eid.split(separator: "|", maxSplits: 3).map(String.init)
                recipe.appearanceMode = parts.count > 0 ? (AppearanceMode(rawValue: parts[0]) ?? .typing) : .typing
                recipe.decorEffect    = parts.count > 1 ? (DecorEffect(rawValue: parts[1]) ?? .none) : .none
                if parts.count > 2 {
                    let r = parts[2]
                    if r.hasPrefix("B") {
                        recipe.hasBorder = r.contains("B1")
                        recipe.plateOn   = r.contains("P1")
                    } else {
                        switch r {
                        case "1", "outline": recipe.hasBorder = true;  recipe.plateOn = false
                        case "plate":        recipe.hasBorder = false; recipe.plateOn = true
                        default:             recipe.hasBorder = false; recipe.plateOn = false
                        }
                    }
                }
                recipe.flyDirection = parts.count > 3 ? (FlyInDirection(rawValue: parts[3]) ?? .trailing) : .trailing
            } else {
                recipe.appearanceMode = .typing
                recipe.decorEffect    = .none
                recipe.hasBorder      = false
                recipe.plateOn        = false
            }
            recipe.plateColorPreset = desc.plateColorID.flatMap { PlateColorPreset(rawValue: $0) } ?? .blackWhite
            recipe.speed            = desc.speed
            recipe.metricPace       = desc.metricPace
            recipe.metricDistance   = desc.metricDistance
            recipe.metricTime       = desc.metricTime
            recipe.metricHeartRate  = desc.metricHeartRate
            if let a = desc.pdtAnchorIdx, CardPosition.allCases.indices.contains(a) {
                recipe.pdtPosition = CardPosition.allCases[a]
            }
            if let ct = desc.chartTypeID, let type = ChartOverlayType(rawValue: ct) {
                recipe.chartOverlayType = type
            } else if desc.showRoute {
                recipe.chartOverlayType = .route
            } else if desc.showHRChart {
                recipe.chartOverlayType = .hrChart
            }
            if let a = desc.routeAnchorIdx, CardPosition.allCases.indices.contains(a) {
                recipe.routePosition = CardPosition.allCases[a]
            }
            if let ps = desc.pdtSizeID2, let size = TextSizeLevel(rawValue: ps) {
                recipe.pdtSizeLevel = size
            }
            if let de = desc.dataEffectID, let mode = AppearanceMode(rawValue: de) {
                recipe.dataAppearanceMode = mode
            }
            restored.append(recipe)
        }
        oneLinerVM.oneLinerVideoModeRecipes = restored
        if template == .video { oneLinerVM.oneLinerClipRecipes = restored }
        // videoPreviewImage는 OneLiner 카드에서만 적용 — 다른 카드(Athletic 등)에 OneLiner 썸네일이 표시되는 버그 방지
        if isOneLiner, let firstThumb = restored.first?.thumbnail {
            videoPreviewImage = firstThumb
        }
    }

    private func syncOneLinerVideoBacking(from oldTemplate: ShareTemplate, to newTemplate: ShareTemplate) {
        guard isOneLiner else { return }
        // 비디오 템플릿을 벗어날 때: active clips → 백업, active 비움
        if oldTemplate == .video {
            oneLinerVM.oneLinerVideoModeRecipes = oneLinerVM.oneLinerClipRecipes
            oneLinerVM.oneLinerClipRecipes = []
        }
        // 비디오 템플릿으로 돌아올 때: 백업에서 복원 + 썸네일 갱신
        if newTemplate == .video {
            oneLinerVM.oneLinerClipRecipes = oneLinerVM.oneLinerVideoModeRecipes
            if let thumb = oneLinerVM.oneLinerVideoModeRecipes.first?.thumbnail {
                videoPreviewImage = thumb
            }
        }
    }

    private func syncUIFromEntry(_ entry: OneLinerEntry) {
        // v3slide\n 포맷(ClipTrimSheet 저장)이면 실제 텍스트와 스타일을 디코딩.
        // 그렇지 않으면 레거시 플레인텍스트 방식 유지.
        if entry.text.hasPrefix("v3slide\n"),
           let data = entry.text.dropFirst("v3slide\n".count).data(using: .utf8),
           let desc = try? JSONDecoder().decode(SavedClipDescriptor.self, from: data) {
            oneLinerVM.oneLinerText     = desc.lines.filter { line in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty || t.hasPrefix("v3slide") || t.hasPrefix("v3recipes")
                    || t.hasPrefix("v4recipes") || t.hasPrefix("v2clips")
                    || (t.count > 30 && t.hasPrefix("{") && t.hasSuffix("}")) { return false }
                return true
            }.joined(separator: "\n")
            oneLinerVM.oneLinerFont     = OneLinerFont.migrate(desc.fontID)
            oneLinerVM.oneLinerColor    = desc.colorID.flatMap { OneLinerTextColor(rawValue: $0) } ?? .white
            if let aIdx = desc.anchorIdx, CardPosition.allCases.indices.contains(aIdx) {
                oneLinerVM.oneLinerPosition = CardPosition.allCases[aIdx]
            }
        } else {
            oneLinerVM.oneLinerText     = entry.text
            oneLinerVM.oneLinerFont     = entry.font
            oneLinerVM.oneLinerColor    = entry.textColor
            oneLinerVM.oneLinerPosition = entry.position
        }
        oneLinerVM.oneLinerShowDate  = entry.showDate
    }

    private func loadOneLinerSettings() {
        migrateUserDefaultsOneLiner()
        let mediaRef = computeOneLinerMediaRef()
        if let entry = oneLinerEntries.first(where: { $0.mediaRef == mediaRef }) {
            syncUIFromEntry(entry)
            oneLinerVM.oneLinerPhAssetDeleted = !entry.isPHAssetAvailable
            // Video slot mode: split saved text back into individual slot fields
            if template == .video && oneLinerVM.oneLinerVideoSlotCount > 2 {
                let lines = entry.text.components(separatedBy: "\n")
                oneLinerVM.oneLinerVideoSlotTexts = (0..<oneLinerVM.oneLinerVideoSlotCount).map { i in
                    i < lines.count ? lines[i] : ""
                }
            }
        } else {
            oneLinerVM.oneLinerText = ""
            oneLinerVM.oneLinerPhAssetDeleted = false
            // 연재 연속성: 새 사진에 처음 문구를 쓸 때 폰트·색은 직전 entry 기본값으로.
            // 위치(9앵커)는 사진마다 독립 — 사진 구도가 다르므로 그대로 유지.
            if let latest = oneLinerEntries.last {
                oneLinerVM.oneLinerFont  = latest.font
                oneLinerVM.oneLinerColor = latest.textColor
            }
            // Video slot mode: clear all slot fields
            if template == .video {
                oneLinerVM.oneLinerVideoSlotTexts = Array(repeating: "", count: max(2, oneLinerVM.oneLinerVideoSlotCount))
            }
        }
        loadOneLinerClipRecipes()
    }

    // MARK: - Placeable story overlay persistence (UserDefaults, per-activity)

    private var psoPrefix: String { "pso_\(activity.id.uuidString)_" }

    /// Placeable 영상 미리보기를 로드한다.
    /// OneLiner 영상과 동일하게 buildVideoPreviewItem → AVSynchronizedLayer 경로 사용.
    /// 텍스트 애니메이션(타이핑·페이드·날아오기)이 CALayer 타임라인과 동기화된다.
    @MainActor
    private func loadPlaceablePreview() async {
        guard !placeableVM.placeableClipRecipes.isEmpty else {
            previewPlayer.invalidate()
            videoPreviewImage = nil
            sourceVideoURL = nil
            return
        }

        // 썸네일을 먼저 추출 → buildForVideoClips 빌드 중에도 첫 프레임이 즉시 표시됨
        if let thumb = await resolvedURL(for: placeableVM.placeableClipRecipes[0]) {
            sourceVideoURL = thumb
            if videoPreviewImage == nil {
                videoPreviewImage = await VideoExportService.firstFrame(of: thumb)
            }
        }

        // 재생 중에는 OneLinerPreviewView(CALayer)만 표시되고 SwiftUI 텍스트 오버레이가 없으므로
        // lines를 그대로 넘겨 페이드/날아오기/타이핑 애니메이션을 미리보기에서도 표시
        await previewPlayer.buildForVideoClips(
            recipes:      placeableVM.placeableClipRecipes,
            activityDate: activity.date,
            showDate:     false,
            muteAudio:    placeableVM.placeableMuteAudio
        )
    }

    private func fallbackToSingleClip() {
        Task { @MainActor in
            let idx = placeableVM.placeableClipRecipes.indices.contains(placeableVM.selectedPlaceableClipIndex)
                ? placeableVM.selectedPlaceableClipIndex : 0
            guard let srcURL = await resolvedURL(for: placeableVM.placeableClipRecipes[idx]) else { return }
            sourceVideoURL = srcURL
            videoPreviewImage = await VideoExportService.firstFrame(of: srcURL)
            // previewPlayer를 통한 단일 클립 폴백 빌드
            if placeableVM.placeableClipRecipes.indices.contains(idx) {
                await previewPlayer.buildForVideoClips(
                    recipes: [placeableVM.placeableClipRecipes[idx]], activityDate: activity.date, showDate: false)
            }
        }
    }

    /// recipe의 URL을 해석 — PHPicker 임시 → resolvedAsset → assetIdentifier 재해석
    private func resolvedURL(for r: ClipRecipe) async -> URL? {
        if FileManager.default.fileExists(atPath: r.url.path) { return r.url }
        if let ua = r.resolvedAsset as? AVURLAsset { return ua.url }
        if let aid = r.assetIdentifier,
           let av = try? await MultiClipComposition.resolveAVAsset(assetID: aid),
           let ua = av as? AVURLAsset { return ua.url }
        return nil
    }

    private func loadPlaceableStoryOverlay() {
        let ud = UserDefaults.standard
        let p  = psoPrefix
        // 사진별 문구 로드 (신규 JSON 배열 우선, 구버전 단일 text 폴백)
        if let data = ud.data(forKey: p + "textsArr"),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            placeableVM.placeableStoryTexts = Dictionary(uniqueKeysWithValues:
                arr.enumerated().compactMap { i, t in t.isEmpty ? nil : (i, t) })
        } else if let t = ud.string(forKey: p + "text"), !t.isEmpty {
            placeableVM.placeableStoryTexts = [0: t]
        }
        if let f = ud.string(forKey: p + "font"),  let fv = OneLinerFont(rawValue: f)    { placeableVM.placeableStoryFont     = fv }
        if let c = ud.string(forKey: p + "color"), let cv = OneLinerTextColor(rawValue: c) { placeableVM.placeableStoryColor  = cv }
        if let s = ud.string(forKey: p + "size"),   let sv = TextSizeLevel(rawValue: s)      { placeableVM.placeableStorySize        = sv }
        let posIdx = ud.integer(forKey: p + "pos")
        let posAll = Array(CardPosition.allCases)
        if posIdx >= 0, posIdx < posAll.count { placeableVM.placeableStoryPosition = posAll[posIdx] }
        if let bv = ud.object(forKey: p + "border") as? Bool { placeableVM.placeableStoryHasBorder = bv }
        if let pv = ud.object(forKey: p + "plate")  as? Bool { placeableVM.placeableStoryPlateOn   = pv }
        if let pr = ud.string(forKey: p + "platePreset"), let pv = PlateColorPreset(rawValue: pr) { placeableVM.placeableStoryPlatePreset = pv }
    }

    private func savePlaceableStoryOverlay() {
        let ud = UserDefaults.standard
        let p  = psoPrefix
        // 사진별 문구를 JSON 배열로 저장 ([String], 인덱스 = 사진 순서)
        let maxIdx = placeableVM.placeableStoryTexts.keys.max() ?? 0
        var arr = Array(repeating: "", count: maxIdx + 1)
        for (idx, text) in placeableVM.placeableStoryTexts where idx <= maxIdx { arr[idx] = text }
        if let data = try? JSONEncoder().encode(arr) { ud.set(data, forKey: p + "textsArr") }
        ud.set(placeableVM.placeableStoryFont.rawValue,               forKey: p + "font")
        ud.set(placeableVM.placeableStoryColor.rawValue,              forKey: p + "color")
        ud.set(placeableVM.placeableStorySize.rawValue,               forKey: p + "size")
        let posAll = Array(CardPosition.allCases)
        ud.set(posAll.firstIndex(of: placeableVM.placeableStoryPosition) ?? 0, forKey: p + "pos")
        ud.set(placeableVM.placeableStoryHasBorder,                   forKey: p + "border")
        ud.set(placeableVM.placeableStoryPlateOn,                     forKey: p + "plate")
        ud.set(placeableVM.placeableStoryPlatePreset.rawValue,        forKey: p + "platePreset")
    }

    // MARK: - Placeable video clip persistence (UserDefaults, per-activity)

    private var pvcPrefix: String { "pvc_\(activity.id.uuidString)_" }

    private func savePlaceableVideoClips() {
        let ud = UserDefaults.standard
        let p  = pvcPrefix
        let valid = placeableVM.placeableClipRecipes.filter { $0.assetIdentifier != nil || $0.clipVideoRef != nil }
        guard !valid.isEmpty else { ud.removeObject(forKey: p + "clips"); return }
        let descs = valid.map { r in
            SavedClipDescriptor(
                assetID: r.assetIdentifier, clipVideoRef: r.clipVideoRef,
                photoRef: nil, thumbRef: r.thumbRef,
                trimStart: r.trimStart, trimEnd: r.trimEnd, fullDuration: r.fullDuration,
                lines: r.lines,
                fontID: r.fontChoice.rawValue, colorID: r.textColor.rawValue,
                anchorIdx: CardPosition.allCases.firstIndex(of: r.position),
                sizeID: r.sizeLevel.rawValue,
                effectID: "\(r.appearanceMode.rawValue)|\(r.decorEffect.rawValue)|B\(r.hasBorder ? 1 : 0)P\(r.plateOn ? 1 : 0)|\(r.flyDirection.rawValue)",
                plateColorID: r.plateColorPreset.rawValue, speed: r.speed,
                metricPace: false, metricDistance: false,
                metricTime: false, metricHeartRate: false,
                pdtAnchorIdx: nil, showRoute: false, routeAnchorIdx: nil,
                showHRChart: false, chartTypeID: nil, pdtSizeID2: nil, dataEffectID: nil)
        }
        if let data = try? JSONEncoder().encode(descs) { ud.set(data, forKey: p + "clips") }
        ud.set(placeableVM.placeableMuteAudio, forKey: p + "mute")
    }

    /// Placeable 슬라이드용 ClipRecipe 배열 — 스토리 문구·스타일을 사진별로 매핑.
    private func makePlaceableSlideRecipes(for photos: [UIImage]) -> [ClipRecipe] {
        photos.enumerated().map { i, photo in
            var r = ClipRecipe(url: URL(fileURLWithPath: ""),
                               fullDuration: PhotoSlideComposition.placeableSlideDuration,
                               thumbnail: photo)
            r.lines            = [placeableVM.placeableStoryTexts[i] ?? ""]
            r.fontChoice       = placeableVM.placeableStoryFont
            r.textColor        = placeableVM.placeableStoryColor
            r.position         = placeableVM.placeableStoryPosition
            r.sizeLevel        = placeableVM.placeableStorySize
            r.hasBorder        = placeableVM.placeableStoryHasBorder
            r.plateOn          = placeableVM.placeableStoryPlateOn
            r.plateColorPreset = placeableVM.placeableStoryPlatePreset
            r.appearanceMode   = placeableVM.placeableSlideAppearance
            r.decorEffect      = placeableVM.placeableSlideAppearance == .fade ? placeableVM.slideDecorEffect : .none
            r.flyDirection     = placeableVM.slideFlyDirection
            return r
        }
    }

    private func applyAnimationToVideoClips() {
        for i in placeableVM.placeableClipRecipes.indices {
            placeableVM.placeableClipRecipes[i].appearanceMode = placeableVM.placeableSlideAppearance
            placeableVM.placeableClipRecipes[i].decorEffect    = placeableVM.placeableSlideAppearance == .fade ? placeableVM.slideDecorEffect : .none
            placeableVM.placeableClipRecipes[i].flyDirection   = placeableVM.slideFlyDirection
        }
    }

    /// 전역 문구 스타일(위치·폰트·색상·크기·테두리·음영판)을 영상 클립 레시피 전체에 동기화.
    /// 프리뷰는 전역 상태를 직접 쓰므로 이 함수 호출 후 프리뷰 = 출력이 일치.
    private func applyStyleToVideoClips() {
        guard isPlaceable, template == .video else { return }
        for i in placeableVM.placeableClipRecipes.indices {
            placeableVM.placeableClipRecipes[i].position        = placeableVM.placeableStoryPosition
            placeableVM.placeableClipRecipes[i].fontChoice       = placeableVM.placeableStoryFont
            placeableVM.placeableClipRecipes[i].textColor        = placeableVM.placeableStoryColor
            placeableVM.placeableClipRecipes[i].sizeLevel        = placeableVM.placeableStorySize
            placeableVM.placeableClipRecipes[i].hasBorder        = placeableVM.placeableStoryHasBorder
            placeableVM.placeableClipRecipes[i].plateOn          = placeableVM.placeableStoryPlateOn
            placeableVM.placeableClipRecipes[i].plateColorPreset = placeableVM.placeableStoryPlatePreset
        }
    }

    private func rebuildPlaceableSlidePreview() {
        guard isPlaceable, template == .slide, !storyPhotos.isEmpty else { return }
        let photos = storyPhotos
        Task {
            let overlay = makePlaceableDataOverlay()
            let recipes = makePlaceableSlideRecipes(for: photos)
            await previewPlayer.buildForPhotoSlides(
                photos: photos, recipes: recipes,
                activityDate: activity.date, showDate: false,
                dataOverlayImage: overlay)
        }
    }

    // PlaceableCard(showBackground: false) → UIImage @3x — 슬라이드 영상 CALayer 오버레이용.
    @MainActor
    private func makePlaceableDataOverlay() -> UIImage? {
        let renderer = ImageRenderer(content:
            PlaceableCard(
                activity: activity,
                detail: detail,
                routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                photo: nil,
                date: activity.date,
                metricsPosition: placeableVM.placeableMetricsPosition,
                accent: placeableVM.placeableAccent,
                showBackground: false,
                showWordmark: false,
                shoeName: displayShoeName,
                weather: condition?.weather,
                size: placeableVM.placeableSize,
                layout: placeableVM.placeableLayout,
                horizTextRow: placeableVM.placeableHorizTextRow,
                horizRoutePos: placeableVM.placeableHorizRoutePos
            )
            .frame(width: PlaceableCard.cardWidth, height: PlaceableCard.cardHeight)
        )
        renderer.scale = 3.0
        return renderer.uiImage
    }

    private func loadPlaceableVideoClips() {
        guard placeableVM.placeableClipRecipes.isEmpty else { return }
        let ud = UserDefaults.standard
        let p  = pvcPrefix
        guard let data  = ud.data(forKey: p + "clips"),
              let descs = try? JSONDecoder().decode([SavedClipDescriptor].self, from: data),
              !descs.isEmpty else { return }
        placeableVM.placeableMuteAudio = ud.bool(forKey: p + "mute")
        var restored: [ClipRecipe] = []
        for desc in descs {
            let thumb: UIImage? = desc.thumbRef.flatMap { ClipThumbStore.load(ref: $0) }
            let recipeURL: URL
            if let ref = desc.clipVideoRef,
               let stableURL = ClipVideoStore.fileURL(ref: ref),
               FileManager.default.fileExists(atPath: stableURL.path) {
                recipeURL = stableURL
            } else {
                recipeURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mimo_pvc_\(UUID().uuidString)")
            }
            var recipe = ClipRecipe(url: recipeURL, fullDuration: desc.fullDuration, thumbnail: thumb)
            recipe.trimStart       = desc.trimStart
            recipe.trimEnd         = desc.trimEnd
            recipe.lines           = desc.lines
            recipe.assetIdentifier = desc.assetID
            recipe.clipVideoRef    = desc.clipVideoRef
            recipe.thumbRef        = desc.thumbRef
            recipe.fontChoice      = OneLinerFont.migrate(desc.fontID)
            recipe.textColor       = desc.colorID.flatMap { OneLinerTextColor(rawValue: $0) } ?? .white
            if let idx = desc.anchorIdx, CardPosition.allCases.indices.contains(idx) {
                recipe.position = CardPosition.allCases[idx]
            }
            recipe.sizeLevel = desc.sizeID.flatMap { TextSizeLevel(rawValue: $0) } ?? .medium
            if let eid = desc.effectID, eid.contains("|") {
                let parts = eid.split(separator: "|", maxSplits: 3).map(String.init)
                recipe.appearanceMode = parts.count > 0 ? (AppearanceMode(rawValue: parts[0]) ?? .typing) : .typing
                recipe.decorEffect    = parts.count > 1 ? (DecorEffect(rawValue: parts[1]) ?? .none) : .none
                if parts.count > 2 {
                    let r = parts[2]
                    recipe.hasBorder = r.contains("B1")
                    recipe.plateOn   = r.contains("P1")
                }
                recipe.flyDirection = parts.count > 3 ? (FlyInDirection(rawValue: parts[3]) ?? .trailing) : .trailing
            }
            recipe.plateColorPreset = desc.plateColorID.flatMap { PlateColorPreset(rawValue: $0) } ?? .blackWhite
            recipe.speed            = desc.speed
            restored.append(recipe)
        }
        placeableVM.placeableClipRecipes = restored
        if let firstThumb = restored.first?.thumbnail { videoPreviewImage = firstThumb }
        // 저장된 클립의 애니메이션으로 UI 상태 동기화 — 칩 표시가 실제 클립 설정과 일치하도록
        if let first = restored.first {
            placeableVM.placeableSlideAppearance = first.appearanceMode
            placeableVM.slideDecorEffect         = first.decorEffect
            placeableVM.slideFlyDirection        = first.flyDirection
        }
    }

    /// 명시적 photoIndex로 OneLiner entry 로드.
    /// cardPhotoIndex가 아직 커밋되지 않은 Button 액션 내에서 호출 시 사용.
    private func loadOneLinerSettingsFor(photoIndex: Int) {
        migrateUserDefaultsOneLiner()
        let mediaRef: String? = photoIndex < oneLinerVM.storyPhotoUUIDs.count
            ? "photo:\(oneLinerVM.storyPhotoUUIDs[photoIndex])"
            : nil
        if let entry = oneLinerEntries.first(where: { $0.mediaRef == mediaRef }) {
            syncUIFromEntry(entry)
            oneLinerVM.oneLinerPhAssetDeleted = !entry.isPHAssetAvailable
        } else {
            oneLinerVM.oneLinerText = ""
            oneLinerVM.oneLinerPhAssetDeleted = false
            if let latest = oneLinerEntries.last {
                oneLinerVM.oneLinerFont  = latest.font
                oneLinerVM.oneLinerColor = latest.textColor
            }
        }
    }

    // MARK: - Story clip edit helpers

    /// storyPhotos를 ClipTrimSheet에 전달할 ClipRecipe 배열로 변환.
    /// 기존 OneLinerEntry에서 text/style 복원, 없으면 기본값.
    private func makeStoryClipRecipes(isSlide: Bool = false) -> [ClipRecipe] {
        let photos = storyPhotos
        let prefix = isSlide ? "slide:" : "photo:"
        return photos.enumerated().map { i, photo in
            let uuid = i < oneLinerVM.storyPhotoUUIDs.count ? oneLinerVM.storyPhotoUUIDs[i] : UUID().uuidString
            let ref  = "\(prefix)\(uuid)"
            // slide: prefix가 없으면 photo: 기존 항목으로 폴백 (마이그레이션 경로)
            let entry = oneLinerEntries.first { $0.mediaRef == ref }
                     ?? (isSlide ? oneLinerEntries.first { $0.mediaRef == "photo:\(uuid)" } : nil)
            var recipe = ClipRecipe(
                url: URL(fileURLWithPath: "/dev/null"),
                fullDuration: 4.0,
                thumbnail: photo
            )
            recipe.storedPhotoRef = ref
            if let e = entry {
                if e.text.hasPrefix("v3slide\n"),
                   let data = e.text.dropFirst("v3slide\n".count).data(using: .utf8),
                   let desc = try? JSONDecoder().decode(SavedClipDescriptor.self, from: data) {
                    // 신규 포맷: 모든 스타일 (plateOn·sizeLevel·effectID 포함) 완전 복원
                    recipe.lines      = desc.lines.map { line in
                        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t.hasPrefix("v3slide") || t.hasPrefix("v3recipes")
                            || t.hasPrefix("v4recipes") || t.hasPrefix("v2clips")
                            || (t.count > 30 && t.hasPrefix("{") && t.hasSuffix("}")) { return "" }
                        return line
                    }
                    recipe.fontChoice = OneLinerFont.migrate(desc.fontID)
                    recipe.textColor  = desc.colorID.flatMap { OneLinerTextColor(rawValue: $0) } ?? .white
                    if let idx = desc.anchorIdx, CardPosition.allCases.indices.contains(idx) {
                        recipe.position = CardPosition.allCases[idx]
                    }
                    recipe.sizeLevel = desc.sizeID.flatMap { TextSizeLevel(rawValue: $0) } ?? .large
                    if let eid = desc.effectID, eid.contains("|") {
                        let parts = eid.split(separator: "|", maxSplits: 3).map(String.init)
                        recipe.appearanceMode = parts.count > 0 ? (AppearanceMode(rawValue: parts[0]) ?? .typing) : .typing
                        recipe.decorEffect    = parts.count > 1 ? (DecorEffect(rawValue: parts[1]) ?? .none) : .none
                        if parts.count > 2 {
                            recipe.hasBorder = parts[2].contains("B1")
                            recipe.plateOn   = parts[2].contains("P1")
                        }
                        recipe.flyDirection = parts.count > 3 ? (FlyInDirection(rawValue: parts[3]) ?? .trailing) : .trailing
                    }
                    recipe.plateColorPreset = desc.plateColorID.flatMap { PlateColorPreset(rawValue: $0) } ?? .blackWhite
                    recipe.metricPace      = desc.metricPace
                    recipe.metricDistance  = desc.metricDistance
                    recipe.metricTime      = desc.metricTime
                    recipe.metricHeartRate = desc.metricHeartRate
                    if let idx = desc.pdtAnchorIdx, CardPosition.allCases.indices.contains(idx) {
                        recipe.pdtPosition = CardPosition.allCases[idx]
                    }
                    if let ct = desc.chartTypeID, let type = ChartOverlayType(rawValue: ct) {
                        recipe.chartOverlayType = type
                    } else if desc.showRoute {
                        recipe.chartOverlayType = .route
                    } else if desc.showHRChart {
                        recipe.chartOverlayType = .hrChart
                    }
                    if let idx = desc.routeAnchorIdx, CardPosition.allCases.indices.contains(idx) {
                        recipe.routePosition = CardPosition.allCases[idx]
                    }
                    if let ps = desc.pdtSizeID2, let size = TextSizeLevel(rawValue: ps) {
                        recipe.pdtSizeLevel = size
                    }
                    if let de = desc.dataEffectID, let mode = AppearanceMode(rawValue: de) {
                        recipe.dataAppearanceMode = mode
                    }
                } else {
                    // 구 포맷: 텍스트 + 기본 3개 스타일만 복원 (마이그레이션 경로)
                    var lines = e.text.components(separatedBy: "\n")
                    while lines.count < 2 { lines.append("") }
                    recipe.lines      = Array(lines.prefix(2))
                    recipe.fontChoice = e.font
                    recipe.textColor  = e.textColor
                    recipe.position   = e.position
                }
            } else {
                recipe.lines = ["", ""]
            }
            return recipe
        }
    }

    /// ClipTrimSheet 완료 후 편집 결과를 OneLinerEntry에 저장.
    /// plateOn·sizeLevel·effectID 등 전체 스타일을 SavedClipDescriptor JSON("v3slide\n")으로 인코딩.
    private func saveStoryClipEdits(_ recipes: [ClipRecipe], isSlide: Bool = false) {
        let prefix = isSlide ? "slide:" : "photo:"
        for (i, recipe) in recipes.enumerated() {
            guard i < oneLinerVM.storyPhotoUUIDs.count else { continue }
            let ref  = "\(prefix)\(oneLinerVM.storyPhotoUUIDs[i])"
            let text = recipe.lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            // SavedClipDescriptor JSON으로 전체 스타일 직렬화 (쉬는 날 buildRecipeSet과 동일 포맷)
            let cleanLines = recipe.lines.map { line -> String in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("v3slide") || t.hasPrefix("v3recipes")
                    || t.hasPrefix("v4recipes") || t.hasPrefix("v2clips")
                    || (t.count > 30 && t.hasPrefix("{") && t.hasSuffix("}")) { return "" }
                return line
            }
            let desc = SavedClipDescriptor(
                assetID: nil, clipVideoRef: nil,
                photoRef: recipe.storedPhotoRef, thumbRef: recipe.thumbRef,
                trimStart: recipe.trimStart, trimEnd: recipe.trimEnd,
                fullDuration: recipe.fullDuration,
                lines: cleanLines,
                fontID: recipe.fontChoice.rawValue,
                colorID: recipe.textColor.rawValue,
                anchorIdx: CardPosition.allCases.firstIndex(of: recipe.position),
                sizeID: recipe.sizeLevel.rawValue,
                effectID: "\(recipe.appearanceMode.rawValue)|\(recipe.decorEffect.rawValue)|B\(recipe.hasBorder ? 1 : 0)P\(recipe.plateOn ? 1 : 0)|\(recipe.flyDirection.rawValue)",
                plateColorID: recipe.plateColorPreset.rawValue,
                speed: recipe.speed,
                metricPace: recipe.metricPace,
                metricDistance: recipe.metricDistance,
                metricTime: recipe.metricTime,
                metricHeartRate: recipe.metricHeartRate,
                pdtAnchorIdx: CardPosition.allCases.firstIndex(of: recipe.pdtPosition),
                showRoute: recipe.showRoute,
                routeAnchorIdx: CardPosition.allCases.firstIndex(of: recipe.routePosition),
                showHRChart: recipe.showHRChart,
                chartTypeID:  recipe.chartOverlayType == .none ? nil : recipe.chartOverlayType.rawValue,
                pdtSizeID2:   recipe.pdtSizeLevel.rawValue,
                dataEffectID: recipe.dataAppearanceMode.rawValue
            )
            let payload: String
            if let data = try? JSONEncoder().encode(desc),
               let json = String(data: data, encoding: .utf8) {
                payload = "v3slide\n" + json
            } else {
                payload = text
            }

            let hasMetric = recipe.metricPace || recipe.metricDistance || recipe.metricTime
                          || recipe.metricHeartRate || recipe.chartOverlayType != .none
            let shouldSave = !text.isEmpty || hasMetric

            if let existing = oneLinerEntries.first(where: { $0.mediaRef == ref }) {
                if shouldSave {
                    existing.text      = payload
                    existing.font      = recipe.fontChoice
                    existing.textColor = recipe.textColor
                    existing.position  = recipe.position
                } else {
                    modelContext.delete(existing)
                }
            } else if shouldSave {
                let entry = OneLinerEntry(workoutID: activity.id.uuidString, mediaRef: ref)
                entry.text      = payload
                entry.font      = recipe.fontChoice
                entry.textColor = recipe.textColor
                entry.position  = recipe.position
                entry.showDate  = true
                modelContext.insert(entry)
            }
        }
        oneLinerVM.cachedStoryRecipes = recipes  // @Query 갱신 전 즉시 렌더용 캐시
        try? modelContext.save()
        Task { await renderCard() }
        // 편집 완료 후 미리보기는 수동(▶ 버튼)으로 시작 — 자동 buildPreview 호출 없음
        if template == .slide { previewPlayer.invalidate() }
    }

    // 저장 트리거 전체 (모두 이 함수를 경유 → upsert 또는 delete-on-empty, append 경로 없음):
    // ① onChange(of: oneLinerVM.oneLinerText)   — 키 입력마다
    // ② 9앵커(position) 칩 탭
    // ③ 폰트 칩 탭
    // ④ 색 칩 탭
    // ⑤ 썸네일 탭                    — cardPhotoIndex 커밋 전에 이전 사진 entry 저장
    // ⑥ 날짜 토글                    — showDate 변경 시 (해당 버튼 액션에 포함)
    private func saveOneLinerSettings() {
        let mediaRef = computeOneLinerMediaRef()
        let trimmed  = oneLinerVM.oneLinerText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = oneLinerEntries.first(where: { $0.mediaRef == mediaRef }) {
            // 빈 문구: 기존 entry 삭제 — 빈 텍스트 entry 잔류 방지
            if trimmed.isEmpty {
                modelContext.delete(existing)
                try? modelContext.save()
                return
            }
            // 변경 없으면 스킵
            guard existing.text      != oneLinerVM.oneLinerText     ||
                  existing.font      != oneLinerVM.oneLinerFont     ||
                  existing.textColor != oneLinerVM.oneLinerColor    ||
                  existing.position  != oneLinerVM.oneLinerPosition ||
                  existing.showDate  != oneLinerVM.oneLinerShowDate else { return }
            existing.text      = oneLinerVM.oneLinerText
            existing.font      = oneLinerVM.oneLinerFont
            existing.textColor = oneLinerVM.oneLinerColor
            existing.position  = oneLinerVM.oneLinerPosition
            existing.showDate  = oneLinerVM.oneLinerShowDate
            try? modelContext.save()
            return
        }

        // 신규 entry: 문구가 있고 5개 미만일 때만 생성
        guard !trimmed.isEmpty, oneLinerEntries.count < 5 else { return }
        let entry = OneLinerEntry(workoutID: activity.id.uuidString, mediaRef: mediaRef)
        entry.text      = oneLinerVM.oneLinerText
        entry.font      = oneLinerVM.oneLinerFont
        entry.textColor = oneLinerVM.oneLinerColor
        entry.position  = oneLinerVM.oneLinerPosition
        entry.showDate  = oneLinerVM.oneLinerShowDate
        modelContext.insert(entry)
        try? modelContext.save()
    }

    /// 중복·빈 문구 entry 정리.
    /// - nil mediaRef = "그라데이션 슬롯" — 러닝당 최대 1개로 취급 (nil끼리도 중복 처리됨).
    /// - 빈 텍스트 entry도 함께 제거.
    private func deduplicateOneLinerEntries() {
        var toDelete: [OneLinerEntry] = []

        // ① 빈 텍스트 entry
        for entry in oneLinerEntries where entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            toDelete.append(entry)
        }

        // ② 같은 (workoutID + mediaRef) 중복 — nil도 단일 슬롯으로 처리
        let deleteIDs = Set(toDelete.map { ObjectIdentifier($0) })
        let remaining = oneLinerEntries.filter { !deleteIDs.contains(ObjectIdentifier($0)) }
        // Dictionary<String?, [OneLinerEntry]> — nil은 Optional.none 키로 그룹됨 ✓
        let grouped = Dictionary(grouping: remaining) { $0.mediaRef as String? }
        for (_, entries) in grouped where entries.count > 1 {
            let sorted = entries.sorted { $0.createdAt > $1.createdAt }
            toDelete.append(contentsOf: sorted.dropFirst())
        }

        guard !toDelete.isEmpty else { return }
        toDelete.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    // MARK: - 연재 일괄 내보내기 (N장 저장)

    /// 문구가 연결된 사진을 순서대로 모두 렌더링해 사진 앱에 저장.
    @MainActor
    private func batchExportOneLinerCards() async {
        guard isOneLiner, template == .story else { return }
        isBatchExporting = true
        defer { isBatchExporting = false }

        for i in oneLinerVM.storyPhotoUUIDs.indices {
            guard i < storyPhotos.count else { continue }
            // 내보내기 시점엔 @Query 갱신 완료 — photoRecipe 사용
            guard let pr = photoRecipe(at: i, prefix: "photo:") else { continue }
            let hasText    = pr.lines.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let hasMetrics = pr.metricPace || pr.metricDistance || pr.metricTime || pr.metricHeartRate
            let hasChart   = pr.showRoute || pr.showHRChart || pr.chartOverlayType != .none
            guard hasText || hasMetrics || hasChart else { continue }

            let text  = pr.lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
            let photo = oneLinerVM.highQualityStoryPhotos[i] ?? storyPhotos[i]
            let card = OneLinerCard(
                activity: activity,
                backgroundPhoto: photo,
                text: text,
                position: pr.position,
                textColor: pr.textColor,
                fontChoice: pr.fontChoice,
                sizeLevel: pr.sizeLevel,
                appearanceMode: pr.appearanceMode,
                decorEffect: pr.decorEffect,
                hasBorder: pr.hasBorder,
                plateOn: pr.plateOn,
                plateColorPreset: pr.plateColorPreset,
                showDate: oneLinerVM.oneLinerShowDate,
                captionMode: true,
                chartBottomReserved: storyChartBottomReserved(for: pr),
                metricPace: pr.metricPace,
                metricDistance: pr.metricDistance,
                metricTime: pr.metricTime,
                metricHeartRate: pr.metricHeartRate,
                pdtPosition: pr.pdtPosition,
                pdtSizeLevel: pr.pdtSizeLevel,
                availableMetrics: oneLinerAvailableMetrics,
                showRoute: pr.showRoute,
                routeCoords: routeCoords,
                routePosition: pr.routePosition,
                showHRChart: pr.showHRChart,
                hrSamples: shareHRSamples,
                hrZones: detail?.hrZones ?? [],
                chartOverlayType: pr.chartOverlayType,
                chartSeriesData: chartSeriesData,
                chartSplits: detail?.splits ?? [],
                intervalSegments: detail?.intervalSegments ?? []
            )
            let renderer = ImageRenderer(content: card.frame(width: OneLinerCard.cardWidth,
                                                              height: OneLinerCard.cardHeight))
            renderer.scale = 3
            if let img = renderer.uiImage {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            }
            // 프레임 간 렌더러 충돌 방지
            await Task.yield()
        }
    }

    /// One-time migration: lift existing UserDefaults entry → SwiftData with mediaRef = nil.
    private func migrateUserDefaultsOneLiner() {
        let id = activity.id.uuidString
        let key = "oneliner_text_\(id)"
        guard let text = UserDefaults.standard.string(forKey: key), !text.isEmpty,
              !oneLinerEntries.contains(where: { $0.mediaRef == nil }) else { return }
        let entry = OneLinerEntry(workoutID: id, mediaRef: nil)
        entry.text = text
        if let raw = UserDefaults.standard.string(forKey: "oneliner_font_\(id)"),
           let f = OneLinerFont(rawValue: raw) { entry.font = f }
        if let raw = UserDefaults.standard.string(forKey: "oneliner_color_\(id)"),
           let c = OneLinerTextColor(rawValue: raw) { entry.textColor = c }
        let posIdx = UserDefaults.standard.integer(forKey: "oneliner_pos_\(id)")
        let cases = Array(CardPosition.allCases)
        if posIdx < cases.count { entry.position = cases[posIdx] }
        if UserDefaults.standard.object(forKey: "oneliner_date_\(id)") != nil {
            entry.showDate = UserDefaults.standard.bool(forKey: "oneliner_date_\(id)")
        }
        modelContext.insert(entry)
        try? modelContext.save()
        ["text", "font", "color", "pos", "date"].forEach {
            UserDefaults.standard.removeObject(forKey: "oneliner_\($0)_\(id)")
        }
    }

    @MainActor
    private func renderCard(showSpinner: Bool = true) async {
        // Placeable card: static image render. 스토리 다사진이면 전체 storyShareImages 생성.
        if cardIndex == 0 {
            if showSpinner { isRendering = true }
            storyShareImages = []
            previewImage = nil
            if template == .story, storyPhotos.count > 1 {
                // 각 사진마다 해당 사진의 문구를 넣어 렌더링
                var rendered: [UIImage] = []
                for (i, photo) in storyPhotos.enumerated() {
                    let t = placeableVM.placeableStoryTexts[i] ?? ""
                    let r = ImageRenderer(content: placeableExportView(photo: photo, text: t))
                    r.scale = 3
                    if let img = r.uiImage { rendered.append(img) }
                }
                storyShareImages = rendered
                // 미리보기는 현재 선택 사진
                let curIdx = placeableCurrentPhotoIdx
                previewImage = rendered.indices.contains(curIdx) ? rendered[curIdx] : rendered.first
            } else {
                let photo = template == .video ? videoPreviewImage : photoFor(0)
                let renderer = ImageRenderer(content: placeableExportView(photo: photo))
                renderer.scale = 3
                previewImage = renderer.uiImage
            }
            isRendering = false
            return
        }

        // BigNumber card: render regardless of template (video/routeVideo don't block it)
        if cardIndex == 3 {
            if showSpinner { isRendering = true }
            storyShareImages = []
            previewImage = nil
            let bnPhoto: UIImage? = template == .video ? videoPreviewImage
                : template == .routeVideo ? routeSnapshot
                : template == .story ? photoFor(3)
                : nil
            let bnCard = BigNumberCard(
                activity: activity, detail: detail, heroMetric: heroMetric,
                mood: bigNumberVM.bigNumberShowMood ? story?.mood : nil,
                memoText: bigNumberVM.bigNumberShowMemo && story?.memo.isEmpty == false ? story?.memo : nil,
                weatherText: condition?.weather?.formattedTemp,
                weatherIcon: condition?.weather?.systemIcon,
                date: activity.date,
                shoeName: displayShoeName,
                photo: bnPhoto,
                chartPanel: .map,
                routeCoordinates: routeCoords,
                accent: bigNumberVM.bigNumberAccent,
                showHRGradient: showHRGradientForRoute,
                hrSamplesForRoute: shareHRSamples,
                routeWorkoutDuration: activity.duration,
                routeZoneBounds: shareZoneBounds
            )
            let renderer = ImageRenderer(content: bnCard.frame(width: 300, height: 375))
            renderer.scale = 3
            previewImage = renderer.uiImage
            isRendering = false
            return
        }

        // Sky card — "그날의 하늘"
        if cardIndex == 4 {
            if showSpinner { isRendering = true }
            storyShareImages = []
            previewImage = nil
            let card = SkyCard(
                activity: activity,
                weather: condition?.weather,
                shoeName: displayShoeName,
                accent: skyVM.skyAccent
            )
            let renderer = ImageRenderer(content: card.frame(width: 300, height: 375))
            renderer.scale = 3
            previewImage = renderer.uiImage
            isRendering = false
            return
        }

        // ECG card — "심전도 시그니처"
        if cardIndex == 5 {
            let activeWaveform = ecgVM.ecgShowPace ? (ecgVM.paceWaveform ?? ecgVM.hrWaveform) : (ecgVM.hrWaveform ?? ecgVM.paceWaveform)
            guard let waveform = activeWaveform else { isRendering = false; return }
            if showSpinner { isRendering = true }
            storyShareImages = []
            previewImage = nil
            let card = ECGSignatureCard(
                activity: activity,
                waveform: waveform,
                weather: condition?.weather,
                shoeName: displayShoeName,
                accent: ecgVM.ecgAccent
            )
            let renderer = ImageRenderer(content: card.frame(width: 300, height: 375))
            renderer.scale = 3
            previewImage = renderer.uiImage
            isRendering = false
            return
        }

        // Ticket card
        if cardIndex == 6 {
            if showSpinner { isRendering = true }
            storyShareImages = []
            previewImage = nil
            let card = TicketCard(
                activity: activity,
                routeCoordinates: routeCoords,
                splits: detail?.splits ?? [],
                raceName: confirmedRace?.raceName,
                shoeName: displayShoeName,
                departureName: ticketVM.ticketDepartureName,
                raceDistanceKm: confirmedRace?.distanceKm,
                raceStartTimeString: confirmedBundledRace?.startTimeString,
                accent: ticketVM.ticketAccent
            )
            let renderer = ImageRenderer(content: card.frame(width: 300, height: 375))
            renderer.scale = 3
            previewImage = renderer.uiImage
            isRendering = false
            return
        }

        // OneLiner card
        if cardIndex == 1 {
            if showSpinner { isRendering = true }
            storyShareImages = []
            previewImage = nil
            let idx   = cardPhotoIndex[1]
            let photo = idx.flatMap { storyPhotos.indices.contains($0) ? storyPhotos[$0] : nil }
                     ?? (!storyPhotos.isEmpty ? storyPhotos[0] : nil)
            // @Query 갱신 타이밍 이슈 우회: 편집 직후엔 oneLinerVM.cachedStoryRecipes 사용
            let pr: ClipRecipe?
            let prIdx = idx ?? 0
            if !oneLinerVM.cachedStoryRecipes.isEmpty, oneLinerVM.cachedStoryRecipes.indices.contains(prIdx) {
                pr = oneLinerVM.cachedStoryRecipes[prIdx]
            } else {
                pr = photoRecipe(at: prIdx, prefix: "photo:")
            }
            let text  = pr?.lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n") ?? oneLinerVM.oneLinerText
            let card = OneLinerCard(
                activity: activity,
                backgroundPhoto: photo,
                text: text,
                position: pr?.position ?? oneLinerVM.oneLinerPosition,
                textColor: pr?.textColor ?? oneLinerVM.oneLinerColor,
                fontChoice: pr?.fontChoice ?? oneLinerVM.oneLinerFont,
                sizeLevel: pr?.sizeLevel ?? .large,
                appearanceMode: pr?.appearanceMode ?? .typing,
                decorEffect: pr?.decorEffect ?? .none,
                hasBorder: pr?.hasBorder ?? false,
                plateOn: pr?.plateOn ?? false,
                plateColorPreset: pr?.plateColorPreset ?? .blackWhite,
                showDate: oneLinerVM.oneLinerShowDate,
                captionMode: true,
                chartBottomReserved: storyChartBottomReserved(for: pr),
                metricPace: pr?.metricPace ?? false,
                metricDistance: pr?.metricDistance ?? false,
                metricTime: pr?.metricTime ?? false,
                metricHeartRate: pr?.metricHeartRate ?? false,
                pdtPosition: pr?.pdtPosition ?? .bottomLeading,
                pdtSizeLevel: pr?.pdtSizeLevel ?? .medium,
                availableMetrics: oneLinerAvailableMetrics,
                showRoute: pr?.showRoute ?? false,
                routeCoords: routeCoords,
                routePosition: pr?.routePosition ?? .bottomTrailing,
                showHRChart: pr?.showHRChart ?? false,
                hrSamples: shareHRSamples,
                hrZones: detail?.hrZones ?? [],
                chartOverlayType: pr?.chartOverlayType ?? .none,
                chartSeriesData: chartSeriesData,
                chartSplits: detail?.splits ?? [],
                intervalSegments: detail?.intervalSegments ?? []
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
        // Athletic card + story template: render athletic card with selected photo background.
        // Share only the single rendered card (no extra plain photos).
        if template == .story, let selPhoto = photoFor(2) {
            let renderer = ImageRenderer(content:
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
                              photo: selPhoto)
                    .frame(width: 300, height: 375)
            )
            renderer.scale = 3
            guard let cardImg = renderer.uiImage else { isRendering = false; return }
            previewImage = cardImg
            storyShareImages = []
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
                          photo: nil,
)
                .frame(width: 300, height: 375)
        case .story:
            if let photo = photoFor(1) {
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
                                   shoeName: displayShoeName,
)
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
        case .video, .slide, .routeVideo:
            EmptyView()
        }
    }

    // MARK: - Photo persistence

    private func persistStoryPhotos(_ images: [UIImage], uuids: [String]? = nil) {
        let capped = Array(images.prefix(5))
        guard !capped.isEmpty else { return }
        let makePhoto: (Int, UIImage) -> StoryPhoto? = { idx, img in
            guard let data = StoryPhoto.thumbnailData(from: img) else { return nil }
            #if DEBUG
            let sizeKB = data.count / 1024
            print("[StoryPhoto] 저장 크기=\(sizeKB)kB\(sizeKB <= 300 ? " ✓300KB 이하" : " ⚠️300KB 초과")")
            #endif
            let uuid = uuids?[safe: idx] ?? UUID().uuidString
            return StoryPhoto(data: data, index: idx, uuid: uuid)
        }
        if let s = story {
            for photo in s.photos ?? [] { modelContext.delete(photo) }
            s.photos = nil
            let newPhotos = capped.enumerated().compactMap { makePhoto($0.offset, $0.element) }
            newPhotos.forEach { modelContext.insert($0) }
            s.photos = newPhotos.isEmpty ? nil : newPhotos
            s.updatedAt = Date()
        } else {
            let s = WorkoutStory(workoutID: activity.id.uuidString)
            modelContext.insert(s)
            let newPhotos = capped.enumerated().compactMap { makePhoto($0.offset, $0.element) }
            newPhotos.forEach { modelContext.insert($0) }
            s.photos = newPhotos
        }
        try? modelContext.save()
    }

    // MARK: - High-quality photo loading from PHAsset

    /// Loads full-res images from Photos library for cross-session rendering quality.
    /// PHAsset localIdentifiers contain "/"; random UUIDs don't — used to distinguish.
    private func loadHighQualityPhotos() async {
        guard let sortedPhotos = story?.photos?.sorted(by: { $0.index < $1.index }) else { return }
        for (idx, photo) in sortedPhotos.enumerated() {
            guard photo.photoUUID.contains("/") else { continue }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [photo.photoUUID], options: nil)
            if assets.count == 0 {
                oneLinerVM.deletedPhotoIndices.insert(idx)
                continue
            }
            guard let asset = assets.firstObject else { continue }
            if let img = await loadImageFromPHAsset(asset) {
                oneLinerVM.highQualityStoryPhotos[idx] = img
            }
        }
    }

    private func loadImageFromPHAsset(_ asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat  // called exactly once
            options.isNetworkAccessAllowed = false      // local only; iCloud-only → nil
            options.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1800, height: 1800),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                cont.resume(returning: image)
            }
        }
    }

    private func clearStoryPhoto() {
        if let s = story {
            for photo in s.photos ?? [] { modelContext.delete(photo) }
            s.photos = nil
            s.updatedAt = Date()
            try? modelContext.save()
        }
    }

    /// 썸네일 X 버튼 — 특정 인덱스의 사진을 스토리에서 삭제하고 카드 인덱스를 정리.
    private func deleteStoryPhoto(at index: Int) {
        let allPhotos = allPickedPhotos.isEmpty ? storyPhotos : allPickedPhotos
        guard index < allPhotos.count else { return }
        var newPhotos = allPhotos
        newPhotos.remove(at: index)

        var newUUIDs = oneLinerVM.storyPhotoUUIDs
        if index < newUUIDs.count { newUUIDs.remove(at: index) }
        oneLinerVM.storyPhotoUUIDs = newUUIDs

        // oneLinerVM.highQualityStoryPhotos 인덱스 재매핑
        var remapped: [Int: UIImage] = [:]
        for (k, v) in oneLinerVM.highQualityStoryPhotos where k != index {
            remapped[k > index ? k - 1 : k] = v
        }
        oneLinerVM.highQualityStoryPhotos = remapped

        // oneLinerVM.deletedPhotoIndices 재매핑
        oneLinerVM.deletedPhotoIndices = Set(oneLinerVM.deletedPhotoIndices.compactMap { idx -> Int? in
            if idx == index { return nil }
            return idx > index ? idx - 1 : idx
        })

        if newPhotos.isEmpty {
            allPickedPhotos = []
            clearStoryPhoto()
            for ci in [0, 1, 2, 3] { cardPhotoIndex[ci] = nil }
        } else {
            allPickedPhotos = newPhotos
            persistStoryPhotos(newPhotos, uuids: newUUIDs)
            // 삭제된 인덱스 기준으로 카드 인덱스 보정
            for ci in [0, 1, 2, 3] {
                guard let idx = cardPhotoIndex[ci] else { continue }
                if idx >= newPhotos.count { cardPhotoIndex[ci] = max(0, newPhotos.count - 1) }
                else if idx > index { cardPhotoIndex[ci] = idx - 1 }
            }
        }
        if template == .slide { previewPlayer.invalidate() }
        Task { await renderCard() }
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

// MARK: - UIActivityViewController wrapper (static image 공유 전용)

// UIImage를 직접 전달 — Instagram은 파일 URL(특히 PNG)을 거부하므로 UIImage 객체를 전달해야 함
struct ShareSheet: UIViewControllerRepresentable {
    let images: [UIImage]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: images, applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// 영상 파일을 공유하고 완료/취소 후 onComplete 호출 (임시 파일 삭제용)
// MARK: - Collection safe subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
