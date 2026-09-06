# 내구성 훈련 반영 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 하프 계획에 "대회 페이스" 단계와 실행 문구를 추가하고, 롱런 후반 케이던스 붕괴(S1)를 감지해 근력·플라이오 운동을 시의적절하게 제안하는 규칙 엔진과 표시 카드를 만든다.

**Architecture:** 기존 `MRRacePlanner`(계획)·`MRAdviceQueue`(조언 큐) 위에 얹는다. 새 순수 함수 모듈 `MRDurabilityCheck`가 km 스플릿에서 S1을 계산하고, `HealthKitManager`가 캐시된 상세에서 롱런 요약을 만들어 `MREngineStore.updateAdvice`로 넘긴다. 조언은 지금까지 화면에 없었으므로 성장 탭에 `MRAdviceCardView`를 새로 놓는다. 사실 판단은 전부 결정적 규칙이고 AI는 쓰지 않는다.

**Tech Stack:** Swift 5 / SwiftUI / HealthKit(재조회 없음, 캐시만) / Swift Testing(`import Testing`) · Xcode 26.3 · iPhone 17 Pro 시뮬레이터

**설계 문서:** `docs/superpowers/specs/2026-09-06-durability-training-design.md`

---

## 파일 구조

| 파일 | 역할 | 작업 |
|---|---|---|
| `MIMORunning/Engine/MRRacePlanner.swift` | 하프 대회 페이스 단계 + 문구 + 근거 주석 | 수정 |
| `MIMORunning/Engine/MRTypes.swift` | 모델 버전 2→3 | 수정 |
| `MIMORunning/Views/MRRacePlanView.swift` | 문구 번역 치환 | 수정 |
| `MIMORunning/Engine/MRDurabilityCheck.swift` | S1 계산·집계 (순수 함수) | 생성 |
| `MIMORunning/Health/HealthKitManager.swift` | 롱런 피로 요약 생성 (캐시만) | 수정 |
| `MIMORunning/Engine/MRAdviceQueue.swift` | 근력 문구·억제·durability·cadenceCue·exercises | 수정 |
| `MIMORunning/Engine/MREngineStore.swift` | updateAdvice 시그니처 확장, 호출부 4곳 | 수정 |
| `MIMORunning/Engine/MRDebugView.swift` | mrBuildAdvice 호출부 | 수정 |
| `MIMORunning/Views/GrowthView.swift` | 입력 전달 + 카드 배치 | 수정 |
| `MIMORunning/Views/MRAdviceCardView.swift` | 조언 카드 | 생성 |
| `MIMORunningTests/MRRacePlannerRacePaceTests.swift` | 계획 테스트 | 생성 |
| `MIMORunningTests/MRDurabilityCheckTests.swift` | S1 테스트 | 생성 |
| `MIMORunningTests/MRAdviceQueueDurabilityTests.swift` | 조언 큐 테스트 | 생성 |

**테스트 실행 명령** (모든 태스크 공통, 스위트 이름만 바꾼다):

```bash
xcodebuild test -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MIMORunningTests/<SuiteTypeName> 2>&1 | grep -E 'Test (Suite|Case)|passed|failed|error:' | tail -30
```

빌드만 확인할 때:

```bash
xcodebuild build -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E 'error:|BUILD' | tail -10
```

새 Swift 파일은 Xcode 프로젝트가 폴더 참조(file system synchronized group)가 아니면 프로젝트에 추가해야 한다. 빌드 에러 `cannot find 'X' in scope`가 나면 Xcode에서 파일을 타깃에 추가한다. 테스트 파일은 `MIMORunningTests` 타깃에 넣는다.

---

### Task 1: 플래너 — 대회 페이스 헬퍼 함수 (순수 함수 + 테스트)

**Files:**
- Modify: `MIMORunning/Engine/MRRacePlanner.swift` (파일 끝에 추가)
- Test: `MIMORunningTests/MRRacePlannerRacePaceTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("MRRacePlanner 대회 페이스 단계")
struct MRRacePlannerRacePaceTests {

    @Test func segmentMinutesIs15ForLongRunsAnd10ForShort() {
        #expect(mrRacePaceSegmentMinutes(longRunMin: 140) == 15)
        #expect(mrRacePaceSegmentMinutes(longRunMin: 60) == 15)
        #expect(mrRacePaceSegmentMinutes(longRunMin: 59) == 10)
    }

    @Test func trainingRacePaceForHalfIgnoresHeatAndTaper() {
        // 하프 등가 110분 → 110×60/21.0975 = 312.8 초/km
        let p = mrTrainingRacePaceSecPerKm(halfEquivMin: 110, distanceM: MRDistance.dH,
                                           weeklyKm: 40, longestKm: 21, finishes: 0)
        #expect(abs(p - 312.8) < 0.2)
    }

    @Test func trainingRacePaceForFullUsesMarathonModel() {
        let b = bMarathonModel(weeklyKm: 50, longestKm: 28, finishes: 1).b
        let expected = 110 * pow(2.0, b) * 60 / 42.195
        let p = mrTrainingRacePaceSecPerKm(halfEquivMin: 110, distanceM: MRDistance.dF,
                                           weeklyKm: 50, longestKm: 28, finishes: 1)
        #expect(abs(p - expected) < 0.01)
    }
}
```

- [ ] **Step 2: 테스트가 컴파일 실패하는지 확인**

Run: 위 공통 명령, `<SuiteTypeName>` = `MRRacePlannerRacePaceTests`
Expected: `error: cannot find 'mrRacePaceSegmentMinutes' in scope`

- [ ] **Step 3: 헬퍼 구현** — `MRRacePlanner.swift` 파일 끝(`mrWeeksToReach` 뒤)에 추가

```swift
// MARK: - 대회 페이스 구간 (롱런 후반)
//
// ⚠ "롱런 마지막 15분을 대회 페이스로"는 코칭 관행이다.
//   Fokkema 2020·Van Hooren 2024 어디에도 없고 통제 연구를 찾지 못했다.
//   근거가 나오면 바꿀 것.
// ⚠ 15분은 자료의 예시값. 임의로 정함. 롱런이 60분 미만이면 10분.

func mrRacePaceSegmentMinutes(longRunMin: Double) -> Int {
    longRunMin < 60 ? 10 : 15
}

/// 훈련용 대회 페이스 (초/km).
///
/// ⚠ 예측 기록 기준이다. 목표 기록이 아니다 — 목표가 예측보다 빠르면
///   D-day 카드가 경고하는 바로 그 과속 배분이 된다.
/// ⚠ 기온 보정 전 · 테이퍼 이득 전 값이다. 훈련은 대회 기온에서 하지 않는다.
func mrTrainingRacePaceSecPerKm(halfEquivMin: Double, distanceM: Double,
                                weeklyKm: Double, longestKm: Double, finishes: Int) -> Double {
    let minutes: Double
    if distanceM >= MRDistance.dF {
        minutes = halfEquivMin * pow(2.0, bMarathonModel(weeklyKm: weeklyKm,
                                                          longestKm: longestKm,
                                                          finishes: finishes).b)
    } else {
        minutes = halfEquivMin * pow(distanceM / MRDistance.dH, 1.06)
    }
    return minutes * 60.0 / (distanceM / 1000.0)
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: 공통 명령, `MRRacePlannerRacePaceTests`
Expected: 3 tests passed

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Engine/MRRacePlanner.swift MIMORunningTests/MRRacePlannerRacePaceTests.swift
git commit -m "플래너: 대회 페이스 구간 헬퍼 (구간 길이·훈련용 대회 페이스)"
```

---

### Task 2: 플래너 — 하프에도 "대회 페이스" 단계 + 실행 문구

**Files:**
- Modify: `MIMORunning/Engine/MRRacePlanner.swift:326-336` (단계 조건), `:368-405` (proj·breakdown)
- Modify: `MIMORunning/Engine/MRTypes.swift:16` (모델 버전)
- Modify: `MIMORunning/Views/MRRacePlanView.swift:17-26` (번역)
- Test: `MIMORunningTests/MRRacePlannerRacePaceTests.swift`

