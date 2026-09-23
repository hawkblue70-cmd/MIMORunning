# 수면 HRV 추세 × 훈련부하 — 설계

> 상태: 확정 (2026-09-21). 결정 항목 6개 모두 권장안 채택.

## 1. 목적

"오늘 몸이 좋았던 게 HRV 때문인가, 2주 이지런 때문인가"에 앱이 답한다. HRV는 원인이 아니라 계기판이다. 그래서 HRV 단독 판정은 만들지 않고, **수면 HRV 7일 추세**와 **최근 14일 부하**를 한 문장에서 같이 말한다.

근거(요약): 저강도 기간에는 HRV가 오르고 고강도 기간에는 눌린다(Plews·Buchheit). 하루 값은 10~20% 자연 변동하므로 7일 평균과 변동계수만 본다. HRV 기반으로 강도를 조절한 러너는 고강도 시간을 덜 쓰고도 같거나 더 나은 향상을 얻었다(Vesterinen 2016). 반대로 취미 러너 10주 연구에서는 수면 HRV가 체력 향상을 추적하지 못했다 — HRV는 **회복 상태** 지표이지 **체력** 지표가 아니다. 문장도 그 선을 지킨다.

애플워치는 SDNN을 드문드문 샘플링한다. 하룻밤 값은 노이즈가 커서 밤 단위 중앙값 → 7일 평균 → 4주 기준선 비교로만 쓴다. 절대값을 상태어에 쓰지 않는다.

## 2. 현재 코드와 바뀌는 것

| 현재 | 변경 |
|---|---|
| `HealthKitManager.queryHRVRecovery` — 러닝마다 8번 쿼리로 "지난밤 vs 직전 7일 ±1.5SD" 계산, **어디에도 표시 안 됨** | 쿼리 제거. `HRVRecovery`·`RecoveryLevel` 타입은 캐시 디코딩 호환용으로만 남긴다(주석으로 deprecated 표시). `fetchCondition`은 `hrvRecovery`를 더 이상 채우지 않는다. `sleepVersion`은 올리지 않는다(재계산 폭주 방지). |
| 엔진 스토어가 안정시심박 400일을 한 번 가져와 UserDefaults 캐시(24h) | 같은 패턴으로 **수면 HRV 60일** 밤별 중앙값을 한 번 가져와 캐시. `@Published private(set) var hrvNights` |
| 총평 훈련부하 줄 `loadNext`가 부하만 보고 "충분히 회복" 판정 | HRV 추세를 결합. 새 줄은 만들지 않는다(결정 1a). |
| 조언 큐에 HRV 항목 없음 | `todayRun` 슬롯에 "강도 넣기 좋은 날" 1건 추가(결정 2). |
| 상세 컨디션 행: 날씨·수면 칩 | 변경 없음(결정 3 — 시각 요소 제외). |

## 3. 데이터

### 3.1 HealthKit 조회 — `MRHealthKit.fetchSleepHRV(days: 60)`
- `heartRateVariabilitySDNN` 샘플을 `HKSampleQuery` 한 번으로 받는다(시작일 = 오늘 − 60일, `strictStartDate`, ms 단위).
- 반환: `[(date: Date, value: Double)]` — 샘플 원본(시작 시각, ms). 밤 묶기는 순수 함수가 한다.

### 3.2 밤 묶기 — `mrHRVNightMedians(samples:calendar:)` (Engine, 순수)
- 기존 창과 같다: **전날 15:00 ~ 당일 12:00**을 "당일 밤"으로 본다.
  - 시각 ≥ 15:00 → 다음 날 키, 시각 < 12:00 → 그날 키, 12:00~15:00 → 버림(낮 샘플).
- 10ms 미만은 노이즈로 버린다(기존 `noiseFloor` 유지).
- 밤별 **중앙값**. 반환 `[(date: 자정, value: ms)]`, 날짜 오름차순.

