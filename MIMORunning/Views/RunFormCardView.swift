import SwiftUI

import Charts

// MARK: - Shared: Long-Distance Context

/// 거리 문맥 판정 — 단일 소스. 폼 탭·리듬 탭 공용.
/// .longRun/.lsd 이거나 현재 거리 > 4주 평균 러닝 × 1.50 또는 절대 거리 ≥ 12km 이면 true.
func isLongDistanceRunContext(
    activity: Activity,
    workoutType: WorkoutType,
    recentAvgDistanceKm: Double?
) -> Bool {
    if workoutType == .longRun || workoutType == .lsd { return true }
    guard let typical = recentAvgDistanceKm, typical > 0 else { return false }
    let distKm = activity.distance / 1000
    return distKm > typical * 1.50 || distKm >= 12.0
}

// MARK: - Run Form Card

struct RunFormCardView: View {
    let activity: Activity
    var splits: [SplitData] = []
    var avgCadence: Int? = nil
    var avgStrideLength: Double? = nil
    var avgGroundContactTime: Double? = nil
    var avgVerticalOscillation: Double? = nil
    /// 고도 프로파일 — 경사 조정 페이스(GAP) 계산용. 없으면 실제 페이스로 구간을 찾는다.
    var altitudeProfile: [(distanceKm: Double, altitude: Double)] = []
    var baseline: RunningFormBaseline? = nil
    var workoutType: WorkoutType = .general
    var intervalSegments: [IntervalSegment] = []
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    var typicalDistanceKm: Double? = nil  // 4주 평균 1회 러닝 거리(km). 장거리 문맥 판단에 사용.
    var heatModel: MRHeatModel? = nil
    var formShifts: [MRFormShift] = []
    /// 이 러닝의 케이던스 잔차(실제 − 페이스 예상값). 추세 문단 마무리("이 러닝도 그 흐름 위에 있어요")에 쓴다.
    var runCadenceResidual: Double? = nil
    var hasRecentGap: Bool = false
    var weatherSnapshot: WeatherSnapshot? = nil
    var historicalTemperatures: [Double] = []   // 야외 런 기온 이력 — 추위 슬롯 문맥 및 tempExtreme 중복 체크용

    // 버킷 계산은 러닝당 1회만 — onAppear 시 저장, splitFormTrendSection·logTrend에서 재사용
    @State private var formSeriesCache: [FormSeries] = []

    // MARK: - Nested Types

    /// 지표 종류·상태는 인사이트 탭 리듬 카드와 공유 (`FormNarrative`) — 두 카드의 판정이 같은 함수를 거친다.
    typealias MetricDir = FormNarrative.Metric
    typealias MetricStatus = FormNarrative.Status
    enum RunningStyle { case quickStep, bigStride, normal, unknown }

    struct FormInsightItem: Identifiable {
        enum Kind: String { case temperature, weather, trend, distance, cadenceHR, style, formChange }
        var id: Kind
        var badgeText: String
        var bodyText: String
        var badgeColor: Color
    }

    struct ChainChild: Identifiable {
        let id: Int
        let label: String
        let rawValue: Double
        let formatted: String
        let unit: String
        let stat: FormStat?
        let dir: MetricDir
        let isRef: Bool
    }

    struct FormSeries {
        struct Point: Identifiable {
            let id: Int         // bucket index
            let kmEnd: Double   // [65] 버킷 끝 누적 km
            let value: Double
            let outOfRange: Bool
        }
        let label: String
        let unit: String
        let points: [Point]
        let bandLo: Double?
        let bandHi: Double?
        let firstAvg: Double?
        let secondAvg: Double?
        let dir: MetricDir
        let lineColor: Color
        let bandIsJudgeable: Bool   // 띠 판정 가능 여부
        var bandIsReference: Bool = false  // true = 다른 페이스 구간에서 빌려온 참고 띠
        let bandSampleCount: Int    // 띠 표본 수 (라벨·로그용)
        let bandPaceMin: Double?    // 띠 기준 페이스 하한 (sec/km) — 라벨용
        let bandPaceMax: Double?    // 띠 기준 페이스 상한 (sec/km) — 라벨용
        let totalSplitCount: Int    // 버킷 전체 수 (결측 표기용)

        var yDomain: ClosedRange<Double> {
            var lo = points.map(\.value).min() ?? 0
            var hi = points.map(\.value).max() ?? 1
            if let b = bandLo { lo = min(lo, b) }
            if let b = bandHi { hi = max(hi, b) }
            // 띠 폭의 25%를 위아래 여백으로 — 띠가 배경이 아닌 "범위"로 읽히도록
            let pad: Double
            if let bLo = bandLo, let bHi = bandHi, bHi > bLo {
                pad = (bHi - bLo) * 0.25
            } else {
                let span = hi - lo
                pad = span > 0 ? span * 0.10 : 1.0
            }
            return (lo - pad)...(hi + pad)
        }
    }

    // MARK: - Computed

    /// 이 러닝의 경사 조정 페이스. 기준선이 GAP으로 계산되므로 구간 조회도 GAP으로 한다.
    private var runGAP: Double? {
        GradeAdjustedPace.compute(splits: splits, altitudeProfile: altitudeProfile)
    }

    private var bb: BandBaseline? {
        baseline?.baseline(for: activity, gradeAdjustedPace: runGAP)
    }

    /// 평지 환산 표기 — 세 카드 공용 함수(GradeAdjustedPace.kpiText) 사용
    private var flatEquivalentText: String? {
        GradeAdjustedPace.kpiText(splits: splits, altitudeProfile: altitudeProfile,
                                  actualPaceSecPerKm: activity.paceSecPerKm)
    }

    /// 오늘 페이스가 개인 페이스 구간 밖(`cutoffs.band(of:) == nil`)일 때 **표시용**으로 쓸
    /// 가장 가까운 유효 밴드. 평소보다 빠르면 가장 빠른 구간부터, 느리면 가장 느린 구간부터 찾는다.
    /// ⚠ 판정(문장·상태 배지·OOB 강조)에는 절대 쓰지 않는다 — 다른 페이스대 기준이라 오독이 된다.
    ///   판정은 계속 `bb`(nil이면 생략)를 쓰고, 여기서는 "참고 띠"만 그린다.
    private var referenceBb: BandBaseline? {
        guard let bl = baseline else { return nil }
        return Self.referenceBand(in: bl, paceSecPerKm: activity.paceSecPerKm)
    }

    /// 참고 밴드 선택 — 순수 함수(테스트 대상).
    /// 페이스가 어느 구간에도 속하지 않을 때만 값을 돌려준다. 벗어난 쪽에서 가장 가까운 밴드부터 찾는다.
    static func referenceBand(in baseline: RunningFormBaseline,
                              paceSecPerKm: Double?) -> BandBaseline? {
        guard let pace = paceSecPerKm,
              baseline.cutoffs.band(of: pace) == nil else { return nil }
        let order: [PaceBand] = isFaster(than: baseline, pace: pace)
            ? [.fast, .tempo, .daily, .jog, .verySlow]     // 평소보다 빠름 → 가장 빠른 구간부터
            : [.verySlow, .jog, .daily, .tempo, .fast]     // 평소보다 느림 → 가장 느린 구간부터
        for band in order {
            if let found = baseline.bands[band] { return found }
        }
        return nil
    }

    /// true = 구간보다 **빠른** 쪽으로 벗어남 (false = 느린 쪽)
    static func isFaster(than baseline: RunningFormBaseline, pace: Double) -> Bool {
        baseline.cutoffs.fastMin > 0 && pace < baseline.cutoffs.fastMin
    }

    private var isFasterThanBands: Bool {
        guard let bl = baseline, let pace = activity.paceSecPerKm else { return false }
        return Self.isFaster(than: bl, pace: pace)
    }

    /// 범위 바·km 차트 띠에 실제로 그릴 밴드 (판정용 `bb`와 구분).
    private var displayBb: BandBaseline? { bb ?? referenceBb }

    /// true = 오늘 페이스가 구간 밖이라 다른 구간을 "참고"로 빌려 그리는 중.
    private var isReferenceBand: Bool { bb == nil && referenceBb != nil }

    /// 표시용 GCT 밴드 (참고 모드 포함). 판정용은 `adjustedGctStat`.
    private var displayGctStat: FormStat? {
        FormNarrative.driftAdjustedGCT(displayBb?.groundContact,
                                       baselineResidualMean: baseline?.gctBaselineResidualMean,
                                       gctShift: formShifts.first(where: { $0.metric.key == "gct" }))
    }

    private func bandDisplayName(_ b: PaceBand) -> String {
        let L = AppLanguage.shared
        switch b {
        case .verySlow: return L.s("아주 느림", "Very slow")
        case .jog:      return L.s("느린 편", "Easy")
        case .daily:    return L.s("보통", "Daily")
        case .tempo:    return L.s("빠른 편", "Tempo")
        case .fast:     return L.s("가장 빠른", "Fastest")
        }
    }

    private func paceStr(_ sec: Double) -> String {
        let i = Int(sec.rounded())
        return "\(i / 60)'\(String(format: "%02d", i % 60))\""
    }

    /// GCT 밴드를 열람 시점 기준으로 보정한 FormStat.
    /// GCT는 지난 1년간 9ms 이상 짧아지는 경우가 있어 현재 밴드로 과거 러닝을 판정하면 오류 발생.
    /// drift = (열람 시점 잔차 3개월 평균) − (baseline 계산 시점 잔차 3개월 평균)
    /// 안전장치: recent 표본 20개 미만(gctShift nil) · R²<0.2 · |drift|<2ms → 보정 없음
    private var adjustedGctStat: FormStat? {
        FormNarrative.driftAdjustedGCT(bb?.groundContact,
                                       baselineResidualMean: baseline?.gctBaselineResidualMean,
                                       gctShift: formShifts.first(where: { $0.metric.key == "gct" }))
    }

    private var isInterval: Bool { workoutType == .interval }

    /// true → 장거리 문맥. 장거리에서는 지표 하락이 자주 나타남 — 상태 배지를 숨기고 조언을 유보.
    private var isLongDistanceContext: Bool {
        isLongDistanceRunContext(
            activity: activity,
            workoutType: workoutType,
            recentAvgDistanceKm: typicalDistanceKm
        )
    }

    /// 초·중·말 폼 형태 — 풀 스플릿 6개 이상 + 기준선 있을 때만. 인터벌은 제외.
    /// 판정(fullSplits)과 표시(버킷)를 섞지 않는다 — 문장은 판정, 30/70 점선 위치만 차트에 표시.
    /// 참고 밴드(오늘 페이스가 구간 밖)면 판정하지 않는다 — 카드의 "판정 대신 참고" 규칙과 같다.
    private var formPhaseResult: FormPhase.Result? {
        guard !isInterval, !isReferenceBand, let bl = baseline else { return nil }
        let gctShift = formShifts.first(where: { $0.metric.key == "gct" })
        // 기준선 밴드는 GAP 기준 — 밴드 조회 페이스도 GAP 배율(GAP ÷ 실측)로 맞춘다 (bb와 같은 규칙)
        let scale: Double = {
            let distKm = fullSplits.map(\.distanceM).reduce(0, +) / 1000
            let dur = fullSplits.map(\.duration).reduce(0, +)
            guard let gap = runGAP, distKm > 0, dur > 0 else { return 1.0 }
            return gap / (dur / distKm)   // 분모도 스플릿 기준 — 같은 총량에서 나온 비율
        }()
        return FormPhase.classify(splits: fullSplits, paceScale: scale, bandFor: { pace in
            FormPhase.bandStats(in: bl, paceSecPerKm: pace, gctShift: gctShift)
        })
    }

    private let lineColor = Color.white.opacity(0.20)
    // [57] 텍스트 열 고정 너비 — 가장 긴 「수직진폭 (참고) N.N cm」+ 들여쓰기를 수용
    //      네 줄 모두 이 값에서 바가 시작 → 축 좌우 끝 픽셀 정렬
    private let barTextColumnWidth: CGFloat = 120

    private var fullSplits: [SplitData] {
        splits.filter { $0.distanceM >= 900 }
    }

    private var showTrendSection: Bool {
        guard !isInterval, fullSplits.count >= 3 else { return false }
        return fullSplits.contains {
            $0.avgCadence != nil || $0.avgStrideLength != nil ||
            $0.avgGroundContactTime != nil || $0.avgVerticalOscillation != nil
        }
    }

