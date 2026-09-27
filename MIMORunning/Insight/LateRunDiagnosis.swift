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

        // 다리
        let legs: [FormNarrative.Metric]
        if let f = form {
            let set = FormPhase.lateFatigue(late: f.signals.late, latePhase: f.phases.late, midPhase: f.phases.mid)
            // 이지 프레임에서 케이던스만 내려간 건 편한 날의 자연스러운 변화(폼 카드와 같은 해석)
            legs = (f.isEasyFrame && set == [.cadence]) ? [] : set
        } else {
            legs = rawLegs(mid: mid, late: late, midGAP: midGAP, lateGAP: lateGAP)
        }

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
        return Result(kind: kind, mid: mid, late: late, decouplingPct: decoupling,
                      legMetrics: legs, durationMin: durationMin)
    }

    /// 기준선 없을 때 — 페이스가 비슷할 때(GAP 5% 안)만 원값 변화를 다리 신호로 본다.
    /// 느려졌으면 케이던스·보폭·접지 변화가 속도로 설명되므로 말하지 않는다.
    private static func rawLegs(mid: FormPhase.PhaseStats, late: FormPhase.PhaseStats,
                                midGAP: Double, lateGAP: Double) -> [FormNarrative.Metric] {
        guard midGAP > 0, abs(lateGAP - midGAP) / midGAP <= rawPaceGateFrac else { return [] }
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
        if (r.kind == .cardio || r.kind == .combined), let h = heatDeltaBpm, h >= RunSummary.heatNoteMinBpm {
            pieces.append(L.s("더위 +\(Int(h.rounded()))bpm", "heat +\(Int(h.rounded())) bpm"))
        }
        if r.kind == .energy {
            pieces.append(L.s("보급 기록이 없어 추정이에요", "estimated — no fueling data"))
        }
        return pieces.joined(separator: " · ")
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
