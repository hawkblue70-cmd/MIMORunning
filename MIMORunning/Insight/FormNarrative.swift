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

// MARK: - 장거리 문맥 문장

extension FormNarrative {

    /// 장거리 문맥(롱런·LSD·평소보다 훨씬 긴 러닝)의 마무리 문장 입력.
    /// 판정(`cad`/`gct`/`sl`)은 러닝 전체 평균의 평소 범위 대비 상태, 전반/후반 평균은 실제 변화 서술용.
    struct LongDistanceInput {
        let distKm: Double
        let typeName: String
        let typicalDistanceKm: Double?
        /// 카드가 "평소보다 긴 거리" 인사이트를 이미 보여주고 있으면 접두 문장을 생략
        let hasDistanceInsight: Bool
        let cad: Status
        let gct: Status
        let sl: Status
        let firstHalfCadence: Int?
        let secondHalfCadence: Int?
        let firstHalfStride: Double?
        let secondHalfStride: Double?
        /// 스플릿이 없을 때의 전체 평균 폴백
        let cadStr: String
        let slStr: String?
        let paceStr: String
        /// 카드가 전반/후반 3단계 문장(FormPhase.sentence)을 함께 보여주면, 전체 평균 문장을 "평균으로는" 범위로 좁힌다.
        var hasPhaseSentence: Bool = false
    }

    /// 전반→후반 변화 방향 임계값. 이 미만은 "유지"로 본다.
    static let longDistanceCadenceDeltaSPM = 2
    static let longDistanceStrideDeltaM = 0.02

    /// 장거리 문맥 문장 — 판단 유보, 사실 서술만.
    ///
    /// - 모두 평소 범위(또는 미상) → "폼이 평소 범위 그대로였어요."
    /// - 범위 아래가 없고 지면접촉만 위 → "지면접촉이 평소보다 조금 길었어요."
    /// - 케이던스·보폭 중 하나라도 범위 아래 → 전반/후반 평균으로 방향을 서술
    ///   (케이던스 Δ≥2spm 올라감/내려감, 보폭 Δ≥0.02m 늘어남/줄어듦, 그 외 유지).
    ///   지면접촉의 `.below`(짧아짐)는 하락이 아니므로 이 분기를 열지 않는다.
    static func longDistanceSentence(_ i: LongDistanceInput) -> String {
        let L = AppLanguage.shared
        let distKmStr = String(format: "%.0f", i.distKm)

        let allInRange = [i.cad, i.gct, i.sl].allSatisfy { $0 == .inRange || $0 == .unknown }
        let anyBelow = i.cad == .below || i.sl == .below
        if allInRange || !anyBelow {
            if !allInRange, i.gct == .above {
                return L.s("\(distKmStr)km를 뛰면서 지면접촉이 평소보다 조금 길었어요.",
                           "Ground contact ran a bit longer than usual in this \(distKmStr) km run.")
            }
            if i.hasPhaseSentence {
                return L.s("\(distKmStr)km를 뛰면서 평균으로는 폼이 평소 범위 안이었어요.",
                           "On average your form stayed within the usual range across \(distKmStr) km.")
            }
            return L.s("\(distKmStr)km를 뛰면서 폼이 평소 범위 그대로였어요.",
                       "Your form stayed within the usual range throughout \(distKmStr) km.")
        }

        // 전반/후반 변화 구절 — (한국어 본문+어간, 영어 구절)
        struct Clause { let koBody: String; let koStem: String; let en: String; let held: Bool }
        var clauses: [Clause] = []
        if let fc = i.firstHalfCadence, let sc = i.secondHalfCadence {
            let d = sc - fc
            if d >= longDistanceCadenceDeltaSPM {
                clauses.append(Clause(koBody: "케이던스는 \(fc)→\(sc)spm으로", koStem: "올라갔",
                                      en: "cadence rose from \(fc) to \(sc) spm", held: false))
            } else if d <= -longDistanceCadenceDeltaSPM {
                clauses.append(Clause(koBody: "케이던스는 \(fc)→\(sc)spm으로", koStem: "내려갔",
                                      en: "cadence dropped from \(fc) to \(sc) spm", held: false))
            } else {
                let v = Int((Double(fc + sc) / 2).rounded())
                clauses.append(Clause(koBody: "케이던스 \(v)spm", koStem: "유지했",
                                      en: "cadence held at \(v) spm", held: true))
            }
        }
        if let fs = i.firstHalfStride, let ss = i.secondHalfStride {
            let d = ss - fs
            let fsS = String(format: "%.2f", fs), ssS = String(format: "%.2f", ss)
            if d >= longDistanceStrideDeltaM {
                clauses.append(Clause(koBody: "보폭은 \(fsS)→\(ssS)m로", koStem: "늘었",
                                      en: "stride lengthened from \(fsS) to \(ssS) m", held: false))
            } else if d <= -longDistanceStrideDeltaM {
                clauses.append(Clause(koBody: "보폭은 \(fsS)→\(ssS)m로", koStem: "줄었",
                                      en: "stride shortened from \(fsS) to \(ssS) m", held: false))
            } else {
                let v = String(format: "%.2f", (fs + ss) / 2)
                clauses.append(Clause(koBody: "보폭 \(v)m", koStem: "유지했",
                                      en: "stride held at \(v) m", held: true))
            }
        }

        guard !clauses.isEmpty else {
            // 스플릿 데이터 없음 — 전체 평균으로 서술
            return i.slStr.map {
                L.s("케이던스 \(i.cadStr)spm, 보폭 \($0)m로 \(i.paceStr) 페이스를 달렸어요.",
                    "Cadence \(i.cadStr) spm and stride \($0) m for the \(i.paceStr) pace.")
            } ?? L.s("케이던스 \(i.cadStr)spm으로 \(i.paceStr) 페이스를 달렸어요.",
                     "Cadence \(i.cadStr) spm for the \(i.paceStr) pace.")
        }

        // 한국어 본문 조립
        let ko: String
        let allHeld = clauses.allSatisfy(\.held)
        if allHeld {
            // "케이던스 195spm, 보폭 0.91m를 끝까지 유지했어요." / "케이던스 195spm을 끝까지 유지했어요."
            let bodies = clauses.map(\.koBody).joined(separator: ", ")
            let particle = clauses.last?.koBody.hasSuffix("spm") == true ? "을" : "를"
            ko = "\(bodies)\(particle) 끝까지 유지했어요."
        } else {
            var parts: [String] = []
            for (idx, c) in clauses.enumerated() {
                let isLast = idx == clauses.count - 1
                // 유지 구절이 다른 구절과 함께 오면 "케이던스는 195spm으로 유지했고" 형태
                let body = c.held ? c.koBody.replacingOccurrences(of: "케이던스 ", with: "케이던스는 ")
                                            .replacingOccurrences(of: "보폭 ", with: "보폭은 ")
                                   + (c.koBody.hasSuffix("spm") ? "으로" : "로")
                                 : c.koBody
                parts.append("\(body) \(c.koStem)\(isLast ? "어요." : "고,")")
            }
            ko = parts.joined(separator: " ")
        }
        let en: String = {
            let joined = clauses.map(\.en).joined(separator: " and ")
            return allHeld ? "\(joined) to the end." : "\(joined)."
        }()

        if let typical = i.typicalDistanceKm,
           (i.distKm > typical * 1.50 || i.distKm >= 12.0),
           !i.hasDistanceInsight {
            let delta = String(format: "%.1f", i.distKm - typical)
            return L.s("평소보다 \(delta)km 긴 \(i.typeName)이에요. \(ko)",
                       "This \(i.typeName) is \(delta) km longer than usual — \(en)")
        }
        return L.s("\(distKmStr)km를 뛰면서 \(ko)",
                   "Over \(distKmStr) km, \(en)")
    }
}

