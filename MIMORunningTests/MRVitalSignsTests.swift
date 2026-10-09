import Testing
import Foundation
@testable import MIMORunning

@Suite("밤 활력 징후", .korean)
struct MRVitalSignsTests {

    private let cal = Calendar.current
    private let now: Date = {
        let c = Calendar.current
        return c.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
    }()

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: now)!)
    }

    /// 30밤 평소값(±jitter) + 마지막 `recent.count`밤은 recent 값(마지막이 오늘 키)
    private func series(base: Double, jitter: Double, recent: [Double]) -> [(date: Date, value: Double)] {
        var out: [(date: Date, value: Double)] = []
        for i in 0..<30 { out.append((day(-30 - recent.count + 1 + i), base + (i % 2 == 0 ? jitter : -jitter))) }
        for (i, v) in recent.enumerated() { out.append((day(-recent.count + 1 + i), v)) }
        return out
    }

    private func steadyRuns() -> [MRWorkout] {
        [34, 32, 29, 27, 25, 22, 20, 18, 15, 13, 11, 8, 6, 3, 1].map {
            MRWorkout(start: day(-$0).addingTimeInterval(7 * 3600), durationMin: 50, distanceKm: 8,
                      hrAvg: 140, hrMax: 170, tempC: 15, humidity: nil, indoor: false, isInterval: false)
        }
    }

    // MARK: 판정

    @Test func noSignalInUsualRange() {
        let resp = series(base: 14.5, jitter: 0.3, recent: [14.8])
        let temp = series(base: 34.5, jitter: 0.1, recent: [34.7])
        #expect(mrVitalSignal(respNights: resp, tempNights: temp, asOf: now) == nil)
    }

    @Test func oneNightOneMetricIsEasy() {
        let resp = series(base: 14.5, jitter: 0.3, recent: [17.0])
        let s = mrVitalSignal(respNights: resp, tempNights: [], asOf: now)
        #expect(s?.elevations.count == 1)
        #expect(s?.isRest == false)
    }

    @Test func bothMetricsIsRest() {
        let resp = series(base: 14.5, jitter: 0.3, recent: [17.0])
        let temp = series(base: 34.5, jitter: 0.1, recent: [35.4])
        #expect(mrVitalSignal(respNights: resp, tempNights: temp, asOf: now)?.isRest == true)
    }

    @Test func twoNightsInARowIsRest() {
        let temp = series(base: 34.5, jitter: 0.1, recent: [35.4, 35.5])
        let s = mrVitalSignal(respNights: [], tempNights: temp, asOf: now)
        #expect(s?.elevations.first?.nights == 2)
        #expect(s?.isRest == true)
    }

    @Test func silentWithoutLastNight() {
        // 어젯밤(오늘 키) 값이 없으면 며칠 전 값으로 말하지 않는다
        var resp = series(base: 14.5, jitter: 0.3, recent: [17, 17])
        resp.removeLast()
        #expect(mrVitalSignal(respNights: resp, tempNights: [], asOf: now) == nil)
    }

    @Test func silentUnderFourteenBaselineNights() {
        let resp = Array(series(base: 14.5, jitter: 0.3, recent: [17]).suffix(10))
        #expect(mrVitalSignal(respNights: resp, tempNights: [], asOf: now) == nil)
    }

    @Test func wristTempKeyedByWakeDay() {
        let wake = cal.date(bySettingHour: 6, minute: 30, second: 0, of: day(0))!
        let nap = cal.date(bySettingHour: 16, minute: 0, second: 0, of: day(-1))!
        let n = mrWristTempNights(samples: [(wake, 34.6), (nap, 35.0)])
        #expect(n.count == 1)
        #expect(cal.isDate(n[0].date, inSameDayAs: day(0)))
    }

    // MARK: 아침 제안 — 맨 앞 규칙

    @Test func readinessEasyOnOneElevation() {
        let resp = series(base: 14.5, jitter: 0.3, recent: [17.0])
        let r = mrReadiness(runs: steadyRuns(), phys: MRPhysiology(), heatHR: MRHeatHRModel(), hrvNights: [],
                            planPhase: nil, asOf: now, respNights: resp)
        #expect(r?.level == .easy)
    }

    @Test func readinessRestBeatsRecoveryWeek() {
        // 대회 계획 회복 주(이지)보다 앞 — 둘 다 벗어나면 휴식
        let resp = series(base: 14.5, jitter: 0.3, recent: [17.0])
        let temp = series(base: 34.5, jitter: 0.1, recent: [35.4])
        let r = mrReadiness(runs: steadyRuns(), phys: MRPhysiology(), heatHR: MRHeatHRModel(), hrvNights: [],
                            planPhase: "회복", asOf: now, respNights: resp, tempNights: temp)
        #expect(r?.level == .rest)
    }
}
