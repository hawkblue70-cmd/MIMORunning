# 포인트 훈련 (계획 주차표 · 아침 제안 · 대회 없을 때) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 대회 훈련 계획의 한 주에 포인트 1회(속도·템포·빌드업·짧은 대회 페이스)를 넣고, 아침 제안이 그 포인트를 권하며, 대회가 없을 때도 롱런·포인트 2주 리듬을 제안한다.

**Architecture:** 순수 함수 파일 `Engine/MRPlanPoint.swift`에 포인트 모델·양·페이스·완료 판정·스냅샷 채우기·대회 없음 제안을 모은다. 플래너(`mrBuildPlan`)가 주차마다 `MRPlanWeek.point`를 채우고, 스냅샷(`MRPlanWeekSummary.point`)이 저장·복원한다. 아침 제안(`mrSessionSuggestion`)은 계획 주차의 포인트를, 계획이 없으면 `mrRhythmSuggestion`을 쓴다. 홈이 최근 180일 포인트 유형 러닝을 엔진에 넣는다.

**Tech Stack:** Swift 6 · SwiftUI · Swift Testing · SwiftData(스냅샷 JSON)

**설계 문서:** `docs/superpowers/specs/2026-09-29-plan-point-session-design.md` — 먼저 읽을 것.

---

## 공통 규칙 (모든 작업)

- **시뮬레이터 금지.** 테스트는 실행하지 않는다. 검증은 컴파일까지:
  ```bash
  cd /Users/hns/MIMORunning/MIMORunning && xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/claude-501/-Users-hns-MIMORunning-MIMORunning/c7613597-c399-4ba4-abca-bf01dac1d0f3/scratchpad/dd-point 2>&1 | grep -E "error:|\*\* TEST BUILD" | head -30
  ```
  기대: `** TEST BUILD SUCCEEDED **`. TDD의 "실패 확인"은 테스트를 먼저 쓰고 **컴파일이 기대한 이유로 깨지는 것**(없는 심볼)을 보는 것이다.
- **git**: 다른 세션이 같은 브랜치(`crew`)에서 동시에 일한다. `git add -A`·`git stash` 금지. 커밋은 경로를 명시한다:
  `git commit -m "…" -- <경로1> <경로2>`. `MIMORunning.xcodeproj/project.pbxproj`는 절대 커밋하지 않는다(다른 세션 변경). 새 파일은 동기화 그룹이라 프로젝트 파일을 건드리지 않아도 빌드에 들어간다.
- 커밋 메시지는 한국어, 끝에 빈 줄 + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- 테스트 파일은 Swift Testing(`import Testing`, `@testable import MIMORunning`), 스위트에 `.korean` 트레잇(한국어 문구 고정).
- 문구는 `AppLanguage.shared.s("한국어", "English")`로 두 언어를 함께 쓴다.
- 임의로 정한 값에는 주석 `⚠ 임의로 정함`을 단다(코드베이스 관례).

## 파일 구조

| 파일 | 책임 |
|---|---|
| Create `MIMORunning/Engine/MRPlanPoint.swift` | 포인트 모델·양·페이스·종류·빈도·문구·완료 판정·스냅샷 채우기·대회 없음 리듬 |
| Modify `MIMORunning/Engine/MRRacePlanner.swift` | 주차마다 `point` 계산, 이지 횟수 1 줄이기 |
| Modify `MIMORunning/Models/RacePlanSnapshot.swift` | `MRPlanWeekSummary.point` 저장·옛 JSON 호환 |
| Modify `MIMORunning/Engine/MRPlanGovernance.swift` | `applyingSnapshot`이 `point`를 스냅샷 값으로 |
| Modify `MIMORunning/Engine/MRRaceArchiveManager.swift` | 스냅샷 생성 시 `point` 포함 |
| Modify `MIMORunning/Views/MeView.swift` | 트리거 1·3·4가 `point`를 옮김, 트리거 5 추가 |
| Modify `MIMORunning/Engine/MRReadiness.swift` | 계획 포인트 세션·대회 없음 리듬 연결·판정 줄 |
| Modify `MIMORunning/Engine/MRTodayCard.swift` | 새 입력 전달 |
| Modify `MIMORunning/Engine/MREngineStore.swift` | `pointRunTypes` 보관·주입, 계획 맥락에 `point`, 리듬 맥락 조립 |
| Modify `MIMORunning/Views/ActivityListView.swift` | 180일 포인트 유형 러닝 주입 |
| Modify `MIMORunning/Views/MRRacePlanView.swift` | 주차표 포인트 줄·완료 노랑 |
| Modify `FEATURES.md` | 기능 기록 |
| Tests | `MRPlanPointTests.swift` · `MRRacePlannerPointTests.swift` · `MRPlanPointSnapshotTests.swift` · `MRSessionPointTests.swift` · `MRRhythmTests.swift` |

---

### Task 1: 포인트 모델 — 양·페이스·종류·빈도·문구

**Files:**
- Create: `MIMORunning/Engine/MRPlanPoint.swift`
- Test: `MIMORunningTests/MRPlanPointTests.swift`

- [ ] **Step 1: 테스트 먼저 쓰기**

`MIMORunningTests/MRPlanPointTests.swift`:

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("포인트 훈련 — 모델·양·페이스", .korean)
struct MRPlanPointTests {

    @Test func speedRepsAreEightPercentOfWeeklyClampedThreeToSix() throws {
        let a = try #require(MRPlanPoint.make(kind: .speed, weeklyKm: 30, longRunKm: 14, raceDistanceM: MRDistance.dH, paceSecPerKm: 300))
        #expect(a.reps == 3)                       // 2.4 → 2 → 하한 3
        #expect(abs(a.totalKm - 6.8) < 0.01)       // 2 + 3×1 + 2×0.4 + 1
        let b = try #require(MRPlanPoint.make(kind: .speed, weeklyKm: 60, longRunKm: 18, raceDistanceM: MRDistance.dH, paceSecPerKm: 300))
        #expect(b.reps == 5)                       // 4.8 → 5
        let c = try #require(MRPlanPoint.make(kind: .speed, weeklyKm: 100, longRunKm: 28, raceDistanceM: MRDistance.dF, paceSecPerKm: 300))
        #expect(c.reps == 6)                       // 8 → 상한 6
    }

    @Test func tempoIsTenPercentOfWeeklyClampedThreeToEight() throws {
        let a = try #require(MRPlanPoint.make(kind: .tempo, weeklyKm: 30, longRunKm: 14, raceDistanceM: nil, paceSecPerKm: 300))
        #expect(a.sustainedKm == 3)
        #expect(abs(a.totalKm - 6) < 0.01)         // 2 + 3 + 1
        let b = try #require(MRPlanPoint.make(kind: .tempo, weeklyKm: 50, longRunKm: 16, raceDistanceM: nil, paceSecPerKm: 300))
        #expect(b.sustainedKm == 5)
        let c = try #require(MRPlanPoint.make(kind: .tempo, weeklyKm: 100, longRunKm: 28, raceDistanceM: nil, paceSecPerKm: 300))
        #expect(c.sustainedKm == 8)
    }

    @Test func buildUpDistanceByRaceCappedBySeventyPercentOfLongRun() throws {
        let half = try #require(MRPlanPoint.make(kind: .buildUp, weeklyKm: 40, longRunKm: 16, raceDistanceM: MRDistance.dH, paceSecPerKm: 310))
        #expect(half.totalKm == 10)                // min(10, 11)
        #expect(abs((half.sustainedKm ?? 0) - 3.3) < 0.01)
        let full = try #require(MRPlanPoint.make(kind: .buildUp, weeklyKm: 50, longRunKm: 16, raceDistanceM: MRDistance.dF, paceSecPerKm: 330))
        #expect(full.totalKm == 11)                // min(14, 11.2 내림 11)
        let tenK = try #require(MRPlanPoint.make(kind: .buildUp, weeklyKm: 30, longRunKm: 12, raceDistanceM: MRDistance.d10, paceSecPerKm: 290))
        #expect(tenK.totalKm == 8)
        let noRace = try #require(MRPlanPoint.make(kind: .buildUp, weeklyKm: 40, longRunKm: 18, raceDistanceM: nil, paceSecPerKm: 310))
        #expect(noRace.totalKm == 10)
        // 롱런 6km → 4.2 내림 4 < 5 → 없음
        #expect(MRPlanPoint.make(kind: .buildUp, weeklyKm: 20, longRunKm: 6, raceDistanceM: MRDistance.dH, paceSecPerKm: 310) == nil)
    }

    @Test func racePaceShortIsThreeByOneKm() throws {
        let p = try #require(MRPlanPoint.make(kind: .racePaceShort, weeklyKm: 25, longRunKm: 10, raceDistanceM: MRDistance.dH, paceSecPerKm: 312))
        #expect(p.reps == 3)
        #expect(abs(p.totalKm - 6.8) < 0.01)
    }

    @Test func zeroPaceMakesNoPoint() {
        #expect(MRPlanPoint.make(kind: .tempo, weeklyKm: 40, longRunKm: 14, raceDistanceM: nil, paceSecPerKm: 0) == nil)
    }

    @Test func pacesComeFromHalfEquivalentByRiegel() throws {
        let p = try #require(mrPointPaces(halfEquivMin: 110))
        #expect(abs(p.half - 312.8) < 0.2)         // 110×60/21.0975
        #expect(p.fiveK < p.tenK && p.tenK < p.half)
        #expect(p.tempo > p.tenK && p.tempo < p.half)
        #expect(mrPointPaces(halfEquivMin: 5) == nil)
    }

    @Test func kindFollowsPlanPhase() {
        #expect(mrPointKind(phase: "늘리기") == .speed)
        #expect(mrPointKind(phase: "유지") == .tempo)
        #expect(mrPointKind(phase: "대회 페이스") == .buildUp)
        #expect(mrPointKind(phase: "테이퍼") == .racePaceShort)
        #expect(mrPointKind(phase: "회복") == nil)
        #expect(mrPointKind(phase: "대회 주") == nil)
        #expect(mrPointKind(phase: "10K 계획") == nil)
    }

    @Test func intervalDaysFromRunsPerWeek() {
        #expect(mrPointIntervalDays(runsPerWeek: 4.2) == 7)
        #expect(mrPointIntervalDays(runsPerWeek: 5) == 7)
        #expect(mrPointIntervalDays(runsPerWeek: 3.4) == 14)
        #expect(mrPointIntervalDays(runsPerWeek: 2.6) == 14)   // 반올림 3
        #expect(mrPointIntervalDays(runsPerWeek: 2.4) == nil)
    }

    @Test func rotationSpeedTempoBuildUp() {
        #expect(MRPlanPoint.nextKind(after: .interval) == .tempo)
        #expect(MRPlanPoint.nextKind(after: .tempo) == .buildUp)
        #expect(MRPlanPoint.nextKind(after: .buildUp) == .speed)
        #expect(MRPlanPoint.nextKind(after: .distanceRun) == .speed)
        #expect(MRPlanPoint.nextKind(after: nil) == .buildUp)
        #expect(MRPlanPoint.nextKind(after: .race) == .buildUp)
    }