### 3.3 캐시 — `MREngineStore`
- `hrvNights: [(date: Date, value: Double)]` 게시. UserDefaults 키 `mimo.hrvCache.fetchedAt` / `mimo.hrvCache.nights`, 24시간 TTL. `loadPersistedRHR`/`persistRHR`와 같은 형태의 `loadPersistedHRV`/`persistHRV`.
- `refreshCore`에서 안정시심박 다음에 조회. 실패하면 빈 배열(기능 전체가 조용히 빠진다).
- DEBUG 로그 한 줄: `[HRV] 60일 N밤 · 7일 평균 X ms(n) · 4주 Y±Z ms(n) · CV 7일 a% / 4주 b% · 상태`

## 4. 계산 — `MRHRVTrend` (Engine/MRHRVTrend.swift, 순수)

```swift
struct MRHRVTrend: Equatable {
    enum State: Equatable { case above, within, below }
    let state: State
    let isVolatile: Bool        // 7일 CV > 1.5 × 4주 CV
    let sevenDayMean: Double    // ms
    let baseline: Double        // 4주(28일) 중앙값, ms
    let baselineSD: Double      // 4주 표준편차(원본, 하한 적용 전)
    let sevenDayCV: Double
    let baselineCV: Double
    let sevenDayNights: Int
    let baselineNights: Int

    /// 위·안정 — 강도 세션 제안의 조건
    var isReadyHigh: Bool { state == .above && !isVolatile }
    /// 아래 또는 불안정 — "충분히 회복" 억제 조건
    var isSuppressed: Bool { state == .below || isVolatile }
}

func mrHRVTrend(nights: [(date: Date, value: Double)], asOf: Date) -> MRHRVTrend?
```

- **기준일은 `asOf`(그 러닝의 날짜)**. 오늘이 아니다. 오래된 러닝을 열어도 당시 상태가 나온다(`InsightPointInTimeTests` 원칙).
- 7일 창: 밤 키가 `day(asOf) − 6 … day(asOf)`. 러닝 전날 밤이 `day(asOf)` 키다. 유효 밤 **4 미만 → nil**.
- 4주 창: `day(asOf) − 34 … day(asOf) − 7` (28일, 7일 창과 겹치지 않음). 유효 밤 **14 미만 → nil**.
- 기준선 = 4주 중앙값, SD = 4주 표본 표준편차. 판정용 SD 하한 = `max(SD, baseline × 0.10)`(기존 규칙 유지).
- `above`: 7일 평균 > 기준선 + 0.5·SD_eff / `below`: < 기준선 − 0.5·SD_eff / 그 외 `within` (결정 5).
- CV = 표본 SD ÷ 평균. `isVolatile` = 4주 CV > 0이고 7일 CV > 1.5 × 4주 CV (결정 5). 7일 밤이 4개면 CV가 거칠지만 그대로 둔다 — 임계값이 이미 너그럽다.
- 레벨 게이팅 없음(결정 6). 추세만 말하므로 전 레벨 안전.

## 5. 부하 축 — 최근 14일 고강도 횟수

### 5.1 총평(Activity 세계)
- `RunSummaryBuilder`의 `daysSinceHardRun` 안에 있던 고강도 판정(체감 강도 ≥ 7 · 계획 고강도 유형 · 존 4+ 절반 이상)을 `isHardRun(_:)` 헬퍼로 빼서 둘이 같이 쓴다.
- `hardRunsLast14`: 러닝 날짜 기준 직전 14일(이 러닝 제외) 고강도 횟수. `runsLast14`: 같은 창 러닝 수.
- **이지 블록** = `hardRunsLast14 ≤ 1 && runsLast14 ≥ 4` (결정 5).
- 이 계산은 `hrvTrend != nil`일 때만 한다(존 분포 디스크 조회 비용).

### 5.2 조언 큐(MRWorkout 세계)
- `mrRecentHardRunCount(runs:phys:heatHR:days:asOf:)`: 14일 창에서 `isInterval`이거나, 15°C 보정 평균심박(`heatHR.refHR(of:) ?? hrAvg`)이 `phys.lt1HR.value` 이상인 러닝 수. LT1이 없으면 인터벌만 센다.
- 이지 블록 조건은 5.1과 같은 숫자(고강도 ≤ 1, 러닝 ≥ 4).

