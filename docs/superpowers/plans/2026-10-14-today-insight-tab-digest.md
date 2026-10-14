# 오늘의 인사이트 탭 요약 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 상세 화면 맨 위 "오늘의 인사이트" 카드에 리듬·폼·퍼포먼스 탭의 결론(문제 최대 2 + 방향 1, 문제 없으면 좋은 신호 1)을 블록으로 보여 준다.

**Architecture:** 각 탭 카드의 판정 문장을 뷰 private에서 static 함수로 옮겨 카드와 요약이 **같은 함수**를 부르게 한다. 탭별 "신호 수집기"가 `[TabDigest.Signal]`을 만들고, 순수 조합기 `TabDigest.make`가 신호 묶음 소유·우선순위·방향 중복 제거를 해 `[TabDigest.Block]`을 낸다. 화면은 RunHeadline 제목 + 블록.

**Tech Stack:** Swift 6 / SwiftUI / XCTest, Xcode 26.3, iOS 17+.

**Spec:** `docs/superpowers/specs/2026-10-14-today-insight-tab-digest-design.md` (권장안 확정: 좋은 신호만 있는 탭도 1줄 · 맨 위 fact·next 줄 제거 · 공유 이미지·대회 탭은 범위 밖)

## Global Constraints

- **새 판정 금지** — 문장은 카드가 쓰는 함수의 반환값 그대로. 카드 문장이 바뀌면 안 된다(추출은 동작 보존 리팩터).
- 모든 사용자 문장은 `AppLanguage.shared.s(ko, en, ja:)` 3개 언어. 말투 합쇼체, 해석·칭찬 대신 사실. 진행률·달성률 표현 금지.
- 공유 작업 트리: 다른 세션이 같은 브랜치(crew)에 커밋한다. `git add -A`·`git add .`·`git stash` 금지, **경로 명시** 커밋, 커밋 뒤 `git show --stat HEAD` 확인. `MIMORunning.xcodeproj/project.pbxproj`는 남의 변경이 있으니 새 파일 추가가 필요할 때만 그 hunk만 넣는다(프로젝트가 폴더 동기화면 pbxproj 수정 불필요 — 먼저 확인).
- 빌드: `xcodebuild -project MIMORunning.xcodeproj -scheme MIMORunning -destination 'generic/platform=iOS' -derivedDataPath <scratch>/dd build CODE_SIGNING_ALLOWED=NO`
- **테스트 실행 금지(사용자 규칙: 시뮬레이터 금지)** — 검증은 `xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratch>/dd CODE_SIGNING_ALLOWED=NO` → `** TEST BUILD SUCCEEDED **` 까지. TDD는 "테스트를 먼저 쓰고 컴파일이 기대대로 깨지는 것을 본다 → 구현 → TEST BUILD SUCCEEDED". `xcodebuild test`·시뮬레이터 부팅 금지. 병렬 시 각자 다른 `-derivedDataPath`.
- 프로젝트는 폴더 동기화(objectVersion 77, PBXFileSystemSynchronized) — 새 파일 추가에 pbxproj 수정 불필요. pbxproj는 커밋하지 말 것(남의 변경).
- 기존 실패 테스트 `MRFormTests/testFormObservationNeedsTwoAgreeingMetrics`는 이 작업 이전부터 실패 — 무시.
- 실기기 설치·캡처는 사용자가 한다. 컴파일·테스트·커밋까지만.

## Review Focus

1. **워치 없는 러닝**(심박·폼 없음) — 블록이 0~1개여야 하고 빈 블록(라벨만)이 보이면 안 된다. → Task 2 테스트 `testEmptyTabsAreOmitted`.
2. **같은 후반 심박 신호가 리듬·퍼포먼스 둘 다에 나옴** — 디커플링이 있으면 퍼포먼스만. → Task 2 `testLateHRFamilyOwnedByPerformanceWhenPresent`.
3. **방향 문장 중복**(훈련부하 next가 리듬·퍼포먼스 둘 다) — 뒤 블록에서 빠져야 한다. → Task 2 `testDuplicateDirectionDroppedInLaterBlock`.
4. **인터벌 러닝** — 폼 블록은 IntervalFatigueCard 해석+권고 한 쌍만. → Task 4 `testIntervalUsesFatigueCardPair`.
5. **템포·롱런의 카디악 드리프트가 '같은 페이스 심박 낮음'으로 표시** — 효율 비교만 받아야 한다. → Task 1 테스트.

---

## File Structure

