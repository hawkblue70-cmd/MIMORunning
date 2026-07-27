import SwiftUI

// MARK: - RunChartLayer

enum RunChartLayer: String, CaseIterable, Identifiable {
    case heartRate = "심박"
    case pace      = "페이스"
    case cadence   = "케이던스"
    case elevation = "고도"
    case power     = "파워"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .heartRate: return Theme.heartRate
        case .pace:      return Theme.pace
        case .cadence:   return Theme.cadence
        case .elevation: return Theme.elevation
        case .power:     return Theme.power
        }
    }

    enum DrawStyle {
        case line(width: CGFloat)
        case dashedLine(width: CGFloat)
        case bars
        case fill
    }

    var drawStyle: DrawStyle {
        switch self {
        case .heartRate: return .line(width: 2.0)
        case .cadence:   return .line(width: 1.4)
        case .power:     return .dashedLine(width: 1.4)
        case .pace:      return .bars
        case .elevation: return .fill
        }
    }

    var unit: String {
        switch self {
        case .heartRate: return "bpm"
        case .pace:      return "/km"
        case .cadence:   return "spm"
        case .elevation: return "m"
        case .power:     return "W"
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
        case .heartRate:
            return "\(Int(value.rounded()))"
        case .cadence:
            return "\(Int(value.rounded()))"
        case .power:
            return "\(Int(value.rounded()))"
        case .elevation:
            return "\(Int(value.rounded()))"
        }
    }
}

// MARK: - RunChartPoint

struct RunChartPoint {
    let km: Double
    let value: Double
    /// 0.0–1.0 normalized within this layer's min/max range.
    /// Pace is inverted (faster = higher) so bars grow upward for fast splits.
    let norm: Double
}

// MARK: - RunChartSeries

struct RunChartSeries {
    let layer: RunChartLayer
    let points: [RunChartPoint]
    let minValue: Double
    let maxValue: Double
    let avgValue: Double
    /// Index of fastest split (min pace sec/km). Pace layer only.
    let minIndex: Int?
    /// Index of slowest split (max pace sec/km). Pace layer only.
    let maxIndex: Int?

    var isEmpty: Bool { points.count < 2 }
}

// MARK: - RunChartData

struct RunChartData {
    let totalKm: Double
    let series: [RunChartLayer: RunChartSeries]
    let hrZoneBands: [(zone: Int, lowerBPM: Int, upperBPM: Int)]
    /// Lower bound for mapping HR zone bands onto the y-axis.
    let hrMin: Double
    /// Upper bound for mapping HR zone bands onto the y-axis.
    let hrMax: Double
    /// Layers with at least 2 points, in CaseIterable order.
    let availableLayers: [RunChartLayer]

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

    static func build(
        activity: Activity,
        hrSamples: [(offset: TimeInterval, bpm: Int)],
        cadenceSamples: [(offset: TimeInterval, value: Double)],
        powerSamples: [(offset: TimeInterval, value: Double)]
    ) -> RunChartData {

        let splits = activity.detail?.splits ?? []
        let totalKm = activity.distance / 1000.0
        let timeDistanceMap = buildTimeDistanceMap(
            splits: splits,
            totalDuration: activity.duration,
            totalKm: totalKm
        )

        var allSeries: [RunChartLayer: RunChartSeries] = [:]

        // Heart rate
        let hrRaw = buildTimeSeriesPoints(
            samples: hrSamples.map { (offset: $0.offset, value: Double($0.bpm)) },
            timeDistanceMap: timeDistanceMap
        )
        if let s = makeSeries(layer: .heartRate, rawPoints: hrRaw, invertNorm: false) {
            allSeries[.heartRate] = s
        }

        // Cadence
        let cadenceRaw = buildTimeSeriesPoints(samples: cadenceSamples, timeDistanceMap: timeDistanceMap)
        if let s = makeSeries(layer: .cadence, rawPoints: cadenceRaw, invertNorm: false) {
            allSeries[.cadence] = s
        }

        // Power
        let powerRaw = buildTimeSeriesPoints(samples: powerSamples, timeDistanceMap: timeDistanceMap)
        if let s = makeSeries(layer: .power, rawPoints: powerRaw, invertNorm: false) {
            allSeries[.power] = s
        }

        // Pace from splits (bars per km segment)
        if !splits.isEmpty, let paceSeries = buildPaceSeries(splits: splits) {
            allSeries[.pace] = paceSeries
        }

        // Elevation — already distance-keyed
        if let altProfile = activity.detail?.altitudeProfile, altProfile.count >= 2 {
            let raw = altProfile.map { (km: $0.distanceKm, value: $0.altitude) }
            if let s = makeSeries(layer: .elevation, rawPoints: raw, invertNorm: false) {
                allSeries[.elevation] = s
            }
        }

        // HR zone bands and y-axis bounds
        let hrZones = activity.detail?.hrZones ?? []
        let hrZoneBands = hrZones.map { (zone: $0.id, lowerBPM: $0.minBPM, upperBPM: $0.maxBPM) }

        let hrMin: Double
        let hrMax: Double
        if !hrZones.isEmpty,
           let zMin = hrZones.map({ Double($0.minBPM) }).min(),
           let zMax = hrZones.map({ Double($0.maxBPM) }).max() {
            hrMin = zMin
            hrMax = zMax
        } else {
            let bpms = hrSamples.map { Double($0.bpm) }
            hrMin = bpms.min() ?? 0
            hrMax = bpms.max() ?? 220
        }

        let availableLayers = RunChartLayer.allCases.filter { layer in
            allSeries[layer]?.isEmpty == false
        }

        return RunChartData(
            totalKm: totalKm,
            series: allSeries,
            hrZoneBands: hrZoneBands,
            hrMin: hrMin,
            hrMax: hrMax,
            availableLayers: availableLayers
        )
    }

