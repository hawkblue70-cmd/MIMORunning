# 오늘의 인사이트 = 카드 판정 요약 (RunHeadline) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 상세 화면 맨 위 "오늘의 인사이트" 카드를 아래 카드(총평·폼·심박 효율) 판정에서 고른 **제목 + 핵심 사실 + 다음 행동**으로 바꾸고, 공유 카드 헤드라인도 같은 제목을 쓰게 한다.

**Architecture:** 순수 함수 조합기 `RunHeadline.make(insight:summaryInput:summaryLines:efficiency:)`가 이미 계산된 판정(인사이트 엔진 결과·`RunSummaryInput`·총평 줄·`RunInsightEngine` 심박 효율)에서 후보를 모아 순서대로 하나를 고른다. 판정 로직은 새로 만들지 않는다. 상세 화면이 입력이 바뀔 때 한 번 계산해 `@State`에 두고, `InsightCard`와 공유 카드에 넘긴다. 저장하지 않는다(과거 러닝도 열 때 새 방식).

**Tech Stack:** Swift, SwiftUI, Swift Testing. 설계 문서: `docs/superpowers/specs/2026-09-30-today-headline-design.md`.

**검증 규칙(모든 태스크):** 시뮬레이터·`xcodebuild test` 금지. 앱+테스트 타깃 컴파일만:
```bash
cd /Users/hns/MIMORunning/MIMORunning && xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|TEST BUILD (SUCCEEDED|FAILED)"
```
Expected: `** TEST BUILD SUCCEEDED **`

**git 규칙:** 다른 세션이 crew에 동시 커밋한다. `git add -A`·`stash` 금지, 경로 명시. `project.pbxproj`·`Claude.md`는 add 금지. 커밋 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

## 파일

| 파일 | 역할 |
|---|---|
| `MIMORunning/Insight/RunHeadline.swift` (새) | 조합기 — 후보·순서·사실 잇기·다음 행동 고르기 |
| `MIMORunningTests/RunHeadlineTests.swift` (새) | 조합기 테스트 |
| `MIMORunning/Views/ActivityDetailView.swift` | `headline` 상태·계산 트리거, `InsightCard` 표시, 공유 카드에 표시용 인사이트 |

참고 타입(이미 있음):
- `RunSummaryLine { axis: String, state: String, tone: .good/.neutral, evidence: String?, next: String? }` — `Insight/RunSummary.swift`
- 총평 축 라벨: `L.s("러닝폼","Form")` · `L.s("거리 적응","Distance")` · `L.s("심박","Heart rate")` · `L.s("훈련부하","Training load")` (RunSummary.swift와 같은 문자열)
- `RunSummaryInput`: `form: FormPhase.Result?`, `distKm`, `workoutType`, `acuteChronic: EffortLoad.RatioLabel?`(.low/.steady/.high/.veryHigh), `streakDays`, `distanceRank: Int?`, `distanceSampleCount: Int?`, `planPhase: String?`
- `FormPhase.Late`: `.held` · `.heavier([Metric])` · `.cadenceDefended` · `.bouncier` · `.faded(paceDropSec:)`; `FormPhase.shortState(_ r: Result) -> String`
- `RunInsight { category: InsightCategory, tone: InsightTone, badge, message, highlights: [String] }` — 심박 효율은 `category == .efficiency`, `tone == .good`, `highlights[0]` = `"7bpm"`
- `InsightResult(theme:workoutType:title:detail:aiEnhanced:)`, `InsightTheme` — `Insight/InsightEngine.swift`
- `FormNarrative.isPlannedHighIntensity(_ type: WorkoutType) -> Bool`
- 테스트 스텁: `FormPhase.Result.stub(late:...)` — `MIMORunningTests/FormPhaseStubs.swift`

---

### Task 1: `RunHeadline` 조합기 + 테스트

**Files:**
- Create: `MIMORunning/Insight/RunHeadline.swift`
- Test: `MIMORunningTests/RunHeadlineTests.swift`

