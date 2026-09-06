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
    case aerobic      = "유산소"
    case calories     = "칼로리"

    var id: String { rawValue }

    /// Color used for toggle chips, stat tiles, and chart lines (zone gradient for HR).
    var color: Color {
        switch self {
        case .heartRate:    return Theme.heartRate
        case .pace:         return Theme.chartPace
        case .cadence:      return Theme.chartCadence
        case .elevation:    return Theme.chartElev
        case .power:        return Theme.chartPower
        case .strideLength: return Theme.chartStride
        case .verticalOsc:  return Theme.chartVertOsc
        // 값 전용(선 없음) 타일은 중립 회색 — 칼로리 핑크가 심박 빨강과 겹쳐 보이던 문제 제거
        case .aerobic:      return Theme.chartValueOnly
        case .calories:     return Theme.chartValueOnly
        }
    }

    enum DrawStyle {
        case line(width: CGFloat)
        case bars
        case fill
        case fillWithLine(fillOpacity: Double, lineWidth: CGFloat)
    }

    var drawStyle: DrawStyle {
        switch self {
        case .heartRate:    return .line(width: 2.2)
        case .cadence:      return .line(width: 2.1)
        case .power:        return .line(width: 2.1)
        case .strideLength: return .line(width: 1.8)
        case .verticalOsc:  return .line(width: 1.8)
        case .aerobic:      return .line(width: 1.5)
        case .calories:     return .line(width: 1.5)
        case .pace:         return .bars
        case .elevation:    return .fillWithLine(fillOpacity: 0.38, lineWidth: 1.0)
        }
    }

    // Visual hierarchy — higher priority layers are more opaque
    var opacity: Double {
        switch self {
        case .heartRate:    return 1.00
        case .cadence:      return 1.00
        case .power:        return 1.00
        case .strideLength: return 0.92
        case .verticalOsc:  return 0.92
        case .aerobic:      return 0.92
        case .calories:     return 0.92
        case .pace:         return 0.20
        case .elevation:    return 0.10
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
        case .aerobic:      return "mL/kg·min"
        case .calories:     return "kcal"
        }
    }

    var shortLabel: String {
        let L = AppLanguage.shared
        switch self {
        case .heartRate:    return L.s("심박",    "HR")
        case .pace:         return L.s("페이스",  "Pace")
        case .cadence:      return L.s("케이던스","Cadence")
        case .elevation:    return L.s("고도",    "Elev.")
        case .power:        return L.s("파워",    "Power")
        case .strideLength: return L.s("보폭",    "Stride")
        case .verticalOsc:  return L.s("진폭",    "Vert.Osc")
        case .aerobic:      return L.s("유산소",  "Aerobic")
        case .calories:     return L.s("칼로리",  "kcal")
        }
    }

    /// 차트에 선으로 그리지 않고 타일에만 값 표시하는 레이어
    var isValueOnly: Bool {
        switch self {
        case .aerobic, .calories: return true
        default:                  return false
        }
    }
}

extension RunChartLayer {
    func formatted(_ value: Double) -> String {
        switch self {
        case .pace:
            let total = Int(value.rounded())
            return "\(total / 60)'\(String(format: "%02d", total % 60))\""
        case .heartRate, .cadence, .power, .elevation, .calories:
            return "\(Int(value.rounded()))"
        case .strideLength:
            return String(format: "%.2f", value)
        case .verticalOsc:
            return String(format: "%.1f", value)
        case .aerobic:
            return String(format: "%.1f", value)
        }
    }

    /// 타일 범위 표시용 — 페이스의 trailing `"` 제거해 공간 절약
    func formattedRange(_ value: Double) -> String {
        guard self == .pace else { return formatted(value) }
        let total = Int(value.rounded())
        return "\(total / 60)'\(String(format: "%02d", total % 60))"
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

    /// stepCount 기반 정확한 평균으로 교체 — 차트 시각화(points)는 유지
    func withAvg(_ avg: Double) -> RunChartSeries {
        RunChartSeries(layer: layer, points: points,
                       minValue: minValue, maxValue: maxValue,
                       avgValue: avg, minIndex: minIndex, maxIndex: maxIndex, lastValue: lastValue)
    }
}

// MARK: - PaceColumn

/// Time-proportional background column for pace visualization.
/// x-positions are based on cumulative duration (slow km = wider column).
struct PaceColumn {
    let startKm: Double
    let endKm: Double
    /// Fraction of total duration at column start (0–1).
    let startX: Double
    /// Fraction of total duration at column end (0–1).
    let endX: Double
    let paceSecPerKm: Double
    /// 0–1, faster = 1 (taller column).
    let norm: Double
    /// Formatted pace label, e.g. "6'27\""
    let label: String
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
    let paceColumns: [PaceColumn]
    let bucketKm: Int
    /// Total workout duration in seconds — used for elapsed-time x-axis labels.
    let totalDuration: TimeInterval

