import Foundation
import HealthKit
import WorkoutKit
import CoreLocation
import Observation

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

    private let store = HKHealthStore()
    @ObservationIgnored private var workoutCache: [UUID: HKWorkout] = [:]

    /// True when any loaded workout originates from Garmin Connect.
    var hasGarminSource: Bool {
        workoutCache.values.contains {
            $0.sourceRevision.source.bundleIdentifier.lowercased().contains("garmin")
        }
    }

    enum AuthStatus {
        case notDetermined, authorized, denied
    }

    private var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.heartRate),
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
    }

    // MARK: - Authorization

    func checkAuthorizationStatus() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationStatus = .denied
            return
        }
        guard UserDefaults.standard.bool(forKey: "hkAuthorizationRequested") else { return }
        // Re-request to cover any types added after initial auth — HealthKit only prompts for new/undecided types.
        try? await store.requestAuthorization(toShare: [], read: readTypes)
        authorizationStatus = .authorized
        await fetchActivities()
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationStatus = .denied
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
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
        isLoading = true
        defer { isLoading = false }
        readBiologicalCharacteristics()
        do {
            let workouts = try await queryWorkouts()

            // ── Phase 1: populate immediately from workout's embedded statistics ──────
            // HKWorkout.statistics(for:) reads pre-aggregated data stored inside the
            // workout record — no extra HealthKit round-trips needed.
            activities = workouts.map { buildSummary(from: $0) }

            // ── Phase 2: enrich the most-recent 50 with calories + heart rate ─────────
            // These extra stat queries are run on the recent slice only, so older
            // history (used by growth/insight) stays fast with summary-only data.
            let enrichCount = min(50, workouts.count)
            for i in 0..<enrichCount {
                activities[i] = await enrich(activities[i], workout: workouts[i])
            }

            // ── Phase 3: compute user level from all activities ───────────────────────
            userLevel = LevelEngine.compute(
                activities: activities,
                dateOfBirth: userDateOfBirth,
                isMale: userIsMale
            )
        } catch {
            self.error = error
        }
    }

    // MARK: - Detail (on demand)

    func fetchDetail(for activityID: UUID) async -> ActivityDetail? {
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
            print("[WorkoutType] \(workoutType.koreanLabel) — \(workout.workoutActivities.count) activities, \(splits.count) splits")

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
                                                    unit: HKUnit.count().unitDivided(by: .minute()),
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

    // MARK: - Workout query — date range, no count limit

    private func queryWorkouts() async throws -> [HKWorkout] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? .distantPast
        let datePred = HKQuery.predicateForSamples(
            withStart: cutoff, end: nil, options: .strictStartDate
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
            .sumQuantity()?.doubleValue(for: .meter()) ?? 0
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

    // MARK: - Route

    private func fetchRouteLocations(for workout: HKWorkout) async -> [CLLocation] {
        let routes = await fetchWorkoutRoutes(for: workout)
        print("[Route] \(routes.count) route(s) for workout \(workout.uuid)")
        guard let route = routes.first else { return [] }

        return await withCheckedContinuation { continuation in
            let batch = LocationBatch()
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error { print("[Route] Query error: \(error.localizedDescription)") }
                if let locations { batch.locations.append(contentsOf: locations) }
                if done {
                    print("[Route] Done — \(batch.locations.count) coordinates")
                    continuation.resume(returning: batch.locations)
                }
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
            ) { _, samples, error in
                if let error { print("[Route] Route sample query error: \(error.localizedDescription)") }
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
        guard let workout = workoutCache[workoutID] else { return [] }
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return samples.map { sample in
            let bpm = Int(sample.quantity.doubleValue(for: unit).rounded())
            let offset = sample.startDate.timeIntervalSince(workout.startDate)
            return (offset: offset, bpm: bpm)
        }
    }

    // MARK: - Workout time-series (for share card panels)

    func fetchWorkoutTimeSeries(for workoutID: UUID, identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> [(offset: TimeInterval, value: Double)] {
        guard let workout = workoutCache[workoutID] else { return [] }
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(identifier),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { s in
            (offset: s.startDate.timeIntervalSince(workout.startDate),
             value: s.quantity.doubleValue(for: unit))
        }
    }

    func fetchCadenceTimeSeries(for workoutID: UUID) async -> [(offset: TimeInterval, value: Double)] {
        guard let workout = workoutCache[workoutID] else { return [] }
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.stepCount),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.compactMap { s in
            let dur = s.endDate.timeIntervalSince(s.startDate)
            guard dur > 0 else { return nil }
            let steps = s.quantity.doubleValue(for: .count())
            return (offset: s.startDate.timeIntervalSince(workout.startDate),
                    value: (steps / dur) * 60)
        }
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
        guard let bpm = await queryAvgQuantity(
            .heartRate, unit: .count().unitDivided(by: .minute()), workout: workout
        ) else { return nil }
        return Int(bpm.rounded())
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
        let hrSamples = (try? await hrDesc.result(for: store)) ?? []

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
            result.append(SplitData(
                id: crossing.km, distanceM: 1000, duration: dur,
                avgHeartRate: splitAvgHR(from: prevDate, to: crossing.date, samples: hrSamples)
            ))
            prevDate = crossing.date
        }
        // Last partial split (≥ 100 m)
        let lastKm = crossings.last?.km ?? 0
        let remaining = cum - Double(lastKm) * 1000
        if remaining >= 100, let lastDate = timeline.last?.date {
            let dur = lastDate.timeIntervalSince(prevDate)
            if dur > 1 {
                result.append(SplitData(
                    id: lastKm + 1, distanceM: remaining, duration: dur,
                    avgHeartRate: splitAvgHR(from: prevDate, to: lastDate, samples: hrSamples)
                ))
            }
        }
        return result
    }

    private func splitAvgHR(from start: Date, to end: Date, samples: [HKQuantitySample]) -> Int? {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let relevant = samples.filter { $0.startDate >= start && $0.startDate < end }
        guard !relevant.isEmpty else { return nil }
        let sum = relevant.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
        return Int((sum / Double(relevant.count)).rounded())
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
        let unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo)
            .unitMultiplied(by: HKUnit(from: "min")))
        return sample.quantity.doubleValue(for: unit)
    }

    // MARK: - HR Zones

    private func queryHRZones(workout: HKWorkout) async -> [HRZoneData] {
        let pred = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let desc = HKSampleQueryDescriptor(
            predicates: [pred],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)]
        )
        guard let samples = try? await desc.result(for: store), samples.count >= 5 else { return [] }

        let maxHR = Double(estimatedMaxHR())
        let unit = HKUnit.count().unitDivided(by: .minute())
        let zoneDefs: [(name: String, lo: Double, hi: Double)] = [
            ("Z1 웜업",   0.50, 0.60),
            ("Z2 회복",   0.60, 0.70),
            ("Z3 유산소", 0.70, 0.80),
            ("Z4 임계",   0.80, 0.90),
            ("Z5 최대",   0.90, 1.01),
        ]
        var zoneSecs = [Double](repeating: 0, count: 5)

        for i in 0..<samples.count {
            let bpm = samples[i].quantity.doubleValue(for: unit)
            let frac = bpm / maxHR
            let next = i + 1 < samples.count ? samples[i + 1].startDate : workout.endDate
            let gap = min(60, max(0, next.timeIntervalSince(samples[i].startDate)))
            for (z, def) in zoneDefs.enumerated() {
                if frac >= def.lo && frac < def.hi { zoneSecs[z] += gap; break }
            }
        }

        let total = zoneSecs.reduce(0, +)
        guard total > 0 else { return [] }
        return zoneDefs.enumerated().compactMap { z, def in
            guard zoneSecs[z] > 0 else { return nil }
            return HRZoneData(
                id: z + 1, name: def.name,
                minBPM: Int(maxHR * def.lo),
                maxBPM: z == 4 ? Int(maxHR) : Int(maxHR * def.hi),
                seconds: zoneSecs[z],
                fraction: zoneSecs[z] / total
            )
        }
    }

    private func estimatedMaxHR() -> Int {
        guard let dob = try? store.dateOfBirthComponents(),
              let year = dob.year, year > 1900 else { return 190 }
        let age = Calendar.current.component(.year, from: Date()) - year
        return max(150, 220 - age)
    }

    // MARK: - Interval segments (WorkoutKit plan composition)

    /// Reads the WorkoutKit plan attached to the workout, maps each planned step to a
    /// workoutActivity, and returns labelled IntervalSegments.  Returns [] when:
    /// • no plan is stored on the workout
    /// • the plan is not a CustomWorkout
    /// • the activity count doesn't match the flattened step count
    private func queryIntervalSegments(workout: HKWorkout) async -> [IntervalSegment] {
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        print("[Interval] ── \(tf.string(from: workout.startDate)) ──")
        print("[Interval] workoutActivities: \(workout.workoutActivities.count)")

        guard let plan = try? await workout.workoutPlan else {
            print("[Interval] No workout plan")
            return []
        }

        guard case .custom(let custom) = plan.workout else {
            print("[Interval] Plan is not CustomWorkout")
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

        print("[Interval] Plan steps: \(flatLabels.count)  workoutActivities: \(workout.workoutActivities.count)")

        guard workout.workoutActivities.count == flatLabels.count else {
            print("[Interval] Count mismatch — hiding interval section")
            return []
        }

        let hrUnit = HKUnit.count().unitDivided(by: .minute())
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

            var paceStr = "—"
            if let d = distM, d > 0, activity.duration > 0 {
                let sPerKm = activity.duration / (d / 1000)
                paceStr = String(format: "%d'%02d\"/km", Int(sPerKm) / 60, Int(sPerKm) % 60)
            }
            print(String(format: "[Interval] #%d (%@)  dist:%.0fm  pace:%@  hr:%@",
                         i + 1, labelPair.label, distM ?? 0, paceStr,
                         hr.map { "\($0)bpm" } ?? "—"))

            result.append(IntervalSegment(
                id: i + 1,
                startDate: activity.startDate,
                endDate: activity.endDate ?? workout.endDate,
                distanceM: distM,
                avgHeartRate: hr,
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
        switch metric {
        case .vo2Max:
            return await fetchVO2MaxHistory(from: startDate)
        case .bodyMass:
            let unit: HKUnit = usePounds ? HKUnit(from: "lb") : .gramUnit(with: .kilo)
            return await fetchQuantitySampleHistory(.bodyMass, from: startDate, unit: unit)
        case .bodyFatPercentage:
            let raw = await fetchQuantitySampleHistory(.bodyFatPercentage, from: startDate, unit: .percent())
            return raw.map { ($0.date, $0.value) }
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
        let unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo)
            .unitMultiplied(by: HKUnit(from: "min")))
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }

    // MARK: - Condition (weather + sleep)

    func fetchCondition(for activity: Activity, firstCoordinate: CLLocationCoordinate2D?) async -> ActivityCondition {
        let weather = await ConditionService.fetchWeather(date: activity.date, coordinate: firstCoordinate)
        let sleep   = await querySleepScore(nightBefore: activity.date)
        return ActivityCondition(weather: weather, sleepScore: sleep)
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
        let sourceCount   = Set(samples.map { $0.sourceRevision.source.bundleIdentifier }).count
        print("[Sleep] 쿼리: 전체 \(samples.count)개, asleep \(asleepSamples.count)개, awake \(awakeSamples.count)개, 소스 \(sourceCount)개")
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
        guard let main = candidates.max(by: { $0.hours < $1.hours }) else {
            print("[Sleep] 런 전 수면 블록 없음"); return nil
        }
        let hours = main.hours
        guard hours > 0.5, hours <= 12.0 else {
            print("[Sleep] 비정상값 \(String(format:"%.1fh", hours)) → 표시 보류"); return nil
        }

        // Component 1 — duration (max 50)
        let durPts = SleepScore.durationScore(hours: hours)

        // Component 2 — consistency (max 30): bedtime deviation from 14-day average
        let consistencyPts = sleepConsistencyScore(currentBedtime: main.start, history: bedtimeHistory)

        // Component 3 — interruptions (max 20): awake samples inside main block
        let hasWatchData = asleepSamples.contains {
            $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
            $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
            $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
        }
        let awakeInBlock = awakeSamples.filter {
            $0.startDate >= main.start && $0.startDate < main.end
        }.count
        let interruptionPts = sleepInterruptionScore(awakeCount: awakeInBlock, hasWatchData: hasWatchData)

        let score = SleepScore.compute(durationHours: hours, consistencyPts: consistencyPts,
                                       interruptionPts: interruptionPts)
        print("[Sleep] 주 수면 \(String(format:"%.1fh", hours)), 시간\(durPts)+일관성\(consistencyPts)+중단\(interruptionPts) = \(score.score) \(score.grade.label)")
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
