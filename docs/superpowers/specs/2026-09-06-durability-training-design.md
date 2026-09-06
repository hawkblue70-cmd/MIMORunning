# 내구성 훈련 반영 — 하프 대회 페이스 단계 · 근력/폼 판단 엔진 · 운동 제안

> 작성일 2026-09-06 · 상태: 설계 확정, 구현 계획 대기

## 1. 배경과 결정

하프 마라톤 훈련 자료(참고문헌 2편)를 앱의 훈련 계획·퍼포먼스 기능과 대조한 결과다.

### 1.1 문헌 확인 결과

**Fokkema 2020** — Scand J Med Sci Sports 30(9):1692–1704. 하프 556명 · 풀 441명, 관찰연구.

| 하프 변수 | 기준군 | 완주 시간 β | 95% CI |
|---|---|---|---|
| 최장 롱런 >21km | 15–21km | −3.87분 | −6.31 ~ −1.44 |
| 주간 >32km | 20–32km | −4.19분 | −6.52 ~ −1.85 |
| 후반 감속(5–10km vs 15–20km) | | 각각 약 −1.8~−1.9%p | |

- 자료가 말한 "21km 이상 = 12~15분 단축"은 하프 데이터에 없다. 그 숫자는 풀의 "롱런 <25km = +13.4분"이다. 하프의 실제 효과는 약 4분.
- 나이·성별·BMI·경력·부상 이력만 보정. **이전 기록으로 보정하지 않음** → 빠른 러너가 원래 더 뛴다는 교란이 남아 있다.
- 부상과는 어느 변수도 무관.
- 앱의 하프 롱런 목표 21km는 이 논문의 절단점과 일치한다. 풀 예측의 롱런 계단도 이미 이 논문에서 왔다.

**Van Hooren 2024** — Sports Med 54(5):1269–1316. 관찰연구 메타분석.

- 바이오메카닉스가 설명하는 러닝 이코노미 개인차 **4~12%** (단독 변수 기준).
- 유의: 수직 진동 r=0.35 · 수직 강성 −0.31 · 다리 강성 −0.28 · 케이던스 −0.20.
- **지면접촉시간 무관(r=−0.02)**, 보폭 무관(r=0.12).

### 1.2 대조 결론

| 자료 전략 | 앱 현재 | 결정 |
|---|---|---|
| 자세보다 체력 | 폼 모듈이 판정 금지 원칙 | 변경 없음 |
| 롱런 ≥21km · 훈련량↑ | 하프 목표 21km, +10%/주, 12개월 최대 캡 | 근거 주석만 추가 |
| 내구성(롱런 후반 대회 페이스 · 고중량/플라이오) | 풀만 "대회 페이스" 단계. 근력 조언은 "주 2회 30분" | **추가** (§2, §3, §4) |
| 80/15/5 강도 배분 | 강도 분포 카드 + 이지 비율 조언(B등급) | 변경 없음 (Rosenblat 2025: 극성 vs 피라미드 차이 없음) |
| 주기화 | 단계명만 있고 내용은 거리뿐 | §2로 부분 충족. 별도 질 세션 지시는 넣지 않음 |

**확정된 원칙**
- "롱런 마지막 15분 대회 페이스"는 두 논문 어디에도 없는 코칭 관행이다. 근거 주석에 "관행 · 통제 연구 없음"으로 표기한다.
- 근력 제안은 **피로 시 폼 붕괴 신호(S1)가 있을 때만** 발동한다. 워치의 근력 기록은 부정확하므로 근력 세션 횟수는 우선순위에만 쓰고 발동 조건으로 쓰지 않는다.
- 폼 제안은 케이던스 큐 하나만. 지면접촉·수직진동 교정은 개입 근거가 없어 제안하지 않는다.
- 사실 판단은 규칙 엔진. AI에 맡기지 않는다.

**제외**: 주차 테이블 근력 표시 · 12개월 주간 거리 캡 변경 · 강도 참고선 변경 · 폼 카드 비중 문구.

---

## 2. 변경 1 — 하프에도 "대회 페이스" 단계

**파일**: `MIMORunning/Engine/MRRacePlanner.swift`

### 2.1 단계 조건
- 현재: `distanceM >= MRDistance.dF && Double(i) > Double(buildWeeks) * 0.75` → "대회 페이스".
- 변경: `distanceM >= MRDistance.dH`. 5K·10K는 제외(근거가 하프·풀에 한정).
- 회복주·테이퍼주는 기존대로 제외. 3주 부하 1주 회복 사이클 유지.
- 우선순위는 지금과 같다: 대회 페이스 > 유지 > 늘리기.

