# 회복 곡선 모양(τ) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 운동 후 1분·2분 회복 심박의 비에서 지수감쇠 시정수 τ를 구해, 리듬 카드 심박 시계열 칸에 중립적인 회복 관찰 한 줄을 띄운다.

**Architecture:** `x = (hr60 − hr120) / (endHR − hr60)`에서 종료심박이 소거되므로 강도 보정 회귀 없이 러닝 간 비교가 선다. 엔진(`MRRecovery`)이 τ·백분위·문구까지 만들고, 뷰는 문자열만 받아 그린다. 판정은 개인 과거 τ 분포의 사분위로만 하고 좋다/나쁘다를 말하지 않는다.

**Tech Stack:** Swift 6 · SwiftUI · Swift Testing (`@Test`/`#expect`) · HealthKit · Xcode 26.3

**스펙:** `docs/superpowers/specs/2026-09-18-hr-recovery-decay-design.md`

---

## 파일 구조

| 파일 | 책임 | 작업 |
|---|---|---|
| `MIMORunning/Engine/MRRecovery.swift` | `MRRecoveryDecay` · `decay(endHR:hr60:hr120:)` · `tauPercentile` · `shapeCaption` · `MRRecoveryShape` | 수정 |
| `MIMORunning/Health/HealthKitManager.swift` | `RecoveryHistoryPoint.hr120`·`.id` · 캐시 v3 · 진행 중 재구축 공유 · 가용률 로그 | 수정 |
| `MIMORunning/Views/ActivityDetailView.swift` | `recoveryShape` 상태 조립 · `RunInsightSection`에 전달 | 수정 |
| `MIMORunning/Views/RunInsightCardView.swift` | `RunInsightSection`에 `recoveryShape` 통과 | 수정 |
| `MIMORunning/Views/RunInsightTabCard.swift` | `RunInsightTabCard`·`RhythmInsightCard`·`InsightExportSheet`에 `recoveryShape` · 캡션 둘째 줄 · `topCaptionH` | 수정 |
| `MIMORunningTests/MRRecoveryTests.swift` | τ·가드·백분위·문구 테스트 | 수정 |

**검증 명령 — 에이전트는 이것만 쓴다.** 시뮬레이터를 부팅하지 않고 앱 타깃과 테스트 타깃을 모두 컴파일한다(약 70초):

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -10
```

기대 출력: `** TEST BUILD SUCCEEDED **`

> **`xcodebuild test`를 돌리지 않는다.** 사용자 지시다 — Xcode 환경에서 시뮬레이터가 "Busy" 거부·서명 불일치로 옛 코드를 실행하는 문제가 반복됐다. 테스트는 계획대로 **작성**하되 **실행은 사용자가 실기기·Xcode에서** 한다. 화면 확인도 마찬가지다. 에이전트는 `** TEST BUILD SUCCEEDED **`까지만 책임진다.
>
> 그래서 이 계획의 TDD 단계는 "테스트를 돌려 실패를 본다"가 아니라 **"테스트를 먼저 쓰고, 컴파일이 기대한 대로 깨지는 것을 본다"**로 읽는다. 단언(assertion) 자체의 참/거짓은 사용자가 나중에 확인한다.

`.claude/worktrees/` 아래는 건드리지 않는다.

**참고 타입(기존)**
- `MRRecoveryPoint(offset:bpm:)` · `MRRecoveryResult(endHR:hr60:hr120:)` · `.hrr1` · `.hrr2` — `Engine/MRRecovery.swift`
- `MRRecovery.endHR(series:duration:)` · `.hr(at:post:)` · `.isEligible(endHR:maxHR:)` · `.compute(endHR:post:)`
- `HealthKitManager.RecoveryHistoryPoint(date:endHR:hrr1:tempC:)` · `.fetchRecoveryHistory(from:)` · `.fetchPostWorkoutHR(for:)` — `Health/HealthKitManager.swift:2556`
- `AppLanguage.shared.isEnglish` · `L.s(ko, en)`
- Swift Testing: `@Suite("이름", .korean)` · `@Test func x()` · `#expect(...)`

---

