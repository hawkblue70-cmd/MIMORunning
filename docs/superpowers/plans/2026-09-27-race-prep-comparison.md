# 대회 준비 비교(B단계) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 등록한 대회마다 지난 대회(같은 대회 우선, 없으면 같은 거리)의 같은 D-N 시점과 지금의 준비 상태(주간 거리·최장 롱런·예상 기록)를 나 탭 대회 계획과 홈 한 줄로 보여 준다.

**Architecture:** 비교 대상 고르기·시점·28일 지표·앞섬 판정·문장은 순수 로직 `MRPrepComparison`에 두고 Swift Testing으로 검증한다. `MREngineStore`가 러닝·확정 대회·현재 예측을 넣어 등록 대회마다 결과를 계산하고(지난 시점 예상 기록은 성장 탭 백테스트와 같은 as-of 방식), 홈 오늘 카드에 한 줄을 붙인다. 대회 DB 시리즈 조회는 `ContentView`가 `RaceDetector`로 엔진에 넘긴다.

**Tech Stack:** Swift 5 모드(앱 타깃 기본 격리 MainActor) · SwiftUI · Swift Testing · Xcode 26(폴더 동기화 그룹)

**설계 문서:** `docs/superpowers/specs/2026-09-27-race-prep-comparison-design.md`

---

## 작업 전 필독 규칙 (이 저장소 전용)

- **시뮬레이터를 켜지 않는다. 테스트도 실행하지 않는다.** 검증은 컴파일까지다. TDD는 "테스트를 먼저 쓰고 컴파일이 기대대로 깨지는 것을 본다 → 구현 → 컴파일 성공". 모든 테스트 기대값은 **손으로 추적**해 보고한다.
- 컴파일 명령(저장소 루트 `/Users/hns/MIMORunning/MIMORunning`, 서브에이전트는 `-derivedDataPath` 전용 경로를 붙인다):

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|\*\* TEST BUILD" | head -20
```

  성공: `** TEST BUILD SUCCEEDED **`.
- 같은 브랜치(crew)에 다른 세션이 동시에 커밋한다. `git add -A`/`.`/`git stash` 금지, 고친 파일 경로만 명시해 커밋, `git show --stat HEAD`로 확인. 작업 트리의 `MIMORunning.xcodeproj/project.pbxproj` 변경은 건드리지 않는다. 고칠 파일에 남의 미커밋 변경이 있으면 멈추고 보고한다.
- 커밋 메시지는 한국어, 끝에 Co-Authored-By 한 줄.
- 문자열은 `AppLanguage.shared.s("한국어", "English")`.

## 설계와 달라진 점

1. **나 탭 블록 위치** — 대회 계획 카드 **안**이 아니라, 펼친 대회 카드 **바로 아래**에 작은 카드로 붙인다(기존 `MRRacePlanCard` 내부를 건드리지 않기 위해). 펼친 대회에만 보인다.
2. **제목 조사** — "D-21과"는 숫자에 따라 조사가 바뀌므로 "D-21 시점과 비교"로 쓴다.
3. **지난 값 표기** — 세 줄 모두 "작년 10km", "작년 4:02:00"처럼 열 이름(작년 / 2024년 / 지난) + 값. 제목이 "작년 ○○ D-21 시점과 비교"라 시점이 드러난다.

## 파일 구조

| 파일 | 상태 | 책임 |
|---|---|---|
| `MIMORunning/Engine/MRPrepComparison.swift` | 새로 | 대상 고르기·시점·28일 지표·결과·앞섬·문장(순수 로직) |
| `MIMORunningTests/MRPrepComparisonTests.swift` | 새로 | 위 규칙 테스트 |
| `MIMORunning/Health/RaceDetector.swift` | 수정 | 등록 대회 이름·날짜 → 시리즈 조회 `series(forRaceNamed:on:)` |
| `MIMORunningTests/RacePastYearTests.swift` | 수정 | 위 조회 테스트 1개 |
| `MIMORunning/Engine/MREngineStore.swift` | 수정 | 시리즈 조회 주입점, `prepComparisons`, as-of 예측, 재계산 훅, 홈 한 줄 |
| `MIMORunning/Engine/MRTodayCard.swift` | 수정 | `prepLine` 속성 |
| `MIMORunning/ContentView.swift` | 수정 | 시리즈 조회를 엔진에 주입 |
| `MIMORunning/Views/MRPrepComparisonView.swift` | 새로 | 나 탭 블록 |
| `MIMORunning/Views/MRRacePlanView.swift` | 수정 | 펼친 대회 아래 블록 |
| `MIMORunning/Views/MRTodayCardView.swift` | 수정 | 대회 안내 줄 아래 한 줄 |

---

### Task 1: 등록 대회 → 시리즈 조회

**Files:**
- Modify: `MIMORunning/Health/RaceDetector.swift`
- Modify: `MIMORunningTests/RacePastYearTests.swift`

등록 대회(`MyPlannedRace`)의 날짜는 대회 DB와 같은 방식(UTC 자정)으로 해석되므로, A에서 만든 `utcDayString`으로 DB 줄을 찾는다.

- [ ] **Step 1: 테스트 추가**

`MIMORunningTests/RacePastYearTests.swift`의 `// MARK: - 지난 해 후보` 줄 바로 위에 추가:

