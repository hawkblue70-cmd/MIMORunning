import SwiftUI

// MARK: - RunChartLayerStore

@Observable @MainActor
final class RunChartLayerStore {
    static let shared = RunChartLayerStore()
    // ⚠ v2 — 시인성 개편 시 키를 바꿔 저장 상태를 기본(전부 켬)으로 한 번 되돌린다.
    // v3: 지면접촉 레이어 추가 — 저장된 v2 집합에는 없어서 그대로 두면 새 레이어가 꺼진 채 시작한다
    private static let defaultsKey = "mimo.runChart.enabledLayers.v3"

    var enabled: Set<RunChartLayer> {
        didSet { persist() }
    }

    private init() {
        if let raw = UserDefaults.standard.array(forKey: Self.defaultsKey) as? [String] {
            let restored = Set(raw.compactMap { RunChartLayer(rawValue: $0) })
            enabled = restored.isEmpty ? Set(RunChartLayer.allCases) : restored
        } else {
            // 기본은 전부 켬 (사용자 확정) — 타일을 탭해 끌 수 있다
            enabled = Set(RunChartLayer.allCases)
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
    var distanceText: String
    var durationText: String
    var weatherText: String? = nil
    var weatherIcon: String? = nil
    var dateText: String? = nil
    var weekdayText: String? = nil
    var startTimeText: String? = nil
    var shoeText: String? = nil
    var paceText: String? = nil

    @State private var store = RunChartLayerStore.shared
    @State private var playProgress: Double? = nil
    @State private var isPlaying = false
    @State private var playTask: Task<Void, Never>? = nil

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
                        .padding(.top, 8)

                    RunCombinedChartView(
                        data: data,
                        enabledLayers: store.enabled,
                        chartHeight: 263,
                        playProgress: playProgress,
                        onInteraction: { if isPlaying { stopPlay() } }
                    )
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                }
                .background(Color.black)

                // Stat tiles — 순서는 RunChartLayer 케이스 순서(= 러닝 상세 데이터 격자). 페이스는 타일 없음.
                LazyVGrid(columns: tileColumns, spacing: 3) {
                    ForEach(data.availableLayers.filter(\.hasTile)) { layer in
                        if let series = data.series[layer] {
                            if layer.isValueOnly {
                                // 값 전용 타일: 항상 밝게, 차트 토글 없음
                                RunStatTile(layer: layer, series: series, isOn: true) { }
                                    .allowsHitTesting(false)
                            } else {
                                RunStatTile(
                                    layer: layer,
                                    series: series,
                                    isOn: store.enabled.contains(layer),
                                    dotColors: (layer == .heartRate && !data.hrZoneBands.isEmpty)
                                        ? ShareChartPalette.dark.hrZones : nil
                                ) {
                                    stopPlay()
                                    store.toggle(layer)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)

                Spacer(minLength: 4)
            }
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .onDisappear { stopPlay() }
        }
    }

    // MARK: - Playback

    private func startPlay(duration: TimeInterval = 10) {
        playTask?.cancel()
        isPlaying = true
        playTask = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(start) / duration
                if t >= 1 {
                    playProgress = 1
                    try? await Task.sleep(for: .seconds(1.2))
                    playProgress = nil
                    isPlaying = false
                    break
                }
                playProgress = t
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func stopPlay() {
        playTask?.cancel()
        playProgress = nil
        isPlaying = false
    }

    // MARK: - Context row

    private var contextRow: some View {
        HStack(alignment: .top, spacing: 0) {
            // 왼쪽: 거리/시간 위, 날짜/요일/시간 아래
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(distanceText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.chartElev)
                    Text(" · ")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text(durationText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.yellow)
                    if let pace = paceText {
                        Text(" · ")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.45))
                        Text(pace)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "5CE5D5"))
                    }
                }
                if dateText != nil || weekdayText != nil || startTimeText != nil {
                    HStack(spacing: 5) {
                        if let d = dateText {
                            Text(d)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                        if let w = weekdayText {
                            Text(w)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.yellow.opacity(0.85))
                        }
                        if let t = startTimeText {
                            Text(t)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                    }
                }
            }

            Spacer(minLength: 6)

            // 오른쪽: 재생 버튼 + 날씨 위, 러닝화 아래
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    // Play / Stop button — left of weather badge
                    Button(action: { isPlaying ? stopPlay() : startPlay() }) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .frame(width: 36, height: 28)
                    .background(Color.white.opacity(0.10), in: Capsule())

                    if let weather = weatherText {
                        HStack(spacing: 3) {
                            Image(systemName: weatherIcon ?? "thermometer.medium")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.white)
                            Text(weather)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(hex: "5CE5D5"))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color(hex: "5CE5D5").opacity(0.12), in: Capsule())
                    }
                }
                if let shoe = shoeText {
                    Label(shoe, systemImage: "shoe.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.chartElev.opacity(0.90))
                }
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
    /// 점을 그라데이션으로 칠할 색 목록 — 심박 선이 존 색일 때 타일 점도 존 색으로 (선 = 타일 일치)
    var dotColors: [Color]? = nil
    let onTap: () -> Void

    private var titleStyle: AnyShapeStyle {
        if let dotColors, dotColors.count >= 2 {
            return AnyShapeStyle(LinearGradient(colors: dotColors, startPoint: .leading, endPoint: .trailing))
        }
        return AnyShapeStyle(layer.color)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                // Row 1: dot + name + range
                HStack(spacing: 4) {
                    Group {
                        if let dotColors, dotColors.count >= 2 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(LinearGradient(colors: dotColors, startPoint: .leading, endPoint: .trailing))
                        } else {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(layer.color)
                        }
                    }
                    .opacity(isOn ? 1.0 : 0.38)
                    .frame(width: 7, height: 7)
                    // 제목 = 차트 선 색 — 상세 격자처럼 색으로 읽힌다(점만으로는 작아 선과 짝짓기 어렵다).
                    // 심박은 선이 존 색 그라데이션이라 제목도 같은 그라데이션.
                    Text(layer.shortLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(titleStyle)
                        .opacity(isOn ? 1.0 : 0.38)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if layer.showsRange {
                        Text("\(layer.formattedRange(series.minValue))–\(layer.formattedRange(series.maxValue))")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color.white.opacity(isOn ? 0.68 : 0.24))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                // Row 2: avg value + unit
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    // 값 글꼴은 상세 격자 셀과 **같은 값**을 쓰고 크기만 줄인다(§5.8) —
                    // 굵기·폭을 따로 정하면 같은 숫자가 화면마다 달라 보인다. 0.8은 타일이 더 촘촘해서.
                    Text(layer.formatted(series.displayValue))
                        .font(.system(size: RunMetricCellMetrics.value * 0.8, weight: .black))
                        .fontWidth(.condensed)
                        .foregroundStyle(Color.white.opacity(isOn ? 1.0 : 0.28))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(layer.unit)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(isOn ? 0.80 : 0.26))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Color.white.opacity(isOn ? 0.10 : 0.04),
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
                distanceText: "6.03 km",
                durationText: "37:50",
                weatherText: "☁️ 28°",
                dateText: "2026. 7. 28",
                weekdayText: "월요일",
                startTimeText: "오전 7:23",
                shoeText: "Nike Pegasus 40"
            )
            .padding(.vertical, 16)
        }
    }
    .preferredColorScheme(.dark)
}
