# 아침 러닝 제안(오늘 강도 게이트) — 설계

> 상태: 확정 (2026-09-22). 결정 4개 모두 권장안. 표시 위치는 사용자 지정 — 홈 오늘 카드 "N주 연속으로 달리고 있어요" 바로 아랫줄.

## 1. 목적

아침에 수면 HRV가 나오면 그날 **강도를 내도 되는지** 앱이 먼저 말한다. 러닝 후 총평(2026-09-21 스펙)이 "오늘 잘 뛴 건가"의 해석이라면, 이건 "오늘 뭘 할까"의 방향이다. 둘 다 같은 7일 추세(`mrHRVTrend`)를 쓴다.

HRV 기반 훈련 연구(Vesterinen 2016, Javaloyes 2019)는 전부 아침 값으로 그날 강도를 정한다. 정상 범위 안이면 계획대로, 아래면 저강도·휴식. 이렇게 한 그룹이 고강도를 덜 하고도 같거나 더 나은 향상을 얻었다.

**HRV는 종류를 고르지 않는다.** 인터벌·템포·롱런은 대회 플랜이나 주간 구조가 정한다. HRV는 계획을 오늘 해도 되는지 걸러주는 문이다. 그래서 출력은 세 단계다.

## 2. 판정 — `MRReadiness` (Engine/MRReadiness.swift, 순수)

```swift
struct MRReadiness: Equatable {
    enum Level: Equatable { case go, easy, rest }
    let level: Level
    let reasons: [String]     // 근거 조각, 순서대로 ' · '로 이어 붙인다
    let hrvPending: Bool      // 오늘 키의 밤이 아직 없다(워치 동기화 전) → "어젯밤 HRV 동기화 전"
    var line: String          // "오늘은 강도 OK · HRV 좋음 · 마지막 고강도 3일 전"
}

func mrReadiness(runs: [MRWorkout], phys: MRPhysiology, heatHR: MRHeatHRModel,
                 hrvNights: [(date: Date, value: Double)], planPhase: String?,
                 asOf: Date, calendar: Calendar = .current) -> MRReadiness?
```

### 2.1 입력 신호 (전부 MRWorkout 세계, 이 파일 안에서 계산)
| 신호 | 계산 | 출처 |
|---|---|---|
| `ranToday` | 오늘 달력일에 러닝이 있음 | `runs` |
| `lastHardDaysAgo` | 14일 창 마지막 고강도까지 일수 | `mrRecentHardRunCount` (기존) |
| `consecutiveDays` | 오늘 또는 어제로 끝나는 연속 러닝 일수 | 새 `mrConsecutiveRunDays` |
| `acwr` | 최근 7일 분 합 ÷ (직전 28일 분 합 ÷ 4). 28일에 러닝이 없으면 nil | 새 `mrDurationAcuteChronic` |
| `rising` | 최근 7일 분 합 ≥ 직전 7일 분 합 × 1.15 (직전 7일이 0이면 false) | 같은 함수 |
| `trend` | `mrHRVTrend(nights:asOf:)` | 기존 |
| `lastNightLow` | 오늘 키 밤 값 < 기준선 − 1.0 × max(SD, 10%·기준선). 추세 없거나 오늘 밤 없으면 false | `hrvNights` + `trend` (결정 3) |
| `hrvPending` | `hrvNights`에 오늘 키가 없음 | `hrvNights` (결정 4) |

### 2.2 규칙 (위에서 첫 매치)
| # | 조건 | 판정 | 근거 조각 |
|---|---|---|---|
| 0 | `ranToday` | **nil** (이미 뛴 날은 제안하지 않는다 — 오늘 기록 줄이 주인공) | |
| 0' | `runs` 비어 있음 | nil | |
| 1 | `planPhase == "회복"` / `"테이퍼"` | easy | "대회 계획 회복 주" / "대회 계획 테이퍼 주" |
| 2 | `acwr > 1.3` 또는 `consecutiveDays ≥ 4` | rest | "부하 급증" / "N일 연속" |
| 3 | `trend.isSuppressed` 또는 `lastNightLow` | rest | "HRV 낮음"/"HRV 불안정" / "어젯밤 HRV 유독 낮음" |
| 4 | `lastHardDaysAgo ≤ 1` | easy | "어제 고강도" (0이면 "오늘 고강도"지만 0은 `ranToday`라 도달 안 함) |
| 5 | `rising` 이고 `trend?.isReadyHigh != true` | easy | "부하 오르는 중" |
| 6 | `trend?.isReadyHigh == true` | go | "HRV 좋음", `lastHardDaysAgo`가 있으면 "마지막 고강도 N일 전" |
| 7 | 그 외 (HRV 범위 안 또는 자료 없음) | `lastHardDaysAgo == nil || ≥ 3` 이면 go, 아니면 easy | go: "HRV 보통"(추세 있을 때) + "마지막 고강도 N일 전" / easy: "고강도 N일 전 · 하루 더 여유" |

