# 미모러닝 (MIMORunning) 기획서

> **"걷고 뛰기만 하세요. 정리는 미모러닝이 합니다."**
> 자기 기록을 보며 발전하는 과정을 확인하고, 그 경험을 쉽게 공유하는 iOS 러닝 앱.
> MIMO 브랜드 라인: Biz · Students · **Running** · 상태: 설계 확정, 코딩 착수 단계

---

## 1. 개요 & 철학

- **주 목적**: 스스로 기록을 보고, 루틴을 통해 **발전하는 과정**을 확인.
- **부 목적**: 그 발전과 **경험을 이야기**(공유).
- **공유 원칙**: 단순·쉽게, 거창하지 않게.
- **타깃 폭**: 걷기부터 시작하는 입문자 ~ 데이터 풍부한 러너 모두 수용.
- **핵심 한 줄**: "어제의 나 vs 오늘의 나"를 보여주고 다음 방향을 제시.
- **브랜드**: MIMO = *Minimum Input, Maximum Output* — 사용자는 걷고 뛰기만(최소 입력), 앱이 읽기·레벨·표시·공유·인사이트를 자동 처리(최대 출력). 이름이 곧 제품 철학.

---

## 2. 핵심 설계 원칙

1. **있는 데이터만 동적 표시** — 폰 런=기본, 워치 런=풀. 없는 지표 자동 생략.
2. **레벨은 비공개 내부 스위치** — 라벨 노출 안 함. 표시 데이터 선택 + 방향성 메시지에만 사용.
3. **기준은 외부 공인 표준 사용** — 우리가 만들지 않음. 정밀도보다 적절한 버킷.
4. **3~5개 핵심 지표만** — "행동으로 이어지지 않는 데이터는 오락."
5. **비교보다 자기 발전 우선** — 동기부여 우선, 좌절 방지.
6. **건강한 진행** — 속도보다 꾸준함·점진적 증가. 과훈련 신호 존중.
7. **사진 우선, 기록만으로도 자기 표현** — 공유는 본인이 찍은 사진을 기본으로, 사진이 없어도 기록(타이포·코스·인사이트·미니미)만으로 자기를 표현할 수 있어야 함.
8. **데이터 표시 통일성** — 카드 형태(정지 이미지·영상·경로 영상)가 달라도 **데이터 표시 요소의 속성(폰트 크기·차트 크기·여백·MiniMe 크기 등)은 항상 동일**. 형태마다 별도 레이아웃 코드 작성 절대 금지. 반드시 하나의 공유 컴포넌트를 scale 파라미터로 재사용.

---

## 3. 데이터 소스 (HealthKit)

### 3.1 원칙
- 모든 기록은 **HealthKit 한 곳**에서 읽음 (기기 무관). v1은 앱이 직접 측정 안 함.
- "폰 런"은 서드파티 앱이 GPS로 기록해 HealthKit에 써준 것. (애플 기본 피트니스 앱은 워치 없이 런 기록 안 함)
- 삼성/갤럭시워치는 애플 공식 브리지 없음 → 서드파티 브리지 필요. 안내는 "건강 앱(HealthKit) 기준".

### 3.2 가져오는 데이터
- **항상(폰만 가능)**: 거리·시간·페이스·고도·스플릿 / 걸음 수·걷기 거리·걷기 운동 / 칼로리(추정) / 루트(야외)
- **워치 필요**: 심박·심박존·회복심박 / 케이던스·파워 / 운동강도·러닝폼(보폭·수직진동·지면접촉) / VO2max·안정시심박·HRV / 수면단계·수면점수·활력징후
- **계산/재구성**: 스플릿(거리 샘플) · 심박존/회복(샘플) · 수면점수(읽기 or 50/30/20 재현) · 인터벌 구간(⚠️ 직접 불가 → `workoutPlan` + 시계열 정렬 재구성)

| 상세 | 방법 | 가능 |
|---|---|---|
| 랩 | HKWorkoutEvent.lap | ✅ |
| 스플릿 | 거리 샘플 계산 | ✅ |
| 심박존/회복 | 샘플 계산 | ✅ |
| 인터벌 구간 | workoutPlan + 재구성 | ⚠️ 추가 로직 |

