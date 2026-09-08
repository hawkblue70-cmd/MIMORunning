# 운동 강도(RPE 1~10) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 러닝마다 운동 강도(1~10)를 Apple HealthKit에서 읽거나 앱에서 입력·저장하고, 개인 기준선과 비교한 강도 인사이트(상세)와 sRPE 주간 부하·같은 강도 페이스 추이(성장 탭)·회복 주 경고(플래너)를 보여준다.

**Architecture:** 순수 함수 엔진 3개(`EffortResolver`/`EffortBaseline`/`EffortRules` in `Insight/`, `EffortLoad`/`EffortPaceTrend` in `Engine/`)가 계산을 맡고, 뷰는 `EffortIndex`(사용자 입력 + Apple 값 조합)만 넘긴다. 사용자 입력은 SwiftData `WorkoutStory.effortRPE`, Apple 값은 `HealthKitManager.effortMap`(관계 쿼리, 앵커 증분, 디스크 캐시)에 있다. 뷰는 `WorkoutStory` `@Query` 결과를 `manager.syncUserEfforts(from:)`로 매니저에 동기화해, 매니저 쪽 시계열(`TrendMetric.easyEffortPace`)도 같은 우선순위를 쓴다.

**Tech Stack:** SwiftUI · SwiftData(CloudKit) · HealthKit iOS 18 `HKWorkoutEffortRelationshipQuery` · Swift Testing(`@Suite`/`@Test`) · 기존 `mrFormShift` 판정기.

**Spec:** `docs/superpowers/specs/2026-09-08-workout-effort-design.md`

**스펙 대비 구현상 조정(작은 것 2개)**
1. "이겨낸 러닝" detail에 "체감 강도 N" 덧붙이기는 `InsightEngine`이 아니라 표시 계층(`InsightCard`)에서 한다. `InsightResult`는 디스크 캐시되므로 엔진에 강도를 넣으면 캐시 무효화가 필요해진다. 조건 변경 없음.
2. 매니저는 SwiftData 스토리를 직접 못 읽으므로 뷰가 `manager.syncUserEfforts(from:)`로 사용자 입력을 밀어 넣는다(GrowthView·ActivityDetailView·MeView).
3. (리뷰 후 추가) 규칙 A′ 절대 임계(이지·LSD 8 이상)는 `effort > baseline`일 때만 발화한다. 기준선이 8인 사용자에게 매 이지런마다 경고가 뜨는 것을 막기 위함. 기준선이 없을 때의 7 이상 규칙은 Apple 추정값 단독이면 침묵한다.

---

## 파일 맵

| 파일 | 역할 | 작업 |
|---|---|---|
| `MIMORunning/Insight/EffortResolver.swift` | `AppleEffort`·`ResolvedEffort`·`EffortResolver`·`EffortIndex` | 생성 |
| `MIMORunning/Theme/EffortPalette.swift` | 10색 보간 · `EffortBand`(4구간 라벨) | 생성 |
| `MIMORunning/Insight/EffortBaseline.swift` | 개인 기준선(8주 유형별 중앙값) | 생성 |
| `MIMORunning/Insight/EffortRules.swift` | 규칙 A/B/C → `RunInsight` | 생성 |
| `MIMORunning/Engine/EffortLoad.swift` | sRPE 주간 부하·단조도·7d/28d·회복 주 판정 | 생성 |
| `MIMORunning/Engine/EffortPaceTrend.swift` | 강도 2~4 페이스 추이 관찰 문구 | 생성 |
| `MIMORunning/Views/EffortScaleView.swift` | 10막대 입력 UI | 생성 |
| `MIMORunning/Views/EffortLoadCard.swift` | 성장 탭 주간 부하 카드 | 생성 |
| `MIMORunning/Models/WorkoutStory.swift` | `effortRPE`·`effortUpdatedAt` | 수정 |
| `MIMORunning/Models/Activity.swift` | `ActivityDetail.appleEffort` + Codable, `TrendMetric.easyEffortPace` | 수정 |
| `MIMORunning/Health/HealthKitManager.swift` | 읽기 타입·관계 쿼리·effortMap·syncUserEfforts·easyEffortPace 히스토리 | 수정 |
| `MIMORunning/Insight/RunInsightEngine.swift` | `insights(...)`에 effort 입력, 규칙 결과 병합 | 수정 |
| `MIMORunning/Views/ActivityDetailView.swift` | StorySection에 강도 UI, 인사이트 재계산, InsightCard detail | 수정 |
| `MIMORunning/Views/GrowthView.swift` | 부하 카드·추이 관찰·동기화 | 수정 |
| `MIMORunning/Views/GrowthShareCardView.swift` | TrendMetric switch 케이스 | 수정 |
| `MIMORunning/Views/MRRacePlanView.swift` | 회복 주 문장 전달·표시 | 수정 |
| `MIMORunning/Views/MeView.swift` | 회복 주 문장 계산·동기화 | 수정 |
| `MIMORunningTests/EffortResolverTests.swift` | | 생성 |
| `MIMORunningTests/EffortPaletteTests.swift` | | 생성 |
| `MIMORunningTests/EffortBaselineTests.swift` | | 생성 |
| `MIMORunningTests/EffortRulesTests.swift` | | 생성 |
| `MIMORunningTests/EffortLoadTests.swift` | | 생성 |
| `MIMORunningTests/EffortPaceTrendTests.swift` | | 생성 |

**테스트 실행 명령** (스위트 이름만 바꾼다):

```bash
xcodebuild test -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MIMORunningTests/<SuiteTypeName> 2>&1 | grep -E 'Test (Suite|Case)|passed|failed|error:' | tail -30
```

빌드만 확인:

```bash
xcodebuild build -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E 'error:|BUILD' | tail -10
```

새 Swift 파일은 프로젝트가 폴더 참조(file system synchronized group)가 아니면 Xcode에서 타깃에 추가해야 한다. `cannot find 'X' in scope`가 나면 파일을 `MIMORunning` 타깃(테스트 파일은 `MIMORunningTests`)에 추가한다. `AppLanguage.shared.s(ko, en)`이 ko/en 문구 헬퍼다(파일 안에서 `let L = AppLanguage.shared`로 줄여 쓴다).

**커밋 메시지 규칙**: 한국어 한 줄 요약 + 빈 줄 + `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

## Task 1: EffortResolver — 값 우선순위 해석기

**Files:**
- Create: `MIMORunning/Insight/EffortResolver.swift`
- Test: `MIMORunningTests/EffortResolverTests.swift`

- [x] **Step 1: 실패하는 테스트 작성**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("EffortResolver 우선순위")
struct EffortResolverTests {

    @Test func userBeatsAppleManualBeatsEstimated() {
        let apple = AppleEffort(manual: 6, estimated: 4, fetchedAt: Date())
        #expect(EffortResolver.resolve(userValue: 3, apple: apple) == ResolvedEffort(value: 3, source: .user))
        #expect(EffortResolver.resolve(userValue: nil, apple: apple) == ResolvedEffort(value: 6, source: .appleManual))
        let est = AppleEffort(manual: nil, estimated: 4.4, fetchedAt: Date())
        #expect(EffortResolver.resolve(userValue: nil, apple: est) == ResolvedEffort(value: 4, source: .appleEstimated))
        #expect(EffortResolver.resolve(userValue: nil, apple: nil) == nil)
    }

    @Test func roundsAndClamps() {
        let apple = AppleEffort(manual: nil, estimated: 7.5, fetchedAt: Date())
        #expect(EffortResolver.resolve(userValue: nil, apple: apple)?.value == 8)
        #expect(EffortResolver.resolve(userValue: 14, apple: nil)?.value == 10)
        #expect(EffortResolver.resolve(userValue: 0, apple: nil)?.value == 1)
        let big = AppleEffort(manual: 12, estimated: nil, fetchedAt: Date())
        #expect(EffortResolver.resolve(userValue: nil, apple: big)?.value == 10)
    }

    @Test func effectiveAndSameValues() {
        let a = AppleEffort(manual: nil, estimated: 5, fetchedAt: Date())
        #expect(a.effective == 5)
        let b = AppleEffort(manual: nil, estimated: 5, fetchedAt: Date(timeIntervalSince1970: 0))
        #expect(a.hasSameValues(as: b))
        #expect(!a.hasSameValues(as: AppleEffort(manual: 5, estimated: 5, fetchedAt: Date())))
    }

    @Test func indexResolvesByWorkoutID() {
        let id = UUID()
        let idx = EffortIndex(user: [id.uuidString: 4],
                              apple: [id: AppleEffort(manual: 7, estimated: nil, fetchedAt: Date())])
        #expect(idx.resolve(id) == ResolvedEffort(value: 4, source: .user))
        let other = UUID()
        #expect(idx.resolve(other) == nil)
    }
}
```

- [x] **Step 2: 실패 확인**

Run: 위 테스트 명령, `EffortResolverTests`
Expected: 컴파일 에러 `cannot find 'AppleEffort' in scope`

- [x] **Step 3: 구현**

```swift
import Foundation

/// Apple HealthKit 운동 강도 — 수동(`workoutEffortScore`)·추정(`estimatedWorkoutEffortScore`). 1~10.
struct AppleEffort: Codable, Equatable {
    var manual: Double?
    var estimated: Double?
    var fetchedAt: Date

    /// 피트니스 앱과 동일 규칙: 수동값이 있으면 수동, 없으면 추정.
    var effective: Double? { manual ?? estimated }

    /// fetchedAt을 무시한 값 비교 — 캐시 갱신 여부 판단용.
    func hasSameValues(as other: AppleEffort) -> Bool {
        manual == other.manual && estimated == other.estimated
    }
}

enum EffortSource: Equatable {
    case user, appleManual, appleEstimated
}

struct ResolvedEffort: Equatable {
    let value: Int          // 1...10
    let source: EffortSource
}

/// 우선순위: 내 입력 > Apple 수동 > Apple 추정 > nil. 심박 기반 추정은 하지 않는다.
enum EffortResolver {
    static func clamp(_ v: Int) -> Int { min(10, max(1, v)) }
    static func clamp(_ v: Double) -> Int { clamp(Int(v.rounded())) }

    static func resolve(userValue: Int?, apple: AppleEffort?) -> ResolvedEffort? {
        if let u = userValue { return ResolvedEffort(value: clamp(u), source: .user) }
        if let m = apple?.manual { return ResolvedEffort(value: clamp(m), source: .appleManual) }
        if let e = apple?.estimated { return ResolvedEffort(value: clamp(e), source: .appleEstimated) }
        return nil
    }
}

/// 뷰·엔진이 들고 다니는 조회 인덱스 — 사용자 입력(workoutID 문자열 키) + Apple 값(UUID 키).
struct EffortIndex {
    let user: [String: Int]
    let apple: [UUID: AppleEffort]

    init(user: [String: Int], apple: [UUID: AppleEffort]) {
        self.user = user
        self.apple = apple
    }

    /// WorkoutStory 목록에서 사용자 입력만 추린다.
    init(stories: [WorkoutStory], apple: [UUID: AppleEffort]) {
        var u: [String: Int] = [:]
        for s in stories { if let r = s.effortRPE { u[s.workoutID] = r } }
        self.init(user: u, apple: apple)
    }

    func resolve(_ id: UUID) -> ResolvedEffort? {
        EffortResolver.resolve(userValue: user[id.uuidString], apple: apple[id])
    }
}
```

주의: `init(stories:)`는 Task 2의 `effortRPE`가 있어야 컴파일된다. Task 2를 먼저 적용하거나 이 이니셜라이저를 Task 2 뒤에 추가한다. 여기서는 **Task 2를 바로 이어서 수행**하고 두 태스크를 함께 빌드한다.

- [x] **Step 4: Task 2 완료 후 테스트 통과 확인**

Run: `EffortResolverTests`
Expected: 4 tests passed

- [x] **Step 5: 커밋** (Task 2와 함께)

---

## Task 2: WorkoutStory에 강도 필드

**Files:**
- Modify: `MIMORunning/Models/WorkoutStory.swift:100-107`

- [x] **Step 1: 필드 추가**

