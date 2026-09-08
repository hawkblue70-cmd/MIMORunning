import Testing
import Foundation
@testable import MIMORunning

/// 문자열 검사는 언어 전역 상태(`AppLanguage.shared`)를 건드리므로 직렬 실행.
@Suite("RecordFlowInsight 러닝 흐름 문장", .serialized)
struct RecordFlowInsightTests {

    // MARK: - 헬퍼

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func day(_ i: Int) -> Date { Self.base.addingTimeInterval(Double(i) * 86_400) }

    /// 하루 버킷 하나.
    private func bar(_ i: Int, km: Double, runs: Int = 1, pace: Double? = nil, effort: Double? = nil) -> RecordBar {
        RecordBar(id: day(i), end: day(i + 1), km: km, minutes: km * 6, au: 0,
                  paceSec: pace, meanEffort: effort, avgHR: nil,
                  runCount: runs, ratedCount: effort == nil ? 0 : runs)
    }

    /// 주 버킷 하나(7일).
    private func weekBar(_ i: Int, km: Double, runs: Int = 1, pace: Double? = nil, effort: Double? = nil) -> RecordBar {
        RecordBar(id: day(i * 7), end: day((i + 1) * 7), km: km, minutes: km * 6, au: 0,
                  paceSec: pace, meanEffort: effort, avgHR: nil,
                  runCount: runs, ratedCount: effort == nil ? 0 : runs)
    }

    /// 앞 3버킷 / 뒤 3버킷 — 각 절반 3회로 최소 표본을 만족한다.
    private func halves(firstKm: Double, secondKm: Double,
                        firstPace: Double? = nil, secondPace: Double? = nil,
                        firstEffort: Double? = nil, secondEffort: Double? = nil,
                        easyCutoff: Int = 4) -> RecordFlowInsight.Input {
        var bars: [RecordBar] = []
        for i in 0..<3 { bars.append(bar(i, km: firstKm, pace: firstPace, effort: firstEffort)) }
        for i in 3..<6 { bars.append(bar(i, km: secondKm, pace: secondPace, effort: secondEffort)) }
        return RecordFlowInsight.Input(bars: bars, period: .day, easyCutoff: easyCutoff)
    }

    private func trendOf(_ input: RecordFlowInsight.Input) -> RecordFlowInsight.Trend? {
        RecordFlowInsight.trend(input)
    }

    // MARK: - 절반 분할

    @Test func splitsByCount() {
        let t = trendOf(halves(firstKm: 10, secondKm: 10))
        #expect(t?.firstRuns == 3)
        #expect(t?.secondRuns == 3)
    }

    @Test func weekWindowSplitsSixSix() {
        // 12주 창 → 6주 / 6주
        let bars = (0..<12).map { weekBar($0, km: 30, runs: 4, pace: 360, effort: 4) }
        let t = RecordFlowInsight.trend(.init(bars: bars, period: .week, easyCutoff: 4))
        #expect(t?.firstRuns == 24)
        #expect(t?.secondRuns == 24)
        #expect(t?.distance == .flat)
    }

    @Test func nilWhenHalfHasTooFewRuns() {
        // 앞 절반 2회 → 방향 없음
        let bars = [bar(0, km: 10), bar(1, km: 10), bar(2, km: 0, runs: 0),
                    bar(3, km: 10), bar(4, km: 10), bar(5, km: 10)]
        #expect(RecordFlowInsight.trend(.init(bars: bars, period: .day, easyCutoff: 4)) == nil)

        // 뒤 절반 2회 → 방향 없음
        let bars2 = [bar(0, km: 10), bar(1, km: 10), bar(2, km: 10),
                     bar(3, km: 10), bar(4, km: 10), bar(5, km: 0, runs: 0)]
        #expect(RecordFlowInsight.trend(.init(bars: bars2, period: .day, easyCutoff: 4)) == nil)
    }

    // MARK: - 거리 (±10%, 임계값 정확히 = 유지)

