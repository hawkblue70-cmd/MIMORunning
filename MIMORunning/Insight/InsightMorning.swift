import Foundation

// MARK: - 러닝 하루 공유 카드 · 아침 제안 조립
//
// 설계: docs/superpowers/specs/2026-10-15-insight-export-morning-design.md §2–§4(스냅샷·재계산)
//      docs/superpowers/specs/2026-10-15-run-day-share-card-design.md(카드 — why 전체·data·planLine)
// 새 판정 없음 — 홈이 저장한 스냅샷 또는 엔진 재계산(`MREngineStore.readiness(asOf:)`) 결과만 옮긴다.

struct InsightMorning: Equatable {
    struct Entry: Equatable {
        /// "당일 아침" / "다음 날 아침"
        let label: String
        /// "go" | "easy" | "rest" (스냅샷 저장 형식과 같다)
        let level: String
        /// 엔진·홈이 만든 판정 줄 그대로("오늘은 이지런 · …")
        let line: String
        /// 왜 그 판정인지 — 홈 둘째 줄 앞부분 전체
        let why: String
        /// 수치 조각(" · " 이음) — HRV·안정시 심박 등, 홈 둘째 줄 뒷부분
        let data: String
        /// 이번 주 계획 진행(홈 셋째 줄). 계획이 없으면 ""
        let planLine: String
    }
    /// 그날 아침
    var morningOf: Entry?
    /// "→ 실제: " 뒤 문장(탭 요약 리듬 블록 첫 short)
    var actual: String?
    /// 다음 날 아침(데이터 있을 때)
    var nextMorning: Entry?
    /// 다음 날 없을 때 "→ 다음" 줄
    var nextDirection: String?

    /// 제안(그날·다음 날)이 하나도 없으면 블록을 숨긴다 — 실제·다음 줄만 덩그러니 나오지 않게
    var isEmpty: Bool { morningOf == nil && nextMorning == nil }

    /// - snapshotFor: 날짜 키("yyyy-MM-dd") → 홈이 저장한 스냅샷
    /// - recompute: asOf → 그 시각 아침 제안 재계산(엔진 준비 전이면 nil)
    /// - firstRunStart: 어떤 날(그 날 안의 아무 시각) → 그날 첫 러닝 시작. 없으면 nil
    static func make(runStart: Date, now: Date, snapshotFor: (String) -> MRReadinessSnapshot?,
                     recompute: (Date) -> MRReadiness?, firstRunStart: (Date) -> Date?,
                     actual: String?, direction: String?, calendar: Calendar,
                     includeNextDay: Bool = true) -> InsightMorning {
        let L = AppLanguage.shared
        let ofLabel = L.s("당일 아침", "That morning", ja: "当日の朝")
        let nextLabel = L.s("다음 날 아침", "Next morning", ja: "翌朝")

        // ① 그날 아침 — 그날 첫 러닝 시작 전에 찍힌 스냅샷 → 없으면 첫 러닝 − 1초로 재계산.
        //    같은 날 두 번째 러닝을 내보내도 '그날 아침'은 첫 러닝 전 제안이다(이미 뛴 날은 엔진이 nil).
        let dayStart = calendar.startOfDay(for: runStart)
        let cutoff = min(firstRunStart(dayStart) ?? runStart, runStart)
        let ofKey = MRReadinessSnapshot.key(for: runStart, calendar: calendar)
        var morningOf: Entry?
        if let s = snapshotFor(ofKey), s.computedAt < cutoff {
            morningOf = entry(label: ofLabel, snapshot: s)
        } else if let r = recompute(cutoff.addingTimeInterval(-1)) {
            morningOf = entry(label: ofLabel, readiness: r)
        }

        // ② 다음 날 아침 — 그 날 스냅샷 → 없으면 min(첫 러닝 − 1초, 12:00, 지금) 재계산.
        //    아직 그 날이 아니거나(저녁 러닝 당일) 그 밤 HRV가 없으면(hrvPending) 블록 대신 방향 줄.
        var nextMorning: Entry?
        if includeNextDay, let nextStart = calendar.date(byAdding: .day, value: 1, to: dayStart), now >= nextStart {
            let nextKey = MRReadinessSnapshot.key(for: nextStart, calendar: calendar)
            // 동기화 전에 찍힌 스냅샷(hrvPending)은 그 밤 값이 없던 문장 → 재계산으로 넘어간다(그것도 pending이면 방향 줄)
            if let s = snapshotFor(nextKey), !s.hrvPending {
                nextMorning = entry(label: nextLabel, snapshot: s)
            } else {
                let noon = calendar.date(byAdding: .hour, value: 12, to: nextStart) ?? nextStart
                var asOf = min(noon, now)
                if let first = firstRunStart(nextStart) { asOf = min(asOf, first.addingTimeInterval(-1)) }
                if let r = recompute(asOf), !r.hrvPending {
                    nextMorning = entry(label: nextLabel, readiness: r)
                }
            }
        }

        let dir = direction.flatMap { $0.isEmpty ? nil : $0 }
        let act = actual.flatMap { $0.isEmpty ? nil : $0 }
        return InsightMorning(morningOf: morningOf, actual: morningOf == nil ? nil : act, nextMorning: nextMorning,
                              nextDirection: nextMorning == nil ? dir : nil)
    }

    private static func entry(label: String, snapshot s: MRReadinessSnapshot) -> Entry {
        Entry(label: label, level: s.level, line: s.line, why: s.why, data: s.data, planLine: s.planLine)
    }

    private static func entry(label: String, readiness r: MRReadiness) -> Entry {
        // 재계산은 지난 시각 기준 — 그 밤 값이 없으면 '동기화 전'이 아니라 없음이라 꼬리를 붙이지 않는다
        Entry(label: label, level: MRReadinessSnapshotStore.levelString(r.level), line: r.line(includePending: false),
              why: r.why, data: r.data.joined(separator: " · "), planLine: r.planLine ?? "")
    }

    static func level(from s: String) -> MRReadiness.Level? {
        switch s {
        case "go": return .go
        case "easy": return .easy
        case "rest": return .rest
        default: return nil
        }
    }
}
