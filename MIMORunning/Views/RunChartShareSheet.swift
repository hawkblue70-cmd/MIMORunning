import CoreLocation
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
// RunCombinedPanelView 와 동일한 레이아웃 — 미리보기·ImageRenderer 출력 공용

struct RunChartShareCard: View {
    let data: RunChartData
    let enabledLayers: Set<RunChartLayer>
    let distanceText: String
    let durationText: String
    let weatherText: String?
    let weatherIcon: String?
    let dateText: String?
    let weekdayText: String?
    let startTimeText: String?
    let shoeText: String?
    var playProgress: Double? = nil

    private let cardW: CGFloat = 300
    private let tileColumns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 차트 영역 — 검정 배경 (RunCombinedPanelView 동일)
            VStack(spacing: 0) {
                contextRow
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                RunCombinedChartView(data: data, enabledLayers: enabledLayers, chartHeight: 218,
                                    playProgress: playProgress)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }
            .background(Color.black)

            // 지표 타일 — 값 전용(유산소·칼로리) 항상 표시, 나머지는 켜진 레이어만
            let activeTiles = data.availableLayers.filter {
                $0.isValueOnly || enabledLayers.contains($0)
            }
            if !activeTiles.isEmpty {
                LazyVGrid(columns: tileColumns, spacing: 3) {
                    ForEach(activeTiles) { layer in
                        if let series = data.series[layer] {
                            ShareStatTile(layer: layer, series: series)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 4)
            }
        }
        .frame(width: cardW)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var contextRow: some View {
        HStack(alignment: .top, spacing: 0) {
            // 왼쪽: MIMO RUNNING 워드마크 → 거리/시간 → 날짜/요일/시간
            VStack(alignment: .leading, spacing: 4) {
                // 워드마크 — 거리 위
                HStack(spacing: 2) {
                    Text("MIMO")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(Theme.violet)
                    Text("RUNNING")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white)
                }
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
                }
                if dateText != nil || weekdayText != nil || startTimeText != nil {
                    HStack(spacing: 4) {
                        if let d = dateText {
                            Text(d)
                                .font(.system(size: 9))
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                        if let w = weekdayText {
                            Text(w)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.yellow.opacity(0.85))
                        }
                        if let t = startTimeText {
                            Text(t)
                                .font(.system(size: 9))
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                    }
                }
            }

            Spacer(minLength: 6)

            // 오른쪽: 날씨(기온) 위, 러닝화 아래
            VStack(alignment: .trailing, spacing: 4) {
                if let weather = weatherText {
                    HStack(spacing: 3) {
                        Image(systemName: weatherIcon ?? "thermometer.medium")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white)
                        Text(weather)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(hex: "5CE5D5"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: "5CE5D5").opacity(0.12), in: Capsule())
                }
                if let shoe = shoeText {
                    Label(shoe, systemImage: "shoe.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.chartElev.opacity(0.90))
                }
            }
        }
    }
}

// MARK: - RunChartShareSheet

struct RunChartShareSheet: View {
    let data: RunChartData
    let distanceText: String
    let durationText: String
    let weatherText: String?
    let weatherIcon: String?
    let dateText: String?
    let weekdayText: String?
    let startTimeText: String?
    let shoeText: String?
    var totalDuration: TimeInterval = 0
    var routeCoordinates: [CLLocationCoordinate2D] = []

    @State private var store = RunChartShareStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isRendering = false
    @State private var renderedImage: UIImage? = nil
    @State private var showActivitySheet = false

    // Video export
    private enum ExportMode { case image, video }
    @State private var exportMode: ExportMode = .image
    @State private var videoContent: ReplayContent = .chartData
    @State private var videoDuration: TimeInterval = 10
    @State private var isExportingVideo = false
    @State private var videoProgress: Double = 0
    @State private var exportedVideo: SharableVideoFile? = nil
    @State private var videoExportTask: Task<Void, Never>? = nil
    @State private var previewImage: UIImage? = nil
    @State private var isLoadingPreview = false
    @State private var previewTask: Task<Void, Never>? = nil