    @Test func distanceDirection() {
        #expect(trendOf(halves(firstKm: 10, secondKm: 12))?.distance == .up)      // +20%
        #expect(trendOf(halves(firstKm: 10, secondKm: 11))?.distance == .flat)    // 정확히 +10%
        #expect(trendOf(halves(firstKm: 10, secondKm: 9))?.distance == .flat)     // 정확히 −10%
        #expect(trendOf(halves(firstKm: 10, secondKm: 8))?.distance == .down)     // −20%
    }

    // MARK: - 페이스 (빠름 = .up, ±5초)

    @Test func paceDirectionUpMeansFaster() {
        // 뒤 절반이 6초 빠름 → .up
        #expect(trendOf(halves(firstKm: 10, secondKm: 10, firstPace: 360, secondPace: 354))?.pace == .up)
        // 정확히 5초 → 유지
        #expect(trendOf(halves(firstKm: 10, secondKm: 10, firstPace: 360, secondPace: 355))?.pace == .flat)
        #expect(trendOf(halves(firstKm: 10, secondKm: 10, firstPace: 360, secondPace: 365))?.pace == .flat)
        // 6초 느려짐 → .down
        #expect(trendOf(halves(firstKm: 10, secondKm: 10, firstPace: 360, secondPace: 366))?.pace == .down)
        // 페이스가 없으면 유지
        #expect(trendOf(halves(firstKm: 10, secondKm: 10))?.pace == .flat)
    }

    // MARK: - 강도 (±1)

    @Test func effortDirection() {
        #expect(trendOf(halves(firstKm: 10, secondKm: 10, firstEffort: 4, secondEffort: 5.2))?.effort == .up)
        #expect(trendOf(halves(firstKm: 10, secondKm: 10, firstEffort: 4, secondEffort: 5))?.effort == .flat)   // 정확히 +1
        #expect(trendOf(halves(firstKm: 10, secondKm: 10, firstEffort: 4, secondEffort: 3))?.effort == .flat)   // 정확히 −1
        #expect(trendOf(halves(firstKm: 10, secondKm: 10, firstEffort: 4, secondEffort: 2.5))?.effort == .down)
        #expect(trendOf(halves(firstKm: 10, secondKm: 10))?.effort == .flat)                                    // 강도 없음
    }

    // MARK: - 문장 우선순위 표

    @Test func sentencePriority() {
        func s(_ d: RecordFlowInsight.Direction,
               _ p: RecordFlowInsight.Direction,
               _ e: RecordFlowInsight.Direction) -> RecordFlowInsight.Sentence {
            RecordFlowInsight.sentence(for: .init(distance: d, pace: p, effort: e, firstRuns: 3, secondRuns: 3))
        }
        // 페이스 up + 강도 flat/down → 최우선
        #expect(s(.up, .up, .flat) == .fasterSameEffort)
        #expect(s(.down, .up, .down) == .fasterSameEffort)
        // 페이스 up이라도 강도 up이면 아님
        #expect(s(.up, .up, .up) == .moreAndHarder)
        #expect(s(.up, .flat, .up) == .moreAndHarder)
        #expect(s(.up, .flat, .flat) == .moreSteadyEffort)
        #expect(s(.down, .flat, .down) == .recovering)
        #expect(s(.flat, .down, .up) == .slowerHarder)
        #expect(s(.flat, .flat, .flat) == .steady)
        // 나머지 조합도 빈칸 없이
        #expect(s(.down, .flat, .flat) == .lessDistance)
        #expect(s(.flat, .down, .flat) == .slower)
        #expect(s(.flat, .down, .down) == .easierSlower)
        #expect(s(.flat, .up, .up) == .pushingFaster)
        #expect(s(.down, .flat, .up) == .lessButHarder)
        #expect(s(.flat, .flat, .down) == .lowerEffort)
        #expect(s(.flat, .flat, .up) == .harder)
        #expect(s(.flat, .up, .flat) == .fasterSameEffort)
    }

    // MARK: - 상태 줄

