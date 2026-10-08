import SwiftUI
import Charts

// MARK: - 신발 비교 차트(신발 상세·신발 공유 카드 공용) + 신발 성격 공유(2026-10-08)

/// 같은 시기 다른 신발 대비 — 줄마다 평균 점 + 95% 막대, 모든 줄이 같은 x 범위라 0 점선·눈금이 이어진다.
/// 기본: 이름 열(왼쪽 112pt) + 막대(오른쪽). compact(공유 칸): 이름 한 줄 위, 막대 아래 — 좁은 칸에서도 겹치지 않게.
struct ShoeCompareChart: View {
    struct Row {
        let id: String
        let name: String
        let stat: ShoeFormComparison.ShoeStat
        let mine: Bool
    }
    let rows: [Row]
    let metric: ShoeFormComparison.Metric
    var compact = false

    static let nameColumn: CGFloat = 112
    /// 공유 칸 — 막대를 이름보다 오른쪽으로 들여 이름 줄과 구분(2026-10-08 사용자 요청)
    static let compactInset: CGFloat = 18

    var body: some View {
        let domain = Self.domain(rows.map(\.stat), metric)
        let ticks = Self.ticks(domain, metric, maxCount: compact ? 3 : 5)
        let inset = compact ? Self.compactInset : Self.nameColumn + 8
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.id) { r in
                if compact {
                    VStack(alignment: .leading, spacing: 0) {
                        name(r).font(.system(size: 8, weight: r.mine ? .semibold : .regular)).lineLimit(1)
                        bar(r, domain: domain, ticks: ticks).frame(height: 13)
                            .padding(.leading, Self.compactInset)
                    }
                    .frame(height: 26)
                } else {
                    HStack(spacing: 8) {
                        name(r).font(.system(size: 10, weight: r.mine ? .semibold : .regular))
                            .lineLimit(2).minimumScaleFactor(0.8)
                            .frame(width: Self.nameColumn, alignment: .leading)
                        bar(r, domain: domain, ticks: ticks)
                    }
                    .frame(height: 34)
                }
            }
            }
            // 0 점선 — 줄마다 그리면 이름 줄에서 끊겨 잘 안 보였다. 모든 줄을 관통하는 한 줄로, 더 진하게(2026-10-08)
            .background(alignment: .topLeading) {   // 점·막대 아래에 깔리게
                GeometryReader { g in
                    let w = g.size.width - inset
                    let x = inset + w * (0 - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
                    Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: g.size.height)) }
                        .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
                }
                .allowsHitTesting(false)
            }
            HStack(spacing: 8) {
                // 막대와 같은 왼쪽 들여쓰기 — 눈금이 막대와 맞게
                Color.clear.frame(width: compact ? Self.compactInset - 8 : Self.nameColumn, height: 1)
                Chart { RuleMark(x: .value("0", 0)).foregroundStyle(.clear) }
                    .chartXScale(domain: domain)
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: ticks) { x in
                            AxisValueLabel {
                                Text(FormChangeStyle.fmt(x.as(Double.self) ?? 0, metric))
                                    .font(.system(size: compact ? 7.5 : 9)).foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .frame(height: compact ? 16 : 20)
            }
        }
    }

    private func name(_ r: Row) -> some View {
        Text(r.name).foregroundStyle(r.mine ? FormChangeStyle.tint(metric) : .white.opacity(0.85))
    }

    /// 모든 줄이 같이 쓰는 x 범위 — 0과 모든 95% 막대를 담고 양끝 10% 여유
    static func domain(_ stats: [ShoeFormComparison.ShoeStat], _ m: ShoeFormComparison.Metric) -> ClosedRange<Double> {
        let lo = min(0, stats.map { $0.mean - ($0.half ?? 0) }.min() ?? 0)
        let hi = max(0, stats.map { $0.mean + ($0.half ?? 0) }.max() ?? 0)
        let pad = max((hi - lo) * 0.1, m.noticeable / 2)
        return (lo - pad)...(hi + pad)
    }

    /// 한 줄의 막대 — 0 점선 + 95% 범위 + 평균 점(축 글자 없이 눈금선만)
    /// 눈금 — 범위 안쪽(양끝 12% 제외)에 들어오는 '보기 좋은 간격'의 배수만. 자동 눈금은 범위 끝에 걸려
    /// 글자가 잘리면 빠져서 진폭·보폭은 '+0.0cm' 하나만 남았다(2026-10-08).
    static func ticks(_ domain: ClosedRange<Double>, _ m: ShoeFormComparison.Metric, maxCount: Int = 5) -> [Double] {
        let steps: [Double]
        switch m {
        case .contact, .flight: steps = [1, 2, 5, 10, 20]
        case .oscillation:      steps = [0.05, 0.1, 0.2, 0.5, 1]
        case .stride:           steps = [0.002, 0.005, 0.01, 0.02, 0.05]
        case .cadence:          steps = [0.5, 1, 2, 5]
        }
        let w = domain.upperBound - domain.lowerBound
        let lo = domain.lowerBound + w * 0.12, hi = domain.upperBound - w * 0.12
        for st in steps {
            let t = stride(from: (lo / st).rounded(.up) * st, through: hi + 1e-12, by: st).map { ($0 / st).rounded() * st }
            if t.count <= maxCount { return t }
        }
        return [0]
    }

    private func bar(_ r: Row, domain: ClosedRange<Double>, ticks: [Double]) -> some View {
        let tint = r.mine ? FormChangeStyle.tint(metric) : Color.white
        return Chart {
            if let h = r.stat.half {
                RuleMark(xStart: .value("lo", max(domain.lowerBound, r.stat.mean - h)),
                         xEnd: .value("hi", min(domain.upperBound, r.stat.mean + h)), y: .value("y", 0))
                    .lineStyle(StrokeStyle(lineWidth: compact ? 2.5 : 3, lineCap: .round))
                    .foregroundStyle(tint.opacity(0.35))
            }
            PointMark(x: .value("avg", r.stat.mean), y: .value("y", 0))
                .symbolSize(compact ? (r.mine ? 50 : 36) : (r.mine ? 110 : 80))
                .foregroundStyle(r.mine ? tint : Color.white.opacity(0.85))
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: -1...1)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: ticks) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
            }
        }
    }
}

