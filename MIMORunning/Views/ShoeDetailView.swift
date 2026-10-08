import SwiftUI
import SwiftData
import Charts

/// 나 탭 › 신발 › 신발 상세 — 같은 러닝 종류·거리끼리 신발별 폼·심박 효율 비교 + 이 신발의 누적 km에 따른 변화(2026-10-08).
/// 계산은 `ShoeFormComparison` 하나. 표본이 적어도 보여 주고 횟수를 같이 적는다.
struct ShoeDetailView: View {
    let shoe: Shoe
    var manager: HealthKitManager

    @Query private var stories: [WorkoutStory]
    @Query private var shoes: [Shoe]
    @Environment(\.dismiss) private var dismiss

    @State private var runs: [ShoeFormComparison.Run] = []
    @State private var shoeDistances: [(date: Date, meters: Double)] = []
    @State private var selected: ShoeFormComparison.Group? = nil
    /// 한 차트에 그릴 지표 — 칩으로 고른다
    @State private var metric: ShoeFormComparison.Metric = .efficiency
    @State private var loaded = false

    private typealias C = ShoeFormComparison
    private var L: AppLanguage { AppLanguage.shared }
    private var myID: String { shoe.id.uuidString }
    private var groups: [(group: C.Group, count: Int)] { C.groups(for: myID, in: runs) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if !loaded {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 40)
                    } else if groups.isEmpty {
                        Text(L.s("이 신발로 기록된 러닝이 아직 없습니다. 러닝 상세에서 신발을 고르면 쌓입니다.",
                                 "No runs recorded with this shoe yet. Pick the shoe on a run's detail page and they'll add up.",
                                 ja: "この靴で記録されたランはまだありません。ランの詳細で靴を選ぶと貯まります。"))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 16)
                    } else {
                        compareCard
                        if let g = selected {
                            wearCard(g)
                        }
                        Text(L.s("같은 러닝 종류·비슷한 거리끼리만 비교합니다. 심박 효율 = 속도 ÷ 평균 심박(심박 한 번에 가는 거리) — 높을수록 같은 심박에 더 빨리 갑니다.",
                                 "Only runs of the same type and similar distance are compared. HR efficiency = speed ÷ average HR (distance per heartbeat) — higher means faster at the same heart rate.",
                                 ja: "同じランの種類・近い距離同士だけを比較します。心拍効率 = 速度 ÷ 平均心拍(心拍1回で進む距離) — 高いほど同じ心拍でより速く走れます。"))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 16)
                    }
                    Spacer(minLength: 24)
                }
                .padding(.top, 8)
                .containerRelativeFrame(.horizontal)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(shoe.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.s("닫기", "Done", ja: "閉じる")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { load() }
    }

    // MARK: - 데이터

    private func load() {
        let shoeByWorkout = Dictionary(stories.compactMap { s in s.shoeID.map { (s.workoutID, $0) } },
                                       uniquingKeysWith: { a, _ in a })
        let typeOf = manager.workoutTypeLookup()
        runs = C.runs(inputs: manager.formInputs,
                      shoeOf: { shoeByWorkout[$0.uuidString] },
                      typeOf: typeOf)
        shoeDistances = manager.activities
            .filter { $0.type == .running && shoeByWorkout[$0.id.uuidString] == myID }
            .map { ($0.date, $0.distance) }
        selected = C.groups(for: myID, in: runs).first?.group
        loaded = true
    }

    private func shoeName(_ id: String) -> String {
        shoes.first { $0.id.uuidString == id }?.displayName ?? L.s("삭제된 신발", "Removed shoe", ja: "削除した靴")
    }

    // MARK: - 머리

    private var header: some View {
        let km = shoeDistances.reduce(0) { $0 + $1.meters } / 1000
        return HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: km >= 100 ? "%.0f" : "%.1f", km))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(L.s("누적 km", "total km", ja: "累計km")).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(shoeDistances.count)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(L.s("러닝", "runs", ja: "ラン")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groups, id: \.group) { g in
                    let on = g.group == selected
                    Button { selected = g.group } label: {
                        Text("\(g.group.label) \(g.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(on ? Color.white : Color.white.opacity(0.6))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(on ? Theme.violet : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 신발 비교

    private func metricName(_ m: C.Metric) -> String {
        switch m {
        case .efficiency:  return L.s("심박 효율", "HR efficiency", ja: "心拍効率")
        case .contact:     return L.s("지면접촉", "Ground contact", ja: "接地時間")
        case .oscillation: return L.s("수직진폭", "Vertical oscillation", ja: "上下動")
        case .cadence:     return L.s("케이던스", "Cadence", ja: "ケイデンス")
        case .stride:      return L.s("보폭", "Stride", ja: "ストライド")
        }
    }

    private func fmt(_ m: C.Metric, _ v: Double) -> String {
        switch m {
        case .efficiency:  return String(format: "%.2fm", v)
        case .contact:     return String(format: "%.0fms", v)
        case .oscillation: return String(format: "%.1fcm", v)
        case .cadence:     return String(format: "%.0fspm", v)
        case .stride:      return String(format: "%.2fm", v)
        }
    }

    /// 이 신발이 뛴 묶음마다 신발별 평균 — 한 차트(세로 = 러닝 종류·거리, 색 = 신발)
    private struct Point: Identifiable {
        let id = UUID()
        let row: String
        let shoe: String
        let value: Double
        let count: Int
        let mine: Bool
    }

    /// 신발 색 — 이 신발은 보라, 나머지는 순서대로
    private static let otherColors: [Color] = [Color.white.opacity(0.85), Color(hex: "4FD1C5"), Color(hex: "FF9A3C"), Color(hex: "FF6FA8"), Color(hex: "B7E34B")]

    private var shoeOrder: [String] {
        let ids = Set(runs.filter { r in groups.contains { $0.group == r.group } }.map(\.shoeID))
        return [myID] + ids.subtracting([myID]).sorted { shoeName($0) < shoeName($1) }
    }

    private func color(of id: String) -> Color {
        if id == myID { return Theme.violet }
        let i = (shoeOrder.firstIndex(of: id) ?? 1) - 1
        return Self.otherColors[max(0, i) % Self.otherColors.count]
    }

    private var metricChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(C.Metric.allCases, id: \.self) { m in
                    let on = m == metric
                    Button { metric = m } label: {
                        Text(metricName(m))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(on ? Color.white : Color.white.opacity(0.6))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(on ? Theme.violet : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var compareCard: some View {
        let order = shoeOrder
        let rows = groups.map(\.group)
        let points: [Point] = rows.flatMap { g in
            C.stats(metric, group: g, runs: runs).map {
                Point(row: g.label, shoe: shoeName($0.shoeID), value: $0.mean, count: $0.count, mine: $0.shoeID == myID)
            }
        }
        let rowLabels = rows.map(\.label).filter { r in points.contains { $0.row == r } }
        return VStack(alignment: .leading, spacing: 12) {
            Text(L.s("신발 비교", "Shoe comparison", ja: "靴の比較"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            metricChips
            if let hb = metric.higherIsBetter {
                Text("\(metricName(metric)) · " + (hb ? L.s("높을수록 좋음", "higher is better", ja: "高いほど良い")
                                                    : L.s("낮을수록 좋음", "lower is better", ja: "低いほど良い")))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
            if points.isEmpty {
                Text(L.s("이 지표가 기록된 러닝이 없습니다.", "No runs with this metric.", ja: "この指標が記録されたランはありません。"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            } else {
                Chart(points) { p in
                    PointMark(x: .value("v", p.value), y: .value("row", p.row))
                        .symbolSize(p.mine ? 110 : 80)
                        .foregroundStyle(color(of: order.first { shoeName($0) == p.shoe } ?? ""))
                        .annotation(position: .bottom, spacing: 1) {
                            Text("\(p.count)").font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                }
                .chartYScale(domain: rowLabels)
                .chartXScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel { Text(fmt(metric, v.as(Double.self) ?? 0)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)) }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel {
                            Text(v.as(String.self) ?? "").font(.system(size: 10)).foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1).minimumScaleFactor(0.8).frame(width: 112, alignment: .leading)
                        }
                    }
                }
                .frame(height: CGFloat(rowLabels.count) * 46 + 28)
                // 범례 — 신발 색과 이름
                HStack(spacing: 12) {
                    ForEach(order, id: \.self) { id in
                        HStack(spacing: 4) {
                            Circle().fill(color(of: id)).frame(width: 8, height: 8)
                            Text(shoeName(id)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                        }
                    }
                }
                Text(L.s("점 = 평균 · 점 아래 숫자 = 횟수", "Dot = average · number below = runs", ja: "点 = 平均 · 点の下の数字 = 回数"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                if let v = summary(rows) {
                    Text(v).font(.system(size: 12)).foregroundStyle(Theme.violetText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    /// 묶음마다 이 신발 vs 다른 신발 — "템포런 · 5~10km: 8ms 깁니다 · 이지런 · 5~10km: 비슷합니다"
    private func summary(_ rows: [C.Group]) -> String? {
        let parts: [String] = rows.compactMap { g in
            guard let d = C.difference(metric, shoeID: myID, group: g, runs: runs) else { return nil }
            let a = abs(d.diff)
            if a < metric.noticeable { return "\(g.label): " + L.s("비슷합니다", "about the same", ja: "ほぼ同じ") }
            let up = d.diff > 0
            let word: String = {
                switch metric {
                case .efficiency:  return up ? L.s("심박당 더 갑니다", "more per beat", ja: "心拍あたり多く進む") : L.s("심박당 덜 갑니다", "less per beat", ja: "心拍あたり少なく進む")
                case .contact, .stride: return up ? L.s("깁니다", "longer", ja: "長い") : L.s("짧습니다", "shorter", ja: "短い")
                case .oscillation: return up ? L.s("큽니다", "higher", ja: "大きい") : L.s("작습니다", "lower", ja: "小さい")
                case .cadence:     return up ? L.s("높습니다", "higher", ja: "高い") : L.s("낮습니다", "lower", ja: "低い")
                }
            }()
            return "\(g.label): \(fmt(metric, a)) \(word)"
        }
        guard !parts.isEmpty else { return nil }
        return L.s("\(shoe.displayName) — 다른 신발 대비 ", "\(shoe.displayName) vs other shoes — ", ja: "\(shoe.displayName) — 他の靴と比べて ")
            + parts.joined(separator: " · ")
    }

    // MARK: - 누적 km에 따른 변화

    private func wearCard(_ g: C.Group) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.s("누적 km에 따른 변화", "Change with mileage", ja: "累計kmによる変化"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            groupChips
            ForEach([C.Metric.efficiency, .contact], id: \.self) { m in
                let pts = C.wear(m, shoeID: myID, group: g, runs: runs, allShoeDistances: shoeDistances)
                if !pts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(metricName(m)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        Chart {
                            ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                                PointMark(x: .value("km", p.km), y: .value("v", p.value))
                                    .symbolSize(40)
                                    .foregroundStyle(Theme.violet)
                            }
                            if pts.count >= 2 {
                                ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                                    LineMark(x: .value("km", p.km), y: .value("v", p.value))
                                        .foregroundStyle(Theme.violet.opacity(0.35))
                                        .lineStyle(StrokeStyle(lineWidth: 1))
                                }
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                                AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))km").font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)) }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                                AxisValueLabel { Text(fmt(m, v.as(Double.self) ?? 0)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)) }
                                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                            }
                        }
                        .frame(height: 120)
                        Text(wearNote(m, pts)).font(.system(size: 11)).foregroundStyle(Theme.violetText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private func wearNote(_ m: C.Metric, _ pts: [(km: Double, value: Double)]) -> String {
        guard let h = C.halves(pts) else {
            return L.s("아직 \(pts.count)회입니다. 6회부터 앞뒤를 비교합니다.",
                       "\(pts.count) runs so far — the early/late comparison starts at 6.",
                       ja: "まだ\(pts.count)回です。6回から前後を比較します。")
        }
        let d = h.late - h.early
        if abs(d) < m.noticeable {
            return L.s("앞쪽 절반과 뒤쪽 절반이 비슷합니다(\(fmt(m, h.early)) → \(fmt(m, h.late))).",
                       "Early and late runs are about the same (\(fmt(m, h.early)) → \(fmt(m, h.late))).",
                       ja: "前半と後半はほぼ同じです(\(fmt(m, h.early)) → \(fmt(m, h.late)))。")
        }
        let worse: Bool = {
            guard let hb = m.higherIsBetter else { return false }
            return hb ? d < 0 : d > 0
        }()
        let base = L.s("앞쪽 절반 \(fmt(m, h.early)) → 뒤쪽 절반 \(fmt(m, h.late)).",
                       "Early \(fmt(m, h.early)) → late \(fmt(m, h.late)).",
                       ja: "前半 \(fmt(m, h.early)) → 後半 \(fmt(m, h.late))。")
        return worse
            ? base + L.s(" 거리가 쌓이며 나빠지는 쪽입니다 — 쿠션이 닳는 신호일 수 있습니다.",
                         " Getting worse as mileage builds — possibly the cushioning wearing out.",
                         ja: " 距離が増えるにつれ悪くなる方向です — クッションがへたってきたサインかもしれません。")
            : base
    }
}
