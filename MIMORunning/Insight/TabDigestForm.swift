import Foundation

/// 폼 카드 판정(마무리 문장·장거리 폼 변화·케이던스-심박 권고·인터벌 해석/제안) + 오늘의 인사이트 폼 블록 신호.
/// 카드(`RunFormCardView`·`IntervalFatigueCard`)와 요약이 같은 함수를 불러 같은 문장을 쓴다.
/// 설계: docs/superpowers/specs/2026-10-14-today-insight-tab-digest-design.md §4.2·§5
enum TabDigestForm {

    /// 폼 카드가 뷰에서 조립하던 재료를 값으로. 카드는 자기 프로퍼티로, 요약은 `ActivityDetail`로 채운다.
    struct Inputs {
        var activity: Activity
        var detail: ActivityDetail?
        var baseline: RunningFormBaseline?
        var formShifts: [MRFormShift]
        var workoutType: WorkoutType
        /// 4주 평균 1회 러닝 거리(km) — 장거리 문맥 판단
        var typicalKm: Double?
        /// 피로 맥락("5일 연속 · 최근 7일 부하 +134%") — 이지런 다리 무거움 문장 근거
        var fatigueContext: String?
        /// 초·중·말 폼 형태(`FormPhase.result`)
        var phase: FormPhase.Result?

        // 카드가 받는 값 그대로(요약은 detail에서 풀어 채운다)
        var splits: [SplitData]
        var avgCadence: Int?
        var avgStrideLength: Double?
        var avgGroundContactTime: Double?
        var avgVerticalOscillation: Double?
        var altitudeProfile: [(distanceKm: Double, altitude: Double)]
        var intervalSegments: [IntervalSegment]
        /// 카드가 "거리" 인사이트 줄을 보여주는가 — 장거리 문장 접두 생략용.
        /// nil이면 거리 줄 발동 조건(평소 × 1.3 이상)만으로 본다(카드의 3줄 상한은 요약에 없다).
        var hasDistanceInsight: Bool? = nil
        /// 최근 3개월 14일↑ 공백 — 추세 문장 침묵
        var hasRecentGap: Bool = false
        var runCadenceResidual: Double? = nil
        /// 더위 심박 보정(bpm, `heatHRModel.delta(기온)`) — 3단계 문장 "흔한 변화" 꼬리 생략 판단(카드와 같은 값). 카드 경로는 쓰지 않는다.
        var heatDeltaBpm: Double? = nil

        /// 카드용 — 카드 프로퍼티를 그대로 넘긴다
        init(activity: Activity, splits: [SplitData], avgCadence: Int?, avgStrideLength: Double?,
             avgGroundContactTime: Double?, avgVerticalOscillation: Double?,
             altitudeProfile: [(distanceKm: Double, altitude: Double)], baseline: RunningFormBaseline?,
             workoutType: WorkoutType, intervalSegments: [IntervalSegment], typicalKm: Double?,
             formShifts: [MRFormShift], fatigueContext: String?, phase: FormPhase.Result?,
             hasRecentGap: Bool = false, runCadenceResidual: Double? = nil) {
            self.activity = activity
            self.detail = nil
            self.baseline = baseline
            self.formShifts = formShifts
            self.workoutType = workoutType
            self.typicalKm = typicalKm
            self.fatigueContext = fatigueContext
            self.phase = phase
            self.splits = splits
            self.avgCadence = avgCadence
            self.avgStrideLength = avgStrideLength
            self.avgGroundContactTime = avgGroundContactTime
            self.avgVerticalOscillation = avgVerticalOscillation
            self.altitudeProfile = altitudeProfile
            self.intervalSegments = intervalSegments
            self.hasRecentGap = hasRecentGap
            self.runCadenceResidual = runCadenceResidual
        }