```swift
    @Test func seriesForRegisteredRaceByNameAndDay() {
        let d = detector()
        #expect(d.series(forRaceNamed: "2026 춘천마라톤", on: r26.date!) == "c")
        #expect(d.series(forRaceNamed: "우리 동네 풀", on: r26.date!) == nil)
        #expect(d.series(forRaceNamed: "2026 춘천마라톤", on: r25.date!) == nil)
    }

```

- [ ] **Step 2: 컴파일이 깨지는지 확인** — Expected: `has no member 'series(forRaceNamed:on:)'` 류

- [ ] **Step 3: 구현** — `RaceDetector.swift`의 `func series(for match: PersistedRaceMatch) -> String?` 함수 바로 아래에:

```swift

    /// 등록 대회(이름·날짜)의 시리즈 값 — 대회 준비 비교(B)용. 등록 대회 날짜도 DB처럼 UTC 자정이다.
    func series(forRaceNamed name: String, on date: Date) -> String? {
        let day = Self.utcDayString(date)
        guard let s = races.first(where: { $0.name == name && $0.dateString == day })?.series,
              !s.isEmpty else { return nil }
        return s
    }
```

- [ ] **Step 4: 컴파일 성공 확인** — `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Health/RaceDetector.swift MIMORunningTests/RacePastYearTests.swift
git commit -m "등록 대회 이름·날짜 → 대회 DB 시리즈 조회 — 대회 준비 비교용"
git show --stat HEAD | tail -3
```

---

### Task 2: 준비 비교 순수 로직 — `MRPrepComparison`

**Files:**
- Create: `MIMORunning/Engine/MRPrepComparison.swift`
- Test: `MIMORunningTests/MRPrepComparisonTests.swift`

규칙: 대상 = 등록 대회보다 이른 확정 대회 중 같은 시리즈·같은 종목(±2%) 최신, 없으면 종목 거리 10% 안 최신. D-N은 오늘부터 대회까지 일수(N ≥ 1만). 지난 시점 = 지난 대회일 − N일. 지표 = 시점 직전 28일(시점 당일 제외) 거리 합÷4, 최장 한 번. 지난 창이 비면 결과 없음, 지금 창이 비면 0. 거리 줄은 지금이 10% 이상 많을 때만 "+○%", 예상 기록은 1초 이상 빠를 때만 "−m:ss".

- [ ] **Step 1: 테스트 먼저 작성**

