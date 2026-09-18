import AVFoundation
import CoreLocation
import MapKit
import SwiftUI

// MARK: - ShareTheme / ShareChartPalette

enum ShareTheme { case dark, light
    var palette: ShareChartPalette { self == .light ? .light : .dark }
}

struct ShareChartPalette {
    // Theme flag
    let isLight: Bool
    // Backgrounds
    let background:        Color
    let cardBackground:    Color   // used for tiles panel
    let sectionBackground: Color   // used for header + chart sections (white in light, cardBackground in dark)
    let cardCornerRadius:  CGFloat // tiles panel corner radius (0 for dark, 9 for light)
    // Text
    let textPrimary:     Color
    // Wordmark
    let wordmarkMIMO:    Color
    let wordmarkRunning: Color
    // Chart canvas
    let gridLine:        Color
    let chartCasing:     Color
    let hrZones:         [Color]
    let hrRepColor:      Color   // HR representative color for chips/tiles (not zone-specific)
    let pace:            Color
    let elevation:       Color
    let elevFill:        Color
    let elevFillMaxOp:   Double
    let timeLabel:       Color
    // Secondary / axis label colors
    let textSecondary:   Color
    let axisLabelColor:  Color
    // Pace column
    let paceColFillOp:      Double
    let paceColBorderOp:    Double
    let paceColBorderWidth: CGFloat
    // Line width adjustment (dark: 0.0, light: -0.2 to pull back thicker base widths)
    let lineWidthAdjust:    CGFloat
    // Casing stroke add (both themes: 1.8)
    let casingWidthAdd:     CGFloat
    // HR line width (drawn separately in drawHRSegments — dark: 2.6, light: 2.4)
    let hrLineWidth:        CGFloat
    // X-axis label colors (separate from timeLabel / axisLabelColor)
    let xAxisTimeColor:     Color   // elapsed time row — yellow family
    let xAxisDistColor:     Color   // distance km row — neutral (black/white)
    let paceColLabelColor:  Color   // pace column km text
    // Scrubber + value label casing
    let scrubberBorderOp:   Double
    let valueLabelBgOp:     Double  // >0 → draw white text casing behind value labels
    // Map border
    let mapBorderOp:        Double
    // Route drawing (stored as Color; UIColor derived on the fly)
    let routeCasingColor: Color
    let mapBadgeBgColor:  Color

    var routeCasingUI: UIColor { UIColor(routeCasingColor) }
    var mapBadgeBgUI:  UIColor { UIColor(mapBadgeBgColor) }

    func layerColor(_ layer: RunChartLayer) -> Color {
        // HR representative color (chips/tiles use solid color; lines use zone gradient)
        if layer == .heartRate { return hrRepColor }
        // Light theme: same hue families as dark, darkened for white-background contrast
        if isLight {
            switch layer {
            case .pace:         return pace                     // #00A8C8 cyan
            case .cadence:      return Color(hex: "B8860B")    // 딥 골드
            case .elevation:    return elevation                // #4FA82E green
            case .power:        return Color(hex: "7C3AED")    // 딥 바이올렛 (다크 C77DFF의 어두운 짝)
            case .groundContact: return Color(hex: "3949AB")   // 딥 인디고 (다크 7B87FF의 어두운 짝)
            case .strideLength: return Color(hex: "3A3A3C")    // 진회색 (다크의 화이트에 대응)
            case .verticalOsc:  return Color(hex: "C2185B")    // 딥 마젠타 (다크 F050FF의 어두운 짝)
            default:            return layer.color
            }
        }
        // Dark theme: delegate to RunChartLayer.color (= Theme.chartXxx = [2] bright values)
        return layer.color
    }

    func hrZoneColor(for bpm: Double, data: RunChartData) -> Color {
        guard !data.hrZoneBands.isEmpty else { return hrZones.first ?? Theme.heartRate }
        let sorted = data.hrZoneBands.sorted { $0.lowerBPM < $1.lowerBPM }
        for band in sorted {
            if bpm < Double(band.upperBPM) {
                let idx = max(0, min(hrZones.count - 1, band.zone - 1))
                return hrZones[idx]
            }
        }
        let idx = max(0, min(hrZones.count - 1, (sorted.last?.zone ?? 1) - 1))
        return hrZones[idx]
    }

    static let dark = ShareChartPalette(
        isLight:           false,
        background:        .black,
        cardBackground:    Color(hex: "15151A"),
        sectionBackground: Color(hex: "15151A"),
        cardCornerRadius:  0,
        textPrimary:     .white,
        wordmarkMIMO:    Theme.violet,
        wordmarkRunning: .white,
        gridLine:        .white.opacity(0.45),
        chartCasing:     .black.opacity(0.85),
        hrZones: [                               // Apple Health zone colors (dark)
            Color(hex: "4C8DFF"),  // Z1 blue
            Color(hex: "40E0D0"),  // Z2 teal
            Color(hex: "C6F432"),  // Z3 lime
            Color(hex: "FF9F0A"),  // Z4 orange
            Color(hex: "FF375F"),  // Z5 pink
        ],
        hrRepColor:      Color(hex: "FF5247"),    // HR chip/tile representative red
        pace:            Theme.chartPace,         // #4DD0F5 cyan
        elevation:       Theme.chartElev,         // #8FE04D lime
        elevFill:        Theme.chartElev,
        elevFillMaxOp:   0.12,
        timeLabel:       Color.yellow.opacity(0.85),
        textSecondary:   .white.opacity(0.55),
        axisLabelColor:  .white,
        paceColFillOp:      0.14,
        paceColBorderOp:    0.16,
        paceColBorderWidth: 1.0,
        lineWidthAdjust:    0.0,
        casingWidthAdd:     1.8,
        hrLineWidth:        2.8,
        xAxisTimeColor:     Color(hex: "FFE04D"),
        xAxisDistColor:     .white,
        paceColLabelColor:  .white.opacity(0.7),
        scrubberBorderOp:   0.0,
        valueLabelBgOp:     0.0,
        mapBorderOp:        0.0,
        routeCasingColor: .black.opacity(0.85),
        mapBadgeBgColor:  .black.opacity(0.70)
    )