### 3.3 컨디션(맥락)
- 날씨: 워크아웃 메타데이터(무료) → WeatherKit 보완
- 수면: 단계·시간·취침·중단 (워치 있을 때 풍부) / 수면점수: 읽기 or 재현
- 활력징후: 안정시심박·호흡·손목온도·SpO2
- 수면은 **전날 밤** → 런과 연결. 컨디션 지표는 **참고용**(의료적 주장 금지).

### 3.4 권한·읽기 타입 (쓰기 없음)
`toShare: []`, `read:` 아래. 미사용 타입은 자동 무시.
- 운동: `workoutType()`, `workoutRouteType()`
- 거리·에너지·걸음: `distanceWalkingRunning`, `activeEnergyBurned`, `basalEnergyBurned`, `stepCount`
- 심박: `heartRate`, `restingHeartRate`, `heartRateVariabilitySDNN`, `walkingHeartRateAverage`, `heartRateRecoveryOneMinute`
- 러닝(워치): `runningSpeed`, `runningPower`, `runningStrideLength`, `runningVerticalOscillation`, `runningGroundContactTime`
- 체력·이동성: `vo2Max`, `walkingSpeed`, `walkingStepLength`
- 수면: `sleepAnalysis`
- 신체 특성: `dateOfBirth`, `biologicalSex` (에이지그레이드·벤치마크)
- Info.plist: `NSHealthShareUsageDescription` 필수.

---

## 4. 사용자 수준 시스템 (비공개)

### 4.1 목적
오직 둘 — (1) **표시할 데이터 자동 선택**, (2) **방향성 메시지 선택**. 평가·랭킹·뱃지 아님. 정밀도 불필요, 너그럽게.

### 4.2 세 표준의 역할
| 표준 | 재는 것 | 역할 |
|---|---|---|
| 인구 백분위 | 일반 러너 대비 상위 % | 표시 버킷 결정 |
| 에이지그레이딩(WMA) | 나이·성별 세계기록 대비 % | 공정 비교·장기 발전·상위 판정 |
| VDOT | 기록→체력→거리 환산·훈련 페이스 | 방향성 제시 |

> 라이선스: 독점 표 복사 금지, **공개 공식 구현**(WMA 계수·Daniels-Gilbert/Riegel·자체 백분위). 오프라인 번들.

### 4.3 판정 규칙
- 5단계 비공개 버킷: 초보→하수→중수→고수→신
- **1차 입력**: 최근 90일 최고 5K 등가(다른 거리는 Riegel/VDOT 환산)
- **보조**: 주간 거리(4주 평균)·최장 연속 달리기·데이터 기간
- **초보 게이트**: 연속 달리기 ≥ 5km → 하수 이상 자격. 미만(걷기/걷뛰기)은 페이스 무관 **초보**.
- **버킷 매핑**(상위 백분위 / 에이지그레이드): 하수 ~80%·<55% / 중수 ~50%·55–65% / 고수 ~20%·65–80% / 신 ~5%·80%+
- **콜드 스타트**: 러닝 3회 미만 → 초보 기본
- **강등 없음**: 도달 최고 레벨 유지 (표시 급변·좌절 방지)
- **교차검증**: 백분위 + 에이지그레이드 2축, 2개 이상 일치 채택, 갈리면 너그러운 쪽. VDOT는 방향성에.

### 4.4 수준별 유효 지표
| 레벨 | 메인 표시 | 방향성 핵심 |
|---|---|---|
| 초보 | 주간 거리·연속일수·안정시심박↓·"쉬워짐" | 속도보다 꾸준함 |
| 하수 | +페이스(추세)·거리목표·심박존 | 첫 5K 연속 |
| 중수 | +임계 페이스·동일워크아웃 비교·PR·VO2 추세 | 임계 훈련 |
| 고수 | +EF·파워/FTP·decoupling·GAP·러닝폼·부하 | 이코노미·임계 |
| 신 | +에이지그레이드(연도)·레이스 예측 | 절대 성능 |

> 숨김: 초보에 케이던스·파워·폼·VO2 절대값 숨김. VO2max는 추세만. 페이스는 추세로.

---

## 5. 데이터 표시 & 방향성

### 5.1 자동 표시
4.4 매트릭스를 기본값으로, "있는 데이터만" 원칙과 결합.