`MIMORunningTests/MRPrepComparisonTests.swift`:

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("대회 준비 비교", .korean)
struct MRPrepComparisonTests {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    /// 로컬(서울) 날짜+시각
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// 대회 DB·등록 대회처럼 "yyyy-MM-dd"를 UTC 자정으로
    private func utc(_ s: String) -> Date {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s)!
    }

    private func past(_ name: String, _ day: String, km: Double, series: String?) -> MRPrepComparison.PastRace {
        MRPrepComparison.PastRace(name: name, date: utc(day), distanceKm: km, series: series)
    }

    private func run(_ d: Date, _ km: Double) -> MRPrepComparison.RunPoint {
        MRPrepComparison.RunPoint(date: d, km: km)
    }

    private func result(weeklyNow: Double = 12, weeklyPast: Double = 10,
                        longNow: Double = 28, longPast: Double = 24,
                        nowPred: Double? = 235, pastPred: Double? = 242,
                        same: Bool = true, years: Int = 1, pastYear: Int = 2025,
                        name: String = "제46회 조선일보 춘천마라톤", km: Double = 42.195) -> MRPrepComparison.Result {
        MRPrepComparison.Result(
            target: past(name, "2025-10-25", km: km, series: same ? "c" : "s"),
            isSameRace: same, daysLeft: 21, yearsAgo: years, pastYear: pastYear,
            now: .init(weeklyKm: weeklyNow, longestKm: longNow),
            past: .init(weeklyKm: weeklyPast, longestKm: longPast),
            nowPredictedMin: nowPred, pastPredictedMin: pastPred)
    }

    // MARK: - 대상

    @Test func sameRaceIsPreferred() {
        let t = MRPrepComparison.target(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c",
            confirmed: [past("제46회 조선일보 춘천마라톤", "2025-10-25", km: 42.195, series: "c"),
                        past("2026 서울마라톤", "2026-03-15", km: 42.195, series: "s")],
            calendar: cal)
        #expect(t?.race.name == "제46회 조선일보 춘천마라톤")
        #expect(t?.isSameRace == true)
    }

    @Test func sameRaceNeedsSameEvent() {
        let t = MRPrepComparison.target(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c",
            confirmed: [past("제46회 조선일보 춘천마라톤", "2025-10-25", km: 10, series: "c")],
            calendar: cal)
        #expect(t == nil)
    }

    @Test func fallsBackToNewestSameDistance() {
        let t = MRPrepComparison.target(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c",
            confirmed: [past("2025 JTBC 서울마라톤", "2025-11-02", km: 42.195, series: "j"),
                        past("2026 서울마라톤", "2026-03-15", km: 42.195, series: "s"),
                        past("2026 ○○ 32K", "2026-04-12", km: 32, series: nil)],
            calendar: cal)
        #expect(t?.race.name == "2026 서울마라톤")
        #expect(t?.isSameRace == false)
    }

    @Test func ignoresRacesOnOrAfterRaceDay() {
        let t = MRPrepComparison.target(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c",
            confirmed: [past("2026 JTBC 마라톤", "2026-11-01", km: 42.195, series: "j"),
                        past("2026 춘천마라톤", "2026-10-25", km: 42.195, series: "c")],
            calendar: cal)
        #expect(t == nil)
    }

    @Test func tenPercentDistanceWindow() {
        let half = MRPrepComparison.target(
            raceDate: utc("2026-10-25"), raceDistanceKm: 21.0975, raceSeries: nil,
            confirmed: [past("2025 ○○ 20K", "2025-11-02", km: 20, series: nil)], calendar: cal)
        #expect(half?.race.distanceKm == 20)
        let tenK = MRPrepComparison.target(
            raceDate: utc("2026-10-25"), raceDistanceKm: 10, raceSeries: nil,
            confirmed: [past("2025 ○○", "2025-11-02", km: 11.5, series: nil)], calendar: cal)
        #expect(tenK == nil)
    }

    // MARK: - 시점 · 지표

    @Test func daysLeftAndPastPoint() {
        let n = MRPrepComparison.daysLeft(raceDate: utc("2026-10-25"), today: date(2026, 10, 4, 8), calendar: cal)
        #expect(n == 21)
        let p = MRPrepComparison.pastPoint(pastRaceDate: utc("2025-10-25"), daysLeft: 21, calendar: cal)
        #expect(p == date(2025, 10, 4, 0))
    }

    @Test func metricsWindowExcludesPointDay() {
        let runs = [run(date(2025, 9, 5), 20),      // 창 밖(29일 전)
                    run(date(2025, 9, 6), 10),
                    run(date(2025, 9, 20), 24),
                    run(date(2025, 10, 3, 6), 6),
                    run(date(2025, 10, 4, 7), 30)]  // 시점 당일 — 제외
        let m = MRPrepComparison.metrics(runs: runs, before: date(2025, 10, 4, 0), calendar: cal)
        #expect(m == MRPrepComparison.Metrics(weeklyKm: 10, longestKm: 24))
    }

    @Test func metricsNilWhenWindowEmpty() {
        #expect(MRPrepComparison.metrics(runs: [run(date(2025, 1, 1), 10)],
                                         before: date(2025, 10, 4, 0), calendar: cal) == nil)
    }

    @Test func buildFullResult() {
        var askedAt: Date? = nil
        let runs = [run(date(2025, 9, 6), 10), run(date(2025, 9, 20), 24), run(date(2025, 10, 3, 6), 6),
                    run(date(2026, 9, 10), 12), run(date(2026, 9, 27), 28), run(date(2026, 10, 2), 8)]
        let r = MRPrepComparison.build(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c",
            confirmed: [past("제46회 조선일보 춘천마라톤", "2025-10-25", km: 42.195, series: "c")],
            runs: runs, today: date(2026, 10, 4, 8),
            nowPredictedMin: 235, predictionAt: { askedAt = $0; return 242 }, calendar: cal)
        #expect(r?.daysLeft == 21)
        #expect(r?.isSameRace == true)
        #expect(r?.yearsAgo == 1)
        #expect(r?.pastYear == 2025)
        #expect(r?.now == MRPrepComparison.Metrics(weeklyKm: 12, longestKm: 28))
        #expect(r?.past == MRPrepComparison.Metrics(weeklyKm: 10, longestKm: 24))
        #expect(r?.nowPredictedMin == 235)
        #expect(r?.pastPredictedMin == 242)
        #expect(askedAt == date(2025, 10, 4, 0))
    }

    @Test func buildNilOnRaceDayOrWithoutPastRuns() {
        let target = [past("제46회 조선일보 춘천마라톤", "2025-10-25", km: 42.195, series: "c")]
        let onRaceDay = MRPrepComparison.build(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c", confirmed: target,
            runs: [run(date(2025, 9, 20), 24)], today: date(2026, 10, 25, 6),
            nowPredictedMin: nil, predictionAt: { _ in nil }, calendar: cal)
        #expect(onRaceDay == nil)
        let noPastRuns = MRPrepComparison.build(
            raceDate: utc("2026-10-25"), raceDistanceKm: 42.195, raceSeries: "c", confirmed: target,
            runs: [run(date(2026, 9, 20), 24)], today: date(2026, 10, 4, 8),
            nowPredictedMin: nil, predictionAt: { _ in nil }, calendar: cal)
        #expect(noPastRuns == nil)
    }

    // MARK: - 나 탭 블록

    @Test func titleAndLines() {
        let r = result()
        #expect(MRPrepComparison.title(r) == "작년 조선일보 춘천마라톤 D-21 시점과 비교")
        #expect(MRPrepComparison.lines(r) == [
            .init(label: "주간 거리", now: "12km", past: "작년 10km", gain: "+20%"),
            .init(label: "최장 롱런", now: "28km", past: "작년 24km", gain: "+17%"),
            .init(label: "예상 기록", now: "3:55:00", past: "작년 4:02:00", gain: "−7:00"),
        ])
    }

    @Test func gainNeedsTenPercentForDistance() {
        #expect(MRPrepComparison.lines(result(weeklyNow: 10.9))[0].gain == nil)
        #expect(MRPrepComparison.lines(result(weeklyNow: 11.0))[0].gain == "+10%")
    }

    @Test func slowerPredictionHasNoGainAndMissingPredictionDropsLine() {
        #expect(MRPrepComparison.lines(result(nowPred: 245))[2].gain == nil)
        #expect(MRPrepComparison.lines(result(pastPred: nil)).count == 2)
    }

    @Test func sameDistanceAndTwoYearTitles() {
        let dist = result(same: false, years: 0, pastYear: 2026, name: "2026 서울마라톤")
        #expect(MRPrepComparison.title(dist) == "지난 서울마라톤 풀 D-21 시점과 비교")
        #expect(MRPrepComparison.lines(dist)[0].past == "지난 10km")
        let two = result(years: 2, pastYear: 2024)
        #expect(MRPrepComparison.title(two) == "2024년 조선일보 춘천마라톤 D-21 시점과 비교")
        #expect(MRPrepComparison.lines(two)[0].past == "2024년 10km")
    }

    // MARK: - 홈 한 줄

    @Test func homeLines() {
        #expect(MRPrepComparison.homeLine(result()) == "작년 이맘때보다 주간 거리 20% 많아요 · 12km / 10km")
        #expect(MRPrepComparison.homeLine(result(weeklyNow: 9)) == "작년 이맘때 주간 10km · 지금 9km")
        #expect(MRPrepComparison.homeLine(result(same: false, years: 0, pastYear: 2026, name: "2026 서울마라톤"))
                == "지난 서울마라톤 이맘때보다 주간 거리 20% 많아요 · 12km / 10km")
        #expect(MRPrepComparison.homeLine(result(years: 2, pastYear: 2024)) == "2024년 이맘때보다 주간 거리 20% 많아요 · 12km / 10km")
    }

    @Test(.english) func homeLinesInEnglish() {
        #expect(MRPrepComparison.homeLine(result()) == "Weekly distance 20% higher than this point last year · 12 km / 10 km")
        #expect(MRPrepComparison.homeLine(result(weeklyNow: 9)) == "This point last year: 10 km/wk · now 9 km")
    }
}
```

손 추적 참고: `utc("2026-10-25")`는 서울 10/25 09:00 → 서울 기준 날짜 10/25. 오늘 10/4 → 21일. 지난 시점 = 2025-10-25 서울 0시 − 21일 = 2025-10-04 0시. 지난 창 [9/6 0시, 10/4 0시): 10+24+6 = 40 → 10/주, 최장 24. 지금 창 [2026-9-6, 10-4): 12+28+8 = 48 → 12, 최장 28. 28/24 = 1.1667 → "+17%". 예상 기록 차이 (242−235)×60 = 420초 → "7:00". `RaceDisplayName.distanceLabel(42.195)` = "풀".

- [ ] **Step 2: 컴파일이 깨지는지 확인** — Expected: `cannot find 'MRPrepComparison' in scope`

- [ ] **Step 3: 구현**

`MIMORunning/Engine/MRPrepComparison.swift`:

```swift
import Foundation

