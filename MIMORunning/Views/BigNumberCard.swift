import SwiftUI
import MapKit

// MARK: - BigNumber 타이포 토큰 (절제형: 액센트는 히어로 숫자·단위에만, 나머지는 무채색 위계)
// 카드(BigNumberCard)와 영상 오버레이(BigNumberVideoOverlayView)가 동일 값을 공유한다.
enum BigNumberStyle {
    static let heroSize: CGFloat        = 92    // condensed·heavy — compressed·black보다 획이 부드럽고 카드를 덜 누름
    static let heroTracking: CGFloat    = -1
    static let unitSize: CGFloat        = 14
    static let unitTracking: CGFloat    = 2
    static let secondaryValueSize: CGFloat = 18
    static let secondaryLabelSize: CGFloat = 9
    static let metaSize: CGFloat        = 9
    static let secondaryValueOpacity: Double = 0.80
    static let secondaryLabelOpacity: Double = 0.50
    static let metaOpacity: Double      = 0.60
    static let dividerOpacity: Double   = 0.12

    /// 히어로 숫자: 밝은 톤끼리의 얕은 그라디언트 (어두운 배경에서 하단이 묻히지 않도록)
    static func heroGradient(_ accent: CardAccent) -> LinearGradient {
        switch accent {
        case .none:   return LinearGradient(colors: [.white, .white],
                                            startPoint: .top, endPoint: .bottom)
        case .violet: return LinearGradient(colors: [Color(hex: "A98BFF"), Color(hex: "8C6BFF")],
                                            startPoint: .top, endPoint: .bottom)
        case .gold:   return LinearGradient(colors: [Color(hex: "FFD166"), Color(hex: "FFC74D")],
                                            startPoint: .top, endPoint: .bottom)
        }
    }
    /// 단위: 액센트 색 90% (액센트 없음 → 흰색 70%)
    static func unitColor(_ accent: CardAccent) -> Color {
        switch accent {
        case .none:   return .white.opacity(0.70)
        case .violet: return Color(hex: "9B7DFF").opacity(0.90)
        case .gold:   return Color(hex: "FFC74D").opacity(0.90)
        }
    }
}

struct BigNumberCard: View {
    let activity: Activity
    let detail: ActivityDetail?
    let heroMetric: HeroMetric
    var memoText: String? = nil
    var weatherText: String? = nil
    var weatherIcon: String? = nil
    let date: Date
    var shoeName: String? = nil
    var photo: UIImage? = nil
    var chartPanel: CardChartPanel = .map
    var chartSplits: [SplitData] = []
    var chartHRSamples: [(offset: TimeInterval, bpm: Int)] = []
    var chartHRZones: [HRZoneData] = []
    var chartWorkoutSeries: [(offset: TimeInterval, value: Double)] = []
    var chartIntervalSegments: [IntervalSegment] = []
    var routeCoordinates: [CLLocationCoordinate2D] = []

    static let cardWidth: CGFloat  = 300
    static let cardHeight: CGFloat = 375

    private var secondaryMetrics: [HeroMetric] {
        let order: [HeroMetric] = [.distance, .duration, .pace, .heartRate]
        return Array(
            order
                .filter { $0 != heroMetric && $0.isAvailable(activity: activity, detail: detail) }
                .prefix(3)
        )
    }

    var accent: CardAccent = .violet
    // HR gradient for route line (dark-background only; suppressed when photo != nil)
    var showHRGradient: Bool = false
    var hrSamplesForRoute: [(offset: TimeInterval, bpm: Int)] = []
    var routeWorkoutDuration: TimeInterval = 0
    var routeZoneBounds: [(id: Int, minBPM: Int)] = []

    private var heroGradient: LinearGradient { BigNumberStyle.heroGradient(accent) }

    private var routeLineColor: Color {
        switch accent {
        case .none:   return .white.opacity(0.85)
        case .violet: return Theme.violet.opacity(0.85)
        case .gold:   return Color(hex: "FFC74D").opacity(0.85)
        }
    }

    var body: some View {
        ZStack {
            // ── Background ──────────────────────────────────────────
            if let photo = photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.cardWidth, height: Self.cardHeight)
                    .clipped()
            } else {
                Color(hex: "141118")
            }

            CardVisual.topScrim
            CardVisual.bottomScrim

            // ── Content ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {

                // 1) Wordmark
                MIMOWordmark(size: 11, onMediaCard: true)
                .padding(.horizontal, 20)
                .padding(.top, 14)

