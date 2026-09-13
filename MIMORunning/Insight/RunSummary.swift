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
    /// 마지막 고강도(계획된 고강도 유형 또는 체감 강도 7 이상) 러닝으로부터 지난 일수
    var daysSinceHardRun: Int? = nil
    /// 이번 주 플랜 단계 원문("회복"/"테이퍼"/…) — 대회 플랜이 있을 때만
    var planPhase: String? = nil
    /// 이지 페이스 조회값 — 있을 때만 다음 이지런 페이스를 숫자로 제안
    var easyPace: MRHRPaceLookup? = nil
    var vo2EightWeeksAgo: Double? = nil
}

/// 총평 규칙. 축 순서 고정: 러닝폼 → 거리 적응 → 심박 → 훈련부하 → 유산소.
/// 상태어는 관찰 사실만. 톤은 초록(good)·노랑(neutral) 둘.
/// 각 줄의 `evidence`(왜 이 말이 나왔나)·`next`(그래서 뭘 하나)도 여기서 함께 채운다.
enum RunSummary {
    static let distanceRatioMin = 1.30
    /// 이지 의도 유형에서 Zone 3 이상 비율이 이 이상이면 "기준 높음"
    static let easyHighZoneFrac = 0.50
    static let loadJumpMin = 0.30
    /// 존 캡션 더위 보정 표기 임계값(bpm) — 존 캡션·근거 줄이 공유해서 쓴다. 총평 상태어에는 붙이지 않는다.
    static let heatNoteMinBpm = 5.0
    /// 심박 근거 줄에서 "(더위 +N)"을 붙이는 문턱(bpm) — 문장 단위 "기온 감안" 임계값과 같다.
    static let heatEvidenceMinBpm = MRHeatHRModel.explainThresholdBpm
    static let vo2Bounds: [Double] = [15, 26, 33, 41, 57]
    /// VO2max 8주 전 대비 근거 절을 붙이는 최소 변화폭 — 이보다 작으면 잡음으로 보고 생략
    static let vo2DeltaEvidenceMin = 0.05
    // 거리주(레이스페이스 장거리)는 빠른 게 정의라 이지 의도로 판정하지 않는다
    static let easyIntentTypes: Set<WorkoutType> = [.easy, .longRun, .lsd]

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
            pieces.append(L.s(inRange ? "접지 \(n) 범위 안" : "접지 \(n) 범위 위",
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
                return L.s(prefixKo + "후반 접지만 지켜보세요.", prefixEn + "watch your late-run ground contact.")
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
        let next = L.s("이 거리는 2~3주 유지한 뒤 늘리세요. 롱런은 한 번에 평소의 1.3배 안에서.",
                      "Hold this distance for 2–3 weeks before increasing. Keep long runs within 1.3× your usual, one step at a time.")

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
        var line: RunSummaryLine

        if frac(2) >= 0.60 {
            line = RunSummaryLine(axis: axis, state: L.s("딱 좋은 강도", "Just right"), tone: .good)
        } else {
            let high3 = frac(3) + frac(4) + frac(5)
            let pct = Int((high3 * 100).rounded())
            if easyIntentTypes.contains(i.workoutType), high3 >= easyHighZoneFrac {
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
        if isEasyHighBranch {
            if let pace = i.easyPace {
                next = L.s("다음 이지런은 Zone 2 상단, \(mrFormatPace(pace.paceSec)) 정도로 가 보세요.",
                          "On your next easy run, aim for the top of Zone 2 — around \(mrFormatPace(pace.paceSec)).")
            } else {
                next = L.s("다음 이지런은 Zone 2 상단으로 가 보세요.", "On your next easy run, aim for the top of Zone 2.")
            }
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
        let wow = i.weekOverWeek ?? 0
        // jumped가 lighter보다 우선한다 — 이번 주 급증은 4주 평균이 낮아도(acuteChronic .low) 조용히 넘기지 않는다(과훈련 신호 존중)
        let jumped = wow >= loadJumpMin || i.acuteChronic == .high || i.acuteChronic == .veryHigh
        let lighter = i.acuteChronic == .low || (i.acuteChronic == nil && wow <= -loadJumpMin)

        var state: String
        var tone: RunSummaryLine.Tone
        if jumped {
            // 경고 점이 음수 %와 나란히 찍히면 안 된다 — 급증 판정은 acuteChronic에서 왔을 수도 있으니 wow가 실제로 상승일 때만 %를 찍는다
            if let w = i.weekOverWeek, w >= loadJumpMin {
                let pct = Int((w * 100).rounded())
                state = L.s("이번 주 +\(pct)%", "This week +\(pct)%")
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
        if i.streakDays >= 4 {
            // next가 회복/휴식을 권할 만큼 연속이 길어지면(loadNext ≥4일 규칙) state의 초록 tone과 어긋난다 — 중립으로 맞춘다
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

    private static func loadEvidence(_ i: RunSummaryInput) -> String? {
        let L = AppLanguage.shared
        guard let au = i.sevenDayAU else {
            return i.streakDays >= 3 ? L.s("\(i.streakDays)일 연속", "\(i.streakDays) days in a row") : nil
        }
        var e = L.s("7일 \(groupedInt(au)) AU", "7-day \(groupedInt(au)) AU")
        if let prev = i.previousSevenAU {
            e += L.s(" · 이전 7일 \(groupedInt(prev))", " · previous 7 days \(groupedInt(prev)) AU")
        }
        if i.streakDays >= 3 {
            e += L.s(" · \(i.streakDays)일 연속", " · \(i.streakDays) days in a row")
        }
        return e
    }

    /// 계획상 회복/테이퍼 주 > 급증/단조/장기 연속 > 충분한 회복 순으로 다음 행동을 고른다.
    private static func loadNext(_ i: RunSummaryInput, jumped: Bool) -> String? {
        let L = AppLanguage.shared
        if let phase = i.planPhase {
            if phase == "회복" {
                return L.s("플랜상 회복 주예요. 이지런 위주로 가세요.", "Your plan has this as a recovery week — stick to easy runs.")
            }
            if phase == "테이퍼" {
                return L.s("플랜상 테이퍼 주예요. 이지런 위주로 가세요.", "Your plan has this as a taper week — keep it easy.")
            }
        }
        if jumped || i.loadSentence == .monotony || i.streakDays >= 4 {
            return L.s("다음 1~2일은 30~40분 회복 이지런이나 휴식이 좋아요.",
                      "Take a 30–40 min recovery run or rest for the next day or two.")
        }
        if i.todayIsHard {
            return L.s("오늘 강도를 냈으니 내일은 이지런이나 휴식이 좋아요.",
                      "You went hard today — make tomorrow an easy run or a rest day.")
        }
        // 결정 2: 부하 자료(4주 평균 대비 or 7일 AU) 없이는 "충분히 회복됐다"고 말하지 않는다 — 마지막 고강도 이후
        // 며칠 지났는지만으로는 근거가 얕다.
        let rested: Bool = {
            guard let days = i.daysSinceHardRun, days >= 2 else { return false }
            guard i.acuteChronic != nil || i.sevenDayAU != nil else { return false }
            let acOk: Bool
            switch i.acuteChronic {
            case nil, .low, .steady: acOk = true
            default: acOk = false
            }
            return acOk && i.loadSentence != .monotony
        }()
        if rested {
            return L.s("충분히 회복됐어요. 빌드업이나 템포런을 넣기 좋은 시점이에요.",
                      "You're well recovered — a good time for a build-up or tempo run.")
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
