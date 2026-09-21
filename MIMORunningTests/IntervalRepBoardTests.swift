import Testing
import Foundation
@testable import MIMORunning

@Suite("경로 영상 인터벌 회차 보드", .korean)
struct IntervalRepBoardTests {
    /// 준비 1km(6'20") → [운동 1km + 회복 200m] × n → 정리 1km. 10초 간격이 아니라 구간 시각만 있으면 된다.
    private func segments(reps: Int, workM: Double = 1000, workPace: [Double]? = nil, hr: [Int]? = nil,
                          start: Date = Date(timeIntervalSince1970: 1_000_000)) -> [IntervalSegment] {
        var out: [IntervalSegment] = []
        var t = start
        func add(_ label: String, _ m: Double, _ sec: Double, hr: Int? = nil, cad: Int? = 184) {
            let end = t.addingTimeInterval(sec)
            out.append(IntervalSegment(id: out.count + 1, startDate: t, endDate: end, distanceM: m,
                                       avgHeartRate: hr, avgCadence: cad, stepLabel: label))
            t = end
        }
        add("준비운동", 1000, 380, hr: 130)
        for i in 0..<reps {
            let pace = workPace?[i] ?? 295
            add("운동", workM, pace * workM / 1000, hr: hr?[i] ?? 150)
            if i < reps - 1 { add("회복", 200, 90, hr: 135) }
        }
        add("정리운동", 1000, 372, hr: 128)
        return out
    }

    private func total(_ segs: [IntervalSegment]) -> (m: Double, s: TimeInterval) {
        (segs.compactMap(\.distanceM).reduce(0, +), segs.last!.endDate.timeIntervalSince(segs.first!.startDate))
    }

    @Test func needsAtLeastTwoWorkSegments() {
        let one = segments(reps: 1)
        let t = total(one)
        #expect(IntervalRepBoard.make(segments: one, activityStart: one[0].startDate, totalDistanceM: t.m, totalDuration: t.s) == nil)
        #expect(IntervalRepBoard.make(segments: [], activityStart: Date(), totalDistanceM: 5000, totalDuration: 1800) == nil)
    }

    @Test func repsCarryPaceHRAndCumulativeDistanceFraction() throws {
        let segs = segments(reps: 5, workPace: [299, 292, 295, 287, 285], hr: [149, 151, 153, 155, 157])
        let t = total(segs)
        let b = try #require(IntervalRepBoard.make(segments: segs, activityStart: segs[0].startDate, totalDistanceM: t.m, totalDuration: t.s))
        #expect(b.reps.count == 5)
        #expect(b.reps[0].index == 1)
        #expect(b.reps[3].paceSecPerKm == 287)
        #expect(b.reps[4].avgHeartRate == 157)
        // 1회차 끝 = 준비 1000 + 운동 1000 = 2000m / 총 6800m(준비 1000 + 운동 5000 + 회복 800 + 정리 1000)
        #expect(abs(b.reps[0].revealFraction - 2000.0 / 6800.0) < 1e-9)
        // 마지막 회차 끝 = 6800 − 정리 1000 = 5800
        #expect(abs(b.reps[4].revealFraction - 5800.0 / 6800.0) < 1e-9)
        #expect(b.reps.map(\.revealFraction) == b.reps.map(\.revealFraction).sorted())
    }

    @Test func fallsBackToTimeFractionWhenAnyDistanceMissing() throws {
        var segs = segments(reps: 3)
        // 회복 구간 하나의 거리를 지운다 → 거리 누적이 불가능 → 시간 비율
        let s = segs[2]
        segs[2] = IntervalSegment(id: s.id, startDate: s.startDate, endDate: s.endDate, distanceM: nil,
                                  avgHeartRate: s.avgHeartRate, avgCadence: s.avgCadence, stepLabel: s.stepLabel)
        let t = total(segs)
        let b = try #require(IntervalRepBoard.make(segments: segs, activityStart: segs[0].startDate, totalDistanceM: 5400, totalDuration: t.s))
        let firstEnd = segs[1].endDate.timeIntervalSince(segs[0].startDate)
        #expect(abs(b.reps[0].revealFraction - firstEnd / t.s) < 1e-9)
    }

    @Test func uniformDistanceHeaderAndAverageFooter() throws {
        let segs = segments(reps: 5, workPace: [299, 292, 295, 287, 285])
        let t = total(segs)
        let b = try #require(IntervalRepBoard.make(segments: segs, activityStart: segs[0].startDate, totalDistanceM: t.m, totalDuration: t.s))
        #expect(b.uniformDistanceM == 1000)
        #expect(b.headerText == "5 × 1km")
        #expect(b.showsDistanceColumn == true)   // 거리 열은 항상
        // 평균 (299+292+295+287+285)/5 = 291.6 → 292 → 4'52"
        #expect(b.footerText == "평균 4'52\"")
    }

