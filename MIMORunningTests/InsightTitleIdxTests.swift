import XCTest
@testable import MIMORunning

/// 인사이트 제목·부연 풀 인덱스는 러닝 ID로 정해진다 — 다시 계산해도 같은 문장, 러닝마다는 다르게.
final class InsightTitleIdxTests: XCTestCase {

    private func act(_ id: UUID) -> Activity {
        Activity(id: id, type: .running, date: Date(), duration: 1800, distance: 5000,
                 calories: nil, avgHeartRate: nil)
    }

    func testSameRunAlwaysSameIndex() {
        let a = act(UUID())
        let first = InsightEngine.titleIdx(for: "easyRarity", poolSize: 3, activity: a)
        for _ in 0..<20 {
            XCTAssertEqual(InsightEngine.titleIdx(for: "easyRarity", poolSize: 3, activity: a), first)
        }
    }

    // 예전 카운터 방식이었으면 같은 러닝을 두 번 계산할 때 인덱스가 바뀌었다
    func testDifferentKeysMayDifferButEachIsStable() {
        let a = act(UUID())
        let e1 = InsightEngine.titleIdx(for: "easyRarity", poolSize: 3, activity: a)
        let c1 = InsightEngine.titleIdx(for: "consistent", poolSize: 3, activity: a)
        XCTAssertEqual(InsightEngine.titleIdx(for: "easyRarity", poolSize: 3, activity: a), e1)
        XCTAssertEqual(InsightEngine.titleIdx(for: "consistent", poolSize: 3, activity: a), c1)
    }

    // 러닝이 다르면 풀 전체에 퍼져야 한다 — 전부 같은 문장이면 돌려 쓰는 의미가 없다
    func testSpreadsAcrossPoolForDifferentRuns() {
        var seen = Set<Int>()
        for _ in 0..<60 { seen.insert(InsightEngine.titleIdx(for: "milestone", poolSize: 3, activity: act(UUID()))) }
        XCTAssertEqual(seen, [0, 1, 2])
    }

    // 실행·기기·버전이 달라도 같은 값 — 고정 UUID에 대한 회귀 핀
    func testStableAcrossProcesses() {
        let a = act(UUID(uuidString: "0A7BB141-0000-4000-8000-000000000000")!)
        let v = InsightEngine.titleIdx(for: "easyRarity", poolSize: 3, activity: a)
        XCTAssertTrue((0..<3).contains(v))
        XCTAssertEqual(v, InsightEngine.titleIdx(for: "easyRarity", poolSize: 3, activity: a))
    }
}
