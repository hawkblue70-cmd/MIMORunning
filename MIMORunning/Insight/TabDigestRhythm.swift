import Foundation

/// 리듬 카드 판정(존 캡션·심박 캡션·종류별 전후반) + 오늘의 인사이트 리듬 블록 신호.
/// 카드(`RhythmInsightCard`)와 요약이 같은 함수를 불러 같은 문장을 쓴다 — 카드는 `shade`를 원래 색으로 바꿔 쓴다.
/// 설계: docs/superpowers/specs/2026-10-14-today-insight-tab-digest-design.md §4.1·§5
enum TabDigestRhythm {

    /// 카드와 요약이 함께 쓰는 판정 — 문장 + 톤
    struct Verdict: Equatable {
        /// 카드 글자색 단계 — 초록(Theme.positive)·흰색(0.75)·노랑(FFD166). 매핑은 카드에 남긴다.
        enum Shade: Equatable { case good, neutral, caution }
        let text: String
        /// 요약에서 문제로 다룰 판정. 카드 색과는 별개다(페이스 기복·후반 느려짐은 카드에선 흰색, 요약에선 문제).
        let isProblem: Bool
        var shade: Shade = .neutral
        /// 폼(접지·케이던스) 판정 — 리듬 블록에서는 내지 않는다(폼 탭 몫, 설계 §5)
        var aboutForm: Bool = false
        /// 페이스 모양 판정 종류 — 요약에서 소유 블록을 가른다(설계 §5: 일반 유형 후반 느려짐은 퍼포먼스 몫)
        enum PaceShape: Equatable { case distanceRunDrop, varied, slowedLate }
        var paceShape: PaceShape? = nil
        /// 요약 블록용 개조식 표현(`TabDigest.Signal.short`) — 카드는 쓰지 않는다
        var short: String? = nil
        var isGood: Bool { shade == .good }
    }

    // MARK: - 존 도넛 캡션 (옮김: RhythmInsightCard.zoneVerdictLabel)

    /// 존 캡션에 붙이는 더위 보정 꼬리. 보정량이 표기 임계값 미만이면 nil.
    static func zoneHeatSuffix(heatHRModel: MRHeatHRModel?, temperatureC: Double?) -> String? {
        let L = AppLanguage.shared
        let heatDelta = heatHRModel?.delta(temperatureC) ?? 0
        guard heatDelta >= RunSummary.heatNoteMinBpm else { return nil }
        let n = Int(heatDelta.rounded())
        return (heatHRModel?.isFallback == true)
            ? L.s(" · 더위로 +\(n)bpm 정도", " · about +\(n) bpm from heat", ja: " · 暑さで+\(n)bpmほど")
            : L.s(" · 더위로 +\(n)bpm", " · +\(n) bpm from heat", ja: " · 暑さで+\(n)bpm")
    }

    /// 존 도넛 캡션. 보이는 존이 없으면 nil(카드는 빈 문자열).
    /// 문제 = 계획된 고강도 유형이 아닌데 템포 구간에 머묾 / 고강도 구간이 많음.
    static func zoneVerdict(fractions: [Int: Double], workoutType: WorkoutType, heatSuffix: String?) -> Verdict? {
        let L = AppLanguage.shared
        let visible = fractions.filter { $0.value > 0.01 }
        let total = max(1e-9, visible.values.reduce(0, +))
        let z2frac = (fractions[2] ?? 0) / total
        func pct(_ f: Double) -> Int { Int((f * 100).rounded()) }
        let z2pct = pct((visible[2] ?? 0) / total)
        let zone2 = Verdict(text: L.s("Zone 2 중심으로 달렸습니다", "Mostly in Zone 2", ja: "ゾーン2中心で走りました"),
                            isProblem: false, shade: .good,
                            short: L.s("Zone 2 중심 · \(z2pct)%", "Mostly Zone 2 · \(z2pct)%", ja: "ゾーン2中心 · \(z2pct)%"))
        if z2frac >= 0.60 { return zone2 }
        // 총평과 같은 규칙 — Zone 4+5 합이 가장 큰 존 이상(35%↑)이면 고강도 캡션
        guard let v = FormNarrative.verdictZone(fractions: visible) else { return nil }
        let heatSuffix = heatSuffix ?? ""
        let planned = FormNarrative.isPlannedHighIntensity(workoutType)
        switch v.zone {
        case 1: return Verdict(text: L.s("가벼운 회복 강도였습니다", "Light recovery run", ja: "軽い回復強度でした"), isProblem: false,
                               short: L.s("가벼운 회복 강도 · Zone 1 \(pct(v.frac))%", "Light recovery · \(pct(v.frac))% in Zone 1", ja: "軽い回復強度 · ゾーン1 \(pct(v.frac))%"))
        case 2: return zone2
        case 3:
            // 인터벌은 운동·회복이 섞인 평균이라 "템포 구간에 머물렀다"가 아니다 — 총평 "의도한 고강도"와도 부딪혔다
            if workoutType == .interval {
                return Verdict(text: L.s("운동·회복이 섞인 평균이 Zone 3입니다", "Zone 3 on average — work and recovery mixed", ja: "本練習と回復が混ざった平均がゾーン3です") + heatSuffix,
                               isProblem: false,
                               short: L.s("운동·회복 평균 Zone 3", "Work + recovery average Zone 3", ja: "本練習・回復の平均ゾーン3") + heatSuffix)
            }
            // Zone 3(여유 심박 70~80%)은 "유산소 구간" — "템포"라 부르면 이지 상한(LT1, 관측 최대심박의 80%)과 같은 심박대를
            // 두고 엇갈렸다("158 아래였습니다" vs "템포 구간", 2026-10-22). 코드 존 이름도 원래 "Z3 유산소".
            return Verdict(text: L.s("심박은 유산소 구간에 머물렀습니다", "Heart rate stayed in the aerobic zone", ja: "心拍は有酸素域にとどまりました") + heatSuffix,
                           isProblem: !planned,
                           short: L.s("유산소 구간에 머묾 · Zone 3 \(pct(v.frac))%", "Stayed in aerobic zone · \(pct(v.frac))% in Zone 3", ja: "有酸素域にとどまる · ゾーン3 \(pct(v.frac))%") + heatSuffix)
        default:
            let high = pct(((visible[4] ?? 0) + (visible[5] ?? 0)) / total)
            return Verdict(text: FormNarrative.highIntensityZoneCaption(type: workoutType) + heatSuffix, isProblem: !planned,
                           short: L.s("고강도 구간 많음 · Zone 4~5 \(high)%", "Lots of high intensity · \(high)% in Zone 4–5", ja: "高強度域が多い · ゾーン4~5 \(high)%") + heatSuffix)
        }
    }

