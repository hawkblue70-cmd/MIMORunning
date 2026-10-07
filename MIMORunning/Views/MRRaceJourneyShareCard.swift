import SwiftUI

// MARK: - 대회 준비 공유 카드 (2026-10-07)
//
// 대회 상세(MRArchiveDetailView) 공유 버튼 → 계획 시작부터 완주까지 한 장.
// 기록 · 예측(계획 시작 → 실제, 대회 전 앱 예측, 워치 VO2max 환산표) · 준비 요약 · 주간 막대(종류별 쌓기 + 계획선 + 수행 기호)
// · 날짜 격자(종류 색) · 계획 수행. 다크 한 가지(v1).

private enum RJ {
    static let easy = Color.white.opacity(0.32)
    static let long = Theme.violet
    static let hard = Color(hex: "F5A524")
    static let race = RaceBadge.color
    static let plan = Theme.violetText
    static let text = Color.white
    static let sub = Color.white.opacity(0.62)
    static let empty = Color.white.opacity(0.07)

    static func color(_ k: MRRaceJourney.Kind) -> Color {
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

    var body: some View {
        let L = AppLanguage.shared
        ZStack {
            LinearGradient(colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MIMOWordmark(size: 9, strokeMIMO: false)
                    Spacer()
                    RaceBadge(name: j.raceName)
                }
                .padding(.top, 13)

                Text(Self.dateLine(j))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(RJ.sub)
                    .padding(.top, 8)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(mrFormatDisplay(j.actualMin))
                        .font(.system(size: 34, weight: .black).width(.condensed))
                        .foregroundStyle(RJ.text)
                    Text(Self.distanceName(j.distanceM))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.violet)
                }

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(Self.predictionLines(j).enumerated()), id: \.offset) { _, l in
                        row(l.label, l.value, highlight: l.highlight)
                    }
                }
                .padding(.top, 4)

                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5).padding(.vertical, 9)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(Self.prepLines(j).enumerated()), id: \.offset) { _, l in
                        row(l.label, l.value)
                    }
                }

                MRRaceJourneyWeekBars(weeks: j.weeks)
                    .frame(height: 96)
                    .padding(.top, 10)

                MRRaceJourneyDayGrid(days: j.days)
                    .padding(.top, 8)

                legend
                    .padding(.top, 8)

                Spacer(minLength: 6)
                Text(L.s("계획부터 완주까지 · 미모러닝", "From plan to finish · MIMO Running", ja: "計画から完走まで · ミモラン"))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(RJ.sub)
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
                .foregroundStyle(RJ.sub)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: highlight ? .bold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(highlight ? RJ.plan : RJ.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var legend: some View {
        let L = AppLanguage.shared
        return HStack(spacing: 8) {
            ForEach([(RJ.easy, L.s("이지", "Easy", ja: "イージー")), (RJ.long, L.s("롱런", "Long", ja: "ロング走")),
                     (RJ.hard, L.s("강도 훈련", "Hard", ja: "強度練習")), (RJ.race, L.s("대회", "Race", ja: "レース"))],
                    id: \.1) { c, t in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1.5).fill(c).frame(width: 7, height: 7)
                    Text(t)
                }
            }
            HStack(spacing: 3) {
                Rectangle().fill(RJ.plan).frame(width: 9, height: 1.5)
                Text(L.s("계획", "Plan", ja: "計画"))
            }
        }
        .font(.system(size: 8, weight: .medium))
        .foregroundStyle(RJ.sub)
    }

    // MARK: - 문구

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
            out.append((String(format: "VO2max %.1f", v),
                        L.s("환산표 ", "chart ", ja: "換算表 ") + "\(mrFormatDisplay(vm)) · " + L.s("오차 ", "error ", ja: "誤差 ") + pct(ve), false))
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

struct MRRaceJourneyWeekBars: View {
    let weeks: [MRRaceJourney.Week]

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
                                        Rectangle().fill(RJ.color(k))
                                            .frame(height: chartH * km / maxKm)
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .frame(width: colW, height: chartH, alignment: .bottom)
                            // 계획선
                            Rectangle().fill(RJ.plan)
                                .frame(width: colW + 2, height: 1.5)
                                .offset(y: -chartH * w.plannedKm / maxKm)
                        }
                        .frame(width: colW, height: chartH, alignment: .bottom)
                        Text(w.symbol ?? "")
                            .font(.system(size: 7))
                            .foregroundStyle(Color.white.opacity(0.8))
                            .frame(height: symH - 2)
                    }
                }
            }
        }
    }
}

// MARK: - 날짜 격자 — 열 = 주, 행 = 월~일

struct MRRaceJourneyDayGrid: View {
    let days: [MRRaceJourney.Day]

    var body: some View {
        // 첫 날은 월요일(계획 주차 시작) — 7일씩 끊는다
        let cols = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        GeometryReader { geo in
            let n = max(cols.count, 1)
            let gap: CGFloat = 2
            let cell = min(10, (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(cols.enumerated()), id: \.offset) { _, col in
                    VStack(spacing: gap) {
                        ForEach(Array(col.enumerated()), id: \.offset) { _, d in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(d.kind.map(RJ.color) ?? RJ.empty)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 7 * 10 + 6 * 2)
    }
}

// MARK: - 공유 화면

struct MRRaceJourneyShareScreen: View {
    let journey: MRRaceJourney
    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @State private var showShareSheet = false
    @Environment(\.dismiss) private var dismiss

    private let cardW: CGFloat = 300
    private let cardH: CGFloat = 600

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer()
                    MRRaceJourneyShareCard(j: journey)
                        .environment(\.colorScheme, .dark)
                        .frame(width: cardW, height: cardH)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.30), radius: 28, y: 10)
                    Spacer(minLength: 20)
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
            MRRaceJourneyShareCard(j: journey)
                .environment(\.colorScheme, .dark)
                .frame(width: cardW, height: cardH))
        renderer.scale = 3
        guard let raw = renderer.uiImage else { isRendering = false; return }
        // 4:5 캔버스 — 다른 공유 카드와 같은 방식
        previewImage = ShareCanvas.fit(raw, background: UIColor(Color(hex: "0D0D12")), cornerRadius: 36)
        isRendering = false
    }
}
