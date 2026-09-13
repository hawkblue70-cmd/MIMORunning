# 기온 보정 심박 단일화 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 관측 심박을 15°C 기준으로 환산하는 함수 하나(`MRHeatHRModel.toRef`)를 만들고, 이 러닝의 심박을 과거와 비교하거나 판정하는 모든 자리가 그 하나를 쓰게 한다. 원본 심박·존 시간은 그대로 두고 **비교·판정에만** 보정값을 쓴다.

**Architecture:** `MRHeatHRModel`(Engine/)은 사용자 본인 기록으로 "15°C 초과 1°C당 bpm"을 학습하고(`mrFitHeatHRModel`, `mrFitHRPaceModel`과 같은 회귀에서 기온 계수만 꺼냄), 학습이 안 되면 문헌 계수(0.8 bpm/°C)를 `isFallback=true`로 쓴다. `MREngineStore.refreshCore()`에서 `heat`(페이스 더위 모델) 옆에 적합해 `heatHR`로 노출한다. 소비자: `RunInsightEngine`(효율·드리프트·이지런 강도), 퍼포먼스 카드 산점도·심박 효율 캡션, 리듬 카드 존 캡션·폼 해석·총평 심박 줄, `InsightEngine`(안전 메모·트레이드오프·회복, 디스크 캐시 v22).

**Tech Stack:** Swift · 기존 `MRLinAlg` OLS · XCTest(엔진) · Swift Testing(문장, `.serialized`).

**확정된 결정 (2026-09-13)**
1. 심박 효율 산점도의 점 위치를 보정 심박으로 그린다(계절 파도 제거). 범례에 "15°C 기준" 표기.
2. 존 도넛 비율·존 시간은 원본 그대로. 캡션에만 "더위 +N bpm"을 덧붙인다.
3. 학습이 안 되면 문헌 폴백을 쓰되 문장은 "참고" 톤("일반적인 더위 영향을 감안하면").

**기준선 원칙(기존 코드에서 확립된 것, 반드시 지킬 것)**
- 회귀 외삽 금지(`MRHRPaceModel.swift:3-7`). 기온 계수는 학습 구간 안에서만 쓴다.
- `ok` 판정에 `delta()`를 쓰지 않는다 — `guard ok`가 검사를 무력화한다(`MRHeatModel.swift:16-27`). `rawDelta`를 따로 둔다.
- 기온이 nil이면 항등(원래 값). 모델이 없어도 값을 왜곡하지 않는다(`MRRobustnessTests.testNoTemperature`).
- 기온 폭이 좁으면 학습 거부(`mrFitDrift`의 `tempSpanC >= 15` 규칙).
- 레이아웃·색·축·숫자 형식은 이 문서에 적힌 것 외에 바꾸지 않는다.

---

## 파일 맵

| 파일 | 역할 | 작업 |
|---|---|---|
| `MIMORunning/Engine/MRHeatHRModel.swift` | 모델·적합·`toRef`·`refHR(of: Activity)` | 생성 |
| `MIMORunning/Engine/MREngineStore.swift` | `heatHR` 적합·노출 | 수정 |
| `MIMORunning/Insight/RunInsightEngine.swift` | `insights(heatHR:)` · 효율/드리프트/이지런 강도 보정 | 수정 |
| `MIMORunning/Views/ActivityDetailView.swift` | `heatHR` 전달(엔진·섹션·InsightEngine) | 수정 |
| `MIMORunning/Views/RunInsightCardView.swift` | `heatHRModel` 전달 | 수정 |
| `MIMORunning/Views/RunInsightTabCard.swift` | 세 카드·내보내기에 `heatHRModel` 전달, 산점도·hrDelta·존 캡션·폼 해석·총평 입력 | 수정 |
| `MIMORunning/Insight/RunSummary.swift` | `heatDeltaBpm` 입력, 심박 줄 접미 | 수정 |
| `MIMORunning/Insight/InsightEngine.swift` | `compute(heatHR:)`, 안전 메모·트레이드오프·회복 보정 | 수정 |
| `MIMORunning/Insight/InsightCache.swift` | `cacheVersion` 21 → 22 | 수정 |
| `MIMORunningTests/MRHeatHRModelTests.swift` | | 생성 |
| `MIMORunningTests/HeatAdjustedHRInsightTests.swift` | 효율·드리프트 문장 | 생성 |
| `MIMORunningTests/RunSummaryTests.swift` | 심박 줄 접미 | 수정 |

**테스트 실행 명령** (스위트 이름만 바꾼다):

```bash
xcodebuild test -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MIMORunningTests/<SuiteTypeName> 2>&1 | grep -E 'Test (Suite|Case)|passed|failed|error:' | tail -30
```

빌드만:

```bash
xcodebuild build -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E 'error:|BUILD' | tail -10
```

새 파일은 폴더에 넣으면 타깃에 자동 포함된다. 커밋 트레일러: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. `.claude/worktrees/`는 건드리지 않는다.

**참고 타입(기존)**
- `MRWorkout(start:durationMin:distanceKm:hrAvg:hrMax:tempC:humidity:indoor:isInterval:)` — `Engine/MRTypes.swift:71` 근처. `hrAvg: Double?`, `tempC: Double?`.
- `MR_REF_TEMP = 15.0` — `Engine/MRHeatModel.swift:3`.
- `mrFitHRPaceModel(runs:asOf:)` — `Engine/MRHRPaceModel.swift:180-230`. OLS 호출·행 필터·`MRLinAlg.residualSD` 사용법은 이 함수를 그대로 따른다(행 필터: 365일 이내·`!indoor`·`hrAvg != nil`·`durationMin >= 20`·`km >= 2`·속도 100~400 m/min).
- `Activity.avgHeartRate: Int?`, `Activity.temperatureC: Double?`, `Activity.paceSecPerKm: Double?`.
- `RunInsight(category:tone:badge:message:highlights:)`, `InsightTone { good, neutral, caution }`.
- `AppLanguage.shared` · `L.s(ko, en)`.