### 5.2 동기부여 트리거 (해당 레벨 핵심 지표 개선 시)
- 초보: "같은 코스 평균 심박 6↓ — 심폐 향상 신호" / "이번 주 거리↑" / "3주 연속!"
- 하수: "첫 5K 완주!" / "평균 페이스 한 달 전보다 20초↑"
- 중수: "지난달 5×1K보다 빨라요" / "10K PR" / "VO2max 8주간↑"
- 고수: "효율 인자(EF) 개선 — 같은 심박에 더 빠르게"
- 신: "올해 에이지그레이드 ○○%로 상승"
- VO2max는 초보~중수에서 특히 효과적, **추세만**. 레벨 상승은 축하, 하락은 조용히.

### 5.3 커스텀
기본 표시 후 사용자가 메인 지표 on/off 오버라이드.

### 5.4 오늘의 러닝 인사이트 (핵심 차별점)
"오늘 잘 뛴 건가?" 고민에, 과거 기록과 비교한 **제목 + 부연 + 가벼운 방향**을 자동 제시.

**구조**
```
[제목]  자산 축적 러닝          ← 철학적 헤드라인 ("○○ 러닝")
[부연]  3주 연속, 이번 주 4회    ← 데이터 근거
[지표]  10.02km · 6'12 · 1:02:04
```
공유 시 제목이 카드 헤드라인.

**제목 어휘(시작 세트)**: 어제보다 나은 러닝 / 한계를 미는 러닝 / 더 가벼워진 러닝 / 효율의 러닝 / 자산 축적 러닝 / 쌓이는 러닝 / 이겨낸 러닝 / 비를 뚫은 러닝 / 숨 고르는 러닝 / 비움의 러닝 / 경계를 넓힌 러닝 / 문을 연 러닝 / 시작이 전부인 러닝

**규칙 판정 — 조건 → 테마**
| 테마 | 발동 조건(계산) |
|---|---|
| 첫 성취 | 생애 첫 5K/10K/하프 등 |
| 기록 향상 | 동거리(±15%) 90일 중 최고 페이스/PR |
| 효율 향상 | 같은 코스 + 유사 페이스에 평균 심박↓ |
| 악조건 극복 | 수면 낮음/우천인데 평소 페이스 유지↑ |
| 거리 확장 | 이번 달/분기 최장 |
| 꾸준함 | 연속 N주 / 빈도 목표 / 누적 마일스톤 |
| 회복 | 느린 페이스 + 낮은 심박(의도적 이지런) |
| 입문·출석 | 미해당 + 그냥 나섬(초보 기본) |

**우선순위(헤드라인 1개)**: 첫 성취 > 기록 향상 > 악조건 극복 > 효율 향상 > 거리 확장 > 꾸준함 > 회복 > 입문·출석.

**생성 엔진 (하이브리드)**
- 사실 판단 = **규칙 엔진**(결정적). AI에 사실 안 맡김.
- 문장(제목·내러티브) = **Apple Intelligence**(Foundation Models, iOS 26+). 어휘집을 스타일 예시로 `@Generable` 제약.
- 폴백 = **어휘집**(미지원 기기). 어휘집 = 기본값·폴백·AI 스타일가이드 3역할.
- 편집 가능: 사용자가 제목 교체/입력.

**미니미** — 마스코트 베이스 + Image Playground 강화
- 베이스(전 기기): 디자인된 MIMO 마스코트의 테마 변형(비/트로피/이완).
- 강화(AI 기기): Image Playground(ImageCreator)로 테마 컨셉 미니미, 선택적 사용자 사진. 만화체.
- 수치는 못 그림(무드만) → 숫자는 타이포. 미지원 시 마스코트 폴백.

### 5.5 대회 자동 감지
- **데이터**: 공공데이터포털 "국내마라톤대회 정보"(문체부) 오픈 API — 대회명·일시·장소·종목, 무료·합법. 장소는 CLGeocoder로 좌표화. 소규모/신규는 사용자 등록 보완.
- **매칭**: 날짜 일치 + 출발 위치 근접(~1km) + 거리≈종목 → "이거 ○○ 대회였나요?" 제안 → 사용자 확인.
- **표시**: 대회 뱃지+이름 / "대회 러닝" 인사이트 / PR·마일스톤 연동 / 전용 카드 템플릿.

### 5.6 모션 & 애니메이션
데이터를 선택·배치한 뒤, 표시 요소에 생동감을 부여 (동기부여·재미).

**원칙**: 앱 화면 안은 적극 애니메이트. **공유 카드는 정지 이미지(ImageRenderer)** → 움직이는 공유(영상/GIF)는 프레임 렌더가 필요해 **v2**.

