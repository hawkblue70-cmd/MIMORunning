import SwiftUI

// MARK: - 대회 준비 공유 카드 (2026-10-07)
//
// 대회 상세(MRArchiveDetailView) 공유 버튼 → 계획 시작부터 완주까지 한 장.
// 기록 · 예측(계획 시작 → 실제, 대회 전 앱 예측, 워치 VO2max 환산표) · 준비 요약 · 주간 막대(종류별 쌓기 + 계획선 + 수행 기호)
// · 주별 한 줄(무엇을 했는지 — 러닝 종류 이름·km) · 다크/라이트.

/// 애플 시스템 색(iOS 다크/라이트 값) — 2026-10-07 사용자 요청.
/// 막대 = 강도 사다리(A안, 애플 피트니스 심박 존처럼 차가운 → 뜨거운): 이지 systemBlue · 롱런 systemGreen · 강도 systemOrange · 대회 systemPink
///   — 대회를 노랑으로 두면 기록 숫자(노랑)와 겹쳐 헷갈렸다.
/// 기록(시간) = systemYellow(지표 의미색 시간=노랑) · 앱 예측 = systemGreen · 계획선 = label(흰/검) · 글자 = label / secondaryLabel · 바탕 = secondarySystemBackground.
private struct RJPalette {
    let bg, easy, long, hard, race, plan, text, sub, divider, time, good: Color
    let raceBadgeOnLight: Bool

    static let dark = RJPalette(
        bg: Color(hex: "1C1C1E"), easy: Color(hex: "0A84FF"), long: Color(hex: "30D158"), hard: Color(hex: "FF9F0A"),
        race: Color(hex: "FF375F"), plan: .white, text: .white, sub: Color(hex: "EBEBF5").opacity(0.6),
        divider: Color(hex: "545458").opacity(0.65), time: Color(hex: "FFD60A"), good: Color(hex: "30D158"),
        raceBadgeOnLight: false)
    /// 라이트 — 흰 바탕에서 노랑 글자는 안 읽혀 기록 숫자는 진한 노랑(접근성 대비 높인 systemYellow 계열)
    static let light = RJPalette(
        bg: .white, easy: Color(hex: "007AFF"), long: Color(hex: "34C759"), hard: Color(hex: "FF9500"),
        race: Color(hex: "FF2D55"), plan: .black, text: .black, sub: Color(hex: "3C3C43").opacity(0.6),
        divider: Color(hex: "3C3C43").opacity(0.29), time: Color(hex: "A07800"), good: Color(hex: "248A3D"),
        raceBadgeOnLight: true)

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

    /// 내보내기 폭 — 리듬·폼 인사이트 카드와 같은 360, 높이는 자연 높이(18주면 길게)
    static let exportWidth: CGFloat = 360

