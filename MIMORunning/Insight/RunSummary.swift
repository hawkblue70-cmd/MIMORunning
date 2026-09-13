import Foundation

/// 총평 한 줄 — 색점(톤) + 축 이름 + 짧은 상태어(관찰 사실, 등급어 아님).
struct RunSummaryLine: Equatable {
    enum Tone: Equatable { case good, neutral }
    let axis: String
    let state: String
    let tone: Tone
}

/// 총평 입력 — 각 카드가 이미 계산한 결론만 받는다. 없는 축은 nil/빈값 → 줄 생략.
struct RunSummaryInput {
    var form: FormPhase.Result? = nil
    var distKm: Double = 0
    var typicalKm: Double? = nil
    var workoutType: WorkoutType = .general
    /// 존 id(1~5) → 비율. 합이 1이 아니어도 된다(내부에서 보이는 존만 정규화).
    var zoneFractions: [Int: Double] = [:]
    /// 지난주 대비 증감률 (0.55 = +55%)
    var weekOverWeek: Double? = nil
    var acuteChronic: EffortLoad.RatioLabel? = nil
    var streakDays: Int = 0
    var vo2: Double? = nil
    var vo2AgeDecade: String = ""
    var vo2GenderLabel: String = ""
}

/// 총평 규칙. 축 순서 고정: 러닝폼 → 거리 적응 → 심박 → 훈련부하 → 유산소.
/// 상태어는 관찰 사실만. 톤은 초록(good)·노랑(neutral) 둘.
enum RunSummary {
    static let distanceRatioMin = 1.30
    /// 이지 의도 유형에서 Zone 3 이상 비율이 이 이상이면 "기준 높음"
    static let easyHighZoneFrac = 0.50
    static let loadJumpMin = 0.30
    static let vo2Bounds: [Double] = [15, 26, 33, 41, 57]
    static let easyIntentTypes: Set<WorkoutType> = [.easy, .longRun, .lsd, .distanceRun]

    /// VO2max 등급 — 리듬 카드 게이지 캡션과 같은 경계.
    static func vo2Level(_ vo2: Double) -> (index: Int, name: String) {
        let L = AppLanguage.shared
        let names = [L.s("낮음", "Low"), L.s("평균이하", "Below avg"), L.s("평균이상", "Above avg"), L.s("높음", "High")]
        var idx = vo2Bounds.count - 2
        for i in 0..<(vo2Bounds.count - 1) where vo2 < vo2Bounds[i + 1] { idx = i; break }
        return (idx, names[idx])
    }

    static func lines(_ i: RunSummaryInput) -> [RunSummaryLine] {
        [formLine(i), distanceLine(i), heartRateLine(i), loadLine(i), aerobicLine(i)].compactMap { $0 }
    }

    // MARK: 축별 규칙

    private static func formLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        guard let f = i.form else { return nil }
        let L = AppLanguage.shared
        return RunSummaryLine(axis: L.s("러닝폼", "Form"), state: FormPhase.shortState(f), tone: f.isHeld ? .good : .neutral)
    }

    private static func distanceLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        guard let t = i.typicalKm, t > 0, i.distKm >= t * distanceRatioMin else { return nil }
        let L = AppLanguage.shared
        let ratio = String(format: "%.1f", i.distKm / t)
        let axis = L.s("거리 적응", "Distance")
        guard let f = i.form else {
            return RunSummaryLine(axis: axis, state: L.s("평소 \(ratio)배", "\(ratio)× usual"), tone: .good)
        }
        return f.isHeld
            ? RunSummaryLine(axis: axis, state: L.s("평소 \(ratio)배, 범위 안", "\(ratio)× usual, form in range"), tone: .good)
            : RunSummaryLine(axis: axis, state: L.s("평소 \(ratio)배", "\(ratio)× usual"), tone: .neutral)
    }

    private static func heartRateLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        let visible = i.zoneFractions.filter { $0.value > 0.01 }
        let total = visible.values.reduce(0, +)
        guard total > 0 else { return nil }
        let L = AppLanguage.shared
        func frac(_ z: Int) -> Double { (visible[z] ?? 0) / total }
        let axis = L.s("심박", "Heart rate")

        if frac(2) >= 0.60 {
            return RunSummaryLine(axis: axis, state: L.s("딱 좋은 강도", "Just right"), tone: .good)
        }
        let high3 = frac(3) + frac(4) + frac(5)
        if easyIntentTypes.contains(i.workoutType), high3 >= easyHighZoneFrac {
            let pct = Int((high3 * 100).rounded())
            let label = i.workoutType.koreanLabel
            return RunSummaryLine(axis: axis,
                                  state: L.s("\(label) 기준 높음 · Zone 3 이상 \(pct)%", "High for a \(label.lowercased()) · \(pct)% in Zone 3+"),
                                  tone: .neutral)
        }
        guard let dom = visible.max(by: { $0.value < $1.value })?.key else { return nil }
        switch dom {
        case 1:  return RunSummaryLine(axis: axis, state: L.s("가벼운 회복 강도", "Light recovery"), tone: .good)
        case 2:  return RunSummaryLine(axis: axis, state: L.s("딱 좋은 강도", "Just right"), tone: .good)
        case 3:  return RunSummaryLine(axis: axis, state: L.s("템포 구간에 머묾", "Stayed in tempo zone"), tone: .neutral)
        default:
            return FormNarrative.isPlannedHighIntensity(i.workoutType)
                ? RunSummaryLine(axis: axis, state: L.s("계획대로 고강도", "High intensity, as planned"), tone: .good)
                : RunSummaryLine(axis: axis, state: L.s("고강도 구간이 많음", "Mostly high intensity"), tone: .neutral)
        }
    }

    private static func loadLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        guard i.weekOverWeek != nil || i.acuteChronic != nil else { return nil }
        let L = AppLanguage.shared
        let axis = L.s("훈련부하", "Training load")
        let wow = i.weekOverWeek ?? 0
        let jumped = wow >= loadJumpMin || i.acuteChronic == .high || i.acuteChronic == .veryHigh
        let lighter = i.acuteChronic == .low || (i.acuteChronic == nil && wow <= -loadJumpMin)

        var state: String
        let tone: RunSummaryLine.Tone
        if jumped {
            if let w = i.weekOverWeek {
                let pct = Int((w * 100).rounded())
                let sign = pct >= 0 ? "+" : ""
                state = L.s("이번 주 \(sign)\(pct)%", "This week \(sign)\(pct)%")
            } else {
                state = L.s("4주 평균 대비 높음", "Above 4-wk avg")
            }
            tone = .neutral
        } else if lighter {
            state = L.s("평소보다 가볍게", "Lighter than usual")
            tone = .good
        } else {
            state = L.s("4주 평균 수준", "Around 4-wk avg")
            tone = .good
        }
        if i.streakDays >= 3 {
            state += L.s(" · \(i.streakDays)일 연속", " · \(i.streakDays) days in a row")
        }
        return RunSummaryLine(axis: axis, state: state, tone: tone)
    }

    private static func aerobicLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        guard let v = i.vo2 else { return nil }
        let L = AppLanguage.shared
        let level = vo2Level(v)
        let g = i.vo2GenderLabel.isEmpty ? "" : " \(i.vo2GenderLabel)"
        return RunSummaryLine(axis: L.s("유산소", "Aerobic"),
                              state: L.s("\(i.vo2AgeDecade)\(g) 기준 \(level.name)", "\(level.name) for \(i.vo2AgeDecade)\(g)"),
                              tone: level.index >= 2 ? .good : .neutral)
    }
}