    @Test func koreanText() {
        let s = MRPlanPoint(kind: .speed, totalKm: 8.2, reps: 4, repKm: 1, sustainedKm: nil, paceSecPerKm: 305)
        #expect(s.text == "속도 1km × 4회 5'05\"")
        let t = MRPlanPoint(kind: .tempo, totalKm: 8, reps: nil, repKm: nil, sustainedKm: 5, paceSecPerKm: 320)
        #expect(t.text == "템포 5km 5'20\"")
        let b = MRPlanPoint(kind: .buildUp, totalKm: 10, reps: nil, repKm: nil, sustainedKm: 3.3, paceSecPerKm: 330)
        #expect(b.text == "빌드업 10km · 마지막 3.3km 5'30\"")
        let r = MRPlanPoint(kind: .racePaceShort, totalKm: 6.8, reps: 3, repKm: 1, sustainedKm: nil, paceSecPerKm: 312)
        #expect(r.text == "대회 페이스 1km × 3회 5'12\"")
    }

    @Test func breakdownEasyNumbersReplacedKeepingLanguage() {
        #expect(mrBreakdownReplacingEasy("롱런 16km + 이지 6.4km × 3회", easyKm: 7, runs: 2) == "롱런 16km + 이지 7km × 2회")
        #expect(mrBreakdownReplacingEasy("Long run 16km + Easy 6.4km × 3x", easyKm: 5.5, runs: 2) == "Long run 16km + Easy 5.5km × 2x")
        #expect(mrBreakdownReplacingEasy("롱런 18km · 마지막 15분은 5'12\"/km + 이지 6km × 3회", easyKm: 4.2, runs: 2)
                == "롱런 18km · 마지막 15분은 5'12\"/km + 이지 4.2km × 2회")
        #expect(mrBreakdownReplacingEasy("롱런 10km + 짧게 3.5km × 3회 · 강도는 그대로", easyKm: 3, runs: 2)
                == "롱런 10km + 짧게 3km × 2회 · 강도는 그대로")
        #expect(mrBreakdownReplacingEasy("롱런 8km + 이지 3회", easyKm: 2, runs: 2) == nil)
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는지 확인**

Run: 공통 규칙의 build-for-testing 명령.
Expected: `error: cannot find 'MRPlanPoint' in scope` 류.

- [ ] **Step 3: 구현**

`MIMORunning/Engine/MRPlanPoint.swift`:

```swift
import Foundation

// MARK: - 포인트 훈련 (설계: docs/superpowers/specs/2026-09-29-plan-point-session-design.md)
//
// 한 주에 한 번, 강도를 의도적으로 올리는 날. 나머지는 이지.
// 강도 분리 자체의 근거: Stöggl & Sperlich 2014 (Front Physiol 5:33) — 9주 양극화 훈련이
//   역치 위주·고강도 위주·볼륨 위주보다 향상이 컸다.
// ⚠ 단계별 종류 배정·회수·거리는 코칭 관행이다. 통제 연구로 정해진 값이 아니다.
//   인터벌 빠른 구간 ≤ 주간 8% · 역치 구간 ≤ 주간 10%는 Daniels' Running Formula의 관행.

struct MRPlanPoint: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case speed, tempo, buildUp, racePaceShort }

    let kind: Kind
    /// 워밍업·쿨다운 포함 총 거리
    let totalKm: Double
    /// speed · racePaceShort 반복 횟수
    let reps: Int?
    /// 반복 1회 거리 (1.0)
    let repKm: Double?
    /// tempo 지속 거리 · buildUp 마지막 3분의 1
    let sustainedKm: Double?
    /// 빠른 구간 페이스 (초/km) — 예측 기록 기준, 기온 보정 전
    let paceSecPerKm: Double

    static let warmupKm = 2.0
    static let cooldownKm = 1.0
    /// 반복 사이 2분 조깅·400m — ⚠ 임의로 정함
    static let jogBetweenKm = 0.4

    /// 포인트로 세는 앱 저장 유형 — 고강도 판정(`RunSummaryBuilder.isHardRun`)의 종류 규칙과 같다.
    static let pointWorkoutTypes: Set<WorkoutType> = [.interval, .tempo, .buildUp, .distanceRun, .race]

    /// 종류와 이번 주 주간·롱런으로 양을 정한다. 만들 수 없으면 nil(페이스 없음·빌드업이 5km 미만).
    static func make(kind: Kind, weeklyKm: Double, longRunKm: Double,
                     raceDistanceM: Double?, paceSecPerKm: Double) -> MRPlanPoint? {
        guard paceSecPerKm > 0 else { return nil }
        func r1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
        switch kind {
        case .speed:
            let reps = min(max(Int((weeklyKm * 0.08).rounded()), 3), 6)
            let total = warmupKm + Double(reps) + Double(reps - 1) * jogBetweenKm + cooldownKm
            return MRPlanPoint(kind: .speed, totalKm: r1(total), reps: reps, repKm: 1.0,
                               sustainedKm: nil, paceSecPerKm: paceSecPerKm)
        case .tempo:
            let t = Double(min(max(Int((weeklyKm * 0.10).rounded()), 3), 8))
            return MRPlanPoint(kind: .tempo, totalKm: r1(warmupKm + t + cooldownKm), reps: nil, repKm: nil,
                               sustainedKm: t, paceSecPerKm: paceSecPerKm)
        case .buildUp:
            // ⚠ 임의로 정함 — 10K 이하 8km · 하프 10km · 풀 14km · 대회 없음 10km, 롱런의 70% 이하
            let base: Double
            if let d = raceDistanceM {
                base = d >= MRDistance.dF ? 14 : (d >= MRDistance.dH ? 10 : 8)
            } else {
                base = 10
            }
            let b = min(base, (longRunKm * 0.7).rounded(.down))
            guard b >= 5 else { return nil }
            return MRPlanPoint(kind: .buildUp, totalKm: b, reps: nil, repKm: nil,
                               sustainedKm: r1(b / 3), paceSecPerKm: paceSecPerKm)
        case .racePaceShort:
            let total = warmupKm + 3 + 2 * jogBetweenKm + cooldownKm
            return MRPlanPoint(kind: .racePaceShort, totalKm: r1(total), reps: 3, repKm: 1.0,
                               sustainedKm: nil, paceSecPerKm: paceSecPerKm)
        }
    }

    /// 대회 없을 때 번갈이 — 속도 → 템포 → 빌드업 → 속도. 지난 포인트를 모르면 빌드업(가장 부담이 적다).
    static func nextKind(after last: WorkoutType?) -> Kind {
        switch last {
        case .interval: return .tempo
        case .tempo: return .buildUp
        case .buildUp, .distanceRun: return .speed
        default: return .buildUp
        }
    }

    /// 주차표·아침 제안 공용 문구 — "속도 1km × 4회 5'05\"".
    var text: String {
        let L = AppLanguage.shared
        let pace = mrFormatPace(paceSecPerKm)
        switch kind {
        case .speed:
            let n = reps ?? 0
            return L.s("속도 1km × \(n)회 \(pace)", "Speed 1km × \(n) at \(pace)")
        case .tempo:
            let t = mrPointKmString(sustainedKm ?? 0)
            return L.s("템포 \(t)km \(pace)", "Tempo \(t)km at \(pace)")
        case .buildUp:
            let b = mrPointKmString(totalKm), s = mrPointKmString(sustainedKm ?? 0)
            return L.s("빌드업 \(b)km · 마지막 \(s)km \(pace)", "Build-up \(b)km · last \(s)km at \(pace)")
        case .racePaceShort:
            let n = reps ?? 0
            return L.s("대회 페이스 1km × \(n)회 \(pace)", "Race pace 1km × \(n) at \(pace)")
        }
    }
}

/// km 표기 — 정수면 "8", 아니면 "6.4". 계획 문구(eachStr)와 같은 규칙.
func mrPointKmString(_ km: Double) -> String {
    km == km.rounded() ? String(format: "%.0f", km) : String(format: "%.1f", km)
}

/// 포인트 페이스 — 예측 하프 등가에서 Riegel 1.06(`mrProjectedRefMin`과 같은 지수)으로.
struct MRPointPaces: Equatable, Sendable {
    let fiveK: Double
    let tenK: Double
    let half: Double
    /// Daniels T 페이스 ≈ 1시간 대회 페이스. 일반 러너에게 1시간은 대략 10K와 하프 사이 — ⚠ 임의로 정함(중간값)
    var tempo: Double { (tenK + half) / 2 }
}

func mrPointPaces(halfEquivMin: Double) -> MRPointPaces? {
    guard halfEquivMin > 10 else { return nil }
    func pace(_ dM: Double) -> Double { halfEquivMin * pow(dM / MRDistance.dH, 1.06) * 60 / (dM / 1000) }
    return MRPointPaces(fiveK: pace(MRDistance.d5), tenK: pace(MRDistance.d10), half: pace(MRDistance.dH))
}

/// 계획 단계 → 포인트 종류. 회복·대회 주·따르는 주(○○ 계획)는 nil.
func mrPointKind(phase: String) -> MRPlanPoint.Kind? {
    switch phase {
    case "늘리기": return .speed
    case "유지": return .tempo
    case "대회 페이스": return .buildUp
    case "테이퍼": return .racePaceShort
    default: return nil
    }
}

/// 포인트 간격(일) — 최근 주당 러닝 4회 이상 7일 · 3회 14일 · 그 아래 nil(포인트 없음).
/// 엔진에 비공개 레벨이 없어 주당 횟수로 대신한다(설계 4절).
func mrPointIntervalDays(runsPerWeek: Double) -> Int? {
    let n = Int(runsPerWeek.rounded())
    if n >= 4 { return 7 }
    if n == 3 { return 14 }
    return nil
}

/// 계획 문구의 마지막 "이지(짧게/Easy/Short) Xkm × N회(x)"에서 숫자만 바꾼다. 언어·나머지 문구는 그대로. 못 찾으면 nil.
/// (`mrParsePlanBreakdown`과 같은 패턴)
func mrBreakdownReplacingEasy(_ text: String, easyKm: Double, runs: Int) -> String? {
    guard let re = try? NSRegularExpression(pattern: #"(?:이지|짧게|Easy|Short) ([0-9]+(?:\.[0-9]+)?)km × ([0-9]+)(?:회|x)"#) else { return nil }
    let ns = text as NSString
    guard let m = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else { return nil }
    // 뒤쪽(횟수)부터 바꿔야 앞쪽(거리) 범위가 밀리지 않는다
    let replacedRuns = ns.replacingCharacters(in: m.range(at: 2), with: "\(runs)") as NSString
    return replacedRuns.replacingCharacters(in: m.range(at: 1), with: mrPointKmString(easyKm))
}
```

- [ ] **Step 4: 컴파일 확인**