    // MARK: - Time → distance mapping

    private static func buildTimeDistanceMap(
        splits: [SplitData],
        totalDuration: TimeInterval,
        totalKm: Double
    ) -> [(time: TimeInterval, km: Double)] {

        guard !splits.isEmpty else {
            return [(0, 0), (totalDuration, totalKm)]
        }

        var map: [(time: TimeInterval, km: Double)] = [(0, 0)]
        var cumulativeTime: TimeInterval = 0
        var cumulativeKm: Double = 0

        for split in splits {
            cumulativeTime += split.duration
            cumulativeKm += split.distanceM / 1000.0
            map.append((cumulativeTime, cumulativeKm))
        }

        return map
    }

    private static func timeToKm(
        _ offset: TimeInterval,
        map: [(time: TimeInterval, km: Double)]
    ) -> Double? {

        guard map.count >= 2 else { return nil }
        if offset <= map[0].time { return map[0].km }
        if offset >= map[map.count - 1].time { return map[map.count - 1].km }

        for i in 1..<map.count {
            let prev = map[i - 1]
            let curr = map[i]
            guard offset >= prev.time && offset <= curr.time else { continue }
            let dt = curr.time - prev.time
            guard dt > 0 else { return prev.km }
            let t = (offset - prev.time) / dt
            return prev.km + t * (curr.km - prev.km)
        }
        return map[map.count - 1].km
    }

    // MARK: - Time-series → km-series

    private static func buildTimeSeriesPoints(
        samples: [(offset: TimeInterval, value: Double)],
        timeDistanceMap: [(time: TimeInterval, km: Double)]
    ) -> [(km: Double, value: Double)] {

        var points = samples.compactMap { s -> (km: Double, value: Double)? in
            guard let km = timeToKm(s.offset, map: timeDistanceMap) else { return nil }
            return (km, s.value)
        }

        if points.count > 300 {
            points = downsample(points, to: 300)
        }

        return points
    }

    // MARK: - Pace series from splits

    private static func buildPaceSeries(splits: [SplitData]) -> RunChartSeries? {
        var rawPoints: [(km: Double, value: Double)] = []
        var cumulativeKm: Double = 0

        for split in splits {
            let splitKm = split.distanceM / 1000.0
            guard splitKm > 0 else { continue }
            let paceSecPerKm = split.duration / splitKm
            let midKm = cumulativeKm + splitKm / 2.0
            rawPoints.append((km: midKm, value: paceSecPerKm))
            cumulativeKm += splitKm
        }

        guard rawPoints.count >= 2 else { return nil }

        let values = rawPoints.map { $0.value }
        let minVal = values.min()!
        let maxVal = values.max()!
        let avgVal = values.reduce(0, +) / Double(values.count)
        let range = maxVal - minVal

        // Invert: smaller sec/km = faster → bar grows taller
        let points = rawPoints.map { p -> RunChartPoint in
            let t = range > 0 ? (p.value - minVal) / range : 0.5
            return RunChartPoint(km: p.km, value: p.value, norm: 1.0 - t)
        }

        // minIndex = fastest (lowest sec/km), maxIndex = slowest
        let fastestIdx = values.enumerated().min(by: { $0.element < $1.element })?.offset
        let slowestIdx = values.enumerated().max(by: { $0.element < $1.element })?.offset

        return RunChartSeries(
            layer: .pace,
            points: points,
            minValue: minVal,
            maxValue: maxVal,
            avgValue: avgVal,
            minIndex: fastestIdx,
            maxIndex: slowestIdx
        )
    }

    // MARK: - Generic series builder

    private static func makeSeries(
        layer: RunChartLayer,
        rawPoints: [(km: Double, value: Double)],
        invertNorm: Bool
    ) -> RunChartSeries? {

        guard rawPoints.count >= 2 else { return nil }

        let values = rawPoints.map { $0.value }
        let minVal = values.min()!
        let maxVal = values.max()!
        let avgVal = values.reduce(0, +) / Double(values.count)
        let range = maxVal - minVal

        let points = rawPoints.map { p -> RunChartPoint in
            var t = range > 0 ? (p.value - minVal) / range : 0.5
            if invertNorm { t = 1.0 - t }
            return RunChartPoint(km: p.km, value: p.value, norm: t)
        }

        return RunChartSeries(
            layer: layer,
            points: points,
            minValue: minVal,
            maxValue: maxVal,
            avgValue: avgVal,
            minIndex: nil,
            maxIndex: nil
        )
    }

    // MARK: - Downsampling

    private static func downsample(
        _ points: [(km: Double, value: Double)],
        to maxCount: Int
    ) -> [(km: Double, value: Double)] {

        guard points.count > maxCount else { return points }
        let step = Double(points.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { i in
            let idx = min(Int((Double(i) * step).rounded()), points.count - 1)
            return points[idx]
        }
    }
}
