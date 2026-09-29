# 강도 훈련 — 본인 데이터에서 출발 (빈도 · 인터벌 시작점) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 강도 훈련의 빈도를 본인 최근 12주 습관에서, 인터벌 페이스를 본인 최근 인터벌 기록에서 정한다. 구조(반복 약 4분·회복 3분·주간 8%·롱런 +10%)는 문헌 그대로.

**Architecture:** 순수 함수는 `MIMORunning/Engine/MRPlanPoint.swift`에 더한다. 플래너(`mrBuildPlan`)는 새 인자 두 개(`pointHabitEveryWeeks`, `intervalHistory`)를 받는다. 대회 없을 때 리듬은 `MRRhythmContext`의 새 필드로 받는다. 홈(`ActivityListView.pushHardRunStarts`)이 인터벌 기록을 엔진에 넣고, 엔진이 계획을 만들 때 습관과 기록을 넘긴다. 트리거 5는 이미 채운 미래 주를 같은 단계 라이브 주에 맞춘다.

**Tech Stack:** Swift 6 · SwiftUI · Swift Testing

**설계:** `docs/superpowers/specs/2026-09-29-point-from-own-data-design.md` (먼저 읽을 것). 앞 설계 `2026-09-29-plan-point-session-design.md`.

---

## 공통 규칙 (모든 작업)

- **시뮬레이터 금지.** 테스트 실행 금지. 검증은 컴파일까지:
  ```bash
  cd /Users/hns/MIMORunning/MIMORunning && xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/claude-501/-Users-hns-MIMORunning-MIMORunning/c7613597-c399-4ba4-abca-bf01dac1d0f3/scratchpad/dd-point 2>&1 | grep -E "error:|\*\* TEST BUILD" | head -30
  ```
  기대: `** TEST BUILD SUCCEEDED **`. TDD = 테스트 먼저 쓰고 컴파일이 기대한 이유(없는 심볼)로 깨지는 것 확인 → 구현 → 성공.
- **git**: 다른 세션이 같은 브랜치(`crew`)에서 일한다. `git add -A`·`git stash` 금지, `MIMORunning.xcodeproj/project.pbxproj` 커밋 금지. 새 파일은 경로로 `git add`, 커밋은 `git commit -m "…" -- <경로들>`. 커밋 전 `git diff <파일>`로 남의 변경이 섞였는지 확인(섞였으면 멈추고 보고). 메시지는 한국어, 끝에 빈 줄 + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- 테스트는 Swift Testing, 스위트에 `.korean` 트레잇. 문구는 `AppLanguage.shared.s("한국어", "English")`.
- 임의로 정한 값에는 `⚠ 임의로 정함` 주석.
- 기존 도우미: `mrPointRun`, `mrPointIntervalDays`, `mrIntervalRepKm`, `mrRepDistanceString`, `mrPointKmString`, `mrMedian`(MRPhysiology.swift), `MRPlanGovernance.weekMonday`, `MRPlanWeekContext.longRunDoneFraction`, `mrParsePlanBreakdown`, `mrBreakdownReplacingEasy`, `mrFormatPace`. `MRWorkout(start:durationMin:distanceKm:hrAvg:hrMax:tempC:humidity:indoor:isInterval:)`. `IntervalSegment(id:startDate:endDate:distanceM:avgHeartRate:avgCadence:stepLabel:)` (Models/Activity.swift, `stepLabel` "운동"·"회복"·"준비운동"·"정리운동").

---

### Task 1: 빈도 — 본인 강도 훈련 습관

**Files:**
- Modify: `MIMORunning/Engine/MRPlanPoint.swift` (함수 2개 추가, `MRRhythmContext`에 필드, `mrRhythmSuggestion`의 간격)
- Modify: `MIMORunning/Engine/MRRacePlanner.swift` (`mrBuildPlan` 인자·루프)
- Test: Create `MIMORunningTests/MRPointHabitTests.swift`

- [ ] **Step 1: 테스트 먼저**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("강도 훈련 — 본인 빈도 습관", .korean)
struct MRPointHabitTests {

