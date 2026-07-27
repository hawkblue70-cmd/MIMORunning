import SwiftUI

// MARK: - RunChartShareStore
// 공유 전용 레이어 선택 상태 — 상세 화면의 RunChartLayerStore 와 완전히 분리

@Observable @MainActor
final class RunChartShareStore {
    static let shared = RunChartShareStore()
    private static let key = "mimo.runChart.shareLayers"

    var enabled: Set<RunChartLayer> {
        didSet { persist() }
    }

    private init() {
        if let raw = UserDefaults.standard.array(forKey: Self.key) as? [String] {
            let restored = Set(raw.compactMap { RunChartLayer(rawValue: $0) })
            enabled = restored.isEmpty ? [.heartRate, .pace] : restored
        } else {
            enabled = [.heartRate, .pace]
        }
    }

    private func persist() {
        UserDefaults.standard.set(enabled.map(\.rawValue), forKey: Self.key)
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

// MARK: - RunChartShareCard
// 미리보기와 출력이 동일한 뷰 — ImageRenderer 에 직접 전달

struct RunChartShareCard: View {
    let data: RunChartData
    let enabledLayers: Set<RunChartLayer>
    let summaryText: String
    let weatherText: String?
    let dateText: String

    private let cardW: CGFloat = 300
    private let cardH: CGFloat = 375
    private let tileColumns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // (a) 워드마크
            HStack(spacing: 0) {
                Text("MIMO")
                    .font(.system(size: 9, weight: .black))
                    .tracking(2)
                    .foregroundStyle(.white)
                Text(" RUNNING")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.violet)
            }

            Spacer().frame(height: 12)

            // (b) 요약 + 날짜 + 날씨 뱃지
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summaryText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                    Text(dateText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let weather = weatherText {
                    Text(weather)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
            }

            Spacer().frame(height: 10)

            // (c) 차트 — RunCombinedChartView 재사용 (미리보기·출력 동일성 보장)
            RunCombinedChartView(data: data, enabledLayers: enabledLayers, chartHeight: 160)

            Spacer().frame(height: 8)

            // (d) 켜진 레이어 타일 2열
            let activeTiles = data.availableLayers.filter { enabledLayers.contains($0) }
            if !activeTiles.isEmpty {
                LazyVGrid(columns: tileColumns, spacing: 6) {
                    ForEach(activeTiles) { layer in
                        if let series = data.series[layer] {
                            ShareStatTile(layer: layer, series: series)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: cardW, height: cardH)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - RunChartShareSheet

struct RunChartShareSheet: View {
    let data: RunChartData
    let summaryText: String
    let weatherText: String?
    let dateText: String

    @State private var store = RunChartShareStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isRendering = false
    @State private var renderedImage: UIImage? = nil
    @State private var showActivitySheet = false

    private let cardW: CGFloat = 300
    private let cardH: CGFloat = 375
    private let L = AppLanguage.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // (a) 미리보기 — 화면 폭에 맞게 축소, 실제 렌더 뷰와 동일
                    GeometryReader { geo in
                        let scale = (geo.size.width - 48) / cardW
                        RunChartShareCard(
                            data: data,
                            enabledLayers: store.enabled,
                            summaryText: summaryText,
                            weatherText: weatherText,
                            dateText: dateText
                        )
                        .frame(width: cardW, height: cardH)
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: geo.size.width, height: cardH * scale, alignment: .top)
                    }
                    .frame(height: scaledCardHeight)
                    .padding(.top, 20)

                    // (b) 지표 선택 레이블
                    HStack {
                        Text(L.s("차트에 넣을 지표", "Chart layers"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                    // (c) 레이어 칩 — data.availableLayers 만, RunCombinedPanelView 와 동일 디자인
                    HStack(spacing: 6) {
                        ForEach(data.availableLayers) { layer in
                            ShareLayerChip(
                                layer: layer,
                                isOn: store.enabled.contains(layer)
                            ) {
                                store.toggle(layer)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer()

                    // (d) 공유하기 버튼
                    Button(action: renderAndShare) {
                        HStack(spacing: 8) {
                            if isRendering {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            Text(L.s("공유하기", "Share"))
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(.white)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRendering)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(L.s("차트 공유", "Share Chart"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Theme.violet)
                }
            }
        }
        .sheet(isPresented: $showActivitySheet) {
            if let img = renderedImage {
                ShareSheet(images: [img])
            }
        }
    }

    // 미리보기 카드 높이 (scale 적용 후)
    private var scaledCardHeight: CGFloat {
        let screenW = UIScreen.main.bounds.width
        let scale = (screenW - 48) / cardW
        return cardH * scale
    }

    private func renderAndShare() {
        guard !isRendering else { return }
        isRendering = true
        let card = RunChartShareCard(
            data: data,
            enabledLayers: store.enabled,
            summaryText: summaryText,
            weatherText: weatherText,
            dateText: dateText
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: cardW, height: cardH)
        renderedImage = renderer.uiImage
        isRendering = false
        if renderedImage != nil { showActivitySheet = true }
    }
}

// MARK: - ShareLayerChip
// RunCombinedPanelView 의 RunLayerChip 과 동일 디자인

private struct ShareLayerChip: View {
    let layer: RunChartLayer
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(layer.color.opacity(isOn ? 1.0 : 0.35))
                    .frame(width: 8, height: 8)
                Text(layer.shortLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(isOn ? Color.primary : Color.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Color.white.opacity(isOn ? 0.08 : 0.04),
                in: RoundedRectangle(cornerRadius: 7)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ShareStatTile
// RunCombinedPanelView 의 RunStatTile 과 동일 디자인

private struct ShareStatTile: View {
    let layer: RunChartLayer
    let series: RunChartSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(layer.color)
                    .frame(width: 6, height: 6)
                Text(layer.shortLabel)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(layer.formatted(series.avgValue))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Text(layer.unit)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text("\(layer.formatted(series.minValue)) – \(layer.formatted(series.maxValue))")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Preview

#Preview("Sheet") {
    let totalKm = 7.05
    let n = 100
    let hrPoints: [RunChartPoint] = (0..<n).map { i in
        let km = Double(i) / Double(n - 1) * totalKm
        let norm = 0.45 + 0.3 * sin(Double(i) / 9.0)
        return RunChartPoint(km: km, value: 145 + norm * 30, norm: norm)
    }
    let hrSeries = RunChartSeries(layer: .heartRate, points: hrPoints,
                                  minValue: 130, maxValue: 178, avgValue: 156,
                                  minIndex: nil, maxIndex: nil)
    let pacePoints: [RunChartPoint] = (0..<7).map { i in
        let km = Double(i) + 0.5
        let raw = 385.0 + Double(i) * 5
        let norm = 1.0 - (raw - 360) / 90.0
        return RunChartPoint(km: km, value: raw, norm: max(0.1, min(1, norm)))
    }
    let paceSeries = RunChartSeries(layer: .pace, points: pacePoints,
                                    minValue: 360, maxValue: 450, avgValue: 400,
                                    minIndex: 0, maxIndex: 6)
    let data = RunChartData(
        totalKm: totalKm,
        series: [.heartRate: hrSeries, .pace: paceSeries],
        hrZoneBands: [(zone: 3, lowerBPM: 140, upperBPM: 160)],
        hrMin: 130,
        hrMax: 180,
        availableLayers: [.heartRate, .pace]
    )
    RunChartShareSheet(
        data: data,
        summaryText: "7.05 km · 47:44",
        weatherText: "23° · 습도 65%",
        dateText: "2026. 7. 27"
    )
}

#Preview("Card") {
    let totalKm = 7.05
    let n = 100
    let hrPoints: [RunChartPoint] = (0..<n).map { i in
        let km = Double(i) / Double(n - 1) * totalKm
        let norm = 0.45 + 0.3 * sin(Double(i) / 9.0)
        return RunChartPoint(km: km, value: 145 + norm * 30, norm: norm)
    }
    let hrSeries = RunChartSeries(layer: .heartRate, points: hrPoints,
                                  minValue: 130, maxValue: 178, avgValue: 156,
                                  minIndex: nil, maxIndex: nil)
    let pacePoints: [RunChartPoint] = (0..<7).map { i in
        let km = Double(i) + 0.5
        let raw = 385.0 + Double(i) * 5
        let norm = 1.0 - (raw - 360) / 90.0
        return RunChartPoint(km: km, value: raw, norm: max(0.1, min(1, norm)))
    }
    let paceSeries = RunChartSeries(layer: .pace, points: pacePoints,
                                    minValue: 360, maxValue: 450, avgValue: 400,
                                    minIndex: 0, maxIndex: 6)
    let data = RunChartData(
        totalKm: totalKm,
        series: [.heartRate: hrSeries, .pace: paceSeries],
        hrZoneBands: [(zone: 3, lowerBPM: 140, upperBPM: 160)],
        hrMin: 130,
        hrMax: 180,
        availableLayers: [.heartRate, .pace]
    )
    ZStack {
        Theme.background.ignoresSafeArea()
        RunChartShareCard(
            data: data,
            enabledLayers: [.heartRate, .pace],
            summaryText: "7.05 km · 47:44",
            weatherText: "23° · 습도 65%",
            dateText: "2026. 7. 27"
        )
    }
    .preferredColorScheme(.dark)
}
