import Foundation

// MARK: - Pace Band

enum PaceBand: String, CaseIterable, Codable, Hashable {
    case verySlow = "아주 느림"
    case jog      = "느린 편"
    case daily    = "보통"
    case tempo    = "빠른 편"
    case fast     = "가장 빠른"
}

// MARK: - Dynamic Band Cutoffs
// 경계는 개인 데이터의 25/50/75 백분위에서 계산. 하드코딩 금지.

struct PaceBandCutoffs: Codable {
    let jogMax: Double      // jog 구간 상한 (중앙값+1.2SD). 이 값 이상 = verySlow
    let jogMin: Double      // 75th percentile — 이 값 이상 = jog 또는 verySlow
    let dailyMin: Double    // 50th percentile — 이 값 이상 = daily
    let tempoMin: Double    // 25th percentile — 이 값 이상 = tempo, 미만 = fast
    let mergedBands: [PaceBand]  // 병합되어 사라진 구간 (gap < 30s)

    func band(of pace: Double) -> PaceBand {
        if pace >= jogMax   { return .verySlow }
        if pace >= jogMin   { return .jog }
        if pace >= dailyMin { return .daily }
        if pace >= tempoMin { return .tempo }
        return .fast
    }

    /// 실제 유효 구간 목록 (병합된 구간 제외)
    var activeBands: [PaceBand] {
        PaceBand.allCases.filter { !mergedBands.contains($0) }
    }
}

// MARK: - Models

struct FormStat: Codable {
    let median: Double
    let sd: Double
    let count: Int
    var lower: Double { median - 1.2 * sd }
    var upper: Double { median + 1.2 * sd }
}

struct BandBaseline: Codable {
    let band: PaceBand
    let sampleCount: Int
    let windowMonths: Int
    let paceMin: Double
    let paceMax: Double
    let cadence: FormStat?
    let strideLength: FormStat?
    let groundContact: FormStat?
    let verticalOsc: FormStat?
    let heartRate: FormStat?
    // 주법 판정용 — 잔차 상관계수 및 분위수
    let cadenceStrideR: Double?
    let cadenceResidualP10: Double?
    let cadenceResidualP25: Double?
    let cadenceResidualP75: Double?
    let cadenceResidualP90: Double?
    let strideResidualP10: Double?
    let strideResidualP25: Double?
    let strideResidualP75: Double?
    let strideResidualP90: Double?

    var paceRange: ClosedRange<Double> { paceMin...paceMax }
}

struct RunningFormBaseline: Codable {
    static let currentVersion = 7
    let version: Int
    let computedAt: Date
    let cutoffs: PaceBandCutoffs
    let bands: [PaceBand: BandBaseline]
    var isEmpty: Bool { bands.isEmpty }
}

// MARK: - Persistent Form Cache

/// 폼 지표 UserDefaults 캐시. ActivityDetail 없이도 기준선 계산에 쓸 수 있도록
/// HealthKit 조회 후 저장. 전체 ActivityDetail(수백KB)보다 훨씬 가벼움.
struct CachedFormMetrics: Codable {
    let cadence: Int?
    let strideLength: Double?
    let groundContact: Double?
    let verticalOsc: Double?
    let heartRate: Int?
    let paceSecPerKm: Double?
    let date: Date
}

// MARK: - Input DTO
// Activity에 폼 지표가 없어(ActivityDetail에 존재) 호출자가 둘을 합성해 전달.

struct FormInput {
    let date: Date
    let paceSecPerKm: Double
    let avgHeartRate: Int?
    let avgCadence: Int?
    let avgStrideLength: Double?
    let avgGroundContactTime: Double?
    let avgVerticalOscillation: Double?

    init?(activity: Activity, detail: ActivityDetail) {
        guard activity.type == .running,
              activity.distance >= 3000,
              let pace = activity.paceSecPerKm,
              detail.avgCadence != nil          // 폼 데이터 없는 기록 제외
        else { return nil }
        self.date                   = activity.date
        self.paceSecPerKm           = pace
        self.avgHeartRate           = activity.avgHeartRate
        self.avgCadence             = detail.avgCadence
        self.avgStrideLength        = detail.avgStrideLength
        self.avgGroundContactTime   = detail.avgGroundContactTime
        self.avgVerticalOscillation = detail.avgVerticalOscillation
    }
}

