import Testing
import Foundation
@testable import MIMORunning

@Suite("스냅샷 포인트 칸", .korean)
struct MRPlanPointSnapshotTests {

    private let mon = Date(timeIntervalSince1970: 1_791_000_000)
    // 4'00" → 반복 1000m (계산이 깔끔하게)
    private let pt = MRPlanPoint(kind: .speed, totalKm: 7.2, reps: 4, repKm: 1, sustainedKm: nil, paceSecPerKm: 240)

    private func decode(_ json: String) throws -> [MRPlanWeekSummary] {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
        return try d.decode([MRPlanWeekSummary].self, from: Data(json.utf8))
    }

    @Test func oldJSONWithoutPointDecodesAsNil() throws {
        let weeks = try decode(#"[{"idx":1,"monday":1791000000,"phase":"늘리기","longRunKm":14,"weeklyKm":30,"breakdown":"롱런 14km + 이지 5.3km × 3회"}]"#)
        #expect(weeks.count == 1)
        #expect(weeks[0].point == nil)
    }

    @Test func pointRoundTrips() throws {
        let s = MRPlanWeekSummary(idx: 1, monday: mon, phase: "늘리기", longRunKm: 14, weeklyKm: 30,
                                  breakdown: "롱런 14km + 이지 4.4km × 2회", point: pt)
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        let json = String(data: try e.encode([s]), encoding: .utf8)!
        #expect(try decode(json)[0].point == pt)
    }

    @Test func applyingSnapshotUsesSnapshotPointEvenWhenNil() {
        let live = MRPlanWeek(idx: 1, monday: mon, phase: "늘리기", longRunKm: 14, longRunMin: 90, weeklyKm: 30,
                              projectedMin: 110, isNewMax: false, breakdown: "롱런 14km + 이지 4.4km × 2회", point: pt)
        let snapNoPoint = MRPlanWeekSummary(idx: 1, monday: mon, phase: "늘리기", longRunKm: 14, weeklyKm: 30,
                                            breakdown: "롱런 14km + 이지 5.3km × 3회")
        // 이번 주처럼 스냅샷에 포인트가 없으면 라이브 포인트가 새어 들지 않는다
        #expect(MRPlanGovernance.applyingSnapshot([live], snapshot: [snapNoPoint], easyPaceSecPerKm: 400)[0].point == nil)
        let snapWithPoint = MRPlanWeekSummary(idx: 1, monday: mon, phase: "늘리기", longRunKm: 14, weeklyKm: 30,
                                              breakdown: "롱런 14km + 이지 4.4km × 2회", point: pt)
        #expect(MRPlanGovernance.applyingSnapshot([live], snapshot: [snapWithPoint], easyPaceSecPerKm: 400)[0].point == pt)
    }

    private func wk(_ offset: Int) -> Date {
        let cal = Calendar.current
        let thisMon = MRPlanGovernance.weekMonday(of: Date())
        return cal.date(byAdding: .day, value: 7 * offset, to: thisMon)!
    }

    private func liveWeek(_ offset: Int, phase: String = "늘리기", point: MRPlanPoint?) -> MRPlanWeek {
        MRPlanWeek(idx: offset + 5, monday: wk(offset), phase: phase, longRunKm: 16, longRunMin: 100, weeklyKm: 40,
                   projectedMin: 110, isNewMax: false, breakdown: "롱런 16km + 이지 5.7km × 2회", point: point)
    }

    private func snapWeek(_ offset: Int, phase: String = "늘리기", point: MRPlanPoint? = nil,
                          breakdown: String = "롱런 16km + 이지 8km × 3회") -> MRPlanWeekSummary {
        MRPlanWeekSummary(idx: offset + 5, monday: wk(offset), phase: phase, longRunKm: 16, weeklyKm: 40,
                          breakdown: breakdown, point: point)
    }

    @Test func fillsOnlyFutureWeeksWithSamePhase() {
        let thisMon = wk(0)
        let r = mrFillSnapshotPoints(
            snapshot: [snapWeek(-1), snapWeek(0), snapWeek(1), snapWeek(2, phase: "유지")],
            live: [liveWeek(-1, point: pt), liveWeek(0, point: pt), liveWeek(1, point: pt), liveWeek(2, phase: "늘리기", point: pt)],
            thisMonday: thisMon, raceDistanceM: MRDistance.dH)
        #expect(r.filled == 1)
        #expect(r.weeks[0].point == nil)          // 지난 주
        #expect(r.weeks[1].point == nil)          // 이번 주 — 공백
        #expect(r.weeks[2].point?.kind == .speed) // 다음 주
        #expect(r.weeks[3].point == nil)          // 단계가 다르면 건너뜀
        // 양은 스냅샷 자신의 주간(40)으로: 40×0.08=3.2 → 3회, 총 7.0 · 이지 (40−16−7.0)/2 = 8.5
        #expect(r.weeks[2].point?.reps == 3)
        #expect(r.weeks[2].breakdown == "롱런 16km + 이지 8.5km × 2회")
    }

    @Test func existingFuturePointIsRefreshedToCurrentRulesOnce() {
        let thisMon = wk(0)
        // 옛 규칙(회복 0.4km)으로 채운 점: 3회 × 1km, 총 6.8 → 지금 규칙(회복 0.5km) 총 7.0, 이지 (40−16−7)/2 = 8.5
        let old = MRPlanPoint(kind: .speed, totalKm: 6.8, reps: 3, repKm: 1, sustainedKm: nil, paceSecPerKm: 240)
        let past = snapWeek(-1, point: old, breakdown: "롱런 16km + 이지 8.6km × 2회")
        let future = snapWeek(1, point: old, breakdown: "롱런 16km + 이지 8.6km × 2회")
        let r = mrFillSnapshotPoints(snapshot: [past, future], live: [], thisMonday: thisMon, raceDistanceM: MRDistance.dH)
        #expect(r.filled == 1)
        #expect(r.weeks[0].point == old)                          // 지난 주는 그대로
        #expect(abs((r.weeks[1].point?.totalKm ?? 0) - 7.0) < 0.01)
        #expect(r.weeks[1].breakdown == "롱런 16km + 이지 8.5km × 2회")
        // 다시 돌려도 바뀌지 않는다
        let again = mrFillSnapshotPoints(snapshot: r.weeks, live: [], thisMonday: thisMon, raceDistanceM: MRDistance.dH)
        #expect(again.filled == 0)
    }

    @Test func alreadyFilledOrUnparsableWeeksAreLeftAlone() {
        let thisMon = wk(0)
        let current = MRPlanPoint.make(kind: .speed, weeklyKm: 40, longRunKm: 16, raceDistanceM: MRDistance.dH, paceSecPerKm: 240)!
        let r = mrFillSnapshotPoints(
            snapshot: [snapWeek(1, point: current), snapWeek(2, breakdown: "롱런 16km + 이지 3회")],
            live: [liveWeek(1, point: pt), liveWeek(2, point: pt)],
            thisMonday: thisMon, raceDistanceM: MRDistance.dH)
        #expect(r.filled == 0)
        #expect(r.weeks[1].point == nil)
    }

    @Test func existingFuturePointFollowsLiveKindWhenKindRuleChanged() {
        let thisMon = wk(0)
        let old = MRPlanPoint.make(kind: .speed, weeklyKm: 40, longRunKm: 16, raceDistanceM: MRDistance.dH, paceSecPerKm: 240)!
        let tempoLive = MRPlanPoint(kind: .tempo, totalKm: 7, reps: nil, repKm: nil, sustainedKm: 4, paceSecPerKm: 260)
        let r = mrFillSnapshotPoints(snapshot: [snapWeek(1, point: old, breakdown: "롱런 16km + 이지 8.5km × 2회")],
                                     live: [liveWeek(1, point: tempoLive)],
                                     thisMonday: thisMon, raceDistanceM: MRDistance.dH)
        #expect(r.filled == 1)
        #expect(r.weeks[0].point?.kind == .tempo)
        #expect(r.weeks[0].point?.paceSecPerKm == 260)
        // 템포런 40×0.1 = 4km, 총 7 → 이지 (40−16−7)/2 = 8.5 — 문구 그대로
        #expect(r.weeks[0].breakdown == "롱런 16km + 이지 8.5km × 2회")
    }
}
