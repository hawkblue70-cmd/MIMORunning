import Foundation

// MARK: - InsightEngine 시스템 요약
//
// ┌── 우선순위 체계 ──────────────────────────────────────────────┐
// │ 1. safety            안전·돌봄 (HR 과상승 / 더위 경보)       │
// │ 2. firstAchievement  생애 첫 거리 달성                       │
// │ 2. raceDay           대회 러닝                               │
// │ 2. recordImproved    동거리 최고 페이스 PR                   │
// │ 3. ── 동급 밴드(6종) ─── recency 타이브레이크 ─────────────  │
// │    · adverseCondition  날씨 악조건 (비/더위·추위/강풍)       │
// │    · tradeoff          지표 트레이드오프                     │
// │    · tempExtreme       기온 극값 (개인 분포 상하위 5%)       │
// │    · timeReunion       동일 시간대 60일+ 공백 후 재회        │
// │    · milestone         누적 이정표 ← 동급 중 항상 최우선    │
// │    · subThreshold      서브T 인터벌 절제 인정                │
// │ 4. distanceExpanded · consistent · periodPositive · recovery  │
// │ 5. default                                                    │
// └──────────────────────────────────────────────────────────────┘
//
// ┌── 밴드 fact 침묵 조건 ────────────────────────────────────────┐
// │ adverse      condition=nil / !hasAdverseSignal / 거리<1km   │
// │ tradeoff     조건 없음 (거리↑·페이스↓, 심박↑·EF↑ 등)       │
// │ tempExtreme  샘플<20 / 5‑95%ile 이내                        │
// │ timeReunion  동일 시간대 60일 이내에 달린 기록 있음          │
// │ milestone    현재 날짜 기준 이전 누적이 경계 미달             │
// │ subT         운동구간<2 / zone5≥3% / 페이스 CV≥8%           │
// └──────────────────────────────────────────────────────────────┘
//
// ┌── 시점 누적 원칙 ─────────────────────────────────────────────┐
// │ milestone·timeReunion은 prior 집계 시                        │
// │ filter { $0.date < a.date } 로 현재 런을 반드시 제외.        │
// │ 미제외 시 이정표 조기 발화 → 다음 런에서 재발화 안 하는     │
// │ 버그 발생. 이 원칙을 깨면 cacheVersion을 올려야 함.          │
// └──────────────────────────────────────────────────────────────┘
//
// ┌── title 소유 규칙 ────────────────────────────────────────────┐
// │ title은 규칙 엔진 단독 소유. AI는 detail만 재표현.           │
// │ AIInsightOutput에 title 필드 없음.                           │
// │ tryAIEnhance → InsightResult(title: base.title, …)           │
// │ isRefined=true 캐시도 title = 규칙 엔진 값 그대로.           │
// └──────────────────────────────────────────────────────────────┘
//
// ┌── 생성 상태 머신 ──────────────────────────────────────────────┐
// │ idle → (task 진입, 캐시 없음) → waiting(재료 로드)            │
// │     → (날씨 완료 OR 3초 타임아웃) → generating               │
// │     → (InsightCache.cache 저장) → cached                     │
// │ * cached: task 재진입 → fast path, 생성 0회                  │
// │ * generating 중 재진입 → claimRefinedCompute 실패 → skip      │
// │ * task 취소로 stale claim → 재진입 시 releaseRefinedCompute   │
// │ ⚠ 이중 실행 금지: Phase1+Phase3 구조가 발열 원인이었음       │
// └──────────────────────────────────────────────────────────────┘
//
// ┌── insightVersion(cacheVersion) 규칙 ──────────────────────────┐
// │ · 로직 변경 시 InsightCache.cacheVersion 정수 +1              │
// │ · 파일명에 버전 포함 → 구버전 캐시 자동 무시 (삭제 불요)     │
// │ · 현재: v11 (title 고정 풀·금지어 정비·AI title 차단 완료)   │
// └──────────────────────────────────────────────────────────────┘

// MARK: - Output types

enum InsightTheme: String, Codable {
    case firstAchievement
    case recordImproved
    case adverseCondition
    case distanceExpanded
    case consistent
    case recovery
    case raceDay
    case `default`
    case tradeoff       // paired-metric reframe of a down metric
    case periodPositive // period total is down — positive scan
    case safety         // safety/environment note (highest priority)
    case rarityFact     // temperature extreme, time-of-day reunion
    case milestone      // lifetime cumulative distance milestone (once per crossing — always wins ties)
    case subThreshold   // controlled effort acknowledgment (interval-structured runs only)
}

struct InsightResult: Codable {
    let theme: InsightTheme
    let workoutType: WorkoutType
    let title: String
    let detail: String
    var aiEnhanced: Bool = false

    init(theme: InsightTheme, workoutType: WorkoutType = .general, title: String, detail: String, aiEnhanced: Bool = false) {
        self.theme = theme
        self.workoutType = workoutType
        self.title = title
        self.detail = detail
        self.aiEnhanced = aiEnhanced
    }
}

// MARK: - Rule engine

struct InsightEngine {

