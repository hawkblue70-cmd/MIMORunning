import AVFoundation
import CoreLocation
import MapKit
import SwiftUI

// MARK: - ReplayContent

enum ReplayContent: String, CaseIterable {
    case data  = "데이터"
    case route = "경로"
    case both  = "둘 다"
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
        let topPad:  Int
        let headerH: Int
        let chartH:  Int   // 0 when mode = .route
        let routeH:  Int   // 0 when mode = .data
        let tilesH:  Int
        let botPad:  Int
        let compact: Bool  // .both: 3-col × 2-row, 0.85× tile scale

        var headerTop: Int { topPad }
        var chartTop:  Int { headerTop + headerH }
        // Route comes after chart (chartH may be 0)
        var routeTop:  Int { chartTop  + chartH  }
        var tilesTop:  Int { routeTop  + routeH  }

        static func make(_ content: ReplayContent) -> SectionLayout {
            switch content {
            case .data:
                // 24+190+620+460+56 = 1350
                return SectionLayout(topPad:24,headerH:190,chartH:620,routeH:0,  tilesH:460,botPad:56,compact:false)
            case .route:
                // 24+190+0+720+360+56 = 1350
                return SectionLayout(topPad:24,headerH:190,chartH:0,  routeH:720,tilesH:360,botPad:56,compact:false)
            case .both:
                // 20+170+480+420+240+20 = 1350
                return SectionLayout(topPad:20,headerH:170,chartH:480,routeH:420,tilesH:240,botPad:20,compact:true)
            }
        }
    }

    // MARK: - Public API

    /// Exports the chart/route animation to a temporary H.264 mp4 (1080×1350).
    /// If `content` requires route but `routeCoordinates` is empty, falls back to `.data`.
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
        routeCoordinates: [CLLocationCoordinate2D] = [],
        content: ReplayContent = .data,
        duration: TimeInterval = 10,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {

        let hasRoute = routeCoordinates.count >= 2
        let actual   = (content != .data && !hasRoute) ? .data : content
        let layout   = SectionLayout.make(actual)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_chart_\(UUID().uuidString).mp4")

        // ── AVAssetWriter setup ──────────────────────────────────────────────
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

        // ── Static sections rendered once ────────────────────────────────────
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

        let tilesImg = renderCGImage(
            ReplayTilesView(
                data: data, enabledLayers: enabledLayers,
                height: tilesPtH, compact: layout.compact
            ),
            width: cardW, height: tilesPtH
        )

        // ── Map snapshot (once, if needed) ────────────────────────────────────
        var mapCGImage:  CGImage? = nil
        var mapPoints:   [CGPoint] = []
        var cumDist:     [Double] = []

        if actual != .data && hasRoute {
            let routePtH = CGFloat(layout.routeH) / scale
            if let (img, pts) = try? await chartMapSnapshot(
                coordinates: routeCoordinates,
                ptSize: CGSize(width: cardW, height: routePtH)
            ) {
                mapCGImage = img.cgImage
                mapPoints  = pts
            }
            cumDist = buildCumulativeDistances(routeCoordinates)
        }

        // ── Frame loop ────────────────────────────────────────────────────────
        do {
            for frameIdx in 0..<totalFrames {
                try Task.checkCancellation()

                let t: Double = frameIdx < animFrames
                    ? Double(frameIdx) / Double(max(1, animFrames - 1))
                    : 1.0

                // Animated chart section (per-frame, nil if mode = .route)
                let chartImg: CGImage? = layout.chartH > 0 ? renderCGImage(
                    RunCombinedChartView(
                        data: data,
                        enabledLayers: enabledLayers,
                        chartHeight: chartPtH,
                        playProgress: t
                    )
                    .frame(width: cardW, height: chartPtH)
                    .background(Color.black),
                    width: cardW, height: chartPtH
                ) : nil

                guard let pb = compositeFrame(
                    layout: layout,
                    headerImage: headerImg,
                    chartImage:  chartImg,
                    mapCGImage:  mapCGImage,
                    mapPoints:   mapPoints,
                    cumDist:     cumDist,
                    routeProgress: t,
                    tilesImage:  tilesImg
                ) else { continue }

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

    // MARK: - Preview frame (first frame as static CGImage for sheet thumbnail)

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
        content: ReplayContent,
        routeCoordinates: [CLLocationCoordinate2D]
    ) -> CGImage? {
        let actual = (content != .data && routeCoordinates.count < 2) ? ReplayContent.data : content
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
                chartHeight: chartPtH, playProgress: 0
            )
            .frame(width: cardW, height: chartPtH)
            .background(Color.black),
            width: cardW, height: chartPtH
        ) : nil
        let tilesImg = renderCGImage(
            ReplayTilesView(data: data, enabledLayers: enabledLayers,
                            height: tilesPtH, compact: layout.compact),
            width: cardW, height: tilesPtH
        )
        return compositeFrame(
            layout: layout, headerImage: headerImg, chartImage: chartImg,
            mapCGImage: nil, mapPoints: [], cumDist: [], routeProgress: 0,
            tilesImage: tilesImg
        ).flatMap { pb -> CGImage? in
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
            guard let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(pb),
                width: videoW, height: videoH,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                            CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
    }

    // MARK: - Composite frame → CVPixelBuffer

    private static func compositeFrame(
        layout: SectionLayout,
        headerImage: CGImage?,
        chartImage:  CGImage?,
        mapCGImage:  CGImage?,
        mapPoints:   [CGPoint],
        cumDist:     [Double],
        routeProgress: Double,
        tilesImage:  CGImage?
    ) -> CVPixelBuffer? {

        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil, videoW, videoH,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let pixelBuffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let ctx = CGContext(
            data:             CVPixelBufferGetBaseAddress(pixelBuffer),
            width:            videoW,
            height:           videoH,
            bitsPerComponent: 8,
            bytesPerRow:      CVPixelBufferGetBytesPerRow(pixelBuffer),
            space:            CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:       CGBitmapInfo.byteOrder32Little.rawValue |
                              CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        // Flip to top-left origin
        ctx.translateBy(x: 0, y: CGFloat(videoH))
        ctx.scaleBy(x: 1, y: -1)

        // Black fill
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: videoW, height: videoH))

        // Draw a CGImage into a top-left-origin pixel rect
        func stamp(_ img: CGImage, yTop: Int, h: Int) {
            ctx.draw(img, in: CGRect(x: 0, y: CGFloat(yTop), width: CGFloat(videoW), height: CGFloat(h)))
        }

        if let img = headerImage { stamp(img, yTop: layout.headerTop, h: layout.headerH) }
        if let img = chartImage, layout.chartH > 0 { stamp(img, yTop: layout.chartTop, h: layout.chartH) }

        // Route section
        if layout.routeH > 0 {
            let routeRect = CGRect(x: 0, y: CGFloat(layout.routeTop),
                                   width: CGFloat(videoW), height: CGFloat(layout.routeH))
            ctx.saveGState()
            ctx.clip(to: routeRect)

            if let mapImg = mapCGImage {
                // aspectFill map image into route rect
                let iw = CGFloat(mapImg.width), ih = CGFloat(mapImg.height)
                let s  = max(routeRect.width / iw, routeRect.height / ih)
                let drawn = CGRect(
                    x: routeRect.midX - iw * s / 2,
                    y: routeRect.midY - ih * s / 2,
                    width: iw * s, height: ih * s
                )
                ctx.draw(mapImg, in: drawn)
            } else {
                // Dark placeholder when no map
                ctx.setFillColor(UIColor(red:0.07, green:0.06, blue:0.14, alpha:1).cgColor)
                ctx.fill(routeRect)
            }

            ctx.restoreGState()

            if mapPoints.count > 1 {
                drawRoutePolyline(
                    ctx: ctx,
                    points: mapPoints,
                    progress: routeProgress,
                    cumDist: cumDist,
                    routeRect: routeRect
                )
            }
        }

        if let img = tilesImage { stamp(img, yTop: layout.tilesTop, h: layout.tilesH) }

        return pixelBuffer
    }

    // MARK: - Route polyline (CGContext, cumulative-distance progress)

    private static func drawRoutePolyline(
        ctx: CGContext,
        points: [CGPoint],    // in snapshot pt-space (cardW wide)
        progress: Double,
        cumDist: [Double],
        routeRect: CGRect     // pixel rect, top-left origin after ctx flip
    ) {
        guard points.count > 1 else { return }

        // Map snapshot-pt → pixel: snapshot was requested at cardW × routePtH pt
        // so scale is simply `scale` (3.6) for both axes, offset by route section top
        func px(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * scale, y: routeRect.minY + p.y * scale)
        }
        let allPx = points.map { px($0) }

        // End index using cumulative distance ratio (not coordinate-count ratio)
        let endIdx = distanceIndex(at: progress, cumDist: cumDist, total: points.count)

        // ── Full route (dim ghost) ──
        let fullPath = CGMutablePath()
        fullPath.move(to: allPx[0])
        allPx.dropFirst().forEach { fullPath.addLine(to: $0) }
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
        ctx.setLineWidth(2); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addPath(fullPath); ctx.strokePath()

        guard endIdx > 0 else { return }
        let travPx = Array(allPx.prefix(endIdx + 1))

        // ── Traveled route ──
        let travPath = CGMutablePath()
        travPath.move(to: travPx[0])
        travPx.dropFirst().forEach { travPath.addLine(to: $0) }

        // Casing (black)
        ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(5.5)
        ctx.addPath(travPath); ctx.strokePath()

        // Colour line
        ctx.setStrokeColor(UIColor(Theme.chartPace).cgColor)
        ctx.setLineWidth(3.5)
        ctx.addPath(travPath); ctx.strokePath()

        // ── Current position marker ──
        let tip = travPx[travPx.count - 1]
        let violet = UIColor(Theme.violet)

        // Glow halo
        ctx.setFillColor(violet.withAlphaComponent(0.25).cgColor)
        ctx.fillEllipse(in: CGRect(x: tip.x-14, y: tip.y-14, width: 28, height: 28))

        // White outer circle
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: tip.x-7, y: tip.y-7, width: 14, height: 14))

        // Violet fill
        ctx.setFillColor(violet.cgColor)
        ctx.fillEllipse(in: CGRect(x: tip.x-5, y: tip.y-5, width: 10, height: 10))
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

    // MARK: - Map snapshot (sized to section)

    private static func chartMapSnapshot(
        coordinates: [CLLocationCoordinate2D],
        ptSize: CGSize   // section dimensions in pt
    ) async throws -> (UIImage, [CGPoint]) {
        guard coordinates.count > 1 else {
            return (placeholderMapImage(size: ptSize), [])
        }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max()
        else { return (placeholderMapImage(size: ptSize), []) }

        let opts     = MKMapSnapshotter.Options()
        opts.region  = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat+maxLat)/2,
                                           longitude: (minLon+maxLon)/2),
            span:   MKCoordinateSpan(
                latitudeDelta: max((maxLat-minLat)*1.6, 0.005),
                longitudeDelta: max((maxLon-minLon)*1.6, 0.005)
            )
        )
        opts.size         = ptSize
        opts.scale        = scale   // matches video render scale (3.6)
        opts.mapType      = .mutedStandard
        opts.showsBuildings = false

        let snap = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<MKMapSnapshotter.Snapshot, Error>) in
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
        let points = stride(from: 0, to: coordinates.count, by: step).map { snap.point(for: coordinates[$0]) }
        return (snap.image, points)
    }

    private static func placeholderMapImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red:0.07, green:0.06, blue:0.14, alpha:1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - ImageRenderer helper

    private static func renderCGImage<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content:
            view.preferredColorScheme(.dark)
        )
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
    let height:       CGFloat   // pt

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
                            Text(w).font(.system(size: 9, weight: .medium)).foregroundStyle(Color.yellow.opacity(0.85))
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
    let height:       CGFloat   // pt
    let compact:      Bool      // 0.85× scale, max 6 tiles

    private let spacing: CGFloat = 3
    private var maxTiles: Int { compact ? 6 : 12 }
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
    let s:      CGFloat   // scale multiplier (1.0 or 0.85)

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
