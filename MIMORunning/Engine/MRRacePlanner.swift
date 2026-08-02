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
    var projectedNow = 0.0
    var projectedFinal = 0.0
    var verdict = ""
    var notes: [String] = []
    var taperWeeks = 2
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
/// · 목표 롱런 25km — Fokkema 2020이 유의하게 보고한 것은 "<25km" 하나뿐.
///   "30–35km 최적"은 논문에 없다. 32km를 요구하면 도달 불가능한 목표를
///   세우고 그걸 '부족'으로 표시하게 된다.
func mrBuildPlan(raceDate: Date,
                 distanceM: Double,
                 today: Date,
                 profile: MRProfile,
                 halfEquivMin: Double,
                 easyPaceSecPerKm: Double?,
                 heat: MRHeatModel,
                 raceTempC: Double,
                 runsPerWeek: Double = 3.0) -> MRRacePlan? {

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
    p.targetLongKm = distanceM >= MRDistance.dF ? 25.0 : 21.0

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

    let buildWeeks = totalWeeks - p.taperWeeks
    let vol = max(profile.weeklyKm4w, 10.0)
    let volPeak = min(vol * 1.35, 60.0)

    var peakLong = max(profile.longestRun16wKm, 5.0)
    var peakVol = vol                    // 누적 최대 주간거리 — 회복주/테이퍼 주가 낮춰선 안 된다
    var longNow = peakLong
    let offset = (7 - cal.component(.weekday, from: today) + 2) % 7
    let monday0 = cal.date(byAdding: .day, value: offset == 0 ? 7 : offset,
                           to: cal.startOfDay(for: today))!

    for i in 1...totalWeeks {
        let mon = cal.date(byAdding: .weekOfYear, value: i - 1, to: monday0)!
        var lr = 0.0, wkVol = 0.0, phase = "", newMax = false, recovery = false

        if i <= buildWeeks {
            recovery = (i % cycleLen == 0)
            if recovery {
                lr = peakLong * 0.65
                phase = "회복"
            } else {
                lr = min(peakLong * (1 + stepPct), p.targetLongKm)
                peakLong = max(peakLong, lr)
                newMax = lr > longNow + 0.5
                phase = Double(i) <= Double(buildWeeks) * 0.35 ? "기초"
                      : Double(i) <= Double(buildWeeks) * 0.75 ? "구축" : "특이"
            }
            longNow = max(longNow, lr)
            wkVol = vol + (volPeak - vol) * min(1.0, Double(i) / Double(max(buildWeeks, 1)))
            if recovery {
                wkVol *= 0.75
            } else {
                peakVol = max(peakVol, wkVol)    // 회복주는 최대치를 낮추지 않는다
            }
        } else {
            let k = i - buildWeeks
            // 지수적 감소, 2주 평균 감량 ≈ 50% (Bosquet 최적 41–60%의 중앙)
            let mult = p.taperWeeks == 1 ? 0.50 : (k == 1 ? 0.62 : 0.38)
            lr = peakLong * (k == 1 ? 0.65 : 0.40)
            wkVol = volPeak * mult
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
        let rest = max(wkVol - lr, 0)
        let others = max(n - 1, 1)
        let each = rest / Double(others)
        // ⚠ 테이퍼 주는 볼륨만 줄인다 — 강도·빈도 유지가 핵심(Bosquet 2007).
        //   "이지 1km × 3회" 같은 숫자는 의미 없고 오히려 혼란스럽다.
        var breakdown = each >= 1.5
            ? String(format: "롱런 %.0fkm + 이지 %.0fkm × %d회", lr, each, others)
            : String(format: "롱런 %.0fkm + 이지 %d회", lr, others)
        if phase == "테이퍼" {
            breakdown = String(format: "롱런 %.0fkm + 짧게 %d회 · 강도는 그대로", lr, others)
        }
        p.weeks.append(MRPlanWeek(idx: i, monday: mon, phase: phase,
                                  longRunKm: (lr * 10).rounded() / 10,
                                  longRunMin: mins.rounded(),
                                  weeklyKm: (wkVol * 10).rounded() / 10,
                                  projectedMin: proj, isNewMax: newMax,
                                  breakdown: breakdown))
    }

    p.reachableLongKm = peakLong
    var finalRef: Double
    if distanceM >= MRDistance.dF {
        finalRef = halfEquivMin * pow(2.0, bMarathonModel(
            weeklyKm: peakVol, longestKm: peakLong,
            finishes: profile.marathonFinishes).b)
    } else {
        finalRef = halfEquivMin * pow(distanceM / MRDistance.dH, 1.06)
    }
    finalRef *= (1 - MR_TAPER_GAIN)
    if heat.ok { finalRef = heat.fromRef(timeRefMin: finalRef, tempC: raceTempC) }
    p.projectedFinal = finalRef

    let ratio = peakLong / max(p.targetLongKm, 1)
    if distanceM >= MRDistance.dF {
        p.verdict = ratio >= 0.95 ? "기록 목표 가능"
                  : ratio >= 0.78 ? "완주는 충분, 기록은 다음 대회에"
                                  : "완주 중심 권장"
        if ratio < 0.78 {
            p.notes.append("\(totalWeeks)주로는 롱런이 \(Int(peakLong))km까지밖에 못 올라갑니다. "
                           + "근거가 있는 하한(25km)까지 가려면 "
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
            p.notes.append("\(totalWeeks)주로는 롱런이 \(Int(peakLong))km까지입니다. "
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
