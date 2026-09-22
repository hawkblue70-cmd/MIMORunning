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

    @Test func fourConsecutiveDaysIsRestEvenWithGoodHRV() {
        var runs = steadyRuns()
        // 1·2·3·4일 전 연속. 끼워 넣는 두 번은 20분 — 최근 7일 분 합이 급증(1.3배)에 걸리지 않게(190/150 = 1.27)
        runs.append(contentsOf: [run(daysAgo: 4, minutes: 20), run(daysAgo: 2, minutes: 20)])
        runs.sort { $0.start < $1.start }
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 37))
        #expect(r?.level == .rest)
        #expect(r?.line == "오늘은 휴식이나 짧은 이지 · 4일 연속")
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
        // 추세는 보통(31)인데 어젯밤만 기준선 − 1SD(SD 하한 3) 아래(26)
        let r = readiness(runs: steadyRuns(), nights: nights(base: 30, recent: 31, todayValue: 26))
        #expect(r?.level == .rest)
        #expect(r?.line == "오늘은 휴식이나 짧은 이지 · 어젯밤 HRV 유독 낮음")
    }

    // MARK: 규칙 4~5

    @Test func hardRunYesterdayIsEasy() {
        var runs = steadyRuns(); runs[runs.count - 1] = run(daysAgo: 1, interval: true)
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 37))
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
        // 2일 전 인터벌 20분을 끼워 넣는다(급증 아님: 170/150) · HRV 범위 안(30)
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
    }

    // MARK: 동기화 전

    @Test func pendingLastNightAppendsNote() {
        let r = readiness(runs: steadyRuns(), nights: nights(base: 30, recent: 37, todayNight: false))
        #expect(r?.hrvPending == true)
        #expect(r?.line == "오늘은 강도 OK · HRV 좋음 · 어젯밤 HRV 동기화 전")
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
        // 만성 4주 중 2주만 러닝 → 비율 없음(급증으로 오판하지 않는다)
        let runs = [12, 9, 2].map { run(daysAgo: $0, minutes: 60) }
        #expect(mrDurationAcuteChronic(runs: runs, asOf: now).ratio == nil)
    }

    @Test func durationAcuteChronicRatio() {
        // 직전 28일(−34…−7): 4주 × 60분 = 240분/주 → 만성 60. 최근 7일: 90분 → 1.5
        var runs = [30, 23, 16, 9].map { run(daysAgo: $0, minutes: 60) }
        runs.append(run(daysAgo: 2, minutes: 90))
        let a = mrDurationAcuteChronic(runs: runs, asOf: now)
        #expect(a.ratio == 1.5)
        #expect(a.rising == true)   // 직전 7일(−13…−7)은 60분(9일 전) → 90 ≥ 69
    }
}