    // MARK: - 심박 차트 캡션 (옮김: RhythmInsightCard.hrVerdictText)

    struct HRCaption: Equatable {
        enum Kind: Equatable { case maxIntensity, lateClimb, secondHalfRise, easedOff, steady }
        let kind: Kind
        let text: String
        /// 요약 블록용 개조식 표현 — 카드는 쓰지 않는다
        var short: String? = nil
    }

    /// 심박 차트 캡션 — 샘플 10개 미만이면 nil.
    static func hrVerdict(samples hrSamples: [(offset: TimeInterval, bpm: Int)], hrMax: Double?, age: Int?,
                          workoutType: WorkoutType, activity: Activity, detail: ActivityDetail?,
                          history: [Activity]) -> HRCaption? {
        guard hrSamples.count >= 10 else { return nil }
        let L = AppLanguage.shared
        // 출발 직후 광학 심박이 튄 구간(HRSeriesSmoothing.hrEarlyArtifactCount)은 전후반 비교·최고치에서 뺀다.
        // 차트는 그대로 그리고 판정만 뺀다 — 그 구간이 "후반에 여유"·"최고 강도"를 만들어내던 것.
        // 러닝 중간 튐(hrMidRunSpikeCleaned)도 주변 값으로 바꿔 판정한다 — 존 분포와 같은 규칙
        // 몸 풀리기 전 구간(km 단위, 더 느린데 더 높던 초반)도 뺀다 — 전후반 −2bpm "끝까지 안정"이 나왔다(2026-10-21)
        var base = hrEarlyArtifactCount(hrSamples).map { Array(hrSamples.dropFirst($0)) } ?? hrSamples
        if let end = hrWarmupPhaseEndOffset(detail?.splits ?? [], altitudeProfile: detail?.altitudeProfile ?? []),
           let t0 = hrSamples.first?.offset {
            base = base.filter { $0.offset >= t0 + end }
        }
        let samples = hrMidRunSpikeCleaned(base)
        guard samples.count >= 10 else { return nil }
        let n = samples.count
        let half = n / 2
        let avgFirst  = samples.prefix(half).map { Double($0.bpm) }.reduce(0, +) / Double(half)
        let avgSecond = samples.suffix(n - half).map { Double($0.bpm) }.reduce(0, +) / Double(n - half)
        let diff = avgSecond - avgFirst
        // 220−나이는 쓰지 않는다 — 엔진과 같은 규칙(관측 최대 → Tanaka)
        // "최고 강도"는 최대심박 90% 이상에 2분 이상 머물렀을 때만 — 오르막 끝에서 한 번 스친 최고치로는 말하지 않는다.
        // (존 도넛 "Zone 2 중심"·총평과 부딪혔다.) 평활한 값으로 재서 광학 튐도 거른다.
        if let mhr = RunInsightEngine.estimatedHRMax(hrMax: hrMax, age: age), mhr > 0 {
            let thr = 0.90 * Double(mhr)
            let sm = hrChartSmoothed(samples.map(\.bpm))
            var secAbove: TimeInterval = 0
            for i in 0..<(samples.count - 1) where sm[i] >= thr {
                secAbove += min(max(samples[i + 1].offset - samples[i].offset, 0), 30)
            }
            if secAbove >= 120 {
                return HRCaption(kind: .maxIntensity, text: L.s("최고 강도까지 올렸습니다", "Pushed to max intensity", ja: "最高強度まで上げました"))
            }
        }
        // 후반 오르막 코스에서 오른 심박은 사실대로 — 빌드업은 계획이라 유형 문구가 먼저
        if diff >= 8, workoutType != .buildUp,
           let climb = GradeAdjustedPace.halvesNetClimb(detail?.altitudeTimeProfile.map { (x: $0.offset, altitude: $0.altitude) } ?? []),
           climb.second - climb.first >= GradeAdjustedPace.halvesClimbGapM, climb.second > 0 {
            return HRCaption(kind: .lateClimb, text: L.s("후반 오르막에서 심박이 올랐습니다", "HR rose on the late climb", ja: "後半の上りで心拍が上がりました"))
        }
        // 빌드업은 후반 상승이 계획 — 문구만 유형별 (색은 동일)
        // 전후반 평균으로는 8bpm 안이어도 총평이 "심박이 먼저 오름"이면 같은 말을 한다 — 반으로 나누면
        // 중반이 섞여 마지막 구간 상승(149→161)이 묻혀 "끝까지 안정적"과 총평이 엇갈렸다(2026-10-08)
        let lateRose = RunSummaryBuilder.lateHRRoseFirst(activity: activity, detail: detail,
                                                         workoutType: workoutType, history: history)
        let d = Int(diff.rounded())
        let dStr = TabDigest.signed(d)
        let samePace = workoutType == .buildUp ? FormNarrative.samePaceHRRise(splits: detail?.splits ?? [], altitudeProfile: detail?.altitudeProfile ?? []) : nil
        if diff >= 8 || lateRose {
            let short = diff >= 8
                ? L.s("후반 심박 상승 · 전후반 \(dStr)bpm", "HR up late · \(dStr) bpm half to half", ja: "後半の心拍上昇 · 前後半\(dStr)bpm")
                : L.s("마지막 구간 심박 상승", "HR up in the final stretch", ja: "最後の区間で心拍上昇")
            return HRCaption(kind: .secondHalfRise, text: FormNarrative.hrSecondHalfRiseCaption(type: workoutType, samePaceRise: samePace), short: short)
        }
        if diff <= -5 {
            return HRCaption(kind: .easedOff, text: L.s("후반에 여유가 있었습니다", "Plenty left in the 2nd half", ja: "後半に余裕がありました"),
                             short: L.s("후반 심박 여유 · 전반 대비 \(dStr)bpm", "HR eased late · \(dStr) bpm vs first half", ja: "後半の心拍に余裕 · 前半比\(dStr)bpm"))
        }
        return HRCaption(kind: .steady, text: FormNarrative.hrSteadyCaption(type: workoutType, samePaceRise: samePace),
                         short: L.s("심박 끝까지 안정 · 전후반 \(dStr)bpm", "HR steady to the end · \(dStr) bpm half to half", ja: "心拍は最後まで安定 · 前後半\(dStr)bpm"))
    }

