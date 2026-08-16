// OneLiner 카드 공용 타입·EffectTextView
//
// 이 파일에 정의된 타입은 OneLiner·Placeable·Stamp 카드에서 공용으로 사용됩니다.
// OneLinerCard 렌더러는 OneLinerCard.swift 에 있습니다.
//
// ⚠️ 이 파일은 공용 타입 전용. 특정 카드 렌더링 코드 작성 금지.

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
        case .small:  return 0.60   // 소: 8.0pt @ 211pt
        case .medium: return 0.75   // 중: 9.9pt @ 211pt  (대 대비 −25%)
        case .large:  return 1.00   // 대: 13.3pt @ 211pt (기준)
        case .xlarge: return 1.38   // 특대: 18.3pt @ 211pt (대 대비 +38%)
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
// 가독성 처리 배타 선택 (없음 / 외곽선). 한 번에 하나만 활성.

enum ReadabilityStyle: String, CaseIterable, Codable {
    case none    = "none"
    case outline = "outline"

    var chipLabel: String {
        switch self {
        case .none:    return AppLanguage.shared.s("없음",   "None")
        case .outline: return AppLanguage.shared.s("테두리", "Border")
        }
    }
}

// MARK: - EffectTextView
//
// appearanceMode: fade → 0.5s 페이드인 on appear (SwiftUI 미리보기용; 영상은 UIKit).
// decorEffect: fade 모드에서만 유효.
// hasBorder: 독립 토글 — 8방향 오프셋 복제(blur 0, 크리스프 글리프 외곽선).
// 소프트 그림자 없음.

struct EffectTextView: View {
    let text:             String
    let font:             Font
    let lineSpacing:      CGFloat
    let alignment:        TextAlignment
    let color:            Color
    let appearanceMode:   AppearanceMode
    let decorEffect:      DecorEffect
    var hasBorder:        Bool          = false
    var flyDirection:     FlyInDirection = .trailing
    var syntheticBoldStroke: CGFloat    = 0
    var borderColor:      Color         = .clear
    var borderOffset:     CGFloat       = 0     // 호출측: max(1.5, baseFontSize * 0.10)
    var isStaticPreview: Bool          = false

    @State private var opacity:     Double    = 1.0
    @State private var popAppeared: Bool      = false
    @State private var wobblePhase: Bool      = false
    @State private var lineOffsets: [CGFloat] = []
    @State private var typedCount:  Int       = 0

    // typing 모드 미리보기용: 표시할 텍스트 (export는 UIKit CALayer 사용)
    private var renderText: String {
        if isStaticPreview { return text }
        guard appearanceMode == .typing else { return text }
        return String(text.prefix(typedCount))
    }

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
            } else {
                singleTextView()
            }
        }
        // pop/wobble은 fade 모드 전용 — 다른 애니메이션 모드 또는 isStaticPreview 시 잔여 변형 없이 1.0 고정
        // isStaticPreview: true이면 onAppear 애니메이션이 실행되지 않아 초기값(1.4·-2.5°)이 고착되므로 중립값 사용
        .scaleEffect(appearanceMode == .fade && !isStaticPreview && decorEffect == .pop
            ? (popAppeared ? 1.0 : 1.4)
            : 1.0)
        .rotationEffect(appearanceMode == .fade && !isStaticPreview && decorEffect == .wobble
            ? .degrees(wobblePhase ? 2.5 : -2.5)
            : .zero)
        .opacity(isStaticPreview ? 1.0 : opacity)
        .onAppear {
            guard !isStaticPreview else { return }
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
        .task(id: text) {
            guard !isStaticPreview else { return }
            guard appearanceMode == .typing, !text.isEmpty else { return }
            typedCount = 0
            try? await Task.sleep(for: .seconds(0.8))
            let chars = Array(text)
            for (i, ch) in chars.enumerated() {
                guard !Task.isCancelled else { return }
                typedCount = i + 1
                let delay: Double = (ch.isWhitespace || ch.isNewline) ? 0.05 : 0.13
                try? await Task.sleep(for: .seconds(delay))
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
        VStack(alignment: hAlign, spacing: lineSpacing) {
            ForEach(lines.indices, id: \.self) { i in
                let line = lines[i]
                if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let off: CGFloat = isStaticPreview ? 0 : (i < lineOffsets.count ? lineOffsets[i] : initX)
                    lineContent(line)
                        .multilineTextAlignment(alignment)
                        .frame(maxWidth: .infinity, alignment: frameAlign)
                        .offset(x: vertical ? 0 : off, y: vertical ? off : 0)
                }
            }
        }
        .onAppear {
            guard !isStaticPreview else { return }
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

    // 테두리/없음: 줄별 VStack, lineLimit 없음 → 각 입력줄이 카드 폭에서 자유롭게 줄바꿈.
    // lineLimit(1): 긴 줄이 축소(minimumScaleFactor)되어 작게 표시되는 문제 → 제거.
    // VideoExportService(NSAttributedString)와 동일하게 줄바꿈으로 처리.
    @ViewBuilder
    private func singleTextView() -> some View {
        let lines  = renderText.components(separatedBy: "\n")
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
    }
}
