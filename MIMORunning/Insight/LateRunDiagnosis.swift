import Foundation

/// 후반 진단 — 롱런 후반에 **무엇이 먼저 무너졌나**(다리 · 심박 · 에너지 · 둘 다) 또는 끝까지 유지했나.
///
/// 총평 '후반' 줄 · 대회 카드 제한 요인 · 조언 큐(롱런 후반 패턴)가 **이 함수 하나만** 쓴다 —
/// 같은 러닝을 세 곳이 다르게 말하지 않게.
///
/// - 구간: 폼 3단계(`FormPhase.phases`)의 중반(30~70%) 대 후반(70~100%). 초반은 워밍업이 섞여 쓰지 않는다.
/// - 다리: 폼 3단계의 후반 피로(`FormPhase.lateFatigue` — 그 페이스의 평소 범위 밖 + 중반보다 나빠짐).
///   기준선이 없으면(form == nil) 페이스가 5% 안일 때만 원값으로 본다(`MRDurabilityCheck`와 같은 게이트).
/// - 심박: 유산소 디커플링 — 중반 대비 후반 효율(GAP 속도 ÷ 심박) 하락률 5% 이상.
///   5%는 Friel의 코칭 관례(aerobic decoupling < 5% = 유산소 기반 충분). Maunder 2021(내구성 리뷰)이
///   같은 개념(장시간 운동 중 생리 지표의 표류)을 내구성으로 정리한다.
/// - 에너지: 다리·심박 신호 없이 페이스와 심박이 **함께** 떨어짐(20초/km↑ · 3bpm↓), 90분 이상에서만.
///   보급 기록이 없으므로 "가능성"으로만 말한다. 90분은 글리코겐 고갈이 문제 되기 시작하는 시간대(관행).
/// - 후반 가속(10초/km↑ 빨라짐)은 계획된 마무리 — 빨라지면 심박이 비선형으로 올라 디커플링이 과장되므로 심박 신호로 보지 않는다.
enum LateRunDiagnosis {
    enum Kind: String, Codable, Sendable {
        case held       // 끝까지 유지
        case legs       // 다리가 먼저
        case cardio     // 심박이 먼저
        case energy     // 후반 힘 빠짐(에너지 고갈 가능성)
        case combined   // 다리·심박 함께
    }

    struct Result: Equatable {
        let kind: Kind
        let mid: FormPhase.PhaseStats
        let late: FormPhase.PhaseStats
        /// 중반 대비 후반 효율 하락률(%). 양수 = 같은 속도에 심박이 더 듦. 심박이 없으면 nil.
        let decouplingPct: Double?
        /// 다리 신호가 된 지표(피로 방향, 순서 고정: 케이던스 → 보폭 → 접지). 없으면 빈 배열.
        let legMetrics: [FormNarrative.Metric]
        let durationMin: Double
        /// 심박 효율이 떨어지기 시작한 지점(km) — "벽은 갑자기 오지 않는다". 없으면 nil.
        var efficiencyOnsetKm: Double? = nil
        /// 페이스가 떨어지기 시작한 지점(km). 없으면 nil.
        var paceOnsetKm: Double? = nil
        /// 후반 − 중반 페이스(초/km, 실측). 양수 = 느려짐.
        var paceChangeSec: Double { late.paceSecPerKm - mid.paceSecPerKm }
        /// 후반 − 중반 평균 심박. 한쪽이라도 없으면 nil.
        var hrChange: Double? {
            guard let a = mid.avgHR, let b = late.avgHR else { return nil }
            return b - a
        }
        var isFastFinish: Bool { paceChangeSec <= -LateRunDiagnosis.fastFinishSec }
    }