    private let cal = Calendar.current
    /// 2026-10-12(월) 주가 "이번 주". 오프셋 0=월.
    private func day(_ offset: Int, hour: Int = 7) -> Date {
        let mon = cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        return cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: mon)!)!
    }
    private func run(_ offset: Int, km: Double) -> MRWorkout {
        MRWorkout(start: day(offset), durationMin: km * 6, distanceKm: km, hrAvg: 140, hrMax: 170,
                  tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }
    /// 지난 12주 화 8km · 목 8km · 토 16km. `pointEvery` 주마다 목요일을 인터벌로 표시(0이면 없음).
    private func history(pointEvery: Int, weeks: Int = 12) -> (runs: [MRWorkout], types: [Date: WorkoutType]) {
        var runs: [MRWorkout] = []
        var types: [Date: WorkoutType] = [:]
        for w in 1...weeks {
            let thu = run(-7 * w + 3, km: 8)
            runs += [run(-7 * w + 1, km: 8), thu, run(-7 * w + 5, km: 16)]
            if pointEvery > 0 && w % pointEvery == 0 { types[thu.start] = .interval }
        }
        return (runs.sorted { $0.start < $1.start }, types)
    }

    @Test func weeklyHabitIsOne() {
        let h = history(pointEvery: 1)
        #expect(mrHabitualPointEveryWeeks(runs: h.runs, pointTypes: h.types, hardStarts: [], asOf: day(2)) == 1)
    }

    @Test func everyOtherWeekIsTwo() {
        let h = history(pointEvery: 2)
        #expect(mrHabitualPointEveryWeeks(runs: h.runs, pointTypes: h.types, hardStarts: [], asOf: day(2)) == 2)
    }

    @Test func everyThirdWeekIsThree() {
        let h = history(pointEvery: 3)
        #expect(mrHabitualPointEveryWeeks(runs: h.runs, pointTypes: h.types, hardStarts: [], asOf: day(2)) == 3)
    }

    @Test func noHardSessionsStartsSlowlyAtThree() {
        let h = history(pointEvery: 0)
        #expect(mrHabitualPointEveryWeeks(runs: h.runs, pointTypes: h.types, hardStarts: [], asOf: day(2)) == 3)
    }

    @Test func longRunBuildUpDoesNotCountAsHardSession() {
        // 토요일 롱런만 빌드업이면 강도 훈련이 아니다(롱런으로 셈)
        var h = history(pointEvery: 0)
        for r in h.runs where (r.distanceKm ?? 0) >= 16 { h.types[r.start] = .buildUp }
        #expect(mrHabitualPointEveryWeeks(runs: h.runs, pointTypes: h.types, hardStarts: [], asOf: day(2)) == 3)
    }

    @Test func fewerThanSixWeeksIsNil() {
        let h = history(pointEvery: 1, weeks: 5)
        #expect(mrHabitualPointEveryWeeks(runs: h.runs, pointTypes: h.types, hardStarts: [], asOf: day(2)) == nil)
    }

    @Test func appliedIntervalIsTheRarerOfRunsRuleAndHabit() {
        #expect(mrPointEveryWeeks(runsPerWeek: 4.2, habit: nil) == 1)
        #expect(mrPointEveryWeeks(runsPerWeek: 4.2, habit: 2) == 2)
        #expect(mrPointEveryWeeks(runsPerWeek: 3, habit: 1) == 2)
        #expect(mrPointEveryWeeks(runsPerWeek: 5, habit: 3) == 3)
        #expect(mrPointEveryWeeks(runsPerWeek: 2, habit: 1) == nil)
    }

    private func plan(habit: Int?) -> MRRacePlan? {
        var p = MRProfile()
        p.weeklyKm4w = 30; p.longestRun16wKm = 14; p.maxWeeklyKm52w = 45; p.runsPerWeek = 5
        let today = Date()
        let race = cal.date(byAdding: .day, value: 7 * 20, to: today)!
        return mrBuildPlan(raceDate: race, distanceM: MRDistance.dH, today: today, profile: p, halfEquivMin: 110,
                           easyPaceSecPerKm: 400, heat: MRHeatModel(), raceTempC: 15, runsPerWeek: 5,
                           pointHabitEveryWeeks: habit)
    }

    @Test func planSpacesPointsByHabit() throws {
        for habit in [2, 3] {
            let p = try #require(plan(habit: habit))
            // 테이퍼를 뺀 강도 훈련 종류 주의 순번에서, 강도 훈련이 든 주끼리 habit 주 이상 떨어져 있다
            let eligible = p.weeks.filter { mrPointKind(phase: $0.phase).map { $0 != .racePaceShort } ?? false }
            let idx = eligible.indices.filter { eligible[$0].point != nil }
            #expect(!idx.isEmpty)
            for (a, b) in zip(idx, idx.dropFirst()) { #expect(b - a >= habit) }
        }
    }

    @Test func rhythmUsesHabitInterval() throws {
        // 주 4회라도 습관 2주면 8일 전 강도 훈련 뒤에는 아직 아니다
        let h = history(pointEvery: 1)
        let lastTue = try #require(h.runs.first { cal.isDate($0.start, inSameDayAs: day(-6)) })
        var ctx = MRRhythmContext(runsPerWeek: 4, paces: mrPointPaces(halfEquivMin: 110), pointTypes: [lastTue.start: .interval])
        ctx.habitEveryWeeks = 2
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx, runs: h.runs, hardStarts: [], asOf: day(2)))
        #expect(!s.isPoint)
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는지 확인** — `cannot find 'mrHabitualPointEveryWeeks'` 등.

- [ ] **Step 3: 구현**

(a) `MRPlanPoint.swift` — `func mrPointIntervalDays(runsPerWeek:)` 바로 아래에:

```swift
/// 본인 강도 훈련 습관 간격(주) — 이번 주 앞 12주 중 러닝이 있던 주에서, 그 주 최장 러닝(롱런)을 뺀 고강도·포인트 유형
/// 러닝(`mrPointRun`)이 있던 주의 비율로. 1 매주 · 2 격주 · 3 3주에 한 번. 러닝 있는 주 6주 미만이면 nil(폴백).
/// 비율 0(강도 훈련을 거의 안 해 옴)이면 3 — 천천히 들인다. 설계 2026-09-29 "본인 데이터에서 출발" 2절.
func mrHabitualPointEveryWeeks(runs: [MRWorkout], pointTypes: [Date: WorkoutType], hardStarts: Set<Date>,
                               asOf: Date, calendar: Calendar = .current) -> Int? {
    let thisMonday = MRPlanGovernance.weekMonday(of: asOf, calendar: calendar)
    guard let from = calendar.date(byAdding: .day, value: -84, to: thisMonday) else { return nil }
    var byWeek: [Date: [MRWorkout]] = [:]
    for w in runs where w.start >= from && w.start < thisMonday {
        byWeek[MRPlanGovernance.weekMonday(of: w.start, calendar: calendar), default: []].append(w)
    }
    guard byWeek.count >= 6 else { return nil }
    let withPoint = byWeek.values.filter { ws in
        let longest = ws.compactMap(\.distanceKm).max() ?? 0
        return mrPointRun(weekRuns: ws, longRunKm: longest, hardStarts: hardStarts, pointTypes: pointTypes) != nil
    }.count
    let ratio = Double(withPoint) / Double(byWeek.count)
    guard ratio > 0 else { return 3 }
    return min(max(Int((1 / ratio).rounded()), 1), 3)
}

/// 적용 간격(주) — 주당 러닝 횟수 규칙(4회↑ 1 · 3회 2 · 2회↓ 없음)과 본인 습관 중 더 드문 쪽.
func mrPointEveryWeeks(runsPerWeek: Double, habit: Int?) -> Int? {
    guard let days = mrPointIntervalDays(runsPerWeek: runsPerWeek) else { return nil }
    let byRuns = days / 7
    return max(byRuns, habit ?? byRuns)
}
```

(b) `MRRhythmContext`에 필드 추가(`var recentRaceDate: Date? = nil` 아래):

```swift
    /// 본인 강도 훈련 습관 간격(주) — nil이면 주당 러닝 횟수 규칙만
    var habitEveryWeeks: Int? = nil
```

`mrRhythmSuggestion`의 `let interval = mrPointIntervalDays(runsPerWeek: ctx.runsPerWeek)`를:

```swift
    let interval = mrPointEveryWeeks(runsPerWeek: ctx.runsPerWeek, habit: ctx.habitEveryWeeks).map { $0 * 7 }
```

(c) `MRRacePlanner.swift` — `mrBuildPlan` 인자에 `tuneUps: [MRTuneUpRace] = [],` 바로 뒤에 추가:

```swift
                 pointHabitEveryWeeks: Int? = nil,
```

루프 앞 `var pointSlot = 0` 바로 위에:

```swift
    // 강도 훈련 간격(주) — 주당 러닝 횟수 규칙과 본인 습관 중 더 드문 쪽(2026-09-29 본인 데이터 우선)
    let pointEvery = mrPointEveryWeeks(runsPerWeek: runsPerWeek, habit: pointHabitEveryWeeks)
```

루프 안 강도 훈련 블록의

```swift
                  let interval = mrPointIntervalDays(runsPerWeek: runsPerWeek),
                  others >= 2 {
```
를
```swift
                  let every = pointEvery,
                  others >= 2 {
```
로, 그리고
```swift
            let slotOK = interval == 7 || kind == .racePaceShort || pointSlot % 2 == 0
```
를
```swift
            let slotOK = every == 1 || kind == .racePaceShort || pointSlot % every == 0
```
로 바꾼다.

- [ ] **Step 4: 컴파일 확인** — `** TEST BUILD SUCCEEDED **`
- [ ] **Step 5: 커밋** — `git add MIMORunningTests/MRPointHabitTests.swift` 후
  `git commit -m "강도 훈련 빈도를 본인 12주 습관에서 — 주당 횟수 규칙과 습관 중 드문 쪽, 계획·리듬 모두" -- MIMORunning/Engine/MRPlanPoint.swift MIMORunning/Engine/MRRacePlanner.swift MIMORunningTests/MRPointHabitTests.swift` (메시지에 Co-Authored-By 줄 포함)

---

### Task 2: 인터벌 페이스 — 구조는 문헌, 페이스는 본인 기록

원칙(2026-09-29 사용자 보정): 문헌 = 구조와 규칙(반복 약 4분·회복 3분·주간 8% 그대로), 본인 데이터 = 값(페이스). 반복 거리·회수·회복 규칙은 **바꾸지 않는다**.

**Files:**
- Modify: `MIMORunning/Engine/MRPlanPoint.swift` (`MRPlanPoint.paceFromHistory`, `howTo`, `MRIntervalHistory`, `mrIntervalHistory`, `mrIntervalPace`, 리듬)
- Modify: `MIMORunning/Engine/MRRacePlanner.swift` (`intervalHistory` 인자)
- Modify: `MIMORunningTests/MRRacePlannerPointTests.swift` (`howToExplainsStructure` 기대값)
- Test: Create `MIMORunningTests/MRIntervalHistoryTests.swift`

- [ ] **Step 1: 테스트 먼저**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("강도 훈련 — 인터벌 페이스는 본인 기록", .korean)
struct MRIntervalHistoryTests {

    private let t0 = Date(timeIntervalSince1970: 1_791_000_000)
    private func seg(_ id: Int, from: Double, sec: Double, m: Double?, label: String) -> IntervalSegment {
        IntervalSegment(id: id, startDate: t0.addingTimeInterval(from), endDate: t0.addingTimeInterval(from + sec),
                        distanceM: m, avgHeartRate: nil, avgCadence: nil, stepLabel: label)
    }
    /// 400m × 5 (각 108초 = 4'30"/km), 회복 200m 72초
    private func fourHundreds() -> [IntervalSegment] {
        var s: [IntervalSegment] = [seg(0, from: 0, sec: 600, m: 2000, label: "준비운동")]
        var t = 600.0
        for i in 1...5 {
            s.append(seg(i * 2 - 1, from: t, sec: 108, m: 400, label: "운동")); t += 108
            if i < 5 { s.append(seg(i * 2, from: t, sec: 72, m: 200, label: "회복")); t += 72 }
        }
        return s
    }

    @Test func summarizesWorkAndRecoverySegments() throws {
        let h = try #require(mrIntervalHistory(segments: fourHundreds(), date: t0))
        #expect(h.repKm == 0.4)
        #expect(h.reps == 5)
        #expect(abs(h.paceSecPerKm - 270) < 0.5)
        #expect(abs(h.recoverySec - 72) < 0.5)
    }

    @Test func fewerThanThreeWorkSegmentsIsNil() {
        let s = Array(fourHundreds().prefix(4))   // 준비 + 운동 2개(+회복 1)
        #expect(mrIntervalHistory(segments: s, date: t0) == nil)
    }

    @Test func threeToFiveMinuteRepsUseMyActualPace() {
        // 1km 5'00" = 300초 → 3~5분 반복 → 본인 실제 페이스
        let h = MRIntervalHistory(date: t0, repKm: 1.0, reps: 4, paceSecPerKm: 300, recoverySec: 180)
        let r = mrIntervalPace(history: h, fiveKPace: 307)
        #expect(r.pace == 300)
        #expect(r.fromHistory)
    }

    @Test func shortRepsFallBackToPredictedFiveK() {
        // 400m 4'30" = 108초 → 2분 미만, 다른 에너지 구간 → 5K 예측 페이스
        let h = MRIntervalHistory(date: t0, repKm: 0.4, reps: 5, paceSecPerKm: 270, recoverySec: 72)
        let r = mrIntervalPace(history: h, fiveKPace: 307)
        #expect(r.pace == 307)
        #expect(!r.fromHistory)
        #expect(mrIntervalPace(history: nil, fiveKPace: 307).fromHistory == false)
    }

    @Test func overFiveMinuteRepsAlsoFallBack() {
        let h = MRIntervalHistory(date: t0, repKm: 1.2, reps: 3, paceSecPerKm: 280, recoverySec: 180)   // 336초
        #expect(!mrIntervalPace(history: h, fiveKPace: 307).fromHistory)
    }

    @Test func howToShowsPaceBasis() {
        var p = MRPlanPoint(kind: .speed, totalKm: 8.5, reps: 5, repKm: 0.8, sustainedKm: nil, paceSecPerKm: 307)
        #expect(p.howTo.hasSuffix("예상 5K 기록 기준"))
        p.paceFromHistory = true
        #expect(p.howTo.hasSuffix("최근 인터벌 페이스 기준"))
    }

    @Test func planUsesHistoryPaceOnlyForThreeToFiveMinuteReps() throws {
        var pr = MRProfile()
        pr.weeklyKm4w = 45; pr.longestRun16wKm = 22; pr.maxWeeklyKm52w = 60; pr.runsPerWeek = 5
        let today = Date()
        let race = Calendar.current.date(byAdding: .day, value: 7 * 24, to: today)!
        let hist = MRIntervalHistory(date: t0, repKm: 1.0, reps: 4, paceSecPerKm: 300, recoverySec: 180)
        let p = try #require(mrBuildPlan(raceDate: race, distanceM: MRDistance.dF, today: today, profile: pr,
                                         halfEquivMin: 110, easyPaceSecPerKm: 400, heat: MRHeatModel(),
                                         raceTempC: 15, runsPerWeek: 5, intervalHistory: hist))
        let speeds = p.weeks.compactMap(\.point).filter { $0.kind == .speed }
        #expect(!speeds.isEmpty)
        #expect(speeds.allSatisfy { $0.paceSecPerKm == 300 && $0.paceFromHistory == true })
        #expect(speeds.allSatisfy { $0.repKm == mrIntervalRepKm(paceSecPerKm: 300) })   // 구조는 그대로(4분 거리)
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는지 확인** — `cannot find 'mrIntervalHistory'` 등.

- [ ] **Step 3: 구현**

(a) `struct MRPlanPoint`의 `let paceSecPerKm: Double` 아래에:

```swift
    /// 페이스 근거 — true 최근 인터벌(3~5분 반복) 실제 페이스 · false/nil 본인 기록으로 낸 5K 예측 페이스
    var paceFromHistory: Bool? = nil
```

(b) `howTo`의 `.speed` 케이스를 교체(구조 문구는 그대로, 끝에 근거):

```swift
        case .speed:
            let basis = paceFromHistory == true
                ? L.s("최근 인터벌 페이스 기준", "pace from your recent intervals")
                : L.s("예상 5K 기록 기준", "pace from your predicted 5K")
            return L.s("사이 \(Self.intervalJogMin)분 천천히 조깅 · 앞뒤 조깅 포함 총 \(total)km · \(basis)",
                       "\(Self.intervalJogMin)-min easy jog between · \(total) km total incl. warm-up/cool-down · \(basis)")
```

(c) `func mrPointKmString` 위에 추가:

```swift
/// 본인 인터벌 한 번의 요약 — 워치 구조화 운동의 "운동"·"회복" 구간에서.
struct MRIntervalHistory: Equatable, Sendable {
    let date: Date
    /// 운동 구간 거리 중앙값, 200m 단위
    let repKm: Double
    let reps: Int
    /// 운동 구간 평균 페이스
    let paceSecPerKm: Double
    /// 회복 구간 시간 중앙값(초). 회복 구간이 없으면 120 — ⚠ 임의로 정함(지금은 기록용, 계획 규칙엔 안 씀)
    let recoverySec: Double
}

/// 구간 → 요약. 운동 구간이 3개 미만이거나 운동 구간 거리가 빠져 있으면 nil.
func mrIntervalHistory(segments: [IntervalSegment], date: Date) -> MRIntervalHistory? {
    let work = segments.filter { $0.stepLabel == "운동" }
    let dists = work.compactMap(\.distanceM).filter { $0 > 0 }
    let paces = work.compactMap(\.paceSecPerKm)
    guard work.count >= 3, dists.count == work.count, !paces.isEmpty else { return nil }
    let repKm = (mrMedian(dists) / 200).rounded() * 200 / 1000
    guard repKm >= 0.2 else { return nil }
    let rec = segments.filter { $0.stepLabel == "회복" }.map(\.duration)
    return MRIntervalHistory(date: date, repKm: repKm, reps: work.count,
                             paceSecPerKm: paces.reduce(0, +) / Double(paces.count),
                             recoverySec: rec.isEmpty ? 120 : mrMedian(rec))
}

/// 인터벌 페이스 — 구조(반복 약 4분·회복 3분·주간 8%)는 문헌(Daniels), 페이스는 본인 데이터.
/// 최근 인터벌 반복이 3~5분이었으면 그 실제 평균 페이스(같은 구조의 가장 직접적인 본인 기록),
/// 아니면 본인 기록으로 낸 5K 예측 페이스. 400m처럼 짧은 반복은 다른 에너지 구간이라 4분 반복 페이스로 옮기지 않는다.
func mrIntervalPace(history: MRIntervalHistory?, fiveKPace: Double) -> (pace: Double, fromHistory: Bool) {
    if let h = history {
        let repSec = h.repKm * h.paceSecPerKm
        if repSec >= 180 && repSec <= 300 { return (h.paceSecPerKm, true) }
    }
    return (fiveKPace, false)
}
```

(d) `MRRacePlanner.swift` — 인자 `pointHabitEveryWeeks: Int? = nil,` 뒤에:

```swift
                 intervalHistory: MRIntervalHistory? = nil,
```

강도 훈련 블록의 `switch kind { case .speed: pace = paces.fiveK` 를

```swift
                let ip = mrIntervalPace(history: intervalHistory, fiveKPace: paces.fiveK)
                let pace: Double
                switch kind {
                case .speed: pace = ip.pace
```
로 바꾸고(원래 `let pace: Double` 선언은 이 줄로 대체), `if let pt = MRPlanPoint.make(…)` 조건 안에서 `point = pt` 를

```swift
                    var marked = pt
                    if kind == .speed { marked.paceFromHistory = ip.fromHistory }
                    point = marked
```
로 바꾼다.

(e) 리듬 — `MRRhythmContext`에 `var habitEveryWeeks` 아래:

```swift
    /// 본인 최근 인터벌(가장 최근 1건) — 3~5분 반복이면 그 페이스
    var intervalHistory: MRIntervalHistory? = nil
```

`mrRhythmSuggestion`의 `func make(_ kind:)`를:

```swift
        func make(_ kind: MRPlanPoint.Kind) -> MRPlanPoint? {
            let ip = mrIntervalPace(history: ctx.intervalHistory, fiveKPace: paces.fiveK)
            let pace = kind == .speed ? ip.pace : (kind == .tempo ? paces.tempo : paces.half)
            var pt = MRPlanPoint.make(kind: kind, weeklyKm: weekly, longRunKm: usualLong ?? 0,
                                      raceDistanceM: nil, paceSecPerKm: pace)
            if kind == .speed { pt?.paceFromHistory = ip.fromHistory }
            return pt
        }
```

(f) `MRRacePlannerPointTests.howToExplainsStructure`의 기대값을
`"사이 3분 천천히 조깅 · 앞뒤 조깅 포함 총 8.2km · 예상 5K 기록 기준"`으로 고친다.

- [ ] **Step 4: 컴파일 확인** — `** TEST BUILD SUCCEEDED **`
- [ ] **Step 5: 커밋** — 새 테스트 `git add` 후 `-- MIMORunning/Engine/MRPlanPoint.swift MIMORunning/Engine/MRRacePlanner.swift MIMORunningTests/MRIntervalHistoryTests.swift MIMORunningTests/MRRacePlannerPointTests.swift`, 메시지 "인터벌 페이스를 본인 기록에서 — 최근 3~5분 반복이면 실제 페이스, 아니면 5K 예측, 구조(4분·3분 회복·8%)는 문헌 그대로, 문구에 근거".

---

### Task 3: 트리거 5 — 이미 채운 미래 주는 같은 단계 라이브 주를 따른다

**Files:**
- Modify: `MIMORunning/Engine/MRPlanPoint.swift` (`mrFillSnapshotPoints`의 `if let sp = s.point { … }` 블록, `isSamePlan`)
- Test: Modify `MIMORunningTests/MRPlanPointSnapshotTests.swift`

- [ ] **Step 1: 테스트 고치고 더하기**

`existingFuturePointIsRefreshedToCurrentRulesOnce`를 다음으로 교체:

```swift
    @Test func existingFuturePointFollowsLiveAndIsIdempotent() {
        let thisMon = wk(0)
        let old = MRPlanPoint(kind: .speed, totalKm: 6.8, reps: 3, repKm: 1, sustainedKm: nil, paceSecPerKm: 240)
        let current = MRPlanPoint.make(kind: .speed, weeklyKm: 40, longRunKm: 16, raceDistanceM: MRDistance.dH, paceSecPerKm: 240)!
        let past = snapWeek(-1, point: old, breakdown: "롱런 16km + 이지 8.6km × 2회")
        let future = snapWeek(1, point: old, breakdown: "롱런 16km + 이지 8.6km × 2회")
        let live = [liveWeek(-1, point: current), liveWeek(1, point: current)]
        let r = mrFillSnapshotPoints(snapshot: [past, future], live: live, thisMonday: thisMon, raceDistanceM: MRDistance.dH)
        #expect(r.filled == 1)
        #expect(r.weeks[0].point == old)                          // 지난 주는 그대로
        #expect(r.weeks[1].point == current)
        #expect(r.weeks[1].breakdown == "롱런 16km + 이지 8.5km × 2회")
        let again = mrFillSnapshotPoints(snapshot: r.weeks, live: live, thisMonday: thisMon, raceDistanceM: MRDistance.dH)
        #expect(again.filled == 0)
    }

    @Test func pointRemovedWhenLiveWeekHasNone() {
        let thisMon = wk(0)
        let current = MRPlanPoint.make(kind: .speed, weeklyKm: 40, longRunKm: 16, raceDistanceM: MRDistance.dH, paceSecPerKm: 240)!
        let r = mrFillSnapshotPoints(snapshot: [snapWeek(1, point: current, breakdown: "롱런 16km + 이지 8.5km × 2회")],
                                     live: [liveWeek(1, point: nil)], thisMonday: thisMon, raceDistanceM: MRDistance.dH)
        #expect(r.filled == 1)
        #expect(r.weeks[0].point == nil)
        #expect(r.weeks[0].breakdown == "롱런 16km + 이지 8km × 3회")   // (40−16)/3
    }

    @Test func smallPaceDriftDoesNotRewrite() {
        let thisMon = wk(0)
        let stored = MRPlanPoint.make(kind: .speed, weeklyKm: 40, longRunKm: 16, raceDistanceM: MRDistance.dH, paceSecPerKm: 240)!
        let drift = MRPlanPoint(kind: stored.kind, totalKm: stored.totalKm, reps: stored.reps, repKm: stored.repKm,
                                sustainedKm: stored.sustainedKm, paceSecPerKm: 243)
        let r = mrFillSnapshotPoints(snapshot: [snapWeek(1, point: stored, breakdown: "롱런 16km + 이지 8.5km × 2회")],
                                     live: [liveWeek(1, point: drift)], thisMonday: thisMon, raceDistanceM: MRDistance.dH)
        #expect(r.filled == 0)
    }
```

`alreadyFilledOrUnparsableWeeksAreLeftAlone`의 `live:` 인자를 `[liveWeek(1, point: current), liveWeek(2, point: pt)]`로 바꾼다(이미 채운 주의 라이브가 같은 점이어야 "그대로"다).

- [ ] **Step 2: 컴파일 확인** — `isSamePlan` 없으면 여기서는 깨지지 않을 수 있다(동작 테스트). 그대로 Step 3.

- [ ] **Step 3: 구현** — `struct MRPlanPoint`에 추가:

```swift
    /// 같은 훈련인가 — 구조가 같고 페이스가 5초/km 안쪽. 예측이 조금 움직여도 스냅샷을 다시 쓰지 않게.
    func isSamePlan(as o: MRPlanPoint) -> Bool {
        kind == o.kind && reps == o.reps && repKm == o.repKm && sustainedKm == o.sustainedKm
            && abs(totalKm - o.totalKm) < 0.05 && (paceFromHistory ?? false) == (o.paceFromHistory ?? false)
            && abs(paceSecPerKm - o.paceSecPerKm) < 5
    }
```

`mrFillSnapshotPoints`의 `if let sp = s.point { … }` 블록 전체를 교체:

```swift
        // 이미 채운 미래 주 — 같은 단계 라이브 주를 따른다(빈도 습관·인터벌 페이스 근거·종류 규칙이 바뀌면 반영).
        // 라이브에 없으면 빼고 이지 한 번으로 되돌린다. 페이스만 5초/km 안쪽 차이면 그대로(스냅샷을 자꾸 다시 쓰지 않게).
        if let sp = s.point {
            guard mon > thisMon, let lw = liveByMonday[mon], lw.phase == s.phase else { return s }
            let parsed = mrParsePlanBreakdown(s.breakdown)
            guard let runs = parsed.easyRuns, runs >= 1, parsed.easyKm != nil else { return s }
            let long = s.longRunKm.rounded()
            var out = s
            if let lp = lw.point {
                guard !lp.isSamePlan(as: sp) else { return s }
                let easyKm = ((s.weeklyKm - long - lp.totalKm) / Double(runs) * 10).rounded() / 10
                guard easyKm >= 1.5, let bd = mrBreakdownReplacingEasy(s.breakdown, easyKm: easyKm, runs: runs) else { return s }
                out.breakdown = bd
                out.point = lp
            } else {
                let easyKm = ((s.weeklyKm - long) / Double(runs + 1) * 10).rounded() / 10
                guard let bd = mrBreakdownReplacingEasy(s.breakdown, easyKm: easyKm, runs: runs + 1) else { return s }
                out.breakdown = bd
                out.point = nil
            }
            filled += 1
            return out
        }
```

(`existingFuturePointFollowsLiveKindWhenKindRuleChanged` 테스트는 그대로 통과해야 한다 — 라이브 템포런 총 7km 채택, 이지 8.5.)

- [ ] **Step 4: 컴파일 확인** — `** TEST BUILD SUCCEEDED **`
- [ ] **Step 5: 커밋** — `-- MIMORunning/Engine/MRPlanPoint.swift MIMORunningTests/MRPlanPointSnapshotTests.swift`, 메시지 "트리거 5 — 이미 채운 미래 주는 같은 단계 라이브 주를 따름(바꾸기·빼기), 페이스 5초 안 차이는 그대로".

---

### Task 4: 엔진·홈 주입 + 문서

**Files:**
- Modify: `MIMORunning/Engine/MREngineStore.swift` (`recentIntervals`·`updateRecentIntervals`, `buildRacePairs`의 `mrBuildPlan` 3곳, `rhythmContext(now:)`)
- Modify: `MIMORunning/Views/ActivityListView.swift` (`pushHardRunStarts` 끝)
- Modify: `FEATURES.md` (6.9.1 절), `docs/superpowers/specs/2026-09-29-plan-point-session-design.md` (한 줄 링크)

- [ ] **Step 1: 엔진** — `@Published private(set) var pointRunTypes …` 아래에:

```swift
    /// 본인 최근 인터벌 요약(최근 12주 인터벌 유형 최신 3건, 오래된 → 최근). 홈이 주입(`updateRecentIntervals`).
    @Published private(set) var recentIntervals: [MRIntervalHistory] = []

    /// 본인 강도 훈련 습관 간격 — 계획·리듬이 쓴다. 러닝·주입값에서 그때그때 계산.
    private var pointHabitEveryWeeks: Int? {
        mrHabitualPointEveryWeeks(runs: runs, pointTypes: pointRunTypes, hardStarts: hardRunStarts, asOf: Date())
    }
```

`func updatePointRunTypes(_:)` 뒤에:

```swift
    /// 홈이 본인 최근 인터벌 요약을 넣어 준다. 계획은 다음 재계산(나 탭)에서 쓰고, 오늘 카드(리듬)는 바로 다시 만든다.
    func updateRecentIntervals(_ items: [MRIntervalHistory]) {
        guard items != recentIntervals else { return }
        recentIntervals = items
        guard case .ready = state else { return }
        todayCard = buildTodayCard(runs: runs, now: Date())
    }
```

`buildRacePairs` 안의 `mrBuildPlan(` 세 곳 모두 `runsPerWeek: planProfile.runsPerWeek,` 줄 다음 인자 순서에 맞게 추가(인자 순서: `… tuneUps:, pointHabitEveryWeeks:, intervalHistory:, caller:, raceName:` — `mrBuildPlan` 선언 순서를 확인해 맞출 것):

```swift
                                 pointHabitEveryWeeks: pointHabitEveryWeeks,
                                 intervalHistory: recentIntervals.last,
```

`rhythmContext(now:)`에서 `var c = MRRhythmContext(...)` 다음 줄에:

```swift
        c.habitEveryWeeks = pointHabitEveryWeeks
        c.intervalHistory = recentIntervals.last
```

- [ ] **Step 2: 홈** — `pushHardRunStarts()`의 `engine.updatePointRunTypes(pointTypes)` 바로 뒤에:

```swift
        // 본인 최근 인터벌(최근 12주 인터벌 유형 최신 3건) — 워치 구조화 운동 구간이 있는 것만. 디스크 상세 3건 이하만 읽는다.
        let since84 = Calendar.current.date(byAdding: .day, value: -84, to: Date()) ?? .distantPast
        let intervalRuns = manager.activities
            .filter { $0.type == .running && $0.date >= since84 && pointTypes[$0.date] == .interval }
            .sorted { $0.date > $1.date }
            .prefix(3)
        let intervals = intervalRuns.compactMap { a in
            manager.detailFromCache(a.id).flatMap { mrIntervalHistory(segments: $0.intervalSegments, date: a.date) }
        }.sorted { $0.date < $1.date }
        #if DEBUG
        print("[강도훈련:기록] 습관·인터벌 — 인터벌 \(intervals.count)건 " + intervals.map {
            "\(Int($0.repKm * 1000))m×\($0.reps) \(mrFormatPace($0.paceSecPerKm)) 회복 \(Int($0.recoverySec))s"
        }.joined(separator: ", "))
        #endif
        engine.updateRecentIntervals(intervals)
```

- [ ] **Step 3: 로그** — `MREngineStore.buildRacePairs`의 첫 `mrBuildPlan` 호출 바로 위(또는 함수 시작)에 DEBUG 한 줄:

```swift
        #if DEBUG
        print("[강도훈련:기록] 습관 간격=\(pointHabitEveryWeeks.map { "\($0)주" } ?? "없음(폴백)") · 인터벌 기록=\(recentIntervals.last.map { "\(Int($0.repKm * 1000))m×\($0.reps)" } ?? "없음(일반 기준)")")
        #endif
```

- [ ] **Step 4: FEATURES.md** — 6.9.1 절의 `**단계별 종류**` 표 바로 위에 추가:

```markdown
**본인 데이터에서 출발**(2026-09-29, 설계 `docs/superpowers/specs/2026-09-29-point-from-own-data-design.md`)
- **빈도**: 이번 주 앞 12주에서 롱런을 뺀 강도 훈련이 있던 주의 비율로 습관 간격(1·2·3주)을 잡고, 주당 러닝 횟수 규칙과 둘 중 더 드문 쪽으로 넣는다. 러닝 있는 주 6주 미만이면 주당 횟수 규칙만(폴백).
- **인터벌 페이스**: 구조(반복 약 4분·회복 3분·주간 8%)는 문헌 그대로, 페이스는 본인 기록 — 최근 12주 워치 구조화 인터벌의 반복이 3~5분이었으면 그 실제 페이스, 아니면 본인 기록으로 낸 5K 예측 페이스(400m처럼 짧은 반복은 옮기지 않음). 주차표 끝에 "최근 인터벌 페이스 기준"/"예상 5K 기록 기준". 로그 `[강도훈련:기록]`.
- **이미 채운 미래 주**: 같은 단계 라이브 주를 따른다(바꾸기·빼기), 페이스 5초/km 안 차이는 그대로.
```

설계 문서 `2026-09-29-plan-point-session-design.md` 맨 위 인용 블록에 한 줄: `> 후속: 빈도·인터벌 시작점은 본인 데이터에서 — \`2026-09-29-point-from-own-data-design.md\``

- [ ] **Step 5: 컴파일 확인** — `** TEST BUILD SUCCEEDED **`
- [ ] **Step 6: 커밋** — `-- MIMORunning/Engine/MREngineStore.swift MIMORunning/Views/ActivityListView.swift FEATURES.md docs/superpowers/specs/2026-09-29-plan-point-session-design.md docs/superpowers/specs/2026-09-29-point-from-own-data-design.md docs/superpowers/plans/2026-09-29-point-from-own-data.md`, 메시지 "강도 훈련 본인 데이터 주입 — 홈이 최근 인터벌 3건 요약, 엔진이 계획·리듬에 습관 간격과 인터벌 기록 전달, FEATURES".

---

## 실기기 확인 포인트

1. 로그 `[강도훈련:기록]` — 습관 간격(예상 2주)과 인터벌 기록(예: 400m×5).
2. 풀 계획 인터벌 주 문구 끝 근거 — 사용자는 400m 기록이라 "예상 5K 기록 기준".
3. 강도 훈련 주 간격이 2주로 벌어졌는가. 로그 `[스냅샷] 시작 전 계획 변경 → 전체 갱신`(풀).
4. 강도 훈련 주 간격(습관 2주 예상).
