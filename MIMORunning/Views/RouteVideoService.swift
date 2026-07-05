import AVFoundation
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Frame view (preview + render)

struct RouteVideoFrameView: View {
    let snapshot: UIImage
    /// Points pre-mapped via MKMapSnapshotter.Snapshot.point(for:) in renderSize space (540×960).
    let snapshotPoints: [CGPoint]
    let routeProgress: CGFloat        // 0 → 1
    let insightTitle: String
    let metrics: [ShareMetricItem]
    var raceName: String? = nil
    var miniMeVariant: MiniMeVariant? = nil
    var customMiniMeImage: UIImage? = nil
    var mood: Mood? = nil
    var memoText: String? = nil
    let distanceKm: String
    let duration: String
    let date: Date
    var weather: WeatherSnapshot? = nil
    var shoeName: String? = nil
    var chartPanel: CardChartPanel = .map
    var chartSplits: [SplitData] = []
    var chartHRSamples: [(offset: TimeInterval, bpm: Int)] = []
    var chartHRZones: [HRZoneData] = []
    var chartWorkoutSeries: [(offset: TimeInterval, value: Double)] = []
    var chartIntervalSegments: [IntervalSegment] = []
    var showStats: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let scale = w / 300   // 300 = VideoOverlayCard reference width; 540/300 = 1.8 at export
            ZStack(alignment: .bottom) {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()
                    .brightness(-0.08)
                    .saturation(0.85)

                RoutePolylineOverlay(snapshotPoints: snapshotPoints, progress: routeProgress)
                    .frame(width: w, height: h)

                if showStats {
                    VideoOverlayCard(
                        insightTitle: insightTitle,
                        distanceKm: distanceKm,
                        date: date,
                        metrics: metrics,
                        raceName: raceName,
                        miniMeVariant: miniMeVariant,
                        miniMeImage: customMiniMeImage,
                        mood: mood,
                        memoText: memoText,
                        chartPanel: chartPanel,
                        chartSplits: chartSplits,
                        chartHRSamples: chartHRSamples,
                        chartHRZones: chartHRZones,
                        chartWorkoutSeries: chartWorkoutSeries,
                        chartIntervalSegments: chartIntervalSegments,
                        weather: weather,
                        shoeName: shoeName,
                        scale: scale
                    )
                    .frame(width: w, height: h)
                }
            }
        }
    }
}

// MARK: - Route polyline canvas overlay

/// Draws the route using pre-mapped snapshot-space points, scaled to the actual canvas size.
private struct RoutePolylineOverlay: View {
    /// Points in renderSize (540×960) coordinate space, from MKMapSnapshotter.Snapshot.point(for:).
    let snapshotPoints: [CGPoint]
    let progress: CGFloat
    var totalDistanceM: Double = 0

