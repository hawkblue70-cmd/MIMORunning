import SwiftUI
import CoreLocation

// MARK: - CardPosition

enum CardPosition: CaseIterable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading:     .topLeading
        case .top:            .top
        case .topTrailing:    .topTrailing
        case .leading:        .leading
        case .center:         .center
        case .trailing:       .trailing
        case .bottomLeading:  .bottomLeading
        case .bottom:         .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }

    /// Returns the position diagonally/cardinally opposite — used to auto-place route art.
    func opposite() -> CardPosition {
        switch self {
        case .leading:       .trailing
        case .trailing:      .leading
        case .top:           .bottom
        case .bottom:        .top
        case .topLeading:    .bottomTrailing
        case .topTrailing:   .bottomLeading
        case .bottomLeading: .topTrailing
        case .bottomTrailing:.topLeading
        case .center:        .bottom
        }
    }

    var isTop:    Bool { self == .topLeading    || self == .top    || self == .topTrailing }
    var isBottom: Bool { self == .bottomLeading || self == .bottom || self == .bottomTrailing }
    var isLeading: Bool { self == .topLeading   || self == .leading || self == .bottomLeading }
    var isTrailing: Bool { self == .topTrailing || self == .trailing || self == .bottomTrailing }
}

// MARK: - CardAccent

enum CardAccent {
    case none, violet, gold
}

// MARK: - PlaceableSize

enum PlaceableSize { case large, small }

enum PlaceableLayout { case vertical, horizontal }

enum HorizRow { case top, middle, bottom }

// MARK: - Bright-background text legibility

extension View {
    /// Strong shadow + thin outline simulation for white text over bright photos.
    func brightCardText() -> some View {
        self
            .shadow(color: .black.opacity(0.50), radius: 4, x: 0, y: 2)
    }
}

// MARK: - PlaceableCard

struct PlaceableCard: View {
    let activity: Activity
    let detail: ActivityDetail?
    let routeCoords: [CLLocationCoordinate2D]?
    let photo: UIImage?
    let date: Date
    var metricsPosition: CardPosition = .topLeading
    var accent: CardAccent = .none
    var showBackground: Bool = true
    var showWordmark: Bool = true
    var shoeName: String? = nil
    var weather: WeatherSnapshot? = nil
    var size: PlaceableSize = .large
    var layout: PlaceableLayout = .vertical
    var horizTextRow:  HorizRow     = .bottom    // horizontal mode: which row text occupies
    var horizRoutePos: CardPosition = .center    // horizontal mode: explicit route anchor cell
    var cropOffsetX:   CGFloat      = 0.5        // 0=left, 0.5=center, 1=right (landscape photo)

    static let cardWidth:  CGFloat = 300
    static let cardHeight: CGFloat = 375

    private var labelFontSize:    CGFloat { size == .large ? 12   : 8.4  }
    private var valueFontSize:    CGFloat { size == .large ? 24   : 16.8 }
    private var unitFontSize:     CGFloat { size == .large ? 14   : 9.8  }
    private var routeArtSize:     CGFloat { size == .large ? 109  : 76   }
    private var routeLineWidth:   CGFloat { size == .large ? 1.0  : 0.7  }
    private var routeShadowRadius: CGFloat {
        size == .large ? CardVisual.routeShadowRadius : CardVisual.routeShadowRadius * 0.7
    }
    private var routeLineColor: Color {
        switch accent {
        case .none:   return .white
        case .violet: return Color(hex: "9B7DFF")
        case .gold:   return Color(hex: "FFC74D")
        }
    }