        /// 요약용 — 인사이트 탭이 폼 카드에 넘기는 것과 같은 값으로 채운다(인터벌 케이던스 = 운동 구간 평균).
        init(activity: Activity, detail: ActivityDetail?, baseline: RunningFormBaseline?, formShifts: [MRFormShift],
             workoutType: WorkoutType, typicalKm: Double?, fatigueContext: String?,
             hasRecentGap: Bool = false, runCadenceResidual: Double? = nil, heatDeltaBpm: Double? = nil) {
            let cadence: Int? = {
                guard workoutType == .interval,
                      let wc = IntervalSegment.workAverage(detail?.intervalSegments ?? [], { $0.avgCadence.map(Double.init) })
                else { return detail?.avgCadence }
                return Int(wc.rounded())
            }()
            let splits = detail?.splits ?? []
            let altitude = detail?.altitudeProfile ?? []
            self.init(activity: activity, splits: splits, avgCadence: cadence,
                      avgStrideLength: detail?.avgStrideLength,
                      avgGroundContactTime: detail?.avgGroundContactTime,
                      avgVerticalOscillation: detail?.avgVerticalOscillation,
                      altitudeProfile: altitude, baseline: baseline, workoutType: workoutType,
                      intervalSegments: detail?.intervalSegments ?? [], typicalKm: typicalKm,
                      formShifts: formShifts, fatigueContext: fatigueContext,
                      phase: FormPhase.result(splits: splits, altitudeProfile: altitude, baseline: baseline,
                                              formShifts: formShifts, workoutType: workoutType),
                      hasRecentGap: hasRecentGap, runCadenceResidual: runCadenceResidual)
            self.detail = detail
            self.heatDeltaBpm = heatDeltaBpm
        }

        // MARK: 파생값 (옮김: RunFormCardView의 computed 프로퍼티)

        /// 이 러닝의 경사 조정 페이스. 기준선이 GAP으로 계산되므로 구간 조회도 GAP으로 한다.
        var runGAP: Double? {
            GradeAdjustedPace.compute(splits: splits, altitudeProfile: altitudeProfile)
        }

        /// 판정용 페이스 구간 기준선
        var bb: BandBaseline? {
            baseline?.baseline(for: activity, gradeAdjustedPace: runGAP)
        }

        /// 오늘 페이스가 구간 밖일 때 **표시용**으로 빌려 쓰는 가장 가까운 밴드(판정에는 쓰지 않는다)
        var referenceBb: BandBaseline? {
            guard let bl = baseline else { return nil }
            return RunFormCardView.referenceBand(in: bl, paceSecPerKm: activity.paceSecPerKm)
        }

        /// 범위 바·km 차트 띠에 실제로 그릴 밴드 (판정용 `bb`와 구분).
        var displayBb: BandBaseline? { bb ?? referenceBb }

        /// true = 오늘 페이스가 구간 밖이라 다른 구간을 "참고"로 빌려 그리는 중.
        var isReferenceBand: Bool { bb == nil && referenceBb != nil }

        /// 표시용 GCT 밴드 (참고 모드 포함). 판정용은 `adjustedGctStat`.
        var displayGctStat: FormStat? {
            FormNarrative.driftAdjustedGCT(displayBb?.groundContact,
                                           baselineResidualMean: baseline?.gctBaselineResidualMean,
                                           gctShift: formShifts.first(where: { $0.metric.key == "gct" }))
        }

        /// GCT 밴드를 열람 시점 기준으로 보정한 FormStat (판정용).
        var adjustedGctStat: FormStat? {
            FormNarrative.driftAdjustedGCT(bb?.groundContact,
                                           baselineResidualMean: baseline?.gctBaselineResidualMean,
                                           gctShift: formShifts.first(where: { $0.metric.key == "gct" }))
        }

        var isInterval: Bool { workoutType == .interval }

        /// true → 장거리 문맥. 장거리에서는 지표 하락이 자주 나타남 — 상태 배지를 숨기고 조언을 유보.
        var isLongDistanceContext: Bool {
            isLongDistanceRunContext(activity: activity, workoutType: workoutType, recentAvgDistanceKm: typicalKm)
        }

