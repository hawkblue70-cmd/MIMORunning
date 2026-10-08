import SwiftUI
import SwiftData
import Charts

/// 나 탭 › 신발 › 신발 상세(2026-10-08) — 질문 둘에 답한다: 이 신발은 거리가 쌓이며 변하나(수명) · 다른 신발과 다른가.
/// 값은 전부 "이 속도·거리면 내 평소" 대비 차이(ShoeFormComparison) — 러닝 종류로 쪼개지 않는다.
struct ShoeDetailView: View {
    let shoe: Shoe
    var manager: HealthKitManager

    @Query private var stories: [WorkoutStory]
    @Query private var shoes: [Shoe]
    @Environment(\.dismiss) private var dismiss

    @State private var samples: [ShoeFormComparison.Sample] = []
    @State private var shoeDistances: [(date: Date, meters: Double)] = []
    @State private var metric: ShoeFormComparison.Metric = .contact
    @State private var loaded = false

    private typealias C = ShoeFormComparison
    private var L: AppLanguage { AppLanguage.shared }
    private var myID: String { shoe.id.uuidString }
    private var totalKm: Double { shoeDistances.reduce(0) { $0 + $1.meters } / 1000 }
    private var model: C.Model? { C.fit(metric, samples: samples, asOf: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !loaded {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        headline
                        metricChips.padding(.horizontal, 16)
                        if let m = model {
                            wearCard(m)
                            compareCard(m)
                            Text(L.s("0 = 내 평소 — 최근 1년 러닝 \(m.n)회로 만든 '이 속도·거리면 보통 얼마'. 페이스와 거리 영향을 빼고 신발만 봅니다.",
                                     "0 = your usual — what your last \(m.n) runs say to expect at that speed and distance. Pace and distance are taken out so only the shoe remains.",
                                     ja: "0 = いつもの値 — 直近1年のラン\(m.n)回から作った「この速度・距離ならふつうはいくつ」。ペースと距離の影響を除き、靴だけを見ます。"))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 16)
                        } else {
                            Text(L.s("이 지표가 있는 러닝이 최근 1년 \(C.minModelRuns)회 이상 쌓이면 비교합니다.",
                                     "Comparisons start once the last year has \(C.minModelRuns)+ runs with this metric.",
                                     ja: "この指標があるランが直近1年で\(C.minModelRuns)回以上たまると比較します。"))
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
        samples = C.samples(inputs: manager.formInputs, shoeOf: { shoeByWorkout[$0.uuidString] })
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
        case .efficiency:  return L.s("심박 효율", "HR efficiency", ja: "心拍効率")
        case .oscillation: return L.s("수직진폭", "Vertical oscillation", ja: "上下動")
        }
    }

    /// 차이 표기 — 부호 포함
    private func fmt(_ v: Double) -> String {
        let sign = v >= 0 ? "+" : "−"
        switch metric {
        case .contact:     return "\(sign)\(Int(abs(v).rounded()))ms"
        case .efficiency:  return "\(sign)\(String(format: "%.1f", abs(v)))%"
        case .oscillation: return "\(sign)\(String(format: "%.1f", abs(v)))cm"
        }
    }

    /// 차이가 좋은 쪽인가
    private func isBetter(_ d: Double) -> Bool { metric.higherIsBetter ? d > 0 : d < 0 }

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

    // MARK: - 결론 한 줄

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: totalKm >= 100 ? "%.0f" : "%.1f", totalKm))
                    .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("km").font(.system(size: 14)).foregroundStyle(.secondary)
                Text(L.s("· 러닝 \(shoeDistances.count)회", "· \(shoeDistances.count) runs", ja: "· ラン\(shoeDistances.count)回"))
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            if let m = model {
                Text(wearSentence(m)).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L.s("흔히 500~800km에서 바꿉니다(관행, 근거는 약함)",
                     "Shoes are commonly replaced at 500–800 km (convention, weak evidence)",
                     ja: "一般に500~800kmで交換します(慣行、根拠は弱い)"))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 16)
    }

    /// 수명 결론 — 새 신발 때 대비 최근 5회
    private func wearSentence(_ m: C.Model) -> String {
        let pts = C.wear(metric, shoeID: myID, samples: samples, model: m, shoeDistances: shoeDistances)
        let name = metricName(metric)
        guard let v = C.verdict(pts) else {
            return L.s("\(name) 기록이 \(pts.count)회라 아직 변화를 말하지 않습니다.",
                       "Only \(pts.count) runs with \(name) — too early to call a change.",
                       ja: "\(name)の記録が\(pts.count)回なので、まだ変化は判断しません。")
        }
        guard let ch = v.change else {
            return L.s("새 신발 구간(\(v.earlyRuns)회) 뒤 러닝이 5회 쌓이면 변화를 봅니다.",
                       "Change is checked once 5 runs follow the new-shoe stretch (\(v.earlyRuns) runs).",
                       ja: "新品の区間(\(v.earlyRuns)回)の後にランが5回たまると変化を見ます。")
        }
        if abs(ch) < metric.noticeable {
            return L.s("\(name) 새 신발 때와 같음(\(fmt(ch))) — 교체 신호 없음",
                       "\(name) same as when new (\(fmt(ch))) — no sign to replace",
                       ja: "\(name)は新品のときと同じ(\(fmt(ch))) — 交換のサインなし")
        }
        return isBetter(ch)
            ? L.s("\(name) 새 신발 때보다 좋아짐(\(fmt(ch)))",
                  "\(name) better than when new (\(fmt(ch)))",
                  ja: "\(name)は新品のときより良くなりました(\(fmt(ch)))")
            : L.s("\(name) 새 신발 때보다 나빠짐(\(fmt(ch))) — 쿠션 상태를 확인하세요",
                  "\(name) worse than when new (\(fmt(ch))) — check the cushioning",
                  ja: "\(name)が新品のときより悪化(\(fmt(ch))) — クッションの状態を確認してください")
    }

    // MARK: - ① 수명 — 누적 km

    private func wearCard(_ m: C.Model) -> some View {
        let pts = C.wear(metric, shoeID: myID, samples: samples, model: m, shoeDistances: shoeDistances)
        let v = C.verdict(pts)
        let maxKm = max(totalKm * 1.15, 200)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L.s("① 수명 — 누적 km에 따른 변화", "① Lifespan — change with mileage", ja: "① 寿命 — 累計kmによる変化"))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            if pts.isEmpty {
                Text(L.s("이 신발로 \(metricName(metric))이 기록된 러닝이 없습니다.",
                         "No runs in this shoe with \(metricName(metric)).",
                         ja: "この靴で\(metricName(metric))が記録されたランはありません。"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            } else {
                Chart {
                    if maxKm >= 500 {
                        RectangleMark(xStart: .value("a", 500), xEnd: .value("b", min(800, maxKm)))
                            .foregroundStyle(Color.white.opacity(0.05))
                    }
                    if let v {
                        RectangleMark(xStart: .value("a", 0), xEnd: .value("b", maxKm),
                                      yStart: .value("lo", v.earlyMean - max(v.earlySD, metric.noticeable / 2)),
                                      yEnd: .value("hi", v.earlyMean + max(v.earlySD, metric.noticeable / 2)))
                            .foregroundStyle(Theme.violet.opacity(0.12))
                    }
                    RuleMark(y: .value("0", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.white.opacity(0.35))
                    ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                        PointMark(x: .value("km", p.km), y: .value("v", p.value))
                            .symbolSize(30)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                        if let r = p.rolling {
                            LineMark(x: .value("km", p.km), y: .value("roll", r))
                                .foregroundStyle(Theme.violet)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .interpolationMethod(.monotone)
                        }
                    }
                }
                .chartXScale(domain: 0...maxKm)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { x in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel { Text("\(Int(x.as(Double.self) ?? 0))km").font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)) }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { y in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel { Text(fmt(y.as(Double.self) ?? 0)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)) }
                    }
                }
                .frame(height: 180)
                Text(L.s("점 = 러닝 하나 · 보라 선 = 최근 5회 평균 · 보라 띠 = 새 신발 때(처음 100km) · 점선 0 = 내 평소",
                         "Dot = one run · violet line = last-5 average · violet band = when new (first 100 km) · dashed 0 = your usual",
                         ja: "点 = ラン1回 · 紫の線 = 直近5回平均 · 紫の帯 = 新品のとき(最初の100km) · 点線0 = いつもの値"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    // MARK: - ② 신발 비교

    private func compareCard(_ m: C.Model) -> some View {
        let stats = C.shoeStats(metric, samples: samples, model: m)
        let ordered = stats.filter { $0.shoeID == myID } + stats.filter { $0.shoeID != myID }
        let rowName: (C.ShoeStat) -> String = { "\(shoeName($0.shoeID)) (\($0.n))" }
        return VStack(alignment: .leading, spacing: 10) {
            Text(L.s("② 신발 비교 — 같은 페이스·거리라면", "② Shoes compared — at the same pace & distance", ja: "② 靴の比較 — 同じペース・距離なら"))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            if ordered.isEmpty {
                Text(L.s("신발을 고른 러닝이 없습니다.", "No runs with a shoe selected.", ja: "靴を選んだランがありません。"))
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
                        AxisValueLabel { Text(fmt(x.as(Double.self) ?? 0)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)) }
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
                Text(L.s("점 = 평균 · 막대 = 95% 범위(횟수가 적을수록 김) · 괄호 = 횟수 · 막대가 0을 넘나들면 차이 없음",
                         "Dot = average · bar = 95% range (longer with fewer runs) · () = runs · a bar crossing 0 means no difference",
                         ja: "点 = 平均 · 棒 = 95%範囲(回数が少ないほど長い) · () = 回数 · 棒が0をまたげば差なし"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(ordered.prefix(4), id: \.shoeID) { s in
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

    /// 신발 한 줄 판정 — 5회 미만은 "아직", 범위가 0을 넘나들면 "평소와 같음"
    private func shoeLine(_ s: C.ShoeStat) -> String {
        let name = shoeName(s.shoeID), mn = metricName(metric)
        if s.n < C.minShoeRuns {
            return L.s("\(name): \(s.n)회 — 아직 판단하기 이릅니다",
                       "\(name): \(s.n) runs — too early to tell",
                       ja: "\(name): \(s.n)回 — まだ判断できません")
        }
        if !s.differs || abs(s.mean) < metric.noticeable / 2 {
            return L.s("\(name): \(mn) 평소와 같음(\(fmt(s.mean)))",
                       "\(name): \(mn) same as usual (\(fmt(s.mean)))",
                       ja: "\(name): \(mn)はいつもと同じ(\(fmt(s.mean)))")
        }
        return isBetter(s.mean)
            ? L.s("\(name): \(mn) 평소보다 좋음(\(fmt(s.mean)))", "\(name): \(mn) better than usual (\(fmt(s.mean)))", ja: "\(name): \(mn)はいつもより良い(\(fmt(s.mean)))")
            : L.s("\(name): \(mn) 평소보다 나쁨(\(fmt(s.mean)))", "\(name): \(mn) worse than usual (\(fmt(s.mean)))", ja: "\(name): \(mn)はいつもより悪い(\(fmt(s.mean)))")
    }
}
