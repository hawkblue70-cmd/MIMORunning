import Foundation

// MARK: - 월간 거리 목표 → 주차 계획 (설계: docs/superpowers/specs/2026-10-07-monthly-volume-goal-design.md)
//
// 사용자가 월 거리를 정하면, 본인 기록으로 검토해 주 단위 계획으로 바꾼다. 무리한 목표는 작게 제안한다.
// 틀(문헌): 주 +10% · 양과 강도를 동시에 올리지 않음 · 롱런 비중(코칭 관행).
// 값(본인 데이터): 출발점(최근 4주) · 경험 범위(12개월 최대 주) · 횟수 · 이지 1회 상한 · 롱런 출발.
// ⚠ 대회 계획과 연결하지 않는다(확인 단계) — 아침 제안·스냅샷·트리거 어디에도 쓰지 않는다.
// ⚠ 진행률·남은 km·달성률은 만들지 않는다(2026-09-22 결정 유지, 목표는 계획의 입력값으로만).
// ⚠ 대회가 있으면 카드를 보이지 않는다 · 강도 훈련은 템포런 ↔ 빌드업만(인터벌은 아침 제안 문장으로만, 2026-10-07).

struct MRMonthlyWeek: Equatable {
    let monday: Date
    /// 이 주 가운데 이번 달 날짜 수(1~7)
    let daysInMonth: Int
    /// 이번 주 이전 — 실제만 표시
    let isPast: Bool
    let isCurrent: Bool
    /// 이 주 실제 거리·횟수(월~일 전체)
    let actualKm: Double
    let actualRuns: Int
    /// 계획 — 지난 주는 nil
    var plannedKm: Double? = nil
    var runs: Int = 0
    var longRunKm: Double = 0
    var easyKm: Double = 0
    var easyRuns: Int = 0
    var point: MRPlanPoint? = nil
    /// 평소 횟수보다 한 번 더 뛰자고 제안한 주
    var addedRun: Bool = false
    var breakdown: String = ""
}

struct MRMonthlyPlan: Equatable {
    enum Limit: Equatable {
        /// 주 증가 속도로 막힘 — 이번 달 가능한 최대
        case growth
        /// 12개월 최대 주 거리 × 1.1에 막힘 — 그 주간 거리
        case experience(weeklyCapKm: Double)
        /// 횟수 천장에서 이지 상한에 막힘 — 그 횟수로 가능한 주간, 한 번 더 뛰면 가능한 주간(7회면 nil)
        case frequency(runs: Int, weeklyMaxKm: Double, plusOneKm: Double?)
    }

    let monthStart: Date
    let daysInMonth: Int
    let goalKm: Double?
    /// 출발점 — 최근 28일 ÷ 4
    let baseWeeklyKm: Double
    /// 최근 12개월 최대 주간 거리(끝난 주)
    let maxWeeklyKm52w: Double
    /// 평소 횟수 — 최근 28일 ÷ 4 반올림(최소 2)
    let usualRuns: Int
    /// 12개월 동안 한 주 최대 러닝 횟수
    let maxRuns52w: Int
    let easyCapKm: Double
    let longest16wKm: Double
    var weeks: [MRMonthlyWeek] = []
    /// 이번 달 예상 합 — 지난 주 실제 + 계획(이번 달 날짜 비율)
    var projectedMonthKm = 0.0
    /// 지금 주간을 그대로 유지하면
    var maintainMonthKm = 0.0
    /// 목표 없이 무리 없는 최대
    var maxMonthKm = 0.0
    var limits: [Limit] = []
    /// 목표가 이번 달에 안 될 때 — 이 흐름이면 다음 달 가능한 거리
    var nextMonthKm: Double? = nil
}

/// 월간 계획에 필요한 본인 데이터 요약. 테스트·디버그 로그가 같이 본다.
struct MRMonthlyBasis: Equatable {
    let baseWeeklyKm: Double
    let usualRuns: Int
    let maxWeeklyKm52w: Double
    let maxRuns52w: Int
    let easyCapKm: Double
    let longest16wKm: Double
    /// 최근 12주 중 러닝 있는 주 수
    let activeWeeks12: Int
}

