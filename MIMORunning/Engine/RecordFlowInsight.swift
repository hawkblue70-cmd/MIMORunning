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
    }

    enum Sentence: Equatable {
        case fasterSameEffort      // 페이스 up & 강도 flat/down
        case moreAndHarder         // 거리 up & 강도 up
        case moreSteadyEffort      // 거리 up & 강도 flat
        case recovering            // 거리 down & 강도 down
        case slowerHarder          // 페이스 down & 강도 up
        case steady                // 모두 flat
        case none                  // 표본 부족 또는 그 외 조합
    }

    struct Result: Equatable {
        /// "최근 30일 · 22회 · 165 km · 쉬운 날 60%"
        let status: String
        /// nil이면 상태 줄만 보여 준다.
        let direction: String?
        let sentence: Sentence
        let trend: Trend?
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
            secondRuns: secondRuns
        )
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
        return .none
    }

    // MARK: - 상태 줄

    static func status(_ input: Input, periodLabel: String) -> String {
        let L = AppLanguage.shared
        let bars = input.bars
        let runs = bars.reduce(0) { $0 + $1.runCount }
        let km = bars.reduce(0.0) { $0 + $1.km }

        var parts = [periodLabel,
                     L.s("\(runs)회", "\(runs) runs"),
                     "\(kmText(km)) km"]

        let rated = bars.compactMap(\.meanEffort)
        if !rated.isEmpty {
            let easy = rated.filter { $0 <= Double(input.easyCutoff) }.count
            let pct = Int((Double(easy) / Double(rated.count) * 100).rounded())
            parts.append(L.s("쉬운 날 \(pct)%", "easy days \(pct)%"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 방향 줄

    private static func directionText(_ sentence: Sentence, input: Input) -> String? {
        let L = AppLanguage.shared
        switch sentence {
        case .fasterSameEffort:
            return L.s("같은 노력으로 더 빨라지고 있어요.",
                       "Getting faster at the same effort.")
        case .moreAndHarder:
            return L.s("거리와 강도가 함께 올라가는 중이에요. 쉬운 날을 하나 더 두면 오래 갑니다.",
                       "Distance and effort are both climbing. One more easy day helps this last.")
        case .moreSteadyEffort:
            return L.s("거리를 늘리면서도 강도는 지켰어요.",
                       "More distance without more effort.")
        case .recovering:
            return L.s("거리와 강도를 낮춘 회복 구간이에요.",
                       "A recovery stretch — less distance, lower effort.")
        case .slowerHarder:
            return L.s("힘은 더 드는데 페이스는 느려졌어요. 더위·수면·피로를 한번 돌아봐 주세요.",
                       "Harder effort but slower pace. Worth checking heat, sleep and fatigue.")
        case .steady:
            let runs = input.bars.reduce(0) { $0 + $1.runCount }
            let km = input.bars.reduce(0.0) { $0 + $1.km }
            let perWeek = runs > 0 ? Double(runs) / max(1, weekSpan(input.bars)) : 0
            let perRun = runs > 0 ? km / Double(runs) : 0
            let n = String(format: "%.1f", perWeek)
            let avg = String(format: "%.1f", perRun)
            return L.s("고른 흐름이에요. 주 \(n)회 · 평균 \(avg) km.",
                       "A steady rhythm — \(n)/week · \(avg) km avg.")
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
