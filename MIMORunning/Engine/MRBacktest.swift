import Foundation

/// 과거 대회급 노력을, **그 직전 데이터만으로** 예측했다면 얼마였을까.
///
/// 이 화면이 필요한 이유:
///   앱이 "4:25:25"라고 말해도 사용자에게는 믿을 근거가 없다.
///   과거를 얼마나 맞혔는지가 유일한 근거다.
///   ⚠ 틀린 것도 반드시 같이 보여준다. 맞은 것만 고르면 그건 광고다.
struct MRBacktestRow: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let actualMin: Double
    let predictedMin: Double?
    let loMin: Double?
    let hiMin: Double?
    let priorCount: Int

    var errorPct: Double? {
        guard let p = predictedMin else { return nil }
        return (p - actualMin) / actualMin * 100
    }
    var inBand: Bool {
        guard let lo = loMin, let hi = hiMin else { return false }
        return actualMin >= lo && actualMin <= hi
    }
}

func mrBacktest(runs: [MRWorkout],
                restingHRSamples: [(date: Date, value: Double)],
                dateOfBirth: Date?,
                sex: MRSex,
                heat: MRHeatModel,
                additionalTargets: [MRRaceEffort] = [],
                asOf: Date) -> [MRBacktestRow] {

    let cal = Calendar.current

    // 자동 감지 타겟
    let physNow = mrPhysiology(runs: runs, restingHRSamples: restingHRSamples,
                               dateOfBirth: dateOfBirth, sex: sex, asOf: asOf)
    let autoTargets = mrApplyHeat(mrDetectEfforts(runs: runs, phys: physNow), heat: heat)

    // 확인된 대회가 있는 날은 자동 감지를 제외 (중복 방지)
    let confirmedDays = Set(additionalTargets.map { cal.startOfDay(for: $0.date) })
    let targets = (mrApplyHeat(additionalTargets, heat: heat)
                   + autoTargets.filter { !confirmedDays.contains(cal.startOfDay(for: $0.date)) })
        .sorted { $0.date < $1.date }

    let standardDistances: [String: Double] = [
        "5K": MRDistance.d5, "10K": MRDistance.d10,
        "하프": MRDistance.dH, "풀": MRDistance.dF
    ]

    var rows: [MRBacktestRow] = []
    for t in targets {
        // 표준 거리만. 12.4K 같은 건 목표 자체가 없다.
        guard let label = standardDistances
            .first(where: { abs($0.value - t.distanceM) / $0.value <= 0.02 })?.key
        else { continue }

        // ★ 그 대회 **전날**을 기준일로 삼는다.
        //   여기서 날짜 필터에 하한이 없으면 미래 데이터가 새어 들어온다.
        //   (파이썬에서 실제로 터졌던 버그다 — 마라톤 오차가 −19%였다)
        let y = cal.date(byAdding: .day, value: -1, to: t.date)!
        let pastRuns = runs.filter { $0.date <= y }

        let phys2 = mrPhysiology(runs: pastRuns, restingHRSamples: restingHRSamples,
                                 dateOfBirth: dateOfBirth, sex: sex, asOf: y)
        let prior = mrApplyHeat(mrDetectEfforts(runs: pastRuns, phys: phys2), heat: heat)
                        .filter { $0.date < t.date }

        guard prior.count >= 3 else {
            rows.append(MRBacktestRow(date: t.date, label: label,
                                      actualMin: t.timeMin, predictedMin: nil,
                                      loMin: nil, hiMin: nil, priorCount: prior.count))
            continue
        }

        let fit2 = mrFitExponent(prior)
        let prof2 = mrProfile(runs: pastRuns, efforts: prior, asOf: y)
        // 그날 실제 기온으로 예측한다 (기온까지 맞혔는지 보려는 게 아니라,
        // 기온을 아는 상태에서 얼마나 맞혔는지를 보려는 것이다)
        let temp = runs.first { cal.isDate($0.date, inSameDayAs: t.date) && $0.tempC != nil }?.tempC
                   ?? MR_REF_TEMP
        let p = mrPredict(efforts: prior, fit: fit2, profile: prof2,
                          heat: heat, asOf: y, targetTempC: temp)
                   .first { $0.label == label }

        rows.append(MRBacktestRow(date: t.date, label: label, actualMin: t.timeMin,
                                  predictedMin: p?.midMin, loMin: p?.loMin,
                                  hiMin: p?.hiMin, priorCount: prior.count))
    }
    return rows.sorted { $0.date < $1.date }
}
