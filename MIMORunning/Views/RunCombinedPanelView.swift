import SwiftUI

// MARK: - RunChartLayerStore

@Observable @MainActor
final class RunChartLayerStore {
    static let shared = RunChartLayerStore()
    private static let defaultsKey = "mimo.runChart.enabledLayers"

    var enabled: Set<RunChartLayer> {
        didSet { persist() }
    }

    private init() {
        if let raw = UserDefaults.standard.array(forKey: Self.defaultsKey) as? [String] {
            let restored = Set(raw.compactMap { RunChartLayer(rawValue: $0) })
            enabled = restored.isEmpty ? [.heartRate, .pace] : restored
        } else {
            enabled = [.heartRate, .pace]
        }
    }

    private func persist() {
        UserDefaults.standard.set(enabled.map(\.rawValue), forKey: Self.defaultsKey)
    }

    func toggle(_ layer: RunChartLayer) {
        if enabled.contains(layer) {
            guard enabled.count > 1 else { return }
            enabled.remove(layer)
        } else {
            enabled.insert(layer)
        }
    }
}

// MARK: - RunCombinedPanelView

struct RunCombinedPanelView: View {
    let data: RunChartData
    var weatherText: String? = nil
    var summaryText: String

    @State private var store = RunChartLayerStore.shared

