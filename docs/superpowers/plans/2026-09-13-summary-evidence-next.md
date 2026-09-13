# 총평 근거·다음 행동 + 폼 카드 3단계 표 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 총평 5줄 각각에 "근거"(왜 이 말이 나왔나)와 "다음"(그래서 뭘 하나)을 붙여 줄을 탭하면 펼쳐 보이게 하고(노란 줄은 기본 펼침), 폼 카드의 네 km 차트 아래에 초·중·말 3단계 표(페이스·심박·케이던스·보폭·접지)와 구간별 관계 문장을 넣어 "줄었어요"가 어느 구간에서 어떻게였는지 되짚지 않아도 되게 한다.

**Architecture:** 규칙 엔진에서 문장을 만든다. `FormPhase.Result`가 세 단계의 `PhaseStats`(심박 포함)와 판정 신호를 함께 들고, `FormPhase.relationSentences`가 구간별 관계 문장을 만든다. `RunSummaryLine`에 `evidence`/`next`가 붙고 `RunSummary`가 확장된 `RunSummaryInput`에서 규칙으로 채운다. 뷰는 입력을 모아 넘기고(`RhythmInsightCard`), `RunSummaryLinesView`가 펼침 상태를 갖되 내보내기 경로는 `allowsExpansion: false`로 5줄만 그린다. 폼 카드는 `FormPhaseTableView` 하나를 추가한다.

**Tech Stack:** SwiftUI · Swift Testing(`.serialized`) · 기존 `FormPhase`, `RunSummary`, `EffortLoad`, `MRHRPaceLookup`, `MRPlanWeek`.

**확정된 결정 (2026-09-13)**
1. 줄을 탭하면 근거·다음이 펼쳐진다. 노란(neutral) 줄은 처음부터 펼침, 초록 줄은 접힘. 공유·내보내기 카드는 5줄만.
2. "충분히 쉬었다" = 마지막 고강도 러닝(계획된 고강도 유형 또는 체감 강도 7 이상)이 2일 이상 전 + 7일 부하가 4주 평균 이하(`acuteChronic ∈ {low, steady}`, 지난주 대비 +30% 미만) + 단조도 없음. 셋 다 만족할 때만 빌드업·템포 제안. 대회 플랜의 이번 주 단계가 회복/테이퍼면 그것이 우선.
3. 거리 증가 기준은 "평소의 1.3배 안에서"(총평 거리 적응 문턱과 같은 수). 외부의 주 10% 규칙은 쓰지 않는다.
4. 기온 보정 심박 작업(`2026-09-13-heat-adjusted-hr.md`) 완료 후 진행. 심박 근거에 "더위 +N bpm"을 쓴다.

**원칙**: 관찰 사실만, 등급어 없음, 없는 데이터는 줄 생략, 색·레이아웃은 이 문서에 적힌 것만 변경. 페이스 숫자는 앱의 이지 페이스 조회값(`MRHRPaceLookup`)이 있을 때만 쓴다.

---

## 파일 맵

| 파일 | 역할 | 작업 |
|---|---|---|
| `MIMORunning/Insight/FormPhase.swift` | `PhaseStats.avgHR`, `Result.phases/signals`, `relationSentences` | 수정 |
| `MIMORunning/Views/FormPhaseTableView.swift` | 3단계 표(공유 컴포넌트, scale) | 생성 |
| `MIMORunning/Views/RunFormCardView.swift` | 표 + 관계 문장 배치 | 수정 |
| `MIMORunning/Insight/RunSummary.swift` | `RunSummaryLine.evidence/next`, `RunSummaryInput` 확장, 규칙 | 수정 |
| `MIMORunning/Views/RunSummaryLinesView.swift` | 탭 펼침, `allowsExpansion` | 수정 |
| `MIMORunning/Views/RunInsightTabCard.swift` | 리듬 카드 입력 조립, `hrZonesFn`·`raceDetailFn`·`easyPaceLookup`·`planPhase` 전달, 내보내기 5줄 | 수정 |
| `MIMORunning/Views/RunInsightCardView.swift`, `ActivityDetailView.swift` | `easyPaceLookup`·`planPhase` 전달 | 수정 |
| `MIMORunningTests/FormPhaseTests.swift`, `RunSummaryTests.swift` | | 수정 |

