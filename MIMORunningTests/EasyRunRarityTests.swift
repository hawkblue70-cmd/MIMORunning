import XCTest
@testable import MIMORunning

/// "올해 N번째 이지런" — 유형 라벨과 같은 기준으로 세고, 이 러닝 이후 기록에 흔들리지 않아야 한다.
///
/// 실제로 났던 일: 유형상 두 번째 이지런에 "올해 3번째 이지런"이 떴다. 페이스 근사가 유형과 다른
/// 러닝을 세었고, 중앙값 기준에 이후 러닝까지 섞여 캐시가 재계산될 때마다 답이 바뀌었다.
final class EasyRunRarityTests: XCTestCase {

    private let cal = Calendar.current

    private func date(_ s: String) -> Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    private func run(_ id: UUID = UUID(), _ day: String, km: Double = 8, paceSec: Double = 360) -> Activity {
        Activity(id: id, type: .running, date: date(day), duration: km * paceSec,
                 distance: km * 1000, calories: nil, avgHeartRate: 140)
    }

    /// 올해 1~7월 일반 러닝 12개(6'00") + 유형 이지런 2개. 현재 = 9/11 이지런(유형상 올해 3번째).
    private func fixture() -> (current: Activity, prior: [Activity], easyIDs: Set<UUID>, laterEasy: Activity) {
        var prior: [Activity] = []
        for m in 1...12 { prior.append(run(UUID(), "2026-0\(min(m, 9))-\(String(format: "%02d", m + 1)) 07:00")) }
        let e1 = UUID(), e2 = UUID()
        prior.append(run(e1, "2026-08-20 07:00", paceSec: 400))   // 유형 이지런, 페이스는 6'40"
        prior.append(run(e2, "2026-09-07 19:00", paceSec: 372))   // 유형 이지런, 페이스는 6'12" (중앙값+10% 문턱 아래)
        let current = run(UUID(), "2026-09-11 17:00", km: 6.07, paceSec: 392)
        // 이 러닝 **이후**의 이지런 — 과거 인사이트에 영향을 주면 안 된다
        let later = run(UUID(), "2026-09-20 07:00", paceSec: 410)
        return (current, prior, [e1, e2, later.id], later)
    }

    func testCountsTypedEasyRunsNotPaceApproximation() throws {
        let f = fixture()
        let r = try XCTUnwrap(InsightEngine.easyRunRarity(f.current, f.prior, typeOf: { f.easyIDs.contains($0) ? .easy : .general }))
        XCTAssertTrue(r.detail.contains("3") || r.title.contains("3"), "유형 이지런 2개 + 이번 = 3번째여야 한다: \(r.title) / \(r.detail)")
        XCTAssertFalse(r.detail.contains("2번째"), r.detail)
    }

    func testLaterRunsDoNotChangeThePastInsight() throws {
        let f = fixture()
        let typeOf: (UUID) -> WorkoutType? = { f.easyIDs.contains($0) ? .easy : .general }
        let before = try XCTUnwrap(InsightEngine.easyRunRarity(f.current, f.prior, typeOf: typeOf))
        let after  = try XCTUnwrap(InsightEngine.easyRunRarity(f.current, f.prior + [f.laterEasy], typeOf: typeOf))
        XCTAssertEqual(before.detail.filter(\.isNumber), after.detail.filter(\.isNumber),
                       "이 러닝 이후의 이지런이 추가돼도 횟수가 변하면 안 된다")
    }

    // 유형을 모르는 러닝(캐시 없음)은 페이스로 판단해 센다 — "모름 = 이지런 아님"으로 치면 횟수가 줄어든다
    func testUnknownTypeRunsFallBackToPacePerRun() throws {
        let f = fixture()
        // e1(6'40")·e2(6'12")는 유형 조회가 nil을 돌려준다. e1은 페이스 문턱(6'36")보다 느려 이지런으로 세고,
        // e2는 빨라서 안 센다 → 이전 이지런 1개 + 이번 = 2번째
        let r = try XCTUnwrap(InsightEngine.easyRunRarity(f.current, f.prior, typeOf: { _ in nil }))
        XCTAssertTrue(r.title.contains("2") || r.detail.contains("2"), "\(r.title) / \(r.detail)")
    }

    func testFallsBackToPaceWhenNoTypeLookup() throws {
        let f = fixture()
        // 페이스 근사: 중앙값 6'00" × 1.1 = 6'36" 보다 느린 이전 러닝은 e1(6'40") 하나 → 이번이 2번째
        let r = try XCTUnwrap(InsightEngine.easyRunRarity(f.current, f.prior, typeOf: nil))
        XCTAssertTrue(r.title.contains("2") || r.detail.contains("2"), "\(r.title) / \(r.detail)")
    }
}