- [ ] **Step 1: 실패하는 테스트 추가** — 같은 스위트에 아래 세 테스트 추가

```swift
    private func makeProfile() -> MRProfile {
        var p = MRProfile()
        p.weeklyKm4w = 30; p.longestRun16wKm = 14
        p.maxWeeklyKm52w = 45; p.runsPerWeek = 4; p.marathonFinishes = 0
        return p
    }

    private func buildPlan(distanceM: Double, weeks: Int = 20) -> MRRacePlan? {
        let today = Date()
        let race = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: today)!
        return mrBuildPlan(raceDate: race, distanceM: distanceM, today: today,
                           profile: makeProfile(), halfEquivMin: 110,
                           easyPaceSecPerKm: 400, heat: MRHeatModel(), raceTempC: 15,
                           runsPerWeek: 4)
    }

    @Test func halfPlanGetsRacePaceWeeksWithSegmentText() throws {
        let plan = try #require(buildPlan(distanceM: MRDistance.dH))
        let rp = plan.weeks.filter { $0.phase == "대회 페이스" }
        #expect(!rp.isEmpty)
        // 문구에 구간 길이(15)와 페이스(/km)가 들어간다. 언어 무관 토큰만 검사.
        #expect(rp.allSatisfy { $0.breakdown.contains("15") && $0.breakdown.contains("/km") })
        // 회복·테이퍼 주에는 구간 문구가 없다
        let rest = plan.weeks.filter { $0.phase == "회복" || $0.phase == "테이퍼" }
        #expect(rest.allSatisfy { !$0.breakdown.contains("/km") })
    }

    @Test func tenKPlanHasNoRacePaceWeeks() throws {
        let plan = try #require(buildPlan(distanceM: MRDistance.d10))
        #expect(plan.weeks.allSatisfy { $0.phase != "대회 페이스" })
    }

    @Test func fullPlanRacePaceWeeksAlsoGetSegmentText() throws {
        var p = makeProfile()
        p.weeklyKm4w = 45; p.longestRun16wKm = 22; p.maxWeeklyKm52w = 60
        let today = Date()
        let race = Calendar.current.date(byAdding: .day, value: 7 * 24, to: today)!
        let plan = try #require(mrBuildPlan(raceDate: race, distanceM: MRDistance.dF, today: today,
                                            profile: p, halfEquivMin: 110, easyPaceSecPerKm: 400,
                                            heat: MRHeatModel(), raceTempC: 15, runsPerWeek: 4))
        let rp = plan.weeks.filter { $0.phase == "대회 페이스" }
        #expect(!rp.isEmpty)
        #expect(rp.allSatisfy { $0.breakdown.contains("/km") })
    }
```

- [ ] **Step 2: 테스트 실패 확인**

Run: 공통 명령, `MRRacePlannerRacePaceTests`
Expected: `halfPlanGetsRacePaceWeeksWithSegmentText` FAIL (rp 비어 있음), `fullPlanRacePaceWeeksAlsoGetSegmentText` FAIL (breakdown에 "/km" 없음)

- [ ] **Step 3: 단계 조건 변경** — `MRRacePlanner.swift` 약 326행

현재:
```swift
                // 풀마라톤 후반(75%~) → "대회 페이스" (상한 도달 여부와 무관)
                // 롱런이 상한에 닿아 더 이상 안 늘어난다 → "유지"
                // 아직 증가 중 → "늘리기"
                if distanceM >= MRDistance.dF && Double(i) > Double(buildWeeks) * 0.75 {
                    phase = "대회 페이스"
```
변경:
```swift
                // 하프 이상 후반(75%~) → "대회 페이스" (상한 도달 여부와 무관)
                //   5K·10K 제외 — 근거(Fokkema 2020)가 하프·풀에 한정된다.
                // 롱런이 상한에 닿아 더 이상 안 늘어난다 → "유지"
                // 아직 증가 중 → "늘리기"
                if distanceM >= MRDistance.dH && Double(i) > Double(buildWeeks) * 0.75 {
                    phase = "대회 페이스"
```

- [ ] **Step 4: breakdown 문구 추가** — 같은 파일, 테이퍼 문구 블록 바로 뒤(`if phase == "테이퍼" { breakdown = ... }` 다음)에 추가

```swift
        if phase == "대회 페이스" {
            // ⚠ 페이스는 기온·테이퍼 보정 전 예측값. 훈련은 대회 기온에서 하지 않는다.
            let racePace = mrTrainingRacePaceSecPerKm(
                halfEquivMin: halfEquivMin, distanceM: distanceM,
                weeklyKm: projVol, longestKm: peakLong, finishes: profile.marathonFinishes)
            let seg = mrRacePaceSegmentMinutes(longRunMin: mins)
            let paceStr = mrFormatPace(racePace) + "/km"
            breakdown = each >= 1.5
                ? L.s("롱런 \(Int(lrDisplay))km · 마지막 \(seg)분은 \(paceStr) + 이지 \(eachStr) × \(others)회",
                      "Long run \(Int(lrDisplay))km · last \(seg) min at \(paceStr) + Easy \(eachStr) × \(others)x")
                : L.s("롱런 \(Int(lrDisplay))km · 마지막 \(seg)분은 \(paceStr) + 이지 \(others)회",
                      "Long run \(Int(lrDisplay))km · last \(seg) min at \(paceStr) + Easy \(others)x")
        }
```

`projVol`·`peakLong`·`mins`·`each`·`eachStr`·`lrDisplay`·`others`는 모두 같은 루프 안에서 이미 선언된 변수다. `mins`는 `let mins = lr * (easyPaceSecPerKm ?? 420) / 60.0`.

- [ ] **Step 5: 근거 주석 추가** — `mrBuildPlan` 위 doc comment의 "목표 롱런 28km" 항목 뒤에 추가

```swift
/// · 하프 목표 롱런 21km — Fokkema 2020 (Scand J Med Sci Sports 30(9):1692–1704,
///   하프군 n=556): 최장 롱런 >21km β −3.87분 (95% CI −6.31~−1.44),
///   주간 >32km β −4.19분 (−6.52~−1.85). 기준군 15–21km · 20–32km/wk.
///   ⚠ 이전 기록 미보정 관찰연구 — 빠른 러너가 원래 더 뛴다는 교란이 남아 있다.
///   ⚠ "21km 이상 = 12~15분"은 이 논문에 없다. 그건 풀의 <25km +13.4분이다.
///
/// · 롱런 후반 대회 페이스 구간 — 코칭 관행. 통제 연구 없음. mrRacePaceSegmentMinutes 참조.
```

- [ ] **Step 6: 모델 버전 올리기** — `MRTypes.swift`

`static let current = 2` → `static let current = 3`, 히스토리 주석에 한 줄 추가:
```swift
///   3 — 하프 대회 페이스 단계 + 롱런 후반 구간 문구
```

- [ ] **Step 7: 번역 치환 추가** — `MRRacePlanView.swift` `localizedBreakdown`

`.replacingOccurrences(of: "강도는 그대로", with: "Keep the intensity")` 뒤에 추가:
```swift
        .replacingOccurrences(of: "마지막 ", with: "last ")
        .replacingOccurrences(of: "분은 ", with: " min at ")
```
⚠ 이 두 줄은 `"회"` → `"x"` 치환보다 **앞에** 두어야 한다(순서는 위치만 지키면 된다).

- [ ] **Step 8: 테스트 통과 확인**

Run: 공통 명령, `MRRacePlannerRacePaceTests`
Expected: 6 tests passed

- [ ] **Step 9: 기존 테스트 회귀 확인**

Run: 공통 명령, `MRRobustnessTests`
Expected: passed (실패 시 원인은 대부분 phase 문자열 의존 — 테스트 파일에서 `"대회 페이스"` 검색해 확인)

- [ ] **Step 10: 커밋**

