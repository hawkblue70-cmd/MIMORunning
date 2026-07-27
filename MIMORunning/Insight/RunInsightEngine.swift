import Foundation

// MARK: - Output Types

enum InsightCategory: String {
    case cardio          = "심폐 컨디션"
    case intensity       = "강도 · 페이스"
    case form            = "주법"
    case endurance       = "지구력 · 후반부"
    case efficiency      = "심박 효율"
    case environment     = "환경"
    case load            = "훈련량"
    case intervalQuality = "인터벌 수행"
    case recovery        = "회복"
}

enum InsightTone { case good, neutral, caution }

struct RunInsight: Identifiable {
    let id = UUID()
    let category: InsightCategory
    let tone: InsightTone
    let badge: String
    let message: String
    let highlights: [String]
}

// MARK: - Segment Types

struct RunSegment {
    let index: Int
    let isWork: Bool
    let startKm: Double
    let endKm: Double
    let duration: TimeInterval
    let paceSecPerKm: Double
    let avgHR: Int?
    let peakHR: Int?
    let endHR: Int?
}

enum RunSegmentSource { case watchPlan, detected, none }

// MARK: - Baseline Types

enum BaselineMode {
    case ageNorm
    case recentRuns
    case personalBaseline
}

struct RunBaseline {
    let mode: BaselineMode
    let sampleCount: Int
    let medianPaceSec: Double?
    let medianHR: Int?
    let medianCadence: Int?
    let vo2MaxThen: Double?
    let weeklyLoadKm: Double
    let prevWeeklyLoadKm: Double
}

// MARK: - Engine

@MainActor
enum RunInsightEngine {

    // MARK: - Baseline

    static func baseline(for activity: Activity, history: [Activity]) -> RunBaseline {
        let calendar = Calendar.current
        let now = activity.date

        let runHistory = history.filter {
            $0.type == .running && $0.id != activity.id && $0.date < activity.date
        }.sorted { $0.date > $1.date }

        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: now) ?? .distantPast
        let mode: BaselineMode
        if runHistory.count < 5 {
            mode = .ageNorm
        } else if runHistory.filter({ $0.date >= twoMonthsAgo }).count >= 5 {
            mode = .personalBaseline
        } else {
            mode = .recentRuns
        }