    // MARK: - 거리 문맥 (옮김: RhythmInsightCard.distanceContext — 카드는 앞에 "↑ "를 붙인다)

    static func distanceRankPhrase(rank: Int, sampleCount: Int) -> String? {
        guard rank <= 3 else { return nil }
        let L = AppLanguage.shared
        if rank == 1 {
            return L.s("최근 \(sampleCount)회 중 가장 긴 거리", "Longest of last \(sampleCount) runs", ja: "直近\(sampleCount)回で最長の距離")
        }
        return L.s("최근 \(sampleCount)회 중 \(rank)번째로 긴 거리", "#\(rank) of last \(sampleCount) by distance", ja: "直近\(sampleCount)回で\(rank)番目に長い距離")
    }

    // MARK: - 종류별 전·후반 판정 (옮김: RhythmInsightCard.buildWorkoutTypeFormParts)

    private static func fullSplits(_ splits: [SplitData]) -> [SplitData] { splits.filter { $0.distanceM >= 900 } }
    private static func halfAvgPace(_ s: [SplitData]) -> Double? {
        let p = s.map(\.paceSecPerKm); guard !p.isEmpty else { return nil }
        return p.reduce(0, +) / Double(p.count)
    }
    private static func halfAvgCadence(_ s: [SplitData]) -> Double? {
        let c = s.compactMap(\.avgCadence).map(Double.init); guard !c.isEmpty else { return nil }
        return c.reduce(0, +) / Double(c.count)
    }
    private static func halfAvgGCT(_ s: [SplitData]) -> Double? {
        let g = s.compactMap(\.avgGroundContactTime); guard !g.isEmpty else { return nil }
        return g.reduce(0, +) / Double(g.count)
    }

    /// 이지 분기 입력 — Z1~2 비율(보이는 존 합 대비). 보이는 존이 없으면 nil.
    static func easyLowZoneFraction(zones hrZones: [HRZoneData]) -> Double? {
        let visibleZones = hrZones.filter { $0.fraction > 0.01 }
        guard !visibleZones.isEmpty else { return nil }
        let totalFrac = visibleZones.map(\.fraction).reduce(0, +)
        let z2BelowFrac = hrZones.filter { $0.id <= 2 }.map(\.fraction).reduce(0, +)
        return totalFrac > 0 ? z2BelowFrac / totalFrac : 0
    }

    /// 이지 분기 (Z1~2 비율)
    static func easyVerdict(lowZoneFraction ratio: Double) -> Verdict {
        let L = AppLanguage.shared
        let pct = Int((ratio * 100).rounded())
        if ratio >= 0.80 {
            return Verdict(text: L.s("제대로 이지 페이스를 지켰습니다", "Great easy pacing — Z1–Z2 \(pct)%", ja: "しっかりイージーペースを守りました"),
                           isProblem: false, shade: .good,
                           short: L.s("이지 페이스 유지 · Zone 1~2 \(pct)%", "Easy pace held · \(pct)% in Zone 1–2", ja: "イージーペース維持 · ゾーン1~2 \(pct)%"))
        } else if ratio >= 0.50 {
            // 존 **비율**만 보는 규칙이라 "중간중간 올라갔다"처럼 시간 변화를 말하면 안 된다 —
            // 심박 곡선이 평평해도(차트 캡션 "끝까지 안정적") 이 문장이 떠서 서로 부딪쳤다.
            return Verdict(text: L.s("이지 구간이 \(pct)%였습니다. 조금 더 천천히 가도 좋습니다",
                                     "Easy zones \(pct)% — a little slower would help", ja: "イージー区間が\(pct)%でした。もう少しゆっくりでも大丈夫です"),
                           isProblem: true, shade: .neutral,
                           short: L.s("이지 구간 · Zone 1~2 \(pct)%", "Easy zones · \(pct)% in Zone 1–2", ja: "イージー区間 · ゾーン1~2 \(pct)%"))
        } else {
            return Verdict(text: L.s("이지런인데 심박이 꽤 높았습니다. 더 천천히 뛰어도 좋습니다", "HR ran high — try slower for true easy effort", ja: "イージーランなのに心拍がかなり高めでした。もっとゆっくり走っても大丈夫です"),
                           isProblem: true, shade: .caution,
                           short: L.s("이지런 기준 심박 높음 · 이지 구간 \(pct)%뿐", "High HR for an easy run · only \(pct)% in Zone 1–2", ja: "イージーランとしては高い心拍 · イージー域\(pct)%のみ"))
        }
    }