```bash
git add MIMORunning/Engine/MRRacePlanner.swift MIMORunning/Engine/MRTypes.swift MIMORunning/Views/MRRacePlanView.swift MIMORunningTests/MRRacePlannerRacePaceTests.swift
git commit -m "플래너: 하프에도 대회 페이스 단계 · 롱런 후반 구간 문구 · 모델 버전 3"
```

---

### Task 3: MRDurabilityCheck — S1 계산 순수 함수

**Files:**
- Create: `MIMORunning/Engine/MRDurabilityCheck.swift`
- Test: `MIMORunningTests/MRDurabilityCheckTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("MRDurabilityCheck S1 피로 시 케이던스 붕괴")
struct MRDurabilityCheckTests {

    /// km 스플릿 생성기. cadences[i]가 nil이면 케이던스 없음.
    private func splits(paces: [Double], cadences: [Int?], hrs: [Int?]? = nil,
                        lastPartialM: Double? = nil) -> [SplitData] {
        var out: [SplitData] = []
        for (i, p) in paces.enumerated() {
            out.append(SplitData(id: i + 1, distanceM: 1000, duration: p,
                                 avgHeartRate: hrs?[i] ?? nil, avgCadence: cadences[i],
                                 avgPower: nil, avgGroundContactTime: nil,
                                 avgStrideLength: nil, avgVerticalOscillation: nil))
        }
        if let m = lastPartialM {
            out.append(SplitData(id: paces.count + 1, distanceM: m, duration: m / 1000 * 400,
                                 avgHeartRate: nil, avgCadence: 170, avgPower: nil,
                                 avgGroundContactTime: nil, avgStrideLength: nil,
                                 avgVerticalOscillation: nil))
        }
        return out
    }

    private func fatigue(q1Pace: Double = 400, q4Pace: Double = 400,
                         q1Cad: Double = 170, q4Cad: Double = 170,
                         hr: Double? = nil, daysAgo: Int = 1) -> MRLongRunFatigue {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return MRLongRunFatigue(id: UUID(), date: Calendar.current.startOfDay(for: d),
                                distanceKm: 16, durationMin: 105,
                                q1PaceSecPerKm: q1Pace, q4PaceSecPerKm: q4Pace,
                                q1Cadence: q1Cad, q4Cadence: q4Cad,
                                firstHalfAvgHR: hr, cadenceCoverage: 1.0)
    }

    // MARK: 자격

    @Test func eligibilityRequiresDistanceDurationAndType() {
        #expect(MRDurabilityCheck.isEligibleLongRun(distanceKm: 10, durationMin: 60, longest16wKm: 12, workoutType: .easy))
        #expect(!MRDurabilityCheck.isEligibleLongRun(distanceKm: 9, durationMin: 60, longest16wKm: 12, workoutType: .easy))
        #expect(!MRDurabilityCheck.isEligibleLongRun(distanceKm: 10, durationMin: 59, longest16wKm: 12, workoutType: .easy))
        // 최근 16주 최장 20km → 하한 14km
        #expect(!MRDurabilityCheck.isEligibleLongRun(distanceKm: 12, durationMin: 80, longest16wKm: 20, workoutType: .longRun))
        #expect(MRDurabilityCheck.isEligibleLongRun(distanceKm: 14, durationMin: 80, longest16wKm: 20, workoutType: .longRun))
        #expect(!MRDurabilityCheck.isEligibleLongRun(distanceKm: 16, durationMin: 90, longest16wKm: 20, workoutType: .interval))
        #expect(!MRDurabilityCheck.isEligibleLongRun(distanceKm: 16, durationMin: 90, longest16wKm: 20, workoutType: .buildUp))
        #expect(!MRDurabilityCheck.isEligibleLongRun(distanceKm: 16, durationMin: 90, longest16wKm: 20, workoutType: .tempo))
    }

    // MARK: 요약

    @Test func summaryExcludesFirstKmAndLastPartialSplit() throws {
        // 12 스플릿 + 부분 스플릿. km1 제외 → 11개 → 분기 크기 max(2, 11/4)=2
        // Q1 = km2,3 · Q4 = km11,12
        let paces: [Double] = [500, 400, 400, 400, 400, 400, 400, 400, 400, 400, 420, 420]
        let cads: [Int?]    = [150, 170, 170, 170, 170, 170, 170, 170, 170, 170, 164, 164]
        let s = try #require(MRDurabilityCheck.summarize(id: UUID(), date: Date(), distanceKm: 12.5,
                                                          durationMin: 84, splits: splits(paces: paces, cadences: cads, lastPartialM: 500)))
        #expect(abs(s.q1PaceSecPerKm - 400) < 0.01)
        #expect(abs(s.q4PaceSecPerKm - 420) < 0.01)
        #expect(abs(s.q1Cadence - 170) < 0.01)
        #expect(abs(s.q4Cadence - 164) < 0.01)
        #expect(abs(s.cadenceCoverage - 1.0) < 0.01)
    }

    @Test func summaryReturnsNilWhenTooFewSplitsOrLowCoverage() {
        let seven = splits(paces: Array(repeating: 400, count: 7), cadences: Array(repeating: 170, count: 7))
        #expect(MRDurabilityCheck.summarize(id: UUID(), date: Date(), distanceKm: 7, durationMin: 47, splits: seven) == nil)
        // 10개 중 케이던스 7개(70%) → 커버리지 미달
        var cads: [Int?] = Array(repeating: 170, count: 10)
        cads[2] = nil; cads[5] = nil; cads[8] = nil
        let low = splits(paces: Array(repeating: 400, count: 10), cadences: cads)
        #expect(MRDurabilityCheck.summarize(id: UUID(), date: Date(), distanceKm: 10, durationMin: 67, splits: low) == nil)
    }

    // MARK: 판정

    @Test func evaluateReturnsNilOutsidePaceGate() {
        // 6% 느려짐 → 평가 불가
        let f = fatigue(q1Pace: 400, q4Pace: 424, q1Cad: 170, q4Cad: 160)
        #expect(MRDurabilityCheck.evaluate(f, recentMedianPace: nil, maxHR: nil) == nil)
    }

    @Test func evaluateReturnsNilOnEarlyOverpaceOrEarlyHighHR() {
        // 초반 과속: 최근 중앙 420, Q1 390 (< 399)
        let over = fatigue(q1Pace: 390, q4Pace: 395, q1Cad: 170, q4Cad: 160)
        #expect(MRDurabilityCheck.evaluate(over, recentMedianPace: 420, maxHR: nil) == nil)
        // 초반 역치: maxHR 190 × 0.85 = 161.5, 전반 165
        let high = fatigue(q1Pace: 400, q4Pace: 400, q1Cad: 170, q4Cad: 160, hr: 165)
        #expect(MRDurabilityCheck.evaluate(high, recentMedianPace: 400, maxHR: 190) == nil)
        // 전반 158이면 통과
        let ok = fatigue(q1Pace: 400, q4Pace: 400, q1Cad: 170, q4Cad: 160, hr: 158)
        #expect(MRDurabilityCheck.evaluate(ok, recentMedianPace: 400, maxHR: 190) == true)
    }

    @Test func evaluateThresholdIsThreePercent() {
        // 2% 하락 → false, 3.5% 하락 → true
        #expect(MRDurabilityCheck.evaluate(fatigue(q1Cad: 170, q4Cad: 166.6), recentMedianPace: nil, maxHR: nil) == false)
        #expect(MRDurabilityCheck.evaluate(fatigue(q1Cad: 170, q4Cad: 164), recentMedianPace: nil, maxHR: nil) == true)
    }

    // MARK: 집계

    @Test func aggregateTriggersOnTwoOfThree() {
        let fs = [fatigue(q1Cad: 170, q4Cad: 164, daysAgo: 2),
                  fatigue(q1Cad: 170, q4Cad: 170, daysAgo: 9),
                  fatigue(q1Cad: 170, q4Cad: 163, daysAgo: 16)]
        let v = MRDurabilityCheck.aggregate(fatigue: fs, runs: [], maxHR: nil, asOf: Date())
        #expect(v.evaluated == 3)
        #expect(v.positive == 2)
        #expect(v.triggered)
    }

    @Test func aggregateNeedsTwoEvaluableRuns() {
        let v = MRDurabilityCheck.aggregate(fatigue: [fatigue(q1Cad: 170, q4Cad: 160)],
                                            runs: [], maxHR: nil, asOf: Date())
        #expect(!v.triggered)
    }

    @Test func aggregateUsesOnlyLatestThreeWithinEightWeeks() {
        let fs = [fatigue(q1Cad: 170, q4Cad: 170, daysAgo: 2),
                  fatigue(q1Cad: 170, q4Cad: 170, daysAgo: 9),
                  fatigue(q1Cad: 170, q4Cad: 170, daysAgo: 16),
                  fatigue(q1Cad: 170, q4Cad: 160, daysAgo: 23),   // 4번째 — 무시
                  fatigue(q1Cad: 170, q4Cad: 160, daysAgo: 70)]   // 8주 밖 — 무시
        let v = MRDurabilityCheck.aggregate(fatigue: fs, runs: [], maxHR: nil, asOf: Date())
        #expect(v.evaluated == 3)
        #expect(v.positive == 0)
        #expect(!v.triggered)
    }

    @Test func aggregateReportsLatestDropPercent() {
        let fs = [fatigue(q1Cad: 170, q4Cad: 161.5, daysAgo: 0),  // −5%
                  fatigue(q1Cad: 170, q4Cad: 164, daysAgo: 7)]
        let v = MRDurabilityCheck.aggregate(fatigue: fs, runs: [], maxHR: nil, asOf: Date())
        #expect(v.triggered)
        #expect(abs((v.latestDropPct ?? 0) - 5.0) < 0.1)
        #expect(v.latestPositiveIsToday)
    }
}
```

