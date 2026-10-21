import SwiftUI
import SwiftData

// MARK: - 러닝 하루 공유 카드(그날 아침 제안 + 러닝 요약 + 다음 날 아침)
//
// 설계: docs/superpowers/specs/2026-10-15-run-day-share-card-design.md
// §5.8 — 오늘의 인사이트 카드(ActivityDetailView.InsightCard)와 이 공유 카드는 아래 공유 뷰를 같이 쓴다:
//   `InsightCardText`(제목·사실·다음 줄 판단) · `TabDigestBlocksView`(탭 요약 블록) ·
//   `RunConditionRow`(날씨·수면 칩) · `RunStatsRow`(거리·페이스·시간·심박 줄).
// 아침 블록은 `MorningSuggestionView` 하나를 그날·다음 날 두 번 쓴다. 새 판정 없음.

// MARK: - 라이트 테마(공유 카드 전용)

/// 러닝 하루 공유 카드의 라이트 테마 스위치. 기본 false = 기존 다크 색 그대로 → 앱 화면 InsightCard는 영향 없음.
/// 공유 뷰들은 이 값으로 **색만** 고른다(크기·여백·배치는 같음 — §5.8).
private struct RunCardLightKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var runCardLight: Bool {
        get { self[RunCardLightKey.self] }
        set { self[RunCardLightKey.self] = newValue }
    }
}

/// 흰 배경용 색 — 차트 내보내기 라이트 팔레트(`ShareChartPalette.light`)와 같은 계열.
enum RunCardLight {
    static let background = Color.white
    static let text       = Color(hex: "1A1A1A")              // 본문
    static let textSoft   = Color(hex: "555555")              // 흐린 글자(다크 0.72~0.85 자리)
    static let textFaint  = Color(hex: "757575")              // 더 흐린 글자(다크 0.55~0.65 자리)
    static let divider    = Color(hex: "1A1A1A").opacity(0.15)
    static let violet     = Color(hex: "5B3FD9")              // 브랜드 바이올렛의 짙은 짝(라벨·방향·거리)
    static let heartRate  = ShareChartPalette.light.hrRepColor   // E0242B
    static let pace       = ShareChartPalette.light.pace         // 0E7C8A
    static let time       = Color(hex: "D4A700")              // 시간·요일 노랑의 짙은 짝
    static let caution    = Color(hex: "E07800")
    static let positive   = Color(hex: "2FA84F")
    static let lime       = Color(hex: "5A8F00")              // 연두(러닝화 이름)의 짙은 짝
}

