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

struct BalanceSnapshot: Equatable {
    enum Mode: Equatable { case full, scaleOnly, bodyOnly }
    let mode: Mode
    let paceSecPerKm: Double?
    let axes: [BalanceAxis]        // mode == .full 일 때만 채움
    let bodies: [BalanceBody]      // 값 있는 것만, 순서 sleep·hrv·load·vo2
    let inputScore: Int            // 들인 것
    let outputScore: Int           // 나온 것
    /// −1…1. + = 왼쪽(들인 것)으로 기움 = 힘든 날, − = 가벼운 날
    var tilt: Double { max(-1, min(1, Double(inputScore - outputScore) / 4)) }

    struct Input: Equatable {
        var workoutType: WorkoutType
        var paceSecPerKm: Double?
        var hasForm: Bool                  // detail?.avgCadence != nil (폼 탭 노출 조건과 같음)
        var isReferenceBand: Bool          // 판정 불가 → 참고 모드
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

        let hasEffort = i.effort != nil && i.effortTypeMedian != nil
        let hasBodyInput = bodies.contains { $0.kind != .vo2 }

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
            } else if i.heartRateStat != nil || hasEffort || hasBodyInput {
                mode = .scaleOnly
            } else {
                return nil
            }
        }

        // 축 (full 만)
        var axes: [BalanceAxis] = []
        if mode == .full {
            func axis(_ k: BalanceAxisKind, _ v: Double?, _ s: FormStat?, _ m: FormNarrative.Metric) -> BalanceAxis? {
                guard let v, let s else { return nil }
                let st: FormNarrative.Status = i.isReferenceBand ? .unknown
                    : FormNarrative.status(rawValue: v, stat: s, metric: m)
                return BalanceAxis(kind: k, value: v, stat: s, status: st)
            }
            // 심박은 bpm 정수 반올림 — 케이던스와 같은 정밀도
            axes = [axis(.heartRate, i.heartRate, i.heartRateStat, .cadence),
                    axis(.cadence, i.cadence, i.cadenceStat, .cadence),
                    axis(.stride, i.stride, i.strideStat, .stride),
                    axis(.groundContact, i.groundContact, i.groundContactStat, .groundContact),
                    axis(.verticalOsc, i.verticalOsc, i.verticalOscStat, .verticalOsc)].compactMap { $0 }
        }

        // 점수 (참고 모드·.unknown 은 0)
        func status(_ v: Double?, _ s: FormStat?, _ m: FormNarrative.Metric) -> FormNarrative.Status {
            i.isReferenceBand ? .unknown : FormNarrative.status(rawValue: v, stat: s, metric: m)
        }
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

        return BalanceSnapshot(mode: mode, paceSecPerKm: i.paceSecPerKm, axes: axes, bodies: bodies,
                               inputScore: input, outputScore: output)
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