- [ ] **Step 2: 컴파일 실패 확인**

Run: 공통 명령, `MRDurabilityCheckTests`
Expected: `error: cannot find 'MRDurabilityCheck' in scope`

- [ ] **Step 3: 구현** — `MIMORunning/Engine/MRDurabilityCheck.swift` 생성

```swift
import Foundation

// MARK: - 내구성 판단 — 롱런 후반 케이던스 붕괴(S1)
//
// "다리가 지치면 발걸음이 느려진다"를 본인 데이터로 잰다.
// 같은 롱런 안에서 첫 25% 구간과 마지막 25% 구간의 케이던스를 비교한다.
//
// ⚠ 페이스 게이트(±5%)가 핵심이다. 후반에 느려졌으면 케이던스 하락이
//   속도 변화로 설명되므로 판정하지 않는다(nil). false가 아니다.
// ⚠ 초반 과속·초반 역치는 근력 문제가 아니다 → RunInsightEngine.analyzeFade와
//   같은 규칙으로 제외한다(중앙 페이스 ×0.95 / maxHR ×0.85).
// ⚠ 수직 진동은 쓰지 않는다. 폼 카드가 Apple Watch MAPE 19%를 이유로
//   추세 판정에서 제외한 것과 일관되게 케이던스만 쓴다.
// ⚠ 3% 임계는 임의로 정함. 170spm 기준 5spm — 페도미터 정수 반올림(1spm)보다 충분히 크다.
// ⚠ 근력·플라이오가 이 패턴을 늦춘다는 직접 근거는 없다. 있는 것은
//   Blagrove 2018 (Sports Med 48(5):1117–1149) "근력 추가 → 경제성·기록 개선"이다.
//   그래서 이 조언은 B등급이다.

/// 롱런 한 건의 피로 요약. HealthKit 상세 캐시의 km 스플릿에서 만든다.
struct MRLongRunFatigue: Codable, Sendable, Identifiable {
    let id: UUID
    let date: Date                 // startOfDay
    let distanceKm: Double
    let durationMin: Double
    let q1PaceSecPerKm: Double     // 첫 25% 구간 (km1 제외)
    let q4PaceSecPerKm: Double     // 마지막 25% 구간 (마지막 부분 스플릿 제외)
    let q1Cadence: Double
    let q4Cadence: Double
    let firstHalfAvgHR: Double?    // 스플릿 avgHeartRate 전반 평균
    let cadenceCoverage: Double    // 케이던스 있는 스플릿 비율 (0~1)

    var cadenceDropPct: Double {
        guard q1Cadence > 0 else { return 0 }
        return (1 - q4Cadence / q1Cadence) * 100
    }
}

enum MRDurabilityCheck {

    static let cadenceDropFrac  = 0.03    // 임의 (주석 참조)
    static let paceGateFrac     = 0.05
    static let minSplits        = 8
    static let minCoverage      = 0.8
    static let windowDays       = 56      // 8주
    static let maxRunsConsidered = 3

    // MARK: 자격

    /// 롱런 자격: 러닝·야외·비인터벌은 호출 쪽에서 거른다. 여기서는 거리·시간·유형.
    static func isEligibleLongRun(distanceKm: Double, durationMin: Double,
                                  longest16wKm: Double, workoutType: WorkoutType) -> Bool {
        if workoutType == .interval || workoutType == .buildUp || workoutType == .tempo { return false }
        let minKm = max(10.0, longest16wKm * 0.7)
        return distanceKm >= minKm && durationMin >= 60
    }

    // MARK: 요약

    /// km 스플릿 → 피로 요약. 스플릿 8개 미만 · 케이던스 커버리지 80% 미만이면 nil.
    static func summarize(id: UUID, date: Date, distanceKm: Double, durationMin: Double,
                          splits: [SplitData]) -> MRLongRunFatigue? {
        guard splits.count >= minSplits else { return nil }
        var body = splits.sorted { $0.id < $1.id }
        // km1 제외 (워밍업), 마지막 부분 스플릿 제외
        body.removeFirst()
        if let last = body.last, last.distanceM < 1000 { body.removeLast() }
        guard body.count >= 4 else { return nil }

        let withCad = body.filter { $0.avgCadence != nil }.count
        let coverage = Double(withCad) / Double(body.count)
        guard coverage >= minCoverage else { return nil }

        let q = max(2, body.count / 4)
        let q1 = Array(body.prefix(q))
        let q4 = Array(body.suffix(q))

        func pace(_ s: [SplitData]) -> Double {
            let dist = s.map(\.distanceM).reduce(0, +)
            let dur  = s.map(\.duration).reduce(0, +)
            return dist > 0 ? dur / (dist / 1000) : 0
        }
        func cad(_ s: [SplitData]) -> Double? {
            let v = s.compactMap(\.avgCadence).map(Double.init)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        guard let c1 = cad(q1), let c4 = cad(q4), c1 > 0 else { return nil }

        let half = Array(body.prefix(max(1, body.count / 2)))
        let hrs = half.compactMap(\.avgHeartRate).map(Double.init)
        let hr: Double? = hrs.isEmpty ? nil : hrs.reduce(0, +) / Double(hrs.count)

        return MRLongRunFatigue(id: id, date: Calendar.current.startOfDay(for: date),
                                distanceKm: distanceKm, durationMin: durationMin,
                                q1PaceSecPerKm: pace(q1), q4PaceSecPerKm: pace(q4),
                                q1Cadence: c1, q4Cadence: c4,
                                firstHalfAvgHR: hr, cadenceCoverage: coverage)
    }

    // MARK: 판정

    /// S1 판정. nil = 평가 불가 (페이스 게이트 밖 · 초반 과속 · 초반 역치).
    static func evaluate(_ f: MRLongRunFatigue, recentMedianPace: Double?, maxHR: Double?) -> Bool? {
        guard f.q1PaceSecPerKm > 0, f.q1Cadence > 0 else { return nil }
        let paceDiff = abs(f.q4PaceSecPerKm - f.q1PaceSecPerKm) / f.q1PaceSecPerKm
        guard paceDiff <= paceGateFrac else { return nil }
        if let med = recentMedianPace, med > 0, f.q1PaceSecPerKm < med * 0.95 { return nil }
        if let mhr = maxHR, mhr > 0, let hr = f.firstHalfAvgHR, hr >= mhr * 0.85 { return nil }
        return f.q4Cadence < f.q1Cadence * (1 - cadenceDropFrac)
    }

    // MARK: 집계

    struct Verdict {
        let evaluated: Int
        let positive: Int
        let latestDropPct: Double?        // 가장 최근 평가된 롱런의 케이던스 하락률 (양수 = 하락)
        let latestDate: Date?
        let latestPositiveIsToday: Bool
        var triggered: Bool { evaluated >= 2 && positive >= 2 }
    }

    /// 최근 8주 자격 롱런 중 평가 가능한 것 최신순 최대 3개. 2개 이상 true → 발동.
    static func aggregate(fatigue: [MRLongRunFatigue], runs: [MRWorkout],
                          maxHR: Double?, asOf: Date) -> Verdict {
        let cal = Calendar.current
        let today = cal.startOfDay(for: asOf)
        let cutoff = cal.date(byAdding: .day, value: -windowDays, to: today) ?? today
        let recent = fatigue.filter { $0.date >= cutoff && $0.date <= today }
                            .sorted { $0.date > $1.date }

        var results: [(f: MRLongRunFatigue, s1: Bool)] = []
        for f in recent {
            let med = medianPace(runs: runs, before: f.date)
            if let s1 = evaluate(f, recentMedianPace: med, maxHR: maxHR) {
                results.append((f, s1))
            }
            if results.count >= maxRunsConsidered { break }
        }
        let latest = results.first
        return Verdict(evaluated: results.count,
                       positive: results.filter(\.s1).count,
                       latestDropPct: latest.map { $0.f.cadenceDropPct },
                       latestDate: latest?.f.date,
                       latestPositiveIsToday: latest.map { $0.s1 && cal.isDate($0.f.date, inSameDayAs: today) } ?? false)
    }

    /// 해당 날짜 직전 8주 러닝 페이스 중앙값. RunInsightEngine.analyzeFade와 같은 창.
    static func medianPace(runs: [MRWorkout], before date: Date) -> Double? {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -windowDays, to: date) ?? date
        let paces = runs.filter { $0.date >= start && $0.date < date }
                        .compactMap(\.paceSecPerKm).sorted()
        guard !paces.isEmpty else { return nil }
        return paces[paces.count / 2]
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: 공통 명령, `MRDurabilityCheckTests`
Expected: 10 tests passed. `cannot find 'MRDurabilityCheck'`가 계속 나오면 Xcode에서 새 파일을 MIMORunning 타깃에 추가.

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Engine/MRDurabilityCheck.swift MIMORunningTests/MRDurabilityCheckTests.swift
git commit -m "내구성 판단: 롱런 후반 케이던스 붕괴(S1) 계산·집계 순수 함수"
```

