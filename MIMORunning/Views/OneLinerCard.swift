import SwiftUI
import UIKit

// MARK: - OneLinerFont
//
// 3종 폰트: 나눔펜(손글씨 감성) + Apple SD Gothic Neo 2종(가독성).
// Apple SD Gothic Neo는 iOS 시스템 번들 폰트 — 앱 내 파일 불필요.
//
// | Case        | PostScript name          | capH@30pt | sizeScale | Style                |
// |-------------|--------------------------|-----------|-----------|----------------------|
// | pen         | NanumPen-Regular         | 20.22     | 1.000     | 펜글씨/차분한        |
// | gothic      | AppleSDGothicNeo-Bold    | 21.45     | 0.943     | 고딕/가독성          |
// | blackGothic | AppleSDGothicNeo-Heavy   | 21.03     | 0.961     | 블랙고딕/테두리 최적 |
//
// sizeScale = pen.capH / font.capH (CoreText 실측값 기준).
//   같은 sizeLevel에서 세 폰트의 시각적 대문자 높이가 동일해짐.
//   pen은 획이 얇아 광학적으로 작아 보일 수 있으므로 필요 시 소폭 상향 가능(현재 1.000).
// 테두리(hasBorder)는 gothic/blackGothic 전용. pen + 테두리 → blackGothic 자동 스냅(ClipTrimView).
// boldSwiftUIFont/boldUIFont: pen=Regular(볼드 없음), gothic/blackGothic=동일 폰트(이미 최대 굵기).

enum OneLinerFont: String, CaseIterable, Codable {
    case pen         // NanumPen              — 손글씨/차분한
    case gothic      // AppleSDGothicNeo-Bold  — 고딕/가독성
    case blackGothic // AppleSDGothicNeo-Heavy — 블랙고딕/테두리 최적

    // PostScript 이름
    var fontName: String {
        switch self {
        case .pen:         return "NanumPen-Regular"
        case .gothic:      return "AppleSDGothicNeo-Bold"
        case .blackGothic: return "AppleSDGothicNeo-Heavy"
        }
    }

    var chipLabel: String {
        switch self {
        case .pen:         return "나눔펜"
        case .gothic:      return "고딕"
        case .blackGothic: return "블랙고딕"
        }
    }

    // 나눔펜 capH(20.22pt @30pt) 기준 정규화 — CoreText 실측.
    // scale = penCapH / fontCapH → 같은 sizeLevel에서 세 폰트의 capH 픽셀이 동일.
    var sizeScale: CGFloat {
        switch self {
        case .pen:         return 1.000  // capH 20.22 (기준)
        case .gothic:      return 0.943  // capH 21.45 → 20.22/21.45 = 0.9427
        case .blackGothic: return 0.961  // capH 21.03 → 20.22/21.03 = 0.9615
        }
    }

    /// 기준 폰트 크기(pt) — scale=1(카드폭 300pt / vScale=1)에서의 값.
    /// 클립 텍스트·타이틀·편집 프리뷰·export 모두 이 상수를 공유.
    static let basePt: CGFloat = 20

    // SwiftUI Font
    func swiftUIFont(size: CGFloat) -> Font {
        .custom(fontName, size: size)
    }

    // UIKit Font — 영상/슬라이드 렌더러용
    func uiFont(size: CGFloat) -> UIFont {
        switch self {
        case .pen:
            return UIFont(name: fontName, size: size) ?? UIFont.systemFont(ofSize: size)
        case .gothic:
            return UIFont(name: fontName, size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
        case .blackGothic:
            return UIFont(name: "AppleSDGothicNeo-Heavy", size: size)
                ?? UIFont(name: "AppleSDGothicNeo-ExtraBold", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .heavy)
        }
    }

    // 멀티 클립용 — 최대 굵기. pen=Regular(볼드 없음), gothic/blackGothic=동일.
    func boldSwiftUIFont(size: CGFloat) -> Font { .custom(fontName, size: size) }

    func boldUIFont(size: CGFloat) -> UIFont { uiFont(size: size) }

    /// 합성 볼드 stroke 폭 (음수 = fill+동색 stroke → 잉크 두께 증가).
    /// pen만 적용 (NanumPen은 볼드 웨이트 없음).
    /// gothic/blackGothic은 실제 굵은 웨이트 → 0 반환.
    /// 1080px export 기준: basePt=20 × vScale=3.6 = 72px → stroke ≈ −2.45
    func syntheticBoldStroke(for size: CGFloat) -> CGFloat {
        self == .pen ? -(size * 0.034) : 0
    }

    // 구 rawValue 마이그레이션: round → gothic, brush → blackGothic
    static func migrate(_ rawValue: String?) -> OneLinerFont {
        switch rawValue {
        case "round":  return .gothic
        case "brush":  return .blackGothic
        default:       return rawValue.flatMap { OneLinerFont(rawValue: $0) } ?? .pen
        }
    }
}

// MARK: - OneLinerTextColor

enum OneLinerTextColor: String, CaseIterable, Codable {
    case white, violet, gold, lime, blue

