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
            if let sum = summary(now: now) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.s("폼 요약 · 최근 4주 vs 3개월 전", "Form summary · last 4 weeks vs 3 months ago", ja: "フォーム要約 · 直近4週 vs 3か月前"))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    // 2×2 — 글머리 점은 지표 색(공중 시간은 계산값이라 회색)
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        ForEach(Array(stride(from: 0, to: sum.values.count, by: 2)), id: \.self) { i in
                            GridRow {
                                ForEach(sum.values[i..<min(i + 2, sum.values.count)], id: \.label) { v in
                                    HStack(spacing: 6) {
                                        Circle().fill(v.tint).frame(width: 6, height: 6)
                                        Text(v.label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                                        Text(v.value).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                    }
                                }
                            }
                        }
                    }
                    Text(sum.pattern).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(C.Metric.shown, id: \.self) { m in
                        chip(metricName(m), on: metric == m, tint: tint(m)) { metric = m }
                    }
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
                    if metric == .contact, abs(seg.change) >= metric.turnThreshold, let r = rhythmNote(from: seg.from, to: now) {
                        Text(r).font(.system(size: 12)).foregroundStyle(tint(metric))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                chart(pts: pts, line: line, turns: turns, from: from, to: now)
                ForEach(Array(turnLines(line: line, turns: turns).enumerated()), id: \.offset) { _, t in
                    Text(t).font(.system(size: 11)).foregroundStyle(tint(metric))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(L.s("같은 페이스·거리로 보정하고 신발 효과를 뺀 값 · 색 선 = 4주 이동평균 · ▲정점 ▼바닥 = 선이 방향을 바꾼 곳 · 점선 0 = 내 평소",
                         "Adjusted for pace and distance, shoe effect removed · colored line = 4-week average · ▲peak ▼low = where the line turned · dashed 0 = usual",
                         ja: "同じペース・距離で補正し靴の影響を除いた値 · 色の線 = 4週移動平均 · ▲山 ▼谷 = 線の向きが変わった所 · 点線0 = いつもの値"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Text({
                    switch metric {
                    case .contact:     return L.s("아래 = 같은 조건에서 접지가 짧음", "Lower = shorter contact at the same pace", ja: "下 = 同じ条件で接地が短い")
                    case .oscillation: return L.s("아래 = 같은 조건에서 덜 튐", "Lower = less bounce at the same pace", ja: "下 = 同じ条件で上下動が小さい")
                    case .stride:      return L.s("위 = 같은 페이스에서 보폭이 김(그만큼 케이던스는 낮음)", "Higher = longer stride at the same pace (cadence lower by as much)", ja: "上 = 同じペースでストライドが長い(その分ケイデンスは低い)")
                    case .cadence:     return L.s("위 = 같은 페이스에서 발을 빨리 굴림(그만큼 보폭은 짧음)", "Higher = quicker steps at the same pace (stride shorter by as much)", ja: "上 = 同じペースで足を速く回す(その分ストライドは短い)")
                    case .flight:      return ""   // 칩에 없음
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
        case .cadence:     return L.s("케이던스", "Cadence", ja: "ケイデンス")
        case .flight:      return L.s("공중 시간", "Flight time", ja: "滞空時間")
        }
    }

    private func fmt(_ v: Double) -> String { fmt(v, metric) }

    private func fmt(_ v: Double, _ m: C.Metric) -> String {
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

    private func day(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = L.locale; f.setLocalizedDateFormatFromTemplate("Md")
        return f.string(from: d)
    }

    /// 지표 색 — 애플 시스템 색(다크 모드 값), 앱의 지표 의미색과 같은 계열(2026-10-08 사용자 결정 A안).
    /// 기간 칩은 브랜드 보라 그대로.
    private func tint(_ m: C.Metric) -> Color {
        switch m {
        case .contact:      return Color(hex: "40C8E0")   // Teal — 지면접촉 청록
        case .oscillation:  return Color(hex: "FF375F")   // Pink — 종합 차트 진폭 마젠타 계열
        case .stride:       return Color(hex: "FF9F0A")   // Orange — 보폭 주황
        case .cadence:      return Color(hex: "FFD60A")   // Yellow — 케이던스 노랑
        case .flight:       return Color.white
        }
    }

    /// `tint`가 있으면 밝은 지표 색 바탕이라 글자는 검정
    private func chip(_ title: String, on: Bool, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? (tint == nil ? Color.white : Color.black) : Color.white.opacity(0.55))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(on ? (tint ?? Theme.violet) : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 방향은 사실로만 — 좋다·나쁘다로 단정하지 않는다
    private func direction(_ d: Double) -> String { direction(d, metric) }

    /// `lean` = 기울기 문턱(꺾임 문턱의 절반)으로 평탄 여부를 본다 — 폼 요약용
    private func direction(_ d: Double, _ m: C.Metric, lean: Bool = false) -> String {
        if abs(d) < (lean ? m.leanThreshold : m.turnThreshold) { return L.s("평탄", "flat", ja: "横ばい") }
        switch m {
        case .contact:     return d > 0 ? L.s("길어지는 중", "getting longer", ja: "長くなっている") : L.s("짧아지는 중", "getting shorter", ja: "短くなっている")
        case .oscillation: return d > 0 ? L.s("커지는 중", "getting higher", ja: "大きくなっている") : L.s("작아지는 중", "getting lower", ja: "小さくなっている")
        case .stride, .flight: return d > 0 ? L.s("길어지는 중", "getting longer", ja: "長くなっている") : L.s("짧아지는 중", "getting shorter", ja: "短くなっている")
        case .cadence:     return d > 0 ? L.s("높아지는 중", "getting higher", ja: "高くなっている") : L.s("낮아지는 중", "getting lower", ja: "低くなっている")
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

    /// 폼 요약 — 최근 4주 vs 3개월 전(같은 페이스·거리 보정, 신발 효과 뺌)의 케이던스·접지·진폭·공중 시간과 흐름 의견 한 줄
    private func summary(now: Date) -> (values: [(label: String, value: String, tint: Color)], pattern: String)? {
        func change(_ m: C.Metric) -> Double? {
            guard let mod = C.fit(m, samples: samples, asOf: now) else { return nil }
            let from = Calendar.current.date(byAdding: .day, value: -110, to: now)!
            return C.recentChange(C.formPoints(m, samples: samples, model: mod, from: from), asOf: now)
        }
        guard let c = change(.cadence), let g = change(.contact), let o = change(.oscillation) else { return nil }
        let f = change(.flight)
        var vals: [(label: String, value: String, tint: Color)] = [
            (L.s("케이던스", "Cadence", ja: "ケイデンス"), fmt(c, .cadence), tint(.cadence)),
            (L.s("접지", "Contact", ja: "接地"), fmt(g, .contact), tint(.contact)),
            (L.s("진폭", "Oscillation", ja: "上下動"), fmt(o, .oscillation), tint(.oscillation))]
        if let f { vals.append((L.s("공중 시간", "Flight", ja: "滞空"), fmt(f, .flight), Color.white.opacity(0.45))) }
        // 꺾임 문턱을 넘었으면 "바뀌는 중", 문턱 안이면 "조금씩 ~쪽으로" — 작아도 흐름이 기운 쪽을 말한다(2026-10-08)
        let clear = C.isClear(cadence: c, contact: g, oscillation: o)
        let text: String
        switch C.pattern(cadence: c, contact: g, oscillation: o) {
        case .quickSteps:
            text = clear
                ? L.s("잔걸음(총총)으로 바뀌는 중입니다 — 발을 빨리 굴리고 덜 튑니다", "Shifting to quicker, shorter steps — faster turnover, less bounce", ja: "小刻みな走りに変わりつつあります — 速く回し、上下動が小さい")
                : L.s("조금씩 잔걸음(총총) 쪽으로 가는 중입니다 — 아직 작은 변화입니다", "Drifting toward quicker, shorter steps — still a small change", ja: "少しずつ小刻みな走りの方向へ — まだ小さな変化です")
        case .longStride:
            text = clear
                ? L.s("큰 걸음으로 바뀌는 중입니다 — 한 걸음을 길게, 더 튑니다", "Shifting to longer strides — longer steps, more bounce", ja: "大きな歩幅に変わりつつあります — 一歩が長く、上下動が大きい")
                : L.s("조금씩 큰 걸음 쪽으로 가는 중입니다 — 아직 작은 변화입니다", "Drifting toward longer strides — still a small change", ja: "少しずつ大きな歩幅の方向へ — まだ小さな変化です")
        case .lowGlide:
            text = clear
                ? L.s("같은 리듬에서 낮게 깔려 달리는 쪽으로 가는 중입니다 — 덜 튑니다", "Same rhythm, running lower — less bounce", ja: "同じリズムで低く走る方向です — 上下動が小さい")
                : L.s("같은 리듬에서 조금씩 낮게 깔리는 중입니다 — 아직 작은 변화입니다", "Same rhythm, slowly running lower — still a small change", ja: "同じリズムで少しずつ低く — まだ小さな変化です")
        case .bouncier:
            text = clear
                ? L.s("같은 리듬에서 더 튀는 쪽으로 가는 중입니다", "Same rhythm, more bounce", ja: "同じリズムで上下動が大きい方向です")
                : L.s("같은 리듬에서 조금씩 더 튀는 중입니다 — 아직 작은 변화입니다", "Same rhythm, slowly bouncing more — still a small change", ja: "同じリズムで少しずつ上下動が大きく — まだ小さな変化です")
        case .steady:
            text = L.s("3개월째 같은 폼을 유지하는 중입니다 — 케이던스·접지·진폭 모두 그대로입니다", "Holding the same form for 3 months — cadence, contact and bounce all steady", ja: "3か月同じフォームを保っています — ケイデンス・接地・上下動ともそのままです")
        case .mixed:
            let big = C.biggestMover(cadence: c, contact: g, oscillation: o)
            let dir = direction(big.change, big.metric, lean: true)
            text = L.s("가장 크게 움직인 건 \(metricName(big.metric)) — \(dir)입니다", "Biggest mover: \(metricName(big.metric)) — \(dir)", ja: "いちばん動いたのは\(metricName(big.metric)) — \(dir)です")
                + (clear ? "" : L.s(" (아직 작은 변화)", " (still small)", ja: "(まだ小さな変化)"))
        }
        return (vals, text)
    }

    /// 지면접촉이 움직인 같은 기간 — 케이던스·공중 시간(같은 보정·신발 효과 뺌) 흐름선의 변화로
    /// "케이던스는 그대로(+1spm) — 공중 시간이 12ms 줄었습니다"
    private func rhythmNote(from: Date, to: Date) -> String? {
        func change(_ m: C.Metric) -> Double? {
            guard let mod = C.fit(m, samples: samples, asOf: to) else { return nil }
            let start = Calendar.current.date(byAdding: .month, value: -months, to: to)!
            let line = C.trend(C.formPoints(m, samples: samples, model: mod, from: start), from: start, to: to)
            guard let a = line.first(where: { $0.date >= from }), let b = line.last, b.date > a.date else { return nil }
            return b.value - a.value
        }
        guard let c = change(.cadence), let f = change(.flight) else { return nil }
        let flightWord = f < 0 ? L.s("줄었습니다", "less", ja: "減りました") : L.s("늘었습니다", "more", ja: "増えました")
        let fl = String(fmt(abs(f), .flight).dropFirst())
        if abs(C.Metric.cadence.rounded(c)) < C.Metric.cadence.noticeable {
            return L.s("케이던스는 그대로(\(fmt(c, .cadence))) — 공중 시간이 \(fl) \(flightWord).",
                       "Cadence unchanged (\(fmt(c, .cadence))) — \(fl) \(flightWord) time in the air.",
                       ja: "ケイデンスはそのまま(\(fmt(c, .cadence))) — 滞空時間が\(fl)\(flightWord)。")
        }
        return L.s("같은 기간 케이던스 \(fmt(c, .cadence)), 공중 시간 \(fmt(f, .flight)).",
                   "Same period: cadence \(fmt(c, .cadence)), flight time \(fmt(f, .flight)).",
                   ja: "同じ期間のケイデンス \(fmt(c, .cadence))、滞空時間 \(fmt(f, .flight))。")
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
                    .foregroundStyle(tint(metric))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(Array(turns.enumerated()), id: \.offset) { _, t in
                PointMark(x: .value("d", t.date), y: .value("turn", t.value))
                    .symbolSize(60)
                    .foregroundStyle(tint(metric))
                    .annotation(position: t.isPeak ? .top : .bottom, spacing: 2) {
                        Text("\(t.isPeak ? "▲" : "▼") \(day(t.date))")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(tint(metric))
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