### 2.2 실행 안내(breakdown) 문구
대회 페이스 주에만 아래 형식. 풀마라톤도 동일하게 받는다(지금은 단계명만 바뀌고 문구는 없다).

```
롱런 18km · 마지막 15분은 5'20"/km + 이지 8km × 3회
```

- **페이스 기준**: 그 주의 예측 기록(`proj`)에서 뽑되, **기온 보정 전 · 테이퍼 이득 전** 값을 쓴다. 훈련은 대회 기온에서 하지 않는다. 목표 기록은 쓰지 않는다 — D-day 카드의 "목표가 예측보다 빠르면 과속 배분" 원칙과 동일.
  - 하프 이하: `halfEquivMin × (distanceM/dH)^1.06`
  - 풀: `halfEquivMin × 2^b` (b = `bMarathonModel(peakVol, peakLong, finishes)`)
  - 초/km = 분 × 60 ÷ (distanceM/1000)
- **구간 길이**: 15분. 롱런 예상 시간(`longRunMin`)이 60분 미만이면 10분. 15분은 자료의 예시값이며 근거 주석에 "임의로 정함"을 남긴다.
- 영어 문구는 기존 패턴대로 빌드 시 `L.s`로 생성하고, `MRRacePlanView.localizedBreakdown`에 "마지막 N분은" → "last N min" 치환을 추가한다(캐시된 한국어 스냅샷 대응).

### 2.3 근거 주석 (파일 상단 doc comment에 추가)
- 하프 롱런 목표 21km: Fokkema 2020 하프군 >21km β −3.87분(CI −6.31~−1.44), 주간 >32km β −4.19분. 이전 기록 미보정 관찰연구.
- 롱런 후반 대회 페이스 구간: 코칭 관행. 통제 연구 없음. 근거가 나오면 바꿀 것.

### 2.4 캐시·버전
- `MRModelVersion.current` 2 → 3. 파생 캐시 자동 격리.
- 계획 스냅샷(`MRPlanWeekSummary`)은 시작 시점에 고정되므로 **진행 중인 계획은 바뀌지 않는다.** 새 계획부터 적용. 의도한 동작.

---

## 3. 변경 2 — 기존 근력 조언 보강

**파일**: `MIMORunning/Engine/MRAdviceQueue.swift` (key `"strength"`)

- 문구: "무거운 무게를 드는 근력운동과 점프 운동을 주 2회 함께 하면 다리가 후반까지 버팁니다. 주 30분이면 충분해요." Blagrove 2018 메타분석 자체가 고중량·플라이오메트릭을 다루므로 등급 A 유지.
- **억제**: 하프 이상 대회가 D-14 이내면 내지 않는다(테이퍼 중 새 고중량 금지, Bosquet 2007 원칙과 일관).
- **중복 제거**: §4의 `"durability"` 조언이 큐에 있으면 `"strength"`는 넣지 않는다. 같은 주제를 두 번 말하지 않는다.

---

## 4. 변경 3 — 내구성 판단 엔진과 운동 제안

### 4.1 신호 정의

| 신호 | 출처 | 정의 |
|---|---|---|
| **S1 피로 시 폼 붕괴** | km 스플릿 `SplitData.avgCadence` | 롱런의 마지막 25% 구간 케이던스가 첫 25% 구간 대비 **≥3% 하락**, 두 구간 페이스 차이 ≤5%일 때만 평가 |
| **S2 감속 원인 제외 플래그** | 스플릿 페이스·심박 | 초반 과속 또는 초반 역치 → 근력 문제가 아니므로 S1 판정에서 제외 |
| **S3 근력 세션** | `HealthKitManager.strengthPerWeek4w` | 우선순위 가중치에만 사용 |
| **S4 지속적 케이던스 하락** | 기존 `mrFormShift(cadence)` | `isReal && delta < 0` (같은 페이스에서 3개월 새 케이던스 감소) |
| **대회 창** | `plans`, `mrFinishedRun`, `gaps` | 시의성·억제 |

수직 진동은 쓰지 않는다. 폼 카드가 이미 Apple Watch MAPE 19%를 이유로 추세 판정에서 제외하고 있다. 일관되게 케이던스만 쓴다.

### 4.2 S1 계산 규칙 (신규 `Engine/MRDurabilityCheck.swift`)

**입력**: `MRLongRunFatigue` 배열 — HealthKitManager가 캐시된 상세(`detailCache` → `loadDetailFromDisk`)에서 만든다. HealthKit 재조회 없음.

