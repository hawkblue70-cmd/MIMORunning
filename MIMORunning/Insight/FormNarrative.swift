import Foundation

/// 폼 카드 마무리 문장 — 러닝 유형(프레임)에 따라 톤만 달라진다.
///
/// 판정(평소 범위 대비 inRange/above/below)은 호출 측(`RunFormCardView`)이 페이스 대역 매칭으로 결정하고,
/// 여기서는 그 결과를 문장으로만 옮긴다. 장거리 문맥(롱런·LSD)과 인터벌은 카드가 따로 처리하므로
/// 이 함수에 도달하지 않는다(도달해도 `.general`로 다룬다).
///
/// 우선순위: 지면접촉 이탈 → 케이던스 이탈 → 보폭 → 모두 평소 범위.
enum FormNarrative {

    /// 유형별 기대 방향.
    /// - easy: 케이던스·보폭이 조금 작아도 자연스럽고, 짧은 지면접촉은 좋은 신호
    /// - fast: 케이던스·보폭이 커지고 지면접촉이 짧아지는 것이 기대 방향
    /// - general: 방향 기대 없음 — 사실 서술
    enum Frame { case easy, fast, general }

    enum Status { case inRange, above, below, unknown }

    struct Input {
        let cad: Status
        let gct: Status
        let sl: Status
        let cadStr: String
        let gctStr: String?
        let slStr: String?
        let paceStr: String
    }

    static func frame(for type: WorkoutType) -> Frame {
        switch type {
        case .easy:                                 return .easy
        case .tempo, .buildUp, .race, .distanceRun: return .fast
        case .general, .longRun, .lsd, .interval:   return .general
        }
    }

    private static func deviated(_ s: Status) -> Bool { s == .above || s == .below }