/// 대회 준비 비교(B단계) — 등록 대회의 D-N 시점과, 지난 대회(같은 대회 우선, 없으면 같은 거리)의
/// 같은 D-N 시점의 준비 상태를 비교한다. 순수 로직.
/// 설계 `docs/superpowers/specs/2026-09-27-race-prep-comparison-design.md`.
enum MRPrepComparison {

    /// 비교 대상이 될 수 있는 확정 대회 하나.
    struct PastRace: Equatable {
        let name: String
        /// 대회 날짜 — 확정 매칭의 raceDate(대회 DB 날짜의 UTC 자정)
        let date: Date
        /// 공식 종목 거리(km)
        let distanceKm: Double
        let series: String?
    }

    struct Target: Equatable {
        let race: PastRace
        let isSameRace: Bool
    }

    /// 러닝 한 번 — 날짜와 거리(km)
    struct RunPoint {
        let date: Date
        let km: Double
    }

    /// 시점 직전 28일의 준비 지표
    struct Metrics: Equatable {
        let weeklyKm: Double
        let longestKm: Double
    }

    struct Result: Equatable {
        let target: PastRace
        let isSameRace: Bool
        /// D-N의 N
        let daysLeft: Int
        /// 등록 대회 연도 − 지난 대회 연도
        let yearsAgo: Int
        let pastYear: Int
        let now: Metrics
        let past: Metrics
        let nowPredictedMin: Double?
        let pastPredictedMin: Double?
    }

    /// 나 탭 블록 한 줄
    struct Line: Equatable {
        let label: String
        let now: String
        let past: String
        /// 지금이 앞설 때만 — "+20%" · "−7:00"
        let gain: String?
    }

    static let sameEventTolerance = 0.02
    static let sameDistanceTolerance = 0.10
    /// 거리 지표를 "많아요"로 말하는 문턱 — 10% 이상
    static let gainThreshold = 0.10
    static let windowDays = 28

    // MARK: - 대상

