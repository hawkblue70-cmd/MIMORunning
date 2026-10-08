import SwiftUI
import Charts

// MARK: - 폼 변화 공유(2026-10-08)
//
// 성장 탭 폼 변화 카드의 '내보내기' 칩 → 폼 요약(2×2 글머리 + 패턴 한 줄) + 지표 네 개의 흐름 차트 2×2를 한 장으로.
// 차트·요약 상자는 성장 탭 카드와 같은 컴포넌트(FormChangeChart·FormChangeSummaryBox) — 크기만 compact로(§5.8).

/// 폼 변화 표기 — 성장 탭 카드와 공유 카드가 같이 쓴다
enum FormChangeStyle {
    private typealias C = ShoeFormComparison
    private static var L: AppLanguage { AppLanguage.shared }

    static func name(_ m: ShoeFormComparison.Metric) -> String {
        switch m {
        case .contact:     return L.s("지면접촉", "Ground contact", ja: "接地時間")
        case .oscillation: return L.s("수직진폭", "Vertical oscillation", ja: "上下動")
        case .stride:      return L.s("보폭", "Stride", ja: "ストライド")
        case .cadence:     return L.s("케이던스", "Cadence", ja: "ケイデンス")
        case .flight:      return L.s("공중 시간", "Flight time", ja: "滞空時間")
        }
    }

    /// 지표 색 — 애플 시스템 색(다크 모드 값), 앱의 지표 의미색과 같은 계열(2026-10-08 사용자 결정 A안)
    static func tint(_ m: ShoeFormComparison.Metric) -> Color {
        switch m {
        case .contact:      return Color(hex: "40C8E0")   // Teal — 지면접촉 청록
        case .oscillation:  return Color(hex: "FF375F")   // Pink — 종합 차트 진폭 마젠타 계열
        case .stride:       return Color(hex: "FF9F0A")   // Orange — 보폭 주황
        case .cadence:      return Color(hex: "FFD60A")   // Yellow — 케이던스 노랑
        case .flight:       return Color.white
        }
    }

    static func fmt(_ v: Double, _ m: ShoeFormComparison.Metric) -> String {
        let r = m.rounded(v)
        let sign = r >= 0 ? "+" : "−"
        switch m {
        case .contact:     return "\(sign)\(Int(abs(r)))ms"
        case .oscillation: return "\(sign)\(String(format: "%.1f", abs(r)))cm"
        case .stride:      return "\(sign)\(String(format: "%.2f", abs(r)))m"
        case .cadence:     return "\(sign)\(Int(abs(r)))spm"
        case .flight:      return "\(sign)\(Int(abs(r)))ms"
        }
    }

    static func day(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = L.locale; f.setLocalizedDateFormatFromTemplate("Md")
        return f.string(from: d)
    }

    /// 방향은 사실로만 — 좋다·나쁘다로 단정하지 않는다.
    /// `lean` = 기울기 문턱(꺾임 문턱의 절반)으로 평탄 여부를 본다 — 폼 요약용
    static func direction(_ d: Double, _ m: ShoeFormComparison.Metric, lean: Bool = false) -> String {
        if abs(d) < (lean ? m.leanThreshold : m.turnThreshold) { return L.s("평탄", "flat", ja: "横ばい") }
        switch m {
        case .contact:     return d > 0 ? L.s("길어지는 중", "getting longer", ja: "長くなっている") : L.s("짧아지는 중", "getting shorter", ja: "短くなっている")
        case .oscillation: return d > 0 ? L.s("커지는 중", "getting higher", ja: "大きくなっている") : L.s("작아지는 중", "getting lower", ja: "小さくなっている")
        case .stride, .flight: return d > 0 ? L.s("길어지는 중", "getting longer", ja: "長くなっている") : L.s("짧아지는 중", "getting shorter", ja: "短くなっている")
        case .cadence:     return d > 0 ? L.s("높아지는 중", "getting higher", ja: "高くなっている") : L.s("낮아지는 중", "getting lower", ja: "低くなっている")
        }
    }

