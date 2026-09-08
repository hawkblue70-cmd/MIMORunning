import Testing
import Foundation
@testable import MIMORunning

@Suite("EffortBaseline 개인 기준선")
struct EffortBaselineTests {
    private func s(_ t: WorkoutType, _ e: Int) -> EffortBaseline.Sample { .init(type: t, effort: e) }

    @Test func sameTypeMedianWhenThreeOrMore() {
        let samples = [s(.easy, 4), s(.easy, 6), s(.easy, 5), s(.tempo, 8)]
        #expect(EffortBaseline.median(for: .easy, samples: samples) == 5)
    }

    @Test func fallsBackToAllRunsMedian() {
        let samples = [s(.easy, 4), s(.tempo, 8), s(.longRun, 6)]
        // easy 1건 → 전체 3건 중앙값 6
        #expect(EffortBaseline.median(for: .easy, samples: samples) == 6)
    }

    @Test func nilWhenFewerThanThreeOverall() {
        #expect(EffortBaseline.median(for: .easy, samples: [s(.easy, 4), s(.easy, 5)]) == nil)
        #expect(EffortBaseline.median(for: .easy, samples: []) == nil)
    }

    @Test func samplesExcludeCurrentRunNonRunningAndOldRuns() {
        let cal = Calendar.current
        let now = Date()
        let cur = Activity(id: UUID(), type: .running, date: now, duration: 3000, distance: 8000, calories: nil, avgHeartRate: nil)
        let a = Activity(id: UUID(), type: .running, date: cal.date(byAdding: .day, value: -3, to: now)!, duration: 3000, distance: 8000, calories: nil, avgHeartRate: nil)
        let old = Activity(id: UUID(), type: .running, date: cal.date(byAdding: .day, value: -60, to: now)!, duration: 3000, distance: 8000, calories: nil, avgHeartRate: nil)
        let walk = Activity(id: UUID(), type: .walking, date: cal.date(byAdding: .day, value: -1, to: now)!, duration: 3000, distance: 4000, calories: nil, avgHeartRate: nil)
        let noEffort = Activity(id: UUID(), type: .running, date: cal.date(byAdding: .day, value: -2, to: now)!, duration: 3000, distance: 8000, calories: nil, avgHeartRate: nil)
        let apple = { (v: Double) in AppleEffort(manual: nil, estimated: v, fetchedAt: now) }
        let idx = EffortIndex(user: [cur.id.uuidString: 9],
                              apple: [a.id: apple(4), old.id: apple(8), walk.id: apple(2)])
        let out = EffortBaseline.samples(current: cur, history: [cur, a, old, walk, noEffort], index: idx,
                                         typeOf: { $0 == a.id ? .easy : nil })
        #expect(out == [EffortBaseline.Sample(type: .easy, effort: 4, source: .appleEstimated)])
    }

    @Test func unknownTypeCountsOnlyInFallback() {
        let samples = [EffortBaseline.Sample(type: nil, effort: 4), EffortBaseline.Sample(type: nil, effort: 6),
                       EffortBaseline.Sample(type: .easy, effort: 5)]
        // easy 1건 → 같은 유형 미달 → 전체 3건 중앙값 5
        #expect(EffortBaseline.median(for: .easy, samples: samples) == 5)
        #expect(EffortBaseline.median(for: .general, samples: samples) == 5)   // nil은 general이 아니다
    }

    @Test func evenCountMedianRoundsHalfAwayFromZero() {
        let samples = [EffortBaseline.Sample(type: .easy, effort: 4), .init(type: .easy, effort: 5),
                       .init(type: .easy, effort: 6), .init(type: .easy, effort: 7)]
        #expect(EffortBaseline.median(for: .easy, samples: samples) == 6)   // 5.5 → 6
    }
    @Test func userEntriesTakePriorityOverAppleWhenThreeOrMore() {
        // 같은 유형: Apple 추정 5·6·6 + 수동 2·3·3 → 수동만으로 3
        let samples = [s(.easy, 5), s(.easy, 6), s(.easy, 6),
                       .init(type: .easy, effort: 2, source: .user),
                       .init(type: .easy, effort: 3, source: .user),
                       .init(type: .easy, effort: 3, source: .user)]
        #expect(EffortBaseline.median(for: .easy, samples: samples) == 3)
        #expect(EffortBaseline.isUserBased(for: .easy, samples: samples))
        // 수동 2건뿐이면 전체(수동+Apple) 중앙값: 2,3,5,6,6 → 5
        let two = Array(samples.dropLast())
        #expect(EffortBaseline.median(for: .easy, samples: two) == 5)
        #expect(!EffortBaseline.isUserBased(for: .easy, samples: two))
    }

    @Test func allRunsUserFallbackBeforeMixedFallback() {
        // 같은 유형 1건뿐 → 전체 러닝 폴백. 전체 중 수동 3건 이상이면 수동만.
        let samples = [s(.easy, 6),
                       .init(type: .tempo, effort: 7, source: .user),
                       .init(type: .longRun, effort: 4, source: .user),
                       .init(type: nil, effort: 3, source: .user),
                       s(.general, 6), s(.general, 6)]
        #expect(EffortBaseline.median(for: .easy, samples: samples) == 4)
        #expect(EffortBaseline.isUserBased(for: .easy, samples: samples))
    }
}