extension MRReadiness.Level {
    /// 라이트 공유 카드용 판정 색 — `displayColor`(초록·노랑·주황)의 의미를 유지한 짙은 짝.
    var displayColorLight: Color {
        switch self {
        case .go:   return RunCardLight.positive        // 2FA84F
        case .easy: return Color(hex: "B8860B")
        case .rest: return RunCardLight.caution         // E07800
        }
    }
}

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
    @Environment(\.runCardLight) private var isLight

    static func kind(_ t: TabDigest.Tab) -> InsightTabKind {
        switch t {
        case .rhythm:      return .rhythm
        case .form:        return .form
        case .performance: return .performance
        }
    }

    /// 탭 카테고리 색 — 리듬 = 심박 빨강, 폼 = 페이스 청록, 퍼포먼스 = 브랜드 바이올렛
    private static func tint(_ t: TabDigest.Tab, isLight: Bool) -> Color {
        switch t {
        case .rhythm:      return isLight ? RunCardLight.heartRate : Theme.heartRate
        case .form:        return isLight ? RunCardLight.pace : Theme.pace
        case .performance: return isLight ? RunCardLight.violet : Theme.violet
        }
    }

    private static func icon(_ t: TabDigest.Tab) -> String {
        switch t {
        case .rhythm:      return "heart.fill"
        case .form:        return "figure.run"
        case .performance: return "chart.line.uptrend.xyaxis"
        }
    }

    private static func dotColor(_ tone: TabDigest.Tone, isLight: Bool) -> Color {
        switch tone {
        case .caution: return isLight ? RunCardLight.caution : Theme.caution   // 총평(RunSummaryLinesView) 주의 줄과 같은 색
        case .good:    return isLight ? RunCardLight.positive : Theme.positive
        case .neutral: return isLight ? RunCardLight.textFaint : .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(digest.enumerated()), id: \.offset) { i, b in
                if i > 0 {
                    Rectangle().fill(isLight ? RunCardLight.divider : Color.white.opacity(0.12)).frame(height: 0.5)
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
            .foregroundStyle(Self.tint(b.tab, isLight: isLight))
            // 원문 줄은 블록당 하나 — 원문이 있는 첫 문장에만(4:5 축소로 글자가 작아지지 않게, 2026-10-15)
            let detailIndex = showsDetail ? b.statements.firstIndex { $0.detail != nil } : nil
            ForEach(Array(b.statements.enumerated()), id: \.offset) { i, st in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle()
                        .fill(Self.dotColor(st.tone, isLight: isLight))
                        .frame(width: 6, height: 6)
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(st.text)
                            // 공유 카드(원문 줄이 붙는 자리)는 요약 줄을 굵게 — 원문 줄과 위계를 나눈다. 앱 화면은 그대로
                            .font(showsDetail ? .subheadline.weight(.semibold) : .subheadline)
                            .foregroundStyle(isLight ? RunCardLight.text : .white.opacity(showsDetail ? 0.95 : 0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        if i == detailIndex, let d = st.detail {
                            Text(d)
                                .font(.footnote)
                                .foregroundStyle(isLight ? RunCardLight.textSoft : .white.opacity(0.68))
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            if let dir = b.direction, dir != headlineNext {
                Text("→ " + dir)
                    .font(.footnote)
                    .foregroundStyle(isLight ? RunCardLight.violet : Theme.violet)
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
    @Environment(\.runCardLight) private var isLight

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
                        if isLight {
                            // 라이트 — 같은 조건, 흰 배경에서 읽히는 짙은 짝(차트 내보내기 라이트와 같은 계열)
                            if w.isRainy                    { return RunCardLight.pace }
                            if let t = hkTemp, t >= 28      { return temperatureColor(t, isLight: true) }
                            if let t = hkTemp, t <= 2       { return temperatureColor(t, isLight: true) }
                            return RunCardLight.textSoft
                        }
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
                        color: slp.isInsufficient ? (isLight ? RunCardLight.time : Theme.time)
                                                  : (isLight ? RunCardLight.textSoft : .secondary)
                    )
                    // 수면 시간 — 사실만. 예전 등급별 처방("오늘 힘껏 달려도 좋습니다")은 수면만 보고 부하(대회 다음 날·
                    // 고강도 연속)를 몰라 홈 아침 제안("오늘은 이지런")과 어긋났고, 끝난 러닝에 처방이라 맞지도 않았다.
                    // "오늘 어떻게 달릴지"는 홈 카드(MRReadiness) 한 곳에서만 말한다.
                    Text(sleepDurationText(slp.sleepHours))
                        .font(.system(size: 11))
                        .foregroundStyle(isLight ? RunCardLight.textFaint : .secondary)
                }
            }
        }
    }
}

// MARK: - 기록 줄

/// 거리 · 페이스 · 시간 · 심박 — 지표 의미색(§11).
struct RunStatsRow: View {
    let activity: Activity
    /// 글자 크기 — 앱 카드 13, 공유 카드는 조금 크게(16)
    var fontSize: CGFloat = 13
    @Environment(\.runCardLight) private var isLight

    var body: some View {
        HStack(spacing: 4) {
            Text(activity.formattedDistance)
                .foregroundStyle(isLight ? RunCardLight.violet : Theme.violet)
            if let pace = activity.formattedPace {
                Text("·").foregroundStyle(.tertiary)
                Text(pace).foregroundStyle(isLight ? RunCardLight.pace : Theme.pace)
            }
            Text("·").foregroundStyle(.tertiary)
            Text(activity.formattedDuration).foregroundStyle(isLight ? RunCardLight.time : Theme.time)
            if let hr = activity.avgHeartRate {
                Text("·").foregroundStyle(.tertiary)
                Text("\(hr)bpm").foregroundStyle(isLight ? RunCardLight.heartRate : Theme.heartRate)
            }
        }
        .font(.system(size: fontSize, weight: .semibold))
    }
}

// MARK: - 아침 제안 한 덩어리

/// 라벨("당일 아침") + 제안 줄(판정 색 = 홈과 같은 displayColor) + why 전체 + data + planLine.
/// 제안이 없고 `direction`이 있으면 "→ 다음: {방향}" 한 줄. 둘 다 없으면 아무것도 그리지 않는다.
struct MorningSuggestionView: View {
    /// 옛 진행 표기(실제/계획 나눗셈) → 지금 표기. "이지 1/3회" → "이지 1회 · 계획 3회" (한·영·일)
    static func modernPlanLine(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"이지 (\d+)/(\d+)회"#, with: "이지 $1회 · 계획 $2회", options: .regularExpression)
        t = t.replacingOccurrences(of: #"easy (\d+)/(\d+)"#, with: "easy $1 · plan $2", options: .regularExpression)
        t = t.replacingOccurrences(of: #"イージー (\d+)/(\d+)回"#, with: "イージー$1回 · 計画$2回", options: .regularExpression)
        return t
    }

    let label: String
    let entry: InsightMorning.Entry?
    var direction: String? = nil
    @Environment(\.runCardLight) private var isLight

    var body: some View {
        let L = AppLanguage.shared
        let labelColor = isLight ? RunCardLight.violet : Theme.violetText
        if let e = entry {
            let lv = InsightMorning.level(from: e.level)
            let color = isLight ? (lv?.displayColorLight ?? RunCardLight.text)
                                : (lv?.displayColor ?? Color.white)
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(labelColor)
                Text(e.line)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
                if !e.why.isEmpty {
                    Text(e.why.keepingNumberUnitsTogether)
                        .font(.subheadline)
                        .foregroundStyle(isLight ? RunCardLight.text : .white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !e.data.isEmpty {
                    Text(e.data.keepingNumberUnitsTogether)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(isLight ? RunCardLight.textSoft : .white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !e.planLine.isEmpty {
                    // 10/18 전에 저장된 아침 기록은 "이지 1/3회" 형식 — 화면에서 지금 형식("이지 1회 · 계획 3회")으로 바꿔 보여 준다
                    Text(Self.modernPlanLine(e.planLine).keepingNumberUnitsTogether)
                        .font(.footnote)
                        .foregroundStyle(isLight ? RunCardLight.textSoft : .white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let d = direction, !d.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(labelColor)
                Text("→ " + L.s("다음: ", "Next: ", ja: "次: ") + d)
                    .font(.subheadline)
                    .foregroundStyle(isLight ? RunCardLight.violet : Theme.violet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 공유 날짜 줄

enum ShareDateText {
    /// "2026. 10. 13 화 오후 6:10" — 요일만 노랑. 인사이트 내보내기 머리와 같은 형식.
    /// `isLight` = 흰 배경 공유 카드(기본 false = 기존 다크 색).
    static func text(for date: Date, isLight: Bool = false) -> Text {
        let L = AppLanguage.shared
        let loc = L.locale
        let fDate = DateFormatter(); fDate.locale = loc
        fDate.dateFormat = L.s("yyyy. M. d ", "MMM d, yyyy ", ja: "yyyy年M月d日 ")
        let fDay  = DateFormatter(); fDay.locale  = loc; fDay.dateFormat = "EEE"
        let fTime = DateFormatter(); fTime.locale = loc
        fTime.dateFormat = L.s(" a h:mm", " h:mm a", ja: " H:mm")
        let base: Color = isLight ? RunCardLight.textSoft : .white.opacity(0.65)
        let day: Color  = isLight ? RunCardLight.time : Color.yellow
        return Text(fDate.string(from: date)).foregroundStyle(base)
             + Text(fDay.string(from: date)).foregroundStyle(day)
             + Text(fTime.string(from: date)).foregroundStyle(base)
    }
}

// MARK: - 카드

/// 위 → 아래: 워드마크·날짜 → 오늘의 러닝 → 구분선 → 당일 아침. 다크 기본, 라이트 선택(`isLight`).
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
    /// 이 러닝에 고른 러닝화 이름 — 거리 줄 밑 연두색 한 줄(2026-10-21 사용자). 없으면 줄 없음.
    var shoeName: String? = nil
    /// 라이트 테마(흰 배경). 기본 다크.
    var isLight: Bool = false

    private var divider: some View {
        Rectangle().fill(isLight ? RunCardLight.divider : Color.white.opacity(0.12)).frame(height: 0.5)
    }

    /// 카드 바탕 — 렌더·4:5 캔버스 여백도 이 색
    static func background(isLight: Bool) -> Color {
        isLight ? RunCardLight.background : Theme.cardBackground
    }

    /// "이번 주 16.2km · 이번 달 87.3km"
    private var distanceLine: String? {
        let L = AppLanguage.shared
        var parts: [String] = []
        if let w = weekKm { parts.append(L.s("이번 주 ", "This week ", ja: "今週 ") + String(format: "%.1fkm", w)) }
        if let m = monthKm { parts.append(L.s("이번 달 ", "This month ", ja: "今月 ") + String(format: "%.1fkm", m)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 아침 이지런 제안(심박 상한 · 목표 페이스)과 실제 비교 — "→ 실제: 6'35"로 페이스는 지켰고, 평균 심박 145로 제안(140 아래)보다 높았습니다".
    /// 페이스를 지켰는데 심박이 높으면 몸 상태 쪽 신호, 페이스가 빨라 심박이 높으면 제안을 넘긴 것 — 읽는 법이 달라 둘을 함께 적는다(2026-10-18).
    /// 숫자는 엔진이 만든 제안 문장("이지는 심박 140 아래, 6'31" 근처로" / "HR under 140, around 6'31"" / "心拍140未満、6'31"前後で")에서
    /// 읽는다 — 스냅샷에 숫자 칸이 따로 없어서. 이지런 제안이 아니거나 심박 상한이 없으면 nil.
    private var morningVsActual: String? {
        // 판정이 이지런인 날 + "강도 OK"인데 오늘 세션이 이지인 날("오늘은 이지 8.3km · 강도 여유 있음") — 둘 다 이지 상한 문장이 붙는다.
        // 휴식 날은 "제안대로"가 맞지 않아 뺀다(2026-10-20: 10/15 강도 OK + 이지 세션 날 줄이 빠졌다)
        guard let e = morning?.morningOf else { return nil }
        let L = AppLanguage.shared
        // 휴식 제안 날 달렸으면 그 사실만(2026-10-20) — "제안대로"·"높았다"를 따지지 않는다
        if e.level == "rest" {
            let d = activity.distance / 1000
            let km = abs(d - d.rounded()) < 0.05 ? String(format: "%.0f", d) : String(format: "%.1f", d)
            let hrPart = activity.avgHeartRate.map { L.s(" · 평균 심박 \($0)", " · avg HR \($0)", ja: " · 平均心拍\($0)") } ?? ""
            return L.s("→ 실제: 쉬라는 날 \(km)km를 달렸습니다", "→ Actual: ran \(km) km on a suggested rest day", ja: "→ 実際: 休養の提案の日に\(km)km走りました") + hrPart
        }
        guard let hr = activity.avgHeartRate else { return nil }
        let text = e.why + " " + e.data
        func firstMatch(_ patterns: [String]) -> String? {
            for p in patterns { if let r = text.range(of: p, options: .regularExpression) { return String(text[r]) } }
            return nil
        }
        // 숫자 칸 우선(2026-10-20부터 저장) — 옛 기록은 제안 문장에서 읽는다
        let parsedCap = firstMatch([#"심박 \d{2,3} 아래"#, #"HR under \d{2,3}"#, #"心拍\d{2,3}未満"#]).flatMap { Int($0.filter(\.isNumber)) }
        guard let cap = e.easyCapHR ?? parsedCap else { return nil }
        // 목표 페이스 "6'31"" — 분·초 두 자리
        let parsedPace: Double? = firstMatch([#"\d{1,2}'\d{2}\" 근처"#, #"around \d{1,2}'\d{2}\""#, #"\d{1,2}'\d{2}\"前後"#]).flatMap { m in
            guard let r = m.range(of: #"\d{1,2}'\d{2}"#, options: .regularExpression) else { return nil }
            let parts = m[r].split(separator: "'").compactMap { Double($0) }
            return parts.count == 2 ? parts[0] * 60 + parts[1] : nil
        }
        let targetPace = e.easyPaceSec ?? parsedPace
        let hrHigh = hr > cap
        guard let tp = targetPace, let ap = activity.paceSecPerKm, let apStr = activity.formattedPace else {
            return hrHigh
                ? L.s("→ 실제: 평균 심박 \(hr) · 아침 제안(\(cap) 아래)보다 높았습니다", "→ Actual: avg HR \(hr) · above the morning's guide (under \(cap))", ja: "→ 実際: 平均心拍\(hr) · 朝の提案(\(cap)未満)より高めでした")
                : L.s("→ 실제: 평균 심박 \(hr) · 아침 제안(\(cap) 아래)대로 달렸습니다", "→ Actual: avg HR \(hr) · within the morning's guide (under \(cap))", ja: "→ 実際: 平均心拍\(hr) · 朝の提案(\(cap)未満)どおりでした")
        }
        // 제안보다 10초/km 이내로 빠르거나 더 느리면 페이스는 지킨 것(폼 3단계 페이스 차이와 같은 문턱)
        let faster = Int((tp - ap).rounded())
        let paceHeld = Double(faster) < FormPhase.paceDeltaSec
        let tpStr = mrFormatPace(tp)
        switch (paceHeld, hrHigh) {
        case (true, true):
            return L.s("→ 실제: \(apStr)로 페이스는 지켰고, 평균 심박 \(hr)로 제안(\(cap) 아래)보다 높았습니다",
                       "→ Actual: pace held at \(apStr), but avg HR \(hr) was above the guide (under \(cap))",
                       ja: "→ 実際: \(apStr)でペースは守り、平均心拍\(hr)で提案(\(cap)未満)より高めでした")
        case (true, false):
            return L.s("→ 실제: \(apStr) · 평균 심박 \(hr)로 아침 제안(\(tpStr) 근처 · \(cap) 아래)대로 달렸습니다",
                       "→ Actual: \(apStr) · avg HR \(hr) — as the morning suggested (around \(tpStr) · under \(cap))",
                       ja: "→ 実際: \(apStr) · 平均心拍\(hr)で朝の提案(\(tpStr)前後 · \(cap)未満)どおりでした")
        case (false, true):
            return L.s("→ 실제: \(apStr)로 제안(\(tpStr))보다 \(faster)초/km 빨랐고, 평균 심박 \(hr)로 제안(\(cap) 아래)보다 높았습니다",
                       "→ Actual: \(apStr), \(faster) s/km faster than the guide (\(tpStr)), and avg HR \(hr) was above it (under \(cap))",
                       ja: "→ 実際: \(apStr)で提案(\(tpStr))より\(faster)秒/km速く、平均心拍\(hr)で提案(\(cap)未満)より高めでした")
        case (false, false):
            return L.s("→ 실제: \(apStr)로 제안(\(tpStr))보다 \(faster)초/km 빨랐지만, 평균 심박 \(hr)로 \(cap) 아래였습니다",
                       "→ Actual: \(apStr), \(faster) s/km faster than the guide (\(tpStr)), but avg HR \(hr) stayed under \(cap)",
                       ja: "→ 実際: \(apStr)で提案(\(tpStr))より\(faster)秒/km速かったものの、平均心拍\(hr)で\(cap)未満でした")
        }
    }

    var body: some View {
        let L = AppLanguage.shared
        let ofLabel = L.s("당일 아침", "That morning", ja: "当日の朝")
        let hasMorningOf = morning?.morningOf != nil
        // 순서(2026-10-15 사용자): 오늘의 러닝 결과 → 당일 아침 제안. 다음 날 아침은 넣지 않는다.
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                MIMOWordmark(size: 9, strokeMIMO: isLight)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    ShareDateText.text(for: activity.date, isLight: isLight)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let line = distanceLine {
                        Text(line)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isLight ? RunCardLight.text : .white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    if let shoe = shoeName, !shoe.isEmpty {
                        Text(shoe)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isLight ? RunCardLight.lime : Theme.power)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }

            // ── 오늘의 러닝 — 앱 오늘의 인사이트 카드와 같은 글·같은 뷰 ──
            VStack(alignment: .leading, spacing: 8) {
                Text(L.s("오늘의 러닝", "Today's Run", ja: "今日のラン"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isLight ? RunCardLight.violet : Theme.violetText)
                Text((workoutTypeLabel ?? activity.type.label) + " · " + text.title)
                    .font(.headline.bold())
                    .foregroundStyle(isLight ? RunCardLight.text : .white)
                    .fixedSize(horizontal: false, vertical: true)
                if let fact = text.visibleFact {
                    Text(fact)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isLight ? RunCardLight.text : .white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let next = text.next {
                    // 다음 행동 — 권고라 방향 줄과 같은 바이올렛·중간 굵기(회색이면 묻혔다)
                    Text(next)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isLight ? RunCardLight.violet : Theme.violetText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RunConditionRow(activity: activity, condition: condition)
                RunStatsRow(activity: activity, fontSize: 16)
                if !digest.isEmpty {
                    divider.padding(.vertical, 2)
                    TabDigestBlocksView(digest: digest, headlineNext: text.next, showsDetail: true)
                }
            }

            if hasMorningOf {
                divider
                MorningSuggestionView(label: ofLabel, entry: morning?.morningOf)
                if let line = morningVsActual {
                    Text(line)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isLight ? RunCardLight.violet : Theme.violetText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Self.background(isLight: isLight))
        .environment(\.runCardLight, isLight)
        .environment(\.colorScheme, isLight ? .light : .dark)
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

    @Query private var allStories: [WorkoutStory]
    @Query private var allShoes: [Shoe]
    /// 상세 화면 러닝화 피커에서 고른 신발(스토리의 shoeID)
    private var shoeName: String? {
        let wid = activity.id.uuidString
        guard let sid = allStories.first(where: { $0.workoutID == wid })?.shoeID else { return nil }
        return allShoes.first { $0.id.uuidString == sid }?.displayName
    }

    /// 테마 칩 — 켜짐 = 라이트, 꺼짐 = 다크(기본). 저장 안 함.
    @State private var isLight = false
    @State private var exportImage: UIImage? = nil
    @State private var isRendering = false
    @State private var showShare = false
    @Environment(\.dismiss) private var dismiss

    private var card: RunDayShareCard {
        RunDayShareCard(activity: activity, workoutTypeLabel: workoutTypeLabel, text: text,
                        condition: condition, digest: digest, morning: morning,
                        weekKm: weekKm, monthKm: monthKm, shoeName: shoeName, isLight: isLight)
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
                controlBar
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
        .onChange(of: isLight) { _, _ in renderCard() }
        .sheet(isPresented: $showShare) {
            if let img = exportImage { ShareSheet(images: [img]) }
        }
    }

    /// 컨트롤 — 러닝 흐름 내보내기와 같은 "다크 | 라이트" 두 칸(2026-10-15 사용자)
    private var controlBar: some View {
        ShareThemeSegmented(isLight: $isLight)
            .onChange(of: isLight) { _, _ in UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
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
                .background(RunDayShareCard.background(isLight: isLight))
        )
        renderer.scale = 3
        guard let raw = renderer.uiImage else { isRendering = false; return }
        // 2) 4:5 캔버스에 맞춤 합성 — 길면 전체 축소(§5.8 같은 합성기)
        exportImage = ShareCanvas.fit(raw, background: UIColor(RunDayShareCard.background(isLight: isLight)))
        isRendering = false
    }
}

// MARK: - 다크 | 라이트 세그먼트

/// 공유 시트 테마 선택 — 러닝 흐름 내보내기(`WeeklyGrowthShareCardView.themeToggle`)와 같은 모양의 "다크 | 라이트" 두 칸.
struct ShareThemeSegmented: View {
    @Binding var isLight: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment(AppLanguage.shared.s("다크", "Dark", ja: "ダーク"), selected: !isLight) { isLight = false }
            segment(AppLanguage.shared.s("라이트", "Light", ja: "ライト"), selected: isLight) { isLight = true }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func segment(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Theme.violet : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Theme.violet.opacity(0.22) : Color.white.opacity(0.08))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}
