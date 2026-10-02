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

    /// 1월에 +5 오르는 계절 곡선(실기기에서 본 겨울 상승 모양)
    private func season(_ ago: Int) -> Double {
        let m = Double(cal.component(.month, from: day(-ago)))
        return 2.5 * (1 + cos((m - 1) / 12 * 2 * .pi))
    }

    @Test func downTrendYearOverYear() {
        // 2년 넘게 연 6bpm씩 하락 + 계절 곡선
        let samples = daily(from: 760) { ago in 58 + 6 * Double(ago) / 365 + self.season(ago) }
        let t = mrRestingHRTrend(samples: samples, asOf: now)
        #expect(t?.direction == .down)
        #expect(abs((t?.yearChange ?? 0) + 6) < 0.8)
        #expect(t?.sentence?.contains("낮아지는 추세") == true)
        #expect(t?.meaning?.contains("4~6bpm") == true)
        #expect(t?.rolling.isEmpty == false)
    }

    @Test func upTrendHasMeaning() {
        let samples = daily(from: 760) { ago in 62 - 4 * Double(ago) / 365 }
        let t = mrRestingHRTrend(samples: samples, asOf: now)
        #expect(t?.direction == .up)
        #expect(t?.meaning?.contains("2~9bpm") == true)
    }

    /// 계절 흔들림만 있을 때 — 지금이 몇 월이든 추세가 없어야 한다(직선 회귀는 여기서 ±5bpm 오판했다).
    @Test func seasonalSwingIsFlatInAnyMonth() {
        for monthsBack in 0..<12 {
            let asOf = cal.date(byAdding: .month, value: -monthsBack, to: now)!
            let samples = daily(from: 1100) { ago in 58 + self.season(ago) }
            let t = mrRestingHRTrend(samples: samples, asOf: asOf)
            #expect(t?.direction == .flat, "asOf \(monthsBack)개월 전")
            #expect(abs(t?.yearChange ?? 99) < 0.5)
        }
    }

    @Test func noTrendUnderTwoYears() {
        // 13개월뿐 — 선은 있지만 같은 달 짝(6개) 부족 → 문장·뜻 없음
        let samples = daily(from: 400) { _ in 58 }
        let t = mrRestingHRTrend(samples: samples, asOf: now)
        #expect(t != nil)
        #expect(t?.yearChange == nil)
        #expect(t?.sentence == nil)
        #expect(t?.meaning == nil)
    }

    @Test func nilWhenTooFewMonths() {
        let samples = daily(from: 50) { _ in 58 }
        #expect(mrRestingHRTrend(samples: samples, asOf: now) == nil)
    }

    @Test func sparseMonthsAreDropped() {
        // 매주 1개뿐 — 달 표본 10일 미만 → 추세 없음
        let samples = stride(from: 300, through: 0, by: -7).map { (day(-$0), 58.0) }
        #expect(mrRestingHRTrend(samples: samples, asOf: now) == nil)
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
