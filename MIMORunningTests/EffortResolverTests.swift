import Testing
import Foundation
@testable import MIMORunning

@Suite("EffortResolver 우선순위")
struct EffortResolverTests {

    @Test func userBeatsAppleManualBeatsEstimated() {
        let apple = AppleEffort(manual: 6, estimated: 4, fetchedAt: Date())
        #expect(EffortResolver.resolve(userValue: 3, apple: apple) == ResolvedEffort(value: 3, source: .user))
        #expect(EffortResolver.resolve(userValue: nil, apple: apple) == ResolvedEffort(value: 6, source: .appleManual))
        let est = AppleEffort(manual: nil, estimated: 4.4, fetchedAt: Date())
        #expect(EffortResolver.resolve(userValue: nil, apple: est) == ResolvedEffort(value: 4, source: .appleEstimated))
        #expect(EffortResolver.resolve(userValue: nil, apple: nil) == nil)
    }

    @Test func roundsAndClamps() {
        let apple = AppleEffort(manual: nil, estimated: 7.5, fetchedAt: Date())
        #expect(EffortResolver.resolve(userValue: nil, apple: apple)?.value == 8)
        #expect(EffortResolver.resolve(userValue: 14, apple: nil)?.value == 10)
        #expect(EffortResolver.resolve(userValue: 0, apple: nil)?.value == 1)
        let big = AppleEffort(manual: 12, estimated: nil, fetchedAt: Date())
        #expect(EffortResolver.resolve(userValue: nil, apple: big)?.value == 10)
    }

    @Test func effectiveAndSameValues() {
        let a = AppleEffort(manual: nil, estimated: 5, fetchedAt: Date())
        #expect(a.effective == 5)
        let b = AppleEffort(manual: nil, estimated: 5, fetchedAt: Date(timeIntervalSince1970: 0))
        #expect(a.hasSameValues(as: b))
        #expect(!a.hasSameValues(as: AppleEffort(manual: 5, estimated: 5, fetchedAt: Date())))
    }

    @Test func indexResolvesByWorkoutID() {
        let id = UUID()
        let idx = EffortIndex(user: [id.uuidString: 4],
                              apple: [id: AppleEffort(manual: 7, estimated: nil, fetchedAt: Date())])
        #expect(idx.resolve(id) == ResolvedEffort(value: 4, source: .user))
        let other = UUID()
        #expect(idx.resolve(other) == nil)
    }

    @Test func indexFromStoriesFiltersNilAndFallsBackToApple() {
        let a = UUID(), b = UUID()
        let s1 = WorkoutStory(workoutID: a.uuidString); s1.effortRPE = 5
        let s2 = WorkoutStory(workoutID: b.uuidString)          // nil → 제외
        let idx = EffortIndex(stories: [s1, s2],
                              apple: [b: AppleEffort(manual: nil, estimated: 3, fetchedAt: Date())])
        #expect(idx.resolve(a) == ResolvedEffort(value: 5, source: .user))
        #expect(idx.resolve(b) == ResolvedEffort(value: 3, source: .appleEstimated))
    }

    @Test func indexFromStoriesNewestWinsOnDuplicateWorkoutID() {
        let id = UUID()
        let old = WorkoutStory(workoutID: id.uuidString); old.effortRPE = 3
        old.effortUpdatedAt = Date(timeIntervalSince1970: 1_000)
        let new = WorkoutStory(workoutID: id.uuidString); new.effortRPE = 7
        new.effortUpdatedAt = Date(timeIntervalSince1970: 2_000)
        #expect(EffortIndex(stories: [new, old], apple: [:]).resolve(id)?.value == 7)
        #expect(EffortIndex(stories: [old, new], apple: [:]).resolve(id)?.value == 7)
    }

    @Test func clampDoubleHandlesNonFiniteAndHuge() {
        #expect(EffortResolver.clamp(Double.nan) == 1)
        #expect(EffortResolver.clamp(Double.infinity) == 1)
        #expect(EffortResolver.clamp(1e300) == 10)
        #expect(EffortResolver.clamp(-5.0) == 1)
        #expect(EffortResolver.clamp(-3) == 1)
        let a = AppleEffort(manual: nil, estimated: 5, fetchedAt: Date())
        #expect(!a.hasSameValues(as: AppleEffort(manual: nil, estimated: 6, fetchedAt: Date())))
    }
}
