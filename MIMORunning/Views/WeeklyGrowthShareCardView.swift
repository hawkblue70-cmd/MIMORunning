import SwiftUI
import Charts

// MARK: - Running flow share card

/// 성장 탭 "러닝 흐름" 카드를 그대로 내보내는 공유 카드 — 차트만 싣는다(잔디는 2026-10-10 뺐다).
/// §5.8 — 차트는 `RecordBarChart`(exportMode) **하나**를 재사용한다. 별도 레이아웃 금지.
struct MileageStreakShareCard: View {
    let bars: [RecordBar]
    let period: RecordPeriod
    let windowStart: Date
    let windowEnd: Date
    /// "최근 30일" / "8월" / "최근 12주"
    let periodLabel: String
    /// 차트 아래 ✦ 상태·방향 두 줄 — 성장 탭과 같은 문장을 공유 카드에도 싣는다
    var flowComment: RecordFlowInsight.Result? = nil
    var theme: ShareTheme = .dark

    private var p: SummaryCardPalette { theme == .light ? .light : .dark }

    /// 플롯 높이 130 → 150(2026-10-21 사용자 "그래프만 크게") — 카드 크기(336×420)는 그대로 두고,
    /// 늘린 20pt는 카드 안 여백에서 받는다(위 13→8 · 구분선 7→4 · 제목 7→4 · 차트 6→3 · 아래 최소 14→6 = 22pt).
    /// 차트 안 간격·글자는 그대로(다른 내보내기와 같은 컴포넌트).
    static let chartPlotHeight: CGFloat = 150

    private static let cellSize: CGFloat = 10
    private static let cellGap:  CGFloat = 2
    private static let labelW:   CGFloat = 10