테스트·빌드 명령은 `2026-09-13-heat-adjusted-hr.md`와 같다. 커밋 트레일러 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

**참고(기존)**
- `FormPhase.PhaseStats { splitCount, startKm, endKm, paceSecPerKm, cadence?, stride?, groundContact?, verticalOsc?, verticalRatio }`, `Result { early, mid, late, earlyEndKm, lateStartKm, totalKm, isHeld }`, `Signals { cadence, stride, groundContact: Status; knownCount; fatigue }`, `classify(splits:paceScale:bandFor:)`, `result(splits:altitudeProfile:baseline:formShifts:workoutType:)`.
- `SplitData.avgHeartRate: Int?`.
- `RunSummaryLine(axis:state:tone:)`, `RunSummaryInput` 필드: form, distKm, typicalKm, workoutType, zoneFractions, weekOverWeek, acuteChronic, streakDays, vo2, vo2AgeDecade, vo2GenderLabel, heatDeltaBpm.
- `MRHRPaceLookup { paceSec, n, hrLo, hrHi, basis }`, `MREngineStore.easyPaceLookup`.
- `MRPlanWeek { monday, phase("회복"/"테이퍼"/…), breakdown }`, `ActivityDetailView.swift:840-856`이 이번 주 `MRPlanWeek`를 찾는 코드.
- `EffortLoad.rollingSentenceKind(runs:asOf:) -> SentenceKind? { monotony, low, high, veryHigh }`, `effortLoadRuns(activity:history:index:)`(RunInsightTabCard 파일 내부).
- `FormNarrative.isPlannedHighIntensity(_:)`, `EffortIndex.resolve(id)?.value`.
- 펼침 패턴 선례: `MRAdviceCardView.swift:10-83` (`@State expanded: Set<String>`, `.contentShape(Rectangle()).onTapGesture { withAnimation(.snappy) … }`, chevron 11pt).
- 내보내기: `InsightExportSheet`가 `RhythmInsightCard`를 ImageRenderer로 그림(RunInsightTabCard ~5405).

---

### Task 1: FormPhase — 단계별 심박·신호 노출 + 구간 관계 문장

> **리뷰 반영(구현 완료 후 확정)**: 구간 어휘는 앱 목소리대로 **초반/중반/후반**(중기·말기 아님) — 표 행 라벨도 같게. 후반 문장의 페이스·케이던스 변화는 부호를 본다(빨라지며/느려지며/같은데, 올라갔어요/내려갔어요/그대로예요), 케이던스를 모르면 절 생략, 폼 문장이 이미 케이던스 하락을 말하면 중복 생략. 단위 "N초/km"·"Nbpm". 더위 위안("흔한 폭")은 드리프트가 `max(10, 더위×2)` 이하일 때만, 심박 절 뒤 괄호로(보정 5bpm 이상일 때만). 커밋 65e9bac + 리뷰 반영 커밋이 기준.

**Files:** `MIMORunning/Insight/FormPhase.swift`, `MIMORunningTests/FormPhaseTests.swift`

