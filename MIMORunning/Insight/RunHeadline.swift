import Foundation

/// 상세 화면 맨 위 "오늘의 인사이트" — 아래 카드(총평·폼·심박 효율)가 **이미 내린 판정**에서 고른 요약.
/// 판정은 하지 않는다. 후보를 순서대로 모아 첫 후보가 제목을 정하고, 다른 축의 다음 후보 하나를 사실로 덧붙이고,
/// 총평 "다음" 문장 하나를 붙인다. 설계: docs/superpowers/specs/2026-09-30-today-headline-design.md
struct RunHeadline: Equatable {
    enum Source: Equatable { case rareEvent, restSignal, goodSignal, mildCaution, context, fallback }
    let title: String
    let fact: String
    let next: String?
    let source: Source

    /// 총평 줄과 맞출 축 — 라벨 문자열은 RunSummary와 같아야 한다(비교는 여기서만).
    enum Axis: Equatable { case form, distance, heart, load, none
        var label: String? {
            let L = AppLanguage.shared
            switch self {
            case .form:     return L.s("러닝폼", "Form")
            case .distance: return L.s("거리 적응", "Distance")
            case .heart:    return L.s("심박", "Heart rate")
            case .load:     return L.s("훈련부하", "Training load")
            case .none:     return nil
            }
        }
    }

    struct Candidate: Equatable {
        let source: Source
        let title: String
        let fact: String
        let axis: Axis
        /// false면 제목 후보가 아니고 두 번째 사실로만 쓴다(예: 8km 미만의 "끝까지 버틴")
        var titleEligible: Bool = true
    }

    /// 역치 추정 맥락(중수 이상 러닝만) — 판정은 엔진(`mrThresholdAsOf`)이 하고 여기선 고르기만.
    /// 설계: docs/superpowers/specs/2026-10-01-threshold-estimate-design.md
    struct ThresholdContext: Equatable {
        /// 러닝 직전(시작 −1초) 기준 역치 페이스(초/km)
        var beforePace: Double?
        /// 러닝 직후(끝) 기준 역치 페이스(초/km)
        var afterPace: Double?
        /// 이 러닝 페이스 − 직전 역치 페이스(초/km). +면 역치보다 느림
        var tempoGapSec: Double?
    }

    /// 인사이트 엔진의 드문 사건 — 카드 판정보다 먼저
    static let rareThemes: Set<InsightTheme> = [.safety, .returnGap, .firstAchievement, .raceDay, .recordImproved, .milestone]
    /// "끝까지 버틴 러닝"을 제목으로 쓰는 최소 거리 — 짧은 러닝엔 과장
    static let heldTitleMinKm = 8.0

    static func make(insight: InsightResult?, summaryInput: RunSummaryInput?,
                     summaryLines: [RunSummaryLine], efficiency: RunInsight?,
                     threshold: ThresholdContext? = nil) -> RunHeadline? {
        // 재료 없음(워치 없는 러닝·재료 도착 전) → 엔진 결과 그대로
        guard let input = summaryInput, summaryLines.count >= 2 else {
            return insight.map { RunHeadline(title: $0.title, fact: $0.detail, next: nil, source: .fallback) }
        }
        let cands = candidates(insight: insight, input: input, lines: summaryLines, efficiency: efficiency,
                               threshold: threshold)
        guard let firstIdx = cands.firstIndex(where: { $0.titleEligible }) else {
            return insight.map { RunHeadline(title: $0.title, fact: $0.detail,
                                             next: nextAction(for: .none, lines: summaryLines), source: .fallback) }
        }
        let first = cands[firstIdx]
        var fact = first.fact
        if first.source != .rareEvent {
            let second = cands.enumerated().first { pair in
                let c = pair.element
                return pair.offset != firstIdx && c.source != .rareEvent && c.fact != first.fact &&
                    (first.axis == .none || c.axis != first.axis)
            }?.element
            if let s = second { fact += " · " + s.fact }
        }
        return RunHeadline(title: first.title, fact: fact,
                           next: nextAction(for: first.axis, lines: summaryLines), source: first.source)
    }

    // MARK: - 후보 (순서 = 배열 순서)

