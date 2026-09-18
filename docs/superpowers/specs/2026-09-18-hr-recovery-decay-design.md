# 회복 곡선 모양(τ) — 리듬 카드 오늘 한 줄

> 작성일 2026-09-18 · 브랜치 `crew` · 상태: 설계 확정
> 선행 스펙: `2026-09-06-hr-recovery-design.md` (HRR1 정의·권한·캐시·성장 추세). 그 결정은 그대로 두고 여기서 확장만 한다.

## 배경

`MRRecovery`는 이미 `hrr1`(종료심박 − 60초)과 `hrr2`(종료심박 − 120초)를 계산한다. 그런데 `hrr2`는 상세 화면 `HRRecoveryPanelChart`의 라벨로만 쓰이고 **어떤 판단에도 들어가지 않는다**. 리듬 카드에는 회복 값이 아예 없다.

문헌상 두 값은 중복이 아니라 서로 다른 축이다.

| 구간 | 지배 기전 | 근거 |
|---|---|---|
| 0–60초 | 미주신경 재활성(부교감 복귀) | Pierpont & Voth 2004 |
| 60–120초 | 교감신경 철수 + 카테콜아민 제거 | Shetler 2001 (JACC 38:1980–7), Pierpont & Voth 2004 |

## 결정

- **상관성의 형태**: HRR은 1차 지수감쇠로 기술된다(Pierpont & Voth 2004). 종료심박·HR60·HR120 세 값이면 시정수 τ가 닫힌 해로 나온다.

  ```
  HR(t) = HR∞ + (HRend − HR∞)·e^(−t/τ)

  x   = (hr60 − hr120) / (endHR − hr60)     ← 2분째 낙폭 ÷ 1분째 낙폭
  τ   = −60 / ln(x)
  HR∞ = endHR − (endHR − hr60) / (1 − x)
  ```

  **x는 두 값의 비일 뿐인데 종료심박이 소거되어 있다.** Daanen 2012이 지목한 최대 교란요인(끝낸 강도)이 구조적으로 빠지므로, HRR1 추세처럼 별도 회귀 보정을 두지 않는다.

- **좋다/나쁘다를 말하지 않는다**: Le Meur 2015(PLOS One 10:e0139754)에서 기능적 과부하(F-OR) 선수의 HRR이 오히려 **빨라졌다**. "빠름 = 좋음"은 쓸 수 없다. 문구는 중립 관찰 서술로만 낸다.

- **절대 경계를 만들지 않는다**: τ의 공인 절단점은 문헌에 없다. 임의 컷오프는 §2-3(기준은 외부 공인 표준) 위반이므로, **개인 과거 τ 분포의 사분위**로만 말한다. 개인 내 비교라 외부 규준이 필요 없고, 강도 교란은 x가 이미 소거한다.

- **범위**: 오늘 한 줄(리듬 카드)만. 장기 추세(τ 잔차)와 "다음 고강도까지 간격"(Stanley·Peake·Buchheit 2013)은 이번에 하지 않는다.

- **HR∞는 계산만 하고 표시하지 않는다**: 2분 외삽이라 불안정하다. 디버그 로그로만 남겨 나중에 판단한다.

- **게이트는 건드리지 않는다**: 종료심박 ≥ 최대심박 80% 자격은 선행 스펙 그대로. 다만 그 게이트를 통과하면서 HR120 샘플까지 있는 러닝 비율을 디버그 로그로 세어, 표본이 너무 적으면 별도로 다시 논의한다.

## 1. 엔진 — `MRRecovery`

```swift
struct MRRecoveryDecay: Sendable {
    let ratio: Double      // x
    let tau: Double        // 초
    let asymptote: Double  // HR∞ (표시하지 않음)
}
```

`MRRecoveryResult`에 `decay: MRRecoveryDecay?`를 더한다. `compute`에서 hr120이 있을 때만 시도하고, 가드 하나라도 걸리면 `nil`.

가드 (전부 임의값 — 수식이 발산하거나 감쇠가 아닌 경우를 거르는 용도):

| 조건 | 이유 |
|---|---|
| `hr120` 존재 | 식이 성립하지 않음 |
| 1분 낙폭 ≥ 8bpm | 분모가 작으면 x가 발산 |
| 2분 낙폭 > 0 | 심박이 되오른 경우(쿨다운 중 재가속·계단) |
| `0 < x < 0.95` | x ≥ 1은 감쇠가 아님 — 종료 직후 걷다가 멈춰 선 패턴 |
| `20 ≤ τ ≤ 200` | 위 가드를 통과해도 남는 극단값 |

`nil`이면 카드는 **침묵**한다. "회복 데이터 없음" 문구 금지(선행 스펙과 같은 태도).