    private let cardW: CGFloat = 300
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
                            distanceText: distanceText,
                            durationText: durationText,
                            weatherText: weatherText,
                            weatherIcon: weatherIcon,
                            dateText: dateText,
                            weekdayText: weekdayText,
                            startTimeText: startTimeText,
                            shoeText: shoeText
                        )
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: geo.size.width, alignment: .center)
                    }
                    .frame(height: previewHeight)
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

                    // (c) 레이어 칩 — 값 전용 제외, 한 줄 가로 스크롤
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(data.availableLayers.filter { !$0.isValueOnly }) { layer in
                                ShareLayerChip(
                                    layer: layer,
                                    isOn: store.enabled.contains(layer)
                                ) {
                                    store.toggle(layer)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 8)

                    // (d) 이미지 / 영상 모드 선택
                    Picker("", selection: $exportMode) {
                        Text(L.s("이미지", "Image")).tag(ExportMode.image)
                        Text(L.s("영상", "Video")).tag(ExportMode.video)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .onChange(of: exportMode) { _, newMode in
                        videoExportTask?.cancel()
                        exportedVideo = nil
                        isExportingVideo = false
                        videoProgress = 0
                        if newMode == .video { refreshPreview() }
                    }
                    .onChange(of: store.enabled) { _, _ in
                        if exportMode == .video { refreshPreview() }
                    }

                    // (e) 영상 옵션 (영상 모드만)
                    if exportMode == .video {
                        let hasRoute = routeCoordinates.count >= 2

                        // (e-1) 내용 선택: 데이터 / 경로 / 둘 다
                        HStack {
                            Text(L.s("내용", "Content"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                        HStack(spacing: 6) {
                            ForEach(ReplayContent.allCases, id: \.self) { mode in
                                let disabled = (mode == .routeData || mode == .routeChart) && !hasRoute
                                let label = mode == .chartData ? L.s("차트+데이터", "Chart+Data")
                                    : mode == .routeData ? L.s("경로+데이터", "Route+Data")
                                    : L.s("경로+차트", "Route+Chart")
                                Button(label) {
                                    videoContent = mode
                                    refreshPreview()
                                }
                                .font(.system(size: 11, weight: videoContent == mode ? .semibold : .regular))
                                .padding(.horizontal, 14).padding(.vertical, 5)
                                .background(videoContent == mode
                                            ? Theme.violet.opacity(0.18)
                                            : Color.white.opacity(0.06))
                                .foregroundStyle(disabled ? Color.secondary.opacity(0.4)
                                                : videoContent == mode ? Theme.violet : .secondary)
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                                .disabled(disabled)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                        // (e-2) 영상 길이
                        HStack {
                            Text(L.s("영상 길이", "Duration"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach([6.0, 10.0, 15.0], id: \.self) { d in
                                    Button("\(Int(d))s") { videoDuration = d }
                                        .font(.system(size: 11,
                                                      weight: videoDuration == d ? .semibold : .regular))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 5)
                                        .background(videoDuration == d
                                                    ? Theme.violet.opacity(0.18)
                                                    : Color.white.opacity(0.06))
                                        .foregroundStyle(videoDuration == d ? Theme.violet : .secondary)
                                        .clipShape(Capsule())
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 6)

                        // (e-3) 모드 미리보기 (실제 지도 포함 — 비동기 로딩)
                        Group {
                            if isLoadingPreview {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            } else if let img = previewImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    }

                    Spacer()

                    // (f) 공유 버튼 (이미지) / 내보내기+공유 버튼 (영상)
                    if exportMode == .image {
                        Button(action: renderAndShare) {
                            HStack(spacing: 8) {
                                if isRendering {
                                    ProgressView().tint(.white).scaleEffect(0.8)
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
                    } else {
                        videoExportArea
                    }
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
        .onDisappear {
            videoExportTask?.cancel()
            previewTask?.cancel()
        }
    }

    // MARK: - Video export

    private var videoExportArea: some View {
        Group {
            if let video = exportedVideo {
                // Export complete: show ShareLink
                ShareLink(
                    item: video,
                    preview: SharePreview(L.s("차트 영상", "Chart Video"),
                                         image: Image(systemName: "video"))
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                        Text(L.s("공유하기", "Share"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(.white)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Button(action: startVideoExport) {
                    HStack(spacing: 8) {
                        if isExportingVideo {
                            ProgressView(value: videoProgress)
                                .progressViewStyle(.linear)
                                .tint(.white)
                                .frame(width: 80)
                        } else {
                            Image(systemName: "video.fill")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Text(isExportingVideo
                             ? L.s("렌더링 중…", "Rendering…")
                             : L.s("영상 만들기", "Export Video"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(.white)
                    .background(isExportingVideo ? Theme.violet.opacity(0.55) : Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isExportingVideo)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func startVideoExport() {
        guard !isExportingVideo else { return }
        isExportingVideo = true
        exportedVideo = nil
        videoProgress = 0
        videoExportTask = Task { @MainActor in
            do {
                let url = try await RunChartReplayExporter.export(
                    data: data,
                    enabledLayers: store.enabled,
                    distanceText: distanceText,
                    durationText: durationText,
                    weatherText: weatherText,
                    weatherIcon: weatherIcon,
                    dateText: dateText,
                    weekdayText: weekdayText,
                    startTimeText: startTimeText,
                    shoeText: shoeText,
                    totalDuration: totalDuration,
                    routeCoordinates: routeCoordinates,
                    content: videoContent,
                    duration: videoDuration,
                    onProgress: { p in videoProgress = p }
                )
                exportedVideo = SharableVideoFile(url: url)
            } catch {
                // silently reset on cancellation or failure
            }
            isExportingVideo = false
        }
    }

    private func refreshPreview() {
        previewTask?.cancel()
        isLoadingPreview = true
        previewImage = nil
        previewTask = Task { @MainActor in
            let img = await RunChartReplayExporter.previewFrame(
                data: data, enabledLayers: store.enabled,
                distanceText: distanceText, durationText: durationText,
                weatherText: weatherText, weatherIcon: weatherIcon,
                dateText: dateText, weekdayText: weekdayText,
                startTimeText: startTimeText, shoeText: shoeText,
                totalDuration: totalDuration,
                routeCoordinates: routeCoordinates,
                content: videoContent,
                progress: 0.45
            )
            guard !Task.isCancelled else { return }
            previewImage = img
            isLoadingPreview = false
        }
    }

    // 미리보기 높이 추정 (타일 수에 따라 가변)
    private var previewHeight: CGFloat {
        let screenW = UIScreen.main.bounds.width
        let scale = (screenW - 48) / cardW
        let tileRows = (data.availableLayers.count + 2) / 3
        let tilesH = CGFloat(tileRows) * 44 + CGFloat(max(0, tileRows - 1)) * 3 + 8
        return (52 + 228 + tilesH) * scale
    }

    private func renderAndShare() {
        guard !isRendering else { return }
        isRendering = true
        let card = RunChartShareCard(
            data: data,
            enabledLayers: store.enabled,
            distanceText: distanceText,
            durationText: durationText,
            weatherText: weatherText,
            weatherIcon: weatherIcon,
            dateText: dateText,
            weekdayText: weekdayText,
            startTimeText: startTimeText,
            shoeText: shoeText
        )
        // 폭 1080px 고정 (scale 3.6), 높이는 콘텐츠에 맞게 자연 결정
        // Instagram 업로드 시 자체 크롭 UI로 4:5 조정 가능
        let renderer = ImageRenderer(content: card.preferredColorScheme(.dark))
        renderer.scale = 1080.0 / cardW   // 정확히 1080px 폭
        renderer.proposedSize = ProposedViewSize(width: cardW, height: nil)
        renderedImage = renderer.uiImage
        isRendering = false
        if renderedImage != nil { showActivitySheet = true }
    }
}

// MARK: - ShareLayerChip

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
                    .lineLimit(1)
                    .fixedSize()
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

private struct ShareStatTile: View {
    let layer: RunChartLayer
    let series: RunChartSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(layer.color)
                    .frame(width: 6, height: 6)
                Text(layer.shortLabel)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                if !layer.isValueOnly {
                    Text("\(layer.formattedRange(series.minValue))–\(layer.formattedRange(series.maxValue))")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(layer.formatted(series.avgValue))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.80)
                    .lineLimit(1)
                Text(layer.unit)
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
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
        distanceText: "7.05 km",
        durationText: "47:44",
        weatherText: "23°C",
        weatherIcon: "cloud.sun.fill",
        dateText: "2026. 7. 27",
        weekdayText: "일요일",
        startTimeText: "오전 7:06",
        shoeText: nil
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
            distanceText: "7.05 km",
            durationText: "47:44",
            weatherText: "23°C",
            weatherIcon: "cloud.sun.fill",
            dateText: "2026. 7. 27",
            weekdayText: "일요일",
            startTimeText: "오전 7:06",
            shoeText: nil
        )
    }
    .preferredColorScheme(.dark)
}
