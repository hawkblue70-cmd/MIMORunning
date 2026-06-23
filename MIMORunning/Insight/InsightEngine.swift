import Foundation

// MARK: - Output types

enum InsightTheme {
    case firstAchievement
    case recordImproved
    case adverseCondition
    case distanceExpanded
    case consistent
    case recovery
    case raceDay
    case `default`
}

struct InsightResult {
    let theme: InsightTheme
    let workoutType: WorkoutType
    let title: String
    let detail: String

    init(theme: InsightTheme, workoutType: WorkoutType = .general, title: String, detail: String) {
        self.theme = theme
        self.workoutType = workoutType
        self.title = title
        self.detail = detail
    }
}

// MARK: - Rule engine

struct InsightEngine {

    /// Compute the highest-priority insight for `activity` against full history.
    /// Priority: raceDay > firstAchievement > recordImproved > adverseCondition > distanceExpanded > consistent > recovery > default
    /// workoutType modulates the final title/detail; raceDay and firstAchievement always win unchanged.
    static func compute(
        activity: Activity,
        history: [Activity],
        level: LevelBucket = .beginner,
        workoutType: WorkoutType = .general,
        splits: [SplitData] = [],
        intervalSegments: [IntervalSegment] = [],
        condition: ActivityCondition? = nil,
        raceMatch: PersistedRaceMatch? = nil
    ) -> InsightResult {
        let prior = history.filter { $0.id != activity.id && $0.type == activity.type }

        let base: InsightResult
        // firstAchievement beats raceDay so that "첫 풀코스 완주" is preserved.
        // When both apply, the race name is embedded in the detail line.
        if let r = firstAchievement(activity, prior, raceMatch: raceMatch) {
            base = r
        } else if let rm = raceMatch, rm.isConfirmed {
            base = raceDayInsight(rm)
        } else if level >= .novice, let r = recordImproved(activity, prior, level: level) {
            base = r
        } else if let r = adverseCondition(activity, condition) {
            base = r
        } else if let r = distanceExpanded(activity, prior) {
            base = r
        } else if let r = consistent(activity, prior, level: level) {
            base = r
        } else if level >= .novice, let r = recovery(activity, prior, level: level) {
            base = r
        } else {
            base = defaultInsight(activity, prior, level: level)
        }

        let typed = applyWorkoutType(base: base, workoutType: workoutType, activity: activity,
                                     splits: splits, intervalSegments: intervalSegments)
        return InsightResult(theme: typed.theme, workoutType: workoutType, title: typed.title, detail: typed.detail)
    }

    // MARK: - Workout type modulation

