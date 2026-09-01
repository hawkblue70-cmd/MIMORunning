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
    case fadeCause       = "후반 감속 원인"
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

// MARK: - Fade Analysis Types

enum FadeCause {
    case overpace       // 초반 오버페이스
    case threshold      // 역치 초과
    case enduranceGap   // 지구력 부족
    case mixed          // 복합 요인
    case unclear        // 판단 어려움
}

struct FadeAnalysis {
    let dropPercent: Double       // 후반 감속률 (%)
    let fadeStartKm: Double?      // 감속 시작 지점
    let hrHeldUp: Bool            // 심박은 유지됐는가
    let earlyOverpace: Bool       // 초반 평균보다 빨랐는가
    let earlyHighHR: Bool         // 전반부 Z4+ 심박 여부
    let recentLongRunKm: Double   // 최근 4주 최장 거리
    let cause: FadeCause
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
        for split in splits { cumKm.append((cumKm.last ?? 0) + split.distanceM / 1000.0) }

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

    // MARK: - HRmax 추정
    //
    // ⚠ 220−나이는 쓰지 않는다.
    //   Tanaka 2001 (JACC 37(1):153–156, 351편 메타 / 18,712명):
    //   220−나이는 50대 이상에서 체계적으로 과소추정한다.
    //   우선순위: (1) 엔진이 관측한 값, (2) 208−0.7×나이(Tanaka), (3) nil.
    private static func estimatedHRMax(hrMax: Double?, age: Int?) -> Int? {
        if let h = hrMax { return Int(h.rounded()) }
        guard let a = age else { return nil }
        return Int((208.0 - 0.7 * Double(a)).rounded())
    }

    // MARK: - Insights (main entry point)