    /// "7/15 이후 수직진폭 작아지는 중(−0.2cm) — 진행 중". `withName == false`면 지표 이름·꼬리 없이(공유 칸 제목에 이름이 있다)
    static func conclusion(_ seg: (from: Date, change: Double), _ m: ShoeFormComparison.Metric, withName: Bool = true) -> String {
        let dir = direction(seg.change, m)
        let amount = abs(seg.change) < m.turnThreshold ? "" : "(\(fmt(seg.change, m)))"
        if !withName {
            return L.s("\(day(seg.from)) 이후 \(dir)\(amount)", "Since \(day(seg.from)): \(dir)\(amount)",
                       ja: "\(day(seg.from))以降 \(dir)\(amount)")
        }
        return L.s("\(day(seg.from)) 이후 \(name(m)) \(dir)\(amount) — 진행 중",
                   "Since \(day(seg.from)), \(name(m)) \(dir)\(amount) — ongoing",
                   ja: "\(day(seg.from))以降、\(name(m))は\(dir)\(amount) — 進行中")
    }

    static var footnote: String {
        L.s("같은 페이스·거리로 보정하고 신발 효과를 뺀 값 · 색 선 = 4주 이동평균 · ▲정점 ▼바닥 = 선이 방향을 바꾼 곳 · 점선 0 = 최근 1년 같은 페이스·거리 평균",
            "Adjusted for pace and distance, shoe effect removed · colored line = 4-week average · ▲peak ▼low = where the line turned · dashed 0 = last-year average at the same pace and distance",
            ja: "同じペース・距離で補正し靴の影響を除いた値 · 色の線 = 4週移動平均 · ▲山 ▼谷 = 線の向きが変わった所 · 点線0 = 直近1年の同じペース・距離の平均")
    }

    /// 차트 위·아래 뜻 — 공유 칸에는 짧게
    static func hint(_ m: ShoeFormComparison.Metric, short: Bool = false) -> String {
        switch m {
        case .contact:     return L.s("아래 = 같은 조건에서 접지가 짧음", "Lower = shorter contact at the same pace", ja: "下 = 同じ条件で接地が短い")
        case .oscillation: return L.s("아래 = 같은 조건에서 덜 튐", "Lower = less bounce at the same pace", ja: "下 = 同じ条件で上下動が小さい")
        case .stride:
            return short ? L.s("위 = 같은 페이스에서 보폭이 김", "Higher = longer stride at the same pace", ja: "上 = 同じペースでストライドが長い")
                : L.s("위 = 같은 페이스에서 보폭이 김(그만큼 케이던스는 낮음)", "Higher = longer stride at the same pace (cadence lower by as much)", ja: "上 = 同じペースでストライドが長い(その分ケイデンスは低い)")
        case .cadence:
            return short ? L.s("위 = 같은 페이스에서 발을 빨리 굴림", "Higher = quicker steps at the same pace", ja: "上 = 同じペースで足を速く回す")
                : L.s("위 = 같은 페이스에서 발을 빨리 굴림(그만큼 보폭은 짧음)", "Higher = quicker steps at the same pace (stride shorter by as much)", ja: "上 = 同じペースで足を速く回す(その分ストライドは短い)")
        case .flight:      return ""
        }
    }
}

/// 폼 요약 상자 — 2×2 글머리(지표 색 점) + 패턴 한 줄
struct FormChangeSummaryBox: View {
    let values: [(label: String, value: String, tint: Color)]
    let pattern: String
    var compact = false