    private var horizontalModeAlignment: Alignment {
        switch horizTextRow {
        case .top:    return .top
        case .middle: return .center
        case .bottom: return .bottom
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundView

            // Route art at opposite corner from metrics
            routeArtLayer

            // Wordmark — 영상 오버레이 시 별도 배치하므로 선택적으로 표시
            if showWordmark {
                wordmarkView
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            // Metrics block at chosen position (shifted to avoid wordmark when top)
            metricsView
                .padding(metricsInsets)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: layout == .horizontal ? horizontalModeAlignment : metricsPosition.alignment)

            // Footer — date + activity icon, always bottom
            footerView
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Background
    // Bright mode: photo at full brightness, no scrim, no dark overlay.
    // Dark fallback only when photo is nil.
    @ViewBuilder
    private var backgroundView: some View {
        if showBackground {
            if let photo {
                let s    = max(Self.cardWidth / photo.size.width, Self.cardHeight / photo.size.height)
                let imgW = photo.size.width  * s
                let imgH = photo.size.height * s
                let ox   = -(cropOffsetX * max(0, imgW - Self.cardWidth))
                Image(uiImage: photo)
                    .resizable()
                    .frame(width: imgW, height: imgH)
                    .offset(x: ox)
                    .frame(width: Self.cardWidth, height: Self.cardHeight)
                    .clipped()
                    .brightness(0.05)
                    .saturation(1.10)
            } else {
                Color(hex: "141118")
                    .frame(width: Self.cardWidth, height: Self.cardHeight)
            }
        }
    }

    // MARK: - Route art

    // Horizontal mode: route placed at explicit horizRoutePos (full 9-cell control).
    private var routePosition: CardPosition {
        if layout == .horizontal { return horizRoutePos }
        return metricsPosition.opposite()
    }

    @ViewBuilder
    private var routeArtLayer: some View {
        if let coords = routeCoords, !coords.isEmpty {
            let rp = routePosition
            RouteLineArt(coordinates: coords, lineColor: routeLineColor, lineWidth: routeLineWidth)
                .cardRouteShadow(radius: routeShadowRadius)
                .frame(width: routeArtSize, height: routeArtSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: rp.alignment)
                .padding(routeArtPadding(for: rp))
                .allowsHitTesting(false)
        }
    }

    private func routeArtPadding(for pos: CardPosition) -> EdgeInsets {
        let base: CGFloat = 12
        // Extra bottom clearance so route doesn't overlap the footer row
        let bottomExtra: CGFloat = pos.isBottom ? 28 : 0
        // Extra top clearance so route doesn't overlap the wordmark (~9pt text + 14pt pad ≈ 26pt)
        let topExtra: CGFloat = pos.isTop ? 16 : 0
        return EdgeInsets(top: base + topExtra, leading: base, bottom: base + bottomExtra, trailing: base)
    }

    // MARK: - Wordmark
    private var wordmarkView: some View {
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
        .brightCardText()
        .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 1)
    }

    // MARK: - Metrics

    private var distanceKm: String {
        let km = activity.distance / 1000
        return km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
    }

    @ViewBuilder
    private var metricsView: some View {
        if layout == .horizontal { horizontalMetricsView } else { verticalMetricsView }
    }

    private var verticalMetricsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Distance — accent color on value, "km" unit at 60%
            VStack(alignment: .leading, spacing: 0) {
                Text(AppLanguage.shared.s("거리", "DIST"))
                    .font(.system(size: labelFontSize, weight: .semibold))
                    .fontWidth(.condensed)
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .brightCardText()
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    distanceValueText
                    Text("km")
                        .font(.system(size: unitFontSize, weight: .semibold).italic())
                        .fontWidth(.condensed)
                        .foregroundStyle(.white.opacity(0.70))
                        .brightCardText()
                }
            }
            // Duration
            metricRow(label: AppLanguage.shared.s("시간", "TIME"),
                      value: activity.formattedDuration)
            // Pace (running/hiking only)
            if let pace = activity.formattedPace {
                metricRow(label: AppLanguage.shared.s("페이스", "PACE"),
                          value: pace, unit: "/km")
            }
        }
    }

    @ViewBuilder
    private var distanceValueText: some View {
        switch accent {
        case .none:
            Text(distanceKm)
                .font(.system(size: valueFontSize, weight: .heavy).italic().monospacedDigit())
                .fontWidth(.condensed)
                .foregroundStyle(.white)
                .brightCardText()
        case .violet:
            Text(distanceKm)
                .font(.system(size: valueFontSize, weight: .heavy).italic().monospacedDigit())
                .fontWidth(.condensed)
                .foregroundStyle(LinearGradient(
                    colors: [Color(hex: "9B7DFF"), Color(hex: "6845E8")],
                    startPoint: .top, endPoint: .bottom))
                .brightCardText()
        case .gold:
            Text(distanceKm)
                .font(.system(size: valueFontSize, weight: .heavy).italic().monospacedDigit())
                .fontWidth(.condensed)
                .foregroundStyle(LinearGradient(
                    colors: [Color(hex: "FFC74D"), Color(hex: "F2A33C")],
                    startPoint: .top, endPoint: .bottom))
                .brightCardText()
        }
    }

    private func metricRow(label: String, value: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: labelFontSize, weight: .semibold))
                .fontWidth(.condensed)
                .tracking(1.5)
                .foregroundStyle(.white)
                .brightCardText()
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: valueFontSize, weight: .heavy).italic().monospacedDigit())
                    .fontWidth(.condensed)
                    .foregroundStyle(.white)
                    .brightCardText()
                if let unit {
                    Text(unit)
                        .font(.system(size: unitFontSize, weight: .semibold).italic())
                        .fontWidth(.condensed)
                        .foregroundStyle(.white.opacity(0.70))
                        .brightCardText()
                }
            }
        }
    }

    // Thin separator dot for horizontal metrics row
    private var dividerDot: some View {
        Text(" · ")
            .font(.system(size: valueFontSize * 0.9, weight: .regular))
            .fontWidth(.condensed)
            .foregroundStyle(.white.opacity(0.45))
            .brightCardText()
    }

    // Accent-colored distance text (same size as other metrics, color-only distinction)
    @ViewBuilder
    private var distanceHorizText: some View {
        switch accent {
        case .none:
            Text(distanceKm)
                .font(.system(size: valueFontSize, weight: .heavy).italic().monospacedDigit())
                .fontWidth(.condensed)
                .foregroundStyle(.white)
                .brightCardText()
        case .violet:
            Text(distanceKm)
                .font(.system(size: valueFontSize, weight: .heavy).italic().monospacedDigit())
                .fontWidth(.condensed)
                .foregroundStyle(LinearGradient(
                    colors: [Color(hex: "9B7DFF"), Color(hex: "6845E8")],
                    startPoint: .top, endPoint: .bottom))
                .brightCardText()
        case .gold:
            Text(distanceKm)
                .font(.system(size: valueFontSize, weight: .heavy).italic().monospacedDigit())
                .fontWidth(.condensed)
                .foregroundStyle(LinearGradient(
                    colors: [Color(hex: "FFC74D"), Color(hex: "F2A33C")],
                    startPoint: .top, endPoint: .bottom))
                .brightCardText()
        }
    }

    // Horizontal single-row: "7.02km · 43:34 · 6'12"" — labels omitted, distance accented
    private var horizontalMetricsView: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                distanceHorizText
                Text("km")
                    .font(.system(size: unitFontSize, weight: .semibold).italic())
                    .fontWidth(.condensed)
                    .foregroundStyle(.white.opacity(0.70))
                    .brightCardText()
            }
            dividerDot
            Text(activity.formattedDuration)
                .font(.system(size: valueFontSize, weight: .heavy).italic().monospacedDigit())
                .fontWidth(.condensed)
                .foregroundStyle(.white)
                .brightCardText()
            if let pace = activity.formattedPace {
                dividerDot
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(pace)
                        .font(.system(size: valueFontSize, weight: .heavy).italic().monospacedDigit())
                        .fontWidth(.condensed)
                        .foregroundStyle(.white)
                        .brightCardText()
                    Text("/km")
                        .font(.system(size: unitFontSize, weight: .semibold).italic())
                        .fontWidth(.condensed)
                        .foregroundStyle(.white.opacity(0.70))
                        .brightCardText()
                }
            }
        }
        .cardTextShadow()
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                Text(date.cardDateString)
                Text(date.weekdayCharKo).foregroundStyle(Theme.time)
                Text(date.cardTimeString)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white)
            .brightCardText()
            if let w = weather {
                HStack(spacing: 3) {
                    Image(systemName: w.systemIcon).font(.system(size: 8))
                    Text(w.formattedTemp).font(.system(size: 8, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.75))
                .brightCardText()
                .padding(.leading, 6)
            }
            Spacer()
            if let shoe = shoeName {
                Text(shoe)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white)
                    .brightCardText()
                    .lineLimit(1)
            }
            Image(systemName: activity.type.icon)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.50))
                .brightCardText()
        }
    }

    // MARK: - Metrics inset helpers
    // When metrics land on a top edge: shift down to clear the wordmark (~9pt text + 14pt top pad ≈ 28pt).
    // When on a bottom edge: shift up to clear the footer row (~9pt text + 12pt bottom pad ≈ 26pt).
    private var metricsInsets: EdgeInsets {
        let p: CGFloat = 14
        let topClear: CGFloat = 50   // clears wordmark + safe breathing room
        let botClear: CGFloat = 26   // clears footer
        if layout == .horizontal {
            switch horizTextRow {
            case .top:    return EdgeInsets(top: p + topClear, leading: p, bottom: p + topClear, trailing: p)
            case .bottom: return EdgeInsets(top: p + botClear, leading: p, bottom: p + botClear, trailing: p)
            case .middle: return EdgeInsets(top: p,            leading: p, bottom: p,            trailing: p)
            }
        }
        switch metricsPosition {
        case .topLeading:
            return EdgeInsets(top: p + topClear, leading: p, bottom: p, trailing: p)
        case .top:
            return EdgeInsets(top: p + topClear, leading: p, bottom: p, trailing: p)
        case .topTrailing:
            return EdgeInsets(top: p + topClear, leading: p, bottom: p, trailing: p)
        case .bottomLeading:
            return EdgeInsets(top: p, leading: p, bottom: p + botClear, trailing: p)
        case .bottom:
            return EdgeInsets(top: p, leading: p, bottom: p + botClear, trailing: p)
        case .bottomTrailing:
            return EdgeInsets(top: p, leading: p, bottom: p + botClear, trailing: p)
        default:
            return EdgeInsets(top: p, leading: p, bottom: p, trailing: p)
        }
    }
}

