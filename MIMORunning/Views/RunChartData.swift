import SwiftUI

// MARK: - RunChartLayer

enum RunChartLayer: String, CaseIterable, Identifiable {
    case heartRate    = "심박"
    case pace         = "페이스"
    case cadence      = "케이던스"
    case elevation    = "고도"
    case power        = "파워"
    case strideLength = "보폭"
    case verticalOsc  = "진폭"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .heartRate:    return Theme.heartRate
        case .pace:         return Theme.pace
        case .cadence:      return Theme.cadence
        case .elevation:    return Theme.elevation
        case .power:        return Theme.power
        case .strideLength: return Theme.strideLength
        case .verticalOsc:  return Theme.verticalOsc
        }
    }

    enum DrawStyle {
        case line(width: CGFloat)
        case bars
        case fill
    }

    var drawStyle: DrawStyle {
        switch self {
        case .heartRate:    return .line(width: 1.6)
        case .cadence:      return .line(width: 1.1)
        case .power:        return .line(width: 1.1)
        case .strideLength: return .line(width: 1.0)
        case .verticalOsc:  return .line(width: 1.0)
        case .pace:         return .bars
        case .elevation:    return .fill
        }
    }

    // Visual hierarchy — higher priority layers are more opaque
    var opacity: Double {
        switch self {
        case .heartRate:    return 1.00
        case .cadence:      return 0.75
        case .power:        return 0.65
        case .strideLength: return 0.60
        case .verticalOsc:  return 0.60
        case .pace:         return 0.20
        case .elevation:    return 0.10
        }
    }

    // Vertical band (0 = top, 1 = bottom of chart).
    // norm mapped: t = top + (1 - norm) * (bottom - top)
    var band: (top: Double, bottom: Double) {
        switch self {
        case .heartRate:    return (0.06, 0.42)
        case .cadence:      return (0.48, 0.62)
        case .strideLength: return (0.64, 0.74)
        case .verticalOsc:  return (0.76, 0.86)
        case .power:        return (0.88, 0.96)
        case .pace:         return (0.00, 1.00)
        case .elevation:    return (0.86, 1.00)
        }
    }

    var unit: String {
        switch self {
        case .heartRate:    return "bpm"
        case .pace:         return "/km"
        case .cadence:      return "spm"
        case .elevation:    return "m"
        case .power:        return "W"
        case .strideLength: return "m"
        case .verticalOsc:  return "cm"
        }
    }

    var shortLabel: String { rawValue }
}

extension RunChartLayer {
    func formatted(_ value: Double) -> String {
        switch self {
        case .pace:
            let total = Int(value.rounded())
            return "\(total / 60)'\(String(format: "%02d", total % 60))\""
        case .heartRate, .cadence, .power, .elevation:
            return "\(Int(value.rounded()))"
        case .strideLength:
            return String(format: "%.2f", value)
        case .verticalOsc:
            return String(format: "%.1f", value)
        }
    }
}

// MARK: - RunChartPoint

struct RunChartPoint {
    let km: Double
    let value: Double
    /// 0–1 normalized within display range (clamped + smoothed). Pace inverted (faster = taller bar).
    let norm: Double
}

// MARK: - RunChartSeries

struct RunChartSeries {
    let layer: RunChartLayer
    let points: [RunChartPoint]
    /// Statistics from original (un-smoothed, un-clamped) values.
    let minValue: Double
    let maxValue: Double
    let avgValue: Double
    /// Index of fastest split. Pace layer only.
    let minIndex: Int?
    /// Index of slowest split. Pace layer only.
    let maxIndex: Int?
    /// Last smoothed value — used for right-side end-point label.
    let lastValue: Double

    init(
        layer: RunChartLayer,
        points: [RunChartPoint],
        minValue: Double,
        maxValue: Double,
        avgValue: Double,
        minIndex: Int? = nil,
        maxIndex: Int? = nil,
        lastValue: Double = 0
    ) {
        self.layer     = layer
        self.points    = points
        self.minValue  = minValue
        self.maxValue  = maxValue
        self.avgValue  = avgValue
        self.minIndex  = minIndex
        self.maxIndex  = maxIndex
        self.lastValue = lastValue
    }

    var isEmpty: Bool { points.count < 2 }
}

// MARK: - RunChartData

struct RunChartData {
    let totalKm: Double
    let series: [RunChartLayer: RunChartSeries]
    let hrZoneBands: [(zone: Int, lowerBPM: Int, upperBPM: Int)]
    let hrMin: Double
    let hrMax: Double
    let availableLayers: [RunChartLayer]
    let workSegments: [(startKm: Double, endKm: Double)]
    let fadeStartKm: Double?

