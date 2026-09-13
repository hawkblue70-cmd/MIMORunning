import Foundation

/// 러닝을 거리 비율로 초(0~30%)·중(30~70%)·말(70~100%) 세 단계로 나눠 폼의 형태를 판정한다.
///
/// - 기준은 폼 카드 눈금과 같다: 그 단계 **페이스 구간**의 평소 범위(±1.2SD, `FormNarrative.status`).
///   기온과 무관하고 페이스로 정규화되므로 그날 데이터만으로 말할 수 있다.
/// - 러닝 길이와 무관: km가 아니라 거리 비율로 나눈다. 풀 스플릿 5개 미만이면 nil — 5km 러닝까지는 판정.
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
        let avgHR: Double?
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
        /// 페이스 무너짐 = 중반보다 20초/km 이상 느려졌는데 심박이 내려가지 않음(−2bpm 이내).
        /// 심박이 내려갔으면 의도한 마무리로 본다. 페이스 정규화가 페이스 붕괴 자체를 가리는 구멍을 막는다.
        case faded(paceDropSec: Int)
    }

    /// 세 단계의 원시 통계 — 관계 문장·표가 함께 쓴다.
    struct Phases: Equatable { let early, mid, late: PhaseStats }
    /// 세 단계의 평소 범위 판정 — 관계 문장·표가 함께 쓴다.
    struct PhaseSignals: Equatable { let early, mid, late: Signals }

    struct Result: Equatable {
        let early: Early?
        let mid: Mid?
        let late: Late
        let earlyEndKm: Double
        let lateStartKm: Double
        let totalKm: Double
        let phases: Phases
        let signals: PhaseSignals
        /// 이지 프레임(`FormNarrative.frame(for:) == .easy`)에서 만들어진 결과인가 — 말기 판정의 톤을 바꾼다.
        var isEasyFrame: Bool = false
        var isHeld: Bool { late == .held }
        /// 이지 프레임에서 케이던스만 내려간 말기는 "무거워짐"이 아니라 편한 날의 자연스러운 변화.
        /// (`.heavier([.cadence, .verticalOsc])`처럼 다른 신호가 섞이면 소프트가 아니다.)
        var isSoftCadenceOnly: Bool { isEasyFrame && late == .heavier([.cadence]) }
        var isFaded: Bool { if case .faded = late { return true }; return false }

        /// 말기 지표가 중기보다 피로 방향으로 나빠졌는가 — `lateFatigue`와 같은 문턱(케이던스 ≤중기−1 ·
        /// 보폭 ≤중기−0.005 · 접지 ≥중기+2 · 수직진폭 ≥중기+0.2). 둘 중 하나라도 결측이면 false.
        /// "페이스 무너짐" 문장·근거·표에서 중기 대비 뭐가 나빠졌는지 짚을 때 쓴다.
        func lateWorsened(_ m: Metric) -> Bool {
            let mid = phases.mid, late = phases.late
            switch m {
            case .cadence:
                guard let mc = mid.cadence, let lc = late.cadence else { return false }
                return lc <= mc - 1
            case .stride:
                guard let ms = mid.stride, let ls = late.stride else { return false }
                return ls <= ms - 0.005
            case .groundContact:
                guard let mg = mid.groundContact, let lg = late.groundContact else { return false }
                return lg >= mg + 2
            case .verticalOsc:
                guard let mv = mid.verticalOsc, let lv = late.verticalOsc else { return false }
                return lv >= mv + FormPhase.verticalOscDeltaCm
            }
        }
    }

    static let minSplits = 5
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
    /// 페이스 무너짐 판정 문턱 — 중반보다 이만큼(초/km) 느려지면 "붕괴" 후보
    static let fadePaceDropSec = 20.0
    /// 페이스가 무너졌는데도 심박이 이 폭(bpm) 안으로만 내려가면 "그대로"로 본다(내려간 게 아니라 유지)
    static let fadeHRToleranceBpm = 2.0
    /// 다음 행동 제안 — 중반을 이만큼(초/km) 늦게 시작해 보라는 페이싱 조언
    static let fadeMidStartEaseSec = 10

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
                verticalOsc: avg(g.map(\.avgVerticalOscillation)),
                avgHR: avg(g.map { $0.avgHeartRate.map(Double.init) }))
        }
        guard let early = stats(0), let mid = stats(1), let late = stats(2) else { return nil }
        return (early, mid, late)
    }

    /// 단계별 GAP 보정 계수 — `phases(splits)`로 각 단계의 startKm..endKm을 구하고, 그 구간에 걸친
    /// `GradeAdjustedPace.gradeSegments`의 계수를 거리로 가중 평균한다(겹치는 길이만큼, `compute`와 같은 방식).
    /// 오르막 구간일수록 계수 < 1(GAP이 더 빠름) — `GradeAdjustedPace.factor(grade:)`와 같은 부호.
    /// 오르막이 한쪽 절반에 몰린 코스에서 전체 평균(≈1)으로 그 구간의 밴드를 잘못 조회하는 걸 막는다.
    /// 세그먼트가 2개 미만이거나 고도 프로파일이 없으면(판정불가) 그 단계는 1.0. 결과는 [0.7, 1.3]으로 clamp.
    static func phasePaceScales(splits: [SplitData], altitudeProfile: [(distanceKm: Double, altitude: Double)])
        -> (early: Double, mid: Double, late: Double) {
        guard let p = phases(splits) else { return (1, 1, 1) }
        let segments = GradeAdjustedPace.gradeSegments(from: altitudeProfile)
        guard !segments.isEmpty else { return (1, 1, 1) }

        func scale(startKm: Double, endKm: Double) -> Double {
            let startM = startKm * 1000, endM = endKm * 1000
            var weighted = 0.0
            var covered = 0.0
            var segCount = 0
            for seg in segments {
                let lo = max(seg.start, startM)
                let hi = min(seg.end, endM)
                guard hi > lo else { continue }
                weighted += seg.factor * (hi - lo)
                covered += hi - lo
                segCount += 1
            }
            guard segCount >= 2, covered > 0 else { return 1.0 }
            return min(max(weighted / covered, 0.7), 1.3)
        }

        return (scale(startKm: p.early.startKm, endKm: p.early.endKm),
                scale(startKm: p.mid.startKm, endKm: p.mid.endKm),
                scale(startKm: p.late.startKm, endKm: p.late.endKm))
    }

    // MARK: - 판정

    struct Signals: Equatable {
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

    /// 후반 피로 = 평소 범위 밖 + 중반보다 나빠짐. 빨라지면서 범위 아래인 보폭은 피로가 아니다.
    /// 중반 값이 없으면(판정불가) 밴드 판정만으로(band-only) 그 지표를 피로로 본다.
    static func lateFatigue(late: Signals, latePhase: PhaseStats, midPhase: PhaseStats) -> [Metric] {
        var out: [Metric] = []
        if late.cadence == .below {
            if let lc = latePhase.cadence, let mc = midPhase.cadence {
                if lc <= mc - 1 { out.append(.cadence) }
            } else {
                out.append(.cadence)
            }
        }
        if late.stride == .below {
            if let ls = latePhase.stride, let ms = midPhase.stride {
                if ls <= ms - 0.005 { out.append(.stride) }
            } else {
                out.append(.stride)
            }
        }
        if late.groundContact == .above {
            if let lg = latePhase.groundContact, let mg = midPhase.groundContact {
                if lg >= mg + 2 { out.append(.groundContact) }
            } else {
                out.append(.groundContact)
            }
        }
        return out
    }

    static func signals(_ p: PhaseStats, _ band: BandStats?) -> Signals {
        Signals(cadence: FormNarrative.status(rawValue: p.cadence, stat: band?.cadence, metric: .cadence),
                stride: FormNarrative.status(rawValue: p.stride, stat: band?.stride, metric: .stride),
                groundContact: FormNarrative.status(rawValue: p.groundContact, stat: band?.groundContact, metric: .groundContact))
    }

    /// - Parameters:
    ///   - paceScales: 단계별 GAP ÷ 실측 페이스 (`phasePaceScales`). 밴드 조회에만 곱한다 — 단계 간 페이스 차이 판정은 실측 그대로.
    ///   - bandFor: 단계 페이스(sec/km, GAP 보정됨) → 그 구간의 평소 범위. 구간 밖·판정불가면 nil.
    ///   - easyFrame: 이지 프레임(`FormNarrative.frame(for:) == .easy`)에서 판정 중인가 — `Result.isEasyFrame`으로 그대로 전달.
    /// `paceScales`엔 기본값을 두지 않는다 — 두면 아래 편의 오버로드(`paceScale:`)와 동시에 기본값으로
    /// 매칭돼 둘 다 생략한 호출("classify(splits:bandFor:)")이 모호(ambiguous)해진다.
    static func classify(splits: [SplitData], paceScales: (early: Double, mid: Double, late: Double),
                        easyFrame: Bool = false, bandFor: (Double) -> BandStats?) -> Result? {
        guard let p = phases(splits) else { return nil }
        let eScale = paceScales.early > 0 ? paceScales.early : 1.0
        let mScale = paceScales.mid > 0 ? paceScales.mid : 1.0
        let lScale = paceScales.late > 0 ? paceScales.late : 1.0
        let e = p.early, m = p.mid, l = p.late
        let eS = signals(e, bandFor(e.paceSecPerKm * eScale))
        let mS = signals(m, bandFor(m.paceSecPerKm * mScale))
        let lS = signals(l, bandFor(l.paceSecPerKm * lScale))
        guard lS.knownCount >= 2 else { return nil }

        // 말기
        let slowedLate = l.paceSecPerKm - m.paceSecPerKm >= paceDeltaSec
        // 위로 튐 = 수직진폭↑(≥0.2cm) 그리고 수직진폭÷보폭 비율↑(≥0.5%p). 보폭만 줄어 비율이 오른 경우는 제외.
        let ratioUp: Bool = {
            guard let va = m.verticalOsc, let vb = l.verticalOsc,
                  let a = m.verticalRatio, let b = l.verticalRatio else { return false }
            return vb - va >= verticalOscDeltaCm && b - a >= verticalRatioDeltaPct
        }()
        let lateFatigueSet = lateFatigue(late: lS, latePhase: l, midPhase: m)
        let strideWorse = lateFatigueSet.contains(.stride)
        let groundContactWorse = lateFatigueSet.contains(.groundContact)

        // 페이스 무너짐 — 중반보다 20초/km 이상 느려졌는데 심박이 내려가지 않음(±2bpm 이내는 "그대로").
        // 어느 한쪽 심박이라도 없으면(쿨다운인지 붕괴인지 구분 불가) 판정하지 않고 아래 기존 판정으로 넘어간다.
        let paceDrop = l.paceSecPerKm - m.paceSecPerKm
        let hrHeld: Bool = {
            guard let a = m.avgHR, let b = l.avgHR else { return false }
            return b >= a - fadeHRToleranceBpm
        }()

        let late: Late
        if paceDrop >= fadePaceDropSec, hrHeld {
            late = .faded(paceDropSec: Int(paceDrop.rounded()))
        } else if slowedLate, strideWorse, !groundContactWorse, lS.cadence == .inRange || lS.cadence == .above {
            late = .cadenceDefended
        } else if strideWorse, ratioUp, !groundContactWorse {
            late = .bouncier
        } else if !lateFatigueSet.isEmpty {
            late = .heavier(lateFatigueSet + (ratioUp ? [.verticalOsc] : []))
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
                      earlyEndKm: e.endKm, lateStartKm: l.startKm, totalKm: l.endKm,
                      phases: Phases(early: e, mid: m, late: l),
                      signals: PhaseSignals(early: eS, mid: mS, late: lS),
                      isEasyFrame: easyFrame)
    }

    /// 세 단계에 같은 배율을 쓰는 편의 오버로드 — 기존 단일 스케일 호출부·테스트가 그대로 동작한다.
    static func classify(splits: [SplitData], paceScale: Double = 1.0, easyFrame: Bool = false,
                        bandFor: (Double) -> BandStats?) -> Result? {
        classify(splits: splits, paceScales: (paceScale, paceScale, paceScale), easyFrame: easyFrame, bandFor: bandFor)
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

    // MARK: - 뷰 진입점

    /// 폼 카드·리듬 카드가 **이 함수 하나만** 쓴다 — 같은 러닝은 두 카드에서 같은 판정이어야 한다.
    /// - 인터벌 제외 · 기준선 없으면 nil
    /// - 밴드 조회 페이스 = 실측 × 단계별 GAP 배율(`phasePaceScales`): 기준선 밴드가 GAP 기준이라서.
    ///   오르막이 코스 한쪽 절반에 몰리면 전체 평균 배율(≈1)로는 그 구간을 잘못된 밴드에서 조회하게 되므로
    ///   단계마다 그 구간의 배율을 따로 낸다.
    /// - 전체 GAP 페이스가 어느 구간에도 없으면(참고 밴드) 판정하지 않는다 — 이 사전 판정은 러닝 전체 기준.
    static func result(splits: [SplitData],
                       altitudeProfile: [(distanceKm: Double, altitude: Double)],
                       baseline: RunningFormBaseline?,
                       formShifts: [MRFormShift],
                       workoutType: WorkoutType) -> Result? {
        guard workoutType != .interval, let bl = baseline else { return nil }
        let full = splits.filter { $0.distanceM >= 900 }
        let distKm = full.map(\.distanceM).reduce(0, +) / 1000
        let dur = full.map(\.duration).reduce(0, +)
        guard distKm > 0, dur > 0 else { return nil }
        let raw = dur / distKm
        let gapPace = GradeAdjustedPace.compute(splits: splits, altitudeProfile: altitudeProfile) ?? raw
        guard bl.cutoffs.band(of: gapPace) != nil else { return nil }
        let gctShift = formShifts.first(where: { $0.metric.key == "gct" })
        let scales = phasePaceScales(splits: full, altitudeProfile: altitudeProfile)
        return classify(splits: full, paceScales: scales, easyFrame: FormNarrative.frame(for: workoutType) == .easy,
                        bandFor: { pace in
            bandStats(in: bl, paceSecPerKm: pace, gctShift: gctShift)
        })
    }

    // MARK: - 문장

    /// 초·중·말 절을 쉼표로 이어 한 문장으로. 거리 문맥이고 말기가 유지가 아니면 "N km 후반엔 흔한 변화예요." 덧붙임.
    /// - Parameter suppressCommonTail: 관계 문장에 이미 더위 위안이 붙었으면(`hasHeatReassurance`) 이 꼬리를 생략 — 같은 말 반복 방지.
    static func sentence(_ r: Result, isLongDistance: Bool, suppressCommonTail: Bool = false) -> String {
        let L = AppLanguage.shared
        let earlyKm = String(format: "%.0f", r.earlyEndKm)
        let lateKm  = String(format: "%.0f", r.totalKm - r.lateStartKm)
        var ko: [String] = []
        var en: [String] = []

        if r.early == .warmup {
            ko.append("처음 \(earlyKm)km는 몸을 풀고")
            en.append("the first \(earlyKm) km were a warm-up")
        }
        switch r.mid {
        case .strideDriven?:
            ko.append("중반엔 보폭으로 속도를 냈고")
            en.append("you sped up mid-run with a longer stride")
        case .cadenceDriven?:
            ko.append("중반엔 발 회전으로 속도를 냈고")
            en.append("you sped up mid-run with quicker steps")
        case .both?:
            ko.append("중반엔 보폭과 회전을 함께 올려 속도를 냈고")
            en.append("you sped up mid-run with a longer stride and quicker steps")
        case nil:
            break
        }
        switch r.late {
        case .held:
            ko.append("끝까지 폼을 유지했어요")
            en.append("your form held to the finish")
        case .cadenceDefended:
            ko.append("마지막 \(lateKm)km엔 속도가 떨어졌지만 발 회전은 지켰어요")
            en.append("pace faded over the last \(lateKm) km but your cadence held")
        case .bouncier:
            ko.append("마지막 \(lateKm)km엔 앞보다 위로 가는 움직임이 늘었어요")
            en.append("over the last \(lateKm) km more motion went up than forward")
        case .heavier(let signals):
            if r.isSoftCadenceOnly {
                // 이지 프레임의 케이던스 단독 하강은 무거워짐이 아니라 편한 날의 변화 — 위안 문장을 절 안에 그대로 담는다
                // (마지막 요소일 때 뒤에 붙는 마침표 하나로 두 문장이 자연스럽게 끝난다).
                ko.append("마지막 \(lateKm)km엔 케이던스가 조금 내려갔어요. 편한 날엔 자연스러운 변화예요")
                en.append("Cadence eased a little over the last \(lateKm) km — natural on an easy day")
            } else {
                ko.append("마지막 \(lateKm)km엔 " + joinKo(signals))
                en.append("over the last \(lateKm) km " + joinEn(signals))
            }
        case .faded(let d):
            // 붕괴 사실 절 뒤에 무엇이 나빠졌는지(있으면) 이어 붙인다 — 소프트 케이던스 절과 같은 방식으로
            // 안쪽 마침표만 직접 넣고 바깥 wrap의 마침표 하나로 마무리한다(이중 마침표 방지).
            var koClause = "마지막 \(lateKm)km엔 페이스가 \(d)초/km 떨어졌는데 심박은 그대로였어요"
            var enClause = "Pace dropped \(d) s/km over the last \(lateKm) km while heart rate stayed up"
            let pieces = fadedWorsenedPieces(r)
            if !pieces.isEmpty {
                koClause += ". " + pieces.map(\.ko).joined(separator: " · ")
                let enJoinedPieces = pieces.map(\.en).joined(separator: " · ")
                let enCapped = String(enJoinedPieces.prefix(1)).uppercased() + enJoinedPieces.dropFirst()
                enClause += ". " + enCapped
            }
            ko.append(koClause)
            en.append(enClause)
        }

        var koS = ko.joined(separator: ", ") + "."
        let enJoined = en.count > 1
            ? en.dropLast().joined(separator: ", ") + ", and " + en[en.count - 1]
            : (en.first ?? "")
        var enS = enJoined + "."
        enS = String(enS.prefix(1)).uppercased() + enS.dropFirst()
        if isLongDistance, r.late != .held, !suppressCommonTail, !r.isSoftCadenceOnly, !r.isFaded {
            let d = String(format: "%.0f", r.totalKm)
            koS += " \(d)km 후반엔 흔한 변화예요."
            enS += " Common late in a \(d) km run."
        }
        return L.s(koS, enS)
    }

    /// 후반 심박 드리프트에 더위 위안이 붙는 조건 — `relationSentences`·`hasHeatReassurance`가 공유.
    /// 중반→후반 심박 ≥5 오르고, 더위 보정 ≥5bpm이고, 그 오름이 더위로 흔한 폭(≤ max(10, 더위×2)) 안일 때.
    private static func heatReassuranceApplies(_ r: Result, heatDeltaBpm: Double?) -> Bool {
        guard let h1 = r.phases.mid.avgHR, let h2 = r.phases.late.avgHR, h2 - h1 >= 5 else { return false }
        guard let heat = heatDeltaBpm, heat >= 5 else { return false }
        return h2 - h1 <= max(10.0, heat * 2)
    }

    /// `relationSentences`가 후반 문장에 "더위를 감안하면 흔한 폭" 괄호를 붙일지 — 밖에서 미리 알아야 `sentence`의
    /// "흔한 변화예요" 꼬리와 중복되지 않게 생략할 수 있다.
    static func hasHeatReassurance(_ r: Result, heatDeltaBpm: Double?) -> Bool {
        heatReassuranceApplies(r, heatDeltaBpm: heatDeltaBpm)
    }

    /// 구간별 관계 문장 — "무엇이 언제 어떻게" 를 한 줄씩. 아무 변화도 없으면 빈 배열.
    /// 문턱: 페이스 ≥ accelDeltaSec(20초, 중반) / paceDeltaSec(10초, 후반) · 보폭 ≥ 0.02 · 접지 ≥ 8ms · 심박 ≥ 5 · 케이던스 "그대로" = |Δ| < 2
    static func relationSentences(_ r: Result, heatDeltaBpm: Double?) -> [String] {
        let L = AppLanguage.shared
        let e = r.phases.early, m = r.phases.mid, l = r.phases.late
        func kmKo(_ p: PhaseStats) -> String { "\(Int(p.startKm.rounded()))~\(Int(p.endKm.rounded()))km" }
        func kmEn(_ p: PhaseStats) -> String { "\(Int(p.startKm.rounded()))–\(Int(p.endKm.rounded())) km" }
        var out: [String] = []

        // 중반: 페이스 ↔ 보폭·접지·케이던스
        let accel = e.paceSecPerKm - m.paceSecPerKm
        if accel >= accelDeltaSec {
            var koPairs: [(conj: String, final: String)] = []
            var enPhrases: [String] = []
            if let a = e.stride, let b = m.stride, b - a >= strideDeltaM {
                koPairs.append(("보폭이 늘고", "보폭이 늘었어요")); enPhrases.append("a longer stride")
            }
            if let a = e.groundContact, let b = m.groundContact, a - b >= 8 {
                koPairs.append(("접지가 짧아지고", "접지가 짧아졌어요")); enPhrases.append("shorter ground contact")
            }
            if let a = e.cadence, let b = m.cadence, b - a >= cadenceGainSPM {
                koPairs.append(("발 회전이 빨라지고", "발 회전이 빨라졌어요")); enPhrases.append("quicker steps")
            }
            if !koPairs.isEmpty {
                let ko = joinKoClauses(koPairs)
                let en = joinEnPhrases(enPhrases)
                out.append(L.s("중반 \(kmKo(m)): 페이스가 \(Int(accel.rounded()))초/km 빨라지며 \(ko).",
                               "Mid \(kmEn(m)): pace picked up by \(Int(accel.rounded())) s/km with \(en)."))
            }
        }

        // 후반: 심박 드리프트 ↔ 케이던스 (부호 있는 페이스·케이던스 변화, 더위 위안은 드리프트가 작을 때만)
        if let h1 = m.avgHR, let h2 = l.avgHR, h2 - h1 >= 5 {
            let hrRise = h2 - h1
            let hrDelta = Int(hrRise.rounded())
            let paceDelta = l.paceSecPerKm - m.paceSecPerKm

            let paceKo: String
            let paceEn: String
            if abs(paceDelta) < paceDeltaSec {
                paceKo = "페이스는 같은데"
                paceEn = "pace held but"
            } else if paceDelta > 0 {
                let n = Int(paceDelta.rounded())
                paceKo = "페이스가 \(n)초/km 느려지며"
                paceEn = "pace slowed by \(n) s/km as"
            } else {
                let n = Int((-paceDelta).rounded())
                paceKo = "페이스가 \(n)초/km 빨라지며"
                paceEn = "pace picked up by \(n) s/km as"
            }

            // late phase already reads out cadence drop when it drove the .heavier verdict — don't repeat it here
            let cadenceAlreadyNamed: Bool = {
                if case .heavier(let signals) = r.late { return signals.contains(.cadence) }
                return false
            }()
            enum CadenceDir { case same, dropped, rose }
            var cadenceDir: CadenceDir? = nil
            if !cadenceAlreadyNamed, let a = m.cadence, let b = l.cadence {
                let d = b - a
                if abs(d) < cadenceSameSPM { cadenceDir = .same }
                else if d <= -cadenceSameSPM { cadenceDir = .dropped }
                else { cadenceDir = .rose }
            }

            var heatKo = "", heatEn = ""
            if heatReassuranceApplies(r, heatDeltaBpm: heatDeltaBpm), let heat = heatDeltaBpm {
                let h = Int(heat.rounded())
                heatKo = " (더위 +\(h)bpm을 감안하면 흔한 폭)"
                heatEn = " (common with +\(h) bpm from heat)"
            }

            let ko: String
            let en: String
            if let dir = cadenceDir {
                let cadKo: String, cadEn: String
                switch dir {
                case .same:    cadKo = "케이던스는 그대로예요.";  cadEn = "while cadence stayed the same."
                case .dropped: cadKo = "케이던스는 내려갔어요."; cadEn = "and cadence dropped."
                case .rose:    cadKo = "케이던스는 올라갔어요."; cadEn = "and cadence went up."
                }
                ko = "\(paceKo) 심박이 \(hrDelta)bpm 올랐고\(heatKo), \(cadKo)"
                en = "\(paceEn) heart rate rose \(hrDelta) bpm\(heatEn), \(cadEn)"
            } else {
                ko = "\(paceKo) 심박이 \(hrDelta)bpm 올랐어요\(heatKo)."
                en = "\(paceEn) heart rate rose \(hrDelta) bpm\(heatEn)."
            }
            out.append(L.s("후반 \(kmKo(l)): " + ko, "Late \(kmEn(l)): " + en))
        }
        return out
    }

    /// 한국어 연결: 마지막 절만 종결형("보폭이 늘고 접지가 짧아졌어요")
    private static func joinKoClauses(_ pairs: [(conj: String, final: String)]) -> String {
        guard let last = pairs.last else { return "" }
        return (pairs.dropLast().map(\.conj) + [last.final]).joined(separator: " ")
    }

    /// 영어 나열: 2개 이상이면 쉼표로 잇고 마지막만 "and" — `joinEn(_:[Metric])`과 공유하는 나열 규칙.
    private static func joinEnPhrases(_ phrases: [String]) -> String {
        guard phrases.count > 1 else { return phrases.first ?? "" }
        return phrases.dropLast().joined(separator: ", ") + " and " + phrases[phrases.count - 1]
    }

    /// 총평 줄용 짧은 상태어
    static func shortState(_ r: Result) -> String {
        let L = AppLanguage.shared
        let lateKm = String(format: "%.0f", r.totalKm - r.lateStartKm)
        switch r.late {
        case .held:            return L.s("끝까지 유지", "Held to the finish")
        case .heavier:
            if r.isSoftCadenceOnly {
                return L.s("편한 페이스 · 케이던스만 살짝 내려감", "Easy pace · cadence eased slightly")
            }
            return L.s("마지막 \(lateKm)km 살짝 무거워짐", "A bit heavier in the last \(lateKm) km")
        case .cadenceDefended: return L.s("후반 회전은 유지", "Cadence held late")
        case .bouncier:        return L.s("후반 위로 튐", "Bouncier late")
        case .faded:           return L.s("마지막 \(lateKm)km 페이스 떨어짐", "Pace faded in the last \(lateKm) km")
        }
    }

    /// 페이스 무너짐 문장·근거가 함께 쓰는 "중반→후반에 뭐가 나빠졌나" 절 — 보폭 → 케이던스 → 접지 순.
    /// `Result.lateWorsened(_:)`로 걸러진 지표만, 둘 다 있는 값으로만 만든다.
    static func fadedWorsenedPieces(_ r: Result) -> [(ko: String, en: String)] {
        let m = r.phases.mid, l = r.phases.late
        var out: [(ko: String, en: String)] = []
        if r.lateWorsened(.stride), let ms = m.stride, let ls = l.stride {
            let a = String(format: "%.2f", ms), b = String(format: "%.2f", ls)
            out.append((ko: "보폭 \(a)→\(b)", en: "stride \(a)→\(b)"))
        }
        if r.lateWorsened(.cadence), let mc = m.cadence, let lc = l.cadence {
            let a = Int(mc.rounded()), b = Int(lc.rounded())
            out.append((ko: "케이던스 \(a)→\(b)", en: "cadence \(a)→\(b)"))
        }
        if r.lateWorsened(.groundContact), let mg = m.groundContact, let lg = l.groundContact {
            let d = Int((lg - mg).rounded())
            out.append((ko: "접지 +\(d)ms", en: "GCT +\(d) ms"))
        }
        return out
    }

    /// 한국어 연결: 마지막 신호만 종결형 — "보폭이 줄고 접지가 길어졌어요"
    private static func joinKo(_ signals: [Metric]) -> String {
        func conj(_ m: Metric) -> String {
            switch m {
            case .cadence:       return "케이던스가 내려가고"
            case .stride:        return "보폭이 줄고"
            case .groundContact: return "접지가 길어지고"
            case .verticalOsc:   return "위아래 움직임이 늘고"
            }
        }
        func final_(_ m: Metric) -> String {
            switch m {
            case .cadence:       return "케이던스가 내려갔어요"
            case .stride:        return "보폭이 줄었어요"
            case .groundContact: return "접지가 길어졌어요"
            case .verticalOsc:   return "위아래 움직임이 늘었어요"
            }
        }
        guard let last = signals.last else { return "" }
        return (signals.dropLast().map(conj) + [final_(last)]).joined(separator: " ")
    }

    private static func joinEn(_ signals: [Metric]) -> String {
        func phrase(_ m: Metric) -> String {
            switch m {
            case .cadence:       return "cadence dropped"
            case .stride:        return "stride shortened"
            case .groundContact: return "ground contact lengthened"
            case .verticalOsc:   return "vertical motion increased"
            }
        }
        return joinEnPhrases(signals.map(phrase))
    }
}
