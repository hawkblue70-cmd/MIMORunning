import Foundation

/// 총평 한 줄 — 색점(톤) + 축 이름 + 짧은 상태어(관찰 사실, 등급어 아님).
/// `evidence`/`next`는 탭하면 펼쳐지는 근거·다음 행동 — 없으면 nil(펼칠 것 없음).
struct RunSummaryLine: Equatable {
    enum Tone: Equatable { case good, neutral }
    let axis: String
    let state: String
    let tone: Tone
    var evidence: String? = nil
    var next: String? = nil
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
    /// 어제 기준(asOf −1일) 4주 평균 대비 라벨 — 저장 없는 히스테리시스. 어제 높음이었으면 오늘 유지로 내려와도
    /// "충분히 회복" 대신 "부하가 내려오는 중"을 말한다(창 경계 하루 차이로 결론이 뒤집히는 것 방지).
    var acuteChronicYesterday: EffortLoad.RatioLabel? = nil
    var streakDays: Int = 0
    var vo2: Double? = nil
    var vo2AgeDecade: String = ""
    var vo2GenderLabel: String = ""
    /// 이 러닝의 기온 보정량(bpm). 총평 줄 상태어에는 붙이지 않는다 — 더위는 존 캡션과 근거 줄이 말한다.
    var heatDeltaBpm: Double? = nil
    /// 롱런/LSD 같은 장거리 문맥인가 — 폼 다음 행동 문구가 "다음 롱런은"/"다음 러닝은"을 고를 때 쓴다.
    var isLongDistanceContext: Bool = false
    /// 오늘 강도를 냈는가(계획된 고강도 유형 · Zone 4+ 절반 이상 · 체감강도 7+) — 훈련부하 다음 행동에서
    /// "내일은 이지런이나 휴식" 제안에 쓴다. 급증/단조/4일+연속 경고가 있으면 그쪽이 우선.
    var todayIsHard: Bool = false

    // MARK: 근거·다음용 — 모두 옵셔널, 없으면 해당 근거·다음 절만 생략

    /// 최근 N회 중 이 거리의 순위(1 = 가장 김)
    var distanceRank: Int? = nil
    var distanceSampleCount: Int? = nil
    var avgHeartRate: Int? = nil
    var peakHeartRate: Int? = nil
    var temperatureC: Double? = nil
    var sevenDayAU: Double? = nil
    var previousSevenAU: Double? = nil
    var loadSentence: EffortLoad.SentenceKind? = nil
    /// 이 러닝의 체감 강도가 아직 없음 — 7일 합에 오늘이 0으로 들어가 있으므로 높다/가볍다를 말하지 않는다
    var todayEffortMissing: Bool = false
    /// 마지막 고강도(계획된 고강도 유형 또는 체감 강도 7 이상) 러닝으로부터 지난 일수
    var daysSinceHardRun: Int? = nil
    /// 이번 주 플랜 단계 원문("회복"/"테이퍼"/…) — 대회 플랜이 있을 때만
    var planPhase: String? = nil
    /// 이지 페이스 조회값 — 있을 때만 다음 이지런 페이스를 숫자로 제안
    var easyPace: MRHRPaceLookup? = nil
    var vo2EightWeeksAgo: Double? = nil
    /// 수면 HRV 7일 vs 4주 추세(러닝 날짜 기준). 없으면 HRV 문장·근거 모두 생략.
    var hrvTrend: MRHRVTrend? = nil
    /// 이 러닝 날의 밤(전날 15시~당일 12시) HRV 중앙값 — 아침 제안이 본 "어젯밤" 값. 근거에 같이 적어 아침·저녁 숫자를 맞춘다.
    var lastNightHRV: Double? = nil
    /// 이 러닝 직전 14일(이 러닝 제외) 고강도 러닝 수 / 러닝 수 — `hrvTrend`가 있을 때만 채운다.
    var hardRunsLast14: Int? = nil
    var runsLast14: Int = 0
    /// 2주 이지 블록 — 고강도 1회 이하이고 러닝 4회 이상
    var isEasyBlock: Bool {
        guard let hard = hardRunsLast14 else { return false }
        return hard <= RunSummary.easyBlockMaxHard && runsLast14 >= RunSummary.easyBlockMinRuns
    }
}

