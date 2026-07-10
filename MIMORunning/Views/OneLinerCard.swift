import SwiftUI
import UIKit

// MARK: - OneLinerFont
//
// 3 OFL 1.1-licensed Korean handwriting fonts + SF Pro Black (앱 숫자 폰트).
//
// | Case   | File                         | PostScript name  | sizeScale | Style         |
// |--------|------------------------------|------------------|-----------|---------------|
// | round  | Gaegu-Regular.ttf            | Gaegu-Regular    | 1.28      | 둥글고 귀여운 |
// | pen    | NanumPenScript-Regular.ttf   | NanumPen-Regular | 1.00      | 펜글씨/차분한 |
// | brush  | NanumBrushScript-Regular.ttf | NanumBrush       | 1.46      | 붓/거친       |
// | gothic | (system SF Pro Black)        | —                | 0.96      | 견고딕/임팩트 |
//
// sizeScale: 실측 capHeight 기반 정규화 (기준=나눔펜 20.22pt @30pt).
//   pen=20.22 (ref×1.00) | round=15.75 (×1.28) | brush=13.80 (×1.46) | gothic=21.14 (×0.96)
// gothic은 시스템 폰트 API(swiftUIFont/uiFont)를 사용하므로 fontName 미사용.
// chipLabel은 해당 폰트로 렌더링되어 선택 전 미리보기 역할.

enum OneLinerFont: String, CaseIterable, Codable {
    case round   // Gaegu              — 둥글고 귀여운
    case pen     // Nanum Pen          — 펜글씨/차분한
    case brush   // Nanum Brush        — 붓/거친
    case gothic  // SF Pro Black       — 앱 숫자폰트/견고딕/임팩트

    // PostScript 이름 (gothic은 시스템 API 경유로 미사용)
    var fontName: String {
        switch self {
        case .round:  return "Gaegu-Regular"
        case .pen:    return "NanumPen-Regular"
        case .brush:  return "NanumBrush"
        case .gothic: return ""
        }
    }

    var chipLabel: String {
        switch self {
        case .round:  return "개구"
        case .pen:    return "나눔펜"
        case .brush:  return "나눔붓"
        case .gothic: return "고딕"
        }
    }

    // 나눔펜 capHeight(20.22pt @30pt) 기준 정규화.
    // round/brush는 1.00 유지 (손글씨 특성상 시각적으로 용인).
    // gothic(SF Pro Black)은 capH=21.14 + Black 획 두께 시각 보정으로 0.88.
    var sizeScale: CGFloat {
        self == .gothic ? 0.88 : 1.00
    }

    // SwiftUI Font — gothic은 .system(weight:.black) 사용
    func swiftUIFont(size: CGFloat) -> Font {
        self == .gothic ? .system(size: size, weight: .black) : .custom(fontName, size: size)
    }

    // UIKit Font — 영상/슬라이드 렌더러용
    func uiFont(size: CGFloat) -> UIFont {
        if self == .gothic { return UIFont.systemFont(ofSize: size, weight: .black) }
        return UIFont(name: fontName, size: size) ?? UIFont.systemFont(ofSize: size)
    }
}

// MARK: - OneLinerTextColor

enum OneLinerTextColor: String, CaseIterable, Codable {
    case white, violet, gold, lime

    var color: Color {
        switch self {
        case .white:  return .white
        case .violet: return Color(hex: "9B7DFC")
        case .gold:   return Color(hex: "FFC74D")
        case .lime:   return Theme.power
        }
    }

    var uiColor: UIColor {
        switch self {
        case .white:  return .white
        case .violet: return UIColor(red: 0x9B/255.0, green: 0x7D/255.0, blue: 0xFC/255.0, alpha: 1)
        case .gold:   return UIColor(red: 0xFF/255.0, green: 0xC7/255.0, blue: 0x4D/255.0, alpha: 1)
        case .lime:   return UIColor(red: 0xA3/255.0, green: 0xE6/255.0, blue: 0x35/255.0, alpha: 1)
        }
    }

    var chipLabel: String {
        switch self {
        case .white:  return AppLanguage.shared.s("흰색", "White")
        case .violet: return AppLanguage.shared.s("바이올렛", "Violet")
        case .gold:   return AppLanguage.shared.s("골드", "Gold")
        case .lime:   return AppLanguage.shared.s("라임", "Lime")
        }
    }
}

// MARK: - TextSizeLevel

