import SwiftUI
import SwiftData
import Charts

/// 나 탭 › 신발 › 신발 상세(2026-10-08) — 신발 성격과 내 폼 변화.
/// 값은 전부 "이 속도·거리(심박 효율은 기온도)면 내 평소" 대비 차이(ShoeFormComparison). 러닝 종류로 쪼개지 않는다.
/// 신발 수명은 다루지 않는다 — 쿠션이 닳아도 몸이 보상해 워치 폼 지표에는 거의 드러나지 않는다(누적 km만 표시).
struct ShoeDetailView: View {
    let shoe: Shoe
    var manager: HealthKitManager

    @Query private var stories: [WorkoutStory]
    @Query private var shoes: [Shoe]
    @Environment(\.dismiss) private var dismiss

    @State private var samples: [ShoeFormComparison.Sample] = []
    @State private var shoeDistances: [(date: Date, meters: Double)] = []
    @State private var metric: ShoeFormComparison.Metric = .contact
    @State private var months: Int = 6
    @State private var loaded = false

    private typealias C = ShoeFormComparison
    private var L: AppLanguage { AppLanguage.shared }
    private var myID: String { shoe.id.uuidString }
    private var totalKm: Double { shoeDistances.reduce(0) { $0 + $1.meters } / 1000 }
    private func model(_ m: C.Metric) -> C.Model? { C.fit(m, samples: samples, asOf: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !loaded {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        headline
                        metricChips.padding(.horizontal, 16)
                        if let m = model(metric) {
                            trendCard(m)
                            compareCard(m)
                            Text(footnote(m))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 16)
                        } else {
                            Text(L.s("이 지표가 있는 러닝이 최근 1년 \(C.minModelRuns)회 이상 쌓이면 보여 드립니다.",
                                     "Shown once the last year has \(C.minModelRuns)+ runs with this metric.",
                                     ja: "この指標があるランが直近1年で\(C.minModelRuns)回以上たまると表示します。"))
                                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.72))
                                .padding(.horizontal, 16)
                        }
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

    private func load() {
        let shoeByWorkout = Dictionary(stories.compactMap { s in s.shoeID.map { (s.workoutID, $0) } },
                                       uniquingKeysWith: { a, _ in a })
        let tempByID = Dictionary(manager.activities.compactMap { a in a.temperatureC.map { (a.id, $0) } },
                                  uniquingKeysWith: { a, _ in a })
        samples = C.samples(inputs: manager.formInputs,
                            shoeOf: { shoeByWorkout[$0.uuidString] },
                            temperatureOf: { tempByID[$0] })
        shoeDistances = manager.activities
            .filter { $0.type == .running && shoeByWorkout[$0.id.uuidString] == myID }
            .map { ($0.date, $0.distance) }
        loaded = true
    }

    private func shoeName(_ id: String) -> String {
        shoes.first { $0.id.uuidString == id }?.displayName ?? L.s("삭제된 신발", "Removed shoe", ja: "削除した靴")
    }

    // MARK: - 표기

    private func metricName(_ m: C.Metric) -> String {
        switch m {
        case .contact:     return L.s("지면접촉", "Ground contact", ja: "接地時間")
        case .oscillation: return L.s("수직진폭", "Vertical oscillation", ja: "上下動")
        case .efficiency:  return L.s("심박 효율", "HR efficiency", ja: "心拍効率")
        }
    }

    private func shortName(_ m: C.Metric) -> String {
        switch m {
        case .contact:     return L.s("접지", "contact", ja: "接地")
        case .oscillation: return L.s("진폭", "oscillation", ja: "上下動")
        case .efficiency:  return L.s("효율", "efficiency", ja: "効率")
        }
    }

    /// 차이 표기(부호 포함) — 판정과 같은 반올림
    private func fmt(_ v: Double, _ m: C.Metric) -> String {
        let r = m.rounded(v)
        let sign = r >= 0 ? "+" : "−"
        switch m {
        case .contact:     return "\(sign)\(Int(abs(r)))ms"
        case .oscillation: return "\(sign)\(String(format: "%.1f", abs(r)))cm"
        case .efficiency:  return "\(sign)\(String(format: "%.1f", abs(r)))%"
        }
    }

    /// 반올림한 값이 문턱 이상인가
    private func notable(_ v: Double, _ m: C.Metric) -> Bool { abs(m.rounded(v)) >= m.noticeable }

