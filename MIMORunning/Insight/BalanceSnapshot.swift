import Foundation

// 밸런스 탭 판정 엔진 — 스펙: docs/superpowers/specs/2026-11-11-balance-tab-design.md
// 폼 탭과 같은 판정 함수(FormNarrative.status)·같은 기준선 — 새 문턱 없음.
// 화면은 이 스냅샷만 그린다(저울 기울기 = tilt, 거미줄 = axes, 몸 상태 막대 = bodies).

enum BalanceLevel: Equatable { case good, normal, bad }

enum BalanceAxisKind: CaseIterable, Equatable { case heartRate, cadence, stride, groundContact, verticalOsc }

struct BalanceAxis: Equatable {
    let kind: BalanceAxisKind
    let value: Double                  // 실제 평균값
    let stat: FormStat                 // 그리는 평소 범위(참고 모드면 빌린 구간)
    let status: FormNarrative.Status   // 참고 모드면 .unknown
}

enum BalanceBodyKind: CaseIterable, Equatable { case sleep, hrv, load, vo2 }

struct BalanceBody: Equatable {
    let kind: BalanceBodyKind
    let level: BalanceLevel
    let display: String
}

/// 저울 접시 위 블록 — 들인 것(심박·체감·수면·HRV·부하) / 나온 것(케이던스·보폭·접지).
enum BalanceBlockKind: Equatable { case heartRate, effort, sleep, hrv, load, cadence, stride, groundContact }

/// 블록 색 — usual = 회색(범위 안·참고 모드·덜 든/더 나온 쪽), bad = 빨강(더 든 쪽·덜 나온 쪽), 몸 상태는 좋음·보통·나쁨 그대로.
enum BalanceTone: Equatable { case usual, good, normal, bad }

struct BalanceBlock: Equatable {
    let kind: BalanceBlockKind
    let tone: BalanceTone
    /// 0.1…1.0, 0.5 = 평소. 거미줄과 같은 눈금(평소 범위 경계 = 0.25·0.75). 나온 것 쪽 접지는 짧을수록 크다.
    let height: Double
}

struct BalanceSnapshot: Equatable {
    enum Mode: Equatable { case full, scaleOnly, bodyOnly }
    let mode: Mode
    let paceSecPerKm: Double?
    let axes: [BalanceAxis]        // mode == .full 일 때만 채움
    let bodies: [BalanceBody]      // 값 있는 것만, 순서 sleep·hrv·load·vo2
    let inputScore: Int            // 들인 것
    let outputScore: Int           // 나온 것
    /// 저울 심박 블록 — bodyOnly 가 아니면 폼 유무와 무관하게 채움(저울만 모드에도 심박 블록이 있게)
    var heartRateAxis: BalanceAxis? = nil
    /// 체감 강도 − 같은 종류 평소 강도. bodyOnly 이거나 둘 중 하나라도 없으면 nil
    var effortDelta: Int? = nil
    /// 참고 모드(빌린 구간·판정 불가) 또는 장거리 문맥 — 심박·폼 축을 판정하지 않는다(화면: "참고" 칩·점선 띠)
    var isReference: Bool = false
    /// −1…1. + = 왼쪽(들인 것)으로 기움 = 힘든 날, − = 가벼운 날
    var tilt: Double { max(-1, min(1, Double(inputScore - outputScore) / 4)) }

