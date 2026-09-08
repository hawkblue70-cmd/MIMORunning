# 운동 강도(RPE 1~10) — 입력 · Apple 연동 · 강도 인사이트 · 주간 부하

> 작성일 2026-09-08 · 브랜치 `crew` · 상태: 구현 완료 (2026-09-08)

## 결정

- **범위**: 1단계(읽기·저장·입력 UI·상세 인사이트 3종) + 2단계(sRPE 주간 부하·플래너 연동·같은 강도 페이스 추이). HealthKit 쓰기(3단계)는 하지 않는다.
- **저장**: 내 앱(SwiftData `WorkoutStory`)에만 저장. HealthKit에 쓰지 않으므로 `toShare: []` 정책 유지.
- **값의 우선순위**: 내 입력 > Apple 수동 입력(`workoutEffortScore`) > Apple 추정(`estimatedWorkoutEffortScore`) > 없음. 미입력 런은 Apple 값만 쓴다. 심박으로 강도를 추정해 채우지 않는다.
- **소급**: 과거 런은 Apple 값으로만 채운다. 사용자가 수동 입력한 런부터 "내 입력"으로 취급한다. 과거 런에도 입력 UI는 열려 있으나(막지 않음) 사전 채움은 Apple 값만.
- **노출**: 러닝(`ActivityType.running`)에만 입력 UI를 보인다. 걷기·하이킹은 입력도, 부하 합산도 하지 않는다.
- **기준선은 개인 중앙값**: 절대 임계(문헌의 "이지런 2~4")를 쓰지 않는다. Apple 추정이 이지런에도 5~6을 주는 경향이 있어 절대값 비교는 거의 모든 이지런을 오판한다. 같은 워크아웃 유형의 최근 8주 중앙값과 비교하고, 절대 임계는 극단(이지런 8 이상)에만 쓴다.
- **앵커링 절충**: Apple 값이 있으면 막대를 그 값으로 채워 보이되 읽기 전용. "Apple 추정/입력" 배지(또는 수정 버튼)를 눌러야 편집 모드가 열린다. Apple 값이 없으면 바로 편집 가능.
- **iOS 17**: effort 타입은 iOS 18+. iOS 17에서는 Apple 값 없이 수동 입력만 동작한다. 모든 HealthKit 호출은 `if #available(iOS 18, *)`로 감싼다.
- **근거**: Foster 2001(sRPE = RPE × 분, CR‑10 수정 척도) · Seiler & Kjerland 2006(sRPE로 존 분포 재현 가능) · Ely 2007·El Helou 2012(더위의 페이스 비용) · Coyle & González‑Alonso 2001(심박 드리프트) · Impellizzeri 2020(ACWR은 상해 예측기가 아님 → "위험" 표현 금지). Coach Parry 마스터스 이지런 영상: 이지런 오류 3유형(초반 과속·환경 부하·후반 가속).
- **하지 않는 것**: HealthKit 쓰기, 심박 기반 강도 추정, 공유 카드 강도 표시, 레벨별 노출 차등(모든 레벨에 표시), ACWR을 "부상 위험"으로 표현, 걷기·하이킹 강도.

---

## 1. 데이터 모델

### 1.1 `WorkoutStory` (SwiftData, CloudKit 동기화)
```swift
var effortRPE: Int?          // 1...10, 사용자 입력. nil = 미입력
var effortUpdatedAt: Date?
```
- 옵셔널 + 기본값 nil → CloudKit 스키마 제약 충족. `hasContent`는 변경하지 않는다(강도만 있어도 "일기 있음"으로 취급하지 않음).
- 기존 `assignShoe(_:)`처럼 `WorkoutStory`가 없으면 생성 후 저장.

### 1.2 Apple 값 캐시 — `ActivityDetail`
```swift
struct AppleEffort: Codable, Equatable {
    var manual: Double?      // workoutEffortScore
    var estimated: Double?   // estimatedWorkoutEffortScore
    var fetchedAt: Date
    var effective: Double? { manual ?? estimated }   // 피트니스 앱과 동일 규칙
}
var appleEffort: AppleEffort?   // ActivityDetail에 추가 (디스크 캐시 버전 증가)
```

### 1.3 해석기 — `EffortResolver` (신규, `Insight/`)
```swift
enum EffortSource { case user, appleManual, appleEstimated }
struct ResolvedEffort { let value: Int; let source: EffortSource }   // value = 반올림 1...10
static func resolve(story: WorkoutStory?, apple: AppleEffort?) -> ResolvedEffort?
```
순수 함수. 러닝 여부 판단은 호출자가 한다.

---

## 2. HealthKit 읽기 (`HealthKitManager`)

