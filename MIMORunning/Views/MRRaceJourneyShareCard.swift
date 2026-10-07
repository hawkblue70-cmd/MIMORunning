import SwiftUI

// MARK: - 대회 준비 공유 카드 (2026-10-07)
//
// 대회 상세(MRArchiveDetailView) 공유 버튼 → 계획 시작부터 완주까지 한 장.
// 기록 · 예측(계획 시작 → 실제, 대회 전 앱 예측, 워치 VO2max 환산표) · 준비 요약 · 주간 막대(종류별 쌓기 + 계획선 + 수행 기호)
// · 주별 한 줄(무엇을 했는지 — 러닝 종류 이름·km) · 다크/라이트.

private struct RJPalette {
    let easy, long, hard, race, plan, text, sub, divider: Color
    let raceBadgeOnLight: Bool

    static let dark = RJPalette(easy: Color.white.opacity(0.32), long: Theme.violet, hard: Color(hex: "F5A524"),
                                race: RaceBadge.color, plan: Theme.violetText, text: .white,
                                sub: Color.white.opacity(0.62), divider: Color.white.opacity(0.12), raceBadgeOnLight: false)
    static let light = RJPalette(easy: Color.black.opacity(0.18), long: Color(hex: "5B3FD9"), hard: Color(hex: "E08A00"),
                                 race: RaceBadge.onLightColor, plan: Color(hex: "5B3FD9"), text: Color(hex: "0D0D0D"),
                                 sub: Color(hex: "7A7A7A"), divider: Color.black.opacity(0.10), raceBadgeOnLight: true)

    func color(_ k: MRRaceJourney.Kind) -> Color {
        switch k {
        case .easy: return easy
        case .long: return long
        case .hard: return hard
        case .race: return race
        }
    }
}

struct MRRaceJourneyShareCard: View {
    let j: MRRaceJourney
    var theme: ShareTheme = .dark

    private var p: RJPalette { theme == .light ? .light : .dark }

    /// 머리·예측·준비·막대·범례·바닥 ≈ 440 + 주별 줄(줄당 15)
    static func height(weeks: Int) -> CGFloat { 440 + CGFloat(weeks) * 15 }

    var body: some View {
        let L = AppLanguage.shared
        ZStack {
            if theme == .light {
                SummaryCardPalette.light.background
            } else {
                LinearGradient(colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MIMOWordmark(size: 9, strokeMIMO: theme == .light)
                    Spacer()
                    RaceBadge(name: j.raceName, onLight: p.raceBadgeOnLight)
                }
                .padding(.top, 13)

                Text(Self.dateLine(j))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(p.sub)
                    .padding(.top, 8)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(mrFormatDisplay(j.actualMin))
                        .font(.system(size: 34, weight: .black).width(.condensed))
                        .foregroundStyle(p.text)
                    Text(Self.distanceName(j.distanceM))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(p.long)
                }

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(Self.predictionLines(j).enumerated()), id: \.offset) { _, l in
                        row(l.label, l.value, highlight: l.highlight)
                    }
                }
                .padding(.top, 4)