enum MRMonthlyPlanner {
    /// 경험 범위 밖 주 증가 — 문헌(10% 규칙)
    static let stepNew = 0.10
    /// 경험 범위 안 주 증가 — ⚠ 임의로 정함. 해 본 양으로 돌아가는 복귀 러너 완화, 통제 연구 없음.
    static let stepReturn = 0.15
    /// 경험 밖으로는 한 달에 한 단계 — 12개월 최대 × 1.1
    static let experienceStep = 1.10
    /// ⚠ 임의로 정함 — 습관으로 보기에 최소한의 주 수(강도 훈련 습관과 같은 값)
    static let minActiveWeeks = 6
    static let minBaseWeeklyKm = 5.0
    /// 늘리는 주로 보는 증가 — 이 위면 강도 훈련 간격 +1주
    static let growthWeekRatio = 1.05
    /// 이지 1회가 이 아래면 그 주 강도 훈련 칸을 두지 않는다(대회 계획과 같은 값)
    static let minEasyKm = 1.5

    /// 롱런 비중 — 주간의 max(30%, 1.2/n). ⚠ 코칭 관행("롱런 ≤ 주간 25~30%")을 주 2~3회에도 쓰도록 넓힘.
    static func longShare(runs n: Int) -> Double { max(0.30, 1.2 / Double(max(n, 2))) }
    /// 이지 상한 때문에 롱런을 늘릴 때의 한도 — 주간의 50%. ⚠ 임의로 정함(주 2~3회 러너의 평소 롱런 비중).
    static let maxLongShare = 0.5

    static func basis(runs: [MRWorkout], asOf: Date, calendar cal: Calendar = .current) -> MRMonthlyBasis {
        let today = cal.startOfDay(for: asOf)
        let thisMonday = MRPlanGovernance.weekMonday(of: asOf, calendar: cal)
        func daysAgo(_ d: Date) -> Int { cal.dateComponents([.day], from: cal.startOfDay(for: d), to: today).day ?? -1 }

        let last28 = runs.filter { let d = daysAgo($0.start); return d >= 0 && d < 28 }
        let base = last28.compactMap(\.distanceKm).reduce(0, +) / 4
        let usual = max(Int((Double(last28.count) / 4).rounded()), 2)

        // 끝난 주(이번 주 전) 52주 — 주별 합·횟수
        var weekKm: [Date: Double] = [:], weekRuns: [Date: [MRWorkout]] = [:]
        if let from = cal.date(byAdding: .day, value: -364, to: thisMonday) {
            for w in runs where w.start >= from && w.start < thisMonday {
                let mon = MRPlanGovernance.weekMonday(of: w.start, calendar: cal)
                weekKm[mon, default: 0] += w.distanceKm ?? 0
                weekRuns[mon, default: []].append(w)
            }
        }
        let max52 = weekKm.values.max() ?? 0
        let maxRuns = weekRuns.values.map(\.count).max() ?? usual

        let longest16 = runs.filter { let d = daysAgo($0.start); return d >= 0 && d < 112 }
            .compactMap(\.distanceKm).max() ?? 0

        // 이지 1회 상한 — 최근 12주, 각 주 최장 러닝을 뺀 러닝 거리의 90번째 백분위
        let from84 = cal.date(byAdding: .day, value: -84, to: thisMonday) ?? thisMonday
        let recentWeeks = weekRuns.filter { $0.key >= from84 }
        var others: [Double] = []
        for (_, ws) in recentWeeks {
            let longest = ws.max { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }?.start
            others += ws.filter { $0.start != longest }.compactMap(\.distanceKm)
        }
        let easyCap: Double
        if others.count >= 6 {
            let s = others.sorted()
            easyCap = s[max(Int((0.9 * Double(s.count)).rounded(.up)) - 1, 0)]
        } else {
            easyCap = max(base / Double(usual) * 1.3, 5)
        }
        return MRMonthlyBasis(baseWeeklyKm: base, usualRuns: usual, maxWeeklyKm52w: max52,
                              maxRuns52w: max(maxRuns, usual), easyCapKm: easyCap,
                              longest16wKm: longest16, activeWeeks12: recentWeeks.count)
    }

    /// 강도 훈련 입력 — 없으면 강도 훈련 칸 없이 거리만.
    struct PointInput {
        var habitEveryWeeks: Int? = nil
        var paces: MRPointPaces? = nil
        var intervalHistory: MRIntervalHistory? = nil
        var lastPointStart: Date? = nil
        var lastPointType: WorkoutType? = nil
    }

