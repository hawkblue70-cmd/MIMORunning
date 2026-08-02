import Foundation
import SwiftUI
import Combine
import HealthKit

// ⚠ 두 배열로 나눠 그리면 날짜 순서가 무너진다.
//   계획 유무가 아니라 대회 날짜가 정렬 기준이다.
enum MRRaceItem: Identifiable {
    case planned(MRGoalCheck)
    case planless(MRTargetRace)

    var id: String {
        switch self {
        case .planned(let c):  return c.race.id.uuidString
        case .planless(let r): return r.id.uuidString
        }
    }
    var date: Date {
        switch self {
        case .planned(let c):  return c.race.date
        case .planless(let r): return r.date
        }
    }
}

/// 엔진 파이프라인 전체를 한 번 돌리고 결과를 들고 있는다.
///
/// ⚠ HealthKit 읽기가 수 초 걸리므로 화면마다 다시 돌리면 안 된다.
///   앱에 하나만 두고 `@EnvironmentObject`로 공유한다.
@MainActor
final class MREngineStore: ObservableObject {

    enum State { case idle, loading, ready, failed(String) }

    @Published var state: State = .idle
    @Published var userInput = MRUserInputStore.load()

    // 결과
    @Published private(set) var runs: [MRWorkout] = []
    @Published private(set) var phys = MRPhysiology()
    @Published private(set) var heat = MRHeatModel()
    @Published private(set) var hrPace = MRHRPaceModel()
    @Published private(set) var efforts: [MRRaceEffort] = []
    @Published private(set) var fit = MRExponentFit()
    @Published private(set) var profile = MRProfile()
    @Published private(set) var predictions: [MRPrediction] = []
    @Published private(set) var plans: [MRRacePlan] = []
    @Published private(set) var checks: [MRGoalCheck] = []
    @Published private(set) var planlessRaces: [MRTargetRace] = []
    @Published private(set) var advice: [MRAdvice] = []
    @Published private(set) var streakWeeks: Int = 0
    @Published private(set) var todayCard: MRTodayCard?
    @Published private(set) var raceDayCard: MRRaceDayCard?
    @Published private(set) var backtest: [MRBacktestRow] = []
    @Published private(set) var drift = MRDriftModel()
    @Published private(set) var profileFull = MRProfileFull()
    @Published private(set) var gaps: [MRGap] = []
    @Published private(set) var stepsDaily: [Date: Double] = [:]
    @Published private(set) var healthMetrics = MRHealthMetrics()
    @Published var adviceLog = MRAdviceLogStore.load()

    // 로컬 저장: backtest / advice 재계산용
    private var rhrSamples: [(date: Date, value: Double)] = []
    private var storedDob: Date? = nil
    private var storedSex: MRSex = .unknown
    private var storedStrengthPerWeek: Double = 0

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var halfEquivMin: Double {
        predictions.first { $0.label == "하프" }?.midMin ?? 0
    }
    var easyPaceSecPerKm: Double? {
        phys.easyCeilingHR.flatMap { hrPace.paceAtHR($0) }
    }

    var raceItems: [MRRaceItem] {
        (checks.map { MRRaceItem.planned($0) }
         + planlessRaces.map { MRRaceItem.planless($0) })
            .sorted { $0.date < $1.date }
    }

    private let hk = MRHealthKit()

    // MARK: - 퍼블릭 진입점

