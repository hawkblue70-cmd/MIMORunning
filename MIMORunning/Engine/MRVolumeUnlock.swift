import Foundation

// MARK: - 대회 계획 주간 거리 상한 — 실제로 해냈으면 한 단계(+10%) 열기 (2026-11-21)
// 설계 docs/superpowers/specs/2026-11-21-volume-cap-unlock-design.md
//
// 상한 = 지난 52주 실제 최대 주간 거리. 계획이 스스로 넘지 않으므로 계획만 따라서는 영영 오르지 않았다.
// 직전 4주 중 3주를 상한의 95% 이상 실제로 달렸고, 최근 14일 아침 판정에 '휴식'이 없고,
// 상향 첫 주가 대회 5주 전 이전이면 → 그 주부터 상한 × 1.10(내림). 계획당 1단계.
// ⚠ 95% · 4주 중 3주 · 14일 · 5주 전은 임의로 정함(문헌·통제 연구 없음). +10% 단계는 기존 증가 규칙(stepPct)과 같은 관행.

struct MRVolumeUnlock: Codable, Equatable {
    /// 상향 첫 주(월요일) — 이 주부터 새 상한
    let fromMonday: Date
    /// 열기 전 상한(52주 최대)과 새 상한
    let baseCapKm: Double
    let raisedCapKm: Double
    /// 근거: 직전 4주 거리(오래된 주 → 최근 주) — 문구용
    let windowKm: [Double]
}

enum MRVolumeUnlockRules {
    static let fraction = 0.95
    static let windowWeeks = 4
    static let needWeeks = 3
    static let restLookbackDays = 14
    static let minWeeksBeforeRace = 5
    /// 새 상한 = 상한 × 1.10, 내림(55 → 60.5 → 60)
    static func raised(_ capKm: Double) -> Double { (capKm * 1.10).rounded(.down) }
    /// 95% 문턱 — 문구에 쓴다(55 → 52)
    static func threshold(_ capKm: Double) -> Double { (capKm * fraction).rounded(.down) }
}

enum MRVolumeUnlockDecision: Equatable {
    case unlocked(MRVolumeUnlock)
    case notYet(reason: String)
}

/// 열림 판정(순수). `restDays`는 직전 14일 중 아침 판정이 '휴식'인 날 수 — 앞 조건을 다 통과했을 때만 부른다(계산이 무겁다).
func mrVolumeUnlock(runs: [MRWorkout], asOf: Date, capKm: Double, raceDate: Date,
                    restDays: () -> Int, calendar cal: Calendar = .current) -> MRVolumeUnlockDecision {
    guard capKm > 0 else { return .notYet(reason: "상한 없음") }
    let thisMonday = MRPlanGovernance.weekMonday(of: asOf, calendar: cal)

    // 직전 4주(끝난 주) 거리 — 오래된 주 → 최근 주
    var window: [Double] = []
    for back in stride(from: MRVolumeUnlockRules.windowWeeks, through: 1, by: -1) {
        guard let mon = cal.date(byAdding: .day, value: -7 * back, to: thisMonday),
              let end = cal.date(byAdding: .day, value: 7, to: mon) else { continue }
        window.append(runs.filter { $0.start >= mon && $0.start < end }.compactMap(\.distanceKm).reduce(0, +))
    }
    let cutoff = capKm * MRVolumeUnlockRules.fraction
    let met = window.filter { $0 + 1e-9 >= cutoff }.count   // 55 × 0.95 = 52.25 같은 경계가 부동소수 오차로 빠지지 않게
    guard met >= MRVolumeUnlockRules.needWeeks else {
        return .notYet(reason: "직전 \(MRVolumeUnlockRules.windowWeeks)주 중 \(met)주만 \(Int(cutoff.rounded(.down)))km 이상")
    }

    // 상향 첫 주 = 다음 주 월요일(이번 주는 이미 정해진 주)
    guard let from = cal.date(byAdding: .day, value: 7, to: thisMonday),
          let latest = cal.date(byAdding: .day, value: -7 * MRVolumeUnlockRules.minWeeksBeforeRace,
                                to: cal.startOfDay(for: raceDate)),
          from <= latest else {
        return .notYet(reason: "대회 \(MRVolumeUnlockRules.minWeeksBeforeRace)주 전 이후라 늦음")
    }

    let rest = restDays()
    guard rest == 0 else { return .notYet(reason: "최근 \(MRVolumeUnlockRules.restLookbackDays)일 중 휴식 판정 \(rest)일") }

    return .unlocked(MRVolumeUnlock(fromMonday: from, baseCapKm: capKm,
                                    raisedCapKm: MRVolumeUnlockRules.raised(capKm), windowKm: window))
}