- [ ] **Step 1: 테스트 추가**
```swift
    // MARK: 단계 데이터·관계 문장

    @Test func resultCarriesPhasesWithHeartRate() {
        let s = (1...10).map { split($0) }   // split() 픽스처는 avgHeartRate 150 고정
        let r = classify(s)
        #expect(r?.phases.early.avgHR == 150)
        #expect(r?.phases.late.splitCount == 3)
        #expect(r?.signals.late.stride == .inRange)
    }

    @Test func midAccelerationSentenceNamesLevers() {
        AppLanguage.shared.isEnglish = false
        // 초기 400 → 중기 375, 보폭 0.88→0.94, 접지 262→250
        let s = (1...3).map { split($0, pace: 400, sl: 0.88, gct: 262) } + (4...10).map { split($0, pace: 375, sl: 0.94, gct: 250) }
        let lines = FormPhase.relationSentences(classify(s)!, heatDeltaBpm: nil)
        #expect(lines.contains("중반 3~7km: 페이스가 25초/km 빨라지며 보폭이 늘고 접지가 짧아졌어요."))
    }

    @Test func lateDriftSentenceWithCadenceHeld() {
        AppLanguage.shared.isEnglish = false
        // 중기 심박 150 → 말기 158, 페이스 같음, 케이던스 유지
        let s = (1...7).map { split($0, hr: 150) } + (8...10).map { split($0, hr: 158) }
        let lines = FormPhase.relationSentences(classify(s)!, heatDeltaBpm: nil)
        #expect(lines.contains("후반 7~10km: 페이스는 같은데 심박이 8bpm 올랐고, 케이던스는 그대로예요."))
    }

    @Test func lateDriftSentenceMentionsHeat() {
        AppLanguage.shared.isEnglish = false
        let s = (1...7).map { split($0, hr: 150) } + (8...10).map { split($0, hr: 158) }
        let lines = FormPhase.relationSentences(classify(s)!, heatDeltaBpm: 8)
        #expect(lines.contains("후반 7~10km: 페이스는 같은데 심박이 8bpm 올랐고 (더위 +8bpm을 감안하면 흔한 폭), 케이던스는 그대로예요."))
    }

    @Test func noRelationWhenNothingChanged() {
        let s = (1...10).map { split($0) }
        #expect(FormPhase.relationSentences(classify(s)!, heatDeltaBpm: nil).isEmpty)
    }
```
`split()` 픽스처에 `hr: Int? = 150` 인자를 추가해 `avgHeartRate: hr`로 넘긴다.

- [ ] **Step 2: 구현**
  - `PhaseStats`에 `let avgHR: Double?` 추가, `stats(_:)`에서 `avg(g.map { $0.avgHeartRate.map(Double.init) })`.
  - `Result`에 `let phases: (early: PhaseStats, mid: PhaseStats, late: PhaseStats)`와 `let signals: (early: Signals, mid: Signals, late: Signals)` 추가. 튜플은 `Equatable` 합성이 안 되므로 `struct Phases: Equatable { let early, mid, late: PhaseStats }` / `struct PhaseSignals: Equatable { let early, mid, late: Signals }`로 두고 `Signals: Equatable` 채택. `classify`에서 채운다. 기존 테스트의 `FormPhase.Result(early:mid:late:earlyEndKm:lateStartKm:totalKm:)` 생성자 호출이 깨지므로, 그 호출부(테스트 헬퍼 `result(...)`, `RunSummaryTests.phase(...)`)는 헬퍼 `FormPhase.Result.stub(early:mid:late:earlyEnd:lateStart:total:)`(테스트 타깃 `extension`으로 두면 됨: 세 `PhaseStats`를 0으로 채움)를 쓰도록 바꾼다.
  - 관계 문장:
```swift
    /// 구간별 관계 문장 — "무엇이 언제 어떻게" 를 한 줄씩. 아무 변화도 없으면 빈 배열.
    /// 문턱: 페이스 ≥ accelDeltaSec(20초, 중기) / paceDeltaSec(10초, 말기) · 보폭 ≥ 0.02 · 접지 ≥ 8ms · 심박 ≥ 5 · 케이던스 "그대로" = |Δ| < 2
    static func relationSentences(_ r: Result, heatDeltaBpm: Double?) -> [String] {
        let L = AppLanguage.shared
        let e = r.phases.early, m = r.phases.mid, l = r.phases.late
        func km(_ p: PhaseStats) -> String { "\(Int(p.startKm.rounded()))~\(Int(p.endKm.rounded()))km" }
        var out: [String] = []

        // 중기: 페이스 ↔ 보폭·접지 (GPT 7·8)
        let accel = e.paceSecPerKm - m.paceSecPerKm
        if accel >= accelDeltaSec {
            var levers: [String] = [], leversEn: [String] = []
            if let a = e.stride, let b = m.stride, b - a >= strideDeltaM { levers.append("보폭이 늘고"); leversEn.append("a longer stride") }
            if let a = e.groundContact, let b = m.groundContact, a - b >= 8 { levers.append("접지가 짧아졌어요"); leversEn.append("shorter ground contact") }
            if let a = e.cadence, let b = m.cadence, b - a >= cadenceGainSPM { levers.append("발 회전이 빨라졌어요"); leversEn.append("quicker steps") }
            if !levers.isEmpty {
                let ko = joinKoClauses(levers)   // "보폭이 늘고 접지가 짧아졌어요"
                out.append(L.s("중기 \(km(m)): 페이스가 \(Int(accel.rounded()))초 빨라지며 \(ko).",
                               "Mid \(km(m)): pace picked up \(Int(accel.rounded())) s/km with \(leversEn.joined(separator: " and "))."))
            }
        }
        // 말기: 심박 드리프트 ↔ 케이던스 (GPT 5·6)
        if let h1 = m.avgHR, let h2 = l.avgHR, h2 - h1 >= 5 {
            let paceSame = abs(l.paceSecPerKm - m.paceSecPerKm) < paceDeltaSec
            let cadHeld = { () -> Bool in guard let a = m.cadence, let b = l.cadence else { return false }; return abs(b - a) < cadenceSameSPM }()
            var ko = paceSame ? "페이스는 같은데 심박이 \(Int((h2 - h1).rounded())) 올랐고" : "페이스가 \(Int((l.paceSecPerKm - m.paceSecPerKm).rounded()))초 느려지며 심박이 \(Int((h2 - h1).rounded())) 올랐고"
            ko += cadHeld ? ", 케이던스는 그대로예요." : ", 케이던스도 내려갔어요."
            if let d = heatDeltaBpm, d >= 5 { ko += " 더위 +\(Int(d.rounded()))bpm을 감안하면 흔한 폭이에요." }
            … 영어 동형 …
            out.append(L.s("말기 \(km(l)): " + ko, "Late \(km(l)): " + en))
        }
        return out
    }
```
   `joinKoClauses`는 마지막 절만 종결형이 되도록 기존 `joinKo`와 같은 방식(절 자체가 이미 "…고"/"…어요" 형태이므로 마지막 요소만 종결형으로 골라 넣는 방식이 필요하면 절을 (연결형, 종결형) 쌍으로 둔다).

- [ ] **Step 3: 테스트** — 기존 FormPhaseTests 전부 + 새 5개. `RunSummaryTests`도 스텁 헬퍼로 통과.
- [ ] **Step 4: 커밋** — "FormPhase — 단계별 심박·판정 신호를 결과에 싣고 구간별 관계 문장(중기 가속 레버·말기 드리프트와 케이던스)"

---

### Task 2: 폼 카드 3단계 표 + 관계 문장

> **리뷰 반영(구현 완료 후 확정)**: 표는 왼쪽 정렬(`.frame(maxWidth:.infinity, alignment:.leading)`), 주의 셀은 앰버 텍스트 + 앰버 0.18 알약 배경(보폭 주황과 구분), 헤더 8pt·'지면접촉', 더위 설명이 관계 문장에 있으면 폼 문장의 '흔한 변화예요' 꼬리 생략(`sentence(_:isLongDistance:suppressCommonTail:)`, `hasHeatReassurance`). 커밋 914e112 + 리뷰 반영 커밋.

**Files:** `MIMORunning/Views/FormPhaseTableView.swift`(생성), `MIMORunning/Views/RunFormCardView.swift`