    /// 총평·조언이 진단하는 최소 시간 — 영상의 "후반 벽"은 장시간 러닝의 이야기다.
    static let minDurationMin = 60.0
    /// 에너지 고갈 가능성을 말하는 최소 시간(관행 — 글리코겐이 문제 되기 시작하는 시간대)
    static let energyMinDurationMin = 90.0
    /// 유산소 디커플링 문턱(%) — Friel 코칭 관례
    static let decouplingThresholdPct = 5.0
    /// "느려졌다" 문턱 — 폼 3단계의 페이스 무너짐과 같은 값
    static let slowdownSec = FormPhase.fadePaceDropSec
    /// "후반 가속" 문턱 — 폼 3단계의 단계 간 페이스 차이와 같은 값
    static let fastFinishSec = FormPhase.paceDeltaSec
    /// 에너지 신호 — 페이스와 함께 심박도 이만큼 내려감
    static let energyHRDropBpm = 3.0
    // 기준선 없을 때의 다리 원값 판정 — MRDurabilityCheck와 같은 페이스 게이트·케이던스 문턱
    static let rawPaceGateFrac = MRDurabilityCheck.paceGateFrac
    static let rawCadenceDropFrac = MRDurabilityCheck.cadenceDropFrac
    static let rawStrideDropFrac = 0.03   // 임의로 정함 — 케이던스와 같은 폭
    static let rawGCTRiseFrac = 0.04      // 임의로 정함 — 250ms 기준 10ms, 폼 카드 유지 알약(+10ms)과 같은 폭

    /// 총평·조언이 진단하는 러닝인가 — 60분 이상 + 후반 속도 변화가 계획인 유형(인터벌·빌드업·템포) 제외.
    /// 대회 카드는 이 게이트 없이 `diagnose`를 직접 부른다(짧은 대회는 카드가 자체 규칙).
    static func applies(to type: WorkoutType, durationMin: Double) -> Bool {
        guard durationMin >= minDurationMin else { return false }
        switch type {
        case .interval, .buildUp, .tempo: return false
        default: return true
        }
    }

    /// - Parameters:
    ///   - form: 같은 러닝의 폼 3단계 결과(`FormPhase.result`). 있으면 다리 신호를 평소 범위로 본다.
    ///   - altitudeProfile: 단계별 GAP 배율(`FormPhase.phasePaceScales`)로 디커플링 속도를 보정한다.
    /// - Returns: 단계를 나눌 수 없거나(풀 스플릿 5개 미만), 이유를 모르는 감속(다리·심박·에너지 신호 없이 느려짐 —
    ///   쿨다운·정지일 수 있음), 심박이 없어 유지를 말할 수 없으면 nil.
    static func diagnose(splits: [SplitData], durationMin: Double, form: FormPhase.Result?,
                         altitudeProfile: [(distanceKm: Double, altitude: Double)] = []) -> Result? {
        let full = splits.filter { $0.distanceM >= 900 }
        guard let p = FormPhase.phases(full) else { return nil }
        let mid = p.mid, late = p.late
        guard mid.paceSecPerKm > 0, late.paceSecPerKm > 0 else { return nil }
        let scales = FormPhase.phasePaceScales(splits: full, altitudeProfile: altitudeProfile)
        let midGAP = mid.paceSecPerKm * (scales.mid > 0 ? scales.mid : 1)
        let lateGAP = late.paceSecPerKm * (scales.late > 0 ? scales.late : 1)

        // 심박 — GAP 속도 ÷ 심박 효율의 하락률
        let decoupling: Double? = {
            guard let mh = mid.avgHR, let lh = late.avgHR, mh > 0, lh > 0 else { return nil }
            let efMid = (1000 / midGAP) / mh
            let efLate = (1000 / lateGAP) / lh
            return (efMid - efLate) / efMid * 100
        }()

        // 다리 — 판정 불가(nil)는 신호 없음으로 본다
        let legs = legSignal(form: form, mid: mid, late: late, midGAP: midGAP, lateGAP: lateGAP) ?? []

        let paceChange = late.paceSecPerKm - mid.paceSecPerKm
        let fastFinish = paceChange <= -fastFinishSec
        let cardio = !fastFinish && (decoupling ?? 0) >= decouplingThresholdPct
        let slowed = paceChange >= slowdownSec
        let hrDropped: Bool = {
            guard let a = mid.avgHR, let b = late.avgHR else { return false }
            return b - a <= -energyHRDropBpm
        }()

        let kind: Kind
        if !legs.isEmpty && cardio {
            kind = .combined
        } else if cardio {
            kind = .cardio
        } else if !legs.isEmpty {
            kind = .legs
        } else if slowed && hrDropped && durationMin >= energyMinDurationMin {
            kind = .energy
        } else if slowed || decoupling == nil {
            return nil
        } else {
            kind = .held
        }
        let on = onsets(full: full, altitudeProfile: altitudeProfile)
        return Result(kind: kind, mid: mid, late: late, decouplingPct: decoupling,
                      legMetrics: legs, durationMin: durationMin,
                      efficiencyOnsetKm: on.efficiencyKm, paceOnsetKm: on.paceKm)
    }