| 파일 | 책임 |
|---|---|
| `MIMORunning/Insight/TabDigest.swift` (신규) | 모델(`Tab`·`Family`·`Signal`·`Block`) + 순수 조합기 `make` |
| `MIMORunning/Insight/TabDigestRhythm.swift` (신규) | 리듬 신호 수집 + 리듬 카드에서 옮긴 static 판정(존 캡션·심박 캡션·페이스 모양) |
| `MIMORunning/Insight/TabDigestForm.swift` (신규) | 폼 신호 수집 + 폼 카드에서 옮긴 static 판정(narrative·B1·B7) + 인터벌 해석/권고 |
| `MIMORunning/Insight/TabDigestPerformance.swift` (신규) | 퍼포먼스 신호 수집 + 옮긴 static 판정(디커플링·7일 부하 문구·이지 경고·복귀) |
| `MIMORunning/Insight/RunInsightEngine.swift` | `RunInsight.source` 추가(결함 수정) |
| `MIMORunning/Views/RunInsightTabCard.swift`, `RunFormCardView.swift`, `IntervalFatigueCard.swift` | private 판정 → 위 static 호출로 교체(문장 동일) |
| `MIMORunning/Views/ActivityDetailView.swift` | digest 계산·`InsightCard`에 블록 렌더·탭 이동, fact·next 줄 제거 |
| `MIMORunningTests/TabDigestTests.swift` 외 (신규) | 조합기·수집기·추출 회귀 테스트 |

---

### Task 1: 효율 인사이트 오분류 수정

**Files:**
- Modify: `MIMORunning/Insight/RunInsightEngine.swift:20-27` (RunInsight), `:1400` (efficiencyInsight 반환부)
- Modify: `MIMORunning/Views/ActivityDetailView.swift:274`, `MIMORunning/Views/RunInsightTabCard.swift` `heroContext`(≈3575)
- Test: `MIMORunningTests/EfficiencyInsightSourceTests.swift` (신규)

**Interfaces:**
- Produces: `RunInsight.source: RunInsight.Source` (`.efficiencyComparison`, `.other`, 기본 `.other`), `static func RunInsight.efficiencyComparison(in: [RunInsight]) -> RunInsight?`

- [ ] **Step 1: 실패 테스트**

```swift
import XCTest
@testable import MIMORunning

final class EfficiencyInsightSourceTests: XCTestCase {
    func testDriftWithEfficiencyCategoryIsNotComparison() {
        let drift = RunInsight(category: .efficiency, tone: .good, badge: "", message: "전반/후반 심박 차이 4bpm", highlights: ["4bpm"])
        let comp = RunInsight(category: .efficiency, tone: .good, badge: "", message: "…심박이 6bpm 낮았습니다.", highlights: ["6bpm"],
                              source: .efficiencyComparison)
        XCTAssertNil(RunInsight.efficiencyComparison(in: [drift]))
        XCTAssertEqual(RunInsight.efficiencyComparison(in: [drift, comp])?.highlights, ["6bpm"])
    }
}
```

- [ ] **Step 2: build-for-testing → 컴파일 실패 확인** (`source` 없음)

- [ ] **Step 3: 구현**

```swift
struct RunInsight: Identifiable {
    enum Source: Equatable { case efficiencyComparison, other }
    let id = UUID()
    let category: InsightCategory
    let tone: InsightTone
    let badge: String
    let message: String
    let highlights: [String]
    /// 같은 `.efficiency` 카테고리라도 카디악 드리프트는 '같은 페이스 비교'가 아니다 — 요약·히어로는 비교만 받는다.
    var source: Source = .other

    static func efficiencyComparison(in list: [RunInsight]) -> RunInsight? {
        list.first { $0.source == .efficiencyComparison }
    }
}
```
`efficiencyInsight`가 `RunInsight(...)`를 만드는 모든 return 지점에 `source: .efficiencyComparison` 추가.
`ActivityDetailView.swift:274` → `let eff = RunInsight.efficiencyComparison(in: runInsights)`.
`heroContext`의 `insights.first { $0.category == .efficiency ... }` → `RunInsight.efficiencyComparison(in: insights)` 후 tone `.good` 확인.
`RunHeadline.candidates`의 `e.category == .efficiency` 조건은 유지(입력이 이미 비교만).

- [ ] **Step 4: TEST BUILD SUCCEEDED 확인**
- [ ] **Step 5: 커밋** `git add MIMORunning/Insight/RunInsightEngine.swift MIMORunning/Views/ActivityDetailView.swift MIMORunning/Views/RunInsightTabCard.swift MIMORunningTests/EfficiencyInsightSourceTests.swift` → "효율 인사이트 출처 구분 — 카디악 드리프트가 '같은 페이스 심박 낮음'으로 뜨던 결함"