    /// 표시 전용 버킷. 판정 계산(전반/후반 비교 등)은 fullSplits를 직접 사용할 것.
    private func bucketedDisplaySplits(_ splits: [SplitData]) -> [SplitData] {
        guard splits.count > 10 else { return splits }
        let step = splits.count > 20 ? 3 : 2

        var buckets: [SplitData] = []
        var i = 0; var idx = 1; let n = splits.count
        while i < n {
            let group = Array(splits[i..<min(i + step, n)])
            func avgD(_ f: (SplitData) -> Double?) -> Double? {
                let v = group.compactMap(f); return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
            }
            func avgI(_ f: (SplitData) -> Int?) -> Int? {
                let v = group.compactMap(f)
                return v.isEmpty ? nil : Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
            }
            buckets.append(SplitData(
                id: idx,
                distanceM: group.map(\.distanceM).reduce(0, +),
                duration: group.map(\.duration).reduce(0, +),
                avgHeartRate: avgI(\.avgHeartRate),
                avgCadence: avgI(\.avgCadence),
                avgPower: avgI(\.avgPower),
                avgGroundContactTime: avgD(\.avgGroundContactTime),
                avgStrideLength: avgD(\.avgStrideLength),
                avgVerticalOscillation: avgD(\.avgVerticalOscillation)
            ))
            i += step; idx += 1
        }
        // 로그는 logTrend에서 출력 — 여기서 출력하면 렌더당 N회 중복

        return buckets
    }