    /// 같은 대회(같은 시리즈·같은 종목 ±2%) 최신 > 같은 거리(10%) 최신. 등록 대회 날짜보다 이른 것만.
    static func target(raceDate: Date, raceDistanceKm: Double, raceSeries: String?,
                       confirmed: [PastRace], calendar: Calendar = .current) -> Target? {
        let raceDay = calendar.startOfDay(for: raceDate)
        let earlier = confirmed
            .filter { calendar.startOfDay(for: $0.date) < raceDay }
            .sorted { $0.date > $1.date }
        func ratio(_ km: Double) -> Double { abs(km - raceDistanceKm) / max(raceDistanceKm, 0.001) }
        if let s = raceSeries, !s.isEmpty,
           let same = earlier.first(where: { $0.series == s && ratio($0.distanceKm) <= sameEventTolerance }) {
            return Target(race: same, isSameRace: true)
        }
        if let dist = earlier.first(where: { ratio($0.distanceKm) <= sameDistanceTolerance + 1e-9 }) {
            return Target(race: dist, isSameRace: false)
        }
        return nil
    }

    // MARK: - 시점 · 지표

    static func daysLeft(raceDate: Date, today: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: today),
                                to: calendar.startOfDay(for: raceDate)).day ?? 0
    }

    /// 지난 대회일(자정) − N일
    static func pastPoint(pastRaceDate: Date, daysLeft: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -daysLeft, to: calendar.startOfDay(for: pastRaceDate))
            ?? pastRaceDate
    }

    /// 시점 직전 28일(시점 당일 제외). 창에 러닝이 없으면 nil.
    static func metrics(runs: [RunPoint], before point: Date, calendar: Calendar = .current) -> Metrics? {
        let end = calendar.startOfDay(for: point)
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: end) else { return nil }
        let inWindow = runs.filter { $0.date >= start && $0.date < end && $0.km > 0 }
        guard !inWindow.isEmpty else { return nil }
        let total = inWindow.map(\.km).reduce(0, +)
        return Metrics(weeklyKm: total / Double(windowDays / 7),
                       longestKm: inWindow.map(\.km).max() ?? 0)
    }

    /// 등록 대회 하나의 결과. D-N ≥ 1이고 대상이 있고 지난 창에 러닝이 있을 때만.
    /// - predictionAt: 그 시점 전날까지 데이터로 낸 예상 기록(분). 엔진이 제공.
    static func build(raceDate: Date, raceDistanceKm: Double, raceSeries: String?,
                      confirmed: [PastRace], runs: [RunPoint], today: Date,
                      nowPredictedMin: Double?, predictionAt: (Date) -> Double?,
                      calendar: Calendar = .current) -> Result? {
        let n = daysLeft(raceDate: raceDate, today: today, calendar: calendar)
        guard n >= 1,
              let t = target(raceDate: raceDate, raceDistanceKm: raceDistanceKm, raceSeries: raceSeries,
                             confirmed: confirmed, calendar: calendar) else { return nil }
        let point = pastPoint(pastRaceDate: t.race.date, daysLeft: n, calendar: calendar)
        guard let past = metrics(runs: runs, before: point, calendar: calendar) else { return nil }
        let now = metrics(runs: runs, before: today, calendar: calendar) ?? Metrics(weeklyKm: 0, longestKm: 0)
        let pastYear = calendar.component(.year, from: t.race.date)
        return Result(target: t.race, isSameRace: t.isSameRace, daysLeft: n,
                      yearsAgo: calendar.component(.year, from: raceDate) - pastYear,
                      pastYear: pastYear, now: now, past: past,
                      nowPredictedMin: nowPredictedMin, pastPredictedMin: predictionAt(point))
    }

    // MARK: - 나 탭 블록

    /// "작년 ○○" · "2024년 ○○" · "지난 ○○"(같은 해) · 같은 거리는 "지난 ○○ 10K"
    static func targetName(_ r: Result) -> String {
        let L = AppLanguage.shared
        let name = RaceDisplayName.short(r.target.name)
        guard r.isSameRace else {
            let label = RaceDisplayName.distanceLabel(km: r.target.distanceKm)
            return L.s("지난 \(name) \(label)", "your last \(name) \(label)")
        }
        if r.yearsAgo == 1 { return L.s("작년 \(name)", "last year's \(name)") }
        if r.yearsAgo >= 2 { return L.s("\(r.pastYear)년 \(name)", "\(name) \(r.pastYear)") }
        return L.s("지난 \(name)", "your last \(name)")
    }

    static func title(_ r: Result) -> String {
        AppLanguage.shared.s("\(targetName(r)) D-\(r.daysLeft) 시점과 비교",
                             "Compared with \(targetName(r)) at D-\(r.daysLeft)")
    }

    /// 지난 값 앞에 붙는 열 이름 — 작년 · 2024년 · 지난
    static func pastColumn(_ r: Result) -> String {
        let L = AppLanguage.shared
        guard r.isSameRace else { return L.s("지난", "last") }
        if r.yearsAgo == 1 { return L.s("작년", "last yr") }
        if r.yearsAgo >= 2 { return L.s("\(r.pastYear)년", "\(r.pastYear)") }
        return L.s("지난", "last")
    }

    static func lines(_ r: Result) -> [Line] {
        let L = AppLanguage.shared
        let col = pastColumn(r)
        func km(_ v: Double) -> String { "\(Int(v.rounded()))km" }
        func gain(_ now: Double, _ past: Double) -> String? {
            guard past > 0, now >= past * (1 + gainThreshold) - 1e-9 else { return nil }
            return "+\(Int(((now / past - 1) * 100).rounded()))%"
        }
        var out = [
            Line(label: L.s("주간 거리", "Weekly"), now: km(r.now.weeklyKm),
                 past: "\(col) \(km(r.past.weeklyKm))", gain: gain(r.now.weeklyKm, r.past.weeklyKm)),
            Line(label: L.s("최장 롱런", "Longest"), now: km(r.now.longestKm),
                 past: "\(col) \(km(r.past.longestKm))", gain: gain(r.now.longestKm, r.past.longestKm)),
        ]
        if let n = r.nowPredictedMin, let p = r.pastPredictedMin {
            let faster = Int(((p - n) * 60).rounded())
            out.append(Line(label: L.s("예상 기록", "Predicted"), now: mrFormatDisplay(n),
                            past: "\(col) \(mrFormatDisplay(p))",
                            gain: faster >= 1 ? "−" + RaceYearOverYear.clockDuration(faster) : nil))
        }
        return out
    }

    // MARK: - 홈 한 줄

    static func homeLine(_ r: Result) -> String {
        let L = AppLanguage.shared
        let nowKm = Int(r.now.weeklyKm.rounded()), pastKm = Int(r.past.weeklyKm.rounded())
        let name = RaceDisplayName.short(r.target.name)
        let subjectKo: String, subjectEn: String
        if r.isSameRace && r.yearsAgo == 1 {
            subjectKo = "작년 이맘때"; subjectEn = "this point last year"
        } else if r.isSameRace && r.yearsAgo >= 2 {
            subjectKo = "\(r.pastYear)년 이맘때"; subjectEn = "this point in \(r.pastYear)"
        } else {
            subjectKo = "지난 \(name) 이맘때"; subjectEn = "this point before your last \(name)"
        }
        if r.past.weeklyKm > 0, r.now.weeklyKm >= r.past.weeklyKm * (1 + gainThreshold) - 1e-9 {
            let pct = Int(((r.now.weeklyKm / r.past.weeklyKm - 1) * 100).rounded())
            return L.s("\(subjectKo)보다 주간 거리 \(pct)% 많아요 · \(nowKm)km / \(pastKm)km",
                       "Weekly distance \(pct)% higher than \(subjectEn) · \(nowKm) km / \(pastKm) km")
        }
        let subjectEnCap = subjectEn.prefix(1).uppercased() + subjectEn.dropFirst()
        return L.s("\(subjectKo) 주간 \(pastKm)km · 지금 \(nowKm)km",
                   "\(subjectEnCap): \(pastKm) km/wk · now \(nowKm) km")
    }
}
```

- [ ] **Step 4: 컴파일 성공 확인** — `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Engine/MRPrepComparison.swift MIMORunningTests/MRPrepComparisonTests.swift
git commit -m "대회 준비 비교 규칙 — 같은 대회 우선·같은 거리, D-N 시점 28일 지표·예상 기록, 앞선 것만 말함"
git show --stat HEAD | tail -3
```

---

### Task 3: 엔진 계산·홈 한 줄·시리즈 주입

**Files:**
- Modify: `MIMORunning/Engine/MREngineStore.swift`
- Modify: `MIMORunning/Engine/MRTodayCard.swift`
- Modify: `MIMORunning/ContentView.swift`

- [ ] **Step 1: `MRTodayCard`에 속성 추가** — `MRTodayCard.swift`의 `let readinessPlan: String?` 줄 아래에(기본값이 있어 기존 생성 호출은 그대로 컴파일된다):

```swift
    /// 대회 준비 비교 — 대회 안내 줄(linkLine) 바로 아래 한 줄. 엔진이 카드를 만든 뒤 채운다.
    var prepLine: String? = nil