    var body: some View {
        Canvas { ctx, size in
            guard snapshotPoints.count > 1, progress > 0 else { return }

            // scaledToFill: uniform scale so image covers the frame, then center-crop.
            let imgW = RouteVideoExportService.renderSize.width
            let imgH = RouteVideoExportService.renderSize.height
            let s    = max(size.width / imgW, size.height / imgH)
            let xOff = (size.width  - imgW * s) / 2
            let yOff = (size.height - imgH * s) / 2
            let pts  = snapshotPoints.map { CGPoint(x: $0.x * s + xOff, y: $0.y * s + yOff) }

            let endIdx = max(1, Int(CGFloat(pts.count - 1) * min(progress, 1.0)))
            let slice = Array(pts[0...endIdx])

            var path = Path()
            path.move(to: slice[0])
            for i in 1..<slice.count { path.addLine(to: slice[i]) }

            ctx.stroke(path, with: .color(Theme.violet.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(Theme.violet),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            let tip = slice[slice.count - 1]
            var glow = Path()
            glow.addEllipse(in: CGRect(x: tip.x - 11, y: tip.y - 11, width: 22, height: 22))
            ctx.fill(glow, with: .color(Theme.violet.opacity(0.38)))
            var dot = Path()
            dot.addEllipse(in: CGRect(x: tip.x - 6, y: tip.y - 6, width: 12, height: 12))
            ctx.fill(dot, with: .color(.white))

            // KM marker dots in preview (dots only, no text)
            if totalDistanceM > 100, pts.count > 1 {
                var cum: [Double] = [0]
                for i in 1..<pts.count {
                    let dx = Double(pts[i].x - pts[i-1].x)
                    let dy = Double(pts[i].y - pts[i-1].y)
                    cum.append(cum.last! + sqrt(dx*dx + dy*dy))
                }
                let totalPxLen = cum.last!
                guard totalPxLen > 0 else { return }

                let totalKm = totalDistanceM / 1000
                let interval: Double = totalKm <= 10 ? 1 : totalKm <= 21.5 ? 2 : 5
                let intervalM = interval * 1000

                func previewInterp(_ targetLen: Double) -> CGPoint {
                    for i in 1..<pts.count {
                        if cum[i] >= targetLen {
                            let segLen = cum[i] - cum[i-1]
                            let t = segLen > 0 ? CGFloat((targetLen - cum[i-1]) / segLen) : 0
                            return CGPoint(x: pts[i-1].x + t*(pts[i].x-pts[i-1].x),
                                           y: pts[i-1].y + t*(pts[i].y-pts[i-1].y))
                        }
                    }
                    return pts.last!
                }

                var targetM = intervalM
                while targetM < totalDistanceM - intervalM * 0.5 {
                    let frac = targetM / totalDistanceM
                    guard frac <= Double(progress) else { break }
                    let pos = previewInterp(frac * totalPxLen)
                    var d = Path()
                    d.addEllipse(in: CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8))
                    ctx.fill(d, with: .color(.white.opacity(0.85)))
                    targetM += intervalM
                }
                // Finish dot
                if Double(progress) >= 1.0, let lastPt = pts.last {
                    var d = Path()
                    d.addEllipse(in: CGRect(x: lastPt.x - 5, y: lastPt.y - 5, width: 10, height: 10))
                    ctx.fill(d, with: .color(Color(hex: "FFC74D")))
                }
            }
        }
    }
}

// MARK: - BigNumberRouteVideoFrameView

struct BigNumberRouteVideoFrameView: View {
    let snapshot: UIImage
    let snapshotPoints: [CGPoint]
    let routeProgress: CGFloat
    let activity: Activity
    let detail: ActivityDetail?
    let heroMetric: HeroMetric
    var mood: Mood? = nil
    var memoText: String? = nil
    var weatherText: String? = nil
    var weatherIcon: String? = nil
    let date: Date
    var shoeName: String? = nil

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()
                    .brightness(-0.08)
                    .saturation(0.85)

                RoutePolylineOverlay(snapshotPoints: snapshotPoints, progress: routeProgress)
                    .frame(width: w, height: h)

                BigNumberVideoOverlayView(
                    activity: activity, detail: detail, heroMetric: heroMetric,
                    mood: mood, memoText: memoText,
                    weatherText: weatherText, weatherIcon: weatherIcon,
                    date: date, shoeName: shoeName
                )
                .frame(width: w, height: h)
            }
        }
    }
}

// MARK: - KM Marker data

private struct KmMarkerInfo {
    let position: CGPoint   // UIKit pixel coords (y=0 at top, already × renderScale)
    let distanceM: Double
    let isFinish: Bool
    let pathFraction: Double  // 0…1 fraction of total distance
}

// MARK: - RouteVideoExportService

struct RouteVideoExportService {

