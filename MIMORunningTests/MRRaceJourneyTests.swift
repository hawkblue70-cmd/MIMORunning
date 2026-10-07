import Testing
import Foundation
@testable import MIMORunning

@Suite("대회 준비 공유 카드 — 계획에서 완주까지", .korean)
struct MRRaceJourneyTests {

    private let cal = Calendar.current
    private func d(_ day: Int, _ h: Int = 7) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h))!
    }
    private func run(_ day: Int, km: Double) -> MRWorkout {
        MRWorkout(start: d(day), durationMin: km * 6, distanceKm: km, hrAvg: 140, hrMax: 170,
                  tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }

    @Test func buildsWeeksDaysAndPredictions() throws {
        // 10/5 주: 화 8 · 목 8(템포런) · 토 16 / 10/12 주: 화 6 · 일 하프 대회
        let runs = [run(6, km: 8), run(8, km: 8), run(10, km: 16), run(13, km: 6), run(18, km: 21.1)]
        let tempo = MRPlanPoint(kind: .tempo, totalKm: 7, reps: nil, repKm: nil, sustainedKm: 4, paceSecPerKm: 320)
        let plan = [
            MRPlanWeekSummary(idx: 1, monday: cal.startOfDay(for: d(5)), phase: "늘리기", longRunKm: 16, weeklyKm: 32, point: tempo),
            MRPlanWeekSummary(idx: 2, monday: cal.startOfDay(for: d(12)), phase: "테이퍼", longRunKm: 10, weeklyKm: 30),
        ]
        let j = try #require(MRRaceJourney.make(
            raceName: "춘천마라톤", raceDate: d(18), distanceM: MRDistance.dH, actualMin: 109,
            planWeeks: plan, planStartPredMin: 112, appPredMin: 110,
            vo2Samples: [(date: d(1), value: 45)],
            runs: runs, types: [d(8): .tempo, d(6): .easy], hardStarts: [], pointTypes: [d(8): .tempo]))

        #expect(j.runCount == 5)
        #expect(abs(j.totalKm - 59.1) < 0.01)
        #expect(j.longestKm == 16)                       // 대회 러닝은 빼고
        #expect(j.hardDone == 1 && j.hardPlanned == 1)
        #expect(j.weeks[0].km[.hard] == 8 && j.weeks[0].km[.long] == 16 && j.weeks[0].km[.easy] == 8)
        #expect(j.weeks[1].km[.race] == 21.1)
        #expect(j.weeks[0].symbol == symbolBoth)
        #expect(j.weeks[1].symbol == symbolOver)          // 대회 21.1 > 롱런 계획 10 × 1.1
        // 무엇을 했는지 — 종류 이름·km, 이지는 횟수(토 16km는 종류 없음 → 계획 롱런 80% 이상이라 롱런)
        #expect(j.weeks[0].detail == "템포런 1회 8km · 롱런 1회 16km · 이지 1회 8km")   // 강도 → 롱런 → 이지 순
        #expect(j.weeks[1].detail == "대회 1회 21.1km · 이지 1회 6km")
        #expect(abs((j.appErrPct ?? 0) - 100.0 / 109) < 0.001)
        #expect(j.planStartPredMin == 112)
        #expect(j.vo2 == 45 && j.vo2PredMin != nil)
    }

    @Test func sameTypeIsGroupedWithCountAndKm() throws {
        // 한 주에 템포런 세 번 · 거리주 · 이지 둘 → "템포런 3회 21.4km · 거리주 1회 11.1km · 이지 2회 10km"
        let runs = [run(5, km: 7), run(6, km: 6), run(7, km: 8.4), run(8, km: 11.1), run(9, km: 5), run(10, km: 5), run(18, km: 10)]
        let types: [Date: WorkoutType] = [d(5): .tempo, d(6): .tempo, d(7): .tempo, d(8): .distanceRun, d(9): .easy, d(10): .easy]
        let j = try #require(MRRaceJourney.make(
            raceName: "x", raceDate: d(18), distanceM: MRDistance.d10, actualMin: 53,
            planWeeks: [MRPlanWeekSummary(idx: 1, monday: cal.startOfDay(for: d(5)), phase: "유지", longRunKm: 12, weeklyKm: 40),
                        MRPlanWeekSummary(idx: 2, monday: cal.startOfDay(for: d(12)), phase: "테이퍼", longRunKm: 8, weeklyKm: 15)],
            planStartPredMin: nil, appPredMin: nil, vo2Samples: [],
            runs: runs, types: types, hardStarts: [], pointTypes: [:]))
        #expect(j.weeks[0].detail == "템포런 3회 21.4km · 거리주 1회 11.1km · 이지 2회 10km")
    }

    @Test func heartRateIntensityDoesNotPaintHard() throws {
        // 심박으로 잡힌 '실제 강도'(hardStarts)라도 저장 종류가 이지면 이지로 칠한다
        let runs = [run(6, km: 8), run(18, km: 10)]
        let j = try #require(MRRaceJourney.make(
            raceName: "x", raceDate: d(18), distanceM: MRDistance.d10, actualMin: 53,
            planWeeks: [MRPlanWeekSummary(idx: 1, monday: cal.startOfDay(for: d(5)), phase: "유지", longRunKm: 12, weeklyKm: 20),
                        MRPlanWeekSummary(idx: 2, monday: cal.startOfDay(for: d(12)), phase: "테이퍼", longRunKm: 8, weeklyKm: 15)],
            planStartPredMin: nil, appPredMin: nil, vo2Samples: [],
            runs: runs, types: [d(6): .easy], hardStarts: [d(6)], pointTypes: [:]))
        #expect(j.weeks[0].km[.hard] == nil)
        #expect(j.weeks[0].km[.easy] == 8)
    }

    @Test func noResultNoCard() {
        #expect(MRRaceJourney.make(raceName: "x", raceDate: d(18), distanceM: MRDistance.dH, actualMin: 0,
                                   planWeeks: [MRPlanWeekSummary(idx: 1, monday: d(5), phase: "유지", longRunKm: 10, weeklyKm: 20)],
                                   planStartPredMin: nil, appPredMin: nil, vo2Samples: [],
                                   runs: [], types: [:], hardStarts: [], pointTypes: [:]) == nil)
    }

    @Test func monthLogUsesPastAndCurrentWeeksOnly() throws {
        // 9/28 주(10월에 걸침) · 10/5 · 10/12 · 10/19(미래) — 오늘 10/14
        let runs = [run(-2 + 30, km: 99).withStart(cal.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 7))!),
                    run(2, km: 8), run(6, km: 10), run(13, km: 12)]
        let mons = [cal.date(from: DateComponents(year: 2026, month: 9, day: 28))!, d(5, 0), d(12, 0), d(19, 0)]
        let plan = mons.enumerated().map { i, m in
            MRPlanWeekSummary(idx: i + 1, monday: cal.startOfDay(for: m), phase: "유지", longRunKm: 10, weeklyKm: 30)
        }
        let j = try #require(MRRaceJourney.makeMonth(
            title: "10월 훈련일지", monthStart: d(1, 0), monthEnd: cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!,
            goalKm: 140, planTotalKm: 128, planWeeks: plan, now: d(14),
            runs: runs, types: [:], hardStarts: [], pointTypes: [:]))
        #expect(j.weeks.count == 3)                    // 10/19 주는 아직 아님
        #expect(j.month?.monthKm == 30)                // 9/29 러닝은 10월이 아님
        #expect(j.month?.monthRuns == 3)
        #expect(j.month?.goalKm == 140)
    }
}

private extension MRWorkout {
    func withStart(_ d: Date) -> MRWorkout {
        MRWorkout(start: d, durationMin: durationMin, distanceKm: distanceKm, hrAvg: hrAvg, hrMax: hrMax,
                  tempC: tempC, humidity: humidity, indoor: indoor, isInterval: isInterval)
    }
}