---

### Task 1: `MRHeatHRModel` — 학습·폴백·환산

> **리뷰 반영(구현 완료 후 확정)**: 학습 조건은 기온 폭이 아니라 **더운 날 표본** — 20°C 이상 러닝 8회 이상 + 최고 기온 25°C 이상. 학습 최고 기온(`tempMaxC`) 밖은 외삽하지 않고 그 값으로 고정(폴백은 40°C까지). 설계 행렬에 시간 추세(`years`) 열 추가. 계수는 0~1.5만 채택(작은 양수 = 더위 적응, 그대로 씀), 음수·1.5 초과만 폴백. Task 2 주의: 비교 대상 과거 러닝의 기온 커버리지가 50% 미만이면 양쪽 다 보정하지 않고 "더위 영향일 수 있어요"로만 말한다. 커밋 50b1d42 + 리뷰 반영 커밋이 기준.

**Files:**
- Create: `MIMORunning/Engine/MRHeatHRModel.swift`
- Modify: `MIMORunning/Engine/MREngineStore.swift` (`heat` 옆)
- Test: `MIMORunningTests/MRHeatHRModelTests.swift`

- [ ] **Step 1: 실패하는 테스트**

```swift
import XCTest
@testable import MIMORunning

/// 관측 심박 → 15°C 환산. 기온이 없거나 모델이 못 쓰면 항등이어야 한다.
final class MRHeatHRModelTests: XCTestCase {

    /// 기온·심박이 함께 변하는 합성 러닝. hr = base + slope × max(0, temp−15) + 잡음(결정적).
    private func makeRuns(count: Int, temps: [Double], slope: Double, baseHR: Double = 140,
                          paceSecPerKm: Double = 360) -> [MRWorkout] {
        let cal = Calendar.current
        return (0..<count).map { i in
            let t = temps[i % temps.count]
            let noise = Double((i * 7) % 5) - 2.0          // −2…+2, 결정적
            let hr = baseHR + slope * max(0, t - MR_REF_TEMP) + noise
            let d = cal.date(byAdding: .day, value: -(i * 3 + 1), to: Date())!
            return MRWorkout(start: d, durationMin: 8 * paceSecPerKm / 60, distanceKm: 8,
                             hrAvg: hr, hrMax: hr + 25, tempC: t, humidity: nil,
                             indoor: false, isInterval: false)
        }
    }

    func testFitsSlopeFromOwnRuns() {
        let runs = makeRuns(count: 60, temps: [5, 10, 15, 20, 25, 30], slope: 0.9)
        let m = mrFitHeatHRModel(runs: runs, asOf: Date())
        XCTAssertTrue(m.ok)
        XCTAssertFalse(m.isFallback)
        XCTAssertEqual(m.bpmPerC, 0.9, accuracy: 0.15)
        XCTAssertEqual(m.toRef(150, tempC: 25), 150 - m.bpmPerC * 10, accuracy: 0.001)
        XCTAssertEqual(m.toRef(150, tempC: 10), 150, accuracy: 0.001, "15°C 아래는 보정하지 않는다")
    }

    func testNarrowTemperatureSpanFallsBackToLiterature() {
        let runs = makeRuns(count: 60, temps: [14, 15, 16, 17], slope: 0.9)
        let m = mrFitHeatHRModel(runs: runs, asOf: Date())
        XCTAssertTrue(m.ok)
        XCTAssertTrue(m.isFallback)
        XCTAssertEqual(m.bpmPerC, MRHeatHRModel.fallbackBpmPerC, accuracy: 0.001)
        XCTAssertFalse(m.rejectReason.isEmpty)
    }

    func testTooFewRunsFallsBack() {
        let runs = makeRuns(count: 10, temps: [5, 15, 25, 30], slope: 0.9)
        XCTAssertTrue(mrFitHeatHRModel(runs: runs, asOf: Date()).isFallback)
    }

    func testImplausibleSlopeFallsBack() {
        // 기온이 올라갈수록 심박이 내려가는(음수 기울기) 데이터 → 문헌 범위 밖 → 폴백
        let runs = makeRuns(count: 60, temps: [5, 10, 15, 20, 25, 30], slope: -1.0)
        let m = mrFitHeatHRModel(runs: runs, asOf: Date())
        XCTAssertTrue(m.isFallback)
    }

    func testNilTemperatureIsIdentity() {
        let m = MRHeatHRModel.fallback()
        XCTAssertEqual(m.toRef(150, tempC: nil), 150, accuracy: 0.001)
        XCTAssertEqual(m.delta(nil), 0, accuracy: 0.001)
    }

    func testUnusableModelIsIdentity() {
        let m = MRHeatHRModel()          // ok=false
        XCTAssertEqual(m.toRef(150, tempC: 30), 150, accuracy: 0.001)
        XCTAssertEqual(m.delta(30), 0, accuracy: 0.001)
    }

    func testExplainsNeedsAtLeastThreeBpm() {
        let m = MRHeatHRModel.fallback()  // 0.8 bpm/°C
        XCTAssertFalse(m.explains(tempC: 18))   // +2.4
        XCTAssertTrue(m.explains(tempC: 19))    // +3.2
        XCTAssertFalse(m.explains(tempC: nil))
    }

    func testRefHRForActivity() {
        let m = MRHeatHRModel.fallback()
        let a = Activity(id: UUID(), type: .running, date: Date(), duration: 3600, distance: 10_000,
                         calories: nil, avgHeartRate: 150, temperatureC: 25, humidityPercent: nil)
        XCTAssertEqual(m.refHR(of: a)!, 150 - 8, accuracy: 0.001)
        let noHR = Activity(id: UUID(), type: .running, date: Date(), duration: 3600, distance: 10_000,
                            calories: nil, avgHeartRate: nil, temperatureC: 25, humidityPercent: nil)
        XCTAssertNil(m.refHR(of: noHR))
    }
}
```

