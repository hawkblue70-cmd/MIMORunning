import SwiftUI

// 밸런스 그림 공용 뷰 — 거미줄(BalanceRadarView)·저울(BalanceScaleView).
// 밸런스 탭(BalanceTabCard)과 스탬프가 같은 뷰를 크기·색(BalanceDrawStyle)만 바꿔 쓴다(§5.8: 복사 레이아웃 금지).
// 판정은 모두 BalanceSnapshot이 하고, 여기서는 스냅샷만 그린다.
// Canvas 대신 Shape·Path — ImageRenderer 첫 렌더 블랙 방지 관례.

// MARK: - 색 묶음

/// 거미줄·저울 색 묶음 — 탭은 InsightInk에서, 스탬프는 스탬프 색(fill·outline)에서 만든다.
struct BalanceDrawStyle {
    var primary: Color        // 값·주 글자
    var secondary: Color      // 축 이름·블록 이름
    var line: Color           // 바깥 고리·축선
    var band: Color           // 평소 범위 띠(면)
    var usual: Color          // 평소(점선)
    var today: Color          // 오늘 도형 선
    var todayFill: Color      // 오늘 도형 면
    var good: Color
    var bad: Color
    var usualBlock: Color     // 범위 안 블록(회색)
    var normal: Color         // 몸 상태 보통(노랑) — 저울 블록
    var board: Color          // 저울 판·받침
    var textOutline: Color?   // nil = 테두리 없음(탭), 스탬프는 outline 색
    var fontScale: CGFloat = 1

    // 탭 화면을 그대로 두기 위한 세부 색 — nil이면 괄호 안 기본 색을 쓴다(스탬프는 비워 둬도 된다)
    var blockLabel: Color? = nil       // 블록 이름(→ secondary)
    var caption: Color? = nil          // 저울 아래 "몸 상태·부담 / 움직임"(→ secondary)
    var emptyMark: Color? = nil        // 블록 없는 접시의 "—"(→ secondary)
    var referenceStroke: Color? = nil  // 참고 모드 평소 범위 띠 점선 테두리(→ usual)
    var fulcrum: Color? = nil          // 받침 삼각형(→ board)
    var fulcrumBase: Color? = nil      // 받침 바닥 선(→ board)
    var chipText: Color? = nil         // "참고" 칩 글자(→ secondary)
    var chipFill: Color? = nil         // "참고" 칩 바탕(→ band)

    /// 크기 × fontScale
    func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size * fontScale, weight: weight)
    }

    /// 블록 톤 → 색
    func toneColor(_ t: BalanceTone) -> Color {
        switch t {
        case .usual: return usualBlock
        case .good: return good
        case .normal: return normal
        case .bad: return bad
        }
    }
}

private extension View {
    /// 글자 색 — textOutline이 있으면 스탬프와 같은 8방향 테두리(stampOutline), 없으면 색만
    @ViewBuilder
    func balanceText(_ color: Color, _ style: BalanceDrawStyle) -> some View {
        if let o = style.textOutline { self.stampOutline(fill: color, outline: o) }
        else { self.foregroundStyle(color) }
    }
}

// MARK: - 문구 (라벨만 — 문장·판정어 없음)

private enum BalanceDrawingText {
    static func blockLabel(_ k: BalanceBlockKind) -> String {
        let L = AppLanguage.shared
        switch k {
        case .heartRate: return L.s("심박", "Heart rate", ja: "心拍")
        case .effort: return L.s("체감", "RPE", ja: "体感")   // 영어 약어(블록 칸이 좁다)
        case .sleep: return L.s("수면", "Sleep", ja: "睡眠")
        case .hrv: return "HRV"
        case .load: return L.s("부하", "Load", ja: "負荷")   // 저울 칸이 좁아 짧게(막대는 "7일 부하")
        case .cadence: return L.s("케이던스", "Cadence", ja: "ケイデンス")
        case .stride: return L.s("보폭", "Stride", ja: "ストライド")
        case .groundContact: return L.s("접지", "Contact", ja: "接地")
        }
    }