    /// Rewrites title to reflect the classified workout type.
    ///
    /// Rules:
    ///  - general  → keep theme-based title unchanged (꾸준함이 쌓이는 러닝, etc.)
    ///  - typed    → type-only vocabulary; NO generic theme words in title
    ///  - strong achievement (firstAchievement / recordImproved) + typed → allowed to combine
    private static func applyWorkoutType(
        base: InsightResult,
        workoutType: WorkoutType,
        activity: Activity,
        splits: [SplitData],
        intervalSegments: [IntervalSegment] = []
    ) -> InsightResult {
        switch workoutType {
        case .general:
            return base

        case .interval:
            guard base.theme != .firstAchievement, base.theme != .adverseCondition,
                  base.theme != .raceDay else { return base }
            let L = AppLanguage.shared
            let title: String
            if base.theme == .recordImproved {
                title = L.s("기록을 깬 인터벌", "PR Interval")
            } else {
                title = pick(
                    [L.s("한계를 깎는 인터벌", "Limit-Breaking Intervals"),
                     L.s("스피드를 깨운 인터벌", "Speed Awakened"),
                     L.s("심장을 끌어올린 인터벌", "Heart-Raising Intervals")],
                    date: activity.date
                )
            }
            let detail = intervalDetailString(intervalSegments: intervalSegments, splits: splits)
            return InsightResult(theme: base.theme, title: title, detail: detail)

        case .longRun:
            guard base.theme != .firstAchievement, base.theme != .adverseCondition,
                  base.theme != .raceDay else { return base }
            let L = AppLanguage.shared
            let title: String
            let detail: String
            if base.theme == .recordImproved {
                title = L.s("기록을 쓴 롱런", "PR Long Run")
                detail = base.detail
            } else if base.theme == .distanceExpanded {
                title = L.s("멀리 나아간 롱런", "Distance Expanded")
                detail = base.detail
            } else {
                title = pick([L.s("멀리 나아간 롱런", "Going the Distance"),
                              L.s("지구력을 쌓은 롱런", "Building Endurance")], date: activity.date)
                detail = L.s("이번 최장 거리 \(activity.formattedDistance)", "Longest this period: \(activity.formattedDistance)")
            }
            return InsightResult(theme: base.theme, title: title, detail: detail)

        case .easy:
            guard base.theme != .firstAchievement, base.theme != .adverseCondition,
                  base.theme != .raceDay else { return base }
            let L = AppLanguage.shared
            return InsightResult(theme: .recovery,
                                 title: L.s("숨을 고른 이지런", "Easy Does It"),
                                 detail: L.s("낮은 강도로 다음 훈련을 준비", "Low effort, prepping for the next session"))

        case .tempo:
            guard base.theme != .firstAchievement, base.theme != .adverseCondition,
                  base.theme != .raceDay else { return base }
            let L = AppLanguage.shared
            let title: String
            if base.theme == .recordImproved {
                title = L.s("기록을 깬 템포", "PR Tempo")
            } else {
                title = pick([L.s("리듬을 탄 템포", "In the Groove"),
                              L.s("임계점을 밀어붙인 템포", "Pushing the Threshold")], date: activity.date)
            }
            let detail = base.theme == .recordImproved
                ? base.detail
                : L.s("균일하게 밀어붙인 \(activity.formattedDistance)", "Steady effort for \(activity.formattedDistance)")
            return InsightResult(theme: base.theme, title: title, detail: detail)
        }
    }

    /// Deterministic pick from `titles` based on workout date — consistent per run, varied across runs.
    private static func pick(_ titles: [String], date: Date) -> String {
        let seed = Int(abs(date.timeIntervalSinceReferenceDate))
        return titles[seed % titles.count]
    }

    /// Builds the interval insight detail string.
    /// Prefers WorkoutKit work steps ("운동" label); falls back to fast km splits.
    private static func intervalDetailString(
        intervalSegments: [IntervalSegment],
        splits: [SplitData]
    ) -> String {
        let L = AppLanguage.shared
        let workSteps = intervalSegments.filter { $0.stepLabel == "운동" }
        if !workSteps.isEmpty {
            let fastest = workSteps.min { ($0.paceSecPerKm ?? .greatestFiniteMagnitude) < ($1.paceSecPerKm ?? .greatestFiniteMagnitude) }
            let fastestStr = fastest?.formattedPace
            let dists = workSteps.compactMap(\.distanceM)
            let avgDist = dists.isEmpty ? nil : dists.reduce(0, +) / Double(dists.count)
            let distStr = avgDist.map { String(format: "%.0fm", $0) }
            switch (distStr, fastestStr) {
            case let (d?, f?): return L.s("\(d)×\(workSteps.count), 최고 \(f)", "\(d)×\(workSteps.count), best \(f)")
            case let (nil, f?): return L.s("\(workSteps.count)개 구간, 최고 \(f)", "\(workSteps.count) reps, best \(f)")
            case let (d?, nil): return "\(d)×\(workSteps.count)"
            default:            return L.s("\(workSteps.count)개 인터벌 구간", "\(workSteps.count) interval reps")
            }
        }
        // fallback: fast km splits
        let fullSplits = splits.filter { $0.distanceM >= 900 }
        if let fastest = fullSplits.min(by: { $0.paceSecPerKm < $1.paceSecPerKm }) {
            return L.s("\(fullSplits.count)개 구간, 최고 \(fastest.formattedPace)", "\(fullSplits.count) splits, best \(fastest.formattedPace)")
        }
        return L.s("인터벌 훈련으로 속도 자극", "Speed work complete")
    }

    // MARK: - Achievement checks

