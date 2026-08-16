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
func mrBuildPlan(raceDate: Date,
                 distanceM: Double,
                 today: Date,
                 profile: MRProfile,
                 halfEquivMin: Double,
                 easyPaceSecPerKm: Double?,
                 heat: MRHeatModel,
                 raceTempC: Double,
                 runsPerWeek: Double = 3.0,
                 priorRace: (date: Date, name: String, peakLong: Double, peakVol: Double)? = nil) -> MRRacePlan? {

    let cal = Calendar.current
    let totalDays = cal.dateComponents([.day], from: cal.startOfDay(for: today),
                                       to: cal.startOfDay(for: raceDate)).day ?? 0
    let totalWeeks = totalDays / 7
    guard totalWeeks >= 3 else { return nil }
    // ⚠ 하프 등가가 없으면 예측이 성립하지 않는다.
    //   0을 그리면 "0분 00초에 완주"라는 말이 되어 신뢰가 통째로 무너진다.
    //   계획을 아예 만들지 않고, 화면은 그 대회를 조용히 건너뛴다.
    guard halfEquivMin > 10 else { return nil }
    // 완전 입문자(주간 5km 미만 + 최근 30일 최장 3km 미만)에게는 계획을 내놓지 않는다.
    // 플래너의 목적은 "지금 뛸 수 있는가"가 아니라 "여기까지 쌓을 수 있는가"이므로
    // 롱런 35% 하한선은 쓰지 않는다 — 훈련으로 도달할 수 있는 사람의 계획까지 없애기 때문.
    if profile.weeklyKm4w < 5 && profile.longestRun30d < 3 { return nil }
    if distanceM >= MRDistance.dF && profile.weeklyKm4w < 15 { return nil }

    var p = MRRacePlan(raceDate: raceDate, distanceM: distanceM)
    p.taperWeeks = distanceM >= MRDistance.dH ? 2 : 1
    let stepPct = 0.10
    let cycleLen = 4                    // 3주 부하 + 1주 회복
    p.targetLongKm = distanceM >= MRDistance.dF ? 28.0 : 21.0

    // '지금 상태로 나가면' — 거리별로 다르게 계산한다.
    // 풀만 durability 지수를 쓰고, 하프 이하는 하프 등가에서 직접 환산한다.
    if distanceM >= MRDistance.dF {
        p.projectedNow = halfEquivMin * pow(2.0, bMarathonModel(
            weeklyKm: profile.weeklyKm4w,
            longestKm: profile.longestRun16wKm,
            finishes: profile.marathonFinishes).b)
    } else {
        p.projectedNow = halfEquivMin * pow(distanceM / MRDistance.dH, 1.06)
    }
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
    let neededTotal  = simulateNeeded(fromLong: simStartLong, fromVol: simStartVol) + p.taperWeeks

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

    if let prior = priorRace, prior.date > today, prior.date < raceDate {
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
        // 빌드 루프는 회복 3주 이후 상태(롱런 60%, 주간 70%)에서 시작
        planStartLong = pLong * 0.60
        planStartVol  = pVol  * 0.70
        p.startDate   = planToday

        recoveryPriorLong = pLong
        recoveryPriorVol  = pVol
        recoveryWeekCount = 3
        priorRaceName     = prior.name
        p.bridgeRows      = []   // 빈 기간이 없으므로 타임라인 불필요
        #if DEBUG
        print("[계획] \(raceDate.formatted(date:.abbreviated,time:.omitted)) · \(prior.name) 다음 주 시작")
        #endif
    } else if neededTotal < totalWeeks {
        // 앞 대회 없음 — 대회일에서 필요 기간만큼 역산해 시작
        guard let deferredStart = cal.date(byAdding: .day, value: -(neededTotal * 7), to: raceDate) else { return nil }
        planToday   = deferredStart
        p.startDate = deferredStart

        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR"); df.dateFormat = "yyyy-MM-dd"
        p.startNote = "이 계획은 \(neededTotal)주짜리입니다. \(df.string(from: deferredStart))에 시작합니다."
        let waitEnd = cal.date(byAdding: .day, value: -1, to: deferredStart) ?? deferredStart
        p.bridgeRows = [
            ("\(sfmt(today)) ~ \(sfmt(waitEnd))", "유지 — 지금처럼 달리시면 됩니다"),
            ("\(sfmt(deferredStart)) ~", "이 계획 시작")
        ]
        #if DEBUG
        print("[계획] \(raceDate.formatted(date:.abbreviated,time:.omitted)) 역산=\(neededTotal)주 · \(df.string(from: deferredStart)) 시작 (대기 \(totalWeeks - neededTotal)주)")
        #endif
    }

    // ── 기준 월요일(monday0) ──────────────────────────────────────────
    // 일반(오늘 기준): 이번 주 월요일로 역산.
    //   · 화요일에 앱을 열어도 이번 주 1주차가 유지된다.
    //   · 월요일이면 daysSinceMon = 0 이라 그대로.
    // defer/prior race: planToday(미래 날짜)의 다음 월요일 — 역산하지 않음.
    let monday0: Date
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

    // 계획 기간 계산
    // 일반: monday0 기준 → 주 안에서 날짜가 바뀌어도 총 주 수가 변하지 않는다.
    // defer/prior race: planToday 기준 — monday0이 planToday보다 늦으면 주 수가 줄기 때문.
    let planRef = (planToday == today && recoveryWeekCount == 0) ? monday0 : planToday
    let planDays = cal.dateComponents([.day], from: cal.startOfDay(for: planRef),
                                       to: cal.startOfDay(for: raceDate)).day ?? 0
    let planTotalWeeks = planDays / 7
    // 회복 주가 있으면 그만큼 더 필요 (최소 build 1주 + taperWeeks + recoveryWeekCount)
    guard planTotalWeeks >= 3 + recoveryWeekCount else { return nil }
    let buildWeeks = planTotalWeeks - p.taperWeeks

    // 앞 대회 있을 때 startNote — planTotalWeeks 를 알아야 총 주 수 표시 가능
    if recoveryWeekCount > 0 {
        p.startNote = "\(priorRaceName) 다음 주부터 이어집니다 · 회복 \(recoveryWeekCount)주 포함 \(planTotalWeeks)주"
    }

    // 롱런 게이지 왼쪽 값: 앞 대회가 있으면 그 대회의 peakLong (회복 구간은 의도적 저하)
    p.startingLongKm = recoveryWeekCount > 0 ? recoveryPriorLong : planStartLong

    var peakLong = planStartLong
    var peakVol = planStartVol           // 누적 최대 주간거리 — 회복주/테이퍼 주가 낮추면 안 된다
    var currentBuildVol = planStartVol   // 매 빌드주 +5%로 유기적 증가
    var longNow = peakLong
    var seenVolRecord = false            // 12개월 최대 주간거리를 처음 넘는 주 — 한 번만 표시

    // 마라톤 후 회복 3주와 30/50/70% 는 관행이다.
    // 통제된 연구를 찾지 못했다. 근거가 나오면 바꿀 것.
    if recoveryWeekCount > 0 {
        let rPcts: [(l: Double, v: Double)] = [(0.25, 0.30), (0.40, 0.50), (0.60, 0.70)]
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
                ? String(format: "롱런 %.0fkm + 이지 %.0fkm × %d회", lr, each, max(n-1, 1))
                : String(format: "롱런 %.0fkm + 이지 %d회", lr, max(n-1, 1))
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

        if i <= buildWeeks {
            // 빌드 사이클을 회복 주 수만큼 오프셋해야 첫 빌드 주가 다운 주가 되지 않는다
            recovery = ((i - recoveryWeekCount) % cycleLen == 0)
            if recovery {
                lr = peakLong * 0.65
                phase = "회복"
                wkVol = currentBuildVol * 0.75
            } else {
                lr = min(peakLong * (1 + stepPct), p.targetLongKm)
                peakLong = max(peakLong, lr)
                newMax = lr > longNow + 0.5
                let atLongRunCap = !newMax && lr >= p.targetLongKm - 0.1
                // 풀마라톤 후반(75%~) → "대회 페이스" (상한 도달 여부와 무관)
                // 롱런이 상한에 닿아 더 이상 안 늘어난다 → "유지"
                // 아직 증가 중 → "늘리기"
                if distanceM >= MRDistance.dF && Double(i) > Double(buildWeeks) * 0.75 {
                    phase = "대회 페이스"
                } else if atLongRunCap {
                    phase = "유지"
                } else {
                    phase = "늘리기"
                }
                currentBuildVol = min(currentBuildVol * 1.05, volCap)
                wkVol = currentBuildVol
                peakVol = max(peakVol, wkVol)    // 회복주는 최대치를 낮추지 않는다
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
        var proj: Double
        if distanceM >= MRDistance.dF {
            proj = halfEquivMin * pow(2.0, bMarathonModel(
                weeklyKm: projVol, longestKm: peakLong,
                finishes: profile.marathonFinishes).b)
        } else {
            // 하프 이하는 durability 항이 지배하지 않는다 — 등가에서 직접
            proj = halfEquivMin * pow(distanceM / MRDistance.dH, 1.06)
        }
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
            ? "롱런 \(Int(lrDisplay))km + 이지 \(eachStr) × \(others)회"
            : String(format: "롱런 %.0fkm + 이지 %d회", lrDisplay, others)
        if phase == "테이퍼" {
            breakdown = String(format: "롱런 %.0fkm + 짧게 %d회 · 강도는 그대로", lrDisplay, others)
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
    print(String(format: "[계획] 과거12개월 최대주간 = %.1fkm", profile.maxWeeklyKm52w))
    if profile.maxWeeklyKm52w > 0 {
        p.notes.append(String(format: "주간 거리는 지난 1년 최고치(%.0fkm)까지 올립니다. 그 이상은 아직 해보신 적이 없습니다.", profile.maxWeeklyKm52w))
    }
    if distanceM >= MRDistance.dF {
        let bResult = bMarathonModel(weeklyKm: peakVol, longestKm: peakLong,
                                     finishes: profile.marathonFinishes)
        var finalRef = halfEquivMin * pow(2.0, bResult.b) * (1 - MR_TAPER_GAIN)
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
                p.projectedFinalNote = String(format: "%d개월 뒤라 예측 폭이 매우 넓습니다 (±%.0f%%). 대회를 치를수록 좁아집니다.", months, pct)
                print(String(format: "[예측] %d주 → ±%.1f%% → 표시 기준(10%%) 초과, 문장으로 대체", totalWeeks, pct))
            }
        } else {
            p.projectedFinalNote = "최근 기록이 적어 예측 폭을 계산하지 못했습니다"
            print(String(format: "[예측] %d주 → σ8 계산 불가", totalWeeks))
        }
    } else {
        var finalRef = halfEquivMin * pow(distanceM / MRDistance.dH, 1.06) * (1 - MR_TAPER_GAIN)
        if heat.ok { finalRef = heat.fromRef(timeRefMin: finalRef, tempC: raceTempC) }
        p.projectedFinal = finalRef
    }

    let ratio = peakLong / max(p.targetLongKm, 1)
    if distanceM >= MRDistance.dF {
        p.verdict = ratio >= 0.95 ? "기록 목표 가능"
                  : ratio >= 0.78 ? "완주는 충분, 기록은 다음 대회에"
                                  : "완주 중심 권장"
        if ratio < 0.78 {
            p.notes.append("\(planTotalWeeks)주로는 롱런이 \(Int(peakLong))km까지밖에 못 올라갑니다. "
                           + "근거가 있는 하한(28km)까지 가려면 "
                           + "\(mrWeeksToReach(from: max(profile.longestRun16wKm, 5), to: p.targetLongKm, step: stepPct, cycle: cycleLen))주가 필요합니다.")
        }
    } else {
        let need = distanceM / 1000.0
        if peakLong >= p.targetLongKm * 0.95 {
            p.verdict = "가능"
        } else if peakLong >= need * 0.6 {
            p.verdict = "완주 중심 권장"
        } else {
            p.verdict = "준비 기간이 짧습니다"
            p.notes.append("\(planTotalWeeks)주로는 롱런이 \(Int(peakLong))km까지입니다. "
                           + "\(Int(need))km 완주를 편하게 하려면 최소 \(Int(need * 0.6))km는 소화해 두는 편이 좋습니다.")
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