    static func sentence(_ i: Input, frame: Frame) -> String {
        let L = AppLanguage.shared
        let cadStr = i.cadStr
        let paceStr = i.paceStr

        // 보폭 이탈 구절 — 사실 서술(중립). 케이던스·GCT 둘 다 이탈이면 3개 → 보폭 생략
        let cadDev = deviated(i.cad), gctDev = deviated(i.gct), slDev = deviated(i.sl)
        let strideClause: String?
        if slDev, !(cadDev && gctDev), let sl = i.slStr {
            strideClause = i.sl == .above
                ? L.s("보폭이 \(sl)m로 평소보다 컸어요.", "Stride was \(sl) m — longer than usual.")
                : L.s("보폭이 \(sl)m로 평소보다 작았어요.", "Stride was \(sl) m — shorter than usual.")
        } else {
            strideClause = nil
        }
        func withStride(_ base: String) -> String {
            strideClause.map { base + " " + $0 } ?? base
        }

        // MARK: 1. 지면접촉
        if let g = i.gctStr {
            if i.gct == .below {
                if i.cad == .inRange {
                    switch frame {
                    case .general:
                        return withStride(L.s(
                            "평소 리듬대로 \(cadStr)spm을 유지했고, 지면접촉이 \(g)ms로 짧았어요.",
                            "Cadence held at your usual \(cadStr) spm, with ground contact short at \(g) ms."))
                    case .easy:
                        return withStride(L.s(
                            "평소 리듬대로 \(cadStr)spm을 유지했고, 지면접촉이 \(g)ms로 짧았어요. 가볍게 뛴 날이에요.",
                            "Cadence held at your usual \(cadStr) spm, with ground contact short at \(g) ms. A light, easy day."))
                    case .fast:
                        return withStride(L.s(
                            "평소 리듬 \(cadStr)spm에 지면접촉이 \(g)ms로 짧았어요. 빠른 페이스에 맞는 폼이에요.",
                            "Your usual \(cadStr) spm with ground contact short at \(g) ms — form that suits a fast pace."))
                    }
                }
                switch frame {
                case .general:
                    return L.s("발걸음이 평소보다 빠르게 돌았어요. 지면접촉이 \(g)ms로 짧았어요.",
                               "Cadence was faster than usual. Ground contact was short at \(g) ms.")
                case .easy:
                    if i.cad == .above {
                        return L.s("발걸음이 빠르게 돌고 지면접촉이 \(g)ms로 짧았어요. 편한 날엔 리듬을 조금 늦춰도 괜찮아요.",
                                   "Quick cadence with ground contact short at \(g) ms. On an easy day it's fine to relax the rhythm a little.")
                    }
                    if i.cad == .below {
                        return L.s("발걸음은 평소보다 느렸지만 지면접촉이 \(g)ms로 짧았어요. 편하게 뛴 날이에요.",
                                   "Cadence was below your usual, but ground contact stayed short at \(g) ms. A relaxed day.")
                    }
                    return L.s("지면접촉이 \(g)ms로 짧았어요. 가볍게 뛴 날이에요.",
                               "Ground contact was short at \(g) ms. A light, easy day.")
                case .fast:
                    if i.cad == .above {
                        return L.s("발걸음이 빠르게 돌고 지면접촉도 \(g)ms로 짧았어요. 빠른 페이스에 맞는 폼이에요.",
                                   "Quick cadence and ground contact short at \(g) ms — form that suits a fast pace.")
                    }
                    if i.cad == .below {
                        return L.s("발걸음은 평소보다 느렸지만 지면접촉이 \(g)ms로 짧았어요.",
                                   "Cadence was below your usual, but ground contact stayed short at \(g) ms.")
                    }
                    return L.s("지면접촉이 \(g)ms로 짧았어요. 빠른 페이스에 맞는 폼이에요.",
                               "Ground contact was short at \(g) ms — form that suits a fast pace.")
                }
            }
            if i.gct == .above {
                switch frame {
                case .general:
                    return withStride(L.s("지면접촉이 \(g)ms로 평소보다 길었어요.",
                                          "Ground contact was \(g) ms — longer than usual."))
                case .easy:
                    return withStride(L.s("지면접촉이 \(g)ms로 평소보다 길었어요. 회복이 덜 된 날일 수 있어요.",
                                          "Ground contact was \(g) ms — longer than usual. You may not have been fully recovered."))
                case .fast:
                    return withStride(L.s("속도를 냈는데 지면접촉이 \(g)ms로 길었어요. 다리가 무거운 날이었을 수 있어요.",
                                          "You pushed the pace, but ground contact ran long at \(g) ms. Your legs may have felt heavy."))
                }
            }
        }

        // MARK: 2. 케이던스
        if i.cad == .below {
            switch frame {
            case .general:
                if i.sl == .below {
                    return L.s("케이던스와 보폭이 평소보다 조금 작았어요.",
                               "Cadence and stride were both a little below your usual.")
                }
                let sfx = i.slStr.map { " \($0)m" } ?? ""
                return L.s("발걸음이 평소보다 느렸어요. 보폭\(sfx)으로 페이스를 만들었어요.",
                           "Cadence was below your usual. Stride\(sfx) carried the pace.")
            case .easy:
                if i.sl == .below {
                    return L.s("발걸음도 보폭도 평소보다 조금 작았어요. 편하게 뛴 날이에요.",
                               "Both cadence and stride were a little below your usual. A relaxed day.")
                }
                return L.s("발걸음이 평소보다 느렸어요. 편한 날엔 자연스러운 변화예요.",
                           "Cadence was below your usual — a natural change on an easy day.")
            case .fast:
                if i.sl == .above, let sl = i.slStr {
                    return L.s("보폭 \(sl)m로 속도를 냈어요. 빠른 날엔 발걸음을 조금 더 빨리 돌리는 쪽이 부담이 덜해요.",
                               "You made the pace with a \(sl) m stride. On fast days, turning your feet over a little quicker is easier on the body.")
                }
                if i.sl == .below {
                    return L.s("발걸음과 보폭이 모두 평소보다 작아 페이스가 덜 나온 날이에요.",
                               "Both cadence and stride were below your usual, so the pace didn't quite come.")
                }
                return L.s("발걸음이 평소보다 느렸어요. 빠른 날엔 발걸음을 조금 더 빨리 돌리는 쪽이 부담이 덜해요.",
                           "Cadence was below your usual. On fast days, turning your feet over a little quicker is easier on the body.")
            }
        }
        if i.cad == .above {
            switch frame {
            case .general:
                if i.sl == .inRange {
                    return L.s("발걸음이 평소보다 빨랐어요. 보폭은 평소 범위였고요.",
                               "Cadence was above your usual. Stride length was within your typical range.")
                }
                return withStride(L.s("발걸음이 평소보다 빨랐어요.", "Cadence was above your usual."))
            case .easy:
                if i.sl == .below {
                    return L.s("잰걸음이었어요. 편한 날엔 리듬을 조금 늦춰도 괜찮아요.",
                               "Short, quick steps. On an easy day it's fine to relax the rhythm a little.")
                }
                return withStride(L.s("발걸음이 평소보다 빨랐어요.", "Cadence was above your usual."))
            case .fast:
                if i.sl == .inRange {
                    return L.s("발걸음이 평소보다 빨랐어요. 보폭은 평소 범위였고요.",
                               "Cadence was above your usual. Stride length was within your typical range.")
                }
                return withStride(L.s("발걸음이 평소보다 빨랐어요.", "Cadence was above your usual."))
            }
        }

        // MARK: 3. 케이던스 평소 범위 — 보폭만 이탈했으면 사실만 (easy/fast)
        if frame != .general, let sc = strideClause {
            return sc
        }

        // MARK: 4. 모두 평소 범위
        switch frame {
        case .general:
            return i.slStr.map {
                L.s("케이던스 \(cadStr)spm, 보폭 \($0)m로 평소와 비슷한 \(paceStr) 페이스가 나왔어요.",
                    "Cadence \(cadStr) spm and stride \($0) m produced the usual \(paceStr) pace.")
            } ?? L.s("케이던스 \(cadStr)spm으로 평소와 비슷하게 \(paceStr) 페이스를 달렸어요.",
                     "A cadence of \(cadStr) spm produced the usual \(paceStr) pace.")
        case .easy:
            return i.slStr.map {
                L.s("케이던스 \(cadStr)spm, 보폭 \($0)m로 평소와 같은 편한 폼이었어요.",
                    "Cadence \(cadStr) spm and stride \($0) m — your usual relaxed form.")
            } ?? L.s("케이던스 \(cadStr)spm으로 평소와 같은 편한 폼이었어요.",
                     "Cadence \(cadStr) spm — your usual relaxed form.")
        case .fast:
            return i.slStr.map {
                L.s("케이던스 \(cadStr)spm, 보폭 \($0)m로 평소와 같은 폼으로 \(paceStr) 페이스를 냈어요.",
                    "Cadence \(cadStr) spm and stride \($0) m — your usual form carried a \(paceStr) pace.")
            } ?? L.s("케이던스 \(cadStr)spm으로 평소와 같은 폼으로 \(paceStr) 페이스를 냈어요.",
                     "Cadence \(cadStr) spm — your usual form carried a \(paceStr) pace.")
        }
    }
}
