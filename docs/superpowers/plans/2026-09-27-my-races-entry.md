# 나 탭 참가 대회 — 예정 | 기록 토글 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 성장 탭 `예측이 얼마나 맞았나`를 없애고, 나 탭 `참가 대회`에 `예정 | 기록` 토글을 둬서 확정된 대회 기록을 모아 보고 러닝 상세로 이동하게 한다.

**Architecture:** 기록 행을 만드는 규칙은 SwiftData·HealthKit·SwiftUI에 의존하지 않는 순수 로직 두 파일(`RaceDisplayName`, `RaceRecordList`)에 두고 Swift Testing으로 검증한다. 나 탭은 확정 매칭·러닝·아카이브·엔진 예측을 평평한 입력으로 바꿔 넘기고, 새 행 뷰(`RaceRecordRow`)로 그린다. 이동은 `NavigationStack(path:)`에 `Activity`를 넣는 방식이다.

**Tech Stack:** Swift 6 · SwiftUI · SwiftData · Swift Testing · Xcode 26(폴더 동기화 그룹이라 새 파일은 프로젝트 파일 수정 없이 자동 포함)

**설계 문서:** `docs/superpowers/specs/2026-09-27-my-races-entry-design.md`

---

## 작업 전 필독 규칙 (이 저장소 전용)

- **시뮬레이터를 켜지 않는다. 테스트도 실행하지 않는다.** 검증은 컴파일까지다. TDD 단계는 "테스트를 먼저 쓰고 컴파일이 기대한 대로 깨지는 것을 본다 → 구현 → 컴파일 성공"이다. 테스트 실행은 사용자가 요청할 때만.
- 컴파일 명령(약 70초, 저장소 루트 `/Users/hns/MIMORunning/MIMORunning`에서):

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|\*\* TEST BUILD" | head -20
```

  성공: `** TEST BUILD SUCCEEDED **`. 서브에이전트를 여럿 병렬로 돌리면 DerivedData 잠금이 걸리므로 `-derivedDataPath <자기 전용 경로>`를 붙인다.
- **같은 브랜치(crew)에 다른 세션이 동시에 커밋한다.** `git add -A`, `git add .`, `git stash` 금지. 커밋은 내가 고친 파일 경로를 명시한다. 커밋 뒤 `git show --stat HEAD`로 내 파일만 들어갔는지 본다. 작업 트리의 `MIMORunning.xcodeproj/project.pbxproj` 변경은 다른 작업이다 — 건드리지 않는다.
- 커밋 메시지는 한국어, 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- 문자열은 `AppLanguage.shared.s("한국어", "English")`(관례상 `let L = AppLanguage.shared; L.s(...)`)로 한/영을 함께 쓴다.

## 파일 구조

| 파일 | 상태 | 책임 |
|---|---|---|
| `MIMORunning/Models/RaceDisplayName.swift` | 새로 | 대회 표시 이름(앞·뒤 연도, `제N회` 제거)·종목 라벨. 대회 해마다 비교(A)도 재사용 |
| `MIMORunning/Models/RaceRecordList.swift` | 새로 | 기록 행 만들기(같은 날 한 행·예측 연결·N회째), 예측 정확도 집계, 토글 기본값 |
| `MIMORunningTests/RaceDisplayNameTests.swift` | 새로 | 위 표시 규칙 테스트 |
| `MIMORunningTests/RaceRecordListTests.swift` | 새로 | 행 만들기·집계·기본값 테스트 |
| `MIMORunning/Engine/MRRaceArchiveManager.swift` | 수정 | 아카이브+계획 스냅샷 삭제 함수 `mrDeleteArchive`를 공용으로 추가 |
| `MIMORunning/Views/RaceRecordRow.swift` | 새로 | 기록 모드 한 행 |
| `MIMORunning/Views/MeView.swift` | 수정 | 토글·기록 목록·경로 기반 이동·계획 시트·삭제 확인 |
| `MIMORunning/Views/GrowthView.swift` | 수정 | `MRBacktestView` 호출과 쓰지 않게 된 아카이브 쿼리 제거 |
| `MIMORunning/Views/MRBacktestView.swift` | 수정 | 목록 본체와 전용 도우미 제거(아카이브 상세·건강 습관·드리프트 뷰는 유지) |

---

### Task 1: 대회 표시 이름·종목 라벨

**Files:**
- Create: `MIMORunning/Models/RaceDisplayName.swift`
- Test: `MIMORunningTests/RaceDisplayNameTests.swift`

- [ ] **Step 1: 테스트 먼저 작성**

`MIMORunningTests/RaceDisplayNameTests.swift`:

```swift
import Testing
import Foundation
@testable import MIMORunning

/// 대회 이름·종목 표시 규칙. 문자열 검사는 `.korean` 트레이트로 언어를 태스크 로컬에 고정.
@Suite("대회 표시 이름·종목", .korean)
struct RaceDisplayNameTests {

    @Test func stripsLeadingYear() {
        #expect(RaceDisplayName.short("2026 춘천마라톤") == "춘천마라톤")
    }

    @Test func stripsEdition() {
        #expect(RaceDisplayName.short("제46회 조선일보 춘천마라톤") == "조선일보 춘천마라톤")
    }

    @Test func stripsEditionInsideParentheses() {
        #expect(RaceDisplayName.short("2026 서울마라톤 (제96회 동아마라톤)") == "서울마라톤 (동아마라톤)")
    }

    @Test func stripsTrailingYear() {
        #expect(RaceDisplayName.short("고구려 마라톤 2025") == "고구려 마라톤")
    }

    @Test func keepsPlainName() {
        #expect(RaceDisplayName.short("JTBC 마라톤") == "JTBC 마라톤")
    }

    @Test func standardDistanceLabels() {
        #expect(RaceDisplayName.distanceLabel(km: 5.0) == "5K")
        #expect(RaceDisplayName.distanceLabel(km: 10.0) == "10K")
        #expect(RaceDisplayName.distanceLabel(km: 21.0975) == "하프")
        #expect(RaceDisplayName.distanceLabel(km: 42.195) == "풀")
    }

    @Test func nonStandardDistanceLabels() {
        #expect(RaceDisplayName.distanceLabel(km: 32.0) == "32K")
        #expect(RaceDisplayName.distanceLabel(km: 10.9) == "10.9K")
    }

