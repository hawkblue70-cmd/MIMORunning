import Testing
import Foundation
@testable import MIMORunning

@Suite("강도 훈련 — 인터벌 페이스는 본인 기록", .korean)
struct MRIntervalHistoryTests {

    private let t0 = Date(timeIntervalSince1970: 1_791_000_000)
    private func seg(_ id: Int, from: Double, sec: Double, m: Double?, label: String) -> IntervalSegment {
        IntervalSegment(id: id, startDate: t0.addingTimeInterval(from), endDate: t0.addingTimeInterval(from + sec),
                        distanceM: m, avgHeartRate: nil, avgCadence: nil, stepLabel: label)
    }
    /// 400m × 5 (각 108초 = 4'30"/km), 회복 200m 72초
    private func fourHundreds() -> [IntervalSegment] {
        var s: [IntervalSegment] = [seg(0, from: 0, sec: 600, m: 2000, label: "준비운동")]
        var t = 600.0
        for i in 1...5 {
            s.append(seg(i * 2 - 1, from: t, sec: 108, m: 400, label: "운동")); t += 108
            if i < 5 { s.append(seg(i * 2, from: t, sec: 72, m: 200, label: "회복")); t += 72 }
        }
        return s
    }

    @Test func summarizesWorkAndRecoverySegments() throws {
        let h = try #require(mrIntervalHistory(segments: fourHundreds(), date: t0))
        #expect(h.repKm == 0.4)
        #expect(h.reps == 5)
        #expect(abs(h.paceSecPerKm - 270) < 0.5)
        #expect(abs(h.recoverySec - 72) < 0.5)
    }

    @Test func fewerThanThreeWorkSegmentsIsNil() {
        let s = Array(fourHundreds().prefix(4))   // 준비 + 운동 2개(+회복 1)
        #expect(mrIntervalHistory(segments: s, date: t0) == nil)
    }

    @Test func threeToFiveMinuteRepsUseMyActualPace() {
        // 1km 5'00" = 300초 → 3~5분 반복 → 본인 실제 페이스
        let h = MRIntervalHistory(date: t0, repKm: 1.0, reps: 4, paceSecPerKm: 300, recoverySec: 180)
        let r = mrIntervalPace(history: h, fiveKPace: 307)
        #expect(r.pace == 300)
        #expect(r.fromHistory)
    }

    @Test func shortRepsFallBackToPredictedFiveK() {
        // 400m 4'30" = 108초 → 2분 미만, 다른 에너지 구간 → 5K 예측 페이스
        let h = MRIntervalHistory(date: t0, repKm: 0.4, reps: 5, paceSecPerKm: 270, recoverySec: 72)
        let r = mrIntervalPace(history: h, fiveKPace: 307)
        #expect(r.pace == 307)
        #expect(!r.fromHistory)
        #expect(mrIntervalPace(history: nil, fiveKPace: 307).fromHistory == false)
    }

    @Test func overFiveMinuteRepsAlsoFallBack() {
        let h = MRIntervalHistory(date: t0, repKm: 1.2, reps: 3, paceSecPerKm: 280, recoverySec: 180)   // 336초
        #expect(!mrIntervalPace(history: h, fiveKPace: 307).fromHistory)
    }

    @Test func howToShowsPaceBasis() {
        var p = MRPlanPoint(kind: .speed, totalKm: 8.5, reps: 5, repKm: 0.8, sustainedKm: nil, paceSecPerKm: 307)
        #expect(p.howTo.hasSuffix("예상 5K 기록 기준"))
        p.paceFromHistory = true
        #expect(p.howTo.hasSuffix("최근 인터벌 페이스 기준"))
    }

    @Test func planUsesHistoryPaceOnlyForThreeToFiveMinuteReps() throws {
        var pr = MRProfile()
        pr.weeklyKm4w = 45; pr.longestRun16wKm = 22; pr.maxWeeklyKm52w = 60; pr.runsPerWeek = 5
        let today = Date()
        let race = Calendar.current.date(byAdding: .day, value: 7 * 24, to: today)!
        let hist = MRIntervalHistory(date: t0, repKm: 1.0, reps: 4, paceSecPerKm: 300, recoverySec: 180)
        let p = try #require(mrBuildPlan(raceDate: race, distanceM: MRDistance.dF, today: today, profile: pr,
                                         halfEquivMin: 110, easyPaceSecPerKm: 400, heat: MRHeatModel(),
                                         raceTempC: 15, runsPerWeek: 5, intervalHistory: hist))
        let speeds = p.weeks.compactMap(\.point).filter { $0.kind == .speed }
        #expect(!speeds.isEmpty)
        #expect(speeds.allSatisfy { $0.paceSecPerKm == 300 && $0.paceFromHistory == true })
        #expect(speeds.allSatisfy { $0.repKm == mrIntervalRepKm(paceSecPerKm: 300) })   // 구조는 그대로(4분 거리)
    }
}
