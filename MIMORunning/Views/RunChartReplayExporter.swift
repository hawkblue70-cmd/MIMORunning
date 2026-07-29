import AVFoundation
import CoreLocation
import MapKit
import SwiftUI

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
        let maxTiles:      Int
        let compact:       Bool

        var headerTop: Int { topPad }
        var routeTop:  Int { headerTop + headerH }
        var chartTop:  Int { routeTop  + routeH  + mapChartGap   }
        var tilesTop:  Int { chartTop  + chartH  + chartTilesGap }

        static func make(_ content: ReplayContent) -> SectionLayout {
            switch content {
            case .chartData:
                // 24+190 | 620 | 460 | 56 = 1350
                return SectionLayout(topPad:24, headerH:190, routeH:0,   mapChartGap:0,
                                     chartH:620, chartTilesGap:0, tilesH:460, botPad:56,
                                     maxTiles:12, compact:false)
            case .routeData:
                // 24+190 | 700 | 380 | 56 = 1350
                return SectionLayout(topPad:24, headerH:190, routeH:700, mapChartGap:0,
                                     chartH:0,   chartTilesGap:0, tilesH:380, botPad:56,
                                     maxTiles:6, compact:false)
            case .routeChart:
                // 24+170 | 520 | 12 | 570 | 54 = 1350
                return SectionLayout(topPad:24, headerH:170, routeH:520, mapChartGap:12,
                                     chartH:570, chartTilesGap:0, tilesH:0, botPad:54,
                                     maxTiles:0, compact:false)
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
        totalDuration: TimeInterval = 0,
        routeCoordinates: [CLLocationCoordinate2D] = [],
        content: ReplayContent = .chartData,
        duration: TimeInterval = 10,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {

        let hasRoute = routeCoordinates.count >= 2
        let needsRoute = content == .routeData || content == .routeChart
        let actual   = (needsRoute && !hasRoute) ? ReplayContent.chartData : content
        let layout   = SectionLayout.make(actual)
        print("[Replay] content:\(actual) coords:\(routeCoordinates.count) routeH:\(layout.routeH)")

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
        let headerPtH = CGFloat(layout.headerH) / scale
        let tilesPtH  = CGFloat(layout.tilesH)  / scale
        let chartPtH  = CGFloat(layout.chartH)  / scale

        let headerImg = renderCGImage(
            ReplayHeaderView(
                distanceText: distanceText, durationText: durationText,
                weatherText: weatherText,   weatherIcon: weatherIcon,
                dateText: dateText,         weekdayText: weekdayText,
                startTimeText: startTimeText, shoeText: shoeText,
                height: headerPtH
            ),
            width: cardW, height: headerPtH
        )

        let tilesImg: CGImage? = layout.tilesH > 0 ? renderCGImage(
            ReplayTilesView(
                data: data, enabledLayers: enabledLayers,
                height: tilesPtH, maxTiles: layout.maxTiles, compact: layout.compact
            ),
            width: cardW, height: tilesPtH
        ) : nil

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
                    pixelSize: snapSize
                )
                mapUIImage = img
                mapPoints  = pts
            } catch {
                print("[Replay] snapshot FAILED:", error)
            }
            cumDist = buildCumulativeDistances(routeCoordinates)
        }
        logMapDiagnostics(routeCoordCount: routeCoordinates.count,
                          mapUIImage: mapUIImage, layout: layout)

        let timeDistTable = buildTimeDistanceTable(data: data, totalDuration: totalDuration)
        let videoSize = CGSize(width: videoW, height: videoH)

        // ── Frame loop ────────────────────────────────────────────────────────
        do {
            for frameIdx in 0..<totalFrames {
                try Task.checkCancellation()

                let t: Double = frameIdx < animFrames
                    ? Double(frameIdx) / Double(max(1, animFrames - 1))
                    : 1.0

                let chartImg: CGImage? = layout.chartH > 0 ? renderCGImage(
                    RunCombinedChartView(
                        data: data,
                        enabledLayers: enabledLayers,
                        chartHeight: chartPtH,
                        playProgress: t,
                        endLabelMinGap: 11
                    )
                    .frame(width: cardW, height: chartPtH)
                    .background(Color.black),
                    width: cardW, height: chartPtH
                ) : nil

                let frame = composeFrame(
                    layout: layout, data: data, totalDuration: totalDuration,
                    headerImage: headerImg, chartImage: chartImg,
                    mapUIImage: mapUIImage, mapPoints: mapPoints,
                    cumDist: cumDist, timeDistTable: timeDistTable,
                    routeCoordinates: routeCoordinates,
                    timeProgress: t, tilesImage: tilesImg
                )

                #if DEBUG
                if frameIdx == 0 { debugSaveFirstFrame(frame) }
                #endif

                guard let pb = pixelBuffer(from: frame, size: videoSize) else { continue }

                while !videoIn.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }
                let pts = CMTime(value: CMTimeValue(frameIdx), timescale: CMTimeScale(videoFPS))
                adaptor.append(pb, withPresentationTime: pts)
                onProgress(Double(frameIdx + 1) / Double(totalFrames))
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

    // MARK: - Preview frame

    static func previewCGImage(
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
        totalDuration: TimeInterval = 0,
        content: ReplayContent,
        routeCoordinates: [CLLocationCoordinate2D]
    ) -> CGImage? {
        let needsRoute = content == .routeData || content == .routeChart
        let actual = (needsRoute && routeCoordinates.count < 2) ? ReplayContent.chartData : content
        let layout = SectionLayout.make(actual)
        let headerPtH = CGFloat(layout.headerH) / scale
        let chartPtH  = CGFloat(layout.chartH)  / scale
        let tilesPtH  = CGFloat(layout.tilesH)  / scale

        let headerImg = renderCGImage(
            ReplayHeaderView(
                distanceText: distanceText, durationText: durationText,
                weatherText: weatherText,   weatherIcon: weatherIcon,
                dateText: dateText,         weekdayText: weekdayText,
                startTimeText: startTimeText, shoeText: shoeText,
                height: headerPtH
            ),
            width: cardW, height: headerPtH
        )
        let chartImg: CGImage? = layout.chartH > 0 ? renderCGImage(
            RunCombinedChartView(
                data: data, enabledLayers: enabledLayers,
                chartHeight: chartPtH, playProgress: 0, endLabelMinGap: 11
            )
            .frame(width: cardW, height: chartPtH)
            .background(Color.black),
            width: cardW, height: chartPtH
        ) : nil
        let tilesImg: CGImage? = layout.tilesH > 0 ? renderCGImage(
            ReplayTilesView(data: data, enabledLayers: enabledLayers,
                            height: tilesPtH, maxTiles: layout.maxTiles, compact: layout.compact),
            width: cardW, height: tilesPtH
        ) : nil

        return composeFrame(
            layout: layout, data: data, totalDuration: totalDuration,
            headerImage: headerImg, chartImage: chartImg,
            mapUIImage: nil, mapPoints: [], cumDist: [],
            timeDistTable: [], routeCoordinates: [],
            timeProgress: 0, tilesImage: tilesImg
        ).cgImage
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
        totalDuration: TimeInterval = 0,
        routeCoordinates: [CLLocationCoordinate2D] = [],
        content: ReplayContent,
        progress: Double = 0.45
    ) async -> UIImage? {
        let hasRoute = routeCoordinates.count >= 2
        let needsRoute = content == .routeData || content == .routeChart
        let actual = (needsRoute && !hasRoute) ? ReplayContent.chartData : content
        let layout = SectionLayout.make(actual)

        let headerPtH = CGFloat(layout.headerH) / scale
        let chartPtH  = CGFloat(layout.chartH)  / scale
        let tilesPtH  = CGFloat(layout.tilesH)  / scale

        let headerImg = renderCGImage(
            ReplayHeaderView(
                distanceText: distanceText, durationText: durationText,
                weatherText: weatherText,   weatherIcon: weatherIcon,
                dateText: dateText,         weekdayText: weekdayText,
                startTimeText: startTimeText, shoeText: shoeText,
                height: headerPtH
            ),
            width: cardW, height: headerPtH
        )
        let chartImg: CGImage? = layout.chartH > 0 ? renderCGImage(
            RunCombinedChartView(
                data: data, enabledLayers: enabledLayers,
                chartHeight: chartPtH, playProgress: progress, endLabelMinGap: 11
            )
            .frame(width: cardW, height: chartPtH)
            .background(Color.black),
            width: cardW, height: chartPtH
        ) : nil
        let tilesImg: CGImage? = layout.tilesH > 0 ? renderCGImage(
            ReplayTilesView(data: data, enabledLayers: enabledLayers,
                            height: tilesPtH, maxTiles: layout.maxTiles, compact: layout.compact),
            width: cardW, height: tilesPtH
        ) : nil

        var mapUIImage: UIImage? = nil
        var mapPoints:  [CGPoint] = []
        var cumDist:    [Double] = []

        if layout.routeH > 0 && hasRoute {
            let snapSize = CGSize(width: CGFloat(videoW), height: CGFloat(layout.routeH))
            do {
                let (img, pts) = try await chartMapSnapshot(
                    coordinates: routeCoordinates,
                    pixelSize: snapSize
                )
                mapUIImage = img
                mapPoints  = pts
            } catch {
                print("[Preview] snapshot FAILED:", error)
            }
            cumDist = buildCumulativeDistances(routeCoordinates)
        }
        logMapDiagnostics(routeCoordCount: routeCoordinates.count,
                          mapUIImage: mapUIImage, layout: layout)

        let timeDistTable = buildTimeDistanceTable(data: data, totalDuration: totalDuration)
        return composeFrame(
            layout: layout, data: data, totalDuration: totalDuration,
            headerImage: headerImg, chartImage: chartImg,
            mapUIImage: mapUIImage, mapPoints: mapPoints,
            cumDist: cumDist, timeDistTable: timeDistTable,
            routeCoordinates: routeCoordinates,
            timeProgress: progress, tilesImage: tilesImg
        )
    }

    // MARK: - Debug helpers

    #if DEBUG
    static func debugSaveFirstFrame(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
    #endif

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
        timeDistTable: [(timeRatio: Double, distanceRatio: Double)],
        routeCoordinates: [CLLocationCoordinate2D] = [],
        timeProgress: Double,
        tilesImage:  CGImage?
    ) -> UIImage {
        let size = CGSize(width: videoW, height: videoH)
        let fmt  = UIGraphicsImageRendererFormat()
        fmt.scale  = 1          // 1pt = 1px — we work entirely in pixel space
        fmt.opaque = true

        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            // Black background
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            // Stamp a CGImage into a UIKit-coordinate rect (y measured from top)
            func stamp(_ img: CGImage, yTop: Int, h: Int) {
                UIImage(cgImage: img).draw(in:
                    CGRect(x: 0, y: CGFloat(yTop), width: CGFloat(videoW), height: CGFloat(h)))
            }

            if let img = headerImage { stamp(img, yTop: layout.headerTop, h: layout.headerH) }
            if let img = chartImage, layout.chartH > 0 {
                stamp(img, yTop: layout.chartTop, h: layout.chartH)
            }

            // Route map section
            if layout.routeH > 0 {
                let routeRect = CGRect(x: 0, y: CGFloat(layout.routeTop),
                                       width: CGFloat(videoW), height: CGFloat(layout.routeH))

                // Clip then draw map (aspectFill)
                let ctx = UIGraphicsGetCurrentContext()!
                ctx.saveGState()
                UIBezierPath(rect: routeRect).addClip()

                if let mapImg = mapUIImage {
                    let pixW = mapImg.size.width * mapImg.scale
                    let pixH = mapImg.size.height * mapImg.scale
                    if pixW > 0, pixH > 0 {
                        let s = max(routeRect.width / pixW, routeRect.height / pixH)
                        let drawn = CGRect(
                            x: routeRect.midX - pixW * s / 2,
                            y: routeRect.midY - pixH * s / 2,
                            width: pixW * s, height: pixH * s
                        )
                        mapImg.draw(in: drawn)
                    } else {
                        UIColor(red: 0.07, green: 0.06, blue: 0.14, alpha: 1).setFill()
                        UIRectFill(routeRect)
                    }
                } else {
                    UIColor(red: 0.07, green: 0.06, blue: 0.14, alpha: 1).setFill()
                    UIRectFill(routeRect)
                }

                ctx.restoreGState()

                let distRatio = timeToDistanceRatio(timeRatio: timeProgress, table: timeDistTable)
                if mapPoints.count > 1 {
                    // Snapshot-derived points: use them directly
                    drawRoutePolyline(ctx: ctx, points: mapPoints,
                                      distanceProgress: distRatio,
                                      timeProgress: timeProgress,
                                      cumDist: cumDist, routeRect: routeRect,
                                      totalKm: data.totalKm, totalDuration: totalDuration)
                } else if routeCoordinates.count >= 2 {
                    // Fallback: draw route from raw lat/lon (no map tile background)
                    drawRouteFromCoordinates(ctx: ctx, coordinates: routeCoordinates,
                                             distanceProgress: distRatio,
                                             timeProgress: timeProgress,
                                             cumDist: cumDist, routeRect: routeRect,
                                             totalKm: data.totalKm, totalDuration: totalDuration)
                }
            }

            if let img = tilesImage, layout.tilesH > 0 {
                stamp(img, yTop: layout.tilesTop, h: layout.tilesH)
            }
        }
    }

    // MARK: - UIImage → CVPixelBuffer (flip applied only here)

    private static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
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
        points: [CGPoint],    // snapshot pt-space (cardW wide, origin top-left)
        distanceProgress: Double,
        timeProgress: Double,
        cumDist: [Double],
        routeRect: CGRect,    // pixel rect in UIKit space (y from top)
        totalKm: Double,
        totalDuration: TimeInterval
    ) {
        guard points.count > 1 else { return }

        // snapshot points are already in pixel space (scale=1 request),
        // so just offset by routeRect.minY for the vertical section position
        func px(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x, y: routeRect.minY + p.y)
        }
        let allPx = points.map { px($0) }
        let endIdx = distanceIndex(at: distanceProgress, cumDist: cumDist, total: points.count)

        // Full ghost route
        let fullPath = CGMutablePath()
        fullPath.move(to: allPx[0])
        allPx.dropFirst().forEach { fullPath.addLine(to: $0) }
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
        ctx.setLineWidth(2); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addPath(fullPath); ctx.strokePath()

        if endIdx > 0 {
            let travPx = Array(allPx.prefix(endIdx + 1))
            let travPath = CGMutablePath()
            travPath.move(to: travPx[0])
            travPx.dropFirst().forEach { travPath.addLine(to: $0) }

            // Casing
            ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(5.5)
            ctx.addPath(travPath); ctx.strokePath()

            // Colored line
            ctx.setStrokeColor(UIColor(Theme.chartPace).cgColor)
            ctx.setLineWidth(3.5)
            ctx.addPath(travPath); ctx.strokePath()

            // Position marker
            let tip = travPx[travPx.count - 1]
            let violet = UIColor(Theme.violet)
            ctx.setFillColor(violet.withAlphaComponent(0.25).cgColor)
            ctx.fillEllipse(in: CGRect(x: tip.x-14, y: tip.y-14, width: 28, height: 28))
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: tip.x-7, y: tip.y-7, width: 14, height: 14))
            ctx.setFillColor(violet.cgColor)
            ctx.fillEllipse(in: CGRect(x: tip.x-5, y: tip.y-5, width: 10, height: 10))
        }

        drawRouteProgressLabel(timeProgress: timeProgress, distanceProgress: distanceProgress,
                               totalKm: totalKm, totalDuration: totalDuration,
                               routeRect: routeRect)
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
        totalDuration: TimeInterval
    ) {
        guard coordinates.count >= 2 else { return }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max()
        else { return }

        let latRange = max(maxLat - minLat, 0.0001)
        let lonRange = max(maxLon - minLon, 0.0001)

        // Aspect-preserving fit within 85% of routeRect
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
            let ny = CGFloat(1.0 - (c.latitude - minLat) / latRange)  // y-flip: lat↑ = y↓
            return CGPoint(x: ox + nx * boxW, y: oy + ny * boxH)
        }

        // Downsample for performance (~500 pts max)
        let step = max(1, coordinates.count / 500)
        let sampled = stride(from: 0, to: coordinates.count, by: step).map { coordinates[$0] }
        let allPx   = sampled.map { toPixel($0) }
        let endIdx  = distanceIndex(at: distanceProgress, cumDist: cumDist, total: allPx.count)

        // Ghost route
        let fullPath = CGMutablePath()
        fullPath.move(to: allPx[0])
        allPx.dropFirst().forEach { fullPath.addLine(to: $0) }
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.22).cgColor)
        ctx.setLineWidth(2); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addPath(fullPath); ctx.strokePath()

        if endIdx > 0 {
            let travPx = Array(allPx.prefix(endIdx + 1))
            let travPath = CGMutablePath()
            travPath.move(to: travPx[0])
            travPx.dropFirst().forEach { travPath.addLine(to: $0) }

            ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(5.5); ctx.addPath(travPath); ctx.strokePath()

            ctx.setStrokeColor(UIColor(Theme.chartPace).cgColor)
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

        drawRouteProgressLabel(timeProgress: timeProgress, distanceProgress: distanceProgress,
                               totalKm: totalKm, totalDuration: totalDuration, routeRect: routeRect)
    }

    private static func drawRouteProgressLabel(
        timeProgress: Double,
        distanceProgress: Double,
        totalKm: Double,
        totalDuration: TimeInterval,
        routeRect: CGRect
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

        let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let attrStr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: UIColor.white
        ])
        let textSize = attrStr.size()
        let padH: CGFloat = 10, padV: CGFloat = 6
        let bgW = textSize.width + padH * 2
        let bgH = textSize.height + padV * 2
        let bgX = routeRect.midX - bgW / 2
        let bgY = routeRect.minY + 14

        UIColor.black.withAlphaComponent(0.70).setFill()
        UIBezierPath(roundedRect: CGRect(x: bgX, y: bgY, width: bgW, height: bgH),
                     cornerRadius: bgH / 2).fill()
        attrStr.draw(at: CGPoint(x: bgX + padH, y: bgY + padV))
    }

    // MARK: - Time ↔ Distance (splits-based)

    private static func buildTimeDistanceTable(
        data: RunChartData,
        totalDuration: TimeInterval
    ) -> [(timeRatio: Double, distanceRatio: Double)] {
        guard let paceSeries = data.series[.pace],
              !paceSeries.points.isEmpty,
              data.totalKm > 0,
              totalDuration > 0 else { return [] }

        let pts = paceSeries.points.sorted { $0.km < $1.km }
        var entries: [(km: Double, sec: Double)] = [(0, 0)]
        for i in 0..<pts.count {
            let prevKm = i == 0 ? 0.0 : pts[i-1].km
            let delta  = max(0, pts[i].km - prevKm)
            let added  = delta * pts[i].value   // pace is sec/km
            entries.append((pts[i].km, entries.last!.sec + added))
        }
        let totalSec = max(1, entries.last?.sec ?? totalDuration)
        return entries.map { (timeRatio: $0.sec / totalSec, distanceRatio: $0.km / data.totalKm) }
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
        pixelSize: CGSize   // pixel dimensions; scale=1 so points returned are in pixel space
    ) async throws -> (UIImage, [CGPoint]) {
        guard coordinates.count > 1 else { return (placeholderMapImage(size: pixelSize), []) }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max()
        else { return (placeholderMapImage(size: pixelSize), []) }

        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat+maxLat)/2,
                                           longitude: (minLon+maxLon)/2),
            span: MKCoordinateSpan(
                latitudeDelta:  max((maxLat-minLat)*1.6, 0.005),
                longitudeDelta: max((maxLon-minLon)*1.6, 0.005)
            )
        )
        opts.size         = pixelSize
        opts.scale        = 1   // fractional scales (e.g. 3.6) are rejected by MKMapSnapshotter
        opts.mapType      = .mutedStandard
        opts.showsBuildings = false

        let snap = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<MKMapSnapshotter.Snapshot, Error>) in
            UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
                MKMapSnapshotter(options: opts).start { snapshot, error in
                    if let error { cont.resume(throwing: error); return }
                    guard let snapshot else {
                        cont.resume(throwing: NSError(domain: "chartMapSnapshot", code: -1)); return
                    }
                    cont.resume(returning: snapshot)
                }
            }
        }

        let step = max(1, coordinates.count / 500)
        let pts = stride(from: 0, to: coordinates.count, by: step)
            .map { snap.point(for: coordinates[$0]) }
        return (snap.image, pts)
    }

    private static func placeholderMapImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.07, green: 0.06, blue: 0.14, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - SwiftUI → CGImage

    private static func renderCGImage<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view.preferredColorScheme(.dark))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        return renderer.cgImage
    }
}

