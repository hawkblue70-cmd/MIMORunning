import Testing
import Foundation
@testable import MIMORunning

@Suite("내 폼 변화 · 신발 성격 — 페이스·거리 보정")
struct ShoeFormComparisonTests {
    private typealias C = ShoeFormComparison
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ d: Int) -> Date { now.addingTimeInterval(Double(d) * 86_400) }

    /// 지면접촉 = 400 − 50·속도 + 1·거리 + 신발 효과 + 시기 효과 + 잡음
    private func sample(_ i: Int, at d: Int, shoe: String?, effect: Double = 0, temp: Double? = 15) -> C.Sample {
        let pace = 300.0 + Double(i % 7) * 15
        let km = 5.0 + Double(i % 5) * 3
        let gct = 400 - 50 * (1000 / pace) + km + effect + (Double(i % 3) - 1)
        return C.Sample(date: day(d), distanceM: km * 1000, paceSecPerKm: pace, avgHeartRate: 140,
                        contact: gct, oscillation: 8.5, temperatureC: temp, shoeID: shoe)
    }

    @Test func modelRemovesPaceAndDistance() throws {
        let s = (0..<40).map { sample($0, at: -$0, shoe: nil) }
        let m = try #require(C.fit(.contact, samples: s, asOf: now))
        #expect(abs((m.coefficient(.speed) ?? 0) - -50) < 0.5)
        #expect(abs((m.coefficient(.distance) ?? 0) - 1) < 0.1)
        #expect(!m.usesTemperature)
        #expect(C.fit(.contact, samples: Array(s.prefix(19)), asOf: now) == nil)
    }

    @Test func shoeEffectIsMeasuredAgainstSameWeeks() throws {
        // 시기 효과: 120일 전 +10ms(여름) → 지금 0. 신발 A는 여름에만, B는 지금만 신었다.
        // 1년 평균 기준이면 A가 +10 쪽으로 보이지만, 같은 시기 비교면 A·B 모두 차이 없음.
        var s: [C.Sample] = []
        for i in 0..<20 { s.append(sample(i, at: -120 - i % 10, shoe: i % 2 == 0 ? "A" : nil, effect: 10)) }
        for i in 20..<40 { s.append(sample(i, at: -(i % 10), shoe: i % 2 == 0 ? "B" : nil)) }
        let m = try #require(C.fit(.contact, samples: s, asOf: now))
        let st = C.shoeStats(.contact, samples: s, model: m)
        let a = try #require(st.first { $0.shoeID == "A" }), b = try #require(st.first { $0.shoeID == "B" })
        #expect(abs(a.mean) < 2)
        #expect(abs(b.mean) < 2)
    }

    @Test func realShoeEffectShowsUp() throws {
        // 같은 시기에 A(+9ms)와 다른 러닝을 섞어 신었다
        let s = (0..<40).map { sample($0, at: -$0, shoe: $0 % 2 == 0 ? "A" : "B", effect: $0 % 2 == 0 ? 9 : 0) }
        let m = try #require(C.fit(.contact, samples: s, asOf: now))
        let a = try #require(C.shoeStats(.contact, samples: s, model: m).first { $0.shoeID == "A" })
        #expect(a.differs)
        #expect(a.mean > 8 && a.mean < 10)
    }

    @Test func recentChangeComparesLastFourWeeksWithThreeMonthsAgo() throws {
        var s = (0..<40).map { sample($0, at: -200 - $0, shoe: nil) }
        s += (0..<6).map { sample($0, at: -80 - $0, shoe: nil, effect: 6) }   // 3개월 전 +6
        s += (0..<6).map { sample($0, at: -$0, shoe: nil) }                    // 최근 0
        let m = try #require(C.fit(.contact, samples: s, asOf: now))
        let pts = C.points(.contact, samples: s, model: m, from: day(-110))
        let ch = try #require(C.recentChange(pts, asOf: now))
        #expect(abs((ch.now - ch.then) - -6) < 1)
    }

    @Test func efficiencyUsesTemperatureWhenRecorded() throws {
        let s = (0..<30).map { i -> C.Sample in
            let t = 5.0 + Double(i)           // 5~34°C
            let hr = Int(130 + t * 0.8)       // 더울수록 심박↑
            return C.Sample(date: day(-i), distanceM: 8000, paceSecPerKm: 360 + Double(i % 4) * 10, avgHeartRate: hr,
                            contact: nil, oscillation: nil, temperatureC: t, shoeID: nil)
        }
        let m = try #require(C.fit(.efficiency, samples: s, asOf: now))
        // 거리가 모두 8km(상수)여도 거리만 빼고 기온은 살린다
        #expect(m.usesTemperature)
        #expect(m.coefficient(.distance) == nil)
        #expect((m.coefficient(.temperature) ?? 0) < 0)   // 더울수록 효율↓
    }

    @Test func roundingMatchesJudgement() {
        #expect(C.Metric.contact.rounded(7.6) == 8)
        #expect(abs(C.Metric.contact.rounded(7.6)) >= C.Metric.contact.noticeable)
        #expect(C.Metric.oscillation.rounded(0.26) == 0.3)
    }
}
