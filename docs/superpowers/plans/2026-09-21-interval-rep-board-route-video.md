# 경로 영상 인터벌 회차 보드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 경로 영상(9:16, `RouteVideoFrameView` + `RouteVideoExportService.exportFast`)에서 **인터벌 러닝일 때만**, 지도가 그려지는 동안 운동 구간(회차)이 끝나는 자리를 지날 때마다 "회차 · 페이스 · 심박" 한 줄이 쌓이는 보드를 보여준다. 회복·준비·정리 구간은 경로를 흐리게 그리고, km 점은 숨긴다. 미리보기와 출력이 같은 컴포넌트를 쓴다(§5.8).

**Architecture:**
- **데이터**: `IntervalRepBoard`(순수 struct) — 운동 구간 목록·회차별 나타나는 지점(거리 비율)·머리글("5 × 1km")·바닥글("평균 4'52"")·흐리게 그릴 시간 구간. 뷰·서비스는 이 값만 읽는다.
- **뷰**: `IntervalRepBoardView(board:revealed:renderMode:scale:)` 하나. 미리보기는 `revealed`를 진행률에서 계산해 그대로 그리고, 출력은 같은 뷰를 두 번(뼈대만 / 줄만) 그려 줄 이미지를 **마스크 높이 애니메이션**으로 위에서부터 드러낸다. 줄 높이가 일정하므로 마스크 높이 = 전체 높이 × (보인 칸 수 / 전체 칸 수).
- **경로 흐리게**: 미리보기 `RoutePolylineOverlay`와 출력 `exportWithCAShapeLayer`가 같은 `dimTimeRanges`(운동이 아닌 구간의 시간 범위)를 받아 그 구간 색의 알파를 0.35로 곱한다. 인터벌이면 단색 모드도 50개 미세 구간으로 그린다(그라데이션 모드와 같은 기계).
- **게이트**: 운동(`stepLabel == "운동"`) 구간이 2개 이상일 때만 보드가 만들어진다. 그 외 러닝은 코드 경로가 하나도 바뀌지 않는다(보드 nil → 기존 차트 패널·km 점·경로 색 그대로).

**Tech Stack:** SwiftUI, Core Animation(`CAKeyframeAnimation`, `AVVideoCompositionCoreAnimationTool`), `ImageRenderer`, Swift Testing. 시뮬레이터는 쓰지 않는다 — 검증은 `xcodebuild build-for-testing`(앱+테스트 타깃 컴파일)까지, 화면 확인은 사용자가 실기기로.

**빌드 확인 명령(모든 태스크 공통):**
```bash
cd /Users/hns/MIMORunning/MIMORunning && xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|TEST BUILD (SUCCEEDED|FAILED)"
```
Expected: `** TEST BUILD SUCCEEDED **`

**git 규칙:** 다른 세션이 같은 crew 브랜치에 커밋한다. `git add -A`·`stash` 금지, 바꾼 파일 경로를 명시해 커밋. 커밋 메시지 끝에 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. `project.pbxproj`는 건드리지 않는다(파일 시스템 동기화 그룹이라 새 파일은 자동 포함).

---

## 파일 구조

| 파일 | 역할 |
|---|---|
| `MIMORunning/Insight/IntervalRepBoard.swift` (새) | 보드 데이터 + 나타나는 지점 계산 + 머리글/바닥글 문장 + 흐림 시간 구간. 순수 함수. |
| `MIMORunning/Views/IntervalRepBoardView.swift` (새) | 보드 뷰 하나(scale·revealed·renderMode). 글자 크기는 폼 카드 인터벌 표와 같은 값(행 10pt·머리 9pt at scale 1). |
| `MIMORunning/Views/CGImageAlphaBounds.swift` (새) | `CGImage.alphaBoundingBox()` — 줄만 그린 이미지에서 줄 영역을 찾는다. |
| `MIMORunning/Views/VideoOverlayCard.swift` | 보드 파라미터 3개 추가. 보드가 있으면 차트 패널 자리에 보드. |
| `MIMORunning/Views/RouteVideoService.swift` | `RouteVideoFrameView`·`RoutePolylineOverlay`(흐림·km 점 숨김·보드) / `exportFast`·`exportWithCAShapeLayer`(흐림·km 마커 숨김·보드 마스크 레이어). |
| `MIMORunning/Views/ShareCardView.swift` | 보드 생성(인터벌 게이트) + 미리보기·출력 호출에 전달. |
| `MIMORunningTests/IntervalRepBoardTests.swift` (새) | 데이터 규칙 테스트. |
| `MIMORunningTests/CGImageAlphaBoundsTests.swift` (새) | 알파 경계 테스트. |

기존 참고 코드:
- 회차 표 스타일: `MIMORunning/Views/IntervalFatigueCard.swift` 1063~1090 (행 10pt, 머리 9pt·0.38 흰색, 행 상하 패딩 3).
- 전력 구간 평균: `IntervalSegment.workAverage` (`MIMORunning/Models/Activity.swift`).
- km 마커 시간 키: `RouteVideoService.swift` `makeMarkerLayer` — `tAppear = pathFraction * routeDuration / videoDuration`, opacity 키프레임 `[0,0,1]`, `beginTime = AVCoreAnimationBeginTimeAtZero`, `fillMode .forwards`, `isRemovedOnCompletion = false`.
- 좌표 규약: 부모 레이어 `isGeometryFlipped = true`, 자식 레이어의 `position`·`frame`은 **UIKit 좌표(y=0 위, 뒤집기 없음)** — km 마커와 동일하게 쓰면 지도와 맞는다(주석 "empirically confirmed").
- 미리보기 진행률: `ShareCardView.animateRouteVideoPreview()` — 0.1초마다 `routePreviewProgress += 2/60` (3초에 완주). 진행률 비율만 맞으면 시간과 무관.

---

### Task 1: `IntervalRepBoard` 데이터 + 테스트

**Files:**
- Create: `MIMORunning/Insight/IntervalRepBoard.swift`
- Test: `MIMORunningTests/IntervalRepBoardTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("경로 영상 인터벌 회차 보드", .korean)
struct IntervalRepBoardTests {
    /// 준비 1km(6'20") → [운동 1km + 회복 200m] × n → 정리 1km. 10초 간격이 아니라 구간 시각만 있으면 된다.
    private func segments(reps: Int, workM: Double = 1000, workPace: [Double]? = nil, hr: [Int]? = nil,
                          start: Date = Date(timeIntervalSince1970: 1_000_000)) -> [IntervalSegment] {
        var out: [IntervalSegment] = []
        var t = start
        func add(_ label: String, _ m: Double, _ sec: Double, hr: Int? = nil, cad: Int? = 184) {
            let end = t.addingTimeInterval(sec)
            out.append(IntervalSegment(id: out.count + 1, startDate: t, endDate: end, distanceM: m,
                                       avgHeartRate: hr, avgCadence: cad, stepLabel: label))
            t = end
        }
        add("준비운동", 1000, 380, hr: 130)
        for i in 0..<reps {
            let pace = workPace?[i] ?? 295
            add("운동", workM, pace * workM / 1000, hr: hr?[i] ?? 150)
            if i < reps - 1 { add("회복", 200, 90, hr: 135) }
        }
        add("정리운동", 1000, 372, hr: 128)
        return out
    }

    private func total(_ segs: [IntervalSegment]) -> (m: Double, s: TimeInterval) {
        (segs.compactMap(\.distanceM).reduce(0, +), segs.last!.endDate.timeIntervalSince(segs.first!.startDate))
    }

    @Test func needsAtLeastTwoWorkSegments() {
        let one = segments(reps: 1)
        let t = total(one)
        #expect(IntervalRepBoard.make(segments: one, activityStart: one[0].startDate, totalDistanceM: t.m, totalDuration: t.s) == nil)
        #expect(IntervalRepBoard.make(segments: [], activityStart: Date(), totalDistanceM: 5000, totalDuration: 1800) == nil)
    }

    @Test func repsCarryPaceHRAndCumulativeDistanceFraction() throws {
        let segs = segments(reps: 5, workPace: [299, 292, 295, 287, 285], hr: [149, 151, 153, 155, 157])
        let t = total(segs)
        let b = try #require(IntervalRepBoard.make(segments: segs, activityStart: segs[0].startDate, totalDistanceM: t.m, totalDuration: t.s))
        #expect(b.reps.count == 5)
        #expect(b.reps[0].index == 1)
        #expect(b.reps[3].paceSecPerKm == 287)
        #expect(b.reps[4].avgHeartRate == 157)
        // 1회차 끝 = 준비 1000 + 운동 1000 = 2000m / 총 6800m(준비 1000 + 운동 5000 + 회복 800 + 정리 1000)
        #expect(abs(b.reps[0].revealFraction - 2000.0 / 6800.0) < 1e-9)
        // 마지막 회차 끝 = 6800 − 정리 1000 = 5800
        #expect(abs(b.reps[4].revealFraction - 5800.0 / 6800.0) < 1e-9)
        #expect(b.reps.map(\.revealFraction) == b.reps.map(\.revealFraction).sorted())
    }

    @Test func fallsBackToTimeFractionWhenAnyDistanceMissing() throws {
        var segs = segments(reps: 3)
        // 회복 구간 하나의 거리를 지운다 → 거리 누적이 불가능 → 시간 비율
        let s = segs[2]
        segs[2] = IntervalSegment(id: s.id, startDate: s.startDate, endDate: s.endDate, distanceM: nil,
                                  avgHeartRate: s.avgHeartRate, avgCadence: s.avgCadence, stepLabel: s.stepLabel)
        let t = total(segs)
        let b = try #require(IntervalRepBoard.make(segments: segs, activityStart: segs[0].startDate, totalDistanceM: 5400, totalDuration: t.s))
        let firstEnd = segs[1].endDate.timeIntervalSince(segs[0].startDate)
        #expect(abs(b.reps[0].revealFraction - firstEnd / t.s) < 1e-9)
    }

    @Test func uniformDistanceHeaderAndAverageFooter() throws {
        let segs = segments(reps: 5, workPace: [299, 292, 295, 287, 285])
        let t = total(segs)
        let b = try #require(IntervalRepBoard.make(segments: segs, activityStart: segs[0].startDate, totalDistanceM: t.m, totalDuration: t.s))
        #expect(b.uniformDistanceM == 1000)
        #expect(b.headerText == "5 × 1km")
        #expect(b.showsDistanceColumn == false)
        // 평균 (299+292+295+287+285)/5 = 291.6 → 292 → 4'52"
        #expect(b.footerText == "평균 4'52\"")
    }

    @Test func mixedDistancesShowColumnAndCountHeader() throws {
        var segs = segments(reps: 3)
        // 2회차 운동 거리를 400m로
        let i = segs.firstIndex { $0.stepLabel == "운동" }! + 2
        let s = segs[i]
        segs[i] = IntervalSegment(id: s.id, startDate: s.startDate, endDate: s.endDate, distanceM: 400,
                                  avgHeartRate: s.avgHeartRate, avgCadence: s.avgCadence, stepLabel: s.stepLabel)
        let t = total(segs)
        let b = try #require(IntervalRepBoard.make(segments: segs, activityStart: segs[0].startDate, totalDistanceM: t.m, totalDuration: t.s))
        #expect(b.uniformDistanceM == nil)
        #expect(b.showsDistanceColumn == true)
        #expect(b.headerText == "인터벌 3회")
    }

    @Test func revealedCountFollowsProgress() throws {
        let segs = segments(reps: 5)
        let t = total(segs)
        let b = try #require(IntervalRepBoard.make(segments: segs, activityStart: segs[0].startDate, totalDistanceM: t.m, totalDuration: t.s))
        #expect(b.revealedCount(progress: 0) == 0)
        #expect(b.revealedCount(progress: CGFloat(b.reps[0].revealFraction) - 0.001) == 0)
        #expect(b.revealedCount(progress: CGFloat(b.reps[0].revealFraction)) == 1)
        #expect(b.revealedCount(progress: CGFloat(b.reps[2].revealFraction) + 0.001) == 3)
        #expect(b.revealedCount(progress: 1) == 5)
    }

    @Test func slotsSingleColumnUpToTenThenPairs() throws {
        let five = segments(reps: 5); let t5 = total(five)
        let b5 = try #require(IntervalRepBoard.make(segments: five, activityStart: five[0].startDate, totalDistanceM: t5.m, totalDuration: t5.s))
        #expect(b5.columns == 1)
        #expect(b5.slotCount == 6)              // 5줄 + 바닥글
        #expect(b5.revealedSlots(revealed: 0) == 0)
        #expect(b5.revealedSlots(revealed: 3) == 3)
        #expect(b5.revealedSlots(revealed: 5) == 6)   // 마지막 회차와 함께 바닥글

        let twelve = segments(reps: 12, workM: 400); let t12 = total(twelve)
        let b12 = try #require(IntervalRepBoard.make(segments: twelve, activityStart: twelve[0].startDate, totalDistanceM: t12.m, totalDuration: t12.s))
        #expect(b12.columns == 2)
        #expect(b12.slotCount == 7)             // 6쌍 + 바닥글
        #expect(b12.revealedSlots(revealed: 1) == 1)   // 1회차만 보여도 첫 쌍의 칸은 열린다
        #expect(b12.revealedSlots(revealed: 2) == 1)
        #expect(b12.revealedSlots(revealed: 3) == 2)
        #expect(b12.revealedSlots(revealed: 12) == 7)
        #expect(b12.headerText == "12 × 400m")
    }

    @Test func dimRangesAreNonWorkSegments() throws {
        let segs = segments(reps: 2)
        let t = total(segs)
        let b = try #require(IntervalRepBoard.make(segments: segs, activityStart: segs[0].startDate, totalDistanceM: t.m, totalDuration: t.s))
        // 준비 · 회복 · 정리 = 3구간
        #expect(b.dimTimeRanges.count == 3)
        #expect(b.dimTimeRanges[0].lowerBound == 0)
        #expect(abs(b.dimTimeRanges[0].upperBound - 380) < 1e-9)
        #expect(b.isDimmed(offset: 100))     // 준비운동 중
        #expect(!b.isDimmed(offset: 500))    // 1회차 운동 중
    }
}
```

- [ ] **Step 2: 컴파일이 `IntervalRepBoard` 없음으로 깨지는 것을 확인**

Run: 빌드 확인 명령
Expected: `error: cannot find 'IntervalRepBoard' in scope` (TEST BUILD FAILED)

- [ ] **Step 3: 구현**

```swift
import Foundation
import CoreGraphics

/// 경로 영상 인터벌 회차 보드 — 운동 구간이 끝나는 지점을 지도가 지날 때 한 줄씩 나타난다.
/// 뷰(`IntervalRepBoardView`)와 출력(`RouteVideoExportService`)은 이 값만 읽는다. 운동 구간 2개 미만이면 nil.
struct IntervalRepBoard: Equatable {
    struct Rep: Equatable {
        let index: Int              // 1부터
        let distanceM: Double?
        let paceSecPerKm: Double?
        let avgHeartRate: Int?
        /// 이 회차가 끝나는 지점의 경로 진행 비율(0…1). 거리 누적이 가능하면 거리 비율, 아니면 시간 비율.
        let revealFraction: Double
    }

    let reps: [Rep]
    /// 모든 운동 구간 거리가 ±5% 안에서 같으면 대표 거리(표준 거리로 반올림), 아니면 nil.
    let uniformDistanceM: Double?
    let averagePaceSecPerKm: Double?
    /// 운동이 아닌 구간(준비·회복·정리)의 시간 범위 — 경로를 흐리게 그리는 데 쓴다. 러닝 시작 기준 초.
    let dimTimeRanges: [ClosedRange<TimeInterval>]

    /// 한 열에 넣는 최대 회차 수. 넘으면 두 열(쌍)로.
    static let maxSingleColumnRows = 10

    // MARK: - 생성

    static func make(segments: [IntervalSegment], activityStart: Date,
                     totalDistanceM: Double, totalDuration: TimeInterval) -> IntervalRepBoard? {
        let ordered = segments.sorted { $0.startDate < $1.startDate }
        let work = ordered.filter { $0.stepLabel == "운동" }
        guard work.count >= 2, totalDuration > 0 else { return nil }

        // 누적 거리 — 모든 구간에 거리가 있고 합이 양수일 때만 거리 비율을 쓴다
        let allHaveDistance = ordered.allSatisfy { ($0.distanceM ?? 0) > 0 }
        let distanceSum = ordered.compactMap(\.distanceM).reduce(0, +)
        let useDistance = allHaveDistance && distanceSum > 0
        let denominator = useDistance ? max(distanceSum, totalDistanceM) : totalDuration

        var cumulative = 0.0
        var reps: [Rep] = []
        var dims: [ClosedRange<TimeInterval>] = []
        for seg in ordered {
            let isWork = seg.stepLabel == "운동"
            let endValue: Double
            if useDistance {
                cumulative += seg.distanceM ?? 0
                endValue = cumulative
            } else {
                endValue = seg.endDate.timeIntervalSince(activityStart)
            }
            if isWork {
                reps.append(Rep(index: reps.count + 1, distanceM: seg.distanceM,
                                paceSecPerKm: seg.paceSecPerKm, avgHeartRate: seg.avgHeartRate,
                                revealFraction: min(max(endValue / denominator, 0), 1)))
            } else {
                let lo = max(0, seg.startDate.timeIntervalSince(activityStart))
                let hi = max(lo, seg.endDate.timeIntervalSince(activityStart))
                dims.append(lo...hi)
            }
        }

        let distances = work.compactMap(\.distanceM)
        var uniform: Double? = nil
        if distances.count == work.count, let lo = distances.min(), let hi = distances.max(), lo > 0, hi / lo <= 1.05 {
            uniform = Double(recognizedDistanceM(distances.reduce(0, +) / Double(distances.count)))
        }
        let paces = work.compactMap(\.paceSecPerKm)
        let avg = paces.isEmpty ? nil : paces.reduce(0, +) / Double(paces.count)
        return IntervalRepBoard(reps: reps, uniformDistanceM: uniform, averagePaceSecPerKm: avg, dimTimeRanges: dims)
    }

    /// 표준 거리(200·400·600·800·1000·1200·1600·2000·3000·5000m)에 8% 안이면 그 값, 아니면 100m(200m 미만은 50m) 단위 반올림.
    /// `ActivityDetailView.recognizedDistanceM`과 같은 규칙.
    static func recognizedDistanceM(_ d: Double) -> Int {
        let standards = [200, 400, 600, 800, 1000, 1200, 1600, 2000, 3000, 5000]
        if let snap = standards.first(where: { abs(Double($0) - d) / Double($0) <= 0.08 }) { return snap }
        return d >= 200 ? Int((d / 100).rounded()) * 100 : Int((d / 50).rounded()) * 50
    }

    // MARK: - 표시 규칙

    var columns: Int { reps.count > Self.maxSingleColumnRows ? 2 : 1 }
    /// 회차 칸 수(열이 둘이면 쌍 수) + 바닥글 1칸
    var slotCount: Int { Int(ceil(Double(reps.count) / Double(columns))) + 1 }
    /// 보인 회차 수로 열린 칸 수 — 마지막 회차가 보이면 바닥글 칸도 함께 열린다
    func revealedSlots(revealed: Int) -> Int {
        let n = min(max(revealed, 0), reps.count)
        guard n > 0 else { return 0 }
        let rowSlots = Int(ceil(Double(n) / Double(columns)))
        return n == reps.count ? rowSlots + 1 : rowSlots
    }
    var showsDistanceColumn: Bool { uniformDistanceM == nil }

    func revealedCount(progress: CGFloat) -> Int {
        let p = Double(progress)
        return reps.filter { $0.revealFraction <= p + 1e-9 }.count
    }

    func isDimmed(offset: TimeInterval) -> Bool {
        dimTimeRanges.contains { $0.contains(offset) }
    }

    // MARK: - 문장 (관찰 사실만)

    var headerText: String {
        let L = AppLanguage.shared
        if let d = uniformDistanceM {
            return "\(reps.count) × \(Self.distanceLabel(d))"
        }
        return L.s("인터벌 \(reps.count)회", "\(reps.count) intervals")
    }

    var footerText: String? {
        guard let avg = averagePaceSecPerKm else { return nil }
        let L = AppLanguage.shared
        return L.s("평균 \(Self.paceText(avg))", "avg \(Self.paceText(avg))")
    }

    static func distanceLabel(_ m: Double) -> String {
        if m >= 1000 {
            let km = m / 1000
            return km == km.rounded() ? "\(Int(km))km" : String(format: "%.1fkm", km)
        }
        return "\(Int(m.rounded()))m"
    }

    static func paceText(_ sec: Double) -> String {
        let i = Int(sec.rounded())
        return String(format: "%d'%02d\"", i / 60, i % 60)
    }
}
```

- [ ] **Step 4: 빌드 확인**

Run: 빌드 확인 명령
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
cd /Users/hns/MIMORunning/MIMORunning && git add MIMORunning/Insight/IntervalRepBoard.swift MIMORunningTests/IntervalRepBoardTests.swift && git commit -m "$(cat <<'EOF'
경로 영상 인터벌 회차 보드 — 데이터(IntervalRepBoard): 회차·나타나는 지점·머리글·바닥글·흐림 구간

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `IntervalRepBoardView` — 보드 뷰 하나

**Files:**
- Create: `MIMORunning/Views/IntervalRepBoardView.swift`

- [ ] **Step 1: 뷰 작성**

글자 크기·간격은 폼 카드 인터벌 표(`IntervalFatigueCard` 1063~1090)와 같은 기준값: 머리글 9pt·흰색 0.38, 행 10pt·흰색 0.82, 행 상하 패딩 2(표는 3이지만 영상은 세이프존이 좁아 2). 모두 `× scale`.

```swift
import SwiftUI

/// 경로 영상 인터벌 회차 보드 — 미리보기·출력이 **이 뷰 하나**를 쓴다(§5.8).
/// `revealed`: 보이는 회차 수(0…reps.count). 보이지 않는 줄은 투명(opacity 0)으로 자리를 지킨다 —
/// 줄이 나타나도 레이아웃이 움직이지 않고, 출력에서 "뼈대만"과 "줄만" 두 렌더가 같은 위치를 갖는다.
/// `renderMode`: `.full`(미리보기) / `.chromeOnly`(머리글·배경만, 줄은 투명) / `.rowsOnly`(줄만, 나머지 투명).
struct IntervalRepBoardView: View {
    enum RenderMode { case full, chromeOnly, rowsOnly }

    let board: IntervalRepBoard
    var revealed: Int
    var renderMode: RenderMode = .full
    var scale: CGFloat = 1.0

    private var L: AppLanguage { AppLanguage.shared }

    // 열 폭(scale=1): 회차 22 · 거리 40 · 페이스 44 · 심박 30
    private var idxW: CGFloat { 22 * scale }
    private var distW: CGFloat { 40 * scale }
    private var paceW: CGFloat { 44 * scale }
    private var hrW: CGFloat { 30 * scale }
    private var colGap: CGFloat { 10 * scale }

    private var chromeOpacity: Double { renderMode == .rowsOnly ? 0 : 1 }
    private func rowOpacity(_ rep: IntervalRepBoard.Rep) -> Double {
        switch renderMode {
        case .chromeOnly: return 0
        case .rowsOnly:   return 1          // 출력은 마스크로 드러내므로 전부 그린다
        case .full:       return rep.index <= revealed ? 1 : 0
        }
    }
    private var footerOpacity: Double {
        switch renderMode {
        case .chromeOnly: return 0
        case .rowsOnly:   return 1
        case .full:       return revealed >= board.reps.count ? 1 : 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 머리글: "5 × 1km"
            Text(board.headerText)
                .font(.system(size: 9 * scale, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.bottom, 3 * scale)
                .opacity(chromeOpacity)

            // 회차 줄 — 열 하나 또는 쌍
            let pairs = stride(from: 0, to: board.reps.count, by: board.columns).map { i in
                Array(board.reps[i..<min(i + board.columns, board.reps.count)])
            }
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, group in
                HStack(spacing: colGap) {
                    ForEach(group, id: \.index) { rep in
                        row(rep).opacity(rowOpacity(rep))
                    }
                }
                .padding(.vertical, 2 * scale)
            }

            // 바닥글: "평균 4'52"" — 마지막 회차와 함께
            if let footer = board.footerText {
                Text(footer)
                    .font(.system(size: 10 * scale, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.positive)
                    .padding(.vertical, 2 * scale)
                    .opacity(footerOpacity)
            }
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 6 * scale)
        .background(
            RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .opacity(chromeOpacity)
        )
        .fixedSize()
    }

    @ViewBuilder
    private func row(_ rep: IntervalRepBoard.Rep) -> some View {
        HStack(spacing: 0) {
            Text("\(rep.index)")
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: idxW, alignment: .leading)
            if board.showsDistanceColumn {
                Text(rep.distanceM.map { IntervalRepBoard.distanceLabel($0) } ?? "–")
                    .foregroundStyle(Color.white.opacity(0.82))
                    .frame(width: distW, alignment: .leading)
            }
            Text(rep.paceSecPerKm.map { IntervalRepBoard.paceText($0) } ?? "–")
                .foregroundStyle(Color.white)
                .frame(width: paceW, alignment: .leading)
            Text(rep.avgHeartRate.map { "\($0)" } ?? "–")
                .foregroundStyle(Theme.heartRate)
                .frame(width: hrW, alignment: .trailing)
        }
        .font(.system(size: 10 * scale, weight: .medium).monospacedDigit())
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: 빌드 확인 명령
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
cd /Users/hns/MIMORunning/MIMORunning && git add MIMORunning/Views/IntervalRepBoardView.swift && git commit -m "$(cat <<'EOF'
경로 영상 인터벌 회차 보드 — 뷰 하나(IntervalRepBoardView): revealed·renderMode·scale

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `VideoOverlayCard`·`RouteVideoFrameView`에 보드 넣기 (미리보기)

**Files:**
- Modify: `MIMORunning/Views/VideoOverlayCard.swift` (파라미터 + 차트 패널 자리)
- Modify: `MIMORunning/Views/RouteVideoService.swift` `RouteVideoFrameView` (8~86행)

- [ ] **Step 1: VideoOverlayCard 파라미터 추가**

`var summaryLines: [RunSummaryLine] = []` 바로 아래에:

```swift
    /// 인터벌 회차 보드 — 있으면 차트 패널 자리에 대신 놓인다(총평이 켜지면 총평이 우선). §5.8: 미리보기·출력 같은 뷰.
    var intervalBoard: IntervalRepBoard? = nil
    var intervalRevealed: Int = 0
    var intervalBoardRenderMode: IntervalRepBoardView.RenderMode = .full
    /// true면 보드 줄 이외의 모든 요소(로고·총평·차트·날짜·구분선·지표·하단 스크림)를 투명하게 — 출력이 "줄만" 이미지를 얻을 때 쓴다.
    /// 레이아웃은 그대로라(opacity만) 뼈대 렌더와 줄 렌더의 위치가 같다.
    var chromeHidden: Bool = false
```
(선언 순서가 곧 memberwise init의 인자 순서다: `summaryLines` → `intervalBoard` → `intervalRevealed` → `intervalBoardRenderMode` → `chromeHidden` → `scale` → `topInset` → `bottomInset`. 호출부는 모두 이 순서로 넘긴다.)

- [ ] **Step 2: 차트 패널 블록을 보드 우선으로**

기존:
```swift
                // ── MIDDLE: chart (right-aligned) — 총평이 켜지면 숨김(§5.8) ──
                if summaryLines.isEmpty, chartPanel != .map {
```
를 다음으로 바꾼다(보드 블록을 앞에 두고, 기존 차트 블록의 조건에 `intervalBoard == nil`을 더한다):
```swift
                // ── MIDDLE: 인터벌 회차 보드 (right-aligned) — 총평이 켜지면 숨김 ──
                if summaryLines.isEmpty, let board = intervalBoard {
                    HStack {
                        Spacer()
                        IntervalRepBoardView(board: board, revealed: intervalRevealed,
                                             renderMode: intervalBoardRenderMode, scale: scale)
                    }
                    .padding(.horizontal, 20 * scale)
                    .padding(.bottom, 8 * scale)
                    .cardTextShadow()
                }

                // ── MIDDLE: chart (right-aligned) — 총평이 켜지거나 보드가 있으면 숨김(§5.8) ──
                if summaryLines.isEmpty, intervalBoard == nil, chartPanel != .map {
```

**`chromeHidden` 적용:** 보드 블록은 `VStack` 안에 그대로 두고(별도 형제로 빼면 레이아웃이 달라진다), **나머지 요소 각각**에 `.opacity(chromeHidden ? 0 : 1)`를 붙인다: 상단 워드마크 `HStack`, 총평 `RunSummaryLinesView`, 차트 블록 `HStack`, 하단 날짜 `HStack`, 구분선 `Rectangle`, 지표 `HStack`, 그리고 `ZStack`의 `CardVisual.bottomScrim`. 보드 블록 자체는 `renderMode`(`.rowsOnly`면 머리글·배경 투명, 줄만 그림)가 처리한다.

- [ ] **Step 3: RouteVideoFrameView에 전달**

`var summaryLines: [RunSummaryLine] = []` 아래에:
```swift
    /// 인터벌 회차 보드 — 진행률에서 보인 회차 수를 계산해 VideoOverlayCard에 넘긴다
    var intervalBoard: IntervalRepBoard? = nil
```
`VideoOverlayCard(` 호출에 `summaryLines: summaryLines,` 다음 줄로:
```swift
                        intervalBoard: intervalBoard,
                        intervalRevealed: intervalBoard?.revealedCount(progress: routeProgress) ?? 0,
```

- [ ] **Step 4: 빌드 확인**

Run: 빌드 확인 명령
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
cd /Users/hns/MIMORunning/MIMORunning && git add MIMORunning/Views/VideoOverlayCard.swift MIMORunning/Views/RouteVideoService.swift && git commit -m "$(cat <<'EOF'
경로 영상 인터벌 회차 보드 — VideoOverlayCard·RouteVideoFrameView에 보드(차트 패널 자리, 진행률로 회차 드러남)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: 경로 흐리게 + km 점 숨김 (미리보기 Canvas + 출력 레이어)

**Files:**
- Modify: `MIMORunning/Views/RouteVideoService.swift` — `RouteVideoFrameView`, `RoutePolylineOverlay`, `exportFast`, `exportWithCAShapeLayer`

- [ ] **Step 1: RoutePolylineOverlay에 흐림·km 점 파라미터**

`var showHRGradient: Bool = false` 아래에:
```swift
    /// 운동이 아닌 구간(준비·회복·정리)의 시간 범위 — 인터벌 영상에서 그 구간을 흐리게 그린다. 비어 있으면 기존 그대로.
    var dimTimeRanges: [ClosedRange<TimeInterval>] = []
    /// 인터벌 영상은 km 점을 숨긴다 — 회차가 곧 구간이라 트랙 위에서 겹친다
    var showKmDots: Bool = true
```
`==`에 `&& a.dimTimeRanges == b.dimTimeRanges && a.showKmDots == b.showKmDots` 추가.

Canvas 본문에서 그라데이션 분기 조건을 바꾼다. 기존 `if showHRGradient && slice.count > 1 && !hrSamples.isEmpty && !zoneBounds.isEmpty {` 앞에 다음을 두고, 미세 구간 그리기를 두 경우가 공유하도록 색 배열만 다르게 만든다:

```swift
            let dimAlpha: Double = 0.35
            func dimFactor(_ i: Int) -> Double {
                guard !dimTimeRanges.isEmpty else { return 1 }
                let offset = Double(i) / Double(max(pts.count - 1, 1)) * workoutDuration
                return dimTimeRanges.contains { $0.contains(offset) } ? dimAlpha : 1
            }
            let useMicroSegments = slice.count > 1 &&
                ((showHRGradient && !hrSamples.isEmpty && !zoneBounds.isEmpty) || !dimTimeRanges.isEmpty)

            if useMicroSegments {
                let useGradient = showHRGradient && !hrSamples.isEmpty && !zoneBounds.isEmpty
                let sortedBounds = zoneBounds.sorted { $0.minBPM < $1.minBPM }
                let lookup = HRLookup(samples: hrSamples)
                let segColors: [Color] = (0..<(slice.count - 1)).map { i in
                    let offset = Double(i) / Double(max(pts.count - 1, 1)) * workoutDuration
                    return useGradient ? canvasGradientColor(bpm: lookup.bpm(at: offset), sorted: sortedBounds) : Theme.violet
                }
                for i in 0..<(slice.count - 1) {
                    var seg = Path(); seg.move(to: slice[i]); seg.addLine(to: slice[i+1])
                    ctx.stroke(seg, with: .color(segColors[i].opacity(0.35 * dimFactor(i))),
                               style: StrokeStyle(lineWidth: 7, lineCap: .round))
                }
                for i in 0..<(slice.count - 1) {
                    var seg = Path(); seg.move(to: slice[i]); seg.addLine(to: slice[i+1])
                    ctx.stroke(seg, with: .color(segColors[i].opacity(dimFactor(i))),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            } else {
                // 단색 모드(기존 그대로)
```
기존 `else` 분기(단색 `path`)는 그대로 둔다. `// KM marker dots in preview` 블록의 조건을 `if showKmDots, totalDistanceM > 100, pts.count > 1 {`로 바꾼다.

- [ ] **Step 2: RouteVideoFrameView가 넘겨주기**

`RouteVideoFrameView`의 `RoutePolylineOverlay(` 호출에 추가:
```swift
                                     dimTimeRanges: intervalBoard?.dimTimeRanges ?? [],
                                     showKmDots: intervalBoard == nil
```
(`RouteVideoFrameView`는 Task 3에서 `intervalBoard`를 받았다. `totalDistanceM`은 지금 미리보기 호출부에서 넘기지 않아 km 점 자체가 안 보이는 경우가 있는데 그 동작은 건드리지 않는다.)

- [ ] **Step 3: 출력 — exportWithCAShapeLayer에 흐림 파라미터**

시그니처 `showKmMarkers: Bool = true,` 아래에 `dimTimeRanges: [ClosedRange<TimeInterval>] = [],` 추가.

`let useGradient = showHRGradient && hrSamples.count >= 10` 를 다음으로 바꾼다:
```swift
            let hasGradient = showHRGradient && hrSamples.count >= 10
            // 흐림 구간이 있으면 단색이라도 미세 구간으로 그린다 — 구간마다 알파를 다르게 줄 수 있는 유일한 길
            let useGradient = hasGradient || !dimTimeRanges.isEmpty
            let dimAlpha: CGFloat = 0.35
            func dimFactor(_ midOffset: Double) -> CGFloat {
                dimTimeRanges.contains { $0.contains(midOffset) } ? dimAlpha : 1
            }
```
글로우 패스와 코어 패스의 색 결정 두 곳을 각각:
```swift
                    let color = hasGradient ? gradientUIColorForVideo(bpm: bpm, bounds: sortedBounds) : UIColor(Theme.violet)
```
로 바꾸고(`bpm` 계산은 그대로 두어도 되지만 `hasGradient`가 거짓이면 쓰이지 않는다), 알파를:
- 글로우: `layer.strokeColor = color.withAlphaComponent(0.35 * dimFactor(midOffset)).cgColor`
- 코어: `layer.strokeColor = color.withAlphaComponent(dimFactor(midOffset)).cgColor`

`sortedBounds` 계산은 `hasGradient`일 때만 의미가 있으니 `let sortedBounds = hasGradient ? computeZoneBoundsStatic(from: hrSamples) : []`로 바꾼다. 팁 애니메이션의 `if useGradient` 분기는 그대로(미세 구간 모드면 `gradientTipAnimation`).

- [ ] **Step 4: exportFast 시그니처에 노출**

`stampLayers: [StampLayerConfig] = [],` 아래에:
```swift
        intervalBoard: IntervalRepBoard? = nil,
```
`exportFast` 안의 `exportWithCAShapeLayer(` 호출에서 `miniMeImage: routeMarkerImage,` **바로 다음, `stampLayers: stampLayers,` 앞**에(시그니처 순서와 같다):
```swift
            showKmMarkers: intervalBoard == nil,
            dimTimeRanges: intervalBoard?.dimTimeRanges ?? [],
```
(`exportBigNumberFast`의 호출은 `showKmMarkers: false`가 이미 있으니 건드리지 않는다.)

- [ ] **Step 5: 빌드 확인**

Run: 빌드 확인 명령
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 6: 커밋**

```bash
cd /Users/hns/MIMORunning/MIMORunning && git add MIMORunning/Views/RouteVideoService.swift && git commit -m "$(cat <<'EOF'
경로 영상 인터벌 — 운동이 아닌 구간 경로 흐리게(알파 0.35) · km 점/마커 숨김 (미리보기 Canvas·출력 레이어 같은 규칙)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: 출력 — 줄 이미지 마스크로 회차 드러내기

**Files:**
- Create: `MIMORunning/Views/CGImageAlphaBounds.swift`
- Test: `MIMORunningTests/CGImageAlphaBoundsTests.swift`
- Modify: `MIMORunning/Views/RouteVideoService.swift` — `exportFast`, `exportWithCAShapeLayer`, 새 `makeIntervalBoardRowsLayer`

- [ ] **Step 1: 알파 경계 테스트**

```swift
import XCTest
import CoreGraphics
@testable import MIMORunning

final class CGImageAlphaBoundsTests: XCTestCase {
    private func image(size: CGSize, rect: CGRect?) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(origin: .zero, size: size))
        if let r = rect {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            // CGContext는 y=0이 아래 — 테스트는 UIKit 좌표(y=0 위)로 검사하므로 뒤집어 그린다
            ctx.fill(CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height))
        }
        return ctx.makeImage()!
    }

    func testFindsOpaqueRectInTopLeftCoordinates() throws {
        let img = image(size: CGSize(width: 100, height: 200), rect: CGRect(x: 30, y: 120, width: 40, height: 50))
        let box = try XCTUnwrap(img.alphaBoundingBox())
        XCTAssertEqual(box.minX, 30, accuracy: 1)
        XCTAssertEqual(box.minY, 120, accuracy: 1)
        XCTAssertEqual(box.width, 40, accuracy: 1)
        XCTAssertEqual(box.height, 50, accuracy: 1)
    }

    func testFullyTransparentReturnsNil() {
        XCTAssertNil(image(size: CGSize(width: 20, height: 20), rect: nil).alphaBoundingBox())
    }
}
```

- [ ] **Step 2: 컴파일이 `alphaBoundingBox` 없음으로 깨지는 것을 확인**

Run: 빌드 확인 명령
Expected: `error: value of type 'CGImage' has no member 'alphaBoundingBox'`

- [ ] **Step 3: 구현**

```swift
import CoreGraphics
import Foundation

extension CGImage {
    /// 알파가 있는 픽셀들의 경계 상자 — **UIKit 좌표(y=0 위)**, 픽셀 단위. 전부 투명이면 nil.
    /// 경로 영상 출력이 "줄만 그린" 오버레이에서 회차 보드의 줄 영역을 찾는 데 쓴다(레이아웃 좌표를 SwiftUI에서 꺼내지 않고).
    func alphaBoundingBox(threshold: UInt8 = 8) -> CGRect? {
        let w = width, h = height
        guard w > 0, h > 0 else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { return nil }
        let data = raw.assumingMemoryBound(to: UInt8.self)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let rowBase = y * w * 4
            for x in 0..<w where data[rowBase + x * 4 + 3] > threshold {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        // CGContext.draw는 y=0이 아래 — UIKit 좌표로 뒤집는다
        let topY = h - 1 - maxY
        return CGRect(x: minX, y: topY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
```

- [ ] **Step 4: 빌드 확인**

Run: 빌드 확인 명령
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: exportFast — 오버레이를 두 번 그린다**

`exportFast` 안 `let overlayCGImage: CGImage?` 블록에서, `VideoOverlayCard(` 생성부를 함수로 뽑아 `renderMode`·`chromeHidden`을 받게 한다:

```swift
        func renderOverlay(boardMode: IntervalRepBoardView.RenderMode, chromeHidden: Bool) throws -> CGImage {
            let exportInset = renderSize.height * 0.05
            let view = VideoOverlayCard(
                distanceKm: distanceKm, date: date,
                metrics: metrics, raceName: raceName,
                chartPanel: chartPanel, chartSplits: chartSplits,
                chartHRSamples: chartHRSamples, chartHRZones: chartHRZones,
                chartWorkoutSeries: chartWorkoutSeries, chartIntervalSegments: chartIntervalSegments,
                weather: weather, shoeName: shoeName,
                summaryLines: summaryLines,
                intervalBoard: intervalBoard,
                intervalRevealed: 0,
                intervalBoardRenderMode: boardMode,
                chromeHidden: chromeHidden,
                scale: renderSize.width / 300,
                topInset: exportInset,
                bottomInset: previewMatchedBottomInset
            )
            .frame(width: renderSize.width, height: renderSize.height)
            .preferredColorScheme(.dark)
            let r = ImageRenderer(content: view)
            r.scale = renderScale
            guard let img = r.uiImage?.cgImage else { throw NSError(domain: "RouteVideoExport", code: -2) }
            return img
        }

        let overlayCGImage: CGImage?
        var boardRowsCGImage: CGImage? = nil
        if stampLayers.isEmpty {
            // 보드가 있으면 뼈대(머리글·배경·나머지 카드)와 줄을 따로 그린다 — 줄은 마스크로 시간에 맞춰 드러낸다
            overlayCGImage = try renderOverlay(boardMode: intervalBoard == nil ? .full : .chromeOnly, chromeHidden: false)
            if intervalBoard != nil {
                boardRowsCGImage = try renderOverlay(boardMode: .rowsOnly, chromeHidden: true)
            }
        } else {
            overlayCGImage = nil
        }
```
(`VideoOverlayCard`의 `chromeHidden`·`intervalBoardRenderMode` 파라미터 순서는 Task 3에서 정한 선언 순서를 따른다 — 선언 순서: `summaryLines`, `intervalBoard`, `intervalRevealed`, `intervalBoardRenderMode`, `chromeHidden`, `scale`, `topInset`, `bottomInset`.)

시그니처에 `boardRows: (image: CGImage, board: IntervalRepBoard)? = nil,` 를 `dimTimeRanges` 바로 아래(`stampLayers` 위)에 추가하고, 호출에는 `dimTimeRanges:` 다음 줄에 `boardRows: boardRowsCGImage.map { (image: $0, board: intervalBoard!) },` 를 넣는다(`intervalBoard`가 nil이면 `boardRowsCGImage`도 nil이라 강제 언래핑이 실행되지 않는다).

- [ ] **Step 6: 마스크 레이어 — 오버레이 정적 레이어 바로 뒤에**

`// Overlay layer: static, on top of everything` 블록 다음, `// Stamp animated layers` 앞에:

```swift
        // 인터벌 회차 보드 줄 — 줄만 그린 이미지를 위에서부터 마스크로 드러낸다.
        // 줄 높이가 같으므로 마스크 높이 = 줄 영역 높이 × (열린 칸 수 / 전체 칸 수). 시간 키는 km 마커와 같은 방식.
        if let rows = boardRows, let bbox = rows.image.alphaBoundingBox() {
            parentLayer.addSublayer(makeIntervalBoardRowsLayer(
                rowsImage: rows.image, board: rows.board, rowsBox: bbox,
                pixelSize: px, routeDuration: routeDur, videoDuration: vidDur))
        }
```

새 함수(`// MARK: - Marker layer factory` 앞에):

```swift
    // MARK: - Interval board rows layer

    /// 줄만 그린 오버레이 이미지(전체 프레임 크기, 줄 밖은 투명)를 마스크로 위에서부터 드러낸다.
    /// `rowsBox`는 줄 영역(UIKit 좌표, 픽셀). 마스크는 그 영역의 x·폭을 그대로 쓰고 높이만 칸 수에 비례해 키운다.
    private static func makeIntervalBoardRowsLayer(
        rowsImage: CGImage, board: IntervalRepBoard, rowsBox: CGRect,
        pixelSize: CGSize, routeDuration: Double, videoDuration: Double
    ) -> CALayer {
        let rowsLayer = CALayer()
        rowsLayer.frame = CGRect(origin: .zero, size: pixelSize)
        rowsLayer.contents = rowsImage

        // 마스크: 검정 사각형, 위쪽 모서리 고정(anchorPoint 0,0) — 높이만 자란다. 좌표는 km 마커와 같은 UIKit 규약.
        let mask = CALayer()
        mask.backgroundColor = UIColor.black.cgColor
        mask.anchorPoint = CGPoint(x: 0, y: 0)
        let pad: CGFloat = 2   // 글리프 안티에일리어싱 여유
        mask.position = CGPoint(x: rowsBox.minX - pad, y: rowsBox.minY - pad)
        mask.bounds = CGRect(x: 0, y: 0, width: rowsBox.width + pad * 2, height: 0)
        rowsLayer.mask = mask

        // 키프레임: 각 회차가 끝나는 시점에 칸 수만큼 높이를 점프(discrete). 마지막 회차엔 바닥글 칸까지.
        let slotH = (rowsBox.height + pad * 2) / CGFloat(board.slotCount)
        var times: [NSNumber] = [0]
        var values: [NSValue] = [NSValue(cgRect: CGRect(x: 0, y: 0, width: rowsBox.width + pad * 2, height: 0))]
        for rep in board.reps {
            let t = min(rep.revealFraction * routeDuration / videoDuration, 1.0)
            let slots = board.revealedSlots(revealed: rep.index)
            times.append(NSNumber(value: t))
            values.append(NSValue(cgRect: CGRect(x: 0, y: 0, width: rowsBox.width + pad * 2, height: slotH * CGFloat(slots))))
        }
        let anim = CAKeyframeAnimation(keyPath: "bounds")
        anim.values = values
        anim.keyTimes = times
        anim.calculationMode = .discrete
        anim.duration = videoDuration
        anim.beginTime = AVCoreAnimationBeginTimeAtZero
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        mask.add(anim, forKey: "bounds")
        return rowsLayer
    }
```

**주의(좌표):** 오버레이 정적 레이어는 `frame = parentLayer.frame`, `contents = cg`로 전체를 덮으며 이미지의 위가 화면 위에 온다(기존 동작). `rowsLayer`도 같은 방식이므로 `rowsImage`의 픽셀 좌표(UIKit, y=0 위)가 그대로 레이어 좌표다. 따라서 `alphaBoundingBox()`가 준 UIKit 좌표를 마스크 `position`에 그대로 쓴다. 만약 실기기 출력에서 줄이 위아래 뒤집혀 드러나면(맨 아래 줄부터 나타남) `mask.position.y`를 `pixelSize.height - rowsBox.maxY - pad`로 바꾸는 것이 유일한 수정 지점이다 — 계획서에 이 사실을 남긴다.

- [ ] **Step 7: 빌드 확인**

Run: 빌드 확인 명령
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 8: 커밋**

```bash
cd /Users/hns/MIMORunning/MIMORunning && git add MIMORunning/Views/CGImageAlphaBounds.swift MIMORunningTests/CGImageAlphaBoundsTests.swift MIMORunning/Views/RouteVideoService.swift MIMORunning/Views/VideoOverlayCard.swift && git commit -m "$(cat <<'EOF'
경로 영상 인터벌 회차 보드 — 출력: 오버레이를 뼈대/줄 두 번 그려 줄 이미지를 마스크 높이 키프레임으로 회차마다 드러냄

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: ShareCardView 연결 — 인터벌 게이트

**Files:**
- Modify: `MIMORunning/Views/ShareCardView.swift` — `RouteVideoFrameView` 호출 두 곳(≈947 스탬프 모드, ≈3572 일반), `exportFast` 호출(≈5188)

- [ ] **Step 1: 보드 계산 프로퍼티**

`private var showHRGradientForRoute: Bool {` 위에:
```swift
    /// 경로 영상 인터벌 회차 보드 — 운동 구간 2개 이상일 때만(그 외 nil → 기존 차트 패널·km 점·경로 색 그대로)
    private var intervalRepBoard: IntervalRepBoard? {
        IntervalRepBoard.make(segments: detail?.intervalSegments ?? [],
                              activityStart: activity.date,
                              totalDistanceM: activity.distance,
                              totalDuration: activity.duration)
    }
```

- [ ] **Step 2: 일반 미리보기(≈3572)에 전달**

`summaryLines: cardSummaryLines,` 다음 줄에 `intervalBoard: intervalRepBoard,` 추가.

- [ ] **Step 3: 스탬프 모드 미리보기(≈947)에도 흐림·km 점만**

이 호출은 `showStats: false`라 보드는 그리지 않지만 경로 흐림과 km 점 숨김은 출력과 같아야 한다. `showHRGradient: showHRGradientForRoute,` 다음에 `intervalBoard: intervalRepBoard,` 추가(`RouteVideoFrameView`가 `showStats == false`면 오버레이 카드를 만들지 않으므로 보드는 자연히 나오지 않고, 폴리라인 파라미터만 전달된다).

- [ ] **Step 4: 출력에 전달**

`exportFast(` 호출의 `stampLayers: exportStampLayers,` 다음에 `intervalBoard: intervalRepBoard,` 추가.

- [ ] **Step 5: 빌드 확인**

Run: 빌드 확인 명령
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 6: 실기기 빌드·설치 (컨트롤러가 수행)**

```bash
cd /Users/hns/MIMORunning/MIMORunning && xcodebuild -scheme MIMORunning -destination 'id=00008130-0004701E2246001C' -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" && xcrun devicectl device install app --device 00008130-0004701E2246001C /Users/hns/Library/Developer/Xcode/DerivedData/MIMORunning-fipaxmfmrgfgryfvkdkgeusqapeq/Build/Products/Debug-iphoneos/MIMORunning.app 2>&1 | grep -iE "installed|error"
```

- [ ] **Step 7: 커밋**

```bash
cd /Users/hns/MIMORunning/MIMORunning && git add MIMORunning/Views/ShareCardView.swift && git commit -m "$(cat <<'EOF'
경로 영상 인터벌 회차 보드 — ShareCardView 연결(운동 구간 2개 이상일 때만 미리보기·출력에 보드·흐림·km 점 숨김)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

## 실기기 확인 포인트 (사용자)

1. 오늘(9/21) 인터벌 기록 → 카드 만들기 → 경로 영상 템플릿. 미리보기 재생 시 오른쪽 아래 보드에 "5 × 1km" 머리글이 먼저 있고, 머리가 각 운동 구간 끝을 지날 때 "1  4'59"  149" 줄이 하나씩 나타나며, 마지막 줄과 함께 "평균 4'52""가 붙는지.
2. 준비·회복·정리 구간의 경로가 흐리고 운동 구간만 진하게 그려지는지. km 점이 없는지.
3. 내보낸 영상(15초)에서 줄이 미리보기와 같은 순서·같은 위치로 나타나는지. **줄이 아래에서부터 나타나면** Task 5 Step 6의 좌표 주의 사항대로 `mask.position.y` 한 줄만 고친다.
4. 인터벌이 아닌 기록(어제 일반 러닝)의 경로 영상이 전과 똑같은지(차트 패널·km 점·경로 색).

## 후속(이번 범위 밖)

- 트랙에서 "지금 뛰는 회차만 밝게, 지난 바퀴는 흐리게" — 겹쳐 그려지는 타원의 가독성. 미세 구간 알파를 시간이 지나면 낮추는 방식이 필요해 별도 작업.
- 정지 공유 카드(애슬레틱 등)에도 보드를 `revealed = 전체`로 두는 것 — 요청 없음.
