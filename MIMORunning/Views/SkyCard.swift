import SwiftUI

// MARK: - SkyCard
// Data source : run start time only — no HealthKit read; SkyPalette computes the gradient.
// Reused      : CardVisual.cardTextShadow / cardLargeTextShadow.
// §7 compliance: no performance judgment — time-of-day aesthetics only.
// Accent      : applies to hero time-range string colour (.none = sky-adaptive, default).

/// "그날의 하늘" — a share card whose background is the sky gradient for the
/// run's start time, featuring a time-of-day decoration and a hero time-range
/// headline ("17:41 – 18:43").
struct SkyCard: View {
    let activity: Activity
    var weather:  WeatherSnapshot? = nil
    var shoeName: String?          = nil
    var accent:   CardAccent       = .none

    static let cardWidth:  CGFloat = 300
    static let cardHeight: CGFloat = 375

    // MARK: Derived

    private var skyColors:   [Color]        { SkyPalette.colors(for: activity.date) }
    private var decoration:  SkyDecoration? { SkyPalette.decorations(for: activity.date) }
    private var useDarkText: Bool           { SkyPalette.isDarkTextNeeded(for: activity.date) }

    private var textColor:    Color { useDarkText ? Color(hex: "1A1A22") : .white }
    private var subTextColor: Color {
        useDarkText ? Color(hex: "1A1A22").opacity(0.72) : Color(hex: "EDEDED")
    }

    private var timeRangeColor: Color {
        switch accent {
        case .none:   return textColor
        case .violet: return Theme.violet
        case .gold:   return Color(hex: "FFC74D")
        }
    }

    private var isOvercast: Bool {
        guard let icon = weather?.systemIcon else { return false }
        return icon.contains("cloud") || icon.contains("rain") ||
               icon.contains("drizzle") || icon.contains("snow")
    }

    // "17:41 – 18:43"
    private var timeRangeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let end = activity.date.addingTimeInterval(activity.duration)
        return "\(fmt.string(from: activity.date)) – \(fmt.string(from: end))"
    }

    // "10.02km · 1:02:02 · 6'11""
    private var statsString: String {
        let km = activity.distance / 1000
        let dist = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
        if let pace = activity.formattedPace {
            return "\(dist)km · \(activity.formattedDuration) · \(pace)"
        }
        return "\(dist)km · \(activity.formattedDuration)"
    }

    // MARK: Body

    var body: some View {
        ZStack {
            // ── Background: gradient + optional overcast tint ──────
            ZStack {
                LinearGradient(
                    colors: skyColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
                if isOvercast {
                    Color(hex: "8A8A92").opacity(0.20)
                }
            }
            .saturation(isOvercast ? 0.78 : 1.0)

            // ── Decoration: sun / moon / stars ─────────────────────
            if let deco = decoration {
                decorationView(deco)
                    .allowsHitTesting(false)
            }

            // ── Content ────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                wordmark
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                Spacer()

                VStack(alignment: .leading, spacing: 5) {
                    Text(timeRangeString)
                        .font(.system(size: 36, weight: .bold).width(.condensed))
                        .tracking(2)
                        .foregroundStyle(timeRangeColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .cardLargeTextShadow()

                    Text(statsString)
                        .font(.system(size: 14, weight: .medium).width(.condensed))
                        .foregroundStyle(subTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .cardTextShadow()

                    bottomRow
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Subviews

    private var wordmark: some View {
        HStack(spacing: 0) {
            Text("MIMO")
                .font(.system(size: 9, weight: .black))
                .tracking(2)
                .foregroundStyle(.white)         // top gradient is always dark enough
            Text(" RUNNING")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.violet)
        }
        .cardTextShadow()
    }

    private var bottomRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                Text(activity.date.cardDateString)
                Text(activity.date.weekdayCharKo).foregroundStyle(Theme.time)
                Text(activity.date.cardTimeString)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(textColor.opacity(0.80))

            if let w = weather {
                HStack(spacing: 3) {
                    Image(systemName: w.systemIcon).font(.system(size: 8))
                    Text(activity.temperatureC.map { String(format: "%.0f°C", $0) } ?? w.formattedTemp).font(.system(size: 8, weight: .medium))
                }
                .foregroundStyle(textColor.opacity(0.65))
                .padding(.leading, 6)
            }

            if let shoe = shoeName {
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "shoe.fill").font(.system(size: 8))
                    Text(shoe)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(textColor.opacity(0.75))
            }
        }
        .cardTextShadow()
    }

    // MARK: Decoration views

    @ViewBuilder
    private func decorationView(_ deco: SkyDecoration) -> some View {
        switch deco {
        case .sun(let h):  sunView(height: h)
        case .moon:        moonView()
        case .stars:       starsView()
        }
    }

    private func sunView(height: CGFloat) -> some View {
        let size = SkyCard.cardWidth * 0.35          // 105 pt
        let y    = SkyCard.cardHeight * (0.65 - Double(height) * 0.50)
        return RadialGradient(
            colors: [.white.opacity(0.88), .white.opacity(0.28), .clear],
            center: .center,
            startRadius: 0,
            endRadius: size / 2
        )
        .frame(width: size, height: size)
        .position(x: SkyCard.cardWidth * 0.70, y: CGFloat(y))
    }

    private func moonView() -> some View {
        let size = SkyCard.cardWidth * 0.12          // 36 pt
        return ZStack {
            RadialGradient(
                colors: [.white.opacity(0.20), .clear],
                center: .center,
                startRadius: 0,
                endRadius: size * 1.4
            )
            .frame(width: size * 2.8, height: size * 2.8)
            Circle()
                .fill(Color.white.opacity(0.90))
                .frame(width: size, height: size)
        }
        .position(x: SkyCard.cardWidth * 0.74, y: SkyCard.cardHeight * 0.22)
    }

    private func starsView() -> some View {
        Canvas { ctx, size in
            for s in starPoints(in: size) {
                ctx.fill(
                    Path(ellipseIn: CGRect(
                        x: s.x - s.r, y: s.y - s.r,
                        width: s.r * 2, height: s.r * 2
                    )),
                    with: .color(Color.white.opacity(s.opacity))
                )
            }
        }
        .frame(width: SkyCard.cardWidth, height: SkyCard.cardHeight)
    }

    private struct StarPoint { let x, y, r, opacity: CGFloat }

    private func starPoints(in size: CGSize) -> [StarPoint] {
        // Seed from UUID bytes for a stable, per-run star layout.
        let u = activity.id.uuid
        var seed = UInt32(u.0) | (UInt32(u.1) << 8) |
                   (UInt32(u.2) << 16) | (UInt32(u.3) << 24)

        func lcg() -> CGFloat {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return CGFloat(seed >> 16) / CGFloat(0xFFFF)
        }

        return (0..<26).map { _ in
            let x = lcg() * size.width
            let y = lcg() * size.height * 0.72   // stars stay in upper 72%
            let r: CGFloat       = 0.6 + lcg() * 1.3
            let opacity: CGFloat = 0.35 + lcg() * 0.55
            return StarPoint(x: x, y: y, r: r, opacity: opacity)
        }
    }
}
