import Foundation
import SwiftData

// MARK: - 주차 이행 기호

let symbolBoth = "●"
let symbolOne  = "◐"
let symbolNone = "○"
let symbolOver = "▲"

func weekSymbol(plan: MRPlanWeekSummary, actualLong: Double, actualWeekly: Double) -> String {
    if actualLong > plan.longRunKm * 1.10 { return symbolOver }
    let longOk   = actualLong   >= plan.longRunKm
    let weeklyOk = actualWeekly >= plan.weeklyKm
    if longOk && weeklyOk { return symbolBoth }
    if longOk || weeklyOk { return symbolOne  }
    return symbolNone
}

// MARK: - 레이블 ↔ 거리 역변환 (소급 생성용)

func mrDistanceForLabel(_ label: String) -> Double {
    switch label {
    case "5K":  return MRDistance.d5
    case "10K": return MRDistance.d10
    case "하프": return MRDistance.dH
    case "풀":  return MRDistance.dF
    default:    return 0
    }
}

// MARK: - 계획 스냅샷 생성

/// check에서 RacePlanSnapshot에 필요한 값들을 추출한다.
func mrBuildSnapshotData(check: MRGoalCheck) -> (
    projectedFinalMin: Double, projectedNowMin: Double,
    goalMin: Double, weeksJSON: String, metaJSON: String
) {
    let plan = check.plan
    let weeksData = plan.weeks.map { w in
        MRPlanWeekSummary(idx: w.idx, monday: w.monday,
                          phase: w.phase, longRunKm: w.longRunKm, weeklyKm: w.weeklyKm)
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let weeksJSON = (try? encoder.encode(weeksData)).flatMap { String(data: $0, encoding: .utf8) } ?? ""

    let meta: [String: String] = [
        "modelVersion": "m\(MRModelVersion.current)",
        "totalWeeks": "\(plan.weeks.count)",
        "peakWeeklyKm": String(format: "%.1f", plan.peakWeeklyKm),
        "reachableLongKm": String(format: "%.1f", plan.reachableLongKm),
        "projectedNow": String(format: "%.2f", plan.projectedNow),
        "projectedFinal": String(format: "%.2f", plan.projectedFinal),
    ]
    let metaJSON = (try? encoder.encode(meta)).flatMap { String(data: $0, encoding: .utf8) } ?? ""

    return (plan.projectedFinal, plan.projectedNow,
            check.goalMin ?? 0, weeksJSON, metaJSON)
}

// MARK: - 아카이브 마크다운 생성

func mrBuildArchiveMarkdown(
    snapshot: RacePlanSnapshot,
    actualMin: Double?,
    preRaceProjectedMin: Double?,
    runs: [MRWorkout]
) -> String {
    let cal = Calendar.current
    let dateFmt = DateFormatter()
    dateFmt.locale = Locale(identifier: "ko_KR")
    dateFmt.dateFormat = "yyyy-MM-dd"

    let weekFmt = DateFormatter()
    weekFmt.locale = Locale(identifier: "ko_KR")
    weekFmt.dateFormat = "MM/dd"

    let raceDateStr     = dateFmt.string(from: snapshot.raceDate)
    let snapshotDateStr = dateFmt.string(from: snapshot.createdAt)

    var md = "# \(snapshot.raceName) · \(raceDateStr)\n\n"
    if let a = actualMin {
        md += "실제  \(mrFormatDisplay(a))\n"
    } else {
        md += "실제  기록 없음\n"
    }
    md += "계획 시작 시점 예측  \(mrFormatDisplay(snapshot.projectedFinalMin)) (\(snapshotDateStr))\n"
    if let pre = preRaceProjectedMin {
        md += "대회 직전 예측  \(mrFormatDisplay(pre))\n"
    }
    md += "\n"

    // 주차별 이행 표
    let planWeeks = snapshot.planWeeks
    guard !planWeeks.isEmpty else {
        return md + appendMeta(snapshot: snapshot, actualMin: actualMin)
    }

    // 대회일 기준 과거 주만
    let raceDayStart = cal.startOfDay(for: snapshot.raceDate)
    let pastWeeks = planWeeks.filter { w in
        let weekEnd = cal.date(byAdding: .day, value: 7,
                               to: cal.startOfDay(for: w.monday))!
        return weekEnd <= raceDayStart
    }

    if !pastWeeks.isEmpty {
        md += "## 주차별 계획과 이행\n\n"
        md += "  주   날짜    단계          롱런(계획/실제)   주간(계획/실제)\n"

        var hitBoth = 0, hitOne = 0, hitNone = 0, over = 0

        for w in pastWeeks {
            let weekStart = cal.startOfDay(for: w.monday)
            let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart)!
            let weekRuns  = runs.filter { $0.start >= weekStart && $0.start < weekEnd }
            let actualLong   = weekRuns.compactMap(\.distanceKm).max() ?? 0
            let actualWeekly = weekRuns.compactMap(\.distanceKm).reduce(0, +)

            let sym = weekSymbol(plan: w, actualLong: actualLong, actualWeekly: actualWeekly)
            switch sym {
            case symbolBoth: hitBoth += 1
            case symbolOne:  hitOne  += 1
            case symbolNone: hitNone += 1
            default:         over    += 1
            }

            let phase = w.phase.count <= 6 ? w.phase.padding(toLength: 6, withPad: " ", startingAt: 0)
                                           : String(w.phase.prefix(6))
            md += String(format: "%@ %2d  %@  %@  %4.1f / %-4.1f     %3.0f / %.0f\n",
                         sym, w.idx,
                         weekFmt.string(from: w.monday),
                         phase,
                         w.longRunKm, actualLong,
                         w.weeklyKm,  actualWeekly)
        }

        let total = planWeeks.count
        md += String(format: "\n계획 %d주 중 %@ %d · %@ %d · %@ %d · %@ %d\n\n",
                     total, symbolBoth, hitBoth, symbolOne, hitOne,
                     symbolNone, hitNone, symbolOver, over)
    }

    md += appendMeta(snapshot: snapshot, actualMin: actualMin)
    return md
}

