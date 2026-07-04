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
    let thisWindowIntenseCount: Int   // 이번 2주 고강도(인터벌/템포) 횟수
    let prevWindowIntenseCount: Int   // 직전 2주 고강도 횟수
    let prevWindowRunCount: Int       // 직전 2주 러닝 횟수 (게이트 충분성)
}

struct WeeklyPattern {
    let priority: Int          // 낮을수록 우선
    let key: String
    let factSummary: String    // AI 입력용 사실 문자열 (확정 수치)
    let shortNames: [String]   // 헤드라인 이름 풀 — weekOfYear로 순환
    let koTemplates: [String]
    let enTemplates: [String]

    func template(for weekOfYear: Int, isEnglish: Bool) -> String {
        let t = isEnglish ? enTemplates : koTemplates
        guard !t.isEmpty else { return "" }
        return t[weekOfYear % t.count]
    }

    func shortName(for weekOfYear: Int) -> String {
        guard !shortNames.isEmpty else { return "" }
        return shortNames[weekOfYear % shortNames.count]
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

    // 구성 변화 게이트: 이번/직전 2주 고강도 횟수 차이 ≥ 2 (직전 2주 데이터 충분할 때만)
    let intenseCountDiff = inputs.thisWindowIntenseCount - inputs.prevWindowIntenseCount
    let compositionChanged = inputs.prevWindowRunCount >= 3 && abs(intenseCountDiff) >= 2

    // TODO: 조합 패턴 검증 후 제거 — 게이트 억제 추적
    var debugSuppressed: [String] = []

    // p5 피로 신호: GCT↑ AND 수직진폭↑ AND 페이스 flat — 부정 계열, insufficient 제외, 구성변화 게이트
    let p5Conditions = inputs.groundContactTime != .insufficient
        && inputs.vertOsc != .insufficient
        && inputs.paceDirection != .insufficient
        && inputs.groundContactTime == .up
        && inputs.vertOsc == .up
        && inputs.paceDirection == .flat
    if p5Conditions {
        if compositionChanged {
            debugSuppressed.append("fatigueSign(p5)")
        } else {
            var facts: [String] = []
            if let r = inputs.metricChangeRatios[.groundContactTime] { facts.append("지면접촉 \(pct(r))") }
            if let r = inputs.metricChangeRatios[.verticalOscillation] { facts.append("수직진폭 \(pct(r))") }
            patterns.append(WeeklyPattern(
                priority: 5, key: "fatigueSign",
                factSummary: facts.joined(separator: ", "),
                shortNames: ["쉼표가 필요한 즈음", "몸이 말을 거는 주"],
                koTemplates: [
                    "이번 2주는 몸이 조금 무거웠을 수 있어요. 다음 러닝은 가볍게 가도 좋아요.",
                    "지면접촉이 늘고 진폭이 커졌어요. 충분한 쉬어감이 도움이 될 수 있어요.",
                    "페이스는 유지됐지만 폼이 달라졌어요. 몸이 신호를 보내는 중일 수 있어요.",
                    "폼이 조금 무거워진 2주였어요. 가볍게 달리는 날을 한 번 넣어봐도 좋아요.",
                    "지면접촉과 진폭이 함께 늘었어요. 짧고 가볍게 달려보는 것도 좋은 선택이에요.",
                    "몸이 피로를 표현하는 방식이에요. 천천히 달리는 날로 응답해줘도 좋아요."
                ],
                enTemplates: [
                    "Your form felt a bit heavier this 2 weeks. An easy run next time might be just right.",
                    "Ground contact up, oscillation up. Some lighter running could help.",
                    "Pace held, but form shifted. Your body might be sending a signal.",
                    "Form got a little heavier these 2 weeks. A gentle day could be a good reset.",
                    "Both contact and oscillation went up. A short, easy run might be a good next step.",
                    "This is how your body expresses fatigue. A slower run is a valid response."
                ]
            ))
        }
    }

    // p6 오버스트라이드: 보폭↑ AND 케이던스↓ AND GCT↑ — 부정 계열, insufficient 제외, 구성변화 게이트
    let p6Conditions = inputs.strideLength != .insufficient
        && inputs.cadence != .insufficient
        && inputs.groundContactTime != .insufficient
        && inputs.strideLength == .up
        && inputs.cadence == .down
        && inputs.groundContactTime == .up
    if p6Conditions {
        if compositionChanged {
            debugSuppressed.append("overstride(p6)")
        } else {
            var facts: [String] = []
            if let r = inputs.metricChangeRatios[.strideLength] { facts.append("보폭 \(pct(r))") }
            if let r = inputs.metricChangeRatios[.cadence] { facts.append("케이던스 \(pct(r))") }
            if let r = inputs.metricChangeRatios[.groundContactTime] { facts.append("지면접촉 \(pct(r))") }
            patterns.append(WeeklyPattern(
                priority: 6, key: "overstride",
                factSummary: facts.joined(separator: ", "),
                shortNames: ["착지를 돌아볼 때", "보폭이 앞서간 주"],
                koTemplates: [
                    "보폭이 커지면서 착지가 길어졌어요. 발이 몸 아래에 떨어지는 느낌을 살려보면 좋아요.",
                    "보폭이 앞서고 케이던스가 줄었어요. 발 회전을 조금 높여보는 게 도움이 될 수 있어요.",
                    "스트라이드가 길어졌어요. 발이 무릎 아래에 떨어지는지 한 번 살펴보면 좋아요.",
                    "지면접촉이 늘고 보폭이 앞섰어요. 케이던스를 먼저 챙기면 자연스럽게 정리될 수 있어요.",
                    "보폭과 접촉이 함께 늘었어요. 짧고 빠른 발 회전을 한 번 의식해보면 어떨까요.",
                    "착지가 앞으로 나간 2주였어요. 발이 몸 무게 중심 아래로 오는 느낌에 집중해보세요."
                ],
                enTemplates: [
                    "Stride lengthened, ground contact extended. Try landing closer to under your body.",
                    "Stride ahead, cadence down. A slightly quicker turnover might help.",
                    "Stride got longer. Worth checking if your foot lands under your knee.",
                    "More contact, more stride. Focusing on cadence first may naturally tighten things up.",
                    "Stride and contact both went up. A short drill on quick, light steps could be useful.",
                    "Your landing shifted forward these 2 weeks. Focus on keeping your foot under your center."
                ]
            ))
        }
    }

    // 구성 변화 패턴: p5/p6 억제 대체 (priority 5)
    if compositionChanged {
        let factStr = intenseCountDiff > 0
            ? "인터벌/템포 \(intenseCountDiff)회 증가"
            : "인터벌/템포 \(abs(intenseCountDiff))회 감소"
        patterns.append(WeeklyPattern(
            priority: 5, key: "compositionChange",
            factSummary: factStr,
            shortNames: ["강약이 있는 주", "훈련이 진해진 주"],
            koTemplates: [
                "이번 2주는 강한 훈련이 늘었어요. 지표가 출렁이는 건 자연스러운 반응이에요.",
                "훈련 구성이 바뀌면 몸도 적응 중이에요. 숫자보다 느낌에 더 귀 기울여봐요.",
                "고강도 훈련이 많아진 2주였어요. 회복에 조금 더 신경 써주는 게 좋아요.",
                "훈련 강도가 바뀌면 지표가 흔들려요. 추세를 조금 더 지켜봐요.",
                "이번 2주는 훈련이 진해졌어요. 지표 변화는 몸이 적응하는 신호예요.",
                "강한 훈련이 들어온 주였어요. 지표 해석보다 회복의 질을 먼저 챙겨요."
            ],
            enTemplates: [
                "More intense sessions this 2 weeks. Metric fluctuations are a natural response.",
                "Training composition shifted. Listen to how your body feels, not just the numbers.",
                "Higher intensity these 2 weeks. A bit more attention to recovery would help.",
                "Training intensity changed — give the trend a little more time to settle.",
                "Harder sessions this 2 weeks. Metric changes are a sign of adaptation.",
                "A more intense stretch. Recovery quality matters more than the numbers right now."
            ]
        ))
    }

    // p7 이코노미 개선: GCT↓ AND 수직진폭↓. power flat/down이면 factSummary 보강
    if inputs.groundContactTime == .down && inputs.vertOsc == .down {
        var facts: [String] = []
        if let r = inputs.metricChangeRatios[.groundContactTime] { facts.append("지면접촉 \(pct(r))") }
        if let r = inputs.metricChangeRatios[.verticalOscillation] { facts.append("수직진폭 \(pct(r))") }
        if (inputs.power == .flat || inputs.power == .down),
           let r = inputs.metricChangeRatios[.power] { facts.append("파워 \(pct(r))") }
        patterns.append(WeeklyPattern(
            priority: 7, key: "economyPlus",
            factSummary: facts.joined(separator: ", "),
            shortNames: ["가벼워지는 러닝", "힘이 덜 드는 러닝", "스미는 리듬"],
            koTemplates: [
                "접촉이 짧아지고 진폭도 줄었어요 — 같은 힘으로 더 가볍게 달리는 중이에요.",
                "지면 접촉과 수직 진폭이 함께 줄었어요. 러닝 이코노미가 올라가고 있어요.",
                "더 낮게, 더 조용하게 달리고 있어요. 폼이 자리를 잡아가는 중이에요.",
                "발이 가볍게 땅을 짚고 있어요. 자연스럽게 폼이 정리되고 있어요.",
                "접촉 시간이 줄고 탄성도 줄었어요 — 에너지가 앞으로 더 잘 가고 있어요.",
                "폼이 경제적으로 바뀌고 있어요. 이게 쌓이면 오랫동안 달릴 수 있어요."
            ],
            enTemplates: [
                "Contact shorter, oscillation down — running the same with less effort.",
                "Ground contact and vertical oscillation both reduced. Economy is improving.",
                "Running lower and quieter. Your form is finding its place.",
                "Feet landing light. Form naturally tidying itself up.",
                "Less contact, less bounce — energy is channeling forward more efficiently.",
                "Your form is becoming more economical. That compounds over time."
            ]
        ))
    }

    // p8 추진력 발달: 보폭↑ AND 케이던스 flat AND 심박 flat/down
    if inputs.strideLength == .up
        && inputs.cadence == .flat
        && (inputs.hrDirection == .flat || inputs.hrDirection == .down) {
        var facts: [String] = []
        if let r = inputs.metricChangeRatios[.strideLength] { facts.append("보폭 \(pct(r))") }
        if inputs.hrDirection == .down { facts.append("심박 \(pct(inputs.hrChangeRatio))") }
        patterns.append(WeeklyPattern(
            priority: 8, key: "propulsion",
            factSummary: facts.joined(separator: ", "),
            shortNames: ["보폭이 자라는 러닝", "밀고 나가는 러닝"],
            koTemplates: [
                "케이던스는 안정되고 보폭만 넓어졌어요. 추진력이 자라고 있어요.",
                "같은 리듬에 발걸음이 길어졌어요. 힘이 붙고 있는 증거예요.",
                "리듬은 그대로, 보폭만 자랐어요. 땅을 미는 힘이 좋아지고 있어요.",
                "심박이 안정된 채로 보폭이 늘었어요. 효율이 올라가는 신호예요.",
                "케이던스를 지키며 보폭이 커졌어요. 러닝이 점점 힘차게 변하고 있어요.",
                "발걸음이 자라는 2주였어요. 같은 노력에 앞으로 더 나아가고 있어요."
            ],
            enTemplates: [
                "Cadence steady, stride widening. Propulsion is growing.",
                "Same rhythm, longer stride. A sign that strength is building.",
                "Rhythm held, stride expanded. Push-off power is improving.",
                "Stride grew with steady heart rate. An efficiency signal.",
                "Cadence kept, stride larger. Your running is getting more powerful.",
                "Growing stride these 2 weeks — covering more ground on the same effort."
            ]
        ))
    }

    // p9 턴오버 개선: 케이던스↑ AND 보폭 flat/down AND 페이스 flat
    if inputs.cadence == .up
        && (inputs.strideLength == .flat || inputs.strideLength == .down)
        && inputs.paceDirection == .flat {
        var facts: [String] = []
        if let r = inputs.metricChangeRatios[.cadence] { facts.append("케이던스 \(pct(r))") }
        patterns.append(WeeklyPattern(
            priority: 9, key: "turnover",
            factSummary: facts.joined(separator: ", "),
            shortNames: ["리듬이 잡히는 러닝", "잰걸음이 몸에 붙는 중"],
            koTemplates: [
                "케이던스가 올라가고 있어요. 빠른 발 회전이 몸에 익어가는 중이에요.",
                "발 회전이 빨라지며 폼이 안정되고 있어요. 좋은 방향이에요.",
                "리듬이 빨라지고 있어요. 자연스럽게 몸이 효율적인 폼을 찾아가고 있어요.",
                "케이던스가 높아지며 발이 가벼워지고 있어요. 잰걸음이 익숙해지는 중이에요.",
                "빠른 발 회전이 자리 잡혀가고 있어요. 러닝 폼의 기반이 단단해지고 있어요.",
                "케이던스가 자라는 2주였어요. 이 리듬이 쌓이면 폼 전체가 가벼워져요."
            ],
            enTemplates: [
                "Cadence is climbing. Quick turnover is becoming natural.",
                "Faster footfall, steadier form. Moving in the right direction.",
                "Rhythm is picking up. Your body is finding a more efficient stride naturally.",
                "Higher cadence, lighter feet. Quick steps are becoming familiar.",
                "Quick turnover is settling in. The foundation of your form is getting solid.",
                "Cadence grew these 2 weeks. As this builds, your whole stride gets lighter."
            ]
        ))
    }

    // p10 이코노미향상: power↑ + (GCT↓ or 보폭↑)
    if inputs.power == .up && (inputs.groundContactTime == .down || inputs.strideLength == .up) {
        var facts: [String] = []
        if let r = inputs.metricChangeRatios[.power] { facts.append("파워 \(pct(r))") }
        if inputs.groundContactTime == .down, let r = inputs.metricChangeRatios[.groundContactTime] { facts.append("지면접촉 \(pct(r))") }
        if inputs.strideLength == .up, let r = inputs.metricChangeRatios[.strideLength] { facts.append("보폭 \(pct(r))") }
        patterns.append(WeeklyPattern(
            priority: 10, key: "economy",
            factSummary: facts.joined(separator: ", "),
            shortNames: ["힘차고 가벼운 러닝", "추진력이 붙는 러닝"],
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
            shortNames: ["빨라지는 러닝", "페이스가 오르는 러닝", "수월해진 러닝"],
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
            shortNames: ["폼이 잡히는 러닝", "발걸음이 넓어진 러닝"],
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
            shortNames: ["심폐가 자라는 러닝", "숨이 고르는 러닝"],
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
        var facts: [String] = [
            "심박 \(pct(inputs.hrChangeRatio))",
            "페이스 \(pct(inputs.paceChangeRatio))",
            "이번 주 \(String(format: "%.1f", inputs.thisWeekDistanceKm))km"
        ]
        if inputs.vo2Max == .up, let r = inputs.metricChangeRatios[.vo2Max] { facts.append("유산소 \(pct(r))") }
        patterns.append(WeeklyPattern(
            priority: 50, key: "easy",
            factSummary: facts.joined(separator: ", "),
            shortNames: ["편해지는 페이스", "기반이 다져지는 중"],
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
            shortNames: ["쌓이는 러닝", "이어지는 러닝", "여무는 러닝"],
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
            shortNames: ["오늘도 한 걸음", "꾸준한 두 주"],
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
            shortNames: ["함께 달려요"],
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

    let sorted = patterns.sorted { $0.priority < $1.priority }

    // TODO: 조합 패턴 검증 후 제거
    func d(_ dir: TrendDirection) -> String {
        switch dir {
        case .up:           return "↑"
        case .down:         return "↓"
        case .flat:         return "→"
        case .insufficient: return "?"
        }
    }
    let dirLine = "pace:\(d(inputs.paceDirection)) hr:\(d(inputs.hrDirection)) cadence:\(d(inputs.cadence)) power:\(d(inputs.power)) stride:\(d(inputs.strideLength)) gct:\(d(inputs.groundContactTime)) vertOsc:\(d(inputs.vertOsc)) vo2Max:\(d(inputs.vo2Max))"
    let gateLine = "compositionGate:\(compositionChanged) (thisIntense=\(inputs.thisWindowIntenseCount) prevIntense=\(inputs.prevWindowIntenseCount) prevRuns=\(inputs.prevWindowRunCount))"
    let suppressedLine = debugSuppressed.isEmpty ? "-" : debugSuppressed.joined(separator: ", ")
    let finalLine = sorted.isEmpty ? "none" : sorted.map { "\($0.key)(p\($0.priority))" }.joined(separator: " > ")
    print("[WeeklyPattern DEBUG]\n  \(dirLine)\n  \(gateLine)\n  suppressed: [\(suppressedLine)]\n  final: \(finalLine)")

    return sorted
}
