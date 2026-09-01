import Foundation

// MARK: - Classifier

struct WorkoutTypeClassifier {

    /// Classifies a running workout into one of eight types.
    /// Priority: race (existing confirmed) → plan (WorkoutKit) → easy (Zone2 HR / pace fallback)
    ///           → buildUp → distanceRun → LSD → longRun → tempo → general.
    /// All thresholds are personal-relative — no absolute cutoffs.
    static func classify(
        activity: Activity,
        history: [Activity],
        splits: [SplitData],
        intervalSegments: [IntervalSegment] = [],
        hrZones: [HRZoneData]? = nil,
        existingType: WorkoutType? = nil
    ) -> WorkoutType {
        guard activity.type == .running, activity.distance >= 1000 else { return .general }
        if existingType == .race { return .race }  // 대회 확정 — 재분류 없이 유지

        let recentRuns = history
            .filter { $0.type == .running
                      && $0.id != activity.id
                      && $0.date < activity.date }   // 미래 데이터 오염 방지 — 분류 결과 시점 고정
            .sorted { $0.date > $1.date }

        if isPlanInterval(intervalSegments: intervalSegments)                   { return .interval    }
        if isEasy(activity: activity, recentRuns: recentRuns, hrZones: hrZones) { return .easy        }
        if isBuildUp(splits: splits)                                            { return .buildUp     }
        if isDistanceRun(activity: activity, recentRuns: recentRuns)            { return .distanceRun }
        if isLSD(activity: activity, recentRuns: recentRuns, splits: splits)    { return .lsd         }
        if isLongRun(activity: activity, recentRuns: recentRuns)                { return .longRun     }
        if isTempo(activity: activity, recentRuns: recentRuns, splits: splits)  { return .tempo       }
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
        guard full.count >= 3 else { return false }  // 스플릿 부족 → 일반 러닝으로 폴백
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
        let recent = recentRuns.filter { $0.date >= cutoff && $0.date < activity.date }.map(\.distance)
        guard recent.count >= 3 else { return activity.distance >= 12000 }
        let avg = recent.reduce(0, +) / Double(recent.count)
        return activity.distance > avg * 1.20
    }