    // MARK: - 시작 지점 — 페이스보다 심박이 먼저

    /// 효율 하락 시작 문턱 — 기준 대비 3%. 후반 전체 판정(5%)보다 낮은 "앞선 신호" 문턱(임의로 정함)
    static let onsetEfficiencyDropFrac = 0.03
    /// 페이스 하락 시작 문턱 — 기준보다 10초/km 느림(폼 3단계 단계 간 페이스 차이와 같은 값)
    static let onsetPaceDropSec = FormPhase.paceDeltaSec
    /// 3km 이동 중앙값이 연속 3번 문턱을 넘어야 시작으로 본다 — 언덕 하나·신호 대기 하나로 시점을 잡지 않게
    static let onsetWindow = 3
    static let onsetPersist = 3

    /// km별 효율(GAP 속도 ÷ 심박)과 페이스가 기준(15~45% 구간 중앙값 — 워밍업 뒤·후반 전)에서 벗어나기 시작한 지점.
    /// 30% 지점 이후만 본다. 풀 스플릿 8개 미만·심박 없는 스플릿이 있으면 효율 시점은 nil.
    static func onsets(full: [SplitData], altitudeProfile: [(distanceKm: Double, altitude: Double)])
        -> (efficiencyKm: Double?, paceKm: Double?) {
        let splits = full.sorted { $0.id < $1.id }
        guard splits.count >= 8 else { return (nil, nil) }
        let totalM = splits.map(\.distanceM).reduce(0, +)
        guard totalM > 0 else { return (nil, nil) }
        let segments = GradeAdjustedPace.gradeSegments(from: altitudeProfile)

        var startM: [Double] = []
        var cum = 0.0
        for sp in splits { startM.append(cum); cum += sp.distanceM }

        func gapScale(_ i: Int) -> Double {
            let lo0 = startM[i], hi0 = startM[i] + splits[i].distanceM
            var w = 0.0, c = 0.0
            for seg in segments {
                let lo = max(seg.start, lo0), hi = min(seg.end, hi0)
                guard hi > lo else { continue }
                w += seg.factor * (hi - lo); c += hi - lo
            }
            return c > 0 ? min(max(w / c, 0.7), 1.3) : 1
        }
        let pace = splits.map(\.paceSecPerKm)
        let ef: [Double?] = splits.indices.map { i in
            guard let hr = splits[i].avgHeartRate, hr > 0, pace[i] > 0 else { return nil }
            return (1000 / (pace[i] * gapScale(i))) / Double(hr)
        }
        func frac(_ i: Int) -> Double { (startM[i] + splits[i].distanceM / 2) / totalM }
        func median(_ v: [Double]) -> Double? {
            guard !v.isEmpty else { return nil }
            let s = v.sorted(); let m = s.count / 2
            return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
        }
        let refIdx = splits.indices.filter { frac($0) >= 0.15 && frac($0) < 0.45 }
        guard refIdx.count >= 2 else { return (nil, nil) }
        let refPace = median(refIdx.map { pace[$0] })
        let refEF = median(refIdx.compactMap { ef[$0] })

        /// i에서 끝나는 창부터 연속으로 문턱을 넘는 첫 지점(그 창 가운데 km의 시작)
        func onset(_ breached: (Int) -> Bool?) -> Double? {
            let first = splits.indices.first { frac($0) >= 0.30 && $0 >= onsetWindow - 1 } ?? splits.count
            var i = first
            while i < splits.count {
                var ok = true
                var j = i
                while j < min(i + onsetPersist, splits.count) {
                    guard let b = breached(j), b else { ok = false; break }
                    j += 1
                }
                // 남은 창이 연속 조건보다 적으면(끝 무렵) 있는 만큼만 — 단, 최소 2개
                if ok && j - i >= min(onsetPersist, 2) {
                    let mid = i - onsetWindow / 2
                    return startM[max(mid, 0)] / 1000
                }
                i += 1
            }
            return nil
        }
        /// 3km 이동 중앙값 — 평균이면 한 km의 이상치(신호 대기·언덕)가 창 3개를 연달아 끌어내린다
        func rolling(_ v: [Double?], _ i: Int) -> Double? {
            let w = v[(i - onsetWindow + 1)...i]
            guard w.allSatisfy({ $0 != nil }) else { return nil }
            return median(w.compactMap { $0 })
        }
        let effKm: Double? = refEF.flatMap { r in
            onset { i in rolling(ef, i).map { $0 < r * (1 - onsetEfficiencyDropFrac) } }
        }
        let paceKm: Double? = refPace.flatMap { r in
            onset { i in rolling(pace.map { Optional($0) }, i).map { $0 >= r + onsetPaceDropSec } }
        }
        return (effKm, paceKm)
    }

