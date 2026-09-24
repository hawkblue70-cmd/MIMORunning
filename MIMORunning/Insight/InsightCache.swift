import Foundation

actor InsightCache {
    static let shared = InsightCache()
    private init() {}

    private struct Key: Hashable {
        let activityID: UUID
        let isRefined: Bool
        let language: String
    }

    private var store: [Key: InsightResult] = [:]
    private var refinedInFlight: Set<UUID> = []

    // MARK: - Lookup (in-memory → disk)

    func result(for activityID: UUID, isRefined: Bool, language: String) -> InsightResult? {
        let key = Key(activityID: activityID, isRefined: isRefined, language: language)
        if let hit = store[key] {
            #if DEBUG
            print("[DetailInsight] 캐시히트(메모리) v=\(Self.cacheVersion) isRefined=\(isRefined) selected=\(hit.theme.rawValue) title=\"\(hit.title)\"")
            #endif
            return hit
        }
        if let disk = loadFromDisk(activityID: activityID, isRefined: isRefined, language: language) {
            store[key] = disk
            #if DEBUG
            print("[DetailInsight] 캐시히트(디스크) v=\(Self.cacheVersion) isRefined=\(isRefined) selected=\(disk.theme.rawValue) title=\"\(disk.title)\"")
            #endif
            return disk
        }
        return nil
    }

    /// `persist`가 false면 메모리에만 반영하고 디스크에는 쓰지 않는다 — 엔진(MREngineStore)이
    /// 아직 준비되기 전(`isReady == false`)에 계산된 결과는 항등 열지수 모델을 썼을 수 있어,
    /// 디스크에 굳히면 다음 cacheVersion 인상 전까지 잘못된 값이 남는다.
    func cache(_ result: InsightResult, for activityID: UUID, isRefined: Bool, language: String, persist: Bool = true) {
        let key = Key(activityID: activityID, isRefined: isRefined, language: language)
        store[key] = result
        guard persist else { return }
        saveToDisk(result, activityID: activityID, isRefined: isRefined, language: language)
    }

    /// Claims a refined-insight compute slot. Returns true if the caller may proceed; false if already in flight.
    func claimRefinedCompute(_ activityID: UUID) -> Bool {
        guard !refinedInFlight.contains(activityID) else { return false }
        refinedInFlight.insert(activityID)
        return true
    }

    func releaseRefinedCompute(_ activityID: UUID) {
        refinedInFlight.remove(activityID)
    }

    func invalidate(_ activityID: UUID) {
        store = store.filter { $0.key.activityID != activityID }
        refinedInFlight.remove(activityID)   // Allow recomputation after explicit invalidation
    }

    func clear() {
        store.removeAll()
    }

    // MARK: - Disk persistence

    // Bump this when insight generation logic changes to invalidate stale cache files.
    private static let cacheVersion = 23   // AI 부연 주장 검사 — 원문에 없는 "가장·이번 달·연속" 폐기 (v22: 심박 비교를 15°C 기준으로 · v21: 이 러닝 이전 기록만 · v20: 직전 날짜 · v19–16: 이지런·AI 검사)

    /// 테스트에서 파일명 패턴을 검증하기 위해 internal 로 노출.
    static func cacheFileName(activityID: UUID, isRefined: Bool, language: String) -> String {
        let refined  = isRefined ? "1" : "0"
        let safeLang = language.replacingOccurrences(of: "/", with: "_")
        return "\(MRModelVersion.prefix)mimo_insight_\(activityID.uuidString)_\(refined)_\(safeLang)_v\(cacheVersion).json"
    }

    private func diskURL(activityID: UUID, isRefined: Bool, language: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.cacheFileName(activityID: activityID, isRefined: isRefined, language: language))
    }

    private func loadFromDisk(activityID: UUID, isRefined: Bool, language: String) -> InsightResult? {
        let url = diskURL(activityID: activityID, isRefined: isRefined, language: language)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(InsightResult.self, from: data)
    }

    private func saveToDisk(_ result: InsightResult, activityID: UUID, isRefined: Bool, language: String) {
        let url = diskURL(activityID: activityID, isRefined: isRefined, language: language)
        guard let data = try? JSONEncoder().encode(result) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
