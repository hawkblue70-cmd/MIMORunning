import AVFoundation
import UIKit

// MARK: - ClipDescriptor

struct ClipDescriptor {
    let url: URL
    let duration: Double    // trimmed duration (seconds)
    let trimStart: Double
    let trimEnd: Double
}

// MARK: - ClipRecipe
//
// User-editable descriptor for one clip.
// The source file is never mutated; trimStart/trimEnd are applied as CMTimeRange
// during composition. Trim info is in-memory only (not persisted to DB).

struct ClipRecipe: Identifiable {
    var id:           UUID    = UUID()
    let url:          URL
    var trimStart:    Double          // seconds from clip start (default: 0)
    var trimEnd:      Double          // seconds from clip start (default: fullDuration)
    let fullDuration: Double
    var thumbnail:    UIImage?        // first frame, loaded async after selection

    init(url: URL, fullDuration: Double, thumbnail: UIImage? = nil) {
        self.url          = url
        self.fullDuration = fullDuration
        self.trimStart    = 0
        self.trimEnd      = fullDuration
        self.thumbnail    = thumbnail
    }

    var trimmedDuration: Double { max(0.1, trimEnd - trimStart) }
    var isTrimmed: Bool { trimStart > 0.05 || trimEnd < fullDuration - 0.05 }
}

// MARK: - MultiClipComposition
//
// Shared multi-clip video stitching engine.
// Joins N video clips in selection order into a normalised 1080×1920 MOV.
// Each clip's preferredTransform is applied so portrait/landscape all fill the frame.
// No re-encoding at composition stage — the single HEVC pass happens in composeAndExport.
//
// Usage:
//   let (url, clips) = try await MultiClipComposition.composeAndExport(urls: urls)
//   defer { try? FileManager.default.removeItem(at: url) }
//   // then feed `url` to VideoExportService.exportOneLinerTypingVideo(sourceURL: url, ...)

enum MultiClipComposition {

    static let targetSize = CGSize(width: 1080, height: 1920)
    /// Hard ceiling: 60 s of combined clip duration.
    static let maxSeconds: Double = 60.0

    enum MCError: Error {
        case noClips, noVideoTrack, compositionFailed, exportFailed
    }

    // MARK: - composeAndExport
    //
    // Stitches clips, applies per-clip rotation/scale-fill, and exports to a temp MOV.
    // Caller must delete the returned URL after use.
    //
    // - Parameter muteAudio: when true, no audio track is written.
    // - Returns: (tempURL, descriptors of each clip)

    static func composeAndExport(urls: [URL], muteAudio: Bool = false) async throws -> (url: URL, clips: [ClipDescriptor]) {
        guard !urls.isEmpty else { throw MCError.noClips }
        let tStart = Date()

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw MCError.compositionFailed }

        let compAudio: AVMutableCompositionTrack? = muteAudio ? nil :
            composition.addMutableTrack(withMediaType: .audio,
                                        preferredTrackID: kCMPersistentTrackID_Invalid)

