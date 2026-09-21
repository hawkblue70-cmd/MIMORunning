# 수면 HRV 추세 × 훈련부하 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 수면 HRV(SDNN) 60일을 밤별 중앙값으로 묶어 7일 평균 vs 4주 기준선 추세를 내고, 총평 훈련부하 줄의 다음 행동과 조언 큐에 최근 14일 부하와 결합한 문장을 띄운다.

**Architecture:** 순수 함수 `mrHRVTrend`(Engine)가 밤 시계열 → 상태(위/범위 안/아래·불안정)를 만든다. `MREngineStore`가 안정시심박처럼 HRV 밤 시계열을 한 번 가져와 캐시·게시한다. `RunSummaryBuilder`가 러닝 날짜 기준으로 추세와 14일 고강도 횟수를 조립해 `RunSummary.loadNext`가 문장을 고르고, `mrBuildAdvice`가 같은 조건으로 러닝 전 조언 1건을 낸다. 러닝별 8번 쿼리하던 `queryHRVRecovery`는 제거한다.

**Tech Stack:** Swift 6 · SwiftUI · Swift Testing (`@Test`/`#expect`) · HealthKit · Xcode 26.3

**스펙:** `docs/superpowers/specs/2026-09-21-hrv-trend-load-design.md`

---

## 파일 구조

| 파일 | 책임 | 작업 |
|---|---|---|
| `MIMORunning/Engine/MRHRVTrend.swift` | `mrHRVNightMedians` · `MRHRVTrend` · `mrHRVTrend` · `mrRecentHardRunCount` | 생성 |
| `MIMORunning/Engine/MRHealthKit.swift` | `fetchSleepHRV(days:)` | 수정 |
| `MIMORunning/Engine/MREngineStore.swift` | `hrvNights` 게시 · UserDefaults 캐시 · `[HRV]` 로그 · `mrBuildAdvice(hrvTrend:)` 전달 | 수정 |
| `MIMORunning/Engine/MRAdviceQueue.swift` | `hrvReady` 조언 | 수정 |
| `MIMORunning/Insight/RunSummary.swift` | `RunSummaryInput.hrvTrend/hardRunsLast14/runsLast14` · 근거·다음 행동 문장 | 수정 |
| `MIMORunning/Insight/RunSummaryBuilder.swift` | `isHardRun` 헬퍼 · 14일 집계 · `Context.hrvNights` | 수정 |
| `MIMORunning/Views/ActivityDetailView.swift` | `hrvNights: engine.hrvNights` 전달(총평 컨텍스트 · `RunInsightSection`) | 수정 |
| `MIMORunning/Views/RunInsightCardView.swift` | `RunInsightSection.hrvNights`(래퍼) → `RunInsightTabCard` 전달 | 수정 |
| `MIMORunning/Views/RunInsightTabCard.swift` | `RunInsightTabCard.hrvNights` → `RhythmInsightCard.hrvNights` → `summaryLines`에 전달 | 수정 |
| `MIMORunning/Health/HealthKitManager.swift` | `queryNightHRVMedian`·`queryHRVRecovery` 삭제, `fetchCondition`에서 HRV 조회 제거 | 수정 |
| `MIMORunning/Health/HRVRecovery.swift` | deprecated 주석 · 미사용 헬퍼 삭제 | 수정 |
| `MIMORunningTests/MRHRVTrendTests.swift` | 밤 묶기·추세·고강도 집계 테스트 | 생성 |
| `MIMORunningTests/RunSummaryTests.swift` | HRV 결합 문장 테스트 | 수정 |
| `MIMORunningTests/MRAdviceQueueHRVTests.swift` | `hrvReady` 조언 테스트 | 생성 |