---

### Task 4: HealthKitManager — 롱런 피로 요약 (캐시만, 쿼리 없음)

**Files:**
- Modify: `MIMORunning/Health/HealthKitManager.swift` (`strengthPerWeek4w` 바로 아래에 추가, 약 108행)

- [ ] **Step 1: 함수 추가**

```swift
    /// 최근 8주 자격 롱런의 피로 요약. 상세 캐시(메모리 → 디스크)만 읽는다 — HealthKit 재조회 없음.
    /// 상세 캐시가 없는 롱런은 건너뛴다(사용자가 상세를 연 적 없거나 백필 전).
    func longRunFatigueSummaries(asOf: Date = Date()) -> [MRLongRunFatigue] {
        let cal = Calendar.current
        let cutoff8w  = cal.date(byAdding: .day, value: -56,  to: asOf) ?? asOf
        let cutoff16w = cal.date(byAdding: .day, value: -112, to: asOf) ?? asOf
        let runs16w = activities.filter { $0.type == .running && $0.date >= cutoff16w && $0.date <= asOf }
        let longest16w = runs16w.map { $0.distance / 1000 }.max() ?? 0

        return runs16w.filter { $0.date >= cutoff8w }.compactMap { a in
            guard let det = detailFromCache(a.id) else { return nil }
            guard !det.routeCoordinates.isEmpty else { return nil }          // 야외만
            let wt = cachedWorkoutTypeForStats(for: a.id) ?? det.workoutType
            guard MRDurabilityCheck.isEligibleLongRun(distanceKm: a.distance / 1000,
                                                      durationMin: a.duration / 60,
                                                      longest16wKm: longest16w,
                                                      workoutType: wt) else { return nil }
            return MRDurabilityCheck.summarize(id: a.id, date: a.date,
                                               distanceKm: a.distance / 1000,
                                               durationMin: a.duration / 60,
                                               splits: det.splits)
        }
    }
```

- [ ] **Step 2: 빌드 확인**

Run: 빌드 명령
Expected: `BUILD SUCCEEDED`. `detailFromCache`가 private이면 `func detailFromCache` 앞의 접근 제한자를 지운다(파일 약 1374행, 이미 외부에서 쓰는 함수다).

- [ ] **Step 3: 커밋**

```bash
git add MIMORunning/Health/HealthKitManager.swift
git commit -m "HealthKitManager: 롱런 피로 요약 (상세 캐시만 사용)"
```

---

### Task 5: MRAdviceQueue — 근력 문구·억제·durability·cadenceCue