- [ ] **Step 2: 실패 확인** — `cannot find 'mrFitHeatHRModel' in scope`.

- [ ] **Step 3: 구현**

`MIMORunning/Engine/MRHeatHRModel.swift`:

```swift
import Foundation

/// 관측 심박 → 15°C 기준 심박.
///
/// 더운 날엔 같은 페이스라도 피부 혈류 때문에 심박이 오른다(Lafrenz 2008: 35°C에서 같은 강도에 심박 +11%).
/// 이 모델은 본인 기록에서 "15°C 초과 1°C당 bpm"을 학습하고, 심박을 과거와 **비교·판정할 때만** 빼 준다.
/// 원본 심박·존 시간은 건드리지 않는다.
///
/// - 기온이 nil이거나 모델을 쓸 수 없으면 항등.
/// - 15°C 아래는 보정하지 않는다(추위 계수는 미신뢰 — `RunFormCardView` 추위 분기와 같은 태도).
/// - 학습이 안 되면 문헌 계수로 폴백하되 `isFallback`으로 표시해 문장 톤을 "참고"로 낮춘다.
struct MRHeatHRModel: Sendable {
    var ok = false
    var isFallback = false
    var bpmPerC = 0.0          // 15°C 초과 1°C당 bpm
    var n = 0
    var tempSpanC = 0.0
    var residSD = 0.0
    var rejectReason = ""      // 학습 거부 이유(디버그·"참고" 근거)

    /// 문헌 폴백 계수. 35°C에서 +11%(≈150bpm 기준 +16bpm) → 20°C 폭 ÷ ≈ 0.8 bpm/°C.
    static let fallbackBpmPerC = 0.8
    static let minBpmPerC = 0.2
    static let maxBpmPerC = 1.5
    static let minRuns = 30
    static let minTempSpanC = 12.0
    /// 보정이 이만큼 이상일 때만 문장에서 "기온 감안"을 말한다
    static let explainThresholdBpm = 3.0

    static func fallback(reason: String = "") -> MRHeatHRModel {
        var m = MRHeatHRModel()
        m.ok = true
        m.isFallback = true
        m.bpmPerC = fallbackBpmPerC
        m.rejectReason = reason
        return m
    }

    // ok에 의존하지 않는 계산 — 타당성 검사용 (MRHeatModel과 같은 이유)
    func rawDelta(_ t: Double) -> Double { bpmPerC * max(0, t - MR_REF_TEMP) }

    /// 이 기온에서 예상되는 심박 상승분(bpm). 기온 없음·모델 불가 → 0.
    func delta(_ tempC: Double?) -> Double {
        guard ok, let t = tempC else { return 0 }
        return rawDelta(t)
    }

    /// 관측 심박 → 15°C 기준
    func toRef(_ hr: Double, tempC: Double?) -> Double { hr - delta(tempC) }

    /// 보정이 표시할 만큼 큰가
    func explains(tempC: Double?) -> Bool { delta(tempC) >= Self.explainThresholdBpm }

    /// 러닝 한 건의 15°C 기준 평균 심박. 심박이 없으면 nil.
    func refHR(of a: Activity) -> Double? {
        guard let hr = a.avgHeartRate else { return nil }
        return toRef(Double(hr), tempC: a.temperatureC)
    }
}

/// HR ~ 1 + speed + durationMin + max(0, temp−15) 에서 기온 계수만 꺼낸다.
/// `mrFitHRPaceModel`과 같은 행 필터를 쓰되 기온이 없는 행은 **제외**한다(15°C로 채우면 계수가 눌린다).
/// 학습 조건: 행 ≥ 30 · 기온 폭 ≥ 12°C · 0.2 ≤ 계수 ≤ 1.5. 아니면 문헌 폴백.
func mrFitHeatHRModel(runs: [MRWorkout], asOf: Date) -> MRHeatHRModel {
    let cal = Calendar.current
    let rows = runs.filter { w in
        guard let hr = w.hrAvg, let km = w.distanceKm, let t = w.tempC, !w.indoor else { return false }
        let days = cal.dateComponents([.day], from: w.start, to: asOf).day ?? -1
        guard days >= 0 && days <= 365 else { return false }
        guard w.durationMin >= 20, km >= 2.0, hr > 0 else { return false }
        let speed = km * 1000 / w.durationMin
        return speed > 100 && speed < 400 && t > -50 && t < 60
    }
    guard rows.count >= MRHeatHRModel.minRuns else {
        return .fallback(reason: "러닝 \(rows.count)회 < \(MRHeatHRModel.minRuns) — 기온 있는 야외 러닝 부족")
    }
    let temps = rows.map { $0.tempC! }
    let span = (temps.max() ?? 0) - (temps.min() ?? 0)
    guard span >= MRHeatHRModel.minTempSpanC else {
        return .fallback(reason: String(format: "기온 폭 %.0f°C < %.0f°C", span, MRHeatHRModel.minTempSpanC))
    }
    // OLS — mrFitHRPaceModel(MRHRPaceModel.swift:180-230)의 X/y 구성과 MRLinAlg 호출을 그대로 따른다.
    let X: [[Double]] = rows.map { w in
        let speed = w.distanceKm! * 1000 / w.durationMin
        return [1.0, speed, w.durationMin, max(0, w.tempC! - MR_REF_TEMP)]
    }
    let y: [Double] = rows.map { $0.hrAvg! }
    guard let c = MRLinAlg.ols(X: X, y: y) else {          // ← 실제 함수명은 mrFitHRPaceModel에서 확인해 맞춘다
        return .fallback(reason: "회귀 실패")
    }
    var m = MRHeatHRModel()
    m.n = rows.count
    m.tempSpanC = span
    m.bpmPerC = c[3]
    m.residSD = MRLinAlg.residualSD(X: X, y: y, coef: c, ddof: 4)
    let plausible = m.bpmPerC >= MRHeatHRModel.minBpmPerC && m.bpmPerC <= MRHeatHRModel.maxBpmPerC
    guard plausible else {
        return .fallback(reason: String(format: "계수 %+.2f bpm/°C — 문헌 범위(%.1f~%.1f) 밖", m.bpmPerC,
                                        MRHeatHRModel.minBpmPerC, MRHeatHRModel.maxBpmPerC))
    }
    m.ok = true
    return m
}
```
`MRLinAlg`의 OLS 함수명·시그니처는 `mrFitHRPaceModel`이 쓰는 것을 읽어 그대로 쓴다(반환이 옵셔널이 아니면 `guard let` 대신 그대로 받는다).