    static let light = ShareChartPalette(
        isLight:           true,
        background:        .white,
        // ⚠ 카드 표면은 한 장이어야 한다. 예전에는 타일 패널만 베이지(F4F3EF)라
        //   라이트에서 흰 차트 패널과 베이지 타일 패널이 박스 두 개로 보였다(다크는 두 값이 같아 안 보였다).
        cardBackground:    .white,                // tiles panel — 차트 영역과 같은 흰색
        sectionBackground: .white,                // header + chart sections (unified surface)
        cardCornerRadius:  9,
        textPrimary:     Color(hex: "1A1A1A"),
        wordmarkMIMO:    Color(hex: "5B3FD9"),
        wordmarkRunning: Color(hex: "1A1A1A"),
        gridLine:        Color(hex: "1A1A1A").opacity(0.15),
        chartCasing:     Color.white.opacity(0.95),
        hrZones: [                               // Apple Health zone colors (light)
            Color(hex: "1565C0"),  // Z1 dark blue
            Color(hex: "00897B"),  // Z2 teal
            Color(hex: "689F00"),  // Z3 olive-lime
            Color(hex: "E07800"),  // Z4 orange
            Color(hex: "D81B60"),  // Z5 deep pink
        ],
        hrRepColor:      Color(hex: "E0242B"),    // HR chip/tile representative red
        pace:            Color(hex: "00A8C8"),    // cyan (same hue as dark, darkened)
        elevation:       Color(hex: "00915A"),    // 스프링 그린의 어두운 짝 (다크 00E676)
        elevFill:        Color(hex: "00915A"),
        elevFillMaxOp:   0.13,
        timeLabel:       Color(hex: "555555"),
        textSecondary:   Color(hex: "757575"),
        axisLabelColor:  Color(hex: "8A8A8A"),
        paceColFillOp:      0.08,
        paceColBorderOp:    0.14,
        paceColBorderWidth: 0.8,
        lineWidthAdjust:    -0.2,
        casingWidthAdd:     1.8,
        hrLineWidth:        2.6,
        xAxisTimeColor:     Color(hex: "D4A700"),
        xAxisDistColor:     Color(hex: "111111"),
        paceColLabelColor:  Color(hex: "555555"),
        scrubberBorderOp:   0.10,
        valueLabelBgOp:     0.90,  // opacity for white text casing behind value labels
        mapBorderOp:        0.10,
        routeCasingColor: Color.white.opacity(0.90),
        mapBadgeBgColor:  Color.white.opacity(0.85)
    )
}

// MARK: - Weather / temperature color helpers

/// Returns a color for the temperature value based on theme.
func temperatureColor(_ celsius: Double, isLight: Bool) -> Color {
    if isLight {
        switch celsius {
        case ..<5:   return Color(hex: "0A84FF")
        case ..<15:  return Color(hex: "00A0A8")
        case ..<23:  return Color(hex: "2FA84F")
        case ..<29:  return Color(hex: "E07800")
        default:     return Color(hex: "E5342A")
        }
    } else {
        switch celsius {
        case ..<5:   return Color(hex: "4C9DFF")
        case ..<15:  return Color(hex: "40D8CE")
        case ..<23:  return Color(hex: "5EE07A")
        case ..<29:  return Color(hex: "FFA33C")
        default:     return Color(hex: "FF5247")
        }
    }
}

