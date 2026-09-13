# 3단계 폼 형태 문장 + 총평 5줄 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 폼 카드의 네 km 선차트 아래에 러닝을 초(0~30%)·중(30~70%)·말(70~100%)로 나눈 폼 형태 문장("처음 4km는 몸을 풀고, 중반엔 보폭으로 속도를 냈고, 끝까지 폼을 유지했어요.")을 붙이고, 리듬 카드 하단 칩 자리에 색점 + 축 + 상태어 5줄 총평(러닝폼·거리 적응·심박·훈련부하·유산소)을 넣는다.

**Architecture:** 순수 엔진 2개 — `FormPhase`(Insight/)가 스플릿을 거리 비율로 3단계로 나눠 각 단계 페이스 구간의 평소 범위(±1.2SD, `FormNarrative.status`와 같은 눈금)와 비교해 패턴을 판정하고 문장·짧은 상태어를 만든다. `RunSummary`(Insight/)는 각 카드가 이미 내는 결론(폼 형태·거리 문맥·존 분포·부하·VO2 등급)을 받아 `RunSummaryLine` 배열을 만든다. 표시는 공유 컴포넌트 `RunSummaryLinesView(lines:scale:)` 하나만 쓴다(CLAUDE.md §5.8). 뷰는 입력을 모아 넘기기만 한다.

**Tech Stack:** SwiftUI · Swift Charts(`RuleMark`) · Swift Testing(`@Suite`/`@Test`, 문자열 검사는 `.serialized`) · 기존 `FormNarrative.status`, `EffortLoad.rolling*`, `RunningFormBaseline`.

**합의된 설계(대화에서 확정)**
- 폼은 기온 무관·페이스 정규화: 각 단계의 페이스로 `baseline.cutoffs.band(of:)` → 그 구간의 `FormStat`로 판정. 판정 기준은 범위 바 눈금(±1.2SD)과 같은 `FormNarrative.status`.
- 러닝 길이 무관: km가 아니라 거리 비율 30/70%. 풀 스플릿 6개 미만 · 기준선 없음 · 인터벌 → 침묵(nil).
- 패턴 어휘: 끝까지 유지 / 후반 무거워짐(케이던스↓·보폭↓·접지↑, 수직진폭÷보폭↑는 강화) / 회전 방어 / 위로 튀기 / 몸 풀기 / 보폭·회전으로 가속.
- 문장은 차트 아래 한 줄. 발동 시 50% 중앙 점선 대신 30%·70% 점선 2개. 기존 "폼 변화" 인사이트는 3단계 문장이 있으면 내린다(중복). 거리 문맥이면 "N km 후반엔 흔한 변화예요." 덧붙임.
- 총평: 색은 초록(`Theme.positive`)·노랑(`Theme.caution` 신설 `FF9F0A`) 둘만, 빨강 없음. 등급어("매우 좋음") 대신 관찰 사실. 데이터 없는 축은 줄 생략. 2줄 이상일 때만 표시, 아니면 기존 한 줄 칩 유지. 연속일은 훈련부하 줄에 흡수.

**레이아웃·색·축·숫자 형식은 위에 적힌 것 외에 바꾸지 않는다** (사용자 피드백 메모). 새 문장 스타일은 기존 `narrative`와 동일(11.5pt · white 0.80 · lineSpacing 3).

---

## 파일 맵

| 파일 | 역할 | 작업 |
|---|---|---|
| `MIMORunning/Insight/FormPhase.swift` | 3단계 분할·판정·문장·상태어 · `bandStats(in:paceSecPerKm:gctShift:)` | 생성 |
| `MIMORunning/Insight/RunSummary.swift` | `RunSummaryLine`·`RunSummaryInput`·`RunSummary.lines`·`vo2Level` | 생성 |
| `MIMORunning/Views/RunSummaryLinesView.swift` | 총평 공유 컴포넌트(scale) | 생성 |
| `MIMORunning/Theme/Theme.swift` | `Theme.caution` | 수정 |
| `MIMORunning/Views/RunFormCardView.swift` | `formPhaseResult` · 차트 아래 문장 · 30/70 점선 · 폼 변화 억제 | 수정 |
| `MIMORunning/Views/RunInsightTabCard.swift` | 리듬 카드 `effortIndex` 전달 · `effortLoadRuns` 공유 헬퍼 · 총평 표시 · `vo2SubLabel`이 `RunSummary.vo2Level` 사용 | 수정 |
| `MIMORunningTests/FormPhaseTests.swift` | | 생성 |
| `MIMORunningTests/RunSummaryTests.swift` | | 생성 |

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

새 Swift 파일은 폴더에 넣으면 타깃에 자동 포함된다(파일 시스템 동기화 그룹). `cannot find 'X' in scope`가 나면 Xcode에서 타깃 멤버십을 확인한다. 테스트 파일은 `MIMORunningTests/`에 둔다. `.claude/worktrees/` 아래는 건드리지 않는다.

**참고 타입(기존)**
- `SplitData(id:distanceM:duration:avgHeartRate:avgCadence:avgPower:avgGroundContactTime:avgStrideLength:avgVerticalOscillation:)` — `Models/Activity.swift:216`. `paceSecPerKm` 계산 프로퍼티.
- `FormStat(median:sd:count:p10:p90:)` · `lower = median − 1.2sd` · `upper = median + 1.2sd` — `Insight/RunningFormBaseline.swift:44`.
- `RunningFormBaseline.cutoffs.band(of: pace) -> PaceBand?` · `.bands[PaceBand] -> BandBaseline?` · `BandBaseline.isJudgeable/cadence/strideLength/groundContact` · `.gctBaselineResidualMean`.
- `FormNarrative.Metric { cadence, stride, groundContact, verticalOsc }` · `FormNarrative.Status { inRange, above, below, unknown }` · `FormNarrative.status(rawValue:stat:metric:)` · `FormNarrative.driftAdjustedGCT(_:baselineResidualMean:gctShift:)` · `FormNarrative.isPlannedHighIntensity(_:)`.
- `WorkoutType { interval, longRun, easy, tempo, buildUp, lsd, distanceRun, race, general }` · `.koreanLabel`(L.s로 이미 양언어).
- `EffortLoad.rollingWeekOverWeek(runs:asOf:) -> Double?` · `EffortLoad.rollingAcuteChronic(runs:asOf:) -> (ratio, label: RatioLabel)?` · `RatioLabel { low, steady, high, veryHigh }`.
- `AppLanguage.shared.isEnglish` · `L.s(ko, en)`.

---

### Task 1: FormPhase 엔진 — 3단계 분할과 패턴 판정

> **리뷰 반영(구현 완료 후 확정)**: `classify(splits:paceScale:bandFor:)` — `paceScale` = GAP ÷ 실측 페이스, 밴드 조회에만 곱한다. `accelDeltaSec = 20`(초기→중기 가속 문턱, 후반 둔화는 10초 유지). 몸 풀기는 중기가 2개 이상 판정 가능할 때만. 회전 방어는 접지↑가 없을 때만. `phases()`는 900m 미만 스플릿 제외·id 정렬·거리 0 그룹이면 nil. 아래 코드 블록은 최초 버전이며 커밋된 파일이 기준이다.

**Files:**
- Create: `MIMORunning/Insight/FormPhase.swift`
- Test: `MIMORunningTests/FormPhaseTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`MIMORunningTests/FormPhaseTests.swift`:

```swift
import Testing
import Foundation
@testable import MIMORunning

/// 초·중·말 3단계 폼 형태 판정. 문장 검사는 `AppLanguage.shared`를 건드리므로 직렬 실행.
@Suite("FormPhase 3단계 폼 형태", .serialized)
struct FormPhaseTests {

    // MARK: 픽스처

    /// 1km 스플릿. 기본값은 평소 범위 한가운데.
    private func split(_ id: Int, pace: Double = 375,
                       cad: Int? = 175, sl: Double? = 0.92, gct: Double? = 255, vo: Double? = 8.4) -> SplitData {
        SplitData(id: id, distanceM: 1000, duration: pace,
                  avgHeartRate: 150, avgCadence: cad, avgPower: nil,
                  avgGroundContactTime: gct, avgStrideLength: sl, avgVerticalOscillation: vo)
    }

    private func stat(_ median: Double, sd: Double) -> FormStat {
        FormStat(median: median, sd: sd, count: 30, p10: nil, p90: nil)
    }

