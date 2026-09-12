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

    func cache(_ result: InsightResult, for activityID: UUID, isRefined: Bool, language: String) {
        let key = Key(activityID: activityID, isRefined: isRefined, language: language)
        store[key] = result
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
    private static let cacheVersion = 17   // AI 부연이 자리표시 "○'○"를 베낀 캐시 무효화 (v16: "5km")

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