        var fullSplits: [SplitData] { splits.filter { $0.distanceM >= 900 } }
    }

    // MARK: - 마무리 문장 (옮김: RunFormCardView.narrative)

    private typealias Status = FormNarrative.Status

    /// 마무리 문장이 어느 갈래로 가는지 — 문장과 문제/좋음 분류가 같은 판정을 쓴다
    private enum Route {
        case lowCadence(Int)
        case interval
        case notJudgeable
        case longDistance(FormNarrative.LongDistanceInput)
        case framed(FormNarrative.Input, FormNarrative.Frame)
    }

    private static func route(_ x: Inputs) -> Route? {
        guard let cad = x.avgCadence else { return nil }
        let cadD = Double(cad)
        let paceStr = x.activity.formattedPace ?? "--"
        let cadStr  = "\(cad)"
        let slStr   = x.avgStrideLength.map { String(format: "%.2f", $0) }
        let gctStr  = x.avgGroundContactTime.map { String(format: "%.0f", $0) }
        let bb = x.bb

        if cadD < 160 { return .lowCadence(cad) }
        // 인터벌: 회복 구간이 포함된 전체 평균이라 개인 기준 비교를 생략한다
        if x.isInterval { return .interval }
        guard bb?.isJudgeable == true else { return .notJudgeable }

        // 장거리 문맥: 장거리에서는 지표 하락이 자주 나타남 — 판단 유보, 사실 서술만 (문장은 FormNarrative 공유)
        if x.isLongDistanceContext {
            let cadSt = FormNarrative.status(rawValue: cadD, stat: bb?.cadence, metric: .cadence)
            let gctSt: Status = x.avgGroundContactTime.map {
                FormNarrative.status(rawValue: $0, stat: x.adjustedGctStat, metric: .groundContact)
            } ?? .unknown
            let slSt: Status = x.avgStrideLength.map {
                FormNarrative.status(rawValue: $0, stat: bb?.strideLength, metric: .stride)
            } ?? .unknown
            // 전반/후반 평균 — 실제 변화 서술용
            let fullSplits = x.fullSplits
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
            let hasDistanceInsight = x.hasDistanceInsight ?? {
                guard let typical = x.typicalKm, typical > 0 else { return false }
                return (x.activity.distance / 1000) >= typical * 1.30
            }()
            let input = FormNarrative.LongDistanceInput(
                distKm: x.activity.distance / 1000,
                typeName: x.workoutType.koreanLabel,
                typicalDistanceKm: x.typicalKm,
                hasDistanceInsight: hasDistanceInsight,
                cad: cadSt, gct: gctSt, sl: slSt,
                firstHalfCadence: cadAvg(fHalf), secondHalfCadence: cadAvg(sHalf),
                firstHalfStride: slAvg(fHalf), secondHalfStride: slAvg(sHalf),
                cadStr: cadStr, slStr: slStr, paceStr: paceStr,
                // 말기가 범위를 벗어났을 때만 "평균으로는"으로 범위를 좁힌다 — 끝까지 유지면 두 문장이 모순되지 않는다
                hasPhaseSentence: x.phase.map { !$0.isHeld } ?? false)
            return .longDistance(input)
        }

        // 유형별 프레임(이지·빠른·일반)에 따라 톤만 달라지는 마무리 문장 — 판정은 여기서, 문장은 FormNarrative
        let cadStatus = FormNarrative.status(rawValue: cadD, stat: bb?.cadence, metric: .cadence)
        let gctStatus: Status = x.avgGroundContactTime.map {
            FormNarrative.status(rawValue: $0, stat: x.adjustedGctStat, metric: .groundContact)
        } ?? .unknown
        let slStatus: Status = x.avgStrideLength.map {
            FormNarrative.status(rawValue: $0, stat: bb?.strideLength, metric: .stride)
        } ?? .unknown
        let voStatus: Status = x.avgVerticalOscillation.map {
            FormNarrative.status(rawValue: $0, stat: bb?.verticalOsc, metric: .verticalOsc)
        } ?? .unknown
        let input = FormNarrative.Input(
            cad: cadStatus, gct: gctStatus, sl: slStatus,
            cadStr: cadStr, gctStr: gctStr, slStr: slStr, paceStr: paceStr,
            vo: voStatus, fatigueContext: x.fatigueContext)
        return .framed(input, FormNarrative.frame(for: x.workoutType))
    }