- [ ] **Step 1: 테스트 작성**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("오늘의 인사이트 — 카드 판정 요약", .korean)
struct RunHeadlineTests {
    // 총평 줄 픽스처 — 축 라벨은 RunSummary와 같은 한국어
    private func line(_ axis: String, _ state: String, _ tone: RunSummaryLine.Tone = .good, next: String? = nil) -> RunSummaryLine {
        var l = RunSummaryLine(axis: axis, state: state, tone: tone); l.next = next; return l
    }
    private let taperNext = "대회 훈련 계획상 테이퍼 주예요. 이지런 위주로 가세요."
    private var todayLines: [RunSummaryLine] {
        [line("러닝폼", "끝까지 유지"), line("심박", "딱 좋은 강도"),
         line("훈련부하", "4주 평균 수준 · 4일 연속", next: taperNext), line("유산소", "50대 남성 기준 높음")]
    }
    private var efficiency7: RunInsight {
        RunInsight(category: .efficiency, tone: .good, badge: "효율 향상",
                   message: "비슷한 페이스 최근 8주 5회보다 심박이 7 bpm 낮았어요.", highlights: ["7bpm", "5회"])
    }
    private func input(km: Double = 6.24, late: FormPhase.Late? = .held, type: WorkoutType = .general,
                       ac: EffortLoad.RatioLabel? = .steady, streak: Int = 0, plan: String? = nil,
                       rank: Int? = nil, samples: Int? = nil) -> RunSummaryInput {
        var i = RunSummaryInput()
        i.distKm = km; i.workoutType = type; i.acuteChronic = ac; i.streakDays = streak; i.planPhase = plan
        i.distanceRank = rank; i.distanceSampleCount = samples
        if let late { i.form = .stub(late: late) }
        return i
    }
    private let streakInsight = InsightResult(theme: .distanceExpanded, title: "경계를 넓힌 러닝", detail: "이번 주 최장 거리 6.24 km")

    @Test func todayExampleSummarizesCards() {
        // 9/29 — 심박 효율(1순위) · 폼 유지(6km라 제목 후보 아님, 두 번째 사실) · 테이퍼 주
        let h = RunHeadline.make(insight: streakInsight, summaryInput: input(plan: "테이퍼", streak: 4),
                                 summaryLines: todayLines, efficiency: efficiency7)
        #expect(h?.title == "가벼워진 러닝")
        #expect(h?.fact == "같은 페이스에 심박 7bpm 낮음 · 폼은 끝까지 평소 범위")
        #expect(h?.next == taperNext)
        #expect(h?.source == .goodSignal)
    }

    @Test func rareEventComesFirstWithoutSecondFact() {
        let pr = InsightResult(theme: .recordImproved, title: "어제보다 나은 러닝", detail: "10K 90일 최고 페이스")
        let h = RunHeadline.make(insight: pr, summaryInput: input(), summaryLines: todayLines, efficiency: efficiency7)
        #expect(h?.title == "어제보다 나은 러닝")
        #expect(h?.fact == "10K 90일 최고 페이스")
        #expect(h?.source == .rareEvent)
    }

    @Test func restSignalBeatsGoodSignal() {
        var lines = todayLines
        lines[2] = line("훈련부하", "4주 평균 대비 높음", .neutral, next: "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요.")
        let h = RunHeadline.make(insight: nil, summaryInput: input(ac: .high), summaryLines: lines, efficiency: efficiency7)
        #expect(h?.title == "쌓이는 러닝")
        #expect(h?.fact == "4주 평균 대비 높음 · 같은 페이스에 심박 7bpm 낮음")
        #expect(h?.next == "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요.")
    }

    @Test func mildCautionComesAfterGoodSignal() {
        let h = RunHeadline.make(insight: nil, summaryInput: input(km: 11, late: .heavier([.stride])),
                                 summaryLines: todayLines, efficiency: efficiency7)
        #expect(h?.title == "가벼워진 러닝")
        #expect(h?.fact.hasSuffix(" · 마지막 4km 살짝 무거워짐") == true)
    }

    @Test func heldFormTitlesOnlyFromEightKm() {
        let long = RunHeadline.make(insight: nil, summaryInput: input(km: 11), summaryLines: todayLines, efficiency: nil)
        #expect(long?.title == "끝까지 버틴 러닝")
        let short = RunHeadline.make(insight: streakInsight, summaryInput: input(km: 6), summaryLines: todayLines, efficiency: nil)
        #expect(short?.title != "끝까지 버틴 러닝")
    }

