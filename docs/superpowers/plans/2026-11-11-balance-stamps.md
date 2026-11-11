# 밸런스 스탬프 2종 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 스탬프 카드에 밸런스 스탬프 2개를 더한다 — ① 거미줄, ② 저울 + 거미줄. 그림은 밸런스 탭과 같은 컴포넌트를 크기·색만 바꿔 쓴다.

**Architecture:** 밸런스 탭(`BalanceTabCard`)의 거미줄·저울을 색 묶음(`BalanceDrawStyle`)과 크기를 받는 공용 뷰 2개(`BalanceRadarView`, `BalanceScaleView`)로 뺀다. 탭은 InsightInk 색으로, 스탬프는 스탬프 색(fill·outline)으로 같은 뷰를 그린다. 판정은 러닝 상세가 밸런스 탭과 같은 `BalanceTabCard.snapshot(context:vo2Points:)`로 한 번 만들어 카드 만들기 화면 → `StampData.balance`로 넘긴다.

**Tech Stack:** SwiftUI(Path·Shape, Canvas 금지 — ImageRenderer 첫 렌더 블랙 방지 관례) · Swift Testing / XCTest.

**Spec (채팅 승인 2026-11-11):**
- 스탬프 ① **거미줄**: 5축(심박·케이던스·보폭·접지·수직 진폭) + 꼭짓점 값 + 아래 `같은 페이스 6'20"/km`. 한 덩어리, 9칸 자유 위치.
- 스탬프 ② **저울 + 거미줄**: 왼쪽 저울(블록 + 블록 이름, 빨강 많은 쪽이 내려감) + 오른쪽 작은 거미줄, 가로로 나란히(스탬프 높이 상한 158pt 때문에 쌓지 않음).
- 몸 상태 세로 막대·한 줄 해석·폼 문장은 넣지 않는다.
- 색: 선·도형·글자는 스탬프 색상 모드(fill), 글자 테두리는 기존 스탬프처럼(`showTextOutline`, outline 색). **빨강·초록 점·값·블록만 의미 색 유지**(나쁜 쪽 `FF5A5F` · 좋은 쪽 `Theme.positive`) — 흑백(ink) 모드에서도. 회색 '평소 범위' 띠 → fill 색 옅은 면(불투명도 0.15), '평소' 점선 → fill 0.6, 오늘 도형 → fill 선 + fill 0.18 면.
- 판정은 밸런스 탭과 같은 값(같은 함수·같은 입력). 그림도 같은 뷰(§5.8: 복사 레이아웃 금지).
- 폼 없는 러닝·인터벌(`snapshot.mode != .full`)은 두 스탬프를 고르는 목록에서 숨긴다.
- 크기 소·중·대·특대, 측정 후 배율 표에 한 줄씩.

## Global Constraints

- 시뮬레이터로 화면 확인 금지. 컴파일: `xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` → `** TEST BUILD SUCCEEDED **`. 이번 작업은 사용자가 테스트 실행을 허락함 — 측정 테스트 `StampMeasureTests`만 실행해 크기를 잰다(아래 Task 2).
- 문구 한·영·일 `AppLanguage.shared.s(ko, en, ja:)`. 판정어·"부상/위험" 금지.
- 커밋은 경로 명시(`git add -A`·stash 금지, `project.pbxproj`·`docs/privacy-running-draft.md`·`.superpowers/` 커밋 금지). 메시지 한국어, 끝 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- 밸런스 탭 화면은 바뀌지 않아야 한다(Task 1은 리팩터).

## Review Focus

1. 밸런스 탭과 스탬프가 같은 러닝을 다르게 그리는 경우 — 같은 뷰·같은 스냅샷이어야 한다.
2. 흑백(ink)·라임 등 색 모드에서 빨강·초록 점이 사라지는 경우 — 남아야 한다.
3. 폼 없는 러닝·인터벌에서 스탬프가 목록에 보이거나 빈 그림이 나오는 경우.
4. 사진·영상·슬라이드·스토리 출력에서 스탬프가 빠지는 경우 — `StampData`가 그대로 흘러가야 한다.
5. 특대에서 높이 상한(158pt)을 넘는 경우.

---

### Task 1: 거미줄·저울을 공용 뷰로 (밸런스 탭 리팩터, 화면 불변)

**Files:**
- Create: `MIMORunning/Views/BalanceDrawing.swift`
- Modify: `MIMORunning/Views/BalanceTabCard.swift`