- 읽기 타입에 `.workoutEffortScore`, `.estimatedWorkoutEffortScore` 추가(iOS 18+). 기존 사용자에게 권한 창이 한 번 더 뜬다. 앱 시작 시 기존 권한 요청 경로에서 함께 요청.
- **개별 조회** `fetchEffort(for workout: HKWorkout) async -> AppleEffort?`
  - `HKWorkoutEffortRelationshipQuery(predicate: HKQuery.predicateForObject(with: workout.uuid), anchor: nil, options: .mostRelevant)`. 결과 `samples`를 quantityType으로 나눠 `manual`/`estimated`에 넣는다. 단위 `HKUnit.appleEffortScore()`.
  - `HKQuery.predicateForObjects(from: workout)`는 effort 샘플에 동작하지 않으므로 쓰지 않는다(Apple DTS 확인).
- **일괄 조회** `fetchEffortMap(since: Date) async -> [UUID: AppleEffort]`
  - 날짜 범위 프레디킷 하나로 관계 쿼리 → 워크아웃 UUID 키 딕셔너리. 주간 부하·기준선·추이 계산용.
  - 디스크 캐시 `mimo_effort_map_v1.json` + `HKQueryAnchor` 저장으로 증분 갱신. 앵커 실패 시 전체 재조회.
- **갱신 시점**
  - 활동 상세 진입 시 해당 워크아웃 `fetchEffort` 재조회 → 값이 바뀌면 `ActivityDetail` 캐시와 effort map 갱신. Apple 추정은 워치 동기화 후 늦게 들어오고, 피트니스 앱에서 사용자가 수정하면 새 샘플이 추가되기 때문.
  - 활동 리스트 새로고침(`fetchActivities`) 시 `fetchEffortMap` 증분 갱신.
- 사용자 수동값이 있으면 Apple 값이 나중에 바뀌어도 수동값 우선(해석기 규칙). Apple 값은 "되돌리기" 대상으로만 남는다.

---

## 3. 입력 UI — `EffortScaleView` (신규, `Views/`)

위치: `ActivityDetailView.StorySection.body`의 `shoePicker` 바로 아래, "오늘의 러닝 일기" 헤더 위. `activity.type == .running`일 때만. 러닝화가 없어도(신발 피커 미표시) 강도 UI는 보인다.

```
운동 강도                     6 · 보통   [Apple 추정]
▇ ▇ ▇ ▇ ▇ ▇ ▁ ▁ ▁ ▁
쉬움      보통       힘듦    전력
```

- **막대**: 10개, `HStack(spacing: 3)`, 각 `RoundedRectangle(cornerRadius: 3)`, 높이 28pt, 폭 균등. 색은 `Theme.hrZoneColors`(5색 파랑→빨강)를 10단계로 선형 보간(`EffortPalette.color(for: Int) -> Color`). 값 이하 막대는 채움, 초과 막대는 같은 색 opacity 0.18.
- **라벨 4구간**(Apple 피트니스 어휘, 2차 소스 기준): 1~3 쉬움 / 4~6 보통 / 7~8 힘듦 / 9~10 전력. `L.s("쉬움","Easy")` 등 ko/en.
- **헤더 우측**: 값 칩 "6 · 보통" + 출처 배지. 배지 문구: 내 입력 / Apple 입력 / Apple 추정. 값 없음이면 칩 대신 "오늘 얼마나 힘들었나요?".
- **상호작용**
  - 편집 모드: 막대 탭 또는 가로 드래그로 값 설정. 손을 떼면 `WorkoutStory.effortRPE` 저장, 배지 "내 입력"으로 전환. 저장 즉시 상세 인사이트 재계산(4장).
  - Apple 값만 있을 때: 읽기 전용. 배지 탭 → 편집 모드. 편집 모드에서 Apple 값 위치에 얇은 테두리 표식(회색 outline)을 남긴다.
  - 사용자 값 + Apple 값이 함께 있을 때: 우측에 작은 "Apple 값으로 되돌리기" 버튼. 누르면 `effortRPE = nil`.
  - 값 없음(iOS 17 또는 폰 런): 바로 편집 가능, 막대 전부 흐림.
- 접근성: 각 막대 `accessibilityLabel("강도 N")`, 슬라이더 `accessibilityAdjustableAction`.

---

## 4. 1단계 인사이트 (활동 상세)

### 4.1 개인 기준선 — `EffortBaseline` (신규, `Insight/`)
- 입력: 최근 8주 러닝의 `(WorkoutType, ResolvedEffort)` 목록(현재 런 제외).
- `median(for type:)`: 같은 유형 3건 이상일 때 중앙값. 미달이면 전체 러닝 중앙값(3건 이상). 그것도 미달이면 nil.
- 정수 반올림. 유형은 `WorkoutTypeClassifier` 결과(`ActivityDetail.workoutType`).