                // 2) Memo (white semibold)
                if let memo = memoText, !memo.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Text(memo)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .cardTextShadow()
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }

                // 3) Hero block — positioned at ~42% from top
                Spacer()

                if chartPanel == .map, !routeCoordinates.isEmpty {
                    HStack {
                        Spacer()
                        RouteLineArt(
                            coordinates: routeCoordinates,
                            lineColor: routeLineColor,
                            hrSamples: hrSamplesForRoute,
                            workoutDuration: routeWorkoutDuration,
                            zoneBounds: routeZoneBounds,
                            showHRGradient: showHRGradient && photo == nil
                        )
                        .frame(width: 110, height: 110)
                    }
                    .padding(.horizontal, 16)
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }

                VStack(spacing: 0) {
                    Text(heroMetric.formattedValue(activity: activity, detail: detail))
                        .font(.system(size: BigNumberStyle.heroSize, weight: .heavy).monospacedDigit())
                        .fontWidth(.condensed)
                        .tracking(BigNumberStyle.heroTracking)
                        .foregroundStyle(heroGradient)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        // 그림자는 사진 배경에서만 — 어두운 단색 배경에선 번짐만 생김
                        .shadow(color: photo != nil ? CardVisual.textShadowColor : .clear,
                                radius: CardVisual.largeTextShadowRadius, x: 0, y: CardVisual.textShadowY)

                    if !heroMetric.unit.isEmpty {
                        Text(heroMetric.unit)
                            .font(.system(size: BigNumberStyle.unitSize, weight: .bold))
                            .fontWidth(.condensed)
                            .foregroundStyle(BigNumberStyle.unitColor(accent))
                            .tracking(BigNumberStyle.unitTracking)
                            .shadow(color: photo != nil ? CardVisual.textShadowColor : .clear,
                                    radius: CardVisual.textShadowRadius, x: 0, y: CardVisual.textShadowY)
                    }
                }
                .frame(maxWidth: .infinity)

                // Smaller spacer below hero → hero sits closer to upper half
                Spacer(minLength: 12).fixedSize()

                // 4) Secondary metrics + meta row
                VStack(alignment: .trailing, spacing: 8) {
                    if !secondaryMetrics.isEmpty {
                        HStack(spacing: 0) {
                            ForEach(Array(secondaryMetrics.enumerated()), id: \.offset) { idx, m in
                                if idx > 0 {
                                    Rectangle()
                                        .fill(Color.white.opacity(BigNumberStyle.dividerOpacity))
                                        .frame(width: 1, height: 32)
                                }
                                VStack(spacing: 3) {
                                    Text(m.formattedValue(activity: activity, detail: detail))
                                        .font(.system(size: BigNumberStyle.secondaryValueSize, weight: .semibold).monospacedDigit())
                                        .fontWidth(.condensed)
                                        .foregroundStyle(.white.opacity(BigNumberStyle.secondaryValueOpacity))
                                    Text(secondaryLabel(for: m).uppercased())
                                        .font(.system(size: BigNumberStyle.secondaryLabelSize, weight: .medium))
                                        .tracking(1)
                                        .foregroundStyle(.white.opacity(BigNumberStyle.secondaryLabelOpacity))
                                }
                                .cardTextShadow()
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    HStack {
                        metaRow
                        if let shoe = shoeName {
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: "shoe.fill")
                                    .font(.system(size: 8))
                                Text(shoe)
                            }
                            .font(.system(size: BigNumberStyle.metaSize))
                            .foregroundStyle(.white.opacity(BigNumberStyle.metaOpacity))
                            .cardTextShadow()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 4) {
            if let w = weatherText {
                Image(systemName: weatherIcon ?? "thermometer.medium").font(.system(size: 9))
                Text("\(w) ·")
            }
            Text(date.cardDateString)
            Text(date.weekdayString)
            Text(date.cardTimeString)
        }
        .font(.system(size: BigNumberStyle.metaSize))
        .foregroundStyle(.white.opacity(BigNumberStyle.metaOpacity))
        .cardTextShadow()
    }

    private func secondaryLabel(for metric: HeroMetric) -> String {
        let L = AppLanguage.shared
        switch metric {
        case .distance:  return "KM"
        case .pace:      return "/km"
        case .duration:  return L.s("시간", "TIME")
        case .heartRate: return "bpm"
        }
    }
}

// MARK: - BigNumberVideoOverlayView
// Transparent overlay (no card background) for video/routeVideo export.
// Scales all content proportionally to available width so it works at any render size.
struct BigNumberVideoOverlayView: View {
    let activity: Activity
    let detail: ActivityDetail?
    let heroMetric: HeroMetric
    var memoText: String? = nil
    var weatherText: String? = nil
    var weatherIcon: String? = nil
    let date: Date
    var shoeName: String? = nil
    // nil → videoSafeTopRef/BottomRef * s (export 기본값). 값 지정 시 scale 미적용 그대로 사용 (preview 전용).
    var topInset: CGFloat? = nil
    var bottomInset: CGFloat? = nil

    var accent: CardAccent = .violet

    private var heroGradient: LinearGradient { BigNumberStyle.heroGradient(accent) }

    private var secondaryMetrics: [HeroMetric] {
        let order: [HeroMetric] = [.distance, .duration, .pace, .heartRate]
        return Array(
            order
                .filter { $0 != heroMetric && $0.isAvailable(activity: activity, detail: detail) }
                .prefix(3)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / 300  // scale relative to standard 300-pt card width
            ZStack {
                CardVisual.bottomScrim

                VStack(alignment: .leading, spacing: 0) {
                    // Logo + memo — unified left edge (matches VideoOverlayCard). 로고에는 그림자 없음
                    VStack(alignment: .leading, spacing: 2 * s) {
                        MIMOWordmark(size: 11 * s, onMediaCard: true)
                        if let memo = memoText, !memo.isEmpty {
                            Text(memo)
                                .font(.system(size: 10 * s, weight: .bold, design: .serif).italic())
                                .foregroundStyle(.white)
                                .cardTextShadow()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, topInset ?? (CardVisual.videoSafeTopRef * s))

                    Spacer()

                    // Hero number
                    VStack(spacing: 0) {
                        Text(heroMetric.formattedValue(activity: activity, detail: detail))
                            .font(.system(size: BigNumberStyle.heroSize * s, weight: .heavy).monospacedDigit())
                            .fontWidth(.condensed)
                            .tracking(BigNumberStyle.heroTracking * s)
                            .foregroundStyle(heroGradient)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .cardLargeTextShadow()   // 영상·사진 배경 → 그림자 유지

                        if !heroMetric.unit.isEmpty {
                            Text(heroMetric.unit)
                                .font(.system(size: BigNumberStyle.unitSize * s, weight: .bold))
                                .fontWidth(.condensed)
                                .foregroundStyle(BigNumberStyle.unitColor(accent))
                                .tracking(BigNumberStyle.unitTracking * s)
                                .cardTextShadow()
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 12 * s).fixedSize()

                    // Secondary metrics + meta
                    VStack(alignment: .trailing, spacing: 8 * s) {
                        if !secondaryMetrics.isEmpty {
                            HStack(spacing: 0) {
                                ForEach(Array(secondaryMetrics.enumerated()), id: \.offset) { idx, m in
                                    if idx > 0 {
                                        Rectangle()
                                            .fill(Color.white.opacity(BigNumberStyle.dividerOpacity))
                                            .frame(width: 1, height: 32 * s)
                                    }
                                    VStack(spacing: 3 * s) {
                                        Text(m.formattedValue(activity: activity, detail: detail))
                                            .font(.system(size: BigNumberStyle.secondaryValueSize * s, weight: .semibold).monospacedDigit())
                                            .fontWidth(.condensed)
                                            .foregroundStyle(.white.opacity(BigNumberStyle.secondaryValueOpacity))
                                        Text(secondaryLabel(for: m).uppercased())
                                            .font(.system(size: BigNumberStyle.secondaryLabelSize * s, weight: .medium))
                                            .tracking(1 * s)
                                            .foregroundStyle(.white.opacity(BigNumberStyle.secondaryLabelOpacity))
                                    }
                                    .cardTextShadow()
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        metaRow(s: s)
                            .frame(maxWidth: .infinity, alignment: .center)
                        if let shoe = shoeName {
                            HStack(spacing: 3 * s) {
                                Image(systemName: "shoe.fill")
                                    .font(.system(size: 8 * s))
                                Text(shoe)
                            }
                            .font(.system(size: BigNumberStyle.metaSize * s))
                            .foregroundStyle(.white.opacity(BigNumberStyle.metaOpacity))
                            .cardTextShadow()
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, bottomInset ?? (CardVisual.videoSafeBottomRef * s))
                }
            }
        }
    }

    @ViewBuilder
    private func metaRow(s: CGFloat) -> some View {
        HStack(spacing: 4 * s) {
            if let w = weatherText {
                Image(systemName: weatherIcon ?? "thermometer.medium").font(.system(size: 9 * s))
                Text("\(w) ·")
            }
            Text(date.cardDateString)
            Text(date.weekdayString)
            Text(date.cardTimeString)
        }
        .font(.system(size: BigNumberStyle.metaSize * s))
        .foregroundStyle(.white.opacity(BigNumberStyle.metaOpacity))
        .cardTextShadow()
    }

    private func secondaryLabel(for metric: HeroMetric) -> String {
        let L = AppLanguage.shared
        switch metric {
        case .distance:  return "KM"
        case .pace:      return "/km"
        case .duration:  return L.s("시간", "TIME")
        case .heartRate: return "bpm"
        }
    }
}

#Preview {
    let activity = Activity(
        id: UUID(),
        type: .running,
        date: Date(),
        duration: 2545,
        distance: 10_020,
        calories: 520,
        avgHeartRate: 152
    )
    BigNumberCard(
        activity: activity,
        detail: nil,
        heroMetric: .distance,
        memoText: "오늘은 날씨도 좋고 페이스도 잘 나왔다",
        weatherText: "22°C",
        date: Date()
    )
    .padding()
    .background(Color.black)
}
