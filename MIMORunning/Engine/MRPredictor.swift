import Foundation

// MARK: - 개인 Riegel 지수 적합

struct MRExponentFit {
    var ok = false
    var b = 1.06
    var bCI = 0.0
    var n = 0
    var sxx = 0.0
    var sigma = 0.0              // 잔차 SD (log 스케일)
    var minLogD = 0.0
    var maxLogD = 0.0
    var measuredMarathonB: Double?

    /// 목표 거리에 쓸 지수.
    /// 관측 범위 밖으로 외삽할수록 인구 사전확률 쪽으로 축소한다.
    /// (log 거리 0.7마다 e분의 1)
    func bFor(distanceM: Double, prior: Double) -> (b: Double, weight: Double) {
        guard ok else { return (prior, 0) }
        let ld = log(distanceM)
        let extrap = max(0, max(minLogD - ld, ld - maxLogD))
        let w = exp(-extrap / 0.7)
        return (b * w + prior * (1 - w), w)
    }
}

func mrFitExponent(_ efforts: [MRRaceEffort]) -> MRExponentFit {
    var f = MRExponentFit()

    // ⚠ 마라톤 제외 (30km 미만만). Riegel은 하프까지는 잘 맞고
    //   마라톤에서만 체계적으로 어긋난다(durability). 섞으면 b가 부풀려진다.
    var subs = efforts.filter { $0.distanceM < 30_000 }
    if subs.count >= 4, let newest = subs.map(\.date).max() {
        let recent = subs.filter { newest.timeIntervalSince($0.date) <= 730 * 86400 }
        if recent.count >= 3, Set(recent.map(\.distanceM)).count >= 2 { subs = recent }
    }

    // 회귀가 안 되더라도 실측 마라톤 지수는 뽑을 수 있으므로 먼저 계산해 둔다
    defer { }
    guard subs.count >= 3, Set(subs.map(\.distanceM)).count >= 2 else {
        f.measuredMarathonB = mrMeasuredMarathonB(efforts, trendPerYear: 0)
        return f
    }

    let years = subs.map { $0.date.timeIntervalSince1970 / 86400 / 365.25 }
    let tMax = years.max()!
    let spanYears = tMax - years.min()!
    let useTime = spanYears > 0.5 && subs.count >= 4

    var logD = subs.map { log($0.distanceM) }
    var logT = subs.map { log($0.timeMinRef) }
    var tRel = years.map { $0 - tMax }

    func buildX(_ ld: [Double], _ tr: [Double]) -> [[Double]] {
        useTime ? zip(ld, tr).map { [1.0, $0, $1] } : ld.map { [1.0, $0] }
    }
    let p = useTime ? 3 : 2

    // ★ 추가 1 — 반복 이상치 제거 (2회, 2.5σ)
    //   나쁜 대회 한 번이 지수를 망치지 않게 한다.
    var keep = [Bool](repeating: true, count: logT.count)
    for _ in 0..<2 {
        let idx = keep.indices.filter { keep[$0] }
        guard idx.count > p + 1 else { break }
        let X = buildX(idx.map { logD[$0] }, idx.map { tRel[$0] })
        guard let c = MRLinAlg.lstsq(X: X, y: idx.map { logT[$0] }) else { break }
        var resid = [Double](repeating: 0, count: logT.count)
        for i in logT.indices {
            var pred = c[0] + c[1] * logD[i]
            if useTime { pred += c[2] * tRel[i] }
            resid[i] = logT[i] - pred
        }
        let kept = idx.map { resid[$0] }
        let mean = kept.reduce(0, +) / Double(kept.count)
        let sd = (kept.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
                  / Double(max(kept.count - 1, 1))).squareRoot()
        guard sd > 1e-6 else { break }
        let next = resid.map { abs($0) <= 2.5 * sd }
        if next == keep { break }
        keep = zip(keep, next).map { $0 && $1 }
    }
    let sel = keep.indices.filter { keep[$0] }
    if sel.count >= p + 1 {
        logD = sel.map { logD[$0] }
        logT = sel.map { logT[$0] }
        tRel = sel.map { tRel[$0] }
    }

    let mean = logD.reduce(0, +) / Double(logD.count)
    f.sxx = logD.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
    f.n = logD.count
    guard f.sxx >= 0.05 else {
        f.measuredMarathonB = mrMeasuredMarathonB(efforts, trendPerYear: 0)
        return f
    }

    let X = buildX(logD, tRel)
    guard let c = MRLinAlg.lstsq(X: X, y: logT) else {
        f.measuredMarathonB = mrMeasuredMarathonB(efforts, trendPerYear: 0)
        return f
    }
    let bRaw = c[1]
    let trend = useTime ? c[2] : 0.0
    f.sigma = max(MRLinAlg.residualSD(X: X, y: logT, coef: c, ddof: p), 0.015)

    // ★ 추가 2 — 거리·시간 교락 측정
    //   초기엔 짧고 느리게, 나중엔 길고 빠르게 달린 사람은
    //   거리 계수와 시간 계수가 서로를 갉아먹는다.
    var collin = 0.0
    if useTime && logT.count >= 4 {
        collin = abs(mrCorrelation(logD, tRel))
    }

    // ★ 추가 3 — 인구 사전확률(1.07) 쪽으로 축소
    //   교락이 심할수록 더 많이 축소한다.
    //   ⚠ 이 축소가 없으면 원값 0.99 같은 값이 그대로 나온다.
    //     Riegel 지수가 1보다 작다는 것은 "거리가 늘수록 페이스가 빨라진다"는
    //     뜻이라 물리적으로 불가능하다.
    let tau = 0.035 * max(0.25, 1.0 - collin)
    let bPrior = 1.07
    let wData = f.sxx / (f.sxx + (f.sigma * f.sigma) / (tau * tau))
    f.b = wData * bRaw + (1 - wData) * bPrior
    // 하프 이하 구간의 지수는 물리적으로 이 범위를 벗어나지 않는다
    f.b = min(max(f.b, 1.00), 1.16)
    f.bCI = 1.96 * f.sigma / f.sxx.squareRoot()
    f.minLogD = logD.min()!
    f.maxLogD = logD.max()!
    f.ok = true
    f.measuredMarathonB = mrMeasuredMarathonB(efforts, trendPerYear: trend)
    return f
}

