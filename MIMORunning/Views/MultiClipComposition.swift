import AVFoundation
import Photos
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
    var url:          URL
    var trimStart:    Double          // seconds from clip start (default: 0)
    var trimEnd:      Double          // seconds from clip start (default: fullDuration)
    var fullDuration: Double
    var thumbnail:    UIImage?        // first frame, loaded async after selection
    var lines:        [String]        // text slots owned by this clip

    // Persistence refs — populated on pick, restored on load
    var assetIdentifier: String? = nil  // PHAsset.localIdentifier (video clips; primary stable ref)
    var clipVideoRef:    String? = nil  // ClipVideoStore ref — stable copy when assetIdentifier unavailable
    var storedPhotoRef:  String? = nil  // OneLinerPhotoStore ref (photo-slide clips)
    var thumbRef:        String? = nil  // ClipThumbStore 200 px mini-thumbnail
    var resolvedAsset:   AVAsset? = nil // PHImageManager 해석 결과 (재진입 시 주입)

    // Per-clip style — controls bound to the selected clip in MultiClipEditorView
    var fontChoice: OneLinerFont      = .pen
    var textColor:  OneLinerTextColor = .white
    var position:   CardPosition      = .bottom
    var sizeLevel:  TextSizeLevel     = .medium
    var appearanceMode:   AppearanceMode   = .typing
    var decorEffect:      DecorEffect      = .none
    var hasBorder: Bool = true {        // 8방향 오프셋 테두리 (plateOn과 상호 배타)
        didSet { if hasBorder { plateOn = false } }
    }
    var plateOn: Bool = false {         // 음영판 (hasBorder와 상호 배타)
        didSet { if plateOn { hasBorder = false } }
    }
    var flyDirection:     FlyInDirection   = .trailing
    var plateColorPreset: PlateColorPreset = .blackWhite

    init(url: URL, fullDuration: Double, thumbnail: UIImage? = nil) {
        self.url          = url
        self.fullDuration = fullDuration
        self.trimStart    = 0
        self.trimEnd      = fullDuration
        self.thumbnail    = thumbnail
        let n             = max(1, min(20, Int(fullDuration / 3.0)))
        self.lines        = Array(repeating: "", count: n)
    }

    var trimmedDuration: Double { max(0.1, trimEnd - trimStart) }
    var isTrimmed: Bool { trimStart > 0.05 || trimEnd < fullDuration - 0.05 }
    /// Number of text slots based on trimmed duration (1 slot per 3 s).
    var linesCount: Int { max(1, min(20, Int(trimmedDuration / 3.0))) }
    var hasText: Bool { lines.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}

// MARK: - PlateLayout
//
// 음영판(plate) CALayer 배치 공통 상수.
// PhotoSlideComposition과 VideoExportService에서 동일 인스턴스를 사용.
//
// 미리보기(SwiftUI) 기준: VStack spacing=3, .padding(.vertical, 2), cornerRadius 5.
// lineSpacing = 2*padV + gap = 7 pt (vScale=1) → NSParagraphStyle.lineSpacing에 사용.
// 이 값을 pStyle.lineSpacing으로 설정하면 boundingRect도 자동으로 올바른 높이를 반환.

struct PlateLayout {
    let padH:        CGFloat   // 좌우 패딩 (= 8 * vScale)
    let padV:        CGFloat   // 상하 패딩 (= 2 * vScale)
    let gap:         CGFloat   // 판 간 세로 간격 (= 3 * vScale)
    let cornerR:     CGFloat   // 코너 반경 (= 5 * vScale)
    let plateH:      CGFloat   // 판 rect 높이 = ceil(lineHeight) + 2*padV
    let lineStep:    CGFloat   // 줄 간 Y 거리 = lineHeight + 2*padV + gap
    let lineSpacing: CGFloat   // NSParagraphStyle.lineSpacing = 2*padV + gap