    /// 다리 신호만 — 대회 카드 '폼 유지력'·'거리별 폼 유지력' 표가 쓴다(시간 게이트 없음, 풀 스플릿 5개↑).
    /// - Returns: 피로 방향으로 무거워진 지표. 빈 배열 = 유지. nil = 판정 불가(폼 데이터 없음 · 기준선 없이 페이스가 5% 넘게 변함).
    static func legSignal(splits: [SplitData], form: FormPhase.Result?,
                          altitudeProfile: [(distanceKm: Double, altitude: Double)] = [])
        -> (metrics: [FormNarrative.Metric], mid: FormPhase.PhaseStats, late: FormPhase.PhaseStats)? {
        let full = splits.filter { $0.distanceM >= 900 }
        guard let p = FormPhase.phases(full) else { return nil }
        let scales = FormPhase.phasePaceScales(splits: full, altitudeProfile: altitudeProfile)
        let midGAP = p.mid.paceSecPerKm * (scales.mid > 0 ? scales.mid : 1)
        let lateGAP = p.late.paceSecPerKm * (scales.late > 0 ? scales.late : 1)
        guard let m = legSignal(form: form, mid: p.mid, late: p.late, midGAP: midGAP, lateGAP: lateGAP) else { return nil }
        return (m, p.mid, p.late)
    }

    private static func legSignal(form: FormPhase.Result?, mid: FormPhase.PhaseStats, late: FormPhase.PhaseStats,
                                  midGAP: Double, lateGAP: Double) -> [FormNarrative.Metric]? {
        if let f = form {
            let set = FormPhase.lateFatigue(late: f.signals.late, latePhase: f.phases.late, midPhase: f.phases.mid)
            // 이지 프레임에서 케이던스만 내려간 건 편한 날의 자연스러운 변화(폼 카드와 같은 해석)
            return (f.isEasyFrame && set == [.cadence]) ? [] : set
        }
        return rawLegs(mid: mid, late: late, midGAP: midGAP, lateGAP: lateGAP)
    }

    /// 기준선 없을 때 — 페이스가 비슷할 때(GAP 5% 안)만 원값 변화를 다리 신호로 본다.
    /// 느려졌으면 케이던스·보폭·접지 변화가 속도로 설명되므로 판정하지 않는다(nil).
    private static func rawLegs(mid: FormPhase.PhaseStats, late: FormPhase.PhaseStats,
                                midGAP: Double, lateGAP: Double) -> [FormNarrative.Metric]? {
        let hasData = (mid.cadence != nil && late.cadence != nil) || (mid.stride != nil && late.stride != nil)
            || (mid.groundContact != nil && late.groundContact != nil)
        guard hasData, midGAP > 0, abs(lateGAP - midGAP) / midGAP <= rawPaceGateFrac else { return nil }
        var out: [FormNarrative.Metric] = []
        if let a = mid.cadence, let b = late.cadence, a > 0, b < a * (1 - rawCadenceDropFrac) { out.append(.cadence) }
        if let a = mid.stride, let b = late.stride, a > 0, b < a * (1 - rawStrideDropFrac) { out.append(.stride) }
        if let a = mid.groundContact, let b = late.groundContact, a > 0, b > a * (1 + rawGCTRiseFrac) { out.append(.groundContact) }
        return out
    }

    // MARK: - 문장 (총평 줄·대회 카드 공용)

