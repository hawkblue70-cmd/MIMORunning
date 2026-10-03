import Foundation

// MARK: - 조언

struct MRAdvice: Identifiable {
    let id = UUID()
    let key: String
    let text: String
    let rationale: String       // 근거. UI에서 탭하면 보인다
    let grade: String           // A / B / C
    let gainMin: Double         // 기대 이득(분)
    let timeliness: Double      // 0~1
    let slot: String            // todayRun / weekly / raceCountdown
    /// 구체 운동 목록. 비어 있으면 UI에 목록을 그리지 않는다.
    var exercises: [String] = []

    /// 우선순위 = 근거등급 × √기대이득 × 시의성
    var score: Double {
        let w: Double = grade == "A" ? 3 : (grade == "B" ? 2 : 1)
        return w * max(gainMin, 0.1).squareRoot() * timeliness
    }
}

// MARK: - 레이스 보급 3종
//
// ⚠ 이전 버전은 "시간당 60g"이었는데 **한 구간 아래의 권고**였다.
//   ACSM/AND/DC 2016 합동 성명(MSSE 48(3):543–568):
//     1–2.5시간 → 30–60 g/h
//     2.5–3시간 초과 → **최대 90 g/h** + 복합 수송 탄수화물(포도당:과당)
//   Jeukendrup 2014 (Sports Med 44 Suppl 1:S25–33): 단일 당원은 SGLT1
//   포화로 ~60 g/h가 천장, 혼합 당으로 ~90 g/h.
//
// ⚠ 근거로 쓰던 두 논문도 오독이었다.
//   Clark 2019 (J Appl Physiol 127(3):726–736)는 **사이클링**, n=16,
//   측정한 것은 CP가 아니라 EP, 그리고 **60 g/h 한 용량만** 시험했다.
//   → "60이 충분하다"의 근거가 될 수 없다.
//   Rapoport 2010은 **레이스 전 글리코겐 로딩** 이야기이고, 원문은
//   그 경계의 러너에게 "strategically refuel during the race"라고 한다.
//   더 먹으라는 근거였는데 적게 먹어도 된다는 근거로 거꾸로 쓰고 있었다.

// ⚠ 2026-10-02 성장 탭에서 보급량 조언(fueling)을 뺐다 — 나 탭 대회 카드의 젤 보급 제안(MRGelPlan)이
//   같은 내용을 시간·km별로 보여 준다. 위 근거는 MRGelPlan·MRRaceDay가 그대로 쓴다.

/// 조언 문구 — 한국어·영어·일본어.
private func adv(_ ko: String, _ en: String, ja: String) -> String { AppLanguage.shared.s(ko, en, ja: ja) }

func mrGutTrainingAdvice(raceDate: Date, distanceM: Double,
                         projectedMin: Double, today: Date) -> MRAdvice? {
    let d = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today),
                                            to: Calendar.current.startOfDay(for: raceDate)).day ?? -1
    guard d >= 14, d <= 90, distanceM >= 20000, projectedMin >= 150 else { return nil }
    return MRAdvice(key: "gut",
        text: adv("목표 보급량은 레이스 당일 처음 시도하지 마세요. 지금 무리 없는 양에서 시작해 롱런에서 주 1회씩, 시간당 10g 정도로만 올리고 연습에서 도달한 만큼만 쓰세요. 메스꺼움이 오면 시간당 30g으로 낮추고 묽은 음료로 바꾸면 됩니다.", "Don't try your target fueling for the first time on race day. Start from an amount you handle easily, raise it about 10 g per hour once a week on long runs, and only use what you've reached in practice. If you feel nauseous, drop to 30 g per hour and switch to a more diluted drink.", ja: "目標の補給量をレース当日に初めて試さないでください。今無理なく摂れる量から始め、ロング走で週1回ずつ1時間あたり10gほどだけ増やし、練習で到達した量だけを使ってください。吐き気が出たら1時間あたり30gに下げ、薄めの飲み物に替えれば大丈夫です。"),
        rationale: adv("Jeukendrup 2017(지구성 선수 30~50%가 위장 문제) · Pugh 2018 n=96(레이스 중 중등도 증상 27%) · D-\(d)", "Jeukendrup 2017 (30–50% of endurance athletes have GI issues) · Pugh 2018 n=96 (27% moderate symptoms during races) · D-\(d)", ja: "Jeukendrup 2017(持久系選手の30~50%に胃腸の問題) · Pugh 2018 n=96(レース中に中等度の症状27%) · D-\(d)"),
        grade: "B", gainMin: 8, timeliness: 0.75, slot: "raceCountdown")
}

func mrHydrationAdvice(raceDate: Date, distanceM: Double,
                        projectedMin: Double, today: Date) -> MRAdvice? {
    let d = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today),
                                            to: Calendar.current.startOfDay(for: raceDate)).day ?? -1
    guard d >= 0, d <= 30, distanceM >= 20000, projectedMin >= 210 else { return nil }
    return MRAdvice(key: "hydration",
        text: adv("수분은 정해진 스케줄이 아니라 갈증에 따라 드세요. 4~5시간대 완주자는 과다 음수로 인한 운동관련 저나트륨혈증 위험군입니다. 2시간 넘는 레이스에서는 나트륨이 든 음료를 함께 쓰고, 젤은 반드시 물과 같이 삼키세요.", "Drink to thirst, not to a fixed schedule. 4–5 hour finishers are the risk group for exercise-associated hyponatremia from overdrinking. In races over 2 hours, use a sodium drink as well, and always take gels with water.", ja: "水分は決まったスケジュールではなく、のどの渇きに合わせて摂ってください。4~5時間台の完走者は、飲みすぎによる運動関連低ナトリウム血症のリスク群です。2時間を超えるレースではナトリウム入りの飲み物も使い、ジェルは必ず水と一緒に飲んでください。"),
        rationale: adv("Hew-Butler 2015 EAH 3차 국제합의(Clin J Sport Med 25(4):303–320) · D-\(d)", "Hew-Butler 2015, 3rd International EAH Consensus (Clin J Sport Med 25(4):303–320) · D-\(d)", ja: "Hew-Butler 2015 EAH第3回国際コンセンサス(Clin J Sport Med 25(4):303–320) · D-\(d)"),
        grade: "A", gainMin: 10, timeliness: 0.9, slot: "raceCountdown")
}

