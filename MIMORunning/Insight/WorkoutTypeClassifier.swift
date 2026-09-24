import Foundation

// MARK: - Classifier

struct WorkoutTypeClassifier {

    /// Classifies a running workout into one of eight types.
    /// Priority: race (existing confirmed) → plan (WorkoutKit) → easy (Zone2 HR / pace fallback)
    ///           → buildUp → distanceRun → LSD → longRun → tempo → general.
    /// 페이스·거리 기준은 개인 상대값이다. 절대 기준은 장거리 8km·템포 4km 하한뿐.
    ///
    /// 기준선(baseline)은 `baselinePace` / `baselineDistance` 참고 — 직전 4주 **중앙값**.
    /// `typeOf`: 과거 러닝의 캐시된 유형. 인터벌·대회를 페이스 기준선에서 빼는 데 쓴다. nil이면 제외 없음.
    /// `heat`: 페이스 더위 모델. 있으면 기준선의 과거 페이스와 오늘 페이스를 모두 15°C로 환산해 비교한다 —
    ///   폭염 첫 주에 평소 강도 러닝이 "기준보다 느림"에 걸려 LSD로, 가을 첫 선선한 날이 거리주로 잘못 잡히는 것을 막는다.
    ///   모델이 없거나 학습이 안 됐으면(ok=false) 원본 페이스 그대로.
    static func classify(
        activity: Activity,
        history: [Activity],
        splits: [SplitData],
        intervalSegments: [IntervalSegment] = [],
        hrZones: [HRZoneData]? = nil,
        existingType: WorkoutType? = nil,
        typeOf: ((UUID) -> WorkoutType?)? = nil,
        heat: MRHeatModel? = nil
    ) -> WorkoutType {
        guard activity.type == .running, activity.distance >= 1000 else { return .general }
        if existingType == .race { return .race }  // 대회 확정 — 재분류 없이 유지

        let recentRuns = history
            .filter { $0.type == .running
                      && $0.id != activity.id
                      && $0.date < activity.date }   // 미래 데이터 오염 방지 — 분류 결과 시점 고정
            .sorted { $0.date > $1.date }
        let base = Baseline(activity: activity, recentRuns: recentRuns, typeOf: typeOf, heat: heat)

        if isPlanInterval(intervalSegments: intervalSegments)              { return .interval    }
        if isEasy(activity: activity, base: base, hrZones: hrZones)        { return .easy        }
        if isBuildUp(splits: splits)                                       { return .buildUp     }
        if isDistanceRun(activity: activity, base: base)                   { return .distanceRun }
        if isLSD(activity: activity, base: base, splits: splits)           { return .lsd         }
        if isLongRun(activity: activity, base: base)                       { return .longRun     }
        if isTempo(activity: activity, base: base, splits: splits)         { return .tempo       }
        return .general
    }

    // MARK: - Baselines (본인 기준선)

    /// 분류에 쓰는 본인 기준선. 회수 창이 아니라 기간 창, 평균이 아니라 중앙값.
    struct Baseline {
        /// 페이스 기준선 (sec/km, 15°C 환산). nil = 표본 부족.
        let pace: Double?
        /// 오늘 페이스 (sec/km, 기준선과 같은 15°C 환산). 모든 페이스 비교는 원본 대신 이 값을 쓴다.
        let todayPace: Double?
        /// 거리 기준선 (m). nil = 직전 4주 3회 미만 → 12km 절대 폴백.
        let distance: Double?
        /// 로그용 — 페이스 기준선 표본 수와 창
        let paceSampleCount: Int
        let paceWindowLabel: String
        /// 더위 환산이 실제로 적용됐는가(모델 ok + 오늘 기온 있음) — 트레이스용
        let heatApplied: Bool

        init(activity: Activity, recentRuns: [Activity], typeOf: ((UUID) -> WorkoutType?)?, heat: MRHeatModel? = nil) {
            let p = WorkoutTypeClassifier.baselinePace(activity: activity, recentRuns: recentRuns, typeOf: typeOf, heat: heat)
            pace = p.value; paceSampleCount = p.count; paceWindowLabel = p.window
            todayPace = WorkoutTypeClassifier.refPace(activity, heat: heat)
            distance = WorkoutTypeClassifier.baselineDistance(activity: activity, recentRuns: recentRuns)
            heatApplied = (heat?.ok ?? false) && activity.temperatureC != nil
        }
    }