**검증 명령 — 에이전트는 이것만 쓴다.** 시뮬레이터를 부팅하지 않고 앱 타깃과 테스트 타깃을 모두 컴파일한다(약 70초):

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -10
```

기대 출력: `** TEST BUILD SUCCEEDED **`

> **`xcodebuild test`를 돌리지 않는다.** 사용자 지시다. 테스트는 계획대로 **작성**하되 **실행은 사용자가 실기기·Xcode에서** 한다. 에이전트는 `** TEST BUILD SUCCEEDED **`까지만 책임진다. TDD 단계는 "테스트를 먼저 쓰고, 컴파일이 기대한 대로 깨지는 것을 본다"로 읽는다.

> **git 규칙.** 같은 브랜치(`crew`)에 다른 세션이 동시에 커밋한다. `git add -A`·`git add .`·`git stash` 금지. 내가 고친 파일만 경로로 `git add`. 커밋 직후 `git show --stat HEAD`로 내 파일만 들어갔는지 확인. 새 Swift 파일은 프로젝트가 파일 시스템 동기화 그룹을 쓰므로 `.pbxproj` 수정 없이 디렉터리에 넣으면 잡힌다(기존 `Engine/`·`MIMORunningTests/` 파일과 같은 위치).

**참고 타입(기존)**
- `MRWorkout(start:durationMin:distanceKm:hrAvg:hrMax:tempC:humidity:indoor:isInterval:)` · `.date`(자정) — `Engine/MRTypes.swift:120`
- `MRPhysiology.lt1HR: MRInference?`(`.value`) — `Engine/MRPhysiology.swift`
- `MRHeatHRModel.refHR(of: MRWorkout) -> Double?` — `Engine/MRHeatHRModel.swift:78`
- `MRAdvice(key:text:rationale:grade:gainMin:timeliness:slot:)` — `Engine/MRAdviceQueue.swift:5`
- `mrBuildAdvice(runs:phys:plans:races:gaps:strengthPerWeek:fatigue:cadenceShift:heatHR:log:asOf:)` — `Engine/MRAdviceQueue.swift:112`
- `MREngineStore.loadPersistedRHR()/persistRHR(fetchedAt:samples:)` — `Engine/MREngineStore.swift:83-101`
- `RunSummaryInput` · `RunSummary.loadEvidence/loadNext` — `Insight/RunSummary.swift`
- `RunSummaryBuilder.Context` · `daysSinceHardRun` — `Insight/RunSummaryBuilder.swift`
- `AppLanguage.shared` · `L.s(ko, en)` · Swift Testing `@Suite("이름", .korean)`

---

### Task 1: 밤 묶기와 추세 계산 (`MRHRVTrend`)

**Files:**
- Create: `MIMORunning/Engine/MRHRVTrend.swift`
- Create: `MIMORunningTests/MRHRVTrendTests.swift`

- [ ] **Step 1: 테스트를 먼저 쓴다**

`MIMORunningTests/MRHRVTrendTests.swift`:

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("수면 HRV 추세", .korean)
struct MRHRVTrendTests {

    private let cal = Calendar.current

    /// 오늘 자정 기준 offset일 · hour시.
    private func at(day offset: Int, hour: Int, minute: Int = 0) -> Date {
        let base = cal.startOfDay(for: Date())
        let d = cal.date(byAdding: .day, value: offset, to: base)!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
    }

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: Date())!)
    }

    // MARK: 밤 묶기

    @Test func eveningSampleBelongsToNextDay() {
        let nights = mrHRVNightMedians(samples: [(at(day: -1, hour: 22), 40)])
        #expect(nights.count == 1)
        #expect(nights[0].date == day(0))
        #expect(nights[0].value == 40)
    }

    @Test func morningSampleBelongsToSameDay() {
        let nights = mrHRVNightMedians(samples: [(at(day: 0, hour: 6), 35)])
        #expect(nights.count == 1)
        #expect(nights[0].date == day(0))
    }

    @Test func daytimeAndNoiseSamplesAreDropped() {
        let nights = mrHRVNightMedians(samples: [
            (at(day: 0, hour: 13), 50),   // 12~15시: 낮 샘플
            (at(day: 0, hour: 3), 8),     // 10ms 미만: 노이즈
        ])
        #expect(nights.isEmpty)
    }

    @Test func nightValueIsMedianOfItsSamples() {
        let nights = mrHRVNightMedians(samples: [
            (at(day: -1, hour: 23), 20), (at(day: 0, hour: 2), 60), (at(day: 0, hour: 5), 30),
        ])
        #expect(nights.count == 1)
        #expect(nights[0].value == 30)
    }

    @Test func nightsAreSortedAscending() {
        let nights = mrHRVNightMedians(samples: [(at(day: 0, hour: 4), 30), (at(day: -3, hour: 4), 31)])
        #expect(nights.map(\.date) == [day(-3), day(0)])
    }

    // MARK: 추세

    /// 4주(−34…−7)는 base, 7일(−6…0)은 recent 값으로 채운 밤 시계열.
    private func series(base: Double, recent: Double,
                        baseJitter: [Double] = [], recentJitter: [Double] = []) -> [(date: Date, value: Double)] {
        var out: [(date: Date, value: Double)] = []
        for i in 0..<28 {
            let j = baseJitter.isEmpty ? 0 : baseJitter[i % baseJitter.count]
            out.append((day(-34 + i), base + j))
        }
        for i in 0..<7 {
            let j = recentJitter.isEmpty ? 0 : recentJitter[i % recentJitter.count]
            out.append((day(-6 + i), recent + j))
        }
        return out
    }

    @Test func aboveWhenSevenDayMeanExceedsBaselinePlusHalfSD() {
        // SD 하한 = 기준선 10% = 3ms → 경계 31.5. 37은 위.
        let t = mrHRVTrend(nights: series(base: 30, recent: 37), asOf: Date())
        #expect(t?.state == .above)
        #expect(t?.isVolatile == false)
        #expect(t?.isReadyHigh == true)
        #expect(t?.sevenDayNights == 7)
        #expect(t?.baselineNights == 28)
    }

    @Test func belowWhenSevenDayMeanUnderBaselineMinusHalfSD() {
        let t = mrHRVTrend(nights: series(base: 30, recent: 25), asOf: Date())
        #expect(t?.state == .below)
        #expect(t?.isSuppressed == true)
    }

    @Test func withinWhenInsideHalfSDBand() {
        let t = mrHRVTrend(nights: series(base: 30, recent: 31), asOf: Date())
        #expect(t?.state == .within)
        #expect(t?.isReadyHigh == false)
        #expect(t?.isSuppressed == false)
    }

    @Test func nilWhenFewerThanFourRecentNights() {
        var s = series(base: 30, recent: 37)
        s.removeAll { $0.date >= day(-3) }   // 최근 7일 중 4밤만 남기고 → 3밤
        s.removeAll { $0.date == day(-4) }
        #expect(mrHRVTrend(nights: s, asOf: Date()) == nil)
    }

    @Test func nilWhenFewerThanFourteenBaselineNights() {
        let s = series(base: 30, recent: 37).filter { $0.date >= day(-19) }   // 4주 창 13밤
        #expect(mrHRVTrend(nights: s, asOf: Date()) == nil)
    }

    @Test func volatileWhenRecentCVExceedsBaselineCVByHalf() {
        // 4주 CV ≈ 0.034(±1), 7일 CV ≈ 0.19(±7) → 불안정. 평균은 같은 30 → within.
        let t = mrHRVTrend(nights: series(base: 30, recent: 30, baseJitter: [1, -1], recentJitter: [7, -7]),
                           asOf: Date())
        #expect(t?.state == .within)
        #expect(t?.isVolatile == true)
        #expect(t?.isSuppressed == true)
    }

    @Test func windowsFollowAsOfNotToday() {
        // asOf = 10일 전이면 그 시점의 7일 창(−16…−10)은 4주 구간 값(30)이고, 최근 7일(37)은 보지 않는다.
        // 4주 창(−44…−17)에는 −34…−17의 18밤이 들어간다.
        let t = mrHRVTrend(nights: series(base: 30, recent: 37), asOf: day(-10))
        #expect(t?.sevenDayMean == 30)
        #expect(t?.sevenDayNights == 7)
        #expect(t?.baselineNights == 18)
        #expect(t?.state == .within)
    }

    @Test func baselineWindowExcludesRecentSeven() {
        // 4주 창에 최근 7일이 섞이면 기준선이 올라가 above가 흔들린다 — 28밤만 세는지 확인
        let t = mrHRVTrend(nights: series(base: 30, recent: 60), asOf: Date())
        #expect(t?.baseline == 30)
        #expect(t?.sevenDayMean == 60)
    }

    // MARK: 14일 고강도 집계 (조언 큐용)

    private func run(daysAgo: Int, hr: Double?, interval: Bool = false) -> MRWorkout {
        MRWorkout(start: day(-daysAgo).addingTimeInterval(7 * 3600), durationMin: 50, distanceKm: 8,
                  hrAvg: hr, hrMax: 170, tempC: 15, humidity: nil, indoor: false, isInterval: interval)
    }

    @Test func hardCountUsesIntervalAndLT1() {
        var phys = MRPhysiology()
        phys.lt1HR = MRInference(value: 150, confidence: .high, basis: [])
        let runs = [run(daysAgo: 1, hr: 140), run(daysAgo: 3, hr: 155), run(daysAgo: 5, hr: 140, interval: true),
                    run(daysAgo: 20, hr: 160)]   // 14일 밖
        let c = mrRecentHardRunCount(runs: runs, phys: phys, heatHR: MRHeatHRModel(), days: 14, asOf: Date())
        #expect(c.hard == 2)
        #expect(c.total == 3)
    }

    @Test func hardCountWithoutLT1CountsIntervalsOnly() {
        let runs = [run(daysAgo: 1, hr: 170), run(daysAgo: 3, hr: 140, interval: true)]
        let c = mrRecentHardRunCount(runs: runs, phys: MRPhysiology(), heatHR: MRHeatHRModel(), days: 14, asOf: Date())
        #expect(c.hard == 1)
        #expect(c.total == 2)
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는 것을 본다**

검증 명령 실행. 기대: `error: cannot find 'mrHRVNightMedians' in scope` 등 → `** TEST BUILD FAILED **`

- [ ] **Step 3: 구현**

`MIMORunning/Engine/MRHRVTrend.swift`:

```swift
import Foundation

