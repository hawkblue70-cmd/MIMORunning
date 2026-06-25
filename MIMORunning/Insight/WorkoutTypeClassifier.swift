import Foundation

// MARK: - Classifier

struct WorkoutTypeClassifier {

    /// Classifies a running workout into one of eight types.
    /// Priority: plan (WorkoutKit) → buildUp pattern → distanceRun → LSD → longRun → easy → tempo → general.
    /// All thresholds are personal-relative — no absolute cutoffs.
    static func classify(
        activity: Activity,
        history: [Activity],
        splits: [SplitData],
        intervalSegments: [IntervalSegment] = []
    ) -> WorkoutType {
        guard activity.type == .running, activity.distance >= 1000 else { return .general }

        let recentRuns = history
            .filter { $0.type == .running && $0.id != activity.id }
            .sorted { $0.date > $1.date }

        if isPlanInterval(intervalSegments: intervalSegments) { return .interval    }
        if isBuildUp(splits: splits)                          { return .buildUp     }
        if isDistanceRun(activity: activity, recentRuns: recentRuns)    { return .distanceRun }
        if isLSD(activity: activity, recentRuns: recentRuns, splits: splits) { return .lsd }
        if isLongRun(activity: activity, recentRuns: recentRuns)        { return .longRun     }
        if isEasy(activity: activity, recentRuns: recentRuns)           { return .easy        }
        if isTempo(activity: activity, recentRuns: recentRuns, splits: splits) { return .tempo }
        return .general
    }

    // MARK: - Sub-checks

    /// ≥ 2 labelled "운동" (work) steps from a WorkoutKit plan → definite interval.
    /// Requires both work AND recovery labels to exist — rules out warmup-only plans.
    private static func isPlanInterval(intervalSegments: [IntervalSegment]) -> Bool {
        let hasWork     = intervalSegments.contains { $0.stepLabel == "운동" }
        let hasRecovery = intervalSegments.contains { $0.stepLabel == "회복" }
        let workCount   = intervalSegments.filter { $0.stepLabel == "운동" }.count
        return hasWork && hasRecovery && workCount >= 2
    }

    /// Progressive buildup: last full split is the fastest, first-to-last improvement ≥5%,
    /// and ≥60% of consecutive split pairs show the runner getting faster.
    private static func isBuildUp(splits: [SplitData]) -> Bool {
        let full = splits.filter { $0.distanceM >= 900 }
        guard full.count >= 4 else { return false }
        let paces = full.map(\.paceSecPerKm)
        guard let firstPace = paces.first,
              let lastPace  = paces.last,
              let minPace   = paces.min() else { return false }
        guard lastPace == minPace else { return false }          // last must be fastest
        guard lastPace < firstPace * 0.95 else { return false } // ≥5% first-to-last gain
        let improvingPairs = zip(paces, paces.dropFirst()).filter { $1 < $0 }.count
        return Double(improvingPairs) / Double(paces.count - 1) >= 0.60
    }

    /// Long distance + pace near/faster than personal average (race-intent effort).
    /// Pace must be < personal avg × 1.10 so it's distinctly faster than easy/LSD.
    private static func isDistanceRun(activity: Activity, recentRuns: [Activity]) -> Bool {
        guard isLongRun(activity: activity, recentRuns: recentRuns) else { return false }
        guard let pace = activity.paceSecPerKm else { return false }
        let recentPaces = recentRuns.prefix(10).compactMap(\.paceSecPerKm)
        guard recentPaces.count >= 3 else { return false }
        let avg = recentPaces.reduce(0, +) / Double(recentPaces.count)
        return pace < avg * 1.10
    }

    /// Long distance + very slow pace (≥20% slower than avg) + very even effort (CV ≤ 8%).
    private static func isLSD(activity: Activity, recentRuns: [Activity], splits: [SplitData]) -> Bool {
        guard isLongRun(activity: activity, recentRuns: recentRuns) else { return false }
        guard let pace = activity.paceSecPerKm else { return false }
        let recentPaces = recentRuns.prefix(10).compactMap(\.paceSecPerKm)
        guard recentPaces.count >= 3 else { return false }
        let avg = recentPaces.reduce(0, +) / Double(recentPaces.count)
        guard pace > avg * 1.20 else { return false }
        let full = splits.filter { $0.distanceM >= 900 }
        guard full.count >= 3 else { return true }  // very slow long + no splits → LSD
        let paces = full.map(\.paceSecPerKm)
        let mean = paces.reduce(0, +) / Double(paces.count)
        guard mean > 0 else { return false }
        let sd = sqrt(paces.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(paces.count))
        return sd / mean <= 0.08
    }

    /// ≥ 8 km AND > 120% of 4-week average (or ≥ 12 km with no history)
    private static func isLongRun(activity: Activity, recentRuns: [Activity]) -> Bool {
        guard activity.distance >= 8000 else { return false }
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: activity.date) ?? .distantPast
        let recent = recentRuns.filter { $0.date >= cutoff }.map(\.distance)
        guard recent.count >= 3 else { return activity.distance >= 12000 }
        let avg = recent.reduce(0, +) / Double(recent.count)
        return activity.distance > avg * 1.20
    }

    /// Pace ≥ 15% slower than 10-run average → recovery/easy
    private static func isEasy(activity: Activity, recentRuns: [Activity]) -> Bool {
        guard let pace = activity.paceSecPerKm else { return false }
        let recentPaces = recentRuns.prefix(10).compactMap(\.paceSecPerKm)
        guard recentPaces.count >= 3 else { return false }
        let avg = recentPaces.reduce(0, +) / Double(recentPaces.count)
        return pace > avg * 1.15
    }

    /// Faster than average + CV ≤ 7% across splits (uniform effort) + ≥ 4 km
    private static func isTempo(activity: Activity, recentRuns: [Activity], splits: [SplitData]) -> Bool {
        guard activity.distance >= 4000, let pace = activity.paceSecPerKm else { return false }
        let recentPaces = recentRuns.prefix(10).compactMap(\.paceSecPerKm)
        guard recentPaces.count >= 2 else { return false }
        let avg = recentPaces.reduce(0, +) / Double(recentPaces.count)
        guard pace < avg * 0.98 else { return false }

        let full = splits.filter { $0.distanceM >= 900 }
        guard full.count >= 3 else { return true }  // fast + no splits → tempo
        let paces = full.map(\.paceSecPerKm)
        let mean = paces.reduce(0, +) / Double(paces.count)
        guard mean > 0 else { return false }
        let sd = sqrt(paces.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(paces.count))
        return sd / mean <= 0.07
    }
}