---

### Task 2: TabDigest 모델 + 조합기

**Files:**
- Create: `MIMORunning/Insight/TabDigest.swift`
- Test: `MIMORunningTests/TabDigestTests.swift`

**Interfaces:**
- Produces (이후 모든 Task가 사용):

```swift
enum TabDigest {
    enum Tab: Int, CaseIterable, Comparable { case rhythm, form, performance
        static func < (a: Tab, b: Tab) -> Bool { a.rawValue < b.rawValue } }
    enum Kind: Equatable { case problem, good, extra }
    enum Tone: Equatable { case caution, good, neutral }
    /// 같은 사실을 여러 카드가 말하는 신호 묶음 — 묶음마다 소유 탭은 하나
    enum Family: Equatable { case lateHR, latePace, load, distanceRank, efficiency, unique
        /// 앞쪽 탭부터 신호가 있으면 그 탭이 소유
        var ownerOrder: [Tab] {
            switch self {
            case .lateHR:       return [.performance, .rhythm]
            case .latePace:     return [.form, .rhythm, .performance]
            case .load:         return [.performance, .rhythm, .form]
            case .distanceRank: return [.rhythm, .performance]
            case .efficiency:   return [.performance]
            case .unique:       return Tab.allCases
            }
        }
    }
    struct Signal: Equatable {
        let tab: Tab
        let kind: Kind
        /// 같은 탭·같은 kind 안에서 작을수록 먼저 (설계 §4 표의 순서 번호)
        let priority: Int
        let family: Family
        let text: String
        var tone: Tone = .neutral
        /// 이 문제/신호의 짝 권고 — 없으면 nil
        var direction: String? = nil
    }
    /// 탭마다 문제 없을 때 쓰는 기본 방향(설계 §4 각 '기본 방향')
    struct Defaults: Equatable { var directions: [Tab: String] = [:] }
    struct Statement: Equatable { let text: String; let tone: Tone }
    struct Block: Equatable { let tab: Tab; let statements: [Statement]; let direction: String? }

    static func make(_ signals: [Signal], defaults: Defaults = .init()) -> [Block]
}
```

규칙(`make`):
1. 소유: `family != .unique`인 신호는 `ownerOrder`에서 그 family 신호가 존재하는 첫 탭의 것만 남긴다.
2. 탭별(Tab 순서): problems = kind==.problem을 priority 오름차순, **최대 2**. problems가 비면 goods 중 priority 최소 **1**. extras(kind==.extra) priority 최소 **1**을 끝에 추가.
3. direction = 채택된 첫 problem의 direction → 없으면 채택된 good의 direction → 없으면 `defaults.directions[tab]`.
4. 앞 블록이 이미 쓴 direction 문자열이면 nil로.
5. statements가 비면 블록 생략(방향만 있는 블록 금지).

- [ ] **Step 1: 실패 테스트**