    /// 폼 카드 인과 사슬 아래 마무리 문장. 케이던스가 없으면 nil.
    static func narrative(_ x: Inputs) -> String? {
        let L = AppLanguage.shared
        guard let r = route(x), let cad = x.avgCadence else { return nil }
        let paceStr = x.activity.formattedPace ?? "--"
        let cadStr  = "\(cad)"
        let slStr   = x.avgStrideLength.map { String(format: "%.2f", $0) }
        switch r {
        case .lowCadence:
            return L.s("케이던스가 \(cad)spm입니다. 보폭이 큰 편입니다.",
                        "Cadence is \(cad) spm — stride is on the longer side.", ja: "ケイデンスは\(cad)spmです。ストライドが大きめです。")
        case .interval:
            let base = slStr.map {
                L.s("케이던스 \(cadStr)spm, 보폭 \($0)m로 \(paceStr) 페이스가 나왔습니다.",
                     "Cadence \(cadStr) spm and stride \($0) m produced a \(paceStr) pace.", ja: "ケイデンス\(cadStr)spm、ストライド\($0)mで\(paceStr)のペースになりました。")
            } ?? L.s("케이던스 \(cadStr)spm으로 \(paceStr) 페이스가 나왔습니다.",
                      "A cadence of \(cadStr) spm produced a \(paceStr) pace.", ja: "ケイデンス\(cadStr)spmで\(paceStr)のペースになりました。")
            return base + " " + L.s(
                "인터벌은 회복 구간이 섞여 평균만으로는 폼을 판단하기 어렵습니다.",
                "Mixed with recovery intervals — averages alone don't reflect form.", ja: "インターバルは回復区間が混ざるため、平均だけではフォームを判断しにくいです。"
            )
        case .notJudgeable:
            return slStr.map { L.s("케이던스 \(cadStr)spm으로 보폭 \($0)m를 만들어 \(paceStr) 페이스가 나왔습니다.",
                                   "A cadence of \(cadStr) spm and \($0) m stride produced a \(paceStr) pace.", ja: "ケイデンス\(cadStr)spmでストライド\($0)mをつくり、\(paceStr)のペースになりました。") }
                ?? L.s("케이던스 \(cadStr)spm으로 \(paceStr) 페이스가 나왔습니다.",
                        "A cadence of \(cadStr) spm produced a \(paceStr) pace.", ja: "ケイデンス\(cadStr)spmで\(paceStr)のペースになりました。")
        case .longDistance(let input):
            return FormNarrative.longDistanceSentence(input)
        case .framed(let input, let frame):
            return FormNarrative.sentence(input, frame: frame)
        }
    }

    private enum Verdict { case problem, good }

    /// `FormNarrative.sentence` 분기 순서(지면접촉 → 케이던스 → 보폭 → 모두 범위)를 따라 고른 분기의 성격.
    /// 문제 = 이지 다리 무거움(F2)·빠른 날 접지 김/케이던스 낮게 속도(F3). 좋음 = 지면접촉 짧음(A7).
    private static func framedVerdict(_ i: FormNarrative.Input, _ f: FormNarrative.Frame) -> Verdict? {
        if i.gctStr != nil {
            if i.gct == .below {
                // 이지 + 발걸음 빠름은 "리듬을 조금 늦춰도 괜찮습니다" 권고가 붙는 분기 — 좋음으로 세지 않는다
                return (f == .easy && i.cad == .above) ? nil : .good
            }
            if i.gct == .above {
                if f == .easy && i.cad == .below { return .problem }
                if f == .fast { return .problem }
                return nil
            }
        }
        // 빠른 날 발걸음 느림 — 보폭으로 속도(또는 기본) 분기는 "발걸음을 조금 더 빨리" 권고. 둘 다 작음은 사실만.
        if i.cad == .below, f == .fast, i.sl != .below { return .problem }
        return nil
    }

