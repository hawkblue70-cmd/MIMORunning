import Foundation

#if DEBUG

// MARK: - 개인 속도-폼 곡선 검증 (DEBUG 전용)
//
// 설계: docs/superpowers/specs/2026-10-21-form-speed-curve-validation.md
// 페이스 구간 기준선(FormBaselineEngine)을 개인 속도→폼 연속 곡선으로 바꿀 가치가 있는지
// 본인 데이터로 판정한다. 판정·UI·캐시는 건드리지 않고 콘솔에 [곡선검증] 표만 낸다.
// 건강 데이터는 파일·iCloud로 내보내지 않는다.
//
// ⚠ 2차식 외삽 금지 — 관측 속도 범위 밖은 끝값으로 고정 (MRLinAlg 주석 참고).
// ⚠ 인터벌 제외는 하지 않는다. FormInput에 운동 유형이 없고, 구간 기준선도 같은 입력을 쓰므로
//   두 모델을 같은 데이터로 비교하는 쪽을 택했다.
// ⚠ walk-forward의 구간 경계(cutoffs)는 현재 기준선 것을 그대로 쓴다 — 경계는 페이스 분포만으로
//   정해져 폼 값 누설은 없다. 구간 통계(중앙값·SD)는 그 러닝 이전 기록만으로 다시 계산한다.

/// 검증용 경량 샘플. 테스트에서 직접 만들 수 있게 FormInput과 분리했다.
struct FormCurveSample {
    let date: Date
    /// 실제 페이스(초/km) — 케이던스×보폭 점검·기어 비율(H3)에 쓴다(속도 = 케이던스 × 보폭은 실제 속도 기준).
    let paceSecPerKm: Double
    /// 경사 조정 페이스 우선(초/km) — 구간 분류·곡선(H1·H2)에 쓴다. 구간 기준선과 같은 조건.
    let effectivePaceSecPerKm: Double
    let cadence: Double?
    let stride: Double?
    let gct: Double?
    let vo: Double?
    /// H5 부하 비율용 (0 = 모름 — 테스트용 기본값)
    var distanceM: Double = 0

    var speedMPerMin: Double { 60000.0 / paceSecPerKm }
    var effectiveSpeedMPerMin: Double { 60000.0 / effectivePaceSecPerKm }

    /// 케이던스/분 × 보폭과 실제 속도의 비율. 1에서 5% 넘게 벗어나면 케이던스·보폭 산출 이상으로 본다.
    var cadenceStrideSpeedRatio: Double? {
        guard let c = cadence, let s = stride, c > 0, s > 0 else { return nil }
        return c * s / speedMPerMin
    }
    var isCadenceStrideOutlier: Bool {
        guard let r = cadenceStrideSpeedRatio else { return false }
        return abs(r - 1) > FormCurveValidation.cadenceStrideTolerance
    }
}

extension FormCurveSample {
    init(_ input: FormInput) {
        self.init(date: input.date,
                  paceSecPerKm: input.paceSecPerKm,
                  effectivePaceSecPerKm: input.effectivePaceSecPerKm,
                  cadence: input.avgCadence.map(Double.init),
                  stride: input.avgStrideLength,
                  gct: input.avgGroundContactTime,
                  vo: input.avgVerticalOscillation,
                  distanceM: input.distanceM)
    }
}

enum FormCurveMetric: CaseIterable {
    case cadence, stride, gct, vo

    var name: String {
        switch self {
        case .cadence: return "케이던스"
        case .stride:  return "보폭"
        case .gct:     return "지면접촉"
        case .vo:      return "수직진폭"
        }
    }
    func value(_ s: FormCurveSample) -> Double? {
        switch self {
        case .cadence: return s.cadence
        case .stride:  return s.stride
        case .gct:     return s.gct
        case .vo:      return s.vo
        }
    }
    var format: String {
        switch self {
        case .cadence: return "%.1f"
        case .stride:  return "%.3f"
        case .gct:     return "%.1f"
        case .vo:      return "%.2f"
        }
    }
}

/// 출시 코드의 곡선을 그대로 쓴다 — 검증한 것과 출시하는 것이 같아야 한다.
typealias FormCurveFit = FormSpeedCurve

