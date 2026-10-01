import Testing
import Foundation
@testable import MIMORunning

@Suite("역치 추정", .korean)
struct MRThresholdTests {

    private let cal = Calendar.current
    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 7) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    private func run(_ start: Date, min: Double, hr: Double?, interval: Bool = false) -> MRWorkout {
        MRWorkout(start: start, durationMin: min, distanceKm: min / 5, hrAvg: hr, hrMax: nil,
                  tempC: nil, humidity: nil, indoor: false, isInterval: interval)
    }
    private func effort(_ start: Date, min: Double) -> MRRaceEffort {
        MRRaceEffort(date: cal.startOfDay(for: start), distanceM: min / 5 * 1000, timeMin: min,
                     timeMinRef: min, tempC: nil, label: "x", isConfirmedRace: false)
    }
    private func estimate(_ asOf: Date, pace: Double) -> MRThresholdEstimate {
        MRThresholdEstimate(asOf: asOf, paceSecPerKm: pace, paceConfidence: .medium,
                            hr: nil, hrConfidence: .none, basis: [])
    }

    @Test func thresholdPaceIsSixtyMinuteRacePace() throws {
        let p = try #require(mrThresholdPace(halfEquivMin: 110))
        #expect(abs(p - 302.3) < 0.5)                      // 10K 298.6 · 하프 312.8 사이
        let h = try #require(mrThresholdPace(halfEquivMin: 60))
        #expect(abs(h - 60 * 60 / 21.0975) < 0.2)          // 하프 60분 = 60분 대회 → 하프 페이스
        #expect(mrThresholdPace(halfEquivMin: 5) == nil)
    }

    @Test func combineHRAgreesWithinFiveBpm() throws {
        let a = try #require(mrCombineThresholdHR(regression: 170, sustained: (172, 3)))
        #expect(a.hr == 171 && a.confidence == .medium)
        #expect(mrCombineThresholdHR(regression: 170, sustained: (180, 3)) == nil)
        let b = try #require(mrCombineThresholdHR(regression: 170, sustained: nil))
        #expect(b.hr == 170 && b.confidence == .low)
        let c = try #require(mrCombineThresholdHR(regression: nil, sustained: (165, 2)))
        #expect(c.hr == 165 && c.confidence == .low)
        #expect(mrCombineThresholdHR(regression: nil, sustained: nil) == nil)
    }

    @Test func hrAtPaceInvertsPaceAtHRWithinDataRange() throws {
        var m = MRHRPaceModel()
        m.ok = true; m.b0 = 60; m.bSpeed = 0.4; m.dataHRMin = 130; m.dataHRMax = 180
        let hr = try #require(m.hrAtPace(300))             // 200 m/min → 60 + 80 = 140
        #expect(abs(hr - 140) < 0.001)
        let back = try #require(m.paceAtHR(hr))
        #expect(abs(back - 300) < 0.001)
        #expect(m.hrAtPace(180) == nil)                    // 193bpm — 학습 상한 위(외삽)
        #expect(m.hrAtPace(600) == nil)                    // 100bpm — 학습 하한 아래
        var bad = m; bad.ok = false
        #expect(bad.hrAtPace(300) == nil)
    }

    @Test func sustainedEffortHRMatchesSameDaySameDuration() throws {
        let asOf = day(2026, 10, 1, 12)
        let d1 = day(2026, 7, 1), d2 = day(2026, 8, 1), d3 = day(2026, 8, 15)
        let d4 = day(2026, 2, 1), d5 = day(2026, 9, 1), d6 = day(2026, 9, 10)
        let runs = [
            run(d1, min: 30.5, hr: 170),                    // ✓ 30분 노력, +1.7%
            run(d2, min: 40, hr: 174),                      // ✓
            run(d3, min: 15, hr: 185),                      // 20분 미만 노력
            run(d4, min: 30, hr: 160),                      // 180일 밖
            run(d5, min: 50, hr: 180, interval: true),      // 인터벌 제외
            run(d6, min: 50, hr: 150),                      // 노력 45분과 +11% — 매칭 안 됨
        ]
        let efforts = [effort(d1, min: 30), effort(d2, min: 40), effort(d3, min: 15),
                       effort(d4, min: 30), effort(d5, min: 50), effort(d6, min: 45)]
        let r = try #require(mrSustainedEffortHR(runs: runs, efforts: efforts, asOf: asOf))
        #expect(r.hr == 172 && r.n == 2)
        #expect(mrSustainedEffortHR(runs: [run(d5, min: 50, hr: 180, interval: true)],
                                    efforts: [effort(d5, min: 50)], asOf: asOf) == nil)
        #expect(mrSustainedEffortHR(runs: runs, efforts: [], asOf: asOf) == nil)
    }

    @Test func trendSentenceOnlyWhenFaster() {
        let a = day(2026, 4, 15), b = day(2026, 10, 1)
        #expect(mrThresholdTrendSentence([estimate(a, pace: 312), estimate(b, pace: 300)]) == "6개월간 12초 빨라졌어요")
        #expect(mrThresholdTrendSentence([estimate(a, pace: 312), estimate(b, pace: 310)]) == nil)   // 2초 — 문턱 미만
        #expect(mrThresholdTrendSentence([estimate(a, pace: 300), estimate(b, pace: 310)]) == nil)   // 느려짐
        #expect(mrThresholdTrendSentence([estimate(b, pace: 300)]) == nil)                           // 점 1개
        #expect(inEnglish { mrThresholdTrendSentence([estimate(a, pace: 312), estimate(b, pace: 300)]) }
                == "12s/km faster over 6 months")
    }
}