        let sixteenWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -16, to: now) ?? .distantPast
        let windowRuns = runHistory.filter { $0.date >= sixteenWeeksAgo }

        let medianPace: Double? = {
            let sorted = windowRuns.compactMap { $0.paceSecPerKm }.sorted()
            guard !sorted.isEmpty else { return nil }
            return sorted[sorted.count / 2]
        }()

        let medianHR: Int? = {
            let sorted = windowRuns.compactMap { $0.avgHeartRate }.sorted()
            guard !sorted.isEmpty else { return nil }
            return sorted[sorted.count / 2]
        }()

        let sevenDaysAgo    = calendar.date(byAdding: .day, value: -7,  to: now) ?? .distantPast
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? .distantPast

        let thisWeekKm = (runHistory
            .filter { $0.date >= sevenDaysAgo }
            .reduce(0.0) { $0 + $1.distance } + activity.distance) / 1000.0

        let prevWeekKm = runHistory
            .filter { $0.date >= fourteenDaysAgo && $0.date < sevenDaysAgo }
            .reduce(0.0) { $0 + $1.distance } / 1000.0

        return RunBaseline(
            mode: mode,
            sampleCount: runHistory.count,
            medianPaceSec: medianPace,
            medianHR: medianHR,
            medianCadence: nil,
            vo2MaxThen: nil,
            weeklyLoadKm: thisWeekKm,
            prevWeeklyLoadKm: prevWeekKm
        )
    }

    // MARK: - Segment Extraction

    static func segments(
        activity: Activity,
        detail: ActivityDetail?,
        hrSamples: [(offset: TimeInterval, bpm: Int)]
    ) -> (segments: [RunSegment], source: RunSegmentSource) {
        let splits    = detail?.splits ?? []
        let intervals = detail?.intervalSegments ?? []

        // B: Apple Watch workout plan → convert directly
        if !intervals.isEmpty {
            let converted = convertWatchPlanSegments(
                activity: activity, intervals: intervals,
                splits: splits, hrSamples: hrSamples
            )
            return converted.isEmpty ? ([], .none) : (converted, .watchPlan)
        }

        // A: Auto-detect from splits (interval workouts only)
        if detail?.workoutType == .interval {
            let detected = detectSegmentsFromSplits(splits)
            return detected.isEmpty ? ([], .none) : (detected, .detected)
        }

        return ([], .none)
    }

    private static func convertWatchPlanSegments(
        activity: Activity,
        intervals: [IntervalSegment],
        splits: [SplitData],
        hrSamples: [(offset: TimeInterval, bpm: Int)]
    ) -> [RunSegment] {
        let totalKm       = activity.distance / 1000.0
        let totalDuration = activity.duration

        return intervals.enumerated().compactMap { (i, seg) in
            let dur = seg.duration
            guard dur > 0 else { return nil }

            let startOffset = max(0, seg.startDate.timeIntervalSince(activity.date))
            let endOffset   = startOffset + dur

            let startKm = interpolateKm(offset: startOffset, splits: splits,
                                        totalDuration: totalDuration, totalKm: totalKm)
            let endKm   = interpolateKm(offset: endOffset, splits: splits,
                                        totalDuration: totalDuration, totalKm: totalKm)
            let distKm  = endKm - startKm

            let pace: Double
            if let distM = seg.distanceM, distM > 0 {
                pace = dur / (distM / 1000.0)
            } else if distKm > 0 {
                pace = dur / distKm
            } else {
                return nil
            }

            let segSamples = hrSamples.filter { $0.offset >= startOffset && $0.offset <= endOffset }
            let avgHR: Int?
            if !segSamples.isEmpty {
                avgHR = segSamples.map(\.bpm).reduce(0, +) / segSamples.count
            } else {
                avgHR = seg.avgHeartRate
            }
            let peakHR = segSamples.map(\.bpm).max()
            let endHR  = hrInWindow(around: endOffset, hrSamples: hrSamples)

            return RunSegment(
                index: i + 1,
                isWork: seg.stepLabel == "운동",
                startKm: startKm,
                endKm: max(startKm + 0.001, endKm),
                duration: dur,
                paceSecPerKm: pace,
                avgHR: avgHR,
                peakHR: peakHR,
                endHR: endHR
            )
        }
    }

    private static func detectSegmentsFromSplits(_ splits: [SplitData]) -> [RunSegment] {
        guard splits.count >= 6 else { return [] }

        let rawPaces = splits.map { $0.paceSecPerKm }.filter { $0 > 0 }
        guard rawPaces.count >= 6 else { return [] }

        let smoothed = movingMedian(rawPaces, window: 5)
        let sortedSm = smoothed.sorted()
        let globalMedian = sortedSm[sortedSm.count / 2]
        guard globalMedian > 0 else { return [] }

        let fastThresh = globalMedian * 0.88  // 12% faster than median = work

        let tags: [Bool] = rawPaces.map { $0 <= fastThresh }

        // Build cumulative km boundary array
        var cumKm: [Double] = [0]
        for split in splits { cumKm.append(cumKm.last! + split.distanceM / 1000.0) }

        // Group consecutive same-tag splits
        struct Group { let isWork: Bool; let startIdx: Int; var endIdx: Int }
        var groups: [Group] = []
        if !tags.isEmpty {
            var cur = Group(isWork: tags[0], startIdx: 0, endIdx: 0)
            for i in 1 ..< tags.count {
                if tags[i] == cur.isWork {
                    cur.endIdx = i
                } else {
                    groups.append(cur)
                    cur = Group(isWork: tags[i], startIdx: i, endIdx: i)
                }
            }
            groups.append(cur)
        }

        struct RawSeg { let isWork: Bool; let startKm: Double; let endKm: Double; let duration: TimeInterval }
        var rawSegs: [RawSeg] = []
        for g in groups {
            guard g.endIdx + 1 < cumKm.count else { continue }
            let startKm = cumKm[g.startIdx]
            let endKm   = cumKm[g.endIdx + 1]
            let dur     = splits[g.startIdx ... g.endIdx].reduce(0.0) { $0 + $1.duration }
            rawSegs.append(RawSeg(isWork: g.isWork, startKm: startKm, endKm: endKm, duration: dur))
        }

        // Merge very short groups into previous (safety for sub-split data)
        var merged: [RawSeg] = []
        for seg in rawSegs {
            if seg.duration < 15, !merged.isEmpty {
                let last = merged.removeLast()
                merged.append(RawSeg(isWork: last.isWork, startKm: last.startKm,
                                     endKm: seg.endKm, duration: last.duration + seg.duration))
            } else {
                merged.append(seg)
            }
        }

        guard merged.filter({ $0.isWork }).count >= 3 else { return [] }

        return merged.enumerated().map { (i, seg) in
            let distKm = seg.endKm - seg.startKm
            let pace   = distKm > 0 ? seg.duration / distKm : 0
            return RunSegment(
                index: i + 1,
                isWork: seg.isWork,
                startKm: seg.startKm,
                endKm: seg.endKm,
                duration: seg.duration,
                paceSecPerKm: pace,
                avgHR: nil, peakHR: nil, endHR: nil
            )
        }
    }

    // MARK: - Insights (main entry point)

    static func insights(
        for activity: Activity,
        detail: ActivityDetail? = nil,
        history: [Activity],
        age: Int?,
        isMale: Bool?,
        restingHR: Int?,
        hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    ) -> (insights: [RunInsight], segmentSource: RunSegmentSource) {
        let base        = Self.baseline(for: activity, history: history)
        let workoutType = detail?.workoutType ?? .general
        var results:   [RunInsight]       = []
        var segSource: RunSegmentSource   = .none

        switch workoutType {

        case .interval:
            let (segs, src) = Self.segments(activity: activity, detail: detail, hrSamples: hrSamples)
            if !segs.isEmpty {
                segSource = src
                let workSegs = segs.filter { $0.isWork }
                let intervalGens: [() -> RunInsight?] = [
                    { intervalConsistencyInsight(workSegs: workSegs) },
                    { intervalFadeInsight(workSegs: workSegs) },
                    { intervalRecoveryInsight(segments: segs, hrSamples: hrSamples) },
                    { intervalVolumeInsight(workSegs: workSegs, activity: activity) },
                ]
                for gen in intervalGens where results.count < 4 {
                    if let i = gen() { results.append(i) }
                }
                if results.count < 4, let i = cardioInsight(detail: detail, age: age, isMale: isMale) {
                    results.append(i)
                }
            } else {
                appendGeneralInsights(into: &results, activity: activity, detail: detail,
                                      history: history, base: base, age: age, isMale: isMale)
            }

        case .tempo:
            let generators: [() -> RunInsight?] = [
                { tempoPaceStabilityInsight(detail: detail) },
                { cardiacDriftInsight(activity: activity, hrSamples: hrSamples, category: .efficiency) },
                { cardioInsight(detail: detail, age: age, isMale: isMale) },
                { efficiencyInsight(activity: activity, history: history) },
                { loadInsight(baseline: base) },
            ]
            for gen in generators where results.count < 4 {
                if let i = gen() { results.append(i) }
            }

        case .easy:
            let generators: [() -> RunInsight?] = [
                { easyOverpaceInsight(activity: activity, age: age) },
                { environmentInsight(activity: activity) },
                { cardioInsight(detail: detail, age: age, isMale: isMale) },
                { loadInsight(baseline: base) },
            ]
            for gen in generators where results.count < 4 {
                if let i = gen() { results.append(i) }
            }

        case .longRun, .lsd:
            let generators: [() -> RunInsight?] = [
                { cardiacDriftInsight(activity: activity, hrSamples: hrSamples, category: .efficiency) },
                { cardioInsight(detail: detail, age: age, isMale: isMale) },
                { environmentInsight(activity: activity) },
                { loadInsight(baseline: base) },
            ]
            for gen in generators where results.count < 4 {
                if let i = gen() { results.append(i) }
            }

        case .buildUp:
            let generators: [() -> RunInsight?] = [
                { buildUpInsight(activity: activity, detail: detail) },
                { cardioInsight(detail: detail, age: age, isMale: isMale) },
                { efficiencyInsight(activity: activity, history: history) },
                { loadInsight(baseline: base) },
            ]
            for gen in generators where results.count < 4 {
                if let i = gen() { results.append(i) }
            }

        case .distanceRun:
            let generators: [() -> RunInsight?] = [
                { distanceRunInsight(activity: activity, baseline: base) },
                { enduranceInsight(detail: detail) },
                { efficiencyInsight(activity: activity, history: history) },
                { cardioInsight(detail: detail, age: age, isMale: isMale) },
            ]
            for gen in generators where results.count < 4 {
                if let i = gen() { results.append(i) }
            }

        default:
            appendGeneralInsights(into: &results, activity: activity, detail: detail,
                                  history: history, base: base, age: age, isMale: isMale)
        }

        return (Array(results.prefix(4)), segSource)
    }

    private static func appendGeneralInsights(
        into results: inout [RunInsight],
        activity: Activity,
        detail: ActivityDetail?,
        history: [Activity],
        base: RunBaseline,
        age: Int?,
        isMale: Bool?
    ) {
        let generators: [() -> RunInsight?] = [
            { cardioInsight(detail: detail, age: age, isMale: isMale) },
            { intensityInsight(activity: activity, detail: detail, age: age) },
            { enduranceInsight(detail: detail) },
            { efficiencyInsight(activity: activity, history: history) },
            { formInsight(detail: detail) },
            { environmentInsight(activity: activity) },
            { loadInsight(baseline: base) },
        ]
        for gen in generators where results.count < 4 {
            if let i = gen() { results.append(i) }
        }
    }

    // MARK: - Interval Insights

    private static func intervalConsistencyInsight(workSegs: [RunSegment]) -> RunInsight? {
        guard workSegs.count >= 2 else { return nil }
        let L = AppLanguage.shared
        let paces = workSegs.map { $0.paceSecPerKm }.filter { $0 > 0 }
        guard paces.count >= 2 else { return nil }

        let mean = paces.reduce(0.0, +) / Double(paces.count)
        guard mean > 0 else { return nil }

        let diff    = paces.last! - paces.first!  // positive = slower at end
        let absDiff = Int(abs(diff).rounded())
        let countStr   = "\(workSegs.count)"
        let avgPaceStr = String(format: "%d'%02d\"", Int(mean) / 60, Int(mean) % 60)
        let diffStr    = "\(absDiff)초"

        let tone: InsightTone; let badge: String; let msg: String
        if absDiff <= 10 {
            tone = .good; badge = L.s("일관적", "Consistent")
            msg = L.s(
                "\(countStr)회 반복 평균 \(avgPaceStr) — 첫 구간과 마지막 차이 \(diffStr)로 일관됐어요.",
                "\(countStr) reps at avg \(avgPaceStr) — only \(diffStr) between first and last. Consistent!"
            )
        } else if absDiff <= 20 {
            tone = .neutral; badge = L.s("보통", "Moderate")
            msg = L.s(
                "\(countStr)회 반복 평균 \(avgPaceStr) — 첫 구간과 마지막 차이 \(diffStr)이에요.",
                "\(countStr) reps at avg \(avgPaceStr) — \(diffStr) between first and last rep."
            )
        } else {
            tone = .caution; badge = L.s("참고", "Note")
            msg = L.s(
                "\(countStr)회 반복 평균 \(avgPaceStr) — 마지막 구간이 \(diffStr) 느려졌어요. 세트 수나 강도 조정을 시도해 볼 수 있어요.",
                "\(countStr) reps at avg \(avgPaceStr) — last rep was \(diffStr) slower. Consider adjusting set count or intensity."
            )
        }
        return RunInsight(category: .intervalQuality, tone: tone, badge: badge,
                          message: msg, highlights: [countStr + "회", avgPaceStr])
    }

    private static func intervalFadeInsight(workSegs: [RunSegment]) -> RunInsight? {
        guard workSegs.count >= 4 else { return nil }
        let L = AppLanguage.shared
        let paces = workSegs.map { $0.paceSecPerKm }.filter { $0 > 0 }
        guard paces.count >= 4 else { return nil }

        let avgFirst = Array(paces.dropLast(2)).reduce(0.0, +) / Double(paces.count - 2)
        let avgLast  = Array(paces.suffix(2)).reduce(0.0, +) / 2.0
        guard avgFirst > 0 else { return nil }

        let diffSec = Int((avgLast - avgFirst).rounded())
        guard diffSec > 10 else { return nil }  // < 10s 차이는 무시

        let diffStr = "\(diffSec)초"
        let msg = L.s(
            "마지막 2구간이 앞부분보다 평균 \(diffStr) 느려졌어요. 세트 수나 회복 시간 조정을 시도해 볼 수 있어요.",
            "Last 2 reps averaged \(diffStr) slower than earlier reps. Consider adjusting set count or recovery time."
        )
        return RunInsight(category: .intervalQuality, tone: .caution, badge: L.s("후반 처짐", "Late Fade"),
                          message: msg, highlights: [diffStr])
    }

    private static func intervalRecoveryInsight(
        segments: [RunSegment],
        hrSamples: [(offset: TimeInterval, bpm: Int)]
    ) -> RunInsight? {
        guard !hrSamples.isEmpty else { return nil }
        let L = AppLanguage.shared

        var hrDrops: [Int] = []
        for i in 0 ..< segments.count - 1 {
            let curr = segments[i]; let next = segments[i + 1]
            guard curr.isWork, !next.isWork else { continue }
            guard let workEndHR = curr.endHR, let recovEndHR = next.endHR else { continue }
            let drop = workEndHR - recovEndHR
            if drop > 0 { hrDrops.append(drop) }
        }
        guard !hrDrops.isEmpty else { return nil }

        let avgDrop = hrDrops.reduce(0, +) / hrDrops.count
        let dropStr = "\(avgDrop)"
        let tone: InsightTone = avgDrop >= 20 ? .good : .neutral
        let badge = tone == .good ? L.s("회복 우수", "Good Recovery") : L.s("회복 능력", "Recovery")
        let msg = L.s(
            "회복 구간에서 심박이 평균 \(dropStr)bpm 떨어졌어요.",
            "HR dropped an average of \(dropStr) bpm during recovery intervals."
        )
        return RunInsight(category: .recovery, tone: tone, badge: badge,
                          message: msg, highlights: [dropStr + "bpm"])
    }

    private static func intervalVolumeInsight(workSegs: [RunSegment], activity: Activity) -> RunInsight? {
        let L = AppLanguage.shared
        let workKm  = workSegs.reduce(0.0) { $0 + ($1.endKm - $1.startKm) }
        let totalKm = activity.distance / 1000.0
        guard workKm > 0, totalKm > 0 else { return nil }

        let workStr  = String(format: "%.1f", workKm)
        let totalStr = String(format: "%.1f", totalKm)
        let msg = L.s(
            "운동 구간 합계 \(workStr)km / 회복 포함 총 \(totalStr)km",
            "Work intervals total \(workStr) km / \(totalStr) km incl. recovery"
        )
        return RunInsight(category: .intervalQuality, tone: .neutral, badge: L.s("운동량", "Volume"),
                          message: msg, highlights: [workStr + "km", totalStr + "km"])
    }

    // MARK: - Tempo Insights

    private static func tempoPaceStabilityInsight(detail: ActivityDetail?) -> RunInsight? {
        guard let splits = detail?.splits, splits.count >= 3 else { return nil }
        let L = AppLanguage.shared
        let paces = splits.map { $0.paceSecPerKm }.filter { $0 > 0 }
        guard paces.count >= 3 else { return nil }

        let mean = paces.reduce(0.0, +) / Double(paces.count)
        guard mean > 0 else { return nil }
        let sd    = (paces.map { pow($0 - mean, 2) }.reduce(0.0, +) / Double(paces.count)).squareRoot()
        let sdInt = Int(sd.rounded())
        let avgPaceStr = String(format: "%d'%02d\"", Int(mean) / 60, Int(mean) % 60)
        let sdStr      = "\(sdInt)초"

        let tone: InsightTone; let badge: String; let msg: String
        if sdInt <= 10 {
            tone = .good; badge = L.s("안정적", "Steady")
            msg = L.s("평균 템포 페이스 \(avgPaceStr), 편차 \(sdStr) — 안정적으로 유지했어요.",
                      "Avg tempo pace \(avgPaceStr), SD \(sdStr) — very steady.")
        } else if sdInt <= 20 {
            tone = .neutral; badge = L.s("페이스 유지", "Pacing")
            msg = L.s("평균 템포 페이스 \(avgPaceStr), 편차 \(sdStr)이에요.",
                      "Avg tempo pace \(avgPaceStr), SD \(sdStr).")
        } else {
            tone = .caution; badge = L.s("페이스 변동", "Variable")
            msg = L.s(
                "평균 페이스 \(avgPaceStr)이지만 편차 \(sdStr)으로 다소 변동이 있었어요. 일정한 리듬을 시도해 볼 수 있어요.",
                "Avg pace \(avgPaceStr) but SD \(sdStr) shows some variation. A steadier rhythm may help next time."
            )
        }
        return RunInsight(category: .intensity, tone: tone, badge: badge,
                          message: msg, highlights: [avgPaceStr, sdStr])
    }

    private static func cardiacDriftInsight(
        activity: Activity,
        hrSamples: [(offset: TimeInterval, bpm: Int)],
        category: InsightCategory
    ) -> RunInsight? {
        guard hrSamples.count >= 10 else { return nil }
        let L = AppLanguage.shared
        let mid   = activity.duration / 2
        let front = hrSamples.filter { $0.offset < mid }.map(\.bpm)
        let back  = hrSamples.filter { $0.offset >= mid }.map(\.bpm)
        guard !front.isEmpty, !back.isEmpty else { return nil }

        let frontAvg = Double(front.reduce(0, +)) / Double(front.count)
        let backAvg  = Double(back.reduce(0,  +)) / Double(back.count)
        guard frontAvg > 0 else { return nil }

        let driftBpm = Int((backAvg - frontAvg).rounded())
        let driftPct = (backAvg - frontAvg) / frontAvg * 100
        let driftStr = "\(abs(driftBpm))bpm"

        let tone: InsightTone = abs(driftPct) <= 6 ? .good : .neutral
        let badge = tone == .good ? L.s("드리프트 낮음", "Low Drift") : L.s("심박 드리프트", "Cardiac Drift")
        let msg: String
        if abs(driftPct) <= 6 {
            msg = L.s("전반/후반 심박 차이 \(driftStr) — 카디악 드리프트 적어요.",
                      "Front/back HR drift \(driftStr) — minimal cardiac drift.")
        } else {
            msg = L.s("후반 심박이 전반보다 \(driftStr) 올랐어요.",
                      "HR rose \(driftStr) in the second half.")
        }
        return RunInsight(category: category, tone: tone, badge: badge,
                          message: msg, highlights: [driftStr])
    }

    // MARK: - Easy Run Insight

    private static func easyOverpaceInsight(activity: Activity, age: Int?) -> RunInsight? {
        guard let avgHR = activity.avgHeartRate, let age = age else { return nil }
        let L = AppLanguage.shared
        let maxHR  = 220 - age
        guard maxHR > 0 else { return nil }
        let pct    = Double(avgHR) / Double(maxHR) * 100
        let pctStr = String(format: "%.0f%%", pct)

        if pct > 75 {
            let msg = L.s(
                "회복런 기준 심박이 \(pctStr)로 다소 높았어요 — 더 여유롭게 가도 좋아요.",
                "HR at \(pctStr) of max for an easy run — it's fine to go a bit easier."
            )
            return RunInsight(category: .intensity, tone: .caution, badge: L.s("강도 참고", "Effort Note"),
                              message: msg, highlights: [pctStr])
        }
        let msg = L.s(
            "심박 \(pctStr)로 여유 있는 강도의 회복런이었어요.",
            "HR at \(pctStr) of max — good easy effort level."
        )
        return RunInsight(category: .intensity, tone: .good, badge: L.s("좋은 강도", "Good Effort"),
                          message: msg, highlights: [pctStr])
    }

    // MARK: - Build-Up Insight

    private static func buildUpInsight(activity: Activity, detail: ActivityDetail?) -> RunInsight? {
        guard let splits = detail?.splits, splits.count >= 3 else { return nil }
        let L = AppLanguage.shared
        let paces = splits.map { $0.paceSecPerKm }.filter { $0 > 0 }
        guard paces.count >= 3 else { return nil }

        var decreasingPairs = 0
        for i in 1 ..< paces.count where paces[i] < paces[i - 1] { decreasingPairs += 1 }

        let ratio   = Double(decreasingPairs) / Double(paces.count - 1)
        let gainSec = Int((paces[0] - paces[paces.count - 1]).rounded())
        let gainStr = "\(gainSec)초"

        if gainSec > 0, ratio >= 0.6 {
            let msg = L.s(
                "전체적으로 \(gainStr) 빨라졌어요 — 빌드업이 잘 됐어요.",
                "Overall \(gainStr) faster from start to finish — great build-up execution."
            )
            return RunInsight(category: .intensity, tone: .good, badge: L.s("빌드업 성공", "Build-Up ✓"),
                              message: msg, highlights: [gainStr])
        }
        let msg = L.s(
            "이번 빌드업은 구간별 속도 변화가 일정하지 않았어요. 다음에 점진적 가속을 시도해 볼 수 있어요.",
            "Pacing varied in this build-up. A more gradual acceleration may help next time."
        )
        return RunInsight(category: .intensity, tone: .neutral, badge: L.s("페이스 패턴", "Pace Pattern"),
                          message: msg, highlights: [])
    }

    // MARK: - Distance Run Insight

    private static func distanceRunInsight(activity: Activity, baseline: RunBaseline) -> RunInsight? {
        guard let currentPace = activity.paceSecPerKm,
              let medianPace  = baseline.medianPaceSec,
              medianPace > 0, baseline.sampleCount >= 3 else { return nil }
        let L = AppLanguage.shared

        let diff    = currentPace - medianPace  // positive = slower than history
        let absDiff = abs(diff)
        guard absDiff > 5 else { return nil }

        let diffStr    = "\(Int(absDiff.rounded()))초"
        let currentStr = String(format: "%d'%02d\"", Int(currentPace) / 60, Int(currentPace) % 60)
        let direction  = diff < 0 ? L.s("빨랐어요", "faster") : L.s("느렸어요", "slower")
        let tone: InsightTone = diff < 0 ? .good : .neutral
        let msg = L.s(
            "평균 페이스 \(currentStr) — 최근 평균보다 \(diffStr) \(direction).",
            "Avg pace \(currentStr) — \(diffStr) \(direction) than recent average."
        )
        return RunInsight(category: .intensity, tone: tone, badge: L.s("페이스 비교", "Pace vs History"),
                          message: msg, highlights: [currentStr, diffStr])
    }

    // MARK: - General Insights (existing rules)

    private static func cardioInsight(detail: ActivityDetail?, age: Int?, isMale: Bool?) -> RunInsight? {
        guard let vo2 = detail?.vo2Max else { return nil }
        let L = AppLanguage.shared
        let voStr = String(format: "%.1f", vo2)

        if let age {
            let level = vo2Level(vo2: vo2, age: age, isMale: isMale ?? true)
            let levelLabel = L.s(level.korLabel, level.enLabel)
            let badge: String; let tone: InsightTone
            switch level {
            case .poor, .belowAverage: badge = L.s("참고", "Note");         tone = .neutral
            case .average:             badge = L.s("평균", "Average");       tone = .neutral
            case .good:                badge = L.s("평균 이상", "Above Avg"); tone = .good
            case .excellent:           badge = L.s("우수", "Excellent");      tone = .good
            }
            let msg = L.s(
                "유산소 피트니스 \(voStr)는 같은 연령대 기준 \(levelLabel)에 해당해요. (추정값)",
                "Cardio fitness \(voStr) is \(levelLabel) for your age group. (estimated)"
            )
            return RunInsight(category: .cardio, tone: tone, badge: badge,
                              message: msg, highlights: [voStr, levelLabel])
        } else {
            let msg = L.s(
                "유산소 피트니스(VO2max 추정값)는 \(voStr) mL/kg·min이에요.",
                "Estimated cardio fitness (VO2max) is \(voStr) mL/kg·min."
            )
            return RunInsight(category: .cardio, tone: .neutral, badge: L.s("확인", "Info"),
                              message: msg, highlights: [voStr])
        }
    }

    private static func intensityInsight(
        activity: Activity,
        detail: ActivityDetail?,
        age: Int?
    ) -> RunInsight? {
        guard let avgHR = activity.avgHeartRate else { return nil }
        let L = AppLanguage.shared
        var parts: [String] = []
        var highlights: [String] = []
        var tone: InsightTone = .neutral

        if let age {
            let maxHR = 220 - age
            guard maxHR > 0 else { return nil }
            let pct = Double(avgHR) / Double(maxHR) * 100
            let zoneName: String
            switch pct {
            case ..<60:   zoneName = L.s("저강도", "low intensity")
            case 60..<70: zoneName = L.s("저강도", "low-moderate")
            case 70..<80: zoneName = L.s("중강도", "moderate");        tone = .good
            case 80..<90: zoneName = L.s("고강도", "high intensity");   tone = .good
            default:      zoneName = L.s("최고 강도", "max effort");    tone = .caution
            }
            let pctStr = String(format: "%.0f%%", pct)
            parts.append(L.s(
                "평균 심박 \(avgHR)은 추정 최대심박의 약 \(pctStr) — \(zoneName)이에요.",
                "Avg HR \(avgHR) is ~\(pctStr) of estimated max — \(zoneName)."
            ))
            highlights += ["\(avgHR)", pctStr]
        } else {
            parts.append(L.s("평균 심박 \(avgHR) bpm이에요.", "Avg HR \(avgHR) bpm."))
            highlights.append("\(avgHR)")
        }

        if let splits = detail?.splits, splits.count >= 3 {
            let paces = splits.map { $0.paceSecPerKm }
            let mean  = paces.reduce(0.0, +) / Double(paces.count)
            if mean > 0 {
                let sd    = (paces.map { pow($0 - mean, 2) }.reduce(0.0, +) / Double(paces.count)).squareRoot()
                let sdInt = Int(sd.rounded())
                let sdStr = L.s("\(sdInt)초", "\(sdInt)s")
                let stability = sdInt <= 15
                    ? L.s("안정적이었어요", "was steady")
                    : L.s("다소 변동이 있었어요", "varied somewhat")
                parts.append(L.s(
                    "페이스 편차 \(sdStr)로 \(stability).",
                    "Pace SD \(sdStr) — \(stability)."
                ))
                highlights.append(sdStr)
            }
        }

        let badge = tone == .good ? L.s("적정 강도", "Good Effort") : L.s("강도 확인", "Intensity")
        return RunInsight(category: .intensity, tone: tone, badge: badge,
                          message: parts.joined(separator: " "), highlights: highlights)
    }

    private static func enduranceInsight(detail: ActivityDetail?) -> RunInsight? {
        guard let splits = detail?.splits, splits.count >= 4 else { return nil }
        let L = AppLanguage.shared
        let half     = splits.count / 2
        let front    = Array(splits[..<half])
        let back     = Array(splits[half...])
        let avgFront = front.map { $0.paceSecPerKm }.reduce(0.0, +) / Double(front.count)
        let avgBack  = back.map  { $0.paceSecPerKm }.reduce(0.0, +) / Double(back.count)
        guard avgFront > 0 else { return nil }

        let drift    = (avgBack - avgFront) / avgFront * 100
        let driftStr = String(format: "%.1f%%", abs(drift))

        let tone: InsightTone; let badge: String; let msg: String
        if drift <= 3 {
            tone = .good; badge = L.s("후반 유지", "Strong Finish")
            msg = L.s(
                "전반 대비 후반 페이스 편차 \(driftStr) — 끝까지 잘 유지했어요.",
                "Pace drift \(driftStr) vs. first half — great consistency to the end."
            )
        } else if drift <= 5 {
            tone = .neutral; badge = L.s("완만한 처짐", "Minor Fade")
            msg = L.s(
                "후반 페이스가 전반보다 \(driftStr) 느려졌어요.",
                "Back-half pace was \(driftStr) slower than the front half."
            )
        } else {
            tone = .caution; badge = L.s("참고", "Note")
            msg = L.s(
                "후반 페이스가 전반보다 \(driftStr) 느려졌어요. 다음번 페이스 배분에 참고해 볼 수 있어요.",
                "Pace fell \(driftStr) in the back half — consider pacing strategy next time."
            )
        }
        return RunInsight(category: .endurance, tone: tone, badge: badge,
                          message: msg, highlights: [driftStr])
    }

    private static func efficiencyInsight(activity: Activity, history: [Activity]) -> RunInsight? {
        guard let currentHR   = activity.avgHeartRate,
              let currentPace = activity.paceSecPerKm,
              currentPace > 0 else { return nil }
        let L = AppLanguage.shared
        let window = 15.0

        let comparable = history.filter {
            $0.type == .running && $0.id != activity.id && $0.avgHeartRate != nil &&
            abs(($0.paceSecPerKm ?? -999) - currentPace) <= window
        }
        guard comparable.count >= 3 else { return nil }

        let histHRs   = comparable.compactMap { $0.avgHeartRate }
        let avgHistHR = Double(histHRs.reduce(0, +)) / Double(histHRs.count)
        let diff      = avgHistHR - Double(currentHR)
        guard abs(diff) >= 3 else { return nil }

        let diffStr   = "\(Int(abs(diff).rounded()))"
        let sampleStr = "\(comparable.count)"

        if diff > 0 {
            let msg = L.s(
                "비슷한 페이스 최근 \(sampleStr)회 대비 심박이 \(diffStr) bpm 낮아요 — 심폐 효율이 개선되고 있어요.",
                "HR is \(diffStr) bpm lower vs \(sampleStr) similar-pace runs — efficiency improving."
            )
            return RunInsight(category: .efficiency, tone: .good, badge: L.s("효율 향상", "Efficient"),
                              message: msg, highlights: [diffStr + "bpm", sampleStr + "회"])
        } else {
            let msg = L.s(
                "비슷한 페이스 최근 \(sampleStr)회 대비 심박이 \(diffStr) bpm 높아요. 오늘 컨디션을 반영한 것일 수 있어요.",
                "HR is \(diffStr) bpm higher vs \(sampleStr) similar-pace runs — may reflect today's condition."
            )
            return RunInsight(category: .efficiency, tone: .neutral, badge: L.s("참고", "Note"),
                              message: msg, highlights: [diffStr + "bpm", sampleStr + "회"])
        }
    }

    private static func formInsight(detail: ActivityDetail?) -> RunInsight? {
        guard let cadence = detail?.avgCadence else { return nil }
        let L = AppLanguage.shared
        var parts: [String] = []
        var highlights: [String] = []
        var tone: InsightTone = .good
        let cadStr = "\(cadence)"

        if cadence < 175 {
            tone = .caution
            parts.append(L.s(
                "케이던스 \(cadStr)은 권장 범위(175~185)보다 \(175 - cadence) 낮아요. 조금 올려볼 수 있어요.",
                "Cadence \(cadStr) is \(175 - cadence) below the suggested range (175–185)."
            ))
        } else if cadence <= 185 {
            parts.append(L.s(
                "케이던스 \(cadStr)은 권장 범위(175~185)에 있어요.",
                "Cadence \(cadStr) is within the suggested range (175–185)."
            ))
        } else {
            parts.append(L.s("케이던스 \(cadStr)은 높은 편이에요.", "Cadence \(cadStr) is on the higher side."))
        }
        highlights.append(cadStr)

        if let gct = detail?.avgGroundContactTime {
            let ms  = Int(gct.rounded())
            let feel = ms > 280 ? L.s("긴 편이에요", "on the longer side") : L.s("적절해요", "looks good")
            parts.append(L.s("지면접촉 \(ms)ms로 \(feel).", "Ground contact \(ms)ms — \(feel)."))
            highlights.append("\(ms)ms")
        }

        if let stride = detail?.avgStrideLength {
            let strideStr = String(format: "%.2fm", stride)
            parts.append(L.s("보폭 \(strideStr)이에요.", "Stride length \(strideStr)."))
            highlights.append(strideStr)
        }

        let badge = tone == .good ? L.s("좋은 주법", "Good Form") : L.s("참고", "Note")
        return RunInsight(category: .form, tone: tone, badge: badge,
                          message: parts.joined(separator: " "), highlights: highlights)
    }

    private static func environmentInsight(activity: Activity) -> RunInsight? {
        guard activity.temperatureC != nil || activity.humidityPercent != nil else { return nil }
        let L = AppLanguage.shared
        var header = ""
        if let t = activity.temperatureC { header += "\(Int(t.rounded()))°C" }
        if let h = activity.humidityPercent {
            if !header.isEmpty { header += " · " }
            header += L.s("습도 \(Int(h.rounded()))%", "\(Int(h.rounded()))% humidity")
        }

        let isHot   = (activity.temperatureC ?? 0) > 25
        let isHumid = (activity.humidityPercent ?? 0) > 75
        let isCool  = (activity.temperatureC ?? 100) < 10

        let msg: String; let tone: InsightTone; let badge: String
        if isHot && isHumid {
            tone = .caution; badge = L.s("날씨 감안", "Conditions")
            msg = L.s("\(header) — 더위와 습도가 높아 체감 부담이 있었을 거예요.",
                      "\(header) — hot and humid conditions add extra strain.")
        } else if isHot {
            tone = .caution; badge = L.s("날씨 감안", "Conditions")
            msg = L.s("\(header) — 더운 날씨라 체감 부담이 있었을 거예요.",
                      "\(header) — warm conditions can increase perceived effort.")
        } else if isHumid {
            tone = .caution; badge = L.s("날씨 감안", "Conditions")
            msg = L.s("\(header) — 습한 편이라 체감 부담이 있었을 거예요.",
                      "\(header) — high humidity can increase perceived effort.")
        } else if isCool {
            tone = .neutral; badge = L.s("날씨", "Conditions")
            msg = L.s("\(header) — 서늘한 날씨였어요.", "\(header) — cool conditions.")
        } else {
            tone = .good; badge = L.s("쾌적", "Pleasant")
            msg = L.s("\(header) — 쾌적한 날씨였어요.", "\(header) — comfortable conditions.")
        }
        return RunInsight(category: .environment, tone: tone, badge: badge,
                          message: msg, highlights: [header])
    }

    private static func loadInsight(baseline: RunBaseline) -> RunInsight? {
        guard baseline.weeklyLoadKm > 0 else { return nil }
        let L = AppLanguage.shared
        let thisStr = String(format: "%.1f", baseline.weeklyLoadKm)

        if baseline.prevWeeklyLoadKm <= 0 {
            let msg = L.s("이번 주 누적 거리 \(thisStr)km예요.", "This week's total: \(thisStr) km.")
            return RunInsight(category: .load, tone: .neutral, badge: L.s("주간 거리", "Weekly Load"),
                              message: msg, highlights: [thisStr + "km"])
        }
        let change   = (baseline.weeklyLoadKm - baseline.prevWeeklyLoadKm) / baseline.prevWeeklyLoadKm * 100
        let absPct   = String(format: "%.0f%%", abs(change))
        let prevStr  = String(format: "%.1f", baseline.prevWeeklyLoadKm)
        let direction = change >= 0 ? L.s("많아요", "more") : L.s("적어요", "less")
        let msg = L.s(
            "이번 주 \(thisStr)km로 지난주(\(prevStr)km)보다 \(absPct) \(direction).",
            "This week \(thisStr) km — \(absPct) \(direction) than last week (\(prevStr) km)."
        )
        let tone: InsightTone = change > 40 ? .caution : .neutral
        let badge = change > 0 ? L.s("거리 증가", "Load Up") : L.s("주간 거리", "Weekly Load")
        return RunInsight(category: .load, tone: tone, badge: badge,
                          message: msg, highlights: [thisStr + "km", absPct])
    }

    // MARK: - VO2max Norm Table

    private enum VO2Level {
        case poor, belowAverage, average, good, excellent
        var korLabel: String {
            switch self {
            case .poor:         return "낮은 편"
            case .belowAverage: return "평균 이하"
            case .average:      return "평균 수준"
            case .good:         return "평균 이상"
            case .excellent:    return "우수한 수준"
            }
        }
        var enLabel: String {
            switch self {
            case .poor:         return "below average"
            case .belowAverage: return "slightly below average"
            case .average:      return "average"
            case .good:         return "above average"
            case .excellent:    return "excellent"
            }
        }
    }

    private static let normsMale: [(ageMax: Int, t: [Double])] = [
        (25,  [38, 42, 46, 52]),
        (35,  [36, 40, 44, 50]),
        (45,  [34, 38, 42, 47]),
        (55,  [32, 35, 40, 46]),
        (65,  [28, 32, 37, 44]),
        (999, [25, 29, 34, 40]),
    ]
    private static let normsFemale: [(ageMax: Int, t: [Double])] = [
        (25,  [31, 35, 39, 44]),
        (35,  [30, 33, 37, 41]),
        (45,  [28, 31, 35, 40]),
        (55,  [25, 28, 32, 37]),
        (65,  [22, 25, 29, 35]),
        (999, [20, 23, 27, 32]),
    ]

    private static func vo2Level(vo2: Double, age: Int, isMale: Bool) -> VO2Level {
        let table = isMale ? normsMale : normsFemale
        guard let row = table.first(where: { age <= $0.ageMax }) else { return .average }
        let t = row.t
        if vo2 < t[0] { return .poor }
        if vo2 < t[1] { return .belowAverage }
        if vo2 < t[2] { return .average }
        if vo2 < t[3] { return .good }
        return .excellent
    }

    // MARK: - Helpers

    private static func interpolateKm(
        offset: TimeInterval,
        splits: [SplitData],
        totalDuration: TimeInterval,
        totalKm: Double
    ) -> Double {
        guard !splits.isEmpty else {
            guard totalDuration > 0 else { return 0 }
            return totalKm * min(1, max(0, offset / totalDuration))
        }
        var t: TimeInterval = 0; var km: Double = 0
        for split in splits {
            let nextT  = t + split.duration
            let nextKm = km + split.distanceM / 1000.0
            if offset < nextT {
                guard split.duration > 0 else { return km }
                return km + (split.distanceM / 1000.0) * (offset - t) / split.duration
            }
            t = nextT; km = nextKm
        }
        return min(totalKm, km)
    }

    private static func hrInWindow(
        around offset: TimeInterval,
        window: TimeInterval = 15,
        hrSamples: [(offset: TimeInterval, bpm: Int)]
    ) -> Int? {
        let nearby = hrSamples.filter { abs($0.offset - offset) <= window }
        guard !nearby.isEmpty else { return nil }
        return nearby.map(\.bpm).reduce(0, +) / nearby.count
    }

    private static func movingMedian(_ values: [Double], window: Int) -> [Double] {
        let w = max(1, window)
        return values.indices.map { i in
            let lo = max(0, i - w / 2)
            let hi = min(values.count, i + w / 2 + 1)
            var slice = Array(values[lo ..< hi])
            slice.sort()
            return slice.isEmpty ? 0 : slice[slice.count / 2]
        }
    }
}
