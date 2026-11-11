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
            isMixedPace: form.isStructured,
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
            // 폼 탭과 같은 피로 맥락·이지 존 비율 — 폼 문장 요약(formNote)이 폼 탭과 같게
            fatigueContext: RunSummaryBuilder.fatigueContext(activity: c.activity, history: c.history, effortIndex: c.effortIndex))
            .withEasyZone(TabDigestRhythm.easyLowZoneFraction(zones: c.hrZones))
        let summary = RunSummaryBuilder.input(c)
        guard var snap = BalanceSnapshot.make(.from(form: form, summary: summary, activity: c.activity,
                                                    history: c.history, effortIndex: c.effortIndex,
                                                    typeOf: c.workoutTypeFn, vo2Points: vo2Points)) else { return nil }
        if snap.mode == .full { snap.formNote = TabDigestForm.narrativeShort(form) }
        return snap
    }
}

// MARK: - 카드

struct BalanceTabCard: View {
    let snapshot: BalanceSnapshot
    var isExport: Bool = false   // 내보내기: 애니메이션 없이 최종 상태
    /// 맨 위 요약 — 폼 탭과 같은 뷰(거리·러닝화·시간·페이스·케이던스·보폭, 2026-11-11 사용자 요청)
    var header: RunFormTopSummary? = nil

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
            if let header { header; divider }
            // 위: 저울 + 몸 상태 세로 막대 한 줄, 아래: 거미줄 크게(2026-11-11 실기기 요청)
            scaleAndBodies
            summaryCaption
            if snapshot.hasRadar {
                divider
                radar.frame(maxWidth: .infinity)
                radarLegend
            }
        case .scaleOnly:
            if let header { header; divider }
            scaleAndBodies
            summaryCaption
        case .bodyOnly:
            if let header { header; divider }
            bodyBars
        }
    }

    /// 저울 + 오른쪽 몸 상태 세로 막대 — 늘 한 줄(2026-11-11 사용자 요청: 저울 폭을 줄이고 막대는 오른쪽).
    /// 판 폭은 남는 폭에서 막대 영역을 뺀 값으로 정하되 190~270pt 안에서.
    @ViewBuilder
    private var scaleAndBodies: some View {
        if snapshot.bodies.isEmpty {
            scale(boardW: Self.boardMax).frame(maxWidth: .infinity)
        } else {
            GeometryReader { g in
                let board = min(Self.boardMax, max(Self.boardMin, g.size.width - Self.bodyColumnsW - Self.scaleBarsGap))
                HStack(alignment: .bottom, spacing: Self.scaleBarsGap) {
                    scale(boardW: board)
                    Spacer(minLength: 0)
                    bodyBars.frame(width: Self.bodyColumnsW)
                }
            }
            .frame(height: scaleHeight(Self.boardMax))
        }
    }

    private static let scaleBarsGap: CGFloat = 10

    /// 저울 전체 높이(판 끝 이동 자리 + 받침 + 캡션) — GeometryReader에 줄 높이
    private func scaleHeight(_ boardW: CGFloat) -> CGFloat {
        BalanceScaleView.drawingHeight(snapshot: snapshot, boardW: boardW) + 4 + 16
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
        // 폼 탭 문장 요약 — 같은 함수(TabDigestForm.narrativeShort)라 폼 탭과 같은 말
        if let note = snapshot.formNote {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(AppLanguage.shared.s("폼", "Form", ja: "フォーム"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ink.fg(0.60))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(ink.fg(0.08))
                    .clipShape(Capsule())
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(ink.fg(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    /// 거미줄·저울 공용 뷰(BalanceDrawing.swift)에 넘기는 색 — 탭에서 쓰던 색 그대로(화면 불변)
    private var drawStyle: BalanceDrawStyle {
        BalanceDrawStyle(
            primary: ink.primary,
            secondary: ink.fg(0.55),                               // 축 이름
            line: ink.fg(0.10),                                    // 바깥 고리·축선
            band: ink.fg(snapshot.isReference ? 0.05 : 0.10),      // 참고 모드는 옅은 띠
            usual: ink.fg(0.40),
            today: ink.violet,
            todayFill: ink.violet.opacity(0.22),
            good: levelColor(.good),
            bad: levelColor(.bad),
            usualBlock: ink.fg(0.32),
            normal: levelColor(.normal),
            board: ink.fg(0.45),
            textOutline: nil,
            fontScale: 1,
            blockLabel: ink.fg(0.60),
            caption: ink.fg(0.75),
            emptyMark: ink.fg(0.40),
            referenceStroke: ink.fg(0.32),
            fulcrum: ink.fg(0.22),
            fulcrumBase: ink.fg(0.18),
            chipText: ink.fg(0.60),
            chipFill: ink.fg(0.08))
    }

    // MARK: 문구 (라벨만 — 문장·판정어 없음)

    private func bodyLabel(_ k: BalanceBodyKind) -> String {
        let L = AppLanguage.shared
        switch k {
        case .sleep: return L.s("수면", "Sleep", ja: "睡眠")
        case .hrv: return "HRV"
        case .load: return L.s("7일 부하", "7-day load", ja: "7日負荷")
        case .vo2: return L.s("유산소", "VO2max", ja: "VO2max")
        }
    }

    // MARK: - 저울

    /// 판 폭 — 막대 옆에서 190~270pt(막대 값 글자를 줄여 막대 영역이 좁아진 만큼 판을 넓힘, 2026-11-11)
    private static let boardMax: CGFloat = 270
    private static let boardMin: CGFloat = 190

    /// 저울 그림(BalanceDrawing.swift) — 판·받침·블록·블록 이름 + 캡션
    private func scale(boardW: CGFloat) -> some View {
        BalanceScaleView(snapshot: snapshot, boardW: boardW, style: drawStyle, progress: progress)
    }

    // MARK: - 폼 거미줄

    /// 그릴 축 — 스냅샷 순서(심박·케이던스·보폭·접지·수직 진폭) 중 있는 것만
    private var radarAxes: [BalanceAxis] { snapshot.axes }

    /// 거미줄 크기 — 큰 화면 R 108, 그 외 R 88(2026-11-11 실기기 요청으로 키움, BalanceRadarSize)
    private var radar: some View {
        ViewThatFits(in: .horizontal) {
            BalanceRadarView(snapshot: snapshot, size: .large, style: drawStyle, progress: progress)
            BalanceRadarView(snapshot: snapshot, size: .medium, style: drawStyle, progress: progress)
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
                Text(BalanceDrawingText.samePace(pace))
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
    /// 막대 영역 폭 — 값 글자를 이름과 같은 8pt로 줄여 116 → 96(2026-11-11 실기기)
    private static let bodyColumnsW: CGFloat = 96
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
            // 값 글자 = 아래 이름과 같은 8pt(2026-11-11 실기기 요청). 두 줄까지 — "어젯밤 낮음"이 "어젯밤…"으로 잘렸다(2026-11-11 실기기).
            // 모든 칸이 두 줄 높이를 아래 정렬로 가져 막대 위치가 어긋나지 않는다
            Text(b.display)
                .font(.system(size: 8, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ink.metricText(c))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(height: 20, alignment: .bottom)
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