- [ ] **Step 1: 컴포넌트**
```swift
/// 초·중·말 표 — 페이스·심박·케이던스·보폭·접지. 폼 카드가 **이 컴포넌트 하나만** 쓴다. scale=1 기준: 글자 9pt · 행 간격 5pt.
struct FormPhaseTableView: View {
    let result: FormPhase.Result
    var scale: CGFloat = 1.0
    // 열: 구간(라벨+km) | 페이스 | 심박 | 케이던스 | 보폭 | 접지
    // 값 색: 페이스 white 0.9 · 심박 Theme.heartRate · 케이던스 Theme.cadence · 보폭 Theme.strideLength · 접지 Theme.groundContact
    // 판정: signals가 .below/.above(피로 방향)이면 그 셀을 Theme.caution, 아니면 위 색. 수직진폭·심박은 판정 없음.
    // 헤더 행: 9pt white 0.5 ("구간 · 페이스 · 심박 · 케이던스 · 보폭 · 접지"). 데이터 3행. 결측은 "–".
}
```
  `Grid`(iOS 16+) 사용, `.frame(maxWidth: .infinity)`. 숫자 형식: 페이스 `m'ss"`, 심박 정수, 케이던스 정수, 보폭 `%.2f`, 접지 정수.

- [ ] **Step 2: 배치** — `RunFormCardView.body`의 `if let phase = formPhaseResult { Text(sentence) }` 블록을
```swift
                    if let phase = formPhaseResult {
                        FormPhaseTableView(result: phase)
                        Text(FormPhase.sentence(phase, isLongDistance: isLongDistanceContext))  … 기존 스타일 …
                        ForEach(FormPhase.relationSentences(phase, heatDeltaBpm: heatHRModel?.delta(activity.temperatureC)), id: \.self) { line in
                            Text(line).font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.66)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
```
  로 바꾼다. `RunFormCardView`에 `var heatHRModel: MRHeatHRModel? = nil`을 추가하고 `RunInsightTabCard`·`InsightExportSheet`의 두 생성 호출부에서 `heatHRModel: heatHRModel`을 넘긴다.
- [ ] **Step 3: 빌드 + 스냅샷**(임시 테스트, 커밋 안 함) — 이전 스냅샷 방식과 같이 16km 합성 데이터로 폼 카드 렌더, 표·문장 확인.
- [ ] **Step 4: 커밋** — "폼 카드 — 네 차트 아래 초·중·말 표(페이스·심박·케이던스·보폭·접지)와 구간별 관계 문장"

---

### Task 3: RunSummary — 근거·다음 규칙

> **리뷰 반영(구현 완료 후 확정)**: 모르는(.unknown) 지표는 근거에서 생략. 심박 근거는 '최고 N'(전체 최고). 거리 적응 줄이 뜨면 심박의 '거리 늘리지 마세요' 생략(중복). 폼 다음 문구는 이탈 지표별(케이던스/접지/보폭/위아래). 숫자 포맷 로케일 고정(en_US_POSIX). 테이퍼는 '테이퍼 주'. '충분히 회복'은 부하 자료(ACWR 또는 AU)가 있을 때만. VO2 차이는 0.05 이상일 때만. 커밋 73ec894 + 리뷰 반영 커밋.

**Files:** `MIMORunning/Insight/RunSummary.swift`, `MIMORunningTests/RunSummaryTests.swift`

- [ ] **Step 1: 타입**
  - `RunSummaryLine`에 `var evidence: String? = nil`, `var next: String? = nil` (memberwise 기본값 → 기존 `RunSummaryLine(axis:state:tone:)` 유지).
  - `RunSummaryInput` 추가 필드(모두 옵셔널·기본값):
    `distanceRank: Int?`, `distanceSampleCount: Int?`(최근 N회 중 순위), `avgHeartRate: Int?`, `peakHeartRate: Int?`, `temperatureC: Double?`, `sevenDayAU: Double?`, `previousSevenAU: Double?`, `loadSentence: EffortLoad.SentenceKind?`, `daysSinceHardRun: Int?`, `planPhase: String?`, `easyPace: MRHRPaceLookup?`, `vo2EightWeeksAgo: Double?`.
