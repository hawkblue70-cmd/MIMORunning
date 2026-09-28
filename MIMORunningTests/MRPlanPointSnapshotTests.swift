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
}