    /// 빌드업·템포·LSD/롱런 분기 — 전후반 폼(케이던스·지면접촉) 판정. 폼 탭이 쓴다(리듬 신호로는 내지 않는다).
    /// 다른 종류이거나 판정할 재료가 없으면 nil.
    static func typeFormVerdict(workoutType wt: WorkoutType, splits: [SplitData], formBaseline: RunningFormBaseline?) -> Verdict? {
        let L = AppLanguage.shared
        let fullSplits = fullSplits(splits)
        switch wt {
        case .buildUp:
            guard fullSplits.count >= 4 else { return nil }
            let half = fullSplits.count / 2
            let second = Array(fullSplits.suffix(fullSplits.count - half))
            guard let sp = halfAvgPace(second),
                  let sc = halfAvgCadence(second) else { return nil }
            guard let baseline = formBaseline else { return nil }
            guard let band = baseline.cutoffs.band(of: sp) else { return nil }
            guard let bandBl = baseline.bands[band],
                  let cadStat = bandBl.cadence,
                  bandBl.sampleCount >= FormBaselineEngine.minSamples else { return nil }
            let expectedCad = cadStat.median
            // "끌어올렸다"는 본인 전반 대비 실제로 올랐을 때만 — 기준값만 넘고 전반과 같으면
            // 폼 추이 카드의 "케이던스는 그대로예요"와 어긋난다.
            let fc = halfAvgCadence(Array(fullSplits.prefix(half)))
            let scI = Int(sc.rounded())
            if sc >= expectedCad, let fc, sc - fc >= 2 {
                let up = Int((sc - fc).rounded())
                return Verdict(text: L.s("후반에 케이던스까지 끌어올렸습니다", "Cadence lifted in the second half — great buildup", ja: "後半はピッチまで引き上げました"),
                               isProblem: false, shade: .good, aboutForm: true,
                               short: L.s("후반 케이던스 +\(up)spm · \(scI)spm", "Late cadence +\(up) spm · \(scI) spm", ja: "後半ケイデンス+\(up)spm · \(scI)spm"))
            } else if sc >= expectedCad {
                return Verdict(text: L.s("빨라진 후반에도 케이던스가 평소 이상이었습니다", "Cadence held above your usual as the pace rose", ja: "速くなった後半もピッチが普段以上でした"),
                               isProblem: false, shade: .good, aboutForm: true,
                               short: L.s("후반 케이던스 \(scI)spm · 평소 이상", "Late cadence \(scI) spm · above usual", ja: "後半ケイデンス\(scI)spm · 普段以上"))
            } else if sc <= expectedCad - 2 {
                let gap = Int((expectedCad - sc).rounded())
                return Verdict(text: L.s("페이스를 주로 보폭으로 올렸습니다. 케이던스를 함께 올리면 무릎 부담이 줄어듭니다", "Stride-led buildup — adding cadence reduces knee load", ja: "ペースを主にストライドで上げました。ピッチも一緒に上げると膝の負担が減ります"),
                               isProblem: true, shade: .caution, aboutForm: true,
                               short: L.s("보폭 위주 빌드업 · 후반 케이던스 평소 -\(gap)spm", "Stride-led buildup · late cadence -\(gap) spm vs usual", ja: "ストライド主体のビルドアップ · 後半ケイデンス普段比-\(gap)spm"))
            } else {
                return Verdict(text: L.s("평소 패턴대로 페이스를 올렸습니다", "Paced up in your usual pattern", ja: "普段のパターンどおりにペースを上げました"),
                               isProblem: false, shade: .neutral, aboutForm: true,
                               short: L.s("평소 패턴 빌드업 · 후반 케이던스 \(scI)spm", "Usual buildup pattern · late cadence \(scI) spm", ja: "普段どおりのビルドアップ · 後半ケイデンス\(scI)spm"))
            }

        case .tempo:
            guard fullSplits.count >= 4 else { return nil }
            let half = fullSplits.count / 2
            let first = Array(fullSplits.prefix(half))
            let second = Array(fullSplits.suffix(fullSplits.count - half))
            if let fg = halfAvgGCT(first), let sg = halfAvgGCT(second) {
                let gctRise = sg - fg
                let g = TabDigest.signed(Int(gctRise.rounded()))
                if gctRise <= -7 {
                    return Verdict(text: L.s("후반으로 갈수록 지면접촉이 짧아졌습니다. 템포 페이스가 잘 맞았습니다",
                                             "Ground contact shortened — tempo pace was well-matched", ja: "後半になるほど接地時間が短くなりました。テンポのペースがよく合っていました"),
                                   isProblem: false, shade: .good, aboutForm: true,
                                   short: L.s("후반 지면접촉 \(g)ms · 단축", "Late ground contact \(g) ms · shorter", ja: "後半の接地時間\(g)ms · 短縮"))
                } else if gctRise < 8 {
                    return Verdict(text: L.s("후반까지 폼이 흔들리지 않았습니다. 역치 페이스가 몸에 익었습니다", "Form held — tempo pace feels natural", ja: "後半までフォームがぶれませんでした。閾値ペースが体になじんでいます"),
                                   isProblem: false, shade: .good, aboutForm: true,
                                   short: L.s("후반까지 폼 유지 · 지면접촉 \(g)ms", "Form held late · ground contact \(g) ms", ja: "後半までフォーム維持 · 接地時間\(g)ms"))
                } else {
                    let rise = Int(gctRise.rounded())
                    return Verdict(text: L.s("후반에 지면접촉이 +\(rise)ms 늘었습니다. 템포 페이스가 살짝 빠를 수 있습니다",
                                             "Ground contact +\(rise)ms in second half — pace may be slightly high", ja: "後半に接地時間が+\(rise)ms増えました。テンポのペースが少し速いかもしれません"),
                                   isProblem: true, shade: .caution, aboutForm: true,
                                   short: L.s("후반 지면접촉 +\(rise)ms", "Late ground contact +\(rise) ms", ja: "後半の接地時間+\(rise)ms"))
                }
            } else if let fc = halfAvgCadence(first), let sc = halfAvgCadence(second) {
                let cadDrop = fc - sc
                if cadDrop < 2 {
                    let c = TabDigest.signed(Int((sc - fc).rounded()))
                    return Verdict(text: L.s("후반까지 폼이 흔들리지 않았습니다. 역치 페이스가 몸에 익었습니다", "Form held — tempo pace feels natural", ja: "後半までフォームがぶれませんでした。閾値ペースが体になじんでいます"),
                                   isProblem: false, shade: .good, aboutForm: true,
                                   short: L.s("후반까지 폼 유지 · 케이던스 \(c)spm", "Form held late · cadence \(c) spm", ja: "後半までフォーム維持 · ケイデンス\(c)spm"))
                } else {
                    let drop = Int(cadDrop.rounded())
                    return Verdict(text: L.s("후반에 케이던스가 \(drop)spm 줄었습니다. 템포 페이스가 살짝 빠를 수 있습니다",
                                             "Cadence dropped \(drop)spm — pace may be slightly high", ja: "後半にピッチが\(drop)spm落ちました。テンポのペースが少し速いかもしれません"),
                                   isProblem: true, shade: .caution, aboutForm: true,
                                   short: L.s("후반 케이던스 -\(drop)spm", "Late cadence -\(drop) spm", ja: "後半ケイデンス-\(drop)spm"))
                }
            } else {
                return nil
            }

        case .lsd, .longRun:
            guard fullSplits.count >= 4 else { return nil }
            let half = fullSplits.count / 2
            let first = Array(fullSplits.prefix(half))
            let second = Array(fullSplits.suffix(fullSplits.count - half))
            func heavier(_ short: String) -> Verdict {
                Verdict(text: L.s("후반에 폼이 조금 무거워졌습니다", "Form got a bit heavier in the second half", ja: "後半にフォームが少し重くなりました"),
                        isProblem: true, shade: .neutral, aboutForm: true, short: short)
            }
            func held(_ short: String) -> Verdict {
                Verdict(text: FormNarrative.formHeldCaption(type: wt), isProblem: false, shade: .good, aboutForm: true, short: short)
            }
            if let fg = halfAvgGCT(first), let sg = halfAvgGCT(second) {
                let gctRise = sg - fg
                let g = TabDigest.signed(Int(gctRise.rounded()))
                if gctRise <= -7 {
                    return Verdict(text: L.s("장거리인데 후반으로 갈수록 지면접촉이 짧아졌습니다", "Ground contact shortened through the long run", ja: "長い距離なのに後半になるほど接地時間が短くなりました"),
                                   isProblem: false, shade: .good, aboutForm: true,
                                   short: L.s("장거리 후반 지면접촉 \(g)ms · 단축", "Late ground contact \(g) ms · shorter", ja: "長距離後半の接地時間\(g)ms · 短縮"))
                } else if gctRise < 10 {
                    return held(L.s("후반까지 폼 유지 · 지면접촉 \(g)ms", "Form held late · ground contact \(g) ms", ja: "後半までフォーム維持 · 接地時間\(g)ms"))
                } else {
                    return heavier(L.s("후반 폼 무거워짐 · 지면접촉 \(g)ms", "Heavier form late · ground contact \(g) ms", ja: "後半フォームが重く · 接地時間\(g)ms"))
                }
            } else if let fc = halfAvgCadence(first), let sc = halfAvgCadence(second) {
                let c = TabDigest.signed(Int((sc - fc).rounded()))
                return fc - sc < 2
                    ? held(L.s("후반까지 폼 유지 · 케이던스 \(c)spm", "Form held late · cadence \(c) spm", ja: "後半までフォーム維持 · ケイデンス\(c)spm"))
                    : heavier(L.s("후반 폼 무거워짐 · 케이던스 \(c)spm", "Heavier form late · cadence \(c) spm", ja: "後半フォームが重く · ケイデンス\(c)spm"))
            } else {
                return nil
            }

        default:
            return nil
        }
    }