    @Test func statusWithAndWithoutRatedBuckets() {
        AppLanguage.shared.isEnglish = false
        // 강도 있는 버킷 6개 중 3개가 쉬운 날(≤4) → 50%
        var bars: [RecordBar] = []
        for i in 0..<3 { bars.append(bar(i, km: 10, pace: 360, effort: 3)) }
        for i in 3..<6 { bars.append(bar(i, km: 10, pace: 360, effort: 8)) }
        let rated = RecordFlowInsight.Input(bars: bars, period: .day, easyCutoff: 4)
        #expect(RecordFlowInsight.status(rated, periodLabel: "최근 30일") == "최근 30일 · 6회 · 60.0 km · 쉬운 날 50%")

        // 강도 기록이 없으면 "쉬운 날" 부분을 뺀다
        let unrated = RecordFlowInsight.Input(bars: (0..<6).map { bar($0, km: 10, pace: 360) },
                                              period: .day, easyCutoff: 4)
        #expect(RecordFlowInsight.status(unrated, periodLabel: "최근 30일") == "최근 30일 · 6회 · 60.0 km")

        // 100 km 이상은 정수
        let big = RecordFlowInsight.Input(bars: (0..<6).map { bar($0, km: 30) }, period: .day, easyCutoff: 4)
        #expect(RecordFlowInsight.status(big, periodLabel: "최근 30일") == "최근 30일 · 6회 · 180 km")
    }

    // MARK: - 조립 · steady 숫자

    @Test func steadyNumbers() {
        AppLanguage.shared.isEnglish = false
        // 12주 · 주 1회 · 매회 10km → "주 1.0회 · 평균 10.0 km"
        let bars = (0..<12).map { weekBar($0, km: 10, runs: 1, pace: 360, effort: 4) }
        let result = RecordFlowInsight.evaluate(.init(bars: bars, period: .week, easyCutoff: 4),
                                                periodLabel: "최근 12주")
        #expect(result.sentence == .steady)
        #expect(result.direction == "고른 흐름이에요. 주 1.0회 · 평균 10.0 km.")
        #expect(result.status == "최근 12주 · 12회 · 120 km · 쉬운 날 100%")   // 100 km 이상은 정수
        #expect(result.trend?.firstRuns == 6)
    }

    @Test func evaluateWithoutEnoughRunsHasNoDirection() {
        AppLanguage.shared.isEnglish = false
        let bars = [bar(0, km: 10), bar(1, km: 0, runs: 0), bar(2, km: 0, runs: 0),
                    bar(3, km: 10), bar(4, km: 10), bar(5, km: 10)]
        let result = RecordFlowInsight.evaluate(.init(bars: bars, period: .day, easyCutoff: 4),
                                                periodLabel: "최근 30일")
        #expect(result.trend == nil)
        #expect(result.sentence == .none)
        #expect(result.direction == nil)
        #expect(result.status == "최근 30일 · 4회 · 40.0 km")
    }

    @Test func fasterSameEffortEndToEnd() {
        AppLanguage.shared.isEnglish = false
        let input = halves(firstKm: 10, secondKm: 10,
                           firstPace: 370, secondPace: 350,
                           firstEffort: 4, secondEffort: 4)
        let result = RecordFlowInsight.evaluate(input, periodLabel: "최근 30일")
        #expect(result.sentence == .fasterSameEffort)
        #expect(result.direction == "같은 노력으로 더 빨라지고 있어요.")
    }

    @Test func englishStrings() {
        AppLanguage.shared.isEnglish = true
        defer { AppLanguage.shared.isEnglish = false }
        let input = halves(firstKm: 10, secondKm: 14, firstEffort: 3, secondEffort: 3)
        let result = RecordFlowInsight.evaluate(input, periodLabel: "Last 30 days")
        #expect(result.sentence == .moreSteadyEffort)
        #expect(result.direction == "More distance without more effort.")
        #expect(result.status == "Last 30 days · 6 runs · 72.0 km · easy days 100%")
    }
}
