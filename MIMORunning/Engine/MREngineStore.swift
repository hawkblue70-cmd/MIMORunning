import Foundation
import SwiftUI
import Combine
import HealthKit

// ⚠ 두 배열로 나눠 그리면 날짜 순서가 무너진다.
//   계획 유무가 아니라 대회 날짜가 정렬 기준이다.
enum MRRaceItem: Identifiable {
    case planned(MRGoalCheck)
    case planless(MRTargetRace)
    /// A 계획 안의 "대회 주"로 흡수된 튠업 — 독립 계획 없음
    case tuneUp(MRTargetRace, planName: String)

    var id: String {
        switch self {
        case .planned(let c):     return c.race.id.uuidString
        case .planless(let r):    return r.id.uuidString
        case .tuneUp(let r, _):   return r.id.uuidString
        }
    }
    var date: Date {
        switch self {
        case .planned(let c):     return c.race.date
        case .planless(let r):    return r.date
        case .tuneUp(let r, _):   return r.date
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
    /// 기온 보정 심박 — 심박을 과거와 비교·판정하는 모든 자리가 이 모델 하나를 쓴다.
    @Published private(set) var heatHR = MRHeatHRModel()
    @Published private(set) var hrPace = MRHRPaceModel()
    @Published private(set) var easyPaceLookup: MRHRPaceLookup?
    @Published private(set) var efforts: [MRRaceEffort] = []
    @Published private(set) var fit = MRExponentFit()
    @Published private(set) var profile = MRProfile()
    @Published private(set) var predictions: [MRPrediction] = []
    @Published private(set) var plans: [MRRacePlan] = []
    @Published private(set) var checks: [MRGoalCheck] = []
    @Published private(set) var planlessRaces: [MRTargetRace] = []
    /// A 계획의 "대회 주"로 흡수된 튠업 대회와 그 계획 이름
    @Published private(set) var absorbedTuneUps: [(race: MRTargetRace, planName: String)] = []
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
    private var rhrLastFetchedAt: Date? = nil
    // 대회별 계획 시작 월요일 고정값 (MeView에서 스냅샷 앵커로 업데이트).
    // refreshCore와 recomputePlans가 동일한 앵커를 참조해 계획 길이를 일치시킨다.
    private var storedSnapshotAnchors: [String: Date] = [:]
    /// 스냅샷 주차(mrArchiveKey → 확정 주차). 자기 계획 있는 단거리의 "따르는 주"와 이번 주 목표는 이 값을 쓴다 —
    /// 라이브 재계산 값은 오늘 프로필로 다시 만들어져 주차표(스냅샷)와 어긋날 수 있다.
    private var storedSnapshotWeeks: [String: [MRPlanWeekSummary]] = [:]

    private static let rhrCacheDateKey    = "mimo.rhrCache.fetchedAt"
    private static let rhrCacheSamplesKey = "mimo.rhrCache.samples"

    private func loadPersistedRHR() -> (fetchedAt: Date, samples: [(date: Date, value: Double)])? {
        let ud = UserDefaults.standard
        guard let ts = ud.object(forKey: Self.rhrCacheDateKey) as? Double,
              let rawArr = ud.array(forKey: Self.rhrCacheSamplesKey) as? [[Double]] else { return nil }
        let samples = rawArr.compactMap { arr -> (date: Date, value: Double)? in
            guard arr.count == 2 else { return nil }
            return (Date(timeIntervalSince1970: arr[0]), arr[1])
        }
        guard !samples.isEmpty else { return nil }
        return (Date(timeIntervalSince1970: ts), samples)
    }

    private func persistRHR(fetchedAt: Date, samples: [(date: Date, value: Double)]) {
        let ud = UserDefaults.standard
        ud.set(fetchedAt.timeIntervalSince1970, forKey: Self.rhrCacheDateKey)
        ud.set(samples.map { [$0.date.timeIntervalSince1970, $0.value] }, forKey: Self.rhrCacheSamplesKey)
    }
    private var storedDob: Date? = nil
    private var storedSex: MRSex = .unknown
    private var storedStrengthPerWeek: Double = 0
    private var storedFatigue: [MRLongRunFatigue] = []
    private var storedCadenceShift: MRFormShift? = nil
    private var storedConfirmedMatches: [PersistedRaceMatch] = []
    private var storedSigmaObs: Double = 0

    /// 뷰에서 주입 — HealthKitManager.persistedConfirmedMatches() 래퍼.
    /// refreshBacktest 진입부에서 storedConfirmedMatches가 비었을 때 폴백으로 호출.
    var persistedMatchesProvider: (() -> [PersistedRaceMatch]) = { [] }

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var halfEquivMin: Double {
        predictions.first { $0.label == "하프" }?.midMin ?? 0
    }
    // 회귀(hrPace)는 그래프용으로만 쓴다.
    // 이지 페이스 값은 항상 실측 구간 중앙값(easyPaceLookup)에서 가져온다.
    var easyPaceSecPerKm: Double? { easyPaceLookup?.paceSec }

    var raceItems: [MRRaceItem] {
        (checks.map { MRRaceItem.planned($0) }
         + planlessRaces.map { MRRaceItem.planless($0) }
         + absorbedTuneUps.map { MRRaceItem.tuneUp($0.race, planName: $0.planName) })
            .sorted { $0.date < $1.date }
    }

    // MARK: - 대회 ↔ 계획 짝짓기
    //
    // A 레이스(하프 이상)에만 계획을 만들고, 그 기간 안의 5K·10K(풀 계획 안의 하프)는
    // "대회 주"로 흡수한다. 감싸는 계획이 없는 단거리만 독립 계획을 만든다.
    // refreshCore와 recomputePlans가 같은 규칙을 써야 하므로 한 곳에 둔다.
    private func buildRacePairs(upcoming: [MRTargetRace], profile planProfile: MRProfile,
                                anchors: [String: Date], raceTempByID: [UUID: Double],
                                now: Date, caller: String)
        -> (paired: [(race: MRTargetRace, plan: MRRacePlan?)],
            absorbed: [(race: MRTargetRace, planName: String)]) {
        let cal = Calendar.current
        let he = halfEquivMin
        var prevPlanInfo: (date: Date, name: String, distanceM: Double, peakLong: Double, peakVol: Double)? = nil
        var absorbed: [(race: MRTargetRace, planName: String)] = []
        var aPairs: [(race: MRTargetRace, plan: MRRacePlan?)] = []

        // ① 자기 계획(앵커)이 있는 단거리 먼저 — A 계획이 겹치는 주에 이 숫자를 따라야 하므로.
        var ownPlanWeeksByKey: [String: [MRPlanWeek]] = [:]
        var shortPairs: [(race: MRTargetRace, plan: MRRacePlan?)] = []
        for r in upcoming where r.distanceM < MRDistance.dH {
            let key = mrArchiveKey(raceDate: r.date, distanceM: r.distanceM)
            guard let anchor = anchors[key] else { continue }
            let pl = mrBuildPlan(raceDate: r.date, distanceM: r.distanceM, today: now,
                                 profile: planProfile, halfEquivMin: he,
                                 easyPaceSecPerKm: easyPaceSecPerKm, heat: heat,
                                 raceTempC: raceTempByID[r.id] ?? MR_REF_TEMP,
                                 runsPerWeek: planProfile.runsPerWeek,
                                 priorRace: nil, forcedMonday: anchor,
                                 caller: caller, raceName: r.name)
            // ⚠ A 계획이 따를 숫자는 사용자가 주차표에서 보는 스냅샷 값이어야 한다.
            //   라이브 주차는 오늘 프로필로 다시 만들어져 스냅샷(48)과 다른 숫자(41)가 나올 수 있고,
            //   그러면 두 카드가 같은 주에 다른 주간 거리를 보여 준다.
            if let pl {
                ownPlanWeeksByKey[key] = MRPlanGovernance.applyingSnapshot(
                    pl.weeks, snapshot: storedSnapshotWeeks[key] ?? [], easyPaceSecPerKm: easyPaceSecPerKm)
            }
            shortPairs.append((r, pl))
        }

        // ② A 레이스(하프 이상)
        for r in upcoming where r.distanceM >= MRDistance.dH {
            let key = mrArchiveKey(raceDate: r.date, distanceM: r.distanceM)
            // 앞선 대회는 반드시 대상 대회보다 하루 이상 앞선 날이어야 한다.
            let prior = prevPlanInfo.flatMap { p in
                cal.startOfDay(for: p.date) < cal.startOfDay(for: r.date) ? p : nil
            }
            let tune = mrTuneUpCandidates(for: r, among: upcoming, today: now,
                                          plannedKeys: Set(anchors.keys)).map { t -> MRTuneUpRace in
                var t = t
                t.ownPlanWeeks = ownPlanWeeksByKey[mrArchiveKey(raceDate: t.date, distanceM: t.distanceM)] ?? []
                return t
            }
            let pl = mrBuildPlan(raceDate: r.date, distanceM: r.distanceM, today: now,
                                 profile: planProfile, halfEquivMin: he,
                                 easyPaceSecPerKm: easyPaceSecPerKm, heat: heat,
                                 raceTempC: raceTempByID[r.id] ?? MR_REF_TEMP,
                                 runsPerWeek: planProfile.runsPerWeek,
                                 priorRace: prior, forcedMonday: anchors[key],
                                 tuneUps: tune, caller: caller, raceName: r.name)
            if let pl {
                prevPlanInfo = (date: r.date, name: r.name, distanceM: r.distanceM,
                                peakLong: pl.reachableLongKm, peakVol: pl.peakWeeklyKm)
                // ⚠ 이미 스냅샷(진행 중인 계획)이 있는 단거리 대회는 흡수하지 않는다.
                //   "진행 중인 계획은 바꾸지 않는다" — 주차 테이블·이행 기호가 사라지면 안 된다.
                //   A 계획 쪽 "대회 주" 표시는 그대로 두고, 독립 계획도 유지한다.
                for t in upcoming where t.id != r.id
                    && anchors[mrArchiveKey(raceDate: t.date, distanceM: t.distanceM)] == nil
                    && pl.absorbedTuneUpDates.contains(where: { cal.isDate($0, inSameDayAs: t.date) })
                    && !absorbed.contains(where: { $0.race.id == t.id }) {
                    absorbed.append((t, r.name))
                }
            }
            aPairs.append((r, pl))
        }

        // ③ 앵커 없고 흡수도 안 된 단거리 — 독립 계획
        let absorbedIDs = Set(absorbed.map { $0.race.id })
        for r in upcoming where r.distanceM < MRDistance.dH && !absorbedIDs.contains(r.id) {
            let key = mrArchiveKey(raceDate: r.date, distanceM: r.distanceM)
            guard anchors[key] == nil else { continue }   // ①에서 처리됨
            let pl = mrBuildPlan(raceDate: r.date, distanceM: r.distanceM, today: now,
                                 profile: planProfile, halfEquivMin: he,
                                 easyPaceSecPerKm: easyPaceSecPerKm, heat: heat,
                                 raceTempC: raceTempByID[r.id] ?? MR_REF_TEMP,
                                 runsPerWeek: planProfile.runsPerWeek,
                                 priorRace: nil, forcedMonday: anchors[key],
                                 caller: caller, raceName: r.name)
            shortPairs.append((r, pl))
        }
        #if DEBUG
        for a in absorbed { print("[계획:\(caller)] 튠업 흡수 — \(a.race.name) → 「\(a.planName)」 계획의 대회 주") }
        #endif
        return ((aPairs + shortPairs).sorted { $0.race.date < $1.race.date }, absorbed)
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

        // 앱 재시작 후에도 유효한 캐시가 있으면 복원
        if rhrSamples.isEmpty, let persisted = loadPersistedRHR() {
            rhrSamples    = persisted.samples
            rhrLastFetchedAt = persisted.fetchedAt
        }
        let rhr: [(date: Date, value: Double)]
        let rhrAge = rhrLastFetchedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if !rhrSamples.isEmpty && rhrAge < 24 * 3600 {
            rhr = rhrSamples
            #if DEBUG
            let saveDateStr: String = {
                let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
                return rhrLastFetchedAt.map { df.string(from: $0) } ?? "?"
            }()
            print("[⏱ fetchRestingHR] 캐시 히트(저장일 \(saveDateStr)) · \(rhrSamples.count)건")
            #endif
        } else {
            let t0 = CFAbsoluteTimeGetCurrent()
            rhr = try await hk.fetchRestingHR()
            let fetchedAt = Date()
            rhrLastFetchedAt = fetchedAt
            persistRHR(fetchedAt: fetchedAt, samples: rhr)
            #if DEBUG
            print(String(format: "[⏱ fetchRestingHR] %.2fs · 조회범위 400일 · 결과 %d건 · 캐시 미스",
                         CFAbsoluteTimeGetCurrent() - t0, rhr.count))
            #endif
        }
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
        heatHR = mrFitHeatHRModel(runs: fetched, asOf: now)
        // mrFitHRPaceModel 내부 #if DEBUG 에서 회귀 통계(n·구간별 실측·R²)가 출력된다.
        hrPace = mrFitHRPaceModel(runs: fetched, asOf: now)

        // mrEasyPaceFromRuns 내부 #if DEBUG 에서 구간 중앙값 결과가 출력된다.
        if let targetHR = phys.easyCeilingHR {
            easyPaceLookup = mrEasyPaceFromRuns(runs: fetched, targetHR: targetHR, asOf: now)
        } else {
            easyPaceLookup = nil
        }

        #if DEBUG
        do {
            let hrMaxStr = phys.hrMax.map { String(format: "%.0f", $0.value) } ?? "—"
            let lt1Str   = phys.lt1HR.map  { String(format: "%.0f", $0.value) } ?? "—"
            let thrStr   = phys.easyCeilingHR.map { String(format: "%.0f", $0) } ?? "—"
            print("[HRPace] tier=\(hrPace.tier) n=\(hrPace.n) · HRmax=\(hrMaxStr) LT1=\(lt1Str) 목표심박=\(thrStr)")
            if let lk = easyPaceLookup {
                print("[HRPace] → 이지페이스 \(mrFormatPace(lk.paceSec))  근거: \(lk.basis)")
            } else {
                print("[HRPace] → 이지페이스 계산 불가 (구간 n<5 또는 목표심박 없음)")
            }
        }
        #endif

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

        // 캐시 백테스트에서 관측 노이즈를 추출 — 첫 실행시 캐시 없으면 0(순수 드리프트 모델)
        let cachedBT = MRBacktestCacheStore.load()?.rows.map(\.row) ?? []
        let sigmaObs = mrSigmaObs(backtest: cachedBT)
        storedSigmaObs = sigmaObs
        #if DEBUG
        print(String(format: "[σ_obs] 백테스트 %d건 → σ_obs=%.4f (±%.1f%%)",
                     cachedBT.count, sigmaObs, (exp(sigmaObs) - 1) * 100))
        #endif
        profile = mrProfile(runs: fetched, efforts: efforts, sigmaObs: sigmaObs, asOf: now)

        // 플래너 전용 프로필: 이번 주 월요일 자정 기준으로 계산.
        // 주 중간에 뛰어도 계획의 시작 수치(롱런·주간거리)가 바뀌지 않는다.
        // 다음 월요일이 되면 이번 주 실적이 자연스럽게 반영된다.
        let planCutoff: Date = {
            let cal = Calendar.current
            let wd = cal.component(.weekday, from: now)   // Sun=1, Mon=2 … Sat=7
            let daysSinceMon = (wd + 5) % 7               // Mon=0, Tue=1 … Sun=6
            let mondayStart = cal.date(byAdding: .day, value: -daysSinceMon,
                                       to: cal.startOfDay(for: now)) ?? now
            // ⚠ days()는 startOfDay(asOf)를 기준으로 계산한다.
            //   asOf = 월요일 00:00:00 이면 당일 런(date=월요일 00:00:00)도 days=0으로 포함된다.
            //   1초 빼면 startOfDay(asOf) = 일요일 → 이번 주 런 전체가 제외된다.
            return mondayStart.addingTimeInterval(-1)
        }()
        let planProfile = mrProfile(runs: fetched, efforts: efforts, sigmaObs: sigmaObs, asOf: planCutoff)

        predictions = mrPredict(efforts: efforts, fit: fit, profile: profile,
                                heat: heat, asOf: now)

        let he = halfEquivMin
        let upcoming = userInput.upcomingRaces(asOf: now)
        let raceTempByID = Dictionary(upcoming.map { r in
            (r.id, mrSeasonalTemp(runs: fetched, for: r.date) ?? MR_REF_TEMP)
        }, uniquingKeysWith: { old, _ in old })
        #if DEBUG
        do {
            let goalFmt = DateFormatter(); goalFmt.dateFormat = "yyyy-MM-dd"
            print(String(format: "[계획:등록대회] %d건", upcoming.count))
            for r in upcoming {
                let distStr = String(format: "%.1fkm", r.distanceM / 1000.0)
                let goalMin = userInput.goals.minutes(for: r.distanceM)
                let goalStr: String
                if let gm = goalMin {
                    let h = Int(gm) / 60; let m = Int(gm) % 60
                    goalStr = h > 0 ? String(format: "%d:%02d:00", h, m) : String(format: "%02d:00", m)
                } else { goalStr = "--:--" }
                print("  · \(r.name) — \(goalFmt.string(from: r.date)) · \(distStr) · 목표 \(goalStr)")
            }
        }
        #endif
        let (paired, absorbed) = buildRacePairs(upcoming: upcoming, profile: planProfile,
                                                anchors: storedSnapshotAnchors, raceTempByID: raceTempByID,
                                                now: now, caller: "refreshCore")
        absorbedTuneUps = absorbed
        let validPairs = paired.compactMap { p -> (MRTargetRace, MRRacePlan)? in
            guard let pl = p.plan else { return nil }
            return (p.race, pl)
        }
        plans = validPairs.map(\.1)
        checks = validPairs.map { (r, pl) in
            let others = validPairs.filter { $0.0.id != r.id }
            return mrCheckGoal(race: r, plan: pl, goals: userInput.goals,
                               profile: profile, halfEquivMin: he, heat: heat,
                               raceTempC: raceTempByID[r.id] ?? MR_REF_TEMP,
                               otherPlans: others)
        }
        let absorbedIDs = Set(absorbed.map { $0.race.id })
        planlessRaces = paired.filter { $0.plan == nil && !absorbedIDs.contains($0.race.id) }.map(\.race)
        advice = mrBuildAdvice(runs: fetched, phys: phys, plans: plans,
                               races: userInput.races,
                               gaps: [], strengthPerWeek: storedStrengthPerWeek,
                               fatigue: storedFatigue, cadenceShift: storedCadenceShift,
                               heatHR: heatHR,
                               log: adviceLog, asOf: now)
        // ⚠ record()는 여기서 호출하지 않는다.
        //   조언 카드가 화면에 실제로 그려지는 .onAppear에서 호출해야 한다.
        //   판정 시점에 기록하면 화면에 뜬 적 없는 항목이 "보여줬다"로 기록돼
        //   신선도가 차감되어 영영 노출되지 않는다.
        raceDayCard = computeRaceDayCard(plans: plans, asOf: now)
        let raceDayVisible = raceDayCard.map { MRRaceDayView.shouldShow($0) } ?? false
        todayCard = mrTodayCard(runs: fetched, phys: phys, plans: plans,
                                raceDayCardVisible: raceDayVisible,
                                advice: advice, asOf: now)

        #if DEBUG
        print("[추론] 레벨 \(profileFull.level) · 모드 \(profileFull.mode) · 노력 \(efforts.count)건 · 예측 \(predictions.count)건")
        #endif

        // ★ 여기서 화면이 그려진다
        state = .ready
    }

    // MARK: - 2단계: 백그라운드 (화면 이미 표시됨)

    private func refreshDetail() async {
        guard case .ready = state else { return }
        let now = Date()

        let floor = Calendar.current.date(byAdding: .year, value: -1,
                                          to: runs.first?.start ?? now) ?? now

        // ① steps·VO2 fetch를 먼저 시작한다.
        //   HK 콜백은 백그라운드 스레드에서 오므로, 아래 드리프트·백테스트가
        //   메인 액터에서 실행되는 동안 실제로 병렬 진행된다.
        async let stepsTask = hk.fetchDailyStepsIncremental(floor: floor)
        async let vo2Task   = hk.fetchVO2Max()

        // ④ 드리프트 (stepsDaily 불필요 — 대기 없이 실행)
        await timed("refreshDrift") { await self.refreshDrift() }

        // ⑤ 백테스트 (stepsDaily 불필요)
        await timed("refreshBacktest") { await self.refreshBacktest() }

        // steps 결과 수거 — 드리프트·백테스트와 겹쳐 있었으면 이미 도착했을 것
        let steps = (try? await stepsTask) ?? [:]
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
                               races: userInput.races,
                               gaps: gaps, strengthPerWeek: storedStrengthPerWeek,
                               fatigue: storedFatigue, cadenceShift: storedCadenceShift,
                               heatHR: heatHR,
                               log: adviceLog, asOf: now)
        // ⚠ record()는 조언 카드 .onAppear에서 — 판정 시점 호출 금지
        let raceDayVisible2 = raceDayCard.map { MRRaceDayView.shouldShow($0) } ?? false
        todayCard = mrTodayCard(runs: runs, phys: phys, plans: plans,
                                raceDayCardVisible: raceDayVisible2,
                                advice: advice, asOf: now)

        #if DEBUG
        let sorted14 = runs.sorted { $0.date < $1.date }
        let gap14 = sorted14.count > 1
            ? (0..<(sorted14.count - 1)).filter { i in
                (Calendar.current.dateComponents([.day], from: sorted14[i].date, to: sorted14[i + 1].date).day ?? 0) >= 14
              }.count
            : 0
        // 경력 상세는 mrProfileFull 내부 #if DEBUG 에서 출력됨
        print(String(format: "[추론] 경력 %.2f년 · 레벨 %@",
                     profileFull.trainingAgeYears?.value ?? 0, profileFull.level))
        #endif

        // ③ VO2max + 건강 지표 (vo2도 ①에서 시작했으므로 이미 도착했을 것)
        let vo2 = (try? await vo2Task) ?? []
        healthMetrics = mrHealthMetrics(runs: runs,
                                        restingHRSamples: rhrSamples,
                                        vo2Samples: vo2,
                                        stepsDaily: stepsDaily,
                                        asOf: now)
        let h = healthMetrics
        let dn = ["", "일", "월", "화", "수", "목", "금", "토"]
        #if DEBUG
        print("[건강] 루틴 \(h.habitDays.map { dn[$0] }.joined(separator: "·")) · 30일 중 \(h.days30)일 · 90일 \(h.sessions90)회 \(Int(h.km90))km")
        do {
            let rhrNow = h.restingHR.map { String(format: "%.0f", $0) } ?? "없음"
            let rhrLY  = h.restingHRLY.map { String(format: "%.0f", $0) } ?? "없음"
            let vo2Now = h.vo2max.map { String(format: "%.1f", $0) } ?? "없음"
            let vo2LY  = h.vo2maxLY.map { String(format: "%.1f", $0) } ?? "없음"
            print("[성장] 안정시 심박 올해 \(rhrNow) (중앙값·90일) · 작년 \(rhrLY) (중앙값·재계산)")
            print("[성장] VO2max 올해 \(vo2Now) · 작년 \(vo2LY)")
        }
        #endif
    }

    // MARK: - 드리프트 (세그먼트 fetch 병렬화 + 캐시)

    private func refreshDrift() async {
        // ⚠ 기온 범위 15°C 이상이 필요하므로 1년으로 확대.
        //   캐시가 있으면 재계산 안 하므로 첫 실행만 느리다.

        // 빠른 캐시 확인: self.runs는 이미 채워져 있으므로
        // HealthKit 쿼리 없이 마지막 런 시작일로 캐시 적중 여부를 먼저 판단한다.
        let t0 = Date()
        if let lastRunStart = runs.last?.start,
           let cached = MRDriftCacheStore.load(),
           abs(cached.lastWorkoutStart.timeIntervalSince(lastRunStart)) < 1 {
            let m = cached.drift.model
            let elapsed = Date().timeIntervalSince(t0)
            #if DEBUG
            print(String(format: "[드리프트] 캐시 히트 · %@ · %d세션 [⏱ drift-캐시읽기] %.3fs",
                         m.ok ? "성공" : "실패", m.sessions, elapsed))
            #endif
            if m.ok {
                drift = m
                return
            }
            // ok=false: 실패 사유별 TTL — 세그먼트 쿼리 반복 방지
            // 표본 부족·기온 범위 부족 → 7일 (계절 데이터 누적 필요)
            // 기타 실패 → 24시간
            let isSampleOrTempFailure = m.sessions < 15 || m.tempSpanC < 15
            let ttl: TimeInterval = isSampleOrTempFailure ? 7 * 24 * 3600 : 24 * 3600
            let cacheAge = Date().timeIntervalSince(cached.computedAt ?? .distantPast)
            // 러닝 20건 이상 증가 시 TTL 무관 재시도 (계절성 데이터 누적 감지)
            let runGrowth = runs.count - (cached.workoutCountAtCompute ?? runs.count)
            if cacheAge < ttl, runGrowth < 20 {
                drift = m
                #if DEBUG
                let reasonStr: String
                if m.sessions < 15 { reasonStr = "표본부족" }
                else if m.tempSpanC < 15 { reasonStr = "기온범위" }
                else { reasonStr = "기타" }
                let retryDate = (cached.computedAt ?? Date()).addingTimeInterval(ttl)
                let retryDf = DateFormatter(); retryDf.dateFormat = "yyyy-MM-dd"
                print(String(format: "[드리프트] 실패(\(reasonStr)) · 다음 재시도 %@ · %.0fh/%.0fh → HK 쿼리 생략",
                             retryDf.string(from: retryDate), cacheAge / 3600, ttl / 3600))
                #endif
                return
            }
            #if DEBUG
            if runGrowth >= 20 {
                print("[드리프트] 캐시 ok=false · 런 \(runGrowth)건 증가 → TTL 무시, 재계산")
            } else {
                let reasonStr: String
                if m.sessions < 15 { reasonStr = "표본부족" }
                else if m.tempSpanC < 15 { reasonStr = "기온범위" }
                else { reasonStr = "기타" }
                print("[드리프트] 캐시 ok=false TTL 만료 · 실패(\(reasonStr)) · \(Int(cacheAge/3600))h/\(Int(ttl/3600))h → 재계산")
            }
            #endif
        }
        #if DEBUG
        print(String(format: "[드리프트] [⏱ drift-캐시읽기] %.3fs → 미스, HealthKit 쿼리 시작",
                     Date().timeIntervalSince(t0)))
        #endif

        // 캐시 미스: 365일 HKWorkout 목록을 읽어 세그먼트 계산
        let cutoff = Date().addingTimeInterval(-365 * 86400)
        let tHK = Date()
        let recent: [HKWorkout] = (try? await hk.fetchRawRunsSince(cutoff)) ?? []
        #if DEBUG
        print(String(format: "[드리프트] [⏱ drift-HK쿼리] %.3fs · %d건",
                     Date().timeIntervalSince(tHK), recent.count))
        #endif

        // 드물게 runs와 recent의 마지막 워크아웃이 1초 이내면 캐시 재사용
        if let cached = MRDriftCacheStore.load(),
           let lastStart = recent.last?.startDate,
           abs(cached.lastWorkoutStart.timeIntervalSince(lastStart)) < 1 {
            let m = cached.drift.model
            drift = m
            // computedAt이 nil이면 TTL 체크가 항상 만료로 판정 → 갱신해 반복 HK 쿼리 방지
            if cached.computedAt == nil {
                MRDriftCacheStore.save(MRDriftCache(
                    lastWorkoutStart: lastStart, computedAt: Date(), drift: cached.drift,
                    workoutCountAtCompute: cached.workoutCountAtCompute ?? recent.count
                ))
            }
            #if DEBUG
            print("[드리프트] 캐시 히트(HK확인 후) · \(m.ok ? "성공" : "실패") · \(m.sessions)세션")
            #endif
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
        #if DEBUG
        print("[T3] 대상 \(recent.count)건 · 세그먼트 \(segs.count)점")
        #endif

        let intervalStarts = Set(runs.filter(\.isInterval).map(\.start))
        #if DEBUG
        let nonIntSegs    = segs.filter { !intervalStarts.contains($0.workoutStart) }
        let byNonInt      = Dictionary(grouping: nonIntSegs, by: \.workoutStart)
        let goodSessions  = byNonInt.filter { $0.value.count >= 8 }.count
        let thinSessions  = byNonInt.count - goodSessions
        // 필터 단계: HK건수 → 인터벌 제외 → 세그<8 제외 → 최종 유효 세션
        print(String(format: "[드리프트] HK %d건 → 인터벌%d건 제외 → %d세션(세그<8: %d제외) → 세그≥8 %d세션 · 세그먼트 %d점(임계 300점)",
                     recent.count, intervalStarts.count,
                     byNonInt.count, thinSessions, goodSessions, nonIntSegs.count))
        #endif
        let m = mrFitDrift(segments: segs, excludeIntervalStarts: intervalStarts)
        drift = m

        if let last = recent.last?.startDate {
            MRDriftCacheStore.save(MRDriftCache(lastWorkoutStart: last,
                                                computedAt: Date(),
                                                drift: MRDriftModelCodable(m),
                                                workoutCountAtCompute: recent.count))
        }
        #if DEBUG
        print("[드리프트] \(m.ok ? "성공" : "실패") · 15°C기준 \(String(format: "%.1f", m.bpmPer10MinAtRef))bpm/10분 · 기온범위 \(Int(m.tempSpanC))°C · \(m.sessions)세션")
        if !m.ok {
            var reasons = [String]()
            if m.sessions < 15 {
                reasons.append("세션 \(m.sessions)개 (최소 15개 필요)")
            }
            if m.tempSpanC < 15 {
                reasons.append("기온범위 \(Int(m.tempSpanC))°C (최소 15°C 필요)")
            }
            if !(m.bpmPer10MinAtRef > 0 && m.bpmPer10MinAtRef < 15) {
                reasons.append("드리프트 \(String(format: "%.1f", m.bpmPer10MinAtRef))bpm/10분 (0–15 범위 밖)")
            }
            if !reasons.isEmpty {
                print("[드리프트] 실패 사유: \(reasons.joined(separator: " · "))")
            }
        }
        #endif
    }

    // MARK: - 백테스트 (노력 핑거프린트 캐시)

    private func refreshBacktest() async {
        // storedConfirmedMatches가 비었으면 영속 키 폴백 — 310·585·600 세 진입 경로 모두 보장
        if storedConfirmedMatches.filter(\.isConfirmed).isEmpty {
            let fallback = persistedMatchesProvider()
            if !fallback.isEmpty {
                storedConfirmedMatches = fallback
                #if DEBUG
                print("[백테스트] storedConfirmedMatches 비어 있음 → 영속 키 \(fallback.filter(\.isConfirmed).count)건 로드")
                #endif
            }
        }

        // 캐시 키: 자동 감지 노력 핑거프린트 + 확인된 대회 목록
        let effortPart = MRBacktestCacheStore.effortKey(efforts)
        let matchPart = storedConfirmedMatches
            .filter { $0.isConfirmed }
            .sorted { $0.activityID.uuidString < $1.activityID.uuidString }
            .map { "\($0.activityID.uuidString)_\(Int($0.distanceKm * 10))" }
            .joined(separator: "|")
        let key = effortPart + "||" + matchPart

        let rows: [MRBacktestRow]
        if let cached = MRBacktestCacheStore.load(), cached.effortKey == key {
            rows = cached.rows.map(\.row)
            #if DEBUG
            print("[백테스트] 캐시 히트 · \(rows.count)건")
            #endif
        } else {
            // 변환은 main actor에서 미리 처리 → Task.detached에는 Sendable [MRRaceEffort]만 전달
            let addl = mrEffortsFromConfirmedMatches(storedConfirmedMatches, runs: runs)
            let r = runs, rhr = rhrSamples, d = storedDob, s = storedSex, h = heat
            let matchCount = addl.count
            let result = await Task.detached(priority: .userInitiated) {
                mrBacktest(runs: r, restingHRSamples: rhr,
                           dateOfBirth: d, sex: s, heat: h,
                           additionalTargets: addl, asOf: Date())
            }.value
            rows = result
            MRBacktestCacheStore.save(MRBacktestCache(
                effortKey: key,
                rows: result.map(MRBacktestRowCodable.init)
            ))
            #if DEBUG
            print("[백테스트] 완료 · \(result.count)건 → 캐시 저장 (확인 대회 \(matchCount)건 포함)")
            #endif
        }

        backtest = rows

        // σ_obs 재계산 — 백테스트 결과가 startup 캐시와 다르면 profile·predictions 갱신
        let newSigma = mrSigmaObs(backtest: rows)
        if newSigma != storedSigmaObs {
            storedSigmaObs = newSigma
            let now = Date()
            profile = mrProfile(runs: runs, efforts: efforts, sigmaObs: newSigma, asOf: now)
            predictions = mrPredict(efforts: efforts, fit: fit, profile: profile, heat: heat, asOf: now)
            #if DEBUG
            print(String(format: "[σ_obs] 백테스트 %d건 → σ_obs=%.4f (±%.1f%%) · 재계산",
                         rows.count, newSigma, (exp(newSigma) - 1) * 100))
            #endif
        } else {
            #if DEBUG
            print(String(format: "[σ_obs] 백테스트 %d건 → σ_obs=%.4f (±%.1f%%)",
                         rows.count, newSigma, (exp(newSigma) - 1) * 100))
            #endif
        }
    }

    // MARK: - 성장 탭에서 수동 트리거

    func computeBacktestIfNeeded() {
        guard backtest.isEmpty, case .ready = state else { return }
        Task { await self.refreshBacktest() }
    }

    /// 확인된 대회 목록이 바뀌면 캐시 키가 달라져 자동으로 재계산된다.
    /// raceDetectorReady=false 시 영속 키 폴백 매치로 진행 — onChange(of: isReady)가 이후 정식 목록으로 재실행.
    func updateConfirmedMatches(_ matches: [PersistedRaceMatch], raceDetectorReady: Bool = true) {
        guard case .ready = state else { return }
        let confirmedCount = matches.filter(\.isConfirmed).count
        #if DEBUG
        print("[백테스트] raceDetector 준비 = \(raceDetectorReady) · 대회 \(confirmedCount)건")
        if !raceDetectorReady && confirmedCount > 0 {
            print("[백테스트] raceDetector 미준비 — 영속 키 \(confirmedCount)건으로 대체")
        }
        #endif
        storedConfirmedMatches = matches
        Task { await self.refreshBacktest() }
    }

    // MARK: - 근력 횟수·롱런 피로·케이던스 이동 업데이트 (HealthKit 재읽기 없음)

    /// - cadenceShift: 바깥 nil = 변경 없음, 안쪽 nil(.some(nil)) = "이동 없음"으로 설정
    func updateAdvice(strengthPerWeek: Double,
                      fatigue: [MRLongRunFatigue]? = nil,
                      cadenceShift: MRFormShift?? = nil) {
        // ⚠ 입력은 준비 여부와 무관하게 보관한다 — refreshCore/refreshDetail이 이 값을 그대로 쓴다.
        //   준비 전에 guard로 빠지면 성장 탭 첫 진입의 롱런 피로가 영영 비어 있게 된다.
        storedStrengthPerWeek = strengthPerWeek
        if let f = fatigue { storedFatigue = f }
        if let c = cadenceShift { storedCadenceShift = c }
        guard case .ready = state else { return }   // 재계산만 건너뛴다
        let now = Date()
        advice = mrBuildAdvice(runs: runs, phys: phys, plans: plans,
                               races: userInput.races,
                               gaps: gaps, strengthPerWeek: storedStrengthPerWeek,
                               fatigue: storedFatigue, cadenceShift: storedCadenceShift,
                               heatHR: heatHR,
                               log: adviceLog, asOf: now)
        // ⚠ record()는 조언 카드 .onAppear에서 — 판정 시점 호출 금지
        let raceDayVisible3 = raceDayCard.map { MRRaceDayView.shouldShow($0) } ?? false
        todayCard = mrTodayCard(runs: runs, phys: phys, plans: plans,
                                raceDayCardVisible: raceDayVisible3,
                                advice: advice, asOf: now)
    }

    // 언어가 바뀌었을 때 HealthKit 재읽기 없이 todayCard 문자열만 재생성한다.
    func recomputeTodayCard() {
        guard case .ready = state else { return }
        let now = Date()
        let raceDayVisible = raceDayCard.map { MRRaceDayView.shouldShow($0) } ?? false
        todayCard = mrTodayCard(runs: runs, phys: phys, plans: plans,
                                raceDayCardVisible: raceDayVisible,
                                advice: advice, asOf: now)
    }

    // MARK: - 대회·목표 변경 (HealthKit 재읽기 없음)

    /// 대회·목표가 바뀌거나 앱 재기동 직후 플랜만 다시 계산한다.
    /// snapshotAnchors: 대회별 고정 시작 월요일 (mrArchiveKey → monday).
    /// 키가 있으면 계획이 재시작되지 않는다 — 스냅샷 저장 이후 주차 구조가 동결된다.
    /// snapshotWeeks: 대회별 확정 주차 — 따르는 주·이번 주 목표의 단일 소스.
    /// 둘 다 nil이면 마지막에 받은 값을 그대로 쓴다 (언어 전환 재계산이 앵커를 지우지 않게).
    func recomputePlans(snapshotAnchors: [String: Date]? = nil,
                        snapshotWeeks: [String: [MRPlanWeekSummary]]? = nil) {
        guard case .ready = state else { return }
        if let snapshotAnchors { storedSnapshotAnchors = snapshotAnchors }   // refreshCore가 같은 앵커를 쓸 수 있도록 저장
        if let snapshotWeeks { storedSnapshotWeeks = snapshotWeeks }
        let snapshotAnchors = storedSnapshotAnchors
        MRUserInputStore.save(userInput)
        let now = Date()
        let planCutoff2: Date = {
            let cal = Calendar.current
            let wd = cal.component(.weekday, from: now)
            let daysSinceMon = (wd + 5) % 7
            let mondayStart2 = cal.date(byAdding: .day, value: -daysSinceMon,
                                        to: cal.startOfDay(for: now)) ?? now
            return mondayStart2.addingTimeInterval(-1)  // 이번 주 런 전체 제외 (월요일 포함)
        }()
        let planProfile2 = mrProfile(runs: runs, efforts: efforts, asOf: planCutoff2)
        let he = halfEquivMin
        let upcoming = userInput.upcomingRaces(asOf: now)
        let raceTempByID = Dictionary(upcoming.map { r in
            (r.id, mrSeasonalTemp(runs: runs, for: r.date) ?? MR_REF_TEMP)
        }, uniquingKeysWith: { old, _ in old })
        let (paired, absorbed) = buildRacePairs(upcoming: upcoming, profile: planProfile2,
                                                anchors: snapshotAnchors, raceTempByID: raceTempByID,
                                                now: now, caller: "recomputePlans")
        absorbedTuneUps = absorbed
        let validPairs = paired.compactMap { p -> (MRTargetRace, MRRacePlan)? in
            guard let pl = p.plan else { return nil }
            return (p.race, pl)
        }
        plans = validPairs.map(\.1)
        checks = validPairs.map { (r, pl) in
            let others = validPairs.filter { $0.0.id != r.id }
            return mrCheckGoal(race: r, plan: pl, goals: userInput.goals,
                               profile: profile, halfEquivMin: he, heat: heat,
                               raceTempC: raceTempByID[r.id] ?? MR_REF_TEMP,
                               otherPlans: others)
        }
        let absorbedIDs = Set(absorbed.map { $0.race.id })
        planlessRaces = paired.filter { $0.plan == nil && !absorbedIDs.contains($0.race.id) }.map(\.race)
        advice = mrBuildAdvice(runs: runs, phys: phys, plans: plans,
                               races: userInput.races,
                               gaps: gaps, strengthPerWeek: storedStrengthPerWeek,
                               fatigue: storedFatigue, cadenceShift: storedCadenceShift,
                               heatHR: heatHR,
                               log: adviceLog, asOf: now)
        // ⚠ record()는 조언 카드 .onAppear에서 — 판정 시점 호출 금지
        raceDayCard = computeRaceDayCard(plans: plans, asOf: now)
        let raceDayVisible4 = raceDayCard.map { MRRaceDayView.shouldShow($0) } ?? false
        todayCard = mrTodayCard(runs: runs, phys: phys, plans: plans,
                                raceDayCardVisible: raceDayVisible4,
                                advice: advice, asOf: now)
    }

    // MARK: - 내부 헬퍼

    // MARK: - 이번 주를 다스리는 계획

    /// `date`가 속한 주의 (계획, 주차) — 계획이 둘 이상 겹치면 대회일이 가장 이른 계획(그 대회 주까지).
    /// 스냅샷이 있는 계획은 주차표와 같은 숫자를 돌려준다. MRPlanGovernance 참조.
    func governingPlanWeek(for date: Date) -> (plan: MRRacePlan, week: MRPlanWeek)? {
        guard let g = MRPlanGovernance.governingWeek(plans: plans, monday: date) else { return nil }
        let key = mrArchiveKey(raceDate: g.plan.raceDate, distanceM: g.plan.distanceM)
        guard let snap = storedSnapshotWeeks[key], !snap.isEmpty else { return g }
        let fixed = MRPlanGovernance.applyingSnapshot([g.week], snapshot: snap, easyPaceSecPerKm: easyPaceSecPerKm)
        return (g.plan, fixed.first ?? g.week)
    }

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

    // 대회 매칭 → MRRaceEffort 변환 (main actor에서 실행, Sendable 타입만 Task.detached로 전달)
    private func mrEffortsFromConfirmedMatches(_ matches: [PersistedRaceMatch],
                                               runs: [MRWorkout]) -> [MRRaceEffort] {
        let cal = Calendar.current
        return matches
            .filter { $0.isConfirmed }
            .compactMap { match -> MRRaceEffort? in
                let stdDistM = match.distanceKm * 1000
                let label = mrLabelFor(distanceM: stdDistM)
                guard ["5K", "10K", "하프", "풀"].contains(label) else { return nil }

                let sameDayRuns = runs.filter { cal.isDate($0.start, inSameDayAs: match.raceDate) }
                guard let run = sameDayRuns.min(by: {
                    abs(($0.distanceKm ?? 0) - match.distanceKm) < abs(($1.distanceKm ?? 0) - match.distanceKm)
                }), let km = run.distanceKm, km > 0 else { return nil }

                let timeMin = run.durationMin * (stdDistM / (km * 1000))
                return MRRaceEffort(date: run.date, distanceM: stdDistM,
                                   timeMin: timeMin, timeMinRef: timeMin,
                                   tempC: run.tempC, label: label,
                                   isConfirmedRace: true)
            }
    }

    @discardableResult
    private func timed<T>(_ label: String, _ work: () async throws -> T) async rethrows -> T {
        let t0 = CFAbsoluteTimeGetCurrent()
        let result = try await work()
        #if DEBUG
        print(String(format: "[⏱ %@] %.2fs", label, CFAbsoluteTimeGetCurrent() - t0))
        #endif
        return result
    }
}
