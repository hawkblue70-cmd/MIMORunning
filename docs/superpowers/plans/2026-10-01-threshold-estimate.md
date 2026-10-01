# 역치 추정 구현 계획

설계: `docs/superpowers/specs/2026-10-01-threshold-estimate-design.md`

공통 규칙
- 검증은 컴파일까지: `xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/mimo-dd-threshold` → `** TEST BUILD SUCCEEDED **`. 시뮬레이터·`xcodebuild test` 금지.
- 다른 세션이 같은 브랜치에 커밋한다: `git add <경로>`만, `-A`·`.`·`stash` 금지. 커밋 후 `git show --stat HEAD` 확인.
- 새 파일은 `MIMORunning.xcodeproj/project.pbxproj`에 등록이 필요한지 확인(폴더 동기화 그룹이면 불필요). pbxproj는 이미 다른 세션 변경(M)이 있다 — 손대야 하면 내 줄만 추가하고 hunk 단위로 커밋.
- 문자열은 `AppLanguage.shared` `L.s("한", "En")`. 주석 밀도·말투는 주변 코드와 같게(근거·⚠ 임의로 정함 표기).
- 커밋 메시지 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Task 1 — 엔진 (순수 함수) + 템포 페이스 교체

파일: `MIMORunning/Engine/MRThreshold.swift`(새), `MIMORunning/Engine/MRPlanPoint.swift`, `MIMORunningTests/MRThresholdTests.swift`(새), `MIMORunningTests/MRPlanPointTests.swift`

1. 테스트 먼저 `MRThresholdTests` (Swift Testing, `@Suite("역치 추정", .korean)`):
   - `mrThresholdPace(halfEquivMin: 110)` ≈ 302.3 (±0.5), `halfEquivMin: 60` → 하프 페이스(60×60/21.0975 ≈ 170.6), `5` → nil.
   - `mrCombineThresholdHR`: (170, (172,n:3)) → 171 · .medium / (170, (180,3)) → nil / (170, nil) → 170 · .low / (nil, (165,2)) → 165 · .low / (nil,nil) → nil.
   - `MRHRPaceModel.hrAtPace`: ok 모델(b0, bSpeed, dataHRMin/Max 직접 세팅) → `paceAtHR(hrAtPace(p)!)` ≈ p; 범위 밖 nil.
   - `mrSustainedEffortHR`: 20~70분·180일 안·같은 날 ±5% 매칭만 중앙값, 인터벌 러닝 제외, 없으면 nil.
   - `mrThresholdTrendSentence`: 6개월 312→300 → "6개월간 12초 빨라졌어요"; 2초 개선·느려짐 → nil; 점 1개 → nil.
2. 구현 `MRThreshold.swift`:
```swift
let MR_THRESHOLD_RACE_MIN = 60.0
let MR_THRESHOLD_HR_AGREE_BPM = 5.0      // ⚠ 임의로 정함 — 광학 심박 러닝 중 ±5bpm(Apple)
let MR_THRESHOLD_IMPROVE_SEC = 3.0       // ⚠ 임의로 정함 — 추세 문장·헤드라인 후보 문턱

struct MRThresholdEstimate: Equatable, Sendable {
    let asOf: Date
    let paceSecPerKm: Double
    let paceConfidence: MRConfidence     // 하프 예측의 confidence
    let hr: Double?
    let hrConfidence: MRConfidence       // hr nil이면 .none
    let basis: [String]                  // 화면 근거줄 (예측 근거 · 회귀 n · 노력 n)
}

func mrThresholdPace(halfEquivMin: Double) -> Double?   // guard > 10
extension MRHRPaceModel { func hrAtPace(_ paceSec: Double) -> Double? }  // hr = b0 + bSpeed×(60000/pace), dataHRMin...dataHRMax 안만
func mrSustainedEffortHR(runs: [MRWorkout], efforts: [MRRaceEffort], asOf: Date) -> (hr: Double, n: Int)?
func mrCombineThresholdHR(regression: Double?, sustained: (hr: Double, n: Int)?) -> (hr: Double, confidence: MRConfidence)?
func mrThresholdAsOf(runs: [MRWorkout], restingHRSamples: [(date: Date, value: Double)],
                     dateOfBirth: Date?, sex: MRSex, heat: MRHeatModel, asOf: Date) -> MRThresholdEstimate?
func mrThresholdTrend(runs:..., restingHRSamples:..., dateOfBirth:, sex:, heat:, now: Date) -> [MRThresholdEstimate]
func mrThresholdTrendSentence(_ points: [MRThresholdEstimate]) -> String?
```
   - `mrThresholdAsOf`: `past = runs.filter { $0.start <= asOf }`, `MRRaceArchiveManager.swift` 340~350행의 as-of 파이프라인 그대로(physiology → `mrApplyHeat(mrDetectEfforts)` → `mrFitExponent` → `mrProfile` → `mrPredict` → `mrFitHRPaceModel`). 하프 예측 없으면 nil.
   - `mrThresholdTrend`: 5~1개월 전 각 달 말일 23:59:59 + now, 총 6시점. nil은 건너뜀. 날짜 오름차순.
   - 추세 문장: 첫 점 대비 마지막이 `MR_THRESHOLD_IMPROVE_SEC` 이상 빨라질 때만. 개월 수 = 두 asOf의 month 차(최소 1). `L.s("\(m)개월간 \(s)초 빨라졌어요", "\(s)s/km faster over \(m) months")`.