    /// 거리주·일반 분기 — 전후반 페이스·기복(CV) 판정. 일반 분기의 접지 개선/폼 무거움은 `aboutForm`.
    /// `altitudeProfile`은 일반 분기의 경사 혼입(전후반 오르내림 차) 판단용 — 카드가 넘기던 그대로.
    static func paceShapeVerdict(splits: [SplitData], workoutType wt: WorkoutType,
                                 altitudeProfile: [(distanceKm: Double, altitude: Double)] = []) -> Verdict? {
        let L = AppLanguage.shared
        let fullSplits = fullSplits(splits)
        switch wt {
        case .distanceRun:
            guard fullSplits.count >= 4 else { return nil }
            let half = fullSplits.count / 2
            let first = Array(fullSplits.prefix(half))
            let second = Array(fullSplits.suffix(fullSplits.count - half))
            guard let fp = halfAvgPace(first), let sp = halfAvgPace(second) else { return nil }
            let paceDelta = sp - fp
            let pd = TabDigest.signed(Int(paceDelta.rounded()))
            let pdShort = L.s("\(pd)초/km", "\(pd) s/km", ja: "\(pd)秒/km")
            var result: Verdict
            if paceDelta <= 0 {
                result = Verdict(text: L.s("후반에도 페이스가 떨어지지 않았습니다", "Pace held through the finish", ja: "後半もペースが落ちませんでした"),
                                 isProblem: false, shade: .good,
                                 short: L.s("후반 페이스 유지 · 전반 대비 ", "Pace held late · ", ja: "後半ペース維持 · 前半比") + pdShort)
            } else if paceDelta <= 25 {
                result = Verdict(text: L.s("후반에 페이스가 \(Int(paceDelta.rounded()))초 떨어졌습니다", "Pace slipped \(Int(paceDelta.rounded()))s in second half", ja: "後半にペースが\(Int(paceDelta.rounded()))秒落ちました"),
                                 isProblem: false, shade: .neutral,
                                 short: L.s("후반 페이스 ", "Late pace ", ja: "後半ペース") + pdShort)
            } else {
                result = Verdict(text: L.s("후반 페이스가 많이 떨어졌습니다. 초반이 빨랐을 수 있습니다", "Big pace drop — may have gone out too fast", ja: "後半のペースが大きく落ちました。序盤が速かったのかもしれません"),
                                 isProblem: true, shade: .caution, paceShape: .distanceRunDrop,
                                 short: L.s("후반 페이스 크게 하락 · ", "Big late pace drop · ", ja: "後半ペース大幅低下 · ") + pdShort)
            }
            // ⓪ GCT 개선 구절 — 페이스 하락이 있어도 접지 단축이면 덧붙임
            if let fg = halfAvgGCT(first), let sg = halfAvgGCT(second), (sg - fg) <= -7 {
                let delta = Int(abs((sg - fg).rounded()))
                result = Verdict(text: result.text + L.s(" 지면접촉은 \(delta)ms 짧아졌습니다.", " Ground contact shortened by \(delta) ms though.", ja: " 接地時間は\(delta)ms短くなりました。"),
                                 isProblem: result.isProblem, shade: result.shade, paceShape: result.paceShape,
                                 short: result.short.map { $0 + L.s(" · 지면접촉 -\(delta)ms", " · contact -\(delta) ms", ja: " · 接地-\(delta)ms") })
            }
            return result

        case .general:
            guard fullSplits.count >= 4 else { return nil }
            let half = fullSplits.count / 2
            let first = Array(fullSplits.prefix(half))
            let second = Array(fullSplits.suffix(fullSplits.count - half))
            let paces = fullSplits.map(\.paceSecPerKm)
            let mean = paces.reduce(0, +) / Double(paces.count)
            var cv = 0.0
            if mean > 0 {
                let sd = sqrt(paces.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(paces.count))
                cv = sd / mean * 100
            }
            // 전반·후반의 오르내림이 크게 다르면(내려갔다 올라오는 코스 등) 폼 변화가 경사 때문일 수 있다 —
            // 전후반 폼 비교(⓪①)는 하지 않고 페이스 고르기(②③)만 본다
            let slopeConfounded: Bool = {
                guard let c = GradeAdjustedPace.halvesNetClimb(altitudeProfile.map { (x: $0.distanceKm, altitude: $0.altitude) })
                else { return false }
                return abs(c.second - c.first) >= GradeAdjustedPace.halvesClimbGapM
            }()
            // 분기⓪ GCT 우선, 없으면 케이던스 폴백 (임계값 2)
            let fGCT = slopeConfounded ? nil : halfAvgGCT(first); let sGCT = slopeConfounded ? nil : halfAvgGCT(second)
            let firstCad = halfAvgCadence(first); let secondCad = halfAvgCadence(second)
            let formHeavy: Bool
            let formImproved: Bool   // ⓪ 후반 GCT ≤ -7ms — 개선
            // 요약용 숫자 — 판정에 쓴 값 그대로(GCT 우선, 없으면 케이던스)
            let formDeltaShort: String? = {
                if let fg = fGCT, let sg = sGCT {
                    return L.s("지면접촉 ", "ground contact ", ja: "接地時間") + TabDigest.signed(Int((sg - fg).rounded())) + "ms"
                }
                guard !slopeConfounded, let fc = firstCad, let sc = secondCad else { return nil }
                return L.s("케이던스 ", "cadence ", ja: "ケイデンス") + TabDigest.signed(Int((sc - fc).rounded())) + "spm"
            }()
            let cvStr = String(format: "%.1f", cv)
            if let fg = fGCT, let sg = sGCT {
                formHeavy    = (sg - fg) >= 10
                formImproved = (sg - fg) <= -7
            } else {
                let cadDrop: Double = (!slopeConfounded && firstCad != nil && secondCad != nil) ? (firstCad! - secondCad!) : 0
                formHeavy    = cadDrop >= 2
                formImproved = false  // 케이던스만으론 개선 판정 안 함
            }
            if formImproved {
                return Verdict(text: L.s("후반으로 갈수록 지면접촉이 짧아졌습니다", "Ground contact shortened as the run progressed", ja: "後半になるほど接地時間が短くなりました"),
                               isProblem: false, shade: .good, aboutForm: true,
                               short: L.s("후반 지면접촉 단축", "Shorter ground contact late", ja: "後半の接地時間短縮") + (formDeltaShort.map { " · " + $0 } ?? ""))
            } else if formHeavy {
                return Verdict(text: L.s("후반에 폼이 조금 무거워졌습니다", "Form got a bit heavier in the second half", ja: "後半にフォームが少し重くなりました"),
                               isProblem: true, shade: .neutral, aboutForm: true,
                               short: L.s("후반 폼 무거워짐", "Heavier form late", ja: "後半フォームが重く") + (formDeltaShort.map { " · " + $0 } ?? ""))
            } else if cv > 5 {
                return Verdict(text: L.s("페이스 기복이 있었습니다", "Pace varied through the run", ja: "ペースに波がありました"),
                               isProblem: true, shade: .neutral, paceShape: .varied,
                               short: L.s("페이스 기복 · km 변동 \(cvStr)%", "Uneven pace · \(cvStr)% km variation", ja: "ペースの波 · km変動\(cvStr)%"))
            } else if second.overallPaceSecPerKm - first.overallPaceSecPerKm >= FormPhase.paceDeltaSec {
                // 꾸준히 처진 러닝은 편차(cv)가 작아도 "고르게"가 아니다 — 6'20"→6'31"→6'47"이 "처음부터 끝까지 고르게"로 나왔다(2026-10-08)
                let d = TabDigest.signed(Int((second.overallPaceSecPerKm - first.overallPaceSecPerKm).rounded()))
                // 후반이 오르막(전후반 오르내림 차 15m↑, 후반이 오름)이면 지형 탓 — 심박 차트 "후반 오르막에서…"와 같은 말(2026-10-17)
                let lateClimb: Bool = {
                    guard let c = GradeAdjustedPace.halvesNetClimb(altitudeProfile.map { (x: $0.distanceKm, altitude: $0.altitude) })
                    else { return false }
                    return c.second - c.first >= GradeAdjustedPace.halvesClimbGapM && c.second > 0
                }()
                if lateClimb {
                    // 문장만 지형을 밝히고 판정 무게(isProblem)는 그대로 — 요약 블록·맨 위 요약의 느낌이 바뀌지 않게(2026-10-17 사용자 결정)
                    return Verdict(text: L.s("후반 오르막에서 페이스가 느려졌습니다", "Pace slowed on the late climb", ja: "後半の上りでペースが落ちました"),
                                   isProblem: true, shade: .neutral, paceShape: .slowedLate,
                                   short: L.s("후반 오르막 페이스 \(d)초/km", "Late climb pace \(d) s/km", ja: "後半の上りペース\(d)秒/km"))
                }
                return Verdict(text: L.s("후반으로 갈수록 페이스가 느려졌습니다", "Pace eased off in the second half", ja: "後半になるほどペースが落ちました"),
                               isProblem: true, shade: .neutral, paceShape: .slowedLate,
                               short: L.s("후반 페이스 \(d)초/km", "Late pace \(d) s/km", ja: "後半ペース\(d)秒/km"))
            } else if cv <= 3 {
                return Verdict(text: L.s("처음부터 끝까지 고르게 달렸습니다", "Even effort from start to finish", ja: "最初から最後まで均等に走りました"),
                               isProblem: false, shade: .good,
                               short: L.s("고른 페이스 · 변동 \(cvStr)%", "Even pace · \(cvStr)% variation", ja: "均等なペース · 変動\(cvStr)%"))
            } else {
                return nil
            }

        default:
            return nil
        }
    }