                Rectangle().fill(p.divider).frame(height: 0.5).padding(.vertical, 9)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(Self.prepLines(j).enumerated()), id: \.offset) { _, l in
                        row(l.label, l.value)
                    }
                }

                MRRaceJourneyWeekBars(weeks: j.weeks, palette: p)
                    .frame(height: 96)
                    .padding(.top, 10)

                legend.padding(.top, 6)

                Rectangle().fill(p.divider).frame(height: 0.5).padding(.vertical, 8)

                // 주별 한 줄 — 무엇을 했는지
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(j.weeks.enumerated()), id: \.offset) { _, w in
                        weekLine(w)
                    }
                }

                Spacer(minLength: 6)
                Text(L.s("계획부터 완주까지 · 미모러닝", "From plan to finish · MIMO Running", ja: "計画から完走まで · ミモラン"))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(p.sub)
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func row(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(p.sub)
                .frame(width: 62, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 11, weight: highlight ? .bold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(highlight ? p.plan : p.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func weekLine(_ w: MRRaceJourney.Week) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(Self.md(w.monday))
                .foregroundStyle(p.sub)
                .frame(width: 30, alignment: .leading)
            Text(w.symbol ?? "")
                .foregroundStyle(p.text)
                .frame(width: 9, alignment: .leading)
            Text(String(format: "%.0f/%.0f", w.totalKm, w.plannedKm))
                .foregroundStyle(p.text)
                .frame(width: 40, alignment: .leading)
            Text(w.detail)
                .foregroundStyle(p.text.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .monospacedDigit()
        .frame(height: 13)
    }

    private var legend: some View {
        let L = AppLanguage.shared
        return HStack(spacing: 8) {
            ForEach([(p.easy, L.s("이지", "Easy", ja: "イージー")), (p.long, L.s("롱런", "Long", ja: "ロング走")),
                     (p.hard, L.s("강도 훈련", "Hard", ja: "強度練習")), (p.race, L.s("대회", "Race", ja: "レース"))],
                    id: \.1) { c, t in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1.5).fill(c).frame(width: 7, height: 7)
                    Text(t)
                }
            }
            HStack(spacing: 3) {
                Rectangle().fill(p.plan).frame(width: 9, height: 1.5)
                Text(L.s("계획", "Plan", ja: "計画"))
            }
        }
        .font(.system(size: 8, weight: .medium))
        .foregroundStyle(p.sub)
    }

    // MARK: - 문구

    static func md(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: d)
    }

    static func distanceName(_ m: Double) -> String {
        let L = AppLanguage.shared
        switch mrLabelFor(distanceM: m) {
        case "풀": return L.s("풀", "Full", ja: "フル")
        case "하프": return L.s("하프", "Half", ja: "ハーフ")
        case let other: return other
        }
    }

    static func dateLine(_ j: MRRaceJourney) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.shared.locale
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: j.raceDate)
    }

    static func pct(_ p: Double) -> String {
        String(format: "%@%.1f%%", p >= 0 ? "+" : "−", abs(p))
    }

    static func predictionLines(_ j: MRRaceJourney) -> [(label: String, value: String, highlight: Bool)] {
        let L = AppLanguage.shared
        var out: [(label: String, value: String, highlight: Bool)] = []
        if let s = j.planStartPredMin {
            out.append((L.s("계획 시작 예측", "Plan-start est.", ja: "計画開始の予測"),
                        "\(mrFormatDisplay(s)) → " + L.s("실제 ", "actual ", ja: "実際 ") + mrFormatDisplay(j.actualMin), false))
        }
        if let a = j.appPredMin, let e = j.appErrPct {
            out.append((L.s("앱 예측", "App est.", ja: "アプリ予測"),
                        "\(mrFormatDisplay(a)) · " + L.s("오차 ", "error ", ja: "誤差 ") + pct(e), true))
        }
        if let v = j.vo2, let vm = j.vo2PredMin, let ve = j.vo2ErrPct {
            out.append(("VO2max",
                        String(format: "%.1f · ", v) + L.s("환산표 ", "chart ", ja: "換算表 ") + "\(mrFormatDisplay(vm)) · "
                            + L.s("오차 ", "error ", ja: "誤差 ") + pct(ve), false))
        }
        return out
    }

    static func prepLines(_ j: MRRaceJourney) -> [(label: String, value: String)] {
        let L = AppLanguage.shared
        var out: [(label: String, value: String)] = []
        out.append((L.s("준비", "Build-up", ja: "準備"),
                    L.s("\(j.weeks.count)주 · \(j.runCount)회 · ", "\(j.weeks.count) wks · \(j.runCount) runs · ",
                        ja: "\(j.weeks.count)週 · \(j.runCount)回 · ") + String(format: "%.0fkm", j.totalKm)))
        var t = L.s("롱런 최장 ", "Longest ", ja: "最長ロング走 ") + String(format: "%.1fkm", j.longestKm)
        if j.hardPlanned > 0 {
            t += " · " + L.s("강도 훈련 \(j.hardDone)/\(j.hardPlanned)회", "Hard \(j.hardDone)/\(j.hardPlanned)",
                             ja: "強度練習 \(j.hardDone)/\(j.hardPlanned)回")
        }
        out.append((L.s("훈련", "Training", ja: "練習"), t))
        let syms = j.symbolCounts
        if !syms.isEmpty {
            out.append((L.s("계획 수행", "Plan", ja: "計画達成"),
                        syms.map { "\($0.symbol) \($0.count)" }.joined(separator: " · ")))
        }
        return out
    }
}

