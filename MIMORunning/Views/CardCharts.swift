import SwiftUI
import Charts

// MARK: - Compact card charts
//
// 카드 공유 시 사용하는 소형 차트 컴포넌트.
// ShareCardView(Athletic), StoryCard, PhotoCard, VideoOverlayCard 공용.

// MARK: - CardWorkoutSeriesChart

struct CardWorkoutSeriesChart: View {
    let samples: [(offset: TimeInterval, value: Double)]
    let panel: CardChartPanel
    var labelScale: CGFloat = 1.0

    private var barColor: Color {
        switch panel {
        case .cadence:  Theme.cadence
        case .power:    Theme.power
        case .elevation: Theme.elevation
        default:        Theme.runningForm
        }
    }

    private var validMin: Double {
        switch panel {
        case .cadence: return 130.0
        case .power:   return 5.0
        default:       return 0.0
        }
    }

    private var useRangeBar: Bool {
        switch panel {
        case .power, .groundContact, .strideLength, .verticalOscillation: return true
        default: return false
        }
    }

    private func yLabel(_ v: Double) -> String {
        switch panel {
        case .strideLength:        return String(format: "%.2f", v)
        case .verticalOscillation: return String(format: "%.1f", v)
        default:                   return "\(Int(v.rounded()))"
        }
    }

    private struct Bucket: Identifiable {
        let id: Int; let midMin: Double; let avg: Double; let minV: Double; let maxV: Double
    }

    private var buckets: [Bucket] {
        let filtered = samples.filter { $0.value > validMin }
        guard !filtered.isEmpty else { return [] }
        let total = max(filtered.map(\.offset).max() ?? 1, 1)
        let count = 40
        let size = total / Double(count)
        return (0..<count).compactMap { i in
            let lo = Double(i) * size, hi = lo + size
            let vals = filtered
                .filter { $0.offset >= lo && ($0.offset < hi || (i == count - 1 && $0.offset <= hi)) }
                .map(\.value)
            guard !vals.isEmpty else { return nil }
            let avg = vals.reduce(0, +) / Double(vals.count)
            return Bucket(id: i, midMin: (lo + hi) / 2 / 60,
                          avg: avg, minV: vals.min() ?? 0, maxV: vals.max() ?? 0)
        }
    }

    private var domainLo: Double {
        if useRangeBar {
            guard let lo = buckets.map(\.minV).min() else { return 0 }
            return max(lo - (lo * 0.02), 0)
        }
        guard let lo = buckets.map(\.avg).min() else { return 0 }
        return max(lo - 15, 0)
    }

    private var domainHi: Double {
        if useRangeBar {
            return (buckets.map(\.maxV).max() ?? 1) * 1.05
        }
        return (buckets.map(\.avg).max() ?? 1) + 10
    }

    var body: some View {
        let lo = domainLo, hi = domainHi
        Chart {
            ForEach(buckets) { b in
                if panel == .elevation {
                    AreaMark(
                        x: .value("분", b.midMin),
                        yStart: .value("바닥", lo),
                        yEnd: .value("고도", b.avg)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [barColor.opacity(0.55), barColor.opacity(0.10)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("분", b.midMin),
                        y: .value("고도", b.avg)
                    )
                    .foregroundStyle(barColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                } else {
                    BarMark(
                        x: .value("분", b.midMin),
                        yStart: .value("lo", useRangeBar ? b.minV : lo),
                        yEnd: .value("hi", useRangeBar ? b.maxV : b.avg),
                        width: .fixed(2)
                    )
                    .foregroundStyle(barColor.opacity(0.85))
                }
            }
        }
        .chartYScale(domain: lo...hi)
        .chartXScale(domain: 0...((buckets.last?.midMin ?? 1) + 0.5))
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.10))
                AxisValueLabel {
                    if let v = val.as(Double.self) {
                        Text(yLabel(v)).font(.system(size: 6.5 * labelScale)).foregroundStyle(Color.white.opacity(0.80))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { val in
                AxisValueLabel {
                    if let t = val.as(Double.self) {
                        Text(AppLanguage.shared.s("\(Int(t))분", "\(Int(t))m")).font(.system(size: 6 * labelScale)).foregroundStyle(Color.white.opacity(0.75))
                    }
                }
            }
        }
    }
}

// MARK: - Interval work summary helper

extension Array where Element == IntervalSegment {
    private static let standardDistances = [100, 200, 300, 400, 500, 600, 800, 1000, 1200, 1500, 1600, 2000, 3000, 4000, 5000]