## 6. 문장

### 6.1 총평 훈련부하 줄 — `RunSummary`
`RunSummaryInput`에 추가: `hrvTrend: MRHRVTrend? = nil`, `hardRunsLast14: Int? = nil`, `runsLast14: Int = 0`. `isEasyBlock` 계산 프로퍼티.

**근거(`loadEvidence`)**: 추세가 있으면 맨 뒤에 `HRV 7일 37ms · 4주 30ms` (영어 `HRV 7-day 37ms · 4-wk 30ms`). 숫자는 반올림 정수. 상태(위/아래)는 근거에 안 쓴다 — 다음 행동 문장이 말한다.

**다음 행동(`loadNext`)** — 기존 분기 순서(강도 미입력 → 계획 회복/테이퍼 → 급증·단조·4일+ → 오늘 고강도 → 내려오는 중 → 충분히 회복 → 유지)는 그대로 두고 세 지점만 손댄다.

| 분기 | HRV 조건 | 문장 |
|---|---|---|
| 급증·단조·4일+ | `isSuppressed` | 기존 문장 뒤에 ` HRV도 기준선 아래로 흔들리고 있어요.` |
| 충분히 회복(`rested`) | `isSuppressed` | **대체**: `부하는 내려왔지만 HRV가 기준선 아래예요. 수면이나 생활 피로 쪽일 수 있으니 하루 더 편하게 가세요.` |
| 충분히 회복 | `isReadyHigh && isEasyBlock` | **대체**: `2주 이지런으로 회복이 쌓였어요. HRV가 4주 기준선 위로 안정적이라 이번 주 강도 세션 넣기 좋아요.` |
| 충분히 회복 | `isReadyHigh && !isEasyBlock` | **대체**: `충분히 회복됐어요. 고강도 뒤에도 HRV가 기준선 위라 부하를 잘 흡수하고 있어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.` |
| 충분히 회복 | `within` 또는 nil | 기존 문장 그대로 |

영어 문장은 같은 뜻으로 `L.s(ko, en)`에 함께 둔다. 의료적 표현("자율신경", "과훈련 증후군")은 쓰지 않는다. 톤(초록/노랑)은 바꾸지 않는다 — 상태어는 부하가 정한다.

### 6.2 조언 큐 — `mrBuildAdvice(hrvTrend:)`
- 새 파라미터 `hrvTrend: MRHRVTrend? = nil`.
- 조건: `hrvTrend.isReadyHigh` && 14일 고강도 ≤ 1 && 14일 러닝 ≥ 4 && 마지막 러닝이 3일 이내.
- `MRAdvice(key: "hrvReady", slot: "todayRun", grade: "B", gainMin: 3, timeliness: 0.6)`
  - text: `지난 2주는 이지런 위주였고 수면 HRV 7일 평균이 4주 기준선 위로 안정적이에요. 이번 주 강도 세션 하나 넣기 좋은 때예요.`
  - rationale: `HRV 7일 Nms · 4주 기준선 Nms · 14일 고강도 N회 · Vesterinen 2016(HRV 기반 강도 조절) · 회복 지표이지 체력 지표는 아님`
- 아래/불안정 조언은 이번 범위 밖(총평이 담당).

## 7. 배선

- `RunSummaryBuilder.Context`에 `var hrvNights: [(date: Date, value: Double)] = []` (memberwise init 기본값을 위해 `var`).
- 호출부 둘(`ActivityDetailView.summaryContext`, `RunInsightTabCard.summaryLines`)이 `engine.hrvNights`를 넘긴다. `RunInsightSection`에 `var hrvNights` 프로퍼티 추가, `ActivityDetailView`에서 전달.
- `MREngineStore`의 `mrBuildAdvice` 호출 4곳 모두 `hrvTrend: mrHRVTrend(nights: hrvNights, asOf: now)` 전달.

