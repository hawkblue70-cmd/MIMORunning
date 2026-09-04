import XCTest
@testable import MIMORunning

final class MRIntensityTimeTests: XCTestCase {

    // MARK: - Helpers

    /// z4Upper: Zone 4 중 AT2(HRR 85%) 이상 체류 초. nil이면 분할 정보 없는 구버전 존.
    private func zones(_ secs: [Double], z4Upper: Double? = nil, at2: Int = 153) -> [HRZoneData] {
        precondition(secs.count == 5)
        let total = secs.reduce(0, +)
        return secs.enumerated().map { i, s in
            HRZoneData(id: i + 1, name: "Z\(i + 1)", minBPM: 0, maxBPM: 0,
                       seconds: s, fraction: total > 0 ? s / total : 0,
                       splitBPM: (i == 3 && z4Upper != nil) ? at2 : nil,
                       upperSeconds: i == 3 ? z4Upper : nil)
        }
    }

    private func run(_ date: Date, hasHR: Bool = true, zones: [HRZoneData]?) -> MRIntensityTime.RunInput {
        MRIntensityTime.RunInput(id: UUID(), date: date, hasHR: hasHR, zones: zones)
    }

    private var cal: Calendar { MRIntensityTime.isoCalendar }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 7))!
    }

    // MARK: - buckets(for:)

    func testBucketsAllMedium_zone4GoesToMid() {
        let b = MRIntensityTime.buckets(for: zones([60, 120, 300, 200, 100]), policy: .allMedium)
        XCTAssertEqual(b.lowSec,  180)
        XCTAssertEqual(b.midSec,  500)
        XCTAssertEqual(b.highSec, 100)
        XCTAssertEqual(b.totalSec, 780)
    }

    func testBucketsAT2Split_usesStoredUpperSeconds() {
        // Zone4 200초 중 AT2 이상 70초 → 고강도 = 70 + Z5 100
        let b = MRIntensityTime.buckets(for: zones([60, 120, 300, 200, 100], z4Upper: 70), policy: .at2Split)
        XCTAssertEqual(b.lowSec,  180)
        XCTAssertEqual(b.midSec,  430)
        XCTAssertEqual(b.highSec, 170)
    }

    func testBucketsAT2Split_withoutSplitInfoFallsBackToAllMedium() {
        let b = MRIntensityTime.buckets(for: zones([60, 120, 300, 200, 100]), policy: .at2Split)
        XCTAssertEqual(b.midSec,  500)
        XCTAssertEqual(b.highSec, 100)
    }

    func testBucketsAT2Split_upperClampedToZone4() {
        let b = MRIntensityTime.buckets(for: zones([0, 0, 0, 100, 0], z4Upper: 500), policy: .at2Split)
        XCTAssertEqual(b.midSec, 0)
        XCTAssertEqual(b.highSec, 100)
    }

    func testHasAT2Split() {
        XCTAssertTrue(MRIntensityTime.hasAT2Split(zones([1, 1, 1, 1, 1], z4Upper: 0)))
        XCTAssertFalse(MRIntensityTime.hasAT2Split(zones([1, 1, 1, 1, 1])))
        XCTAssertFalse(MRIntensityTime.hasAT2Split([]))
    }

    func testBucketsMissingZoneIdsCountAsZero() {
        // Zone 5만 있는 배열 — 나머지 존은 0으로 처리
        let z = [HRZoneData(id: 5, name: "Z5", minBPM: 0, maxBPM: 0, seconds: 90, fraction: 1)]
        let b = MRIntensityTime.buckets(for: z, policy: .allMedium)
        XCTAssertEqual(b.lowSec, 0); XCTAssertEqual(b.midSec, 0); XCTAssertEqual(b.highSec, 90)
    }

    // MARK: - aggregate

    func testAggregateSumsTimeAcrossRunsAndExcludesMissing() {
        let d = day(2026, 9, 1)
        let runs = [
            run(d, zones: zones([600, 600, 0, 0, 0])),        // 저강도 20분
            run(d, zones: zones([0, 0, 1200, 600, 0])),       // 중간 30분
            run(d, zones: zones([0, 0, 0, 0, 300])),          // 고강도 5분
            run(d, hasHR: true,  zones: nil),                 // 존 미계산
            run(d, hasHR: false, zones: []),                  // 심박 없음
        ]
        let r = MRIntensityTime.aggregate(runs: runs, policy: .allMedium)
        XCTAssertEqual(r.runsTotal, 5)
        XCTAssertEqual(r.runsWithZones, 3)
        XCTAssertEqual(r.runsZonesMissing.count, 1)
        XCTAssertEqual(r.runsNoHR.count, 1)
        XCTAssertEqual(r.buckets.lowSec,  1200)
        XCTAssertEqual(r.buckets.midSec,  1800)
        XCTAssertEqual(r.buckets.highSec, 300)
        XCTAssertEqual(r.buckets.lowFrac, 1200.0 / 3300.0, accuracy: 1e-9)
    }

    func testAggregateIsTimeWeightedNotRunCounted() {
        // 회차로는 저강도 1 : 중간 2 이지만 시간으로는 저강도가 압도
        let d = day(2026, 9, 1)
        let runs = [
            run(d, zones: zones([3000, 3000, 0, 0, 0])),   // 100분 저강도
            run(d, zones: zones([0, 0, 300, 0, 0])),       // 5분 중간
            run(d, zones: zones([0, 0, 300, 0, 0])),       // 5분 중간
        ]
        let r = MRIntensityTime.aggregate(runs: runs, policy: .allMedium)
        XCTAssertEqual(r.buckets.lowFrac, 6000.0 / 6600.0, accuracy: 1e-9)
    }

    func testAggregateEmpty() {
        let r = MRIntensityTime.aggregate(runs: [], policy: .allMedium)
        XCTAssertEqual(r.runsTotal, 0)
        XCTAssertEqual(r.buckets.totalSec, 0)
        XCTAssertEqual(r.buckets.lowFrac, 0)
    }

    // MARK: - 주 단위 저강도 비율 (K-8 참고)

    func testWeeklyLowFractionsAndSummary() {
        let anchor = day(2026, 9, 3)
        let runs = [
            run(day(2026, 9, 1),  zones: zones([300, 0, 700, 0, 0])),      // W36 30% (진행중)
            run(day(2026, 8, 26), zones: zones([220, 0, 780, 0, 0])),      // W35 22%
            run(day(2026, 8, 19), zones: zones([150, 0, 850, 0, 0])),      // W34 15%
            // W33 러닝 없음
            run(day(2026, 8, 5),  hasHR: true, zones: nil),                // W32 존 없음
        ]
        let w = MRIntensityTime.weeklyLowFractions(runs: runs, anchor: anchor, weeks: 5, policy: .at2Split, now: anchor)
        XCTAssertEqual(w.count, 5)
        XCTAssertEqual(w.map(\.shortLabel), ["W36", "W35", "W34", "W33", "W32"])
        XCTAssertTrue(w[0].inProgress)
        XCTAssertEqual(w[0].lowFrac!, 0.30, accuracy: 1e-9)
        XCTAssertEqual(w[1].lowFrac!, 0.22, accuracy: 1e-9)
        XCTAssertNil(w[3].lowFrac); XCTAssertEqual(w[3].runs, 0)
        XCTAssertNil(w[4].lowFrac); XCTAssertEqual(w[4].runs, 1)

        let sm = MRIntensityTime.summary(of: w)!
        XCTAssertEqual(sm.count, 2)                       // 진행 중 W36, 데이터 없는 W33·W32 제외
        XCTAssertEqual(sm.median, 0.185, accuracy: 1e-9)
        XCTAssertEqual(sm.min, 0.15, accuracy: 1e-9)
        XCTAssertEqual(sm.max, 0.22, accuracy: 1e-9)
    }

    func testSummaryNilWhenOnlyInProgressWeek() {
        let anchor = day(2026, 9, 3)
        let w = MRIntensityTime.weeklyLowFractions(
            runs: [run(day(2026, 9, 1), zones: zones([1, 1, 1, 1, 1], z4Upper: 0))],
            anchor: anchor, weeks: 2, policy: .at2Split, now: anchor)
        XCTAssertNil(MRIntensityTime.summary(of: w))
    }
}
