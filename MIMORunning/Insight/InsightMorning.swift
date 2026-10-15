import Foundation

// MARK: - 인사이트 내보내기 · 아침 제안 조립
//
// 설계: docs/superpowers/specs/2026-10-15-insight-export-morning-design.md §2–§4
// 새 판정 없음 — 홈이 저장한 스냅샷 또는 엔진 재계산(`MREngineStore.readiness(asOf:)`) 결과만 옮긴다.

struct InsightMorning: Equatable {
    struct Entry: Equatable {
        /// "그날 아침" / "다음 날 아침"
        let label: String
        /// "go" | "easy" | "rest" (스냅샷 저장 형식과 같다)
        let level: String
        /// 엔진·홈이 만든 판정 줄 그대로("오늘은 이지런 · …")
        let line: String
        /// why 첫 문장
        let why: String
        /// 수치 조각(" · " 이음) — "수치 표시" 칩이 켜졌을 때만 그린다
        let data: String
    }
    /// 그날 아침
    var morningOf: Entry?
    /// "→ 실제: " 뒤 문장(탭 요약 리듬 블록 첫 short)
    var actual: String?
    /// 다음 날 아침(데이터 있을 때)
    var nextMorning: Entry?
    /// 다음 날 없을 때 "→ 다음" 줄
    var nextDirection: String?

    var isEmpty: Bool { morningOf == nil && nextMorning == nil && nextDirection == nil }

    /// - snapshotFor: 날짜 키("yyyy-MM-dd") → 홈이 저장한 스냅샷
    /// - recompute: asOf → 그 시각 아침 제안 재계산(엔진 준비 전이면 nil)
    /// - firstRunStart: 어떤 날(그 날 안의 아무 시각) → 그날 첫 러닝 시작. 없으면 nil
    static func make(runStart: Date, now: Date, snapshotFor: (String) -> MRReadinessSnapshot?,
                     recompute: (Date) -> MRReadiness?, firstRunStart: (Date) -> Date?,
                     actual: String?, direction: String?, calendar: Calendar) -> InsightMorning {
        let L = AppLanguage.shared
        let ofLabel = L.s("그날 아침", "That morning", ja: "その日の朝")
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
        if let nextStart = calendar.date(byAdding: .day, value: 1, to: dayStart), now >= nextStart {
            let nextKey = MRReadinessSnapshot.key(for: nextStart, calendar: calendar)
            if let s = snapshotFor(nextKey) {
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
        return InsightMorning(morningOf: morningOf, actual: act, nextMorning: nextMorning,
                              nextDirection: nextMorning == nil ? dir : nil)
    }

    private static func entry(label: String, snapshot s: MRReadinessSnapshot) -> Entry {
        Entry(label: label, level: s.level, line: s.line, why: firstSentence(s.why), data: s.data)
    }

    private static func entry(label: String, readiness r: MRReadiness) -> Entry {
        Entry(label: label, level: MRReadinessSnapshotStore.levelString(r.level), line: r.line,
              why: firstSentence(r.why), data: r.data.joined(separator: " · "))
    }

    /// 첫 문장만 — "." 뒤가 공백·끝일 때(5.2km 같은 소수점은 자르지 않는다), "。"는 곧바로(일본어는 띄어 쓰지 않는다).
    static func firstSentence(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        var i = t.startIndex
        while i < t.endIndex {
            let c = t[i]
            let next = t.index(after: i)
            if c == "。" { return String(t[..<next]) }
            if c == "." && (next == t.endIndex || t[next].isWhitespace) { return String(t[..<next]) }
            i = next
        }
        return t
    }

    /// 판정 줄의 판정어 — 엔진 줄 앞머리("오늘은 ", "Today: ", "今日は")만 뗀다. 새 낱말을 만들지 않는다.
    static func verdict(fromLine line: String) -> String {
        for p in ["오늘은 ", "Today: ", "今日は"] where line.hasPrefix(p) {
            return String(line.dropFirst(p.count))
        }
        return line
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
