import SwiftUI

// MARK: - Variant

/// MiniMe character state — drives background colors, pose symbol, and badge icon.
/// Computed from InsightTheme + WorkoutType (+ optional mood for detail).
/// All rendering is in MiniMeView so the variant logic stays independent of UI code.
enum MiniMeVariant {
    case running        // 일반 달리기 기본
    case sprinting      // 인터벌 — 고강도
    case longDistance   // 롱런 — 지구력
    case recovery       // 이지런 / 회복
    case tempo          // 템포런 — 리듬
    case celebrating    // 첫성취 / PR / 대회 완주
    case rainy          // 악조건 극복 (비/바람)
    case tough          // 힘든 느낌 (mood: tough)

    /// Primary selection rule: theme wins over workout type; mood is tiebreaker.
    static func from(
        theme: InsightTheme,
        workoutType: WorkoutType,
        mood: Mood? = nil
    ) -> MiniMeVariant {
        switch theme {
        case .firstAchievement, .recordImproved, .raceDay:
            return .celebrating
        case .adverseCondition:
            return .rainy
        case .recovery:
            return .recovery
        default:
            break
        }
        if mood == .tough { return .tough }
        switch workoutType {
        case .interval: return .sprinting
        case .longRun:  return .longDistance
        case .easy:     return .recovery
        case .tempo:    return .tempo
        case .general:  return .running
        }
    }

    // MARK: Art properties

    var mainSymbol: String {
        switch self {
        case .sprinting:                              "figure.highintensity.intervaltraining"
        case .recovery:                               "figure.walk"
        case .running, .longDistance, .tempo,
             .celebrating, .rainy, .tough:            "figure.run"
        }
    }

    var badgeSymbol: String? {
        switch self {
        case .celebrating:  "star.fill"
        case .sprinting:    "bolt.fill"
        case .recovery:     "leaf.fill"
        case .tempo:        "waveform"
        case .rainy:        "cloud.rain.fill"
        case .tough:        "flame.fill"
        default:            nil
        }
    }

    fileprivate var gradientColors: [Color] {
        switch self {
        case .running:      [Color(hex: "7C5CFC"), Color(hex: "4636B8")]
        case .sprinting:    [Color(hex: "FF6B35"), Color(hex: "7C3FC0")]
        case .longDistance: [Color(hex: "6349CC"), Color(hex: "1A1060")]
        case .recovery:     [Color(hex: "34A8C6"), Color(hex: "3D6BB5")]
        case .tempo:        [Color(hex: "00C9A7"), Color(hex: "5C46C0")]
        case .celebrating:  [Color(hex: "F4B942"), Color(hex: "7C5CFC")]
        case .rainy:        [Color(hex: "4A90D4"), Color(hex: "2C3866")]
        case .tough:        [Color(hex: "BF3535"), Color(hex: "7C3FC0")]
        }
    }

    fileprivate var badgeColor: Color {
        switch self {
        case .celebrating:  Color(hex: "F4B942")
        case .sprinting:    Color(hex: "FFA040")
        case .recovery:     Color(hex: "30D158")
        case .tempo:        Color(hex: "00C9A7")
        case .rainy:        Color(hex: "64B8F0")
        case .tough:        Color(hex: "FF6B6B")
        default:            .white
        }
    }
}

// MARK: - View

