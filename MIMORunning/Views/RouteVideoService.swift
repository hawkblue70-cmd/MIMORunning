import AVFoundation
import CoreLocation
import MapKit
import SwiftUI

private func metricsRows(_ items: [ShareMetricItem]) -> [[ShareMetricItem]] {
    let capped = Array(items.prefix(6))
    guard capped.count == 6 else { return [capped] }
    return [Array(capped.prefix(3)), Array(capped.suffix(3))]
}

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
    let distanceKm: String
    let duration: String
    let date: Date
    var weather: WeatherSnapshot? = nil

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let scale = w / 300          // 300 = standard card width; 540/300 = 1.8 at export
            ZStack(alignment: .bottom) {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()

                RoutePolylineOverlay(snapshotPoints: snapshotPoints, progress: routeProgress)
                    .frame(width: w, height: h)

                LinearGradient(
                    colors: [Color.black.opacity(0.92), Color.black.opacity(0.68), Color.clear],
                    startPoint: .bottom,
                    endPoint: UnitPoint(x: 0.5, y: 0.55)
                )

                statsPanel(scale: scale)
            }
        }
    }

    private var startDateTimeString: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "yyyy. M. d  a h:mm"
        return df.string(from: date)
    }

    @ViewBuilder
    private func statsPanel(scale: CGFloat) -> some View {
        let pad: CGFloat = 14 * scale

        VStack(alignment: .leading, spacing: 0) {
            // Wordmark
            HStack(spacing: 0) {
                Text("MIMO")
                    .font(.system(size: 9 * scale, weight: .black))
                    .tracking(2)
                    .foregroundStyle(.white)
                Text(" RUNNING")
                    .font(.system(size: 9 * scale, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.violet)
            }
            .padding(.horizontal, pad)
            .padding(.top, 14 * scale)

            // Insight title
            if !insightTitle.isEmpty {
                Text(insightTitle)
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, pad)
                    .padding(.top, 3 * scale)
            }

            // Badges + MiniMe row
            let hasBadges = raceName != nil || miniMeVariant != nil || customMiniMeImage != nil
            if hasBadges {
                HStack(spacing: 5 * scale) {
                    if let race = raceName {
                        HStack(spacing: 3 * scale) {
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 6.5 * scale, weight: .semibold))
                            Text(race)
                                .font(.system(size: 7 * scale, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.violet)
                        .padding(.horizontal, 5 * scale)
                        .padding(.vertical, 2 * scale)
                        .background(Theme.violet.opacity(0.22))
                        .clipShape(Capsule())
                    }
                    Spacer()
                    if let img = customMiniMeImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 26 * scale, height: 26 * scale)
                            .clipShape(Circle())
                    } else if let v = miniMeVariant {
                        MiniMeView(variant: v, size: 26 * scale)
                    }
                }
                .padding(.horizontal, pad)
                .padding(.top, 4 * scale)
            }

            Spacer()

            // Date · Divider · Stats (athletic style)
            if let w = weather {
                HStack(spacing: 3 * scale) {
                    Image(systemName: w.systemIcon)
                        .font(.system(size: 8 * scale))
                    Text(w.formattedTemp)
                        .font(.system(size: 8 * scale, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.80))
                .padding(.horizontal, pad)
                .padding(.bottom, 2 * scale)
            }
            Text(startDateTimeString)
                .font(.system(size: 9 * scale, weight: .medium))
                .foregroundStyle(.white.opacity(0.80))
                .padding(.horizontal, pad)
                .padding(.bottom, 3 * scale)

            Rectangle()
                .fill(Theme.violet.opacity(0.30))
                .frame(height: 0.5)
                .padding(.horizontal, pad)

            HStack(alignment: .center, spacing: 0) {
                let distW: CGFloat = (metrics.count >= 5 ? 70 : 96) * scale
                let distPt: CGFloat = (metrics.count >= 5 ? 28 : 38) * scale
                HStack(alignment: .lastTextBaseline, spacing: 3 * scale) {
                    Text(distanceKm)
                        .font(.system(size: distPt, weight: .black).width(.condensed))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("KM")
                        .font(.system(size: 10 * scale, weight: .bold).width(.condensed))
                        .foregroundStyle(Theme.violet)
                        .padding(.bottom, 2 * scale)
                }
                .fixedSize(horizontal: true, vertical: true)
                .frame(width: distW, alignment: .leading)
                .padding(.leading, pad)

                if !metrics.isEmpty {
                    Rectangle()
                        .fill(.white.opacity(0.07))
                        .frame(width: 0.5, height: 36 * scale)

                    let rows = metricsRows(metrics)
                    VStack(spacing: rows.count > 1 ? 3 * scale : 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 0) {
                                ForEach(row) { m in
                                    VStack(spacing: 1) {
                                        Text(m.value)
                                            .font(.system(size: (row.count >= 5 ? 11 : 12) * scale,
                                                          weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                        Text(m.label)
                                            .font(.system(size: 8 * scale, weight: .semibold))
                                            .foregroundStyle(m.color)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8 * scale)
                    .frame(maxWidth: .infinity)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 3 * scale)
            .padding(.bottom, 8 * scale)
        }
    }
}

// MARK: - Route polyline canvas overlay

/// Draws the route using pre-mapped snapshot-space points, scaled to the actual canvas size.
private struct RoutePolylineOverlay: View {
    /// Points in renderSize (540×960) coordinate space, from MKMapSnapshotter.Snapshot.point(for:).
    let snapshotPoints: [CGPoint]
    let progress: CGFloat

    var body: some View {
        Canvas { ctx, size in
            guard snapshotPoints.count > 1, progress > 0 else { return }

            // Scale snapshot-space points to current canvas size
            let sx = size.width  / RouteVideoExportService.renderSize.width
            let sy = size.height / RouteVideoExportService.renderSize.height
            let pts = snapshotPoints.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }

            let endIdx = max(1, Int(CGFloat(pts.count - 1) * min(progress, 1.0)))
            let slice = Array(pts[0...endIdx])

            var path = Path()
            path.move(to: slice[0])
            for i in 1..<slice.count { path.addLine(to: slice[i]) }

            ctx.stroke(path, with: .color(Theme.violet.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(Theme.violet),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            let tip = slice.last!
            var glow = Path()
            glow.addEllipse(in: CGRect(x: tip.x - 9, y: tip.y - 9, width: 18, height: 18))
            ctx.fill(glow, with: .color(Theme.violet.opacity(0.38)))
            var dot = Path()
            dot.addEllipse(in: CGRect(x: tip.x - 5, y: tip.y - 5, width: 10, height: 10))
            ctx.fill(dot, with: .color(.white))
        }
    }
}

// MARK: - RouteVideoExportService

struct RouteVideoExportService {

    static let fps: Int32  = 30
    static let frameCount  = 600          // 20 s × 30 fps
    static let renderSize  = CGSize(width: 540, height: 960)

    // MARK: Map snapshot + coordinate mapping

    /// Returns the map image and route points pre-mapped into renderSize coordinate space
    /// using MKMapSnapshotter.Snapshot.point(for:) for pixel-accurate alignment.
    static func mapSnapshot(
        coordinates: [CLLocationCoordinate2D]
    ) async throws -> (image: UIImage, points: [CGPoint]) {
        guard coordinates.count > 1 else { return (darkPlaceholder(), []) }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.005)
        )
        let opts        = MKMapSnapshotter.Options()
        opts.region     = MKCoordinateRegion(center: center, span: span)
        opts.size       = renderSize
        opts.scale      = 1
        opts.mapType    = .mutedStandard
        opts.showsBuildings = false

        let snap = try await MKMapSnapshotter(options: opts).start()

        // Use snapshot.point(for:) for map-projection-accurate positions
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

    // MARK: Export (main actor — ImageRenderer requires it)

    @MainActor
    static func export(
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
        weather: WeatherSnapshot? = nil,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_route_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let inputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_500_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: inputSettings)
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(renderSize.width),
                kCVPixelBufferHeightKey as String: Int(renderSize.height)
            ]
        )
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frameCount {
            let progress = CGFloat(frame) / CGFloat(frameCount - 1)

            let frameView = RouteVideoFrameView(
                snapshot: snapshot,
                snapshotPoints: snapshotPoints,
                routeProgress: progress,
                insightTitle: insightTitle,
                metrics: metrics,
                raceName: raceName,
                miniMeVariant: miniMeVariant,
                customMiniMeImage: customMiniMeImage,
                distanceKm: distanceKm,
                duration: duration,
                date: date,
                weather: weather
            )
            .frame(width: renderSize.width, height: renderSize.height)

            let renderer = ImageRenderer(content: frameView)
            renderer.scale = 1
            guard let cgImage = renderer.cgImage,
                  let buffer = makePixelBuffer(from: cgImage) else { continue }

            let pts = CMTime(value: CMTimeValue(frame), timescale: fps)
            while !writerInput.isReadyForMoreMediaData { await Task.yield() }
            adaptor.append(buffer, withPresentationTime: pts)
            progressHandler(Double(frame + 1) / Double(frameCount))
            await Task.yield()
        }

        writerInput.markAsFinished()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }

        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "RouteVideoExport", code: -1)
        }
        return outputURL
    }

    // MARK: CGImage → CVPixelBuffer

    private static func makePixelBuffer(from cgImage: CGImage) -> CVPixelBuffer? {
        let w = cgImage.width, h = cgImage.height
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                  kCVPixelFormatType_32BGRA, attrs, &pb) == kCVReturnSuccess,
              let buf = pb else { return nil }
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buf),
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buf
    }
}