enum TextSizeLevel: String, CaseIterable, Codable {
    case small  = "small"
    case medium = "medium"
    case large  = "large"

    var scale: CGFloat {
        switch self {
        case .small:  return 0.8
        case .medium: return 1.0
        case .large:  return 1.2
        }
    }

    var chipLabel: String {
        switch self {
        case .small:  return AppLanguage.shared.s("소", "S")
        case .medium: return AppLanguage.shared.s("중", "M")
        case .large:  return AppLanguage.shared.s("대", "L")
        }
    }
}

// MARK: - AppearanceMode
//
// 텍스트 등장 방식 (택1). 타이핑=기본(MIMO 정체성). 페이드=문장 전체 투명→불투명.

enum AppearanceMode: String, CaseIterable, Codable {
    case typing = "typing"  // 글자 하나씩 순차 등장 (기본)
    case fade   = "fade"    // 문장 전체 페이드인 (배정 시간 앞 30%)

    var chipLabel: String {
        switch self {
        case .typing: return AppLanguage.shared.s("타이핑", "Typing")
        case .fade:   return AppLanguage.shared.s("페이드", "Fade")
        }
    }
}

// MARK: - DecorEffect
//
// 페이드 모드 선택 시에만 활성화되는 꾸밈 효과.
// 타이핑 모드에서는 UI 숨김 (타이핑은 그 자체로 완결).
// wobble = 지속 반복 ±0.8° / pop = 페이드 완료 후 1회 1.2→1.0 스프링

enum DecorEffect: String, CaseIterable, Codable {
    case none   = "none"
    case wobble = "wobble"
    case pop    = "pop"

    var chipLabel: String {
        switch self {
        case .none:   return AppLanguage.shared.s("없음",   "None")
        case .wobble: return AppLanguage.shared.s("흔들림", "Shake")
        case .pop:    return AppLanguage.shared.s("팝",     "Pop")
        }
    }
}

// MARK: - EffectTextView
//
// Bold shadow is always the baseline.
// appearanceMode: fade → 0.5s 페이드인 on appear (SwiftUI 미리보기용; 영상은 UIKit).
// decorEffect: fade 모드에서만 유효.
// outline: 독립 가독성 토글, 두 등장 방식 모두 적용.

struct EffectTextView: View {
    let text:           String
    let font:           Font
    let lineSpacing:    CGFloat
    let alignment:      TextAlignment
    let color:          Color
    let appearanceMode: AppearanceMode
    let decorEffect:    DecorEffect
    let outline:        Bool

    @State private var opacity:     Double = 1.0
    @State private var popAppeared: Bool   = false
    @State private var wobblePhase: Bool   = false