    /// 짧은 상태어 — 총평 줄
    static func state(_ r: Result) -> String {
        let L = AppLanguage.shared
        switch r.kind {
        case .held:
            return r.isFastFinish ? L.s("후반 가속까지 유지", "Held with a fast finish")
                                  : L.s("끝까지 유지", "Held to the end")
        case .legs:     return L.s("다리가 먼저 지침", "Legs tired first")
        case .cardio:   return L.s("심박이 먼저 오름", "HR rose first")
        case .energy:   return L.s("후반 힘 빠짐", "Ran low late")
        case .combined: return L.s("다리·심박 함께", "Legs and HR together")
        }
    }

    /// 근거 — 중반→후반 페이스 · 심박 · 효율 · 무거워진 폼 지표. 모르는 값은 말하지 않는다.
    /// - heatDeltaBpm: 이 러닝의 더위 보정량. 심박 신호일 때 `RunSummary.heatNoteMinBpm` 이상이면 붙인다.
    static func evidence(_ r: Result, heatDeltaBpm: Double? = nil) -> String {
        let L = AppLanguage.shared
        var pieces: [String] = []
        pieces.append(L.s("중반→후반 페이스 \(mrFormatPace(r.mid.paceSecPerKm))→\(mrFormatPace(r.late.paceSecPerKm))",
                          "mid→late pace \(mrFormatPace(r.mid.paceSecPerKm))→\(mrFormatPace(r.late.paceSecPerKm))"))
        if let a = r.mid.avgHR, let b = r.late.avgHR {
            let ai = Int(a.rounded()), bi = Int(b.rounded())
            pieces.append(L.s("심박 \(ai)→\(bi)", "HR \(ai)→\(bi)"))
        }
        if let d = r.decouplingPct, !r.isFastFinish {
            let n = String(format: "%.0f", abs(d))
            if d >= 0.5 {
                pieces.append(L.s("같은 속도에 심박 \(n)% 더 듦", "\(n)% more HR per speed"))
            } else if d <= -0.5 {
                pieces.append(L.s("같은 속도에 심박 \(n)% 덜 듦", "\(n)% less HR per speed"))
            } else {
                pieces.append(L.s("심박 효율 그대로", "HR efficiency unchanged"))
            }
        }
        if !r.legMetrics.isEmpty {
            let names = r.legMetrics.map { m -> String in
                switch m {
                case .cadence:       return L.s("케이던스↓", "cadence↓")
                case .stride:        return L.s("보폭↓", "stride↓")
                case .groundContact: return L.s("지면접촉↑", "ground contact↑")
                case .verticalOsc:   return L.s("수직진폭↑", "vertical osc↑")
                }
            }
            pieces.append(names.joined(separator: " "))
        }
        if let o = onsetPiece(r) { pieces.append(o) }
        if (r.kind == .cardio || r.kind == .combined), let h = heatDeltaBpm, h >= RunSummary.heatNoteMinBpm {
            pieces.append(L.s("더위 +\(Int(h.rounded()))bpm", "heat +\(Int(h.rounded())) bpm"))
        }
        if r.kind == .energy {
            pieces.append(L.s("보급 기록이 없어 추정이에요", "estimated — no fueling data"))
        }
        return pieces.joined(separator: " · ")
    }

    /// 시작 지점 절 — 유지 날에는 말하지 않는다. 효율이 페이스보다 먼저(또는 페이스는 끝까지 유지)일 때
    /// "심박 효율 22km부터↓ · 페이스 28km부터↓", 페이스만 떨어졌으면 "페이스 28km부터↓".
    static func onsetPiece(_ r: Result) -> String? {
        guard r.kind != .held else { return nil }
        let L = AppLanguage.shared
        func km(_ v: Double) -> String { String(format: "%.0f", v) }
        switch (r.efficiencyOnsetKm, r.paceOnsetKm) {
        case let (e?, p?) where e < p:
            return L.s("심박 효율 \(km(e))km부터↓, 페이스는 \(km(p))km부터↓",
                       "HR efficiency slipped from \(km(e)) km, pace from \(km(p)) km")
        case let (e?, nil):
            return L.s("심박 효율 \(km(e))km부터↓, 페이스는 유지",
                       "HR efficiency slipped from \(km(e)) km while pace held")
        case let (_, p?):
            return L.s("페이스 \(km(p))km부터↓", "pace slipped from \(km(p)) km")
        default:
            return nil
        }
    }