extension FormSpeedCurve {
    func range(speed: Double) -> ClosedRange<Double> {
        let p = predict(speed: speed)
        return (p - FormCurveValidation.bandK * residualSD)...(p + FormCurveValidation.bandK * residualSD)
    }
}

enum FormCurveVerdict: String {
    case below = "아래", inside = "범위", above = "위"
    init(_ v: Double, _ r: ClosedRange<Double>) {
        self = v < r.lowerBound ? .below : (v > r.upperBound ? .above : .inside)
    }
}

// MARK: - Report

struct FormCurveH1Metric {
    let metric: FormCurveMetric
    let n: Int
    let bandMAE: Double
    let curveMAE: Double
    let edgeN: Int
    let edgeBandMAE: Double?
    let edgeCurveMAE: Double?
    let smallN: Int
    let smallBandMAE: Double?
    let smallCurveMAE: Double?
    let bandOutRate: Double
    let curveOutRate: Double

    /// 설계 4장 — 사용자 체감 확인(엇갈린 러닝)은 별도. nil = 표본 부족(경계·작은 구간 각 3건 미만).
    var passesNumeric: Bool? {
        if curveMAE > bandMAE || curveOutRate > 0.35 { return false }
        guard let eb = edgeBandMAE, let ec = edgeCurveMAE,
              let sb = smallBandMAE, let sc = smallCurveMAE else { return nil }
        return ec <= eb * 0.9 && sc <= sb * 0.9
    }
}

struct FormCurveDisagreement {
    let date: Date
    let pace: Double
    let metric: FormCurveMetric
    let value: Double
    let bandRange: ClosedRange<Double>
    let bandVerdict: FormCurveVerdict
    let curveRange: ClosedRange<Double>
    let curveVerdict: FormCurveVerdict
}

struct FormCurveH2 {
    let n: Int
    let beta: Double        // ms / spm
    let r: Double
    let betaFirstHalf: Double?
    let betaSecondHalf: Double?
    let examples: [(date: Date, gctResid: Double, cadResid: Double)]

    var passes: Bool {
        guard abs(r) >= 0.4, let a = betaFirstHalf, let b = betaSecondHalf,
              a.sign == b.sign else { return false }
        let big = max(abs(a), abs(b))
        return big == 0 || abs(a - b) / big <= 0.5
    }
}

struct FormCurveH3 {
    let n: Int
    let paceSpreadSec: Double   // 페이스 P90 − P10 (초/km)
    let cadenceShare: Double?
    let ciLow: Double?
    let ciHigh: Double?
    let shareFirstHalf: Double?
    let shareSecondHalf: Double?

    var isJudgeable: Bool { paceSpreadSec >= FormCurveValidation.minPaceSpreadSec && cadenceShare != nil }
    var passes: Bool {
        guard isJudgeable, let lo = ciLow, let hi = ciHigh,
              let a = shareFirstHalf, let b = shareSecondHalf else { return false }
        return hi - lo <= 0.2 && abs(a - b) <= 0.15
    }
}

struct FormCurveValidationReport {
    let totalRuns: Int
    let outlierRuns: Int
    let paceP10: Double?
    let paceP90: Double?
    let h1: [FormCurveH1Metric]
    let disagreements: [FormCurveDisagreement]
    let h2: FormCurveH2?
    let h3: FormCurveH3
    let h4: [FormCurveH4Metric]
    let h4Changed: [FormCurveFloorChange]
    let h5: FormCurveH5?
}

/// H4 — 같은 조건(7일 안·페이스 ±5초) 러닝 쌍으로 잰 반복 측정 잡음과, 그것을 최소 폭으로 둔 구간 범위.
struct FormCurveH4Metric {
    let metric: FormCurveMetric
    let pairN: Int
    let noiseSD: Double?          // 쌍 차이 SD / √2
    let n: Int                    // walk-forward 판정 수
    let outRateBefore: Double
    let outRateAfter: Double
    /// 설계 기준 — 범위 밖 비율 15~25% (사용자 체감 확인은 별도). nil = 잡음 표본 부족.
    var passesNumeric: Bool? {
        guard noiseSD != nil else { return nil }
        return outRateAfter >= 0.15 && outRateAfter <= 0.25
    }
}

