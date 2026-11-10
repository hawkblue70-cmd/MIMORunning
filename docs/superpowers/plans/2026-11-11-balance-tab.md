# 밸런스 탭 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 러닝 상세 인사이트 탭 줄에 '밸런스' 탭을 더해, 저울(들인 것 ↔ 나온 것) + 폼 거미줄 + 몸 상태 막대로 오늘 러닝을 문장 없이 그림 한 장으로 보여준다.

**Architecture:** 판정은 순수 엔진 `BalanceSnapshot`(Insight/)이 원시값 입력(`BalanceSnapshot.Input`)만 받아 계산하고, 뷰 쪽 접착 코드가 폼 탭과 같은 `TabDigestForm.Inputs`·총평과 같은 `RunSummaryBuilder.input(_:)`에서 입력을 채운다. 뷰 `BalanceTabCard`는 그리기만 하고, 내보내기 시트도 같은 뷰를 쓴다(미리보기 = 출력).

**Tech Stack:** SwiftUI · Swift Charts 없음(SVG식 Path로 저울·거미줄) · Swift Testing(`@Suite(..., .korean)`).

**Spec:** `docs/superpowers/specs/2026-11-11-balance-tab-design.md`

## Global Constraints

- 시뮬레이터 실행 금지. 검증은 컴파일만: `xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` → `** TEST BUILD SUCCEEDED **`. TDD 단계는 "테스트를 먼저 쓰고 컴파일이 기대한 대로 깨지는 것을 본다".
- 문구는 한국어·영어·일본어 `AppLanguage.shared.s(ko, en, ja:)`. 문장 단락 없음, 판정어·"부상/위험" 금지. 탭 이름 `밸런스` / `Balance` / `バランス`.
- 색: 좋음 `Theme.positive`(초록) · 보통 노랑(`Color(hex: "F5C542")`) · 나쁨 빨강(`Color(hex: "FF5A5F")`) · 오늘 도형 바이올렛 `#7C5CFC`(`Theme.violet`) · 평소 도형 회색.
- 커밋은 경로를 명시해서(`git add -A`·stash 금지 — 같은 브랜치를 다른 세션이 쓴다). 메시지 끝 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- 새 파일은 Xcode 동기화 그룹이라 프로젝트 파일 수정 없이 포함된다.

## Review Focus

1. 폼 탭과 밸런스 탭이 같은 러닝을 다르게 말하는 경우 — 같은 `FormNarrative.status`·같은 stat(`strideStat`, `adjustedGctStat`)을 써야 한다(Task 1 테스트 `formAxesUseGivenStats`, Task 3 접착 코드).
2. 판정 불가 구간(`isReferenceBand`)에서 빨간 점·저울 점수가 생기는 경우 — 없어야 한다(Task 1 `referenceBandDoesNotScore`).
3. 인터벌 러닝에서 저울·거미줄이 나오는 경우 — 몸 상태 막대만(Task 1 `intervalShowsBodyOnly`).
4. 평소대로 뛴 날 저울이 기우는 경우 — 모든 항목 범위 안이면 기울기 0(Task 1 `allInRangeIsLevel`).
5. 폰·가민 러닝(폼 없음)·심박 없음·몸 상태 없음 조합 — 저울만 / 탭 숨김이 스펙대로(Task 1 `modeByAvailableData`).

---

### Task 1: 판정 엔진 `BalanceSnapshot`

**Files:**
- Create: `MIMORunning/Insight/BalanceSnapshot.swift`
- Test: `MIMORunningTests/BalanceSnapshotTests.swift`