// MARK: - 근력·폼 조언 공통 억제
//
// ⚠ 이 시기에 새 고중량·새 큐를 넣으면 회복만 잡아먹는다.
//   · 테이퍼: 하프 이상 대회 D-14 이내 (Bosquet 2007 — 볼륨만 줄이고 강도 유지, 새 자극 금지)
//   · 회복: 완주 기록이 있는 하프 이상 대회 D+14 이내 (근손상·염증 정상화 기간)
//   · 복귀: 공백 종료 21일 이내

/// 억제 사유. nil이면 억제 없음.
/// 공백 원인(내부 값은 한국어) — 표시용.
func mrGapCauseLabel(_ cause: String) -> String {
    switch cause {
    case "부상 의심":      return adv(cause, "possible injury", ja: "けがの疑い")
    case "질병·여행 의심": return adv(cause, "possible illness or travel", ja: "病気・旅行の疑い")
    default:               return adv(cause, "unknown", ja: "不明")
    }
}

func mrStrengthAdviceSuppression(races: [MRTargetRace], runs: [MRWorkout],
                                 gaps: [MRGap], asOf: Date) -> String? {
    let cal = Calendar.current
    let today = cal.startOfDay(for: asOf)
    for r in races where r.distanceM >= MRDistance.dH {
        let d = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: r.date)).day ?? 999
        if d >= 0 && d <= 14 { return "테이퍼 D-\(d)" }
        if d < 0 && d >= -14, mrFinishedRun(for: r, runs: runs) != nil { return "대회 회복 D+\(-d)" }
    }
    if let g = gaps.last,
       let since = cal.dateComponents([.day], from: cal.startOfDay(for: g.end), to: today).day,
       since >= 0, since <= 21 {
        return "공백 복귀 \(since)일"
    }
    return nil
}

// MARK: - 큐 조립

