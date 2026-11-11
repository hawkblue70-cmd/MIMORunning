import SwiftUI

// 밸런스 탭 — "오늘 러닝의 나"를 그림 한 장으로. 스펙: docs/superpowers/specs/2026-11-11-balance-tab-design.md
// 판정은 모두 BalanceSnapshot(폼 탭과 같은 기준선·판정)이 하고, 이 뷰는 스냅샷만 그린다.
// 앱 화면과 내보내기(InsightExportSheet)가 같은 뷰를 쓴다 — 미리보기 = 출력, 별도 레이아웃 금지(§5.8).

// MARK: - 입력 조립 (접착 코드)

extension BalanceSnapshot.Input {
    /// 폼 탭·총평과 같은 입력에서 채운다. 판정 stat은 bb 기반(판정용), 참고 모드면 그리는 stat(displayBb 기반).
    static func from(form: TabDigestForm.Inputs, summary: RunSummaryInput, activity: Activity,
                     history: [Activity], effortIndex: EffortIndex?, typeOf: ((UUID) -> WorkoutType?)?,
                     vo2Points: [(date: Date, value: Double)]) -> BalanceSnapshot.Input {
        let ref = form.isReferenceBand
        // 오늘 페이스 구간은 있지만 표본이 모자라 판정 불가 — 폼 탭처럼 그리기만 하고 빨간 점·점수는 없다
        let notJudgeable = !ref && form.bb?.isJudgeable == false
        let band = ref ? form.displayBb : form.bb

        // 체감 강도 — 같은 종류 평소 강도(최근 8주 중앙값) 대비
        let effort = effortIndex?.resolve(activity.id)?.value
        let effortMedian: Int? = effortIndex.flatMap { idx in
            let samples = EffortBaseline.samples(current: activity, history: history, index: idx,
                                                 typeOf: typeOf ?? { _ in nil })
            return EffortBaseline.median(for: form.workoutType, samples: samples)
        }

        // 유산소 — 러닝 날짜 이전 182일(본인 최근 6개월 범위)
        let sixMonthsAgo = Calendar.current.date(byAdding: .day, value: -182, to: activity.date)
            ?? activity.date.addingTimeInterval(-182 * 86_400)
        let vo2Six = vo2Points.filter { $0.date >= sixMonthsAgo && $0.date < activity.date }.map(\.value)

        // HRV — 총평과 같은 출처: 어젯밤 값이 4주 기준보다 15% 넘게 낮으면 어젯밤 낮음
        let trend = summary.hrvTrend
        let hrvLastNightLow: Bool = {
            guard let t = trend, let v = summary.lastNightHRV else { return false }
            return MRReadiness.lastNightDeviation(v, trend: t) < 0
        }()
        // 막대 색(나쁨)과 글자가 엇갈리지 않게 — 7일 추세가 낮음·불안정이 아닌데 어젯밤만 낮으면 그 사실을 쓴다
        let hrvDisplay: String? = trend.map { t in
            if hrvLastNightLow && !t.isVolatile && t.state != .below {
                return AppLanguage.shared.s("어젯밤 낮음", "low last night", ja: "昨夜低め")
            }
            return t.gradeLabel
        }

        return BalanceSnapshot.Input(
            workoutType: form.workoutType,
            paceSecPerKm: activity.paceSecPerKm,
            hasForm: form.avgCadence != nil,
            isReferenceBand: ref || notJudgeable,
            heartRate: activity.avgHeartRate.map(Double.init), heartRateStat: band?.heartRate,
            cadence: form.avgCadence.map(Double.init), cadenceStat: band?.cadence,
            stride: form.avgStrideLength, strideStat: ref ? form.displayStrideStat : form.strideStat,
            groundContact: form.avgGroundContactTime,
            groundContactStat: ref ? form.displayGctStat : form.adjustedGctStat,
            verticalOsc: form.avgVerticalOscillation, verticalOscStat: band?.verticalOsc,
            effort: effort, effortTypeMedian: effortMedian,
            sleepHours: summary.lastNightSleepHours,
            usualSleepHours: MREngineStore.persistedUsualSleepHours(asOf: activity.date),
            hrvLevel: BalanceSnapshot.hrvLevel(summary.hrvTrend, lastNightLow: hrvLastNightLow),
            hrvDisplay: hrvDisplay,
            load: summary.acuteChronic,
            vo2: summary.vo2, vo2SixMonths: vo2Six)
    }
}