**Interfaces:**
- Consumes: `FormStat(median:sd:count:p10:p90:)`, `FormNarrative.status(rawValue:stat:metric:) -> FormNarrative.Status`(`.inRange/.above/.below/.unknown`), `FormNarrative.Metric`, `EffortLoad.RatioLabel`(`.low/.steady/.high/.veryHigh`), `WorkoutType`.
- Produces:
```swift
enum BalanceLevel: Equatable { case good, normal, bad }

enum BalanceAxisKind: CaseIterable, Equatable { case heartRate, cadence, stride, groundContact, verticalOsc }

struct BalanceAxis: Equatable {
    let kind: BalanceAxisKind
    let value: Double          // 실제 평균값
    let stat: FormStat         // 그리는 평소 범위(참고 모드면 빌린 구간)
    let status: FormNarrative.Status   // 참고 모드면 .unknown
}

enum BalanceBodyKind: CaseIterable, Equatable { case sleep, hrv, load, vo2 }

struct BalanceBody: Equatable { let kind: BalanceBodyKind; let level: BalanceLevel; let display: String }

struct BalanceSnapshot: Equatable {
    enum Mode: Equatable { case full, scaleOnly, bodyOnly }
    let mode: Mode
    let paceSecPerKm: Double?
    let axes: [BalanceAxis]        // mode == .full 일 때만 채움
    let bodies: [BalanceBody]      // 값 있는 것만, 순서 sleep·hrv·load·vo2
    let inputScore: Int            // 들인 것
    let outputScore: Int           // 나온 것
    /// −1…1. + = 왼쪽(들인 것)으로 기움 = 힘든 날, − = 가벼운 날
    var tilt: Double { max(-1, min(1, Double(inputScore - outputScore) / 4)) }

    struct Input: Equatable {
        var workoutType: WorkoutType
        var paceSecPerKm: Double?
        var hasForm: Bool                  // detail?.avgCadence != nil (폼 탭 노출 조건과 같음)
        var isReferenceBand: Bool          // 판정 불가 → 참고 모드
        var heartRate: Double?;  var heartRateStat: FormStat?
        var cadence: Double?;    var cadenceStat: FormStat?
        var stride: Double?;     var strideStat: FormStat?
        var groundContact: Double?; var groundContactStat: FormStat?
        var verticalOsc: Double?;   var verticalOscStat: FormStat?
        var effort: Int?;        var effortTypeMedian: Int?
        var sleepHours: Double?; var usualSleepHours: Double?
        var hrvLevel: BalanceLevel?        // 접착 코드가 `hrvLevel(_:lastNightLow:)`로 채움
        var load: EffortLoad.RatioLabel?
        var vo2: Double?;        var vo2SixMonths: [Double]
    }

    static func make(_ i: Input) -> BalanceSnapshot?
    static func sleepLevel(hours: Double, usual: Double) -> BalanceLevel
    static func loadLevel(_ l: EffortLoad.RatioLabel) -> BalanceLevel
    static func vo2Level(current: Double, sixMonths: [Double]) -> BalanceLevel?
    static func hrvLevel(_ t: MRHRVTrend?, lastNightLow: Bool) -> BalanceLevel?
}
```

규칙(스펙 값):
- `sleepLevel`: `hours >= usual` → good · `usual − hours <= 1.0` → normal(30분 미만 부족도 good: `usual − hours < 0.5` → good) · 그 외 bad.
- `loadLevel`: steady → good · low → normal · high, veryHigh → bad.
- `vo2Level`: sixMonths 비면 nil · `current >= sixMonths.min()` → good · 아니면 bad.
- `hrvLevel`: t nil → nil · `t.isVolatile || t.state == .below || lastNightLow` → bad · `t.isReadyHigh` → good · 그 외 normal (총평 `gradeLabel` 순서와 같음).
- 점수(참고 모드·`.unknown` 축은 0): 들인 것 = 심박 above +1 / below −1 · 체감 `effort − effortTypeMedian` ≥ 2 → +1, ≤ −2 → −1 · 몸 상태 sleep·hrv·load 중 bad 하나당 +1(vo2 제외). 나온 것 = 케이던스·보폭 above +1 / below −1 · 접지 below +1 / above −1 · 수직 진폭은 점수 없음.
- 모드: `workoutType == .interval` → `.bodyOnly`(bodies 비면 nil) · `hasForm` 이고 폼 stat이 하나라도 있으면 `.full` · 아니면 들인 것 항목(심박 stat, 체감 쌍, 몸 상태 sleep/hrv/load) 하나라도 있으면 `.scaleOnly` · 하나도 없으면 nil.