**데이터별 연출**
- **경로**: `Path.trim(0→1)`로 선이 그려짐 + 끝점 닷이 경로 따라 이동
- **그래프(페이스·심박)**: Swift Charts 자동 애니메이트 — 라인 그려짐 / 막대 자람
- **숫자(거리·페이스·심박)**: `.contentTransition(.numericText())` 롤링(오도미터)
- **아이콘**: `.symbolEffect(.pulse/.bounce)` (예: 심박 펄스)

**물리 모션 ("이동 / 급정지 후 움직임")**
- 스프링 프리셋: `.spring` / `.bouncy` / `.snappy` / `.smooth`
- `.interpolatingSpring(...)` — 관성 반영(쭉 이동 후 급정지·미세 출렁)
- `KeyframeAnimator`(iOS 17) — 다단계 안무(이동→정지→재움직임)
- `PhaseAnimator` — 트리거 시 단계 순차 재생

**범위**: 앱 내 애니메이션 = v1 / 움직이는 공유물(영상·GIF) = v2.

### 5.7 공유 카드 — 원칙 & 확장
**핵심 원칙: 사진 우선, 기록만으로도 자기 표현**
- **기본**: 사용자가 찍은 사진을 주제/배경으로 (실사진 우선, AI 장면 생성은 안 함).
- **사진이 없어도** 기록만으로 자기를 표현할 수 있어야 함 → 모든 템플릿은 **(a) 사진 모드 / (b) 기록 전용 모드** 2가지 지원.
- **기록 전용 모드** = 타이포 + 코스 라인아트 + 인사이트 제목 + **미니미** + 바이올렛으로 충분히 표현력 있게. (사진이 없을 때 **미니미가 "나"의 시각적 대리** 역할 → 자기 표현의 핵심)
- "있는 것만 표시" 원칙을 사진에도 적용 — 사진은 옵셔널.

**확장 후보 (검토)** — 실사례 검토(인스타·스레드)에서 도출
- **① 성장/마일스톤 카드 공유** — VO2max 게이지·PR·추세·상위%를 단일 런과 별개로 공유 (가장 차별적 → v1.x 검토)
- **② 네온 루트 스타일** — 실사진 위 우리 렌더 글로우 루트 (AI 장면 생성 없이 절제판)
- **③ 멀티 패널/캐러셀** — 요약 + 스플릿 + 지도 여러 장
- **④ 영상 공유** — 스트라바·편집 영상이 주류 → v2 내 우선순위 상향 검토

### 5.8 데이터 표시 통일성 규칙 (CRITICAL — 반드시 준수)

> **"카드 형태가 달라도 데이터 표시 방식은 하나다."**

**통일성이란**: 애슬레틱·영상·경로 영상 카드에서 폰트 크기, 차트 크기, 여백, MiniMe 크기, 색상 등 **데이터 표시 요소의 속성이 동일**한 것. 배경·비율은 달라도 데이터는 같아 보여야 한다.

**구현 원칙**
- **단일 컴포넌트 원칙**: 영상/경로 영상 오버레이는 `VideoOverlayCard(scale:)` **하나만** 사용.
- **scale 파라미터**: 렌더 크기에 맞게 scale을 조정하되 `scale=1.0`의 기준값(폰트 pt, 차트 px, 여백 pt)은 애슬레틱 카드와 동일하게 유지.
- **프리뷰 = 출력**: 미리보기 화면에서도 반드시 동일 컴포넌트 사용. 프리뷰만 따로 만들면 출력물과 달라짐 → 금지.
- **복사 금지**: 기존 컴포넌트를 복사해서 사이즈만 바꾼 별도 레이아웃 작성 절대 금지. 변경은 원본 컴포넌트를 수정.

**scale 기준값 (현재 확정)**
| 요소 | 기준값(scale=1) | 비고 |
|---|---|---|
| 워드마크 | 9pt | MIMO / RUNNING |
| 인사이트 제목 | 13pt bold | |
| 차트 | 160×100pt | CardChartPanelView |
| MiniMe | 54pt | |
| 아이콘/레이블 | 7pt / 8pt | 차트 패널 헤더 |
| 수평 패딩 | 10pt | |

**잘못된 예** (이 코드를 발견하면 즉시 수정)
```swift
// ❌ 금지: 영상 전용 별도 레이아웃
VStack {
    Text(title).font(.system(size: 15))  // 애슬레틱(13pt)과 다름
    MiniMeOrCustomImage(size: 38)        // 애슬레틱(54pt)과 다름
}

// ✅ 올바름: 동일 컴포넌트, scale만 조정
VideoOverlayCard(..., scale: 1.0)
```

