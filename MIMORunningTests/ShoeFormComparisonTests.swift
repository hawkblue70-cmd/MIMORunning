import Testing
import Foundation
@testable import MIMORunning

@Suite("신발별 폼 비교 — 페이스·거리 보정")
struct ShoeFormComparisonTests {
    private typealias C = ShoeFormComparison
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// 지면접촉 = 400 − 50·속도(m/s) + 1·거리(km) + 신발 효과 + 잡음
    private func sample(_ i: Int, shoe: String?, effect: Double = 0, noise: Double = 0) -> C.Sample {
        let pace = 300.0 + Double(i % 7) * 15          // 5'00"~6'30"
        let km = 5.0 + Double(i % 5) * 3                 // 5~17km
        let speed = 1000 / pace
        let gct = 400 - 50 * speed + 1 * km + effect + noise
        return C.Sample(date: now.addingTimeInterval(Double(-i) * 86_400), distanceM: km * 1000, paceSecPerKm: pace,
                        avgHeartRate: 140, contact: gct, oscillation: 8.5, shoeID: shoe)
    }

    @Test func modelRemovesPaceAndDistance() throws {
        let s = (0..<40).map { sample($0, shoe: nil) }
        let m = try #require(C.fit(.contact, samples: s, asOf: now))
        #expect(abs(m.b - -50) < 0.01)
        #expect(abs(m.c - 1) < 0.01)
        // 보정 후 차이는 0 — 페이스·거리가 달라도
        #expect(s.allSatisfy { abs(C.residual(.contact, $0, model: m) ?? 99) < 0.01 })
    }

    @Test func needsTwentyRunsInLastYear() {
        let s = (0..<19).map { sample($0, shoe: nil) }
        #expect(C.fit(.contact, samples: s, asOf: now) == nil)
    }

    @Test func shoeEffectSurvivesMixedPaces() throws {
        // 기준은 신발 없는 러닝 30회, 신발 A는 +10ms, B는 0 — 페이스·거리는 제각각
        var s = (0..<30).map { sample($0, shoe: nil, noise: Double($0 % 3) - 1) }
        s += (30..<42).map { sample($0, shoe: "A", effect: 10, noise: Double($0 % 3) - 1) }
        s += (42..<54).map { sample($0, shoe: "B", noise: Double($0 % 3) - 1) }
        let m = try #require(C.fit(.contact, samples: s, asOf: now))
        let st = C.shoeStats(.contact, samples: s, model: m)
        let a = try #require(st.first { $0.shoeID == "A" }), b = try #require(st.first { $0.shoeID == "B" })
        #expect(a.differs)
        // 기준은 모든 신발 러닝으로 만든다 — A(+10)가 기준을 약 2ms 끌어올려 B는 −2ms 근처.
        // 화면은 문턱 절반(4ms) 안이면 "평소와 같음"이라 쓴다
        #expect(abs(b.mean) < C.Metric.contact.noticeable / 2)
        #expect(a.mean - b.mean > 9 && a.mean - b.mean < 11)
    }

    @Test func wearComparesNewStretchWithLastFive() throws {
        let base = (0..<30).map { sample($0, shoe: nil) }
        let m = try #require(C.fit(.contact, samples: base, asOf: now))
        // 신발 A 12회, 10km씩 — 앞 10회(100km)는 0, 뒤 2회는 +12ms → 새 신발 뒤 5회 미만이라 변화 판단 안 함
        func shoeRun(_ k: Int, effect: Double) -> C.Sample {
            let s = sample(k, shoe: "A", effect: effect)
            return C.Sample(date: now.addingTimeInterval(Double(k) * 86_400), distanceM: s.distanceM, paceSecPerKm: s.paceSecPerKm,
                            avgHeartRate: 140, contact: s.contact, oscillation: 8.5, shoeID: "A")
        }
        var runs = (0..<12).map { shoeRun($0, effect: $0 < 10 ? 0 : 12) }
        var dists = runs.map { (date: $0.date, meters: 10_000.0) }
        var v = try #require(C.verdict(C.wear(.contact, shoeID: "A", samples: runs, model: m, shoeDistances: dists)))
        #expect(v.earlyRuns == 10)
        #expect(v.change == nil)
        // 뒤에 3회 더(+12) → 새 신발 뒤 5회 → 최근 5회 평균 +12
        runs += (12..<15).map { shoeRun($0, effect: 12) }
        dists = runs.map { (date: $0.date, meters: 10_000.0) }
        v = try #require(C.verdict(C.wear(.contact, shoeID: "A", samples: runs, model: m, shoeDistances: dists)))
        #expect(abs((v.change ?? 0) - 12) < 0.01)
    }

    @Test func efficiencyResidualIsPercent() throws {
        let s = (0..<25).map { sample($0, shoe: nil) }
        let m = try #require(C.fit(.efficiency, samples: s, asOf: now))
        let r = C.Sample(date: now, distanceM: 8000, paceSecPerKm: 390, avgHeartRate: 130, contact: nil, oscillation: nil, shoeID: "A")
        let e = m.expected(r)
        let res = try #require(C.residual(.efficiency, r, model: m))
        #expect(abs(res - ((r.efficiency! - e) / e * 100)) < 1e-9)
    }
}