    static func axisLabel(_ k: BalanceAxisKind) -> String {
        let L = AppLanguage.shared
        switch k {
        case .heartRate: return L.s("심박", "Heart rate", ja: "心拍")
        case .cadence: return L.s("케이던스", "Cadence", ja: "ケイデンス")
        case .stride: return L.s("보폭", "Stride", ja: "ストライド")
        case .groundContact: return L.s("접지", "Contact", ja: "接地")
        case .verticalOsc: return L.s("수직 진폭", "Vert. osc.", ja: "上下動")
        }
    }

    /// 꼭짓점 값 — 케이던스 정수 spm · 보폭 0.00m · 접지 정수 ms · 수직 진폭 0.0cm · 심박 정수 bpm
    static func axisValue(_ a: BalanceAxis) -> String {
        switch a.kind {
        case .heartRate: return "\(Int(a.value.rounded()))bpm"
        case .cadence: return "\(Int(a.value.rounded()))spm"
        case .stride: return String(format: "%.2fm", a.value)
        case .groundContact: return "\(Int(a.value.rounded()))ms"
        case .verticalOsc: return String(format: "%.1fcm", a.value)
        }
    }
}

// MARK: - 폼 거미줄

/// 거미줄 크기 — w·h = 바깥 틀, r = 도형 반지름, labelR = 축 라벨 자리 반지름.
/// 탭: 큰 화면 R 108, 그 외 R 88(카드의 ViewThatFits). 2026-11-11 실기기 요청으로 키움(52 → 72 → 96 → 108).
struct BalanceRadarSize {
    let w: CGFloat, h: CGFloat, r: CGFloat, labelR: CGFloat
    var center: CGPoint { CGPoint(x: w / 2, y: h / 2) }
    // 바깥 크기는 그대로, 도형과 라벨 사이 여백(28 → 22pt)을 줄여 도형만 키움(2026-11-11 실기기: 96 → 108)
    static let large = BalanceRadarSize(w: 340, h: 292, r: 108, labelR: 130)
    static let medium = BalanceRadarSize(w: 290, h: 244, r: 88, labelR: 108)
}

/// 거미줄 + 축 라벨·값 (+ 참고 칩). 범례·기준 페이스 줄은 쓰는 쪽에서 붙인다.
struct BalanceRadarView: View {
    let snapshot: BalanceSnapshot
    let size: BalanceRadarSize
    let style: BalanceDrawStyle
    /// 0 → 1: 오늘 도형 펼침
    var progress: Double = 1