extension FormInput {
    /// CachedFormMetrics(UserDefaults)에서 생성. detailCache 없이도 기준선 계산 가능.
    init?(activity: Activity, cached: CachedFormMetrics) {
        guard activity.type == .running,
              activity.distance >= 3000,
              let pace = activity.paceSecPerKm,
              cached.cadence != nil else { return nil }
        self.date                   = activity.date
        self.paceSecPerKm           = pace
        self.avgHeartRate           = cached.heartRate
        self.avgCadence             = cached.cadence
        self.avgStrideLength        = cached.strideLength
        self.avgGroundContactTime   = cached.groundContact
        self.avgVerticalOscillation = cached.verticalOsc
    }
}

// MARK: - Engine

@MainActor
enum FormBaselineEngine {
    static let minSamples = 5
    private static let cacheKey = "mimo.formBaseline.v7"
    private static let cacheTTL: TimeInterval = 7 * 24 * 3600

    // nil = 아직 읽지 않음, .some(nil) = 읽었으나 캐시 없음, .some(.some(v)) = 유효한 캐시
    private static var memo: RunningFormBaseline?? = nil

    /// 캐시를 동기적으로 조회. @MainActor → ActivityDetailView(@MainActor) @State 초기값으로 사용 가능. 계산 없음.
    /// memo로 반복 disk I/O 방지 — View 재생성마다 UserDefaults+JSON decode 건너뜀.
    static func peekFromCache() -> RunningFormBaseline? {
        if let result = memo { return result }  // outer non-nil: 이미 조회됨
        let found: RunningFormBaseline?
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(RunningFormBaseline.self, from: data),
           cached.version == RunningFormBaseline.currentVersion,
           Date().timeIntervalSince(cached.computedAt) <= cacheTTL {
            found = cached
        } else {
            found = nil
        }
        memo = .some(found)
        return found
    }