    var workSummaryText: String? {
        let paces = compactMap(\.paceSecPerKm).sorted()
        let median = paces.isEmpty ? nil : paces[paces.count / 2]
        let workSegs = filter { seg in
            if let label = seg.stepLabel { return label == "운동" }
            guard let p = seg.paceSecPerKm, let m = median else { return seg.id % 2 == 1 }
            return p < m
        }
        guard !workSegs.isEmpty else { return nil }
        let distances = workSegs.compactMap(\.distanceM)
        guard distances.count == workSegs.count else { return nil }
        let snapped = distances.map { d -> Int in
            let t = 0.08
            if let s = Self.standardDistances.first(where: { abs(Double($0) - d) / Double($0) <= t }) { return s }
            return d >= 200 ? Int((d / 100).rounded()) * 100 : Int((d / 50).rounded()) * 50
        }
        let counts = Dictionary(grouping: snapped, by: { $0 }).mapValues(\.count)
        guard let (dist, cnt) = counts.max(by: { $0.value < $1.value }), cnt > 1 || counts.count == 1 else { return nil }
        let label = dist >= 1000
            ? (dist % 1000 == 0 ? "\(dist / 1000)km" : String(format: "%.1fkm", Double(dist) / 1000))
            : "\(dist)m"
        return AppLanguage.shared.s("\(label)×\(cnt)회", "\(label)×\(cnt)")
    }
}

// MARK: - CardIntervalChart

struct CardIntervalChart: View {
    let segments: [IntervalSegment]
    var labelScale: CGFloat = 1.0
    @State private var labelX: [Int: CGFloat] = [:]

    var body: some View {
        let paces = segments.compactMap(\.paceSecPerKm).filter { $0 > 0 }
        let lo = (paces.min() ?? 240) * 0.86
        let sorted = paces.sorted()
        let p90 = sorted[(sorted.count - 1) * 9 / 10]
        let rawHi = paces.max() ?? 360
        let hi = rawHi > p90 * 1.5 ? p90 * 1.18 : rawHi * 1.06
        let n = segments.count
        let step: Int = n <= 6 ? 1 : n <= 15 ? 2 : n <= 30 ? 5 : 10
        let chartW: CGFloat = 130 * labelScale
        let barW: CGFloat = labelScale * (n <= 6 ? 7 : n <= 12 ? 5 : n <= 20 ? 4 : 3)
        VStack(spacing: 1) {
            Chart {
                ForEach(segments) { seg in
                    let pace = seg.paceSecPerKm ?? hi
                    let isWork = seg.stepLabel == "운동"
                    BarMark(x: .value("구간", seg.id), y: .value("pace", pace),
                            width: .fixed(barW))
                        .foregroundStyle((isWork ? Theme.intervalWork : Color.white.opacity(0.25)).gradient)
                        .cornerRadius(2)
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXScale(domain: 0.5...(Double(n) + 0.5))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.10))
                    AxisValueLabel {
                        if let sec = val.as(Double.self) {
                            Text(String(format: "%d'%02d\"", Int(sec) / 60, Int(sec) % 60))
                                .font(.system(size: 6.5 * labelScale))
                                .foregroundStyle(Color.white.opacity(0.80))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                Color.clear.onAppear {
                    var positions: [Int: CGFloat] = [:]
                    for id in 1...n where id % step == 0 {
                        if let x = proxy.position(forX: id) { positions[id] = x }
                    }
                    labelX = positions
                }
            }
            .frame(width: chartW, height: 63 * labelScale)
            .clipped()

            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(Array(labelX.keys.sorted()), id: \.self) { id in
                    Text("\(id)")
                        .font(.system(size: 6.5 * labelScale))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .fixedSize()
                        .position(x: labelX[id] ?? 0, y: 5 * labelScale)
                }
            }
            .frame(width: chartW, height: 10 * labelScale)
        }
    }
}