---

## 6. 앱 구조 (IA)

탭 3개 + 컨텍스트 공유:
1. **기록(Activities)** — 런/걷기 리스트 + 이번 주
2. **성장(Growth)** — 페이스 추이·주간 거리·연속 히트맵·PR·월간 비교·심폐·나의 여정(걷기→러닝)
3. **나(Me)** — 누적 통계·마일스톤·설정·표시 커스텀

공유는 어느 기록에서든 꺼내는 액션.

### 6.1 화면별 상세 명세
**A. 기록 탭**: 이번 주 요약 + 권한 게이트 / 활동 카드(있는 지표만) / 상태(로딩·빈·거부·에러) / 당겨 새로고침 · 탭→상세.
**B. 활동 상세**: 헤더(+대회 뱃지) / 오늘의 인사이트(제목·부연·미니미) / 지도(야외만) / 지표 그리드 / 옵셔널(스플릿·랩·심박존·인터벌) / 공유 액션.
**C. 공유 카드**: 템플릿 선택(애슬레틱·스토리·+) / 데이터 토글(레벨 기본+사용자) / 사진 배경 / 제목 편집 / ImageRenderer→ShareLink.
**D. 성장**: 추이·주간거리·연속 히트맵·PR·월간·심폐·여정 (레벨별 차등).
**E. 나**: 누적·마일스톤·등록 대회·설정.
**공통 상태**: 로딩/빈/에러/오프라인 일관 적용.

---

## 7. 데이터 모델 (확정)

```swift
struct Activity {
    let id: UUID
    let date: Date
    let type: ActivityType        // walking / running / hiking
    let distance: Double          // m
    let duration: TimeInterval
    let avgPace: Double?
    let elevationGain: Double?
    let calories: Double?
    let avgHeartRate: Int?
    let avgCadence: Int?
    let avgPower: Int?
    let effort: Int?
    let routeCoordinates: [Coordinate]?
    let source: Source            // healthKit / manual
    var detail: ActivityDetail?
    var context: ActivityContext?
    var story: ActivityStory?
    var insight: Insight?
    var raceMatch: RaceMatch?
}

struct ActivityDetail {            // 있으면 렌더링
    var laps: [Lap]?
    var splits: [Split]?
    var hrZones: [HRZone]?
    var hrRecovery: HRRecovery?
    var intervalPlan: WorkoutPlanInfo?
    var intervalSegments: [Segment]?
    var runningForm: RunningForm?
}

struct ActivityContext {
    var weather: Weather?
    var sleepSummary: SleepSummary?
    var sleepScore: Int?
    var vitals: Vitals?
    var conditionIndex: Condition?
}

struct ActivityStory { var note: String?; var photos: [PhotoRef]; var mood: Mood? }

struct UserLevel {                 // 비공개, 표시 선택용
    let bucket: LevelBucket
    let ageGrade: Double?
    let vdot: Double?
    let percentile: Double?
}

struct DisplayConfig { var levelDefaults: [Metric]; var userOverrides: [Metric: Bool] }
struct Milestone { let type: MilestoneType; let date: Date; let value: Double }

struct Insight {                   // 5.4
    let theme: InsightTheme
    var title: String              // "○○ 러닝"
    var detail: String
    var miniMe: ImageRef?
}

struct Race {                      // 5.5
    let id: UUID
    let name: String
    let date: Date
    let startTime: Date?
    let venue: String
    let coordinate: Coordinate?
    let distanceType: RaceDistance
}

struct RaceMatch { let activityId: UUID; let race: Race; var confirmed: Bool }
```
> `detail`·`context`·`insight`·`raceMatch` 모두 옵셔널 → 있으면 렌더링.

---

## 8. 기술 스택 (iOS 17+)
- **SwiftUI** · **HealthKit** · **Swift Charts** · **MapKit**
- **ImageRenderer**(뷰→이미지, 핵심) · **ShareLink / PhotosPicker**
- **WeatherKit**(날씨) · **SwiftData**(스토리·설정·캐시)
- **Foundation Models**(인사이트 문장, iOS 26+/A17 Pro·M1+, 폴백=어휘집) *(선택 강화)*
- **ImagePlayground**(미니미, 폴백=마스코트) *(선택 강화)*
- 외부 표준(에이지그레이딩·VDOT/Riegel·백분위) 오프라인 번들
- 공공데이터포털 마라톤 API + CLGeocoder (대회 감지)

