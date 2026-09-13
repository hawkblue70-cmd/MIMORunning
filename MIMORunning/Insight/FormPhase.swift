import Foundation

/// 러닝을 거리 비율로 초(0~30%)·중(30~70%)·말(70~100%) 세 단계로 나눠 폼의 형태를 판정한다.
///
/// - 기준은 폼 카드 눈금과 같다: 그 단계 **페이스 구간**의 평소 범위(±1.2SD, `FormNarrative.status`).
///   기온과 무관하고 페이스로 정규화되므로 그날 데이터만으로 말할 수 있다.
/// - 러닝 길이와 무관: km가 아니라 거리 비율로 나눈다. 풀 스플릿 6개 미만이면 nil.
/// - 기준선이 없어 어느 단계도 판정할 수 없으면 nil(침묵). 말기는 케이던스·보폭·접지 중 2개 이상 알아야 한다.
enum FormPhase {
    typealias Metric = FormNarrative.Metric
    typealias Status = FormNarrative.Status

    /// 한 단계의 페이스에 해당하는 평소 범위. 뷰가 기준선에서 만들어 넘긴다(`bandStats(in:paceSecPerKm:gctShift:)`).
    struct BandStats {
        var cadence: FormStat?
        var stride: FormStat?
        var groundContact: FormStat?
    }

    struct PhaseStats: Equatable {
        let splitCount: Int
        let startKm: Double
        let endKm: Double
        let paceSecPerKm: Double
        let cadence: Double?
        let stride: Double?
        let groundContact: Double?
        let verticalOsc: Double?
        /// 수직진폭 ÷ 보폭 (%) — 앞이 아니라 위로 가는 움직임의 비율
        var verticalRatio: Double? {
            guard let vo = verticalOsc, let sl = stride, sl > 0 else { return nil }
            return vo / (sl * 100) * 100
        }
    }

    enum Early: Equatable { case warmup }
    enum Mid: Equatable { case strideDriven, cadenceDriven, both }
    enum Late: Equatable {
        case held
        /// 피로 방향 이탈. 순서 고정: cadence → stride → groundContact → verticalOsc
        case heavier([Metric])
        case cadenceDefended
        case bouncier
    }

    struct Result: Equatable {
        let early: Early?
        let mid: Mid?
        let late: Late
        let earlyEndKm: Double
        let lateStartKm: Double
        let totalKm: Double
        var isHeld: Bool { late == .held }
    }

    static let minSplits = 6
    static let earlyFraction = 0.30
    static let lateFraction = 0.70
    /// 단계 간 페이스 차이가 이 이상이어야 "빨라졌다/느려졌다"
    static let paceDeltaSec = 10.0
    /// 초기→중기 "빨라졌다"는 워밍업이 끼므로 후반 둔화(10초)보다 큰 문턱
    static let accelDeltaSec = 20.0
    static let strideDeltaM = 0.02
    static let cadenceSameSPM = 2.0
    static let cadenceGainSPM = 3.0
    static let verticalRatioDeltaPct = 0.5
    /// 비율은 보폭만 줄어도 오르므로 수직진폭 자체도 이만큼 늘어야 "위로 튐"으로 본다
    static let verticalOscDeltaCm = 0.2

    // MARK: - 분할