`MREngineStore.swift`: `@Published private(set) var heat = MRHeatModel()` 아래에
```swift
    /// 기온 보정 심박 — 심박을 과거와 비교·판정하는 모든 자리가 이 모델 하나를 쓴다.
    @Published private(set) var heatHR = MRHeatHRModel()
```
`refreshCore()`의 `heat = mrFitHeatModel(runs: fetched)` 바로 아래에
```swift
        heatHR = mrFitHeatHRModel(runs: fetched, asOf: now)
```
(`now`는 그 함수에 이미 있는 변수명을 쓴다; 없으면 `Date()`.)

- [ ] **Step 4: 통과 확인** — `MRHeatHRModelTests` 8개.
- [ ] **Step 5: 커밋** — "MRHeatHRModel — 본인 기록으로 15°C 초과 1°C당 심박을 학습, 못 배우면 문헌 0.8 bpm/°C 폴백(참고 표시)"

---

### Task 2: `RunInsightEngine` — 효율·드리프트·이지런 강도에 보정 적용

> **리뷰 반영(구현 완료 후 확정)**: 더위가 차이를 설명하는지는 양쪽 보정 후 차이(`diff > -3`)로 판정(오늘 기온만 보면 과거가 더웠던 경우를 놓친다). 기온 커버리지 규칙에 오늘 기온 유무도 포함. 개선 주장은 원본·보정 둘 다 3 bpm 이상 낮을 때만. 과거가 더웠던 경우 "더운 날이 많았던 최근 기록을 15°C 기준으로 맞추면 …" 접두. 폴백 모델은 "감안해도"·이지런 접미도 "일반적인 더위 영향" 톤. 드리프트 "올랐어요"는 양수 드리프트에서만. 커밋 3e89cd2·9a64c3b + 리뷰 반영 커밋이 기준.

**Files:**
- Modify: `MIMORunning/Insight/RunInsightEngine.swift` (`insights(...)` 365–382 · `efficiencyInsight` 1296 · `cardiacDriftInsight` 673 · `easyOverpaceInsight` 709 · 호출부 413/424/436/465/520)
- Modify: `MIMORunning/Views/ActivityDetailView.swift:865-884` (`heatHR: engine.heatHR` 전달)
- Test: `MIMORunningTests/HeatAdjustedHRInsightTests.swift`

- [ ] **Step 1: 실패하는 테스트** (Swift Testing, 문자열이라 `.serialized`)

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("기온 보정 심박 — 러닝 인사이트", .serialized)
struct HeatAdjustedHRInsightTests {
    private func run(_ daysAgo: Int, pace: Double, hr: Int, temp: Double?, id: UUID = UUID()) -> Activity {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return Activity(id: id, type: .running, date: d, duration: pace * 10, distance: 10_000,
                        calories: nil, avgHeartRate: hr, temperatureC: temp, humidityPercent: nil)
    }
    private var model: MRHeatHRModel { var m = MRHeatHRModel.fallback(); m.isFallback = false; return m } // 0.8 bpm/°C, 학습형

