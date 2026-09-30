# 오늘의 인사이트를 카드 판정의 요약으로 — 설계

날짜: 2026-09-30 · 상태: 사용자 승인(대화), 문서 검토 대기

## 1. 문제

상세 화면 맨 위 "오늘의 인사이트" 카드는 인사이트 엔진(`InsightEngine`)이 따로 고른 사실을 보여준다. 아래 카드들(리듬·폼·퍼포먼스·러닝 흐름)은 더 정교한 판정을 하는데, 맨 위 카드는 그 판정을 보지 않는다.

예: 2026-09-29 테이퍼 주 6.24km 편한 러닝. 맨 위는 "경계를 넓힌 러닝 · 이번 주 최장 거리 6.24km"(화요일, 이번 주 두 번째 러닝). 아래 카드는 "같은 페이스 최근 8주보다 심박 7bpm 낮음", "폼 끝까지 평소 범위", "어젯밤 HRV 평소보다 높음", "테이퍼 주 — 이지런 위주로"를 말한다. 맨 위가 가장 덜 중요한 사실을 말한다.

## 2. 목표

- 맨 위 카드 = 아래 카드 판정의 요약. **새 판정 로직을 만들지 않고 이미 있는 판정에서 고르기만** 한다 → 위아래가 서로 다른 말을 하는 일이 구조적으로 사라진다.
- 구성: **제목("○○ 러닝") + 핵심 사실 한 줄 + 다음 행동 한 줄**.
- 제목은 고른 핵심 사실에 맞춰 어휘 묶음에서 정한다(제목과 아래 줄이 같은 이야기).
- 공유 카드 헤드라인은 맨 위 카드 제목과 늘 같다.

## 3. 범위 밖

- 기록 목록 행(지금 인사이트 제목을 쓰지 않음)
- 애플 인텔리전스로 제목 짓기
- `InsightEngine` 자체 수정·캐시 버전 변경 (드문 사건과 대체 결과를 대는 역할로 그대로 둔다)

## 4. 구조

### 4.1 조합기 `RunHeadline` (새 파일 `MIMORunning/Insight/RunHeadline.swift`)

입력을 받아 결과만 돌려주는 순수 함수. 판정은 하지 않는다.

```swift
struct RunHeadline: Equatable {
    enum Source: Equatable { case rareEvent, restSignal, goodSignal, mildCaution, context, fallback }
    let title: String        // "가벼워진 러닝"
    let fact: String         // "같은 페이스에 심박 7bpm 낮음 · 폼은 끝까지 평소 범위"
    let next: String?        // 총평 "다음" 문장 하나. 없으면 nil(줄 숨김)
    let source: Source

    static func make(insight: InsightResult?,          // 저장된 인사이트 엔진 결과(드문 사건·대체)
                     summaryInput: RunSummaryInput?,   // RunSummaryBuilder.input
                     summaryLines: [RunSummaryLine],   // RunSummaryBuilder.lines (2줄 미만이면 재료 없음으로 본다)
                     efficiency: RunInsight?) -> RunHeadline?   // 퍼포먼스 심박 효율(RunInsightEngine, tone == .good일 때만 후보)
}
```

- `summaryLines.count < 2`(워치 없는 러닝·재료 도착 전)면 **대체(fallback)**: `insight`의 제목·부연 그대로. `insight`도 없으면 nil(카드는 지금처럼 "오늘의 러닝 / 인사이트 분석 준비 중").

### 4.2 후보와 순서

후보마다 (순서, 제목, 짧은 사실, 축)을 갖는다. 가장 앞 순서의 후보가 제목을 정한다.