// MARK: - ReplayHeaderView

private struct ReplayHeaderView: View {
    let distanceText: String
    let durationText: String
    let weatherText:  String?
    let weatherIcon:  String?
    let dateText:     String?
    let weekdayText:  String?
    let startTimeText: String?
    let shoeText:     String?
    let height:       CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
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
                            Text(d).font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.72))
                        }
                        if let w = weekdayText {
                            Text(w).font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.yellow.opacity(0.85))
                        }
                        if let t = startTimeText {
                            Text(t).font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.72))
                        }
                    }
                }
            }
            Spacer(minLength: 6)
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
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: "5CE5D5").opacity(0.12), in: Capsule())
                }
                if let shoe = shoeText {
                    Label(shoe, systemImage: "shoe.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.chartElev.opacity(0.90))
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(width: RunChartReplayExporter.cardW, height: height, alignment: .center)
        .background(Color.black)
    }
}

// MARK: - ReplayTilesView

private struct ReplayTilesView: View {
    let data:         RunChartData
    let enabledLayers: Set<RunChartLayer>
    let height:       CGFloat
    let maxTiles:     Int
    let compact:      Bool

    private let spacing: CGFloat = 3
    private var tileScale: CGFloat { compact ? 0.85 : 1.0 }

    private var activeTiles: [RunChartLayer] {
        Array(data.availableLayers
            .filter { $0.isValueOnly || enabledLayers.contains($0) }
            .prefix(maxTiles))
    }

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: spacing),
         GridItem(.flexible(), spacing: spacing),
         GridItem(.flexible(), spacing: spacing)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(activeTiles) { layer in
                if let series = data.series[layer] {
                    ReplayTileCell(layer: layer, series: series, s: tileScale)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: RunChartReplayExporter.cardW, height: height, alignment: .top)
        .background(Color(red: 0.10, green: 0.10, blue: 0.10))
    }
}

private struct ReplayTileCell: View {
    let layer:  RunChartLayer
    let series: RunChartSeries
    let s:      CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * s) {
            HStack(spacing: 4 * s) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(layer.color)
                    .frame(width: 6 * s, height: 6 * s)
                Text(layer.shortLabel)
                    .font(.system(size: 9.5 * s))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                if !layer.isValueOnly {
                    Text("\(layer.formattedRange(series.minValue))–\(layer.formattedRange(series.maxValue))")
                        .font(.system(size: 8.5 * s))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2 * s) {
                Text(layer.formatted(series.avgValue))
                    .font(.system(size: 12 * s, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.80)
                    .lineLimit(1)
                Text(layer.unit)
                    .font(.system(size: 8.5 * s))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8 * s)
        .padding(.vertical, 4 * s)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9 * s))
    }
}