```

- [ ] **Step 2: 엔진 속성** — `MREngineStore.swift`에서 `var persistedMatchesProvider: (() -> [PersistedRaceMatch]) = { [] }` 줄 아래에:

```swift
    /// 대회 준비 비교(B) — 확정 매칭 → 대회 DB 시리즈. 앱 수준(ContentView)이 RaceDetector로 채운다.
    var seriesForMatch: (PersistedRaceMatch) -> String? = { _ in nil }
    /// 대회 준비 비교(B) — 등록 대회(이름·날짜) → 대회 DB 시리즈.
    var seriesForRace: (String, Date) -> String? = { _, _ in nil }
```

`@Published private(set) var backtest: [MRBacktestRow] = []` 줄 아래에:

```swift
    /// 대회 준비 비교(B) — 등록 대회 id(uuidString) → 결과. 비교할 지난 대회가 없으면 항목 없음.
    @Published private(set) var prepComparisons: [String: MRPrepComparison.Result] = [:]
```

- [ ] **Step 3: 계산 함수** — `func updateConfirmedMatches(...)` 함수 닫는 중괄호 바로 아래에:

```swift

    /// 대회 준비 비교(B)를 다시 계산하고 홈 오늘 카드(한 줄)도 다시 만든다.
    func refreshPrepComparisons(now: Date = Date()) {
        guard case .ready = state else { return }
        let confirmed = storedConfirmedMatches.filter(\.isConfirmed).map {
            MRPrepComparison.PastRace(name: $0.raceName, date: $0.raceDate,
                                      distanceKm: $0.distanceKm, series: seriesForMatch($0))
        }
        let points = runs.compactMap { w in
            w.distanceKm.map { MRPrepComparison.RunPoint(date: w.date, km: $0) }
        }
        var out: [String: MRPrepComparison.Result] = [:]
        for race in userInput.upcomingRaces(asOf: now) {
            let label = race.label
            if let r = MRPrepComparison.build(
                raceDate: race.date, raceDistanceKm: race.distanceM / 1000,
                raceSeries: seriesForRace(race.name, race.date),
                confirmed: confirmed, runs: points, today: now,
                nowPredictedMin: predictions.first { $0.label == label }?.midMin,
                predictionAt: { point in self.asOfPrediction(label: label, at: point) }) {
                out[race.id.uuidString] = r
            }
        }
        prepComparisons = out
        todayCard = buildTodayCard(runs: runs, now: now)
    }

    /// 그 시점 전날까지의 데이터만으로 낸 예상 기록(분) — 성장 탭 예측 목록(mrBacktest)과 같은 방식.
    private func asOfPrediction(label: String, at point: Date) -> Double? {
        guard ["5K", "10K", "하프", "풀"].contains(label),
              let y = Calendar.current.date(byAdding: .day, value: -1, to: point) else { return nil }
        let pastRuns = runs.filter { $0.date <= y }
        let phys2 = mrPhysiology(runs: pastRuns, restingHRSamples: rhrSamples,
                                 dateOfBirth: storedDob, sex: storedSex, asOf: y)
        let prior = mrApplyHeat(mrDetectEfforts(runs: pastRuns, phys: phys2), heat: heat)
            .filter { $0.date < point }
        guard prior.count >= 3 else { return nil }
        let fit2 = mrFitExponent(prior)
        let prof2 = mrProfile(runs: pastRuns, efforts: prior, asOf: y)
        return mrPredict(efforts: prior, fit: fit2, profile: prof2, heat: heat, asOf: y)
            .first { $0.label == label }?.midMin
    }
