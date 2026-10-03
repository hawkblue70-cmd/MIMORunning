import Foundation

/// 대회까지 남은 기간에 따라 앱이 할 말이 달라진다.
///
/// ⚠ 각 단계의 근거:
///   · 테이퍼 시작 D-14 — Bosquet 2007 (MSSE 39(8):1358–1365, 27연구 메타):
///     2주 테이퍼, 볼륨 지수적 41–60% 감소, 강도·빈도 유지
///   · D-7 이후 새 최장 롱런 금지 — 그 시점 롱런은 이득이 없고 회복만 잡아먹는다
///   · 초반 페이스 경고 — Smyth 2018 (n=1,724,109): 첫 5km를 목표보다
///     10% 빠르게 가면 완주 시간 **+37분**. 3%만 넘어도 약 +11분.
///   · 회복 2주 — 마라톤 후 근손상·염증 지표가 정상화되는 데 걸리는 시간
enum MRRacePhase {
    case building        // D-15 이상
    case tapering        // D-14 ~ D-8
    case finalWeek       // D-7 ~ D-2
    case eve             // D-1
    case raceDay         // D-0
    case recovery        // D+1 ~ D+14

    var title: String {
        let L = AppLanguage.shared
        switch self {
        case .building:  return L.s("쌓는 시기", "Building", ja: "積む時期")
        case .tapering:  return L.s("이제 아끼는 시기", "Time to save it", ja: "温存する時期")
        case .finalWeek: return L.s("마지막 한 주", "Final week", ja: "最後の1週間")
        case .eve:       return L.s("내일입니다", "Tomorrow", ja: "明日です")
        case .raceDay:   return L.s("오늘입니다", "Today", ja: "今日です")
        case .recovery:  return L.s("회복 중", "Recovering", ja: "回復中")
        }
    }
}

struct MRRaceDayCard {
    let race: MRTargetRace
    let phase: MRRacePhase
    let daysLeft: Int
    let headline: String
    let lines: [String]
    let splits: [(km: Double, time: Double)]     // 대회 임박 시에만
    /// 접힌 상태에서 헤드라인 아래 한 줄 — 페이스처럼 매일 봐야 하는 숫자만. 빈 문자열이면 헤드라인만.
    var compactLine: String = ""
    /// 전날·당일·회복은 항상 펼친다 — 그날 카드가 화면의 주인공이어야 한다.
    var alwaysExpanded: Bool { daysLeft <= 1 }
}

/// 대회 날짜에 실제로 뛴 기록이 있는가.
///
/// ⚠ 등록된 대회 날짜가 지났다는 것은 **참가했다는 뜻이 아니다.**
///   신청만 하고 안 갔을 수도, 부상으로 기권했을 수도 있다.
///   실제 러닝 기록이 있어야 참가한 것이다.
///   거리는 ±15%까지 인정한다 — GPS 오차 + 코스 이탈 + 시계를 늦게 끈 경우.
func mrFinishedRun(for race: MRTargetRace, runs: [MRWorkout]) -> MRWorkout? {
    let cal = Calendar.current
    return runs.first {
        cal.isDate($0.date, inSameDayAs: race.date)
        && abs(($0.distanceKm ?? 0) * 1000 - race.distanceM) / race.distanceM <= 0.15
    }
}