    private static func raceDayInsight(_ rm: PersistedRaceMatch) -> InsightResult {
        let L = AppLanguage.shared
        let km = rm.distanceKm
        let title: String
        if abs(km - 42.195) < 1.0       { title = L.s("마라톤 완주 러닝", "Marathon Finish") }
        else if abs(km - 21.0975) < 0.5 { title = L.s("하프 완주 러닝",  "Half Marathon Finish") }
        else if abs(km - 10) < 0.5      { title = L.s("10K 대회 러닝",   "10K Race") }
        else if abs(km - 5) < 0.3       { title = L.s("5K 대회 러닝",    "5K Race") }
        else                             { title = L.s("대회 러닝",       "Race Day") }
        return InsightResult(theme: .raceDay, title: title, detail: rm.raceName)
    }

    /// First time reaching a distance milestone (3K / 5K / 10K / half / full).
    /// When a confirmed race match is provided, the race name is embedded in the detail.
    private static func firstAchievement(
        _ a: Activity,
        _ prior: [Activity],
        raceMatch: PersistedRaceMatch? = nil
    ) -> InsightResult? {
        let L = AppLanguage.shared
        let km = a.distance / 1000
        let milestones: [(Double, String, String)] = [
            (42.2, "풀코스 마라톤", "Full Marathon"),
            (21.1, "하프 마라톤",  "Half Marathon"),
            (10.0, "10K",         "10K"),
            (5.0,  "5K",          "5K"),
            (3.0,  "3K",          "3K")
        ]
        for (threshold, koLabel, enLabel) in milestones {
            guard km >= threshold else { continue }
            if !prior.contains(where: { $0.distance / 1000 >= threshold }) {
                let label = L.s(koLabel, enLabel)
                let detail: String
                if let race = raceMatch, race.isConfirmed {
                    detail = L.s("\(race.raceName) · 생애 첫 \(label) 완주", "\(race.raceName) · First ever \(label) finish")
                } else {
                    detail = L.s("생애 첫 \(label) 완주", "First ever \(label) finish")
                }
                return InsightResult(theme: .firstAchievement, title: L.s("문을 연 러닝", "Breaking Through"), detail: detail)
            }
            break
        }
        return nil
    }