### Task 1: τ 닫힌 해와 가드

**Files:**
- Modify: `MIMORunning/Engine/MRRecovery.swift`
- Test: `MIMORunningTests/MRRecoveryTests.swift`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`MIMORunningTests/MRRecoveryTests.swift`의 `struct MRRecoveryTests { ... }` 안, 마지막 `@Test` 뒤에 추가:

```swift
    // MARK: 회복 곡선 모양 (τ)

    /// HR(t) = HR∞ + (endHR − HR∞)·e^(−t/τ) 로 만든 값에서 τ와 HR∞가 되돌아오는지
    @Test func decayRecoversTauAndAsymptote() {
        let endHR = 170.0, asym = 110.0, tau = 60.0
        let hr60  = asym + (endHR - asym) * exp(-60 / tau)
        let hr120 = asym + (endHR - asym) * exp(-120 / tau)
        let d = MRRecovery.decay(endHR: endHR, hr60: hr60, hr120: hr120)
        #expect(d != nil)
        #expect(abs((d?.tau ?? 0) - tau) < 2)
        #expect(abs((d?.asymptote ?? 0) - asym) < 3)
        // x = 2분째 낙폭 / 1분째 낙폭 = e^(−60/τ)
        #expect(abs((d?.ratio ?? 0) - exp(-1)) < 0.02)
    }

    /// 종료심박이 달라도 같은 곡선 모양이면 τ가 같다 — 강도 교란이 x에서 소거되는지
    @Test func decayIsIndependentOfEndHR() {
        let tau = 70.0
        func make(_ endHR: Double, _ asym: Double) -> Double? {
            let hr60  = asym + (endHR - asym) * exp(-60 / tau)
            let hr120 = asym + (endHR - asym) * exp(-120 / tau)
            return MRRecovery.decay(endHR: endHR, hr60: hr60, hr120: hr120)?.tau
        }
        let a = make(185, 115), b = make(150, 100)
        #expect(a != nil && b != nil)
        #expect(abs((a ?? 0) - (b ?? 1)) < 1)
    }

    @Test func decayGuardsRejectBadShapes() {
        // 1분 낙폭 7bpm → 거부, 8bpm → 통과
        #expect(MRRecovery.decay(endHR: 150, hr60: 143, hr120: 140) == nil)
        #expect(MRRecovery.decay(endHR: 150, hr60: 142, hr120: 139) != nil)
        // 2분째에 심박이 되오름 → 거부
        #expect(MRRecovery.decay(endHR: 170, hr60: 130, hr120: 134) == nil)
        // 2분 낙폭 0 → 거부
        #expect(MRRecovery.decay(endHR: 170, hr60: 130, hr120: 130) == nil)
        // x ≥ 1 (2분째가 더 크게 떨어짐) → 거부
        #expect(MRRecovery.decay(endHR: 170, hr60: 150, hr120: 125) == nil)
        // τ < 20초 (거의 즉시 바닥) → 거부. x = e^(−60/20) = 0.0498 보다 작은 x
        #expect(MRRecovery.decay(endHR: 190, hr60: 120, hr120: 117) == nil)
        // τ > 300초 → 거부. x = e^(−60/300) = 0.8187 보다 큰 x
        #expect(MRRecovery.decay(endHR: 170, hr60: 140, hr120: 114) == nil)
    }
```