    @Test func secondFactSkipsSameAxis() {
        // 부하 급증 + 4일 연속(계획 없음) — 둘 다 훈련부하 축이라 두 번째 사실로 붙지 않는다
        var lines = todayLines
        lines[2] = line("훈련부하", "4주 평균 대비 높음 · 4일 연속", .neutral)
        let h = RunHeadline.make(insight: nil, summaryInput: input(late: nil, ac: .high, streak: 4),
                                 summaryLines: lines, efficiency: nil)
        #expect(h?.fact == "4주 평균 대비 높음 · 4일 연속")
    }

    @Test func nextActionFallsBackThroughAxes() {
        // 심박 축 next 없음 → 훈련부하 next
        let h1 = RunHeadline.make(insight: nil, summaryInput: input(), summaryLines: todayLines, efficiency: efficiency7)
        #expect(h1?.next == taperNext)
        // 같은 축(심박)에 next가 있으면 그것
        var lines = todayLines
        lines[1] = line("심박", "딱 좋은 강도", next: "다음 이지런은 6'40\"로.")
        let h2 = RunHeadline.make(insight: nil, summaryInput: input(), summaryLines: lines, efficiency: efficiency7)
        #expect(h2?.next == "다음 이지런은 6'40\"로.")
        // 어디에도 next 없음 → nil
        let bare = [line("러닝폼", "끝까지 유지"), line("심박", "딱 좋은 강도")]
        let h3 = RunHeadline.make(insight: nil, summaryInput: input(), summaryLines: bare, efficiency: efficiency7)
        #expect(h3?.next == nil)
    }

    @Test func fewSummaryLinesFallBackToEngine() {
        let h = RunHeadline.make(insight: streakInsight, summaryInput: input(), summaryLines: [line("심박", "딱 좋은 강도")],
                                 efficiency: efficiency7)
        #expect(h?.title == "경계를 넓힌 러닝")
        #expect(h?.fact == "이번 주 최장 거리 6.24 km")
        #expect(h?.source == .fallback)
        #expect(RunHeadline.make(insight: nil, summaryInput: nil, summaryLines: [], efficiency: nil) == nil)
    }

    @Test func taperWeekIsContextTitleWhenNothingElse() {
        let h = RunHeadline.make(insight: streakInsight, summaryInput: input(km: 6, late: nil, plan: "테이퍼"),
                                 summaryLines: todayLines, efficiency: nil)
        #expect(h?.title == "숨 고르는 러닝")
        #expect(h?.fact == "대회 계획 테이퍼 주")
    }
}
```

- [ ] **Step 2: 빌드가 `RunHeadline` 없음으로 깨지는 것을 확인**

Run: 빌드 확인 명령 · Expected: `error: cannot find 'RunHeadline' in scope`

- [ ] **Step 3: 구현**

```swift
import Foundation

/// 상세 화면 맨 위 "오늘의 인사이트" — 아래 카드(총평·폼·심박 효율)가 **이미 내린 판정**에서 고른 요약.
/// 판정은 하지 않는다. 후보를 순서대로 모아 첫 후보가 제목을 정하고, 다른 축의 다음 후보 하나를 사실로 덧붙이고,
/// 총평 "다음" 문장 하나를 붙인다. 설계: docs/superpowers/specs/2026-09-30-today-headline-design.md
struct RunHeadline: Equatable {
    enum Source: Equatable { case rareEvent, restSignal, goodSignal, mildCaution, context, fallback }
    let title: String
    let fact: String
    let next: String?
    let source: Source

    /// 총평 줄과 맞출 축 — 라벨 문자열은 RunSummary와 같아야 한다(비교는 여기서만).
    enum Axis: Equatable { case form, distance, heart, load, none
        var label: String? {
            let L = AppLanguage.shared
            switch self {
            case .form:     return L.s("러닝폼", "Form")
            case .distance: return L.s("거리 적응", "Distance")
            case .heart:    return L.s("심박", "Heart rate")
            case .load:     return L.s("훈련부하", "Training load")
            case .none:     return nil
            }
        }
    }

    struct Candidate: Equatable {
        let source: Source
        let title: String
        let fact: String
        let axis: Axis
        /// false면 제목 후보가 아니고 두 번째 사실로만 쓴다(예: 8km 미만의 "끝까지 버틴")
        var titleEligible: Bool = true
    }

