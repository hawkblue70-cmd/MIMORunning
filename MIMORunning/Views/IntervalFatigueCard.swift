import SwiftUI
import Charts

// MARK: - Interval Fatigue Analysis Card
// Inserted inside RunFormCardView for interval workouts.
// Receives ALL interval segments; filters work / recovery internally.

struct IntervalFatigueCard: View {

    let segments: [IntervalSegment]
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    var workoutStart: Date = .distantPast

    private var workSegs: [IntervalSegment] { segments.filter { $0.stepLabel == "운동" } }
    private var recSegs:  [IntervalSegment] { segments.filter { $0.stepLabel == "회복" } }

    // MARK: - Internal Types

    // Interpretation category — drives 해석 text and 제안 content.
    // ① 근피로   : pace dropped ≥1%, stride dominant, HR stable
    // ② 심폐부담 : pace maintained + HR rose ≥5 bpm
    // ③ 리듬붕괴 : pace dropped ≥1%, cadence dominant, HR stable
    // ⑤ 정상     : pace maintained, HR stable
    // ⑥ 네거티브 : pace improved ≥1%, HR rose (natural response)
    //   lateBoost: pace improved ≥1%, HR stable (positive, no HR rise)
    //   cardioLimit: pace dropped ≥1% + HR rose (한계 구간)
    private enum InterpType {
        case muscFatigue, cardioStress, cardioLimit, rhythmCollapse
        case normal, lateBoost, negativeSplit
    }

    enum StrideKind  { case muscFatigue, rhythmCollapse }
    enum HRStatus    { case drop, stable, slip, rise }

    struct ChartPoint: Identifiable {
        let id: Int; let value: Double
    }

    // Badge shown below the normalized cadence·stride chart
    private enum NormBadgeKind {
        case muscFatigue    // stride dropped more
        case rhythmCollapse // cadence dropped more
        case bothDecline    // both dropped comparably
        case styleChange    // one rose while the other fell
        case stable         // both within ±2%
    }

    // MARK: - HR Window Helpers

    private func hrWindow(for seg: IntervalSegment) -> [(offset: TimeInterval, bpm: Int)] {
        let start = seg.startDate.timeIntervalSince(workoutStart)
        let end   = seg.endDate.timeIntervalSince(workoutStart)
        return hrSamples.filter { $0.offset >= start && $0.offset <= end }
    }

    private func recoveryHRDrop(for rec: IntervalSegment) -> Int? {
        let w = hrWindow(for: rec)
        guard w.count >= 2 else { return nil }
        return w.first!.bpm - w.last!.bpm
    }

    // MARK: - Outlier Detection (IQR, ≥5 segments)

    private var outlierIDs: Set<Int> {
        guard workSegs.count >= 5 else { return [] }
        let cads = workSegs.compactMap { $0.avgCadence.map(Double.init) }
        guard cads.count >= 5 else { return [] }
        let sorted = cads.sorted()
        let q1 = sorted[sorted.count / 4]
        let q3 = sorted[3 * sorted.count / 4]
        let fence = max((q3 - q1) * 1.5, 3.0)
        let lo = q1 - fence, hi = q3 + fence
        return Set(workSegs.compactMap { seg in
            guard let cad = seg.avgCadence.map(Double.init) else { return nil }
            return (cad < lo || cad > hi) ? seg.id : nil
        })
    }

    private var analysisSegs: [IntervalSegment] { workSegs.filter { !outlierIDs.contains($0.id) } }

    // MARK: - Early / Late Halves (middle excluded for odd N)

    private var halfCount: Int { analysisSegs.count / 2 }
    private var earlySegs: [IntervalSegment] { Array(analysisSegs.prefix(halfCount)) }
    private var lateSegs:  [IntervalSegment] { Array(analysisSegs.suffix(halfCount)) }