    private var formSeries: [FormSeries] {
        guard !isInterval else { return [] }
        let L = AppLanguage.shared
        let fs = fullSplits              // 원본: 판정(전반/후반 비교) 전용
        let bs = bucketedDisplaySplits(fs) // 버킷: 차트 포인트 표시 전용
        guard fs.count >= 3 else { return [] }

        // [65] 버킷별 누적 km — x축 km 표기용
        var accumKm = 0.0
        var bucketKm = [Int: Double]()
        for s in bs { accumKm += s.distanceM / 1000.0; bucketKm[s.id] = accumKm }
        let mid = fs.count / 2
        let firstHalf  = Array(fs.prefix(mid))
        let secondHalf = Array(fs.suffix(from: mid))

        func avg(_ vals: [Double?]) -> Double? {
            let v = vals.compactMap { $0 }
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        // 판정가능 → ±1.2SD×factor / 판정불가(표본<minSamples) → P10-P90 관측 범위
        // 참고 밴드(오늘 페이스가 구간 밖)는 판정불가로 취급 — 띠는 그리되 OOB 강조는 끈다
        let isRefBand     = isReferenceBand
        let dispBb        = displayBb
        let bbJudgeable   = isRefBand ? false : (bb?.isJudgeable ?? true)
        let bbSampleCount = dispBb?.sampleCount ?? 0
        func splitBounds(_ formStat: FormStat?, dir: MetricDir)
            -> (lo: Double, hi: Double)? {
            guard let stat = formStat else { return nil }
            if !bbJudgeable, let p10 = stat.p10, let p90 = stat.p90 {
                return (lo: roundedDisplay(p10, dir: dir),
                        hi: roundedDisplay(p90, dir: dir))
            }
            let factor: Double = dir == .groundContact ? 1.2 : 1.5
            let halfWidth = (stat.upper - stat.lower) / 2.0 * factor
            return (lo: roundedDisplay(stat.median - halfWidth, dir: dir),
                    hi: roundedDisplay(stat.median + halfWidth, dir: dir))
        }
        let isOOB: (Double, FormStat?, MetricDir) -> Bool = { v, stat, dir in
            guard bbJudgeable else { return false }
            guard let b = splitBounds(stat, dir: dir) else { return false }
            let rv = self.roundedDisplay(v, dir: dir)
            return rv < b.lo || rv > b.hi
        }

        var result: [FormSeries] = []

        // Cadence
        let cadPairs: [(Int, Double)] = bs.compactMap { s in s.avgCadence.map { (s.id, Double($0)) } }
        if !cadPairs.isEmpty {
            let stat = dispBb?.cadence
            let cb = splitBounds(stat, dir: .cadence)
            result.append(FormSeries(
                label: L.s("케이던스", "Cadence"), unit: "spm",
                points: cadPairs.map { km, v in .init(id: km, kmEnd: bucketKm[km] ?? Double(km), value: v, outOfRange: isOOB(v, stat, .cadence)) },
                bandLo: cb?.lo, bandHi: cb?.hi,
                firstAvg:  avg(firstHalf.map  { $0.avgCadence.map(Double.init) }),
                secondAvg: avg(secondHalf.map { $0.avgCadence.map(Double.init) }),
                dir: .cadence, lineColor: Theme.cadence,
                bandIsJudgeable: bbJudgeable, bandIsReference: isRefBand, bandSampleCount: bbSampleCount,
                bandPaceMin: dispBb?.paceMin, bandPaceMax: dispBb?.paceMax, totalSplitCount: bs.count
            ))
        }

        // Stride
        let slPairs: [(Int, Double)] = bs.compactMap { s in s.avgStrideLength.map { (s.id, $0) } }
        if !slPairs.isEmpty {
            let stat = dispBb?.strideLength
            let sb = splitBounds(stat, dir: .stride)
            result.append(FormSeries(
                label: L.s("보폭", "Stride"), unit: "m",
                points: slPairs.map { km, v in .init(id: km, kmEnd: bucketKm[km] ?? Double(km), value: v, outOfRange: isOOB(v, stat, .stride)) },
                bandLo: sb?.lo, bandHi: sb?.hi,
                firstAvg:  avg(firstHalf.map(\.avgStrideLength)),
                secondAvg: avg(secondHalf.map(\.avgStrideLength)),
                dir: .stride, lineColor: Theme.strideLength,
                bandIsJudgeable: bbJudgeable, bandIsReference: isRefBand, bandSampleCount: bbSampleCount,
                bandPaceMin: dispBb?.paceMin, bandPaceMax: dispBb?.paceMax, totalSplitCount: bs.count
            ))
        }

        // GCT — [109] adjustedGctStat로 시점 보정 밴드 적용
        let gctPairs: [(Int, Double)] = bs.compactMap { s in s.avgGroundContactTime.map { (s.id, $0) } }
        if !gctPairs.isEmpty {
            let stat = displayGctStat
            let gb = splitBounds(stat, dir: .groundContact)
            result.append(FormSeries(
                label: L.s("지면접촉", "GCT"), unit: "ms",
                points: gctPairs.map { km, v in .init(id: km, kmEnd: bucketKm[km] ?? Double(km), value: v, outOfRange: isOOB(v, stat, .groundContact)) },
                bandLo: gb?.lo, bandHi: gb?.hi,
                firstAvg:  avg(firstHalf.map(\.avgGroundContactTime)),
                secondAvg: avg(secondHalf.map(\.avgGroundContactTime)),
                dir: .groundContact, lineColor: Theme.groundContact,
                bandIsJudgeable: bbJudgeable, bandIsReference: isRefBand, bandSampleCount: bbSampleCount,
                bandPaceMin: dispBb?.paceMin, bandPaceMax: dispBb?.paceMax, totalSplitCount: bs.count
            ))
        }

        // Vertical Oscillation (참고 전용 — 추세 표시, 판정·OOB 강조 없음)
        let voPairs: [(Int, Double)] = bs.compactMap { s in s.avgVerticalOscillation.map { (s.id, $0) } }
        if !voPairs.isEmpty {
            let voBounds = splitBounds(dispBb?.verticalOsc, dir: .verticalOsc)
            result.append(FormSeries(
                label: L.s("수직진폭", "Vert Osc"), unit: "cm",
                points: voPairs.map { km, v in .init(id: km, kmEnd: bucketKm[km] ?? Double(km), value: v, outOfRange: false) },
                bandLo: voBounds?.lo, bandHi: voBounds?.hi,
                firstAvg: avg(firstHalf.map(\.avgVerticalOscillation)),
                secondAvg: avg(secondHalf.map(\.avgVerticalOscillation)),
                dir: .verticalOsc, lineColor: Theme.verticalOsc,
                bandIsJudgeable: false, bandIsReference: isRefBand, bandSampleCount: bbSampleCount,
                bandPaceMin: nil, bandPaceMax: nil, totalSplitCount: bs.count
            ))
        }

        // 데이터 포인트 3개 이하는 추이 차트 자체가 무의미 — 제외 (VO 제외: 데이터 없음 칸 유지 필요)
        return result.filter { s in
            let include = s.dir == .verticalOsc || s.points.count > 3
            #if DEBUG
            if !include {
                print("[폼:추이] \(s.label) 데이터 \(s.points.count)/\(fs.count)스플릿 → 3개 이하 제외")
            }
            #endif
            return include
        }
    }

    // MARK: - Style Classification

    /// 주법 판정. 인터벌·장거리 문맥이면 .unknown. r ≤ -0.3 AND n ≥ 20 이 아니면 .unknown.
    private var runningStyleClassification: RunningStyle {
        guard !isInterval, !isLongDistanceContext,
              let bb,
              let r = bb.cadenceStrideR, r <= -0.3,
              bb.sampleCount >= 20,
              let cad = avgCadence,
              let str = avgStrideLength,
              let cadStat = bb.cadence,
              let strStat = bb.strideLength
        else { return .unknown }

        let cadResidual = Double(cad) - cadStat.median
        let strResidual = str - strStat.median

        if let p90 = bb.cadenceResidualP90, let p25 = bb.strideResidualP25,
           cadResidual >= p90 && strResidual <= p25 { return .quickStep }
        if let p10 = bb.cadenceResidualP10, let p75 = bb.strideResidualP75,
           cadResidual <= p10 && strResidual >= p75 { return .bigStride }
        return .normal
    }

    // 주법 유형 라벨(잔발형/큰보폭형)을 표시하지 않는 이유:
    // - Patoz 2019의 유형 판정 밴드는 듀티팩터 27.6~28.8% (폭 1.2%p)
    // - 애플워치 접지시간 MAPE 약 19% → 듀티팩터 오차 ±5.3%p = 밴드의 4.4배
    //   즉 측정 정밀도가 판정 밴드보다 훨씬 커서 유형을 구분할 수 없다
    // - Patoz 2022 (n=52)은 어떤 주법 패턴도 더 경제적이지 않다고 결론
    // 따라서 "당신은 ○○형입니다"라는 판정은 하지 않고,
    // 관찰된 사실만 서술한다 ("이 페이스에서 평소보다 걸음이 잦았어요")

    // MARK: - Insight Slot

    private func paceString(_ secPerKm: Double) -> String {
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d'%02d\"", m, s)
    }

    private func trendInsightText(_ realShifts: [MRFormShift]) -> String {
        let L = AppLanguage.shared
        guard let shift = realShifts.first else { return "" }
        let weeks = shift.weeksConsistent
        let suffix = L.s("\(weeks)주째 ", "for \(weeks) wks ")
        switch shift.metric.key {
        case "vo":
            return shift.delta > 0
                ? L.s("위아래 움직임이 \(suffix)커지고 있어요.", "Vertical oscillation has been \(suffix)increasing.")
                : L.s("위아래 움직임이 \(suffix)줄어들고 있어요.", "Vertical oscillation has been \(suffix)decreasing.")
        case "cadence":
            return shift.delta > 0
                ? L.s("케이던스가 \(suffix)높아지고 있어요.", "Cadence has been \(suffix)increasing.")
                : L.s("케이던스가 \(suffix)낮아지고 있어요.", "Cadence has been \(suffix)decreasing.")
        case "gct":
            return shift.delta > 0
                ? L.s("지면접촉이 \(suffix)길어지고 있어요.", "Ground contact has been \(suffix)increasing.")
                : L.s("지면접촉이 \(suffix)짧아지고 있어요.", "Ground contact has been \(suffix)decreasing.")
        default:
            return L.s("주법 지표에 변화가 있어요.", "A form metric is shifting.")
        }
    }

    private var formInsights: [FormInsightItem] {
        let L = AppLanguage.shared
        var items: [FormInsightItem] = []

        // [96] 장거리 폼 변화 지점 — 거리문맥일 때만, 가장 먼저 삽입 ([97]: 거리문맥에도 표시)
        if let changeItem = longDistanceFormChangeInsight {
            items.append(changeItem)
        }

        // [기온] 야외(temp != nil) AND (temp ≥ 25 OR ≤ 5)
        // · 더위(≥25°C): 개인 모델로 보정 페이스 문장
        // · 추위(≤5°C): bCold 미신뢰 — 보정 문장 없음, 사실 한 줄만
        //   tempExtreme(하위 5%)가 DetailInsight에서 이미 발화 중이면 폼 카드 침묵
        // [날씨] 비 — 기온 슬롯과 동시에 뜨면 합치고, 기온 없으면 별도 슬롯
        let isRainy = weatherSnapshot?.isRainy == true
        var tempFired = false
        if let temp = activity.temperatureC, (temp >= 25 || temp <= 5) {
            if temp >= 25,
               let model = heatModel, model.ok,
               let pace = activity.paceSecPerKm {
                // 더위 보정 — 기존 로직
                let corrected = pace * exp(model.logDelta(temp))
                let diff = pace - corrected   // 양수 = 교정 페이스가 빠름
                if diff >= 5 {
                    tempFired = true
                    let refStr = paceString(corrected)
                    let tempStr = String(format: "%.1f", temp)
                    let text: String
                    if isRainy {
                        text = L.s(
                            "\(tempStr)°C에 비까지 왔어요. 시원한 날이었다면 같은 노력으로 \(refStr) 정도 나왔을 거예요.",
                            "You ran in \(tempStr)°C rain. On a cooler day, same effort might have produced \(refStr).")
                    } else {
                        text = L.s(
                            "\(tempStr)°C에서 뛰었어요. 시원한 날이었다면 같은 노력으로 \(refStr) 정도 나왔을 거예요.",
                            "You ran at \(tempStr)°C. On a cooler day, the same effort might have produced a \(refStr) pace.")
                    }
                    items.append(FormInsightItem(
                        id: .temperature,
                        badgeText: L.s(isRainy ? "기온·날씨" : "기온", isRainy ? "Temp & Rain" : "Heat"),
                        bodyText: text,
                        badgeColor: Color(hex: "FF8C42")))
                }
            } else if temp <= 5 {
                // 추위 — bCold 계수 미신뢰, 보정 문장 없음
                let sortedTemps = historicalTemperatures.sorted()
                // InsightEngine tempExtreme: 하위 5% → 같은 사실을 DetailInsight가 이미 발화 중 → 침묵
                let isTempExtremeFiring = sortedTemps.count >= 20
                    && Double(sortedTemps.filter { $0 <= temp }.count) / Double(sortedTemps.count) <= 0.05
                #if DEBUG
                let tempInt = Int(temp.rounded())
                if isTempExtremeFiring {
                    print("[기온] \(tempInt)°C · tempExtreme 발화 중 → 폼 카드 기온 슬롯 침묵")
                } else {
                    print("[기온] \(tempInt)°C · 기준 15°C 미만 → 보정 문장 생략 (추위 계수 미신뢰)")
                }
                #endif
                if !isTempExtremeFiring {
                    tempFired = true
                    let tempInt = Int(temp.rounded())
                    let baseLine = isRainy
                        ? L.s("\(tempInt)°C에 비까지 왔어요.", "You ran in \(tempInt)°C rain.")
                        : L.s("\(tempInt)°C에서 뛰었어요.", "You ran at \(tempInt)°C.")
                    // 사실 문맥 — 인과 없음
                    let contextLine: String = {
                        guard sortedTemps.count >= 5 else { return "" }
                        let pct = Double(sortedTemps.filter { $0 <= temp }.count) / Double(sortedTemps.count)
                        if temp < 0 {
                            let subZeroCount = sortedTemps.filter { $0 < 0 }.count
                            if subZeroCount > 0 {
                                return L.s("최근 기록 중 영하 러닝은 \(subZeroCount)번이에요.",
                                           "\(subZeroCount) sub-zero run(s) in your history.")
                            }
                        } else if pct <= 0.20 {
                            return L.s("최근 기록 중 가장 추운 축이에요.",
                                       "One of your coldest runs on record.")
                        }
                        return ""
                    }()
                    let text = contextLine.isEmpty ? baseLine : "\(baseLine) \(contextLine)"
                    items.append(FormInsightItem(
                        id: .temperature,
                        badgeText: L.s(isRainy ? "기온·날씨" : "기온", isRainy ? "Temp & Rain" : "Cold"),
                        bodyText: text,
                        badgeColor: Color(hex: "6BAED6")))
                }
            }
        }
        if !tempFired, isRainy, items.count < 3 {
            let text = L.s(
                "비 오는 날이었어요. 노면이 젖으면 지면접촉과 페이스가 평소와 달라질 수 있어요.",
                "It was raining. Wet pavement can affect ground contact and pace.")
            items.append(FormInsightItem(
                id: .weather,
                badgeText: L.s("날씨", "Weather"),
                bodyText: text,
                badgeColor: Color(hex: "6BAED6")))
        }

        // [추세] 공백이 있으면 hasRecentGap=true → mrFormObservation 내에서 nil 반환
        if let obs = mrFormObservation(formShifts, hasRecentGap: hasRecentGap, refCadence: avgCadence,
                                       runCadenceResidual: runCadenceResidual), items.count < 3 {
            items.append(FormInsightItem(id: .trend,
                                         badgeText: L.s("추세", "Trend"),
                                         bodyText: obs.text,
                                         badgeColor: Theme.positive))
        }

        // [거리] distance ≥ 4주 평균 × 130%
        if let typical = typicalDistanceKm, typical > 0,
           (activity.distance / 1000) >= typical * 1.30,
           items.count < 3 {
            let distKm = activity.distance / 1000
            let ratio  = distKm / typical
            let text = L.s(
                "\(String(format: "%.1f", distKm))km는 평소(\(String(format: "%.1f", typical))km)의 \(String(format: "%.1f", ratio))배예요.",
                "\(String(format: "%.1f", distKm)) km is \(String(format: "%.1f", ratio))× your usual \(String(format: "%.1f", typical)) km.")
            items.append(FormInsightItem(id: .distance,
                                         badgeText: L.s("거리", "Distance"),
                                         bodyText: text,
                                         badgeColor: Color(hex: "6BAED6")))
        }

        // [케이던스 U자] 같은 페이스에서 심박 최저 케이던스 추정 (우선순위 4위)
        if let item = cadenceHRInsight, items.count < 3 {
            items.append(item)
        }

        // [주법] 평소 대비 걸음수/보폭 관찰 — 유형 라벨 없이 사실만
        let style = runningStyleClassification
        if (style == .quickStep || style == .bigStride), items.count < 3 {
            let text: String
            switch style {
            case .quickStep:
                text = L.s("평소보다 발걸음이 빠르고 보폭이 짧았어요.", "Cadence was higher and stride shorter than usual.")
            case .bigStride:
                text = L.s("평소보다 보폭이 크고 발걸음이 느렸어요.", "Stride was longer and cadence slower than usual.")
            default:
                text = ""
            }
            items.append(FormInsightItem(id: .style,
                                         badgeText: L.s("걸음수/보폭", "Stride"),
                                         bodyText: text,
                                         badgeColor: Theme.groundContact))
        }

        // 총 4줄 상한: 논리적 줄 수 합산 후 초과하면 낮은 우선순위부터 제거
        while items.map({ $0.bodyText.components(separatedBy: "\n").count }).reduce(0, +) > 4, !items.isEmpty {
            items.removeLast()
        }

        // [107] 후보 0개면 측정값 폴백 — 해석 없이 사실만
        if items.isEmpty {
            let distKm  = activity.distance / 1000
            let distStr = String(format: "%.1f", distKm)
            var text: String
            if let pace = activity.paceSecPerKm, pace > 0 {
                let i = Int(pace.rounded())
                let pStr = "\(i / 60)'\(String(format: "%02d", i % 60))\""
                text = L.s("\(distStr)km를 \(pStr) 페이스로 달렸어요.",
                           "You ran \(distStr) km at \(pStr)/km.")
            } else {
                text = L.s("\(distStr)km를 달렸어요.", "You ran \(distStr) km.")
            }
            // 가장 큰 후반 변화 지표 한 줄 추가 (있으면)
            let all = formSeriesCache.isEmpty ? formSeries : formSeriesCache
            let notableChange: String? = all.compactMap { s -> (MetricDir, Double, Double)? in
                guard let f = s.firstAvg, let sec = s.secondAvg, f > 0 else { return nil }
                return (s.dir, f, sec)
            }.max(by: { abs($0.2 - $0.1) / $0.1 < abs($1.2 - $1.1) / $1.1 }).flatMap { dir, f, sec in
                let diff = sec - f
                let absDiff = abs(diff)
                switch dir {
                case .cadence:
                    guard absDiff >= 2 else { return nil }
                    let d = String(format: "%.0f", absDiff)
                    return diff < 0
                        ? L.s("케이던스가 후반에 \(d)spm 낮아졌어요.", "Cadence was \(d) spm lower in the second half.")
                        : L.s("케이던스가 후반에 \(d)spm 높아졌어요.", "Cadence was \(d) spm higher in the second half.")
                case .groundContact:
                    guard absDiff >= 5 else { return nil }
                    let d = String(format: "%.0f", absDiff)
                    return diff < 0
                        ? L.s("지면접촉이 후반에 \(d)ms 짧아졌어요.", "Ground contact was \(d) ms shorter in the second half.")
                        : L.s("지면접촉이 후반에 \(d)ms 길어졌어요.", "Ground contact was \(d) ms longer in the second half.")
                case .stride:
                    guard absDiff >= 0.03 else { return nil }
                    let d = String(format: "%.2f", absDiff)
                    return diff < 0
                        ? L.s("보폭이 후반에 \(d)m 짧아졌어요.", "Stride was \(d) m shorter in the second half.")
                        : L.s("보폭이 후반에 \(d)m 길어졌어요.", "Stride was \(d) m longer in the second half.")
                case .verticalOsc:
                    guard absDiff >= 0.3 else { return nil }
                    let d = String(format: "%.1f", absDiff)
                    return L.s("수직진폭이 후반에 \(d)cm 변했어요.", "Vertical oscillation changed by \(d) cm.")
                }
            }
            if let change = notableChange { text += " " + change }
            items.append(FormInsightItem(id: .trend,
                                         badgeText: L.s("기록", "Stats"),
                                         bodyText: text,
                                         badgeColor: Color.white.opacity(0.58)))
            #if DEBUG
            print("[인사이트] 표시 0개 → 폴백: \(text)")
            #endif
        }

        return Array(items.prefix(3))
    }

    // MARK: - Long-Distance Form Change Insight [96]

    /// 거리문맥 러닝에서 케이던스·보폭·지면접촉이 평소 범위를 벗어난 첫 버킷을 찾아
    /// 관찰 문구를 생성한다. 세 지표 모두 범위 안이면 nil.
    private var longDistanceFormChangeInsight: FormInsightItem? {
        // 3단계 폼 문장이 나오면 이탈 위치까지 그 문장이 말한다 — 같은 사실을 두 번 적지 않는다.
        guard isLongDistanceContext, formPhaseResult == nil else { return nil }
        let L = AppLanguage.shared
        let all = formSeriesCache.isEmpty ? formSeries : formSeriesCache

        struct BandExit {
            let dir: MetricDir
            let kmStart: Double   // 버킷 시작 km
            let kmEnd: Double     // 버킷 끝 km
        }
        var exits: [BandExit] = []
        // [103] 전체 거리의 40% 이전 이탈은 "처음부터 다른 값" — 변화 판정 제외
        let totalKm = activity.distance / 1000
        let minKmForChange = totalKm * 0.40

        for s in all {
            guard s.dir != .verticalOsc else { continue }
            guard let bandLo = s.bandLo, let bandHi = s.bandHi,
                  !s.points.isEmpty else { continue }
            for (i, pt) in s.points.enumerated() {
                let exited: Bool
                switch s.dir {
                case .cadence, .stride:   exited = pt.value < bandLo
                case .groundContact:       exited = pt.value > bandHi
                case .verticalOsc:         exited = false
                }
                if exited {
                    let start = i > 0 ? s.points[i - 1].kmEnd : 0.0
                    guard start >= minKmForChange else { break }  // [103] 초반 이탈 제외
                    exits.append(BandExit(dir: s.dir, kmStart: start, kmEnd: pt.kmEnd))
                    break
                }
            }
        }

        guard !exits.isEmpty else { return nil }
        let sorted = exits.sorted { $0.kmStart < $1.kmStart }

        // 문구 — 관찰+위치만, 원인 표현 없음 [96 ⚠️]
        let lines: [String] = sorted.enumerated().compactMap { idx, e in
            let km = Int(e.kmStart.rounded())
            switch e.dir {
            case .cadence:
                return idx == 0
                    ? L.s("\(km)km 지점부터 케이던스가 평소 범위 아래로 내려갔어요.",
                          "From \(km) km, cadence dropped below its normal range.")
                    : L.s("케이던스는 \(km)km부터였어요.", "Cadence from \(km) km.")
            case .stride:
                return idx == 0
                    ? L.s("\(km)km 지점부터 보폭이 평소 범위 아래로 내려갔어요.",
                          "From \(km) km, stride length dropped below its normal range.")
                    : L.s("보폭은 \(km)km부터였어요.", "Stride from \(km) km.")
            case .groundContact:
                return idx == 0
                    ? L.s("\(km)km 지점부터 지면접촉이 평소 범위 위로 올라갔어요.",
                          "From \(km) km, ground contact time rose above its normal range.")
                    : L.s("지면접촉은 \(km)km부터였어요.", "Ground contact from \(km) km.")
            case .verticalOsc:
                return nil
            }
        }
        guard !lines.isEmpty else { return nil }

        return FormInsightItem(
            id: .formChange,
            badgeText: L.s("폼 변화", "Form Shift"),
            bodyText: lines.joined(separator: "\n"),
            badgeColor: Theme.groundContact)
    }

    // MARK: - Cadence-HR U-Curve Insight

    /// 케이던스–심박 U자 곡선 인사이트. 글로벌 조건 + 퍼액티비티 조건 모두 통과 시 반환.
    private var cadenceHRInsight: FormInsightItem? {
        guard !isInterval,
              let diag = baseline?.cadenceHRDiag,
              diag.isGloballyValid,
              let vertex = diag.vertexResidual,
              let bb = bb,
              let cadStat = bb.cadence,
              let actCad = avgCadence
        else { return nil }

        let optimalCadence = Int((cadStat.median + vertex).rounded())

        // 퍼액티비티 조건
        guard abs(optimalCadence - actCad) >= 2 else { return nil }
        guard optimalCadence >= 160, optimalCadence <= 190 else { return nil }

        let L = AppLanguage.shared
        let direction = optimalCadence > actCad
            ? L.s("조금 높은", "slightly higher")
            : L.s("조금 낮은", "slightly lower")
        let body = L.s(
            "같은 페이스에서 케이던스 \(optimalCadence) 근처일 때 심박이 가장 낮았어요. 지금보다 \(direction) 편이 효율적일 수 있어요.",
            "HR was lowest around a cadence of \(optimalCadence) at the same pace. A \(direction) cadence than now may be more efficient."
        )
        return FormInsightItem(id: .cadenceHR,
                               badgeText: L.s("케이던스", "Cadence"),
                               bodyText: body,
                               badgeColor: Color(hex: "4ECDC4"))
    }

    private var chainChildren: [ChainChild] {
        let L = AppLanguage.shared
        var items: [ChainChild] = []
        var n = 0
        // 바에 그릴 밴드는 표시용(displayBb) — 구간 밖이면 가장 가까운 구간을 참고로 빌린다
        if let sl = avgStrideLength {
            items.append(ChainChild(id: n, label: L.s("보폭", "Stride"),
                rawValue: sl, formatted: String(format: "%.2f", sl), unit: "m",
                stat: displayBb?.strideLength, dir: .stride, isRef: false)); n += 1
        }
        if let gct = avgGroundContactTime {
            items.append(ChainChild(id: n, label: L.s("지면접촉", "GCT"),
                rawValue: gct, formatted: String(format: "%.0f", gct), unit: "ms",
                stat: displayGctStat, dir: .groundContact, isRef: false)); n += 1
        }
        if let vo = avgVerticalOscillation {
            items.append(ChainChild(id: n, label: L.s("수직진폭", "Vert Osc"),
                rawValue: vo, formatted: String(format: "%.1f", vo), unit: "cm",
                stat: displayBb?.verticalOsc, dir: .verticalOsc, isRef: true))
        }
        return items
    }

    // MARK: - Display Rounding Helpers

    private func roundedDisplay(_ v: Double, dir: MetricDir) -> Double {
        FormNarrative.roundedDisplay(v, metric: dir)
    }

    private func metricFmt(_ v: Double, dir: MetricDir) -> String {
        switch dir {
        case .cadence:       return String(format: "%.0f", v)
        case .stride:        return String(format: "%.2f", v)
        case .groundContact: return String(format: "%.0f", v)
        case .verticalOsc:   return String(format: "%.1f", v)
        }
    }

    private func metricStatus(rawValue: Double, stat: FormStat?, dir: MetricDir) -> MetricStatus {
        FormNarrative.status(rawValue: rawValue, stat: stat, metric: dir)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topSummary
            divider
            if isInterval {
                if intervalSegments.contains(where: { $0.stepLabel == "운동" }) {
                    IntervalFatigueCard(segments: intervalSegments,
                                       hrSamples: hrSamples,
                                       workoutStart: activity.date)
                }
            } else {
                causalChain
                divider
                formInsightSection
                if showTrendSection {
                    splitFormTrendSection
                    if let phase = formPhaseResult {
                        Text(FormPhase.sentence(phase, isLongDistance: isLongDistanceContext))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.white.opacity(0.80))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            formSeriesCache = formSeries  // 버킷 1회 계산 → 이후 재사용
            logDistanceContext()
            logChain()
            logTrend()
            logStyleClassification()
            logInsightSlot()
            logUCurve()
            logRangeBar()
            logLongDistanceChange()
            logGctCorrection()
        }
        .onChange(of: formShifts.count) { _, _ in
            #if DEBUG
            // formShifts는 async 완료 후 설정됨 — onAppear 이후 도착하면 재로그
            logInsightSlot()
            logGctCorrection()
            #endif
        }
    }

    // MARK: - Top Summary

    private var topSummary: some View {
        let km = activity.distance / 1000
        let kmStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(kmStr)
                    .font(cardNumFont(40))
                    .tracking(-1.6)
                Text("km")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "8A8F99"))
            }
            .foregroundStyle(Color.white)
            HStack(spacing: 0) {
                KPICell(label: AppLanguage.shared.s("시간", "Time"),
                        value: activity.formattedDuration)
                kpiSep
                KPICell(label: AppLanguage.shared.s("페이스", "Pace"),
                        value: activity.formattedPace ?? "--'--\"",
                        context: flatEquivalentText, contextColor: Color.white.opacity(0.58))
                if let cad = avgCadence {
                    kpiSep
                    KPICell(label: AppLanguage.shared.s("케이던스", "Cadence"),
                            value: "\(cad)", unit: "spm",
                            color: Theme.cadence,
                            context: isInterval ? AppLanguage.shared.s("전력 구간", "work segs") : nil)
                }
                if let sl = avgStrideLength {
                    kpiSep
                    KPICell(label: AppLanguage.shared.s("보폭", "Stride"),
                            value: String(format: "%.2f", sl), unit: "m",
                            color: Color.white)
                }
            }
        }
    }

    // MARK: - Causal Chain

    @ViewBuilder
    private var causalChain: some View {
        let L = AppLanguage.shared
        let children = chainChildren
        VStack(alignment: .leading, spacing: 0) {
            if let cad = avgCadence {
                rootNodeView(label: isInterval ? L.s("케이던스 (전력)", "Cadence (work)") : L.s("케이던스", "Cadence"),
                             rawValue: Double(cad), formatted: "\(cad)", unit: "spm",
                             stat: (isReferenceBand || bb?.isJudgeable == true) ? displayBb?.cadence : nil,
                             dir: .cadence)
            }
            ForEach(children) { child in
                connectorView
                childNodeView(child: child)
            }
            // [70] 범위 바 설명: 바 아래, 축 시작 x에 맞춰 들여씀
            if let summary = barSummaryText() {
                Color.clear.frame(height: 5)
                HStack(spacing: 0) {
                    Color.clear.frame(width: barTextColumnWidth + 8)
                    Text(summary)
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineSpacing(2.5)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            if let paceStr = activity.formattedPace {
                resultArrowView
                resultNodeView(label: L.s("페이스", "Pace"), value: paceStr)
            }
            if let sentence = narrative {
                Color.clear.frame(height: 10)
                Text(sentence)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Chain Node Views

    /// 행 라벨의 지표 색 — 지표 격자와 같은 규칙(라벨에 색, 값은 흰색).
    /// 같은 색을 쓰는 아래 미니 차트와 "이 행 ↔ 이 차트"로 묶인다. 상단 KPI 행은 값에 색을 주는
    /// 기존 규칙을 그대로 둔다(숫자가 주인공인 행).
    private func metricLabelColor(_ dir: MetricDir) -> Color {
        switch dir {
        case .cadence:       return Theme.cadence
        case .stride:        return Theme.strideLength
        case .groundContact: return Theme.groundContact
        case .verticalOsc:   return Theme.verticalOsc
        }
    }

    private func rootNodeView(label: String, rawValue: Double, formatted: String,
                              unit: String, stat: FormStat?, dir: MetricDir) -> some View {
        // [57] 텍스트 열을 barTextColumnWidth로 고정 → 네 줄 바가 같은 x에서 시작
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(metricLabelColor(dir)).lineLimit(1)
                    Text(formatted).font(cardNumFont(22)).foregroundStyle(Color.white).lineLimit(1)
                    Text(unit).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.58)).lineLimit(1)
                }
            }
            .frame(width: barTextColumnWidth, alignment: .leading)
            if !isInterval, let stat {
                rangeBarView(rawValue: rawValue, stat: stat, dir: dir,
                             dotValues: recentDotsForBand(dir: dir),
                             totalSamples: displayBb?.sampleCount ?? 0,
                             bandName: displayBb?.band.rawValue ?? "",
                             isReference: isReferenceBand)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func childNodeView(child: ChainChild) -> some View {
        // 바 정렬: 들여쓰기를 내부 sub-HStack에 격리하고 바는 바깥 HStack에 배치
        // → 루트 노드와 동일한 x 위치에 바가 정렬됨
        // [57] 들여쓰기 포함한 텍스트 열을 barTextColumnWidth로 고정
        HStack(alignment: .top, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: 14)
                    .overlay {
                        Rectangle().fill(lineColor).frame(width: 0.5).frame(width: 14, alignment: .center)
                    }
                Color.clear.frame(width: 6)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(child.label).font(.system(size: 10, weight: .medium)).foregroundStyle(metricLabelColor(child.dir)).lineLimit(1)
                        Text(child.formatted)
                            .font(cardNumFont(20))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        Text(child.unit).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.58)).lineLimit(1)
                    }
                }
            }
            .frame(width: barTextColumnWidth, alignment: .leading)
            if !isInterval, let stat = child.stat {
                rangeBarView(rawValue: child.rawValue, stat: stat, dir: child.dir,
                             dotValues: recentDotsForBand(dir: child.dir),
                             totalSamples: displayBb?.sampleCount ?? 0,
                             bandName: displayBb?.band.rawValue ?? "",
                             isReference: isReferenceBand)
                    .frame(maxWidth: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var connectorView: some View {
        HStack(spacing: 0) {
            ZStack {
                Rectangle().fill(lineColor).frame(width: 0.5, height: 14).frame(width: 14, alignment: .center)
                Rectangle().fill(lineColor).frame(width: 8, height: 0.5).frame(width: 14, alignment: .trailing)
            }
            .frame(width: 14, height: 14)
            Spacer()
        }
    }

    private var resultArrowView: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .top) {
                Rectangle().fill(lineColor).frame(width: 0.5, height: 12).frame(width: 14, alignment: .center)
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 8, weight: .thin)).foregroundStyle(lineColor)
                    .frame(width: 14, alignment: .center).padding(.top, 10)
            }
            .frame(width: 14, height: 18)
            Spacer()
        }
    }

    private func resultNodeView(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.62))
            Text(value).font(cardNumFont(26)).foregroundStyle(Theme.violet)
        }
    }

    // MARK: - Range Bar

    /// 범위 바 히스토리 점: baseline.allFormSamples에서 열람 러닝 이전 12개월 · 같은 페이스 구간 · 거리 0.5~2배 필터 후 최신 5개.
    private func recentDotsForBand(dir: MetricDir) -> [Double] {
        // 참고 밴드일 땐 점을 찍지 않는다 — 구간 밖 러닝들은 페이스가 제각각이라
        // 산포만 커져 축이 늘어나고(띠가 눌린다) 오늘 점이 과거 점에 묻힌다.
        guard !isReferenceBand else { return [] }
        guard let baseline = baseline, !baseline.allFormSamples.isEmpty else { return [] }
        guard let actPace = activity.paceSecPerKm else { return [] }
        let actBand = baseline.cutoffs.band(of: actPace)
        let todayDist = activity.distance
        let viewDate = activity.date
        let cal = Calendar.current
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: viewDate) ?? .distantPast
        let filtered = baseline.allFormSamples.filter { s in
            guard s.distanceM > 0, todayDist > 0 else { return false }
            // 자신 제외
            if cal.isDate(s.date, inSameDayAs: viewDate) { return false }
            // 열람 러닝 이전 12개월
            if s.date >= viewDate { return false }
            if s.date < oneYearAgo { return false }
            // 같은 페이스 구간
            guard baseline.cutoffs.band(of: s.paceSecPerKm) == actBand else { return false }
            // 거리 0.5~2배
            let ratio = todayDist / s.distanceM
            return ratio >= 0.5 && ratio <= 2.0
        }
        return filtered.prefix(5).compactMap { s -> Double? in
            switch dir {
            case .cadence:       return s.cadence.map(Double.init)
            case .stride:        return s.strideLength
            case .groundContact: return s.groundContactTime
            case .verticalOsc:   return s.verticalOscillation
            }
        }
    }

    private func rangeBarView(rawValue: Double, stat: FormStat, dir: MetricDir,
                              dotValues: [Double], totalSamples: Int, bandName: String,
                              isReference: Bool = false) -> some View {
        let bandLo = roundedDisplay(stat.lower, dir: dir)
        let bandHi = roundedDisplay(stat.upper, dir: dir)
        let rv     = roundedDisplay(rawValue, dir: dir)
        let loStr  = metricFmt(bandLo, dir: dir)
        let hiStr  = metricFmt(bandHi, dir: dir)

        // [87] 축 범위: 평소 범위가 약 75% 차지 (최소 폭 1.3배, 여백 8%)
        //   → 범위 밖 점도 잘리지 않고, 밴드가 넓게 표시됨
        let allVals: [Double] = [bandLo, bandHi, rv] + dotValues
        let rawLo = allVals.min() ?? bandLo
        let rawHi = allVals.max() ?? bandHi
        let bandWidth = max(bandHi - bandLo, 0.001)
        let minSpan = bandWidth * 1.3
        var axisLo: Double
        var axisHi: Double
        if rawHi - rawLo < minSpan {
            let center = (rawLo + rawHi) / 2
            axisLo = center - minSpan / 2
            axisHi = center + minSpan / 2
        } else {
            axisLo = rawLo
            axisHi = rawHi
        }
        let axisSpan = axisHi - axisLo
        axisLo -= axisSpan * 0.08
        axisHi += axisSpan * 0.08

        let green: Color = Theme.positive
        let neutral: Color = Color.white.opacity(0.70)
        let dotColor: Color = {
            // [76] 범위 안 + 개선 방향 벗어남 = 녹색. 반대 방향만 회색.
            // [79] 거리 문맥은 색에 영향 없음 — 색은 판정이 아니라 "범위 안" 사실 표시
            // 참고 밴드(다른 페이스대)일 땐 색으로 판정하지 않는다 — 항상 중립
            if isReference { return neutral }
            switch dir {
            case .cadence:
                return rv >= bandLo ? green : neutral
            case .groundContact, .verticalOsc:
                // 지면접촉·수직진폭은 낮을수록 좋은 쪽 — 범위 아래로 벗어나도 녹색 (범례와 일치)
                return rv <= bandHi ? green : neutral
            case .stride:
                return rv >= bandLo && rv <= bandHi ? green : neutral
            }
        }()
        // [94] 인라인 로그 제거 — 뷰 재렌더마다 반복 출력됨. logRangeBar()에서 onAppear 1회 출력.

        // [61] 줄별 라벨 삭제 — 카드 하단에 barSummaryText()로 통합

        return VStack(alignment: .leading, spacing: 1) {
            // [55] 축 숫자를 Canvas symbols로 평소 범위 끝 x에 정렬
            Canvas { ctx, size in
                let w = size.width
                guard w > 0, bandHi > bandLo, axisHi > axisLo else { return }
                let barL: CGFloat = 4
                let barR: CGFloat = w - 4
                let barW = barR - barL
                let axisRange = axisHi - axisLo
                let barY: CGFloat = 7

                let posX = { (v: Double) -> CGFloat in
                    barL + CGFloat((v - axisLo) / axisRange) * barW
                }
                let bandLoX = posX(bandLo)
                let bandHiX = posX(bandHi)

                // [63] 전체 축: 배경에 가까운 수준 — 눈금판 역할만
                var fullLine = Path()
                fullLine.move(to: CGPoint(x: barL, y: barY))
                fullLine.addLine(to: CGPoint(x: barR, y: barY))
                ctx.stroke(fullLine, with: .color(.white.opacity(0.04)), lineWidth: 0.5)
                for x in [barL, barR] {
                    var cap = Path()
                    cap.move(to: CGPoint(x: x, y: barY - 2.5))
                    cap.addLine(to: CGPoint(x: x, y: barY + 2.5))
                    ctx.stroke(cap, with: .color(.white.opacity(0.07)), lineWidth: 1)
                }

                // [63] 평소 범위: 훨씬 밝고 굵게 — 축과 두 단계 이상 대비
                // 참고 밴드는 점선 + 낮은 명도 — "내 페이스대 기준"과 시각적으로 구분
                var bandLine = Path()
                bandLine.move(to: CGPoint(x: bandLoX, y: barY))
                bandLine.addLine(to: CGPoint(x: bandHiX, y: barY))
                ctx.stroke(bandLine,
                           with: .color(.white.opacity(isReference ? 0.32 : 0.55)),
                           style: isReference
                               ? StrokeStyle(lineWidth: 2, dash: [2.5, 2.5])
                               : StrokeStyle(lineWidth: 2.5))
                for x in [bandLoX, bandHiX] {
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: barY - 4))
                    tick.addLine(to: CGPoint(x: x, y: barY + 4))
                    ctx.stroke(tick,
                               with: .color(.white.opacity(isReference ? 0.45 : 0.72)),
                               lineWidth: isReference ? 2 : 2.5)
                }

                // [52] 히스토리 점: 같은 y, 가까운 점끼리 가로 흩뿌림
                let todayX = posX(rv)
                var jxs: [CGFloat] = dotValues.map { posX($0) }
                let jThr: CGFloat = 6; let jOfs: CGFloat = 3.5
                for i in 0..<jxs.count {
                    for j in (i+1)..<jxs.count where abs(jxs[j] - jxs[i]) < jThr {
                        let mid = (jxs[i] + jxs[j]) / 2
                        jxs[i] = mid - jOfs; jxs[j] = mid + jOfs
                    }
                }
                for i in 0..<jxs.count where abs(jxs[i] - todayX) < jThr {
                    jxs[i] = todayX + (i % 2 == 0 ? -jOfs : jOfs)
                }
                for hx in jxs {
                    let r: CGFloat = 3.5
                    ctx.stroke(Path(ellipseIn: CGRect(x: hx-r, y: barY-r, width: r*2, height: r*2)),
                               with: .color(.white.opacity(0.60)), lineWidth: 1.2)
                }
                // 오늘 값: 채운 원, 항상 최상단
                let tr: CGFloat = 4.5
                ctx.fill(Path(ellipseIn: CGRect(x: todayX-tr, y: barY-tr, width: tr*2, height: tr*2)),
                         with: .color(dotColor))

                // [55] lo/hi 숫자: 평소 범위 끝 눈금 아래 가운데 정렬
                if let loSym = ctx.resolveSymbol(id: 0) {
                    let cx = min(max(bandLoX, barL + 8), barR - 8)
                    ctx.draw(loSym, at: CGPoint(x: cx, y: barY + 7), anchor: .top)
                }
                if let hiSym = ctx.resolveSymbol(id: 1) {
                    let cx = min(max(bandHiX, barL + 8), barR - 8)
                    ctx.draw(hiSym, at: CGPoint(x: cx, y: barY + 7), anchor: .top)
                }
            } symbols: {
                // [74] 축 숫자: 설명 문구와 동일 크기/밝기
                Text(loStr).font(.system(size: 8)).foregroundStyle(Color.white.opacity(0.72)).tag(0)
                Text(hiStr).font(.system(size: 8)).foregroundStyle(Color.white.opacity(0.72)).tag(1)
            }
            .frame(height: 26)

        }
    }

    // MARK: - Form Insight Section

    @ViewBuilder
    private var formInsightSection: some View {
        let items = formInsights
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.badgeText)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(item.badgeColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(item.badgeColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(item.bodyText)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.80))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            divider
        }
    }

    // MARK: - Split Form Trend (2×2 Grid)

    @ViewBuilder
    private var splitFormTrendSection: some View {
        // formSeriesCache가 비면 ImageRenderer(onAppear 미호출) 상황 — 직접 계산 폴백
        let all = formSeriesCache.isEmpty ? formSeries : formSeriesCache
        let cadS  = all.first { $0.dir == .cadence }
        let gctS  = all.first { $0.dir == .groundContact }
        let slS   = all.first { $0.dir == .stride }
        let voS   = all.first { $0.dir == .verticalOsc }

        let hasTopRow    = cadS != nil || gctS != nil
        let hasBottomRow = slS  != nil || voS  != nil

        if hasTopRow || hasBottomRow {
            VStack(alignment: .leading, spacing: 10) {
                // Row 1: 판정 지표
                if hasTopRow {
                    HStack(alignment: .top, spacing: 10) {
                        if let s = cadS {
                            formSeriesCell(s).frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                        if let s = gctS {
                            formSeriesCell(s).frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                // Row 2: 참고 지표
                if hasBottomRow {
                    HStack(alignment: .top, spacing: 10) {
                        if let s = slS {
                            formSeriesCell(s).frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                        if let s = voS {
                            formSeriesCell(s).frame(maxWidth: .infinity)
                        } else {
                            // 진폭 데이터 없음 placeholder — 칸을 숨기면 레이아웃이 깨짐
                            voNoDataCell.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var voNoDataCell: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AppLanguage.shared.s("수직진폭", "Vert Osc"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.42))
            Text(AppLanguage.shared.s("데이터 없음", "No data"))
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.34))
                .frame(height: 52, alignment: .center)
        }
    }

    private func formSeriesCell(_ s: FormSeries) -> some View {
        let L = AppLanguage.shared
        // [65] km x축 계산
        let kmEnds = s.points.map(\.kmEnd)
        let lastKm = kmEnds.last ?? 1.0
        let half = s.points.count / 2
        let midKm: Double = {
            if half > 0, half < s.points.count {
                return (s.points[half - 1].kmEnd + s.points[half].kmEnd) / 2.0
            }
            return lastKm / 2.0
        }()
        // 3단계 문장이 있으면 50% 중앙선 대신 30%·70% 경계 2개
        let phaseMarkKms: [Double] = formPhaseResult.map { [$0.earlyEndKm, $0.lateStartKm] } ?? [midKm]
        let showEveryOther = kmEnds.count > 6
        var displayKms: [Double] = showEveryOther
            ? kmEnds.enumerated().compactMap { i, km in i % 2 == 0 ? km : nil }
            : kmEnds
        if showEveryOther, let lastKmVal = kmEnds.last, displayKms.last != lastKmVal {
            displayKms.append(lastKmVal)
            // [68] 직전 라벨과 너무 가까우면 직전 제거 (예: 14 · 15.5 → 15.5만 유지)
            if displayKms.count >= 3 {
                let normalStep = displayKms[displayKms.count - 2] - displayKms[displayKms.count - 3]
                let lastGap   = displayKms[displayKms.count - 1] - displayKms[displayKms.count - 2]
                if normalStep > 0, lastGap < normalStep * 0.65 {
                    displayKms.remove(at: displayKms.count - 2)
                }
            }
        }
        let kmStep = kmEnds.count > 1 ? (kmEnds[1] - kmEnds[0]) : 1.0
        // 마지막 라벨을 실제 총 거리 위치로 교체 — 버킷 끝(예: 4.5km)과 총 거리(예: 5km)가
        // 다르면 "4  5 km"이 겹쳐 보이는 현상 방지
        let totalKm = activity.distance / 1000
        if !displayKms.isEmpty {
            displayKms[displayKms.count - 1] = totalKm
            // 직전 라벨이 총 거리와 너무 가까우면 제거 (겹침 방지)
            if displayKms.count >= 2 {
                let gap = totalKm - displayKms[displayKms.count - 2]
                if gap < kmStep * 0.7 {
                    displayKms.remove(at: displayKms.count - 2)
                }
            }
        }
        let lastDisplayKm = displayKms.last ?? totalKm
        // 위치 0에 "km" 단위 레이블 삽입 — 숫자 레이블에 "km" 붙이지 않아 겹침 원천 차단
        let displayKmsWithUnit = [0.0] + displayKms
        let totalBuckets = s.totalSplitCount
        let dataCount = s.points.count

        return VStack(alignment: .leading, spacing: 4) {
            // [88] 제목 + 수치/추세 한 줄
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(s.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(1)
                if let f = s.firstAvg, let sec = s.secondAvg {
                    let missingRate = Double(totalBuckets - dataCount) / Double(max(1, totalBuckets))
                    if missingRate > 0.50 {
                        Text(L.s("데이터 부족", "Low data"))
                            .font(.system(size: 8))
                            .foregroundStyle(Color.white.opacity(0.42))
                    } else {
                        trendChangeBadge(dir: s.dir, unit: s.unit, firstAvg: f, secondAvg: sec)
                    }
                } else if s.bandLo != nil {
                    let bandLabel: String = {
                        // 오늘 페이스가 구간 밖 → 어느 구간을 빌려왔는지 명시
                        if s.bandIsReference, let b = displayBb?.band {
                            return L.s("\(bandDisplayName(b)) 구간 기준 (참고)",
                                       "\(bandDisplayName(b)) band (ref)")
                        }
                        if s.dir == .verticalOsc || isLongDistanceContext {
                            return L.s("평소 범위 (참고)", "Typical (ref)")
                        }
                        if s.bandIsJudgeable, let pLo = s.bandPaceMin, let pHi = s.bandPaceMax {
                            func pf(_ sec: Double) -> String {
                                let i = Int(sec.rounded())
                                return "\(i / 60)'\(String(format: "%02d", i % 60))\""
                            }
                            return L.s("평소 범위 (\(pf(pLo))~\(pf(pHi)) 러닝 \(s.bandSampleCount)회)",
                                       "Typical (\(pf(pLo))–\(pf(pHi)) · \(s.bandSampleCount) runs)")
                        }
                        if s.bandIsJudgeable {
                            return L.s("평소 범위 n=\(s.bandSampleCount)", "Typical n=\(s.bandSampleCount)")
                        }
                        return L.s("참고 범위 n=\(s.bandSampleCount)", "Ref range n=\(s.bandSampleCount)")
                    }()
                    Text(bandLabel)
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
                Spacer(minLength: 0)
                if dataCount < totalBuckets && totalBuckets > 0 {
                    Text("(\(dataCount)/\(totalBuckets))")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.36))
                }
            }

            // Sparkline chart
            Chart {
                // Normal-range band
                if let lo = s.bandLo, let hi = s.bandHi {
                    RectangleMark(
                        xStart: .value("", 0.0),
                        xEnd: .value("", max(lastKm + kmStep * 0.5, totalKm)),
                        yStart: .value("", lo),
                        yEnd: .value("", hi)
                    )
                    .foregroundStyle(Color.white.opacity(s.bandIsReference ? 0.05 : 0.08))
                }

                // 구간 경계 — 기본은 50% 중앙선, 3단계 문장이 있으면 30%·70%
                ForEach(phaseMarkKms, id: \.self) { km in
                    RuleMark(x: .value("", km))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                        .foregroundStyle(Color.white.opacity(0.15))
                }

                // Line
                ForEach(s.points) { pt in
                    LineMark(
                        x: .value("km", pt.kmEnd),
                        y: .value("val", pt.value)
                    )
                    .foregroundStyle(s.lineColor)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                }

                // In-range small dots
                ForEach(s.points.filter { !$0.outOfRange }) { pt in
                    PointMark(x: .value("km", pt.kmEnd), y: .value("val", pt.value))
                        .foregroundStyle(s.lineColor.opacity(Theme.sparkDotOpacity))
                        .symbolSize(Theme.sparkDotSize)
                }

                // Out-of-range: white halo then colored inner (장거리 문맥이면 OOB 강조 생략)
                if !isLongDistanceContext {
                    ForEach(s.points.filter(\.outOfRange)) { pt in
                        PointMark(x: .value("km", pt.kmEnd), y: .value("val", pt.value))
                            .foregroundStyle(Color.white)
                            .symbolSize(Theme.sparkHaloSize)
                    }
                    ForEach(s.points.filter(\.outOfRange)) { pt in
                        PointMark(x: .value("km", pt.kmEnd), y: .value("val", pt.value))
                            .foregroundStyle(s.lineColor)
                            .symbolSize(Theme.sparkHaloCoreSize)
                    }
                }
            }
            .chartYScale(domain: s.yDomain)
            .chartXScale(domain: 0...max(lastKm + kmStep * 0.5, totalKm))
            .chartXAxis {
                AxisMarks(values: displayKmsWithUnit) { val in
                    if let v = val.as(Double.self) {
                        let isUnit = v < 0.01   // position 0 → "km" 단위 표시
                        let isLast = !isUnit && abs(v - lastDisplayKm) < 0.01
                        if isUnit {
                            // "km" 단위 레이블: 맨 앞에 한번만, 숫자와 겹침 없음
                            AxisValueLabel(anchor: .topLeading) {
                                Text("km")
                                    .font(.system(size: 7))
                                    .foregroundStyle(Color.white.opacity(0.42))
                            }
                        } else {
                            let fmtKm = v.truncatingRemainder(dividingBy: 1) < 0.05
                                ? String(format: "%.0f", v)
                                : String(format: "%.1f", v)
                            if isLast {
                                AxisValueLabel(anchor: .topTrailing) {
                                    Text(fmtKm)
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.white.opacity(0.68))
                                }
                            } else {
                                AxisValueLabel(centered: false) {
                                    Text(fmtKm)
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.white.opacity(0.68))
                                }
                            }
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 52)

            if isLongDistanceContext, let bandLo = s.bandLo {
                let belowCount = s.points.filter { $0.value < bandLo }.count
                if s.points.count > 0, Double(belowCount) / Double(s.points.count) >= 0.30 {
                    Text(FormNarrative.belowRangeNote(type: workoutType, metric: s.dir))
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
            }
        }
    }

    private func trendChangeBadge(dir: MetricDir, unit: String, firstAvg: Double, secondAvg: Double) -> some View {
        // 차이는 표시 정밀도로 반올림한 양끝의 차로 — 원값 차를 쓰면 0.91 → 0.92 (+0.02)처럼 어긋난다.
        let fmtNum: (Double) -> String = { v in metricFmt(v, dir: dir) }
        let first  = Double(fmtNum(firstAvg))  ?? firstAvg
        let second = Double(fmtNum(secondAvg)) ?? secondAvg
        let diff = second - first
        let diffUnit = dir == .groundContact ? "ms" : ""
        let sign: String = diff > 0.0005 ? "+" : diff < -0.0005 ? "−" : "±"
        let label = "\(fmtNum(first)) → \(fmtNum(second)) (\(sign)\(fmtNum(abs(diff)))\(diffUnit))"
        let green = Theme.positive
        let muted = Color.white.opacity(0.70)
        let color: Color
        switch dir {
        case .cadence:                     color = diff > 0.0005 ? green : muted
        case .groundContact, .verticalOsc: color = diff < -0.0005 ? green : muted
        default:                           color = muted
        }
        return Text(label)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(color)
    }

    // MARK: - Bar Summary

    /// [61] 범위 바 설명 — 카드 하단에 한 줄. 밴드 이름 대신 페이스 범위 사용.
    /// 오늘 페이스가 개인 페이스 구간 밖일 때의 범위 바 설명.
    /// "왜 판정이 없는지 + 지금 보이는 띠가 무엇인지"를 한 번에 알려준다.
    private func referenceBarSummaryText() -> String? {
        let L = AppLanguage.shared
        guard !isInterval, let ref = referenceBb, ref.sampleCount > 0,
              ref.paceMin > 0, ref.paceMax > 0 else { return nil }
        let name = bandDisplayName(ref.band)
        let pr   = abs(ref.paceMax - ref.paceMin) < 1
            ? paceStr(ref.paceMin)
            : "\(paceStr(ref.paceMin))~\(paceStr(ref.paceMax))"
        let line1 = L.s("점선 = \(name) 구간(\(pr)) 러닝 \(ref.sampleCount)회 · 참고",
                        "Dashed = \(name) band (\(pr)) · \(ref.sampleCount) runs · reference")
        let todayPace = activity.formattedPace ?? "--'--\""
        let dirWord = isFasterThanBands
            ? L.s("빨라", "faster than")
            : L.s("느려", "slower than")
        let line2 = L.s(
            "\n오늘 페이스(\(todayPace))는 평소 구간보다 \(dirWord) 판정 대신 참고로만 보여드려요",
            "\nToday's pace (\(todayPace)) is \(dirWord) your usual bands — shown for reference, not judged")
        return line1 + line2
    }

    private func barSummaryText() -> String? {
        let L = AppLanguage.shared
        if isReferenceBand { return referenceBarSummaryText() }
        guard !isInterval, let bb = bb, bb.sampleCount > 0 else { return nil }
        let paceMin = bb.paceMin
        let paceMax = bb.paceMax
        guard paceMin > 0, paceMax > 0 else { return nil }
        func pf(_ sec: Double) -> String {
            let i = Int(sec.rounded())
            return "\(i/60)'\(String(format: "%02d", i%60))\""
        }
        let n = bb.sampleCount
        let pr = "\(pf(paceMin))~\(pf(paceMax))"
        let todayDist = activity.distance
        // [112] allFormSamples 풀에서 재필터 (페이스 구간 + 12개월 창 + 거리)
        let actPaceBS = activity.paceSecPerKm ?? 0
        let actBandBS = baseline?.cutoffs.band(of: actPaceBS)
        let viewDateBS = activity.date
        let oneYearAgoBS = Calendar.current.date(byAdding: .year, value: -1, to: viewDateBS) ?? .distantPast
        let poolBS = baseline?.allFormSamples ?? []
        let recentCount = min(poolBS.filter { s in
            guard s.distanceM > 0, todayDist > 0 else { return false }
            if Calendar.current.isDate(s.date, inSameDayAs: viewDateBS) { return false }
            if s.date >= viewDateBS { return false }
            if s.date < oneYearAgoBS { return false }
            guard baseline?.cutoffs.band(of: s.paceSecPerKm) == actBandBS else { return false }
            let ratio = todayDist / s.distanceM
            return ratio >= 0.5 && ratio <= 2.0
        }.count, 5)
        let line1 = L.s(
            "눈금 사이 = 평소 범위 · \(pr) 러닝 \(n)회",
            "Ticks = typical range · \(n) runs at \(pr)")
        // [93] 0건일 때 "비교할 만한 거리의 러닝이 없어요", 2건 이상만 흰 점 표기
        let dotLine: String
        if recentCount == 0 {
            dotLine = L.s("\n비교할 만한 거리의 러닝이 없어요",
                          "\nNo runs of similar distance to compare")
        } else if recentCount >= 2 {
            dotLine = L.s("\n흰 점 = 거리가 비슷한 최근 \(recentCount)회",
                          "\nWhite dots = \(recentCount) recent similar-distance runs")
        } else {
            dotLine = ""
        }
        // 색 범례 — 초록은 "범위 안"이 아니라 "좋은 쪽"이다. 케이던스는 범위 위로,
        // 지면접촉은 범위 아래로 벗어나도 초록이라, 설명이 없으면 보폭(범위 밖=회색)과
        // 색이 갈리는 이유를 알 수 없다.
        let colorLine = L.s(
            "\n초록 = 범위 안이거나 더 좋은 쪽 (케이던스는 높게 · 지면접촉·수직진폭은 낮게)",
            "\nGreen = in range, or the better side (higher cadence · lower contact & oscillation)")
        let caveat: String = n < 3
            ? L.s("\n비교 대상이 적어 참고용이에요.", "\nLimited samples — treat as reference only.")
            : ""
        return line1 + dotLine + colorLine + caveat
    }

    // MARK: - Narrative

    private var narrative: String? {
        let L = AppLanguage.shared
        guard let cad = avgCadence else { return nil }
        let cadD = Double(cad)
        let paceStr = activity.formattedPace ?? "--"
        let cadStr  = "\(cad)"
        let slStr   = avgStrideLength.map { String(format: "%.2f", $0) }
        let gctStr  = avgGroundContactTime.map { String(format: "%.0f", $0) }

        if cadD < 160 {
            return L.s("케이던스가 \(cad)spm이에요. 보폭이 큰 편이에요.",
                        "Cadence is \(cad) spm — stride is on the longer side.")
        }
        // 인터벌: 회복 구간이 포함된 전체 평균이라 개인 기준 비교를 생략한다
        if isInterval {
            let base = slStr.map {
                L.s("케이던스 \(cadStr)spm, 보폭 \($0)m로 \(paceStr) 페이스가 나왔어요.",
                     "Cadence \(cadStr) spm and stride \($0) m produced a \(paceStr) pace.")
            } ?? L.s("케이던스 \(cadStr)spm으로 \(paceStr) 페이스가 나왔어요.",
                      "A cadence of \(cadStr) spm produced a \(paceStr) pace.")
            return base + " " + L.s(
                "인터벌은 회복 구간이 섞여 평균만으로는 폼을 판단하기 어려워요.",
                "Mixed with recovery intervals — averages alone don't reflect form."
            )
        }
        guard bb?.isJudgeable == true else {
            return slStr.map { L.s("케이던스 \(cadStr)spm으로 보폭 \($0)m를 만들어 \(paceStr) 페이스가 나왔어요.",
                                   "A cadence of \(cadStr) spm and \($0) m stride produced a \(paceStr) pace.") }
                ?? L.s("케이던스 \(cadStr)spm으로 \(paceStr) 페이스가 나왔어요.",
                        "A cadence of \(cadStr) spm produced a \(paceStr) pace.")
        }

        // 장거리 문맥: 장거리에서는 지표 하락이 자주 나타남 — 판단 유보, 사실 서술만 (문장은 FormNarrative 공유)
        if isLongDistanceContext {
            let cadSt = metricStatus(rawValue: cadD, stat: bb?.cadence, dir: .cadence)
            let gctSt: MetricStatus = avgGroundContactTime.map {
                metricStatus(rawValue: $0, stat: adjustedGctStat, dir: .groundContact)
            } ?? .unknown
            let slSt: MetricStatus = avgStrideLength.map {
                metricStatus(rawValue: $0, stat: bb?.strideLength, dir: .stride)
            } ?? .unknown
            // 전반/후반 평균 — 실제 변화 서술용
            let splitMid = fullSplits.count / 2
            let fHalf = Array(fullSplits.prefix(splitMid))
            let sHalf = Array(fullSplits.suffix(fullSplits.count - splitMid))
            func cadAvg(_ arr: [SplitData]) -> Int? {
                let v = arr.compactMap { $0.avgCadence }
                return v.isEmpty ? nil : Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
            }
            func slAvg(_ arr: [SplitData]) -> Double? {
                let v = arr.compactMap { $0.avgStrideLength }
                return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
            }
            let input = FormNarrative.LongDistanceInput(
                distKm: activity.distance / 1000,
                typeName: workoutType.koreanLabel,
                typicalDistanceKm: typicalDistanceKm,
                hasDistanceInsight: formInsights.contains(where: { $0.id == .distance }),
                cad: cadSt, gct: gctSt, sl: slSt,
                firstHalfCadence: cadAvg(fHalf), secondHalfCadence: cadAvg(sHalf),
                firstHalfStride: slAvg(fHalf), secondHalfStride: slAvg(sHalf),
                cadStr: cadStr, slStr: slStr, paceStr: paceStr)
            return FormNarrative.longDistanceSentence(input)
        }

        // 유형별 프레임(이지·빠른·일반)에 따라 톤만 달라지는 마무리 문장 — 판정은 여기서, 문장은 FormNarrative
        let cadStatus = metricStatus(rawValue: cadD, stat: bb?.cadence, dir: .cadence)
        let gctStatus: MetricStatus = avgGroundContactTime.map {
            metricStatus(rawValue: $0, stat: adjustedGctStat, dir: .groundContact)
        } ?? .unknown
        let slStatus: MetricStatus = avgStrideLength.map {
            metricStatus(rawValue: $0, stat: bb?.strideLength, dir: .stride)
        } ?? .unknown
        let input = FormNarrative.Input(
            cad: cadStatus, gct: gctStatus, sl: slStatus,
            cadStr: cadStr, gctStr: gctStr, slStr: slStr, paceStr: paceStr)
        return FormNarrative.sentence(input, frame: FormNarrative.frame(for: workoutType))
    }

    // MARK: - Log

    private func logDistanceContext() {
        #if DEBUG
        let distKm = activity.distance / 1000
        let typical = typicalDistanceKm
        let typicalStr = typical.map { String(format: "%.1f", $0) } ?? "-"
        let pctStr: String = typical.map { t in t > 0 ? "\(Int(distKm / t * 100 + 0.5))%" : "-" } ?? "-"
        let msg = isLongDistanceContext ? "→ 문맥 적용 (지표 배지·해석 생략)" : "→ 미적용"
        print("[폼:거리문맥] \(String(format: "%.1f", distKm))km / 4주평균 \(typicalStr)km (\(pctStr)) type=\(workoutType.koreanLabel)  \(msg)")
        #endif
    }

    private func logChain() {
        #if DEBUG
        guard !isInterval else { return }
        func pf(_ s: Double) -> String { String(format: "%d'%02d\"", Int(s) / 60, Int(s) % 60) }
        func rng(_ s: FormStat?, _ fmt: String) -> String {
            guard let s else { return "기준없음" }
            return String(format: "\(fmt)–\(fmt)(폭\(fmt))", s.lower, s.upper, s.upper - s.lower)
        }
        let cStr  = avgCadence.map { "\($0)" } ?? "-"
        let slStr = avgStrideLength.map  { String(format: "%.2f", $0) } ?? "-"
        let gctStr = avgGroundContactTime.map { String(format: "%.0f", $0) } ?? "-"
        let voStr  = avgVerticalOscillation.map { String(format: "%.1f", $0) } ?? "-"
        let pace   = activity.paceSecPerKm.map { pf($0) } ?? "--"
        let narrativeStr = narrative ?? "-"  // evaluate first so [폼] observation logs fire before chain log
        let gctAdj = adjustedGctStat
        let gctWasAdjusted = gctAdj?.median != bb?.groundContact?.median
        let gctBandStr = gctWasAdjusted ? "\(rng(gctAdj, "%.0f")) [보정]" : rng(bb?.groundContact, "%.0f")
        let chainLog = "[폼:사슬] C=\(cStr)(\(rng(bb?.cadence, "%.0f"))) 보폭=\(slStr)(\(rng(bb?.strideLength, "%.2f")))"
            + "\n         GCT=\(gctStr)(\(gctBandStr)) VO=\(voStr) 페이스=\(pace)"
            + "\n         → \"\(narrativeStr)\""
        print(chainLog)
        #endif
    }

    private func logTrend() {
        #if DEBUG
        let all = formSeriesCache  // onAppear에서 1회 계산된 캐시 사용
        guard !all.isEmpty else { return }
        let totalBuckets = all[0].totalSplitCount
        print("[폼:추이] \(String(format: "%.1f", activity.distance/1000))km splits=\(fullSplits.count) → 버킷 \(totalBuckets)개")
        for s in all {
            let total   = s.points.count
            let buckets = s.totalSplitCount  // [45] 분모를 전체 버킷 수로 통일
            let oob     = s.points.filter(\.outOfRange).count
            let pct     = total > 0 ? Int(Double(oob) / Double(total) * 100 + 0.5) : 0
            var line1   = "  \(s.label)"
            if let f = s.firstAvg, let sec = s.secondAvg {
                let diff = sec - f
                let sign = diff > 0 ? "+" : ""
                line1 += "  \(metricFmt(f, dir: s.dir))→\(metricFmt(sec, dir: s.dir))(\(sign)\(metricFmt(diff, dir: s.dir)))"
            }
            if let lo = s.bandLo, let hi = s.bandHi {
                let width  = hi - lo
                let method = s.dir == .verticalOsc ? "참고" : (s.bandIsJudgeable ? "평소범위" : "관측범위")
                let nStr   = s.dir == .verticalOsc ? "" : " · n=\(s.bandSampleCount)"
                let jStr   = (s.bandIsJudgeable || s.dir == .verticalOsc) ? "" : " · 판정불가"
                line1 += "  띠(\(method)\(jStr)) \(metricFmt(lo, dir: s.dir))–\(metricFmt(hi, dir: s.dir))(폭\(metricFmt(width, dir: s.dir)))\(nStr)"
            }
            print(line1)
            print("            띠밖 \(oob)/\(total)(\(pct)%) · 데이터 \(total)/\(buckets) 버킷")
        }
        #endif
    }

    private func logGctCorrection() {
        #if DEBUG
        guard let stat = bb?.groundContact else { return }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: activity.date)
        guard let baselineMean = baseline?.gctBaselineResidualMean else {
            print("[폼:GCT보정] baseline 없음 → 보정 안 함")
            return
        }
        guard let gctShift = formShifts.first(where: { $0.metric.key == "gct" }) else {
            print("[폼:GCT보정] 기준일 \(dateStr) · GCT shift 없음 (n부족 또는 미계산) → 보정 안 함")
            return
        }
        let viewingMean = gctShift.recentMean
        let rawDrift = viewingMean - baselineMean
        if let r2 = gctShift.r2, r2 < 0.2 {
            print(String(format: "[폼:GCT보정] 기준일 %@ · R²=%.2f (<0.2) → 보정 안 함", dateStr, r2))
            return
        }
        if abs(rawDrift) < 2 {
            print(String(format: "[폼:GCT보정] 기준일 %@ · drift %+.1fms (<2ms) → 보정 없음", dateStr, rawDrift))
            return
        }
        // 실제 보정량은 공유 함수와 동일 (±15ms 제한)
        let drift = FormNarrative.gctDrift(baselineResidualMean: baselineMean, gctShift: gctShift) ?? max(-15, min(15, rawDrift))
        let lo  = roundedDisplay(stat.lower, dir: .groundContact)
        let hi  = roundedDisplay(stat.upper, dir: .groundContact)
        let aLo = roundedDisplay(stat.lower + drift, dir: .groundContact)
        let aHi = roundedDisplay(stat.upper + drift, dir: .groundContact)
        print(String(format: "[폼:GCT보정] 기준일 %@ · 시점잔차 %+.2f · 기준잔차 %+.2f", dateStr, viewingMean, baselineMean))
        print(String(format: "             drift %+.1fms → 밴드 %.0f–%.0f → %.0f–%.0f", drift, lo, hi, aLo, aHi))
        #endif
    }

    private func logRangeBar() {
        #if DEBUG
        guard let baseline = baseline else { return }
        let pool = baseline.allFormSamples
        guard !pool.isEmpty else {
            print("[폼:범위바] allFormSamples 없음 — 캐시 재계산 후 사용 가능")
            return
        }
        guard let actPace = activity.paceSecPerKm else { return }
        let actBand = baseline.cutoffs.band(of: actPace)
        let todayDist = activity.distance
        let viewDate = activity.date
        let cal = Calendar.current
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: viewDate) ?? .distantPast
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"

        // 1단계: 날짜 창 (자신 제외 + 이전 + 12개월)
        let inWindow = pool.filter { s in
            !cal.isDate(s.date, inSameDayAs: viewDate) &&
            s.date < viewDate &&
            s.date >= oneYearAgo
        }
        // 2단계: 페이스 구간
        let inBand = inWindow.filter { baseline.cutoffs.band(of: $0.paceSecPerKm) == actBand }
        // 3단계: 거리 0.5~2배
        let inDist = inBand.filter { s in
            guard s.distanceM > 0, todayDist > 0 else { return false }
            let ratio = todayDist / s.distanceM
            return ratio >= 0.5 && ratio <= 2.0
        }
        let recent5 = Array(inDist.prefix(5))

        let winStart = inWindow.last.map { df.string(from: $0.date) } ?? "?"
        let winEnd   = df.string(from: viewDate)
        print("[폼:범위바] 후보 풀 = \(winStart) ~ \(winEnd) · 러닝 \(inWindow.count)건")
        print("             구간 통과 \(inBand.count)건 · 거리 통과 \(inDist.count)건 · 표시 \(recent5.count)건")

        if !recent5.isEmpty {
            let dots = recent5.map { s in "\(df.string(from: s.date))(\(String(format:"%.1f", s.distanceM/1000))km)" }
            print("[폼:범위바] 샘플 = \(dots.joined(separator: " · "))")
        }

        // 거리 필터 탈락 상세 (통과 0건일 때)
        if inDist.isEmpty, !inBand.isEmpty {
            let loKm = (todayDist / 2) / 1000
            let hiKm = (todayDist * 2) / 1000
            let rejectExamples = inBand.prefix(5).map { String(format: "%.1f", $0.distanceM / 1000) + "km" }
            print(String(format: "[폼:범위바] 거리 창 = %.1f~%.1fkm · 후보 \(inBand.count)건 → 통과 0건", loKm, hiKm))
            print("             탈락 예시: " + rejectExamples.joined(separator: " · "))
        }
        #endif
    }

    private func logLongDistanceChange() {
        #if DEBUG
        guard isLongDistanceContext else { return }
        let all = formSeriesCache.isEmpty ? formSeries : formSeriesCache

        struct BandExit {
            let dir: MetricDir; let kmStart: Double; let kmEnd: Double; let bucketIdx: Int
        }
        var exits: [BandExit] = []
        let totalKmLog = activity.distance / 1000
        let minKmLog = totalKmLog * 0.40
        for s in all {
            guard s.dir != .verticalOsc else { continue }
            guard let bandLo = s.bandLo, let bandHi = s.bandHi, !s.points.isEmpty else { continue }
            for (i, pt) in s.points.enumerated() {
                let exited: Bool
                switch s.dir {
                case .cadence, .stride: exited = pt.value < bandLo
                case .groundContact: exited = pt.value > bandHi
                case .verticalOsc: exited = false
                }
                if exited {
                    let start = i > 0 ? s.points[i - 1].kmEnd : 0.0
                    if start < minKmLog {
                        // [103] 초반 이탈 로그
                        let dirNames: [MetricDir: String] = [.cadence:"케이던스",.stride:"보폭",.groundContact:"지면접촉",.verticalOsc:"수직진폭"]
                        print("[폼:장거리변화] \(dirNames[s.dir, default: "?"] ) 버킷\(i+1)부터 범위 밖 — 초반 이탈(40% 기준 \(String(format:"%.1f",minKmLog))km 미만)로 판정 제외")
                        break
                    }
                    exits.append(BandExit(dir: s.dir, kmStart: start, kmEnd: pt.kmEnd, bucketIdx: i))
                    break
                }
            }
        }
        if exits.isEmpty {
            print("[폼:장거리변화] 세 지표 모두 범위 안(또는 초반 이탈) — 변화 없음")
            return
        }
        let sorted = exits.sorted { $0.kmStart < $1.kmStart }
        let dname: (MetricDir) -> String = {
            switch $0 {
            case .cadence: return "케이던스"
            case .stride: return "보폭"
            case .groundContact: return "지면접촉"
            case .verticalOsc: return "수직진폭"
            }
        }
        let parts = sorted.map { e in
            "\(dname(e.dir)) = 버킷\(e.bucketIdx + 1)(\(Int(e.kmStart.rounded()))~\(Int(e.kmEnd.rounded()))km)"
        }
        let earliest = sorted.first!
        print("[폼:장거리변화] \(parts.joined(separator: " · ")) → 변화 시작 \(Int(earliest.kmStart.rounded()))km")
        #endif
    }

    private func logInsightSlot() {
        #if DEBUG
        let items = formInsights
        let tempFiredDebug = items.contains { $0.id == .temperature }
        let isRainyDebug = weatherSnapshot?.isRainy == true
        let kinds: [FormInsightItem.Kind] = (tempFiredDebug && isRainyDebug)
            ? [.formChange, .temperature, .trend, .distance, .cadenceHR, .style]
            : [.formChange, .temperature, .weather, .trend, .distance, .cadenceHR, .style]
        let candidates: [(FormInsightItem.Kind, String)] = kinds
            .map { kind in
                let found = items.first { $0.id == kind }
                let label: String
                switch kind {
                case .temperature:
                    if let t = activity.temperatureC {
                        let suffix = (isRainyDebug && tempFiredDebug) ? " · 비 (날씨 통합)" : ""
                        label = "\(String(format: "%.1f", t))°C\(suffix)"
                    } else { label = "temp nil" }
                case .weather:
                    label = weatherSnapshot?.isRainy == true ? "비 있음" : "비 없음"
                case .trend:
                    let n = formShifts.filter(\.isReal).count
                    if let obs = mrFormObservation(formShifts, hasRecentGap: hasRecentGap, refCadence: avgCadence,
                                                   runCadenceResidual: runCadenceResidual) {
                        label = obs.isStable ? "안정(\(formShifts.count)개)" : "실증 \(n)/\(formShifts.count)"
                    } else {
                        label = hasRecentGap ? "공백→침묵" : "실증 \(n)/\(formShifts.count)"
                    }
                case .distance:
                    let km = activity.distance / 1000
                    let typ = typicalDistanceKm.map { String(format: "%.1f", $0) } ?? "-"
                    label = "\(String(format: "%.1f", km))km / 4주평균 \(typ)km"
                case .cadenceHR:
                    if let diag = baseline?.cadenceHRDiag, diag.isGloballyValid,
                       let vertex = diag.vertexResidual,
                       let cadStat = bb?.cadence {
                        let opt = Int((cadStat.median + vertex).rounded())
                        label = "최적케이던스 \(opt) (현재 \(avgCadence.map { "\($0)" } ?? "-"))"
                    } else {
                        label = "글로벌 조건 미충족"
                    }
                case .style:
                    switch runningStyleClassification {
                    case .quickStep: label = "잔발형"
                    case .bigStride: label = "큰보폭형"
                    case .normal:    label = "평소 주법"
                    case .unknown:   label = "생략"
                    }
                case .formChange:
                    label = longDistanceFormChangeInsight != nil ? "변화 있음" : "변화 없음"
                }
                let mark = found != nil ? "✓" : "✗"
                return (kind, "\(mark) \(kind.rawValue)  \(label)")
            }
        print("[인사이트] 후보 \(kinds.count)개 검토")
        candidates.forEach { print("  \($0.1)") }
        if items.isEmpty {
            print("[인사이트] 표시 없음")
        } else {
            print("[인사이트] 표시 \(items.count)개: \(items.map(\.id.rawValue).joined(separator: ", "))")
        }
        #endif
    }

    private func logUCurve() {
        #if DEBUG
        guard let diag = baseline?.cadenceHRDiag else {
            print("[U자] 진단 없음 (HR 데이터 부족 또는 baseline 미계산)")
            return
        }
        let rangeOK = diag.residualRangeP10P90 >= 10
        let binsOK  = diag.binCount >= 5
        var line1 = "[U자] 잔차범위 \(String(format: "%.1f", diag.residualRangeP10P90))spm(\(rangeOK ? "✓" : "<10 ✗")) bin=\(diag.binCount)(\(binsOK ? "✓" : "<5 ✗"))"
        var reasons: [String] = []
        if !rangeOK { reasons.append("잔차범위 부족") }
        if !binsOK  { reasons.append("bin 부족") }

        if let a = diag.a, let r2 = diag.r2 {
            let aOK  = a > 0
            let r2OK = r2 >= 0.3
            line1 += " a=\(String(format: "%+.2f", a))(\(aOK ? "✓" : "✗")) R²=\(String(format: "%.2f", r2))(\(r2OK ? "✓" : "<0.3 ✗"))"
            if !aOK  { reasons.append("아래로 볼록 아님") }
            if !r2OK { reasons.append("R² 부족") }
        }
        print(line1)

        if let vertex = diag.vertexResidual,
           let cadStat = bb?.cadence {
            let optCad = Int((cadStat.median + vertex).rounded())
            print("      최저점 \(String(format: "%+.1f", vertex))spm → 최적 케이던스 \(optCad)")
            if let actCad = avgCadence {
                if abs(optCad - actCad) < 2 { reasons.append("현재 케이던스와 차이 <2spm") }
                if optCad < 160 || optCad > 190 { reasons.append("절대 범위 밖 (\(optCad)spm)") }
            }
            print("      → \(reasons.isEmpty ? "표시" : "미표시: \(reasons.joined(separator: ", "))")")
        } else {
            if reasons.isEmpty { reasons.append("최저점 범위 밖 또는 회귀 실패") }
            print("      → 미표시: \(reasons.joined(separator: ", "))")
        }
        #endif
    }

    private func logStyleClassification() {
        #if DEBUG
        guard let bb else { return }
        let bandName = bb.band.rawValue
        guard let r = bb.cadenceStrideR else {
            print("[주법] 판정 생략 — \(bandName) 상관계수 없음")
            return
        }
        if isLongDistanceContext {
            print("[주법] 판정 생략 — 장거리 문맥 (\(bandName) r=\(String(format: "%+.3f", r)))")
            return
        }
        if isInterval {
            print("[주법] 판정 생략 — 인터벌")
            return
        }
        if r > -0.3 {
            print("[주법] 판정 생략 — \(bandName) r=\(String(format: "%+.3f", r)) (음의 상관 아님)")
            return
        }
        if bb.sampleCount < 20 {
            print("[주법] 판정 생략 — \(bandName) n=\(bb.sampleCount) < 20")
            return
        }
        print("[주법] 구간=\(bandName) r=\(String(format: "%.3f", r)) n=\(bb.sampleCount) → 판정 수행")
        guard let cad = avgCadence, let str = avgStrideLength,
              let cadStat = bb.cadence, let strStat = bb.strideLength else { return }
        let cadR = Double(cad) - cadStat.median
        let strR = str - strStat.median
        let p90c = bb.cadenceResidualP90.map { String(format: "P90=%+.1f", $0) } ?? "P90=?"
        let p25s = bb.strideResidualP25.map  { String(format: "P25=%+.3f", $0) } ?? "P25=?"
        let p10c = bb.cadenceResidualP10.map { String(format: "P10=%+.1f", $0) } ?? "P10=?"
        let p75s = bb.strideResidualP75.map  { String(format: "P75=%+.3f", $0) } ?? "P75=?"
        let cadCkQS = bb.cadenceResidualP90.map { cadR >= $0 ? "✓" : "✗" } ?? "?"
        let strCkQS = bb.strideResidualP25.map  { strR <= $0 ? "✓" : "✗" } ?? "?"
        let cadCkBS = bb.cadenceResidualP10.map { cadR <= $0 ? "✓" : "✗" } ?? "?"
        let strCkBS = bb.strideResidualP75.map  { strR >= $0 ? "✓" : "✗" } ?? "?"
        let styleStr: String
        switch runningStyleClassification {
        case .quickStep: styleStr = "잔발형"
        case .bigStride: styleStr = "큰보폭형"
        case .normal:    styleStr = "평소 주법"
        case .unknown:   styleStr = "알 수 없음"
        }
        print("      잔발형 체크: 케이던스 잔차 \(String(format: "%+.1f", cadR)) (\(p90c) \(cadCkQS)) 보폭 잔차 \(String(format: "%+.3f", strR)) (\(p25s) \(strCkQS))")
        print("      큰보폭형 체크: 케이던스 잔차 \(String(format: "%+.1f", cadR)) (\(p10c) \(cadCkBS)) 보폭 잔차 \(String(format: "%+.3f", strR)) (\(p75s) \(strCkBS))")
        print("      → \(styleStr)")
        #endif
    }

    // MARK: - Helpers

    private var kpiSep: some View {
        Rectangle().fill(Color.white.opacity(0.10)).frame(width: 0.5, height: 40)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
    }

    @ViewBuilder
    private func placeholderSection(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.38))
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }
}