파일 맨 위 `import Foundation`이 이미 있으므로 `exp`는 그대로 쓸 수 있다.

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -10
```

Expected: 컴파일 에러 `type 'MRRecovery' has no member 'decay'`

- [ ] **Step 3: 최소 구현**

`MIMORunning/Engine/MRRecovery.swift`에서 `struct MRRecoveryResult` **바로 앞**에 타입을 추가한다:

```swift
/// 회복 곡선의 모양. HR(t) = HR∞ + (HRend − HR∞)·e^(−t/τ) 의 1차 지수감쇠 파라미터.
///   Pierpont & Voth 2004 (Am J Cardiol 94(1):64–68).
/// ⚠ `ratio`는 두 낙폭의 비라 종료심박이 소거된다 — HRR1과 달리 강도 보정 회귀가 필요 없다.
/// ⚠ `asymptote`는 2분 외삽이라 불안정하다. 표시하지 않고 디버그로만 쓴다.
struct MRRecoveryDecay: Sendable {
    let ratio: Double      // x = (hr60 − hr120) / (endHR − hr60)
    let tau: Double        // 초
    let asymptote: Double  // HR∞ (bpm)
}
```

`enum MRRecovery` 안, `minObs` 상수 아래에 상수를 더한다:

```swift
    // MARK: 회복 곡선 모양 (τ) — 전부 임의값. 수식이 발산하거나 감쇠가 아닌 경우를 거른다.

    static let minFirstMinuteDrop = 8.0       // 분모가 작으면 x가 발산한다
    static let tauRange: ClosedRange<Double> = 20...300
    // τ 상한 300초 = x ≤ 0.819. 200초(x ≤ 0.741)로 잡으면 "2분 뒤에도 계속 내려오는 중"인
    // 러닝을 판정 전에 가드가 먼저 버린다. 문헌상 최대운동 후 τ는 대체로 30–120초.
```

`enum MRRecovery` 안, `compute` 바로 뒤에 함수를 더한다:

```swift
    /// 세 값으로 τ를 닫힌 해로 구한다. 가드에 걸리면 nil — 카드는 침묵한다.
    static func decay(endHR: Double, hr60: Double, hr120: Double) -> MRRecoveryDecay? {
        let d1 = endHR - hr60      // 1분째 낙폭
        let d2 = hr60 - hr120      // 2분째 낙폭
        guard d1 >= minFirstMinuteDrop, d2 > 0 else { return nil }
        let x = d2 / d1
        guard x > 0, x < 1 else { return nil }   // x ≥ 1은 감쇠가 아니다 (로그 정의역 보호)
        let tau = -60.0 / log(x)
        guard tauRange.contains(tau) else { return nil }
        return MRRecoveryDecay(ratio: x, tau: tau, asymptote: endHR - d1 / (1 - x))
    }
```

- [ ] **Step 4: 통과를 확인한다**

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -10
```

Expected: `MRRecoveryTests` 전체 PASS (기존 테스트 포함)

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Engine/MRRecovery.swift MIMORunningTests/MRRecoveryTests.swift
git commit -m "회복 곡선 시정수 τ — 두 낙폭의 비에서 종료심박이 소거된다

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `MRRecoveryResult`가 decay를 들고 다니게

**Files:**
- Modify: `MIMORunning/Engine/MRRecovery.swift`
- Test: `MIMORunningTests/MRRecoveryTests.swift`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

Task 1에서 추가한 블록 끝에 이어 붙인다:

```swift
    @Test func computeAttachesDecayWhenTwoMinuteSampleExists() {
        // τ=60, HR∞=110, endHR=170 → hr60 132, hr120 118
        let p = post([(58, 132), (62, 132), (118, 118), (122, 118)])
        let r = MRRecovery.compute(endHR: 170, post: p)
        #expect(r?.hrr1 == 38)
        #expect(r?.hrr2 == 52)
        #expect(r?.decay != nil)
        #expect(abs((r?.decay?.tau ?? 0) - 60) < 3)
    }

    @Test func computeHasNoDecayWithoutTwoMinuteSample() {
        let r = MRRecovery.compute(endHR: 170, post: post([(58, 132), (62, 132)]))
        #expect(r?.hrr1 == 38)      // 기존 동작 불변
        #expect(r?.hrr2 == nil)
        #expect(r?.decay == nil)
    }
```

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -10
```

Expected: 컴파일 에러 `value of type 'MRRecoveryResult' has no member 'decay'`

- [ ] **Step 3: 최소 구현**

`MRRecoveryResult`를 계산 프로퍼티로 바꾼다(저장 프로퍼티를 늘리지 않아 기존 생성자 호출부가 그대로 컴파일된다):

```swift
struct MRRecoveryResult: Sendable {
    let endHR: Double          // 종료 직전 30초 평균
    let hr60: Double
    let hr120: Double?
    var hrr1: Double { endHR - hr60 }
    var hrr2: Double? { hr120.map { endHR - $0 } }
    /// 회복 곡선 모양. 120초 샘플이 있고 가드를 통과할 때만 생긴다.
    var decay: MRRecoveryDecay? {
        hr120.flatMap { MRRecovery.decay(endHR: endHR, hr60: hr60, hr120: $0) }
    }
}
```

`compute`는 그대로 둔다 — 이미 `hr120`을 채우고 있다.

- [ ] **Step 4: 통과를 확인한다**

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -10
```

