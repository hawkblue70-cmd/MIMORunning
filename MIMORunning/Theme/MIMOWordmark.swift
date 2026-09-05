import SwiftUI

struct MIMOWordmark: View {
    var size: CGFloat = 16
    // 하위 호환용 파라미터 (PNG 방식에선 미사용)
    var mimoColor: Color = .white
    var runColor: Color  = Theme.violet
    // true 시 MIMO 글자에만 검은 테두리 (라이트 배경 대응)
    var strokeMIMO: Bool = false

    var body: some View {
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