    /// 기록이 모자라면 nil(설계 1절 게이트).
    static func build(goalKm: Double?, runs: [MRWorkout], asOf: Date, point: PointInput = PointInput(),
                      calendar cal: Calendar = .current) -> MRMonthlyPlan? {
        let b = basis(runs: runs, asOf: asOf, calendar: cal)
        guard b.activeWeeks12 >= minActiveWeeks, b.baseWeeklyKm >= minBaseWeeklyKm,
              let month = cal.dateInterval(of: .month, for: asOf) else { return nil }
        let monthStart = month.start
        let days = cal.range(of: .day, in: .month, for: asOf)?.count ?? 30
        let goal = goalKm.flatMap { $0 > 0 ? $0 : nil }
        let thisMonday = MRPlanGovernance.weekMonday(of: asOf, calendar: cal)
        let ceiling = max(b.maxWeeklyKm52w > 0 ? b.maxWeeklyKm52w * experienceStep : b.baseWeeklyKm * 1.5,
                          b.baseWeeklyKm)

        // 그 달과 겹치는 월요일 주
        var mondays: [Date] = []
        var m = MRPlanGovernance.weekMonday(of: monthStart, calendar: cal)
        while m < month.end {
            mondays.append(m)
            m = cal.date(byAdding: .day, value: 7, to: m) ?? month.end
        }
        func daysIn(_ mon: Date, _ interval: DateInterval) -> Int {
            (0..<7).filter { i in
                guard let d = cal.date(byAdding: .day, value: i, to: mon) else { return false }
                return d >= interval.start && d < interval.end
            }.count
        }
        func actual(_ mon: Date) -> (km: Double, n: Int) {
            let end = cal.date(byAdding: .day, value: 7, to: mon) ?? mon
            let ws = runs.filter { $0.start >= mon && $0.start < end }
            return (ws.compactMap(\.distanceKm).reduce(0, +), ws.count)
        }

        // 계획 진행 — 이번 주(k=0)부터. 목표 nil이면 상한 그대로(= 무리 없는 최대).
        struct Sim { var weeks: [MRMonthlyWeek] = []; var limits: [MRMonthlyPlan.Limit] = []; var lastW: Double }
        func simulate(rate: Double?, withPoints: Bool) -> Sim {
            var sim = Sim(lastW: b.baseWeeklyKm)
            var prev = b.baseWeeklyKm
            var k = 0
            var lastPointIdx: Int? = point.lastPointStart.map { d in
                -((cal.dateComponents([.day], from: MRPlanGovernance.weekMonday(of: d, calendar: cal),
                                      to: thisMonday).day ?? 0) / 7)
            }
            var nextKind = MRPlanPoint.nextKindNoRace(after: point.lastPointType)
            for mon in mondays {
                let a = actual(mon)
                var w = MRMonthlyWeek(monday: mon, daysInMonth: daysIn(mon, month),
                                      isPast: mon < thisMonday, isCurrent: mon == thisMonday,
                                      actualKm: a.km, actualRuns: a.n)
                guard mon >= thisMonday else { sim.weeks.append(w); continue }

                let step = prev < b.maxWeeklyKm52w ? stepReturn : stepNew
                var cap = prev * (1 + step)
                if prev < b.maxWeeklyKm52w && cap > b.maxWeeklyKm52w {
                    cap = max(b.maxWeeklyKm52w, prev * (1 + stepNew))   // 경험 범위를 넘는 부분은 10%로
                }
                let capped = min(cap, ceiling)
                var target = rate.map { min($0, capped) } ?? capped
                if let r = rate, r > capped + 0.05 {
                    let lim: MRMonthlyPlan.Limit = cap >= ceiling ? .experience(weeklyCapKm: r1(ceiling)) : .growth
                    if !sim.limits.contains(lim) { sim.limits.append(lim) }
                }

                // 강도 훈련 칸 — 늘리는 주는 간격 +1주(양과 강도를 동시에 올리지 않음)
                var pt: MRPlanPoint? = nil
                if withPoints, let base = mrPointEveryWeeks(runsPerWeek: Double(b.usualRuns), habit: point.habitEveryWeeks),
                   let paces = point.paces {
                    let every = target > prev * growthWeekRatio ? min(base + 1, 3) : base
                    if lastPointIdx.map({ k - $0 >= every }) ?? true {
                        let longGuess = min(target * longShare(runs: b.usualRuns), longCap(b, k))
                        pt = makePoint(nextKind, weekly: target, long: longGuess, paces: paces, history: point.intervalHistory)
                            ?? makePoint(.tempo, weekly: target, long: longGuess, paces: paces, history: point.intervalHistory)
                    }
                }

                // 횟수 — 이지 1회가 상한을 넘으면 한 번 더(횟수 천장까지), 천장에서도 넘으면 주간을 낮춘다
                var n = b.usualRuns
                var split = splitWeek(target, runs: n, longCap: longCap(b, k), easyCap: b.easyCapKm, point: pt)
                while split.easy > b.easyCapKm + 0.05 && n < b.maxRuns52w {
                    n += 1
                    split = splitWeek(target, runs: n, longCap: longCap(b, k), easyCap: b.easyCapKm, point: pt)
                }
                // 강도 훈련 칸 때문에 주간을 낮춰야 하면 이번 주는 칸을 빼고 다음 주로 미룬다
                if split.easy > b.easyCapKm + 0.05, pt != nil {
                    let without = splitWeek(target, runs: n, longCap: longCap(b, k), easyCap: b.easyCapKm, point: nil)
                    if without.easy <= b.easyCapKm + 0.05 { pt = nil; split = without }
                }
                if split.easy > b.easyCapKm + 0.05 {
                    let lowered = split.long + (pt?.totalKm ?? 0) + Double(split.easyRuns) * b.easyCapKm
                    let plusOne: Double? = n < 7 ? lowered + b.easyCapKm : nil
                    if rate != nil {
                        let lim = MRMonthlyPlan.Limit.frequency(runs: n, weeklyMaxKm: r1(lowered), plusOneKm: plusOne.map(r1))
                        if !sim.limits.contains(where: { if case .frequency = $0 { return true }; return false }) {
                            sim.limits.append(lim)
                        }
                    }
                    target = lowered
                    split = splitWeek(target, runs: n, longCap: longCap(b, k), easyCap: b.easyCapKm, point: pt)
                }
                // 이지가 너무 짧아지면 강도 훈련 칸을 뺀다
                if pt != nil, split.easyRuns < 1 || split.easy < minEasyKm {
                    pt = nil
                    split = splitWeek(target, runs: n, longCap: longCap(b, k), easyCap: b.easyCapKm, point: nil)
                }
                if let p = pt {
                    lastPointIdx = k
                    nextKind = MRPlanPoint.nextKindNoRace(after: workoutType(p.kind))
                }

                w.plannedKm = r1(target)
                w.runs = n
                w.longRunKm = split.long
                w.easyKm = split.easy
                w.easyRuns = split.easyRuns
                w.point = pt
                w.addedRun = n > b.usualRuns
                w.breakdown = breakdownText(long: split.long, easy: split.easy, easyRuns: split.easyRuns)
                sim.weeks.append(w)
                prev = target
                sim.lastW = target
                k += 1
            }
            return sim
        }

        func monthSum(_ ws: [MRMonthlyWeek]) -> Double {
            ws.reduce(0) { acc, w in
                if w.isPast {
                    // 지난 주는 실제 — 그 주 러닝 가운데 이번 달 날짜만
                    let end = cal.date(byAdding: .day, value: 7, to: w.monday) ?? w.monday
                    return acc + runs.filter { $0.start >= max(w.monday, monthStart) && $0.start < min(end, month.end) }
                        .compactMap(\.distanceKm).reduce(0, +)
                }
                return acc + (w.plannedKm ?? 0) * Double(w.daysInMonth) / 7
            }
        }

        let rate = goal.map { $0 * 7 / Double(days) }
        let main = simulate(rate: rate, withPoints: true)
        let free = simulate(rate: nil, withPoints: false)

        var plan = MRMonthlyPlan(monthStart: monthStart, daysInMonth: days, goalKm: goal,
                                 baseWeeklyKm: b.baseWeeklyKm, maxWeeklyKm52w: b.maxWeeklyKm52w,
                                 usualRuns: b.usualRuns, maxRuns52w: b.maxRuns52w, easyCapKm: b.easyCapKm,
                                 longest16wKm: b.longest16wKm)
        plan.weeks = main.weeks
        plan.limits = main.limits
        plan.projectedMonthKm = monthSum(main.weeks)
        plan.maxMonthKm = monthSum(free.weeks)
        plan.maintainMonthKm = b.baseWeeklyKm * Double(days) / 7

        // 목표가 이번 달에 안 되면 — 같은 규칙으로 다음 달까지 이어 본다(경험 범위는 이번 달 최고로 갱신)
        if let g = goal, plan.projectedMonthKm < g - 1,
           let nextStart = cal.date(byAdding: .month, value: 1, to: monthStart),
           let next = cal.dateInterval(of: .month, for: nextStart),
           let nextDays = cal.range(of: .day, in: .month, for: nextStart)?.count {
            let nextRate = g * 7 / Double(nextDays)
            let peak = max(b.maxWeeklyKm52w, main.weeks.compactMap(\.plannedKm).max() ?? 0)
            let nextCeiling = peak * experienceStep
            var prev = main.lastW
            // 횟수 천장 — 롱런 ≤ 주간 50%와 이지 상한으로 낼 수 있는 최대
            let freqMax = 2 * Double(b.maxRuns52w - 1) * b.easyCapKm
            var mon = cal.date(byAdding: .day, value: 7, to: main.weeks.last?.monday ?? thisMonday) ?? next.start
            var sum = 0.0
            // 이번 달 마지막 주가 다음 달에 걸친 날
            if let lw = main.weeks.last, let p = lw.plannedKm { sum += p * Double(7 - lw.daysInMonth) / 7 }
            while mon < next.end {
                let step = prev < peak ? stepReturn : stepNew
                let w = min(prev * (1 + step), nextCeiling, nextRate, freqMax)
                sum += w * Double(daysIn(mon, next)) / 7
                prev = w
                mon = cal.date(byAdding: .day, value: 7, to: mon) ?? next.end
            }
            // 다음 달에도 늘지 않으면(횟수 천장 등) 말하지 않는다 — 그때는 횟수 이유가 답이다
            plan.nextMonthKm = sum > plan.projectedMonthKm + 1 ? sum : nil
        }
        return plan
    }