    init(
        totalKm: Double,
        series: [RunChartLayer: RunChartSeries],
        hrZoneBands: [(zone: Int, lowerBPM: Int, upperBPM: Int)],
        hrMin: Double,
        hrMax: Double,
        availableLayers: [RunChartLayer],
        workSegments: [(startKm: Double, endKm: Double)] = [],
        fadeStartKm: Double? = nil
    ) {
        self.totalKm         = totalKm
        self.series          = series
        self.hrZoneBands     = hrZoneBands
        self.hrMin           = hrMin
        self.hrMax           = hrMax
        self.availableLayers = availableLayers
        self.workSegments    = workSegments
        self.fadeStartKm     = fadeStartKm
    }

    static let empty = RunChartData(
        totalKm: 0,
        series: [:],
        hrZoneBands: [],
        hrMin: 0,
        hrMax: 220,
        availableLayers: []
    )
}

// MARK: - RunChartBuilder

@MainActor
enum RunChartBuilder {

    // Clamp strategy for display-only outlier removal (stats always use original values)
    private enum ClampMode {
        case percentile(lo: Double, hi: Double)
        case hard(min: Double, max: Double)
    }

    static func build(
        activity: Activity,
        detail: ActivityDetail?,
        hrSamples: [(offset: TimeInterval, bpm: Int)],
        cadenceSamples: [(offset: TimeInterval, value: Double)],
        powerSamples: [(offset: TimeInterval, value: Double)],
        strideSamples: [(offset: TimeInterval, value: Double)] = [],
        vertOscSamples: [(offset: TimeInterval, value: Double)] = [],
        fadeStartKm: Double? = nil
    ) -> RunChartData {

        let splits      = detail?.splits ?? []
        let totalKm     = activity.distance / 1000.0
        let useLongDist = totalKm > 20
        let tdMap       = buildTimeDistanceMap(splits: splits,
                                               totalDuration: activity.duration,
                                               totalKm: totalKm)

        var allSeries: [RunChartLayer: RunChartSeries] = [:]

        func rawPoints(_ samples: [(offset: TimeInterval, value: Double)]) -> [(km: Double, value: Double)] {
            useLongDist
                ? buildKmAveragedPoints(samples: samples, timeDistanceMap: tdMap, totalKm: totalKm)
                : buildTimeSeriesPoints(samples: samples, timeDistanceMap: tdMap)
        }

        // Heart rate — 2–98 percentile clamp, window 9
        let hrRaw = rawPoints(hrSamples.map { (offset: $0.offset, value: Double($0.bpm)) })
        if let s = makeSmoothedSeries(layer: .heartRate, rawPoints: hrRaw,
                                      smoothWindow: 9,
                                      clamp: .percentile(lo: 0.02, hi: 0.98)) {
            allSeries[.heartRate] = s
        }

        // Cadence — physiological hard clamp 150–200 spm, window 21
        let cadRaw = rawPoints(cadenceSamples)
        if let s = makeSmoothedSeries(layer: .cadence, rawPoints: cadRaw,
                                      smoothWindow: 21,
                                      clamp: .hard(min: 150, max: 200)) {
            allSeries[.cadence] = s
        }

        // Power — 5–95 percentile clamp, window 15
        let powRaw = rawPoints(powerSamples)
        if let s = makeSmoothedSeries(layer: .power, rawPoints: powRaw,
                                      smoothWindow: 15,
                                      clamp: .percentile(lo: 0.05, hi: 0.95)) {
            allSeries[.power] = s
        }

        // Stride length — physiological hard clamp 0.4–1.6 m, window 21
        let strRaw = rawPoints(strideSamples)
        if let s = makeSmoothedSeries(layer: .strideLength, rawPoints: strRaw,
                                      smoothWindow: 21,
                                      clamp: .hard(min: 0.4, max: 1.6)) {
            allSeries[.strideLength] = s
        }

        // Vertical oscillation — physiological hard clamp 4–16 cm, window 21
        let vocRaw = rawPoints(vertOscSamples)
        if let s = makeSmoothedSeries(layer: .verticalOsc, rawPoints: vocRaw,
                                      smoothWindow: 21,
                                      clamp: .hard(min: 4, max: 16)) {
            allSeries[.verticalOsc] = s
        }

        // Pace from splits — no smoothing
        if !splits.isEmpty, let paceSeries = buildPaceSeries(splits: splits) {
            allSeries[.pace] = paceSeries
        }

        // Elevation — already distance-keyed, no smoothing
        if let altProfile = detail?.altitudeProfile, altProfile.count >= 2 {
            let raw = altProfile.map { (km: $0.distanceKm, value: $0.altitude) }
            if let s = makeSeries(layer: .elevation, rawPoints: raw, invertNorm: false) {
                allSeries[.elevation] = s
            }
        }

        // HR zone bands
        let hrZones     = detail?.hrZones ?? []
        let hrZoneBands = hrZones.map { (zone: $0.id, lowerBPM: $0.minBPM, upperBPM: $0.maxBPM) }
        let hrMin: Double
        let hrMax: Double
        if !hrZones.isEmpty,
           let zMin = hrZones.map({ Double($0.minBPM) }).min(),
           let zMax = hrZones.map({ Double($0.maxBPM) }).max() {
            hrMin = zMin; hrMax = zMax
        } else {
            let bpms = hrSamples.map { Double($0.bpm) }
            hrMin = bpms.min() ?? 0; hrMax = bpms.max() ?? 220
        }

        let availableLayers = RunChartLayer.allCases.filter { allSeries[$0]?.isEmpty == false }

        // Work-segment bands from interval plan
        var workSegs: [(startKm: Double, endKm: Double)] = []
        if let intervals = detail?.intervalSegments {
            let workoutStart = activity.date
            for seg in intervals where seg.stepLabel == "운동" {
                let s0 = seg.startDate.timeIntervalSince(workoutStart)
                let e0 = s0 + seg.duration
                guard s0 >= 0, e0 > s0 else { continue }
                guard let sk = timeToKm(s0, map: tdMap),
                      let ek = timeToKm(e0, map: tdMap), ek > sk else { continue }
                workSegs.append((startKm: sk, endKm: ek))
            }
        }

        return RunChartData(
            totalKm: totalKm,
            series: allSeries,
            hrZoneBands: hrZoneBands,
            hrMin: hrMin,
            hrMax: hrMax,
            availableLayers: availableLayers,
            workSegments: workSegs,
            fadeStartKm: fadeStartKm
        )
    }