    /// Easy / recovery run.
    /// Primary: Zone 1+2 time fraction ≥ 65% (from hrZones), guard: pace must not be faster than personal avg.
    /// Fallback (no hrZones): pace ≥ 15% slower than 10-run average.
    private static func isEasy(activity: Activity, recentRuns: [Activity], hrZones: [HRZoneData]?) -> Bool {
        let recentPaces = recentRuns.prefix(10).compactMap(\.paceSecPerKm)
        let avgPace: Double? = recentPaces.count >= 3
            ? recentPaces.reduce(0, +) / Double(recentPaces.count) : nil

        if let zones = hrZones, !zones.isEmpty {
            let zone12 = zones.filter { $0.id <= 2 }.map(\.fraction).reduce(0, +)
            guard zone12 >= 0.65 else { return false }
            // 평균보다 빠른 페이스는 이지런 아님 (보조 조건)
            if let pace = activity.paceSecPerKm, let avg = avgPace, pace < avg { return false }
            return true
        }

        // hrZones 없을 때: 페이스 기반 폴백
        guard let pace = activity.paceSecPerKm, let avg = avgPace else { return false }
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
        existingType: WorkoutType? = nil
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

        var notes: [String] = []
        let full = splits.filter { $0.distanceM >= 900 }
        let distKm = activity.distance / 1000
        let myPace = activity.paceSecPerKm
        let recent10Paces = recentRuns.prefix(10).compactMap(\.paceSecPerKm)
        let avg10: Double? = recent10Paces.count >= 2
            ? recent10Paces.reduce(0, +) / Double(recent10Paces.count) : nil

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
                if let pace = myPace, let avg = avg10, recent10Paces.count >= 3, pace < avg {
                    notes.append("이지탈락: Zone2 \(pct)%≥65%지만 페이스 \(pf(pace)) < avg\(pf(avg))")
                } else {
                    return (.easy, "이지: Zone2 \(pct)% ≥ 65%")
                }
            } else {
                notes.append("이지탈락: Zone2 \(pct)% < 65%")
            }
        } else if let pace = myPace, recent10Paces.count >= 3, let avg = avg10 {
            let thr = avg * 1.15
            if pace > thr {
                return (.easy, "이지(페이스폴백): \(pf(pace)) > avg\(pf(avg))×1.15=\(pf(thr))")
            }
            notes.append("이지탈락: Zone2없음·페이스 \(pf(pace)) ≤ \(pf(thr))(avg\(pf(avg))×1.15)")
        } else {
            notes.append("이지탈락: Zone2없음·최근 \(recent10Paces.count)건 < 3건")
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

        // 롱런 여부 (4·5·6 공용)
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: activity.date) ?? .distantPast
        let recent4wDist = recentRuns.filter { $0.date >= cutoff }.map(\.distance)
        let avg4wKm: Double? = recent4wDist.count >= 3
            ? recent4wDist.reduce(0, +) / Double(recent4wDist.count) / 1000 : nil
        let isLong: Bool = {
            guard activity.distance >= 8000 else { return false }
            if let avg = avg4wKm { return activity.distance > avg * 1000 * 1.20 }
            return activity.distance >= 12000
        }()
        if !isLong {
            if activity.distance < 8000 {
                notes.append("롱런탈락: \(String(format: "%.1f", distKm))km < 8km")
            } else if let avg = avg4wKm {
                notes.append("롱런탈락: \(String(format: "%.1f", distKm))km ≤ \(String(format: "%.1f", avg))km × 1.20 = \(String(format: "%.1f", avg * 1.20))km")
            } else {
                notes.append("롱런탈락: \(String(format: "%.1f", distKm))km < 12km(히스토리없음)")
            }
        }

        // 4. 거리주
        if isLong, let pace = myPace, recent10Paces.count >= 3, let avg = avg10 {
            let thr = avg * 1.10
            if pace < thr {
                return (.distanceRun, "거리주: \(pf(pace)) < avg\(pf(avg))×1.10=\(pf(thr))")
            }
            notes.append("거리주탈락: \(pf(pace)) ≥ \(pf(thr))(avg\(pf(avg))×1.10)")
        } else if isLong {
            notes.append("거리주탈락: 최근 \(recent10Paces.count)건 < 3건")
        }

        // 5. LSD
        if isLong, let pace = myPace, recent10Paces.count >= 3, let avg = avg10 {
            let thr = avg * 1.20
            if pace > thr {
                if full.count >= 3 {
                    let c = cv(full.map(\.paceSecPerKm))
                    if c <= 8 {
                        return (.lsd, "LSD: \(pf(pace)) > avg\(pf(avg))×1.20=\(pf(thr)), CV\(String(format: "%.1f", c))%")
                    }
                    notes.append("LSD탈락: pace✓ / CV \(String(format: "%.1f", c))% > 8%")
                } else {
                    notes.append("LSD탈락: splits \(full.count) < 3(CV불가)")
                }
            } else {
                notes.append("LSD탈락: \(pf(pace)) ≤ \(pf(thr))(avg\(pf(avg))×1.20)")
            }
        }

        // 6. 롱런
        if isLong {
            let pctStr = avg4wKm.map { String(format: "%.0f%%", distKm / $0 * 100) } ?? "히스토리없음"
            return (.longRun, "롱런: \(String(format: "%.1f", distKm))km \(pctStr) vs 4주평균")
        }

        // 7. 템포런
        if activity.distance >= 4000, let pace = myPace, recent10Paces.count >= 2, let avg = avg10 {
            let thr = avg * 0.98
            if pace < thr {
                if full.count >= 3 {
                    let c = cv(full.map(\.paceSecPerKm))
                    if c <= 7 {
                        return (.tempo, "템포: \(pf(pace)) < avg\(pf(avg))×0.98=\(pf(thr)), CV\(String(format: "%.1f", c))%")
                    }
                    notes.append("템포탈락: pace✓\(pf(pace))<\(pf(thr)) / CV \(String(format: "%.1f", c))% > 7%")
                } else {
                    notes.append("템포탈락: pace✓ / splits \(full.count) < 3(CV불가)")
                }
            } else {
                notes.append("템포탈락: \(pf(pace)) ≥ 임계\(pf(thr))(avg\(pf(avg))×0.98)")
            }
        } else if activity.distance < 4000 {
            notes.append("템포탈락: \(String(format: "%.1f", distKm))km < 4km")
        } else {
            notes.append("템포탈락: 최근 \(recent10Paces.count)건 < 2건")
        }

        return (.general, notes.joined(separator: " | "))
    }
#endif
}