/// 최소 폭 때문에 '범위 밖' → '범위'로 바뀐 러닝.
struct FormCurveFloorChange {
    let date: Date
    let pace: Double
    let metric: FormCurveMetric
    let value: Double
    let before: ClosedRange<Double>
    let after: ClosedRange<Double>
}

/// H5 — 지면접촉 잔차(구간 중앙값 대비, walk-forward)와 부하 비율(직전 7일 거리 ÷ 4주 주평균).
struct FormCurveH5 {
    let n: Int
    let r: Double
    let rFirstHalf: Double?
    let rSecondHalf: Double?
    let highLoadN: Int
    let highLoadMeanResid: Double?
    let normalLoadMeanResid: Double?

    var passes: Bool {
        guard abs(r) >= 0.3, let a = rFirstHalf, let b = rSecondHalf else { return false }
        return a.sign == r.sign && b.sign == r.sign
    }
}

// MARK: - Engine

@MainActor
enum FormCurveValidation {
    static let cadenceStrideTolerance = 0.05
    static let bandK = 1.2                  // 구간 기준선 FormStat과 같은 ±1.2SD
    static let minCurvePoints = FormSpeedCurve.minPoints
    static let minPaceSpreadSec = 60.0
    static let edgeSec = 10.0
    static let smallBandN = 15
    static let bootstrapRuns = 1000

    private static var didLog = false

    /// 앱 실행당 한 번만 콘솔에 낸다 (기준선 캐시 사용 여부와 무관하게).
    static func logOnce(inputs: [FormInput], cutoffs: PaceBandCutoffs, asOf: Date = Date()) {
        guard !didLog else { return }
        didLog = true
        let report = run(samples: inputs.map(FormCurveSample.init), cutoffs: cutoffs, asOf: asOf)
        for line in logLines(report) { print(line) }
    }

    static func run(samples raw: [FormCurveSample], cutoffs: PaceBandCutoffs, asOf: Date) -> FormCurveValidationReport {
        let window = asOf.addingTimeInterval(-365 * 86400)
        let inWindow = raw.filter { $0.date >= window && $0.date <= asOf }
        let clean = inWindow.filter { !$0.isCadenceStrideOutlier }
        let paces = clean.map(\.paceSecPerKm).sorted()
        let (h1, dis) = walkForward(samples: clean, cutoffs: cutoffs, asOf: asOf)
        let floorMetrics = floorTest(samples: clean, cutoffs: cutoffs, asOf: asOf)
        return FormCurveValidationReport(
            totalRuns: inWindow.count,
            outlierRuns: inWindow.count - clean.count,
            paceP10: paces.isEmpty ? nil : percentile(paces, 0.10),
            paceP90: paces.isEmpty ? nil : percentile(paces, 0.90),
            h1: h1,
            disagreements: dis,
            h2: tradeOff(samples: clean, asOf: asOf),
            h3: gearShare(samples: clean),
            h4: floorMetrics.metrics,
            h4Changed: floorMetrics.changed,
            h5: loadVsGCT(samples: clean, cutoffs: cutoffs))
    }

    // MARK: H4 — 측정 잡음 · 최소 폭

    static let floorMetrics: [FormCurveMetric] = [.cadence, .gct, .vo]
    static let noisePairDays = 7.0
    static let noisePairPaceSec = 5.0
    static let minNoisePairs = 10

    /// 7일 안·GAP 페이스 ±5초 러닝 쌍의 차이 SD / √2. 쌍은 모든 조합(겹침 허용) — 잡음 크기 추정용.
    static func noise(samples: [FormCurveSample], metric: FormCurveMetric) -> (pairs: Int, sd: Double?) {
        let s = samples.filter { metric.value($0) != nil }.sorted { $0.date < $1.date }
        var diffs: [Double] = []
        for i in s.indices {
            for j in (i + 1)..<s.count {
                if s[j].date.timeIntervalSince(s[i].date) > noisePairDays * 86400 { break }
                guard abs(s[j].effectivePaceSecPerKm - s[i].effectivePaceSecPerKm) <= noisePairPaceSec else { continue }
                diffs.append(metric.value(s[j])! - metric.value(s[i])!)
            }
        }
        guard diffs.count >= minNoisePairs else { return (diffs.count, nil) }
        let m = diffs.reduce(0, +) / Double(diffs.count)
        let sd = (diffs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(diffs.count - 1)).squareRoot()
        return (diffs.count, sd / 2.0.squareRoot())
    }

