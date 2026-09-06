import Foundation
import HealthKit
import WorkoutKit
import CoreLocation
import Observation
import SwiftData

// Thread-safe accumulator for HKWorkoutRouteQuery batched callbacks
private final class LocationBatch: @unchecked Sendable {
    var locations: [CLLocation] = []
}

@Observable
@MainActor
class HealthKitManager {
    var activities: [Activity] = []
    var authorizationStatus: AuthStatus = .notDetermined
    var isLoading = false
    var error: Error?
    var userDateOfBirth: DateComponents? = nil
    var userIsMale: Bool? = nil
    /// 건강 앱 생년월일 미설정 시 수동 입력 나이 (0 = 미설정). UserDefaults 영속.
    var manualAge: Int = {
        let v = UserDefaults.standard.integer(forKey: "mimo.manualAge")
        return v > 0 ? v : 0
    }() {
        didSet { UserDefaults.standard.set(manualAge, forKey: "mimo.manualAge") }
    }

    /// 존 계산에 쓸 나이 소스 존재 여부 — HealthKit DOB 또는 수동 입력 둘 중 하나.
    var hasDOBSource: Bool {
        (userDateOfBirth?.year ?? 0) > 1900 || manualAge > 0
    }
    var userLevel: UserLevel = UserLevel(bucket: .beginner, ageGrade: nil, best5KEquivSec: nil, best5KDate: nil, vdot: nil)
    /// 유형 캐시 버전이 올라간 직후 8주 스플릿 포함 재분류 진행 중 여부.
    var isWorkoutTypeReclassifying = false
    /// 온디맨드 분류 완료 시 1 증가 → 리스트 배지 재렌더링 트리거.
    var workoutTypeRevision: Int = 0
    /// Latest resting HR from HealthKit — used as RHR in Karvonen zone calc
    var restingHeartRate: Int? = nil
    /// 폼 백필 진행 상황. nil = 백필 안 하는 중.
    var formBackfillProgress: (done: Int, total: Int)? = nil

    private let store = HKHealthStore()
    @ObservationIgnored private var workoutCache: [UUID: HKWorkout] = [:]
    @ObservationIgnored private var cachedMHR: Int? = nil
    /// 추정 최대심박(208 − 0.7×나이) — 회복 표시 자격 판정용. 생년월일 없으면 nil.
    var estimatedMaxHR: Int? { cachedMHR }
    @ObservationIgnored private var isFetchInProgress = false
    @ObservationIgnored private var pausedIntervalsCache: [UUID: [DateInterval]] = [:]
    @ObservationIgnored private var detailCache: [UUID: ActivityDetail] = [:] {
        didSet { fatigueMemo = nil }   // 상세가 채워지면 롱런 피로 요약을 다시 계산한다
    }
    /// 존 체류 시간 전용 캐시 — 분류 경로에서 계산한 hrZones를 버리지 않고 강도 분포(4주 합산)에 재사용. 지연 로드.
    @ObservationIgnored private var hrZoneOnlyCache: [String: [HRZoneData]]? = nil
    @ObservationIgnored private var hrSeriesCache: [UUID: [(offset: TimeInterval, bpm: Int)]] = [:]
    /// 불완전(provisional) 캐시 ID — 다음 진입 시 HealthKit 재조회
    @ObservationIgnored private var hrSeriesProvisionalIDs: Set<UUID> = []
    @ObservationIgnored private var panelSeriesCache: [String: [(offset: TimeInterval, value: Double)]] = [:]
    // 동일 지표 동시 요청 시 하나의 Task만 실행 — HealthKit 중복 조회 방지
    @ObservationIgnored private var metricFetchTasks: [String: Task<[(date: Date, value: Double)], Never>] = [:]
    // 백필 중복 실행 방지 — 화면 전환 시 이전 Task 취소 후 새 Task 시작
    @ObservationIgnored private var workoutTypeBackfillTask: Task<Void, Never>?
    /// longRunFatigueSummaries 메모 — 같은 날·같은 활동 목록이면 재계산하지 않는다.
    /// 디스크 상세 캐시 디코드(경로 좌표 포함)가 러닝당 한 번씩 들어가기 때문.
    @ObservationIgnored private var fatigueMemo: (key: String, value: [MRLongRunFatigue])? = nil

    // Codable proxies for disk serialization of time-series tuples
    private struct HRPoint: Codable { var offset: Double; var bpm: Int }
    private struct SeriesPoint: Codable { var offset: Double; var value: Double }
    /// 심박 시리즈 캐시 완전성 메타데이터 — mimo_hr_{uuid}_meta.json
    private struct HRSeriesMeta: Codable {
        var count: Int
        var durationMin: Int
        /// true = 샘플 수 < durationMin×2 — 다음 진입 시 HealthKit 재조회
        var provisional: Bool
    }

    @ObservationIgnored private let cacheContainer: ModelContainer? = {
        let schema = Schema([CachedActivity.self])
        // 의도적 로컬 캐시. CloudKit 금지 — CachedActivity는 non-optional+unique라 CloudKit 규칙 위반. 2026-07 회귀 이력.
        return try? ModelContainer(for: schema,
                                   configurations: ModelConfiguration("activity-cache",
                                                                       schema: schema,
                                                                       isStoredInMemoryOnly: false,
                                                                       cloudKitDatabase: .none))
    }()
    private var cacheContext: ModelContext? { cacheContainer?.mainContext }

    /// True once the background history fetch has reached the beginning of the user's HealthKit data.
    /// Milestone and temperature-distribution facts are suppressed until this is true to avoid false triggers.
    var isHistoryLoadComplete: Bool {
        UserDefaults.standard.bool(forKey: Self.historyCompleteKey)
    }

    /// True when any loaded workout originates from Garmin Connect.
    var hasGarminSource: Bool {
        workoutCache.values.contains {
            $0.sourceRevision.source.bundleIdentifier.lowercased().contains("garmin")
        }
    }

