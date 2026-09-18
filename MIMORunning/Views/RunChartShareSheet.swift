import CoreLocation
import SwiftUI

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
    let paceText: String?
    var playProgress: Double? = nil
    /// 차트 높이 — 카드 전체가 영상과 같은 4:5(375pt)에 떨어지도록 시트가 계산해 넣는다.
    /// 기본값은 실측 전 첫 프레임용.
    var chartHeight: CGFloat = 226
    var palette: ShareChartPalette = .dark
    /// 영상 프레임은 0 — 직사각형 프레임 안에서 모서리가 배경색으로 남는다.
    var cornerRadius: CGFloat = 20
    /// 영상 프레임은 4:5 높이(375pt)로 고정한다. nil이면 내용 높이.
    var fixedHeight: CGFloat? = nil

    private let cardW: CGFloat = 300

    /// ⚠ §5.8 — 이미지 카드와 영상 프레임이 **이 뷰 하나**를 그린다. 헤더·타일을 영상 쪽에서
    ///   따로 그리던 시절엔 글꼴·여백·세로 위치가 하나씩 어긋나 여덟 번을 따로 맞췄다.
    var body: some View {
        VStack(spacing: 0) {
            // 차트 영역
            VStack(spacing: 0) {
                RunChartShareHeader(
                    distanceText: distanceText, durationText: durationText,
                    weatherText: weatherText, weatherIcon: weatherIcon,
                    dateText: dateText, weekdayText: weekdayText,
                    startTimeText: startTimeText, shoeText: shoeText,
                    paceText: paceText, palette: palette)

                RunCombinedChartView(data: data, enabledLayers: enabledLayers, chartHeight: chartHeight,
                                    playProgress: playProgress)
                    .environment(\.shareChartPalette, palette)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
            }
            // 차트 구역도 카드와 같은 표면(sectionBackground). `background`는 영상 프레임 채움용이라
            // 다크에서 순검정이어서, 여기 쓰면 타일 패널(15151A)과 이음새가 생겼다.
            .background(palette.sectionBackground)

            RunChartShareTiles(data: data, enabledLayers: enabledLayers, palette: palette)
        }
        .frame(width: cardW, height: fixedHeight, alignment: .top)
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// 카드 헤더 — 이미지 카드와 영상 프레임(경로 모드 포함)이 **같은 뷰**를 그린다(§5.8).
struct RunChartShareHeader: View {
    let distanceText: String
    let durationText: String
    let weatherText: String?
    let weatherIcon: String?
    let dateText: String?
    let weekdayText: String?
    let startTimeText: String?
    let shoeText: String?
    let paceText: String?
    var palette: ShareChartPalette = .dark

    var body: some View {
        contextRow
            .padding(.horizontal, 12)
            .padding(.top, 8)
    }

    /// 헤더 — 다크·라이트가 **같은 레이아웃**을 쓰고 색만 팔레트에서 가져온다.
    ///
    /// ⚠ 예전에는 라이트만 3행(워드마크+날씨/신발 세로, 거리 히어로 23pt, 날짜 줄)이라
    ///   내보낸 이미지가 다크보다 43pt 길었다(369 vs 326). 같은 카드가 테마마다 크기가
    ///   달라지면 안 된다 — §5.8.
    @ViewBuilder
    private var contextRow: some View {
        let chipBg: Color = palette.isLight ? Color(hex: "F2F1ED") : .white.opacity(0.10)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 0) {
                MIMOWordmark(size: 9, strokeMIMO: palette.isLight)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    if let d = dateText {
                        Text(d).font(.system(size: 9)).foregroundStyle(palette.textSecondary)
                    }
                    if let w = weekdayText {
                        Text(w).font(.system(size: 9, weight: .medium)).foregroundStyle(palette.textSecondary)
                    }
                    if let t = startTimeText {
                        Text(t).font(.system(size: 9)).foregroundStyle(palette.textSecondary)
                    }
                    if let weather = weatherText {
                        let celsius = parseCelsius(from: weather)
                        let iColor = weatherIconColor(systemName: weatherIcon, celsius: celsius, isLight: palette.isLight)
                        let tColor: Color = palette.isLight
                            ? (celsius.map { temperatureColor($0, isLight: true) } ?? iColor)
                            : palette.textPrimary.opacity(0.8)
                        HStack(spacing: 3) {
                            Image(systemName: weatherIcon ?? "thermometer.medium")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(iColor)
                            Text(weather)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(tColor)
                                .fixedSize()
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(chipBg, in: Capsule())
                        .fixedSize()
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            HStack(alignment: .center, spacing: 0) {
                // 중립 위계 — 지표 색을 쓰지 않는다
                Text(distanceText)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(" · ")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.textPrimary.opacity(0.25))
                Text(durationText)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textPrimary.opacity(0.75))
                if let pace = paceText {
                    Text(" · ")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.textPrimary.opacity(0.25))
                    Text(pace)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(palette.textPrimary.opacity(0.75))
                }
                Spacer(minLength: 6)
                if let shoe = shoeText {
                    Label(shoe, systemImage: "shoe.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// 지표 타일 격자 — 이미지 카드와 영상 프레임이 **같은 뷰**를 그린다(§5.8).
/// 값 전용(유산소·칼로리)은 항상, 나머지는 켜진 레이어만. 비어 있으면 아무것도 그리지 않는다.
struct RunChartShareTiles: View {
    let data: RunChartData
    let enabledLayers: Set<RunChartLayer>
    var palette: ShareChartPalette = .dark

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    static func activeTiles(data: RunChartData, enabledLayers: Set<RunChartLayer>) -> [RunChartLayer] {
        data.availableLayers.filter { $0.hasTile && ($0.isValueOnly || enabledLayers.contains($0)) }
    }

    var body: some View {
        let tiles = Self.activeTiles(data: data, enabledLayers: enabledLayers)
        if !tiles.isEmpty {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(tiles) { layer in
                    if let series = data.series[layer] {
                        ShareStatTile(layer: layer, series: series, palette: palette)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 4)
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
    let paceText: String?
    var totalDuration: TimeInterval = 0
    var routeCoordinates: [CLLocationCoordinate2D] = []

    // 앱 종합 패널과 **같은 저장소**를 본다 — 레이어는 거기서 타일을 눌러 고르고,
    // 내보내기는 화면에서 본 그대로를 낸다. 시트에 선택 UI를 또 두면 같은 결정을 두 곳에서 하게 된다.
    @State private var store = RunChartLayerStore.shared
    /// 카드를 4:5로 떨어뜨리는 차트 높이. ImageRenderer로 잰 카드 높이에서 차트 몫을 빼
    /// 나머지(헤더·타일)를 알아낸 뒤 남는 자리를 차트에 준다 — 타일 수나 글꼴이 바뀌어도 따라간다.
    /// 예전에는 52+228+타일수×44 같은 상수로 어림해, 글꼴을 키울 때마다 어긋났다.
    @State private var fittedChartH: CGFloat = 226

    /// 미리보기 좌우 여백 — 이미지·영상이 **같은 폭**으로 보이도록 한 곳에서만 정한다.
    /// 예전에는 이미지 24pt(−48), 영상 20pt라 8pt 차이로 미묘하게 달라 보였다.
    private static let previewSideInset: CGFloat = 20

    /// 영상과 같은 4:5. 1350px ÷ 3.6 = 375pt.
    private var targetCardH: CGFloat {
        CGFloat(RunChartReplayExporter.videoH) / RunChartReplayExporter.scale
    }
    @Environment(\.dismiss) private var dismiss
    @State private var isRendering = false
    @State private var renderedImage: UIImage? = nil
    @State private var showActivitySheet = false

    // Video export
    private enum ExportMode { case image, video }
    @State private var exportMode: ExportMode = .video
    @State private var videoContent: ReplayContent = .routeChart
    @State private var videoDuration: TimeInterval = 15
    @State private var isExportingVideo = false
    @State private var videoProgress: Double = 0
    @State private var exportedVideo: SharableVideoFile? = nil
    @State private var videoExportTask: Task<Void, Never>? = nil
    @State private var previewImage: UIImage? = nil
    @State private var isLoadingPreview = false
    @State private var previewTask: Task<Void, Never>? = nil
    // 다른 공유 카드(구간·경로·성장·주간·요약)가 모두 다크로 시작한다 — 여기만 라이트라
    // 앱에서 넘어오면 카드와 그 안의 지도가 갑자기 밝아졌다.
    @State private var shareTheme: ShareTheme = .dark

    private let cardW: CGFloat = 300
    private let L = AppLanguage.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // 스크롤로 감싼다 — 예전에는 그냥 VStack이라 내용이 화면을 넘으면 SwiftUI가
                    // 가장 잘 줄어드는 것을 눌렀다. 이미지 모드 미리보기(약 490pt)가 영상(441pt)보다
                    // 커서, 이미지에서만 모드 칩 글자가 minimumScaleFactor까지 쪼그라들었다.
                    ScrollView { shareOptions }

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
            .navigationTitle(L.s("차트 내보내기", "Export Chart"))
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

    @ViewBuilder
    private var shareOptions: some View {
        VStack(spacing: 0) {
                    // (a) 미리보기 — 이미지 모드: 정적 카드 / 영상 모드: 실제 렌더 프레임
                    if exportMode == .image {
                        GeometryReader { geo in
                            let scale = (geo.size.width - Self.previewSideInset * 2) / cardW
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
                                shoeText: shoeText,
                                paceText: paceText,
                                chartHeight: fittedChartH,
                                palette: shareTheme.palette
                            )
                            .environment(\.colorScheme, shareTheme == .dark ? .dark : .light)
                            .scaleEffect(scale, anchor: .top)
                            .frame(width: geo.size.width, alignment: .center)
                        }
                        // 영상 미리보기와 **같은 식**으로 높이를 잡는다 — 4:5 고정.
                        // 카드 자체는 refitChartHeight()가 375pt에 맞춰 둔다.
                        .frame(height: targetCardH * previewScale)
                        .clipped()
                        .padding(.top, 20)
                    } else {
                        // 영상 모드: 실제 프레임(비동기 로딩)
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.04))
                            if isLoadingPreview {
                                ProgressView().tint(.secondary)
                            } else if let img = previewImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        // 내보내는 영상과 같은 비율 — 숫자를 따로 적으면 한쪽만 바뀐다.
                        .aspectRatio(CGFloat(RunChartReplayExporter.videoW)
                                     / CGFloat(RunChartReplayExporter.videoH), contentMode: .fit)
                        .padding(.horizontal, Self.previewSideInset)
                        .padding(.top, 20)
                    }

                    // (d) 컨트롤 바 — 모드(이미지/영상) + 테마는 항상, 영상 내용은 **영상 모드에서만**.
                    // 예전에는 다섯을 한 줄에 균등 분할하고 이미지 모드에서 두 칸을 비활성으로 남겼다.
                    // 한 칸이 66pt뿐이라 "차트+데이터"가 꽉 차고, 죽은 칸 둘이 UI가 망가진 것처럼 보였다.
                    // 영상의 하위 옵션을 모드와 같은 높이로 늘어놓은 것 자체가 위계를 감춘다.
                    let hasRoute = routeCoordinates.count >= 2
                    HStack(spacing: 5) {
                        controlChip(L.s("이미지", "Image"),
                                    isOn: exportMode == .image) {
                            exportMode = .image
                        }
                        controlChip(L.s("영상", "Video"),
                                    isOn: exportMode == .video) {
                            exportMode = .video
                        }
                        controlChip(shareTheme == .light ? L.s("라이트", "Light") : L.s("다크", "Dark"),
                                    isOn: shareTheme == .light) {
                            shareTheme = shareTheme == .light ? .dark : .light
                            videoExportTask?.cancel()
                            exportedVideo = nil; isExportingVideo = false; videoProgress = 0
                            if exportMode == .video { refreshPreview() }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .onAppear {
                        refitChartHeight()   // 미리보기·내보내기보다 먼저 — 둘 다 이 값을 쓴다
                        if exportMode == .video { refreshPreview() }
                    }
                    .onChange(of: exportMode) { _, newMode in
                        videoExportTask?.cancel()
                        exportedVideo = nil
                        isExportingVideo = false
                        videoProgress = 0
                        if newMode == .video { refreshPreview() }
                    }
                    .onChange(of: store.enabled) { _, _ in
                        refitChartHeight()   // 타일 수가 바뀌면 차트 몫도 바뀐다
                        if exportMode == .video { refreshPreview() }
                    }
                    .onChange(of: videoDuration) { _, _ in
                        videoExportTask?.cancel()
                        exportedVideo = nil
                        isExportingVideo = false
                        videoProgress = 0
                    }
                    .onChange(of: shareTheme) { _, _ in
                        videoExportTask?.cancel()
                        exportedVideo = nil
                        isExportingVideo = false
                        videoProgress = 0
                        if exportMode == .video { refreshPreview() }
                    }

                    // (d-2) 영상 내용 — 영상 모드의 하위 옵션이라 모드 줄 아래에 따로 둔다.
                    if exportMode == .video {
                        HStack(spacing: 5) {
                            controlChip(L.s("차트+데이터", "Chart+Data"),
                                        isOn: videoContent == .chartData) {
                                videoContent = .chartData
                                videoExportTask?.cancel()
                                exportedVideo = nil; isExportingVideo = false; videoProgress = 0
                                refreshPreview()
                            }
                            controlChip(L.s("경로+차트", "Route+Chart"),
                                        isOn: videoContent == .routeChart,
                                        isDisabled: !hasRoute) {
                                videoContent = .routeChart
                                videoExportTask?.cancel()
                                exportedVideo = nil; isExportingVideo = false; videoProgress = 0
                                refreshPreview()
                            }
                            // 빈 칸 — 위 줄(3칸)과 같은 폭이 되게 한다. 두 칸만 두면 칩이 110→174pt로
                            // 늘어나 같은 글자가 위아래 줄에서 다르게 보인다.
                            // ⚠ maxHeight를 0으로 묶어야 한다. Color는 양방향으로 공간을 다 차지하는
                            //   뷰라, 세로 ScrollView 안에서는 HStack 높이를 통째로 늘려버린다.
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                    }

                    // (e) 영상 옵션 (영상 모드만)
                    if exportMode == .video {

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
                                ForEach([10.0, 15.0], id: \.self) { d in
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

                    }

        }
    }

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
                        Text(L.s("영상 내보내기", "Export Video"))
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
                             ? L.s("영상 만드는 중…", "Rendering…")
                             : L.s("영상 내보내기", "Export Video"))
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
                    paceText: paceText,
                    totalDuration: totalDuration,
                    routeCoordinates: routeCoordinates,
                    content: videoContent,
                    duration: videoDuration,
                    chartHeight: fittedChartH,
                    palette: shareTheme.palette,
                    onProgress: { p in videoProgress = p }
                )
                exportedVideo = SharableVideoFile(url: url)
                presentShareSheet(url: url)
            } catch {
                // silently reset on cancellation or failure
            }
            isExportingVideo = false
        }
    }

    private func presentShareSheet(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = scene.keyWindow?.rootViewController else { return }
        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }
        guard !(topVC is UIActivityViewController) else { return }
        // iPad: popover 앵커 없으면 크래시 → 화면 중앙 고정
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        topVC.present(activityVC, animated: true)
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
                paceText: paceText,
                totalDuration: totalDuration,
                routeCoordinates: routeCoordinates,
                content: videoContent,
                progress: 0.45,
                chartHeight: fittedChartH,
                palette: shareTheme.palette
            )
            guard !Task.isCancelled else { return }
            previewImage = img
            isLoadingPreview = false
        }
    }

    /// 카드를 4:5(375pt)에 맞추는 차트 높이를 **ImageRenderer로** 잰다.
    /// 화면 실측(PreferenceKey)에 기대면 시트가 영상 모드로 열릴 때 이미지 미리보기가 그려지지 않아
    /// 영상이 기본값(226)으로 375를 넘겨 타일 아래가 잘렸다. 출력도 ImageRenderer라 이쪽이 더 정확하다.
    /// 차트 외 높이(헤더·타일)는 차트 높이와 무관하므로 한 번에 나온다.
    private func refitChartHeight() {
        let probeChartH: CGFloat = 226
        let probe = RunChartShareCard(
            data: data, enabledLayers: store.enabled,
            distanceText: distanceText, durationText: durationText,
            weatherText: weatherText, weatherIcon: weatherIcon,
            dateText: dateText, weekdayText: weekdayText,
            startTimeText: startTimeText, shoeText: shoeText,
            paceText: paceText, chartHeight: probeChartH, palette: shareTheme.palette
        )
        .environment(\.colorScheme, shareTheme == .dark ? .dark : .light)
        let r = ImageRenderer(content: probe)
        r.scale = RunChartReplayExporter.scale
        r.proposedSize = ProposedViewSize(width: cardW, height: nil)
        guard let img = r.cgImage else { return }
        let rest = CGFloat(img.height) / RunChartReplayExporter.scale - probeChartH
        let want = min(max(targetCardH - rest, 120), 300)
        guard abs(want - fittedChartH) > 0.5 else { return }
        fittedChartH = want
        #if DEBUG
        print(String(format: "[차트공유] 카드 4:5 맞춤 — 차트 외 %.0fpt · 차트 %.0fpt · 총 %.0fpt (목표 %.0f)",
                     rest, want, rest + want, targetCardH))
        #endif
    }

    /// 카드 좌표계 → 화면 폭 배율. 미리보기 프레임과 카드 렌더가 같은 값을 써야 한다.
    private var previewScale: CGFloat { (UIScreen.main.bounds.width - Self.previewSideInset * 2) / cardW }


    private func controlChip(_ label: String, isOn: Bool, isDisabled: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(label)
                .font(.system(size: 10.5, weight: isOn ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(isOn ? Theme.violet.opacity(0.18) : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.45)
                                 : isOn ? Theme.violet : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func renderAndShare() {
        guard !isRendering else { return }
        isRendering = true
        let palette = shareTheme.palette
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
            shoeText: shoeText,
            paceText: paceText,
            chartHeight: fittedChartH,
            palette: palette
        )
        // 폭 1080px 고정 (scale 3.6). 높이는 미리보기가 맞춰 둔 4:5 — 영상과 같은 비율이라
        // 인스타그램이 잘라내지 않고, 같은 러닝의 이미지와 영상이 같아 보인다(§5.8).
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, shareTheme == .dark ? .dark : .light))
        renderer.scale = 1080.0 / cardW   // 정확히 1080px 폭
        renderer.proposedSize = ProposedViewSize(width: cardW, height: nil)
        renderedImage = renderer.uiImage
        #if DEBUG
        if let img = renderedImage {
            print(String(format: "[차트공유] 이미지 출력 %.0f×%.0fpx · 영상 %d×%dpx",
                         img.size.width * img.scale, img.size.height * img.scale,
                         RunChartReplayExporter.videoW, RunChartReplayExporter.videoH))
        }
        #endif
        isRendering = false
        if renderedImage != nil { showActivitySheet = true }
    }
}

// MARK: - ShareStatTile

private struct ShareStatTile: View {
    let layer: RunChartLayer
    let series: RunChartSeries
    let palette: ShareChartPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(palette.layerColor(layer))
                    .frame(width: 6, height: 6)
                Text(layer.shortLabel)
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.textPrimary.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                if layer.showsRange {
                    Text("\(layer.formattedRange(series.minValue))–\(layer.formattedRange(series.maxValue))")
                        .font(.system(size: 8.5))
                        .foregroundStyle(palette.textPrimary.opacity(0.68))
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                // 앱 타일과 같은 상수에 묶는다 — 카드 폭(300)이 앱 패널(약 358)의 0.84라
                // 앱의 0.8보다 한 단계 작은 0.7을 쓴다. 숫자를 따로 적으면 한쪽만 바뀐다(§5.8).
                Text(layer.formatted(series.displayValue))
                    .font(.system(size: RunMetricCellMetrics.value * 0.7, weight: .black))
                    .fontWidth(.condensed)
                    .foregroundStyle(palette.textPrimary)
                    .minimumScaleFactor(0.80)
                    .lineLimit(1)
                Text(layer.unit)
                    .font(.system(size: 8.5))
                    .foregroundStyle(palette.textPrimary.opacity(0.80))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        // 지표 셀과 같은 박스 규칙 — 표면색 채움 + 라이트에서만 옅은 테두리.
        // 카드 표면이 흰 한 장이라 채움만으로는 셀 경계가 안 보인다.
        .background {
            let r = RoundedRectangle(cornerRadius: 9)
            r.fill(palette.isLight ? Color.white : palette.textPrimary.opacity(0.08))
                .overlay(r.stroke(palette.isLight ? Color.black.opacity(0.10) : .clear,
                                  lineWidth: palette.isLight ? 0.5 : 0))
        }
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
        shoeText: nil,
        paceText: "6'46\""
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
            shoeText: nil,
            paceText: "6'46\""
        )
    }
    .preferredColorScheme(.dark)
}
