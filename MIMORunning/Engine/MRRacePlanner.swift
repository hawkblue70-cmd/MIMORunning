import Foundation

// MARK: - 상수 (전부 2차 문헌 감사를 통과한 값)

/// 테이퍼 이득 1.0%
///
/// ⚠ Smyth & Lawlor 2021(n=158,117)의 "중앙값 5분32초 = 2.6%"를 그대로
///   쓰면 안 된다. 그 값의 비교 기준은 **relaxed 1주 테이퍼**인데,
///   실제로는 러너의 64%가 이미 2~3주 테이퍼를 한다. 현실적 baseline
///   대비 한계 이득은 약 1%p다. 게다가 관찰연구이고 저자 본인이
///   "strict taper를 하는 사람이 애초에 훈련량도 많다"는 교란을 인정했다.
let MR_TAPER_GAIN = 0.010

struct MRPlanWeek {
    let idx: Int
    let monday: Date
    let phase: String           // 기초 / 구축 / 특이 / 회복 / 테이퍼
    let longRunKm: Double
    let longRunMin: Double
    let weeklyKm: Double
    let projectedMin: Double
    let isNewMax: Bool
    /// 이 주가 최근 12개월 최대 주간 거리를 처음 넘는 주인지 — 사실 표시용
    var isVolRecord: Bool = false
    /// "롱런 11km + 이지 8km × 3회" 같은 실행 안내
    ///
    /// ⚠ 주간 합계만 주면 사용자가 나눌 방법을 모른다.
    ///   횟수는 **본인의 최근 4주 러닝 빈도**를 그대로 쓴다.
    ///   "주 5회 하세요" 같은 지시를 하지 않기 위해서다 —
    ///   지금 하고 있는 리듬 위에 거리만 얹는다.
    var breakdown: String = ""
}

struct MRRacePlan {
    let raceDate: Date
    let distanceM: Double
    var weeks: [MRPlanWeek] = []
    var reachableLongKm = 0.0
    var targetLongKm = 0.0
    var peakWeeklyKm = 0.0
    /// 최근 12개월 최대 주간 거리 — 참고용, 판단이 아님
    var histMaxWeeklyKm = 0.0
    var projectedNow = 0.0
    var projectedFinal = 0.0
    /// 불확실성 하한 (마라톤 전용, 0이면 미계산)
    var projectedFinalLo = 0.0
    /// 불확실성 상한 (마라톤 전용, 0이면 미계산)
    var projectedFinalHi = 0.0
    /// σ₈ 데이터 부족으로 구간을 못 구했을 때 보여줄 참고 문구
    var projectedFinalNote = ""
    var verdict = ""
    var notes: [String] = []
    var taperWeeks = 2
    /// 역산된 계획 시작일. nil이면 오늘 즉시 시작.
    var startDate: Date? = nil
    /// 헤더 아래에 표시할 시작일 안내 문구. 비어 있으면 표시 안 함.
    var startNote: String = ""
    /// 계획 시작 시점의 롱런 — 롱런 게이지 왼쪽 값.
    var startingLongKm = 0.0
    /// 앞 대회 종료 후 계획 시작까지의 타임라인. [(날짜범위, 내용)] — 비어 있으면 표시 안 함.
    var bridgeRows: [(range: String, text: String)] = []
    /// 이 계획의 주차 안에 "대회 주"로 흡수된 튠업 대회 날짜. 스토어가 독립 계획 생략 여부를 정한다.
    var absorbedTuneUpDates: [Date] = []
}

// MARK: - 튠업 대회
//
// A 레이스(하프 이상) 하나에만 계획을 만들고, 그 기간 안의 5K·10K(풀 계획 안의 하프)는
// 별도 계획 없이 해당 주를 "대회 주"로 바꾼다. 코칭 관행의 A/B/C 레이스 구분을
// 사용자 입력 없이 거리로 추론한 것이다.

/// A 계획 안에 들어오는 튠업 대회.
struct MRTuneUpRace {
    let date: Date
    let name: String
    let distanceM: Double
    /// 이미 독립 계획(스냅샷)이 있는 대회 — "사용자가 신경 쓰는 대회"로 해석해 그 전 주를 테이퍼로 양보한다.
    var hasOwnPlan: Bool = false
}

/// 튠업 대회 주 주간 거리 배율 — 임의로 정함 (Bosquet 2007 테이퍼 원칙을 거리에 맞춰 축소).
let MR_TUNEUP_SHORT_VOL = 0.80   // 5K·10K 주: 대회 전 2~3일 가볍게, 롱런은 유지(대회 이틀 뒤)
let MR_TUNEUP_HALF_VOL  = 0.70   // 하프 주: 대회가 그 주 롱런, 앞 5~7일 볼륨 −30%, 다음 주 회복

/// A 레이스 하나에 대한 튠업 후보: 오늘 < 날짜 < A 날짜이고, 하프 미만이거나 (A가 풀일 때만) 하프.
/// 실제 흡수 여부는 플래너가 계획 주차 안에 드는지로 정한다(`MRRacePlan.absorbedTuneUpDates`).
func mrTuneUpCandidates(for race: MRTargetRace, among races: [MRTargetRace], today: Date,
                        plannedKeys: Set<String> = []) -> [MRTuneUpRace] {
    let cal = Calendar.current
    let t0 = cal.startOfDay(for: today), t1 = cal.startOfDay(for: race.date)
    return races.filter { r in
        guard r.id != race.id, r.distanceM < MRDistance.dF else { return false }
        if r.distanceM >= MRDistance.dH && race.distanceM < MRDistance.dF { return false }
        let d = cal.startOfDay(for: r.date)
        return d > t0 && d < t1
    }
    .sorted { $0.date < $1.date }
    .map { MRTuneUpRace(date: $0.date, name: $0.name, distanceM: $0.distanceM,
                        hasOwnPlan: plannedKeys.contains(mrArchiveKey(raceDate: $0.date, distanceM: $0.distanceM))) }
}