private func appendMeta(snapshot: RacePlanSnapshot, actualMin: Double?) -> String {
    var s = "\n<!-- MIMO-META\n"
    s += "modelVersion: m\(MRModelVersion.current)\n"
    s += String(format: "distanceM: %.0f\n", snapshot.distanceM)
    s += String(format: "snapshotProjectedFinal: %.2f\n", snapshot.projectedFinalMin)
    if let a = actualMin { s += String(format: "actualMin: %.2f\n", a) }
    s += "-->"
    return s
}

// MARK: - 대회일 실제 기록 찾기

/// engine.runs에서 대회일 당일 기록 중 거리가 가장 가까운 워크아웃을 찾는다.
func mrFindRaceDayRun(runs: [MRWorkout], raceDate: Date, distanceM: Double) -> MRWorkout? {
    let cal = Calendar.current
    let candidates = runs.filter {
        !$0.isInterval &&
        cal.isDate($0.start, inSameDayAs: raceDate) &&
        ($0.distanceKm ?? 0) > 0
    }
    return candidates.min {
        abs(($0.distanceKm ?? 0) - distanceM / 1000) <
        abs(($1.distanceKm ?? 0) - distanceM / 1000)
    }
}

// MARK: - 스냅샷·아카이브 키

func mrArchiveKey(raceDate: Date, distanceM: Double) -> String {
    "\(Int(raceDate.timeIntervalSince1970))-\(Int(distanceM))"
}

// MARK: - 중복 스냅샷 정리 (CloudKit 경쟁 조건 방어)

func mrDeduplicateSnapshots(_ snapshots: [RacePlanSnapshot],
                             context: ModelContext) {
    var seen: [String: RacePlanSnapshot] = [:]
    for snap in snapshots.sorted(by: { $0.createdAt < $1.createdAt }) {
        let key = mrArchiveKey(raceDate: snap.raceDate, distanceM: snap.distanceM)
        if seen[key] == nil {
            seen[key] = snap
        } else {
            context.delete(snap)
        }
    }
}

func mrDeduplicateArchives(_ archives: [RaceArchive],
                            context: ModelContext) {
    var seen: [String: RaceArchive] = [:]
    for arch in archives.sorted(by: { $0.createdAt < $1.createdAt }) {
        let key = mrArchiveKey(raceDate: arch.raceDate, distanceM: arch.distanceM)
        if seen[key] == nil {
            seen[key] = arch
        } else {
            context.delete(arch)
        }
    }
}

// MARK: - 소급 아카이브 생성 (디버그 전용)