// MARK: - 수면 HRV 추세
//
// 애플워치 HRV(SDNN)는 밤중에 드문드문 샘플링된다. 하룻밤 값은 새벽 1시 값과 4시 값이 크게 달라 노이즈가 크다.
// 그래서 밤별 중앙값 → 7일 평균 → 4주(28일) 기준선 비교로만 쓴다. 절대값을 상태어에 쓰지 않는다.
//
// 근거: 저강도 기간에는 HRV가 오르고 고강도 기간에는 눌린다(Plews·Buchheit). 하루 값은 10~20% 자연 변동.
//       HRV는 회복 상태 지표이지 체력 지표가 아니다(취미 러너 10주 연구에서 체력 향상을 추적하지 못함).

/// 밤별 중앙값. 창은 **전날 15:00 ~ 당일 12:00** — 15시 이후 샘플은 다음 날 키, 12시 전은 그날 키, 12~15시는 낮이라 버린다.
/// 10ms 미만은 측정 노이즈로 버린다. 반환은 날짜(자정) 오름차순.
func mrHRVNightMedians(samples: [(Date, Double)],
                       noiseFloor: Double = 10.0,
                       calendar: Calendar = .current) -> [(date: Date, value: Double)] {
    var buckets: [Date: [Double]] = [:]
    for (t, v) in samples where v >= noiseFloor {
        let hour = calendar.component(.hour, from: t)
        let dayStart = calendar.startOfDay(for: t)
        let key: Date
        if hour >= 15 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            key = next
        } else if hour < 12 {
            key = dayStart
        } else {
            continue
        }
        buckets[key, default: []].append(v)
    }
    return buckets.keys.sorted().map { ($0, mrMedian(buckets[$0]!)) }
}

struct MRHRVTrend: Equatable {
    enum State: Equatable { case above, within, below }
    let state: State
    /// 7일 변동계수가 4주 변동계수의 1.5배를 넘는다
    let isVolatile: Bool
    let sevenDayMean: Double     // ms
    let baseline: Double         // 4주 중앙값, ms
    let baselineSD: Double       // 4주 표본 표준편차(하한 적용 전)
    let sevenDayCV: Double
    let baselineCV: Double
    let sevenDayNights: Int
    let baselineNights: Int

    /// 위·안정 — 강도 세션 제안 조건
    var isReadyHigh: Bool { state == .above && !isVolatile }
    /// 아래 또는 불안정 — "충분히 회복" 억제 조건
    var isSuppressed: Bool { state == .below || isVolatile }

    static let minRecentNights = 4
    static let minBaselineNights = 14
    static let bandSD = 0.5
    static let volatileRatio = 1.5
    /// SD 하한 = 기준선의 10% — 4주가 너무 고르면 밴드가 0에 가까워져 판정이 튄다
    static let sdFloorFraction = 0.10
}

/// 표본 표준편차(n−1). n < 2면 0.
private func mrSampleSD(_ v: [Double]) -> Double {
    guard v.count >= 2 else { return 0 }
    let mean = v.reduce(0, +) / Double(v.count)
    let variance = v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(v.count - 1)
    return variance.squareRoot()
}

/// `asOf`(러닝 날짜) 기준 — 7일 창 = day(asOf)−6…day(asOf), 4주 창 = day(asOf)−34…day(asOf)−7.
/// 러닝 전날 밤이 day(asOf) 키다. 유효 밤이 7일 4 미만 또는 4주 14 미만이면 nil.
func mrHRVTrend(nights: [(date: Date, value: Double)], asOf: Date,
                calendar: Calendar = .current) -> MRHRVTrend? {
    let today = calendar.startOfDay(for: asOf)
    func daysBefore(_ d: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: d), to: today).day ?? Int.min
    }
    var recent: [Double] = []
    var base: [Double] = []
    for n in nights {
        let d = daysBefore(n.date)
        if d >= 0 && d <= 6 { recent.append(n.value) }
        else if d >= 7 && d <= 34 { base.append(n.value) }
    }
    guard recent.count >= MRHRVTrend.minRecentNights,
          base.count >= MRHRVTrend.minBaselineNights else { return nil }

    let mean7 = recent.reduce(0, +) / Double(recent.count)
    let baseline = mrMedian(base)
    let baseMean = base.reduce(0, +) / Double(base.count)
    let sd28 = mrSampleSD(base)
    let sdEff = max(sd28, baseline * MRHRVTrend.sdFloorFraction)
    let cv7 = mean7 > 0 ? mrSampleSD(recent) / mean7 : 0
    let cv28 = baseMean > 0 ? sd28 / baseMean : 0

    let state: MRHRVTrend.State
    if mean7 > baseline + MRHRVTrend.bandSD * sdEff { state = .above }
    else if mean7 < baseline - MRHRVTrend.bandSD * sdEff { state = .below }
    else { state = .within }

    let volatile = cv28 > 0 && cv7 > MRHRVTrend.volatileRatio * cv28

    return MRHRVTrend(state: state, isVolatile: volatile,
                      sevenDayMean: mean7, baseline: baseline, baselineSD: sd28,
                      sevenDayCV: cv7, baselineCV: cv28,
                      sevenDayNights: recent.count, baselineNights: base.count)
}

// MARK: - 최근 N일 고강도 횟수 (조언 큐용, MRWorkout 세계)

/// 인터벌이거나 15°C 보정 평균심박이 LT1 이상이면 고강도. LT1이 없으면 인터벌만 센다.
/// 창은 `asOf` 자정 기준 직전 `days`일(오늘 포함).
func mrRecentHardRunCount(runs: [MRWorkout], phys: MRPhysiology, heatHR: MRHeatHRModel,
                          days: Int, asOf: Date,
                          calendar: Calendar = .current) -> (hard: Int, total: Int) {
    let today = calendar.startOfDay(for: asOf)
    var hard = 0, total = 0
    for w in runs {
        let d = calendar.dateComponents([.day], from: w.date, to: today).day ?? Int.min
        guard d >= 0 && d < days else { continue }
        total += 1
        if w.isInterval { hard += 1; continue }
        // refHR는 hrAvg가 nil일 때만 nil — 심박 없는 러닝은 고강도로 세지 않는다
        if let lt1 = phys.lt1HR?.value, let hr = heatHR.refHR(of: w), hr >= lt1 { hard += 1 }
    }
    return (hard, total)
}
```

`mrMedian`은 `Engine/MRFormulas.swift`(또는 인접 파일)에 이미 있다 — `grep -rn "func mrMedian" MIMORunning/Engine`으로 확인하고 시그니처(`[Double] -> Double`)가 맞으면 그대로 쓴다. 없으면 이 파일에 `private func mrMedian`을 추가하지 말고 기존 것의 이름을 확인해 맞춘다.

- [ ] **Step 4: 컴파일 확인**

검증 명령 실행. 기대: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Engine/MRHRVTrend.swift MIMORunningTests/MRHRVTrendTests.swift
git commit -m "수면 HRV 추세 — 밤별 중앙값·7일 vs 4주 기준선·변동계수·14일 고강도 집계 (MRHRVTrend)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git show --stat HEAD
```