// MARK: - 지표 상태 판정 (폼 카드·인사이트 탭 리듬 카드 공용)

extension FormNarrative {

    /// 폼 지표 종류. 폼 카드의 `MetricDir`·상태 판정·반올림이 모두 이 타입을 쓴다.
    enum Metric { case cadence, stride, groundContact, verticalOsc }

    /// 표시 정밀도로 반올림 — 판정도 표시값 기준으로 해야 두 카드의 경계값이 일치한다
    /// (예: 케이던스 170 vs 하한 170.4 → 표시상 170–… 이므로 범위 안).
    static func roundedDisplay(_ v: Double, metric: Metric) -> Double {
        switch metric {
        case .cadence, .groundContact: return v.rounded()
        case .stride:                  return (v * 100).rounded() / 100
        case .verticalOsc:             return (v * 10).rounded() / 10
        }
    }

    /// 평소 범위(`FormStat.lower…upper`) 대비 상태. 값·경계 모두 표시 정밀도로 반올림해 비교한다.
    static func status(rawValue: Double?, stat: FormStat?, metric: Metric) -> Status {
        guard let rawValue, let stat else { return .unknown }
        let rv = roundedDisplay(rawValue, metric: metric)
        let lo = roundedDisplay(stat.lower, metric: metric)
        let hi = roundedDisplay(stat.upper, metric: metric)
        if rv >= lo && rv <= hi { return .inRange }
        return rv > hi ? .above : .below
    }

    /// GCT 밴드 시점 보정량(ms). GCT는 1년 새 9ms 이상 짧아지기도 해 현재 밴드로 과거 러닝을 판정하면 틀린다.
    /// drift = (열람 시점 잔차 3개월 평균) − (baseline 계산 시점 잔차 3개월 평균), ±15ms로 제한.
    /// 안전장치: shift 없음(표본 부족) · R² < 0.2 · |drift| < 2ms → nil(보정 없음).
    static func gctDrift(baselineResidualMean: Double?, gctShift: MRFormShift?) -> Double? {
        guard let baselineResidualMean, let gctShift else { return nil }
        if let r2 = gctShift.r2, r2 < 0.2 { return nil }
        let raw = gctShift.recentMean - baselineResidualMean
        guard abs(raw) >= 2 else { return nil }
        return max(-15, min(15, raw))
    }