### 8.1 개발 환경 & 프로젝트 구조
- **필수**: 맥 + **Xcode 26.3** (네이티브 iOS). 윈도우 불가.
- **타깃**: iOS 17+ (Apple Intelligence 기능은 iOS 26+/대응 기기, 그 외 폴백)
- **AI 코딩**: Xcode 26.3 내장 Claude Agent(프리뷰 시각 검증) 또는 Cursor/Claude Code + Xcode 빌드
- **이 문서를 CLAUDE.md로** 프로젝트 루트에 배치
```
App/        MIMORunningApp
Models/     Activity, UserLevel, Race, Insight …
Health/     HealthKitManager, RaceDetector
Insight/    RuleEngine, TitleVocabulary, AppleIntelligence
Level/      LevelEngine (백분위·에이지그레이드·VDOT)
Views/      ActivityList, ActivityDetail, ShareCard, Growth, Me
Theme/      Theme (색·타이포)
Resources/  외부표준·대회 데이터
```

---

## 9. 로드맵 & v1(MVP) 범위

**v1 포함**
- [ ] HealthKit 읽기(걷기·러닝·하이킹) + 활동 리스트
- [ ] 활동 상세(지도·지표·스플릿/랩/심박존)
- [ ] 공유 카드 애슬레틱+스토리 2종(데이터 토글·사진 배경) + ImageRenderer + ShareLink
- [ ] 레벨 산출(백분위+에이지그레이드) + 수준별 자동 표시 + 방향성
- [ ] 오늘의 러닝 인사이트 규칙 엔진 + 어휘집
- [ ] 성장 화면(페이스 추이·주간 거리·연속 히트맵·PR)
- [ ] 마일스톤
- [ ] 앱 내 데이터 모션 (숫자 롤링 · 경로 그리기 · 그래프 애니메이트 · 스프링)

**v1.x / v2+**
- **성장/마일스톤 카드 공유**(VO2·PR·추세·상위%) — 차별적, v1.x 우선 검토
- 공유 확장: 네온 루트 스타일 · 멀티 패널/캐러셀 · 영상 공유(우선순위 상향)
- 인사이트 AI 강화 · 미니미 생성 · 대회 자동 감지 · 컨디션 통합
- 직접 GPS 추적 / WorkoutKit 구조화 운동 / 인터벌 재구성
- 플라이오버(가볍게·MapKit·낮은 우선순위) · 친구·크루
- **움직이는 공유물(영상/GIF export)** — 프레임 렌더 필요

> 원칙: 읽기→표시→공유 카드가 폴백만으로 완결되게. AI·대회·소셜은 그 위에 얹는 강화.

---

## 10. 개발 순서
1. HealthKit 권한 + 활동 리스트 ✅(완료)
2. 활동 상세(지도 + 지표 + 옵셔널 섹션)
3. **공유 카드 + ImageRenderer + ShareLink** ← MVP 관통점 ✅(애슬레틱 1종 완료)
4. 카드 템플릿 추가(스토리) + 데이터 토글 + 사진 배경
5. 레벨 산출(3표준) + 자동 표시 + 방향성/인사이트
6. 성장 화면(추이·히트맵·PR·여정)
7. 스토리·메모 + 마일스톤
8. (v1.x) 대회 감지 · AI/미니미 강화 · 컨디션

---

## 11. 디자인 확정 사항
- **앱 이름**: 미모러닝 / MIMORunning. 태그라인 "걷고 뛰기만 하세요. 정리는 미모러닝이 합니다."
- **브랜드 컬러**: 바이올렛 **#7C5CFC** (로고·버튼·하이라이트·레벨/성장 정체성)
- **지표 의미색**: 시간=노랑 · 페이스=청록 · 심박=빨강 · 고도=초록 · 파워=라임 · 칼로리=핑크 (Apple 관습)
- **타이포(공유 카드)**: 애슬레틱(콘덴스드) + 스토리(세리프 이탤릭) 2종. 라벨=시스템 산세리프 대문자.
- **미니미**: 마스코트 베이스 + Image Playground 강화

**추후 디테일(구현 중 확정)**: 미니미 마스코트 테마 세트 · 추가 카드 템플릿(코스·사진·미니멀) · 레벨 임계값 미세조정 · 카드 토글 기본 조합.