    // MARK: - 리듬 블록 신호 (설계 §4.1)

    private static func line(_ axisLabel: String?, in lines: [RunSummaryLine]) -> RunSummaryLine? {
        guard let lbl = axisLabel else { return nil }
        return lines.first { $0.axis == lbl }
    }

    /// 총평 줄 문장 — 상태어 + 근거(있으면 " — " 뒤에)
    private static func statement(_ l: RunSummaryLine) -> String {
        guard let e = l.evidence, !e.isEmpty else { return l.state }
        return l.state + " — " + e
    }

    static func signals(context c: RunSummaryBuilder.Context, input i: RunSummaryInput, lines: [RunSummaryLine]) -> [TabDigest.Signal] {
        var out: [TabDigest.Signal] = []
        func problem(_ p: Int, _ family: TabDigest.Family, _ text: String, _ direction: String?, short: String?) {
            out.append(TabDigest.Signal(tab: .rhythm, kind: .problem, priority: p, family: family, text: text,
                                        tone: .caution, direction: direction, short: short))
        }
        func good(_ p: Int, _ family: TabDigest.Family, _ text: String, short: String?) {
            out.append(TabDigest.Signal(tab: .rhythm, kind: .good, priority: p, family: family, text: text, tone: .good, short: short))
        }

        let heart = line(RunHeadline.Axis.heart.label, in: lines)

        // R1/R2 — 이지 의도인데 심박 높음 / 회복·테이퍼·대회 후 주인데 고강도 (총평 심박 줄 그대로)
        var heartProblem = false
        if let h = heart, h.tone == .neutral {
            let planEasy = i.workoutType != .race && i.planPhase.map { RunSummary.planEasyPhases.contains($0) } == true
            let easyIntent = RunSummary.easyIntentTypes.contains(i.workoutType)
            if planEasy || easyIntent {
                problem(planEasy ? 2 : 1, .unique, statement(h), h.next,
                        short: AppLanguage.shared.s("심박 ", "HR ", ja: "心拍 ") + h.state)
                heartProblem = true
            }
        }

        // R3 — 후반 진단(롱런 60분↑)
        var hasLate = false
        if let r = i.lateRun, r.kind != .held {
            let late = line(RunSummary.lateAxisLabel, in: lines)
            let text = late.map(statement) ?? {
                let e = LateRunDiagnosis.evidence(r, heatDeltaBpm: i.heatDeltaBpm)
                return e.isEmpty ? LateRunDiagnosis.state(r) : LateRunDiagnosis.state(r) + " — " + e
            }()
            // 심박 먼저·함께 = 후반 심박 / 다리 먼저 = 후반 폼(폼 카드 소유) / 힘 빠짐 = 후반 페이스
            let family: TabDigest.Family = {
                switch r.kind {
                case .cardio, .combined: return .lateHR
                case .legs:              return .lateForm
                default:                 return .latePace
                }
            }()
            problem(3, family, text, late?.next, short: LateRunDiagnosis.state(r))
            hasLate = true
        }

        // R4 — 후반 심박 상승(빌드업·오르막 아님) — 카드 심박 캡션과 같은 판정
        let hr = hrVerdict(samples: c.hrSamples, hrMax: c.hrMax, age: c.age, workoutType: c.workoutType,
                           activity: c.activity, detail: c.detail, history: c.history)
        // 빌드업은 후반 상승이 계획이라 문제로 내지 않는다(카드 캡션은 유형 문구로 그대로)
        if !hasLate, c.workoutType != .buildUp, let hr, hr.kind == .secondHalfRise {
            problem(4, .lateHR, hr.text, nil, short: hr.short)
        }

        // R5 — 의도 없는 템포 구간 머묾 / 고강도 많음 (R1/R2가 같은 심박 강도를 이미 말했으면 생략)
        let zoneFractions = Dictionary(c.hrZones.map { ($0.id, $0.fraction) }, uniquingKeysWith: +)
        let zone = zoneVerdict(fractions: zoneFractions, workoutType: c.workoutType,
                               heatSuffix: zoneHeatSuffix(heatHRModel: c.heatHRModel, temperatureC: c.activity.temperatureC))
        if !heartProblem, let zone, zone.isProblem {
            problem(5, .unique, zone.text, heart?.next, short: zone.short)
        }

        // R6 — 페이스: 후반 많이 떨어짐(거리주, .latePace) / 기복(.unique).
        // 일반 유형 후반 느려짐은 퍼포먼스 지구력(P6) 소유라 여기서 내지 않는다(설계 §5 — 조합기 순서상 리듬이 앞서므로 신호 단계에서 거름)
        let pace = paceShapeVerdict(splits: c.detail?.splits ?? [], workoutType: c.workoutType,
                                    altitudeProfile: c.detail?.altitudeProfile ?? [])
        if let pace, pace.isProblem, !pace.aboutForm {
            switch pace.paceShape {
            case .distanceRunDrop: problem(6, .latePace, pace.text, nil, short: pace.short)
            case .varied:          problem(6, .unique, pace.text, nil, short: pace.short)
            case .slowedLate, nil: break
            }
        }

        // 덧붙임 — 몸 풀리기 전 구간을 판정에서 뺐으면 그 사실(디커플링·전후반 값이 왜 바뀌었는지 보이게, 2026-10-22)
        if let w = hrWarmupPhase(c.detail?.splits ?? [], altitudeProfile: c.detail?.altitudeProfile ?? []) {
            let t = warmupPhaseText(w)
            out.append(TabDigest.Signal(tab: .rhythm, kind: .extra, priority: 1, family: .unique,
                                        text: t.text, tone: .neutral, short: t.short))
        }

        // 좋은 신호 — Zone 2 중심/이지 지킴 → 끝까지 안정/후반 여유 → 최근 N회 최장
        if c.workoutType == .easy, let f = easyLowZoneFraction(zones: c.hrZones) {
            let v = easyVerdict(lowZoneFraction: f)
            if v.isGood { good(1, .unique, v.text, short: v.short) }
        } else if let zone, zone.isGood {
            good(1, .unique, zone.text, short: zone.short)
        }
        if let hr, hr.kind == .steady || hr.kind == .easedOff {
            good(2, .unique, hr.text, short: hr.short)
        }
        if i.distanceRank == 1, let n = i.distanceSampleCount, n >= 5,
           let text = distanceRankPhrase(rank: 1, sampleCount: n) {
            good(3, .distanceRank, text,
                 short: AppLanguage.shared.s("최근 \(n)회 중 최장 거리", "Longest of last \(n) runs", ja: "直近\(n)回で最長距離"))
        }
        return out
    }