    /// 인사이트 엔진의 드문 사건 — 카드 판정보다 먼저
    static let rareThemes: Set<InsightTheme> = [.safety, .returnGap, .firstAchievement, .raceDay, .recordImproved, .milestone]
    /// "끝까지 버틴 러닝"을 제목으로 쓰는 최소 거리 — 짧은 러닝엔 과장
    static let heldTitleMinKm = 8.0

    static func make(insight: InsightResult?, summaryInput: RunSummaryInput?,
                     summaryLines: [RunSummaryLine], efficiency: RunInsight?) -> RunHeadline? {
        // 재료 없음(워치 없는 러닝·재료 도착 전) → 엔진 결과 그대로
        guard let input = summaryInput, summaryLines.count >= 2 else {
            return insight.map { RunHeadline(title: $0.title, fact: $0.detail, next: nil, source: .fallback) }
        }
        let cands = candidates(insight: insight, input: input, lines: summaryLines, efficiency: efficiency)
        guard let firstIdx = cands.firstIndex(where: { $0.titleEligible }) else {
            return insight.map { RunHeadline(title: $0.title, fact: $0.detail,
                                             next: nextAction(for: .none, lines: summaryLines), source: .fallback) }
        }
        let first = cands[firstIdx]
        var fact = first.fact
        if first.source != .rareEvent {
            let second = cands.enumerated().first { pair in
                let c = pair.element
                return pair.offset != firstIdx && c.source != .rareEvent && c.fact != first.fact &&
                    (first.axis == .none || c.axis != first.axis)
            }?.element
            if let s = second { fact += " · " + s.fact }
        }
        return RunHeadline(title: first.title, fact: fact,
                           next: nextAction(for: first.axis, lines: summaryLines), source: first.source)
    }

    // MARK: - 후보 (순서 = 배열 순서)

    static func candidates(insight: InsightResult?, input i: RunSummaryInput,
                           lines: [RunSummaryLine], efficiency: RunInsight?) -> [Candidate] {
        let L = AppLanguage.shared
        func line(_ a: Axis) -> RunSummaryLine? { a.label.flatMap { lbl in lines.first { $0.axis == lbl } } }
        let planEasy = i.planPhase == "회복" || i.planPhase == "테이퍼"
        var out: [Candidate] = []

        // 1 드문 사건
        if let ins = insight, rareThemes.contains(ins.theme) {
            out.append(Candidate(source: .rareEvent, title: ins.title, fact: ins.detail, axis: .none))
        }
        // 2 쉬어야 할 신호
        if i.acuteChronic == .high || i.acuteChronic == .veryHigh, let l = line(.load) {
            out.append(Candidate(source: .restSignal, title: L.s("쌓이는 러닝", "Stacking Up"), fact: l.state, axis: .load))
        }
        if i.streakDays >= 4 && !planEasy {
            out.append(Candidate(source: .restSignal, title: L.s("쌓이는 러닝", "Stacking Up"),
                                 fact: L.s("\(i.streakDays)일 연속", "\(i.streakDays) days in a row"), axis: .load))
        }
        if let f = i.form, case .faded = f.late {
            out.append(Candidate(source: .restSignal, title: L.s("끝까지 달린 러닝", "Ran It Out"),
                                 fact: FormPhase.shortState(f), axis: .form))
        }
        // 3 좋은 신호
        if let e = efficiency, e.category == .efficiency, e.tone == .good, let h = e.highlights.first {
            out.append(Candidate(source: .goodSignal, title: L.s("가벼워진 러닝", "Lighter Run"),
                                 fact: L.s("같은 페이스에 심박 \(h) 낮음", "HR \(h) lower at the same pace"), axis: .heart))
        }
        if let f = i.form, f.late == .held {
            out.append(Candidate(source: .goodSignal, title: L.s("끝까지 버틴 러닝", "Held to the End"),
                                 fact: L.s("폼은 끝까지 평소 범위", "Form stayed in range to the end"), axis: .form,
                                 titleEligible: i.distKm >= heldTitleMinKm))
        }
        if FormNarrative.isPlannedHighIntensity(i.workoutType), let l = line(.heart), l.tone == .good {
            out.append(Candidate(source: .goodSignal, title: L.s("한계를 미는 러닝", "Pushing the Edge"), fact: l.state, axis: .heart))
        }
        if i.distanceRank == 1, let n = i.distanceSampleCount, n >= 5 {
            out.append(Candidate(source: .goodSignal, title: L.s("경계를 넓힌 러닝", "Expanding Boundaries"),
                                 fact: L.s("최근 \(n)회 중 가장 긴 거리", "Longest of your last \(n) runs"), axis: .distance))
        }
        // 4 가벼운 주의
        if let f = i.form, case .heavier = f.late {
            out.append(Candidate(source: .mildCaution, title: L.s("끝까지 달린 러닝", "Ran It Out"),
                                 fact: FormPhase.shortState(f), axis: .form))
        }
        if let l = line(.heart), l.tone == .neutral {
            out.append(Candidate(source: .mildCaution, title: L.s("쌓이는 러닝", "Stacking Up"), fact: l.state, axis: .heart))
        }
        // 5 맥락
        if planEasy, let p = i.planPhase {
            out.append(Candidate(source: .context, title: L.s("숨 고르는 러닝", "Catching Your Breath"),
                                 fact: p == "테이퍼" ? L.s("대회 계획 테이퍼 주", "Race plan: taper week")
                                                    : L.s("대회 계획 회복 주", "Race plan: recovery week"),
                                 axis: .load))
        }
        if i.workoutType == .easy, let l = line(.heart), l.tone == .good {
            out.append(Candidate(source: .context, title: L.s("숨 고르는 러닝", "Catching Your Breath"), fact: l.state, axis: .heart))
        }
        if let ins = insight, ins.theme == .consistent {
            out.append(Candidate(source: .context, title: ins.title, fact: ins.detail, axis: .none))
        }
        return out
    }