    /// 평소 범위(±1.2SD, 반올림): 케이던스 171~179 · 보폭 0.88~0.96 · 접지 245~265
    private var band: FormPhase.BandStats {
        FormPhase.BandStats(cadence: stat(175, sd: 3), stride: stat(0.92, sd: 0.03), groundContact: stat(255, sd: 8))
    }

    private func classify(_ splits: [SplitData]) -> FormPhase.Result? {
        FormPhase.classify(splits: splits, bandFor: { _ in band })
    }

    // MARK: 분할

    @Test func sixSplitsSplitTwoTwoTwo() {
        let p = FormPhase.phases((1...6).map { split($0) })
        #expect(p?.early.splitCount == 2)
        #expect(p?.mid.splitCount == 2)
        #expect(p?.late.splitCount == 2)
        #expect(p?.early.endKm == 2)
        #expect(p?.late.startKm == 4)
    }

    @Test func sixteenSplitsUseThirtySeventyByDistance() {
        let p = FormPhase.phases((1...16).map { split($0) })
        #expect(p?.early.splitCount == 5)
        #expect(p?.mid.splitCount == 6)
        #expect(p?.late.splitCount == 5)
        #expect(p?.early.endKm == 5)
        #expect(p?.late.startKm == 11)
        #expect(p?.late.endKm == 16)
    }

    @Test func fewerThanSixSplitsIsSilent() {
        #expect(FormPhase.phases((1...5).map { split($0) }) == nil)
        #expect(classify((1...5).map { split($0) }) == nil)
    }

    @Test func phaseStatsAveragePaceAndMetrics() {
        let s = [split(1, pace: 400, cad: 170), split(2, pace: 380, cad: 172)] + (3...6).map { split($0) }
        let p = FormPhase.phases(s)
        #expect(p?.early.paceSecPerKm == 390)
        #expect(p?.early.cadence == 171)
    }

    // MARK: 말기 패턴

    @Test func allInRangeIsHeld() {
        let r = classify((1...10).map { split($0) })
        #expect(r?.late == .held)
        #expect(r?.early == nil)
        #expect(r?.mid == nil)
        #expect(r?.isHeld == true)
    }

    @Test func lateStrideDownAndGCTUpIsHeavier() {
        // 10개: 말기 = 8~10km. 수직진폭은 그대로(8.4) → 보폭이 줄어 비율만 올라도 verticalOsc 신호는 붙지 않는다
        let s = (1...7).map { split($0) } + (8...10).map { split($0, sl: 0.85, gct: 272) }
        let r = classify(s)
        #expect(r?.late == .heavier([.stride, .groundContact]))
        #expect(r?.lateStartKm == 7)
        #expect(r?.totalKm == 10)
    }

    @Test func lateCadenceDropAloneIsHeavierWithCadenceSignal() {
        let s = (1...7).map { split($0) } + (8...10).map { split($0, cad: 166) }
        #expect(classify(s)?.late == .heavier([.cadence]))
    }

    @Test func slowedLateWithStrideDownButCadenceHeldIsCadenceDefended() {
        let s = (1...7).map { split($0, pace: 375) } + (8...10).map { split($0, pace: 395, cad: 175, sl: 0.85) }
        #expect(classify(s)?.late == .cadenceDefended)
    }

    @Test func strideDownWithVerticalRatioUpIsBouncier() {
        // 중기 8.4cm·비율 8.4/92 = 9.1% → 말기 9.6cm(+1.2)·비율 9.6/85 = 11.3% (+2.2%p), 접지는 범위 안
        let s = (1...7).map { split($0) } + (8...10).map { split($0, sl: 0.85, vo: 9.6) }
        #expect(classify(s)?.late == .bouncier)
    }

    @Test func heavierGainsVerticalOscSignalWhenRatioRises() {
        // 보폭↓ + 접지↑ + 비율↑ → [.stride, .groundContact, .verticalOsc]
        let s = (1...7).map { split($0) } + (8...10).map { split($0, sl: 0.85, gct: 272, vo: 9.6) }
        #expect(classify(s)?.late == .heavier([.stride, .groundContact, .verticalOsc]))
    }

    // MARK: 초기·중기 패턴

    @Test func earlyOffRangeThenInRangeIsWarmup() {
        let s = (1...3).map { split($0, pace: 400, sl: 0.85, gct: 270) } + (4...10).map { split($0) }
        let r = classify(s)
        #expect(r?.early == .warmup)
        #expect(r?.late == .held)
        #expect(r?.earlyEndKm == 3)
    }

    @Test func earlyAndMidBothOffRangeIsNotWarmup() {
        let s = (1...7).map { split($0, sl: 0.85) } + (8...10).map { split($0) }
        #expect(classify(s)?.early == nil)
    }

    @Test func midFasterWithLongerStrideIsStrideDriven() {
        // 초기 400 → 중기 375 (25초 빨라짐), 보폭 0.88 → 0.94, 케이던스 고정
        let s = (1...3).map { split($0, pace: 400, sl: 0.88) } + (4...7).map { split($0, pace: 375, sl: 0.94) } + (8...10).map { split($0, pace: 375, sl: 0.94) }
        #expect(classify(s)?.mid == .strideDriven)
    }

    @Test func midFasterWithQuickerStepsIsCadenceDriven() {
        let s = (1...3).map { split($0, pace: 400, cad: 172) } + (4...10).map { split($0, pace: 375, cad: 176) }
        #expect(classify(s)?.mid == .cadenceDriven)
    }

    @Test func midFasterWithBothIsBoth() {
        let s = (1...3).map { split($0, pace: 400, cad: 172, sl: 0.88) } + (4...10).map { split($0, pace: 375, cad: 176, sl: 0.94) }
        #expect(classify(s)?.mid == .both)
    }

    @Test func midNotFasterHasNoMidPattern() {
        let s = (1...3).map { split($0, sl: 0.88) } + (4...10).map { split($0, sl: 0.94) }
        #expect(classify(s)?.mid == nil)
    }

    // MARK: 침묵 조건

    @Test func noBandForAnyPhaseIsSilent() {
        #expect(FormPhase.classify(splits: (1...10).map { split($0) }, bandFor: { _ in nil }) == nil)
    }

