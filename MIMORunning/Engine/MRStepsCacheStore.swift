import Foundation

/// 일별 걸음 수 캐시.
///
/// ⚠ 키를 "yyyy-MM-dd" 문자열로 쓰면 DateFormatter를 2,471×2번 호출하게 된다.
///   DateFormatter는 호출당 수십 마이크로초라 이것만으로 초 단위가 나온다.
///   → epoch day(로컬 기준 정수) 키를 쓴다. 변환이 Calendar.dateComponents 한 번이다.
struct MRStepsCache: Codable {
    var lastDay: Date
    var daily: [Int: Double]    // epochDay → 걸음 수
}

enum MRStepsCacheStore {
    private static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_steps_v2.json")   // v2 = Int 키 스키마
    }

    static func load() -> MRStepsCache? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MRStepsCache.self, from: d)
    }

    static func save(_ c: MRStepsCache) {
        guard let d = try? JSONEncoder().encode(c) else { return }
        try? d.write(to: url, options: .atomic)
    }
}

// MARK: - epoch day 변환 (timezone-safe)
//
// timeIntervalSince1970 / 86400 를 쓰면 UTC+9 같은 시간대에서
// 로컬 자정이 전날 UTC 오후로 떨어져 연속된 날이 같은 정수를 받는다.
// Calendar.dateComponents([.day], ...) 는 DST와 시간대를 모두 처리한다.

private let _epochRef: Date = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 0))

@inline(__always) func mrEpochDay(_ d: Date) -> Int {
    let start = Calendar.current.startOfDay(for: d)
    return Calendar.current.dateComponents([.day], from: _epochRef, to: start).day!
}

@inline(__always) func mrFromEpochDay(_ n: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: n, to: _epochRef)!
}