Expected: 전체 PASS

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Engine/MRRecovery.swift MIMORunningTests/MRRecoveryTests.swift
git commit -m "MRRecoveryResult가 decay를 계산 프로퍼티로 제공

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: 개인 τ 분포 사분위와 문구

**Files:**
- Modify: `MIMORunning/Engine/MRRecovery.swift`
- Test: `MIMORunningTests/MRRecoveryTests.swift`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

Task 2 블록 끝에 이어 붙인다:

```swift
    @Test func tauPercentileNeedsEightSamples() {
        let seven = [40.0, 45, 50, 55, 60, 65, 70]
        #expect(MRRecovery.tauPercentile(52, history: seven) == nil)
        #expect(MRRecovery.tauPercentile(52, history: seven + [75]) != nil)
    }

    @Test func tauPercentileCountsSamplesBelow() {
        let h = [40.0, 45, 50, 55, 60, 65, 70, 75]   // 8개
        #expect(MRRecovery.tauPercentile(39, history: h) == 0.0)     // 전부 위
        #expect(MRRecovery.tauPercentile(76, history: h) == 1.0)     // 전부 아래
        #expect(MRRecovery.tauPercentile(57, history: h) == 0.5)     // 4/8
    }

    @Test func shapeCaptionSaysFasterSameSlower() {
        func shape(_ tau: Double, _ history: [Double]) -> MRRecoveryShape {
            MRRecoveryShape(hrr1: 38, hrr2: 52,
                            decay: MRRecoveryDecay(ratio: exp(-60 / tau), tau: tau, asymptote: 110),
                            percentile: MRRecovery.tauPercentile(tau, history: history))
        }
        let h = [40.0, 45, 50, 55, 60, 65, 70, 75]
        #expect(MRRecovery.shapeCaption(shape(39, h)) == "평소보다 빠르게 안정됐어요")
        #expect(MRRecovery.shapeCaption(shape(57, h)) == "평소대로 내려왔어요")
        #expect(MRRecovery.shapeCaption(shape(76, h)) == "2분 뒤에도 계속 내려오는 중이었어요")
    }

    @Test func shapeCaptionFallsBackToRawNumbers() {
        // 과거 표본 7개 → 비교하지 않고 사실만
        let s = MRRecoveryShape(hrr1: 38, hrr2: 52,
                                decay: MRRecoveryDecay(ratio: 0.37, tau: 60, asymptote: 110),
                                percentile: nil)
        #expect(MRRecovery.shapeCaption(s) == "1분 −38 · 2분 −52bpm")
    }
```

> 문구 비교는 한국어 기준이다. `.korean` 스위트 트레이트가 `AppLanguage`를 한국어로 고정한다.