    /// Pace PR within ±15% of current distance over last 90 days
    private static func recordImproved(_ a: Activity, _ prior: [Activity], level: LevelBucket = .beginner) -> InsightResult? {
        guard let pace = a.paceSecPerKm else { return nil }
        let km = a.distance / 1000
        let margin = km * 0.15
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: a.date) ?? .distantPast
        let priorPaces = prior
            .filter { abs($0.distance / 1000 - km) <= margin && $0.date >= cutoff }
            .compactMap(\.paceSecPerKm)
        guard !priorPaces.isEmpty, let bestPrior = priorPaces.min(), pace < bestPrior else { return nil }
        let L = AppLanguage.shared
        let (title, detail): (String, String) = {
            switch level {
            case .advanced, .elite:
                return (L.s("효율의 러닝", "Efficiency Run"),
                        L.s("동일 거리 페이스 갱신 — 한계를 넘어서는 중", "PR on same distance — limits keep dropping"))
            default:
                return (L.s("한계를 미는 러닝", "Pushing Limits"),
                        L.s("최근 동일 거리 중 가장 빠른 페이스 \(a.formattedPace ?? "")",
                            "Fastest pace on this distance recently: \(a.formattedPace ?? "")"))
            }
        }()
        return InsightResult(theme: .recordImproved, title: title, detail: detail)
    }

    /// Longest run this week or this calendar month (≥ 5 km).
    /// Weekly checked first — more immediate achievement; falls back to monthly.
    private static func distanceExpanded(_ a: Activity, _ prior: [Activity]) -> InsightResult? {
        guard a.distance / 1000 >= 5 else { return nil }
        let cal = Calendar.current

        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: a.date)) ?? .distantPast
        let maxPriorWeek = prior.filter { $0.date >= weekStart }.map(\.distance).max() ?? 0
        let L = AppLanguage.shared
        if a.distance > maxPriorWeek {
            return InsightResult(theme: .distanceExpanded,
                                 title: L.s("경계를 넓힌 러닝", "Expanding Boundaries"),
                                 detail: L.s("이번 주 최장 거리 \(a.formattedDistance)", "Longest run this week: \(a.formattedDistance)"))
        }

        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: a.date)) ?? .distantPast
        let maxPriorMonth = prior.filter { $0.date >= monthStart }.map(\.distance).max() ?? 0
        guard a.distance > maxPriorMonth else { return nil }
        return InsightResult(theme: .distanceExpanded,
                             title: L.s("경계를 넓힌 러닝", "Expanding Boundaries"),
                             detail: L.s("이번 달 최장 거리 \(a.formattedDistance)", "Longest run this month: \(a.formattedDistance)"))
    }

    /// Consecutive-weeks streak ≥ threshold, or ≥ N runs this week
    private static func consistent(_ a: Activity, _ prior: [Activity], level: LevelBucket = .beginner) -> InsightResult? {
        let cal = Calendar.current
        let streakThreshold = level == .beginner ? 2 : 3

        // Precompute set of weeks that have at least one prior run — O(n) once
        let priorWeekStarts = Set(prior.map {
            cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.date)) ?? $0.date
        })

        var streak = 1
        var weekAnchor = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: a.date)
        ) ?? a.date
        for _ in 0..<52 {
            let prevWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekAnchor)!
            if priorWeekStarts.contains(prevWeekStart) {
                streak += 1
                weekAnchor = prevWeekStart
            } else {
                break
            }
        }
        let L = AppLanguage.shared
        if streak >= streakThreshold {
            let (title, detail): (String, String) = {
                switch level {
                case .beginner:
                    return (L.s("꾸준함이 쌓이는 러닝", "Building Consistency"),
                            L.s("\(streak)주 연속 — 루틴이 만들어지고 있어요", "\(streak) weeks straight — building a routine"))
                case .advanced, .elite:
                    return (L.s("자산 축적 러닝", "Banking Miles"),
                            L.s("\(streak)주 연속 러닝", "\(streak) weeks in a row"))
                default:
                    return (L.s("쌓이는 러닝", "Stacking Up"),
                            L.s("\(streak)주 연속 러닝", "\(streak) weeks in a row"))
                }
            }()
            return InsightResult(theme: .consistent, title: title, detail: detail)
        }

        let thisWeekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: a.date)
        ) ?? a.date
        let thisWeekCount = prior.filter { $0.date >= thisWeekStart }.count + 1
        let weekCountThreshold = level == .beginner ? 2 : 3
        if thisWeekCount >= weekCountThreshold {
            let (title, detail): (String, String) = {
                switch level {
                case .beginner:
                    return (L.s("꾸준함이 쌓이는 러닝", "Building Consistency"),
                            L.s("이번 주 \(thisWeekCount)번째 러닝", "Run #\(thisWeekCount) this week"))
                default:
                    return (L.s("쌓이는 러닝", "Stacking Up"),
                            L.s("이번 주 \(thisWeekCount)번째 러닝", "Run #\(thisWeekCount) this week"))
                }
            }()
            return InsightResult(theme: .consistent, title: title, detail: detail)
        }
        return nil
    }

    /// Pace ≥ 15% slower than recent average; HR below average when available
    private static func recovery(_ a: Activity, _ prior: [Activity], level: LevelBucket = .beginner) -> InsightResult? {
        guard let pace = a.paceSecPerKm else { return nil }
        let recentPaces = prior.prefix(10).compactMap(\.paceSecPerKm)
        guard !recentPaces.isEmpty else { return nil }
        let avgPace = recentPaces.reduce(0, +) / Double(recentPaces.count)
        guard pace > avgPace * 1.15 else { return nil }

        if let hr = a.avgHeartRate {
            let recentHRs = prior.prefix(10).compactMap(\.avgHeartRate)
            if !recentHRs.isEmpty {
                let avgHR = Double(recentHRs.reduce(0, +)) / Double(recentHRs.count)
                guard Double(hr) < avgHR else { return nil }
            }
        }
        let L = AppLanguage.shared
        let detail = level >= .advanced
            ? L.s("의도적인 회복 — 다음 퀄리티 훈련을 위한 투자", "Intentional recovery — investing in your next quality session")
            : L.s("몸을 돌보는 여유로운 페이스", "Taking care of your body, easy pace")
        return InsightResult(theme: .recovery, title: L.s("숨 고르는 러닝", "Easy Does It"), detail: detail)
    }

    private static func adverseCondition(_ a: Activity, _ condition: ActivityCondition?) -> InsightResult? {
        guard let cond = condition, cond.hasAdverseSignal, a.distance >= 1000 else { return nil }

        let L = AppLanguage.shared
        if let w = cond.weather, w.isAdverse {
            if w.isRainy {
                return InsightResult(theme: .adverseCondition,
                                     title: L.s("빗속을 달린 러닝", "Running in the Rain"),
                                     detail: L.s("비와 함께 — 해낸 것 자체가 성취", "Through the rain — showing up is the achievement"))
            }
            if w.isHot {
                return InsightResult(theme: .adverseCondition,
                                     title: L.s("더위를 이겨낸 러닝", "Beating the Heat"),
                                     detail: L.s("\(w.formattedTemp) 더위에도 끝까지", "\(w.formattedTemp) heat, but you finished"))
            }
            if w.isCold {
                return InsightResult(theme: .adverseCondition,
                                     title: L.s("추위를 뚫은 러닝", "Pushing Through the Cold"),
                                     detail: L.s("\(w.formattedTemp) — 나오는 것만으로도 반", "\(w.formattedTemp) — getting out was half the battle"))
            }
            return InsightResult(theme: .adverseCondition,
                                 title: L.s("바람을 가른 러닝", "Into the Wind"),
                                 detail: L.s("강풍 속에서도 멈추지 않았어요", "Strong winds, but you didn't stop"))
        }
        let sleepLabel = cond.sleepScore.map { L.s("수면 \($0.grade.label)", "Sleep: \($0.grade.label)") } ?? L.s("수면 부족", "poor sleep")
        return InsightResult(theme: .adverseCondition,
                             title: L.s("잠 부족에도 해낸 러닝", "Running on Little Sleep"),
                             detail: L.s("\(sleepLabel)인 날 — 그래도 나섰어요", "\(sleepLabel) — you showed up anyway"))
    }

    // MARK: - AI enhancement bridge

    /// Attempts on-device AI rewrite (iOS 26+). Returns nil on older OS or failure;
    /// callers keep the rule-based result as-is.
    static func tryAIEnhance(_ base: InsightResult) async -> InsightResult? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return await InsightAIGenerator.enhance(base)
        }
        #endif
        return nil
    }

    private static func defaultInsight(_ a: Activity, _ prior: [Activity], level: LevelBucket = .beginner) -> InsightResult {
        let L = AppLanguage.shared
        if prior.isEmpty {
            return InsightResult(theme: .default,
                                 title: L.s("시작이 전부인 러닝", "The First Step"),
                                 detail: L.s("첫 걸음, 가장 어렵고 가장 값진 순간", "The first step is the hardest — and most valuable"))
        }
        let total = prior.count + 1
        if total % 10 == 0 {
            return InsightResult(theme: .default,
                                 title: L.s("자산 축적 러닝", "Banking Miles"),
                                 detail: L.s("누적 \(total)번째 러닝 달성", "Run #\(total) — every one counts"))
        }
        switch level {
        case .beginner:
            return InsightResult(theme: .default,
                                 title: L.s("오늘도 나온 러닝", "Showing Up"),
                                 detail: L.s("나서는 것 자체가 이미 절반", "Getting out the door is already half the battle"))
        case .novice:
            return InsightResult(theme: .default,
                                 title: L.s("쌓이는 러닝", "Stacking Up"),
                                 detail: L.s("오늘도 꾸준히 쌓아갑니다", "Steady progress, one run at a time"))
        case .advanced, .elite:
            return InsightResult(theme: .default,
                                 title: L.s("자산 축적 러닝", "Banking Miles"),
                                 detail: L.s("꾸준한 훈련이 미래의 나를 만듭니다", "Consistent training builds the future you"))
        default:
            return InsightResult(theme: .default,
                                 title: L.s("자산 축적 러닝", "Banking Miles"),
                                 detail: L.s("오늘도 꾸준히 쌓아갑니다", "Steady progress, one run at a time"))
        }
    }
}