    init(uiFont: UIFont, vScale: CGFloat) {
        let padV_  = 2 * vScale
        let gap_   = 3 * vScale
        padH       = 8 * vScale
        padV       = padV_
        gap        = gap_
        cornerR    = 5 * vScale
        lineSpacing = 2 * padV_ + gap_
        plateH     = ceil(uiFont.lineHeight) + 2 * padV_
        lineStep   = uiFont.lineHeight + lineSpacing
    }
}

// MARK: - OneLinerTitleStyle
//
// Style for the full-video title overlay (영상·슬라이드 only).
// Stored as raw-value fields in SavedRecipeSet.

struct OneLinerTitleStyle: Equatable {
    var position:   CardPosition       = .top
    var sizeLevel:  TextSizeLevel      = .medium
    var fontChoice: OneLinerFont       = .gothic
    var textColor:  OneLinerTextColor  = .white
    var outline:    Bool               = false
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

            if !muteAudio,
               let ca = compAudio,
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

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw MCError.compositionFailed }

        let compAudio: AVMutableCompositionTrack? = muteAudio ? nil :
            composition.addMutableTrack(withMediaType: .audio,
                                        preferredTrackID: kCMPersistentTrackID_Invalid)

        let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        var insertAt      = CMTime.zero
        var clips:        [ClipDescriptor] = []
        var clipIdx       = 0
        var audioInserted = 0

        for recipe in recipes {
            let asset: AVAsset = recipe.resolvedAsset ?? AVURLAsset(url: recipe.url)
            let vts   = try await asset.loadTracks(withMediaType: .video)
            guard let vt = vts.first else { clipIdx += 1; continue }

            let natSz  = try await vt.load(.naturalSize)
            let prefTf = try await vt.load(.preferredTransform)

            // Trimmed range within the source clip
            let clipRange = CMTimeRange(
                start:    CMTimeMakeWithSeconds(recipe.trimStart, preferredTimescale: 600),
                duration: CMTimeMakeWithSeconds(recipe.trimmedDuration, preferredTimescale: 600))

            try compVideo.insertTimeRange(clipRange, of: vt, at: insertAt)

            // 음소거=true이면 compAudio=nil → 조건 자체가 false → 전 클립 오디오 삽입 없음
            if !muteAudio,
               let ca = compAudio,
               let ats = try? await asset.loadTracks(withMediaType: .audio),
               let at  = ats.first {
                try? ca.insertTimeRange(clipRange, of: at, at: insertAt)
                audioInserted += 1
            }

            layerInstr.setTransform(
                scaleFillTransform(naturalSize: natSz, preferredTransform: prefTf),
                at: insertAt)

            clips.append(ClipDescriptor(url: recipe.url, duration: recipe.trimmedDuration,
                                        trimStart: recipe.trimStart, trimEnd: recipe.trimEnd))
            insertAt = CMTimeAdd(insertAt, clipRange.duration)
            clipIdx += 1
        }
        guard !clips.isEmpty else { throw MCError.noVideoTrack }

        print("[MultiClip] export 음소거=\(muteAudio) 삽입오디오=\(audioInserted)개")

        let totalDuration = insertAt

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

        return (outURL, clips)
    }

    // MARK: - PHAsset 해석

    /// PHAsset.localIdentifier → AVAsset 해석.
    /// AVComposition(슬로모션·편집 영상) 포함 모든 타입 수용.
    /// fileExists 체크 없음 — PHImageManager가 반환하는 모든 AVAsset 타입 사용.
    static func resolveAVAsset(assetID: String) async throws -> AVAsset {
        enum E: Error { case notFound, failed }
        guard let phAsset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetID], options: nil).firstObject
        else { throw E.notFound }

        return try await withCheckedThrowingContinuation { cont in
            let opts = PHVideoRequestOptions()
            opts.deliveryMode           = .highQualityFormat
            opts.version                = .current
            opts.isNetworkAccessAllowed = true
            opts.progressHandler = { _, _, _, _ in }
            var resumed = false
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: opts) { avAsset, _, info in
                guard !resumed else { return }
                resumed = true
                if let err = info?[PHImageErrorKey] as? Error { cont.resume(throwing: err); return }
                if let asset = avAsset { cont.resume(returning: asset) }
                else                   { cont.resume(throwing: E.failed) }
            }
        }
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
