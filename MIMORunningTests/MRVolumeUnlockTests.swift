import Testing
import Foundation
@testable import MIMORunning

@Suite("대회 계획 주간 거리 상한 열기", .korean)
struct MRVolumeUnlockTests {

    private let cal = Calendar.current
    /// 2026-11-16(월)이 '이번 주'. 오프셋 = 그 월요일부터의 일수.
    private var thisMonday: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 16))! }
    private func day(_ offset: Int, hour: Int = 7) -> Date {
        cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: thisMonday)!)!
    }
    private func run(_ offset: Int, km: Double) -> MRWorkout {
        MRWorkout(start: day(offset), durationMin: km * 6, distanceKm: km, hrAvg: 140, hrMax: 170,
                  tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }
    /// 직전 4주 거리(오래된 주 → 최근 주) — 주마다 러닝 하나
    private func weeks(_ kms: [Double]) -> [MRWorkout] {
        kms.enumerated().map { i, km in run(-7 * (kms.count - i) + 1, km: km) }
    }
    private var asOf: Date { day(2) }
    private var farRace: Date { cal.date(from: DateComponents(year: 2027, month: 3, day: 21))! }

    @Test func raisedAndThresholdRounding() {
        #expect(MRVolumeUnlockRules.raised(55) == 60)         // 60.5 → 내림
        #expect(MRVolumeUnlockRules.threshold(55) == 52)      // 52.25 → 내림
    }

    @Test func unlocksWhenThreeOfFourWeeksReachNinetyFivePercent() {
        let r = mrVolumeUnlock(runs: weeks([40, 55, 55, 55]), asOf: asOf, capKm: 55, raceDate: farRace, restDays: { 0 })
        guard case .unlocked(let u) = r else { Issue.record("열려야 함: \(r)"); return }
        #expect(u.fromMonday == cal.date(byAdding: .day, value: 7, to: thisMonday))   // 다음 주 월요일
        #expect(u.baseCapKm == 55 && u.raisedCapKm == 60)
        #expect(u.windowKm == [40, 55, 55, 55])
    }

    @Test func boundaryNinetyFivePercent() {
        // 55 × 0.95 = 52.25 — 52.25는 통과, 52.2는 아님
        let pass = mrVolumeUnlock(runs: weeks([52.25, 52.25, 52.25, 10]), asOf: asOf, capKm: 55, raceDate: farRace, restDays: { 0 })
        if case .notYet = pass { Issue.record("경계값은 통과해야 함") }
        let fail = mrVolumeUnlock(runs: weeks([52.2, 52.2, 52.2, 10]), asOf: asOf, capKm: 55, raceDate: farRace, restDays: { 0 })
        if case .unlocked = fail { Issue.record("경계 아래는 열리면 안 됨") }
    }

    @Test func twoOfFourWeeksIsNotEnough() {
        let r = mrVolumeUnlock(runs: weeks([55, 40, 55, 41]), asOf: asOf, capKm: 55, raceDate: farRace, restDays: { 0 })
        if case .unlocked = r { Issue.record("4주 중 2주는 열리면 안 됨") }
    }

    @Test func thisWeekDoesNotCount() {
        // 이번 주(월요일 이후) 러닝은 직전 4주에 들지 않는다
        var runs = weeks([55, 55, 40, 40])
        runs.append(run(1, km: 60))
        let r = mrVolumeUnlock(runs: runs, asOf: asOf, capKm: 55, raceDate: farRace, restDays: { 0 })
        if case .unlocked = r { Issue.record("이번 주 러닝으로 열리면 안 됨") }
    }

    @Test func restDaysBlockAndAreOnlyAskedAfterOtherConditionsPass() {
        var asked = 0
        let blocked = mrVolumeUnlock(runs: weeks([55, 55, 55, 55]), asOf: asOf, capKm: 55, raceDate: farRace,
                                     restDays: { asked += 1; return 2 })
        if case .unlocked = blocked { Issue.record("휴식 판정이 있으면 열리면 안 됨") }
        #expect(asked == 1)
        asked = 0
        _ = mrVolumeUnlock(runs: weeks([10, 10, 10, 10]), asOf: asOf, capKm: 55, raceDate: farRace,
                           restDays: { asked += 1; return 0 })
        #expect(asked == 0)   // 앞 조건 탈락 — 무거운 판정은 부르지 않는다
    }

    @Test func tooCloseToRaceDoesNotUnlock() {
        // 상향 첫 주 = 11/23, 대회 5주 전 한계 = 대회일 − 35일. 대회 12/20이면 한계 11/15 → 늦음
        let near = cal.date(from: DateComponents(year: 2026, month: 12, day: 20))!
        let r = mrVolumeUnlock(runs: weeks([55, 55, 55, 55]), asOf: asOf, capKm: 55, raceDate: near, restDays: { 0 })
        if case .unlocked = r { Issue.record("대회 5주 전 이후는 열리면 안 됨") }
    }

    @Test func resolveKeepsStartedAndCancelsPending() {
        let from = cal.date(byAdding: .day, value: 7, to: thisMonday)!
        let u = MRVolumeUnlock(fromMonday: from, baseCapKm: 55, raisedCapKm: 60, windowKm: [55, 55, 55, 55])
        // 시작 전: 이번 판정이 다시 열림이면 저장값 유지(첫 주가 밀리지 않음), 아니면 취소
        let moved = MRVolumeUnlock(fromMonday: cal.date(byAdding: .day, value: 14, to: thisMonday)!,
                                   baseCapKm: 55, raisedCapKm: 60, windowKm: [55, 55, 55, 55])
        #expect(MRVolumeUnlockStore.resolve(stored: u, fresh: .unlocked(moved), today: day(0)) == u)
        #expect(MRVolumeUnlockStore.resolve(stored: u, fresh: .notYet(reason: "x"), today: day(0)) == nil)
        // 시작된 뒤: 판정이 닫혀도 고정
        #expect(MRVolumeUnlockStore.resolve(stored: u, fresh: .notYet(reason: "x"), today: day(8)) == u)
        // 저장 없음: 열림이면 새로 저장
        #expect(MRVolumeUnlockStore.resolve(stored: nil, fresh: .unlocked(u), today: day(0)) == u)
    }

    // MARK: - 계획에 반영

    private func profile() -> MRProfile {
        var p = MRProfile()
        p.weeklyKm4w = 45; p.longestRun16wKm = 21
        p.maxWeeklyKm52w = 55; p.runsPerWeek = 4; p.marathonFinishes = 1
        return p
    }

    private func marathonPlan(unlock: MRVolumeUnlock?) -> MRRacePlan? {
        let today = thisMonday
        let race = cal.date(from: DateComponents(year: 2027, month: 3, day: 21))!
        return mrBuildPlan(raceDate: race, distanceM: MRDistance.dF, today: today,
                           profile: profile(), halfEquivMin: 118,
                           easyPaceSecPerKm: 400, heat: MRHeatModel(), raceTempC: 15,
                           runsPerWeek: 4, forcedMonday: thisMonday, volUnlock: unlock)
    }

    @Test func planWithoutUnlockNeverExceedsOneYearHigh() throws {
        let p = try #require(marathonPlan(unlock: nil))
        #expect(p.weeks.map(\.weeklyKm).max()! <= 55.05)
        #expect(p.volUnlock == nil)
        #expect(p.notes.contains { $0.contains("4주 중 3주를 52km 이상 달리면 주 60km까지 한 단계 열립니다") })
    }

    @Test func unlockRaisesOnlyWeeksFromTheFirstRaisedWeek() throws {
        let base = try #require(marathonPlan(unlock: nil))
        let from = cal.date(byAdding: .day, value: 7 * 12, to: thisMonday)!   // 13주차 월요일
        let u = MRVolumeUnlock(fromMonday: from, baseCapKm: 55, raisedCapKm: 60, windowKm: [55, 55, 55, 55])
        let raised = try #require(marathonPlan(unlock: u))
        for (a, b) in zip(base.weeks, raised.weeks) where a.monday < from {
            #expect(abs(a.weeklyKm - b.weeklyKm) < 0.01, "열기 전 주는 같아야 함: \(a.monday)")
        }
        let after = raised.weeks.filter { $0.monday >= from }
        #expect(after.map(\.weeklyKm).max()! > 55.5)
        #expect(after.map(\.weeklyKm).max()! <= 60.05)
        #expect(raised.weeklyCapKm == 60)
        #expect(raised.notes.contains { $0.contains("주 60km까지 올립니다") })
    }

    @Test func halfOrShorterBelowCeilingIsNotAffected() throws {
        // 10K는 거리별 목표(32km)가 상한(55)보다 낮아 열어도 바뀌지 않는다
        let race = cal.date(byAdding: .day, value: 7 * 10, to: thisMonday)!
        func plan(_ u: MRVolumeUnlock?) -> MRRacePlan? {
            mrBuildPlan(raceDate: race, distanceM: MRDistance.d10, today: thisMonday, profile: profile(), halfEquivMin: 110,
                        easyPaceSecPerKm: 400, heat: MRHeatModel(), raceTempC: 15, runsPerWeek: 4, volUnlock: u)
        }
        let u = MRVolumeUnlock(fromMonday: cal.date(byAdding: .day, value: 14, to: thisMonday)!,
                               baseCapKm: 55, raisedCapKm: 60, windowKm: [55, 55, 55, 55])
        let a = try #require(plan(nil)), b = try #require(plan(u))
        #expect(a.weeks.map(\.weeklyKm) == b.weeks.map(\.weeklyKm))
    }

    // MARK: - 시작한 계획 스냅샷

    @Test func snapshotRaiseTouchesOnlyFutureWeeksFromUnlock() throws {
        let base = try #require(marathonPlan(unlock: nil))
        let from = cal.date(byAdding: .day, value: 7 * 12, to: thisMonday)!
        let u = MRVolumeUnlock(fromMonday: from, baseCapKm: 55, raisedCapKm: 60, windowKm: [55, 55, 55, 55])
        let raised = try #require(marathonPlan(unlock: u))
        let snap = base.weeks.map {
            MRPlanWeekSummary(idx: $0.idx, monday: $0.monday, phase: $0.phase, longRunKm: $0.longRunKm,
                              weeklyKm: $0.weeklyKm, breakdown: $0.breakdown, point: $0.point)
        }
        // 12주차 월요일을 '이번 주'로 — 13주차(from)부터가 미래
        let thisMon = cal.date(byAdding: .day, value: 7 * 11, to: thisMonday)!
        let r = mrRaiseSnapshotVolume(snapshot: snap, live: raised.weeks, thisMonday: thisMon, unlockFrom: from)
        #expect(r.raised > 0)
        for (s, o) in zip(snap, r.weeks) {
            let mon = cal.startOfDay(for: s.monday)
            if mon <= cal.startOfDay(for: thisMon) || mon < cal.startOfDay(for: from) {
                #expect(o.weeklyKm == s.weeklyKm, "지난·이번·열기 전 주는 그대로: \(s.monday)")
            } else {
                #expect(o.weeklyKm >= s.weeklyKm - 0.01, "낮추지 않는다")
            }
        }
        #expect(r.weeks.map(\.weeklyKm).max()! > 55.5)
    }
}