    @Test func heatExplainsTheWholeDifference() {
        AppLanguage.shared.isEnglish = false
        let today = run(0, pace: 376, hr: 149, temp: 25)                  // 보정 −8 → 141
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 146, temp: 15) }
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: model)
        #expect(r?.badge == "기온 감안")
        #expect(r?.message == "비슷한 페이스 최근 5회 대비 심박이 3 bpm 높지만 25°C 기온을 감안하면 평소 수준이에요.")
        #expect(r?.tone == .neutral)
    }

    @Test func fallbackModelUsesReferenceTone() {
        AppLanguage.shared.isEnglish = false
        let today = run(0, pace: 376, hr: 149, temp: 25)
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 146, temp: 15) }
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: .fallback())
        #expect(r?.badge == "참고")
        #expect(r?.message == "비슷한 페이스 최근 5회 대비 심박이 3 bpm 높지만 일반적인 더위 영향(25°C)을 감안하면 평소 수준으로 보여요.")
    }

    @Test func stillHigherAfterAdjustment() {
        AppLanguage.shared.isEnglish = false
        let today = run(0, pace: 376, hr: 160, temp: 25)                  // 보정 152, 과거 146 → +6
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 146, temp: 15) }
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: model)
        #expect(r?.message == "25°C 기온을 감안해도 비슷한 페이스 최근 5회 대비 심박이 6 bpm 높아요. 오늘 컨디션을 반영한 것일 수 있어요.")
    }

    @Test func lowerAfterAdjustmentIsEfficiencyGain() {
        AppLanguage.shared.isEnglish = false
        let today = run(0, pace: 376, hr: 142, temp: 15)
        let hist = (1...5).map { run($0 * 3, pace: 376, hr: 150, temp: 28) } // 과거는 더운 날 → 보정 139.6
        let r = RunInsightEngine.efficiencyInsight(activity: today, history: hist, heatHR: model)
        // 보정 후 오늘 142 vs 과거 139.6 → 차이 2.4 < 3 → 침묵 (더운 날의 과거 심박을 그대로 비교하면 "8 낮음"으로 과장됐을 것)
        #expect(r == nil)
    }

    @Test func historyIsPointInTime() {
        AppLanguage.shared.isEnglish = false
        let today = run(10, pace: 376, hr: 149, temp: 15)
        let future = (0...4).map { run($0, pace: 376, hr: 130, temp: 15) }   // 이 러닝 이후 기록
        #expect(RunInsightEngine.efficiencyInsight(activity: today, history: future, heatHR: model) == nil)
    }

    @Test func driftNoteMentionsHeatWhenHot() {
        AppLanguage.shared.isEnglish = false
        let today = run(0, pace: 376, hr: 149, temp: 26)
        let samples: [(offset: TimeInterval, bpm: Int)] = (0..<120).map { i in (Double(i) * 30, i < 60 ? 143 : 155) }
        let r = RunInsightEngine.cardiacDriftInsight(activity: today, hrSamples: samples, category: .efficiency, heatHR: model)
        #expect(r?.message == "후반 심박이 전반보다 12bpm 올랐어요. 26°C에서는 흔한 폭이에요.")
        let cool = run(0, pace: 376, hr: 149, temp: 12)
        let r2 = RunInsightEngine.cardiacDriftInsight(activity: cool, hrSamples: samples, category: .efficiency, heatHR: model)
        #expect(r2?.message == "후반 심박이 전반보다 12bpm 올랐어요.")
    }

    @Test func easyOverpaceUsesAdjustedHR() {
        AppLanguage.shared.isEnglish = false
        // 최대 170 · 관측 130(76%) · 25°C → 보정 122(72%) → 여유 있는 강도
        let today = run(0, pace: 420, hr: 130, temp: 25)
        let r = RunInsightEngine.easyOverpaceInsight(activity: today, age: nil, hrMax: 170, heatHR: model)
        #expect(r?.tone == .good)
        #expect(r?.message == "심박 72%로 여유 있는 강도의 이지런이었어요. (25°C 감안)")
    }
}
```

- [ ] **Step 2: 실패 확인** — 세 함수가 `private`이거나 `heatHR` 인자가 없어 컴파일 실패.

- [ ] **Step 3: 구현**

1. `insights(...)`에 인자 추가: `heat: MRHeatModel,` 다음 줄에 `heatHR: MRHeatHRModel = MRHeatHRModel(),`. 본문에서 `efficiencyInsight(activity:history:)` 호출 3곳(413·465·520 근처)을 `efficiencyInsight(activity: activity, history: history, heatHR: heatHR)`로, `cardiacDriftInsight(...)` 2곳(413·436)에 `heatHR: heatHR` 추가, `easyOverpaceInsight(activity:age:hrMax:)` 1곳(424)에 `heatHR: heatHR` 추가.

2. `efficiencyInsight` — `private static` → `static` (테스트용). 시그니처 `static func efficiencyInsight(activity: Activity, history: [Activity], heatHR: MRHeatHRModel) -> RunInsight?`. 본문:

```swift
        guard let currentRef  = heatHR.refHR(of: activity),
              let currentPace = activity.paceSecPerKm, currentPace > 0 else { return nil }
        let L = AppLanguage.shared
        let window = 15.0

        // 이 러닝 이전 기록만 (엔진의 다른 사실과 같은 시점 규칙)
        let comparable = history.filter {
            $0.type == .running && $0.id != activity.id && $0.date < activity.date &&
            $0.avgHeartRate != nil &&
            abs(($0.paceSecPerKm ?? -999) - currentPace) <= window
        }
        guard comparable.count >= 3 else { return nil }

        // 과거도 같은 모델로 15°C 환산 — 더운 날의 과거 심박이 "높았던 기준"으로 남지 않게.
        // 단, 과거 기록의 기온 커버리지가 50% 미만이면 한쪽만 보정하는 셈이라 양쪽 다 원본으로 비교하고
        // 더위는 "영향일 수 있어요"로만 말한다(coverageOK == false 분기).
        let histRefs  = comparable.compactMap { heatHR.refHR(of: $0) }
        let avgHistRef = histRefs.reduce(0, +) / Double(histRefs.count)
        let histRaw    = comparable.compactMap { $0.avgHeartRate.map(Double.init) }
        let avgHistRaw = histRaw.reduce(0, +) / Double(histRaw.count)

        let rawDiff = avgHistRaw - Double(activity.avgHeartRate!)   // 미보정 (양수 = 오늘이 낮음)
        let diff    = avgHistRef - currentRef                       // 보정 후
        let heatBpm = heatHR.delta(activity.temperatureC)
        let tempStr = activity.temperatureC.map { "\(Int($0.rounded()))°C" } ?? ""
        let sampleStr = "\(comparable.count)"

        // ① 더위가 차이를 통째로 설명 — 미보정으로는 3 이상 높은데 보정하면 3 미만
        if rawDiff <= -3, abs(diff) < 3, heatHR.explains(tempC: activity.temperatureC) {
            let rawStr = "\(Int(abs(rawDiff).rounded()))"
            if heatHR.isFallback {
                return RunInsight(category: .efficiency, tone: .neutral, badge: L.s("참고", "Note"),
                    message: L.s("비슷한 페이스 최근 \(sampleStr)회 대비 심박이 \(rawStr) bpm 높지만 일반적인 더위 영향(\(tempStr))을 감안하면 평소 수준으로 보여요.",
                                 "HR is \(rawStr) bpm higher vs \(sampleStr) similar-pace runs, but allowing for typical heat effects (\(tempStr)) it looks like your usual level."),
                    highlights: [rawStr + "bpm", tempStr])
            }
            return RunInsight(category: .efficiency, tone: .neutral, badge: L.s("기온 감안", "Heat-Adjusted"),
                message: L.s("비슷한 페이스 최근 \(sampleStr)회 대비 심박이 \(rawStr) bpm 높지만 \(tempStr) 기온을 감안하면 평소 수준이에요.",
                             "HR is \(rawStr) bpm higher vs \(sampleStr) similar-pace runs, but at \(tempStr) that is your usual level."),
                highlights: [rawStr + "bpm", tempStr])
        }
        guard abs(diff) >= 3 else { return nil }
        let diffStr = "\(Int(abs(diff).rounded()))"

        if diff > 0 {
            // 기존 "낮아요 — 심폐 효율 개선" 문장 그대로 (보정값으로 계산됐을 뿐)
            … 기존 코드 …
        } else {
            … 기존 gapDays/cause 계산 그대로 …
            let prefix = heatHR.explains(tempC: activity.temperatureC)
                ? L.s("\(tempStr) 기온을 감안해도 ", "Even allowing for \(tempStr), ")
                : ""
            let msg = L.s(
                "\(prefix)비슷한 페이스 최근 \(sampleStr)회 대비 심박이 \(diffStr) bpm 높아요. \(cause)",
                "\(prefix)HR is \(diffStr) bpm higher vs \(sampleStr) similar-pace runs — \(cause)")
            return RunInsight(category: .efficiency, tone: .neutral, badge: L.s("참고", "Note"),
                              message: msg, highlights: [diffStr + "bpm", sampleStr + "회"])
        }
