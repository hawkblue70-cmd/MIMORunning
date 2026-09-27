# 대회 해마다 비교 A단계(결과 비교) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 대회로 확정된 러닝의 상세 화면에서, 같은 대회의 지난해와 같은 거리의 지난 대회 기록을 비교해 인사이트 카드 부연 줄과 대회 탭 표로 보여 준다.

**Architecture:** 대회 DB(RaceDetector.swift 안 CSV)에 `series` 칸을 두고 개발용 파이썬 스크립트로 채운다. `RaceDetector`가 확정 매칭 → DB 줄 → 시리즈를 찾고, 같은 시리즈 지난 해 대회에 해당하는 러닝을 판정한다(저장은 호출자). 비교 규칙·문장은 순수 로직 `RaceYearOverYear`에 두고 Swift Testing으로 검증한다. 활동 상세 화면이 이것들을 엮어 인사이트 카드와 대회 탭에 넘긴다.

**Tech Stack:** Swift 5 모드(앱 타깃 기본 격리 MainActor) · SwiftUI · Swift Testing · Python 3(개발 도구) · Xcode 26(폴더 동기화 그룹 — 새 Swift 파일은 프로젝트 파일 수정 없이 포함)

**설계 문서:** `docs/superpowers/specs/2026-09-27-race-year-over-year-design.md`

---

## 작업 전 필독 규칙 (이 저장소 전용)

- **시뮬레이터를 켜지 않는다. 테스트도 실행하지 않는다.** 검증은 컴파일까지다. TDD 단계는 "테스트를 먼저 쓰고 컴파일이 기대한 대로 깨지는 것을 본다 → 구현 → 컴파일 성공"이다. 테스트 실행은 사용자가 요청할 때만. 테스트는 실행하지 않으므로 **모든 기대값을 손으로 추적**해 보고한다.
- 컴파일 명령(약 70초, 저장소 루트 `/Users/hns/MIMORunning/MIMORunning`에서):

```bash
xcodebuild build-for-testing -project MIMORunning.xcodeproj -scheme MIMORunning -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|\*\* TEST BUILD" | head -20
```

  성공: `** TEST BUILD SUCCEEDED **`. 서브에이전트는 `-derivedDataPath <전용 경로>`를 붙인다.
- **같은 브랜치(crew)에 다른 세션이 동시에 커밋한다.** `git add -A`, `git add .`, `git stash` 금지. 고친 파일 경로만 명시해 커밋하고 `git show --stat HEAD`로 확인한다. 작업 트리의 `MIMORunning.xcodeproj/project.pbxproj` 변경은 다른 작업이다 — 건드리지 않는다. 고칠 파일에 남의 미커밋 변경이 있으면 멈추고 보고한다.
- 커밋 메시지는 한국어, 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- 문자열은 `AppLanguage.shared.s("한국어", "English")`로 한/영을 함께 쓴다.
- 대회 판정 게이트는 `Calendar.current`를 쓴다. 대회 관련 테스트는 기존 `RaceDetectorGateTests`처럼 **로컬 시간대 기준**으로 날짜를 만든다(개발 기기는 KST).

## 설계와 달라진 점(설계 문서에도 반영)

1. **시리즈 칸은 모든 줄에 채운다.** 규칙 키를 모든 대회에 넣으면 새 연도 대회가 들어올 때 이름이 같으면 자동으로 이어진다. 이름이 바뀐 대회만 수동 지정 파일로 고친다.
2. **부연 줄 비교 문장은 인사이트 엔진이 아니라 화면에서 만든다.** 인사이트 결과는 디스크에 캐시되므로, 과거 대회를 나중에 확정하면 문장이 낡는다. 활동 상세 화면이 비교 결과를 계산해 인사이트 카드의 부연 줄만 바꿔 보여 준다(테마가 `.raceDay`일 때만). 공유 카드는 제목만 쓰므로 영향이 없다.
3. **같은 해에 두 번 열리는 대회**(예: 한강 서울 하프 1월·8월)는 "작년" 대신 "지난 ○○" 문장을 쓴다.
4. **과거 러닝 확인 질문 문구**는 어느 러닝을 묻는지 드러나게 날짜를 넣는다: `2025 춘천마라톤 — 10월 25일 러닝이 이 대회였나요? [맞아요] [아니요]`.

## 파일 구조

| 파일 | 상태 | 책임 |
|---|---|---|
| `tools/race_series.py` | 새로 | 대회 DB CSV에 `series` 칸을 채우는 개발 도구(규칙 + 수동 지정), 사람이 볼 후보 쌍 출력 |
| `tools/race_series_overrides.tsv` | 새로 | 이름이 바뀐 대회의 시리즈 수동 지정(이름 → 키) |
| `MIMORunning/Health/RaceDetector.swift` | 수정 | CSV `series` 칸·`BundledRace.series`, 매칭 → DB 줄·시리즈, 지난 해 후보 찾기, 테스트 훅 |
| `MIMORunning/Insight/RaceYearOverYear.swift` | 새로 | 비교 대상 선택·차이·문장·표 행(순수 로직) |
| `MIMORunningTests/RaceSeriesCSVTests.swift` | 새로 | 번들 DB 시리즈 무결성 |
| `MIMORunningTests/RacePastYearTests.swift` | 새로 | 매칭 → 시리즈, 지난 해 후보 판정 |
| `MIMORunningTests/RaceYearOverYearTests.swift` | 새로 | 비교 규칙·문장 |
| `MIMORunning/Views/RunInsightCardView.swift` | 수정 | `RunInsightSection`이 비교 데이터를 넘김 |
| `MIMORunning/Views/RunInsightTabCard.swift` | 수정 | 대회 탭 비교 섹션(기존 "같은 거리 대회 비교" 교체), 내보내기 시트 전달 |
| `MIMORunning/Views/ActivityDetailView.swift` | 수정 | 비교 계산·지난 해 찾기 실행·질문 응답, 인사이트 카드 부연 줄·깃발 줄 |

---

### Task 1: 대회 DB 시리즈 칸

**Files:**
- Create: `tools/race_series.py`, `tools/race_series_overrides.tsv`
- Modify: `MIMORunning/Health/RaceDetector.swift` (`BundledRace`, `loadRacesFromCSV`, 끝의 CSV 문자열 — 스크립트가 고침)
- Test: `MIMORunningTests/RaceSeriesCSVTests.swift`

- [ ] **Step 1: 테스트 먼저 작성**

`MIMORunningTests/RaceSeriesCSVTests.swift`:

```swift
import Testing
import Foundation
@testable import MIMORunning

/// 번들 대회 DB의 시리즈 칸 — 같은 대회를 해마다 묶는 키(tools/race_series.py가 채움).
@Suite("대회 시리즈 칸")
struct RaceSeriesCSVTests {

    private var races: [BundledRace] {
        let d = RaceDetector()
        d.loadRacesForTesting()
        return d.races
    }

    private func series(_ name: String) -> String? {
        races.first { $0.name == name }?.series
    }

    @Test func everyRaceHasSeries() {
        #expect(races.allSatisfy { !($0.series ?? "").isEmpty })
    }

    @Test func chuncheonMarathonAcrossYears() {
        let s = series("제45회 조선일보 춘천마라톤")
        #expect(s != nil)
        #expect(series("제46회 조선일보 춘천마라톤") == s)
        #expect(series("2026 춘천마라톤") == s)
        #expect(series("2026 춘천봄내마라톤") != s)
    }

    @Test func renamedRacesJoinedByOverride() {
        #expect(series("2025 JTBC 서울마라톤") == series("2026 JTBC 마라톤"))
        #expect(series("2025 서울마라톤 (제95회 동아마라톤)") == series("2027 서울마라톤"))
        #expect(series("2025 서울마라톤 (제95회 동아마라톤)") == series("2026 서울마라톤 (제96회 동아마라톤)"))
    }

    @Test func ruleJoinsSuffixAndSpacingDifferences() {
        #expect(series("제21회 밀양아리랑마라톤대회") == series("제22회 밀양아리랑마라톤"))
        #expect(series("고구려 마라톤 2025") == series("2026 고구려 마라톤"))
    }

    @Test func springAndAutumnIncheonStaySeparate() {
        #expect(series("2025 인천마라톤") == series("2026 인천마라톤 (상반기)"))
        #expect(series("2025 인천마라톤대회") != series("2025 인천마라톤"))
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는지 확인**

Run: 위 "컴파일 명령"
Expected: `error: value of type 'BundledRace' has no member 'series'`

- [ ] **Step 3: `BundledRace`에 `series` 추가**

`MIMORunning/Health/RaceDetector.swift`의 `struct BundledRace`에서 `let startTimeString: String?` 줄 바로 아래에 추가(기본값이 있어야 기존 테스트의 멤버와이즈 생성자 호출이 그대로 컴파일된다):

```swift
    /// 같은 대회를 해마다 묶는 키 — CSV `series` 칸(tools/race_series.py가 채움). 칸이 없거나 비면 nil.
    var series: String? = nil
