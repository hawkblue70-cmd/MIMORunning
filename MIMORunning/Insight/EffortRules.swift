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
        let label = i.type.koreanLabel
        var out: [RunInsight] = []
        var replacesEnv = false

        // ── C: 스플릿 형태 (이지 유형 + 기준선+1 이상) ── A보다 먼저 계산: 모순 쌍 방지
        let cInsight: RunInsight? = { () -> RunInsight? in
            guard easyTypes.contains(i.type), let b = i.baseline, e >= b + 1,
                  let slow = secondHalfSlowdown(splits: i.splits) else { return nil }
            if slow >= splitThreshold {
                return RunInsight(
                    category: .intensity, tone: .caution, badge: L.s("페이스 배분", "Pacing"),
                    message: L.s("후반이 처지고 체감도 높았어요. 초반 페이스가 목적보다 빨랐을 수 있어요.",
                                 "You faded late and effort ran high — the early pace may have been too quick for the goal."),
                    highlights: [])
            } else if slow <= -splitThreshold {
                return RunInsight(
                    category: .intensity, tone: .caution, badge: L.s("페이스 배분", "Pacing"),
                    message: L.s("\(label) 후반에 속도를 올리면 회복이라는 목적이 흐려져요.",
                                 "Speeding up late in a \(label.lowercased()) blurs its purpose: recovery."),
                    highlights: [])
            }
            return nil
        }()

        // ── A 계열: 하나만 ──
        if easyTypes.contains(i.type) {
            let tooHard: Bool = { () -> Bool in
                if let b = i.baseline { return e >= b + 2 || (e >= 8 && e > b) }
                // 기준선 없음: 절대 7 이상 — 단, Apple 추정값만 있을 때는 침묵(추정치가 이지런을 부풀리는 경향)
                return e >= 7 && i.effort.source != .appleEstimated
            }()
            if tooHard {
                out.append(RunInsight(
                    category: .intensity, tone: .caution, badge: L.s("체감 강도", "Perceived Effort"),
                    message: L.s("\(label)인데 체감 강도가 \(e)이었어요. 이름과 달리 몸이 힘들었다면 회복 목적은 이루지 못한 거예요.",
                                 "\(label), but effort was \(e)/10. If the body says hard, it wasn't a recovery run."),
                    highlights: ["\(e)"]))
            } else if let b = i.baseline, e <= b - 2 {
                // 이지 유형에서 평소보다 확실히 편했던 날 — "의도와 맞았어요"보다 정확한 표현
                out.append(RunInsight(
                    category: .intensity, tone: .good, badge: L.s("편한 날", "Easy Day"),
                    message: L.s("체감 \(e) · 평소 \(b) — 평소보다 편하게 뛴 \(label)이에요.",
                                 "Effort \(e) · usual \(b) — an easier-than-usual \(label.lowercased())."),
                    highlights: ["\(e)"]))
            } else if let b = i.baseline, cInsight == nil {
                out.append(matched(e, b))
            }
        } else if hardTypes.contains(i.type), let b = i.baseline {
            if e <= b - 2 {
                out.append(RunInsight(
                    category: .intensity, tone: .neutral, badge: L.s("강도 메모", "Effort"),
                    message: L.s("체감 \(e), 평소 같은 훈련(\(b))보다 낮았어요. 여유 있게 소화한 날.",
                                 "Effort \(e), below your usual \(b) for this workout — a comfortable day."),
                    highlights: ["\(e)"]))
            } else {
                out.append(matched(e, b))
            }
        } else if let b = i.baseline {
            out.append(matched(e, b))
        }

        // ── B: 더위·습도 (기준선 필요) ──
        if let b = i.baseline {
            let hot   = (i.temperatureC ?? -100) >= hotC
            let humid = (i.humidityPercent ?? -1) >= humidPct
            if hot || humid {
                let header = envHeader(temp: i.temperatureC, hum: i.humidityPercent)
                let noun = hot && humid ? L.s("덥고 습한 날", "a hot, humid day")
                         : hot ? L.s("더운 날", "a hot day")
                         : L.s("습한 날", "a humid day")
                if e >= b + 1 {
                    out.append(RunInsight(
                        category: .environment, tone: .neutral, badge: L.s("환경", "Conditions"),
                        message: L.s("\(header). 같은 페이스라도 \(noun)은 체감이 1~2 높아지는 게 자연스러워요. 페이스보다 강도에 맞춰 뛰는 날.",
                                     "\(header). On \(noun) the same pace feels 1–2 points harder — run to effort, not pace."),
                        highlights: [header]))
                    replacesEnv = true
                } else if e <= b {
                    out.append(RunInsight(
                        category: .environment, tone: .good, badge: L.s("환경", "Conditions"),
                        message: L.s("\(header). \(noun)인데 체감이 평소 수준이었어요.",
                                     "\(header). \(noun.prefix(1).uppercased() + noun.dropFirst()), yet effort stayed at your usual level."),
                        highlights: [header]))
                    replacesEnv = true
                }
            }
        }

        if let c = cInsight { out.append(c) }

        return EffortRuleOutput(insights: out, replacesEnvironment: replacesEnv)
    }

    private static func matched(_ e: Int, _ b: Int) -> RunInsight {
        let L = AppLanguage.shared
        return RunInsight(category: .intensity, tone: .good, badge: L.s("의도에 맞는 강도", "On-Target Effort"),
                          message: L.s("체감 \(e) · 평소 \(b) — 훈련 의도와 맞았어요.",
                                       "Effort \(e) · usual \(b) — matched the session's intent."),
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
        guard p1 > 0, p2 > 0 else { return nil }
        let r = p2 / p1 - 1
        return r.isFinite ? r : nil
    }
}
