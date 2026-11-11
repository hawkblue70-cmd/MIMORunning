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
            isLongDistance: form.isLongDistanceContext,
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
    /// 내보내기 이미지 맨 위 기본 기록("8.42 km · 53:23") — 이미지만 보고도 어떤 러닝인지(앱 화면은 위 종합 카드가 보여 주므로 nil)
    var recordLine: String? = nil

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
            if let recordLine { recordHeader(recordLine) }
            // 위: 저울 + 몸 상태 세로 막대 한 줄, 아래: 거미줄 크게(2026-11-11 실기기 요청)
            scaleAndBodies
            summaryCaption
            if radarAxes.count >= 3 {
                divider
                radar.frame(maxWidth: .infinity)
                radarLegend
            }
        case .scaleOnly:
            if let recordLine { recordHeader(recordLine) }
            scaleAndBodies
            summaryCaption
        case .bodyOnly:
            if let recordLine { recordHeader(recordLine) }
            bodyBars
        }
    }

    /// 내보내기 맨 위 기본 기록 한 줄
    private func recordHeader(_ line: String) -> some View {
        Text(line)
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(ink.primary)
            .frame(maxWidth: .infinity)
    }

    /// 저울 옆에 몸 상태 세로 막대 — 폭이 모자라면(작은 폰) 막대를 저울 아래 한 줄로
    @ViewBuilder
    private var scaleAndBodies: some View {
        if snapshot.bodies.isEmpty {
            scale
        } else {
            ViewThatFits(in: .horizontal) {
                // 막대 영역은 고정 폭 — 글자 이상 폭(약 160pt)으로 재면 ViewThatFits가 늘 아래 배치로 넘어갔다(2026-11-11 실기기)
                HStack(alignment: .bottom, spacing: 10) {
                    scale(boardW: Self.boardNarrow).fixedSize()
                    bodyBars.frame(width: Self.bodyColumnsW)
                }
                VStack(spacing: compact ? 8 : 12) {
                    scale
                    bodyBars
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// 저울 아래 한 줄 해석 — 빨강 블록만 사실로(`BalanceSnapshot.summaryLine`)
    @ViewBuilder
    private var summaryCaption: some View {
        if let line = snapshot.summaryLine {
            Text(line)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ink.fg(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - 저울

    /// 판 폭 — 막대 옆이면 236, 막대가 아래로 내려간 작은 화면은 300 · 270(`scale`의 ViewThatFits).
    private static let boardWide: CGFloat = 300
    private static let boardMid: CGFloat = 270
    /// 몸 상태 막대 옆에 둘 때의 판 폭(2026-11-11 실기기: 저울 폭을 줄이고 옆에 세로 막대)
    private static let boardNarrow: CGFloat = 236
    private static let blockSlotMax: CGFloat = 26
    private static let blockMaxH: CGFloat = 60
    private static let boardH: CGFloat = 4
    private static let labelRowH: CGFloat = 18
    private static let groupSpacing: CGFloat = 2
    /// 판 아래 가장자리 y — 회전 축(받침 꼭짓점)
    private static var pivotY: CGFloat { blockMaxH + groupSpacing + boardH }
    private static var groupH: CGFloat { pivotY + groupSpacing + labelRowH }
    private static let fulcrumW: CGFloat = 22
    private static let fulcrumH: CGFloat = 20

    /// 기울어진 판 끝의 위아래 이동량 + 2pt — 최종 기울기 기준(애니메이션 중 배치가 흔들리지 않게)
    private func tiltRoom(_ boardW: CGFloat) -> CGFloat {
        let rad = abs(snapshot.tilt) * 12 * Double.pi / 180
        return (boardW / 2 * CGFloat(sin(rad))).rounded(.up) + 2
    }

    /// 한 접시의 블록 칸 폭 — 반폭을 블록 수(최소 5칸)로 나눠 최대 30
    private func slotW(_ boardW: CGFloat) -> CGFloat {
        let halfW = (boardW - Self.fulcrumW - 8) / 2
        let n = max(5, snapshot.inputBlocks.count, snapshot.outputBlocks.count)
        return min(Self.blockSlotMax, (halfW / CGFloat(n)).rounded(.down))
    }

    /// 판 기울기(도) — tilt × 12. + = 왼쪽(들인 것)이 내려감 = 반시계 방향
    private var tiltDegrees: Double { -snapshot.tilt * 12 * progress }

    private var scale: some View {
        ViewThatFits(in: .horizontal) {
            scale(boardW: Self.boardWide)
            scale(boardW: Self.boardMid)
            scale(boardW: Self.boardNarrow)
        }
        .frame(maxWidth: .infinity)
    }

    private func scale(boardW: CGFloat) -> some View {
        let L = AppLanguage.shared
        return VStack(spacing: 4) {
            ZStack(alignment: .top) {
                fulcrum
                    .offset(y: Self.pivotY)
                beamGroup(boardW: boardW)
                    .rotationEffect(.degrees(tiltDegrees),
                                    anchor: UnitPoint(x: 0.5, y: Self.pivotY / Self.groupH))
            }
            .frame(width: boardW, height: Self.pivotY + Self.fulcrumH + 3, alignment: .top)
            // rotationEffect는 배치에 반영되지 않는다 — 판 끝이 오르내리는 만큼(반폭 × sin 각도) 위아래 자리를 비워
            // 기운 블록이 위 구분선에, 기운 블록 이름이 아래 "들인 것 / 나온 것"에 겹치지 않게(내보내기도 잘리지 않음)
            .padding(.vertical, tiltRoom(boardW))
            HStack {
                Text(L.s("들인 것", "Effort in", ja: "かけたもの"))
                Spacer(minLength: 0)
                Text(L.s("나온 것", "Output", ja: "出たもの"))
            }
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(ink.fg(0.75))
            .frame(width: boardW - 24)
        }
        .fixedSize()
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
    private func beamGroup(boardW: CGFloat) -> some View {
        let halfW = (boardW - Self.fulcrumW - 8) / 2
        let slot = slotW(boardW)
        return VStack(spacing: Self.groupSpacing) {
            HStack(spacing: 0) {
                blockRow(snapshot.inputBlocks, slotW: slot).frame(width: halfW)
                Spacer(minLength: 0)
                blockRow(snapshot.outputBlocks, slotW: slot).frame(width: halfW)
            }
            .frame(height: Self.blockMaxH, alignment: .bottom)
            Capsule()
                .fill(ink.fg(0.45))
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
            // 올릴 블록이 없는 접시(폼 없는 러닝의 나온 것 등)는 "—"
            if blocks.isEmpty {
                Text("—")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink.fg(0.40))
            }
            ForEach(blocks, id: \.kind) { b in
                RoundedRectangle(cornerRadius: 3)
                    .fill(toneColor(b.tone))
                    .frame(width: (slotW * 0.6).rounded(), height: max(4, Self.blockMaxH * b.height))
                    .frame(width: slotW)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func labelRow(_ blocks: [BalanceBlock], slotW: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(blocks, id: \.kind) { b in
                Text(blockLabel(b.kind))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(ink.fg(0.60))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(width: slotW)
            }
        }
    }

    // MARK: - 폼 거미줄

    // 2026-11-11 실기기 요청으로 크게 — 전체 폭 가운데에 둔다(R 52 → 72)
    /// 거미줄 크기 — 큰 화면 R 96, 그 외 R 76(`radar`의 ViewThatFits). 2026-11-11 실기기 요청으로 두 번 키움(52 → 72 → 96).
    private struct RadarSize {
        let w: CGFloat, h: CGFloat, r: CGFloat, labelR: CGFloat
        var center: CGPoint { CGPoint(x: w / 2, y: h / 2) }
        static let large = RadarSize(w: 340, h: 292, r: 96, labelR: 124)
        static let medium = RadarSize(w: 290, h: 244, r: 76, labelR: 100)
    }

    /// 그릴 축 — 스냅샷 순서(심박·케이던스·보폭·접지·수직 진폭) 중 있는 것만
    private var radarAxes: [BalanceAxis] { snapshot.axes }

    /// 축 자리의 점 — 없는 축은 자리를 비운다(다섯 자리 고정)
    private static func point(_ k: BalanceAxisKind, r: CGFloat, center: CGPoint) -> CGPoint {
        let a = BalanceRadarGeometry.angle(k)
        return CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
    }

    private var radar: some View {
        ViewThatFits(in: .horizontal) {
            radar(.large)
            radar(.medium)
        }
    }

    private func radar(_ m: RadarSize) -> some View {
        let axes = radarAxes
        let kinds = axes.map(\.kind)
        let todayR = axes.map { BalanceSnapshot.radius(value: $0.value, stat: $0.stat) }
        return ZStack {
            // 바탕 — 바깥 고리(1.0)와 축선
            RadarPolygon(kinds: kinds, radii: Array(repeating: 1.0, count: kinds.count),
                         maxR: m.r, progress: 1)
                .stroke(ink.fg(0.10), lineWidth: 0.5)
            RadarSpokes(kinds: kinds, maxR: m.r)
                .stroke(ink.fg(0.10), lineWidth: 0.5)
            // 평소 범위 띠(0.25…0.75 = stat 하한…상한) — 회색. 참고(빌린 구간·판정 불가·장거리)는 옅은 띠 + 점선 테두리(폼 탭 참고 띠와 같은 표기)
            RadarBand(kinds: kinds, inner: 0.25, outer: 0.75, maxR: m.r)
                .fill(ink.fg(snapshot.isReference ? 0.05 : 0.10), style: FillStyle(eoFill: true))
            if snapshot.isReference {
                RadarBand(kinds: kinds, inner: 0.25, outer: 0.75, maxR: m.r)
                    .stroke(ink.fg(0.32), style: StrokeStyle(lineWidth: 0.8, dash: [2.5, 2.5]))
            }
            // 평소(띠 가운데 = 중앙값) — 회색 도형
            RadarPolygon(kinds: kinds, radii: Array(repeating: 0.5, count: kinds.count),
                         maxR: m.r, progress: 1)
                .stroke(ink.fg(0.40), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            // 오늘 — 보라 도형(펼쳐짐)
            RadarPolygon(kinds: kinds, radii: todayR, maxR: m.r, progress: progress)
                .fill(ink.violet.opacity(0.22))
            RadarPolygon(kinds: kinds, radii: todayR, maxR: m.r, progress: progress)
                .stroke(ink.violet, lineWidth: 1.5)
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
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(ink.fg(0.60))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(ink.fg(0.08))
            .clipShape(Capsule())
    }

    /// 꼭짓점 점 — 나쁜 방향으로 범위를 벗어난 축만 빨간 점(참고 모드는 상태 .unknown이라 없음)
    private func vertexDots(axes: [BalanceAxis], radii: [Double], m: RadarSize) -> some View {
        ForEach(Array(axes.enumerated()), id: \.element.kind) { i, a in
            let adverse = BalanceSnapshot.isAdverse(a.kind, a.status)
            let p = Self.point(a.kind, r: m.r * CGFloat(radii[i] * progress), center: m.center)
            Circle()
                .fill(adverse ? badColor : ink.violet)
                .frame(width: adverse ? 7 : 4, height: adverse ? 7 : 4)
                .position(p)
        }
    }

    private func axisLabels(axes: [BalanceAxis], m: RadarSize) -> some View {
        ForEach(axes, id: \.kind) { a in
            let p = Self.point(a.kind, r: m.labelR, center: m.center)
            VStack(spacing: 0) {
                // 축 이름은 회색 — 빨강은 평소 범위 밖 값에만(지표 의미색 빨강 "심박"이 나쁜 값처럼 읽혔다, 2026-11-11)
                Text(axisLabel(a.kind))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(ink.fg(0.55))
                Text(axisValue(a))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(BalanceSnapshot.isAdverse(a.kind, a.status) ? badColor : ink.primary)
            }
            .lineLimit(1)
            .fixedSize()
            .position(p)
        }
    }

    /// 거미줄 아래 범례 + 기준 페이스 — 가운데 숫자는 찌그러진 오늘 도형에 가려졌다(2026-11-11 실기기)
    private var radarLegend: some View {
        let L = AppLanguage.shared
        return HStack(spacing: 10) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(ink.fg(snapshot.isReference ? 0.05 : 0.10))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(ink.fg(snapshot.isReference ? 0.32 : 0), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2])))
                    .frame(width: 12, height: 8)
                Text(L.s("평소 범위", "Usual range", ja: "普段の範囲"))
            }
            HStack(spacing: 4) {
                Rectangle().stroke(ink.fg(0.40), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 12, height: 0.5)
                Text(L.s("평소", "Usual", ja: "普段"))
            }
            HStack(spacing: 4) {
                Capsule().fill(ink.violet).frame(width: 12, height: 2)
                Text(L.s("오늘", "Today", ja: "今日"))
            }
            if let pace = snapshot.paceSecPerKm {
                Text(L.s("같은 페이스 \(mrFormatPace(pace))/km", "same pace \(mrFormatPace(pace))/km", ja: "同じペース \(mrFormatPace(pace))/km"))
                    .monospacedDigit()
                    .foregroundStyle(ink.pace)
            }
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(ink.fg(0.60))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 몸 상태 막대

    /// 몸 상태 — 세로 막대 4개. 막대 높이는 모두 같고 색으로만 좋음·보통·나쁨(길이로 부담을 나타내면 짧은 초록이 모자람처럼 읽혔다)
    private static let bodyColumnsW: CGFloat = 116
    private static let bodyBarH: CGFloat = 56

    private var bodyBars: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(snapshot.bodies, id: \.kind) { b in
                bodyColumn(b)
            }
        }
    }

    private func bodyColumn(_ b: BalanceBody) -> some View {
        let c = levelColor(b.level)
        return VStack(spacing: 4) {
            Text(b.display)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ink.metricText(c))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Capsule()
                .fill(ink.fg(0.08))
                .frame(width: 10, height: Self.bodyBarH)
                .overlay(alignment: .bottom) {
                    Capsule().fill(c)
                        .frame(width: 10, height: Self.bodyBarH * CGFloat(progress))
                }
            Text(bodyLabel(b.kind))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(ink.fg(0.60))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(height: 20, alignment: .top)
        }
        .frame(maxWidth: .infinity)
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
