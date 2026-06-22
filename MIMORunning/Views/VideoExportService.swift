import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - VideoPickerResult

struct VideoPickerResult: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { v in
            SentTransferredFile(v.url)
        } importing: { recv in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("mimo_import_\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: recv.file, to: dest)
            return VideoPickerResult(url: dest)
        }
    }
}

// MARK: - SharableVideoFile

struct SharableVideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { f in
            SentTransferredFile(f.url)
        } importing: { recv in
            SharableVideoFile(url: recv.file)
        }
    }
}

// MARK: - VideoExportService

struct VideoExportService {

    enum ExportError: Error {
        case noVideoTrack, compositionFailed, sessionFailed, exportFailed, cancelled
    }

    static let targetSize = CGSize(width: 1080, height: 1920)
    static let trimDuration: Double = 30.0

    // MARK: First frame

    static func firstFrame(of url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 540, height: 960)
        return await withCheckedContinuation { cont in
            generator.generateCGImageAsynchronously(for: .zero) { img, _, _ in
                cont.resume(returning: img.map { UIImage(cgImage: $0) })
            }
        }
    }

    // MARK: Export

    static func exportVideo(sourceURL: URL, overlay: UIImage) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw ExportError.noVideoTrack }

        let duration    = try await asset.load(.duration)
        let trimEnd     = min(CMTimeGetSeconds(duration), trimDuration)
        let timeRange   = CMTimeRange(start: .zero,
                                      duration: CMTimeMakeWithSeconds(trimEnd, preferredTimescale: 600))

        let naturalSize        = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)

        // Display size after rotation
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displayWidth    = abs(transformedRect.width)
        let displayHeight   = abs(transformedRect.height)

        // Scale-to-fill 1080×1920
        let scaleX       = targetSize.width  / displayWidth
        let scaleY       = targetSize.height / displayHeight
        let scale        = max(scaleX, scaleY)
        let scaledWidth  = displayWidth  * scale
        let scaledHeight = displayHeight * scale
        let txOffset     = (targetSize.width  - scaledWidth)  / 2
        let tyOffset     = (targetSize.height - scaledHeight) / 2

        // Composition
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.compositionFailed }
        try compVideo.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
           let audioTrack  = audioTracks.first,
           let compAudio   = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compAudio.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        // Layer instruction: rotate + scale-to-fill
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        var t  = preferredTransform
        t.tx  -= transformedRect.origin.x
        t.ty  -= transformedRect.origin.y
        t      = t.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        t      = t.concatenating(CGAffineTransform(translationX: txOffset, y: tyOffset))
        layerInstruction.setTransform(t, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange        = timeRange
        instruction.layerInstructions = [layerInstruction]

        let videoComposition              = AVMutableVideoComposition()
        videoComposition.renderSize       = targetSize
        videoComposition.frameDuration    = CMTimeMake(value: 1, timescale: 30)
        videoComposition.instructions     = [instruction]

        // CALayer overlay — pre-rendered by ImageRenderer in ShareCardScreen
        let parentLayer   = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: targetSize)
        parentLayer.isGeometryFlipped = true          // UIKit coordinate system

        let videoLayer    = CALayer()
        videoLayer.frame  = CGRect(origin: .zero, size: targetSize)

        let overlayLayer           = CALayer()
        overlayLayer.frame         = CGRect(origin: .zero, size: targetSize)
        overlayLayer.contents      = overlay.cgImage

        // Slight brightness boost on the video layer (matches CardVisual.videoBrightnessBoost).
        let brightenLayer         = CALayer()
        brightenLayer.frame       = CGRect(origin: .zero, size: targetSize)
        brightenLayer.backgroundColor = UIColor.white.cgColor
        brightenLayer.opacity     = CardVisual.videoBrightenLayerOpacity

        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(brightenLayer)
        parentLayer.addSublayer(overlayLayer)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        // Export
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_video_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPreset1920x1080)
        else { throw ExportError.sessionFailed }

        session.outputURL      = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.timeRange      = timeRange

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed: cont.resume()
                case .failed:    cont.resume(throwing: session.error ?? ExportError.exportFailed)
                case .cancelled: cont.resume(throwing: ExportError.cancelled)
                default:         cont.resume(throwing: ExportError.exportFailed)
                }
            }
        }

        return outputURL
    }

}
