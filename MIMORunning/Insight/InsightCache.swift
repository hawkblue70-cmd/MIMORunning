import Foundation

actor InsightCache {
    static let shared = InsightCache()
    private init() {}

    private struct Key: Hashable {
        let activityID: UUID
        let historyCount: Int
        let isRefined: Bool
        let language: String
    }

    private var store: [Key: InsightResult] = [:]

    func result(for activityID: UUID, historyCount: Int, isRefined: Bool, language: String) -> InsightResult? {
        store[Key(activityID: activityID, historyCount: historyCount, isRefined: isRefined, language: language)]
    }

    func cache(_ result: InsightResult, for activityID: UUID, historyCount: Int, isRefined: Bool, language: String) {
        store[Key(activityID: activityID, historyCount: historyCount, isRefined: isRefined, language: language)] = result
    }

    func invalidate(_ activityID: UUID) {
        store = store.filter { $0.key.activityID != activityID }
    }

    func clear() {
        store.removeAll()
    }
}