**Interfaces — Produces:**
```swift
struct BalanceDrawStyle {
    var primary: Color        // 값·주 글자
    var secondary: Color      // 축 이름·블록 이름
    var line: Color           // 바깥 고리·축선
    var band: Color           // 평소 범위 띠(면)
    var usual: Color          // 평소(점선)
    var today: Color          // 오늘 도형 선
    var todayFill: Color      // 오늘 도형 면
    var good: Color
    var bad: Color
    var usualBlock: Color     // 범위 안 블록(회색)
    var normal: Color         // 몸 상태 보통(노랑) — 저울 블록
    var board: Color          // 저울 판·받침
    var textOutline: Color?   // nil = 테두리 없음(탭), 스탬프는 outline 색
    var fontScale: CGFloat = 1
}
struct BalanceRadarView: View {   // 거미줄 + 축 라벨·값 (+ 참고 칩), 범례·페이스 줄은 포함하지 않음
    let snapshot: BalanceSnapshot
    let size: BalanceRadarSize    // w·h·r·labelR — 지금 RadarSize.large/medium을 옮긴 것 + 스탬프용 크기
    let style: BalanceDrawStyle
    var progress: Double = 1
}
struct BalanceScaleView: View {  // 판·받침·블록·블록 이름(+ 캡션 옵션)
    let snapshot: BalanceSnapshot
    let boardW: CGFloat
    let style: BalanceDrawStyle
    var progress: Double = 1
    var showCaptions: Bool = true // "몸 상태·부담 / 움직임"
}
```
- [ ] Step 1: `BalanceTabCard`의 radar/scale 관련 private 코드(RadarPolygon·RadarSpokes·RadarBand 등 도형, 축 라벨·꼭짓점 점, 판·블록·라벨·tiltRoom)를 `BalanceDrawing.swift`로 옮겨 위 두 뷰로 만든다. 색은 모두 `style`에서.
- [ ] Step 2: `BalanceTabCard`가 ink에서 `BalanceDrawStyle`을 만들어 두 뷰를 쓴다(값은 지금 쓰던 색 그대로 — 화면 불변). ViewThatFits·GeometryReader·범례·막대·문장은 카드에 남긴다.
- [ ] Step 3: 빌드 통과. Step 4: 커밋.

### Task 2: 스탬프 템플릿 2개

**Files:** `MIMORunning/Views/StampTypes.swift`, `MIMORunning/Views/StampCard.swift`, `MIMORunning/Views/StampControls.swift`(필터), `MIMORunningTests/StampMeasureTests.swift`(측정 데이터에 balance 표본)

**Interfaces — Consumes:** Task 1 뷰들. **Produces:**
- `StampTemplate.balanceRadar`, `.balanceScaleRadar` — `allCases` 맨 끝(선택 화면 순서). displayName: "밸런스 거미줄"/"Balance Radar"/"バランスレーダー", "밸런스 저울"/"Balance Scale"/"バランス天秤".
- `StampRequirement.balance` — `data.balance?.mode == .full`일 때만 충족. `requires`에 `[.balance]`.
- `StampData`에 `var balance: BalanceSnapshot? = nil`.
- 렌더: ① `VStack { BalanceRadarView(size: 스탬프 크기, style: stampStyle) ; Text("같은 페이스 6'20\"/km") }` ② `HStack(alignment: .bottom) { BalanceScaleView(boardW: 스탬프 판 폭, showCaptions: false) ; BalanceRadarView(작은 크기) }`. `stampStyle`은 Spec의 색 규칙(fill·outline·showTextOutline).
- 크기: 자연 크기(scale 1)를 정한 뒤 `StampMeasureTests`를 실행(`xcodebuild test ... -only-testing:MIMORunningTests/StampMeasureTests`)해 "[StampMeasure]" 출력으로 `sizeScales` 한 줄씩(다른 스탬프처럼 기준 폭 211pt의 40·55·72·90%, 높이 상한 158pt). 측정용 `wide` 데이터에 `BalanceSnapshot` 표본을 넣는다(테스트 파일의 `BalanceSnapshotTests.base()`와 같은 값으로 `BalanceSnapshot.make`).
- [ ] Steps: 타입 추가 → 렌더 → 필터 → 측정 실행 → 배율 반영 → 빌드 → 커밋.

### Task 3: 데이터 연결

**Files:** `MIMORunning/Views/ActivityDetailView.swift`, `MIMORunning/Views/ShareCardView.swift`, `FEATURES.md`(4.5 스탬프 목록)
- `ShareCardScreen`에 `var balance: BalanceSnapshot? = nil`; `ActivityDetailView`가 `BalanceTabCard.snapshot(context: summaryContext, vo2Points: vo2Points)`로 만들어 넘긴다(밸런스 탭과 같은 함수).
- `ShareCardView.swift` 1024행 `StampData(...)` 조립에 `d.balance = balance`.
- 스탬프 스토리·영상·슬라이드는 같은 `StampData`를 쓰는지 확인(쓰면 변경 없음).
- [ ] Steps: 연결 → 빌드 → FEATURES 한 줄 → 커밋.