    /// 최근 4주 근력운동 주당 횟수. workoutCache에서 계산 — HealthKit 재조회 없음.
    var strengthPerWeek4w: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let strengthTypes: Set<HKWorkoutActivityType> = [
            .traditionalStrengthTraining, .functionalStrengthTraining,
            .coreTraining, .crossTraining,
        ]
        let count = workoutCache.values.filter {
            strengthTypes.contains($0.workoutActivityType) && $0.startDate >= cutoff
        }.count
        return Double(count) / 4.0
    }

    /// 최근 8주 자격 롱런의 피로 요약. 상세 캐시(메모리 → 디스크)만 읽는다 — HealthKit 재조회 없음.
    /// 상세 캐시가 없는 롱런은 건너뛴다(사용자가 상세를 연 적 없거나 백필 전).
    func longRunFatigueSummaries(asOf: Date = Date()) -> [MRLongRunFatigue] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: asOf)
        let key = "\(today.timeIntervalSince1970)|\(activities.count)|\(activities.first?.id.uuidString ?? "")|\(workoutTypeRevision)"
        if let memo = fatigueMemo, memo.key == key { return memo.value }

        let cutoff8w  = cal.date(byAdding: .day, value: -MRDurabilityCheck.windowDays, to: today) ?? today
        let cutoff16w = cal.date(byAdding: .day, value: -112, to: today) ?? today
        let runs16w = activities.filter { $0.type == .running && $0.date >= cutoff16w && $0.date <= asOf }
        // 실내 러닝도 포함 — 본인이 실제로 해낸 거리 기준. 후보(8주)는 야외만.
        let longest16w = runs16w.map { $0.distance / 1000 }.max() ?? 0

        let runs8w = runs16w.filter { $0.date >= cutoff8w }
        // 단계별 탈락 집계 — 왜 후보가 0인지 로그로 보이게 한다
        var nPrefilter = 0, nNoDetail = 0, nIndoor = 0, nType = 0, nNoSplits = 0
        let minKm = max(10.0, longest16w * 0.7)
        let result: [MRLongRunFatigue] = runs8w.compactMap { a in
            // 값싼 거리·시간 선별을 먼저 — 상세 디코드(경로 좌표 포함)는 후보에만
            let km = a.distance / 1000, mins = a.duration / 60
            guard km >= minKm, mins >= 60 else { return nil }
            nPrefilter += 1
            guard let det = detailFromCache(a.id) else { nNoDetail += 1; return nil }
            guard !det.routeCoordinates.isEmpty else { nIndoor += 1; return nil }          // 야외만
            let wt = cachedWorkoutTypeForStats(for: a.id) ?? det.workoutType
            guard MRDurabilityCheck.isEligibleLongRun(distanceKm: km, durationMin: mins,
                                                      longest16wKm: longest16w,
                                                      workoutType: wt) else { nType += 1; return nil }
            let s = MRDurabilityCheck.summarize(id: a.id, start: a.date,
                                                distanceKm: km, durationMin: mins,
                                                splits: det.splits)
            if s == nil { nNoSplits += 1 }
            return s
        }
        #if DEBUG
        let df = DateFormatter(); df.dateFormat = "M/d"
        print(String(format: "[내구성:후보] 8주 러닝 %d건 · 하한 %.1fkm/60분 통과 %d · 상세없음 %d · 실내 %d · 유형제외 %d · 스플릿부족 %d → 요약 %d건 (16주 최장 %.1fkm)",
                     runs8w.count, minKm, nPrefilter, nNoDetail, nIndoor, nType, nNoSplits, result.count, longest16w))
        for f in result.sorted(by: { $0.start > $1.start }) {
            print(String(format: "[내구성:후보]   %@ %.1fkm · Q1 %@ %.0fspm → Q4 %@ %.0fspm (%+.1f%%) · 전반HR %@",
                         df.string(from: f.start), f.distanceKm,
                         mrFormatPace(f.q1PaceSecPerKm), f.q1Cadence,
                         mrFormatPace(f.q4PaceSecPerKm), f.q4Cadence, -f.cadenceDropPct,
                         f.firstHalfAvgHR.map { String(format: "%.0f", $0) } ?? "—"))
        }
        #endif
        fatigueMemo = (key, result)
        return result
    }

    enum AuthStatus {
        case notDetermined, authorized, denied
    }

    private static let readTypes: Set<HKObjectType> = {
        [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount),
            HKQuantityType(.runningPower),
            HKQuantityType(.runningSpeed),
            HKQuantityType(.runningStrideLength),
            HKQuantityType(.runningVerticalOscillation),
            HKQuantityType(.runningGroundContactTime),
            HKQuantityType(.vo2Max),
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
        ]
    }()

    private static let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    private static let vo2MaxUnit: HKUnit = {
        HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo)
            .unitMultiplied(by: HKUnit(from: "min")))
    }()

    // MARK: - Authorization

    func checkAuthorizationStatus() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationStatus = .denied
            return
        }
        guard UserDefaults.standard.bool(forKey: "hkAuthorizationRequested") else { return }
        // Set authorized and load cached data immediately — don't wait for HK daemon roundtrip.
        authorizationStatus = .authorized
        await fetchActivities()
        // Re-request after data is shown to pick up any new types added since last install.
        // (e.g. dateOfBirth added after initial install — user sees dialog for new type only)
        try? await store.requestAuthorization(toShare: [], read: Self.readTypes)
        // Re-read characteristics in case the user just granted dateOfBirth / biologicalSex
        readBiologicalCharacteristics()
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationStatus = .denied
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            UserDefaults.standard.set(true, forKey: "hkAuthorizationRequested")
            authorizationStatus = .authorized
            await fetchActivities()
        } catch {
            self.error = error
            authorizationStatus = .denied
        }
    }

    // MARK: - Fetch (two-phase)

    // forced=true: 당기기 새로고침 등 명시적 요청. forced=false(기본): 완료 태그 있으면 캐시만 사용.
    func fetchActivities(forced: Bool = false) async {
        // 일회성 마이그레이션: 시간 범위 폴백 추가 이전에 저장된 부분적 HR 시리즈 캐시 삭제
        migrateHRSeriesCacheIfNeeded()
        // 일회성 마이그레이션: 러닝 폼 쿼리 방식 변경(predicateForObjects→timeRange) 후 캐시 재빌드
        migrateRunningMetricCacheIfNeeded()
        // 일회성 마이그레이션: 기온·습도 소급 적용
        migrateWeatherBackfillIfNeeded()
        // 일회성 마이그레이션: 옛 JSON 형식 운동 유형 캐시 → 새 문자열 형식
        migrateWorkoutTypeCacheEntries()

        // 메모리에 데이터 있고 완료 태그가 최근(5분 이내)이면 즉시 반환 — 디스크 I/O·락 없음
        // 5분 초과 시 웜캐시 갱신 허용 — 운동 완료 후 포그라운드 복귀 시 새 운동 감지
        let lastSync = UserDefaults.standard.object(forKey: "mimo.lastSyncedAt") as? Date
        let syncAge = lastSync.map { Date().timeIntervalSince($0) } ?? .infinity
        if !forced, !activities.isEmpty, syncAge < 300 { return }

        guard !isFetchInProgress else { return }
        isFetchInProgress = true
        defer { isFetchInProgress = false }

        // Phase 0: 캐시 먼저 로드 — 강제 종료 후 재실행에서도 즉시 표시
        let cached = loadActivityCache()
        let isWarmCache = !cached.isEmpty
        if isWarmCache && activities.isEmpty {
            activities = cached.map { $0.toActivity() }
            // 캐시 로드 직후 레벨 계산 — 아래 조기 return 경로에서도 레벨이 반영되도록
            userLevel = LevelEngine.compute(activities: activities, dateOfBirth: userDateOfBirth, isMale: userIsMale)
            #if DEBUG
            logWorkoutTypeCacheStats()
            #endif
            // 유형 캐시 버전이 올라간 뒤 처음 실행 → 8주를 스플릿 포함으로 즉시 재분류
            if !UserDefaults.standard.bool(forKey: Self.workoutTypeReadyKey) {
                isWorkoutTypeReclassifying = true
                workoutTypeBackfillTask?.cancel()
                workoutTypeBackfillTask = Task { await self.backfillWorkoutTypes(weeks: 8, forceReclassify: true) }
            }
        }

        // 5분 이내 early return은 위에서 이미 처리됨.
        // 5분 초과 시에는 오늘 자정부터 증분 조회를 실행해 새 운동을 자동 감지.

        // 캐시가 없는 첫 실행만 로딩 표시
        isLoading = !isWarmCache

        // Resolve subscription status and prepare HRZone parameters before HealthKit query.
        await ProManager.shared.checkEntitlements()
        readBiologicalCharacteristics()
        if restingHeartRate == nil { await refreshHRZoneParameters() }

        defer { isLoading = false }

        do {
            let cacheDict = Dictionary(cached.map { ($0.workoutID, $0) }, uniquingKeysWith: { _, new in new })

            if isWarmCache {
                if forced {
                    // ── 강제 새로고침: 전체 대조 (삭제 감지 + 신규 추가) ──
                    // 캐시 기간 전체를 HealthKit와 대조해 삭제된 운동을 제거하고 새 운동을 추가
                    let sinceAll = cached.map(\.date).min() ?? Calendar.current.startOfDay(for: Date())
                    let allHK = try await queryWorkouts(since: sinceAll)
                    let validIDs = Set(allHK.map { $0.uuid.uuidString })

                    // HealthKit에서 사라진 운동을 캐시에서 제거
                    let toDelete = cached.filter { !validIDs.contains($0.workoutID) }
                    if !toDelete.isEmpty, let ctx = cacheContext {
                        toDelete.forEach { ctx.delete($0) }
                        try? ctx.save()
                    }

                    // 남은 캐시로 activities 재건
                    let survivingCache = cached.filter { validIDs.contains($0.workoutID) }
                    activities = survivingCache.map { $0.toActivity() }

                    // 캐시에 없는 신규 운동 추가
                    let survivingIDs = Set(survivingCache.map { $0.workoutID })
                    let newWorkouts = allHK.filter { !survivingIDs.contains($0.uuid.uuidString) }
                    if !newWorkouts.isEmpty {
                        activities = newWorkouts.map { buildSummary(from: $0) } + activities
                        let survivingDict = Dictionary(survivingCache.map { ($0.workoutID, $0) }, uniquingKeysWith: { _, new in new })
                        await enrichAndCache(newWorkouts, cacheDict: survivingDict)
                    }
                    userLevel = LevelEngine.compute(activities: activities, dateOfBirth: userDateOfBirth, isMale: userIsMale)
                    UserDefaults.standard.set(Date(), forKey: "mimo.lastSyncedAt")
                    Task { await self.repairMissingMetrics() }
                    Task { await self.fetchAllOlderHistory() }
                } else {
                    // ── 일반 갱신: 오늘 자정부터 증분 조회 ──
                    let startOfToday = Calendar.current.startOfDay(for: Date())
                    let latestCached = cached.map(\.date).max()
                    let since = latestCached.map { min($0, startOfToday) } ?? startOfToday
                    let fetched = try await queryWorkouts(since: since)
                    let newWorkouts = fetched.filter { cacheDict[$0.uuid.uuidString] == nil }
                    if newWorkouts.isEmpty {
                        // 드리프트 감지 — 캐시가 더 많으면 재건
                        if cached.count > activities.count {
                            activities = cached.map { $0.toActivity() }
                        }
                        userLevel = LevelEngine.compute(activities: activities, dateOfBirth: userDateOfBirth, isMale: userIsMale)
                        UserDefaults.standard.set(Date(), forKey: "mimo.lastSyncedAt")
                        Task { await self.repairMissingMetrics() }
                        Task { await self.fetchAllOlderHistory() }
                        return
                    }
                    activities = newWorkouts.map { buildSummary(from: $0) } + activities
                    await enrichAndCache(newWorkouts, cacheDict: cacheDict)
                    userLevel = LevelEngine.compute(activities: activities, dateOfBirth: userDateOfBirth, isMale: userIsMale)
                    UserDefaults.standard.set(Date(), forKey: "mimo.lastSyncedAt")
                    Task { await self.repairMissingMetrics() }
                    Task { await self.fetchAllOlderHistory() }
                }
            } else {
                // 콜드캐시(최초 실행): 최근 6개월 먼저 표시 후 나머지 백그라운드
                let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? .distantPast
                let recentWorkouts = try await queryWorkouts(since: sixMonthsAgo)
                activities = recentWorkouts.map { buildSummary(from: $0) }
                isLoading = false
                await enrichAndCache(recentWorkouts, cacheDict: cacheDict)
                userLevel = LevelEngine.compute(activities: activities, dateOfBirth: userDateOfBirth, isMale: userIsMale)
                UserDefaults.standard.set(Date(), forKey: "mimo.lastSyncedAt")
                UserDefaults.standard.set(sixMonthsAgo, forKey: "mimo.oldestFetchedDate")
                Task { await self.fetchAllOlderHistory() }
            }
        } catch {
            self.error = error
        }
    }

    // MARK: - Metrics repair (background, metricsChecked flag)

    private enum HRQueryResult {
        case found(Int)  // 쿼리 성공, 샘플 있음
        case notFound    // 쿼리 성공, 샘플 없음 — HealthKit에 진짜 없음
        case failed      // 쿼리 자체 실패 — 다음 실행에서 재시도
    }

    /// SwiftData 마이그레이션 이슈 없는 UserDefaults 기반 체크 집합
    private var repairedWorkoutIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "mimo.repairedIDs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "mimo.repairedIDs") }
    }

    /// avgHeartRate == nil이고 아직 repair 시도 안 한 활동을 최대 20개씩 재조회.
    /// found / notFound → repairedWorkoutIDs에 추가 → 이후 건너뜀.
    /// failed → 추가 안 함 → 다음 실행 재시도.
    private func repairMissingMetrics() async {
        let repaired = repairedWorkoutIDs
        let candidates = activities.filter { $0.avgHeartRate == nil && !repaired.contains($0.id.uuidString) }
        guard !candidates.isEmpty else { return }
        let batch = candidates.prefix(20)

        for activity in batch {
            if workoutCache[activity.id] == nil {
                await fetchSingleWorkout(id: activity.id)
            }
            guard let workout = workoutCache[activity.id] else {
                // HKWorkout 자체 없음 — 영구 확정
                finalizeRepair(for: activity.id, hr: nil)
                continue
            }
            // 1차: 워크아웃 연결 샘플 (Apple Watch 정상 기록)
            if let hr = await queryAvgHeartRate(workout: workout) {
                finalizeRepair(for: activity.id, hr: hr)
                continue
            }
            // 2차: 시간 범위 기반 — 서드파티 앱 독립 기록 커버
            switch await queryAvgHeartRateByTimeRange(start: workout.startDate, end: workout.endDate) {
            case .found(let hr): finalizeRepair(for: activity.id, hr: hr)
            case .notFound:      finalizeRepair(for: activity.id, hr: nil)  // 진짜 없음 → 영구 확정
            case .failed:        break                                        // 일시적 실패 → 다음 실행 재시도
            }
        }
    }

    /// HR 업데이트(있으면) + repairedWorkoutIDs 마킹
    private func finalizeRepair(for activityID: UUID, hr: Int?) {
        if let hr, let idx = activities.firstIndex(where: { $0.id == activityID }) {
            let a = activities[idx]
            let updated = Activity(id: a.id, type: a.type, date: a.date,
                                   duration: a.duration, distance: a.distance,
                                   calories: a.calories, avgHeartRate: hr,
                                   temperatureC: a.temperatureC, humidityPercent: a.humidityPercent)
            activities[idx] = updated
            saveToCache([CachedActivity(from: updated)])  // upsert via @Attribute(.unique)
        }
        var repaired = repairedWorkoutIDs
        repaired.insert(activityID.uuidString)
        repairedWorkoutIDs = repaired
    }

    /// 시간 범위로 심박 조회 — 성공(빈 배열) vs 실패(에러) 구분
    private func queryAvgHeartRateByTimeRange(start: Date, end: Date) async -> HRQueryResult {
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        do {
            let all = try await descriptor.result(for: store)
            if all.isEmpty { return .notFound }
            let sum = all.reduce(0.0) { $0 + $1.quantity.doubleValue(for: Self.bpmUnit) }
            return .found(Int((sum / Double(all.count)).rounded()))
        } catch {
            return .failed
        }
    }

    // MARK: - Background history fetch (3개월씩, 실행당 1회)

    private static let oldestFetchedKey   = "mimo.oldestFetchedDate"
    private static let historyCompleteKey = "mimo.historyComplete"
    private static let emptyMonthCountKey = "mimo.consecutiveEmptyMonths"
    private static let historyFetchVersionKey = "mimo.historyFetchVersion"

    /// 실행당 3개월씩 과거로 fetch — 발열 없음. 6개월 연속 빈 달이면 historyComplete.
    /// historyFetchVersion < 2: 공백 기간으로 잘못 중단된 캐시 리셋 후 재실행.
    private func fetchAllOlderHistory() async {
        // 잘못 중단된 경우 한 번 리셋 (공백 3개월로 중단됐을 수 있음)
        if UserDefaults.standard.integer(forKey: Self.historyFetchVersionKey) < 2 {
            UserDefaults.standard.removeObject(forKey: Self.historyCompleteKey)
            UserDefaults.standard.set(0, forKey: Self.emptyMonthCountKey)
            UserDefaults.standard.set(2, forKey: Self.historyFetchVersionKey)
        }

        guard !UserDefaults.standard.bool(forKey: Self.historyCompleteKey) else { return }

        let end = (UserDefaults.standard.object(forKey: Self.oldestFetchedKey) as? Date)
               ?? Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? .distantPast
        // 3개월씩 fetch — 1개월 기준 대비 3배 빠르게 과거 도달
        let start = Calendar.current.date(byAdding: .month, value: -3, to: end) ?? .distantPast

        guard let workouts = try? await queryWorkouts(since: start, until: end) else { return }
        UserDefaults.standard.set(start, forKey: Self.oldestFetchedKey)

        if workouts.isEmpty {
            let streak = UserDefaults.standard.integer(forKey: Self.emptyMonthCountKey) + 3
            UserDefaults.standard.set(streak, forKey: Self.emptyMonthCountKey)
            // 6개월(2회 연속 빈 3개월 구간) 이상 연속으로 운동 없으면 완료 처리
            if streak >= 6 {
                UserDefaults.standard.set(true, forKey: Self.historyCompleteKey)
            }
            return
        }

        UserDefaults.standard.set(0, forKey: Self.emptyMonthCountKey)

        let cached = loadActivityCache()
        let cacheDict = Dictionary(cached.map { ($0.workoutID, $0) }, uniquingKeysWith: { _, new in new })
        let existingIDs = Set(activities.map { $0.id.uuidString })
        let toAdd = workouts.compactMap { w -> Activity? in
            guard !existingIDs.contains(w.uuid.uuidString) else { return nil }
            return cacheDict[w.uuid.uuidString]?.toActivity() ?? buildSummary(from: w)
        }
        if !toAdd.isEmpty { activities += toAdd }
        await enrichAndCache(workouts, cacheDict: cacheDict)
        userLevel = LevelEngine.compute(activities: activities, dateOfBirth: userDateOfBirth, isMale: userIsMale)
    }

    // MARK: - Enrich helper

    private func enrichAndCache(_ workouts: [HKWorkout], cacheDict: [String: CachedActivity]) async {
        let toEnrich = workouts.filter { cacheDict[$0.uuid.uuidString] == nil }
        if !toEnrich.isEmpty {
            await withTaskGroup(of: Activity?.self) { group in
                for w in toEnrich {
                    guard let a = activities.first(where: { $0.id == w.uuid }) else { continue }
                    group.addTask { await self.enrich(a, workout: w) }
                }
                for await enriched in group {
                    guard let enriched,
                          let idx = activities.firstIndex(where: { $0.id == enriched.id }) else { continue }
                    activities[idx] = enriched
                    saveToCache([CachedActivity(from: enriched)])
                }
            }
        }
        // Background: weather pre-fetch for any workout not yet cached
        Task { await self.prefetchWeather(for: workouts) }
    }

    /// Fetches weather for workouts not yet in ConditionCache.
    /// Processes in small batches to stay within Open-Meteo free-tier limits.
    private func prefetchWeather(for workouts: [HKWorkout]) async {
        for batchStart in stride(from: 0, to: workouts.count, by: 3) {
            let batch = workouts[batchStart..<min(batchStart + 3, workouts.count)]
            await withTaskGroup(of: Void.self) { group in
                for w in batch {
                    group.addTask {
                        let cached = await ConditionCache.shared.condition(for: w.uuid)
                        // Skip only when weather is already stored
                        if let cached, cached.weather != nil { return }
                        let coord = await self.fetchFirstCoordinate(for: w)
                        guard let coord else {
                            // No GPS → mark as tried so we don't re-query routes every launch
                            if cached == nil {
                                await ConditionCache.shared.cache(ActivityCondition(), for: w.uuid)
                            }
                            return
                        }
                        let weather = await ConditionService.fetchWeather(date: w.startDate, coordinate: coord)
                        var cond = cached ?? ActivityCondition()
                        cond.weather = weather
                        await ConditionCache.shared.cache(cond, for: w.uuid)
                    }
                }
            }
        }
    }

    /// Lightweight route query — returns only the first GPS point without loading the full track.
    private func fetchFirstCoordinate(for workout: HKWorkout) async -> CLLocationCoordinate2D? {
        let routes = await fetchWorkoutRoutes(for: workout)
        guard let route = routes.first else { return nil }
        return await withCheckedContinuation { continuation in
            var resumed = false
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, _ in
                guard !resumed else { return }
                if let first = locations?.first {
                    resumed = true
                    continuation.resume(returning: first.coordinate)
                } else if done {
                    resumed = true
                    continuation.resume(returning: nil)
                }
            }
            self.store.execute(query)
        }
    }

    // MARK: - Cache helpers

    private func loadActivityCache() -> [CachedActivity] {
        guard let ctx = cacheContext else { return [] }
        let pro = ProManager.shared
        var descriptor = FetchDescriptor<CachedActivity>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        // Apply the same date gate as queryWorkouts() so Phase 0 cache
        // never flashes activities that are beyond the trial cutoff.
        if pro.isTrialExpired {
            let cutoff = pro.effectiveCutoffDate
            descriptor.predicate = #Predicate<CachedActivity> { $0.date < cutoff }
        }
        return (try? ctx.fetch(descriptor)) ?? []
    }

    private func saveToCache(_ items: [CachedActivity]) {
        guard let ctx = cacheContext else { return }
        for item in items { ctx.insert(item) }
        try? ctx.save()
    }

    // MARK: - Detail (on demand)

    private static let workoutTypeCacheKey  = "mimo.workoutTypeCache.v8"  // v8: RHR min→중앙값 전환 → Zone 경계 변동에 따른 전량 재분류
    private static let workoutTypeReadyKey  = workoutTypeCacheKey + ".ready"  // true = 8주 스플릿 포함 재분류 완료
    private static let formCacheKey         = "mimo.formCache.v1"
    /// 캐시 버전과 무관하게 영속 — 대회 확정 ID는 여기에도 함께 저장해 버전 교체 후에도 baseline에서 제외 보장
    private static let confirmedRaceIDsKey     = "mimo.confirmedRaceIDs.v1"
    /// 전체 PersistedRaceMatch JSON — 백테스트 폴백용 (raceDetector 미준비 시)
    private static let confirmedRaceMatchesKey = "mimo.confirmedRaceMatches.v1"

    // MARK: Form Metrics Cache

    func cachedForm(for id: UUID) -> CachedFormMetrics? {
        loadFormCacheDict()[id.uuidString]
    }

    private func persistForm(_ m: CachedFormMetrics, for id: UUID) {
        var dict = loadFormCacheDict()
        dict[id.uuidString] = m
        saveFormCacheDict(dict)
    }

    /// fetchDetail 결과에서 폼 지표를 추출해 persistForm 호출.
    private func persistFormFromDetail(_ detail: ActivityDetail, for id: UUID) {
        guard detail.avgCadence != nil else { return }
        let act = activities.first { $0.id == id }
        persistForm(CachedFormMetrics(
            cadence:       detail.avgCadence,
            strideLength:  detail.avgStrideLength,
            groundContact: detail.avgGroundContactTime,
            verticalOsc:   detail.avgVerticalOscillation,
            heartRate:     act?.avgHeartRate,
            paceSecPerKm:  act?.paceSecPerKm,
            date:          act?.date ?? Date()
        ), for: id)
    }

    private func loadFormCacheDict() -> [String: CachedFormMetrics] {
        guard let data = UserDefaults.standard.data(forKey: Self.formCacheKey),
              let dict = try? JSONDecoder().decode([String: CachedFormMetrics].self, from: data)
        else { return [:] }
        return dict
    }

    private func saveFormCacheDict(_ dict: [String: CachedFormMetrics]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        UserDefaults.standard.set(data, forKey: Self.formCacheKey)
    }

    /// 캐시 값 파싱: "tempo:1" → (tempo, true) / "tempo" 구형 포맷도 처리 (hasSplits=false)
    private func parseWorkoutTypeEntry(_ raw: String) -> (type: WorkoutType, hasSplits: Bool)? {
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard let typeRaw = parts.first, let t = WorkoutType(rawValue: String(typeRaw)) else { return nil }
        return (t, parts.count > 1 && parts[1] == "1")
    }

    /// 옛 JSON 형식(CachedType{type, hasSplits}) 엔트리를 새 문자열 형식으로 마이그레이션.
    /// 변환 불가 시 해당 키 삭제. 1회만 실행.
    func migrateWorkoutTypeCacheEntries() {
        let migKey = "mimo.migration.workoutTypeCache.jsonFormat.v1"
        guard !UserDefaults.standard.bool(forKey: migKey) else { return }
        struct LegacyCachedType: Codable { let type: String; let hasSplits: Bool }
        var dict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
        var migratedCount = 0, deletedCount = 0
        for (key, raw) in dict {
            guard parseWorkoutTypeEntry(raw) == nil else { continue }
            if let data = raw.data(using: .utf8),
               let legacy = try? JSONDecoder().decode(LegacyCachedType.self, from: data),
               WorkoutType(rawValue: legacy.type) != nil {
                dict[key] = "\(legacy.type):\(legacy.hasSplits ? "1" : "0")"
                migratedCount += 1
            } else {
                dict.removeValue(forKey: key)
                deletedCount += 1
            }
        }
        UserDefaults.standard.set(dict, forKey: Self.workoutTypeCacheKey)
        UserDefaults.standard.set(true, forKey: migKey)
        #if DEBUG
        print("[리스트:유형] 마이그레이션 \(migratedCount)건 / 삭제 \(deletedCount)건")
        #endif
    }

    /// 확인된 대회 ID를 workoutType 캐시 + 별도 영속 키 두 곳에 저장.
    /// workoutType 캐시는 버전 교체로 소실될 수 있으므로, confirmedRaceIDsKey는 절대 지우지 않는다.
    func markConfirmedRaces(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        // ① workoutTypeCache에 race:1 기록
        var dict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
        var changed = false
        for id in ids {
            let key = id.uuidString
            if let raw = dict[key], let entry = parseWorkoutTypeEntry(raw),
               entry.type == .race, entry.hasSplits { continue }
            dict[key] = "race:1"
            changed = true
        }
        if changed { UserDefaults.standard.set(dict, forKey: Self.workoutTypeCacheKey) }
        // ② 버전-무관 영속 키에도 병합 저장
        var persistent = (UserDefaults.standard.array(forKey: Self.confirmedRaceIDsKey) as? [String]) ?? []
        let existingSet = Set(persistent)
        let newEntries = ids.map(\.uuidString).filter { !existingSet.contains($0) }
        if !newEntries.isEmpty {
            persistent.append(contentsOf: newEntries)
            UserDefaults.standard.set(persistent, forKey: Self.confirmedRaceIDsKey)
        }
    }

    /// 캐시 버전과 무관하게 영속된 대회 확정 ID 집합을 반환.
    func persistedConfirmedRaceIDs() -> Set<UUID> {
        let raw = (UserDefaults.standard.array(forKey: Self.confirmedRaceIDsKey) as? [String]) ?? []
        return Set(raw.compactMap { UUID(uuidString: $0) })
    }

    /// 확정 대회 전체 매치를 JSON으로 저장 — raceDetector 미준비 시 백테스트 폴백으로 사용.
    func updatePersistedRaceMatches(_ matches: [PersistedRaceMatch]) {
        guard !matches.isEmpty else { return }
        if let data = try? JSONEncoder().encode(matches) {
            UserDefaults.standard.set(data, forKey: Self.confirmedRaceMatchesKey)
        }
    }

    /// 영속된 전체 매치 배열 반환 — raceDetector 미준비 시 백테스트 폴백.
    func persistedConfirmedMatches() -> [PersistedRaceMatch] {
        guard let data = UserDefaults.standard.data(forKey: Self.confirmedRaceMatchesKey),
              let matches = try? JSONDecoder().decode([PersistedRaceMatch].self, from: data)
        else { return [] }
        return matches
    }

    /// hasSplits=true 엔트리는 hasSplits=false 분류로 덮어쓰지 않는다 — 스플릿 없는 백필 오염 방지
    /// race 확정 엔트리는 어떤 값으로도 덮어쓰지 않는다 — markConfirmedRaces 이후 재분류 오염 방지
    private func persistWorkoutType(_ type: WorkoutType, hasSplits: Bool, for id: UUID) {
        var dict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
        let key = id.uuidString
        if let existing = dict[key], let existingEntry = parseWorkoutTypeEntry(existing) {
            if existingEntry.hasSplits && !hasSplits { return }
            if existingEntry.type == .race { return }
        }
        dict[key] = "\(type.rawValue):\(hasSplits ? "1" : "0")"
        UserDefaults.standard.set(dict, forKey: Self.workoutTypeCacheKey)
    }

    /// engine.runs(WorkoutKit 플랜 기반)에서 인터벌 여부를 읽어 캐시에 없는 항목을 1회 보완한다.
    /// cachedWorkoutType은 .interval만 표시하므로 인터벌 판정만 복원하면 충분하다.
    // TODO: remove after v1.x ships (migration no longer needed)
    func backfillIntervalTypes(from runs: [MRWorkout]) {
        let migKey = "mimo.migration.intervalBackfill.v1"
        guard !UserDefaults.standard.bool(forKey: migKey) else { return }
        let intervalStarts = Set(runs.filter(\.isInterval).map(\.start))
        var dict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
        var added = 0
        for activity in activities where activity.type == .running {
            guard dict[activity.id.uuidString] == nil else { continue }
            if intervalStarts.contains(activity.date) {
                dict[activity.id.uuidString] = WorkoutType.interval.rawValue
                added += 1
            }
        }
        UserDefaults.standard.set(dict, forKey: Self.workoutTypeCacheKey)
        UserDefaults.standard.set(true, forKey: migKey)
        #if DEBUG
        let total = dict.values.filter { $0 == "interval" }.count
        print("[마이그레이션] 인터벌 백필 완료: \(added)건 추가 / 누계 \(total)건")
        #endif
    }

    // MARK: - On-demand list classification
    private var onDemandClassifiedCount = 0
    private var onDemandQueue: [Activity] = []
    private var onDemandProcessing = false
    var isOnDemandClassifying: Bool = false
    private var _sortedRunHistory: [Activity] = []
    private var _sortedRunHistoryCount = 0

    /// activities.count 변화 시 1회 재정렬. 이진 탐색용 캐시.
    private var sortedRunHistory: [Activity] {
        if _sortedRunHistory.isEmpty || _sortedRunHistoryCount != activities.count {
            _sortedRunHistory = activities.filter { $0.type == .running }.sorted { $0.date > $1.date }
            _sortedRunHistoryCount = activities.count
        }
        return _sortedRunHistory
    }

    /// 시점 고정 — date 이전 러닝만 반환. 내림차순 정렬 배열에서 이진 탐색.
    private func historyBefore(date: Date, in sorted: [Activity]) -> [Activity] {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid].date >= date { lo = mid + 1 } else { hi = mid }
        }
        return Array(sorted[lo...])
    }

    /// 리스트 셀 등장 시 호출. 미분류 또는 잠정(hasSplits=false)이면 큐에 추가 후 확정 분류 실행.
    func enqueueOnDemandClassification(activity: Activity) {
        guard activity.type == .running else { return }
        guard !onDemandQueue.contains(where: { $0.id == activity.id }) else { return }
        // 이미 확정(hasSplits=true)인 건은 건너뜀
        let dict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
        if let raw = dict[activity.id.uuidString], parseWorkoutTypeEntry(raw)?.hasSplits == true { return }
        onDemandQueue.append(activity)
        guard !onDemandProcessing else { return }
        Task { await processOnDemandQueue() }
    }

    private func processOnDemandQueue() async {
        guard !onDemandProcessing else { return }
        onDemandProcessing = true
        isOnDemandClassifying = true
        defer { onDemandProcessing = false; isOnDemandClassifying = false }
        let sorted = sortedRunHistory
        while !onDemandQueue.isEmpty {
            let batch = Array(onDemandQueue.prefix(10))
            onDemandQueue.removeFirst(min(10, onDemandQueue.count))
            var batchCounts: [String: Int] = [:]
            for act in batch {
                // 배치 집어들 때 다른 경로(백필 등)가 확정으로 저장했을 수도 있으므로 재확인
                let dict2 = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
                if let raw = dict2[act.id.uuidString], parseWorkoutTypeEntry(raw)?.hasSplits == true { continue }

                var actSplits: [SplitData] = []
                var actSegments: [IntervalSegment] = []
                var actHRZones: [HRZoneData] = []
                if let cached = detailCache[act.id] {
                    actSplits = cached.splits; actSegments = cached.intervalSegments; actHRZones = cached.hrZones
                } else if let disk = loadDetailFromDisk(act.id) {
                    actSplits = disk.splits; actSegments = disk.intervalSegments; actHRZones = disk.hrZones
                }
                if actSplits.isEmpty {
                    let fetched = await fetchSplitsAndSegmentsForBackfill(activity: act)
                    actSplits = fetched.splits
                    if actSegments.isEmpty { actSegments = fetched.segments }
                }
                if actHRZones.isEmpty {
                    if workoutCache[act.id] == nil { let _ = await fetchSplitsAndSegmentsForBackfill(activity: act) }
                    if let wo = workoutCache[act.id] { actHRZones = await queryHRZones(workout: wo) }
                }
                persistHRZones(actHRZones, for: act.id)
                let hist = historyBefore(date: act.date, in: sorted)
                let zones4Classify: [HRZoneData]? = actHRZones.isEmpty ? nil : actHRZones
                let wt = WorkoutTypeClassifier.classify(
                    activity: act, history: hist,
                    splits: actSplits, intervalSegments: actSegments, hrZones: zones4Classify
                )
                persistWorkoutType(wt, hasSplits: !actSplits.isEmpty, for: act.id)
                onDemandClassifiedCount += 1
                batchCounts[wt.rawValue, default: 0] += 1
            }
            let savedCount = batchCounts.values.reduce(0, +)
            if savedCount > 0 { workoutTypeRevision += 1 }
            #if DEBUG
            if !batchCounts.isEmpty {
                let totalRuns = activities.filter { $0.type == .running }.count
                let typeStr = batchCounts.sorted { $0.value > $1.value }
                    .map { "\($0.key) \($0.value)" }.joined(separator: " · ")
                print("[리스트:유형] 확정분류 +\(savedCount)건 (누적 \(onDemandClassifiedCount)/\(totalRuns)) · \(typeStr)")
            }
            #endif
            await Task.yield()
        }
    }

    /// 폼 기준선 입력 데이터.
    /// 상세 캐시(detailCache) 우선, 없으면 UserDefaults 폼 캐시 사용.
    var formInputs: [FormInput] {
        let formDict = loadFormCacheDict()
        return activities.compactMap { a -> FormInput? in
            if let det = detailCache[a.id] { return FormInput(activity: a, detail: det) }
            guard let f = formDict[a.id.uuidString] else { return nil }
            return FormInput(activity: a, cached: f)
        }
    }