func mrBuildAdvice(runs: [MRWorkout],
                   phys: MRPhysiology,
                   plans: [MRRacePlan],
                   races: [MRTargetRace] = [],
                   gaps: [MRGap],
                   strengthPerWeek: Double,
                   fatigue: [MRLongRunFatigue] = [],
                   cadenceShift: MRFormShift? = nil,
                   heatHR: MRHeatHRModel = MRHeatHRModel(),
                   hrvTrend: MRHRVTrend? = nil,
                   hardRunStarts: Set<Date> = [],
                   log: MRAdviceLog,
                   asOf: Date) -> [MRAdvice] {

    var out: [MRAdvice] = []
    let cal = Calendar.current
    func days(_ d: Date) -> Int {
        cal.dateComponents([.day], from: d, to: cal.startOfDay(for: asOf)).day ?? -1
    }
    guard let last = runs.last else { return out }

    // ── 단일 세션 스파이크
    //
    // Frandsen 2025 (BJSM 59(17):1203–1210, n=5,205)는 단일 임계값이 아니라
    // 3개 밴드를 보고했고 관계가 단조증가가 아니다:
    //   ≤10% 참조 · 10–30% HRR 1.64 · 30–100% 1.52 · >100% 2.28
    let prior = runs.filter {
        $0.start != last.start
        && $0.date < last.date
        && last.date.timeIntervalSince($0.date) <= 30 * 86400
    }.compactMap(\.distanceKm)

    if let longest = prior.max(), let cur = last.distanceKm, cur > longest * 1.10 {
        let over = (cur / longest - 1) * 100
        let hrr = over <= 30 ? "1.64" : (over <= 100 ? "1.52" : "2.28")
        out.append(MRAdvice(key: "spike",
            text: String(format: adv("지난 30일 최장 거리보다 %.0f%% 길었습니다. 다음 롱런은 %.0fkm 정도가 무난합니다.", "%.0f%% longer than your longest run in the last 30 days. About %.0f km is a safe next long run.", ja: "直近30日の最長距離より%.0f%%長く走りました。次のロング走は%.0fkmほどが無難です。"), over, longest * 1.1),
            rationale: String(format: adv("최근 30일 최장 %.1fkm → 이번 %.1fkm · Frandsen 2025 해당 밴드 HRR %@", "Longest in 30 days %.1f km → this run %.1f km · Frandsen 2025 band HRR %@", ja: "直近30日の最長 %.1fkm → 今回 %.1fkm · Frandsen 2025 該当帯のHRR %@"), longest, cur, hrr),
            grade: "B", gainMin: 8, timeliness: 0.9, slot: "todayRun"))
    }

    // ── 공백 후 복귀
    //
    // 원인에 따라 말이 달라야 한다. 부상 뒤 복귀와 감기 뒤 복귀는 다르다.
    // ⚠ "왜 쉬었냐"고 묻지 않는다. 걸음 수로 추론한 것이다.
    if let g = gaps.last,
       let dSince = Calendar.current.dateComponents([.day], from: g.end, to: asOf).day,
       dSince >= 0, dSince <= 21 {
        let pre = runs.filter {
            let x = Calendar.current.dateComponents([.day], from: $0.date, to: g.start).day ?? -1
            return x > 0 && x <= 28
        }.compactMap(\.distanceKm).reduce(0, +) / 4.0

        if pre > 0 {
            let decay = g.days < 28 ? 0.8 : (g.days < 56 ? 0.6 : 0.4)
            let text: String
            let wk = Int(pre*decay)
            switch g.cause {
            case "부상 의심":
                // 이 공백 직전에 단일 세션 급증이 있었다.
                // 같은 실수를 반복하지 않게 하는 게 핵심이다.
                text = adv("\(g.days)일 쉬고 돌아오셨습니다. 당분간 주 \(wk)km 정도로 시작하시고, 롱런은 한 번에 10% 넘게 올리지 않는 게 좋습니다.",
                           "Back after \(g.days) days off. Start at about \(wk) km a week for now, and don't raise the long run more than 10% at a time.",
                           ja: "\(g.days)日休んで戻ってきました。しばらくは週\(wk)kmほどから始め、ロング走は一度に10%を超えて伸ばさないのがよいです。")
            case "질병·여행 의심":
                text = adv("\(g.days)일 만입니다. 몸이 아직 돌아오는 중일 수 있으니 주 \(wk)km 정도로 가볍게 시작하시면 됩니다.",
                           "First run in \(g.days) days. Your body may still be coming back, so start easy at about \(wk) km a week.",
                           ja: "\(g.days)日ぶりです。体がまだ戻りきっていないかもしれないので、週\(wk)kmほどで軽く始めれば大丈夫です。")
            default:
                text = adv("\(g.days)일 만에 다시 나오셨습니다. 반갑습니다. 주 \(wk)km 정도로 시작하면 무리가 없습니다.",
                           "Back out after \(g.days) days — good to see you. Starting at about \(wk) km a week is comfortable.",
                           ja: "\(g.days)日ぶりに走り出しました。おかえりなさい。週\(wk)kmほどから始めれば無理がありません。")
            }
            out.append(MRAdvice(key: "return", text: text,
                rationale: String(format: adv("공백 전 주 평균 %.0fkm × %.1f · 원인 추정: %@ (걸음 수 기준)",
                                             "Pre-break weekly avg %.0f km × %.1f · likely cause: %@ (from step count)",
                                             ja: "ブランク前の週平均 %.0fkm × %.1f · 推定原因: %@(歩数基準)"),
                                         pre, decay, mrGapCauseLabel(g.cause)),
                grade: "B", gainMin: 9, timeliness: 0.95, slot: "todayRun"))
        }
    }

    // ── 수면 HRV 위·안정 + 2주 이지 블록 → 강도 세션 제안
    //
    // HRV 기반으로 강도를 조절한 러너는 고강도 시간을 덜 쓰고도 같거나 더 나은 향상을 얻었다
    // (Vesterinen 2016, HRV-guided vs predefined). 저강도 기간에는 HRV가 오른다(Plews·Buchheit).
    // ⚠ HRV는 회복 상태 지표이지 체력 지표가 아니다 — "체력이 늘었다"고 말하지 않는다. 등급 B.
    // 아래/불안정 조언은 여기 없다 — 총평 훈련부하 줄이 담당.
    // 14일 고강도가 1회뿐이어도 그게 어제·오늘 러닝이면 제안하지 않는다 — 총평의 "마지막 고강도 2일 이상 전"과 같은 규칙.
    if let t = hrvTrend, t.isReadyHigh, days(last.date) <= 3 {
        let c = mrRecentHardRunCount(runs: runs, phys: phys, heatHR: heatHR, days: 14, asOf: asOf,
                                     extraHardStarts: hardRunStarts)
        if c.hard <= 1 && c.total >= 4 && (c.lastHardDaysAgo ?? Int.max) >= 2 {
            out.append(MRAdvice(key: "hrvReady",
                text: adv("지난 2주는 이지런 위주였고 수면 HRV 7일 평균이 4주 기준선 위로 안정적입니다. 이번 주 강도 세션 하나 넣기 좋은 때입니다.", "The last two weeks were mostly easy runs, and your 7-day sleep HRV average is steadily above its 4-week baseline. A good week to add one quality session.", ja: "直近2週間はイージーラン中心で、睡眠中HRVの7日平均が4週の基準線より上で安定しています。今週は強度練習を1回入れるのに適した時期です。"),
                rationale: String(format: adv("HRV 7일 %.0fms · 4주 기준선 %.0fms · 14일 고강도 %d회 · Vesterinen 2016(HRV 기반 강도 조절) · 회복 지표이지 체력 지표는 아님", "HRV 7-day %.0f ms · 4-wk baseline %.0f ms · %d hard runs in 14 days · Vesterinen 2016 (HRV-guided training) · a recovery marker, not a fitness marker", ja: "HRV 7日 %.0fms · 4週基準線 %.0fms · 14日間の高強度%d回 · Vesterinen 2016(HRVに基づく強度調整) · 回復の指標であり体力の指標ではない"),
                                  t.sevenDayMean, t.baseline, c.hard),
                grade: "B", gainMin: 3, timeliness: 0.6, slot: "todayRun"))
        }
    }

    // ── 이지 비율
    //
    // ⚠ 이전 버전은 우리의 **LT1 심박** 기준 비율을 Muniz-Pumares 2025의
    //   **임계속도 페이스** 기준 49%와 나란히 놓았다. 존 정의가 달라
    //   비교 자체가 성립하지 않는다(심박 체계에서 정상은 75–85%다).
    // ⚠ 그리고 강도 분포를 바꾸면 기록이 좋아진다는 RCT 근거가 없다 —
    //   Rosenblat 2025 (Sports Med 55(3):655–673, 13연구 IPD 네트워크 메타):
    //   극성 vs 피라미드 VO2max p=0.68, TT p=0.34. 차이 없음.
    //   → 비교 수치를 빼고 등급을 A에서 B로 내린다.
    if let lt1 = phys.lt1HR {
        let all = runs.filter { let d = days($0.date); return d >= 0 && d < 28 && $0.hrAvg != nil }
        let intervals = all.filter(\.isInterval).count
        // ⚠ 인터벌은 분모에서 뺀다. 의도한 고강도를
        //   "이지를 너무 빠르게 뛴 것"으로 세면 조언이 통째로 틀린다.
        let hrRuns = all.filter { !$0.isInterval }
        if hrRuns.count >= 4 {
            // 15°C 기준으로 보정한 심박으로 판정 — 더운 날 심박 상승분을 빼고 본다
            let easy = hrRuns.filter { (heatHR.refHR(of: $0) ?? $0.hrAvg!) < lt1.value }.count
            if Double(easy) / Double(hrRuns.count) < 0.6 {
                // ⚠ "17회 중 0회"처럼 0을 그대로 노출하지 않는다.
                //   사실이지만 0은 사람을 찌르고, 이 조언은 애초에
                //   인과 근거가 약해 등급 B로 내려간 항목이다.
                //   근거가 약한 걸 제일 아프게 말하면 안 된다.
                let phrase = easy == 0
                    ? adv("최근 4주는 대부분 템포에 가까운 날이었습니다", "Most of the last 4 weeks were close to tempo effort", ja: "直近4週はほとんどがテンポに近い日でした")
                    : adv("최근 4주 \(hrRuns.count)회 중 \(easy)회가 유산소 구간이었습니다", "\(easy) of \(hrRuns.count) runs in the last 4 weeks were in the aerobic zone", ja: "直近4週の\(hrRuns.count)回のうち\(easy)回が有酸素域でした")
                let intervalNote = intervals > 0
                    ? adv("(인터벌 \(intervals)회는 따로 세었습니다) ", "(\(intervals) interval sessions counted separately) ", ja: "(インターバル\(intervals)回は別に数えました)")
                    : ""
                out.append(MRAdvice(key: "easyRatio",
                    text: adv("\(phrase). \(intervalNote)주에 한 번만 더 느리게 잡아두면 다리가 오래 갑니다. 강도 분포를 바꾸면 기록이 좋아진다는 직접 근거는 아직 없지만, 낮은 강도가 몸에 부담을 덜 주는 것은 분명합니다.",
                              "\(phrase). \(intervalNote)Making just one more run a week slower keeps your legs going longer. There's no direct evidence yet that changing your intensity mix improves race times, but lower intensity clearly puts less strain on the body.",
                              ja: "\(phrase)。\(intervalNote)週に1回だけでもゆっくり走る日を増やすと、脚が長持ちします。強度の配分を変えると記録が良くなるという直接の根拠はまだありませんが、低い強度が体への負担を減らすのは確かです。"),
                    rationale: String(format: adv("LT1 추정 %.0f±%.0fbpm 기준(15°C 기준 심박으로 비교) · 인터벌 %d회 제외 · 인과관계 미확인(Rosenblat 2025)", "Estimated LT1 %.0f±%.0f bpm (compared at 15°C-adjusted HR) · %d intervals excluded · causality unconfirmed (Rosenblat 2025)", ja: "推定LT1 %.0f±%.0fbpm基準(15°C換算心拍で比較) · インターバル%d回を除外 · 因果関係は未確認(Rosenblat 2025)"),
                                      lt1.value, phys.lt1SD, intervals),
                    grade: "B", gainMin: 3, timeliness: 0.15, slot: "weekly"))
            }
        }
    }

    // ── 내구성 · 근력 · 케이던스 (공통 억제 적용)
    let suppression = mrStrengthAdviceSuppression(races: races, runs: runs, gaps: gaps, asOf: asOf)
    #if DEBUG
    if let s = suppression { print("[조언] 근력·폼 조언 억제 — \(s)") }
    #endif

    // ── 내구성 (S1: 롱런 후반 케이던스 붕괴)
    //
    // 발동 조건은 S1 집계 하나다. 근력 세션 횟수는 발동 조건이 아니다 —
    // 워치의 근력 기록이 부정확해 근력을 하는 사람에게도 잔소리가 되기 때문.
    let verdict = MRDurabilityCheck.aggregate(fatigue: fatigue, runs: runs,
                                              maxHR: phys.hrMax?.value, asOf: asOf)
    #if DEBUG
    print(String(format: "[내구성:판정] 요약 %d건 → 평가 가능 %d건 · 양성 %d건 · %@%@",
                 fatigue.count, verdict.evaluated, verdict.positive,
                 verdict.triggered ? "발동" : (verdict.evaluated < 2 ? "판정 없음(평가 가능 2건 미만)" : "미발동"),
                 verdict.latestDropPct.map { String(format: " · 최신 하락 %.1f%%", $0) } ?? ""))
    #endif
    // 롱런 후반 패턴(`LateRunDiagnosis` 최근 3회 중 2회) — 다리형은 내구성 조언과 같은 주제라 거기로 합친다
    let late = MRLateRunPattern.aggregate(fatigue: fatigue, asOf: asOf)
    #if DEBUG
    // 성장 탭이 롱런 요약을 넘기기 전(빈 배열)의 조언 계산은 찍지 않는다 — "진단 0건"이 여러 줄 반복되는 소음
    if !fatigue.isEmpty { print("[후반:패턴] 진단 \(late.evaluated)건 · 반복 유형 \(late.dominant?.rawValue ?? "없음")(\(late.dominantCount)회)") }
    #endif
    if suppression == nil, !verdict.triggered, late.dominant == .legs {
        out.append(MRAdvice(key: "durability",
            text: late.latestIsTodayAndDominant
                ? adv("오늘 롱런도 후반에 다리가 먼저 지쳤습니다. 최근 롱런 \(late.evaluated)번 중 \(late.dominantCount)번이 그랬습니다. 거리를 무리하게 늘리기보다 편한 롱런을 꾸준히 쌓고, 무거운 근력운동과 점프 운동을 더해 보세요.", "Your legs tired first late in today's long run too — \(late.dominantCount) of your last \(late.evaluated) long runs went that way. Rather than forcing more distance, keep stacking easy long runs and add heavy strength work and jumps.", ja: "今日のロング走も後半に脚が先に疲れました。直近のロング走\(late.evaluated)回のうち\(late.dominantCount)回がそうでした。距離を無理に伸ばすより、楽なロング走を継続して積み、重めの筋力トレーニングとジャンプ系の運動を加えてみてください。")
                : adv("최근 롱런 후반에 심박은 버티는데 폼이 먼저 무거워지는 패턴이 반복됐습니다. 거리를 무리하게 늘리기보다 편한 롱런을 꾸준히 쌓고, 무거운 근력운동과 점프 운동을 더해 보세요.", "Late in recent long runs, your heart rate held but your form got heavier first, again and again. Rather than forcing more distance, keep stacking easy long runs and add heavy strength work and jumps.", ja: "最近のロング走の後半で、心拍は持ちこたえるのにフォームが先に重くなるパターンが繰り返されました。距離を無理に伸ばすより、楽なロング走を継続して積み、重めの筋力トレーニングとジャンプ系の運動を加えてみてください。"),
            rationale: adv("최근 8주 롱런 \(late.evaluated)회 중 \(late.dominantCount)회 후반 폼이 평소 범위 밖으로 무거워짐(심박 효율은 유지) · Blagrove 2018 메타분석(근력·플라이오 → 경제성)", "\(late.dominantCount) of \(late.evaluated) long runs in 8 weeks: late form heavier than usual range (HR efficiency held) · Blagrove 2018 meta-analysis (strength/plyometrics → economy)", ja: "直近8週のロング走\(late.evaluated)回のうち\(late.dominantCount)回で後半のフォームが普段の範囲外に重くなった(心拍効率は維持) · Blagrove 2018メタ分析(筋力・プライオ → ランニングエコノミー)"),
            grade: "B", gainMin: 6, timeliness: late.latestIsTodayAndDominant ? 0.8 : 0.4,
            slot: late.latestIsTodayAndDominant ? "todayRun" : "weekly",
            exercises: [
                adv("근력 주 2회 20~30분 — 스쿼트·데드리프트·한발 운동·카프 레이즈 중 2~3개", "Strength 2×/week, 20–30 min — 2–3 of squats, deadlifts, single-leg work, calf raises", ja: "筋力トレーニング週2回20~30分 — スクワット・デッドリフト・片脚種目・カーフレイズから2~3種目"),
                adv("무거운 무게 = 8회 이하로 힘든 무게, 세트당 3~5회", "Heavy = a weight that's hard by 8 reps or fewer; 3–5 reps per set", ja: "重い重量 = 8回以下できつくなる重さ、1セット3~5回"),
                adv("점프 — 제자리 홉·바운딩·언덕 스프린트 중 하나, 10분 이내", "Jumps — one of hops in place, bounding, or hill sprints, under 10 min", ja: "ジャンプ — その場ホップ・バウンディング・坂ダッシュのどれか1つ、10分以内"),
                adv("롱런 다음날은 피하고, 이지런 날에", "Avoid the day after a long run; do it on an easy-run day", ja: "ロング走の翌日は避け、イージーランの日に"),
            ]))
    }
    if suppression == nil, verdict.triggered {
        let dropStr = String(format: "%.0f", max(verdict.latestDropPct ?? 0, 0))
        let text: String
        let slot: String
        var timeliness: Double
        if verdict.latestPositiveIsToday {
            slot = "todayRun"; timeliness = 0.8
            text = adv("오늘 롱런 후반에 케이던스가 \(dropStr)% 떨어졌습니다. 최근 롱런 \(verdict.evaluated)번 중 \(verdict.positive)번이 그랬습니다. 다리가 지치면 발걸음이 느려지는 패턴입니다. 무거운 무게를 드는 근력운동과 점프 운동이 이걸 늦추는 데 도움이 될 수 있습니다.", "Your cadence dropped \(dropStr)% late in today's long run — \(verdict.positive) of your last \(verdict.evaluated) long runs did the same. It's the pattern of steps slowing as legs tire. Heavy strength work and jumps can help delay it.", ja: "今日のロング走の後半にケイデンスが\(dropStr)%落ちました。直近のロング走\(verdict.evaluated)回のうち\(verdict.positive)回がそうでした。脚が疲れるとピッチが落ちるパターンです。重い重量の筋力トレーニングとジャンプ系の運動が、これを遅らせるのに役立つことがあります。")
        } else {
            slot = "weekly"; timeliness = 0.4
            text = adv("최근 롱런 후반에 발걸음이 느려지는 패턴이 반복됐습니다. 무거운 무게를 드는 근력운동과 점프 운동이 후반 페이스를 지키는 데 도움이 됩니다.", "Your steps have repeatedly slowed late in recent long runs. Heavy strength work and jumps help hold your late pace.", ja: "最近のロング走の後半でピッチが落ちるパターンが繰り返されました。重い重量の筋力トレーニングとジャンプ系の運動が、後半のペースを保つのに役立ちます。")
        }
        if strengthPerWeek < 1.0 { timeliness += 0.1 }
        out.append(MRAdvice(key: "durability", text: text,
            rationale: String(format: adv("최근 8주 롱런 %d회 중 %d회 후반 케이던스 ≥3%%↓ · Blagrove 2018 메타분석(근력·플라이오 → 경제성) · 3%% 임계는 임의", "%d long runs in 8 weeks, %d with late cadence down ≥3%% · Blagrove 2018 meta-analysis (strength/plyometrics → economy) · the 3%% threshold is arbitrary", ja: "直近8週のロング走%d回のうち%d回で後半ケイデンス3%%以上低下 · Blagrove 2018メタ分析(筋力・プライオ → ランニングエコノミー) · 3%%の閾値は任意"),
                              verdict.evaluated, verdict.positive),
            grade: "B", gainMin: 6, timeliness: timeliness, slot: slot,
            exercises: [
                adv("근력 주 2회 20~30분 — 스쿼트·데드리프트·한발 운동·카프 레이즈 중 2~3개", "Strength 2×/week, 20–30 min — 2–3 of squats, deadlifts, single-leg work, calf raises", ja: "筋力トレーニング週2回20~30分 — スクワット・デッドリフト・片脚種目・カーフレイズから2~3種目"),
                adv("무거운 무게 = 8회 이하로 힘든 무게, 세트당 3~5회", "Heavy = a weight that's hard by 8 reps or fewer; 3–5 reps per set", ja: "重い重量 = 8回以下できつくなる重さ、1セット3~5回"),
                adv("점프 — 제자리 홉·바운딩·언덕 스프린트 중 하나, 10분 이내", "Jumps — one of hops in place, bounding, or hill sprints, under 10 min", ja: "ジャンプ — その場ホップ・バウンディング・坂ダッシュのどれか1つ、10分以内"),
                adv("롱런 다음날은 피하고, 이지런 날에", "Avoid the day after a long run; do it on an easy-run day", ja: "ロング走の翌日は避け、イージーランの日に"),
            ]))
    }

    // ── 근력운동 (기본) — 2026-10-02 뺐다.
    //   내 데이터와 무관한 일반론이고, 근력을 하되 기록하지 않는 사람에게도 계속 떴다.
    //   근력은 롱런 후반 패턴(durability)이 발동할 때만 처방으로 말한다. 일반 근력 조언은 추후 재논의.

    // ── 케이던스 큐 (유일한 폼 제안)
    //
    // Van Hooren 2024 (Sports Med 54(5):1269–1316): 케이던스 r=−0.20.
    // 개입 근거는 Heiderscheit 2011 (MSSE 43(2):296–302): 케이던스 +5~10% → 관절 부하 감소.
    // ⚠ 지친 뒤 하락(S1)이 하나라도 있으면 그건 내구성 문제다 — 큐를 주지 않는다.
    if suppression == nil, verdict.positive == 0,
       let s = cadenceShift, s.metric.key == "cadence", s.isReal, s.delta < 0 {
        out.append(MRAdvice(key: "cadenceCue",
            text: String(format: adv("같은 페이스에서 케이던스가 3개월 새 %.0f spm 내려갔습니다. 이지런 한 번에 10분만 평소보다 5%% 빠른 발걸음으로 달려보세요.", "At the same pace, your cadence has dropped %.0f spm over 3 months. On one easy run, try 10 minutes at a step rate 5%% quicker than usual.", ja: "同じペースでケイデンスが3か月で%.0f spm下がりました。イージーランの中で10分だけ、普段より5%%速いピッチで走ってみてください。"), abs(s.delta)),
            rationale: String(format: adv("MRFormShift cadence Δ=%.1f spm (MDC %.1f) · Van Hooren 2024 r=−0.20 · Heiderscheit 2011 (+5~10%% 케이던스)", "MRFormShift cadence Δ=%.1f spm (MDC %.1f) · Van Hooren 2024 r=−0.20 · Heiderscheit 2011 (+5–10%% cadence)", ja: "MRFormShift cadence Δ=%.1f spm (MDC %.1f) · Van Hooren 2024 r=−0.20 · Heiderscheit 2011(ケイデンス+5~10%%)"), s.delta, s.mdc),
            grade: "B", gainMin: 2, timeliness: 0.3, slot: "weekly",
            exercises: [
                adv("이지런 중 10분, 메트로놈 앱을 평소 케이던스 +5%로", "10 min during an easy run, metronome app at your usual cadence +5%", ja: "イージーラン中の10分間、メトロノームアプリを普段のケイデンス+5%に"),
                adv("보폭을 줄인다는 느낌으로. 속도는 올리지 않는다", "Think shorter steps — don't speed up", ja: "歩幅を狭める感覚で。スピードは上げない"),
            ]))
    }

    // ── 롱런 후반 패턴 — 심박형 · 한꺼번에 · 끝까지 유지 (훈련 방식 변경이라 근력과 같은 억제 적용)
    //
    // 심박형: 목표 페이스 과도 · 유산소 기반/역치 부족 · 더위·수분 — 영상의 원인 목록 그대로.
    //   Friel 유산소 디커플링 5% 관례 · Maunder 2021(Sports Med 51(8):1619–1628, 내구성).
    // 한꺼번에: 초반 강도 과도 또는 기본 지구력 부족 → 초반을 늦추고 주간 거리를 꾸준히.
    // 끝까지 유지: 다음 단계 = 롱런 후반 목표 페이스 삽입(대회 계획의 빌드 후반 규칙과 같은 처방).
    //   대회 계획이 있으면 계획이 이미 그 처방을 하므로 생략한다.
    let slotToday = late.latestIsTodayAndDominant
    if suppression == nil {
        switch late.dominant {
        case .cardio?:
            out.append(MRAdvice(key: "lateCardio",
                text: adv("최근 롱런 \(late.evaluated)번 중 \(late.dominantCount)번, 후반에 같은 속도를 내는 데 심박이 더 들었습니다. 다리보다 심박이 먼저 한계에 닿는 패턴입니다. 롱런 중반 페이스를 10초/km 늦추고, 주 1회 템포 20분으로 같은 페이스의 심박을 낮춰 보세요. 더운 날엔 수분·나트륨도 챙기세요.", "In \(late.dominantCount) of your last \(late.evaluated) long runs, holding the same speed late cost more heart rate — your heart rate tends to hit its limit before your legs. Slow the middle of your long runs by 10 s/km, and add a weekly 20-minute tempo to lower your heart rate at the same pace. On hot days, keep up fluids and sodium too.", ja: "直近のロング走\(late.evaluated)回のうち\(late.dominantCount)回で、後半に同じ速度を出すのにより多くの心拍が必要でした。脚より心拍が先に限界に達するパターンです。ロング走の中盤ペースを10秒/km落とし、週1回20分のテンポ走で同じペースの心拍を下げてみてください。暑い日は水分・ナトリウムも補給してください。"),
                rationale: adv("최근 8주 롱런 \(late.evaluated)회 중 \(late.dominantCount)회 중반 대비 후반 심박 효율 5%↑ 하락 · Friel 유산소 디커플링 5% 관례 · Maunder 2021(내구성)", "\(late.dominantCount) of \(late.evaluated) long runs in 8 weeks: late HR efficiency down 5%+ vs mid · Friel 5% aerobic decoupling convention · Maunder 2021 (durability)", ja: "直近8週のロング走\(late.evaluated)回のうち\(late.dominantCount)回で中盤比の後半心拍効率が5%以上低下 · Friel 有酸素デカップリング5%の慣例 · Maunder 2021(耐久力)"),
                grade: "B", gainMin: 5, timeliness: slotToday ? 0.75 : 0.35, slot: slotToday ? "todayRun" : "weekly",
                exercises: [
                    adv("롱런 — 중반 페이스를 평소보다 10초/km 늦게, 후반 심박을 비교", "Long run — middle section 10 s/km slower than usual, then compare late HR", ja: "ロング走 — 中盤のペースを普段より10秒/km遅くし、後半の心拍を比較"),
                    adv("템포 주 1회 — 편하게 힘든 강도 20분(대화는 짧은 문장만)", "Tempo once a week — 20 min at comfortably hard (short sentences only)", ja: "テンポ走週1回 — 「楽にきつい」強度で20分(会話は短い文だけ)"),
                    adv("더운 날 — 출발 전 수분, 60분 넘으면 나트륨 음료", "Hot days — drink before you start; sodium drink if over 60 min", ja: "暑い日 — 出発前に水分、60分を超えるならナトリウム入り飲料"),
                ]))
        case .combined?:
            out.append(MRAdvice(key: "lateCombined",
                text: adv("최근 롱런 \(late.evaluated)번 중 \(late.dominantCount)번, 후반에 심박도 더 들고 폼도 무거워졌습니다. 초반 강도가 높았거나 기본 지구력이 아직 부족할 때 나오는 패턴입니다. 초반을 더 편하게 시작하고, 긴 롱런 한 번보다 주간 거리를 꾸준히 쌓아 보세요.", "In \(late.dominantCount) of your last \(late.evaluated) long runs, heart rate cost rose and form got heavier late. It's a pattern seen when the start is too hard or base endurance is still building. Start easier, and build steady weekly volume rather than one big long run.", ja: "直近のロング走\(late.evaluated)回のうち\(late.dominantCount)回で、後半に心拍も多く必要になり、フォームも重くなりました。序盤の強度が高かったり、基礎持久力がまだ足りないときに出るパターンです。序盤をもっと楽に入り、長いロング走1回より週間距離を継続して積んでみてください。"),
                rationale: adv("최근 8주 롱런 \(late.evaluated)회 중 \(late.dominantCount)회 후반 심박 효율 5%↑ 하락 + 폼 평소 범위 밖 · Maunder 2021(내구성)", "\(late.dominantCount) of \(late.evaluated) long runs in 8 weeks: late HR efficiency down 5%+ and form outside usual range · Maunder 2021 (durability)", ja: "直近8週のロング走\(late.evaluated)回のうち\(late.dominantCount)回で後半心拍効率が5%以上低下+フォームが普段の範囲外 · Maunder 2021(耐久力)"),
                grade: "C", gainMin: 4, timeliness: slotToday ? 0.7 : 0.3, slot: slotToday ? "todayRun" : "weekly",
                exercises: [
                    adv("롱런 첫 20분은 이지 페이스보다도 느리게", "First 20 min of a long run even slower than easy pace", ja: "ロング走の最初の20分はイージーペースよりもさらにゆっくり"),
                    adv("한 주 거리를 한 번에 몰지 말고 3~4회로 나눠 꾸준히", "Spread weekly distance over 3–4 runs instead of one big day", ja: "1週間の距離を1回にまとめず、3~4回に分けて継続的に"),
                ]))
        case .held? where plans.isEmpty:
            out.append(MRAdvice(key: "lateHeld",
                text: adv("최근 롱런 \(late.evaluated)번 중 \(late.dominantCount)번, 후반까지 심박 효율과 폼을 지켰습니다. 다음 단계는 지친 상태에서 페이스를 지키는 연습입니다 — 롱런 마지막 15분을 목표 대회 페이스로 올려 보세요.", "In \(late.dominantCount) of your last \(late.evaluated) long runs, you held HR efficiency and form to the end. The next step is practicing pace while tired — lift the last 15 minutes of your long run to goal race pace.", ja: "直近のロング走\(late.evaluated)回のうち\(late.dominantCount)回で、後半まで心拍効率とフォームを保ちました。次のステップは疲れた状態でペースを保つ練習です — ロング走の最後の15分を目標レースペースに上げてみてください。"),
                rationale: adv("최근 8주 롱런 \(late.evaluated)회 중 \(late.dominantCount)회 후반 유지(심박 효율 하락 5% 미만 · 폼 평소 범위) · 롱런 후반 대회 페이스 삽입은 관행(통제 연구 없음)", "\(late.dominantCount) of \(late.evaluated) long runs in 8 weeks held late (HR efficiency loss under 5% · form in usual range) · race pace late in long runs is common practice (no controlled studies)", ja: "直近8週のロング走\(late.evaluated)回のうち\(late.dominantCount)回で後半を維持(心拍効率の低下5%未満 · フォームは普段の範囲) · ロング走後半にレースペースを入れるのは慣行(対照研究なし)"),
                grade: "C", gainMin: 3, timeliness: 0.25, slot: "weekly"))
        default:
            break
        }
    }

    // ── 보급 2종(장 훈련·수분)
    //
    // ⚠ "가장 가까운 대회"가 아니라 "**보급이 필요한** 대회 중 가장 가까운 것"이다.
    //   8/30 10K가 11/1 풀보다 가깝다고 해서 마라톤 보급 안내를 놓치면 안 된다.
    //   10K에는 애초에 보급 조언이 붙지 않으므로, 그 대회를 보고 있으면
    //   조언이 통째로 사라진다. 실제로 그렇게 사라지고 있었다.
    let fuelable = plans.filter { $0.distanceM >= 20000 }
    if let target = fuelable.min(by: { $0.raceDate < $1.raceDate }) {
        let fns: [(Date, Double, Double, Date) -> MRAdvice?] = [
            mrGutTrainingAdvice, mrHydrationAdvice
        ]
        for fn in fns {
            if let a = fn(target.raceDate, target.distanceM, target.projectedFinal, asOf) {
                out.append(a)
            }
        }
    }

    // ── 롱런 후반 패턴 — 에너지형 (보급 연습은 테이퍼·회복 중에도 유효해 억제하지 않는다)
    // ⚠ 대회 보급 연습 조언(gut)이 이미 있으면 같은 주제라 생략한다.
    // ⚠ 보급 기록이 없으므로 "가능성"으로만 말한다 — 페이스와 심박이 함께 내려간 90분 이상 롱런에서만 진단된다.
    if late.dominant == .energy, !out.contains(where: { $0.key == "gut" }) {
        out.append(MRAdvice(key: "lateEnergy",
            text: adv("최근 롱런 \(late.evaluated)번 중 \(late.dominantCount)번, 90분이 지나면 페이스와 심박이 함께 내려갔습니다. 에너지가 떨어졌을 가능성이 있습니다. 90분 넘는 롱런은 30~40분부터 시간당 30~60g 탄수화물을 나눠 먹어 보고, 초반 10분은 목표보다 느리게 시작해 보세요.", "In \(late.dominantCount) of your last \(late.evaluated) long runs, pace and heart rate dropped together after 90 minutes — you may have run low on energy. On long runs over 90 minutes, take 30–60 g of carbs per hour starting at 30–40 minutes, and start the first 10 minutes slower than goal.", ja: "直近のロング走\(late.evaluated)回のうち\(late.dominantCount)回で、90分を過ぎるとペースと心拍が一緒に下がりました。エネルギー切れの可能性があります。90分を超えるロング走では30~40分から1時間あたり30~60gの炭水化物を分けて摂り、最初の10分は目標より遅く始めてみてください。"),
            rationale: adv("최근 8주 90분+ 롱런 \(late.evaluated)회 중 \(late.dominantCount)회 후반 페이스 20초/km↑ 느려짐 + 심박 3bpm↓ (보급 기록 없음, 추정) · ACSM/AND/DC 2016(1~2.5시간 30~60 g/h)", "\(late.dominantCount) of \(late.evaluated) 90+ min long runs in 8 weeks: late pace 20+ s/km slower and HR down 3+ bpm (no fueling data, estimated) · ACSM/AND/DC 2016 (30–60 g/h for 1–2.5 h)", ja: "直近8週の90分以上のロング走\(late.evaluated)回のうち\(late.dominantCount)回で後半ペースが20秒/km以上低下+心拍3bpm以上低下(補給記録なし、推定) · ACSM/AND/DC 2016(1~2.5時間で30~60 g/h)"),
            grade: "B", gainMin: 6, timeliness: slotToday ? 0.75 : 0.4, slot: slotToday ? "todayRun" : "weekly",
            exercises: [
                adv("젤 1개 ≈ 탄수화물 22~25g — 1시간에 1~2개", "One gel ≈ 22–25 g carbs — 1–2 per hour", ja: "ジェル1個 ≈ 炭水化物22~25g — 1時間に1~2個"),
                adv("첫 보급은 30~40분, 이후 20~30분 간격", "First fuel at 30–40 min, then every 20–30 min", ja: "最初の補給は30~40分、その後20~30分間隔"),
                adv("물과 함께. 레이스에 쓸 제품으로 연습", "With water. Practice with the product you'll race with", ja: "水と一緒に。レースで使う製品で練習"),
            ]))
    }

    // ── 신선도 반영 + 주 5개 상한
    //
    // ⚠ 상한이 없으면 조언이 8개씩 쌓여 화면이 훈계가 된다.
    //   설계 원칙: 주 5개. 그 이상은 표시하지 않는다.
    return out
        .map { a -> (MRAdvice, Double) in (a, a.score * log.freshness(a.key, asOf: asOf)) }
        .sorted { $0.1 > $1.1 }
        .prefix(5)
        .map(\.0)
}