    var color: Color {
        switch self {
        case .white:  return .white
        case .violet: return Color(hex: "9B7DFC")
        case .gold:   return Color(hex: "FFC74D")
        case .lime:   return Theme.power
        case .blue:   return Color(hex: "4FC3F7")
        }
    }

    var uiColor: UIColor {
        switch self {
        case .white:  return .white
        case .violet: return UIColor(red: 0x9B/255.0, green: 0x7D/255.0, blue: 0xFC/255.0, alpha: 1)
        case .gold:   return UIColor(red: 0xFF/255.0, green: 0xC7/255.0, blue: 0x4D/255.0, alpha: 1)
        case .lime:   return UIColor(red: 0xA3/255.0, green: 0xE6/255.0, blue: 0x35/255.0, alpha: 1)
        case .blue:   return UIColor(red: 0x4F/255.0, green: 0xC3/255.0, blue: 0xF7/255.0, alpha: 1)
        }
    }

    var chipLabel: String {
        switch self {
        case .white:  return AppLanguage.shared.s("흰색", "White")
        case .violet: return AppLanguage.shared.s("바이올렛", "Violet")
        case .gold:   return AppLanguage.shared.s("골드", "Gold")
        case .lime:   return AppLanguage.shared.s("라임", "Lime")
        case .blue:   return AppLanguage.shared.s("블루", "Blue")
        }
    }

    // 글자색에 자동 대비되는 테두리 색 (밝은 색→검정, 어두운·진한 색→흰색)
    var borderSwiftColor: Color {
        switch self {
        case .white, .gold, .lime: return .black
        case .violet, .blue:       return .white.opacity(0.60)
        }
    }

    var borderUIColor: UIColor {
        switch self {
        case .white, .gold, .lime: return .black
        case .violet, .blue:       return UIColor.white.withAlphaComponent(0.60)
        }
    }

    // fontSize 에 곱하는 오프셋 계수. 대+pen(20pt) 기준: 검정=1.1pt, 흰색=1.02pt.
    // 흰색 테두리는 어두운 배경에서 광학적으로 번져 보이므로 더 낮게 설정.
    var borderOffsetFactor: CGFloat {
        switch self {
        case .white, .gold, .lime: return 0.055   // 검정 테두리
        case .violet, .blue:       return 0.051   // 흰색 테두리 — blooming 보정
        }
    }
}

// MARK: - TextSizeLevel

enum TextSizeLevel: String, CaseIterable, Codable {
    case small  = "small"
    case medium = "medium"
    case large  = "large"
    case xlarge = "xlarge"  // 특대

    var scale: CGFloat {
        switch self {
        case .small:  return 0.65
        case .medium: return 0.8
        case .large:  return 1.0
        case .xlarge: return 1.25
        }
    }

    var chipLabel: String {
        switch self {
        case .small:  return AppLanguage.shared.s("소", "S")
        case .medium: return AppLanguage.shared.s("중", "M")
        case .large:  return AppLanguage.shared.s("대", "L")
        case .xlarge: return AppLanguage.shared.s("특대", "XL")
        }
    }
}

// MARK: - AppearanceMode
//
// 텍스트 등장 방식 (택1). 타이핑=기본(MIMO 정체성). 페이드=문장 전체 투명→불투명.

enum AppearanceMode: String, CaseIterable, Codable {
    case typing = "typing"  // 글자 하나씩 순차 등장 (기본)
    case fade   = "fade"    // 문장 전체 페이드인 (배정 시간 앞 30%)
    case flyIn  = "flyIn"   // 옆에서 슬라이드 인 (0.3s easeOut)