    /// 러닝의 페이스를 15°C 기준으로 환산(sec/km). 더위 모델이 없거나 학습이 안 됐거나 기온이 없으면 원본 그대로.
    /// `MRHeatModel.toRef`와 같은 계수 — 페이스는 시간에 비례하므로 같은 배율이 붙는다.
    static func refPace(_ run: Activity, heat: MRHeatModel?) -> Double? {
        guard let p = run.paceSecPerKm else { return nil }
        guard let h = heat, h.ok, let t = run.temperatureC else { return p }
        return p * exp(h.logDelta(t))
    }

    /// 페이스 기준선 — 직전 4주 중앙값(최소 5회). 부족하면 8주, 그래도 부족하면 최근 10회 중 3회 이상(콜드 스타트).
    /// 인터벌·대회·3km 미만은 제외 — 목적이 다른 러닝이 기준선을 흔들지 않게.
    /// `heat`가 있으면 각 러닝의 페이스를 15°C로 환산한 뒤 중앙값을 낸다(`refPace`).
    static func baselinePace(activity: Activity, recentRuns: [Activity],
                             typeOf: ((UUID) -> WorkoutType?)?,
                             heat: MRHeatModel? = nil) -> (value: Double?, count: Int, window: String) {
        let eligible = recentRuns.filter { run in
            guard run.distance >= 3000, run.paceSecPerKm != nil else { return false }
            if let t = typeOf?(run.id), t == .interval || t == .race { return false }
            return true
        }
        let cal = Calendar.current
        for weeks in [4, 8] {
            let cutoff = cal.date(byAdding: .weekOfYear, value: -weeks, to: activity.date) ?? .distantPast
            let paces = eligible.filter { $0.date >= cutoff }.compactMap { refPace($0, heat: heat) }
            if paces.count >= 5 { return (median(paces), paces.count, "\(weeks)주") }
        }
        let paces = eligible.prefix(10).compactMap { refPace($0, heat: heat) }
        guard paces.count >= 3 else { return (nil, paces.count, "최근10회") }
        return (median(paces), paces.count, "최근10회")
    }