```
(`heatBpm`은 쓰지 않으면 지운다. 영어 `prefix` 뒤 문장의 첫 글자는 소문자 그대로 둔다.)

3. `cardiacDriftInsight` — `private static` → `static`, 인자 `heatHR: MRHeatHRModel` 추가. 드리프트가 6% 초과인 분기의 문장 뒤에, `heatHR.delta(activity.temperatureC) >= 5 && driftPct <= 10`이면 `" \(tempStr)에서는 흔한 폭이에요."` / `" Common at \(tempStr)."`를 붙인다(`tempStr` = 반올림 정수 + "°C").

4. `easyOverpaceInsight` — `private static` → `static`, 인자 `heatHR: MRHeatHRModel` 추가. `pct`를 `heatHR.refHR(of: activity)!`로 계산(`avgHR` guard를 `refHR`로 바꾼다). `heatHR.explains(tempC:)`이면 두 문장 끝에 `" (\(tempStr) 감안)"` / `" (adjusted for \(tempStr))"`를 붙인다.

5. `ActivityDetailView.swift:877` `heat: engine.heat,` 아래에 `heatHR: engine.heatHR,`.

- [ ] **Step 4: 통과 확인** — `HeatAdjustedHRInsightTests` 7개 + 기존 `FormTypeCaptionTests`(`efficiencyComparisonApplies`) 회귀.
- [ ] **Step 5: 커밋** — "러닝 인사이트 — 비슷한 페이스 대비 심박·드리프트·이지런 강도를 15°C 기준 심박으로 판정, 과거 기록도 같은 모델로 환산"

---

### Task 3: 퍼포먼스 카드 — 산점도·심박 효율 캡션을 보정 심박으로

> **리뷰 반영(구현 완료 후 확정)**: `scatterEligible`로 필터를 뽑아 '15°C 기준' 표기는 실제 그려진 점 기준. 오늘 심박 바인딩은 `refHR`로. 영어 캡션 '(vs. similar pace · at 15°C)'. 복귀(공백) 비교도 15°C 기준. 커밋 29cc6e5 + Task 4 정리 커밋.

**Files:**
- Modify: `MIMORunning/Views/RunInsightCardView.swift` (`heatModel` 옆에 `heatHRModel` 전달)
- Modify: `MIMORunning/Views/ActivityDetailView.swift:269` (`heatHRModel: engine.heatHR`)
- Modify: `MIMORunning/Views/RunInsightTabCard.swift` — `RunInsightTabCard`·`InsightExportSheet`·`PerformanceInsightCard`·`RhythmInsightCard`에 `var heatHRModel: MRHeatHRModel? = nil` 추가·전달(호출부 ~1005·5433·962·5404), `scatterData` 3224, `hrTrendPts` 3206, `hrDelta` 3253, 범례 3095, 캡션 2953–2969

- [ ] **Step 1: 플럼빙** — 위 네 구조체에 프로퍼티를 추가하고 모든 생성 호출부에 `heatHRModel: heatHRModel`을 넘긴다. `RunInsightCardView`는 `heatModel`과 같은 방식으로 한 줄 추가.

- [ ] **Step 2: 산점도 데이터** — `PerformanceInsightCard`에 헬퍼:
```swift
    /// 비교·판정용 심박 — 모델이 있으면 15°C 환산. 없으면 원본.
    private func refHR(_ a: Activity) -> Double? {
        if let m = heatHRModel { return m.refHR(of: a) }
        return a.avgHeartRate.map(Double.init)
    }
    /// 산점도·캡션에 "15°C 기준"을 붙일지 — 실제로 보정된 점이 하나라도 있을 때만
    private var scatterIsHeatAdjusted: Bool {
        guard let m = heatHRModel, m.ok else { return false }
        let all = [activity] + history
        return all.contains { m.delta($0.temperatureC) >= 1 }
    }
