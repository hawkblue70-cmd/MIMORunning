import Foundation

/// 러닝 흐름 차트 아래 문장 — **상태 한 줄 + 방향 한 줄**.
///
/// 규칙 엔진(결정적)이며 판단어·"부상/위험" 같은 표현을 쓰지 않는다(§5.4 사실 판단은 규칙, 문장은 어휘).
/// 창을 **앞뒤 절반**으로 나눠 거리·페이스·강도 세 축의 방향(up/flat/down)을 잡고,
/// 그 조합을 6개 문장 중 하나로 옮긴다. 절반에 러닝이 3회 미만이면 방향을 말하지 않는다(상태 줄만).
///
/// 순수 함수만 있고 화면·HealthKit에 의존하지 않는다.
enum RecordFlowInsight {

    // MARK: - 임계값 (한 곳에서만)

    /// 거리 합계 변화율 — 이 값을 **넘어야** 방향으로 본다(정확히 같으면 유지).
    static let distanceThreshold = 0.10
    /// 거리 가중 평균 페이스 변화(초/km).
    static let paceThresholdSec = 5.0
    /// 평균 강도 변화(1~10 척도).
    static let effortThreshold = 1.0
    /// 절반마다 필요한 최소 러닝 횟수.
    static let minRunsPerHalf = 3
    /// 시간 가중 평균 심박 변화(bpm) — 체감 강도가 그대로인데 페이스가 느려졌을 때 "편하게 뛴 것"인지 가른다.
    /// ⚠ 3bpm은 임의로 정함(기온-심박 설명 문턱 `MRHeatHRModel.explainThresholdBpm`과 같게).
    static let heartRateThresholdBpm = 3.0

    // MARK: - 입력

    struct Input {
        let bars: [RecordBar]
        /// .day → 앞뒤 절반은 날짜(=버킷) 기준, .week → 6주/6주
        let period: RecordPeriod
        /// 쉬운 날 판정: `meanEffort ≤ easyCutoff`
        let easyCutoff: Int
    }

    /// 세 축 각각의 방향. 페이스는 **빠름 = .up**(초/km가 작아짐).
    enum Direction: Equatable { case up, flat, down }

    struct Trend: Equatable {
        let distance: Direction
        let pace: Direction
        let effort: Direction
        let firstRuns: Int
        let secondRuns: Int
        /// 버킷 평균 심박 중앙값 방향 — 심박 없는 러닝뿐이면 .flat(판정에 안 쓴다)
        var heartRate: Direction = .flat
        /// 체감 강도와 심박이 **둘 다** 내려갔는가(각각 문턱 미만이어도) — 조금 편하게 뛰어 조금 느려진 경우를 잡는다
        var easedOnBoth: Bool = false
    }

    enum Sentence: Equatable {
        case fasterSameEffort      // 페이스 up & 강도 flat/down
        case moreAndHarder         // 거리 up & 강도 up
        case moreSteadyEffort      // 거리 up & 강도 flat
        case recovering            // 거리 down & 강도 down
        case slowerHarder          // 페이스 down & 강도 up
        case steady                // 모두 flat
        // ── 나머지 조합도 빈칸 없이 채운다(표본이 있으면 방향 문장은 항상 하나) ──
        case easierSlower          // 페이스 down & 강도 down — 천천히·편하게
        case pushingFaster         // 페이스 up & 강도 up — 밀어붙여 빨라짐
        case lessButHarder         // 거리 down & 강도 up
        case lowerEffort           // 강도 down(그 외)
        case harder                // 강도 up(그 외)
        case lessDistance          // 거리 down & 강도 flat
        case slower                // 페이스 down & 강도 flat
        case none                  // 표본 부족
    }

    struct Result: Equatable {
        /// "최근 30일 · 22회 · 165 km · 쉬운 날 60%"
        let status: String
        /// nil이면 상태 줄만 보여 준다.
        let direction: String?
        let sentence: Sentence
        let trend: Trend?