    var body: some View {
        let m = size
        let axes = snapshot.axes   // 스냅샷 순서(심박·케이던스·보폭·접지·수직 진폭) 중 있는 것만
        let kinds = axes.map(\.kind)
        let todayR = axes.map { BalanceSnapshot.radius(value: $0.value, stat: $0.stat) }
        return ZStack {
            // 바탕 — 바깥 고리(1.0)와 축선
            RadarPolygon(kinds: kinds, radii: Array(repeating: 1.0, count: kinds.count),
                         maxR: m.r, progress: 1)
                .stroke(style.line, lineWidth: 0.5)
            RadarSpokes(kinds: kinds, maxR: m.r)
                .stroke(style.line, lineWidth: 0.5)
            // 평소 범위 띠(0.25…0.75 = stat 하한…상한). 참고(빌린 구간·판정 불가·장거리)는 옅은 띠 + 점선 테두리
            // (폼 탭 참고 띠와 같은 표기 — 옅은 면 색은 쓰는 쪽이 style.band로 정한다)
            RadarBand(kinds: kinds, inner: 0.25, outer: 0.75, maxR: m.r)
                .fill(style.band, style: FillStyle(eoFill: true))
            if snapshot.isReference {
                RadarBand(kinds: kinds, inner: 0.25, outer: 0.75, maxR: m.r)
                    .stroke(style.referenceStroke ?? style.usual, style: StrokeStyle(lineWidth: 0.8, dash: [2.5, 2.5]))
            }
            // 평소(띠 가운데 = 중앙값) — 점선 도형
            RadarPolygon(kinds: kinds, radii: Array(repeating: 0.5, count: kinds.count),
                         maxR: m.r, progress: 1)
                .stroke(style.usual, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            // 오늘 — 도형(펼쳐짐)
            RadarPolygon(kinds: kinds, radii: todayR, maxR: m.r, progress: progress)
                .fill(style.todayFill)
            RadarPolygon(kinds: kinds, radii: todayR, maxR: m.r, progress: progress)
                .stroke(style.today, lineWidth: 1.5)
            vertexDots(axes: axes, radii: todayR, m: m)
            axisLabels(axes: axes, m: m)
        }
        .frame(width: m.w, height: m.h)
        .overlay(alignment: .topLeading) {
            if snapshot.isReference { referenceChip }
        }
    }

    /// "참고" 칩 — 판정어가 아니라 기준이 참고용이라는 표시
    private var referenceChip: some View {
        Text(AppLanguage.shared.s("참고", "Ref", ja: "参考"))
            .font(style.font(8, .semibold))
            .balanceText(style.chipText ?? style.secondary, style)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(style.chipFill ?? style.band)
            .clipShape(Capsule())
    }

    /// 꼭짓점 점 — 나쁜 방향으로 범위를 벗어난 축은 빨간 점, 좋은 방향은 초록 점(참고 모드는 상태 .unknown이라 없음)
    private func vertexDots(axes: [BalanceAxis], radii: [Double], m: BalanceRadarSize) -> some View {
        ForEach(Array(axes.enumerated()), id: \.element.kind) { i, a in
            let adverse = BalanceSnapshot.isAdverse(a.kind, a.status)
            let favorable = BalanceSnapshot.isFavorable(a.kind, a.status)
            let p = BalanceRadarGeometry.point(a.kind, r: m.r * CGFloat(radii[i] * progress), center: m.center)
            Circle()
                .fill(adverse ? style.bad : (favorable ? style.good : style.today))
                .frame(width: adverse || favorable ? 7 : 4, height: adverse || favorable ? 7 : 4)
                .position(p)
        }
    }

    private func axisLabels(axes: [BalanceAxis], m: BalanceRadarSize) -> some View {
        ForEach(axes, id: \.kind) { a in
            let p = BalanceRadarGeometry.point(a.kind, r: m.labelR, center: m.center)
            VStack(spacing: 0) {
                // 축 이름은 회색 — 빨강은 평소 범위 밖 값에만(지표 의미색 빨강 "심박"이 나쁜 값처럼 읽혔다, 2026-11-11)
                Text(BalanceDrawingText.axisLabel(a.kind))
                    .font(style.font(9, .medium))
                    .balanceText(style.secondary, style)
                Text(BalanceDrawingText.axisValue(a))
                    .font(style.font(12, .semibold))
                    .monospacedDigit()
                    .balanceText(BalanceSnapshot.isAdverse(a.kind, a.status) ? style.bad
                                 : (BalanceSnapshot.isFavorable(a.kind, a.status) ? style.good : style.primary),
                                 style)
            }
            .lineLimit(1)
            .fixedSize()
            .position(p)
        }
    }
}

// MARK: - 저울

/// 판·받침·블록·블록 이름(+ 아래 캡션 "몸 상태·부담 / 움직임"). 판 폭은 쓰는 쪽이 정한다.
struct BalanceScaleView: View {
    let snapshot: BalanceSnapshot
    let boardW: CGFloat
    let style: BalanceDrawStyle
    /// 0 → 1: 판 기울기
    var progress: Double = 1
    var showCaptions: Bool = true // "몸 상태·부담 / 움직임"

    static let blockSlotMax: CGFloat = 26
    static let blockMaxH: CGFloat = 60
    static let boardH: CGFloat = 4
    static let labelRowH: CGFloat = 18
    static let groupSpacing: CGFloat = 2
    /// 판 아래 가장자리 y — 회전 축(받침 꼭짓점)
    static var pivotY: CGFloat { blockMaxH + groupSpacing + boardH }
    static var groupH: CGFloat { pivotY + groupSpacing + labelRowH }
    static let fulcrumW: CGFloat = 22
    static let fulcrumH: CGFloat = 20