func mrCorrelation(_ a: [Double], _ b: [Double]) -> Double {
    let n = Double(a.count)
    let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
    var cov = 0.0, va = 0.0, vb = 0.0
    for i in a.indices {
        cov += (a[i] - ma) * (b[i] - mb)
        va += (a[i] - ma) * (a[i] - ma)
        vb += (b[i] - mb) * (b[i] - mb)
    }
    guard va > 1e-18, vb > 1e-18 else { return 0 }
    return cov / (va * vb).squareRoot()
}

/// 하프와 풀이 **12개월** 이내에 함께 있으면 마라톤 지수를 '측정'한다.
///
/// ⚠ 창을 200일로 잡으면 안 된다. 데니 님의 하프(4/6)와 풀(11/23)은
///   231일 간격이라 그대로 놓친다. 아마추어는 봄 하프 / 가을 풀이 정석이라
///   6~8개월 간격이 오히려 표준이다.
func mrMeasuredMarathonB(_ efforts: [MRRaceEffort],
                         trendPerYear: Double) -> Double? {
    let halves = efforts.filter { abs($0.distanceM - MRDistance.dH) < 1 }
    let fulls  = efforts.filter { abs($0.distanceM - MRDistance.dF) < 1 }
    var best: (gap: Int, h: MRRaceEffort, f: MRRaceEffort)?
    for fu in fulls {
        for hf in halves {
            let gap = Int(abs(fu.date.timeIntervalSince(hf.date)) / 86400)
            if gap <= 365 && (best == nil || gap < best!.gap) {
                best = (gap, hf, fu)
            }
        }
    }
    guard let b = best else { return nil }

    // 추세 보정은 간격이 짧을 때만. 불확실한 추세를 먼 간격에 곱하면
    // 보정이 오차를 키운다.
    let dtYears = b.f.date.timeIntervalSince(b.h.date) / 86400 / 365.25
    let hAdj = b.h.timeMinRef * (b.gap <= 120 ? exp(trendPerYear * dtYears) : 1.0)
    let exponent = log(b.f.timeMinRef / hAdj) / log(2.0)
    return min(max(exponent, 1.03), 1.40)
}

// MARK: - 예측