**Files:**
- Modify: `MIMORunning/Engine/MRAdviceQueue.swift`
- Test: `MIMORunningTests/MRAdviceQueueDurabilityTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("MRAdviceQueue 내구성·근력·케이던스 조언")
struct MRAdviceQueueDurabilityTests {

    private let cal = Calendar.current

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: Date())!)
    }

    private func runs(count: Int = 12) -> [MRWorkout] {
        (0..<count).map { i in
            MRWorkout(start: day(-i * 3), durationMin: 60, distanceKm: 10,
                      hrAvg: 150, hrMax: 170, tempC: 15, humidity: nil,
                      indoor: false, isInterval: false)
        }.reversed()
    }

    private func fatigue(drop: Double, daysAgo: Int) -> MRLongRunFatigue {
        MRLongRunFatigue(id: UUID(), date: day(-daysAgo), distanceKm: 16, durationMin: 105,
                         q1PaceSecPerKm: 400, q4PaceSecPerKm: 400,
                         q1Cadence: 170, q4Cadence: 170 * (1 - drop),
                         firstHalfAvgHR: nil, cadenceCoverage: 1.0)
    }

    private var triggeredFatigue: [MRLongRunFatigue] {
        [fatigue(drop: 0.05, daysAgo: 0), fatigue(drop: 0.04, daysAgo: 7), fatigue(drop: 0.0, daysAgo: 14)]
    }

    private func cadenceShift(delta: Double) -> MRFormShift {
        let m = mrFormMetrics.first { $0.key == "cadence" }!
        return MRFormShift(metric: m, recentMean: 0, baseMean: 0, delta: delta,
                           mdc: 1.0, weeksConsistent: 5, r2: nil)
    }

    private func build(fatigue: [MRLongRunFatigue] = [], races: [MRTargetRace] = [],
                       gaps: [MRGap] = [], strength: Double = 2.0,
                       cadenceShift: MRFormShift? = nil, runs r: [MRWorkout]? = nil) -> [MRAdvice] {
        mrBuildAdvice(runs: r ?? runs(), phys: MRPhysiology(), plans: [], races: races,
                      gaps: gaps, strengthPerWeek: strength, fatigue: fatigue,
                      cadenceShift: cadenceShift, log: MRAdviceLog(), asOf: Date())
    }

    private func keys(_ a: [MRAdvice]) -> Set<String> { Set(a.map(\.key)) }

    // MARK: durability

    @Test func durabilityFiresOnTriggeredFatigueWithExercises() throws {
        let a = build(fatigue: triggeredFatigue)
        let d = try #require(a.first { $0.key == "durability" })
        #expect(d.slot == "todayRun")          // 최신 롱런이 오늘
        #expect(abs(d.timeliness - 0.8) < 0.001)
        #expect(!d.exercises.isEmpty)
        #expect(d.grade == "B")
    }

    @Test func durabilityWeeklyWhenLatestLongRunNotToday() throws {
        let fs = [fatigue(drop: 0.05, daysAgo: 2), fatigue(drop: 0.04, daysAgo: 9)]
        let d = try #require(build(fatigue: fs).first { $0.key == "durability" })
        #expect(d.slot == "weekly")
        #expect(abs(d.timeliness - 0.4) < 0.001)
    }

    @Test func durabilityTimelinessBumpsWhenNoStrengthSessions() throws {
        let d = try #require(build(fatigue: triggeredFatigue, strength: 0.5).first { $0.key == "durability" })
        #expect(abs(d.timeliness - 0.9) < 0.001)
    }

    @Test func durabilitySuppressesStrength() {
        let k = keys(build(fatigue: triggeredFatigue, strength: 0.0))
        #expect(k.contains("durability"))
        #expect(!k.contains("strength"))
    }

    @Test func strengthStillFiresWithoutDurability() {
        let k = keys(build(strength: 0.0))
        #expect(k.contains("strength"))
        #expect(!k.contains("durability"))
    }

    @Test func noDurabilityWhenNotTriggered() {
        let fs = [fatigue(drop: 0.05, daysAgo: 0), fatigue(drop: 0.0, daysAgo: 7), fatigue(drop: 0.0, daysAgo: 14)]
        #expect(!keys(build(fatigue: fs)).contains("durability"))
    }

    // MARK: 억제

    @Test func allThreeSuppressedDuringTaper() {
        let half = MRTargetRace(date: day(10), distanceM: MRDistance.dH, name: "하프")
        let k = keys(build(fatigue: triggeredFatigue, races: [half], strength: 0.0,
                           cadenceShift: cadenceShift(delta: -3)))
        #expect(!k.contains("durability"))
        #expect(!k.contains("strength"))
        #expect(!k.contains("cadenceCue"))
    }

    @Test func notSuppressedByTenKTaper() {
        let tenK = MRTargetRace(date: day(10), distanceM: MRDistance.d10, name: "10K")
        #expect(keys(build(fatigue: triggeredFatigue, races: [tenK])).contains("durability"))
    }

    @Test func suppressedDuringRecoveryAfterFinishedRace() {
        // 7일 전 하프 완주 기록 (21.1km)
        var r = runs()
        r.append(MRWorkout(start: day(-7), durationMin: 110, distanceKm: 21.1,
                           hrAvg: 165, hrMax: 185, tempC: 15, humidity: nil,
                           indoor: false, isInterval: false))
        let half = MRTargetRace(date: day(-7), distanceM: MRDistance.dH, name: "하프")
        let k = keys(build(fatigue: triggeredFatigue, races: [half], strength: 0.0, runs: r))
        #expect(!k.contains("durability"))
        #expect(!k.contains("strength"))
    }

    @Test func notSuppressedByPastRaceWithoutFinishRecord() {
        let half = MRTargetRace(date: day(-7), distanceM: MRDistance.dH, name: "하프")
        #expect(keys(build(fatigue: triggeredFatigue, races: [half])).contains("durability"))
    }

    @Test func suppressedWithinThreeWeeksOfGapReturn() {
        let g = MRGap(start: day(-40), end: day(-10), days: 30, cause: "동기 저하",
                      preSpike: false, stepsDropped: false)
        let k = keys(build(fatigue: triggeredFatigue, gaps: [g], strength: 0.0))
        #expect(!k.contains("durability"))
        #expect(!k.contains("strength"))
    }

    // MARK: cadenceCue

    @Test func cadenceCueFiresOnRealCadenceDropWithoutS1() throws {
        let fs = [fatigue(drop: 0.0, daysAgo: 2), fatigue(drop: 0.0, daysAgo: 9)]
        let c = try #require(build(fatigue: fs, cadenceShift: cadenceShift(delta: -3)).first { $0.key == "cadenceCue" })
        #expect(c.slot == "weekly")
        #expect(!c.exercises.isEmpty)
    }

    @Test func cadenceCueSilentWhenAnyS1Positive() {
        let fs = [fatigue(drop: 0.05, daysAgo: 2), fatigue(drop: 0.0, daysAgo: 9)]
        #expect(!keys(build(fatigue: fs, cadenceShift: cadenceShift(delta: -3))).contains("cadenceCue"))
    }

    @Test func cadenceCueSilentWhenShiftIsUpwardOrNotReal() {
        #expect(!keys(build(cadenceShift: cadenceShift(delta: +3))).contains("cadenceCue"))
        let m = mrFormMetrics.first { $0.key == "cadence" }!
        let weak = MRFormShift(metric: m, recentMean: 0, baseMean: 0, delta: -0.5,
                               mdc: 1.0, weeksConsistent: 5, r2: nil)   // isPractical 실패
        #expect(!keys(build(cadenceShift: weak)).contains("cadenceCue"))
    }
}
```

- [ ] **Step 2: 컴파일 실패 확인**

Run: 공통 명령, `MRAdviceQueueDurabilityTests`
Expected: `error: extra arguments at positions ... in call` (mrBuildAdvice에 races/fatigue/cadenceShift 없음)

- [ ] **Step 3: MRAdvice에 exercises 필드 추가** — `MRAdviceQueue.swift` 상단 struct

```swift
struct MRAdvice: Identifiable {
    let id = UUID()
    let key: String
    let text: String
    let rationale: String       // 근거. UI에서 탭하면 보인다
    let grade: String           // A / B / C
    let gainMin: Double         // 기대 이득(분)
    let timeliness: Double      // 0~1
    let slot: String            // todayRun / weekly / raceCountdown
    /// 구체 운동 목록. 비어 있으면 UI에 목록을 그리지 않는다.
    var exercises: [String] = []
```
(나머지 `score`는 그대로.)

- [ ] **Step 4: 억제 헬퍼 추가** — `mrBuildAdvice` 위에 추가

```swift
// MARK: - 근력·폼 조언 공통 억제
//
// ⚠ 이 시기에 새 고중량·새 큐를 넣으면 회복만 잡아먹는다.
//   · 테이퍼: 하프 이상 대회 D-14 이내 (Bosquet 2007 — 볼륨만 줄이고 강도 유지, 새 자극 금지)
//   · 회복: 완주 기록이 있는 하프 이상 대회 D+14 이내 (근손상·염증 정상화 기간)
//   · 복귀: 공백 종료 21일 이내

/// 억제 사유. nil이면 억제 없음.
func mrStrengthAdviceSuppression(races: [MRTargetRace], runs: [MRWorkout],
                                 gaps: [MRGap], asOf: Date) -> String? {
    let cal = Calendar.current
    let today = cal.startOfDay(for: asOf)
    for r in races where r.distanceM >= MRDistance.dH {
        let d = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: r.date)).day ?? 999
        if d >= 0 && d <= 14 { return "테이퍼 D-\(d)" }
        if d < 0 && d >= -14, mrFinishedRun(for: r, runs: runs) != nil { return "대회 회복 D+\(-d)" }
    }
    if let g = gaps.last,
       let since = cal.dateComponents([.day], from: cal.startOfDay(for: g.end), to: today).day,
       since >= 0, since <= 21 {
        return "공백 복귀 \(since)일"
    }
    return nil
}
```

- [ ] **Step 5: mrBuildAdvice 시그니처 확장 + 근력 문구 변경 + 새 조언** — 기존 `mrBuildAdvice`를 아래로 교체한다. 기존 본문(스파이크·복귀·이지 비율·보급·상한)은 그대로 두고 근력 블록만 바꾸고 새 블록을 추가한다.