    /// 다음 행동 — 유형별 대책(영상 요지: 거리만 늘리지 말고 무너지는 원인에 맞춰 훈련을 나눈다).
    /// - isRace: 대회면 "다음 대회" 기준 문장.
    static func next(_ r: Result, heatDeltaBpm: Double? = nil, isRace: Bool = false) -> String? {
        let L = AppLanguage.shared
        let hot = (heatDeltaBpm ?? 0) >= RunSummary.heatNoteMinBpm
        switch r.kind {
        case .held:
            if r.isFastFinish { return nil }
            return isRace
                ? L.s("끝까지 달리기를 남겼어요. 다음 대회는 목표 페이스를 조금 올려 봐도 좋아요.",
                      "You kept your running to the end. You could aim a little faster next race.")
                : L.s("다음 롱런은 마지막 15분을 목표 대회 페이스로 올려 보세요 — 지친 상태에서 페이스를 지키는 연습이에요.",
                      "On your next long run, lift the last 15 minutes to goal race pace — practice holding pace while tired.")
        case .legs:
            return isRace
                ? L.s("30km 이상을 버티는 롱런을 늘리기보다, 편한 페이스 롱런을 꾸준히 쌓고 근력·점프 운동을 주 2회 넣어 보세요.",
                      "Rather than grinding out 30 km+ long runs, keep stacking easy-paced long runs and add strength and jump work twice a week.")
                : L.s("거리를 무리하게 늘리기보다, 편한 페이스 롱런을 꾸준히 쌓고 근력·점프 운동을 주 2회 넣어 보세요.",
                      "Rather than forcing more distance, keep stacking easy-paced long runs and add strength and jump work twice a week.")
        case .cardio:
            if hot {
                return L.s("더운 날은 수분·나트륨을 챙기고 페이스를 5~10초/km 늦추세요.",
                           "On hot days, keep up fluids and sodium and ease pace by 5–10 s/km.")
            }
            return isRace
                ? L.s("다음 대회는 초반을 5~10초/km 늦게 시작하고, 롱런 후반에 목표 페이스를 넣어 지친 상태의 페이스를 연습해 보세요.",
                      "Start your next race 5–10 s/km slower, and practice goal pace late in long runs.")
                : L.s("다음 롱런은 중반 페이스를 10초/km 늦춰 보세요. 주 1회 템포 20분이 같은 페이스의 심박을 낮춰 줘요.",
                      "Ease mid-run pace by 10 s/km next long run. A weekly 20-minute tempo lowers HR at the same pace.")
        case .energy:
            return isRace
                ? L.s("다음 대회는 30~40분부터 탄수화물을 나눠 먹고, 롱런에서 같은 보급을 미리 연습해 두세요.",
                      "Next race, start carbs at 30–40 minutes and rehearse the same fueling in long runs.")
                : L.s("90분 넘는 롱런은 30~40분부터 시간당 30~60g 탄수화물을 나눠 먹어 보세요. 초반 10분은 목표보다 느리게요.",
                      "On runs over 90 minutes, take 30–60 g of carbs per hour from 30–40 minutes in, and start the first 10 minutes easier.")
        case .combined:
            return L.s("초반을 더 편하게 시작하고, 긴 롱런 한 번보다 주간 거리를 꾸준히 쌓아 기본 지구력을 올려 보세요.",
                       "Start easier, and build base endurance with steady weekly volume rather than one big long run.")
        }
    }
}

// MARK: - 기록 한 점 — 성장 탭 '후반 내구성' 카드

struct LateRunPoint: Identifiable, Equatable {
    static let windowWeeks = 16
    /// 카드가 요약 문장·유형 줄에 쓰는 최근 러닝 수
    static let recentCount = 6
    /// 추세 문장 — 앞 절반 대 뒤 절반 평균 효율 하락률 차이가 이 이상(%p)이어야 "좋아짐/나빠짐"(임의로 정함)
    static let trendDeltaPct = 1.5

