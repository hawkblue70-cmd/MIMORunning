import Foundation

struct WeeklyInsightInputs {
    let paceDirection: TrendDirection
    let hrDirection: TrendDirection
    let cadence: TrendDirection
    let power: TrendDirection
    let strideLength: TrendDirection
    let groundContactTime: TrendDirection
    let vertOsc: TrendDirection
    let vo2Max: TrendDirection
    let paceChangeRatio: Double
    let hrChangeRatio: Double
    let metricChangeRatios: [TrendMetric: Double]
    let weekStreak: Int
    let runCount: Int
    let thisWeekDistanceKm: Double
}

struct WeeklyPattern {
    let priority: Int          // 낮을수록 우선
    let key: String
    let factSummary: String    // AI 입력용 사실 문자열 (확정 수치)
    let koTemplates: [String]
    let enTemplates: [String]

    func template(for weekOfYear: Int, isEnglish: Bool) -> String {
        let t = isEnglish ? enTemplates : koTemplates
        guard !t.isEmpty else { return "" }
        return t[weekOfYear % t.count]
    }
}

// 변화율을 부호 포함 정수 % 문자열로 포매팅.
private func pct(_ ratio: Double) -> String {
    let v = Int((ratio * 100).rounded())
    return v >= 0 ? "+\(v)%" : "\(v)%"
}