    /// 마무리 문장이 고른 분기가 '문제' 분기인가 (설계 F2·F3·F8)
    static func narrativeIsProblem(_ x: Inputs) -> Bool {
        switch route(x) {
        case .lowCadence?:              return true
        case .framed(let i, let f)?:    return framedVerdict(i, f) == .problem
        default:                        return false
        }
    }

    /// 마무리 문장이 고른 분기가 '좋은' 분기인가 (지면접촉 짧음)
    static func narrativeIsGood(_ x: Inputs) -> Bool {
        if case .framed(let i, let f)? = route(x) { return framedVerdict(i, f) == .good }
        return false
    }

    // MARK: - 장거리 폼 변화 (옮김: RunFormCardView.longDistanceFormChangeInsight [96])

    /// 거리문맥 러닝에서 케이던스·보폭·지면접촉이 평소 범위를 벗어난 첫 버킷을 찾아 관찰 문구를 만든다.
    /// 세 지표 모두 범위 안이거나 3단계 폼 문장이 있으면 nil. 줄은 "\n"으로 잇는다.
    /// - Parameter series: 카드가 이미 계산해 둔 추이 시리즈(없으면 여기서 계산)
    static func formChangeSentence(_ x: Inputs, series: [RunFormCardView.FormSeries]? = nil) -> String? {
        // 3단계 폼 문장이 나오면 이탈 위치까지 그 문장이 말한다 — 같은 사실을 두 번 적지 않는다.
        guard x.isLongDistanceContext, x.phase == nil else { return nil }
        let L = AppLanguage.shared
        let all = series ?? RunFormCardView.makeFormSeries(x)

        struct BandExit {
            let dir: FormNarrative.Metric
            let kmStart: Double   // 버킷 시작 km
            let kmEnd: Double     // 버킷 끝 km
        }
        var exits: [BandExit] = []
        // [103] 전체 거리의 40% 이전 이탈은 "처음부터 다른 값" — 변화 판정 제외
        let totalKm = x.activity.distance / 1000
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
                    ? L.s("\(km)km 지점부터 케이던스가 평소 범위 아래로 내려갔습니다.",
                          "From \(km) km, cadence dropped below its normal range.", ja: "\(km)km地点からケイデンスが普段の範囲を下回りました。")
                    : L.s("케이던스는 \(km)km부터였습니다.", "Cadence from \(km) km.", ja: "ケイデンスは\(km)kmからでした。")
            case .stride:
                return idx == 0
                    ? L.s("\(km)km 지점부터 보폭이 평소 범위 아래로 내려갔습니다.",
                          "From \(km) km, stride length dropped below its normal range.", ja: "\(km)km地点からストライドが普段の範囲を下回りました。")
                    : L.s("보폭은 \(km)km부터였습니다.", "Stride from \(km) km.", ja: "ストライドは\(km)kmからでした。")
            case .groundContact:
                return idx == 0
                    ? L.s("\(km)km 지점부터 지면접촉이 평소 범위 위로 올라갔습니다.",
                          "From \(km) km, ground contact time rose above its normal range.", ja: "\(km)km地点から接地時間が普段の範囲を上回りました。")
                    : L.s("지면접촉은 \(km)km부터였습니다.", "Ground contact from \(km) km.", ja: "接地時間は\(km)kmからでした。")
            case .verticalOsc:
                return nil
            }
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    // MARK: - 케이던스-심박 U자 권고 (옮김: RunFormCardView.cadenceHRInsight)

