import SwiftUI
import UIKit

// MARK: - OneLinerFont
//
// 3 OFL 1.1-licensed Korean handwriting fonts bundled in MIMORunning/Fonts/.
//
// | Case  | File                         | PostScript name  | Style          |
// |-------|------------------------------|------------------|----------------|
// | round | Gaegu-Regular.ttf            | Gaegu-Regular    | 둥글고 귀여운  |
// | pen   | NanumPenScript-Regular.ttf   | NanumPen-Regular | 펜글씨/차분한  |
// | brush | NanumBrushScript-Regular.ttf | NanumBrush       | 붓/거친        |
//
// chipLabel is rendered *in the font itself* so users preview before tapping.

enum OneLinerFont: String, CaseIterable, Codable {
    case round   // Gaegu           — 둥글고 귀여운
    case pen     // Nanum Pen       — 펜글씨/차분한
    case brush   // Nanum Brush     — 붓/거친

    var fontName: String {
        switch self {
        case .round: return "Gaegu-Regular"
        case .pen:   return "NanumPen-Regular"
        case .brush: return "NanumBrush"
        }
    }

    var chipLabel: String {
        switch self {
        case .round: return "개구"
        case .pen:   return "나눔펜"
        case .brush: return "나눔붓"
        }
    }

    // Optical-size correction: brush strokes appear smaller at the same pt size
    var sizeScale: CGFloat {
        switch self {
        case .round: return 1.0
        case .pen:   return 1.05
        case .brush: return 1.18
        }
    }
}

// MARK: - OneLinerTextColor

enum OneLinerTextColor: String, CaseIterable, Codable {
    case white, violet, gold

    var color: Color {
        switch self {
        case .white:  return .white
        case .violet: return Color(hex: "9B7DFC")
        case .gold:   return Color(hex: "FFC74D")
        }
    }

    var uiColor: UIColor {
        switch self {
        case .white:  return .white
        case .violet: return UIColor(red: 0x9B/255.0, green: 0x7D/255.0, blue: 0xFC/255.0, alpha: 1)
        case .gold:   return UIColor(red: 0xFF/255.0, green: 0xC7/255.0, blue: 0x4D/255.0, alpha: 1)
        }
    }

    var chipLabel: String {
        switch self {
        case .white:  return AppLanguage.shared.s("흰색", "White")
        case .violet: return AppLanguage.shared.s("바이올렛", "Violet")
        case .gold:   return AppLanguage.shared.s("골드", "Gold")
        }
    }
}

// MARK: - OneLinerCard
//
// Full-bleed photo or sky-gradient card with wordmark (MIMO / RUNNING) at top-left.
// The user's message is the only hero. Optional date stamp at bottom-trailing.
// Background priority: backgroundPhoto → SkyPalette gradient (activity start time).
// showBackground: false renders content-only with transparent background (for video overlay).

struct OneLinerCard: View {
    var activity: Activity? = nil
    /// Date used for the date stamp and gradient when `activity` is nil (rest-day mode).
    var displayDate: Date = Date()
    var backgroundPhoto: UIImage? = nil
    var text: String = ""
    var position: CardPosition = .center
    var textColor: OneLinerTextColor = .white
    var fontChoice: OneLinerFont = .pen
    var showDate: Bool = true
    var showBackground: Bool = true

    private var cardDate: Date { activity?.date ?? displayDate }

    static let cardWidth:  CGFloat = 300
    static let cardHeight: CGFloat = 375

    private var baseFontSize: CGFloat { 24 * fontChoice.sizeScale }
    private var lineSpacing:  CGFloat { baseFontSize * 0.4 }

    private var textAlignment: TextAlignment {
        switch position {
        case .topTrailing, .trailing, .bottomTrailing: return .trailing
        case .topLeading,  .leading,  .bottomLeading:  return .leading
        default: return .center
        }
    }

    // Top-row positions need extra padding to clear the wordmark (~28pt zone)
    private var textTopInset: CGFloat { position.isTop ? 28 : 0 }

    var body: some View {
        ZStack {
            // ── Background ─────────────────────────────────────
            if showBackground { background }

            // ── Wordmark: MIMO (white) + RUNNING (violet) ──────
            wordmark

            // ── Hero text ──────────────────────────────────────
            if text.isEmpty {
                if showBackground {
                    Text(AppLanguage.shared.s("한마디를 입력해 주세요", "Enter your one-liner"))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text(text)
                    .font(.custom(fontChoice.fontName, size: baseFontSize))
                    .lineSpacing(lineSpacing)
                    .multilineTextAlignment(textAlignment)
                    .foregroundStyle(textColor.color)
                    .shadow(color: .black.opacity(0.55), radius: 5, x: 1, y: 2)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                    .padding(.top, textTopInset)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: position.alignment
                    )
            }

            // ── Date stamp ─────────────────────────────────────
            if showDate {
                Text(cardDate.oneLinerDateString)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 14)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
    }

    @ViewBuilder
    private var background: some View {
        if let photo = backgroundPhoto {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: Self.cardWidth, height: Self.cardHeight)
                .clipped()
                .overlay(Color.black.opacity(0.22))
        } else {
            LinearGradient(
                colors: SkyPalette.colors(for: cardDate),
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(Color.black.opacity(0.12))
        }
    }

    private var wordmark: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 14)
        .padding(.top, 12)
    }
}

// MARK: - Date helper

private extension Date {
    var oneLinerDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy. M. d."
        return f.string(from: self)
    }
}

// MARK: - Previews

private func _registerFonts() { FontLoader.registerBundledFonts() }

private let _previewActivity = Activity(
    id: UUID(),
    type: .running,
    date: Date(),
    duration: 3724,
    distance: 6010,
    calories: nil,
    avgHeartRate: nil
)

#Preview("펜 / 그라데이션 배경") {
    let _ = _registerFonts()
    OneLinerCard(
        activity: _previewActivity,
        text: "꽃밭을 달리는데\n난 땀밭",
        position: .center,
        textColor: .white,
        fontChoice: .pen
    )
    .frame(width: 300, height: 375)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .preferredColorScheme(.dark)
}

#Preview("개구 / 골드 / 상단") {
    let _ = _registerFonts()
    OneLinerCard(
        activity: _previewActivity,
        text: "꽃밭을 달리는데\n난 땀밭",
        position: .top,
        textColor: .gold,
        fontChoice: .round
    )
    .frame(width: 300, height: 375)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .preferredColorScheme(.dark)
}

#Preview("나눔붓 / 하단 좌측") {
    let _ = _registerFonts()
    OneLinerCard(
        activity: _previewActivity,
        text: "꽃밭을 달리는데\n난 땀밭",
        position: .bottomLeading,
        textColor: .violet,
        fontChoice: .brush
    )
    .frame(width: 300, height: 375)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .preferredColorScheme(.dark)
}
