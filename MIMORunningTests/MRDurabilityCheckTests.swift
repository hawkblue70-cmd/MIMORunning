import Testing
import Foundation
@testable import MIMORunning

@Suite("MRDurabilityCheck S1 피로 시 케이던스 붕괴")
struct MRDurabilityCheckTests {

    /// km 스플릿 생성기. cadences[i]가 nil이면 케이던스 없음.
    private func splits(paces: [Double], cadences: [Int?], hrs: [Int?]? = nil,
                        lastPartialM: Double? = nil) -> [SplitData] {
        var out: [SplitData] = []
        for (i, p) in paces.enumerated() {
            out.append(SplitData(id: i + 1, distanceM: 1000, duration: p,
                                 avgHeartRate: hrs?[i] ?? nil, avgCadence: cadences[i],
                                 avgPower: nil, avgGroundContactTime: nil,
                                 avgStrideLength: nil, avgVerticalOscillation: nil))
        }
        if let m = lastPartialM {
            out.append(SplitData(id: paces.count + 1, distanceM: m, duration: m / 1000 * 400,
                                 avgHeartRate: nil, avgCadence: 170, avgPower: nil,
                                 avgGroundContactTime: nil, avgStrideLength: nil,
                                 avgVerticalOscillation: nil))
        }
        return out
    }

    private func fatigue(q1Pace: Double = 400, q4Pace: Double = 400,
                         q1Cad: Double = 170, q4Cad: Double = 170,
                         hr: Double? = nil, daysAgo: Int = 1) -> MRLongRunFatigue {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return MRLongRunFatigue(id: UUID(), date: Calendar.current.startOfDay(for: d),
                                distanceKm: 16, durationMin: 105,
                                q1PaceSecPerKm: q1Pace, q4PaceSecPerKm: q4Pace,
                                q1Cadence: q1Cad, q4Cadence: q4Cad,
                                firstHalfAvgHR: hr, cadenceCoverage: 1.0)
    }

    // MARK: 자격

    @Test func eligibilityRequiresDistanceDurationAndType() {
        #expect(MRDurabilityCheck.isEligibleLongRun(distanceKm: 10, durationMin: 60, longest16wKm: 12, workoutType: .easy))
        #expect(!MRDurabilityCheck.isEligibleLongRun(distanceKm: 9, durationMin: 60, longest16wKm: 12, workoutType: .easy))
        #expect(!MRDurabilityCheck.isEligibleLongRun(distanceKm: 10, durationMin: 59, longest16wKm: 12, workoutType: .easy))
        // 최근 16주 최장 20km → 하한 14km
        #expect(!MRDurabilityCheck.isEligibleLongRun(distanceKm: 12, durationMin: 80, longest16wKm: 20, workoutType: .longRun))
        #expect(MRDurabilityCheck.isEligibleLongRun(distanceKm: 14, durationMin: 80, longest16wKm: 20, workoutType: .longRun))
        #expect(!MRDurabilityCheck.isEligibleLongRun(distanceKm: 16, durationMin: 90, longest16wKm: 20, workoutType: .interval))
        #expect(!MRDurabilityCheck.isEligibleLongRun(distanceKm: 16, durationMin: 90, longest16wKm: 20, workoutType: .buildUp))
        #expect(!MRDurabilityCheck.isEligibleLongRun(distanceKm: 16, durationMin: 90, longest16wKm: 20, workoutType: .tempo))
    }

    // MARK: 요약

