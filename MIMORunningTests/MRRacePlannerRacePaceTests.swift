import Testing
import Foundation
@testable import MIMORunning

@Suite("MRRacePlanner 대회 페이스 단계")
struct MRRacePlannerRacePaceTests {

    @Test func segmentMinutesIs15ForLongRunsAnd10ForShort() {
        #expect(mrRacePaceSegmentMinutes(longRunMin: 140) == 15)
        #expect(mrRacePaceSegmentMinutes(longRunMin: 60) == 15)
        #expect(mrRacePaceSegmentMinutes(longRunMin: 59) == 10)
    }

    @Test func trainingRacePaceForHalfIgnoresHeatAndTaper() {
        // 하프 등가 110분 → 110×60/21.0975 = 312.8 초/km
        let p = mrTrainingRacePaceSecPerKm(halfEquivMin: 110, distanceM: MRDistance.dH,
                                           weeklyKm: 40, longestKm: 21, finishes: 0)
        #expect(abs(p - 312.8) < 0.2)
    }

    @Test func trainingRacePaceForFullUsesMarathonModel() {
        let b = bMarathonModel(weeklyKm: 50, longestKm: 28, finishes: 1).b
        let expected = 110 * pow(2.0, b) * 60 / 42.195
        let p = mrTrainingRacePaceSecPerKm(halfEquivMin: 110, distanceM: MRDistance.dF,
                                           weeklyKm: 50, longestKm: 28, finishes: 1)
        #expect(abs(p - expected) < 0.01)
    }
}
