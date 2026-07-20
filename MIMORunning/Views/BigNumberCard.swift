import SwiftUI
import MapKit

struct BigNumberCard: View {
    let activity: Activity
    let detail: ActivityDetail?
    let heroMetric: HeroMetric
    var mood: Mood? = nil
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

    private var heroGradient: LinearGradient {
        switch accent {
        case .none:   return LinearGradient(colors: [.white, .white],
                                            startPoint: .top, endPoint: .bottom)
        case .violet: return LinearGradient(colors: [Color(hex: "9B7DFF"), Color(hex: "6845E8")],
                                            startPoint: .top, endPoint: .bottom)
        case .gold:   return LinearGradient(colors: [Color(hex: "FFC74D"), Color(hex: "F2A33C")],
                                            startPoint: .top, endPoint: .bottom)
        }
    }

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
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // 2) Mood icon (gold) + Memo (white semibold)
                if mood != nil || memoText != nil {
                    HStack(alignment: .top, spacing: 6) {
                        if let mood = mood {
                            Image(systemName: mood.sfSymbol)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(hex: "FFC74D"))
                        }
                        if let memo = memoText, !memo.isEmpty {
                            Text(memo)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                        }
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

                VStack(spacing: 6) {
                    Text(heroMetric.formattedValue(activity: activity, detail: detail))
                        .font(.system(size: 96, weight: .black).monospacedDigit())
                        .fontWidth(.condensed)
                        .tracking(-2)
                        .foregroundStyle(heroGradient)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .cardLargeTextShadow()

                    if !heroMetric.unit.isEmpty {
                        Text(heroMetric.unit)
                            .font(.system(size: 20, weight: .black))
                            .fontWidth(.condensed)
                            .foregroundStyle(Color.white.opacity(0.9))
                            .tracking(4)
                            .cardTextShadow()
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
                                        .fill(Color(hex: "26262E").opacity(0.8))
                                        .frame(width: 1, height: 36)
                                }
                                VStack(spacing: 3) {
                                    Text(m.formattedValue(activity: activity, detail: detail))
                                        .font(.system(size: 22, weight: .black).monospacedDigit())
                                        .fontWidth(.condensed)
                                        .foregroundStyle(Color(hex: "EDEDED"))
                                    Text(secondaryLabel(for: m))
                                        .font(.system(size: 11, weight: .bold))
                                        .fontWidth(.condensed)
                                        .foregroundStyle(.white)
                                }
                                .cardTextShadow()
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    metaRow
                        .frame(maxWidth: .infinity, alignment: .center)
                    if let shoe = shoeName {
                        HStack(spacing: 3) {
                            Image(systemName: "shoe.fill")
                                .font(.system(size: 8))
                            Text(shoe)
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .cardTextShadow()
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
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
            Text(date.weekdayCharKo).foregroundStyle(Theme.time)
            Text(date.cardTimeString)
        }
        .font(.system(size: 10))
        .foregroundStyle(.white)
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
    var mood: Mood? = nil
    var memoText: String? = nil
    var weatherText: String? = nil
    var weatherIcon: String? = nil
    let date: Date
    var shoeName: String? = nil
    // nil → videoSafeTopRef/BottomRef * s (export 기본값). 값 지정 시 scale 미적용 그대로 사용 (preview 전용).
    var topInset: CGFloat? = nil
    var bottomInset: CGFloat? = nil

    var accent: CardAccent = .violet

    private var heroGradient: LinearGradient {
        switch accent {
        case .none:   return LinearGradient(colors: [.white, .white],
                                            startPoint: .top, endPoint: .bottom)
        case .violet: return LinearGradient(colors: [Color(hex: "9B7DFF"), Color(hex: "6845E8")],
                                            startPoint: .top, endPoint: .bottom)
        case .gold:   return LinearGradient(colors: [Color(hex: "FFC74D"), Color(hex: "F2A33C")],
                                            startPoint: .top, endPoint: .bottom)
        }
    }

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
                CardVisual.topScrim
                CardVisual.bottomScrim

                VStack(alignment: .leading, spacing: 0) {
                    // Wordmark — positioned inside the video safe zone top edge
                    HStack(spacing: 0) {
                        Text("MIMO")
                            .font(.system(size: 9 * s, weight: .black))
                            .tracking(2)
                            .foregroundStyle(.white)
                        Text(" RUNNING")
                            .font(.system(size: 9 * s, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(Theme.violet)
                    }
                    .padding(.horizontal, CardVisual.videoSafeHorizRef * s)
                    .padding(.top, topInset ?? (CardVisual.videoSafeTopRef * s))

                    // Mood + Memo
                    if mood != nil || memoText != nil {
                        HStack(alignment: .top, spacing: 6 * s) {
                            if let mood = mood {
                                Image(systemName: mood.sfSymbol)
                                    .font(.system(size: 10 * s, weight: .semibold))
                                    .foregroundStyle(Color(hex: "FFC74D"))
                            }
                            if let memo = memoText, !memo.isEmpty {
                                Text(memo)
                                    .font(.system(size: 11 * s, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .cardTextShadow()
                        .padding(.horizontal, 16 * s)
                        .padding(.top, 10 * s)
                    }

                    Spacer()

                    // Hero number
                    VStack(spacing: 6 * s) {
                        Text(heroMetric.formattedValue(activity: activity, detail: detail))
                            .font(.system(size: 96 * s, weight: .black).monospacedDigit())
                            .fontWidth(.condensed)
                            .tracking(-2)
                            .foregroundStyle(heroGradient)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .cardLargeTextShadow()

                        if !heroMetric.unit.isEmpty {
                            Text(heroMetric.unit)
                                .font(.system(size: 20 * s, weight: .black))
                                .fontWidth(.condensed)
                                .foregroundStyle(Color.white.opacity(0.9))
                                .tracking(4)
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
                                            .fill(Color(hex: "26262E").opacity(0.8))
                                            .frame(width: 1, height: 36 * s)
                                    }
                                    VStack(spacing: 3 * s) {
                                        Text(m.formattedValue(activity: activity, detail: detail))
                                            .font(.system(size: 22 * s, weight: .black).monospacedDigit())
                                            .fontWidth(.condensed)
                                            .foregroundStyle(Color(hex: "EDEDED"))
                                        Text(secondaryLabel(for: m))
                                            .font(.system(size: 11 * s, weight: .bold))
                                            .fontWidth(.condensed)
                                            .foregroundStyle(.white)
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
                            .font(.system(size: 9 * s))
                            .foregroundStyle(.white)
                            .cardTextShadow()
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.horizontal, CardVisual.videoSafeHorizRef * s)
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
            Text(date.weekdayCharKo).foregroundStyle(Theme.time)
            Text(date.cardTimeString)
        }
        .font(.system(size: 10 * s))
        .foregroundStyle(.white)
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
        mood: .great,
        memoText: "오늘은 날씨도 좋고 페이스도 잘 나왔다",
        weatherText: "22°C",
        date: Date()
    )
    .padding()
    .background(Color.black)
}
