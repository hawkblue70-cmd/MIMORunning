import Foundation

// MARK: - Classifier

struct WorkoutTypeClassifier {

    /// Classifies a running workout into one of five types.
    /// Priority: plan composition (WorkoutKit work steps) → split CV → distance/pace comparisons.
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

        // Interval only when WorkoutKit plan has explicit work + recovery steps.
        // Pace-variance inference is unreliable (even splits cause false positives).
        if isPlanInterval(intervalSegments: intervalSegments) { return .interval }
        if isLongRun(activity: activity, recentRuns: recentRuns)  { return .longRun  }
        if isEasy(activity: activity, recentRuns: recentRuns)     { return .easy     }
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