/// 백테스트의 마지막 N건에 대해 소급 아카이브를 만든다.
/// 대회 당시에는 계획 기능이 없었을 때 과거를 재구성하는 용도.
/// 이미 아카이브가 있는 대회는 건너뛴다.
func mrCreateRetroactiveArchives(
    backtestRows: [MRBacktestRow],
    runs: [MRWorkout],
    rhrSamples: [(date: Date, value: Double)],
    dateOfBirth: Date?,
    sex: MRSex,
    heat: MRHeatModel,
    confirmedMatches: [PersistedRaceMatch],
    existingArchiveKeys: Set<String>,
    context: ModelContext,
    maxCount: Int = 3
) -> String {
    let cal = Calendar.current
    let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    let scored = backtestRows.filter { $0.predictedMin != nil }.sorted { $0.date < $1.date }
    let targets = Array(scored.suffix(maxCount))

    var logLines: [String] = []
    var count = 0

    for row in targets {
        let distM = mrDistanceForLabel(row.label)
        guard distM > 0 else { continue }

        let key = mrArchiveKey(raceDate: row.date, distanceM: distM)
        guard !existingArchiveKeys.contains(key) else {
            logLines.append("  → \(dateFmt.string(from: row.date)) \(row.label) — 이미 존재, 건너뜀")
            continue
        }

        // 레이스 이름: 확인된 매칭에서 찾기, 없으면 레이블+날짜
        let raceName: String = confirmedMatches.first {
            $0.isConfirmed && cal.isDate($0.raceDate, inSameDayAs: row.date)
        }?.raceName ?? "\(row.label) \(dateFmt.string(from: row.date))"

        let asOf = cal.date(byAdding: .day, value: -1, to: row.date)!
        let pastRuns = runs.filter { $0.start <= asOf }

        let phys2 = mrPhysiology(runs: pastRuns, restingHRSamples: rhrSamples,
                                  dateOfBirth: dateOfBirth, sex: sex, asOf: asOf)
        let prior = mrApplyHeat(mrDetectEfforts(runs: pastRuns, phys: phys2), heat: heat)
                        .filter { $0.date < row.date }
        let fit2  = mrFitExponent(prior)
        let prof2 = mrProfile(runs: pastRuns, efforts: prior, asOf: asOf)
        let preds2 = mrPredict(efforts: prior, fit: fit2, profile: prof2, heat: heat, asOf: asOf)
        let hrp2   = mrFitHRPaceModel(runs: pastRuns, asOf: asOf)
        let easyPace2 = phys2.easyCeilingHR.flatMap { hrp2.paceAtHR($0) }
        let halfEquiv = preds2.first { $0.label == "하프" }?.midMin ?? 0

        guard let plan = mrBuildPlan(
            raceDate: row.date,
            distanceM: distM,
            today: asOf,
            profile: prof2,
            halfEquivMin: halfEquiv,
            easyPaceSecPerKm: easyPace2,
            heat: heat,
            raceTempC: MR_REF_TEMP,
            runsPerWeek: prof2.runsPerWeek
        ) else {
            logLines.append("  → \(row.label) \(dateFmt.string(from: row.date)) — 계획 불가 (준비기간 3주 미만)")
            continue
        }

        // 주차 요약 JSON
        let planWeeks = plan.weeks.map { w in
            MRPlanWeekSummary(idx: w.idx, monday: w.monday,
                              phase: w.phase, longRunKm: w.longRunKm, weeklyKm: w.weeklyKm)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let weeksJSON = (try? encoder.encode(planWeeks)).flatMap { String(data: $0, encoding: .utf8) } ?? ""

        // 임시 스냅샷 (context 삽입 없음 — 마크다운 빌드용)
        let snap = RacePlanSnapshot(
            raceDate: row.date, raceName: raceName, distanceM: distM,
            projectedFinalMin: plan.projectedFinal, projectedNowMin: plan.projectedNow,
            goalMin: 0, weeksJSON: weeksJSON, metaJSON: ""
        )

        var md = mrBuildArchiveMarkdown(
            snapshot: snap, actualMin: row.actualMin,
            preRaceProjectedMin: nil, runs: runs
        )
        // 소급 재구성임을 명시
        let note = "> 이 계획은 나중에 소급 재구성한 것입니다.\n> 대회 당시에는 앱에 계획 기능이 없었습니다.\n\n"
        md = note + md

        let archive = RaceArchive(
            raceDate: row.date, raceName: raceName, distanceM: distM,
            markdown: md, hasResult: true, actualMin: row.actualMin,
            snapshotProjectedFinalMin: plan.projectedFinal, reconstructed: true
        )
        context.insert(archive)
        count += 1

        // 이행 통계 집계
        var hitBoth = 0, hitOne = 0, hitNone = 0, hitOver = 0
        let raceDayStart = cal.startOfDay(for: row.date)
        for w in planWeeks {
            let weekStart = cal.startOfDay(for: w.monday)
            let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart)!
            guard weekEnd <= raceDayStart else { break }
            let weekRuns    = runs.filter { $0.start >= weekStart && $0.start < weekEnd }
            let actualLong  = weekRuns.compactMap(\.distanceKm).max() ?? 0
            let actualTotal = weekRuns.compactMap(\.distanceKm).reduce(0, +)
            switch weekSymbol(plan: w, actualLong: actualLong, actualWeekly: actualTotal) {
            case symbolBoth: hitBoth += 1
            case symbolOne:  hitOne  += 1
            case symbolNone: hitNone += 1
            default:         hitOver += 1
            }
        }
        logLines.append(
            "[아카이브] \(dateFmt.string(from: row.date)) \(raceName) · \(plan.weeks.count)주 · \(symbolBoth) \(hitBoth) \(symbolOne) \(hitOne) \(symbolNone) \(hitNone) \(symbolOver) \(hitOver)"
        )
    }

    return (["[아카이브] 소급 \(count)건 생성"] + logLines).joined(separator: "\n")
}
