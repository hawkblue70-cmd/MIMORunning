import SwiftUI
import SwiftData
import Charts

/// 나 탭 › 신발 › 신발 상세(2026-10-08) — 신발 성격: 같은 시기 다른 신발 대비 지면접촉·수직진폭.
/// 값은 "이 속도·거리면 내 평소" 대비 차이(ShoeFormComparison)에서 같은 시기(앞뒤 14일) 다른 신발 러닝을 뺀 것 — 계절·체력이 빠진다.
/// 내 폼의 흐름은 성장 탭 › 폼 변화(FormChangeCard). 신발 수명·심박 효율은 다루지 않는다.
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
    @State private var shareData: ShoeShareData?

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
                            compareCard(m)
                            Text(L.s("0 = 같은 시기 다른 신발 — 최근 1년 러닝 \(m.n)회로 페이스·거리 영향을 뺀 값입니다. 내 폼의 흐름은 성장 탭 › 폼 변화에서 봅니다.",
                                     "0 = other shoes in the same weeks — pace and distance taken out using your last \(m.n) runs. Your form trend is in Growth › Form change.",
                                     ja: "0 = 同じ時期の他の靴 — 直近1年のラン\(m.n)回でペース・距離の影響を除いた値です。自分のフォームの流れは成長タブ › フォームの変化で見られます。"))
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
                    if loaded {
                        // 내보내기 — 맨 아래(2026-10-08 사용자 요청). 결론 + 지표 네 개 신발 비교 2×2 한 장
                        Button { shareData = makeShareData() } label: {
                            Label(L.s("러닝화 폼 데이터 내보내기", "Export shoe form data", ja: "シューズのフォームデータを書き出す"),
                                  systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Theme.violet)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
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
        .sheet(item: $shareData) { ShoeShareScreen(data: $0) }
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
        case .oscillation: return L.s("수직진폭", "Vertical oscillation", ja: "上下動")
        case .stride:      return L.s("보폭", "Stride", ja: "ストライド")
        case .cadence:     return L.s("케이던스", "Cadence", ja: "ケイデンス")
        case .flight:      return L.s("공중 시간", "Flight time", ja: "滞空時間")
        }
    }

    private func shortName(_ m: C.Metric) -> String {
        switch m {
        case .contact:     return L.s("접지", "contact", ja: "接地")
        case .oscillation: return L.s("진폭", "oscillation", ja: "上下動")
        case .stride:      return L.s("보폭", "stride", ja: "ストライド")
        case .cadence:     return L.s("케이던스", "cadence", ja: "ケイデンス")
        case .flight:      return L.s("공중 시간", "flight", ja: "滞空時間")
        }
    }

    /// 차이 표기(부호 포함) — 판정과 같은 반올림, 폼 변화 카드와 같은 표기
    private func fmt(_ v: Double, _ m: C.Metric) -> String { FormChangeStyle.fmt(v, m) }

    /// 반올림한 값이 문턱 이상인가
    private func notable(_ v: Double, _ m: C.Metric) -> Bool { abs(m.rounded(v)) >= m.noticeable }

    private var metricChips: some View {
        HStack(spacing: 8) {
            ForEach(C.Metric.shown, id: \.self) { m in
                let on = m == metric
                Button { metric = m } label: {
                    Text(metricName(m))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(on ? Color.black : Color.white.opacity(0.6))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(on ? FormChangeStyle.tint(m) : Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 결론 — 신발 성격

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
            if let r = rhythmSentence() {
                Text(r).font(.system(size: 13)).foregroundStyle(FormChangeStyle.tint(.contact))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
    }

    /// "같은 시기 다른 신발 대비 접지 +8ms · 진폭 같음"
    private func characterSentence() -> String? {
        var parts: [String] = []
        var runs = 0
        for m in C.Metric.shown {
            guard let mod = model(m), let s = C.shoeStats(m, samples: samples, model: mod).first(where: { $0.shoeID == myID }) else { continue }
            runs = max(runs, s.n)
            guard s.n >= C.minShoeRuns else { continue }
            // 막대가 0을 안 넘지만 말할 만한 차이보다 작으면 '차이 작음' — 막대와 글이 어긋나지 않게(2026-10-08)
            parts.append(s.differs && notable(s.mean, m) ? "\(shortName(m)) \(fmt(s.mean, m))"
                : s.differs ? "\(shortName(m)) " + L.s("차이 작음", "small difference", ja: "小さな差")
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

    /// 접지 차이가 있을 때 — 그게 리듬(케이던스) 때문인지 공중 시간 때문인지, 같은 시기 기준으로 계산한 값으로
    /// "같은 리듬(케이던스 +0spm)에서 공중 시간이 8ms 짧은 신발입니다"
    private func rhythmSentence() -> String? {
        func effect(_ m: C.Metric) -> C.ShoeStat? {
            guard let mod = model(m) else { return nil }
            return C.shoeStats(m, samples: samples, model: mod).first { $0.shoeID == myID && $0.n >= C.minShoeRuns }
        }
        guard let g = effect(.contact), g.differs, notable(g.mean, .contact),
              let c = effect(.cadence), let f = effect(.flight) else { return nil }
        let cad = fmt(c.mean, .cadence), fl = String(fmt(abs(f.mean), .flight).dropFirst())
        let shorterFlight = f.mean < 0
        if !notable(c.mean, .cadence) {
            return L.s("같은 리듬(케이던스 \(cad))에서 공중 시간이 \(fl) \(shorterFlight ? "짧은" : "긴") 신발입니다.",
                       "Same rhythm (cadence \(cad)) with \(fl) \(shorterFlight ? "less" : "more") time in the air.",
                       ja: "同じリズム(ケイデンス \(cad))で滞空時間が\(fl)\(shorterFlight ? "短い" : "長い")靴です。")
        }
        return L.s("케이던스 \(cad), 공중 시간 \(fmt(f.mean, .flight)) — 리듬이 달라진 신발입니다.",
                   "Cadence \(cad), flight time \(fmt(f.mean, .flight)) — this shoe changes your rhythm.",
                   ja: "ケイデンス \(cad)、滞空時間 \(fmt(f.mean, .flight)) — リズムが変わる靴です。")
    }

    // MARK: - 신발 비교 — 같은 시기 대비

    private func compareCard(_ mod: C.Model) -> some View {
        let ordered = ordered(metric, mod)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L.s("신발 비교 — 같은 시기 다른 신발 대비", "Shoes — vs other shoes in the same weeks", ja: "靴の比較 — 同じ時期の他の靴と比べて"))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            if ordered.isEmpty {
                Text(L.s("같은 시기에 다른 신발로 뛴 러닝이 있어야 비교할 수 있습니다.",
                         "Needs runs in other shoes during the same weeks.",
                         ja: "同じ時期に他の靴で走ったランが必要です。"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            } else {
                // 신발 이름 열(왼쪽) + 막대(오른쪽) — 이름이 막대 위에 겹치지 않게(2026-10-08 사용자 요청), 공유 카드와 같은 컴포넌트
                ShoeCompareChart(rows: ordered.map(row), metric: metric)
                Text(L.s("점 = 같은 시기(앞뒤 2주) 다른 신발 대비 평균 · 막대 = 95% 범위 · 괄호 = 횟수 · 막대가 0을 넘나들면 같음 · 안 넘어도 말할 만한 차이보다 작으면 차이 작음",
                         "Dot = average vs other shoes in the same ±2 weeks · bar = 95% range · () = runs · crossing 0 = same · not crossing but below a noticeable size = small difference",
                         ja: "点 = 同じ時期(前後2週)の他の靴との差の平均 · 棒 = 95%範囲 · () = 回数 · 棒が0をまたげば同じ · またがなくても目立つ差より小さければ小さな差"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(ordered.prefix(5), id: \.shoeID) { s in
                    Text(shoeLine(s, metric))
                        .font(.system(size: 12))
                        .foregroundStyle(s.shoeID == myID ? FormChangeStyle.tint(metric) : .white.opacity(0.75))
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

    // 색: 지표 칩·이 신발 점·막대·이름·한 줄 = 지표의 애플 시스템 색(폼 변화 카드와 같은 FormChangeStyle.tint, 2026-10-08)

    private func row(_ s: C.ShoeStat) -> ShoeCompareChart.Row {
        .init(id: s.shoeID, name: "\(shoeName(s.shoeID)) (\(s.n))", stat: s, mine: s.shoeID == myID)
    }

    /// 이 신발 먼저, 나머지는 비교 횟수 순
    private func ordered(_ m: C.Metric, _ mod: C.Model) -> [C.ShoeStat] {
        let stats = C.shoeStats(m, samples: samples, model: mod)
        return stats.filter { $0.shoeID == myID } + stats.filter { $0.shoeID != myID }
    }

    // MARK: - 공유

    private func makeShareData() -> ShoeShareData {
        let panels = C.Metric.shown.map { m -> ShoeShareData.Panel in
            guard let mod = model(m) else { return .init(metric: m, rows: [], line: nil) }
            let o = ordered(m, mod)
            let mine = o.first { $0.shoeID == myID }
            return .init(metric: m, rows: o.prefix(ShoeShareCard.maxRows).map(row),
                         line: mine.map { shoeLine($0, m, withName: false) })
        }
        return ShoeShareData(shoeName: shoe.displayName, totalKm: totalKm, runs: shoeDistances.count,
                             character: characterSentence(), rhythm: rhythmSentence(), panels: panels,
                             modelRuns: model(.contact)?.n)
    }

    /// 신발 한 줄 — 방향 사실만(좋다·나쁘다로 단정하지 않는다: 접지가 긴 신발이 나쁜 신발은 아니다)
    /// `withName == false`면 "이 신발:" 없이(공유 칸 — 칸 제목이 지표, 카드 제목이 신발)
    private func shoeLine(_ s: C.ShoeStat, _ metric: C.Metric, withName: Bool = true) -> String {
        let line = shoeLineNamed(s, metric)
        guard !withName, let r = line.range(of: ": ") else { return line }
        return String(line[r.upperBound...])
    }

    private func shoeLineNamed(_ s: C.ShoeStat, _ metric: C.Metric) -> String {
        let name = shoeName(s.shoeID), mn = metricName(metric)
        if s.n < C.minShoeRuns {
            return L.s("\(name): \(s.n)회 — 아직 판단하기 이릅니다", "\(name): \(s.n) runs — too early to tell", ja: "\(name): \(s.n)回 — まだ判断できません")
        }
        if s.differs && !notable(s.mean, metric) {
            return L.s("\(name): \(mn) 다른 신발과 차이 작음(\(fmt(s.mean, metric)))",
                       "\(name): \(mn) small difference from other shoes (\(fmt(s.mean, metric)))",
                       ja: "\(name): \(mn)は他の靴と小さな差(\(fmt(s.mean, metric)))")
        }
        if !s.differs {
            return L.s("\(name): \(mn) 다른 신발과 같음(\(fmt(s.mean, metric)))",
                       "\(name): \(mn) same as other shoes (\(fmt(s.mean, metric)))",
                       ja: "\(name): \(mn)は他の靴と同じ(\(fmt(s.mean, metric)))")
        }
        let amount = String(fmt(abs(s.mean), metric).dropFirst())
        let longer = s.mean > 0
        switch metric {
        case .contact:
            return L.s("\(name): 지면접촉이 다른 신발보다 \(amount) \(longer ? "깁니다" : "짧습니다")",
                       "\(name): ground contact \(amount) \(longer ? "longer" : "shorter") than other shoes",
                       ja: "\(name): 接地時間が他の靴より\(amount)\(longer ? "長いです" : "短いです")")
        case .oscillation:
            return L.s("\(name): 수직진폭이 다른 신발보다 \(amount) \(longer ? "큽니다" : "작습니다")",
                       "\(name): vertical oscillation \(amount) \(longer ? "higher" : "lower") than other shoes",
                       ja: "\(name): 上下動が他の靴より\(amount)\(longer ? "大きいです" : "小さいです")")
        case .stride:
            return L.s("\(name): 보폭이 다른 신발보다 \(amount) \(longer ? "깁니다" : "짧습니다")",
                       "\(name): stride \(amount) \(longer ? "longer" : "shorter") than other shoes",
                       ja: "\(name): ストライドが他の靴より\(amount)\(longer ? "長いです" : "短いです")")
        case .cadence:
            return L.s("\(name): 케이던스가 다른 신발보다 \(amount) \(longer ? "높습니다" : "낮습니다")",
                       "\(name): cadence \(amount) \(longer ? "higher" : "lower") than other shoes",
                       ja: "\(name): ケイデンスが他の靴より\(amount)\(longer ? "高いです" : "低いです")")
        case .flight:
            // 칩에 없는 문장 전용 지표
            return L.s("\(name): \(mn) \(fmt(s.mean, metric))", "\(name): \(mn) \(fmt(s.mean, metric))", ja: "\(name): \(mn) \(fmt(s.mean, metric))")
        }
    }
}