    static let fps: Int32    = 30
    static let frameCount    = 450          // 15 s × 30 fps
    static let renderSize    = CGSize(width: 540, height: 960)
    static let renderScale: CGFloat = 2.0
    static var pixelSize: CGSize {
        CGSize(width: renderSize.width * renderScale, height: renderSize.height * renderScale)
    }
    static var videoDuration: Double { Double(frameCount) / Double(fps) }   // 15.0 s
    static var routeDuration: Double  { videoDuration - 1.0 }               // 14.0 s

    // MARK: Map snapshot + coordinate mapping

    static func mapSnapshot(
        coordinates: [CLLocationCoordinate2D]
    ) async throws -> (image: UIImage, points: [CGPoint]) {
        guard coordinates.count > 1 else { return (darkPlaceholder(), []) }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return (darkPlaceholder(), [])
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.005)
        )
        let opts        = MKMapSnapshotter.Options()
        opts.region     = MKCoordinateRegion(center: center, span: span)
        opts.size       = renderSize
        opts.scale      = renderScale
        opts.mapType    = .mutedStandard
        opts.showsBuildings = false

        let snap = try await MKMapSnapshotter(options: opts).start()

        let step = max(1, coordinates.count / 500)
        let points = Swift.stride(from: 0, to: coordinates.count, by: step).map { i in
            snap.point(for: coordinates[i])
        }

        return (snap.image, points)
    }

    private static func darkPlaceholder() -> UIImage {
        UIGraphicsImageRenderer(size: renderSize).image { ctx in
            UIColor(red: 0.05, green: 0.04, blue: 0.10, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: renderSize))
        }
    }

    // MARK: - Stage 2: CAShapeLayer + AVVideoCompositionCoreAnimationTool

    /// Export route video (VideoOverlayCard stats) using GPU-composited CAShapeLayer animation.
    /// Replaces the per-frame CVPixelBuffer loop.  1080×1920 HEVC, ~3-5 s on device.
    @MainActor
    static func exportFast(
        snapshot: UIImage,
        snapshotPoints: [CGPoint],
        insightTitle: String,
        distanceKm: String,
        duration: String,
        date: Date,
        metrics: [ShareMetricItem],
        raceName: String?,
        miniMeVariant: MiniMeVariant?,
        customMiniMeImage: UIImage?,
        mood: Mood?,
        memoText: String?,
        weather: WeatherSnapshot?,
        shoeName: String?,
        chartPanel: CardChartPanel,
        chartSplits: [SplitData],
        chartHRSamples: [(offset: TimeInterval, bpm: Int)],
        chartHRZones: [HRZoneData],
        chartWorkoutSeries: [(offset: TimeInterval, value: Double)],
        chartIntervalSegments: [IntervalSegment],
        totalDistanceM: Double,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        let t0 = CACurrentMediaTime()

        // 1. Pre-render overlay once (main thread, SwiftUI → CGImage)
        let overlayView = VideoOverlayCard(
            insightTitle: insightTitle, distanceKm: distanceKm, date: date,
            metrics: metrics, raceName: raceName,
            miniMeVariant: miniMeVariant, miniMeImage: customMiniMeImage,
            mood: mood, memoText: memoText,
            chartPanel: chartPanel, chartSplits: chartSplits,
            chartHRSamples: chartHRSamples, chartHRZones: chartHRZones,
            chartWorkoutSeries: chartWorkoutSeries, chartIntervalSegments: chartIntervalSegments,
            weather: weather, shoeName: shoeName,
            scale: renderSize.width / 300
        )
        .frame(width: renderSize.width, height: renderSize.height)
        let overlayRenderer = ImageRenderer(content: overlayView)
        overlayRenderer.scale = renderScale
        guard let overlayImage = overlayRenderer.uiImage,
              let overlayCGImage = overlayImage.cgImage else {
            throw NSError(domain: "RouteVideoExport", code: -2)
        }

        // 2. Convert Metal-backed snapshot to CPU CGImage via CIContext
        guard let ciMap = CIImage(image: snapshot),
              let mapCGImage = CIContext().createCGImage(ciMap, from: ciMap.extent) else {
            throw NSError(domain: "RouteVideoExport", code: -3)
        }

        // 3. Scaled route points (renderSize → pixel space)
        let scaledPoints = snapshotPoints.map {
            CGPoint(x: $0.x * renderScale, y: $0.y * renderScale)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_route_v2_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)

        try await exportWithCAShapeLayer(
            mapCGImage: mapCGImage,
            overlayCGImage: overlayCGImage,
            scaledPoints: scaledPoints,
            totalDistanceM: totalDistanceM,
            outputURL: outputURL,
            progressHandler: progressHandler
        )

        let elapsed   = CACurrentMediaTime() - t0
        let fileBytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        print("[RouteVideo v2] \(Int(pixelSize.width))×\(Int(pixelSize.height)) — \(String(format: "%.1f", elapsed))s — \(fileBytes / 1024)KB")
        return outputURL
    }

    /// Export route video (BigNumber overlay).
    @MainActor
    static func exportBigNumberFast(
        snapshot: UIImage,
        snapshotPoints: [CGPoint],
        activity: Activity,
        detail: ActivityDetail?,
        heroMetric: HeroMetric,
        mood: Mood?,
        memoText: String?,
        weatherText: String?,
        weatherIcon: String?,
        date: Date,
        shoeName: String?,
        totalDistanceM: Double,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        let t0 = CACurrentMediaTime()

        let overlayView = BigNumberVideoOverlayView(
            activity: activity, detail: detail, heroMetric: heroMetric,
            mood: mood, memoText: memoText,
            weatherText: weatherText, weatherIcon: weatherIcon,
            date: date, shoeName: shoeName
        )
        .frame(width: renderSize.width, height: renderSize.height)
        let overlayRenderer = ImageRenderer(content: overlayView)
        overlayRenderer.scale = renderScale
        guard let overlayImage = overlayRenderer.uiImage,
              let overlayCGImage = overlayImage.cgImage else {
            throw NSError(domain: "RouteVideoExport", code: -2)
        }

        guard let ciMap = CIImage(image: snapshot),
              let mapCGImage = CIContext().createCGImage(ciMap, from: ciMap.extent) else {
            throw NSError(domain: "RouteVideoExport", code: -3)
        }

        let scaledPoints = snapshotPoints.map {
            CGPoint(x: $0.x * renderScale, y: $0.y * renderScale)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_route_bn_v2_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)

        try await exportWithCAShapeLayer(
            mapCGImage: mapCGImage,
            overlayCGImage: overlayCGImage,
            scaledPoints: scaledPoints,
            totalDistanceM: totalDistanceM,
            outputURL: outputURL,
            progressHandler: progressHandler
        )

        let elapsed   = CACurrentMediaTime() - t0
        let fileBytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        print("[RouteVideo BN v2] \(Int(pixelSize.width))×\(Int(pixelSize.height)) — \(String(format: "%.1f", elapsed))s — \(fileBytes / 1024)KB")
        return outputURL
    }

    // MARK: - Core compositing engine

    private static func exportWithCAShapeLayer(
        mapCGImage: CGImage,
        overlayCGImage: CGImage,
        scaledPoints: [CGPoint],
        totalDistanceM: Double,
        outputURL: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        let px = pixelSize
        let routeDur = routeDuration
        let vidDur   = videoDuration

        // A. Write 2-frame background video (map + darken) — fast, same-pixel both frames
        let bgURL = try await writeBackgroundVideo(mapCGImage: mapCGImage, pixelSize: px)
        defer { try? FileManager.default.removeItem(at: bgURL) }

        // B. Build layer hierarchy
        //    parentLayer uses CG coords (y=0 at bottom) via isGeometryFlipped = true.
        //    Child layers position in parent's CG space; their own contents render in iOS space (y=0 top).
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: px)
        parentLayer.isGeometryFlipped = true

        // Video layer receives source video frames (the map)
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        if scaledPoints.count > 1 {
            // CAShapeLayer.path (local space, y=0 TOP) and layer.position (parent space)
            // both use the SAME UIKit coordinate convention under isGeometryFlipped=true.
            // Do NOT y-flip positions — empirically confirmed: stroke (no flip) aligns with map.
            let routePath = buildStrokePath(from: scaledPoints)

            // Start marker: static white ring at first point (UIKit coords, no flip)
            if let firstPt = scaledPoints.first {
                let startLayer = makeStartMarkerLayer(
                    position: CGPoint(x: firstPt.x, y: firstPt.y),
                    renderScale: renderScale
                )
                parentLayer.addSublayer(startLayer)
            }

            // Glow route stroke
            let glowRoute = CAShapeLayer()
            glowRoute.frame = parentLayer.frame
            glowRoute.path = routePath
            glowRoute.strokeColor = UIColor(Theme.violet).withAlphaComponent(0.35).cgColor
            glowRoute.lineWidth = 8 * renderScale
            glowRoute.fillColor = UIColor.clear.cgColor
            glowRoute.lineCap = .round; glowRoute.lineJoin = .round
            glowRoute.strokeEnd = 0
            glowRoute.add(strokeAnimation(duration: routeDur), forKey: "strokeEnd")
            parentLayer.addSublayer(glowRoute)

            // Core route stroke
            let coreRoute = CAShapeLayer()
            coreRoute.frame = parentLayer.frame
            coreRoute.path = routePath
            coreRoute.strokeColor = UIColor(Theme.violet).cgColor
            coreRoute.lineWidth = 3.5 * renderScale
            coreRoute.fillColor = UIColor.clear.cgColor
            coreRoute.lineCap = .round; coreRoute.lineJoin = .round
            coreRoute.strokeEnd = 0
            coreRoute.add(strokeAnimation(duration: routeDur), forKey: "strokeEnd")
            parentLayer.addSublayer(coreRoute)

            // Moving tip dot — same path as stroke (UIKit coords, no flip needed)
            let firstPt = scaledPoints[0]
            let rGlow: CGFloat = 11 * renderScale
            let rDot:  CGFloat = 5  * renderScale

            let tipGlow = makeCircleLayer(radius: rGlow,
                                          color: UIColor(Theme.violet).withAlphaComponent(0.38))
            tipGlow.position = firstPt
            tipGlow.add(pathAnimation(path: routePath, duration: routeDur), forKey: "position")
            parentLayer.addSublayer(tipGlow)

            let tipDot = makeCircleLayer(radius: rDot, color: .white)
            tipDot.position = firstPt
            tipDot.add(pathAnimation(path: routePath, duration: routeDur), forKey: "position")
            parentLayer.addSublayer(tipDot)

            // KM markers (position also UIKit coords, no flip)
            let markers = computeKmMarkers(snapshotPoints: scaledPoints, totalDistanceM: totalDistanceM)
            for m in markers {
                parentLayer.addSublayer(makeMarkerLayer(marker: m, pixelSize: px,
                                                        routeDuration: routeDur,
                                                        videoDuration: vidDur,
                                                        renderScale: renderScale))
            }
        }

        // Overlay layer: static, on top of everything
        let overlayLayer = CALayer()
        overlayLayer.frame = parentLayer.frame
        overlayLayer.contents = overlayCGImage
        parentLayer.addSublayer(overlayLayer)

        // C. Load background video track
        let bgAsset  = AVURLAsset(url: bgURL)
        let bgTracks = try await bgAsset.loadTracks(withMediaType: .video)
        guard let bgTrack = bgTracks.first else {
            throw NSError(domain: "RouteVideoExport", code: -9)
        }
        let bgRange = try await bgTrack.load(.timeRange)

        // D. Composition
        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw NSError(domain: "RouteVideoExport", code: -10) }
        try compTrack.insertTimeRange(bgRange, of: bgTrack, at: .zero)

        let videoComp = AVMutableVideoComposition()
        videoComp.frameDuration = CMTime(value: 1, timescale: fps)
        videoComp.renderSize = px
        videoComp.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = bgRange
        let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
        instruction.layerInstructions = [layerInstr]
        videoComp.instructions = [instruction]

        // E. Export via AVAssetExportSession (GPU-accelerated, no Swift frame loop)
        guard let exporter = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
        ) else { throw NSError(domain: "RouteVideoExport", code: -11) }
        exporter.videoComposition = videoComp
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov

        let progressTask = Task {
            while !Task.isCancelled {
                progressHandler(Double(exporter.progress))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { cont.resume() }
        }
        progressTask.cancel()
        progressHandler(1.0)

        guard exporter.status == .completed else {
            throw exporter.error ?? NSError(domain: "RouteVideoExport", code: -12,
                                            userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        }
    }

    // MARK: - Background video writer

    private static func writeBackgroundVideo(
        mapCGImage: CGImage,
        pixelSize: CGSize
    ) async throws -> URL {
        let px = pixelSize
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_bg_\(UUID().uuidString).mov")

        // Render map + darken into a single pixel buffer
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, Int(px.width), Int(px.height),
                                  kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let buf = pb else {
            throw NSError(domain: "RouteVideoExport", code: -6)
        }
        CVPixelBufferLockBaseAddress(buf, [])
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buf),
            width: Int(px.width), height: Int(px.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(buf, [])
            throw NSError(domain: "RouteVideoExport", code: -7)
        }
        ctx.draw(mapCGImage, in: CGRect(origin: .zero, size: px))
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.08).cgColor)
        ctx.fill(CGRect(origin: .zero, size: px))
        CVPixelBufferUnlockBaseAddress(buf, [])

        // Write 2 identical frames so the video duration = frameCount/fps (15 s)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input  = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(px.width), AVVideoHeightKey: Int(px.height),
            AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 0.85]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: nil
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Write all frameCount identical frames at 1/fps intervals.
        // HEVC compresses static P-frames to near-zero, so this is fast.
        // Two-frame approach caused AVAssetWriter to infer the last frame's duration
        // equal to the gap between frames → doubled video length (30s instead of 15s).
        for i in 0..<frameCount {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
        }

        input.markAsFinished()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "RouteVideoExport", code: -8)
        }
        return url
    }

    // MARK: - Layer factory helpers

    private static func strokeAnimation(duration: Double) -> CABasicAnimation {
        let anim = CABasicAnimation(keyPath: "strokeEnd")
        anim.fromValue = 0
        anim.toValue   = 1
        anim.duration  = duration
        anim.beginTime = AVCoreAnimationBeginTimeAtZero
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.fillMode  = .forwards
        anim.isRemovedOnCompletion = false
        return anim
    }

    private static func pathAnimation(path: CGPath, duration: Double) -> CAKeyframeAnimation {
        let anim = CAKeyframeAnimation(keyPath: "position")
        anim.path = path
        anim.duration = duration
        anim.beginTime = AVCoreAnimationBeginTimeAtZero
        anim.calculationMode = .paced
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        return anim
    }

    private static func makeCircleLayer(radius: CGFloat, color: UIColor) -> CALayer {
        let layer = CALayer()
        let d = radius * 2
        layer.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        layer.cornerRadius = radius
        layer.backgroundColor = color.cgColor
        return layer
    }

    private static func makeStartMarkerLayer(position: CGPoint, renderScale: CGFloat) -> CALayer {
        let ringR: CGFloat = 5 * renderScale
        let container = CALayer()
        let d = ringR * 2 + 4 * renderScale
        container.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        container.position = position

        let ring = CALayer()
        ring.bounds = CGRect(x: 0, y: 0, width: ringR * 2, height: ringR * 2)
        ring.position = CGPoint(x: d / 2, y: d / 2)
        ring.cornerRadius = ringR
        ring.borderWidth = 1.5 * renderScale
        ring.borderColor = UIColor.white.cgColor
        ring.backgroundColor = UIColor.clear.cgColor
        container.addSublayer(ring)
        return container
    }

    // MARK: - CGPath builders

    // For CAShapeLayer.path — drawn in layer's LOCAL space (y=0 at TOP on iOS).
    // With parentLayer.isGeometryFlipped=true the layer's local top = video top → use UIKit coords directly.
    private static func buildStrokePath(from points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }

    // MARK: - KM marker computation

    private static func computeKmMarkers(
        snapshotPoints: [CGPoint],
        totalDistanceM: Double
    ) -> [KmMarkerInfo] {
        guard snapshotPoints.count > 1, totalDistanceM > 100 else { return [] }

        let totalKm   = totalDistanceM / 1000
        let interval: Double = totalKm <= 10 ? 1 : totalKm <= 21.5 ? 2 : 5
        let intervalM = interval * 1000

        // Cumulative pixel-path length for each point
        var cum: [Double] = [0]
        for i in 1..<snapshotPoints.count {
            let dx = Double(snapshotPoints[i].x - snapshotPoints[i-1].x)
            let dy = Double(snapshotPoints[i].y - snapshotPoints[i-1].y)
            cum.append(cum.last! + sqrt(dx*dx + dy*dy))
        }
        let totalPixelLen = cum.last!
        guard totalPixelLen > 0 else { return [] }

        var markers: [KmMarkerInfo] = []

        var targetM = intervalM
        while targetM < totalDistanceM - intervalM * 0.5 {
            let frac   = targetM / totalDistanceM
            let pixelT = frac * totalPixelLen
            let pos    = interpolatePoint(at: pixelT, cum: cum, points: snapshotPoints)
            markers.append(KmMarkerInfo(position: pos, distanceM: targetM,
                                        isFinish: false, pathFraction: frac))
            targetM += intervalM
        }

        // Finish marker at last point
        markers.append(KmMarkerInfo(position: snapshotPoints.last!,
                                    distanceM: totalDistanceM,
                                    isFinish: true, pathFraction: 1.0))
        return markers
    }

    private static func interpolatePoint(
        at targetLen: Double,
        cum: [Double],
        points: [CGPoint]
    ) -> CGPoint {
        for i in 1..<points.count {
            if cum[i] >= targetLen {
                let segLen = cum[i] - cum[i-1]
                let t = segLen > 0 ? CGFloat((targetLen - cum[i-1]) / segLen) : 0
                return CGPoint(
                    x: points[i-1].x + t * (points[i].x - points[i-1].x),
                    y: points[i-1].y + t * (points[i].y - points[i-1].y)
                )
            }
        }
        return points.last!
    }

    // MARK: - Marker layer factory

    private static func makeMarkerLayer(
        marker: KmMarkerInfo,
        pixelSize: CGSize,
        routeDuration: Double,
        videoDuration: Double,
        renderScale: CGFloat
    ) -> CALayer {
        // position uses same UIKit coord convention as strokePath (y=0 at top, no flip)
        let csize: CGFloat = 80 * renderScale
        let half  = csize / 2
        let container = CALayer()
        container.bounds   = CGRect(x: 0, y: 0, width: csize, height: csize)
        container.position = marker.position
        container.opacity  = 0

        if marker.isFinish {
            let goldColor = UIColor(Color(hex: "FFC74D"))
            let glowR: CGFloat = 9 * renderScale
            let glow = makeCircleLayer(radius: glowR, color: goldColor.withAlphaComponent(0.40))
            glow.position = CGPoint(x: half, y: half)
            container.addSublayer(glow)

            let dotR: CGFloat = 5 * renderScale
            let dot = makeCircleLayer(radius: dotR, color: goldColor)
            dot.position = CGPoint(x: half, y: half)
            container.addSublayer(dot)
        } else {
            let dotR: CGFloat = 3.5 * renderScale
            let dot = makeCircleLayer(radius: dotR,
                                      color: UIColor.white.withAlphaComponent(0.85))
            dot.position = CGPoint(x: half, y: half)
            container.addSublayer(dot)

            // Pre-render label as CGImage — reliable in AVVideoCompositionCoreAnimationTool
            let km = Int((marker.distanceM / 1000).rounded())
            if let labelImg = makeKmLabelImage(km: km, renderScale: renderScale) {
                let lw = CGFloat(labelImg.width)
                let lh = CGFloat(labelImg.height)
                let gap: CGFloat = 5 * renderScale

                // Safe zone: flip label left if dot is near the right edge (60px safe margin)
                let nearRight = marker.position.x > pixelSize.width - 60 - dotR - gap - lw
                let labelX = nearRight
                    ? half - dotR - gap - lw / 2
                    : half + dotR + gap + lw / 2

                let labelLayer = CALayer()
                labelLayer.contents = labelImg
                labelLayer.bounds   = CGRect(x: 0, y: 0, width: lw, height: lh)
                labelLayer.position = CGPoint(x: labelX, y: half)
                container.addSublayer(labelLayer)
            }
        }

        // Full-span keyframe animations spanning the entire video duration.
        // This is more reliable than delayed CABasicAnimation + fillMode in AVVideoCompositionCoreAnimationTool.
        let tAppear  = marker.pathFraction * routeDuration / videoDuration
        let tPopEnd  = min((marker.pathFraction * routeDuration + 0.2) / videoDuration, 1.0)

        // Opacity: discrete jump from 0 to 1 at tAppear
        let opAnim = CAKeyframeAnimation(keyPath: "opacity")
        opAnim.values    = [0, 0, 1]
        opAnim.keyTimes  = [0, max(0, tAppear - 0.0001), tAppear + 0.0001].map { NSNumber(value: min($0, 1.0)) }
        opAnim.duration  = videoDuration
        opAnim.beginTime = AVCoreAnimationBeginTimeAtZero
        opAnim.fillMode  = .forwards
        opAnim.isRemovedOnCompletion = false
        container.add(opAnim, forKey: "opacity")

        // Scale: 0→1 pop over 0.2 s, stays at 1 for remainder
        let scAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        scAnim.values   = [0.001, 0.001, 1.0]
        scAnim.keyTimes = [0, tAppear, tPopEnd].map { NSNumber(value: $0) }
        scAnim.timingFunctions = [
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeOut)
        ]
        scAnim.duration  = videoDuration
        scAnim.beginTime = AVCoreAnimationBeginTimeAtZero
        scAnim.fillMode  = .forwards
        scAnim.isRemovedOnCompletion = false
        container.add(scAnim, forKey: "scale")
        return container
    }

    // MARK: - KM label image (pre-rendered CGImage, avoids CATextLayer rendering quirks)

    private static func makeKmLabelImage(km: Int, renderScale: CGFloat) -> CGImage? {
        let text     = "\(km)km"
        let fontSize = 12 * renderScale
        let font     = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let hPad: CGFloat = 5 * renderScale
        let vPad: CGFloat = 2.5 * renderScale
        let imgSize = CGSize(width: ceil(textSize.width + hPad * 2),
                             height: ceil(textSize.height + vPad * 2))
        // scale=1.0 → CGImage pixels == imgSize pixels (avoids 2x/3x screen-scale inflation)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        return UIGraphicsImageRenderer(size: imgSize, format: fmt).image { _ in
            UIColor.black.withAlphaComponent(0.65).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: imgSize),
                         cornerRadius: imgSize.height / 2).fill()
            (text as NSString).draw(at: CGPoint(x: hPad, y: vPad), withAttributes: attrs)
        }.cgImage
    }
}
