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
        switch self {
        case .building:  return "쌓는 시기"
        case .tapering:  return "이제 아끼는 시기"
        case .finalWeek: return "마지막 한 주"
        case .eve:       return "내일입니다"
        case .raceDay:   return "오늘입니다"
        case .recovery:  return "회복 중"
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

    var lines: [String] = []
    var headline = ""

    switch phase {
    case .building:
        headline = "D-\(d)"
        if let p = plan {
            lines.append("계획대로 쌓으면 \(mrFormatDisplay(p.projectedFinal))입니다.")
        }

    case .tapering:
        headline = "D-\(d) · 이제 쌓는 게 아니라 아끼는 시기입니다"
        lines.append("거리는 절반 가까이 줄이시되 **페이스는 그대로** 두세요. 완전히 쉬면 오히려 둔해집니다.")
        lines.append("여기서 늘려도 대회 날 몸에 남지 않습니다. 지금까지 쌓은 것이 다입니다.")

    case .finalWeek:
        headline = "D-\(d) · 마지막 한 주"
        lines.append("새 최장 롱런은 하지 마세요. 이 시점의 롱런은 이득 없이 회복만 잡아먹습니다.")
        lines.append("대회에서 쓸 젤과 음료를 이번 주 러닝에서 한 번 미리 써보세요. 당일 처음 시도하면 안 됩니다.")
        if let t = base, t >= 150 {
            lines.append("보급은 시간당 \(t >= 150 ? "60~90g" : "30~60g") — 15~20분 간격으로 나누시고요.")
        }

    case .eve:
        headline = "내일입니다"
        lines.append("오늘은 20~30분 가볍게 몸만 풀거나, 쉬셔도 됩니다.")
        lines.append("짐은 오늘 싸두세요 — 배번, 젤, 물, 옷, 신발.")
        if let t = base {
            let pace = t * 60 / (race.distanceM / 1000)
            lines.append("예상 평균 \(mrFormatPace(pace))/km입니다. 첫 5km는 여기서 **더 빠르지 않게**.")
        }

    case .raceDay:
        headline = "오늘입니다"
        if let t = base {
            let pace = t * 60 / (race.distanceM / 1000)
            let cap = pace * 0.98
            // ⚠ 이 앱이 대회 당일 할 수 있는 가장 중요한 말이다.
            //   Smyth 2018 (n=1,724,109): 첫 5km를 10% 빠르게 가면 **+37분**.
            //   3%만 넘어도 약 11분이다. 대부분의 완주자가 여기서 무너진다.
            lines.append("첫 5km를 \(mrFormatPace(cap))/km보다 빠르게 가지 마세요.")
            lines.append("172만 명 기록에서 초반 10% 과속은 완주 시간을 평균 37분 늘렸습니다. 3%만 넘어도 11분입니다.")
            lines.append("예상 평균은 \(mrFormatPace(pace))/km. 초반에 아낀 것은 후반에 돌아옵니다.")
        }
        lines.append("좋은 레이스 되세요.")

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
                ? "목표 \(mrFormatDisplay(g))보다 \(mrFormatDisplay(-diff)) 빨랐습니다."
                : "목표 \(mrFormatDisplay(g))에서 \(mrFormatDisplay(diff)) 차이였습니다.")
        }
        // 예측이 얼마나 맞았는지 — 이 앱이 스스로를 검증하는 자리다
        if let p = base {
            let err = (p - run.durationMin) / run.durationMin * 100
            lines.append(String(format: "이 앱은 %@로 봤습니다 (%+.1f%%).",
                                mrFormatDisplay(p), err))
        }

        if race.distanceM >= MRDistance.dF {
            lines.append("마라톤 뒤에는 근육이 회복되는 데 2주쯤 걸립니다. 지금 기록이 잘 안 나와도 정상이에요.")
            lines.append(ago <= 3 ? "며칠은 걷기나 아주 가벼운 조깅만으로 충분합니다."
                                  : "슬슬 이지 러닝으로 돌아오셔도 됩니다. 강도는 다음 주부터.")
        } else {
            lines.append("며칠은 가볍게 가시면 됩니다.")
        }
        lines.append("이 기록이 다음 예상에 반영됩니다.")
        splits = []      // 끝난 대회에 스플릿은 필요 없다
    }

    // 목표가 예상보다 3% 이상 빠르면: 배분 기준이 후자임을 명시
    // (finalWeek·eve·raceDay에서만 — splits가 실제로 표시되는 단계)
    if let g = goalMin, let p = base, (p - g) / g > 0.03 {
        switch phase {
        case .finalWeek, .eve, .raceDay:
            lines.append("입력하신 목표는 \(mrFormatDisplay(g))인데, 지금 몸으로는 "
                + "\(mrFormatDisplay(p)) 부근입니다. 위 배분은 후자 기준입니다. "
                + "몸이 좋으면 30km 지나서 올리시면 됩니다 — 반대는 되돌릴 수 없습니다.")
        default: break
        }
    }

    return MRRaceDayCard(race: race, phase: phase, daysLeft: d,
                         headline: headline, lines: lines, splits: splits)
}
