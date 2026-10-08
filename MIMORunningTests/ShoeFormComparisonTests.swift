import Testing
import Foundation
@testable import MIMORunning

@Suite("신발별 폼 비교")
struct ShoeFormComparisonTests {
    private typealias C = ShoeFormComparison
    private func run(_ day: Int, shoe: String, type: WorkoutType = .general, km: Double = 8,
                     pace: Double = 390, hr: Int? = 140, gct: Double? = 260, vo: Double? = 8.7) -> C.Run {
        C.Run(date: Date(timeIntervalSince1970: Double(day) * 86_400), distanceM: km * 1000, paceSecPerKm: pace,
              avgHeartRate: hr, cadence: 172, stride: 0.9, contact: gct, oscillation: vo,
              shoeID: shoe, group: C.Group(type: type, bucket: .of(km * 1000)))
    }

    @Test func bucketsByDistance() {
        #expect(C.DistanceBucket.of(4_999) == .under5)
        #expect(C.DistanceBucket.of(8_140) == .from5)
        #expect(C.DistanceBucket.of(10_000) == .from10)
        #expect(C.DistanceBucket.of(21_097) == .from21)
    }

    @Test func efficiencyIsMetersPerBeat() {
        // 6'30"/km = 153.8m/분 ÷ 140bpm ≈ 1.10m
        let e = run(1, shoe: "A").efficiency ?? 0
        #expect(abs(e - 1.0989) < 0.001)
        #expect(run(1, shoe: "A", hr: nil).efficiency == nil)
    }

    @Test func comparesOnlyWithinSameTypeAndDistance() {
        let runs = [run(1, shoe: "A", gct: 270), run(2, shoe: "A", gct: 266),
                    run(3, shoe: "B", gct: 258), run(4, shoe: "B", gct: 256),
                    run(5, shoe: "B", type: .interval, km: 8, gct: 220),   // 다른 종류 — 섞이면 안 된다
                    run(6, shoe: "B", km: 16, gct: 280)]                   // 다른 거리 — 섞이면 안 된다
        let g = C.Group(type: .general, bucket: .from5)
        let d = C.difference(.contact, shoeID: "A", group: g, runs: runs)
        #expect(d?.diff == 11)   // 268 − 257
        #expect(d?.mine == 2 && d?.others == 2)
        #expect(C.groups(for: "A", in: runs).first?.group == g)
        #expect(C.stats(.contact, group: g, runs: runs).count == 2)
    }

    @Test func wearUsesCumulativeKmAndHalvesNeedSix() {
        let runs = (1...6).map { run($0, shoe: "A", gct: 250 + Double($0) * 2) }
        let dists = (1...6).map { (date: Date(timeIntervalSince1970: Double($0) * 86_400), meters: 10_000.0) }
        let pts = C.wear(.contact, shoeID: "A", group: nil, runs: runs, allShoeDistances: dists)
        #expect(pts.map(\.km) == [10, 20, 30, 40, 50, 60])
        let h = C.halves(pts)
        #expect(h?.early == 254 && h?.late == 260)
        #expect(C.halves(Array(pts.prefix(5))) == nil)
    }
}