- [ ] **Step 2: 테스트** (오늘 러닝 픽스처: 거리주 16km, 평소 7.6, Zone 4 62%, 심박 149/157, 25°C 더위 +8, 7일 1783/1149, +55%, 4일 연속, 폼 held with phases stub, VO2 45.4 vs 44.6)
```swift
    @Test func evidenceAndNextForTodayRun() {
        let out = lines(todayInput())
        #expect(out[0].evidence == "케이던스 175 유지 · 마지막 5km 보폭 0.90 범위 안 · 접지 266 범위 안")
        #expect(out[0].next == nil)
        #expect(out[1].evidence == "평소 7.6km · 최근 10회 중 가장 긴 거리")
        #expect(out[1].next == "이 거리는 2~3주 유지한 뒤 늘리세요. 롱런은 한 번에 평소의 1.3배 안에서.")
        #expect(out[2].evidence == "Zone 4 62% · 평균 149 · 후반 157까지 · 25°C(더위 +8)")
        #expect(out[2].next == "장거리는 후반 심박이 자연히 올라요. 거리를 한 번에 크게 늘리지 마세요.")
        #expect(out[3].evidence == "7일 1,783 AU · 이전 7일 1,149 · 4일 연속")
        #expect(out[3].next == "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요.")
        #expect(out[4].evidence == "VO2max 45.4 · 8주 전 대비 +0.8")
        #expect(out[4].next == nil)
    }
    @Test func easyIntentHighHRSuggestsEasyPace() {
        var i = todayInput(); i.workoutType = .easy; i.easyPace = MRHRPaceLookup(paceSec: 400, n: 12, hrLo: 125, hrHi: 135)
        #expect(lines(i)[2].next == "다음 이지런은 Zone 2 상단, 6'40\" 정도로 가 보세요.")
    }
    @Test func restedSuggestsQualitySession() {
        var i = todayInput(); i.weekOverWeek = 0.05; i.acuteChronic = .steady; i.loadSentence = nil; i.daysSinceHardRun = 3; i.streakDays = 0
        #expect(lines(i)[3].next == "충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.")
    }
    @Test func planRecoveryPhaseOverrides() {
        var i = todayInput(); i.planPhase = "회복"
        #expect(lines(i)[3].next == "플랜상 회복 주예요. 이지런 위주로 가세요.")
    }
    @Test func heavierFormSuggestsWatchingLateStride() {
        var i = todayInput(); i.form = FormPhase.Result.stub(late: .heavier([.stride]), …)
        #expect(lines(i)[0].next == "다음 롱런은 같은 거리에서 후반 보폭만 지켜보세요.")
    }
```
- [ ] **Step 3: 규칙** (각 `*Line` 함수 끝에서 evidence/next를 채움)
  - 러닝폼 evidence: late phase 값으로 "케이던스 N 유지/내려감 · 마지막 Nkm 보폭 X 범위 안/아래 · 접지 N 범위 안/위". next: held → nil; heavier/cadenceDefended/bouncier → "다음 롱런은 같은 거리에서 후반 보폭만 지켜보세요." (bouncier면 "…후반 위아래 움직임만 지켜보세요.").
  - 거리 적응 evidence: "평소 {typical}km" + (rank == 1 ? " · 최근 N회 중 가장 긴 거리" : rank ≤ 3 ? " · 최근 N회 중 {rank}번째로 긴 거리" : ""). next: ratio ≥ 1.3 → "이 거리는 2~3주 유지한 뒤 늘리세요. 롱런은 한 번에 평소의 1.3배 안에서."
  - 심박 evidence: "Zone {dom} {pct}% · 평균 {avg}" + (peak ? " · 후반 {peak}까지" : "") + (temp ? " · {T}°C" + (heatDelta ≥ 3 ? "(더위 +{n})" : "") : ""). next: 계획된 고강도(거리주 포함)·Zone 4 우세 → "장거리는 후반 심박이 자연히 올라요. 거리를 한 번에 크게 늘리지 마세요."(롱런류일 때) / 템포·빌드업·인터벌·대회 → nil; 이지 의도인데 높음 → easyPace 있으면 "다음 이지런은 Zone 2 상단, {pace} 정도로 가 보세요." 없으면 "다음 이지런은 Zone 2 상단으로 가 보세요."; 그 외 nil.
  - 훈련부하 evidence: "7일 {a} AU · 이전 7일 {b}" (+ " · {n}일 연속"); AU 없으면 연속일만. next: planPhase 회복/테이퍼 → "플랜상 회복 주예요. 이지런 위주로 가세요."; 급증(jumped) 또는 monotony 또는 streak ≥ 4 → "다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요."; rested(daysSinceHardRun ≥ 2, !jumped, acuteChronic ∈ {low, steady, nil}, loadSentence != .monotony) → "충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요."; 그 외 nil.
  - 유산소 evidence: "VO2max {v} · 8주 전 대비 {±d}" (8주 값 없으면 "VO2max {v}"). next: nil.
  - 영어 문장도 모두 `L.s`로.