- [ ] **Step 1: 실패하는 테스트 작성** — `BalanceSnapshotTests.swift`, `@Suite("밸런스 탭 판정", .korean)`. 공통 헬퍼 `stat(_ median: Double, _ sd: Double) -> FormStat`.
  - `sleepLevels`: `sleepLevel(hours: 7, usual: 7) == .good` · `(6.6, 7) == .good` · `(6.2, 7) == .normal` · `(5.9, 7) == .bad`.
  - `loadLevels`: steady→good, low→normal, high→bad, veryHigh→bad.
  - `vo2Levels`: `vo2Level(current: 48, sixMonths: []) == nil` · `(48, [47, 49]) == .good` · `(46.5, [47, 49]) == .bad`.
  - `allInRangeIsLevel`: 모든 축 값 = median(심박 150/stat(150,5) 등), effort == median, 몸 상태 good → `mode == .full`, `inputScore == 0`, `outputScore == 0`, `tilt == 0`.
  - `heavyLegsTiltsLeft`: 심박 160(stat 150,5 → above), 케이던스 166(stat 172,3 → below), sleepHours 5 / usual 7 → `inputScore == 2`, `outputScore == -1`, `tilt == 0.75`, 케이던스 축 status `.below`.
  - `formAxesUseGivenStats`: 보폭 1.05 · strideStat(1.0, 0.03)이면 status `.above`(같은 함수 결과 `FormNarrative.status(rawValue: 1.05, stat:, metric: .stride)`와 일치).
  - `referenceBandDoesNotScore`: `isReferenceBand = true`, 심박 above·케이던스 below 값 → 모든 축 status `.unknown`, 점수 0, 축은 그려짐(`axes.count == 5`).
  - `intervalShowsBodyOnly`: workoutType `.interval`, 폼·몸 상태 있음 → `mode == .bodyOnly`, `axes.isEmpty`; 몸 상태 없음 → `make == nil`.
  - `modeByAvailableData`: hasForm false + 심박 stat 있음 → `.scaleOnly` · hasForm false + 아무 입력 없음 → nil · 수직 진폭은 점수 0(값 above여도 `outputScore` 변화 없음).
- [ ] **Step 2: 컴파일이 깨지는 것 확인** — 위 빌드 명령 → `BalanceSnapshot` 없음 에러.
- [ ] **Step 3: `BalanceSnapshot.swift` 구현** — 위 Interfaces와 규칙 그대로. 파일 머리 주석에 스펙 경로와 "폼 탭과 같은 판정 함수 — 새 문턱 없음".
- [ ] **Step 4: 빌드 통과 확인** — `** TEST BUILD SUCCEEDED **`.
- [ ] **Step 5: 커밋** — `git add MIMORunning/Insight/BalanceSnapshot.swift MIMORunningTests/BalanceSnapshotTests.swift`.

### Task 2: 본인 평소 수면 시간

**Files:**
- Modify: `MIMORunning/Engine/MREngineStore.swift` (`persistedSleepHours` 바로 아래)
- Test: `MIMORunningTests/BalanceSnapshotTests.swift`에 추가하지 않고 순수 함수로 분리해 `MIMORunningTests/BalanceSnapshotTests.swift` 끝에 1개.

**Interfaces:**
- Produces:
```swift
/// 그날(러닝 날짜) 아침 전 28밤의 잠든 시간 중앙값 — 밸런스 탭 수면 막대 기준. 7밤 미만이면 nil.
static func usualSleepHours(nights: [(date: Date, value: Double)], asOf: Date, calendar: Calendar = .current) -> Double?
static func persistedUsualSleepHours(asOf: Date, calendar: Calendar = .current) -> Double?   // sleepNightsKey 디코드 → usualSleepHours
```
- 창: `asOf` 날짜 이전(그날 제외) 28일 안의 밤. 중앙값은 `mrMedian`.

- [ ] **Step 1: 테스트** `usualSleepMedianExcludesTodayAndNeedsSeven`: 28밤 중 6밤만 → nil; 10밤(6·7·8시간 섞음) + 그날 밤 3시간 → 중앙값이 그날 값을 포함하지 않음.
- [ ] **Step 2: 컴파일 깨짐 확인.**
- [ ] **Step 3: 구현.**
- [ ] **Step 4: 빌드 통과.**
- [ ] **Step 5: 커밋** — 두 파일 경로 명시.

### Task 3: 밸런스 탭 화면·연결·내보내기

**Files:**
- Create: `MIMORunning/Views/BalanceTabCard.swift`
- Modify: `MIMORunning/Views/RunInsightTabCard.swift` — `InsightTabKind`(8행: `case rhythm, form, performance, balance, race`, title), `visibleTabs` 두 곳(1054행 카드·5629행 `InsightExportSheet`), 탭 내용 switch 두 곳(1141행·5811행 `case .performance:` 다음에 `case .balance:`).
- 기능 문서: `FEATURES.md` 3.2 활동 상세에 한 줄.