    var chipLabel: String {
        switch self {
        case .typing: return AppLanguage.shared.s("타이핑", "Typing")
        case .fade:   return AppLanguage.shared.s("페이드", "Fade")
        case .flyIn:  return AppLanguage.shared.s("날아오기", "Fly In")
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

// MARK: - FlyInDirection
//
// 날아오기(flyIn) 모드 전용 방향 선택.
// 켄 번즈 방향 반대로 자동 설정(짝수=trailing, 홀수=leading); 사용자가 칩으로 변경 가능.

enum FlyInDirection: String, CaseIterable, Codable {
    case leading  = "leading"   // 왼쪽에서 슬라이드 인
    case trailing = "trailing"  // 오른쪽에서 슬라이드 인

    var chipLabel: String {
        switch self {
        case .leading:  return AppLanguage.shared.s("왼쪽에서", "From Left")
        case .trailing: return AppLanguage.shared.s("오른쪽에서", "From Right")
        }
    }
}

// MARK: - ReadabilityStyle
//
// 가독성 처리 배타 선택 (없음 / 외곽선 / 음영판). 한 번에 하나만 활성.
// plate = 문구 뒤 어두운 rounded rect (불투명도 55%, 상하좌우 패딩, 코너 6pt).

enum ReadabilityStyle: String, CaseIterable, Codable {
    case none    = "none"
    case outline = "outline"
    case plate   = "plate"

    var chipLabel: String {
        switch self {
        case .none:    return AppLanguage.shared.s("없음",   "None")
        case .outline: return AppLanguage.shared.s("테두리", "Border")
        case .plate:   return AppLanguage.shared.s("음영판", "Plate")
        }
    }
}

// MARK: - PlateColorPreset
//
// 음영판(plate) 가독성 모드에서 사용하는 판+글자 색상 쌍.
// 판 불투명도: 흰 판만 0.80, 나머지 0.55.

enum PlateColorPreset: String, CaseIterable, Codable {
    case blackWhite = "blackWhite"
    case greenWhite = "greenWhite"
    case blueWhite  = "blueWhite"
    case redWhite   = "redWhite"
    case whiteBlack = "whiteBlack"

    var plateOpacity: Double { self == .whiteBlack ? 0.80 : 0.55 }

    var plateSwiftColor: Color {
        switch self {
        case .blackWhite: return Color.black
        case .greenWhite: return Color(hex: "1B5E20")
        case .blueWhite:  return Color(hex: "1565C0")
        case .redWhite:   return Color(hex: "B71C1C")
        case .whiteBlack: return Color.white
        }
    }

    var textSwiftColor: Color {
        switch self {
        case .blackWhite, .greenWhite, .blueWhite, .redWhite: return Color.white
        case .whiteBlack: return Color.black
        }
    }

    var plateUIColor: UIColor {
        switch self {
        case .blackWhite: return .black
        case .greenWhite: return UIColor(red: 0x1B/255.0, green: 0x5E/255.0, blue: 0x20/255.0, alpha: 1)
        case .blueWhite:  return UIColor(red: 0x15/255.0, green: 0x65/255.0, blue: 0xC0/255.0, alpha: 1)
        case .redWhite:   return UIColor(red: 0xB7/255.0, green: 0x1C/255.0, blue: 0x1C/255.0, alpha: 1)
        case .whiteBlack: return .white
        }
    }

    var textUIColor: UIColor {
        switch self {
        case .blackWhite, .greenWhite, .blueWhite, .redWhite: return .white
        case .whiteBlack: return .black
        }
    }

    var plateBgColor: Color        { plateSwiftColor.opacity(plateOpacity) }
    var plateUIColorWithAlpha: UIColor { plateUIColor.withAlphaComponent(plateOpacity) }
}

// MARK: - EffectTextView
//
// appearanceMode: fade → 0.5s 페이드인 on appear (SwiftUI 미리보기용; 영상은 UIKit).
// decorEffect: fade 모드에서만 유효.
// hasBorder: 독립 토글 — 8방향 오프셋 복제(blur 0, 크리스프 글리프 외곽선).
// plateOn:   독립 토글 — 줄별 음영판(rounded rect 배경).
// 둘 다 켤 수 있음. 소프트 그림자 없음.

struct EffectTextView: View {
    let text:             String
    let font:             Font
    let lineSpacing:      CGFloat
    let alignment:        TextAlignment
    let color:            Color
    let appearanceMode:   AppearanceMode
    let decorEffect:      DecorEffect
    var hasBorder:        Bool          = false
    var plateOn:          Bool          = false
    var flyDirection:     FlyInDirection = .trailing
    var plateBgColor:     Color         = Color.black.opacity(0.55)
    var syntheticBoldStroke: CGFloat    = 0
    var borderColor:      Color         = .clear
    var borderOffset:     CGFloat       = 0     // 호출측: max(1.5, baseFontSize * 0.10)

    @State private var opacity:     Double    = 1.0
    @State private var popAppeared: Bool      = false
    @State private var wobblePhase: Bool      = false
    @State private var lineOffsets: [CGFloat] = []

    // fill 색으로 Text 반환 (합성 볼드 포함, stroke 없음)
    private func baseText(_ string: String) -> Text {
        guard syntheticBoldStroke != 0 else {
            return Text(string).font(font).foregroundStyle(color)
        }
        var attr = AttributedString(string)
        attr.font = font
        attr.foregroundColor = color
        attr.uiKit.strokeWidth = syntheticBoldStroke
        attr.uiKit.strokeColor = UIColor(color)
        return Text(attr)
    }

    // 테두리색으로 채운 Text (8방향 배경용, blur 없음)
    private func borderText(_ string: String) -> Text {
        guard syntheticBoldStroke != 0 else {
            return Text(string).font(font).foregroundStyle(borderColor)
        }
        var attr = AttributedString(string)
        attr.font = font
        attr.foregroundColor = borderColor
        attr.uiKit.strokeWidth = syntheticBoldStroke
        attr.uiKit.strokeColor = UIColor(borderColor)
        return Text(attr)
    }

    // 8방향 오프셋 복제 — 크리스프 글리프 외곽선(blur 0)
    // baseText를 anchor로 .background에 테두리 복사본을 렌더.
    // ZStack 대신 background 사용 → 오프셋 복제가 텍스트 layout frame에 영향 없음.
    @ViewBuilder
    private func borderedContent(_ string: String) -> some View {
        let o = borderOffset
        baseText(string)
            .background {
                Group {
                    borderText(string).offset(x: -o, y: -o)
                    borderText(string).offset(x:  o, y: -o)
                    borderText(string).offset(x: -o, y:  o)
                    borderText(string).offset(x:  o, y:  o)
                    borderText(string).offset(x: -o, y:  0)
                    borderText(string).offset(x:  o, y:  0)
                    borderText(string).offset(x:  0, y: -o)
                    borderText(string).offset(x:  0, y:  o)
                }
            }
    }

    // 한 줄 텍스트 콘텐츠 (hasBorder 처리 통합)
    @ViewBuilder
    private func lineContent(_ line: String) -> some View {
        if hasBorder { borderedContent(line) } else { baseText(line) }
    }

    var body: some View {
        Group {
            if appearanceMode == .flyIn {
                perLineFlyView()
            } else if plateOn {
                plateView
            } else {
                singleTextView()
            }
        }
        // pop/wobble은 fade 모드 전용 — 다른 애니메이션 모드에서는 잔여 변형 없이 1.0 고정
        .scaleEffect(appearanceMode == .fade && decorEffect == .pop
            ? (popAppeared ? 1.0 : 1.25)
            : 1.0)
        .rotationEffect(appearanceMode == .fade && decorEffect == .wobble
            ? .degrees(wobblePhase ? 1.5 : -1.5)
            : .zero)
        .opacity(opacity)
        .onAppear {
            if appearanceMode == .fade {
                opacity = 0
                withAnimation(.easeIn(duration: 0.5)) { opacity = 1.0 }
                if decorEffect == .pop {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.45).delay(0.5)) {
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

    // 날아오기 모드: 줄별 stagger offset
    @ViewBuilder
    private func perLineFlyView() -> some View {
        let lines  = text.components(separatedBy: "\n")
        let hAlign: HorizontalAlignment = alignment == .trailing ? .trailing
            : alignment == .leading ? .leading : .center
        let initX:  CGFloat = flyDirection == .trailing ? 280 : -280
        VStack(alignment: hAlign, spacing: plateOn ? 3 : lineSpacing) {
            ForEach(lines.indices, id: \.self) { i in
                let line = lines[i]
                if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let off: CGFloat = i < lineOffsets.count ? lineOffsets[i] : initX
                    if plateOn {
                        lineContent(line)
                            .lineLimit(1).minimumScaleFactor(0.65)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(plateBgColor))
                            .offset(x: off)
                    } else {
                        lineContent(line)
                            .multilineTextAlignment(alignment)
                            .lineLimit(1).minimumScaleFactor(0.65)
                            .offset(x: off)
                    }
                }
            }
        }
        .onAppear {
            let initOff: CGFloat = flyDirection == .trailing ? 280 : -280
            lineOffsets = Array(repeating: initOff, count: lines.count)
            for i in lines.indices {
                guard !lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                withAnimation(.easeOut(duration: 0.3).delay(Double(i) * 0.25)) {
                    lineOffsets[i] = 0
                }
            }
        }
    }

    // 음영판: 줄별 rounded rect 배경
    @ViewBuilder
    private var plateView: some View {
        let hAlign: HorizontalAlignment = alignment == .trailing ? .trailing
            : alignment == .leading ? .leading : .center
        let lines = text.components(separatedBy: "\n")
        VStack(alignment: hAlign, spacing: 3) {
            ForEach(lines.indices, id: \.self) { i in
                if !lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lineContent(lines[i])
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(plateBgColor))
                }
            }
        }
        .background {
            #if DEBUG
            auditRenderHeight("음영판")
            #endif
        }
    }

    // 테두리/없음: 줄별 VStack + lineLimit(1).
    // 이전: lineLimit(2) 단일 Text → 짧은 줄까지 긴 줄 기준으로 minimumScaleFactor 강제 축소.
    // 수정: plateView와 동일한 줄 분할·독립 축소. 줄마다 개별적으로 fit 결정.
    @ViewBuilder
    private func singleTextView() -> some View {
        let lines  = text.components(separatedBy: "\n")
        let hAlign: HorizontalAlignment = alignment == .trailing ? .trailing
            : alignment == .leading ? .leading : .center
        VStack(alignment: hAlign, spacing: lineSpacing) {
            ForEach(lines.indices, id: \.self) { i in
                if !lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lineContent(lines[i])
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
        }
        .background {
            #if DEBUG
            auditRenderHeight("테두리/없음")
            #endif
        }
    }

#if DEBUG
    @ViewBuilder
    private func auditRenderHeight(_ label: String) -> some View {
        GeometryReader { g in
            Color.clear
                .onAppear {
                    print("[SizeAudit-Render] \(label) h=\(String(format:"%.1f",g.size.height))pt  w=\(String(format:"%.1f",g.size.width))pt")
                }
                .onChange(of: g.size) { _, sz in
                    print("[SizeAudit-Render] \(label) → h=\(String(format:"%.1f",sz.height))pt  w=\(String(format:"%.1f",sz.width))pt")
                }
        }
    }
#endif
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
    var hasBorder:      Bool           = false
    var plateOn:        Bool           = false
    var flyDirection:   FlyInDirection = .trailing
    var plateColorPreset: PlateColorPreset = .blackWhite
    var showDate: Bool = true
    var showBackground: Bool = true
    /// When true, text + date are pinned together at the bottom-left (caption layout).
    /// The `position` parameter is ignored in this mode.
    var captionMode: Bool = false
    /// Full-video title overlay (영상·슬라이드 미리보기). Empty = hidden.
    var videoTitle: String = ""
    var titleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    /// 카드 높이 오버라이드. nil=기본 375(4:5). 영상/슬라이드 9:16 프리뷰는 300*16/9=533.33 전달.
    /// 폭은 300 고정(폰트 기준 유지) → 호출부에서 scaleEffect로 목표 크기에 맞춤.
    var cardHeightOverride: CGFloat? = nil

    private var cardDate: Date { activity?.date ?? displayDate }

    static let cardWidth:  CGFloat = 300
    static let cardHeight: CGFloat = 375

    private var baseFontSize: CGFloat { OneLinerFont.basePt * fontChoice.sizeScale * sizeLevel.scale }
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
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white)   // 밝은 흰색
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                        // 날짜: 워드마크(MIMO RUNNING) 줄 오른쪽 → 하단 문구와 겹침 방지
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 14)
                        .padding(.top, 12)
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
                    // 문구 블록 (날짜는 아래에서 우상단 별도 배치)
                    EffectTextView(
                        text: text, font: fontChoice.swiftUIFont(size: baseFontSize),
                        lineSpacing: lineSpacing, alignment: textAlignment,
                        color: plateOn ? plateColorPreset.textSwiftColor : textColor.color,
                        appearanceMode: appearanceMode,
                        decorEffect: decorEffect,
                        hasBorder: hasBorder, plateOn: plateOn,
                        flyDirection: flyDirection,
                        plateBgColor: plateColorPreset.plateBgColor,
                        syntheticBoldStroke: fontChoice.syntheticBoldStroke(for: baseFontSize),
                        borderColor: hasBorder ? textColor.borderSwiftColor : .clear,
                        borderOffset: hasBorder ? max(0.8, baseFontSize * textColor.borderOffsetFactor) : 0
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, textTopInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
                    if showDate {
                        // 날짜: 워드마크(MIMO RUNNING) 줄 오른쪽 → 문구와 겹침 방지
                        Text(cardDate.oneLinerDateString)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.trailing, 14)
                            .padding(.top, 12)
                    }
                }
            }
        }
        .frame(width: Self.cardWidth, height: cardHeightOverride ?? Self.cardHeight)
    }

    // Full-video title overlay — 9위치(3×3 그리드) 완전 반영.
    // Paddings use the same scale1080 basis as ClipTrimView (safeTop=260px, safeBottom=270px @1080px).
    private var titleOverlay: some View {
        let scale1080: CGFloat = Self.cardWidth / 1080.0   // 300/1080 ≈ 0.2778
        let fontSize   = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale
        let topPad:    CGFloat = titleStyle.position.isTop    ? (CardVisual.videoSafeTop + 4) * scale1080 : 0
        let bottomPad: CGFloat = titleStyle.position.isBottom ? CardVisual.videoSafeBottom    * scale1080 : 0
        let titleTextAlign: TextAlignment = {
            switch titleStyle.position {
            case .topLeading, .leading, .bottomLeading:    return .leading
            case .topTrailing, .trailing, .bottomTrailing: return .trailing
            default: return .center
            }
        }()
        return makeTitleView(videoTitle, fontSize: fontSize)
            .multilineTextAlignment(titleTextAlign)
            .lineLimit(2)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 10)
            .padding(.top, topPad)
            .padding(.bottom, bottomPad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: titleStyle.position.alignment)
            .allowsHitTesting(false)
    }

    /// 제목 채움 Text (테두리 없을 때 합성 볼드 포함).
    private func makeTitleBaseText(_ string: String, fontSize: CGFloat) -> Text {
        let synStroke = titleStyle.fontChoice.syntheticBoldStroke(for: fontSize)
        let tColor    = titleStyle.textColor.color
        let tFont     = titleStyle.fontChoice.swiftUIFont(size: fontSize)
        guard synStroke != 0 else {
            return Text(string).font(tFont).foregroundStyle(tColor)
        }
        var attr = AttributedString(string)
        attr.font = tFont; attr.foregroundColor = tColor
        attr.uiKit.strokeWidth = synStroke; attr.uiKit.strokeColor = UIColor(tColor)
        return Text(attr)
    }

    /// 제목 테두리색 Text (8방향 배경용).
    private func makeTitleBorderText(_ string: String, fontSize: CGFloat) -> Text {
        Text(string)
            .font(titleStyle.fontChoice.swiftUIFont(size: fontSize))
            .foregroundStyle(titleStyle.textColor.borderSwiftColor)
    }

    /// 제목 뷰 — 테두리는 8방향 오프셋 ZStack (EffectTextView와 동일 기법, §15.3).
    @ViewBuilder
    private func makeTitleView(_ string: String, fontSize: CGFloat) -> some View {
        let hasBorder = titleStyle.outline
        let o: CGFloat = hasBorder ? max(0.8, fontSize * titleStyle.textColor.borderOffsetFactor) : 0
        if hasBorder {
            ZStack {
                Group {
                    makeTitleBorderText(string, fontSize: fontSize).offset(x: -o, y: -o)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x:  o, y: -o)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x: -o, y:  o)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x:  o, y:  o)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x: -o, y:  0)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x:  o, y:  0)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x:  0, y: -o)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x:  0, y:  o)
                }
                makeTitleBaseText(string, fontSize: fontSize)
            }
        } else {
            makeTitleBaseText(string, fontSize: fontSize)
        }
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
                    color: plateOn ? plateColorPreset.textSwiftColor : textColor.color,
                    appearanceMode: appearanceMode,
                    decorEffect: decorEffect,
                    hasBorder: hasBorder, plateOn: plateOn,
                    flyDirection: flyDirection,
                    plateBgColor: plateColorPreset.plateBgColor,
                    syntheticBoldStroke: fontChoice.syntheticBoldStroke(for: baseFontSize),
                    borderColor: hasBorder ? textColor.borderSwiftColor : .clear,
                    borderOffset: hasBorder ? max(0.8, baseFontSize * textColor.borderOffsetFactor) : 0
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
                .frame(width: Self.cardWidth, height: cardHeightOverride ?? Self.cardHeight)
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