    /// 거리 기준선 — 직전 4주 러닝 거리 중앙값 (3회 이상). 롱런 몇 번이 평균을 끌어올리는 문제를 피한다.
    static func baselineDistance(activity: Activity, recentRuns: [Activity]) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: activity.date) ?? .distantPast
        let recent = recentRuns.filter { $0.date >= cutoff && $0.date < activity.date }.map(\.distance)
        guard recent.count >= 3 else { return nil }
        return median(recent)
    }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        let n = s.count
        guard n > 0 else { return 0 }
        return n % 2 == 0 ? (s[n / 2 - 1] + s[n / 2]) / 2 : s[n / 2]
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

    /// Progressive buildup: first-to-last improvement ≥5%, AND either
    ///   (a) each of three pace-thirds is strictly faster than the previous, OR
    ///   (b) linear regression slope < 0 with R² ≥ 0.40 (catches noisy but real build-ups).
    private static func isBuildUp(splits: [SplitData]) -> Bool {
        let full = splits.filter { $0.distanceM >= 900 }
        guard full.count >= 4 else { return false }
        let paces = full.map(\.paceSecPerKm)
        guard let firstPace = paces.first, let lastPace = paces.last else { return false }
        guard lastPace < firstPace * 0.95 else { return false }  // ≥5% first-to-last gain

        // (a) 3등분 단조 상승: 각 구간 평균 페이스가 순차 감소 (= 점점 빨라짐)
        let n = paces.count; let t = max(1, n / 3)
        let avgOf: (ArraySlice<Double>) -> Double = { s in s.reduce(0, +) / Double(s.count) }
        let a1 = avgOf(paces[0..<t])
        let a2 = avgOf(paces[t..<(2 * t)])
        let a3 = avgOf(paces[(2 * t)...])
        if a1 > a2 && a2 > a3 { return true }

        // (b) 선형 회귀 기울기 < 0이고 R² ≥ 0.40 (전반적 하향 추세)
        let xMean = Double(n - 1) / 2.0
        let yMean = paces.reduce(0, +) / Double(n)
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (i, y) in paces.enumerated() {
            let dx = Double(i) - xMean; let dy = y - yMean
            sxy += dx * dy; sxx += dx * dx; syy += dy * dy
        }
        guard sxx > 0, syy > 0 else { return false }
        return sxy / sxx < 0 && (sxy * sxy) / (sxx * syy) >= 0.40
    }

    /// Long distance + pace near/faster than personal baseline (race-intent effort).
    /// Pace must be < baseline × 1.10 so it's distinctly faster than easy/LSD.
    private static func isDistanceRun(activity: Activity, base: Baseline) -> Bool {
        guard isLongRun(activity: activity, base: base) else { return false }
        guard let pace = base.todayPace, let med = base.pace else { return false }
        return pace < med * 1.10
    }

    /// Long distance + very slow pace (≥20% slower than baseline) + very even effort (CV ≤ 8%).
    private static func isLSD(activity: Activity, base: Baseline, splits: [SplitData]) -> Bool {
        guard isLongRun(activity: activity, base: base) else { return false }
        guard let pace = base.todayPace, let med = base.pace else { return false }
        guard pace > med * 1.20 else { return false }
        let full = splits.filter { $0.distanceM >= 900 }
        guard full.count >= 3 else { return false }  // 스플릿 부족 → 일반 러닝으로 폴백
        let paces = full.map(\.paceSecPerKm)
        let mean = paces.reduce(0, +) / Double(paces.count)
        guard mean > 0 else { return false }
        let sd = sqrt(paces.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(paces.count))
        return sd / mean <= 0.08
    }

    /// ≥ 8 km AND > 120% of 4-week median distance (or ≥ 12 km with no history)
    private static func isLongRun(activity: Activity, base: Baseline) -> Bool {
        guard activity.distance >= 8000 else { return false }
        guard let med = base.distance else { return activity.distance >= 12000 }
        return activity.distance > med * 1.20
    }

    /// Easy / recovery run.
    /// Primary: Zone 1+2 time fraction ≥ 65% (from hrZones) — 심박이 우선, 페이스는 보지 않는다.
    /// ⚠ 예전에는 "기준선보다 빠르면 이지런 아님" 보조 조건이 있었다. 체력이 올라 같은 쉬운 심박으로
    ///   더 빨리 뛴 날(존1~2 77%·강도 입력 '쉬움')이 템포런이 됐다 — 좋아진 몸을 "세게 뛰었다"로 읽은 것(2026-09-24).
    /// Fallback (no hrZones): pace ≥ 15% slower than baseline.
    private static func isEasy(activity: Activity, base: Baseline, hrZones: [HRZoneData]?) -> Bool {
        if let zones = hrZones, !zones.isEmpty {
            let zone12 = zones.filter { $0.id <= 2 }.map(\.fraction).reduce(0, +)
            return zone12 >= 0.65
        }

        // hrZones 없을 때: 페이스 기반 폴백
        guard let pace = base.todayPace, let med = base.pace else { return false }
        return pace > med * 1.15
    }

    /// Faster than baseline + CV ≤ 7% across splits (uniform effort) + ≥ 4 km
    private static func isTempo(activity: Activity, base: Baseline, splits: [SplitData]) -> Bool {
        guard activity.distance >= 4000, let pace = base.todayPace, let med = base.pace else { return false }
        guard pace < med * 0.98 else { return false }

        let full = splits.filter { $0.distanceM >= 900 }
        guard full.count >= 3 else { return false }  // 스플릿 부족 → 일반 러닝으로 폴백
        let paces = full.map(\.paceSecPerKm)
        let mean = paces.reduce(0, +) / Double(paces.count)
        guard mean > 0 else { return false }
        let sd = sqrt(paces.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(paces.count))
        return sd / mean <= 0.07
    }

    // MARK: - Debug Trace (임시 — 경계 케이스 검증 후 제거)