| 순서 | 후보(발동 조건) | 제목 | 짧은 사실(예) | 축 |
|---|---|---|---|---|
| 1 드문 사건 | `insight.theme` ∈ {safety, returnGap, firstAchievement, raceDay, recordImproved, milestone} | 엔진 제목 그대로 | 엔진 부연 그대로 | — |
| 2 쉬어야 할 신호 | ① `acuteChronic` ∈ {high, veryHigh} ② `streakDays ≥ 4`이고 계획 회복·테이퍼 주가 아님 ③ 폼 `late == .faded` | ①② "쌓이는 러닝" ③ "끝까지 달린 러닝" | ① 훈련부하 줄 상태어("4주 평균 대비 높음") ② "N일 연속" ③ `FormPhase.shortState`("마지막 3km 페이스 떨어짐") | ①② 훈련부하 ③ 러닝폼 |
| 3 좋은 신호 | ① `efficiency`(tone good) ② 폼 `late == .held` 이고 거리 ≥ 8km ③ 계획된 고강도 유형(`FormNarrative.isPlannedHighIntensity(workoutType)`)이고 심박 줄 tone good ④ `distanceRank == 1`, `distanceSampleCount ≥ 5` | ① "가벼워진 러닝" ② "끝까지 버틴 러닝" ③ "한계를 미는 러닝" ④ "경계를 넓힌 러닝" | ① "같은 페이스에 심박 Nbpm 낮음"(N = `efficiency.highlights[0]`) ② "폼은 끝까지 평소 범위" ③ 심박 줄 상태어 ④ "최근 N회 중 가장 긴 거리" | ① 심박 ② 러닝폼 ③ 심박 ④ 거리 적응 |
| 4 가벼운 주의 | ① 폼 `late == .heavier` ② 심박 줄 tone neutral(이지런 심박 높음 등) | ① "끝까지 달린 러닝" ② "쌓이는 러닝" | ① `FormPhase.shortState` ② 심박 줄 상태어 | ① 러닝폼 ② 심박 |
| 5 맥락 | ① 계획 회복·테이퍼 주(`planPhase` == "회복"/"테이퍼") ② `workoutType == .easy`이고 심박 줄 tone good ③ `insight.theme == .consistent` | ①② "숨 고르는 러닝" ③ 엔진 제목 | ① "대회 계획 테이퍼 주"/"회복 주" ② 심박 줄 상태어 ③ 엔진 부연 | ①② 훈련부하/심박 ③ — |
| 6 대체 | 위 후보가 하나도 없음 | 엔진 제목 | 엔진 부연 | — |

- 2(쉬어야 할 신호)를 좋은 신호보다 앞에 두는 이유: 설계 원칙 6 "과훈련 신호 존중". 4(가벼운 주의)는 좋은 신호 뒤 — 원칙 5 "동기부여 우선".
- 같은 순서 안에서는 표의 번호 순(①→④).
- 축은 `RunSummaryLine.axis` 문자열(RunSummary가 쓰는 한국어·영어 라벨)로 맞춘다. 문자열 비교는 조합기 안 한 곳(축 상수)에서만 한다.
- "러닝폼 끝까지 유지"(좋은 신호 ②)는 8km 미만이면 **제목 후보는 아니고** 두 번째 사실로만 쓸 수 있다(짧은 러닝의 "끝까지 버틴"은 과장).

### 4.3 핵심 사실 한 줄

- 1순위 후보의 짧은 사실 + 그다음 후보의 짧은 사실 **하나**를 `" · "`로 잇는다(최대 2개).
- 두 번째 후보는 순서 2~5의 후보 중 1순위 후보 바로 다음 것. 드문 사건(1)·대체(6)가 1순위면 두 번째 사실을 붙이지 않는다(엔진 부연이 이미 완결 문장).
- 두 번째 후보가 1순위와 **같은 축**이면 건너뛰고 그다음 것을 쓴다(같은 이야기 반복 방지).
- 숫자는 각 카드가 쓰는 값·문구를 그대로 쓴다(새로 계산하지 않음).

### 4.4 다음 행동 한 줄

총평 5줄의 `next` 중 하나:
1. 1순위 후보와 **같은 축** 줄의 `next`
2. 없으면 훈련부하 줄의 `next`
3. 없으면 `next`가 있는 첫 줄
4. 모두 없으면 nil — 줄을 숨긴다

### 4.5 오늘(9/29) 러닝 예

- 후보: 3① 심박 효율(7bpm) → 1순위, 3② 폼 끝까지 유지(6.24km라 제목 후보 아님, 두 번째 사실 가능), 5① 테이퍼 주
- 결과:
  - 제목: 가벼워진 러닝
  - 사실: 같은 페이스에 심박 7bpm 낮음 · 폼은 끝까지 평소 범위
  - 다음: 대회 훈련 계획상 테이퍼 주예요. 이지런 위주로 가세요. (심박 축 줄에 next 없음 → 훈련부하 줄)

## 5. 화면 연결

### 5.1 상세 화면 (`ActivityDetailView`)

- `@State headline: RunHeadline?` — 인사이트(`insight`)·총평 재료(`hrSamples`, `formBaseline`, `effectiveHRZones`, `runInsights`)가 바뀔 때 한 번 계산한다(렌더마다 계산하지 않음). 총평 입력·줄은 기존 `summaryContext`(`RunSummaryBuilder`)를 그대로 쓴다.
- `InsightCard`에 `headline`을 넘긴다. 표시:
  - 제목: `headline?.title ?? insight?.title ?? "오늘의 러닝"`
  - 사실: `headline?.fact`(없으면 지금 `displayDetail` 그대로 — 대회 비교 줄·악조건 체감 강도 덧붙임 포함)
  - 다음(새 줄): `headline?.next` — 사실 줄 아래, 같은 글꼴 한 단계 흐리게. nil이면 숨김.
  - 드문 사건·대체일 때는 지금 `displayDetail` 규칙(대회 해마다 비교 줄 등)을 그대로 쓴다.
