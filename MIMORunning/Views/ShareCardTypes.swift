import SwiftUI
import CoreLocation

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
    /// Top scrim (short block, ≤2 lines): black 8% at top edge, fades to clear at 22% of height.
    static var topScrim: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.08), .clear],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.22)
        )
    }
    /// Top scrim (tall block, 3+ lines with memo): black 15%, fades to clear at 30% of height.
    static var topScrimWide: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.15), .clear],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.30)
        )
    }
    /// Bottom scrim for photo cards: black 8%, clears at 60% from top.
    static var bottomScrim: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.08), .clear],
            startPoint: .bottom,
            endPoint: UnitPoint(x: 0.5, y: 0.40)
        )
    }
    /// Bottom scrim for video cards: removed — text shadows handle readability.
    static var videoBottomScrim: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.00), .clear],
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


// MARK: - 대회 뱃지 (공유 카드·상세 지도 공용)
//
// ⚠ §5.8 데이터 표시 통일성 — 카드마다 복사하던 캡슐 뱃지를 이 하나로 모았다.
//   박스 없이 밝은 노랑 굵은 글씨 + 텍스트 그림자. 이 카드들의 다른 요소(거리·지표)와 같은 문법이고,
//   "노랑 = 실제로 한 것" 색 규칙에도 맞는다 (이미 뛴 대회).
//   scale=1 기준: 아이콘 9pt · 글자 10pt bold (워드마크 11pt 바로 아래 — 이 카드의 유일한 '이름' 정보).
struct RaceBadge: View {
    let name: String
    var scale: CGFloat = 1.0
    /// 밝은 노랑 — 심박 라임(#C6FF00)과 구분되게 주황기 없는 순노랑.
    static let color = Color(hex: "FFD60A")

    var body: some View {
        HStack(spacing: 3 * scale) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 9 * scale, weight: .bold))
            Text(name)
                .font(.system(size: 10 * scale, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(Self.color)
        .cardTextShadow()
    }
}