/// First-generation MiniMe: SwiftUI primitives + SF Symbols on a violet-themed gradient tile.
/// Swap variant.mainSymbol / gradientColors here when upgrading to hand-drawn illustrations.
struct MiniMeView: View {
    let variant: MiniMeVariant
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26)
                .fill(
                    LinearGradient(
                        colors: variant.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Subtle inner glow ring
            RoundedRectangle(cornerRadius: size * 0.26)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)

            // Running figure
            Image(systemName: variant.mainSymbol)
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(.white)
                .offset(y: size * 0.03)

            // Badge icon — top-right corner
            if let badge = variant.badgeSymbol {
                Image(systemName: badge)
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundStyle(variant.badgeColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(size * 0.10)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Contextual MiniMe (insight card — animated overlays per variant)

/// Wraps a base avatar (custom image or MiniMeView) with variant-driven decorations and
/// lightweight animations: spring entry, continuous float, pulsing glow, confetti burst.
struct ContextualMiniMeView: View {
    var customImage: UIImage?
    var variant: MiniMeVariant
    var size: CGFloat = 58

    @State private var appeared    = false
    @State private var floating    = false
    @State private var pulsing     = false
    @State private var confettiScale:   CGFloat = 0
    @State private var confettiOpacity: Double  = 0

    private let confettiColors: [Color] = [
        Color(hex: "F4B942"), Color(hex: "FF6B35"),
        Color(hex: "7C5CFC"), Color(hex: "30D158"),
        Color(hex: "64B8F0"), Color(hex: "FF9BC0"),
        Color(hex: "F4B942"), Color(hex: "00C9A7"),
    ]

    var body: some View {
        ZStack {
            glowRing
            contextDecoration
            baseAvatar
                .scaleEffect(appeared ? 1.0 : 0.65)
                .opacity(appeared ? 1.0 : 0.0)
                .offset(y: floating ? -2 : 0)
            badgeOverlay
        }
        // Keep layout frame at avatar size; decorations overflow without affecting layout.
        .frame(width: size, height: size)
        .onAppear { startAnimations() }
    }

    // MARK: Glow ring

    @ViewBuilder
    private var glowRing: some View {
        let show = variant == .celebrating || variant == .sprinting || variant == .tempo
        if show {
            Circle()
                .fill(glowColor.opacity(pulsing ? 0.22 : 0.05))
                .frame(width: size * 1.55, height: size * 1.55)
        }
    }

    // MARK: Context decoration per variant

    @ViewBuilder
    private var contextDecoration: some View {
        switch variant {
        case .sprinting:    speedLines
        case .celebrating:  confettiLayer
        case .rainy:        rainDrops
        case .tough:        sweatDrops
        case .longDistance: distanceTrail
        default:            EmptyView()
        }
    }

    // MARK: Base avatar

    @ViewBuilder
    private var baseAvatar: some View {
        let shadowOpacity = pulsing ? 0.42 : 0.10
        let shadowRadius  = pulsing ? size * 0.18 : size * 0.05
        if let img = customImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(glowColor.opacity(0.38), lineWidth: 1.5))
                .shadow(color: glowColor.opacity(shadowOpacity), radius: shadowRadius)
        } else {
            MiniMeView(variant: variant, size: size)
                .shadow(color: glowColor.opacity(shadowOpacity), radius: shadowRadius)
        }
    }

    // MARK: Badge overlays

    @ViewBuilder
    private var badgeOverlay: some View {
        switch variant {
        case .celebrating:
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.22, weight: .bold))
                .foregroundStyle(Color(hex: "F4B942"))
                .scaleEffect(pulsing ? 1.18 : 0.82)
                .opacity(appeared ? 1.0 : 0.0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(size * 0.02)
        case .sprinting:
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.20, weight: .bold))
                .foregroundStyle(Color(hex: "FFA040"))
                .scaleEffect(pulsing ? 1.12 : 0.90)
                .opacity(appeared ? 1.0 : 0.0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(size * 0.02)
        case .tempo:
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: size * 0.17))
                .foregroundStyle(Color(hex: "00C9A7").opacity(pulsing ? 0.85 : 0.30))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        case .recovery:
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.18))
                .foregroundStyle(Color(hex: "30D158").opacity(0.80))
                .opacity(appeared ? 1.0 : 0.0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(size * 0.02)
        default:
            EmptyView()
        }
    }

    // MARK: Speed lines (interval/sprinting)

    private var speedLines: some View {
        ZStack {
            lineCapsule(dx: -0.52, dy: -0.10, w: 0.38, opacity: 0.35)
            lineCapsule(dx: -0.54, dy:  0.08, w: 0.26, opacity: 0.25)
            lineCapsule(dx: -0.50, dy:  0.22, w: 0.16, opacity: 0.18)
        }
        .rotationEffect(.degrees(-3))
    }

    private func lineCapsule(dx: CGFloat, dy: CGFloat, w: CGFloat, opacity: Double) -> some View {
        Capsule()
            .fill(Color(hex: "FF6B35").opacity(opacity))
            .frame(width: size * w, height: 1.5)
            .offset(x: size * dx, y: size * dy)
    }

    // MARK: Distance trail (long run)

    private var distanceTrail: some View {
        Capsule()
            .fill(LinearGradient(
                colors: [Color(hex: "6349CC").opacity(0),
                         Color(hex: "6349CC").opacity(0.22),
                         Color(hex: "6349CC").opacity(0)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(width: size * 1.9, height: size * 0.20)
            .offset(y: size * 0.40)
    }

    // MARK: Confetti burst (celebrating)

    private var confettiLayer: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * 45.0 * .pi / 180.0
                let dist  = size * 0.68 * confettiScale
                Group {
                    if i % 2 == 0 {
                        Circle().frame(width: size * 0.09)
                    } else {
                        RoundedRectangle(cornerRadius: 1)
                            .frame(width: size * 0.06, height: size * 0.11)
                            .rotationEffect(.degrees(Double(i) * 30))
                    }
                }
                .foregroundStyle(confettiColors[i])
                .offset(x: cos(angle) * dist, y: sin(angle) * dist)
            }
        }
        .opacity(confettiOpacity)
    }

    // MARK: Rain drops (adverse condition)

    private var rainDrops: some View {
        ZStack {
            raindrop(dx: -0.44, dy: -0.46, opacity: 0.65)
            raindrop(dx:  0.03, dy: -0.50, opacity: 0.50)
            raindrop(dx:  0.40, dy: -0.42, opacity: 0.55)
        }
    }

    private func raindrop(dx: CGFloat, dy: CGFloat, opacity: Double) -> some View {
        Image(systemName: "drop.fill")
            .font(.system(size: size * 0.13))
            .foregroundStyle(Color(hex: "64B8F0").opacity(opacity))
            .offset(x: size * dx, y: size * dy)
    }

    // MARK: Sweat drops (tough)

    private var sweatDrops: some View {
        ZStack {
            sweatdrop(dx:  0.42, dy: -0.32, opacity: 0.72)
            sweatdrop(dx:  0.50, dy: -0.06, opacity: 0.50)
        }
    }

    private func sweatdrop(dx: CGFloat, dy: CGFloat, opacity: Double) -> some View {
        Image(systemName: "drop.fill")
            .font(.system(size: size * 0.12))
            .foregroundStyle(Color(hex: "64C8F0").opacity(opacity))
            .rotationEffect(.degrees(20))
            .offset(x: size * dx, y: size * dy)
    }

    // MARK: Glow color per variant

    private var glowColor: Color {
        switch variant {
        case .celebrating:  Color(hex: "F4B942")
        case .sprinting:    Color(hex: "FF6B35")
        case .recovery:     Color(hex: "34A8C6")
        case .tempo:        Color(hex: "00C9A7")
        case .rainy:        Color(hex: "64B8F0")
        case .tough:        Color(hex: "FF6B6B")
        case .longDistance: Color(hex: "6349CC")
        default:            Color(hex: "7C5CFC")
        }
    }

    // MARK: Animation sequence

    private func startAnimations() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.60).delay(0.08)) {
            appeared = true
        }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.60)) {
            floating = true
        }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.50)) {
            pulsing = true
        }
        guard variant == .celebrating else { return }
        // Burst outward then fade — requires iOS 17 withAnimation completion
        withAnimation(.spring(response: 0.42, dampingFraction: 0.55).delay(0.30)) {
            confettiScale   = 1.0
            confettiOpacity = 1.0
        } completion: {
            withAnimation(.easeOut(duration: 0.55)) {
                confettiScale   = 2.2
                confettiOpacity = 0.0
            }
        }
    }
}
