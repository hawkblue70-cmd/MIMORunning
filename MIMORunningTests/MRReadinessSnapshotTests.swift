import XCTest
import SwiftData
@testable import MIMORunning

@MainActor
final class MRReadinessSnapshotTests: XCTestCase {
    private func ctx() throws -> ModelContext {
        let c = try ModelContainer(for: MRReadinessDaySnapshot.self, MRReadinessSnapshot.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    func testKeyFormat() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let d = cal.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 7))!
        XCTAssertEqual(MRReadinessDaySnapshot.key(for: d, calendar: cal), "2026-03-05")
    }

    func testUpsertSameDayKeepsOneRowWithLatest() throws {
        let c = try ctx()
        let t1 = Date()
        let r1 = MRReadiness(level: .go, reasons: [], hrvPending: false, why: "첫째", data: ["a"])
        MRReadinessSnapshotStore.upsert(r1, at: t1, context: c)
        let r2 = MRReadiness(level: .rest, reasons: [], hrvPending: false, why: "둘째", data: ["b", "c"])
        MRReadinessSnapshotStore.upsert(r2, at: t1.addingTimeInterval(5), context: c)
        let all = try c.fetch(FetchDescriptor<MRReadinessDaySnapshot>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].level, "rest")
        XCTAssertEqual(all[0].why, "둘째")
        XCTAssertEqual(all[0].data, "b · c")
        XCTAssertEqual(all[0].computedAt, t1.addingTimeInterval(5))
        XCTAssertNotNil(MRReadinessSnapshotStore.fetch(dateKey: MRReadinessDaySnapshot.key(for: t1), context: c))
    }

    func testUpsertSameContentDoesNotBumpComputedAt() throws {
        let c = try ctx()
        let t1 = Date()
        let r = MRReadiness(level: .go, reasons: [], hrvPending: false, why: "첫째", data: ["a"])
        MRReadinessSnapshotStore.upsert(r, at: t1, context: c)
        MRReadinessSnapshotStore.upsert(r, at: t1.addingTimeInterval(600), context: c)
        let key = MRReadinessDaySnapshot.key(for: t1)
        XCTAssertEqual(MRReadinessSnapshotStore.fetch(dateKey: key, context: c)?.computedAt, t1)
        let r2 = MRReadiness(level: .go, reasons: [], hrvPending: false, why: "달라짐", data: ["a"])
        MRReadinessSnapshotStore.upsert(r2, at: t1.addingTimeInterval(900), context: c)
        let s = MRReadinessSnapshotStore.fetch(dateKey: key, context: c)
        XCTAssertEqual(s?.computedAt, t1.addingTimeInterval(900))
        XCTAssertEqual(s?.why, "달라짐")
    }

    // 옛 iCloud 기록 → 기기 안 기록으로 옮기고 옛 기록은 지운다(2026-10-19)
    func testMigrateLegacyMovesAndDeletes() throws {
        let c = try ctx()
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let old = MRReadinessSnapshot(dateKey: "2026-10-16")
        old.level = "easy"; old.why = "옛"; old.data = "HRV 40ms"; old.computedAt = t
        old.easyCapHR = 142; old.easyPaceSec = 390; old.hrvPending = true
        c.insert(old)
        try c.save()

        XCTAssertEqual(MRReadinessSnapshotStore.migrateLegacy(context: c), 1)
        XCTAssertEqual(try c.fetch(FetchDescriptor<MRReadinessSnapshot>()).count, 0)
        let moved = try XCTUnwrap(MRReadinessSnapshotStore.fetch(dateKey: "2026-10-16", context: c))
        XCTAssertEqual(moved.level, "easy")
        XCTAssertEqual(moved.data, "HRV 40ms")
        XCTAssertEqual(moved.computedAt, t)
        XCTAssertEqual(moved.easyCapHR, 142)
        XCTAssertEqual(moved.easyPaceSec, 390)
        XCTAssertTrue(moved.hrvPending)
        // 다시 돌려도 옮길 게 없다
        XCTAssertEqual(MRReadinessSnapshotStore.migrateLegacy(context: c), 0)
    }

    func testMigrateLegacyKeepsExistingLocal() throws {
        let c = try ctx()
        let r = MRReadiness(level: .go, reasons: [], hrvPending: false, why: "기기", data: ["a"])
        let t = Date()
        MRReadinessSnapshotStore.upsert(r, at: t, context: c)
        let key = MRReadinessDaySnapshot.key(for: t)
        let old = MRReadinessSnapshot(dateKey: key)
        old.why = "옛"
        c.insert(old)
        try c.save()

        XCTAssertEqual(MRReadinessSnapshotStore.migrateLegacy(context: c), 1)
        XCTAssertEqual(try c.fetch(FetchDescriptor<MRReadinessDaySnapshot>()).count, 1)
        XCTAssertEqual(MRReadinessSnapshotStore.fetch(dateKey: key, context: c)?.why, "기기")
        XCTAssertEqual(try c.fetch(FetchDescriptor<MRReadinessSnapshot>()).count, 0)
    }
}
