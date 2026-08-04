import Foundation
import SwiftData

// MARK: - 주차 이행 기호

private let symbolBoth = "●"
private let symbolOne  = "◐"
private let symbolNone = "○"
private let symbolOver = "▲"

private func weekSymbol(plan: MRPlanWeekSummary, actualLong: Double, actualWeekly: Double) -> String {
    if actualLong > plan.longRunKm * 1.10 { return symbolOver }
    let longOk   = actualLong   >= plan.longRunKm
    let weeklyOk = actualWeekly >= plan.weeklyKm
    if longOk && weeklyOk { return symbolBoth }
    if longOk || weeklyOk { return symbolOne  }
    return symbolNone
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
