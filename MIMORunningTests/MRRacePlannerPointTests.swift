import Testing
import Foundation
@testable import MIMORunning

@Suite("MRRacePlanner 포인트 칸", .korean)
struct MRRacePlannerPointTests {

    private func profile(runs: Double) -> MRProfile {
        var p = MRProfile()
        p.weeklyKm4w = 30; p.longestRun16wKm = 14
        p.maxWeeklyKm52w = 45; p.runsPerWeek = runs; p.marathonFinishes = 0
        return p
    }

    private func plan(distanceM: Double = MRDistance.dH, weeks: Int = 20, runs: Double = 4) -> MRRacePlan? {
        let today = Date()
        let race = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: today)!
        return mrBuildPlan(raceDate: race, distanceM: distanceM, today: today,
                           profile: profile(runs: runs), halfEquivMin: 110,
                           easyPaceSecPerKm: 400, heat: MRHeatModel(), raceTempC: 15,
                           runsPerWeek: runs)
    }

    @Test func pointKindMatchesPhase() throws {
        let p = try #require(plan())
        #expect(p.weeks.contains { $0.point != nil })
        for w in p.weeks {
            guard let pt = w.point else { continue }
            if w.phase == "늘리기" {
                #expect(pt.kind == .speed || pt.kind == .tempo)   // 늘리기는 인터벌·템포런 번갈이
            } else {
                #expect(pt.kind == mrPointKind(phase: w.phase))
            }
        }
    }

    @Test func recoveryAndRaceWeekHaveNoPoint() throws {
        let p = try #require(plan())
        #expect(p.weeks.filter { $0.phase == "회복" }.allSatisfy { $0.point == nil })
        let cal = Calendar.current
        let raceWeek = try #require(p.weeks.first { w in
            let end = cal.date(byAdding: .day, value: 7, to: w.monday)!
            return p.raceDate >= w.monday && p.raceDate < end
        })
        #expect(raceWeek.point == nil)
    }

    @Test func pointReplacesOneEasyRunAndKeepsWeeklyTotal() throws {
        let p = try #require(plan())
        let withPoint = p.weeks.filter { $0.point != nil }
        #expect(!withPoint.isEmpty)
        for w in withPoint {
            let parsed = mrParsePlanBreakdown(w.breakdown)
            #expect(parsed.easyRuns == 2)          // 주 4회 → 롱런 1 + 포인트 1 + 이지 2
            // 문구의 "롱런 Nkm"(플래너 표기값 lrDisplay)로 합을 잰다 — longRunKm(0.1 반올림)을 다시 반올림하면 14.45 같은 경계에서 1km 어긋난다
            if let km = parsed.easyKm, let pt = w.point,
               let m = w.breakdown.range(of: #"롱런 ([0-9]+)km"#, options: .regularExpression),
               let longShown = Double(w.breakdown[m].dropFirst(3).dropLast(2)) {
                let sum = longShown + pt.totalKm + km * 2
                #expect(abs(sum - w.weeklyKm) < 0.3)   // 표기 반올림 허용
                #expect(km >= 1.5)
            }
        }
        #expect(p.weeks.filter { $0.point == nil && $0.phase == "늘리기" }
            .allSatisfy { mrParsePlanBreakdown($0.breakdown).easyRuns.map { $0 == 3 } ?? true })
    }

    @Test func threeRunsPerWeekAlternates() throws {
        let p = try #require(plan(runs: 3))
        // 테이퍼를 뺀 포인트 종류 주에서 연달아 두 주 모두 포인트는 없다
        let eligible = p.weeks.filter { mrPointKind(phase: $0.phase).map { $0 != .racePaceShort } ?? false }
        #expect(eligible.count >= 4)
        for (a, b) in zip(eligible, eligible.dropFirst()) {
            #expect(!(a.point != nil && b.point != nil))
        }
        #expect(eligible.contains { $0.point != nil })
    }

    @Test func twoRunsPerWeekHasNoPoint() throws {
        let p = try #require(plan(runs: 2))
        #expect(p.weeks.allSatisfy { $0.point == nil })
    }

    @Test func tenKPlanHasNoBuildUp() throws {
        let p = try #require(plan(distanceM: MRDistance.d10, weeks: 12))
        #expect(p.weeks.allSatisfy { $0.point?.kind != .buildUp })
    }

    @Test func weekAfterTenKTuneUpHasNoPoint() throws {
        let today = Date()
        let cal = Calendar.current
        let race = cal.date(byAdding: .day, value: 7 * 20, to: today)!
        // 8주 뒤 주의 수요일에 10K 튠업
        let thisMon = MRPlanGovernance.weekMonday(of: today)
        let tuneDate = cal.date(byAdding: .day, value: 7 * 8 + 2, to: thisMon)!
        let tune = MRTuneUpRace(date: tuneDate, name: "10K", distanceM: MRDistance.d10, hasOwnPlan: false, ownPlanWeeks: [])
        let p = try #require(mrBuildPlan(raceDate: race, distanceM: MRDistance.dH, today: today,
                                         profile: profile(runs: 4), halfEquivMin: 110,
                                         easyPaceSecPerKm: 400, heat: MRHeatModel(), raceTempC: 15,
                                         runsPerWeek: 4, tuneUps: [tune]))
        let tuneMon = MRPlanGovernance.weekMonday(of: tuneDate)
        let nextMon = cal.date(byAdding: .day, value: 7, to: tuneMon)!
        let after = try #require(p.weeks.first { cal.isDate($0.monday, inSameDayAs: nextMon) })
        #expect(after.point == nil)
        // 대회 뒤 14일 안에 시작하는 주(12일 뒤 월요일)도 없음
        let twoAfter = cal.date(byAdding: .day, value: 14, to: tuneMon)!
        let second = try #require(p.weeks.first { cal.isDate($0.monday, inSameDayAs: twoAfter) })
        #expect(second.point == nil)
    }

    @Test func howToExplainsStructure() {
        let s = MRPlanPoint(kind: .speed, totalKm: 8.2, reps: 4, repKm: 1, sustainedKm: nil, paceSecPerKm: 307)
        #expect(s.howTo == "사이 3분 천천히 조깅 · 앞뒤 조깅 포함 총 8.2km · 예상 5K 기록 기준")
    }

    @Test func buildPhaseAlternatesIntervalAndTempoStartingWithInterval() throws {
        let p = try #require(plan(distanceM: MRDistance.dF, weeks: 24))
        let kinds = p.weeks.filter { $0.phase == "늘리기" }.compactMap(\.point?.kind)
        #expect(kinds.count >= 2)
        for (i, k) in kinds.enumerated() {
            #expect(k == (i % 2 == 0 ? .speed : .tempo))
        }
    }

    @Test func fullRacePaceWeeksDoNotStackTargetLongRuns() throws {
        var pr = profile(runs: 5)
        pr.weeklyKm4w = 45; pr.longestRun16wKm = 22; pr.maxWeeklyKm52w = 60
        let today = Date()
        let race = Calendar.current.date(byAdding: .day, value: 7 * 24, to: today)!
        let p = try #require(mrBuildPlan(raceDate: race, distanceM: MRDistance.dF, today: today,
                                         profile: pr, halfEquivMin: 110, easyPaceSecPerKm: 400,
                                         heat: MRHeatModel(), raceTempC: 15, runsPerWeek: 5))
        let rp = p.weeks.filter { $0.phase == "대회 페이스" }
        #expect(rp.count >= 2)
        let target = p.targetLongKm
        for (a, b) in zip(rp, rp.dropFirst()) {
            #expect(!(a.longRunKm >= target - 0.1 && b.longRunKm >= target - 0.1))
        }
        #expect(rp.allSatisfy { $0.point.map { $0.kind != .buildUp || $0.totalKm <= 10 } ?? true })
    }
}