    /// 구간 범위 반폭 = max(1.2 × SD, 1.2 × 잡음). 중앙값은 그대로라 H1의 MAE는 바뀌지 않는다.
    static func flooredRange(_ st: FormStat, noiseSD: Double) -> ClosedRange<Double> {
        let half = max(bandK * st.sd, bandK * noiseSD)
        return (st.median - half)...(st.median + half)
    }

    static func floorTest(samples: [FormCurveSample], cutoffs: PaceBandCutoffs,
                          asOf: Date) -> (metrics: [FormCurveH4Metric], changed: [FormCurveFloorChange]) {
        let recentFrom = asOf.addingTimeInterval(-90 * 86400)
        let targets = samples.filter { $0.date >= recentFrom }
        var metrics: [FormCurveH4Metric] = []
        var changed: [FormCurveFloorChange] = []
        for m in floorMetrics {
            let (pairs, noiseSD) = noise(samples: samples, metric: m)
            var n = 0, before = 0, after = 0
            for t in targets {
                guard let v = m.value(t),
                      let (st, _) = bandStat(for: t, metric: m, samples: samples, cutoffs: cutoffs) else { continue }
                n += 1
                let br = st.lower...st.upper
                let bOut = FormCurveVerdict(v, br) != .inside
                if bOut { before += 1 }
                guard let ns = noiseSD else { if bOut { after += 1 }; continue }
                let ar = flooredRange(st, noiseSD: ns)
                let aOut = FormCurveVerdict(v, ar) != .inside
                if aOut { after += 1 }
                if bOut && !aOut {
                    changed.append(FormCurveFloorChange(date: t.date, pace: t.effectivePaceSecPerKm, metric: m,
                                                        value: v, before: br, after: ar))
                }
            }
            guard n > 0 else { continue }
            metrics.append(FormCurveH4Metric(metric: m, pairN: pairs, noiseSD: noiseSD, n: n,
                                             outRateBefore: Double(before) / Double(n),
                                             outRateAfter: Double(after) / Double(n)))
        }
        return (metrics, changed.sorted { $0.date > $1.date })
    }

    // MARK: H5 — 부하 비율 ↔ 지면접촉

    static let highLoadRatio = 1.3

    /// 직전 7일 거리 ÷ (직전 28일 거리 / 4). 입력이 3km+·폼 있는 러닝뿐이라 실제 부하의 근사값.
    static func loadRatio(at date: Date, samples: [FormCurveSample]) -> Double? {
        let d7 = date.addingTimeInterval(-7 * 86400), d28 = date.addingTimeInterval(-28 * 86400)
        let prior = samples.filter { $0.date < date && $0.date >= d28 }
        let km28 = prior.map(\.distanceM).reduce(0, +)
        guard km28 > 0 else { return nil }
        let km7 = prior.filter { $0.date >= d7 }.map(\.distanceM).reduce(0, +)
        return km7 / (km28 / 4)
    }

    static func loadVsGCT(samples: [FormCurveSample], cutoffs: PaceBandCutoffs) -> FormCurveH5? {
        var pts: [(load: Double, resid: Double)] = []
        for t in samples.sorted(by: { $0.date < $1.date }) {
            guard let g = t.gct, let load = loadRatio(at: t.date, samples: samples),
                  let (st, _) = bandStat(for: t, metric: .gct, samples: samples, cutoffs: cutoffs) else { continue }
            pts.append((load, g - st.median))
        }
        guard pts.count >= minCurvePoints, let r = pearson(pts.map(\.load), pts.map(\.resid)) else { return nil }
        let half = pts.count / 2
        let first = Array(pts[..<half]), second = Array(pts[half...])
        let high = pts.filter { $0.load >= highLoadRatio }.map(\.resid)
        let normal = pts.filter { $0.load < highLoadRatio }.map(\.resid)
        func mean(_ a: [Double]) -> Double? { a.isEmpty ? nil : a.reduce(0, +) / Double(a.count) }
        return FormCurveH5(n: pts.count, r: r,
                           rFirstHalf: pearson(first.map(\.load), first.map(\.resid)),
                           rSecondHalf: pearson(second.map(\.load), second.map(\.resid)),
                           highLoadN: high.count, highLoadMeanResid: mean(high), normalLoadMeanResid: mean(normal))
    }