`final class WorkoutStory` 안, `var shoeID: String?` 바로 아래에:

```swift
    /// 사용자가 앱에서 입력한 운동 강도 1...10. nil = 미입력(Apple 값 사용).
    /// CloudKit: 옵셔널 + 기본값 nil.
    var effortRPE: Int?
    var effortUpdatedAt: Date?
```

`hasContent`는 바꾸지 않는다(강도만 있어도 "일기 있음"이 아님).

- [x] **Step 2: 빌드 + Task 1 테스트**

Run: 빌드 명령 → `BUILD SUCCEEDED`. 그 다음 `EffortResolverTests` → 4 passed.

- [x] **Step 3: 커밋**

```bash
git add MIMORunning/Insight/EffortResolver.swift MIMORunning/Models/WorkoutStory.swift MIMORunningTests/EffortResolverTests.swift
git commit -m "운동 강도: AppleEffort·EffortResolver·EffortIndex + WorkoutStory.effortRPE

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 3: EffortPalette — 10색 보간과 4구간 라벨

**Files:**
- Create: `MIMORunning/Theme/EffortPalette.swift`
- Test: `MIMORunningTests/EffortPaletteTests.swift`

- [x] **Step 1: 실패하는 테스트**

```swift
import Testing
import SwiftUI
@testable import MIMORunning

@Suite("EffortPalette 10색 · 4구간")
struct EffortPaletteTests {

    private func close(_ a: EffortPalette.RGBA, _ b: EffortPalette.RGBA) -> Bool {
        abs(a.r - b.r) < 0.02 && abs(a.g - b.g) < 0.02 && abs(a.b - b.b) < 0.02
    }

    @Test func endpointsMatchHRZoneRamp() {
        #expect(close(EffortPalette.rgba(EffortPalette.color(for: 1)), EffortPalette.rgba(Theme.hrZoneColors[0])))
        #expect(close(EffortPalette.rgba(EffortPalette.color(for: 10)), EffortPalette.rgba(Theme.hrZoneColors[4])))
        #expect(EffortPalette.colors.count == 10)
    }

    @Test func clampsOutOfRange() {
        #expect(close(EffortPalette.rgba(EffortPalette.color(for: 0)), EffortPalette.rgba(EffortPalette.color(for: 1))))
        #expect(close(EffortPalette.rgba(EffortPalette.color(for: 99)), EffortPalette.rgba(EffortPalette.color(for: 10))))
    }

    @Test func bands() {
        #expect(EffortBand(value: 1) == .easy)
        #expect(EffortBand(value: 3) == .easy)
        #expect(EffortBand(value: 4) == .moderate)
        #expect(EffortBand(value: 6) == .moderate)
        #expect(EffortBand(value: 7) == .hard)
        #expect(EffortBand(value: 8) == .hard)
        #expect(EffortBand(value: 9) == .allOut)
        #expect(EffortBand(value: 10) == .allOut)
        #expect(EffortBand.easy.range == 1...3)
        #expect(EffortBand.allOut.range == 9...10)
    }
}
```

- [x] **Step 2: 실패 확인** — `cannot find 'EffortPalette' in scope`

- [x] **Step 3: 구현**

```swift
import SwiftUI
import UIKit

/// Apple 피트니스 어휘의 4구간 (2차 소스 기준: Easy 1–3 · Moderate 4–6 · Hard 7–8 · All Out 9–10)
enum EffortBand: CaseIterable, Equatable {
    case easy, moderate, hard, allOut

    init(value: Int) {
        switch value {
        case ...3:   self = .easy
        case 4...6:  self = .moderate
        case 7...8:  self = .hard
        default:     self = .allOut
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .easy:     1...3
        case .moderate: 4...6
        case .hard:     7...8
        case .allOut:   9...10
        }
    }

    var label: String {
        let L = AppLanguage.shared
        return switch self {
        case .easy:     L.s("쉬움", "Easy")
        case .moderate: L.s("보통", "Moderate")
        case .hard:     L.s("힘듦", "Hard")
        case .allOut:   L.s("전력", "All Out")
        }
    }
}

/// `Theme.hrZoneColors`(파랑→빨강 5색)를 10단계로 선형 보간. index 0 = 강도 1.
enum EffortPalette {
    struct RGBA { let r: CGFloat; let g: CGFloat; let b: CGFloat; let a: CGFloat }

    static let colors: [Color] = (1...10).map { color(for: $0) }

    static func color(for value: Int) -> Color {
        let stops = Theme.hrZoneColors.map { UIColor($0) }
        let v = min(10, max(1, value))
        let t = Double(v - 1) / 9.0 * Double(stops.count - 1)     // 0...4
        let i = min(stops.count - 2, Int(t))
        let f = t - Double(i)
        return Color(uiColor: blend(stops[i], stops[i + 1], f))
    }

    static func rgba(_ color: Color) -> RGBA {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: r, g: g, b: b, a: a)
    }

    private static func blend(_ a: UIColor, _ b: UIColor, _ f: Double) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(f)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: 1)
    }
}
```

- [x] **Step 4: 테스트 통과 확인** — `EffortPaletteTests` 3 passed

- [x] **Step 5: 커밋**

```bash
git add MIMORunning/Theme/EffortPalette.swift MIMORunningTests/EffortPaletteTests.swift
git commit -m "운동 강도: EffortPalette 10색 보간 · EffortBand 4구간

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 4: ActivityDetail.appleEffort + Codable

**Files:**
- Modify: `MIMORunning/Models/Activity.swift:130-147` (구조체), `:238-296` (Codable)

- [x] **Step 1: 프로퍼티 추가**

`struct ActivityDetail` 안, `let altitudeTimeProfile ...` 아래에:

```swift
    /// Apple 운동 강도 캐시 (iOS 18+, 워치 런). 상세 진입 시 재조회로 갱신.
    var appleEffort: AppleEffort? = nil
```

기본값이 있으므로 기존 memberwise 호출(`HealthKitManager.swift:1578`, `:1600`)은 그대로 컴파일된다.

- [x] **Step 2: CodingKeys·decode·encode**

`private enum CodingKeys` 마지막 줄 `case altTimeOffset, altTimeAlt` 아래에 `case appleEffort` 추가.

`init(from:)` 마지막(`altitudeTimeProfile = ...` 다음)에:

```swift
        appleEffort = try c.decodeIfPresent(AppleEffort.self, forKey: .appleEffort)
```

`encode(to:)` 마지막에:

```swift
        try c.encodeIfPresent(appleEffort, forKey: .appleEffort)
```

- [x] **Step 3: 빌드** → `BUILD SUCCEEDED`. 기존 디스크 캐시(v10)는 키가 없어 nil로 디코딩되므로 버전을 올리지 않는다.

- [x] **Step 4: 커밋**

```bash
git add MIMORunning/Models/Activity.swift
git commit -m "운동 강도: ActivityDetail.appleEffort 캐시 필드 + Codable

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 5: HealthKitManager — 읽기 권한 · 관계 쿼리 · effortMap · 사용자 입력 동기화

**Files:**
- Modify: `MIMORunning/Health/HealthKitManager.swift` — `readTypes`(:171), 새 섹션, `fetchActivities`(:240)

HealthKit은 단위 테스트가 불가하다. 이 태스크는 빌드 + 시뮬레이터/실기기 로그로 검증한다.

- [x] **Step 1: 읽기 타입 추가**

`private static let readTypes: Set<HKObjectType> = { [ ... ] }()`를 다음으로 바꾼다(기존 배열 내용은 그대로 두고 `.union` 추가):

```swift
    private static let readTypes: Set<HKObjectType> = {
        let base: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount),
            HKQuantityType(.runningPower),
            HKQuantityType(.runningSpeed),
            HKQuantityType(.runningStrideLength),
            HKQuantityType(.runningVerticalOscillation),
            HKQuantityType(.runningGroundContactTime),
            HKQuantityType(.vo2Max),
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
        ]
        return base.union(effortReadTypes)
    }()

    /// iOS 18+ 운동 강도 타입. 그 이하에서는 빈 집합.
    private static var effortReadTypes: Set<HKObjectType> {
        guard #available(iOS 18, *) else { return [] }
        return [HKQuantityType(.workoutEffortScore), HKQuantityType(.estimatedWorkoutEffortScore)]
    }
```

기존 사용자는 `checkAuthorizationStatus()`의 재요청 경로(`:216`)에서 새 타입 권한 창을 한 번 보게 된다. 추가 코드 없음.

- [x] **Step 2: 강도 섹션 추가**

`// MARK: - Pause Intervals` 바로 위(`enrich` 함수 뒤)에 새 섹션을 넣는다:

```swift
    // MARK: - Workout Effort (iOS 18)

    /// Apple 운동 강도 — 워크아웃 UUID 키. 관계 쿼리 앵커 증분 + 디스크 캐시.
    private(set) var effortMap: [UUID: AppleEffort] = [:]
    /// 앱에서 입력한 강도 — 뷰가 WorkoutStory @Query 결과로 동기화(`syncUserEfforts`).
    private(set) var userEffortByWorkout: [String: Int] = [:]
    @ObservationIgnored private var effortAnchor: HKQueryAnchor? = nil
    @ObservationIgnored private var effortMapLoaded = false

    private struct EffortMapFile: Codable { var entries: [String: AppleEffort] }

    private var effortMapURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_effort_map_v1.json")
    }
    private var effortAnchorURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_effort_anchor_v1.dat")
    }

    /// 뷰·엔진 공용 조회 인덱스.
    var effortIndex: EffortIndex { EffortIndex(user: userEffortByWorkout, apple: effortMap) }

    func appleEffort(for id: UUID) -> AppleEffort? {
        loadEffortMapIfNeeded()
        return effortMap[id]
    }

    /// 사용자 입력 동기화 — 바뀐 게 없으면 무시. 바뀌면 강도 기반 시계열 캐시를 지운다.
    func syncUserEfforts(from stories: [WorkoutStory]) {
        var m: [String: Int] = [:]
        for s in stories { if let r = s.effortRPE { m[s.workoutID] = r } }
        guard m != userEffortByWorkout else { return }
        userEffortByWorkout = m
        try? FileManager.default.removeItem(at: metricHistoryCacheURL(.easyEffortPace, usePounds: false))
    }

    private func loadEffortMapIfNeeded() {
        guard !effortMapLoaded else { return }
        effortMapLoaded = true
        if let data = try? Data(contentsOf: effortMapURL),
           let file = try? JSONDecoder().decode(EffortMapFile.self, from: data) {
            effortMap = Dictionary(uniqueKeysWithValues: file.entries.compactMap { k, v in
                UUID(uuidString: k).map { ($0, v) }
            })
        }
        if let data = try? Data(contentsOf: effortAnchorURL) {
            effortAnchor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        }
    }

    private func saveEffortMap() {
        let file = EffortMapFile(entries: Dictionary(uniqueKeysWithValues: effortMap.map { ($0.key.uuidString, $0.value) }))
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: effortMapURL, options: .atomic)
        }
        if let a = effortAnchor,
           let data = try? NSKeyedArchiver.archivedData(withRootObject: a, requiringSecureCoding: true) {
            try? data.write(to: effortAnchorURL, options: .atomic)
        }
    }

    /// 관계 쿼리 1회 — 첫 결과를 받으면 쿼리를 멈춘다(장기 실행 쿼리이므로 반드시 stop).
    @available(iOS 18, *)
    private func runEffortRelationshipQuery(predicate: NSPredicate?, anchor: HKQueryAnchor?)
        async -> (relationships: [HKWorkoutEffortRelationship], anchor: HKQueryAnchor?) {
        let gate = MRResumeOnce()
        let store = self.store
        return await withCheckedContinuation { cont in
            let query = HKWorkoutEffortRelationshipQuery(predicate: predicate, anchor: anchor,
                                                         options: .mostRelevant) { query, relationships, newAnchor, error in
                guard gate.first() else { return }
                store.stop(query)
                if let error { print("[강도] 관계 쿼리 실패: \(error.localizedDescription)") }
                cont.resume(returning: (relationships ?? [], newAnchor))
            }
            store.execute(query)
        }
    }

    /// 관계 샘플 → AppleEffort. 두 타입 모두 없으면 nil.
    private func appleEffort(from samples: [HKSample]?) -> AppleEffort? {
        guard #available(iOS 18, *), let samples, !samples.isEmpty else { return nil }
        let unit = HKUnit.appleEffortScore()
        var out = AppleEffort(manual: nil, estimated: nil, fetchedAt: Date())
        for case let q as HKQuantitySample in samples {
            let v = q.quantity.doubleValue(for: unit)
            switch q.quantityType.identifier {
            case HKQuantityTypeIdentifier.workoutEffortScore.rawValue:          out.manual = v
            case HKQuantityTypeIdentifier.estimatedWorkoutEffortScore.rawValue: out.estimated = v
            default: break
            }
        }
        return out.effective == nil ? nil : out
    }

    /// 상세 진입 시 — 한 워크아웃의 강도를 다시 읽어 캐시 갱신. 조회 실패·값 없음이면 기존 캐시 반환.
    func refreshEffort(for activityID: UUID) async -> AppleEffort? {
        guard #available(iOS 18, *) else { return nil }
        loadEffortMapIfNeeded()
        let pred = HKQuery.predicateForObject(with: activityID)
        let (rels, _) = await runEffortRelationshipQuery(predicate: pred, anchor: nil)
        guard let rel = rels.first(where: { $0.workout.uuid == activityID }),
              let effort = appleEffort(from: rel.samples) else { return effortMap[activityID] }
        if effortMap[activityID]?.hasSameValues(as: effort) != true {
            effortMap[activityID] = effort
            if var d = detailCache[activityID] {
                d.appleEffort = effort
                detailCache[activityID] = d
                saveDetailToDisk(d, id: activityID)
            }
            saveEffortMap()
        }
        return effort
    }

    /// 증분 갱신 — 앵커 이후 바뀐 관계만. 최근 12개월 러닝 대상. fetchActivities에서 호출.
    func refreshEffortMap() async {
        guard #available(iOS 18, *) else { return }
        loadEffortMapIfNeeded()
        let since = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? .distantPast
        let pred = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
        let (rels, newAnchor) = await runEffortRelationshipQuery(predicate: pred, anchor: effortAnchor)
        var changed = false
        for rel in rels {
            guard let e = appleEffort(from: rel.samples) else { continue }
            if effortMap[rel.workout.uuid]?.hasSameValues(as: e) != true {
                effortMap[rel.workout.uuid] = e
                changed = true
            }
        }
        if let newAnchor { effortAnchor = newAnchor; changed = true }
        if changed { saveEffortMap() }
        #if DEBUG
        print("[강도] Apple 강도 맵 \(effortMap.count)건 (이번 갱신 \(rels.count)관계)")
        #endif
    }
```