    private var metricChips: some View {
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

    // MARK: - 결론 — 신발 성격 + 내 폼 흐름

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: totalKm >= 100 ? "%.0f" : "%.1f", totalKm))
                    .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("km").font(.system(size: 14)).foregroundStyle(.secondary)
                Text(L.s("· 러닝 \(shoeDistances.count)회", "· \(shoeDistances.count) runs", ja: "· ラン\(shoeDistances.count)回"))
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            if let c = characterSentence() {
                Text(c).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let m = model(metric), let t = trendSentence(m) {
                Text(t).font(.system(size: 13)).foregroundStyle(Theme.violetText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
    }

    /// "같은 시기 다른 신발보다 접지 +9ms · 진폭 같음 · 효율 같음" — 세 지표 모두
    private func characterSentence() -> String? {
        var parts: [String] = []
        var runs = 0
        for m in C.Metric.allCases {
            guard let mod = model(m), let s = C.shoeStats(m, samples: samples, model: mod).first(where: { $0.shoeID == myID }) else { continue }
            runs = max(runs, s.n)
            guard s.n >= C.minShoeRuns else { continue }
            parts.append(s.differs && notable(s.mean, m)
                ? "\(shortName(m)) \(fmt(s.mean, m))"
                : "\(shortName(m)) " + L.s("같음", "same", ja: "同じ"))
        }
        if parts.isEmpty {
            return runs > 0
                ? L.s("같은 시기 다른 신발과 비교할 러닝이 \(runs)회라 아직 성격을 말하지 않습니다(\(C.minShoeRuns)회부터).",
                      "Only \(runs) runs to compare against other shoes in the same weeks — too early to describe this shoe (needs \(C.minShoeRuns)).",
                      ja: "同じ時期の他の靴と比較できるランが\(runs)回なので、まだ特徴は判断しません(\(C.minShoeRuns)回から)。")
                : nil
        }
        return L.s("같은 시기 다른 신발 대비 ", "Vs other shoes in the same weeks: ", ja: "同じ時期の他の靴と比べて ")
            + parts.joined(separator: " · ")
    }

    /// "최근 4주, 3개월 전보다 같은 페이스·거리에서 접지 −6ms(짧아짐)"
    private func trendSentence(_ mod: C.Model) -> String? {
        let pts = C.points(metric, samples: samples, model: mod, from: Calendar.current.date(byAdding: .day, value: -110, to: Date())!)
        guard let ch = C.recentChange(pts, asOf: Date()) else { return nil }
        let d = ch.now - ch.then
        let name = metricName(metric)
        if !notable(d, metric) {
            return L.s("내 폼: 최근 4주 \(name)이 3개월 전과 비슷합니다(\(fmt(d, metric))).",
                       "Your form: \(name) in the last 4 weeks is about the same as 3 months ago (\(fmt(d, metric))).",
                       ja: "自分のフォーム: 直近4週の\(name)は3か月前とほぼ同じです(\(fmt(d, metric)))。")
        }
        return L.s("내 폼: 최근 4주 \(name)이 3개월 전보다 \(dirKo(d, metric))습니다(\(fmt(d, metric))).",
                   "Your form: \(name) in the last 4 weeks is \(dirEn(d, metric)) than 3 months ago (\(fmt(d, metric))).",
                   ja: "自分のフォーム: 直近4週の\(name)は3か月前より\(dirJa(d, metric))(\(fmt(d, metric)))。")
    }

    // 방향은 사실로만 — 좋다·나쁘다로 단정하지 않는다(접지가 긴 신발이 나쁜 신발은 아니다)
    private func dirKo(_ d: Double, _ m: C.Metric) -> String {
        switch m {
        case .contact:     return d > 0 ? "길어졌" : "짧아졌"
        case .oscillation: return d > 0 ? "커졌" : "작아졌"
        case .efficiency:  return d > 0 ? "올랐" : "내렸"
        }
    }
    private func dirEn(_ d: Double, _ m: C.Metric) -> String {
        switch m {
        case .contact:     return d > 0 ? "longer" : "shorter"
        case .oscillation: return d > 0 ? "higher" : "lower"
        case .efficiency:  return d > 0 ? "higher" : "lower"
        }
    }
    private func dirJa(_ d: Double, _ m: C.Metric) -> String {
        switch m {
        case .contact:     return d > 0 ? "長くなりました" : "短くなりました"
        case .oscillation: return d > 0 ? "大きくなりました" : "小さくなりました"
        case .efficiency:  return d > 0 ? "上がりました" : "下がりました"
        }
    }

    private func footnote(_ m: C.Model) -> String {
        m.usesTemperature
            ? L.s("0 = 내 평소 — 최근 1년 러닝 \(m.n)회로 만든 '이 속도·거리·기온이면 보통 얼마'.",
                  "0 = your usual — what your last \(m.n) runs say to expect at that speed, distance and temperature.",
                  ja: "0 = いつもの値 — 直近1年のラン\(m.n)回から作った「この速度・距離・気温ならふつうはいくつ」。")
            : L.s("0 = 내 평소 — 최근 1년 러닝 \(m.n)회로 만든 '이 속도·거리면 보통 얼마'. 페이스·거리 영향을 뺀 값입니다.",
                  "0 = your usual — what your last \(m.n) runs say to expect at that speed and distance. Pace and distance are taken out.",
                  ja: "0 = いつもの値 — 直近1年のラン\(m.n)回から作った「この速度・距離ならふつうはいくつ」。ペース・距離の影響を除いた値です。")
    }

    // MARK: - ① 내 폼 변화

    private func trendCard(_ mod: C.Model) -> some View {
        let now = Date()
        let from = Calendar.current.date(byAdding: .month, value: -months, to: now)!
        let pts = C.points(metric, samples: samples, model: mod, from: from)
        let line = C.trend(pts, from: from, to: now)
        let mine = pts.filter { $0.shoeID == myID }
        let others = pts.filter { $0.shoeID != myID }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L.s("① 내 폼 변화", "① How my form is changing", ja: "① 自分のフォームの変化"))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                ForEach([6, 12], id: \.self) { n in
                    Button { months = n } label: {
                        Text(L.s("\(n)개월", "\(n)mo", ja: "\(n)か月"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(months == n ? Color.white : Color.white.opacity(0.55))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(months == n ? Theme.violet : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(mod.usesTemperature
                 ? L.s("같은 페이스·거리·기온으로 보정", "Adjusted for pace, distance and temperature", ja: "同じペース・距離・気温で補正")
                 : L.s("같은 페이스·거리로 보정", "Adjusted for pace and distance", ja: "同じペース・距離で補正"))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            if pts.isEmpty {
                Text(L.s("이 기간에 기록이 없습니다.", "No runs in this period.", ja: "この期間の記録はありません。"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            } else {
                Chart {
                    RuleMark(y: .value("0", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.white.opacity(0.3))
                    ForEach(Array(others.enumerated()), id: \.offset) { _, p in
                        PointMark(x: .value("d", p.date), y: .value("v", p.value))
                            .symbolSize(22)
                            .foregroundStyle(Color.white.opacity(0.28))
                    }
                    ForEach(Array(mine.enumerated()), id: \.offset) { _, p in
                        PointMark(x: .value("d", p.date), y: .value("v", p.value))
                            .symbolSize(40)
                            .foregroundStyle(Theme.violet)
                    }
                    ForEach(Array(line.enumerated()), id: \.offset) { _, t in
                        LineMark(x: .value("d", t.date), y: .value("trend", t.value))
                            .foregroundStyle(Color.white)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartXScale(domain: from...now)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: months > 6 ? 2 : 1)) { x in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).locale(L.locale))
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { y in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel { Text(fmt(y.as(Double.self) ?? 0, metric)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)) }
                    }
                }
                .frame(height: 190)
                Text(L.s("흰 선 = 내 폼(4주 이동평균, 모든 신발) · 보라 점 = \(shoe.displayName) · 회색 점 = 다른 신발 · 점선 0 = 내 평소",
                         "White line = my form (4-week average, all shoes) · violet = \(shoe.displayName) · gray = other shoes · dashed 0 = usual",
                         ja: "白い線 = 自分のフォーム(4週移動平均、全シューズ) · 紫の点 = \(shoe.displayName) · 灰色の点 = 他の靴 · 点線0 = いつもの値"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Text({
                    switch metric {
                    case .contact:     return L.s("아래 = 같은 조건에서 접지가 짧음", "Lower = shorter contact at the same pace", ja: "下 = 同じ条件で接地が短い")
                    case .oscillation: return L.s("아래 = 같은 조건에서 덜 튐", "Lower = less bounce at the same pace", ja: "下 = 同じ条件で上下動が小さい")
                    case .efficiency:  return L.s("위 = 같은 심박에 더 빠름", "Higher = faster at the same heart rate", ja: "上 = 同じ心拍でより速い")
                    }
                }())
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    // MARK: - ② 신발 비교 — 같은 시기 대비

    private func compareCard(_ mod: C.Model) -> some View {
        let stats = C.shoeStats(metric, samples: samples, model: mod)
        let ordered = stats.filter { $0.shoeID == myID } + stats.filter { $0.shoeID != myID }
        let rowName: (C.ShoeStat) -> String = { "\(shoeName($0.shoeID)) (\($0.n))" }
        return VStack(alignment: .leading, spacing: 10) {
            Text(L.s("② 신발 비교 — 같은 시기 다른 신발 대비", "② Shoes — vs other shoes in the same weeks", ja: "② 靴の比較 — 同じ時期の他の靴と比べて"))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            if ordered.isEmpty {
                Text(L.s("같은 시기에 다른 신발로 뛴 러닝이 있어야 비교할 수 있습니다.",
                         "Needs runs in other shoes during the same weeks.",
                         ja: "同じ時期に他の靴で走ったランが必要です。"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            } else {
                Chart {
                    RuleMark(x: .value("0", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.white.opacity(0.35))
                    ForEach(ordered, id: \.shoeID) { s in
                        let mine = s.shoeID == myID
                        if let h = s.half {
                            RuleMark(xStart: .value("lo", s.mean - h), xEnd: .value("hi", s.mean + h), y: .value("shoe", rowName(s)))
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                .foregroundStyle((mine ? Theme.violet : Color.white).opacity(0.35))
                        }
                        PointMark(x: .value("avg", s.mean), y: .value("shoe", rowName(s)))
                            .symbolSize(mine ? 110 : 80)
                            .foregroundStyle(mine ? Theme.violet : Color.white.opacity(0.85))
                    }
                }
                .chartYScale(domain: ordered.map(rowName))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { x in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel { Text(fmt(x.as(Double.self) ?? 0, metric)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)) }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { y in
                        AxisValueLabel {
                            Text(y.as(String.self) ?? "").font(.system(size: 10)).foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1).minimumScaleFactor(0.75).frame(width: 120, alignment: .leading)
                        }
                    }
                }
                .frame(height: CGFloat(ordered.count) * 36 + 28)
                Text(L.s("점 = 같은 시기(앞뒤 2주) 다른 신발 대비 평균 · 막대 = 95% 범위 · 괄호 = 횟수 · 막대가 0을 넘나들면 차이 없음",
                         "Dot = average vs other shoes in the same ±2 weeks · bar = 95% range · () = runs · crossing 0 = no difference",
                         ja: "点 = 同じ時期(前後2週)の他の靴との差の平均 · 棒 = 95%範囲 · () = 回数 · 棒が0をまたげば差なし"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(ordered.prefix(5), id: \.shoeID) { s in
                    Text(shoeLine(s))
                        .font(.system(size: 12))
                        .foregroundStyle(s.shoeID == myID ? Theme.violetText : .white.opacity(0.75))
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

    private func shoeLine(_ s: C.ShoeStat) -> String {
        let name = shoeName(s.shoeID), mn = metricName(metric)
        if s.n < C.minShoeRuns {
            return L.s("\(name): \(s.n)회 — 아직 판단하기 이릅니다", "\(name): \(s.n) runs — too early to tell", ja: "\(name): \(s.n)回 — まだ判断できません")
        }
        if !s.differs || !notable(s.mean, metric) {
            return L.s("\(name): \(mn) 다른 신발과 같음(\(fmt(s.mean, metric)))",
                       "\(name): \(mn) same as other shoes (\(fmt(s.mean, metric)))",
                       ja: "\(name): \(mn)は他の靴と同じ(\(fmt(s.mean, metric)))")
        }
        let ko: String = {
            switch metric {
            case .contact:     return s.mean > 0 ? "깁니다" : "짧습니다"
            case .oscillation: return s.mean > 0 ? "큽니다" : "작습니다"
            case .efficiency:  return s.mean > 0 ? "높습니다" : "낮습니다"
            }
        }()
        let ja: String = {
            switch metric {
            case .contact:     return s.mean > 0 ? "長いです" : "短いです"
            case .oscillation: return s.mean > 0 ? "大きいです" : "小さいです"
            case .efficiency:  return s.mean > 0 ? "高いです" : "低いです"
            }
        }()
        return L.s("\(name): \(mn)이 다른 신발보다 \(fmt(abs(s.mean), metric).dropFirst()) \(ko)",
                   "\(name): \(mn) is \(fmt(abs(s.mean), metric).dropFirst()) \(dirEn(s.mean, metric)) than other shoes",
                   ja: "\(name): \(mn)が他の靴より\(fmt(abs(s.mean), metric).dropFirst())\(ja)")
    }
}
