import Foundation
import SwiftData

// MARK: - MRReadinessSnapshot

/// 홈 "아침 러닝 제안"을 날짜별로 한 장 남긴 기록. 나중에 내보낼 때 그날 앱이 말한 그대로를 보이기 위한 것.
/// CloudKit 규칙: 모든 저장 속성에 기본값, unique 제약 없음 → 같은 키 중복은 upsert가 막는다.
@Model
final class MRReadinessSnapshot {
    var dateKey: String = ""        // "yyyy-MM-dd" (로컬 캘린더)
    var level: String = ""          // "go" | "easy" | "rest"
    var line: String = ""
    var why: String = ""
    var data: String = ""
    var planLine: String = ""
    var computedAt: Date = Date.distantPast
    /// 저장 당시 그 밤 HRV가 아직 없었나(워치 동기화 전) — 다음 날 블록은 이 스냅샷 대신 재계산으로 넘어간다
    var hrvPending: Bool = false
    /// 이지 기준 숫자 — 0 = 없음(옛 기록·이지 아닌 날). CloudKit 규칙대로 기본값이 있는 새 속성(2026-10-20)
    var easyCapHR: Int = 0
    var easyPaceSec: Double = 0

    init(dateKey: String = "", level: String = "", line: String = "", why: String = "",
         data: String = "", planLine: String = "", computedAt: Date = Date.distantPast,
         hrvPending: Bool = false) {
        self.dateKey = dateKey
        self.level = level
        self.line = line
        self.why = why
        self.data = data
        self.planLine = planLine
        self.computedAt = computedAt
        self.hrvPending = hrvPending
    }

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

enum MRReadinessSnapshotStore {
    static func levelString(_ l: MRReadiness.Level) -> String {
        switch l {
        case .go: return "go"
        case .easy: return "easy"
        case .rest: return "rest"
        }
    }

    /// 그날 키로 저장 — 있으면 갱신(computedAt = at), 없으면 추가.
    @MainActor
    static func upsert(_ r: MRReadiness, at: Date, context: ModelContext) {
        let key = MRReadinessSnapshot.key(for: at)
        let snap: MRReadinessSnapshot
        let newData = r.data.joined(separator: " · ")
        if let existing = fetch(dateKey: key, context: context) {
            // 내용이 같으면 쓰지 않는다 — computedAt이 러닝 시작 뒤로 밀려 진짜 러닝 전 스냅샷이 버려지고, 매번 저장·CloudKit 내보내기가 일어나는 것을 막는다
            if existing.level == levelString(r.level), existing.line == r.line, existing.why == r.why,
               existing.data == newData, existing.planLine == (r.planLine ?? ""),
               existing.hrvPending == r.hrvPending,
               existing.easyCapHR == (r.easyCapHR ?? 0), existing.easyPaceSec == (r.easyPaceSecPerKm ?? 0) { return }
            snap = existing
        } else {
            snap = MRReadinessSnapshot(dateKey: key)
            context.insert(snap)
        }
        snap.level = levelString(r.level)
        snap.line = r.line
        snap.why = r.why
        snap.data = newData
        snap.planLine = r.planLine ?? ""
        snap.computedAt = at
        snap.hrvPending = r.hrvPending
        snap.easyCapHR = r.easyCapHR ?? 0
        snap.easyPaceSec = r.easyPaceSecPerKm ?? 0
        try? context.save()
    }

    static func fetch(dateKey: String, context: ModelContext) -> MRReadinessSnapshot? {
        var d = FetchDescriptor<MRReadinessSnapshot>(predicate: #Predicate { $0.dateKey == dateKey })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}