### 4.2 규칙 — `EffortRules` (신규, `Insight/`, 순수 함수) → `[RunInsight]` (category `.intensity`)
입력: `effort: ResolvedEffort`, `type: WorkoutType`, `baseline: Int?`, `splits: [SplitData]`, `temperatureC`, `humidityPercent`.

| 규칙 | 조건 | tone · badge | 메시지(ko) |
|---|---|---|---|
| A 라벨 vs 몸 | type ∈ {easy, lsd} 이고 (effort ≥ baseline+2 또는 baseline nil이고 effort ≥ 7) | caution · 강도 참고 | "이지런인데 체감 강도가 N이었어요. 이름은 이지여도 몸이 힘들었다면 그날은 이지런이 아니에요." |
| A′ 극단 | type ∈ {easy, lsd} 이고 effort ≥ 8 | caution · 강도 참고 | 위와 같음(A와 중복 시 하나만) |
| A″ 여유 | type ∈ {tempo, interval, race} 이고 effort ≤ baseline−2 | neutral · 강도 메모 | "평소 같은 훈련보다 체감이 낮았어요. 여유 있게 소화한 날." |
| A‴ 부합 | 위 셋 미해당이고 baseline 있음 | good · 의도에 맞는 강도 | "훈련 의도와 체감 강도가 맞았어요." |
| B 더위 | (temperatureC ≥ 25 또는 humidityPercent ≥ 75) 이고 effort ≥ baseline+1 | neutral · 환경 | "N°C. 같은 페이스라도 더운 날은 체감이 1~2 높아지는 게 자연스러워요. 페이스보다 강도에 맞춰 뛰는 날." |
| B′ 더위 선방 | 같은 환경 조건이고 effort ≤ baseline | good · 환경 | "더운 날인데 체감이 평소 수준이었어요." |
| C 초반 과속 | type ∈ {easy, lsd}, 스플릿 ≥ 4개, 후반부 평균 페이스가 전반부보다 `splitThreshold`(3%) 이상 느림, effort ≥ baseline+1 | caution · 페이스 배분 | "후반이 처지고 체감도 높았어요. 초반 페이스가 목적보다 빨랐을 수 있어요." |
| C′ 후반 가속 | 같은 조건에서 후반부가 3% 이상 빠름, effort ≥ baseline+1 | caution · 페이스 배분 | "이지런 후반에 속도를 올리면 회복이라는 목적이 흐려져요." |

- 규칙 A 계열은 하나만 발화. B·C는 각 하나씩. 최대 3개 문장.
- baseline nil이면 A′·A″·A‴·B·B′·C·C′는 발화하지 않는다(A만 절대 임계로 발화).
- `splitThreshold`는 상수 하나(0.03)로 두고 이번에 튜닝하지 않는다. 마지막 부분 스플릿(1km 미만)은 전·후반 계산에서 제외.

### 4.3 배치
- `RunInsightEngine.insights(...)`에 `effort: ResolvedEffort?`, `effortBaseline: Int?` 매개변수 추가. 기존 `easyOverpaceInsight`(심박 기준)와 `EffortRules` 결과가 둘 다 있으면 `RunInsightTabCard` 강도 섹션에서 심박 문장 아래 강도 문장을 한 줄 추가한다. 기존 문장은 바꾸지 않는다.
- `environmentInsight`의 "체감 부담" 문장은 B/B′가 발화할 때 B/B′로 대체(중복 방지).
- `InsightEngine`(오늘의 러닝 인사이트) "이겨낸 러닝" 테마: 기존 조건 그대로 두고, 발화 시 `detail`에 강도가 있으면 "체감 강도 N"을 덧붙인다. 조건 변경 없음.
- 강도가 없으면(해석기 nil) 이 장의 어떤 문장도 나오지 않는다. "강도 없음" 문구 금지.

---

## 5. 2단계 — 주간 부하 · 플래너 · 추이

### 5.1 부하 계산 — `EffortLoad` (신규, `Engine/`, 순수 함수)
- 세션 부하 `AU = effort × duration(min)`. 러닝 + 해석기 값 있는 런만.
- `weekly(runs:, weekStart:) -> WeekLoad { total: Double, daily: [Double](7), runCount: Int, coveredCount: Int, meanEffort: Double? }`
  - `coverage = coveredCount / runCount`. `runCount == 0`이면 `WeekLoad` nil.