    // MARK: Curve

    static func fitCurve(_ pts: [(date: Date, speed: Double, value: Double)], asOf: Date) -> FormCurveFit? {
        FormSpeedCurve.fit(pts, asOf: asOf)
    }

    /// target 날짜 이전 1년 기록만으로 곡선을 만든다 — 미래 러닝 누설 없음.
    static func curveFit(for target: FormCurveSample, metric: FormCurveMetric,
                         samples: [FormCurveSample]) -> FormCurveFit? {
        let from = target.date.addingTimeInterval(-365 * 86400)
        let pts = samples.compactMap { s -> (date: Date, speed: Double, value: Double)? in
            guard s.date < target.date, s.date >= from, let v = metric.value(s) else { return nil }
            return (s.date, s.effectiveSpeedMPerMin, v)
        }
        return fitCurve(pts, asOf: target.date)
    }

    /// 구간 기준선과 같은 규칙(6개월 5회↑, 아니면 12개월 5회↑)을 target 이전 기록에만 적용.
    static func bandStat(for target: FormCurveSample, metric: FormCurveMetric,
                         samples: [FormCurveSample], cutoffs: PaceBandCutoffs) -> (stat: FormStat, bandN: Int)? {
        guard let band = cutoffs.band(of: target.effectivePaceSecPerKm) else { return nil }
        let w12 = target.date.addingTimeInterval(-365 * 86400)
        let w6  = target.date.addingTimeInterval(-182 * 86400)
        let prior = samples.filter { $0.date < target.date && $0.date >= w12
            && cutoffs.band(of: $0.effectivePaceSecPerKm) == band }
        let six = prior.filter { $0.date >= w6 }
        let chosen = six.count >= FormBaselineEngine.minSamples ? six : prior
        guard chosen.count >= FormBaselineEngine.minSamples,
              let st = FormBaselineEngine.formStat(chosen.compactMap { metric.value($0) }) else { return nil }
        return (st, chosen.count)
    }

    static func isNearEdge(_ pace: Double, _ c: PaceBandCutoffs) -> Bool {
        var edges = [c.jogMin, c.dailyMin, c.tempoMin]
        if c.jogMax < .greatestFiniteMagnitude / 2 { edges.append(c.jogMax) }
        return edges.contains { abs(pace - $0) <= edgeSec }
    }

    // MARK: H1

    static func walkForward(samples: [FormCurveSample], cutoffs: PaceBandCutoffs,
                            asOf: Date) -> ([FormCurveH1Metric], [FormCurveDisagreement]) {
        let recentFrom = asOf.addingTimeInterval(-90 * 86400)
        let targets = samples.filter { $0.date >= recentFrom }
        var metrics: [FormCurveH1Metric] = []
        var dis: [FormCurveDisagreement] = []

        for m in FormCurveMetric.allCases {
            var bandErr: [Double] = [], curveErr: [Double] = []
            var edgeB: [Double] = [], edgeC: [Double] = []
            var smallB: [Double] = [], smallC: [Double] = []
            var bandOut = 0, curveOut = 0
            for t in targets {
                guard let v = m.value(t),
                      let (st, bandN) = bandStat(for: t, metric: m, samples: samples, cutoffs: cutoffs),
                      let fit = curveFit(for: t, metric: m, samples: samples) else { continue }
                let eb = abs(v - st.median)
                let ec = abs(v - fit.predict(speed: t.effectiveSpeedMPerMin))
                bandErr.append(eb); curveErr.append(ec)
                if isNearEdge(t.effectivePaceSecPerKm, cutoffs) { edgeB.append(eb); edgeC.append(ec) }
                if bandN < smallBandN { smallB.append(eb); smallC.append(ec) }
                let br = st.lower...st.upper
                let cr = fit.range(speed: t.effectiveSpeedMPerMin)
                let bv = FormCurveVerdict(v, br), cv = FormCurveVerdict(v, cr)
                if bv != .inside { bandOut += 1 }
                if cv != .inside { curveOut += 1 }
                if bv != cv {
                    dis.append(FormCurveDisagreement(date: t.date, pace: t.effectivePaceSecPerKm, metric: m,
                                                     value: v, bandRange: br, bandVerdict: bv,
                                                     curveRange: cr, curveVerdict: cv))
                }
            }
            guard !bandErr.isEmpty else { continue }
            func mae(_ a: [Double]) -> Double? { a.count >= 3 ? a.reduce(0, +) / Double(a.count) : nil }
            let n = Double(bandErr.count)
            metrics.append(FormCurveH1Metric(
                metric: m, n: bandErr.count,
                bandMAE: bandErr.reduce(0, +) / n, curveMAE: curveErr.reduce(0, +) / n,
                edgeN: edgeB.count, edgeBandMAE: mae(edgeB), edgeCurveMAE: mae(edgeC),
                smallN: smallB.count, smallBandMAE: mae(smallB), smallCurveMAE: mae(smallC),
                bandOutRate: Double(bandOut) / n, curveOutRate: Double(curveOut) / n))
        }
        return (metrics, dis.sorted { $0.date > $1.date })
    }