    @Test func summaryExcludesFirstKmAndLastPartialSplit() throws {
        // 12 스플릿 + 부분 스플릿. km1 제외 → 11개 → 분기 크기 max(2, 11/4)=2
        // Q1 = km2,3 · Q4 = km11,12
        let paces: [Double] = [500, 400, 400, 400, 400, 400, 400, 400, 400, 400, 420, 420]
        let cads: [Int?]    = [150, 170, 170, 170, 170, 170, 170, 170, 170, 170, 164, 164]
        let s = try #require(MRDurabilityCheck.summarize(id: UUID(), date: Date(), distanceKm: 12.5,
                                                          durationMin: 84, splits: splits(paces: paces, cadences: cads, lastPartialM: 500)))
        #expect(abs(s.q1PaceSecPerKm - 400) < 0.01)
        #expect(abs(s.q4PaceSecPerKm - 420) < 0.01)
        #expect(abs(s.q1Cadence - 170) < 0.01)
        #expect(abs(s.q4Cadence - 164) < 0.01)
        #expect(abs(s.cadenceCoverage - 1.0) < 0.01)
    }

    @Test func summaryReturnsNilWhenTooFewSplitsOrLowCoverage() {
        let seven = splits(paces: Array(repeating: 400, count: 7), cadences: Array(repeating: 170, count: 7))
        #expect(MRDurabilityCheck.summarize(id: UUID(), date: Date(), distanceKm: 7, durationMin: 47, splits: seven) == nil)
        // 10개 중 케이던스 7개(70%) → 커버리지 미달
        var cads: [Int?] = Array(repeating: 170, count: 10)
        cads[2] = nil; cads[5] = nil; cads[8] = nil
        let low = splits(paces: Array(repeating: 400, count: 10), cadences: cads)
        #expect(MRDurabilityCheck.summarize(id: UUID(), date: Date(), distanceKm: 10, durationMin: 67, splits: low) == nil)
    }

    // MARK: 판정

    @Test func evaluateReturnsNilOutsidePaceGate() {
        // 6% 느려짐 → 평가 불가
        let f = fatigue(q1Pace: 400, q4Pace: 424, q1Cad: 170, q4Cad: 160)
        #expect(MRDurabilityCheck.evaluate(f, recentMedianPace: nil, maxHR: nil) == nil)
    }

    @Test func evaluateReturnsNilOnEarlyOverpaceOrEarlyHighHR() {
        // 초반 과속: 최근 중앙 420, Q1 390 (< 399)
        let over = fatigue(q1Pace: 390, q4Pace: 395, q1Cad: 170, q4Cad: 160)
        #expect(MRDurabilityCheck.evaluate(over, recentMedianPace: 420, maxHR: nil) == nil)
        // 초반 역치: maxHR 190 × 0.85 = 161.5, 전반 165
        let high = fatigue(q1Pace: 400, q4Pace: 400, q1Cad: 170, q4Cad: 160, hr: 165)
        #expect(MRDurabilityCheck.evaluate(high, recentMedianPace: 400, maxHR: 190) == nil)
        // 전반 158이면 통과
        let ok = fatigue(q1Pace: 400, q4Pace: 400, q1Cad: 170, q4Cad: 160, hr: 158)
        #expect(MRDurabilityCheck.evaluate(ok, recentMedianPace: 400, maxHR: 190) == true)
    }

    @Test func evaluateThresholdIsThreePercent() {
        // 2% 하락 → false, 3.5% 하락 → true
        #expect(MRDurabilityCheck.evaluate(fatigue(q1Cad: 170, q4Cad: 166.6), recentMedianPace: nil, maxHR: nil) == false)
        #expect(MRDurabilityCheck.evaluate(fatigue(q1Cad: 170, q4Cad: 164), recentMedianPace: nil, maxHR: nil) == true)
    }

    // MARK: 집계

    @Test func aggregateTriggersOnTwoOfThree() {
        let fs = [fatigue(q1Cad: 170, q4Cad: 164, daysAgo: 2),
                  fatigue(q1Cad: 170, q4Cad: 170, daysAgo: 9),
                  fatigue(q1Cad: 170, q4Cad: 163, daysAgo: 16)]
        let v = MRDurabilityCheck.aggregate(fatigue: fs, runs: [], maxHR: nil, asOf: Date())
        #expect(v.evaluated == 3)
        #expect(v.positive == 2)
        #expect(v.triggered)
    }

    @Test func aggregateNeedsTwoEvaluableRuns() {
        let v = MRDurabilityCheck.aggregate(fatigue: [fatigue(q1Cad: 170, q4Cad: 160)],
                                            runs: [], maxHR: nil, asOf: Date())
        #expect(!v.triggered)
    }

    @Test func aggregateUsesOnlyLatestThreeWithinEightWeeks() {
        let fs = [fatigue(q1Cad: 170, q4Cad: 170, daysAgo: 2),
                  fatigue(q1Cad: 170, q4Cad: 170, daysAgo: 9),
                  fatigue(q1Cad: 170, q4Cad: 170, daysAgo: 16),
                  fatigue(q1Cad: 170, q4Cad: 160, daysAgo: 23),   // 4번째 — 무시
                  fatigue(q1Cad: 170, q4Cad: 160, daysAgo: 70)]   // 8주 밖 — 무시
        let v = MRDurabilityCheck.aggregate(fatigue: fs, runs: [], maxHR: nil, asOf: Date())
        #expect(v.evaluated == 3)
        #expect(v.positive == 0)
        #expect(!v.triggered)
    }

    @Test func aggregateReportsLatestDropPercent() {
        let fs = [fatigue(q1Cad: 170, q4Cad: 161.5, daysAgo: 0),  // −5%
                  fatigue(q1Cad: 170, q4Cad: 164, daysAgo: 7)]
        let v = MRDurabilityCheck.aggregate(fatigue: fs, runs: [], maxHR: nil, asOf: Date())
        #expect(v.triggered)
        #expect(abs((v.latestDropPct ?? 0) - 5.0) < 0.1)
        #expect(v.latestPositiveIsToday)
    }
}
