import Foundation

// MARK: - 백테스트 캐시

/// 노력 목록이 바뀌지 않으면 백테스트 결과를 재사용한다.
/// 키 = 노력 목록 핑거프린트 (날짜 + 거리 + 기준 시간 해시).
struct MRBacktestCache: Codable {
    var effortKey: String
    var rows: [MRBacktestRowCodable]
}

struct MRBacktestRowCodable: Codable {
    var date: Date
    var label: String
    var actualMin: Double
    var predictedMin: Double?
    var loMin: Double?
    var hiMin: Double?
    var priorCount: Int

    init(_ r: MRBacktestRow) {
        date = r.date; label = r.label; actualMin = r.actualMin
        predictedMin = r.predictedMin; loMin = r.loMin; hiMin = r.hiMin
        priorCount = r.priorCount
    }
    var row: MRBacktestRow {
        MRBacktestRow(date: date, label: label, actualMin: actualMin,
                      predictedMin: predictedMin, loMin: loMin, hiMin: hiMin,
                      priorCount: priorCount)
    }
}

enum MRBacktestCacheStore {
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("mr_backtest_cache.json")
    }()

    static func load() -> MRBacktestCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MRBacktestCache.self, from: data)
    }

    static func save(_ cache: MRBacktestCache) {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 노력 목록 → 핑거프린트 문자열
    static func effortKey(_ efforts: [MRRaceEffort]) -> String {
        efforts.map { e in
            "\(Int(e.date.timeIntervalSince1970))_\(Int(e.distanceM))_\(Int(e.timeMinRef * 10))"
        }.joined(separator: "|")
    }
}
