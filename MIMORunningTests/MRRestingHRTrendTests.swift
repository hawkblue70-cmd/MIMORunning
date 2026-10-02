import Testing
import Foundation
@testable import MIMORunning

@Suite("안정시 심박 추세", .korean)
struct MRRestingHRTrendTests {

    private let cal = Calendar.current
    private let now = Calendar.current.startOfDay(for: Date())

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: now)!
    }

    /// offset일 전부터 오늘까지 매일 1개, 값은 f(daysAgo).
    private func daily(from offset: Int, _ f: (Int) -> Double) -> [(date: Date, value: Double)] {
        (0...offset).reversed().map { ago in (day(-ago), f(ago)) }
    }

    @Test func beforeRunningBaselineWhenDataExists() {
        // 300일 전 첫 러닝. 그 전 64, 이후 선형으로 57까지
        let samples = daily(from: 400) { ago in ago > 300 ? 64 : 57 + 7 * Double(ago) / 300 }
        let t = mrRestingHRTrend(samples: samples, firstRunDate: day(-300), asOf: now)
        #expect(t != nil)
        #expect(t?.baselineKind == .beforeRunning)
        #expect(t?.baseline == 64)
        #expect((t?.change ?? 0) < -5)
        #expect(t?.sentence(asOf: now)?.contains("러닝을 시작한 뒤") == true)
    }

    @Test func windowStartBaselineWhenNoPreRunData() {
        // 러닝은 표본보다 먼저 시작 — 시작 전 데이터 없음
        let samples = daily(from: 300) { ago in 55 + 5 * Double(ago) / 300 }
        let t = mrRestingHRTrend(samples: samples, firstRunDate: day(-500), asOf: now)
        #expect(t?.baselineKind == .windowStart)
        #expect(t?.sentence(asOf: now)?.contains("개월 전보다") == true)
    }

    @Test func noSentenceWhenFlatOrRising() {
        let flat = daily(from: 300) { _ in 58 }
        #expect(mrRestingHRTrend(samples: flat, firstRunDate: nil, asOf: now)?.sentence(asOf: now) == nil)
        let rising = daily(from: 300) { ago in 55 + 5 * (1 - Double(ago) / 300) }
        let t = mrRestingHRTrend(samples: rising, firstRunDate: nil, asOf: now)
        #expect(t != nil)                      // 선은 보인다
        #expect(t?.sentence(asOf: now) == nil) // 문장은 없다
    }

    @Test func nilWhenTooFewMonths() {
        let samples = daily(from: 50) { _ in 58 }
        #expect(mrRestingHRTrend(samples: samples, firstRunDate: nil, asOf: now) == nil)
    }

    @Test func sparseMonthsAreDropped() {
        // 매주 1개뿐 — 달 표본 10일 미만 → 추세 없음
        let samples = stride(from: 300, through: 0, by: -7).map { (day(-$0), 58.0) }
        #expect(mrRestingHRTrend(samples: samples, firstRunDate: nil, asOf: now) == nil)
    }

    @Test func noBaselineWhenWindowOverlapsRecent() {
        // 150일뿐 — 첫 90일이 최근 90일과 겹침 → 기준 없음, 선만
        let samples = daily(from: 150) { _ in 58 }
        let t = mrRestingHRTrend(samples: samples, firstRunDate: nil, asOf: now)
        #expect(t != nil)
        #expect(t?.baseline == nil)
    }

    // MARK: 단기 상승 구간(로그용)

    @Test func riseEpisodeCountsThreeDayRun() {
        var samples = daily(from: 60) { _ in 55 }
        for ago in [10, 9, 8] { samples[60 - ago].value = 61 }
        let r = mrRestingHRRiseEpisodes(samples: samples, from: day(-30), to: now)
        #expect(r.episodes == 1)
        #expect(r.flaggedDays == 3)
    }

    @Test func twoDayRiseIsNotEpisode() {
        var samples = daily(from: 60) { _ in 55 }
        for ago in [10, 9] { samples[60 - ago].value = 61 }
        let r = mrRestingHRRiseEpisodes(samples: samples, from: day(-30), to: now)
        #expect(r.episodes == 0)
        #expect(r.flaggedDays == 2)
    }
}