---

### Task 2: HealthKit 조회와 엔진 스토어 캐시

**Files:**
- Modify: `MIMORunning/Engine/MRHealthKit.swift:231-256` (안정시심박 다음)
- Modify: `MIMORunning/Engine/MREngineStore.swift:68-101, 265-300`

- [ ] **Step 1: `fetchSleepHRV` 추가**

`MRHealthKit.swift`의 `fetchRestingHR` 바로 뒤에:

```swift
    // MARK: 수면 HRV

    /// 수면 HRV(SDNN) 원본 샘플. 밤 묶기는 `mrHRVNightMedians`가 한다.
    /// 60일이면 7일 창 + 4주 기준선(34일)에 여유가 있다. 그 이상은 쓰지 않는다.
    func fetchSleepHRV(days: Int = 60) async throws -> [(Date, Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        else { return [] }
        let unit = HKUnit.secondUnit(with: .milli)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let from = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let pred = HKQuery.predicateForSamples(withStart: from, end: nil, options: .strictStartDate)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, s, e in
                if let e { cont.resume(throwing: e); return }
                cont.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }
```

- [ ] **Step 2: 엔진 스토어 — 게시 프로퍼티·캐시**

`MREngineStore.swift` 게시 프로퍼티 블록(`streakWeeks` 근처)에:

```swift
    /// 수면 HRV 밤별 중앙값(60일). 총평·조언이 `mrHRVTrend(nights:asOf:)`로 러닝 날짜 기준 추세를 만든다.
    @Published private(set) var hrvNights: [(date: Date, value: Double)] = []
```

`rhrLastFetchedAt` 선언 아래에:

```swift
    private var hrvLastFetchedAt: Date? = nil
```

`persistRHR` 아래에:

```swift
    private static let hrvCacheDateKey   = "mimo.hrvCache.fetchedAt"
    private static let hrvCacheNightsKey = "mimo.hrvCache.nights"

    private func loadPersistedHRV() -> (fetchedAt: Date, nights: [(date: Date, value: Double)])? {
        let ud = UserDefaults.standard
        guard let ts = ud.object(forKey: Self.hrvCacheDateKey) as? Double,
              let rawArr = ud.array(forKey: Self.hrvCacheNightsKey) as? [[Double]] else { return nil }
        let nights = rawArr.compactMap { arr -> (date: Date, value: Double)? in
            guard arr.count == 2 else { return nil }
            return (Date(timeIntervalSince1970: arr[0]), arr[1])
        }
        guard !nights.isEmpty else { return nil }
        return (Date(timeIntervalSince1970: ts), nights)
    }

    private func persistHRV(fetchedAt: Date, nights: [(date: Date, value: Double)]) {
        let ud = UserDefaults.standard
        ud.set(fetchedAt.timeIntervalSince1970, forKey: Self.hrvCacheDateKey)
        ud.set(nights.map { [$0.date.timeIntervalSince1970, $0.value] }, forKey: Self.hrvCacheNightsKey)
    }
```

- [ ] **Step 3: `refreshCore`에서 조회**

안정시심박 블록(`persistRHR(fetchedAt:samples:)` 호출이 있는 `else` 닫힘) 바로 뒤, `let dob = hk.dateOfBirth()` 앞에:

```swift
        // ── 수면 HRV: 안정시심박과 같은 캐시 정책(24시간). 실패하면 빈 배열 — 기능 전체가 조용히 빠진다.
        if hrvNights.isEmpty, let persisted = loadPersistedHRV() {
            hrvNights = persisted.nights
            hrvLastFetchedAt = persisted.fetchedAt
        }
        let hrvAge = hrvLastFetchedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if hrvNights.isEmpty || hrvAge >= 24 * 3600 {
            let t0 = CFAbsoluteTimeGetCurrent()
            let raw = (try? await hk.fetchSleepHRV()) ?? []
            let nights = mrHRVNightMedians(samples: raw)
            // 일시적 조회 실패(빈 결과)가 복원된 캐시를 메모리에서 지우지 않게 — 결과가 있을 때만 교체
            if !nights.isEmpty || hrvNights.isEmpty { hrvNights = nights }
            let fetchedAt = Date()
            hrvLastFetchedAt = fetchedAt
            if !nights.isEmpty { persistHRV(fetchedAt: fetchedAt, nights: nights) }
            #if DEBUG
            print(String(format: "[⏱ fetchSleepHRV] %.2fs · 조회범위 60일 · 샘플 %d건 · %d밤 · 캐시 미스",
                         CFAbsoluteTimeGetCurrent() - t0, raw.count, nights.count))
            #endif
        }
        #if DEBUG
        if let t = mrHRVTrend(nights: hrvNights, asOf: now) {
            let stateStr: String = {
                switch t.state { case .above: return "위"; case .within: return "범위 안"; case .below: return "아래" }
            }()
            print(String(format: "[HRV] 60일 %d밤 · 7일 평균 %.0fms(%d) · 4주 %.0f±%.0fms(%d) · CV 7일 %.0f%% / 4주 %.0f%% · %@%@",
                         hrvNights.count, t.sevenDayMean, t.sevenDayNights, t.baseline, t.baselineSD, t.baselineNights,
                         t.sevenDayCV * 100, t.baselineCV * 100, stateStr, t.isVolatile ? "·불안정" : ""))
        } else {
            print("[HRV] 60일 \(hrvNights.count)밤 · 추세 없음(7일 4밤·4주 14밤 미만)")
        }
        #endif
```

`now`는 `refreshCore` 안에서 이미 쓰는 기준 시각 변수다(`streakWeeks = mrActiveWeekStreak(runs: fetched, asOf: now)`). 이름이 다르면 그 변수로 맞춘다.

- [ ] **Step 4: 컴파일 확인**