    @Test func lateNeedsTwoKnownMetrics() {
        // 말기 보폭·접지 결측 → 케이던스 하나만 알면 침묵
        let s = (1...7).map { split($0) } + (8...10).map { split($0, sl: nil, gct: nil) }
        #expect(classify(s) == nil)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run:
```bash
xcodebuild test -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MIMORunningTests/FormPhaseTests 2>&1 | grep -E 'Test (Suite|Case)|passed|failed|error:' | tail -30
```
Expected: `error: cannot find 'FormPhase' in scope` (컴파일 실패).

- [ ] **Step 3: 엔진 구현**

`MIMORunning/Insight/FormPhase.swift`:

```swift
import Foundation

/// 러닝을 거리 비율로 초(0~30%)·중(30~70%)·말(70~100%) 세 단계로 나눠 폼의 형태를 판정한다.
///
/// - 기준은 폼 카드 눈금과 같다: 그 단계 **페이스 구간**의 평소 범위(±1.2SD, `FormNarrative.status`).
///   기온과 무관하고 페이스로 정규화되므로 그날 데이터만으로 말할 수 있다.
/// - 러닝 길이와 무관: km가 아니라 거리 비율로 나눈다. 풀 스플릿 6개 미만이면 nil.
/// - 기준선이 없어 어느 단계도 판정할 수 없으면 nil(침묵). 말기는 케이던스·보폭·접지 중 2개 이상 알아야 한다.
enum FormPhase {
    typealias Metric = FormNarrative.Metric
    typealias Status = FormNarrative.Status

    /// 한 단계의 페이스에 해당하는 평소 범위. 뷰가 기준선에서 만들어 넘긴다(`bandStats(in:paceSecPerKm:gctShift:)`).
    struct BandStats {
        var cadence: FormStat?
        var stride: FormStat?
        var groundContact: FormStat?
    }

    struct PhaseStats: Equatable {
        let splitCount: Int
        let startKm: Double
        let endKm: Double
        let paceSecPerKm: Double
        let cadence: Double?
        let stride: Double?
        let groundContact: Double?
        let verticalOsc: Double?
        /// 수직진폭 ÷ 보폭 (%) — 앞이 아니라 위로 가는 움직임의 비율
        var verticalRatio: Double? {
            guard let vo = verticalOsc, let sl = stride, sl > 0 else { return nil }
            return vo / (sl * 100) * 100
        }
    }

    enum Early: Equatable { case warmup }
    enum Mid: Equatable { case strideDriven, cadenceDriven, both }
    enum Late: Equatable {
        case held
        /// 피로 방향 이탈. 순서 고정: cadence → stride → groundContact → verticalOsc
        case heavier([Metric])
        case cadenceDefended
        case bouncier
    }

    struct Result: Equatable {
        let early: Early?
        let mid: Mid?
        let late: Late
        let earlyEndKm: Double
        let lateStartKm: Double
        let totalKm: Double
        var isHeld: Bool { late == .held }
    }

    static let minSplits = 6
    static let earlyFraction = 0.30
    static let lateFraction = 0.70
    /// 단계 간 페이스 차이가 이 이상이어야 "빨라졌다/느려졌다"
    static let paceDeltaSec = 10.0
    static let strideDeltaM = 0.02
    static let cadenceSameSPM = 2.0
    static let cadenceGainSPM = 3.0
    static let verticalRatioDeltaPct = 0.5
    /// 비율은 보폭만 줄어도 오르므로 수직진폭 자체도 이만큼 늘어야 "위로 튐"으로 본다
    static let verticalOscDeltaCm = 0.2

    // MARK: - 분할

    static func phases(_ splits: [SplitData]) -> (early: PhaseStats, mid: PhaseStats, late: PhaseStats)? {
        guard splits.count >= minSplits else { return nil }
        let totalM = splits.map(\.distanceM).reduce(0, +)
        guard totalM > 0 else { return nil }

        var groups: [[SplitData]] = [[], [], []]
        var startM: [Double?] = [nil, nil, nil]
        var endM: [Double] = [0, 0, 0]
        var cum = 0.0
        for s in splits {
            let midFrac = (cum + s.distanceM / 2) / totalM
            let g = midFrac < earlyFraction ? 0 : (midFrac >= lateFraction ? 2 : 1)
            if startM[g] == nil { startM[g] = cum }
            groups[g].append(s)
            cum += s.distanceM
            endM[g] = cum
        }
        guard groups.allSatisfy({ !$0.isEmpty }) else { return nil }

        func avg(_ vals: [Double?]) -> Double? {
            let v = vals.compactMap { $0 }
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        func stats(_ i: Int) -> PhaseStats {
            let g = groups[i]
            let distKm = g.map(\.distanceM).reduce(0, +) / 1000
            let dur = g.map(\.duration).reduce(0, +)
            return PhaseStats(
                splitCount: g.count,
                startKm: (startM[i] ?? 0) / 1000,
                endKm: endM[i] / 1000,
                paceSecPerKm: distKm > 0 ? dur / distKm : 0,
                cadence: avg(g.map { $0.avgCadence.map(Double.init) }),
                stride: avg(g.map(\.avgStrideLength)),
                groundContact: avg(g.map(\.avgGroundContactTime)),
                verticalOsc: avg(g.map(\.avgVerticalOscillation)))
        }
        return (stats(0), stats(1), stats(2))
    }

    // MARK: - 판정

    struct Signals {
        let cadence: Status
        let stride: Status
        let groundContact: Status
        var knownCount: Int { [cadence, stride, groundContact].filter { $0 != .unknown }.count }
        /// 피로 방향 이탈 — 케이던스↓ · 보폭↓ · 접지↑ (순서 고정)
        var fatigue: [Metric] {
            var out: [Metric] = []
            if cadence == .below { out.append(.cadence) }
            if stride == .below { out.append(.stride) }
            if groundContact == .above { out.append(.groundContact) }
            return out
        }
    }

    static func signals(_ p: PhaseStats, _ band: BandStats?) -> Signals {
        Signals(cadence: FormNarrative.status(rawValue: p.cadence, stat: band?.cadence, metric: .cadence),
                stride: FormNarrative.status(rawValue: p.stride, stat: band?.stride, metric: .stride),
                groundContact: FormNarrative.status(rawValue: p.groundContact, stat: band?.groundContact, metric: .groundContact))
    }

    /// - Parameter bandFor: 단계 페이스(sec/km) → 그 구간의 평소 범위. 구간 밖·판정불가면 nil.
    static func classify(splits: [SplitData], bandFor: (Double) -> BandStats?) -> Result? {
        guard let p = phases(splits) else { return nil }
        let e = p.early, m = p.mid, l = p.late
        let eS = signals(e, bandFor(e.paceSecPerKm))
        let mS = signals(m, bandFor(m.paceSecPerKm))
        let lS = signals(l, bandFor(l.paceSecPerKm))
        guard lS.knownCount >= 2 else { return nil }

        // 말기
        let slowedLate = l.paceSecPerKm - m.paceSecPerKm >= paceDeltaSec
        // 위로 튐 = 수직진폭↑(≥0.2cm) 그리고 수직진폭÷보폭 비율↑(≥0.5%p). 보폭만 줄어 비율이 오른 경우는 제외.
        let ratioUp: Bool = {
            guard let a = m.verticalRatio, let b = l.verticalRatio,
                  let va = m.verticalOsc, let vb = l.verticalOsc else { return false }
            return vb - va >= verticalOscDeltaCm && b - a >= verticalRatioDeltaPct
        }()
        let late: Late
        if slowedLate, lS.stride == .below, lS.cadence == .inRange || lS.cadence == .above {
            late = .cadenceDefended
        } else if lS.stride == .below, ratioUp, lS.groundContact != .above {
            late = .bouncier
        } else if !lS.fatigue.isEmpty {
            late = .heavier(lS.fatigue + (ratioUp ? [.verticalOsc] : []))
        } else {
            late = .held
        }

        // 초기 — 초기만 벗어나고 중기는 범위 안이면 몸 풀기
        let early: Early? = (!eS.fatigue.isEmpty && mS.fatigue.isEmpty) ? .warmup : nil

        // 중기 — 초기보다 빨라졌을 때 어느 레버로 속도를 냈는지
        var mid: Mid? = nil
        if e.paceSecPerKm - m.paceSecPerKm >= paceDeltaSec,
           let es = e.stride, let ms = m.stride, let ec = e.cadence, let mc = m.cadence {
            let strideUp = ms - es >= strideDeltaM
            let cadUp = mc - ec >= cadenceGainSPM
            if strideUp && cadUp { mid = .both }
            else if strideUp && abs(mc - ec) < cadenceSameSPM { mid = .strideDriven }
            else if cadUp && abs(ms - es) < strideDeltaM { mid = .cadenceDriven }
        }

        return Result(early: early, mid: mid, late: late,
                      earlyEndKm: e.endKm, lateStartKm: l.startKm, totalKm: l.endKm)
    }

    // MARK: - 기준선 → 단계 범위

    /// 단계 페이스가 속한 구간의 평소 범위. 구간 밖이거나 표본 부족(판정불가)이면 nil.
    /// 접지는 폼 카드와 같은 시점 보정(`driftAdjustedGCT`)을 거친다.
    static func bandStats(in baseline: RunningFormBaseline, paceSecPerKm: Double, gctShift: MRFormShift?) -> BandStats? {
        guard let band = baseline.cutoffs.band(of: paceSecPerKm),
              let b = baseline.bands[band], b.isJudgeable else { return nil }
        let gct = FormNarrative.driftAdjustedGCT(b.groundContact,
                                                 baselineResidualMean: baseline.gctBaselineResidualMean,
                                                 gctShift: gctShift)
        return BandStats(cadence: b.cadence, stride: b.strideLength, groundContact: gct)
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: 위 테스트 명령. Expected: `FormPhaseTests` 18 tests passed.

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Insight/FormPhase.swift MIMORunningTests/FormPhaseTests.swift
git commit -m "FormPhase — 러닝을 거리 비율 30/70%로 초·중·말 나눠 단계 페이스 구간의 평소 범위로 폼 형태 판정

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: FormPhase 문장·짧은 상태어

**Files:**
- Modify: `MIMORunning/Insight/FormPhase.swift` (끝에 `// MARK: - 문장` 섹션 추가)
- Test: `MIMORunningTests/FormPhaseTests.swift` (테스트 추가)

- [ ] **Step 1: 실패하는 테스트 추가**

`FormPhaseTests` 구조체 안, `// MARK: 침묵 조건` 앞에 추가:

```swift
    // MARK: 문장

    private func ko(_ r: FormPhase.Result, long: Bool = false) -> String {
        AppLanguage.shared.isEnglish = false
        return FormPhase.sentence(r, isLongDistance: long)
    }
    private func en(_ r: FormPhase.Result, long: Bool = false) -> String {
        AppLanguage.shared.isEnglish = true
        defer { AppLanguage.shared.isEnglish = false }
        return FormPhase.sentence(r, isLongDistance: long)
    }
    private func result(early: FormPhase.Early? = nil, mid: FormPhase.Mid? = nil, late: FormPhase.Late,
                        earlyEnd: Double = 4, lateStart: Double = 12, total: Double = 16) -> FormPhase.Result {
        FormPhase.Result(early: early, mid: mid, late: late, earlyEndKm: earlyEnd, lateStartKm: lateStart, totalKm: total)
    }

    @Test func heldAloneIsOneClause() {
        #expect(ko(result(late: .held)) == "끝까지 폼을 유지했어요.")
        #expect(en(result(late: .held)) == "Your form held to the finish.")
    }

    @Test func warmupAccelerationHeldJoinsThreeClauses() {
        let r = result(early: .warmup, mid: .strideDriven, late: .held)
        #expect(ko(r) == "처음 4km는 몸을 풀고, 중반엔 보폭으로 속도를 냈고, 끝까지 폼을 유지했어요.")
    }

    @Test func heavierListsSignalsWithLastKm() {
        let r = result(late: .heavier([.stride, .groundContact]))
        #expect(ko(r) == "마지막 4km엔 보폭이 줄고 접지가 길어졌어요.")
        #expect(en(r) == "Over the last 4 km stride shortened and ground contact lengthened.")
    }

    @Test func heavierThreeSignals() {
        let r = result(late: .heavier([.cadence, .stride, .verticalOsc]))
        #expect(ko(r) == "마지막 4km엔 케이던스가 내려가고 보폭이 줄고 위아래 움직임이 늘었어요.")
    }

    @Test func cadenceDefendedAndBouncier() {
        #expect(ko(result(late: .cadenceDefended)) == "마지막 4km엔 속도가 떨어졌지만 발 회전은 지켰어요.")
        #expect(ko(result(late: .bouncier)) == "마지막 4km엔 앞보다 위로 가는 움직임이 늘었어요.")
    }

    @Test func longDistanceAppendsCommonNoteOnlyWhenNotHeld() {
        #expect(ko(result(late: .heavier([.stride])), long: true) == "마지막 4km엔 보폭이 줄었어요. 16km 후반엔 흔한 변화예요.")
        #expect(ko(result(late: .held), long: true) == "끝까지 폼을 유지했어요.")
    }

    @Test func midVariants() {
        #expect(ko(result(mid: .cadenceDriven, late: .held)) == "중반엔 발 회전으로 속도를 냈고, 끝까지 폼을 유지했어요.")
        #expect(ko(result(mid: .both, late: .held)) == "중반엔 보폭과 회전을 함께 올려 속도를 냈고, 끝까지 폼을 유지했어요.")
    }

    @Test func shortStates() {
        AppLanguage.shared.isEnglish = false
        #expect(FormPhase.shortState(result(late: .held)) == "끝까지 유지")
        #expect(FormPhase.shortState(result(late: .heavier([.stride]))) == "마지막 4km 살짝 무거워짐")
        #expect(FormPhase.shortState(result(late: .cadenceDefended)) == "후반 회전은 유지")
        #expect(FormPhase.shortState(result(late: .bouncier)) == "후반 위로 튐")
    }
```

- [ ] **Step 2: 실패 확인**

Run: 테스트 명령(`FormPhaseTests`). Expected: `error: type 'FormPhase' has no member 'sentence'`.

- [ ] **Step 3: 문장 구현**

`FormPhase.swift` 마지막 `}` 앞에 추가:

```swift
    // MARK: - 문장

    /// 초·중·말 절을 쉼표로 이어 한 문장으로. 거리 문맥이고 말기가 유지가 아니면 "N km 후반엔 흔한 변화예요." 덧붙임.
    static func sentence(_ r: Result, isLongDistance: Bool) -> String {
        let L = AppLanguage.shared
        let earlyKm = String(format: "%.0f", r.earlyEndKm)
        let lateKm  = String(format: "%.0f", r.totalKm - r.lateStartKm)
        var ko: [String] = []
        var en: [String] = []

        if r.early == .warmup {
            ko.append("처음 \(earlyKm)km는 몸을 풀고")
            en.append("the first \(earlyKm) km were a warm-up")
        }
        switch r.mid {
        case .strideDriven?:
            ko.append("중반엔 보폭으로 속도를 냈고")
            en.append("you sped up mid-run with a longer stride")
        case .cadenceDriven?:
            ko.append("중반엔 발 회전으로 속도를 냈고")
            en.append("you sped up mid-run with quicker steps")
        case .both?:
            ko.append("중반엔 보폭과 회전을 함께 올려 속도를 냈고")
            en.append("you sped up mid-run with a longer stride and quicker steps")
        case nil:
            break
        }
        switch r.late {
        case .held:
            ko.append("끝까지 폼을 유지했어요")
            en.append("your form held to the finish")
        case .cadenceDefended:
            ko.append("마지막 \(lateKm)km엔 속도가 떨어졌지만 발 회전은 지켰어요")
            en.append("pace faded over the last \(lateKm) km but your cadence held")
        case .bouncier:
            ko.append("마지막 \(lateKm)km엔 앞보다 위로 가는 움직임이 늘었어요")
            en.append("over the last \(lateKm) km more motion went up than forward")
        case .heavier(let signals):
            ko.append("마지막 \(lateKm)km엔 " + joinKo(signals))
            en.append("over the last \(lateKm) km " + joinEn(signals))
        }

        var koS = ko.joined(separator: ", ") + "."
        var enS = en.joined(separator: ", ") + "."
        enS = enS.prefix(1).uppercased() + enS.dropFirst()
        if isLongDistance, r.late != .held {
            let d = String(format: "%.0f", r.totalKm)
            koS += " \(d)km 후반엔 흔한 변화예요."
            enS += " Common late in a \(d) km run."
        }
        return L.s(koS, enS)
    }

    /// 총평 줄용 짧은 상태어
    static func shortState(_ r: Result) -> String {
        let L = AppLanguage.shared
        let lateKm = String(format: "%.0f", r.totalKm - r.lateStartKm)
        switch r.late {
        case .held:            return L.s("끝까지 유지", "Held to the finish")
        case .heavier:         return L.s("마지막 \(lateKm)km 살짝 무거워짐", "A bit heavier in the last \(lateKm) km")
        case .cadenceDefended: return L.s("후반 회전은 유지", "Cadence held late")
        case .bouncier:        return L.s("후반 위로 튐", "Bouncier late")
        }
    }

    /// 한국어 연결: 마지막 신호만 종결형 — "보폭이 줄고 접지가 길어졌어요"
    private static func joinKo(_ signals: [Metric]) -> String {
        func conj(_ m: Metric) -> String {
            switch m {
            case .cadence:       return "케이던스가 내려가고"
            case .stride:        return "보폭이 줄고"
            case .groundContact: return "접지가 길어지고"
            case .verticalOsc:   return "위아래 움직임이 늘고"
            }
        }
        func final_(_ m: Metric) -> String {
            switch m {
            case .cadence:       return "케이던스가 내려갔어요"
            case .stride:        return "보폭이 줄었어요"
            case .groundContact: return "접지가 길어졌어요"
            case .verticalOsc:   return "위아래 움직임이 늘었어요"
            }
        }
        guard let last = signals.last else { return "" }
        return (signals.dropLast().map(conj) + [final_(last)]).joined(separator: " ")
    }

    private static func joinEn(_ signals: [Metric]) -> String {
        func phrase(_ m: Metric) -> String {
            switch m {
            case .cadence:       return "cadence dropped"
            case .stride:        return "stride shortened"
            case .groundContact: return "ground contact lengthened"
            case .verticalOsc:   return "vertical motion increased"
            }
        }
        let p = signals.map(phrase)
        guard p.count > 1 else { return p.first ?? "" }
        return p.dropLast().joined(separator: ", ") + " and " + p[p.count - 1]
    }
```

- [ ] **Step 4: 통과 확인**

Run: 테스트 명령(`FormPhaseTests`). Expected: 26 tests passed.

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Insight/FormPhase.swift MIMORunningTests/FormPhaseTests.swift
git commit -m "FormPhase 문장 — 초·중·말 절을 한 문장으로, 총평용 짧은 상태어

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: 폼 카드에 3단계 문장 + 30/70 점선 + 폼 변화 억제

**Files:**
- Modify: `MIMORunning/Views/RunFormCardView.swift`
  - `longDistanceFormChangeInsight` (line ~664)
  - `body` (line ~813–841)
  - `formSeriesCell`의 midpoint `RuleMark` (line ~1315–1321 · ~1422–1425)

- [ ] **Step 1: `formPhaseResult` 계산 프로퍼티 추가**

`private var isLongDistanceContext: Bool { … }` (line ~206–212) 바로 아래에 추가:

```swift
    /// 초·중·말 폼 형태 — 풀 스플릿 6개 이상 + 기준선 있을 때만. 인터벌은 제외.
    /// 판정(fullSplits)과 표시(버킷)를 섞지 않는다 — 문장은 판정, 30/70 점선 위치만 차트에 표시.
    private var formPhaseResult: FormPhase.Result? {
        guard !isInterval, let bl = baseline else { return nil }
        let gctShift = formShifts.first(where: { $0.metric.key == "gct" })
        // 기준선 밴드는 GAP 기준 — 밴드 조회 페이스도 GAP 배율(GAP ÷ 실측)로 맞춘다 (bb와 같은 규칙)
        let scale: Double = {
            let distKm = fullSplits.map(\.distanceM).reduce(0, +) / 1000
            let dur = fullSplits.map(\.duration).reduce(0, +)
            guard let gap = runGAP, distKm > 0, dur > 0 else { return 1.0 }
            return gap / (dur / distKm)   // 분모도 스플릿 기준 — 같은 총량에서 나온 비율
        }()
        return FormPhase.classify(splits: fullSplits, paceScale: scale, bandFor: { pace in
            FormPhase.bandStats(in: bl, paceSecPerKm: pace, gctShift: gctShift)
        })
    }
```

- [ ] **Step 2: 폼 변화 인사이트 억제**

`longDistanceFormChangeInsight`의 첫 줄

```swift
        guard isLongDistanceContext else { return nil }
```
을
```swift
        // 3단계 폼 문장이 나오면 이탈 위치까지 그 문장이 말한다 — 같은 사실을 두 번 적지 않는다.
        guard isLongDistanceContext, formPhaseResult == nil else { return nil }
```
로 바꾼다.

- [ ] **Step 3: 차트 아래 문장**

`body`에서
```swift
                if showTrendSection { splitFormTrendSection }
```
을
```swift
                if showTrendSection {
                    splitFormTrendSection
                    if let phase = formPhaseResult {
                        Text(FormPhase.sentence(phase, isLongDistance: isLongDistanceContext))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.white.opacity(0.80))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
```
로 바꾼다. (스타일은 `causalChain` 하단 `narrative` 텍스트와 동일.)

- [ ] **Step 4: 30/70 점선**

`formSeriesCell` 안에서 `midKm`이 계산된 직후(line ~1321 근처)에 추가:

```swift
        // 3단계 문장이 있으면 50% 중앙선 대신 30%·70% 경계 2개
        let phaseMarkKms: [Double] = formPhaseResult.map { [$0.earlyEndKm, $0.lateStartKm] } ?? [midKm]
```

그리고 Chart 안의
```swift
            // Midpoint divider
            RuleMark(x: .value("", midKm))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                .foregroundStyle(Color.white.opacity(0.15))
```
을
```swift
            // 구간 경계 — 기본은 50% 중앙선, 3단계 문장이 있으면 30%·70%
            ForEach(phaseMarkKms, id: \.self) { km in
                RuleMark(x: .value("", km))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                    .foregroundStyle(Color.white.opacity(0.15))
            }
```
로 바꾼다. 선 굵기·색·대시는 그대로.

- [ ] **Step 5: 빌드 확인**

Run:
```bash
xcodebuild build -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E 'error:|BUILD' | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: 기존 폼 테스트 회귀 확인**

Run:
```bash
xcodebuild test -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MIMORunningTests/FormNarrativeTests \
  -only-testing:MIMORunningTests/FormReferenceBandTests 2>&1 | grep -E 'Test (Suite|Case)|passed|failed|error:' | tail -20
```
Expected: 모두 passed.

- [ ] **Step 7: 커밋**

```bash
git add MIMORunning/Views/RunFormCardView.swift
git commit -m "폼 카드 — km 차트 아래 초·중·말 폼 형태 문장, 발동 시 30/70 점선, 폼 변화 인사이트는 문장에 흡수

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `Theme.caution` + 총평 공유 컴포넌트

**Files:**
- Modify: `MIMORunning/Theme/Theme.swift` (`static let positive` 바로 아래, line ~69)
- Create: `MIMORunning/Views/RunSummaryLinesView.swift`
- Create: `MIMORunning/Insight/RunSummary.swift` (이 태스크에서는 `RunSummaryLine` 타입만; 규칙은 Task 5)

- [ ] **Step 1: 색 추가**

`Theme.swift`의
```swift
    static let positive = Color(hex: "5CE08A")
```
아래에 추가:
```swift
    /// "참고 · 방향 제시" 노랑. 총평 줄의 중립 톤. 빨강은 쓰지 않는다(좌절 방지).
    static let caution = Color(hex: "FF9F0A")
```

- [ ] **Step 2: 줄 타입**

`MIMORunning/Insight/RunSummary.swift` 생성:

```swift
import Foundation

/// 총평 한 줄 — 색점(톤) + 축 이름 + 짧은 상태어(관찰 사실, 등급어 아님).
struct RunSummaryLine: Equatable {
    enum Tone: Equatable { case good, neutral }
    let axis: String
    let state: String
    let tone: Tone
}
```

- [ ] **Step 3: 컴포넌트**

`MIMORunning/Views/RunSummaryLinesView.swift` 생성:

```swift
import SwiftUI

/// 총평 줄 묶음 — 색점 + 축 + 상태어. 리듬 카드 하단과 (추후) 공유 카드가 **이 컴포넌트 하나만** 쓴다(§5.8).
/// 크기는 `scale`로만 조절한다. scale=1 기준: 글자 10pt · 점 7pt · 좌우 여백 12pt · 상하 10pt.
struct RunSummaryLinesView: View {
    let lines: [RunSummaryLine]
    var scale: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 7 * scale) {
                    Circle()
                        .fill(color(line.tone))
                        .frame(width: 7 * scale, height: 7 * scale)
                        .padding(.top, 3.5 * scale)
                    Text(line.axis)
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(1)
                    Text("·")
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(Color.white.opacity(0.35))
                    Text(line.state)
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineSpacing(2 * scale)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12 * scale).padding(.vertical, 10 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
    }

    private func color(_ tone: RunSummaryLine.Tone) -> Color {
        tone == .good ? Theme.positive : Theme.caution
    }
}
```

- [ ] **Step 4: 빌드 확인**

Run: 빌드 명령. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Theme/Theme.swift MIMORunning/Insight/RunSummary.swift MIMORunning/Views/RunSummaryLinesView.swift
git commit -m "총평 줄 컴포넌트 — 색점(초록·노랑) + 축 + 상태어, scale 하나로 크기 조절

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: RunSummary 규칙 엔진

> **리뷰 반영(구현 완료 후 확정)**: `easyIntentTypes = [.easy, .longRun, .lsd]` — 거리주는 빠른 게 정의라 이지 의도로 판정하지 않는다. Zone 4 이상 우세·계획 아님이면 "고강도 구간이 많음 · Zone 3 이상 N%". 부하 급증 문구는 지난주 대비 +30% 이상일 때만 %를 찍고 그 외는 "4주 평균 대비 높음"(음수 %가 노란 점 옆에 오지 않게). 우세 존 동률은 높은 존. 부하 데이터가 없어도 연속일 3일 이상이면 "N일 연속" 줄. 영어 이지 의도 문구는 라벨을 소문자화하지 않음. 아래 코드 블록은 최초 버전이며 커밋된 파일(d2b7cd5)이 기준이다.

**Files:**
- Modify: `MIMORunning/Insight/RunSummary.swift`
- Test: `MIMORunningTests/RunSummaryTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`MIMORunningTests/RunSummaryTests.swift`:

```swift
import Testing
import Foundation
@testable import MIMORunning

/// 총평 5줄 규칙 — 축 순서·생략·톤·상태어. 문자열 검사라 직렬 실행.
@Suite("RunSummary 총평 줄", .serialized)
struct RunSummaryTests {

    private func lines(_ i: RunSummaryInput) -> [RunSummaryLine] {
        AppLanguage.shared.isEnglish = false
        return RunSummary.lines(i)
    }
    private func phase(_ late: FormPhase.Late) -> FormPhase.Result {
        FormPhase.Result(early: nil, mid: nil, late: late, earlyEndKm: 4, lateStartKm: 12, totalKm: 16)
    }

    @Test func emptyInputHasNoLines() {
        #expect(lines(RunSummaryInput()).isEmpty)
    }

    @Test func fullInputHasFiveLinesInOrder() {
        var i = RunSummaryInput()
        i.form = phase(.held)
        i.distKm = 16; i.typicalKm = 7.6
        i.workoutType = .distanceRun
        i.zoneFractions = [2: 0.10, 3: 0.20, 4: 0.62, 5: 0.08]
        i.weekOverWeek = 0.55; i.acuteChronic = .steady; i.streakDays = 4
        i.vo2 = 45.4; i.vo2AgeDecade = "50대"; i.vo2GenderLabel = "남성"
        let out = lines(i)
        #expect(out.map(\.axis) == ["러닝폼", "거리 적응", "심박", "훈련부하", "유산소"])
        #expect(out[0] == RunSummaryLine(axis: "러닝폼", state: "끝까지 유지", tone: .good))
        #expect(out[1] == RunSummaryLine(axis: "거리 적응", state: "평소 2.1배, 범위 안", tone: .good))
        #expect(out[2] == RunSummaryLine(axis: "심박", state: "거리주 기준 높음 · Zone 3 이상 90%", tone: .neutral))
        #expect(out[3] == RunSummaryLine(axis: "훈련부하", state: "이번 주 +55% · 4일 연속", tone: .neutral))
        #expect(out[4] == RunSummaryLine(axis: "유산소", state: "50대 남성 기준 높음", tone: .good))
    }

    // MARK: 러닝폼

    @Test func heavierFormIsNeutralWithShortState() {
        var i = RunSummaryInput(); i.form = phase(.heavier([.stride]))
        #expect(lines(i) == [RunSummaryLine(axis: "러닝폼", state: "마지막 4km 살짝 무거워짐", tone: .neutral)])
    }

    // MARK: 거리 적응

    @Test func distanceBelow130PercentIsOmitted() {
        var i = RunSummaryInput(); i.distKm = 9; i.typicalKm = 7.6
        #expect(lines(i).isEmpty)
    }

    @Test func distanceWithoutFormInfoOmitsRangeClaim() {
        var i = RunSummaryInput(); i.distKm = 16; i.typicalKm = 7.6
        #expect(lines(i) == [RunSummaryLine(axis: "거리 적응", state: "평소 2.1배", tone: .good)])
    }

    @Test func distanceWithHeavierFormIsNeutral() {
        var i = RunSummaryInput(); i.distKm = 16; i.typicalKm = 7.6; i.form = phase(.heavier([.stride]))
        #expect(lines(i).last == RunSummaryLine(axis: "거리 적응", state: "평소 2.1배", tone: .neutral))
    }

    // MARK: 심박

    @Test func zoneTwoMajorityIsJustRight() {
        var i = RunSummaryInput(); i.zoneFractions = [1: 0.1, 2: 0.7, 3: 0.2]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "딱 좋은 강도", tone: .good)])
    }

    @Test func easyIntentWithHighZonesIsFlagged() {
        var i = RunSummaryInput(); i.workoutType = .easy; i.zoneFractions = [2: 0.4, 3: 0.5, 4: 0.1]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "이지런 기준 높음 · Zone 3 이상 60%", tone: .neutral)])
    }

    @Test func plannedHighIntensityInZoneFourIsGood() {
        var i = RunSummaryInput(); i.workoutType = .tempo; i.zoneFractions = [3: 0.3, 4: 0.6, 5: 0.1]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "계획대로 고강도", tone: .good)])
    }

    @Test func generalRunInZoneFourIsNeutral() {
        var i = RunSummaryInput(); i.workoutType = .general; i.zoneFractions = [3: 0.3, 4: 0.6, 5: 0.1]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "고강도 구간이 많음", tone: .neutral)])
    }

    @Test func zoneOneDominantIsRecovery() {
        var i = RunSummaryInput(); i.zoneFractions = [1: 0.6, 2: 0.4]
        #expect(lines(i) == [RunSummaryLine(axis: "심박", state: "가벼운 회복 강도", tone: .good)])
    }

    // MARK: 훈련부하

    @Test func loadOmittedWithoutData() {
        var i = RunSummaryInput(); i.streakDays = 5
        #expect(lines(i).isEmpty)
    }

    @Test func steadyLoadIsGood() {
        var i = RunSummaryInput(); i.weekOverWeek = 0.05; i.acuteChronic = .steady
        #expect(lines(i) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 수준", tone: .good)])
    }

    @Test func highRatioWithoutWeekOverWeekUsesFourWeekWording() {
        var i = RunSummaryInput(); i.acuteChronic = .high
        #expect(lines(i) == [RunSummaryLine(axis: "훈련부하", state: "4주 평균 대비 높음", tone: .neutral)])
    }

    @Test func lowLoadIsLighter() {
        var i = RunSummaryInput(); i.weekOverWeek = -0.4; i.acuteChronic = .low
        #expect(lines(i) == [RunSummaryLine(axis: "훈련부하", state: "평소보다 가볍게", tone: .good)])
    }

    @Test func bigDropWithoutRatioIsLighter() {
        var i = RunSummaryInput(); i.weekOverWeek = -0.4
        #expect(lines(i) == [RunSummaryLine(axis: "훈련부하", state: "평소보다 가볍게", tone: .good)])
    }

    @Test func streakBelowThreeNotAppended() {
        var i = RunSummaryInput(); i.weekOverWeek = 0.0; i.streakDays = 2
        #expect(lines(i).first?.state == "4주 평균 수준")
    }

    // MARK: 유산소

    @Test func vo2Levels() {
        AppLanguage.shared.isEnglish = false
        #expect(RunSummary.vo2Level(20).name == "낮음")
        #expect(RunSummary.vo2Level(30).name == "평균이하")
        #expect(RunSummary.vo2Level(35).name == "평균이상")
        #expect(RunSummary.vo2Level(45.4).name == "높음")
        #expect(RunSummary.vo2Level(60).index == 3)
    }

    @Test func vo2BelowAverageIsNeutral() {
        var i = RunSummaryInput(); i.vo2 = 30; i.vo2AgeDecade = "50대"; i.vo2GenderLabel = ""
        #expect(lines(i) == [RunSummaryLine(axis: "유산소", state: "50대 기준 평균이하", tone: .neutral)])
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: 테스트 명령(`RunSummaryTests`). Expected: `error: cannot find 'RunSummaryInput' in scope`.

- [ ] **Step 3: 규칙 구현**

`MIMORunning/Insight/RunSummary.swift`에 `RunSummaryLine` 아래 추가:

```swift
/// 총평 입력 — 각 카드가 이미 계산한 결론만 받는다. 없는 축은 nil/빈값 → 줄 생략.
struct RunSummaryInput {
    var form: FormPhase.Result? = nil
    var distKm: Double = 0
    var typicalKm: Double? = nil
    var workoutType: WorkoutType = .general
    /// 존 id(1~5) → 비율. 합이 1이 아니어도 된다(내부에서 보이는 존만 정규화).
    var zoneFractions: [Int: Double] = [:]
    /// 지난주 대비 증감률 (0.55 = +55%)
    var weekOverWeek: Double? = nil
    var acuteChronic: EffortLoad.RatioLabel? = nil
    var streakDays: Int = 0
    var vo2: Double? = nil
    var vo2AgeDecade: String = ""
    var vo2GenderLabel: String = ""
}

/// 총평 규칙. 축 순서 고정: 러닝폼 → 거리 적응 → 심박 → 훈련부하 → 유산소.
/// 상태어는 관찰 사실만. 톤은 초록(good)·노랑(neutral) 둘.
enum RunSummary {
    static let distanceRatioMin = 1.30
    /// 이지 의도 유형에서 Zone 3 이상 비율이 이 이상이면 "기준 높음"
    static let easyHighZoneFrac = 0.50
    static let loadJumpMin = 0.30
    static let vo2Bounds: [Double] = [15, 26, 33, 41, 57]
    static let easyIntentTypes: Set<WorkoutType> = [.easy, .longRun, .lsd, .distanceRun]

    /// VO2max 등급 — 리듬 카드 게이지 캡션과 같은 경계.
    static func vo2Level(_ vo2: Double) -> (index: Int, name: String) {
        let L = AppLanguage.shared
        let names = [L.s("낮음", "Low"), L.s("평균이하", "Below avg"), L.s("평균이상", "Above avg"), L.s("높음", "High")]
        var idx = vo2Bounds.count - 2
        for i in 0..<(vo2Bounds.count - 1) where vo2 < vo2Bounds[i + 1] { idx = i; break }
        return (idx, names[idx])
    }

    static func lines(_ i: RunSummaryInput) -> [RunSummaryLine] {
        [formLine(i), distanceLine(i), heartRateLine(i), loadLine(i), aerobicLine(i)].compactMap { $0 }
    }

    // MARK: 축별 규칙

    private static func formLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        guard let f = i.form else { return nil }
        let L = AppLanguage.shared
        return RunSummaryLine(axis: L.s("러닝폼", "Form"), state: FormPhase.shortState(f), tone: f.isHeld ? .good : .neutral)
    }

    private static func distanceLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        guard let t = i.typicalKm, t > 0, i.distKm >= t * distanceRatioMin else { return nil }
        let L = AppLanguage.shared
        let ratio = String(format: "%.1f", i.distKm / t)
        let axis = L.s("거리 적응", "Distance")
        guard let f = i.form else {
            return RunSummaryLine(axis: axis, state: L.s("평소 \(ratio)배", "\(ratio)× usual"), tone: .good)
        }
        return f.isHeld
            ? RunSummaryLine(axis: axis, state: L.s("평소 \(ratio)배, 범위 안", "\(ratio)× usual, form in range"), tone: .good)
            : RunSummaryLine(axis: axis, state: L.s("평소 \(ratio)배", "\(ratio)× usual"), tone: .neutral)
    }

    private static func heartRateLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        let visible = i.zoneFractions.filter { $0.value > 0.01 }
        let total = visible.values.reduce(0, +)
        guard total > 0 else { return nil }
        let L = AppLanguage.shared
        func frac(_ z: Int) -> Double { (visible[z] ?? 0) / total }
        let axis = L.s("심박", "Heart rate")

        if frac(2) >= 0.60 {
            return RunSummaryLine(axis: axis, state: L.s("딱 좋은 강도", "Just right"), tone: .good)
        }
        let high3 = frac(3) + frac(4) + frac(5)
        if easyIntentTypes.contains(i.workoutType), high3 >= easyHighZoneFrac {
            let pct = Int((high3 * 100).rounded())
            let label = i.workoutType.koreanLabel
            return RunSummaryLine(axis: axis,
                                  state: L.s("\(label) 기준 높음 · Zone 3 이상 \(pct)%", "High for a \(label.lowercased()) · \(pct)% in Zone 3+"),
                                  tone: .neutral)
        }
        guard let dom = visible.max(by: { $0.value < $1.value })?.key else { return nil }
        switch dom {
        case 1:  return RunSummaryLine(axis: axis, state: L.s("가벼운 회복 강도", "Light recovery"), tone: .good)
        case 2:  return RunSummaryLine(axis: axis, state: L.s("딱 좋은 강도", "Just right"), tone: .good)
        case 3:  return RunSummaryLine(axis: axis, state: L.s("템포 구간에 머묾", "Stayed in tempo zone"), tone: .neutral)
        default:
            return FormNarrative.isPlannedHighIntensity(i.workoutType)
                ? RunSummaryLine(axis: axis, state: L.s("계획대로 고강도", "High intensity, as planned"), tone: .good)
                : RunSummaryLine(axis: axis, state: L.s("고강도 구간이 많음", "Mostly high intensity"), tone: .neutral)
        }
    }

    private static func loadLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        guard i.weekOverWeek != nil || i.acuteChronic != nil else { return nil }
        let L = AppLanguage.shared
        let axis = L.s("훈련부하", "Training load")
        let wow = i.weekOverWeek ?? 0
        let jumped = wow >= loadJumpMin || i.acuteChronic == .high || i.acuteChronic == .veryHigh
        let lighter = i.acuteChronic == .low || (i.acuteChronic == nil && wow <= -loadJumpMin)

        var state: String
        let tone: RunSummaryLine.Tone
        if jumped {
            if let w = i.weekOverWeek {
                let pct = Int((w * 100).rounded())
                let sign = pct >= 0 ? "+" : ""
                state = L.s("이번 주 \(sign)\(pct)%", "This week \(sign)\(pct)%")
            } else {
                state = L.s("4주 평균 대비 높음", "Above 4-wk avg")
            }
            tone = .neutral
        } else if lighter {
            state = L.s("평소보다 가볍게", "Lighter than usual")
            tone = .good
        } else {
            state = L.s("4주 평균 수준", "Around 4-wk avg")
            tone = .good
        }
        if i.streakDays >= 3 {
            state += L.s(" · \(i.streakDays)일 연속", " · \(i.streakDays) days in a row")
        }
        return RunSummaryLine(axis: axis, state: state, tone: tone)
    }

    private static func aerobicLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        guard let v = i.vo2 else { return nil }
        let L = AppLanguage.shared
        let level = vo2Level(v)
        let g = i.vo2GenderLabel.isEmpty ? "" : " \(i.vo2GenderLabel)"
        return RunSummaryLine(axis: L.s("유산소", "Aerobic"),
                              state: L.s("\(i.vo2AgeDecade)\(g) 기준 \(level.name)", "\(level.name) for \(i.vo2AgeDecade)\(g)"),
                              tone: level.index >= 2 ? .good : .neutral)
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: 테스트 명령(`RunSummaryTests`). Expected: 19 tests passed.

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Insight/RunSummary.swift MIMORunningTests/RunSummaryTests.swift
git commit -m "RunSummary — 러닝폼·거리 적응·심박·훈련부하·유산소 총평 규칙, 관찰 사실만·없는 축은 생략

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: 리듬 카드에 총평 표시

> **리뷰 반영(구현 완료 후 확정)**: `effortIndex`는 `InsightExportSheet`의 리듬 카드 호출부에도 전달(내보내기 이미지 = 화면). 폼 형태 판정 진입점은 후속 정리에서 `FormPhase.result(splits:altitudeProfile:baseline:formShifts:workoutType:)` 하나로 합쳐 두 카드가 같은 규칙을 쓴다. 커밋 50b6501 + 정리 커밋이 기준.

**Files:**
- Modify: `MIMORunning/Views/RunInsightTabCard.swift`
  - `computeRunningStreak` 근처 (line ~663): `effortLoadRuns` 헬퍼 추가
  - `cardContent` `.rhythm` 호출 (line ~940–950): `effortIndex` 전달
  - `RhythmInsightCard` 프로퍼티 (line ~1359–1374): `effortIndex` 추가
  - `RhythmInsightCard.body` (line ~1422–1445): 총평 표시
  - `RhythmInsightCard.vo2SubLabel` (line ~2543): `RunSummary.vo2Level` 사용
  - `PerformanceInsightCard.sevenDayLoad` (line ~2663): 헬퍼 사용

- [ ] **Step 1: 공유 헬퍼**

`private func computeRunningStreak(...)` 함수 바로 아래에 추가:

```swift
/// 부하 계산용 러닝 목록 — 이 러닝 날짜로 끝나는 36일 창(이 러닝 포함). 리듬·퍼포먼스 카드가 **이 함수 하나만** 쓴다.
private func effortLoadRuns(activity: Activity, history: [Activity], index: EffortIndex)
    -> (runs: [EffortLoad.Run], acts: [Activity], dayEnd: Date) {
    let cal = Calendar.current
    let dayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: activity.date)) ?? activity.date
    let since = cal.date(byAdding: .day, value: -36, to: activity.date) ?? .distantPast
    var acts = history.filter { $0.date >= since && $0.date < dayEnd }
    // history가 이 러닝을 포함하지 않는 호출부에서도 이 러닝이 창에 들어가야 한다.
    if !acts.contains(where: { $0.id == activity.id }) { acts.append(activity) }
    return (EffortLoad.runs(from: acts, index: index), acts, dayEnd)
}
```

`PerformanceInsightCard.sevenDayLoad`의 앞부분

```swift
        guard let idx = effortIndex else { return nil }
        let cal = Calendar.current
        let dayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: activity.date)) ?? activity.date
        let since = cal.date(byAdding: .day, value: -36, to: activity.date) ?? .distantPast
        var acts = history.filter { $0.date >= since && $0.date < dayEnd }
        // history가 이 러닝을 포함하지 않는 호출부에서도 이 러닝이 창에 들어가야 한다.
        if !acts.contains(where: { $0.id == activity.id }) { acts.append(activity) }
        let runs = EffortLoad.runs(from: acts, index: idx)
