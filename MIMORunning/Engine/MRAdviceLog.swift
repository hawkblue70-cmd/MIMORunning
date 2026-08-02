import Foundation

/// 무엇을 언제 몇 번 보여줬는지 기억한다.
///
/// ⚠ 이게 없으면 앱은 **매일 같은 말을 합니다.**
///   "근력운동을 주 2회 하세요"를 30일 연속 보면 그건 조언이 아니라 잔소리다.
///   같은 조언이 반복될수록 신선도를 떨어뜨려 큐에서 밀어낸다.
struct MRAdviceLog: Codable {
    struct Entry: Codable {
        var lastShown: Date
        var count: Int
    }
    var entries: [String: Entry] = [:]

    /// 신선도 0~1. 우선순위에 곱한다.
    ///
    /// ⚠ v1은 "마지막으로 보여준 지 며칠"로 쟀는데 틀렸다.
    ///   앱을 하루에 세 번 열면 세 번째엔 이미 0.15가 된다 —
    ///   사용자는 아직 한 번도 제대로 안 봤는데.
    ///   → **며칠에 걸쳐 몇 번 말했는가**로 잰다. 같은 날 여러 번은 1회다.
    ///     그리고 14일 이상 안 나왔으면 횟수를 리셋한다(다시 새 조언이 된다).
    func freshness(_ key: String, asOf: Date) -> Double {
        guard let e = entries[key] else { return 1.0 }
        let days = Calendar.current.dateComponents([.day], from: e.lastShown, to: asOf).day ?? 99
        if days >= 14 { return 1.0 }              // 오래 쉬었으면 새 조언
        switch e.count {
        case 0, 1: return 1.00                    // 오늘 처음 나온 것
        case 2:    return 0.70
        case 3:    return 0.50
        case 4:    return 0.35
        default:   return 0.20                    // 다섯 번 말했는데 안 바뀌면 그 조언은 안 통하는 것
        }
    }

    /// 같은 날 여러 번 계산해도 **1회로만** 센다.
    mutating func record(_ keys: [String], asOf: Date) {
        let cal = Calendar.current
        for k in keys {
            if var e = entries[k] {
                if !cal.isDate(e.lastShown, inSameDayAs: asOf) {
                    // 14일 이상 비었으면 리셋
                    let gap = cal.dateComponents([.day], from: e.lastShown, to: asOf).day ?? 0
                    e.count = gap >= 14 ? 1 : e.count + 1
                    e.lastShown = asOf
                    entries[k] = e
                }
            } else {
                entries[k] = Entry(lastShown: asOf, count: 1)
            }
        }
    }
}

enum MRAdviceLogStore {
    private static let key = "mimo.adviceLog.v2"
    static func load() -> MRAdviceLog {
        guard let d = UserDefaults.standard.data(forKey: key),
              let v = try? JSONDecoder().decode(MRAdviceLog.self, from: d)
        else { return MRAdviceLog() }
        return v
    }
    static func save(_ v: MRAdviceLog) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }
}
