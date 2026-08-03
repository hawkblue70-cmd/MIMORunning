import Foundation

// MARK: - WeeklyInsight 설계 요약
//
// ▶ 주간 총평(WeeklySummary) 3요소
//   구성   : 이번 2주 러닝 횟수 + 고강도(인터벌/템포) 비율 + 롱런 유무
//   몸의 신호: 조합 패턴(p5-p9, compositionChange) 최우선 1개의 factSummary. 없으면 "지표 안정".
//   흐름   : 연속 주수(streakWeeks) 또는 주간 거리 추세(recent 4주).
//   → assembleWeeklySummary()에서 조립. 폴백=2~3문장 템플릿, AI 시도=모든 패턴.
//
// ▶ 14일 날짜 기반 윈도우 (개수 기반 prefix 금지)
//   모든 지표(pace·HR·cadence·GCT·strideLength·vertOsc·vo2Max·power)와
//   구성 게이트(thisWindowIntenseCount), assembleWeeklySummary의 thisWindowRuns는
//   반드시 Calendar.current.date(byAdding: .day, value: -14, to: Date()) 날짜 필터를 사용.
//   [이력] runs.prefix(14) 개수 기반을 사용하던 시기에 pace·HR 방향 판정이 오래된 런에
//   오염돼 WeeklyInsightInputs의 paceDirection·hrDirection이 왜곡됐음 (2025-07 수정).
//
// ▶ 신호 패턴 (compositionChange)
//   compositionChange: 이번/직전 2주 고강도 횟수 차 ≥ 2 (prevWindowRunCount ≥ 3 충분성 게이트)
//   형태 지표(수직진폭·GCT·케이던스·보폭·파워)는 MDC 검증 결과 측정 오차 범위 안에 있어
//   패턴 판정에 사용하지 않는다. (잔차 차 / MDC = 0.09~0.60배 — 노이즈로 주의 성격을 정하는 것을 방지)
//
// ▶ 구성 게이트 (compositionChanged = true)
//   p5·p6를 억제 — 훈련 구성이 바뀌면 폼 신호가 구성 효과와 혼동될 수 있으므로.
//
// ▶ 총평 AI (현재 off — GrowthView.useAITotalComment = false)
//   2026-07 검증: 온디바이스 모델이 3요소 총평 규격을 재시도에도 못 맞춤
//   (감사합니다 종결, 동일 출력 반복). 템플릿 확정.
//   재평가 조건: FoundationModels 모델 업데이트 또는 iOS 27+ 새 API 출시 시.
//   구현은 InsightAIGenerator.generateWeeklyComment(patternKey:factSummary:) 에 유지.
//
// ▶ 반복 방지
//   동일 패턴 3주 연속 → 차순위 패턴 사용. streak은 예외(연속 자체가 의미).
//   최근 5회 이력: UserDefaults "mimo_weekly_pattern_history" ([String] 배열).
//   GrowthView.applyPatternRepeatGuard() 에서 처리.
//
// ▶ trendDirection 순서 주의
//   values 배열은 반드시 시간순(오래된→최신). 호출부에서 .reversed() 확인.
//
// ▶ 캐시 버전 규칙
//   templates·rules 변경 시 GrowthView.weeklyCommentVersion 상수를 올리면
//   해당 주의 메모리·디스크 캐시가 자동 무효화됨.

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

    // p21 기온 보정 페이스 (heatOk=true일 때만 유효)
    let heatOk: Bool
    let heatAvgTempC: Double          // 이번 주 야외 런 평균 기온 (°C)
    let heatActualPaceSec: Double     // 실제 평균 페이스 (sec/km)
    let heatRefPaceSec: Double        // 15°C 환산 페이스 (sec/km)
    let heatBasisText: String         // "본인 러닝 N회로 계산한 기온 계수 X%/°C 기준"

    // p22 심박 드리프트 (driftOk=true일 때만 유효)
    let driftOk: Bool
    let driftBpmActual: Double        // 이번 주 롱런 기온에서의 드리프트 (bpm/10min)
    let driftBpmRef: Double           // 15°C 기준 드리프트 (bpm/10min)
    let driftTempC: Double            // 이번 주 롱런 평균 기온

    // p23 같은 심박에서의 속도 비교
    let hrPaceDeltaSec: Double?       // 양수=최근 더 빠름, 음수=느림, nil=데이터 부족
}

