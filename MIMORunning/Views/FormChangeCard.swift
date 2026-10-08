import SwiftUI
import SwiftData
import Charts

/// 성장 탭 › 폼 변화(2026-10-08) — 같은 페이스·거리로 보정하고 신발 효과를 뺀 지면접촉·수직진폭의 4주 이동평균과,
/// 그 선이 방향을 바꾼 시점(정점 ▲·바닥 ▼). 꺾임 근처(앞뒤 14일)의 대회·새 신발 시작을 함께 적는다(원인 단정은 안 함).
/// 계산은 ShoeFormComparison 하나 — 신발 상세의 신발 비교와 같은 기준.
struct FormChangeCard: View {
    var manager: HealthKitManager

    @Query private var stories: [WorkoutStory]
    @Query private var shoes: [Shoe]

    @State private var samples: [ShoeFormComparison.Sample] = []
    @State private var raceDates: [Date] = []
    @State private var shoeStarts: [(date: Date, shoeID: String)] = []
    @State private var metric: ShoeFormComparison.Metric = .contact
    @State private var months: Int = 6

    private typealias C = ShoeFormComparison
    private var L: AppLanguage { AppLanguage.shared }

    var body: some View {
        let now = Date()
        let from = Calendar.current.date(byAdding: .month, value: -months, to: now)!
        let model = C.fit(metric, samples: samples, asOf: now)
        let pts = model.map { C.formPoints(metric, samples: samples, model: $0, from: from) } ?? []
        let line = C.trend(pts, from: from, to: now)
        let turns = C.turns(line, threshold: metric.turnThreshold)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.s("폼 변화", "Form change", ja: "フォームの変化"))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                ForEach([6, 12], id: \.self) { n in
                    chip(L.s("\(n)개월", "\(n)mo", ja: "\(n)か月"), on: months == n) { months = n }
                }
            }
            HStack(spacing: 8) {
                ForEach(C.Metric.allCases, id: \.self) { m in
                    chip(metricName(m), on: metric == m) { metric = m }
                }
            }
            if model == nil {
                Text(L.s("폼 데이터가 있는 러닝이 최근 1년 \(C.minModelRuns)회 이상 쌓이면 보여 드립니다.",
                         "Shown once the last year has \(C.minModelRuns)+ runs with form data.",
                         ja: "フォームデータのあるランが直近1年で\(C.minModelRuns)回以上たまると表示します。"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            } else if line.count < 2 {
                Text(L.s("이 기간에 흐름을 그릴 만큼 러닝이 없습니다.", "Not enough runs in this period to draw a trend.",
                         ja: "この期間は流れを描けるほどランがありません。"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            } else {
                if let seg = C.lastSegment(line, turns: turns) {
                    Text(conclusion(seg))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                chart(pts: pts, line: line, turns: turns, from: from, to: now)
                ForEach(Array(turnLines(line: line, turns: turns).enumerated()), id: \.offset) { _, t in
                    Text(t).font(.system(size: 11)).foregroundStyle(Theme.violetText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(L.s("같은 페이스·거리로 보정하고 신발 효과를 뺀 값 · 흰 선 = 4주 이동평균 · ▲정점 ▼바닥 = 선이 방향을 바꾼 곳 · 점선 0 = 내 평소",
                         "Adjusted for pace and distance, shoe effect removed · white line = 4-week average · ▲peak ▼low = where the line turned · dashed 0 = usual",
                         ja: "同じペース・距離で補正し靴の影響を除いた値 · 白い線 = 4週移動平均 · ▲山 ▼谷 = 線の向きが変わった所 · 点線0 = いつもの値"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Text({
                    switch metric {
                    case .contact:     return L.s("아래 = 같은 조건에서 접지가 짧음", "Lower = shorter contact at the same pace", ja: "下 = 同じ条件で接地が短い")
                    case .oscillation: return L.s("아래 = 같은 조건에서 덜 튐", "Lower = less bounce at the same pace", ja: "下 = 同じ条件で上下動が小さい")
                    case .stride:      return L.s("위 = 같은 페이스에서 보폭이 김(그만큼 케이던스는 낮음)", "Higher = longer stride at the same pace (cadence lower by as much)", ja: "上 = 同じペースでストライドが長い(その分ケイデンスは低い)")
                    }
                }())
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .task(id: manager.activities.count &+ stories.count) { load() }
    }

    // MARK: - 데이터

    private func load() {
        let shoeByWorkout = Dictionary(stories.compactMap { s in s.shoeID.map { (s.workoutID, $0) } },
                                       uniquingKeysWith: { a, _ in a })
        samples = C.samples(inputs: manager.formInputs, shoeOf: { shoeByWorkout[$0.uuidString] })
        let typeOf = manager.workoutTypeLookup()
        let runs = manager.activities.filter { $0.type == .running }
        raceDates = runs.filter { typeOf($0.id) == .race }.map(\.date)
        var first: [String: Date] = [:]
        for a in runs {
            guard let sid = shoeByWorkout[a.id.uuidString] else { continue }
            if first[sid].map({ a.date < $0 }) ?? true { first[sid] = a.date }
        }
        shoeStarts = first.map { ($0.value, $0.key) }
    }

    // MARK: - 표기

    private func metricName(_ m: C.Metric) -> String {
        switch m {
        case .contact:     return L.s("지면접촉", "Ground contact", ja: "接地時間")
        case .oscillation: return L.s("수직진폭", "Vertical oscillation", ja: "上下動")
        case .stride:      return L.s("보폭", "Stride", ja: "ストライド")
        }
    }

    private func fmt(_ v: Double) -> String {
        let r = metric.rounded(v)
        let sign = r >= 0 ? "+" : "−"
        switch metric {
        case .contact:     return "\(sign)\(Int(abs(r)))ms"
        case .oscillation: return "\(sign)\(String(format: "%.1f", abs(r)))cm"
        case .stride:      return "\(sign)\(String(format: "%.2f", abs(r)))m"
        }
    }

    private func day(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = L.locale; f.setLocalizedDateFormatFromTemplate("Md")
        return f.string(from: d)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Color.white : Color.white.opacity(0.55))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(on ? Theme.violet : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 방향은 사실로만 — 좋다·나쁘다로 단정하지 않는다
    private func direction(_ d: Double) -> String {
        if abs(d) < metric.turnThreshold { return L.s("평탄", "flat", ja: "横ばい") }
        switch metric {
        case .contact:     return d > 0 ? L.s("길어지는 중", "getting longer", ja: "長くなっている") : L.s("짧아지는 중", "getting shorter", ja: "短くなっている")
        case .oscillation: return d > 0 ? L.s("커지는 중", "getting higher", ja: "大きくなっている") : L.s("작아지는 중", "getting lower", ja: "小さくなっている")
        case .stride:      return d > 0 ? L.s("길어지는 중", "getting longer", ja: "長くなっている") : L.s("짧아지는 중", "getting shorter", ja: "短くなっている")
        }
    }

    private func conclusion(_ seg: (from: Date, change: Double)) -> String {
        let dir = direction(seg.change)
        let amount = abs(seg.change) < metric.turnThreshold ? "" : "(\(fmt(seg.change)))"
        return L.s("\(day(seg.from)) 이후 \(metricName(metric)) \(dir)\(amount) — 진행 중",
                   "Since \(day(seg.from)), \(metricName(metric)) \(dir)\(amount) — ongoing",
                   ja: "\(day(seg.from))以降、\(metricName(metric))は\(dir)\(amount) — 進行中")
    }

    /// 꺾임마다 한 줄 — "▼ 6/10 바닥 → ▲ 7/05 정점 +0.3cm · 근처: 보스턴12 시작 7/02"
    private func turnLines(line: [(date: Date, value: Double)], turns: [C.Turn]) -> [String] {
        guard let start = line.first else { return [] }
        var prev = (date: start.date, value: start.value)
        return turns.map { t in
            let mark = t.isPeak ? "▲" : "▼"
            let kind = t.isPeak ? L.s("정점", "peak", ja: "山") : L.s("바닥", "low", ja: "谷")
            var s = "\(mark) \(day(t.date)) \(kind) \(fmt(t.value - prev.value))"
            let near = nearbyEvents(t.date)
            if !near.isEmpty { s += L.s(" · 근처: ", " · around then: ", ja: " · 近く: ") + near.joined(separator: ", ") }
            prev = (t.date, t.value)
            return s
        }
    }

    /// 꺾임 앞뒤 14일 안의 대회·새 신발 시작
    private func nearbyEvents(_ d: Date) -> [String] {
        let w: TimeInterval = Double(C.windowHalfDays) * 86_400
        var out: [String] = raceDates.filter { abs($0.timeIntervalSince(d)) <= w }
            .map { L.s("대회 \(day($0))", "race \(day($0))", ja: "レース \(day($0))") }
        out += shoeStarts.filter { abs($0.date.timeIntervalSince(d)) <= w }.map { s in
            let name = shoes.first { $0.id.uuidString == s.shoeID }?.displayName ?? L.s("새 신발", "new shoe", ja: "新しい靴")
            return L.s("\(name) 시작 \(day(s.date))", "\(name) first run \(day(s.date))", ja: "\(name) 使い始め \(day(s.date))")
        }
        return out
    }

    // MARK: - 차트

    private func chart(pts: [C.Point], line: [(date: Date, value: Double)], turns: [C.Turn], from: Date, to: Date) -> some View {
        Chart {
            RuleMark(y: .value("0", 0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.white.opacity(0.3))
            ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                PointMark(x: .value("d", p.date), y: .value("v", p.value))
                    .symbolSize(18)
                    .foregroundStyle(Color.white.opacity(0.22))
            }
            ForEach(Array(line.enumerated()), id: \.offset) { _, t in
                LineMark(x: .value("d", t.date), y: .value("trend", t.value))
                    .foregroundStyle(Color.white)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(Array(turns.enumerated()), id: \.offset) { _, t in
                PointMark(x: .value("d", t.date), y: .value("turn", t.value))
                    .symbolSize(60)
                    .foregroundStyle(Theme.violet)
                    .annotation(position: t.isPeak ? .top : .bottom, spacing: 2) {
                        Text("\(t.isPeak ? "▲" : "▼") \(day(t.date))")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.violetText)
                    }
            }
        }
        .chartXScale(domain: from...to)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: months > 6 ? 2 : 1)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel(format: .dateTime.month(.abbreviated).locale(L.locale))
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { y in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel { Text(fmt(y.as(Double.self) ?? 0)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)) }
            }
        }
        .frame(height: 180)
    }
}
