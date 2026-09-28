import Testing
import Foundation
@testable import MIMORunning

@Suite("스냅샷 포인트 칸", .korean)
struct MRPlanPointSnapshotTests {

    private let mon = Date(timeIntervalSince1970: 1_791_000_000)
    private let pt = MRPlanPoint(kind: .speed, totalKm: 7.2, reps: 4, repKm: 1, sustainedKm: nil, paceSecPerKm: 300)

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
        // 양은 스냅샷 자신의 주간(40)으로: 40×0.08=3.2 → 3회, 총 6.8 · 이지 (40−16−6.8)/2 = 8.6
        #expect(r.weeks[2].point?.reps == 3)
        #expect(r.weeks[2].breakdown == "롱런 16km + 이지 8.6km × 2회")
    }

    @Test func alreadyFilledOrUnparsableWeeksAreLeftAlone() {
        let thisMon = wk(0)
        let r = mrFillSnapshotPoints(
            snapshot: [snapWeek(1, point: pt), snapWeek(2, breakdown: "롱런 16km + 이지 3회")],
            live: [liveWeek(1, point: pt), liveWeek(2, point: pt)],
            thisMonday: thisMon, raceDistanceM: MRDistance.dH)
        #expect(r.filled == 0)
        #expect(r.weeks[1].point == nil)
    }
}