- [ ] **Step 2: 실패를 확인한다**

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -10
```

Expected: 컴파일 에러 `cannot find 'MRRecoveryShape' in scope`

- [ ] **Step 3: 최소 구현**

`MIMORunning/Engine/MRRecovery.swift`에서 `MRRecoveryDecay` 정의 **바로 뒤**에 추가:

```swift
/// 리듬 카드 한 줄에 필요한 값 묶음. 뷰는 이걸 받아 `MRRecovery.shapeCaption`이 만든 문자열만 그린다.
struct MRRecoveryShape: Sendable {
    let hrr1: Double
    let hrr2: Double
    let decay: MRRecoveryDecay
    /// 과거 τ 분포 안에서 이 러닝의 위치(0...1). 표본 8개 미만이면 nil → 비교하지 않는다.
    let percentile: Double?
}
```

`enum MRRecovery` 안, `decay(endHR:hr60:hr120:)` 뒤에 추가:

```swift
    static let minTauSamples = 8   // 임의로 정함 — 사분위가 의미를 갖는 최소선

    /// 과거 τ 중 오늘보다 작은(= 더 빨랐던) 것의 비율. 표본이 모자라면 nil.
    /// ⚠ `history`에 오늘 러닝을 넣지 않는다 — 자기를 포함하면 표본이 작을수록 가운데로 끌린다.
    static func tauPercentile(_ tau: Double, history: [Double]) -> Double? {
        guard history.count >= minTauSamples else { return nil }
        return Double(history.filter { $0 < tau }.count) / Double(history.count)
    }

    /// 리듬 카드 캡션 둘째 줄.
    /// ⚠ 좋다/나쁘다를 말하지 않는다 — Le Meur 2015(PLOS One 10:e0139754)에서 기능적 과부하 시
    ///   HRR이 오히려 빨라졌다. 빠름 = 좋음으로 읽히면 안 된다.
    /// ⚠ τ의 공인 절단점은 없다. 개인 분포 사분위로만 말한다(§2-3: 기준은 외부 공인 표준).
    static func shapeCaption(_ shape: MRRecoveryShape) -> String {
        let L = AppLanguage.shared
        guard let p = shape.percentile else {
            let d1 = Int(shape.hrr1.rounded()), d2 = Int(shape.hrr2.rounded())
            return L.isEnglish ? "−\(d1) at 1 min · −\(d2) at 2 min" : "1분 −\(d1) · 2분 −\(d2)bpm"
        }
        if p < 0.25 { return L.s("평소보다 빠르게 안정됐어요", "Settled faster than usual") }
        if p >= 0.75 { return L.s("2분 뒤에도 계속 내려오는 중이었어요", "Still coming down after 2 min") }
        return L.s("평소대로 내려왔어요", "Came down as usual")
    }
```

- [ ] **Step 4: 통과를 확인한다**

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -10
```

Expected: 전체 PASS

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Engine/MRRecovery.swift MIMORunningTests/MRRecoveryTests.swift
git commit -m "개인 τ 분포 사분위로 회복 한 줄 — 좋다/나쁘다는 말하지 않는다

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: 과거 τ 분포를 캐시에서 만든다

**Files:**
- Modify: `MIMORunning/Health/HealthKitManager.swift:2556-2605`

`RecoveryHistoryPoint`는 `endHR`과 `hrr1`을 이미 갖고 있으므로 `hr60 = endHR − hrr1`이 나온다. **`hr120` 하나만** 더하면 τ가 나온다 — 필드를 더 늘리지 않는다.

- [ ] **Step 1: 저장 필드와 캐시 버전을 올린다**

`MIMORunning/Health/HealthKitManager.swift:2556` 부근:

```swift
    struct RecoveryHistoryPoint: Codable {
        let date: Date
        let endHR: Double
        let hrr1: Double
        var tempC: Double? = nil   // HKMetadataKeyWeatherTemperature — 회귀의 기온 항
        var hr120: Double? = nil   // 종료 120초 후 심박 — τ 분포용. hr60 = endHR − hrr1 로 나온다.
    }
```

`recoveryHistoryURL`의 파일명을 바꾼다 (파일명 교체가 곧 캐시 무효화다):

```swift
            .appendingPathComponent("mimo_hrr_history_v3.json")   // v3: hr120(τ) 필드
```

`fetchRecoveryHistory` 안 `RecoveryHistoryPoint(...)` 생성부에 `hr120`을 채운다:

```swift
                    return RecoveryHistoryPoint(date: w.startDate, endHR: endHR, hrr1: r.hrr1,
                                                tempC: temp, hr120: r.hr120)
```

- [ ] **Step 2: τ 목록 헬퍼를 더한다**

`fetchRecoveryHistory`가 끝나는 지점(`return points` 다음 줄) 뒤에 메서드를 추가한다:

```swift
    /// 과거 러닝의 회복 곡선 시정수 τ 목록. `excluding` 러닝은 뺀다 — 자기를 포함한 분포와
    /// 비교하면 표본이 작을수록 가운데로 끌린다.
    func recoveryTauHistory(from start: Date, excluding activityDate: Date?) async -> [Double] {
        let pts = await fetchRecoveryHistory(from: start)
        return pts.compactMap { p -> Double? in
            if let d = activityDate, abs(p.date.timeIntervalSince(d)) < 60 { return nil }
            guard let h120 = p.hr120 else { return nil }
            return MRRecovery.decay(endHR: p.endHR, hr60: p.endHR - p.hrr1, hr120: h120)?.tau
        }
    }
```

- [ ] **Step 3: 가용률 로그를 더한다**

같은 파일 `fetchRecoveryHistory` 안, 기존 `#if DEBUG print("[회복] 12개월 러닝 ...")` 줄 **바로 아래**에 한 줄 추가한다. 스펙의 "HR120까지 잡히는 러닝 비율을 세어본다"가 이 로그다:

```swift
        print("[회복] 그중 2분 샘플 \(points.filter { $0.hr120 != nil }.count)건 · τ 성립 \(points.compactMap { p in p.hr120.flatMap { MRRecovery.decay(endHR: p.endHR, hr60: p.endHR - p.hrr1, hr120: $0) } }.count)건")
```

- [ ] **Step 4: 빌드를 확인한다**

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -10
```

Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Health/HealthKitManager.swift
git commit -m "회복 히스토리에 hr120 저장 · τ 목록 헬퍼 · 캐시 v3

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: 상세 화면에서 `MRRecoveryShape`를 조립한다

**Files:**
- Modify: `MIMORunning/Views/ActivityDetailView.swift:77-141`

- [ ] **Step 1: 상태를 더한다**

`@State private var recoveryResult: MRRecoveryResult? = nil` (78행) 바로 아래:

```swift
    /// 리듬 카드 회복 한 줄 입력 — τ와 과거 분포 내 위치. 자격 미달·샘플 부족이면 nil로 남아 카드가 침묵한다.
    @State private var recoveryShape: MRRecoveryShape? = nil
```

> **성능 주의:** `recoveryTauHistory`는 `fetchRecoveryHistory`를 거치고, 캐시가 비어 있으면 12개월 워크아웃마다 HealthKit 조회를 한다(수 초). `loadRecovery()`는 이미 `.task`에서 `await`로 돌므로 UI를 막지는 않고, 캡션만 늦게 뜬다. 디스크 캐시(`mimo_hrr_history_v3.json`)가 있으면 새 러닝이 생길 때만 다시 만든다. 이 동작을 바꾸지 말 것 — 성장 탭이 같은 캐시를 공유한다.

- [ ] **Step 2: `loadRecovery`가 shape까지 만들게 한다**

`loadRecovery()` (130행 부근)의 `recoveryResult = MRRecovery.compute(endHR: endHR, post: post)` 다음, `#if DEBUG` 앞에 끼워 넣는다:

```swift
        if let r = recoveryResult, let d = r.decay {
            let start = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
            let taus = await manager.recoveryTauHistory(from: start, excluding: activity.id)
            recoveryShape = MRRecoveryShape(r, percentile: MRRecovery.tauPercentile(d.tau, history: taus))
        }
```

`MRRecoveryShape(_:percentile:)`는 `MRRecoveryResult`에서만 만드는 실패가능 init이다 — `decay`와 `hrr2`가 서로 어긋난 상태를 타입이 막는다. 여기서는 `r.decay`가 이미 있으므로 nil이 돌아오지 않는다.

- [ ] **Step 3: 로그를 늘린다**

같은 함수의 기존 `#if DEBUG` 블록 안, `print(String(format: "[회복] 종료심박 ...` 다음 줄에:

```swift
        if let d = recoveryShape?.decay {
            print(String(format: "[회복:모양] τ %.0f초 · x %.2f · HR∞ %.0f · 분위 %@",
                         d.tau, d.ratio, d.asymptote,
                         recoveryShape?.percentile.map { String(format: "%.2f", $0) } ?? "표본부족"))
        }
```

- [ ] **Step 4: `RunInsightSection`에 넘긴다**

`ActivityDetailView.swift:303` 부근, `planPhase: matchedPlanWeek()?.phase` 다음 줄에 인자를 더한다:

```swift
                            planPhase: matchedPlanWeek()?.phase,
                            recoveryShape: recoveryShape
```

(기존 `planPhase: matchedPlanWeek()?.phase` 줄 끝에 쉼표를 붙이고 새 줄을 넣는다.)

- [ ] **Step 5: 빌드 실패를 확인한다**

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -10
```

Expected: `error: extra argument 'recoveryShape' in call` — Task 6에서 받는 쪽을 만든다.

---

### Task 6: 카드까지 전달하고 캡션 둘째 줄을 그린다

**Files:**
- Modify: `MIMORunning/Views/RunInsightCardView.swift:100-120`
- Modify: `MIMORunning/Views/RunInsightTabCard.swift` (`RunInsightTabCard` 프로퍼티 · `cardContent` · `RhythmInsightCard` 프로퍼티 · `rhythmRow` 캡션 · `topCaptionH` · `InsightExportSheet`)

- [ ] **Step 1: `RunInsightSection`에 프로퍼티와 통과를 더한다**

`MIMORunning/Views/RunInsightCardView.swift`의 `struct RunInsightSection` 프로퍼티 목록 끝(`var isClassifying: Bool = false` 뒤)에:

```swift
    /// 회복 곡선 한 줄 입력 — 리듬 카드로 그대로 흘려보낸다.
    var recoveryShape: MRRecoveryShape? = nil
```

같은 파일 `RunInsightCardView.swift:172`의 `RunInsightTabCard(...)` 마지막 인자를 바꾼다:

```swift
                planPhase: planPhase,
                recoveryShape: recoveryShape
            )
```

- [ ] **Step 2: `RunInsightTabCard`에 프로퍼티와 통과를 더한다**

`MIMORunning/Views/RunInsightTabCard.swift:807` 부근, `var planPhase: String? = nil` 뒤:

```swift
    /// 회복 곡선 한 줄 입력 — 리듬 카드와 내보내기 시트가 같은 값을 본다(§5.8).
    var recoveryShape: MRRecoveryShape? = nil
```

`cardContent`의 `case .rhythm:` 안 `RhythmInsightCard(...)` 인자 끝(`planPhase: planPhase` 뒤)에:

```swift
                planPhase: planPhase,
                recoveryShape: recoveryShape
```

`showExport` 시트의 `InsightExportSheet(...)` 인자 끝(`planPhase: planPhase` 뒤)에도 똑같이:

```swift
                planPhase: planPhase,
                recoveryShape: recoveryShape
```

- [ ] **Step 3: `InsightExportSheet`가 받아 넘기게 한다**

`RunInsightTabCard.swift:5558` 부근 `var planPhase: String? = nil` 뒤:

```swift
    var recoveryShape: MRRecoveryShape? = nil
```

같은 구조체 안 `case .rhythm:`의 `RhythmInsightCard(...)` 인자 끝에도 `recoveryShape: recoveryShape`를 더한다. 미리보기 = 출력이므로 두 곳이 같은 값을 봐야 한다(§5.8).

- [ ] **Step 4: `RhythmInsightCard`가 받아 그린다**

`RunInsightTabCard.swift:1394` 부근, `var summaryAllowsExpansion: Bool = true` **앞**에:

```swift
    /// 회복 곡선 한 줄. nil이면 캡션 둘째 줄을 그리지 않는다 — "회복 데이터 없음" 문구는 쓰지 않는다.
    var recoveryShape: MRRecoveryShape? = nil