    var body: some View {
        let L = AppLanguage.shared
        ZStack {
            p.bg
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MIMOWordmark(size: 9, strokeMIMO: theme == .light)
                    Spacer()
                    if let m = j.month {
                        Text(m.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(p.text)
                    } else {
                        RaceBadge(name: j.raceName, onLight: p.raceBadgeOnLight)
                    }
                }
                .padding(.top, 13)

                Text(Self.dateLine(j))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(p.sub)
                    .padding(.top, 8)

                if let pr = j.progress {
                    // 진행 중 — 지금까지 거리를 크게, 몇 주차인지 옆에
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(j.totalKm >= 100 ? String(format: "%.0f", j.totalKm) : String(format: "%.1f", j.totalKm))
                            .font(.system(size: 34, weight: .black).width(.condensed))
                            .foregroundStyle(p.text)
                        Text("km")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(p.text)
                        Text(AppLanguage.shared.s("· \(pr.weekNumber)/\(pr.totalWeeks)주차 · \(Self.distanceName(j.distanceM))",
                                                  "· week \(pr.weekNumber)/\(pr.totalWeeks) · \(Self.distanceName(j.distanceM))",
                                                  ja: "· \(pr.weekNumber)/\(pr.totalWeeks)週目 · \(Self.distanceName(j.distanceM))"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(p.sub)
                    }
                } else if let m = j.month {
                    // 월간 — 이번 달 실제 거리를 크게(거리는 기록 시간이 아니라 글자색), 횟수 옆에
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(m.monthKm >= 100 ? String(format: "%.0f", m.monthKm) : String(format: "%.1f", m.monthKm))
                            .font(.system(size: 34, weight: .black).width(.condensed))
                            .foregroundStyle(p.text)
                        Text("km")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(p.text)
                        Text(AppLanguage.shared.s("· \(m.monthRuns)회", "· \(m.monthRuns) runs", ja: "· \(m.monthRuns)回"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(p.sub)
                    }
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(mrFormatDisplay(j.actualMin))
                            .font(.system(size: 34, weight: .black).width(.condensed))
                            .foregroundStyle(p.time)
                        Text(Self.distanceName(j.distanceM))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(p.text)
                    }
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

                legend.padding(.top, 10)

                // 주마다 두 줄 — 가로 막대(종류별 쌓기 + 계획 세로선 + 실제/계획 km) · 그 주에 한 것
                MRRaceJourneyWeekRows(weeks: j.weeks, palette: p)
                    .padding(.top, 8)

                Text(j.progress != nil ? L.s("대회 준비 중", "Race build-up in progress", ja: "レース準備中")
                          : j.month != nil ? L.s("월간 계획 · 수행 기록", "Monthly plan · log", ja: "月間計画 · 実行記録")
                          : L.s("계획부터 완주까지", "From plan to finish", ja: "計画から完走まで"))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(p.sub)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .top)
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
                .foregroundStyle(highlight ? p.good : p.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
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
        if let pr = j.progress {
            return f.string(from: j.raceDate) + " · D-\(pr.daysLeft)"
        }
        if let m = j.month, let last = Calendar.current.date(byAdding: .day, value: -1, to: m.end) {
            let g = DateFormatter(); g.dateFormat = "MM.dd"
            return f.string(from: m.start) + " – " + g.string(from: last)
        }
        return f.string(from: j.raceDate)
    }

    static func pct(_ p: Double) -> String {
        String(format: "%@%.1f%%", p >= 0 ? "+" : "−", abs(p))
    }

    static func predictionLines(_ j: MRRaceJourney) -> [(label: String, value: String, highlight: Bool)] {
        let L = AppLanguage.shared
        var out: [(label: String, value: String, highlight: Bool)] = []
        if let pr = j.progress {
            if let g = pr.goalMin {
                out.append((L.s("목표 기록", "Goal", ja: "目標タイム"), mrFormatDisplay(g), false))
            }
            if let e = pr.projectedMin {
                out.append((L.s("대회 예측", "Race-day est.", ja: "レース予測"), mrFormatDisplay(e), true))   // 계획대로면 대회 날(projectedFinal)
            }
            return out
        }
        if let m = j.month {
            // 목표와 계획 합계만 — 달성률·남은 km는 넣지 않는다(2026-09-22 결정)
            if let g = m.goalKm {
                out.append((L.s("목표", "Goal", ja: "目標"), String(format: "%.0fkm", g), false))
            }
            out.append((L.s("계획 합계", "Planned", ja: "計画の合計"), String(format: "%.0fkm", m.planTotalKm), false))
            return out
        }
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
        out.append((j.month != nil || j.progress != nil ? L.s("수행", "Logged", ja: "実行") : L.s("준비", "Build-up", ja: "準備"),
                    L.s("\(j.weeks.count)주 · \(j.runCount)회 · ", "\(j.weeks.count) wks · \(j.runCount) runs · ",
                        ja: "\(j.weeks.count)週 · \(j.runCount)回 · ") + String(format: "%.0fkm", j.totalKm)))
        var t = (j.month != nil ? L.s("최장 ", "Longest ", ja: "最長 ") : L.s("롱런 최장 ", "Longest ", ja: "最長ロング走 "))
            + String(format: "%.1fkm", j.longestKm)
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

// MARK: - 주별 두 줄 — 가로 막대 + 수행 과정

private struct MRRaceJourneyWeekRows: View {
    let weeks: [MRRaceJourney.Week]
    let palette: RJPalette

    private static let barH: CGFloat = 8

    var body: some View {
        let maxKm = max(weeks.map { max($0.totalKm, $0.plannedKm) }.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, w in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(MRRaceJourneyShareCard.md(w.monday))
                            .foregroundStyle(palette.sub)
                            .frame(width: 30, alignment: .leading)
                        // 계획 단계 — 대회 주차표와 같은 이름·글자색(늘리기는 기본 글자색)
                        Text(localizedPhase(w.phase))
                            .foregroundStyle(mrPhaseColor(w.phase) ?? palette.text.opacity(0.85))
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: 44, alignment: .leading)
                        Text(w.symbol ?? "")
                            .foregroundStyle(palette.text)
                            .frame(width: 9, alignment: .leading)
                        GeometryReader { geo in
                            let W = geo.size.width
                            ZStack(alignment: .leading) {
                                HStack(spacing: 0) {
                                    ForEach([MRRaceJourney.Kind.easy, .long, .hard, .race], id: \.rawValue) { k in
                                        if let km = w.km[k], km > 0 {
                                            Rectangle().fill(palette.color(k)).frame(width: W * km / maxKm)
                                        }
                                    }
                                }
                                .frame(height: Self.barH)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                // 계획 km — 보라 세로선
                                Rectangle().fill(palette.plan)
                                    .frame(width: 1.5, height: Self.barH + 4)
                                    .offset(x: min(W * w.plannedKm / maxKm, W - 1.5))
                            }
                            .frame(height: geo.size.height)
                        }
                        .frame(height: Self.barH + 4)
                        Text(String(format: "%.0f/%.0f", w.totalKm, w.plannedKm))
                            .foregroundStyle(palette.text)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()

                    Text(w.detail)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(palette.text.opacity(0.80))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.leading, 35)   // 단계 칸부터 — 설명 줄 폭을 넓게
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 리듬·폼 인사이트 내보내기와 같은 방식 — 카드 전체를 자연 높이로 스크롤 미리보기
                ScrollView {
                    MRRaceJourneyShareCard(j: journey, theme: cardTheme)
                        .environment(\.colorScheme, cardTheme == .dark ? .dark : .light)
                        .frame(width: MRRaceJourneyShareCard.exportWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(20)
                        .frame(maxWidth: .infinity)
                }
                themeToggle
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                shareCTA
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
            }
            .background(Color(hex: "0D0D0F"))
            .navigationTitle(journey.month != nil
                             ? AppLanguage.shared.s("월간 훈련일지", "Monthly log", ja: "月間練習日誌")
                             : AppLanguage.shared.s("대회 준비 공유", "Share build-up", ja: "準備を共有"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("닫기", "Close", ja: "閉じる")) { dismiss() }
                        .foregroundStyle(Theme.violet)
                }
            }
        }
        .preferredColorScheme(.dark)
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
        // 1) 카드를 자연 높이로 렌더(폭 360) — 리듬·폼 인사이트 카드와 같은 방식
        let bg = cardTheme == .light ? Color.white : Color(hex: "1C1C1E")
        let renderer = ImageRenderer(content:
            MRRaceJourneyShareCard(j: journey, theme: cardTheme)
                .environment(\.colorScheme, cardTheme == .dark ? .dark : .light)
                .frame(width: MRRaceJourneyShareCard.exportWidth)
                .background(bg))
        renderer.scale = 3
        guard let raw = renderer.uiImage else { isRendering = false; return }
        // 2) 인스타그램 4:5 캔버스에 맞춤 합성 — 인사이트 카드와 같은 합성기, 단색 바탕(§5.8)
        previewImage = ShareCanvas.fit(raw, background: UIColor(bg))
        isRendering = false
    }
}