    // MARK: H2

    static func tradeOff(samples: [FormCurveSample], asOf: Date) -> FormCurveH2? {
        let both = samples.filter { $0.cadence != nil && $0.gct != nil }.sorted { $0.date < $1.date }
        func pts(_ m: FormCurveMetric) -> [(date: Date, speed: Double, value: Double)] {
            both.map { ($0.date, $0.effectiveSpeedMPerMin, m.value($0)!) }
        }
        guard let cf = fitCurve(pts(.cadence), asOf: asOf),
              let gf = fitCurve(pts(.gct), asOf: asOf) else { return nil }
        let cadRes = both.map { $0.cadence! - cf.predict(speed: $0.effectiveSpeedMPerMin) }
        let gctRes = both.map { $0.gct! - gf.predict(speed: $0.effectiveSpeedMPerMin) }
        guard let beta = slope(cadRes, gctRes), let r = pearson(cadRes, gctRes) else { return nil }
        let half = both.count / 2
        let examples = (0..<both.count).suffix(3).reversed().map {
            (date: both[$0].date, gctResid: gctRes[$0], cadResid: cadRes[$0])
        }
        return FormCurveH2(n: both.count, beta: beta, r: r,
                           betaFirstHalf: slope(Array(cadRes[..<half]), Array(gctRes[..<half])),
                           betaSecondHalf: slope(Array(cadRes[half...]), Array(gctRes[half...])),
                           examples: examples)
    }

    // MARK: H3

    /// ln 케이던스 ~ ln 속도 기울기 = 속도 증가 중 케이던스 몫 (보폭 몫 = 1 − 케이던스 몫).
    static func gearShare(samples: [FormCurveSample]) -> FormCurveH3 {
        let pts = samples.filter { $0.cadence != nil && $0.stride != nil }.sorted { $0.date < $1.date }
        let paces = pts.map(\.paceSecPerKm).sorted()
        let spread = paces.count >= 2 ? percentile(paces, 0.90) - percentile(paces, 0.10) : 0
        let xs = pts.map { log($0.speedMPerMin) }
        let ys = pts.map { log($0.cadence!) }
        guard pts.count >= minCurvePoints, spread >= minPaceSpreadSec, let share = slope(xs, ys) else {
            return FormCurveH3(n: pts.count, paceSpreadSec: spread, cadenceShare: nil,
                               ciLow: nil, ciHigh: nil, shareFirstHalf: nil, shareSecondHalf: nil)
        }
        var rng = SplitMix64(seed: 20261021)
        var boots: [Double] = []
        for _ in 0..<bootstrapRuns {
            var bx: [Double] = [], by: [Double] = []
            for _ in 0..<pts.count {
                let i = Int.random(in: 0..<pts.count, using: &rng)
                bx.append(xs[i]); by.append(ys[i])
            }
            if let s = slope(bx, by) { boots.append(s) }
        }
        boots.sort()
        let half = pts.count / 2
        return FormCurveH3(n: pts.count, paceSpreadSec: spread, cadenceShare: share,
                           ciLow: boots.isEmpty ? nil : percentile(boots, 0.05),
                           ciHigh: boots.isEmpty ? nil : percentile(boots, 0.95),
                           shareFirstHalf: slope(Array(xs[..<half]), Array(ys[..<half])),
                           shareSecondHalf: slope(Array(xs[half...]), Array(ys[half...])))
    }

