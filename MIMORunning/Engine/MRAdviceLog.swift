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

extension MRAdviceLog {
    /// 이 키를 지금 보여줘도 되는가.
    ///
    /// ★ nil(미기록) = 최초 표시 허용.
    ///   nil을 "방금 표시함"으로 처리하면 기록이 없는 사용자가 영원히 못 본다 — 이게 반복된 버그의 핵심이었다.
    func canShow(_ key: String, minDays: Int, asOf: Date = Date()) -> (Bool, String) {
        guard let last = entries[key]?.lastShown else {
            return (true, "미기록 → 최초 표시")
        }
        let d = Calendar.current.dateComponents([.day], from: last, to: asOf).day ?? 0
        return d >= minDays
            ? (true, "\(d)일 경과 → 표시")
            : (false, "\(d)일밖에 안 지남 → 침묵")
    }

    /// 카드가 화면에 나타난 시점(.onAppear)에만 호출.
    /// 판정 시점(canShow 근처)에서 부르지 않는다 — 판정은 앱 켤 때마다 돈다.
    mutating func markShown(_ key: String, asOf: Date = Date()) {
        record([key], asOf: asOf)
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

    // race condition으로 오염된 건강 이야기 항목 1회 삭제.
    // 버전을 올릴 때는 migV1Key 뒤에 .v2, .v3 … 을 추가한다.
    private static let migV1Key = "mimo.adviceLog.migration.healthStoryReset.v1"
    static func runMigrationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migV1Key) else { return }
        var log = load()
        log.entries.removeValue(forKey: "health.story.a")
        log.entries.removeValue(forKey: "health.story.b")
        save(log)
        UserDefaults.standard.set(true, forKey: migV1Key)
    }
}
