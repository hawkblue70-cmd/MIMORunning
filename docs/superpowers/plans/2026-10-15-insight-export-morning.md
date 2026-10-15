# 인사이트 내보내기 + 아침 제안 Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development. Steps use checkbox syntax.

**Goal:** 오늘의 인사이트 내보내기 이미지 아래에 '그날 아침 제안 → 실제'와 '다음 날 아침 제안'을 붙인다(스냅샷 우선, 없으면 asOf 재계산).

**Spec:** `docs/superpowers/specs/2026-10-15-insight-export-morning-design.md`

## Global Constraints
- 새 판정 금지 — 아침 문장은 `mrReadiness` 결과(line/why/data) 그대로, 실제 줄은 탭 요약 리듬 블록 short 그대로.
- 문자열은 `AppLanguage.shared.s(ko,en,ja:)`, 합쇼체, 사실, 진행률 표현 금지.
- 공유 작업 트리: `git add -A`/`.`/`stash` 금지, 경로 명시 커밋, pbxproj 커밋 금지(폴더 동기화).
- 테스트 실행·시뮬레이터 금지 — `xcodebuild build-for-testing ... -destination 'generic/platform=iOS Simulator'` → TEST BUILD SUCCEEDED.
- SwiftData 새 @Model은 CloudKit 규칙(모든 프로퍼티 기본값, unique 제약 없음)과 `MIMORunningApp.swift` 스키마 등록.

## Task 1: 아침 제안 스냅샷 저장
**Files:** Create `MIMORunning/Models/MRReadinessSnapshot.swift`; Modify `MIMORunning/MIMORunningApp.swift`(스키마), `MIMORunning/Views/MRTodayCardView.swift`(onAppear 저장), 필요 시 `MIMORunning/Engine/MRTodayCard.swift`(why/data 보존 필드).
**Produces:**
```swift
@Model final class MRReadinessSnapshot {
    var dateKey: String = ""        // "yyyy-MM-dd" (로컬 캘린더)
    var level: String = ""          // "go" | "easy" | "rest"
    var line: String = ""           // MRReadiness.line
    var why: String = ""
    var data: String = ""
    var planLine: String = ""
    var computedAt: Date = Date.distantPast
    init(...)
    static func key(for date: Date, calendar: Calendar = .current) -> String
}
enum MRReadinessSnapshotStore { @MainActor static func upsert(_ r: MRReadiness, at: Date, context: ModelContext); static func fetch(dateKey: String, context: ModelContext) -> MRReadinessSnapshot? }
```
- 홈 카드가 readiness를 보여 줄 때(onAppear + 값 변경) 그날 키로 upsert(같은 키면 갱신, computedAt = 지금). `MRTodayCard`가 why/data/level을 문자열로만 가지면 필요한 필드를 추가해 보존.
- 테스트: `key(for:)` 형식, 같은 날 두 번 upsert → 1개(인메모리 ModelContainer).

## Task 2: asOf 재계산
**Files:** Modify `MIMORunning/Engine/MREngineStore.swift`; Test `MIMORunningTests/MRReadinessAsOfTests.swift`.
**Produces:** `@MainActor func readiness(asOf: Date, hardRunStarts: Set<Date>) -> MRReadiness?` — `buildTodayCard`와 같은 입력을 asOf 기준으로 모아 `mrReadiness` 호출. `runs`는 `start < asOf`로 거른다. planWeek/rhythm/grayZone도 asOf 기준. 기존 buildTodayCard 동작 불변(공통 입력 조립을 private 헬퍼로 추출해 공유).
- 호출자용 헬퍼(앱 쪽): `RunSummaryBuilder`나 새 static에서 asOf−14…asOf 러닝 중 `isHardRun`인 시작 시각 집합 계산 — 홈 `pushHardRunStarts`와 같은 판정 함수 사용.
- 테스트: asOf 이후 러닝이 결과에 영향 없음(같은 입력에 미래 러닝 추가 전후 동일) · 러닝 당일 asOf = 시작−1초면 nil이 아님.

## Task 3: 조립기 + 내보내기 블록
**Files:** Create `MIMORunning/Insight/InsightMorning.swift`, `MIMORunning/Views/InsightMorningSection.swift`; Modify `MIMORunning/Views/RunInsightTabCard.swift`(InsightExportSheet), `ActivityDetailView.swift`/`RunInsightCardView.swift`(필요 입력 전달); Test `MIMORunningTests/InsightMorningTests.swift`.
**Produces:**
```swift
struct InsightMorning: Equatable {
    struct Entry: Equatable { let label: String; let level: String; let line: String; let why: String; let data: String }
    var morningOf: Entry?      // 그날 아침
    var actual: String?        // "실제: " 뒤 문장(탭 요약 리듬 블록 첫 short)
    var nextMorning: Entry?    // 다음 날 아침(데이터 있을 때)
    var nextDirection: String? // 다음 날 없을 때 "→ 다음" 줄
    static func make(runStart: Date, now: Date, snapshotFor: (String) -> MRReadinessSnapshot?,
                     recompute: (Date) -> MRReadiness?, firstRunStart: (Date) -> Date?,
                     actual: String?, direction: String?, calendar: Calendar) -> InsightMorning
}
```
규칙(스펙 §2·§3): 그날 아침 = 스냅샷(computedAt < runStart) → recompute(runStart−1) . 다음 날 = 스냅샷(그 날 키) → recompute(min(첫 러닝−1, 다음날 12:00, now)) 단 now < 다음 날 00:00 이거나 결과 hrvPending이면 nil → nextDirection. why는 첫 문장만.
- 뷰: 스펙 §4 레이아웃. 판정 색 = 홈 `MRTodayCardView`의 레벨 색 그대로(공유 함수로 꺼내 재사용). "수치 표시" 칩(기본 꺼짐) → data 줄.
- InsightExportSheet: exportCardView 맨 아래에 섹션 추가, 칩은 시트 컨트롤 영역. 엔진 접근은 `@EnvironmentObject engine`(ActivityDetailView가 이미 가짐) 또는 클로저 주입.
- 테스트: 스냅샷 우선 · 러닝 이후 스냅샷 무시 · 다음 날 pending → direction · why 첫 문장 자르기.

## Review Focus
1. 저녁 러닝 당일 내보내기 → 다음 날 블록 없음, 방향 줄만.
2. 아침에 홈을 열고 러닝 → 그날 아침 = 스냅샷(재계산 아님).
3. 앱을 안 연 날 → 재계산이 그날 러닝을 세지 않음.
4. 수치 칩 꺼짐 기본 → 이미지에 HRV ms 없음.
5. 기존 내보내기 카드 내용 불변.