    init(
        totalKm: Double,
        series: [RunChartLayer: RunChartSeries],
        hrZoneBands: [(zone: Int, lowerBPM: Int, upperBPM: Int)],
        hrMin: Double,
        hrMax: Double,
        availableLayers: [RunChartLayer],
        workSegments: [(startKm: Double, endKm: Double)] = [],
        fadeStartKm: Double? = nil,
        paceColumns: [PaceColumn] = [],
        bucketKm: Int = 1,
        totalDuration: TimeInterval = 0
    ) {
        self.totalKm         = totalKm
        self.series          = series
        self.hrZoneBands     = hrZoneBands
        self.hrMin           = hrMin
        self.hrMax           = hrMax
        self.availableLayers = availableLayers
        self.workSegments    = workSegments
        self.fadeStartKm     = fadeStartKm
        self.paceColumns     = paceColumns
        self.bucketKm        = bucketKm
        self.totalDuration   = totalDuration
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

        // 저장된 평균값 — 앱 시작 시 HealthKit에서 가져와 CachedActivity에 저장된 값 우선 사용
        let storedHRAvg    = activity.avgHeartRate.map { Double($0) }
        let storedCadAvg   = detail?.avgCadence.map { Double($0) }
        let storedPowAvg   = detail?.avgPower.map { Double($0) }
        let storedStrAvg   = detail?.avgStrideLength
        let storedVocAvg   = detail?.avgVerticalOscillation

        // Heart rate — 2–98 percentile clamp, median 15 → mean 13
        let hrRaw = rawPoints(hrSamples.map { (offset: $0.offset, value: Double($0.bpm)) })
        if let s = makeSmoothedSeries(layer: .heartRate, rawPoints: hrRaw,
                                      smoothWindow: 15,
                                      clamp: .percentile(lo: 0.02, hi: 0.98),
                                      meanWindow: 13) {
            allSeries[.heartRate] = storedHRAvg.map { s.withAvg($0) } ?? s
        }

        // Cadence — hard clamp 140–220, 상하 3% percentile 제거 → median 25 → mean 25
        let cadRaw = rawPoints(cadenceSamples)
        if let s = makeSmoothedSeries(layer: .cadence, rawPoints: cadRaw,
                                      smoothWindow: 25,
                                      clamp: .hard(min: 140, max: 220),
                                      secondaryClamp: .percentile(lo: 0.01, hi: 0.92),
                                      meanWindow: 25) {
            allSeries[.cadence] = storedCadAvg.map { s.withAvg($0) } ?? s
        }

        // Power — 5–95 percentile clamp, median 25 → mean 25
        let powRaw = rawPoints(powerSamples)
        if let s = makeSmoothedSeries(layer: .power, rawPoints: powRaw,
                                      smoothWindow: 25,
                                      clamp: .percentile(lo: 0.05, hi: 0.95),
                                      meanWindow: 25) {
            allSeries[.power] = storedPowAvg.map { s.withAvg($0) } ?? s
        }

        // Stride — hard clamp 0.4–1.6 m → 5–95 percentile → median 25 → mean 25
        let strRaw = rawPoints(strideSamples)
        if let s = makeSmoothedSeries(layer: .strideLength, rawPoints: strRaw,
                                      smoothWindow: 25,
                                      clamp: .hard(min: 0.4, max: 1.6),
                                      secondaryClamp: .percentile(lo: 0.05, hi: 0.95),
                                      meanWindow: 25) {
            allSeries[.strideLength] = storedStrAvg.map { s.withAvg($0) } ?? s
        }

        // Vert osc — hard clamp 4–16 cm → 5–95 percentile → median 25 → mean 25
        let vocRaw = rawPoints(vertOscSamples)
        if let s = makeSmoothedSeries(layer: .verticalOsc, rawPoints: vocRaw,
                                      smoothWindow: 25,
                                      clamp: .hard(min: 4, max: 16),
                                      secondaryClamp: .percentile(lo: 0.05, hi: 0.95),
                                      meanWindow: 25) {
            allSeries[.verticalOsc] = storedVocAvg.map { s.withAvg($0) } ?? s
        }

        // Pace from splits — no smoothing
        if !splits.isEmpty, let paceSeries = buildPaceSeries(splits: splits) {
            allSeries[.pace] = paceSeries
        }

        // Elevation — already distance-keyed, light mean smoothing
        if let altProfile = detail?.altitudeProfile, altProfile.count >= 2 {
            let raw = altProfile.map { (km: $0.distanceKm, value: $0.altitude) }
            if let s = makeSeries(layer: .elevation, rawPoints: raw, invertNorm: false, smoothWindow: 25, meanWindow: 25,
                                  minDisplaySpan: elevationMinSpanM) {
                allSeries[.elevation] = s
            }
        }

        // 유산소 피트니스 (VO2max) — HealthKit 최신 추정값, detail에서 직접 사용
        if let vo2 = detail?.vo2Max, vo2 > 0 {
            let pt0 = RunChartPoint(km: 0,       value: vo2, norm: 0.5)
            let ptN = RunChartPoint(km: totalKm, value: vo2, norm: 0.5)
            allSeries[.aerobic] = RunChartSeries(layer: .aerobic, points: [pt0, ptN],
                                                 minValue: vo2, maxValue: vo2,
                                                 avgValue: vo2, lastValue: vo2)
        }

        // 칼로리 (총합) — activity.calories 직접 사용
        if let totalCal = activity.calories, totalCal > 0 {
            let pt0 = RunChartPoint(km: 0,       value: totalCal, norm: 0.5)
            let ptN = RunChartPoint(km: totalKm, value: totalCal, norm: 0.5)
            allSeries[.calories] = RunChartSeries(layer: .calories, points: [pt0, ptN],
                                                  minValue: totalCal, maxValue: totalCal,
                                                  avgValue: totalCal, lastValue: totalCal)
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

        let (pcols, bkm) = buildPaceColumns(splits: splits, totalDuration: activity.duration)

        return RunChartData(
            totalKm: totalKm,
            series: allSeries,
            hrZoneBands: hrZoneBands,
            hrMin: hrMin,
            hrMax: hrMax,
            availableLayers: availableLayers,
            workSegments: workSegs,
            fadeStartKm: fadeStartKm,
            paceColumns: pcols,
            bucketKm: bkm,
            totalDuration: activity.duration
        )
    }

    // MARK: - Pace columns (time-proportional background)

    private static func buildPaceColumns(
        splits: [SplitData],
        totalDuration: TimeInterval
    ) -> ([PaceColumn], Int) {
        guard !splits.isEmpty, totalDuration > 0 else { return ([], 1) }

        let totalKm  = splits.reduce(0.0) { $0 + $1.distanceM / 1000 }
        let bucketKm = max(1, Int(ceil(totalKm / 14.0)))

        // Group splits into chunks of bucketKm splits each
        var chunks: [[SplitData]] = []
        var i = 0
        while i < splits.count {
            let end = min(i + bucketKm, splits.count)
            chunks.append(Array(splits[i..<end]))
            i = end
        }

        // Compute timing and pace per chunk
        var cumulativeTime: Double = 0
        var cumulativeKm: Double   = 0
        var rawPaces: [Double]                       = []
        var timings:  [(start: Double, end: Double)] = []
        var kmRanges: [(start: Double, end: Double)] = []

        for chunk in chunks {
            let chunkKm   = chunk.reduce(0.0) { $0 + $1.distanceM / 1000 }
            let chunkTime = chunk.reduce(0.0) { $0 + $1.duration }
            let pace      = chunkKm > 0 ? chunkTime / chunkKm : 0
            rawPaces.append(pace)
            timings.append((start: cumulativeTime, end: cumulativeTime + chunkTime))
            kmRanges.append((start: cumulativeKm,  end: cumulativeKm + chunkKm))
            cumulativeTime += chunkTime
            cumulativeKm   += chunkKm
        }

        let validPaces = rawPaces.filter { $0 > 0 }
        guard !validPaces.isEmpty else { return ([], bucketKm) }

        let minPace   = validPaces.min()!
        let maxPace   = validPaces.max()!
        let paceRange = maxPace - minPace

        let columns: [PaceColumn] = rawPaces.indices.compactMap { idx in
            let pace = rawPaces[idx]
            guard pace > 0 else { return nil }
            let norm  = paceRange > 0 ? 1.0 - (pace - minPace) / paceRange : 0.5
            let sec   = Int(pace.rounded())
            let label = "\(sec / 60)'\(String(format: "%02d", sec % 60))\""
            return PaceColumn(
                startKm: kmRanges[idx].start, endKm: kmRanges[idx].end,
                startX:  timings[idx].start / totalDuration,
                endX:    min(1.0, timings[idx].end / totalDuration),
                paceSecPerKm: pace, norm: norm, label: label
            )
        }

        return (columns, bucketKm)
    }

    // MARK: - Smoothed series builder (line layers)

    private static func makeSmoothedSeries(
        layer: RunChartLayer,
        rawPoints: [(km: Double, value: Double)],
        smoothWindow: Int,
        clamp: ClampMode,
        secondaryClamp: ClampMode? = nil,
        meanWindow: Int = 0
    ) -> RunChartSeries? {
        guard rawPoints.count >= 2 else { return nil }

        let rawValues = rawPoints.map { $0.value }

        // Primary clamp (outlier removal)
        let clamped: [Double]
        switch clamp {
        case .percentile(let lo, let hi):
            clamped = percentileClamp(rawValues, lo: lo, hi: hi)
        case .hard(let mn, let mx):
            clamped = rawValues.map { max(mn, min(mx, $0)) }
        }

        // Secondary clamp (outlier 제거 — 상하 극단값 추가 제거)
        let doubleClamped: [Double]
        if let sec = secondaryClamp {
            switch sec {
            case .percentile(let lo, let hi):
                doubleClamped = percentileClamp(clamped, lo: lo, hi: hi)
            case .hard(let mn, let mx):
                doubleClamped = clamped.map { max(mn, min(mx, $0)) }
            }
        } else {
            doubleClamped = clamped
        }

        // Two-pass smoothing: median removes spikes, mean removes step artifacts
        var smoothed = movingMedian(doubleClamped, window: smoothWindow)
        if meanWindow > 1 { smoothed = movingMean(smoothed, window: meanWindow) }
        let lastValue = smoothed.last ?? doubleClamped.reduce(0, +) / Double(doubleClamped.count)

        // Chart normalization: smoothed range (line fills chart height naturally)
        let smMin   = smoothed.min()!
        let smMax   = smoothed.max()!
        let smRange = smMax - smMin
        let smAvg   = smoothed.reduce(0, +) / Double(smoothed.count)

        // Stats display: clamped raw data = actual HealthKit range, not smoothed
        let rawMin = doubleClamped.min()!
        let rawMax = doubleClamped.max()!

        let points = zip(rawPoints, smoothed).map { (rp, sv) -> RunChartPoint in
            RunChartPoint(km: rp.km, value: sv,
                          norm: smRange > 0 ? (sv - smMin) / smRange : 0.5)
        }

        return RunChartSeries(layer: layer, points: points,
                              minValue: rawMin, maxValue: rawMax, avgValue: smAvg,
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

    // MARK: - Smoothing helpers

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

    private static func movingMean(_ values: [Double], window: Int) -> [Double] {
        guard window > 1 else { return values }
        let half = window / 2
        return values.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(values.count - 1, i + half)
            let slice = values[lo...hi]
            return slice.reduce(0, +) / Double(slice.count)
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

    /// 고도 표시 최소 스팬(m).
    ///
    /// ⚠ 자동 스케일이면 4~11m짜리 평지 코스가 산처럼 그려진다 — 정보량은 0인데
    ///   화면에서 가장 큰 도형이 된다. 실제 고저차가 이 값보다 작으면 이 값을 분모로
    ///   써서 평지가 평평하게 보이게 한다. 30m는 임의로 정함(도심 코스 한 블록 언덕 정도).
    nonisolated static let elevationMinSpanM: Double = 30

    /// 정규화 분모. 실제 범위가 최소 스팬보다 작으면 최소 스팬을 쓴다.
    nonisolated static func displaySpan(range: Double, minSpan: Double) -> Double {
        max(range, minSpan)
    }

    private static func makeSeries(
        layer: RunChartLayer,
        rawPoints: [(km: Double, value: Double)],
        invertNorm: Bool,
        smoothWindow: Int = 0,
        meanWindow: Int = 0,
        minDisplaySpan: Double = 0
    ) -> RunChartSeries? {
        guard rawPoints.count >= 2 else { return nil }
        let values = rawPoints.map { $0.value }
        let minVal = values.min()!
        let maxVal = values.max()!
        let avgVal = values.reduce(0, +) / Double(values.count)

        // Optional two-pass smoothing: median removes spikes, mean smooths the curve
        var display = smoothWindow > 1 ? movingMedian(values, window: smoothWindow) : values
        display     = meanWindow   > 1 ? movingMean(display, window: meanWindow)    : display
        let lastValue = display.last ?? avgVal
        let dispMin   = display.min()!
        let dispRange = displaySpan(range: display.max()! - dispMin, minSpan: minDisplaySpan)
        let points    = rawPoints.indices.map { i -> RunChartPoint in
            let sv = display[i]
            var t = dispRange > 0 ? (sv - dispMin) / dispRange : 0.5
            if invertNorm { t = 1.0 - t }
            return RunChartPoint(km: rawPoints[i].km, value: sv, norm: t)
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