    var body: some View {
        let L = AppLanguage.shared
        VStack(alignment: .leading, spacing: compact ? 5 : 6) {
            Text(L.s("폼 요약 · 최근 4주 vs 3개월 전", "Form summary · last 4 weeks vs 3 months ago", ja: "フォーム要約 · 直近4週 vs 3か月前"))
                .font(.system(size: compact ? 9 : 11)).foregroundStyle(.white.opacity(0.6))
            // 2×2 — 글머리 점은 지표 색(공중 시간은 계산값이라 회색)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(Array(stride(from: 0, to: values.count, by: 2)), id: \.self) { i in
                    GridRow {
                        ForEach(values[i..<min(i + 2, values.count)], id: \.label) { v in
                            HStack(spacing: 6) {
                                Circle().fill(v.tint).frame(width: 6, height: 6)
                                Text(v.label).font(.system(size: compact ? 11 : 12)).foregroundStyle(.white.opacity(0.75))
                                Text(v.value).font(.system(size: compact ? 11 : 12, weight: .semibold)).foregroundStyle(.white)
                            }
                        }
                    }
                }
            }
            Text(pattern).font(.system(size: compact ? 13 : 14, weight: .semibold)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// 흐름 차트 — 점(신발 효과 뺀 러닝) + 4주 이동평균 색 선 + 꺾임 ▲▼
struct FormChangeChart: View {
    let metric: ShoeFormComparison.Metric
    let pts: [ShoeFormComparison.Point]
    let line: [(date: Date, value: Double)]
    let turns: [ShoeFormComparison.Turn]
    let from: Date
    let to: Date
    let months: Int
    var compact = false

    var body: some View {
        let tint = FormChangeStyle.tint(metric)
        let axisFont: CGFloat = compact ? 7.5 : 9
        Chart {
            RuleMark(y: .value("0", 0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.white.opacity(0.3))
            ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                PointMark(x: .value("d", p.date), y: .value("v", p.value))
                    .symbolSize(compact ? 7 : 18)
                    .foregroundStyle(Color.white.opacity(0.22))
            }
            ForEach(Array(line.enumerated()), id: \.offset) { _, t in
                LineMark(x: .value("d", t.date), y: .value("trend", t.value))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: compact ? 1.8 : 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(Array(turns.enumerated()), id: \.offset) { _, t in
                PointMark(x: .value("d", t.date), y: .value("turn", t.value))
                    .symbolSize(compact ? 28 : 60)
                    .foregroundStyle(tint)
                    .annotation(position: t.isPeak ? .top : .bottom, spacing: 2) {
                        Text("\(t.isPeak ? "▲" : "▼") \(FormChangeStyle.day(t.date))")
                            .font(.system(size: compact ? 7.5 : 9, weight: .semibold)).foregroundStyle(tint)
                    }
            }
        }
        .chartXScale(domain: from...to)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: months > 6 || compact ? 2 : 1)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel(format: .dateTime.month(.abbreviated).locale(AppLanguage.shared.locale))
                    .font(.system(size: axisFont)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: compact ? 3 : 4)) { y in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    Text(FormChangeStyle.fmt(y.as(Double.self) ?? 0, metric))
                        .font(.system(size: axisFont)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(height: compact ? 96 : 180)
    }
}

// MARK: - 공유 데이터·카드

struct FormChangeShareData: Identifiable {
    struct Panel {
        let metric: ShoeFormComparison.Metric
        let pts: [ShoeFormComparison.Point]
        let line: [(date: Date, value: Double)]
        let turns: [ShoeFormComparison.Turn]
        let segment: (from: Date, change: Double)?
    }
    let id = UUID()
    let months: Int
    let from: Date
    let to: Date
    let summary: (values: [(label: String, value: String, tint: Color)], pattern: String)?
    let panels: [Panel]
}

struct FormChangeShareCard: View {
    let data: FormChangeShareData

    /// 내보내기 폭 — 다른 성장 공유 카드와 같은 360, 높이는 자연 높이
    static let exportWidth: CGFloat = 360

    var body: some View {
        let L = AppLanguage.shared
        let sub = Color(hex: "EBEBF5").opacity(0.6)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MIMOWordmark(size: 9)
                Spacer()
                Text(L.s("폼 변화", "Form change", ja: "フォームの変化"))
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            }
            .padding(.top, 13)

            Text(L.s("\(FormChangeStyle.day(data.from)) – \(FormChangeStyle.day(data.to)) · 최근 \(data.months)개월",
                     "\(FormChangeStyle.day(data.from)) – \(FormChangeStyle.day(data.to)) · last \(data.months) months",
                     ja: "\(FormChangeStyle.day(data.from)) – \(FormChangeStyle.day(data.to)) · 直近\(data.months)か月"))
                .font(.system(size: 10, weight: .medium)).foregroundStyle(sub)
                .padding(.top, 8)

            if let s = data.summary {
                FormChangeSummaryBox(values: s.values, pattern: s.pattern, compact: true)
                    .padding(.top, 10)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(data.panels, id: \.metric) { p in panel(p) }
            }
            .padding(.top, 10)

            Text(FormChangeStyle.footnote)
                .font(.system(size: 8, weight: .medium)).foregroundStyle(sub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color(hex: "1C1C1E"))
    }

    private func panel(_ p: FormChangeShareData.Panel) -> some View {
        let tint = FormChangeStyle.tint(p.metric)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(FormChangeStyle.name(p.metric)).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            }
            if p.line.count >= 2 {
                if let seg = p.segment {
                    Text(FormChangeStyle.conclusion(seg, p.metric, withName: false))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                FormChangeChart(metric: p.metric, pts: p.pts, line: p.line, turns: p.turns,
                                from: data.from, to: data.to, months: data.months, compact: true)
                Text(FormChangeStyle.hint(p.metric, short: true))
                    .font(.system(size: 7.5)).foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1).minimumScaleFactor(0.8)
            } else {
                Text(AppLanguage.shared.s("흐름을 그릴 만큼 러닝이 없습니다", "Not enough runs", ja: "ランが足りません"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 공유 화면 — 대회 준비 공유와 같은 방식(자연 높이 렌더 → 4:5 캔버스)

/// 폼 변화·신발 성격 공유가 같이 쓰는 화면 — 미리보기와 출력이 같은 카드 뷰(§5.8), 다크만
struct DarkCardShareScreen<Card: View>: View {
    let title: String
    let width: CGFloat
    @ViewBuilder let card: () -> Card
    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @State private var showShareSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let L = AppLanguage.shared
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    card()
                        .frame(width: width)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(20)
                        .frame(maxWidth: .infinity)
                }
                Group {
                    if isRendering {
                        ProgressView().tint(Theme.violet).frame(maxWidth: .infinity).padding(.vertical, 18)
                    } else if previewImage != nil {
                        Button { showShareSheet = true } label: {
                            Label(L.s("카드 내보내기", "Export card", ja: "カードを書き出す"), systemImage: "square.and.arrow.up")
                                .font(.headline).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(Theme.violet)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .sheet(isPresented: $showShareSheet) {
                            if let img = previewImage { ShareSheet(images: [img]) }
                        }
                    } else {
                        Text(L.s("카드 생성에 실패했습니다", "Card creation failed", ja: "カードの作成に失敗しました"))
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 32)
            }
            .background(Color(hex: "0D0D0F"))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.s("닫기", "Close", ja: "閉じる")) { dismiss() }.foregroundStyle(Theme.violet)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await render() }
    }

    @MainActor
    private func render() async {
        isRendering = true
        let bg = Color(hex: "1C1C1E")
        let renderer = ImageRenderer(content:
            card()
                .environment(\.colorScheme, .dark)
                .frame(width: width)
                .background(bg))
        renderer.scale = 3
        guard let raw = renderer.uiImage else { isRendering = false; return }
        previewImage = ShareCanvas.fit(raw, background: UIColor(bg))
        isRendering = false
    }
}

struct FormChangeShareScreen: View {
    let data: FormChangeShareData
    var body: some View {
        DarkCardShareScreen(title: AppLanguage.shared.s("폼 변화 공유", "Share form change", ja: "フォームの変化を共有"),
                            width: FormChangeShareCard.exportWidth) {
            FormChangeShareCard(data: data)
        }
    }
}
