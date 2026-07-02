import HealthKit

// MARK: - ECGWaveform
// Data source : HealthKit runningSpeed (→ sec/km) and heartRate via HealthKitManager.
// §7 compliance: normalization is intra-workout only — rawMin/rawMax bound this run.
//   1.0 = fastest/highest *this run*. No absolute benchmarks applied.

/// Identifies the HealthKit data type behind an ECGWaveform.
enum WaveformSource { case pace, heartRate }

/// Normalized pace or heart-rate time-series for the "심전도 시그니처" ECG share card.
///
/// `points` is always 100 values mapped to equal-width time buckets across the
/// workout. 1.0 = fastest pace / highest heart rate. Empty buckets (pause gaps)
/// are filled by nearest-neighbor interpolation so the waveform is continuous.
struct ECGWaveform {
    /// 100 normalized values, 0.0–1.0. 1.0 = fastest / highest.
    let points: [CGFloat]
    /// Index of the highest point (peak effort moment).
    let peakIndex: Int
    /// Original raw minimum value before normalization (sec/km for pace, bpm for HR).
    let rawMin: Double
    /// Original raw maximum value before normalization.
    let rawMax: Double
    /// Raw value at the peak index, before normalization (sec/km for pace, bpm for HR).
    let peakValue: Double
    /// Whether this waveform is sourced from pace or heart rate data.
    let source: WaveformSource

    // MARK: - Constants

    static let bucketCount = 100

    // MARK: - Pace (runningSpeed → inverted, fast = 1.0)

    /// Builds a waveform from the workout's per-second `runningSpeed` HealthKit
    /// samples. Speed is converted to pace (sec/km), then inverted so that the
    /// fastest moment maps to 1.0.
    ///
    /// The `runningSpeed` series is fetched via the existing
    /// `fetchWorkoutTimeSeries` path, which already applies the
    /// pause/resume `workoutEvents` exclusion logic.
    static func fromPace(activity: Activity, using manager: HealthKitManager) async -> ECGWaveform? {
        let speedSamples = await manager.fetchWorkoutTimeSeries(
            for: activity.id,
            identifier: .runningSpeed,
            unit: .meter().unitDivided(by: .second())
        )
        guard !speedSamples.isEmpty else { return nil }

        // Convert m/s → sec/km; discard stopped/noise samples (< 0.5 m/s ≈ 1.8 km/h).
        let paceSamples: [(offset: TimeInterval, value: Double)] = speedSamples.compactMap { s in
            guard s.value >= 0.5 else { return nil }
            return (offset: s.offset, value: 1000.0 / s.value)
        }
        guard !paceSamples.isEmpty else { return nil }

        guard let rawPoints = downsample(paceSamples, duration: activity.duration),
              rawPoints.count == bucketCount else { return nil }

        let rawMin = rawPoints.min() ?? 0     // lowest sec/km = fastest
        let rawMax = rawPoints.max() ?? 1     // highest sec/km = slowest
        guard rawMax - rawMin > 0.5 else { return nil }   // waveform too flat

        // Invert: fast pace (low sec/km) → 1.0; slow → 0.0
        let span = rawMax - rawMin
        let normalized = rawPoints.map { CGFloat(1.0 - ($0 - rawMin) / span) }
        let peakIndex  = normalized.indices.max(by: { normalized[$0] < normalized[$1] }) ?? 0
        let peakValue  = rawPoints[peakIndex]   // sec/km at fastest moment

        return ECGWaveform(points: normalized, peakIndex: peakIndex, rawMin: rawMin, rawMax: rawMax, peakValue: peakValue, source: .pace)
    }

    // MARK: - Heart rate (higher bpm = 1.0)

    /// Builds a waveform from the workout's `heartRate` HealthKit samples.
    /// Higher heart rate maps to 1.0 — no inversion.
    ///
    /// Uses the existing `fetchHRTimeSeries` path (same pause exclusion logic).
    static func fromHeartRate(activity: Activity, using manager: HealthKitManager) async -> ECGWaveform? {
        let hrSamples = await manager.fetchHRTimeSeries(for: activity.id)
        guard !hrSamples.isEmpty else { return nil }

        let doubleSamples = hrSamples.map { (offset: $0.offset, value: Double($0.bpm)) }

        guard let rawPoints = downsample(doubleSamples, duration: activity.duration),
              rawPoints.count == bucketCount else { return nil }

        let rawMin = rawPoints.min() ?? 0
        let rawMax = rawPoints.max() ?? 1
        guard rawMax - rawMin > 2 else { return nil }     // waveform too flat

        let span = rawMax - rawMin
        let normalized = rawPoints.map { CGFloat(($0 - rawMin) / span) }
        let peakIndex  = normalized.indices.max(by: { normalized[$0] < normalized[$1] }) ?? 0
        let peakValue  = rawPoints[peakIndex]   // bpm at highest moment

        return ECGWaveform(points: normalized, peakIndex: peakIndex, rawMin: rawMin, rawMax: rawMax, peakValue: peakValue, source: .heartRate)
    }

    // MARK: - Primary entry point: pace first, HR fallback, nil if both unavailable

    /// Tries pace first ("있는 것만 표시" principle); falls back to heart rate if
    /// `runningSpeed` data is not available (phone-only run without Apple Watch).
    static func build(for activity: Activity, using manager: HealthKitManager) async -> ECGWaveform? {
        if let ecg = await fromPace(activity: activity, using: manager) { return ecg }
        return await fromHeartRate(activity: activity, using: manager)
    }

    // MARK: - Downsampling

    /// Averages time-stamped samples into `bucketCount` equal-width buckets,
    /// then fills empty buckets via nearest-neighbor interpolation.
    ///
    /// Returns nil if the duration is zero or every sample falls outside [0, duration).
    private static func downsample(
        _ samples: [(offset: TimeInterval, value: Double)],
        duration: TimeInterval
    ) -> [Double]? {
        guard duration > 0, !samples.isEmpty else { return nil }

        let bucketWidth = duration / Double(bucketCount)
        var buckets = [[Double]](repeating: [], count: bucketCount)

        for s in samples {
            guard s.offset >= 0 else { continue }
            let idx = min(Int(s.offset / bucketWidth), bucketCount - 1)
            buckets[idx].append(s.value)
        }

        var result: [Double?] = buckets.map {
            $0.isEmpty ? nil : $0.reduce(0, +) / Double($0.count)
        }
        interpolateNil(&result)

        let filled = result.compactMap { $0 }
        return filled.count == bucketCount ? filled : nil
    }

    /// Forward then backward nearest-neighbor pass to fill nil gaps.
    private static func interpolateNil(_ values: inout [Double?]) {
        var last: Double? = nil
        for i in values.indices {
            if let v = values[i] { last = v }
            else if let l = last { values[i] = l }
        }
        var next: Double? = nil
        for i in values.indices.reversed() {
            if let v = values[i] { next = v }
            else if let n = next { values[i] = n }
        }
    }
}
