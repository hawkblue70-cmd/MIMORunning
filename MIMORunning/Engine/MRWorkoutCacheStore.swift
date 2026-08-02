import Foundation

struct MRWorkoutCache: Codable {
    var newestStart: Date
    var runs: [MRWorkout]
}

/// 워크아웃 리스트를 파일로 캐시한다.
///
/// 캐시 히트 시 전체 HK 쿼리 → 새 워크아웃 수개 쿼리로 단축.
/// isInterval 판정(WorkoutKit 쿼리 N회)도 새 워크아웃만 수행.
enum MRWorkoutCacheStore {
    private static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_workouts_v1.json")
    }

    static func load() -> MRWorkoutCache? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MRWorkoutCache.self, from: d)
    }

    static func save(_ c: MRWorkoutCache) {
        guard let d = try? JSONEncoder().encode(c) else { return }
        try? d.write(to: url, options: .atomic)
    }
}