struct WeeklyPattern {
    let priority: Int          // 낮을수록 우선
    let key: String
    let factSummary: String    // AI 입력용 사실 문자열 (확정 수치)
    var basis: String = ""     // 근거줄 (카드 하단 소자 — "" 이면 미표시)
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

// MARK: - WeeklySummary

/// 2주 훈련 총평 — 구성·몸의 신호·흐름 3요소.
/// `assembleWeeklySummary()` 로 생성. 폴백 템플릿·AI 입력 모두 이 타입에서.
struct WeeklySummary {
    let totalRunCount: Int
    let intenseRunCount: Int        // 인터벌·템포 횟수
    let hasLongRun: Bool            // 최장 런 > 14 km
    let bodySignalKey: String       // 조합 패턴 key 또는 ""
    let bodySignalFact: String      // 수치 사실 (AI입력용)
    let streakWeeks: Int
    let weekDistanceTrend: TrendDirection
    let topPatternKey: String       // detectWeeklyPatterns 최상위 key

    private static let comboKeys: Set<String> = ["compositionChange"]

    /// shortName 선택용 key — 조합 패턴 신호(있으면) > 전체 top 패턴
    var shortNamePatternKey: String {
        WeeklySummary.comboKeys.contains(bodySignalKey) ? bodySignalKey : topPatternKey
    }

    /// AI 입력: 3요소 합산 (한국어 사실)
    var aiFacts: String {
        var parts = ["구성: \(koCompositionFact)"]
        if !bodySignalFact.isEmpty { parts.append("몸의 신호: \(bodySignalFact)") }
        parts.append("흐름: \(koFlowFact)")
        return parts.joined(separator: " / ")
    }