    /// 몸 풀리기 전 구간 사실 문장 — 요약 블록(text·short)과 리듬 카드 본문이 같은 문장을 쓴다.
    static func warmupPhaseText(_ w: HRWarmupPhase) -> (text: String, short: String) {
        let L = AppLanguage.shared
        return (L.s("처음 \(w.km)km는 심박이 \(w.peakBpm)까지 올랐다가 \(w.km + 1)km부터 \(w.settledBpm)로 내려왔습니다. 몸 풀기 전 구간이라 전후반 비교에서 뺐습니다.",
                    "HR reached \(w.peakBpm) in the first \(w.km) km and came down to \(w.settledBpm) from km \(w.km + 1). That warm-up stretch is left out of the half-to-half comparison.",
                    ja: "最初の\(w.km)kmは心拍が\(w.peakBpm)まで上がり、\(w.km + 1)kmから\(w.settledBpm)に下がりました。体がほぐれる前の区間なので前後半の比較から外しました。"),
                L.s("몸 풀기 전 \(w.km)km 심박 \(w.peakBpm) → \(w.settledBpm) · 비교에서 제외",
                    "Warm-up \(w.km) km HR \(w.peakBpm) → \(w.settledBpm) · excluded", ja: "ほぐれる前の\(w.km)km 心拍\(w.peakBpm) → \(w.settledBpm) · 比較から除外"))
    }

    /// 리듬 블록 기본 방향 — 거리 적응 줄의 next
    static func defaultDirection(lines: [RunSummaryLine]) -> String? {
        line(RunHeadline.Axis.distance.label, in: lines)?.next
    }
}