// MARK: - 주간 막대 — 종류별 쌓기 + 계획선 + 수행 기호

private struct MRRaceJourneyWeekBars: View {
    let weeks: [MRRaceJourney.Week]
    let palette: RJPalette

    var body: some View {
        GeometryReader { geo in
            let n = max(weeks.count, 1)
            let gap: CGFloat = n > 14 ? 2 : 4
            let colW = (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            let symH: CGFloat = 11
            let chartH = geo.size.height - symH
            let maxKm = max(weeks.map { max($0.totalKm, $0.plannedKm) }.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, w in
                    VStack(spacing: 2) {
                        ZStack(alignment: .bottom) {
                            VStack(spacing: 0) {
                                ForEach([MRRaceJourney.Kind.race, .hard, .long, .easy], id: \.rawValue) { k in
                                    if let km = w.km[k], km > 0 {
                                        Rectangle().fill(palette.color(k))
                                            .frame(height: chartH * km / maxKm)
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .frame(width: colW, height: chartH, alignment: .bottom)
                            // 계획선
                            Rectangle().fill(palette.plan)
                                .frame(width: colW + 2, height: 1.5)
                                .offset(y: -chartH * w.plannedKm / maxKm)
                        }
                        .frame(width: colW, height: chartH, alignment: .bottom)
                        Text(w.symbol ?? "")
                            .font(.system(size: 7))
                            .foregroundStyle(palette.text.opacity(0.8))
                            .frame(height: symH - 2)
                    }
                }
            }
        }
    }
}

// MARK: - 공유 화면

struct MRRaceJourneyShareScreen: View {
    let journey: MRRaceJourney
    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @State private var showShareSheet = false
    @State private var cardTheme: ShareTheme = .dark
    @Environment(\.dismiss) private var dismiss

    private let cardW: CGFloat = 300
    private var cardH: CGFloat { MRRaceJourneyShareCard.height(weeks: journey.weeks.count) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer(minLength: 8)
                    MRRaceJourneyShareCard(j: journey, theme: cardTheme)
                        .environment(\.colorScheme, cardTheme == .dark ? .dark : .light)
                        .frame(width: cardW, height: cardH)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.30), radius: 28, y: 10)
                        .scaleEffect(min(1, 560 / cardH))
                        .frame(height: min(cardH, 560))
                    Spacer(minLength: 16)
                    themeToggle
                        .padding(.horizontal, 24)
                    Spacer(minLength: 12)
                    shareCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }
            }
            .navigationTitle(AppLanguage.shared.s("대회 준비 공유", "Share build-up", ja: "準備を共有"))
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

    private var themeToggle: some View {
        let L = AppLanguage.shared
        return HStack(spacing: 8) {
            ForEach([(ShareTheme.dark, L.s("다크", "Dark", ja: "ダーク")), (ShareTheme.light, L.s("라이트", "Light", ja: "ライト"))],
                    id: \.1) { t, label in
                Button { cardTheme = t } label: {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(cardTheme == t ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(cardTheme == t ? Theme.violet : Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var shareCTA: some View {
        if isRendering {
            ProgressView().tint(Theme.violet).frame(maxWidth: .infinity).padding(.vertical, 18)
        } else if previewImage != nil {
            Button { showShareSheet = true } label: {
                Label(AppLanguage.shared.s("카드 내보내기", "Export card", ja: "カードを書き出す"), systemImage: "square.and.arrow.up")
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
            MRRaceJourneyShareCard(j: journey, theme: cardTheme)
                .environment(\.colorScheme, cardTheme == .dark ? .dark : .light)
                .frame(width: cardW, height: cardH))
        renderer.scale = 3
        guard let raw = renderer.uiImage else { isRendering = false; return }
        // 4:5 캔버스 — 다른 공유 카드와 같은 방식
        let backdrop = cardTheme == .light ? SummaryCardPalette.light.background : Color(hex: "0D0D12")
        previewImage = ShareCanvas.fit(raw, background: UIColor(backdrop), cornerRadius: 36)
        isRendering = false
    }
}