검증 명령 실행. 기대: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Engine/MRHealthKit.swift MIMORunning/Engine/MREngineStore.swift
git commit -m "수면 HRV 추세 — 60일 SDNN 한 번 조회·밤별 중앙값 캐시(24h)·[HRV] 로그 (MREngineStore.hrvNights)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git show --stat HEAD
```

---

### Task 3: 조언 큐 `hrvReady`

**Files:**
- Modify: `MIMORunning/Engine/MRAdviceQueue.swift:112-125` (시그니처) · 이지 비율 블록 앞
- Modify: `MIMORunning/Engine/MREngineStore.swift` (`mrBuildAdvice` 호출 4곳: 415, 478, 785, 855 근처)
- Create: `MIMORunningTests/MRAdviceQueueHRVTests.swift`

- [ ] **Step 1: 테스트를 먼저 쓴다**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("MRAdviceQueue 수면 HRV 조언", .korean)
struct MRAdviceQueueHRVTests {

    private let cal = Calendar.current

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: Date())!)
    }

    private func run(daysAgo: Int, hr: Double = 140, interval: Bool = false) -> MRWorkout {
        MRWorkout(start: day(-daysAgo).addingTimeInterval(7 * 3600), durationMin: 50, distanceKm: 8,
                  hrAvg: hr, hrMax: 170, tempC: 15, humidity: nil, indoor: false, isInterval: interval)
    }

    /// 14일 동안 이지런 6회(2~3일 간격), 마지막은 어제.
    private func easyBlock() -> [MRWorkout] {
        [13, 11, 8, 6, 3, 1].map { run(daysAgo: $0) }   // 이미 오래된 것 → 최신 순(runs.last = 어제)
    }

    private func trend(state: MRHRVTrend.State, volatile: Bool = false) -> MRHRVTrend {
        MRHRVTrend(state: state, isVolatile: volatile, sevenDayMean: 37, baseline: 30, baselineSD: 3,
                   sevenDayCV: 0.05, baselineCV: 0.06, sevenDayNights: 7, baselineNights: 28)
    }

    private var phys: MRPhysiology {
        var p = MRPhysiology()
        p.lt1HR = MRInference(value: 150, confidence: .high, basis: [])
        return p
    }

    private func build(runs: [MRWorkout], trend: MRHRVTrend?) -> [MRAdvice] {
        mrBuildAdvice(runs: runs, phys: phys, plans: [], races: [], gaps: [], strengthPerWeek: 2,
                      fatigue: [], cadenceShift: nil, hrvTrend: trend, log: MRAdviceLog(), asOf: Date())
    }

    private func hrvAdvice(_ a: [MRAdvice]) -> MRAdvice? { a.first { $0.key == "hrvReady" } }

    @Test func readyHighAfterEasyBlockGivesAdvice() {
        let a = hrvAdvice(build(runs: easyBlock(), trend: trend(state: .above)))
        #expect(a != nil)
        #expect(a?.slot == "todayRun")
        #expect(a?.grade == "B")
        #expect(a?.text == "지난 2주는 이지런 위주였고 수면 HRV 7일 평균이 4주 기준선 위로 안정적이에요. 이번 주 강도 세션 하나 넣기 좋은 때예요.")
        #expect(a?.rationale == "HRV 7일 37ms · 4주 기준선 30ms · 14일 고강도 0회 · Vesterinen 2016(HRV 기반 강도 조절) · 회복 지표이지 체력 지표는 아님")
    }

    @Test func noAdviceWhenTrendMissing() {
        #expect(hrvAdvice(build(runs: easyBlock(), trend: nil)) == nil)
    }

    @Test func noAdviceWhenVolatile() {
        #expect(hrvAdvice(build(runs: easyBlock(), trend: trend(state: .above, volatile: true))) == nil)
    }

    @Test func noAdviceWhenWithinOrBelow() {
        #expect(hrvAdvice(build(runs: easyBlock(), trend: trend(state: .within))) == nil)
        #expect(hrvAdvice(build(runs: easyBlock(), trend: trend(state: .below))) == nil)
    }

    @Test func noAdviceWhenTwoHardRunsInFourteenDays() {
        var runs = easyBlock()
        runs[1] = run(daysAgo: 11, interval: true)
        runs[3] = run(daysAgo: 6, hr: 160)
        #expect(hrvAdvice(build(runs: runs, trend: trend(state: .above))) == nil)
    }

    @Test func oneHardRunStillCountsAsEasyBlock() {
        var runs = easyBlock()
        runs[2] = run(daysAgo: 8, interval: true)
        let a = hrvAdvice(build(runs: runs, trend: trend(state: .above)))
        #expect(a != nil)
        #expect(a?.rationale.contains("14일 고강도 1회") == true)
    }

    @Test func noAdviceWhenFewerThanFourRuns() {
        let runs = [run(daysAgo: 9), run(daysAgo: 5), run(daysAgo: 1)]
        #expect(hrvAdvice(build(runs: runs, trend: trend(state: .above))) == nil)
    }

    @Test func noAdviceWhenLastRunOlderThanThreeDays() {
        let runs = [13, 11, 9, 7, 5, 4].map { run(daysAgo: $0) }
        #expect(hrvAdvice(build(runs: runs, trend: trend(state: .above))) == nil)
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는 것을 본다**

검증 명령 실행. 기대: `error: extra argument 'hrvTrend' in call` → `** TEST BUILD FAILED **`

- [ ] **Step 3: 구현**

`mrBuildAdvice` 시그니처에 `heatHR` 다음 파라미터 추가:

```swift
                   heatHR: MRHeatHRModel = MRHeatHRModel(),
                   hrvTrend: MRHRVTrend? = nil,
                   log: MRAdviceLog,
                   asOf: Date) -> [MRAdvice] {
```

`// ── 이지 비율` 블록 바로 앞에:

```swift
    // ── 수면 HRV 위·안정 + 2주 이지 블록 → 강도 세션 제안
    //
    // HRV 기반으로 강도를 조절한 러너는 고강도 시간을 덜 쓰고도 같거나 더 나은 향상을 얻었다
    // (Vesterinen 2016, HRV-guided vs predefined). 저강도 기간에는 HRV가 오른다(Plews·Buchheit).
    // ⚠ HRV는 회복 상태 지표이지 체력 지표가 아니다 — "체력이 늘었다"고 말하지 않는다. 등급 B.
    // 아래/불안정 조언은 여기 없다 — 총평 훈련부하 줄이 담당.
    if let t = hrvTrend, t.isReadyHigh, days(last.date) <= 3 {
        let c = mrRecentHardRunCount(runs: runs, phys: phys, heatHR: heatHR, days: 14, asOf: asOf)
        if c.hard <= 1 && c.total >= 4 {
            out.append(MRAdvice(key: "hrvReady",
                text: "지난 2주는 이지런 위주였고 수면 HRV 7일 평균이 4주 기준선 위로 안정적이에요. 이번 주 강도 세션 하나 넣기 좋은 때예요.",
                rationale: String(format: "HRV 7일 %.0fms · 4주 기준선 %.0fms · 14일 고강도 %d회 · Vesterinen 2016(HRV 기반 강도 조절) · 회복 지표이지 체력 지표는 아님",
                                  t.sevenDayMean, t.baseline, c.hard),
                grade: "B", gainMin: 3, timeliness: 0.6, slot: "todayRun"))
        }
    }
```

`days(_:)`는 이 함수 상단에 이미 정의된 로컬 함수다(`cal.dateComponents([.day], from: d, to: startOfDay(asOf))`). `last`는 `guard let last = runs.last`로 이미 있다.

- [ ] **Step 4: 엔진 스토어 호출 4곳에 전달**

`MREngineStore.swift`에서 `mrBuildAdvice(` 호출마다 `heatHR: heatHR,` 다음 줄에 추가:

```swift
                               hrvTrend: mrHRVTrend(nights: hrvNights, asOf: now),
```

각 호출부의 기준 시각 변수명(`now` 또는 `asOf`)을 그 자리 것으로 맞춘다. 4곳 모두 바꿨는지 `grep -n "hrvTrend:" MIMORunning/Engine/MREngineStore.swift | wc -l` → `4`.

- [ ] **Step 5: 컴파일 확인**

검증 명령 실행. 기대: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 6: 커밋**

```bash
git add MIMORunning/Engine/MRAdviceQueue.swift MIMORunning/Engine/MREngineStore.swift MIMORunningTests/MRAdviceQueueHRVTests.swift
git commit -m "수면 HRV 추세 — 조언 큐 hrvReady: 위·안정 + 14일 고강도 ≤1·러닝 ≥4면 강도 세션 제안(B등급)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git show --stat HEAD
```

---

### Task 4: 총평 훈련부하 줄 문장

**Files:**
- Modify: `MIMORunning/Insight/RunSummary.swift` (`RunSummaryInput` · `loadEvidence` · `loadNext`)
- Modify: `MIMORunningTests/RunSummaryTests.swift` (`restedSuggestsQualitySession` 뒤)

- [ ] **Step 1: 테스트를 먼저 쓴다**

`RunSummaryTests.swift`의 `restedSuggestsQualitySession` 테스트 바로 뒤에 추가:

```swift
    // MARK: 수면 HRV 결합

    private func hrv(_ state: MRHRVTrend.State, volatile: Bool = false) -> MRHRVTrend {
        MRHRVTrend(state: state, isVolatile: volatile, sevenDayMean: 37.4, baseline: 29.6, baselineSD: 3,
                   sevenDayCV: 0.05, baselineCV: 0.06, sevenDayNights: 7, baselineNights: 28)
    }

    /// `restedSuggestsQualitySession`과 같은 입력 — 부하만으로는 "충분히 회복".
    private func restedInput() -> RunSummaryInput {
        var i = todayInput(); i.weekOverWeek = 0.05; i.acuteChronic = .steady; i.loadSentence = nil
        i.daysSinceHardRun = 3; i.streakDays = 0; i.todayIsHard = false
        return i
    }

    @Test func hrvEvidenceAppendsSevenDayAndBaseline() {
        var i = restedInput(); i.hrvTrend = hrv(.within)
        #expect(lines(i)[3].evidence?.hasSuffix(" · HRV 7일 37ms · 4주 30ms") == true)
        inEnglish { #expect(lines(i)[3].evidence?.hasSuffix(" · HRV 7-day 37ms · 4-wk 30ms") == true) }
    }

    @Test func hrvWithinKeepsRestedSentence() {
        var i = restedInput(); i.hrvTrend = hrv(.within); i.hardRunsLast14 = 0; i.runsLast14 = 6
        #expect(lines(i)[3].next == "충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.")
    }

    @Test func hrvReadyAfterEasyBlockSuggestsQualityWeek() {
        var i = restedInput(); i.hrvTrend = hrv(.above); i.hardRunsLast14 = 1; i.runsLast14 = 6
        #expect(lines(i)[3].next == "2주 이지런으로 회복이 쌓였어요. HRV가 4주 기준선 위로 안정적이라 이번 주 강도 세션 넣기 좋아요.")
    }

    @Test func hrvReadyWithRecentHardRunsSaysAbsorbing() {
        var i = restedInput(); i.hrvTrend = hrv(.above); i.hardRunsLast14 = 2; i.runsLast14 = 6
        #expect(lines(i)[3].next == "충분히 회복됐어요. 고강도 뒤에도 HRV가 기준선 위라 부하를 잘 흡수하고 있어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.")
    }

    @Test func hrvEasyBlockNeedsFourRuns() {
        // 러닝 3회면 이지 블록이 아니다 → 흡수 문장
        var i = restedInput(); i.hrvTrend = hrv(.above); i.hardRunsLast14 = 0; i.runsLast14 = 3
        #expect(lines(i)[3].next?.hasPrefix("충분히 회복됐어요. 고강도 뒤에도") == true)
    }

    @Test func hrvBelowSuppressesRested() {
        var i = restedInput(); i.hrvTrend = hrv(.below); i.hardRunsLast14 = 0; i.runsLast14 = 6
        #expect(lines(i)[3].next == "부하는 내려왔지만 HRV가 기준선 아래예요. 수면이나 생활 피로 쪽일 수 있으니 하루 더 편하게 가세요.")
    }

    @Test func hrvVolatileSuppressesRestedEvenWhenAbove() {
        var i = restedInput(); i.hrvTrend = hrv(.above, volatile: true); i.hardRunsLast14 = 0; i.runsLast14 = 6
        #expect(lines(i)[3].next == "부하는 내려왔지만 HRV가 기준선 아래예요. 수면이나 생활 피로 쪽일 수 있으니 하루 더 편하게 가세요.")
    }

    @Test func hrvSuppressedAppendsToJumpSentence() {
        var i = todayInput(); i.acuteChronic = .high; i.loadSentence = .high; i.streakDays = 0; i.todayIsHard = false
        i.hrvTrend = hrv(.below)
        #expect(lines(i)[3].next == "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요. HRV도 기준선 아래로 흔들리고 있어요.")
    }

    @Test func hrvAboveDoesNotTouchJumpSentence() {
        var i = todayInput(); i.acuteChronic = .high; i.loadSentence = .high; i.streakDays = 0; i.todayIsHard = false
        i.hrvTrend = hrv(.above)
        #expect(lines(i)[3].next == "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요.")
    }

    @Test func hrvNilChangesNothing() {
        var i = restedInput(); i.hrvTrend = nil; i.hardRunsLast14 = 0; i.runsLast14 = 6
        #expect(lines(i)[3].next == "충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.")
        #expect(lines(i)[3].evidence?.contains("HRV") == false)
    }
```

`todayInput()`이 만드는 훈련부하 줄이 index 3인지 기존 `restedSuggestsQualitySession`이 `lines(i)[3]`을 쓰는 것으로 확인된다. `inEnglish {}`는 `MIMORunningTests/Support/LanguageTrait.swift`의 헬퍼다.

- [ ] **Step 2: 컴파일이 깨지는 것을 본다**

검증 명령 실행. 기대: `error: value of type 'RunSummaryInput' has no member 'hrvTrend'` → `** TEST BUILD FAILED **`

- [ ] **Step 3: `RunSummaryInput` 필드**

`RunSummary.swift`의 `RunSummaryInput` 안, `vo2EightWeeksAgo` 아래에:

```swift
    /// 수면 HRV 7일 vs 4주 추세(러닝 날짜 기준). 없으면 HRV 문장·근거 모두 생략.
    var hrvTrend: MRHRVTrend? = nil
    /// 이 러닝 직전 14일(이 러닝 제외) 고강도 러닝 수 / 러닝 수 — `hrvTrend`가 있을 때만 채운다.
    var hardRunsLast14: Int? = nil
    var runsLast14: Int = 0
    /// 2주 이지 블록 — 고강도 1회 이하이고 러닝 4회 이상
    var isEasyBlock: Bool {
        guard let hard = hardRunsLast14 else { return false }
        return hard <= RunSummary.easyBlockMaxHard && runsLast14 >= RunSummary.easyBlockMinRuns
    }
```

`enum RunSummary` 상수 블록(`vo2DeltaEvidenceMin` 근처)에:

```swift
    /// 2주 이지 블록 판정 — 14일 고강도 최대 1회 · 러닝 최소 4회
    static let easyBlockMaxHard = 1
    static let easyBlockMinRuns = 4
```

- [ ] **Step 4: 근거 줄**

`loadEvidence`에서 `if i.todayEffortMissing, !parts.isEmpty { ... }` 블록 **앞**에 삽입:

```swift
        if let t = i.hrvTrend {
            let seven = Int(t.sevenDayMean.rounded()), base = Int(t.baseline.rounded())
            parts.append(L.s("HRV 7일 \(seven)ms · 4주 \(base)ms", "HRV 7-day \(seven)ms · 4-wk \(base)ms"))
        }
```

- [ ] **Step 5: 다음 행동 세 지점**

`loadNext`의 급증·단조·4일+ 분기를 교체:

```swift
        if jumped || i.loadSentence == .monotony || i.streakDays >= 4 {
            var s = L.s("다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요.",
                        "Take a 30–40 min recovery run or rest for the next day or two.")
            if i.hrvTrend?.isSuppressed == true {
                s += L.s(" HRV도 기준선 아래로 흔들리고 있어요.", " Your HRV is also wobbling below baseline.")
            }
            return s
        }
```

`if rested { return ... }` 블록을 교체:

```swift
        if rested {
            // HRV가 있으면 회복 판정을 한 번 더 거른다 — 부하는 내려왔어도 HRV가 아래·불안정이면 "충분히"라고 하지 않는다.
            // 위·안정이면 2주 이지 블록(회복이 쌓임)과 고강도 있음(잘 흡수함)을 나눠 말한다. 범위 안이면 기존 문장.
            if let t = i.hrvTrend {
                if t.isSuppressed {
                    return L.s("부하는 내려왔지만 HRV가 기준선 아래예요. 수면이나 생활 피로 쪽일 수 있으니 하루 더 편하게 가세요.",
                               "Load has come down, but your HRV is below baseline. It may be sleep or life stress — take one more easy day.")
                }
                if t.isReadyHigh {
                    return i.isEasyBlock
                        ? L.s("2주 이지런으로 회복이 쌓였어요. HRV가 4주 기준선 위로 안정적이라 이번 주 강도 세션 넣기 좋아요.",
                              "Two weeks of easy running have built up recovery. Your HRV is steadily above its 4-week baseline — a good week for a quality session.")
                        : L.s("충분히 회복됐어요. 고강도 뒤에도 HRV가 기준선 위라 부하를 잘 흡수하고 있어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.",
                              "You're well recovered. Your HRV stayed above baseline even after hard runs, so you're absorbing the load — a good time for a build-up or tempo run.")
                }
            }
            return L.s("충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.",
                      "You're well recovered — a good time for a build-up or tempo run.")
        }
```

- [ ] **Step 6: 컴파일 확인**

검증 명령 실행. 기대: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 7: 커밋**

```bash
git add MIMORunning/Insight/RunSummary.swift MIMORunningTests/RunSummaryTests.swift
git commit -m "수면 HRV 추세 — 총평 훈련부하 줄: 근거에 7일·4주 ms, 다음 행동에 이지 블록·흡수·억제 문장

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git show --stat HEAD
```

---

### Task 5: 빌더 조립과 배선

**Files:**
- Modify: `MIMORunning/Insight/RunSummaryBuilder.swift` (`Context` · `daysSinceHardRun` · `input`)
- Modify: `MIMORunning/Views/RunInsightCardView.swift` (`RunInsightSection` — 얇은 래퍼, 여기에 `hrvNights` 프로퍼티와 `RunInsightTabCard(...)` 전달)
- Modify: `MIMORunning/Views/RunInsightTabCard.swift` (`RunInsightTabCard.hrvNights` → `RhythmInsightCard.hrvNights` → `summaryLines`의 `Context(`)
- Modify: `MIMORunning/Views/ActivityDetailView.swift:224-236` (`summaryContext`) · `350-372` (`RunInsightSection(...)` 생성)

- [ ] **Step 1: `Context`에 `hrvNights`**

`RunSummaryBuilder.Context` 마지막 `let hrZonesFn` 아래에(memberwise init 기본값을 위해 `var`):

```swift
        /// 수면 HRV 밤별 중앙값(엔진 스토어 `hrvNights`). 비어 있으면 HRV 문장·근거 모두 빠진다.
        var hrvNights: [(date: Date, value: Double)] = []
```

- [ ] **Step 2: 고강도 판정 헬퍼 분리**

`daysSinceHardRun` 안의 `isHighZoneFraction`·`isHard` 판정을 파일 레벨 헬퍼로 빼고 둘 다 쓴다. `daysSinceHardRun`을 다음으로 교체:

```swift
    /// 고강도 러닝인가 — 체감 강도 7 이상 · 계획된 고강도 유형 · 존 4+5 비율 50% 이상 중 하나.
    /// 싼 검사부터: 체감 강도(딕셔너리) → 계획 유형(UserDefaults) → 존 분포(디스크 조회 가능) 순으로 단락평가.
    static func isHardRun(_ run: Activity, effortIndex: EffortIndex?,
                          workoutTypeFn: ((UUID) -> WorkoutType?)?,
                          hrZonesFn: ((UUID) -> [HRZoneData]?)?) -> Bool {
        if (effortIndex?.resolve(run.id)?.value ?? 0) >= 7 { return true }
        if workoutTypeFn?(run.id).map(FormNarrative.isPlannedHighIntensity) == true { return true }
        guard let zones = hrZonesFn?(run.id) else { return false }
        let total = zones.map(\.fraction).reduce(0, +)
        guard total > 0 else { return false }
        let highFrac = zones.filter { $0.id >= 4 }.map(\.fraction).reduce(0, +) / total
        return highFrac >= 0.5
    }

    /// 마지막 고강도 러닝까지의 일수. 28일 안에 없으면 nil — 총평 훈련부하 줄이 그 근거를 생략한다.
    private static func daysSinceHardRun(activity: Activity, history: [Activity],
                                        effortIndex: EffortIndex?,
                                        workoutTypeFn: ((UUID) -> WorkoutType?)?,
                                        hrZonesFn: ((UUID) -> [HRZoneData]?)?) -> Int? {
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -28, to: activity.date) ?? .distantPast
        let priorRuns = history
            .filter { $0.type == .running && $0.date < activity.date && $0.date >= since }
            .sorted { $0.date > $1.date }
        for run in priorRuns where isHardRun(run, effortIndex: effortIndex, workoutTypeFn: workoutTypeFn, hrZonesFn: hrZonesFn) {
            return cal.dateComponents([.day], from: cal.startOfDay(for: run.date), to: cal.startOfDay(for: activity.date)).day
        }
        return nil
    }

    /// 이 러닝 직전 14일(이 러닝 제외) 고강도 러닝 수 / 러닝 수 — 총평 HRV 결합 문장의 이지 블록 판정.
    static func hardRunsLast14(activity: Activity, history: [Activity],
                               effortIndex: EffortIndex?,
                               workoutTypeFn: ((UUID) -> WorkoutType?)?,
                               hrZonesFn: ((UUID) -> [HRZoneData]?)?) -> (hard: Int, total: Int) {
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -14, to: cal.startOfDay(for: activity.date)) ?? .distantPast
        let runs = history.filter { $0.type == .running && $0.id != activity.id && $0.date < activity.date && $0.date >= since }
        let hard = runs.filter { isHardRun($0, effortIndex: effortIndex, workoutTypeFn: workoutTypeFn, hrZonesFn: hrZonesFn) }.count
        return (hard, runs.count)
    }
```

- [ ] **Step 3: `input(_:)`에서 조립**

`input(_:)`의 `return input` 직전에:

```swift
        // 수면 HRV 추세는 러닝 날짜 기준(오래된 러닝을 열어도 당시 상태). 추세가 있을 때만 14일 고강도를 센다(존 분포 조회 비용).
        if !c.hrvNights.isEmpty, let t = mrHRVTrend(nights: c.hrvNights, asOf: c.activity.date) {
            input.hrvTrend = t
            let h = hardRunsLast14(activity: c.activity, history: c.history,
                                   effortIndex: c.effortIndex, workoutTypeFn: c.workoutTypeFn, hrZonesFn: c.hrZonesFn)
            input.hardRunsLast14 = h.hard
            input.runsLast14 = h.total
        }
```

- [ ] **Step 4: `RunInsightSection` 프로퍼티와 `summaryLines`**

`RunInsightTabCard.swift`의 `RunInsightSection` 프로퍼티 목록(`var heatHRModel: MRHeatHRModel? = nil` 아래)에:

```swift
    /// 수면 HRV 밤별 중앙값(엔진 스토어). 총평 HRV 결합 문장용.
    var hrvNights: [(date: Date, value: Double)] = []
```

`summaryLines`의 `RunSummaryBuilder.Context(` 호출에서 `hrZonesFn: hrZonesFn` 뒤에 `, hrvNights: hrvNights` 추가.

- [ ] **Step 5: `ActivityDetailView` 두 곳**

`summaryContext`의 `hrZonesFn: manager.hrZonesFromCache` 뒤에 `, hrvNights: engine.hrvNights`.
`RunInsightSection(...)` 생성부의 `heatHRModel: engine.heatHR,` 다음 줄에 `hrvNights: engine.hrvNights,`.

- [ ] **Step 6: 컴파일 확인**

검증 명령 실행. 기대: `** TEST BUILD SUCCEEDED **`. `RunSummaryBuilderTests`는 `Context`를 memberwise init으로 만들므로 기본값 덕에 그대로 컴파일돼야 한다 — 에러가 나면 `hrvNights`가 `let`으로 들어갔는지 확인.

- [ ] **Step 7: 커밋**

```bash
git add MIMORunning/Insight/RunSummaryBuilder.swift MIMORunning/Views/RunInsightTabCard.swift MIMORunning/Views/ActivityDetailView.swift
git commit -m "수면 HRV 추세 — 빌더가 러닝 날짜 기준 추세·14일 고강도를 조립, 리듬 카드·공유 카드 배선(isHardRun 공유)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git show --stat HEAD
```

---

### Task 6: 러닝별 HRV 쿼리 제거

**Files:**
- Modify: `MIMORunning/Health/HealthKitManager.swift:4030-4130`
- Modify: `MIMORunning/Health/HRVRecovery.swift`

- [ ] **Step 1: `fetchCondition`에서 HRV 조회 제거**

캐시 갱신 분기:

```swift
            if needsSleep {
                updated.sleepScore   = await querySleepScore(nightBefore: activity.date)
                updated.sleepChecked = true
                updated.sleepVersion = ActivityCondition.currentSleepVersion
            }
```

최초 조회 분기:

```swift
        // Never fetched → weather + sleep in parallel. (HRV는 엔진 스토어가 60일을 한 번에 가져온다 — MRHRVTrend)
        async let weather = ConditionService.fetchWeather(date: activity.date, coordinate: firstCoordinate)
        async let sleep   = querySleepScore(nightBefore: activity.date)
        let result = ActivityCondition(weather: await weather, sleepScore: await sleep,
                                       hrvRecovery: nil, sleepChecked: true,
                                       sleepVersion: ActivityCondition.currentSleepVersion)
```

`// MARK: - HRV Recovery` 섹션(`queryNightHRVMedian`·`queryHRVRecovery` 두 함수, 주석 포함)을 통째로 삭제한다. `sleepVersion`은 올리지 않는다(기존 캐시의 `hrvRecovery` 값은 무해하고, 올리면 전 러닝 수면 재계산이 돈다).

- [ ] **Step 2: `HRVRecovery.swift` 정리**

`hrvMedian`·`hrvSD`는 이제 리더가 없다 — 삭제. `HRVRecovery`·`RecoveryLevel` 위 주석을 교체:

```swift
// MARK: - HRV Recovery (deprecated)
//
// ⚠ 더 이상 계산하지 않는다. 조건 캐시(`ActivityCondition.hrvRecovery`) 디코딩 호환용으로만 남긴다.
//   수면 HRV는 엔진 스토어가 60일을 한 번에 가져와 `mrHRVTrend`(7일 vs 4주 기준선)로 본다 — Engine/MRHRVTrend.swift.
```

`grep -rn "hrvMedian\|hrvSD\|queryHRVRecovery\|queryNightHRVMedian" MIMORunning MIMORunningTests` → 결과 없음.

- [ ] **Step 3: 컴파일 확인**

검증 명령 실행. 기대: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 4: 커밋**

```bash
git add MIMORunning/Health/HealthKitManager.swift MIMORunning/Health/HRVRecovery.swift
git commit -m "수면 HRV 추세 — 러닝별 1박 HRV 쿼리(8회/러닝) 제거, HRVRecovery는 캐시 디코딩 호환용으로만

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git show --stat HEAD
```

---

## 실기기 확인 포인트 (사용자)

1. 앱 실행 후 Xcode 콘솔 `[HRV]` 로그 — `60일 N밤`에서 N이 40 이상이면 정상. 4주 14밤 미만이면 기능이 조용히 빠진다.
2. 최근 러닝 상세 → 리듬 카드 총평 훈련부하 줄 펼침 — 근거 끝에 `HRV 7일 …ms · 4주 …ms`, 다음 행동이 이지 블록 문장인지.
3. 홈 조언 카드에 `hrvReady`("지난 2주는 이지런 위주였고…")가 뜨는지. 조건: 위·안정 + 14일 고강도 ≤ 1 + 러닝 ≥ 4 + 마지막 러닝 3일 이내.
4. 공유 카드 "총평" 칩 — 같은 문장이 그대로 나오는지(§5.8).
