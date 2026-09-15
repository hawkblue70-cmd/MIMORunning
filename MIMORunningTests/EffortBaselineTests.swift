import Testing
import Foundation
@testable import MIMORunning

@Suite("EffortBaseline 개인 기준선", .korean)
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

    // MARK: - 유형별 평소 강도(TypeSummary)

    private func run(_ daysAgo: Int, from now: Date = Date()) -> Activity {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        return Activity(id: UUID(), type: .running, date: d, duration: 3000, distance: 8000,
                        calories: nil, avgHeartRate: nil)
    }

    private func apple(_ v: Double, at now: Date = Date()) -> AppleEffort {
        AppleEffort(manual: nil, estimated: v, fetchedAt: now)
    }

    @Test func typeSummaryWidensToTwelveWeeksWhenUnderThree() {
        let now = Date()
        let recent = [run(5, from: now), run(20, from: now)]                 // 8주 안 2건
        let older  = [run(60, from: now), run(75, from: now)]                // 8~12주 2건
        let all = recent + older
        let idx = EffortIndex(user: [:], apple: Dictionary(uniqueKeysWithValues: zip(all.map(\.id), [4, 6, 8, 6].map { apple(Double($0), at: now) })))
        let s = EffortBaseline.typeSummary(for: .easy, asOf: now, history: all, index: idx, typeOf: { _ in .easy })
        #expect(s.windowWeeks == 12)
        #expect(s.count == 4)
        #expect(s.median == 6)          // 4,6,6,8 → 6
        #expect(!s.isUserBased)
    }

    @Test func typeSummaryPrefersUserRatingsOverApple() {
        let now = Date()
        let userRuns = [run(3, from: now), run(6, from: now), run(9, from: now)]
        let appleRuns = [run(12, from: now), run(15, from: now), run(18, from: now)]
        let all = userRuns + appleRuns
        let idx = EffortIndex(user: Dictionary(uniqueKeysWithValues: zip(userRuns.map { $0.id.uuidString }, [2, 3, 3])),
                              apple: Dictionary(uniqueKeysWithValues: zip(appleRuns.map(\.id), [6, 6, 7].map { apple(Double($0), at: now) })))
        let s = EffortBaseline.typeSummary(for: .easy, asOf: now, history: all, index: idx, typeOf: { _ in .easy })
        #expect(s.windowWeeks == 8)
        #expect(s.count == 6)
        #expect(s.isUserBased)
        #expect(s.median == 3)          // Apple 값 무시 → 2,3,3
    }

    @Test func typeTableKeepsFixedOrderAndDropsEmptyTypes() {
        let now = Date()
        let tempoRuns = [run(2, from: now), run(4, from: now)]
        let easyRuns  = [run(6, from: now), run(8, from: now), run(10, from: now)]
        let all = tempoRuns + easyRuns
        let idx = EffortIndex(user: Dictionary(uniqueKeysWithValues: all.map { ($0.id.uuidString, 5) }), apple: [:])
        let tempoIDs = Set(tempoRuns.map(\.id))
        let rows = EffortBaseline.typeTable(asOf: now, history: all, index: idx,
                                            typeOf: { tempoIDs.contains($0) ? .tempo : .easy })
        #expect(rows.map(\.type) == [.easy, .tempo])   // 고정 순서: easy 먼저
        #expect(rows[0].count == 3)
        #expect(rows[0].median == 5)
        #expect(rows[1].count == 2)
        #expect(rows[1].median == nil)                 // 3건 미만 → 전체 폴백 없이 nil
    }

    @Test func typeSummaryExcludesCurrentRun() {
        let now = Date()
        let all = [run(0, from: now), run(3, from: now), run(6, from: now)]
        let idx = EffortIndex(user: Dictionary(uniqueKeysWithValues: all.map { ($0.id.uuidString, 5) }), apple: [:])
        let full = EffortBaseline.typeSummary(for: .easy, asOf: now, history: all, index: idx, typeOf: { _ in .easy })
        #expect(full.count == 3)
        let excluded = EffortBaseline.typeSummary(for: .easy, asOf: now, history: all, index: idx,
                                                  typeOf: { _ in .easy }, excluding: all[0].id)
        #expect(excluded.count == 2)
        #expect(excluded.median == nil)
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
