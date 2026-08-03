import Foundation

// MARK: - Codable wrapper for MRDriftModel

struct MRDriftModelCodable: Codable {
    var ok: Bool
    var bpmPer10MinAtRef: Double
    var bpmPer10MinPerDegC: Double
    var sessions: Int
    var tempSpanC: Double

    init(_ m: MRDriftModel) {
        ok = m.ok
        bpmPer10MinAtRef   = m.bpmPer10MinAtRef
        bpmPer10MinPerDegC = m.bpmPer10MinPerDegC
        sessions  = m.sessions
        tempSpanC = m.tempSpanC
    }
    var model: MRDriftModel {
        var m = MRDriftModel()
        m.ok = ok
        m.bpmPer10MinAtRef   = bpmPer10MinAtRef
        m.bpmPer10MinPerDegC = bpmPer10MinPerDegC
        m.sessions  = sessions
        m.tempSpanC = tempSpanC
        return m
    }
}

// MARK: - 드리프트 캐시

/// 세그먼트 fetch는 워크아웃당 2 HK 쿼리다.
/// 90일 기준 최대 90건 × 2 = 180 쿼리 → 마지막 워크아웃 시작일이 바뀌지 않으면 재사용.
struct MRDriftCache: Codable {
    var lastWorkoutStart: Date
    var drift: MRDriftModelCodable
}

enum MRDriftCacheStore {
    static var cacheFileName: String { "\(MRModelVersion.prefix)mr_drift_cache.json" }

    private static let url: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(cacheFileName)
    }()

    static func load() -> MRDriftCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MRDriftCache.self, from: data)
    }

    static func save(_ cache: MRDriftCache) {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