파일 맨 아래(클래스 밖)에 헬퍼를 추가한다:

```swift
/// 콜백이 여러 번 와도 continuation은 한 번만 resume.
private final class MRResumeOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func first() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
```

`metricHistoryCacheURL(_:usePounds:)`는 파일에 이미 존재한다(`:3205` 부근에서 사용). `.easyEffortPace`는 Task 12에서 추가되므로 **Task 12 전까지는 `syncUserEfforts`의 마지막 줄을 주석 처리**하고, Task 12에서 주석을 푼다.

- [x] **Step 3: fetchActivities 훅**

`fetchActivities(forced:)` 안, `migrateWorkoutTypeCacheEntries()` 호출 바로 아래에:

```swift
        // Apple 운동 강도 — 앵커 증분. 활동 조회와 독립적으로 백그라운드 실행.
        Task { await self.refreshEffortMap() }
```

- [x] **Step 4: 빌드** → `BUILD SUCCEEDED`. Swift 6 경고(`Sendable`)가 에러면 `runEffortRelationshipQuery` 클로저에서 `store`·`gate`만 캡처하는지 확인한다.

- [x] **Step 5: 시뮬레이터/실기기 확인**

앱 실행 → 콘솔에 `[강도] Apple 강도 맵 N건` 로그. 워치 런이 없는 시뮬레이터는 0건이 정상.

- [x] **Step 6: 커밋**

```bash
git add MIMORunning/Health/HealthKitManager.swift
git commit -m "운동 강도: HealthKit effort 읽기 권한 · 관계 쿼리 · effortMap 앵커 캐시 · 사용자 입력 동기화

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 6: EffortScaleView — 10막대 입력 UI + StorySection 배치

**Files:**
- Create: `MIMORunning/Views/EffortScaleView.swift`
- Modify: `MIMORunning/Views/ActivityDetailView.swift:216` (호출), `:2657-2720` (StorySection)

- [x] **Step 1: EffortScaleView 작성**

```swift
import SwiftUI

/// 운동 강도 1~10 입력. 10개 가로 막대(파랑→빨강), 4구간 라벨, 출처 배지.
/// - Apple 값만 있으면 읽기 전용 → 배지 탭으로 편집 모드.
/// - 값이 없으면 바로 편집 가능.
struct EffortScaleView: View {
    let resolved: ResolvedEffort?          // 표시 값(내 입력 > Apple)
    let appleValue: Int?                   // 편집 모드에서 표식으로 남기는 Apple 값
    let onSet: (Int) -> Void               // 사용자 값 저장
    let onResetToApple: () -> Void         // 내 입력 삭제(Apple 값으로 되돌리기)

    @State private var editing = false
    @State private var dragValue: Int? = nil

