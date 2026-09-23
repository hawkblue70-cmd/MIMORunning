# 아침 제안 × 대회 훈련 계획 — 오늘 세션 제안 설계

> 상태: 확정 (2026-09-23). 결정 4개 모두 권장안.

## 1. 목적

아침 제안(2026-09-22 스펙)은 "오늘 강도를 내도 되는가"만 답했다. 대회를 등록해 훈련 계획이 있으면, 그 계획의 이번 주 구성("롱런 14km + 이지 8km × 3회", 대회 페이스 주면 "롱런 마지막 15분은 5'22"")을 읽어 **오늘 어떤 세션인지**까지 말한다. 원칙은 그대로다 — HRV·부하는 문을 열고 닫고, 종류는 플랜이 정한다.

## 2. 플랜이 아는 것 / 모르는 것

- 주 단위: 단계(늘리기·유지·대회 페이스·회복·테이퍼·대회 주·○○ 계획), 주간 km, 롱런 km·분. 이지 횟수는 본인 최근 4주 빈도(`MRProfile.runsPerWeek`)에서 `max(round(n) − 1, 1)`.
- 요일 배정은 없다 → "오늘 무엇"은 **이번 주에 남은 것 + 오늘 판정 + 본인 롱런 요일 습관**으로 추론한다.
- "거리주"라는 유형은 플랜에 없다. 대회 페이스 주의 "롱런 마지막 N분 대회 페이스"가 그 역할이다. 페이스는 예측 기록 기준(`mrTrainingRacePaceSecPerKm`), 목표 기록이 아니다.

## 3. 입력 — `MRPlanWeekContext` (스토어가 조립)

```swift
struct MRPlanWeekContext: Equatable {
    let phase: String
    let longRunKm: Double
    let weeklyKm: Double
    let easyRuns: Int              // max(round(runsPerWeek) − 1, 1)
    let racePaceSecPerKm: Double?  // phase == "대회 페이스"일 때만
    let racePaceSegmentMin: Int?   // mrRacePaceSegmentMinutes(longRunMin)
    let daysToRace: Int
}
```

`MREngineStore.buildTodayCard`가 `governingPlanWeek(for: now)`에서 만든다. 플랜이 없으면 nil → 종류 제안 없음(지금과 같음).

## 4. 판정 — `mrSessionSuggestion` (Engine/MRReadiness.swift, 순수)

이번 주 = 월~일(`MRPlanGovernance.weekMonday`). 이번 주 러닝 중 거리 ≥ 롱런 km × 0.8이면 **롱런 완료**, 나머지 러닝 수 = 이지 완료(상한 easyRuns). 남은 날 = 오늘 포함 일요일까지. 이지 1회 거리 = (주간 km − 롱런 km) / easyRuns.

**롱런 습관 요일** `mrHabitualLongRunWeekday`: 최근 8주(이번 주 제외) 각 주에서 러닝 2회 이상인 주의 최장 러닝 요일 최빈값. 표본 3주 미만이면 nil.

| 조건 | 세션 |
|---|---|
| `daysToRace ≤ 7` | **nil** — 대회 주는 D-day 카드가 담당(두 카드가 다른 말을 하면 안 된다) |
| 판정 rest | nil. 롱런 남았고 남은 날 ≤ 2면 진행에 "롱런은 이번 주 못 하면 다음 주로" |
| 판정 go, 롱런 남음, (오늘이 습관 요일 또는 남은 날 ≤ 2) | **롱런 Nkm** (+ 대회 페이스 주면 ", 마지막 N분 M'SS"") |
| 판정 go, 그 외 | 이지 Nkm |
| 판정 easy | 이지 Nkm |
| 롱런·이지 모두 완료 | nil, 진행 "이번 주 계획 완료" |

**진행 문자열**(둘째 줄 끝에 붙임): `이번 주 롱런 아직` 또는 `롱런 완료` · `이지 2/3회`. 롱런 남았고 판정이 easy/rest면 `· N일 남음`.

이지 거리가 1.5km 미만이면 숫자 없이 "이지런".

## 5. 표시

- `MRReadiness`에 `session: String?`, `progress: String?` 추가.
- **판정 줄**: 세션이 있으면 `판정어 · 세션` ("오늘은 강도 OK · 롱런 14km, 마지막 15분 5'22""). 근거 조각은 둘째 줄의 "왜" 문장이 이미 담고 있어 이 경우 판정 줄에서 뺀다. 세션이 없으면 지금처럼 `판정어 · 근거`.
- **둘째 줄**: 왜 + 데이터 + 진행.
- `hrvPending` 접미는 그대로 끝에.

## 6. 테스트 (작성만)
`MRReadinessTests`에 픽스처 `plan(phase:longRunKm:weeklyKm:easyRuns:daysToRace:)`로: go+롱런 남음+습관 요일 → 롱런 / go+롱런 남음+요일 아님 → 이지 + "롱런 아직" / 남은 날 2일 → 롱런 / 대회 페이스 문구 / easy → 이지 + 남은 날 / rest → nil + "다음 주로" / 대회 주 → nil / 롱런 완료 판정(0.8배) / 모두 완료 / 습관 요일 헬퍼.

## 7. 범위 밖
- 인터벌·템포 제안(플랜에 없음).
- 플랜 없는 사용자에게 주간 구조 추정.