    /// 캐시 삭제. 백필 완료 후 재계산 트리거 시 사용.
    static func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        memo = nil
    }
    #if DEBUG
    /// 개발 중 true로 변경하면 캐시 무시 후 항상 재계산.
    static var forceRecompute = false
    #endif

    // MARK: Compute

    static func compute(from inputs: [FormInput]) -> RunningFormBaseline {
        #if DEBUG
        print("[Baseline:계산] 입력 FormInput 총 \(inputs.count)개")
        #endif
        let now = Date()
        let window12 = Calendar.current.date(byAdding: .month, value: -12, to: now) ?? .distantPast
        let window6  = Calendar.current.date(byAdding: .month, value: -6,  to: now) ?? .distantPast

        // 12개월 폼 데이터 전체
        let all12 = inputs.filter { $0.date >= window12 }
        #if DEBUG
        print("[Baseline:계산] 12개월 이내 \(all12.count)개 / 케이던스있는 것 \(all12.filter { $0.avgCadence != nil }.count)개")
        #endif

        // 경계 산출: 반드시 12개월 전체 사용 — 6개월 부분 집합은 페이스 폭이 좁아 구간 병합 오류 발생
        let cutoffs = computeCutoffs(from: all12.map(\.paceSecPerKm))
        #if DEBUG
        if !all12.isEmpty {
            let _n = Double(all12.count)
            let _vPct = Int(Double(all12.filter { cutoffs.band(of: $0.paceSecPerKm) == .verySlow }.count) / _n * 100 + 0.5)
            let _jPct = Int(Double(all12.filter { cutoffs.band(of: $0.paceSecPerKm) == .jog     }.count) / _n * 100 + 0.5)
            let _dPct = Int(Double(all12.filter { cutoffs.band(of: $0.paceSecPerKm) == .daily   }.count) / _n * 100 + 0.5)
            let _tPct = Int(Double(all12.filter { cutoffs.band(of: $0.paceSecPerKm) == .tempo   }.count) / _n * 100 + 0.5)
            let _fPct = Int(Double(all12.filter { cutoffs.band(of: $0.paceSecPerKm) == .fast    }.count) / _n * 100 + 0.5)
            print("  구간 비율: \(PaceBand.verySlow.rawValue) \(_vPct)% \(PaceBand.jog.rawValue) \(_jPct)% \(PaceBand.daily.rawValue) \(_dPct)% \(PaceBand.tempo.rawValue) \(_tPct)% \(PaceBand.fast.rawValue) \(_fPct)%")
        }
        #endif

        var bands: [PaceBand: BandBaseline] = [:]

        for band in cutoffs.activeBands {
            // 적응형 기간
            let samples6  = all12.filter { $0.date >= window6  && cutoffs.band(of: $0.paceSecPerKm) == band }
            let samples12 = all12.filter {                         cutoffs.band(of: $0.paceSecPerKm) == band }

            let (samples, windowMonths): ([FormInput], Int)
            if samples6.count >= minSamples {
                (samples, windowMonths) = (samples6, 6)
            } else if samples12.count >= minSamples {
                (samples, windowMonths) = (samples12, 12)
            } else {
                continue
            }

            let paces   = samples.map(\.paceSecPerKm)
            let cadStat = formStat(samples.compactMap { $0.avgCadence.map(Double.init) })
            let strStat = formStat(samples.compactMap { $0.avgStrideLength })

            // 잔차 상관 및 분위수 — 주법 판정용
            let pairs: [(Double, Double)] = samples.compactMap { s in
                guard let c = s.avgCadence.map(Double.init), let t = s.avgStrideLength else { return nil }
                return (c, t)
            }
            var cadenceStrideR:     Double? = nil
            var cadenceResidualP10: Double? = nil
            var cadenceResidualP25: Double? = nil
            var cadenceResidualP75: Double? = nil
            var cadenceResidualP90: Double? = nil
            var strideResidualP10:  Double? = nil
            var strideResidualP25:  Double? = nil
            var strideResidualP75:  Double? = nil
            var strideResidualP90:  Double? = nil

            if let cs = cadStat, let ss = strStat, pairs.count >= 5 {
                let cadRes = pairs.map { $0.0 - cs.median }
                let strRes = pairs.map { $0.1 - ss.median }
                cadenceStrideR = pearsonR(cadRes, strRes)
                let cadSorted = cadRes.sorted()
                let strSorted = strRes.sorted()
                cadenceResidualP10 = percentile(cadSorted, 0.10)
                cadenceResidualP25 = percentile(cadSorted, 0.25)
                cadenceResidualP75 = percentile(cadSorted, 0.75)
                cadenceResidualP90 = percentile(cadSorted, 0.90)
                strideResidualP10  = percentile(strSorted, 0.10)
                strideResidualP25  = percentile(strSorted, 0.25)
                strideResidualP75  = percentile(strSorted, 0.75)
                strideResidualP90  = percentile(strSorted, 0.90)
                #if DEBUG
                let rStr = cadenceStrideR.map { String(format: "%.3f", $0) } ?? "nil"
                print("[주법:상관] 구간=\(band.rawValue) r=\(rStr) n=\(pairs.count)")
                #endif
            }

            bands[band] = BandBaseline(
                band:         band,
                sampleCount:  samples.count,
                windowMonths: windowMonths,
                paceMin:      paces.min() ?? 0,
                paceMax:      paces.max() ?? 0,
                cadence:      cadStat,
                strideLength: strStat,
                groundContact: formStat(samples.compactMap { $0.avgGroundContactTime }),
                verticalOsc:  formStat(samples.compactMap { $0.avgVerticalOscillation }),
                heartRate:    formStat(samples.compactMap { $0.avgHeartRate.map(Double.init) }),
                cadenceStrideR:     cadenceStrideR,
                cadenceResidualP10: cadenceResidualP10,
                cadenceResidualP25: cadenceResidualP25,
                cadenceResidualP75: cadenceResidualP75,
                cadenceResidualP90: cadenceResidualP90,
                strideResidualP10:  strideResidualP10,
                strideResidualP25:  strideResidualP25,
                strideResidualP75:  strideResidualP75,
                strideResidualP90:  strideResidualP90
            )
        }

        let result = RunningFormBaseline(version: RunningFormBaseline.currentVersion,
                                         computedAt: now, cutoffs: cutoffs, bands: bands)
        #if DEBUG
        print("[Baseline:계산] 결과 구간 \(result.bands.count)개")
        logBaseline(result)
        #endif
        return result
    }

    // MARK: Load or Compute

    static func loadOrCompute(inputs: [FormInput]) async -> RunningFormBaseline {
        let cached = loadFromCache()
        let cacheValid = cached.map {
            !isStale($0) && $0.version == RunningFormBaseline.currentVersion
        } ?? false

        #if DEBUG
        if cacheValid && !forceRecompute, let c = cached {
            print("[Baseline] 캐시 사용 (계산일: \(c.computedAt), bands=\(c.bands.count))")
            memo = .some(c)
            return c
        }
        let reason: String
        if forceRecompute {
            reason = "강제 재계산 (forceRecompute=true)"
        } else if cached == nil {
            reason = "캐시 없음"
        } else if let c = cached, c.version != RunningFormBaseline.currentVersion {
            reason = "버전 불일치 v\(c.version) → v\(RunningFormBaseline.currentVersion)"
        } else {
            reason = "만료 (7일 초과)"
        }
        print("[Baseline] 재계산 시작 — \(reason)")
        #else
        if cacheValid, let c = cached { memo = .some(c); return c }
        #endif

        let baseline = compute(from: inputs)
        saveToCache(baseline)
        return baseline
    }

    // MARK: Private — Cutoffs

    /// 개인 페이스 분포로 구간 경계 산출.
    /// 25/50/75 → 40/60/80 → 2구간 순으로 시도하며, 어느 구간도 70% 미만일 때 성공.
    /// 20회 미만이면 단일 구간.
    /// ⚠️ 반드시 12개월 전체 페이스 배열로 호출 — 6개월 부분 집합 금지.
    private static func computeCutoffs(from paces: [Double]) -> PaceBandCutoffs {
        guard paces.count >= 20 else {
            // 표본 부족 → 단일 구간 (모두 .jog 으로)
            return PaceBandCutoffs(jogMax: .greatestFiniteMagnitude, jogMin: 0, dailyMin: 0, tempoMin: 0,
                                   mergedBands: [.daily, .tempo, .fast])
        }

        let sorted = paces.sorted()

        // 1차: 25/50/75 백분위
        if let c = tryCutoffs(sorted: sorted, lo: 0.25, mid: 0.50, hi: 0.75) { return c }

        // 2차: 40/60/80 백분위 (20/40/60/80 상위 3개 경계)
        if let c = tryCutoffs(sorted: sorted, lo: 0.40, mid: 0.60, hi: 0.80) { return c }

        // 최종 폴백: 중앙값 기준 2구간 (느림/빠름)
        let median = percentile(sorted, 0.50)
        let jogMax = computeJogMax(sortedAll: sorted, jogMin: median)
        #if DEBUG
        print("  [Baseline] 2구간 폴백 — 페이스 분포가 너무 좁음")
        #endif
        return PaceBandCutoffs(jogMax: jogMax, jogMin: median, dailyMin: median, tempoMin: median,
                               mergedBands: [.daily, .tempo])
    }

    /// jog 구간 페이스(≥jogMin)의 중앙값+1.2SD → jogMax.
    private static func computeJogMax(sortedAll: [Double], jogMin: Double) -> Double {
        let jogPaces = sortedAll.filter { $0 >= jogMin }
        guard jogPaces.count >= 3 else { return .greatestFiniteMagnitude }
        let med  = percentile(jogPaces, 0.50)
        let mean = jogPaces.reduce(0, +) / Double(jogPaces.count)
        let sd   = sqrt(jogPaces.map { pow($0 - mean, 2) }.reduce(0, +) / Double(jogPaces.count))
        return med + 1.2 * sd
    }

    /// 지정 백분위 3개로 경계 시도.
    /// 4구간(verySlow 분리 전) 중 어느 구간도 70% 이상을 차지하지 않아야 성공.
    private static func tryCutoffs(sorted: [Double], lo: Double, mid: Double, hi: Double) -> PaceBandCutoffs? {
        let pLo  = percentile(sorted, lo)
        let pMid = percentile(sorted, mid)
        let pHi  = percentile(sorted, hi)

        // 균형 검증: verySlow 분리 전 4구간 기준
        let n = Double(sorted.count)
        var bandCounts: [PaceBand: Int] = [:]
        for pace in sorted {
            let b: PaceBand = pace >= pHi ? .jog : (pace >= pMid ? .daily : (pace >= pLo ? .tempo : .fast))
            bandCounts[b, default: 0] += 1
        }
        #if DEBUG
        let _pct: (PaceBand) -> Int = { Int(Double(bandCounts[$0] ?? 0) / n * 100 + 0.5) }
        print("  [Baseline] 시도(\(Int(lo*100))/\(Int(mid*100))/\(Int(hi*100))%): \(PaceBand.jog.rawValue) \(_pct(.jog))% \(PaceBand.daily.rawValue) \(_pct(.daily))% \(PaceBand.tempo.rawValue) \(_pct(.tempo))% \(PaceBand.fast.rawValue) \(_pct(.fast))%")
        #endif
        for (_, count) in bandCounts where Double(count) / n >= 0.70 {
            return nil
        }
        let jogMax = computeJogMax(sortedAll: sorted, jogMin: pHi)
        return PaceBandCutoffs(jogMax: jogMax, jogMin: pHi, dailyMin: pMid, tempoMin: pLo, mergedBands: [])
    }

    // MARK: Private — Statistics

    private static func formStat(_ rawVals: [Double]) -> FormStat? {
        let vals = trimOutliers(rawVals)
        guard vals.count >= 2 else { return nil }
        let sorted = vals.sorted()
        let median = sorted[sorted.count / 2]
        let mean   = vals.reduce(0, +) / Double(vals.count)
        let sd     = sqrt(vals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(vals.count))
        return FormStat(median: median, sd: sd, count: vals.count)
    }

    private static func pearsonR(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 2 else { return nil }
        let n  = Double(xs.count)
        let xm = xs.reduce(0, +) / n
        let ym = ys.reduce(0, +) / n
        let num = zip(xs, ys).reduce(0.0) { $0 + ($1.0 - xm) * ($1.1 - ym) }
        let dx  = sqrt(xs.map { pow($0 - xm, 2) }.reduce(0, +))
        let dy  = sqrt(ys.map { pow($0 - ym, 2) }.reduce(0, +))
        guard dx > 0, dy > 0 else { return nil }
        return num / (dx * dy)
    }

    /// 1~99 백분위 밖 제거 — GPS 오류·정지 구간 극단값 방지.
    private static func trimOutliers(_ vals: [Double]) -> [Double] {
        guard vals.count >= 4 else { return vals }
        let sorted = vals.sorted()
        let n = sorted.count
        let loIdx = Int((Double(n - 1) * 0.01).rounded())
        let hiIdx = Int((Double(n - 1) * 0.99).rounded())
        let lo = sorted[loIdx]; let hi = sorted[hiIdx]
        return vals.filter { $0 >= lo && $0 <= hi }
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard sorted.count > 1 else { return sorted[0] }
        let idx  = p * Double(sorted.count - 1)
        let lo   = Int(idx)
        let hi   = min(lo + 1, sorted.count - 1)
        let frac = idx - Double(lo)
        return sorted[lo] * (1 - frac) + sorted[hi] * frac
    }

    // MARK: Private — Cache

    private static func loadFromCache() -> RunningFormBaseline? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(RunningFormBaseline.self, from: data)
    }

    private static func saveToCache(_ baseline: RunningFormBaseline) {
        guard let data = try? JSONEncoder().encode(baseline) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        memo = .some(baseline)
    }

    private static func isStale(_ baseline: RunningFormBaseline) -> Bool {
        Date().timeIntervalSince(baseline.computedAt) > cacheTTL
    }
}