```

`rhythmRow`의 심박 시계열 칸 캡션(1685행 부근)을 `VStack`으로 바꾼다. **차트는 건드리지 않는다** — 종료 후 3분은 60분 러닝 x축의 5%라 칸 안에서 보이지 않고 러닝 본체만 눌린다:

```swift
                } caption: {
                    VStack(spacing: 1) {
                        if hasHR, let v = hrVerdictText {
                            Text(v.text)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(v.color)
                        }
                        // 회복 곡선 한 줄 — 중립 관찰이라 판정색을 쓰지 않는다(케이던스 보조 라벨과 같은 색).
                        if let s = recoveryShape {
                            Text(MRRecovery.shapeCaption(s))
                                .font(.system(size: 8.5))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
```

- [ ] **Step 5: 캡션 높이를 회복 줄이 있을 때만 2줄로**

`RunInsightTabCard.swift:1601`:

```swift
    /// 회복 곡선 한 줄이 있을 때만 2줄 높이를 잡는다 — 없는 러닝(대부분)까지 여백을 떠안지 않도록.
    /// 네 칸이 한 렌더에서 같은 값을 보므로 정렬은 그대로다.
    private var topCaptionH: CGFloat {
        guard recoveryShape != nil else { return compact ? 24 : 28 }
        return compact ? 36 : 38
    }
```

높이를 무조건 올리면 안 된다 — `recoveryShape`는 대부분의 러닝에서 nil이라(80% 게이트·120초 샘플 없음·감쇠 가드), 얻은 것 없는 칸까지 여백을 떠안고 구분선이 내려간다.

일반 모드 값이 42가 아니라 **38**인 이유: 줄바꿈된 2줄짜리 `hrVerdictText`(`lineLimit` 없음) + 회복 줄이 약 32.8pt라 38에 여유 있게 들어가고, 38은 `bottomCaptionH`의 일반 모드 값과 같아 2×2의 위아래 행 높이가 맞는다. 3줄 판정은 38에서 잘리지만 기존 28에서도 잘렸으므로 후퇴가 아니다.

- [ ] **Step 6: 빌드를 확인한다**

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -10
```

Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 7: 사용자 확인 항목으로 남긴다**

`topCaptionH` 변경이 다른 레이아웃을 깨지 않는지는 컴파일로 알 수 없다. Task 7의 실기기 확인 목록에 넣는다.

- [ ] **Step 8: 커밋**

```bash
git add MIMORunning/Views/ActivityDetailView.swift MIMORunning/Views/RunInsightCardView.swift MIMORunning/Views/RunInsightTabCard.swift
git commit -m "리듬 카드 심박 칸에 회복 곡선 한 줄 — 내보내기도 같은 컴포넌트

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: 실기기 확인 요청

**Files:** 없음 (검증만)

- [ ] **Step 1: 사용자에게 실기기 확인을 요청한다**

에이전트는 시뮬레이터로 화면을 보지 않는다. 다음을 사용자에게 확인 요청한다:

0. Xcode에서 `MRRecoveryTests` 스위트 실행 — 이 계획이 작성한 단위 테스트는 에이전트가 돌리지 않았다
1. 워치로 기록한 고강도 러닝 상세 → 리듬 카드 우상단 심박 칸에 둘째 줄이 뜨는지
2. 2×2 그리드 네 칸의 세로 정렬이 유지되는지(캡션 높이 변경 영향)
3. "오늘의 인사이트 내보내기"에서 같은 줄이 같은 크기로 나오는지 (§5.8)
4. 이지런(종료심박 80% 미달)에서는 줄이 **아예 없는지** — "데이터 없음" 문구가 뜨면 안 된다
5. Xcode 콘솔의 `[회복]` / `[회복:모양]` 로그 — 12개월 중 τ가 성립한 건수가 8건 이상인지

- [ ] **Step 2: τ 성립 건수가 8건 미만이면 보고한다**

그 경우 캡션은 계속 폴백("1분 −38 · 2분 −52bpm")만 나온다. 구현을 더 밀지 말고, 게이트(종료심박 80%)를 다시 논의할지 사용자에게 묻는다. 스펙 §결정에 "게이트는 건드리지 않는다"고 못박아 두었다.

---

## 하지 않는 것 (스펙 §6)

- τ 장기 추세·잔차 회귀 (HRR1이 이미 담당)
- 다음 고강도까지의 간격 제안
- HR∞ 표시 (계산만 하고 디버그 로그로만)
- 공유 카드 전용 레이아웃 — 리듬 카드 컴포넌트를 따라갈 뿐
- 임상 절단점(Cole 1999 12bpm · Shetler 2001 22bpm) 인용
- 심박 시계열 차트에 종료 후 꼬리 추가