```swift
import XCTest
@testable import MIMORunning

final class TabDigestTests: XCTestCase {
    typealias S = TabDigest.Signal
    func testProblemsCappedAtTwoAndGoodSuppressed() {
        let b = TabDigest.make([
            S(tab: .rhythm, kind: .problem, priority: 3, family: .unique, text: "c", tone: .caution),
            S(tab: .rhythm, kind: .problem, priority: 1, family: .unique, text: "a", tone: .caution, direction: "da"),
            S(tab: .rhythm, kind: .problem, priority: 2, family: .unique, text: "b", tone: .caution),
            S(tab: .rhythm, kind: .good, priority: 1, family: .unique, text: "g", tone: .good),
        ])
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b[0].statements.map(\.text), ["a", "b"])
        XCTAssertEqual(b[0].direction, "da")
    }
    func testGoodOnlyTabShowsOneLine() {
        let b = TabDigest.make([
            S(tab: .form, kind: .good, priority: 2, family: .unique, text: "g2", tone: .good),
            S(tab: .form, kind: .good, priority: 1, family: .unique, text: "g1", tone: .good),
        ], defaults: .init(directions: [.form: "df"]))
        XCTAssertEqual(b.first?.statements.map(\.text), ["g1"])
        XCTAssertEqual(b.first?.direction, "df")
    }
    func testEmptyTabsAreOmitted() {
        let b = TabDigest.make([S(tab: .rhythm, kind: .good, priority: 1, family: .unique, text: "g", tone: .good)],
                               defaults: .init(directions: [.form: "df", .performance: "dp"]))
        XCTAssertEqual(b.map(\.tab), [.rhythm])
    }
    func testLateHRFamilyOwnedByPerformanceWhenPresent() {
        let b = TabDigest.make([
            S(tab: .rhythm, kind: .problem, priority: 4, family: .lateHR, text: "후반에 심박이 올랐습니다", tone: .caution),
            S(tab: .performance, kind: .problem, priority: 3, family: .lateHR, text: "디커플링", tone: .caution),
        ])
        XCTAssertEqual(b.map(\.tab), [.performance])
    }
    func testLateHRFallsBackToRhythm() {
        let b = TabDigest.make([S(tab: .rhythm, kind: .problem, priority: 4, family: .lateHR, text: "r", tone: .caution)])
        XCTAssertEqual(b.map(\.tab), [.rhythm])
    }
    func testDuplicateDirectionDroppedInLaterBlock() {
        let b = TabDigest.make([
            S(tab: .rhythm, kind: .problem, priority: 1, family: .unique, text: "r", tone: .caution, direction: "쉬세요"),
            S(tab: .performance, kind: .problem, priority: 2, family: .unique, text: "p", tone: .caution, direction: "쉬세요"),
        ])
        XCTAssertEqual(b[0].direction, "쉬세요")
        XCTAssertNil(b[1].direction)
    }
    func testExtraAppendedAfterStatements() {
        let b = TabDigest.make([
            S(tab: .form, kind: .good, priority: 1, family: .unique, text: "held", tone: .good),
            S(tab: .form, kind: .extra, priority: 1, family: .unique, text: "trend"),
        ])
        XCTAssertEqual(b[0].statements.map(\.text), ["held", "trend"])
    }
    func testBlocksInTabOrder() {
        let b = TabDigest.make([
            S(tab: .performance, kind: .good, priority: 1, family: .unique, text: "p", tone: .good),
            S(tab: .rhythm, kind: .good, priority: 1, family: .unique, text: "r", tone: .good),
            S(tab: .form, kind: .good, priority: 1, family: .unique, text: "f", tone: .good),
        ])
        XCTAssertEqual(b.map(\.tab), [.rhythm, .form, .performance])
    }
}
```

- [ ] **Step 2: build-for-testing → 컴파일 실패 확인**
- [ ] **Step 3: 구현** — 위 Interfaces 그대로 + `make`:

```swift
static func make(_ signals: [Signal], defaults: Defaults = .init()) -> [Block] {
    let owned = signals.filter { s in
        guard s.family != .unique else { return true }
        let owner = s.family.ownerOrder.first { t in signals.contains { $0.family == s.family && $0.tab == t } }
        return owner == s.tab
    }
    var used = Set<String>()
    var out: [Block] = []
    for tab in Tab.allCases {
        let mine = owned.filter { $0.tab == tab }
        let problems = Array(mine.filter { $0.kind == .problem }.sorted { $0.priority < $1.priority }.prefix(2))
        let good = problems.isEmpty ? mine.filter { $0.kind == .good }.min { $0.priority < $1.priority } : nil
        let extra = mine.filter { $0.kind == .extra }.min { $0.priority < $1.priority }
        let chosen = problems + [good, extra].compactMap { $0 }
        guard !chosen.isEmpty else { continue }
        var dir = problems.first?.direction ?? good?.direction ?? defaults.directions[tab]
        if let d = dir, used.contains(d) { dir = nil }
        if let d = dir { used.insert(d) }
        out.append(Block(tab: tab, statements: chosen.map { Statement(text: $0.text, tone: $0.tone) }, direction: dir))
    }
    return out
}
```
- [ ] **Step 4: TEST BUILD SUCCEEDED 확인**
- [ ] **Step 5: 커밋** (TabDigest.swift, TabDigestTests.swift)

---

### Task 3: 리듬 신호 수집기 (+ 리듬 카드 판정 추출)

**Files:**
- Create: `MIMORunning/Insight/TabDigestRhythm.swift`
- Modify: `MIMORunning/Views/RunInsightTabCard.swift` — `RhythmInsightCard`의 `zoneVerdictLabel`(≈2673), `buildWorkoutTypeFormParts`의 거리주·일반 페이스 분기(≈2425-2510: C11~C17), 이지 분기(≈2530-2545: C18~C20)
- Test: `MIMORunningTests/TabDigestRhythmTests.swift`

**Interfaces:**
- Consumes: `TabDigest.Signal`, `RunSummaryInput`, `[RunSummaryLine]`, `RunSummaryBuilder.Context`
- Produces:

```swift
enum TabDigestRhythm {
    /// 카드와 요약이 함께 쓰는 판정 — 문장 + 톤(카드는 톤을 색으로 바꿔 쓴다)
    struct Verdict: Equatable { let text: String; let isProblem: Bool }
    /// 존 도넛 캡션(옮김: zoneVerdictLabel). heatSuffix는 카드가 붙이던 그대로 인자로.
    static func zoneVerdict(fractions: [Int: Double], workoutType: WorkoutType, heatSuffix: String?) -> Verdict?
    /// 이지 분기 C18~C20 (Z1~2 비율)
    static func easyVerdict(lowZoneFraction: Double) -> Verdict
    /// 거리주·일반 페이스 분기 C11~C17 — splits에서 전후반·CV 판정
    static func paceShapeVerdict(splits: [SplitData], workoutType: WorkoutType) -> Verdict?
    static func signals(context: RunSummaryBuilder.Context, input: RunSummaryInput, lines: [RunSummaryLine]) -> [TabDigest.Signal]
    static func defaultDirection(lines: [RunSummaryLine]) -> String?   // 거리 적응 줄 next
}
```

추출 규칙: 카드의 private 함수 본문을 **그대로** 옮기고 Color 반환은 `isProblem`으로 바꾼다(카드는 `isProblem ? 노랑 : 초록`처럼 원래 색 규칙으로 되돌린다 — 원래 색 매핑을 카드 쪽에 남길 것). 카드는 이 static을 호출하도록 바꾼다.

`signals` 매핑(설계 §4.1, priority = 표 순서):
- R1/R2: 심박 줄(`RunSummary` 심박 axis label = `RunHeadline.Axis.heart.label`) tone `.neutral`이고 `input.workoutType`이 이지 의도이거나 `input.planPhase`가 회복·테이퍼·대회 후 → problem p1(이지)/p2(plan), text = `"심박 · " + line.state`가 아니라 **`line.state` + evidence가 있으면 " — " + evidence**, direction = `line.next`, family `.unique`
- R3: `input.lateRun` 있고 kind가 held/가속 유지가 아님 → problem p3, text = `LateRunDiagnosis.state(r)` 문장 + evidence, direction = 후반 줄 next, family `.lateHR`(kind cardio/combined) 또는 `.latePace`(그 외)
- R4: R3 없고 `RunSummaryBuilder.lateHRRoseFirst(...)` 또는 후반-전반 ≥8bpm(카드 `hrVerdictText`와 같은 조건 — 함께 추출해 `hrVerdict(...)`로 둬도 됨) → problem p4, `FormNarrative.hrSecondHalfRiseCaption(type:)`, family `.lateHR`
- R5: `zoneVerdict(...)?.isProblem == true` → problem p5, direction = `FormNarrative.highIntensityOneLiner(type:)`의 둘째 문장이 아니라 **심박 줄 next가 있으면 그것, 없으면 nil**
- R6: `paceShapeVerdict(...)?.isProblem == true` → problem p6, family `.latePace`
- good: easyVerdict 좋음(g1) → `FormNarrative.hrSteadyCaption` (R4 조건 불충족이고 심박 있음, g2) → `input.distanceRank == 1 && sampleCount >= 5`이면 "최근 N회 중 가장 긴 거리"(g3, family `.distanceRank`)
- `TabDigest.Tone`: problem → `.caution`, good → `.good`

- [ ] **Step 1: 추출 회귀 테스트 먼저** — `zoneVerdict`·`easyVerdict`·`paceShapeVerdict`에 대해 카드가 지금 내는 문장과 같은지(설계 출처 목록 A3~A7, C11~C20 문장)를 픽스처로 고정:

```swift
final class TabDigestRhythmTests: XCTestCase {
    func testEasyVerdictThresholds() {
        XCTAssertEqual(TabDigestRhythm.easyVerdict(lowZoneFraction: 0.85).isProblem, false)
        XCTAssertTrue(TabDigestRhythm.easyVerdict(lowZoneFraction: 0.6).text.contains("60%"))
        XCTAssertTrue(TabDigestRhythm.easyVerdict(lowZoneFraction: 0.4).isProblem)
    }
    func testZoneVerdictZone2() {
        let v = TabDigestRhythm.zoneVerdict(fractions: [2: 0.7, 3: 0.3], workoutType: .easy, heatSuffix: nil)
        XCTAssertEqual(v?.text, AppLanguage.shared.s("Zone 2 중심으로 달렸습니다", "Mostly Zone 2", ja: "Zone 2中心で走りました"))  // 카드 원문의 en/ja를 그대로 옮길 것
        XCTAssertEqual(v?.isProblem, false)
    }
    func testZoneVerdictHighIntensityUnplannedIsProblem() {
        let v = TabDigestRhythm.zoneVerdict(fractions: [4: 0.5, 5: 0.2, 2: 0.3], workoutType: .general, heatSuffix: nil)
        XCTAssertEqual(v?.isProblem, true)
    }
    func testPaceShapeEvenIsGood() {
        let splits = (1...8).map { FormPhaseStubs.split(km: $0, paceSec: 380) }
        XCTAssertEqual(TabDigestRhythm.paceShapeVerdict(splits: splits, workoutType: .general)?.isProblem, false)
    }
}
```
(`FormPhaseStubs`는 `MIMORunningTests/FormPhaseStubs.swift`의 기존 스텁 — 실제 헬퍼 이름을 확인해 맞출 것. 테스트 언어는 한국어 기본 — 기존 테스트가 `AppLanguage` 언어를 어떻게 고정하는지 `AppLanguageTests.swift`를 보고 따를 것.)

- [ ] **Step 2: 실패 확인 → Step 3: 추출 구현(카드가 static 호출) → Step 4: TEST BUILD SUCCEEDED**
- [ ] **Step 5: signals 테스트 추가 후 구현**

```swift
    func testEasyRunHighHRBecomesProblemWithNext() {
        var i = RunSummaryInput(); i.workoutType = .easy; i.zoneFractions = [3: 0.6, 2: 0.4]; i.distKm = 8
        let lines = RunSummary.lines(i)
        let sig = TabDigestRhythm.signals(context: .stub(workoutType: .easy), input: i, lines: lines)
        let p = sig.first { $0.kind == .problem }
        XCTAssertEqual(p?.priority, 1)
        XCTAssertNotNil(p?.direction)
    }
```
`RunSummaryBuilder.Context.stub(...)`가 없으면 테스트 타깃에 `extension RunSummaryBuilder.Context { static func stub(workoutType: WorkoutType) -> Self }`를 만든다(빈 history·nil 옵셔널).
- [ ] **Step 6: 커밋** (신규 2 + RunInsightTabCard.swift)

---

### Task 4: 폼 신호 수집기 (+ 폼 카드 판정 추출)

**Files:**
- Create: `MIMORunning/Insight/TabDigestForm.swift`
- Modify: `MIMORunning/Views/RunFormCardView.swift` — `narrative`(1719), `longDistanceFormChangeInsight`(697), `cadenceHRInsight`(771); `MIMORunning/Views/IntervalFatigueCard.swift` — `interpretationType`(161), `interpretation`(401), `suggestion`(488)
- Test: `MIMORunningTests/TabDigestFormTests.swift`

**Interfaces:**
- Produces:

```swift
enum TabDigestForm {
    struct Inputs {               // 폼 카드가 지금 뷰에서 조립하는 재료를 값으로
        var activity: Activity
        var detail: ActivityDetail?
        var baseline: RunningFormBaseline?
        var formShifts: [MRFormShift]
        var workoutType: WorkoutType
        var typicalKm: Double?
        var fatigueContext: String?
        var phase: FormPhase.Result?
    }
    static func narrative(_ x: Inputs) -> String?                       // 옮김: RunFormCardView.narrative
    static func narrativeIsProblem(_ x: Inputs) -> Bool                  // narrative가 고른 분기가 '문제' 분기인지(설계 F2·F3·F8)
    static func formChangeSentence(_ x: Inputs) -> String?               // 옮김: longDistanceFormChangeInsight 문장
    static func cadenceAdvice(_ x: Inputs) -> String?                    // 옮김: cadenceHRInsight 문장
    static func intervalPair(_ x: Inputs) -> (interpretation: String, suggestion: String?)?  // 옮김: IntervalFatigueCard
    static func signals(_ x: Inputs, lines: [RunSummaryLine]) -> [TabDigest.Signal]
}
```

