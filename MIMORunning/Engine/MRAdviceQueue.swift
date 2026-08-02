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

func mrFuelingAdvice(raceDate: Date, distanceM: Double,
                     projectedMin: Double, today: Date) -> MRAdvice? {
    let d = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today),
                                            to: Calendar.current.startOfDay(for: raceDate)).day ?? -1
    guard d >= 0, d <= 90, distanceM >= 20000 else { return nil }
    let hours = projectedMin / 60.0
    guard hours >= 1.5 else { return nil }

    if hours >= 2.5 {
        let lo = Int(60 * hours), hi = Int(90 * hours)
        return MRAdvice(key: "fueling",
            text: "\(mrFormatDisplay(projectedMin)) 예상이면 2.5시간을 넘으니 권장 구간이 시간당 60g이 아니라 60~90g입니다(총 \(lo)~\(hi)g). 60g를 넘길 때는 포도당:과당 혼합 제품을 쓰세요 — 단일 포도당은 흡수 한계가 60g/h입니다. 젤만으로는(1개 22~25g) 못 채우니 음료를 함께 계산하고 15~20분 간격으로 나누세요. 상단은 훈련에서 연습해 본 만큼만.",
            rationale: "ACSM/AND/DC 2016 합동 성명 · Jeukendrup 2014(복합 수송 탄수화물) · D-\(d)",
            grade: "A", gainMin: 12, timeliness: 0.85, slot: "raceCountdown")
    }
    let lo = Int(30 * hours), hi = Int(60 * hours)
    return MRAdvice(key: "fueling",
        text: "\(mrFormatDisplay(projectedMin)) 예상이면 시간당 30~60g이 권장 구간입니다(총 \(lo)~\(hi)g). 15~20분 간격으로 균등하게 나누세요.",
        rationale: "ACSM/AND/DC 2016 합동 성명 · D-\(d)",
        grade: "A", gainMin: 6, timeliness: 0.7, slot: "raceCountdown")
}

func mrGutTrainingAdvice(raceDate: Date, distanceM: Double,
                         projectedMin: Double, today: Date) -> MRAdvice? {
    let d = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today),
                                            to: Calendar.current.startOfDay(for: raceDate)).day ?? -1
    guard d >= 14, d <= 90, distanceM >= 20000, projectedMin >= 150 else { return nil }
    return MRAdvice(key: "gut",
        text: "목표 보급량은 레이스 당일 처음 시도하지 마세요. 지금 무리 없는 양에서 시작해 롱런에서 주 1회씩, 시간당 10g 정도로만 올리고 연습에서 도달한 만큼만 쓰세요. 메스꺼움이 오면 시간당 30g으로 낮추고 묽은 음료로 바꾸면 됩니다.",
        rationale: "Jeukendrup 2017(지구성 선수 30~50%가 위장 문제) · Pugh 2018 n=96(레이스 중 중등도 증상 27%) · D-\(d)",
        grade: "B", gainMin: 8, timeliness: 0.75, slot: "raceCountdown")
}

func mrHydrationAdvice(raceDate: Date, distanceM: Double,
                        projectedMin: Double, today: Date) -> MRAdvice? {
    let d = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today),
                                            to: Calendar.current.startOfDay(for: raceDate)).day ?? -1
    guard d >= 0, d <= 30, distanceM >= 20000, projectedMin >= 210 else { return nil }
    return MRAdvice(key: "hydration",
        text: "수분은 정해진 스케줄이 아니라 갈증에 따라 드세요. 4~5시간대 완주자는 과다 음수로 인한 운동관련 저나트륨혈증 위험군입니다. 2시간 넘는 레이스에서는 나트륨이 든 음료를 함께 쓰고, 젤은 반드시 물과 같이 삼키세요.",
        rationale: "Hew-Butler 2015 EAH 3차 국제합의(Clin J Sport Med 25(4):303–320) · D-\(d)",
        grade: "A", gainMin: 10, timeliness: 0.9, slot: "raceCountdown")
}

// MARK: - 큐 조립