    func refresh() async {
        state = .loading
        do {
            try await hk.requestAuthorization()
            try await refreshCore()
            // 2단계는 기다리지 않는다 — 화면은 이미 그려졌다
            Task { await self.refreshDetail() }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - 1단계: 화면에 즉시 필요한 것 (목표 ~2초)

    private func refreshCore() async throws {
        let now = Date()

        // 증분 fetch — 캐시 히트 시 WorkoutKit 쿼리 0회
        var fetched = try await timed("fetchRunsIncremental") { try await hk.fetchRunsIncremental() }

        // ⚠ 인터벌 판정이 폭주하면(전체의 40% 초과) 기준이 잘못된 것이다.
        let flagged = fetched.filter(\.isInterval).count
        if Double(flagged) / Double(max(fetched.count, 1)) > 0.40 {
            fetched = fetched.map {
                MRWorkout(start: $0.start, durationMin: $0.durationMin,
                          distanceKm: $0.distanceKm, hrAvg: $0.hrAvg,
                          hrMax: $0.hrMax, tempC: $0.tempC,
                          humidity: $0.humidity, indoor: $0.indoor,
                          isInterval: false)
            }
            print("⚠ 인터벌 판정 \(flagged)/\(fetched.count) — 기준이 잘못됨. 무시함")
        }

        let rhr = try await timed("fetchRestingHR") { try await hk.fetchRestingHR() }
        let dob = hk.dateOfBirth()
        let sexRaw = hk.biologicalSex()
        let sex: MRSex = sexRaw == .female ? .female : (sexRaw == .male ? .male : .unknown)

        runs = fetched
        // ⚠ 연속 주는 한 곳에서만 계산한다.
        //   홈·성장 탭·공유 카드가 같은 값을 가리켜야 사용자가 믿을 수 있다.
        streakWeeks = mrActiveWeekStreak(runs: fetched, asOf: now)
        rhrSamples = rhr
        storedDob = dob
        storedSex = sex

        phys = mrPhysiology(runs: fetched, restingHRSamples: rhr,
                            dateOfBirth: dob, sex: sex, asOf: now)
        heat = mrFitHeatModel(runs: fetched)
        hrPace = mrFitHRPaceModel(runs: fetched, asOf: now)
        print("[HRPace] tier=\(hrPace.tier) · 이지페이스=\(easyPaceSecPerKm.map { mrFormatPace($0) } ?? "-")")

        efforts = mrApplyHeat(mrDetectEfforts(runs: fetched, phys: phys), heat: heat)
        fit = mrFitExponent(efforts)

        // 걸음 수는 2단계에서 — stage 1은 firstDataDate nil로 profileFull 추산
        profileFull = mrProfileFull(
            runs: fetched, efforts: efforts,
            firstDataDate: nil,
            dateOfBirth: dob,
            hasGoalTime: userInput.goals.tenKSec != nil
                      || userInput.goals.halfSec  != nil
                      || userInput.goals.fullSec  != nil,
            hasGoalRace: !userInput.upcomingRaces(asOf: now).isEmpty,
            asOf: now)
        // gaps는 stepsDaily가 필요 — 2단계에서 채워진다
        gaps = []

        profile = MRProfile(weeklyKm4w: profileFull.weeklyKm4w,
                            longestRun30d: profileFull.longestRun30d,
                            longestRun16wKm: profileFull.longestRun16wKm,
                            marathonFinishes: profileFull.marathonFinishes,
                            runsPerWeek: profileFull.runsPerWeek)

        predictions = mrPredict(efforts: efforts, fit: fit, profile: profile,
                                heat: heat, asOf: now)

        let he = halfEquivMin
        let upcoming = userInput.upcomingRaces(asOf: now)
        let raceTempByID = Dictionary(uniqueKeysWithValues: upcoming.map { r in
            (r.id, mrSeasonalTemp(runs: fetched, for: r.date) ?? MR_REF_TEMP)
        })
        let paired = upcoming.map { r -> (race: MRTargetRace, plan: MRRacePlan?) in
            let rt = raceTempByID[r.id] ?? MR_REF_TEMP
            return (r, mrBuildPlan(raceDate: r.date, distanceM: r.distanceM, today: now,
                                   profile: profile, halfEquivMin: he,
                                   easyPaceSecPerKm: easyPaceSecPerKm, heat: heat,
                                   raceTempC: rt, runsPerWeek: profile.runsPerWeek))
        }
        let validPairs = paired.compactMap { p -> (MRTargetRace, MRRacePlan)? in
            guard let pl = p.plan else { return nil }
            return (p.race, pl)
        }
        plans = validPairs.map(\.1)
        checks = validPairs.map { (r, pl) in
            mrCheckGoal(race: r, plan: pl, goals: userInput.goals,
                        profile: profile, halfEquivMin: he, heat: heat,
                        raceTempC: raceTempByID[r.id] ?? MR_REF_TEMP)
        }
        planlessRaces = paired.filter { $0.plan == nil }.map(\.race)
        advice = mrBuildAdvice(runs: fetched, phys: phys, plans: plans,
                               gaps: [], strengthPerWeek: storedStrengthPerWeek,
                               log: adviceLog, asOf: now)
        adviceLog.record(advice.map(\.key), asOf: now)
        MRAdviceLogStore.save(adviceLog)
        raceDayCard = computeRaceDayCard(plans: plans, asOf: now)
        let raceDayVisible = raceDayCard.map { MRRaceDayView.shouldShow($0) } ?? false
        todayCard = mrTodayCard(runs: fetched, phys: phys, plans: plans,
                                raceDayCardVisible: raceDayVisible,
                                advice: advice, asOf: now)

        print("[추론] 레벨 \(profileFull.level) · 모드 \(profileFull.mode) · 노력 \(efforts.count)건 · 예측 \(predictions.count)건")

        // ★ 여기서 화면이 그려진다
        state = .ready
    }

    // MARK: - 2단계: 백그라운드 (화면 이미 표시됨)

    private func refreshDetail() async {
        guard case .ready = state else { return }
        let now = Date()

        // ① 걸음 수 증분 fetch — 어제까지는 캐시, 오늘만 새로 읽는다
        // 경력 추정의 '기기 구매일 함정 회피'를 위해 첫 런보다 1년 앞에서 시작한다
        let floor = Calendar.current.date(byAdding: .year, value: -1,
                                          to: runs.first?.start ?? now) ?? now
        let steps = (try? await timed("fetchDailySteps") { try await hk.fetchDailyStepsIncremental(floor: floor) }) ?? [:]
        stepsDaily = steps

        // ② profileFull 재계산 (firstDataDate 포함) + gaps
        let firstData = steps.keys.min()
        profileFull = mrProfileFull(
            runs: runs, efforts: efforts,
            firstDataDate: firstData,
            dateOfBirth: storedDob,
            hasGoalTime: userInput.goals.tenKSec != nil
                      || userInput.goals.halfSec  != nil
                      || userInput.goals.fullSec  != nil,
            hasGoalRace: !userInput.upcomingRaces(asOf: now).isEmpty,
            asOf: now)
        gaps = mrDetectGaps(runs: runs, stepsDaily: steps)

        // gaps가 채워졌으니 advice/todayCard 재계산
        advice = mrBuildAdvice(runs: runs, phys: phys, plans: plans,
                               gaps: gaps, strengthPerWeek: storedStrengthPerWeek,
                               log: adviceLog, asOf: now)
        adviceLog.record(advice.map(\.key), asOf: now)
        MRAdviceLogStore.save(adviceLog)
        let raceDayVisible2 = raceDayCard.map { MRRaceDayView.shouldShow($0) } ?? false
        todayCard = mrTodayCard(runs: runs, phys: phys, plans: plans,
                                raceDayCardVisible: raceDayVisible2,
                                advice: advice, asOf: now)

        print("[추론] firstData=\(firstData.map(mrYMD) ?? "-") · 경력 \(String(format: "%.2f", profileFull.trainingAgeYears?.value ?? 0))년 · 공백 \(gaps.count)건")

        // ③ VO2max + 건강 지표
        let vo2 = (try? await hk.fetchVO2Max()) ?? []
        healthMetrics = mrHealthMetrics(runs: runs,
                                        restingHRSamples: rhrSamples,
                                        vo2Samples: vo2,
                                        stepsDaily: stepsDaily,
                                        asOf: now)
        let h = healthMetrics
        let dn = ["", "일", "월", "화", "수", "목", "금", "토"]
        print("[건강] 루틴 \(h.habitDays.map { dn[$0] }.joined(separator: "·")) · 30일 중 \(h.days30)일 · 90일 \(h.sessions90)회 \(Int(h.km90))km")

        // ④ 드리프트 (세그먼트 병렬 fetch + 캐시)
        await timed("refreshDrift") { await self.refreshDrift() }

        // ⑤ 백테스트 (노력 핑거프린트 캐시)
        await timed("refreshBacktest") { await self.refreshBacktest() }
    }

    // MARK: - 드리프트 (세그먼트 fetch 병렬화 + 캐시)

    private func refreshDrift() async {
        let cutoff = Date().addingTimeInterval(-90 * 86400)

        // 90일 HKWorkout만 직접 읽는다 (WorkoutKit 쿼리 없음, 빠름)
        let recent: [HKWorkout] = (try? await hk.fetchRawRunsSince(cutoff)) ?? []

        // 캐시 확인: 마지막 워크아웃 시작일이 같으면 재사용
        if let cached = MRDriftCacheStore.load(),
           let lastStart = recent.last?.startDate,
           abs(cached.lastWorkoutStart.timeIntervalSince(lastStart)) < 1 {
            let m = cached.drift.model
            drift = m
            print("[드리프트] 캐시 히트 · \(m.ok ? "성공" : "실패") · \(m.sessions)세션")
            return
        }

        // 최대 6개 동시 실행 (세마포어 패턴)
        let segs: [MRSegment] = await withTaskGroup(of: (Int, [MRSegment]).self) { group in
            let maxConcurrent = 6
            var started = 0

            for i in 0..<min(maxConcurrent, recent.count) {
                let w = recent[i]
                group.addTask { (i, (try? await self.hk.fetchSegments(for: w)) ?? []) }
                started += 1
            }

            var results: [(Int, [MRSegment])] = []
            for await (i, s) in group {
                results.append((i, s))
                if started < recent.count {
                    let next = started
                    let w = recent[next]
                    group.addTask { (next, (try? await self.hk.fetchSegments(for: w)) ?? []) }
                    started += 1
                }
            }
            return results.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
        print("[T3] 대상 \(recent.count)건 · 세그먼트 \(segs.count)점")

        let intervalStarts = Set(runs.filter(\.isInterval).map(\.start))
        let m = mrFitDrift(segments: segs, excludeIntervalStarts: intervalStarts)
        drift = m

        if let last = recent.last?.startDate {
            MRDriftCacheStore.save(MRDriftCache(lastWorkoutStart: last,
                                                drift: MRDriftModelCodable(m)))
        }
        print("[드리프트] \(m.ok ? "성공" : "실패") · 10분당 \(String(format: "%.1f", m.bpmPer10Min))bpm · \(m.sessions)세션")
    }

    // MARK: - 백테스트 (노력 핑거프린트 캐시)

    private func refreshBacktest() async {
        let key = MRBacktestCacheStore.effortKey(efforts)

        if let cached = MRBacktestCacheStore.load(), cached.effortKey == key {
            backtest = cached.rows.map(\.row)
            print("[백테스트] 캐시 히트 · \(backtest.count)건")
            return
        }

        let r = runs, rhr = rhrSamples, d = storedDob, s = storedSex, h = heat
        let result = await Task.detached(priority: .userInitiated) {
            mrBacktest(runs: r, restingHRSamples: rhr,
                       dateOfBirth: d, sex: s, heat: h, asOf: Date())
        }.value

        backtest = result
        MRBacktestCacheStore.save(MRBacktestCache(
            effortKey: key,
            rows: result.map(MRBacktestRowCodable.init)
        ))
        print("[백테스트] 완료 · \(result.count)건")
    }

    // MARK: - 성장 탭에서 수동 트리거

    func computeBacktestIfNeeded() {
        guard backtest.isEmpty, case .ready = state else { return }
        Task { await self.refreshBacktest() }
    }

    // MARK: - 근력 횟수 업데이트 (HealthKit 재읽기 없음)

    func updateAdvice(strengthPerWeek: Double) {
        guard case .ready = state else { return }
        storedStrengthPerWeek = strengthPerWeek
        let now = Date()
        advice = mrBuildAdvice(runs: runs, phys: phys, plans: plans,
                               gaps: gaps, strengthPerWeek: storedStrengthPerWeek,
                               log: adviceLog, asOf: now)
        adviceLog.record(advice.map(\.key), asOf: now)
        MRAdviceLogStore.save(adviceLog)
        let raceDayVisible3 = raceDayCard.map { MRRaceDayView.shouldShow($0) } ?? false
        todayCard = mrTodayCard(runs: runs, phys: phys, plans: plans,
                                raceDayCardVisible: raceDayVisible3,
                                advice: advice, asOf: now)
    }

    // MARK: - 대회·목표 변경 (HealthKit 재읽기 없음)

    func recomputePlans() {
        guard case .ready = state else { return }
        MRUserInputStore.save(userInput)
        let now = Date()
        let he = halfEquivMin
        let upcoming = userInput.upcomingRaces(asOf: now)
        let raceTempByID = Dictionary(uniqueKeysWithValues: upcoming.map { r in
            (r.id, mrSeasonalTemp(runs: runs, for: r.date) ?? MR_REF_TEMP)
        })
        let paired = upcoming.map { r -> (race: MRTargetRace, plan: MRRacePlan?) in
            let rt = raceTempByID[r.id] ?? MR_REF_TEMP
            return (r, mrBuildPlan(raceDate: r.date, distanceM: r.distanceM, today: now,
                                   profile: profile, halfEquivMin: he,
                                   easyPaceSecPerKm: easyPaceSecPerKm, heat: heat,
                                   raceTempC: rt, runsPerWeek: profile.runsPerWeek))
        }
        let validPairs = paired.compactMap { p -> (MRTargetRace, MRRacePlan)? in
            guard let pl = p.plan else { return nil }
            return (p.race, pl)
        }
        plans = validPairs.map(\.1)
        checks = validPairs.map { (r, pl) in
            mrCheckGoal(race: r, plan: pl, goals: userInput.goals,
                        profile: profile, halfEquivMin: he, heat: heat,
                        raceTempC: raceTempByID[r.id] ?? MR_REF_TEMP)
        }
        planlessRaces = paired.filter { $0.plan == nil }.map(\.race)
        advice = mrBuildAdvice(runs: runs, phys: phys, plans: plans,
                               gaps: gaps, strengthPerWeek: storedStrengthPerWeek,
                               log: adviceLog, asOf: now)
        adviceLog.record(advice.map(\.key), asOf: now)
        MRAdviceLogStore.save(adviceLog)
        raceDayCard = computeRaceDayCard(plans: plans, asOf: now)
        let raceDayVisible4 = raceDayCard.map { MRRaceDayView.shouldShow($0) } ?? false
        todayCard = mrTodayCard(runs: runs, phys: phys, plans: plans,
                                raceDayCardVisible: raceDayVisible4,
                                advice: advice, asOf: now)
    }

    // MARK: - 내부 헬퍼

    private func computeRaceDayCard(plans: [MRRacePlan], asOf: Date) -> MRRaceDayCard? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: asOf)
        let racesWithD = userInput.races.compactMap { race -> (MRTargetRace, Int)? in
            let d = cal.dateComponents([.day], from: today,
                                       to: cal.startOfDay(for: race.date)).day ?? -999
            guard d >= -14 else { return nil }
            return (race, d)
        }
        let upcoming = racesWithD.filter { $0.1 >= 0 }.min { $0.1 < $1.1 }
        let recovery = racesWithD.filter { $0.1 <  0 }.max { $0.1 < $1.1 }
        guard let (race, _) = upcoming ?? recovery else { return nil }

        let goalMin = userInput.goals.minutes(for: race.distanceM)
        let plan = plans.first {
            abs($0.distanceM - race.distanceM) < 1 &&
            abs($0.raceDate.timeIntervalSince(race.date)) < 86400
        }
        let raceTemp = mrSeasonalTemp(runs: runs, for: race.date) ?? MR_REF_TEMP
        return mrRaceDayCard(race: race, plan: plan,
                             predictions: predictions,
                             heat: heat,
                             raceTempC: raceTemp,
                             goalMin: goalMin,
                             runs: runs,
                             asOf: asOf)
    }

    @discardableResult
    private func timed<T>(_ label: String, _ work: () async throws -> T) async rethrows -> T {
        let t0 = CFAbsoluteTimeGetCurrent()
        let result = try await work()
        print(String(format: "[⏱ %@] %.2fs", label, CFAbsoluteTimeGetCurrent() - t0))
        return result
    }
}