/// 총평 규칙. 축 순서 고정: 러닝폼 → 거리 적응 → 심박 → 훈련부하 → 유산소.
/// 상태어는 관찰 사실만. 톤은 초록(good)·노랑(neutral) 둘.
/// 각 줄의 `evidence`(왜 이 말이 나왔나)·`next`(그래서 뭘 하나)도 여기서 함께 채운다.
enum RunSummary {
    static let distanceRatioMin = 1.30
    /// 이지 의도 유형에서 Zone 3 이상 비율이 이 이상이면 "기준 높음"
    static let easyHighZoneFrac = 0.50
    /// 유지(.steady)일 때 "충분히 회복" 문장을 허용하는 최근 7일 증감 상한 — 이 이상 늘었으면 아직 회복 국면이 아니다.
    static let restedWeekOverWeekMax = 0.15
    /// 존 캡션 더위 보정 표기 임계값(bpm) — 존 캡션·근거 줄이 공유해서 쓴다. 총평 상태어에는 붙이지 않는다.
    static let heatNoteMinBpm = 5.0
    /// 심박 근거 줄에서 "(더위 +N)"을 붙이는 문턱(bpm) — 문장 단위 "기온 감안" 임계값과 같다.
    static let heatEvidenceMinBpm = MRHeatHRModel.explainThresholdBpm
    static let vo2Bounds: [Double] = [15, 26, 33, 41, 57]
    /// VO2max 8주 전 대비 근거 절을 붙이는 최소 변화폭 — 이보다 작으면 잡음으로 보고 생략
    static let vo2DeltaEvidenceMin = 0.05
    /// 2주 이지 블록 판정 — 14일 고강도 최대 1회 · 러닝 최소 4회
    static let easyBlockMaxHard = 1
    static let easyBlockMinRuns = 4
    // 거리주(레이스페이스 장거리)는 빠른 게 정의라 이지 의도로 판정하지 않는다
    static let easyIntentTypes: Set<WorkoutType> = [.easy, .longRun, .lsd]
    /// 오늘 거리가 계획의 일부인 유형 — 거리 적응 줄이 증량 규칙을 말하지 않는다.
    static let plannedLongRunTypes: Set<WorkoutType> = [.longRun, .lsd, .distanceRun, .race]
    /// 대회 훈련 계획상 강도를 낮추는 주 — 이 주에는 계획된 고강도 유형이라도 고강도가 계획 이탈이다.
    static let planEasyPhases: Set<String> = ["회복", "테이퍼"]

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
        var line = RunSummaryLine(axis: L.s("러닝폼", "Form"), state: FormPhase.shortState(f),
                                  tone: (f.isHeld || f.isSoftCadenceOnly) ? .good : .neutral)
        line.evidence = formEvidence(f)
        // 거리 적응 줄이 뜨는 러닝(평소 1.3배↑)도 롱런으로 부른다 — 두 줄의 호칭이 어긋나지 않게
        line.next = formNext(f, isLongDistanceContext: i.isLongDistanceContext || distanceLineApplies(i))
        return line
    }

    /// 모르는 지표는 말하지 않는다 — 값이 있어도 판정 신호가 `.unknown`(기준선 없음)이면 그 절은 생략.
    private static func formEvidence(_ f: FormPhase.Result) -> String? {
        let L = AppLanguage.shared
        let late = f.phases.late
        let sig = f.signals.late
        let lateKm = Int((f.totalKm - f.lateStartKm).rounded())
        var pieces: [String] = []

        if f.isFaded {
            let mid = f.phases.mid
            pieces.append(L.s("페이스 \(mrFormatPace(mid.paceSecPerKm))→\(mrFormatPace(late.paceSecPerKm))",
                              "pace \(mrFormatPace(mid.paceSecPerKm))→\(mrFormatPace(late.paceSecPerKm))"))
            pieces += FormPhase.fadedWorsenedPieces(f).map { L.s($0.ko, $0.en) }
            return pieces.joined(separator: " · ")
        }

        if let cad = late.cadence, sig.cadence != .unknown {
            let held: Bool
            switch sig.cadence {
            case .inRange, .above: held = true
            default: held = false   // .below
            }
            let n = Int(cad.rounded())
            pieces.append(L.s(held ? "케이던스 \(n) 유지" : "케이던스 \(n) 내려감",
                              held ? "cadence held at \(n)" : "cadence dropped to \(n)"))
        }
        if let sl = late.stride, sig.stride != .unknown {
            let s = String(format: "%.2f", sl)
            switch sig.stride {
            case .inRange:
                pieces.append(L.s("마지막 \(lateKm)km 보폭 \(s) 범위 안", "stride \(s) in range over the last \(lateKm) km"))
            case .above:
                pieces.append(L.s("마지막 \(lateKm)km 보폭 \(s) 범위 위", "stride \(s) above range over the last \(lateKm) km"))
            case .below:
                pieces.append(L.s("마지막 \(lateKm)km 보폭 \(s) 범위 아래", "stride \(s) below range over the last \(lateKm) km"))
            case .unknown:
                break
            }
        }
        if let gct = late.groundContact, sig.groundContact != .unknown {
            let inRange = sig.groundContact != .above
            let n = Int(gct.rounded())
            pieces.append(L.s(inRange ? "지면접촉 \(n) 범위 안" : "지면접촉 \(n) 범위 위",
                              inRange ? "ground contact \(n) in range" : "ground contact \(n) above range"))
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }

    /// `.heavier`는 피로 방향으로 처음 벗어난 지표(순서 고정: 케이던스 → 보폭 → 접지)만 짚어 다음 행동을 준다 —
    /// 안 무너진 지표까지 지켜보라고 하면 산만해진다.
    private static func formNext(_ f: FormPhase.Result, isLongDistanceContext: Bool) -> String? {
        let L = AppLanguage.shared
        let prefixKo = isLongDistanceContext ? "다음 롱런은 같은 거리에서 " : "다음 러닝은 같은 거리에서 "
        let prefixEn = isLongDistanceContext
            ? "Keep the distance the same on your next long run and "
            : "Keep the distance the same on your next run and "
        switch f.late {
        case .held:
            return nil
        case .heavier(let metrics):
            if f.isSoftCadenceOnly { return nil }
            switch metrics.first {
            case .cadence:
                return L.s(prefixKo + "후반 케이던스만 지켜보세요.", prefixEn + "watch your late-run cadence.")
            case .groundContact:
                return L.s(prefixKo + "후반 지면접촉만 지켜보세요.", prefixEn + "watch your late-run ground contact.")
            default: // .stride, .verticalOsc, 또는 비어 있을 때(이론상 없음)의 안전한 기본값
                return L.s(prefixKo + "후반 보폭만 지켜보세요.", prefixEn + "watch your late-run stride.")
            }
        case .cadenceDefended:
            return L.s(prefixKo + "후반 보폭만 지켜보세요.", prefixEn + "watch your late-run stride.")
        case .bouncier:
            return L.s(prefixKo + "후반 위아래 움직임만 지켜보세요.", prefixEn + "watch your late-run vertical motion.")
        case .faded:
            // 붕괴는 후반이 아니라 중반 페이싱이 원인 — 거리·유형과 무관하게 같은 조언
            return L.s("다음엔 중반을 \(FormPhase.fadeMidStartEaseSec)초/km 늦게 시작해 보세요.",
                      "Next time, start the middle stretch about \(FormPhase.fadeMidStartEaseSec) s/km slower.")
        }
    }

    /// 거리 적응 줄이 뜨는 조건 — 심박 줄의 "장거리라 그렇다" 다음 문구를 생략할지 판단할 때도 같이 쓴다
    /// (거리 줄이 이미 그 말을 했으면 심박 줄이 중복해서 말하지 않는다).
    private static func distanceLineApplies(_ i: RunSummaryInput) -> Bool {
        guard let t = i.typicalKm, t > 0 else { return false }
        return i.distKm >= t * distanceRatioMin
    }

    private static func distanceLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        guard distanceLineApplies(i), let t = i.typicalKm, t > 0 else { return nil }
        let L = AppLanguage.shared
        let ratio = String(format: "%.1f", i.distKm / t)
        let axis = L.s("거리 적응", "Distance")

        let typicalStr = String(format: "%.1f", t)
        var evidence = L.s("평소 \(typicalStr)km", "usual \(typicalStr) km")
        if let rank = i.distanceRank, let n = i.distanceSampleCount {
            if rank == 1 {
                evidence += L.s(" · 최근 \(n)회 중 가장 긴 거리", " · longest of the last \(n)")
            } else if rank <= 3 {
                evidence += L.s(" · 최근 \(n)회 중 \(rank)번째로 긴 거리", " · #\(rank) longest of the last \(n)")
            }
        }
        // 다음 롱런 거리를 정하는 주체가 둘이면 지시가 충돌한다.
        // 대회 플랜 > 계획된 롱런 유형 > (둘 다 없을 때만) 일반 증량 규칙 순으로 고른다.
        let next: String
        if let phase = i.planPhase {
            next = planEasyPhases.contains(phase)
                ? L.s("대회 훈련 계획상 \(phase) 주예요. 거리를 더 늘리지 말고 계획대로 가세요.",
                      "Your race plan has this as an easy week — hold the distance and stick to the plan.")
                : L.s("대회 훈련 계획상 \(phase) 주의 러닝이에요. 다음 롱런 거리는 계획을 따르세요.",
                      "This run is part of your race plan — follow the plan for your next long run.")
        } else if plannedLongRunTypes.contains(i.workoutType) {
            // 오늘 거리는 의도한 것이라 증량 경고가 아니라 회복이 다음 행동이다
            next = L.s("계획한 거리를 채운 러닝이에요. 다음 1~2일은 이지런이나 휴식으로 회복하세요.",
                      "You covered the distance you set out to — take the next day or two easy, or rest.")
        } else {
            next = L.s("이 거리는 2~3주 유지한 뒤 늘리세요. 롱런은 한 번에 평소의 1.3배 안에서.",
                      "Hold this distance for 2–3 weeks before increasing. Keep long runs within 1.3× your usual, one step at a time.")
        }

        var line: RunSummaryLine
        if let f = i.form {
            line = f.isHeld
                ? RunSummaryLine(axis: axis, state: L.s("평소 \(ratio)배, 범위 안", "\(ratio)× usual, form in range"), tone: .good)
                : RunSummaryLine(axis: axis, state: L.s("평소 \(ratio)배", "\(ratio)× usual"), tone: .neutral)
        } else {
            line = RunSummaryLine(axis: axis, state: L.s("평소 \(ratio)배", "\(ratio)× usual"), tone: .good)
        }
        line.evidence = evidence
        line.next = next
        return line
    }

    private static func heartRateLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        let visible = i.zoneFractions.filter { $0.value > 0.01 }
        let total = visible.values.reduce(0, +)
        guard total > 0 else { return nil }
        let L = AppLanguage.shared
        func frac(_ z: Int) -> Double { (visible[z] ?? 0) / total }
        let axis = L.s("심박", "Heart rate")

        // 동률이면 높은 존이 이긴다(결정적 타이브레이크) — 근거 줄의 "Zone N"과 상태어 판정이 같은 규칙을 쓴다
        guard let dom = visible.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key else { return nil }
        let domPct = Int((frac(dom) * 100).rounded())

        // "Zone N X%"·"· T°C"는 로케일과 무관 — L.s 없이 그대로 쓴다(no-op 래핑 금지)
        var evidence = "Zone \(dom) \(domPct)%"
        if let avg = i.avgHeartRate {
            evidence += L.s(" · 평균 \(avg)", " · avg \(avg)")
            // 러닝 전체 최고 심박 — "후반"이 아니라 실측 최고치 그 자체를 말한다
            if let peak = i.peakHeartRate, peak > avg {
                evidence += L.s(" · 최고 \(peak)", " · peak \(peak)")
            }
        }
        if let t = i.temperatureC {
            let tInt = Int(t.rounded())
            var piece = " · \(tInt)°C"
            if let heat = i.heatDeltaBpm, heat >= heatEvidenceMinBpm {
                let n = Int(heat.rounded())
                piece += L.s("(더위 +\(n))", " (heat +\(n))")
            }
            evidence += piece
        }

        var isEasyHighBranch = false
        /// 대회 훈련 계획상 강도를 낮추는 주인데 고강도로 뛴 경우 — 그 단계 이름
        var planDeviationPhase: String? = nil
        var line: RunSummaryLine

        if frac(2) >= 0.60 {
            line = RunSummaryLine(axis: axis, state: L.s("딱 좋은 강도", "Just right"), tone: .good)
        } else {
            let high3 = frac(3) + frac(4) + frac(5)
            let pct = Int((high3 * 100).rounded())
            if let phase = i.planPhase, planEasyPhases.contains(phase), high3 >= easyHighZoneFrac {
                // 유형이 '계획된 고강도'여도 플랜이 우선한다 — 회복·테이퍼 주의 고강도는 계획대로가 아니다
                planDeviationPhase = phase
                line = RunSummaryLine(axis: axis,
                                      state: L.s("\(phase) 주인데 고강도 · Zone 3 이상 \(pct)%",
                                                 "High intensity in an easy week · \(pct)% in Zone 3+"),
                                      tone: .neutral)
            } else if easyIntentTypes.contains(i.workoutType), high3 >= easyHighZoneFrac {
                isEasyHighBranch = true
                let label = i.workoutType.koreanLabel
                line = RunSummaryLine(axis: axis,
                                      state: L.s("\(label) 기준 높음 · Zone 3 이상 \(pct)%", "High for \(label) · \(pct)% in Zone 3+"),
                                      tone: .neutral)
            } else {
                switch dom {
                case 1: line = RunSummaryLine(axis: axis, state: L.s("가벼운 회복 강도", "Light recovery"), tone: .good)
                case 2: line = RunSummaryLine(axis: axis, state: L.s("딱 좋은 강도", "Just right"), tone: .good)
                case 3:
                    if i.workoutType == .interval {
                        // 인터벌은 평균 존이 회복 구간에 깎여 나가므로 Zone 3 우세만으로도 계획대로 고강도로 본다
                        line = RunSummaryLine(axis: axis, state: L.s("계획대로 고강도", "High intensity, as planned"), tone: .good)
                    } else if FormNarrative.isPlannedHighIntensity(i.workoutType) {
                        line = RunSummaryLine(axis: axis, state: L.s("계획대로 템포 구간", "Tempo zone, as planned"), tone: .good)
                    } else {
                        line = RunSummaryLine(axis: axis, state: L.s("템포 구간에 머묾", "Stayed in tempo zone"), tone: .neutral)
                    }
                default:
                    line = FormNarrative.isPlannedHighIntensity(i.workoutType)
                        ? RunSummaryLine(axis: axis, state: L.s("계획대로 고강도", "High intensity, as planned"), tone: .good)
                        : RunSummaryLine(axis: axis,
                                         state: L.s("고강도 구간이 많음 · Zone 3 이상 \(pct)%", "Mostly high intensity · \(pct)% in Zone 3+"),
                                         tone: .neutral)
                }
            }
        }

        var next: String? = nil
        if let phase = planDeviationPhase {
            next = L.s("\(phase) 주는 다음 고강도를 받아낼 몸을 만드는 기간이에요. 다음 러닝은 이지런으로 돌아가세요.",
                      "An easy week is what makes the next hard block land — make your next run an easy one.")
        } else if isEasyHighBranch {
            if let pace = i.easyPace {
                next = L.s("다음 이지런은 Zone 2 상단, \(mrFormatPace(pace.paceSec)) 정도로 가 보세요.",
                          "On your next easy run, aim for the top of Zone 2 — around \(mrFormatPace(pace.paceSec)).")
            } else {
                next = L.s("다음 이지런은 Zone 2 상단으로 가 보세요.", "On your next easy run, aim for the top of Zone 2.")
            }
        }

        // 이 줄이 뜬 까닭(대회 훈련 계획 단계)은 상태어가 아니라 근거 맨 앞에서 말한다 — 상태어는 짧게 유지
        if let phase = planDeviationPhase {
            evidence = L.s("대회 훈련 계획상 \(phase) 주 · \(evidence)",
                          "Race-plan easy week · \(evidence)")
        }
        line.evidence = evidence
        line.next = next
        return line
    }

    private static func loadLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        let L = AppLanguage.shared
        let axis = L.s("훈련부하", "Training load")
        let evidence = loadEvidence(i)

        guard i.weekOverWeek != nil || i.acuteChronic != nil else {
            // 부하 데이터가 없어도 연속일 자체는 보여준다
            guard i.streakDays >= 3 else { return nil }
            // 연속 4일 이상이면 회복을 권하는 next와 어긋나지 않도록 tone을 중립으로 낮춘다
            let tone: RunSummaryLine.Tone = i.streakDays >= 4 ? .neutral : .good
            var line = RunSummaryLine(axis: axis, state: L.s("\(i.streakDays)일 연속", "\(i.streakDays) days in a row"), tone: tone)
            line.evidence = evidence
            line.next = loadNext(i, jumped: false)
            return line
        }
        // 상태어는 4주 평균 대비(acuteChronic)로만 정한다. 최근 7일 대 직전 7일 증감(weekOverWeek)은 창 경계에 걸린
        // 고강도 하루가 빠지는 것만으로 하루 사이 +62% → +23%로 뒤집히므로 결론에 쓰지 않고 근거 줄에 숫자로만 적는다.
        let jumped = i.acuteChronic == .high || i.acuteChronic == .veryHigh

        var state: String
        var tone: RunSummaryLine.Tone
        switch i.acuteChronic {
        case .veryHigh:
            state = L.s("4주 평균 대비 크게 높음", "Well above 4-wk avg")
            tone = .neutral
        case .high:
            state = L.s("4주 평균 대비 높음", "Above 4-wk avg")
            tone = .neutral
        case .low:
            state = L.s("평소보다 가볍게", "Lighter than usual")
            tone = .good
        case .steady:
            state = L.s("4주 평균 수준", "Around 4-wk avg")
            tone = .good
        case nil:
            // 4주 비교가 아직 안 되는 기간(유효 창 3개 미만) — 증감 %만으로 높다/가볍다를 말하지 않고 7일 합만 적는다
            if let au = i.sevenDayAU {
                state = L.s("7일 \(groupedInt(au)) AU 기준", "7-day \(groupedInt(au)) AU")
            } else {
                state = L.s("4주 비교 전", "No 4-wk baseline yet")
            }
            tone = .good
        }
        if i.streakDays >= 4 {
            // next가 회복/휴식을 권할 만큼 연속이 길어지면(loadNext ≥4일 규칙) state의 초록 tone과 어긋난다 — 중립으로 맞춘다
            tone = .neutral
        }
        if i.todayEffortMissing {
            // 오늘 러닝이 0 AU로 들어간 합계로 "가볍게"라고 말하면 고강도 직후에 뒤집힌다 — 입력 전이라는 사실만 말한다
            state = L.s("오늘 강도 입력 전", "Today's effort not rated yet")
            tone = .neutral
        }
        if i.streakDays >= 3 {
            state += L.s(" · \(i.streakDays)일 연속", " · \(i.streakDays) days in a row")
        }
        var line = RunSummaryLine(axis: axis, state: state, tone: tone)
        line.evidence = evidence
        line.next = loadNext(i, jumped: jumped)
        return line
    }

    /// 근거: "7일 N AU · 이전 7일 N · 최근 7일 +N%" — 있는 것만, 이 순서로.
    /// 연속일은 **상태어에만** 쓴다(loadLine) — 두 줄에 같은 "N일 연속"이 겹쳐 보이지 않게.
    private static func loadEvidence(_ i: RunSummaryInput) -> String? {
        let L = AppLanguage.shared
        var parts: [String] = []
        if let au = i.sevenDayAU {
            parts.append(L.s("7일 \(groupedInt(au)) AU", "7-day \(groupedInt(au)) AU"))
            if let prev = i.previousSevenAU {
                parts.append(L.s("이전 7일 \(groupedInt(prev))", "previous 7 days \(groupedInt(prev)) AU"))
            }
        }
        if let w = i.weekOverWeek {
            // 증감은 상태어가 아니라 근거의 숫자 — 부호를 붙여 그대로 적는다
            let pct = Int((abs(w) * 100).rounded())
            let signed = (w < 0 ? "-" : "+") + "\(pct)%"
            parts.append(L.s("최근 7일 \(signed)", "Last 7 days \(signed)"))
        }
        if i.todayEffortMissing, !parts.isEmpty {
            parts.append(L.s("오늘 러닝 미포함", "today's run not included"))
        }
        // 라벨은 뜻이 바로 읽히게: 7일 평균 → "이번 주", 4주 중앙값 → "평소"(사용자 결정 2026-09-22)
        // HRV는 부하(AU) 줄과 다른 자료라 다음 줄 첫 칸에서 시작한다 — 한 줄에 이어 붙이면 "HRV" 뒤에서 접혀 읽기 어렵다.
        var lines: [String] = []
        if !parts.isEmpty { lines.append(parts.joined(separator: " · ")) }
        if let t = i.hrvTrend {
            let seven = Int(t.sevenDayMean.rounded()), base = Int(t.baseline.rounded())
            // 상태어는 본인 4주 기준선 대비다 — 절대 등급이 아니다. 좋음(위·안정) / 불안정 / 낮음(아래) / 보통(범위 안)
            let grade = hrvGradeLabel(t)
            if let n = i.lastNightHRV {
                let night = Int(n.rounded())
                // 어젯밤이 기준선 범위를 벗어나면 그 자리에 표시 — 추세 상태어(보통)만 보면 어젯밤도 보통인 줄 안다.
                // 아침 제안과 같은 문턱(MRReadiness.lastNightDeviation).
                let dev = MRReadiness.lastNightDeviation(n, trend: t)
                let nightNote = dev < 0 ? L.s("(평소보다 낮음)", " (below usual)")
                              : dev > 0 ? L.s("(평소보다 높음)", " (above usual)") : L.s("(평소 범위)", " (usual range)")
                // 상태어는 이번 주(7일 평균) 판정 — 이번 주 숫자 바로 뒤 괄호로. 어젯밤 괄호와 같은 자리라 무엇을 두고 하는 말인지 헷갈리지 않는다.
                lines.append(L.s("HRV 어젯밤 \(night)\(nightNote) · 7일 평균 \(seven)(\(grade)) · 4주 평균 \(base)ms",
                               "HRV last night \(night)\(nightNote) · 7-day avg \(seven) (\(grade)) · 4-wk avg \(base)ms"))
            } else {
                lines.append(L.s("HRV 7일 평균 \(seven)(\(grade)) · 4주 평균 \(base)ms", "HRV 7-day avg \(seven) (\(grade)) · 4-wk avg \(base)ms"))
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// HRV 근거 상태어 — 본인 4주 기준선 대비 관찰어. 억제(아래·불안정)가 좋음보다 먼저다.
    static func hrvGradeLabel(_ t: MRHRVTrend) -> String { t.gradeLabel }

    /// 계획상 회복/테이퍼 주 > 급증/단조/장기 연속 > 충분한 회복 순으로 다음 행동을 고른다.
    /// 어젯밤 한 밤이 평소(4주)보다 15% 넘게 낮았나 — 근거 줄의 "(평소보다 낮음)"과 같은 판정. 추세가 보통이어도 다음 행동에 반영한다.
    private static func lastNightLow(_ i: RunSummaryInput) -> Bool {
        guard let t = i.hrvTrend, let n = i.lastNightHRV else { return false }
        return MRReadiness.lastNightDeviation(n, trend: t) < 0
    }

    private static func loadNext(_ i: RunSummaryInput, jumped: Bool) -> String? {
        let L = AppLanguage.shared
        if i.todayEffortMissing {
            return L.s("강도를 입력하면 오늘 러닝이 부하에 반영돼요.", "Rate today's effort and it will count toward your load.")
        }
        if let phase = i.planPhase {
            if phase == "회복" {
                return L.s("대회 훈련 계획상 회복 주예요. 이지런 위주로 가세요.", "Your race plan has this as a recovery week — stick to easy runs.")
            }
            if phase == "테이퍼" {
                return L.s("대회 훈련 계획상 테이퍼 주예요. 이지런 위주로 가세요.", "Your race plan has this as a taper week — keep it easy.")
            }
        }
        if jumped || i.loadSentence == .monotony || i.streakDays >= 4 {
            var s = L.s("다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요.",
                        "Take a 30–40 min recovery run or rest for the next day or two.")
            if i.hrvTrend?.isSuppressed == true {
                s += L.s(" HRV도 기준선 아래로 흔들리고 있어요.", " Your HRV is also wobbling below baseline.")
            } else if lastNightLow(i) {
                // 추세는 보통이어도 어젯밤이 낮았으면 그 사실을 다음 행동에 붙인다 — 근거 줄의 "(평소보다 낮음)"과 짝
                s += L.s(" 어젯밤 HRV도 평소보다 낮았어요.", " Last night's HRV was also below usual.")
            }
            return s
        }
        if i.todayIsHard {
            return L.s("오늘 강도를 냈으니 내일은 이지런이나 휴식이 좋아요.",
                      "You went hard today — make tomorrow an easy run or a rest day.")
        }
        // 히스테리시스: 어제(창 하루 전)까지 4주 평균 대비 높음이었다가 오늘 유지/가볍게로 내려온 날은
        // "충분히 회복"이 아니라 "내려오는 중" — 창 경계로 고강도 하루가 빠진 것뿐일 수 있다.
        let yesterdayHigh = i.acuteChronicYesterday == .high || i.acuteChronicYesterday == .veryHigh
        let todayCalm = i.acuteChronic == .steady || i.acuteChronic == .low
        if yesterdayHigh && todayCalm {
            return L.s("부하가 내려오는 중이에요. 하루 더 편하게 가면 좋아요.",
                      "Load is coming down — one more easy day is a good idea.")
        }
        // 결정 2: 4주 평균 대비 자료 없이는 "충분히 회복됐다"고 말하지 않는다 — 마지막 고강도 이후 며칠 지났는지만으로는
        // 근거가 얕다. 유지(.steady)라도 최근 7일이 직전 7일보다 15% 이상 늘었으면 아직 회복 국면이 아니다.
        let rested: Bool = {
            guard let days = i.daysSinceHardRun, days >= 2 else { return false }
            guard i.loadSentence != .monotony, !yesterdayHigh else { return false }
            switch i.acuteChronic {
            case .low: return true
            case .steady: return (i.weekOverWeek ?? 0) < restedWeekOverWeekMax
            default: return false
            }
        }()
        if rested {
            // HRV가 있으면 회복 판정을 한 번 더 거른다 — 부하는 내려왔어도 HRV가 아래·불안정이면 "충분히"라고 하지 않는다.
            // 위·안정이면 2주 이지 블록(회복이 쌓임)과 고강도 있음(잘 흡수함)을 나눠 말한다. 범위 안이면 기존 문장.
            if let t = i.hrvTrend {
                if t.isSuppressed {
                    return L.s("부하는 내려왔지만 HRV가 기준선 아래예요. 수면이나 생활 피로 쪽일 수 있으니 하루 더 편하게 가세요.",
                               "Load has come down, but your HRV is below baseline. It may be sleep or life stress — take one more easy day.")
                }
                if lastNightLow(i) {
                    // 추세는 보통인데 어젯밤만 낮음 — "충분히 회복"이라 하지 않고 하루만 미룬다
                    return L.s("부하는 내려왔지만 어젯밤 HRV가 평소보다 낮았어요. 하루 더 편하게 가세요.",
                               "Load has come down, but last night's HRV was below usual — take one more easy day.")
                }
                if t.isReadyHigh {
                    return i.isEasyBlock
                        ? L.s("2주 이지런으로 회복이 쌓였어요. HRV가 4주 기준선 위로 안정적이라 이번 주 강도 세션 넣기 좋아요.",
                              "Two weeks of easy running have built up recovery. Your HRV is steadily above its 4-week baseline — a good week for a quality session.")
                        : L.s("충분히 회복됐어요. 고강도 뒤에도 HRV가 기준선 위라 부하를 잘 흡수하고 있어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.",
                              "You're well recovered. Your HRV stayed above baseline even after hard runs, so you're absorbing the load — a good time for a build-up or tempo run.")
                }
            }
            return L.s("충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.",
                      "You're well recovered — a good time for a build-up or tempo run.")
        }
        // 유지(.steady)인데 회복 판정에는 못 미치는 날(최근 7일이 직전보다 15% 이상 늘었거나 고강도가 최근) —
        // 다음 줄이 비어 보이지 않게 중립 한 줄. 부하가 오르는 중이면 고강도 사이에 쉬운 날을 두라는 말만 붙인다.
        // 증감 폭은 말하지 않는다("조금/크게") — 근거 줄의 숫자(+81% 같은)와 싸운다. "하루 간격"은 이틀 연속 고강도를 피하라는 뜻.
        if i.acuteChronic == .steady {
            let rising = (i.weekOverWeek ?? 0) >= restedWeekOverWeekMax
            guard rising else { return L.s("지금 리듬을 유지하면 좋아요.", "Keep this rhythm.") }
            if i.hrvTrend?.isReadyHigh == true {
                return L.s("지금 리듬을 유지하면 좋아요. HRV는 좋고 직전 7일보다 부하가 늘었으니, 고강도 사이에는 쉬운 날 하루를 두세요.",
                           "Keep this rhythm. HRV looks good and load is up on the previous 7 days, so leave an easy day between hard sessions.")
            }
            return L.s("지금 리듬을 유지하면 좋아요. 직전 7일보다 부하가 늘었으니 고강도 사이에는 쉬운 날 하루를 두세요.",
                       "Keep this rhythm. Load is up on the previous 7 days, so leave an easy day between hard sessions.")
        }
        return nil
    }

    private static func aerobicLine(_ i: RunSummaryInput) -> RunSummaryLine? {
        guard let v = i.vo2 else { return nil }
        let L = AppLanguage.shared
        let level = vo2Level(v)
        let g = i.vo2GenderLabel.isEmpty ? "" : " \(i.vo2GenderLabel)"
        var line = RunSummaryLine(axis: L.s("유산소", "Aerobic"),
                              state: L.s("\(i.vo2AgeDecade)\(g) 기준 \(level.name)", "\(level.name) for \(i.vo2AgeDecade)\(g)"),
                              tone: level.index >= 2 ? .good : .neutral)
        // "VO2max N.N"은 로케일과 무관 — L.s 없이 그대로 쓴다(no-op 래핑 금지)
        var evidence = "VO2max \(String(format: "%.1f", v))"
        if let prev = i.vo2EightWeeksAgo {
            let diff = v - prev
            if abs(diff) >= vo2DeltaEvidenceMin {
                let sign = diff >= 0 ? "+" : "-"
                let diffStr = String(format: "%.1f", abs(diff))
                evidence += L.s(" · 8주 전 대비 \(sign)\(diffStr)", " · vs. 8 weeks ago \(sign)\(diffStr)")
            }
        }
        line.evidence = evidence
        return line
    }

    /// 천단위 콤마 정수 문자열("1,783") — 로케일 고정(en_US_POSIX): 기기 로케일이 바뀌어도 구분자가 안 흔들린다.
    /// ⚠ en_US_POSIX는 그룹 구분자를 스스로 정의하지 않는다(POSIX/C 로케일 특성) — 명시적으로 켜 줘야 "1,783"이 된다.
    private static let groupedIntFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        nf.locale = Locale(identifier: "en_US_POSIX")
        nf.usesGroupingSeparator = true
        nf.groupingSeparator = ","
        nf.groupingSize = 3
        return nf
    }()

    private static func groupedInt(_ v: Double) -> String {
        groupedIntFormatter.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v.rounded()))"
    }
}