#if DEBUG
    /// classify와 동일한 로직으로 분류하되, 각 단계의 탈락 근거를 문자열로 함께 반환.
    static func classifyWithTrace(
        activity: Activity,
        history: [Activity],
        splits: [SplitData],
        intervalSegments: [IntervalSegment] = [],
        hrZones: [HRZoneData]? = nil,
        existingType: WorkoutType? = nil,
        typeOf: ((UUID) -> WorkoutType?)? = nil,
        heat: MRHeatModel? = nil
    ) -> (type: WorkoutType, trace: String) {
        func pf(_ s: Double) -> String { String(format: "%d'%02d\"", Int(s) / 60, Int(s) % 60) }
        func cv(_ arr: [Double]) -> Double {
            guard arr.count >= 2 else { return 0 }
            let mean = arr.reduce(0, +) / Double(arr.count)
            guard mean > 0 else { return 0 }
            let sd = sqrt(arr.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(arr.count))
            return sd / mean * 100
        }

        guard activity.type == .running, activity.distance >= 1000 else {
            return (.general, "비러닝 또는 1km 미만")
        }
        if existingType == .race { return (.race, "대회 (확정 대회)") }

        let recentRuns = history
            .filter { $0.type == .running && $0.id != activity.id && $0.date < activity.date }
            .sorted { $0.date > $1.date }
        let base = Baseline(activity: activity, recentRuns: recentRuns, typeOf: typeOf, heat: heat)

        var notes: [String] = []
        let full = splits.filter { $0.distanceM >= 900 }
        let distKm = activity.distance / 1000
        let myPace = base.todayPace          // 15°C 환산 — 기준선과 같은 잣대
        let med = base.pace
        let baseStr = med.map { "기준 \(pf($0))(\(base.paceWindowLabel) 중앙값·\(base.paceSampleCount)회)" }
            ?? "기준없음(\(base.paceWindowLabel) \(base.paceSampleCount)회)"
        notes.append(baseStr)
        if base.heatApplied, let raw = activity.paceSecPerKm, let ref = myPace, let t = activity.temperatureC {
            notes.append("더위환산: \(Int(t.rounded()))°C \(pf(raw)) → 15°C \(pf(ref))")
        }

        // 1. 인터벌
        let workCount = intervalSegments.filter { $0.stepLabel == "운동" }.count
        let hasRecov  = intervalSegments.contains { $0.stepLabel == "회복" }
        if workCount >= 2 && hasRecov {
            return (.interval, "플랜 인터벌 \(workCount)회")
        }

        // 2. 이지런 — 심박 1차, 페이스 폴백
        if let zones = hrZones, !zones.isEmpty {
            let zone12 = zones.filter { $0.id <= 2 }.map(\.fraction).reduce(0, +)
            let pct = Int((zone12 * 100).rounded())
            if zone12 >= 0.65 {
                // 심박 우선 — 기준선보다 빨라도 이지런(isEasy와 같은 규칙)
                return (.easy, "이지: Zone2 \(pct)% ≥ 65% · \(baseStr)")
            } else {
                notes.append("이지탈락: Zone2 \(pct)% < 65%")
            }
        } else if let pace = myPace, let m = med {
            let thr = m * 1.15
            if pace > thr {
                return (.easy, "이지(페이스폴백): \(pf(pace)) > 기준\(pf(m))×1.15=\(pf(thr)) · \(baseStr)")
            }
            notes.append("이지탈락: Zone2없음·페이스 \(pf(pace)) ≤ \(pf(thr))(기준\(pf(m))×1.15)")
        } else {
            notes.append("이지탈락: Zone2없음·기준선 없음")
        }

        // 3. 빌드업 — 3등분 단조 or 선형 회귀 R²≥0.40
        if full.count >= 4 {
            let ps = full.map(\.paceSecPerKm)
            let fp = ps.first!, lp = ps.last!
            if lp < fp * 0.95 {
                let n = ps.count; let t = max(1, n / 3)
                let avgOf: (ArraySlice<Double>) -> Double = { s in s.reduce(0,+) / Double(s.count) }
                let a1 = avgOf(ps[0..<t]), a2 = avgOf(ps[t..<(2*t)]), a3 = avgOf(ps[(2*t)...])
                if a1 > a2 && a2 > a3 {
                    return (.buildUp, "빌드업(단조3분구) \(pf(fp))→\(pf(lp))")
                }
                let xMean = Double(n-1)/2.0, yMean = ps.reduce(0,+)/Double(n)
                var sxy = 0.0, sxx = 0.0, syy = 0.0
                for (i, y) in ps.enumerated() {
                    let dx = Double(i)-xMean; let dy = y-yMean
                    sxy += dx*dy; sxx += dx*dx; syy += dy*dy
                }
                if sxx > 0 && syy > 0 && sxy/sxx < 0 {
                    let r2 = (sxy*sxy)/(sxx*syy)
                    if r2 >= 0.40 {
                        return (.buildUp, "빌드업(R²=\(String(format:"%.2f",r2))) \(pf(fp))→\(pf(lp))")
                    }
                    notes.append("빌드업탈락: 단조3분구✗ R²=\(String(format:"%.2f",r2)) < 0.40")
                } else {
                    notes.append("빌드업탈락: 단조3분구✗ 기울기≥0")
                }
            } else {
                notes.append("빌드업탈락: 초→말 개선 \(Int((1-lp/fp)*100))% < 5%")
            }
        } else {
            notes.append("빌드업탈락: splits \(full.count) < 4")
        }

        // 롱런 여부 (4·5·6 공용) — 4주 거리 중앙값 × 1.20
        let medKm = base.distance.map { $0 / 1000 }
        let isLong: Bool = {
            guard activity.distance >= 8000 else { return false }
            if let m = base.distance { return activity.distance > m * 1.20 }
            return activity.distance >= 12000
        }()
        if !isLong {
            if activity.distance < 8000 {
                notes.append("롱런탈락: \(String(format: "%.1f", distKm))km < 8km")
            } else if let m = medKm {
                notes.append("롱런탈락: \(String(format: "%.1f", distKm))km ≤ 4주중앙 \(String(format: "%.1f", m))km × 1.20 = \(String(format: "%.1f", m * 1.20))km")
            } else {
                notes.append("롱런탈락: \(String(format: "%.1f", distKm))km < 12km(히스토리없음)")
            }
        }

        // 4. 거리주
        if isLong, let pace = myPace, let m = med {
            let thr = m * 1.10
            if pace < thr {
                return (.distanceRun, "거리주: \(pf(pace)) < 기준\(pf(m))×1.10=\(pf(thr)) · \(baseStr)")
            }
            notes.append("거리주탈락: \(pf(pace)) ≥ \(pf(thr))(기준\(pf(m))×1.10)")
        } else if isLong {
            notes.append("거리주탈락: 기준선 없음")
        }

        // 5. LSD
        if isLong, let pace = myPace, let m = med {
            let thr = m * 1.20
            if pace > thr {
                if full.count >= 3 {
                    let c = cv(full.map(\.paceSecPerKm))
                    if c <= 8 {
                        return (.lsd, "LSD: \(pf(pace)) > 기준\(pf(m))×1.20=\(pf(thr)), CV\(String(format: "%.1f", c))%")
                    }
                    notes.append("LSD탈락: pace✓ / CV \(String(format: "%.1f", c))% > 8%")
                } else {
                    notes.append("LSD탈락: splits \(full.count) < 3(CV불가)")
                }
            } else {
                notes.append("LSD탈락: \(pf(pace)) ≤ \(pf(thr))(기준\(pf(m))×1.20)")
            }
        }

        // 6. 롱런
        if isLong {
            let pctStr = medKm.map { String(format: "%.0f%%", distKm / $0 * 100) } ?? "히스토리없음"
            return (.longRun, "롱런: \(String(format: "%.1f", distKm))km \(pctStr) vs 4주중앙")
        }

        // 7. 템포런
        if activity.distance >= 4000, let pace = myPace, let m = med {
            let thr = m * 0.98
            if pace < thr {
                if full.count >= 3 {
                    let c = cv(full.map(\.paceSecPerKm))
                    if c <= 7 {
                        return (.tempo, "템포: \(pf(pace)) < 기준\(pf(m))×0.98=\(pf(thr)), CV\(String(format: "%.1f", c))% · \(baseStr)")
                    }
                    notes.append("템포탈락: pace✓\(pf(pace))<\(pf(thr)) / CV \(String(format: "%.1f", c))% > 7%")
                } else {
                    notes.append("템포탈락: pace✓ / splits \(full.count) < 3(CV불가)")
                }
            } else {
                notes.append("템포탈락: \(pf(pace)) ≥ 임계\(pf(thr))(기준\(pf(m))×0.98)")
            }
        } else if activity.distance < 4000 {
            notes.append("템포탈락: \(String(format: "%.1f", distKm))km < 4km")
        } else {
            notes.append("템포탈락: 기준선 없음")
        }

        return (.general, notes.joined(separator: " | "))
    }
#endif
}