```
을
```swift
        guard let idx = effortIndex else { return nil }
        let cal = Calendar.current
        let (runs, acts, dayEnd) = effortLoadRuns(activity: activity, history: history, index: idx)
```
로 바꾼다. 이후 코드(`w`, `thisAU`, `ac`, `sentence`, `bars`, `prevSeven`)는 그대로 — `cal`, `acts`, `dayEnd`, `runs`를 그대로 쓴다.

- [ ] **Step 2: 리듬 카드에 `effortIndex` 전달**

`RhythmInsightCard` 프로퍼티 목록에서 `var formShifts: [MRFormShift] = []` 아래에 추가:
```swift
    /// 강도(sRPE) 조회 인덱스 — 총평 훈련부하 줄용. 없으면 그 줄 생략.
    var effortIndex: EffortIndex? = nil
```

`cardContent`의 `.rhythm` 호출에서 `formShifts: formShifts` 뒤에 추가:
```swift
                formShifts: formShifts,
                effortIndex: effortIndex
```

- [ ] **Step 3: 총평 줄 계산**

`RhythmInsightCard`의 `private var oneLiner: String?` 바로 위에 추가:

```swift
    /// 초·중·말 폼 형태 — 폼 카드와 같은 엔진·같은 입력(풀 스플릿 + 기준선 + GCT 시점 보정).
    private var formPhaseResult: FormPhase.Result? {
        guard rhythmWorkoutType != .interval, let det = detail, let bl = formBaseline else { return nil }
        let gctShift = formShifts.first(where: { $0.metric.key == "gct" })
        // 기준선 밴드는 GAP 기준 — 폼 카드 `formPhaseResult`와 같은 배율 규칙
        let scale: Double = {
            let full = det.splits.filter { $0.distanceM >= 900 }
            let distKm = full.map(\.distanceM).reduce(0, +) / 1000
            let dur = full.map(\.duration).reduce(0, +)
            guard let gap = GradeAdjustedPace.compute(splits: det.splits, altitudeProfile: det.altitudeProfile),
                  distKm > 0, dur > 0 else { return 1.0 }
            return gap / (dur / distKm)   // 분모도 스플릿 기준 — 폼 카드와 같은 규칙
        }()
        return FormPhase.classify(splits: det.splits, paceScale: scale, bandFor: { pace in
            FormPhase.bandStats(in: bl, paceSecPerKm: pace, gctShift: gctShift)
        })
    }

    /// 총평 5줄 — 각 축의 결론은 해당 카드 엔진에서 그대로 받는다. 2줄 미만이면 기존 한 줄 칩으로 폴백.
    private var summaryLines: [RunSummaryLine] {
        var input = RunSummaryInput()
        input.form = formPhaseResult
        input.distKm = activity.distance / 1000
        input.typicalKm = typicalRunDistanceKm
        input.workoutType = rhythmWorkoutType
        input.zoneFractions = Dictionary(hrZones.map { ($0.id, $0.fraction) }, uniquingKeysWith: { a, _ in a })
        if let idx = effortIndex {
            let runs = effortLoadRuns(activity: activity, history: history, index: idx).runs
            input.weekOverWeek = EffortLoad.rollingWeekOverWeek(runs: runs, asOf: activity.date)
            input.acuteChronic = EffortLoad.rollingAcuteChronic(runs: runs, asOf: activity.date)?.label
        }
        input.streakDays = computeRunningStreak(activity: activity, history: history)
        if let fi = vo2Info, let v = detail?.vo2Max {
            input.vo2 = v
            input.vo2AgeDecade = fi.ageDecade
            input.vo2GenderLabel = fi.genderLabel
        }
        return RunSummary.lines(input)
    }