// MARK: - Preview helpers

private extension PlaceableCard {
    static var previewActivity: Activity {
        Activity(id: UUID(), type: .running, date: Date(),
                 duration: 2835, distance: 8020, calories: 480, avgHeartRate: 152)
    }

    static var previewCoords: [CLLocationCoordinate2D] {
        stride(from: 0, through: 40, by: 1).map { i in
            let t = Double(i) / 40.0
            return CLLocationCoordinate2D(latitude: 37.32 + t * 0.06,
                                         longitude: 126.67 + t * 0.05)
        }
    }

    static var brightPhoto: UIImage {
        let size = CGSize(width: 300, height: 375)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            // Warm light background gradient
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(red: 0.88, green: 0.80, blue: 0.68, alpha: 1).cgColor,
                         UIColor(red: 0.72, green: 0.82, blue: 0.78, alpha: 1).cgColor] as CFArray,
                locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient,
                start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }
}

// MARK: - Previews

#Preview("topLeading · none · bright photo") {
    ZStack {
        Color(white: 0.15).ignoresSafeArea()
        PlaceableCard(
            activity: PlaceableCard.previewActivity,
            detail: nil,
            routeCoords: PlaceableCard.previewCoords,
            photo: PlaceableCard.brightPhoto,
            date: PlaceableCard.previewActivity.date,
            metricsPosition: .topLeading,
            accent: .none
        )
    }
}

#Preview("topLeading · violet · bright photo") {
    ZStack {
        Color(white: 0.15).ignoresSafeArea()
        PlaceableCard(
            activity: PlaceableCard.previewActivity,
            detail: nil,
            routeCoords: PlaceableCard.previewCoords,
            photo: PlaceableCard.brightPhoto,
            date: PlaceableCard.previewActivity.date,
            metricsPosition: .topLeading,
            accent: .violet
        )
    }
}

#Preview("topLeading · gold · no photo") {
    ZStack {
        Color(white: 0.15).ignoresSafeArea()
        PlaceableCard(
            activity: PlaceableCard.previewActivity,
            detail: nil,
            routeCoords: PlaceableCard.previewCoords,
            photo: nil,
            date: PlaceableCard.previewActivity.date,
            metricsPosition: .topLeading,
            accent: .gold
        )
    }
}