func mrRaceDayCard(race: MRTargetRace,
                   plan: MRRacePlan?,
                   predictions: [MRPrediction],
                   heat: MRHeatModel,
                   raceTempC: Double,
                   goalMin: Double?,
                   runs: [MRWorkout],
                   asOf: Date) -> MRRaceDayCard? {

    let cal = Calendar.current
    let d = cal.dateComponents([.day], from: cal.startOfDay(for: asOf),
                               to: cal.startOfDay(for: race.date)).day ?? 0
    var done: MRWorkout? = nil
    let phase: MRRacePhase
    switch d {
    case 15...:     phase = .building
    case 8...14:    phase = .tapering
    case 2...7:     phase = .finalWeek
    case 1:         phase = .eve
    case 0:         phase = .raceDay
    case (-14)...(-1):
        // 실제 기록이 없으면 회복 화면을 띄우지 않는다
        guard let finishedRun = mrFinishedRun(for: race, runs: runs) else { return nil }
        done = finishedRun
        phase = .recovery
    default:        return nil
    }

    // ⚠ 기준은 **예상 기록**이다. 목표가 아니다.
    //   목표가 예상보다 빠르면 첫 5km부터 이미 과속인 배분이 되고,
    //   그건 이 화면이 경고하려는 바로 그 실수다(Smyth 2018).
    //
    // ⚠ D-0에는 plan이 항상 nil이다(남은 기간 0주 < 3주).
    //   plan에만 의존하면 대회 당일에 늘 목표로 떨어진다 —
    //   하필 가장 중요한 날에만 틀린다.
    //   예측기는 대회 당일에도 살아있으므로 그걸 fallback으로 쓴다.
    let predicted: Double? = predictions
        .first { abs($0.distanceM - race.distanceM) / race.distanceM < 0.02 }
        .map { heat.ok ? heat.fromRef(timeRefMin: $0.midMin, tempC: raceTempC) : $0.midMin }
    let base = plan?.projectedFinal ?? predicted ?? goalMin
    var splits: [(Double, Double)] = []
    if let t = base, race.distanceM >= 10000 {
        let paceMinPerM = t / race.distanceM
        let marks: [Double] = race.distanceM >= MRDistance.dF
            ? [5, 10, 15, 21.0975, 25, 30, 35, 40, 42.195]
            : (race.distanceM >= MRDistance.dH ? [5, 10, 15, 21.0975] : [2, 5, 8, 10])
        splits = marks.filter { $0 * 1000 <= race.distanceM + 1 }
                      .map { ($0, paceMinPerM * $0 * 1000) }
    }

    // 4주 평균 주간거리 — 테이퍼 주차별 권장 거리 계산에 사용
    let cutoff28 = cal.date(byAdding: .day, value: -28, to: asOf)!
    let vol4w = runs.filter { $0.start > cutoff28 }.compactMap(\.distanceKm).reduce(0, +) / 4.0

    let L = AppLanguage.shared
    var lines: [String] = []
    var headline = ""
    var compactLine = ""

    // 계획이 있으면 이번 주의 계획 값을 그대로 말한다 — D-day 카드와 주차 표가 다른 숫자를 내면 안 된다.
    // (10K는 1주 테이퍼라 D-14 주는 "유지"인데, 예전엔 거리와 무관하게 "테이퍼 2주차"라고 했다.)
    let todayWD = cal.component(.weekday, from: asOf)
    let thisMonday = cal.date(byAdding: .day, value: -((todayWD + 5) % 7), to: cal.startOfDay(for: asOf)) ?? asOf
    let planWeek = plan?.weeks.first { cal.isDate($0.monday, inSameDayAs: thisMonday) }
    let inPlanTaper = planWeek?.phase == "테이퍼"

    switch phase {
    case .building:
        headline = "D-\(d)"
        if let p = plan {
            lines.append(L.s("계획대로 쌓으면 \(mrFormatDisplay(p.projectedFinal))입니다.", "On plan: \(mrFormatDisplay(p.projectedFinal)).", ja: "計画どおり積めば\(mrFormatDisplay(p.projectedFinal))です。"))
        }

    case .tapering:
        if let w = planWeek, !inPlanTaper {
            // 계획상 아직 테이퍼가 아닌 주(10K 1주 테이퍼의 D-14 주 등) — 계획 값을 그대로 말한다
            headline = L.s("D-\(d) · 마지막 정상 주", "D-\(d) · Last normal week", ja: "D-\(d) · 最後の通常週")
            let bd = mrBreakdownWithPoint(w)
            lines.append(L.s("이번 주는 계획대로 — \(bd). 테이퍼는 다음 주부터입니다.", "Stick to the plan this week — \(bd). The taper starts next week.", ja: "今週は計画どおり — \(bd)。テーパーは来週からです。"))
            lines.append(L.s("여기서 늘려도 대회 날 몸에 남지 않습니다. 지금까지 쌓은 것이 다입니다.", "Adding more now won't show up on race day. What you've built is what you have.", ja: "ここで増やしてもレース当日の体には残りません。これまで積んだものがすべてです。"))
            if let t = base {
                let pace = t * 60 / (race.distanceM / 1000)
                lines.append(L.s("대회 예상 평균 \(mrFormatPace(pace))/km — 짧은 구간은 이 페이스로 감각을 유지하세요.", "Projected race pace \(mrFormatPace(pace))/km — run short stretches at it to keep the feel.", ja: "レース予測平均 \(mrFormatPace(pace))/km — 短い区間はこのペースで感覚を保ってください。"))
                compactLine = L.s("예상 \(mrFormatPace(pace))/km · 계획대로 \(Int(w.weeklyKm))km, 테이퍼는 다음 주", "Projected \(mrFormatPace(pace))/km · \(Int(w.weeklyKm)) km on plan, taper next week", ja: "予測 \(mrFormatPace(pace))/km · 計画どおり\(Int(w.weeklyKm))km、テーパーは来週")
            }
        } else {
            headline = L.s("D-\(d) · 이제 쌓는 게 아니라 아끼는 시기입니다", "D-\(d) · Time to save it, not build it", ja: "D-\(d) · もう積む時期ではなく温存する時期です")
            lines.append(L.s("거리는 절반 가까이 줄이시되 **페이스는 그대로** 두세요. 완전히 쉬면 오히려 둔해집니다.", "Cut the distance by nearly half but **keep the pace**. Resting completely leaves you sluggish.", ja: "距離は半分近くまで減らし、**ペースはそのまま**にしてください。完全に休むとかえって体が鈍ります。"))
            lines.append(L.s("여기서 늘려도 대회 날 몸에 남지 않습니다. 지금까지 쌓은 것이 다입니다.", "Adding more now won't show up on race day. What you've built is what you have.", ja: "ここで増やしてもレース当日の体には残りません。これまで積んだものがすべてです。"))
            if let w = planWeek {
                lines.append(L.s("이번 주는 계획대로 \(Int(w.weeklyKm))km — \(mrBreakdownWithPoint(w)).", "This week: \(Int(w.weeklyKm)) km on plan — \(mrBreakdownWithPoint(w)).", ja: "今週は計画どおり\(Int(w.weeklyKm))km — \(mrBreakdownWithPoint(w))。"))
            } else {
                // 계획 없음 — 4주 평균 기준 폴백 (2주 테이퍼 첫 주 ~84%)
                lines.append(vol4w >= 5
                    ? L.s("테이퍼 2주차 — 이번 주는 \(Int((vol4w * 0.84).rounded()))km 정도로.", "Two weeks out — about \(Int((vol4w * 0.84).rounded())) km this week.", ja: "テーパー2週目 — 今週は\(Int((vol4w * 0.84).rounded()))kmほどに。")
                    : L.s("테이퍼 2주차 — 이번 주는 평소의 80% 정도로.", "Two weeks out — about 80% of your usual this week.", ja: "テーパー2週目 — 今週は普段の80%ほどに。"))
            }
            // 페이스는 2주 전부터 — "페이스는 그대로"의 그 페이스가 몇인지. 스플릿 표는 D-7부터(뷰).
            if let t = base {
                let pace = t * 60 / (race.distanceM / 1000)
                lines.append(L.s("대회 예상 평균 \(mrFormatPace(pace))/km — 테이퍼 러닝의 짧은 구간은 이 페이스로.", "Projected race pace \(mrFormatPace(pace))/km — run short stretches of your taper runs at it.", ja: "レース予測平均 \(mrFormatPace(pace))/km — テーパー中のランの短い区間はこのペースで。"))
                compactLine = L.s("예상 \(mrFormatPace(pace))/km · 거리는 줄이고 페이스는 그대로", "Projected \(mrFormatPace(pace))/km · less distance, same pace", ja: "予測 \(mrFormatPace(pace))/km · 距離は減らしペースはそのまま")
            }
        }

    case .finalWeek:
        headline = L.s("D-\(d) · 마지막 한 주", "D-\(d) · Final week", ja: "D-\(d) · 最後の1週間")
        lines.append(L.s("새 최장 롱런은 하지 마세요. 이 시점의 롱런은 이득 없이 회복만 잡아먹습니다.", "No new longest long run. A long run this late costs recovery and gains nothing.", ja: "最長を更新するロング走はしないでください。この時期のロング走は得るものがなく、回復を削るだけです。"))
        lines.append(L.s("대회에서 쓸 젤과 음료를 이번 주 러닝에서 한 번 미리 써보세요. 당일 처음 시도하면 안 됩니다.", "Try the gels and drinks you'll race with on one run this week. Nothing new on race day.", ja: "レースで使うジェルとドリンクを今週のランで一度試してください。当日に初めて試すのは避けてください。"))
        if let t = base, t >= 150 {
            lines.append(L.s("보급은 탄수화물 시간당 \(t >= 150 ? "60~90g" : "30~60g")(젤 1개 ≈ 22~25g) — 젤은 30분마다, 사이사이 음료로 채우세요.", "Fuel: \(t >= 150 ? "60–90 g" : "30–60 g") of carbs per hour (one gel ≈ 22–25 g), a gel every 30 min, topped up with drink in between.", ja: "補給は炭水化物を1時間あたり\(t >= 150 ? "60~90g" : "30~60g")(ジェル1個 ≈ 22~25g) — ジェルは30分ごとに、合間はドリンクで補ってください。"))
        }
        if let w = planWeek {
            lines.append(L.s("이번 주는 계획대로 \(Int(w.weeklyKm))km — \(mrBreakdownWithPoint(w)).", "This week: \(Int(w.weeklyKm)) km on plan — \(mrBreakdownWithPoint(w)).", ja: "今週は計画どおり\(Int(w.weeklyKm))km — \(mrBreakdownWithPoint(w))。"))
        } else {
            // 계획 없음 — 4주 평균 기준 폴백 (마지막 주 ~51%)
            lines.append(vol4w >= 5
                ? L.s("테이퍼 1주차 — 이번 주는 \(Int((vol4w * 0.51).rounded()))km 정도로.", "Race week — about \(Int((vol4w * 0.51).rounded())) km this week.", ja: "テーパー1週目 — 今週は\(Int((vol4w * 0.51).rounded()))kmほどに。")
                : L.s("테이퍼 1주차 — 이번 주는 평소의 50% 정도로.", "Race week — about 50% of your usual this week.", ja: "テーパー1週目 — 今週は普段の50%ほどに。"))
        }
        // 마지막 한 주는 배분을 정하는 시기 — 전날에야 숫자를 주면 늦다. 첫 5km 상한은 당일과 같은 2%.
        if let t = base {
            let pace = t * 60 / (race.distanceM / 1000)
            lines.append(L.s("예상 평균 \(mrFormatPace(pace))/km · 첫 5km는 \(mrFormatPace(pace * 0.98))/km보다 빠르지 않게. 아래 배분은 처음부터 끝까지 같은 페이스입니다.", "Projected average \(mrFormatPace(pace))/km · first 5 km no faster than \(mrFormatPace(pace * 0.98))/km. The splits below are even pace start to finish.", ja: "予測平均 \(mrFormatPace(pace))/km · 最初の5kmは\(mrFormatPace(pace * 0.98))/kmより速くしないこと。下の配分は最初から最後まで同じペースです。"))
            compactLine = L.s("예상 \(mrFormatPace(pace))/km · 첫 5km는 \(mrFormatPace(pace * 0.98)) 이내 · 젤은 미리 연습", "Projected \(mrFormatPace(pace))/km · first 5 km within \(mrFormatPace(pace * 0.98)) · practice your gels", ja: "予測 \(mrFormatPace(pace))/km · 最初の5kmは\(mrFormatPace(pace * 0.98))以内 · ジェルは事前に練習")
        }

    case .eve:
        headline = L.s("내일입니다", "Tomorrow", ja: "明日です")
        lines.append(L.s("오늘은 20~30분 가볍게 몸만 풀거나, 쉬셔도 됩니다.", "Today, 20–30 easy minutes to loosen up — or just rest.", ja: "今日は20~30分軽く体をほぐすか、休んでも大丈夫です。"))
        lines.append(L.s("짐은 오늘 싸두세요 — 배번, 젤, 물, 옷, 신발.", "Pack today — bib, gels, water, clothes, shoes.", ja: "荷物は今日まとめておいてください — ゼッケン、ジェル、水、ウェア、シューズ。"))
        if let t = base {
            let pace = t * 60 / (race.distanceM / 1000)
            lines.append(L.s("예상 평균 \(mrFormatPace(pace))/km입니다. 첫 5km는 여기서 **더 빠르지 않게**.", "Projected average \(mrFormatPace(pace))/km. For the first 5 km, **no faster than this**.", ja: "予測平均 \(mrFormatPace(pace))/kmです。最初の5kmはこれより**速くしないこと**。"))
        }

    case .raceDay:
        headline = L.s("오늘입니다", "Today", ja: "今日です")
        if let t = base {
            let pace = t * 60 / (race.distanceM / 1000)
            let cap = pace * 0.98
            // ⚠ 이 앱이 대회 당일 할 수 있는 가장 중요한 말이다.
            //   Smyth 2018 (J Sports Analytics 4(3), n=1,724,109):
            //   첫 5km를 10% 빠르게 가면 완주 시간 평균 +37분.
            //   세 명 중 한 명(33%)이 첫 5km를 가장 빠른 구간으로 달렸고,
            //   이들의 평균 과속률은 12%였다.
            lines.append(L.s("첫 5km를 \(mrFormatPace(cap))/km보다 빠르게 가지 마세요.", "Don't run the first 5 km faster than \(mrFormatPace(cap))/km.", ja: "最初の5kmを\(mrFormatPace(cap))/kmより速く走らないでください。"))
            lines.append(L.s("172만 명 기록에서 초반 10% 과속은 완주 시간을 평균 37분 늘렸습니다. 세 명 중 한 명이 첫 5km를 가장 빠르게 달립니다.", "Across 1.72 million finishes, starting 10% too fast added 37 minutes on average. One in three runners runs their fastest 5 km first.", ja: "172万人の記録では、序盤10%のオーバーペースで完走タイムが平均37分延びました。3人に1人が最初の5kmを一番速く走っています。"))
            // ■1 균등 배분 설명 — 배분표가 같은 페이스임을 명시, 네거티브 스플릿 암시 제거
            lines.append(L.s("위 배분은 처음부터 끝까지 같은 페이스입니다. 초반에 빨라지는 쪽이 후반 감속으로 돌아옵니다.", "The splits above are even pace start to finish. Speed spent early comes back as a late slowdown.", ja: "上の配分は最初から最後まで同じペースです。序盤に速くした分は後半の失速として返ってきます。"))
        }

    case .recovery:
        // done은 phase 결정 시 guard로 검증됐으므로 nil이 아니다
        let run = done!
        let ago = -d
        let time = mrFormatDisplay(run.durationMin)
        headline = "\(race.name) \(time)"

        // 목표가 있었으면 결과를 함께 말한다. 판정이 아니라 사실로.
        if let g = goalMin {
            let diff = run.durationMin - g
            lines.append(diff <= 0
                ? L.s("목표 \(mrFormatDisplay(g))보다 \(mrFormatDisplay(-diff)) 빨랐습니다.", "\(mrFormatDisplay(-diff)) faster than your goal of \(mrFormatDisplay(g)).", ja: "目標\(mrFormatDisplay(g))より\(mrFormatDisplay(-diff))速く走りました。")
                : L.s("목표 \(mrFormatDisplay(g))에서 \(mrFormatDisplay(diff)) 차이였습니다.", "\(mrFormatDisplay(diff)) off your goal of \(mrFormatDisplay(g)).", ja: "目標\(mrFormatDisplay(g))との差は\(mrFormatDisplay(diff))でした。"))
        }
        // 예측이 얼마나 맞았는지 — 이 앱이 스스로를 검증하는 자리다
        if let p = base {
            let err = (p - run.durationMin) / run.durationMin * 100
            lines.append(String(format: L.s("이 앱은 %@로 봤습니다 (%+.1f%%).", "This app predicted %@ (%+.1f%%).", ja: "このアプリの予測は%@でした (%+.1f%%)。"),
                                mrFormatDisplay(p), err))
        }

        if race.distanceM >= MRDistance.dF {
            lines.append(L.s("마라톤 뒤에는 근육이 회복되는 데 2주쯤 걸립니다. 지금 기록이 잘 안 나와도 정상입니다.", "Muscles take about two weeks to recover after a marathon. Slow times right now are normal.", ja: "マラソンの後は筋肉の回復に2週間ほどかかります。今タイムが出なくても正常です。"))
            lines.append(ago <= 3 ? L.s("며칠은 걷기나 아주 가벼운 조깅만으로 충분합니다.", "For a few days, walking or very easy jogging is plenty.", ja: "数日はウォーキングかごく軽いジョグで十分です。")
                                  : L.s("슬슬 이지 러닝으로 돌아오셔도 됩니다. 강도는 다음 주부터.", "You can ease back into easy runs. Intensity from next week.", ja: "そろそろイージーランに戻って大丈夫です。強度は来週から。"))
        } else {
            lines.append(L.s("며칠은 가볍게 가시면 됩니다.", "Keep it easy for a few days.", ja: "数日は軽めにしてください。"))
        }
        lines.append(L.s("이 기록이 다음 예상에 반영됩니다.", "This result feeds into your next prediction.", ja: "この記録は次の予測に反映されます。"))
        splits = []      // 끝난 대회에 스플릿은 필요 없다
    }

    // ■2 목표-예상 차이를 구간별로 정직하게 표현 (finalWeek·eve·raceDay)
    // ≤0%: 달성 예상 / ≤3%: 사정권 / ≤8%: 부족분 있음 / >8%: 거리 있음
    // ⚠ base가 goalMin 자체로 낙착한 경우(예측·계획 모두 없음)는 gap=0이므로
    //   p < g(gapPct < 0)일 때만 "목표 안에 들어옵니다"를 표시한다.
    if let g = goalMin, let p = base {
        let gapPct = (p - g) / g * 100
        switch phase {
        case .finalWeek, .eve, .raceDay:
            if gapPct < 0 {
                lines.append(L.s("목표 안에 들어옵니다.", "You're inside your goal.", ja: "目標圏内です。"))
            } else if gapPct <= 3 {
                lines.append(L.s("사정권입니다. 당일 컨디션에 따라 갈립니다.", "Within range — race-day conditions will decide.", ja: "射程圏内です。当日のコンディション次第です。"))
                // "30km 지나서" 조언은 마라톤에만 적용
                if race.distanceM >= MRDistance.dF {
                    lines.append(L.s("몸이 좋으면 30km 지나서 올리시면 됩니다 — 반대는 되돌릴 수 없습니다.", "If you feel good, pick it up after 30 km — the other way round can't be undone.", ja: "調子がよければ30km以降で上げてください — 逆は取り返せません。"))
                }
            } else if gapPct <= 8 {
                lines.append(L.s("입력하신 목표는 \(mrFormatDisplay(g))인데 지금 몸으로는 \(mrFormatDisplay(p)) 부근입니다. 부족분이 있습니다. 이 배분으로 완주부터 확보하시죠.", "Your goal is \(mrFormatDisplay(g)), but your current fitness points to around \(mrFormatDisplay(p)). There's a gap — secure the finish with these splits first.", ja: "入力した目標は\(mrFormatDisplay(g))ですが、今の体では\(mrFormatDisplay(p))前後です。不足分があります。この配分でまず完走を確保しましょう。"))
            } else {
                lines.append(L.s("입력하신 목표는 \(mrFormatDisplay(g))인데 지금 몸으로는 \(mrFormatDisplay(p)) 부근입니다. 이번 대회에서 목표까지는 거리가 있습니다. 오늘 배분은 완주 기준입니다.", "Your goal is \(mrFormatDisplay(g)), but your current fitness points to around \(mrFormatDisplay(p)). The goal is a stretch for this race — today's splits are set for finishing.", ja: "入力した目標は\(mrFormatDisplay(g))ですが、今の体では\(mrFormatDisplay(p))前後です。今回のレースで目標までは距離があります。今日の配分は完走基準です。"))
            }
        default: break
        }
    }

    // ■2 순서: "좋은 레이스 되세요"는 목표 대비 부족 문구 뒤에 붙는 마지막 인사
    if case .raceDay = phase {
        lines.append(L.s("좋은 레이스 되세요.", "Have a great race.", ja: "良いレースを。"))
    }

    return MRRaceDayCard(race: race, phase: phase, daysLeft: d,
                         headline: headline, lines: lines, splits: splits,
                         compactLine: compactLine)
}