    // MARK: Stats

    static func slope(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 3 else { return nil }
        let n = Double(xs.count)
        let xm = xs.reduce(0, +) / n, ym = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - xm) * ($1 - xm) }
        guard sxx > 0 else { return nil }
        return zip(xs, ys).reduce(0) { $0 + ($1.0 - xm) * ($1.1 - ym) } / sxx
    }

    static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 3 else { return nil }
        let n = Double(xs.count)
        let xm = xs.reduce(0, +) / n, ym = ys.reduce(0, +) / n
        let dx = xs.reduce(0) { $0 + ($1 - xm) * ($1 - xm) }.squareRoot()
        let dy = ys.reduce(0) { $0 + ($1 - ym) * ($1 - ym) }.squareRoot()
        guard dx > 0, dy > 0 else { return nil }
        return zip(xs, ys).reduce(0) { $0 + ($1.0 - xm) * ($1.1 - ym) } / (dx * dy)
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        FormBaselineEngine.percentile(sorted, p)
    }

    // MARK: Log

    static func logLines(_ r: FormCurveValidationReport) -> [String] {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        func pf(_ s: Double) -> String { String(format: "%d'%02d\"", Int(s.rounded()) / 60, Int(s.rounded()) % 60) }
        func f(_ v: Double?, _ fmt: String) -> String { v.map { String(format: fmt, $0) } ?? "—" }
        func yn(_ b: Bool?) -> String { b.map { $0 ? "채택" : "기각" } ?? "표본 부족" }
        var out: [String] = []
        let P = "[곡선검증]"
        out.append("\(P) 데이터 — 12개월 러닝 \(r.totalRuns)회 · 케이던스×보폭 이상 \(r.outlierRuns)회 제외 · 페이스 P10~P90 "
                   + (r.paceP10.flatMap { lo in r.paceP90.map { "\(pf(lo))~\(pf($0)) (폭 \(Int(($0 - lo).rounded()))초)" } } ?? "—"))

        out.append("\(P) H1 판정 기준 — 최근 90일 walk-forward (MAE 구간 / 곡선 · 범위 밖 비율 구간 / 곡선)")
        for m in r.h1 {
            let fmt = m.metric.format
            out.append("\(P)   \(m.metric.name) n=\(m.n) · 전체 \(f(m.bandMAE, fmt)) / \(f(m.curveMAE, fmt))"
                       + " · 경계 n=\(m.edgeN) \(f(m.edgeBandMAE, fmt)) / \(f(m.edgeCurveMAE, fmt))"
                       + " · 작은 구간 n=\(m.smallN) \(f(m.smallBandMAE, fmt)) / \(f(m.smallCurveMAE, fmt))"
                       + String(format: " · 범위 밖 %.0f%% / %.0f%%", m.bandOutRate * 100, m.curveOutRate * 100)
                       + " → 숫자 기준 \(yn(m.passesNumeric))")
        }
        if r.h1.isEmpty { out.append("\(P)   비교 가능한 러닝 없음 (곡선 최소 \(minCurvePoints)회 · 구간 최소 \(FormBaselineEngine.minSamples)회)") }
        out.append("\(P) H1 엇갈린 판정 \(r.disagreements.count)건 — 체감과 맞는 쪽 확인 필요")
        for d in r.disagreements.prefix(20) {
            let fmt = d.metric.format
            out.append("\(P)   \(df.string(from: d.date)) \(pf(d.pace)) \(d.metric.name) \(f(d.value, fmt))"
                       + " · 구간 \(f(d.bandRange.lowerBound, fmt))~\(f(d.bandRange.upperBound, fmt)) \(d.bandVerdict.rawValue)"
                       + " · 곡선 \(f(d.curveRange.lowerBound, fmt))~\(f(d.curveRange.upperBound, fmt)) \(d.curveVerdict.rawValue)")
        }

        if let h = r.h2 {
            out.append("\(P) H2 같은 페이스 맞바꿈 — n=\(h.n) · β=\(f(h.beta, "%+.2f"))ms/spm · r=\(f(h.r, "%+.2f"))"
                       + " · 앞 절반 β=\(f(h.betaFirstHalf, "%+.2f")) · 뒤 절반 β=\(f(h.betaSecondHalf, "%+.2f")) → \(h.passes ? "채택" : "기각")")
            for e in h.examples {
                let explained = h.beta * e.cadResid
                out.append("\(P)   \(df.string(from: e.date)) 접지 \(f(e.gctResid, "%+.0f"))ms · 케이던스 \(f(e.cadResid, "%+.1f"))spm"
                           + " → 케이던스로 설명 \(f(explained, "%+.0f"))ms · 나머지 \(f(e.gctResid - explained, "%+.0f"))ms")
            }
        } else {
            out.append("\(P) H2 같은 페이스 맞바꿈 — 표본 부족 (케이던스·지면접촉 둘 다 있는 러닝 \(minCurvePoints)회 미만)")
        }

        let g = r.h3
        if g.isJudgeable {
            out.append("\(P) H3 기어 비율 — n=\(g.n) · 케이던스 몫 \(f(g.cadenceShare, "%.2f")) (90% \(f(g.ciLow, "%.2f"))~\(f(g.ciHigh, "%.2f")))"
                       + " · 보폭 몫 \(f(g.cadenceShare.map { 1 - $0 }, "%.2f"))"
                       + " · 앞 절반 \(f(g.shareFirstHalf, "%.2f")) · 뒤 절반 \(f(g.shareSecondHalf, "%.2f")) → \(g.passes ? "채택" : "기각")")
        } else {
            out.append("\(P) H3 기어 비율 — 판정 불가 (n=\(g.n) · 페이스 폭 \(Int(g.paceSpreadSec.rounded()))초 < \(Int(minPaceSpreadSec))초 또는 표본 부족) → 2차: km 구간 단위로 시도")
        }
        out.append("\(P) H4 측정 잡음 · 최소 폭 — 쌍 = 7일 안·페이스 ±\(Int(noisePairPaceSec))초 (범위 밖 비율 지금 → 최소 폭)")
        for m in r.h4 {
            let fmt = m.metric.format
            out.append("\(P)   \(m.metric.name) 쌍 \(m.pairN) · 잡음 SD \(f(m.noiseSD, fmt)) · n=\(m.n)"
                       + String(format: " · 범위 밖 %.0f%% → %.0f%%", m.outRateBefore * 100, m.outRateAfter * 100)
                       + " → 숫자 기준 \(yn(m.passesNumeric))")
        }
        out.append("\(P) H4 최소 폭으로 '범위'가 된 러닝 \(r.h4Changed.count)건 — 그날 평소와 같았는지 체감 확인 필요")
        for c in r.h4Changed.prefix(20) {
            let fmt = c.metric.format
            out.append("\(P)   \(df.string(from: c.date)) \(pf(c.pace)) \(c.metric.name) \(f(c.value, fmt))"
                       + " · 지금 \(f(c.before.lowerBound, fmt))~\(f(c.before.upperBound, fmt))"
                       + " → 최소 폭 \(f(c.after.lowerBound, fmt))~\(f(c.after.upperBound, fmt))")
        }

        if let h = r.h5 {
            out.append("\(P) H5 부하 비율 ↔ 지면접촉 잔차 — n=\(h.n) · r=\(f(h.r, "%+.2f"))"
                       + " · 앞 절반 r=\(f(h.rFirstHalf, "%+.2f")) · 뒤 절반 r=\(f(h.rSecondHalf, "%+.2f"))"
                       + " · 부하 ≥\(f(highLoadRatio, "%.1f")) \(h.highLoadN)회 평균 \(f(h.highLoadMeanResid, "%+.1f"))ms"
                       + " / 그 외 \(f(h.normalLoadMeanResid, "%+.1f"))ms → \(h.passes ? "채택(피로 관련)" : "기각")")
        } else {
            out.append("\(P) H5 부하 비율 ↔ 지면접촉 — 표본 부족 (\(minCurvePoints)회 미만)")
        }
        return out
    }
}

/// 부트스트랩 재현용 고정 시드 난수.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
#endif