- 단조도 `monotony = mean(daily) / sd(daily)` (휴식일 0 포함). sd 0이면 nil.
- 7일 대 28일: `acute = 이번 주 total`, `chronic = 직전 4주 total 평균`. `ratio = acute / chronic`. 라벨: <0.8 낮음 / 0.8~1.3 유지 / 1.3~1.5 높음 / >1.5 크게 높음.
- **표시 조건**
  - 주간 합·일별 막대: 이번 주 러닝 1건 이상이면 표시.
  - 지난주 비교·단조도·28일 비교: 이번 주와 비교 대상 주 모두 coverage ≥ 0.5. 미달 주는 비교 문장 생략.
  - 28일 비교: 직전 4주 중 coverage ≥ 0.5인 주가 3주 이상. 미달이면 비교 없음(콜드 스타트, 안내 문구 없음).
  - 단조도 문장: monotony ≥ 2.0 이고 coverage == 1.0 일 때만.

### 5.2 성장 탭 카드 — "훈련 강도 부하" (`GrowthView`, 주간 거리 카드 아래)
- 7개 일별 막대(월~일). 막대 높이 = 그날 AU, 색 = 그날 평균 강도의 `EffortPalette` 색. 휴식일은 빈 칸.
- 헤더: "이번 주 부하 1,240 AU · 러닝 5회 중 4회 강도 있음". 지난주 대비 "+18%"는 표시 조건 충족 시.
- 하단 문장(우선순위대로 최대 1개): 단조도 → 28일 비교 → 없음.
  - 단조도: "휴식일 없이 비슷한 부하가 이어졌어요. 쉬운 날과 힘든 날을 나눠 보세요."
  - 28일 "크게 높음": "최근 4주 평균보다 부하가 많이 높은 주예요." / "높음": "평소보다 조금 높은 주예요." / "낮음": "회복 쪽으로 기운 주예요." / "유지": 문장 없음.
  - "부상", "위험" 단어 금지(Impellizzeri 2020).
- 데이터: `fetchEffortMap(since: 최근 12개월)` + 캐시된 러닝 요약(duration, type). 계산은 `EffortLoad`.

### 5.3 훈련 계획 플래너 연동 (`MRRacePlanView` 주 행)
- 이번 주 `MRPlanWeek.phase`가 "회복" 또는 "테이퍼"이고, 이번 주 `meanEffort`가 최근 8주 전체 러닝 강도 중앙값 + 1 이상(coverage ≥ 0.5) → 주 행 아래 한 줄: "회복 주인데 평균 강도가 평소보다 높아요."
- 그 외 단계에는 문장 없음. 계획이 없으면 표시 없음.

### 5.4 같은 강도의 페이스 추이 (`GrowthView`, `TrendMetric.easyEffortPace`)
- 대상: 해석기 강도 2~4인 러닝(개인 기준선이 아닌 고정 범위. 목적이 "쉬운 날의 페이스"이므로).
- 월별 중앙값 페이스, 최근 6개월. 월 3건 이상인 달만 점을 찍고, 유효한 달이 3개 이상일 때만 카드 표시.
- 문장은 **좋아진 쪽만**: "강도 2~4로 뛴 러닝의 페이스가 3개월 새 12초 빨라졌어요." 판정은 기존 `mrFormShift` 재사용(최근 3개월 vs 이전 3개월). 나빠진 쪽은 침묵.
- 기존 `TrendMetric` 스파크 카드·시계열 시트 경로를 그대로 탄다(hr-recovery와 동일 방식). 라벨 "쉬운 날 페이스", 단위 /km, 낮을수록 좋음, 색 `Theme.pace`.

---

## 6. 상태·오류
- 권한 거부/iOS 17: Apple 값 nil → 수동 입력만. 오류 문구 없음.
- 관계 쿼리 실패: 캐시 값 유지, 로그만.
- 사용자 입력 저장 실패(`modelContext.save` throw): 기존 스토리 저장과 동일하게 `try?` 후 UI는 낙관적 반영.
- 워크아웃 삭제 시 `WorkoutStory`는 기존 정책과 동일(정리 없음).

---

## 7. 테스트 (`MIMORunningTests`)
- `EffortResolverTests`: 우선순위(user > manual > estimated > nil), 반올림, 범위 클램프.
- `EffortBaselineTests`: 유형별 중앙값, 3건 미달 시 전체 중앙값 폴백, 현재 런 제외.
- `EffortRulesTests`: A/A′/A″/A‴ 배타성, baseline nil 시 A만, B/B′ 환경 조건, C/C′ 전·후반 계산(부분 스플릿 제외, 3% 임계), 최대 3문장.
- `EffortLoadTests`: 주간 합·일별·coverage, 단조도(sd 0 → nil), 28일 라벨 경계값(0.8/1.3/1.5), 콜드 스타트(유효 3주 미달 → nil), coverage 0.5 미달 시 비교 생략, 걷기 제외.
- `EffortPaletteTests`: 10색 보간 양끝이 `hrZoneColors` 첫·끝 색과 일치.
- UI: `EffortScaleView` 러닝 외 미표시(뷰 조건 함수 단위 테스트), Apple 값만 있을 때 읽기 전용 상태 플래그.