struct MRProfile {
    var weeklyKm4w = 0.0
    var longestRun30d = 0.0     // 최근 30일 최장 런 — 플래너 입문 가드용
    var longestRun16wKm = 0.0
    var marathonFinishes = 0
    /// 최근 4주 주당 러닝 횟수. 지시가 아니라 **관찰값**이다.
    var runsPerWeek = 0.0
    /// 최근 52주(12개월) 최대 주간 거리. 판단이 아니라 사실 전달용.
    var maxWeeklyKm52w = 0.0
    /// OLS d²=a+b·T 분해 (T단위: 주). a: 관측 노이즈 분산(백테스트로 고정), b: 체력 변동 속도 분산/주.
    /// 셋 다 0이면 데이터 부족.
    var sigma8A: Double = 0    // intercept: 관측 노이즈 분산 (= 2·σ_obs²)
    var sigma8B: Double = 0    // slope: 체력 변동 분산/주
    var sigma8BSE: Double = 0  // SE(b): b 추정 표준오차
}

func mrProfile(runs: [MRWorkout], efforts: [MRRaceEffort], sigmaObs: Double = 0, asOf: Date) -> MRProfile {
    var p = MRProfile()
    let cal = Calendar.current
    func days(_ d: Date) -> Int {
        cal.dateComponents([.day], from: d, to: cal.startOfDay(for: asOf)).day ?? -1
    }
    // ★ 하한 0을 반드시 넣는다. 없으면 미래 러닝이 전부 통과한다.
    let last28 = runs.filter { let d = days($0.date); return d >= 0 && d < 28 }
    p.weeklyKm4w = last28.compactMap(\.distanceKm).reduce(0, +) / 4.0
    p.runsPerWeek = Double(last28.count) / 4.0

    let last30 = runs.filter { let d = days($0.date); return d >= 0 && d < 30 }
    p.longestRun30d = last30.compactMap(\.distanceKm).max() ?? 0

    let last16w = runs.filter { let d = days($0.date); return d >= 0 && d < 112 }
    p.longestRun16wKm = last16w.compactMap(\.distanceKm).max() ?? 0

    p.marathonFinishes = efforts.filter { $0.distanceM >= 40_000 }.count

    // 52주 최대 주간 거리 — Calendar.iso8601 (mrActiveWeekStreak와 동일한 기준)
    // ⚠ Calendar.current 는 firstWeekday 로케일 의존 → yearForWeekOfYear 가 0이 나올 수 있다.
    var isoCal = Calendar(identifier: .iso8601)
    isoCal.timeZone = .current
    let runs12m = runs.filter { let d = days($0.date); return d >= 0 && d < 364 }
    print(String(format: "[계획] 52주최대 — 입력 runs=%d건 · 12개월내=%d건",
                 runs.count, runs12m.count))
    var weekBins = [String: Double]()
    for r in runs12m {
        let c = isoCal.dateComponents([.weekOfYear, .yearForWeekOfYear], from: r.date)
        let key = "\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
        weekBins[key, default: 0] += r.distanceKm ?? 0
    }
    let maxEntry = weekBins.max(by: { $0.value < $1.value })
    p.maxWeeklyKm52w = maxEntry?.value ?? 0
    print(String(format: "[계획] 52주최대 — 주 버킷 %d개 · 최대 %.1fkm (%@)",
                 weekBins.count, p.maxWeeklyKm52w, maxEntry?.key ?? "-"))

    // d²=a+b·T 분해 (T단위: 주, d=log(하프등가비))
    // a = 2·σ_obs² — 백테스트 잔차로 고정 (관측 노이즈)
    // b 만 절편 고정 최소제곱: b = Σ((d²-a)·T) / Σ(T²), b<0이면 0 클램프
    // 12개월 노력 3건 미만이면 24개월로 확장
    let efforts12m = efforts.filter { let d = days($0.date); return d >= 0 && d < 364 }
    let efforts24m = efforts.filter { let d = days($0.date); return d >= 0 && d < 728 }
    let effortsForSigma: [MRRaceEffort]
    let sigmaWindowLabel: String
    if efforts12m.count >= 3 {
        effortsForSigma = efforts12m
        sigmaWindowLabel = "12개월내 \(efforts12m.count)건"
    } else if efforts24m.count >= 3 {
        effortsForSigma = efforts24m
        sigmaWindowLabel = "12개월 \(efforts12m.count)건→24개월 확장 \(efforts24m.count)건"
    } else {
        effortsForSigma = efforts24m
        sigmaWindowLabel = "24개월내 \(efforts24m.count)건(부족)"
    }

    // 모든 쌍 (i < j), 2주(14일) 이상 간격 → (T, d²) 수집
    var olsPairs = [(T: Double, dSq: Double)]()
    if effortsForSigma.count >= 2 {
        let sortedHE = effortsForSigma.sorted { $0.date < $1.date }.compactMap { e -> (Date, Double)? in
            guard e.distanceM > 0, e.timeMinRef > 0 else { return nil }
            let he = e.timeMinRef * pow(MRDistance.dH / e.distanceM, 1.06)
            return (e.date, he)
        }
        for i in 0..<sortedHE.count {
            for j in (i + 1)..<sortedHE.count {
                let (d1, h1) = sortedHE[i]
                let (d2, h2) = sortedHE[j]
                let dayGap = Double(cal.dateComponents([.day], from: d1, to: d2).day ?? 0)
                guard dayGap >= 14, h1 > 0, h2 > 0 else { continue }
                let T = dayGap / 7.0
                let delta = log(h2 / h1)
                olsPairs.append((T: T, dSq: delta * delta))
            }
        }
    }

    let aFixed = 2.0 * sigmaObs * sigmaObs
    if olsPairs.count >= 3 {
        let Tmin = olsPairs.map(\.T).min() ?? 0
        let Tmax = olsPairs.map(\.T).max() ?? 0
        let Tsq  = olsPairs.map { $0.T * $0.T }.reduce(0, +)
        let sumNumer = olsPairs.map { ($0.dSq - aFixed) * $0.T }.reduce(0, +)

        if Tsq > 1e-9 {
            let b = max(0, sumNumer / Tsq)
            // SE(b): 잔차 표준오차 / √Σ(T²)
            let residSS = olsPairs.map { pair -> Double in
                let e = pair.dSq - aFixed - b * pair.T; return e * e
            }.reduce(0, +)
            let seB = sqrt(residSS / max(1, Double(olsPairs.count) - 1) / Tsq)

            p.sigma8A   = aFixed
            p.sigma8B   = b
            p.sigma8BSE = seB

            // 진단 로그 — 노력이 쌓일수록 폭이 좁아지는지 확인용
            let pct12 = (exp(sqrt(max(0, aFixed + b * 12))) - 1) * 100
            let pct32 = (exp(sqrt(max(0, aFixed + b * 32))) - 1) * 100
            print(String(format: "[예측] 쌍 %d개 · a=%.5f · b=%.7f · 12주 ±%.1f%% · 32주 ±%.1f%%",
                         olsPairs.count, aFixed, b, pct12, pct32))
            if seB > b {
                print(String(format: "[예측] ⚠ SE(b)=%.7f > b=%.7f", seB, b))
            }
        } else {
            print("[예측] σ8 — 실패 사유: T 분산 없음(\(sigmaWindowLabel))")
        }
    } else if effortsForSigma.count < 2 {
        print("[예측] σ8 — 실패 사유: 노력 부족(\(sigmaWindowLabel), 최소 2건)")
    } else {
        print("[예측] σ8 — 실패 사유: 쌍 부족(\(sigmaWindowLabel), 2주 이상 간격 쌍 \(olsPairs.count)개, 최소 3개)")
    }

    return p
}

