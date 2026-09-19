import SwiftUI

struct MIMOWordmark: View {
    var size: CGFloat = 16

    /// PNG 왼쪽 투명 여백 때문에 "MIMO"의 M은 프레임 왼쪽 끝보다 안쪽에서 시작한다.
    /// 로고 아래 요소를 M의 왼쪽 선에 맞출 때 더해 주는 값 (size 11 → 약 2.7pt).
    /// 근거: MIMOWordmark.png 2464×848, M 잉크 시작 x≈90px, 프레임 폭 = size×2.3×(2464/848).
    static func inkLeadingInset(size: CGFloat) -> CGFloat {
        size * 2.3 * (2464.0 / 848.0) * (90.0 / 2464.0)
    }
    // 하위 호환용 파라미터 (PNG 방식에선 미사용)
    var mimoColor: Color = .white
    var runColor: Color  = Theme.violet
    // true 시 MIMO 글자에만 검은 테두리 (라이트 배경 대응)
    var strokeMIMO: Bool = false
    /// true = 사진·영상 공유 카드(애슬레틱·포토·스토리·스탬프·플레이서블·원라이너·영상 오버레이 등)의 로고.
    /// `showsOnMediaCards`가 false면 로고를 그리지 않되 같은 크기의 빈 자리는 남긴다(hidden)
    /// → 총평·대회 뱃지·문구·날짜 등 다른 요소의 위치는 한 점도 움직이지 않는다.
    var onMediaCard: Bool = false

    /// 사진·영상 공유 카드 로고 on/off — 공유 시트의 "로고" 칩이 바꾸는 값. 기본 ON(2026-09 결정: 설정이
    /// 저장되므로 끄는 건 평생 한 번, 켜 두면 유일한 무료 획득 채널이 작동).
    /// 데이터 전용 카드(성장·주간·스플릿·경로·차트·인사이트 내보내기)와 앱 화면은 이 값과 무관하게 항상 표시.
    static let mediaLogoKey = "share_showLogoOnMediaCards"

    /// 영상 CALayer 경로(VideoExportService·PhotoSlideComposition)용 — 거기서는 다른 레이어 위치가
    /// wMZoneH 상수로 이미 독립돼 있어 로고 레이어만 빠진다. SwiftUI 쪽은 아래 @AppStorage가 같은 키를 본다.
    static var showsOnMediaCards: Bool {
        // 키가 없으면(한 번도 안 건드림) 기본 ON — 아래 @AppStorage 기본값과 반드시 같아야 미리보기 = 출력
        (UserDefaults.standard.object(forKey: mediaLogoKey) as? Bool) ?? true
    }

    // 칩을 켜고 끄면 미리보기 카드가 바로 다시 그려지도록 뷰 안에서 직접 구독. ImageRenderer 트리에서도 같은 값을 읽는다.
    @AppStorage(MIMOWordmark.mediaLogoKey) private var logoOnMediaCards = true

    init(size: CGFloat = 16, mimoColor: Color = .white, runColor: Color = Theme.violet,
         strokeMIMO: Bool = false, onMediaCard: Bool = false) {
        self.size = size
        self.mimoColor = mimoColor
        self.runColor = runColor
        self.strokeMIMO = strokeMIMO
        self.onMediaCard = onMediaCard
    }

    var body: some View {
        if onMediaCard && !logoOnMediaCards {
            mark.hidden()
        } else {
            mark
        }
    }

    @ViewBuilder
    private var mark: some View {
        if strokeMIMO {
            MIMOWordmarkStrokeView(size: size)
        } else {
            // 단일 PNG: 흰 MIMO + 1.8 테두리 → 어두운·밝은 배경 모두 대응 (그림자 없음)
            Image("MIMOWordmark")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: size * 2.3)
                .accessibilityLabel("MIMO Running")
        }
    }
}

/// 코드 기반 워드마크: MIMO 글자에만 검은 테두리 적용. SVG 원본 기준 렌더링.
/// SVG viewBox "6 12 306 95" — MIMO(Arial 800 46pt), RUNNING(Arial 800 27pt ls5)
private struct MIMOWordmarkStrokeView: View {
    let size: CGFloat

    private var h: CGFloat  { size * 2.3 }
    private var s: CGFloat  { h / 95 }          // viewBox height = 95
    private var ox: CGFloat { -6 * s }           // viewBox x=6 → canvas x=0
    private var oy: CGFloat { -12 * s }          // viewBox y=12 → canvas y=0

    var body: some View {
        Canvas { ctx, _ in
            // 스우시 gradient — y 좌표 -6 이동 (MIMO 쪽에 붙여 RUNNING과 간격 확보)
            var swoosh = Path()
            swoosh.move(to:       svgPt(14, 64))
            swoosh.addCurve(to:   svgPt(306, 14),
                            control1: svgPt(74, 72),
                            control2: svgPt(190, 66))
            swoosh.addCurve(to:   svgPt(34, 54),
                            control1: svgPt(214, 60),
                            control2: svgPt(112, 58))
            swoosh.addCurve(to:   svgPt(14, 64),
                            control1: svgPt(25, 53),
                            control2: svgPt(16, 56))
            swoosh.closeSubpath()
            ctx.fill(swoosh, with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(hex: "7C5CFC"), location: 0),
                    .init(color: Color(hex: "5A3CFF"), location: 1)
                ]),
                startPoint: svgPt(0, 0),
                endPoint:   svgPt(306, 95)
            ))

            // RUNNING (테두리 없음 — PNG와 동일 스타일)
            let runFont = Font.system(size: 27 * s, weight: .heavy)
            ctx.draw(
                Text("RUNNING").font(runFont).tracking(5 * s)
                    .foregroundStyle(Color(hex: "7C5CFC")),
                at: svgPt(16, 102), anchor: .bottomLeading
            )

            // MIMO: 먼저 검은 테두리(8방향), 그 위에 흰 fill
            let mimoFont = Font.system(size: 46 * s, weight: .heavy)
            let mimoOrigin = svgPt(14, 50)
            let os: CGFloat = max(0.4, s * 2.2)   // 테두리 두께
            let od = os * 0.707                    // 대각선 성분
            let blackMIMO = Text("MIMO").font(mimoFont).foregroundStyle(Color.black)
            for (ddx, ddy): (CGFloat, CGFloat) in [
                (os,0),(-os,0),(0,os),(0,-os),
                (od,od),(-od,od),(od,-od),(-od,-od)
            ] {
                ctx.draw(blackMIMO,
                         at: CGPoint(x: mimoOrigin.x + ddx, y: mimoOrigin.y + ddy),
                         anchor: .bottomLeading)
            }
            ctx.draw(
                Text("MIMO").font(mimoFont).foregroundStyle(Color.white),
                at: mimoOrigin, anchor: .bottomLeading
            )
        }
        .frame(width: 300 * s, height: h)
        .accessibilityLabel("MIMO Running")
    }

    private func svgPt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * s + ox, y: y * s + oy)
    }
}

#Preview {
    VStack(spacing: 0) {
        ZStack {
            LinearGradient(colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                           startPoint: .top, endPoint: .bottom)
            MIMOWordmark(size: 22)
        }
        .frame(height: 100)

        ZStack {
            LinearGradient(colors: [Color(hex: "9EC6F0"), Color(hex: "CFE0F5")],
                           startPoint: .top, endPoint: .bottom)
            MIMOWordmark(size: 22, strokeMIMO: true)
        }
        .frame(height: 100)
    }
    .frame(width: 280)
}