    private var L: AppLanguage { AppLanguage.shared }
    private var shownValue: Int? { dragValue ?? resolved?.value }
    /// 편집 가능: 값 없음 / 내 입력 / 편집 모드 진입
    private var isEditable: Bool { resolved == nil || resolved?.source == .user || editing }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            bars
            bandLabels
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(resolved?.source == .user ? Theme.violet.opacity(0.35) : Color.white.opacity(0.07), lineWidth: 1)
        )
        .onChange(of: resolved) { _, _ in editing = false }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 11))
                .foregroundStyle(resolved != nil ? Theme.violet : .secondary)
            Text(L.s("운동 강도", "Effort"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(resolved != nil ? .white : .secondary)
            Spacer()
            if let v = shownValue {
                Text("\(v) · \(EffortBand(value: v).label)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EffortPalette.color(for: v))
                    .contentTransition(.numericText())
                sourceBadge
            } else {
                Text(L.s("오늘 얼마나 힘들었나요?", "How hard was it?"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        switch resolved?.source {
        case .user:
            HStack(spacing: 6) {
                badge(L.s("내 입력", "Mine"), tint: Theme.violet)
                if appleValue != nil {
                    Button(action: onResetToApple) {
                        Text(L.s("Apple 값으로", "Use Apple"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .appleManual, .appleEstimated:
            Button { editing = true } label: {
                HStack(spacing: 3) {
                    badge(resolved?.source == .appleManual ? L.s("Apple 입력", "Apple") : L.s("Apple 추정", "Apple est."),
                          tint: .secondary)
                    if !editing {
                        Image(systemName: "pencil").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        case nil:
            EmptyView()
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: bars

    private var bars: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 3
            let w = (geo.size.width - spacing * 9) / 10
            HStack(spacing: spacing) {
                ForEach(1...10, id: \.self) { i in
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(EffortPalette.color(for: i).opacity(filled(i) ? 1 : 0.18))
                        if editing, let a = appleValue, a == i {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
                        }
                    }
                    .frame(width: w, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture { if isEditable { commit(i) } }
                    .accessibilityLabel(L.s("강도 \(i)", "Effort \(i)"))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { g in
                        guard isEditable else { return }
                        dragValue = value(atX: g.location.x, width: geo.size.width)
                    }
                    .onEnded { g in
                        guard isEditable else { return }
                        commit(value(atX: g.location.x, width: geo.size.width))
                    }
            )
        }
        .frame(height: 28)
        .opacity(isEditable ? 1 : 0.85)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.s("운동 강도", "Effort"))
        .accessibilityValue(shownValue.map { "\($0)" } ?? "")
        .accessibilityAdjustableAction { dir in
            guard isEditable else { return }
            let cur = shownValue ?? 5
            commit(dir == .increment ? min(10, cur + 1) : max(1, cur - 1))
        }
    }

    private func filled(_ i: Int) -> Bool { (shownValue ?? 0) >= i }

    private func value(atX x: CGFloat, width: CGFloat) -> Int {
        let ratio = min(max(x / max(width, 1), 0), 0.999)
        return Int(ratio * 10) + 1
    }

    private func commit(_ v: Int) {
        dragValue = nil
        editing = false
        onSet(v)
    }

    // MARK: band labels — 구간 폭은 막대 개수 비례(3·3·2·2)

    private var bandLabels: some View {
        GeometryReader { geo in
            let unit = geo.size.width / 10
            HStack(spacing: 0) {
                ForEach(EffortBand.allCases, id: \.self) { band in
                    Text(band.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: unit * CGFloat(band.range.count))
                }
            }
        }
        .frame(height: 12)
    }
}
```

- [x] **Step 2: StorySection에 배치**

`StorySection`에 활동 유형과 Apple 값을 넘긴다. 구조체 선언부(`:2657`) 수정:

```swift
private struct StorySection: View {
    let workoutID: String
    let activityType: ActivityType
    let appleEffort: AppleEffort?
```

`init`을 다음으로 바꾼다:

```swift
    init(workoutID: String, activityType: ActivityType, appleEffort: AppleEffort?) {
        self.workoutID = workoutID
        self.activityType = activityType
        self.appleEffort = appleEffort
        let wid = workoutID
        _stories = Query(filter: #Predicate<WorkoutStory> { $0.workoutID == wid })
        _allOneLinerEntries = Query(filter: #Predicate<OneLinerEntry> { $0.workoutID == wid })
    }
```

`body`의 `VStack` 안, `if !shoes.isEmpty { shoePicker }` 바로 아래에:

```swift
            if activityType == .running {
                EffortScaleView(
                    resolved: EffortResolver.resolve(userValue: story?.effortRPE, apple: appleEffort),
                    appleValue: appleEffort?.effective.map { EffortResolver.clamp($0) },
                    onSet: { setEffort($0) },
                    onResetToApple: { setEffort(nil) }
                )
            }
```

`assignShoe(_:)` 아래에 저장 함수 추가:

```swift
    private func setEffort(_ value: Int?) {
        if let s = story {
            s.effortRPE = value
            s.effortUpdatedAt = value == nil ? nil : Date()
            s.updatedAt = Date()
        } else if let value {
            let s = WorkoutStory(workoutID: workoutID)
            s.effortRPE = value
            s.effortUpdatedAt = Date()
            modelContext.insert(s)
        }
        try? modelContext.save()
    }
```

호출부(`ActivityDetailView.swift:216`)를 바꾼다:

```swift
                    StorySection(workoutID: activity.id.uuidString,
                                 activityType: activity.type,
                                 appleEffort: detail?.appleEffort ?? manager.appleEffort(for: activity.id))
```

- [x] **Step 3: 상세 진입 시 Apple 값 재조회**

`ActivityDetailView`의 `.task` 블록(`:428`) 안, 러닝 경로의 `detail = await manager.fetchDetail(for: activity.id)` 바로 다음 줄에:

```swift
            if let e = await manager.refreshEffort(for: activity.id) { detail?.appleEffort = e }
```

`detail`은 `@State private var detail: ActivityDetail?`이고 `appleEffort`는 `var`이므로 대입 가능.

- [x] **Step 4: 빌드 → 시뮬레이터 확인**

러닝 상세 → 러닝화 피커 아래에 강도 카드. 막대 탭 → 값 저장 → 배지 "내 입력". 걷기 상세에는 카드가 없어야 한다. 값 없음 상태에서 헤더가 "오늘 얼마나 힘들었나요?"인지 확인.

- [x] **Step 5: 커밋**

```bash
git add MIMORunning/Views/EffortScaleView.swift MIMORunning/Views/ActivityDetailView.swift
git commit -m "운동 강도: 10막대 입력 UI(EffortScaleView) · 러닝 상세 스토리 섹션에 배치 · Apple 값 재조회

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 7: EffortBaseline — 개인 기준선

**Files:**
- Create: `MIMORunning/Insight/EffortBaseline.swift`
- Test: `MIMORunningTests/EffortBaselineTests.swift`

- [x] **Step 1: 실패하는 테스트**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("EffortBaseline 개인 기준선")
struct EffortBaselineTests {
    private func s(_ t: WorkoutType, _ e: Int) -> EffortBaseline.Sample { .init(type: t, effort: e) }

    @Test func sameTypeMedianWhenThreeOrMore() {
        let samples = [s(.easy, 4), s(.easy, 6), s(.easy, 5), s(.tempo, 8)]
        #expect(EffortBaseline.median(for: .easy, samples: samples) == 5)
    }

    @Test func fallsBackToAllRunsMedian() {
        let samples = [s(.easy, 4), s(.tempo, 8), s(.longRun, 6)]
        // easy 1건 → 전체 3건 중앙값 6
        #expect(EffortBaseline.median(for: .easy, samples: samples) == 6)
    }

    @Test func nilWhenFewerThanThreeOverall() {
        #expect(EffortBaseline.median(for: .easy, samples: [s(.easy, 4), s(.easy, 5)]) == nil)
        #expect(EffortBaseline.median(for: .easy, samples: []) == nil)
    }

    @Test func samplesExcludeCurrentRunNonRunningAndOldRuns() {
        let cal = Calendar.current
        let now = Date()
        let cur = Activity(id: UUID(), type: .running, date: now, duration: 3000, distance: 8000, calories: nil, avgHeartRate: nil)
        let a = Activity(id: UUID(), type: .running, date: cal.date(byAdding: .day, value: -3, to: now)!, duration: 3000, distance: 8000, calories: nil, avgHeartRate: nil)
        let old = Activity(id: UUID(), type: .running, date: cal.date(byAdding: .day, value: -60, to: now)!, duration: 3000, distance: 8000, calories: nil, avgHeartRate: nil)
        let walk = Activity(id: UUID(), type: .walking, date: cal.date(byAdding: .day, value: -1, to: now)!, duration: 3000, distance: 4000, calories: nil, avgHeartRate: nil)
        let noEffort = Activity(id: UUID(), type: .running, date: cal.date(byAdding: .day, value: -2, to: now)!, duration: 3000, distance: 8000, calories: nil, avgHeartRate: nil)
        let apple = { (v: Double) in AppleEffort(manual: nil, estimated: v, fetchedAt: now) }
        let idx = EffortIndex(user: [cur.id.uuidString: 9],
                              apple: [a.id: apple(4), old.id: apple(8), walk.id: apple(2)])
        let out = EffortBaseline.samples(current: cur, history: [cur, a, old, walk, noEffort], index: idx,
                                         typeOf: { $0 == a.id ? .easy : nil })
        #expect(out.count == 1)
        #expect(out.first?.type == .easy)
        #expect(out.first?.effort == 4)
    }
}
```

- [x] **Step 2: 실패 확인** — `cannot find 'EffortBaseline'`

- [x] **Step 3: 구현**

```swift
import Foundation

/// 개인 기준선 — 최근 8주, 같은 워크아웃 유형의 강도 중앙값. 절대 임계를 쓰지 않는 이유는
/// Apple 추정이 이지런에도 5~6을 주는 경향이 있기 때문(스펙 "결정" 참조).
enum EffortBaseline {
    struct Sample: Equatable {
        let type: WorkoutType
        let effort: Int
    }

    static let minSamples = 3
    static let windowDays = 56

    /// 같은 유형 3건 이상 → 그 중앙값. 미달 → 전체 러닝 3건 이상이면 전체 중앙값. 그것도 미달 → nil.
    static func median(for type: WorkoutType, samples: [Sample]) -> Int? {
        let same = samples.filter { $0.type == type }.map { Double($0.effort) }
        if same.count >= minSamples { return Int(WorkoutTypeClassifier.median(same).rounded()) }
        let all = samples.map { Double($0.effort) }
        if all.count >= minSamples { return Int(WorkoutTypeClassifier.median(all).rounded()) }
        return nil
    }

    /// 현재 런 제외 · 러닝만 · 현재 런 기준 56일 이내 · 강도 있는 것만.
    static func samples(current: Activity,
                        history: [Activity],
                        index: EffortIndex,
                        typeOf: (UUID) -> WorkoutType?) -> [Sample] {
        let cutoff = current.date.addingTimeInterval(-Double(windowDays) * 86_400)
        return history.compactMap { a in
            guard a.id != current.id, a.type == .running,
                  a.date >= cutoff, a.date <= current.date,
                  let e = index.resolve(a.id) else { return nil }
            return Sample(type: typeOf(a.id) ?? .general, effort: e.value)
        }
    }
}
```

`WorkoutTypeClassifier.median(_ values: [Double]) -> Double`은 `Insight/WorkoutTypeClassifier.swift:90`에 이미 있다(빈 배열 → 0).

- [x] **Step 4: 통과 확인** — `EffortBaselineTests` 4 passed

- [x] **Step 5: 커밋**

```bash
git add MIMORunning/Insight/EffortBaseline.swift MIMORunningTests/EffortBaselineTests.swift
git commit -m "운동 강도: EffortBaseline 8주 유형별 중앙값 기준선

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 8: EffortRules — 규칙 A/B/C

**Files:**
- Create: `MIMORunning/Insight/EffortRules.swift`
- Test: `MIMORunningTests/EffortRulesTests.swift`

- [x] **Step 1: 실패하는 테스트**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("EffortRules 라벨 vs 몸 · 더위 · 스플릿")
struct EffortRulesTests {

    private func split(_ id: Int, km: Double = 1.0, pace: Double) -> SplitData {
        SplitData(id: id, distanceM: km * 1000, duration: pace * km, avgHeartRate: nil, avgCadence: nil,
                  avgPower: nil, avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil)
    }
    private func input(effort: Int, source: EffortSource = .user, type: WorkoutType, baseline: Int?,
                       splits: [SplitData] = [], temp: Double? = nil, hum: Double? = nil) -> EffortRuleInput {
        EffortRuleInput(effort: ResolvedEffort(value: effort, source: source), type: type, baseline: baseline,
                        splits: splits, temperatureC: temp, humidityPercent: hum)
    }
    private func badges(_ o: EffortRuleOutput) -> [String] { o.insights.map(\.badge) }

    // A 계열은 하나만
    @Test func easyRunTooHardAgainstBaseline() {
        let o = EffortRules.evaluate(input(effort: 7, type: .easy, baseline: 5))
        #expect(o.insights.count == 1)
        #expect(o.insights[0].tone == .caution)
        #expect(o.insights[0].category == .intensity)
    }

    @Test func easyRunAbsoluteEightWithoutBaselineGap() {
        // baseline 7이면 +2 미달이지만 절대 8 이상 → caution
        let o = EffortRules.evaluate(input(effort: 8, type: .lsd, baseline: 7))
        #expect(o.insights.count == 1)
        #expect(o.insights[0].tone == .caution)
    }

    @Test func noBaselineOnlyAbsoluteRuleFires() {
        #expect(EffortRules.evaluate(input(effort: 7, type: .easy, baseline: nil)).insights.count == 1)
        #expect(EffortRules.evaluate(input(effort: 6, type: .easy, baseline: nil)).insights.isEmpty)
        // baseline 없으면 B·C도 침묵
        let hotFade = input(effort: 9, type: .easy, baseline: nil,
                            splits: [split(1, pace: 360), split(2, pace: 360), split(3, pace: 380), split(4, pace: 380)],
                            temp: 30)
        let o = EffortRules.evaluate(hotFade)
        #expect(o.insights.count == 1)
        #expect(o.replacesEnvironment == false)
    }

    @Test func hardTypeBelowBaselineIsNeutral_andMatchedIsGood() {
        let easyDay = EffortRules.evaluate(input(effort: 5, type: .tempo, baseline: 7))
        #expect(easyDay.insights.count == 1)
        #expect(easyDay.insights[0].tone == .neutral)
        let matched = EffortRules.evaluate(input(effort: 7, type: .tempo, baseline: 7))
        #expect(matched.insights.count == 1)
        #expect(matched.insights[0].tone == .good)
        let general = EffortRules.evaluate(input(effort: 5, type: .general, baseline: 5))
        #expect(general.insights.count == 1)
        #expect(general.insights[0].tone == .good)
    }

    @Test func heatRules() {
        let higher = EffortRules.evaluate(input(effort: 6, type: .general, baseline: 5, temp: 26))
        #expect(higher.replacesEnvironment)
        #expect(higher.insights.contains { $0.category == .environment && $0.tone == .neutral })
        let held = EffortRules.evaluate(input(effort: 5, type: .general, baseline: 5, hum: 80))
        #expect(held.replacesEnvironment)
        #expect(held.insights.contains { $0.category == .environment && $0.tone == .good })
        let mild = EffortRules.evaluate(input(effort: 6, type: .general, baseline: 5, temp: 20, hum: 50))
        #expect(!mild.replacesEnvironment)
        #expect(!mild.insights.contains { $0.category == .environment })
    }

    @Test func secondHalfSlowdownMath() {
        // 전반 360·360, 후반 380·380 → 380/360 − 1 = +5.6%
        let s = [split(1, pace: 360), split(2, pace: 360), split(3, pace: 380), split(4, pace: 380)]
        let v = EffortRules.secondHalfSlowdown(splits: s)!
        #expect(abs(v - 0.0556) < 0.001)
        // 부분 스플릿(1km 미만) 제외 → 3개 남아 nil
        let partial = [split(1, pace: 360), split(2, pace: 360), split(3, pace: 380), split(4, km: 0.4, pace: 380)]
        #expect(EffortRules.secondHalfSlowdown(splits: partial) == nil)
        // 5개(홀수) → 가운데 제외: 전반 1·2, 후반 4·5
        let five = [split(1, pace: 360), split(2, pace: 360), split(3, pace: 900), split(4, pace: 360), split(5, pace: 360)]
        #expect(abs(EffortRules.secondHalfSlowdown(splits: five)!) < 0.0001)
    }

    @Test func splitRulesOnlyForEasyTypesAboveBaseline() {
        let fade = [split(1, pace: 360), split(2, pace: 360), split(3, pace: 380), split(4, pace: 380)]
        let surge = [split(1, pace: 380), split(2, pace: 380), split(3, pace: 360), split(4, pace: 360)]
        let fadeOut = EffortRules.evaluate(input(effort: 6, type: .easy, baseline: 5, splits: fade))
        #expect(fadeOut.insights.contains { $0.category == .intensity && $0.message.contains("초반") })
        let surgeOut = EffortRules.evaluate(input(effort: 6, type: .easy, baseline: 5, splits: surge))
        #expect(surgeOut.insights.contains { $0.message.contains("후반") })
        // 템포는 스플릿 규칙 없음
        let tempo = EffortRules.evaluate(input(effort: 8, type: .tempo, baseline: 7, splits: fade))
        #expect(!tempo.insights.contains { $0.message.contains("초반") })
        // 기준선 이하면 없음
        let calm = EffortRules.evaluate(input(effort: 5, type: .easy, baseline: 5, splits: fade))
        #expect(!calm.insights.contains { $0.message.contains("초반") })
    }

    @Test func atMostThreeInsights() {
        let fade = [split(1, pace: 360), split(2, pace: 360), split(3, pace: 380), split(4, pace: 380)]
        let o = EffortRules.evaluate(input(effort: 8, type: .easy, baseline: 5, splits: fade, temp: 30, hum: 80))
        #expect(o.insights.count == 3)
    }
}
```

- [x] **Step 2: 실패 확인** — `cannot find 'EffortRuleInput'`

- [x] **Step 3: 구현**

```swift
import Foundation

struct EffortRuleInput {
    let effort: ResolvedEffort
    let type: WorkoutType
    let baseline: Int?
    let splits: [SplitData]
    let temperatureC: Double?
    let humidityPercent: Double?
}

struct EffortRuleOutput {
    let insights: [RunInsight]
    /// B/B′가 발화 → 기존 environmentInsight(체감 부담 문장)를 이 결과로 대체.
    let replacesEnvironment: Bool
}

/// 스펙 4.2. 순수 함수. 문장은 최대 3개(A 계열 1 + B 1 + C 1).
enum EffortRules {
    static let splitThreshold = 0.03
    static let hotC = 25.0
    static let humidPct = 75.0
    static let easyTypes: Set<WorkoutType> = [.easy, .lsd]
    static let hardTypes: Set<WorkoutType> = [.tempo, .interval, .race]

    static func evaluate(_ i: EffortRuleInput) -> EffortRuleOutput {
        let L = AppLanguage.shared
        let e = i.effort.value
        var out: [RunInsight] = []
        var replacesEnv = false
        let hl = ["\(e)"]

        // ── A 계열: 하나만 ──
        if easyTypes.contains(i.type) {
            let overBaseline = i.baseline.map { e >= $0 + 2 } ?? (e >= 7)
            if e >= 8 || overBaseline {
                out.append(RunInsight(
                    category: .intensity, tone: .caution, badge: L.s("강도 참고", "Effort Note"),
                    message: L.s("이지런인데 체감 강도가 \(e)이었어요. 이름은 이지여도 몸이 힘들었다면 그날은 이지런이 아니에요.",
                                 "Labeled easy, but effort was \(e)/10. If the body says hard, it wasn't an easy run."),
                    highlights: hl))
            } else if i.baseline != nil {
                out.append(matched(e))
            }
        } else if hardTypes.contains(i.type), let b = i.baseline {
            if e <= b - 2 {
                out.append(RunInsight(
                    category: .intensity, tone: .neutral, badge: L.s("강도 메모", "Effort"),
                    message: L.s("평소 같은 훈련보다 체감이 낮았어요. 여유 있게 소화한 날.",
                                 "Felt easier than your usual for this workout — a comfortable day."),
                    highlights: hl))
            } else {
                out.append(matched(e))
            }
        } else if i.baseline != nil {
            out.append(matched(e))
        }

        // ── B: 더위·습도 (기준선 필요) ──
        if let b = i.baseline {
            let hot   = (i.temperatureC ?? -100) >= hotC
            let humid = (i.humidityPercent ?? -1) >= humidPct
            if hot || humid {
                let header = envHeader(temp: i.temperatureC, hum: i.humidityPercent)
                if e >= b + 1 {
                    out.append(RunInsight(
                        category: .environment, tone: .neutral, badge: L.s("환경", "Conditions"),
                        message: L.s("\(header). 같은 페이스라도 더운 날은 체감이 1~2 높아지는 게 자연스러워요. 페이스보다 강도에 맞춰 뛰는 날.",
                                     "\(header). Same pace feels 1–2 points harder in heat — run to effort, not pace."),
                        highlights: [header]))
                    replacesEnv = true
                } else if e <= b {
                    out.append(RunInsight(
                        category: .environment, tone: .good, badge: L.s("환경", "Conditions"),
                        message: L.s("더운 날인데 체감이 평소 수준이었어요.",
                                     "Hot day, yet effort stayed at your usual level."),
                        highlights: [header]))
                    replacesEnv = true
                }
            }
        }

        // ── C: 스플릿 형태 (이지 유형 + 기준선+1 이상) ──
        if easyTypes.contains(i.type), let b = i.baseline, e >= b + 1,
           let slow = secondHalfSlowdown(splits: i.splits) {
            if slow >= splitThreshold {
                out.append(RunInsight(
                    category: .intensity, tone: .caution, badge: L.s("페이스 배분", "Pacing"),
                    message: L.s("후반이 처지고 체감도 높았어요. 초반 페이스가 목적보다 빨랐을 수 있어요.",
                                 "You faded late and effort ran high — the early pace may have been too quick for the goal."),
                    highlights: [String(format: "%+.0f%%", slow * 100)]))
            } else if slow <= -splitThreshold {
                out.append(RunInsight(
                    category: .intensity, tone: .caution, badge: L.s("페이스 배분", "Pacing"),
                    message: L.s("이지런 후반에 속도를 올리면 회복이라는 목적이 흐려져요.",
                                 "Speeding up late in an easy run blurs its purpose: recovery."),
                    highlights: [String(format: "%+.0f%%", slow * 100)]))
            }
        }

        return EffortRuleOutput(insights: out, replacesEnvironment: replacesEnv)
    }

    private static func matched(_ e: Int) -> RunInsight {
        let L = AppLanguage.shared
        return RunInsight(category: .intensity, tone: .good, badge: L.s("의도에 맞는 강도", "On-Target Effort"),
                          message: L.s("훈련 의도와 체감 강도가 맞았어요.", "Effort matched the intent of the session."),
                          highlights: ["\(e)"])
    }

    private static func envHeader(temp: Double?, hum: Double?) -> String {
        let L = AppLanguage.shared
        var parts: [String] = []
        if let t = temp { parts.append("\(Int(t.rounded()))°C") }
        if let h = hum { parts.append(L.s("습도 \(Int(h.rounded()))%", "\(Int(h.rounded()))% humidity")) }
        return parts.joined(separator: " · ")
    }

    /// (후반 sec/km ÷ 전반 sec/km) − 1. 양수 = 후반 느림. 1km 미만 부분 스플릿 제외, 4개 미만 nil.
    /// 홀수면 가운데 스플릿 제외.
    static func secondHalfSlowdown(splits: [SplitData]) -> Double? {
        let full = splits.filter { $0.distanceM >= 1000 }.sorted { $0.id < $1.id }
        guard full.count >= 4 else { return nil }
        let half = full.count / 2
        let first = Array(full.prefix(half))
        let second = Array(full.suffix(half))
        func pace(_ s: [SplitData]) -> Double {
            let dKm = s.map(\.distanceM).reduce(0, +) / 1000
            let t = s.map(\.duration).reduce(0, +)
            return dKm > 0 ? t / dKm : 0
        }
        let p1 = pace(first), p2 = pace(second)
        guard p1 > 0 else { return nil }
        return p2 / p1 - 1
    }
}
```

`SplitData`(`Models/Activity.swift:198`)는 memberwise init(9개 필드)이며 테스트 헬퍼 `split()`이 그 순서를 따른다.

- [x] **Step 4: 통과 확인** — `EffortRulesTests` 8 passed

- [x] **Step 5: 커밋**

```bash
git add MIMORunning/Insight/EffortRules.swift MIMORunningTests/EffortRulesTests.swift
git commit -m "운동 강도: EffortRules — 라벨 vs 몸 · 더위 · 전후반 스플릿 규칙

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 9: RunInsightEngine·ActivityDetailView 연결 + InsightCard detail

**Files:**
- Modify: `MIMORunning/Insight/RunInsightEngine.swift:362-376` (시그니처), switch 종료 직후
- Modify: `MIMORunning/Views/ActivityDetailView.swift:791-830` (loadInsights), `:1255-1340` (InsightCard)

- [x] **Step 1: 엔진 시그니처 확장**

`static func insights(` 매개변수 목록의 `planWeeklyTargetKm: Double? = nil` 뒤에 추가:

```swift
        planWeeklyTargetKm: Double? = nil,
        effort: ResolvedEffort? = nil,
        effortBaseline: Int? = nil
```

- [x] **Step 2: 규칙 결과 병합**

함수 끝 `return (Array(results.prefix(4)), segSource, fadeKm)`(`:480`) 바로 앞에 넣고, `return`의 상한을 강도 문장 수만큼 늘린다(강도 문장이 유형별 생성기 결과를 밀어내지 않도록):

```swift
        // 운동 강도(RPE) 규칙 — 유형별 생성기와 독립. 앞에 끼워 강도 섹션에서 먼저 보이게 한다.
        var effortCount = 0
        if let effort {
            let ruleOut = EffortRules.evaluate(EffortRuleInput(
                effort: effort, type: workoutType, baseline: effortBaseline,
                splits: detail?.splits ?? [],
                temperatureC: activity.temperatureC, humidityPercent: activity.humidityPercent))
            if ruleOut.replacesEnvironment {
                results.removeAll { $0.category == .environment }
            }
            results.insert(contentsOf: ruleOut.insights, at: 0)
            effortCount = ruleOut.insights.count
        }
        return (Array(results.prefix(4 + effortCount)), segSource, fadeKm)
```

기존 `return (Array(results.prefix(4)), segSource, fadeKm)` 줄은 삭제한다.

- [x] **Step 3: ActivityDetailView — 강도·기준선 계산과 전달**

`ActivityDetailView` 구조체 안(`@State private var runInsights` 근처)에 계산 프로퍼티 추가:

```swift
    /// 이 런의 강도 — 내 입력(panelAllStories) > Apple(detail 캐시 > manager 맵)
    private var resolvedEffort: ResolvedEffort? {
        let story = panelAllStories.first { $0.workoutID == activity.id.uuidString }
        let apple = detail?.appleEffort ?? manager.appleEffort(for: activity.id)
        return EffortResolver.resolve(userValue: story?.effortRPE, apple: apple)
    }

    /// 최근 8주 같은 유형 기준선
    private var effortBaseline: Int? {
        let idx = EffortIndex(stories: panelAllStories, apple: manager.effortMap)
        let samples = EffortBaseline.samples(current: activity, history: manager.activities, index: idx,
                                             typeOf: { [m = manager] id in m.cachedWorkoutTypeForStats(for: id) })
        return EffortBaseline.median(for: detail?.workoutType ?? .general, samples: samples)
    }
```

`loadInsights()`의 `RunInsightEngine.insights(` 호출에 인자 추가(`planWeeklyTargetKm: planWeeklyTargetKm` 뒤):

```swift
            planWeeklyTargetKm: planWeeklyTargetKm,
            effort: activity.type == .running ? resolvedEffort : nil,
            effortBaseline: effortBaseline
```

강도가 바뀌면 재계산 + 매니저 동기화. `ScrollView` 바깥 modifier 체인(`.task { ... }`가 붙은 곳)과 같은 레벨에 추가. 타입체커 시간 초과가 나면 `.task` 블록 바로 앞의 다른 `.onChange`와 묶어 배치한다:

```swift
        .onChange(of: panelAllStories.map(\.effortRPE)) { _, _ in
            manager.syncUserEfforts(from: panelAllStories)
            runInsights = []
            loadInsights()
        }
```

- [x] **Step 4: InsightCard — 악조건 극복 detail에 강도 덧붙임**

`private struct InsightCard: View`(`:1255`)에 프로퍼티 추가:

```swift
    var effortValue: Int? = nil
```

`Text(insight?.detail ?? ...)`(`:1335`)를 다음으로 바꾼다:

```swift
                    Text(displayDetail)
```

같은 구조체에 계산 프로퍼티 추가:

```swift
    private var displayDetail: String {
        guard let ins = insight else { return AppLanguage.shared.s("인사이트 분석 준비 중", "Analyzing…") }
        if ins.theme == .adverseCondition, let e = effortValue {
            return ins.detail + AppLanguage.shared.s(" · 체감 강도 \(e)", " · effort \(e)/10")
        }
        return ins.detail
    }
```

호출부(`ActivityDetailView.swift:212-214`)에 `effortValue: resolvedEffort?.value` 인자 추가:

```swift
                        InsightCard(activity: activity, insight: insight, condition: condition,
                                    confirmedRace: confirmedRaceMatch, hillMatch: hillMatch,
                                    effortValue: resolvedEffort?.value)
```

- [x] **Step 5: 빌드 → 시뮬레이터 확인**

러닝 상세에서 강도를 7로 바꾸면 종합 패널의 인사이트 카드 목록 맨 앞에 강도 문장이 나타나야 한다(기준선이 없으면 이지런 7 이상만). 강도 값을 지우면 문장이 사라진다.

- [x] **Step 6: 커밋**

```bash
git add MIMORunning/Insight/RunInsightEngine.swift MIMORunning/Views/ActivityDetailView.swift
git commit -m "운동 강도: RunInsightEngine에 강도·기준선 입력 병합 · 상세 재계산 · 악조건 극복 detail에 체감 강도

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 10: EffortLoad — sRPE 주간 부하 엔진

**Files:**
- Create: `MIMORunning/Engine/EffortLoad.swift`
- Test: `MIMORunningTests/EffortLoadTests.swift`

- [x] **Step 1: 실패하는 테스트**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("EffortLoad sRPE 주간 부하")
struct EffortLoadTests {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Seoul")!; return c }
    // 2026-09-07 (월) 00:00 KST
    private var monday: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 7))! }
    private func day(_ offset: Int, hour: Int = 7) -> Date { cal.date(byAdding: .hour, value: offset * 24 + hour, to: monday)! }
    private func run(_ dayOffset: Int, min: Double, effort: Int?) -> EffortLoad.Run {
        .init(date: day(dayOffset), durationMin: min, effort: effort)
    }

    @Test func sessionAU() {
        #expect(EffortLoad.sessionAU(effort: 6, durationMin: 50) == 300)
    }

    @Test func mondayStart() {
        // 수요일 → 그 주 월요일
        #expect(EffortLoad.mondayStart(of: day(2), calendar: cal) == monday)
        #expect(EffortLoad.mondayStart(of: monday, calendar: cal) == monday)
    }

    @Test func weeklyTotalsDailyCoverageMean() {
        let runs = [run(0, min: 40, effort: 4), run(0, min: 20, effort: 6),   // 월: 160 + 120
                    run(2, min: 60, effort: nil),                              // 수: 강도 없음
                    run(5, min: 90, effort: 3),                                // 토: 270
                    .init(date: day(7), durationMin: 30, effort: 9)]           // 다음 주 → 제외
        let w = EffortLoad.weekly(runs: runs, weekStart: monday, calendar: cal)!
        #expect(w.total == 550)
        #expect(w.daily == [280, 0, 0, 0, 0, 270, 0])
        #expect(w.runCount == 4)
        #expect(w.coveredCount == 3)
        #expect(abs(w.coverage - 0.75) < 0.0001)
        #expect(abs((w.meanEffort ?? 0) - 13.0 / 3.0) < 0.0001)
        #expect(w.dailyMeanEffort[0] == 5)
        #expect(w.dailyMeanEffort[2] == nil)
    }

    @Test func weeklyNilWhenNoRuns() {
        #expect(EffortLoad.weekly(runs: [], weekStart: monday, calendar: cal) == nil)
        #expect(EffortLoad.weekly(runs: [run(9, min: 30, effort: 5)], weekStart: monday, calendar: cal) == nil)
    }

    @Test func monotony() {
        #expect(EffortLoad.monotony(daily: [100, 100, 100, 100, 100, 100, 100]) == nil)   // sd 0
        let m = EffortLoad.monotony(daily: [200, 0, 200, 0, 200, 0, 200])!
        // mean 114.29, pop sd 98.97 → 1.155
        #expect(abs(m - 1.1547) < 0.001)
    }

    @Test func ratioLabels() {
        #expect(EffortLoad.ratioLabel(0.79) == .low)
        #expect(EffortLoad.ratioLabel(0.8) == .steady)
        #expect(EffortLoad.ratioLabel(1.3) == .steady)
        #expect(EffortLoad.ratioLabel(1.31) == .high)
        #expect(EffortLoad.ratioLabel(1.5) == .high)
        #expect(EffortLoad.ratioLabel(1.51) == .veryHigh)
    }

    private func week(_ total: Double, coverage: Double) -> EffortLoad.WeekLoad {
        let covered = Int((coverage * 4).rounded())
        return .init(weekStart: monday, total: total, daily: [total, 0, 0, 0, 0, 0, 0],
                     dailyMeanEffort: [5, nil, nil, nil, nil, nil, nil],
                     runCount: 4, coveredCount: covered, meanEffort: 5)
    }

    @Test func acuteChronicNeedsThreeCoveredWeeks() {
        let cur = week(1200, coverage: 1)
        #expect(EffortLoad.acuteChronic(current: cur, previous: [week(800, coverage: 1), week(800, coverage: 1)]) == nil)
        let ok = EffortLoad.acuteChronic(current: cur, previous: [week(800, coverage: 1), week(800, coverage: 0.25), week(800, coverage: 1), week(800, coverage: 0.5)])!
        #expect(abs(ok.ratio - 1.5) < 0.0001)
        #expect(ok.label == .high)
        // 이번 주 커버리지 미달
        #expect(EffortLoad.acuteChronic(current: week(1200, coverage: 0.25), previous: [week(800, coverage: 1), week(800, coverage: 1), week(800, coverage: 1)]) == nil)
    }

    @Test func weekOverWeek() {
        #expect(abs(EffortLoad.weekOverWeek(current: week(1180, coverage: 1), previous: week(1000, coverage: 0.5))! - 0.18) < 0.0001)
        #expect(EffortLoad.weekOverWeek(current: week(1180, coverage: 1), previous: week(1000, coverage: 0.25)) == nil)
        #expect(EffortLoad.weekOverWeek(current: week(1180, coverage: 1), previous: nil) == nil)
    }

    @Test func sentenceKindPriority() {
        // 단조도 ≥ 2 & coverage 1 → monotony
        let flat = EffortLoad.WeekLoad(weekStart: monday, total: 700, daily: [100, 100, 100, 100, 100, 100, 110],
                                       dailyMeanEffort: Array(repeating: 5, count: 7), runCount: 7, coveredCount: 7, meanEffort: 5)
        #expect(EffortLoad.sentenceKind(current: flat, previous: [week(300, coverage: 1), week(300, coverage: 1), week(300, coverage: 1)]) == .monotony)
        // 단조도 미달 → 비율 라벨
        let spiky = week(1200, coverage: 1)
        #expect(EffortLoad.sentenceKind(current: spiky, previous: [week(600, coverage: 1), week(600, coverage: 1), week(600, coverage: 1)]) == .veryHigh)
        #expect(EffortLoad.sentenceKind(current: week(600, coverage: 1), previous: [week(600, coverage: 1), week(600, coverage: 1), week(600, coverage: 1)]) == nil)
        #expect(EffortLoad.sentenceKind(current: week(400, coverage: 1), previous: [week(600, coverage: 1), week(600, coverage: 1), week(600, coverage: 1)]) == .low)
    }

    @Test func weeksSeriesOldestToNewest() {
        let runs = [run(-14, min: 30, effort: 5), run(0, min: 30, effort: 5)]
        let ws = EffortLoad.weeks(runs: runs, endingAt: monday, count: 3, calendar: cal)
        #expect(ws.count == 3)
        #expect(ws[0]?.total == 150)
        #expect(ws[1] == nil)
        #expect(ws[2]?.total == 150)
    }

    @Test func recoveryWeekJudgement() {
        #expect(EffortLoad.isRecoveryPhase("회복"))
        #expect(EffortLoad.isRecoveryPhase("테이퍼"))
        #expect(!EffortLoad.isRecoveryPhase("기초"))
        #expect(EffortLoad.recoveryWeekExceeds(meanEffort: 6.2, coverage: 0.6, eightWeekEfforts: [4, 5, 5, 6]))
        #expect(!EffortLoad.recoveryWeekExceeds(meanEffort: 5.9, coverage: 0.6, eightWeekEfforts: [4, 5, 5, 6]))
        #expect(!EffortLoad.recoveryWeekExceeds(meanEffort: 8, coverage: 0.4, eightWeekEfforts: [4, 5, 5]))
        #expect(!EffortLoad.recoveryWeekExceeds(meanEffort: 8, coverage: 1, eightWeekEfforts: [4, 5]))
    }
}
```

- [x] **Step 2: 실패 확인** — `cannot find 'EffortLoad'`

- [x] **Step 3: 구현**

```swift
import Foundation

/// sRPE 부하(Foster 2001: RPE × 분) · 주간 합 · 단조도 · 7일/28일 비교 · 회복 주 판정.
/// 러닝만, 강도 있는 런만 합산. "부상·위험" 표현은 쓰지 않는다(Impellizzeri 2020).
enum EffortLoad {

    struct Run {
        let date: Date
        let durationMin: Double
        let effort: Int?          // nil = 강도 없음 → 부하 미합산, runCount에는 포함
    }

    struct WeekLoad: Equatable {
        let weekStart: Date
        let total: Double                 // AU
        let daily: [Double]               // 월~일 7개, AU
        let dailyMeanEffort: [Double?]    // 월~일 7개, 색상용
        let runCount: Int
        let coveredCount: Int
        let meanEffort: Double?
        var coverage: Double { runCount == 0 ? 0 : Double(coveredCount) / Double(runCount) }
    }

    enum RatioLabel: Equatable { case low, steady, high, veryHigh }
    enum SentenceKind: Equatable { case monotony, low, high, veryHigh }

    static let minCoverage = 0.5
    static let minChronicWeeks = 3
    static let monotonyThreshold = 2.0

    static func sessionAU(effort: Int, durationMin: Double) -> Double {
        Double(effort) * durationMin
    }

    /// 월요일 00:00
    static func mondayStart(of date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.startOfDay(for: cal.date(from: comps) ?? date)
    }

    static func weekly(runs: [Run], weekStart: Date, calendar: Calendar = .current) -> WeekLoad? {
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
        let inWeek = runs.filter { $0.date >= weekStart && $0.date < weekEnd }
        guard !inWeek.isEmpty else { return nil }
        var daily = Array(repeating: 0.0, count: 7)
        var dailyEfforts = Array(repeating: [Int](), count: 7)
        var covered = 0
        var effortSum = 0
        for r in inWeek {
            guard let e = r.effort else { continue }
            let dayIdx = min(6, max(0, calendar.dateComponents([.day], from: weekStart, to: r.date).day ?? 0))
            daily[dayIdx] += sessionAU(effort: e, durationMin: r.durationMin)
            dailyEfforts[dayIdx].append(e)
            covered += 1
            effortSum += e
        }
        let dailyMean: [Double?] = dailyEfforts.map { $0.isEmpty ? nil : Double($0.reduce(0, +)) / Double($0.count) }
        return WeekLoad(weekStart: weekStart,
                        total: daily.reduce(0, +),
                        daily: daily,
                        dailyMeanEffort: dailyMean,
                        runCount: inWeek.count,
                        coveredCount: covered,
                        meanEffort: covered > 0 ? Double(effortSum) / Double(covered) : nil)
    }

    /// count주, 오래된→최신. 마지막 원소가 `endingAt` 주. 러닝 없는 주는 nil.
    static func weeks(runs: [Run], endingAt lastWeekStart: Date, count: Int, calendar: Calendar = .current) -> [WeekLoad?] {
        (0..<count).reversed().map { back in
            guard let ws = calendar.date(byAdding: .day, value: -7 * back, to: lastWeekStart) else { return nil }
            return weekly(runs: runs, weekStart: ws, calendar: calendar)
        }
    }

    /// 평균 ÷ 모표준편차. sd 0이면 nil.
    static func monotony(daily: [Double]) -> Double? {
        guard !daily.isEmpty else { return nil }
        let mean = daily.reduce(0, +) / Double(daily.count)
        let variance = daily.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(daily.count)
        let sd = variance.squareRoot()
        guard sd > 0 else { return nil }
        return mean / sd
    }

    static func ratioLabel(_ ratio: Double) -> RatioLabel {
        if ratio < 0.8 { return .low }
        if ratio <= 1.3 { return .steady }
        if ratio <= 1.5 { return .high }
        return .veryHigh
    }

    /// 이번 주 ÷ 직전 4주 평균. 커버리지 ≥ 0.5인 이전 주가 3개 이상이어야 한다.
    static func acuteChronic(current: WeekLoad, previous: [WeekLoad]) -> (ratio: Double, label: RatioLabel)? {
        guard current.coverage >= minCoverage else { return nil }
        let valid = previous.filter { $0.coverage >= minCoverage }
        guard valid.count >= minChronicWeeks else { return nil }
        let chronic = valid.map(\.total).reduce(0, +) / Double(valid.count)
        guard chronic > 0 else { return nil }
        let r = current.total / chronic
        return (r, ratioLabel(r))
    }

    /// 지난주 대비 증감률. 두 주 모두 커버리지 ≥ 0.5.
    static func weekOverWeek(current: WeekLoad, previous: WeekLoad?) -> Double? {
        guard let p = previous, p.coverage >= minCoverage, current.coverage >= minCoverage, p.total > 0 else { return nil }
        return current.total / p.total - 1
    }

    /// 카드 하단 문장 우선순위: 단조도 → 28일 비교(유지는 침묵) → nil
    static func sentenceKind(current: WeekLoad, previous: [WeekLoad]) -> SentenceKind? {
        if current.coverage >= 1.0, let m = monotony(daily: current.daily), m >= monotonyThreshold {
            return .monotony
        }
        guard let ac = acuteChronic(current: current, previous: previous) else { return nil }
        switch ac.label {
        case .low:      return .low
        case .steady:   return nil
        case .high:     return .high
        case .veryHigh: return .veryHigh
        }
    }

    // MARK: 플래너 연동

    static func isRecoveryPhase(_ phase: String) -> Bool {
        phase == "회복" || phase == "테이퍼"
    }

    /// 이번 주 평균 강도가 최근 8주 강도 중앙값 + 1 이상 (커버리지 ≥ 0.5, 표본 3개 이상)
    static func recoveryWeekExceeds(meanEffort: Double?, coverage: Double, eightWeekEfforts: [Int]) -> Bool {
        guard let mean = meanEffort, coverage >= minCoverage, eightWeekEfforts.count >= 3 else { return false }
        let median = WorkoutTypeClassifier.median(eightWeekEfforts.map(Double.init))
        return mean >= median + 1
    }
}
```

- [x] **Step 4: 통과 확인** — `EffortLoadTests` 11 passed. `weeklyTotalsDailyCoverageMean`의 `dailyMeanEffort[0] == 5`는 `(4+6)/2`.

- [x] **Step 5: 커밋**

```bash
git add MIMORunning/Engine/EffortLoad.swift MIMORunningTests/EffortLoadTests.swift
git commit -m "운동 강도: EffortLoad — sRPE 주간 부하·단조도·7일/28일 비교·회복 주 판정

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 11: 성장 탭 "훈련 강도 부하" 카드

**Files:**
- Create: `MIMORunning/Views/EffortLoadCard.swift`
- Modify: `MIMORunning/Views/GrowthView.swift` — `@Query` 추가(`:93` 근처), body `weeklySection` 아래(`:247`), `.onAppear`(`:262`)

- [x] **Step 1: 카드 뷰**

```swift
import SwiftUI

/// 성장 탭 — 이번 주 sRPE 부하. 일별 막대(색 = 그날 평균 강도), 합계·커버리지, 지난주 대비, 하단 문장 1개.
struct EffortLoadCard: View {
    let current: EffortLoad.WeekLoad
    let previous: [EffortLoad.WeekLoad]     // 직전 4주 중 존재하는 주(오래된→최신)

    private var L: AppLanguage { AppLanguage.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.s("훈련 강도 부하", "Training Load (Effort)"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(L.s("강도 × 시간(분)", "effort × minutes"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            headline
            bars
            if let kind = EffortLoad.sentenceKind(current: current, previous: previous) {
                Text(sentence(kind))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var headline: some View {
        HStack(spacing: 8) {
            Text(L.s("이번 주 \(Int(current.total.rounded())) AU", "This week \(Int(current.total.rounded())) AU"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(L.s("러닝 \(current.runCount)회 중 \(current.coveredCount)회 강도 있음",
                     "\(current.coveredCount) of \(current.runCount) runs rated"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if let delta = EffortLoad.weekOverWeek(current: current, previous: previous.last) {
                Text(String(format: "%@%.0f%%", delta >= 0 ? "+" : "", delta * 100))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(delta >= 0 ? Theme.violet : .secondary)
            }
        }
    }

    private var bars: some View {
        let maxAU = max(current.daily.max() ?? 0, 1)
        let labels = L.isEnglish ? ["M", "T", "W", "T", "F", "S", "S"] : ["월", "화", "수", "목", "금", "토", "일"]
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05))
                        if current.daily[i] > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(EffortPalette.color(for: Int((current.dailyMeanEffort[i] ?? 5).rounded())))
                                .frame(height: max(4, 56 * current.daily[i] / maxAU))
                        }
                    }
                    .frame(height: 56)
                    Text(labels[i])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sentence(_ kind: EffortLoad.SentenceKind) -> String {
        switch kind {
        case .monotony: return L.s("휴식일 없이 비슷한 부하가 이어졌어요. 쉬운 날과 힘든 날을 나눠 보세요.",
                                   "Similar load every day with no rest. Try separating easy and hard days.")
        case .veryHigh: return L.s("최근 4주 평균보다 부하가 많이 높은 주예요.", "A much heavier week than your 4-week average.")
        case .high:     return L.s("평소보다 조금 높은 주예요.", "A slightly heavier week than usual.")
        case .low:      return L.s("회복 쪽으로 기운 주예요.", "A lighter, recovery-leaning week.")
        }
    }
}
```

- [x] **Step 2: GrowthView 연결**

`@Query private var allArchives: [RaceArchive]`(`:93`) 아래에:

```swift
    @Query private var allStories: [WorkoutStory]
```

계산 프로퍼티 추가(`weeklySection` 근처):

```swift
    /// 이번 주 + 직전 4주 sRPE 부하. 이번 주 러닝이 없으면 nil.
    private var effortLoadWeeks: (current: EffortLoad.WeekLoad, previous: [EffortLoad.WeekLoad])? {
        let idx = manager.effortIndex
        let runs = runsCache.map { EffortLoad.Run(date: $0.date, durationMin: $0.duration / 60, effort: idx.resolve($0.id)?.value) }
        let monday = EffortLoad.mondayStart(of: Date())
        let ws = EffortLoad.weeks(runs: runs, endingAt: monday, count: 5)
        guard let cur = ws.last ?? nil else { return nil }
        return (cur, ws.dropLast().compactMap { $0 })
    }
```

body의 `weeklySection` 바로 아래(`paceSection` 위)에:

```swift
                            if let load = effortLoadWeeks {
                                EffortLoadCard(current: load.current, previous: load.previous)
                            }
```

`.onAppear {`(`:262`) 블록 첫 줄에 동기화 추가, 그리고 같은 modifier 체인에 onChange 추가:

```swift
                        manager.syncUserEfforts(from: allStories)
```

```swift
                    .onChange(of: allStories.map(\.effortRPE)) { _, _ in
                        manager.syncUserEfforts(from: allStories)
                    }
```

타입체커 시간 초과가 나면(`GrowthView.swift:242` 주석 참고) onChange를 `MRAdviceCardView()` 뒤가 아닌 `EffortLoadCard` 자체에 붙인다.

- [x] **Step 3: 빌드 → 시뮬레이터**

성장 탭에 주간 거리 아래 카드. 이번 주 러닝이 없으면 카드 없음. 상세에서 강도 입력 후 돌아오면 막대가 갱신되어야 한다.

- [x] **Step 4: 커밋**

```bash
git add MIMORunning/Views/EffortLoadCard.swift MIMORunning/Views/GrowthView.swift
git commit -m "운동 강도: 성장 탭 훈련 강도 부하 카드(일별 AU·커버리지·지난주 대비·단조도/28일 문장)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 12: TrendMetric.easyEffortPace + EffortPaceTrend 관찰 문구

**Files:**
- Create: `MIMORunning/Engine/EffortPaceTrend.swift`
- Test: `MIMORunningTests/EffortPaceTrendTests.swift`
- Modify: `MIMORunning/Models/Activity.swift:300-370`, `MIMORunning/Health/HealthKitManager.swift` (`fetchMetricHistoryFromHealthKit`, `invalidateRunningMetricHistoryCache`, `syncUserEfforts` 주석 해제), `MIMORunning/Views/GrowthView.swift:856,1100,~1465,863`, `MIMORunning/Views/GrowthShareCardView.swift:318`, `MIMORunning/Views/ActivityDetailView.swift:708`

- [x] **Step 1: 실패하는 테스트**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("EffortPaceTrend 같은 강도 페이스 추이")
struct EffortPaceTrendTests {
    /// MRFormShift memberwise init(metric·recentMean·baseMean·delta·mdc·weeksConsistent·r2).
    /// isReal = (|delta| > mdc || weeksConsistent ≥ 4) && isPractical(easyPace 키는 항상 true).
    private func shift(delta: Double, real: Bool) -> MRFormShift {
        MRFormShift(metric: EffortPaceTrend.metric, recentMean: 360 + delta, baseMean: 360, delta: delta,
                    mdc: real ? 1.0 : 999, weeksConsistent: real ? 4 : 0, r2: nil)
    }

    @Test func easyRangeIsTwoToFour() {
        #expect(EffortPaceTrend.easyRange.contains(2))
        #expect(EffortPaceTrend.easyRange.contains(4))
        #expect(!EffortPaceTrend.easyRange.contains(5))
        #expect(!EffortPaceTrend.easyRange.contains(1))
    }

    @Test func residualsPassThrough() {
        let d = Date()
        let r = EffortPaceTrend.residuals(points: [(date: d, value: 360), (date: d.addingTimeInterval(86400), value: 350)])
        #expect(r.count == 2)
        #expect(r[1].value == 350)
    }

    @Test func observationOnlyWhenFaster() {
        let faster = shift(delta: -12, real: true)
        #expect(faster.isReal)
        #expect(EffortPaceTrend.observation(shift: faster)?.text.contains("12") == true)
        #expect(EffortPaceTrend.observation(shift: shift(delta: 12, real: true)) == nil)
        #expect(EffortPaceTrend.observation(shift: shift(delta: -12, real: false)) == nil)
    }

    @Test func formatsPace() {
        #expect(TrendMetric.easyEffortPace.formattedValue(372) == "6'12\" /km")
        #expect(TrendMetric.easyEffortPace.lowerIsBetter)
    }
}
```

- [x] **Step 2: 실패 확인** — `cannot find 'EffortPaceTrend'`

- [x] **Step 3: EffortPaceTrend 구현**

```swift
import Foundation

/// "같은 노력(강도 2~4)으로 더 빨라졌나" — 기존 폼 판정기(mrFormShift: 최근 3개월 vs 이전 3개월, MDC₉₅)를 재사용.
/// 좋아진 쪽(페이스 감소)만 문장을 만든다. 나빠진 쪽은 침묵.
enum EffortPaceTrend {
    static let easyRange = 2...4
    /// higherMeansMoreBounce=true: 값이 높을수록 나쁨(페이스 sec/km)
    static let metric = MRFormMetric(key: "easyPace", label: "쉬운 날 페이스", unit: "s/km", higherMeansMoreBounce: true)

    static func residuals(points: [(date: Date, value: Double)]) -> [MRFormResidual] {
        points.map { MRFormResidual(date: $0.date, value: $0.value) }
    }

    static func observation(shift: MRFormShift) -> (text: String, basis: String)? {
        guard shift.metric.key == metric.key, shift.isReal, shift.delta < 0 else { return nil }
        let L = AppLanguage.shared
        let d = Int((-shift.delta).rounded())
        let text = L.isEnglish
            ? "In runs at effort 2–4, your pace got \(d)s/km faster over 3 months."
            : "강도 2~4로 뛴 러닝의 페이스가 3개월 새 \(d)초 빨라졌어요."
        let basis = String(format: "Δ%+.1fs/km · MDC %.1f · Foster 2001", shift.delta, shift.mdc)
        return (text, basis)
    }
}
```

- [x] **Step 4: TrendMetric 케이스**

`Models/Activity.swift` `enum TrendMetric`:

```swift
    case hrRecovery1   // 운동 후 1분 심박 회복 (bpm) — MRRecovery
    case easyEffortPace   // 강도 2~4 러닝의 페이스 (sec/km) — EffortPaceTrend
```

`koreanLabel`: `case .easyEffortPace: L.s("쉬운 날 페이스", "Easy-Effort Pace")`
`unit`: `case .easyEffortPace: "/km"`
`lowerIsBetter`: `self == .groundContactTime || self == .verticalOscillation || self == .easyEffortPace`
`sparkColor`: `case .easyEffortPace: Theme.pace`
`formattedValue`:

```swift
        case .easyEffortPace:
            let s = Int(val.rounded())
            return "\(s / 60)'\(String(format: "%02d", s % 60))\" \(unit)"
```

- [x] **Step 5: 나머지 exhaustive switch**

- `Views/GrowthShareCardView.swift:318` switch에 `case .easyEffortPace: return "\(sign)\(Int(absChange.rounded()))s \(arrow)"`
- `Views/ActivityDetailView.swift:708` `currentValue(for:)`에 `case .easyEffortPace: return nil`
- 빌드 시 컴파일러가 알려주는 다른 `switch metric` 비완전 지점에도 같은 의미로 케이스를 추가한다(라벨은 `koreanLabel`, 값 포맷은 `formattedValue`를 그대로 쓰는 곳은 수정 불필요).

- [x] **Step 6: HealthKitManager 히스토리**

`fetchMetricHistoryFromHealthKit(_:from:usePounds:)`의 `case .hrRecovery1:` 아래에:

```swift
        case .easyEffortPace:
            return easyEffortPaceHistory(from: startDate)
```

`// MARK: - Workout Effort (iOS 18)` 섹션에 추가:

```swift
    /// 강도 2~4(내 입력 > Apple)로 뛴 러닝의 페이스(sec/km) 시계열 — HealthKit 조회 없음, activities 기반.
    func easyEffortPaceHistory(from startDate: Date) -> [(date: Date, value: Double)] {
        loadEffortMapIfNeeded()
        let idx = effortIndex
        return activities
            .filter { $0.type == .running && $0.date >= startDate && $0.distance >= 1000 && $0.duration > 0 }
            .compactMap { a -> (date: Date, value: Double)? in
                guard let e = idx.resolve(a.id), EffortPaceTrend.easyRange.contains(e.value) else { return nil }
                return (a.date, a.duration / (a.distance / 1000))
            }
            .sorted { $0.date < $1.date }
    }
```

`invalidateRunningMetricHistoryCache()`의 `runningMetrics` 배열에 `.easyEffortPace` 추가. `syncUserEfforts`의 주석 처리한 마지막 줄(`metricHistoryCacheURL(.easyEffortPace ...)` 삭제)을 활성화한다.

- [x] **Step 7: GrowthView**

`:856`과 `:1100`의 `runningMetrics` 배열 끝에 `.easyEffortPace` 추가.

`@State private var recoveryObservation` 아래에:

```swift
    /// 같은 강도(2~4) 페이스 추이 관찰 — 빨라진 쪽만 (EffortPaceTrend.observation)
    @State private var effortPaceObservation: (text: String, basis: String)? = nil
```

회복 관찰 계산 블록(`:1464` `let hist = await manager.fetchRecoveryHistory(...)` 앞)에:

```swift
        // 같은 강도 페이스 추이 — 강도 2~4 러닝의 페이스를 폼 판정기(3개월 vs 3개월, MDC)로 본다
        let easyPts = await manager.fetchMetricHistory(.easyEffortPace, from: oneYearAgo)
        if let shift = mrFormShift(EffortPaceTrend.residuals(points: easyPts), metric: EffortPaceTrend.metric, asOf: Date()),
           let o = EffortPaceTrend.observation(shift: shift) {
            effortPaceObservation = o
        }
```

`metricTrendsSection`(`:863`) `if let rec = recoveryObservation { ... }` 아래에:

```swift
            if let ep = effortPaceObservation {
                MRFormObservationCard(text: ep.text, basis: ep.basis, isStable: true,
                                      title: L.s("쉬운 날 페이스", "Easy-Effort Pace"),
                                      icon: "gauge.with.dots.needle.33percent")
            }
```

- [x] **Step 8: 빌드 + 테스트**

빌드 → `BUILD SUCCEEDED`. `EffortPaceTrendTests` 4 passed. 성장 탭 "주간 지표 추세" 그리드에 "쉬운 날 페이스" 스파크 카드가 생긴다(데이터 없으면 기존 빈 상태 표시).

- [x] **Step 9: 커밋**

```bash
git add MIMORunning/Engine/EffortPaceTrend.swift MIMORunningTests/EffortPaceTrendTests.swift \
  MIMORunning/Models/Activity.swift MIMORunning/Health/HealthKitManager.swift \
  MIMORunning/Views/GrowthView.swift MIMORunning/Views/GrowthShareCardView.swift MIMORunning/Views/ActivityDetailView.swift
git commit -m "운동 강도: TrendMetric.easyEffortPace 스파크 카드 · 같은 강도 페이스 추이 관찰 문구(EffortPaceTrend)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 13: 훈련 계획 플래너 — 회복 주 문장

**Files:**
- Modify: `MIMORunning/Views/MRRacePlanView.swift` — `MRRacePlanCard`(`:53-60`, `:272`), `MRWeekTable`(`:295-301`, `:599` 근처, `:704` 근처), `MRRacePlanSection`(`:889`, `:915`)
- Modify: `MIMORunning/Views/MeView.swift:27`, `:215`

- [x] **Step 1: MeView에서 문장 계산·동기화**

`MeView`에 `@Query private var allStories: [WorkoutStory]`가 없으면 추가(`SwiftData` import 있음). 계산 프로퍼티:

```swift
    /// 회복·테이퍼 주에 평균 강도가 평소보다 높을 때 플래너에 보이는 한 줄. 단계 판정은 MRWeekTable이 한다.
    private var recoveryEffortNote: String? {
        let idx = manager.effortIndex
        let runs = manager.activities.filter { $0.type == .running }
        let monday = EffortLoad.mondayStart(of: Date())
        let loadRuns = runs.map { EffortLoad.Run(date: $0.date, durationMin: $0.duration / 60, effort: idx.resolve($0.id)?.value) }
        guard let cur = EffortLoad.weekly(runs: loadRuns, weekStart: monday) else { return nil }
        let eightWeeksAgo = monday.addingTimeInterval(-56 * 86_400)
        let past = runs.filter { $0.date >= eightWeeksAgo && $0.date < monday }.compactMap { idx.resolve($0.id)?.value }
        guard EffortLoad.recoveryWeekExceeds(meanEffort: cur.meanEffort, coverage: cur.coverage, eightWeekEfforts: past) else { return nil }
        return AppLanguage.shared.s("회복 주인데 평균 강도가 평소보다 높아요.", "Recovery week, but your average effort is above usual.")
    }
```

호출부(`:215`):

```swift
                        MRRacePlanSection(recoveryEffortNote: recoveryEffortNote)
```

MeView 최상위 modifier 체인에 동기화 추가:

```swift
        .onAppear { manager.syncUserEfforts(from: allStories) }
```

- [x] **Step 2: MRRacePlanSection → MRRacePlanCard → MRWeekTable 전달**

`MRRacePlanSection`(`:889`)에 `var recoveryEffortNote: String? = nil` 추가. `:915`의 `MRRacePlanCard(check: c, isExpanded: isExpanded, runs: engine.runs, snapshot: snapshot(for: c))`에 `recoveryEffortNote: recoveryEffortNote` 인자 추가(trailing closure 앞).

`MRRacePlanCard`(`:53`)에 `var recoveryEffortNote: String? = nil` 추가(`onToggleCollapse` 앞). `:272`의 `MRWeekTable(...)` 호출에 `recoveryEffortNote: recoveryEffortNote` 추가.

`MRWeekTable`(`:295`)에 `var recoveryEffortNote: String? = nil` 추가.

- [x] **Step 3: 주 행에 표시**

라이브 플랜 분기 — `if !w.breakdown.isEmpty { Text(localizedBreakdown(w.breakdown)) ... }`(`:704-708`) 바로 아래:

```swift
                                if isCurrent(w), EffortLoad.isRecoveryPhase(w.phase), let note = recoveryEffortNote {
                                    Text(note)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(hex: "FFD166"))
                                }
```

스냅샷 분기 — `let bd = breakdownForSnap(snap); if !bd.isEmpty { ... }`(`:599`) 블록 바로 아래:

```swift
                                if isCurr, EffortLoad.isRecoveryPhase(snap.phase), let note = recoveryEffortNote {
                                    Text(note)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(hex: "FFD166"))
                                }
```

`MRPlanWeekSummary`에 `phase`가 있는지 확인(`:445`에서 `snapshotWeeks.map(\.phase)`로 이미 사용 중이므로 존재).

- [x] **Step 4: 빌드 → 확인**

나 탭 → 대회 계획 → 이번 주가 회복/테이퍼 단계이고 조건이 맞을 때만 노란 한 줄. 프리뷰(`:1048`, `:1055`)는 기본값 nil로 컴파일된다.

- [x] **Step 5: 커밋**

```bash
git add MIMORunning/Views/MRRacePlanView.swift MIMORunning/Views/MeView.swift
git commit -m "운동 강도: 훈련 계획 회복·테이퍼 주에 평균 강도 초과 문장

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 14: 전체 테스트·FEATURES.md·마무리

**Files:**
- Modify: `FEATURES.md`

- [x] **Step 1: 전체 테스트**

```bash
xcodebuild test -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E 'Test Suite|passed|failed|error:' | tail -40
```

Expected: 새 스위트 6개 포함 전부 passed, 기존 스위트 회귀 없음.

- [x] **Step 2: 수동 시나리오 점검(시뮬레이터 또는 실기기)**

1. 러닝 상세: 강도 카드 위치(러닝화 아래) · 탭/드래그 · 배지 전환 · "Apple 값으로" 되돌리기 · 걷기 상세에는 없음.
2. 상세 인사이트: 강도 7 입력 후 강도 문장 등장, 삭제 후 사라짐.
3. 성장 탭: 부하 카드 · 스파크 카드 "쉬운 날 페이스".
4. 나 탭 플래너: 회복 주 문장(조건 맞을 때).
5. iOS 17 시뮬레이터(있으면): Apple 값 없이 입력만 동작, 크래시 없음.

- [x] **Step 3: FEATURES.md 갱신**

기존 항목 형식을 따라 "운동 강도(RPE)" 절을 추가한다: Apple 값 읽기(iOS 18) · 앱 내 입력(러닝만, 10막대) · 우선순위(내 입력 > Apple 수동 > Apple 추정) · 상세 인사이트 3종(개인 8주 기준선) · 성장 탭 sRPE 부하 카드(커버리지 50%·유효 3주 규칙) · 쉬운 날 페이스 추이 · 플래너 회복 주 문장 · 하지 않는 것(HealthKit 쓰기·심박 추정·공유 카드).

- [x] **Step 4: 커밋**

```bash
git add FEATURES.md
git commit -m "FEATURES: 운동 강도(RPE) — Apple 읽기·앱 입력·개인 기준선 인사이트·sRPE 주간 부하·쉬운 날 페이스·회복 주 문장

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## 스펙 커버리지 체크

| 스펙 | 태스크 |
|---|---|
| 1.1 WorkoutStory 필드 | 2 |
| 1.2 ActivityDetail.appleEffort | 4 |
| 1.3 EffortResolver | 1 |
| 2 HealthKit 읽기·관계 쿼리·앵커 캐시·갱신 시점 | 5, 6(Step 3) |
| 3 EffortScaleView 전체 | 6 |
| 4.1 EffortBaseline | 7 |
| 4.2 EffortRules 규칙표 | 8 |
| 4.3 배치(엔진 병합·환경 대체·이겨낸 러닝 detail) | 9 |
| 5.1 EffortLoad | 10 |
| 5.2 성장 탭 카드 | 11 |
| 5.3 플래너 | 13 |
| 5.4 같은 강도 페이스 추이 | 12 |
| 6 상태·오류(권한·iOS 17·쿼리 실패 침묵) | 5(`#available`, 실패 시 캐시 유지), 6 |
| 7 테스트 | 1, 3, 7, 8, 10, 12 |
