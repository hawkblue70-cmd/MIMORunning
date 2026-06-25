import Foundation

actor InsightCache {
    static let shared = InsightCache()
    private init() {}

    private struct Key: Hashable {
        let activityID: UUID
        let historyCount: Int
        let isRefined: Bool
    }

    private var store: [Key: InsightResult] = [:]

    func result(for activityID: UUID, historyCount: Int, isRefined: Bool) -> InsightResult? {
        store[Key(activityID: activityID, historyCount: historyCount, isRefined: isRefined)]
    }

    func cache(_ result: InsightResult, for activityID: UUID, historyCount: Int, isRefined: Bool) {
        store[Key(activityID: activityID, historyCount: historyCount, isRefined: isRefined)] = result
    }

    func invalidate(_ activityID: UUID) {
        store = store.filter { $0.key.activityID != activityID }
    }

    func clear() {
        store.removeAll()
    }
}
