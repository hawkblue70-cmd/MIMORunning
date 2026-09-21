import Testing
import Foundation
@testable import MIMORunning

@Suite("수면 HRV 추세", .korean)
struct MRHRVTrendTests {

    private let cal = Calendar.current

    /// 오늘 자정 기준 offset일 · hour시.
    private func at(day offset: Int, hour: Int, minute: Int = 0) -> Date {
        let base = cal.startOfDay(for: Date())
        let d = cal.date(byAdding: .day, value: offset, to: base)!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
    }

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: Date())!)
    }

    // MARK: 밤 묶기

    @Test func eveningSampleBelongsToNextDay() {
        let nights = mrHRVNightMedians(samples: [(at(day: -1, hour: 22), 40)])
        #expect(nights.count == 1)
        #expect(nights[0].date == day(0))
        #expect(nights[0].value == 40)
    }

    @Test func morningSampleBelongsToSameDay() {
        let nights = mrHRVNightMedians(samples: [(at(day: 0, hour: 6), 35)])
        #expect(nights.count == 1)
        #expect(nights[0].date == day(0))
    }

    @Test func daytimeAndNoiseSamplesAreDropped() {
        let nights = mrHRVNightMedians(samples: [
            (at(day: 0, hour: 13), 50),   // 12~15시: 낮 샘플
            (at(day: 0, hour: 3), 8),     // 10ms 미만: 노이즈
        ])
        #expect(nights.isEmpty)
        // 경계: 정확히 10ms는 남긴다
        #expect(mrHRVNightMedians(samples: [(at(day: 0, hour: 3), 10)]).count == 1)
    }

    @Test func nightValueIsMedianOfItsSamples() {
        let nights = mrHRVNightMedians(samples: [
            (at(day: -1, hour: 23), 20), (at(day: 0, hour: 2), 60), (at(day: 0, hour: 5), 30),
        ])
        #expect(nights.count == 1)
        #expect(nights[0].value == 30)
    }

    @Test func nightsAreSortedAscending() {
        let nights = mrHRVNightMedians(samples: [(at(day: 0, hour: 4), 30), (at(day: -3, hour: 4), 31)])
        #expect(nights.map(\.date) == [day(-3), day(0)])
    }

    // MARK: 추세

    /// 4주(−34…−7)는 base, 7일(−6…0)은 recent 값으로 채운 밤 시계열.
    private func series(base: Double, recent: Double,
                        baseJitter: [Double] = [], recentJitter: [Double] = []) -> [(date: Date, value: Double)] {
        var out: [(date: Date, value: Double)] = []
        for i in 0..<28 {
            let j = baseJitter.isEmpty ? 0 : baseJitter[i % baseJitter.count]
            out.append((day(-34 + i), base + j))
        }
        for i in 0..<7 {
            let j = recentJitter.isEmpty ? 0 : recentJitter[i % recentJitter.count]
            out.append((day(-6 + i), recent + j))
        }
        return out
    }

    @Test func aboveWhenSevenDayMeanExceedsBaselinePlusHalfSD() {
        // SD 하한 = 기준선 10% = 3ms → 경계 31.5. 37은 위.
        let t = mrHRVTrend(nights: series(base: 30, recent: 37), asOf: Date())
        #expect(t?.state == .above)
        #expect(t?.isVolatile == false)
        #expect(t?.isReadyHigh == true)
        #expect(t?.sevenDayNights == 7)
        #expect(t?.baselineNights == 28)
    }

    @Test func belowWhenSevenDayMeanUnderBaselineMinusHalfSD() {
        let t = mrHRVTrend(nights: series(base: 30, recent: 25), asOf: Date())
        #expect(t?.state == .below)
        #expect(t?.isSuppressed == true)
    }

    @Test func withinWhenInsideHalfSDBand() {
        let t = mrHRVTrend(nights: series(base: 30, recent: 31), asOf: Date())
        #expect(t?.state == .within)
        #expect(t?.isReadyHigh == false)
        #expect(t?.isSuppressed == false)
    }

    @Test func nilWhenFewerThanFourRecentNights() {
        var s = series(base: 30, recent: 37)
        s.removeAll { $0.date >= day(-3) }   // 최근 7일 중 −6…−4의 3밤만 남긴다
        #expect(mrHRVTrend(nights: s, asOf: Date()) == nil)
        // 경계: 4밤(−6…−3)이면 성립
        var s4 = series(base: 30, recent: 37)
        s4.removeAll { $0.date >= day(-2) }
        #expect(mrHRVTrend(nights: s4, asOf: Date()) != nil)
    }

    @Test func nilWhenFewerThanFourteenBaselineNights() {
        let s = series(base: 30, recent: 37).filter { $0.date >= day(-19) }   // 4주 창 13밤
        #expect(mrHRVTrend(nights: s, asOf: Date()) == nil)
    }

    @Test func volatileWhenRecentCVExceedsBaselineCVByHalf() {
        // 4주 CV ≈ 0.034(±1), 7일 CV ≈ 0.23(±7, 마지막 밤 0 → 평균 정확히 30) → 불안정. 평균은 기준선과 같아 within.
        let t = mrHRVTrend(nights: series(base: 30, recent: 30, baseJitter: [1, -1],
                                          recentJitter: [7, -7, 7, -7, 7, -7, 0]),
                           asOf: Date())
        #expect(t?.state == .within)
        #expect(t?.isVolatile == true)
        #expect(t?.isSuppressed == true)
    }

    @Test func windowsFollowAsOfNotToday() {
        // asOf = 10일 전이면 그 시점의 7일 창(−16…−10)은 4주 구간 값(30)이고, 최근 7일(37)은 보지 않는다.
        // 4주 창(−44…−17)에는 −34…−17의 18밤이 들어간다.
        let t = mrHRVTrend(nights: series(base: 30, recent: 37), asOf: day(-10))
        #expect(t?.sevenDayMean == 30)
        #expect(t?.sevenDayNights == 7)
        #expect(t?.baselineNights == 18)
        #expect(t?.state == .within)
    }

    @Test func baselineWindowExcludesRecentSeven() {
        // 4주 창에 최근 7일이 섞이면 기준선이 올라가 above가 흔들린다 — 28밤만 세는지 확인
        let t = mrHRVTrend(nights: series(base: 30, recent: 60), asOf: Date())
        #expect(t?.baseline == 30)
        #expect(t?.sevenDayMean == 60)
    }

    // MARK: 14일 고강도 집계 (조언 큐용)

    private func run(daysAgo: Int, hr: Double?, interval: Bool = false) -> MRWorkout {
        MRWorkout(start: day(-daysAgo).addingTimeInterval(7 * 3600), durationMin: 50, distanceKm: 8,
                  hrAvg: hr, hrMax: 170, tempC: 15, humidity: nil, indoor: false, isInterval: interval)
    }

    @Test func hardCountUsesIntervalAndLT1() {
        var phys = MRPhysiology()
        phys.lt1HR = MRInference(value: 150, confidence: .high, basis: [])
        let runs = [run(daysAgo: 1, hr: 140), run(daysAgo: 3, hr: 155), run(daysAgo: 5, hr: 140, interval: true),
                    run(daysAgo: 20, hr: 160)]   // 14일 밖
        let c = mrRecentHardRunCount(runs: runs, phys: phys, heatHR: MRHeatHRModel(), days: 14, asOf: Date())
        #expect(c.hard == 2)
        #expect(c.total == 3)
    }

    @Test func hardCountWithoutLT1CountsIntervalsOnly() {
        let runs = [run(daysAgo: 1, hr: 170), run(daysAgo: 3, hr: 140, interval: true)]
        let c = mrRecentHardRunCount(runs: runs, phys: MRPhysiology(), heatHR: MRHeatHRModel(), days: 14, asOf: Date())
        #expect(c.hard == 1)
        #expect(c.total == 2)
    }
}
