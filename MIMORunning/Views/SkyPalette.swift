import SwiftUI

// MARK: - SkyDecoration

/// Visual decoration hint for the sky share card at a given time of day.
public enum SkyDecoration: Equatable {
    /// Sun at the given normalised height (0 = horizon, 1 = zenith at solar noon).
    case sun(CGFloat)
    /// Moon prominent — early/mid night (20:00–00:00).
    case moon
    /// Star-filled sky — late night / pre-dawn (00:00–04:00).
    case stars
}

// MARK: - SkyPalette

/// Produces time-of-day sky gradients (3 stops, top → bottom) and decoration
/// hints for the Sky share card, driven purely by the run start time.
public struct SkyPalette {

    // MARK: Internal colour model

    private struct RGB {
        let r, g, b: Double

        /// Initialise from a 6-digit hex string (with or without leading `#`).
        init(_ hex: String) {
            let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            let v = UInt64(s, radix: 16) ?? 0
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >>  8) & 0xFF) / 255
            b = Double( v        & 0xFF) / 255
        }

        private init(r: Double, g: Double, b: Double) {
            self.r = r; self.g = g; self.b = b
        }

        func lerp(_ other: RGB, t: Double) -> RGB {
            let tc = max(0, min(1, t))
            return RGB(r: r + (other.r - r) * tc,
                       g: g + (other.g - g) * tc,
                       b: b + (other.b - b) * tc)
        }

        var color: Color { Color(red: r, green: g, blue: b) }
    }

    // MARK: Slot definitions
    //
    // 6 cyclic time slots. Night wraps: 20:00 → (midnight) → 04:00.
    // Index:  0=Dawn  1=Morning  2=Day  3=LateAfternoon  4=Sunset  5=Night

    private static let slotStartHours: [Double] = [4, 6, 8, 16, 18, 20]

    private static let slotColors: [[RGB]] = [
        ["0B1A3A", "3A3A6E", "E8734A"].map { RGB($0) },   // Dawn          04:00–06:00
        ["4A7BC4", "9BBCE8", "F5D9A8"].map { RGB($0) },   // Morning       06:00–08:00
        ["2E6BC4", "7FB2E8", "C9E4F5"].map { RGB($0) },   // Day           08:00–16:00
        ["3A6BB4", "E8A05A", "F5C88A"].map { RGB($0) },   // Late afternoon 16:00–18:00
        ["2A2A5E", "B4527A", "F08A4A"].map { RGB($0) },   // Sunset        18:00–20:00
        ["060612", "14142E", "26264A"].map { RGB($0) },   // Night         20:00–04:00
    ]

    /// Half the blend window at each slot boundary (15 min each side = 30 min total).
    private static let blendHalf = 0.25

    // MARK: - Public API

    /// Three gradient stop colours (top → bottom) for the given run start time.
    /// Slot boundaries blend linearly over a 30-minute window so there are no
    /// abrupt colour jumps at transition times.
    public static func colors(for date: Date) -> [Color] {
        rawRGBs(for: date).map(\.color)
    }

    /// Whether the bottom gradient stop is bright enough (luminance > 0.6) to
    /// warrant dark text (`Color(hex: "1A1A22")`) instead of white.
    public static func isDarkTextNeeded(for date: Date) -> Bool {
        guard let last = rawRGBs(for: date).last else { return false }
        let lum = 0.2126 * last.r + 0.7152 * last.g + 0.0722 * last.b
        return lum > 0.6
    }

    private static func rawRGBs(for date: Date) -> [RGB] {
        let t = hourDecimal(from: date)

        for (i, boundary) in slotStartHours.enumerated() {
            var dist = t - boundary
            if dist >  12 { dist -= 24 }
            if dist < -12 { dist += 24 }

            guard abs(dist) <= blendHalf else { continue }

            let factor = (dist + blendHalf) / (2 * blendHalf)
            let prev   = (i + slotColors.count - 1) % slotColors.count
            return (0..<slotColors[0].count).map { j in
                slotColors[prev][j].lerp(slotColors[i][j], t: factor)
            }
        }

        return slotColors[pureSlotIndex(for: t)]
    }

    /// Sky decoration for the given run start time.
    /// Returns `nil` for dawn and sunset, where neither sun nor night objects
    /// are prominent enough to feature.
    public static func decorations(for date: Date) -> SkyDecoration? {
        let t = hourDecimal(from: date)

        // Dawn (04–06) and Sunset (18–20): transitional sky, no decoration.
        if (t >= 4 && t < 6) || (t >= 18 && t < 20) { return nil }

        // Night (20–04): moon for early night, stars for late night / pre-dawn.
        if t >= 20 || t < 4 { return t >= 20 ? .moon : .stars }

        // Sun visible 06–18: height 0 at horizon, 1.0 at solar noon (12:00).
        let height = max(0.0, 1.0 - abs(t - 12.0) / 6.0)
        return .sun(CGFloat(height))
    }

    // MARK: - Private helpers

    private static func hourDecimal(from date: Date) -> Double {
        let cal = Calendar.current
        return Double(cal.component(.hour,   from: date))
             + Double(cal.component(.minute, from: date)) / 60.0
    }

    private static func pureSlotIndex(for t: Double) -> Int {
        switch t {
        case 4  ..< 6:  return 0   // Dawn
        case 6  ..< 8:  return 1   // Morning
        case 8  ..< 16: return 2   // Day
        case 16 ..< 18: return 3   // Late afternoon
        case 18 ..< 20: return 4   // Sunset
        default:        return 5   // Night (t ≥ 20 or t < 4)
        }
    }
}

// MARK: - Preview

#Preview("Sky gradients by hour") {
    HStack(spacing: 8) {
        ForEach([5, 7, 12, 17, 19, 22], id: \.self) { hour in
            SkyGradientSwatch(hour: hour)
        }
    }
    .padding(16)
    .background(Color.black)
}

private struct SkyGradientSwatch: View {
    let hour: Int

    private var date: Date {
        Calendar.current.date(
            bySettingHour: hour, minute: 0, second: 0, of: Date()
        ) ?? Date()
    }

    var body: some View {
        VStack(spacing: 6) {
            LinearGradient(
                colors: SkyPalette.colors(for: date),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 44, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottomLeading) {
                if let deco = SkyPalette.decorations(for: date) {
                    decoIcon(deco).padding(5)
                }
            }

            Text(String(format: "%02d:00", hour))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }

    @ViewBuilder
    private func decoIcon(_ deco: SkyDecoration) -> some View {
        switch deco {
        case .sun(let h):
            Image(systemName: "sun.max.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.yellow)
                .opacity(Double(0.5 + h * 0.5))
        case .moon:
            Image(systemName: "moon.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.85))
        case .stars:
            Image(systemName: "star.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }
}