    /// 폴백 2~3문장 템플릿
    func template(for weekOfYear: Int, isEnglish: Bool) -> String {
        let s1 = isEnglish ? enCompositionSentence(weekOfYear) : koCompositionSentence(weekOfYear)
        let s2 = isEnglish ? enBodySignalSentence(weekOfYear) : koBodySignalSentence(weekOfYear)
        let s3 = isEnglish ? enFlowSentence(weekOfYear) : koFlowSentence(weekOfYear)
        return [s1, s2, s3].filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: AI 사실 문자열

    private var koCompositionFact: String {
        guard totalRunCount > 0 else { return "기록 없음" }
        var base: String
        if intenseRunCount >= 3 {
            base = "인터벌·템포 \(intenseRunCount)회를 섞은 \(totalRunCount)회"
        } else if intenseRunCount >= 1 {
            base = "이지런 \(totalRunCount - intenseRunCount)회·인터벌 \(intenseRunCount)회"
        } else {
            base = "이지런 위주 \(totalRunCount)회"
        }
        return hasLongRun ? base + "·롱런 포함" : base
    }
    private var koFlowFact: String {
        if streakWeeks >= 2 { return "\(streakWeeks)주 연속" }
        switch weekDistanceTrend {
        case .up:   return "주간 거리 증가 중"
        case .down: return "주간 거리 감소 중"
        default:    return "주간 거리 유지"
        }
    }

    // MARK: 한국어 템플릿 문장

    private func koCompositionSentence(_ woy: Int) -> String {
        guard totalRunCount > 0 else { return "" }
        let variants: [String]
        if intenseRunCount >= 3 {
            variants = [
                "인터벌·템포를 \(intenseRunCount)회 섞은 \(totalRunCount)회 구성이었어요.",
                "고강도 훈련을 \(intenseRunCount)번 넣은 \(totalRunCount)회의 2주였어요.",
                "\(totalRunCount)회 중 \(intenseRunCount)회를 인터벌·템포로 채운 2주예요."
            ]
        } else if intenseRunCount >= 1 {
            variants = [
                "이지런 위주에 인터벌 \(intenseRunCount)회를 섞은 \(totalRunCount)회였어요.",
                "\(totalRunCount)번 달리는 동안 인터벌·템포가 \(intenseRunCount)번 있었어요.",
                "대부분 이지런으로, \(intenseRunCount)번의 인터벌이 포함된 구성이에요."
            ]
        } else {
            variants = [
                "이지런 위주로 \(totalRunCount)회 달린 2주였어요.",
                "편안한 페이스로 \(totalRunCount)번 쌓은 2주예요.",
                "\(totalRunCount)회 모두 이지런 위주로 이어졌어요."
            ]
        }
        let base = variants[woy % variants.count]
        return hasLongRun ? base + " 롱런도 한 번 있었어요." : base
    }

    private func koBodySignalSentence(_ woy: Int) -> String {
        let p = (woy + 1) % 3
        switch bodySignalKey {
        case "fatigueSign":
            return ["지면접촉과 진폭이 늘었어요. 몸이 피로 신호를 보내는 중일 수 있어요.",
                    "폼이 조금 무거워졌어요. 가볍게 달리는 날을 넣어봐도 좋아요.",
                    "접촉이 길어지고 진폭도 커졌어요. 쉬어가는 날이 도움이 될 수 있어요."][p]
        case "overstride":
            return ["보폭이 길어지고 케이던스가 줄었어요. 발이 몸 아래에 떨어지는 느낌을 살려보면 좋아요.",
                    "착지가 앞으로 나갔어요. 발 회전을 조금 높이면 자연스럽게 정리될 수 있어요.",
                    "스트라이드가 앞서고 접촉이 길어졌어요. 발이 무릎 아래에 오는 느낌으로 달려봐요."][p]
        case "economyPlus":
            return ["달리는 방식이 조금씩 달라지고 있어요. 몸이 리듬을 잡아가는 흐름이에요.",
                    "폼이 안정적으로 이어지고 있어요. 몸이 달리기에 익숙해지는 중이에요.",
                    "달리는 흐름이 자리를 잡아가고 있어요."][p]
        case "propulsion":
            return ["보폭이 자라고 추진력이 붙는 흐름이에요.",
                    "밀고 나가는 힘이 붙으면서 보폭이 넓어졌어요.",
                    "케이던스는 유지하며 보폭이 자랐어요. 러닝이 점점 힘차지고 있어요."][p]
        case "turnover":
            return ["케이던스가 높아지며 잰걸음의 리듬이 잡히는 중이에요.",
                    "발 회전이 빨라지고 리듬이 몸에 익어가고 있어요.",
                    "발 회전이 빨라지면서 폼이 안정되고 있어요."][p]
        case "compositionChange":
            return ["훈련 구성이 바뀌며 지표가 출렁이는 건 자연스러운 흐름이에요.",
                    "구성 변화에 몸이 적응 중이라 지표 변동은 자연스러워요.",
                    "고강도가 늘면 지표가 흔들려요. 몸이 적응하는 과정이에요."][p]
        default:
            // 폼 지표 안정 메시지는 MRFormObservationCard가 담당한다.
            // 이 위치에서 "지표" 언급은 중복이므로 침묵.
            return ""
        }
    }

    private func koFlowSentence(_ woy: Int) -> String {
        if streakWeeks >= 3 {
            return ["\(streakWeeks)주째 이어지는 흐름이에요.",
                    "\(streakWeeks)주 연속으로 달리고 있어요.",
                    "꾸준히 \(streakWeeks)주를 이어왔어요."][woy % 3]
        }
        let p = woy % 3
        switch weekDistanceTrend {
        case .up:
            return ["주간 거리가 조금씩 늘어나는 방향이에요.",
                    "달리는 거리가 꾸준히 쌓여가고 있어요.",
                    "주간 거리가 늘어나는 흐름이에요."][p]
        case .down:
            return ["주간 거리를 조절하며 가고 있어요.",
                    "이번 2주는 거리를 줄이며 달렸어요.",
                    "쉬어가는 흐름으로 달린 2주였어요."][p]
        default:
            return ""
        }
    }

    // MARK: 영어 템플릿 문장

    private func enCompositionSentence(_ woy: Int) -> String {
        guard totalRunCount > 0 else { return "" }
        var base: String
        if intenseRunCount >= 3 {
            base = "\(intenseRunCount) interval/tempo sessions in \(totalRunCount) runs this 2 weeks."
        } else if intenseRunCount >= 1 {
            base = "Mostly easy running with \(intenseRunCount) interval session\(intenseRunCount > 1 ? "s" : "") across \(totalRunCount) runs."
        } else {
            base = "Easy-run focused — \(totalRunCount) sessions over 2 weeks."
        }
        return hasLongRun ? base + " A long run was in the mix." : base
    }
    private func enBodySignalSentence(_ woy: Int) -> String {
        let p = (woy + 1) % 3
        switch bodySignalKey {
        case "fatigueSign":
            return ["Ground contact and oscillation up — your body may be signaling fatigue. A lighter day could help.",
                    "Form felt a bit heavier this stretch. An easy day would be a good response.",
                    "Contact longer, oscillation bigger. Some lighter running could be just what's needed."][p]
        case "overstride":
            return ["Stride lengthened and cadence dropped. Try landing closer to under your body.",
                    "Landing shifted forward. A slightly quicker turnover may sort it out naturally.",
                    "Stride ahead, contact longer. Focus on your foot landing under your knee."][p]
        case "economyPlus":
            return ["Running rhythm shifting. Your body is finding its pattern.",
                    "Form settling in consistently. Movement becoming familiar.",
                    "A steady stretch of running. The rhythm is taking shape."][p]
        case "propulsion":
            return ["Stride growing, more push-off force developing.",
                    "Push-off power building as stride widens.",
                    "Cadence steady, stride wider — drive is getting stronger."][p]
        case "turnover":
            return ["Cadence up, quicker-turnover rhythm forming.",
                    "Faster footfall, rhythm settling in.",
                    "Faster turnover stabilizing the form."][p]
        case "compositionChange":
            return ["Metric variation from the composition shift is natural — adaptation in progress.",
                    "With training composition changing, metric swings are expected. Body is adapting.",
                    "More intense sessions change the metrics. This is the adaptation phase."][p]
        default:
            return ""  // MRFormObservationCard handles form metric stability messaging
        }
    }
    private func enFlowSentence(_ woy: Int) -> String {
        let p = woy % 3
        if streakWeeks >= 3 {
            return ["\(streakWeeks)-week streak continuing.",
                    "\(streakWeeks) weeks straight — consistency is building.",
                    "Running every week for \(streakWeeks) weeks now."][p]
        }
        switch weekDistanceTrend {
        case .up:
            return ["Weekly mileage trending up.",
                    "Distance building week by week.",
                    "Running volume on the rise."][p]
        case .down:
            return ["Weekly mileage easing down.",
                    "Stepping back on distance this stretch.",
                    "Lighter mileage these 2 weeks."][p]
        default:
            return ""
        }
    }
}

/// 2주 훈련 총평을 조립. 런이 없으면 nil.
func assembleWeeklySummary(
    patterns: [WeeklyPattern],
    inputs: WeeklyInsightInputs,
    thisWindowRuns: [Activity],
    recentWeeklyKms: [Double]   // oldest → newest, up to 4 values
) -> WeeklySummary? {
    guard !thisWindowRuns.isEmpty else { return nil }
    let comboKeys: Set<String> = ["compositionChange"]
    let bodySignalPattern = patterns.first { comboKeys.contains($0.key) }
    let distanceTrend: TrendDirection = recentWeeklyKms.count >= 3
        ? trendDirection(values: Array(recentWeeklyKms.suffix(4))).direction
        : .insufficient
    return WeeklySummary(
        totalRunCount:     thisWindowRuns.count,
        intenseRunCount:   inputs.thisWindowIntenseCount,
        hasLongRun:        thisWindowRuns.contains { $0.distance / 1000 > 14 },
        bodySignalKey:     bodySignalPattern?.key ?? "",
        bodySignalFact:    bodySignalPattern?.factSummary ?? "",
        streakWeeks:       inputs.weekStreak,
        weekDistanceTrend: distanceTrend,
        topPatternKey:     patterns.first?.key ?? "easy"
    )
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

    #if DEBUG
    print("[폼] GCT=\(inputs.groundContactTime) VO=\(inputs.vertOsc) cadence=\(inputs.cadence) stride=\(inputs.strideLength) power=\(inputs.power) — 패턴 선택에 미사용")
    #endif

    // 구성 변화 게이트: 이번/직전 2주 고강도 횟수 차이 ≥ 2 (직전 2주 데이터 충분할 때만)
    let intenseCountDiff = inputs.thisWindowIntenseCount - inputs.prevWindowIntenseCount
    let compositionChanged = inputs.prevWindowRunCount >= 3 && abs(intenseCountDiff) >= 2

    // 구성 변화 패턴 (priority 5)
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

    // p20 스피드향상: 페이스↓(값=빨라짐) + 심박 flat or ↓
    if inputs.paceDirection == .down && (inputs.hrDirection == .flat || inputs.hrDirection == .down) {
        var facts: [String] = ["페이스 \(pct(inputs.paceChangeRatio))"]
        if inputs.hrDirection == .down { facts.append("심박 \(pct(inputs.hrChangeRatio))") }
        patterns.append(WeeklyPattern(
            priority: 30, key: "speed",
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

    // p21 기온 보정 페이스: 최근 7일 평균 기온 ≥20°C + heat.ok + ≥3 런 + 보정 차 ≥10초
    if inputs.heatOk {
        let actual = mrFormatPace(inputs.heatActualPaceSec)
        let ref    = mrFormatPace(inputs.heatRefPaceSec)
        let temp   = String(format: "%.0f", inputs.heatAvgTempC)
        patterns.append(WeeklyPattern(
            priority: 21, key: "heatAdjusted",
            factSummary: "\(temp)°C, 실제 \(actual)/km → 15°C 환산 \(ref)/km",
            basis: inputs.heatBasisText,
            shortNames: ["더운 날의 러닝", "기온 보정 페이스"],
            koTemplates: [
                "최근 7일 평균 \(actual)/km, 기온은 \(temp)°C였어요. 15°C였다면 \(ref) 정도예요.",
                "\(temp)°C에서 \(actual)/km로 달렸어요. 같은 몸으로 15°C에서 뛰면 \(ref)쯤 됩니다.",
                "이번 더위에서 \(actual)/km. 기온을 걷어내면 \(ref) 수준이에요.",
                "\(temp)°C의 최근 7일, 평균 \(actual)/km — 같은 노력이라면 15°C에서 \(ref)예요.",
            ],
            enTemplates: [
                "Averaged \(actual)/km over the last 7 days at \(temp)°C. At 15°C, that would be about \(ref).",
                "Running \(actual)/km at \(temp)°C this week. Same effort at 15°C: around \(ref).",
                "\(actual)/km in this heat. Strip away the temperature and you're at \(ref).",
                "\(temp)°C this week, \(actual)/km avg — same effort at 15°C would be \(ref).",
            ]
        ))
    }

    // p22 심박 드리프트: 이번 주 야외 롱런(≥40분) + drift.ok + 기온 ≥20°C
    if inputs.driftOk {
        let actual = String(format: "%.1f", inputs.driftBpmActual)
        let ref    = String(format: "%.1f", inputs.driftBpmRef)
        let temp   = String(format: "%.0f", inputs.driftTempC)
        patterns.append(WeeklyPattern(
            priority: 22, key: "driftWeek",
            factSummary: "\(temp)°C 롱런, 드리프트 \(actual)bpm/10분 (기준 \(ref)bpm/10분)",
            shortNames: ["드리프트 알림", "심박 드리프트"],
            koTemplates: [
                "긴 러닝에서 심박이 10분당 \(actual)bpm 올랐어요. \(temp)°C에서 평소는 \(ref) 정도예요.",
                "\(temp)°C 롱런에서 10분마다 \(actual)bpm씩 심박이 올랐어요. 15°C 기준으론 \(ref)bpm이에요.",
                "이번 주 롱런(\(temp)°C)에서 심박 드리프트가 10분당 \(actual)bpm이었어요. 기준 \(ref)bpm.",
            ],
            enTemplates: [
                "Heart rate drifted \(actual) bpm/10 min in your long run at \(temp)°C. Usual: \(ref).",
                "Long run at \(temp)°C: \(actual) bpm drift per 10 min. Reference (15°C): \(ref) bpm.",
                "This week's long run at \(temp)°C showed \(actual) bpm/10 min drift — baseline \(ref).",
            ]
        ))
    }

    // p23 같은 심박 속도: 최근 4주 vs 직전 4주 정규화 페이스 차 ≥5초
    if let delta = inputs.hrPaceDeltaSec {
        let secs  = Int(abs(delta).rounded())
        let dir   = delta > 0 ? "빠릅니다" : "느립니다"
        let enDir = delta > 0 ? "faster" : "slower"
        patterns.append(WeeklyPattern(
            priority: 23, key: "hrPaceWeek",
            factSummary: "같은 심박에서 8주 전보다 \(secs)초 \(dir)",
            shortNames: ["심박 기준 속도", "유산소 효율"],
            koTemplates: [
                "같은 심박에서 지난 8주보다 \(secs)초 \(dir).",
                "심박이 같아도 \(secs)초 \(dir). 유산소 효율이 달라졌어요.",
                "8주 전과 같은 심박인데 속도가 \(secs)초 \(dir).",
            ],
            enTemplates: [
                "At the same heart rate, you're \(secs) sec/km \(enDir) than the past 8 weeks.",
                "\(secs) sec/km \(enDir) at the same heart rate — aerobic efficiency shifted.",
                "Same heart rate, \(secs) sec/km \(enDir) vs 8 weeks ago.",
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

    return patterns.sorted { $0.priority < $1.priority }
}