`signals` 매핑(설계 §4.2):
- 인터벌: `intervalPair` → 문제 유형이면 problem p1 + direction suggestion, 아니면 good g1. 다른 신호 없음.
- F1 faded: `phase?.late == .faded` → problem p1, text `FormPhase.sentence(phase)`, direction 폼 줄 next(`RunSummary.formNext` 결과 = lines의 폼 axis next), family `.latePace`
- F2/F3/F8: `narrativeIsProblem` → problem p2, text `narrative`, direction 폼 줄 next ?? `cadenceAdvice`
- F4/F5: 리듬 카드 C3·C7 문장(Task 3에서 `TabDigestRhythm`에 함께 추출했으면 그 함수, 아니면 이 Task에서 `buildWorkoutTypeFormParts`의 빌드업·템포 분기를 `TabDigestForm.typeFormVerdict(...)`로 추출) → problem p4/p5, 문장 안 권고가 있으면 direction nil
- F6 heavier/bouncier → problem p6, `FormPhase.sentence`, direction 폼 줄 next. isSoftCadenceOnly는 **good**(g2)
- F7 `formChangeSentence` → problem p7
- good: held → g1 "끝까지 폼을 유지했습니다"(FormPhase.sentence), 템포 C5·C6 g3, C9 g4, narrative 좋은 분기 g5
- extra: `mrFormObservation(formShifts, ...)?.text`의 첫 줄(`\n` 앞) e1
- defaults: `cadenceAdvice`

- [ ] **Step 1: 추출 회귀 테스트** — `narrative`의 이지 다리 무거움 분기(지면접촉 위·케이던스 아래 + fatigueContext)가 "다리가 무거운 날의 패턴입니다 — 5일 연속…"을 내고 `narrativeIsProblem == true`인지, 모두 범위면 false인지. 픽스처는 `MIMORunningTests/FormNarrativeTests.swift`·`FormPhaseStubs.swift`의 기존 빌더를 재사용.
- [ ] **Step 2~4: 추출 → 카드가 static 호출 → TEST BUILD SUCCEEDED**
- [ ] **Step 5: signals 테스트** — `testIntervalUsesFatigueCardPair`: 인터벌 Inputs면 signals가 1개(인터벌 쌍)뿐. `testFadedTakesLatePaceFamily`. `testSoftCadenceOnlyIsGood`.
- [ ] **Step 6: 커밋**

---

### Task 5: 퍼포먼스 신호 수집기 (+ 퍼포먼스 카드 판정 추출)

**Files:**
- Create: `MIMORunning/Insight/TabDigestPerformance.swift`
- Modify: `MIMORunning/Views/RunInsightTabCard.swift` — `aerobicDecouplingPct`(3729), `decouplingReading`(3756), `sevenDayLoadRatioLabel`(4940), `sevenDayLoadSentence`(4956), `returnInsight`(5033)·`returnInsightRow` 문장, 강도 분포 easyAlert 문장(≈4858)
- Test: `MIMORunningTests/TabDigestPerformanceTests.swift`

**Interfaces:**
- Produces:

```swift
enum TabDigestPerformance {
    static func decouplingPct(splits: [SplitData], workoutType: WorkoutType, distKm: Double) -> Double?   // 옮김
    static func decouplingVerdict(pct: Double, workoutType: WorkoutType, temperatureC: Double?,
                                  lateHRRoseFirst: Bool) -> TabDigestRhythm.Verdict                     // 옮김(Color → isProblem)
    static func loadRatioText(_ label: EffortLoad.RatioLabel) -> String                                  // 옮김
    static func loadSentence(_ kind: EffortLoad.SentenceKind) -> String?                                 // 옮김(steady → nil)
    static func returnSentences(activity: Activity, history: [Activity], heatHRModel: MRHeatHRModel?)
        -> (gap: String, compare: String?, advice: String?, recovered: String?)?                         // 옮김
    static func signals(context: RunSummaryBuilder.Context, input: RunSummaryInput, lines: [RunSummaryLine],
                        insights: [RunInsight], easyAlertText: String?) -> [TabDigest.Signal]
}
```

`signals` 매핑(설계 §4.3):
- P1 복귀: `returnSentences` gap(+compare) → problem p1, direction advice
- P2 부하: `input.acuteChronic` high/veryHigh 또는 `input.loadSentence == .monotony` → problem p2, text = `loadRatioText` + (loadSentence 있으면 ", " + 그것), direction = 훈련부하 줄 next(`RunHeadline.Axis.load.label`), family `.load`
- P3 디커플링 >5% → problem p3, family `.lateHR`
- P4 `RunInsight.efficiencyComparison(in:)` tone 높음(caution) → problem p4, family `.efficiency`
- P5 `easyAlertText`(뷰가 이미 계산한 값이 있으면 넘김, 없으면 nil — 비동기 결과 전엔 건너뜀) → problem p5
- P6 `insights`에서 endurance >5% → problem p6, family `.latePace`
- P7 cardio 낮음 → problem p7
- good: 효율 비교 good g1(family `.efficiency`), 역치 상승은 제목이 이미 말하므로 제외, 디커플링 ≤5% g3(family `.lateHR`), 복귀 recovered g4, 네거티브 스플릿 g5
- defaults: 훈련부하 줄 next