/// 롱런을 진행시켜 대회일까지의 계획을 만든다.
///
/// 진행 규칙과 그 근거:
///
/// · 세션 스텝 10% — Frandsen 2025 (BJSM 59(17):1203–1210, n=5,205)의
///   **참조 밴드**다. 그 위로는 10–30% HRR 1.64 / 30–100% 1.52 / >100% 2.28.
///   ⚠ 관계가 단조증가가 아니다. "10% 초과 = 1.64"는 밴드 하나를
///     전체로 확대한 오독이다.
///
/// · 주간 볼륨 캡 **없음** — RCT 근거가 없다.
///   Buist 2008 (Am J Sports Med 36(1):33–39, n=532 RCT):
///   10% graded vs 표준 → 부상률 20.8% vs 20.3%, **p=0.90**.
///   같은 Frandsen 2025조차 ACWR·주간비를 무관계로 보고한다.
///
/// · 부상 이력 특별 처리 **없음** — "7%·2:1"은 창작된 숫자였다.
///   실재하는 것은 Desai 2021 (JOSPT 51(3):144–150, n=224)의
///   "이전 부상 이력 HR 1.9"뿐이고, 그걸 진행률로 번역한 문헌은 없다.
///   → 숨겨진 감속 대신 사실만 알려 준다.
///
/// · 테이퍼 2주 · 지수 감소 — Bosquet 2007 (MSSE 39(8):1358–1365, 27연구
///   메타): "2-wk taper, volume **exponentially reduced by 41–60%**",
///   강도와 빈도는 유지. 3주 선형 0.80/0.60/0.40은 평균 감량 40%로
///   최적 밴드에도 못 미쳤다.
///
/// · 목표 롱런 28km — 롱런 페널티 계단이 0이 되는 지점.
///   계단 자체는 Fokkema 2020의 "<25km = +13.4분" 하나에서
///   왔고 22~28 전이는 절단점 불확실성 때문에 둔 것이다.
///   Doherty 2020은 32km 문턱을 쓰지만 코호트 평균 수준이라
///   개인 지수 조정에는 이식하지 않았다.
///
/// · 하프 목표 롱런 21km — Fokkema 2020 (Scand J Med Sci Sports 30(9):1692–1704,
///   하프군 n=556): 최장 롱런 >21km β −3.87분 (95% CI −6.31~−1.44),
///   주간 >32km β −4.19분 (−6.52~−1.85). 기준군 15–21km · 20–32km/wk.
///   ⚠ 이전 기록 미보정 관찰연구 — 빠른 러너가 원래 더 뛴다는 교란이 남아 있다.
///   ⚠ "21km 이상 = 12~15분"은 이 논문에 없다. 그건 풀의 <25km +13.4분이다.
///
/// · 롱런 후반 대회 페이스 구간 — 코칭 관행. 통제 연구 없음. mrRacePaceSegmentMinutes 참조.
func mrBuildPlan(raceDate: Date,
                 distanceM: Double,
                 today: Date,
                 profile: MRProfile,
                 halfEquivMin: Double,
                 easyPaceSecPerKm: Double?,
                 heat: MRHeatModel,
                 raceTempC: Double,
                 runsPerWeek: Double = 3.0,
                 priorRace: (date: Date, name: String, distanceM: Double, peakLong: Double, peakVol: Double)? = nil,
                 forcedMonday: Date? = nil,
                 tuneUps: [MRTuneUpRace] = [],
                 caller: String = "unknown",
                 raceName: String = "") -> MRRacePlan? {

    let L = AppLanguage.shared
    let cal = Calendar.current
    let totalDays = cal.dateComponents([.day], from: cal.startOfDay(for: today),
                                       to: cal.startOfDay(for: raceDate)).day ?? 0
    let totalWeeks = totalDays / 7
    guard totalWeeks >= 3 else { return nil }
    // ⚠ 하프 등가가 없으면 예측이 성립하지 않는다.
    //   0을 그리면 "0분 00초에 완주"라는 말이 되어 신뢰가 통째로 무너진다.
    //   계획을 아예 만들지 않고, 화면은 그 대회를 조용히 건너뛴다.
    guard halfEquivMin > 10 else { return nil }
    // 완전 입문자(주간 5km 미만 + 최근 16주 최장 3km 미만)에게는 계획을 내놓지 않는다.
    // 부상·휴식으로 최근 4주가 비어 있어도 16주 안에 기록이 있으면 복귀자로 판단한다.
    // 플래너의 목적은 "지금 뛸 수 있는가"가 아니라 "여기까지 쌓을 수 있는가"이므로
    // 롱런 35% 하한선은 쓰지 않는다 — 훈련으로 도달할 수 있는 사람의 계획까지 없애기 때문.
    if profile.weeklyKm4w < 5 && profile.longestRun16wKm < 3 { return nil }
    if distanceM >= MRDistance.dF && profile.weeklyKm4w < 15 { return nil }

    var p = MRRacePlan(raceDate: raceDate, distanceM: distanceM)
    p.taperWeeks = distanceM >= MRDistance.dH ? 2 : 1
    let stepPct = 0.10
    let cycleLen = 4                    // 3주 부하 + 1주 회복
    // 목표 롱런: 레이스 거리별 상한. 짧은 레이스에 과도한 부하를 막는다.
    // 5K ≤ 12km(2.4×) · 10K ≤ 16km(1.6×) · 하프 ≤ 21km(1.0×) · 풀 ≤ 28km(0.66×)
    if distanceM >= MRDistance.dF {
        p.targetLongKm = 28.0
    } else if distanceM >= MRDistance.dH {
        p.targetLongKm = 21.0
    } else if distanceM >= MRDistance.d10 {
        p.targetLongKm = 16.0
    } else {
        p.targetLongKm = 12.0   // 5K 이하
    }

    // '지금 상태로 나가면' — 거리별로 다르게 계산한다.
    // 풀만 durability 지수를 쓰고, 하프 이하는 하프 등가에서 직접 환산한다.
    p.projectedNow = mrProjectedRefMin(halfEquivMin: halfEquivMin, distanceM: distanceM,
                                       weeklyKm: profile.weeklyKm4w,
                                       longestKm: profile.longestRun16wKm,
                                       finishes: profile.marathonFinishes)
    // ⚠ 화살표 양쪽은 반드시 같은 기온 조건이어야 한다.
    //   projectedNow만 15°C면 "훈련하면 느려진다"는 화면이 나온다.
    if heat.ok { p.projectedNow = heat.fromRef(timeRefMin: p.projectedNow, tempC: raceTempC) }

    let vol = max(profile.weeklyKm4w, 10.0)
    // 주간 거리 상한 = 지난 12개월 최대. 본인이 실제로 해낸 값이므로 임의 숫자가 아니다.
    // 더 많이 뛰면 상한이 저절로 올라간다.
    // 과거 최대 0(신규 사용자)이면 현재 주간 × 1.5로 폴백 — 근거 없는 값.
    let volCap = profile.maxWeeklyKm52w > 0 ? profile.maxWeeklyKm52w : vol * 1.5

    // ── 필요 기간 역산 (시뮬레이션) ──────────────────────────────
    // 공식 대신 빌드 루프와 동일 규칙으로 반복. 증가율·회복 주기가 바뀌면 자동으로 맞는다.
    func simulateNeeded(fromLong: Double, fromVol: Double) -> Int {
        var lg = fromLong, bv = fromVol
        for w in 1...60 {
            if w % cycleLen != 0 {
                lg = min(lg * (1 + stepPct), p.targetLongKm)
                bv = min(bv * 1.05, volCap)
            }
            if lg >= p.targetLongKm - 0.1 && bv >= volCap - 0.5 { return w }
        }
        return 60  // 60주 안에 못 닿는 경우 — 실사용에서는 거의 발생하지 않는다
    }

    let simStartLong = max(profile.longestRun16wKm, 5.0)
    let simStartVol  = vol
    // 하프 튠업 하나당 롱런 진행이 2주(대회 주 + 회복 주) 멈춘다 — 필요 기간에 더한다.
    // 앞선 A 대회(priorRace) 이전의 후보는 그 계획이 맡으므로 세지 않는다.
    let halfTuneUpCount = tuneUps.filter { t in
        guard t.distanceM >= MRDistance.dH else { return false }
        if let pr = priorRace { return t.date > pr.date }
        return true
    }.count
    // 자기 계획이 있는 단거리 튠업은 그 전 주를 테이퍼로 양보하므로 1주씩 더 든다.
    let ownPlanShortCount = tuneUps.filter { t in
        guard t.hasOwnPlan, t.distanceM < MRDistance.dH else { return false }
        if let pr = priorRace { return t.date > pr.date }
        return true
    }.count
    let neededTotal  = simulateNeeded(fromLong: simStartLong, fromVol: simStartVol) + p.taperWeeks
                     + 2 * halfTuneUpCount + ownPlanShortCount

    // 날짜를 짧게 표시 — 올해(baseYear)는 "M-d", 다른 해는 "yyyy-M-d"
    let baseYear = cal.component(.year, from: today)
    func sfmt(_ d: Date) -> String {
        let y = cal.component(.year, from: d)
        let fmtr = DateFormatter()
        fmtr.locale = Locale(identifier: "ko_KR")
        fmtr.dateFormat = y == baseYear ? "M-d" : "yyyy-M-d"
        return fmtr.string(from: d)
    }

    // ── 시작일 결정: 필요 기간 < 남은 기간이면 시작을 뒤로 미룬다 ──
    var planStartLong = simStartLong
    var planStartVol  = simStartVol
    var planToday     = today          // 루프 Monday0 계산 기준

    // 앞 대회 회복 주 생성용 — 0이면 회복 주 없음
    var recoveryPriorLong = 0.0
    var recoveryPriorVol  = 0.0
    var recoveryWeekCount = 0
    var priorRaceName     = ""
    #if DEBUG
    var dbgStartNote = "앞선 대회 없음 · 즉시 시작"
    #endif

    // 앞 대회 뒤 회복 블록 — 거리별로 다르다.
    //   풀: 3주 (30/50/70%) — 마라톤 후 근손상·염증 정상화 관행. 통제 연구 못 찾음.
    //   하프: 1주 (60/70%) — 임의로 정함.
    //   10K 이하: 회복 블록 없음. 계획 안의 튠업 레이스로 두고 그냥 지나간다.
    //   ⚠ 예전에는 거리와 무관하게 3주를 넣어, 10K 6주 뒤 하프 계획이
    //     "회복 3주 + 최소 3주"를 못 채워 통째로 사라졌다(11/15 하프 사례).
    let priorRecoveryWeeks: Int = {
        guard let d = priorRace?.distanceM else { return 0 }
        return d >= MRDistance.dF ? 3 : (d >= MRDistance.dH ? 1 : 0)
    }()

    if let prior = priorRace, priorRecoveryWeeks > 0, prior.date > today, prior.date < raceDate {
        // 앞 대회 당일이 속한 주를 건너뛰고 그 다음 주 월요일부터 시작
        // Gregorian .weekday: 일=1, 월=2 … 토=7
        let priorWD = cal.component(.weekday, from: prior.date)
        let daysToNextMon = (9 - priorWD) % 7   // 일(1)→1, 월(2)→7로 처리
        let priorNext = cal.date(byAdding: .day,
                                  value: daysToNextMon == 0 ? 7 : daysToNextMon,
                                  to: cal.startOfDay(for: prior.date)) ?? cal.startOfDay(for: prior.date)
        let pLong     = max(prior.peakLong, simStartLong)
        let pVol      = max(prior.peakVol,  simStartVol)

        planToday     = priorNext
        // 빌드 루프는 회복 블록 마지막 주 상태(롱런 60%, 주간 70%)에서 시작
        planStartLong = pLong * 0.60
        planStartVol  = pVol  * 0.70
        p.startDate   = planToday

        recoveryPriorLong = pLong
        recoveryPriorVol  = pVol
        recoveryWeekCount = priorRecoveryWeeks
        priorRaceName     = prior.name
        // 타임라인: 오늘 ~ 앞 대회 전날은 그 대회 계획을 따르고, 대회 주, 그다음 이 계획.
        // 주차 테이블에서 겹치지 않게 하되, 앞 대회가 이 계획 안에 "보이게" 한다.
        let priorLabel = mrLabelFor(distanceM: prior.distanceM)
        let priorWeekMon = cal.date(byAdding: .day, value: -7, to: priorNext) ?? priorNext
        let dayBeforePriorWeek = cal.date(byAdding: .day, value: -1, to: priorWeekMon) ?? priorWeekMon
        p.bridgeRows = [
            ("\(sfmt(today)) ~ \(sfmt(dayBeforePriorWeek))",
             L.s("「\(prior.name)」 계획을 따릅니다", "Follow the \(prior.name) plan")),
            ("\(sfmt(priorWeekMon)) ~ \(sfmt(prior.date))",
             L.s("대회 주 — \(priorLabel) 대회 \(prior.name)", "Race week — \(priorLabel) \(prior.name)")),
            ("\(sfmt(planToday)) ~",
             L.s("이 계획 시작 · 회복 \(priorRecoveryWeeks)주", "Plan starts · \(priorRecoveryWeeks)-wk recovery"))
        ]
        #if DEBUG
        dbgStartNote = "앞선 대회「\(prior.name)」 다음 주"
        #endif
    } else if neededTotal < totalWeeks {
        // 앞 대회 없음 — 대회일에서 필요 기간만큼 역산해 시작
        guard let deferredStart = cal.date(byAdding: .day, value: -(neededTotal * 7), to: raceDate) else { return nil }
        planToday   = deferredStart
        p.startDate = deferredStart

        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR"); df.dateFormat = "yyyy-MM-dd"
        p.startNote = L.s("이 계획은 \(neededTotal)주짜리입니다. \(df.string(from: deferredStart))에 시작합니다.",
                          "This is a \(neededTotal)-week plan starting \(df.string(from: deferredStart)).")
        let waitEnd = cal.date(byAdding: .day, value: -1, to: deferredStart) ?? deferredStart
        p.bridgeRows = [
            ("\(sfmt(today)) ~ \(sfmt(waitEnd))", L.s("유지 — 지금처럼 달리시면 됩니다", "Maintain — keep running as you are")),
            ("\(sfmt(deferredStart)) ~", L.s("이 계획 시작", "Plan starts"))
        ]
        #if DEBUG
        dbgStartNote = "역산 \(neededTotal)주 · \(df.string(from: deferredStart)) (대기 \(totalWeeks - neededTotal)주)"
        #endif
    }

    // ── 기준 월요일(monday0) ──────────────────────────────────────────
    // forcedMonday가 있으면 스냅샷에서 고정된 시작 월요일을 사용 — 계획이 재시작되지 않는다.
    // 없으면 기존 로직: 이번 주 월요일로 역산.
    let monday0: Date
    if let forced = forcedMonday, recoveryWeekCount == 0, planToday == today {
        monday0 = cal.startOfDay(for: forced)
    } else {
        let planWD = cal.component(.weekday, from: planToday)   // Sun=1, Mon=2 … Sat=7
        if planToday == today && recoveryWeekCount == 0 {
            let daysSinceMon = (planWD + 5) % 7               // Mon=0, Tue=1, … Sun=6
            guard let m = cal.date(byAdding: .day, value: -daysSinceMon,
                                   to: cal.startOfDay(for: planToday)) else { return nil }
            monday0 = m
        } else {
            let offset = (7 - planWD + 2) % 7
            guard let m = cal.date(byAdding: .day, value: offset,
                                   to: cal.startOfDay(for: planToday)) else { return nil }
            monday0 = m
        }
    }

    // 계획 기간 계산
    // 일반: monday0 기준 → 주 안에서 날짜가 바뀌어도 총 주 수가 변하지 않는다.
    // defer/prior race: planToday 기준 — monday0이 planToday보다 늦으면 주 수가 줄기 때문.
    let planRef = (planToday == today && recoveryWeekCount == 0) ? monday0 : planToday
    let planDays = cal.dateComponents([.day], from: cal.startOfDay(for: planRef),
                                       to: cal.startOfDay(for: raceDate)).day ?? 0
    let planTotalWeeks = planDays / 7
    // 회복 주가 있으면 그만큼 더 필요 (최소 build 1주 + taperWeeks + recoveryWeekCount)
    guard planTotalWeeks >= 3 + recoveryWeekCount else {
        #if DEBUG
        print("[계획:\(caller)] \(raceName.isEmpty ? "대회" : raceName) — 계획 없음: 회복 \(recoveryWeekCount)주 포함 최소 \(3 + recoveryWeekCount)주 필요, 남은 \(planTotalWeeks)주")
        #endif
        return nil
    }
    let buildWeeks = planTotalWeeks - p.taperWeeks

    #if DEBUG
    let _dbgDist = String(format: "%.1fkm", distanceM / 1000.0)
    let _dbgDateFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
    let _dbgLabel = raceName.isEmpty ? _dbgDist : "\(raceName)(\(_dbgDist))"
    let _dbgForced = forcedMonday.map { " · forcedMonday=\(_dbgDateFmt.string(from: $0))" } ?? ""
    print("[계획:\(caller)] 대상=\(_dbgLabel) · \(_dbgDateFmt.string(from: raceDate)) · \(planTotalWeeks)주 · asOf=\(_dbgDateFmt.string(from: today))\(_dbgForced) (totalDays=\(totalDays) planDays=\(planDays))")
    print("  └ 시작=\(dbgStartNote)")
    #endif

    // 앞 대회 있을 때 startNote — planTotalWeeks 를 알아야 총 주 수 표시 가능
    if recoveryWeekCount > 0 {
        p.startNote = L.s("\(priorRaceName) 다음 주부터 이어집니다 · 회복 \(recoveryWeekCount)주 포함 \(planTotalWeeks)주",
                          "Continues after \(priorRaceName) · \(planTotalWeeks) weeks incl. \(recoveryWeekCount)-wk recovery")
    }

    // 롱런 게이지 왼쪽 값: 앞 대회가 있으면 그 대회의 peakLong (회복 구간은 의도적 저하)
    p.startingLongKm = recoveryWeekCount > 0 ? recoveryPriorLong : planStartLong

    var peakLong = planStartLong
    var peakVol = planStartVol           // 누적 최대 주간거리 — 회복주/테이퍼 주가 낮추면 안 된다
    var currentBuildVol = planStartVol   // 매 빌드주 +5%로 유기적 증가
    var longNow = peakLong
    var seenVolRecord = false            // 12개월 최대 주간거리를 처음 넘는 주 — 한 번만 표시
    var forceRecovery = false            // 하프 튠업 다음 주는 회복 주

    // 마라톤 후 회복 3주와 30/50/70% 는 관행이다. 하프 1주(60/70%)는 임의로 정함.
    // 통제된 연구를 찾지 못했다. 근거가 나오면 바꿀 것.
    if recoveryWeekCount > 0 {
        let rPcts: [(l: Double, v: Double)] = recoveryWeekCount >= 3
            ? [(0.25, 0.30), (0.40, 0.50), (0.60, 0.70)]
            : [(0.60, 0.70)]
        for r in 0..<recoveryWeekCount {
            let ri   = r + 1
            guard let mon = cal.date(byAdding: .weekOfYear, value: r, to: monday0) else { continue }
            let lr   = (recoveryPriorLong * rPcts[r].l * 10).rounded() / 10
            let wkV  = (recoveryPriorVol  * rPcts[r].v * 10).rounded() / 10
            let mins = lr * (easyPaceSecPerKm ?? 420) / 60.0
            let n    = max(Int(runsPerWeek.rounded()), 2)
            let rest = max(wkV - lr, 0)
            let each = rest / Double(max(n - 1, 1))
            let bk   = each >= 1.5
                ? String(format: L.s("롱런 %.0fkm + 이지 %.0fkm × %d회", "Long run %.0fkm + Easy %.0fkm × %dx"), lr, each, max(n-1, 1))
                : String(format: L.s("롱런 %.0fkm + 이지 %d회", "Long run %.0fkm + Easy %dx"), lr, max(n-1, 1))
            p.weeks.append(MRPlanWeek(idx: ri, monday: mon, phase: "회복",
                                      longRunKm: lr, longRunMin: mins.rounded(),
                                      weeklyKm: wkV, projectedMin: p.projectedNow,
                                      isNewMax: false, breakdown: bk))
        }
    }

    // 회복 주가 있으면 주 4부터 시작 (stride는 loopStart > planTotalWeeks면 자동 비어 있음)
    let loopStart = 1 + recoveryWeekCount
    for i in stride(from: loopStart, through: planTotalWeeks, by: 1) {
        guard let mon = cal.date(byAdding: .weekOfYear, value: i - 1, to: monday0) else { continue }
        var lr = 0.0, wkVol = 0.0, phase = "", newMax = false, recovery = false

        // 이 주(월~일)에 들어오는 튠업 대회. 0 없음 · 1 단거리(5K·10K) · 2 하프
        let weekEnd = cal.date(byAdding: .day, value: 7, to: mon) ?? mon
        let tune = tuneUps.first { $0.date >= mon && $0.date < weekEnd }
        let tuneKind = tune.map { $0.distanceM >= MRDistance.dH ? 2 : 1 } ?? 0
        if let t = tune { p.absorbedTuneUpDates.append(t.date) }
        // 다음 주에 자기 계획이 있는 단거리 대회가 있는가 → 이번 주는 그 대회의 테이퍼에 양보
        // ("이미 계획을 세워 둔 대회 = 사용자가 신경 쓰는 대회"로 해석. 입력 없이 우선순위를 추론한다.)
        let nextWeekEnd = cal.date(byAdding: .day, value: 14, to: mon) ?? weekEnd
        let preTune = tune == nil ? tuneUps.first {
            $0.hasOwnPlan && $0.distanceM < MRDistance.dH && $0.date >= weekEnd && $0.date < nextWeekEnd
        } : nil

        if i <= buildWeeks {
            // 빌드 사이클을 회복 주 수만큼 오프셋해야 첫 빌드 주가 다운 주가 되지 않는다
            recovery = ((i - recoveryWeekCount) % cycleLen == 0) || forceRecovery
            forceRecovery = false
            if preTune != nil {
                // 단거리 대회 전 주 — 그 대회 독립 계획의 1주 테이퍼와 같은 값 (롱런 65% · 주간 50%). 진행 멈춤.
                lr = peakLong * 0.65
                phase = "대회 주"
                wkVol = currentBuildVol * 0.50
            } else if tuneKind == 2 {
                // 하프 튠업: 대회가 이번 주 롱런. 롱런 진행은 멈추고 다음 주는 회복.
                lr = MRDistance.dH / 1000.0
                phase = "대회 주"
                wkVol = currentBuildVol * MR_TUNEUP_HALF_VOL
                forceRecovery = true
            } else if recovery {
                lr = peakLong * 0.65
                phase = tuneKind == 1 ? "대회 주" : "회복"
                wkVol = currentBuildVol * 0.75
            } else {
                lr = min(peakLong * (1 + stepPct), p.targetLongKm)
                peakLong = max(peakLong, lr)
                newMax = lr > longNow + 0.5
                let atLongRunCap = !newMax && lr >= p.targetLongKm - 0.1
                // 하프 이상 후반(75%~) → "대회 페이스" (상한 도달 여부와 무관)
                //   5K·10K 제외 — 근거(Fokkema 2020)가 하프·풀에 한정된다.
                // 롱런이 상한에 닿아 더 이상 안 늘어난다 → "유지"
                // 아직 증가 중 → "늘리기"
                if distanceM >= MRDistance.dH && Double(i) > Double(buildWeeks) * 0.75 {
                    phase = "대회 페이스"
                } else if atLongRunCap {
                    phase = "유지"
                } else {
                    phase = "늘리기"
                }
                currentBuildVol = min(currentBuildVol * 1.05, volCap)
                wkVol = currentBuildVol
                peakVol = max(peakVol, wkVol)    // 회복주는 최대치를 낮추지 않는다
                if tuneKind == 1 {
                    // 5K·10K 튠업: 롱런은 유지(대회 이틀 뒤), 주간 거리만 줄인다. 진행(currentBuildVol)은 계속.
                    phase = "대회 주"
                    wkVol = currentBuildVol * MR_TUNEUP_SHORT_VOL
                }
            }
            longNow = max(longNow, lr)
        } else {
            let k = i - buildWeeks
            // 지수적 감소, 2주 평균 감량 ≈ 50% (Bosquet 최적 41–60%의 중앙)
            let mult = p.taperWeeks == 1 ? 0.50 : (k == 1 ? 0.62 : 0.38)
            lr = peakLong * (k == 1 ? 0.65 : 0.40)
            wkVol = peakVol * mult
            phase = "테이퍼"
        }

        // ⚠ 그 주의 볼륨을 예측에 넣으면 **회복주와 테이퍼 주에 예측이 후퇴한다.**
        //   회복주는 후퇴가 아니다 — 몸이 좋아지는 것은 뛸 때가 아니라 쉴 때다.
        //   그날 몸에 남아 있는 것은 **축적된 상태**이지 그 주에 뛴 양이 아니다.
        let projVol = peakVol
        // 풀은 durability 지수, 하프 이하는 등가에서 직접 — mrProjectedRefMin 한 곳에서 계산
        var proj = mrProjectedRefMin(halfEquivMin: halfEquivMin, distanceM: distanceM,
                                     weeklyKm: projVol, longestKm: peakLong,
                                     finishes: profile.marathonFinishes)
        if phase == "테이퍼" {
            let k = Double(i - buildWeeks)
            proj *= (1 - MR_TAPER_GAIN * (k / Double(max(p.taperWeeks, 1))))
        }
        // ⚠ 주차별 예상에도 레이스 기온 환산을 적용한다.
        //   최종 예상(projectedFinal)과 같은 기준이어야 마지막 주와 일치한다.
        if heat.ok { proj = heat.fromRef(timeRefMin: proj, tempC: raceTempC) }

        let mins = lr * (easyPaceSecPerKm ?? 420) / 60.0
        let n = max(Int(runsPerWeek.rounded()), 2)
        let others = max(n - 1, 1)
        // 표시값 기준으로 역산 — "롱런 A + 이지 B × N = 주간" 합산이 일치하도록
        let lrDisplay = lr.rounded()
        let wkDisplay = (wkVol * 10).rounded() / 10
        let each = max(wkDisplay - lrDisplay, 0) / Double(others)
        // ⚠ 테이퍼 주는 볼륨만 줄인다 — 강도·빈도 유지가 핵심(Bosquet 2007).
        //   "이지 1km × 3회" 같은 숫자는 의미 없고 오히려 혼란스럽다.
        let eachStr: String = {
            if each == each.rounded() { return String(format: "%.0fkm", each) }
            return String(format: "%.1fkm", each)
        }()
        var breakdown = each >= 1.5
            ? L.s("롱런 \(Int(lrDisplay))km + 이지 \(eachStr) × \(others)회",
                  "Long run \(Int(lrDisplay))km + Easy \(eachStr) × \(others)x")
            : String(format: L.s("롱런 %.0fkm + 이지 %d회", "Long run %.0fkm + Easy %dx"), lrDisplay, others)
        if phase == "테이퍼" {
            breakdown = String(format: L.s("롱런 %.0fkm + 짧게 %d회 · 강도는 그대로",
                                           "Long run %.0fkm + Short %dx · Keep the intensity"), lrDisplay, others)
        }
        if phase == "대회 페이스" {
            // ⚠ 페이스는 기온·테이퍼 보정 전 예측값. 훈련은 대회 기온에서 하지 않는다.
            let racePace = mrTrainingRacePaceSecPerKm(
                halfEquivMin: halfEquivMin, distanceM: distanceM,
                weeklyKm: projVol, longestKm: peakLong, finishes: profile.marathonFinishes)
            let seg = mrRacePaceSegmentMinutes(longRunMin: mins.rounded())   // 저장값(longRunMin)과 동일 기준
            let paceStr = mrFormatPace(racePace) + "/km"
            breakdown = each >= 1.5
                ? L.s("롱런 \(Int(lrDisplay))km · 마지막 \(seg)분은 \(paceStr) + 이지 \(eachStr) × \(others)회",
                      "Long run \(Int(lrDisplay))km · last \(seg) min at \(paceStr) + Easy \(eachStr) × \(others)x")
                : L.s("롱런 \(Int(lrDisplay))km · 마지막 \(seg)분은 \(paceStr) + 이지 \(others)회",
                      "Long run \(Int(lrDisplay))km · last \(seg) min at \(paceStr) + Easy \(others)x")
        }
        if let pt = preTune, i <= buildWeeks {
            let label = mrLabelFor(distanceM: pt.distanceM)
            breakdown = String(format: L.s("%@ 대회 전 주 — 롱런 %.0fkm + 짧게 %d회 · 강도는 그대로",
                                           "Week before %@ race — Long run %.0fkm + Short %dx · Keep the intensity"),
                               label, lrDisplay, others)
        }
        if let t = tune {
            let label = mrLabelFor(distanceM: t.distanceM)
            if i > buildWeeks {
                // 테이퍼 안의 튠업: 테이퍼는 그대로, 대회는 가볍게
                breakdown += L.s(" · \(label) 대회는 가볍게", " · \(label) race, take it easy")
            } else if tuneKind == 2 {
                let m = max(n - 1, 1)
                breakdown = L.s("하프 대회 (이번 주 롱런) + 이지 \(m)회 · 앞 5~7일 볼륨 −30%",
                                "Half race (this week's long run) + Easy \(m)x · volume −30% for 5–7 days before")
            } else {
                let m = max(n - 2, 0)
                breakdown = m > 0
                    ? L.s("\(label) 대회 + 롱런 \(Int(lrDisplay))km(대회 이틀 뒤) + 이지 \(m)회 · 대회 전 2~3일은 가볍게",
                          "\(label) race + Long run \(Int(lrDisplay))km (2 days after) + Easy \(m)x · easy 2–3 days before")
                    : L.s("\(label) 대회 + 롱런 \(Int(lrDisplay))km(대회 이틀 뒤) · 대회 전 2~3일은 가볍게",
                          "\(label) race + Long run \(Int(lrDisplay))km (2 days after) · easy 2–3 days before")
            }
        }
        // 12개월 최대 주간거리를 처음 초과하는 주를 표시 — 경고가 아니라 사실 전달
        var isVR = false
        // 상한에 처음 도달하는 주를 표시 — 넘어섰다는 게 아니라 닿았다는 사실 전달
        if !seenVolRecord && profile.maxWeeklyKm52w > 0 && wkVol >= profile.maxWeeklyKm52w - 0.5 {
            isVR = true
            seenVolRecord = true
            print(String(format: "[계획] W%d=%.0fkm ≥ 과거최대 %.0fkm → 상한 도달",
                         i, wkVol, profile.maxWeeklyKm52w))
        }

        p.weeks.append(MRPlanWeek(idx: i, monday: mon, phase: phase,
                                  longRunKm: (lr * 10).rounded() / 10,
                                  longRunMin: mins.rounded(),
                                  weeklyKm: (wkVol * 10).rounded() / 10,
                                  projectedMin: proj, isNewMax: newMax,
                                  isVolRecord: isVR,
                                  breakdown: breakdown))
    }

    p.reachableLongKm = peakLong
    p.peakWeeklyKm = peakVol
    p.histMaxWeeklyKm = profile.maxWeeklyKm52w

    // 튠업 고지 — 판단이 아니라 결과 전달
    let halfAbsorbed = tuneUps.filter { t in
        t.distanceM >= MRDistance.dH && p.absorbedTuneUpDates.contains(t.date)
    }.count
    if halfAbsorbed > 0 {
        p.notes.append(L.s("하프 대회 주와 그다음 회복 주에는 롱런이 늘지 않습니다. 목표 롱런 도달이 \(2 * halfAbsorbed)주 늦어집니다.",
                           "The half-race week and the recovery week after it don't advance the long run. Reaching the target long run is delayed by \(2 * halfAbsorbed) weeks."))
    }
    var raceRun = 0, maxRaceRun = 0
    for w in p.weeks {
        if w.phase == "대회 주" { raceRun += 1; maxRaceRun = max(maxRaceRun, raceRun) } else { raceRun = 0 }
    }
    if maxRaceRun >= 3 {
        p.notes.append(L.s("대회가 \(maxRaceRun)주 연속입니다. 그 구간은 훈련 자극이 거의 없습니다.",
                           "\(maxRaceRun) consecutive race weeks — almost no training stimulus in that stretch."))
    }
    print(String(format: "[계획] 과거12개월 최대주간 = %.1fkm", profile.maxWeeklyKm52w))
    if profile.maxWeeklyKm52w > 0 {
        p.notes.append(String(format: L.s("주간 거리는 지난 1년 최고치(%.0fkm)까지 올립니다. 그 이상은 아직 해보신 적이 없습니다.",
                                          "Weekly distance will reach your 1-yr high (%.0f km). You haven't gone beyond this before."),
                             profile.maxWeeklyKm52w))
    }
    if distanceM >= MRDistance.dF {
        let bResult = bMarathonModel(weeklyKm: peakVol, longestKm: peakLong,
                                     finishes: profile.marathonFinishes)
        var finalRef = mrProjectedRefMin(halfEquivMin: halfEquivMin, distanceM: distanceM,
                                         weeklyKm: peakVol, longestKm: peakLong,
                                         finishes: profile.marathonFinishes) * (1 - MR_TAPER_GAIN)
        if heat.ok { finalRef = heat.fromRef(timeRefMin: finalRef, tempC: raceTempC) }
        p.projectedFinal = finalRef
        // 불확실성 구간 — 데이터에서 잰 체력 변동성 + 모델 오차
        // σ₈: 최근 12개월 노력 시계열에서 잰 8주 기준 로그 변동성 (mrProfile 계산)
        // 모델 오차(extraSD)는 b-공간 → log(시간)-공간으로 변환해 결합
        func hm(_ m: Double) -> String {
            let t = Int(m.rounded()); return "\(t/60):\(String(format: "%02d", t%60))"
        }
        // d²=a+b·T 분해 적용: sigmaFitSq = a + b·T (T=totalWeeks)
        let sigmaFitSq = profile.sigma8A + profile.sigma8B * Double(totalWeeks)
        if sigmaFitSq > 0 {
            let logSigmaModel = bResult.extraSD * log(2.0)
            let logSigmaTotal = sqrt(sigmaFitSq + logSigmaModel * logSigmaModel)
            let pct = (exp(logSigmaTotal) - 1) * 100
            // 10% 는 "이 폭을 넘으면 숫자로 보여줄 가치가 없다"는
            // 표시 기준이다. 모델에서 나온 값이 아니다.
            // 12% 로 올리면 JTBC(±10.9%대)가 숫자 구간을 표시하게 된다.
            if pct <= 10.0 {
                p.projectedFinalLo = finalRef * exp(-logSigmaTotal)
                p.projectedFinalHi = finalRef * exp(+logSigmaTotal)
                print(String(format: "[예측] %d주 → ±%.1f%% · %@ (%@~%@)",
                             totalWeeks, pct,
                             mrFormatDisplay(finalRef), hm(p.projectedFinalLo), hm(p.projectedFinalHi)))
            } else {
                let months = max(1, totalWeeks / 4)
                p.projectedFinalNote = L.isEnglish
                    ? String(format: "Race is %d months away — prediction is wide (±%.0f%%). It will narrow as you race more.", months, pct)
                    : String(format: "%d개월 뒤라 예측 폭이 매우 넓습니다 (±%.0f%%). 대회를 치를수록 좁아집니다.", months, pct)
                print(String(format: "[예측] %d주 → ±%.1f%% → 표시 기준(10%%) 초과, 문장으로 대체", totalWeeks, pct))
            }
        } else {
            p.projectedFinalNote = L.s("최근 기록이 적어 예측 폭을 계산하지 못했습니다",
                                       "Not enough recent data to calculate the prediction range")
            print(String(format: "[예측] %d주 → σ8 계산 불가", totalWeeks))
        }
    } else {
        var finalRef = mrProjectedRefMin(halfEquivMin: halfEquivMin, distanceM: distanceM,
                                         weeklyKm: peakVol, longestKm: peakLong,
                                         finishes: profile.marathonFinishes) * (1 - MR_TAPER_GAIN)
        if heat.ok { finalRef = heat.fromRef(timeRefMin: finalRef, tempC: raceTempC) }
        p.projectedFinal = finalRef
    }

    let ratio = peakLong / max(p.targetLongKm, 1)
    if distanceM >= MRDistance.dF {
        p.verdict = ratio >= 0.95 ? "기록 목표 가능"
                  : ratio >= 0.78 ? "완주는 충분, 기록은 다음 대회에"
                                  : "완주 중심 권장"
        if ratio < 0.78 {
            p.notes.append(L.s(
                "\(planTotalWeeks)주로는 롱런이 \(Int(peakLong))km까지밖에 못 올라갑니다. 근거가 있는 하한(28km)까지 가려면 \(mrWeeksToReach(from: max(profile.longestRun16wKm, 5), to: p.targetLongKm, step: stepPct, cycle: cycleLen))주가 필요합니다.",
                "In \(planTotalWeeks) weeks, the long run can only reach \(Int(peakLong)) km. Reaching the evidence-based minimum (28 km) requires \(mrWeeksToReach(from: max(profile.longestRun16wKm, 5), to: p.targetLongKm, step: stepPct, cycle: cycleLen)) weeks."
            ))
        }
    } else {
        let need = distanceM / 1000.0
        if peakLong >= p.targetLongKm * 0.95 {
            p.verdict = "가능"
        } else if peakLong >= need * 0.6 {
            p.verdict = "완주 중심 권장"
        } else {
            p.verdict = "준비 기간이 짧습니다"
            p.notes.append(L.s(
                "\(planTotalWeeks)주로는 롱런이 \(Int(peakLong))km까지입니다. \(Int(need))km 완주를 편하게 하려면 최소 \(Int(need * 0.6))km는 소화해 두는 편이 좋습니다.",
                "In \(planTotalWeeks) weeks, the long run reaches \(Int(peakLong)) km. To finish \(Int(need)) km comfortably, reaching at least \(Int(need * 0.6)) km first is recommended."
            ))
        }
    }
    return p
}