    @Test(.english) func englishLabels() {
        #expect(RaceDisplayName.distanceLabel(km: 21.0975) == "Half")
        #expect(RaceDisplayName.distanceLabel(km: 42.195) == "Full")
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는지 확인**

Run: 위 "컴파일 명령"
Expected: `error: cannot find 'RaceDisplayName' in scope`

- [ ] **Step 3: 구현**

`MIMORunning/Models/RaceDisplayName.swift`:

```swift
import Foundation

/// 대회 이름·종목 표시 규칙. 나 탭 참가 대회 기록과 대회 해마다 비교가 같은 함수를 쓴다.
///
/// 대회 DB 이름은 출처마다 표기가 달라 연도와 회차가 앞뒤·괄호 안에 붙는다.
/// 화면에는 그것을 뗀 이름을 쓴다. 저장된 이름은 바꾸지 않는다.
enum RaceDisplayName {

    /// 앞·뒤 연도와 "제N회"(괄호 안 포함)를 뗀 표시 이름.
    /// "제46회 조선일보 춘천마라톤" → "조선일보 춘천마라톤"
    /// "2026 서울마라톤 (제96회 동아마라톤)" → "서울마라톤 (동아마라톤)"
    static func short(_ name: String) -> String {
        var s = name
        s = s.replacingOccurrences(of: #"^\s*20\d{2}\s+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+20\d{2}\s*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"제\s*\d+\s*회\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? name : s
    }

    /// 공식 종목 거리(km) → "5K"·"10K"·"하프"·"풀"(영어 Half·Full). 표준 거리 ±2% 밖이면 "32K"·"10.9K".
    static func distanceLabel(km: Double) -> String {
        let L = AppLanguage.shared
        let standards: [(km: Double, label: String)] = [
            (5.0, "5K"), (10.0, "10K"),
            (21.0975, L.s("하프", "Half")), (42.195, L.s("풀", "Full")),
        ]
        if let hit = standards.first(where: { abs($0.km - km) / $0.km <= 0.02 }) { return hit.label }
        if abs(km - km.rounded()) < 0.05 { return "\(Int(km.rounded()))K" }
        return String(format: "%.1fK", km)
    }
}
```

- [ ] **Step 4: 컴파일 성공 확인**

Run: 위 "컴파일 명령"
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Models/RaceDisplayName.swift MIMORunningTests/RaceDisplayNameTests.swift
git commit -m "$(cat <<'EOF'
대회 표시 이름·종목 라벨 — 연도·회차를 뗀 이름, 5K·10K·하프·풀·비표준 라벨

나 탭 참가 대회 기록과 대회 해마다 비교가 함께 쓴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git show --stat HEAD | tail -4
```

---

### Task 2: 기록 행 만들기·예측 정확도·토글 기본값

**Files:**
- Create: `MIMORunning/Models/RaceRecordList.swift`
- Test: `MIMORunningTests/RaceRecordListTests.swift`

규칙 요약:
- 행 출처는 둘. ① 확정 대회 러닝(누르면 러닝 상세) ② 같은 날 러닝이 없는 훈련 계획 아카이브(흐린 행). 같은 날짜는 한 행이고 ①이 이긴다.
- 예측 줄은 같은 날·같은 표준 거리(±2%)의 엔진 예측이 있을 때만. 값은 같은 날 아카이브의 "그때 앱 예측"(>0)이 있으면 그것, 없으면 엔진 예측. 구간 안/밖은 엔진 예측 행의 값.
- 엔진 예측 행만 있고 확정 러닝이 없는 날(대회급 훈련 러닝)은 목록에 없다.
- N회째는 `seriesKey`가 준 같은 값의 확정 러닝 중 이 날짜까지의 개수, 2 이상일 때만. 시리즈 칸이 생기기 전에는 `seriesKey`를 넘기지 않으므로 항상 없음.
- 최신순.

- [ ] **Step 1: 테스트 먼저 작성**

`MIMORunningTests/RaceRecordListTests.swift`:

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("나 탭 참가 대회 기록", .korean)
struct RaceRecordListTests {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func run(_ name: String, km: Double, _ d: Date, minutes: Double,
                     id: UUID = UUID()) -> RaceRecordList.RunInput {
        RaceRecordList.RunInput(activityID: id, raceName: name, distanceKm: km,
                                date: d, durationSec: minutes * 60)
    }

    private func archive(_ index: Int, _ name: String, _ d: Date, km: Double,
                         hasResult: Bool = false, actualMin: Double = 0,
                         projectedMin: Double = 0, hasDetail: Bool = true) -> RaceRecordList.ArchiveInput {
        RaceRecordList.ArchiveInput(index: index, raceName: name, raceDate: d, distanceM: km * 1000,
                                    hasResult: hasResult, actualMin: actualMin,
                                    projectedMin: projectedMin, hasDetail: hasDetail)
    }

    private func prediction(_ d: Date, km: Double, predicted: Double,
                            errorPct: Double = 1.0, inBand: Bool = true) -> RaceRecordList.PredictionInput {
        RaceRecordList.PredictionInput(date: d, distanceKm: km, predictedMin: predicted,
                                       errorPct: errorPct, inBand: inBand)
    }

    // MARK: - 행 만들기

    @Test func confirmedRunBecomesTappableRow() {
        let id = UUID()
        let rows = RaceRecordList.rows(
            runs: [run("2026 춘천마라톤", km: 42.195, date(2026, 10, 25), minutes: 232, id: id)],
            archives: [], predictions: [], calendar: cal)
        #expect(rows.count == 1)
        #expect(rows[0].source == .run(activityID: id))
        #expect(rows[0].name == "춘천마라톤")
        #expect(rows[0].distanceLabel == "풀")
        #expect(rows[0].finishMin == 232)
        #expect(rows[0].opensRun)
    }

    @Test func runAndArchiveOnSameDayMergeIntoOneRow() {
        let d = date(2026, 10, 25)
        let rows = RaceRecordList.rows(
            runs: [run("2026 춘천마라톤", km: 42.195, d, minutes: 232)],
            archives: [archive(3, "2026 춘천마라톤", date(2026, 10, 25, hour: 0), km: 42.195)],
            predictions: [], calendar: cal)
        #expect(rows.count == 1)
        #expect(rows[0].opensRun)
        #expect(rows[0].archiveIndex == 3)
        #expect(rows[0].hasPlan)
    }

    @Test func archiveWithoutWeeklyDetailHasNoPlanButton() {
        let d = date(2026, 10, 25)
        let rows = RaceRecordList.rows(
            runs: [run("2026 춘천마라톤", km: 42.195, d, minutes: 232)],
            archives: [archive(0, "2026 춘천마라톤", d, km: 42.195, hasDetail: false)],
            predictions: [], calendar: cal)
        #expect(rows[0].archiveIndex == 0)
        #expect(rows[0].hasPlan == false)
    }

    @Test func archiveOnlyDayIsDimRowWithoutRun() {
        let rows = RaceRecordList.rows(
            runs: [],
            archives: [archive(0, "2025 ○○마라톤", date(2025, 10, 5), km: 21.0975),
                       archive(1, "2025 △△마라톤", date(2025, 4, 6), km: 10, hasResult: true, actualMin: 55)],
            predictions: [], calendar: cal)
        #expect(rows.count == 2)
        #expect(rows[0].source == .archiveOnly)
        #expect(rows[0].opensRun == false)
        #expect(rows[0].finishMin == nil)
        #expect(rows[1].finishMin == 55)
    }

    @Test func predictionAttachesOnlyForSameDayAndSameDistance() {
        let d = date(2026, 3, 15)
        let half = RaceRecordList.rows(
            runs: [run("2026 서울하프", km: 21.0975, d, minutes: 110)],
            predictions: [prediction(d, km: 10, predicted: 50)], calendar: cal)
        #expect(half[0].prediction == nil)

        let matched = RaceRecordList.rows(
            runs: [run("2026 서울하프", km: 21.0975, d, minutes: 110)],
            predictions: [prediction(d, km: 21.0975, predicted: 112, inBand: false)], calendar: cal)
        #expect(matched[0].prediction == RaceRecordList.Prediction(predictedMin: 112, inBand: false))
    }

    @Test func archiveProjectionPreferredOverEnginePrediction() {
        let d = date(2026, 10, 25)
        let rows = RaceRecordList.rows(
            runs: [run("2026 춘천마라톤", km: 42.195, d, minutes: 232)],
            archives: [archive(0, "2026 춘천마라톤", d, km: 42.195, projectedMin: 235)],
            predictions: [prediction(d, km: 42.195, predicted: 240)], calendar: cal)
        #expect(rows[0].prediction?.predictedMin == 235)
    }

    @Test func trainingEffortWithoutConfirmedRaceIsNotListed() {
        let rows = RaceRecordList.rows(
            runs: [], archives: [],
            predictions: [prediction(date(2026, 5, 3), km: 10, predicted: 50)], calendar: cal)
        #expect(rows.isEmpty)
    }

    @Test func nonStandardRaceHasRowWithoutPrediction() {
        let d = date(2026, 4, 12)
        let rows = RaceRecordList.rows(
            runs: [run("2026 ○○ 32K", km: 32, d, minutes: 180)],
            predictions: [prediction(d, km: 42.195, predicted: 240)], calendar: cal)
        #expect(rows[0].distanceLabel == "32K")
        #expect(rows[0].prediction == nil)
    }

    @Test func editionCountFromSeriesKey() {
        let a = run("제45회 조선일보 춘천마라톤", km: 42.195, date(2024, 10, 27), minutes: 240)
        let b = run("제46회 조선일보 춘천마라톤", km: 42.195, date(2025, 10, 25), minutes: 236)
        let c = run("2026 춘천마라톤", km: 42.195, date(2026, 10, 25), minutes: 232)
        let other = run("2026 서울마라톤", km: 42.195, date(2026, 3, 15), minutes: 238)
        let key: (RaceRecordList.RunInput) -> String? = { $0.raceName.contains("춘천") ? "chuncheon-marathon" : nil }
        let rows = RaceRecordList.rows(runs: [a, b, c, other], seriesKey: key, calendar: cal)
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.date, $0.editionCount) })
        #expect(byName[c.date] == .some(3))
        #expect(byName[b.date] == .some(2))
        #expect(byName[a.date] == .some(nil))
        #expect(byName[other.date] == .some(nil))
    }

    @Test func noSeriesKeyMeansNoEditionCount() {
        let rows = RaceRecordList.rows(
            runs: [run("2025 춘천마라톤", km: 42.195, date(2025, 10, 25), minutes: 236),
                   run("2026 춘천마라톤", km: 42.195, date(2026, 10, 25), minutes: 232)],
            calendar: cal)
        #expect(rows.allSatisfy { $0.editionCount == nil })
    }

    @Test func rowsAreNewestFirst() {
        let rows = RaceRecordList.rows(
            runs: [run("A", km: 10, date(2025, 4, 6), minutes: 50),
                   run("B", km: 10, date(2026, 4, 5), minutes: 49)],
            archives: [archive(0, "C", date(2025, 11, 2), km: 10)],
            calendar: cal)
        #expect(rows.map(\.name) == ["B", "C", "A"])
    }

    // MARK: - 예측 정확도

    @Test func accuracyCountsOnlyConfirmedRaceDays() {
        let d1 = date(2026, 3, 15), d2 = date(2026, 10, 25), effortDay = date(2026, 5, 3)
        let acc = RaceRecordList.accuracy(
            runs: [run("서울", km: 42.195, d1, minutes: 238), run("춘천", km: 42.195, d2, minutes: 232)],
            predictions: [prediction(d1, km: 42.195, predicted: 245, errorPct: 3.0, inBand: true),
                          prediction(d2, km: 42.195, predicted: 250, errorPct: -5.0, inBand: false),
                          prediction(effortDay, km: 10, predicted: 50, errorPct: 20, inBand: false)],
            calendar: cal)
        #expect(acc == RaceRecordList.Accuracy(hit: 1, count: 2, meanAbsErrorPct: 4.0))
    }

    @Test func accuracyIsNilWithoutPredictions() {
        let acc = RaceRecordList.accuracy(
            runs: [run("서울", km: 42.195, date(2026, 3, 15), minutes: 238)],
            predictions: [], calendar: cal)
        #expect(acc == nil)
    }

    // MARK: - 토글 기본값

    @Test func defaultModeIsPlannedWhenUpcomingRaceExists() {
        let today = date(2026, 9, 27)
        #expect(RaceRecordList.defaultMode(plannedDates: [date(2026, 10, 25)], today: today, calendar: cal) == .planned)
        #expect(RaceRecordList.defaultMode(plannedDates: [date(2026, 9, 27, hour: 0)], today: today, calendar: cal) == .planned)
        #expect(RaceRecordList.defaultMode(plannedDates: [nil], today: today, calendar: cal) == .planned)
    }

    @Test func defaultModeIsRecordsWithoutUpcomingRace() {
        let today = date(2026, 9, 27)
        #expect(RaceRecordList.defaultMode(plannedDates: [], today: today, calendar: cal) == .records)
        #expect(RaceRecordList.defaultMode(plannedDates: [date(2026, 9, 26)], today: today, calendar: cal) == .records)
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는지 확인**

Run: 위 "컴파일 명령"
Expected: `error: cannot find 'RaceRecordList' in scope`

- [ ] **Step 3: 구현**

`MIMORunning/Models/RaceRecordList.swift`:

```swift
import Foundation

/// 나 탭 참가 대회 — 예정 | 기록.
enum RaceListMode: Equatable {
    case planned
    case records
}

/// 나 탭 참가 대회 · 기록 모드의 행을 만드는 순수 로직.
///
/// SwiftData·HealthKit·SwiftUI에 의존하지 않는다 — 뷰가 확정 매칭·러닝·아카이브·엔진 예측을
/// 아래 입력 구조체로 평평하게 바꿔 넘긴다.
///
/// 규칙(설계 `2026-09-27-my-races-entry-design.md`):
///  · 같은 날짜는 한 행. 확정 대회 러닝 > 러닝 없는 훈련 계획 아카이브.
///  · 엔진 예측만 있고 확정 러닝이 없는 날(대회급 훈련 러닝)은 목록에 없다.
///  · 예측 줄은 같은 날·같은 표준 거리(±2%)의 엔진 예측이 있을 때만.
enum RaceRecordList {

    /// 확정된 대회 러닝 하나.
    struct RunInput {
        let activityID: UUID
        let raceName: String
        /// 공식 종목 거리(km) — 확정 매칭에 저장된 값
        let distanceKm: Double
        /// 러닝 시작 시각
        let date: Date
        let durationSec: TimeInterval
    }

    /// 훈련 계획 아카이브 하나. `index`는 뷰가 가진 아카이브 배열에서의 위치 — 시트·삭제에서 원본을 찾을 때 쓴다.
    struct ArchiveInput {
        let index: Int
        let raceName: String
        let raceDate: Date
        let distanceM: Double
        let hasResult: Bool
        let actualMin: Double
        /// 계획 시작 시점 앱 예측(`snapshotProjectedFinalMin`). 0이면 없음.
        let projectedMin: Double
        /// 주차별 이행표가 있는가(`mrArchiveHasDetail`)
        let hasDetail: Bool
    }

    /// 엔진 예측 행(백테스트) 중 예측이 있는 것.
    struct PredictionInput {
        let date: Date
        /// 표준 거리(km) — 5 · 10 · 21.0975 · 42.195
        let distanceKm: Double
        let predictedMin: Double
        let errorPct: Double
        let inBand: Bool
    }

    struct Prediction: Equatable {
        let predictedMin: Double
        let inBand: Bool
    }

    struct Row: Identifiable, Equatable {
        enum Source: Equatable {
            case run(activityID: UUID)
            case archiveOnly
        }
        let id: String
        let date: Date
        /// 표시 이름(`RaceDisplayName.short`)
        let name: String
        let distanceLabel: String
        /// 완주 시간(분). nil = 기록 없음
        let finishMin: Double?
        let source: Source
        let prediction: Prediction?
        /// 같은 시리즈 N회째 — 2 이상일 때만
        let editionCount: Int?
        /// 이 날짜의 훈련 계획 아카이브 위치 — 삭제·계획 시트용
        let archiveIndex: Int?
        /// 계획 버튼을 보이는가(아카이브에 주차별 이행표가 있음)
        let hasPlan: Bool

        var opensRun: Bool {
            if case .run = source { return true }
            return false
        }
    }

    struct Accuracy: Equatable {
        let hit: Int
        let count: Int
        let meanAbsErrorPct: Double
    }

    // MARK: - 행

    static func rows(runs: [RunInput],
                     archives: [ArchiveInput] = [],
                     predictions: [PredictionInput] = [],
                     seriesKey: ((RunInput) -> String?)? = nil,
                     calendar: Calendar = .current) -> [Row] {
        func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }

        var out: [Row] = []
        var runDays = Set<Date>()

        for r in runs {
            let d = day(r.date)
            runDays.insert(d)
            let arch = archives.first { day($0.raceDate) == d }
            let prediction = prediction(for: r, in: predictions, calendar: calendar).map { p in
                let fromArchive = arch.map(\.projectedMin) ?? 0
                return Prediction(predictedMin: fromArchive > 0 ? fromArchive : p.predictedMin,
                                  inBand: p.inBand)
            }
            var edition: Int? = nil
            if let seriesKey, let key = seriesKey(r) {
                let n = runs.filter { seriesKey($0) == key && day($0.date) <= d }.count
                if n >= 2 { edition = n }
            }
            out.append(Row(
                id: r.activityID.uuidString,
                date: r.date,
                name: RaceDisplayName.short(r.raceName),
                distanceLabel: RaceDisplayName.distanceLabel(km: r.distanceKm),
                finishMin: r.durationSec / 60,
                source: .run(activityID: r.activityID),
                prediction: prediction,
                editionCount: edition,
                archiveIndex: arch?.index,
                hasPlan: arch?.hasDetail ?? false))
        }

        for a in archives where !runDays.contains(day(a.raceDate)) {
            out.append(Row(
                id: "archive-\(a.index)",
                date: a.raceDate,
                name: RaceDisplayName.short(a.raceName),
                distanceLabel: RaceDisplayName.distanceLabel(km: a.distanceM / 1000),
                finishMin: (a.hasResult && a.actualMin > 0) ? a.actualMin : nil,
                source: .archiveOnly,
                prediction: nil,
                editionCount: nil,
                archiveIndex: a.index,
                hasPlan: a.hasDetail))
        }

        return out.sorted { $0.date > $1.date }
    }

    // MARK: - 예측 정확도

    /// 확정 대회 러닝과 짝지어진 엔진 예측만 집계한다. 짝이 하나도 없으면 nil.
    static func accuracy(runs: [RunInput],
                         predictions: [PredictionInput],
                         calendar: Calendar = .current) -> Accuracy? {
        let matched = runs.compactMap { prediction(for: $0, in: predictions, calendar: calendar) }
        guard !matched.isEmpty else { return nil }
        let meanAbs = matched.map { abs($0.errorPct) }.reduce(0, +) / Double(matched.count)
        return Accuracy(hit: matched.filter(\.inBand).count, count: matched.count, meanAbsErrorPct: meanAbs)
    }

    // MARK: - 토글 기본값

    /// 오늘 이후(오늘 포함) 예정 대회가 하나라도 있으면 예정, 없으면 기록. 날짜를 읽지 못한 예정 대회는 앞으로 있는 것으로 본다.
    static func defaultMode(plannedDates: [Date?], today: Date,
                            calendar: Calendar = .current) -> RaceListMode {
        let start = calendar.startOfDay(for: today)
        return plannedDates.contains { ($0 ?? .distantFuture) >= start } ? .planned : .records
    }

    // MARK: - 내부

    /// 같은 날·같은 표준 거리(±2%)의 엔진 예측.
    private static func prediction(for run: RunInput, in predictions: [PredictionInput],
                                   calendar: Calendar) -> PredictionInput? {
        predictions.first {
            calendar.isDate($0.date, inSameDayAs: run.date)
            && abs($0.distanceKm - run.distanceKm) / max($0.distanceKm, 0.001) <= 0.02
        }
    }
}
```

- [ ] **Step 4: 컴파일 성공 확인**

Run: 위 "컴파일 명령"
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Models/RaceRecordList.swift MIMORunningTests/RaceRecordListTests.swift
git commit -m "$(cat <<'EOF'
나 탭 참가 대회 기록 행 로직 — 같은 날 한 행·예측 연결·N회째·정확도·토글 기본값

확정 대회 러닝 > 러닝 없는 계획 아카이브. 대회급 훈련 러닝은 목록에서 뺀다.
순수 로직이라 SwiftData·HealthKit 없이 테스트한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git show --stat HEAD | tail -4
```

---

### Task 3: 아카이브 삭제 함수 공용화

`MRBacktestView`의 private `deleteArchive`를 나 탭도 쓰도록 공용 함수로 옮긴다. 이 Task에서는 새 함수만 추가하고, 옛 private 함수는 Task 6에서 `MRBacktestView`와 함께 지운다.

**Files:**
- Modify: `MIMORunning/Engine/MRRaceArchiveManager.swift` (`func mrDeduplicateArchives` 바로 아래)

- [ ] **Step 1: 함수 추가**

`mrDeduplicateArchives(...)` 함수의 닫는 중괄호 바로 다음 줄에 넣는다:

```swift

/// 아카이브와 그것을 만들어낸 계획 스냅샷을 함께 지운다.
/// 스냅샷을 남기면 `createArchivesIfNeeded`가 다음에 같은 아카이브를 다시 만든다. 러닝 기록은 건드리지 않는다.
func mrDeleteArchive(_ arch: RaceArchive, snapshots: [RacePlanSnapshot], context: ModelContext) {
    let cal = Calendar.current
    snapshots
        .filter { snap in
            cal.isDate(snap.raceDate, inSameDayAs: arch.raceDate)
            && abs(snap.distanceM - arch.distanceM) / max(arch.distanceM, 1) <= 0.02
        }
        .forEach { context.delete($0) }
    context.delete(arch)
    try? context.save()
}
```

- [ ] **Step 2: 컴파일 성공 확인**

Run: 위 "컴파일 명령"
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add MIMORunning/Engine/MRRaceArchiveManager.swift
git commit -m "$(cat <<'EOF'
아카이브+계획 스냅샷 삭제를 공용 함수 mrDeleteArchive로 — 나 탭 참가 대회에서 재사용

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git show --stat HEAD | tail -3
```

---

### Task 4: 기록 행 뷰

**Files:**
- Create: `MIMORunning/Views/RaceRecordRow.swift`

행 전체 탭(러닝 상세 이동)은 부모가 `.onTapGesture`로 붙인다. 행 안의 `계획` 버튼이 부모 탭보다 먼저 받도록 이 뷰는 `NavigationLink`를 쓰지 않는다. 색은 기존 관례를 따른다 — 대회명 노랑(`RaceBadge.color`), 종목 칩 바이올렛, 구간 안 초록(`Theme.positive`), 구간 밖 주황(성장 탭 목록과 같은 값).

- [ ] **Step 1: 뷰 작성**

`MIMORunning/Views/RaceRecordRow.swift`:

```swift
import SwiftUI

/// 나 탭 참가 대회 · 기록 모드의 한 행.
///
/// 확정 러닝 행은 부모가 행 전체에 탭을 붙여 러닝 상세로 보낸다(여기서는 꺾쇠만 그림).
/// 러닝 없는 계획 아카이브 행은 흐리게 그린다.
struct RaceRecordRow: View {
    let row: RaceRecordList.Row
    var onTapPlan: (() -> Void)? = nil