    // MARK: - Smoothed series builder (line layers)

    private static func makeSmoothedSeries(
        layer: RunChartLayer,
        rawPoints: [(km: Double, value: Double)],
        smoothWindow: Int,
        clamp: ClampMode
    ) -> RunChartSeries? {
        guard rawPoints.count >= 2 else { return nil }

        let rawValues = rawPoints.map { $0.value }

        // Stats from original values — stat tiles show these
        let minVal = rawValues.min()!
        let maxVal = rawValues.max()!
        let avgVal = rawValues.reduce(0, +) / Double(rawValues.count)

        // Clamp for display (original values preserved for stats)
        let clamped: [Double]
        switch clamp {
        case .percentile(let lo, let hi):
            clamped = percentileClamp(rawValues, lo: lo, hi: hi)
        case .hard(let mn, let mx):
            clamped = rawValues.map { max(mn, min(mx, $0)) }
        }

        let smoothed  = movingMedian(clamped, window: smoothWindow)
        let lastValue = smoothed.last ?? avgVal

        let smMin   = smoothed.min()!
        let smMax   = smoothed.max()!
        let smRange = smMax - smMin

        let points = zip(rawPoints, smoothed).map { (rp, sv) -> RunChartPoint in
            RunChartPoint(km: rp.km, value: sv,
                          norm: smRange > 0 ? (sv - smMin) / smRange : 0.5)
        }

        return RunChartSeries(layer: layer, points: points,
                              minValue: minVal, maxValue: maxVal, avgValue: avgVal,
                              lastValue: lastValue)
    }

    // MARK: - Clamping helpers

    private static func percentileClamp(_ values: [Double], lo: Double, hi: Double) -> [Double] {
        guard values.count > 1 else { return values }
        let sorted = values.sorted()
        let n      = sorted.count - 1
        let loVal  = sorted[max(0, Int((lo * Double(n)).rounded()))]
        let hiVal  = sorted[min(n, Int((hi * Double(n)).rounded()))]
        return values.map { max(loVal, min(hiVal, $0)) }
    }

    // MARK: - Moving median smoothing

