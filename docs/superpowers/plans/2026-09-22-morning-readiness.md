# 아침 러닝 제안(오늘 강도 게이트) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아침 수면 HRV 추세와 최근 부하로 "오늘은 강도 OK / 이지런 / 휴식이나 짧은 이지" 한 줄을 만들어 홈 오늘 카드의 연속 줄 바로 아래에 띄우고, 앱이 앞으로 올 때 어젯밤 HRV를 다시 읽는다.

**Architecture:** 순수 함수 `mrReadiness`(Engine/MRReadiness.swift)가 `MRWorkout` 목록·HRV 밤 시계열·플랜 단계로 판정과 문장을 만든다. `mrTodayCard`가 그것을 `readinessLine`으로 담고, `MREngineStore`는 오늘 카드 생성을 헬퍼 하나로 모으고 `refreshHRVIfStale()`를 제공한다. 뷰는 문자열 한 줄만 그린다.

**Tech Stack:** Swift 6 · SwiftUI · Swift Testing(`@Test`) + XCTest(오늘 카드 기존 테스트) · HealthKit · Xcode 26.3

**스펙:** `docs/superpowers/specs/2026-09-22-morning-readiness-design.md`

---

## 파일 구조

| 파일 | 책임 | 작업 |
|---|---|---|
| `MIMORunning/Engine/MRReadiness.swift` | `MRReadiness` · `mrReadiness` · `mrConsecutiveRunDays` · `mrDurationAcuteChronic` | 생성 |
| `MIMORunning/Engine/MRTodayCard.swift` | `MRTodayCard.readinessLine/readinessLevel` · `mrTodayCard(heatHR:hrvNights:planPhase:)` | 수정 |
| `MIMORunning/Engine/MREngineStore.swift` | `buildTodayCard(runs:now:)` 헬퍼로 5곳 통합 · HRV 재조회 조건에 "오늘 밤 없음" · `refreshHRVIfStale()` | 수정 |
| `MIMORunning/Views/MRTodayCardView.swift` | 연속 줄 아래 `readinessLine` | 수정 |
| `MIMORunning/MIMORunningApp.swift` | `scenePhase == .active` → `refreshHRVIfStale()` | 수정 |
| `MIMORunningTests/MRReadinessTests.swift` | 규칙·우선순위·헬퍼 | 생성 |
| `MIMORunningTests/MRTodayCardTests.swift` | `readinessLine` 채움·오늘 뛴 날 nil | 수정 |

