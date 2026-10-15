import SwiftUI

// MARK: - 러닝 하루 공유 카드(그날 아침 제안 + 러닝 요약 + 다음 날 아침)
//
// 설계: docs/superpowers/specs/2026-10-15-run-day-share-card-design.md
// §5.8 — 오늘의 인사이트 카드(ActivityDetailView.InsightCard)와 이 공유 카드는 아래 공유 뷰를 같이 쓴다:
//   `InsightCardText`(제목·사실·다음 줄 판단) · `TabDigestBlocksView`(탭 요약 블록) ·
//   `RunConditionRow`(날씨·수면 칩) · `RunStatsRow`(거리·페이스·시간·심박 줄).
// 아침 블록은 `MorningSuggestionView` 하나를 그날·다음 날 두 번 쓴다. 새 판정 없음.

// MARK: - 제목·사실·다음 줄

/// 오늘의 인사이트 카드의 글 — 앱 카드와 공유 카드가 같은 규칙으로 고른다.
struct InsightCardText {
    let insight: InsightResult?
    /// 카드 판정 요약 — 있고 드문 사건·대체가 아니면 제목·사실·다음 행동을 이것으로
    var headline: RunHeadline? = nil
    /// 탭 요약 블록 — 사실 줄에서 블록이 이미 말한 축을 빼는 데 쓴다
    var digest: [TabDigest.Block] = []
    /// 대회 해마다 비교 한 문장 — 있으면 대회 러닝(.raceDay)의 부연 줄을 이것으로
    var comparisonLine: String? = nil
    var effortValue: Int? = nil

    var usesHeadline: Bool {
        guard let h = headline else { return false }
        return h.source != .rareEvent && h.source != .fallback
    }

    var title: String {
        (usesHeadline ? headline?.title : nil) ?? insight?.title ?? AppLanguage.shared.s("오늘의 러닝", "Today's Run", ja: "今日のラン")
    }

    /// 다음 행동 — 총평의 "다음" 한 문장(없으면 nil)
    var next: String? { headline?.next }

    var showsComparison: Bool { insight?.theme == .raceDay && comparisonLine != nil }

    /// 사실 줄 — 탭 블록이 같은 축(폼·심박·거리·부하)을 이미 말하면 그 조각을 뺀다. 다 빠지면 nil(줄 숨김).
    /// 드문 사건·대체(엔진 부연·대회 비교)는 블록이 다루지 않으므로 그대로.
    var visibleFact: String? {
        guard usesHeadline, let h = headline else { return displayDetail }
        guard !digest.isEmpty, !h.factParts.isEmpty else { return h.fact }
        let covered = Set(digest.map(\.tab))
        let kept = h.factParts.filter { part in
            guard let tab = Self.tab(for: part.axis) else { return true }
            return !covered.contains(tab)
        }
        return kept.isEmpty ? nil : kept.map(\.text).joined(separator: " · ")
    }

    private static func tab(for axis: RunHeadline.Axis) -> TabDigest.Tab? {
        switch axis {
        case .form:             return .form
        case .heart, .distance: return .rhythm
        case .load:             return .performance
        case .none:             return nil
        }
    }

    private var displayDetail: String {
        guard let ins = insight else { return AppLanguage.shared.s("인사이트 분석 준비 중", "Analyzing…", ja: "インサイトを分析中") }
        if showsComparison, let line = comparisonLine { return line }
        if ins.theme == .adverseCondition, let e = effortValue {
            return ins.detail + AppLanguage.shared.s(" · 체감 강도 \(e)", " · effort \(e)/10", ja: " · 体感強度 \(e)")
        }
        return ins.detail
    }
}

// MARK: - 탭 요약 블록(리듬 → 폼 → 퍼포먼스)

/// 애플 건강 앱 스타일 헤더 + 점 + 문장 + → 방향. `onSelect`가 있으면 블록이 버튼(그 탭으로 이동)·셰브런 표시,
/// nil이면 그림만(공유 카드).
struct TabDigestBlocksView: View {
    let digest: [TabDigest.Block]
    /// 위 "다음" 줄 — 블록 방향이 같은 문장이면 블록에서는 생략(같은 권고 두 번 방지)
    var headlineNext: String? = nil
    var onSelect: ((InsightTabKind) -> Void)? = nil
    /// 짧은 줄 아래 카드 원문을 한 줄 더(공유 카드 — 탭을 열어 볼 수 없으니 조금 자세히). 앱 화면은 끔.
    var showsDetail: Bool = false