Run: build-for-testing. Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git commit -m "포인트 훈련 모델 — 종류·양·페이스·빈도·문구·이지 문구 숫자 교체

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- MIMORunning/Engine/MRPlanPoint.swift MIMORunningTests/MRPlanPointTests.swift
```
(새 파일은 먼저 `git add MIMORunning/Engine/MRPlanPoint.swift MIMORunningTests/MRPlanPointTests.swift`.)

---

### Task 2: 플래너 — 주차마다 포인트, 이지 1회 줄이기

**Files:**
- Modify: `MIMORunning/Engine/MRRacePlanner.swift` (`struct MRPlanWeek` 13~32행, 루프 앞 `var forceRecovery = false`, 루프 안 `let each = …`부터 `p.weeks.append(MRPlanWeek(idx: i, …))`까지)
- Test: `MIMORunningTests/MRRacePlannerPointTests.swift`

- [ ] **Step 1: 테스트 먼저 쓰기**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("MRRacePlanner 포인트 칸", .korean)
struct MRRacePlannerPointTests {

    private func profile(runs: Double) -> MRProfile {
        var p = MRProfile()
        p.weeklyKm4w = 30; p.longestRun16wKm = 14
        p.maxWeeklyKm52w = 45; p.runsPerWeek = runs; p.marathonFinishes = 0
        return p
    }

    private func plan(distanceM: Double = MRDistance.dH, weeks: Int = 20, runs: Double = 4) -> MRRacePlan? {
        let today = Date()
        let race = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: today)!
        return mrBuildPlan(raceDate: race, distanceM: distanceM, today: today,
                           profile: profile(runs: runs), halfEquivMin: 110,
                           easyPaceSecPerKm: 400, heat: MRHeatModel(), raceTempC: 15,
                           runsPerWeek: runs)
    }

    @Test func pointKindMatchesPhase() throws {
        let p = try #require(plan())
        #expect(p.weeks.contains { $0.point != nil })
        for w in p.weeks {
            guard let pt = w.point else { continue }
            #expect(pt.kind == mrPointKind(phase: w.phase))
        }
    }

    @Test func recoveryAndRaceWeekHaveNoPoint() throws {
        let p = try #require(plan())
        #expect(p.weeks.filter { $0.phase == "회복" }.allSatisfy { $0.point == nil })
        let cal = Calendar.current
        let raceWeek = try #require(p.weeks.first { w in
            let end = cal.date(byAdding: .day, value: 7, to: w.monday)!
            return p.raceDate >= w.monday && p.raceDate < end
        })
        #expect(raceWeek.point == nil)
    }

    @Test func pointReplacesOneEasyRunAndKeepsWeeklyTotal() throws {
        let p = try #require(plan())
        let withPoint = p.weeks.filter { $0.point != nil }
        #expect(!withPoint.isEmpty)
        for w in withPoint {
            let parsed = mrParsePlanBreakdown(w.breakdown)
            #expect(parsed.easyRuns == 2)          // 주 4회 → 롱런 1 + 포인트 1 + 이지 2
            // 문구의 "롱런 Nkm"(플래너 표기값 lrDisplay)로 합을 잰다 — longRunKm(0.1 반올림)을 다시 반올림하면 14.45 같은 경계에서 1km 어긋난다
            if let km = parsed.easyKm, let pt = w.point,
               let m = w.breakdown.range(of: #"롱런 ([0-9]+)km"#, options: .regularExpression),
               let longShown = Double(w.breakdown[m].dropFirst(3).dropLast(2)) {
                let sum = longShown + pt.totalKm + km * 2
                #expect(abs(sum - w.weeklyKm) < 0.3)   // 표기 반올림 허용
                #expect(km >= 1.5)
            }
        }
        #expect(p.weeks.filter { $0.point == nil && $0.phase == "늘리기" }
            .allSatisfy { mrParsePlanBreakdown($0.breakdown).easyRuns.map { $0 == 3 } ?? true })
    }

    @Test func threeRunsPerWeekAlternates() throws {
        let p = try #require(plan(runs: 3))
        // 테이퍼를 뺀 포인트 종류 주에서 연달아 두 주 모두 포인트는 없다
        let eligible = p.weeks.filter { mrPointKind(phase: $0.phase).map { $0 != .racePaceShort } ?? false }
        #expect(eligible.count >= 4)
        for (a, b) in zip(eligible, eligible.dropFirst()) {
            #expect(!(a.point != nil && b.point != nil))
        }
        #expect(eligible.contains { $0.point != nil })
    }

    @Test func twoRunsPerWeekHasNoPoint() throws {
        let p = try #require(plan(runs: 2))
        #expect(p.weeks.allSatisfy { $0.point == nil })
    }

    @Test func tenKPlanHasNoBuildUp() throws {
        let p = try #require(plan(distanceM: MRDistance.d10, weeks: 12))
        #expect(p.weeks.allSatisfy { $0.point?.kind != .buildUp })
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는지 확인** — Expected: `value of type 'MRPlanWeek' has no member 'point'`.

- [ ] **Step 3: 구현**

(a) `struct MRPlanWeek`의 `var breakdown: String = ""` 아래에 추가:

```swift
    /// 이번 주 포인트 1회(2026-09-29) — 이지 한 번을 대신한다. 회복·대회 주·주 2회 이하면 nil.
    var point: MRPlanPoint? = nil
```

(b) 루프 앞 `var forceRecovery = false` 줄 바로 아래에 추가:

```swift
    // 주 3회는 포인트를 격주로 — 포인트 종류가 정해지는 주(테이퍼 제외)를 센다
    var pointSlot = 0
```

(c) 루프 안의 이 줄을

```swift
        let each = max(wkDisplay - lrDisplay, 0) / Double(others)
```

아래로 바꾼다:

```swift
        // ── 포인트 1회 (2026-09-29 설계) — 이지 한 번을 대신한다. 주간 km·러닝 횟수는 그대로.
        //   따르는 주는 따르는 계획의 포인트 그대로. 튠업 주·대회 전 주·대회 주·회복 주는 없음.
        let isRaceWeek = raceDate >= mon && raceDate < weekEnd
        var point: MRPlanPoint? = nil
        if let f = followed, i <= buildWeeks {
            point = f.week.point
        } else if preTune == nil, tune == nil, !isRaceWeek,
                  let kind = mrPointKind(phase: phase),
                  let interval = mrPointIntervalDays(runsPerWeek: runsPerWeek),
                  others >= 2 {
            let slotOK = interval == 7 || kind == .racePaceShort || pointSlot % 2 == 0
            if kind != .racePaceShort { pointSlot += 1 }
            if slotOK, let paces = mrPointPaces(halfEquivMin: halfEquivMin) {
                let pace: Double
                switch kind {
                case .speed: pace = paces.fiveK
                case .tempo: pace = paces.tempo
                case .buildUp, .racePaceShort:
                    pace = mrTrainingRacePaceSecPerKm(halfEquivMin: halfEquivMin, distanceM: distanceM,
                                                      weeklyKm: projVol, longestKm: peakLong,
                                                      finishes: profile.marathonFinishes)
                }
                if let pt = MRPlanPoint.make(kind: kind, weeklyKm: wkDisplay, longRunKm: lrDisplay,
                                             raceDistanceM: distanceM, paceSecPerKm: pace),
                   (wkDisplay - lrDisplay - pt.totalKm) / Double(others - 1) >= 1.5 {
                    point = pt
                }
            }
        }
        // 이지 횟수 — 포인트가 있으면 하나 줄인다. 문구의 "이지 B × N"이 이 값이다.
        let easyRuns = point == nil ? others : others - 1
        let each = max(wkDisplay - lrDisplay - (point?.totalKm ?? 0), 0) / Double(easyRuns)
```

(d) 그 아래 문구 코드에서 `others`를 `easyRuns`로 바꾼다. 바꿀 곳은 정확히 이 네 블록이다:
  - 기본 `var breakdown = each >= 1.5 ? L.s("롱런 … × \(others)회", "… × \(others)x") : String(format: …, lrDisplay, others)` — 세 군데 `others` → `easyRuns`
  - `if phase == "테이퍼" { breakdown = String(format: …, lrDisplay, eachStr, others) }` — `others` → `easyRuns`
  - `if phase == "대회 페이스" { … × \(others)회 … \(others)x … 이지 \(others)회 … Easy \(others)x }` — 네 군데 → `easyRuns`
  - `else if let pt = preTune, … String(format: …, label, lrDisplay, eachStr, others)` — `others` → `easyRuns`
  튠업 블록(`if let t = tune, followed == nil { … n - 1 … n - 2 … }`)은 그대로 둔다(그 주는 포인트가 없다).

(e) 루프 끝 `p.weeks.append(MRPlanWeek(idx: i, …, breakdown: breakdown))`에 `point`를 넘긴다:

```swift
        p.weeks.append(MRPlanWeek(idx: i, monday: mon, phase: phase,
                                  longRunKm: (lr * 10).rounded() / 10,
                                  longRunMin: mins.rounded(),
                                  weeklyKm: (wkVol * 10).rounded() / 10,
                                  projectedMin: proj, isNewMax: newMax,
                                  isVolRecord: isVR,
                                  breakdown: breakdown,
                                  point: point))