- [ ] **Step 1: 추출 회귀 테스트** — `decouplingVerdict` 경계: 4.9%/7%/12% × 덥다(26°C)/아님 → 설계 출처 C 표 문장·isProblem. `loadSentence(.steady) == nil`.
- [ ] **Step 2~4: 추출 → 카드가 static 호출 → TEST BUILD SUCCEEDED**
- [ ] **Step 5: signals 테스트** — 부하 veryHigh면 problem p2 + direction이 훈련부하 줄 next와 같음; 디커플링 신호는 family `.lateHR`.
- [ ] **Step 6: 커밋**

---

### Task 6: 화면 연결 — 블록 렌더·탭 이동·fact/next 제거

**Files:**
- Modify: `MIMORunning/Views/ActivityDetailView.swift` — `recomputeHeadline`(≈270), `InsightCard`(≈1703-1830), 인사이트 탭 선택 상태(`RunInsightTabCard`의 선택 탭 바인딩 위치 확인)
- Test: `MIMORunningTests/TabDigestAssemblyTests.swift`

**Interfaces:**
- Consumes: Task 2~5의 `TabDigest.make`, `TabDigestRhythm/Form/Performance.signals`, `defaultDirection`
- Produces: `static func TabDigest.assemble(rhythm: [Signal], form: [Signal], performance: [Signal], defaults: Defaults) -> [Block]` (= `make(rhythm+form+performance, defaults:)`, 테스트 편의)

- [ ] **Step 1:** `@State private var digest: [TabDigest.Block] = []`. `recomputeHeadline()` 끝에서 세 수집기를 부르고 `TabDigest.make`로 계산(같은 `headlineKey` 트리거). 폼 Inputs는 폼 카드에 넘기는 값과 같은 출처(`summaryContext`, `formBaseline`, `RunSummaryBuilder.fatigueContext`, `input.form`)로 만든다.
- [ ] **Step 2:** `InsightCard`에 `digest: [TabDigest.Block]`·`onSelectTab: (InsightTabKind) -> Void` 추가. 제목 아래의 `headline.fact` 텍스트와 `headline.next` 블록(≈1807-1815)을 **digest가 비어 있지 않을 때** 제거하고 블록 렌더. digest가 비면(워치 없음 등) 지금 표시 그대로(대체 경로 유지).
  블록 뷰: 탭 라벨(`InsightTabKind.title`, 11pt semibold, secondary) → statements 각 줄(앞에 6pt 점: caution=`Theme` 노랑 계열(총평 neutral 색과 같은 값), good=`Theme.positive`, neutral=secondary) → direction("→ " + 문장, 보라 `Theme.violet`). 블록 사이 구분선 0.5pt. 블록 전체 `Button`으로 `onSelectTab` 호출.
- [ ] **Step 3:** 탭 이동 — `RunInsightTabCard`가 선택 탭을 `@State`로 갖고 있으면 `@Binding`으로 끌어올리거나 `ActivityDetailView`에 `@State selectedInsightTab`을 두고 넘긴다. 이동 후 `ScrollViewReader`로 인사이트 탭 카드 위치로 스크롤(기존 `.id` 있으면 재사용).
- [ ] **Step 4:** `shareInsight`(≈294)는 그대로 — 공유 카드는 title·fact를 계속 쓴다(범위 밖 결정).
- [ ] **Step 5:** 조립 테스트 — 이지런 심박 높음 + 다리 무거움 + 부하 veryHigh 시나리오에서 블록 3개, 각 블록 direction 존재, 훈련부하 next가 한 번만 등장.
- [ ] **Step 6:** build-for-testing 성공 확인(테스트 실행은 하지 않음 — 사용자 규칙).
- [ ] **Step 7: 커밋** — ActivityDetailView.swift(+ 바인딩으로 바뀐 RunInsightTabCard.swift) + 테스트.

---

### Task 7: 메모리·문서 정리

- [ ] 설계 문서 상태를 "구현 완료(실기기 확인 대기)"로 갱신하고 커밋.
- [ ] 메모리 `today-headline.md`에 "2026-10-14 탭 요약 블록 추가(TabDigest), fact·next 줄은 블록 있을 때 숨김, 실기기 확인 대기" 한 줄 추가.