```

- [ ] **Step 4: 재계산 훅 세 곳**

1. `updateConfirmedMatches` 안 `storedConfirmedMatches = matches` 줄 바로 아래에 `refreshPrepComparisons()`.
2. 1단계 갱신 끝의 `state = .ready` 줄(주석 `// ★ 여기서 화면이 그려진다` 아래) 바로 아래에 `refreshPrepComparisons(now: now)`.
3. `func recomputePlans(...)`의 마지막 줄 `todayCard = buildTodayCard(runs: runs, now: now)` 바로 아래에 `refreshPrepComparisons(now: now)`.

- [ ] **Step 5: 홈 한 줄** — `private func buildTodayCard(runs:now:)`의 `return mrTodayCard(` 를 `var card: MRTodayCard? = mrTodayCard(`로 바꾸고, 그 호출이 끝난 다음 줄에:

```swift
        card?.prepLine = prepLine(for: card, now: now)
        return card
```

그리고 함수 아래에 추가:

```swift

    /// 홈 대회 안내 줄 아래 한 줄 — 안내 줄이 가리키는 대회(가장 가까운 계획 대회)의 준비 비교.
    /// 안내 줄이 없으면(D-day 카드가 떠 있거나 계획 대회 없음) 없다.
    private func prepLine(for card: MRTodayCard?, now: Date) -> String? {
        guard card?.linkLine != nil,
              let next = plans.filter({ $0.raceDate > now }).min(by: { $0.raceDate < $1.raceDate }) else { return nil }
        let cal = Calendar.current
        guard let race = userInput.races.first(where: {
                  cal.isDate($0.date, inSameDayAs: next.raceDate) && abs($0.distanceM - next.distanceM) < 1
              }),
              let r = prepComparisons[race.id.uuidString] else { return nil }
        return MRPrepComparison.homeLine(r)
    }
```

- [ ] **Step 6: 시리즈 주입** — `ContentView.swift`의 `.task {` 안 `engine.persistedMatchesProvider = { [manager] in manager.persistedConfirmedMatches() }` 줄 바로 아래에:

```swift
            // 대회 준비 비교(B) — 시리즈 조회. raceDetector가 준비되면 확정 대회 전달(updateConfirmedMatches)이 다시 계산한다.
            engine.seriesForMatch = { [raceDetector] m in raceDetector.series(for: m) }
            engine.seriesForRace = { [raceDetector] name, date in raceDetector.series(forRaceNamed: name, on: date) }
```

- [ ] **Step 7: 컴파일 성공 확인** — `** TEST BUILD SUCCEEDED **`. 실패 시 흔한 원인: `mrTodayCard`가 옵셔널이 아닌 값을 돌려주면 `var card: MRTodayCard? = ...` 그대로 두면 된다. `MRWorkout.distanceKm`는 `Double?`.

- [ ] **Step 8: 커밋**