        /// 상태 줄에서 기간·횟수·거리(앞 세 칸)를 뺀 것 — 월 결산 공유 카드는 그 숫자를 위에 크게 싣는다.
        /// 남는 칸(쉬운 날 %)이 없으면 방향 줄을 상태 자리로 올리고, 그것도 없으면 nil.
        func withoutTotals() -> Result? {
            let rest = status.components(separatedBy: " · ").dropFirst(3)
            if rest.isEmpty {
                guard let d = direction else { return nil }
                return Result(status: d, direction: nil, sentence: sentence, trend: trend)
            }
            return Result(status: rest.joined(separator: " · "), direction: direction, sentence: sentence, trend: trend)
        }
    }

    // MARK: - 방향 판정

    /// 창을 시간순 절반(버킷 개수)으로 나눠 세 축의 방향을 잡는다.
    /// 절반 중 하나라도 러닝이 `minRunsPerHalf` 미만이면 nil(방향을 말하지 않음).
    static func trend(_ input: Input) -> Trend? {
        let bars = input.bars
        guard bars.count >= 2 else { return nil }
        let mid = bars.count / 2                 // 홀수면 뒤 절반이 하나 더 갖는다
        let first = Array(bars[0..<mid])
        let second = Array(bars[mid...])

        let firstRuns = first.reduce(0) { $0 + $1.runCount }
        let secondRuns = second.reduce(0) { $0 + $1.runCount }
        guard firstRuns >= minRunsPerHalf, secondRuns >= minRunsPerHalf else { return nil }

        return Trend(
            distance: distanceDirection(first, second),
            pace: paceDirection(first, second),
            effort: effortDirection(first, second),
            firstRuns: firstRuns,
            secondRuns: secondRuns,
            heartRate: heartRateDirection(first, second),
            easedOnBoth: easedOnBoth(first, second)
        )
    }

    /// 체감 강도 평균과 심박 중앙값이 **둘 다** 내려갔는가. 둘 중 하나라도 없으면 false.
    /// (2026-09-29 실기기: 강도 4.7→3.8 · 심박 138→135 · 페이스 6초 느려짐 — 각각 문턱 미만이라 "같은 강도"로 묶였다)
    private static func easedOnBoth(_ first: [RecordBar], _ second: [RecordBar]) -> Bool {
        guard let ea = meanEffort(first), let eb = meanEffort(second),
              let ha = medianHR(first), let hb = medianHR(second) else { return false }
        return eb < ea && hb < ha
    }

    private static func distanceDirection(_ first: [RecordBar], _ second: [RecordBar]) -> Direction {
        let a = first.reduce(0) { $0 + $1.km }
        let b = second.reduce(0) { $0 + $1.km }
        guard a > 0 else { return b > 0 ? .up : .flat }
        let rel = (b - a) / a
        if rel > distanceThreshold { return .up }
        if rel < -distanceThreshold { return .down }
        return .flat
    }

    /// 거리 가중 평균 페이스(sec/km). **빨라지면 .up**.
    private static func paceDirection(_ first: [RecordBar], _ second: [RecordBar]) -> Direction {
        guard let a = RecordSeries.paceBaseline(first), let b = RecordSeries.paceBaseline(second) else { return .flat }
        let delta = a - b                        // 양수 = 뒤 절반이 더 빠름
        if delta > paceThresholdSec { return .up }
        if delta < -paceThresholdSec { return .down }
        return .flat
    }

    /// 강도 있는 버킷의 평균 강도(버킷 단위 평균).
    private static func effortDirection(_ first: [RecordBar], _ second: [RecordBar]) -> Direction {
        guard let a = meanEffort(first), let b = meanEffort(second) else { return .flat }
        let delta = b - a
        if delta > effortThreshold { return .up }
        if delta < -effortThreshold { return .down }
        return .flat
    }

