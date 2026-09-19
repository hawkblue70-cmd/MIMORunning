import SwiftUI
import CoreLocation

// MARK: - TicketCard
//
// Apple Wallet-style boarding pass for a run.
// 3-section layout: [FROM/TO header] | [2×3 info grid] | [barcode strip]
// Separated by a TicketPerforatedLine (notched tear-off) and a solid 1pt divider.
//
// TO label rules
//   Standard distances (±2%): 5K · 10K · 하프(21.1K) · 풀(42.2K) → standard label
//   All others: Int(km.rounded()) + "K"   e.g. 6.01 km → "6K"
//
// Race variant  (raceName != nil)
//   TO  = race name (2 lines max, min-scale 0.6 for long names)
//   TIME = BundledRace.startTimeString "HH:MM" if set, else activity start
//   GATE = race-distance badge label ("FULL"/"HALF"/"10K"/"5K") + 🏆 gold trophy
//   Border / FROM color / wordmark RUNNING = gold (#FFC74D)
//   Barcode number: MIMO-RACE-YYYYMMDD  (vs MIMO-RUN-… for normal)
//   Accent locked to gold — chip row hidden in container
//
// Accent (non-race only, passed from container)
//   .none / .violet → violet   .gold → gold
//   Applies to: FROM text, RUNNING wordmark, route barcode line colour, border tint
//
// Barcode strip
//   GPS route: TicketRouteBarcode — force-stretched (independent x/y scales, barcode feel)
//   Treadmill: TicketSplitBarcode — varying-width 3-stripe-per-split bars
//   No data: number label only
//
// Structural constants
//   cardWidth=300  cardHeight=375  borderInset=14pt
//   Inner border: RoundedRectangle(cornerRadius:7) stroke, 14pt inset, sits BELOW VStack
//   Notch circles centred on the inner border line (x=14, x=286); bg-fill erases border,
//   arc outline in border colour recreates the "punched paper" punch-hole look.

struct TicketCard: View {
    let activity: Activity
    var routeCoordinates: [CLLocationCoordinate2D] = []
    var splits: [SplitData] = []
    var raceName: String? = nil
    var shoeName: String? = nil
    var departureName: String = "RUN"
    var raceDistanceKm: Double? = nil
    var raceStartTimeString: String? = nil   // "HH:MM" from BundledRace.startTimeString
    var accent: CardAccent = .none           // ignored when isRace (gold fixed)

    static let cardWidth:  CGFloat = 300
    static let cardHeight: CGFloat = 375
    static let borderInset: CGFloat = 14

    // MARK: - Derived

    private var hasGPS: Bool    { !routeCoordinates.isEmpty }
    private var hasSplits: Bool { !splits.isEmpty }

    var isRace: Bool { raceName != nil }

    // Resolved accent colour: race always gold; non-race follows accent parameter
    private var accentColor: Color {
        if isRace || accent == .gold { return Color(hex: "FFC74D") }
        return Theme.violet
    }

    // Border tint: gold when accent/race resolves to gold; grey otherwise
    private var borderColor: Color {
        let isGold = isRace || accent == .gold
        return isGold ? Color(hex: "FFC74D").opacity(0.4) : Color(hex: "3A3A44")
    }

    // TO: standard ±2% label or Int(km.rounded())+"K"
    private var distanceLabel: String {
        let km = activity.distance / 1000
        let standards: [(km: Double, label: String)] = [
            (5.0, "5K"), (10.0, "10K"), (21.1, "하프"), (42.2, "풀")
        ]
        for (stdKm, lbl) in standards where abs(km - stdKm) / stdKm <= 0.02 { return lbl }
        return "\(Int(km.rounded()))K"
    }

    // GATE race distance: ±5% match (same tolerance as BundledRace.matchesDistance)
    private func raceDistanceLabel(for km: Double) -> String {
        let standards: [(Double, String)] = [
            (42.195, "FULL"), (21.0975, "HALF"), (10.0, "10K"), (5.0, "5K")
        ]
        for (std, lbl) in standards where abs(km - std) / max(std, 0.001) <= 0.05 { return lbl }
        return "\(Int(km.rounded()))K"
    }

    private var departureText: String { hasGPS ? departureName : "INDOOR" }
    private var arrivalText: String   { raceName ?? distanceLabel }