        // Single layer instruction covers the full timeline; per-clip transforms set as keyframes.
        let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)

        var insertAt = CMTime.zero
        var clips:   [ClipDescriptor] = []

        for url in urls {
            let asset   = AVURLAsset(url: url)
            let vts     = try await asset.loadTracks(withMediaType: .video)
            guard let vt = vts.first else { continue }

            let dur    = try await asset.load(.duration)
            let natSz  = try await vt.load(.naturalSize)
            let prefTf = try await vt.load(.preferredTransform)
            let range  = CMTimeRange(start: .zero, duration: dur)

            try compVideo.insertTimeRange(range, of: vt, at: insertAt)

            if let ca = compAudio,
               let ats = try? await asset.loadTracks(withMediaType: .audio),
               let at  = ats.first {
                try? ca.insertTimeRange(range, of: at, at: insertAt)
            }

            // Set the normalised transform at the clip's start position.
            layerInstr.setTransform(
                scaleFillTransform(naturalSize: natSz, preferredTransform: prefTf),
                at: insertAt)

            let clipSecs = CMTimeGetSeconds(dur)
            clips.append(ClipDescriptor(url: url, duration: clipSecs, trimStart: 0, trimEnd: clipSecs))
            insertAt = CMTimeAdd(insertAt, dur)
        }
        guard !clips.isEmpty else { throw MCError.noVideoTrack }

        let totalDuration = insertAt
        let totalSeconds  = CMTimeGetSeconds(totalDuration)

        // Build video composition with one instruction spanning the full timeline.
        let vcInstr = AVMutableVideoCompositionInstruction()
        vcInstr.timeRange         = CMTimeRange(start: .zero, duration: totalDuration)
        vcInstr.layerInstructions = [layerInstr]

        let videoComp           = AVMutableVideoComposition()
        videoComp.renderSize    = targetSize
        videoComp.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComp.instructions  = [vcInstr]

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_multiclip_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outURL)

        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHEVCHighestQuality)
        else { throw MCError.exportFailed }

        session.outputURL        = outURL
        session.outputFileType   = .mov
        session.videoComposition = videoComp
        session.timeRange        = CMTimeRange(start: .zero, duration: totalDuration)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed: cont.resume()
                case .failed:    cont.resume(throwing: session.error ?? MCError.exportFailed)
                default:         cont.resume(throwing: MCError.exportFailed)
                }
            }
        }

        let elapsed = Date().timeIntervalSince(tStart)
        print("""
[MultiClip] 클립수=\(clips.count) \
각길이=\(clips.map { "\(Int($0.duration))초" }.joined(separator: "+")) \
합산=\(Int(totalSeconds))초 합성시간=\(String(format: "%.2f", elapsed))s
""")

        return (outURL, clips)
    }

    // MARK: - Helpers

    /// Total duration of clips at given URLs (loads in parallel).
    static func totalDuration(urls: [URL]) async -> Double {
        await withTaskGroup(of: Double.self) { group in
            for url in urls {
                group.addTask {
                    (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
                }
            }
            var sum = 0.0
            for await d in group { sum += d }
            return sum
        }
    }

    /// Sync total of trimmed durations — no async needed since durations are already in the recipes.
    static func totalDuration(recipes: [ClipRecipe]) -> Double {
        recipes.reduce(0) { $0 + $1.trimmedDuration }
    }

    // MARK: - composeAndExport (recipes — supports trim)
    //
    // Like the URL-based version, but uses each recipe's trimStart/trimEnd
    // to insert only the trimmed CMTimeRange from each clip.
    // Log format: [MultiClip] 클립수=N 각트림=[0-5s, 2-10s, ...] 합산=Xs 합성시간=X.XXs

    static func composeAndExport(recipes: [ClipRecipe], muteAudio: Bool = false) async throws -> (url: URL, clips: [ClipDescriptor]) {
        guard !recipes.isEmpty else { throw MCError.noClips }
        let tStart = Date()

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw MCError.compositionFailed }

        let compAudio: AVMutableCompositionTrack? = muteAudio ? nil :
            composition.addMutableTrack(withMediaType: .audio,
                                        preferredTrackID: kCMPersistentTrackID_Invalid)

        let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        var insertAt   = CMTime.zero
        var clips:     [ClipDescriptor] = []

        for recipe in recipes {
            let asset = AVURLAsset(url: recipe.url)
            let vts   = try await asset.loadTracks(withMediaType: .video)
            guard let vt = vts.first else { continue }

            let natSz  = try await vt.load(.naturalSize)
            let prefTf = try await vt.load(.preferredTransform)

            // Trimmed range within the source clip
            let clipRange = CMTimeRange(
                start:    CMTimeMakeWithSeconds(recipe.trimStart, preferredTimescale: 600),
                duration: CMTimeMakeWithSeconds(recipe.trimmedDuration, preferredTimescale: 600))

            try compVideo.insertTimeRange(clipRange, of: vt, at: insertAt)

            if let ca = compAudio,
               let ats = try? await asset.loadTracks(withMediaType: .audio),
               let at  = ats.first {
                try? ca.insertTimeRange(clipRange, of: at, at: insertAt)
            }

            layerInstr.setTransform(
                scaleFillTransform(naturalSize: natSz, preferredTransform: prefTf),
                at: insertAt)

            clips.append(ClipDescriptor(url: recipe.url, duration: recipe.trimmedDuration,
                                        trimStart: recipe.trimStart, trimEnd: recipe.trimEnd))
            insertAt = CMTimeAdd(insertAt, clipRange.duration)
        }
        guard !clips.isEmpty else { throw MCError.noVideoTrack }

        let totalDuration = insertAt
        let totalSeconds  = CMTimeGetSeconds(totalDuration)

        let vcInstr = AVMutableVideoCompositionInstruction()
        vcInstr.timeRange         = CMTimeRange(start: .zero, duration: totalDuration)
        vcInstr.layerInstructions = [layerInstr]

        let videoComp           = AVMutableVideoComposition()
        videoComp.renderSize    = targetSize
        videoComp.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComp.instructions  = [vcInstr]

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_multiclip_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outURL)

        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHEVCHighestQuality)
        else { throw MCError.exportFailed }

        session.outputURL        = outURL
        session.outputFileType   = .mov
        session.videoComposition = videoComp
        session.timeRange        = CMTimeRange(start: .zero, duration: totalDuration)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed: cont.resume()
                case .failed:    cont.resume(throwing: session.error ?? MCError.exportFailed)
                default:         cont.resume(throwing: MCError.exportFailed)
                }
            }
        }

        let elapsed    = Date().timeIntervalSince(tStart)
        let trimLog    = clips.map { "\(Int($0.trimStart))-\(Int($0.trimEnd))s" }.joined(separator: ", ")
        print("[MultiClip] 클립수=\(clips.count) 각트림=[\(trimLog)] 합산=\(Int(totalSeconds))초 합성시간=\(String(format: "%.2f", elapsed))s")

        return (outURL, clips)
    }

    // MARK: - Private

    private static func scaleFillTransform(naturalSize: CGSize,
                                            preferredTransform: CGAffineTransform) -> CGAffineTransform {
        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let dw    = abs(displayRect.width)
        let dh    = abs(displayRect.height)
        let scale = max(targetSize.width / dw, targetSize.height / dh)
        let txOff = (targetSize.width  - dw * scale) / 2
        let tyOff = (targetSize.height - dh * scale) / 2

        var tf = preferredTransform
        tf.tx -= displayRect.origin.x
        tf.ty -= displayRect.origin.y
        tf = tf.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        tf = tf.concatenating(CGAffineTransform(translationX: txOff, y: tyOff))
        return tf
    }
}