    /// Compute the highest-priority insight for `activity` against full history.
    /// Priority: safety > firstAchievement > raceDay > recordImproved
    ///           > [adverseCondition ≈ tradeoff ≈ rarityFact ≈ milestone ≈ subThreshold]
    ///           > distanceExpanded > consistent > periodPositive > recovery > default
    /// Within the band, recency-based pick (oldest-shown theme wins); `.milestone` always wins ties.
    /// p5 fatigueSign → soften non-critical themes (UserDefaults.mimo_weekly_p5_fatigue_active).
    /// Safety combines with firstAchievement/raceDay rather than suppressing them.
    static func compute(
        activity: Activity,
        history: [Activity],
        level: LevelBucket = .beginner,
        workoutType: WorkoutType = .general,
        splits: [SplitData] = [],
        intervalSegments: [IntervalSegment] = [],
        condition: ActivityCondition? = nil,
        raceMatch: PersistedRaceMatch? = nil,
        detail: ActivityDetail? = nil
    ) -> InsightResult {
        let prior = history.filter { $0.id != activity.id && $0.type == activity.type }

        var base: InsightResult
        #if DEBUG
        var _dbgFacts = "[]"
        var _dbgReason = "n/a"
        #endif
        // Safety is the highest priority. For once-in-a-lifetime achievements (firstAchievement,
        // raceDay), safety becomes the title and the achievement is embedded in the detail line.
        let safetyCandidate = safetyNote(activity, prior, condition: condition)
        if let safety = safetyCandidate {
            if let r = firstAchievement(activity, prior, raceMatch: raceMatch) {
                base = InsightResult(theme: .safety, title: safety.title,
                                     detail: "\(safety.detail) · \(r.detail)")
            } else if let rm = raceMatch, rm.isConfirmed {
                let r = raceDayInsight(rm)
                base = InsightResult(theme: .safety, title: safety.title,
                                     detail: "\(safety.detail) · \(r.detail)")
            } else {
                base = safety
            }
        } else if let r = firstAchievement(activity, prior, raceMatch: raceMatch) {
            base = r
        } else if let rm = raceMatch, rm.isConfirmed {
            base = raceDayInsight(rm)
        } else if level >= .novice, let r = recordImproved(activity, prior, level: level) {
            base = r
        } else {
            // Same-priority band: adverseCondition ≈ tradeoff ≈ rarityFact ≈ subThreshold.
            // Collect all candidates then pick by recency (oldest-shown theme wins).
            var band: [InsightResult] = []
            if let r = adverseCondition(activity, condition) { band.append(r) }
            if let r = tradeoffInsight(activity, prior, detail: detail, splits: splits) { band.append(r) }
            if let r = rarityFact(activity, prior, condition: condition) { band.append(r) }
            if let r = subThresholdRecognition(activity, intervalSegments, detail) { band.append(r) }

            #if DEBUG
            _dbgFacts = buildBandFactLog(activity, prior, condition: condition,
                                         intervalSegments: intervalSegments, detail: detail, splits: splits)
            let _histBefore = loadThemeHistory()
            #endif

            if let r = pickByRecency(band) {
                base = r
                #if DEBUG
                let _wasNew = !_histBefore.contains(r.theme.rawValue)
                _dbgReason = band.count == 1 ? "단독후보" : (_wasNew ? "우선순위동급-미노출우선" : "우선순위동급-반복방지")
                #endif
            } else if let r = distanceExpanded(activity, prior) {
                base = r
                #if DEBUG
                _dbgReason = "band없음→distanceExpanded"
                #endif
            } else if let r = consistent(activity, prior, level: level) {
                base = r
                #if DEBUG
                _dbgReason = "band없음→consistent"
                #endif
            } else if let r = periodicPositive(activity, prior) {
                base = r
                #if DEBUG
                _dbgReason = "band없음→periodPositive"
                #endif
            } else if level >= .novice, let r = recovery(activity, prior, level: level) {
                base = r
                #if DEBUG
                _dbgReason = "band없음→recovery"
                #endif
            } else {
                base = defaultInsight(activity, prior, level: level)
                #if DEBUG
                _dbgReason = "band없음→default"
                #endif
            }
        }

        // p5 weekly fatigue: soften non-critical themes when GrowthView signals fatigue
        if isWeeklyFatigueActive() { base = applyFatigueContext(base) }

        #if DEBUG
        if _dbgReason == "n/a" { _dbgReason = base.theme.rawValue }
        let _p5Tag = isWeeklyFatigueActive() ? " [p5]" : ""
        let _dateStr: String = {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: activity.date)
        }()
        let _distStr = String(format: "%.1fkm", activity.distance / 1000)
        print("[DetailInsight] 재생성 activity=\(activity.id)(\(_dateStr), \(_distStr)) facts=\(_dbgFacts) selected=\(base.theme.rawValue) reason=\(_dbgReason)\(_p5Tag) title=\"\(base.title)\"")
        #endif

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
                  base.theme != .raceDay, base.theme != .tradeoff,
                  base.theme != .periodPositive, base.theme != .safety,
                  base.theme != .rarityFact, base.theme != .milestone,
                  base.theme != .subThreshold else { return base }
            let L = AppLanguage.shared
            let title: String
            if base.theme == .recordImproved {
                title = L.s("기록을 깬 인터벌", "PR Interval")
            } else {
                title = pick(
                    [L.s("차오르는 인터벌", "Surging Intervals"),
                     L.s("스피드를 깨운 인터벌", "Speed Awakened"),
                     L.s("호흡을 끌어올린 인터벌", "Breath-Pushing Intervals")],
                    date: activity.date
                )
            }
            let detail = intervalDetailString(intervalSegments: intervalSegments, splits: splits)
            return InsightResult(theme: base.theme, title: title, detail: detail)