```

(`typicalRunDistanceKm`은 `RhythmInsightCard`에 이미 있는 계산 프로퍼티(line ~1384)를 쓴다. 새로 만들지 않는다.)

- [ ] **Step 4: 하단 칩 자리에 총평**

`RhythmInsightCard.body`에서
```swift
            if let line = oneLiner {
                divider
                oneLiner(text: line, bg: IC.greenBg, fg: IC.greenText, accent: IC.green)
            }
```
을
```swift
            let summary = summaryLines
            if summary.count >= 2 {
                divider
                RunSummaryLinesView(lines: summary)
            } else if let line = oneLiner {
                divider
                oneLiner(text: line, bg: IC.greenBg, fg: IC.greenText, accent: IC.green)
            }
```
로 바꾼다.

- [ ] **Step 5: VO2 등급 단일화**

`vo2SubLabel(fi:vo2:)`에서
```swift
        let bounds: [Double]   = [15, 26, 33, 41, 57]
        let levelColors: [Color] = [Color(hex: "E8564A"), Color(hex: "F0913C"), Color(hex: "EDC84B"), Theme.positive]
        let levelNames = [L.s("낮음","Low"), L.s("평균이하","Below avg"), L.s("평균이상","Above avg"), L.s("높음","High")]
        var idx = bounds.count - 2
        for i in 0..<(bounds.count - 1) { if vo2 < bounds[i + 1] { idx = i; break } }
