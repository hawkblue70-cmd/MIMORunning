import XCTest
import SwiftData
@testable import MIMORunning

@MainActor
final class MRReadinessSnapshotTests: XCTestCase {
    private func ctx() throws -> ModelContext {
        let c = try ModelContainer(for: MRReadinessSnapshot.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    func testKeyFormat() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let d = cal.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 7))!
        XCTAssertEqual(MRReadinessSnapshot.key(for: d, calendar: cal), "2026-03-05")
    }

    func testUpsertSameDayKeepsOneRowWithLatest() throws {
        let c = try ctx()
        let t1 = Date()
        let r1 = MRReadiness(level: .go, reasons: [], hrvPending: false, why: "첫째", data: ["a"])
        MRReadinessSnapshotStore.upsert(r1, at: t1, context: c)
        let r2 = MRReadiness(level: .rest, reasons: [], hrvPending: false, why: "둘째", data: ["b", "c"])
        MRReadinessSnapshotStore.upsert(r2, at: t1.addingTimeInterval(5), context: c)
        let all = try c.fetch(FetchDescriptor<MRReadinessSnapshot>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].level, "rest")
        XCTAssertEqual(all[0].why, "둘째")
        XCTAssertEqual(all[0].data, "b · c")
        XCTAssertEqual(all[0].computedAt, t1.addingTimeInterval(5))
        XCTAssertNotNil(MRReadinessSnapshotStore.fetch(dateKey: MRReadinessSnapshot.key(for: t1), context: c))
    }

    func testUpsertSameContentDoesNotBumpComputedAt() throws {
        let c = try ctx()
        let t1 = Date()
        let r = MRReadiness(level: .go, reasons: [], hrvPending: false, why: "첫째", data: ["a"])
        MRReadinessSnapshotStore.upsert(r, at: t1, context: c)
        MRReadinessSnapshotStore.upsert(r, at: t1.addingTimeInterval(600), context: c)
        let key = MRReadinessSnapshot.key(for: t1)
        XCTAssertEqual(MRReadinessSnapshotStore.fetch(dateKey: key, context: c)?.computedAt, t1)
        let r2 = MRReadiness(level: .go, reasons: [], hrvPending: false, why: "달라짐", data: ["a"])
        MRReadinessSnapshotStore.upsert(r2, at: t1.addingTimeInterval(900), context: c)
        let s = MRReadinessSnapshotStore.fetch(dateKey: key, context: c)
        XCTAssertEqual(s?.computedAt, t1.addingTimeInterval(900))
        XCTAssertEqual(s?.why, "달라짐")
    }
}