    // TIME: race gun time if available, else activity start
    private var timeText: String {
        if isRace, let st = raceStartTimeString, !st.isEmpty { return st }
        return activity.date.cardTimeString
    }

    // GATE: race distance badge or pace
    private var gateText: String {
        if isRace, let km = raceDistanceKm { return raceDistanceLabel(for: km) }
        return activity.formattedPace ?? "--'--\""
    }
    private var gateIcon: (name: String, color: Color)? {
        guard isRace else { return nil }
        return ("trophy.fill", Color(hex: "FFC74D"))
    }

    // Barcode: RACE or RUN
    private var barcodeString: String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        return "MIMO-\(isRace ? "RACE" : "RUN")-\(df.string(from: activity.date))"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(hex: "16161C")

            // Inner border sits BELOW content layer so canvas notch fills erase it cleanly
            RoundedRectangle(cornerRadius: 7)
                .stroke(borderColor, lineWidth: 1)
                .padding(Self.borderInset)

            VStack(alignment: .leading, spacing: 0) {
                topSection
                TicketPerforatedLine(borderInset: Self.borderInset)
                infoGrid
                Color(hex: "26262E").frame(height: 1).padding(.horizontal, Self.borderInset)
                Spacer(minLength: 0)
                barcodeStrip
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Top section

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Wordmark
            HStack(spacing: 6) {
                MIMOWordmark(size: 11, onMediaCard: true)
                if isRace {
                    Text("· RACE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Color(hex: "FFC74D").opacity(0.7))
                }
            }

            // FROM → TO
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    ticketLabel("FROM")
                    Text(departureText)
                        .font(.system(size: 22, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(accentColor)       // accent applies here
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("→")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Color(hex: "6E6E78"))
                    .padding(.horizontal, 8)

                VStack(alignment: .trailing, spacing: 3) {
                    ticketLabel("TO")
                    Text(arrivalText)
                        .font(.system(size: 22, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .lineLimit(isRace ? 2 : 1)          // long race names: 2 lines
                        .minimumScaleFactor(isRace ? 0.6 : 0.5)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    // MARK: - Info grid (2×3)

    private var infoGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ticketField(label: "DATE", value: activity.date.cardDateString)
                Spacer()
                ticketField(label: "TIME", value: timeText, trailingAlign: true)
            }
            HStack(spacing: 0) {
                ticketField(label: "SEAT", value: shoeName ?? "—")
                Spacer()
                ticketField(label: "GATE", value: gateText, trailingAlign: true,
                            icon: gateIcon?.name, iconColor: gateIcon?.color ?? .white)
            }
            HStack(spacing: 0) {
                ticketField(label: "DIST", value: activity.formattedDistance)
                Spacer()
                ticketField(label: "DURATION", value: activity.formattedDuration, trailingAlign: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Barcode strip

    private var barcodeStrip: some View {
        VStack(spacing: 6) {
            if hasGPS {
                TicketRouteBarcode(coordinates: routeCoordinates,
                                   lineColor: accentColor.opacity(0.85))  // accent applies here
                    .frame(width: Self.cardWidth * 0.80, height: Self.cardHeight * 0.10)
            } else if hasSplits {
                TicketSplitBarcode(splits: splits)
                    .frame(width: Self.cardWidth * 0.80, height: Self.cardHeight * 0.10)
            }
            Text(barcodeString)
                .font(.system(size: 7, weight: .regular, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Color(hex: "6E6E78"))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 20)
    }

    // MARK: - Label helpers

    private func ticketLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .tracking(3)
            .foregroundStyle(Color(hex: "6E6E78"))
    }

    @ViewBuilder
    private func ticketField(
        label: String,
        value: String,
        trailingAlign: Bool = false,
        icon: String? = nil,
        iconColor: Color = .white
    ) -> some View {
        VStack(alignment: trailingAlign ? .trailing : .leading, spacing: 3) {
            ticketLabel(label)
            HStack(spacing: 4) {
                if let i = icon {
                    Image(systemName: i)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(iconColor)
                }
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Perforated separator + notches

// Notch circles centred on the inner border line (x = borderInset, x = width − borderInset).
// Canvas bg-fill erases the border at each circle; arc outlines in border colour add the
// "punched paper" appearance. The canvas layer is above the border in ZStack, so fills work.

struct TicketPerforatedLine: View {
    var borderInset: CGFloat = 14
    private let notchRadius: CGFloat = 8
    private let borderColor = Color(hex: "3A3A44")
    private let cardBg      = Color(hex: "16161C")
    private let dashColor   = Color(hex: "2E2E3A")

    var body: some View {
        Canvas { ctx, size in
            let r    = notchRadius
            let midY = size.height / 2
            let lx   = borderInset
            let rx   = size.width - borderInset

            var dashPath = Path()
            dashPath.move(to: CGPoint(x: lx + r, y: midY))
            dashPath.addLine(to: CGPoint(x: rx - r, y: midY))
            ctx.stroke(dashPath, with: .color(dashColor),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            ctx.fill(Path(ellipseIn: CGRect(x: lx - r, y: midY - r, width: r*2, height: r*2)),
                     with: .color(cardBg))
            ctx.fill(Path(ellipseIn: CGRect(x: rx - r, y: midY - r, width: r*2, height: r*2)),
                     with: .color(cardBg))

            var leftArc = Path()
            leftArc.addArc(center: CGPoint(x: lx, y: midY), radius: r,
                           startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
            ctx.stroke(leftArc, with: .color(borderColor), style: StrokeStyle(lineWidth: 1))

            var rightArc = Path()
            rightArc.addArc(center: CGPoint(x: rx, y: midY), radius: r,
                            startAngle: .degrees(90), endAngle: .degrees(270), clockwise: true)
            ctx.stroke(rightArc, with: .color(borderColor), style: StrokeStyle(lineWidth: 1))
        }
        .frame(height: notchRadius * 2)
    }
}

// MARK: - Route barcode (GPS, force-stretched)
// Independent x/y scales → route fills full band dimensions, not aspect-ratio-preserving.
// lineColor is driven by the card's accentColor so race vs. normal vs. gold-accent all match.

private struct TicketRouteBarcode: View {
    let coordinates: [CLLocationCoordinate2D]
    var lineColor: Color = Theme.violet.opacity(0.85)

    var body: some View {
        Canvas { ctx, size in
            guard coordinates.count > 1 else { return }
            let lats = coordinates.map(\.latitude)
            let lons = coordinates.map(\.longitude)
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLon = lons.min(), let maxLon = lons.max() else { return }

            let latRange = max(maxLat - minLat, 0.0001)
            let lonRange = max(maxLon - minLon, 0.0001)
            let inset: CGFloat = 1
            let scaleX = (size.width  - inset * 2) / CGFloat(lonRange)
            let scaleY = (size.height - inset * 2) / CGFloat(latRange)

            let step = max(1, coordinates.count / 600)
            var path = Path()
            var moved = false
            for i in Swift.stride(from: 0, to: coordinates.count, by: step) {
                let c = coordinates[i]
                let pt = CGPoint(
                    x: inset + CGFloat(c.longitude - minLon) * scaleX,
                    y: inset + CGFloat(maxLat - c.latitude) * scaleY
                )
                if !moved { path.move(to: pt); moved = true }
                else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(lineColor),
                       style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Split barcode (treadmill fallback)
// 3 stripes per split (thick + filler + hairline); width ∝ pace, height ∝ speed.

private struct TicketSplitBarcode: View {
    let splits: [SplitData]
    private var shown: [SplitData] { Array(splits.prefix(24)) }

    var body: some View {
        Canvas { ctx, size in
            let data = shown
            guard !data.isEmpty else { return }

            let paces     = data.map(\.paceSecPerKm)
            let maxPace   = paces.max() ?? 360
            let minPace   = paces.min() ?? 180
            let paceRange = max(maxPace - minPace, 20)

            struct Stripe { let w: CGFloat; let h: CGFloat; let op: CGFloat }
            var stripes: [Stripe] = []
            for split in data {
                let t  = CGFloat((split.paceSecPerKm - minPace) / paceRange)
                let bh = size.height * (0.50 + 0.50 * (1.0 - t))
                let op: CGFloat = 0.40 + 0.60 * (1.0 - t)
                stripes.append(Stripe(w: 2.0 + t * 4.5,          h: bh,        op: op))
                stripes.append(Stripe(w: 1.0 + (1.0 - t) * 1.5,  h: bh * 0.65, op: op * 0.40))
                stripes.append(Stripe(w: 0.8,                     h: bh * 0.40, op: 0.22))
            }

            let gapPx    = CGFloat(0.8)
            let totalW   = stripes.map(\.w).reduce(0, +)
            let totalGap = CGFloat(stripes.count - 1) * gapPx
            let scale    = (size.width - totalGap) / max(totalW, 1)

            var x: CGFloat = 0
            for s in stripes {
                let bw   = max(s.w * scale, 0.5)
                let rect = CGRect(x: x, y: size.height - s.h, width: bw, height: s.h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 0),
                         with: .color(Theme.violet.opacity(s.op)))
                x += bw + gapPx
            }
        }
    }
}

// MARK: - Previews

#Preview("GPS 6.01km → 6K") {
    let activity = Activity(
        id: UUID(), type: .running, date: Date(),
        duration: 2220, distance: 6_010, calories: 312, avgHeartRate: 155
    )
    let coords = (0..<79).map { i -> CLLocationCoordinate2D in
        let a = Double(i) * 0.08
        return CLLocationCoordinate2D(latitude: 37.56 + sin(a) * 0.004,
                                      longitude: 127.00 + cos(a) * 0.018)
    }
    TicketCard(activity: activity, routeCoordinates: coords,
               shoeName: "Nike Pegasus", departureName: "종암동")
        .frame(width: 300, height: 375)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .preferredColorScheme(.dark).padding().background(Color(hex: "0D0D12"))
}

#Preview("GPS — Gold accent") {
    let activity = Activity(
        id: UUID(), type: .running, date: Date(),
        duration: 2220, distance: 6_010, calories: 312, avgHeartRate: 155
    )
    let coords = (0..<79).map { i -> CLLocationCoordinate2D in
        let a = Double(i) * 0.08
        return CLLocationCoordinate2D(latitude: 37.56 + sin(a) * 0.004,
                                      longitude: 127.00 + cos(a) * 0.018)
    }
    TicketCard(activity: activity, routeCoordinates: coords,
               shoeName: "Nike Pegasus", departureName: "종암동", accent: .gold)
        .frame(width: 300, height: 375)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .preferredColorScheme(.dark).padding().background(Color(hex: "0D0D12"))
}

#Preview("Treadmill") {
    let activity = Activity(
        id: UUID(), type: .running, date: Date(),
        duration: 2580, distance: 7_050, calories: 380, avgHeartRate: 161
    )
    let paceSecs: [Double] = [260, 254, 258, 252, 264, 256, 248]
    let splits = (1...7).map { i -> SplitData in
        SplitData(id: i, distanceM: i < 7 ? 1000 : 50, duration: paceSecs[i - 1],
                  avgHeartRate: 158 + i, avgCadence: 172, avgPower: nil,
                  avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil)
    }
    TicketCard(activity: activity, splits: splits, shoeName: "Adidas Adizero")
        .frame(width: 300, height: 375)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .preferredColorScheme(.dark).padding().background(Color(hex: "0D0D12"))
}

#Preview("Race — 춘천마라톤 (FULL)") {
    let activity = Activity(
        id: UUID(), type: .running, date: Date(),
        duration: 13338, distance: 42_195, calories: 2840, avgHeartRate: 162
    )
    let raceCoords = (0..<380).map { i -> CLLocationCoordinate2D in
        let a = Double(i) * 0.05
        return CLLocationCoordinate2D(latitude: 37.88 + sin(a * 0.7) * 0.012,
                                      longitude: 127.73 + cos(a * 0.3) * 0.035)
    }
    TicketCard(activity: activity, routeCoordinates: raceCoords,
               raceName: "춘천마라톤", shoeName: "Brooks Ghost",
               departureName: "춘천시청", raceDistanceKm: 42.195,
               raceStartTimeString: "08:00")
        .frame(width: 300, height: 375)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .preferredColorScheme(.dark).padding().background(Color(hex: "0D0D12"))
}

#Preview("Race — 긴 대회명 (HALF)") {
    let activity = Activity(
        id: UUID(), type: .running, date: Date(),
        duration: 7724, distance: 21_097, calories: 1480, avgHeartRate: 158
    )
    TicketCard(activity: activity, raceName: "제33회 경주벚꽃마라톤",
               shoeName: "Saucony Endorphin", departureName: "경주",
               raceDistanceKm: 21.0975, raceStartTimeString: "08:30")
        .frame(width: 300, height: 375)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .preferredColorScheme(.dark).padding().background(Color(hex: "0D0D12"))
}