    static func candidates(insight: InsightResult?, input i: RunSummaryInput,
                           lines: [RunSummaryLine], efficiency: RunInsight?,
                           threshold: ThresholdContext? = nil) -> [Candidate] {
        let L = AppLanguage.shared
        func line(_ a: Axis) -> RunSummaryLine? { a.label.flatMap { lbl in lines.first { $0.axis == lbl } } }
        let planEasy = i.planPhase == "회복" || i.planPhase == "테이퍼"
        var out: [Candidate] = []

        // 1 드문 사건
        if let ins = insight, rareThemes.contains(ins.theme) {
            out.append(Candidate(source: .rareEvent, title: ins.title, fact: ins.detail, axis: .none))
        }
        // 2 쉬어야 할 신호
        if i.acuteChronic == .high || i.acuteChronic == .veryHigh, let l = line(.load) {
            out.append(Candidate(source: .restSignal, title: L.s("쌓이는 러닝", "Stacking Up"), fact: l.state, axis: .load))
        }
        if i.streakDays >= 4 && !planEasy {
            out.append(Candidate(source: .restSignal, title: L.s("쌓이는 러닝", "Stacking Up"),
                                 fact: L.s("\(i.streakDays)일 연속", "\(i.streakDays) days in a row"), axis: .load))
        }
        if let f = i.form, case .faded = f.late {
            out.append(Candidate(source: .restSignal, title: L.s("끝까지 달린 러닝", "Ran It Out"),
                                 fact: FormPhase.shortState(f), axis: .form))
        }
        // 3 좋은 신호
        // 역치 상승 — 이 러닝이 들어가며 역치 페이스 추정이 문턱 이상 빨라졌다(좋은 신호 맨 앞)
        if let b = threshold?.beforePace, let a = threshold?.afterPace, b - a >= MR_THRESHOLD_IMPROVE_SEC {
            out.append(Candidate(source: .goodSignal, title: L.s("역치를 밀어올린 러닝", "Raising the Threshold"),
                                 fact: L.s("역치 페이스 추정 \(mrFormatPace(b)) → \(mrFormatPace(a))",
                                           "Threshold pace est. \(mrFormatPace(b)) → \(mrFormatPace(a))"),
                                 axis: .none))
        }
        if let e = efficiency, e.category == .efficiency, e.tone == .good, let h = e.highlights.first {
            out.append(Candidate(source: .goodSignal, title: L.s("가벼워진 러닝", "Lighter Run"),
                                 fact: L.s("같은 페이스에 심박 \(h) 낮음", "HR \(h) lower at the same pace"), axis: .heart))
        }
        if let f = i.form, f.late == .held {
            out.append(Candidate(source: .goodSignal, title: L.s("끝까지 버틴 러닝", "Held to the End"),
                                 fact: L.s("폼은 끝까지 평소 범위", "Form stayed in range to the end"), axis: .form,
                                 titleEligible: i.distKm >= heldTitleMinKm))
        }
        if FormNarrative.isPlannedHighIntensity(i.workoutType), let l = line(.heart), l.tone == .good {
            out.append(Candidate(source: .goodSignal, title: L.s("한계를 미는 러닝", "Pushing the Edge"), fact: l.state, axis: .heart))
        }
        if i.distanceRank == 1, let n = i.distanceSampleCount, n >= 5 {
            out.append(Candidate(source: .goodSignal, title: L.s("경계를 넓힌 러닝", "Expanding Boundaries"),
                                 fact: L.s("최근 \(n)회 중 가장 긴 거리", "Longest of your last \(n) runs"), axis: .distance))
        }
        // 템포런의 역치 대비 — 두 번째 사실 전용(좋은 신호 맨 끝). 느리면 +, 빠르면 −
        if i.workoutType == .tempo, let gap = threshold?.tempoGapSec {
            let sec = Int(abs(gap).rounded())
            let sign = gap > 0 ? "+" : "−"
            let fact = abs(gap) < 1
                ? L.s("본인 역치 페이스 그대로", "Right at your threshold pace")
                : L.s("본인 역치 대비 \(sign)\(sec)초/km", "\(sign)\(sec)s/km vs your threshold")
            out.append(Candidate(source: .goodSignal, title: "", fact: fact, axis: .none, titleEligible: false))
        }
        // 4 가벼운 주의
        if let f = i.form, case .heavier = f.late {
            out.append(Candidate(source: .mildCaution, title: L.s("끝까지 달린 러닝", "Ran It Out"),
                                 fact: FormPhase.shortState(f), axis: .form))
        }
        if let l = line(.heart), l.tone == .neutral {
            out.append(Candidate(source: .mildCaution, title: L.s("쌓이는 러닝", "Stacking Up"), fact: l.state, axis: .heart))
        }
        // 5 맥락
        if planEasy, let p = i.planPhase {
            out.append(Candidate(source: .context, title: L.s("숨 고르는 러닝", "Catching Your Breath"),
                                 fact: p == "테이퍼" ? L.s("대회 계획 테이퍼 주", "Race plan: taper week")
                                                    : L.s("대회 계획 회복 주", "Race plan: recovery week"),
                                 axis: .load))
        }
        if i.workoutType == .easy, let l = line(.heart), l.tone == .good {
            out.append(Candidate(source: .context, title: L.s("숨 고르는 러닝", "Catching Your Breath"), fact: l.state, axis: .heart))
        }
        if let ins = insight, ins.theme == .consistent {
            out.append(Candidate(source: .context, title: ins.title, fact: ins.detail, axis: .none))
        }
        return out
    }

    // MARK: - 다음 행동

    /// 같은 축 줄의 next → 훈련부하 줄의 next → next가 있는 첫 줄 → nil
    static func nextAction(for axis: Axis, lines: [RunSummaryLine]) -> String? {
        if let lbl = axis.label, let n = lines.first(where: { $0.axis == lbl })?.next { return n }
        if let lbl = Axis.load.label, let n = lines.first(where: { $0.axis == lbl })?.next { return n }
        return lines.first(where: { $0.next != nil })?.next
    }
}