```
을
```swift
        let levelColors: [Color] = [Color(hex: "E8564A"), Color(hex: "F0913C"), Color(hex: "EDC84B"), Theme.positive]
        let level = RunSummary.vo2Level(vo2)   // 총평 유산소 줄과 같은 경계·이름
        let idx = level.index
```
로 바꾸고, 반환문의 `levelNames[idx]`를 `level.name`으로 바꾼다.

- [ ] **Step 6: 빌드 + 전체 관련 테스트**

Run: 빌드 명령. Expected: `** BUILD SUCCEEDED **`.

Run:
```bash
xcodebuild test -project MIMORunning.xcodeproj -scheme MIMORunning \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MIMORunningTests/FormPhaseTests \
  -only-testing:MIMORunningTests/RunSummaryTests \
  -only-testing:MIMORunningTests/EffortLoadTests \
  -only-testing:MIMORunningTests/FormNarrativeTests 2>&1 | grep -E 'Test (Suite|Case)|passed|failed|error:' | tail -30
```
Expected: 모두 passed.

- [ ] **Step 7: 커밋**

```bash
git add MIMORunning/Views/RunInsightTabCard.swift
git commit -m "리듬 카드 하단 — 한 줄 칩 대신 총평 5줄(러닝폼·거리 적응·심박·훈련부하·유산소), 부하 러닝 목록은 두 카드가 한 헬퍼로

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: 시뮬레이터 육안 확인