/// Parses a celsius value from a formatted weather string such as "18°C" or "맑음 21°".
func parseCelsius(from text: String) -> Double? {
    guard let range = text.range(of: #"-?\d+"#, options: .regularExpression) else { return nil }
    return Double(text[range])
}

/// Returns a condition-based color for a weather SF Symbol icon name.
/// Falls back to temperature color when celsius is provided, gray otherwise.
func weatherIconColor(systemName: String?, celsius: Double? = nil, isLight: Bool) -> Color {
    guard let name = systemName else {
        return celsius.map { temperatureColor($0, isLight: isLight) } ?? Color(hex: "7A8794")
    }
    let n = name.lowercased()
    if n.contains("sun") || n.contains("clear") { return Color(hex: "F5A623") }
    if n.contains("rain") || n.contains("drizzle") || n.contains("shower") { return Color(hex: "3B82F6") }
    if n.contains("snow") || n.contains("sleet") || n.contains("blizzard") || n.contains("hail") { return Color(hex: "7FC4FF") }
    if n.contains("cloud") || n.contains("fog") || n.contains("wind") || n.contains("overcast") { return Color(hex: "7A8794") }
    return celsius.map { temperatureColor($0, isLight: isLight) } ?? Color(hex: "7A8794")
}

// MARK: - EnvironmentKey (allows chart views to read palette without prop drilling)

private struct ShareChartPaletteKey: EnvironmentKey {
    static let defaultValue = ShareChartPalette.dark
}

extension EnvironmentValues {
    var shareChartPalette: ShareChartPalette {
        get { self[ShareChartPaletteKey.self] }
        set { self[ShareChartPaletteKey.self] = newValue }
    }
}

// MARK: - ReplayContent

enum ReplayContent: String, CaseIterable {
    case chartData  = "차트+데이터"
    case routeData  = "경로+데이터"
    case routeChart = "경로+차트"
}

// MARK: - RunChartReplayExporter

@MainActor
enum RunChartReplayExporter {

    // MARK: - Video constants

    static let videoW   = 1080
    static let videoH   = 1350
    static let videoFPS = 30
    static let bitrate  = 8_000_000
    static let holdSecs = 1.2
    static let scale: CGFloat = 3.6   // 1080 / 300pt

    /// 합성할 때 각 구역을 가장자리까지 채운다 — 이미지 카드(RunChartShareCard)가
    /// 헤더와 차트를 **하나의 연속된 패널**로 그리는 것과 같은 규칙이다.
    /// 예전에는 헤더 0% · 차트 3% · 지도 5%로 제각각이라 블록들의 왼쪽 끝이 다 어긋났고,
    /// 여백을 주면 헤더 띠만 가장자리까지 가 다시 어긋난다. 들여쓰기는 **각 뷰 안에서** 한다.
    static let sideInsetPx: CGFloat = 0
    static let cardW: CGFloat = 300   // pt reference width

    // MARK: - Layout

    struct SectionLayout {
        let topPad:        Int
        let headerH:       Int
        let routeH:        Int   // 0 if no map
        let mapChartGap:   Int
        let chartH:        Int   // 0 if no chart
        let chartTilesGap: Int
        let tilesH:        Int   // 0 if no tiles
        let botPad:        Int

        var headerTop: Int { topPad }
        var routeTop:  Int { headerTop + headerH }
        var chartTop:  Int { routeTop  + routeH  + mapChartGap   }
        var tilesTop:  Int { chartTop  + chartH  + chartTilesGap }

        /// 경로 모드 배치. 헤더·타일은 **실측한 자연 높이**를 받는다 — 고정 슬롯(190·530px)에
        /// 끼우면 이미지 카드와 세로 위치가 어긋났다. 남는 자리를 지도(·차트)가 채운다.
        /// 위아래 여백은 0 — 이미지 카드는 헤더가 맨 위, 타일이 맨 아래에 붙는다.
        /// `chartData`는 여기 오지 않는다(이미지 카드를 통째로 그린다).
        static func make(_ content: ReplayContent, headerPx: Int, tilesPx: Int) -> SectionLayout {
            switch content {
            case .chartData:
                // 도달하지 않는다. 형식상 헤더+차트+타일로 채운다.
                return SectionLayout(topPad:0, headerH:headerPx, routeH:0, mapChartGap:0,
                                     chartH:videoH - headerPx - tilesPx, chartTilesGap:0,
                                     tilesH:tilesPx, botPad:0)
            case .routeData:
                return SectionLayout(topPad:0, headerH:headerPx, routeH:videoH - headerPx - tilesPx,
                                     mapChartGap:0, chartH:0, chartTilesGap:0, tilesH:tilesPx, botPad:0)
            case .routeChart:
                // 타일이 없어 자리가 넉넉하다. 628px(174pt)은 지도와의 균형으로 정한 값.
                let chart = 628, gap = 12
                return SectionLayout(topPad:0, headerH:headerPx, routeH:videoH - headerPx - gap - chart,
                                     mapChartGap:gap, chartH:chart, chartTilesGap:0, tilesH:0, botPad:0)
            }
        }
    }

    // MARK: - Public API

    static func export(
        data: RunChartData,
        enabledLayers: Set<RunChartLayer>,
        distanceText: String,
        durationText: String,
        weatherText: String?,
        weatherIcon: String?,
        dateText: String?,
        weekdayText: String?,
        startTimeText: String?,
        shoeText: String?,
        paceText: String? = nil,
        totalDuration: TimeInterval = 0,
        routeCoordinates: [CLLocationCoordinate2D] = [],
        content: ReplayContent = .chartData,
        duration: TimeInterval = 10,
        /// 이미지 카드가 4:5에 맞춰 둔 차트 높이 — 영상도 같은 카드를 그리므로 같은 값을 받는다.
        chartHeight: CGFloat = 226,
        palette: ShareChartPalette = .dark,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {

        let hasRoute = routeCoordinates.count >= 2
        let needsRoute = content == .routeChart || content == .routeData
        let actual   = (needsRoute && !hasRoute) ? ReplayContent.chartData : content
        #if DEBUG
        print("[Replay] content:\(actual) coords:\(routeCoordinates.count)")
        #endif

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_chart_\(UUID().uuidString).mp4")

        // ── AVAssetWriter ────────────────────────────────────────────────────
        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let videoIn = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey:  AVVideoCodecType.h264,
                AVVideoWidthKey:  videoW,
                AVVideoHeightKey: videoH,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoProfileLevelKey:  AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
        )
        videoIn.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoIn,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey  as String: videoW,
                kCVPixelBufferHeightKey as String: videoH
            ]
        )
        writer.add(videoIn)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let animFrames  = Int(duration * Double(videoFPS))
        let holdFrames  = Int(holdSecs * Double(videoFPS))
        let totalFrames = animFrames + holdFrames

        // ── Static sections (rendered once) ─────────────────────────────────
        // 헤더·타일은 프레임마다 바뀌지 않는다 — 한 번만 그린다. 이미지 카드와 **같은 뷰**를
        // 자연 높이로 그리므로 배치는 카드와 같다(§5.8). 프레임마다 카드를 통째로 그리면
        // 헤더·타일 레이아웃이 450번 반복돼 내보내기가 몇 배 느려졌다.
        let strips = renderCardStrips(
            data: data, enabledLayers: enabledLayers, withTiles: actual != .routeChart,
            distanceText: distanceText, durationText: durationText,
            weatherText: weatherText, weatherIcon: weatherIcon,
            dateText: dateText, weekdayText: weekdayText,
            startTimeText: startTimeText, shoeText: shoeText, paceText: paceText,
            palette: palette)
        let headerImg = strips.header
        let tilesImg  = strips.tiles
        let layout = SectionLayout.make(actual, headerPx: headerImg?.height ?? 0,
                                        tilesPx: tilesImg?.height ?? 0)
        let chartPtH = CGFloat(layout.chartH) / scale

        // ── Map snapshot (once, if needed) ───────────────────────────────────
        var mapUIImage: UIImage? = nil
        var mapPoints:  [CGPoint] = []
        var cumDist:    [Double] = []

        if layout.routeH > 0 && hasRoute {
            // Request at pixel dimensions, scale=1 (MKMapSnapshotter rejects fractional scales)
            let snapSize = CGSize(width: CGFloat(videoW), height: CGFloat(layout.routeH))
            do {
                let (img, pts) = try await chartMapSnapshot(
                    coordinates: routeCoordinates,
                    pixelSize: snapSize,
                    isLight: palette.isLight
                )
                mapUIImage = img
                mapPoints  = pts
            } catch {
                #if DEBUG
                print("[Replay] snapshot FAILED:", error)
                #endif
            }
            // cumDist must match the same sample step used by chartMapSnapshot (max 500 pts)
            let snapStep = max(1, routeCoordinates.count / 500)
            let sampledCoords = stride(from: 0, to: routeCoordinates.count, by: snapStep)
                .map { routeCoordinates[$0] }
            cumDist = buildCumulativeDistances(sampledCoords)
        }
        #if DEBUG
        logMapDiagnostics(routeCoordCount: routeCoordinates.count,
                          mapUIImage: mapUIImage, layout: layout)
        #endif

        let timeDistTable = buildTimeDistanceTable(data: data, totalDuration: totalDuration)
        let videoSize = CGSize(width: videoW, height: videoH)

        // ── Frame loop ────────────────────────────────────────────────────────
        // autoreleasepool: 프레임마다 생성되는 UIImage/CGImage를 즉시 해제.
        // 없으면 300+프레임 × 5~20MB가 메모리에 쌓여 OOM kill(iPhone 11 Pro 등)을 유발함.
        do {
            for frameIdx in 0..<totalFrames {
                try Task.checkCancellation()

                let t: Double = frameIdx < animFrames
                    ? Double(frameIdx) / Double(max(1, animFrames - 1))
                    : 1.0

                let distRatio = timeToDistanceRatio(timeRatio: t, table: timeDistTable)

                // isReadyForMoreMediaData는 async await 필요 → autoreleasepool 밖에서 먼저 대기
                while !videoIn.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }

                // 렌더링·합성·append를 한 pool로 묶어 즉시 해제
                // (UIImage/CGImage/CVPixelBuffer가 쌓이면 300+프레임에서 OOM kill 발생)
                let appended: Bool = autoreleasepool {
                    let frame: UIImage
                    if actual == .chartData {
                        // 차트 조각만 프레임마다 — 이미지 카드 안의 차트와 같은 패딩·배경.
                        let chartImg = renderCGImage(
                            chartStrip(data: data, enabledLayers: enabledLayers,
                                       chartHeight: chartHeight, playProgress: distRatio,
                                       palette: palette),
                            width: cardW, height: nil, palette: palette)
                        frame = composeCardFrame(header: headerImg, chart: chartImg,
                                                 tiles: tilesImg, palette: palette)
                    } else {
                        let chartImg: CGImage? = layout.chartH > 0 ? renderCGImage(
                            RunCombinedChartView(
                                data: data,
                                enabledLayers: enabledLayers,
                                chartHeight: chartPtH,
                                playProgress: distRatio
                            )
                            .frame(width: cardW, height: chartPtH)
                            .background(palette.sectionBackground),
                            width: cardW, height: chartPtH, palette: palette
                        ) : nil

                        frame = composeFrame(
                            layout: layout, data: data, totalDuration: totalDuration,
                            headerImage: headerImg, chartImage: chartImg,
                            mapUIImage: mapUIImage, mapPoints: mapPoints,
                            cumDist: cumDist, distanceProgress: distRatio,
                            routeCoordinates: routeCoordinates,
                            timeProgress: t, tilesImage: tilesImg,
                            palette: palette
                        )
                    }

                    guard let pb = pixelBuffer(from: frame, size: videoSize) else { return false }
                    let pts = CMTime(value: CMTimeValue(frameIdx), timescale: CMTimeScale(videoFPS))
                    adaptor.append(pb, withPresentationTime: pts)
                    return true
                }

                if appended {
                    onProgress(Double(frameIdx + 1) / Double(totalFrames))
                }
                await Task.yield()
            }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        videoIn.markAsFinished()
        await withCheckedContinuation { cont in writer.finishWriting { cont.resume() } }

        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: tempURL)
            throw writer.error ?? NSError(domain: "RunChartReplayExporter", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Video encoding failed"])
        }
        return tempURL
    }

    // MARK: - Preview frame with real map (async — used for sheet preview)

    /// Renders a single frame at `progress` (0–1) including the actual map snapshot.
    /// Use `progress ≈ 0.45` for a mid-run preview that shows polyline + marker clearly.
    static func previewFrame(
        data: RunChartData,
        enabledLayers: Set<RunChartLayer>,
        distanceText: String,
        durationText: String,
        weatherText: String?,
        weatherIcon: String?,
        dateText: String?,
        weekdayText: String?,
        startTimeText: String?,
        shoeText: String?,
        paceText: String? = nil,
        totalDuration: TimeInterval = 0,
        routeCoordinates: [CLLocationCoordinate2D] = [],
        content: ReplayContent,
        progress: Double = 0.45,
        chartHeight: CGFloat = 226,
        palette: ShareChartPalette = .dark
    ) async -> UIImage? {
        let hasRoute = routeCoordinates.count >= 2
        let needsRoute = content == .routeChart || content == .routeData
        let actual = (needsRoute && !hasRoute) ? ReplayContent.chartData : content

        // 내보내기와 **같은 조각·같은 합성** — 미리보기가 곧 출력이다.
        let strips = renderCardStrips(
            data: data, enabledLayers: enabledLayers, withTiles: actual != .routeChart,
            distanceText: distanceText, durationText: durationText,
            weatherText: weatherText, weatherIcon: weatherIcon,
            dateText: dateText, weekdayText: weekdayText,
            startTimeText: startTimeText, shoeText: shoeText, paceText: paceText,
            palette: palette)
        let headerImg = strips.header
        let tilesImg  = strips.tiles

        if actual == .chartData {
            let timeDistTable = buildTimeDistanceTable(data: data, totalDuration: totalDuration)
            let distRatio = timeToDistanceRatio(timeRatio: progress, table: timeDistTable)
            let chartImg = renderCGImage(
                chartStrip(data: data, enabledLayers: enabledLayers,
                           chartHeight: chartHeight, playProgress: distRatio, palette: palette),
                width: cardW, height: nil, palette: palette)
            return composeCardFrame(header: headerImg, chart: chartImg, tiles: tilesImg, palette: palette)
        }

        let layout = SectionLayout.make(actual, headerPx: headerImg?.height ?? 0,
                                        tilesPx: tilesImg?.height ?? 0)
        let chartPtH = CGFloat(layout.chartH) / scale
        let chartImg: CGImage? = layout.chartH > 0 ? renderCGImage(
            RunCombinedChartView(
                data: data, enabledLayers: enabledLayers,
                chartHeight: chartPtH, playProgress: progress
            )
            .frame(width: cardW, height: chartPtH)
            .background(palette.sectionBackground),
            width: cardW, height: chartPtH, palette: palette
        ) : nil

        var mapUIImage: UIImage? = nil
        var mapPoints:  [CGPoint] = []
        var cumDist:    [Double] = []

        if layout.routeH > 0 && hasRoute {
            let snapSize = CGSize(width: CGFloat(videoW), height: CGFloat(layout.routeH))
            do {
                let (img, pts) = try await chartMapSnapshot(
                    coordinates: routeCoordinates,
                    pixelSize: snapSize,
                    isLight: palette.isLight
                )
                mapUIImage = img
                mapPoints  = pts
            } catch {
                #if DEBUG
                print("[Preview] snapshot FAILED:", error)
                #endif
            }
            let snapStep = max(1, routeCoordinates.count / 500)
            let sampledCoords = stride(from: 0, to: routeCoordinates.count, by: snapStep)
                .map { routeCoordinates[$0] }
            cumDist = buildCumulativeDistances(sampledCoords)
        }
        #if DEBUG
        logMapDiagnostics(routeCoordCount: routeCoordinates.count,
                          mapUIImage: mapUIImage, layout: layout)
        #endif

        let timeDistTable = buildTimeDistanceTable(data: data, totalDuration: totalDuration)
        let distRatio = timeToDistanceRatio(timeRatio: progress, table: timeDistTable)
        return composeFrame(
            layout: layout, data: data, totalDuration: totalDuration,
            headerImage: headerImg, chartImage: chartImg,
            mapUIImage: mapUIImage, mapPoints: mapPoints,
            cumDist: cumDist, distanceProgress: distRatio,
            routeCoordinates: routeCoordinates,
            timeProgress: progress, tilesImage: tilesImg,
            palette: palette
        )
    }

    #if DEBUG
    private static func logMapDiagnostics(routeCoordCount: Int,
                                          mapUIImage: UIImage?,
                                          layout: SectionLayout) {
        print("[Replay] routeCoords =", routeCoordCount)
        print("[Replay] mapImage =", String(describing: mapUIImage?.size))
        guard layout.routeH > 0 else { print("[Replay] mapRect = N/A (no route section)"); return }
        let mapRect = CGRect(x: 0, y: CGFloat(layout.routeTop),
                             width: CGFloat(videoW), height: CGFloat(layout.routeH))
        print("[Replay] mapRect =", mapRect)
        if let img = mapUIImage {
            let pixW = img.size.width * img.scale
            let pixH = img.size.height * img.scale
            if pixW > 0, pixH > 0 {
                let s = max(mapRect.width / pixW, mapRect.height / pixH)
                let fittedRect = CGRect(x: mapRect.midX - pixW*s/2,
                                        y: mapRect.midY - pixH*s/2,
                                        width: pixW*s, height: pixH*s)
                print("[Replay] fittedRect =", fittedRect)
            } else {
                print("[Replay] fittedRect = INVALID (pixW:\(pixW) pixH:\(pixH))")
            }
        } else {
            print("[Replay] fittedRect = N/A (no map — coordinate fallback will render)")
        }
    }
    #endif

    // MARK: - Frame composition (UIKit coordinate space — top-left origin)

    private static func composeFrame(
        layout: SectionLayout,
        data: RunChartData,
        totalDuration: TimeInterval,
        headerImage: CGImage?,
        chartImage:  CGImage?,
        mapUIImage:  UIImage?,
        mapPoints:   [CGPoint],
        cumDist:     [Double],
        distanceProgress: Double,
        routeCoordinates: [CLLocationCoordinate2D] = [],
        timeProgress: Double,
        tilesImage:  CGImage?,
        palette: ShareChartPalette = .dark
    ) -> UIImage {
        let size = CGSize(width: videoW, height: videoH)
        let fmt  = UIGraphicsImageRendererFormat()
        fmt.scale  = 1
        fmt.opaque = true

        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            UIColor(palette.background).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            func stamp(_ img: CGImage, yTop: Int, h: Int) {
                UIImage(cgImage: img).draw(in:
                    CGRect(x: 0, y: CGFloat(yTop), width: CGFloat(videoW), height: CGFloat(h)))
            }

            if let img = headerImage { stamp(img, yTop: layout.headerTop, h: layout.headerH) }
            if let img = chartImage, layout.chartH > 0 {
                let m = sideInsetPx
                UIImage(cgImage: img).draw(in:
                    CGRect(x: m, y: CGFloat(layout.chartTop),
                           width: CGFloat(videoW) - m * 2, height: CGFloat(layout.chartH)))
            }

            if layout.routeH > 0 {
                let routeRect = CGRect(x: 0, y: CGFloat(layout.routeTop),
                                       width: CGFloat(videoW), height: CGFloat(layout.routeH))

                let ctx = UIGraphicsGetCurrentContext()!
                ctx.saveGState()
                UIBezierPath(rect: routeRect).addClip()

                let hMargin = sideInsetPx
                let mapCornerRadius: CGFloat = 20
                let mapDrawRect = CGRect(
                    x: routeRect.minX + hMargin,
                    y: routeRect.minY,
                    width: routeRect.width - hMargin * 2,
                    height: routeRect.height
                )
                if let mapImg = mapUIImage {
                    ctx.saveGState()
                    UIBezierPath(roundedRect: mapDrawRect, cornerRadius: mapCornerRadius).addClip()
                    mapImg.draw(in: mapDrawRect)
                    ctx.restoreGState()
                } else {
                    UIColor(red: 0.07, green: 0.06, blue: 0.14, alpha: 1).setFill()
                    UIRectFill(routeRect)
                }

                // Light theme: thin border around map rect
                if palette.mapBorderOp > 0, mapUIImage != nil {
                    let borderPath = UIBezierPath(roundedRect: mapDrawRect, cornerRadius: mapCornerRadius)
                    UIColor(palette.textPrimary).withAlphaComponent(palette.mapBorderOp).setStroke()
                    borderPath.lineWidth = 3.0  // 0.8pt × 3.6 scale
                    borderPath.stroke()
                }

                ctx.restoreGState()

                if mapPoints.count > 1 {
                    drawRoutePolyline(ctx: ctx, points: mapPoints,
                                      distanceProgress: distanceProgress,
                                      timeProgress: timeProgress,
                                      cumDist: cumDist, routeRect: routeRect,
                                      totalKm: data.totalKm, totalDuration: totalDuration,
                                      palette: palette)
                } else if routeCoordinates.count >= 2 {
                    drawRouteFromCoordinates(ctx: ctx, coordinates: routeCoordinates,
                                             distanceProgress: distanceProgress,
                                             timeProgress: timeProgress,
                                             cumDist: cumDist, routeRect: routeRect,
                                             totalKm: data.totalKm, totalDuration: totalDuration,
                                             palette: palette)
                }
            }

            if let img = tilesImage, layout.tilesH > 0 {
                let m = sideInsetPx
                UIImage(cgImage: img).draw(in:
                    CGRect(x: m, y: CGFloat(layout.tilesTop),
                           width: CGFloat(videoW) - m * 2, height: CGFloat(layout.tilesH)))
            }
        }
    }

    // MARK: - UIImage → CVPixelBuffer (flip applied only here)

    /// 경로 1 영상 내보내기도 같은 변환을 쓴다 — 픽셀 포맷·상하 뒤집기를 두 벌로 두지 않는다.
    static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil, Int(size.width), Int(size.height),
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let pixelBuffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let ctx = CGContext(
            data:             CVPixelBufferGetBaseAddress(pixelBuffer),
            width:            Int(size.width),
            height:           Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow:      CVPixelBufferGetBytesPerRow(pixelBuffer),
            space:            CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:       CGBitmapInfo.byteOrder32Little.rawValue |
                              CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        // UIKit top-left origin → CG bottom-left origin conversion
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        image.draw(in: CGRect(origin: .zero, size: size))
        UIGraphicsPopContext()
        return pixelBuffer
    }

    // MARK: - Route polyline

    private static func drawRoutePolyline(
        ctx: CGContext,
        points: [CGPoint],
        distanceProgress: Double,
        timeProgress: Double,
        cumDist: [Double],
        routeRect: CGRect,
        totalKm: Double,
        totalDuration: TimeInterval,
        palette: ShareChartPalette = .dark
    ) {
        guard points.count > 1 else { return }

        func px(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x, y: routeRect.minY + p.y)
        }
        let allPx = points.map { px($0) }
        let endIdx = distanceIndex(at: distanceProgress, cumDist: cumDist, total: points.count)

        let fullPath = CGMutablePath()
        fullPath.move(to: allPx[0])
        allPx.dropFirst().forEach { fullPath.addLine(to: $0) }
        ctx.setStrokeColor(UIColor(palette.textPrimary).withAlphaComponent(0.18).cgColor)
        ctx.setLineWidth(2); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addPath(fullPath); ctx.strokePath()

        if endIdx > 0 {
            let travPx = Array(allPx.prefix(endIdx + 1))
            let travPath = CGMutablePath()
            travPath.move(to: travPx[0])
            travPx.dropFirst().forEach { travPath.addLine(to: $0) }

            ctx.setStrokeColor(palette.routeCasingUI.cgColor)
            ctx.setLineWidth(5.5)
            ctx.addPath(travPath); ctx.strokePath()

            ctx.setStrokeColor(UIColor(palette.pace).cgColor)
            ctx.setLineWidth(3.5)
            ctx.addPath(travPath); ctx.strokePath()

            let tip = travPx[travPx.count - 1]
            let violet = UIColor(Theme.violet)
            ctx.setFillColor(violet.withAlphaComponent(0.25).cgColor)
            ctx.fillEllipse(in: CGRect(x: tip.x-14, y: tip.y-14, width: 28, height: 28))
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: tip.x-7, y: tip.y-7, width: 14, height: 14))
            ctx.setFillColor(violet.cgColor)
            ctx.fillEllipse(in: CGRect(x: tip.x-5, y: tip.y-5, width: 10, height: 10))
        }

        drawKmMarkers(ctx: ctx, allPx: allPx, cumDist: cumDist,
                      routeRect: routeRect, totalKm: totalKm,
                      distanceProgress: distanceProgress, palette: palette)
        drawRouteProgressLabel(timeProgress: timeProgress, distanceProgress: distanceProgress,
                               totalKm: totalKm, totalDuration: totalDuration,
                               routeRect: routeRect, palette: palette)
    }

    // Fallback: draw route directly from lat/lon when map snapshot is unavailable
    private static func drawRouteFromCoordinates(
        ctx: CGContext,
        coordinates: [CLLocationCoordinate2D],
        distanceProgress: Double,
        timeProgress: Double,
        cumDist: [Double],
        routeRect: CGRect,
        totalKm: Double,
        totalDuration: TimeInterval,
        palette: ShareChartPalette = .dark
    ) {
        guard coordinates.count >= 2 else { return }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max()
        else { return }

        let latRange = max(maxLat - minLat, 0.0001)
        let lonRange = max(maxLon - minLon, 0.0001)

        let latAspect = CGFloat(latRange / lonRange)
        let availW    = routeRect.width  * 0.85
        let availH    = routeRect.height * 0.85
        let boxW: CGFloat
        let boxH: CGFloat
        if latAspect * availW > availH {
            boxH = availH; boxW = boxH / latAspect
        } else {
            boxW = availW; boxH = boxW * latAspect
        }
        let ox = routeRect.midX - boxW / 2
        let oy = routeRect.midY - boxH / 2

        func toPixel(_ c: CLLocationCoordinate2D) -> CGPoint {
            let nx = CGFloat((c.longitude - minLon) / lonRange)
            let ny = CGFloat(1.0 - (c.latitude - minLat) / latRange)
            return CGPoint(x: ox + nx * boxW, y: oy + ny * boxH)
        }

        let step = max(1, coordinates.count / 500)
        let sampled = stride(from: 0, to: coordinates.count, by: step).map { coordinates[$0] }
        let allPx   = sampled.map { toPixel($0) }
        let localCumDist = buildCumulativeDistances(sampled)
        let endIdx  = distanceIndex(at: distanceProgress, cumDist: localCumDist, total: allPx.count)

        let fullPath = CGMutablePath()
        fullPath.move(to: allPx[0])
        allPx.dropFirst().forEach { fullPath.addLine(to: $0) }
        ctx.setStrokeColor(UIColor(palette.textPrimary).withAlphaComponent(0.22).cgColor)
        ctx.setLineWidth(2); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addPath(fullPath); ctx.strokePath()

        if endIdx > 0 {
            let travPx = Array(allPx.prefix(endIdx + 1))
            let travPath = CGMutablePath()
            travPath.move(to: travPx[0])
            travPx.dropFirst().forEach { travPath.addLine(to: $0) }

            ctx.setStrokeColor(palette.routeCasingUI.cgColor)
            ctx.setLineWidth(5.5); ctx.addPath(travPath); ctx.strokePath()

            ctx.setStrokeColor(UIColor(palette.pace).cgColor)
            ctx.setLineWidth(3.5); ctx.addPath(travPath); ctx.strokePath()

            let tip = travPx.last!
            let violet = UIColor(Theme.violet)
            ctx.setFillColor(violet.withAlphaComponent(0.25).cgColor)
            ctx.fillEllipse(in: CGRect(x: tip.x-14, y: tip.y-14, width: 28, height: 28))
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: tip.x-7, y: tip.y-7, width: 14, height: 14))
            ctx.setFillColor(violet.cgColor)
            ctx.fillEllipse(in: CGRect(x: tip.x-5, y: tip.y-5, width: 10, height: 10))
        }

        drawKmMarkers(ctx: ctx, allPx: allPx, cumDist: localCumDist,
                      routeRect: routeRect, totalKm: totalKm,
                      distanceProgress: distanceProgress, palette: palette)
        drawRouteProgressLabel(timeProgress: timeProgress, distanceProgress: distanceProgress,
                               totalKm: totalKm, totalDuration: totalDuration,
                               routeRect: routeRect, palette: palette)
    }

    private static func drawRouteProgressLabel(
        timeProgress: Double,
        distanceProgress: Double,
        totalKm: Double,
        totalDuration: TimeInterval,
        routeRect: CGRect,
        palette: ShareChartPalette = .dark
    ) {
        guard totalKm > 0, timeProgress > 0 else { return }
        let km = distanceProgress * totalKm
        let elapsed = timeProgress * totalDuration
        let s = Int(elapsed.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        let timeStr = h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
        let text = String(format: "%.1fkm · %@", km, timeStr)

        let font = UIFont.systemFont(ofSize: 11, weight: .heavy)
        let textColor = UIColor(palette.textPrimary)
        let attrStr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: textColor
        ])
        let textSize = attrStr.size()
        let padH: CGFloat = 10, padV: CGFloat = 6
        let bgW = textSize.width + padH * 2
        let bgH = textSize.height + padV * 2
        let bgX = routeRect.midX - bgW / 2
        let bgY = routeRect.minY + 14

        palette.mapBadgeBgUI.setFill()
        UIBezierPath(roundedRect: CGRect(x: bgX, y: bgY, width: bgW, height: bgH),
                     cornerRadius: bgH / 2).fill()
        attrStr.draw(at: CGPoint(x: bgX + padH, y: bgY + padV))
    }

    // MARK: - Km markers on route

    private static func drawKmMarkers(
        ctx: CGContext,
        allPx: [CGPoint],
        cumDist: [Double],
        routeRect: CGRect,
        totalKm: Double,
        distanceProgress: Double,
        palette: ShareChartPalette = .dark
    ) {
        guard totalKm > 0, allPx.count > 1, !cumDist.isEmpty else { return }
        guard let totalDist = cumDist.last, totalDist > 0 else { return }

        let interval: Int
        if totalKm >= 30 { interval = 5 }
        else if totalKm >= 20 { interval = 2 }
        else { interval = 1 }

        let maxKm = Int(totalKm)
        guard maxKm >= interval else { return }

        let passedDist = distanceProgress * totalDist
        let font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let padH: CGFloat = 8, padV: CGFloat = 5
        let corner: CGFloat = 6

        for km in stride(from: interval, through: maxKm, by: interval) {
            let targetDist = Double(km) * 1000.0
            guard targetDist <= totalDist else { break }
            // Only render markers that have been passed by the animated route
            guard targetDist <= passedDist else { break }

            // Binary search for the index where cumDist first reaches targetDist
            var lo = 0, hi = cumDist.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if cumDist[mid] <= targetDist { lo = mid } else { hi = mid - 1 }
            }
            let idx = min(lo, allPx.count - 1)
            let pt = allPx[idx]

            let dotR: CGFloat = 4.0
            ctx.setFillColor(palette.mapBadgeBgUI.cgColor)
            ctx.fillEllipse(in: CGRect(x: pt.x - dotR - 1.5, y: pt.y - dotR - 1.5,
                                       width: (dotR + 1.5) * 2, height: (dotR + 1.5) * 2))
            ctx.setFillColor(UIColor(palette.textPrimary).cgColor)
            ctx.fillEllipse(in: CGRect(x: pt.x - dotR, y: pt.y - dotR,
                                       width: dotR * 2, height: dotR * 2))

            let label = "\(km)km"
            let attrStr = NSAttributedString(string: label, attributes: [
                .font: font,
                .foregroundColor: UIColor(palette.textPrimary)
            ])
            let textSize = attrStr.size()
            let bgW = textSize.width + padH * 2
            let bgH = textSize.height + padV * 2

            // Determine travel direction by comparing neighboring pts
            let prevIdx = max(0, idx - 1)
            let nextIdx = min(allPx.count - 1, idx + 1)
            let travelDy = allPx[nextIdx].y - allPx[prevIdx].y
            // Going up on screen (dy < 0) → badge to the right (+x)
            // Going down on screen (dy >= 0) → badge to the left (-x)
            let goRight = travelDy < 0
            let gap: CGFloat = dotR + 8
            var bgX = goRight ? pt.x + gap : pt.x - gap - bgW
            var bgY = pt.y - bgH / 2   // vertically centered on dot

            // Clamp within routeRect
            bgX = max(routeRect.minX + 3, min(routeRect.maxX - bgW - 3, bgX))
            bgY = max(routeRect.minY + 3, min(routeRect.maxY - bgH - 3, bgY))

            palette.mapBadgeBgUI.setFill()
            UIBezierPath(roundedRect: CGRect(x: bgX, y: bgY, width: bgW, height: bgH),
                         cornerRadius: corner).fill()

            attrStr.draw(at: CGPoint(x: bgX + padH, y: bgY + padV))
        }
    }

    // MARK: - Time ↔ Distance (paceColumns-based — same source as chart's elapsedTime)

    private static func buildTimeDistanceTable(
        data: RunChartData,
        totalDuration: TimeInterval
    ) -> [(timeRatio: Double, distanceRatio: Double)] {
        guard data.totalKm > 0, !data.paceColumns.isEmpty else { return [] }

        // Each PaceColumn already stores startX/endX as fractions of totalDuration,
        // and startKm/endKm as absolute km. Convert to parallel (timeRatio, distanceRatio) pairs.
        // This mirrors chart's elapsedTime(atKm:), guaranteeing the same mapping.
        var entries: [(timeRatio: Double, distanceRatio: Double)] = [(0.0, 0.0)]
        for col in data.paceColumns.sorted(by: { $0.startX < $1.startX }) {
            entries.append((timeRatio: col.startX, distanceRatio: col.startKm / data.totalKm))
            entries.append((timeRatio: col.endX,   distanceRatio: col.endKm   / data.totalKm))
        }
        entries.append((1.0, 1.0))

        // Sort and deduplicate by timeRatio
        entries.sort { $0.timeRatio < $1.timeRatio }
        var deduped: [(timeRatio: Double, distanceRatio: Double)] = []
        for e in entries where deduped.isEmpty || deduped.last!.timeRatio < e.timeRatio {
            deduped.append(e)
        }
        return deduped
    }

    private static func timeToDistanceRatio(
        timeRatio: Double,
        table: [(timeRatio: Double, distanceRatio: Double)]
    ) -> Double {
        guard !table.isEmpty else { return timeRatio }
        let t = max(0, min(1, timeRatio))
        for i in 1..<table.count {
            guard table[i].timeRatio >= t else { continue }
            let prev = table[i-1], curr = table[i]
            let span = curr.timeRatio - prev.timeRatio
            guard span > 0 else { return curr.distanceRatio }
            let frac = (t - prev.timeRatio) / span
            return prev.distanceRatio + frac * (curr.distanceRatio - prev.distanceRatio)
        }
        return 1
    }

    // MARK: - Cumulative distance helpers

    static func buildCumulativeDistances(_ coords: [CLLocationCoordinate2D]) -> [Double] {
        var dist: [Double] = [0]
        for i in 1..<coords.count {
            let from = CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
            let to   = CLLocation(latitude: coords[i].latitude,   longitude: coords[i].longitude)
            dist.append(dist.last! + from.distance(from: to))
        }
        return dist
    }

    private static func distanceIndex(at progress: Double, cumDist: [Double], total: Int) -> Int {
        guard !cumDist.isEmpty, let totalDist = cumDist.last, totalDist > 0 else {
            return Int(Double(total - 1) * max(0, min(1, progress)))
        }
        let target = max(0, min(1, progress)) * totalDist
        var lo = 0, hi = cumDist.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if cumDist[mid] <= target { lo = mid } else { hi = mid - 1 }
        }
        return min(lo, total - 1)
    }

    // MARK: - Map snapshot

    private static func chartMapSnapshot(
        coordinates: [CLLocationCoordinate2D],
        pixelSize: CGSize,   // pixel dimensions; scale=1 so points returned are in pixel space
        isLight: Bool = false
    ) async throws -> (UIImage, [CGPoint]) {
        guard coordinates.count > 1 else { return (placeholderMapImage(size: pixelSize), []) }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max()
        else { return (placeholderMapImage(size: pixelSize), []) }

        // 스냅샷 폭은 **실제로 그릴 폭과 같아야 한다** — 여백보다 좁게 요청하면 그릴 때
        // 가로로 늘어난다. 합성의 sideInsetPx와 같은 비율을 쓴다.
        let hMargin = RunChartReplayExporter.sideInsetPx / CGFloat(RunChartReplayExporter.videoW)
        let requestSize = CGSize(width: pixelSize.width * (1 - 2 * hMargin), height: pixelSize.height)

        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat+maxLat)/2,
                                           longitude: (minLon+maxLon)/2),
            span: MKCoordinateSpan(
                latitudeDelta:  max((maxLat-minLat)*1.3, 0.005),
                longitudeDelta: max((maxLon-minLon)*1.3, 0.005)
            )
        )
        opts.size         = requestSize
        opts.scale        = 1   // fractional scales (e.g. 3.6) are rejected by MKMapSnapshotter
        opts.mapType      = .mutedStandard
        opts.showsBuildings = false
        opts.traitCollection = UITraitCollection(userInterfaceStyle: isLight ? .light : .dark)

        let snap = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<MKMapSnapshotter.Snapshot, Error>) in
            MKMapSnapshotter(options: opts).start { snapshot, error in
                if let error { cont.resume(throwing: error); return }
                guard let snapshot else {
                    cont.resume(throwing: NSError(domain: "chartMapSnapshot", code: -1)); return
                }
                cont.resume(returning: snapshot)
            }
        }

        let step = max(1, coordinates.count / 500)
        let pts = stride(from: 0, to: coordinates.count, by: step)
            .map { snap.point(for: coordinates[$0]) }
        // Snapshot is 95% wide; mapDrawRect starts at +hMargin in the full routeRect.
        // Shift points right so they align with the drawn map position.
        let marginOffset = pixelSize.width * hMargin
        let adjustedPts = pts.map { CGPoint(x: $0.x + marginOffset, y: $0.y) }
        return (snap.image, adjustedPts)
    }

    private static func placeholderMapImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.07, green: 0.06, blue: 0.14, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - SwiftUI → CGImage

    /// `height: nil`이면 자연 높이로 그린다 — 반환 이미지의 `height`가 곧 실측 px.
    /// colorScheme은 이미지 출력(ImageRenderer + environment)과 같은 방식으로 넣는다 —
    /// preferredColorScheme은 ImageRenderer 안에서 안 먹어 `.secondary` 같은 시스템 색이 달라졌다.
    private static func renderCGImage<V: View>(_ view: V, width: CGFloat, height: CGFloat?,
                                               palette: ShareChartPalette = .dark) -> CGImage? {
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, palette.isLight ? .light : .dark)
            .environment(\.shareChartPalette, palette))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        return renderer.cgImage
    }

    // MARK: - 이미지 카드의 세 조각 (§5.8 — 영상은 카드와 같은 뷰를 같은 폭·같은 패딩으로 그린다)

    /// 헤더·타일 조각. 자연 높이로 그려 반환 이미지의 `height`가 곧 배치 px가 된다.
    /// 카드 안에서 헤더는 sectionBackground 위에, 타일은 cardBackground 위에 놓인다 — 같게 깐다.
    private static func renderCardStrips(
        data: RunChartData, enabledLayers: Set<RunChartLayer>, withTiles: Bool,
        distanceText: String, durationText: String,
        weatherText: String?, weatherIcon: String?,
        dateText: String?, weekdayText: String?,
        startTimeText: String?, shoeText: String?, paceText: String?,
        palette: ShareChartPalette
    ) -> (header: CGImage?, tiles: CGImage?) {
        let header = renderCGImage(
            RunChartShareHeader(
                distanceText: distanceText, durationText: durationText,
                weatherText: weatherText, weatherIcon: weatherIcon,
                dateText: dateText, weekdayText: weekdayText,
                startTimeText: startTimeText, shoeText: shoeText,
                paceText: paceText, palette: palette)
                .frame(width: cardW)
                .background(palette.sectionBackground),
            width: cardW, height: nil, palette: palette)
        let tiles: CGImage? = withTiles ? renderCGImage(
            RunChartShareTiles(data: data, enabledLayers: enabledLayers, palette: palette)
                .frame(width: cardW)
                .background(palette.cardBackground),
            width: cardW, height: nil, palette: palette) : nil
        return (header, tiles)
    }

    /// 차트 조각 — `RunChartShareCard` 안의 차트와 **같은 패딩(위 2·아래 4)·같은 배경**.
    /// 여기가 카드와 달라지면 프레임마다 그리는 부분만 어긋난다.
    private static func chartStrip(
        data: RunChartData, enabledLayers: Set<RunChartLayer>,
        chartHeight: CGFloat, playProgress: Double, palette: ShareChartPalette
    ) -> some View {
        RunCombinedChartView(data: data, enabledLayers: enabledLayers,
                             chartHeight: chartHeight, playProgress: playProgress)
            .environment(\.shareChartPalette, palette)
            .padding(.top, 2)
            .padding(.bottom, 4)
            .frame(width: cardW)
            .background(palette.sectionBackground)
    }

    /// 세 조각을 위에서부터 빈틈없이 쌓는다 — 카드의 VStack(spacing: 0)과 같다.
    /// 합이 1350에 1~2px 못 미치면 남는 줄은 cardBackground(카드와 같은 색)로 남는다.
    private static func composeCardFrame(header: CGImage?, chart: CGImage?, tiles: CGImage?,
                                         palette: ShareChartPalette) -> UIImage {
        let size = CGSize(width: videoW, height: videoH)
        let fmt  = UIGraphicsImageRendererFormat()
        fmt.scale = 1; fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            UIColor(palette.cardBackground).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            var y: CGFloat = 0
            for img in [header, chart, tiles].compactMap({ $0 }) {
                let h = CGFloat(img.height)
                UIImage(cgImage: img).draw(in: CGRect(x: 0, y: y, width: CGFloat(videoW), height: h))
                y += h
            }
        }
    }
}
