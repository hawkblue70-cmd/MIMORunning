# 오늘의 인사이트 — 탭 요약(리듬·폼·퍼포먼스) 설계

- 날짜: 2026-10-14
- 상태: 설계 검토 대기
- 선행 설계: `2026-09-30-today-headline-design.md` (RunHeadline)

## 1. 왜

상세 화면 맨 위 "오늘의 인사이트"는 지금 **판정 하나 + 다른 축 사실 하나 + 다음 한 줄**이다(RunHeadline).
리듬·폼·퍼포먼스 카드에는 문제를 짚고 방향을 주는 문장이 수십 개 있지만, 사용자는 탭을 일일이 열어 보지 않는다.
→ **열지 않아도 세 탭의 결론(문제 + 방향)이 맨 위에서 읽혀야 한다.** 길어져도 된다(사용자 확정).

## 2. 원칙

1. **새 판정 금지.** 탭 카드가 이미 내린 판정·문장을 **같은 함수로** 가져온다. 요약과 카드가 다르게 말하면 안 된다.
2. **문제 + 방향을 우선.** 탭마다 "무엇이 문제였나(근거 숫자)" → "다음엔 어떻게"를 적는다. 문제가 없으면 좋은 신호를 사실로 적는다.
3. **있는 데이터만.** 재료가 없는 탭 블록은 통째로 빠진다(워치 없는 러닝 = 리듬만 또는 지금처럼 엔진 대체).
4. **같은 신호는 한 번만.** 신호 묶음(§5)마다 소유 블록을 하나로 정한다.
5. **말투.** 합쇼체, 해석·칭찬 대신 사실(기존 규칙). 진행률·달성률 표현 금지(기존 결정).
6. **탭으로 이동.** 블록을 누르면 해당 탭이 열린다. 요약은 목차 겸 결론.

## 3. 화면 구조

```
[제목]  숨 고르는 러닝                         ← RunHeadline.title 그대로 (공유 카드 헤드라인도 동일)

리듬 ─────────────────────────────────────
  이지런인데 Zone 3 이상이 52%였습니다. 후반 4km에서 심박이 9bpm 올랐습니다.
  → 다음 이지런은 Zone 2 상단(6'40" 안팎)으로 가 보세요.

폼 ───────────────────────────────────────
  같은 페이스 평소보다 지면접촉이 273ms로 길고 케이던스가 169spm으로 낮았습니다.
  다리가 무거운 날의 패턴입니다 — 5일 연속 · 최근 7일 부하 +134%.
  → 다음 러닝은 같은 거리에서 후반 지면접촉만 지켜보세요.

퍼포먼스 ─────────────────────────────────
  4주 평균 대비 7일 부하가 크게 높습니다(+34%). 같은 페이스 심박은 최근 8주보다 4bpm 높았습니다.
  → 다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋습니다.
```
(문장은 예시 — 실제로는 아래 표의 카드 문장이 그대로 들어간다)

- 블록 = **탭 라벨 + 상태 문장(최대 2개) + 방향 1줄(→)**. 블록 순서는 탭 순서 고정(리듬 → 폼 → 퍼포먼스).
- 상태 문장 톤 표시: 문제 = 노랑 점, 좋은 신호 = 초록 점(총평 줄과 같은 색 규칙).
- 지금의 `fact`·`next` 줄은 블록으로 옮겨지므로 맨 위에서 제거(중복 방지). 제목은 유지.
- 접기 없음(사용자: 길어져도 충분히). 최대 길이 = 제목 + 3블록 × 3줄.

## 4. 블록별 선정 규칙

각 블록: ① 문제 후보를 순서대로 훑어 **최대 2개** → ② 문제가 0개면 좋은 신호 1개 → ③ 방향 = 첫 문제의 짝 권고, 없으면 블록 기본 권고, 그것도 없으면 생략.
번호는 Explore 조사 목록(아래 "출처") 기준.

### 4.1 리듬 (심박 강도 · 후반 심박 · 거리)

| 순서 | 문제 후보 | 출처 문장 | 짝 방향 |
|---|---|---|---|
| R1 | 이지 의도인데 심박 높음 | 총평 심박 state "{유형} 기준 높음 · Zone 3 이상 {p}%" / 이지 판정 C19·C20 | 총평 심박 next "다음 이지런은 Zone 2 상단[, {pace}]…" |
| R2 | 회복·테이퍼·대회 후 주인데 고강도 | 총평 심박 state "{phase} 주인데 고강도…" | 총평 심박 next(D6) |
| R3 | 후반 진단(롱런 60분↑): 다리 먼저 / 심박 먼저 / 힘 빠짐 / 함께 | `LateRunDiagnosis.state` | `LateRunDiagnosis.next` (피로 누적이면 "회복한 뒤 다시 보세요") |
| R4 | 후반 심박 상승(빌드업·오르막 아님) | `FormNarrative.hrSecondHalfRiseCaption` + 차이 bpm | R3 없을 때만. 방향 없음(퍼포먼스 디커플링이 소유 시 생략, §5) |
| R5 | 의도 없는 템포 구간 머묾 / 고강도 많음 | `zoneVerdictLabel` A6 · `highIntensityZoneCaption` A7 | `highIntensityOneLiner` "다음 러닝은 이지런으로 하세요." |
| R6 | 페이스: 후반 많이 떨어짐(거리주) / 기복 / 후반 느려짐 | C13 · C15 · C16 | C13의 "초반이 빨랐을 수 있습니다" 문장 자체가 방향 |