**검증 명령 — 에이전트는 이것만 쓴다.**

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -10
```

기대 출력: `** TEST BUILD SUCCEEDED **`. `xcodebuild test`·시뮬레이터 부팅 금지(사용자 지시). 테스트는 작성만.

> **git 규칙.** 같은 브랜치(`crew`)에 다른 세션이 동시에 커밋한다. `git add -A`·`git add .`·`git stash` 금지. 내가 고친 파일만 경로로 `git add`. 커밋 직후 `git show --stat HEAD` 확인. 새 Swift 파일은 디렉터리에 넣으면 잡힌다(`.pbxproj` 수정 없음).

**참고 타입(기존)**
- `MRWorkout(start:durationMin:distanceKm:hrAvg:hrMax:tempC:humidity:indoor:isInterval:)` · `.date`(자정) — `Engine/MRTypes.swift`
- `mrRecentHardRunCount(runs:phys:heatHR:days:asOf:) -> (hard: Int, total: Int, lastHardDaysAgo: Int?)` · `mrHRVTrend(nights:asOf:) -> MRHRVTrend?`(`isReadyHigh`·`isSuppressed`·`isVolatile`·`state`·`baseline`·`baselineSD`) — `Engine/MRHRVTrend.swift`
- `MRTodayCard` · `mrTodayCard(runs:phys:plans:raceDayCardVisible:advice:asOf:)` — `Engine/MRTodayCard.swift`
- `MREngineStore.governingPlanWeek(for:) -> (plan: MRRacePlan, week: MRPlanWeek)?`(`week.phase`) · `hrvNights` · `hrvLastFetchedAt` · `recomputeTodayCard()` — `Engine/MREngineStore.swift`
- `AppLanguage.shared.s(ko, en)` · `Theme.positive`(초록) · `Theme.time`(노랑) · `Color(hex:)`

---

### Task 1: 판정 엔진 `MRReadiness`

**Files:**
- Create: `MIMORunning/Engine/MRReadiness.swift`
- Create: `MIMORunningTests/MRReadinessTests.swift`

- [ ] **Step 1: 테스트를 먼저 쓴다**

```swift
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

    /// 4주간 2~3일 간격 이지런, 마지막은 어제. 분 합이 고르다(급증·상승 없음).
    private func steadyRuns() -> [MRWorkout] {
        [27, 25, 22, 20, 18, 15, 13, 11, 8, 6, 3, 1].map { run(daysAgo: $0) }
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
        runs.append(contentsOf: [run(daysAgo: 4), run(daysAgo: 2)])   // 1·2·3·4일 전 연속
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
        // 직전 7일 짧고 최근 7일 길지만 4주 대비 급증은 아님
        var runs = [27, 25, 22, 20, 18, 15].map { run(daysAgo: $0, minutes: 60) }
        runs.append(contentsOf: [13, 11, 8].map { run(daysAgo: $0, minutes: 30) })
        runs.append(contentsOf: [6, 3, 1].map { run(daysAgo: $0, minutes: 60) })
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 31))
        #expect(r?.level == .easy)
        #expect(r?.reasons.first == "부하 오르는 중")
    }

    @Test func risingLoadWithGoodHRVIsGo() {
        var runs = [27, 25, 22, 20, 18, 15].map { run(daysAgo: $0, minutes: 60) }
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
        var runs = steadyRuns(); runs[runs.count - 3] = run(daysAgo: 6, interval: true)
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 31))
        #expect(r?.level == .go)
        #expect(r?.line == "오늘은 강도 OK · HRV 보통 · 마지막 고강도 6일 전")
    }

    @Test func normalHRVIsEasyWhenHardWasTwoDaysAgo() {
        var runs = steadyRuns(); runs[runs.count - 1] = run(daysAgo: 1); runs.append(run(daysAgo: 2, interval: true))
        runs.sort { $0.start < $1.start }
        let r = readiness(runs: runs, nights: nights(base: 30, recent: 31))
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

    @Test func durationAcuteChronicRatio() {
        // 직전 28일(−34…−7): 4주 × 60분 = 240분/주 → 만성 60. 최근 7일: 90분 → 1.5
        var runs = [30, 23, 16, 9].map { run(daysAgo: $0, minutes: 60) }
        runs.append(run(daysAgo: 2, minutes: 90))
        let a = mrDurationAcuteChronic(runs: runs, asOf: now)
        #expect(a.ratio == 1.5)
        #expect(a.rising == true)   // 직전 7일(−13…−7)은 60분(9일 전) → 90 ≥ 69
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는 것을 본다** — `cannot find 'mrReadiness' in scope`

- [ ] **Step 3: 구현**

`MIMORunning/Engine/MRReadiness.swift`:

```swift
import Foundation

// MARK: - 아침 러닝 제안 (오늘 강도 게이트)
//
// HRV 기반 훈련 연구(Vesterinen 2016, Javaloyes 2019)는 아침 값으로 그날 강도를 정한다 —
// 정상 범위 안이면 계획대로, 아래면 저강도·휴식. HRV는 종류(인터벌/템포)를 고르지 않는다.
// 이 판정은 "오늘 강도를 내도 되는가"만 답한다. 제안이지 지시가 아니다.

struct MRReadiness: Equatable {
    enum Level: Equatable { case go, easy, rest }
    let level: Level
    /// 근거 조각 — 순서대로 " · "로 이어 붙인다
    let reasons: [String]
    /// 오늘 키의 밤이 아직 없다(워치 동기화 전) — 판정은 어제까지 자료로 그대로 한다
    let hrvPending: Bool

    var line: String {
        let L = AppLanguage.shared
        let head: String = switch level {
        case .go:   L.s("오늘은 강도 OK", "Today: hard is OK")
        case .easy: L.s("오늘은 이지런", "Today: easy run")
        case .rest: L.s("오늘은 휴식이나 짧은 이지", "Today: rest or a short easy run")
        }
        var parts = [head] + reasons
        if hrvPending { parts.append(L.s("어젯밤 HRV 동기화 전", "last night's HRV not synced yet")) }
        return parts.joined(separator: " · ")
    }

    static let spikeRatio = 1.3
    static let risingRatio = 1.15
    static let restConsecutiveDays = 4
    /// 범위 안 HRV에서 강도 OK로 보는 마지막 고강도 최소 일수
    static let normalHRVGoMinDays = 3
    /// 어젯밤 단일 값이 "유독 낮음"인 기준 — 기준선 − 1.0 × SD_eff
    static let lastNightLowSD = 1.0
}

/// 오늘 또는 어제로 끝나는 연속 러닝 일수. 오늘·어제 모두 러닝이 없으면 0.
func mrConsecutiveRunDays(runs: [MRWorkout], asOf: Date, calendar: Calendar = .current) -> Int {
    let today = calendar.startOfDay(for: asOf)
    let days = Set(runs.map { calendar.dateComponents([.day], from: $0.date, to: today).day ?? Int.min })
    var cursor = days.contains(0) ? 0 : (days.contains(1) ? 1 : -1)
    guard cursor >= 0 else { return 0 }
    var n = 0
    while days.contains(cursor) { n += 1; cursor += 1 }
    return n
}

/// 분 기준 급성:만성 — 최근 7일 분 합 ÷ (직전 28일(−34…−7) 분 합 ÷ 4). 28일에 러닝이 없으면 ratio nil.
/// `rising` = 최근 7일 ≥ 직전 7일(−13…−7) × 1.15 (직전 7일이 0이면 false).
func mrDurationAcuteChronic(runs: [MRWorkout], asOf: Date,
                            calendar: Calendar = .current) -> (ratio: Double?, rising: Bool) {
    let today = calendar.startOfDay(for: asOf)
    var acute = 0.0, chronic = 0.0, previous = 0.0
    for w in runs {
        let d = calendar.dateComponents([.day], from: w.date, to: today).day ?? Int.min
        if d >= 0 && d <= 6 { acute += w.durationMin }
        else if d >= 7 && d <= 34 {
            chronic += w.durationMin
            if d <= 13 { previous += w.durationMin }
        }
    }
    let ratio: Double? = chronic > 0 ? acute / (chronic / 4) : nil
    let rising = previous > 0 && acute >= previous * MRReadiness.risingRatio
    return (ratio, rising)
}

func mrReadiness(runs: [MRWorkout], phys: MRPhysiology, heatHR: MRHeatHRModel,
                 hrvNights: [(date: Date, value: Double)], planPhase: String?,
                 asOf: Date, calendar: Calendar = .current) -> MRReadiness? {
    let L = AppLanguage.shared
    let today = calendar.startOfDay(for: asOf)
    guard !runs.isEmpty else { return nil }
    // 규칙 0 — 이미 뛴 날은 제안하지 않는다(오늘 기록 줄이 주인공)
    if runs.contains(where: { calendar.isDate($0.start, inSameDayAs: asOf) }) { return nil }

    let hard = mrRecentHardRunCount(runs: runs, phys: phys, heatHR: heatHR, days: 14, asOf: asOf, calendar: calendar)
    let consecutive = mrConsecutiveRunDays(runs: runs, asOf: asOf, calendar: calendar)
    let load = mrDurationAcuteChronic(runs: runs, asOf: asOf, calendar: calendar)
    let trend = mrHRVTrend(nights: hrvNights, asOf: asOf, calendar: calendar)
    let todayNight = hrvNights.last.flatMap { calendar.isDate($0.date, inSameDayAs: today) ? $0.value : nil }
    let pending = todayNight == nil
    let lastNightLow: Bool = {
        guard let t = trend, let v = todayNight else { return false }
        let sdEff = max(t.baselineSD, t.baseline * MRHRVTrend.sdFloorFraction)
        return v < t.baseline - MRReadiness.lastNightLowSD * sdEff
    }()

    func lastHardPiece() -> String? {
        guard let d = hard.lastHardDaysAgo else { return nil }
        return L.s("마지막 고강도 \(d)일 전", "last hard run \(d) days ago")
    }
    func make(_ level: MRReadiness.Level, _ reasons: [String]) -> MRReadiness {
        MRReadiness(level: level, reasons: reasons, hrvPending: pending)
    }

    // 규칙 1 — 대회 계획의 회복·테이퍼 주
    if planPhase == "회복" { return make(.easy, [L.s("대회 계획 회복 주", "race plan: recovery week")]) }
    if planPhase == "테이퍼" { return make(.easy, [L.s("대회 계획 테이퍼 주", "race plan: taper week")]) }
    // 규칙 2 — 부하 급증 · 장기 연속
    if let r = load.ratio, r > MRReadiness.spikeRatio { return make(.rest, [L.s("부하 급증", "load spike")]) }
    if consecutive >= MRReadiness.restConsecutiveDays {
        return make(.rest, [L.s("\(consecutive)일 연속", "\(consecutive) days in a row")])
    }
    // 규칙 3 — HRV 억제 · 어젯밤 유독 낮음
    if let t = trend, t.isSuppressed {
        return make(.rest, [t.isVolatile ? L.s("HRV 불안정", "HRV unstable") : L.s("HRV 낮음", "HRV low")])
    }
    if lastNightLow { return make(.rest, [L.s("어젯밤 HRV 유독 낮음", "last night's HRV unusually low")]) }
    // 규칙 4 — 어제 고강도
    if let d = hard.lastHardDaysAgo, d <= 1 { return make(.easy, [L.s("어제 고강도", "hard run yesterday")]) }
    // 규칙 5 — 부하 오르는 중(HRV가 좋으면 통과)
    let ready = trend?.isReadyHigh == true
    if load.rising && !ready { return make(.easy, [L.s("부하 오르는 중", "load rising")]) }
    // 규칙 6 — HRV 좋음
    if ready { return make(.go, [L.s("HRV 좋음", "HRV good")] + [lastHardPiece()].compactMap { $0 }) }
    // 규칙 7 — 범위 안 또는 자료 없음: 부하 쪽이 넉넉할 때만 강도 OK
    let roomy = hard.lastHardDaysAgo.map { $0 >= MRReadiness.normalHRVGoMinDays } ?? true
    if roomy {
        var reasons: [String] = []
        if trend != nil { reasons.append(L.s("HRV 보통", "HRV normal")) }
        if let p = lastHardPiece() { reasons.append(p) }
        return make(.go, reasons)
    }
    let d = hard.lastHardDaysAgo ?? 0
    return make(.easy, [L.s("고강도 \(d)일 전", "hard run \(d) days ago"), L.s("하루 더 여유", "one more easy day")])
}
```

`mrHRVTrend`·`mrRecentHardRunCount`가 `calendar:` 파라미터를 받는지 `Engine/MRHRVTrend.swift`에서 확인한다(둘 다 `calendar: Calendar = .current`가 있다). `MRHRVTrend.sdFloorFraction`은 `static let`으로 이미 있다.

- [ ] **Step 4: 컴파일 확인** → `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Engine/MRReadiness.swift MIMORunningTests/MRReadinessTests.swift
git commit -m "아침 러닝 제안 — 판정 엔진 MRReadiness(강도 OK/이지런/휴식, 플랜 주>급증·연속>HRV 억제>어제 고강도>부하 상승>HRV 좋음>범위 안)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git show --stat HEAD
```

---

### Task 2: 오늘 카드 · 엔진 스토어 · 뷰 · 앞으로 올 때 재조회

**Files:**
- Modify: `MIMORunning/Engine/MRTodayCard.swift`
- Modify: `MIMORunning/Engine/MREngineStore.swift` (`hrvNights` 재조회 조건 ~321행 · `mrTodayCard(` 5곳 · `recomputeTodayCard` 옆)
- Modify: `MIMORunning/Views/MRTodayCardView.swift` (`Text(c.streakLine)` 바로 아래)
- Modify: `MIMORunning/MIMORunningApp.swift` (`.task { await engine.refresh() }` 옆)
- Modify: `MIMORunningTests/MRTodayCardTests.swift`

- [ ] **Step 1: XCTest 추가** — `MRTodayCardTests` 클래스 안, 마지막 테스트 뒤:

```swift
    // MARK: - 아침 제안 줄

    /// HRV 밤 시계열과 심박 모델을 넘기면 연속 줄 아래 제안 줄이 채워진다. 오늘 뛴 날엔 nil.
    func testReadinessLineFilledInTheMorningAndNilAfterRunningToday() throws {
        let cal = Calendar.current
        let morning = date("2026-09-15 08:00")
        func d(_ off: Int) -> Date { cal.startOfDay(for: cal.date(byAdding: .day, value: off, to: morning)!) }
        let runs = [27, 25, 22, 20, 18, 15, 13, 11, 8, 6, 3, 1].map { run(start: d(-$0).addingTimeInterval(7 * 3600)) }
        var nights: [(date: Date, value: Double)] = []
        for i in 0..<28 { nights.append((d(-34 + i), 30 + (i % 2 == 0 ? 1 : -1))) }
        for i in 0..<7 { nights.append((d(-6 + i), 37)) }

        let c = try XCTUnwrap(mrTodayCard(runs: runs, phys: MRPhysiology(), plans: [], raceDayCardVisible: false,
                                          advice: [], asOf: morning, heatHR: MRHeatHRModel(), hrvNights: nights, planPhase: nil))
        XCTAssertEqual(c.readinessLevel, .go)
        XCTAssertEqual(c.readinessLine, L("오늘은 강도 OK · HRV 좋음", "Today: hard is OK · HRV good"))

        let ranToday = runs + [run(start: date("2026-09-15 07:00"))]
        let c2 = try XCTUnwrap(mrTodayCard(runs: ranToday, phys: MRPhysiology(), plans: [], raceDayCardVisible: false,
                                           advice: [], asOf: date("2026-09-15 09:00"), heatHR: MRHeatHRModel(), hrvNights: nights, planPhase: nil))
        XCTAssertNil(c2.readinessLine)
    }
```

- [ ] **Step 2: 컴파일이 깨지는 것을 본다** — `extra argument 'heatHR' in call`

- [ ] **Step 3: `MRTodayCard`**

`struct MRTodayCard`에 필드 추가(`linkLine` 아래):

```swift
    /// 아침 제안 — 연속 줄 바로 아래. 오늘 뛴 날·러닝 없음·판정 불가면 nil.
    let readinessLine: String?
    let readinessLevel: MRReadiness.Level?
```

`mrTodayCard` 시그니처를 다음으로 바꾼다(기본값이 있어 기존 호출은 그대로 컴파일):

```swift
func mrTodayCard(runs: [MRWorkout],
                 phys: MRPhysiology,
                 plans: [MRRacePlan],
                 raceDayCardVisible: Bool,
                 advice: [MRAdvice],
                 asOf: Date,
                 heatHR: MRHeatHRModel = MRHeatHRModel(),
                 hrvNights: [(date: Date, value: Double)] = [],
                 planPhase: String? = nil) -> MRTodayCard? {
```

함수 끝 `return MRTodayCard(...)` 앞에:

```swift
    // ── 아침 제안 — 오늘 아직 안 뛴 날에만. 종류는 고르지 않고 강도만 연다.
    let readiness = mrReadiness(runs: runs, phys: phys, heatHR: heatHR, hrvNights: hrvNights,
                                planPhase: planPhase, asOf: asOf)
```

그리고 `return MRTodayCard(streakLine: streakLine, distanceCells: distanceCells, sessionLine: sessionLine, linkLine: linkLine, readinessLine: readiness?.line, readinessLevel: readiness?.level)`.

- [ ] **Step 4: `MREngineStore` — 헬퍼로 통합 + 재조회 조건 + `refreshHRVIfStale`**

`recomputeTodayCard()` 바로 위에 헬퍼를 추가하고, 파일의 `todayCard = mrTodayCard(...)` **5곳 전부**를 `todayCard = buildTodayCard(runs: <그 자리의 runs 변수>, now: now)`로 바꾼다(`grep -n "mrTodayCard(" MIMORunning/Engine/MREngineStore.swift`로 확인, 바꾼 뒤 `grep -c "buildTodayCard(" …` = 6(정의 1 + 호출 5)).

```swift
    /// 오늘 카드 생성 — 호출부 5곳이 이 하나만 쓴다(대회 D-day 가시성·아침 제안 입력을 한 곳에서).
    private func buildTodayCard(runs: [MRWorkout], now: Date) -> MRTodayCard? {
        let raceDayVisible = raceDayCard.map { MRRaceDayView.shouldShow($0) } ?? false
        return mrTodayCard(runs: runs, phys: phys, plans: plans,
                           raceDayCardVisible: raceDayVisible,
                           advice: advice, asOf: now,
                           heatHR: heatHR, hrvNights: hrvNights,
                           planPhase: governingPlanWeek(for: now)?.week.phase)
    }
```

`refreshCore`의 HRV 조회 조건(현재 `if hrvNights.isEmpty || hrvAge >= 24 * 3600 {`)을:

```swift
        // 오늘 키의 밤이 없으면(워치가 아침에 동기화) 24시간 안이어도 다시 읽는다 — 아침 제안이 어젯밤을 봐야 한다
        let hasTonight = hrvNights.last.map { Calendar.current.isDateInToday($0.date) } ?? false
        if hrvNights.isEmpty || hrvAge >= 24 * 3600 || !hasTonight {
```

`recomputeTodayCard()` 아래에:

```swift
    /// 앱이 앞으로 올 때 — 오늘 키의 밤이 아직 없고 마지막 조회가 30분 이상 전이면 HRV만 다시 읽고 조언·오늘 카드를 다시 만든다.
    /// HealthKit 전체 재읽기는 하지 않는다.
    func refreshHRVIfStale() async {
        guard case .ready = state else { return }
        let hasTonight = hrvNights.last.map { Calendar.current.isDateInToday($0.date) } ?? false
        let age = hrvLastFetchedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        guard !hasTonight, age >= 30 * 60 else { return }
        let raw = (try? await hk.fetchSleepHRV()) ?? []
        let nights = mrHRVNightMedians(samples: raw)
        let fetchedAt = Date()
        hrvLastFetchedAt = fetchedAt
        if !nights.isEmpty {
            hrvNights = nights
            persistHRV(fetchedAt: fetchedAt, nights: nights)
        }
        let now = Date()
        advice = mrBuildAdvice(runs: runs, phys: phys, plans: plans,
                               races: userInput.races,
                               gaps: gaps, strengthPerWeek: storedStrengthPerWeek,
                               fatigue: storedFatigue, cadenceShift: storedCadenceShift,
                               heatHR: heatHR,
                               hrvTrend: mrHRVTrend(nights: hrvNights, asOf: now),
                               log: adviceLog, asOf: now)
        todayCard = buildTodayCard(runs: runs, now: now)
        #if DEBUG
        print("[HRV] 앞으로 옴 → 재조회 \(nights.count)밤 · 오늘 밤 \(hrvNights.last.map { Calendar.current.isDateInToday($0.date) } ?? false ? "있음" : "없음")")
        #endif
    }
```

`gaps`는 스토어의 `@Published private(set) var gaps`(68행)다 — 다른 재계산 호출부와 같다.

- [ ] **Step 5: 뷰** — `MRTodayCardView.body`에서 `Text(c.streakLine)…foregroundStyle(.white)` 바로 아래:

```swift
                // 아침 제안 — 연속 줄 바로 아래 한 줄. 색은 판정별(초록/노랑/주황). 오늘 뛴 날엔 없다.
                if let line = c.readinessLine, let level = c.readinessLevel {
                    let color: Color = switch level {
                    case .go:   Theme.positive
                    case .easy: Theme.time
                    case .rest: Color(hex: "FF9A3C")
                    }
                    Text(line)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(color)
                        .padding(.top, 6)
                }
```

- [ ] **Step 6: 앱** — `MIMORunningApp`의 `WindowGroup` 안 `ContentView()` 체인에 `.task { await engine.refresh() }` 다음 줄:

```swift
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { Task { await engine.refreshHRVIfStale() } }
                    }
```

그리고 `struct MIMORunningApp` 프로퍼티에 `@Environment(\.scenePhase) private var scenePhase`를 추가한다(`App` 안에서도 `@Environment(\.scenePhase)`는 유효).

- [ ] **Step 7: 컴파일 확인** → `** TEST BUILD SUCCEEDED **`

- [ ] **Step 8: 커밋**

```bash
git add MIMORunning/Engine/MRTodayCard.swift MIMORunning/Engine/MREngineStore.swift MIMORunning/Views/MRTodayCardView.swift MIMORunning/MIMORunningApp.swift MIMORunningTests/MRTodayCardTests.swift
git commit -m "아침 러닝 제안 — 홈 오늘 카드 연속 줄 아래 한 줄(강도 OK/이지런/휴식) · 오늘 밤 없으면 HRV 재조회 · 앞으로 올 때 refreshHRVIfStale

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git show --stat HEAD
```

---

## 실기기 확인 포인트
1. 아침에 앱을 열었을 때 연속 줄 아래 "오늘은 …" 한 줄. 색: 초록(강도 OK)·노랑(이지런)·주황(휴식).
2. 워치 동기화 전이면 끝에 "어젯밤 HRV 동기화 전". 잠시 뒤 앱을 백그라운드→포그라운드하면 콘솔 `[HRV] 앞으로 옴 → 재조회 …` 후 문구가 바뀌는지.
3. 오늘 뛰고 나면 줄이 사라지고 오늘 기록 줄이 뜨는지.