3. `MRPointPaces.tempo` → `mrThresholdPace(halfEquivMin: half * MRDistance.dH / 1000 / 60) ?? (tenK + half) / 2`. 주석의 "임의로 정함(중간값)"을 Daniels T 정의 + 설계 링크로 교체.
   `MRPlanPointTests.pacesComeFromHalfEquivalentByRiegel`에 `#expect(abs(p.tempo - 302.3) < 0.5)` 추가.
4. 컴파일 확인 → 커밋 "역치 추정 엔진 — 60분 대회 페이스·심박 교차·월별 추세, 템포 페이스 교체".

## Task 2 — 저장소 연결 + 성장 탭 카드 + 오늘의 인사이트

파일: `MIMORunning/Engine/MREngineStore.swift`, `MIMORunning/Views/ThresholdTrendCard.swift`(새), `MIMORunning/Views/GrowthView.swift`, `MIMORunning/Insight/RunHeadline.swift`, `MIMORunning/Views/ActivityDetailView.swift`, `MIMORunningTests/RunHeadlineTests.swift`

1. `MREngineStore`
   - `@Published private(set) var thresholdTrend: [MRThresholdEstimate] = []` — `refreshCore`에서 `predictions` 계산 직후 `mrThresholdTrend(runs: fetched, restingHRSamples: rhrSamples, dateOfBirth: dob, sex: sex, heat: heat, now: now)`. DEBUG 로그 `[역치] n점 · 최신 4'58 · 심박 168(보통)`.
   - `func thresholdChange(runStart: Date, runEnd: Date) -> (before: MRThresholdEstimate?, after: MRThresholdEstimate?)` — before = asOf `runStart − 1s`, after = asOf `runEnd`. 결과를 `[Date: ...]` 메모로 보관, refreshCore 시작 시 메모 비움.
2. `RunHeadline`
   - `struct ThresholdContext: Equatable { var beforePace: Double?; var afterPace: Double?; var tempoGapSec: Double? }`
   - `make(...)`·`candidates(...)`에 `threshold: ThresholdContext? = nil` 매개변수 추가(기본값으로 기존 호출·테스트 유지).
   - 좋은 신호 **맨 앞**: `before − after ≥ MR_THRESHOLD_IMPROVE_SEC` → title `L.s("역치를 밀어올린 러닝", "Raising the Threshold")`, fact `L.s("역치 페이스 추정 \(mrFormatPace(b)) → \(mrFormatPace(a))", "Threshold pace est. … → …")`, axis `.none`.
   - 좋은 신호 **맨 끝**: `i.workoutType == .tempo`, gap 있음 → fact `L.s("본인 역치 대비 \(부호)\(Int(abs(gap).rounded()))초/km", "\(…)s/km vs your threshold")`, axis `.none`, `titleEligible: false`. |gap| < 1이면 "본인 역치 페이스 그대로".
   - 테스트: 역치 상승 → 제목·사실·source .goodSignal; 2초 → 후보 없음; 템포 + 효율 신호 → 사실 두 번째에 역치 대비 줄; threshold nil → 기존 결과 불변.
3. `ActivityDetailView.recomputeHeadline`
   - `activity.type == .running && level >= .intermediate`일 때만 컨텍스트 생성. before/after = `engine.thresholdChange(runStart: activity.date, runEnd: activity.date + activity.duration)`.
   - tempoGapSec = 이 러닝 페이스(초/km; `Activity.avgPace` 단위 확인, 없으면 duration/distance×1000) − `before?.paceSecPerKm`.
   - `headlineKey`에 `engine.thresholdTrend.count` 추가(엔진 준비 후 재계산).
4. `ThresholdTrendCard` (성장 탭)
   - 입력 `points: [MRThresholdEstimate]`. 레이아웃·폰트·카드 배경은 같은 파일의 `MetricSparkCard`/`MRFormObservationCard` 스타일을 따른다(새 스타일 만들지 말 것).
   - 헤더 `L.s("역치 페이스", "Threshold Pace")`, 큰 숫자 `mrFormatPace(last)/km`, 심박 있으면 ` · 역치 심박 \(Int)bpm`.
   - Swift Charts `LineMark`+`PointMark`, `Theme.pace`, y축 반전(`.chartYScale(domain: .automatic(reversed: true))`) — 빠를수록 위, x축 월 라벨.
   - `mrThresholdTrendSentence` 있으면 `Theme.positive`로 한 줄.
   - 설명 줄(보조색 작은 글씨): `L.s("오래 버틸 수 있는 가장 빠른 페이스(약 1시간 대회 페이스) · 본인 기록으로 낸 추정", "…")` + 탭하면 basis 펼침.
   - 글자색 보라 금지(최근 커밋 기준 보라 글자는 `Theme.violetText`).
5. `GrowthView`: `metricTrendsSection` 다음에 `if manager.userLevel.bucket >= .intermediate, engine.thresholdTrend.count >= 3 { ThresholdTrendCard(points: engine.thresholdTrend) }` (GrowthView에 `engine` 환경 객체가 없으면 `@EnvironmentObject private var engine: MREngineStore` 추가 — 상위에서 주입되는지 확인).
6. 컴파일 확인 → 커밋 "역치 표시 — 성장 탭 역치 페이스 카드·오늘의 인사이트 '역치를 밀어올린 러닝'·템포 역치 대비".
