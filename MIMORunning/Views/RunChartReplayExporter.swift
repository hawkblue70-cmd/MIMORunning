import AVFoundation
import SwiftUI

// MARK: - RunChartReplayExporter
//
// Exports the chart playback animation to a 1080×1350 (4:5) H.264 mp4.
// Rendering pipeline:
//   • Static background (black) + RunChartShareCard with playProgress
//   • ImageRenderer per frame at 3.6× scale → CGImage → 32BGRA CVPixelBuffer
//   • AVAssetWriter appends frames immediately — no frame accumulation.
//   • Task cancellation → cancelWriting + temp-file cleanup.

@MainActor
enum RunChartReplayExporter {

    // MARK: - Constants

    private static let videoW     = 1080
    private static let videoH     = 1350
    private static let videoFPS   = 30
    private static let bitrate    = 8_000_000
    private static let holdSecs   = 1.2

    // Physical pt dimensions at 3.6× scale (1080 ÷ 300 = 3.6)
    private static let cardW: CGFloat = 300
    private static let cardH: CGFloat = 375   // 1350 ÷ 3.6

    // MARK: - Public API

    /// Encodes the chart animation to a temporary mp4 and returns the file URL.
    /// `onProgress` is called on the main actor with a 0–1 fraction.
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
        duration: TimeInterval = 10,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_chart_\(UUID().uuidString).mp4")

        // --- AVAssetWriter ---
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

        let scale: CGFloat    = CGFloat(videoW) / cardW   // 3.6
        let animFrames        = Int(duration * Double(videoFPS))        // e.g. 300
        let holdFrames        = Int(holdSecs * Double(videoFPS))        // 36
        let totalFrames       = animFrames + holdFrames                 // 336

        do {
            for frameIdx in 0..<totalFrames {
                try Task.checkCancellation()

                // 0→1 over animFrames, then hold at 1.0
                let t: Double = frameIdx < animFrames
                    ? Double(frameIdx) / Double(max(1, animFrames - 1))
                    : 1.0

                // Build and render frame
                let frame = frameView(
                    data: data, enabledLayers: enabledLayers,
                    distanceText: distanceText, durationText: durationText,
                    weatherText: weatherText, weatherIcon: weatherIcon,
                    dateText: dateText, weekdayText: weekdayText,
                    startTimeText: startTimeText, shoeText: shoeText,
                    playProgress: t
                )
                let renderer = ImageRenderer(content: frame)
                renderer.scale = scale
                renderer.proposedSize = ProposedViewSize(width: cardW, height: cardH)

                guard let cgImg = renderer.cgImage,
                      let pb    = pixelBuffer(from: cgImg)
                else { continue }

                // Wait for encoder to be ready
                while !videoIn.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }
                let pts = CMTime(value: CMTimeValue(frameIdx), timescale: CMTimeScale(videoFPS))
                adaptor.append(pb, withPresentationTime: pts)

                onProgress(Double(frameIdx + 1) / Double(totalFrames))
                await Task.yield()   // keep UI responsive (progress bar updates)
            }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        videoIn.markAsFinished()
        await withCheckedContinuation { cont in
            writer.finishWriting { cont.resume() }
        }

        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: tempURL)
            throw writer.error ?? NSError(
                domain: "RunChartReplayExporter", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Video encoding failed"])
        }
        return tempURL
    }

    // MARK: - Frame view

    private static func frameView(
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
        playProgress: Double
    ) -> some View {
        ZStack(alignment: .top) {
            Color.black
            RunChartShareCard(
                data: data,
                enabledLayers: enabledLayers,
                distanceText: distanceText,
                durationText: durationText,
                weatherText: weatherText,
                weatherIcon: weatherIcon,
                dateText: dateText,
                weekdayText: weekdayText,
                startTimeText: startTimeText,
                shoeText: shoeText,
                playProgress: playProgress
            )
        }
        .frame(width: cardW, height: cardH)
        .preferredColorScheme(.dark)
    }

    // MARK: - CGImage → CVPixelBuffer (32BGRA)

    private static func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        let w = image.width, h = image.height
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil, w, h,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let pixelBuffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let ctx = CGContext(
            data:             CVPixelBufferGetBaseAddress(pixelBuffer),
            width:            w,
            height:           h,
            bitsPerComponent: 8,
            bytesPerRow:      CVPixelBufferGetBytesPerRow(pixelBuffer),
            space:            CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:       CGBitmapInfo.byteOrder32Little.rawValue |
                              CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixelBuffer
    }
}