/// 앞으로 열릴 수 있는가 — 계획대로(남은 주는 계획 거리, 끝난 주는 실제 거리) 달린다고 보고, 오늘 이후 어느 월요일에 판정해도
/// "직전 4주 중 3주가 95% 이상 + 상향 첫 주 ≤ 대회 5주 전"을 못 채우면 false. 휴식 판정은 미리 알 수 없어 보지 않는다(낙관적).
/// 불가능하면 카드의 "…달리면 한 단계 열립니다" 문구를 숨긴다(2026-11-23 사용자).
func mrVolumeUnlockPossible(capKm: Double, raceDate: Date, thisMonday: Date,
                            plannedKm: [Date: Double], actualKm: (Date) -> Double,
                            calendar cal: Calendar = .current) -> Bool {
    guard capKm > 0, let latest = cal.date(byAdding: .day, value: -7 * MRVolumeUnlockRules.minWeeksBeforeRace,
                                           to: cal.startOfDay(for: raceDate)) else { return false }
    let cutoff = capKm * MRVolumeUnlockRules.fraction
    let thisMon = cal.startOfDay(for: thisMonday)
    let planned = Dictionary(plannedKm.map { (cal.startOfDay(for: $0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
    var eval = thisMon   // 판정 월요일
    while let from = cal.date(byAdding: .day, value: 7, to: eval), from <= latest {
        var met = 0
        for back in 1...MRVolumeUnlockRules.windowWeeks {
            guard let mon = cal.date(byAdding: .day, value: -7 * back, to: eval) else { continue }
            let km = mon < thisMon ? actualKm(mon) : (planned[cal.startOfDay(for: mon)] ?? 0)
            if km + 1e-9 >= cutoff { met += 1 }
        }
        if met >= MRVolumeUnlockRules.needWeeks { return true }
        guard let next = cal.date(byAdding: .day, value: 7, to: eval) else { break }
        eval = next
    }
    return false
}

// MARK: - 저장 — 대회별 열림 결정을 유지한다(주마다 판정이 흔들려 계획이 오르내리지 않게)

enum MRVolumeUnlockStore {
    private static let key = "mimo.volumeUnlock.v1"

    static func load() -> [String: MRVolumeUnlock] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let v = try? JSONDecoder().decode([String: MRVolumeUnlock].self, from: d) else { return [:] }
        return v
    }

    static func save(_ v: [String: MRVolumeUnlock]) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }

    /// 이번 판정 결과를 저장된 결정과 합친다.
    /// - 이미 시작된 상향(fromMonday ≤ 오늘)은 고정 — 다시 판정하지 않는다.
    /// - 아직 시작 전인 저장 결정은 이번 판정이 여전히 열림이면 유지(첫 주가 매주 밀리지 않게), 아니면 취소.
    /// - 저장이 없으면 이번 판정이 열림일 때 새로 저장.
    static func resolve(stored: MRVolumeUnlock?, fresh: MRVolumeUnlockDecision, today: Date,
                        calendar cal: Calendar = .current) -> MRVolumeUnlock? {
        if let s = stored, cal.startOfDay(for: s.fromMonday) <= cal.startOfDay(for: today) { return s }
        switch fresh {
        case .unlocked(let u): return stored ?? u
        case .notYet: return nil
        }
    }
}

// MARK: - 시작한 계획의 미래 주 갱신 (트리거 6)

/// 이미 시작한 계획의 스냅샷에서 **상향 첫 주 이후의 미래 주**만 새 상한 기준 라이브 주로 바꾼다.
/// 지난 주·이번 주는 건드리지 않고, 거리가 늘어나는 주(`live.weeklyKm > snap.weeklyKm + 0.5`)·같은 단계인 주만 — 낮추지 않는다.
/// 롱런·실행 안내·강도 훈련은 그 라이브 주를 따른다(트리거 5 "같은 단계 라이브 주를 따른다"와 같은 뜻).
func mrRaiseSnapshotVolume(snapshot: [MRPlanWeekSummary], live: [MRPlanWeek], thisMonday: Date,
                           unlockFrom: Date, calendar cal: Calendar = .current) -> (weeks: [MRPlanWeekSummary], raised: Int) {
    let liveByMonday = Dictionary(live.map { (cal.startOfDay(for: $0.monday), $0) }, uniquingKeysWith: { a, _ in a })
    let thisMon = cal.startOfDay(for: thisMonday)
    let from = cal.startOfDay(for: unlockFrom)
    var raised = 0
    let weeks = snapshot.map { s -> MRPlanWeekSummary in
        let mon = cal.startOfDay(for: s.monday)
        guard mon > thisMon, mon >= from, let l = liveByMonday[mon],
              l.phase == s.phase, l.weeklyKm > s.weeklyKm + 0.5 else { return s }
        raised += 1
        return MRPlanWeekSummary(idx: s.idx, monday: s.monday, phase: s.phase, longRunKm: l.longRunKm,
                                 weeklyKm: l.weeklyKm, breakdown: l.breakdown, point: l.point)
    }
    return (weeks, raised)
}
