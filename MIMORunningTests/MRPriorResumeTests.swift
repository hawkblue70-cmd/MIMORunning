import Testing
import Foundation
@testable import MIMORunning

@Suite("앞 대회 뒤 재개 — 회복 블록 유지 · 대회 러닝 제외", .korean)
struct MRPriorResumeTests {

    private let cal = Calendar.current
    private func date(_ m: Int, _ d: Int, _ y: Int = 2026, hour: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }
    private func run(_ start: Date, km: Double) -> MRWorkout {
        MRWorkout(start: start, durationMin: km * 6, distanceKm: km, hrAvg: 140, hrMax: 170,
                  tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }

    // MARK: - 프로필: 대회 러닝 제외

    @Test func longestNonRaceRunExcludesTheRaceRun() {
        let runs = [run(date(10, 31), km: 14), run(date(11, 8), km: 12), run(date(11, 15), km: 21.3)]
        let half = [(date: date(11, 15, hour: 9), distanceM: MRDistance.dH)]
        let p = mrProfile(runs: runs, efforts: [], asOf: date(11, 23), raceDays: half)
        #expect(p.longestRun16wKm == 21.3)               // 예측(지구력)에는 대회 러닝도 증거 — 그대로
        #expect(p.longestNonRaceRun16wKm == 14)          // 계획 출발점은 대회를 뺀 값
        // 앱이 '대회'로 분류한 러닝(시작 시각)도 뺀다
        let p2 = mrProfile(runs: runs, efforts: [], asOf: date(11, 23), raceRunStarts: [date(11, 15)])
        #expect(p2.longestNonRaceRun16wKm == 14)
        // 대회 정보가 없으면 계산하지 않는다(nil → 최장 러닝 그대로)
        #expect(mrProfile(runs: runs, efforts: [], asOf: date(11, 23)).longestNonRaceRun16wKm == nil)
    }

    @Test func sameDayButDifferentDistanceIsNotTheRace() {
        // 대회 날 아침 18km 롱런을 따로 뛴 경우 — 하프 거리의 ±10%가 아니라 대회 러닝으로 보지 않는다
        let runs = [run(date(11, 15, hour: 6), km: 18), run(date(11, 8), km: 10)]
        let half = [(date: date(11, 15, hour: 9), distanceM: MRDistance.dH)]
        let p = mrProfile(runs: runs, efforts: [], asOf: date(11, 23), raceDays: half)
        #expect(p.longestNonRaceRun16wKm == 18)
    }

    // MARK: - 플래너: 앞 대회가 끝난 뒤에도 회복 블록에서 이어진다

    private func profile(nonRace: Double?) -> MRProfile {
        var p = MRProfile()
        p.weeklyKm4w = 45; p.longestRun16wKm = 21.3; p.longestNonRaceRun16wKm = nonRace
        p.maxWeeklyKm52w = 55; p.runsPerWeek = 4; p.marathonFinishes = 1
        return p
    }

    private func plan(prior: Bool, forced: Bool, nonRace: Double?) -> MRRacePlan? {
        let race = date(3, 21, 2027)
        let priorRace: (date: Date, name: String, distanceM: Double, peakLong: Double, peakVol: Double)? =
            prior ? (date(11, 15, hour: 9), "MBN 서울마라톤", MRDistance.dH, 21, 51.4) : nil
        return mrBuildPlan(raceDate: race, distanceM: MRDistance.dF, today: date(11, 23),
                           profile: profile(nonRace: nonRace), halfEquivMin: 118,
                           easyPaceSecPerKm: 400, heat: MRHeatModel(), raceTempC: 15,
                           runsPerWeek: 4, priorRace: priorRace,
                           forcedMonday: forced ? cal.startOfDay(for: date(11, 16)) : nil)
    }

    @Test func planContinuesFromRecoveryBlockAfterThePriorRaceEnded() throws {
        let p = try #require(plan(prior: true, forced: true, nonRace: 14))
        #expect(p.priorRecoveryWeeks == 1)
        #expect(p.weeks[0].phase == "회복")
        #expect(abs(p.weeks[0].longRunKm - 12.6) < 0.05)          // 하프 정점 21 × 60%
        #expect(abs(p.weeks[1].longRunKm - 13.9) < 0.15)          // 12.6 +10% — 26km가 아니다
        #expect(p.weeks[4].phase == "회복")                       // 회복 주는 5주차(12/14)부터 4주 간격
        #expect(p.weeks.map(\.longRunKm).max()! <= 28.05)
    }

    @Test func withoutTheAnchorMatchOldBehaviorStays() throws {
        // 앵커가 앞 대회 다음 주가 아니면(시작 전 계획 등) 지난 앞 대회는 쓰지 않는다 — 기존 동작
        let p = try #require(plan(prior: true, forced: false, nonRace: 14))
        #expect(p.priorRecoveryWeeks == 0)
        #expect(p.weeks.first?.phase != "회복")
    }

    @Test func startingLongRunIgnoresRaceRunWhenKnown() throws {
        // 앞 대회 정보가 없고 최장 러닝이 대회(21.3)여도, 대회를 뺀 14km에서 시작한다 — 21.3에서 시작하면 첫 주 23km
        let withEx = try #require(plan(prior: false, forced: false, nonRace: 14))
        let without = try #require(plan(prior: false, forced: false, nonRace: nil))
        #expect(withEx.weeks[0].longRunKm < 17)
        #expect(without.weeks[0].longRunKm > 22)
    }

    // MARK: - 스냅샷 보정

    private func liveWeek(_ idx: Int, _ mon: Date, _ phase: String, long: Double, weekly: Double) -> MRPlanWeek {
        MRPlanWeek(idx: idx, monday: cal.startOfDay(for: mon), phase: phase, longRunKm: long, longRunMin: 0,
                   weeklyKm: weekly, projectedMin: 0, isNewMax: false, breakdown: "롱런 \(Int(long))km")
    }

    @Test func resumeReplacesThisAndFutureWeeksOnly() {
        let m1 = date(11, 16), m2 = date(11, 23), m3 = date(11, 30)
        let snap = [
            MRPlanWeekSummary(idx: 1, monday: cal.startOfDay(for: m1), phase: "회복", longRunKm: 12.6, weeklyKm: 36),
            MRPlanWeekSummary(idx: 2, monday: cal.startOfDay(for: m2), phase: "늘리기", longRunKm: 25.8, weeklyKm: 44),
            MRPlanWeekSummary(idx: 3, monday: cal.startOfDay(for: m3), phase: "늘리기", longRunKm: 28, weeklyKm: 46),
        ]
        let live = [liveWeek(1, m1, "회복", long: 12.6, weekly: 36), liveWeek(2, m2, "늘리기", long: 13.9, weekly: 38),
                    liveWeek(3, m3, "늘리기", long: 15.3, weekly: 40)]
        let r = mrResumeFutureWeeks(snapshot: snap, live: live, thisMonday: cal.startOfDay(for: m2))
        #expect(r.changed == 2)
        #expect(r.weeks[0].longRunKm == 12.6 && r.weeks[0].weeklyKm == 36)   // 지난 주 그대로
        #expect(r.weeks[1].longRunKm == 13.9 && r.weeks[1].weeklyKm == 38)   // 이번 주 = 지금 뛸 주
        #expect(r.weeks[2].longRunKm == 15.3)
        // 이미 같으면 바꾸지 않는다
        #expect(mrResumeFutureWeeks(snapshot: r.weeks, live: live, thisMonday: cal.startOfDay(for: m2)).changed == 0)
    }
}