```bash
git add MIMORunning/Engine/MREngineStore.swift MIMORunning/Engine/MRTodayCard.swift MIMORunning/ContentView.swift
git commit -m "엔진 — 등록 대회마다 준비 비교 계산(지난 시점 as-of 예측), 홈 대회 안내 줄 아래 한 줄, 시리즈 조회 주입"
git show --stat HEAD | tail -4
```

---

### Task 4: 화면 — 나 탭 블록·홈 한 줄

**Files:**
- Create: `MIMORunning/Views/MRPrepComparisonView.swift`
- Modify: `MIMORunning/Views/MRRacePlanView.swift` (`MRRacePlanSection`)
- Modify: `MIMORunning/Views/MRTodayCardView.swift`

- [ ] **Step 1: 블록 뷰** — `MIMORunning/Views/MRPrepComparisonView.swift`:

```swift
import SwiftUI

/// 나 탭 대회 계획 — 지난 대회 같은 D-N 시점과 지금의 준비 비교(B단계). 펼친 대회 카드 바로 아래.
struct MRPrepComparisonView: View {
    let result: MRPrepComparison.Result

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MRPrepComparison.title(result))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
            ForEach(Array(MRPrepComparison.lines(result).enumerated()), id: \.offset) { _, line in
                HStack(spacing: 8) {
                    Text(line.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 58, alignment: .leading)
                    Text(line.now)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text(line.past)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if let g = line.gain {
                        Text(g)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.positive)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
```

- [ ] **Step 2: 나 탭 연결** — `MRRacePlanView.swift`의 `struct MRRacePlanSection` 본문 `ForEach(engine.raceItems) { item in` 클로저에서, `switch item { ... }` 블록이 끝난 바로 다음 줄(클로저 닫는 `}` 전)에:

```swift
                    // 대회 준비 비교(B) — 펼친 대회에만, 카드 바로 아래
                    if isExpanded, let prep = engine.prepComparisons[item.id] {
                        MRPrepComparisonView(result: prep)
                    }
```

- [ ] **Step 3: 홈 한 줄** — `MRTodayCardView.swift`에서 `if let link = c.linkLine { ... }` 블록 바로 아래(같은 `if c.sessionLine != nil || c.linkLine != nil {` 블록 안)에:

```swift
                    // 대회 준비 비교(B) — 안내 줄 아래 한 줄, 작고 흐리게
                    if let prep = c.prepLine {
                        Text(prep)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .padding(.top, 4)
                    }
```

- [ ] **Step 4: 컴파일 성공 확인** — `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Views/MRPrepComparisonView.swift MIMORunning/Views/MRRacePlanView.swift MIMORunning/Views/MRTodayCardView.swift
git commit -m "대회 준비 비교 화면 — 나 탭 펼친 대회 아래 블록, 홈 대회 안내 줄 아래 한 줄"
git show --stat HEAD | tail -4
```

---

### Task 5: 마무리

- [ ] 전체 컴파일 `** TEST BUILD SUCCEEDED **`, `git log --oneline -5`(Task 1~4 커밋), `git status --short`(무관한 pbxproj만).
- [ ] 실기기 확인 목록(사용자):
  1. 10K 대회를 등록해 두면(지난 10K 대회 확정 기록이 있을 때) 나 탭 대회 계획에서 그 대회를 펼쳤을 때 카드 아래에 "지난 ○○ 10K D-N 시점과 비교" 블록이 뜬다.
  2. 주간 거리·최장 롱런이 지난 시점보다 10% 이상 많으면 "+○%"가 초록으로 붙고, 아니면 숫자만.
  3. 홈 오늘 카드의 "다음 대회까지 N주 — …" 줄 아래에 "지난 ○○ 이맘때보다 주간 거리 ○% 많아요 · …" 또는 "지난 ○○ 이맘때 주간 …km · 지금 …km"가 뜬다. D-14 이후(D-day 카드가 뜰 때)에는 두 줄 모두 없다.
  4. 비교할 지난 대회가 없는 대회는 블록·한 줄이 없다.

## Self-Review 결과

- **설계 대응:** 대상 고르기(Task 2 `target`, 시리즈는 Task 1·3) · D-N ≥ 1·지난 시점(Task 2) · 28일 지표·지난 창 비면 숨김(Task 2) · 예상 기록 as-of·R 거리 기준·표준 거리만(Task 3 `asOfPrediction`) · 앞섬 10%·1초·숫자만(Task 2) · 문장(작년/2년/같은 해/같은 거리, 홈 두 문장, 한/영)(Task 2) · 나 탭 블록·홈 한 줄·안내 줄 조건(Task 3·4) · 테스트 목록(Task 1·2).
- **설계와 달라진 점:** 위 3가지(블록 위치·제목 조사·지난 값 표기). 설계 문서에 반영한다.
- **타입 일관성:** `MRPrepComparison.PastRace/Target/RunPoint/Metrics/Result/Line`, `target/daysLeft/pastPoint/metrics/build/targetName/title/pastColumn/lines/homeLine`, `RaceDetector.series(forRaceNamed:on:)`, `MREngineStore.prepComparisons/seriesForMatch/seriesForRace/refreshPrepComparisons`, `MRTodayCard.prepLine` — 정의와 사용 이름이 같다.