```
`scatterData`에서 `Double(th)`·`Double(act.avgHeartRate!)`를 `refHR(activity)!`·`refHR(act)!`로 바꾼다(guard/filter 조건은 `avgHeartRate != nil` 그대로 두어도 `refHR`이 non-nil). `hrTrendPts`도 `Double(r.avgHeartRate!)`·`Double(curHR)`을 `refHR(...)`로. `hrDelta`의 `Double(curHR)`도 `refHR(activity)`.

- [ ] **Step 3: 표기** — 범례 `HStack(spacing: 12)` 마지막에, `scatterIsHeatAdjusted`일 때만
```swift
                    Text(L.s("15°C 기준", "at 15°C"))
                        .font(.system(size: 8)).foregroundStyle(.white.opacity(0.50))
```
심박 효율 캡션(2953–2969)의 "(동일 페이스 기준)" 문자열이 있으면 `scatterIsHeatAdjusted`일 때 "(동일 페이스 · 15°C 기준)" / "(same pace · at 15°C)"로.

- [ ] **Step 4: 빌드** — `** BUILD SUCCEEDED **`.
- [ ] **Step 5: 커밋** — "퍼포먼스 카드 — 심박 효율 산점도·캡션을 15°C 기준 심박으로 (계절 파도 제거), 범례에 '15°C 기준'"

---

### Task 4: 리듬 카드 — 존 캡션·폼 해석·총평 심박 줄

> **리뷰 반영(구현 완료 후 확정)**: 더위 표기는 **존 도넛 캡션 한 곳**만(' · 더위로 +Nbpm', 폴백이면 '정도'), 총평 줄 상태어에는 붙이지 않음(근거 줄이 맡음). 복귀 문장은 원본 bpm을 표시하고 비교만 보정. 폼 해석의 '심박 낮았어요'는 원본도 낮을 때만. 커밋 ddfd8b4·8f3ad99 + 리뷰 반영 커밋.

**Files:**
- Modify: `MIMORunning/Views/RunInsightTabCard.swift` — `zoneVerdictLabel` 2412, `formInterpretation` 1881, `summaryLines` ~2600
- Modify: `MIMORunning/Insight/RunSummary.swift` — `RunSummaryInput.heatDeltaBpm`, `heartRateLine`
- Test: `MIMORunningTests/RunSummaryTests.swift`

- [ ] **Step 1: 실패하는 테스트** (RunSummaryTests에 추가)
```swift
    @Test func heartRateLineAppendsHeatNoteOnNeutralTone() {
        var i = RunSummaryInput(); i.workoutType = .general; i.zoneFractions = [3: 0.3, 4: 0.6, 5: 0.1]; i.heatDeltaBpm = 8
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "고강도 구간이 많음 · Zone 3 이상 100% · 더위 +8bpm 감안", tone: .neutral)])
    }
    @Test func heartRateLineNoHeatNoteWhenSmallOrGood() {
        var i = RunSummaryInput(); i.workoutType = .general; i.zoneFractions = [3: 0.3, 4: 0.6, 5: 0.1]; i.heatDeltaBpm = 3
        #expect(lines(i).first?.state == "고강도 구간이 많음 · Zone 3 이상 100%")
        var g = RunSummaryInput(); g.zoneFractions = [2: 0.7, 3: 0.3]; g.heatDeltaBpm = 8
        #expect(lines(g).first?.state == "딱 좋은 강도")
    }
```
- [ ] **Step 2: 실패 확인** — `heatDeltaBpm` 없음.
- [ ] **Step 3: 구현**
  - `RunSummaryInput`에 `/// 이 러닝의 기온 보정량(bpm). 5 이상이고 톤이 neutral일 때만 접미로 붙는다.` `var heatDeltaBpm: Double? = nil`. `RunSummary`에 `static let heatNoteMinBpm = 5.0`.
  - `heartRateLine` 끝: 만든 `RunSummaryLine`이 `.neutral`이고 `heatDeltaBpm >= heatNoteMinBpm`이면 `state += L.s(" · 더위 +\(Int(d.rounded()))bpm 감안", " · heat +\(Int(d.rounded())) bpm allowed")`. 구현은 `heartRateLine`을 `baseHeartRateLine` + 접미 래퍼로 나누면 깔끔하다.
  - `RhythmInsightCard.summaryLines`: `input.heatDeltaBpm = heatHRModel?.delta(activity.temperatureC)`.
  - `zoneVerdictLabel`: `dom.id >= 3`이고 `heatHRModel?.delta(activity.temperatureC) ?? 0 >= 5`이면 반환 문자열 뒤에 `" · 더위 +Nbpm"` / `" · heat +N bpm"`. 비율·색은 그대로(결정 2).
  - `formInterpretation` 5번 심박 분기: `Double(hr)`를 `heatHRModel?.refHR(of: activity) ?? Double(hr)`로.