> 규칙 7 주석: 앞서 논의한 표는 "범위 안 → 이지런"이었다. 연구는 정상 범위 안이면 계획대로를 지지하므로, 부하 쪽이 넉넉할 때(마지막 고강도 3일 이상 전)만 강도 OK로 본다. 중간안이며 최종 문장에서 사용자에게 알린다.

`hrvPending`이면 `reasons` 끝에 "어젯밤 HRV 동기화 전"을 붙인다. 판정은 어제까지 자료로 그대로 한다.

### 2.3 문장
- go: `오늘은 강도 OK` / easy: `오늘은 이지런` / rest: `오늘은 휴식이나 짧은 이지`
- `line` = 판정어 + " · " + reasons.joined(" · "). 영어: `Today: hard is OK` / `Today: easy run` / `Today: rest or a short easy run`, 근거는 `HRV good` / `HRV normal` / `HRV low` / `HRV unstable` / `last night's HRV unusually low` / `last hard run N days ago` / `hard run yesterday` / `load rising` / `load spike` / `N days in a row` / `race plan: recovery week` / `race plan: taper week` / `last night's HRV not synced yet`.
- 의료 표현 없음. "제안"이지 지시가 아니다 — 문장에 "해야"를 쓰지 않는다.

## 3. 데이터 신선도 (결정 4)

- `MREngineStore.refreshCore`의 HRV 재조회 조건에 **"오늘 키 밤이 없음"**을 추가한다: `hrvNights.isEmpty || 24h 경과 || hrvNights.last?.date < today`. 조회는 60일 쿼리 하나라 싸다.
- 새 `MREngineStore.refreshHRVIfStale()`: 상태가 `.ready`이고 오늘 키 밤이 없고 마지막 조회가 30분 이상 전이면 `fetchSleepHRV` → `hrvNights` 갱신 → 조언·오늘 카드 재계산(기존 `recomputeTodayCard`와 같은 자리에서 `mrBuildAdvice`까지). 아니면 아무것도 안 한다.
- `MIMORunningApp`에 `@Environment(\.scenePhase)`를 두고 `.active`로 바뀔 때 `refreshHRVIfStale()`를 부른다. 앱 첫 진입은 기존 `.task { engine.refresh() }`가 처리한다.

## 4. 오늘 카드 (표시)

- `MRTodayCard`에 `readinessLine: String?`, `readinessLevel: MRReadiness.Level?` 추가.
- `mrTodayCard(...)`에 파라미터 추가: `heatHR: MRHeatHRModel = MRHeatHRModel()`, `hrvNights: [(date: Date, value: Double)] = []`, `planPhase: String? = nil`. 안에서 `mrReadiness`를 부른다. 기본값 덕에 기존 테스트 호출은 그대로 컴파일.
- `MREngineStore`의 `mrTodayCard` 호출 5곳을 `private func buildTodayCard(runs:now:)` 하나로 모은다. `planPhase = governingPlanWeek(for: now)?.week.phase`.
- `MRTodayCardView`: `streakLine` 바로 아래에 `readinessLine`을 그린다. 14pt, 색은 판정별 — go `Theme.positive`, easy `Theme.time`(노랑), rest `Color(hex: "FF9A3C")`(리듬 카드 경고와 같은 주황). 위 간격 6pt. nil이면 아무것도 안 그린다(오늘 뛴 날·자료 없음).

## 5. 조언 큐와의 관계

`hrvReady` 조언은 그대로 둔다(근거 펼치기용). 오늘 카드 줄이 매일의 판단, 조언은 그 배경. 둘이 어긋나지 않게 `hrvReady` 조건(위·안정 + 14일 고강도 ≤1 + 마지막 고강도 2일 이상 전)은 규칙 6의 부분집합이다.

## 6. 테스트 (작성만)
- `MRReadinessTests.swift` (Swift Testing, `.korean`): 규칙 0~7 각 1개 이상, 우선순위(회복 주가 HRV 좋음보다 먼저 · 급증이 HRV보다 먼저), `hrvPending` 접미, `lastNightLow`, 연속일·ACWR 헬퍼.
- `MRTodayCardTests`(XCTest)에 1개: `hrvNights`·`heatHR`를 넘기면 `readinessLine`이 채워지고, 오늘 뛴 날엔 nil.

## 7. 범위 밖
- 종류 제안(인터벌/템포) — 플랜에 일별 세션이 없다.
- 안정시심박·수면 점수 결합.
- 조언 큐에 easy/rest 항목 추가(오늘 카드 줄이 담당).
