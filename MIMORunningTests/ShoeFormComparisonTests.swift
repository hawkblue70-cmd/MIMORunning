import Testing
import Foundation
@testable import MIMORunning

@Suite("내 폼 변화 · 신발 성격 — 페이스·거리 보정")
struct ShoeFormComparisonTests {
    private typealias C = ShoeFormComparison
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ d: Int) -> Date { now.addingTimeInterval(Double(d) * 86_400) }

    /// 지면접촉 = 400 − 50·속도 + 1·거리 + 신발 효과 + 시기 효과 + 잡음
    private func sample(_ i: Int, at d: Int, shoe: String?, effect: Double = 0) -> C.Sample {
        let pace = 300.0 + Double(i % 7) * 15
        let km = 5.0 + Double(i % 5) * 3
        let gct = 400 - 50 * (1000 / pace) + km + effect + (Double(i % 3) - 1)
        return C.Sample(date: day(d), distanceM: km * 1000, paceSecPerKm: pace,
                        contact: gct, oscillation: 8.5, shoeID: shoe)
    }

    @Test func modelRemovesPaceAndDistance() throws {
        let s = (0..<40).map { sample($0, at: -$0, shoe: nil) }
        let m = try #require(C.fit(.contact, samples: s, asOf: now))
        #expect(abs(m.coef[1] - -50) < 0.5)
        #expect(abs(m.coef[2] - 1) < 0.1)
        #expect(C.fit(.contact, samples: Array(s.prefix(19)), asOf: now) == nil)
    }

    @Test func shoeEffectIsMeasuredAgainstSameWeeks() throws {
        // 시기 효과: 120일 전 +10ms → 지금 0. A는 그때만, B는 지금만. 같은 시기 비교면 둘 다 차이 없음.
        var s: [C.Sample] = []
        for i in 0..<20 { s.append(sample(i, at: -120 - i % 10, shoe: i % 2 == 0 ? "A" : nil, effect: 10)) }
        for i in 20..<40 { s.append(sample(i, at: -(i % 10), shoe: i % 2 == 0 ? "B" : nil)) }
        let m = try #require(C.fit(.contact, samples: s, asOf: now))
        let st = C.shoeStats(.contact, samples: s, model: m)
        #expect(abs(try #require(st.first { $0.shoeID == "A" }).mean) < 2)
        #expect(abs(try #require(st.first { $0.shoeID == "B" }).mean) < 2)
    }

    @Test func realShoeEffectShowsUp() throws {
        let s = (0..<40).map { sample($0, at: -$0, shoe: $0 % 2 == 0 ? "A" : "B", effect: $0 % 2 == 0 ? 9 : 0) }
        let m = try #require(C.fit(.contact, samples: s, asOf: now))
        let a = try #require(C.shoeStats(.contact, samples: s, model: m).first { $0.shoeID == "A" })
        #expect(a.differs)
        #expect(a.mean > 8 && a.mean < 10)
    }

    @Test func formTrendIgnoresShoeSwitch() throws {
        // 폼은 그대로인데 최근 30일부터 +9ms 신발 A를 주로 신음 → 신발 효과를 빼면 흐름은 평탄
        var s: [C.Sample] = []
        for i in 0..<60 {
            let recent = i < 30
            let shoe: String? = recent ? (i % 3 == 0 ? "B" : "A") : (i % 3 == 0 ? "A" : "B")
            s.append(sample(i, at: -i * 2, shoe: shoe, effect: shoe == "A" ? 9 : 0))
        }
        let m = try #require(C.fit(.contact, samples: s, asOf: now))
        let pts = C.formPoints(.contact, samples: s, model: m, from: day(-120))
        let line = C.trend(pts, from: day(-110), to: now)
        let span = (line.map(\.value).max() ?? 0) - (line.map(\.value).min() ?? 0)
        #expect(span < C.Metric.contact.turnThreshold)
        #expect(C.turns(line, threshold: C.Metric.contact.turnThreshold).isEmpty)
    }

    @Test func zigzagFindsPeaksAndLowsAndSkipsSmallWiggles() {
        // 0 → −10(바닥) → +8(정점) → 0, 주 단위. 중간에 ±2 흔들림은 무시
        let vals: [Double] = [0, -3, -6, -10, -8, -9, -4, 0, 4, 8, 6, 7, 3, 0, 1, 0]
        let line = vals.enumerated().map { (date: day($0.offset * 7 - 120), value: $0.element) }
        let t = C.turns(line, threshold: 4)
        #expect(t.count == 2)
        #expect(t[0].isPeak == false && t[0].value == -10)
        #expect(t[1].isPeak == true && t[1].value == 8)
        let seg = C.lastSegment(line, turns: t)
        #expect(seg?.change == -8)
    }

    @Test func smallDipBeforeTheFirstHumpCountsAsALow() {
        // 화면 사례(10/08 보폭): +0.004 → −0.002(5월) → +0.010(7월) → −0.001 — 시작값에서는 문턱(0.01)을 못 넘지만 혹은 꺾임 둘
        let vals: [Double] = [0.004, 0.001, -0.002, -0.001, 0.002, 0.006, 0.010, 0.009, 0.005, 0.001, -0.001, -0.001, 0.0]
        let line = vals.enumerated().map { (date: day($0.offset * 14 - 180), value: $0.element) }
        let t = C.turns(line, threshold: C.Metric.stride.turnThreshold)
        #expect(t.count == 2)
        #expect(t.first?.isPeak == false && t.first?.value == -0.002)
        #expect(t.last?.isPeak == true && t.last?.value == 0.010)
        // 시작부터 오르기만 하면 바닥 표시 없음
        let up = [0.0, 0.004, 0.008, 0.012, 0.016].enumerated().map { (date: day($0.offset * 14), value: $0.element) }
        #expect(C.turns(up, threshold: 0.01).isEmpty)
        // 화면 사례(10/08 케이던스): 시작 0 → +0.4(4/29) → −1.4(7/1) → +0.4 — +0.4 혹은 얕아서 꺾임 아님, 7/1 바닥만
        let cad = [0, 0.2, 0.4, 0.2, 0, -0.6, -1.2, -1.4, -0.8, 0, 0.4, 0.2].enumerated().map { (date: day($0.offset * 14 - 180), value: $0.element) }
        let ct = C.turns(cad, threshold: C.Metric.cadence.turnThreshold)
        #expect(ct.count == 1 && ct.first?.isPeak == false && ct.first?.value == -1.4)
    }

    @Test func turnsCloserThanFourWeeksAreDropped() {
        let vals: [Double] = [0, -6, 0, -6, 0, -6, 0]   // 매주 뒤집힘
        let line = vals.enumerated().map { (date: day($0.offset * 7), value: $0.element) }
        let t = C.turns(line, threshold: 4)
        for (a, b) in zip(t, t.dropFirst()) {
            #expect((Calendar.current.dateComponents([.day], from: a.date, to: b.date).day ?? 0) >= C.minTurnGapDays)
        }
    }

    @Test func strideShoeEffectShowsUp() throws {
        // 보폭 = 0.6 + 0.1·속도 + 신발 A +0.04m
        let s = (0..<40).map { i -> C.Sample in
            let pace = 300.0 + Double(i % 7) * 15, km = 5.0 + Double(i % 5) * 3
            let a = i % 2 == 0
            return C.Sample(date: day(-i), distanceM: km * 1000, paceSecPerKm: pace, contact: nil, oscillation: nil,
                            stride: 0.6 + 0.1 * (1000 / pace) + (a ? 0.04 : 0) + Double(i % 3 - 1) * 0.005,
                            shoeID: a ? "A" : "B")
        }
        let m = try #require(C.fit(.stride, samples: s, asOf: now))
        let st = try #require(C.shoeStats(.stride, samples: s, model: m).first { $0.shoeID == "A" })
        #expect(st.differs)
        #expect(abs(st.mean - 0.04) < 0.005)
        #expect(C.Metric.stride.rounded(0.0344) == 0.034)
    }

    @Test func flightTimeIsStepTimeMinusContact() {
        let s = C.Sample(date: now, distanceM: 8000, paceSecPerKm: 391, contact: 279, oscillation: nil, cadence: 171, shoeID: nil)
        #expect(abs((s.flight ?? 0) - (60_000.0 / 171 - 279)) < 1e-9)   // ≈ 72ms
        #expect(C.Sample(date: now, distanceM: 8000, paceSecPerKm: 391, contact: 279, oscillation: nil, shoeID: nil).flight == nil)
    }

    @Test func longerContactAtSameCadenceMeansShorterFlight() throws {
        // 신발 A: 케이던스 같고 접지 +8ms → 공중 시간 −8ms
        let s = (0..<40).map { i -> C.Sample in
            let pace = 300.0 + Double(i % 7) * 15, km = 5.0 + Double(i % 5) * 3, a = i % 2 == 0
            let cad = 150 + 25 * (1000 / pace) + Double(i % 3 - 1) * 0.5
            let gct = 400 - 50 * (1000 / pace) + (a ? 8 : 0) + Double(i % 3 - 1)
            return C.Sample(date: day(-i), distanceM: km * 1000, paceSecPerKm: pace, contact: gct, oscillation: nil,
                            cadence: cad, shoeID: a ? "A" : "B")
        }
        func effect(_ m: C.Metric) throws -> C.ShoeStat {
            let mod = try #require(C.fit(m, samples: s, asOf: now))
            return try #require(C.shoeStats(m, samples: s, model: mod).first { $0.shoeID == "A" })
        }
        #expect(abs(try effect(.cadence).mean) < C.Metric.cadence.noticeable)
        #expect(abs(try effect(.flight).mean - -8) < 1.5)
        #expect(!C.Metric.shown.contains(.flight))
    }

    @Test func patternFromCadenceContactOscillation() {
        #expect(C.pattern(cadence: 3, contact: -6, oscillation: -0.2) == .quickSteps)
        #expect(C.pattern(cadence: -3, contact: 2, oscillation: 0.2) == .longStride)
        #expect(C.pattern(cadence: 0.3, contact: -1, oscillation: -0.2) == .lowGlide)
        #expect(C.pattern(cadence: 0, contact: 0, oscillation: 0.2) == .bouncier)
        #expect(C.pattern(cadence: 0.3, contact: 1, oscillation: 0.05) == .steady)
        #expect(C.pattern(cadence: 3, contact: 6, oscillation: -0.2) == .mixed)   // 케이던스↑인데 접지↑ — 한 방향 아님
        #expect(C.Metric.shown.contains(.cadence))
    }

    @Test func smallButConsistentDriftIsALeanNotNoChange() {
        // 화면 사례(10/08): 케이던스 +0.6 · 접지 −3ms · 진폭 −0.1cm — 꺾임 문턱 안이지만 셋 다 총총 쪽으로 기움
        #expect(C.pattern(cadence: 0.6, contact: -3, oscillation: -0.1) == .quickSteps)
        #expect(!C.isClear(cadence: 0.6, contact: -3, oscillation: -0.1))
        #expect(C.isClear(cadence: 0.6, contact: -5, oscillation: -0.1))
        let big = C.biggestMover(cadence: 0.2, contact: 3, oscillation: -0.14)   // 진폭 0.93 > 접지 0.75
        #expect(big.metric == .oscillation)
    }

    @Test func temperatureCheckFindsTemperatureEffect() throws {
        // 접지 = 400 − 50·속도 + 0.5ms/°C(10°C당 +5ms), 기온은 계절처럼 오르내림
        let s = (0..<80).map { i -> C.Sample in
            let pace = 300.0 + Double(i % 7) * 15, km = 5.0 + Double(i % 5) * 3
            let t = 15 + 12 * sin(Double(i) / 80 * .pi * 2)
            var x = C.Sample(date: day(-i * 3), distanceM: km * 1000, paceSecPerKm: pace,
                             contact: 400 - 50 * (1000 / pace) + 0.5 * t + Double(i % 3 - 1), oscillation: nil, shoeID: nil)
            x.temperatureC = t
            return x
        }
        let c = try #require(C.temperatureCheck(.contact, samples: s, asOf: now))
        #expect(abs(c.per10C - 5) < 0.5)
        #expect(abs(c.per10C) > c.half10C)
        #expect(c.sdWithTemp < c.sdBase)
        #expect(c.swingWithTemp < c.swingBase)
    }

    @Test func roundingMatchesJudgement() {
        #expect(C.Metric.contact.rounded(7.6) == 8)
        #expect(C.Metric.oscillation.rounded(0.26) == 0.3)
    }
}