## 2. 판정 — 개인 τ 분포 사분위

모집단은 **최근 12개월 러닝 중 `decay`가 성립한 것**(`fetchRecoveryHistory` 결과에서 τ를 계산), **이 러닝은 제외**한다 — 자기를 포함한 분포와 비교하면 표본이 작을수록 가운데로 끌린다.

과거 τ 표본 **8개 이상**일 때만 비교 문구를 낸다. 임의값이며, 사분위가 의미를 갖는 최소선으로 잡았다.

| 위치 | 문구 |
|---|---|
| 하위 25% | "평소보다 빠르게 안정됐어요" |
| 중간 50% | "평소대로 내려왔어요" |
| 상위 25% | "2분 뒤에도 계속 내려오는 중이었어요" |

8개 미만이면 비교 없이 사실만: "1분 −38 · 2분 −52bpm".

τ 숫자 자체는 어느 경우에도 노출하지 않는다(레벨과 같은 태도 — 내부 스위치).

## 3. 표시 — 리듬 카드 2×2 그리드, 심박 시계열 칸

`RhythmInsightCard.rhythmRow`의 우상단 칸. 지금 `hrVerdictText` 한 줄이 있는 캡션에 둘째 줄을 더한다.

- 심박 시계열 차트 자체는 **바꾸지 않는다.** 종료 후 3분은 60분 러닝 x축의 5%라 칸 안에서 보이지 않고 러닝 본체만 눌린다.
- 캡션 높이 `topCaptionH`(기본 28 / compact 24)가 2줄을 못 받으면 상수를 올린다. 2×2 네 칸이 같은 상수를 보므로 정렬은 유지된다.
- §5.8: 리듬 카드 = 내보내기 미리보기 = 같은 컴포넌트이므로 이 캡션은 **내보내기 카드에도 따라간다.** 의도한 동작이다.

## 4. 데이터

- `RecoveryHistoryPoint`에 **`hr120: Double?` 하나만** 추가한다. `endHR`과 `hrr1`이 이미 있으므로 `hr60 = endHR − hrr1`, 여기에 `hr120`이면 τ가 나온다 — 필드를 더 늘리지 않는다. `MRRecovery.compute` 결과에 이미 들어 있어 HealthKit 조회도 늘지 않는다.
- 캐시 스키마가 바뀌므로 `mimo_hrr_history_v2.json` → `_v3.json`. 메트릭 히스토리 캐시 무효화 목록도 같이 갱신.
- 개별 워크아웃 캐시(`mimo_hrr_{id}.json`)는 원 샘플이라 그대로 둔다.

## 5. 테스트 — `MRRecoveryTests`

- 합성 지수곡선(τ 기지)에서 τ 왕복 복원 — 오차 ±2초 이내
- HR∞ 복원
- 가드 경계: 1분 낙폭 7 vs 8bpm · 2분 낙폭 0 이하 · x = 0.95 vs 1.0 · τ 20/200 경계
- 사분위 3구간 전환 (하위/중간/상위 각 1건)
- 과거 표본 7개 → 비교 없는 폴백 문구, 8개 → 비교 문구
- hr120 없음 → `decay == nil`, 기존 `hrr1` 동작 불변

## 6. 하지 않는 것

- τ 장기 추세 · 잔차 회귀 (HRR1이 이미 담당)
- 다음 고강도까지의 간격 제안
- HR∞ 표시 · 안정시심박 대비 잔여 부하
- 공유 카드 전용 레이아웃 (§5.8 — 리듬 카드 컴포넌트를 따라갈 뿐)
- 임상 절단점(Cole 1999 12bpm · Shetler 2001 22bpm) 인용 — 앙와위 검사 기준

## 참고문헌

- Daanen HAM, Lamberts RP, et al. *A systematic review on heart-rate recovery to monitor changes in training status in athletes.* Int J Sports Physiol Perform 2012;7(3):251–260.
- Pierpont GL, Voth EJ. *Assessing autonomic function by analysis of heart rate recovery from exercise in healthy subjects.* Am J Cardiol 2004;94(1):64–68.
- Shetler K, Marcus R, Froelicher VF, et al. *Heart rate recovery: validation and methodologic issues.* J Am Coll Cardiol 2001;38(7):1980–1987.
- Le Meur Y, Buchheit M, et al. *The development of functional overreaching is associated with a faster heart rate recovery in endurance athletes.* PLOS One 2015;10(10):e0139754.
- Stanley J, Peake JM, Buchheit M. *Cardiac parasympathetic reactivation following exercise: implications for training prescription.* Sports Med 2013;43(12):1259–1277.