/// 백테스트 잔차에서 단일 레이스 관측 노이즈 σ_obs (log 단위)를 추출한다.
/// 반환값 0이면 데이터 없음 — mrProfile의 sigmaObs 기본값과 동일하게 처리됨.
func mrSigmaObs(backtest: [MRBacktestRow]) -> Double {
    let logResiduals = backtest.compactMap { row -> Double? in
        guard let pred = row.predictedMin, pred > 0, row.actualMin > 0 else { return nil }
        return log(pred / row.actualMin)
    }
    guard logResiduals.count >= 2 else { return 0 }
    let mean = logResiduals.reduce(0, +) / Double(logResiduals.count)
    let ss   = logResiduals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
    return sqrt(ss / Double(logResiduals.count - 1))
}

func mrPredict(efforts: [MRRaceEffort],
               fit: MRExponentFit,
               profile: MRProfile,
               heat: MRHeatModel,
               asOf: Date,
               targetTempC: Double = MR_REF_TEMP) -> [MRPrediction] {

    let cal = Calendar.current
    // 앵커 = 최근 550일 노력 중 (환산시간 / 거리^1.06)이 가장 작은 것
    let recent = efforts.filter {
        let d = cal.dateComponents([.day], from: $0.date,
                                   to: cal.startOfDay(for: asOf)).day ?? -1
        return d >= 0 && d <= 550
    }
    guard let anchor = recent.min(by: {
        $0.timeMinRef / pow($0.distanceM, 1.06) < $1.timeMinRef / pow($1.distanceM, 1.06)
    }) else { return [] }

    let ageDays = Double(cal.dateComponents([.day], from: anchor.date,
                                            to: cal.startOfDay(for: asOf)).day ?? 0)
    let (bHalf, _) = fit.bFor(distanceM: MRDistance.dH, prior: 1.06)
    let halfEquiv = anchor.timeMinRef * pow(MRDistance.dH / anchor.distanceM, bHalf)

    var out: [MRPrediction] = []
    for (label, dm) in [("5K", MRDistance.d5), ("10K", MRDistance.d10),
                        ("하프", MRDistance.dH), ("풀", MRDistance.dF)] {
        var t: Double
        var b: Double
        var w: Double
        var bExtra = 0.0
        var note: String

        if dm >= MRDistance.dF {
            // ⚠ 마라톤 지수는 '하프→풀' 구간의 지수다.
            //   10K 앵커에 그대로 곱하면 안 된다. 먼저 하프 등가로 옮긴다.
            if let mb = fit.measuredMarathonB {
                let s = shrinkMeasuredB(mb, nObs: profile.marathonFinishes)
                b = s.post
                note = String(format: "하프 등가 %@ × 지수 %.3f (실측 %.3f → 인구 축소 ±%.3f)",
                              mrFormatHMS(halfEquiv), b, mb, s.sd)
                w = 0.7
            } else {
                let m = bMarathonModel(weeklyKm: profile.weeklyKm4w,
                                       longestKm: profile.longestRun16wKm,
                                       finishes: profile.marathonFinishes)
                b = m.b; bExtra = m.extraSD; w = 0
                note = String(format: "하프 등가 %@ × 지수 %.3f (주 %.0fkm · 롱런 %.0fkm)",
                              mrFormatHMS(halfEquiv), b, profile.weeklyKm4w, profile.longestRun16wKm)
            }
            t = halfEquiv * pow(2.0, b)
        } else {
            let r = fit.bFor(distanceM: dm, prior: 1.06)
            b = r.b; w = r.weight
            note = w >= 0.95 ? "개인 지수 (관측 범위 내)"
                 : (w > 0.05 ? String(format: "개인 지수 %.0f%% + 기본 1.06 (외삽 축소)", w * 100)
                             : "기본 지수 1.06")
            t = anchor.timeMinRef * pow(dm / anchor.distanceM, b)
        }

        // 불확실도
        let sePersonal = fit.ok ? fit.bCI / 1.96 : 0.035
        let seExp = w * sePersonal + (1 - w) * 0.035
        let logGap = abs(log(dm / anchor.distanceM))
        var se = (fit.sigma * fit.sigma
                  + pow(logGap * seExp, 2)
                  + pow(log(2.0) * bExtra, 2)).squareRoot()
        se += 0.003 * (ageDays / 30.0)

        // 15°C 기준값을 목표 기온으로 환산
        if heat.ok, abs(targetTempC - MR_REF_TEMP) > 0.5 {
            t /= exp(heat.logDelta(targetTempC))
        }

        var lo = t * exp(-1.96 * se)
        var hi = t * exp(1.96 * se)
        if dm >= MRDistance.dF {
            if fit.measuredMarathonB == nil { hi = t * exp(1.96 * se * 1.6) }
            // ★ 최소 구간 폭. Vickers의 검증 모델도 RMSE≈14분이다.
            lo = min(lo, t - 20.0)
            hi = max(hi, t + 20.0)
        }

        let halfWidth = (hi - lo) / 2 / t
        var conf: MRConfidence = halfWidth <= 0.035 ? .high
                               : halfWidth <= 0.075 ? .medium
                               : halfWidth <= 0.22  ? .low : .none
        if dm >= MRDistance.dF && profile.weeklyKm4w < 5 { conf = .none }

        out.append(MRPrediction(label: label, distanceM: dm, midMin: t,
                                loMin: lo, hiMin: hi, confidence: conf,
                                basis: ["기준: \(anchor.label) \(mrFormatHMS(anchor.timeMin)) (\(Int(ageDays))일 전)",
                                        String(format: "지수 b=%.3f — %@", b, note)]))
    }
    return out
}