#if DEBUG
    /// [리스트:유형] 운동 유형 캐시 적중률 로그. Phase 0 캐시 로드 직후 1회 호출.
    private func logWorkoutTypeCacheStats() {
        let dict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
        let runs = activities.filter { $0.type == .running }
        var success = 0, missingCount = 0, parseFailCount = 0, failReasons: [String] = []
        for run in runs {
            let key = run.id.uuidString
            if let raw = dict[key] {
                if parseWorkoutTypeEntry(raw) != nil { success += 1 }
                else { parseFailCount += 1; failReasons.append("파싱실패(\(raw))") }
            } else {
                missingCount += 1
            }
        }
        let failCount = missingCount + parseFailCount
        print("[리스트:유형] 캐시 조회 \(runs.count)건 / 디코딩 성공 \(success)건 / 실패 \(failCount)건 (미등록 \(missingCount)건 · 파싱실패 \(parseFailCount)건)")
        if !failReasons.isEmpty {
            print("[리스트:유형] 디코딩 실패 사유: \(failReasons.prefix(5).joined(separator: ", "))")
        }
        var confirmed = 0, provisional = 0
        for run in runs {
            guard let raw = dict[run.id.uuidString],
                  let entry = parseWorkoutTypeEntry(raw) else { continue }
            if entry.hasSplits { confirmed += 1 } else { provisional += 1 }
        }
        print("[리스트:배지] 확정 \(confirmed)건 · 잠정 \(provisional)건")
    }
    #endif

    /// Returns the workout type for display in the list. Checks memory → UserDefaults (persists across launches).
    func cachedWorkoutType(for activityID: UUID) -> WorkoutType? {
        let type: WorkoutType
        if let detail = detailCache[activityID] {
            type = detail.workoutType
        } else {
            let dict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
            guard let raw = dict[activityID.uuidString],
                  let entry = parseWorkoutTypeEntry(raw) else { return nil }
            type = entry.type
        }
        return type == .interval ? .interval : nil
    }

    /// Returns all workout types from cache (for training distribution stats).
    /// UserDefaults hasSplits=true (백필) 최우선 → detailCache → on-demand(hasSplits=false) 순서.
    /// detailCache에 구버전 분류가 있어도 백필이 저장한 최신 값이 우선한다.
    func cachedWorkoutTypeForStats(for id: UUID) -> WorkoutType? {
        let dict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
        if let raw = dict[id.uuidString], let entry = parseWorkoutTypeEntry(raw), entry.hasSplits {
            return entry.type   // 스플릿 포함 확정 — 최우선
        }
        if let detail = detailCache[id] { return detail.workoutType }  // detailCache 폴백
        if let raw = dict[id.uuidString], let entry = parseWorkoutTypeEntry(raw) {
            return entry.type   // on-demand 잠정
        }
        return nil
    }

    /// hasSplits=false 로 저장된 엔트리는 잠정 분류 — 배지를 흐리게 표시.
    /// 상세 진입 후 스플릿 포함 재분류 시 false 로 바뀌어 확정됨.
    func isProvisionalWorkoutType(for id: UUID) -> Bool {
        if detailCache[id] != nil { return false }
        let dict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
        guard let raw = dict[id.uuidString],
              let entry = parseWorkoutTypeEntry(raw) else { return false }
        return !entry.hasSplits
    }

    /// 백필 전용 — 워크아웃 한 건의 스플릿·인터벌 세그먼트를 HealthKit에서 가볍게 조회.
    /// `workoutCache`에 없으면 `fetchSingleWorkout`으로 보완. 실패 시 빈 튜플 반환.
    private func fetchSplitsAndSegmentsForBackfill(activity: Activity) async -> (splits: [SplitData], segments: [IntervalSegment]) {
        if workoutCache[activity.id] == nil { await fetchSingleWorkout(id: activity.id) }
        guard let workout = workoutCache[activity.id] else { return ([], []) }
        async let splitsTask   = querySplits(workout: workout)
        async let segmentsTask = queryIntervalSegments(workout: workout)
        return await (splitsTask, segmentsTask)
    }

    /// 8주 이내 러닝을 스플릿 포함으로 분류해 저장.
    /// - forceReclassify: true → hasSplits=false 잠정 분류도 재처리 (캐시 버전 교체 후 즉시 정확화)
    /// 배치당 10건, 최대 8배치(강제재분류 시), 배치 사이 5초 대기.
    func backfillWorkoutTypes(weeks: Int = 4, forceReclassify: Bool = false) async {
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -max(weeks, 8), to: Date()) ?? .distantPast
        let dict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]

        let allRuns = activities.filter { $0.type == .running && $0.date >= cutoff }
        let toProcess: [Activity]
        if forceReclassify {
            // hasSplits=false(잠정) 및 nil 모두 대상
            toProcess = allRuns.filter { act in
                guard let raw = dict[act.id.uuidString] else { return true }
                return parseWorkoutTypeEntry(raw)?.hasSplits == false
            }.sorted { $0.date > $1.date }
        } else {
            // 미분류(nil)와 잠정(hasSplits=false) 모두 대상 — 8주 창은 항상 확정으로 수렴
            toProcess = allRuns.filter { act in
                guard let raw = dict[act.id.uuidString] else { return true }
                return parseWorkoutTypeEntry(raw)?.hasSplits == false
            }.sorted { $0.date > $1.date }
        }

        #if DEBUG
        let df = DateFormatter(); df.dateFormat = "M/d"
        if forceReclassify {
            print("[유형:재분류] \(max(weeks, 8))주 \(allRuns.count)건 — 스플릿 포함 배치 처리 (대상 \(toProcess.count)건)")
        } else {
            let nilCount = allRuns.filter { dict[$0.id.uuidString] == nil }.count
            let provisionalInTarget = toProcess.count - nilCount
            print("[유형:재분류] \(max(weeks, 8))주 \(allRuns.count)건 중 대상 \(toProcess.count)건 (미분류 \(nilCount) · 잠정 \(provisionalInTarget))")
        }
        if !toProcess.isEmpty {
            let dates = toProcess.map { df.string(from: $0.date) }.joined(separator: ", ")
            print("[유형:재분류] 캐시 없는/잠정 \(toProcess.count)건 = \(dates)")
        }
        #endif

        guard !toProcess.isEmpty else {
            if forceReclassify {
                UserDefaults.standard.set(true, forKey: Self.workoutTypeReadyKey)
                isWorkoutTypeReclassifying = false
            }
            return
        }

        // prefix(30) 제거: 7/19 같은 과거 런을 분류할 때 그 이전 히스토리가 0건이 되는 버그 수정
        let allRunHistory = activities
            .filter { $0.type == .running }
            .sorted { $0.date > $1.date }

        let batchSize = 10
        let maxBatches = forceReclassify ? 12 : 5  // 강제재분류 시 최대 120건 처리

        #if DEBUG
        let logDF = DateFormatter(); logDF.dateFormat = "M/d"
        #endif

        for batchIdx in 0..<maxBatches {
            guard !Task.isCancelled else {
                #if DEBUG
                print("[유형:재분류] 취소됨 (배치 \(batchIdx + 1) 이전)")
                #endif
                return
            }
            let start = batchIdx * batchSize
            guard start < toProcess.count else { break }
            let batch = Array(toProcess[start..<min(start + batchSize, toProcess.count)])

            #if DEBUG
            print("[훈련배분] 배치 \(batchIdx + 1): \(batch.count)건 (히스토리 \(allRunHistory.count)건 · 스플릿 조회 포함)")
            #endif

            var confirmedCount = 0, provisionalCount = 0
            for act in batch {
                var actSplits: [SplitData] = []
                var actSegments: [IntervalSegment] = []
                var actHRZones: [HRZoneData] = []
                if let cached = detailCache[act.id] {
                    actSplits    = cached.splits
                    actSegments  = cached.intervalSegments
                    actHRZones   = cached.hrZones
                } else if let disk = loadDetailFromDisk(act.id) {
                    actSplits    = disk.splits
                    actSegments  = disk.intervalSegments
                    actHRZones   = disk.hrZones
                } else {
                    let fetched  = await fetchSplitsAndSegmentsForBackfill(activity: act)
                    actSplits    = fetched.splits
                    actSegments  = fetched.segments
                    // fetchSplitsAndSegmentsForBackfill이 workoutCache를 채워줬으므로 hrZones 즉시 조회
                    if let wo = workoutCache[act.id] {
                        actHRZones = await queryHRZones(workout: wo)
                    }
                }
                // 디스크 캐시 구버전이라 splits가 비어있으면 HK에서 보완 — hasSplits=true 보장
                if actSplits.isEmpty {
                    let fetched = await fetchSplitsAndSegmentsForBackfill(activity: act)
                    actSplits = fetched.splits
                    if actSegments.isEmpty { actSegments = fetched.segments }
                }
                // 디스크 캐시가 구버전이라 hrZones가 비어있는 경우 HK에서 보완
                if actHRZones.isEmpty {
                    if workoutCache[act.id] == nil {
                        let _ = await fetchSplitsAndSegmentsForBackfill(activity: act)
                    }
                    if let wo = workoutCache[act.id] {
                        actHRZones = await queryHRZones(workout: wo)
                    }
                }
                persistHRZones(actHRZones, for: act.id)
                let zones4Classify: [HRZoneData]? = actHRZones.isEmpty ? nil : actHRZones
                let cachedEntry = (UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey)
                    as? [String: String] ?? [:])[act.id.uuidString].flatMap { parseWorkoutTypeEntry($0) }
                #if DEBUG
                let (type, trace) = WorkoutTypeClassifier.classifyWithTrace(
                    activity: act, history: allRunHistory,
                    splits: actSplits, intervalSegments: actSegments, hrZones: zones4Classify,
                    existingType: cachedEntry?.type
                )
                #else
                let type = WorkoutTypeClassifier.classify(
                    activity: act, history: allRunHistory,
                    splits: actSplits, intervalSegments: actSegments, hrZones: zones4Classify,
                    existingType: cachedEntry?.type
                )
                #endif
                persistWorkoutType(type, hasSplits: !actSplits.isEmpty, for: act.id)
                if actSplits.isEmpty { provisionalCount += 1 } else { confirmedCount += 1 }
                #if DEBUG
                let distKm  = String(format: "%.1f", act.distance / 1000)
                let paceStr = act.paceSecPerKm.map { "\(Int($0)/60)'\(String(format: "%02d", Int($0)%60))\"" } ?? "?"
                let planStr = actSegments.filter { $0.stepLabel == "운동" }.count
                let z2Str: String = {
                    guard let z = zones4Classify, !z.isEmpty else { return " Zone2 없음" }
                    let pct = Int((z.filter { $0.id <= 2 }.map(\.fraction).reduce(0, +) * 100).rounded())
                    return " Zone2 \(pct)%"
                }()
                let hrStr = act.avgHeartRate.map { " 심박\($0)" } ?? ""
                if let oldType = detailCache[act.id]?.workoutType, oldType != type {
                    print("[유형:판정:상세] \(logDF.string(from: act.date)) \(distKm)km → \(oldType.koreanLabel) → \(type.koreanLabel) (detailCache 재판정)")
                }
                print("[유형:판정] \(logDF.string(from: act.date)) \(distKm)km \(paceStr)\(z2Str)\(hrStr) splits=\(actSplits.count) 플랜=\(planStr > 0 ? "\(planStr)회" : "없음") → \(type.koreanLabel) (\(trace))")
                #endif
                await Task.yield()
            }
            #if DEBUG
            print("[훈련배분] 배치 \(batchIdx + 1) 완료: \(batch.count)건 → 확정 저장 \(confirmedCount)건 · 잠정 \(provisionalCount)건")
            #endif

            let hasMore = (start + batchSize) < toProcess.count
            if hasMore && batchIdx + 1 < maxBatches {
                try? await Task.sleep(for: .seconds(5))
            }
        }

        #if DEBUG
        let processed = min(toProcess.count, batchSize * maxBatches)
        if forceReclassify {
            print("[유형:재분류] 완료 — \(processed)건 스플릿 포함 재분류")
        } else {
            print("[훈련배분] 백필 완료 — 총 \(processed)건")
        }
        #endif

        workoutTypeRevision += 1
        if forceReclassify {
            UserDefaults.standard.set(true, forKey: Self.workoutTypeReadyKey)
            isWorkoutTypeReclassifying = false
        }
    }

    /// 열람 러닝 기준 4주 창의 미분류(hasSplits=false 포함) 러닝을 스플릿 포함으로 즉시 백필.
    /// 이미 hasSplits=true 캐시가 있는 항목은 건너뜀 — 두 번째 방문부터 비용 0.
    func backfillWorkoutTypesAroundActivity(_ activity: Activity) async {
        guard activity.type == .running else { return }
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: activity.date) ?? .distantPast
        let dict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
        let windowRuns = activities
            .filter { $0.type == .running && $0.date >= cutoff && $0.date <= activity.date }
        let toProcess = windowRuns.filter { act in
            guard let raw = dict[act.id.uuidString],
                  let entry = parseWorkoutTypeEntry(raw) else { return true }
            return !entry.hasSplits  // 잠정 분류 → 재분류
        }.sorted { $0.date > $1.date }

        guard !toProcess.isEmpty else {
            #if DEBUG
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            print("[훈련배분] 창 \(df.string(from: cutoff)) ~ \(df.string(from: activity.date)) · 미분류 0건 → 건너뜀")
            #endif
            return
        }
        #if DEBUG
        let df2 = DateFormatter(); df2.dateFormat = "yyyy-MM-dd"
        print("[훈련배분] 창 \(df2.string(from: cutoff)) ~ \(df2.string(from: activity.date)) · 미분류 \(toProcess.count)건 → 온디맨드 백필")
        #endif

        let allRunHistory = activities
            .filter { $0.type == .running }
            .sorted { $0.date > $1.date }

        for act in toProcess {
            guard !Task.isCancelled else { return }
            var actSplits: [SplitData] = []
            var actSegments: [IntervalSegment] = []
            var actHRZones: [HRZoneData] = []
            if let cached = detailCache[act.id] {
                actSplits = cached.splits; actSegments = cached.intervalSegments; actHRZones = cached.hrZones
            } else if let disk = loadDetailFromDisk(act.id) {
                actSplits = disk.splits; actSegments = disk.intervalSegments; actHRZones = disk.hrZones
            }
            if actSplits.isEmpty {
                let fetched = await fetchSplitsAndSegmentsForBackfill(activity: act)
                actSplits = fetched.splits
                if actSegments.isEmpty { actSegments = fetched.segments }
            }
            if actHRZones.isEmpty {
                if workoutCache[act.id] == nil { let _ = await fetchSplitsAndSegmentsForBackfill(activity: act) }
                if let wo = workoutCache[act.id] { actHRZones = await queryHRZones(workout: wo) }
            }
            persistHRZones(actHRZones, for: act.id)
            let zones4Classify: [HRZoneData]? = actHRZones.isEmpty ? nil : actHRZones
            let backfillCached = (UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey)
                as? [String: String] ?? [:])[act.id.uuidString].flatMap { parseWorkoutTypeEntry($0) }
            let type = WorkoutTypeClassifier.classify(
                activity: act,
                history: historyBefore(date: act.date, in: allRunHistory),
                splits: actSplits, intervalSegments: actSegments, hrZones: zones4Classify,
                existingType: backfillCached?.type
            )
            persistWorkoutType(type, hasSplits: !actSplits.isEmpty, for: act.id)
            await Task.yield()
        }
        workoutTypeRevision += 1
    }

    // MARK: - Form Metrics Backfill

    /// 최근 N개월 러닝의 폼 지표(케이던스·보폭·지면접촉·수직진폭)를
    /// HealthKit에서 가볍게 조회해 UserDefaults 캐시에 저장.
    /// 배치당 50건, 최대 5배치(250건). 배치 사이 3초 대기.
    /// 전체 ActivityDetail(무거움)은 부르지 않음.
    /// - Returns: 이번 호출에서 새로 처리한 항목 수 (기준선 재계산 여부 판단에 사용)
    @discardableResult
    func backfillFormMetrics(months: Int = 12) async -> Int {
        // v2: processed 키 변경 → 과거 편중 세트 리셋, 균등 샘플링으로 재시도
        let processedKey = "mimo.formBackfill.processed.v2"
        var processed = Set(UserDefaults.standard.stringArray(forKey: processedKey) ?? [])
        let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? .distantPast

        let batchSize = 50
        let maxBatches = 5
        var totalDone = 0

        // 세션 전체 처리 예정량 (진행 표시용, 최대 250)
        let initialDict = loadFormCacheDict()
        let total12m   = activities.filter { $0.type == .running && $0.date >= cutoff }.count
        let total12m3k = activities.filter { $0.type == .running && $0.date >= cutoff && $0.distance >= 3000 }.count
        print("[FormBackfill] 12개월 러닝 \(total12m)건 / 3km이상 \(total12m3k)건 / 캐시 \(initialDict.count)건")

        let sessionTotal = min(
            activities
                .filter { $0.type == .running && $0.date >= cutoff }
                .filter { initialDict[$0.id.uuidString] == nil && !processed.contains($0.id.uuidString) }
                .count,
            batchSize * maxBatches
        )

        guard sessionTotal > 0 else {
            print("[FormBackfill] 처리할 항목 없음 (캐시 \(initialDict.count)건)")
            return 0
        }

        for batchIndex in 1...maxBatches {
            guard !Task.isCancelled else { break }

            var formDict = loadFormCacheDict()

            // 대상: 러닝 + 기간 내 + 폼 캐시 없음 + 미처리 — 오름차순 후 균등 stride 샘플링
            let available = activities
                .filter { $0.type == .running && $0.date >= cutoff }
                .filter { formDict[$0.id.uuidString] == nil && !processed.contains($0.id.uuidString) }
                .sorted { $0.date < $1.date }  // 오래된 것부터 → 12개월 전체 고르게 커버

            guard !available.isEmpty else { break }

            let step = max(1, available.count / batchSize)
            let targets = stride(from: 0, to: available.count, by: step)
                .prefix(batchSize)
                .map { available[$0] }

            print("[FormBackfill] 배치 \(batchIndex)/\(maxBatches) — \(targets.count)건 시작 (stride \(step), 누적 \(totalDone)/\(sessionTotal))")

            let targetIDs = Set(targets.map(\.id))
            // 가장 오래된 선택 활동 기준으로 쿼리 기간 설정 (오름차순 정렬 → first가 최고오래됨)
            let minDate = targets.first?.date.addingTimeInterval(-3600) ?? cutoff

            // 해당 기간 HKWorkout 일괄 조회
            let hkWorkouts: [HKWorkout]
            do { hkWorkouts = try await queryWorkouts(since: minDate, until: Date()) }
            catch {
                print("[FormBackfill] workout 조회 실패: \(error)")
                break
            }

            let workoutMap = Dictionary(
                hkWorkouts
                    .filter { targetIDs.contains($0.uuid) && $0.workoutActivityType == .running }
                    .map { ($0.uuid, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            var batchDone = 0
            for act in targets {
                guard !Task.isCancelled else { break }
                defer { processed.insert(act.id.uuidString) }

                guard let workout = workoutMap[act.id] else { continue }

                // 4지표 동시 조회 (같은 workout → 단일 기간)
                async let cad  = queryCadence(workout: workout)
                async let gct  = queryAvgQuantity(.runningGroundContactTime,
                                                   unit: .secondUnit(with: .milli), workout: workout)
                async let str  = queryAvgQuantity(.runningStrideLength,
                                                   unit: .meter(), workout: workout)
                async let vOsc = queryAvgQuantity(.runningVerticalOscillation,
                                                   unit: .meterUnit(with: .centi), workout: workout)

                let (cadence, groundContact, strideLen, vertOsc) = await (cad, gct, str, vOsc)
                formDict[act.id.uuidString] = CachedFormMetrics(
                    cadence:       cadence,
                    strideLength:  strideLen,
                    groundContact: groundContact,
                    verticalOsc:   vertOsc,
                    heartRate:     act.avgHeartRate,
                    paceSecPerKm:  act.paceSecPerKm,
                    date:          act.date
                )
                batchDone += 1
                totalDone += 1
                formBackfillProgress = (done: totalDone, total: sessionTotal)

                #if DEBUG
                if batchDone % 5 == 0 || batchDone == targets.count {
                    print("[FormBackfill] \(batchDone)/\(targets.count) (배치 \(batchIndex)) 케이던스 있음: \(cadence != nil)")
                }
                #endif

                await Task.yield()
            }

            saveFormCacheDict(formDict)
            UserDefaults.standard.set(Array(processed), forKey: processedKey)
            print("[FormBackfill] 배치 \(batchIndex)/\(maxBatches) 완료 — 누적 \(totalDone)건, 캐시 총 \(loadFormCacheDict().count)건")

            // Task가 취소됐거나 배치가 중간에 끊겼으면 종료
            if Task.isCancelled || batchDone < targets.count { break }

            // 남은 항목 확인 — 없으면 종료, 있으면 다음 배치
            let nextDict = loadFormCacheDict()
            let remaining = activities
                .filter { $0.type == .running && $0.date >= cutoff }
                .filter { nextDict[$0.id.uuidString] == nil && !processed.contains($0.id.uuidString) }
                .count
            guard remaining > 0, batchIndex < maxBatches else { break }

            print("[FormBackfill] \(remaining)건 남음 — \(batchIndex + 1)번째 배치 (3초 대기)")
            do { try await Task.sleep(nanoseconds: 3_000_000_000) }
            catch { break }  // 취소 시 즉시 종료
        }

        formBackfillProgress = nil
        print("[FormBackfill] 세션 완료 — 총 처리 \(totalDone)건")
        return totalDone
    }

    func fetchDetail(for activityID: UUID) async -> ActivityDetail? {
        #if DEBUG
        // 캐시히트 여부와 관계없이 workoutTypeCache 누적 현황 출력
        defer {
            let _d = UserDefaults.standard
                .dictionary(forKey: Self.workoutTypeCacheKey)
                as? [String: String] ?? [:]
            let _ic = _d.values.filter { parseWorkoutTypeEntry($0)?.type == .interval }.count
            print("[유형] 인터벌 \(_ic)/\(_d.count)건")
        }
        #endif
        if let cached = detailCache[activityID], cached.isComplete { return cached }
        if var disk = loadDetailFromDisk(activityID), disk.isComplete {
            // [29] 이미 확정(hasSplits=true)된 분류가 있으면 재판정 건너뜀 — 매 실행 반복 방지
            let wtDict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
            if let raw = wtDict[activityID.uuidString], let entry = parseWorkoutTypeEntry(raw), entry.hasSplits {
                if disk.workoutType != entry.type {
                    disk.workoutType = entry.type
                    saveDetailToDisk(disk, id: activityID)
                }
                detailCache[activityID] = disk
                persistFormFromDetail(disk, for: activityID)
                return disk
            }
            // 디스크의 workoutType은 구버전 분류기 결과일 수 있으므로 현재 분류기로 재계산
            var actHRZones = disk.hrZones
            if actHRZones.isEmpty, let wo = workoutCache[activityID] {
                actHRZones = await queryHRZones(workout: wo)
            }
            persistHRZones(actHRZones, for: activityID)
            let zones4Classify: [HRZoneData]? = actHRZones.isEmpty ? nil : actHRZones
            let oldType = disk.workoutType
            if let act = activities.first(where: { $0.id == activityID }) {
                let hist = historyBefore(date: act.date, in: sortedRunHistory)
                let type = WorkoutTypeClassifier.classify(
                    activity: act, history: hist,
                    splits: disk.splits, intervalSegments: disk.intervalSegments, hrZones: zones4Classify
                )
                disk.workoutType = type
                #if DEBUG
                let df = DateFormatter(); df.dateFormat = "M/d"
                let paceStr = act.paceSecPerKm.map { "\(Int($0)/60)'\(String(format: "%02d", Int($0)%60))\"" } ?? "?"
                let z2Str: String = zones4Classify.map { z in
                    "Zone2 \(Int((z.filter { $0.id <= 2 }.map(\.fraction).reduce(0, +) * 100).rounded()))% "
                } ?? ""
                let cacheTag = type != oldType ? " · 상세캐시 갱신" : ""
                print("[유형:판정:상세] \(df.string(from: act.date)) \(String(format: "%.1f", act.distance/1000))km \(paceStr) \(z2Str)splits=\(disk.splits.count) → \(type.koreanLabel) (디스크 재판정\(cacheTag))")
                #endif
                // 재판정 결과가 바뀌었으면 디스크 캐시도 갱신 — 다음 실행에서 또 재판정 방지
                if type != oldType { saveDetailToDisk(disk, id: activityID) }
            }
            detailCache[activityID] = disk
            persistWorkoutType(disk.workoutType, hasSplits: !disk.splits.isEmpty, for: activityID)
            persistFormFromDetail(disk, for: activityID)
            return disk
        }
        let result = await fetchDetailFromHealthKit(for: activityID)
        if let result {
            detailCache[activityID] = result
            persistHRZones(result.hrZones, for: activityID)
            // Only persist when data is complete so the next visit retries HealthKit
            // if fields like GPS route were still being processed at the time of fetch.
            if result.isComplete { saveDetailToDisk(result, id: activityID) }
            #if DEBUG
            let _oldDict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
            let _oldType = _oldDict[activityID.uuidString].flatMap { WorkoutType(rawValue: $0) }
            let _act = activities.first { $0.id == activityID }
            let _df  = DateFormatter(); _df.dateFormat = "M/d"
            let _ds  = _act.map { _df.string(from: $0.date) } ?? "?"
            let _km  = _act.map { String(format: "%.1f", $0.distance/1000) } ?? "?"
            let _ps: String
            if let a = _act, let sec = a.paceSecPerKm {
                _ps = "\(Int(sec)/60)'\(String(format: "%02d", Int(sec)%60))\""
            } else { _ps = "?" }
            let _sn = result.splits.count
            let _in = result.intervalSegments.filter { $0.stepLabel == "운동" }.count
            let _z2: String = {
                let zones = result.hrZones
                guard !zones.isEmpty else { return "" }
                let pct = Int((zones.filter { $0.id <= 2 }.map(\.fraction).reduce(0, +) * 100).rounded())
                return " Zone2 \(pct)%"
            }()
            let _hrTag = _act.flatMap(\.avgHeartRate).map { " 심박\($0)" } ?? ""
            if let old = _oldType, old != result.workoutType {
                print("[유형] 재분류 \(_ds) \(old.koreanLabel) → \(result.workoutType.koreanLabel) (상세데이터 반영) 캐시갱신")
            }
            print("[유형:판정] \(_ds) \(_km)km \(_ps)\(_z2)\(_hrTag) splits=\(_sn) 플랜=\(_in > 0 ? "\(_in)회" : "없음") → \(result.workoutType.koreanLabel)")
            #endif
            persistWorkoutType(result.workoutType, hasSplits: !result.splits.isEmpty, for: activityID)
            persistFormFromDetail(result, for: activityID)
        }
        return result
    }

    private func detailCacheURL(_ id: UUID) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_detail", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // v10: SplitData에 avgVerticalOscillation 추가. 기존 v9 캐시 자동 무효화.
        return dir.appendingPathComponent("v10_\(id.uuidString).json")
    }

    private func loadDetailFromDisk(_ id: UUID) -> ActivityDetail? {
        let url = detailCacheURL(id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ActivityDetail.self, from: data)
    }

    /// 메모리 캐시 → 디스크 캐시 순서로 조회. RaceInsightCard 등 외부에서 splits 로드 시 사용.
    func detailFromCache(_ id: UUID) -> ActivityDetail? {
        if let cached = detailCache[id] { return cached }
        return loadDetailFromDisk(id)
    }

    // MARK: - HR zone time store (존 체류 시간 전용 · 강도 분포 K-1)

    private var hrZoneOnlyCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_hrzones_v2.json")   // v2: Zone4 AT2 분할(splitBPM·upperSeconds) 포함
    }

    private func loadHRZoneOnlyCache() -> [String: [HRZoneData]] {
        if let c = hrZoneOnlyCache { return c }
        let loaded = (try? Data(contentsOf: hrZoneOnlyCacheURL))
            .flatMap { try? JSONDecoder().decode([String: [HRZoneData]].self, from: $0) } ?? [:]
        hrZoneOnlyCache = loaded
        return loaded
    }

    /// 분류·상세 경로에서 HealthKit으로 계산한 존 분포를 보관.
    /// 상세 캐시가 없는 러닝도 강도 분포 합산에 쓰인다. 빈 배열은 저장하지 않음.
    private func persistHRZones(_ zones: [HRZoneData], for id: UUID) {
        // AT2 분할 정보 없는 구버전 존(디스크 상세에서 온 것)은 저장 가치 없음 — 보충 경로가 재조회한다
        guard !zones.isEmpty, MRIntensityTime.hasAT2Split(zones) else { return }
        var dict = loadHRZoneOnlyCache()
        dict[id.uuidString] = zones
        hrZoneOnlyCache = dict
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: hrZoneOnlyCacheURL, options: .atomic)
        }
    }

    /// 강도 분포(존 시간 합산)용 존 조회 — 메모리 상세 → 존 전용 캐시 → 디스크 상세 순. 없으면 nil.
    /// 리듬 카드 도넛과 같은 데이터(queryHRZones 결과)이며 여기서 새로 계산하지 않는다.
    /// AT2 분할 정보(K-4)가 없는 구버전 존은 nil로 취급 — `backfillHRZonesAroundActivity`가 재조회해 채운다.
    func hrZonesFromCache(_ id: UUID) -> [HRZoneData]? {
        func ok(_ z: [HRZoneData]?) -> [HRZoneData]? {
            guard let z, !z.isEmpty, MRIntensityTime.hasAT2Split(z) else { return nil }
            return z
        }
        if let z = ok(detailCache[id]?.hrZones) { return z }
        if let z = ok(loadHRZoneOnlyCache()[id.uuidString]) { return z }
        if let z = ok(loadDetailFromDisk(id)?.hrZones) { return z }
        return nil
    }

    /// 열람 러닝 기준 4주 창에서 존 체류 시간이 어느 캐시에도 없는 러닝을 채운다.
    /// 도넛이 쓰는 queryHRZones를 그대로 호출 — 새 계산이 아니라 캐시 보충.
    /// 심박(avgHeartRate)이 없는 러닝은 건너뜀.
    func backfillHRZonesAroundActivity(_ activity: Activity) async {
        guard activity.type == .running else { return }
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: activity.date) ?? .distantPast
        let windowRuns = activities.filter { $0.type == .running && $0.date >= cutoff && $0.date <= activity.date }
        let missing = windowRuns.filter { $0.avgHeartRate != nil && hrZonesFromCache($0.id) == nil }
        guard !missing.isEmpty else { return }
        var filled = 0
        for act in missing {
            guard !Task.isCancelled else { break }
            if workoutCache[act.id] == nil { await fetchSingleWorkout(id: act.id) }
            guard let wo = workoutCache[act.id] else { continue }
            let zones = await queryHRZones(workout: wo)
            if !zones.isEmpty { persistHRZones(zones, for: act.id); filled += 1 }
            await Task.yield()
        }
        #if DEBUG
        print("[강도분포] 존 캐시 보충 — 창 \(windowRuns.count)건 중 존 없음 \(missing.count)건 → 채움 \(filled)건")
        #endif
    }

    private func saveDetailToDisk(_ detail: ActivityDetail, id: UUID) {
        guard let data = try? JSONEncoder().encode(detail) else { return }
        try? data.write(to: detailCacheURL(id), options: .atomic)
    }

    private func fetchDetailFromHealthKit(for activityID: UUID) async -> ActivityDetail? {
        // workoutCache is populated during fetchActivities; if detail is tapped before
        // background sync finishes (cache-first launch), do a targeted lookup.
        if workoutCache[activityID] == nil { await fetchSingleWorkout(id: activityID) }
        guard let workout = workoutCache[activityID] else { return nil }
        let actType = mapType(workout.workoutActivityType)

        // HR zones run concurrently across all activity types
        async let zonesTask = queryHRZones(workout: workout)

        switch actType {
        case .running:
            async let locTask      = fetchRouteLocations(for: workout)
            async let splitsTask   = querySplits(workout: workout)
            async let powerTask    = queryAvgQuantity(.runningPower, unit: .watt(), workout: workout)
            async let cadTask      = queryCadence(workout: workout)
            async let intervalTask = queryIntervalSegments(workout: workout)
            async let gctTask      = queryAvgQuantity(.runningGroundContactTime,
                                                       unit: .secondUnit(with: .milli), workout: workout)
            async let strTask      = queryAvgQuantity(.runningStrideLength, unit: .meter(), workout: workout)
            async let voTask       = queryAvgQuantity(.runningVerticalOscillation,
                                                       unit: .meterUnit(with: .centi), workout: workout)
            // +24h: Apple Watch가 워크아웃 종료 후 수 분~수십 분 뒤 VO2Max를 계산해 HealthKit에 기록하므로
            // workout.endDate 이후에 생성된 샘플도 포함시켜 가장 최신값을 가져옴
            async let vo2Task      = queryLatestVO2Max(before: workout.endDate.addingTimeInterval(24 * 3600))

            let (locations, splits, zones, powerVal, cadence) =
                await (locTask, splitsTask, zonesTask, powerTask, cadTask)
            let intervals = await intervalTask
            let (gct, strideLen, vertOsc, vo2) = await (gctTask, strTask, voTask, vo2Task)

            let workoutType: WorkoutType = {
                guard let activity = activities.first(where: { $0.id == activityID }) else { return .general }
                let hkCached = (UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey)
                    as? [String: String] ?? [:])[activityID.uuidString].flatMap { parseWorkoutTypeEntry($0) }
                #if DEBUG
                let (wt, trace) = WorkoutTypeClassifier.classifyWithTrace(
                    activity: activity, history: activities,
                    splits: splits, intervalSegments: intervals, hrZones: zones,
                    existingType: hkCached?.type)
                let z2dbg = zones.isEmpty ? "hrZones없음"
                    : "Zone2 \(Int((zones.filter { $0.id <= 2 }.map(\.fraction).reduce(0, +) * 100).rounded()))%"
                let dfdbg = DateFormatter(); dfdbg.dateFormat = "M/d"
                print("[유형:판정:상세] \(dfdbg.string(from: activity.date)) \(z2dbg) splits=\(splits.count) → \(wt.koreanLabel) (\(trace))")
                return wt
                #else
                return WorkoutTypeClassifier.classify(activity: activity, history: activities,
                                                      splits: splits, intervalSegments: intervals,
                                                      hrZones: zones, existingType: hkCached?.type)
                #endif
            }()
            return ActivityDetail(
                routeCoordinates: locations.map(\.coordinate),
                routeTimeOffsets: computeRouteTimeOffsets(from: locations, workoutStart: workout.startDate),
                elevationGain: computeElevationGain(from: locations),
                avgPower: powerVal.map { Int($0.rounded()) },
                avgCadence: cadence,
                splits: splits,
                hrZones: zones,
                intervalSegments: intervals,
                workoutType: workoutType,
                avgGroundContactTime: gct,
                avgStrideLength: strideLen,
                avgVerticalOscillation: vertOsc,
                vo2Max: vo2,
                altitudeProfile: computeAltitudeProfile(from: locations),
                altitudeTimeProfile: computeAltitudeTimeProfile(from: locations, workoutStart: workout.startDate)
            )

        default: // walking, hiking
            let (locations, zones) = await (fetchRouteLocations(for: workout), zonesTask)
            return ActivityDetail(
                routeCoordinates: locations.map(\.coordinate),
                routeTimeOffsets: computeRouteTimeOffsets(from: locations, workoutStart: workout.startDate),
                elevationGain: computeElevationGain(from: locations),
                avgPower: nil,
                avgCadence: nil,
                splits: [],
                hrZones: zones,
                intervalSegments: [],
                workoutType: .general,
                avgGroundContactTime: nil,
                avgStrideLength: nil,
                avgVerticalOscillation: nil,
                vo2Max: nil,
                altitudeProfile: computeAltitudeProfile(from: locations),
                altitudeTimeProfile: computeAltitudeTimeProfile(from: locations, workoutStart: workout.startDate)
            )
        }
    }

    private func fetchSingleWorkout(id: UUID) async {
        let pred = HKQuery.predicateForObject(with: id)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(pred)],
            sortDescriptors: []
        )
        guard let workout = try? await descriptor.result(for: store).first else { return }
        workoutCache[id] = workout
    }

    // MARK: - Workout query — date range, no count limit

    private func queryWorkouts(since: Date? = nil, until: Date? = nil) async throws -> [HKWorkout] {
        let pro = ProManager.shared
        let startCutoff: Date
        let endDate: Date?
        if pro.isTrialExpired {
            startCutoff = Calendar.current.date(byAdding: .month, value: -12, to: pro.firstLaunchDate) ?? .distantPast
            endDate = pro.effectiveCutoffDate
        } else {
            startCutoff = since ?? Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? .distantPast
            endDate = until
        }
        let datePred = HKQuery.predicateForSamples(
            withStart: startCutoff, end: endDate, options: .strictStartDate
        )
        let typePred = NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .walking),
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForWorkouts(with: .hiking),
        ])
        let combined = NSCompoundPredicate(
            andPredicateWithSubpredicates: [datePred, typePred]
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(combined)],
            sortDescriptors: [SortDescriptor(\HKWorkout.startDate, order: .reverse)]
            // No limit — full 12-month history for accurate growth/insight
        )
        return try await descriptor.result(for: store)
    }

    // MARK: - Activity builders

    /// Fast build from the workout's own embedded statistics — zero extra queries.
    private func weatherFrom(_ workout: HKWorkout) -> (tempC: Double?, humidity: Double?) {
        let meta = workout.metadata
        var t: Double? = nil
        var h: Double? = nil
        if let q = meta?[HKMetadataKeyWeatherTemperature] as? HKQuantity,
           q.is(compatibleWith: .degreeCelsius()) {
            let v = q.doubleValue(for: .degreeCelsius())
            if v > -50 && v < 60 { t = v }
        }
        if let q = meta?[HKMetadataKeyWeatherHumidity] as? HKQuantity,
           q.is(compatibleWith: .percent()) {
            let v = q.doubleValue(for: .percent()) * 100
            if v >= 0 && v <= 100 { h = v }
        }
        return (t, h)
    }

    private func buildSummary(from workout: HKWorkout) -> Activity {
        workoutCache[workout.uuid] = workout
        let distID = distanceTypeID(for: workout.workoutActivityType)
        let distance = workout.statistics(for: HKQuantityType(distID))?
            .sumQuantity()?.doubleValue(for: .meter())
            ?? workout.totalDistance?.doubleValue(for: .meter())
            ?? 0
        let hrBpm = workout.statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?.doubleValue(for: Self.bpmUnit)
        let (tempC, humidity) = weatherFrom(workout)
        return Activity(
            id: workout.uuid,
            type: mapType(workout.workoutActivityType),
            date: workout.startDate,
            duration: workout.duration,
            distance: distance,
            calories: nil,
            avgHeartRate: hrBpm.map { Int($0.rounded()) },
            temperatureC: tempC,
            humidityPercent: humidity
        )
    }

    private func distanceTypeID(for type: HKWorkoutActivityType) -> HKQuantityTypeIdentifier {
        return .distanceWalkingRunning
    }

    /// Add calories + heart rate. Runs two stat queries concurrently.
    /// Also retries distance via sample query if embedded stats returned 0.
    private func enrich(_ activity: Activity, workout: HKWorkout) async -> Activity {
        async let calTask = querySum(.activeEnergyBurned, unit: .kilocalorie(), workout: workout)
        async let hrTask  = queryAvgHeartRate(workout: workout)
        let (cal, hr) = await (calTask, hrTask)

        // 시간 범위 폴백 — 워크아웃 링크 실패 시 시간대 기반 재시도
        var finalHR = hr
        if finalHR == nil,
           case .found(let rangeHR) = await queryAvgHeartRateByTimeRange(
               start: workout.startDate, end: workout.endDate) {
            finalHR = rangeHR
        }

        var distance = activity.distance
        if distance == 0 {
            let distID = distanceTypeID(for: workout.workoutActivityType)
            distance = await querySum(distID, unit: .meter(), workout: workout)
        }
        // Third fallback: totalDistance (covers apps like Garmin Connect that write
        // distance to the workout object but don't always link quantity samples)
        if distance == 0, let td = workout.totalDistance {
            distance = td.doubleValue(for: .meter())
        }

        let (tempC, humidity) = weatherFrom(workout)
        return Activity(
            id: activity.id,
            type: activity.type,
            date: activity.date,
            duration: activity.duration,
            distance: distance,
            calories: cal > 0 ? cal : nil,
            avgHeartRate: finalHR ?? activity.avgHeartRate,
            temperatureC: tempC ?? activity.temperatureC,
            humidityPercent: humidity ?? activity.humidityPercent
        )
    }

    // MARK: - Pause Intervals

    private func pausedIntervals(for workout: HKWorkout) -> [DateInterval] {
        if let cached = pausedIntervalsCache[workout.uuid] { return cached }
        guard let events = workout.workoutEvents else {
            pausedIntervalsCache[workout.uuid] = []
            return []
        }
        var intervals: [DateInterval] = []
        var pauseStart: Date? = nil
        let sorted = events.sorted { $0.dateInterval.start < $1.dateInterval.start }
        for event in sorted {
            switch event.type {
            case .pause, .motionPaused:
                if pauseStart == nil { pauseStart = event.dateInterval.start }
            case .resume, .motionResumed:
                if let start = pauseStart {
                    let end = event.dateInterval.start
                    if end > start { intervals.append(DateInterval(start: start, end: end)) }
                    pauseStart = nil
                }
            default: break
            }
        }
        if let start = pauseStart, workout.endDate > start {
            intervals.append(DateInterval(start: start, end: workout.endDate))
        }
        pausedIntervalsCache[workout.uuid] = intervals
        return intervals
    }

    private func isPaused(_ date: Date, in intervals: [DateInterval]) -> Bool {
        guard !intervals.isEmpty else { return false }
        return intervals.contains { $0.start <= date && date < $0.end }
    }

    // MARK: - Route

    private func fetchRouteLocations(for workout: HKWorkout) async -> [CLLocation] {
        let routes = await fetchWorkoutRoutes(for: workout)
        guard let route = routes.first else { return [] }

        return await withCheckedContinuation { continuation in
            let batch = LocationBatch()
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, _ in
                if let locations { batch.locations.append(contentsOf: locations) }
                if done { continuation.resume(returning: batch.locations) }
            }
            self.store.execute(query)
        }
    }

    private func fetchWorkoutRoutes(for workout: HKWorkout) async -> [HKWorkoutRoute] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            self.store.execute(query)
        }
    }

    private func computeElevationGain(from locations: [CLLocation]) -> Double? {
        let valid = locations.filter { $0.verticalAccuracy >= 0 }
        guard valid.count > 1 else { return nil }
        var gain = 0.0
        for i in 1..<valid.count {
            let delta = valid[i].altitude - valid[i - 1].altitude
            if delta > 0 { gain += delta }
        }
        return gain > 1 ? gain : nil
    }

    private func computeRouteTimeOffsets(from locations: [CLLocation], workoutStart: Date) -> [TimeInterval] {
        locations.map { $0.timestamp.timeIntervalSince(workoutStart) }
    }

    private func computeAltitudeTimeProfile(from locations: [CLLocation], workoutStart: Date) -> [(offset: TimeInterval, altitude: Double)] {
        let valid = locations.filter { $0.verticalAccuracy >= 0 }
        guard valid.count > 1 else { return [] }
        let step = max(1, valid.count / 300)
        var result: [(offset: TimeInterval, altitude: Double)] = []
        for i in Swift.stride(from: 0, to: valid.count, by: step) {
            let offset = valid[i].timestamp.timeIntervalSince(workoutStart)
            result.append((offset: offset, altitude: valid[i].altitude))
        }
        return result
    }

    private func computeAltitudeProfile(from locations: [CLLocation]) -> [(distanceKm: Double, altitude: Double)] {
        let valid = locations.filter { $0.verticalAccuracy >= 0 }
        guard valid.count > 1 else { return [] }
        let step = max(1, valid.count / 300)
        var result: [(distanceKm: Double, altitude: Double)] = []
        var cumDist = 0.0
        var prev: CLLocation? = nil
        for i in Swift.stride(from: 0, to: valid.count, by: step) {
            if let p = prev { cumDist += p.distance(from: valid[i]) }
            result.append((distanceKm: cumDist / 1000, altitude: valid[i].altitude))
            prev = valid[i]
        }
        return result
    }

    // MARK: - Heart Rate time series for a single workout

    func fetchHRTimeSeries(for workoutID: UUID) async -> [(offset: TimeInterval, bpm: Int)] {
        // 확정(non-provisional) 인메모리 캐시 → 즉시 반환
        if let cached = hrSeriesCache[workoutID], !hrSeriesProvisionalIDs.contains(workoutID) {
            return cached
        }

        // workout을 먼저 확보 — 디스크 캐시 유효성 검증에 필요
        if workoutCache[workoutID] == nil { await fetchSingleWorkout(id: workoutID) }
        let cachedWorkout = workoutCache[workoutID]
        let durationMin = cachedWorkout.map { max(Int($0.duration / 60), 1) } ?? 1

        // 디스크 캐시 로드
        if let (disk, diskProvisional) = loadHRSeriesFromDisk(workoutID) {
            let isComplete = disk.count >= durationMin * 2
            if !diskProvisional && isComplete {
                // 확정 캐시 — 재조회 없이 사용
                hrSeriesCache[workoutID] = disk
                hrSeriesProvisionalIDs.remove(workoutID)
                return disk
            }
            // Provisional 또는 완전성 미달 → HealthKit 재조회 후 비교
            guard let workout = cachedWorkout else {
                hrSeriesCache[workoutID] = disk
                if !isComplete { hrSeriesProvisionalIDs.insert(workoutID) }
                return disk
            }
            let fresh = await queryHRSamples(for: workout)
            let best = fresh.count > disk.count ? fresh : disk
            hrSeriesCache[workoutID] = best
            let nowProvisional = best.count < durationMin * 2
            if nowProvisional { hrSeriesProvisionalIDs.insert(workoutID) } else { hrSeriesProvisionalIDs.remove(workoutID) }
            saveHRSeriesToDisk(best, id: workoutID, durationMin: durationMin)
            return best
        }

        // 디스크 캐시 없음 → 신규 조회
        guard let workout = cachedWorkout else { return [] }
        let bestResult = await queryHRSamples(for: workout)

        hrSeriesCache[workoutID] = bestResult
        let nowProvisional = bestResult.count < durationMin * 2
        if nowProvisional { hrSeriesProvisionalIDs.insert(workoutID) } else { hrSeriesProvisionalIDs.remove(workoutID) }
        saveHRSeriesToDisk(bestResult, id: workoutID, durationMin: durationMin)
        return bestResult
    }

    /// 워크아웃에서 HR 샘플을 HealthKit에서 직접 조회 (linked 1차 + 시리즈 2차).
    private func queryHRSamples(for workout: HKWorkout) async -> [(offset: TimeInterval, bpm: Int)] {
        let unit = Self.bpmUnit
        let minExpected = max(Int(workout.duration / 60), 1)
        let paused = pausedIntervals(for: workout)

        // 1차: 워크아웃 연결 샘플
        let linkedPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let linkedDesc = HKSampleQueryDescriptor(
            predicates: [linkedPred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        var bestResult: [(offset: TimeInterval, bpm: Int)] =
            ((try? await linkedDesc.result(for: store)) ?? [])
            .filter { !isPaused($0.startDate, in: paused) }
            .map { s in
                (offset: s.startDate.timeIntervalSince(workout.startDate),
                 bpm: Int(s.quantity.doubleValue(for: unit).rounded()))
            }

        // 2차: 시간 범위 시리즈 쿼리 (워치 HK 시리즈 컨테이너 대응)
        // 중복 컨테이너 경계 타임스탬프 → Set<Date>로 완전 일치 중복 제거.
        if bestResult.count < minExpected {
            let seriesPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
                type: HKQuantityType(.heartRate),
                predicate: HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])
            )
            let seriesDesc = HKQuantitySeriesSampleQueryDescriptor(predicate: seriesPred, options: [])
            var seen = Set<Date>()
            var seriesResult: [(offset: TimeInterval, bpm: Int)] = []
            do {
                for try await entry in seriesDesc.results(for: store) {
                    let start = entry.dateInterval.start
                    guard seen.insert(start).inserted else { continue }
                    guard !isPaused(start, in: paused) else { continue }
                    let offset = start.timeIntervalSince(workout.startDate)
                    guard offset >= 0 else { continue }
                    seriesResult.append((offset: offset, bpm: Int(entry.quantity.doubleValue(for: unit).rounded())))
                }
            } catch {}
            if seriesResult.count > bestResult.count {
                bestResult = seriesResult.sorted { $0.offset < $1.offset }
            }
        }
        return bestResult
    }

    private func hrSeriesCacheURL(_ id: UUID) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_hr_\(id.uuidString).json")
    }

    private func hrSeriesMetaURL(_ id: UUID) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_hr_\(id.uuidString)_meta.json")
    }

    /// 디스크 캐시 로드. 메타 파일 없거나 provisional=true이면 (series, true) 반환.
    private func loadHRSeriesFromDisk(_ id: UUID) -> (series: [(offset: TimeInterval, bpm: Int)], provisional: Bool)? {
        guard let data = try? Data(contentsOf: hrSeriesCacheURL(id)),
              let pts = try? JSONDecoder().decode([HRPoint].self, from: data) else { return nil }
        let series = pts.map { (offset: $0.offset, bpm: $0.bpm) }
        guard let metaData = try? Data(contentsOf: hrSeriesMetaURL(id)),
              let meta = try? JSONDecoder().decode(HRSeriesMeta.self, from: metaData) else {
            return (series, true)  // 메타 없음 = 이전 포맷 캐시 → provisional 처리
        }
        return (series, meta.provisional)
    }

    private func saveHRSeriesToDisk(_ series: [(offset: TimeInterval, bpm: Int)], id: UUID, durationMin: Int) {
        guard let data = try? JSONEncoder().encode(series.map { HRPoint(offset: $0.offset, bpm: $0.bpm) }) else { return }
        try? data.write(to: hrSeriesCacheURL(id), options: .atomic)
        let provisional = series.count < durationMin * 2
        let meta = HRSeriesMeta(count: series.count, durationMin: durationMin, provisional: provisional)
        if let metaData = try? JSONEncoder().encode(meta) {
            try? metaData.write(to: hrSeriesMetaURL(id), options: .atomic)
        }
    }

    // MARK: - 운동 후 심박 (회복)

    private func hrRecoveryCacheURL(_ id: UUID) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_hrr_\(id.uuidString).json")
    }

    /// 종료 후 180초 심박 샘플 (offset = 종료 기준 초). 디스크 캐시 → HealthKit.
    /// ⚠ 종료 1시간 이내 워크아웃은 워치 동기화가 안 끝났을 수 있어 캐시하지 않는다.
    func fetchPostWorkoutHR(for workoutID: UUID) async -> [MRRecoveryPoint] {
        let url = hrRecoveryCacheURL(workoutID)
        if let data = try? Data(contentsOf: url),
           let pts = try? JSONDecoder().decode([MRRecoveryPoint].self, from: data) {
            return pts
        }
        if workoutCache[workoutID] == nil { await fetchSingleWorkout(id: workoutID) }
        guard let w = workoutCache[workoutID] else { return [] }
        let pts = await queryPostWorkoutHR(workout: w)
        if Date().timeIntervalSince(w.endDate) > 3600, let data = try? JSONEncoder().encode(pts) {
            try? data.write(to: url, options: .atomic)
        }
        return pts
    }

    /// [종료, 종료+180초] 심박 — 개별 샘플과 시리즈 컨테이너 둘 다 읽고 시각으로 중복 제거 (queryHRSamples와 같은 이유).
    private func queryPostWorkoutHR(workout w: HKWorkout) async -> [MRRecoveryPoint] {
        let unit = Self.bpmUnit
        let end = w.endDate
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForSamples(withStart: end, end: end.addingTimeInterval(MRRecovery.postWindowSec), options: [])
        )
        var seen = Set<Date>()
        var out: [MRRecoveryPoint] = []
        let sampleDesc = HKSampleQueryDescriptor(predicates: [pred],
                                                 sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)])
        for s in (try? await sampleDesc.result(for: store)) ?? [] where seen.insert(s.startDate).inserted {
            out.append(MRRecoveryPoint(offset: s.startDate.timeIntervalSince(end),
                                       bpm: Int(s.quantity.doubleValue(for: unit).rounded())))
        }
        let seriesDesc = HKQuantitySeriesSampleQueryDescriptor(predicate: pred, options: [])
        do {
            for try await e in seriesDesc.results(for: store) {
                let st = e.dateInterval.start
                guard seen.insert(st).inserted else { continue }
                out.append(MRRecoveryPoint(offset: st.timeIntervalSince(end),
                                           bpm: Int(e.quantity.doubleValue(for: unit).rounded())))
            }
        } catch {}
        return out.filter { $0.offset >= 0 }.sorted { $0.offset < $1.offset }
    }

    /// 워크아웃 마지막 30초 평균 심박 — 히스토리 빌드용 소형 쿼리 (전체 시계열을 읽지 않는다).
    private func queryEndHR(workout w: HKWorkout) async -> Double? {
        let unit = Self.bpmUnit
        let end = w.endDate
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForSamples(withStart: end.addingTimeInterval(-MRRecovery.endWindowSec), end: end, options: [])
        )
        var seen = Set<Date>()
        var vals: [Double] = []
        let seriesDesc = HKQuantitySeriesSampleQueryDescriptor(predicate: pred, options: [])
        do {
            for try await e in seriesDesc.results(for: store) where seen.insert(e.dateInterval.start).inserted {
                vals.append(e.quantity.doubleValue(for: unit))
            }
        } catch {}
        if vals.isEmpty {
            let sampleDesc = HKSampleQueryDescriptor(predicates: [pred], sortDescriptors: [])
            vals = ((try? await sampleDesc.result(for: store)) ?? []).map { $0.quantity.doubleValue(for: unit) }
        }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    struct RecoveryHistoryPoint: Codable {
        let date: Date
        let endHR: Double
        let hrr1: Double
        var tempC: Double? = nil   // HKMetadataKeyWeatherTemperature — 회귀의 기온 항
    }
    private struct RecoveryHistoryFile: Codable {
        var points: [RecoveryHistoryPoint]
        var cachedAt: Date
        var coveredFrom: Date
    }
    private var recoveryHistoryURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_hrr_history_v2.json")   // v2: 자격 80% · 기온 필드
    }

    /// 최근 12개월 러닝의 (날짜, 종료심박, HRR1). 자격(종료심박 ≥ 최대심박 70%) 통과분만.
    /// 캐시는 새 러닝(종료 1시간 경과)이 캐시 시각 이후에 있으면 다시 만든다.
    func fetchRecoveryHistory(from start: Date) async -> [RecoveryHistoryPoint] {
        let fullStart = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        if let data = try? Data(contentsOf: recoveryHistoryURL),
           let file = try? JSONDecoder().decode(RecoveryHistoryFile.self, from: data),
           file.coveredFrom <= fullStart.addingTimeInterval(86_400 * 7) {
            let newerRun = activities.contains {
                $0.type == .running && $0.date > file.cachedAt && Date().timeIntervalSince($0.date) > 3600 + $0.duration
            }
            if !newerRun { return file.points.filter { $0.date >= start } }
        }

        let fetched = (try? await queryWorkouts(since: fullStart)) ?? []
        let runs = fetched.filter { $0.workoutActivityType == .running && Date().timeIntervalSince($0.endDate) > 3600 }
                          .sorted { $0.startDate < $1.startDate }
        for w in runs { workoutCache[w.uuid] = w }
        let maxHR = cachedMHR.map(Double.init)

        var points: [RecoveryHistoryPoint] = []
        await withTaskGroup(of: RecoveryHistoryPoint?.self) { group in
            for w in runs {
                group.addTask { [self] in
                    guard let endHR = await self.queryEndHR(workout: w),
                          MRRecovery.isEligible(endHR: endHR, maxHR: maxHR) else { return nil }
                    let post = await self.fetchPostWorkoutHR(for: w.uuid)
                    guard let r = MRRecovery.compute(endHR: endHR, post: post) else { return nil }
                    let temp = (w.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity)?.doubleValue(for: .degreeCelsius())
                    return RecoveryHistoryPoint(date: w.startDate, endHR: endHR, hrr1: r.hrr1, tempC: temp)
                }
            }
            for await p in group { if let p { points.append(p) } }
        }
        points.sort { $0.date < $1.date }
        #if DEBUG
        print("[회복] 12개월 러닝 \(runs.count)건 → 자격·샘플 통과 \(points.count)건 (최대심박 \(cachedMHR.map(String.init) ?? "미상"))")
        #endif
        let file = RecoveryHistoryFile(points: points, cachedAt: Date(), coveredFrom: fullStart)
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: recoveryHistoryURL, options: .atomic) }
        return points.filter { $0.date >= start }
    }

    // 워크아웃 연결 시리즈 쿼리 추가 이전에 저장된 잘못된 HR 캐시(휴식 구간 HR만 포함) 삭제
    private func migrateHRSeriesCacheIfNeeded() {
        let key = "mimo.hrSeriesCacheVersion"
        guard UserDefaults.standard.integer(forKey: key) < 6 else { return }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        if let files = try? FileManager.default.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("mimo_hr_") {
                try? FileManager.default.removeItem(at: file)
            }
        }
        hrSeriesCache.removeAll()
        UserDefaults.standard.set(6, forKey: key)
    }

    // 러닝 폼 지표 쿼리를 predicateForObjects → predicateForSamples(timeRange) 로 변경 후
    // 기존 캐시(workout-linked 기준)를 1회 삭제해 새 방식으로 재빌드
    private func migrateRunningMetricCacheIfNeeded() {
        let key = "mimo.runningMetricQueryVersion"
        guard UserDefaults.standard.integer(forKey: key) < 1 else { return }
        invalidateRunningMetricHistoryCache()
        UserDefaults.standard.set(1, forKey: key)
    }

    private func migrateWeatherBackfillIfNeeded() {
        let key = "mimo.weatherBackfill.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        Task {
            let candidates = activities.filter { $0.temperatureC == nil && $0.humidityPercent == nil }
            for activity in candidates.prefix(50) {
                if workoutCache[activity.id] == nil { await fetchSingleWorkout(id: activity.id) }
                guard let workout = workoutCache[activity.id] else { continue }
                let (tempC, humidity) = weatherFrom(workout)
                guard tempC != nil || humidity != nil else { continue }
                guard let idx = activities.firstIndex(where: { $0.id == activity.id }) else { continue }
                let a = activities[idx]
                let updated = Activity(id: a.id, type: a.type, date: a.date,
                                       duration: a.duration, distance: a.distance,
                                       calories: a.calories, avgHeartRate: a.avgHeartRate,
                                       temperatureC: tempC, humidityPercent: humidity)
                activities[idx] = updated
                saveToCache([CachedActivity(from: updated)])
            }
        }
    }

    // MARK: - Workout time-series (for share card panels)

    func fetchWorkoutTimeSeries(for workoutID: UUID, identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> [(offset: TimeInterval, value: Double)] {
        let key = "\(workoutID)_\(identifier.rawValue)"
        if let cached = panelSeriesCache[key] { return cached }

        // workout 먼저 확보 — 디스크 캐시 유효성 검증에 필요
        if workoutCache[workoutID] == nil { await fetchSingleWorkout(id: workoutID) }
        let cachedWorkout = workoutCache[workoutID]

        if let disk = loadPanelSeriesFromDisk(key: key) {
            if let wk = cachedWorkout {
                let minExpected = max(Int(wk.duration / 60), 1)
                if disk.count >= minExpected {
                    panelSeriesCache[key] = disk
                    return disk
                }
                // 부족하면 시리즈 재조회로 이어짐
            } else {
                panelSeriesCache[key] = disk
                return disk
            }
        }

        guard let workout = cachedWorkout else { return [] }
        let paused = pausedIntervals(for: workout)
        let minExpected = max(Int(workout.duration / 60), 1)

        // 1차: 워크아웃 연결 샘플
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(identifier),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        var result = ((try? await descriptor.result(for: store)) ?? [])
            .filter { !isPaused($0.startDate, in: paused) }
            .map { s in
                (offset: s.startDate.timeIntervalSince(workout.startDate),
                 value: s.quantity.doubleValue(for: unit))
            }

        // 2차 시리즈 폴백: Apple Watch 워크아웃 지표가 시리즈로 저장된 경우
        if result.count < minExpected {
            let seriesPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
                type: HKQuantityType(identifier),
                predicate: HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
            )
            let seriesDesc = HKQuantitySeriesSampleQueryDescriptor(predicate: seriesPred, options: [])
            var seriesResult: [(offset: TimeInterval, value: Double)] = []
            do {
                for try await entry in seriesDesc.results(for: store) {
                    guard !isPaused(entry.dateInterval.start, in: paused) else { continue }
                    let offset = entry.dateInterval.start.timeIntervalSince(workout.startDate)
                    guard offset >= 0 else { continue }
                    seriesResult.append((offset: offset, value: entry.quantity.doubleValue(for: unit)))
                }
            } catch {}
            if seriesResult.count > result.count {
                result = seriesResult.sorted { $0.offset < $1.offset }
            }
        }

        panelSeriesCache[key] = result
        savePanelSeriesToDisk(result, key: key)
        return result
    }

    func fetchCadenceTimeSeries(for workoutID: UUID) async -> [(offset: TimeInterval, value: Double)] {
        let key = "\(workoutID)_cadence_v4"
        if let cached = panelSeriesCache[key] { return cached }

        if workoutCache[workoutID] == nil { await fetchSingleWorkout(id: workoutID) }
        let cachedWorkout = workoutCache[workoutID]

        if let disk = loadPanelSeriesFromDisk(key: key) {
            if let wk = cachedWorkout {
                let minExpected = max(Int(wk.duration / 60), 1)
                if disk.count >= minExpected {
                    panelSeriesCache[key] = disk
                    return disk
                }
            } else {
                panelSeriesCache[key] = disk
                return disk
            }
        }

        guard let workout = cachedWorkout else { return [] }
        let paused = pausedIntervals(for: workout)
        let workoutDuration = workout.duration
        let minExpected = max(Int(workoutDuration / 60), 1)

        // 1차: runningSpeed / runningStrideLength — Apple Watch 직접 측정, 분당 샘플 수십 개
        let speedSamples  = await fetchWorkoutTimeSeries(for: workoutID, identifier: .runningSpeed,
                                                         unit: .meter().unitDivided(by: .second()))
        let strideSamples = await fetchWorkoutTimeSeries(for: workoutID, identifier: .runningStrideLength,
                                                         unit: .meter())

        var result: [(offset: TimeInterval, value: Double)] = []

        if !speedSamples.isEmpty && !strideSamples.isEmpty {
            let sortedSpeed  = speedSamples.sorted  { $0.offset < $1.offset }
            let sortedStride = strideSamples.sorted { $0.offset < $1.offset }

            if sortedSpeed.count == sortedStride.count {
                for (sp, st) in zip(sortedSpeed, sortedStride) {
                    guard !isPaused(workout.startDate.addingTimeInterval(sp.offset), in: paused), st.value > 0 else { continue }
                    let spm = sp.value / st.value * 60
                    if spm >= 100 && spm <= 250 { result.append((offset: sp.offset, value: spm)) }
                }
            } else {
                for sp in sortedSpeed {
                    guard !isPaused(workout.startDate.addingTimeInterval(sp.offset), in: paused) else { continue }
                    var lo = 0, hi = sortedStride.count - 1
                    while lo < hi {
                        let mid = (lo + hi) / 2
                        if sortedStride[mid].offset < sp.offset { lo = mid + 1 } else { hi = mid }
                    }
                    var best = sortedStride[lo]
                    if lo > 0 && abs(sortedStride[lo - 1].offset - sp.offset) < abs(best.offset - sp.offset) {
                        best = sortedStride[lo - 1]
                    }
                    guard abs(best.offset - sp.offset) < 5, best.value > 0 else { continue }
                    let spm = sp.value / best.value * 60
                    if spm >= 100 && spm <= 250 { result.append((offset: sp.offset, value: spm)) }
                }
            }
        }

        // 2차: stepCount 폴백 (runningSpeed/StrideLength 없는 구형 기기)
        if result.count < minExpected {
            let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
                type: HKQuantityType(.stepCount),
                predicate: HKQuery.predicateForObjects(from: workout)
            )
            let descriptor = HKSampleQueryDescriptor(
                predicates: [pred],
                sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
            )
            var stepResult: [(offset: TimeInterval, value: Double)] = []
            if let samples = try? await descriptor.result(for: store) {
                for s in samples {
                    guard !isPaused(s.startDate, in: paused) else { continue }
                    let dur = s.endDate.timeIntervalSince(s.startDate)
                    guard dur > 0 else { continue }
                    let steps = s.quantity.doubleValue(for: .count())
                    let spm = (steps / dur) * 60
                    let startOffset = s.startDate.timeIntervalSince(workout.startDate)
                    if dur >= workoutDuration * 0.25 {
                        let endOffset = min(startOffset + dur, workoutDuration)
                        let n = max(2, min(40, Int(dur / 20)))
                        for j in 0..<n {
                            let t = startOffset + (endOffset - startOffset) * (Double(j) + 0.5) / Double(n)
                            stepResult.append((offset: t, value: spm))
                        }
                    } else {
                        stepResult.append((offset: startOffset + dur / 2, value: spm))
                    }
                }
                stepResult = stepResult.filter { $0.offset >= 0 }
            }
            if stepResult.count > result.count { result = stepResult }
        }

        panelSeriesCache[key] = result
        savePanelSeriesToDisk(result, key: key)
        return result
    }

    private func panelSeriesCacheURL(key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_panel_\(safe).json")
    }

    private func loadPanelSeriesFromDisk(key: String) -> [(offset: TimeInterval, value: Double)]? {
        guard let data = try? Data(contentsOf: panelSeriesCacheURL(key: key)),
              let pts = try? JSONDecoder().decode([SeriesPoint].self, from: data) else { return nil }
        return pts.map { (offset: $0.offset, value: $0.value) }
    }

    private func savePanelSeriesToDisk(_ series: [(offset: TimeInterval, value: Double)], key: String) {
        guard let data = try? JSONEncoder().encode(series.map { SeriesPoint(offset: $0.offset, value: $0.value) }) else { return }
        try? data.write(to: panelSeriesCacheURL(key: key), options: .atomic)
    }

    // MARK: - Stats queries

    private func querySum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        workout: HKWorkout
    ) async -> Double {
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(identifier),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let descriptor = HKStatisticsQueryDescriptor(predicate: pred, options: .cumulativeSum)
        guard let stats = try? await descriptor.result(for: store) else { return 0 }
        return stats.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    private func queryAvgQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        workout: HKWorkout
    ) async -> Double? {
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(identifier),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let descriptor = HKStatisticsQueryDescriptor(predicate: pred, options: .discreteAverage)
        guard let stats = try? await descriptor.result(for: store),
              let avg = stats.averageQuantity() else { return nil }
        return avg.doubleValue(for: unit)
    }

    // workout-linked 쿼리 대신 시간 범위로 조회 — Garmin 등 서드파티 standalone 샘플 포함
    private func querySumInRange(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async -> Double {
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(identifier),
            predicate: HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        )
        let descriptor = HKStatisticsQueryDescriptor(predicate: pred, options: .cumulativeSum)
        guard let stats = try? await descriptor.result(for: store) else { return 0 }
        return stats.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    private func queryAvgQuantityInRange(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async -> Double? {
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(identifier),
            predicate: HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        )
        let descriptor = HKStatisticsQueryDescriptor(predicate: pred, options: .discreteAverage)
        guard let stats = try? await descriptor.result(for: store),
              let avg = stats.averageQuantity() else { return nil }
        return avg.doubleValue(for: unit)
    }

    private func queryAvgHeartRate(workout: HKWorkout) async -> Int? {
        let paused = pausedIntervals(for: workout)
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        guard let all = try? await descriptor.result(for: store), !all.isEmpty else { return nil }
        let unit = Self.bpmUnit
        let active = all.filter { !isPaused($0.startDate, in: paused) }
        guard !active.isEmpty else { return nil }
        let sum = active.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
        return Int((sum / Double(active.count)).rounded())
    }

    private func queryCadence(workout: HKWorkout) async -> Int? {
        let steps = await querySum(.stepCount, unit: .count(), workout: workout)
        guard steps > 0, workout.duration > 60 else { return nil }
        return Int((steps / (workout.duration / 60)).rounded())
    }

    // MARK: - Splits

    private func querySplits(workout: HKWorkout) async -> [SplitData] {
        let distPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.distanceWalkingRunning),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let distDesc = HKSampleQueryDescriptor(
            predicates: [distPred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        guard let distSamples = try? await distDesc.result(for: store),
              !distSamples.isEmpty else { return [] }

        // HR: 1차 연결 샘플, 부족하면 2차 시리즈 쿼리 — fetchHRTimeSeries와 동일 로직.
        // predicateForObjects만 쓰면 Watch HR 시리즈 컨테이너(1개)만 반환 → 구간별 매칭 불가.
        let hrDateSamples: [(startDate: Date, bpm: Int)] = await {
            let unit = Self.bpmUnit
            let linkedPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
                type: HKQuantityType(.heartRate),
                predicate: HKQuery.predicateForObjects(from: workout)
            )
            let linkedDesc = HKSampleQueryDescriptor(
                predicates: [linkedPred],
                sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
            )
            let linked = (try? await linkedDesc.result(for: store)) ?? []
            let linkedMapped = linked.map { (startDate: $0.startDate, bpm: Int($0.quantity.doubleValue(for: unit).rounded())) }
            let minExpected = max(Int(workout.duration / 60), 1)
            if linkedMapped.count >= minExpected { return linkedMapped }
            // 2차: 시리즈 쿼리 — Watch의 HKQuantitySeriesSampleBuilder 포인트 추출
            let seriesPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
                type: HKQuantityType(.heartRate),
                predicate: HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])
            )
            let seriesDesc = HKQuantitySeriesSampleQueryDescriptor(predicate: seriesPred, options: [])
            var series: [(startDate: Date, bpm: Int)] = []
            var seenDates = Set<Date>()
            do {
                for try await entry in seriesDesc.results(for: store) {
                    let start = entry.dateInterval.start
                    guard seenDates.insert(start).inserted else { continue }
                    series.append((startDate: start, bpm: Int(entry.quantity.doubleValue(for: unit).rounded())))
                }
            } catch {}
            return series.count > linkedMapped.count ? series.sorted { $0.startDate < $1.startDate } : linkedMapped
        }()

        let powerPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.runningPower),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let powerDesc = HKSampleQueryDescriptor(
            predicates: [powerPred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        let cadPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.stepCount),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let cadDesc = HKSampleQueryDescriptor(
            predicates: [cadPred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        let gctPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.runningGroundContactTime),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let gctDesc = HKSampleQueryDescriptor(
            predicates: [gctPred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        let stridePred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.runningStrideLength),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let strideDesc = HKSampleQueryDescriptor(
            predicates: [stridePred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        let voPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.runningVerticalOscillation),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let voDesc = HKSampleQueryDescriptor(
            predicates: [voPred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        async let powerFetch  = powerDesc.result(for: store)
        async let cadFetch    = cadDesc.result(for: store)
        async let gctFetch    = gctDesc.result(for: store)
        async let strideFetch = strideDesc.result(for: store)
        async let voFetch     = voDesc.result(for: store)
        let powerSamples  = (try? await powerFetch)  ?? []
        let cadSamples    = (try? await cadFetch)    ?? []
        let gctSamples    = (try? await gctFetch)    ?? []
        let strideSamples = (try? await strideFetch) ?? []
        let voSamples     = (try? await voFetch)     ?? []
        let paused = pausedIntervals(for: workout)

        // Build cumulative distance timeline: (date, cumulative meters)
        var timeline: [(date: Date, cum: Double)] = [(distSamples[0].startDate, 0.0)]
        var cum = 0.0
        for s in distSamples {
            cum += s.quantity.doubleValue(for: .meter())
            timeline.append((s.endDate, cum))
        }
        guard cum >= 1000 else { return [] }

        // Find km crossing times via linear interpolation
        var crossings: [(km: Int, date: Date)] = []
        for km in 1... {
            let target = Double(km) * 1000
            guard target <= cum else { break }
            guard let idx = timeline.firstIndex(where: { $0.cum >= target }), idx > 0 else { continue }
            let a = timeline[idx - 1], b = timeline[idx]
            let frac = b.cum > a.cum ? (target - a.cum) / (b.cum - a.cum) : 0
            let date = a.date.addingTimeInterval(b.date.timeIntervalSince(a.date) * frac)
            crossings.append((km, date))
        }

        // Build SplitData from crossings
        var result: [SplitData] = []
        guard let firstPoint = timeline.first else { return [] }
        var prevDate = firstPoint.date
        for crossing in crossings {
            let dur = crossing.date.timeIntervalSince(prevDate)
            guard dur > 1 else { prevDate = crossing.date; continue }
            let activeDur = activeDuration(from: prevDate, to: crossing.date, paused: paused)
            let hr = splitAvgHRFromDates(from: prevDate, to: crossing.date, samples: hrDateSamples, paused: paused)
            result.append(SplitData(
                id: crossing.km, distanceM: 1000, duration: activeDur,
                avgHeartRate: hr,
                avgCadence: splitAvgCadence(from: prevDate, to: crossing.date, samples: cadSamples, paused: paused),
                avgPower: splitAvgPower(from: prevDate, to: crossing.date, samples: powerSamples, paused: paused),
                avgGroundContactTime: splitAvgGCT(from: prevDate, to: crossing.date, samples: gctSamples, paused: paused),
                avgStrideLength: splitAvgStrideLength(from: prevDate, to: crossing.date, samples: strideSamples, paused: paused),
                avgVerticalOscillation: splitAvgVO(from: prevDate, to: crossing.date, samples: voSamples, paused: paused)
            ))
            prevDate = crossing.date
        }
        // Last partial split (≥ 100 m)
        let lastKm = crossings.last?.km ?? 0
        let remaining = cum - Double(lastKm) * 1000
        if remaining >= 100, let lastDate = timeline.last?.date {
            let dur = lastDate.timeIntervalSince(prevDate)
            if dur > 1 {
                let activeDur = activeDuration(from: prevDate, to: lastDate, paused: paused)
                let hr = splitAvgHRFromDates(from: prevDate, to: lastDate, samples: hrDateSamples, paused: paused)
                result.append(SplitData(
                    id: lastKm + 1, distanceM: remaining, duration: activeDur,
                    avgHeartRate: hr,
                    avgCadence: splitAvgCadence(from: prevDate, to: lastDate, samples: cadSamples, paused: paused),
                    avgPower: splitAvgPower(from: prevDate, to: lastDate, samples: powerSamples, paused: paused),
                    avgGroundContactTime: splitAvgGCT(from: prevDate, to: lastDate, samples: gctSamples, paused: paused),
                    avgStrideLength: splitAvgStrideLength(from: prevDate, to: lastDate, samples: strideSamples, paused: paused),
                    avgVerticalOscillation: splitAvgVO(from: prevDate, to: lastDate, samples: voSamples, paused: paused)
                ))
            }
        }
        return result
    }

    private func activeDuration(from start: Date, to end: Date, paused: [DateInterval]) -> TimeInterval {
        let wall = end.timeIntervalSince(start)
        let pausedSec = paused.reduce(0.0) { total, iv in
            let s = max(iv.start, start); let e = min(iv.end, end)
            return e > s ? total + e.timeIntervalSince(s) : total
        }
        return max(wall - pausedSec, 1)
    }

    private func splitAvgHRFromDates(from start: Date, to end: Date, samples: [(startDate: Date, bpm: Int)], paused: [DateInterval] = []) -> Int? {
        let relevant = samples.filter { $0.startDate >= start && $0.startDate < end && !isPaused($0.startDate, in: paused) }
        guard !relevant.isEmpty else { return nil }
        let sum = relevant.reduce(0) { $0 + $1.bpm }
        return Int((Double(sum) / Double(relevant.count)).rounded())
    }

    private func splitAvgPower(from start: Date, to end: Date, samples: [HKQuantitySample], paused: [DateInterval] = []) -> Int? {
        let relevant = samples.filter { $0.startDate >= start && $0.startDate < end && !isPaused($0.startDate, in: paused) }
        guard !relevant.isEmpty else { return nil }
        let sum = relevant.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .watt()) }
        return Int((sum / Double(relevant.count)).rounded())
    }

    private func splitAvgCadence(from start: Date, to end: Date, samples: [HKQuantitySample], paused: [DateInterval] = []) -> Int? {
        let relevant = samples.filter { $0.startDate >= start && $0.startDate < end && !isPaused($0.startDate, in: paused) }
        guard !relevant.isEmpty else { return nil }
        let totalSteps  = relevant.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .count()) }
        let totalDurSec = relevant.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        guard totalDurSec > 0 else { return nil }
        let spm = (totalSteps / totalDurSec) * 60
        let corrected = spm > 200 ? spm / 2 : spm
        return corrected > 60 ? Int(corrected.rounded()) : nil
    }

    private func splitAvgGCT(from start: Date, to end: Date, samples: [HKQuantitySample], paused: [DateInterval] = []) -> Double? {
        let relevant = samples.filter { $0.startDate >= start && $0.startDate < end && !isPaused($0.startDate, in: paused) }
        guard !relevant.isEmpty else { return nil }
        let unit = HKUnit.secondUnit(with: .milli)
        let sum = relevant.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
        return sum / Double(relevant.count)
    }

    private func splitAvgStrideLength(from start: Date, to end: Date, samples: [HKQuantitySample], paused: [DateInterval] = []) -> Double? {
        let relevant = samples.filter { $0.startDate >= start && $0.startDate < end && !isPaused($0.startDate, in: paused) }
        guard !relevant.isEmpty else { return nil }
        let sum = relevant.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .meter()) }
        return sum / Double(relevant.count)
    }

    private func splitAvgVO(from start: Date, to end: Date, samples: [HKQuantitySample], paused: [DateInterval] = []) -> Double? {
        let relevant = samples.filter { $0.startDate >= start && $0.startDate < end && !isPaused($0.startDate, in: paused) }
        guard !relevant.isEmpty else { return nil }
        let unit = HKUnit.meterUnit(with: .centi)
        let sum = relevant.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
        return sum / Double(relevant.count)
    }

    // MARK: - VO2max (most recent estimate at/before a given date)

    private func queryLatestVO2Max(before date: Date) async -> Double? {
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.vo2Max),
            predicate: HKQuery.predicateForSamples(withStart: nil, end: date, options: [])
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        // mL/(kg·min) — compose unit to avoid locale-sensitive string parsing
        let unit = Self.vo2MaxUnit
        return sample.quantity.doubleValue(for: unit)
    }

    // MARK: - HR Zone Parameters (Karvonen / HRR)

    /// Fetches fresh RHR from HealthKit and computes MHR every time — no cache.
    func refreshHRZoneParameters() async {
        // Discard any legacy UserDefaults cache
        UserDefaults.standard.removeObject(forKey: "hrZone_rhr")
        UserDefaults.standard.removeObject(forKey: "hrZone_mhr")
        UserDefaults.standard.removeObject(forKey: "hrZone_fetchDate")

        // Tanaka: MHR = 208 − 0.7 × age
        guard let dob = userDateOfBirth, let year = dob.year, year > 1900 else {
            restingHeartRate = nil; cachedMHR = nil; return
        }
        let age = Calendar.current.component(.year, from: Date()) - year
        let mhr = max(150, Int((208.0 - 0.7 * Double(age)).rounded()))

        guard let rhr = await queryLatestRestingHR() else {
            restingHeartRate = nil; cachedMHR = nil; return
        }
        restingHeartRate = rhr
        cachedMHR        = mhr
    }

    /// Fetches resting HR samples anchored to a specific date (직전 30일 → 전체 기간 폴백).
    /// `anchor`: 검색 종료 기준. 기본값 Date()는 전역 파라미터 갱신용; 러닝별 존 계산은 workout.startDate를 전달.
    private func queryLatestRestingHR(before anchor: Date = Date()) async -> Int? {
        let unit = Self.bpmUnit

        func fetchSamples(start: Date?, end: Date) async -> [Int] {
            let predicate = HKQuery.predicateForSamples(
                withStart: start, end: end, options: start == nil ? [] : .strictStartDate
            )
            let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
                type: HKQuantityType(.restingHeartRate), predicate: predicate
            )
            let desc = HKSampleQueryDescriptor(
                predicates: [pred],
                sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .reverse)]
            )
            guard let samples = try? await desc.result(for: store) else { return [] }
            return samples.map { Int($0.quantity.doubleValue(for: unit).rounded()) }
        }

        func median(_ values: [Int]) -> Int {
            let s = values.sorted()
            let n = s.count
            return n % 2 == 0 ? (s[n/2 - 1] + s[n/2]) / 2 : s[n/2]
        }

        // 1차: anchor 직전 30일
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: anchor)
        let recent30 = await fetchSamples(start: thirtyDaysAgo, end: anchor)
        if recent30.count >= 10 {
            let med = max(40, median(recent30))
            print("[존] RHR 중앙값 \(med) (30일 \(recent30.count)개 · 최소 \(recent30.min()!) · 최대 \(recent30.max()!))")
            return med
        }

        // 2차: 표본 부족 시 60일로 확장
        let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: anchor)
        let recent60 = await fetchSamples(start: sixtyDaysAgo, end: anchor)
        if !recent60.isEmpty {
            let med = max(40, median(recent60))
            print("[존] RHR 중앙값 \(med) (60일 \(recent60.count)개 · 최소 \(recent60.min()!) · 최대 \(recent60.max()!) — 30일 표본 부족)")
            return med
        }

        // 3차 폴백: anchor 이전 전체 기간
        let allTime = await fetchSamples(start: nil, end: anchor)
        if !allTime.isEmpty {
            let med = max(40, median(allTime))
            print("[존] RHR 중앙값 \(med) (전체 \(allTime.count)개 — 60일 표본 없음)")
            return med
        }

        return nil
    }

    // MARK: - HR Zones

    /// MHR 단독 기반 존 경계 — RHR 없을 때 폴백. Karvonen보다 부정확하나 단색보다 의미 있음.
    private func hrZonesMHR(mhr: Int, samples: [(offset: TimeInterval, bpm: Int)]) -> [HRZoneData] {
        let ratios: [(name: String, lo: Double, hi: Double)] = [
            ("Z1 웜업",   0.00, 0.60),
            ("Z2 회복",   0.60, 0.70),
            ("Z3 유산소", 0.70, 0.80),
            ("Z4 임계",   0.80, 0.90),
            ("Z5 최대",   0.90, Double.infinity),  // MHR 초과 측정치도 Z5로 포함
        ]
        func bnd(_ r: Double) -> Int { Int((Double(mhr) * r).rounded()) }
        var secs = [Double](repeating: 0, count: 5)
        let sorted = samples.sorted { $0.offset < $1.offset }
        for i in 0..<sorted.count {
            let bpmF = Double(sorted[i].bpm) / Double(mhr)
            let next = i + 1 < sorted.count ? sorted[i + 1].offset : sorted[i].offset + 5
            let gap  = min(60, max(0, next - sorted[i].offset))
            for (z, r) in ratios.enumerated() {
                if bpmF >= r.lo && bpmF < r.hi { secs[z] += gap; break }
            }
        }
        let total = secs.reduce(0, +)
        guard total > 0 else { return [] }
        // %MHR 폴백에서 AT2 = HRmax × 0.90 = Zone 5 하한 → Zone 4 전체가 AT2 미만(상단 0초)
        return ratios.enumerated().map { z, r in
            HRZoneData(id: z + 1, name: r.name,
                       minBPM: z == 0 ? 0 : bnd(r.lo),
                       maxBPM: z == 4 ? mhr : bnd(r.hi) - 1,
                       seconds: secs[z], fraction: secs[z] / total,
                       splitBPM: z == 3 ? bnd(0.90) : nil,
                       upperSeconds: z == 3 ? 0 : nil)
        }
    }

    /// 런 날짜 기준 직전 30일 RHR로 Karvonen 존 계산. RHR 없으면 %MHR 폴백.
    /// [HRChart] 와 ZoneRoute도 이 함수로 일원화 — `date`: 러닝 시작 시각.
    /// 러닝 날짜 기준 나이. HealthKit DOB → 수동 입력 → nil 순.
    /// nil이면 존 계산 불가 → 뷰에서 안내 메시지 표시.
    private func effectiveAge(at date: Date) -> (age: Int, source: String)? {
        if let dob = userDateOfBirth, let year = dob.year, year > 1900,
           let midYear = Calendar.current.date(from: DateComponents(year: year, month: 6, day: 15)) {
            let age = Calendar.current.dateComponents([.year], from: midYear, to: date).year ?? 35
            return (max(15, age), "HealthKit DOB")
        }
        if manualAge > 0 { return (manualAge, "수동입력") }
        return nil
    }

    func computeHRZonesForDate(_ date: Date, samples: [(offset: TimeInterval, bpm: Int)]) async -> [HRZoneData] {
        guard !samples.isEmpty else { return [] }
        guard let (age, ageSrc) = effectiveAge(at: date) else { return [] }
        let mhr = max(150, Int((208.0 - 0.7 * Double(age)).rounded()))
        let _ = ageSrc  // consumed to silence unused-variable warning

        if let rhr = await queryLatestRestingHR(before: date), mhr > rhr {
            let hrr = Double(mhr - rhr)
            func bnd(_ r: Double) -> Int { Int((Double(rhr) + r * hrr).rounded()) }
            print("[존] HRmax \(mhr) · 경계 <\(bnd(0.60)) / \(bnd(0.60))–\(bnd(0.70)-1) / \(bnd(0.70))–\(bnd(0.80)-1) / \(bnd(0.80))–\(bnd(0.90)-1) / \(bnd(0.90))+")
            return computeKarvonenZones(samples: samples, rhr: rhr, mhr: mhr)
        }
        return hrZonesMHR(mhr: mhr, samples: samples)
    }

    /// Karvonen 존 분포 계산 (offset 기반 샘플 — fetchHRTimeSeries 결과).
    private func computeKarvonenZones(samples: [(offset: TimeInterval, bpm: Int)], rhr: Int, mhr: Int) -> [HRZoneData] {
        let hrr = Double(mhr - rhr)
        let ratios: [(name: String, lo: Double, hi: Double)] = [
            ("Z1 웜업",   0.00, 0.60),
            ("Z2 회복",   0.60, 0.70),
            ("Z3 유산소", 0.70, 0.80),
            ("Z4 임계",   0.80, 0.90),
            ("Z5 최대",   0.90, Double.infinity),  // 실제 MHR 초과 측정치도 Z5로 포함
        ]
        func boundary(_ ratio: Double) -> Int { Int((Double(rhr) + ratio * hrr).rounded()) }
        // AT2 = HRR 85% — Zone 4(80~90%) 안의 실제 심박값. 강도 분포(K-4)가 Zone 4를 여기서 나눈다.
        let at2Ratio = 0.85
        var zoneSecs = [Double](repeating: 0, count: 5)
        var z4UpperSecs: Double = 0
        let sorted = samples.sorted { $0.offset < $1.offset }
        for i in 0..<sorted.count {
            let hrrF = (Double(sorted[i].bpm) - Double(rhr)) / hrr
            let next = i + 1 < sorted.count ? sorted[i + 1].offset : sorted[i].offset + 5
            let gap  = min(60, max(0, next - sorted[i].offset))
            for (z, ratio) in ratios.enumerated() {
                if hrrF >= ratio.lo && hrrF < ratio.hi {
                    zoneSecs[z] += gap
                    if z == 3 && hrrF >= at2Ratio { z4UpperSecs += gap }
                    break
                }
            }
        }
        let total = zoneSecs.reduce(0, +)
        guard total > 0 else { return [] }
        return ratios.enumerated().map { z, ratio in
            HRZoneData(id: z + 1, name: ratio.name,
                       minBPM: z == 0 ? rhr : boundary(ratio.lo),
                       maxBPM: z == 4 ? mhr : boundary(ratio.hi) - 1,
                       seconds: zoneSecs[z], fraction: zoneSecs[z] / total,
                       splitBPM: z == 3 ? boundary(at2Ratio) : nil,
                       upperSeconds: z == 3 ? z4UpperSecs : nil)
        }
    }

    private func queryHRZones(workout: HKWorkout) async -> [HRZoneData] {
        let unit = Self.bpmUnit

        // 러닝 날짜 기준 나이 — HealthKit DOB → 수동입력 → nil(존계산불가)
        guard let (ageAtRun, ageSrc) = effectiveAge(at: workout.startDate) else { return [] }
        let mhr = max(150, Int((208.0 - 0.7 * Double(ageAtRun)).rounded()))
        let rhr = await queryLatestRestingHR(before: workout.startDate)

        // 1차: 워크아웃 연결 샘플
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let desc = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        var bpmDates: [(bpm: Double, start: Date)] = []
        if let linked = try? await desc.result(for: store) {
            bpmDates = linked.map { ($0.quantity.doubleValue(for: unit), $0.startDate) }
        }

        // 2차 시리즈 폴백: Apple Watch HR이 HKQuantitySeriesSampleBuilder로 저장된 경우.
        // options: [] — 컨테이너 startDate가 workout.startDate보다 1~2초 앞선 경우도 포함 (strictStartDate 금지).
        if bpmDates.count < 5 {
            let seriesPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
                type: HKQuantityType(.heartRate),
                predicate: HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])
            )
            let seriesDesc = HKQuantitySeriesSampleQueryDescriptor(predicate: seriesPred, options: [])
            var seen = Set<Date>()
            var seriesBpmDates: [(bpm: Double, start: Date)] = []
            do {
                for try await entry in seriesDesc.results(for: store) {
                    let start = entry.dateInterval.start
                    guard seen.insert(start).inserted else { continue }
                    seriesBpmDates.append((entry.quantity.doubleValue(for: unit), start))
                }
            } catch {}
            if seriesBpmDates.count > bpmDates.count {
                bpmDates = seriesBpmDates.sorted { $0.start < $1.start }
            }
        }

        guard bpmDates.count >= 5 else { return [] }

        let _ = ageSrc  // consumed to silence unused-variable warning
        let asSamples = bpmDates.map { (offset: $0.start.timeIntervalSince(workout.startDate), bpm: Int($0.bpm.rounded())) }

        if let rhr, mhr > rhr {
            return computeKarvonenZones(samples: asSamples, rhr: rhr, mhr: mhr)
        }
        return hrZonesMHR(mhr: mhr, samples: asSamples)
    }

    /// 이미 fetch된 HR 시리즈 샘플로 존 분포 계산 — 동기 경로 호환용 (날짜 없는 컨텍스트). 가능하면 computeHRZonesForDate 사용.
    func computeHRZonesFromSamples(_ samples: [(offset: TimeInterval, bpm: Int)]) -> [HRZoneData] {
        guard !samples.isEmpty else { return [] }
        guard let (age, _) = effectiveAge(at: Date()) else { return [] }
        // Karvonen (전역 RHR/MHR — 현재 30일 기준, 날짜별 정확도 불필요한 동기 호출용)
        if let rhr = restingHeartRate, let mhr = cachedMHR, mhr > rhr {
            return computeKarvonenZones(samples: samples, rhr: rhr, mhr: mhr)
        }
        let mhrFallback = max(150, Int((208.0 - 0.7 * Double(age)).rounded()))
        return hrZonesMHR(mhr: mhrFallback, samples: samples)
    }

    // MARK: - Interval segments (WorkoutKit plan composition)

    /// Reads the WorkoutKit plan attached to the workout, maps each planned step to a
    /// workoutActivity using goal-distance-based lookahead matching, and returns labelled
    /// IntervalSegments. Returns [] when no plan is stored or the plan is not a CustomWorkout.
    ///
    /// Lookahead matching: if a workout activity's distance is much closer to a future plan
    /// step than the current one, skip ahead — this prevents label-shifting when the Watch
    /// merges activities (e.g. during an unexpected pause between intervals).
    private func queryIntervalSegments(workout: HKWorkout) async -> [IntervalSegment] {
        guard let plan = try? await workout.workoutPlan else { return [] }
        guard case .custom(let custom) = plan.workout else { return [] }

        // Plan step with goal distance for smarter activity matching
        struct PlanStep {
            let label: String
            let isWork: Bool
            let goalDistanceM: Double?
        }

        func goalDist(_ goal: WorkoutGoal) -> Double? {
            if case .distance(let value, let unit) = goal {
                return Measurement(value: value, unit: unit).converted(to: .meters).value
            }
            return nil
        }

        // Flatten: optional warmup · blocks×iterations×steps · optional cooldown
        var flatSteps: [PlanStep] = []
        if let w = custom.warmup {
            flatSteps.append(PlanStep(label: "준비운동", isWork: false, goalDistanceM: goalDist(w.goal)))
        }
        for block in custom.blocks {
            for _ in 0..<block.iterations {
                for step in block.steps {
                    let gd = goalDist(step.step.goal)
                    switch step.purpose {
                    case .work:     flatSteps.append(PlanStep(label: "운동", isWork: true,  goalDistanceM: gd))
                    case .recovery: flatSteps.append(PlanStep(label: "회복", isWork: false, goalDistanceM: gd))
                    @unknown default: flatSteps.append(PlanStep(label: "구간", isWork: false, goalDistanceM: gd))
                    }
                }
            }
        }
        if let c = custom.cooldown {
            flatSteps.append(PlanStep(label: "정리운동", isWork: false, goalDistanceM: goalDist(c.goal)))
        }

        guard !workout.workoutActivities.isEmpty, !flatSteps.isEmpty else { return [] }

        let hrUnit = Self.bpmUnit
        let cadPred2 = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.stepCount),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let cadDesc2 = HKSampleQueryDescriptor(
            predicates: [cadPred2],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        let cadSamples2 = (try? await cadDesc2.result(for: store)) ?? []

        var result: [IntervalSegment] = []
        var planIdx = 0

        for (i, activity) in workout.workoutActivities.enumerated() {
            guard planIdx < flatSteps.count else { break }

            let distM: Double? = {
                guard let qty = activity.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                    .sumQuantity() else { return nil }
                let m = qty.doubleValue(for: .meter())
                return m > 0 ? m : nil
            }()

            // Lookahead: only when current step has a known goal distance.
            // If a step within the next 4 is >3× better match by distance ratio, skip ahead.
            // This corrects label-shifting caused by Watch merging activities on a bad interval.
            var bestIdx = planIdx
            if let actDist = distM,
               let currentGoal = flatSteps[planIdx].goalDistanceM, currentGoal > 0 {
                let currentScore = abs(actDist / currentGoal - 1.0)
                var bestScore = currentScore
                let lookahead = min(4, flatSteps.count - planIdx)
                for ahead in 1..<lookahead {
                    guard let aheadGoal = flatSteps[planIdx + ahead].goalDistanceM,
                          aheadGoal > 0 else { break }
                    let score = abs(actDist / aheadGoal - 1.0)
                    if score < bestScore * 0.3 {
                        bestScore = score
                        bestIdx = planIdx + ahead
                    }
                }
            }

            let step = flatSteps[bestIdx]
            planIdx = bestIdx + 1

            let hr: Int? = {
                guard let qty = activity.statistics(for: HKQuantityType(.heartRate))?
                    .averageQuantity() else { return nil }
                return Int(qty.doubleValue(for: hrUnit).rounded())
            }()
            let cadence: Int? = {
                let segStart = activity.startDate
                let segEnd = activity.endDate ?? workout.endDate
                let relevant = cadSamples2.filter { $0.startDate >= segStart && $0.startDate < segEnd }
                guard !relevant.isEmpty else { return nil }
                let totalSteps  = relevant.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .count()) }
                let totalDurSec = relevant.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                guard totalDurSec > 0 else { return nil }
                let spm = (totalSteps / totalDurSec) * 60
                let corrected = spm > 200 ? spm / 2 : spm
                return corrected > 60 ? Int(corrected.rounded()) : nil
            }()

            result.append(IntervalSegment(
                id: i + 1,
                startDate: activity.startDate,
                endDate: activity.endDate ?? workout.endDate,
                distanceM: distM,
                avgHeartRate: hr,
                avgCadence: cadence,
                stepLabel: step.label
            ))
        }
        return result
    }

    // MARK: - Biological characteristics

    private func readBiologicalCharacteristics() {
        userDateOfBirth = try? store.dateOfBirthComponents()
        if let sexObj = try? store.biologicalSex() {
            switch sexObj.biologicalSex {
            case .male:   userIsMale = true
            case .female: userIsMale = false
            default:      userIsMale = nil
            }
        }
    }

    private func mapType(_ type: HKWorkoutActivityType) -> ActivityType {
        switch type {
        case .running:  .running
        case .hiking:   .hiking
        default:        .walking
        }
    }

    // MARK: - Metric Trend History

    func fetchMetricHistory(_ metric: TrendMetric, from startDate: Date, usePounds: Bool = false) async -> [(date: Date, value: Double)] {
        // 캐시 히트: 파일이 존재하면 HealthKit 재조회 없이 즉시 반환 (데이터 없어도 반환)
        if let cached = loadMetricHistoryFromDisk(metric, usePounds: usePounds) {
            return cached.filter { $0.date >= startDate }
        }
        // 동일 지표 동시 요청 시 이미 실행 중인 Task를 공유 — HealthKit 중복 조회 방지
        let taskKey = "\(metric.rawValue)-\(usePounds)"
        if let existing = metricFetchTasks[taskKey] {
            return await existing.value.filter { $0.date >= startDate }
        }
        // 캐시 미스: 1년치 전부 불러와 저장 — 빈 결과도 반드시 저장해 반복 조회 방지
        let fullStart = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        let fetchTask = Task<[(date: Date, value: Double)], Never> {
            let result = await fetchMetricHistoryFromHealthKit(metric, from: fullStart, usePounds: usePounds)
            saveMetricHistoryToDisk(result, metric: metric, usePounds: usePounds, coveredFrom: fullStart)
            metricFetchTasks.removeValue(forKey: taskKey)
            return result
        }
        metricFetchTasks[taskKey] = fetchTask
        return await fetchTask.value.filter { $0.date >= startDate }
    }

    private func fetchMetricHistoryFromHealthKit(_ metric: TrendMetric, from startDate: Date, usePounds: Bool = false) async -> [(date: Date, value: Double)] {
        switch metric {
        case .vo2Max:
            return await fetchVO2MaxHistory(from: startDate)
        case .hrRecovery1:
            return await fetchRecoveryHistory(from: startDate).map { ($0.date, $0.hrr1) }
        case .bodyMass:
            let unit: HKUnit = usePounds ? HKUnit(from: "lb") : .gramUnit(with: .kilo)
            return await fetchQuantitySampleHistory(.bodyMass, from: startDate, unit: unit)
        case .bodyFatPercentage:
            // HealthKit stores body fat as a fraction (0–1); multiply by 100 to get percentage
            let raw = await fetchQuantitySampleHistory(.bodyFatPercentage, from: startDate, unit: .percent())
            return raw.map { ($0.date, $0.value * 100) }
        case .cadence, .power, .groundContactTime, .strideLength, .verticalOscillation:
            // workoutCache is in-memory only; it's empty on warm restart (early return path).
            // Fall back to a direct HK workout query so we can actually build the disk cache.
            // 메트릭 히스토리 빌드 시에는 항상 HK 전체 조회 — workoutCache는 최근만 가질 수 있음
            let fetched = (try? await queryWorkouts(since: startDate)) ?? []
            var runWorkouts = fetched.filter { $0.workoutActivityType == .running }
            for w in runWorkouts { workoutCache[w.uuid] = w }
            if runWorkouts.isEmpty {
                // HK 조회 실패 시 인메모리 캐시 폴백
                runWorkouts = workoutCache.values
                    .filter { $0.workoutActivityType == .running && $0.startDate >= startDate }
            }
            let sortedWorkouts = runWorkouts.sorted { $0.startDate < $1.startDate }
            guard !sortedWorkouts.isEmpty else { return [] }

            // Parallel per-workout queries — all HealthKit requests in flight at once
            let m = metric
            var results: [(date: Date, value: Double)] = []
            await withTaskGroup(of: (Date, Double?).self) { group in
                for workout in sortedWorkouts {
                    group.addTask {
                        // predicateForObjects 대신 시간 범위 — Garmin 등 비연결 standalone 샘플 포함
                        let wStart = workout.startDate
                        let wEnd   = workout.endDate
                        let val: Double?
                        switch m {
                        case .cadence:
                            // ⚠ querySumInRange는 시간 범위 내 모든 소스(iPhone·Watch·서드파티)를
                            //   중복 합산해 실제의 2-3배가 나올 수 있다.
                            //   queryCadence는 predicateForObjects(from: workout)으로
                            //   워크아웃에 연결된 샘플만 읽어 중복이 없다.
                            //   Garmin 등 비연결 워크아웃은 nil → 그 운동만 트렌드에서 빠진다.
                            //   2배 오류로 틀린 값을 표시하는 것보다 낫다.
                            val = await self.queryCadence(workout: workout).map { Double($0) }
                        case .power:
                            val = await self.queryAvgQuantityInRange(.runningPower, unit: .watt(), from: wStart, to: wEnd)
                        case .groundContactTime:
                            val = await self.queryAvgQuantityInRange(.runningGroundContactTime,
                                                                     unit: .secondUnit(with: .milli), from: wStart, to: wEnd)
                        case .strideLength:
                            val = await self.queryAvgQuantityInRange(.runningStrideLength, unit: .meter(), from: wStart, to: wEnd)
                        case .verticalOscillation:
                            val = await self.queryAvgQuantityInRange(.runningVerticalOscillation,
                                                                     unit: .meterUnit(with: .centi), from: wStart, to: wEnd)
                        default:
                            val = nil
                        }
                        return (workout.startDate, val)
                    }
                }
                for await (date, val) in group {
                    if let v = val, v > 0 {
                        results.append((date: date, value: v))
                    }
                }
            }
            return results.sorted { $0.date < $1.date }
        }
    }

    // MARK: - Metric history disk cache

    private struct MetricDataPoint: Codable {
        let date: Date
        let value: Double
    }

    private struct MetricHistoryCacheFile: Codable {
        let points: [MetricDataPoint]
        let cachedAt: Date
        var coveredFrom: Date?  // nil = 레거시 캐시 → 자동 무효화 대상
    }

    private static let metricCacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MIMOMetrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // 지표당 파일 1개 — 날짜 무관, 영구 캐시 (새 런 추가·새로고침 시만 삭제)
    private func metricHistoryCacheURL(_ metric: TrendMetric, usePounds: Bool) -> URL {
        let suffix = (metric == .bodyMass && usePounds) ? "_lbs" : ""
        return Self.metricCacheDir.appendingPathComponent("metric_\(metric.rawValue)\(suffix).json")
    }

    private func loadMetricHistoryFromDisk(_ metric: TrendMetric, usePounds: Bool) -> [(date: Date, value: Double)]? {
        let url = metricHistoryCacheURL(metric, usePounds: usePounds)
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(MetricHistoryCacheFile.self, from: data) else { return nil }
        // VO2Max: Apple Watch가 워크아웃 종료 후 수십 분 뒤 계산 → 2h TTL.
        // 워크아웃 직후 캐시 재구성 시 아직 새 VO2Max가 없어 이전값이 저장되는 문제 방지.
        if metric == .vo2Max, Date().timeIntervalSince(file.cachedAt) > 7_200 {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        // coveredFrom 없는 레거시 캐시, 또는 1년치를 커버하지 않는 부분 캐시는 무효화
        let requiredStart = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        guard let coveredFrom = file.coveredFrom,
              coveredFrom <= requiredStart.addingTimeInterval(86_400 * 7) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return file.points.map { ($0.date, $0.value) }
    }

    /// 새 런 추가 시 호출 — 런 기반 메트릭 캐시 삭제
    func invalidateRunningMetricHistoryCache() {
        let runningMetrics: [TrendMetric] = [.cadence, .power, .groundContactTime, .strideLength, .verticalOscillation, .vo2Max, .hrRecovery1]
        for metric in runningMetrics {
            try? FileManager.default.removeItem(at: metricHistoryCacheURL(metric, usePounds: false))
        }
        // 회복 히스토리 원본 캐시도 함께 — 파생(메트릭) 캐시만 지우면 옛 원본에서 다시 만들어진다
        try? FileManager.default.removeItem(at: recoveryHistoryURL)
    }

    /// 신체 측정(체중·체지방) 캐시 삭제 — 탭 진입 시마다 호출해 최신 HealthKit 데이터 반영
    func invalidateBodyMetricHistoryCache() {
        try? FileManager.default.removeItem(at: metricHistoryCacheURL(.bodyMass, usePounds: false))
        try? FileManager.default.removeItem(at: metricHistoryCacheURL(.bodyMass, usePounds: true))
        try? FileManager.default.removeItem(at: metricHistoryCacheURL(.bodyFatPercentage, usePounds: false))
        try? FileManager.default.removeItem(at: Self.metricCacheDir.appendingPathComponent("bodyMass_allTime.json"))
    }

    /// 당기기 새로고침 시 호출 — 모든 지표 캐시 삭제 (체성분 포함)
    func invalidateAllMetricHistoryCache() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: Self.metricCacheDir, includingPropertiesForKeys: nil) else { return }
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: - Body Change Section Queries

    /// 전체 기간 체중 기록 (오름차순). 24시간 디스크 캐시 사용.
    func fetchBodyMassAllTime() async -> [(date: Date, value: Double)] {
        let cacheURL = Self.metricCacheDir.appendingPathComponent("bodyMass_allTime.json")
        if let data = try? Data(contentsOf: cacheURL),
           let file = try? JSONDecoder().decode(MetricHistoryCacheFile.self, from: data),
           Date().timeIntervalSince(file.cachedAt) < 86_400 {
            return file.points.map { ($0.date, $0.value) }
        }
        let unit = HKUnit.gramUnit(with: .kilo)
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.bodyMass),
            predicate: HKQuery.predicateForSamples(withStart: .distantPast, end: Date(), options: [])
        )
        let desc = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        guard let samples = try? await desc.result(for: store) else { return [] }
        let result = samples.map { (date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
        let cacheFile = MetricHistoryCacheFile(
            points: result.map { MetricDataPoint(date: $0.date, value: $0.value) },
            cachedAt: Date(),
            coveredFrom: .distantPast
        )
        if let encoded = try? JSONEncoder().encode(cacheFile) {
            try? encoded.write(to: cacheURL, options: .atomic)
        }
        return result
    }

    private func saveMetricHistoryToDisk(_ points: [(date: Date, value: Double)], metric: TrendMetric, usePounds: Bool, coveredFrom: Date) {
        let file = MetricHistoryCacheFile(
            points: points.map { MetricDataPoint(date: $0.date, value: $0.value) },
            cachedAt: Date(),
            coveredFrom: coveredFrom
        )
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: metricHistoryCacheURL(metric, usePounds: usePounds), options: .atomic)
    }

    private func fetchQuantitySampleHistory(
        _ identifier: HKQuantityTypeIdentifier,
        from startDate: Date,
        unit: HKUnit
    ) async -> [(date: Date, value: Double)] {
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(identifier),
            predicate: HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: [])
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }

    private func fetchVO2MaxHistory(from startDate: Date) async -> [(date: Date, value: Double)] {
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.vo2Max),
            predicate: HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: [])
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        let unit = Self.vo2MaxUnit
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }

    // MARK: - Condition (weather + sleep)

    func fetchCondition(for activity: Activity, firstCoordinate: CLLocationCoordinate2D?) async -> ActivityCondition {
        let cached = await ConditionCache.shared.condition(for: activity.id)
        if let cached {
            let needsWeather = cached.weather == nil && firstCoordinate != nil
            let needsSleep   = !cached.sleepChecked ||
                               cached.sleepVersion < ActivityCondition.currentSleepVersion

            // Cache is complete — return immediately
            if !needsWeather && !needsSleep { return cached }

            var updated = cached
            if needsWeather,
               let w = await ConditionService.fetchWeather(date: activity.date, coordinate: firstCoordinate) {
                updated.weather = w
            }
            if needsSleep {
                async let sleepFetch = querySleepScore(nightBefore: activity.date)
                async let hrvFetch   = queryHRVRecovery(nightBefore: activity.date)
                updated.sleepScore   = await sleepFetch
                updated.hrvRecovery  = await hrvFetch
                updated.sleepChecked = true
                updated.sleepVersion = ActivityCondition.currentSleepVersion
            }
            await ConditionCache.shared.cache(updated, for: activity.id)
            return updated
        }
        // Never fetched → weather + sleep + HRV in parallel
        async let weather = ConditionService.fetchWeather(date: activity.date, coordinate: firstCoordinate)
        async let sleep   = querySleepScore(nightBefore: activity.date)
        async let hrv     = queryHRVRecovery(nightBefore: activity.date)
        let result = ActivityCondition(weather: await weather, sleepScore: await sleep,
                                       hrvRecovery: await hrv, sleepChecked: true,
                                       sleepVersion: ActivityCondition.currentSleepVersion)
        await ConditionCache.shared.cache(result, for: activity.id)
        return result
    }

    // MARK: - HRV Recovery

    /// 단일 night window(nightStart~nightEnd)의 HRV 중앙값.
    /// noiseFloor 미만 샘플은 측정 노이즈로 제외.
    private func queryNightHRVMedian(for date: Date, noiseFloor: Double = 10.0) async -> Double? {
        let cal = Calendar.current
        guard let dayStart   = cal.date(bySettingHour: 0, minute: 0, second: 0, of: date),
              let nightStart = cal.date(byAdding: .hour, value: -9,  to: dayStart),
              let nightEnd   = cal.date(byAdding: .hour, value: 12, to: dayStart) else { return nil }

        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let msUnit  = HKUnit.secondUnit(with: .milli)

        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: nightStart, end: nightEnd,
                                                   options: .strictStartDate)
            let q = HKSampleQuery(sampleType: hrvType, predicate: pred,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                cont.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            self.store.execute(q)
        }

        let values = samples
            .map { $0.quantity.doubleValue(for: msUnit) }
            .filter { $0 >= noiseFloor }
        return values.isEmpty ? nil : hrvMedian(values)
    }

    /// 수면 HRV 기반 회복 등급 계산.
    /// today: 해당 night window 중앙값.
    /// baseline: 직전 7일(today 제외) 일별 중앙값의 중앙값. 유효일 4일 미만 → .insufficient.
    private func queryHRVRecovery(nightBefore date: Date) async -> HRVRecovery? {
        let cal = Calendar.current

        guard let todayVal = await queryNightHRVMedian(for: date) else { return nil }

        var dailyValues: [Double] = []
        for offset in 1...7 {
            guard let pastDay = cal.date(byAdding: .day, value: -offset, to: date) else { continue }
            if let v = await queryNightHRVMedian(for: pastDay) { dailyValues.append(v) }
        }

        guard dailyValues.count >= 4 else {
            return HRVRecovery(todayValue: todayVal, baseline: 0, sd: 0, level: .insufficient)
        }

        let baseline    = hrvMedian(dailyValues)
        let sd          = hrvSD(dailyValues)
        let effectiveSD = max(sd, baseline * 0.10)  // SD 하한: baseline의 10%
        let level: RecoveryLevel = {
            if todayVal < baseline - 1.5 * effectiveSD { return .low }
            if todayVal > baseline + 1.5 * effectiveSD { return .high }
            return .normal
        }()

        return HRVRecovery(todayValue: todayVal, baseline: baseline, sd: sd, level: level)
    }

    // MARK: - Sleep score (50/30/20 weighted composite)

    private func querySleepScore(nightBefore date: Date) async -> SleepScore? {
        let cal = Calendar.current
        // Window: 전날 15:00 → 당일 12:00
        guard let dayStart   = cal.date(bySettingHour: 0, minute: 0, second: 0, of: date),
              let nightStart = cal.date(byAdding: .hour, value: -9,  to: dayStart),
              let nightEnd   = cal.date(byAdding: .hour, value:  12, to: dayStart)
        else { return nil }

        let dbFmt = DateFormatter(); dbFmt.dateFormat = "M/d"
        print("[Sleep:진입] \(dbFmt.string(from: date)) 윈도우 \(dbFmt.string(from: nightStart))~\(dbFmt.string(from: nightEnd))")

        // Fetch tonight's samples and 13-day bedtime history concurrently
        async let sleepTask   = fetchSleepSamples(from: nightStart, to: nightEnd)
        async let historyTask = fetchBedtimeHistory(before: date, daysBack: 13)
        let (samples, bedtimeHistory) = await (sleepTask, historyTask)

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]
        let asleepSamples = samples.filter { asleepValues.contains($0.value) }
        let awakeSamples  = samples.filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }
        print("[Sleep:샘플] 전체 \(samples.count)개, asleep \(asleepSamples.count)개, awake \(awakeSamples.count)개, 이력 \(bedtimeHistory.count)일")
        guard !asleepSamples.isEmpty else { print("[Sleep:중단] asleep 샘플 없음"); return nil }

        // Union-merge asleep samples — 30분 갭 허용: 정상 각성 구간도 하나로 묶음
        let sorted = asleepSamples.map { ($0.startDate, $0.endDate) }.sorted { $0.0 < $1.0 }
        let gapTolerance: TimeInterval = 30 * 60
        var merged: [(start: Date, end: Date)] = []
        for (s, e) in sorted {
            if let last = merged.last, s <= last.end.addingTimeInterval(gapTolerance) {
                merged[merged.count - 1] = (last.start, max(last.end, e))
            } else {
                merged.append((start: s, end: e))
            }
        }

        // Largest block before run start = 전날 밤 주 수면
        let runStart = date
        let candidates = merged.compactMap { blk -> (start: Date, end: Date, hours: Double)? in
            let effEnd = min(blk.end, runStart)
            guard effEnd > blk.start else { return nil }
            return (blk.start, effEnd, effEnd.timeIntervalSince(blk.start) / 3600.0)
        }
        guard let main = candidates.max(by: { $0.hours < $1.hours }) else { return nil }

        // 실제 수면 시간 = 주 블록 안 asleep 샘플 합산
        // (취침 시간 ≠ 수면 시간 — 각성·비수면 구간을 제외해야 Apple과 일치)
        let inBlock = asleepSamples.filter { $0.endDate > main.start && $0.startDate < main.end }
        let sleepIntervals = inBlock
            .map { (max($0.startDate, main.start), min($0.endDate, main.end)) }
            .sorted { $0.0 < $1.0 }
        var mergedSleep: [(start: Date, end: Date)] = []
        for (s, e) in sleepIntervals {
            if let last = mergedSleep.last, s <= last.end {
                mergedSleep[mergedSleep.count - 1] = (last.start, max(last.end, e))
            } else {
                mergedSleep.append((s, e))
            }
        }
        let hours = mergedSleep.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) } / 3600.0
        guard hours > 0.5, hours <= 12.0 else { return nil }

        // Component 2 — consistency (max 30): circular bedtime deviation from 13-day median
        let (consistencyPts, devMinutes) = sleepConsistencyScore(currentBedtime: main.start, history: bedtimeHistory)

        // 이상값 판정: 수면 > 10h (낮잠 합산·측정 오류) 또는 취침 편차 ≥ 170분(≈2.5h) → 일관성 계산 제외
        let isHoursOutlier    = hours > 10.0
        let isBedtimeOutlier  = devMinutes >= 170
        if isHoursOutlier || isBedtimeOutlier {
            let dbFmtOut = DateFormatter(); dbFmtOut.dateFormat = "M/d"
            let outlierReason = isHoursOutlier
                ? "수면 \(String(format: "%.2f", hours))h > 10h"
                : "편차 \(devMinutes)분"
            print("[Sleep] \(dbFmtOut.string(from: date)) 이상값(\(outlierReason)) → 일관성 계산 제외")
            return nil
        }

        // Component 3 — interruptions (max 20): awake events inside main block
        let hasWatchData = asleepSamples.contains {
            $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
            $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
            $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
        }
        let sortedAwake = awakeSamples.map { ($0.startDate, $0.endDate) }.sorted { $0.0 < $1.0 }
        var mergedAwake: [(start: Date, end: Date)] = []
        for (s, e) in sortedAwake {
            if let last = mergedAwake.last, s <= last.end.addingTimeInterval(gapTolerance) {
                mergedAwake[mergedAwake.count - 1] = (last.start, max(last.end, e))
            } else {
                mergedAwake.append((start: s, end: e))
            }
        }
        let minAwakeDuration: TimeInterval = 5 * 60   // 5분 미만 각성은 정상 수면 전환
        let significantAwake = mergedAwake.filter {
            $0.start >= main.start && $0.start < main.end &&
            $0.end.timeIntervalSince($0.start) >= minAwakeDuration
        }
        let awakeInBlock = significantAwake.count
        let bedSeconds   = main.end.timeIntervalSince(main.start)
        let awakeMinutes = Int(max(0, (bedSeconds - hours * 3600.0) / 60.0))
        let interruptionPts = sleepInterruptionScore(awakeCount: awakeInBlock, awakeMinutes: awakeMinutes, hasWatchData: hasWatchData)

        let score = SleepScore.compute(durationHours: hours, consistencyPts: consistencyPts,
                                       interruptionPts: interruptionPts)
        let goalH    = SleepScore.sleepGoalHours()
        let durPts   = SleepScore.durationScore(hours: hours, goalHours: goalH)
        let devStr   = devMinutes >= 0 ? "\(devMinutes)분" : "이력부족"
        let bedHours = bedSeconds / 3600.0
        let dbFmt2   = DateFormatter(); dbFmt2.dateFormat = "M/d"
        print("[Sleep] \(dbFmt2.string(from: date)) 취침 \(String(format: "%.2f", bedHours))h / 수면 \(String(format: "%.2f", hours))h(목표 \(String(format: "%.1f", goalH))h) / 각성 \(awakeMinutes)분 \(awakeInBlock)회 | 시간 \(durPts)/50 | 일관성 \(consistencyPts)/30 (편차 \(devStr)) | 각성 \(interruptionPts)/20 = \(score.score)")
        return score
    }

    private func fetchSleepSamples(from start: Date, to end: Date) async -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { (cont: CheckedContinuation<[HKCategorySample], Never>) in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in cont.resume(returning: (samples as? [HKCategorySample]) ?? []) }
            self.store.execute(query)
        }
    }

    /// Returns the start time (bedtime) of every main sleep block (≥3 h) in the past `daysBack` days.
    private func fetchBedtimeHistory(before date: Date, daysBack: Int) async -> [Date] {
        let cal = Calendar.current
        guard let windowStart = cal.date(byAdding: .day, value: -daysBack, to: date) else { return [] }
        let predicate = HKQuery.predicateForSamples(
            withStart: windowStart, end: date, options: .strictStartDate
        )
        let samples = await withCheckedContinuation { (cont: CheckedContinuation<[HKCategorySample], Never>) in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in cont.resume(returning: (samples as? [HKCategorySample]) ?? []) }
            self.store.execute(query)
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]
        let sorted = samples
            .filter { asleepValues.contains($0.value) }
            .map { ($0.startDate, $0.endDate) }
            .sorted { $0.0 < $1.0 }

        let gapTolerance: TimeInterval = 5 * 60
        var merged: [(start: Date, end: Date)] = []
        for (s, e) in sorted {
            if let last = merged.last, s <= last.end.addingTimeInterval(gapTolerance) {
                merged[merged.count - 1] = (last.start, max(last.end, e))
            } else {
                merged.append((start: s, end: e))
            }
        }
        let cal2 = Calendar.current
        return merged.compactMap { blk -> Date? in
            guard blk.end.timeIntervalSince(blk.start) / 3600 >= 3.0 else { return nil }
            // 낮잠·오전 회복수면 제외: 취침시각이 오후 6시(18시) ~ 새벽 5시 59분인 블록만
            // (아침 달리기 후 낮잠이 3h+ 이상이면 평균 취침시각을 낮게 왜곡해 consistency=0 유발)
            let h = cal2.component(.hour, from: blk.start)
            guard h >= 18 || h < 6 else { return nil }
            return blk.start
        }
    }

    /// 각성 점수 = 시간점수(max 14) + 횟수점수(max 6).
    /// 워치 데이터 없으면 중간값 15점 고정.
    private func sleepInterruptionScore(awakeCount: Int, awakeMinutes: Int, hasWatchData: Bool) -> Int {
        guard hasWatchData else { return 15 }
        let timePts: Int = switch awakeMinutes {
        case ..<8:   14
        case ..<15:  12
        case ..<22:  9
        case ..<30:  6
        case ..<40:  3
        case ..<55:  1
        default:     0
        }
        let countPts: Int = switch awakeCount {
        case 0:  6
        case 1:  5
        case 2:  3
        case 3:  2
        default: 0
        }
        return max(0, timePts + countPts)
    }

    /// 취침 일관성 점수 (max 30). 반환값: (점수, 편차분) — 편차 -1 은 이력 부족.
    /// 정오(12:00)를 기준점으로 순환 비교해 23:50↔00:10 같은 자정 넘김 오계산을 방지.
    /// 2패스 중앙값: 예비 중앙값 기준 ±180분 초과 이력 제거 후 재계산. 최저 6점 (Apple 정합 완화 곡선).
    private func sleepConsistencyScore(currentBedtime: Date, history: [Date]) -> (score: Int, deviationMinutes: Int) {
        guard history.count >= 5 else { return (21, -1) }  // 이력 부족 → 중간값 21
        let cal = Calendar.current
        // 정오를 원점으로 분 단위 환산 (0=12:00, 720=24:00/00:00, 1439=11:59)
        let toMinsFromNoon: (Date) -> Int = { d in
            let h = cal.component(.hour, from: d)
            let m = cal.component(.minute, from: d)
            return ((h * 60 + m) - 12 * 60 + 1440) % 1440
        }
        // 순환 거리: 23:50 vs 00:10 → 20분 (1430분이 아님)
        let circularDist: (Int, Int) -> Int = { a, b in
            let diff = abs(a - b); return min(diff, 1440 - diff)
        }
        let medianOf: ([Int]) -> Int = { sorted in
            sorted.count % 2 == 0
                ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
                : sorted[sorted.count / 2]
        }

        // Pass 1: 예비 중앙값
        let allMins = history.map(toMinsFromNoon).sorted()
        let preliminaryMedian = medianOf(allMins)

        // 이력 중 이상값(예비 중앙값에서 ±3h 초과) 제거 후 재계산
        let tf = DateFormatter(); tf.dateFormat = "M/d HH:mm"
        let filteredHistory = history.filter { d in
            circularDist(toMinsFromNoon(d), preliminaryMedian) <= 180
        }
        let removedCount = history.count - filteredHistory.count
        if removedCount > 0 {
            let removedStrs = history.filter { d in
                circularDist(toMinsFromNoon(d), preliminaryMedian) > 180
            }.map { tf.string(from: $0) }.joined(separator: ", ")
            print("[Sleep:이력] 이상값 \(removedCount)건 제거 → \(removedStrs)")
        }

        // Pass 2: 정제된 이력으로 최종 중앙값
        let cleanedMins = (filteredHistory.count >= 3 ? filteredHistory : history).map(toMinsFromNoon).sorted()
        let median = medianOf(cleanedMins)
        let deviation = circularDist(toMinsFromNoon(currentBedtime), median)

        // 취침시각 디버그 로그
        let tf2 = DateFormatter(); tf2.dateFormat = "HH:mm"
        let histStr = history.map { tf2.string(from: $0) }.joined(separator: ", ")
        let medFromMidnight = (median + 720) % 1440
        let medStr = String(format: "%02d:%02d", medFromMidnight / 60, medFromMidnight % 60)
        print("[Sleep:취침] 오늘 \(tf2.string(from: currentBedtime)) | 이력 \(histStr) | 중앙값 \(medStr) | 편차 \(deviation)분")

        // Apple 정합 곡선: 82분 편차 → 21점 (실측 일치)
        let score: Int = switch deviation {
        case ..<21:  30
        case ..<36:  28
        case ..<51:  26
        case ..<71:  23
        case ..<91:  21   // 82분이 여기 — Apple 값(21/30)과 일치
        case ..<121: 17
        case ..<151: 13
        case ..<181: 9
        default:     6    // 최저 6
        }
        return (score, deviation)
    }
}
