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
    var userLevel: UserLevel = UserLevel(bucket: .beginner, ageGrade: nil, best5KEquivSec: nil, best5KDate: nil, vdot: nil)
    /// Latest resting HR from HealthKit — used as RHR in Karvonen zone calc
    var restingHeartRate: Int? = nil

    private let store = HKHealthStore()
    @ObservationIgnored private var workoutCache: [UUID: HKWorkout] = [:]
    @ObservationIgnored private var cachedMHR: Int? = nil
    @ObservationIgnored private var isFetchInProgress = false
    @ObservationIgnored private var pausedIntervalsCache: [UUID: [DateInterval]] = [:]
    @ObservationIgnored private var detailCache: [UUID: ActivityDetail] = [:]
    @ObservationIgnored private var hrSeriesCache: [UUID: [(offset: TimeInterval, bpm: Int)]] = [:]
    @ObservationIgnored private var panelSeriesCache: [String: [(offset: TimeInterval, value: Double)]] = [:]

    // Codable proxies for disk serialization of time-series tuples
    private struct HRPoint: Codable { var offset: Double; var bpm: Int }
    private struct SeriesPoint: Codable { var offset: Double; var value: Double }

    @ObservationIgnored private let cacheContainer: ModelContainer? = {
        let schema = Schema([CachedActivity.self])
        return try? ModelContainer(for: schema,
                                   configurations: ModelConfiguration("activity-cache",
                                                                       schema: schema,
                                                                       isStoredInMemoryOnly: false))
    }()
    private var cacheContext: ModelContext? { cacheContainer?.mainContext }

    /// True when any loaded workout originates from Garmin Connect.
    var hasGarminSource: Bool {
        workoutCache.values.contains {
            $0.sourceRevision.source.bundleIdentifier.lowercased().contains("garmin")
        }
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
            HKQuantityType(.distanceCycling),
            HKQuantityType(.cyclingPower),
            HKQuantityType(.cyclingSpeed),
            HKQuantityType(.cyclingCadence),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.swimmingStrokeCount),
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
        // Re-request to cover any types added after initial auth — HealthKit only prompts for new/undecided types.
        try? await store.requestAuthorization(toShare: [], read: Self.readTypes)
        authorizationStatus = .authorized
        await fetchActivities()
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

    func fetchActivities() async {
        guard !isFetchInProgress else { return }
        isFetchInProgress = true
        defer { isFetchInProgress = false }

        // Fast path: data is loaded and was synced very recently — skip disk read + all async work.
        let lastSync = UserDefaults.standard.object(forKey: "mimo.lastSyncedAt") as? Date
        if !activities.isEmpty, let last = lastSync, Date().timeIntervalSince(last) < 300 {
            return
        }

        isLoading = true

        // Phase 0: instant display from SwiftData cache (zero HealthKit queries)
        let cached = loadActivityCache()
        let isWarmCache = !cached.isEmpty
        if isWarmCache {
            activities = cached.map { $0.toActivity() }
            isLoading = false
        }

        // Resolve subscription status and prepare HRZone parameters before HealthKit query.
        await ProManager.shared.checkEntitlements()
        readBiologicalCharacteristics()
        if restingHeartRate == nil { await refreshHRZoneParameters() }

        defer { isLoading = false }

        do {
            let cacheDict = Dictionary(uniqueKeysWithValues: cached.map { ($0.workoutID, $0) })

            // Warm cache: only query workouts newer than the latest cached entry — very fast.
            // Cold cache: full 12-month query.
            let since: Date? = isWarmCache
                ? cached.map(\.date).max().flatMap { Calendar.current.date(byAdding: .day, value: -1, to: $0) }
                : nil
            let fetchedWorkouts = try await queryWorkouts(since: since)

            if isWarmCache {
                if fetchedWorkouts.isEmpty {
                    // Nothing new — level recompute only.
                    userLevel = LevelEngine.compute(activities: activities, dateOfBirth: userDateOfBirth, isMale: userIsMale)
                    UserDefaults.standard.set(Date(), forKey: "mimo.lastSyncedAt")
                    return
                }
                // Prepend new workouts to cached list (avoiding duplicates).
                let newIDs = Set(fetchedWorkouts.map { $0.uuid.uuidString })
                let newActivities = fetchedWorkouts.map { w -> Activity in
                    let summary = buildSummary(from: w)
                    return cacheDict[w.uuid.uuidString]?.toActivity() ?? summary
                }
                activities = newActivities + activities.filter { !newIDs.contains($0.id.uuidString) }
            } else {
                // Cold cache: query recent 2 months first for fast display.
                let twoMonthsAgo = Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? .distantPast
                let recentWorkouts = try await queryWorkouts(since: twoMonthsAgo)
                activities = recentWorkouts.map { w -> Activity in
                    let summary = buildSummary(from: w)
                    return cacheDict[w.uuid.uuidString]?.toActivity() ?? summary
                }
                isLoading = false
                await enrichAndCache(recentWorkouts, cacheDict: cacheDict)
                userLevel = LevelEngine.compute(activities: activities, dateOfBirth: userDateOfBirth, isMale: userIsMale)
                UserDefaults.standard.set(Date(), forKey: "mimo.lastSyncedAt")

                // Background: fetch older history (months 3–12).
                Task { await self.fetchOlderActivities(until: twoMonthsAgo) }
                return
            }

            // Warm cache new-workout enrich path.
            await enrichAndCache(fetchedWorkouts, cacheDict: cacheDict)
            userLevel = LevelEngine.compute(activities: activities, dateOfBirth: userDateOfBirth, isMale: userIsMale)
            UserDefaults.standard.set(Date(), forKey: "mimo.lastSyncedAt")
        } catch {
            self.error = error
        }
    }

    // MARK: - Background history fetch (cold cache: months 3–12)

    private func fetchOlderActivities(until: Date) async {
        guard let oldWorkouts = try? await queryWorkouts(until: until), !oldWorkouts.isEmpty else { return }
        let cached = loadActivityCache()
        let cacheDict = Dictionary(uniqueKeysWithValues: cached.map { ($0.workoutID, $0) })
        let existingIDs = Set(activities.map { $0.id.uuidString })
        let toAdd = oldWorkouts.compactMap { w -> Activity? in
            guard !existingIDs.contains(w.uuid.uuidString) else { return nil }
            let summary = buildSummary(from: w)
            return cacheDict[w.uuid.uuidString]?.toActivity() ?? summary
        }
        if !toAdd.isEmpty { activities += toAdd }
        await enrichAndCache(oldWorkouts, cacheDict: cacheDict)
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

    private static let workoutTypeCacheKey = "mimo.workoutTypeCache.v1"

    private func persistWorkoutType(_ type: WorkoutType, for id: UUID) {
        var dict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
        dict[id.uuidString] = type.rawValue
        UserDefaults.standard.set(dict, forKey: Self.workoutTypeCacheKey)
    }

    /// Returns the workout type for display in the list. Checks memory → UserDefaults (persists across launches).
    func cachedWorkoutType(for activityID: UUID) -> WorkoutType? {
        let type: WorkoutType
        if let detail = detailCache[activityID] {
            type = detail.workoutType
        } else {
            let dict = UserDefaults.standard.dictionary(forKey: Self.workoutTypeCacheKey) as? [String: String] ?? [:]
            guard let raw = dict[activityID.uuidString], let t = WorkoutType(rawValue: raw) else { return nil }
            type = t
        }
        return type == .interval ? .interval : nil
    }

    func fetchDetail(for activityID: UUID) async -> ActivityDetail? {
        if let cached = detailCache[activityID], cached.isComplete { return cached }
        if let disk = loadDetailFromDisk(activityID), disk.isComplete {
            detailCache[activityID] = disk
            persistWorkoutType(disk.workoutType, for: activityID)
            return disk
        }
        let result = await fetchDetailFromHealthKit(for: activityID)
        if let result {
            detailCache[activityID] = result
            // Only persist when data is complete so the next visit retries HealthKit
            // if fields like GPS route were still being processed at the time of fetch.
            if result.isComplete { saveDetailToDisk(result, id: activityID) }
            persistWorkoutType(result.workoutType, for: activityID)
        }
        return result
    }

    private func detailCacheURL(_ id: UUID) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_detail", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("v2_\(id.uuidString).json")
    }

    private func loadDetailFromDisk(_ id: UUID) -> ActivityDetail? {
        let url = detailCacheURL(id)
        // Migrate existing cache files from old Caches/ location (cleared by iOS) to Application Support/.
        if !FileManager.default.fileExists(atPath: url.path) {
            let oldURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("mimo_detail_v2_\(id.uuidString).json")
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try? FileManager.default.moveItem(at: oldURL, to: url)
            }
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ActivityDetail.self, from: data)
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
            async let vo2Task      = queryLatestVO2Max(before: workout.endDate)

            let (locations, splits, zones, powerVal, cadence) =
                await (locTask, splitsTask, zonesTask, powerTask, cadTask)
            let intervals = await intervalTask
            let (gct, strideLen, vertOsc, vo2) = await (gctTask, strTask, voTask, vo2Task)

            let workoutType: WorkoutType = {
                guard let activity = activities.first(where: { $0.id == activityID }) else { return .general }
                return WorkoutTypeClassifier.classify(activity: activity, history: activities,
                                                      splits: splits, intervalSegments: intervals)
            }()
            return ActivityDetail(
                routeCoordinates: locations.map(\.coordinate),
                elevationGain: computeElevationGain(from: locations),
                avgSpeed: nil,
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
                poolLength: nil,
                swimmingStrokeCount: nil,
                swimLapCount: nil,
                swolfScore: nil,
                altitudeProfile: computeAltitudeProfile(from: locations),
                altitudeTimeProfile: computeAltitudeTimeProfile(from: locations, workoutStart: workout.startDate)
            )

        case .cycling:
            async let locTask   = fetchRouteLocations(for: workout)
            async let speedTask = queryAvgQuantity(.cyclingSpeed, unit: HKUnit(from: "m/s"), workout: workout)
            async let powerTask = queryAvgQuantity(.cyclingPower, unit: .watt(), workout: workout)
            async let cadTask   = queryAvgQuantity(.cyclingCadence,
                                                    unit: Self.bpmUnit,
                                                    workout: workout)

            let (locations, speed, power, cad, zones) = await (locTask, speedTask, powerTask, cadTask, zonesTask)

            return ActivityDetail(
                routeCoordinates: locations.map(\.coordinate),
                elevationGain: computeElevationGain(from: locations),
                avgSpeed: speed.map { $0 * 3.6 },
                avgPower: power.map { Int($0.rounded()) },
                avgCadence: cad.map { Int($0.rounded()) },
                splits: [],
                hrZones: zones,
                intervalSegments: [],
                workoutType: .general,
                avgGroundContactTime: nil,
                avgStrideLength: nil,
                avgVerticalOscillation: nil,
                vo2Max: nil,
                poolLength: nil,
                swimmingStrokeCount: nil,
                swimLapCount: nil,
                swolfScore: nil,
                altitudeProfile: computeAltitudeProfile(from: locations),
                altitudeTimeProfile: computeAltitudeTimeProfile(from: locations, workoutStart: workout.startDate)
            )

        case .swimming:
            let zones = await zonesTask
            let strokeDouble = await querySum(.swimmingStrokeCount, unit: .count(), workout: workout)
            let lapCount = workout.workoutEvents?.filter { $0.type == .lap }.count ?? 0
            let poolLength = (workout.metadata?[HKMetadataKeyLapLength] as? HKQuantity)?
                .doubleValue(for: .meter())
            let intStrokeCount = strokeDouble > 0 ? Int(strokeDouble.rounded()) : nil

            var swolf: Double? = nil
            if lapCount > 0, strokeDouble > 0 {
                let avgSecsPerLap    = workout.duration / Double(lapCount)
                let avgStrokesPerLap = strokeDouble / Double(lapCount)
                swolf = avgSecsPerLap + avgStrokesPerLap
            }

            return ActivityDetail(
                routeCoordinates: [],
                elevationGain: nil,
                avgSpeed: nil,
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
                poolLength: poolLength,
                swimmingStrokeCount: intStrokeCount,
                swimLapCount: lapCount > 0 ? lapCount : nil,
                swolfScore: swolf,
                altitudeProfile: [],
                altitudeTimeProfile: []
            )

        default: // walking, hiking
            let (locations, zones) = await (fetchRouteLocations(for: workout), zonesTask)
            return ActivityDetail(
                routeCoordinates: locations.map(\.coordinate),
                elevationGain: computeElevationGain(from: locations),
                avgSpeed: nil,
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
                poolLength: nil,
                swimmingStrokeCount: nil,
                swimLapCount: nil,
                swolfScore: nil,
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
            HKQuery.predicateForWorkouts(with: .cycling),
            HKQuery.predicateForWorkouts(with: .swimming),
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
    private func buildSummary(from workout: HKWorkout) -> Activity {
        workoutCache[workout.uuid] = workout
        let distID = distanceTypeID(for: workout.workoutActivityType)
        let distance = workout.statistics(for: HKQuantityType(distID))?
            .sumQuantity()?.doubleValue(for: .meter())
            ?? workout.totalDistance?.doubleValue(for: .meter())
            ?? 0
        return Activity(
            id: workout.uuid,
            type: mapType(workout.workoutActivityType),
            date: workout.startDate,
            duration: workout.duration,
            distance: distance,
            calories: nil,
            avgHeartRate: nil
        )
    }

    private func distanceTypeID(for type: HKWorkoutActivityType) -> HKQuantityTypeIdentifier {
        switch type {
        case .cycling:  return .distanceCycling
        case .swimming: return .distanceSwimming
        default:        return .distanceWalkingRunning
        }
    }

    /// Add calories + heart rate. Runs two stat queries concurrently.
    /// Also retries distance via sample query if embedded stats returned 0.
    private func enrich(_ activity: Activity, workout: HKWorkout) async -> Activity {
        async let calTask  = querySum(.activeEnergyBurned, unit: .kilocalorie(), workout: workout)
        async let hrTask   = queryAvgHeartRate(workout: workout)
        let (cal, hr) = await (calTask, hrTask)

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

        return Activity(
            id: activity.id,
            type: activity.type,
            date: activity.date,
            duration: activity.duration,
            distance: distance,
            calories: cal > 0 ? cal : nil,
            avgHeartRate: hr
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
        if let cached = hrSeriesCache[workoutID] { return cached }
        if let disk = loadHRSeriesFromDisk(workoutID) {
            hrSeriesCache[workoutID] = disk
            return disk
        }
        guard let workout = workoutCache[workoutID] else { return [] }
        let paused = pausedIntervals(for: workout)
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let unit = Self.bpmUnit
        let result = samples
            .filter { !isPaused($0.startDate, in: paused) }
            .map { sample in
                let bpm = Int(sample.quantity.doubleValue(for: unit).rounded())
                let offset = sample.startDate.timeIntervalSince(workout.startDate)
                return (offset: offset, bpm: bpm)
            }
        hrSeriesCache[workoutID] = result
        saveHRSeriesToDisk(result, id: workoutID)
        return result
    }

    private func hrSeriesCacheURL(_ id: UUID) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_hr_\(id.uuidString).json")
    }

    private func loadHRSeriesFromDisk(_ id: UUID) -> [(offset: TimeInterval, bpm: Int)]? {
        guard let data = try? Data(contentsOf: hrSeriesCacheURL(id)),
              let pts = try? JSONDecoder().decode([HRPoint].self, from: data) else { return nil }
        return pts.map { (offset: $0.offset, bpm: $0.bpm) }
    }

    private func saveHRSeriesToDisk(_ series: [(offset: TimeInterval, bpm: Int)], id: UUID) {
        guard let data = try? JSONEncoder().encode(series.map { HRPoint(offset: $0.offset, bpm: $0.bpm) }) else { return }
        try? data.write(to: hrSeriesCacheURL(id), options: .atomic)
    }

    // MARK: - Workout time-series (for share card panels)

    func fetchWorkoutTimeSeries(for workoutID: UUID, identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> [(offset: TimeInterval, value: Double)] {
        let key = "\(workoutID)_\(identifier.rawValue)"
        if let cached = panelSeriesCache[key] { return cached }
        if let disk = loadPanelSeriesFromDisk(key: key) {
            panelSeriesCache[key] = disk
            return disk
        }
        guard let workout = workoutCache[workoutID] else { return [] }
        let paused = pausedIntervals(for: workout)
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(identifier),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let result = samples
            .filter { !isPaused($0.startDate, in: paused) }
            .map { s in
                (offset: s.startDate.timeIntervalSince(workout.startDate),
                 value: s.quantity.doubleValue(for: unit))
            }
        panelSeriesCache[key] = result
        savePanelSeriesToDisk(result, key: key)
        return result
    }

    func fetchCadenceTimeSeries(for workoutID: UUID) async -> [(offset: TimeInterval, value: Double)] {
        let key = "\(workoutID)_cadence"
        if let cached = panelSeriesCache[key] { return cached }
        if let disk = loadPanelSeriesFromDisk(key: key) {
            panelSeriesCache[key] = disk
            return disk
        }
        guard let workout = workoutCache[workoutID] else { return [] }
        let paused = pausedIntervals(for: workout)
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.stepCount),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let workoutDuration = workout.duration

        var result: [(offset: TimeInterval, value: Double)] = []
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
                    result.append((offset: t, value: spm))
                }
            } else {
                result.append((offset: startOffset + dur / 2, value: spm))
            }
        }
        let filtered = result.filter { $0.offset >= 0 }
        panelSeriesCache[key] = filtered
        savePanelSeriesToDisk(filtered, key: key)
        return filtered
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

        let hrPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let hrDesc = HKSampleQueryDescriptor(
            predicates: [hrPred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        let powerPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.runningPower),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let powerDesc = HKSampleQueryDescriptor(
            predicates: [powerPred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        let stepPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.stepCount),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let stepDesc = HKSampleQueryDescriptor(
            predicates: [stepPred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        async let hrFetch    = hrDesc.result(for: store)
        async let powerFetch = powerDesc.result(for: store)
        async let stepFetch  = stepDesc.result(for: store)
        let hrSamples    = (try? await hrFetch)    ?? []
        let powerSamples = (try? await powerFetch) ?? []
        let stepSamples  = (try? await stepFetch)  ?? []
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
        var prevDate = timeline.first!.date
        for crossing in crossings {
            let dur = crossing.date.timeIntervalSince(prevDate)
            guard dur > 1 else { prevDate = crossing.date; continue }
            let activeDur = activeDuration(from: prevDate, to: crossing.date, paused: paused)
            result.append(SplitData(
                id: crossing.km, distanceM: 1000, duration: activeDur,
                avgHeartRate: splitAvgHR(from: prevDate, to: crossing.date, samples: hrSamples, paused: paused),
                avgCadence: splitAvgCadence(from: prevDate, to: crossing.date, duration: activeDur, samples: stepSamples, paused: paused),
                avgPower: splitAvgPower(from: prevDate, to: crossing.date, samples: powerSamples, paused: paused)
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
                result.append(SplitData(
                    id: lastKm + 1, distanceM: remaining, duration: activeDur,
                    avgHeartRate: splitAvgHR(from: prevDate, to: lastDate, samples: hrSamples, paused: paused),
                    avgCadence: splitAvgCadence(from: prevDate, to: lastDate, duration: activeDur, samples: stepSamples, paused: paused),
                    avgPower: splitAvgPower(from: prevDate, to: lastDate, samples: powerSamples, paused: paused)
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

    private func splitAvgHR(from start: Date, to end: Date, samples: [HKQuantitySample], paused: [DateInterval] = []) -> Int? {
        let unit = Self.bpmUnit
        let relevant = samples.filter { $0.startDate >= start && $0.startDate < end && !isPaused($0.startDate, in: paused) }
        guard !relevant.isEmpty else { return nil }
        let sum = relevant.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
        return Int((sum / Double(relevant.count)).rounded())
    }

    private func splitAvgPower(from start: Date, to end: Date, samples: [HKQuantitySample], paused: [DateInterval] = []) -> Int? {
        let relevant = samples.filter { $0.startDate >= start && $0.startDate < end && !isPaused($0.startDate, in: paused) }
        guard !relevant.isEmpty else { return nil }
        let sum = relevant.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .watt()) }
        return Int((sum / Double(relevant.count)).rounded())
    }

    private func splitAvgCadence(from start: Date, to end: Date, duration: TimeInterval, samples: [HKQuantitySample], paused: [DateInterval] = []) -> Int? {
        let relevant = samples.filter { $0.startDate >= start && $0.startDate < end && !isPaused($0.startDate, in: paused) }
        guard !relevant.isEmpty, duration > 0 else { return nil }
        // duration은 이미 정지 제외된 활성 시간 — 추가 차감 없이 직접 사용
        let totalSteps = relevant.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .count()) }
        return Int((totalSteps / (duration / 60)).rounded())
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

    /// Fetches resting HR samples (최근 30일 우선, 없으면 전체 기간) — 중앙값 반환.
    private func queryLatestRestingHR() async -> Int? {
        let unit = Self.bpmUnit

        func fetchSamples(start: Date?) async -> [Int] {
            let predicate = HKQuery.predicateForSamples(
                withStart: start, end: Date(), options: start == nil ? [] : .strictStartDate
            )
            let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
                type: HKQuantityType(.restingHeartRate), predicate: predicate
            )
            let desc = HKSampleQueryDescriptor(
                predicates: [pred],
                sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .reverse)],
                limit: 7
            )
            guard let samples = try? await desc.result(for: store) else { return [] }
            return samples.map { Int($0.quantity.doubleValue(for: unit).rounded()) }.sorted()
        }

        // 1차: 최근 30일 — 애플과 동일하게 최솟값 사용
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        let recent = await fetchSamples(start: thirtyDaysAgo)
        if !recent.isEmpty {
            let rhr = max(40, recent.min() ?? 40)   // 비정상 저값(40 미만) 방지
            return rhr
        }

        // 2차 폴백: 전체 기간
        let allTime = await fetchSamples(start: nil)
        if !allTime.isEmpty {
            let rhr = max(40, allTime.min() ?? 40)
            return rhr
        }

        return nil
    }

    // MARK: - HR Zones

    private func queryHRZones(workout: HKWorkout) async -> [HRZoneData] {
        // Both RHR (HealthKit) and age are required — without them, skip zone display
        guard let rhr = restingHeartRate, let mhr = cachedMHR, mhr > rhr else { return [] }

        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let desc = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        guard let samples = try? await desc.result(for: store), samples.count >= 5 else { return [] }

        let hrr = Double(mhr - rhr)
        // Karvonen: boundary = RHR + ratio × HRR  (Apple 기본값)
        // Z1 <60%  Z2 60–70%  Z3 70–80%  Z4 80–90%  Z5 90%+
        let ratios: [(name: String, lo: Double, hi: Double)] = [
            ("Z1 웜업",   0.00, 0.60),
            ("Z2 회복",   0.60, 0.70),
            ("Z3 유산소", 0.70, 0.80),
            ("Z4 임계",   0.80, 0.90),
            ("Z5 최대",   0.90, 1.01),
        ]
        func boundary(_ ratio: Double) -> Int { Int((Double(rhr) + ratio * hrr).rounded()) }

        var zoneSecs = [Double](repeating: 0, count: 5)
        let unit = Self.bpmUnit

        for i in 0..<samples.count {
            let bpm  = samples[i].quantity.doubleValue(for: unit)
            let hrrF = (bpm - Double(rhr)) / hrr
            let next = i + 1 < samples.count ? samples[i + 1].startDate : workout.endDate
            let gap  = min(60, max(0, next.timeIntervalSince(samples[i].startDate)))
            for (z, ratio) in ratios.enumerated() {
                if hrrF >= ratio.lo && hrrF < ratio.hi { zoneSecs[z] += gap; break }
            }
        }

        let total = zoneSecs.reduce(0, +)
        guard total > 0 else { return [] }

        return ratios.enumerated().map { z, ratio in
            HRZoneData(
                id: z + 1, name: ratio.name,
                minBPM: z == 0 ? rhr          : boundary(ratio.lo),
                maxBPM: z == 4 ? mhr          : boundary(ratio.hi) - 1,
                seconds: zoneSecs[z],
                fraction: zoneSecs[z] / total
            )
        }
    }

    // MARK: - Interval segments (WorkoutKit plan composition)

    /// Reads the WorkoutKit plan attached to the workout, maps each planned step to a
    /// workoutActivity, and returns labelled IntervalSegments.  Returns [] when:
    /// • no plan is stored on the workout
    /// • the plan is not a CustomWorkout
    /// • the activity count doesn't match the flattened step count
    private func queryIntervalSegments(workout: HKWorkout) async -> [IntervalSegment] {
        guard let plan = try? await workout.workoutPlan else {
            return []
        }

        guard case .custom(let custom) = plan.workout else {
            return []
        }

        // Flatten: optional warmup · blocks×iterations×steps · optional cooldown
        var flatLabels: [(label: String, isWork: Bool)] = []
        if custom.warmup != nil { flatLabels.append(("준비운동", false)) }
        for block in custom.blocks {
            for _ in 0..<block.iterations {
                for step in block.steps {
                    switch step.purpose {
                    case .work:     flatLabels.append(("운동", true))
                    case .recovery: flatLabels.append(("회복", false))
                    @unknown default: flatLabels.append(("구간", false))
                    }
                }
            }
        }
        if custom.cooldown != nil { flatLabels.append(("정리운동", false)) }

        guard workout.workoutActivities.count == flatLabels.count else {
            return []
        }

        let hrUnit = Self.bpmUnit

        // Fetch step count samples for the whole workout; filter per segment below.
        // workoutActivity.statistics(for: .stepCount) is not stored per activity segment.
        let stepPred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.stepCount),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let stepDesc = HKSampleQueryDescriptor(
            predicates: [stepPred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        let stepSamples = (try? await stepDesc.result(for: store)) ?? []

        var result: [IntervalSegment] = []

        for (i, (activity, labelPair)) in zip(workout.workoutActivities, flatLabels).enumerated() {
            let distM: Double? = {
                guard let qty = activity.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                    .sumQuantity() else { return nil }
                let m = qty.doubleValue(for: .meter())
                return m > 0 ? m : nil
            }()
            let hr: Int? = {
                guard let qty = activity.statistics(for: HKQuantityType(.heartRate))?
                    .averageQuantity() else { return nil }
                return Int(qty.doubleValue(for: hrUnit).rounded())
            }()
            let cadence: Int? = {
                let segStart = activity.startDate
                let segEnd = activity.endDate ?? workout.endDate
                let segDuration = segEnd.timeIntervalSince(segStart)
                guard segDuration > 10 else { return nil }
                let steps = stepSamples
                    .filter { $0.startDate >= segStart && $0.endDate <= segEnd }
                    .reduce(0.0) { $0 + $1.quantity.doubleValue(for: .count()) }
                guard steps > 0 else { return nil }
                return Int((steps / (segDuration / 60)).rounded())
            }()

            var paceStr = "—"
            if let d = distM, d > 0, activity.duration > 0 {
                let sPerKm = activity.duration / (d / 1000)
                paceStr = String(format: "%d'%02d\"/km", Int(sPerKm) / 60, Int(sPerKm) % 60)
            }
            result.append(IntervalSegment(
                id: i + 1,
                startDate: activity.startDate,
                endDate: activity.endDate ?? workout.endDate,
                distanceM: distM,
                avgHeartRate: hr,
                avgCadence: cadence,
                stepLabel: labelPair.label
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
        case .cycling:  .cycling
        case .swimming: .swimming
        default:        .walking
        }
    }

    // MARK: - Metric Trend History

    func fetchMetricHistory(_ metric: TrendMetric, from startDate: Date, usePounds: Bool = false) async -> [(date: Date, value: Double)] {
        if let disk = loadMetricHistoryFromDisk(metric, startDate: startDate, usePounds: usePounds) {
            return disk
        }
        let result = await fetchMetricHistoryFromHealthKit(metric, from: startDate, usePounds: usePounds)
        if !result.isEmpty {
            saveMetricHistoryToDisk(result, metric: metric, startDate: startDate, usePounds: usePounds)
        }
        return result
    }

    private func fetchMetricHistoryFromHealthKit(_ metric: TrendMetric, from startDate: Date, usePounds: Bool = false) async -> [(date: Date, value: Double)] {
        switch metric {
        case .vo2Max:
            return await fetchVO2MaxHistory(from: startDate)
        case .bodyMass:
            let unit: HKUnit = usePounds ? HKUnit(from: "lb") : .gramUnit(with: .kilo)
            return await fetchQuantitySampleHistory(.bodyMass, from: startDate, unit: unit)
        case .bodyFatPercentage:
            // HealthKit stores body fat as a fraction (0–1); multiply by 100 to get percentage
            let raw = await fetchQuantitySampleHistory(.bodyFatPercentage, from: startDate, unit: .percent())
            return raw.map { ($0.date, $0.value * 100) }
        case .cadence, .power, .groundContactTime, .strideLength, .verticalOscillation:
            let workouts = workoutCache.values
                .filter { $0.workoutActivityType == .running && $0.startDate >= startDate }
                .sorted { $0.startDate < $1.startDate }
            guard !workouts.isEmpty else { return [] }

            var results: [(date: Date, value: Double)] = []
            for workout in workouts {
                let val: Double?
                switch metric {
                case .cadence:
                    let steps = await querySum(.stepCount, unit: .count(), workout: workout)
                    let mins = workout.duration / 60
                    val = (steps > 0 && mins > 0) ? steps / mins : nil
                case .power:
                    val = await queryAvgQuantity(.runningPower, unit: .watt(), workout: workout)
                case .groundContactTime:
                    val = await queryAvgQuantity(.runningGroundContactTime,
                                                 unit: .secondUnit(with: .milli), workout: workout)
                case .strideLength:
                    val = await queryAvgQuantity(.runningStrideLength, unit: .meter(), workout: workout)
                case .verticalOscillation:
                    val = await queryAvgQuantity(.runningVerticalOscillation,
                                                 unit: .meterUnit(with: .centi), workout: workout)
                default:
                    val = nil
                }
                if let v = val, v > 0 {
                    results.append((date: workout.startDate, value: v))
                }
            }
            return results
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
        var isStale: Bool { Date().timeIntervalSince(cachedAt) > 86400 }  // 24h — historical metric data doesn't change intraday
    }

    private static let metricCacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MIMOMetrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func metricHistoryCacheURL(_ metric: TrendMetric, startDate: Date, usePounds: Bool) -> URL {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: startDate)
        let dateStr = String(format: "%04d%02d%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
        let suffix = (metric == .bodyMass && usePounds) ? "_lbs" : ""
        return Self.metricCacheDir.appendingPathComponent("metric_\(metric.rawValue)_\(dateStr)\(suffix).json")
    }

    private func loadMetricHistoryFromDisk(_ metric: TrendMetric, startDate: Date, usePounds: Bool) -> [(date: Date, value: Double)]? {
        let url = metricHistoryCacheURL(metric, startDate: startDate, usePounds: usePounds)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let file = try? JSONDecoder().decode(MetricHistoryCacheFile.self, from: data),
              !file.isStale else { return nil }
        return file.points.map { ($0.date, $0.value) }
    }

    /// 새 런 추가 시 호출 — 런 기반 메트릭(케이던스·파워·폼) 디스크 캐시를 삭제해 다음 쿼리 시 최신 데이터 반영
    func invalidateRunningMetricHistoryCache() {
        let runningMetrics: [TrendMetric] = [.cadence, .power, .groundContactTime, .strideLength, .verticalOscillation]
        let since = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        for metric in runningMetrics {
            let url = metricHistoryCacheURL(metric, startDate: since, usePounds: false)
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func saveMetricHistoryToDisk(_ points: [(date: Date, value: Double)], metric: TrendMetric, startDate: Date, usePounds: Bool) {
        let file = MetricHistoryCacheFile(
            points: points.map { MetricDataPoint(date: $0.date, value: $0.value) },
            cachedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: metricHistoryCacheURL(metric, startDate: startDate, usePounds: usePounds), options: .atomic)
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
            // Weather already stored, or no GPS to fetch it → return as-is
            if cached.weather != nil || firstCoordinate == nil { return cached }
            // Condition cached but weather missing and GPS available → fetch weather only
            if let w = await ConditionService.fetchWeather(date: activity.date, coordinate: firstCoordinate) {
                var updated = cached; updated.weather = w
                await ConditionCache.shared.cache(updated, for: activity.id)
                return updated
            }
            return cached
        }
        // Never fetched → weather + sleep + HRV in parallel
        async let weather = ConditionService.fetchWeather(date: activity.date, coordinate: firstCoordinate)
        async let sleep   = querySleepScore(nightBefore: activity.date)
        async let hrv     = queryHRVRecovery(nightBefore: activity.date)
        let result = ActivityCondition(weather: await weather, sleepScore: await sleep, hrvRecovery: await hrv)
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

        // Fetch tonight's samples and 14-day bedtime history concurrently
        async let sleepTask   = fetchSleepSamples(from: nightStart, to: nightEnd)
        async let historyTask = fetchBedtimeHistory(before: date, daysBack: 14)
        let (samples, bedtimeHistory) = await (sleepTask, historyTask)

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]
        let asleepSamples = samples.filter { asleepValues.contains($0.value) }
        let awakeSamples  = samples.filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }
        guard !asleepSamples.isEmpty else { return nil }

        // Union-merge with 5-min gap tolerance (eliminates duplicate-source overlap)
        let sorted = asleepSamples.map { ($0.startDate, $0.endDate) }.sorted { $0.0 < $1.0 }
        let gapTolerance: TimeInterval = 5 * 60
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
        let hours = main.hours
        guard hours > 0.5, hours <= 12.0 else { return nil }

        // Component 2 — consistency (max 30): bedtime deviation from 14-day average
        let consistencyPts = sleepConsistencyScore(currentBedtime: main.start, history: bedtimeHistory)

        // Component 3 — interruptions (max 20): awake events inside main block.
        // Union-merge awake samples first to deduplicate multiple sources (e.g. Watch + third-party
        // app each writing their own awake stages). Then count only events lasting ≥ 5 min — brief
        // arousals between sleep stages are physiologically normal and should not be penalised.
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
        let minAwakeDuration: TimeInterval = 5 * 60
        let awakeInBlock = mergedAwake.filter {
            $0.start >= main.start && $0.start < main.end &&
            $0.end.timeIntervalSince($0.start) >= minAwakeDuration
        }.count
        let interruptionPts = sleepInterruptionScore(awakeCount: awakeInBlock, hasWatchData: hasWatchData)

        let score = SleepScore.compute(durationHours: hours, consistencyPts: consistencyPts,
                                       interruptionPts: interruptionPts)
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
        return merged.compactMap { blk -> Date? in
            blk.end.timeIntervalSince(blk.start) / 3600 >= 3.0 ? blk.start : nil
        }
    }

    private func sleepInterruptionScore(awakeCount: Int, hasWatchData: Bool) -> Int {
        guard hasWatchData else { return 10 } // phone-only: unknown → neutral
        switch awakeCount {
        case 0:  return 20
        case 1:  return 16
        case 2:  return 12
        case 3:  return 7
        default: return 2
        }
    }

    private func sleepConsistencyScore(currentBedtime: Date, history: [Date]) -> Int {
        guard history.count >= 3 else { return 15 } // not enough history → neutral
        let cal = Calendar.current
        let toMins: (Date) -> Int = { d in
            var h = cal.component(.hour, from: d)
            let m = cal.component(.minute, from: d)
            if h < 6 { h += 24 } // AM bedtimes normalized past midnight
            return h * 60 + m
        }
        let historyMins = history.map(toMins)
        let avgMins  = historyMins.reduce(0, +) / historyMins.count
        let deviation = abs(toMins(currentBedtime) - avgMins)
        switch deviation {
        case ..<20:  return 30
        case ..<40:  return 25
        case ..<60:  return 18
        case ..<90:  return 10
        case ..<120: return 4
        default:     return 0
        }
    }
}