```

- [ ] **Step 4: 컴파일 확인** — `** TEST BUILD SUCCEEDED **`. 기존 `MRRacePlannerRacePaceTests.halfPlanGetsRacePaceWeeksWithSegmentText`가 기대하는 "대회 페이스가 아닌 주에 /km 없음"은 포인트 문구가 안내 문구에 안 들어가므로 유지된다.

- [ ] **Step 5: 커밋**

```bash
git add MIMORunningTests/MRRacePlannerPointTests.swift
git commit -m "플래너 — 주차마다 포인트 1회(단계별 종류·주 3회 격주·주 2회 없음), 이지 횟수 하나 줄임

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- MIMORunning/Engine/MRRacePlanner.swift MIMORunningTests/MRRacePlannerPointTests.swift
```

---

### Task 3: 스냅샷이 포인트를 저장·복원

**Files:**
- Modify: `MIMORunning/Models/RacePlanSnapshot.swift` (`MRPlanWeekSummary`)
- Modify: `MIMORunning/Engine/MRPlanGovernance.swift` (`applyingSnapshot`)
- Modify: `MIMORunning/Engine/MRRaceArchiveManager.swift:41` (`mrBuildSnapshotData`)
- Modify: `MIMORunning/Views/MeView.swift` (트리거 1·3·4의 `MRPlanWeekSummary(` 생성 5곳)
- Modify: `MIMORunning/Views/MRRacePlanView.swift:398` (`displaySnap`)
- Test: `MIMORunningTests/MRPlanPointSnapshotTests.swift`

- [ ] **Step 1: 테스트 먼저 쓰기**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("스냅샷 포인트 칸", .korean)
struct MRPlanPointSnapshotTests {

    private let mon = Date(timeIntervalSince1970: 1_791_000_000)
    private let pt = MRPlanPoint(kind: .speed, totalKm: 7.2, reps: 4, repKm: 1, sustainedKm: nil, paceSecPerKm: 300)

    private func decode(_ json: String) throws -> [MRPlanWeekSummary] {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
        return try d.decode([MRPlanWeekSummary].self, from: Data(json.utf8))
    }

    @Test func oldJSONWithoutPointDecodesAsNil() throws {
        let weeks = try decode(#"[{"idx":1,"monday":1791000000,"phase":"늘리기","longRunKm":14,"weeklyKm":30,"breakdown":"롱런 14km + 이지 5.3km × 3회"}]"#)
        #expect(weeks.count == 1)
        #expect(weeks[0].point == nil)
    }

    @Test func pointRoundTrips() throws {
        let s = MRPlanWeekSummary(idx: 1, monday: mon, phase: "늘리기", longRunKm: 14, weeklyKm: 30,
                                  breakdown: "롱런 14km + 이지 4.4km × 2회", point: pt)
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        let json = String(data: try e.encode([s]), encoding: .utf8)!
        #expect(try decode(json)[0].point == pt)
    }

    @Test func applyingSnapshotUsesSnapshotPointEvenWhenNil() {
        let live = MRPlanWeek(idx: 1, monday: mon, phase: "늘리기", longRunKm: 14, longRunMin: 90, weeklyKm: 30,
                              projectedMin: 110, isNewMax: false, breakdown: "롱런 14km + 이지 4.4km × 2회", point: pt)
        let snapNoPoint = MRPlanWeekSummary(idx: 1, monday: mon, phase: "늘리기", longRunKm: 14, weeklyKm: 30,
                                            breakdown: "롱런 14km + 이지 5.3km × 3회")
        // 이번 주처럼 스냅샷에 포인트가 없으면 라이브 포인트가 새어 들지 않는다
        #expect(MRPlanGovernance.applyingSnapshot([live], snapshot: [snapNoPoint], easyPaceSecPerKm: 400)[0].point == nil)
        let snapWithPoint = MRPlanWeekSummary(idx: 1, monday: mon, phase: "늘리기", longRunKm: 14, weeklyKm: 30,
                                              breakdown: "롱런 14km + 이지 4.4km × 2회", point: pt)
        #expect(MRPlanGovernance.applyingSnapshot([live], snapshot: [snapWithPoint], easyPaceSecPerKm: 400)[0].point == pt)
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는지 확인** — Expected: `extra argument 'point' in call`.

- [ ] **Step 3: 구현**

(a) `RacePlanSnapshot.swift`의 `MRPlanWeekSummary`:

```swift
struct MRPlanWeekSummary: Codable {
    let idx: Int
    let monday: Date
    let phase: String
    let longRunKm: Double
    let weeklyKm: Double
    var breakdown: String   // 실행 안내
    /// 포인트 1회(2026-09-29) — 옛 스냅샷엔 없다(nil). 이미 시작한 계획은 트리거 5가 다음 주부터 채운다.
    var point: MRPlanPoint?

    init(idx: Int, monday: Date, phase: String,
         longRunKm: Double, weeklyKm: Double, breakdown: String = "", point: MRPlanPoint? = nil) {
        self.idx = idx; self.monday = monday; self.phase = phase
        self.longRunKm = longRunKm; self.weeklyKm = weeklyKm
        self.breakdown = breakdown
        self.point = point
    }
```

그리고 `init(from decoder:)`의 `breakdown = …` 줄 아래에:

```swift
        point     = (try? c.decodeIfPresent(MRPlanPoint.self, forKey: .point)) ?? nil
```

(b) `MRPlanGovernance.applyingSnapshot`의 `return MRPlanWeek(…)`에 마지막 인자 추가 — **스냅샷 값 그대로**(nil이면 nil):

```swift
            return MRPlanWeek(idx: w.idx, monday: w.monday, phase: s.phase,
                              longRunKm: s.longRunKm, longRunMin: mins.rounded(),
                              weeklyKm: s.weeklyKm, projectedMin: w.projectedMin,
                              isNewMax: w.isNewMax, isVolRecord: w.isVolRecord,
                              breakdown: s.breakdown.isEmpty ? w.breakdown : s.breakdown,
                              point: s.point)
```

주석 한 줄 추가: `// 포인트도 스냅샷 값 — 옛 스냅샷의 이번 주(nil)에 라이브 포인트가 새어 들지 않게(설계 6절 "이번 주 공백")`

(c) `mrBuildSnapshotData`: `breakdown: w.breakdown)` → `breakdown: w.breakdown, point: w.point)`.

(d) `MeView.saveSnapshotsIfNeeded`:
  - 트리거 3 `merged`의 `return MRPlanWeekSummary(… phase: live.phase, … breakdown: live.breakdown)` → 끝에 `, point: live.point`
  - 트리거 4 `appended.append(MRPlanWeekSummary(… breakdown: w.breakdown))` → `, point: w.point`
  - 트리거 1의 `MRPlanWeekSummary(` 세 곳(테이퍼 `phase: "테이퍼"`, `phase: "유지"`, 그리고 `corrected` 안) → 각각 끝에 `, point: snap.point`

(e) `MRRacePlanView.displaySnap`: `breakdown: live.breakdown)` → `breakdown: live.breakdown, point: live.point)`.

- [ ] **Step 4: 컴파일 확인** — `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunningTests/MRPlanPointSnapshotTests.swift
git commit -m "스냅샷 포인트 칸 — 저장·옛 JSON 호환·확정 주차는 스냅샷 포인트 그대로, 트리거가 포인트를 옮김

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- MIMORunning/Models/RacePlanSnapshot.swift MIMORunning/Engine/MRPlanGovernance.swift MIMORunning/Engine/MRRaceArchiveManager.swift MIMORunning/Views/MeView.swift MIMORunning/Views/MRRacePlanView.swift MIMORunningTests/MRPlanPointSnapshotTests.swift
```

---

### Task 4: 트리거 5 — 이미 시작한 계획의 다음 주부터 포인트 채우기

**Files:**
- Modify: `MIMORunning/Engine/MRPlanPoint.swift` (함수 추가)
- Modify: `MIMORunning/Views/MeView.swift` (트리거 3·4 `do { … }` 블록 바로 뒤, `// ── Trigger 1:` 앞)
- Test: `MIMORunningTests/MRPlanPointSnapshotTests.swift` (케이스 추가)

- [ ] **Step 1: 테스트 추가** — `MRPlanPointSnapshotTests` 안에:

```swift
    private func wk(_ offset: Int) -> Date {
        let cal = Calendar.current
        let thisMon = MRPlanGovernance.weekMonday(of: Date())
        return cal.date(byAdding: .day, value: 7 * offset, to: thisMon)!
    }

    private func liveWeek(_ offset: Int, phase: String = "늘리기", point: MRPlanPoint?) -> MRPlanWeek {
        MRPlanWeek(idx: offset + 5, monday: wk(offset), phase: phase, longRunKm: 16, longRunMin: 100, weeklyKm: 40,
                   projectedMin: 110, isNewMax: false, breakdown: "롱런 16km + 이지 5.7km × 2회", point: point)
    }

    private func snapWeek(_ offset: Int, phase: String = "늘리기", point: MRPlanPoint? = nil,
                          breakdown: String = "롱런 16km + 이지 8km × 3회") -> MRPlanWeekSummary {
        MRPlanWeekSummary(idx: offset + 5, monday: wk(offset), phase: phase, longRunKm: 16, weeklyKm: 40,
                          breakdown: breakdown, point: point)
    }

    @Test func fillsOnlyFutureWeeksWithSamePhase() {
        let thisMon = wk(0)
        let r = mrFillSnapshotPoints(
            snapshot: [snapWeek(-1), snapWeek(0), snapWeek(1), snapWeek(2, phase: "유지")],
            live: [liveWeek(-1, point: pt), liveWeek(0, point: pt), liveWeek(1, point: pt), liveWeek(2, phase: "늘리기", point: pt)],
            thisMonday: thisMon, raceDistanceM: MRDistance.dH)
        #expect(r.filled == 1)
        #expect(r.weeks[0].point == nil)          // 지난 주
        #expect(r.weeks[1].point == nil)          // 이번 주 — 공백
        #expect(r.weeks[2].point?.kind == .speed) // 다음 주
        #expect(r.weeks[3].point == nil)          // 단계가 다르면 건너뜀
        // 양은 스냅샷 자신의 주간(40)으로: 40×0.08=3.2 → 3회, 총 6.8 · 이지 (40−16−6.8)/2 = 8.6
        #expect(r.weeks[2].point?.reps == 3)
        #expect(r.weeks[2].breakdown == "롱런 16km + 이지 8.6km × 2회")
    }

    @Test func alreadyFilledOrUnparsableWeeksAreLeftAlone() {
        let thisMon = wk(0)
        let r = mrFillSnapshotPoints(
            snapshot: [snapWeek(1, point: pt), snapWeek(2, breakdown: "롱런 16km + 이지 3회")],
            live: [liveWeek(1, point: pt), liveWeek(2, point: pt)],
            thisMonday: thisMon, raceDistanceM: MRDistance.dH)
        #expect(r.filled == 0)
        #expect(r.weeks[1].point == nil)
    }
```

- [ ] **Step 2: 컴파일이 깨지는지 확인** — Expected: `cannot find 'mrFillSnapshotPoints' in scope`.

- [ ] **Step 3: 구현**

(a) `MRPlanPoint.swift` 끝에 추가:

```swift
/// 트리거 5 — 이미 시작한 계획의 스냅샷에 포인트 칸 채우기(설계 6절).
/// 다음 주(thisMonday 뒤)부터, 스냅샷 주에 point가 없고 같은 월요일 라이브 주가 **같은 단계**로 point를 가질 때만.
/// 종류·페이스는 라이브, 양은 스냅샷 자신의 주간·롱런으로 다시 잰다. 이지 문구는 숫자만 바꾼다.
/// 이지 1회가 1.5km 아래로 내려가거나 문구를 못 읽으면 그 주는 건너뛴다. 지난 주·이번 주는 건드리지 않는다.
func mrFillSnapshotPoints(snapshot: [MRPlanWeekSummary], live: [MRPlanWeek], thisMonday: Date,
                          raceDistanceM: Double, calendar: Calendar = .current) -> (weeks: [MRPlanWeekSummary], filled: Int) {
    let liveByMonday = Dictionary(live.map { (calendar.startOfDay(for: $0.monday), $0) },
                                  uniquingKeysWith: { a, _ in a })
    let thisMon = calendar.startOfDay(for: thisMonday)
    var filled = 0
    let weeks = snapshot.map { s -> MRPlanWeekSummary in
        let mon = calendar.startOfDay(for: s.monday)
        guard s.point == nil, mon > thisMon,
              let lw = liveByMonday[mon], lw.phase == s.phase, let lp = lw.point else { return s }
        let parsed = mrParsePlanBreakdown(s.breakdown)
        guard let runs = parsed.easyRuns, runs >= 2, parsed.easyKm != nil else { return s }
        let long = s.longRunKm.rounded()   // 플래너 문구와 같은 표기값(lrDisplay)
        guard let pt = MRPlanPoint.make(kind: lp.kind, weeklyKm: s.weeklyKm, longRunKm: long,
                                        raceDistanceM: raceDistanceM, paceSecPerKm: lp.paceSecPerKm) else { return s }
        let easyKm = ((s.weeklyKm - long - pt.totalKm) / Double(runs - 1) * 10).rounded() / 10
        guard easyKm >= 1.5, let bd = mrBreakdownReplacingEasy(s.breakdown, easyKm: easyKm, runs: runs - 1) else { return s }
        filled += 1
        var out = s
        out.breakdown = bd
        out.point = pt
        return out
    }
    return (weeks, filled)
}
```

(b) `MeView.saveSnapshotsIfNeeded` — 트리거 3·4의 `do { … }` 블록이 끝난 바로 뒤, `// ── Trigger 1: targetLongKm 규칙 변경` 주석 앞에 추가:

```swift
            // ── Trigger 5: 포인트 칸 채우기(2026-09-29) — 이미 시작한 계획은 다음 주부터 ──
            // 포인트는 롱런·주간 km를 바꾸지 않고 이지 한 번의 성격만 바꾼다. 지난 주·이번 주는 그대로(설계 6절).
            do {
                let r = mrFillSnapshotPoints(snapshot: existing.planWeeks, live: check.plan.weeks,
                                             thisMonday: thisMonday, raceDistanceM: check.race.distanceM)
                if r.filled > 0 {
                    let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
                    if let wd = try? enc.encode(r.weeks), let wj = String(data: wd, encoding: .utf8) {
                        existing.weeksJSON = wj
                    }
                    #if DEBUG
                    print("[스냅샷] 포인트 칸 채움 → \(r.filled)주: \(check.race.name)")
                    #endif
                }
            }
```

- [ ] **Step 4: 컴파일 확인** — `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git commit -m "트리거 5 — 이미 시작한 계획은 다음 주부터 포인트 칸 채움(같은 단계만, 양은 스냅샷 주간으로)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- MIMORunning/Engine/MRPlanPoint.swift MIMORunning/Views/MeView.swift MIMORunningTests/MRPlanPointSnapshotTests.swift
```

---

### Task 5: 포인트 완료 판정 + 홈에서 포인트 유형 러닝 주입

**Files:**
- Modify: `MIMORunning/Engine/MRPlanPoint.swift` (함수 추가)
- Modify: `MIMORunning/Engine/MREngineStore.swift` (`hardRunStarts` 선언 아래·`updateHardRunStarts` 아래)
- Modify: `MIMORunning/Views/ActivityListView.swift` (`pushHardRunStarts` 끝)
- Test: `MIMORunningTests/MRPlanPointTests.swift` (케이스 추가)

- [ ] **Step 1: 테스트 추가** — `MRPlanPointTests` 안에:

```swift
    private func run(_ day: Int, km: Double) -> MRWorkout {
        let start = Date(timeIntervalSince1970: 1_791_000_000 + Double(day) * 86_400)
        return MRWorkout(start: start, durationMin: km * 6, distanceKm: km, hrAvg: 145, hrMax: 170,
                         tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }

    @Test func pointRunExcludesTheLongRunAndUsesHardOrType() {
        let easy = run(0, km: 8), hard = run(2, km: 9), long = run(5, km: 16)
        // 고강도 판정으로
        #expect(mrPointRun(weekRuns: [easy, hard, long], longRunKm: 16, hardStarts: [hard.start], pointTypes: [:])?.start == hard.start)
        // 저장 유형으로
        #expect(mrPointRun(weekRuns: [easy, hard, long], longRunKm: 16, hardStarts: [], pointTypes: [hard.start: .tempo])?.start == hard.start)
        // 롱런 · 빌드업 하나만 — 롱런이 우선, 포인트는 미완료
        #expect(mrPointRun(weekRuns: [easy, long], longRunKm: 16, hardStarts: [long.start], pointTypes: [long.start: .buildUp]) == nil)
        // 포인트 유형이 아니면 아님
        #expect(mrPointRun(weekRuns: [easy, hard], longRunKm: 16, hardStarts: [], pointTypes: [hard.start: .easy]) == nil)
        // 롱런 없는 주(0)면 제외 없음
        #expect(mrPointRun(weekRuns: [long], longRunKm: 0, hardStarts: [long.start], pointTypes: [:])?.start == long.start)
    }
```

- [ ] **Step 2: 컴파일이 깨지는지 확인** — `cannot find 'mrPointRun' in scope`.

- [ ] **Step 3: 구현**

(a) `MRPlanPoint.swift` 끝에:

```swift
/// 그 주 포인트를 했는가 — 롱런으로 센 러닝(거리 ≥ 롱런×0.8 중 가장 긴 것 하나)을 뺀 나머지 중
/// 고강도 판정(`hardStarts`, 앱 판정 최근 15일)이거나 저장 유형이 포인트 유형(`pointTypes`, 최근 180일)인 러닝.
/// 가장 이른 것을 돌려준다. 주차표와 아침 제안이 같이 쓴다(설계 7절).
func mrPointRun(weekRuns: [MRWorkout], longRunKm: Double, hardStarts: Set<Date>,
                pointTypes: [Date: WorkoutType]) -> MRWorkout? {
    let longCounted: Date? = longRunKm > 0
        ? weekRuns.filter { ($0.distanceKm ?? 0) >= longRunKm * MRPlanWeekContext.longRunDoneFraction }
                  .max { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }?.start
        : nil
    return weekRuns
        .filter { $0.start != longCounted }
        .filter { w in
            hardStarts.contains(w.start)
                || (pointTypes[w.start].map { MRPlanPoint.pointWorkoutTypes.contains($0) } ?? false)
        }
        .min { $0.start < $1.start }
}
```

(b) `MREngineStore` — `@Published private(set) var hardRunStarts: Set<Date> = []` 아래에:

```swift
    /// 앱 저장 유형이 포인트 유형(인터벌·템포·빌드업·거리주·대회)인 러닝의 시작 시각 → 유형. 최근 180일, 홈이 주입(`updatePointRunTypes`).
    /// 고강도 집합(15일)으로는 지난 주차의 포인트 완료와 대회 없을 때 번갈이를 못 본다.
    @Published private(set) var pointRunTypes: [Date: WorkoutType] = [:]
```

`func updateHardRunStarts(_ starts: Set<Date>) { … }` 함수 바로 뒤에:

```swift
    /// 홈이 포인트 유형 러닝을 넣어 준다. 바뀌었을 때만 오늘 카드를 다시 만든다.
    func updatePointRunTypes(_ types: [Date: WorkoutType]) {
        guard types != pointRunTypes else { return }
        pointRunTypes = types
        guard case .ready = state else { return }
        todayCard = buildTodayCard(runs: runs, now: Date())
    }
```

(c) `ActivityListView.pushHardRunStarts()` — 마지막 줄 `engine.updateHardRunStarts(Set(starts))` 아래에:

```swift
        // 포인트 유형 러닝(최근 180일) — 지난 주차 포인트 완료·대회 없을 때 번갈이용. UserDefaults는 한 번만 읽는다.
        let lookup = manager.workoutTypeLookup()
        let since180 = Calendar.current.date(byAdding: .day, value: -180, to: Date()) ?? .distantPast
        var pointTypes: [Date: WorkoutType] = [:]
        for a in manager.activities where a.type == .running && a.date >= since180 {
            if let t = lookup(a.id), MRPlanPoint.pointWorkoutTypes.contains(t) { pointTypes[a.date] = t }
        }
        engine.updatePointRunTypes(pointTypes)
```

- [ ] **Step 4: 컴파일 확인** — `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git commit -m "포인트 완료 판정(롱런 제외·고강도 또는 포인트 유형) + 홈이 180일 포인트 유형 러닝 주입

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- MIMORunning/Engine/MRPlanPoint.swift MIMORunning/Engine/MREngineStore.swift MIMORunning/Views/ActivityListView.swift MIMORunningTests/MRPlanPointTests.swift
```

---

### Task 6: 아침 제안 — 계획 주차의 포인트

**Files:**
- Modify: `MIMORunning/Engine/MRReadiness.swift` (`MRReadiness`, `MRPlanWeekContext`, `MRSessionSuggestion`, `mrSessionSuggestion`, `mrReadiness`)
- Modify: `MIMORunning/Engine/MRTodayCard.swift` (`mrTodayCard` 인자)
- Modify: `MIMORunning/Engine/MREngineStore.swift` (`planWeekContext`, `buildTodayCard`)
- Test: `MIMORunningTests/MRSessionPointTests.swift`

- [ ] **Step 1: 테스트 먼저 쓰기**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("아침 제안 — 계획 포인트", .korean)
struct MRSessionPointTests {

    private let cal = Calendar.current
    /// 2026-10-12(월) 주. 요일 오프셋 0=월 … 6=일.
    private func day(_ offset: Int, hour: Int = 8) -> Date {
        let mon = cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        return cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: mon)!)!
    }
    private func run(_ offset: Int, km: Double) -> MRWorkout {
        MRWorkout(start: day(offset, hour: 7), durationMin: km * 6, distanceKm: km, hrAvg: 140, hrMax: 170,
                  tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }
    /// 지난 8주 화·목 8km, 토 16km → 습관 롱런 요일 토요일(7)
    private func history() -> [MRWorkout] {
        (1...8).flatMap { w in [run(-7 * w + 1, km: 8), run(-7 * w + 3, km: 8), run(-7 * w + 5, km: 16)] }
            .sorted { $0.start < $1.start }
    }
    private let pt = MRPlanPoint(kind: .speed, totalKm: 7.2, reps: 4, repKm: 1, sustainedKm: nil, paceSecPerKm: 305)
    private func plan(point: MRPlanPoint?) -> MRPlanWeekContext {
        var c = MRPlanWeekContext(phase: "늘리기", longRunKm: 16, weeklyKm: 40, easyRuns: point == nil ? 3 : 2,
                                  racePaceSecPerKm: nil, racePaceSegmentMin: nil, daysToRace: 60, easyKm: 8.4)
        c.point = point
        return c
    }

    @Test func goOnThursdaySuggestsPoint() throws {
        let s = try #require(mrSessionSuggestion(level: .go, plan: plan(point: pt), runs: history(), asOf: day(3)))
        #expect(s.isPoint)
        #expect(s.session == "포인트 속도 1km × 4회 5'05\"")
        #expect(s.progress.contains("포인트 아직"))
    }

    @Test func dayBeforeHabitualLongRunIsEasyNotPoint() throws {
        // 금요일(4) — 내일이 습관 롱런 요일(토)
        let s = try #require(mrSessionSuggestion(level: .go, plan: plan(point: pt), runs: history(), asOf: day(4)))
        #expect(!s.isPoint)
        #expect(!s.isLongRun)
    }

    @Test func habitualDayStillLongRunFirst() throws {
        let s = try #require(mrSessionSuggestion(level: .go, plan: plan(point: pt), runs: history(), asOf: day(5)))
        #expect(s.isLongRun)
        // 토요일 남은 날 2 → 포인트는 건너뛰어도 된다
        #expect(s.progress.contains("건너뛰어도"))
    }

    @Test func pointDoneThisWeekCountsAndEasyCountExcludesIt() throws {
        let hardTue = run(1, km: 8)
        let runs = history() + [hardTue]
        let s = try #require(mrSessionSuggestion(level: .go, plan: plan(point: pt), runs: runs, asOf: day(3),
                                                 hardStarts: [hardTue.start]))
        #expect(!s.isPoint)
        #expect(s.progress.contains("포인트 완료"))
        #expect(s.progress.contains("이지 0/2회"))
    }

    @Test func noPointInPlanKeepsOldProgress() throws {
        let s = try #require(mrSessionSuggestion(level: .go, plan: plan(point: nil), runs: history(), asOf: day(3)))
        #expect(!s.isPoint)
        #expect(!s.progress.contains("포인트"))
    }

    @Test func readinessLineForPointSessionKeepsVerdictHead() {
        var r = MRReadiness(level: .go, reasons: [], hrvPending: false)
        r.session = "포인트 속도 1km × 4회 5'05\""
        r.sessionIsPoint = true
        #expect(r.line == "오늘은 강도 OK · 포인트 속도 1km × 4회 5'05\"")
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는지 확인** — `value of type 'MRSessionSuggestion' has no member 'isPoint'` 등.

- [ ] **Step 3: 구현** (`MRReadiness.swift`)

(a) `struct MRReadiness`의 `var sessionIsLongRun: Bool = false` 아래에:

```swift
    /// 세션이 포인트인가 — 판정 줄을 "오늘은 강도 OK · 포인트 …"로 둔다(이지용 "강도 여유 있음" 문형을 쓰지 않는다)
    var sessionIsPoint: Bool = false
```

`var line`의 조건 `if level == .go, let sess = session, !sessionIsLongRun {` 를 다음으로:

```swift
        if level == .go, let sess = session, !sessionIsLongRun, !sessionIsPoint {
```

(b) `struct MRPlanWeekContext`의 `var easyKm: Double? = nil` 아래에:

```swift
    /// 이번 주 포인트(스냅샷 값 — 이미 시작한 계획의 이번 주는 nil, 설계 6절)
    var point: MRPlanPoint? = nil
```

(c) `struct MRSessionSuggestion`을:

```swift
struct MRSessionSuggestion: Equatable {
    let session: String?
    let progress: String
    var isLongRun: Bool = false
    /// 세션이 포인트인가(계획 포인트·대회 없을 때 추천)
    var isPoint: Bool = false
    /// "왜" 문장 뒤에 덧붙일 한 문장 — 강도 여유가 있는데 이지를 권하는 날, 그 여유를 어디에 쓸지
    var whyNote: String? = nil
}
```

(d) `mrSessionSuggestion` 전체를 아래로 교체:

```swift
/// 오늘 판정 + 이번 주 계획 → 오늘 세션과 진행. 대회 주면 nil(D-day 카드 담당).
/// 강도 OK 우선순위: 롱런(습관 요일·남은 날 ≤2) > 포인트(남은 날 ≥3, 롱런 습관 요일 전날 아님) > 이지. 설계 8절.
func mrSessionSuggestion(level: MRReadiness.Level, plan: MRPlanWeekContext, runs: [MRWorkout],
                         asOf: Date, hardStarts: Set<Date> = [], pointTypes: [Date: WorkoutType] = [:],
                         calendar: Calendar = .current) -> MRSessionSuggestion? {
    let L = AppLanguage.shared
    guard plan.daysToRace > MRPlanWeekContext.raceWeekDays else { return nil }
    let today = calendar.startOfDay(for: asOf)
    let monday = MRPlanGovernance.weekMonday(of: asOf, calendar: calendar)
    guard let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) else { return nil }
    let week = runs.filter { $0.start >= monday && $0.start < nextMonday }
    let longDone = plan.longRunKm > 0 && week.contains { ($0.distanceKm ?? 0) >= plan.longRunKm * MRPlanWeekContext.longRunDoneFraction }
    // 포인트 — 롱런으로 센 러닝을 뺀 고강도·포인트 유형 러닝(주차표와 같은 함수)
    let pointDone = plan.point != nil
        && mrPointRun(weekRuns: week, longRunKm: plan.longRunKm, hardStarts: hardStarts, pointTypes: pointTypes) != nil
    let pointLeft = plan.point != nil && !pointDone
    let easyDone = min(max(week.count - (longDone ? 1 : 0) - (pointDone ? 1 : 0), 0), plan.easyRuns)
    let daysLeft = max(7 - (calendar.dateComponents([.day], from: monday, to: today).day ?? 0), 1)   // 오늘 포함, 일요일이면 1
    let longLeft = plan.longRunKm > 0 && !longDone

    // 이지 1회 거리 — 훈련일지 문구에서 읽은 값이 우선
    let easyKm = plan.easyKm ?? (max(plan.weeklyKm - plan.longRunKm - (plan.point?.totalKm ?? 0), 0) / Double(max(plan.easyRuns, 1)))
    // 일지와 같은 자릿수 — 정수면 "8km", 아니면 "6.4km"
    let easyKmStr = abs(easyKm - easyKm.rounded()) < 0.05 ? String(format: "%.0f", easyKm) : String(format: "%.1f", easyKm)
    let easyText = easyKm >= 1.5
        ? L.s("이지 \(easyKmStr)km", "Easy \(easyKmStr)km")
        : L.s("이지런", "Easy run")
    var longText = L.s("롱런 \(Int(plan.longRunKm.rounded()))km", "Long run \(Int(plan.longRunKm.rounded()))km")
    if let pace = plan.racePaceSecPerKm, let seg = plan.racePaceSegmentMin, pace > 0 {
        longText += L.s(", 마지막 \(seg)분 \(mrFormatPace(pace))", ", last \(seg) min at \(mrFormatPace(pace))")
    }

    // 진행
    var progress: [String] = []
    if plan.longRunKm > 0 {
        progress.append(longDone ? L.s("이번 주 롱런 완료", "long run done this week") : L.s("이번 주 롱런 아직", "long run still to do this week"))
    }
    if plan.point != nil {
        progress.append(pointDone ? L.s("포인트 완료", "workout done") : L.s("포인트 아직", "workout still to do"))
    }
    progress.append(L.s("이지 \(easyDone)/\(plan.easyRuns)회", "easy \(easyDone)/\(plan.easyRuns)"))
    // 주 끝에 포인트를 몰아넣지 않는다 — 남은 날 2일 이하면 이번 주 포인트는 건너뛴다(다음 주로 미루지 않음)
    let pointSkippable = pointLeft && daysLeft <= 2
    if pointSkippable {
        progress.append(L.s("포인트는 이번 주 건너뛰어도 괜찮아요", "fine to skip this week's workout"))
    }

    // 세션
    let allDone = !longLeft && (!pointLeft || pointSkippable) && easyDone >= plan.easyRuns
    if allDone {
        return MRSessionSuggestion(session: nil, progress: L.s("이번 주 계획 완료", "this week's plan is done"))
    }
    switch level {
    case .rest:
        if longLeft && daysLeft <= 2 {
            progress.append(L.s("롱런은 이번 주 못 하면 다음 주로", "if the long run doesn't fit this week, move it to next week"))
        }
        return MRSessionSuggestion(session: nil, progress: progress.joined(separator: " · "))
    case .go:
        let habitual = mrHabitualLongRunWeekday(runs: runs, asOf: asOf, calendar: calendar)
        let todayWD = calendar.component(.weekday, from: asOf)
        if longLeft && (habitual == todayWD || daysLeft <= 2) {
            return MRSessionSuggestion(session: longText, progress: progress.joined(separator: " · "), isLongRun: true)
        }
        // 포인트 — 롱런 습관 요일 전날은 피한다(다음 날 아침 제안이 "어제 고강도 → 이지"를 내 롱런이 밀린다)
        let tomorrowWD = todayWD % 7 + 1
        if let pt = plan.point, pointLeft, daysLeft >= 3, habitual != tomorrowWD {
            return MRSessionSuggestion(session: L.s("포인트 \(pt.text)", "Workout: \(pt.text)"),
                                       progress: progress.joined(separator: " · "), isPoint: true)
        }
        // 강도 여유는 있지만 오늘은 롱런·포인트 날이 아니다 — 여유를 이번 주 롱런에 남겨 두라고 말한다
        let note: String? = longLeft
            ? (habitual.map { L.s("여유는 \(mrWeekdayName($0)) 롱런에 쓰세요.", "Save it for \(mrWeekdayName($0))'s long run.") }
               ?? L.s("여유는 이번 주 롱런에 쓰세요.", "Save it for this week's long run."))
            : nil
        return MRSessionSuggestion(session: easyText, progress: progress.joined(separator: " · "), whyNote: note)
    case .easy:
        if longLeft { progress.append(L.s("\(daysLeft)일 남음", "\(daysLeft) days left")) }
        return MRSessionSuggestion(session: easyText, progress: progress.joined(separator: " · "))
    }
}
```

(e) `mrReadiness` 시그니처에 인자 추가(`planWeek:` 뒤, `calendar:` 앞):

```swift
                 planWeek: MRPlanWeekContext? = nil,
                 pointRunTypes: [Date: WorkoutType] = [:],
                 rhythm: MRRhythmContext? = nil,
                 calendar: Calendar = .current) -> MRReadiness? {
```

`rhythm`은 Task 7에서 쓰는 타입이다. 이 작업에서는 `MRPlanPoint.swift` 끝에 **임시 없이 바로** 아래 선언을 넣어 컴파일되게 한다(Task 7이 필드와 함수를 채운다):

```swift
// MARK: - 대회가 없을 때 — 2주 리듬 (설계 9절)

/// 대회 계획이 오늘을 덮지 않을 때의 입력. 스토어가 조립한다.
struct MRRhythmContext: Equatable {
    let runsPerWeek: Double
    let paces: MRPointPaces?
    /// 앱 저장 유형이 포인트 유형인 러닝(최근 180일) — 번갈이·마지막 포인트
    let pointTypes: [Date: WorkoutType]
    /// 최근 14일 안에 끝난 대회 — 이름·날짜. 없으면 nil.
    var recentRaceName: String? = nil
    var recentRaceDate: Date? = nil
}
```

`make` 함수 안의 계획 세션 블록

```swift
        if let plan = planWeek, let s = mrSessionSuggestion(level: level, plan: plan, runs: runs, asOf: asOf, calendar: calendar) {
            r.session = s.session
            r.progress = s.progress
            r.sessionIsLongRun = s.isLongRun
            if let note = s.whyNote { r.why = r.why.isEmpty ? note : r.why + " " + note }
        }
```

를 다음으로 교체(리듬 호출은 Task 7에서 한 줄 추가):

```swift
        // 대회 훈련 계획이 있으면 오늘 세션·이번 주 진행을 붙인다 — 종류는 플랜이 정한다
        let s: MRSessionSuggestion? = planWeek.flatMap {
            mrSessionSuggestion(level: level, plan: $0, runs: runs, asOf: asOf,
                                hardStarts: hardRunStarts, pointTypes: pointRunTypes, calendar: calendar)
        }
        if let s {
            r.session = s.session
            r.progress = s.progress.isEmpty ? nil : s.progress
            r.sessionIsLongRun = s.isLongRun
            r.sessionIsPoint = s.isPoint
            if let note = s.whyNote { r.why = r.why.isEmpty ? note : r.why + " " + note }
        }
```

(f) `MRTodayCard.swift`의 `mrTodayCard` 시그니처 끝 `planWeek: MRPlanWeekContext? = nil)` 를

```swift
                 planWeek: MRPlanWeekContext? = nil,
                 pointRunTypes: [Date: WorkoutType] = [:],
                 rhythm: MRRhythmContext? = nil) -> MRTodayCard? {
```

로, 안의 `mrReadiness(…, planWeek: planWeek)` 호출을

```swift
    let readiness = mrReadiness(runs: runs, phys: phys, heatHR: heatHR, hrvNights: hrvNights,
                                planPhase: planPhase, asOf: asOf, hardRunStarts: hardRunStarts, planWeek: planWeek,
                                pointRunTypes: pointRunTypes, rhythm: rhythm)
```

로 바꾼다.

(g) `MREngineStore.planWeekContext`의 반환을 `easyKm: parsed.easyKm, point: week.point)`로(끝에 `point:` 추가). `buildTodayCard`의 `mrTodayCard(…)` 호출에서 `planWeek: governing.map { … })` 뒤에 `, pointRunTypes: pointRunTypes`를 추가한다(`rhythm:`은 Task 7).

- [ ] **Step 4: 컴파일 확인** — `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunningTests/MRSessionPointTests.swift
git commit -m "아침 제안 — 계획 주차 포인트(롱런 > 포인트 > 이지, 롱런 요일 전날 피함, 남은 날 2일 이하 건너뜀)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- MIMORunning/Engine/MRReadiness.swift MIMORunning/Engine/MRTodayCard.swift MIMORunning/Engine/MREngineStore.swift MIMORunning/Engine/MRPlanPoint.swift MIMORunningTests/MRSessionPointTests.swift
```

---

### Task 7: 대회가 없을 때 — 2주 리듬

**Files:**
- Modify: `MIMORunning/Engine/MRPlanPoint.swift` (`MRRhythmContext` 상수·함수 추가)
- Modify: `MIMORunning/Engine/MRReadiness.swift` (`make`에 리듬 연결)
- Modify: `MIMORunning/Engine/MREngineStore.swift` (`rhythmContext(now:)`, `buildTodayCard`)
- Test: `MIMORunningTests/MRRhythmTests.swift`

- [ ] **Step 1: 테스트 먼저 쓰기**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("아침 제안 — 대회 없을 때 2주 리듬", .korean)
struct MRRhythmTests {

    private let cal = Calendar.current
    /// 2026-10-12(월) 주. 오프셋 0=월 … 6=일.
    private func day(_ offset: Int, hour: Int = 8) -> Date {
        let mon = cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        return cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: mon)!)!
    }
    private func run(_ offset: Int, km: Double) -> MRWorkout {
        MRWorkout(start: day(offset, hour: 7), durationMin: km * 6, distanceKm: km, hrAvg: 140, hrMax: 170,
                  tempC: 15, humidity: nil, indoor: false, isInterval: false)
    }
    /// 지난 8주 화·목 8km, 토 16km(습관 토요일). `skipLastSaturday`면 지난 토요일(−2) 롱런을 뺀다.
    private func history(skipLastSaturday: Bool = false) -> [MRWorkout] {
        (1...8).flatMap { w -> [MRWorkout] in
            let sat = run(-7 * w + 5, km: 16)
            let keepSat = !(skipLastSaturday && w == 1)
            return [run(-7 * w + 1, km: 8), run(-7 * w + 3, km: 8)] + (keepSat ? [sat] : [])
        }.sorted { $0.start < $1.start }
    }
    private func ctx(runs: Double = 4, types: [Date: WorkoutType] = [:], raceDaysAgo: Int? = nil) -> MRRhythmContext {
        var c = MRRhythmContext(runsPerWeek: runs, paces: mrPointPaces(halfEquivMin: 110), pointTypes: types)
        if let d = raceDaysAgo { c.recentRaceName = "춘천마라톤"; c.recentRaceDate = day(-d) }
        return c
    }

    @Test func usualLongRunIsMedianOfWeeklyLongest() {
        #expect(mrUsualLongRunKm(runs: history(), asOf: day(2)) == 16)
        let short = (1...4).flatMap { w in [run(-7 * w + 1, km: 5), run(-7 * w + 5, km: 7)] }
        #expect(mrUsualLongRunKm(runs: short, asOf: day(2)) == nil)   // 8km 미만
    }

    @Test func postRaceTwoWeeksIsEasyEvenWhenGo() throws {
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(raceDaysAgo: 5), runs: history(), hardStarts: [], asOf: day(2)))
        #expect(s.session == "이지런")
        #expect(!s.isPoint && !s.isLongRun)
        #expect(s.whyNote?.contains("회복") == true)
    }

    @Test func longRunDueOnHabitualDay() throws {
        // 토요일(5), 지난 토요일 롱런 없음 → 마지막 롱런 14일 전
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(), runs: history(skipLastSaturday: true), hardStarts: [], asOf: day(5)))
        #expect(s.isLongRun)
        #expect(s.session == "롱런 16km")
    }

    @Test func pointDueRotatesAfterInterval() throws {
        // 지난주 화(−6)가 인터벌 → 수요일(2) 기준 8일 전, 주 4회 간격 7 → 다음은 템포
        let hist = history()
        let lastTue = try #require(hist.first { cal.isDate($0.start, inSameDayAs: day(-6)) })
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(types: [lastTue.start: .interval]), runs: hist,
                                                hardStarts: [], asOf: day(2)))
        #expect(s.isPoint)
        #expect(s.session?.hasPrefix("포인트 추천: 템포") == true)
        #expect(s.whyNote?.contains("인터벌") == true)
    }

    @Test func noPointHistorySuggestsBuildUp() throws {
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(), runs: history(), hardStarts: [], asOf: day(2)))
        #expect(s.session?.hasPrefix("포인트 추천: 빌드업") == true)
    }

    @Test func dayBeforeHabitualLongRunNoPoint() throws {
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(), runs: history(), hardStarts: [], asOf: day(4)))
        #expect(!s.isPoint)
    }

    @Test func threeRunsPerWeekNeedsFourteenDays() throws {
        let hist = history()
        let lastTue = try #require(hist.first { cal.isDate($0.start, inSameDayAs: day(-6)) })
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(runs: 3, types: [lastTue.start: .interval]), runs: hist,
                                                hardStarts: [], asOf: day(2)))
        #expect(!s.isPoint)   // 8일 < 14일
    }

    @Test func twoRunsPerWeekNeverPoint() throws {
        let s = try #require(mrRhythmSuggestion(level: .go, ctx: ctx(runs: 2), runs: history(), hardStarts: [], asOf: day(2)))
        #expect(!s.isPoint)
    }

    @Test func easyLevelHasNoSessionButShowsRhythm() throws {
        let s = try #require(mrRhythmSuggestion(level: .easy, ctx: ctx(), runs: history(), hardStarts: [], asOf: day(2)))
        #expect(s.session == nil)
        #expect(s.progress.contains("마지막 롱런 4일 전"))
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는지 확인** — `cannot find 'mrRhythmSuggestion' in scope`.

- [ ] **Step 3: 구현**

(a) `MRPlanPoint.swift`의 `struct MRRhythmContext` 안(마지막 필드 아래)에 상수 추가:

```swift
    static let longRunEveryDays = 7
    /// ⚠ 코칭 관행 — 대회 거리별로 나누지 않는다
    static let postRaceEasyDays = 14
    static let minUsualLongKm = 8.0
```

그리고 구조체 아래에 함수 둘:

```swift
/// 평소 롱런 — 이번 주 앞의 4주(월~일) 각 주 최장 러닝의 중앙값. 러닝 있는 주 2개 미만이거나 8km 미만이면 nil.
/// 늘리지 않는다 — 대회가 없을 때 목적은 유지다(설계 9.1).
func mrUsualLongRunKm(runs: [MRWorkout], asOf: Date, calendar: Calendar = .current) -> Double? {
    let thisMonday = MRPlanGovernance.weekMonday(of: asOf, calendar: calendar)
    guard let from = calendar.date(byAdding: .day, value: -28, to: thisMonday) else { return nil }
    var byWeek: [Date: Double] = [:]
    for w in runs where w.start >= from && w.start < thisMonday {
        let mon = MRPlanGovernance.weekMonday(of: w.start, calendar: calendar)
        byWeek[mon] = max(byWeek[mon] ?? 0, w.distanceKm ?? 0)
    }
    guard byWeek.count >= 2 else { return nil }
    let l = mrMedian(Array(byWeek.values))
    return l >= MRRhythmContext.minUsualLongKm ? l : nil
}

/// 대회 계획이 오늘을 덮지 않을 때 — 마지막으로 한 날을 보고 빠진 것을 권한다(설계 9.4).
/// 강도 OK: 대회 뒤 14일 → 이지 · 롱런 7일↑ + 습관 요일(또는 습관 없음) → 롱런 · 포인트 간격↑ + 롱런 요일 전날 아님 → 포인트(번갈이) · 그 외 이지.
/// 이지·휴식 날은 세션 없이 리듬 상태만. 이지 거리는 말하지 않는다(주간 목표가 없다).
func mrRhythmSuggestion(level: MRReadiness.Level, ctx: MRRhythmContext, runs: [MRWorkout],
                        hardStarts: Set<Date>, asOf: Date, calendar: Calendar = .current) -> MRSessionSuggestion? {
    let L = AppLanguage.shared
    let today = calendar.startOfDay(for: asOf)
    let past = runs.filter { $0.start < today }
    func daysAgo(_ d: Date) -> Int { calendar.dateComponents([.day], from: calendar.startOfDay(for: d), to: today).day ?? 0 }
    let md: DateFormatter = { let f = DateFormatter(); f.dateFormat = "M/d"; return f }()

    // 대회 뒤 2주 — 포인트도 롱런도 권하지 않는다
    if let rd = ctx.recentRaceDate, (0..<MRRhythmContext.postRaceEasyDays).contains(daysAgo(rd)) {
        let n = daysAgo(rd)
        let name = ctx.recentRaceName ?? L.s("대회", "the race")
        let note = L.s("\(name) \(n)일 뒤 — 2주는 이지로 회복해요.", "\(n) days after \(name) — keep two weeks easy to recover.")
        return MRSessionSuggestion(session: level == .go ? L.s("이지런", "Easy run") : nil, progress: "", whyNote: note)
    }

    let usualLong = mrUsualLongRunKm(runs: runs, asOf: asOf, calendar: calendar)
    func isLong(_ w: MRWorkout) -> Bool {
        guard let l = usualLong else { return false }
        return (w.distanceKm ?? 0) >= l * MRPlanWeekContext.longRunDoneFraction
    }
    let lastLong = past.filter(isLong).max { $0.start < $1.start }
    let lastPoint = past
        .filter { !isLong($0) }
        .filter { w in
            hardStarts.contains(w.start)
                || (ctx.pointTypes[w.start].map { MRPlanPoint.pointWorkoutTypes.contains($0) } ?? false)
        }
        .max { $0.start < $1.start }
    let interval = mrPointIntervalDays(runsPerWeek: ctx.runsPerWeek)

    var pieces: [String] = []
    if usualLong != nil, let l = lastLong {
        pieces.append(L.s("마지막 롱런 \(daysAgo(l.start))일 전", "last long run \(daysAgo(l.start)) days ago"))
    }
    if interval != nil, let p = lastPoint {
        pieces.append(L.s("마지막 포인트 \(daysAgo(p.start))일 전", "last workout \(daysAgo(p.start)) days ago"))
    }
    let progress = pieces.joined(separator: " · ")

    guard level == .go else { return MRSessionSuggestion(session: nil, progress: progress) }

    let habitual = mrHabitualLongRunWeekday(runs: runs, asOf: asOf, calendar: calendar)
    let todayWD = calendar.component(.weekday, from: asOf)
    let longDue = usualLong != nil
        && (lastLong.map { daysAgo($0.start) >= MRRhythmContext.longRunEveryDays } ?? true)
    if let l = usualLong, longDue, habitual == nil || habitual == todayWD {
        return MRSessionSuggestion(session: L.s("롱런 \(Int(l.rounded()))km", "Long run \(Int(l.rounded()))km"),
                                   progress: progress, isLongRun: true)
    }

    let tomorrowWD = todayWD % 7 + 1
    if let iv = interval, let paces = ctx.paces, habitual != tomorrowWD,
       lastPoint.map({ daysAgo($0.start) >= iv }) ?? true {
        let lastType = lastPoint.flatMap { ctx.pointTypes[$0.start] }
        let weekly = past.filter { daysAgo($0.start) <= 28 }.compactMap(\.distanceKm).reduce(0, +) / 4
        func make(_ kind: MRPlanPoint.Kind) -> MRPlanPoint? {
            let pace = kind == .speed ? paces.fiveK : (kind == .tempo ? paces.tempo : paces.half)
            return MRPlanPoint.make(kind: kind, weeklyKm: weekly, longRunKm: usualLong ?? 0,
                                    raceDistanceM: nil, paceSecPerKm: pace)
        }
        // 빌드업이 안 되면(평소 롱런이 짧음) 속도로
        if let pt = make(MRPlanPoint.nextKind(after: lastType)) ?? make(.speed) {
            let why: String
            if let lp = lastPoint {
                let label = lastType.map { " " + $0.koreanLabel } ?? ""
                why = L.s("지난 포인트는 \(md.string(from: lp.start))\(label), \(daysAgo(lp.start))일 전이에요.",
                          "Last workout:\(label) \(daysAgo(lp.start)) days ago.")
            } else {
                why = L.s("최근 포인트가 없어요.", "No recent workout.")
            }
            return MRSessionSuggestion(session: L.s("포인트 추천: \(pt.text)", "Workout: \(pt.text)"),
                                       progress: progress, isPoint: true, whyNote: why)
        }
    }

    let note: String? = longDue
        ? habitual.map { L.s("여유는 \(mrWeekdayName($0)) 롱런에 쓰세요.", "Save it for \(mrWeekdayName($0))'s long run.") }
        : nil
    return MRSessionSuggestion(session: L.s("이지런", "Easy run"), progress: progress, whyNote: note)
}
```

(b) `MRReadiness.swift`의 `make` 안에서 Task 6이 만든

```swift
        let s: MRSessionSuggestion? = planWeek.flatMap {
            mrSessionSuggestion(level: level, plan: $0, runs: runs, asOf: asOf,
                                hardStarts: hardRunStarts, pointTypes: pointRunTypes, calendar: calendar)
        }
```

을 다음으로 바꾼다(계획이 있으면 계획만 — D-7 이내 nil이어도 리듬을 쓰지 않는다):

```swift
        let s: MRSessionSuggestion? = planWeek != nil
            ? planWeek.flatMap {
                mrSessionSuggestion(level: level, plan: $0, runs: runs, asOf: asOf,
                                    hardStarts: hardRunStarts, pointTypes: pointRunTypes, calendar: calendar)
              }
            : rhythm.flatMap {
                mrRhythmSuggestion(level: level, ctx: $0, runs: runs, hardStarts: hardRunStarts,
                                   asOf: asOf, calendar: calendar)
              }
```

(c) `MREngineStore` — `planWeekContext(…)` 함수 바로 아래에 추가:

```swift
    /// 대회 계획이 오늘을 덮지 않을 때의 2주 리듬 입력(설계 9절). 최근 14일 대회는 등록 대회 우선, 없으면 저장 유형 '대회'.
    private func rhythmContext(now: Date) -> MRRhythmContext {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func within14(_ d: Date) -> Bool {
            let n = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: today).day ?? -1
            return n >= 0 && n < MRRhythmContext.postRaceEasyDays
        }
        let registered = userInput.races.filter { within14($0.date) }.max { $0.date < $1.date }
        let typed = pointRunTypes.filter { $0.value == .race && within14($0.key) }.keys.max()
        var c = MRRhythmContext(runsPerWeek: profile.runsPerWeek,
                                paces: mrPointPaces(halfEquivMin: halfEquivMin),
                                pointTypes: pointRunTypes)
        if let r = registered {
            c.recentRaceName = r.name; c.recentRaceDate = r.date
        } else if let t = typed {
            c.recentRaceName = AppLanguage.shared.s("대회", "the race"); c.recentRaceDate = t
        }
        return c
    }
```

`buildTodayCard`의 `mrTodayCard(…, pointRunTypes: pointRunTypes)` 끝에 `, rhythm: governing == nil ? rhythmContext(now: now) : nil`을 추가한다.

- [ ] **Step 4: 컴파일 확인** — `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunningTests/MRRhythmTests.swift
git commit -m "대회 없을 때 2주 리듬 — 평소 롱런 유지·포인트 번갈이(속도→템포→빌드업)·대회 뒤 14일 이지, 아침 제안 연결

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- MIMORunning/Engine/MRPlanPoint.swift MIMORunning/Engine/MRReadiness.swift MIMORunning/Engine/MREngineStore.swift MIMORunningTests/MRRhythmTests.swift
```

---

### Task 8: 주차표 포인트 줄 (화면 — 실기기 확인)

**Files:**
- Modify: `MIMORunning/Views/MRRacePlanView.swift` (`MRWeekTable` 속성·헬퍼·펼친 영역 두 곳, `MRRacePlanCard`의 `MRWeekTable(` 호출)

- [ ] **Step 1: `MRWeekTable` 속성 추가** — `var recoveryEffortNote: String? = nil` 아래에:

```swift
    /// 포인트 완료 판정 입력 — 엔진이 홈에서 받은 값(고강도 15일 · 포인트 유형 180일)
    var hardRunStarts: Set<Date> = []
    var pointRunTypes: [Date: WorkoutType] = [:]
```

- [ ] **Step 2: 헬퍼 추가** — `breakdownForSnap(_:)` 함수 바로 아래에:

```swift
    /// 그 주에 한 포인트 — 주차표와 아침 제안이 같은 판정(`mrPointRun`)을 쓴다. 미래 주는 nil.
    private func pointRunIn(week monday: Date, longRunKm: Double) -> MRWorkout? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: monday)
        guard start <= cal.startOfDay(for: Date()),
              let end = cal.date(byAdding: .day, value: 7, to: start) else { return nil }
        let weekRuns = runs.filter { $0.start >= start && $0.start < end }
        return mrPointRun(weekRuns: weekRuns, longRunKm: longRunKm, hardStarts: hardRunStarts, pointTypes: pointRunTypes)
    }

    /// 포인트 두 줄 — 계획(흰색 0.72) · 한 뒤(노랑 = 실제로 한 것). 설계 7절.
    @ViewBuilder
    private func pointLines(_ pt: MRPlanPoint, monday: Date, longRunKm: Double) -> some View {
        let L = AppLanguage.shared
        Text(L.s("포인트 · \(pt.text)", "Workout · \(pt.text)"))
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.72))
        if let done = pointRunIn(week: monday, longRunKm: longRunKm) {
            let type = pointRunTypes[done.start].map { " " + $0.koreanLabel } ?? ""
            Text(L.s("포인트 ✓ \(dateFmt.string(from: done.start))\(type)", "Workout ✓ \(dateFmt.string(from: done.start))\(type)"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.yellow)   // 노랑 = 실제로 한 것
        }
    }
```

- [ ] **Step 3: 펼친 영역에 넣기**

스냅샷 분기의 펼친 영역에서

```swift
                                let bd = breakdownForSnap(snap)
                                if !bd.isEmpty {
                                    Text(bd)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
```

바로 아래에:

```swift
                                if let pt = snap.point {
                                    pointLines(pt, monday: snap.monday, longRunKm: snap.longRunKm)
                                }
```

라이브 분기의 펼친 영역에서

```swift
                                if !w.breakdown.isEmpty {
                                    Text(localizedBreakdown(w.breakdown))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
```

바로 아래에:

```swift
                                if let pt = w.point {
                                    pointLines(pt, monday: w.monday, longRunKm: w.longRunKm)
                                }
```

- [ ] **Step 4: 호출부** — `MRRacePlanCard`의

```swift
                MRWeekTable(weeks: plan.weeks, histMaxWeeklyKm: plan.histMaxWeeklyKm,
                            runs: runs, snapshotWeeks: snapshot?.planWeeks ?? [],
                            currentRaceLabels: Set(engine.userInput.races.map { mrLabelFor(distanceM: $0.distanceM) }),
                            recoveryEffortNote: recoveryEffortNote)
```

를

```swift
                MRWeekTable(weeks: plan.weeks, histMaxWeeklyKm: plan.histMaxWeeklyKm,
                            runs: runs, snapshotWeeks: snapshot?.planWeeks ?? [],
                            currentRaceLabels: Set(engine.userInput.races.map { mrLabelFor(distanceM: $0.distanceM) }),
                            recoveryEffortNote: recoveryEffortNote,
                            hardRunStarts: engine.hardRunStarts,
                            pointRunTypes: engine.pointRunTypes)
```

로.

- [ ] **Step 5: 컴파일 확인** — `** TEST BUILD SUCCEEDED **`

- [ ] **Step 6: 커밋**

```bash
git commit -m "주차표 포인트 줄 — 펼친 주에 '포인트 · 속도 1km × 4회 5'05\"', 한 뒤 노랑 '포인트 ✓ 날짜 유형'

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- MIMORunning/Views/MRRacePlanView.swift
```

---

### Task 9: FEATURES.md 기록 + 최종 빌드

**Files:**
- Modify: `FEATURES.md` (6.9 훈련 계획 플래너 절 끝 — `- **스냅샷 규칙**:` 항목 바로 아래)

- [ ] **Step 1: 항목 추가**

```markdown
- **포인트 훈련**(2026-09-29, 설계 `docs/superpowers/specs/2026-09-29-plan-point-session-design.md`): 한 주에 포인트 1회가 이지 한 번을 대신한다(주간 km·러닝 횟수 그대로). 종류는 단계가 고른다 — 늘리기 속도(1km × 주간 8%, 3~6회, 5K 예측 페이스) · 유지 템포(주간 10%, 3~8km, 10K와 하프 사이) · 대회 페이스 빌드업(10K 8·하프 10·풀 14km, 롱런 70% 이하, 마지막 1/3 대회 페이스) · 테이퍼 대회 페이스 1km × 3. 회복·튠업·대회 주·따르는 주(따르는 계획의 포인트)는 규칙대로. 빈도: 최근 주당 러닝 4회↑ 매주 · 3회 격주 · 2회↓ 없음. 이지 1회가 1.5km 아래면 그 주는 생략. 안내 문구에는 넣지 않고(이지 횟수만 하나 줄어듦) 구조화 칸(`MRPlanWeek.point`)으로 저장, 펼친 주에 "포인트 · …" 줄과 한 뒤 노랑 "포인트 ✓ 날짜 유형". 완료 = 롱런으로 센 러닝을 뺀 고강도 또는 포인트 유형 러닝(`mrPointRun`, 홈이 180일 포인트 유형 주입). **이미 시작한 계획은 다음 주부터 채움**(트리거 5, 같은 단계만, 양은 스냅샷 주간으로) — 이번 주는 공백. 기존 이행 기호(● ◐ ○ ▲)는 그대로
- **아침 제안 × 포인트**: 강도 OK 날 롱런(습관 요일·남은 날 ≤2) > 포인트(남은 날 ≥3, 롱런 습관 요일 전날 아님) > 이지. 판정 줄 "오늘은 강도 OK · 포인트 속도 1km × 4회 5'05\"", 셋째 줄 "이번 주 롱런 아직 · 포인트 아직 · 이지 1/2회". 남은 날 2일 이하면 "포인트는 이번 주 건너뛰어도 괜찮아요"(다음 주로 미루지 않음). 포인트 다음 날은 기존 고강도 판정이 이지를 권한다
- **대회 없을 때 2주 리듬**(오늘을 덮는 계획 주차가 없을 때): 평소 롱런(지난 4주 주별 최장의 중앙값, 8km↑) 유지 — 7일 지났고 습관 요일(또는 습관 없음)이면 롱런. 포인트는 같은 빈도 규칙으로 속도 → 템포 → 빌드업 번갈이(최근 포인트 없으면 빌드업, 안 되면 속도), 이유 "지난 포인트는 9/24 빌드업, 8일 전이에요." 대회 뒤 14일은 강도 OK여도 이지("○○ 6일 뒤 — 2주는 이지로 회복해요."). 이지 거리는 말하지 않는다(주간 목표 없음). 80/20 보류 중 이 범위만 해제 — 이지 확인·강도 예산·초보 해석은 계속 보류
```

- [ ] **Step 2: 최종 빌드** — build-for-testing. Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git commit -m "FEATURES — 포인트 훈련·아침 제안 포인트·대회 없을 때 2주 리듬

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- FEATURES.md
```

---

## 실기기 확인 포인트 (사용자)

1. 나 탭 하프·풀 계획 주차표 — 다음 주부터 펼친 주에 포인트 줄이 보이는가, 이번 주는 없는가. 로그 `[스냅샷] 포인트 칸 채움 → N주`.
2. 주차표 이지 횟수가 하나 줄고 합이 주간 km와 맞는가.
3. 홈 아침 제안 — 강도 OK인 평일에 "포인트 …"가 뜨는가, 토요일 전날(금)엔 이지인가.
4. 포인트를 한 주에 노랑 "포인트 ✓"가 뜨는가.
5. 계획이 없는 기간(10/4 뒤 다음 계획 시작 전 등)에 롱런·포인트 추천과 셋째 줄 "마지막 롱런 N일 전 · 마지막 포인트 N일 전".