    @Test func mixedDistancesShowColumnAndCountHeader() throws {
        var segs = segments(reps: 3)
        // 2회차 운동 거리를 400m로
        let i = segs.firstIndex { $0.stepLabel == "운동" }! + 2
        let s = segs[i]
        segs[i] = IntervalSegment(id: s.id, startDate: s.startDate, endDate: s.endDate, distanceM: 400,
                                  avgHeartRate: s.avgHeartRate, avgCadence: s.avgCadence, stepLabel: s.stepLabel)
        let t = total(segs)
        let b = try #require(IntervalRepBoard.make(segments: segs, activityStart: segs[0].startDate, totalDistanceM: t.m, totalDuration: t.s))
        #expect(b.uniformDistanceM == nil)
        #expect(b.showsDistanceColumn == true)
        #expect(b.headerText == "인터벌 3회")
    }

    @Test func revealedCountFollowsProgress() throws {
        let segs = segments(reps: 5)
        let t = total(segs)
        let b = try #require(IntervalRepBoard.make(segments: segs, activityStart: segs[0].startDate, totalDistanceM: t.m, totalDuration: t.s))
        #expect(b.revealedCount(progress: 0) == 0)
        #expect(b.revealedCount(progress: CGFloat(b.reps[0].revealFraction) - 0.001) == 0)
        #expect(b.revealedCount(progress: CGFloat(b.reps[0].revealFraction)) == 1)
        #expect(b.revealedCount(progress: CGFloat(b.reps[2].revealFraction) + 0.001) == 3)
        #expect(b.revealedCount(progress: 1) == 5)
    }

    @Test func nineRepsSwitchToTwoColumns() throws {
        let eight = segments(reps: 8, workM: 400); let t8 = total(eight)
        let b8 = try #require(IntervalRepBoard.make(segments: eight, activityStart: eight[0].startDate, totalDistanceM: t8.m, totalDuration: t8.s))
        #expect(b8.columns == 1)
        let nine = segments(reps: 9, workM: 400); let t9 = total(nine)
        let b9 = try #require(IntervalRepBoard.make(segments: nine, activityStart: nine[0].startDate, totalDistanceM: t9.m, totalDuration: t9.s))
        #expect(b9.columns == 2)
        #expect(b9.slotCount == 6)   // 5쌍(9회 → 5줄) + 바닥글
    }

    @Test func slotsSingleColumnUpToTenThenPairs() throws {
        let five = segments(reps: 5); let t5 = total(five)
        let b5 = try #require(IntervalRepBoard.make(segments: five, activityStart: five[0].startDate, totalDistanceM: t5.m, totalDuration: t5.s))
        #expect(b5.columns == 1)
        #expect(b5.slotCount == 6)              // 5줄 + 바닥글
        #expect(b5.revealedSlots(revealed: 0) == 0)
        #expect(b5.revealedSlots(revealed: 3) == 3)
        #expect(b5.revealedSlots(revealed: 5) == 6)   // 마지막 회차와 함께 바닥글

        let twelve = segments(reps: 12, workM: 400); let t12 = total(twelve)
        let b12 = try #require(IntervalRepBoard.make(segments: twelve, activityStart: twelve[0].startDate, totalDistanceM: t12.m, totalDuration: t12.s))
        #expect(b12.columns == 2)
        #expect(b12.slotCount == 7)             // 6쌍 + 바닥글
        #expect(b12.revealedSlots(revealed: 1) == 1)   // 1회차만 보여도 첫 쌍의 칸은 열린다
        #expect(b12.revealedSlots(revealed: 2) == 1)
        #expect(b12.revealedSlots(revealed: 3) == 2)
        #expect(b12.revealedSlots(revealed: 12) == 7)
        #expect(b12.headerText == "12 × 400m")
    }

    @Test func warmupAndCooldownRowsCarryPaceAndEndFraction() throws {
        let segs = segments(reps: 2)
        let t = total(segs)
        let b = try #require(IntervalRepBoard.make(segments: segs, activityStart: segs[0].startDate, totalDistanceM: t.m, totalDuration: t.s))
        let w = try #require(b.warmup)
        #expect(w.paceSecPerKm == 380)
        #expect(w.avgHeartRate == 130)
        #expect(abs(w.revealFraction - 1000.0 / t.m) < 1e-9)      // 준비 1km가 끝나는 지점
        let c = try #require(b.cooldown)
        #expect(c.paceSecPerKm == 372)
        #expect(abs(c.revealFraction - 1.0) < 1e-9)               // 마지막 구간 끝 = 경로 끝
        #expect(!b.isRevealed(b.warmup, progress: 0))
        #expect(b.isRevealed(b.warmup, progress: CGFloat(w.revealFraction)))
        #expect(!b.isRevealed(b.cooldown, progress: 0.99))
        #expect(b.isRevealed(b.cooldown, progress: 1))
        #expect(b.isRevealed(nil, progress: 1) == false)
    }

    @Test func dimRangesAreNonWorkSegments() throws {
        let segs = segments(reps: 2)
        let t = total(segs)
        let b = try #require(IntervalRepBoard.make(segments: segs, activityStart: segs[0].startDate, totalDistanceM: t.m, totalDuration: t.s))
        // 준비 · 회복 · 정리 = 3구간
        #expect(b.dimTimeRanges.count == 3)
        #expect(b.dimTimeRanges[0].lowerBound == 0)
        #expect(abs(b.dimTimeRanges[0].upperBound - 380) < 1e-9)
        #expect(b.isDimmed(offset: 100))     // 준비운동 중
        #expect(!b.isDimmed(offset: 500))    // 1회차 운동 중
    }
}