```swift
struct MRLongRunFatigue: Codable {
    let id: UUID
    let date: Date
    let distanceKm: Double
    let durationMin: Double
    let q1PaceSecPerKm: Double     // 첫 25% 구간 (1km 제외)
    let q4PaceSecPerKm: Double     // 마지막 25% 구간 (마지막 부분 스플릿 제외)
    let q1Cadence: Double
    let q4Cadence: Double
    let firstHalfAvgHR: Double?    // 스플릿 avgHeartRate 평균
    let cadenceCoverage: Double    // 케이던스 있는 스플릿 비율
}
```

**롱런 자격**
- 러닝, 야외, 인터벌·빌드업·템포 아님 (`WorkoutType` ∉ {interval, buildUp, tempo}).
- 거리 ≥ max(10km, 최근 16주 최장 × 0.7), 시간 ≥ 60분.
- 케이던스 있는 스플릿 ≥ 80%, 전체 스플릿 ≥ 8개.

**구간**: km 1 제외 후 첫 25%를 Q1, 마지막 부분 스플릿(<1000m) 제외 후 마지막 25%를 Q4. 각 구간 최소 2개 스플릿.

**S1 판정** (셋 중 하나라도 실패하면 `nil` = 평가 불가, `false`가 아님)
1. 페이스 게이트: `|q4Pace − q1Pace| / q1Pace ≤ 0.05`. 이 게이트가 있어야 케이던스 하락이 속도 변화로 설명되지 않는다.
2. S2 제외: 초반 과속(`q1Pace < 최근 8주 러닝 페이스 중앙값 × 0.95`) 또는 초반 역치(`firstHalfAvgHR ≥ maxHR × 0.85`)이면 평가 불가. 기존 `analyzeFade`와 같은 규칙.
3. `q4Cadence < q1Cadence × 0.97` → `true`.

3%는 임의로 정함. 케이던스 170spm 기준 5spm으로 페도미터 정수 반올림(1spm)보다 충분히 크다. 근거 주석에 그렇게 남긴다.

**집계**: 최근 8주 자격 롱런 중 평가 가능(`nil` 아님)한 것 최신순 최대 3개. `true`가 2개 이상 → 근력 발동. 평가 가능 롱런이 2개 미만이면 판정 없음.

### 4.3 판정 → 조언

| 조언 key | 발동 | 등급 | gainMin | 슬롯 | timeliness |
|---|---|---|---|---|---|
| `durability` | S1 집계 발동 | B | 6 | 롱런 당일이면 `todayRun`, 아니면 `weekly` | 롱런 당일 0.8 · 그 외 0.4 · S3 <1.0이면 +0.1 |
| `cadenceCue` | S4 && S1 집계에서 `true`가 0개 | B | 2 | `weekly` | 0.3 |
| (기존) `strength` | S3 <1.5 | A | 4 | `weekly` | 0.2 · `durability` 있으면 생략 |

**억제 (세 조언 공통)**
- 하프 이상 대회가 D-14 이내 (테이퍼).
- 완주 기록이 있는 대회가 D+14 이내 (회복, `mrFinishedRun`).
- 공백 복귀 21일 이내 (`gaps.last`).

**문구**

`durability` (todayRun 당일):
> 오늘 롱런 후반에 케이던스가 N% 떨어졌어요. 최근 롱런 3번 중 2번이 그랬습니다. 다리가 지치면 발걸음이 느려지는 패턴이에요. 무거운 무게를 드는 근력운동과 점프 운동이 이걸 늦춥니다.

`durability` (weekly):
> 최근 롱런 후반에 발걸음이 느려지는 패턴이 반복됐어요. 무거운 무게를 드는 근력운동과 점프 운동이 후반 페이스를 지키는 데 도움이 됩니다.

rationale: `"최근 8주 롱런 N회 중 M회 후반 케이던스 ≥3%↓ · Blagrove 2018 메타분석(근력·플라이오 → 경제성) · 3% 임계는 임의"`

`cadenceCue`:
> 같은 페이스에서 케이던스가 3개월 새 N spm 내려갔어요. 이지런 한 번에 10분만 평소보다 5% 빠른 발걸음으로 달려보세요.

rationale: `"MRFormShift cadence Δ=N spm (MDC 통과) · Van Hooren 2024 r=−0.20 · Heiderscheit 2011 (+5~10% 케이던스)"`

**운동 목록** (`MRAdvice.exercises: [String]`, 신규 필드, 기본 `[]`)

`durability`:
- 근력 주 2회 20~30분 — 스쿼트·데드리프트·한발 운동·카프 레이즈 중 2~3개
- 무거운 무게 = 8회 이하로 힘든 무게, 세트당 3~5회
- 점프 — 제자리 홉·바운딩·언덕 스프린트 중 하나, 10분 이내
- 롱런 다음날은 피하고, 이지런 날에