    /// 같은 페이스에서 심박이 가장 낮았던 케이던스 권고. 글로벌 조건 + 퍼액티비티 조건 모두 통과 시 문장.
    static func cadenceAdvice(_ x: Inputs) -> String? {
        guard !x.isInterval,
              let diag = x.baseline?.cadenceHRDiag,
              diag.isGloballyValid,
              let vertex = diag.vertexResidual,
              let bb = x.bb,
              let cadStat = bb.cadence,
              let actCad = x.avgCadence
        else { return nil }

        let optimalCadence = Int((cadStat.median + vertex).rounded())

        // 퍼액티비티 조건
        guard abs(optimalCadence - actCad) >= 2 else { return nil }
        guard optimalCadence >= 160, optimalCadence <= 190 else { return nil }

        let L = AppLanguage.shared
        let direction = optimalCadence > actCad
            ? L.s("조금 높은", "slightly higher", ja: "少し高い")
            : L.s("조금 낮은", "slightly lower", ja: "少し低い")
        return L.s(
            "같은 페이스에서 케이던스 \(optimalCadence) 근처일 때 심박이 가장 낮았습니다. 지금보다 \(direction) 편이 효율적일 수 있습니다.",
            "HR was lowest around a cadence of \(optimalCadence) at the same pace. A \(direction) cadence than now may be more efficient.", ja: "同じペースでケイデンス\(optimalCadence)前後のとき心拍が最も低かったです。今より\(direction)ほうが効率的かもしれません。"
        )
    }

    // MARK: - 인터벌 해석·제안 (IntervalFatigueCard와 같은 판정)

    static func intervalPair(_ x: Inputs) -> (interpretation: String, suggestion: String?)? {
        guard x.isInterval, let v = IntervalFatigueCard.verdict(segments: x.intervalSegments) else { return nil }
        return (v.interpretation, v.suggestion)
    }

    // MARK: - 폼 블록 신호 (설계 §4.2)

    /// 총평 '러닝폼' 줄의 next — 폼 문제의 짝 방향
    private static func formNext(_ lines: [RunSummaryLine]) -> String? {
        guard let lbl = RunHeadline.Axis.form.label else { return nil }
        return lines.first { $0.axis == lbl }?.next
    }

