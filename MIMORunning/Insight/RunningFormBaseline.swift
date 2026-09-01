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
    let jogMax: Double       // jog 구간 상한 (중앙값+1.2SD). 이 값 이상 = verySlow
    let verySlowMax: Double  // verySlow 상한 (중앙값+1.5SD). 이 값 초과 = 비교 대상 없음(nil)
    let fastMin: Double      // fast 하한 (중앙값-1.5SD). 이 값 미만 = 비교 대상 없음(nil)
    let jogMin: Double       // 75th percentile — 이 값 이상 = jog 또는 verySlow
    let dailyMin: Double     // 50th percentile — 이 값 이상 = daily
    let tempoMin: Double     // 25th percentile — 이 값 이상 = tempo, 미만 = fast
    let mergedBands: [PaceBand]  // 병합되어 사라진 구간 (gap < 30s)

    /// nil = 범위 밖 (비교 대상 없음 — 폼 판정 생략)
    func band(of pace: Double) -> PaceBand? {
        if pace > verySlowMax  { return nil }
        if fastMin > 0, pace < fastMin { return nil }
        if pace >= jogMax      { return .verySlow }
        if pace >= jogMin      { return .jog }
        if pace >= dailyMin    { return .daily }
        if pace >= tempoMin    { return .tempo }
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
    let p10: Double?   // 관측 P10 (표본 < 15건 띠에 사용)
    let p90: Double?
    var lower: Double { median - 1.2 * sd }
    var upper: Double { median + 1.2 * sd }
}

/// 범위 바 히스토리 점용 경량 샘플.
struct BandDotSample: Codable {
    let date: Date
    let distanceM: Double
    let paceSecPerKm: Double   // 페이스 구간 필터링용
    let cadence: Int?
    let strideLength: Double?
    let groundContactTime: Double?
    let verticalOscillation: Double?
}

struct BandBaseline: Codable {
    let band: PaceBand
    let isJudgeable: Bool        // 표본 기준(minSamples) 충족 여부
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
    let recentSamples: [BandDotSample]  // 최신 20건 — 범위 바 점 표시용

    var paceRange: ClosedRange<Double> { paceMin...paceMax }
}

// MARK: - Cadence-HR U-Curve Diagnostic

/// 케이던스–심박 U자 곡선 진단 데이터. baseline 계산 시 항상 저장(글로벌 조건 불충족 포함).
/// vertexResidual != nil ↔ 모든 글로벌 조건 충족 → 뷰에서 퍼액티비티 조건만 추가 검사.
struct CadenceHRCurveDiag: Codable {
    let residualRangeP10P90: Double   // P90-P10 of cadence residuals
    let binCount: Int                 // bins with ≥3 samples
    let a: Double?                    // 2차 계수 (nil = 회귀 미수행)
    let r2: Double?                   // R² (nil = 회귀 미수행)
    let vertexResidual: Double?       // -b/(2a), nil = 글로벌 조건 미충족
    let residualDataMin: Double?      // 외삽 방지용 잔차 최솟값
    let residualDataMax: Double?      // 외삽 방지용 잔차 최댓값

    var isGloballyValid: Bool { vertexResidual != nil }
}

struct RunningFormBaseline: Codable {
    static let currentVersion = 15  // allFormSamples: 전체 폼 히스토리 풀 추가
    let version: Int
    let computedAt: Date
    let cutoffs: PaceBandCutoffs
    let bands: [PaceBand: BandBaseline]
    let cadenceHRDiag: CadenceHRCurveDiag?
    var isEmpty: Bool { bands.isEmpty }
    // GCT 시점 보정용 — baseline 계산 시점의 GCT 잔차 3개월 평균
    let gctBaselineResidualMean: Double?
    // 범위 바 후보 풀 — 전체 폼 히스토리 (날짜·페이스·거리 필터링은 뷰에서)
    let allFormSamples: [BandDotSample]
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
    let activityID: UUID
    let date: Date
    let paceSecPerKm: Double
    let distanceM: Double
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
        self.activityID             = activity.id
        self.date                   = activity.date
        self.paceSecPerKm           = pace
        self.distanceM              = activity.distance
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
        self.activityID             = activity.id
        self.date                   = activity.date
        self.paceSecPerKm           = pace
        self.distanceM              = activity.distance
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