> **결과(2026-09-13)**: 시뮬레이터에는 HealthKit 데이터가 없어 카드가 뜨지 않으므로, 16km 합성 스플릿 + 합성 기준선으로 `ImageRenderer` 스냅샷(임시 테스트, 커밋 안 함)을 찍어 확인했다. 폼 카드: 네 차트 아래 문장 + 30/70 점선 확인. 리듬 카드: 하단 5줄 총평 확인. 발견: 축 라벨 폭이 달라 상태어 시작 위치가 어긋남 → 축 열 폭 고정으로 정리.

**Files:** 없음 (확인만)

- [ ] **Step 1: 빌드 후 시뮬레이터에서 러닝 상세 → 폼 탭·리듬 탭 확인**

확인 항목:
- 폼 탭: 네 차트 아래 3단계 문장이 붙고, 점선이 2개(30/70)로 바뀌었는지. 6km 미만 러닝에서는 문장 없음 + 점선 1개(50%) 유지.
- 리듬 탭: 하단에 색점 5줄(데이터 없는 축은 빠짐). 2줄 미만이면 기존 초록 칩.
- 그 외 레이아웃·색·축·숫자 형식이 바뀌지 않았는지.

문제가 있으면 해당 태스크로 돌아가 수정하고 다시 커밋한다.

---

## 후속(이 계획 범위 밖)

- 심박 줄에 **기온 보정 심박** 반영("기온 감안해도 Zone 3 상단") — 보정 심박 단일화 작업 이후.
- 총평을 공유 카드에 토글로 노출 — `RunSummaryLinesView(scale:)` 그대로 사용.
- 오르막·내리막이 큰 스플릿을 단계 판정에서 제외 — `GradeAdjustedPace.gradeSegments`로 km별 경사 시리즈를 만든 뒤.