    static func insights(
        for activity: Activity,
        detail: ActivityDetail? = nil,
        history: [Activity],
        age: Int?,
        isMale: Bool?,
        restingHR: Int?,
        hrSamples: [(offset: TimeInterval, bpm: Int)] = [],
        hrMax: Double? = nil,
        lt1HR: Double? = nil,
        lt1SD: Double = 0,
        easyCeilingHR: Double? = nil,
        heat: MRHeatModel
    ) -> (insights: [RunInsight], segmentSource: RunSegmentSource, fadeStartKm: Double?) {
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
                                      history: history, base: base, age: age, isMale: isMale,
                                      hrSamples: hrSamples)
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
                { easyOverpaceInsight(activity: activity, age: age, hrMax: hrMax) },
                { environmentInsight(activity: activity) },
                { cardioInsight(detail: detail, age: age, isMale: isMale) },
                { loadInsight(baseline: base) },
            ]
            for gen in generators where results.count < 4 {
                if let i = gen() { results.append(i) }
            }

        case .longRun, .lsd:
            let mhrLL = estimatedHRMax(hrMax: hrMax, age: age)
            let generators: [() -> RunInsight?] = [
                { cardiacDriftInsight(activity: activity, hrSamples: hrSamples, category: .efficiency) },
                { fadeCauseInsight(activity: activity, detail: detail, history: history, hrSamples: hrSamples, maxHR: mhrLL)
                  ?? enduranceInsight(detail: detail) },
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
            let mhrDR = estimatedHRMax(hrMax: hrMax, age: age)
            let generators: [() -> RunInsight?] = [
                { distanceRunInsight(activity: activity, baseline: base, heat: heat,
                                     lt1HR: lt1HR, lt1SD: lt1SD, easyCeilingHR: easyCeilingHR) },
                { fadeCauseInsight(activity: activity, detail: detail, history: history, hrSamples: hrSamples, maxHR: mhrDR)
                  ?? enduranceInsight(detail: detail) },
                { efficiencyInsight(activity: activity, history: history) },
                { cardioInsight(detail: detail, age: age, isMale: isMale) },
            ]
            for gen in generators where results.count < 4 {
                if let i = gen() { results.append(i) }
            }

        default:
            appendGeneralInsights(into: &results, activity: activity, detail: detail,
                                  history: history, base: base, age: age, isMale: isMale,
                                  hrSamples: hrSamples, hrMax: hrMax,
                                  lt1HR: lt1HR, lt1SD: lt1SD, easyCeilingHR: easyCeilingHR)
        }

        let maxHRForFade = estimatedHRMax(hrMax: hrMax, age: age)
        let fadeKm = analyzeFade(activity: activity, detail: detail, history: history,
                                 hrSamples: hrSamples, maxHR: maxHRForFade)?.fadeStartKm
        return (Array(results.prefix(4)), segSource, fadeKm)
    }

    private static func appendGeneralInsights(
        into results: inout [RunInsight],
        activity: Activity,
        detail: ActivityDetail?,
        history: [Activity],
        base: RunBaseline,
        age: Int?,
        isMale: Bool?,
        hrSamples: [(offset: TimeInterval, bpm: Int)],
        hrMax: Double? = nil,
        lt1HR: Double? = nil,
        lt1SD: Double = 0,
        easyCeilingHR: Double? = nil
    ) {
        let maxHR = estimatedHRMax(hrMax: hrMax, age: age)
        let generators: [() -> RunInsight?] = [
            { cardioInsight(detail: detail, age: age, isMale: isMale) },
            { intensityInsight(activity: activity, detail: detail, age: age,
                               hrMax: hrMax, lt1HR: lt1HR, lt1SD: lt1SD, easyCeilingHR: easyCeilingHR) },
            { fadeCauseInsight(activity: activity, detail: detail, history: history, hrSamples: hrSamples, maxHR: maxHR)
              ?? enduranceInsight(detail: detail) },
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

    private static func easyOverpaceInsight(activity: Activity, age: Int?, hrMax: Double? = nil) -> RunInsight? {
        guard let avgHR = activity.avgHeartRate,
              let mhr = estimatedHRMax(hrMax: hrMax, age: age), mhr > 0 else { return nil }
        let L = AppLanguage.shared
        let pct    = Double(avgHR) / Double(mhr) * 100
        let pctStr = String(format: "%.0f%%", pct)

        if pct > 75 {
            let msg = L.s(
                "이지런 기준 심박이 \(pctStr)로 다소 높았어요 — 더 여유롭게 가도 좋아요.",
                "HR at \(pctStr) of max for an easy run — it's fine to go a bit easier."
            )
            return RunInsight(category: .intensity, tone: .caution, badge: L.s("강도 참고", "Effort Note"),
                              message: msg, highlights: [pctStr])
        }
        let msg = L.s(
            "심박 \(pctStr)로 여유 있는 강도의 이지런이었어요.",
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

    private static func distanceRunInsight(
        activity: Activity,
        baseline: RunBaseline,
        heat: MRHeatModel,
        lt1HR: Double? = nil,
        lt1SD: Double = 0,
        easyCeilingHR: Double? = nil
    ) -> RunInsight? {
        guard let currentPace = activity.paceSecPerKm,
              let medianPace  = baseline.medianPaceSec,
              medianPace > 0, baseline.sampleCount >= 3 else { return nil }
        let L = AppLanguage.shared
        let tempC = activity.temperatureC

        // ① 기온 보정: 오늘 페이스 → 15°C 기준 환산
        // ⚠ 여름 러닝은 기온 탓에 항상 "느렸어요"가 나온다.
        //   본인 더위 계수로 보정 후 비교해야 공정하다.
        let adjustedPace = currentPace * exp(heat.logDelta(tempC))
        let raw  = currentPace - medianPace    // 미보정 차이 (양수 = 느림)
        let diff = adjustedPace - medianPace   // 보정 후 차이
        let heatExplains = heat.ok
            && (tempC.map { abs($0 - MR_REF_TEMP) >= 5 } ?? false)
            && abs(raw - diff) >= 5            // 보정이 5초 이상 차이를 만들었을 때

        let diffToShow = heatExplains ? diff : raw
        guard heatExplains || abs(diffToShow) > 5 else { return nil }

        let currentStr = String(format: "%d'%02d\"", Int(currentPace) / 60, Int(currentPace) % 60)
        var parts: [String] = []
        var highlights: [String] = [currentStr]
        var tone: InsightTone = .neutral

        // ① 페이스 비교 문장
        if heatExplains && abs(diff) < 5 {
            let tempStr = tempC.map { "\(Int($0.rounded()))°C" } ?? ""
            parts.append(L.s(
                "평균 페이스 \(currentStr) — \(tempStr)를 감안하면 평소와 같습니다.",
                "Avg pace \(currentStr) — on par with recent average for \(tempStr)."
            ))
            tone = .good
        } else {
            let absDiff = abs(diffToShow)
            let diffStr = "\(Int(absDiff.rounded()))초"
            highlights.append(diffStr)
            let direction = diffToShow < 0 ? L.s("빨랐어요", "faster") : L.s("느렸어요", "slower")
            tone = diffToShow < 0 ? .good : .neutral
            if heatExplains {
                let tempStr = tempC.map { "\(Int($0.rounded()))°C" } ?? ""
                parts.append(L.s(
                    "평균 페이스 \(currentStr) — \(tempStr) 감안해도 \(diffStr) \(direction).",
                    "Avg pace \(currentStr) — \(diffStr) \(direction) even after heat adjustment."
                ))
            } else {
                parts.append(L.s(
                    "평균 페이스 \(currentStr) — 최근 평균보다 \(diffStr) \(direction).",
                    "Avg pace \(currentStr) — \(diffStr) \(direction) than recent average."
                ))
            }
        }

        // ② 심박 / LT1 해석 문장
        if let ceil = easyCeilingHR, let lt1 = lt1HR, let avgHR = activity.avgHeartRate {
            let hrText: String
            if Double(avgHR) < ceil {
                hrText = L.s(
                    "유산소 구간 안에서 달리셨어요.",
                    "You stayed in the aerobic zone.")
                tone = .good
            } else if Double(avgHR) < lt1 + lt1SD {
                hrText = L.s(
                    "이지보다 템포에 가까운 날이었습니다.",
                    "Closer to tempo than easy today.")
            } else {
                hrText = L.s(
                    "꽤 강하게 밀어붙이셨네요.",
                    "You pushed pretty hard today.")
            }
            parts.append(hrText)
            highlights.append("\(avgHR)bpm")
        }

        let badge = heatExplains ? L.s("기온 감안", "Heat-Adjusted") : L.s("페이스 비교", "Pace vs History")
        return RunInsight(category: .intensity, tone: tone, badge: badge,
                          message: parts.joined(separator: " "), highlights: highlights)
    }

    // MARK: - Fade Cause Analysis

    static func analyzeFade(
        activity: Activity,
        detail: ActivityDetail?,
        history: [Activity],
        hrSamples: [(offset: TimeInterval, bpm: Int)],
        maxHR: Int?
    ) -> FadeAnalysis? {
        // 인터벌·빌드업은 감속이 정상 — 분석 제외
        // [99] .race 추가: 대회 감속 분석 필요. .easy/.tempo: 감속이 의미 있는 신호.
        let wt = detail?.workoutType ?? .general
        #if DEBUG
        let df99 = DateFormatter(); df99.dateFormat = "M/d"
        let dateStr99 = df99.string(from: activity.date)
        let distStr99 = String(format: "%.1f", activity.distance / 1000)
        func wtKo(_ w: WorkoutType) -> String {
            switch w {
            case .race: return "대회"
            case .longRun: return "롱런"
            case .lsd: return "LSD"
            case .distanceRun: return "거리주"
            case .general: return "일반"
            case .easy: return "이지런"
            case .tempo: return "템포"
            case .interval: return "인터벌"
            case .buildUp: return "빌드업"
            }
        }
        #endif
        switch wt {
        case .race, .longRun, .lsd, .distanceRun, .easy, .tempo, .general: break
        default:
            #if DEBUG
            print("[감속] \(dateStr99) \(distStr99)km type=\(wtKo(wt)) → 인터벌/빌드업 제외")
            #endif
            return nil
        }

        guard let splits = detail?.splits, splits.count >= 6 else {
            #if DEBUG
            let cnt = detail?.splits.count ?? 0
            print("[감속] \(dateStr99) \(distStr99)km type=\(wtKo(wt)) → 스플릿 \(cnt)개 (최소 6개 필요) → 분석 안 함")
            #endif
            return nil
        }

        // 전반/후반 페이스 드리프트
        let half      = splits.count / 2
        let frontPaces = Array(splits[..<half]).map { $0.paceSecPerKm }.filter { $0 > 0 }
        let backPaces  = Array(splits[half...]).map { $0.paceSecPerKm }.filter { $0 > 0 }
        guard !frontPaces.isEmpty, !backPaces.isEmpty else { return nil }

        let avgFront = frontPaces.reduce(0.0, +) / Double(frontPaces.count)
        let avgBack  = backPaces.reduce(0.0,  +) / Double(backPaces.count)
        guard avgFront > 0 else { return nil }

        let dropPercent = (avgBack - avgFront) / avgFront * 100
        guard dropPercent >= 8 else {
            #if DEBUG
            print("[감속] \(dateStr99) \(distStr99)km type=\(wtKo(wt)) · 감속 \(String(format:"%.1f", dropPercent))% (기준 8% 미만) → 분석 안 함")
            #endif
            return nil
        }

        // fadeStartKm: 앞 1/3 중앙 페이스 대비 연속 2구간 이상 10% 이상 느린 첫 지점
        let frontThirdCount = max(1, splits.count / 3)
        var ftSorted = Array(splits[..<frontThirdCount]).map { $0.paceSecPerKm }.filter { $0 > 0 }
        ftSorted.sort()
        let frontMedian: Double = ftSorted.isEmpty ? avgFront : ftSorted[ftSorted.count / 2]

        var fadeStartKm: Double? = nil
        if frontMedian > 0 {
            var cumKm: Double = 0; var consecutiveSlow = 0; var candidateKm: Double? = nil
            for split in splits {
                if split.paceSecPerKm > frontMedian * 1.10 {
                    consecutiveSlow += 1
                    if consecutiveSlow == 1 { candidateKm = cumKm }
                    if consecutiveSlow >= 2 { fadeStartKm = candidateKm; break }
                } else {
                    consecutiveSlow = 0; candidateKm = nil
                }
                cumKm += split.distanceM / 1000.0
            }
        }

        // HR 분석
        let mid      = activity.duration / 2
        let frontHRs = hrSamples.filter { $0.offset < mid  }.map(\.bpm)
        let backHRs  = hrSamples.filter { $0.offset >= mid }.map(\.bpm)

        let hrHeldUp: Bool
        if !frontHRs.isEmpty, !backHRs.isEmpty {
            let fAvg = Double(frontHRs.reduce(0, +)) / Double(frontHRs.count)
            let bAvg = Double(backHRs.reduce(0,  +)) / Double(backHRs.count)
            hrHeldUp = fAvg > 0 && bAvg >= fAvg * 0.95
        } else {
            hrHeldUp = false
        }

        // earlyOverpace: 전반 페이스가 최근 8주 중앙보다 5%+ 빠른가
        let eightWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: activity.date) ?? .distantPast
        var recentPaces = history.filter {
            $0.type == .running && $0.id != activity.id &&
            $0.date >= eightWeeksAgo && $0.date < activity.date
        }.compactMap { $0.paceSecPerKm }
        recentPaces.sort()

        let earlyOverpace: Bool
        if !recentPaces.isEmpty {
            let recentMedian = recentPaces[recentPaces.count / 2]
            earlyOverpace = recentMedian > 0 && avgFront < recentMedian * 0.95
        } else {
            earlyOverpace = false
        }

        // earlyHighHR: 전반 평균 심박 >= maxHR * 0.85
        let earlyHighHR: Bool
        if let mhr = maxHR, mhr > 0, !frontHRs.isEmpty {
            let fAvg = Double(frontHRs.reduce(0, +)) / Double(frontHRs.count)
            earlyHighHR = fAvg >= Double(mhr) * 0.85
        } else {
            earlyHighHR = false
        }

        // 최근 4주 최장 거리
        let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: activity.date) ?? .distantPast
        let recentLongRunKm = history.filter {
            $0.type == .running && $0.id != activity.id &&
            $0.date >= fourWeeksAgo && $0.date < activity.date
        }.map { $0.distance / 1000.0 }.max() ?? 0

        // 원인 판정
        let actDistKm = activity.distance / 1000.0
        let cause: FadeCause
        if earlyOverpace && earlyHighHR {
            cause = .overpace
        } else if earlyHighHR && !hrHeldUp {
            cause = .threshold
        } else if actDistKm > 0 && recentLongRunKm < actDistKm * 0.6 {
            // [106] hrHeldUp 조건 제거 — 심박이 오히려 떨어지면서 페이스가 무너지는 것이
            //        근지구력 소진의 전형적 패턴. hrHeldUp 요구시 가장 명확한 사례를 놓침.
            cause = .enduranceGap
        } else if earlyOverpace || earlyHighHR {
            cause = .mixed
        } else {
            cause = .unclear
        }

        #if DEBUG
        func causeKo(_ c: FadeCause) -> String {
            switch c {
            case .overpace: return "초반 과속"
            case .threshold: return "젖산역치"
            case .enduranceGap: return "지구력 부족"
            case .mixed: return "복합"
            case .unclear: return "원인 미상"
            }
        }
        let fadeKmStr = fadeStartKm.map { String(format: "%.1f", $0) + "km" } ?? "특정 불가"
        print("[감속] \(dateStr99) \(distStr99)km type=\(wtKo(wt)) · 후반 감속 \(String(format:"%.1f", dropPercent))%")
        print("[감속]   감속 시작 = \(fadeKmStr) · 원인 = \(causeKo(cause))")
        // [104] 원인 판정 근거 상세 로그
        print("[감속]   hrHeldUp=\(hrHeldUp) · earlyOverpace=\(earlyOverpace) · earlyHighHR=\(earlyHighHR)")
        print("[감속]   최근4주 최장=\(String(format:"%.1f",recentLongRunKm))km · 당일=\(distStr99)km")
        if cause == .enduranceGap, recentLongRunKm > 0 {
            let ratio = actDistKm / recentLongRunKm
            print("[감속] 원인 = 지구력 부족 (준비 최장 \(String(format:"%.1f",recentLongRunKm))km / 당일 \(distStr99)km · \(String(format:"%.1f",ratio))배)")
        }
        #endif
        return FadeAnalysis(
            dropPercent: dropPercent,
            fadeStartKm: fadeStartKm,
            hrHeldUp: hrHeldUp,
            earlyOverpace: earlyOverpace,
            earlyHighHR: earlyHighHR,
            recentLongRunKm: recentLongRunKm,
            cause: cause
        )
    }

    private static func fadeCauseInsight(
        activity: Activity,
        detail: ActivityDetail?,
        history: [Activity],
        hrSamples: [(offset: TimeInterval, bpm: Int)],
        maxHR: Int?
    ) -> RunInsight? {
        guard let fa = analyzeFade(activity: activity, detail: detail, history: history,
                                   hrSamples: hrSamples, maxHR: maxHR) else { return nil }
        let L = AppLanguage.shared
        let suffix = L.s(" 당일 컨디션이나 날씨 영향일 수도 있어요.",
                         " Day-of conditions or weather may also have played a role.")
        let fkmStr     = fa.fadeStartKm.map { String(format: "%.1f", $0) + "km" }
        let recentStr  = String(format: "%.1f", fa.recentLongRunKm) + "km"

        let tone: InsightTone; let badge: String; let msg: String; var highlights: [String] = []

        switch fa.cause {
        case .overpace:
            tone = .caution; badge = L.s("페이스 배분", "Pacing")
            if let fkm = fkmStr {
                msg = L.s(
                    "초반 페이스가 최근 평균보다 빨랐고 심박도 높게 시작했어요. \(fkm) 부터 감속이 시작된 걸 보면 초반 배분이 원인일 가능성이 있어요." + suffix,
                    "Early pace was faster than recent average and HR started high. Deceleration appeared around \(fkm), which may suggest pacing was too aggressive early on." + suffix
                )
                highlights = [fkm]
            } else {
                msg = L.s(
                    "초반 페이스가 최근 평균보다 빨랐고 심박도 높게 시작했어요. 초반 배분이 원인일 가능성이 있어요." + suffix,
                    "Early pace was faster than recent average and HR started high. This may suggest pacing was too aggressive early on." + suffix
                )
            }

        case .threshold:
            tone = .caution; badge = L.s("강도", "Intensity")
            msg = L.s(
                "전반부터 심박이 역치 구간(최대심박 85% 이상)에 머물렀어요. 그 강도를 오래 유지하기 어려워 후반에 느려진 것으로 보여요." + suffix,
                "HR stayed in the threshold zone (85%+ of max HR) from the start. Sustaining that intensity may have led to the slowdown." + suffix
            )

        case .enduranceGap:
            tone = .neutral; badge = L.s("지구력", "Endurance")
            let ratio = fa.recentLongRunKm > 0 ? activity.distance / 1000 / fa.recentLongRunKm : 0
            let ratioStr = String(format: "%.1f", ratio)
            // [106] 문구: 관찰 수준만 — 메커니즘 표현 없음
            msg = L.s(
                "준비한 최장 거리(\(recentStr))의 \(ratioStr)배를 뛰었어요." + suffix,
                "Today's run was \(ratioStr)× your longest preparation run (\(recentStr))." + suffix
            )
            highlights = [recentStr]

        case .mixed:
            tone = .neutral; badge = L.s("복합", "Mixed")
            msg = L.s(
                "초반 강도와 지구력 요인이 함께 작용한 것으로 보여요." + suffix,
                "Both early intensity and endurance factors may have contributed." + suffix
            )

        case .unclear:
            tone = .neutral; badge = L.s("참고", "Note")
            if let fkm = fkmStr {
                msg = L.s(
                    "\(fkm) 부터 감속이 있었어요. 컨디션·기온·보급 등 기록에 없는 요인도 영향을 줬을 수 있어요.",
                    "Deceleration appeared around \(fkm). Factors not in the record — such as conditions, temperature, or fueling — may also have had an effect."
                )
                highlights = [fkm]
            } else {
                msg = L.s(
                    "후반 감속이 있었어요. 컨디션·기온·보급 등 기록에 없는 요인도 영향을 줬을 수 있어요.",
                    "Deceleration in the second half. Factors not in the record — such as conditions, temperature, or fueling — may also have had an effect."
                )
            }
        }

        return RunInsight(category: .fadeCause, tone: tone, badge: badge,
                          message: msg, highlights: highlights)
    }

    // MARK: - General Insights (existing rules)

    private static func cardioInsight(
        detail: ActivityDetail?,
        age: Int?,
        isMale: Bool?
    ) -> RunInsight? {
        guard let vo2 = detail?.vo2Max, let age else { return nil }
        let L = AppLanguage.shared
        let voStr = String(format: "%.1f", vo2)
        let useMale = isMale ?? true
        let (level, norm) = vo2MaxLevel(vo2: vo2, age: age, isMale: useMale)
        let levelLabel = L.s(level.rawValue, level.enLabel)

        // Age group string (e.g. "50대" / "50s")
        let ageDecade: String
        if let n = norm {
            let lo = n.range.lowerBound
            ageDecade = lo >= 60 ? L.s("60대 이상", "60+") : L.s("\(lo / 10 * 10)대", "\(lo)s")
        } else {
            ageDecade = L.s("해당 연령대", "your age group")
        }
        let genderSuffix = isMale == nil ? "" : L.s(useMale ? " 남성" : " 여성", useMale ? " male" : " female")

        let suffix = ""

        let mainMsg: String
        switch level {
        case .high:
            mainMsg = L.s(
                "유산소 피트니스 \(voStr)는 \(ageDecade)\(genderSuffix) 기준 '높음'이에요.",
                "Cardio fitness \(voStr) is 'High' for \(ageDecade)\(genderSuffix)."
            )
        case .aboveAvg:
            mainMsg = L.s(
                "유산소 피트니스 \(voStr)는 \(ageDecade)\(genderSuffix) 기준 '평균 이상'이에요.",
                "Cardio fitness \(voStr) is 'Above Average' for \(ageDecade)\(genderSuffix)."
            )
        case .belowAvg:
            mainMsg = L.s(
                "유산소 피트니스 \(voStr)는 \(ageDecade)\(genderSuffix) 기준 '평균 이하'예요. 꾸준한 유산소 운동으로 올릴 수 있어요.",
                "Cardio fitness \(voStr) is 'Below Average' for \(ageDecade)\(genderSuffix). Consistent aerobic training can help."
            )
        case .low:
            mainMsg = L.s(
                "유산소 피트니스 \(voStr)는 \(ageDecade)\(genderSuffix) 기준 '낮음' 구간이에요. 가벼운 유산소부터 쌓아가면 좋아요.",
                "Cardio fitness \(voStr) is in the 'Low' range for \(ageDecade)\(genderSuffix). Building up with easy aerobic runs will help."
            )
        }

        return RunInsight(
            category: .cardio,
            tone: level.tone,
            badge: levelLabel,
            message: mainMsg + suffix,
            highlights: [voStr, levelLabel]
        )
    }

    private static func intensityInsight(
        activity: Activity,
        detail: ActivityDetail?,
        age: Int?,
        hrMax: Double? = nil,
        lt1HR: Double? = nil,
        lt1SD: Double = 0,
        easyCeilingHR: Double? = nil
    ) -> RunInsight? {
        guard let avgHR = activity.avgHeartRate else { return nil }
        let L = AppLanguage.shared
        var parts: [String] = []
        var highlights: [String] = []
        var tone: InsightTone = .neutral

        // ⚠ LT1이 있으면 인구 평균(%HRmax)이 아니라 **본인 역치**로 말한다.
        //   Nuuttila 2025 (n=165): LT1은 남 78.5% · 여 80.0% HRmax.
        //   같은 82%라도 LT1이 80%면 임계 위, 84%면 임계 아래다. %HRmax는 구분 못 한다.
        if let ceil = easyCeilingHR, let lt1 = lt1HR {
            let text: String
            if Double(avgHR) < ceil {
                text = L.s(
                    "유산소 구간 안에서 달리셨어요. 이런 날이 오래 가는 다리를 만듭니다.",
                    "You stayed in the aerobic zone. Runs like this build lasting endurance.")
                tone = .good
            } else if Double(avgHR) < lt1 + lt1SD {
                text = L.s(
                    "이지보다 템포에 가까운 날이었습니다. 나쁜 건 아니고, 다음 한 번을 조금 느리게 잡아두면 균형이 맞아요.",
                    "Closer to tempo than easy today. Nothing wrong with that — one easy session next time keeps the balance.")
                tone = .neutral
            } else {
                text = L.s(
                    "꽤 강하게 밀어붙이셨네요. 내일은 가볍게 가셔도 좋습니다.",
                    "You pushed pretty hard today. Tomorrow can be an easy one.")
                tone = .good
            }
            parts.append(text)
            highlights.append("\(avgHR)bpm")
        } else if let mhr = estimatedHRMax(hrMax: hrMax, age: age), mhr > 0 {
            // LT1 없음 — %HRmax 폴백 (Tanaka, 엔진 관측값 우선)
            let pct = Double(avgHR) / Double(mhr) * 100
            let zoneName: String
            switch pct {
            case ..<60:   zoneName = L.s("저강도", "low intensity")
            case 60..<70: zoneName = L.s("저강도", "low-moderate")
            case 70..<80: zoneName = L.s("중강도", "moderate");        tone = .good
            case 80..<90: zoneName = L.s("중고강도", "moderate-high"); tone = .good
            default:      zoneName = L.s("고강도", "high intensity");  tone = .caution
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
            // 직전 런과의 공백이 14일 이상이면 원인을 공백으로 귀속
            let gapDays: Int? = {
                let sorted = history.filter { $0.type == .running && $0.date < activity.date }
                                    .sorted { $0.date < $1.date }
                guard let last = sorted.last else { return nil }
                let g = Calendar.current.dateComponents([.day], from: last.date, to: activity.date).day ?? 0
                return g >= 14 ? g : nil
            }()
            let cause = gapDays.map { L.s("\($0)일 공백의 영향일 수 있어요.", "\($0)-day break may be a factor.") }
                     ?? L.s("오늘 컨디션을 반영한 것일 수 있어요.", "may reflect today's condition.")
            let msg = L.s(
                "비슷한 페이스 최근 \(sampleStr)회 대비 심박이 \(diffStr) bpm 높아요. \(cause)",
                "HR is \(diffStr) bpm higher vs \(sampleStr) similar-pace runs — \(cause)"
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
        let tone: InsightTone = .good
        let cadStr = "\(cadence)"

        // ⚠ "175~185로 올려보세요"를 근거 없이 말하지 않는다.
        //   최적 케이던스는 신장·다리길이·페이스에 따라 달라진다.
        //   Cavanagh & Williams (1982 Med Sci Sports Exerc): 선수들은 자신에게 맞는 케이던스를 자연스럽게 선택.
        //   Heiderscheit (2011 J Orthop Sports Phys Ther): 5–10% 증가로 하중 감소 — 목표 수치는 제시 안 함.
        //   180spm은 Daniels의 엘리트 선수 관찰값이지, 일반 러너 처방 범위가 아니다.
        parts.append(L.s("케이던스 \(cadStr)spm", "Cadence \(cadStr) spm"))
        highlights.append(cadStr)

        if let gct = detail?.avgGroundContactTime {
            let ms = Int(gct.rounded())
            parts.append(L.s("지면접촉 \(ms)ms.", "Ground contact \(ms)ms."))
            highlights.append("\(ms)ms")
        }

        if let stride = detail?.avgStrideLength {
            let strideStr = String(format: "%.2fm", stride)
            parts.append(L.s("보폭 \(strideStr)이에요.", "Stride length \(strideStr)."))
            highlights.append(strideStr)
        }

        let badge = L.s("주법", "Form")
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

    // MARK: - VO2max Norm Table (FRIEND / Apple Health)

    // FRIEND = Fitness Registry and Importance of Exercise National Database
    // Thresholds confirmed against Apple Health cardio fitness norms
    private enum VO2MaxLevel: String {
        case high = "높음"; case aboveAvg = "평균 이상"; case belowAvg = "평균 이하"; case low = "낮음"
        var enLabel: String {
            switch self {
            case .high:     return "High"
            case .aboveAvg: return "Above Average"
            case .belowAvg: return "Below Average"
            case .low:      return "Low"
            }
        }
        var tone: InsightTone {
            switch self { case .high, .aboveAvg: return .good; case .belowAvg, .low: return .neutral }
        }
    }

    // (ageRange, High threshold, Above Average threshold, Below Average threshold)
    // vo2 >= high → .high; >= aboveAvg → .aboveAvg; >= belowAvg → .belowAvg; else → .low
    // Values confirmed against Apple Health cardio fitness screens (FRIEND database)
    private static let maleNormsFriend: [(range: ClosedRange<Int>, high: Double, aboveAvg: Double, belowAvg: Double)] = [
        (20...29, 57, 48, 38),
        (30...39, 52, 43, 34),
        (40...49, 47, 38, 31),
        (50...59, 41, 33, 26),
        (60...120, 36, 28, 18)
    ]
    private static let femaleNormsFriend: [(range: ClosedRange<Int>, high: Double, aboveAvg: Double, belowAvg: Double)] = [
        (20...29, 47, 38, 29),
        (30...39, 38, 30, 24),
        (40...49, 34, 27, 21),
        (50...59, 29, 23, 19),
        (60...120, 25, 20, 15)
    ]

    private static func vo2MaxLevel(
        vo2: Double, age: Int, isMale: Bool
    ) -> (level: VO2MaxLevel, norm: (range: ClosedRange<Int>, high: Double, aboveAvg: Double, belowAvg: Double)?) {
        let norms = isMale ? maleNormsFriend : femaleNormsFriend
        guard let row = norms.first(where: { $0.range.contains(age) }) else { return (.belowAvg, nil) }
        let level: VO2MaxLevel
        if vo2 >= row.high          { level = .high }
        else if vo2 >= row.aboveAvg { level = .aboveAvg }
        else if vo2 >= row.belowAvg { level = .belowAvg }
        else                        { level = .low }
        return (level, row)
    }

    // MARK: - Public VO2 Fitness Info

    struct VO2FitnessInfo {
        let levelLabel: String
        let normBelowAvg: Double
        let normAboveAvg: Double
        let normHigh: Double
        let ageDecade: String
        let genderLabel: String
    }

    static func vo2FitnessInfo(vo2: Double, age: Int, isMale: Bool?) -> VO2FitnessInfo? {
        let male = isMale ?? true
        let result = vo2MaxLevel(vo2: vo2, age: age, isMale: male)
        guard let norm = result.norm else { return nil }
        let L = AppLanguage.shared
        let decade: String
        switch age {
        case ..<30: decade = L.s("20대", "20s")
        case ..<40: decade = L.s("30대", "30s")
        case ..<50: decade = L.s("40대", "40s")
        case ..<60: decade = L.s("50대", "50s")
        default:    decade = L.s("60대+", "60s+")
        }
        let gender = isMale == nil ? "" : (male ? L.s("남성", "M") : L.s("여성", "F"))
        return VO2FitnessInfo(
            levelLabel: result.level.rawValue,
            normBelowAvg: norm.belowAvg,
            normAboveAvg: norm.aboveAvg,
            normHigh: norm.high,
            ageDecade: decade,
            genderLabel: gender
        )
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