    struct Input: Equatable {
        var workoutType: WorkoutType
        var paceSecPerKm: Double?
        var hasForm: Bool                  // detail?.avgCadence != nil (폼 탭 노출 조건과 같음)
        var isReferenceBand: Bool          // 판정 불가 → 참고 모드
        /// 장거리 문맥(`TabDigestForm.Inputs.isLongDistanceContext`) — 폼 탭처럼 판단 유보: 심박·폼 축 판정·점수 없음
        var isLongDistance: Bool = false
        var heartRate: Double?;  var heartRateStat: FormStat?
        var cadence: Double?;    var cadenceStat: FormStat?
        var stride: Double?;     var strideStat: FormStat?
        var groundContact: Double?; var groundContactStat: FormStat?
        var verticalOsc: Double?;   var verticalOscStat: FormStat?
        var effort: Int?;        var effortTypeMedian: Int?
        var sleepHours: Double?; var usualSleepHours: Double?
        var hrvLevel: BalanceLevel?        // 접착 코드가 `hrvLevel(_:lastNightLow:)`로 채움
        var hrvDisplay: String?            // 접착 코드가 `MRHRVTrend.gradeLabel`로 채움 — 없으면 HRV 막대를 만들지 않음
        var load: EffortLoad.RatioLabel?
        var vo2: Double?;        var vo2SixMonths: [Double]
    }

    // MARK: - 몸 상태 단계

    static func sleepLevel(hours: Double, usual: Double) -> BalanceLevel {
        if hours >= usual || usual - hours < 0.5 { return .good }
        return usual - hours <= 1.0 ? .normal : .bad
    }

    static func loadLevel(_ l: EffortLoad.RatioLabel) -> BalanceLevel {
        switch l {
        case .steady: return .good
        case .low: return .normal
        case .high, .veryHigh: return .bad
        }
    }

    static func vo2Level(current: Double, sixMonths: [Double]) -> BalanceLevel? {
        guard let lo = sixMonths.min() else { return nil }
        return current >= lo ? .good : .bad
    }

    /// 총평 `gradeLabel` 순서와 같다: 불안정·낮음·어젯밤 낮음 → 나쁨, 좋음 → 좋음, 그 외 보통.
    static func hrvLevel(_ t: MRHRVTrend?, lastNightLow: Bool) -> BalanceLevel? {
        guard let t else { return nil }
        if t.isVolatile || t.state == .below || lastNightLow { return .bad }
        return t.isReadyHigh ? .good : .normal
    }

    // MARK: - 만들기