    /// 기울어진 판 끝의 위아래 이동량 + 2pt — 최종 기울기 기준(애니메이션 중 배치가 흔들리지 않게)
    static func tiltRoom(tilt: Double, boardW: CGFloat) -> CGFloat {
        let rad = abs(tilt) * 12 * Double.pi / 180
        return (boardW / 2 * CGFloat(sin(rad))).rounded(.up) + 2
    }

    /// 캡션을 뺀 저울 높이(판 끝 이동 자리 + 받침) — 쓰는 쪽이 줄 높이를 잡을 때
    static func drawingHeight(snapshot: BalanceSnapshot, boardW: CGFloat) -> CGFloat {
        (pivotY + fulcrumH + 3) + 2 * tiltRoom(tilt: snapshot.tilt, boardW: boardW)
    }

    private var tiltRoom: CGFloat { Self.tiltRoom(tilt: snapshot.tilt, boardW: boardW) }

    /// 한 접시의 블록 칸 폭 — 반폭을 블록 수(최소 5칸)로 나눠 최대 blockSlotMax
    private var slotW: CGFloat {
        let halfW = (boardW - Self.fulcrumW - 8) / 2
        let n = max(5, snapshot.inputBlocks.count, snapshot.outputBlocks.count)
        return min(Self.blockSlotMax, (halfW / CGFloat(n)).rounded(.down))
    }

    /// 판 기울기(도) — tilt × 12. + = 왼쪽이 내려감(반시계) — 빨강 블록이 많은 쪽
    private var tiltDegrees: Double { -snapshot.tilt * 12 * progress }

    var body: some View {
        let L = AppLanguage.shared
        return VStack(spacing: 4) {
            ZStack(alignment: .top) {
                fulcrum
                    .offset(y: Self.pivotY)
                beamGroup
                    .rotationEffect(.degrees(tiltDegrees),
                                    anchor: UnitPoint(x: 0.5, y: Self.pivotY / Self.groupH))
            }
            .frame(width: boardW, height: Self.pivotY + Self.fulcrumH + 3, alignment: .top)
            // rotationEffect는 배치에 반영되지 않는다 — 판 끝이 오르내리는 만큼(반폭 × sin 각도) 위아래 자리를 비워
            // 기운 블록이 위 구분선에, 기운 블록 이름이 아래 "몸 상태·부담 / 움직임"에 겹치지 않게(내보내기도 잘리지 않음)
            .padding(.vertical, tiltRoom)
            if showCaptions {
                HStack {
                    // 이름 변경(2026-11-11): 왼쪽은 러닝 중 부담 + 출발 전 몸 상태, 오른쪽은 같은 페이스를 만든 방식(폼)이라
                    // "들인 것 / 나온 것"은 정확하지 않았다
                    Text(L.s("몸 상태·부담", "Body & strain", ja: "体の状態・負担"))
                    Spacer(minLength: 0)
                    Text(L.s("움직임", "Movement", ja: "動き"))
                }
                .font(style.font(11, .semibold))
                .tracking(0.3)
                .balanceText(style.caption ?? style.secondary, style)
                .frame(width: boardW - 24)
            }
        }
        .fixedSize()
    }

    /// 받침 — 꼭짓점이 판 가운데 아래에 닿는 삼각형 + 바닥 선
    private var fulcrum: some View {
        VStack(spacing: 0) {
            FulcrumShape()
                .fill(style.fulcrum ?? style.board)
                .frame(width: Self.fulcrumW, height: Self.fulcrumH)
            Capsule().fill(style.fulcrumBase ?? style.board).frame(width: 56, height: 3)
        }
    }