        case .longRun:
            guard base.theme != .firstAchievement, base.theme != .adverseCondition,
                  base.theme != .raceDay, base.theme != .tradeoff,
                  base.theme != .periodPositive, base.theme != .safety,
                  base.theme != .rarityFact, base.theme != .milestone,
                  base.theme != .subThreshold else { return base }
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
                detail = L.s("장거리 완주 \(activity.formattedDistance)", "Long run complete: \(activity.formattedDistance)")
            }
            return InsightResult(theme: base.theme, title: title, detail: detail)

        case .easy:
            guard base.theme != .firstAchievement, base.theme != .adverseCondition,
                  base.theme != .raceDay, base.theme != .tradeoff,
                  base.theme != .periodPositive, base.theme != .safety,
                  base.theme != .rarityFact, base.theme != .milestone,
                  base.theme != .subThreshold else { return base }
            let L = AppLanguage.shared
            return InsightResult(theme: .recovery,
                                 title: L.s("숨을 고른 이지런", "Easy Does It"),
                                 detail: L.s("낮은 강도로 다음 훈련을 준비", "Low effort, prepping for the next session"))

        case .tempo:
            guard base.theme != .firstAchievement, base.theme != .adverseCondition,
                  base.theme != .raceDay, base.theme != .tradeoff,
                  base.theme != .periodPositive, base.theme != .safety,
                  base.theme != .rarityFact, base.theme != .milestone,
                  base.theme != .subThreshold else { return base }
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

        case .buildUp:
            guard base.theme != .firstAchievement, base.theme != .adverseCondition,
                  base.theme != .raceDay, base.theme != .tradeoff,
                  base.theme != .periodPositive, base.theme != .safety,
                  base.theme != .rarityFact, base.theme != .milestone,
                  base.theme != .subThreshold else { return base }
            let L = AppLanguage.shared
            let title = base.theme == .recordImproved
                ? L.s("기록을 쓴 빌드업", "PR Build-Up")
                : pick([L.s("후반이 가장 빨랐던 빌드업", "Fastest at the Finish"),
                        L.s("끝으로 갈수록 강해진 러닝", "Getting Stronger"),
                        L.s("마지막을 위해 달린 빌드업", "Saving the Best for Last")],
                       date: activity.date)
            let detail = base.theme == .recordImproved
                ? base.detail
                : L.s("후반이 가장 빨랐어요 — 빌드업의 정석", "Last splits your fastest — textbook buildup")
            return InsightResult(theme: base.theme, title: title, detail: detail)

        case .lsd:
            guard base.theme != .firstAchievement, base.theme != .adverseCondition,
                  base.theme != .raceDay, base.theme != .tradeoff,
                  base.theme != .periodPositive, base.theme != .safety,
                  base.theme != .rarityFact, base.theme != .milestone,
                  base.theme != .subThreshold else { return base }
            let L = AppLanguage.shared
            let title = pick([L.s("느리게 길게 간 LSD", "Long Slow Distance"),
                              L.s("유산소 엔진을 키운 LSD", "Aerobic Engine Builder"),
                              L.s("천천히 멀리 간 러닝", "Slow and Far")],
                             date: activity.date)
            return InsightResult(theme: base.theme, title: title,
                                 detail: L.s("느리게 길게, 유산소 엔진을 키운 시간 \(activity.formattedDistance)",
                                             "Slow and steady for \(activity.formattedDistance) — building the aerobic base"))

        case .distanceRun:
            guard base.theme != .firstAchievement, base.theme != .adverseCondition,
                  base.theme != .raceDay, base.theme != .tradeoff,
                  base.theme != .periodPositive, base.theme != .safety,
                  base.theme != .rarityFact, base.theme != .milestone,
                  base.theme != .subThreshold else { return base }
            let L = AppLanguage.shared
            let title = base.theme == .recordImproved
                ? L.s("기록을 쓴 거리주", "PR Distance Run")
                : pick([L.s("레이스처럼 달린 거리주", "Race-Intent Distance Run"),
                        L.s("목표 페이스로 달린 거리주", "Goal-Pace Distance Run"),
                        L.s("강도 있게 달린 거리주", "Quality Distance Run")],
                       date: activity.date)
            let detail = base.theme == .recordImproved
                ? base.detail
                : L.s("긴 거리를 페이스 잡아 완주 — \(activity.formattedDistance)",
                      "\(activity.formattedDistance) with race intent — well executed")
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
    // Snap raw GPS distance to nearest standard interval distance within ±8%
    private static let standardDistances = [
        100, 200, 300, 400, 500, 600, 800,
        1000, 1200, 1500, 1600, 2000, 3000, 4000, 5000
    ]

    private static func recognizedDistLabel(_ meters: Double) -> String {
        let snapped: Int
        if let s = standardDistances.first(where: { abs(Double($0) - meters) / Double($0) <= 0.08 }) {
            snapped = s
        } else {
            snapped = meters >= 200 ? Int((meters / 100).rounded()) * 100 : Int((meters / 50).rounded()) * 50
        }
        if snapped >= 1000 {
            return snapped % 1000 == 0 ? "\(snapped / 1000)km" : String(format: "%.1fkm", Double(snapped) / 1000)
        }
        return "\(snapped)m"
    }

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
            let distStr = avgDist.map { recognizedDistLabel($0) }
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
                        L.s("동일 거리 페이스 갱신 — 꾸준히 나아지고 있어요", "PR on same distance — steady improvement"))
            default:
                return (L.s("페이스가 자란 러닝", "Growing Pace"),
                        L.s("최근 동일 거리 중 가장 빠른 페이스 \(a.formattedPace ?? "")",
                            "Fastest pace on this distance recently: \(a.formattedPace ?? "")"))
            }
        }()
        return InsightResult(theme: .recordImproved, title: title, detail: detail)
    }

    /// Longest run this week or this calendar month (≥ 5 km).
    /// Weekly checked first — more immediate achievement; falls back to monthly.
    /// Requires ≥1 prior run in the same window — avoids triggering on the first run of a week/month.
    private static func distanceExpanded(_ a: Activity, _ prior: [Activity]) -> InsightResult? {
        guard a.distance / 1000 >= 5 else { return nil }
        let cal = Calendar.current
        let L = AppLanguage.shared

        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: a.date)) ?? .distantPast
        let priorThisWeek = prior.filter { $0.date >= weekStart }
        let distanceTitles = [L.s("경계를 넓힌 러닝", "Expanding Boundaries"),
                              L.s("낯선 거리를 만난 날", "Into New Distance"),
                              L.s("거리의 문을 연 러닝", "Opening New Distance")]
        if !priorThisWeek.isEmpty, let maxWeek = priorThisWeek.map(\.distance).max(),
           a.distance > maxWeek {
            let idx = nextTitleIdx(for: "distanceExpanded", poolSize: 3)
            return InsightResult(theme: .distanceExpanded,
                                 title: distanceTitles[idx],
                                 detail: L.s("이번 주 최장 거리 \(a.formattedDistance)", "Longest run this week: \(a.formattedDistance)"))
        }

        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: a.date)) ?? .distantPast
        let priorThisMonth = prior.filter { $0.date >= monthStart }
        guard !priorThisMonth.isEmpty, let maxMonth = priorThisMonth.map(\.distance).max(),
              a.distance > maxMonth else { return nil }
        let idx = nextTitleIdx(for: "distanceExpanded", poolSize: 3)
        return InsightResult(theme: .distanceExpanded,
                             title: distanceTitles[idx],
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
            let prevWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekAnchor) ?? weekAnchor
            if priorWeekStarts.contains(prevWeekStart) {
                streak += 1
                weekAnchor = prevWeekStart
            } else {
                break
            }
        }
        let L = AppLanguage.shared
        let consistentTitles = [L.s("꾸준함이 쌓이는 러닝", "Building Consistency"),
                                L.s("쌓이는 러닝", "Stacking Up"),
                                L.s("이어지는 러닝", "Keeping It Going")]
        if streak >= streakThreshold {
            let idx = nextTitleIdx(for: "consistent", poolSize: 3)
            return InsightResult(theme: .consistent,
                                 title: consistentTitles[idx],
                                 detail: L.s("\(streak)주 연속 러닝", "\(streak) weeks in a row"))
        }

        let thisWeekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: a.date)
        ) ?? a.date
        let thisWeekCount = prior.filter { $0.date >= thisWeekStart }.count + 1
        let weekCountThreshold = level == .beginner ? 2 : 3
        if thisWeekCount >= weekCountThreshold {
            let idx = nextTitleIdx(for: "consistent", poolSize: 3)
            return InsightResult(theme: .consistent,
                                 title: consistentTitles[idx],
                                 detail: L.s("이번 주 \(thisWeekCount)번째 러닝", "Run #\(thisWeekCount) this week"))
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
                                     title: L.s("궂은 날의 완주", "Finishing Through It"),
                                     detail: L.s("\(w.formattedTemp) 더위에도 끝까지", "\(w.formattedTemp) heat, but you finished"))
            }
            if w.isCold {
                return InsightResult(theme: .adverseCondition,
                                     title: L.s("궂은 날의 완주", "Finishing Through It"),
                                     detail: L.s("\(w.formattedTemp) — 나오는 것만으로도 반", "\(w.formattedTemp) — getting out was half the battle"))
            }
            return InsightResult(theme: .adverseCondition,
                                 title: L.s("바람을 가른 러닝", "Into the Wind"),
                                 detail: L.s("강풍 속에서도 멈추지 않았어요", "Strong winds, but you didn't stop"))
        }
        return nil
    }

    // MARK: - Async compute (cache-friendly entry point)

    /// Async wrapper around `compute` — enables cache checks at call sites before invoking the
    /// synchronous rule engine. Marking async lets `.task` callers interleave UI work between
    /// suspension points without a perceptible delay on the detail view.
    static func computeBackground(
        activity: Activity,
        history: [Activity],
        level: LevelBucket = .beginner,
        workoutType: WorkoutType = .general,
        splits: [SplitData] = [],
        intervalSegments: [IntervalSegment] = [],
        condition: ActivityCondition? = nil,
        raceMatch: PersistedRaceMatch? = nil,
        detail: ActivityDetail? = nil
    ) async -> InsightResult {
        compute(activity: activity, history: history, level: level,
                workoutType: workoutType, splits: splits,
                intervalSegments: intervalSegments, condition: condition,
                raceMatch: raceMatch, detail: detail)
    }

    // MARK: - AI enhancement bridge

    /// Attempts on-device AI rewrite (iOS 26+). Returns nil on older OS or failure;
    /// callers keep the rule-based result as-is.
    static func tryAIEnhance(_ base: InsightResult) async -> InsightResult? {
        guard !base.aiEnhanced else { return nil }  // already enhanced, skip
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard let enhanced = await InsightAIGenerator.enhance(base) else { return nil }
            // Title always comes from the rule engine (base) — AI may only rewrite detail.
            return InsightResult(theme: base.theme, workoutType: base.workoutType,
                                 title: base.title, detail: enhanced.detail, aiEnhanced: true)
        }
        #endif
        return nil
    }

    // MARK: - Safety / environment notes

    /// Personal-safety check.
    /// Order: HR elevation vs own pace-band (C-1, non-hot only) → heat care (C-2).
    /// All comparisons are personal-relative. Silence when sample count is insufficient.
    private static func safetyNote(
        _ a: Activity,
        _ prior: [Activity],
        condition: ActivityCondition?
    ) -> InsightResult? {
        let isHot = condition?.weather?.isHot ?? false
        if !isHot, let r = hrElevatedNote(a, prior) { return r }
        if isHot,  let r = heatCareNote(a, prior)   { return r }
        return nil
    }

    /// C-1: Current avg HR ≥8% above the user's own baseline at the same pace band (±5 s/km).
    /// Requires ≥5 prior samples in that band. Not called when conditions are hot — caller gates this.
    /// Scanned against most-recent 60 runs to bound cost (pace-band match is O(n)).
    private static func hrElevatedNote(_ a: Activity, _ prior: [Activity]) -> InsightResult? {
        guard let currentPace = a.paceSecPerKm, let currentHR = a.avgHeartRate else { return nil }
        let bandHRs = prior.prefix(60)
            .filter { guard let p = $0.paceSecPerKm else { return false }; return abs(p - currentPace) <= 5.0 }
            .compactMap(\.avgHeartRate)
        guard bandHRs.count >= 5 else { return nil }
        let avgBandHR = Double(bandHRs.reduce(0, +)) / Double(bandHRs.count)
        guard Double(currentHR) >= avgBandHR * 1.08 else { return nil }
        let L = AppLanguage.shared
        let excess = Int((Double(currentHR) - avgBandHR).rounded())
        return InsightResult(
            theme: .safety,
            title: L.s("오늘 심박이 평소보다 높았어요", "Heart Rate Above Your Norm"),
            detail: L.s("같은 페이스대에서 평소보다 약 \(excess)bpm 높았어요. 충분한 회복을 챙기세요",
                        "Avg ~\(excess) bpm above your baseline at this pace. Prioritize recovery today")
        )
    }

    /// C-2: Hot-weather care — hydration/recovery reminder.
    /// isLong is personal: distance > recent avg × 1.20.
    private static func heatCareNote(_ a: Activity, _ prior: [Activity]) -> InsightResult? {
        let L = AppLanguage.shared
        let recentDists = prior.prefix(10).map(\.distance)
        let isLong: Bool = {
            guard recentDists.count >= 3 else { return a.distance >= 10_000 }
            let avg = recentDists.reduce(0, +) / Double(recentDists.count)
            return a.distance > avg * 1.20
        }()

        let variants: [(String, String)] = isLong
            ? [(L.s("더위 속 장거리 — 잘 해냈어요", "Long Run in the Heat — Well Done"),
                L.s("더운 날 장거리는 심박을 더 올려요. 수분과 염분을 충분히 보충하세요",
                    "Heat raises HR on long runs. Rehydrate and replenish electrolytes")),
               (L.s("열기를 이겨낸 장거리", "Enduring the Heat"),
                L.s("고온 장거리는 몸에 더 큰 자극 — 오늘 충분히 쉬세요",
                    "Long runs in heat hit harder — make sure to rest well today")),
               (L.s("더운 날의 긴 거리", "Distance in the Heat"),
                L.s("고온 장거리 완주. 심박이 더 올라가는 건 정상이에요. 수분 잊지 마세요",
                    "Distance in heat done. Elevated HR is normal — stay hydrated"))]
            : [(L.s("더운 날 잘 뛰었어요", "Great Run in the Heat"),
                L.s("더운 날씨엔 심박이 자연스럽게 올라요 — 수분 잊지 마세요",
                    "Heat naturally raises HR — don't forget to hydrate")),
               (L.s("열기 속 러닝 완료", "Run Complete in the Heat"),
                L.s("고온에서도 완주 — 가벼운 음식과 수분으로 회복하세요",
                    "Finished in the heat — recover with fluids and light food")),
               (L.s("더위와 함께 달린 러닝", "Running Through the Heat"),
                L.s("더운 날 나선 것 자체가 이미 대단해요. 충분히 수분 보충하세요",
                    "Getting out in the heat is already impressive — keep hydrating"))]

        let idx = Int(abs(a.date.timeIntervalSinceReferenceDate)) % variants.count
        let (title, detail) = variants[idx]
        return InsightResult(theme: .safety, title: title, detail: detail)
    }

    // MARK: - Tradeoff interpretation

    /// Re-frames a down metric by pairing it with a counter-metric that improved.
    /// Checks in order: efficiency gain · endurance buildup · stride training · form work · speed at cost.
    private static func tradeoffInsight(
        _ a: Activity,
        _ prior: [Activity],
        detail: ActivityDetail?,
        splits: [SplitData]
    ) -> InsightResult? {
        let recentPrior = Array(prior.prefix(10))
        guard !recentPrior.isEmpty, let currentPace = a.paceSecPerKm else { return nil }

        let L = AppLanguage.shared
        let priorPaces = recentPrior.compactMap(\.paceSecPerKm)
        guard !priorPaces.isEmpty else { return nil }
        let avgPriorPace = priorPaces.reduce(0, +) / Double(priorPaces.count)

        let priorHRs     = recentPrior.compactMap(\.avgHeartRate)
        let avgPriorHR   = priorHRs.isEmpty ? nil : Double(priorHRs.reduce(0, +)) / Double(priorHRs.count)
        let avgPriorDist = recentPrior.map(\.distance).reduce(0, +) / Double(recentPrior.count)

        // 1. Pace maintained (±4%) + HR down ≥5% → efficiency gain
        if let hr = a.avgHeartRate, let avgHR = avgPriorHR {
            let paceVar = abs(currentPace - avgPriorPace) / avgPriorPace
            let hrDrop  = (avgHR - Double(hr)) / avgHR
            if paceVar <= 0.04 && hrDrop >= 0.05 {
                let bpm = Int((avgHR - Double(hr)).rounded())
                return InsightResult(
                    theme: .tradeoff,
                    title: L.s("심폐가 단단해지는 러닝", "Efficiency Rising"),
                    detail: L.s("같은 페이스, 평균 심박 \(bpm)bpm 감소", "Same pace, avg HR down \(bpm) bpm")
                )
            }
        }

        // 2. Pace ≥8% slower + Distance ≥20% longer → endurance buildup
        if currentPace > avgPriorPace * 1.08 && a.distance > avgPriorDist * 1.20 {
            return InsightResult(
                theme: .tradeoff,
                title: L.s("지구력을 쌓는 러닝", "Endurance Buildup"),
                detail: L.s("더 멀리 \(a.formattedDistance) — 페이스는 거리를 위해 양보",
                            "\(a.formattedDistance) — pace yielded to distance")
            )
        }

        // Watch-data tradeoffs (only when ActivityDetail is available)
        if let det = detail {
            // 3. Notable stride (>1.0 m) + low cadence (<162 spm) → stride-focus training
            if let strideM = det.avgStrideLength, strideM > 1.0 {
                let splitCadences = splits.compactMap(\.avgCadence).map(Double.init)
                if !splitCadences.isEmpty {
                    let avgCadence = splitCadences.reduce(0, +) / Double(splitCadences.count)
                    if avgCadence < 162 {
                        return InsightResult(
                            theme: .tradeoff,
                            title: L.s("보폭이 자라는 러닝", "Stride Growing"),
                            detail: L.s("보폭 \(String(format: "%.2f", strideM))m · 케이던스를 내주고 거리를 얻는 중",
                                        "Stride \(String(format: "%.2f", strideM)) m · trading cadence for stride")
                        )
                    }
                }
            }

            // 4. Pace ≥6% slower + vertical oscillation ≤7.5 cm → form/economy work
            if let vertOsc = det.avgVerticalOscillation,
               currentPace > avgPriorPace * 1.06, vertOsc <= 7.5 {
                return InsightResult(
                    theme: .tradeoff,
                    title: L.s("폼이 다듬어지는 러닝", "Form Refinement"),
                    detail: L.s("수직 진폭 \(String(format: "%.1f", vertOsc))cm — 에너지 손실 최소화 중",
                                "Vert. osc. \(String(format: "%.1f", vertOsc)) cm — cutting energy loss")
                )
            }
        }

        // 5. Pace ≥5% faster + HR ≥5% higher → speed at justified cost
        if let hr = a.avgHeartRate, let avgHR = avgPriorHR,
           currentPace < avgPriorPace * 0.95, Double(hr) > avgHR * 1.05 {
            return InsightResult(
                theme: .tradeoff,
                title: L.s("스피드의 정당한 대가", "Speed Worth Paying For"),
                detail: L.s("페이스 \(a.formattedPace ?? "") — 심박이 그 값을 지불",
                            "Pace \(a.formattedPace ?? "") — HR paid the price")
            )
        }

        return nil
    }

    // MARK: - Multi-angle positive scan

    /// When this calendar month's total distance/count is down vs the prior month, scans in priority
    /// order for a positive fact: pace quality → peak distance → weekly streak → milestone → recovery block.
    /// Always returns a result once triggered (activity count > 0 means a positive exists).
    private static func periodicPositive(_ a: Activity, _ prior: [Activity]) -> InsightResult? {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: a.date)) ?? .distantPast
        guard let prevMonthStart = cal.date(byAdding: .month, value: -1, to: monthStart) else { return nil }

        let thisMonthPrior = prior.filter { $0.date >= monthStart }
        let prevMonthActs  = prior.filter { $0.date >= prevMonthStart && $0.date < monthStart }
        guard !prevMonthActs.isEmpty else { return nil }

        let thisMonthDist  = thisMonthPrior.reduce(0.0) { $0 + $1.distance } + a.distance
        let prevMonthDist  = prevMonthActs.reduce(0.0)  { $0 + $1.distance }
        let thisMonthCount = thisMonthPrior.count + 1
        let prevMonthCount = prevMonthActs.count

        // Trigger when month is notably behind: distance < 80% OR count already lower with ≥3 prior runs
        let distDown  = prevMonthDist > 0 && thisMonthDist < prevMonthDist * 0.80
        let countDown = prevMonthCount >= 3 && thisMonthCount < prevMonthCount
        guard distDown || countDown else { return nil }

        let L = AppLanguage.shared

        // 1. Average pace better this month?
        if let currentPace = a.paceSecPerKm {
            let thisPaces = thisMonthPrior.compactMap(\.paceSecPerKm) + [currentPace]
            let prevPaces = prevMonthActs.compactMap(\.paceSecPerKm)
            if !prevPaces.isEmpty {
                let thisAvg = thisPaces.reduce(0, +) / Double(thisPaces.count)
                let prevAvg = prevPaces.reduce(0, +) / Double(prevPaces.count)
                if thisAvg < prevAvg * 0.97 {
                    return InsightResult(
                        theme: .periodPositive,
                        title: L.s("밀도가 높아진 러닝", "Quality Over Quantity"),
                        detail: L.s("횟수는 줄었지만 이달 평균 페이스 향상", "Fewer runs, better avg pace this month")
                    )
                }
            }
        }

        // 2. Best single run this month ≥ best last month?
        let prevMonthMaxDist = prevMonthActs.map(\.distance).max() ?? 0
        if a.distance > prevMonthMaxDist {
            return InsightResult(
                theme: .periodPositive,
                title: L.s("집중된 달의 러닝", "Peak Run of the Month"),
                detail: L.s("이달 최고 거리 \(a.formattedDistance) — 적게 뛰어도 깊게",
                            "Best run this month: \(a.formattedDistance)")
            )
        }

        // 3. No week skipped so far this month?
        let allWeekStarts = Set(
            (thisMonthPrior + [a]).map {
                cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.date)) ?? $0.date
            }
        )
        let weeksElapsed = max(1, cal.component(.weekOfMonth, from: a.date))
        if allWeekStarts.count >= weeksElapsed {
            return InsightResult(
                theme: .periodPositive,
                title: L.s("꾸준히 이어가는 러닝", "Steady Every Week"),
                detail: L.s("달리기 횟수는 적어도 매주 빠지지 않았어요", "Fewer runs, but every week still counted")
            )
        }

        // 4. Cumulative lifetime distance milestone?
        let priorTotal   = prior.reduce(0.0) { $0 + $1.distance }
        let currentTotal = priorTotal + a.distance
        for km in [100, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 5000] {
            let m = Double(km) * 1000
            if priorTotal < m && currentTotal >= m {
                return InsightResult(
                    theme: .periodPositive,
                    title: L.s("이정표를 넘은 러닝", "Milestone Reached"),
                    detail: L.s("누적 \(km)km 돌파", "Lifetime total: \(km) km")
                )
            }
        }

        // 5. High-load block followed by deliberate recovery (recent 4 wks < 70% of prev 4 wks)?
        let fourWeeksAgo  = cal.date(byAdding: .weekOfYear, value: -4, to: a.date) ?? .distantPast
        let eightWeeksAgo = cal.date(byAdding: .weekOfYear, value: -8, to: a.date) ?? .distantPast
        let recent4Dist   = prior.filter { $0.date >= fourWeeksAgo }.reduce(0.0) { $0 + $1.distance }
        let prev4to8Dist  = prior.filter { $0.date >= eightWeeksAgo && $0.date < fourWeeksAgo }.reduce(0.0) { $0 + $1.distance }
        if prev4to8Dist > 0 && recent4Dist < prev4to8Dist * 0.70 {
            return InsightResult(
                theme: .periodPositive,
                title: L.s("부하를 내린 러닝", "Down Week Done Right"),
                detail: L.s("고부하 이후 몸을 가다듬는 회복 블록", "Post-load recovery block — intentional, not accidental")
            )
        }

        // Fallback — showing up in a lighter month is itself a positive
        return InsightResult(
            theme: .periodPositive,
            title: L.s("쉬운 달에도 이어가는 러닝", "Keeping the Base"),
            detail: L.s("쉬운 달에도 나선 것 자체가 이미 자산", "Showing up in a lighter month still builds the base")
        )
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

    // MARK: - Rarity facts

    /// Umbrella collector. Tries: temperature extreme → time-of-day reunion → cumulative 50 km milestone.
    /// Also records current run's temperature for distribution tracking (deduped by activity ID).
    private static func rarityFact(
        _ a: Activity,
        _ prior: [Activity],
        condition: ActivityCondition?
    ) -> InsightResult? {
        if let tempC = condition?.weather?.tempC { recordTemperature(tempC, for: a.id) }
        let historicalTemps = loadTemperatureHistory()
        if let r = temperatureExtreme(a, condition: condition, historicalTemps: historicalTemps) { return r }
        if let r = timeOfDayReunion(a, prior) { return r }
        if let r = cumulativeMilestone(a, prior) { return r }
        return nil
    }

    /// Fires when today's temperature is in the top/bottom 5% of the user's personal run-temperature
    /// distribution. Silence when fewer than 20 samples exist.
    private static func temperatureExtreme(
        _ a: Activity,
        condition: ActivityCondition?,
        historicalTemps: [Double]
    ) -> InsightResult? {
        guard let tempC = condition?.weather?.tempC, historicalTemps.count >= 20 else { return nil }
        let sorted = historicalTemps.sorted()
        let n = sorted.count
        let rank = sorted.filter { $0 <= tempC }.count
        let percentile = Double(rank) / Double(n)
        let L = AppLanguage.shared
        if percentile >= 0.95 {
            let idx = nextTitleIdx(for: "tempHot", poolSize: 3)
            let titles = [L.s("가장 더운 축의 러닝", "One of Your Hottest Runs"),
                          L.s("기온 상위 5%의 러닝", "Top 5% Heat Run"),
                          L.s("뜨거운 날의 러닝", "Peak Heat Run")]
            let details = [L.s("오늘 기온은 본인 러닝 기온 분포 상위 5% 이내예요", "Today's temp is within your top 5% running conditions"),
                           L.s("이 더위에 달린 건 \(n)번의 기록 중 드문 편이에요", "Running in this heat is rare across your \(n) recorded runs"),
                           L.s("본인 기온 분포 극단 — 더위 속 완주", "Near the extreme of your personal temperature range")]
            return InsightResult(theme: .rarityFact, title: titles[idx], detail: details[idx])
        }
        if percentile <= 0.05 {
            let idx = nextTitleIdx(for: "tempCold", poolSize: 3)
            let titles = [L.s("가장 추운 축의 러닝", "One of Your Coldest Runs"),
                          L.s("기온 하위 5%의 러닝", "Bottom 5% Cold Run"),
                          L.s("혹한 속 러닝", "Into the Cold")]
            let details = [L.s("오늘 기온은 본인 러닝 기온 분포 하위 5% 이내예요", "Today's temp is within your bottom 5% running conditions"),
                           L.s("이 추위에 달린 건 \(n)번의 기록 중 드문 편이에요", "Running in this cold is rare across your \(n) recorded runs"),
                           L.s("본인 기온 분포 극단 — 혹한 속 완주", "Near the extreme of your personal temperature range")]
            return InsightResult(theme: .rarityFact, title: titles[idx], detail: details[idx])
        }
        return nil
    }

    /// Same time-slot (dawn/morning/midday/evening/night) last visited >60 days ago → "N개월 만의 OO 러닝".
    /// First-ever visit to that slot → "첫 OO 러닝".
    private static func timeOfDayReunion(_ a: Activity, _ prior: [Activity]) -> InsightResult? {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: a.date)

        func slotID(for h: Int) -> Int {
            switch h { case 4..<7: return 0; case 7..<11: return 1; case 11..<16: return 2; case 16..<20: return 3; default: return 4 }
        }
        let slot = slotID(for: hour)
        let (koName, enName): (String, String) = [("새벽","dawn"),("오전","morning"),("낮","midday"),("저녁","evening"),("밤","night")][slot]

        let sameSlot = prior.filter { slotID(for: cal.component(.hour, from: $0.date)) == slot && $0.date < a.date }
        let L = AppLanguage.shared

        if sameSlot.isEmpty {
            let idx = nextTitleIdx(for: "timeFirst", poolSize: 3)
            let titles = [L.s("첫 \(koName) 러닝", "First \(enName.capitalized) Run"),
                          L.s("\(koName)에 처음 달린 러닝", "Running at \(enName.capitalized) for the First Time"),
                          L.s("\(koName) 러닝 첫 경험", "\(enName.capitalized) Run Debut")]
            let details = [L.s("처음으로 \(koName)에 달렸어요", "First time running in the \(enName)"),
                           L.s("\(koName) 러닝 첫 기록 — 시간대의 문을 열었어요", "First \(enName) run logged — a new window opens"),
                           L.s("지금까지 \(koName)엔 달린 기록이 없었어요", "No prior runs at this time of day")]
            return InsightResult(theme: .rarityFact, title: titles[idx], detail: details[idx])
        }
        guard let lastVisit = sameSlot.max(by: { $0.date < $1.date }) else { return nil }
        let days = cal.dateComponents([.day], from: lastVisit.date, to: a.date).day ?? 0
        guard days >= 60 else { return nil }
        let months = max(1, (days + 14) / 30)

        let idx = nextTitleIdx(for: "timeReunion", poolSize: 3)
        let titles = [L.s("\(months)개월 만의 \(koName) 러닝", "\(enName.capitalized) Run After \(months) Months"),
                      L.s("오랜만의 \(koName) 러닝", "Back to \(enName.capitalized) Running"),
                      L.s("\(months)개월 만에 다시 \(koName)에", "Back at \(enName.capitalized) After \(months) Months")]
        let details = [L.s("\(months)개월 만에 다시 \(koName)에 달렸어요", "Back to \(enName) runs after \(months) months"),
                       L.s("마지막 \(koName) 러닝이 \(days)일 전이었어요", "Your last \(enName) run was \(days) days ago"),
                       L.s("오래된 시간대로 돌아왔어요 — \(months)개월 만", "Old time slot revisited — \(months) months later")]
        return InsightResult(theme: .rarityFact, title: titles[idx], detail: details[idx])
    }

    /// Fires when this run crosses any 50 km cumulative lifetime boundary.
    private static func cumulativeMilestone(_ a: Activity, _ prior: [Activity]) -> InsightResult? {
        let priorM   = prior.filter { $0.date < a.date }.reduce(0.0) { $0 + $1.distance }
        let currentM = priorM + a.distance
        let priorKm  = priorM   / 1000
        let curKm    = currentM / 1000
        let nextMark = (Int(priorKm / 50) + 1) * 50
        guard curKm >= Double(nextMark) else { return nil }
        let km = nextMark
        let L = AppLanguage.shared
        let idx = nextTitleIdx(for: "milestone", poolSize: 3)
        let titles = [L.s("누적 \(km)km의 발자국", "\(km) km of Footprints"),
                      L.s("\(km)km 이정표를 넘은 러닝", "Crossing \(km) km Total"),
                      L.s("\(km)km이 쌓인 날", "\(km) km — Day It Stacked Up")]
        let details = [L.s("이 러닝으로 누적 \(km)km에 도달했어요", "This run brought your total to \(km) km"),
                       L.s("한 걸음 한 걸음 쌓아 \(km)km", "Step by step to \(km) km"),
                       L.s("누적 \(Int(curKm))km — \(km)km 이정표 통과", "Lifetime: \(Int(curKm)) km, past the \(km) km mark")]
        return InsightResult(theme: .milestone, title: titles[idx], detail: details[idx])
    }

    // MARK: - SubThreshold recognition

    /// Fires only for interval-structured runs (≥2 work steps) when:
    ///   (a) HR zone 5 fraction < 3% of total tracked HR time (or no HR zone data), AND
    ///   (b) work-step pace CV < 8% (consistent pacing across all reps).
    /// Acknowledges controlled discipline — no prescription, no set-count.
    private static func subThresholdRecognition(
        _ a: Activity,
        _ intervalSegments: [IntervalSegment],
        _ detail: ActivityDetail?
    ) -> InsightResult? {
        let workSteps = intervalSegments.filter { $0.stepLabel == "운동" }
        guard workSteps.count >= 2 else { return nil }

        if let hrZones = detail?.hrZones, !hrZones.isEmpty {
            let z5Fraction = hrZones.first(where: { $0.id == 5 })?.fraction ?? 0.0
            guard z5Fraction < 0.03 else { return nil }
        }

        let workPaces = workSteps.compactMap(\.paceSecPerKm)
        guard workPaces.count >= 2 else { return nil }
        let mean = workPaces.reduce(0, +) / Double(workPaces.count)
        guard mean > 0 else { return nil }
        let variance = workPaces.map { pow($0 - mean, 2) }.reduce(0, +) / Double(workPaces.count)
        let cv = sqrt(variance) / mean
        guard cv < 0.08 else { return nil }

        let L = AppLanguage.shared
        let idx = nextTitleIdx(for: "subThreshold", poolSize: 3)
        let titles = [L.s("절제가 빛난 인터벌", "Discipline in Every Rep"),
                      L.s("흔들리지 않은 인터벌", "Steady Through the Sets"),
                      L.s("페이스를 지켜낸 인터벌", "Pace Held Throughout")]
        let details = [L.s("심장이 요동쳐도 페이스는 일정 — 절제된 서브T 인터벌",
                           "HR surged but pace stayed true — textbook sub-threshold control"),
                       L.s("모든 구간 고른 페이스 — 과부하 없이 훈련 목표 완수",
                           "Even splits across all reps — goal met without overreach"),
                       L.s("빠르지만 무너지지 않은 인터벌 — 다음 훈련도 충전된 상태로",
                           "Fast but controlled — you'll recover well for the next session")]
        return InsightResult(theme: .subThreshold, title: titles[idx], detail: details[idx])
    }

    // MARK: - Fatigue context

    /// Softens tone when GrowthView signals p5 fatigueSign active (UserDefaults bridge).
    /// safety/firstAchievement/raceDay pass through unchanged.
    /// Achievement themes: prepend fatigue note, preserve data.
    /// Other themes: replace detail with completion acknowledgment.
    private static func applyFatigueContext(_ base: InsightResult) -> InsightResult {
        guard base.theme != .safety, base.theme != .firstAchievement,
              base.theme != .raceDay, base.theme != .milestone else { return base }
        let L = AppLanguage.shared
        let seed = Int((base.title.unicodeScalars.first?.value ?? 1) % 4)
        switch base.theme {
        case .recordImproved, .distanceExpanded, .adverseCondition, .tradeoff, .rarityFact, .milestone, .subThreshold:
            let prefixes = [L.s("몸이 무거운 흐름 속에서도 ", "Through heavy legs — "),
                            L.s("피로가 쌓이는 주간에도 ", "Even in a heavy week — "),
                            L.s("힘든 흐름 속에서도 ", "Despite the fatigue — "),
                            L.s("무거운 몸으로도 ", "Heavy legs and all — ")]
            return InsightResult(theme: base.theme, workoutType: base.workoutType,
                                 title: base.title, detail: prefixes[seed] + base.detail)
        default:
            let replacements = [L.s("몸이 무거운 흐름 속에서도 완주한 러닝이에요.",
                                    "A finish through heavy legs — that counts."),
                                L.s("피로가 쌓이는 주간에도 나섰어요.",
                                    "You showed up even in a heavy week."),
                                L.s("힘든 흐름 속에서도 달렸어요.",
                                    "Running through the fatigue takes its own strength."),
                                L.s("무거운 몸을 끌고 나온 것 자체가 이미 성취예요.",
                                    "Getting out the door with tired legs is its own win.")]
            return InsightResult(theme: base.theme, workoutType: base.workoutType,
                                 title: base.title, detail: replacements[seed])
        }
    }

    // MARK: - UserDefaults stores

    private static let tempHistoryKey    = "mimo_run_temp_history_v1"
    private static let tempHistoryIDsKey = "mimo_run_temp_ids_v1"
    private static let fatigueSignKey    = "mimo_weekly_p5_fatigue_active"
    private static let themeHistoryKey   = "mimo_insight_theme_history_v1"
    private static let titleIdxBaseKey   = "mimo_insight_title_idx_v1"

    /// Returns the current index for the given key's title pool (size `poolSize`) and advances it for
    /// the next call. Ensures sequential rotation through the pool without date-based repetition.
    private static func nextTitleIdx(for key: String, poolSize: Int) -> Int {
        let fullKey = "\(titleIdxBaseKey)_\(key)"
        let ud = UserDefaults.standard
        let current = ud.integer(forKey: fullKey) % poolSize
        ud.set((current + 1) % poolSize, forKey: fullKey)
        return current
    }

    /// Records temp for an activity once (deduped by UUID). Caps history at 200 (oldest dropped).
    static func recordTemperature(_ tempC: Double, for activityID: UUID) {
        let ud = UserDefaults.standard
        var ids   = ud.array(forKey: tempHistoryIDsKey) as? [String] ?? []
        var temps = ud.array(forKey: tempHistoryKey)    as? [Double] ?? []
        let idStr = activityID.uuidString
        guard !ids.contains(idStr) else { return }
        ids.append(idStr); temps.append(tempC)
        if temps.count > 200 { ids = Array(ids.dropFirst()); temps = Array(temps.dropFirst()) }
        ud.set(ids,   forKey: tempHistoryIDsKey)
        ud.set(temps, forKey: tempHistoryKey)
    }

    private static func loadTemperatureHistory() -> [Double] {
        UserDefaults.standard.array(forKey: tempHistoryKey) as? [Double] ?? []
    }

    /// Called by GrowthView after weeklyPatternCache is updated.
    static func updateFatigueSignal(active: Bool) {
        UserDefaults.standard.set(active, forKey: fatigueSignKey)
    }

    private static func isWeeklyFatigueActive() -> Bool {
        UserDefaults.standard.bool(forKey: fatigueSignKey)
    }

    private static func loadThemeHistory() -> [String] {
        UserDefaults.standard.array(forKey: themeHistoryKey) as? [String] ?? []
    }

    private static func recordTheme(_ theme: InsightTheme) {
        let ud = UserDefaults.standard
        var h = ud.array(forKey: themeHistoryKey) as? [String] ?? []
        h.append(theme.rawValue)
        if h.count > 10 { h = Array(h.suffix(10)) }
        ud.set(h, forKey: themeHistoryKey)
    }

    /// From same-priority candidates, returns the one whose theme was seen LEAST recently.
    /// `.milestone` is a once-in-a-lifetime fact — it always wins the tie-break.
    /// Never-seen themes win over previously-seen ones. Records the winner to history.
    private static func pickByRecency(_ candidates: [InsightResult]) -> InsightResult? {
        guard !candidates.isEmpty else { return nil }
        // Milestones are crossed at most once per boundary — always prefer over recency picks
        if let m = candidates.first(where: { $0.theme == .milestone }) {
            recordTheme(m.theme)
            return m
        }
        let history = loadThemeHistory()
        let winner = candidates.min { a, b in
            let ai = history.lastIndex(of: a.theme.rawValue) ?? -1
            let bi = history.lastIndex(of: b.theme.rawValue) ?? -1
            return ai < bi
        }
        if let w = winner { recordTheme(w.theme) }
        return winner
    }

    // MARK: - DEBUG fact log (stripped from release builds)

    #if DEBUG
    /// Probes all same-priority band facts and returns a diagnostic string.
    /// Called only in DEBUG builds; re-runs checks without side-effects (temp recording is idempotent).
    private static func buildBandFactLog(
        _ a: Activity, _ prior: [Activity],
        condition: ActivityCondition?,
        intervalSegments: [IntervalSegment],
        detail: ActivityDetail?,
        splits: [SplitData]
    ) -> String {
        var parts: [String] = []

        // adverseCondition (moved into band)
        let advR = adverseCondition(a, condition)
        if let advR = advR {
            parts.append("adverse(발화:\(advR.title))")
        } else if condition == nil {
            parts.append("adverse(침묵:날씨없음)")
        } else if !(condition?.hasAdverseSignal ?? false) {
            parts.append("adverse(침묵:정상날씨)")
        } else if a.distance < 1000 {
            parts.append("adverse(침묵:거리<1km)")
        } else {
            parts.append("adverse(침묵:날씨OK)")
        }

        // tradeoff
        let tradeoffFired = tradeoffInsight(a, prior, detail: detail, splits: splits) != nil
        parts.append("tradeoff(\(tradeoffFired ? "발화" : "침묵"))")

        // temperature extreme
        let hTemps = loadTemperatureHistory()
        if let tempC = condition?.weather?.tempC {
            if hTemps.count < 20 {
                parts.append("tempExtreme(침묵:표본\(hTemps.count)<20)")
            } else {
                let sorted = hTemps.sorted()
                let pct = Double(sorted.filter { $0 <= tempC }.count) / Double(sorted.count)
                if pct >= 0.95      { parts.append("tempExtreme(발화:상위5%·\(Int(tempC))°C)") }
                else if pct <= 0.05 { parts.append("tempExtreme(발화:하위5%·\(Int(tempC))°C)") }
                else                { parts.append("tempExtreme(침묵:\(Int(pct*100))%ile·\(Int(tempC))°C)") }
            }
        } else {
            parts.append("tempExtreme(침묵:기온없음)")
        }

        // time-of-day reunion
        let cal = Calendar.current
        let hour = cal.component(.hour, from: a.date)
        func sid(_ h: Int) -> Int {
            switch h { case 4..<7: return 0; case 7..<11: return 1; case 11..<16: return 2; case 16..<20: return 3; default: return 4 }
        }
        let slot = sid(hour)
        let slotNames = ["새벽","오전","낮","저녁","밤"]
        let sameSlot = prior.filter { sid(cal.component(.hour, from: $0.date)) == slot && $0.date < a.date }
        if sameSlot.isEmpty {
            parts.append("timeReunion(발화:첫\(slotNames[slot]))")
        } else if let last = sameSlot.max(by: { $0.date < $1.date }) {
            let days = cal.dateComponents([.day], from: last.date, to: a.date).day ?? 0
            if days >= 60 { parts.append("timeReunion(발화:\(days)일만의\(slotNames[slot]))") }
            else          { parts.append("timeReunion(침묵:최근\(days)일)") }
        } else {
            parts.append("timeReunion(침묵)")
        }

        // cumulative milestone
        let priorKm = prior.filter { $0.date < a.date }.reduce(0.0) { $0 + $1.distance } / 1000
        let curKm   = priorKm + a.distance / 1000
        let nextMark = (Int(priorKm / 50) + 1) * 50
        if curKm >= Double(nextMark) {
            parts.append("milestone(발화:\(nextMark)km·현재\(Int(curKm))km)")
        } else {
            let rem = Double(nextMark) - curKm
            parts.append("milestone(침묵:다음\(nextMark)km·\(String(format:"%.1f",rem))km남음)")
        }

        // subThreshold
        let workSteps = intervalSegments.filter { $0.stepLabel == "운동" }
        if workSteps.count < 2 {
            parts.append("subT(침묵:운동구간\(workSteps.count)개)")
        } else {
            let z5 = detail?.hrZones.first(where: { $0.id == 5 })?.fraction ?? -1
            if z5 >= 0.03 {
                parts.append("subT(침묵:zone5=\(Int(z5*100))%≥3%)")
            } else {
                let paces = workSteps.compactMap(\.paceSecPerKm)
                if paces.count < 2 {
                    parts.append("subT(침묵:페이스없음)")
                } else {
                    let mean = paces.reduce(0,+) / Double(paces.count)
                    let cv   = mean > 0 ? sqrt(paces.map { pow($0-mean,2) }.reduce(0,+)/Double(paces.count))/mean : 999
                    if cv < 0.08 { parts.append("subT(발화:CV=\(String(format:"%.1f",cv*100))%)") }
                    else         { parts.append("subT(침묵:CV=\(String(format:"%.1f",cv*100))%≥8%)") }
                }
            }
        }

        return "[" + parts.joined(separator: ", ") + "]"
    }

    /// Scans every static Korean title string against the forbidden-word list.
    /// Call once at app launch to catch regressions before they ship.
    static func auditTitlePools() {
        let forbidden = ["더 빨리", "더 멀리", "더 많이", "격렬", "폭발", "한계", "심장을"]
        let allTitles: [String] = [
            // distanceExpanded
            "경계를 넓힌 러닝", "낯선 거리를 만난 날", "거리의 문을 연 러닝",
            // consistent
            "꾸준함이 쌓이는 러닝", "쌓이는 러닝", "이어지는 러닝",
            // milestone (km placeholder)
            "누적 NNNkm의 발자국", "NNNkm 이정표를 넘은 러닝", "NNNkm이 쌓인 날",
            // tempHot
            "가장 더운 축의 러닝", "기온 상위 5%의 러닝", "뜨거운 날의 러닝",
            // tempCold
            "가장 추운 축의 러닝", "기온 하위 5%의 러닝", "혹한 속 러닝",
            // timeFirst / timeReunion (slot name substituted)
            "첫 새벽 러닝", "새벽에 처음 달린 러닝", "새벽 러닝 첫 경험",
            "N개월 만의 새벽 러닝", "오랜만의 새벽 러닝", "N개월 만에 다시 새벽에",
            // subThreshold
            "절제가 빛난 인터벌", "흔들리지 않은 인터벌", "페이스를 지켜낸 인터벌",
            // adverseCondition
            "빗속을 달린 러닝", "궂은 날의 완주", "바람을 가른 러닝",
            // recordImproved
            "효율의 러닝", "페이스가 자란 러닝",
            // firstAchievement
            "문을 연 러닝",
            // recovery
            "숨 고르는 러닝",
            // raceDay
            "마라톤 완주 러닝", "하프 완주 러닝", "10K 대회 러닝", "5K 대회 러닝", "대회 러닝",
            // tradeoff
            "심폐가 단단해지는 러닝", "지구력을 쌓는 러닝", "보폭이 자라는 러닝",
            "폼이 다듬어지는 러닝", "스피드의 정당한 대가",
            // safety
            "오늘 심박이 평소보다 높았어요",
            "더위 속 장거리 — 잘 해냈어요", "열기를 이겨낸 장거리", "더운 날의 긴 거리",
            "더운 날 잘 뛰었어요", "열기 속 러닝 완료", "더위와 함께 달린 러닝",
            // applyWorkoutType
            "기록을 깬 인터벌", "차오르는 인터벌", "스피드를 깨운 인터벌", "호흡을 끌어올린 인터벌",
            "기록을 쓴 롱런", "멀리 나아간 롱런", "지구력을 쌓은 롱런",
            "숨을 고른 이지런",
            "기록을 깬 템포", "리듬을 탄 템포", "임계점을 밀어붙인 템포",
            "기록을 쓴 빌드업", "후반이 가장 빨랐던 빌드업", "끝으로 갈수록 강해진 러닝", "마지막을 위해 달린 빌드업",
            "느리게 길게 간 LSD", "유산소 엔진을 키운 LSD", "천천히 멀리 간 러닝",
            "레이스처럼 달린 거리주", "목표 페이스로 달린 거리주", "강도 있게 달린 거리주",
            // periodPositive
            "밀도가 높아진 러닝", "집중된 달의 러닝", "꾸준히 이어가는 러닝",
            "이정표를 넘은 러닝", "부하를 내린 러닝", "쉬운 달에도 이어가는 러닝",
            // default
            "시작이 전부인 러닝", "자산 축적 러닝", "오늘도 나온 러닝",
        ]
        var found = 0
        for title in allTitles {
            for word in forbidden where title.contains(word) {
                print("[InsightTitleAudit] ⚠️ 금지어 '\(word)' in → \"\(title)\"")
                found += 1
            }
        }
        if found == 0 {
            print("[InsightTitleAudit] ✓ 금지어 없음 (\(allTitles.count)개 검사)")
        }
    }
    #endif
}