    /// `gctDrift`를 적용한 GCT `FormStat`. 보정 조건 미충족이면 원본 그대로.
    static func driftAdjustedGCT(_ stat: FormStat?, baselineResidualMean: Double?, gctShift: MRFormShift?) -> FormStat? {
        guard let stat, let drift = gctDrift(baselineResidualMean: baselineResidualMean, gctShift: gctShift) else { return stat }
        return FormStat(median: stat.median + drift, sd: stat.sd, count: stat.count,
                        p10: stat.p10.map { $0 + drift }, p90: stat.p90.map { $0 + drift })
    }
}

// MARK: - 러닝 유형별 캡션 (인사이트 탭 리듬 카드 · 폼 카드 공용)

/// 빌드업·템포·대회는 후반 가속과 고강도가 **계획**이다. 같은 관측을 경고나 변명처럼 읽히지 않게
/// 유형만 반영한 사실 문장으로 바꾼다. 이지·일반·장거리 유형의 문장은 그대로 둔다.
extension FormNarrative {

    /// 후반 가속이 계획인 유형 — 빌드업·템포·대회.
    static func isPlannedFastFinish(_ type: WorkoutType) -> Bool {
        type == .buildUp || type == .tempo || type == .race
    }

    /// 고강도 구간이 계획인 유형 — 후반 가속 유형 + 인터벌 + 거리주.
    /// 거리주는 레이스페이스 장거리(분류기가 "빠른 롱런"으로 정의)라 Zone 3~4가 계획이다.
    /// 후반 가속(`isPlannedFastFinish`)에는 넣지 않는다 — 거리주는 균등 페이스가 목표.
    static func isPlannedHighIntensity(_ type: WorkoutType) -> Bool {
        isPlannedFastFinish(type) || type == .interval || type == .distanceRun
    }

    /// 심박 차트 캡션 — 전반 대비 후반 평균 심박 +8bpm 이상일 때.
    /// 빌드업만 "빌드업답게"를 붙이고, 템포·대회·인터벌은 사실 그대로, 이지·일반은 변경 없음.
    static func hrSecondHalfRiseCaption(type: WorkoutType) -> String {
        let L = AppLanguage.shared
        if type == .buildUp {
            return L.s("빌드업답게 후반에 심박이 올라갔어요", "HR climbed in the 2nd half — as a build-up should")
        }
        return L.s("후반에 심박이 올랐어요", "HR climbed in the 2nd half")
    }

    /// 심박존 도넛 캡션 — 4존 이상이 최다 구간일 때.
    static func highIntensityZoneCaption(type: WorkoutType) -> String {
        let L = AppLanguage.shared
        if isPlannedHighIntensity(type) {
            return L.s("계획대로 고강도 구간이 많았어요", "High-intensity effort, as planned")
        }
        return L.s("고강도 구간이 많았어요", "High-intensity effort")
    }

    /// 한 줄 요약 — 고강도 비율 40% 이상일 때.
    static func highIntensityOneLiner(type: WorkoutType) -> String {
        let L = AppLanguage.shared
        if isPlannedHighIntensity(type) {
            return L.s("계획대로 고강도 구간이 많았어요. 다음엔 여유롭게 가도 좋아요",
                       "High-intensity run, as planned. An easy run next time is great.")
        }
        return L.s("고강도 구간이 많았어요. 다음엔 여유롭게 가도 좋아요",
                   "High-intensity run. An easy run next time is great.")
    }

    /// 후반까지 폼이 버텼을 때의 알약 문구(전·후반 GCT +10ms 미만 또는 케이던스 −2spm 미만).
    static func formHeldCaption(type: WorkoutType) -> String {
        let L = AppLanguage.shared
        if isPlannedFastFinish(type) {
            return L.s("후반 가속에도 폼이 버텼어요", "Form held through the fast finish")
        }
        return L.s("장거리인데 후반까지 폼이 버텼어요", "Form held through the long run")
    }

    /// 폼 추이 차트(km별) 하단 주석 — 포인트의 30% 이상이 평소 범위 아래일 때.
    /// 후반 가속 유형은 페이스가 원인임을 말하고(GCT는 "아래에 머물러요" = 짧아짐), 그 외는 장거리 문맥 그대로.
    static func belowRangeNote(type: WorkoutType, metric: Metric) -> String {
        let L = AppLanguage.shared
        if isPlannedFastFinish(type) {
            if metric == .groundContact {
                return L.s("후반 페이스가 빨라 범위 아래에 머물러요", "Faster late pace — contact stays below the range")
            }
            return L.s("후반 페이스가 빨라 범위를 벗어났어요", "Faster late pace — outside the range")
        }
        return L.s("장거리라 평소 범위 아래에 머물러요", "Long run — staying below normal range is natural")
    }
}
