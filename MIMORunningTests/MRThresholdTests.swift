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
        let d4 = day(2025, 9, 1), d5 = day(2026, 9, 1), d6 = day(2026, 9, 10)
        let runs = [
            run(d1, min: 30.5, hr: 170),                    // ✓ 30분 노력, +1.7%
            run(d2, min: 40, hr: 174),                      // ✓
            run(d3, min: 15, hr: 185),                      // 20분 미만 노력
            run(d4, min: 30, hr: 160),                      // 창(365일) 밖
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

    @Test func updateSentenceOnlyWhenAnchorMadeItFaster() {
        let a = effort(day(2026, 9, 20), min: 50)
        let tenK = MRRaceEffort(date: a.date, distanceM: 10_000, timeMin: 50, timeMinRef: 50,
                                tempC: nil, label: "10K", isConfirmedRace: false)
        #expect(mrThresholdUpdateSentence(anchor: tenK, beforePace: 330, afterPace: 320) == "9월 20일 10K 기록으로 10초 빨라졌어요")
        #expect(mrThresholdUpdateSentence(anchor: tenK, beforePace: 322, afterPace: 320) == nil)   // 2초 — 문턱 미만
        #expect(mrThresholdUpdateSentence(anchor: tenK, beforePace: 310, afterPace: 320) == nil)   // 느려짐
        #expect(mrThresholdUpdateSentence(anchor: tenK, beforePace: nil, afterPace: 320) == nil)   // 첫 기록
        #expect(inEnglish { mrThresholdUpdateSentence(anchor: tenK, beforePace: 330, afterPace: 320) }
                == "10s/km faster after your 10K on Sep 20")
    }

    @Test func anchorIsBestConfirmedRaceWithinTwentyFourMonths() throws {
        let asOf = day(2026, 10, 1, 12)
        func race(_ d: Date, km: Double, min: Double, name: String) -> (MRWorkout, MRThresholdRace) {
            let w = MRWorkout(start: d, durationMin: min, distanceKm: km, hrAvg: nil, hrMax: nil,
                              tempC: nil, humidity: nil, indoor: false, isInterval: false)
            let e = MRRaceEffort(date: Calendar.current.startOfDay(for: d), distanceM: km * 1000, timeMin: min,
                                 timeMinRef: min, tempC: nil, label: mrLabelFor(distanceM: km * 1000), isConfirmedRace: true)
            return (w, MRThresholdRace(effort: e, name: name))
        }
        let a = race(day(2025, 11, 9), km: 10, min: 50, name: "가을 10K")          // ✓ 최고
        let b = race(day(2026, 4, 5), km: MRDistance.dH / 1000, min: 118, name: "봄 하프")
        let old = race(day(2024, 5, 1), km: 10, min: 45, name: "옛 대회")          // 24개월 밖
        let full = race(day(2026, 3, 1), km: MRDistance.dF / 1000, min: 200, name: "풀")   // 풀 제외
        let all = [a, b, old, full]
        let est = try #require(mrThresholdAsOf(runs: all.map(\.0), races: all.map(\.1), restingHRSamples: [],
                                               dateOfBirth: nil, sex: .male, heat: MRHeatModel(), asOf: asOf))
        #expect(est.anchorName == "가을 10K")
        let expected = try #require(mrThresholdPace(halfEquivMin: 50 * pow(MRDistance.dH / 10_000, 1.06)))
        #expect(abs(est.paceSecPerKm - expected) < 0.01)
        #expect(est.paceConfidence == .medium)
        // 24개월 밖 대회뿐 → 기준 기록 없음
        #expect(mrThresholdAsOf(runs: [old.0], races: [old.1], restingHRSamples: [], dateOfBirth: nil,
                                sex: .male, heat: MRHeatModel(), asOf: asOf) == nil)
    }
}