```

같은 파일 `loadRacesFromCSV()` 안의 `BundledRace(...)` 생성 호출에서 `startTimeString: f[2]` 뒤에 인자를 추가:

```swift
                startTimeString: f[2],
                series: f.count > 11 && !f[11].isEmpty ? f[11] : nil
```

- [ ] **Step 4: 도구 파일 두 개 만들기**

`tools/race_series.py`:

```python
#!/usr/bin/env python3
"""대회 DB(RaceDetector.swift 안 CSV)에 series 칸을 채운다.

규칙: 이름에서 연도(20xx, 20xx년)·회차(제N회, (N회))·띄어쓰기·끝의 '대회'를 떼어 키를 만든다.
같은 키 = 같은 대회. 이름이 실제로 바뀐 대회는 race_series_overrides.tsv(이름<TAB>키)로 지정한다.

사용:
  python3 tools/race_series.py            # series 칸을 다시 채워 파일을 고친다
  python3 tools/race_series.py --check    # 고치지 않고 결과만 출력
  python3 tools/race_series.py --candidates  # 사람이 확인할 후보 쌍(날짜 ±14일·출발지 5km·키 다름)
"""
import csv, io, math, re, sys, datetime as dt
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "MIMORunning/Health/RaceDetector.swift"
OVERRIDES = ROOT / "tools/race_series_overrides.tsv"
OPEN = 'private static let racesCSV = #"""\n'
CLOSE = '\n"""#'

def key(name: str) -> str:
    s = re.sub(r'(?<!\d)20\d{2}년?(?!\d)', '', name)
    s = re.sub(r'\(\s*\d+\s*회\s*\)', '', s)
    s = re.sub(r'제\s*\d+\s*회', '', s)
    s = re.sub(r'\(\s*\)', '', s)
    s = re.sub(r'\s+', '', s)
    s = re.sub(r'대회$', '', s)
    return s

def load():
    text = SWIFT.read_text(encoding="utf-8")
    a = text.index(OPEN) + len(OPEN)
    b = text.index(CLOSE, a)
    return text, a, b, list(csv.reader(io.StringIO(text[a:b])))

def overrides():
    out = {}
    if OVERRIDES.exists():
        for line in OVERRIDES.read_text(encoding="utf-8").splitlines():
            if not line.strip() or line.startswith("#"): continue
            name, k = line.split("\t")
            out[name.strip()] = k.strip()
    return out

def main():
    text, a, b, rows = load()
    header, body = rows[0], rows[1:]
    if header[-1] == "series":
        body = [r[:-1] if len(r) == len(header) else r for r in body]
        header = header[:-1]
    ov = overrides()
    unknown = [n for n in ov if n not in {r[0] for r in body}]
    if unknown:
        sys.exit("overrides에 DB에 없는 이름: " + ", ".join(unknown))
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    w.writerow(header + ["series"])
    series = []
    for r in body:
        s = ov.get(r[0], key(r[0]))
        series.append((r, s))
        w.writerow(r + [s])
    if "--candidates" in sys.argv:
        pts = []
        for r, s in series:
            try: pts.append((r, s, dt.date.fromisoformat(r[1]), float(r[5]), float(r[6])))
            except (ValueError, IndexError): pass
        for r1, s1, d1, la1, ln1 in pts:
            for r2, s2, d2, la2, ln2 in pts:
                if d2.year != d1.year + 1 or s1 == s2: continue
                if abs((d2.replace(year=d1.year) - d1).days) > 14: continue
                km = 111 * math.hypot(la1 - la2, (ln1 - ln2) * math.cos(math.radians(la1)))
                if km <= 5:
                    print(f"{r1[0]} ({r1[1]}) ↔ {r2[0]} ({r2[1]}) · {km:.1f}km")
        return
    groups = {}
    for r, s in series:
        groups.setdefault(s, set()).add(r[1][:4])
    multi = sum(1 for ys in groups.values() if len(ys) > 1)
    print(f"대회 {len(series)}줄 · 시리즈 {len(groups)}개 · 해를 넘는 시리즈 {multi}개")
    if "--check" in sys.argv: return
    new_csv = out.getvalue().rstrip("\n")
    SWIFT.write_text(text[:a] + new_csv + text[b:], encoding="utf-8")
    print("RaceDetector.swift 갱신")

if __name__ == "__main__":
    main()
```

`tools/race_series_overrides.tsv` (탭 구분 — 에디터가 탭을 공백으로 바꾸지 않게 주의):

```text
# 이름<TAB>시리즈 키 — 규칙(연도·회차·띄어쓰기·끝 '대회' 제거)으로 묶이지 않는 같은 대회
2026 춘천마라톤	조선일보춘천마라톤
2026 JTBC 마라톤	JTBC서울마라톤
2026 경기수원국제하프마라톤	수원국제하프마라톤
제23회 태화강 마라톤	태화강국제마라톤
제20회 정남진장흥 전국마라톤	정남진장흥마라톤
2026 인천마라톤 (상반기)	인천마라톤
2026 서울하프마라톤 (조선일보)	서울하프마라톤
RUN SEOUL RUN 2025 (런서울런)	런서울런
3.1절기념 제27회 건강달리기	3.1절건강달리기
제16회 태종대혹서기전국마라톤	태종대전국마라톤
2025 울릉도 국제트레일러닝 UiiT 40K	울릉도국제트레일러닝
2026 울릉도 국제 트레일러닝	울릉도국제트레일러닝
제3회 GO대관령 국제 트레일런	고대관령트레일런
2027 서울마라톤	서울마라톤(동아마라톤)
2025 인천마라톤대회	인천마라톤(하반기)
```

- [ ] **Step 5: 스크립트로 CSV에 series 칸 채우기**

```bash
cd /Users/hns/MIMORunning/MIMORunning && python3 tools/race_series.py --check && python3 tools/race_series.py
```

Expected:
```
대회 428줄 · 시리즈 365개 · 해를 넘는 시리즈 60개
대회 428줄 · 시리즈 365개 · 해를 넘는 시리즈 60개
RaceDetector.swift 갱신
```

(대회 줄 수가 다르면 다른 세션이 DB를 고친 것이다 — 숫자만 보고하고 계속한다.) 기존 줄은 끝에 `,series값`만 붙어야 한다. 확인:

```bash
git diff -U0 MIMORunning/Health/RaceDetector.swift | grep '^-' | grep -v '^---' | wc -l
git diff -U0 MIMORunning/Health/RaceDetector.swift | grep '^+' | grep -c '조선일보춘천마라톤'
```

Expected: 첫 줄은 CSV 줄 수 + 코드 변경 줄 수(약 430), 둘째 줄은 `3`. 그리고 `grep -n "^name,date" MIMORunning/Health/RaceDetector.swift` 결과 끝이 `,series`.

- [ ] **Step 6: 컴파일 성공 확인**

Run: 위 "컴파일 명령"
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 7: 커밋**

```bash
git add tools/race_series.py tools/race_series_overrides.tsv MIMORunning/Health/RaceDetector.swift MIMORunningTests/RaceSeriesCSVTests.swift
git commit -m "$(cat <<'EOF'
대회 DB에 시리즈 칸 — 같은 대회를 해마다 묶는 키, 채우는 도구와 수동 지정 목록

규칙(연도·회차·띄어쓰기·끝 '대회' 제거)으로 모든 줄을 채우고, 이름이 바뀐 대회
(춘천·JTBC·동아 2027 등 14건)와 봄·가을이 다른 인천마라톤은 수동 지정으로 고친다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git show --stat HEAD | tail -6
```

---

### Task 2: 매칭 → 시리즈, 지난 해 후보 찾기

**Files:**
- Modify: `MIMORunning/Health/RaceDetector.swift`
- Test: `MIMORunningTests/RacePastYearTests.swift`

규칙(설계 2-2): 오늘 확정된 대회 M의 DB 줄 → 시리즈. 같은 시리즈의 **더 이른 날짜** 대회 중 M의 종목 거리를 가진 것을 최신순으로 본다. 대회마다 — 그 대회로 이미 확정된 러닝이 있으면 건너뛴다. 없으면 그날 러닝 중 (매칭 기록이 없고, 거리가 M의 종목 거리 ±5%인) 러닝을 기존 하드 게이트로 검사한다. 자동 확정 기준까지 통과하면 `.strong`, 게이트만 통과하면 `.weak`. 대회 하나에 러닝 하나만. **이 함수는 저장하지 않는다** — 확정·질문은 호출자(화면)가 정한다.

- [ ] **Step 1: 테스트 먼저 작성**

`MIMORunningTests/RacePastYearTests.swift`:

```swift
import Testing
import Foundation
import CoreLocation
@testable import MIMORunning

