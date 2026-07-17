import SwiftUI
import UIKit
import CoreLocation

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
        case .violet: return Color(hex: "5E35B1")
        case .gold:   return Color(hex: "FFC74D")
        case .lime:   return Theme.power
        case .blue:   return Color(hex: "1976D2")
        }
    }

    var uiColor: UIColor {
        switch self {
        case .white:  return .white
        case .violet: return UIColor(red: 0x5E/255.0, green: 0x35/255.0, blue: 0xB1/255.0, alpha: 1)
        case .gold:   return UIColor(red: 0xFF/255.0, green: 0xC7/255.0, blue: 0x4D/255.0, alpha: 1)
        case .lime:   return UIColor(red: 0xA3/255.0, green: 0xE6/255.0, blue: 0x35/255.0, alpha: 1)
        case .blue:   return UIColor(red: 0x19/255.0, green: 0x76/255.0, blue: 0xD2/255.0, alpha: 1)
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
    case bottom   = "bottom"    // 아래에서 슬라이드 인(위로)

    var chipLabel: String {
        switch self {
        case .leading:  return AppLanguage.shared.s("왼쪽에서", "From Left")
        case .trailing: return AppLanguage.shared.s("오른쪽에서", "From Right")
        case .bottom:   return AppLanguage.shared.s("아래에서", "From Below")
        }
    }

    /// 세로(아래에서) 방향이면 true → 애니메이션을 y축으로.
    var isVertical: Bool { self == .bottom }
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
            ? (popAppeared ? 1.0 : 1.4)
            : 1.0)
        .rotationEffect(appearanceMode == .fade && decorEffect == .wobble
            ? .degrees(wobblePhase ? 2.5 : -2.5)
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
        let frameAlign: Alignment = alignment == .trailing ? .trailing
            : alignment == .leading ? .leading : .center
        let vertical: Bool  = flyDirection.isVertical
        let initX:  CGFloat = vertical ? 280 : (flyDirection == .trailing ? 280 : -280)
        VStack(alignment: hAlign, spacing: plateOn ? 3 : lineSpacing) {
            ForEach(lines.indices, id: \.self) { i in
                let line = lines[i]
                if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let off: CGFloat = i < lineOffsets.count ? lineOffsets[i] : initX
                    if plateOn {
                        lineContent(line)
                            .multilineTextAlignment(alignment)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(plateBgColor))
                            .frame(maxWidth: .infinity, alignment: frameAlign)
                            .offset(x: vertical ? 0 : off, y: vertical ? off : 0)
                    } else {
                        lineContent(line)
                            .multilineTextAlignment(alignment)
                            .frame(maxWidth: .infinity, alignment: frameAlign)
                            .offset(x: vertical ? 0 : off, y: vertical ? off : 0)
                    }
                }
            }
        }
        .onAppear {
            let initOff: CGFloat = flyDirection.isVertical ? 280 : (flyDirection == .trailing ? 280 : -280)
            lineOffsets = Array(repeating: initOff, count: lines.count)
            for i in lines.indices {
                guard !lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                withAnimation(.easeOut(duration: 0.45).delay(Double(i) * 0.25)) {
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
        let frameAlign: Alignment = alignment == .trailing ? .trailing
            : alignment == .leading ? .leading : .center
        let lines = text.components(separatedBy: "\n")
        VStack(alignment: hAlign, spacing: 3) {
            ForEach(lines.indices, id: \.self) { i in
                if !lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lineContent(lines[i])
                        .multilineTextAlignment(alignment)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(plateBgColor))
                        .frame(maxWidth: .infinity, alignment: frameAlign)
                }
            }
        }
        .background {
            #if DEBUG
            auditRenderHeight("음영판")
            #endif
        }
    }

    // 테두리/없음: 줄별 VStack, lineLimit 없음 → 각 입력줄이 카드 폭에서 자유롭게 줄바꿈.
    // lineLimit(1): 긴 줄이 축소(minimumScaleFactor)되어 작게 표시되는 문제 → 제거.
    // VideoExportService(NSAttributedString)와 동일하게 줄바꿈으로 처리.
    @ViewBuilder
    private func singleTextView() -> some View {
        let lines  = text.components(separatedBy: "\n")
        let hAlign: HorizontalAlignment = alignment == .trailing ? .trailing
            : alignment == .leading ? .leading : .center
        let frameAlign: Alignment = alignment == .trailing ? .trailing
            : alignment == .leading ? .leading : .center
        VStack(alignment: hAlign, spacing: lineSpacing) {
            ForEach(lines.indices, id: \.self) { i in
                if !lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lineContent(lines[i])
                        .multilineTextAlignment(alignment)
                        .frame(maxWidth: .infinity, alignment: frameAlign)
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
    var showWordmark: Bool = true
    /// When true, text + date are pinned together at the bottom-left (caption layout).
    /// The `position` parameter is ignored in this mode.
    var captionMode: Bool = false
    /// 스토리 모드에서 차트 패널이 하단에 배치될 때 해당 영역 높이(pt). > 0이면 문구를 차트 위 공간에 배치.
    var chartBottomReserved: CGFloat = 0
    /// 스토리 모드에서 차트 패널이 상단에 배치될 때 해당 영역 높이(pt). > 0이면 문구를 차트 아래 공간에 배치.
    var chartTopReserved: CGFloat = 0
    /// Full-video title overlay (영상·슬라이드 미리보기). Empty = hidden.
    var videoTitle: String = ""
    var titleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    /// 카드 높이 오버라이드. nil=기본 375(4:5). 영상/슬라이드 9:16 프리뷰는 300*16/9=533.33 전달.
    /// 폭은 300 고정(폰트 기준 유지) → 호출부에서 scaleEffect로 목표 크기에 맞춤.
    var cardHeightOverride: CGFloat? = nil

    // PDT metric chips (pace / distance / time / heartrate)
    var metricPace:      Bool = false
    var metricDistance:  Bool = false
    var metricTime:      Bool = false
    var metricHeartRate: Bool = false
    var pdtPosition:     CardPosition  = .bottomLeading
    var pdtSizeLevel:    TextSizeLevel = .medium
    var availableMetrics: [MetricItem] = []

    // Route minimap (M) and HR chart (H) — story mode overlays
    var showRoute:    Bool = false
    var routeCoords:  [CLLocationCoordinate2D] = []
    var routePosition: CardPosition = .bottomTrailing
    var showHRChart:  Bool = false
    var hrSamples:    [(offset: TimeInterval, bpm: Int)] = []
    var hrZones:      [HRZoneData]  = []
    // Generic chart overlay (elevation, cadence, splits, intervals, etc.)
    var chartOverlayType:   ChartOverlayType = .none
    var chartSeriesData:    [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:]
    var chartSplits:        [SplitData] = []
    var intervalSegments:   [IntervalSegment] = []

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
            if showWordmark { wordmark }

            // ── Full-video title (영상·슬라이드 정지 미리보기) ─
            if !videoTitle.isEmpty { titleOverlay }

            // ── PDT metric chips (페이스·거리·시간·심박) ────────
            if metricPace || metricDistance || metricTime || metricHeartRate {
                pdtChipsOverlay
            }

            // ── 경로 미니맵 (M) — chartOverlayType == .route일 때는 차트 패널이 처리 ─
            if showRoute, chartOverlayType != .route, !routeCoords.isEmpty {
                RouteMiniMap(coords: routeCoords)
                    .frame(width: 54, height: 54)
                    .padding(.horizontal, 18)
                    .padding(.top, routePosition.isTop
                        ? (cardHeightOverride != nil ? (CardVisual.videoSafeTop + 4) * (Self.cardWidth / 1080) : 28)
                        : 4)
                    .padding(.bottom, routePosition.isBottom
                        ? (cardHeightOverride != nil ? CardVisual.videoSafeBottom * (Self.cardWidth / 1080) : 24)
                        : 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: routePosition.alignment)
                    .allowsHitTesting(false)
            }

            // ── 심박 차트 (H) ──────────────────────────────────
            if showHRChart, hrSamples.count >= 2 {
                if cardHeightOverride != nil {
                    // 9:16 모드: zone-colored range bar chart (dataPreviewOverlay와 동일 크기)
                    let cardH   = cardHeightOverride ?? Self.cardHeight
                    let panW    = Self.cardWidth - 20
                    let panH    = cardH * 0.264
                    let hrSrc   = hrSamples.filter { $0.bpm > 0 }
                        .map { (offset: $0.offset, value: Double($0.bpm)) }
                    let hrt0    = hrSrc.first?.offset ?? 0
                    let hrdt    = max(1.0, (hrSrc.last?.offset ?? 1) - hrt0)
                    let hrdtMin = hrdt / 60.0
                    let hrBN    = 80
                    let hrBSz   = hrdt / Double(hrBN)
                    let hrBuckets: [(id: Int, avg: Double, lo: Double, hi: Double)] = (0..<hrBN).compactMap { i in
                        let bLo  = hrt0 + Double(i) * hrBSz
                        let bHi  = bLo + hrBSz
                        let vals = hrSrc
                            .filter { $0.offset >= bLo && ($0.offset < bHi || (i == hrBN-1 && $0.offset <= hrt0+hrdt)) }
                            .map(\.value)
                        guard !vals.isEmpty else { return nil }
                        return (i, vals.reduce(0,+)/Double(vals.count), vals.min()!, vals.max()!)
                    }
                    let hrAvgAll = hrSrc.isEmpty ? 0.0 : hrSrc.map(\.value).reduce(0,+) / Double(hrSrc.count)
                    let oMin  = hrBuckets.map(\.lo).min() ?? 0
                    let oMax  = hrBuckets.map(\.hi).max() ?? 1
                    let hrRng = max(oMax - oMin, oMin * 0.02)
                    let hrYLo = max(0, oMin - hrRng * 0.4)
                    let hrYHi = oMax + hrRng * 0.2
                    let hrYRange = max(1e-6, hrYHi - hrYLo)
                    let sortedZones = hrZones.sorted { $0.minBPM < $1.minBPM }
                    let zoneColor: (Double) -> Color = { bpm in
                        var idx = 1
                        for z in sortedZones { if bpm >= Double(z.minBPM) { idx = z.id } }
                        switch idx {
                        case 1:  return Color(red: 0.30, green: 0.55, blue: 1.00)
                        case 2:  return Color(red: 0.20, green: 0.85, blue: 0.45)
                        case 3:  return Color(red: 0.75, green: 0.88, blue: 0.20)
                        case 4:  return Color(red: 1.00, green: 0.55, blue: 0.10)
                        default: return Color(red: 1.00, green: 0.25, blue: 0.45)
                        }
                    }
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.30))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLanguage.shared.s("♥ 심박수", "♥ HR"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.top, 8)
                                .padding(.leading, 10)
                            Canvas { ctx, size in
                                guard !hrBuckets.isEmpty else { return }
                                let yLblW: CGFloat = 26
                                let xLblH: CGFloat = 11
                                let cw = max(1, size.width - yLblW)
                                let ch = max(1, size.height - xLblH)
                                let yMarkN = 4, xMarkN = 4
                                func pty(_ v: Double) -> CGFloat { ch * CGFloat(1-(v-hrYLo)/hrYRange) }
                                let axisFont  = Font.system(size: 7, design: .monospaced)
                                let axisColor = Color.white.opacity(0.55)
                                for i in 0..<yMarkN {
                                    let yVal = hrYLo + Double(i)*(hrYHi-hrYLo)/Double(yMarkN-1)
                                    let yp = pty(yVal)
                                    var gp = Path(); gp.move(to: .init(x:0,y:yp)); gp.addLine(to: .init(x:cw,y:yp))
                                    ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                                    ctx.draw(Text(String(format:"%.0f",yVal)).font(axisFont).foregroundColor(axisColor),
                                             at: .init(x:cw+2,y:yp), anchor: .leading)
                                }
                                for i in 0..<xMarkN {
                                    let frac = Double(i)/Double(xMarkN-1)
                                    let xp = CGFloat(frac)*cw
                                    var gp = Path(); gp.move(to: .init(x:xp,y:0)); gp.addLine(to: .init(x:xp,y:ch))
                                    ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                                    let xTxt = AppLanguage.shared.isEnglish
                                        ? String(format:"%.0fm",frac*hrdtMin)
                                        : String(format:"%.0f분",frac*hrdtMin)
                                    var anch: UnitPoint = .top
                                    if i == 0 { anch = .topLeading } else if i == xMarkN-1 { anch = .topTrailing }
                                    ctx.draw(Text(xTxt).font(axisFont).foregroundColor(axisColor),
                                             at: .init(x:xp,y:ch+2), anchor: anch)
                                }
                                let barGap = cw / CGFloat(hrBN)
                                let barW   = max(1.5, barGap - 0.8)
                                for b in hrBuckets {
                                    let bx = CGFloat(b.id)*barGap+(barGap-barW)/2
                                    let topY = pty(b.hi); let botY = pty(b.lo)
                                    let barH = max(1.5, botY - topY)
                                    ctx.fill(Path(CGRect(x:bx,y:topY,width:barW,height:barH)),
                                             with: .color(zoneColor(b.avg).opacity(0.85)))
                                }
                                let avgY = pty(hrAvgAll)
                                var dashPath = Path(); var dx: CGFloat = 0
                                while dx < cw {
                                    dashPath.move(to: .init(x:dx,y:avgY))
                                    dashPath.addLine(to: .init(x:min(dx+4,cw),y:avgY))
                                    dx += 7
                                }
                                ctx.stroke(dashPath, with: .color(Color.red.opacity(0.75)), lineWidth: 1.2)
                                ctx.draw(
                                    Text("avg \(Int(hrAvgAll))").font(Font.system(size:7.5,weight:.medium))
                                        .foregroundColor(Color.red.opacity(0.9)),
                                    at: .init(x:cw-2,y:avgY-1), anchor: .bottomTrailing)
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 4)
                        }
                    }
                    .frame(width: panW, height: panH)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                } else {
                    // 4:5 모드: zone-colored bar chart (편집화면과 동일)
                    let panW4  = Self.cardWidth - 20
                    let panH4  = Self.cardHeight * 0.264
                    let hrSrc4 = hrSamples.filter { $0.bpm > 0 }
                        .map { (offset: $0.offset, value: Double($0.bpm)) }
                    let hrt04    = hrSrc4.first?.offset ?? 0
                    let hrdt4    = max(1.0, (hrSrc4.last?.offset ?? 1) - hrt04)
                    let hrdtMin4 = hrdt4 / 60.0
                    let hrBN4    = 80
                    let hrBSz4   = hrdt4 / Double(hrBN4)
                    let hrBuckets4: [(id: Int, avg: Double, lo: Double, hi: Double)] = (0..<hrBN4).compactMap { i in
                        let bLo  = hrt04 + Double(i) * hrBSz4
                        let bHi  = bLo + hrBSz4
                        let vals = hrSrc4
                            .filter { $0.offset >= bLo && ($0.offset < bHi || (i == hrBN4-1 && $0.offset <= hrt04+hrdt4)) }
                            .map(\.value)
                        guard !vals.isEmpty else { return nil }
                        return (i, vals.reduce(0,+)/Double(vals.count), vals.min()!, vals.max()!)
                    }
                    let hrAvgAll4 = hrSrc4.isEmpty ? 0.0 : hrSrc4.map(\.value).reduce(0,+) / Double(hrSrc4.count)
                    let oMin4  = hrBuckets4.map(\.lo).min() ?? 0
                    let oMax4  = hrBuckets4.map(\.hi).max() ?? 1
                    let hrRng4 = max(oMax4 - oMin4, oMin4 * 0.02)
                    let hrYLo4 = max(0, oMin4 - hrRng4 * 0.4)
                    let hrYHi4 = oMax4 + hrRng4 * 0.2
                    let hrYRange4 = max(1e-6, hrYHi4 - hrYLo4)
                    let sortedZones4 = hrZones.sorted { $0.minBPM < $1.minBPM }
                    let zoneColor4: (Double) -> Color = { bpm in
                        var idx = 1
                        for z in sortedZones4 { if bpm >= Double(z.minBPM) { idx = z.id } }
                        switch idx {
                        case 1:  return Color(red: 0.30, green: 0.55, blue: 1.00)
                        case 2:  return Color(red: 0.20, green: 0.85, blue: 0.45)
                        case 3:  return Color(red: 0.75, green: 0.88, blue: 0.20)
                        case 4:  return Color(red: 1.00, green: 0.55, blue: 0.10)
                        default: return Color(red: 1.00, green: 0.25, blue: 0.45)
                        }
                    }
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.30))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLanguage.shared.s("♥ 심박수", "♥ HR"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.top, 8)
                                .padding(.leading, 10)
                            Canvas { ctx, size in
                                guard !hrBuckets4.isEmpty else { return }
                                let yLblW: CGFloat = 26
                                let xLblH: CGFloat = 11
                                let cw = max(1, size.width - yLblW)
                                let ch = max(1, size.height - xLblH)
                                let yMarkN = 4, xMarkN = 4
                                func pty(_ v: Double) -> CGFloat { ch * CGFloat(1-(v-hrYLo4)/hrYRange4) }
                                let axisFont  = Font.system(size: 7, design: .monospaced)
                                let axisColor = Color.white.opacity(0.55)
                                for i in 0..<yMarkN {
                                    let yVal = hrYLo4 + Double(i)*(hrYHi4-hrYLo4)/Double(yMarkN-1)
                                    let yp = pty(yVal)
                                    var gp = Path(); gp.move(to: .init(x:0,y:yp)); gp.addLine(to: .init(x:cw,y:yp))
                                    ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                                    ctx.draw(Text(String(format:"%.0f",yVal)).font(axisFont).foregroundColor(axisColor),
                                             at: .init(x:cw+2,y:yp), anchor: .leading)
                                }
                                for i in 0..<xMarkN {
                                    let frac = Double(i)/Double(xMarkN-1)
                                    let xp = CGFloat(frac)*cw
                                    var gp = Path(); gp.move(to: .init(x:xp,y:0)); gp.addLine(to: .init(x:xp,y:ch))
                                    ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                                    let xTxt = AppLanguage.shared.isEnglish
                                        ? String(format:"%.0fm",frac*hrdtMin4)
                                        : String(format:"%.0f분",frac*hrdtMin4)
                                    var anch: UnitPoint = .top
                                    if i == 0 { anch = .topLeading } else if i == xMarkN-1 { anch = .topTrailing }
                                    ctx.draw(Text(xTxt).font(axisFont).foregroundColor(axisColor),
                                             at: .init(x:xp,y:ch+2), anchor: anch)
                                }
                                let barGap = cw / CGFloat(hrBN4)
                                let barW   = max(1.5, barGap - 0.8)
                                for b in hrBuckets4 {
                                    let bx = CGFloat(b.id)*barGap+(barGap-barW)/2
                                    let topY = pty(b.hi); let botY = pty(b.lo)
                                    let barH = max(1.5, botY - topY)
                                    ctx.fill(Path(CGRect(x:bx,y:topY,width:barW,height:barH)),
                                             with: .color(zoneColor4(b.avg).opacity(0.85)))
                                }
                                let avgY = pty(hrAvgAll4)
                                var dashPath = Path(); var dx: CGFloat = 0
                                while dx < cw {
                                    dashPath.move(to: .init(x:dx,y:avgY))
                                    dashPath.addLine(to: .init(x:min(dx+4,cw),y:avgY))
                                    dx += 7
                                }
                                ctx.stroke(dashPath, with: .color(Color.red.opacity(0.75)), lineWidth: 1.2)
                                ctx.draw(
                                    Text("avg \(Int(hrAvgAll4))").font(Font.system(size:7.5,weight:.medium))
                                        .foregroundColor(Color.red.opacity(0.9)),
                                    at: .init(x:cw-2,y:avgY-1), anchor: .bottomTrailing)
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 4)
                        }
                    }
                    .frame(width: panW4, height: panH4)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                }
            }

            // ── 경로 차트 패널 (chartOverlayType == .route) ───────
            if chartOverlayType == .route, !routeCoords.isEmpty {
                let cardH   = cardHeightOverride ?? Self.cardHeight
                let panW    = Self.cardWidth - 20
                let panH    = cardH * 0.264
                let lats    = routeCoords.map { $0.latitude }
                let lons    = routeCoords.map { $0.longitude }
                let minLat  = lats.min()!, maxLat = lats.max()!
                let minLon  = lons.min()!, maxLon = lons.max()!
                let rng     = max(1e-6, max(maxLat - minLat, maxLon - minLon))
                let padX    = (rng - (maxLon - minLon)) / 2
                let padY    = (rng - (maxLat - minLat)) / 2
                let routePt: (CLLocationCoordinate2D, CGSize) -> CGPoint = { c, size in
                    let nx   = CGFloat((c.longitude - minLon + padX) / rng)
                    let ny   = CGFloat((c.latitude  - minLat + padY) / rng)
                    let ins: CGFloat = size.height * 0.06
                    let dim  = min(size.width, size.height) - ins * 2
                    let xOff = (size.width - dim) / 2
                    return CGPoint(x: xOff + ins + nx * dim, y: ins + (1 - ny) * dim)
                }
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLanguage.shared.s("↗ 경로", "↗ Route"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.top, 8)
                            .padding(.leading, 10)
                        Canvas { ctx, size in
                            var path = Path()
                            path.move(to: routePt(routeCoords[0], size))
                            for c in routeCoords.dropFirst() { path.addLine(to: routePt(c, size)) }
                            ctx.stroke(path, with: .color(.white.opacity(0.88)),
                                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            let dotR: CGFloat = 3.5
                            let sPt = routePt(routeCoords.first!, size)
                            ctx.fill(Path(ellipseIn: CGRect(x: sPt.x - dotR, y: sPt.y - dotR,
                                                            width: dotR * 2, height: dotR * 2)),
                                     with: .color(.green.opacity(0.90)))
                            let ePt = routePt(routeCoords.last!, size)
                            ctx.fill(Path(ellipseIn: CGRect(x: ePt.x - dotR, y: ePt.y - dotR,
                                                            width: dotR * 2, height: dotR * 2)),
                                     with: .color(.red.opacity(0.90)))
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                    }
                }
                .frame(width: panW, height: panH)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            }

            // ── 일반 차트 오버레이 (고도·케이던스 등) ─────────────
            if !showHRChart, ![.none, .route, .hrChart].contains(chartOverlayType) {
                genericChartOverlay
            }

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
                    .padding(.bottom, chartBottomReserved > 0 ? chartBottomReserved + 8 : 0)
                    .padding(.top,    chartTopReserved    > 0 ? chartTopReserved    + 8 : 0)
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
        // export와 동일 기준: safeTop * 0.6 (칩은 safeTop 위치 → 제목이 칩 위에 배치됨)
        let topPad:    CGFloat = titleStyle.position.isTop    ? CardVisual.videoSafeTop * 0.6 * scale1080 : 0
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

    // UIKit NSLayoutManager로 줄바꿈 위치를 미리 계산해 \n 삽입.
    // CALayer 렌더러(영상 출력)와 SwiftUI EffectTextView의 줄바꿈이 일치하도록 맞춤.
    private func uikitLineBreakText(_ text: String, uiFont: UIFont, maxWidth: CGFloat) -> String {
        text.components(separatedBy: "\n").map { para -> String in
            guard !para.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return para }
            let storage   = NSTextStorage(string: para, attributes: [.font: uiFont])
            let manager   = NSLayoutManager()
            storage.addLayoutManager(manager)
            let container = NSTextContainer(size: CGSize(width: maxWidth, height: 100_000))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            _ = manager.glyphRange(for: container)
            var lines: [String] = []; var gi = 0
            while gi < manager.numberOfGlyphs {
                var gr = NSRange()
                manager.lineFragmentRect(forGlyphAt: gi, effectiveRange: &gr)
                let cr = manager.characterRange(forGlyphRange: gr, actualGlyphRange: nil)
                lines.append((para as NSString).substring(with: cr).trimmingCharacters(in: .newlines))
                gi = NSMaxRange(gr)
            }
            return lines.isEmpty ? para : lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    // Text just above date — the text+date unit moves together to `position`.
    // Horizontal alignment follows the position column; vertical follows the row.
    @ViewBuilder
    private var captionContent: some View {
        let isTrailing = (position == .topTrailing || position == .trailing || position == .bottomTrailing)
        let hAlign: HorizontalAlignment = position.isLeading ? .leading : isTrailing ? .trailing : .center
        let tAlign: TextAlignment       = position.isLeading ? .leading : isTrailing ? .trailing : .center
        // 9:16 클립 모드에서는 UIKit 줄바꿈을 미리 계산해 CALayer 출력과 일치시킴
        let clipText: String = (cardHeightOverride != nil && !text.isEmpty)
            ? uikitLineBreakText(text, uiFont: fontChoice.uiFont(size: baseFontSize), maxWidth: Self.cardWidth - 48)
            : text
        VStack(alignment: hAlign, spacing: 4) {
            if text.isEmpty {
                if showBackground {
                    if plateOn {
                        // plate 켜진 상태 + 텍스트 없음 → ClipTrimSheet 프리뷰와 동일하게 "···" + 음영판 표시.
                        // 사용자에게 "음영판 설정이 저장됐다"는 시각적 피드백을 제공.
                        EffectTextView(
                            text: "···",
                            font: fontChoice.swiftUIFont(size: baseFontSize),
                            lineSpacing: lineSpacing, alignment: tAlign,
                            color: plateColorPreset.textSwiftColor,
                            appearanceMode: .typing, decorEffect: .none,
                            hasBorder: false, plateOn: true, flyDirection: .trailing,
                            plateBgColor: plateColorPreset.plateBgColor,
                            syntheticBoldStroke: fontChoice.syntheticBoldStroke(for: baseFontSize),
                            borderColor: .clear, borderOffset: 0
                        )
                        .opacity(0.35)
                    } else {
                        Text(AppLanguage.shared.s("한마디를 입력해 주세요", "Enter your one-liner"))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            } else {
                EffectTextView(
                    text: clipText, font: fontChoice.swiftUIFont(size: baseFontSize),
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
        .padding(.horizontal, cardHeightOverride != nil ? 24 : 14)
        .padding(.top, {
            let s = Self.cardWidth / 1080.0
            if cardHeightOverride != nil {
                // 9:16 클립 모드: ClipTrimView · CALayer와 동일한 안전 여백 사용
                let clipTop = (CardVisual.videoSafeTop + 4) * s  // ≈ 73.3 pt
                if !videoTitle.isEmpty && titleStyle.position.isTop && position.isTop {
                    let titlePad  = CardVisual.videoSafeTop * 0.6 * s
                    let titleFont = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale
                    let titleH    = titleFont * 1.4 * 2 + 8
                    return max(clipTop, titlePad + titleH)
                }
                return clipTop
            }
            // 4:5 일반 모드
            if !videoTitle.isEmpty && titleStyle.position.isTop && position.isTop {
                let titlePad  = CardVisual.videoSafeTop * 0.6 * s
                let titleFont = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale
                let titleH    = titleFont * 1.4 * 2 + 8
                return max(32, titlePad + titleH)
            }
            return position.isTop ? 32 : 12
        }())
        // 차트 있으면 차트 위로 배치; 없으면 9:16은 CALayer 안전 여백, 4:5는 기존값
        .padding(.bottom, chartBottomReserved > 0
            ? chartBottomReserved + 8
            : cardHeightOverride != nil
                ? CardVisual.videoSafeBottom * (Self.cardWidth / 1080.0)  // ≈ 75 pt
                : (position.isBottom ? 34 : 12))
    }


    @ViewBuilder
    private var background: some View {
        if let photo = backgroundPhoto {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: Self.cardWidth, height: cardHeightOverride ?? Self.cardHeight)
                .clipped()
        } else {
            LinearGradient(
                colors: SkyPalette.colors(for: cardDate),
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(Color.black.opacity(0.12))
        }
    }

    @ViewBuilder
    private var genericChartOverlay: some View {
        let cardH = cardHeightOverride ?? Self.cardHeight
        let ps    = Self.cardWidth / 300.0   // always 1.0; kept for formula consistency
        let panW  = Self.cardWidth - 20 * ps
        let panH  = cardH * 0.264
        let lineColor: Color = Color(uiColor: chartOverlayType.lineUIColor)
        let title = AppLanguage.shared.s(chartOverlayType.chartTitleKo, chartOverlayType.chartTitleEn)
        let isElevation = (chartOverlayType == .elevation)

        if chartOverlayType == .intervals, !intervalSegments.isEmpty {
            intervalChartPanel(segments: intervalSegments, panW: panW)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
        } else if chartOverlayType == .splits {
            let filtered = chartSplits.filter { $0.distanceM >= 900 }
            if filtered.count >= 2 {
                splitsChartPanel(splits: filtered, panW: panW)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
        } else if let series = chartSeriesData[chartOverlayType], series.count >= 2 {
            let src   = series.filter { $0.value > 0 }
            let t0    = src.first?.offset  ?? 0
            let dt    = max(1.0, (src.last?.offset  ?? 1) - t0)
            let dtMin = dt / 60.0
            let bN    = 80
            let bSz   = dt / Double(bN)
            let buckets: [(id: Int, avg: Double, lo: Double, hi: Double)] = (0..<bN).compactMap { i in
                let bLo  = t0 + Double(i) * bSz
                let bHi  = bLo + bSz
                let vals = src.filter { $0.offset >= bLo && ($0.offset < bHi || (i == bN-1 && $0.offset <= t0+dt)) }.map(\.value)
                guard !vals.isEmpty else { return nil }
                return (i, vals.reduce(0,+)/Double(vals.count), vals.min()!, vals.max()!)
            }
            let avgAll = src.isEmpty ? 0.0 : src.map(\.value).reduce(0,+)/Double(src.count)
            let useRangeBar = [ChartOverlayType.strideLength, .verticalOscillation, .power, .groundContact].contains(chartOverlayType)
            let avgs = buckets.map(\.avg)
            let lo2 = (useRangeBar ? buckets.map(\.lo) : avgs).min() ?? 0
            let hi2 = (useRangeBar ? buckets.map(\.hi) : avgs).max() ?? 1
            let rng = max(hi2 - lo2, lo2 * 0.02)
            let yLo = max(0, lo2 - rng * (useRangeBar ? 0.4 : 0.6))
            let yHi = hi2 + rng * 0.2
            let yRange = max(1e-6, yHi - yLo)
            let fmtY: (Double) -> String = { v in
                isElevation ? String(format: "%.0fm", v)
                : abs(v) >= 100 ? String(format: "%.0f", v)
                : abs(v) >= 10  ? String(format: "%.1f", v)
                : String(format: "%.2f", v)
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12 * ps).fill(Color.black.opacity(0.30))
                VStack(alignment: .leading, spacing: 2 * ps) {
                    Text(title)
                        .font(.system(size: 10 * ps, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.top, 8 * ps)
                        .padding(.leading, 10 * ps)
                    Canvas { ctx, size in
                        guard !buckets.isEmpty || isElevation else { return }
                        let yLblW: CGFloat = 26 * ps
                        let xLblH: CGFloat = 11 * ps
                        let cw = max(1, size.width - yLblW)
                        let ch = max(1, size.height - xLblH)
                        func pty(_ v: Double) -> CGFloat { ch * CGFloat(1-(v-yLo)/yRange) }
                        let axisFont  = Font.system(size: 7*ps, design: .monospaced)
                        let axisColor = Color.white.opacity(0.55)
                        for i in 0..<4 {
                            let yVal = yLo + Double(i)*(yHi-yLo)/3.0
                            let yp   = pty(yVal)
                            var gp = Path(); gp.move(to: .init(x:0,y:yp)); gp.addLine(to: .init(x:cw,y:yp))
                            ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                            ctx.draw(Text(fmtY(yVal)).font(axisFont).foregroundColor(axisColor),
                                     at: .init(x:cw+2,y:yp), anchor: .leading)
                        }
                        for i in 0..<4 {
                            let frac = Double(i)/3.0
                            let xp   = CGFloat(frac)*cw
                            var gp = Path(); gp.move(to: .init(x:xp,y:0)); gp.addLine(to: .init(x:xp,y:ch))
                            ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                            let xTxt = AppLanguage.shared.isEnglish
                                ? String(format:"%.0fm", frac*dtMin)
                                : String(format:"%.0f분", frac*dtMin)
                            var anch: UnitPoint = .top
                            if i == 0 { anch = .topLeading } else if i == 3 { anch = .topTrailing }
                            ctx.draw(Text(xTxt).font(axisFont).foregroundColor(axisColor),
                                     at: .init(x:xp,y:ch+2), anchor: anch)
                        }
                        if isElevation {
                            let ptX: (Double) -> CGFloat = { CGFloat(($0-t0)/dt)*cw }
                            var fill = Path()
                            fill.move(to: .init(x:ptX(src[0].offset),y:ch))
                            fill.addLine(to: .init(x:ptX(src[0].offset),y:pty(src[0].value)))
                            for pt in src.dropFirst() { fill.addLine(to: .init(x:ptX(pt.offset),y:pty(pt.value))) }
                            fill.addLine(to: .init(x:ptX(src.last!.offset),y:ch)); fill.closeSubpath()
                            ctx.fill(fill, with: .color(lineColor.opacity(0.30)))
                            var line = Path()
                            line.move(to: .init(x:ptX(src[0].offset),y:pty(src[0].value)))
                            for pt in src.dropFirst() { line.addLine(to: .init(x:ptX(pt.offset),y:pty(pt.value))) }
                            ctx.stroke(line, with: .color(lineColor), lineWidth: 1.5)
                        } else {
                            let barGap = cw/CGFloat(bN); let barW = max(1.5,barGap-0.8)
                            let base   = pty(yLo)
                            for b in buckets {
                                let bx   = CGFloat(b.id)*barGap+(barGap-barW)/2
                                let topY = useRangeBar ? pty(b.hi) : pty(b.avg)
                                let botY = useRangeBar ? pty(b.lo) : base
                                ctx.fill(Path(CGRect(x:bx,y:topY,width:barW,height:max(1.5,botY-topY))),
                                         with: .color(lineColor.opacity(0.80)))
                            }
                            let avgY = pty(avgAll)
                            var dash = Path(); var x: CGFloat = 0
                            while x < cw { dash.move(to:.init(x:x,y:avgY)); dash.addLine(to:.init(x:min(x+4,cw),y:avgY)); x+=7 }
                            ctx.stroke(dash, with: .color(lineColor.opacity(0.60)), lineWidth: 1.2)
                        }
                    }
                    .padding(.horizontal, 10 * ps)
                    .padding(.bottom, 4 * ps)
                }
            }
            .frame(width: panW, height: panH)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        }
    }

    /// 편집화면(ClipTrimView.dataPreviewOverlay)과 동일한 스플릿 차트 — 행 구성 완전 일치.
    @ViewBuilder
    private func splitsChartPanel(splits: [SplitData], panW: CGFloat) -> some View {
        let ps: CGFloat = 1.0
        let rowH:   CGFloat = 7 * ps
        let titleH: CGFloat = 16 * ps
        let colHH:  CGFloat = 8  * ps
        let vPad:   CGFloat = 5  * ps

        let displaySplits: [SplitData] = splits.count > 21 ? splits.filter { $0.id % 2 == 0 } : splits
        let panH = titleH + colHH + CGFloat(displaySplits.count) * rowH + vPad * 2

        let paces      = displaySplits.map { $0.paceSecPerKm }
        let minP       = paces.min() ?? 0
        let maxP       = paces.max() ?? 1
        let rangeP     = max(1.0, maxP - minP)
        let avgP       = paces.reduce(0.0, +) / Double(paces.count)
        let fastestIdx = paces.indices.min(by: { paces[$0] < paces[$1] }) ?? 0

        let hasHR  = displaySplits.contains { $0.avgHeartRate != nil }
        let hasCad = displaySplits.contains { $0.avgCadence   != nil }
        let hasPwr = displaySplits.contains { $0.avgPower     != nil }

        let hPad:    CGFloat = 8  * ps
        let gap:     CGFloat = 3  * ps
        let kmW:     CGFloat = 18 * ps
        let colW:    CGFloat = 24 * ps
        let fixedW   = 2 * hPad + kmW + 2 * gap + colW
        let optW     = (hasHR  ? gap + colW : 0) + (hasCad ? gap + colW : 0) + (hasPwr ? gap + colW : 0)
        let barAreaW = max(20 * ps, panW - fixedW - optW)

        let zoneColor: (Int?) -> Color = { hrOpt in
            guard let hr = hrOpt,
                  let zid = hrZones.first(where: { hr >= $0.minBPM && hr <= $0.maxBPM })?.id
            else { return Color.red.opacity(0.70) }
            switch zid {
            case 1: return Color(hex: "4FC3F7")
            case 2: return Color(hex: "81C784")
            case 3: return Color(hex: "FFB74D")
            case 4: return Color(hex: "FF7043")
            default: return Color(hex: "E53935")
            }
        }

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12 * ps).fill(Color.black.opacity(0.30))
            VStack(alignment: .leading, spacing: 0) {
                Text(AppLanguage.shared.s("⚡ 스플릿", "⚡ Splits"))
                    .font(.system(size: 10 * ps, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(height: titleH)
                    .padding(.horizontal, hPad)
                // 열 제목 행
                HStack(spacing: gap) {
                    Spacer().frame(width: kmW)
                    Spacer().frame(width: barAreaW)
                    Text(AppLanguage.shared.s("페이스", "Pace"))
                        .font(.system(size: 5.5 * ps, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: colW, alignment: .trailing)
                    if hasHR {
                        Text(AppLanguage.shared.s("심박", "HR"))
                            .font(.system(size: 5.5 * ps, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: colW, alignment: .trailing)
                    }
                    if hasCad {
                        Text(AppLanguage.shared.s("케이던스", "Cad"))
                            .font(.system(size: 5.5 * ps, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: colW, alignment: .trailing)
                    }
                    if hasPwr {
                        Text(AppLanguage.shared.s("파워", "Pwr"))
                            .font(.system(size: 5.5 * ps, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: colW, alignment: .trailing)
                    }
                }
                .padding(.horizontal, hPad)
                .frame(height: colHH)
                ForEach(Array(displaySplits.enumerated()), id: \.element.id) { idx, split in
                    let isFastest = idx == fastestIdx
                    let pace = split.paceSecPerKm
                    let barFrac = CGFloat(0.28 + 0.72 * (pace - minP) / rangeP)
                    let barColor: Color = isFastest
                        ? Color(hex: "FFC74D")
                        : (pace <= avgP
                            ? Color(red: 0.486, green: 0.361, blue: 0.988).opacity(0.85)
                            : Color.white.opacity(0.30))
                    let zc = zoneColor(split.avgHeartRate)
                    HStack(spacing: gap) {
                        Text("\(split.id)k")
                            .font(.system(size: 6.5 * ps, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.80))
                            .frame(width: kmW, alignment: .trailing)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.10))
                                .frame(width: barAreaW, height: 3 * ps)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(barColor)
                                .frame(width: max(3, barAreaW * barFrac), height: 3 * ps)
                        }
                        .frame(width: barAreaW)
                        Text(split.formattedPace)
                            .font(.system(size: 7 * ps, weight: .bold, design: .monospaced))
                            .foregroundStyle(isFastest ? Color(hex: "FFC74D") : .white)
                            .frame(width: colW, alignment: .trailing)
                        if hasHR {
                            HStack(spacing: 1.5 * ps) {
                                Circle()
                                    .fill(split.avgHeartRate != nil ? zc : Color.clear)
                                    .frame(width: 3.5 * ps, height: 3.5 * ps)
                                Text(split.avgHeartRate.map { "\($0)" } ?? "—")
                                    .font(.system(size: 6.5 * ps, design: .monospaced))
                                    .foregroundStyle(split.avgHeartRate != nil ? zc : Color.white.opacity(0.30))
                            }
                            .frame(width: colW, alignment: .trailing)
                        }
                        if hasCad {
                            Text(split.avgCadence.map { "\($0)" } ?? "—")
                                .font(.system(size: 6.5 * ps, design: .monospaced))
                                .foregroundStyle(Color(hex: "60E8CC"))
                                .frame(width: colW, alignment: .trailing)
                        }
                        if hasPwr {
                            Text(split.avgPower.map { "\($0)" } ?? "—")
                                .font(.system(size: 6.5 * ps, design: .monospaced))
                                .foregroundStyle(Color(hex: "BEFA6A"))
                                .frame(width: colW, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, hPad)
                    .frame(height: rowH)
                }
                Spacer(minLength: vPad)
            }
        }
        .frame(width: panW, height: panH)
    }

    /// 참조 이미지(활동 상세)와 동일한 인터벌 테이블 패널
    @ViewBuilder
    private func intervalChartPanel(segments: [IntervalSegment], panW: CGFloat) -> some View {
        let ps: CGFloat  = 1.0
        let rowH: CGFloat  = 6.5 * ps
        let titleH: CGFloat = 16 * ps
        let colHH: CGFloat  = 8  * ps
        let vPad: CGFloat   = 5  * ps

        let displaySegs: [IntervalSegment] = segments.count > 10
            ? segments.filter { ($0.id % 2) == 1 }
            : segments
        let panH: CGFloat = titleH + colHH + CGFloat(displaySegs.count) * rowH + vPad * 2

        let hasHR  = displaySegs.contains { $0.avgHeartRate != nil }
        let hasCad = displaySegs.contains { $0.avgCadence   != nil }

        // 바 너비: duration 비례
        let maxDur = displaySegs.map(\.duration).max() ?? 1.0

        // "400m×5회" 요약 계산
        let workSegs = segments.filter { $0.stepLabel == "운동" }
        let summaryText: String? = {
            let dists = workSegs.compactMap(\.distanceM)
            guard dists.count == workSegs.count, !workSegs.isEmpty else { return nil }
            let snapped = dists.map { d -> Int in
                d >= 1000 ? Int((d / 100).rounded()) * 100 : Int((d / 50).rounded()) * 50
            }
            let counts = Dictionary(grouping: snapped, by: { $0 }).mapValues(\.count)
            guard let (dist, cnt) = counts.max(by: { $0.value < $1.value }), cnt > 0 else { return nil }
            let lbl = dist >= 1000
                ? (dist % 1000 == 0 ? "\(dist/1000)km" : String(format: "%.1fkm", Double(dist)/1000))
                : "\(dist)m"
            return AppLanguage.shared.s("\(lbl)×\(cnt)회", "\(lbl)×\(cnt)")
        }()

        let hPad:   CGFloat = 8  * ps
        let gap:    CGFloat = 3  * ps
        let lblW:   CGFloat = 30 * ps   // "2 운동" 스타일
        let colW:   CGFloat = 22 * ps
        let barAreaW = max(16 * ps, panW - 2 * hPad - lblW - gap - colW
                          - (hasHR  ? gap + colW : 0)
                          - (hasCad ? gap + colW : 0))

        let zoneColor: (Int?) -> Color = { hrOpt in
            guard let hr = hrOpt,
                  let zid = hrZones.first(where: { hr >= $0.minBPM && hr <= $0.maxBPM })?.id
            else { return Color.red.opacity(0.70) }
            switch zid {
            case 1: return Color(hex: "4FC3F7")
            case 2: return Color(hex: "81C784")
            case 3: return Color(hex: "FFB74D")
            case 4: return Color(hex: "FF7043")
            default: return Color(hex: "E53935")
            }
        }

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12 * ps).fill(Color.black.opacity(0.30))
            VStack(alignment: .leading, spacing: 0) {
                // 제목 행
                HStack(spacing: 4 * ps) {
                    Text(AppLanguage.shared.s("⚙ 인터벌", "⚙ Interval"))
                        .font(.system(size: 10 * ps, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    if let s = summaryText {
                        Text(s)
                            .font(.system(size: 7 * ps, weight: .regular))
                            .foregroundStyle(Color(red: 0.486, green: 0.361, blue: 0.988))
                    }
                    Spacer()
                }
                .frame(height: titleH)
                .padding(.horizontal, hPad)
                // 열 헤더
                HStack(spacing: gap) {
                    Spacer().frame(width: lblW)
                    Spacer().frame(width: barAreaW)
                    Text(AppLanguage.shared.s("페이스", "Pace"))
                        .font(.system(size: 5.5 * ps, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: colW, alignment: .trailing)
                    if hasHR {
                        Text(AppLanguage.shared.s("심박", "HR"))
                            .font(.system(size: 5.5 * ps, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: colW, alignment: .trailing)
                    }
                    if hasCad {
                        Text(AppLanguage.shared.s("케이던스", "Cad"))
                            .font(.system(size: 5.5 * ps, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: colW, alignment: .trailing)
                    }
                }
                .padding(.horizontal, hPad)
                .frame(height: colHH)
                // 데이터 행
                ForEach(displaySegs) { seg in
                    let isWork  = seg.stepLabel == "운동"
                    let barFrac = CGFloat(seg.duration / maxDur)
                    let minFrac: CGFloat = 0.10
                    let drawFrac = minFrac + (1 - minFrac) * barFrac
                    let barColor: Color = isWork
                        ? Color(red: 0.486, green: 0.361, blue: 0.988)
                        : Color(white: 0.30)
                    let shortLabel: String = {
                        switch seg.stepLabel {
                        case "준비운동": return AppLanguage.shared.s("준비", "WU")
                        case "운동":     return AppLanguage.shared.s("운동", "Work")
                        case "회복":     return AppLanguage.shared.s("회복", "Rec")
                        case "정리운동": return AppLanguage.shared.s("정리", "CD")
                        default:         return seg.stepLabel ?? "-"
                        }
                    }()
                    let zc = zoneColor(seg.avgHeartRate)
                    HStack(spacing: gap) {
                        // 번호 + 레이블
                        HStack(spacing: 2 * ps) {
                            Text("\(seg.id)")
                                .font(.system(size: 5.5 * ps, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.40))
                                .frame(width: 10 * ps, alignment: .trailing)
                            Text(shortLabel)
                                .font(.system(size: 6.5 * ps, weight: isWork ? .semibold : .regular))
                                .foregroundStyle(isWork
                                    ? Color(red: 0.686, green: 0.561, blue: 1.0)
                                    : .white.opacity(0.60))
                                .frame(width: lblW - 12 * ps, alignment: .leading)
                        }
                        .frame(width: lblW)
                        // 가로 바
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: barAreaW, height: 3 * ps)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(barColor.opacity(isWork ? 0.85 : 0.55))
                                .frame(width: max(3, barAreaW * drawFrac), height: 3 * ps)
                        }
                        .frame(width: barAreaW)
                        // 페이스
                        Text(seg.formattedPace ?? "—")
                            .font(.system(size: 6.5 * ps, weight: isWork ? .bold : .regular, design: .monospaced))
                            .foregroundStyle(isWork ? Color(hex: "FFC74D") : .white.opacity(0.65))
                            .frame(width: colW, alignment: .trailing)
                        // 심박 (옵션)
                        if hasHR {
                            HStack(spacing: 1.5 * ps) {
                                Circle()
                                    .fill(seg.avgHeartRate != nil ? zc : Color.clear)
                                    .frame(width: 3.5 * ps, height: 3.5 * ps)
                                Text(seg.avgHeartRate.map { "\($0)" } ?? "—")
                                    .font(.system(size: 6 * ps, design: .monospaced))
                                    .foregroundStyle(seg.avgHeartRate != nil ? zc : .white.opacity(0.30))
                            }
                            .frame(width: colW, alignment: .trailing)
                        }
                        // 케이던스 (옵션)
                        if hasCad {
                            Text(seg.avgCadence.map { "\($0)" } ?? "—")
                                .font(.system(size: 6 * ps, design: .monospaced))
                                .foregroundStyle(Color(hex: "60E8CC"))
                                .frame(width: colW, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, hPad)
                    .frame(height: rowH)
                }
                Spacer(minLength: vPad)
            }
        }
        .frame(width: panW, height: panH)
    }

    private var pdtChipsOverlay: some View {
        let items: [MetricItem] = [
            metricDistance  ? availableMetrics.first { $0.id == "distance" }  : nil,
            metricPace      ? availableMetrics.first { $0.id == "pace" }      : nil,
            metricTime      ? availableMetrics.first { $0.id == "time" }      : nil,
            metricHeartRate ? availableMetrics.first { $0.id == "heartrate" } : nil
        ].compactMap { $0 }
        let sz = pdtSizeLevel.scale  // 소=0.65 중=0.8 대=1.0
        return HStack(spacing: 6 * sz) {
            ForEach(items) { m in
                HStack(spacing: 3 * sz) {
                    Text(m.value)
                        .font(.system(size: 11 * sz, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    if !m.label.isEmpty {
                        Text(m.label)
                            .font(.system(size: 9 * sz))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 8 * sz)
                .padding(.vertical, 4 * sz)
                .background(RoundedRectangle(cornerRadius: 8 * sz).fill(m.color.opacity(0.30)))
                .overlay(RoundedRectangle(cornerRadius: 8 * sz)
                    .strokeBorder(m.color.opacity(0.55), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, cardHeightOverride != nil ? 20 : 14)
        .padding(.top, pdtPosition.isTop
            ? (cardHeightOverride != nil ? {
                let base = (CardVisual.videoSafeTop + 4) * (Self.cardWidth / 1080)
                guard !videoTitle.isEmpty, titleStyle.position.isTop else { return base }
                let tFontSize = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale
                let titleH = tFontSize * 1.4 * 2 + 8
                let titleEndY = CardVisual.videoSafeTop * 0.6 * (Self.cardWidth / 1080) + titleH
                return max(base, titleEndY + 4)
            }() : 28)
            : 4)
        .padding(.bottom, pdtPosition.isBottom
            ? (cardHeightOverride != nil
                ? CardVisual.videoSafeBottom * (Self.cardWidth / 1080)
                : (chartBottomReserved > 0 ? chartBottomReserved + 4 : 24))
            : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pdtPosition.alignment)
        .allowsHitTesting(false)
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