    private let tileColumns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        if data.availableLayers.isEmpty {
            emptyPlaceholder
        } else {
            VStack(spacing: 0) {
                // Chart area — pure black for line contrast
                VStack(spacing: 0) {
                    contextRow
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    RunCombinedChartView(data: data, enabledLayers: store.enabled)
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                }
                .background(Color.black)

                // Stat tiles — all layers always shown, tap to toggle
                LazyVGrid(columns: tileColumns, spacing: 6) {
                    ForEach(data.availableLayers) { layer in
                        if let series = data.series[layer] {
                            RunStatTile(
                                layer: layer,
                                series: series,
                                isOn: store.enabled.contains(layer)
                            ) {
                                store.toggle(layer)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                Spacer(minLength: 12)
            }
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Context row

    private var contextRow: some View {
        HStack {
            Text(summaryText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.92))
            Spacer()
            if let weather = weatherText {
                Text(weather)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }
        }
    }

    // MARK: - Empty state

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("종합 차트 데이터 없음")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
}

// MARK: - Stat Tile (toggle + display)

private struct RunStatTile: View {
    let layer: RunChartLayer
    let series: RunChartSeries
    let isOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                // Row 1: dot + name + range
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(layer.color.opacity(isOn ? 1.0 : 0.38))
                        .frame(width: 7, height: 7)
                    Text(layer.shortLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(isOn ? 0.55 : 0.28))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text("\(layer.formatted(series.minValue))–\(layer.formatted(series.maxValue))")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(isOn ? 0.38 : 0.20))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                // Row 2: avg value + unit
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(layer.formatted(series.avgValue))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(isOn ? 1.0 : 0.28))
                    Text(layer.unit)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(isOn ? 0.52 : 0.22))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .background(
                Color.white.opacity(isOn ? 0.08 : 0.04),
                in: RoundedRectangle(cornerRadius: 9)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    let totalKm = 10.0
    let n = 100

    let hrPoints: [RunChartPoint] = (0..<n).map { i in
        let km = Double(i) / Double(n - 1) * totalKm
        let norm = 0.4 + 0.35 * sin(Double(i) / 10.0)
        return RunChartPoint(km: km, value: 140 + norm * 30, norm: norm)
    }
    let hrSeries = RunChartSeries(layer: .heartRate, points: hrPoints,
                                  minValue: 91, maxValue: 159, avgValue: 146,
                                  minIndex: nil, maxIndex: nil)

    let pacePoints: [RunChartPoint] = (0..<10).map { i in
        let km = Double(i) + 0.5
        let raw = 370.0 + Double(i) * 4 - (i == 3 ? 30 : 0) + (i == 8 ? 25 : 0)
        let norm = 1.0 - (raw - 340) / 80.0
        return RunChartPoint(km: km, value: raw, norm: max(0.1, min(1, norm)))
    }
    let paceSeries = RunChartSeries(layer: .pace, points: pacePoints,
                                    minValue: 340, maxValue: 420, avgValue: 376,
                                    minIndex: 3, maxIndex: 8)

    let elevPoints: [RunChartPoint] = (0..<n).map { i in
        let km = Double(i) / Double(n - 1) * totalKm
        let norm = 0.1 + 0.45 * abs(sin(Double(i) / 15.0))
        return RunChartPoint(km: km, value: 50 + norm * 120, norm: norm)
    }
    let elevSeries = RunChartSeries(layer: .elevation, points: elevPoints,
                                    minValue: 4, maxValue: 11, avgValue: 6,
                                    minIndex: nil, maxIndex: nil)

    let cadencePoints: [RunChartPoint] = (0..<n).map { i in
        let km = Double(i) / Double(n - 1) * totalKm
        let norm = 0.55 + 0.2 * cos(Double(i) / 8.0)
        return RunChartPoint(km: km, value: 160 + norm * 20, norm: norm)
    }
    let cadenceSeries = RunChartSeries(layer: .cadence, points: cadencePoints,
                                       minValue: 70, maxValue: 211, avgValue: 173,
                                       minIndex: nil, maxIndex: nil)

    let powerPoints: [RunChartPoint] = (0..<n).map { i in
        let km = Double(i) / Double(n - 1) * totalKm
        let norm = 0.5 + 0.3 * sin(Double(i) / 12.0 + 1.5)
        return RunChartPoint(km: km, value: 180 + norm * 40, norm: norm)
    }
    let powerSeries = RunChartSeries(layer: .power, points: powerPoints,
                                     minValue: 100, maxValue: 225, avgValue: 201,
                                     minIndex: nil, maxIndex: nil)

    let stridePoints: [RunChartPoint] = (0..<n).map { i in
        let km = Double(i) / Double(n - 1) * totalKm
        let norm = 0.5 + 0.2 * sin(Double(i) / 11.0)
        return RunChartPoint(km: km, value: 0.85 + norm * 0.2, norm: norm)
    }
    let strideSeries = RunChartSeries(layer: .strideLength, points: stridePoints,
                                      minValue: 0.82, maxValue: 1.02, avgValue: 0.93,
                                      minIndex: nil, maxIndex: nil)

    let vertOscPoints: [RunChartPoint] = (0..<n).map { i in
        let km = Double(i) / Double(n - 1) * totalKm
        let norm = 0.4 + 0.3 * cos(Double(i) / 9.0)
        return RunChartPoint(km: km, value: 8.0 + norm * 2.5, norm: norm)
    }
    let vertOscSeries = RunChartSeries(layer: .verticalOsc, points: vertOscPoints,
                                       minValue: 8.5, maxValue: 10.0, avgValue: 9.0,
                                       minIndex: nil, maxIndex: nil)

    let chartData = RunChartData(
        totalKm: totalKm,
        series: [
            .heartRate: hrSeries,
            .pace: paceSeries,
            .elevation: elevSeries,
            .cadence: cadenceSeries,
            .power: powerSeries,
            .strideLength: strideSeries,
            .verticalOsc: vertOscSeries
        ],
        hrZoneBands: [
            (zone: 1, lowerBPM: 100, upperBPM: 120),
            (zone: 2, lowerBPM: 120, upperBPM: 140),
            (zone: 3, lowerBPM: 140, upperBPM: 160),
            (zone: 4, lowerBPM: 160, upperBPM: 175)
        ],
        hrMin: 91,
        hrMax: 159,
        availableLayers: [.heartRate, .pace, .elevation, .cadence, .power, .strideLength, .verticalOsc]
    )

    return ZStack {
        Theme.background.ignoresSafeArea()
        ScrollView {
            RunCombinedPanelView(
                data: chartData,
                weatherText: "☁️ 28° · 습도 70%",
                summaryText: "6.03 km · 37:50"
            )
            .padding(.vertical, 16)
        }
    }
    .preferredColorScheme(.dark)
}