    var body: some View {
        Text(text)
            .font(font)
            .lineSpacing(lineSpacing)
            .multilineTextAlignment(alignment)
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.85), radius: 0.7, x: 0, y: 0)
            .shadow(color: .black.opacity(0.55), radius: 5, x: 1, y: 2)
            .shadow(color: .black.opacity(outline ? 0.55 : 0), radius: 0.5, x:  1.5, y:  0)
            .shadow(color: .black.opacity(outline ? 0.55 : 0), radius: 0.5, x: -1.5, y:  0)
            .shadow(color: .black.opacity(outline ? 0.55 : 0), radius: 0.5, x:  0,   y:  1.5)
            .shadow(color: .black.opacity(outline ? 0.55 : 0), radius: 0.5, x:  0,   y: -1.5)
            .lineLimit(2)
            .scaleEffect(decorEffect == .pop ? (popAppeared ? 1.0 : 1.2) : 1.0)
            .rotationEffect(decorEffect == .wobble ? .degrees(wobblePhase ? 0.8 : -0.8) : .zero)
            .opacity(opacity)
            .onAppear {
                if appearanceMode == .fade {
                    opacity = 0
                    withAnimation(.easeIn(duration: 0.5)) { opacity = 1.0 }
                    if decorEffect == .pop {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.55).delay(0.5)) {
                            popAppeared = true
                        }
                    }
                }
                if decorEffect == .wobble {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        wobblePhase = true
                    }
                }
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
    var sizeLevel: TextSizeLevel = .medium
    var appearanceMode: AppearanceMode = .typing
    var decorEffect:    DecorEffect    = .none
    var outline:        Bool           = false
    var showDate: Bool = true
    var showBackground: Bool = true
    /// When true, text + date are pinned together at the bottom-left (caption layout).
    /// The `position` parameter is ignored in this mode.
    var captionMode: Bool = false
    /// Full-video title overlay (영상·슬라이드 미리보기). Empty = hidden.
    var videoTitle: String = ""
    var titleStyle: OneLinerTitleStyle = OneLinerTitleStyle()

    private var cardDate: Date { activity?.date ?? displayDate }

    static let cardWidth:  CGFloat = 300
    static let cardHeight: CGFloat = 375

    private var baseFontSize: CGFloat { 20 * fontChoice.sizeScale * sizeLevel.scale }
    private var lineSpacing:  CGFloat { baseFontSize * 0.1 }

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

            // ── Full-video title (영상·슬라이드 정지 미리보기) ─
            if !videoTitle.isEmpty { titleOverlay }

            // ── Hero text + date ───────────────────────────────
            if captionMode {
                captionContent
                if showDate {
                    Text(cardDate.oneLinerDateString)
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(.white.opacity(0.55))
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 14)
                        .padding(.bottom, 12)
                }
            } else {
                if text.isEmpty {
                    if showBackground {
                        Text(AppLanguage.shared.s("한마디를 입력해 주세요", "Enter your one-liner"))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.35))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    EffectTextView(
                        text: text, font: fontChoice.swiftUIFont(size: baseFontSize),
                        lineSpacing: lineSpacing, alignment: textAlignment,
                        color: textColor.color, appearanceMode: appearanceMode,
                        decorEffect: decorEffect, outline: outline
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, textTopInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
                }
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
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
    }

    // Full-video title overlay — always horizontally centered, vertically by titleStyle.position.
    // Paddings mirror the export layout at vScale=1 (card width = 300pt).
    private var titleOverlay: some View {
        let fontSize = 20 * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale
        let topPad:    CGFloat = titleStyle.position.isTop    ? 28 : 0
        let bottomPad: CGFloat = titleStyle.position.isBottom ? 14 : 0
        let vAlign: Alignment  = titleStyle.position.isTop    ? .top
                               : titleStyle.position.isBottom ? .bottom : .center
        return Text(videoTitle)
            .font(titleStyle.fontChoice.swiftUIFont(size: fontSize))
            .multilineTextAlignment(.center)
            .foregroundStyle(titleStyle.textColor.color)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.55), radius: 5, x: 1, y: 2)
            .shadow(color: .black.opacity(titleStyle.outline ? 0.55 : 0), radius: 0.5, x:  1.5, y: 0)
            .shadow(color: .black.opacity(titleStyle.outline ? 0.55 : 0), radius: 0.5, x: -1.5, y: 0)
            .shadow(color: .black.opacity(titleStyle.outline ? 0.55 : 0), radius: 0.5, x: 0, y:  1.5)
            .shadow(color: .black.opacity(titleStyle.outline ? 0.55 : 0), radius: 0.5, x: 0, y: -1.5)
            .padding(.horizontal, 10)
            .padding(.top, topPad)
            .padding(.bottom, bottomPad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vAlign)
            .allowsHitTesting(false)
    }

    // Text just above date — the text+date unit moves together to `position`.
    // Horizontal alignment follows the position column; vertical follows the row.
    @ViewBuilder
    private var captionContent: some View {
        let isTrailing = (position == .topTrailing || position == .trailing || position == .bottomTrailing)
        let hAlign: HorizontalAlignment = position.isLeading ? .leading : isTrailing ? .trailing : .center
        let tAlign: TextAlignment       = position.isLeading ? .leading : isTrailing ? .trailing : .center
        VStack(alignment: hAlign, spacing: 4) {
            if text.isEmpty {
                if showBackground {
                    Text(AppLanguage.shared.s("한마디를 입력해 주세요", "Enter your one-liner"))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                }
            } else {
                EffectTextView(
                    text: text, font: fontChoice.swiftUIFont(size: baseFontSize),
                    lineSpacing: lineSpacing, alignment: tAlign,
                    color: textColor.color, appearanceMode: appearanceMode,
                    decorEffect: decorEffect, outline: outline
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
        .padding(.horizontal, 14)
        .padding(.top, position.isTop ? 32 : 12)
        // 하단 위치: 날짜(11pt + 12pt 패딩 + 여백) 위로 문구가 올라가도록 여유 확보
        .padding(.bottom, position.isBottom ? 34 : 12)
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