extension BalanceTabCard {
    /// 탭 카드·내보내기 시트가 같은 식으로 부른다 — 총평과 같은 Context, 폼 탭과 같은 판정 재료.
    static func snapshot(context c: RunSummaryBuilder.Context,
                         vo2Points: [(date: Date, value: Double)]) -> BalanceSnapshot? {
        let form = TabDigestForm.Inputs(
            activity: c.activity, detail: c.detail, baseline: c.formBaseline, formShifts: c.formShifts,
            workoutType: c.workoutType,
            typicalKm: RunSummaryBuilder.typicalRunDistanceKm(activity: c.activity, history: c.history),
            fatigueContext: nil)
        let summary = RunSummaryBuilder.input(c)
        return BalanceSnapshot.make(.from(form: form, summary: summary, activity: c.activity,
                                          history: c.history, effortIndex: c.effortIndex,
                                          typeOf: c.workoutTypeFn, vo2Points: vo2Points))
    }
}

// MARK: - 카드

struct BalanceTabCard: View {
    let snapshot: BalanceSnapshot
    var isExport: Bool = false   // 내보내기: 애니메이션 없이 최종 상태

    @Environment(\.insightLight) private var insightLight
    @Environment(\.insightCompact) private var compact
    private var ink: InsightInk { InsightInk(light: insightLight) }
    @State private var appeared = false
    /// 0 → 1: 저울 기울기·도형 펼침·막대 채움. 내보내기는 처음부터 1.
    private var progress: Double { (isExport || appeared) ? 1 : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        // 다른 인사이트 카드와 같은 여백 — 내보내기는 위 여백만 줄여 헤더에 붙인다
        .padding(.top, compact ? 4 : 16).padding(.bottom, compact ? 12 : 16)
        .background(ink.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            guard !isExport, !appeared else { return }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) { appeared = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch snapshot.mode {
        case .full:
            scale
            if radarAxes.count >= 3 || !snapshot.bodies.isEmpty {
                divider
                // 거미줄은 고정 크기, 몸 상태 막대가 남은 폭을 쓴다(좁은 화면에서도 넘치지 않게)
                HStack(alignment: .center, spacing: 10) {
                    if radarAxes.count >= 3 { radar }
                    if !snapshot.bodies.isEmpty { bodyBars.frame(maxWidth: .infinity) }
                }
                .frame(maxWidth: .infinity)
            }
        case .scaleOnly:
            scale
            if !snapshot.bodies.isEmpty {
                divider
                bodyBars
            }
        case .bodyOnly:
            bodyBars
        }
    }

    private var divider: some View {
        Rectangle().fill(ink.fg(0.08)).frame(height: 0.5)
    }

    // MARK: 색

    private func levelColor(_ l: BalanceLevel) -> Color {
        switch l {
        case .good: return ink.positive
        case .normal: return ink.pick(Color(hex: "F5C542"), Color(hex: "D4A700"))
        case .bad: return ink.pick(Color(hex: "FF5A5F"), Color(hex: "E0242B"))
        }
    }

    private var badColor: Color { levelColor(.bad) }

    private func toneColor(_ t: BalanceTone) -> Color {
        switch t {
        case .usual: return ink.fg(0.32)
        case .good: return levelColor(.good)
        case .normal: return levelColor(.normal)
        case .bad: return levelColor(.bad)
        }
    }

    // MARK: 문구 (라벨만 — 문장·판정어 없음)

    private func blockLabel(_ k: BalanceBlockKind) -> String {
        let L = AppLanguage.shared
        switch k {
        case .heartRate: return L.s("심박", "Heart rate", ja: "心拍")
        case .effort: return L.s("체감", "RPE", ja: "体感")   // 영어는 저울 "Effort in"과 겹치지 않게
        case .sleep: return L.s("수면", "Sleep", ja: "睡眠")
        case .hrv: return "HRV"
        case .load: return L.s("7일 부하", "7-day load", ja: "7日負荷")
        case .cadence: return L.s("케이던스", "Cadence", ja: "ケイデンス")
        case .stride: return L.s("보폭", "Stride", ja: "ストライド")
        case .groundContact: return L.s("접지", "Contact", ja: "接地")
        }
    }

    private func axisLabel(_ k: BalanceAxisKind) -> String {
        let L = AppLanguage.shared
        switch k {
        case .heartRate: return L.s("심박", "Heart rate", ja: "心拍")
        case .cadence: return L.s("케이던스", "Cadence", ja: "ケイデンス")
        case .stride: return L.s("보폭", "Stride", ja: "ストライド")
        case .groundContact: return L.s("접지", "Contact", ja: "接地")
        case .verticalOsc: return L.s("수직 진폭", "Vert. osc.", ja: "上下動")
        }
    }

    private func bodyLabel(_ k: BalanceBodyKind) -> String {
        let L = AppLanguage.shared
        switch k {
        case .sleep: return L.s("수면", "Sleep", ja: "睡眠")
        case .hrv: return "HRV"
        case .load: return L.s("7일 부하", "7-day load", ja: "7日負荷")
        case .vo2: return L.s("유산소", "VO2max", ja: "VO2max")
        }
    }

    /// 꼭짓점 값 — 케이던스 정수 spm · 보폭 0.00m · 접지 정수 ms · 수직 진폭 0.0cm · 심박 정수 bpm
    private func axisValue(_ a: BalanceAxis) -> String {
        switch a.kind {
        case .heartRate: return "\(Int(a.value.rounded()))bpm"
        case .cadence: return "\(Int(a.value.rounded()))spm"
        case .stride: return String(format: "%.2fm", a.value)
        case .groundContact: return "\(Int(a.value.rounded()))ms"
        case .verticalOsc: return String(format: "%.1fcm", a.value)
        }
    }

    /// 축 이름 색 — 폼 카드 행 라벨과 같은 지표 의미색(심박 빨강·케이던스 노랑 …)
    private func axisColor(_ k: BalanceAxisKind) -> Color {
        switch k {
        case .heartRate: return ink.heartRate
        case .cadence: return ink.metricText(ink.cadence)
        case .stride: return ink.metricText(ink.strideLength)
        case .groundContact: return ink.groundContact
        case .verticalOsc: return ink.metricText(ink.verticalOsc)
        }
    }

    // MARK: - 저울

    private static let boardW: CGFloat = 288
    private static let blockSlotW: CGFloat = 25
    private static let blockW: CGFloat = 15
    private static let blockMaxH: CGFloat = 44
    private static let boardH: CGFloat = 4
    private static let labelRowH: CGFloat = 18
    private static let groupSpacing: CGFloat = 2
    /// 판 아래 가장자리 y — 회전 축(받침 꼭짓점)
    private static var pivotY: CGFloat { blockMaxH + groupSpacing + boardH }
    private static var groupH: CGFloat { pivotY + groupSpacing + labelRowH }
    private static let fulcrumW: CGFloat = 22
    private static let fulcrumH: CGFloat = 20

    /// 판 기울기(도) — tilt × 12. + = 왼쪽(들인 것)이 내려감 = 반시계 방향
    private var tiltDegrees: Double { -snapshot.tilt * 12 * progress }

    private var scale: some View {
        let L = AppLanguage.shared
        return VStack(spacing: 4) {
            ZStack(alignment: .top) {
                fulcrum
                    .offset(y: Self.pivotY)
                beamGroup
                    .rotationEffect(.degrees(tiltDegrees),
                                    anchor: UnitPoint(x: 0.5, y: Self.pivotY / Self.groupH))
            }
            .frame(width: Self.boardW, height: Self.pivotY + Self.fulcrumH + 3, alignment: .top)
            HStack {
                Text(L.s("들인 것", "Effort in", ja: "かけたもの"))
                Spacer(minLength: 0)
                Text(L.s("나온 것", "Output", ja: "出たもの"))
            }
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(ink.fg(0.75))
            .frame(width: Self.boardW - 24)
        }
        .frame(maxWidth: .infinity)
    }

    /// 받침 — 꼭짓점이 판 가운데 아래에 닿는 삼각형 + 바닥 선
    private var fulcrum: some View {
        VStack(spacing: 0) {
            FulcrumShape()
                .fill(ink.fg(0.22))
                .frame(width: Self.fulcrumW, height: Self.fulcrumH)
            Capsule().fill(ink.fg(0.18)).frame(width: 56, height: 3)
        }
    }

    /// 판 + 양쪽 블록 + 블록 이름 — 한 덩어리로 기운다
    private var beamGroup: some View {
        let halfW = (Self.boardW - Self.fulcrumW - 8) / 2
        return VStack(spacing: Self.groupSpacing) {
            HStack(spacing: 0) {
                blockRow(snapshot.inputBlocks).frame(width: halfW)
                Spacer(minLength: 0)
                blockRow(snapshot.outputBlocks).frame(width: halfW)
            }
            .frame(height: Self.blockMaxH, alignment: .bottom)
            Capsule()
                .fill(ink.fg(0.45))
                .frame(height: Self.boardH)
            HStack(spacing: 0) {
                labelRow(snapshot.inputBlocks).frame(width: halfW)
                Spacer(minLength: 0)
                labelRow(snapshot.outputBlocks).frame(width: halfW)
            }
            .frame(height: Self.labelRowH, alignment: .top)
        }
        .frame(width: Self.boardW, height: Self.groupH)
    }

    private func blockRow(_ blocks: [BalanceBlock]) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(blocks, id: \.kind) { b in
                RoundedRectangle(cornerRadius: 3)
                    .fill(toneColor(b.tone))
                    .frame(width: Self.blockW, height: max(4, Self.blockMaxH * b.height))
                    .frame(width: Self.blockSlotW)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func labelRow(_ blocks: [BalanceBlock]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(blocks, id: \.kind) { b in
                Text(blockLabel(b.kind))
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(ink.fg(0.60))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(width: Self.blockSlotW)
            }
        }
    }

    // MARK: - 폼 거미줄

    private static let radarW: CGFloat = 210
    private static let radarH: CGFloat = 190
    private static let radarR: CGFloat = 52
    private static let labelR: CGFloat = 72

    /// 그릴 축 — 스냅샷 순서(심박·케이던스·보폭·접지·수직 진폭) 중 있는 것만
    private var radarAxes: [BalanceAxis] { snapshot.axes }

    /// 축 자리의 점 — 없는 축은 자리를 비운다(다섯 자리 고정)
    private static func point(_ k: BalanceAxisKind, r: CGFloat, center: CGPoint) -> CGPoint {
        let a = BalanceRadarGeometry.angle(k)
        return CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
    }

    private var radarCenter: CGPoint { CGPoint(x: Self.radarW / 2, y: Self.radarH / 2) }

    private var radar: some View {
        let axes = radarAxes
        let kinds = axes.map(\.kind)
        let todayR = axes.map { BalanceSnapshot.radius(value: $0.value, stat: $0.stat) }
        return ZStack {
            // 바탕 — 바깥 고리(1.0)와 축선
            RadarPolygon(kinds: kinds, radii: Array(repeating: 1.0, count: kinds.count),
                         maxR: Self.radarR, progress: 1)
                .stroke(ink.fg(0.10), lineWidth: 0.5)
            RadarSpokes(kinds: kinds, maxR: Self.radarR)
                .stroke(ink.fg(0.10), lineWidth: 0.5)
            // 평소 범위 띠(0.25…0.75 = stat 하한…상한) — 회색
            RadarBand(kinds: kinds, inner: 0.25, outer: 0.75, maxR: Self.radarR)
                .fill(ink.fg(0.10), style: FillStyle(eoFill: true))
            // 평소(띠 가운데 = 중앙값) — 회색 도형
            RadarPolygon(kinds: kinds, radii: Array(repeating: 0.5, count: kinds.count),
                         maxR: Self.radarR, progress: 1)
                .stroke(ink.fg(0.40), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            // 오늘 — 보라 도형(펼쳐짐)
            RadarPolygon(kinds: kinds, radii: todayR, maxR: Self.radarR, progress: progress)
                .fill(ink.violet.opacity(0.22))
            RadarPolygon(kinds: kinds, radii: todayR, maxR: Self.radarR, progress: progress)
                .stroke(ink.violet, lineWidth: 1.5)
            vertexDots(axes: axes, radii: todayR)
            axisLabels(axes: axes)
            paceCenter
        }
        .frame(width: Self.radarW, height: Self.radarH)
    }

    /// 꼭짓점 점 — 나쁜 방향으로 범위를 벗어난 축만 빨간 점(참고 모드는 상태 .unknown이라 없음)
    private func vertexDots(axes: [BalanceAxis], radii: [Double]) -> some View {
        ForEach(Array(axes.enumerated()), id: \.element.kind) { i, a in
            let adverse = BalanceSnapshot.isAdverse(a.kind, a.status)
            let p = Self.point(a.kind, r: Self.radarR * CGFloat(radii[i] * progress), center: radarCenter)
            Circle()
                .fill(adverse ? badColor : ink.violet)
                .frame(width: adverse ? 7 : 4, height: adverse ? 7 : 4)
                .position(p)
        }
    }

    private func axisLabels(axes: [BalanceAxis]) -> some View {
        ForEach(axes, id: \.kind) { a in
            let p = Self.point(a.kind, r: Self.labelR, center: radarCenter)
            VStack(spacing: 0) {
                Text(axisLabel(a.kind))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(axisColor(a.kind))
                Text(axisValue(a))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(BalanceSnapshot.isAdverse(a.kind, a.status) ? badColor : ink.primary)
            }
            .lineLimit(1)
            .fixedSize()
            .position(p)
        }
    }

    /// 가운데 페이스 — 기준이 "같은 페이스"라 축이 아니라 숫자로
    @ViewBuilder
    private var paceCenter: some View {
        if let pace = snapshot.paceSecPerKm {
            VStack(spacing: 0) {
                Text(mrFormatPace(pace))
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(ink.pace)
                Text("/km")
                    .font(.system(size: 7))
                    .foregroundStyle(ink.fg(0.55))
            }
            .fixedSize()
            .position(radarCenter)
        }
    }

    // MARK: - 몸 상태 막대

    /// 막대 길이 = 부담(좋음 ⅓ · 보통 ⅔ · 나쁨 가득) — 저울 블록 높이와 같은 방향
    private func bodyFill(_ l: BalanceLevel) -> Double {
        switch l {
        case .good: return 0.34
        case .normal: return 0.67
        case .bad: return 1.0
        }
    }

    private var bodyBars: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            ForEach(snapshot.bodies, id: \.kind) { b in
                bodyRow(b)
            }
        }
    }

    private func bodyRow(_ b: BalanceBody) -> some View {
        let c = levelColor(b.level)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(bodyLabel(b.kind))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(ink.fg(0.70))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(b.display)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ink.metricText(c))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Capsule()
                .fill(ink.fg(0.08))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule()
                            .fill(c)
                            .frame(width: g.size.width * CGFloat(bodyFill(b.level) * progress))
                    }
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
}
