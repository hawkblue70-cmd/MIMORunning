import Testing
@testable import MIMORunning

struct MRGelPlanTests {

    @Test func sub3MarathonMatchesSevenKmCadence() throws {
        let p = try #require(MRGelPlan.build(distanceM: 42195, projectedMin: 180))
        #expect(p.intervalMin == 30)
        #expect(p.stops.map { Int($0.km.rounded()) } == [7, 14, 21, 28, 35])
        // 카페인은 21km(90분)
        #expect(p.stops.firstIndex { $0.kind == .caffeine } == 2)
        #expect(p.recommendedLo == 60)
    }

    @Test func slowerMarathonUsesTimeNotDistance() throws {
        let p = try #require(MRGelPlan.build(distanceM: 42195, projectedMin: 252))   // 6'00"/km
        #expect(p.stops.count == 7)                          // 30~210분
        #expect(Int(p.stops[0].km.rounded()) == 5)
        let caf = try #require(p.stops.first { $0.kind == .caffeine })
        #expect(caf.minute == 150)                           // 0.83×252−60 ≈ 149
        #expect(p.stops.filter { $0.kind == .caffeine }.count == 1)
    }

    @Test func halfUnder2hIsOneCaffeineGel() throws {
        let p = try #require(MRGelPlan.build(distanceM: 21097.5, projectedMin: 105))
        #expect(p.intervalMin == 40)
        #expect(p.stops.count == 1)                          // 80분은 남은 25분 < 30 → 뺀다
        #expect(p.stops[0].kind == .caffeine)
        #expect(Int(p.stops[0].km.rounded()) == 8)
        #expect(p.recommendedHi == 60)
    }

    @Test func slowHalfGetsSecondGel() throws {
        let p = try #require(MRGelPlan.build(distanceM: 21097.5, projectedMin: 130))
        #expect(p.stops.map(\.minute) == [40, 80])
    }

    @Test func tenKIsPreStartOnly() throws {
        let p = try #require(MRGelPlan.build(distanceM: 10000, projectedMin: 50))
        #expect(p.stops.isEmpty)
    }

    @Test func shortRacesAndMissingProjectionGetNothing() {
        #expect(MRGelPlan.build(distanceM: 5000, projectedMin: 25) == nil)
        #expect(MRGelPlan.build(distanceM: 21097.5, projectedMin: 0) == nil)
    }

    @Test func elapsedFormat() {
        #expect(MRGelPlan.elapsed(40) == "0:40")
        #expect(MRGelPlan.elapsed(150) == "2:30")
    }
}