**Interfaces:**
- Consumes: Task 1 `BalanceSnapshot.make(_:)`·`hrvLevel`, Task 2 `MREngineStore.persistedUsualSleepHours(asOf:)`, `TabDigestForm.Inputs(activity:detail:baseline:formShifts:workoutType:typicalKm:fatigueContext:)`(필드 `bb`, `displayBb`, `isReferenceBand`, `strideStat`, `displayStrideStat`, `adjustedGctStat`, `displayGctStat`), `RunSummaryBuilder.input(_ c: RunSummaryBuilder.Context) -> RunSummaryInput`(필드 `hrvTrend`, `lastNightHRV`, `acuteChronic`, `lastNightSleepHours`, `vo2`), `MREngineStore.persistedLastNightHRVLow(asOf:)`, `EffortBaseline.samples(current:history:index:typeOf:)` + `EffortBaseline.median(for:samples:)`, `effortIndex.resolve(id)?.value`.
- Produces:
```swift
struct BalanceTabCard: View {
    let snapshot: BalanceSnapshot
    var isExport: Bool = false   // 내보내기: 애니메이션 없이 최종 상태
}
extension BalanceSnapshot.Input {
    /// 폼 탭·총평과 같은 입력에서 채운다. 판정 stat은 bb 기반(판정용), 그리는 stat은 displayBb 기반.
    static func from(form: TabDigestForm.Inputs, summary: RunSummaryInput, activity: Activity,
                     history: [Activity], effortIndex: EffortIndex?, typeOf: ((UUID) -> WorkoutType?)?,
                     vo2Points: [(date: Date, value: Double)]) -> BalanceSnapshot.Input
}
```
- 접착 규칙: 폼 stat은 `form.isReferenceBand`면 display 쪽(`displayBb?.cadence`, `displayStrideStat`, `displayGctStat`, `displayBb?.verticalOsc`, `displayBb?.heartRate`), 아니면 판정 쪽(`bb?.cadence`, `strideStat`, `adjustedGctStat`, `bb?.verticalOsc`, `bb?.heartRate`). 심박 값 = `activity.avgHeartRate`. vo2SixMonths = `vo2Points`에서 러닝 날짜 이전 182일 값. hrvLevel = `BalanceSnapshot.hrvLevel(summary.hrvTrend, lastNightLow: MREngineStore.persistedLastNightHRVLow(asOf: activity.date))`.
- 그리기(스펙 값): 위 저울 — 받침 + 판(최대 ±12°, `tilt × 12`) + 왼쪽 접시 들인 것 블록(심박·체감·수면·HRV·부하, 있는 것만) / 오른쪽 나온 것(케이던스·보폭·접지), 블록 색 = 항목 상태(좋음·보통·나쁨 또는 축 status: 범위 안 회색, 들인 것 쪽 above 빨강, 나온 것 쪽 below 빨강). 아래 `.full`이면 5축 거미줄(회색 = stat lower…upper 띠의 가운데 = 평소, 보라 = 오늘, `.below/.above` 중 나쁜 방향 꼭짓점 빨간 점, 꼭짓점 옆 실제 값 — 케이던스 정수 spm·보폭 0.00m·접지 정수 ms·수직 진폭 0.0cm·심박 정수 bpm), 가운데 페이스(`mrFormatPace`). 옆 몸 상태 막대(`bodies`). `.scaleOnly`면 저울 + 몸 상태 막대, `.bodyOnly`면 막대만. 눈금 정규화: 축 반지름 = 0.5 + (값 − median) / (upper − lower) × 0.5, 0.1…1.0로 자름(평소 범위 경계 = 회색 띠 경계).
- 애니메이션: 앱 화면은 나타날 때 `.spring`으로 저울이 기울고 도형이 펼쳐짐, `isExport`면 없음.
- 탭 노출: `visibleTabs`에서 `.balance`는 `BalanceSnapshot.make(...) != nil`일 때만(두 곳 같은 식 — 카드에 `balanceSnapshot` 계산 프로퍼티 하나를 두고 내보내기 시트도 같은 식).

- [ ] **Step 1: `InsightTabKind.balance` 추가 후 빌드** — switch 누락 에러 목록 확인(기대: 탭 내용 switch 두 곳).
- [ ] **Step 2: `BalanceTabCard.swift` 구현**(뷰 + `Input.from`).
- [ ] **Step 3: `RunInsightTabCard.swift` 연결** — 탭 두 switch에 `BalanceTabCard(snapshot:)`(내보내기는 `isExport: true`), `visibleTabs` 두 곳.
- [ ] **Step 4: 빌드 통과** — `** TEST BUILD SUCCEEDED **`.
- [ ] **Step 5: `FEATURES.md` 3.2에 한 줄** — "밸런스 탭(2026-11-11): 저울·폼 거미줄·몸 상태 막대, 기준 같은 페이스(폼 탭과 같은 판정), 인터벌은 막대만, 폼 없으면 저울만 — 스펙 docs/superpowers/specs/2026-11-11-balance-tab-design.md".
- [ ] **Step 6: 커밋** — `BalanceTabCard.swift`·`RunInsightTabCard.swift`·`FEATURES.md` 경로 명시.
