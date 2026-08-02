import Foundation
import HealthKit

/// 워크아웃 내부의 분 단위 (심박, 속도) 점.
struct MRSegment {
    let workoutStart: Date       // 어느 세션에서 나왔는지 (군집 보정에 쓴다)
    let elapsedMin: Double       // 세션 내 경과 시간
    let hr: Double
    let speedMPerMin: Double
    let tempC: Double?
}

extension MRHealthKit {

    /// 워크아웃 하나를 1분 구간으로 쪼개 (심박, 속도)를 뽑는다.
    ///
    /// ⚠ 왜 1분인가: 심박은 속도 변화를 **20~40초 늦게** 따라간다.
    ///   더 잘게 쪼개면 그 지연이 노이즈로 들어온다.
    ///   1분은 지연을 흡수하면서도 인터벌 구간을 구분할 만큼 짧다.
    func fetchSegments(for w: HKWorkout) async throws -> [MRSegment] {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let dType  = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        else { return [] }

        let pred = HKQuery.predicateForObjects(from: w)
        let interval = DateComponents(minute: 1)
        let hrUnit = HKUnit.count().unitDivided(by: .minute())

        func collect(_ type: HKQuantityType, _ opt: HKStatisticsOptions)
            async throws -> [(Date, HKStatistics)] {
            try await withCheckedThrowingContinuation { cont in
                let q = HKStatisticsCollectionQuery(
                    quantityType: type, quantitySamplePredicate: pred,
                    options: opt, anchorDate: w.startDate, intervalComponents: interval)
                q.initialResultsHandler = { _, res, err in
                    if let err { cont.resume(throwing: err); return }
                    var out: [(Date, HKStatistics)] = []
                    res?.enumerateStatistics(from: w.startDate, to: w.endDate) {
                        stat, _ in out.append((stat.startDate, stat))
                    }
                    cont.resume(returning: out)
                }
                store.execute(q)
            }
        }

        let hrStats = try await collect(hrType, .discreteAverage)
        let dStats  = try await collect(dType,  .cumulativeSum)
        let dMap = Dictionary(uniqueKeysWithValues: dStats.map { ($0.0, $0.1) })

        var temp: Double? = nil
        if let q = w.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity {
            temp = q.doubleValue(for: .degreeCelsius())
        }

        var out: [MRSegment] = []
        for (start, hs) in hrStats {
            guard let hr = hs.averageQuantity()?.doubleValue(for: hrUnit),
                  let ds = dMap[start],
                  let meters = ds.sumQuantity()?.doubleValue(for: .meter())
            else { continue }
            // 1분 구간이므로 m/min = m
            guard meters > 100, meters < 400, hr > 60, hr < 220 else { continue }
            out.append(MRSegment(workoutStart: w.startDate,
                                 elapsedMin: start.timeIntervalSince(w.startDate) / 60,
                                 hr: hr, speedMPerMin: meters, tempC: temp))
        }
        // 처음 3분은 버린다 — 심박이 아직 정상 상태에 도달하지 않았다
        return out.filter { $0.elapsedMin >= 3 }
    }
}