    /// 구간 밖 — 성장 탭 예측 목록과 같은 주황
    private static let warn = Color(red: 0.95, green: 0.68, blue: 0.25)

    private var dateText: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: row.date)
        return String(format: "%d.%02d.%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private var hasSecondLine: Bool {
        row.prediction != nil || row.editionCount != nil || row.hasPlan
    }

    var body: some View {
        let L = AppLanguage.shared
        let dim = !row.opensRun
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(dateText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(row.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(dim ? Color.secondary : RaceBadge.color)
                    .lineLimit(1)
                Text(row.distanceLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.violet)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.violet.opacity(0.15))
                    .clipShape(Capsule())
                Spacer(minLength: 4)
                Text(row.finishMin.map { mrFormatDisplay($0) } ?? L.s("기록 없음", "No result"))
                    .font(.system(size: 14, weight: row.finishMin == nil ? .regular : .bold, design: .rounded))
                    .foregroundStyle(dim ? Color.secondary : Color.white)
                    .monospacedDigit()
                if row.opensRun {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if hasSecondLine {
                HStack(spacing: 6) {
                    if let p = row.prediction {
                        Text(L.s("예측 \(mrFormatDisplay(p.predictedMin))", "Predicted \(mrFormatDisplay(p.predictedMin))"))
                            .foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.secondary)
                        Text(p.inBand ? L.s("구간 안", "In range") : L.s("구간 밖", "Out of range"))
                            .foregroundStyle(p.inBand ? Theme.positive : Self.warn)
                    }
                    if let n = row.editionCount {
                        if row.prediction != nil { Text("·").foregroundStyle(.secondary) }
                        Text(L.s("\(n)회째", "#\(n)"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if row.hasPlan {
                        Button { onTapPlan?() } label: {
                            Text(L.s("계획", "Plan"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 2: 컴파일 성공 확인**

Run: 위 "컴파일 명령"
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add MIMORunning/Views/RaceRecordRow.swift
git commit -m "$(cat <<'EOF'
나 탭 참가 대회 기록 행 뷰 — 날짜·대회명·종목·완주 시간, 둘째 줄 예측·N회째·계획 버튼

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git show --stat HEAD | tail -3
```

---

### Task 5: 나 탭 — 토글·기록 목록·러닝 상세 이동

**Files:**
- Modify: `MIMORunning/Views/MeView.swift`

- [ ] **Step 1: 상태 변수 추가**

`@State private var raceToDelete: MyPlannedRace?` 줄 바로 아래에 추가:

```swift
    /// 나 탭 내비게이션 경로 — 참가 대회 기록 행이 러닝 상세(`Activity`)를 넣는다.
    @State private var navPath = NavigationPath()
    /// 참가 대회 토글. 탭에 들어올 때마다 `RaceRecordList.defaultMode`로 다시 정한다(저장 안 함).
    @State private var raceListMode: RaceListMode = .planned
    /// 러닝 상세에서 돌아올 때는 토글을 되돌리지 않기 위한 표시
    @State private var raceDetailPushed = false
    @State private var showAllRaceRecords = false
    @State private var planArchive: RaceArchive? = nil
    @State private var archiveToDelete: RaceArchive? = nil
```

- [ ] **Step 2: NavigationStack을 경로 기반으로, 이동 목적지와 기본값 설정 추가**

`var body: some View {` 안의 `NavigationStack {`를 다음으로 바꾼다:

```swift
        NavigationStack(path: $navPath) {
```

같은 NavigationStack 안의 아래 세 줄:

```swift
            .navigationTitle(AppLanguage.shared.s("나", "Me"))
            .navigationBarTitleDisplayMode(.large)
            .onAppear { manager.syncUserEfforts(from: allStories) }
```

을 다음으로 바꾼다:

```swift
            .navigationTitle(AppLanguage.shared.s("나", "Me"))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Activity.self) { activity in
                ActivityDetailView(activity: activity, manager: manager)
            }
            .onAppear {
                manager.syncUserEfforts(from: allStories)
                // 러닝 상세에서 돌아온 경우는 사용자가 고른 토글을 유지한다
                if raceDetailPushed {
                    raceDetailPushed = false
                } else {
                    raceListMode = RaceRecordList.defaultMode(plannedDates: plannedRaces.map(\.raceDate),
                                                              today: Date())
                    showAllRaceRecords = false
                }
            }
```

- [ ] **Step 3: 대회 검색 시트를 닫으면 예정으로 전환**

```swift
        .sheet(isPresented: $showRaceSearch) {
```

를 다음으로 바꾼다:

```swift
        .sheet(isPresented: $showRaceSearch, onDismiss: {
            if plannedRaces.contains(where: { !$0.isPast }) { raceListMode = .planned }
        }) {
```

- [ ] **Step 4: `plannedRacesSection` 교체**

`// MARK: - Planned races section` 아래의 `private var plannedRacesSection: some View { ... }` 전체(헤더 HStack부터 `ForEach(plannedRaces)` 분기까지, 함수 끝 중괄호까지)를 다음으로 바꾼다:

```swift
    private var plannedRacesSection: some View {
        let L = AppLanguage.shared
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(L.s("참가 대회", "My Races"))
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                raceModeChip(.planned, L.s("예정", "Upcoming"))
                raceModeChip(.records, L.s("기록", "Results"))
                Button { showRaceSearch = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.violet)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(.horizontal, 16)

            switch raceListMode {
            case .planned: plannedRacesContent
            case .records: raceRecordsContent
            }
        }
    }

    /// 예정 | 기록 칩 — 앱의 기존 칩 토글과 같은 모양(보라 채움 + 흰 글자 / 흐린 배경).
    private func raceModeChip(_ mode: RaceListMode, _ title: String) -> some View {
        let isOn = raceListMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { raceListMode = mode }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(isOn ? .white : .white.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isOn ? Theme.violet : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 예정 — 기존 행 그대로, 오늘 이후 대회만. 지난 예정 대회는 탭이 열릴 때 계획 아카이브가 되어 기록으로 간다.
    @ViewBuilder
    private var plannedRacesContent: some View {
        let L = AppLanguage.shared
        let upcoming = plannedRaces.filter { !$0.isPast }
        if upcoming.isEmpty {
            raceEmptyText(L.s("참가 예정 대회를 등록하세요", "Add races you plan to join"))
        } else {
            ForEach(upcoming) { race in
                PlannedRaceRow(race: race, locked: isRaceLocked(race)) {
                    raceToDelete = race
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func raceEmptyText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
    }

    // MARK: - 참가 대회 · 기록

    /// 확정 대회 러닝. 러닝이 아직 목록에 로드되지 않은 매칭은 빼고, 로드되면 나타난다.
    private var raceRecordRuns: [RaceRecordList.RunInput] {
        let byID = Dictionary(manager.activities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return raceDetector.matches.values
            .filter(\.isConfirmed)
            .compactMap { m in
                guard let a = byID[m.activityID] else { return nil }
                return RaceRecordList.RunInput(activityID: a.id, raceName: m.raceName,
                                               distanceKm: m.distanceKm, date: a.date,
                                               durationSec: a.duration)
            }
    }

    private var raceRecordArchives: [RaceRecordList.ArchiveInput] {
        allArchives.enumerated().map { i, a in
            RaceRecordList.ArchiveInput(index: i, raceName: a.raceName, raceDate: a.raceDate,
                                        distanceM: a.distanceM, hasResult: a.hasResult,
                                        actualMin: a.actualMin,
                                        projectedMin: a.snapshotProjectedFinalMin,
                                        hasDetail: mrArchiveHasDetail(a.markdown))
        }
    }

    /// 엔진 예측 행 중 예측이 있는 것. 라벨("5K"·"10K"·"하프"·"풀")을 km로 바꾼다.
    private var raceRecordPredictions: [RaceRecordList.PredictionInput] {
        engine.backtest.compactMap { r in
            guard let p = r.predictedMin, let e = r.errorPct else { return nil }
            return RaceRecordList.PredictionInput(date: r.date,
                                                  distanceKm: mrDistanceForLabel(r.label) / 1000,
                                                  predictedMin: p, errorPct: e, inBand: r.inBand)
        }
    }

    @ViewBuilder
    private var raceRecordsContent: some View {
        let L = AppLanguage.shared
        let runs = raceRecordRuns
        let predictions = raceRecordPredictions
        let rows = RaceRecordList.rows(runs: runs, archives: raceRecordArchives, predictions: predictions)
        VStack(alignment: .leading, spacing: 10) {
            if rows.isEmpty {
                raceEmptyText(L.s("대회를 뛰면 여기에 모여요. 러닝이 대회로 확인되면 자동으로 추가돼요.",
                                  "Your races gather here. Runs confirmed as races are added automatically."))
            } else {
                let visible = showAllRaceRecords ? rows : Array(rows.prefix(5))
                ForEach(visible) { row in
                    raceRecordRowView(row)
                        .padding(.horizontal, 16)
                }
                if rows.count > 5 {
                    Button(showAllRaceRecords ? L.s("접기", "Collapse")
                                              : L.s("전체 \(rows.count)건 보기", "Show all \(rows.count)")) {
                        withAnimation { showAllRaceRecords.toggle() }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.violet)
                    .padding(.horizontal, 16)
                }
                if let acc = RaceRecordList.accuracy(runs: runs, predictions: predictions) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.s("예측 정확도 · 구간 안 \(acc.hit)/\(acc.count) · 평균 오차 \(String(format: "%.1f", acc.meanAbsErrorPct))%",
                                 "Prediction accuracy · \(acc.hit)/\(acc.count) in range · avg error \(String(format: "%.1f", acc.meanAbsErrorPct))%"))
                        Text(L.s("예측은 그 대회 전날까지의 데이터만으로 다시 계산한 값이에요.",
                                 "Predictions are recalculated using only data from before each race."))
                        if acc.count < 3 {
                            Text(L.s("표본이 \(acc.count)건뿐입니다. 예측은 참고용이고, 특히 마라톤은 ±20분 이상 벌어질 수 있습니다.",
                                     "Only \(acc.count) sample(s). Estimates only — marathons can vary by ±20 min or more."))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                }
            }
        }
        .sheet(item: $planArchive) { arch in
            MRArchiveDetailView(archive: arch)
        }
        .confirmationDialog(
            archiveToDelete.map(\.raceName) ?? "",
            isPresented: Binding(get: { archiveToDelete != nil },
                                 set: { if !$0 { archiveToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L.s("삭제", "Delete"), role: .destructive) {
                if let arch = archiveToDelete {
                    mrDeleteArchive(arch, snapshots: allSnapshots, context: modelContext)
                }
                archiveToDelete = nil
            }
            Button(L.s("취소", "Cancel"), role: .cancel) { archiveToDelete = nil }
        } message: {
            Text(L.s("이 대회 기록을 목록에서 지웁니다. 러닝 기록 자체는 지워지지 않습니다.",
                     "Removes this race from the list. Your run itself is not deleted."))
        }
    }

    /// 행 하나 — 확정 러닝은 탭하면 러닝 상세, 러닝 없는 아카이브는 길게 눌러 삭제.
    @ViewBuilder
    private func raceRecordRowView(_ row: RaceRecordList.Row) -> some View {
        let L = AppLanguage.shared
        let archive: RaceArchive? = row.archiveIndex.flatMap { allArchives.indices.contains($0) ? allArchives[$0] : nil }
        let base = RaceRecordRow(row: row) { planArchive = archive }
        switch row.source {
        case .run(let id):
            base.onTapGesture {
                guard let activity = manager.activities.first(where: { $0.id == id }) else { return }
                raceDetailPushed = true
                navPath.append(activity)
            }
        case .archiveOnly:
            base.contextMenu {
                if let archive {
                    Button(L.s("이 대회 삭제", "Delete this race"), systemImage: "trash", role: .destructive) {
                        archiveToDelete = archive
                    }
                }
            }
        }
    }
```

주의: `allArchives`·`allSnapshots`·`modelContext`·`raceDetector`·`engine`·`isRaceLocked`는 MeView에 이미 있다. 새로 선언하지 않는다.

- [ ] **Step 5: 컴파일 성공 확인**

Run: 위 "컴파일 명령"
Expected: `** TEST BUILD SUCCEEDED **`

실패 시 흔한 원인:
- `switch` 안에서 뷰를 반환하는 부분이 `@ViewBuilder` 밖이면 에러 → `plannedRacesSection`의 `VStack` 클로저 안이므로 정상이다. 에러가 나면 `Group { switch ... }`로 감싼다.
- `raceDetector.matches`는 `[String: PersistedRaceMatch]`이고 `PersistedRaceMatch.activityID`는 `UUID`다.

- [ ] **Step 6: 커밋**

```bash
git add MIMORunning/Views/MeView.swift
git commit -m "$(cat <<'EOF'
나 탭 참가 대회에 예정|기록 토글 — 확정 대회 기록 목록, 탭하면 러닝 상세

기본은 앞으로 열릴 예정 대회가 있으면 예정, 없으면 기록(저장 안 함, 상세에서 돌아올 땐 유지).
계획 이행표는 행 안 계획 버튼, 러닝 없는 아카이브는 길게 눌러 삭제. 예측 정확도는 확정 대회만.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git show --stat HEAD | tail -3
```

---

### Task 6: 성장 탭 대회 목록 제거

**Files:**
- Modify: `MIMORunning/Views/GrowthView.swift`
- Modify: `MIMORunning/Views/MRBacktestView.swift`

- [ ] **Step 1: 성장 탭 호출 제거**

`MIMORunning/Views/GrowthView.swift`에서 다음 줄을 지운다:

```swift
                            MRBacktestView(rows: engine.backtest, confirmedMatches: Array(raceDetector.matches.values), archives: allArchives)
```

그리고 더는 쓰이지 않는 쿼리 줄을 지운다(지우기 전에 `grep -n "allArchives" MIMORunning/Views/GrowthView.swift`로 다른 사용처가 없는지 확인 — 2026-09-27 기준 선언과 위 호출 두 곳뿐):

```swift
    @Query private var allArchives: [RaceArchive]
```

- [ ] **Step 2: `MRBacktestView.swift`에서 목록 전용 코드 제거**

다음 심볼을 파일에서 통째로 지운다(선언부터 닫는 중괄호까지):

1. `private func mrBtStandardLabel(km: Double) -> String?`
2. `private func mrBtLocalizedLabel(_ raw: String) -> String`
3. `struct MRBacktestView: View` (안의 `deleteArchive` 포함)
4. `private func mrDistanceFor(label: String) -> Double`
5. `struct MRBacktestRowView: View`

남기는 것: 파일 위쪽 색 상수(`mrBtAccent`·`mrBtCard`·`mrBtGood`·`mrBtWarn` — 아래 뷰들이 씀), `struct MRArchiveDetailView`, `struct MRHealthMetricsView`, `struct MRDriftView`와 그 뒤의 코드 전부.

지운 뒤 다른 곳에서 쓰는지 확인:

```bash
grep -rn "MRBacktestView\b\|MRBacktestRowView\|mrBtStandardLabel\|mrBtLocalizedLabel\|mrDistanceFor(label" MIMORunning MIMORunningTests --include='*.swift'
```

Expected: `MRAdviceCardView.swift`의 주석 한 줄(`형제 카드(MRBacktestView 등)`)만 나온다. 주석은 그대로 둔다.

- [ ] **Step 3: 컴파일 성공 확인**

Run: 위 "컴파일 명령"
Expected: `** TEST BUILD SUCCEEDED **`
(사용하지 않게 된 private 색 상수가 있다면 경고만 나고 에러는 아니다.)

- [ ] **Step 4: 커밋**

```bash
git add MIMORunning/Views/GrowthView.swift MIMORunning/Views/MRBacktestView.swift
git commit -m "$(cat <<'EOF'
성장 탭 "예측이 얼마나 맞았나" 제거 — 나 탭 참가 대회 기록으로 옮김

목록 본체·행 뷰·전용 도우미를 지운다. 아카이브 상세·건강 습관·드리프트 뷰는 유지.
엔진의 예측 계산(backtest)은 그대로다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git show --stat HEAD | tail -4
```

---

### Task 7: 마무리 확인

- [ ] **Step 1: 전체 컴파일**

Run: 위 "컴파일 명령"
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 2: 커밋 범위 확인**

```bash
git log --oneline -6
git status --short
```

Expected: Task 1~6 커밋 6개. `git status`에는 이 작업과 무관한 `MIMORunning.xcodeproj/project.pbxproj`만 남는다(다른 세션 작업).

- [ ] **Step 3: 사용자에게 실기기 확인 목록 전달**(시뮬레이터 금지 — 사용자가 직접 확인)

1. 나 탭을 열면 예정 대회가 있으면 `예정`, 없으면 `기록`이 선택되어 있다.
2. `기록`에 확정된 대회가 최신순으로 나오고, 행을 누르면 그 러닝 상세로 간다. 뒤로 오면 `기록`이 그대로 선택되어 있다.
3. 계획을 세웠던 대회 행에 `계획` 버튼이 있고, 누르면 주차 이행표 시트가 열린다(행 이동은 일어나지 않음).
4. 계획은 있었지만 뛰지 않은 대회는 흐린 `기록 없음` 행이고, 길게 누르면 삭제할 수 있다.
5. 목록 아래 예측 정확도 줄이 보인다(예측이 있는 대회가 있을 때).
6. 성장 탭 맨 아래 `예측이 얼마나 맞았나`가 사라졌다.
7. `＋`로 대회를 등록하고 닫으면 `예정`으로 바뀐다.

---

## Self-Review 결과

- **설계 대응:** 토글·기본값(Task 2·5) · 예정 오늘 이후만(Task 5) · 기록 출처 두 가지와 같은 날 한 행(Task 2) · 대회급 훈련 러닝 제외(Task 2 테스트) · 행 탭 러닝 상세·계획 버튼(Task 4·5) · 둘째 줄 예측·N회째(Task 2·4, N회째는 A의 시리즈 칸 연결 전까지 표시 없음) · 5행 + 전체 보기 · 정확도·설명·표본 경고(Task 5) · 아카이브 길게 눌러 삭제(Task 3·5) · 빈 상태 문구(Task 5) · 상세에서 돌아올 때 토글 유지(Task 5) · 성장 탭 제거와 재사용 부분 유지(Task 6).
- **설계와 달라진 점(설계 문서에 반영함):** 지난 예정 대회는 기존 코드가 탭 진입 시 아카이브로 만든 뒤 지우므로 별도 행 출처가 없다. 러닝이 아직 로드되지 않은 확정 대회는 행을 만들지 않고 로드되면 나타난다.
- **N회째 연결:** A 구현 때 `MeView.raceRecordsContent`의 `RaceRecordList.rows(...)` 호출에 `seriesKey:`(확정 러닝 → DB 시리즈 값)를 넘긴다. 이 계획에서는 넘기지 않는다.