    static func make(_ i: Input) -> BalanceSnapshot? {
        // 몸 상태 막대 (값 있는 것만, 순서 고정)
        var bodies: [BalanceBody] = []
        if let h = i.sleepHours, let u = i.usualSleepHours {
            bodies.append(BalanceBody(kind: .sleep, level: sleepLevel(hours: h, usual: u),
                                      display: sleepText(h)))
        }
        if let lv = i.hrvLevel, let d = i.hrvDisplay {
            bodies.append(BalanceBody(kind: .hrv, level: lv, display: d))
        }
        if let l = i.load {
            let lv = loadLevel(l)
            bodies.append(BalanceBody(kind: .load, level: lv, display: loadText(l)))
        }
        if let v = i.vo2, let lv = vo2Level(current: v, sixMonths: i.vo2SixMonths) {
            bodies.append(BalanceBody(kind: .vo2, level: lv, display: String(format: "%.1f", v)))
        }

        // 모드
        let mode: Mode
        if i.workoutType == .interval {
            guard !bodies.isEmpty else { return nil }
            mode = .bodyOnly
        } else {
            let hasFormStat = i.cadenceStat != nil || i.strideStat != nil
                || i.groundContactStat != nil || i.verticalOscStat != nil
            if i.hasForm && hasFormStat {
                mode = .full
            } else if i.heartRate != nil && i.heartRateStat != nil {
                // 폼 없음 → 저울만. 심박(값과 기준)도 없으면 저울을 못 그린다 → 탭 숨김(스펙)
                mode = .scaleOnly
            } else {
                return nil
            }
        }

        // 판정 — 참고 모드·장거리 문맥·폭 없는 기준(상한 ≤ 하한)은 .unknown(빨간 점·점수 없음)
        let noJudge = i.isReferenceBand || i.isLongDistance
        func status(_ v: Double?, _ s: FormStat?, _ m: FormNarrative.Metric) -> FormNarrative.Status {
            guard !noJudge, let s, s.upper - s.lower > 0 else { return .unknown }
            return FormNarrative.status(rawValue: v, stat: s, metric: m)
        }

        // 축 (full 만)
        var axes: [BalanceAxis] = []
        if mode == .full {
            func axis(_ k: BalanceAxisKind, _ v: Double?, _ s: FormStat?, _ m: FormNarrative.Metric) -> BalanceAxis? {
                guard let v, let s else { return nil }
                return BalanceAxis(kind: k, value: v, stat: s, status: status(v, s, m))
            }
            // 심박은 bpm 정수 반올림 — 케이던스와 같은 정밀도
            axes = [axis(.heartRate, i.heartRate, i.heartRateStat, .cadence),
                    axis(.cadence, i.cadence, i.cadenceStat, .cadence),
                    axis(.stride, i.stride, i.strideStat, .stride),
                    axis(.groundContact, i.groundContact, i.groundContactStat, .groundContact),
                    axis(.verticalOsc, i.verticalOsc, i.verticalOscStat, .verticalOsc)].compactMap { $0 }
        }

        // 점수 (.unknown 은 0)
        var input = 0
        var output = 0
        if mode != .bodyOnly {
            switch status(i.heartRate, i.heartRateStat, .cadence) {
            case .above: input += 1
            case .below: input -= 1
            default: break
            }
            if let e = i.effort, let m = i.effortTypeMedian {
                if e - m >= 2 { input += 1 } else if e - m <= -2 { input -= 1 }
            }
        }
        input += bodies.filter { $0.kind != .vo2 && $0.level == .bad }.count
        if mode == .full {
            for (v, s, m) in [(i.cadence, i.cadenceStat, FormNarrative.Metric.cadence),
                              (i.stride, i.strideStat, .stride)] {
                switch status(v, s, m) {
                case .above: output += 1
                case .below: output -= 1
                default: break
                }
            }
            switch status(i.groundContact, i.groundContactStat, .groundContact) {
            case .below: output += 1     // 접지 짧음 = 좋음
            case .above: output -= 1
            default: break
            }
            // 수직 진폭은 점수 없음
        }

        // 저울 블록 재료 — 점수와 같은 판정(참고 모드면 .unknown)
        var hrAxis: BalanceAxis? = nil
        var effortDelta: Int? = nil
        if mode != .bodyOnly {
            if let v = i.heartRate, let s = i.heartRateStat {
                hrAxis = BalanceAxis(kind: .heartRate, value: v, stat: s, status: status(v, s, .cadence))
            }
            if let e = i.effort, let m = i.effortTypeMedian { effortDelta = e - m }
        }

        return BalanceSnapshot(mode: mode, paceSecPerKm: i.paceSecPerKm, axes: axes, bodies: bodies,
                               inputScore: input, outputScore: output,
                               heartRateAxis: hrAxis, effortDelta: effortDelta, isReference: noJudge)
    }

    // MARK: - 그리기 재료 (순수 계산 — 화면은 이 값만 그린다)

    /// 거미줄·블록 눈금: 0.5 + (값 − 평소) / (상한 − 하한) × 0.5, 0.1…1.0. 평소 범위 경계 = 0.25·0.75.
    static func radius(value: Double, stat: FormStat) -> Double {
        let w = stat.upper - stat.lower
        guard w > 0 else { return 0.5 }
        return max(0.1, min(1.0, 0.5 + (value - stat.median) / w * 0.5))
    }

    /// 빨간 점·빨간 블록이 되는 쪽 — 심박·접지는 위(더 들임·길어짐), 케이던스·보폭은 아래(덜 나옴).
    /// 수직 진폭은 방향 해석이 갈려 빨간 점을 찍지 않는다(저울 점수에도 없음).
    static func isAdverse(_ kind: BalanceAxisKind, _ status: FormNarrative.Status) -> Bool {
        switch kind {
        case .heartRate, .groundContact: return status == .above
        case .cadence, .stride: return status == .below
        case .verticalOsc: return false
        }
    }