    static func signals(_ x: Inputs, lines: [RunSummaryLine]) -> [TabDigest.Signal] {
        var out: [TabDigest.Signal] = []
        func problem(_ p: Int, _ family: TabDigest.Family, _ text: String, _ direction: String?) {
            out.append(TabDigest.Signal(tab: .form, kind: .problem, priority: p, family: family, text: text,
                                        tone: .caution, direction: direction))
        }
        func good(_ p: Int, _ text: String, _ direction: String? = nil) {
            out.append(TabDigest.Signal(tab: .form, kind: .good, priority: p, family: .unique, text: text,
                                        tone: .good, direction: direction))
        }

        // 인터벌 — 인터벌 피로 카드의 해석 + 제안 한 쌍만
        if x.isInterval {
            if let v = IntervalFatigueCard.verdict(segments: x.intervalSegments) {
                if v.isProblem { problem(1, .unique, v.interpretation, v.suggestion) }
                else { good(1, v.interpretation) }
            }
            return out
        }

        let next = formNext(lines)
        let isLong = x.isLongDistanceContext
        var latePhaseProblem = false

        // F1 후반 페이스 무너짐 / F6 후반 무거워짐·위로 튐 / 좋음: 끝까지 유지·이지 케이던스만 하강
        if let p = x.phase {
            // 카드(RunFormCardView)와 같은 꼬리 생략 — 더위 안심 괄호가 붙으면 "흔한 변화" 꼬리를 뺀다
            let sentence = FormPhase.sentence(p, isLongDistance: isLong,
                                              suppressCommonTail: FormPhase.hasHeatReassurance(p, heatDeltaBpm: x.heatDeltaBpm))
            switch p.late {
            case .faded:
                problem(1, .latePace, sentence, next)
                latePhaseProblem = true
            case .heavier:
                if p.isSoftCadenceOnly {
                    good(2, sentence)
                } else {
                    problem(6, .lateForm, sentence, next)
                    latePhaseProblem = true
                }
            case .bouncier:
                problem(6, .lateForm, sentence, next)
                latePhaseProblem = true
            case .held:
                good(1, sentence)
            case .cadenceDefended:
                break
            }
        }

        // F2·F3·F8 마무리 문장 문제 분기 / 좋음: 지면접촉 짧음
        if let text = narrative(x) {
            if narrativeIsProblem(x) {
                switch route(x) {
                case .lowCadence?:
                    // F8 케이던스 160 미만 — 방향 = 케이던스-심박 권고(있을 때). F4~F7 뒤.
                    problem(8, .unique, text, cadenceAdvice(x))
                case .framed(_, let f)? where f == .easy:
                    // F2 다리 무거움 패턴 — 방향 = 러닝폼 줄 next
                    problem(2, .unique, text, next)
                default:
                    // F3 빠른 날 — 권고가 문장 안에 있어 방향 없음
                    problem(3, .unique, text, nil)
                }
            } else if narrativeIsGood(x) {
                good(5, text)
            }
        }

        // F4 빌드업 보폭으로만 / F5 템포 후반 접지↑·발걸음↓ — 문장 안에 권고가 있어 방향 없음.
        // 좋음: 템포 C5·C6 · 장거리 C9. 장거리 C10(후반 무거워짐)은 3단계 문장이 같은 사실을 말하지 않을 때만.
        if let v = TabDigestRhythm.typeFormVerdict(workoutType: x.workoutType, splits: x.splits, formBaseline: x.baseline) {
            switch x.workoutType {
            case .buildUp:
                if v.isProblem { problem(4, .unique, v.text, nil) }
            case .tempo:
                if v.isProblem { problem(5, .unique, v.text, nil) } else if v.isGood { good(3, v.text) }
            case .lsd, .longRun:
                if v.isProblem { if !latePhaseProblem { problem(6, .lateForm, v.text, next) } }
                else if v.isGood { good(4, v.text) }
            default:
                break
            }
        }

        // F7 장거리 후반 범위 이탈 시작 km
        if let text = formChangeSentence(x) {
            problem(7, .lateForm, text, next)
        }

        // 덧붙임 — 장기 추세 첫 문장
        if let obs = mrFormObservation(x.formShifts, hasRecentGap: x.hasRecentGap, refCadence: x.avgCadence,
                                       runCadenceResidual: x.runCadenceResidual),
           let first = obs.text.components(separatedBy: "\n").first, !first.isEmpty {
            out.append(TabDigest.Signal(tab: .form, kind: .extra, priority: 1, family: .unique, text: first))
        }
        return out
    }

    /// 폼 블록 기본 방향 — 케이던스-심박 권고
    static func defaultDirection(_ x: Inputs) -> String? { cadenceAdvice(x) }

    /// 최근 3개월 러닝 사이에 14일↑ 공백이 있었는가 — 폼 카드·요약이 추세 문장 침묵에 같은 값을 쓴다.
    /// (옮김: RunInsightTabCard `case .form:`의 hasFormGap)
    static func hasRecentGap(activity: Activity, history: [Activity]) -> Bool {
        let cal = Calendar.current
        guard let threeMonthsAgo = cal.date(byAdding: .month, value: -3, to: activity.date) else { return false }
        let recent = history
            .filter { $0.type == .running && $0.date >= threeMonthsAgo && $0.date <= activity.date }
            .sorted { $0.date < $1.date }
        for (a, b) in zip(recent, recent.dropFirst()) {   // 0·1건이면 루프 없음 (0..<-1 크래시 방지)
            let gap = cal.dateComponents([.day], from: a.date, to: b.date).day ?? 0
            if gap >= 14 { return true }
        }
        return false
    }
}