    // MARK: - 도우미

    static func r1(_ x: Double) -> Double { (x * 10).rounded() / 10 }

    /// 롱런 상한 — 최근 16주 최장에서 주 +10%. 기록 없으면 제한 없음.
    static func longCap(_ b: MRMonthlyBasis, _ k: Int) -> Double {
        b.longest16wKm > 0 ? b.longest16wKm * pow(1 + stepNew, Double(k + 1)) : .infinity
    }

    /// 주간을 롱런 + 강도 훈련 + 이지 × N으로. 롱런은 정수 km, 이지는 표시값 기준으로 역산(합 일치).
    /// 롱런은 비중(`longShare`)에서 시작하고, 이지 1회가 상한을 넘으면 롱런을 먼저 늘린다(롱런 상한·주간의 50%까지).
    static func splitWeek(_ weekly: Double, runs n: Int, longCap: Double, easyCap: Double,
                          point: MRPlanPoint?) -> (long: Double, easy: Double, easyRuns: Int) {
        let wk = r1(weekly)
        let ptKm = point?.totalKm ?? 0
        let easyRuns = max(n - 1 - (point == nil ? 0 : 1), 0)
        var long = min(wk * longShare(runs: n), longCap).rounded()
        if easyRuns > 0, (wk - long - ptKm) / Double(easyRuns) > easyCap {
            // 늘린 롱런은 올림 — 반올림하면 이지가 상한을 0.1~0.5km 넘는다
            long = max(long, min(longCap, wk * maxLongShare, wk - ptKm - Double(easyRuns) * easyCap).rounded(.up))
        }
        long = min(long, longCap.rounded(.down))
        guard easyRuns > 0 else { return (long, 0, 0) }
        let easy = max(wk - long - ptKm, 0) / Double(easyRuns)
        return (long, r1(easy), easyRuns)
    }