    static func kind(_ t: TabDigest.Tab) -> InsightTabKind {
        switch t {
        case .rhythm:      return .rhythm
        case .form:        return .form
        case .performance: return .performance
        }
    }

    /// 탭 카테고리 색 — 리듬 = 심박 빨강, 폼 = 페이스 청록, 퍼포먼스 = 브랜드 바이올렛
    private static func tint(_ t: TabDigest.Tab) -> Color {
        switch t {
        case .rhythm:      return Theme.heartRate
        case .form:        return Theme.pace
        case .performance: return Theme.violet
        }
    }

    private static func icon(_ t: TabDigest.Tab) -> String {
        switch t {
        case .rhythm:      return "heart.fill"
        case .form:        return "figure.run"
        case .performance: return "chart.line.uptrend.xyaxis"
        }
    }

    private static func dotColor(_ tone: TabDigest.Tone) -> Color {
        switch tone {
        case .caution: return Theme.caution          // 총평(RunSummaryLinesView) 주의 줄과 같은 색
        case .good:    return Theme.positive
        case .neutral: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(digest.enumerated()), id: \.offset) { i, b in
                if i > 0 {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5)
                }
                block(b)
            }
        }
        .contentTransition(.opacity)
    }

    @ViewBuilder
    private func block(_ b: TabDigest.Block) -> some View {
        let tab = Self.kind(b.tab)
        if let onSelect {
            Button { onSelect(tab) } label: { content(b, tappable: true) }
                .buttonStyle(.plain)
                .accessibilityHint(AppLanguage.shared.s("\(tab.title) 탭으로 이동합니다", "Opens the \(tab.title) tab", ja: "\(tab.title)タブに移動します"))
        } else {
            content(b, tappable: false)
        }
    }

    private func content(_ b: TabDigest.Block, tappable: Bool) -> some View {
        let tab = Self.kind(b.tab)
        return VStack(alignment: .leading, spacing: 5) {
            // 애플 건강 앱 스타일 — 카테고리 아이콘 + 색 제목, 오른쪽 끝 셰브런(누를 수 있을 때만)
            HStack(spacing: 5) {
                Image(systemName: Self.icon(b.tab))
                    .font(.system(size: 12, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 4)
                if tappable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(Self.tint(b.tab))
            // 원문 줄은 블록당 하나 — 원문이 있는 첫 문장에만(4:5 축소로 글자가 작아지지 않게, 2026-10-15)
            let detailIndex = showsDetail ? b.statements.firstIndex { $0.detail != nil } : nil
            ForEach(Array(b.statements.enumerated()), id: \.offset) { i, st in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle()
                        .fill(Self.dotColor(st.tone))
                        .frame(width: 6, height: 6)
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(st.text)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        if i == detailIndex, let d = st.detail {
                            Text(d)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            if let dir = b.direction, dir != headlineNext {
                Text("→ " + dir)
                    .font(.footnote)
                    .foregroundStyle(Theme.violet)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - 날씨·수면 칩 줄

struct ConditionChip: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(label).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

/// 컨디션 행: 날씨 칩 + 수면 칩(등급) + 수면 시간. 날씨·수면이 다 없으면 아무것도 그리지 않는다.
struct RunConditionRow: View {
    let activity: Activity
    let condition: ActivityCondition?

    private func sleepDurationText(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        let h = total / 60, m = total % 60
        return AppLanguage.shared.s("수면 시간 \(h)시간 \(m)분", "Slept \(h)h \(m)m", ja: "睡眠時間 \(h)時間\(m)分")
    }

    var body: some View {
        if let cond = condition, cond.weather != nil || cond.sleepScore != nil {
            HStack(alignment: .center, spacing: 6) {
                if let w = cond.weather {
                    // ⚠ 숫자·색상 모두 HK 메타데이터(activity.temperatureC)로 통일.
                    //   condition?.weather는 외부 API라 값이 다를 수 있다 — 아이콘만 차용.
                    let hkTemp = activity.temperatureC
                    let wColor: Color = {
                        if w.isRainy            { return Theme.pace }
                        if (hkTemp ?? 0) >= 28  { return Theme.calories }
                        if (hkTemp ?? 99) <= 2  { return .blue }
                        return .secondary
                    }()
                    let tempLabel = hkTemp.map { String(format: "%.0f°C", $0) } ?? w.formattedTemp
                    ConditionChip(icon: w.systemIcon(at: activity.date), label: tempLabel, color: wColor)
                }
                if let slp = cond.sleepScore {
                    // 등급 라벨 칩 (숫자 없음 — Apple Health 스타일)
                    ConditionChip(
                        icon: "bed.double.fill",
                        label: AppLanguage.shared.s(
                            "수면 \(slp.chipLabel)",
                            "Sleep \(slp.chipLabel)", ja: "睡眠 \(slp.chipLabel)"
                        ),
                        color: slp.isInsufficient ? Theme.time : .secondary
                    )
                    // 수면 시간 — 사실만. 예전 등급별 처방("오늘 힘껏 달려도 좋습니다")은 수면만 보고 부하(대회 다음 날·
                    // 고강도 연속)를 몰라 홈 아침 제안("오늘은 이지런")과 어긋났고, 끝난 러닝에 처방이라 맞지도 않았다.
                    // "오늘 어떻게 달릴지"는 홈 카드(MRReadiness) 한 곳에서만 말한다.
                    Text(sleepDurationText(slp.sleepHours))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 기록 줄

/// 거리 · 페이스 · 시간 · 심박 — 지표 의미색(§11).
struct RunStatsRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 4) {
            Text(activity.formattedDistance)
                .foregroundStyle(Theme.violet)
            if let pace = activity.formattedPace {
                Text("·").foregroundStyle(.tertiary)
                Text(pace).foregroundStyle(Theme.pace)
            }
            Text("·").foregroundStyle(.tertiary)
            Text(activity.formattedDuration).foregroundStyle(Theme.time)
            if let hr = activity.avgHeartRate {
                Text("·").foregroundStyle(.tertiary)
                Text("\(hr)bpm").foregroundStyle(Theme.heartRate)
            }
        }
        .font(.system(size: 13, weight: .semibold))
    }
}

// MARK: - 아침 제안 한 덩어리

/// 라벨("당일 아침") + 제안 줄(판정 색 = 홈과 같은 displayColor) + why 전체 + data + planLine.
/// 제안이 없고 `direction`이 있으면 "→ 다음: {방향}" 한 줄. 둘 다 없으면 아무것도 그리지 않는다.
struct MorningSuggestionView: View {
    let label: String
    let entry: InsightMorning.Entry?
    var direction: String? = nil

    var body: some View {
        let L = AppLanguage.shared
        if let e = entry {
            let color = InsightMorning.level(from: e.level)?.displayColor ?? Color.white
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.violetText)
                Text(e.line)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
                if !e.why.isEmpty {
                    Text(e.why)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !e.data.isEmpty {
                    Text(e.data)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !e.planLine.isEmpty {
                    Text(e.planLine)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let d = direction, !d.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.violetText)
                Text("→ " + L.s("다음: ", "Next: ", ja: "次: ") + d)
                    .font(.subheadline)
                    .foregroundStyle(Theme.violet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 공유 날짜 줄

enum ShareDateText {
    /// "2026. 10. 13 화 오후 6:10" — 요일만 노랑. 인사이트 내보내기 머리와 같은 형식.
    static func text(for date: Date) -> Text {
        let L = AppLanguage.shared
        let loc = L.locale
        let fDate = DateFormatter(); fDate.locale = loc
        fDate.dateFormat = L.s("yyyy. M. d ", "MMM d, yyyy ", ja: "yyyy年M月d日 ")
        let fDay  = DateFormatter(); fDay.locale  = loc; fDay.dateFormat = "EEE"
        let fTime = DateFormatter(); fTime.locale = loc
        fTime.dateFormat = L.s(" a h:mm", " h:mm a", ja: " H:mm")
        return Text(fDate.string(from: date)).foregroundStyle(.white.opacity(0.65))
             + Text(fDay.string(from: date)).foregroundStyle(Color.yellow)
             + Text(fTime.string(from: date)).foregroundStyle(.white.opacity(0.65))
    }
}

// MARK: - 카드

/// 위 → 아래: 워드마크·날짜 → 그날 아침 → 구분선 → 오늘의 러닝 → 구분선 → 다음 날 아침. 다크 고정.
/// 미리보기와 출력이 이 뷰 하나다.
struct RunDayShareCard: View {
    let activity: Activity
    /// 러닝 유형 라벨("이지런" 등) — 없으면 활동 유형 이름
    var workoutTypeLabel: String? = nil
    let text: InsightCardText
    var condition: ActivityCondition? = nil
    var digest: [TabDigest.Block] = []
    var morning: InsightMorning? = nil
    /// 이 러닝까지의 이번 주(월요일 시작)·이번 달 러닝 거리(km) — 날짜 밑 한 줄
    var weekKm: Double? = nil
    var monthKm: Double? = nil

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5)
    }

    /// "이번 주 16.2km · 이번 달 87.3km"
    private var distanceLine: String? {
        let L = AppLanguage.shared
        var parts: [String] = []
        if let w = weekKm { parts.append(L.s("이번 주 ", "This week ", ja: "今週 ") + String(format: "%.1fkm", w)) }
        if let m = monthKm { parts.append(L.s("이번 달 ", "This month ", ja: "今月 ") + String(format: "%.1fkm", m)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        let L = AppLanguage.shared
        let ofLabel = L.s("당일 아침", "That morning", ja: "当日の朝")
        let hasMorningOf = morning?.morningOf != nil
        // 순서(2026-10-15 사용자): 오늘의 러닝 결과 → 당일 아침 제안. 다음 날 아침은 넣지 않는다.
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                MIMOWordmark(size: 9)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    ShareDateText.text(for: activity.date)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let line = distanceLine {
                        Text(line)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }

            // ── 오늘의 러닝 — 앱 오늘의 인사이트 카드와 같은 글·같은 뷰 ──
            VStack(alignment: .leading, spacing: 8) {
                Text(L.s("오늘의 러닝", "Today's Run", ja: "今日のラン"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.violetText)
                Text((workoutTypeLabel ?? activity.type.label) + " · " + text.title)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let fact = text.visibleFact {
                    Text(fact)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let next = text.next {
                    Text(next)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                RunConditionRow(activity: activity, condition: condition)
                RunStatsRow(activity: activity)
                if !digest.isEmpty {
                    divider.padding(.vertical, 2)
                    TabDigestBlocksView(digest: digest, headlineNext: text.next, showsDetail: true)
                }
            }

            if hasMorningOf {
                divider
                MorningSuggestionView(label: ofLabel, entry: morning?.morningOf)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.cardBackground)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - 시트

/// 미리보기(= 출력과 같은 `RunDayShareCard`) + 공유 버튼. 4:5 1080×1350(ShareCanvas.fit).
struct RunDayShareSheet: View {
    let activity: Activity
    var workoutTypeLabel: String? = nil
    let text: InsightCardText
    var condition: ActivityCondition? = nil
    var digest: [TabDigest.Block] = []
    var morning: InsightMorning? = nil
    var weekKm: Double? = nil
    var monthKm: Double? = nil

    @State private var exportImage: UIImage? = nil
    @State private var isRendering = false
    @State private var showShare = false
    @Environment(\.dismiss) private var dismiss

    private var card: RunDayShareCard {
        RunDayShareCard(activity: activity, workoutTypeLabel: workoutTypeLabel, text: text,
                        condition: condition, digest: digest, morning: morning,
                        weekKm: weekKm, monthKm: monthKm)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    card
                        .frame(width: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                }
                shareBar
            }
            .background(Color(hex: "0D0D0F"))
            .navigationTitle(AppLanguage.shared.s("러닝 하루 공유", "Share run day", ja: "ランの一日を共有"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.shared.s("닫기", "Close", ja: "閉じる")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { renderCard() }
        .sheet(isPresented: $showShare) {
            if let img = exportImage { ShareSheet(images: [img]) }
        }
    }

    private var shareBar: some View {
        Button {
            renderCard()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showShare = true
            }
        } label: {
            HStack(spacing: 8) {
                if isRendering {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(AppLanguage.shared.s("공유하기", "Share", ja: "共有する"))
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.violet)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isRendering)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    @MainActor
    private func renderCard() {
        isRendering = true
        // 1) 카드를 자연 높이로 렌더 — 인사이트 내보내기와 같은 폭·배율
        let renderer = ImageRenderer(content:
            card
                .frame(width: 360)
                .background(Theme.cardBackground)
        )
        renderer.scale = 3
        guard let raw = renderer.uiImage else { isRendering = false; return }
        // 2) 4:5 캔버스에 맞춤 합성 — 길면 전체 축소(§5.8 같은 합성기)
        exportImage = ShareCanvas.fit(raw, background: UIColor(Theme.cardBackground))
        isRendering = false
    }
}