좋은 신호(문제 0개일 때 1개): Zone 2 중심 / 이지 지킴(C18) → 끝까지 안정(A12) → 후반 여유(A11) → 최근 N회 최장(A1).
기본 방향: 거리 적응 next(D4, 거리 줄이 있을 때).

### 4.2 폼 (러닝폼 판정 · 후반 폼)

인터벌이면 `IntervalFatigueCard`의 `interpretation` + `suggestion` 한 쌍만 쓴다.

| 순서 | 문제 후보 | 출처 문장 | 짝 방향 |
|---|---|---|---|
| F1 | 후반 페이스 무너짐(faded) | `FormPhase.sentence`의 faded 절 | `formNext` "다음엔 중반을 10초/km 늦게 시작해 보세요." |
| F2 | 다리 무거움 패턴(이지: 접지↑ + 케이던스↓) | `FormNarrative.sentence` easy 분기 + `fatigueContext` | `formNext`(지면접촉) |
| F3 | 빠른 날 접지 김 / 케이던스 낮게 속도 | `FormNarrative.sentence` fast 분기 | 같은 문장의 "발걸음을 조금 더 빨리…" |
| F4 | 빌드업을 보폭으로만 올림 | C3 | C3 뒷문장 |
| F5 | 템포 후반 접지↑ / 발걸음↓ | C7 | C7 "템포 페이스가 살짝 빠를 수 있습니다" |
| F6 | 후반 무거워짐(heavier) / 위로 튐(bouncier) | `FormPhase.sentence` | `formNext` |
| F7 | 장거리 후반 범위 이탈 시작 km | B1 `longDistanceFormChangeInsight` | `formNext` |
| F8 | 케이던스 160 미만 | A1 "보폭이 큰 편입니다" | B7 케이던스-심박 권고가 있으면 그것 |

좋은 신호: held "끝까지 폼을 유지했습니다" → 템포 C5·C6 → 장거리 C9 → 접지 짧음(A7).
덧붙임(문제·좋은 신호와 별개, 있으면 1줄): 장기 추세 `mrFormObservation` 첫 문장.
기본 방향: B7 `cadenceHRInsight`(효율 케이던스 권고).
isSoftCadenceOnly는 **좋은 신호로** 다룬다(총평 tone과 맞춤 — 지금 RunHeadline은 주의로 넣는 어긋남이 있음).

### 4.3 퍼포먼스 (효율 · 지구력 · 부하 · 체력)

| 순서 | 문제 후보 | 출처 문장 | 짝 방향 |
|---|---|---|---|
| P1 | 복귀 공백 14일↑ | `returnInsight` "{g}일 만의 러닝…" + 공백 전 심박 비교 | 28일↑ "2~3주에 걸쳐 천천히 올려도 괜찮습니다" |
| P2 | 7일 부하 크게 증가 / 단조 | `sevenDayLoadRatioLabel` + `sevenDayLoadSentence` | 총평 `loadNext`(D10) |
| P3 | 디커플링 5%↑ (덥지 않음) | `decouplingReading` | 문장 안 원인("초반이 빨랐을 수") — 별도 방향 없으면 `enduranceInsight` 권고 |
| P4 | 같은 페이스 심박 높음 | `efficiencyInsight` 높음 + 원인 | 없음(사실만) |
| P5 | 이지 비율 경고 | `easyAlert` "{w}주 {n}회 중 이지런 {k}회…" | 총평 loadNext 중 강약 나누기 |
| P6 | 후반 페이스 5%↑ 느려짐 | `enduranceInsight` | 같은 문장 꼬리 |
| P7 | 유산소 등급 낮음·평균 이하 | `cardioInsight` | 같은 문장 꼬리 |

좋은 신호: 같은 페이스 심박 낮음(`efficiencyInsight` good) → 역치 상승 → 디커플링 ≤5% → 복귀 심박 회복 → 네거티브 스플릿.
기본 방향: 총평 `loadNext`(훈련부하 next — "지금 리듬을 유지하면 좋습니다" 포함).

## 5. 신호 묶음과 소유 블록 (중복 방지)