func mrBuildAdvice(runs: [MRWorkout],
                   phys: MRPhysiology,
                   plans: [MRRacePlan],
                   gaps: [MRGap],
                   strengthPerWeek: Double,
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
            text: String(format: "지난 30일 최장 거리보다 %.0f%% 길었어요. 다음 롱런은 %.0fkm 정도가 무난합니다.", over, longest * 1.1),
            rationale: String(format: "최근 30일 최장 %.1fkm → 이번 %.1fkm · Frandsen 2025 해당 밴드 HRR %@", longest, cur, hrr),
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
            switch g.cause {
            case "부상 의심":
                // 이 공백 직전에 단일 세션 급증이 있었다.
                // 같은 실수를 반복하지 않게 하는 게 핵심이다.
                text = "\(g.days)일 쉬고 돌아오셨네요. 당분간 주 \(Int(pre*decay))km 정도로 시작하시고, "
                     + "롱런은 한 번에 10% 넘게 올리지 않는 게 좋습니다."
            case "질병·여행 의심":
                text = "\(g.days)일 만이네요. 몸이 아직 돌아오는 중일 수 있으니 "
                     + "주 \(Int(pre*decay))km 정도로 가볍게 시작하시면 됩니다."
            default:
                text = "\(g.days)일 만에 다시 나오셨네요. 반갑습니다. "
                     + "주 \(Int(pre*decay))km 정도로 시작하면 무리가 없어요."
            }
            out.append(MRAdvice(key: "return", text: text,
                rationale: String(format: "공백 전 주 평균 %.0fkm × %.1f · 원인 추정: %@ (걸음 수 기준)", pre, decay, g.cause),
                grade: "B", gainMin: 9, timeliness: 0.95, slot: "todayRun"))
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
            let easy = hrRuns.filter { $0.hrAvg! < lt1.value }.count
            if Double(easy) / Double(hrRuns.count) < 0.6 {
                // ⚠ "17회 중 0회"처럼 0을 그대로 노출하지 않는다.
                //   사실이지만 0은 사람을 찌르고, 이 조언은 애초에
                //   인과 근거가 약해 등급 B로 내려간 항목이다.
                //   근거가 약한 걸 제일 아프게 말하면 안 된다.
                let phrase = easy == 0
                    ? "최근 4주는 대부분 템포에 가까운 날이었어요"
                    : "최근 4주 \(hrRuns.count)회 중 \(easy)회가 유산소 구간이었어요"
                let intervalNote = intervals > 0
                    ? "(인터벌 \(intervals)회는 따로 세었습니다) "
                    : ""
                out.append(MRAdvice(key: "easyRatio",
                    text: "\(phrase). \(intervalNote)주에 한 번만 더 느리게 잡아두면 다리가 오래 갑니다. "
                        + "강도 분포를 바꾸면 기록이 좋아진다는 직접 근거는 아직 없지만, "
                        + "낮은 강도가 몸에 부담을 덜 주는 것은 분명합니다.",
                    rationale: String(format: "LT1 추정 %.0f±%.0fbpm 기준 · 인터벌 %d회 제외 · 인과관계 미확인(Rosenblat 2025)",
                                      lt1.value, phys.lt1SD, intervals),
                    grade: "B", gainMin: 3, timeliness: 0.15, slot: "weekly"))
            }
        }
    }

    // ── 근력운동
    //
    // 러닝에 근력을 더하면 러닝만 할 때보다 경제성과 기록이 좋아진다는
    // 메타분석이 여럿 있다(Blagrove 2018, Sports Med 48(5):1117–1149).
    // 근거가 A급인 몇 안 되는 항목이다.
    // ⚠ 다만 이득 추정치가 없어 gain을 크게 잡지 않는다.
    if strengthPerWeek < 1.5 {
        out.append(MRAdvice(key: "strength",
            text: "근력운동을 주 2회 함께 하면 러닝만 할 때보다 좋았다는 연구가 많습니다. 주 30분이면 충분해요.",
            rationale: String(format: "최근 4주 근력 세션 주 %.1f회 · Blagrove 2018 메타분석", strengthPerWeek),
            grade: "A", gainMin: 4, timeliness: 0.2, slot: "weekly"))
    }

    // ── 보급 3종
    //
    // ⚠ "가장 가까운 대회"가 아니라 "**보급이 필요한** 대회 중 가장 가까운 것"이다.
    //   8/30 10K가 11/1 풀보다 가깝다고 해서 마라톤 보급 안내를 놓치면 안 된다.
    //   10K에는 애초에 보급 조언이 붙지 않으므로, 그 대회를 보고 있으면
    //   조언이 통째로 사라진다. 실제로 그렇게 사라지고 있었다.
    let fuelable = plans.filter { $0.distanceM >= 20000 }
    if let target = fuelable.min(by: { $0.raceDate < $1.raceDate }) {
        let fns: [(Date, Double, Double, Date) -> MRAdvice?] = [
            mrFuelingAdvice, mrGutTrainingAdvice, mrHydrationAdvice
        ]
        for fn in fns {
            if let a = fn(target.raceDate, target.distanceM, target.projectedFinal, asOf) {
                out.append(a)
            }
        }
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