시그니처:
```swift
func mrBuildAdvice(runs: [MRWorkout],
                   phys: MRPhysiology,
                   plans: [MRRacePlan],
                   races: [MRTargetRace] = [],
                   gaps: [MRGap],
                   strengthPerWeek: Double,
                   fatigue: [MRLongRunFatigue] = [],
                   cadenceShift: MRFormShift? = nil,
                   log: MRAdviceLog,
                   asOf: Date) -> [MRAdvice] {
```

기존 `// ── 근력운동` 블록 전체를 아래로 교체:
```swift
    // ── 내구성 · 근력 · 케이던스 (공통 억제 적용)
    let suppression = mrStrengthAdviceSuppression(races: races, runs: runs, gaps: gaps, asOf: asOf)
    #if DEBUG
    if let s = suppression { print("[조언] 근력·폼 조언 억제 — \(s)") }
    #endif

    // ── 내구성 (S1: 롱런 후반 케이던스 붕괴)
    //
    // 발동 조건은 S1 집계 하나다. 근력 세션 횟수는 발동 조건이 아니다 —
    // 워치의 근력 기록이 부정확해 근력을 하는 사람에게도 잔소리가 되기 때문.
    let verdict = MRDurabilityCheck.aggregate(fatigue: fatigue, runs: runs,
                                              maxHR: phys.hrMax?.value, asOf: asOf)
    var durabilityShown = false
    if suppression == nil, verdict.triggered {
        durabilityShown = true
        let dropStr = String(format: "%.0f", max(verdict.latestDropPct ?? 0, 0))
        let text: String
        let slot: String
        var timeliness: Double
        if verdict.latestPositiveIsToday {
            slot = "todayRun"; timeliness = 0.8
            text = "오늘 롱런 후반에 케이던스가 \(dropStr)% 떨어졌어요. 최근 롱런 \(verdict.evaluated)번 중 \(verdict.positive)번이 그랬습니다. 다리가 지치면 발걸음이 느려지는 패턴이에요. 무거운 무게를 드는 근력운동과 점프 운동이 이걸 늦춥니다."
        } else {
            slot = "weekly"; timeliness = 0.4
            text = "최근 롱런 후반에 발걸음이 느려지는 패턴이 반복됐어요. 무거운 무게를 드는 근력운동과 점프 운동이 후반 페이스를 지키는 데 도움이 됩니다."
        }
        if strengthPerWeek < 1.0 { timeliness += 0.1 }
        out.append(MRAdvice(key: "durability", text: text,
            rationale: String(format: "최근 8주 롱런 %d회 중 %d회 후반 케이던스 ≥3%%↓ · Blagrove 2018 메타분석(근력·플라이오 → 경제성) · 3%% 임계는 임의",
                              verdict.evaluated, verdict.positive),
            grade: "B", gainMin: 6, timeliness: timeliness, slot: slot,
            exercises: [
                "근력 주 2회 20~30분 — 스쿼트·데드리프트·한발 운동·카프 레이즈 중 2~3개",
                "무거운 무게 = 8회 이하로 힘든 무게, 세트당 3~5회",
                "점프 — 제자리 홉·바운딩·언덕 스프린트 중 하나, 10분 이내",
                "롱런 다음날은 피하고, 이지런 날에",
            ]))
    }

    // ── 근력운동 (기본)
    //
    // 러닝에 근력을 더하면 러닝만 할 때보다 경제성과 기록이 좋아진다는
    // 메타분석이 여럿 있다(Blagrove 2018, Sports Med 48(5):1117–1149).
    // 그 메타분석 자체가 고중량·플라이오메트릭을 다루므로 문구를 그렇게 쓴다.
    // ⚠ durability가 이미 나왔으면 같은 주제를 두 번 말하지 않는다.
    if suppression == nil, !durabilityShown, strengthPerWeek < 1.5 {
        out.append(MRAdvice(key: "strength",
            text: "무거운 무게를 드는 근력운동과 점프 운동을 주 2회 함께 하면 다리가 후반까지 버팁니다. 주 30분이면 충분해요.",
            rationale: String(format: "최근 4주 근력 세션 주 %.1f회 · Blagrove 2018 메타분석", strengthPerWeek),
            grade: "A", gainMin: 4, timeliness: 0.2, slot: "weekly"))
    }

    // ── 케이던스 큐 (유일한 폼 제안)
    //
    // Van Hooren 2024 (Sports Med 54(5):1269–1316): 케이던스 r=−0.20.
    // 개입 근거는 Heiderscheit 2011 (MSSE 43(2):296–302): 케이던스 +5~10% → 관절 부하 감소.
    // ⚠ 지친 뒤 하락(S1)이 하나라도 있으면 그건 내구성 문제다 — 큐를 주지 않는다.
    if suppression == nil, verdict.positive == 0,
       let s = cadenceShift, s.metric.key == "cadence", s.isReal, s.delta < 0 {
        out.append(MRAdvice(key: "cadenceCue",
            text: String(format: "같은 페이스에서 케이던스가 3개월 새 %.0f spm 내려갔어요. 이지런 한 번에 10분만 평소보다 5%% 빠른 발걸음으로 달려보세요.", abs(s.delta)),
            rationale: String(format: "MRFormShift cadence Δ=%.1f spm (MDC %.1f) · Van Hooren 2024 r=−0.20 · Heiderscheit 2011 (+5~10%% 케이던스)", s.delta, s.mdc),
            grade: "B", gainMin: 2, timeliness: 0.3, slot: "weekly",
            exercises: [
                "이지런 중 10분, 메트로놈 앱을 평소 케이던스 +5%로",
                "보폭을 줄인다는 느낌으로. 속도는 올리지 않는다",
            ]))
    }
```

- [ ] **Step 6: 테스트 통과 확인**

Run: 공통 명령, `MRAdviceQueueDurabilityTests`
Expected: 14 tests passed. `MRTargetRace(date:distanceM:name:)` 컴파일 에러가 나면 `MRTargetRace(date: ..., distanceM: ..., name: ..., startTime: nil, place: nil)`로 바꾼다.

- [ ] **Step 7: 기존 조언 테스트 회귀**

Run: 공통 명령, `MRAdviceLogTests`
Expected: passed

- [ ] **Step 8: 커밋**

```bash
git add MIMORunning/Engine/MRAdviceQueue.swift MIMORunningTests/MRAdviceQueueDurabilityTests.swift
git commit -m "조언 큐: 내구성(S1)·케이던스 큐·근력 문구 보강·테이퍼/회복/복귀 억제·운동 목록"
```

---

### Task 6: MREngineStore·GrowthView — 입력 전달

**Files:**
- Modify: `MIMORunning/Engine/MREngineStore.swift:92` (저장 변수), `:322-324`, `:382-384`, `:673-688`, `:756-758` (호출부)
- Modify: `MIMORunning/Engine/MRDebugView.swift:279-281`
- Modify: `MIMORunning/Views/GrowthView.swift:262` (onAppear), `:437-441` (폼 shift)

- [ ] **Step 1: 저장 변수 추가** — `MREngineStore.swift` `private var storedStrengthPerWeek: Double = 0` 아래

```swift
    private var storedFatigue: [MRLongRunFatigue] = []
    private var storedCadenceShift: MRFormShift? = nil
```

- [ ] **Step 2: 호출부 4곳 수정** — `mrBuildAdvice(` 호출 4곳(약 322·382·678·756행)을 전부 아래 형태로. `runs:`의 첫 인자는 각 위치의 기존 값(`fetched` 또는 `runs`)을 유지하고, `gaps:`도 기존 값 유지.

```swift
        advice = mrBuildAdvice(runs: <기존값>, phys: phys, plans: plans,
                               races: userInput.races,
                               gaps: <기존값>, strengthPerWeek: storedStrengthPerWeek,
                               fatigue: storedFatigue, cadenceShift: storedCadenceShift,
                               log: adviceLog, asOf: now)
```

