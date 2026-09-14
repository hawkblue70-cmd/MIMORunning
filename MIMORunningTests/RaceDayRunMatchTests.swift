import Testing
import Foundation
@testable import MIMORunning

/// 대회일 실제 기록 찾기 — 거리 허용 오차 ±10%.
/// 대회에 안 나갔는데 그날 뛴 다른 러닝이 대회 결과로 둔갑하는 것을 막는다.
@Suite("대회일 기록 매칭")
struct RaceDayRunMatchTests {

    private let raceDay = Calendar.current.date(from: DateComponents(
        year: 2026, month: 9, day: 6, hour: 8, minute: 0))!

    private func run(_ km: Double, minutes: Double, hourOffset: Int = 0,
                     isInterval: Bool = false) -> MRWorkout {
        MRWorkout(start: Calendar.current.date(byAdding: .hour, value: hourOffset, to: raceDay)!,
                  durationMin: minutes, distanceKm: km,
                  hrAvg: nil, hrMax: nil, tempC: nil, humidity: nil,
                  indoor: false, isInterval: isInterval)
    }

    // MARK: - 허용 오차 밖은 잡지 않는다

    @Test func joggingOnRaceDayIsNotTakenAsTheResult() {
        // 10K 대회에 등록만 하고 안 나감 + 그날 7km 조깅 → 기록 없음이어야 한다
        let found = mrFindRaceDayRun(runs: [run(7.0, minutes: 45)],
                                     raceDate: raceDay, distanceM: MRDistance.d10)
        #expect(found == nil)
    }

    @Test func longRunIsNotTakenAsATenK() {
        let found = mrFindRaceDayRun(runs: [run(15.0, minutes: 90)],
                                     raceDate: raceDay, distanceM: MRDistance.d10)
        #expect(found == nil)
    }

    @Test func noRunsAtAllYieldsNil() {
        #expect(mrFindRaceDayRun(runs: [], raceDate: raceDay, distanceM: MRDistance.d10) == nil)
    }

    // MARK: - 실제 대회 기록은 그대로 잡힌다

    @Test func gpsOverreadOnTenKStillMatches() {
        // 10K를 GPS가 10.3km로 읽는 흔한 경우
        let found = mrFindRaceDayRun(runs: [run(10.3, minutes: 53.8)],
                                     raceDate: raceDay, distanceM: MRDistance.d10)
        #expect(found?.distanceKm == 10.3)
    }

    @Test func marathonWithinTenPercentMatches() {
        let found = mrFindRaceDayRun(runs: [run(42.6, minutes: 304.75)],
                                     raceDate: raceDay, distanceM: MRDistance.dF)
        #expect(found?.distanceKm == 42.6)
    }

    @Test func toleranceBoundaries() {
        // 10K 기준 9.0~11.0km
        #expect(mrFindRaceDayRun(runs: [run(9.0, minutes: 50)],
                                 raceDate: raceDay, distanceM: MRDistance.d10) != nil)
        #expect(mrFindRaceDayRun(runs: [run(11.0, minutes: 60)],
                                 raceDate: raceDay, distanceM: MRDistance.d10) != nil)
        #expect(mrFindRaceDayRun(runs: [run(8.9, minutes: 50)],
                                 raceDate: raceDay, distanceM: MRDistance.d10) == nil)
        #expect(mrFindRaceDayRun(runs: [run(11.1, minutes: 60)],
                                 raceDate: raceDay, distanceM: MRDistance.d10) == nil)
    }

    // MARK: - 여러 기록 중에서 고르기

    @Test func picksClosestAmongQualifyingRuns() {
        // 워밍업 4km + 대회 10.2km + 쿨다운 3km 를 따로 기록한 경우
        let runs = [run(4.0, minutes: 26, hourOffset: -1),
                    run(10.2, minutes: 54),
                    run(3.0, minutes: 20, hourOffset: 2)]
        #expect(mrFindRaceDayRun(runs: runs, raceDate: raceDay, distanceM: MRDistance.d10)?
                    .distanceKm == 10.2)
    }

    @Test func intervalSessionIsIgnored() {
        let found = mrFindRaceDayRun(runs: [run(10.0, minutes: 55, isInterval: true)],
                                     raceDate: raceDay, distanceM: MRDistance.d10)
        #expect(found == nil)
    }

    @Test func otherDaysAreIgnored() {
        let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: raceDay)!
        let r = MRWorkout(start: dayBefore, durationMin: 54, distanceKm: 10.1,
                          hrAvg: nil, hrMax: nil, tempC: nil, humidity: nil,
                          indoor: false, isInterval: false)
        #expect(mrFindRaceDayRun(runs: [r], raceDate: raceDay, distanceM: MRDistance.d10) == nil)
    }

    @Test func zeroTargetDistanceYieldsNil() {
        #expect(mrFindRaceDayRun(runs: [run(10.0, minutes: 54)],
                                 raceDate: raceDay, distanceM: 0) == nil)
    }
}
