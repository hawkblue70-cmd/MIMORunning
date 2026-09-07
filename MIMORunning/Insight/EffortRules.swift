import Foundation

struct EffortRuleInput {
    let effort: ResolvedEffort
    let type: WorkoutType
    let baseline: Int?
    let splits: [SplitData]
    let temperatureC: Double?
    let humidityPercent: Double?
}

struct EffortRuleOutput {
    let insights: [RunInsight]
    /// B/B′가 발화 → 기존 environmentInsight(체감 부담 문장)를 이 결과로 대체.
    let replacesEnvironment: Bool
}

/// 스펙 4.2. 순수 함수. 문장은 최대 3개(A 계열 1 + B 1 + C 1).
enum EffortRules {
    static let splitThreshold = 0.03
    static let hotC = 25.0
    static let humidPct = 75.0
    static let easyTypes: Set<WorkoutType> = [.easy, .lsd]
    static let hardTypes: Set<WorkoutType> = [.tempo, .interval, .race]

    static func evaluate(_ i: EffortRuleInput) -> EffortRuleOutput {
        let L = AppLanguage.shared
        let e = i.effort.value
        var out: [RunInsight] = []
        var replacesEnv = false
        let hl = ["\(e)"]

        // ── A 계열: 하나만 ──
        if easyTypes.contains(i.type) {
            let overBaseline = i.baseline.map { e >= $0 + 2 } ?? (e >= 7)
            if e >= 8 || overBaseline {
                out.append(RunInsight(
                    category: .intensity, tone: .caution, badge: L.s("강도 참고", "Effort Note"),
                    message: L.s("이지런인데 체감 강도가 \(e)이었어요. 이름은 이지여도 몸이 힘들었다면 그날은 이지런이 아니에요.",
                                 "Labeled easy, but effort was \(e)/10. If the body says hard, it wasn't an easy run."),
                    highlights: hl))
            } else if i.baseline != nil {
                out.append(matched(e))
            }
        } else if hardTypes.contains(i.type), let b = i.baseline {
            if e <= b - 2 {
                out.append(RunInsight(
                    category: .intensity, tone: .neutral, badge: L.s("강도 메모", "Effort"),
                    message: L.s("평소 같은 훈련보다 체감이 낮았어요. 여유 있게 소화한 날.",
                                 "Felt easier than your usual for this workout — a comfortable day."),
                    highlights: hl))
            } else {
                out.append(matched(e))
            }
        } else if i.baseline != nil {
            out.append(matched(e))
        }

        // ── B: 더위·습도 (기준선 필요) ──
        if let b = i.baseline {
            let hot   = (i.temperatureC ?? -100) >= hotC
            let humid = (i.humidityPercent ?? -1) >= humidPct
            if hot || humid {
                let header = envHeader(temp: i.temperatureC, hum: i.humidityPercent)
                if e >= b + 1 {
                    out.append(RunInsight(
                        category: .environment, tone: .neutral, badge: L.s("환경", "Conditions"),
                        message: L.s("\(header). 같은 페이스라도 더운 날은 체감이 1~2 높아지는 게 자연스러워요. 페이스보다 강도에 맞춰 뛰는 날.",
                                     "\(header). Same pace feels 1–2 points harder in heat — run to effort, not pace."),
                        highlights: [header]))
                    replacesEnv = true
                } else if e <= b {
                    out.append(RunInsight(
                        category: .environment, tone: .good, badge: L.s("환경", "Conditions"),
                        message: L.s("더운 날인데 체감이 평소 수준이었어요.",
                                     "Hot day, yet effort stayed at your usual level."),
                        highlights: [header]))
                    replacesEnv = true
                }
            }
        }

        // ── C: 스플릿 형태 (이지 유형 + 기준선+1 이상) ──
        if easyTypes.contains(i.type), let b = i.baseline, e >= b + 1,
           let slow = secondHalfSlowdown(splits: i.splits) {
            if slow >= splitThreshold {
                out.append(RunInsight(
                    category: .intensity, tone: .caution, badge: L.s("페이스 배분", "Pacing"),
                    message: L.s("후반이 처지고 체감도 높았어요. 초반 페이스가 목적보다 빨랐을 수 있어요.",
                                 "You faded late and effort ran high — the early pace may have been too quick for the goal."),
                    highlights: [String(format: "%+.0f%%", slow * 100)]))
            } else if slow <= -splitThreshold {
                out.append(RunInsight(
                    category: .intensity, tone: .caution, badge: L.s("페이스 배분", "Pacing"),
                    message: L.s("이지런 후반에 속도를 올리면 회복이라는 목적이 흐려져요.",
                                 "Speeding up late in an easy run blurs its purpose: recovery."),
                    highlights: [String(format: "%+.0f%%", slow * 100)]))
            }
        }

        return EffortRuleOutput(insights: out, replacesEnvironment: replacesEnv)
    }

    private static func matched(_ e: Int) -> RunInsight {
        let L = AppLanguage.shared
        return RunInsight(category: .intensity, tone: .good, badge: L.s("의도에 맞는 강도", "On-Target Effort"),
                          message: L.s("훈련 의도와 체감 강도가 맞았어요.", "Effort matched the intent of the session."),
                          highlights: ["\(e)"])
    }

    private static func envHeader(temp: Double?, hum: Double?) -> String {
        let L = AppLanguage.shared
        var parts: [String] = []
        if let t = temp { parts.append("\(Int(t.rounded()))°C") }
        if let h = hum { parts.append(L.s("습도 \(Int(h.rounded()))%", "\(Int(h.rounded()))% humidity")) }
        return parts.joined(separator: " · ")
    }

    /// (후반 sec/km ÷ 전반 sec/km) − 1. 양수 = 후반 느림. 1km 미만 부분 스플릿 제외, 4개 미만 nil.
    /// 홀수면 가운데 스플릿 제외.
    static func secondHalfSlowdown(splits: [SplitData]) -> Double? {
        let full = splits.filter { $0.distanceM >= 1000 }.sorted { $0.id < $1.id }
        guard full.count >= 4 else { return nil }
        let half = full.count / 2
        let first = Array(full.prefix(half))
        let second = Array(full.suffix(half))
        func pace(_ s: [SplitData]) -> Double {
            let dKm = s.map(\.distanceM).reduce(0, +) / 1000
            let t = s.map(\.duration).reduce(0, +)
            return dKm > 0 ? t / dKm : 0
        }
        let p1 = pace(first), p2 = pace(second)
        guard p1 > 0 else { return nil }
        return p2 / p1 - 1
    }
}