func mrWeeksToReach(from start: Double, to target: Double,
                    step: Double, cycle: Int) -> Int {
    guard target > start else { return 0 }
    let n = ceil(log(target / start) / log(1 + step))
    return Int(ceil(n * Double(cycle) / Double(cycle - 1)))
}

// MARK: - 대회 페이스 구간 (롱런 후반)
//
// ⚠ "롱런 마지막 15분을 대회 페이스로"는 코칭 관행이다.
//   Fokkema 2020·Van Hooren 2024 어디에도 없고 통제 연구를 찾지 못했다.
//   근거가 나오면 바꿀 것.
// ⚠ 15분은 자료의 예시값. 임의로 정함. 롱런이 60분 미만이면 10분.

func mrRacePaceSegmentMinutes(longRunMin: Double) -> Int {
    longRunMin < 60 ? 10 : 15
}

/// 훈련용 대회 페이스 (초/km).
///
/// ⚠ 예측 기록 기준이다. 목표 기록이 아니다 — 목표가 예측보다 빠르면
///   D-day 카드가 경고하는 바로 그 과속 배분이 된다.
/// ⚠ 기온 보정 전 · 테이퍼 이득 전 값이다. 훈련은 대회 기온에서 하지 않는다.
func mrTrainingRacePaceSecPerKm(halfEquivMin: Double, distanceM: Double,
                                weeklyKm: Double, longestKm: Double, finishes: Int) -> Double {
    guard distanceM > 0 else { return 0 }
    let minutes = mrProjectedRefMin(halfEquivMin: halfEquivMin, distanceM: distanceM,
                                    weeklyKm: weeklyKm, longestKm: longestKm, finishes: finishes)
    return minutes * 60.0 / (distanceM / 1000.0)
}

// MARK: - 기준 예측 시간 (단일 공식)

/// 기준 예측 시간(분) — 기온 보정 전 · 테이퍼 이득 전.
/// 풀은 마라톤 지수(bMarathonModel), 하프 이하는 Riegel 지수 1.06.
/// ⚠ 1.06 — Vickers & Vertosick 2016에서 10K·하프에 잘 교정된 값(MRFormulas.swift bMarathonModel 주석 참조).
///   MRPredictor의 개인 지수 prior와 같다.
/// projectedNow · 주차별 projectedMin · projectedFinal · 훈련용 대회 페이스가 모두 이 함수를 쓴다.
func mrProjectedRefMin(halfEquivMin: Double, distanceM: Double,
                       weeklyKm: Double, longestKm: Double, finishes: Int) -> Double {
    if distanceM >= MRDistance.dF {
        return halfEquivMin * pow(2.0, bMarathonModel(weeklyKm: weeklyKm,
                                                       longestKm: longestKm,
                                                       finishes: finishes).b)
    }
    return halfEquivMin * pow(distanceM / MRDistance.dH, 1.06)
}
