import Foundation
import HealthKit
import WorkoutKit

/// HealthKit 접근을 한 곳에 모은다. 엔진의 나머지는 HealthKit을 모른다.
struct MRHealthKit {

    let store = HKHealthStore()

    // MARK: 권한

    static var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        let q: [HKQuantityTypeIdentifier] = [
            .heartRate, .restingHeartRate, .heartRateVariabilitySDNN,
            .vo2Max, .stepCount, .distanceWalkingRunning,
            .activeEnergyBurned,
            .runningPower, .runningSpeed, .runningStrideLength,
            .runningVerticalOscillation, .runningGroundContactTime,
            .bodyMass, .bodyFatPercentage,
        ]
        q.forEach { if let t = HKQuantityType.quantityType(forIdentifier: $0) { s.insert(t) } }
        let c: [HKCharacteristicTypeIdentifier] = [.dateOfBirth, .biologicalSex]
        c.forEach { if let t = HKCharacteristicType.characteristicType(forIdentifier: $0) { s.insert(t) } }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        return s
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "MRHealthKit", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "이 기기는 건강 데이터를 지원하지 않습니다."])
        }
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    // MARK: 워크아웃

    /// 러닝 HKWorkout 원본 배열을 시간 오름차순으로 가져온다.
    /// `since`가 있으면 해당 날짜 이후만 읽는다.
    func fetchRawRunsSince(_ since: Date? = nil) async throws -> [HKWorkout] {
        var preds: [NSPredicate] = [HKQuery.predicateForWorkouts(with: .running)]
        if let since {
            preds.append(HKQuery.predicateForSamples(withStart: since, end: nil,
                                                     options: .strictStartDate))
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(),
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
    }

    /// 증분 fetch. 캐시된 워크아웃은 재사용하고 새 것만 HealthKit에서 읽는다.
    ///
    /// isInterval 판정(WorkoutKit 쿼리 1회/건)도 새 워크아웃만 수행한다.
    /// 두 번째 실행부터 "새로 읽은 것 0건" 로그가 나와야 정상이다.
    func fetchRunsIncremental() async throws -> [MRWorkout] {
        let cache = MRWorkoutCacheStore.load()
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())

        // newestStart 이미 캐시됨 → 1초 이후부터만 새로 읽는다
        let since: Date? = cache.map {
            Date(timeIntervalSince1970: $0.newestStart.timeIntervalSince1970 + 1)
        }

        let t0 = CFAbsoluteTimeGetCurrent()

        // 증분 fetch + 오늘 실시간 fetch 병렬 실행
        // 오늘 것은 항상 HealthKit에서 재조회해 삭제된 워크아웃을 감지한다
        async let freshTask   = fetchRawRunsSince(since)
        async let todayTask   = fetchRawRunsSince(todayStart)
        let fresh    = try await freshTask
        let todayHK  = (try? await todayTask) ?? []

        let tHKQuery = CFAbsoluteTimeGetCurrent() - t0

        #if DEBUG
        print("[캐시] 워크아웃 캐시 \(cache == nil ? "없음" : "있음(\(cache!.runs.count)건, ~\(mrYMD(cache!.newestStart)))") · 증분 \(fresh.count)건 · 오늘 HK \(todayHK.count)건")
        #endif

        // 오늘 이전 캐시 보존 + 오늘 것은 HK 실시간값으로 교체
        let baseRuns  = (cache?.runs ?? []).filter { !cal.isDate($0.start, inSameDayAs: Date()) }
        // 증분 중 오늘 이전 것만 추가 (오늘 이후는 todayHK로 대체)
        let freshOldHK = fresh.filter { !cal.isDate($0.startDate, inSameDayAs: Date()) }

        // isInterval 판정은 새 워크아웃만
        async let freshOldMRTask = convertToMRWorkouts(freshOldHK)
        async let todayMRTask    = convertToMRWorkouts(todayHK)
        let freshOldMR = await freshOldMRTask
        let todayMR    = await todayMRTask

        let tConvert = CFAbsoluteTimeGetCurrent() - t0 - tHKQuery

        let merged = (baseRuns + freshOldMR + todayMR).sorted { $0.start < $1.start }

        if let newest = merged.last?.start {
            MRWorkoutCacheStore.save(MRWorkoutCache(newestStart: newest, runs: merged))
        }

        #if DEBUG
        let tTotal = CFAbsoluteTimeGetCurrent() - t0
        let tRest = tTotal - tHKQuery - tConvert
        print("[⏱ fetchRunsIncremental] 증분 \(fresh.count)건 · 합계 \(String(format: "%.2f", tTotal))s (HK쿼리 \(String(format: "%.2f", tHKQuery))s · 변환 \(String(format: "%.2f", tConvert))s · 나머지 \(String(format: "%.2f", tRest))s)")
        #endif

        return merged
    }

    /// 하위 호환 — 전체 fetch (원본이 필요한 경우)
    func fetchRawRuns() async throws -> [HKWorkout] {
        try await fetchRawRunsSince(nil)
    }

    /// HKWorkout 배열을 MRWorkout으로 변환한다 (WorkoutKit 인터벌 감지 포함).
    func convertToMRWorkouts(_ workouts: [HKWorkout]) async -> [MRWorkout] {
        let flags: [Bool] = await withTaskGroup(of: (Int, Bool).self) { group in
            for (i, w) in workouts.enumerated() {
                group.addTask { (i, await Self.isIntervalWorkout(w)) }
            }
            var result = Array(repeating: false, count: workouts.count)
            for await (i, flag) in group { result[i] = flag }
            return result
        }
        return zip(workouts, flags).map { Self.convert($0, isInterval: $1) }
    }

    /// HKWorkout 원본과 MRWorkout을 쌍으로 돌려준다.
    ///
    /// 세그먼트(분 단위 심박·거리)를 나중에 읽으려면 HKWorkout 원본이 필요하다.
    /// `fetchRuns()`는 이 메서드에서 `.map(\.mr)`한다.
    func fetchRunsWithSource() async throws -> [(mr: MRWorkout, hk: HKWorkout)] {
        let workouts = try await fetchRawRuns()
        let flags: [Bool] = await withTaskGroup(of: (Int, Bool).self) { group in
            for (i, w) in workouts.enumerated() {
                group.addTask { (i, await Self.isIntervalWorkout(w)) }
            }
            var result = Array(repeating: false, count: workouts.count)
            for await (i, flag) in group { result[i] = flag }
            return result
        }
        return zip(workouts, flags).map { (Self.convert($0, isInterval: $1), $0) }
    }

    /// 러닝 워크아웃 전체를 시간 오름차순으로 가져온다.
    func fetchRuns() async throws -> [MRWorkout] {
        try await fetchRunsWithSource().map(\.mr)
    }

    /// 워크아웃이 구조화된 인터벌 세션인지 판정한다.
    ///
    /// HealthKitManager.queryIntervalSegments + WorkoutTypeClassifier.isPlanInterval과
    /// 동일한 기준:  WorkoutKit 커스텀 플랜에 운동(.work) 구간 ≥2개 + 회복(.recovery) ≥1개.
    ///
    /// ⚠ 앱의 나머지 화면도 이 기준으로 "인터벌"을 표시하므로,
    ///   엔진이 다른 기준을 쓰면 화면과 내부가 어긋난다.
    private static func isIntervalWorkout(_ w: HKWorkout) async -> Bool {
        guard let plan = try? await w.workoutPlan else { return false }
        guard case .custom(let custom) = plan.workout else { return false }
        var workCount = 0
        var hasRecovery = false
        for block in custom.blocks {
            for step in block.steps {
                switch step.purpose {
                case .work:     workCount += 1
                case .recovery: hasRecovery = true
                @unknown default: break
                }
            }
        }
        return workCount >= 2 && hasRecovery
    }

    /// HKWorkout → MRWorkout
    ///
    /// ⚠ iOS 16부터 workout.totalDistance / totalEnergyBurned가 deprecated다.
    ///   반드시 statistics(for:)를 써야 한다.
    static func convert(_ w: HKWorkout, isInterval: Bool = false) -> MRWorkout {
        let hrUnit = HKUnit.count().unitDivided(by: .minute())
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!

        let distM = w.statistics(for: distType)?
            .sumQuantity()?.doubleValue(for: .meter())
        let hrStats = w.statistics(for: hrType)
        let hrAvg = hrStats?.averageQuantity()?.doubleValue(for: hrUnit)
        let hrMax = hrStats?.maximumQuantity()?.doubleValue(for: hrUnit)

        var temp: Double? = nil
        if let q = w.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity {
            temp = q.doubleValue(for: .degreeCelsius())
        }

        // ⚠ 습도가 100배로 저장되는 경우가 있다 (8000% 같은 값).
        var hum: Double? = nil
        if let q = w.metadata?[HKMetadataKeyWeatherHumidity] as? HKQuantity {
            var h = q.doubleValue(for: .percent()) * 100.0
            while h > 100 { h /= 100.0 }
            hum = h
        }

        let indoor = (w.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) ?? false

        return MRWorkout(
            start: w.startDate,
            durationMin: w.duration / 60.0,
            distanceKm: distM.map { $0 / 1000.0 },
            hrAvg: hrAvg,
            hrMax: hrMax,
            tempC: temp,
            humidity: hum,
            indoor: indoor,
            isInterval: isInterval
        )
    }

    // MARK: 안정시심박

    // 건강 모드의 작년 비교에 400일이 필요하고, 그 이상은 쓰지 않는다.
    func fetchRestingHR(days: Int = 400) async throws -> [(date: Date, value: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)
        else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let from = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let pred = HKQuery.predicateForSamples(withStart: from, end: nil, options: .strictStartDate)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, s, e in
                if let e { cont.resume(throwing: e); return }
                cont.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }

    // MARK: 수면 HRV

    /// 수면 HRV(SDNN) 원본 샘플. 밤 묶기는 `mrHRVNightMedians`가 한다.
    /// 60일이면 7일 창 + 4주 기준선(34일)에 여유가 있다. 그 이상은 쓰지 않는다.
    func fetchSleepHRV(days: Int = 60) async throws -> [(Date, Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        else { return [] }
        let unit = HKUnit.secondUnit(with: .milli)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let from = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let pred = HKQuery.predicateForSamples(withStart: from, end: nil, options: .strictStartDate)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, s, e in
                if let e { cont.resume(throwing: e); return }
                cont.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }

    // MARK: 일별 걸음 수

    /// 일별 걸음 수. 공백 원인 분류(`mrDetectGaps`)와 firstDataDate 산출에 쓴다.
    ///
    /// firstDataDate = `stepsDaily.keys.min()` — 러닝 시작 전에 기기가 이미 있었는지
    /// 판별하는 가장 쉬운 방법이다.
    func fetchDailySteps(from: Date, to: Date = Date()) async throws -> [Date: Double] {
        guard let t = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [:] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: from)
        let dayCount = max(1, cal.dateComponents([.day], from: start, to: to).day ?? 999)

        // 구간 ≤ 7일: HKStatisticsQuery 날짜별 호출.
        //   HKStatisticsCollectionQuery는 predicate를 걸어도 초기화 비용이 수 초다.
        //   캐시 히트 후 이틀치라면 단순 쿼리 2회가 훨씬 빠르다.
        if dayCount <= 7 {
            var m: [Date: Double] = [:]
            var day = start
            while day < to {
                let nextDay = cal.date(byAdding: .day, value: 1, to: day)!
                let pred = HKQuery.predicateForSamples(withStart: day, end: nextDay,
                                                       options: .strictStartDate)
                let thisDay = day
                let v: Double = try await withCheckedThrowingContinuation { cont in
                    let q = HKStatisticsQuery(quantityType: t, quantitySamplePredicate: pred,
                                              options: .cumulativeSum) { _, stats, err in
                        if let err { cont.resume(throwing: err); return }
                        cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                    }
                    store.execute(q)
                }
                if v > 0 { m[thisDay] = v }
                day = nextDay
            }
            return m
        }

        // 구간 > 7일: HKStatisticsCollectionQuery
        // ⚠ quantitySamplePredicate: nil이면 HealthKit이 전체 이력을 스캔한다.
        //   enumerateStatistics(from:to:)는 출력만 자를 뿐 쿼리 범위를 줄이지 않는다.
        //   predicate로 범위를 잘라야 한다.
        let samplePred = HKQuery.predicateForSamples(withStart: start, end: to,
                                                     options: .strictStartDate)
        let stats: [(Date, HKStatistics)] = try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: t, quantitySamplePredicate: samplePred,
                options: .cumulativeSum, anchorDate: start,
                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, res, err in
                if let err { cont.resume(throwing: err); return }
                var out: [(Date, HKStatistics)] = []
                res?.enumerateStatistics(from: start, to: to) { stat, _ in out.append((stat.startDate, stat)) }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
        var m: [Date: Double] = [:]
        for (d, s) in stats {
            if let v = s.sumQuantity()?.doubleValue(for: .count()), v > 0 {
                m[cal.startOfDay(for: d)] = v
            }
        }
        return m
    }

    /// 증분 걸음 수 fetch. 어제까지의 확정값은 캐시에서, 오늘은 항상 새로 읽는다.
    ///
    /// 같은 날 두 번째 실행부터는 HK 쿼리를 생략한다.
    /// 단, 어제 값이 0(미동기화)이면 재시도한다.
    func fetchDailyStepsIncremental(floor: Date) async throws -> [Date: Double] {
        let cal = Calendar.current
        let cache = MRStepsCacheStore.load()

        // ★ 오늘 이미 읽었고 어제 값도 있으면 HK 쿼리 완전 생략
        if let cache {
            let today = cal.startOfDay(for: Date())
            let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
            let yesterdayEpoch = mrEpochDay(yesterday)
            if cache.lastDay == today && (cache.daily[yesterdayEpoch] ?? 0) > 0 {
                var out: [Date: Double] = [:]
                out.reserveCapacity(cache.daily.count)
                for (k, v) in cache.daily { out[mrFromEpochDay(k)] = v }
                return out
            }
        }

        // 캐시에서 하루 전부터 다시 읽는다 (오늘은 아직 확정 전이므로 재확인)
        let freshFrom = cache.map {
            cal.date(byAdding: .day, value: -1, to: $0.lastDay)!
        } ?? floor

        let fresh = try await fetchDailySteps(from: freshFrom)
        #if DEBUG
        print("[캐시] 걸음 캐시 \(cache == nil ? "없음" : "있음(\(cache!.daily.count)일)") · 새로 읽은 \(fresh.count)일")
        #endif

        // 캐시(Int 키) + 새 데이터 병합 — DateFormatter 없음
        var merged: [Int: Double] = cache?.daily ?? [:]
        for (k, v) in fresh { merged[mrEpochDay(k)] = v }

        MRStepsCacheStore.save(MRStepsCache(
            lastDay: cal.startOfDay(for: Date()),
            daily: merged))

        // 반환값은 [Date: Double] — mrFromEpochDay는 startOfDay를 돌려주므로
        // mrDetectGaps / mrHealthMetrics의 startOfDay 비교와 일치한다
        var out: [Date: Double] = [:]
        out.reserveCapacity(merged.count)
        for (k, v) in merged { out[mrFromEpochDay(k)] = v }
        return out
    }

    // MARK: VO2max

    func fetchVO2Max() async throws -> [(date: Date, value: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max)
        else { return [] }
        let unit = HKUnit(from: "ml/kg*min")
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, s, e in
                if let e { cont.resume(throwing: e); return }
                cont.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }

    // MARK: 생년월일 / 성별

    func dateOfBirth() -> Date? {
        (try? store.dateOfBirthComponents())?.date
    }

    func biologicalSex() -> HKBiologicalSex? {
        (try? store.biologicalSex())?.biologicalSex
    }
}