    /// 판 + 양쪽 블록 + 블록 이름 — 한 덩어리로 기운다
    private var beamGroup: some View {
        let halfW = (boardW - Self.fulcrumW - 8) / 2
        let slot = slotW
        return VStack(spacing: Self.groupSpacing) {
            HStack(spacing: 0) {
                blockRow(snapshot.inputBlocks, slotW: slot).frame(width: halfW)
                Spacer(minLength: 0)
                blockRow(snapshot.outputBlocks, slotW: slot).frame(width: halfW)
            }
            .frame(height: Self.blockMaxH, alignment: .bottom)
            Capsule()
                .fill(style.board)
                .frame(height: Self.boardH)
            HStack(spacing: 0) {
                labelRow(snapshot.inputBlocks, slotW: slot).frame(width: halfW)
                Spacer(minLength: 0)
                labelRow(snapshot.outputBlocks, slotW: slot).frame(width: halfW)
            }
            .frame(height: Self.labelRowH, alignment: .top)
        }
        .frame(width: boardW, height: Self.groupH)
    }

    private func blockRow(_ blocks: [BalanceBlock], slotW: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            // 올릴 블록이 없는 접시(폼 없는 러닝의 움직임 등)는 "—"
            if blocks.isEmpty {
                Text("—")
                    .font(style.font(12, .medium))
                    .balanceText(style.emptyMark ?? style.secondary, style)
            }
            ForEach(blocks, id: \.kind) { b in
                RoundedRectangle(cornerRadius: 3)
                    .fill(style.toneColor(b.tone))
                    .frame(width: (slotW * 0.6).rounded(), height: max(4, Self.blockMaxH * b.height))
                    .frame(width: slotW)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func labelRow(_ blocks: [BalanceBlock], slotW: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(blocks, id: \.kind) { b in
                Text(BalanceDrawingText.blockLabel(b.kind))
                    .font(style.font(7.5, .medium))
                    .balanceText(style.blockLabel ?? style.secondary, style)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .frame(width: slotW)
            }
        }
    }
}

// MARK: - 도형

/// 받침 삼각형 — 꼭짓점이 위
private struct FulcrumShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 거미줄 다각형 — 축 자리(고정 다섯 자리 중 있는 것)마다 반지름 비율(0…1) × maxR × progress
private struct RadarPolygon: Shape {
    let kinds: [BalanceAxisKind]
    let radii: [Double]
    let maxR: CGFloat
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for (i, k) in kinds.enumerated() {
            let a = BalanceRadarGeometry.angle(k)
            let r = maxR * CGFloat(radii[i] * progress)
            let pt = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// 평소 범위 띠 — 바깥(상한)·안(하한) 두 다각형, 짝홀 채우기로 고리
private struct RadarBand: Shape {
    let kinds: [BalanceAxisKind]
    let inner: Double
    let outer: Double
    let maxR: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = RadarPolygon(kinds: kinds, radii: Array(repeating: outer, count: kinds.count),
                             maxR: maxR, progress: 1).path(in: rect)
        p.addPath(RadarPolygon(kinds: kinds, radii: Array(repeating: inner, count: kinds.count),
                               maxR: maxR, progress: 1).path(in: rect))
        return p
    }
}

/// 축선 — 가운데에서 바깥 고리까지
private struct RadarSpokes: Shape {
    let kinds: [BalanceAxisKind]
    let maxR: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for k in kinds {
            let a = BalanceRadarGeometry.angle(k)
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + maxR * CGFloat(cos(a)), y: c.y + maxR * CGFloat(sin(a))))
        }
        return p
    }
}

/// 축 각도 — 다섯 자리 고정(맨 위 심박부터 시계 방향). 도형과 글자가 같은 값을 쓴다.
private enum BalanceRadarGeometry {
    static func angle(_ k: BalanceAxisKind) -> Double {
        let i = BalanceAxisKind.allCases.firstIndex(of: k) ?? 0
        return -Double.pi / 2 + Double(i) * 2 * Double.pi / 5
    }

    /// 축 자리의 점 — 없는 축은 자리를 비운다(다섯 자리 고정)
    static func point(_ k: BalanceAxisKind, r: CGFloat, center: CGPoint) -> CGPoint {
        let a = angle(k)
        return CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
    }
}