- 재료가 늦게 도착하므로 처음엔 지금 인사이트가 보이고, 재료가 모이면 한 번 바뀐다(`.contentTransition(.opacity)` 유지).

### 5.2 공유 카드 (`ShareCardScreen`)

- 상세 화면이 넘기는 `insight`를 **표시용 InsightResult**로 바꿔 넘긴다: 제목 = `headline.title`, 부연 = `headline.fact`, 테마 = 원래 인사이트 테마(없으면 `.default`). 공유 카드 헤드라인이 맨 위 카드 제목과 같아진다.
- 공유 카드 코드는 바꾸지 않는다(이미 `insight?.title`을 쓴다).

### 5.3 애플 인텔리전스

- 사실 줄은 숫자가 정확해야 해서 다듬지 않는다(규칙 문장 그대로).
- 대체(6)·드문 사건(1)일 때는 지금처럼 엔진 결과(애플 인텔리전스로 다듬은 부연 포함)를 그대로 쓴다.

### 5.4 과거 러닝

- 저장하지 않고 화면을 열 때 계산 → 예전 기록도 열면 새 방식. 캐시 무효화·버전 올림 없음.

## 6. 문구 (한국어 / 영어)

| 키 | 한국어 | 영어 |
|---|---|---|
| 가벼워진 | 가벼워진 러닝 | Lighter Run |
| 끝까지 버틴 | 끝까지 버틴 러닝 | Held to the End |
| 끝까지 달린 | 끝까지 달린 러닝 | Ran It Out |
| 쌓이는 | 쌓이는 러닝 | Stacking Up |
| 한계를 미는 | 한계를 미는 러닝 | Pushing the Edge |
| 경계를 넓힌 | 경계를 넓힌 러닝 | Expanding Boundaries |
| 숨 고르는 | 숨 고르는 러닝 | Catching Your Breath |
| 심박 효율 사실 | 같은 페이스에 심박 Nbpm 낮음 | HR N bpm lower at the same pace |
| 폼 유지 사실 | 폼은 끝까지 평소 범위 | Form stayed in range to the end |
| 거리 사실 | 최근 N회 중 가장 긴 거리 | Longest of your last N runs |
| 연속 사실 | N일 연속 | N days in a row |
| 계획 사실 | 대회 계획 테이퍼 주 / 대회 계획 회복 주 | Race plan: taper week / recovery week |

제목 어휘는 CLAUDE.md §5.4 어휘집("더 가벼워진 러닝", "쌓이는 러닝", "한계를 미는 러닝", "경계를 넓힌 러닝", "숨 고르는 러닝")에서 가져오거나 같은 결로 짓는다.

## 7. 테스트 (`MIMORunningTests/RunHeadlineTests.swift`, Swift Testing, `.korean`)

- 드문 사건(recordImproved)이 심박 효율보다 먼저 → 엔진 제목·부연, 두 번째 사실 없음
- 쉬어야 할 신호(부하 급증)가 심박 효율보다 먼저 → "쌓이는 러닝"
- 가벼운 주의(heavier)는 심박 효율 뒤 → 제목 "가벼워진 러닝", 두 번째 사실 = 폼 shortState
- 폼 held는 8km 미만이면 제목 후보가 아니고 두 번째 사실로만
- 같은 축 두 번째 사실은 건너뜀
- 다음 행동 고르기: 같은 축 → 훈련부하 → 첫 줄 → nil
- 총평 2줄 미만이면 대체(엔진 제목·부연)
- 9/29 예(4.5) 재현

검증은 `build-for-testing` 컴파일까지(시뮬레이터 금지 규칙). 화면은 사용자가 실기기로 확인.

## 8. 파일

| 파일 | 변경 |
|---|---|
| `MIMORunning/Insight/RunHeadline.swift` | 새 파일 — 조합기 |
| `MIMORunningTests/RunHeadlineTests.swift` | 새 파일 — 테스트 |
| `MIMORunning/Views/ActivityDetailView.swift` | `headline` 상태·계산, `InsightCard` 표시(제목·사실·다음 줄), 공유 카드에 표시용 인사이트 전달 |
