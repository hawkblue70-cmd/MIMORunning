import Testing
import Foundation
@testable import MIMORunning

@Suite("아침 러닝 제안", .korean)
struct MRReadinessTests {

    private let cal = Calendar.current
    private let now: Date = {
        // 오늘 08:00 — 아침에 앱을 연 상황
        let c = Calendar.current
        return c.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
    }()

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: now)!)
    }

    private func run(daysAgo: Int, minutes: Double = 50, hr: Double = 140, interval: Bool = false) -> MRWorkout {
        MRWorkout(start: day(-daysAgo).addingTimeInterval(7 * 3600), durationMin: minutes, distanceKm: 8,
                  hrAvg: hr, hrMax: 170, tempC: 15, humidity: nil, indoor: false, isInterval: interval)
    }

    /// 5주간 주 3회 이지런(50분), 마지막은 어제. 만성 4주(7…34일)가 모두 채워져 분 비율이 1.0 — 급증·상승 없음.
    private func steadyRuns() -> [MRWorkout] {
        [34, 32, 29, 27, 25, 22, 20, 18, 15, 13, 11, 8, 6, 3, 1].map { run(daysAgo: $0) }
    }

    /// 4주(−34…−7) base, 7일(−6…0) recent. `todayNight: false`면 오늘 키 밤을 뺀다(동기화 전).
    private func nights(base: Double, recent: Double, baseJitter: [Double] = [1, -1],
                        todayNight: Bool = true, todayValue: Double? = nil) -> [(date: Date, value: Double)] {
        var out: [(date: Date, value: Double)] = []
        for i in 0..<28 { out.append((day(-34 + i), base + baseJitter[i % baseJitter.count])) }
        for i in 0..<7 {
            let d = -6 + i
            if d == 0 && !todayNight { continue }
            out.append((day(d), d == 0 ? (todayValue ?? recent) : recent))
        }
        return out
    }

    private var phys: MRPhysiology {
        var p = MRPhysiology()
        p.lt1HR = MRInference(value: 150, confidence: .high, basis: [])
        return p
    }

    private func readiness(runs: [MRWorkout], nights: [(date: Date, value: Double)] = [],
                           planPhase: String? = nil) -> MRReadiness? {
        mrReadiness(runs: runs, phys: phys, heatHR: MRHeatHRModel(), hrvNights: nights,
                    planPhase: planPhase, asOf: now)
    }

    // MARK: 규칙 0

    @Test func nilWhenAlreadyRanToday() {
        var runs = steadyRuns(); runs.append(run(daysAgo: 0))
        #expect(readiness(runs: runs, nights: nights(base: 30, recent: 37)) == nil)
    }

    @Test func nilWithoutRuns() {
        #expect(readiness(runs: [], nights: nights(base: 30, recent: 37)) == nil)
    }

    // MARK: 규칙 1~2 우선순위

    @Test func recoveryWeekBeatsGoodHRV() {
        let r = readiness(runs: steadyRuns(), nights: nights(base: 30, recent: 37), planPhase: "회복")
        #expect(r?.level == .easy)
        #expect(r?.line == "오늘은 이지런 · 대회 계획 회복 주")
    }

    @Test func taperWeekIsEasy() {
        let r = readiness(runs: steadyRuns(), nights: nights(base: 30, recent: 37), planPhase: "테이퍼")
        #expect(r?.line == "오늘은 이지런 · 대회 계획 테이퍼 주")
    }

    @Test func fourConsecutiveDaysIsEasyEvenWithGoodHRV() {
        // steadyRuns는 평소 1일 구간뿐 → 문턱 4. 나흘 연속이면 휴식이 아니라 이지런(강도만 뺀다)
        var runs = steadyRuns()
        // 1·2·3·4일 전 연속. 끼워 넣는 두 번은 20분 — 최근 7일 분 합이 급증(1.3배)에 걸리지 않게(190/150 = 1.27, 여유 5분)
        runs.append(contentsOf: [run(daysAgo: 4, minutes: 20), run(daysAgo: 2, minutes: 20)])
        runs.sort { $0.start < $1.start }
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 37))
        #expect(r?.level == .easy)
        #expect(r?.line == "오늘은 이지런 · 4일 연속")
        // 둘째 줄: 왜 + 데이터(HRV 어젯밤·이번 주·평소·상태어, 연속일). 마지막 고강도는 없으니 생략
        #expect(r?.why == "4일 내리 달렸어요. 평소보다 긴 연속이라 오늘은 강도를 빼고 이지런으로 가세요.")
        // 어젯밤 37은 평소 30보다 15% 넘게 높다 → "(평소보다 높음)"
        #expect(r?.data == ["HRV 어젯밤 37(평소보다 높음) · 7일 평균 37(좋음) · 4주 평균 30ms", "4일 연속"])
        #expect(r?.detail == "4일 내리 달렸어요. 평소보다 긴 연속이라 오늘은 강도를 빼고 이지런으로 가세요. HRV 어젯밤 37(평소보다 높음) · 7일 평균 37(좋음) · 4주 평균 30ms · 4일 연속")
    }

    /// 평소 주 4일 연속(월~목)으로 뛰는 사람 — 4주 전부 4일 구간. 각 러닝 30분이라 급증·상승 없음.
    private func fourDayStreakRuns(currentStreak: Int) -> [MRWorkout] {
        var days: [Int] = []
        for w in 1...4 { days.append(contentsOf: [7 * w + 3, 7 * w + 2, 7 * w + 1, 7 * w]) }   // 10~7, 17~14, 24~21, 31~28
        days.append(contentsOf: (1...currentStreak).reversed().map { $0 })                       // 현재 구간: N…1일 전
        return days.sorted(by: >).map { run(daysAgo: $0, minutes: 30) }
    }

    @Test func habitualFourDayStreakIsNotFlaggedAtFour() {
        // 평소 4일 연속 → 문턱 5. 오늘 4일째면 연속 판정 없이 HRV로 넘어간다
        let r = readiness(runs: fourDayStreakRuns(currentStreak: 4), nights: nights(base: 30, recent: 37))
        #expect(r?.level == .go)
        #expect(r?.reasons.first == "HRV 좋음")
        #expect(mrTypicalStreakDays(runs: fourDayStreakRuns(currentStreak: 4), asOf: now) == 4)
    }

    @Test func habitualFourDayStreakIsFlaggedAtFive() {
        let r = readiness(runs: fourDayStreakRuns(currentStreak: 5), nights: nights(base: 30, recent: 37))
        #expect(r?.level == .easy)
        #expect(r?.line == "오늘은 이지런 · 5일 연속")
    }

    @Test func consecutiveThresholdIsClamped() {
        #expect(mrConsecutiveThreshold(typicalStreak: nil) == 4)
        #expect(mrConsecutiveThreshold(typicalStreak: 1) == 4)
        #expect(mrConsecutiveThreshold(typicalStreak: 4) == 5)
        #expect(mrConsecutiveThreshold(typicalStreak: 9) == 6)
    }

    @Test func loadSpikeIsRest() {
        // 직전 4주는 짧게, 최근 7일은 길게 → ACWR > 1.3
        var runs = [27, 25, 22, 20, 18, 15, 13, 11, 8].map { run(daysAgo: $0, minutes: 30) }
        runs.append(contentsOf: [6, 4, 2, 1].map { run(daysAgo: $0, minutes: 90) })
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 37))
        #expect(r?.level == .rest)
        #expect(r?.reasons.first == "부하 급증")
    }

    // MARK: 규칙 3

    @Test func lowHRVIsRest() {
        let r = readiness(runs: steadyRuns(), nights: nights(base: 30, recent: 25))
        #expect(r?.level == .rest)
        #expect(r?.line == "오늘은 휴식이나 짧은 이지 · HRV 낮음")
    }

    @Test func volatileHRVIsRest() {
        var n = nights(base: 30, recent: 30)
        // 7일을 크게 흔든다(±7) — 4주(±1)의 1.5배 초과
        n = n.map { $0.date >= day(-6) ? ($0.date, 30 + (cal.component(.day, from: $0.date) % 2 == 0 ? 7 : -7)) : $0 }
        let r = readiness(runs: steadyRuns(), nights: n)
        #expect(r?.level == .rest)
        #expect(r?.reasons.first == "HRV 불안정")
    }

    @Test func unusuallyLowLastNightIsRestEvenIfTrendNormal() {
        // 4주가 원래 ±4로 출렁이는 사람(SD ≈ 4.1) · 7일은 31로 보통 · 어젯밤만 22(기준선 30의 −27%, 문턱 −15% 아래).
        // 4주가 고른(±1) 픽스처면 어젯밤 하나로 7일 CV가 1.5배를 넘어 '불안정'이 먼저 잡힌다 — 그건 의도된 우선순위.
        let r = readiness(runs: steadyRuns(), nights: nights(base: 30, recent: 31, baseJitter: [4, -4], todayValue: 22))
        #expect(r?.level == .rest)
        #expect(r?.line == "오늘은 휴식이나 짧은 이지 · 어젯밤 HRV 22ms, 평소 30ms보다 낮음")
    }

    @Test func mildlyLowLastNightIsNotFlagged() {
        // 어젯밤 26 — 기준선 30의 −13%, 문턱 −15% 안 → 하룻밤 잡음으로 보고 HRV로 휴식을 권하지 않는다
        let r = readiness(runs: steadyRuns(), nights: nights(base: 30, recent: 31, baseJitter: [4, -4], todayValue: 26))
        #expect(r?.reasons.contains { $0.contains("어젯밤 HRV") } == false)
    }

    @Test func lowLastNightAfterHardRunNamesTheCause() {
        // 어제 인터벌 + 어젯밤 HRV 급락 → 휴식 판정은 그대로, 원인(어제 고강도)을 앞에 붙인다
        var runs = steadyRuns(); runs[runs.count - 1] = run(daysAgo: 1, interval: true)
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 31, baseJitter: [4, -4], todayValue: 22))
        #expect(r?.level == .rest)
        #expect(r?.line == "오늘은 휴식이나 짧은 이지 · 어제 고강도 · 어젯밤 HRV 22ms, 평소 30ms보다 낮음")
    }

    @Test func lowHRVAfterHardRunNamesTheCause() {
        var runs = steadyRuns(); runs[runs.count - 1] = run(daysAgo: 1, interval: true)
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 25))
        #expect(r?.line == "오늘은 휴식이나 짧은 이지 · 어제 고강도 · HRV 낮음")
    }

    // MARK: 규칙 4~5

    @Test func hardRunYesterdayIsEasy() {
        var runs = steadyRuns(); runs[runs.count - 1] = run(daysAgo: 1, interval: true)
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 37))
        #expect(r?.level == .easy)
        #expect(r?.line == "오늘은 이지런 · 어제 고강도")
    }

    @Test func appClassifiedHardRunYesterdayIsEasy() {
        // 어제 러닝이 엔진 기준으론 이지(심박 140, 구조화 운동 아님)라도 앱이 인터벌로 분류했으면 "어제 고강도"
        let runs = steadyRuns()
        let r = mrReadiness(runs: runs, phys: phys, heatHR: MRHeatHRModel(), hrvNights: nights(base: 30, recent: 37),
                            planPhase: nil, asOf: now, hardRunStarts: [runs.last!.start])
        #expect(r?.level == .easy)
        #expect(r?.line == "오늘은 이지런 · 어제 고강도")
    }

    @Test func risingLoadWithNormalHRVIsEasy() {
        // 직전 7일 짧고(90분) 최근 7일 길지만(180분) 4주 대비 급증은 아님(만성 630/4 = 157.5 → 1.14)
        var runs = [34, 32, 29, 27, 25, 22, 20, 18, 15].map { run(daysAgo: $0, minutes: 60) }
        runs.append(contentsOf: [13, 11, 8].map { run(daysAgo: $0, minutes: 30) })
        runs.append(contentsOf: [6, 3, 1].map { run(daysAgo: $0, minutes: 60) })
        // HRV는 기준선과 같은 30 — 위도 안정 상승도 아님
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 30))
        #expect(r?.level == .easy)
        #expect(r?.reasons.first == "부하 오르는 중")
    }

    @Test func risingLoadWithGoodHRVIsGo() {
        var runs = [34, 32, 29, 27, 25, 22, 20, 18, 15].map { run(daysAgo: $0, minutes: 60) }
        runs.append(contentsOf: [13, 11, 8].map { run(daysAgo: $0, minutes: 30) })
        runs.append(contentsOf: [6, 3, 1].map { run(daysAgo: $0, minutes: 60) })
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 37))
        #expect(r?.level == .go)
    }

    // MARK: 규칙 6~7

    @Test func goodHRVIsGoWithLastHardDays() {
        var runs = steadyRuns(); runs[runs.count - 3] = run(daysAgo: 6, interval: true)
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 37))
        #expect(r?.level == .go)
        #expect(r?.line == "오늘은 강도 OK · HRV 좋음 · 마지막 고강도 6일 전")
        #expect(r?.why == "이번 주 HRV가 평소 위로 안정적이에요. 강도를 소화할 준비가 된 신호예요.")
        #expect(r?.data == ["HRV 어젯밤 37(평소보다 높음) · 7일 평균 37(좋음) · 4주 평균 30ms", "마지막 고강도 6일 전"])
    }

    @Test func goodHRVWithoutRecentHardOmitsThatPiece() {
        let r = readiness(runs: steadyRuns(), nights: nights(base: 30, recent: 37))
        #expect(r?.line == "오늘은 강도 OK · HRV 좋음")
    }

    @Test func normalHRVIsGoWhenLoadHasRoom() {
        // HRV는 기준선과 같은 30(범위 안, 안정 상승 아님) · 마지막 고강도 6일 전 → 부하가 넉넉하니 강도 OK
        var runs = steadyRuns(); runs[runs.count - 3] = run(daysAgo: 6, interval: true)
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 30))
        #expect(r?.level == .go)
        #expect(r?.line == "오늘은 강도 OK · HRV 보통 · 마지막 고강도 6일 전")
    }

    @Test func normalHRVIsEasyWhenHardWasTwoDaysAgo() {
        // 2일 전 인터벌 20분을 끼워 넣는다(급증 아님: 170/150 · 상승 아님: 170 < 172.5, 여유 2.5분) · HRV 범위 안(30)
        var runs = steadyRuns(); runs.append(run(daysAgo: 2, minutes: 20, interval: true))
        runs.sort { $0.start < $1.start }
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 30))
        #expect(r?.level == .easy)
        #expect(r?.line == "오늘은 이지런 · 고강도 2일 전 · 하루 더 여유")
    }

    @Test func noHRVDataUsesLoadOnly() {
        let r = readiness(runs: steadyRuns(), nights: [])
        #expect(r?.level == .go)
        #expect(r?.line == "오늘은 강도 OK")
        #expect(r?.hrvPending == false)
        // HRV 자료가 없으면 데이터 조각도 없고 왜 문장만 남는다
        #expect(r?.data == [])
        #expect(r?.detail == "부하가 안정돼 있어요. 계획한 강도를 넣어도 돼요.")
    }

    // MARK: 동기화 전

    @Test func pendingLastNightAppendsNote() {
        let r = readiness(runs: steadyRuns(), nights: nights(base: 30, recent: 37, todayNight: false))
        #expect(r?.hrvPending == true)
        #expect(r?.line == "오늘은 강도 OK · HRV 좋음 · 어젯밤 HRV 동기화 전")
        // 어젯밤이 없으면 데이터 조각도 이번 주·평소만
        #expect(r?.data == ["HRV 7일 평균 37(좋음) · 4주 평균 30ms"])
    }

    @Test func eveningSampleKeyedTomorrowDoesNotHidePending() {
        // 낮 15시 이후 샘플이 내일 키로 붙어 last가 내일이어도 오늘 키가 있으면 동기화 전이 아니다
        var n = nights(base: 30, recent: 37)
        n.append((day(1), 20))
        let r = readiness(runs: steadyRuns(), nights: n)
        #expect(r?.hrvPending == false)
        #expect(r?.line == "오늘은 강도 OK · HRV 좋음")
    }

    // MARK: 대회 훈련 계획 → 오늘 세션

    private func plan(phase: String = "늘리기", longRunKm: Double = 14, weeklyKm: Double = 38, easyRuns: Int = 3,
                      racePace: Double? = nil, segMin: Int? = nil, daysToRace: Int = 30) -> MRPlanWeekContext {
        MRPlanWeekContext(phase: phase, longRunKm: longRunKm, weeklyKm: weeklyKm, easyRuns: easyRuns,
                          racePaceSecPerKm: racePace, racePaceSegmentMin: segMin, daysToRace: daysToRace)
    }

    /// `asOf` 기준 이번 주 월요일에서 `offset`일 뒤 07:00. 이번 주 러닝 픽스처용.
    private func thisWeekRun(dayOffset: Int, km: Double, asOf: Date) -> MRWorkout {
        let monday = MRPlanGovernance.weekMonday(of: asOf)
        let start = cal.date(byAdding: .day, value: dayOffset, to: monday)!.addingTimeInterval(7 * 3600)
        return MRWorkout(start: start, durationMin: km * 6.5, distanceKm: km, hrAvg: 140, hrMax: 170,
                         tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }

    /// 8주 동안 매주 토요일 롱런 14km + 화·목 이지 8km — 롱런 습관 요일 = 토(7). 이번 주는 비어 있다.
    private func saturdayLongRunHistory(asOf: Date) -> [MRWorkout] {
        let monday = MRPlanGovernance.weekMonday(of: asOf)
        var out: [MRWorkout] = []
        for w in 1...8 {
            let mon = cal.date(byAdding: .day, value: -7 * w, to: monday)!
            for (off, km) in [(1, 8.0), (3, 8.0), (5, 14.0)] {
                out.append(MRWorkout(start: cal.date(byAdding: .day, value: off, to: mon)!.addingTimeInterval(7 * 3600),
                                     durationMin: km * 6.5, distanceKm: km, hrAvg: 140, hrMax: 170,
                                     tempC: 15, humidity: nil, indoor: false, isInterval: false))
            }
        }
        return out
    }

    /// 이번 주 특정 요일(1=일…7=토) 08:00
    private func thisWeek(weekday: Int) -> Date {
        let monday = MRPlanGovernance.weekMonday(of: now)
        let offset = (weekday + 5) % 7   // 월=0 … 일=6
        return cal.date(byAdding: .day, value: offset, to: monday)!.addingTimeInterval(8 * 3600)
    }

    @Test func parsesEasyCountAndDistanceFromPlanText() {
        #expect(mrParsePlanBreakdown("롱런 19km + 이지 6.4km × 4회") == (easyRuns: 4, easyKm: 6.4))
        #expect(mrParsePlanBreakdown("롱런 19km · 마지막 15분은 5'22\"/km + 이지 6km × 4회") == (easyRuns: 4, easyKm: 6.0))
        #expect(mrParsePlanBreakdown("롱런 12km + 짧게 5km × 3회 · 강도는 그대로") == (easyRuns: 3, easyKm: 5.0))
        #expect(mrParsePlanBreakdown("롱런 10km + 이지 3회") == (easyRuns: 3, easyKm: nil))
        #expect(mrParsePlanBreakdown("10K 계획을 따릅니다 · 롱런 14km + 이지 7km × 2회") == (easyRuns: 2, easyKm: 7.0))
        #expect(mrParsePlanBreakdown("Long run 19km + Easy 6.4km × 4x") == (easyRuns: 4, easyKm: 6.4))
        #expect(mrParsePlanBreakdown("") == (easyRuns: nil, easyKm: nil))
    }

    @Test func planEasyKmOverridesComputedDistance() {
        let wed = thisWeek(weekday: 4)
        var p = plan(longRunKm: 19, weeklyKm: 45, easyRuns: 4)
        p.easyKm = 6.4
        let s = mrSessionSuggestion(level: .easy, plan: p, runs: saturdayLongRunHistory(asOf: wed), asOf: wed)
        #expect(s?.session == "이지 6.4km")
        #expect(s?.progress.contains("이지 0/4회") == true)
    }

    @Test func habitualLongRunWeekdayIsSaturday() {
        #expect(mrHabitualLongRunWeekday(runs: saturdayLongRunHistory(asOf: now), asOf: now) == 7)
    }

    @Test func goOnHabitualDayWithLongRunLeftSuggestsLongRun() {
        let sat = thisWeek(weekday: 7)
        var runs = saturdayLongRunHistory(asOf: sat)
        runs.append(contentsOf: [thisWeekRun(dayOffset: 1, km: 8, asOf: sat), thisWeekRun(dayOffset: 3, km: 8, asOf: sat)])
        let s = mrSessionSuggestion(level: .go, plan: plan(), runs: runs, asOf: sat)
        #expect(s?.session == "롱런 14km")
        #expect(s?.progress == "이번 주 롱런 아직 · 이지 2/3회")
    }

    @Test func goOnOtherDayKeepsEasyAndNotesLongRunPending() {
        let wed = thisWeek(weekday: 4)
        var runs = saturdayLongRunHistory(asOf: wed)
        runs.append(thisWeekRun(dayOffset: 1, km: 8, asOf: wed))
        let s = mrSessionSuggestion(level: .go, plan: plan(), runs: runs, asOf: wed)
        #expect(s?.session == "이지 8km")
        #expect(s?.isLongRun == false)
        #expect(s?.whyNote == "여유는 토요일 롱런에 쓰세요.")
        #expect(s?.progress == "이번 주 롱런 아직 · 이지 1/3회")
    }

    @Test func goWithEasySessionReadsAsEasyWithRoom() {
        // 강도 OK인데 오늘 세션이 이지 → "오늘은 이지 8km · 강도 여유 있음", 왜 문장 끝에 롱런 요일
        let wed = thisWeek(weekday: 4)
        let r = mrReadiness(runs: saturdayLongRunHistory(asOf: wed), phys: phys, heatHR: MRHeatHRModel(),
                            hrvNights: [], planPhase: nil, asOf: wed, planWeek: plan())
        #expect(r?.level == .go)
        #expect(r?.line == "오늘은 이지 8km · 강도 여유 있음")
        #expect(r?.why.hasSuffix("여유는 토요일 롱런에 쓰세요.") == true)
    }

    @Test func goWithLongRunKeepsHardOkHead() {
        let sat = thisWeek(weekday: 7)
        let r = mrReadiness(runs: saturdayLongRunHistory(asOf: sat), phys: phys, heatHR: MRHeatHRModel(),
                            hrvNights: [], planPhase: nil, asOf: sat, planWeek: plan())
        #expect(r?.line == "오늘은 강도 OK · 롱런 14km")
    }

    @Test func goWithTwoDaysLeftSuggestsLongRunEvenOffHabit() {
        // 습관은 토요일인데 이미 토요일을 지나 일요일(남은 날 1) — 롱런이 남았으면 오늘
        let sunday = cal.date(byAdding: .day, value: 6, to: MRPlanGovernance.weekMonday(of: now))!.addingTimeInterval(8 * 3600)
        let runs = saturdayLongRunHistory(asOf: sunday)
        let s = mrSessionSuggestion(level: .go, plan: plan(), runs: runs, asOf: sunday)
        #expect(s?.session == "롱런 14km")
    }

    @Test func racePaceWeekAppendsSegment() {
        let sat = thisWeek(weekday: 7)
        let s = mrSessionSuggestion(level: .go, plan: plan(phase: "대회 페이스", racePace: 322, segMin: 15),
                                    runs: saturdayLongRunHistory(asOf: sat), asOf: sat)
        #expect(s?.session == "롱런 14km, 마지막 15분 5'22\"")
    }

    @Test func easyLevelSuggestsEasyWithDaysLeft() {
        let wed = thisWeek(weekday: 4)
        let s = mrSessionSuggestion(level: .easy, plan: plan(), runs: saturdayLongRunHistory(asOf: wed), asOf: wed)
        #expect(s?.session == "이지 8km")
        #expect(s?.progress == "이번 주 롱런 아직 · 이지 0/3회 · 5일 남음")
    }

    @Test func restLevelHasNoSessionAndWarnsLateInWeek() {
        let sat = thisWeek(weekday: 7)
        let s = mrSessionSuggestion(level: .rest, plan: plan(), runs: saturdayLongRunHistory(asOf: sat), asOf: sat)
        #expect(s?.session == nil)
        #expect(s?.progress == "이번 주 롱런 아직 · 이지 0/3회 · 롱런은 이번 주 못 하면 다음 주로")
    }

    @Test func raceWeekYieldsNothing() {
        let sat = thisWeek(weekday: 7)
        #expect(mrSessionSuggestion(level: .go, plan: plan(daysToRace: 5), runs: saturdayLongRunHistory(asOf: sat), asOf: sat) == nil)
    }

    @Test func longRunCountsDoneAtEightyPercent() {
        let sun = cal.date(byAdding: .day, value: 6, to: MRPlanGovernance.weekMonday(of: now))!.addingTimeInterval(8 * 3600)
        var runs = saturdayLongRunHistory(asOf: sun)
        runs.append(thisWeekRun(dayOffset: 5, km: 11.5, asOf: sun))   // 14 × 0.8 = 11.2 이상 → 완료
        let s = mrSessionSuggestion(level: .go, plan: plan(), runs: runs, asOf: sun)
        #expect(s?.session == "이지 8km")
        #expect(s?.progress == "이번 주 롱런 완료 · 이지 0/3회")
    }

    @Test func everythingDoneSaysPlanComplete() {
        let sun = cal.date(byAdding: .day, value: 6, to: MRPlanGovernance.weekMonday(of: now))!.addingTimeInterval(8 * 3600)
        var runs = saturdayLongRunHistory(asOf: sun)
        runs.append(contentsOf: [1, 2, 3].map { thisWeekRun(dayOffset: $0, km: 8, asOf: sun) })
        runs.append(thisWeekRun(dayOffset: 5, km: 14, asOf: sun))
        let s = mrSessionSuggestion(level: .go, plan: plan(), runs: runs, asOf: sun)
        #expect(s?.session == nil)
        #expect(s?.progress == "이번 주 계획 완료")
    }

    @Test func readinessLineUsesSessionWhenPlanPresent() {
        // 판정 줄이 "판정어 · 세션"이 되고 근거는 둘째 줄로 — 이지 판정(어제 고강도) + 계획
        let wed = thisWeek(weekday: 4)
        var runs = saturdayLongRunHistory(asOf: wed)
        runs.append(MRWorkout(start: cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: wed))!.addingTimeInterval(7 * 3600),
                              durationMin: 45, distanceKm: 7, hrAvg: 140, hrMax: 170, tempC: 15, humidity: nil, indoor: false, isInterval: true))
        let r = mrReadiness(runs: runs, phys: phys, heatHR: MRHeatHRModel(), hrvNights: [], planPhase: nil, asOf: wed, planWeek: plan())
        #expect(r?.level == .easy)
        #expect(r?.line == "오늘은 이지런 · 이지 8km")
        #expect(r?.planLine == "이번 주 롱런 아직 · 이지 1/3회 · 5일 남음")
        #expect(r?.detail.contains("이번 주 롱런") == false)   // 계획 진행은 셋째 줄로 따로
    }

    // MARK: 헬퍼

    @Test func consecutiveDaysEndingYesterday() {
        let runs = [5, 3, 2, 1].map { run(daysAgo: $0) }
        #expect(mrConsecutiveRunDays(runs: runs, asOf: now) == 3)
    }

    @Test func consecutiveDaysIsZeroWhenLastRunTwoDaysAgo() {
        let runs = [4, 3, 2].map { run(daysAgo: $0) }
        #expect(mrConsecutiveRunDays(runs: runs, asOf: now) == 0)
    }

    @Test func durationAcuteChronicNeedsThreeWeeksOfData() {
        // 만성 4주 중 1주(7…13일)만 러닝 → 비율 없음(급증으로 오판하지 않는다)
        let runs = [12, 9, 2].map { run(daysAgo: $0, minutes: 60) }
        #expect(mrDurationAcuteChronic(runs: runs, asOf: now).ratio == nil)
    }

    @Test func durationAcuteChronicRatio() {
        // 직전 28일(−34…−7): 주 1회 60분 × 4주 = 240분 합 → 주 60분. 최근 7일: 90분 → 1.5
        var runs = [30, 23, 16, 9].map { run(daysAgo: $0, minutes: 60) }
        runs.append(run(daysAgo: 2, minutes: 90))
        let a = mrDurationAcuteChronic(runs: runs, asOf: now)
        #expect(a.ratio == 1.5)
        #expect(a.rising == true)   // 직전 7일(−13…−7)은 60분(9일 전) → 90 ≥ 69
    }
}