    var body: some View {
        ZStack {
            if theme == .light {
                p.background
            } else {
                LinearGradient(
                    colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            VStack(alignment: .leading, spacing: 0) {
                wordmarkRow
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                divider.padding(.top, 4)

                flowTitleRow
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                if isMonthSummary {
                    monthTotalsRow
                        .padding(.horizontal, 20)
                        .padding(.top, 2)
                }

                recordChart
                    .padding(.horizontal, 14)
                    .padding(.top, 3)

                Spacer(minLength: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)   // 넘치더라도 로고(위)가 아니라 아래가 잘리게
        }
    }

    // MARK: Wordmark
    private var wordmarkRow: some View {
        MIMOWordmark(size: 9, strokeMIMO: theme == .light)
    }

    private var divider: some View {
        Rectangle()
            .fill(p.divider)
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    // MARK: 러닝 흐름 (성장 탭과 동일한 컴포넌트)

    /// 일 단위(달력 한 달) 카드 — 월 기록으로 총거리·횟수를 위에 크게 싣는다. 12주 보기는 그대로.
    private var isMonthSummary: Bool { period == .day }

    /// 창이 달력 한 달(1일~다음 달 1일)인가 — 이번 달 기본 보기는 "오늘까지 최근 30일" 롤링이라 아니다.
    private var isCalendarMonthWindow: Bool {
        let cal = Calendar.current
        guard cal.component(.day, from: windowStart) == 1,
              let next = cal.date(byAdding: .month, value: 1, to: cal.startOfDay(for: windowStart)) else { return false }
        return cal.isDate(windowEnd, inSameDayAs: next)
    }

    /// "9월 기록" — 날짜와 관계없이 항상 기록(2026-09-30 사용자 결정: "결산보다 기록"). 달 이름은 보는 달(windowStart).
    /// 최근 30일 보기면 "최근 30일 기록"(2026-10-02 사용자: 10/2에 9/2부터 창이라 "9월 기록"으로 잘못 나왔다).
    private var monthTitle: String {
        let L = AppLanguage.shared
        if !isCalendarMonthWindow {
            return L.s("\(periodLabel) 기록", periodLabel, ja: "\(periodLabel)の記録")
        }
        if L.isJapanese { return "\(Calendar.current.component(.month, from: windowStart))月の記録" }
        if L.isEnglish {
            let df = DateFormatter(); df.locale = Locale(identifier: "en_US"); df.dateFormat = "MMMM"
            return "\(df.string(from: windowStart)) runs"
        }
        return "\(Calendar.current.component(.month, from: windowStart))월 기록"
    }

    private var flowTitleRow: some View {
        HStack(alignment: .center) {
            Text(isMonthSummary ? monthTitle : AppLanguage.shared.s("러닝 흐름", "Running Flow", ja: "ランの流れ"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(p.textPrimary)
            Spacer()
            // 월 기록 카드도 오른쪽 "러닝 흐름"은 왼쪽 제목과 같은 크기·색 — 두 제목이 한 줄의 짝으로 읽히게
            Text(isMonthSummary ? AppLanguage.shared.s("러닝 흐름", "Running Flow", ja: "ランの流れ") : periodLabel)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(p.textPrimary)
        }
    }

    /// "196 km        24회 · 17일" — 총거리를 카드에서 가장 큰 숫자로, 횟수·달린 날을 옆에.
    /// 하루 두 번 뛴 날이 있으면 횟수와 날 수가 달라 꾸준함이 그대로 보인다.
    private var monthTotalsRow: some View {
        let L = AppLanguage.shared
        let km = bars.reduce(0.0) { $0 + $1.km }
        let runs = bars.reduce(0) { $0 + $1.runCount }
        let days = bars.filter { $0.runCount > 0 }.count
        let kmStr = km >= 100 ? String(format: "%.0f", km) : String(format: "%.1f", km)
        return HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(kmStr)
                .font(.system(size: 34, weight: .black).width(.condensed))
                .foregroundStyle(p.textPrimary)
            // "km"는 바이올렛 — 애슬레틱 카드의 거리 표기("16.0 KM")와 같은 방식
            Text("km")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.violet)
            Spacer(minLength: 8)
            // 달린 날 수는 앰버 — 아래 연속 달리기 격자 칸 색(heatFull)과 같아, 격자에 칠해진 날이라는 게 이어진다
            (Text(L.s("\(runs)회 · ", "\(runs) runs · ", ja: "\(runs)回 · ")).foregroundStyle(p.textPrimary)
             + Text(L.s("\(days)일", "\(days) days", ja: "\(days)日")).foregroundStyle(p.heatFull))
                .font(.system(size: 15, weight: .semibold))
        }
    }

    /// §5.8 — 성장 탭 카드와 **같은 컴포넌트**. 크기·상호작용만 내보내기 모드로.
    /// 월 기록 카드면 같은 숫자를 위에 크게 실었으니 차트 머리·흐름 문장의 총계는 뺀다.
    private var recordChart: some View {
        RecordBarChart(
            bars: bars,
            period: period,
            start: windowStart,
            end: windowEnd,
            exportMode: true,
            showsTotals: !isMonthSummary,
            cardBackground: p.boxFill,
            flowComment: isMonthSummary ? flowComment?.withoutTotals() : flowComment,
            showsTrendStrips: true,   // 성장 탭과 같은 심박·유산소 선·범례
            exportPlotHeight: Self.chartPlotHeight
        )
    }

}

// MARK: - Running flow share screen

struct MileageStreakShareCardScreen: View {
    let bars: [RecordBar]
    let period: RecordPeriod
    let windowStart: Date
    let windowEnd: Date
    let periodLabel: String
    /// 차트 아래 ✦ 상태·방향 두 줄 — 성장 탭과 같은 문장을 공유 카드에도 싣는다
    var flowComment: RecordFlowInsight.Result? = nil
    var screenTitle: String = AppLanguage.shared.s("러닝 흐름", "Running Flow", ja: "ランの流れ")

    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @State private var showShareSheet = false
    @State private var cardTheme: ShareTheme = .dark
    @Environment(\.dismiss) private var dismiss

    /// 4:5 고정(2026-10-10). 월 결산(일 보기)의 내용 높이 ≈414pt가 들어가도록 폭을 336으로 — 주 보기는 아래가 조금 남는다.
    /// 2026-10-21: 플롯 +20pt(130 → 150)는 카드 안 여백 22pt에서 받는다 — 카드·출력 크기와 글자 크기는 그대로.
    private let cardW: CGFloat = 336
    private var cardH: CGFloat { cardW * 5 / 4 }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer()
                    MileageStreakShareCard(
                        bars: bars,
                        period: period,
                        windowStart: windowStart,
                        windowEnd: windowEnd,
                        periodLabel: periodLabel,
                        flowComment: flowComment,
                        theme: cardTheme
                    )
                    .environment(\.colorScheme, cardTheme == .dark ? .dark : .light)
                    .frame(width: cardW, height: cardH)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Theme.violet.opacity(0.30), radius: 28, y: 10)

                    Spacer(minLength: 20)

                    themeToggle
                        .padding(.horizontal, 24)

                    Spacer(minLength: 12)

                    shareCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("닫기", "Close", ja: "閉じる")) { dismiss() }
                        .foregroundStyle(Theme.violet)
                }
            }
        }
        .task { await renderCard() }
        .onChange(of: cardTheme) { Task { await renderCard() } }
    }

    // MARK: - Theme toggle

    private var themeToggle: some View {
        HStack(spacing: 0) {
            themeSegment(label: AppLanguage.shared.s("다크", "Dark", ja: "ダーク"),
                         selected: cardTheme == .dark) { cardTheme = .dark }
            themeSegment(label: AppLanguage.shared.s("라이트", "Light", ja: "ライト"),
                         selected: cardTheme == .light) { cardTheme = .light }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func themeSegment(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
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

    @ViewBuilder
    private var shareCTA: some View {
        if isRendering {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.violet)
                Text(AppLanguage.shared.s("카드 만드는 중...", "Creating card...", ja: "カードを作成中..."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        } else if previewImage != nil {
            Button { showShareSheet = true } label: {
                Label(AppLanguage.shared.s("흐름 내보내기", "Export Flow", ja: "流れを書き出す"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .sheet(isPresented: $showShareSheet) {
                if let img = previewImage { ShareSheet(images: [img]) }
            }
        } else {
            Text(AppLanguage.shared.s("카드 생성에 실패했습니다", "Card creation failed", ja: "カードの作成に失敗しました"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
    }

    @MainActor
    private func renderCard() async {
        isRendering = true
        let renderer = ImageRenderer(content:
            MileageStreakShareCard(
                bars: bars,
                period: period,
                windowStart: windowStart,
                windowEnd: windowEnd,
                periodLabel: periodLabel,
                flowComment: flowComment,
                theme: cardTheme
            )
            .environment(\.colorScheme, cardTheme == .dark ? .dark : .light)
            .frame(width: cardW, height: cardH)
        )
        renderer.scale = 3
        guard let raw = renderer.uiImage else { isRendering = false; return }
        // 카드 자체가 4:5(336×420)라 캔버스를 꽉 채운다. 캔버스 맞춤은 안전망으로 둔다 —
        // 비율이 어긋나도 인스타그램 피드에서 잘리지 않고, 둥근 모서리가 여백을 카드 테두리로 읽히게 한다.
        previewImage = ShareCanvas.fit(raw,
                                       background: UIColor(canvasBackdrop),
                                       cornerRadius: 36)
        isRendering = false
    }

    /// 4:5 캔버스의 바탕 — 카드 그라디언트의 어두운 끝(라이트는 카드 배경).
    private var canvasBackdrop: Color {
        cardTheme == .light ? SummaryCardPalette.light.background : Color(hex: "0D0D12")
    }
}