    // MARK: - 다음 행동

    /// 같은 축 줄의 next → 훈련부하 줄의 next → next가 있는 첫 줄 → nil
    static func nextAction(for axis: Axis, lines: [RunSummaryLine]) -> String? {
        if let lbl = axis.label, let n = lines.first(where: { $0.axis == lbl })?.next { return n }
        if let lbl = Axis.load.label, let n = lines.first(where: { $0.axis == lbl })?.next { return n }
        return lines.first(where: { $0.next != nil })?.next
    }
}
```

- [ ] **Step 4: 빌드 확인** — Expected: `** TEST BUILD SUCCEEDED **`

테스트 기대값 점검(실행하지 않으므로 손으로): `todayExampleSummarizesCards`에서 후보 순서는 [효율(heart) · 폼 유지(form, 제목X) · 테이퍼(load)] (streak 4이지만 테이퍼라 restSignal 없음) → 제목 효율, 두 번째 = 폼 유지(축 다름) → 사실 일치. next: 심박 줄 next 없음 → 훈련부하 next. `mildCautionComesAfterGoodSignal`의 `.stub(late: .heavier([.stride]))`는 `lateStart: 12, total: 16` → shortState "마지막 4km 살짝 무거워짐". 기대값이 코드와 다르면 코드가 아니라 **테스트 픽스처를 코드 규칙에 맞게** 고치고 보고할 것(설계 규칙이 우선).

- [ ] **Step 5: 커밋**

```bash
cd /Users/hns/MIMORunning/MIMORunning && git add MIMORunning/Insight/RunHeadline.swift MIMORunningTests/RunHeadlineTests.swift && git commit -m "$(cat <<'EOF'
오늘의 인사이트 조합기(RunHeadline) — 카드 판정에서 제목·핵심 사실·다음 행동을 고른다(판정은 새로 하지 않음)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 상세 화면 연결 — 계산·InsightCard·공유 카드

**Files:**
- Modify: `MIMORunning/Views/ActivityDetailView.swift`

- [ ] **Step 1: 상태와 계산**

`@State private var runInsights: [RunInsight] = []` 아래에:

```swift
    /// 오늘의 인사이트 요약(RunHeadline) — 입력이 바뀔 때 한 번 계산(렌더마다 계산하지 않음)
    @State private var headline: RunHeadline?
```

`private var shareSummaryLines: [RunSummaryLine] { RunSummaryBuilder.lines(summaryContext) }` 아래에:

```swift
    /// headline 재계산 트리거 — 인사이트·총평 재료가 바뀌면 달라지는 값들
    private var headlineKey: String {
        "\(insight?.title ?? "")|\(insight?.detail ?? "")|\(hrSamples.count)|\(formBaseline == nil ? 0 : 1)|" +
        "\(effectiveHRZones.count)|\(runInsights.count)|\(detail == nil ? 0 : 1)"
    }

    private func recomputeHeadline() {
        guard activity.type == .running else { headline = nil; return }
        let input = RunSummaryBuilder.input(summaryContext)
        let lines = RunSummary.lines(input)
        let eff = runInsights.first { $0.category == .efficiency }
        let h = RunHeadline.make(insight: insight, summaryInput: input, summaryLines: lines, efficiency: eff)
        if h != headline { withAnimation(.easeInOut(duration: 0.3)) { headline = h } }
    }

    /// 공유 카드에 넘길 인사이트 — 요약을 골랐으면 그 제목·사실(헤드라인 = 맨 위 카드 제목), 드문 사건·대체면 엔진 결과 그대로
    private var shareInsight: InsightResult? {
        guard let h = headline, h.source != .rareEvent, h.source != .fallback else { return insight }
        return InsightResult(theme: insight?.theme ?? .default, workoutType: insight?.workoutType ?? .general,
                             title: h.title, detail: h.fact, aiEnhanced: false)
    }
```

- [ ] **Step 2: 트리거 연결**

`.onChange(of: hrSamples.count) { _, newCount in` 수정자 **바로 위**에:

```swift
        .onChange(of: headlineKey, initial: true) { _, _ in recomputeHeadline() }
```

- [ ] **Step 3: InsightCard 호출과 공유 카드**

`InsightCard(activity: activity, insight: insight, condition: condition,` 호출에 `headline: headline,`을 `insight: insight,` 다음에 추가.

`ShareCardScreen(activity: activity, detail: detail, insight: insight, manager: manager, condition: condition,`의 `insight: insight`를 `insight: shareInsight`로.

- [ ] **Step 4: InsightCard 표시**

`private struct InsightCard: View {`의 `let insight: InsightResult?` 아래에:

```swift
    /// 카드 판정 요약 — 있고 드문 사건·대체가 아니면 제목·사실·다음 행동을 이것으로
    var headline: RunHeadline? = nil
    private var usesHeadline: Bool {
        guard let h = headline else { return false }
        return h.source != .rareEvent && h.source != .fallback
    }
```

제목 `Text(insight?.title ?? AppLanguage.shared.s("오늘의 러닝", "Today's Run"))`를:

```swift
                    Text((usesHeadline ? headline?.title : nil) ?? insight?.title ?? AppLanguage.shared.s("오늘의 러닝", "Today's Run"))
```

부연 `Text(displayDetail)` 블록(`.font(.subheadline)` · `.foregroundStyle(.white.opacity(0.72))` · `.contentTransition(.opacity)`)을:

```swift
                    Text(usesHeadline ? (headline?.fact ?? displayDetail) : displayDetail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .contentTransition(.opacity)
                    // 다음 행동 — 총평의 "다음" 한 문장(없으면 숨김). 드문 사건·대체에도 붙인다
                    if let next = headline?.next {
                        Text(next)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                    }
```

- [ ] **Step 5: 빌드 확인** — Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 6: 커밋**

```bash
cd /Users/hns/MIMORunning/MIMORunning && git add MIMORunning/Views/ActivityDetailView.swift && git commit -m "$(cat <<'EOF'
상세 화면 오늘의 인사이트 — RunHeadline 연결(제목·핵심 사실·다음 행동), 공유 카드 헤드라인도 같은 제목

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## 실기기 확인 포인트(사용자)

1. 9/29 러닝: "가벼워진 러닝 / 같은 페이스에 심박 7bpm 낮음 · 폼은 끝까지 평소 범위 / 대회 훈련 계획상 테이퍼 주예요…"
2. 대회·첫 완주·기록 향상 러닝은 지금처럼 엔진 제목(대회 비교 줄 포함).
3. 워치 없는 러닝은 지금과 같음.
4. 카드 만들기 헤드라인이 맨 위 카드 제목과 같은지.