// MARK: - 신발 성격 공유

struct ShoeShareData: Identifiable {
    struct Panel {
        let metric: ShoeFormComparison.Metric
        let rows: [ShoeCompareChart.Row]
        /// 이 신발 한 줄(이름 없이) — "다른 신발과 같음(−1ms)"
        let line: String?
    }
    let id = UUID()
    let shoeName: String
    let totalKm: Double
    let runs: Int
    let character: String?
    let rhythm: String?
    let panels: [Panel]
    let modelRuns: Int?
}

struct ShoeShareCard: View {
    let data: ShoeShareData

    static let exportWidth: CGFloat = 360
    /// 칸마다 신발 수 — 이 신발 먼저, 나머지는 비교 횟수 순
    static let maxRows = 5

    var body: some View {
        let L = AppLanguage.shared
        let sub = Color(hex: "EBEBF5").opacity(0.6)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MIMOWordmark(size: 9)
                Spacer()
                Text(data.shoeName)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.top, 13)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: data.totalKm >= 100 ? "%.0f" : "%.1f", data.totalKm))
                    .font(.system(size: 34, weight: .black).width(.condensed)).foregroundStyle(.white)
                Text("km").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(L.s("· 러닝 \(data.runs)회", "· \(data.runs) runs", ja: "· ラン\(data.runs)回"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(sub)
            }
            .padding(.top, 6)

            if let c = data.character {
                Text(c).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            if let r = data.rhythm {
                Text(r).font(.system(size: 11)).foregroundStyle(FormChangeStyle.tint(.contact))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }

            TwoColumnGrid(items: data.panels) { panel($0) }
            .padding(.top, 10)

            Text(L.s("점 = 같은 시기(앞뒤 2주) 다른 신발 대비 평균 · 막대 = 95% 범위 · 괄호 = 횟수 · 막대가 0을 넘나들면 같음 · 안 넘어도 말할 만한 차이보다 작으면 차이 작음",
                     "Dot = average vs other shoes in the same ±2 weeks · bar = 95% range · () = runs · crossing 0 = same · not crossing but below a noticeable size = small difference",
                     ja: "点 = 同じ時期(前後2週)の他の靴との差の平均 · 棒 = 95%範囲 · () = 回数 · 棒が0をまたげば同じ · またがなくても目立つ差より小さければ小さな差")
                 + (data.modelRuns.map {
                     L.s(" · 0 = 같은 시기 다른 신발(최근 1년 러닝 \($0)회로 페이스·거리 영향을 뺀 값)",
                         " · 0 = other shoes in the same weeks (pace and distance taken out using \($0) runs)",
                         ja: " · 0 = 同じ時期の他の靴(直近1年のラン\($0)回でペース・距離の影響を除いた値)")
                 } ?? ""))
                .font(.system(size: 8, weight: .medium)).foregroundStyle(sub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color(hex: "1C1C1E"))
    }

    private func panel(_ p: ShoeShareData.Panel) -> some View {
        let tint = FormChangeStyle.tint(p.metric)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(FormChangeStyle.name(p.metric)).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            }
            if p.rows.isEmpty {
                Text(AppLanguage.shared.s("비교할 러닝이 없습니다", "Nothing to compare", ja: "比較できるランがありません"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                if let l = p.line {
                    Text(l).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(2, reservesSpace: true)   // 한 줄이어도 두 줄 높이 — 칸끼리 차트 시작 위치가 맞게
                }
                ShoeCompareChart(rows: p.rows, metric: p.metric, compact: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ShoeShareScreen: View {
    let data: ShoeShareData
    var body: some View {
        DarkCardShareScreen(title: AppLanguage.shared.s("러닝화 폼 데이터 내보내기", "Export shoe form data", ja: "シューズのフォームデータを書き出す"),
                            width: ShoeShareCard.exportWidth) {
            ShoeShareCard(data: data)
        }
    }
}