    private static func movingMedian(_ values: [Double], window: Int) -> [Double] {
        let half = window / 2
        return values.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(values.count - 1, i + half)
            var slice = Array(values[lo...hi])
            slice.sort()
            return slice[slice.count / 2]
        }
    }

    // MARK: - km-averaged points for distance > 20 km

    private static func buildKmAveragedPoints(
        samples: [(offset: TimeInterval, value: Double)],
        timeDistanceMap: [(time: TimeInterval, km: Double)],
        totalKm: Double
    ) -> [(km: Double, value: Double)] {
        let kmValues = samples.compactMap { s -> (km: Double, value: Double)? in
            guard let km = timeToKm(s.offset, map: timeDistanceMap) else { return nil }
            return (km, s.value)
        }
        guard !kmValues.isEmpty else { return [] }
        let bucketCount = max(1, Int(totalKm.rounded()))
        var buckets: [[Double]] = Array(repeating: [], count: bucketCount)
        for (km, val) in kmValues {
            buckets[min(bucketCount - 1, max(0, Int(km)))].append(val)
        }
        return buckets.enumerated().compactMap { (i, b) -> (km: Double, value: Double)? in
            guard !b.isEmpty else { return nil }
            return (km: Double(i) + 0.5, value: b.reduce(0, +) / Double(b.count))
        }
    }

    // MARK: - Time → distance mapping

    private static func buildTimeDistanceMap(
        splits: [SplitData],
        totalDuration: TimeInterval,
        totalKm: Double
    ) -> [(time: TimeInterval, km: Double)] {
        guard !splits.isEmpty else { return [(0, 0), (totalDuration, totalKm)] }
        var map: [(time: TimeInterval, km: Double)] = [(0, 0)]
        var t: TimeInterval = 0; var km: Double = 0
        for split in splits {
            t  += split.duration
            km += split.distanceM / 1000.0
            map.append((t, km))
        }
        return map
    }

    private static func timeToKm(_ offset: TimeInterval,
                                  map: [(time: TimeInterval, km: Double)]) -> Double? {
        guard map.count >= 2 else { return nil }
        if offset <= map[0].time            { return map[0].km }
        if offset >= map[map.count-1].time  { return map[map.count-1].km }
        for i in 1..<map.count {
            let prev = map[i-1], curr = map[i]
            guard offset >= prev.time && offset <= curr.time else { continue }
            let dt = curr.time - prev.time
            guard dt > 0 else { return prev.km }
            return prev.km + (offset - prev.time) / dt * (curr.km - prev.km)
        }
        return map[map.count-1].km
    }

    // MARK: - Time-series → km-series (≤ 20 km)

    private static func buildTimeSeriesPoints(
        samples: [(offset: TimeInterval, value: Double)],
        timeDistanceMap: [(time: TimeInterval, km: Double)]
    ) -> [(km: Double, value: Double)] {
        var pts = samples.compactMap { s -> (km: Double, value: Double)? in
            guard let km = timeToKm(s.offset, map: timeDistanceMap) else { return nil }
            return (km, s.value)
        }
        if pts.count > 300 { pts = downsample(pts, to: 300) }
        return pts
    }

    // MARK: - Pace series from splits

    private static func buildPaceSeries(splits: [SplitData]) -> RunChartSeries? {
        var rawPoints: [(km: Double, value: Double)] = []
        var cumulativeKm: Double = 0
        for split in splits {
            let splitKm = split.distanceM / 1000.0
            guard splitKm > 0 else { continue }
            rawPoints.append((km: cumulativeKm + splitKm / 2.0, value: split.duration / splitKm))
            cumulativeKm += splitKm
        }
        guard rawPoints.count >= 2 else { return nil }

        let values    = rawPoints.map { $0.value }
        let minVal    = values.min()!
        let maxVal    = values.max()!
        let avgVal    = values.reduce(0, +) / Double(values.count)
        let lastValue = rawPoints.last?.value ?? avgVal
        let range     = maxVal - minVal

        let points = rawPoints.map { p -> RunChartPoint in
            RunChartPoint(km: p.km, value: p.value,
                          norm: range > 0 ? 1.0 - (p.value - minVal) / range : 0.5)
        }
        let fastestIdx = values.enumerated().min(by: { $0.element < $1.element })?.offset
        let slowestIdx = values.enumerated().max(by: { $0.element < $1.element })?.offset

        return RunChartSeries(layer: .pace, points: points,
                              minValue: minVal, maxValue: maxVal, avgValue: avgVal,
                              minIndex: fastestIdx, maxIndex: slowestIdx,
                              lastValue: lastValue)
    }

    // MARK: - Generic series builder (elevation)

    private static func makeSeries(
        layer: RunChartLayer,
        rawPoints: [(km: Double, value: Double)],
        invertNorm: Bool
    ) -> RunChartSeries? {
        guard rawPoints.count >= 2 else { return nil }
        let values    = rawPoints.map { $0.value }
        let minVal    = values.min()!
        let maxVal    = values.max()!
        let avgVal    = values.reduce(0, +) / Double(values.count)
        let lastValue = rawPoints.last?.value ?? avgVal
        let range     = maxVal - minVal
        let points    = rawPoints.map { p -> RunChartPoint in
            var t = range > 0 ? (p.value - minVal) / range : 0.5
            if invertNorm { t = 1.0 - t }
            return RunChartPoint(km: p.km, value: p.value, norm: t)
        }
        return RunChartSeries(layer: layer, points: points,
                              minValue: minVal, maxValue: maxVal, avgValue: avgVal,
                              lastValue: lastValue)
    }

    // MARK: - Downsampling

    private static func downsample(
        _ points: [(km: Double, value: Double)],
        to maxCount: Int
    ) -> [(km: Double, value: Double)] {
        guard points.count > maxCount else { return points }
        let step = Double(points.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { i in
            points[min(Int((Double(i) * step).rounded()), points.count - 1)]
        }
    }
}