// MARK: - SizeAudit (DEBUG)
//
// 3폰트 × 4사이즈 × 3애니메이션에서 정착 시 cap height가 동일한지 검증.
// 앱 기동 후 콘솔에서 "[SizeAudit]" 검색 → 같은 sizeLevel의 capH(px)가 ±1px 이내여야 함.
// 실행: OneLinerCard 프리뷰 or 임의 onAppear에서 OneLinerSizeAudit.run() 호출.

#if DEBUG
enum OneLinerSizeAudit {
    static func run(screenScale: CGFloat = 3) {
        // 애니메이션 독립성: 최종 정착 scale은 항상 1.0.
        // typing=offset 없음 / fade=opacity만 / flyIn=offset만 → 잔여 scale 변형 없음.
        let animLabel = ["typing", "fade", "flyIn"]
        print("[SizeAudit] === 폰트 × 사이즈 capH 정착값 (px @ \(Int(screenScale))x) ===")
        print("[SizeAudit] 애니메이션(\(animLabel.joined(separator: "/"))): 최종 scale=1.0, 정착값 동일 여부 확인")

        // capH@30pt 실측값 (CoreText)
        let capH30: [OneLinerFont: CGFloat] = [
            .pen:         20.22,
            .gothic:      21.45,
            .blackGothic: 21.03,
        ]

        for level in TextSizeLevel.allCases {
            var row = "[SizeAudit] \(level.chipLabel)(\(level.rawValue)): "
            var capHValues: [CGFloat] = []
            for font in OneLinerFont.allCases {
                let pt    = OneLinerFont.basePt * font.sizeScale * level.scale
                let capHpt = (capH30[font] ?? 20.22) * (pt / 30.0)
                let capHpx = capHpt * screenScale
                capHValues.append(capHpx)
                row += "\(font.rawValue)=\(String(format: "%.1f", capHpx))px  "
            }
            let spread = (capHValues.max() ?? 0) - (capHValues.min() ?? 0)
            row += spread <= 1.0 ? "✓" : "⚠️ spread=\(String(format: "%.1f", spread))px"
            print(row)
        }
    }
}
#endif

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
    #if DEBUG
    let _ = OneLinerSizeAudit.run()
    #endif
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
        fontChoice: .gothic
    )
    .frame(width: 300, height: 375)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .preferredColorScheme(.dark)
}

#Preview("블랙고딕 / 하단 좌측") {
    let _ = _registerFonts()
    OneLinerCard(
        activity: _previewActivity,
        text: "꽃밭을 달리는데\n난 땀밭",
        position: .bottomLeading,
        textColor: .violet,
        fontChoice: .blackGothic
    )
    .frame(width: 300, height: 375)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .preferredColorScheme(.dark)
}