## 8. 테스트 (작성만, 실행은 사용자)

- `MIMORunningTests/MRHRVTrendTests.swift` (`@Suite(.korean)`)
  - 밤 묶기: 22:00 샘플 → 다음 날 키, 06:00 → 그날, 13:00 → 버림, 8ms → 버림, 중앙값.
  - 추세: above / below / within / 유효 밤 부족 → nil / 4주 창이 7일 창을 포함하지 않음 / `isVolatile` / asOf가 과거일 때 창 이동.
- `RunSummaryTests`에 추가: 세 대체 문장과 급증 추가 문장, `within`이면 기존 문장, 근거 줄의 `HRV 7일 … · 4주 …`.
- `MRAdviceQueueHRVTests.swift`: 조건 충족 시 `hrvReady` 1건, 고강도 2회면 없음, `isVolatile`이면 없음, trend nil이면 없음.

## 9. 범위 밖 / 후속
- 상세 컨디션 행 HRV 칩(시각 요소, 승인 필요).
- 아래/불안정일 때 러닝 전 "오늘은 이지런" 조언.
- 성장 탭 HRV 추세 차트.
- 실기기 확인: 워치 사용자에게 60일 중 밤 데이터가 몇 개 잡히는지(`[HRV]` 로그). 4주 창 14밤 미만이면 기능이 조용히 빠진다.

## 10. 실기기 반영 (2026-09-21 저녁)

첫 실기기 로그 `[HRV] 60일 61밤 · 7일 평균 27ms(7) · 4주 25±5ms(28) · CV 7일 7% / 4주 18% · 범위 안`. 판정선(27.5)에 0.5ms 모자라 "범위 안"이었으나 변동계수가 18%→7%로 준 것이 더 큰 신호라 다음을 추가했다.

- **안정 상승** `isStableRise` = 7일 평균 > 4주 기준선 **이고** 7일 CV < 4주 CV × 0.5. `isReadyHigh` = (밴드 위·비불안정) **또는** 안정 상승. 억제 조건(아래·불안정)은 그대로. 근거: 평균이 유지·상승하며 CV가 줄면 훈련을 잘 소화하는 상태(Plews·Buchheit, Flatt·Esco).
- **조언 `hrvReady`** 에 "마지막 고강도 2일 이상 전" 조건 추가(`mrRecentHardRunCount`가 `lastHardDaysAgo`도 반환). 14일 고강도 1회가 어제·오늘 러닝이면 제안하지 않는다 — 총평 규칙과 일치.
- **근거 줄 상태어**: `HRV 7일 27ms · 4주 25ms · 좋음`. 좋음(위·안정) / 불안정 / 낮음(아래) / 보통(범위 안). 본인 4주 기준선 대비 관찰어이지 절대 등급이 아니다. 억제가 좋음보다 먼저.

## 11. 밤 값은 잠든 동안만 (2026-09-23)

애플 건강 1일 화면과 비교하니 우리 밤 창(전날 15시~당일 12시)이 **기상 후 깨어 있을 때 값**(7시·8시·10:42)까지 밤에 넣어 중앙값이 낮게 나왔다(대략 28 vs 애플 수면 29~58). 사용자 결정: 수면 기록으로 기상 시각을 아니 잠든 동안 값만 쓴다.

- `MRHealthKit.fetchAsleepIntervals(days: 60)`: `sleepAnalysis`의 core·deep·REM·unspecified 구간.
- `mrHRVNightMedians(samples:asleep:)`: 잠든 구간(±15분) 안의 샘플만 그 밤(구간 끝 = 기상 시각의 키)에 넣는다. 그 밤에 수면 기록이 있는데 구간 밖이면 버린다. **수면 기록이 없는 밤만** 창 규칙으로 폴백.
- 엔진 스토어는 HRV·수면 구간을 나란히 조회(`async let`). 캐시는 밤별 중앙값만 저장하므로 형식 변화 없음. 기준선·이번 주 평균·상태어가 이 재료로 다시 계산되므로 값이 며칠 함께 바뀐다.