- [ ] **Step 3: updateAdvice 시그니처 확장** — 기존 `func updateAdvice(strengthPerWeek: Double)`를 교체

```swift
    // MARK: - 근력 횟수·롱런 피로·케이던스 이동 업데이트 (HealthKit 재읽기 없음)

    func updateAdvice(strengthPerWeek: Double,
                      fatigue: [MRLongRunFatigue]? = nil,
                      cadenceShift: MRFormShift?? = nil) {
        guard case .ready = state else { return }
        storedStrengthPerWeek = strengthPerWeek
        if let f = fatigue { storedFatigue = f }
        if let c = cadenceShift { storedCadenceShift = c }
        let now = Date()
        advice = mrBuildAdvice(runs: runs, phys: phys, plans: plans,
                               races: userInput.races,
                               gaps: gaps, strengthPerWeek: storedStrengthPerWeek,
                               fatigue: storedFatigue, cadenceShift: storedCadenceShift,
                               log: adviceLog, asOf: now)
        // ⚠ record()는 조언 카드 .onAppear에서 — 판정 시점 호출 금지
        let raceDayVisible3 = raceDayCard.map { MRRaceDayView.shouldShow($0) } ?? false
        todayCard = mrTodayCard(runs: runs, phys: phys, plans: plans,
                                raceDayCardVisible: raceDayVisible3,
                                advice: advice, asOf: now)
    }
```

`cadenceShift: MRFormShift??` — 바깥 nil은 "바꾸지 않음", 안쪽 nil은 "이동 없음으로 설정".

- [ ] **Step 4: MRDebugView 호출부** — 약 279행

```swift
                let advice = mrBuildAdvice(runs: runs, phys: phys, plans: plans,
                                           races: input.races,
                                           gaps: [], strengthPerWeek: 0,
                                           log: MRAdviceLog(), asOf: Date())
```
(`input`이 그 스코프의 `MRUserInput` 변수명이 아니면 실제 이름으로 바꾼다. 없으면 `races:` 인자를 생략해도 된다 — 기본값 `[]`.)

- [ ] **Step 5: GrowthView onAppear** — 약 262행

```swift
                        engine.updateAdvice(strengthPerWeek: manager.strengthPerWeek4w,
                                            fatigue: manager.longRunFatigueSummaries())
```

- [ ] **Step 6: GrowthView 폼 shift 전달** — `computeFormObservation` 안, `shifts` 루프가 끝난 직후(`// 최근 3개월 안에 14일 이상 공백이 있으면` 주석 앞)에 추가

```swift
        // 케이던스 이동을 조언 엔진에 넘긴다 — 엔진이 폼 계산을 중복하지 않는다.
        engine.updateAdvice(strengthPerWeek: manager.strengthPerWeek4w,
                            cadenceShift: .some(shifts.first { $0.metric.key == "cadence" }))
```

- [ ] **Step 7: 빌드 확인**

Run: 빌드 명령
Expected: `BUILD SUCCEEDED`

- [ ] **Step 8: 커밋**

```bash
git add MIMORunning/Engine/MREngineStore.swift MIMORunning/Engine/MRDebugView.swift MIMORunning/Views/GrowthView.swift
git commit -m "엔진: 롱런 피로·케이던스 이동·대회 목록을 조언 큐에 전달"
```

---

### Task 7: MRAdviceCardView — 조언 카드 (성장 탭)

**Files:**
- Create: `MIMORunning/Views/MRAdviceCardView.swift`
- Modify: `MIMORunning/Views/GrowthView.swift:233` (`weekSummarySection` 아래)

- [ ] **Step 1: 카드 뷰 생성**

```swift
import SwiftUI

/// 조언 카드 — 큐 상위 2건. 탭하면 운동 목록과 근거가 펼쳐진다.
///
/// ⚠ 조언이 0건이면 카드를 그리지 않는다. "제안 없음" 문구 금지.
/// ⚠ record()는 여기 .onAppear에서만 호출한다. 판정 시점에 기록하면
///   화면에 뜬 적 없는 항목이 "보여줬다"로 기록돼 영영 노출되지 않는다.
struct MRAdviceCardView: View {
    @EnvironmentObject private var engine: MREngineStore
    @State private var expanded: Set<String> = []

    private var items: [MRAdvice] { Array(engine.advice.prefix(2)) }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLanguage.shared.s("제안", "Suggestions"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
                ForEach(items) { a in
                    row(a)
                }
            }
            .padding(14)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12), in: RoundedRectangle(cornerRadius: 14))
            .onAppear {
                engine.adviceLog.record(items.map(\.key), asOf: Date())
                MRAdviceLogStore.save(engine.adviceLog)
            }
        }
    }

    @ViewBuilder
    private func row(_ a: MRAdvice) -> some View {
        let open = expanded.contains(a.key)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(Theme.violet).frame(width: 6, height: 6).padding(.top, 6)
                Text(a.text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 4)
            }
            if open {
                if !a.exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(a.exercises, id: \.self) { e in
                            Text("· " + e)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.leading, 14)
                }
                Text(a.rationale)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 14)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) {
                if open { expanded.remove(a.key) } else { expanded.insert(a.key) }
            }
        }
    }
}
```

`Theme.violet`은 `MIMORunning/Theme/Theme.swift`에 있다. `MREngineStore`가 `@EnvironmentObject`가 아니라 `@ObservedObject`/`@StateObject`로 주입되면 GrowthView가 쓰는 방식과 같게 맞춘다(GrowthView 상단의 `engine` 선언을 확인).

- [ ] **Step 2: 성장 탭 배치** — `GrowthView.swift` `weekSummarySection` 바로 아래

```swift
                            weekSummarySection
                            MRAdviceCardView()
                            heatmapSection
```

- [ ] **Step 3: 빌드 확인**

Run: 빌드 명령
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: 시뮬레이터 확인**

시뮬레이터에서 앱 실행 → 성장 탭. 조언이 있으면 "제안" 카드가 주간 요약 아래에 보이고, 탭하면 운동 목록·근거가 펼쳐진다. 조언이 없으면 카드가 없다. 디버그 콘솔에서 `[조언]` 로그로 억제 사유 확인.

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Views/MRAdviceCardView.swift MIMORunning/Views/GrowthView.swift
git commit -m "성장 탭: 조언 카드 (운동 목록·근거 펼침, 노출 기록)"
```

---

### Task 8: 전체 테스트 + FEATURES.md 갱신

**Files:**
- Modify: `FEATURES.md` (6장 데이터 엔진 절)

- [ ] **Step 1: 전체 테스트**

```bash
xcodebuild test -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E 'passed|failed|error:' | tail -20
```
Expected: 실패 0

- [ ] **Step 2: FEATURES.md에 항목 추가** — 6장(데이터 엔진) 끝에

```markdown
### 6.7 내구성 판단 엔진 (`MRDurabilityCheck`)

- 롱런 첫 25% vs 마지막 25% 케이던스 비교 (페이스 ±5% 게이트, 초반 과속·역치 제외)
- 최근 8주 롱런 3회 중 2회 이상 ≥3% 하락 → 근력·플라이오 제안 (`durability`, B등급)
- 3개월 케이던스 하락(MDC 통과) + S1 없음 → 케이던스 큐 제안 (`cadenceCue`, B등급)
- 억제: 하프 이상 대회 D-14 · 완주 후 D+14 · 공백 복귀 21일
- 표시: 성장 탭 조언 카드 (`MRAdviceCardView`), 운동 목록·근거 펼침
- 근거: Fokkema 2020 · Van Hooren 2024 · Blagrove 2018 · Heiderscheit 2011
```

그리고 "훈련 계획" 관련 항목이 있으면 "하프 이상 빌드 후반 25%: 대회 페이스 단계 — 롱런 마지막 15분 예측 페이스" 한 줄 추가.

- [ ] **Step 3: 커밋**

```bash
git add FEATURES.md
git commit -m "FEATURES: 내구성 판단 엔진·하프 대회 페이스 단계 기록"
```