    private static func tone(_ l: BalanceLevel) -> BalanceTone {
        switch l {
        case .good: return .good
        case .normal: return .normal
        case .bad: return .bad
        }
    }

    /// 몸 상태 블록 높이 — 좋음 = 평소(0.5), 보통 = 범위 경계(0.75), 나쁨 = 0.95(부담이 크다)
    private static func bodyHeight(_ l: BalanceLevel) -> Double {
        switch l {
        case .good: return 0.5
        case .normal: return 0.75
        case .bad: return 0.95
        }
    }

    /// 왼쪽 접시(들인 것) — 심박·체감·수면·HRV·부하 중 있는 것만. 유산소는 저울에 올리지 않는다.
    var inputBlocks: [BalanceBlock] {
        guard mode != .bodyOnly else { return [] }
        var out: [BalanceBlock] = []
        if let a = heartRateAxis {
            out.append(BalanceBlock(kind: .heartRate,
                                    tone: Self.isAdverse(.heartRate, a.status) ? .bad : .usual,
                                    height: Self.radius(value: a.value, stat: a.stat)))
        }
        if let d = effortDelta {
            // 점수 문턱(±2)이 평소 범위 경계(0.25·0.75)에 오게
            out.append(BalanceBlock(kind: .effort, tone: d >= 2 ? .bad : .usual,
                                    height: max(0.1, min(1.0, 0.5 + Double(d) * 0.125))))
        }
        let map: [BalanceBodyKind: BalanceBlockKind] = [.sleep: .sleep, .hrv: .hrv, .load: .load]
        for b in bodies {
            guard let k = map[b.kind] else { continue }
            out.append(BalanceBlock(kind: k, tone: Self.tone(b.level), height: Self.bodyHeight(b.level)))
        }
        return out
    }

    /// 오른쪽 접시(나온 것) — 케이던스·보폭·접지(full 만). 수직 진폭은 거미줄에만.
    var outputBlocks: [BalanceBlock] {
        guard mode == .full else { return [] }
        var out: [BalanceBlock] = []
        for a in axes {
            switch a.kind {
            case .cadence:
                out.append(BalanceBlock(kind: .cadence, tone: Self.isAdverse(.cadence, a.status) ? .bad : .usual,
                                        height: Self.radius(value: a.value, stat: a.stat)))
            case .stride:
                out.append(BalanceBlock(kind: .stride, tone: Self.isAdverse(.stride, a.status) ? .bad : .usual,
                                        height: Self.radius(value: a.value, stat: a.stat)))
            case .groundContact:
                // 접지는 짧을수록 더 나온 것 — 눈금을 뒤집는다(평소 0.5는 그대로)
                out.append(BalanceBlock(kind: .groundContact,
                                        tone: Self.isAdverse(.groundContact, a.status) ? .bad : .usual,
                                        height: max(0.1, min(1.0, 1.0 - Self.radius(value: a.value, stat: a.stat)))))
            case .heartRate, .verticalOsc:
                break
            }
        }
        return out
    }

    /// 수면 시간 — 정수면 "6h", 아니면 소수 한 자리 "6.5h".
    private static func sleepText(_ h: Double) -> String {
        let r = (h * 10).rounded() / 10
        return r == r.rounded() ? String(format: "%.0fh", r) : String(format: "%.1fh", r)
    }

    /// 부하 막대 글자 — 판정어가 아니라 부하 상태 그대로(색이 좋고 나쁨을 말한다).
    private static func loadText(_ l: EffortLoad.RatioLabel) -> String {
        let L = AppLanguage.shared
        switch l {
        case .low: return L.s("낮음", "low", ja: "低め")
        case .steady: return L.s("유지", "steady", ja: "維持")
        case .high: return L.s("높음", "high", ja: "高め")
        case .veryHigh: return L.s("크게 높음", "very high", ja: "かなり高め")
        }
    }
}