/// 대회 해마다 비교 — 확정 매칭의 시리즈와 지난 해 후보 러닝 판정.
@Suite("대회 지난 해 찾기", .korean)
@MainActor
struct RacePastYearTests {

    private func race(_ name: String, _ date: String, _ time: String?,
                      _ lat: Double, _ lng: Double, _ precision: String, series: String?) -> BundledRace {
        BundledRace(name: name, dateString: date, region: "강원", start: "춘천",
                    startLatitude: lat, startLongitude: lng, geoPrecision: precision,
                    distancesKm: [10.0, 42.195], nonStandard: false, startTimeString: time,
                    series: series)
    }

    private var r26: BundledRace { race("2026 춘천마라톤", "2026-10-25", "09:00", 37.872, 127.718, "venue", series: "c") }
    private var r25: BundledRace { race("제46회 조선일보 춘천마라톤", "2025-10-25", "08:00", 37.87, 127.72, "district", series: "c") }
    private var r24: BundledRace { race("제45회 조선일보 춘천마라톤", "2024-10-27", "09:00", 37.878, 127.726, "venue", series: "c") }
    private var spring: BundledRace { race("2026 춘천봄내마라톤", "2026-06-06", "09:00", 37.8813, 127.73, "venue", series: "b") }

    /// 로컬 시간대 기준 날짜+시각(게이트가 Calendar.current를 쓰므로).
    private func localDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private let todayID = UUID()
    private let id25 = UUID()
    private let id24 = UUID()

    private var todayMatch: PersistedRaceMatch {
        PersistedRaceMatch(activityID: todayID, raceName: "2026 춘천마라톤", distanceKm: 42.195,
                           raceDate: r26.date!, isConfirmed: true, isDismissed: false,
                           isManual: false, gateVersion: RaceDetector.gateVersion)
    }

    private func run(_ id: UUID, _ date: Date, km: Double) -> Activity {
        Activity(id: id, type: .running, date: date, duration: 14_000, distance: km * 1000,
                 calories: nil, avgHeartRate: nil)
    }

    private var runs: [Activity] {
        [run(id25, localDate(2025, 10, 25, 8, 2), km: 42.3),
         run(id24, localDate(2024, 10, 27, 9, 3), km: 42.4)]
    }

    private func detector(matches: [PersistedRaceMatch] = []) -> RaceDetector {
        let d = RaceDetector()
        d.loadRacesForTesting([r26, r25, r24, spring])
        d.loadMatchesForTesting(matches)
        return d
    }

    /// 러닝별 출발·도착 좌표 — 각 대회 출발점에서 출발해 같은 곳에 도착.
    private func ends(_ id: UUID) -> (start: CLLocationCoordinate2D, end: CLLocationCoordinate2D?)? {
        switch id {
        case id25: return (r25.startCoordinate!, r25.startCoordinate!)
        case id24: return (r24.startCoordinate!, r24.startCoordinate!)
        default:   return nil
        }
    }

    // MARK: - 매칭 → DB 줄 · 시리즈

    @Test func matchResolvesToBundledRaceAndSeries() {
        let d = detector()
        #expect(d.bundledRace(for: todayMatch)?.name == "2026 춘천마라톤")
        #expect(d.series(for: todayMatch) == "c")
    }

    @Test func manualRaceHasNoSeries() {
        let manual = PersistedRaceMatch(activityID: UUID(), raceName: "우리 동네 10K", distanceKm: 10,
                                        raceDate: localDate(2026, 5, 1, 8, 0), isConfirmed: true,
                                        isDismissed: false, isManual: true, gateVersion: RaceDetector.gateVersion)
        #expect(detector().series(for: manual) == nil)
    }

    // MARK: - 지난 해 후보

    @Test func findsWeakAndStrongCandidatesNewestFirst() async {
        let found = await detector().pastYearCandidates(for: todayMatch, runs: runs) { self.ends($0) }
        #expect(found.map(\.race.name) == ["제46회 조선일보 춘천마라톤", "제45회 조선일보 춘천마라톤"])
        #expect(found.map(\.activityID) == [id25, id24])
        // 2025는 district 정밀도라 자동 확정 불가 → 질문, 2024는 venue·시각·도착 모두 맞음 → 자동 확정
        #expect(found.map(\.strength) == [.weak, .strong])
    }

    @Test func skipsRunAlreadyMarkedNotRace() async {
        let dismissed = PersistedRaceMatch(activityID: id25, raceName: "", distanceKm: 0, raceDate: Date(),
                                           isConfirmed: false, isDismissed: true, isManual: false,
                                           gateVersion: RaceDetector.gateVersion)
        let found = await detector(matches: [dismissed]).pastYearCandidates(for: todayMatch, runs: runs) { self.ends($0) }
        #expect(found.map(\.activityID) == [id24])
    }

    @Test func skipsRaceAlreadyConfirmedWithAnotherRun() async {
        let other = PersistedRaceMatch(activityID: UUID(), raceName: r25.name, distanceKm: 42.195,
                                       raceDate: r25.date!, isConfirmed: true, isDismissed: false,
                                       isManual: false, gateVersion: RaceDetector.gateVersion)
        let found = await detector(matches: [other]).pastYearCandidates(for: todayMatch, runs: runs) { self.ends($0) }
        #expect(found.map(\.activityID) == [id24])
    }

    @Test func requiresSameEventDistanceAsToday() async {
        // 2025 대회 날 10K를 뛰었다 — 그 대회에 10K 종목이 있어도 오늘(풀)과 비교할 러닝이 아니다
        let tenK = [run(id25, localDate(2025, 10, 25, 8, 2), km: 10.1)]
        let found = await detector().pastYearCandidates(for: todayMatch, runs: tenK) { self.ends($0) }
        #expect(found.isEmpty)
    }

    @Test func runWithoutRouteIsSkipped() async {
        let found = await detector().pastYearCandidates(for: todayMatch, runs: runs) { _ in nil }
        #expect(found.isEmpty)
    }