    static func phases(_ rawSplits: [SplitData]) -> (early: PhaseStats, mid: PhaseStats, late: PhaseStats)? {
        // 부분(마지막) 스플릿 제외 + id 순으로 정렬 — 풀 스플릿만 거리 비율 분할에 쓴다
        let splits = rawSplits.filter { $0.distanceM >= 900 }.sorted { $0.id < $1.id }
        guard splits.count >= minSplits else { return nil }
        let totalM = splits.map(\.distanceM).reduce(0, +)
        guard totalM > 0 else { return nil }

        var groups: [[SplitData]] = [[], [], []]
        var startM: [Double?] = [nil, nil, nil]
        var endM: [Double] = [0, 0, 0]
        var cum = 0.0
        for s in splits {
            let midFrac = (cum + s.distanceM / 2) / totalM
            let g = midFrac < earlyFraction ? 0 : (midFrac >= lateFraction ? 2 : 1)
            if startM[g] == nil { startM[g] = cum }
            groups[g].append(s)
            cum += s.distanceM
            endM[g] = cum
        }
        guard groups.allSatisfy({ !$0.isEmpty }) else { return nil }

        func avg(_ vals: [Double?]) -> Double? {
            let v = vals.compactMap { $0 }
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        func stats(_ i: Int) -> PhaseStats? {
            let g = groups[i]
            let distKm = g.map(\.distanceM).reduce(0, +) / 1000
            guard distKm > 0 else { return nil }
            let dur = g.map(\.duration).reduce(0, +)
            return PhaseStats(
                splitCount: g.count,
                startKm: (startM[i] ?? 0) / 1000,
                endKm: endM[i] / 1000,
                paceSecPerKm: dur / distKm,
                cadence: avg(g.map { $0.avgCadence.map(Double.init) }),
                stride: avg(g.map(\.avgStrideLength)),
                groundContact: avg(g.map(\.avgGroundContactTime)),
                verticalOsc: avg(g.map(\.avgVerticalOscillation)))
        }
        guard let early = stats(0), let mid = stats(1), let late = stats(2) else { return nil }
        return (early, mid, late)
    }

    // MARK: - 판정

    struct Signals {
        let cadence: Status
        let stride: Status
        let groundContact: Status
        var knownCount: Int { [cadence, stride, groundContact].filter { $0 != .unknown }.count }
        /// 피로 방향 이탈 — 케이던스↓ · 보폭↓ · 접지↑ (순서 고정)
        var fatigue: [Metric] {
            var out: [Metric] = []
            if cadence == .below { out.append(.cadence) }
            if stride == .below { out.append(.stride) }
            if groundContact == .above { out.append(.groundContact) }
            return out
        }
    }

    static func signals(_ p: PhaseStats, _ band: BandStats?) -> Signals {
        Signals(cadence: FormNarrative.status(rawValue: p.cadence, stat: band?.cadence, metric: .cadence),
                stride: FormNarrative.status(rawValue: p.stride, stat: band?.stride, metric: .stride),
                groundContact: FormNarrative.status(rawValue: p.groundContact, stat: band?.groundContact, metric: .groundContact))
    }

    /// - Parameters:
    ///   - paceScale: GAP ÷ 실측 평균 페이스 (전체 러닝 기준). 밴드 조회에만 곱한다 — 단계 간 페이스 차이 판정은 실측 그대로.
    ///   - bandFor: 단계 페이스(sec/km, GAP 보정됨) → 그 구간의 평소 범위. 구간 밖·판정불가면 nil.
    static func classify(splits: [SplitData], paceScale: Double = 1.0, bandFor: (Double) -> BandStats?) -> Result? {
        guard let p = phases(splits) else { return nil }
        let scale = paceScale > 0 ? paceScale : 1.0
        let e = p.early, m = p.mid, l = p.late
        let eS = signals(e, bandFor(e.paceSecPerKm * scale))
        let mS = signals(m, bandFor(m.paceSecPerKm * scale))
        let lS = signals(l, bandFor(l.paceSecPerKm * scale))
        guard lS.knownCount >= 2 else { return nil }

        // 말기
        let slowedLate = l.paceSecPerKm - m.paceSecPerKm >= paceDeltaSec
        // 위로 튐 = 수직진폭↑(≥0.2cm) 그리고 수직진폭÷보폭 비율↑(≥0.5%p). 보폭만 줄어 비율이 오른 경우는 제외.
        let ratioUp: Bool = {
            guard let va = m.verticalOsc, let vb = l.verticalOsc,
                  let a = m.verticalRatio, let b = l.verticalRatio else { return false }
            return vb - va >= verticalOscDeltaCm && b - a >= verticalRatioDeltaPct
        }()
        let late: Late
        if slowedLate, lS.stride == .below, lS.groundContact != .above, lS.cadence == .inRange || lS.cadence == .above {
            late = .cadenceDefended
        } else if lS.stride == .below, ratioUp, lS.groundContact != .above {
            late = .bouncier
        } else if !lS.fatigue.isEmpty {
            late = .heavier(lS.fatigue + (ratioUp ? [.verticalOsc] : []))
        } else {
            late = .held
        }

        // 초기 — 초기만 벗어나고 중기는 (판정 가능한 상태로) 범위 안이면 몸 풀기
        let early: Early? = (!eS.fatigue.isEmpty && mS.knownCount >= 2 && mS.fatigue.isEmpty) ? .warmup : nil

        // 중기 — 초기보다 빨라졌을 때 어느 레버로 속도를 냈는지
        var mid: Mid? = nil
        if e.paceSecPerKm - m.paceSecPerKm >= accelDeltaSec,
           let es = e.stride, let ms = m.stride, let ec = e.cadence, let mc = m.cadence {
            let strideUp = ms - es >= strideDeltaM
            let cadUp = mc - ec >= cadenceGainSPM
            if strideUp && cadUp { mid = .both }
            else if strideUp && abs(mc - ec) < cadenceSameSPM { mid = .strideDriven }
            else if cadUp && abs(ms - es) < strideDeltaM { mid = .cadenceDriven }
        }

        return Result(early: early, mid: mid, late: late,
                      earlyEndKm: e.endKm, lateStartKm: l.startKm, totalKm: l.endKm)
    }

    // MARK: - 기준선 → 단계 범위

    /// 단계 페이스가 속한 구간의 평소 범위. 구간 밖이거나 표본 부족(판정불가)이면 nil.
    /// 접지는 폼 카드와 같은 시점 보정(`driftAdjustedGCT`)을 거친다.
    static func bandStats(in baseline: RunningFormBaseline, paceSecPerKm: Double, gctShift: MRFormShift?) -> BandStats? {
        guard let band = baseline.cutoffs.band(of: paceSecPerKm),
              let b = baseline.bands[band], b.isJudgeable else { return nil }
        let gct = FormNarrative.driftAdjustedGCT(b.groundContact,
                                                 baselineResidualMean: baseline.gctBaselineResidualMean,
                                                 gctShift: gctShift)
        return BandStats(cadence: b.cadence, stride: b.strideLength, groundContact: gct)
    }
}