- [ ] **Step 4: 테스트·커밋** — "총평 근거·다음 — 각 축의 근거 한 줄과 다음 행동 규칙(회복 이지런·빌드업/템포·거리 1.3배·이지런 페이스)"

---

### Task 4: 리듬 카드 입력 조립·플럼빙

> **리뷰 반영(구현 완료 후 확정)**: `matchedPlanWeek()`를 `ActivityDetailView`에서 추출해 이 러닝이 속한 주의 `phase`를 넘긴다. `sevenDayAU(runs:asOf:)` 헬퍼를 두 카드가 공유. 마지막 고강도 탐색은 28일 이내·싼 검사(강도 → 유형 → 존)부터, 회복 판정에 쓰일 때만 계산. 8주 전 VO2는 VO2가 있을 때만 조회. 커밋 23ec64e + 성능 정리 커밋.

**Files:** `RunInsightTabCard.swift`, `RunInsightCardView.swift`, `ActivityDetailView.swift`

- [ ] `RunInsightTabCard`·`InsightExportSheet`·`RhythmInsightCard`에 `hrZonesFn`, `raceDetailFn`(둘 다 이미 상위에 있음 → 전달만), `easyPaceLookup: MRHRPaceLookup?`, `planPhase: String?` 추가·전달. `ActivityDetailView`: `easyPaceLookup: engine.easyPaceLookup`, `planPhase`는 `planWeeklyTargetKm` 계산 루프(840-856)에서 같은 `MRPlanWeek`의 `phase`를 꺼내 넘긴다. `RunInsightSection`도 전달.
- [ ] `RhythmInsightCard.summaryLines`에서 새 입력 채우기: `distanceRank/SampleCount`(기존 `distanceContext` 계산을 값 반환 헬퍼로 분리), `avgHeartRate = activity.avgHeartRate`, `peakHeartRate = hrSamples.map(\.bpm).max()`, `temperatureC`, 부하 AU 두 값(`effortLoadRuns` + `EffortLoad.window`·이전 7일, PerformanceInsightCard.sevenDayLoad의 계산을 파일 내 헬퍼로 뽑아 공유), `loadSentence = EffortLoad.rollingSentenceKind`, `daysSinceHardRun`(history를 날짜 역순으로 훑어 `workoutTypeFn` 계획된 고강도 또는 `effortIndex.resolve(id)?.value >= 7`인 첫 러닝까지의 일수), `planPhase`, `easyPace`, `vo2EightWeeksAgo`(`raceDetailFn`으로 8주 전 ±7일 러닝의 `vo2Max` 중앙값).
- [ ] 빌드 + 커밋 — "리듬 카드 — 총평 근거·다음에 필요한 입력 조립(부하 AU·마지막 고강도·플랜 단계·이지 페이스·8주 전 VO2)"

---

### Task 5: RunSummaryLinesView 탭 펼침

> **리뷰 반영(구현 완료 후 확정)**: 컴포넌트는 ba424aa(chevron 9pt). `summaryAllowsExpansion` 플래그는 Task 4에서 리듬 카드·내보내기 호출부에 배선.