| 신호 묶음 | 등장 위치 | 소유 블록 |
|---|---|---|
| 후반 심박 상승 | 리듬 A10·D7, 퍼포먼스 디커플링·카디악 드리프트 | 디커플링이 계산되면(롱런·9.5km↑) **퍼포먼스**, 아니면 **리듬** |
| 후반 페이스 저하 | 리듬 C13·C16, 폼 faded, 퍼포먼스 지구력 | faded면 **폼**, 아니면 거리주는 **리듬**, 나머지 **퍼포먼스** |
| 훈련부하·연속일 | 총평 load 줄(리듬 카드 안), 퍼포먼스 7일 부하, 폼 fatigueContext | **퍼포먼스**(폼은 근거 꼬리로만) |
| 거리 순위 | 리듬 hero, 퍼포먼스 hero | **리듬** |
| 심박 효율 | 퍼포먼스 산점도·한 줄 | **퍼포먼스** |
| 폼 지표(케이던스·접지·보폭) | 리듬 카드 폼 요약 줄 B·C, 폼 카드 | **폼** (리듬은 심박·강도만) |

방향 문장도 같은 문장이 두 블록에 나오면 뒤 블록에서 뺀다.

## 6. 구현 범위

### 6.1 선행 수정 (결함)
`ActivityDetailView.swift:274`와 퍼포먼스 `heroContext`가 `category == .efficiency`만 본다. 카디악 드리프트도 같은 category라
템포·롱런에서 "같은 페이스에 심박 {n}bpm 낮음"이 **전후반 심박 차이**로 잘못 나올 수 있다(코드 읽기로 확인, 실행 미확인).
→ 효율 인사이트를 종류로 구분(전용 kind 또는 id)해 두 곳 모두 `efficiencyInsight`만 받게 한다.

### 6.2 뷰 판정 추출 (static, 문장과 톤 분리)
뷰 private에 갇혀 있어 지금은 요약에서 못 쓰는 것들. 카드도 추출한 함수를 부르도록 바꿔 **카드 = 요약** 단일 출처를 만든다.
- 리듬: `zoneVerdictLabel`, `hrVerdictText`, `buildWorkoutTypeFormParts`(C, Color 분리), `distanceContext`
- 폼: `FormNarrative.Input` 조립(밴드·GCT 보정 — `FormPhase.bandStats`와 공유), `longDistanceFormChangeInsight`(B1), `cadenceHRInsight`(B7)
- 퍼포먼스: `decouplingReading`/`aerobicDecouplingPct`, `easyAlert`, `sevenDayLoadSentence`/`RatioLabel`, `returnInsight`
- 재료는 대부분 `RunSummaryBuilder.Context`에 이미 있다. 강도 분포(`_intensityResult`)는 비동기 — 준비 전엔 P5를 건너뛴다.

### 6.3 조합기
`TabDigest.make(context) -> [TabDigest.Block]` (Insight/). 블록 = `tab, statements: [(text, tone)], direction: String?`.
§4 순서·§5 소유 규칙만 담당. RunHeadline 제목 선정은 그대로 두되 `fact`·`next`는 화면에서 내린다(공유 카드는 제목만 쓰므로 영향 없음).

### 6.4 화면
`ActivityDetailView`의 오늘의 인사이트 카드에 블록 렌더. 블록 탭 → `InsightTabKind` 선택 후 스크롤. 계산은 지금 headline처럼 입력이 바뀔 때 한 번.

### 6.5 테스트
- 조합기 단위 테스트: 이지런 심박 높음 / 다리 무거움 / 롱런 디커플링(소유권) / 복귀 / 인터벌 / 워치 없음 / 모두 평소.
- 추출 회귀: 추출 전후 카드 문장이 같음을 픽스처로 비교.

## 7. 결정 필요

1. **좋은 신호만 있는 탭** — 1줄로 적는다(권장, "충분히 적기") vs 블록 생략.
2. **지금의 fact·next 줄 제거** — 블록과 중복이라 제거 권장.
3. **오늘의 인사이트 내보내기(공유 이미지)** 에 블록을 넣을지 — 이번 범위 밖 권장(제목만 유지).
4. **대회 탭** — 대회 러닝은 대회 카드가 따로 있어 이번 범위 밖 권장.

## 8. 출처
조사 기준 파일: `Views/RunInsightTabCard.swift`(RhythmInsightCard·PerformanceInsightCard), `Views/RunFormCardView.swift`, `Views/IntervalFatigueCard.swift`,
`Insight/RunSummary.swift`·`RunSummaryBuilder.swift`·`FormNarrative.swift`·`FormPhase.swift`·`LateRunDiagnosis.swift`·`RunInsightEngine.swift`·`RunHeadline.swift`, `Engine/EffortLoad.swift`·`MRRecovery.swift`·`MRFormStyle.swift`.