    static func compute(from inputs: [FormInput],
                        excludedRaceInputs: [FormInput] = []) -> RunningFormBaseline {
        #if DEBUG
        print("[Baseline:계산] 입력 FormInput 총 \(inputs.count)개")
        if !excludedRaceInputs.isEmpty {
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            func pf(_ s: Double) -> String { String(format: "%d'%02d\"", Int(s)/60, Int(s)%60) }
            let desc = excludedRaceInputs.map { "\(df.string(from: $0.date))(\(pf($0.paceSecPerKm)))" }.joined(separator: " · ")
            print("[Baseline:계산] 대회 제외 \(excludedRaceInputs.count)건 = \(desc)")
        }
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
        // 아주 느림 행방 추적 — jogMax-verySlowMax 범위 내 표본 수와 상한 초과 제외 건수를 기록
        func _pfPace(_ s: Double) -> String {
            guard s < .greatestFiniteMagnitude / 2 else { return "∞" }
            return String(format: "%d'%02d\"", Int(s) / 60, Int(s) % 60)
        }
        if cutoffs.mergedBands.contains(.verySlow) {
            print("[Baseline] 아주 느림 — 병합됨 (느린 편과 경계 차이 <30초)")
        } else if cutoffs.activeBands.contains(.verySlow) {
            let _vsInRange = all12.filter { $0.paceSecPerKm >= cutoffs.jogMax && $0.paceSecPerKm <= cutoffs.verySlowMax }
            let _vsAbove   = all12.filter { $0.paceSecPerKm > cutoffs.verySlowMax }
            if _vsInRange.count < minSamples {
                print("[Baseline] 아주 느림 — 범위(\(_pfPace(cutoffs.jogMax))–\(_pfPace(cutoffs.verySlowMax))) 내 \(_vsInRange.count)건 (최소 \(minSamples)건 미달) · 상한 초과 \(_vsAbove.count)건 제외")
            } else {
                print("[Baseline] 아주 느림 — 범위 내 \(_vsInRange.count)건 OK · 상한(\(_pfPace(cutoffs.verySlowMax))) 초과 \(_vsAbove.count)건 제외")
            }
        }
        #endif

        var bands: [PaceBand: BandBaseline] = [:]

        for band in cutoffs.activeBands {
            // 적응형 기간
            let samples6  = all12.filter { $0.date >= window6  && cutoffs.band(of: $0.paceSecPerKm) == band }
            let samples12 = all12.filter {                         cutoffs.band(of: $0.paceSecPerKm) == band }

            let (samples, windowMonths, isJudgeable): ([FormInput], Int, Bool)
            if samples6.count >= minSamples {
                (samples, windowMonths, isJudgeable) = (samples6, 6, true)
            } else if samples12.count >= minSamples {
                (samples, windowMonths, isJudgeable) = (samples12, 12, true)
            } else if !samples12.isEmpty {
                // 표본 부족 — 띠는 표시하되 판정은 생략
                (samples, windowMonths, isJudgeable) = (samples12, 12, false)
            } else {
                continue
            }

            #if DEBUG
            let excludedInBand = excludedRaceInputs.filter { cutoffs.band(of: $0.paceSecPerKm) == band }.count
            let excStr = excludedInBand > 0 ? ", 대회 \(excludedInBand)건 제외" : ""
            let judgeStr = isJudgeable ? "" : " · 판정불가"
            print("── \(band.rawValue) (\(samples.count)회 / \(windowMonths)개월\(excStr)\(judgeStr)) ──")
            #endif
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

            let recentSamples: [BandDotSample] = samples
                .sorted { $0.date > $1.date }
                .prefix(20)
                .map { inp in BandDotSample(date: inp.date, distanceM: inp.distanceM,
                                            paceSecPerKm: inp.paceSecPerKm,
                                            cadence: inp.avgCadence, strideLength: inp.avgStrideLength,
                                            groundContactTime: inp.avgGroundContactTime,
                                            verticalOscillation: inp.avgVerticalOscillation) }
            bands[band] = BandBaseline(
                band:         band,
                isJudgeable:  isJudgeable,
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
                strideResidualP90:  strideResidualP90,
                recentSamples:      recentSamples
            )
        }

        let curveDiag = computeCadenceHRCurve(inputs: all12, cutoffs: cutoffs, bands: bands)

        // GCT 잔차 기준값 — 보정 게이트: 25개 이상 + 최근 3개월 20개 이상
        let gctBaselineResidualMean: Double? = {
            let gctObs: [MRFormObs] = all12.compactMap { inp in
                guard let gct = inp.avgGroundContactTime else { return nil }
                return MRFormObs(date: inp.date, speedMPerMin: 60000.0 / inp.paceSecPerKm, metricValue: gct)
            }
            guard gctObs.count >= 25 else { return nil }
            let residuals = mrFormResiduals(obs: gctObs, asOf: now)
            guard !residuals.isEmpty else { return nil }
            let cal = Calendar.current
            let cutoff = cal.startOfDay(for: now)
            let recent = residuals.filter {
                let d = cal.dateComponents([.day], from: $0.date, to: cutoff).day ?? 999
                return d >= 0 && d < 90
            }
            guard recent.count >= 20 else { return nil }
            let mean = recent.map(\.value).reduce(0, +) / Double(recent.count)
            #if DEBUG
            print(String(format: "[Baseline:GCT기준] 최근 3개월 %d개 · 잔차 평균 %+.2f", recent.count, mean))
            #endif
            return mean
        }()

        // 범위 바 후보 풀: 전체 입력에서 케이던스 있는 것, 날짜 내림차순 500건
        let allFormSamples: [BandDotSample] = inputs
            .filter { $0.avgCadence != nil }
            .sorted { $0.date > $1.date }
            .prefix(500)
            .map { inp in BandDotSample(date: inp.date, distanceM: inp.distanceM,
                                        paceSecPerKm: inp.paceSecPerKm,
                                        cadence: inp.avgCadence, strideLength: inp.avgStrideLength,
                                        groundContactTime: inp.avgGroundContactTime,
                                        verticalOscillation: inp.avgVerticalOscillation) }
        #if DEBUG
        print("[Baseline:계산] allFormSamples \(allFormSamples.count)건 (전체 입력 \(inputs.count)건 중)")
        #endif

        let result = RunningFormBaseline(version: RunningFormBaseline.currentVersion,
                                         computedAt: now, cutoffs: cutoffs, bands: bands,
                                         cadenceHRDiag: curveDiag,
                                         gctBaselineResidualMean: gctBaselineResidualMean,
                                         allFormSamples: allFormSamples)
        #if DEBUG
        let _pf: (Double) -> String = { s in
            guard s < Double.greatestFiniteMagnitude / 2 else { return "∞" }
            return String(format: "%d'%02d\"", Int(s) / 60, Int(s) % 60)
        }
        let _activeNames = PaceBand.allCases.compactMap { result.bands[$0] != nil ? $0.rawValue : nil }
        let _aboveMax = all12.filter { $0.paceSecPerKm > result.cutoffs.verySlowMax }.count
        let _vsStr = result.cutoffs.verySlowMax < Double.greatestFiniteMagnitude / 2
            ? "아주 느림 상한 \(_pf(result.cutoffs.verySlowMax)) · 상한 밖 \(_aboveMax)건 제외"
            : ""
        let _noSampleBands = result.cutoffs.activeBands.filter { result.bands[$0] == nil }.map(\.rawValue)
        let _noSamplesStr = _noSampleBands.isEmpty ? "" : " · 표본 없음: \(_noSampleBands.joined(separator: ","))"
        let _unjudgeableBands = PaceBand.allCases.compactMap { b in
            result.bands[b].flatMap { !$0.isJudgeable ? "\($0.band.rawValue)(n=\($0.sampleCount))" : nil }
        }
        let _unjudgeStr = _unjudgeableBands.isEmpty ? "" : " · 판정불가: \(_unjudgeableBands.joined(separator: ","))"
        let _mergedStr = result.cutoffs.mergedBands.isEmpty ? "" : " · 병합: \(result.cutoffs.mergedBands.map(\.rawValue).joined(separator: ","))"
        let _detail = [_vsStr, _noSamplesStr, _unjudgeStr, _mergedStr].filter { !$0.isEmpty }.joined(separator: "")
        print("[Baseline:계산] 구간 \(result.bands.count)개 (\(_activeNames.joined(separator: " · "))" + (_detail.isEmpty ? ")" : ") | \(_detail)"))
        logBaseline(result)
        #endif
        return result
    }

