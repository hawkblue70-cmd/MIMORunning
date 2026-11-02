import Testing
import Foundation
@testable import MIMORunning

@Suite("임계 속도(CS) — 훈련 기록의 최고 연속 km 구간", .korean)
struct MRCriticalSpeedTests {

    private func split(_ id: Int, sec: Double, m: Double = 1000) -> SplitData {
        SplitData(id: id, distanceM: m, duration: sec, avgHeartRate: nil, avgCadence: nil, avgPower: nil,
                  avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil)
    }

    @Test func bestContiguousWindowsSkipPartialSplit() {
        // 300 · 280 · 290 · 310 · 270 + 마지막 0.4km — 창은 온전한 km만
        let s = [300, 280, 290, 310, 270].enumerated().map { split($0.offset + 1, sec: Double($0.element)) }
            + [split(6, sec: 90, m: 400)]
        let b = MRCriticalSpeed.bestKmTimes(splits: s)
        #expect(b[1] == 270)
        #expect(b[2] == 570)     // 280+290
        #expect(b[3] == 870)     // 300+280+290 = 870, 290+310+270 = 870
        #expect(b[4] == 1150)    // 280+290+310+270
        #expect(b[5] == nil)     // 최대 4km
    }

    @Test func gapInSplitsBreaksWindow() {
        // 2km 스플릿 없음(정지·GPS 끊김) — 1·3km를 잇지 않는다
        let s = [split(1, sec: 300), split(3, sec: 300)]
        #expect(MRCriticalSpeed.bestKmTimes(splits: s)[2] == nil)
    }

    @Test func linearFitRecoversSpeedAndDPrime() throws {
        // CS 4 m/s · D′ 200m: 거리 = 4t + 200 → t = (d − 200)/4
        let pts = [1000.0, 2000, 3000].map { (distanceM: $0, timeSec: ($0 - 200) / 4) }
        let f = try #require(MRCriticalSpeed.fit(points: pts))
        #expect(abs(f.csMps - 4) < 1e-9)
        #expect(abs(f.dPrimeM - 200) < 1e-6)
        #expect(f.r2 > 0.999)
    }

    @Test func fitNeedsThreePointsInsideTwoToTwentyMinutes() {
        #expect(MRCriticalSpeed.fit(points: [(1000, 200), (2000, 450)]) == nil)
        // 4km 25분은 창 밖 → 남은 점 2개
        #expect(MRCriticalSpeed.fit(points: [(1000, 300), (2000, 620), (4000, 1500)]) == nil)
    }

    @Test func estimateUsesHardRunsInWindowOnly() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func day(_ d: Int) -> Date { now.addingTimeInterval(Double(-d) * 86400) }
        let runs: [MRCriticalSpeed.RunBest] = [
            // 인터벌 — 1km 240초
            .init(date: day(10), type: .interval, best: [1: 240, 2: 520]),
            // 템포 — 2·3·4km
            .init(date: day(20), type: .tempo, best: [1: 255, 2: 515, 3: 780, 4: 1050]),
            // 이지런이 더 빠른 척해도(GPS 튐) 강한 러닝만 쓴다
            .init(date: day(5), type: .easy, best: [1: 200, 2: 420, 3: 650]),
            // 8주 밖
            .init(date: day(70), type: .race, best: [1: 220, 2: 450, 3: 690]),
        ]
        let e = try #require(MRCriticalSpeed.estimate(runs: runs, asOf: now))
        #expect(e.points.map(\.km) == [1, 2, 3, 4])
        #expect(e.points.map(\.timeSec) == [240, 515, 780, 1050])
        #expect(e.fit.csMps > 3.5 && e.fit.csMps < 4.0)
    }

    @Test func pointsFromOneRunAreNotEnough() {
        // 점이 모두 대회 하나의 앞부분 — 그 대회 페이스를 다시 읽을 뿐이라 CS로 인정하지 않는다(2026-11-03 실기기)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let runs: [MRCriticalSpeed.RunBest] = [
            .init(date: now.addingTimeInterval(-30 * 86400), type: .race, best: [1: 302, 2: 625, 3: 940]),
            .init(date: now.addingTimeInterval(-10 * 86400), type: .interval, best: [1: 330, 2: 700]),
        ]
        #expect(MRCriticalSpeed.estimate(runs: runs, asOf: now) == nil)
    }

    @Test func paceFromSpeed() {
        #expect(abs(MRCriticalSpeed.paceSecPerKm(csMps: 4) - 250) < 1e-9)
    }
}