    private func avgInt(_ segs: [IntervalSegment], _ kp: KeyPath<IntervalSegment, Int?>) -> Double? {
        let v = segs.compactMap { $0[keyPath: kp].map(Double.init) }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
    private func avgDbl(_ segs: [IntervalSegment], _ kp: KeyPath<IntervalSegment, Double?>) -> Double? {
        let v = segs.compactMap { $0[keyPath: kp] }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    // MARK: - Axis 1: Pace

    private var earlyPace: Double? { avgDbl(earlySegs, \.paceSecPerKm) }
    private var latePace:  Double? { avgDbl(lateSegs,  \.paceSecPerKm) }

    // positive = slower (worse). Used throughout instead of a PaceStatus enum.
    private var paceDiffPct: Double? {
        guard let ep = earlyPace, let lp = latePace, ep > 0 else { return nil }
        return (lp - ep) / ep * 100
    }

    // MARK: - Axis 2: Stride vs Cadence contribution

    private var earlyStride: Double? { avgDbl(earlySegs, \.computedStride) }
    private var lateStride:  Double? { avgDbl(lateSegs,  \.computedStride) }
    private var earlyCad:    Double? { avgInt(earlySegs, \.avgCadence) }
    private var lateCad:     Double? { avgInt(lateSegs,  \.avgCadence) }

    private var strideDropPct: Double? {
        guard let es = earlyStride, let ls = lateStride, es > 0 else { return nil }
        return (es - ls) / es * 100
    }
    private var cadDropPct: Double? {
        guard let ec = earlyCad, let lc = lateCad, ec > 0 else { return nil }
        return (ec - lc) / ec * 100
    }

    // Only meaningful when pace dropped ≥1% (paceDiffPct ≥ 1).
    private var strideKind: StrideKind? {
        guard let diff = paceDiffPct, diff >= 1 else { return nil }
        switch (strideDropPct, cadDropPct) {
        case (nil, nil):                                   return nil
        case (.some, nil):                                 return .muscFatigue
        case (nil, .some):                                 return .rhythmCollapse
        case (.some(let sd), .some(let cd)):
            if sd <= 0 && cd <= 0 { return nil }
            return sd > cd ? .muscFatigue : .rhythmCollapse
        }
    }

    // MARK: - Axis 3: HR cost

    private var earlyHR: Double? { avgInt(earlySegs, \.avgHeartRate) }
    private var lateHR:  Double? { avgInt(lateSegs,  \.avgHeartRate) }

    private var hrStatus: HRStatus? {
        guard let eh = earlyHR, let lh = lateHR else { return nil }
        let d = lh - eh
        if d > 10 { return .rise   }
        if d >  8 { return .slip   }
        if d > -5 { return .stable }
        return .drop
    }

    private var hrRising: Bool { hrStatus == .rise || hrStatus == .slip }

    // MARK: - Interpretation Type
    //
    // Pace thresholds for interpretation: ±1% (finer than the old ±2%).
    // HR threshold: ≥5 bpm rise = cardio strain.
    //
    // pace improved (≤-1%): HR rose → ⑥ negativeSplit; HR stable → lateBoost
    // pace maintained (-1% ~ +1%): HR rose → ② cardioStress; HR stable → ⑤ normal
    // pace dropped (≥+1%): HR rose → cardioLimit (한계); stride ▼ → ① muscFatigue; cad ▼ → ③ rhythmCollapse

    private var interpretationType: InterpType {
        guard halfCount >= 1, let diff = paceDiffPct else { return .normal }

        if diff <= -1 {
            // 후반 페이스 빨라짐 (≥1% faster)
            return hrRising ? .negativeSplit : .lateBoost
        } else if diff < 1 {
            // 후반 페이스 유지 (±1% 이내)
            return hrRising ? .cardioStress : .normal
        } else {
            // 후반 페이스 저하 (≥1% slower)
            if hrRising { return .cardioLimit }
            if strideKind == .muscFatigue    { return .muscFatigue }
            if strideKind == .rhythmCollapse { return .rhythmCollapse }
            return .cardioStress  // fallback: no cadence data, assume cardio
        }
    }

    private var allWorkAvgPace: Double? { avgDbl(workSegs, \.paceSecPerKm) }

    // ④ 초반 오버페이스 — additive annotation appended to ①②③.
    // Only fires when pace dropped ≥1% AND first rep ≥3% faster than overall avg.
    private var hasOverpace: Bool {
        guard let diff = paceDiffPct, diff >= 1,
              let firstPace = workSegs.first?.paceSecPerKm,
              let avgPace = allWorkAvgPace, avgPace > 0 else { return false }
        return (avgPace - firstPace) / avgPace * 100 >= 3
    }

    private var overpaceDeltaSec: Int {
        guard let firstPace = workSegs.first?.paceSecPerKm,
              let avgPace = allWorkAvgPace else { return 0 }
        return Int((avgPace - firstPace).rounded())
    }

    // ①③ observation helper: stride vs cadence % drop comparison, shown instead of raw values.
    // Returns nil when only one metric is available or changes are negligible.
    private var strideVsCadenceComparison: String? {
        guard let sd = strideDropPct, let cd = cadDropPct else { return nil }
        let sdAbs = abs(sd), cdAbs = abs(cd)
        if sdAbs < 0.5 && cdAbs < 0.5 { return nil }
        let L = AppLanguage.shared
        if interpretationType == .muscFatigue {
            return L.s(
                "후반에 보폭이 \(String(format: "%.1f", sdAbs))% 줄어 발걸음(\(String(format: "%.1f", cdAbs))%)보다 컸고요.",
                "In the later reps stride dropped \(String(format: "%.1f", sdAbs))% vs cadence (\(String(format: "%.1f", cdAbs))%)."
            )
        } else if interpretationType == .rhythmCollapse {
            return L.s(
                "후반에 발걸음이 \(String(format: "%.1f", cdAbs))% 줄어 보폭(\(String(format: "%.1f", sdAbs))%)보다 컸고요.",
                "In the later reps cadence dropped \(String(format: "%.1f", cdAbs))% vs stride (\(String(format: "%.1f", sdAbs))%)."
            )
        }
        return nil
    }

    // MARK: - Normalized Chart Badge

    // Chart-based badge: rep-1 vs last-rep delta (same basis as the normalized chart).
    private var normBadgeFromChart: NormBadgeKind {
        guard !normalizedCadencePoints.isEmpty || !normalizedStridePoints.isEmpty else { return .stable }
        let cadD = (normalizedCadencePoints.last?.value ?? 100) - 100  // negative = dropped
        let strD = (normalizedStridePoints.last?.value  ?? 100) - 100

        // Opposite directions (one +2%+, other -2%-)
        if (strD >= 2 && cadD <= -2) || (cadD >= 2 && strD <= -2) { return .styleChange }
        // Stride-led: stride fell ≥2% AND stride drop exceeds cadence drop by ≥2%p
        if strD <= -2 && (cadD - strD) >= 2  { return .muscFatigue }
        // Cadence-led: cadence fell ≥2% AND cadence drop exceeds stride drop by ≥2%p
        if cadD <= -2 && (strD - cadD) >= 2  { return .rhythmCollapse }
        // Both dropped comparably
        if strD <= -2 && cadD <= -2           { return .bothDecline }
        return .stable
    }

    // Final badge — for ①③ interpretation types, interpretation (early/late avg) is authoritative.
    private var normBadgeKind: NormBadgeKind {
        switch interpretationType {
        case .muscFatigue:    return .muscFatigue
        case .rhythmCollapse: return .rhythmCollapse
        default:              return normBadgeFromChart
        }
    }

    private var normBadgeTitle: String {
        let L = AppLanguage.shared
        switch normBadgeKind {
        case .muscFatigue:    return L.s("근피로 가능성",   "Leg Fatigue?")
        case .rhythmCollapse: return L.s("리듬 붕괴 가능성", "Rhythm Breakdown?")
        case .bothDecline:    return L.s("전신 피로 가능성", "Overall Fatigue?")
        case .styleChange:    return L.s("주법 변화",       "Style Shift")
        case .stable:         return L.s("폼 안정",         "Form Stable")
        }
    }

    private var normBadgeDesc: String {
        let L = AppLanguage.shared
        switch normBadgeKind {
        case .muscFatigue:    return L.s("보폭이 더 크게 떨어졌어요",          "Stride dropped more than cadence")
        case .rhythmCollapse: return L.s("발걸음이 더 크게 떨어졌어요",         "Cadence dropped more than stride")
        case .bothDecline:    return L.s("둘 다 나란히 떨어졌어요",             "Both declined together")
        case .styleChange:    return L.s("같은 속도를 다른 방식으로 만들었어요", "Same speed, different mechanics")
        case .stable:         return L.s("둘 다 유지됐어요",                   "Both held steady")
        }
    }

    private var normBadgeBaseColor: Color {
        switch normBadgeKind {
        case .muscFatigue:    return Color(hex: "FFA94D")  // stride line color
        case .rhythmCollapse: return Theme.cadence  // 케이던스 선과 같은 색
        case .stable:         return Theme.positive  // green
        case .bothDecline, .styleChange: return .white
        }
    }

    private var normBadgeFgOpacity: Double {
        switch normBadgeKind {
        case .bothDecline, .styleChange: return 0.62
        default: return 1.0
        }
    }

    // MARK: - 관찰 (Observation)
    // Always shows actual measured values — pace first, then the most changed secondary metric.
    // No evaluative language ("안정적", "완벽한"). That belongs in interpretation.

    private func fmtPace(_ sec: Double) -> String {
        let s = Int(sec.rounded())
        return String(format: "%d'%02d\"", s / 60, s % 60)
    }

    private var observation: String {
        let L = AppLanguage.shared
        var parts: [String] = []
        let paceGotBetter = (paceDiffPct ?? 0) < 0
        let isPositive = interpretationType == .normal || interpretationType == .lateBoost || interpretationType == .negativeSplit
        let isFatigue  = interpretationType == .muscFatigue || interpretationType == .rhythmCollapse

        // Pace (always first when available)
        if let ep = earlyPace, let lp = latePace {
            let delta = Int((lp - ep).rounded())
            let epStr = fmtPace(ep), lpStr = fmtPace(lp)
            let dir: String
            if delta > 2 {
                dir = L.s("\(abs(delta))초 느려졌어요.", "slowed by \(abs(delta))s.")
            } else if delta < -2 {
                dir = L.s("\(abs(delta))초 빨라졌어요.", "sped up by \(abs(delta))s.")
            } else {
                dir = L.s("그대로였어요.", "stayed the same.")
            }
            parts.append(L.s("페이스가 \(epStr) → \(lpStr)로 \(dir)",
                              "Pace: \(epStr) → \(lpStr), \(dir)"))
        }

        // Secondary metric:
        // ①③ → stride vs cadence % comparison (reveals the cause).
        // ⑤⑥ → positive-direction metrics first, HR deprioritized.
        // ②한계 → highest % change (problem metric) as before.
        if isFatigue, let comp = strideVsCadenceComparison {
            parts.append(comp)
        } else {
            struct MC { let pct: Double; let isPositiveChange: Bool; let isHR: Bool; let text: String }
            var cands: [MC] = []

            if let ec = earlyCad, let lc = lateCad, ec > 0 {
                let pct = (lc - ec) / ec * 100
                let ecI = Int(ec.rounded()), lcI = Int(lc.rounded())
                let cadBetter = lc > ec
                let conn = parts.isEmpty ? "케이던스가" : (paceGotBetter == cadBetter ? "케이던스도" : "케이던스는")
                let dir  = pct > 0.5 ? "올랐고요." : pct < -0.5 ? "내렸고요." : "그대로였고요."
                cands.append(.init(pct: abs(pct), isPositiveChange: cadBetter, isHR: false,
                                   text: L.s("\(conn) \(ecI) → \(lcI) spm으로 \(dir)",
                                             "Cadence: \(ecI) → \(lcI) spm, \(dir)")))
            }

            if let es = earlyStride, let ls = lateStride, es > 0 {
                let pct = (ls - es) / es * 100
                let esS = String(format: "%.2f", es), lsS = String(format: "%.2f", ls)
                let strBetter = ls >= es * 0.995   // maintained (≤0.5% drop) counts as positive
                let conn = parts.isEmpty ? "보폭이" : (paceGotBetter == (ls > es) ? "보폭도" : "보폭은")
                let dir  = pct < -0.5 ? "줄었고요." : pct > 0.5 ? "늘었고요." : "그대로였고요."
                cands.append(.init(pct: abs(pct), isPositiveChange: strBetter, isHR: false,
                                   text: L.s("\(conn) \(esS) → \(lsS) m로 \(dir)",
                                             "Stride: \(esS) → \(lsS) m, \(dir)")))
            }

            if let eh = earlyHR, let lh = lateHR, eh > 0 {
                let d   = lh - eh
                let ehI = Int(eh.rounded()), lhI = Int(lh.rounded())
                let hrBetter = lh < eh
                let conn = parts.isEmpty ? "심박이" : (paceGotBetter == hrBetter ? "심박도" : "심박은")
                let dir: String
                if d > 1.5       { dir = "\(Int(d.rounded())) bpm 올랐고요." }
                else if d < -1.5 { dir = "\(Int(abs(d).rounded())) bpm 내렸고요." }
                else              { dir = "그대로였고요." }
                cands.append(.init(pct: abs(d / eh * 100), isPositiveChange: hrBetter, isHR: true,
                                   text: L.s("\(conn) \(ehI) → \(lhI) bpm으로 \(dir)",
                                             "HR: \(ehI) → \(lhI) bpm, \(dir)")))
            }

            // Positive interpretations: prefer improving metrics, deprioritize HR rising.
            // Abnormal interpretations: highest % change (problem) wins.
            let sorted = isPositive
                ? cands.sorted { a, b in
                    if a.isPositiveChange != b.isPositiveChange { return a.isPositiveChange }
                    if a.isHR != b.isHR { return !a.isHR }   // non-HR before HR on good runs
                    return a.pct > b.pct
                  }
                : cands.sorted { $0.pct > $1.pct }

            if let top = sorted.first {
                parts.append(top.text)
            }
        }

        return parts.isEmpty
            ? L.s("구간 데이터가 충분하지 않아요.", "Not enough rep data.")
            : parts.joined(separator: " ")
    }

    // MARK: - 해석 (Interpretation)
    // Primary cause (one of ①②③⑤⑥) + additive ④ when applicable.
    // Tone: 단정하되 가능성으로 연다 ("~일 수 있어요", "~줬을 거예요").

    private var interpretation: String {
        let L = AppLanguage.shared
        var parts: [String] = []

        switch interpretationType {
        case .normal:
            if let ec = earlyCad, let lc = lateCad, lc > ec {
                return L.s(
                    "페이스를 지키면서 발걸음이 오히려 올랐어요. 후반까지 리듬이 살아 있었다는 뜻이에요.",
                    "Pace held while cadence actually climbed — rhythm stayed strong to the end."
                )
            } else if let es = earlyStride, let ls = lateStride, ls >= es * 0.995 {
                return L.s(
                    "보폭이 끝까지 유지됐어요. 다리 힘이 남아 있었어요.",
                    "Stride held all the way through — leg power was there."
                )
            } else {
                return L.s(
                    "페이스를 끝까지 고르게 유지했어요.",
                    "Pace held steady throughout."
                )
            }
        case .lateBoost:
            if let ec = earlyCad, let lc = lateCad, lc > ec {
                return L.s(
                    "발걸음이 올라가면서 속도가 붙었어요. 여유가 남아 있었다는 뜻이에요.",
                    "Cadence climbed and pace followed — more in the tank."
                )
            } else {
                return L.s(
                    "후반으로 갈수록 페이스가 살아났어요. 여유가 있었다는 뜻이에요.",
                    "Pace picked up in the second half — you had more to give."
                )
            }
        case .negativeSplit:
            // ⑥ pace improved + HR rose — normal physiological response
            if let eh = earlyHR, let lh = lateHR {
                let d = Int((lh - eh).rounded())
                parts.append(L.s(
                    "후반으로 갈수록 리듬이 살아났어요. 심박이 \(d) bpm 오른 건 더 빠르게 뛴 만큼의 자연스러운 반응이에요.",
                    "Rhythm picked up in the second half. HR rising \(d) bpm is a natural response to running faster."))
            } else {
                parts.append(L.s("후반으로 갈수록 리듬이 살아났어요.",
                                  "Rhythm picked up in the second half."))
            }
        case .muscFatigue:
            // ① 근피로: stride-driven drop, HR stable
            parts.append(L.s("심폐는 여유가 있었는데 다리 힘이 먼저 빠졌을 수 있어요.",
                              "Cardio had capacity, but leg strength may have given out first."))
        case .cardioStress:
            // ② 심폐 부담: pace maintained + HR rose ≥8 bpm
            if let eh = earlyHR, let lh = lateHR {
                let d = Int((lh - eh).rounded())
                parts.append(L.s("심박이 \(d) bpm 오른 건 심폐 부담이 쌓이고 있다는 신호예요.",
                                  "HR rising \(d) bpm is a signal that cardio load is accumulating."))
            } else {
                parts.append(L.s("심폐 부담이 쌓이고 있다는 신호예요.",
                                  "A sign that cardio load is accumulating."))
            }
        case .cardioLimit:
            // 한계 구간: pace dropped + HR also rose
            if let eh = earlyHR, let lh = lateHR {
                let d = Int((lh - eh).rounded())
                parts.append(L.s("심박이 \(d) bpm 올라간 건 한계에 다가가고 있다는 신호예요.",
                                  "HR rising \(d) bpm signals you were approaching your limit."))
            } else {
                parts.append(L.s("후반엔 한계에 가까운 구간이었어요.",
                                  "The later reps pushed close to your limit."))
            }
        case .rhythmCollapse:
            // ③ 리듬 붕괴: cadence-dominant drop, HR stable
            parts.append(L.s("후반으로 갈수록 발걸음 리듬이 흐트러졌어요.",
                              "Stride rhythm broke down in the later reps."))
        }

        // ④ 초반 오버페이스 — appended to ①②③/한계 when pace dropped ≥1% and first rep too fast
        if hasOverpace {
            parts.append(L.s("1회차가 평균보다 \(overpaceDeltaSec)초 빨랐던 것도 영향을 줬을 거예요.",
                              "Starting rep 1 \(overpaceDeltaSec)s faster than average likely played a role."))
        }

        return parts.joined(separator: " ")
    }

    // MARK: - 제안 (Suggestion)
    // Only when there is a clear improvement path. Max 2 lines.

    private var suggestion: String? {
        let L = AppLanguage.shared
        var lines: [String] = []

        switch interpretationType {
        case .normal, .lateBoost, .negativeSplit:
            // 잘한 러닝에 지적 금지. history 없이는 늘리는 제안도 금지.
            return nil
        case .muscFatigue:
            // 훈련 조정 + 보강운동
            if let avgPace = allWorkAvgPace {
                let s = Int(avgPace.rounded())
                let avgStr = String(format: "%d'%02d\"", s / 60, s % 60)
                lines.append(L.s("다음엔 1회차를 \(avgStr)로 시작해 보세요.",
                                   "Next session, start rep 1 at \(avgStr)."))
            }
            lines.append(L.s("종아리·둔근 보강을 주 2회 곁들이면 후반 보폭 유지에 도움이 돼요.",
                               "Calf raises and hip hinges 2×/week help maintain stride in later reps."))
        case .cardioStress:
            // 회복 시간 or 구간 수 조정
            lines.append(L.s("회복을 30초 늘리거나 구간을 1개 줄여보세요.",
                               "Try adding 30s to recovery, or drop one rep."))
        case .cardioLimit:
            // 전체 강도 조정
            lines.append(L.s("강도를 조금 낮추거나 회복을 30초 늘려보세요.",
                               "Try lowering the overall effort, or add 30s to recovery."))
        case .rhythmCollapse:
            // 구간 단축 + 드릴
            lines.append(L.s("구간 길이를 조금 줄여 리듬을 유지해 보세요.",
                               "Try shortening each rep to keep your rhythm intact."))
            lines.append(L.s("짧은 스트라이드·스킵 드릴이 리듬 유지에 도움이 돼요.",
                               "Short stride and skip drills help maintain rhythm."))
        }

        let combined = lines.prefix(2).joined(separator: "\n")
        return combined.isEmpty ? nil : combined
    }

    // MARK: - Recovery Segment Notes (per-segment)

    // One note per recovery segment — combines HR drop and pace issues causally.
    // Maximum 3 notes total (later segments dropped silently).
    private var segmentRecoveryNotes: [String] {
        guard !recSegs.isEmpty else { return [] }
        let L = AppLanguage.shared
        var notes: [String] = []
        for (i, rec) in recSegs.enumerated() {
            let recNum = i + 1
            let drop = recoveryHRDrop(for: rec)
            let isShort    = rec.duration < 90
            let isPoorDrop = drop.map { $0 < 8 } ?? false
            let isVeryPoor = drop.map { $0 < 3 } ?? false
            let durSec = Int(rec.duration.rounded())

            let preceding = workSegs.filter { $0.endDate <= rec.startDate }.last
            let hasPaceProblem: Bool = {
                guard let wPace = preceding?.paceSecPerKm,
                      let rPace = rec.paceSecPerKm else { return false }
                return rPace <= wPace * 1.10
            }()

            // Priority: combined cause first, then single-issue notes
            let note: String?
            if isShort && hasPaceProblem && isPoorDrop {
                note = L.s(
                    "회복\(recNum): \(durSec)초로 짧았고 페이스도 운동 구간과 비슷해 심박이 내려가지 않았어요",
                    "Rec \(recNum): only \(durSec)s and pace close to work — HR didn't recover"
                )
            } else if isShort && isPoorDrop {
                note = L.s(
                    "회복\(recNum): 회복 시간이 짧고 심박도 충분히 내려가지 않았어요",
                    "Rec \(recNum): short recovery and HR didn't drop enough"
                )
            } else if hasPaceProblem && isPoorDrop {
                note = L.s(
                    "회복\(recNum): 회복 페이스가 운동 구간과 비슷해 심박이 충분히 내려가지 않았어요",
                    "Rec \(recNum): recovery pace close to work — HR didn't drop enough"
                )
            } else if isVeryPoor {
                note = L.s(
                    "회복\(recNum): 심박 회복이 거의 안 됐어요",
                    "Rec \(recNum): HR barely recovered"
                )
            } else if isPoorDrop {
                note = L.s(
                    "회복\(recNum): 심박이 조금밖에 안 내려갔어요",
                    "Rec \(recNum): HR dropped only a little"
                )
            } else if hasPaceProblem {
                note = L.s(
                    "회복\(recNum): 회복 페이스가 운동 구간과 비슷했어요",
                    "Rec \(recNum): recovery pace was close to work pace"
                )
            } else {
                note = nil
            }

            if let n = note { notes.append(n) }
        }
        return Array(notes.prefix(3))
    }

    // MARK: - Temporary Dip Detection

    private var tempDropNote: String? {
        let indexed = workSegs.enumerated().compactMap { i, s in
            s.avgCadence.map { (display: i + 1, cad: Double($0)) }
        }
        guard indexed.count >= 3 else { return nil }
        let L = AppLanguage.shared
        for i in 1..<(indexed.count - 1) {
            let prev = indexed[i - 1].cad, curr = indexed[i].cad, next = indexed[i + 1].cad
            guard prev > 0, (prev - curr) / prev * 100 > 3, next > curr else { continue }
            return L.s("\(indexed[i].display)구간에서 일시적 리듬 저하, 스스로 회복했어요",
                        "Segment \(indexed[i].display) had a brief dip — bounced back")
        }
        return nil
    }

    // MARK: - Per-Segment Emoji (pace-based; cadence fallback)

    private func segEmoji(index: Int) -> String {
        let seg = workSegs[index]
        if outlierIDs.contains(seg.id) { return "⚠️" }
        if let ref = earlyPace, ref > 0, let pace = seg.paceSecPerKm {
            let diff = (pace - ref) / ref * 100
            if diff >  5 { return "🔴" }
            if diff >  2 { return "🟡" }
            if diff < -2 { return "🔵" }
            return "🟢"
        }
        if let fc = workSegs.compactMap(\.avgCadence).first.map(Double.init), let cad = seg.avgCadence {
            let drop = (fc - Double(cad)) / fc * 100
            if drop > 3 { return "🔴" }
            if drop > 1 { return "🟡" }
            if drop < -1 { return "🔵" }
            return "🟢"
        }
        return "–"
    }

    // MARK: - Chart Points

    private var pacePoints: [ChartPoint] {
        workSegs.enumerated().compactMap { i, s in s.paceSecPerKm.map { .init(id: i + 1, value: $0) } }
    }
    private var cadencePoints: [ChartPoint] {
        workSegs.enumerated().compactMap { i, s in s.avgCadence.map { .init(id: i + 1, value: Double($0)) } }
    }
    private var hrPoints: [ChartPoint] {
        workSegs.enumerated().compactMap { i, s in s.avgHeartRate.map { .init(id: i + 1, value: Double($0)) } }
    }

    // Normalized to rep-1 = 100%. Reps with nil/0 cadence are skipped (stride = speed/cadence is undefined).
    private var normalizedCadencePoints: [ChartPoint] {
        guard let base = workSegs.first?.avgCadence.map(Double.init), base > 0 else { return [] }
        return workSegs.enumerated().compactMap { i, s in
            guard let c = s.avgCadence.map(Double.init), c > 0 else { return nil }
            return .init(id: i + 1, value: c / base * 100)
        }
    }
    private var normalizedStridePoints: [ChartPoint] {
        guard let base = workSegs.first?.computedStride, base > 0 else { return [] }
        return workSegs.enumerated().compactMap { i, s in
            guard s.avgCadence != nil, let str = s.computedStride else { return nil }
            return .init(id: i + 1, value: str / base * 100)
        }
    }

    // MARK: - Body

    var body: some View {
        if workSegs.count < 3 {
            HStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.28))
                Text(AppLanguage.shared.s("구간이 부족해요 (최소 3개 필요)", "Not enough intervals (need 3+)"))
                    .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.38))
            }
            .padding(.vertical, 14)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                chartSection

                if let note = tempDropNote { noteRow(note) }
                if !outlierIDs.isEmpty {
                    let ids = outlierIDs.sorted().map { "\($0)" }.joined(separator: ", ")
                    noteRow(AppLanguage.shared.s("\(ids)구간은 이상치로 판정에서 제외됐어요",
                                                 "Segment(s) \(ids) excluded as outliers"))
                }

                internalDivider
                segmentTable
                internalDivider

                ForEach(segmentRecoveryNotes, id: \.self) { noteRow($0) }

                if halfCount >= 1 {
                    analysisCard
                }
            }
            .onAppear {
                #if DEBUG
                logCharts()
                #endif
            }
        }
    }

    #if DEBUG
    private func logCharts() {
        var parts: [String] = []
        if let fp = pacePoints.first?.value, let lp = pacePoints.last?.value {
            let d = lp - fp
            parts.append("페이스 \(String(format: "%.1f", fp))→\(String(format: "%.1f", lp))(\(d >= 0 ? "+" : "−")\(String(format: "%.1f", abs(d)))s)")
        }
        var normParts: [String] = []
        if let lc = normalizedCadencePoints.last?.value {
            let d = lc - 100
            normParts.append("케이던스 100→\(String(format: "%.1f", lc))(\(d >= 0 ? "+" : "−")\(String(format: "%.1f", abs(d)))%)")
        }
        if let ls = normalizedStridePoints.last?.value {
            let d = ls - 100
            normParts.append("보폭 100→\(String(format: "%.1f", ls))(\(d >= 0 ? "+" : "−")\(String(format: "%.1f", abs(d)))%)")
        }
        if !normParts.isEmpty { parts.append(normParts.joined(separator: " ")) }
        if let eh = earlyHR, let lh = lateHR {
            let d = lh - eh
            parts.append("심박 \(String(format: "%.1f", eh))→\(String(format: "%.1f", lh))(\(d >= 0 ? "+" : "−")\(String(format: "%.1f", abs(d))))")
        }
        let dominant: String
        switch interpretationType {
        case .muscFatigue:                dominant = "보폭"
        case .rhythmCollapse:             dominant = "케이던스"
        case .cardioStress, .cardioLimit: dominant = "심박"
        default:                          dominant = "없음"
        }
        print("[인터벌:차트] \(parts.joined(separator: " | ")) 주도지표=\(dominant)")

        // Badge log
        let cadD = (normalizedCadencePoints.last?.value ?? 100) - 100
        let strD = (normalizedStridePoints.last?.value  ?? 100) - 100
        let diffPP = cadD - strD  // cadence delta minus stride delta (%p)
        let chartBadgeName: String
        switch normBadgeFromChart {
        case .muscFatigue:    chartBadgeName = "근피로가능성"
        case .rhythmCollapse: chartBadgeName = "리듬붕괴가능성"
        case .bothDecline:    chartBadgeName = "전신피로가능성"
        case .styleChange:    chartBadgeName = "주법변화"
        case .stable:         chartBadgeName = "폼안정"
        }
        let finalBadgeName: String
        switch normBadgeKind {
        case .muscFatigue:    finalBadgeName = "근피로가능성"
        case .rhythmCollapse: finalBadgeName = "리듬붕괴가능성"
        case .bothDecline:    finalBadgeName = "전신피로가능성"
        case .styleChange:    finalBadgeName = "주법변화"
        case .stable:         finalBadgeName = "폼안정"
        }
        let align = (chartBadgeName == finalBadgeName) ? "일치" : "불일치(해석판정우선)"
        print("[인터벌:배지] 케이던스\(String(format: "%+.1f", cadD))% 보폭\(String(format: "%+.1f", strD))% 차이\(String(format: "%+.1f", diffPP))%p | 차트→\(chartBadgeName) 최종→\(finalBadgeName) \(align)")
    }
    #endif

    // MARK: - 3-Part Analysis Card (관찰·해석·제안)

    private var boxBgColor: Color {
        switch interpretationType {
        case .muscFatigue, .rhythmCollapse: return Color(hex: "FC9A56").opacity(0.16)
        case .cardioStress, .cardioLimit:   return Color(hex: "5C7CFA").opacity(0.16)
        case .normal:                        return Color(hex: "7C5CFC").opacity(0.20)
        case .lateBoost, .negativeSplit:     return Color(hex: "5CE5D5").opacity(0.16)
        }
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 관찰 — 초반→후반 실측값 (평가 어휘 없음)
            Text(observation)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.90))
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 8)

            // 해석 — 왜 그랬을까 (가능성 어조)
            Text(interpretation)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            // 제안 — 개선 여지가 있을 때만
            if let sug = suggestion {
                Spacer().frame(height: 10)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "FFD166"))
                        .frame(width: 16)
                        .padding(.top, 1)
                    Text(sug)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(hex: "FFD166"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(boxBgColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Chart Section
    // Reading order: pace (무슨 일) → cadence·stride normalized (왜) → HR (비용)

    @ViewBuilder
    private var chartSection: some View {
        let L = AppLanguage.shared
        let hasPace = !pacePoints.isEmpty
        let hasNorm = normalizedCadencePoints.count >= 2 || normalizedStridePoints.count >= 2
        let hasHR   = !hrPoints.isEmpty

        VStack(spacing: 10) {
            if hasPace { paceChartRow }
            if hasNorm {
                if hasPace { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5) }
                normalizedChartRow
            }
            if hasHR {
                if hasPace || hasNorm { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5) }
                lineChartRow(label: L.s("심박", "HR"),
                             points: hrPoints, color: Color(hex: "F87171"), isGoodUp: false,
                             earlyAvg: earlyHR, lateAvg: lateHR)
            }
        }
    }

    // MARK: - Pace Chart (y-axis inverted: faster = higher)

    private var paceChartRow: some View {
        let L = AppLanguage.shared
        let n = workSegs.count
        let mid = Double(n) / 2.0 + 0.5
        let showOdd = n > 8
        let xVals: [Double] = showOdd
            ? Array(stride(from: 1.0, through: Double(n), by: 2.0))
            : (1...max(1, n)).map(Double.init)
        // Negate values: smaller pace sec/km (faster) → less negative → higher y position
        let negVals = pacePoints.map { -$0.value }
        let span = max((negVals.max() ?? 1) - (negVals.min() ?? 0), 1.0)
        let yLo = (negVals.min() ?? 0) - span * 0.18
        let yHi = (negVals.max() ?? 1) + span * 0.18

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.s("페이스", "Pace"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.50))
                Spacer()
                if let ep = earlyPace, let lp = latePace {
                    let delta = Int((lp - ep).rounded())
                    let sign = delta > 0 ? "+" : delta < 0 ? "−" : "±"
                    let badge = "\(fmtPace(ep)) → \(fmtPace(lp)) (\(sign)\(abs(delta))초)"
                    Text(badge)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(delta < 0 ? Theme.positive : Color.white.opacity(0.70))
                }
            }
            Chart {
                RuleMark(x: .value("mid", mid))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                    .foregroundStyle(Color.white.opacity(0.15))
                ForEach(pacePoints) { pt in
                    LineMark(x: .value("", Double(pt.id)), y: .value("", -pt.value))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    PointMark(x: .value("", Double(pt.id)), y: .value("", -pt.value))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .symbolSize(22)
                }
            }
            .chartYScale(domain: yLo...yHi)
            .chartXScale(domain: 0.5...(Double(n) + 0.5))
            .chartXAxis {
                AxisMarks(values: xVals) { val in
                    AxisValueLabel(centered: false) {
                        if let v = val.as(Double.self) {
                            Text("\(Int(v))").font(.system(size: 8)).foregroundStyle(Color.white.opacity(0.30))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 2)) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                        .foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel {
                        if let v = val.as(Double.self), v < 0 {
                            let sec = Int((-v).rounded())
                            Text(String(format: "%d'%02d\"", sec / 60, sec % 60))
                                .font(.system(size: 7))
                                .foregroundStyle(Color.white.opacity(0.30))
                        }
                    }
                }
            }
            .frame(height: 56)
        }
    }

    // MARK: - Normalized Cadence · Stride Chart (rep 1 = 100%)

    private var normalizedChartRow: some View {
        let L = AppLanguage.shared
        let cadPts = normalizedCadencePoints
        let strPts = normalizedStridePoints
        let n = workSegs.count
        let mid = Double(n) / 2.0 + 0.5
        let showOdd = n > 8
        let xVals: [Double] = showOdd
            ? Array(stride(from: 1.0, through: Double(n), by: 2.0))
            : (1...max(1, n)).map(Double.init)

        let allVals = (cadPts + strPts).map(\.value)
        let span = max((allVals.max() ?? 100) - (allVals.min() ?? 100), 1.0)
        let yLo = (allVals.min() ?? 99) - max(span * 0.25, 1.0)
        let yHi = (allVals.max() ?? 101) + max(span * 0.25, 1.0)

        let cadColor = Theme.cadence
        let strColor = Color(hex: "FFA94D")
        // Dominant metric emphasized; other dimmed — mirrors interpretationType
        let cadOpacity: Double = interpretationType == .rhythmCollapse ? 1.0
                               : interpretationType == .muscFatigue    ? 0.35 : 1.0
        let strOpacity: Double = interpretationType == .muscFatigue    ? 1.0
                               : interpretationType == .rhythmCollapse ? 0.35 : 1.0

        let cadFinal = cadPts.last?.value ?? 100
        let strFinal = strPts.last?.value ?? 100
        let cadDelta = cadFinal - 100
        let strDelta = strFinal - 100
        let cadLbl = (cadDelta >= 0 ? "+" : "−") + String(format: "%.1f", abs(cadDelta)) + "%"
        let strLbl = (strDelta >= 0 ? "+" : "−") + String(format: "%.1f", abs(strDelta)) + "%"
        let badge = L.s("1회차 대비  케이던스 \(cadLbl)  보폭 \(strLbl)", "vs rep1  Cad \(cadLbl)  Stride \(strLbl)")

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Circle().fill(cadColor).frame(width: 5, height: 5)
                    Circle().fill(strColor).frame(width: 5, height: 5)
                    Text(L.s("케이던스 · 보폭 (1회차=100%)", "Cad · Stride (rep1=100%)"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.50))
                }
                Spacer()
                Text(badge)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.60))
            }
            Chart {
                RuleMark(y: .value("", 100))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                    .foregroundStyle(Color.white.opacity(0.18))
                RuleMark(x: .value("mid", mid))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                    .foregroundStyle(Color.white.opacity(0.10))
                ForEach(cadPts) { pt in
                    LineMark(x: .value("", Double(pt.id)), y: .value("", pt.value),
                             series: .value("", "cad"))
                        .foregroundStyle(cadColor.opacity(cadOpacity))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    PointMark(x: .value("", Double(pt.id)), y: .value("", pt.value))
                        .foregroundStyle(cadColor.opacity(cadOpacity * 0.55))
                        .symbolSize(22)
                }
                ForEach(strPts) { pt in
                    LineMark(x: .value("", Double(pt.id)), y: .value("", pt.value),
                             series: .value("", "str"))
                        .foregroundStyle(strColor.opacity(strOpacity))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    PointMark(x: .value("", Double(pt.id)), y: .value("", pt.value))
                        .foregroundStyle(strColor.opacity(strOpacity * 0.55))
                        .symbolSize(22)
                }
            }
            .chartYScale(domain: yLo...yHi)
            .chartXScale(domain: 0.5...(Double(n) + 0.5))
            .chartXAxis {
                AxisMarks(values: xVals) { val in
                    AxisValueLabel(centered: false) {
                        if let v = val.as(Double.self) {
                            Text("\(Int(v))").font(.system(size: 8)).foregroundStyle(Color.white.opacity(0.30))
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 52)
            HStack(spacing: 6) {
                Text(normBadgeTitle)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(normBadgeBaseColor.opacity(normBadgeFgOpacity))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(normBadgeBaseColor.opacity(0.15))
                    .clipShape(Capsule())
                Text(normBadgeDesc)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.50))
            }
        }
    }

    private func lineChartRow(
        label: String, points: [ChartPoint], color: Color, isGoodUp: Bool,
        earlyAvg: Double? = nil, lateAvg: Double? = nil
    ) -> some View {
        let n = workSegs.count
        let mid = Double(n) / 2.0 + 0.5
        let showOdd = n > 8
        let xVals: [Double] = showOdd
            ? Array(stride(from: 1.0, through: Double(n), by: 2.0))
            : (1...max(1, n)).map(Double.init)
        let vals = points.map(\.value)
        let span = max((vals.max() ?? 1) - (vals.min() ?? 0), 1.0)
        let yLo = (vals.min() ?? 0) - span * 0.18
        let yHi = (vals.max() ?? 1) + span * 0.18

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.50))
                Spacer()
                badgeView(ea: earlyAvg, la: lateAvg,
                          fallbackFirst: points.first?.value, fallbackLast: points.last?.value,
                          isGoodUp: isGoodUp)
            }
            Chart {
                RuleMark(x: .value("mid", mid))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                    .foregroundStyle(Color.white.opacity(0.15))
                ForEach(points) { pt in
                    LineMark(x: .value("", Double(pt.id)), y: .value("", pt.value))
                        .foregroundStyle(color).interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    PointMark(x: .value("", Double(pt.id)), y: .value("", pt.value))
                        .foregroundStyle(color.opacity(0.55)).symbolSize(22)
                }
            }
            .chartYScale(domain: yLo...yHi)
            .chartXScale(domain: 0.5...(Double(n) + 0.5))
            .chartXAxis {
                AxisMarks(values: xVals) { val in
                    AxisValueLabel(centered: false) {
                        if let v = val.as(Double.self) {
                            Text("\(Int(v))").font(.system(size: 8)).foregroundStyle(Color.white.opacity(0.30))
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 52)
        }
    }

    private func badgeView(ea: Double?, la: Double?,
                           fallbackFirst: Double?, fallbackLast: Double?, isGoodUp: Bool) -> some View {
        let (from, to): (Double?, Double?) = (ea != nil && la != nil) ? (ea, la) : (fallbackFirst, fallbackLast)
        return Group {
            if let f = from, let l = to {
                let fr = Int(f.rounded()), lr = Int(l.rounded())
                let dr = lr - fr               // diff after rounding — avoids "156→156 (+1)" artifacts
                let sign = dr > 0 ? "+" : dr < 0 ? "−" : "±"
                let label = "\(fr) → \(lr) (\(sign)\(abs(dr)))"
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle((isGoodUp ? dr >= 0 : dr <= 0) ? Theme.positive : Color.white.opacity(0.70))
            }
        }
    }

    // MARK: - Segment Table

    private var segmentTable: some View {
        let L = AppLanguage.shared
        let hasPace   = workSegs.contains { $0.paceSecPerKm  != nil }
        let hasCad    = workSegs.contains { $0.avgCadence     != nil }
        let hasStride = workSegs.contains { $0.computedStride != nil }
        let hasHR     = workSegs.contains { $0.avgHeartRate   != nil }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(L.s("구간", "Seg")).frame(width: 26, alignment: .leading)
                if hasPace   { Text(L.s("페이스", "Pace")).frame(maxWidth: .infinity, alignment: .leading) }
                if hasCad    { Text(L.s("케이던스", "Cad")).frame(maxWidth: .infinity, alignment: .leading) }
                if hasStride { Text(L.s("보폭", "Stride")).frame(maxWidth: .infinity, alignment: .leading) }
                if hasHR     { Text(L.s("심박", "HR")).frame(maxWidth: .infinity, alignment: .leading) }
                Text(L.s("상태(페이스)", "State(Pace)")).frame(width: 46, alignment: .center)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.38))
            .padding(.bottom, 5)

            ForEach(workSegs.indices, id: \.self) { idx in
                let seg = workSegs[idx]
                let isOutlier = outlierIDs.contains(seg.id)
                HStack(spacing: 0) {
                    Text("\(idx + 1)").frame(width: 26, alignment: .leading)
                    if hasPace   { Text(seg.formattedPace ?? "–").frame(maxWidth: .infinity, alignment: .leading) }
                    if hasCad    { Text(seg.avgCadence.map { "\($0)" } ?? "–").frame(maxWidth: .infinity, alignment: .leading) }
                    if hasStride { Text(seg.computedStride.map { String(format: "%.2f", $0) } ?? "–").frame(maxWidth: .infinity, alignment: .leading) }
                    if hasHR     { Text(seg.avgHeartRate.map { "\($0)" } ?? "–").frame(maxWidth: .infinity, alignment: .leading) }
                    Text(segEmoji(index: idx)).frame(width: 46, alignment: .center)
                }
                .font(.system(size: 10))
                .foregroundStyle(isOutlier ? Color.white.opacity(0.38) : Color.white.opacity(0.82))
                .padding(.vertical, 3)
            }
        }
    }

    // MARK: - Helpers

    private func noteRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.38)).padding(.top, 1)
            Text(text)
                .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var internalDivider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
    }
}