    @Test func raceWithoutSeriesHasNoCandidates() async {
        let manual = PersistedRaceMatch(activityID: todayID, raceName: "우리 동네 풀", distanceKm: 42.195,
                                        raceDate: localDate(2026, 10, 25, 9, 0), isConfirmed: true,
                                        isDismissed: false, isManual: true, gateVersion: RaceDetector.gateVersion)
        let found = await detector().pastYearCandidates(for: manual, runs: runs) { self.ends($0) }
        #expect(found.isEmpty)
    }
}
```

- [ ] **Step 2: 컴파일이 깨지는지 확인**

Run: 위 "컴파일 명령"
Expected: `value of type 'RaceDetector' has no member 'loadMatchesForTesting'` 등

- [ ] **Step 3: 구현**

`MIMORunning/Health/RaceDetector.swift`에서 `func matchFor(activityID: UUID) -> PersistedRaceMatch? { ... }` 함수 바로 아래에 추가:

```swift

    // MARK: - Series (대회 해마다 비교)

    /// 확정 매칭이 가리키는 DB 대회 줄. 직접 입력한 대회처럼 DB에 없으면 nil.
    /// `confirm`은 `raceDate`에 DB 날짜(UTC 자정)를 넣으므로 UTC 날짜 문자열로 맞춘다.
    func bundledRace(for match: PersistedRaceMatch) -> BundledRace? {
        let day = Self.utcDayString(match.raceDate)
        return races.first { $0.name == match.raceName && $0.dateString == day }
    }

    /// 확정 매칭의 시리즈 값. DB에 없거나 칸이 비면 nil.
    func series(for match: PersistedRaceMatch) -> String? {
        guard let s = bundledRace(for: match)?.series, !s.isEmpty else { return nil }
        return s
    }

    /// 같은 시리즈 지난 해 대회에 해당해 보이는 러닝 하나.
    struct PastRaceCandidate {
        let race: BundledRace
        let activityID: UUID
        /// `.strong` = 자동 확정 기준 통과, `.weak` = 하드 게이트만 통과(사용자에게 묻는다)
        let strength: MatchStrength
    }

    /// 같은 시리즈의 지난 해 대회마다, 그날 러닝 중 조건에 맞는 것을 찾는다(설계 2-2).
    /// 저장하지 않는다 — 확정·질문은 호출자가 정한다.
    /// - Parameter routeEnds: 러닝의 출발·도착 좌표. 경로가 없으면 nil(그 러닝은 건너뜀).
    func pastYearCandidates(
        for match: PersistedRaceMatch,
        runs: [Activity],
        routeEnds: (UUID) async -> (start: CLLocationCoordinate2D, end: CLLocationCoordinate2D?)?
    ) async -> [PastRaceCandidate] {
        guard let series = series(for: match), match.distanceKm > 0 else { return [] }
        let today = Self.utcDayString(match.raceDate)
        let pastRaces = races
            .filter { $0.series == series && $0.dateString < today && $0.bestMatchingDistance(match.distanceKm) != nil }
            .sorted { $0.dateString > $1.dateString }

        var out: [PastRaceCandidate] = []
        for race in pastRaces {
            guard let raceDate = race.date else { continue }
            let alreadyConfirmed = matches.values.contains {
                $0.isConfirmed && $0.raceName == race.name && Self.utcDayString($0.raceDate) == race.dateString
            }
            if alreadyConfirmed { continue }

            let dayRuns = runs.filter {
                $0.type == .running
                && matches[$0.id.uuidString] == nil
                && Calendar.current.isDate($0.date, inSameDayAs: raceDate)
                && abs($0.distance / 1000 - match.distanceKm) / match.distanceKm <= 0.05
            }
            for run in dayRuns {
                guard let ends = await routeEnds(run.id) else { continue }
                let km = run.distance / 1000
                guard passesHardGate(race: race, date: run.date, distanceKm: km, startCoord: ends.start) else { continue }
                let strong = qualifiesForAutoConfirm(race: race, date: run.date, distanceKm: km, endCoord: ends.end)
                out.append(PastRaceCandidate(race: race, activityID: run.id, strength: strong ? .strong : .weak))
                break
            }
        }
        return out
    }

    private static func utcDayString(_ date: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
```

같은 파일의 기존 `func loadRacesForTesting()` 바로 아래에 테스트 훅 두 개를 추가:

```swift

    /// 테스트 전용 — 번들 CSV 대신 주어진 대회로.
    func loadRacesForTesting(_ list: [BundledRace]) {
        races = list
        isReady = true
    }

    /// 테스트 전용 — 저장소(SwiftData·UserDefaults)를 건드리지 않고 매칭을 채운다.
    func loadMatchesForTesting(_ list: [PersistedRaceMatch]) {
        matches = Dictionary(list.map { ($0.activityID.uuidString, $0) }, uniquingKeysWith: { _, b in b })
    }
```

(`qualifiesForAutoConfirm`은 같은 클래스의 private 메서드라 그대로 호출된다. `MatchStrength`는 연관값 없는 enum이라 `==` 비교가 된다.)

- [ ] **Step 4: 컴파일 성공 확인**

Run: 위 "컴파일 명령"
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Health/RaceDetector.swift MIMORunningTests/RacePastYearTests.swift
git commit -m "$(cat <<'EOF'
확정 대회 → DB 줄·시리즈, 같은 시리즈 지난 해 후보 러닝 판정

게이트 통과는 질문(weak), 자동 확정 기준까지 통과는 확정 후보(strong). 저장은 호출자가 한다.
테스트 훅으로 저장소를 건드리지 않고 대회·매칭을 채운다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git show --stat HEAD | tail -3
```

---

### Task 3: 비교 규칙·문장 — `RaceYearOverYear`

**Files:**
- Create: `MIMORunning/Insight/RaceYearOverYear.swift`
- Test: `MIMORunningTests/RaceYearOverYearTests.swift`

규칙: 과거 = 오늘보다 이른 확정 대회(오늘 러닝 제외). **같은 대회** = 시리즈가 같고 공식 종목 거리가 ±2% 안. **같은 거리** = 나머지 중 종목 거리가 10% 안, 최신 5개. 차이는 종목 거리가 ±2% 안이면 완주 시간(과거 − 오늘, 초), 아니면 km당 페이스(과거 − 오늘, 초). 부연 줄 대상 = 같은 대회 최신 > 같은 거리 최신. 1초 이상 빨라졌을 때만 차이를 말하고, 아니면 지난 기록만 말한다.

- [ ] **Step 1: 테스트 먼저 작성**

`MIMORunningTests/RaceYearOverYearTests.swift`:

```swift
import Testing
import Foundation
@testable import MIMORunning

@Suite("대회 해마다 비교", .korean)
struct RaceYearOverYearTests {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    private func entry(_ name: String, _ d: Date, km: Double, sec: TimeInterval,
                       series: String? = nil, temp: Double? = nil, id: UUID = UUID()) -> RaceYearOverYear.Entry {
        RaceYearOverYear.Entry(activityID: id, raceName: name, date: d, distanceKm: km,
                               durationSec: sec, tempC: temp, series: series)
    }

    /// 오늘: 2026 춘천마라톤 3:52:10
    private var today: RaceYearOverYear.Entry {
        entry("2026 춘천마라톤", date(2026, 10, 25), km: 42.195, sec: 13_930, series: "c", temp: 18)
    }

    // MARK: - 같은 대회

    @Test func sameRaceLastYearFaster() {
        let past = entry("2025 춘천마라톤", date(2025, 10, 25), km: 42.195, sec: 14_182, series: "c", temp: 24)
        let c = RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal)
        #expect(c.sameRace.count == 1)
        #expect(c.sameRace[0].delta == .time(seconds: 252))
        #expect(c.headline == "작년보다 4분 12초 빨라요")
        #expect(c.today.isToday)
        #expect(c.today.tempC == 18)
    }

    @Test(.english) func sameRaceLastYearFasterInEnglish() {
        let past = entry("2025 춘천마라톤", date(2025, 10, 25), km: 42.195, sec: 14_182, series: "c")
        #expect(RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal).headline
                == "4:12 faster than last year")
    }

    @Test func sameRaceTwoYearsAgoFaster() {
        let past = entry("2024 춘천마라톤", date(2024, 10, 27), km: 42.195, sec: 14_182, series: "c")
        #expect(RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal).headline
                == "2024년보다 4분 12초 빨라요")
    }

    @Test func sameRaceEarlierThisYearUsesLastWording() {
        let past = entry("2026 춘천마라톤", date(2026, 1, 25), km: 42.195, sec: 14_182, series: "c")
        #expect(RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal).headline
                == "지난 춘천마라톤보다 4분 12초 빨라요")
    }

    @Test func sameRaceSlowerStatesLastRecordOnly() {
        let past = entry("2025 춘천마라톤", date(2025, 10, 25), km: 42.195, sec: 13_800, series: "c")
        let c = RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal)
        #expect(c.headline == "작년 춘천마라톤 3:50:00")
        #expect(c.sameRace[0].delta == .time(seconds: -130))
    }

    @Test func equalTimeIsNotFaster() {
        let past = entry("2025 춘천마라톤", date(2025, 10, 25), km: 42.195, sec: 13_930, series: "c")
        #expect(RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal).headline
                == "작년 춘천마라톤 3:52:10")
    }

    @Test func oneSecondFasterCounts() {
        let past = entry("2025 춘천마라톤", date(2025, 10, 25), km: 42.195, sec: 13_931, series: "c")
        #expect(RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal).headline
                == "작년보다 1초 빨라요")
    }

    @Test func sameSeriesDifferentEventIsNotSameRace() {
        // 작년 같은 대회 10K — 오늘 풀과 같은 대회로도, 같은 거리로도 보지 않는다
        let past = entry("2025 춘천마라톤", date(2025, 10, 25), km: 10, sec: 3_000, series: "c")
        let c = RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal)
        #expect(c.isEmpty)
        #expect(c.headline == nil)
    }

    // MARK: - 같은 거리

    @Test func sameDistanceExactUsesTime() {
        let past = entry("2026 서울마라톤", date(2026, 3, 15), km: 42.195, sec: 14_320, series: "s")
        let c = RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal)
        #expect(c.sameRace.isEmpty)
        #expect(c.sameDistance.map(\.title) == ["서울마라톤"])
        #expect(c.headline == "지난 서울마라톤보다 6분 30초 빨라요")
    }

    @Test func sameDistanceOtherEventUsesPace() {
        let half = entry("2026 서울하프", date(2026, 4, 26), km: 21.0975, sec: 6_300, series: "h")
        let past = entry("2025 ○○", date(2025, 11, 2), km: 20.0, sec: 6_130, series: "x")
        let c = RaceYearOverYear.compare(today: half, confirmed: [past], calendar: cal)
        #expect(c.sameDistance.map(\.title) == ["○○ 20K"])
        #expect(c.sameDistance[0].delta == .pace(secondsPerKm: 8))
        #expect(c.headline == "지난 ○○ 20K보다 km당 8초 빨라요")
    }

    @Test func sameDistanceSlowerStatesLastRecord() {
        let past = entry("2026 서울마라톤", date(2026, 3, 15), km: 42.195, sec: 13_000, series: "s")
        #expect(RaceYearOverYear.compare(today: today, confirmed: [past], calendar: cal).headline
                == "지난 서울마라톤 3:36:40")
    }

    @Test func sameRaceWinsHeadlineOverSameDistance() {
        let race = entry("2025 춘천마라톤", date(2025, 10, 25), km: 42.195, sec: 14_182, series: "c")
        let dist = entry("2026 서울마라톤", date(2026, 3, 15), km: 42.195, sec: 14_320, series: "s")
        let c = RaceYearOverYear.compare(today: today, confirmed: [dist, race], calendar: cal)
        #expect(c.headline == "작년보다 4분 12초 빨라요")
        #expect(c.sameRace.count == 1)
        #expect(c.sameDistance.count == 1)
    }

    @Test func tenPercentDistanceWindow() {
        let tenK = entry("2026 ○○10K", date(2026, 5, 3), km: 10, sec: 3_000)
        let eleven = entry("A", date(2026, 4, 1), km: 11.0, sec: 3_400)
        let elevenHalf = entry("B", date(2026, 3, 1), km: 11.5, sec: 3_500)
        let c = RaceYearOverYear.compare(today: tenK, confirmed: [eleven, elevenHalf], calendar: cal)
        #expect(c.sameDistance.map(\.title) == ["A 11K"])
    }

    @Test func excludesTodayAndFutureAndKeepsFiveNewest() {
        let later = entry("2027 서울마라톤", date(2027, 3, 21), km: 42.195, sec: 14_000)
        let selfEntry = entry("2026 춘천마라톤", date(2026, 10, 25), km: 42.195, sec: 13_930, id: today.activityID)
        let olds = (1...7).map { i in entry("대회\(i)", date(2026, i, 1), km: 42.195, sec: 14_000) }
        let c = RaceYearOverYear.compare(today: today, confirmed: [later, selfEntry] + olds, calendar: cal)
        #expect(c.sameDistance.map(\.title) == ["대회7", "대회6", "대회5", "대회4", "대회3"])
    }

    @Test func noPastRaceMeansEmptyAndNoHeadline() {
        let c = RaceYearOverYear.compare(today: today, confirmed: [], calendar: cal)
        #expect(c.isEmpty)
        #expect(c.headline == nil)
    }

    // MARK: - 표 차이 문구

    @Test func deltaTexts() {
        #expect(RaceYearOverYear.deltaText(.time(seconds: 252)) == "+4:12")
        #expect(RaceYearOverYear.deltaText(.time(seconds: -65)) == "−1:05")
        #expect(RaceYearOverYear.deltaText(.time(seconds: 3_725)) == "+1:02:05")
        #expect(RaceYearOverYear.deltaText(.time(seconds: 0)) == "±0:00")
        #expect(RaceYearOverYear.deltaText(.pace(secondsPerKm: 5)) == "km당 +5초")
        #expect(inEnglish { RaceYearOverYear.deltaText(.pace(secondsPerKm: -3)) } == "−3 s/km")
    }
}
```

손 추적 참고: 14,182 − 13,930 = 252초 = 4분 12초. 13,800 − 13,930 = −130. `mrFormatDisplay(13_800/60)` = "3:50:00", `mrFormatDisplay(13_000/60)` = "3:36:40". 반 페이스: 6,130/20 = 306.5, 6,300/21.0975 = 298.61 → 7.89 → 8. 11.0은 10.0의 10%(경계 포함), 11.5는 15%.

- [ ] **Step 2: 컴파일이 깨지는지 확인**

Run: 위 "컴파일 명령"
Expected: `cannot find 'RaceYearOverYear' in scope`

- [ ] **Step 3: 구현**

`MIMORunning/Insight/RaceYearOverYear.swift`:

```swift
import Foundation

/// 대회 해마다 비교(A단계) — 같은 대회의 지난해, 같은 거리의 지난 대회와 결과를 비교한다.
///
/// 순수 로직(HealthKit·SwiftUI 의존 없음). 설계 `2026-09-27-race-year-over-year-design.md`.
///  · 같은 대회: 시리즈가 같고 공식 종목 거리가 ±2% 안.
///  · 같은 거리: 나머지 중 종목 거리가 10% 안, 최신 5개.
///  · 차이: 종목 거리가 ±2% 안이면 완주 시간, 아니면 km당 페이스. 더위 보정 없음.
///  · 부연 줄: 같은 대회 최신 > 같은 거리 최신. 1초 이상 빨라졌을 때만 차이를 말한다(하락은 조용히).
enum RaceYearOverYear {

    /// 확정된 대회 러닝 하나.
    struct Entry: Equatable {
        let activityID: UUID
        let raceName: String
        let date: Date
        /// 공식 종목 거리(km)
        let distanceKm: Double
        let durationSec: TimeInterval
        let tempC: Double?
        let series: String?
    }

    enum Delta: Equatable {
        /// 과거 − 오늘 완주 시간(초). +면 오늘이 빠르다.
        case time(seconds: Int)
        /// 과거 − 오늘 km당 페이스(초). +면 오늘이 빠르다.
        case pace(secondsPerKm: Int)

        var isTodayFaster: Bool {
            switch self {
            case .time(let s):         return s >= 1
            case .pace(let s):         return s >= 1
            }
        }
    }

    struct Row: Identifiable, Equatable {
        let id: UUID
        let date: Date
        /// 표시 이름. 오늘과 종목 거리가 다르면 "○○ 20K"처럼 종목을 붙인다.
        let title: String
        let durationSec: TimeInterval
        let tempC: Double?
        /// nil = 오늘 행
        let delta: Delta?

        var isToday: Bool { delta == nil }
    }

    /// 같은 시리즈 지난 해 대회로 보이지만 확신이 부족한 러닝 — 대회 탭에서 한 번 묻는다.
    struct Question: Identifiable, Equatable {
        let activityID: UUID
        /// 표시 이름(연도·회차 제거)
        let raceName: String
        let year: Int
        let runDate: Date
        var id: UUID { activityID }
    }

    struct Comparison: Equatable {
        let today: Row
        let sameRace: [Row]
        let sameDistance: [Row]
        /// 인사이트 카드 부연 줄. 비교할 과거 대회가 없으면 nil.
        let headline: String?

        var isEmpty: Bool { sameRace.isEmpty && sameDistance.isEmpty }
    }

    static let exactDistanceTolerance = 0.02
    static let sameDistanceTolerance = 0.10
    static let maxSameDistanceRows = 5

    // MARK: - 비교

    static func compare(today: Entry, confirmed: [Entry], calendar: Calendar = .current) -> Comparison {
        let past = confirmed
            .filter { $0.activityID != today.activityID && $0.date < today.date }
            .sorted { $0.date > $1.date }

        let sameRaceEntries = past.filter { e in
            guard let s = today.series, !s.isEmpty, e.series == s else { return false }
            return isSameEvent(e.distanceKm, today.distanceKm)
        }
        let raceIDs = Set(sameRaceEntries.map(\.activityID))
        let sameDistanceEntries = Array(past.filter { e in
            !raceIDs.contains(e.activityID)
            && abs(e.distanceKm - today.distanceKm) / max(today.distanceKm, 0.001) <= sameDistanceTolerance + 1e-9
        }.prefix(maxSameDistanceRows))

        let headline: String?
        if let e = sameRaceEntries.first {
            headline = sentence(target: e, today: today, sameRace: true, calendar: calendar)
        } else if let e = sameDistanceEntries.first {
            headline = sentence(target: e, today: today, sameRace: false, calendar: calendar)
        } else {
            headline = nil
        }

        return Comparison(
            today: Row(id: today.activityID, date: today.date, title: RaceDisplayName.short(today.raceName),
                       durationSec: today.durationSec, tempC: today.tempC, delta: nil),
            sameRace: sameRaceEntries.map { row(for: $0, today: today) },
            sameDistance: sameDistanceEntries.map { row(for: $0, today: today) },
            headline: headline)
    }

    static func delta(past: Entry, today: Entry) -> Delta {
        if isSameEvent(past.distanceKm, today.distanceKm) {
            return .time(seconds: Int((past.durationSec - today.durationSec).rounded()))
        }
        let pastPace = past.durationSec / max(past.distanceKm, 0.001)
        let todayPace = today.durationSec / max(today.distanceKm, 0.001)
        return .pace(secondsPerKm: Int((pastPace - todayPace).rounded()))
    }

    static func isSameEvent(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) / max(b, 0.001) <= exactDistanceTolerance
    }

    // MARK: - 문장

    /// 부연 줄 한 문장. 빨라졌으면 차이, 아니면 지난 기록만.
    static func sentence(target e: Entry, today: Entry, sameRace: Bool, calendar: Calendar = .current) -> String {
        let L = AppLanguage.shared
        let d = delta(past: e, today: today)
        let name = title(e, today: today)
        let yearsAgo = calendar.component(.year, from: today.date) - calendar.component(.year, from: e.date)
        let year = calendar.component(.year, from: e.date)
        let record = mrFormatDisplay(e.durationSec / 60)

        if d.isTodayFaster {
            let amount: String
            switch d {
            case .time(let s): amount = L.s(koreanDuration(s), clockDuration(s))
            case .pace(let s): amount = L.s("km당 \(s)초", "\(s) s/km")
            }
            if sameRace && yearsAgo == 1 { return L.s("작년보다 \(amount) 빨라요", "\(amount) faster than last year") }
            if sameRace && yearsAgo >= 2 { return L.s("\(year)년보다 \(amount) 빨라요", "\(amount) faster than \(year)") }
            return L.s("지난 \(name)보다 \(amount) 빨라요", "\(amount) faster than your last \(name)")
        }
        if sameRace && yearsAgo == 1 { return L.s("작년 \(name) \(record)", "Last year's \(name): \(record)") }
        if sameRace && yearsAgo >= 2 { return L.s("\(year)년 \(name) \(record)", "\(name) \(year): \(record)") }
        return L.s("지난 \(name) \(record)", "Last \(name): \(record)")
    }

    /// 표의 차이 칸 — "+4:12" · "−1:05" · "±0:00" · "km당 +5초"(영어 "+5 s/km").
    static func deltaText(_ d: Delta) -> String {
        func sign(_ v: Int) -> String { v > 0 ? "+" : (v < 0 ? "−" : "±") }
        switch d {
        case .time(let s):
            return sign(s) + clockDuration(abs(s))
        case .pace(let s):
            return AppLanguage.shared.s("km당 \(sign(s))\(abs(s))초", "\(sign(s))\(abs(s)) s/km")
        }
    }

    // MARK: - 내부

    private static func row(for e: Entry, today: Entry) -> Row {
        Row(id: e.activityID, date: e.date, title: title(e, today: today),
            durationSec: e.durationSec, tempC: e.tempC, delta: delta(past: e, today: today))
    }

    private static func title(_ e: Entry, today: Entry) -> String {
        let name = RaceDisplayName.short(e.raceName)
        return isSameEvent(e.distanceKm, today.distanceKm)
            ? name
            : "\(name) \(RaceDisplayName.distanceLabel(km: e.distanceKm))"
    }

    /// "4분 12초" · "1시간 2분 5초" · "30초"
    private static func koreanDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)시간") }
        if m > 0 { parts.append("\(m)분") }
        if s > 0 || parts.isEmpty { parts.append("\(s)초") }
        return parts.joined(separator: " ")
    }

    /// "4:12" · "1:02:05"
    private static func clockDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
```

주의(손 추적): `tenPercentDistanceWindow`의 11.0은 |11−10|/10 = 0.1이 부동소수점으로 0.1을 살짝 넘을 수 있어 `+ 1e-9` 여유를 둔다. `excludesTodayAndFutureAndKeepsFiveNewest`의 `olds`는 2026년 1~7월 1일이라 모두 오늘(10/25)보다 이르고, 제목은 `RaceDisplayName.short("대회7")` = "대회7".

- [ ] **Step 4: 컴파일 성공 확인**

Run: 위 "컴파일 명령"
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Insight/RaceYearOverYear.swift MIMORunningTests/RaceYearOverYearTests.swift
git commit -m "$(cat <<'EOF'
대회 해마다 비교 규칙·문장 — 같은 대회 지난해·같은 거리 지난 대회, 하락은 조용히

같은 대회는 시리즈+같은 종목, 같은 거리는 10% 안 최신 5개. 같은 종목이면 시간, 아니면 km당 페이스.
빨라졌을 때만 차이를 말하고, 아니면 지난 기록만 적는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git show --stat HEAD | tail -3
```

---

### Task 4: 대회 탭 비교 섹션

**Files:**
- Modify: `MIMORunning/Views/RunInsightCardView.swift` (`RunInsightSection`)
- Modify: `MIMORunning/Views/RunInsightTabCard.swift` (`RunInsightTabCard`, `RaceInsightCard`, `InsightExportSheet`)

전달 경로: `ActivityDetailView` → `RunInsightSection` → `RunInsightTabCard` → `RaceInsightCard`(질문·응답 포함), `RunInsightTabCard` → `InsightExportSheet` → `RaceInsightCard`(내보내기 이미지 — 비교 표만, 질문 없음). 세 구조체 모두 멤버와이즈 생성자를 쓰므로 **새 속성은 각 구조체의 `raceDetailFn` 선언 바로 아래**에 두고, 생성 호출에서도 `raceDetailFn:` 인자 바로 뒤에 넣는다(인자 순서 = 선언 순서).

- [ ] **Step 1: 세 구조체에 속성 추가**

`RunInsightCardView.swift`의 `struct RunInsightSection`에서 `var raceDetailFn: ((UUID) -> ActivityDetail?)? = nil` 줄 아래, 그리고 `RunInsightTabCard.swift`의 `struct RunInsightTabCard`와 `private struct RaceInsightCard`에서 같은 줄 아래에 각각 추가:

```swift
    /// 대회 해마다 비교(같은 대회·같은 거리). 확정 대회가 아니면 nil.
    var raceComparison: RaceYearOverYear.Comparison? = nil
    /// 같은 시리즈 지난 해 대회로 보이는 러닝 — 확인 질문
    var raceQuestions: [RaceYearOverYear.Question] = []
    /// 질문 응답(true = 맞아요). nil이면 질문을 그리지 않는다(내보내기 이미지).
    var onAnswerRaceQuestion: ((RaceYearOverYear.Question, Bool) -> Void)? = nil
```

`struct InsightExportSheet`에는 `var raceDetailFn: ((UUID) -> ActivityDetail?)? = nil` 줄 아래에 하나만 추가:

```swift
    /// 대회 해마다 비교 — 내보내기 이미지에는 표만(질문 없음)
    var raceComparison: RaceYearOverYear.Comparison? = nil
```

- [ ] **Step 2: 생성 호출에 인자 추가**

1. `RunInsightCardView.swift`의 `RunInsightTabCard(` 호출에서 `raceDetailFn: raceDetailFn,` 다음 줄에:

```swift
                raceComparison: raceComparison,
                raceQuestions: raceQuestions,
                onAnswerRaceQuestion: onAnswerRaceQuestion,
```

2. `RunInsightTabCard.swift`의 `.sheet(isPresented: $showExport) { InsightExportSheet(` 호출에서 `raceDetailFn: raceDetailFn,` 다음 줄에:

```swift
                raceComparison: raceComparison,
```

3. 같은 파일 `RunInsightTabCard`의 탭 스위치 `case .race:`의 `RaceInsightCard(` 호출(마지막 인자가 `raceDetailFn: raceDetailFn`)을 다음으로:

```swift
            RaceInsightCard(
                activity: activity, detail: detail,
                age: age, isMale: isMale,
                confirmedRace: confirmedRace,
                confirmedRaces: confirmedRaces,
                history: history,
                raceDetailFn: raceDetailFn,
                raceComparison: raceComparison,
                raceQuestions: raceQuestions,
                onAnswerRaceQuestion: onAnswerRaceQuestion
            )
```

4. `InsightExportSheet` 안의 `case .race:`의 `RaceInsightCard(` 호출도 마지막 `raceDetailFn: raceDetailFn` 뒤에 `,`와 `raceComparison: raceComparison`을 추가.

- [ ] **Step 3: `RaceInsightCard`의 기존 비교 섹션 교체**

`RaceInsightCard.body`에서 다음 블록:

```swift
            // ── 대회 간 비교 (같은 거리 2개 이상)
            let sdr = sameDistanceRaces
            if !sdr.isEmpty {
                Color.white.opacity(0.1).frame(height: 0.5)
                crossRaceSection(sdr)
            }
```

을 다음으로 바꾼다:

```swift
            // ── 같은 대회 · 같은 거리 (과거 대회가 있거나 확인할 과거 러닝이 있을 때)
            if let cmp = raceComparison, !cmp.isEmpty || !visibleQuestions.isEmpty {
                Color.white.opacity(0.1).frame(height: 0.5)
                comparisonSection(cmp)
            }
```

그리고 `private var sameDistanceRaces: ...` 계산 속성과 `private func crossRaceSection(...)` 함수를 **통째로 지운다**(다른 곳에서 쓰지 않는지 `grep -n "sameDistanceRaces\|crossRaceSection" MIMORunning/Views/RunInsightTabCard.swift`로 확인 — 지운 뒤 결과 없음). `distanceDivision(km:)`와 `distanceCollapseRows`는 그대로 둔다.

지운 자리(또는 `RaceInsightCard` 안 아무 `// MARK:` 구역)에 추가:

```swift
    // MARK: 같은 대회 · 같은 거리

    /// 내보내기 이미지(응답 콜백 없음)에서는 질문을 그리지 않는다.
    private var visibleQuestions: [RaceYearOverYear.Question] {
        onAnswerRaceQuestion == nil ? [] : raceQuestions
    }

    private func comparisonSection(_ cmp: RaceYearOverYear.Comparison) -> some View {
        let L = AppLanguage.shared
        let showRaceGroup = !cmp.sameRace.isEmpty || !visibleQuestions.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            Text(L.s("같은 대회 · 같은 거리", "Same Race · Same Distance"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            if showRaceGroup {
                comparisonGroupLabel(L.s("같은 대회", "Same race"))
                comparisonRow(cmp.today)
                ForEach(cmp.sameRace) { comparisonRow($0) }
                ForEach(visibleQuestions) { questionRow($0) }
            }
            if !cmp.sameDistance.isEmpty {
                comparisonGroupLabel(L.s("같은 거리", "Same distance"))
                if !showRaceGroup { comparisonRow(cmp.today) }
                ForEach(cmp.sameDistance) { comparisonRow($0) }
            }
        }
    }

    private func comparisonGroupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.35))
            .padding(.top, 2)
    }

    /// 한 줄 — 연.월 · 이름 · 완주 시간 · 차이(오늘 행은 "오늘") · 기온
    private func comparisonRow(_ row: RaceYearOverYear.Row) -> some View {
        let L = AppLanguage.shared
        let c = Calendar.current.dateComponents([.year, .month], from: row.date)
        return HStack(spacing: 6) {
            Text(String(format: "%d.%02d", c.year ?? 0, c.month ?? 0))
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.45))
                .monospacedDigit()
                .frame(width: 48, alignment: .leading)
            Text(row.title)
                .font(.system(size: 11, weight: row.isToday ? .semibold : .regular))
                .foregroundStyle(row.isToday ? Theme.violet : Color.white.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(mrFormatDisplay(row.durationSec / 60))
                .font(cardNumFont(12))
                .foregroundStyle(row.isToday ? Theme.violet : Color.white.opacity(0.85))
                .lineLimit(1)
                .layoutPriority(1)
            Text(row.delta.map { RaceYearOverYear.deltaText($0) } ?? L.s("오늘", "Today"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(row.isToday ? Theme.violet : Color.white.opacity(0.6))
                .lineLimit(1)
                .frame(width: 62, alignment: .trailing)
            Text(row.tempC.map { "\(Int($0.rounded()))°C" } ?? "")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// 지난 해 대회 확인 — "2025 춘천마라톤 — 10월 25일 러닝이 이 대회였나요?  [맞아요] [아니요]"
    private func questionRow(_ q: RaceYearOverYear.Question) -> some View {
        let L = AppLanguage.shared
        let c = Calendar.current.dateComponents([.month, .day], from: q.runDate)
        let m = c.month ?? 0, d = c.day ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            Text(L.s("\(String(q.year)) \(q.raceName) — \(m)월 \(d)일 러닝이 이 대회였나요?",
                     "\(String(q.year)) \(q.raceName) — was your run on \(m)/\(d) this race?"))
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { onAnswerRaceQuestion?(q, true) } label: {
                    Text(L.s("맞아요", "Yes"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.violet)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button { onAnswerRaceQuestion?(q, false) } label: {
                    Text(L.s("아니요", "No"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.violet.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
```

(`String(q.year)`로 쓰는 이유: 문자열 보간에 Int를 그대로 넣으면 로케일에 따라 "2,025"처럼 쉼표가 들어갈 수 있다.)

- [ ] **Step 4: 컴파일 성공 확인**

Run: 위 "컴파일 명령"
Expected: `** TEST BUILD SUCCEEDED **`
(이 단계에서는 아직 아무도 비교 데이터를 넘기지 않으므로 화면 변화는 "같은 거리 대회 비교" 섹션이 사라지는 것뿐이다. Task 5에서 채운다.)

- [ ] **Step 5: 커밋**

```bash
git add MIMORunning/Views/RunInsightCardView.swift MIMORunning/Views/RunInsightTabCard.swift
git commit -m "$(cat <<'EOF'
대회 탭 "같은 대회 · 같은 거리" 섹션 — 연.월·이름·기록·차이·기온, 지난 해 확인 질문

기존 "같은 거리 대회 비교"(페이스·심박 나열)를 교체한다. 내보내기 이미지에는 질문 없이 표만.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git show --stat HEAD | tail -3
```

---

### Task 5: 활동 상세 — 비교 계산·지난 해 찾기·부연 줄

**Files:**
- Modify: `MIMORunning/Views/ActivityDetailView.swift`

- [ ] **Step 1: 상태 추가**

`@State private var showManualRaceEntry = false` 줄 아래에:

```swift
    /// 대회 해마다 비교 결과. 확정 대회가 아니면 nil.
    @State private var raceComparison: RaceYearOverYear.Comparison? = nil
    /// 같은 시리즈 지난 해 대회로 보이지만 확신이 부족해 사용자에게 물을 러닝
    @State private var pendingPastRaces: [RaceDetector.PastRaceCandidate] = []
```

- [ ] **Step 2: 계산·응답 함수 추가**

`private func runRaceAssessment() async { ... }` 함수 바로 아래에:

```swift
    // MARK: - 대회 해마다 비교

    /// 비교를 다시 계산할 시점 — 오늘 대회 확정 여부, 매칭 수(지난 러닝 확정·대회 아님 포함), 러닝 목록 로드.
    private var raceComparisonKey: String {
        "\(confirmedRaceMatch?.raceName ?? "-")|\(raceDetector.matches.count)|\(manager.activities.count)"
    }

    private var raceQuestions: [RaceYearOverYear.Question] {
        pendingPastRaces.map { c in
            let run = manager.activities.first { $0.id == c.activityID }
            return RaceYearOverYear.Question(
                activityID: c.activityID,
                raceName: RaceDisplayName.short(c.race.name),
                year: Int(c.race.dateString.prefix(4)) ?? 0,
                runDate: run?.date ?? c.race.date ?? Date())
        }
    }

    /// 같은 시리즈 지난 해 러닝을 찾아(확실하면 확정, 애매하면 질문) 비교를 다시 만든다.
    private func refreshRaceComparison() async {
        guard let m = confirmedRaceMatch else {
            raceComparison = nil
            pendingPastRaces = []
            return
        }
        let runs = manager.activities
        let candidates = await raceDetector.pastYearCandidates(for: m, runs: runs) { id in
            var det = manager.detailFromCache(id)
            if det == nil { det = await manager.fetchDetail(for: id) }
            guard let coords = det?.routeCoordinates, let first = coords.first else { return nil }
            return (start: first, end: coords.last)
        }
        guard !Task.isCancelled else { return }
        pendingPastRaces = candidates.filter { $0.strength == .weak }
        for c in candidates where c.strength == .strong {
            guard let run = runs.first(where: { $0.id == c.activityID }) else { continue }
            raceDetector.confirm(activityID: c.activityID, race: c.race, activityDistanceKm: run.distance / 1000)
        }
        raceComparison = buildRaceComparison(for: m)
    }

    private func buildRaceComparison(for m: PersistedRaceMatch) -> RaceYearOverYear.Comparison? {
        let byID = Dictionary(manager.activities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func entry(_ match: PersistedRaceMatch) -> RaceYearOverYear.Entry? {
            guard let a = byID[match.activityID] else { return nil }
            return RaceYearOverYear.Entry(activityID: a.id, raceName: match.raceName, date: a.date,
                                          distanceKm: match.distanceKm, durationSec: a.duration,
                                          tempC: a.temperatureC, series: raceDetector.series(for: match))
        }
        guard let today = entry(m) else { return nil }
        let others = raceDetector.matches.values
            .filter { $0.isConfirmed && $0.activityID != m.activityID }
            .compactMap(entry)
        return RaceYearOverYear.compare(today: today, confirmed: others)
    }

    /// 질문 응답 — 맞아요: 그 대회로 확정, 아니요: 대회 아님(다시 묻지 않음). 매칭 수가 바뀌어 비교가 다시 계산된다.
    private func answerRaceQuestion(_ q: RaceYearOverYear.Question, isSameRace: Bool) {
        guard let c = pendingPastRaces.first(where: { $0.activityID == q.activityID }) else { return }
        if isSameRace, let run = manager.activities.first(where: { $0.id == c.activityID }) {
            raceDetector.confirm(activityID: c.activityID, race: c.race, activityDistanceKm: run.distance / 1000)
        } else {
            raceDetector.markAsNotRace(activityID: c.activityID)
        }
        pendingPastRaces.removeAll { $0.activityID == q.activityID }
    }
```

- [ ] **Step 3: 재계산 트리거**

body 체인의 `.task {` (주석 `// Release any stale in-flight claim left by a prior cancelled task for this activity`로 시작하는 것) 바로 위 줄에 추가:

```swift
        .task(id: raceComparisonKey) {
            guard activity.type == .running else { return }
            await refreshRaceComparison()
        }
```

(`.task(id:)`는 키가 바뀌면 이전 작업을 취소하고 다시 돈다. 지난 해 러닝을 자동 확정하면 매칭 수가 바뀌어 한 번 더 돌고, 두 번째에는 새로 찾을 것이 없어 멈춘다.)

- [ ] **Step 4: 대회 탭으로 전달**

`RunInsightSection(` 호출에서 `raceDetailFn: { [manager] id in manager.detailFromCache(id) },` 다음 줄에:

```swift
                            raceComparison: raceComparison,
                            raceQuestions: raceQuestions,
                            onAnswerRaceQuestion: { q, yes in answerRaceQuestion(q, isSameRace: yes) },
```

- [ ] **Step 5: 인사이트 카드 부연 줄·깃발 줄**

`private struct InsightCard`에서 `var effortValue: Int? = nil` 줄 아래에:

```swift
    /// 대회 해마다 비교 한 문장 — 있으면 대회 러닝(.raceDay)의 부연 줄을 이것으로 바꾸고 종목은 깃발 줄로 옮긴다.
    var comparisonLine: String? = nil

    private var showsComparison: Bool { insight?.theme == .raceDay && comparisonLine != nil }
```

`displayDetail`의 `guard let ins = insight else { ... }` 다음 줄에:

```swift
        if showsComparison, let line = comparisonLine { return line }
```

깃발 줄 `Label(AppLanguage.shared.s("대회 러닝 · \(race.raceName)", "Race · \(race.raceName)"), systemImage: "flag.checkered")`을 다음으로:

```swift
                        let division = showsComparison ? " · " + InsightEngine.raceDistanceDivision(km: race.distanceKm) : ""
                        Label(AppLanguage.shared.s("대회 러닝 · \(race.raceName)\(division)", "Race · \(race.raceName)\(division)"),
                              systemImage: "flag.checkered")
```

(`if let race = confirmedRace {` 블록 안이므로 `let` 선언이 ViewBuilder에서 허용된다.)

`detailContent`의 `InsightCard(` 호출 마지막 인자 `effortValue: resolvedEffort?.value)`를 다음으로:

```swift
                                    effortValue: resolvedEffort?.value,
                                    comparisonLine: raceComparison?.headline)
```

- [ ] **Step 6: 컴파일 성공 확인**

Run: 위 "컴파일 명령"
Expected: `** TEST BUILD SUCCEEDED **`

흔한 실패와 대응:
- `pastYearCandidates`의 트레일링 클로저 안 `manager` 참조가 `self` 캡처를 요구하면 `[manager]` 캡처 목록을 붙인다.
- 반환 튜플 레이블이 추론되지 않으면 `return (start: first, end: coords.last)`처럼 레이블을 명시(위 코드는 이미 명시).

- [ ] **Step 7: 커밋**

```bash
git add MIMORunning/Views/ActivityDetailView.swift
git commit -m "$(cat <<'EOF'
활동 상세 — 대회 해마다 비교 계산, 같은 시리즈 지난 해 러닝 확정·질문, 부연 줄 비교 문장

확실한 지난 해 러닝은 자동 확정, 애매하면 대회 탭에서 한 번 묻는다. 비교가 있으면 대회 러닝의
부연 줄을 비교 문장으로 바꾸고 종목은 깃발 줄로 옮긴다(인사이트 캐시와 무관하게 화면에서 계산).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git show --stat HEAD | tail -3
```

---

### Task 6: 마무리 확인

- [ ] **Step 1: 전체 컴파일**

Run: 위 "컴파일 명령"
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 2: 커밋 범위 확인**

```bash
git log --oneline -6
git status --short
```

Expected: Task 1~5 커밋 5개. `git status`에는 이 작업과 무관한 `project.pbxproj`만.

- [ ] **Step 3: 사용자에게 실기기 확인 목록 전달**(시뮬레이터 금지)

1. 확정된 대회 러닝을 열면, 같은 대회 지난해 기록이 있을 때 부연 줄이 "작년보다 ○분 ○초 빨라요" 또는 "작년 ○○ 기록"으로 바뀌고 깃발 줄 끝에 종목이 붙는다.
2. 대회 탭에 "같은 대회 · 같은 거리" 표가 나오고, 오늘 행이 바이올렛, 과거 행에 차이와 기온이 있다.
3. 지난해 같은 대회 날 러닝이 있는데 확정되지 않았던 경우: 확실하면 표에 바로 들어오고, 애매하면 확인 질문이 뜬다. "맞아요"는 표에 추가, "아니요"는 질문이 사라지고 다시 나오지 않는다.
4. 비교할 과거 대회가 없는 대회는 부연 줄이 예전과 같고 표가 없다.
5. 나 탭 참가 대회 기록의 "N회째"는 아직 나오지 않는다(이 계획 범위 밖 — 아래 후속).

## 후속(이 계획 범위 밖)

- 나 탭 참가 대회 기록의 `N회째`: `MeView.raceRecordsContent`의 `RaceRecordList.rows(...)` 호출에 `seriesKey: { run in raceDetector.series(for: <run의 확정 매칭>) }`를 넘기면 켜진다. `RunInput`에 매칭이 없으므로 `raceDetector.matches[run.activityID.uuidString]`로 찾는다.
- 사용자 확인이 필요한 시리즈 후보 4쌍(남산우정·울진 금강송·청주 무심천·금산) — 확인되면 `tools/race_series_overrides.tsv`에 추가하고 스크립트를 다시 돌린다.
- 2023·2024년 대회 추가 — 사용자가 목록을 주면 CSV에 넣고 스크립트를 다시 돌린다.

## Self-Review 결과

- **설계 대응:** 시리즈 칸·채우는 방법(Task 1) · 매칭→DB 줄·시리즈, 지난 해 찾기(게이트·자동 확정·질문·대회 아님 건너뜀·같은 종목만)(Task 2, 확정·질문 적용은 Task 5) · 같은 거리 10%·최신 5·같은 대회 제외(Task 3) · 비교 숫자(같은 종목 시간/다른 종목 페이스, 더위 보정 없음, 기온 표시)(Task 3·4) · 문장 규칙과 우선순위·하락은 조용히·1초 경계·한/영(Task 3) · 표 묶음·오늘 행·차이 부호·질문 줄·과거 없으면 숨김(Task 4) · 부연 줄·깃발 줄 종목(Task 5) · 테스트 목록(Task 1·2·3).
- **설계와 달라진 점:** 위 "설계와 달라진 점" 4가지. 설계 문서의 6장 표(InsightEngine 변경)는 Task 5 방식으로 대체됨.
- **타입 일관성:** `RaceYearOverYear.Entry/Row/Delta/Question/Comparison`, `RaceDetector.PastRaceCandidate`, `pastYearCandidates(for:runs:routeEnds:)`, `series(for:)`, `bundledRace(for:)`, `loadRacesForTesting(_:)`, `loadMatchesForTesting(_:)` — 정의(Task 2·3)와 사용(Task 4·5) 이름이 같다.
