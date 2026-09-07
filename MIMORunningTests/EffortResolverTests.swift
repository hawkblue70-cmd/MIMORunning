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
}
