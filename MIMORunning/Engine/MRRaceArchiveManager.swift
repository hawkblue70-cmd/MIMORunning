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
                          phase: w.phase, longRunKm: w.longRunKm, weeklyKm: w.weeklyKm,
                          breakdown: w.breakdown)
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
        "targetLongKm": String(format: "%.1f", plan.targetLongKm),
        "startingLongKm": String(format: "%.2f", plan.startingLongKm),
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
                               to: cal.startOfDay(for: w.monday)) ?? cal.startOfDay(for: w.monday)
        return weekEnd <= raceDayStart
    }

    if !pastWeeks.isEmpty {
        md += mrArchiveWeeklySectionHeader + "\n\n"
        md += "  주   날짜    단계          롱런(계획/실제)   주간(계획/실제)\n"

        var hitBoth = 0, hitOne = 0, hitNone = 0, over = 0

        for w in pastWeeks {
            let weekStart = cal.startOfDay(for: w.monday)
            let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
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

/// 주차별 이행표 섹션 머리말. 상세를 열어 볼 가치가 있는지 판정할 때도 이 값을 쓴다.
let mrArchiveWeeklySectionHeader = "## 주차별 계획과 이행"

/// 상세 화면을 열 만한 내용이 있는가.
/// 주차별 이행표가 없으면 상세에는 실제·예측만 남는데, 그 둘은 목록 행에 이미 있다.
/// (소급 재구성 시 계획 주차를 만들지 못한 아카이브가 여기 해당)
func mrArchiveHasDetail(_ markdown: String) -> Bool {
    markdown.contains(mrArchiveWeeklySectionHeader)
}

/// 화면에 보여줄 본문 — 끝에 붙은 MIMO-META 주석 블록을 떼어낸다.
/// 저장된 마크다운은 그대로 두고 표시만 자른다(모델 버전·원본 수치는 보존).
func mrArchiveDisplayText(_ markdown: String) -> String {
    var text = markdown
    while let open = text.range(of: "<!-- MIMO-META") {
        let close = text.range(of: "-->", range: open.upperBound..<text.endIndex)
        let end = close?.upperBound ?? text.endIndex
        text.removeSubrange(open.lowerBound..<end)
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

/// 대회 기록으로 인정할 거리 허용 오차.
/// GPS 오차·시작선까지의 여유·중간에 끊긴 기록을 감안해 ±10%.
/// (10K 9.0~11.0 / 하프 19.0~23.2 / 풀 38.0~46.4 km)
let mrRaceDayDistanceTolerance = 0.10

/// engine.runs에서 대회일 당일 기록 중 목표 거리에 가장 가까운 워크아웃을 찾는다.
/// 허용 오차 밖이면 nil — 대회에 안 나갔는데 그날 뛴 다른 러닝이 대회 기록으로
/// 둔갑하는 것을 막는다(예전에는 오차 없이 "가장 가까운 것"을 무조건 골랐다).
func mrFindRaceDayRun(runs: [MRWorkout], raceDate: Date, distanceM: Double) -> MRWorkout? {
    let targetKm = distanceM / 1000
    guard targetKm > 0 else { return nil }
    let cal = Calendar.current
    let candidates = runs.filter {
        guard !$0.isInterval, cal.isDate($0.start, inSameDayAs: raceDate) else { return false }
        let km = $0.distanceKm ?? 0
        guard km > 0 else { return false }
        return abs(km - targetKm) / targetKm <= mrRaceDayDistanceTolerance
    }
    return candidates.min {
        abs(($0.distanceKm ?? 0) - targetKm) < abs(($1.distanceKm ?? 0) - targetKm)
    }
}

// MARK: - 저장된 아카이브 재검증

/// 이미 저장된 아카이브 중 "실제 기록"을 뒷받침할 러닝이 없는 것을 지운다.
///
/// 거리 허용 오차가 없던 시절에는 대회일에 뛴 아무 기록이나 대회 결과로 저장됐다
/// (대회에 안 나갔는데 그날 조깅만 한 경우, 테스트로 등록했다 지운 대회 등).
/// 아카이브는 스냅샷에서 다시 만들어지는 파생 데이터이므로, 지우면
/// `createArchivesIfNeeded`가 올바른 상태(기록 있으면 기록, 없으면 "기록 없음")로
/// 다시 만든다. 스냅샷까지 사라진 유령 아카이브는 그대로 없어진다.
///
/// 소급 재구성(`reconstructed`) 아카이브는 다시 만들어질 경로가 없으므로 건드리지 않는다.
/// - Returns: 삭제된 아카이브의 (키, 이름)
@discardableResult
func mrPruneUnsupportedArchives(_ archives: [RaceArchive],
                                 runs: [MRWorkout],
                                 context: ModelContext) -> [(key: String, name: String)] {
    var removed: [(key: String, name: String)] = []
    for arch in archives where arch.hasResult && !arch.reconstructed {
        guard mrFindRaceDayRun(runs: runs,
                               raceDate: arch.raceDate,
                               distanceM: arch.distanceM) == nil else { continue }
        removed.append((mrArchiveKey(raceDate: arch.raceDate, distanceM: arch.distanceM),
                        arch.raceName))
        context.delete(arch)
    }
    return removed
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
///
/// **2패스 방식**
/// 1패스: asOf = 대회 − 20주 로 계획을 시도 → 엔진이 돌려준 시작일을 읽는다.
/// 2패스: 그 시작일을 asOf 로 해서 계획을 다시 생성한다.
/// 1패스 실패 시 폴백: 풀=−16주, 그 이하=−12주.
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
    let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e
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

        logLines.append("\n[\(row.label) \(dateFmt.string(from: row.date))] \(raceName)")

        // ── 1패스: 대회 20주 전 시점으로 계획 시도 → 시작일을 얻기 위한 탐색
        guard let asOf1 = cal.date(byAdding: .weekOfYear, value: -20, to: row.date) else { continue }
        let pastRuns1 = runs.filter { $0.date <= asOf1 }
        let phys1     = mrPhysiology(runs: pastRuns1, restingHRSamples: rhrSamples,
                                     dateOfBirth: dateOfBirth, sex: sex, asOf: asOf1)
        let prior1    = mrApplyHeat(mrDetectEfforts(runs: pastRuns1, phys: phys1), heat: heat)
                            .filter { $0.date < row.date }
        let fit1      = mrFitExponent(prior1)
        let prof1     = mrProfile(runs: pastRuns1, efforts: prior1, asOf: asOf1)
        let preds1    = mrPredict(efforts: prior1, fit: fit1, profile: prof1, heat: heat, asOf: asOf1)
        let hrp1      = mrFitHRPaceModel(runs: pastRuns1, asOf: asOf1)
        let easy1     = phys1.easyCeilingHR.flatMap { hrp1.paceAtHR($0) }
        let half1     = preds1.first { $0.label == "하프" }?.midMin ?? 0

        let plan1 = mrBuildPlan(
            raceDate: row.date, distanceM: distM, today: asOf1,
            profile: prof1, halfEquivMin: half1,
            easyPaceSecPerKm: easy1, heat: heat,
            raceTempC: MR_REF_TEMP, runsPerWeek: prof1.runsPerWeek,
            caller: "백테스트:1패스 \(dateFmt.string(from: asOf1))", raceName: raceName
        )

        // 1패스에서 얻은 실제 시작일
        let asOf2: Date
        if let p1 = plan1 {
            let planStart = p1.weeks.first.map { cal.startOfDay(for: $0.monday) } ?? asOf1
            asOf2 = planStart
            logLines.append(
                "  1패스 asOf \(dateFmt.string(from: asOf1)) → \(p1.weeks.count)주, 시작일 \(dateFmt.string(from: planStart))"
            )
        } else {
            // 폴백: 데이터 부족 등으로 1패스 실패
            let fbWeeks = distM >= MRDistance.dF * 0.99 ? -16 : -12
            asOf2 = cal.date(byAdding: .weekOfYear, value: fbWeeks, to: row.date) ?? row.date
            logLines.append(
                "  1패스 asOf \(dateFmt.string(from: asOf1)) → 실패, 폴백 \(abs(fbWeeks))주 전 = \(dateFmt.string(from: asOf2))"
            )
        }

        // ── 2패스: 그 시작일부터 계획 생성 (이게 "당시 앱이 만들었을 계획")
        let pastRuns2 = runs.filter { $0.date <= asOf2 }
        let phys2     = mrPhysiology(runs: pastRuns2, restingHRSamples: rhrSamples,
                                     dateOfBirth: dateOfBirth, sex: sex, asOf: asOf2)
        let prior2    = mrApplyHeat(mrDetectEfforts(runs: pastRuns2, phys: phys2), heat: heat)
                            .filter { $0.date < row.date }
        let fit2      = mrFitExponent(prior2)
        let prof2     = mrProfile(runs: pastRuns2, efforts: prior2, asOf: asOf2)
        let preds2    = mrPredict(efforts: prior2, fit: fit2, profile: prof2, heat: heat, asOf: asOf2)
        let hrp2      = mrFitHRPaceModel(runs: pastRuns2, asOf: asOf2)
        let easy2     = phys2.easyCeilingHR.flatMap { hrp2.paceAtHR($0) }
        let half2     = preds2.first { $0.label == "하프" }?.midMin ?? 0

        guard let plan2 = mrBuildPlan(
            raceDate: row.date, distanceM: distM, today: asOf2,
            profile: prof2, halfEquivMin: half2,
            easyPaceSecPerKm: easy2, heat: heat,
            raceTempC: MR_REF_TEMP, runsPerWeek: prof2.runsPerWeek,
            caller: "백테스트:2패스 \(dateFmt.string(from: asOf2))", raceName: raceName
        ) else {
            logLines.append("  2패스 asOf \(dateFmt.string(from: asOf2)) → 계획 생성 실패 (데이터 부족)")
            continue
        }

        logLines.append("  2패스 asOf \(dateFmt.string(from: asOf2)) → \(plan2.weeks.count)주 계획 생성 완료")

        // ── 주차 이행 통계
        let planWeeks = plan2.weeks.map { w in
            MRPlanWeekSummary(idx: w.idx, monday: w.monday,
                              phase: w.phase, longRunKm: w.longRunKm, weeklyKm: w.weeklyKm,
                              breakdown: w.breakdown)
        }
        let weeksJSON = (try? encoder.encode(planWeeks)).flatMap { String(data: $0, encoding: .utf8) } ?? ""

        var hitBoth = 0, hitOne = 0, hitNone = 0, hitOver = 0
        var matchedWeeks = 0
        let raceDayStart = cal.startOfDay(for: row.date)
        for w in planWeeks {
            let weekStart = cal.startOfDay(for: w.monday)
            let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
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
            matchedWeeks += 1
        }

        logLines.append("  실제 기록 매칭 \(matchedWeeks)주 / \(planWeeks.count)주")
        logLines.append("  \(symbolBoth) \(hitBoth) \(symbolOne) \(hitOne) \(symbolNone) \(hitNone) \(symbolOver) \(hitOver)")

        // ── 마크다운 생성 + 아카이브 저장
        let snap = RacePlanSnapshot(
            raceDate: row.date, raceName: raceName, distanceM: distM,
            projectedFinalMin: plan2.projectedFinal, projectedNowMin: plan2.projectedNow,
            goalMin: 0, weeksJSON: weeksJSON, metaJSON: ""
        )

        let retroNote = "> 이 계획은 나중에 소급 재구성한 것입니다.\n> 대회 당시에는 앱에 계획 기능이 없었습니다.\n\n"
        let md = retroNote + mrBuildArchiveMarkdown(
            snapshot: snap, actualMin: row.actualMin,
            preRaceProjectedMin: nil, runs: runs
        )

        let archive = RaceArchive(
            raceDate: row.date, raceName: raceName, distanceM: distM,
            markdown: md, hasResult: true, actualMin: row.actualMin,
            snapshotProjectedFinalMin: plan2.projectedFinal, reconstructed: true
        )
        context.insert(archive)
        count += 1
    }

    return (["[아카이브] 소급 \(count)건 생성"] + logLines).joined(separator: "\n")
}
