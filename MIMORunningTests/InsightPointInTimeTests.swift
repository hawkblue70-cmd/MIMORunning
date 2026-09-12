import XCTest
@testable import MIMORunning

/// 인사이트는 그 러닝 **시점**의 기록으로만 계산된다 — 이후 러닝이 과거 인사이트를 바꾸면 안 된다.
///
/// 캐시가 다시 계산될 때(버전 올림·언어 변경·대회 확정) 그 사이 쌓인 러닝이 섞이면
/// "동일 거리 PR"이 나중의 더 빠른 러닝 때문에 사라지고, "이번 주 최장"이 뒤집혔다.
final class InsightPointInTimeTests: XCTestCase {

    private func date(_ s: String) -> Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    private func run(_ day: String, km: Double = 10, paceSec: Double) -> Activity {
        Activity(id: UUID(), type: .running, date: date(day), duration: km * paceSec,
                 distance: km * 1000, calories: nil, avgHeartRate: nil)
    }

    func testLaterFasterRunDoesNotEraseEarlierPR() {
        // 7~8월 매주 10km 6'30" × 10회, 9/1에 6'00" — 그 시점엔 동일 거리 PR
        var history: [Activity] = []
        for w in 0..<10 { history.append(run("2026-0\(w < 5 ? 7 : 8)-\(String(format: "%02d", (w % 5) * 6 + 1)) 07:00", paceSec: 390)) }
        let pr = run("2026-09-01 07:00", paceSec: 360)
        // 이후에 더 빠른 러닝이 추가됨
        let later = run("2026-09-10 07:00", paceSec: 330)

        let before = InsightEngine.compute(activity: pr, history: history + [pr], level: .novice)
        let after  = InsightEngine.compute(activity: pr, history: history + [pr, later], level: .novice)

        XCTAssertEqual(before.theme, .recordImproved, "9/1 시점에는 동일 거리 PR이어야 한다: \(before.title)")
        XCTAssertEqual(after.theme, before.theme, "이후 러닝이 추가돼도 9/1 인사이트는 그대로여야 한다: \(after.title)")
        XCTAssertEqual(after.detail, before.detail)
    }
}