- [ ] **Step 4: 테스트·빌드** — `RunSummaryTests` 28개.
- [ ] **Step 5: 커밋** — "리듬 카드 — 존 캡션·폼 해석·총평 심박 줄에 더위 보정량 반영 (존 비율은 원본 유지)"

---

### Task 5: `InsightEngine`(디스크 캐시) — 안전 메모·트레이드오프·회복

> **리뷰 반영(구현 완료 후 확정)**: 심폐 개선(트레이드오프 #1)은 원본·보정 둘 다 5% 이상 낮을 때만 + '(기온 감안)'. 기온 커버리지(오늘 있음 + 과거 절반 이상) 미달이면 양쪽 원본 비교. 커밋 8be6d85 + 리뷰 반영 커밋.

**Files:**
- Modify: `MIMORunning/Insight/InsightEngine.swift` — `compute(...)` 107–119, `safetyNote` 713–722, `hrElevatedNote` 723–747, `recovery` 614–632, `tradeoffInsight` 815–900
- Modify: `MIMORunning/Insight/InsightCache.swift:65` — `cacheVersion = 22`
- Modify: `MIMORunning/Views/ActivityDetailView.swift` — `InsightEngine.compute(...)` 호출부에 `heatHR: engine.heatHR` (호출 위치는 `grep -n "InsightEngine.compute" MIMORunning/Views/ActivityDetailView.swift`)

- [ ] **Step 1: 구현**
  - `compute(...)`에 `heatHR: MRHeatHRModel = MRHeatHRModel()` 인자 추가. 내부에서 `let refHR: (Activity) -> Double? = { heatHR.refHR(of: $0) }`를 만들어 아래 세 곳에 넘긴다.
  - `hrElevatedNote`: `currentHR`·`bandHRs`를 `refHR`로 계산. 이제 더위를 단계적으로 빼므로 `safetyNote`의 `isHot` 이진 게이트는 **유지하되** 순서만 바꾼다: 보정 후에도 8% 이상 높으면 `hrElevatedNote`, 아니고 `isHot`이면 `heatCareNote`. detail 문장 끝에 `heatHR.explains(tempC:)`이면 `" (기온 감안)"`.
  - `tradeoffInsight` #1·#5, `recovery`: `avgHeartRate` 비교를 `refHR`로.
  - `InsightCache.cacheVersion = 22` 주석: `// 심박 비교를 15°C 기준으로 (v21: 이 러닝 이전 기록만)`.
- [ ] **Step 2: 빌드 + 기존 테스트** — `InsightPointInTimeTests`, `InsightFactGuardTests`, `MIMORunningTests`(캐시 파일명) 통과.
- [ ] **Step 3: 커밋** — "인사이트 엔진 — 같은 페이스대 심박 상승·심폐 개선·회복 판정을 15°C 기준 심박으로, 캐시 v22"

---

### Task 6: 확인 — 스냅샷 + 전체 관련 스위트

- [ ] 관련 스위트 일괄: `MRHeatHRModelTests`, `HeatAdjustedHRInsightTests`, `RunSummaryTests`, `FormTypeCaptionTests`, `InsightPointInTimeTests`, `MRRobustnessTests`, `MIMORunningTests` 모두 통과.
- [ ] 임시 테스트(커밋 안 함)로 `RunInsightTabCard`(리듬)·`PerformanceInsightCard`가 포함된 `RunInsightTabCard` 퍼포먼스 탭을 25°C 러닝 + 15°C 과거 기록 + `MRHeatHRModel.fallback()`으로 ImageRenderer 렌더 → 산점도 범례 "15°C 기준", 존 캡션 "· 더위 +8bpm", 총평 심박 줄 접미 확인. (퍼포먼스 탭은 `@State tab`이라 직접 못 바꾸면 `PerformanceInsightCard`를 파일 내부에서 `fileprivate`→`internal`로 잠시 열지 말고, 리듬 카드만 렌더하고 산점도는 단위 로직(`scatterData`)을 로그로 확인한다.)

---

## 범위 밖(후속)
- `RunInsightEngine.intensityInsight`(~1193)·`distanceRunInsight`(~841)의 원본 심박 vs `easyCeilingHR`/`lt1HR` 비교 — 같은 계절 파도를 탄다. 다음 차례로 가장 가치가 큼. `RunBaseline.medianHR`(~127)은 어디서도 읽지 않음(제거 후보).
- `distanceRunInsight`의 배지 "기온 감안"(페이스 더위 모델)과 효율 인사이트의 "기온 감안"(심박)이 한 목록에 같이 뜰 수 있음 — 배지 문구 구분은 후속.
- 성장 탭 `hrPaceWeek`(GrowthView 1188)·`MRAdviceQueue.easyRatio`(28일 이지 비율)·`hrAnalysisCache` 14일 심박 추세 — 같은 `heatHR.refHR`를 쓰면 되지만 이번엔 손대지 않는다.
- `RhythmInsightCard.hrVerdictText`의 `220 − 나이`(2553) — 엔진 규칙(`estimatedHRMax`, Tanaka)과 어긋남. 별건.
- 추위 보정(15°C 아래) — 계수 미신뢰, 의도적으로 제외.
