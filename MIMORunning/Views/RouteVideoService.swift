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
    // HR gradient for route polyline
    var hrSamplesForRoute: [(offset: TimeInterval, bpm: Int)] = []
    var routeWorkoutDuration: TimeInterval = 0
    var routeZoneBounds: [(id: Int, minBPM: Int)] = []
    var showHRGradient: Bool = false
    // nil → videoSafeTopRef/BottomRef * scale (export 기본값). 값 지정 시 그대로 사용 (preview 전용).
    var topInset: CGFloat? = nil
    var bottomInset: CGFloat? = nil

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
                    .brightness(CardVisual.videoBrightnessBoost)
                    .saturation(CardVisual.videoSaturationBoost)

                RoutePolylineOverlay(snapshotPoints: snapshotPoints, progress: routeProgress,
                                     hrSamples: hrSamplesForRoute,
                                     workoutDuration: routeWorkoutDuration,
                                     zoneBounds: routeZoneBounds,
                                     showHRGradient: showHRGradient)
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
                        scale: scale,
                        topInset: topInset,
                        bottomInset: bottomInset
                    )
                    .frame(width: w, height: h)
                    .preferredColorScheme(.dark)
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
    // HR gradient
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    var workoutDuration: TimeInterval = 0
    var zoneBounds: [(id: Int, minBPM: Int)] = []
    var showHRGradient: Bool = false

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

            if showHRGradient && slice.count > 1 && !hrSamples.isEmpty && !zoneBounds.isEmpty {
                let sortedBounds = zoneBounds.sorted { $0.minBPM < $1.minBPM }
                for i in 0..<(slice.count - 1) {
                    let offset = Double(i) / Double(max(pts.count - 1, 1)) * workoutDuration
                    let color = canvasGradientColor(bpm: canvasBPM(at: offset), sorted: sortedBounds)
                    var seg = Path(); seg.move(to: slice[i]); seg.addLine(to: slice[i+1])
                    ctx.stroke(seg, with: .color(color.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 7, lineCap: .round))
                }
                for i in 0..<(slice.count - 1) {
                    let offset = Double(i) / Double(max(pts.count - 1, 1)) * workoutDuration
                    let color = canvasGradientColor(bpm: canvasBPM(at: offset), sorted: sortedBounds)
                    var seg = Path(); seg.move(to: slice[i]); seg.addLine(to: slice[i+1])
                    ctx.stroke(seg, with: .color(color),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            } else {
                var path = Path()
                path.move(to: slice[0])
                for i in 1..<slice.count { path.addLine(to: slice[i]) }
                ctx.stroke(path, with: .color(Theme.violet.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                ctx.stroke(path, with: .color(Theme.violet),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

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
                let interval: Double = totalKm <= 22 ? 1 : totalKm <= 35 ? 2 : 5
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

    private func canvasBPM(at offset: TimeInterval) -> Int {
        let window = hrSamples.filter { abs($0.offset - offset) <= 2.5 }
        if window.isEmpty {
            return hrSamples.min(by: { abs($0.offset - offset) < abs($1.offset - offset) })?.bpm ?? 120
        }
        return window.reduce(0) { $0 + $1.bpm } / window.count
    }

    private func canvasGradientColor(bpm: Int, sorted: [(id: Int, minBPM: Int)]) -> Color {
        let colors = Theme.hrZoneColors
        guard sorted.count >= 2, !colors.isEmpty else { return Theme.violet }
        if bpm <= sorted[0].minBPM { return colors[0] }
        for i in 0..<(sorted.count - 1) {
            let lo = sorted[i].minBPM, hi = sorted[i+1].minBPM
            guard hi > lo, bpm < hi else { continue }
            let t = Double(bpm - lo) / Double(hi - lo)
            return lerpCanvasColor(colors[min(i, colors.count-1)], colors[min(i+1, colors.count-1)], t)
        }
        return colors[min(sorted.count-1, colors.count-1)]
    }

    private func lerpCanvasColor(_ a: Color, _ b: Color, _ t: Double) -> Color {
        var r1: CGFloat=0, g1: CGFloat=0, b1: CGFloat=0, a1: CGFloat=0
        var r2: CGFloat=0, g2: CGFloat=0, b2: CGFloat=0, a2: CGFloat=0
        UIColor(a).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(b).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let tc = CGFloat(max(0, min(1, t)))
        return Color(red: Double(r1+(r2-r1)*tc), green: Double(g1+(g2-g1)*tc), blue: Double(b1+(b2-b1)*tc))
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
    var accent: CardAccent = .violet
    // HR gradient for route polyline
    var hrSamplesForRoute: [(offset: TimeInterval, bpm: Int)] = []
    var routeWorkoutDuration: TimeInterval = 0
    var routeZoneBounds: [(id: Int, minBPM: Int)] = []
    var showHRGradient: Bool = false
    // nil → videoSafeTopRef/BottomRef * s (export 기본값). 값 지정 시 그대로 사용 (preview 전용).
    var topInset: CGFloat? = nil
    var bottomInset: CGFloat? = nil

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
                    .brightness(CardVisual.videoBrightnessBoost)
                    .saturation(CardVisual.videoSaturationBoost)

                RoutePolylineOverlay(snapshotPoints: snapshotPoints, progress: routeProgress,
                                     hrSamples: hrSamplesForRoute,
                                     workoutDuration: routeWorkoutDuration,
                                     zoneBounds: routeZoneBounds,
                                     showHRGradient: showHRGradient)
                    .frame(width: w, height: h)

                BigNumberVideoOverlayView(
                    activity: activity, detail: detail, heroMetric: heroMetric,
                    mood: mood, memoText: memoText,
                    weatherText: weatherText, weatherIcon: weatherIcon,
                    date: date, shoeName: shoeName,
                    topInset: topInset,
                    bottomInset: bottomInset,
                    accent: accent
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
    // renderSize = intermediate SwiftUI point space; pixelSize MUST equal VideoExportService.targetSize.
    // renderScale is derived — do NOT hardcode. Changing renderSize without updating renderScale
    // would silently produce a wrong output resolution.
    static let renderSize    = CGSize(width: 540, height: 960)
    static let renderScale: CGFloat = VideoExportService.targetSize.width / renderSize.width  // 1080/540 = 2.0
    static var pixelSize: CGSize { VideoExportService.targetSize }  // always 1080×1920
    static var videoDuration: Double { Double(frameCount) / Double(fps) }   // 15.0 s
    static var routeDuration: Double  { videoDuration - 1.0 }               // 14.0 s

    // MARK: - Stamp overlay config (애니메이션 분리 레이어용)

    /// 경로 영상 출력 시 스탬프·문구를 별도 CALayer로 애니메이션하기 위한 설정.
    /// 스탬프와 문구 각각 하나씩 생성해서 exportFast에 전달.
    struct StampLayerConfig {
        let image: UIImage             // renderOnlyStamp 또는 renderOnlyText로 렌더된 UIImage
        let entranceMode: StampEntranceMode
        let flyDirection: FlyInDirection
        let startTime: Double          // 영상 시작 기준 초 단위 (절대값)
        let animDuration: Double       // 애니메이션 지속 초 단위
    }

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

        // 시스템 라이트/다크 모드·시간대 무관하게 지도 외관을 항상 라이트로 고정
        let snap = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<MKMapSnapshotter.Snapshot, Error>) in
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                MKMapSnapshotter(options: opts).start { snapshot, error in
                    if let error { cont.resume(throwing: error); return }
                    guard let snapshot else {
                        cont.resume(throwing: NSError(domain: "RouteVideoExport", code: -4)); return
                    }
                    cont.resume(returning: snapshot)
                }
            }
        }

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
        hrSamplesForRoute: [(offset: TimeInterval, bpm: Int)] = [],
        routeWorkoutDuration: TimeInterval = 0,
        showHRGradient: Bool = false,
        stampLayers: [StampLayerConfig] = [],
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        let t0 = CACurrentMediaTime()

        // 1. Pre-render overlay once (main thread, SwiftUI → CGImage)
        // stampLayers 있으면 VideoOverlayCard 생략 — 스탬프 레이어가 별도 CALayer로 합성됨
        let overlayCGImage: CGImage?
        if stampLayers.isEmpty {
            let exportInset = renderSize.height * 0.05   // 5% = 48pt → 96px at renderScale 2 (preview 일치)
            let overlayView = VideoOverlayCard(
                insightTitle: insightTitle, distanceKm: distanceKm, date: date,
                metrics: metrics, raceName: raceName,
                miniMeVariant: miniMeVariant, miniMeImage: customMiniMeImage,
                mood: mood, memoText: memoText,
                chartPanel: chartPanel, chartSplits: chartSplits,
                chartHRSamples: chartHRSamples, chartHRZones: chartHRZones,
                chartWorkoutSeries: chartWorkoutSeries, chartIntervalSegments: chartIntervalSegments,
                weather: weather, shoeName: shoeName,
                scale: renderSize.width / 300,
                topInset: exportInset,
                bottomInset: exportInset
            )
            .frame(width: renderSize.width, height: renderSize.height)
            .preferredColorScheme(.dark)
            let overlayRenderer = ImageRenderer(content: overlayView)
            overlayRenderer.scale = renderScale
            guard let overlayImage = overlayRenderer.uiImage,
                  let cg = overlayImage.cgImage else {
                throw NSError(domain: "RouteVideoExport", code: -2)
            }
            overlayCGImage = cg
        } else {
            overlayCGImage = nil
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
            hrSamples: hrSamplesForRoute,
            workoutDuration: routeWorkoutDuration,
            showHRGradient: showHRGradient,
            miniMeImage: customMiniMeImage,
            stampLayers: stampLayers,
            outputURL: outputURL,
            progressHandler: progressHandler
        )

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
        hrSamplesForRoute: [(offset: TimeInterval, bpm: Int)] = [],
        routeWorkoutDuration: TimeInterval = 0,
        showHRGradient: Bool = false,
        miniMeImage: UIImage? = nil,
        accent: CardAccent = .violet,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        let t0 = CACurrentMediaTime()

        let exportInset = renderSize.height * 0.05   // 5% = 48pt → 96px at renderScale 2 (preview 일치)
        let overlayView = BigNumberVideoOverlayView(
            activity: activity, detail: detail, heroMetric: heroMetric,
            mood: mood, memoText: memoText,
            weatherText: weatherText, weatherIcon: weatherIcon,
            date: date, shoeName: shoeName,
            topInset: exportInset,
            bottomInset: exportInset,
            accent: accent
        )
        .frame(width: renderSize.width, height: renderSize.height)
        .preferredColorScheme(.dark)
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
            hrSamples: hrSamplesForRoute,
            workoutDuration: routeWorkoutDuration,
            showHRGradient: showHRGradient,
            miniMeImage: miniMeImage,
            showKmMarkers: false,
            outputURL: outputURL,
            progressHandler: progressHandler
        )

        return outputURL
    }

    // MARK: - Core compositing engine

    private static func exportWithCAShapeLayer(
        mapCGImage: CGImage,
        overlayCGImage: CGImage?,
        scaledPoints: [CGPoint],
        totalDistanceM: Double,
        hrSamples: [(offset: TimeInterval, bpm: Int)] = [],
        workoutDuration: TimeInterval = 0,
        showHRGradient: Bool = false,
        miniMeImage: UIImage? = nil,
        showKmMarkers: Bool = true,
        stampLayers: [StampLayerConfig] = [],
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

            let useGradient = showHRGradient && hrSamples.count >= 10
            if useGradient {
                // Gradient mode: ~50 micro-segments, each with its own color and timed strokeEnd
                let segCount = min(50, scaledPoints.count - 1)
                let step = (scaledPoints.count - 1) / segCount
                let sortedBounds = computeZoneBoundsStatic(from: hrSamples)

                // Glow pass — all micro-segments
                for si in 0..<segCount {
                    let i0 = si * step
                    let i1 = min(i0 + step, scaledPoints.count - 1)
                    let tStart = routeDur * Double(si) / Double(segCount)
                    let tEnd   = routeDur * Double(si + 1) / Double(segCount)
                    let midOffset = workoutDuration * Double(i0 + i1) / 2.0 / Double(scaledPoints.count - 1)
                    let bpm = smoothedBPMForVideo(at: midOffset, samples: hrSamples)
                    let color = gradientUIColorForVideo(bpm: bpm, bounds: sortedBounds)

                    let seg = UIBezierPath()
                    seg.move(to: scaledPoints[i0])
                    for j in (i0 + 1)...i1 { seg.addLine(to: scaledPoints[j]) }
                    seg.lineCapStyle = .round; seg.lineJoinStyle = .round

                    let layer = CAShapeLayer()
                    layer.frame = parentLayer.frame
                    layer.path = seg.cgPath
                    layer.strokeColor = color.withAlphaComponent(0.35).cgColor
                    layer.lineWidth = 8 * renderScale
                    layer.fillColor = UIColor.clear.cgColor
                    layer.lineCap = .round; layer.lineJoin = .round
                    layer.strokeEnd = 0
                    layer.add(segmentAnimation(tStart: tStart, tEnd: tEnd, totalDur: routeDur), forKey: "strokeEnd")
                    parentLayer.addSublayer(layer)
                }
                // Core pass — all micro-segments on top of glow
                for si in 0..<segCount {
                    let i0 = si * step
                    let i1 = min(i0 + step, scaledPoints.count - 1)
                    let tStart = routeDur * Double(si) / Double(segCount)
                    let tEnd   = routeDur * Double(si + 1) / Double(segCount)
                    let midOffset = workoutDuration * Double(i0 + i1) / 2.0 / Double(scaledPoints.count - 1)
                    let bpm = smoothedBPMForVideo(at: midOffset, samples: hrSamples)
                    let color = gradientUIColorForVideo(bpm: bpm, bounds: sortedBounds)

                    let seg = UIBezierPath()
                    seg.move(to: scaledPoints[i0])
                    for j in (i0 + 1)...i1 { seg.addLine(to: scaledPoints[j]) }
                    seg.lineCapStyle = .round; seg.lineJoinStyle = .round

                    let layer = CAShapeLayer()
                    layer.frame = parentLayer.frame
                    layer.path = seg.cgPath
                    layer.strokeColor = color.cgColor
                    layer.lineWidth = 3.5 * renderScale
                    layer.fillColor = UIColor.clear.cgColor
                    layer.lineCap = .round; layer.lineJoin = .round
                    layer.strokeEnd = 0
                    layer.add(segmentAnimation(tStart: tStart, tEnd: tEnd, totalDur: routeDur), forKey: "strokeEnd")
                    parentLayer.addSublayer(layer)
                }
            } else {
                // Single-color mode (original)
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
            }

            // Moving tip — choose animation axis: arc-length-keyed for gradient, path-based for solid
            // Gradient segments draw by point-index; .paced path animation uses arc-length → axis mismatch.
            // gradientTipAnimation rebuilds keyframes from the same arc-length-per-segment logic.
            let firstPt = scaledPoints[0]
            let tipPositionAnim: CAAnimation
            if useGradient {
                let segC = min(50, scaledPoints.count - 1)
                let stp  = max(1, (scaledPoints.count - 1) / segC)
                tipPositionAnim = gradientTipAnimation(
                    scaledPoints: scaledPoints, segCount: segC, step: stp, routeDur: routeDur
                )
            } else {
                tipPositionAnim = pathAnimation(path: routePath, duration: routeDur)
            }

            if let uiImg = miniMeImage, let cgImg = uiImg.cgImage {
                let markerR: CGFloat = 20 * renderScale   // 80px diameter (~7% of 1080px)
                let borderW: CGFloat = 2  * renderScale
                let imageR  = markerR - borderW

                // White outer circle — border ring and drop shadow
                let borderLayer = makeCircleLayer(radius: markerR, color: .white)
                borderLayer.shadowOpacity = 0.45
                borderLayer.shadowRadius  = 4 * renderScale
                borderLayer.shadowOffset  = CGSize(width: 0, height: 2 * renderScale)
                borderLayer.shadowColor   = UIColor.black.cgColor
                borderLayer.position = firstPt
                borderLayer.add(tipPositionAnim, forKey: "position")
                parentLayer.addSublayer(borderLayer)

                // Circular image layer (sits on top, slightly smaller)
                let imageLayer = CALayer()
                let imgD = imageR * 2
                imageLayer.bounds = CGRect(x: 0, y: 0, width: imgD, height: imgD)
                imageLayer.position = firstPt
                imageLayer.contents = cgImg
                imageLayer.contentsGravity = .resizeAspectFill
                imageLayer.masksToBounds = true
                imageLayer.cornerRadius = imageR
                imageLayer.add(tipPositionAnim, forKey: "position")
                parentLayer.addSublayer(imageLayer)
            } else {
                let rGlow: CGFloat = 11 * renderScale
                let rDot:  CGFloat = 5  * renderScale

                let tipGlow = makeCircleLayer(radius: rGlow,
                                              color: UIColor(Theme.violet).withAlphaComponent(0.38))
                tipGlow.position = firstPt
                tipGlow.add(tipPositionAnim, forKey: "position")
                parentLayer.addSublayer(tipGlow)

                let tipDot = makeCircleLayer(radius: rDot, color: .white)
                tipDot.position = firstPt
                tipDot.add(tipPositionAnim, forKey: "position")
                parentLayer.addSublayer(tipDot)
            }

            // KM markers — route video only (BigNumber card uses showKmMarkers: false)
            if showKmMarkers {
                let markers = computeKmMarkers(snapshotPoints: scaledPoints, totalDistanceM: totalDistanceM)
                for m in markers {
                    parentLayer.addSublayer(makeMarkerLayer(marker: m, pixelSize: px,
                                                            routeDuration: routeDur,
                                                            videoDuration: vidDur,
                                                            renderScale: renderScale))
                }
            }
        }

        // Overlay layer: static, on top of everything (nil = no static overlay, e.g. stamp mode)
        if let cg = overlayCGImage {
            let overlayLayer = CALayer()
            overlayLayer.frame = parentLayer.frame
            overlayLayer.contents = cg
            parentLayer.addSublayer(overlayLayer)
        }

        // Stamp animated layers: 스탬프·문구 각각 별도 CALayer로 애니메이션
        for config in stampLayers {
            if let stampLayer = makeStampAnimatedLayer(config: config, px: px, vidDur: vidDur) {
                parentLayer.addSublayer(stampLayer)
            }
        }

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
        // Use HEVCHighestQuality — same codec as VideoExportService for consistent output.
        guard let exporter = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHEVCHighestQuality
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

    // MARK: - Stamp animated layer

    /// StampLayerConfig의 image를 CALayer contents로 설정하고 입장 애니메이션을 적용한다.
    /// km 마커와 동일한 full-span keyframe 방식(AVVideoCompositionCoreAnimationTool 호환).
    private static func makeStampAnimatedLayer(config: StampLayerConfig, px: CGSize, vidDur: Double) -> CALayer? {
        // Metal 백 이미지 대응: .cgImage 실패 시 CIContext 변환 (경로 스냅샷과 동일한 패턴)
        let cgImage: CGImage
        if let direct = config.image.cgImage {
            cgImage = direct
        } else if let ci = CIImage(image: config.image),
                  let converted = CIContext().createCGImage(ci, from: ci.extent) {
            cgImage = converted
        } else {
            return nil
        }

        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: px)
        layer.contents = cgImage
        // opacity는 모델 값을 건드리지 않음 — km 마커와 동일하게 keyframe 애니메이션만으로 제어
        // (opacity=0 을 직접 설정하면 AVVideoCompositionCoreAnimationTool 이 레이어를 합성 제외할 수 있음)

        let tStart = config.startTime / vidDur
        let tEnd   = min(tStart + config.animDuration / vidDur, 0.9999)
        let tMid1  = tStart + (tEnd - tStart) * 0.5
        let tMid2  = tStart + (tEnd - tStart) * 0.8
        func kf(_ t: Double) -> NSNumber { NSNumber(value: max(0, min(1, t))) }

        // 공통 helper: full-span keyframe 기준값 세팅
        func applyCommon(_ anim: CAKeyframeAnimation) {
            anim.duration = vidDur
            anim.beginTime = AVCoreAnimationBeginTimeAtZero
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
        }

        switch config.entranceMode {
        case .none:
            // tStart 시점에 즉시 등장
            let op = CAKeyframeAnimation(keyPath: "opacity")
            op.values   = [0, 0, 1, 1]
            op.keyTimes = [kf(0), kf(tStart - 0.0001), kf(tStart + 0.0001), kf(1)]
            applyCommon(op)
            layer.add(op, forKey: "opacity")

        case .fade:
            // tStart → tEnd 동안 페이드인
            let op = CAKeyframeAnimation(keyPath: "opacity")
            op.values   = [0, 0, 1, 1]
            op.keyTimes = [kf(0), kf(tStart), kf(tEnd), kf(1)]
            applyCommon(op)
            layer.add(op, forKey: "opacity")

        case .stamp:
            // 즉시 등장 + 스프링 스케일 0 → 1.15 → 0.95 → 1
            let op = CAKeyframeAnimation(keyPath: "opacity")
            op.values   = [0, 0, 1, 1]
            op.keyTimes = [kf(0), kf(tStart - 0.0001), kf(tStart), kf(1)]
            applyCommon(op)
            layer.add(op, forKey: "opacity")

            let sc = CAKeyframeAnimation(keyPath: "transform.scale")
            sc.values   = [0.001, 0.001, 1.15, 0.95, 1.0, 1.0]
            sc.keyTimes = [kf(0), kf(tStart), kf(tMid1), kf(tMid2), kf(tEnd), kf(1)]
            sc.timingFunctions = [
                CAMediaTimingFunction(name: .linear),
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeIn),
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .linear)
            ]
            applyCommon(sc)
            layer.add(sc, forKey: "scale")

        case .flyIn:
            // 즉시 등장 + 방향에서 슬라이드 인
            let op = CAKeyframeAnimation(keyPath: "opacity")
            op.values   = [0, 0, 1, 1]
            op.keyTimes = [kf(0), kf(tStart - 0.0001), kf(tStart), kf(1)]
            applyCommon(op)
            layer.add(op, forKey: "opacity")

            let (dx, dy): (CGFloat, CGFloat)
            switch config.flyDirection {
            case .leading:  (dx, dy) = (-px.width, 0)
            case .trailing: (dx, dy) = ( px.width, 0)
            case .bottom:   (dx, dy) = (0, px.height)
            }

            if dx != 0 {
                let tx = CAKeyframeAnimation(keyPath: "transform.translation.x")
                tx.values   = [0, dx, 0, 0]
                tx.keyTimes = [kf(0), kf(tStart), kf(tEnd), kf(1)]
                tx.timingFunctions = [
                    CAMediaTimingFunction(name: .linear),
                    CAMediaTimingFunction(name: .easeOut),
                    CAMediaTimingFunction(name: .linear)
                ]
                applyCommon(tx)
                layer.add(tx, forKey: "translateX")
            }
            if dy != 0 {
                let ty = CAKeyframeAnimation(keyPath: "transform.translation.y")
                ty.values   = [0, dy, 0, 0]
                ty.keyTimes = [kf(0), kf(tStart), kf(tEnd), kf(1)]
                ty.timingFunctions = [
                    CAMediaTimingFunction(name: .linear),
                    CAMediaTimingFunction(name: .easeOut),
                    CAMediaTimingFunction(name: .linear)
                ]
                applyCommon(ty)
                layer.add(ty, forKey: "translateY")
            }
        }

        return layer
    }

    /// Position animation synchronized to the gradient segment draw.
    /// Gradient segments divide scaledPoints into `segCount` groups of `step` points each.
    /// Each group draws over 1/segCount of routeDur. Within a group the progress is arc-length-keyed
    /// so the tip position exactly tracks the strokeEnd tip rather than jumping ahead.
    private static func gradientTipAnimation(
        scaledPoints: [CGPoint],
        segCount: Int,
        step: Int,
        routeDur: Double
    ) -> CAKeyframeAnimation {
        let n = scaledPoints.count
        guard n > 1 else {
            let anim = CAKeyframeAnimation(keyPath: "position")
            anim.values = [NSValue(cgPoint: scaledPoints.first ?? .zero)]
            anim.duration = routeDur
            anim.beginTime = AVCoreAnimationBeginTimeAtZero
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            return anim
        }

        // Cumulative arc length at each scaledPoint (pixel-space distance)
        var cumLen = [CGFloat](repeating: 0, count: n)
        for i in 1..<n {
            let dx = scaledPoints[i].x - scaledPoints[i-1].x
            let dy = scaledPoints[i].y - scaledPoints[i-1].y
            cumLen[i] = cumLen[i-1] + sqrt(dx*dx + dy*dy)
        }

        // Build per-point keyTimes that mirror each gradient segment's time window.
        // For point j in segment si: time = tStart[si] + arcFrac * (tEnd[si] - tStart[si])
        var keyTimes = [NSNumber]()
        var values   = [NSValue]()
        keyTimes.reserveCapacity(n)
        values.reserveCapacity(n)

        for j in 0..<n {
            let si     = min(j / max(1, step), segCount - 1)
            let i0     = si * step
            let i1     = min(i0 + step, n - 1)
            let tStart = routeDur * Double(si)     / Double(segCount)
            let tEnd   = routeDur * Double(si + 1) / Double(segCount)
            let segLen = cumLen[i1] - cumLen[i0]
            let relArc = segLen > 0 ? Double((cumLen[j] - cumLen[i0]) / segLen) : 0
            let t      = tStart + relArc * (tEnd - tStart)
            keyTimes.append(NSNumber(value: max(0, min(1, t / routeDur))))
            values.append(NSValue(cgPoint: scaledPoints[j]))
        }

        #if DEBUG
        // Validate: at p=0.25/0.50/0.75 the tip should be within a few pixels of the strokeEnd.
        for p in [0.25, 0.50, 0.75] {
            let t   = routeDur * p
            let si  = min(Int(p * Double(segCount)), segCount - 1)
            let i0  = si * step; let i1 = min(i0 + step, n - 1)
            let tS  = routeDur * Double(si)     / Double(segCount)
            let tE  = routeDur * Double(si + 1) / Double(segCount)
            let frac = tE > tS ? (t - tS) / (tE - tS) : 0
            // Where the gradient strokeEnd is at time t (arc-length within segment)
            let targetLen = cumLen[i0] + CGFloat(frac) * (cumLen[i1] - cumLen[i0])
            var lo2 = i0; var hi2 = i1
            while lo2 + 1 < hi2 {
                let mid = (lo2 + hi2) / 2
                if cumLen[mid] <= targetLen { lo2 = mid } else { hi2 = mid }
            }
            let segL2 = cumLen[hi2] - cumLen[lo2]
            let tk = segL2 > 0 ? (targetLen - cumLen[lo2]) / segL2 : 0
            let strokePt = CGPoint(
                x: scaledPoints[lo2].x + tk * (scaledPoints[hi2].x - scaledPoints[lo2].x),
                y: scaledPoints[lo2].y + tk * (scaledPoints[hi2].y - scaledPoints[lo2].y)
            )
            // Where the tip keyframe animation lands at time p
            let kts = keyTimes.map { $0.doubleValue }
            let loK = kts.lastIndex(where: { $0 <= p }) ?? 0
            let hiK = min(loK + 1, n - 1)
            let miniMePt: CGPoint
            if loK == hiK {
                miniMePt = scaledPoints[loK]
            } else {
                let range = kts[hiK] - kts[loK]
                let fk = range > 0 ? CGFloat((p - kts[loK]) / range) : 0
                let a = scaledPoints[loK]; let b = scaledPoints[hiK]
                miniMePt = CGPoint(x: a.x + fk * (b.x - a.x), y: a.y + fk * (b.y - a.y))
            }
            let dx = strokePt.x - miniMePt.x; let dy = strokePt.y - miniMePt.y
            print(String(format: "[RouteVideo] p=%.2f 선끝=(%d,%d) 미니미=(%d,%d) 거리차=%.0fpx",
                         p, Int(strokePt.x), Int(strokePt.y),
                         Int(miniMePt.x), Int(miniMePt.y), sqrt(dx*dx + dy*dy)))
        }
        #endif

        let anim = CAKeyframeAnimation(keyPath: "position")
        anim.values              = values
        anim.keyTimes            = keyTimes
        anim.calculationMode     = .linear
        anim.duration            = routeDur
        anim.beginTime           = AVCoreAnimationBeginTimeAtZero
        anim.fillMode            = .forwards
        anim.isRemovedOnCompletion = false
        return anim
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
        let interval: Double = totalKm <= 22 ? 1 : totalKm <= 35 ? 2 : 5
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

    // MARK: - Gradient helpers (CAShapeLayer path)

    private static func segmentAnimation(tStart: Double, tEnd: Double, totalDur: Double) -> CABasicAnimation {
        let anim = CABasicAnimation(keyPath: "strokeEnd")
        anim.fromValue = 0
        anim.toValue   = 1
        anim.duration  = max(tEnd - tStart, 0.01)
        anim.beginTime = AVCoreAnimationBeginTimeAtZero + tStart
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.fillMode  = .forwards
        anim.isRemovedOnCompletion = false
        return anim
    }

    private static func computeZoneBoundsStatic(from samples: [(offset: TimeInterval, bpm: Int)]) -> [(id: Int, minBPM: Int)] {
        guard !samples.isEmpty else { return [] }
        let peak = min(220, Int(Double(samples.map(\.bpm).max() ?? 180) / 0.90))
        return [
            (1, 0),
            (2, Int(Double(peak) * 0.60)),
            (3, Int(Double(peak) * 0.70)),
            (4, Int(Double(peak) * 0.80)),
            (5, Int(Double(peak) * 0.90))
        ]
    }

    private static func smoothedBPMForVideo(at offset: TimeInterval, samples: [(offset: TimeInterval, bpm: Int)]) -> Int {
        let window = samples.filter { abs($0.offset - offset) <= 2.5 }
        if window.isEmpty {
            guard let nearest = samples.min(by: { abs($0.offset - offset) < abs($1.offset - offset) }) else { return 60 }
            return nearest.bpm
        }
        return window.reduce(0) { $0 + $1.bpm } / window.count
    }

    private static func gradientUIColorForVideo(bpm: Int, bounds: [(id: Int, minBPM: Int)]) -> UIColor {
        let sorted = bounds.sorted { $0.minBPM < $1.minBPM }
        let colors = Theme.hrZoneColors.map { UIColor($0) }
        guard sorted.count >= 2, !colors.isEmpty else { return UIColor(Theme.violet) }
        if bpm <= sorted[0].minBPM { return colors[0] }
        for i in 0..<(sorted.count - 1) {
            let lo = sorted[i].minBPM, hi = sorted[i+1].minBPM
            guard hi > lo, bpm < hi else { continue }
            let t = CGFloat(bpm - lo) / CGFloat(hi - lo)
            return lerpUIColorStatic(colors[min(i, colors.count-1)], colors[min(i+1, colors.count-1)], t)
        }
        return colors[min(sorted.count-1, colors.count-1)]
    }

    private static func lerpUIColorStatic(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat=0, g1: CGFloat=0, b1: CGFloat=0, a1: CGFloat=0
        var r2: CGFloat=0, g2: CGFloat=0, b2: CGFloat=0, a2: CGFloat=0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let tc = max(0, min(1, t))
        return UIColor(red: r1+(r2-r1)*tc, green: g1+(g2-g1)*tc, blue: b1+(b2-b1)*tc, alpha: 1)
    }
}