**Files:** `MIMORunning/Views/RunSummaryLinesView.swift`, `RunInsightTabCard.swift`(내보내기 호출부)

- [ ] `var allowsExpansion: Bool = true`. `@State private var expanded: Set<String>`(키 = `axis`). `init(lines:scale:allowsExpansion:)`에서 `_expanded = State(initialValue: allowsExpansion ? Set(lines.filter { $0.tone == .neutral && ($0.evidence != nil || $0.next != nil) }.map(\.axis)) : [])`.
- [ ] 행: 기존 HStack 그대로 + 오른쪽 끝 chevron(11pt, white 0.5, `evidence`/`next`가 있을 때만). 펼침 시 아래에 두 줄: `근거` 라벨(8.5pt, white 0.45) + 텍스트(9.5pt, white 0.62); `다음` 라벨(8.5pt, `Theme.caution`(neutral)/`Theme.positive`(good) 0.9) + 텍스트(9.5pt, white 0.85). 들여쓰기 = 점 지름 + 간격 + 축 열 폭. `.contentShape(Rectangle()).onTapGesture { withAnimation(.snappy) { toggle } }` — `allowsExpansion == false`면 제스처·chevron 없음.
- [ ] `InsightExportSheet`의 `RhythmInsightCard`가 만드는 `RunSummaryLinesView`에 `allowsExpansion: false`가 가도록 `RhythmInsightCard`에 `var summaryAllowsExpansion: Bool = true`를 두고 내보내기 호출부(~5405)에서 `false`.
- [ ] 빌드 + 스냅샷(펼침 상태) + 커밋 — "총평 줄 — 탭하면 근거·다음이 펼쳐지고 노란 줄은 기본 펼침, 내보내기는 5줄만"

---

### Task 6: 확인

> **기기 검증(2026-09-13 저녁, 실제 러닝 6건)에서 추가된 규칙**
> - 이지런 프레임: 케이던스만 살짝 내려간 건 "무거워짐"이 아니라 "편한 페이스 · 케이던스만 살짝 내려감"(초록, 다음 없음). 폼 문장 "편한 날엔 자연스러운 변화예요".
> - 장거리 문맥이 아니면 "다음 롱런은" 대신 "다음 러닝은".
> - 3단계 판정은 풀 스플릿 5개(5km)부터.
> - 후반 피로 신호는 평소 범위 밖 + 중반보다 나빠졌을 때만(빨라지면서 범위 아래인 보폭은 피로가 아님).
> - 심박 줄의 "거리를 한 번에 크게 늘리지 마세요"는 제거(거리 적응 줄이 맡음). 거리주·템포·빌드업·대회가 Zone 3 우세면 "계획대로 템포 구간", 인터벌은 평균 존과 무관하게 "계획대로 고강도".
> - 훈련부하 다음 순서: 플랜 회복/테이퍼 → 부하 급증/단조/연속 4일 → 오늘 고강도("오늘 강도를 냈으니 내일은 이지런이나 휴식") → 충분히 회복 → 없음.
> - **페이스 무너짐**(`.faded`): 후반이 중반보다 20초/km 이상 느려졌는데 심박이 −2bpm 이내로 유지되면 유지가 아니라 붕괴. 문장 "마지막 Nkm엔 페이스가 d초/km 떨어졌는데 심박은 그대로였어요. 보폭 a→b · 케이던스 a→b · 접지 +Nms." 다음 "다음엔 중반을 10초/km 늦게 시작해 보세요." 심박이 내려갔으면 쿨다운으로 봄. 근거: 페이스 정규화가 페이스 붕괴 자체를 가리는 구멍.
- 관련 스위트 전부(FormPhaseTests·RunSummaryTests·HeatAdjustedHRInsightTests·FormNarrativeTests) 통과.
- 스냅샷: 폼 카드(표+관계 문장), 리듬 카드(펼침/접힘, 내보내기 5줄).