func detectWeeklyPatterns(_ inputs: WeeklyInsightInputs) -> [WeeklyPattern] {
    var patterns: [WeeklyPattern] = []
    let streak = inputs.weekStreak
    let count  = inputs.runCount

    // p10 이코노미향상: power↑ + (GCT↓ or 보폭↑)
    if inputs.power == .up && (inputs.groundContactTime == .down || inputs.strideLength == .up) {
        var facts: [String] = []
        if let r = inputs.metricChangeRatios[.power] { facts.append("파워 \(pct(r))") }
        if inputs.groundContactTime == .down, let r = inputs.metricChangeRatios[.groundContactTime] { facts.append("지면접촉 \(pct(r))") }
        if inputs.strideLength == .up, let r = inputs.metricChangeRatios[.strideLength] { facts.append("보폭 \(pct(r))") }
        patterns.append(WeeklyPattern(
            priority: 10, key: "economy",
            factSummary: facts.joined(separator: ", "),
            koTemplates: [
                "힘차게 밀어내며 발걸음이 가벼워졌어요",
                "추진력이 좋아지고 접촉 시간이 짧아졌어요",
                "더 힘있게, 더 가볍게 — 러닝이 효율적으로 바뀌고 있어요",
                "추진력이 붙고 발이 가벼워졌어요",
                "땅을 미는 힘이 좋아지고 있어요",
                "러닝 이코노미가 살아나는 2주였어요",
                "힘은 늘고 접촉은 짧아졌어요",
                "몸이 점점 효율적으로 달리고 있어요"
            ],
            enTemplates: [
                "Pushing off stronger, landing lighter",
                "More drive, shorter ground contact time",
                "Stronger and lighter — your running is getting more efficient",
                "More propulsion, lighter footfall",
                "Getting better at pushing off the ground",
                "Two weeks of improving running economy"
            ]
        ))
    }

    // p20 스피드향상: 페이스↓(값=빨라짐) + 심박 flat or ↓
    if inputs.paceDirection == .down && (inputs.hrDirection == .flat || inputs.hrDirection == .down) {
        var facts: [String] = ["페이스 \(pct(inputs.paceChangeRatio))"]
        if inputs.hrDirection == .down { facts.append("심박 \(pct(inputs.hrChangeRatio))") }
        patterns.append(WeeklyPattern(
            priority: 20, key: "speed",
            factSummary: facts.joined(separator: ", "),
            koTemplates: [
                "심박은 차분한데 페이스가 빨라졌어요",
                "같은 노력에 더 빠르게 달리고 있어요",
                "심폐가 페이스를 따라오고 있어요",
                "페이스가 올라가고 심박은 안정됐어요",
                "같은 심박으로 더 빠르게 나아가고 있어요",
                "심박과 페이스의 균형이 좋아지고 있어요",
                "페이스가 자연스럽게 빨라지고 있어요"
            ],
            enTemplates: [
                "Faster pace with the same heart rate",
                "Running quicker on the same effort",
                "Your cardio is keeping up with your pace",
                "Pace up, heart rate steady",
                "More speed on the same heartbeats",
                "Heart rate and pace finding a better balance"
            ]
        ))
    }

    // p30 폼개선: 보폭↑ + 케이던스 flat + (수직진동 flat or ↓)
    if inputs.strideLength == .up && inputs.cadence == .flat
        && (inputs.vertOsc == .flat || inputs.vertOsc == .down) {
        var facts: [String] = []
        if let r = inputs.metricChangeRatios[.strideLength] { facts.append("보폭 \(pct(r))") }
        if inputs.vertOsc == .down, let r = inputs.metricChangeRatios[.verticalOscillation] { facts.append("수직진폭 \(pct(r))") }
        patterns.append(WeeklyPattern(
            priority: 30, key: "form",
            factSummary: facts.joined(separator: ", "),
            koTemplates: [
                "보폭이 넓어지고 자세가 안정됐어요",
                "케이던스를 지키며 보폭이 효율적으로 늘었어요",
                "더 곧게, 더 넓게 — 폼이 자리 잡히고 있어요",
                "발걸음이 넓어지면서 리듬이 유지됐어요",
                "보폭이 늘어나고 폼이 안정되고 있어요",
                "자세가 바르게 잡히며 보폭도 넓어졌어요",
                "리듬은 그대로, 보폭만 넓어졌어요"
            ],
            enTemplates: [
                "Wider stride, steadier posture",
                "Cadence held, stride length growing efficiently",
                "Taller and wider — your form is settling in",
                "Stride widening while rhythm stays consistent",
                "Stride lengthening as form gets more stable",
                "Better posture, longer stride"
            ]
        ))
    }

    // p40 심폐향상: VO2max↑
    if inputs.vo2Max == .up {
        var facts: [String] = []
        if let r = inputs.metricChangeRatios[.vo2Max] { facts.append("유산소 \(pct(r))") }
        patterns.append(WeeklyPattern(
            priority: 40, key: "cardio",
            factSummary: facts.joined(separator: ", "),
            koTemplates: [
                "유산소 기반이 탄탄해지고 있어요",
                "심폐 능력이 꾸준히 오르고 있어요",
                "몸이 달리기를 더 잘하도록 적응하고 있어요",
                "심폐 지구력이 쌓이고 있어요",
                "유산소 능력이 점점 발전하고 있어요",
                "심폐가 한 단계 더 성장하고 있어요",
                "유산소 능력이 꾸준히 올라오고 있어요"
            ],
            enTemplates: [
                "Your aerobic base is getting stronger",
                "VO2max trending up — potential is growing",
                "Your body is adapting to run better",
                "Cardio endurance is building up",
                "Aerobic capacity continuing to develop",
                "Your cardio is stepping up"
            ]
        ))
    }

    // p50 이지런주간: 심박↓ + 페이스↑(값=느려짐) + 거리 있음
    if inputs.hrDirection == .down && inputs.paceDirection == .up && inputs.thisWeekDistanceKm > 0 {
        let facts: [String] = [
            "심박 \(pct(inputs.hrChangeRatio))",
            "페이스 \(pct(inputs.paceChangeRatio))",
            "이번 주 \(String(format: "%.1f", inputs.thisWeekDistanceKm))km"
        ]
        patterns.append(WeeklyPattern(
            priority: 50, key: "easy",
            factSummary: facts.joined(separator: ", "),
            koTemplates: [
                "오늘은 천천히, 내일을 위한 달리기예요",
                "여유 있게 달렸고, 심박도 잘 관리됐어요",
                "느린 달리기가 빠른 달리기를 만들어요",
                "회복하며 달리는 한 주였어요",
                "쉬어가는 주간도 훈련의 일부예요",
                "몸을 아끼며 달린 2주였어요",
                "심박을 낮게 유지하며 꾸준히 달렸어요"
            ],
            enTemplates: [
                "Easy today means faster tomorrow",
                "Relaxed running, heart rate well managed",
                "Slow runs build fast runs",
                "A recovery week done right",
                "Rest weeks are training too",
                "Two weeks of running smart, not hard"
            ]
        ))
    }

    // p60 연속경신: 4주 이상 연속
    if streak >= 4 {
        patterns.append(WeeklyPattern(
            priority: 60, key: "streak",
            factSummary: "\(streak)주 연속",
            koTemplates: [
                "\(streak)주 연속 — 최장 기록을 경신 중이에요 🔥",
                "\(streak)주 이어온 꾸준함, 그게 실력이에요",
                "멈추지 않은 \(streak)주, 이제 습관이 됐어요",
                "\(streak)주 연속 — 꾸준함이 빛나고 있어요",
                "쉬지 않고 이어온 \(streak)주예요",
                "매주 달린 \(streak)주, 루틴이 완성되고 있어요"
            ],
            enTemplates: [
                "\(streak) weeks straight — chasing a new streak record 🔥",
                "\(streak) weeks of consistency, that's real strength",
                "\(streak) unbroken weeks — it's a habit now",
                "\(streak) weeks straight — consistency is your superpower",
                "\(streak) weeks without a break",
                "Every week running for \(streak) weeks"
            ]
        ))
    }

    // p70 꾸준유지: 패턴 없음 + 이번 주 3회 이상
    if patterns.isEmpty && count >= 3 {
        patterns.append(WeeklyPattern(
            priority: 70, key: "consistent",
            factSummary: "이번 주 \(count)회 러닝",
            koTemplates: [
                "이번 2주, 꾸준히 달렸어요. 쌓이는 게 보여요",
                "달리는 날이 쌓여 기반이 됩니다",
                "꾸준함이 가장 강한 훈련법이에요",
                "2주를 성실하게 채웠어요",
                "작은 꾸준함이 큰 변화를 만들어요",
                "이 리듬, 이어가 봐요"
            ],
            enTemplates: [
                "Steady 2 weeks — it's adding up",
                "Running days stack into a foundation",
                "Consistency is the strongest training method",
                "Two solid weeks of showing up",
                "Small consistency, big change ahead",
                "Keep this rhythm going"
            ]
        ))
    }

    // 폴백: 러닝 없음 → 권유 (priority 99)
    if count == 0 {
        patterns.append(WeeklyPattern(
            priority: 99, key: "encourage",
            factSummary: "",
            koTemplates: [
                "2주간 데이터가 쌓이면 추세를 읽어드릴게요",
                "오늘 달리면 2주 뒤 변화가 보여요",
                "첫 발이 가장 어렵고, 가장 중요해요",
                "달리기 시작이 반이에요",
                "작은 시작이 큰 변화의 출발이에요",
                "오늘 나서면 내일이 달라져요"
            ],
            enTemplates: [
                "Run more and we'll spot the trend in 2 weeks",
                "Run today, see the change in 2 weeks",
                "The first step is the hardest, and the most important",
                "Getting started is half the battle",
                "Small beginnings lead to big changes",
                "Step out today and tomorrow will be different"
            ]
        ))
    }

    return patterns.sorted { $0.priority < $1.priority }
}