// MARK: - Query API

extension RunningFormBaseline {
    func band(for activity: Activity) -> PaceBand {
        guard let pace = activity.paceSecPerKm else { return .jog }
        return cutoffs.band(of: pace)
    }

    func baseline(for activity: Activity) -> BandBaseline? {
        bands[band(for: activity)]
    }

    /// 케이던스 권장 밴드.
    /// 개인 lower < 160 이면 160을 absoluteWarning으로 추가 반환.
    func cadenceBand(for activity: Activity)
        -> (lower: Double, upper: Double, absoluteWarning: Double?) {
        guard let bb = baseline(for: activity), let cad = bb.cadence else {
            return (160, 180, nil)  // 기준선 없으면 연구 기본값
        }
        let warning: Double? = cad.lower < 160 ? 160 : nil
        return (cad.lower, cad.upper, warning)
    }
}

// MARK: - Debug

#if DEBUG
extension FormBaselineEngine {

    static func logBaseline(_ b: RunningFormBaseline) {
        func pf(_ s: Double) -> String {
            guard s < .greatestFiniteMagnitude / 2 else { return "∞" }
            return String(format: "%d'%02d\"", Int(s) / 60, Int(s) % 60)
        }
        let c = b.cutoffs
        print("═══ [Baseline] \(b.computedAt) ═══")
        print("구간 경계: \(PaceBand.fast.rawValue) <\(pf(c.tempoMin)) | \(PaceBand.tempo.rawValue) <\(pf(c.dailyMin)) | \(PaceBand.daily.rawValue) <\(pf(c.jogMin)) | \(PaceBand.jog.rawValue) \(pf(c.jogMin))–\(pf(c.jogMax)) | \(PaceBand.verySlow.rawValue) ≥\(pf(c.jogMax))")
        if !c.mergedBands.isEmpty { print("병합된 구간: \(c.mergedBands.map(\.rawValue))") }

        for band in PaceBand.allCases {
            guard let bb = b.bands[band] else { print("\(band.rawValue): 표본 부족"); continue }
            print("── \(band.rawValue) (\(bb.sampleCount)회 / \(bb.windowMonths)개월) 페이스 \(pf(bb.paceRange.lowerBound))~\(pf(bb.paceRange.upperBound)) ──")
            func p(_ label: String, _ s: FormStat?, _ f: String) {
                guard let s else { return }
                print("  \(label): 중앙 \(String(format: f, s.median)) SD \(String(format: f, s.sd)) 범위 \(String(format: f, s.lower))~\(String(format: f, s.upper)) (n=\(s.count))")
            }
            p("케이던스", bb.cadence,      "%.1f")
            p("보폭    ", bb.strideLength,  "%.3f")
            p("지면접촉", bb.groundContact, "%.1f")
            p("수직진폭", bb.verticalOsc,   "%.2f")
            p("심박    ", bb.heartRate,     "%.1f")
            if let r = bb.cadenceStrideR {
                let rStr  = String(format: "%.3f", r)
                let p10c  = bb.cadenceResidualP10.map { String(format: "%+.1f", $0) } ?? "-"
                let p90c  = bb.cadenceResidualP90.map { String(format: "%+.1f", $0) } ?? "-"
                let p10s  = bb.strideResidualP10.map  { String(format: "%+.3f", $0) } ?? "-"
                let p90s  = bb.strideResidualP90.map  { String(format: "%+.3f", $0) } ?? "-"
                print("  [주법] r=\(rStr) cadR P10=\(p10c) P90=\(p90c) strR P10=\(p10s) P90=\(p90s)")
            }
        }
    }
}
#endif