    let id: UUID
    let date: Date
    let distanceKm: Double
    let kind: LateRunDiagnosis.Kind
    /// 중반 대비 후반 효율 하락률(%). 후반 가속·심박 없음이면 nil(추세 차트에서 제외).
    let decouplingPct: Double?
    let efficiencyOnsetKm: Double?

    /// 최근 러닝 요약 — 가장 많은 유형과 횟수. 동률이면 최근 쪽 유형.
    static func summary(_ pts: [LateRunPoint]) -> (kind: LateRunDiagnosis.Kind, count: Int, total: Int)? {
        let recent = Array(pts.suffix(recentCount))
        guard recent.count >= 2 else { return nil }
        var best: (LateRunDiagnosis.Kind, Int)? = nil
        for p in recent.reversed() {
            let c = recent.filter { $0.kind == p.kind }.count
            if best == nil || c > best!.1 { best = (p.kind, c) }
        }
        return best.map { ($0.0, $0.1, recent.count) }
    }

    /// 효율 하락률 추세 — 앞 절반 평균 − 뒤 절반 평균(양수 = 좋아짐). 점 4개 미만이면 nil.
    static func trendDelta(_ pts: [LateRunPoint]) -> Double? {
        let v = pts.compactMap(\.decouplingPct)
        guard v.count >= 4 else { return nil }
        let h = v.count / 2
        let early = v.prefix(h), late = v.suffix(v.count - h)
        return early.reduce(0, +) / Double(early.count) - late.reduce(0, +) / Double(late.count)
    }

    /// 카드 요약 문장 — 대상이 60분 이상 러닝이라 "롱런"이 아니라 "60분 이상 러닝"으로 부른다(10km 이지런도 들어옴).
    /// 전부 같은 유형이면 "N번 모두", 아니면 "N번 중 M번".
    static func sentence(_ pts: [LateRunPoint]) -> String? {
        guard let s = summary(pts) else { return nil }
        let L = AppLanguage.shared
        let n = s.total, c = s.count
        let all = c == n
        let headKo = all ? "최근 60분 이상 러닝 \(n)번 모두" : "최근 60분 이상 러닝 \(n)번 중 \(c)번"
        let headEn = all ? "In all of your last \(n) runs over 60 min" : "In \(c) of your last \(n) runs over 60 min"
        switch s.kind {
        case .held:
            return L.s("\(headKo) 후반까지 달리기를 남겼어요.", "\(headEn), you kept your running to the end.")
        case .cardio:
            return L.s("\(headKo) 심박이 먼저 올랐어요. 다리보다 심폐가 먼저 한계에 닿는 편이에요.",
                       "\(headEn), HR rose first — your cardio tends to hit the limit before your legs.")
        case .legs:
            return L.s("\(headKo) 다리가 먼저 지쳤어요. 심폐보다 근지구력이 먼저 한계에 닿는 편이에요.",
                       "\(headEn), legs tired first — muscular endurance tends to give out before cardio.")
        case .energy:
            return L.s("\(headKo) 후반에 힘이 빠졌어요. 보급을 점검해 볼 만해요.",
                       "\(headEn), you ran low late — worth checking your fueling.")
        case .combined:
            return L.s("\(headKo) 다리와 심박이 함께 무너졌어요.",
                       "\(headEn), legs and HR faded together.")
        }
    }

    /// 추세 문장 — 효율 하락률이 줄면 후반 내구성이 좋아지는 것
    static func trendSentence(_ pts: [LateRunPoint]) -> String? {
        guard let d = trendDelta(pts) else { return nil }
        let L = AppLanguage.shared
        let n = String(format: "%.1f", abs(d))
        if d >= trendDeltaPct {
            return L.s("후반 효율 하락이 이전보다 \(n)%p 줄었어요 — 후반 내구성이 좋아지고 있어요.",
                       "Late-run efficiency loss is down \(n) pts — your durability is improving.")
        }
        if d <= -trendDeltaPct {
            return L.s("후반 효율 하락이 이전보다 \(n)%p 늘었어요. 최근 롱런 강도나 회복을 살펴보세요.",
                       "Late-run efficiency loss is up \(n) pts. Check recent long-run intensity or recovery.")
        }
        return L.s("후반 효율 하락은 이전과 비슷해요.", "Late-run efficiency loss is about the same as before.")
    }
}