    // MARK: Load or Compute

    static func loadOrCompute(inputs: [FormInput],
                               excludedRaceInputs: [FormInput] = []) async -> RunningFormBaseline {
        let cached = loadFromCache()
        let cacheValid = cached.map {
            !isStale($0) && $0.version == RunningFormBaseline.currentVersion
        } ?? false

        #if DEBUG
        if cacheValid && !forceRecompute, let c = cached {
            print("[Baseline] 캐시 사용 (계산일: \(c.computedAt), bands=\(c.bands.count))")
            let _pf: (Double) -> String = { s in
                guard s < .greatestFiniteMagnitude / 2 else { return "∞" }
                return String(format: "%d'%02d\"", Int(s)/60, Int(s)%60)
            }
            let _list = PaceBand.allCases.compactMap { b in
                c.bands[b].map { "\(b.rawValue)(n=\($0.sampleCount)\($0.isJudgeable ? "" : "·불가"))" }
            }.joined(separator: " / ")
            print("[Baseline] 구간 \(c.bands.count)개: \(_list) | 아주 느림 상한 = \(_pf(c.cutoffs.verySlowMax))")
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

        let baseline = compute(from: inputs, excludedRaceInputs: excludedRaceInputs)
        saveToCache(baseline)
        return baseline
    }

    // MARK: Private — Cadence-HR U-Curve

    /// 12개월 러닝 전체를 페이스 구간 잔차로 변환한 뒤 2차 회귀로 심박 최저 케이던스를 추정.
    /// 표시 조건을 하나라도 충족 못 하면 vertexResidual = nil로 반환(CadenceHRCurveDiag는 항상 반환해 로그에 사용).
    /// 케이던스·심박 모두 없는 경우에만 nil 반환.
    private static func computeCadenceHRCurve(
        inputs: [FormInput],
        cutoffs: PaceBandCutoffs,
        bands: [PaceBand: BandBaseline]
    ) -> CadenceHRCurveDiag? {
        // 케이던스 + 심박 둘 다 있는 기록만
        let eligible = inputs.filter { $0.avgCadence != nil && $0.avgHeartRate != nil }
        guard eligible.count >= 10 else {
            #if DEBUG
            print("[U자:계산] 데이터 부족 (\(eligible.count)개 케이던스+심박) → 진단 없음")
            #endif
            return nil
        }

        // 페이스 구간 중앙값으로 잔차 계산
        var cadResiduals: [Double] = []
        var hrResiduals:  [Double] = []
        for inp in eligible {
            guard let band = cutoffs.band(of: inp.paceSecPerKm),
                  let bb   = bands[band],
                  let cs   = bb.cadence,
                  let hs   = bb.heartRate,
                  let cad  = inp.avgCadence,
                  let hr   = inp.avgHeartRate else { continue }
            cadResiduals.append(Double(cad) - cs.median)
            hrResiduals.append(Double(hr)  - hs.median)
        }

        guard cadResiduals.count >= 10 else {
            #if DEBUG
            print("[U자:계산] 잔차 계산 후 데이터 부족 (\(cadResiduals.count)개) → 진단 없음")
            #endif
            return nil
        }

        let cadSorted = cadResiduals.sorted()
        let p10 = percentile(cadSorted, 0.10)
        let p90 = percentile(cadSorted, 0.90)
        let range = p90 - p10

        // 2spm bin: binIdx = floor(cr/2), center = binIdx*2 + 1
        var binDict: [Int: [Double]] = [:]
        for (i, cr) in cadResiduals.enumerated() {
            let binIdx = Int(floor(cr / 2.0))
            binDict[binIdx, default: []].append(hrResiduals[i])
        }
        let validBins = binDict.filter { $0.value.count >= 3 }
        let binCount  = validBins.count

        let rangeOK = range >= 10
        let binsOK  = binCount >= 5

        #if DEBUG
        var logParts = "[U자:계산] 잔차범위 \(String(format: "%.1f", range))spm(\(rangeOK ? "✓" : "<10 ✗")) bin=\(binCount)(\(binsOK ? "✓" : "<5 ✗"))"
        #endif

        guard rangeOK, binsOK else {
            #if DEBUG
            var reasons: [String] = []
            if !rangeOK { reasons.append("잔차범위 부족") }
            if !binsOK  { reasons.append("bin 부족") }
            print("\(logParts) → 미표시: \(reasons.joined(separator: ", "))")
            #endif
            return CadenceHRCurveDiag(residualRangeP10P90: range, binCount: binCount,
                                      a: nil, r2: nil, vertexResidual: nil,
                                      residualDataMin: nil, residualDataMax: nil)
        }

        // 2차 회귀: y = a·x² + b·x + c, X 열 = [x², x, 1]
        let sorted = validBins.sorted { $0.key < $1.key }
        let xs = sorted.map { Double($0.key) * 2.0 + 1.0 }
        let ys = sorted.map { pair in pair.value.reduce(0, +) / Double(pair.value.count) }

        let X = xs.map { x in [x * x, x, 1.0] }
        guard let coef = MRLinAlg.lstsq(X: X, y: ys), coef.count == 3 else {
            #if DEBUG
            print("\(logParts) 회귀 실패 → 미표시")
            #endif
            return CadenceHRCurveDiag(residualRangeP10P90: range, binCount: binCount,
                                      a: nil, r2: nil, vertexResidual: nil,
                                      residualDataMin: nil, residualDataMax: nil)
        }
        let a = coef[0], b = coef[1], c = coef[2]

        // R²
        let yMean = ys.reduce(0, +) / Double(ys.count)
        let ssTot = ys.map { pow($0 - yMean, 2) }.reduce(0, +)
        let ssRes = zip(xs, ys).map { x, y in pow(y - (a * x * x + b * x + c), 2) }.reduce(0, +)
        let r2 = ssTot > 1e-12 ? 1.0 - ssRes / ssTot : 0.0

        let aOK  = a > 0
        let r2OK = r2 >= 0.3

        #if DEBUG
        logParts += " a=\(String(format: "%+.2f", a))(\(aOK ? "✓" : "✗")) R²=\(String(format: "%.2f", r2))(\(r2OK ? "✓" : "<0.3 ✗"))"
        #endif

        guard aOK, r2OK else {
            #if DEBUG
            var reasons: [String] = []
            if !aOK  { reasons.append("아래로 볼록 아님") }
            if !r2OK { reasons.append("R² 부족") }
            print("\(logParts) → 미표시: \(reasons.joined(separator: ", "))")
            #endif
            return CadenceHRCurveDiag(residualRangeP10P90: range, binCount: binCount,
                                      a: a, r2: r2, vertexResidual: nil,
                                      residualDataMin: nil, residualDataMax: nil)
        }

        let vertex   = -b / (2.0 * a)
        let dataMin  = cadResiduals.min() ?? vertex
        let dataMax  = cadResiduals.max() ?? vertex
        let inRange  = vertex >= dataMin && vertex <= dataMax

        #if DEBUG
        logParts += " 최저점 \(String(format: "%+.1f", vertex))spm(\(inRange ? "✓" : "외삽 ✗"))"
        #endif

        guard inRange else {
            #if DEBUG
            print("\(logParts) → 미표시: 외삽")
            #endif
            return CadenceHRCurveDiag(residualRangeP10P90: range, binCount: binCount,
                                      a: a, r2: r2, vertexResidual: nil,
                                      residualDataMin: dataMin, residualDataMax: dataMax)
        }

        #if DEBUG
        print("\(logParts) → 글로벌 조건 충족")
        #endif
        return CadenceHRCurveDiag(residualRangeP10P90: range, binCount: binCount,
                                  a: a, r2: r2, vertexResidual: vertex,
                                  residualDataMin: dataMin, residualDataMax: dataMax)
    }

    // MARK: Private — Cutoffs

    /// 개인 페이스 분포로 구간 경계 산출.
    /// 25/50/75 → 40/60/80 → 2구간 순으로 시도하며, 어느 구간도 70% 미만일 때 성공.
    /// 20회 미만이면 단일 구간.
    /// ⚠️ 반드시 12개월 전체 페이스 배열로 호출 — 6개월 부분 집합 금지.
    private static func computeCutoffs(from paces: [Double]) -> PaceBandCutoffs {
        guard paces.count >= 20 else {
            // 표본 부족 → 단일 구간 (모두 .jog 으로)
            return PaceBandCutoffs(jogMax: .greatestFiniteMagnitude, verySlowMax: .greatestFiniteMagnitude,
                                   fastMin: 0, jogMin: 0, dailyMin: 0, tempoMin: 0,
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
        let verySlowMax = computeVerySlowMax(sortedAll: sorted, jogMax: jogMax)
        let fastMin     = computeFastMin(sortedAll: sorted, tempoMin: median)
        #if DEBUG
        print("  [Baseline] 2구간 폴백 — 페이스 분포가 너무 좁음")
        #endif
        return PaceBandCutoffs(jogMax: jogMax, verySlowMax: verySlowMax,
                               fastMin: fastMin, jogMin: median, dailyMin: median, tempoMin: median,
                               mergedBands: [.daily, .tempo])
    }

    /// verySlow 구간(≥jogMax)의 중앙값+1.5SD → verySlowMax.
    /// 샘플 < 3이면 상한 없음(greatestFiniteMagnitude).
    private static func computeVerySlowMax(sortedAll: [Double], jogMax: Double) -> Double {
        let vsPaces = sortedAll.filter { $0 >= jogMax }
        guard vsPaces.count >= 3 else { return .greatestFiniteMagnitude }
        let mean = vsPaces.reduce(0, +) / Double(vsPaces.count)
        let sd   = sqrt(vsPaces.map { pow($0 - mean, 2) }.reduce(0, +) / Double(vsPaces.count))
        let med  = percentile(vsPaces, 0.50)
        let result = med + 1.5 * sd
        #if DEBUG
        func pf(_ s: Double) -> String { String(format: "%d'%02d\"", Int(s)/60, Int(s)%60) }
        print("[Baseline] 아주 느림 상한 = \(pf(result)) (중앙 \(pf(med)) + 1.5SD \(String(format: "%.0f", sd))초)")
        #endif
        return result
    }

    /// fast 구간(＜tempoMin)의 중앙값-1.5SD → fastMin.
    /// 샘플 < 3이면 하한 없음(0).
    private static func computeFastMin(sortedAll: [Double], tempoMin: Double) -> Double {
        let fastPaces = sortedAll.filter { $0 < tempoMin }
        guard fastPaces.count >= 3 else { return 0 }
        let mean = fastPaces.reduce(0, +) / Double(fastPaces.count)
        let sd   = sqrt(fastPaces.map { pow($0 - mean, 2) }.reduce(0, +) / Double(fastPaces.count))
        let med  = percentile(fastPaces, 0.50)
        let result = max(0, med - 1.5 * sd)
        #if DEBUG
        func pf(_ s: Double) -> String { String(format: "%d'%02d\"", Int(s)/60, Int(s)%60) }
        if result > 0 {
            print("[Baseline] 가장 빠른 하한 = \(pf(result)) (중앙 \(pf(med)) - 1.5SD \(String(format: "%.0f", sd))초)")
        }
        #endif
        return result
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
        let jogMax      = computeJogMax(sortedAll: sorted, jogMin: pHi)
        let verySlowMax = computeVerySlowMax(sortedAll: sorted, jogMax: jogMax)
        let fastMin     = computeFastMin(sortedAll: sorted, tempoMin: pLo)
        return PaceBandCutoffs(jogMax: jogMax, verySlowMax: verySlowMax,
                               fastMin: fastMin, jogMin: pHi, dailyMin: pMid, tempoMin: pLo, mergedBands: [])
    }

    // MARK: Private — Statistics

    private static func formStat(_ rawVals: [Double]) -> FormStat? {
        let vals = trimOutliers(rawVals)
        guard vals.count >= 2 else { return nil }
        let sorted = vals.sorted()
        let median = sorted[sorted.count / 2]
        let mean   = vals.reduce(0, +) / Double(vals.count)
        let sd     = sqrt(vals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(vals.count))
        let p10 = percentile(sorted, 0.10)
        let p90 = percentile(sorted, 0.90)
        return FormStat(median: median, sd: sd, count: vals.count, p10: p10, p90: p90)
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
    func band(for activity: Activity) -> PaceBand? {
        guard let pace = activity.paceSecPerKm else { return .jog }
        return cutoffs.band(of: pace)
    }

    func baseline(for activity: Activity) -> BandBaseline? {
        guard let b = band(for: activity) else { return nil }
        return bands[b]
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
        let vsMax = c.verySlowMax < .greatestFiniteMagnitude ? "~\(pf(c.verySlowMax))" : "∞"
        print("구간 경계: \(PaceBand.fast.rawValue) <\(pf(c.tempoMin)) | \(PaceBand.tempo.rawValue) <\(pf(c.dailyMin)) | \(PaceBand.daily.rawValue) <\(pf(c.jogMin)) | \(PaceBand.jog.rawValue) \(pf(c.jogMin))–\(pf(c.jogMax)) | \(PaceBand.verySlow.rawValue) \(pf(c.jogMax))\(vsMax) | 범위밖 >\(vsMax)")
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
        if let d = b.cadenceHRDiag {
            let rangeOK = d.residualRangeP10P90 >= 10
            let binsOK  = d.binCount >= 5
            var line = "── [U자] 잔차범위 \(String(format: "%.1f", d.residualRangeP10P90))spm(\(rangeOK ? "✓" : "<10 ✗")) bin=\(d.binCount)(\(binsOK ? "✓" : "<5 ✗"))"
            if let a = d.a, let r2 = d.r2 {
                line += " a=\(String(format: "%+.2f", a))(\(a > 0 ? "✓" : "✗")) R²=\(String(format: "%.2f", r2))(\(r2 >= 0.3 ? "✓" : "<0.3 ✗"))"
            }
            if let v = d.vertexResidual {
                line += " 최저점 \(String(format: "%+.1f", v))spm → 글로벌 조건 충족"
            } else {
                line += " → 글로벌 조건 미충족"
            }
            print(line)
        } else {
            print("── [U자] 진단 없음 (케이던스+심박 데이터 부족)")
        }
    }
}
#endif