`cadenceCue`:
- 이지런 중 10분, 메트로놈 앱을 평소 케이던스 +5%로
- 보폭을 줄인다는 느낌으로. 속도는 올리지 않는다

### 4.4 데이터 경로

```
HealthKitManager
  └ func longRunFatigueSummaries(asOf:) -> [MRLongRunFatigue]
      · detailCache → loadDetailFromDisk 순. 상세 캐시 없는 롱런은 건너뜀(쿼리 없음)
      · 최근 8주 러닝만 검사
GrowthView.onAppear
  └ engine.updateAdvice(strengthPerWeek:, fatigue:)        ← 기존 호출에 인자 추가
MREngineStore
  └ storedFatigue 보관 → mrBuildAdvice(..., fatigue:, formShiftCadence:)
      · refreshCore / refreshDetail / recomputePlans의 mrBuildAdvice 호출 모두 같은 인자 전달
MRAdviceQueue.mrBuildAdvice
  └ MRDurabilityCheck.evaluate(fatigue:, runs:, maxHR:) → 집계 결과
  └ 조언 생성 + 억제 + 중복 제거
```

- `formShiftCadence: MRFormShift?`는 GrowthView가 이미 계산하는 값(`mrFormShift(cadence)`)을 같은 `updateAdvice` 호출로 넘긴다. 엔진이 폼 계산을 중복하지 않는다.
- maxHR은 `MRPhysiology`의 기존 추정값을 쓴다.

### 4.5 표시 — 조언 카드 (신규)

**현재 상태**: `MREngineStore.advice`는 계산되지만 릴리스 UI 어디에도 렌더링되지 않는다(디버그 뷰만). 운동 제안이 사용자에게 닿으려면 표시면이 필요하다.

**위치**: 성장 탭, `updateAdvice`가 호출되는 화면의 상단 요약 아래. 대회 D-day 카드·오늘 카드가 있는 기록 탭에는 두지 않는다(같은 화면에서 말이 두 번 나오는 것을 피한다).

**형태**: `MRAdviceCardView` — 컴팩트 카드, 최대 2건.
- 한 줄 텍스트(`text`).
- 탭 → 펼침: `exercises` 불릿 + rationale(작은 글씨). 기존 "근거는 탭해서 보는" 패턴.
- `.onAppear`에서 `MRAdviceLog.record(keys)` → 저장. 판정 시점에는 기록하지 않는다(기존 주석 원칙).
- 조언 0건이면 카드 자체를 그리지 않는다. "제안 없음" 같은 문구 금지.

---

## 5. 테스트

`MIMORunningTests`에 추가. 전부 순수 함수 대상, HealthKit 불필요.

**MRRacePlanner**
- 하프 20주 계획에서 빌드 후반 25% 주차의 phase가 "대회 페이스"이고 breakdown에 "마지막 15분은"이 포함된다.
- 10K 계획에는 "대회 페이스" 주가 없다.
- 회복주·테이퍼주는 대회 페이스 문구를 받지 않는다.
- 롱런 예상 60분 미만이면 "10분".
- 페이스 값이 `halfEquivMin × (dH/dH)^1.06 × 60 / 21.0975`와 일치(기온·테이퍼 미적용).

**MRDurabilityCheck**
- 자격: 9km는 제외, 10km·60분은 포함. 인터벌 제외.
- Q1/Q4 구간 추출이 km1과 마지막 부분 스플릿을 제외한다.
- 페이스 차 6% → `nil`. 초반 과속 → `nil`. 초반 역치 → `nil`.
- 케이던스 2% 하락 → `false`, 3.5% 하락 → `true`.
- 집계: 3개 중 2개 `true` → 발동. 평가 가능 1개 → 판정 없음.

**MRAdviceQueue**
- `durability` 있을 때 `strength` 없음.
- D-10 하프 → 세 조언 모두 없음. D+7 완주 기록 → 없음. 공백 복귀 10일 → 없음.
- S4 && S1 0개 → `cadenceCue`. S4 && S1 1개 → 없음.
- 롱런 당일 timeliness 0.8, 다음날 0.4.

---

## 6. 구현 순서 (계획 문서에서 상세화)

1. 플래너 — 조건·문구·번역·근거 주석·모델 버전 · 테스트
2. 기존 근력 조언 — 문구·테이퍼 억제 · 테스트
3. `MRLongRunFatigue` + HealthKitManager 요약 함수
4. `MRDurabilityCheck` · 테스트
5. `MRAdviceQueue` — durability·cadenceCue·억제·중복 제거·`exercises` 필드 · 테스트
6. `MREngineStore.updateAdvice` 시그니처 확장 + GrowthView 호출
7. `MRAdviceCardView` + 성장 탭 배치 + record()