    static func makePoint(_ kind: MRPlanPoint.Kind, weekly: Double, long: Double,
                          paces: MRPointPaces, history: MRIntervalHistory?) -> MRPlanPoint? {
        let ip = mrIntervalPace(history: history, fiveKPace: paces.fiveK)
        let pace: Double
        switch kind {
        case .speed: pace = ip.pace
        case .tempo: pace = paces.tempo
        case .buildUp, .racePaceShort: pace = paces.half   // 대회 없을 때 리듬과 같은 기준
        }
        var pt = MRPlanPoint.make(kind: kind, weeklyKm: weekly, longRunKm: long,
                                  raceDistanceM: nil, paceSecPerKm: pace)
        if kind == .speed { pt?.paceFromHistory = ip.fromHistory }
        return pt
    }

    static func workoutType(_ k: MRPlanPoint.Kind) -> WorkoutType {
        switch k {
        case .speed: return .interval
        case .tempo: return .tempo
        case .buildUp, .racePaceShort: return .buildUp
        }
    }

    static func breakdownText(long: Double, easy: Double, easyRuns: Int) -> String {
        let L = AppLanguage.shared
        let lr = Int(long)
        guard easyRuns > 0 else { return L.s("롱런 \(lr)km", "Long run \(lr)km", ja: "ロング走 \(lr)km") }
        let e = mrPointKmString(easy)
        return L.s("롱런 \(lr)km + 이지 \(e)km × \(easyRuns)회",
                   "Long run \(lr)km + Easy \(e)km × \(easyRuns)x",
                   ja: "ロング走 \(lr)km + イージー \(e)km × \(easyRuns)回")
    }
}