    /// 심박 방향(bpm) — 버킷(하루·주·달) 평균 심박의 **중앙값**끼리 비교. 한쪽이라도 심박이 없으면 .flat.
    /// 시간 가중 평균은 롱런·대회 한 번(100분)이 이지런 여러 번을 덮어 "편하게 뛴 날이 늘었다"를 놓쳤다
    /// (2026-09-29 실기기: 9월 하순 이지런 134bpm이 9/26 롱런 빌드업에 묻힘) — 보통 날의 강도를 본다.
    static func medianHR(_ bars: [RecordBar]) -> Double? {
        let v = bars.compactMap(\.avgHR).sorted()
        guard !v.isEmpty else { return nil }
        let m = v.count / 2
        return v.count % 2 == 1 ? v[m] : (v[m - 1] + v[m]) / 2
    }

    private static func heartRateDirection(_ first: [RecordBar], _ second: [RecordBar]) -> Direction {
        guard let a = medianHR(first), let b = medianHR(second) else { return .flat }
        let delta = b - a
        if delta >= heartRateThresholdBpm { return .up }
        if delta <= -heartRateThresholdBpm { return .down }   // 3bpm 포함(138→135)
        return .flat
    }

    private static func meanEffort(_ bars: [RecordBar]) -> Double? {
        let vals = bars.compactMap(\.meanEffort)
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    // MARK: - 문장 선택 (우선순위 하나뿐)

    static func sentence(for trend: Trend) -> Sentence {
        if trend.pace == .up, trend.effort == .flat || trend.effort == .down { return .fasterSameEffort }
        if trend.distance == .up, trend.effort == .up { return .moreAndHarder }
        if trend.distance == .up, trend.effort == .flat { return .moreSteadyEffort }
        if trend.distance == .down, trend.effort == .down { return .recovering }
        if trend.pace == .down, trend.effort == .up { return .slowerHarder }
        if trend.distance == .flat, trend.pace == .flat, trend.effort == .flat { return .steady }
        // 빈틈 채우기 — 강도 방향을 축으로 나머지 조합을 배정
        switch trend.effort {
        case .down: return trend.pace == .down ? .easierSlower : .lowerEffort
        case .up:   return trend.pace == .up ? .pushingFaster : (trend.distance == .down ? .lessButHarder : .harder)
        case .flat:
            if trend.distance == .down { return .lessDistance }
            // 체감 강도가 "그대로"여도 심박이 3bpm↓이거나, 강도·심박이 둘 다 조금씩 내려갔으면
            // 더위·피로가 아니라 편하게 뛴 것 — 이지런으로 느려진 경우(2026-09-29 사용자)
            if trend.pace == .down {
                return (trend.heartRate == .down || trend.easedOnBoth) ? .easierSlower : .slower
            }
            return .steady
        }
    }

    // MARK: - 상태 줄

    static func status(_ input: Input, periodLabel: String) -> String {
        let L = AppLanguage.shared
        let bars = input.bars
        let runs = bars.reduce(0) { $0 + $1.runCount }
        let km = bars.reduce(0.0) { $0 + $1.km }

        var parts = [periodLabel,
                     L.s("\(runs)회", "\(runs) runs", ja: "\(runs)回"),
                     "\(kmText(km)) km"]

        let rated = bars.compactMap(\.meanEffort)
        if !rated.isEmpty {
            let easy = rated.filter { $0 <= Double(input.easyCutoff) }.count
            let pct = Int((Double(easy) / Double(rated.count) * 100).rounded())
            parts.append(L.s("쉬운 날 \(pct)%", "easy days \(pct)%", ja: "楽な日 \(pct)%"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 방향 줄

    private static func directionText(_ sentence: Sentence, input: Input) -> String? {
        let L = AppLanguage.shared
        switch sentence {
        case .fasterSameEffort:
            return L.s("같은 노력으로 더 빨라지고 있습니다.",
                       "Getting faster at the same effort.", ja: "同じ努力でより速くなっています。")
        case .moreAndHarder:
            return L.s("거리와 강도가 함께 올라가는 중입니다. 쉬운 날을 하나 더 두면 오래 갑니다.",
                       "Distance and effort are both climbing. One more easy day helps this last.", ja: "距離と強度が一緒に上がっています。楽な日をもう1日入れると長続きします。")
        case .moreSteadyEffort:
            return L.s("거리를 늘리면서도 강도는 지켰습니다.",
                       "More distance without more effort.", ja: "距離を伸ばしながら強度は保ちました。")
        case .recovering:
            return L.s("거리와 강도를 낮춘 회복 구간입니다.",
                       "A recovery stretch — less distance, lower effort.", ja: "距離と強度を下げた回復期間です。")
        case .slowerHarder:
            return L.s("힘은 더 드는데 페이스는 느려졌습니다. 더위·수면·피로를 한번 돌아봐 주세요.",
                       "Harder effort but slower pace. Worth checking heat, sleep and fatigue.", ja: "きつさは増したのにペースは遅くなりました。暑さ・睡眠・疲労を一度振り返ってみてください。")
        case .steady:
            let runs = input.bars.reduce(0) { $0 + $1.runCount }
            let km = input.bars.reduce(0.0) { $0 + $1.km }
            let perWeek = runs > 0 ? Double(runs) / max(1, weekSpan(input.bars)) : 0
            let perRun = runs > 0 ? km / Double(runs) : 0
            let n = String(format: "%.1f", perWeek)
            let avg = String(format: "%.1f", perRun)
            return L.s("고른 흐름입니다. 주 \(n)회 · 평균 \(avg) km.",
                       "A steady rhythm — \(n)/week · \(avg) km avg.", ja: "安定した流れです。週\(n)回 · 平均\(avg) km。")
        case .easierSlower:
            return L.s("천천히, 편하게 뛴 구간입니다. 의도한 여유라면 그대로 좋습니다.",
                       "Slower and easier — fine if the easing was intended.", ja: "ゆっくり楽に走った期間です。意図したゆとりならそのままで大丈夫です。")
        case .pushingFaster:
            return L.s("더 밀어붙여 빨라졌습니다. 다음 쉬운 날을 꼭 챙기세요.",
                       "Faster by pushing harder. Make sure the next easy day stays easy.", ja: "より追い込んで速くなりました。次の楽な日を必ず確保してください。")
        case .lessButHarder:
            return L.s("거리는 줄었지만 강도는 올랐습니다. 양보다 질에 기울어진 구간.",
                       "Less distance, more effort — a quality-over-volume stretch.", ja: "距離は減りましたが強度は上がりました。量より質に寄った期間。")
        case .lowerEffort:
            return L.s("강도를 낮춘 구간입니다.",
                       "Effort has come down.", ja: "強度を下げた期間です。")
        case .harder:
            return L.s("강도가 올라가는 중입니다. 쉬운 날이 함께 있는지 봐 주세요.",
                       "Effort is climbing. Check that easy days are still in the mix.", ja: "強度が上がっています。楽な日も入っているか確認してください。")
        case .lessDistance:
            return L.s("거리를 줄인 구간입니다.",
                       "Distance has come down.", ja: "距離を減らした期間です。")
        case .slower:
            return L.s("같은 강도인데 페이스가 느려졌습니다. 더위나 피로일 수 있습니다.",
                       "Same effort, slower pace — heat or fatigue may be at play.", ja: "同じ強度なのにペースが遅くなりました。暑さや疲労かもしれません。")
        case .none:
            return nil
        }
    }

    /// 창의 길이를 주 단위로 (버킷 단위와 무관하게 실제 기간에서).
    private static func weekSpan(_ bars: [RecordBar]) -> Double {
        guard let first = bars.first, let last = bars.last else { return 1 }
        let days = last.end.timeIntervalSince(first.id) / 86_400
        return max(1, days / 7)
    }

    // MARK: - 조립

    static func evaluate(_ input: Input, periodLabel: String) -> Result {
        let t = trend(input)
        let s = t.map { sentence(for: $0) } ?? .none
        return Result(status: status(input, periodLabel: periodLabel),
                      direction: directionText(s, input: input),
                      sentence: s,
                      trend: t)
    }

    // MARK: - 표기

    /// 100 km 미만은 소수 한 자리("46.5"), 그 이상은 정수("165").
    private static func kmText(_ km: Double) -> String {
        km >= 100 ? String(format: "%.0f", km) : String(format: "%.1f", km)
    }
}
