import Foundation
import SwiftData

// MARK: - MRReadinessDaySnapshot (기기 안 전용)

/// 홈 "아침 러닝 제안"을 날짜별로 한 장 남긴 기록. 나중에 내보낼 때 그날 앱이 말한 그대로를 보이기 위한 것.
/// ⚠ 기기 안에만 저장한다(iCloud 동기화 안 함) — HRV·안정시 심박 같은 건강 수치가 들어 있어
///   App Review 5.1.3(ii) "개인 건강 정보를 iCloud에 저장하지 말 것"에 걸린다(2026-10-19).
///   앱 컨테이너의 별도 로컬 구성(`readiness-local`, cloudKitDatabase: .none)에 들어간다.
///   대가: 다른 기기·폰 교체 뒤엔 스냅샷이 없어 '당일 아침'이 재계산 문장으로 나온다.
@Model
final class MRReadinessDaySnapshot {
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
    /// 오늘 세션이 계획 포인트(빌드업·템포·인터벌·대회 페이스)였나 — 총평 "의도한" 판단용(2026-10-20). 기기 안 전용이라 CloudKit 배포 무관
    var sessionIsPoint: Bool = false

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

// MARK: - MRReadinessSnapshot (옛 iCloud 동기화 기록 — 옮기기 전용)

/// 2026-10-15~10-19 빌드가 iCloud(CloudKit 레코드 CD_MRReadinessSnapshot)로 동기화하던 옛 기록.
/// 새로 쓰지 않는다. 앱이 켜질 때 `MRReadinessSnapshotStore.migrateLegacy`가 기기 안 기록으로 옮기고 지운다 —
/// 지우면 그 삭제가 iCloud에도 반영되어 서버 사본이 사라진다. 옛 빌드 기기가 다시 올려도 다음 실행 때 또 옮긴다.
/// ⚠ 클래스 이름·속성을 바꾸지 말 것 — CloudKit 엔티티 이름이 클래스 이름이라 바꾸면 옛 기록을 못 읽는다.
@Model
final class MRReadinessSnapshot {
    var dateKey: String = ""
    var level: String = ""
    var line: String = ""
    var why: String = ""
    var data: String = ""
    var planLine: String = ""
    var computedAt: Date = Date.distantPast
    var hrvPending: Bool = false
    var easyCapHR: Int = 0
    var easyPaceSec: Double = 0

    init(dateKey: String = "") { self.dateKey = dateKey }
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
        let key = MRReadinessDaySnapshot.key(for: at)
        let snap: MRReadinessDaySnapshot
        let newData = r.data.joined(separator: " · ")
        if let existing = fetch(dateKey: key, context: context) {
            // 내용이 같으면 쓰지 않는다 — computedAt이 러닝 시작 뒤로 밀려 진짜 러닝 전 스냅샷이 버려지고, 매번 저장·CloudKit 내보내기가 일어나는 것을 막는다
            if existing.level == levelString(r.level), existing.line == r.line, existing.why == r.why,
               existing.data == newData, existing.planLine == (r.planLine ?? ""),
               existing.hrvPending == r.hrvPending,
               existing.easyCapHR == (r.easyCapHR ?? 0), existing.easyPaceSec == (r.easyPaceSecPerKm ?? 0),
               existing.sessionIsPoint == r.sessionIsPoint { return }
            snap = existing
        } else {
            snap = MRReadinessDaySnapshot(dateKey: key)
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
        snap.sessionIsPoint = r.sessionIsPoint
        try? context.save()
    }

    static func fetch(dateKey: String, context: ModelContext) -> MRReadinessDaySnapshot? {
        var d = FetchDescriptor<MRReadinessDaySnapshot>(predicate: #Predicate { $0.dateKey == dateKey })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// 옛 iCloud 기록 → 기기 안 기록으로 옮기고 옛 기록은 지운다(삭제가 iCloud에도 반영됨). 옮길 게 없으면 아무것도 안 한다.
    /// 같은 날짜가 이미 기기 안에 있으면 기기 안 것을 둔다(옮긴 뒤 새로 찍힌 쪽이 최신).
    /// - Returns: 옮긴(지운) 옛 기록 수
    @MainActor
    @discardableResult
    static func migrateLegacy(context: ModelContext) -> Int {
        guard let legacy = try? context.fetch(FetchDescriptor<MRReadinessSnapshot>()), !legacy.isEmpty else { return 0 }
        for old in legacy {
            if fetch(dateKey: old.dateKey, context: context) == nil {
                let n = MRReadinessDaySnapshot(dateKey: old.dateKey, level: old.level, line: old.line, why: old.why,
                                               data: old.data, planLine: old.planLine, computedAt: old.computedAt,
                                               hrvPending: old.hrvPending)
                n.easyCapHR = old.easyCapHR
                n.easyPaceSec = old.easyPaceSec
                context.insert(n)
            }
            context.delete(old)
        }
        try? context.save()
        return legacy.count
    }
}
