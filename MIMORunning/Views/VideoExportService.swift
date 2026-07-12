import AVFoundation
import Photos
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

    // MARK: - SDR filmic pipeline (preview = export)
    //
    // HDR 소스를 BT.709 SDR로 전처리할 때 사용하는 필믹 파라미터.
    // export는 preprocessHDRToSDR() 필믹 파이프라인 사용.
    // 프리뷰는 재생 안정성·성능을 위해 재인코딩을 생략하고 709 태깅 톤매핑만 적용(색은 근사).
    //
    // 눈 튜닝 순서:
    //   1. sdrMidtoneLift 로 미드톤 전체 밝기 조절 (올리면 밝아짐)
    //   2. sdrHighlightCeiling 로 하늘 클리핑 조절 (낮출수록 하이라이트 더 압축)
    //   3. sdrClarity 로 펀치감 조절 (올리면 또렷해지나 과하면 거칠어짐)
    //   4. sdrSaturation 은 마지막, 1.02 이상 금지

    /// 미드톤 리프트. 0.50 그레이를 얼마나 올리나(+%). 범위 0.00–0.10, 기본 0.05.
    static var sdrMidtoneLift: Float = 0.07

    /// 하이라이트 롤오프 상한. 1.0 화이트가 이 값으로 부드럽게 압축됨. 범위 0.93–1.00, 기본 0.96.
    static var sdrHighlightCeiling: Float = 0.98

    /// 로컬 콘트라스트(클래리티). CIUnsharpMask intensity, 반경 25px(광역 선명도).
    /// 0.0 = off, 범위 0.05–0.20, 기본 0.12.
    static var sdrClarity: Float = 0.12

    /// 채도 배수. 1.00 = 중립, 1.02 이상 과보정 금지. 기본 1.01.
    static var sdrSaturation: Float = 1.01

    /// Returns true if the track has BT.2020 (HDR) color primaries.
    private static func isHDRSource(track: AVAssetTrack) async -> Bool {
        let descs = (try? await track.load(.formatDescriptions)) ?? []
        for desc in descs {
            guard let p = CMFormatDescriptionGetExtension(
                desc, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries
            ) as? String else { continue }
            if p == (kCVImageBufferColorPrimaries_ITU_R_2020 as String) { return true }
        }
        return false
    }

    /// Stamps BT.709 SDR output properties on `vc`.
    /// For preprocessed sources this is a label-only pass; AVFoundation keeps the SDR pixels as-is.
    /// For raw HDR sources (AVComposition / EV=0 fast path) AVFoundation applies BT.709 tone-mapping.
    private static func applySDROutputProps(
        _ vc: AVMutableVideoComposition,
        track: AVAssetTrack
    ) async {
        vc.colorPrimaries        = AVVideoColorPrimaries_ITU_R_709_2
        vc.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        vc.colorYCbCrMatrix      = AVVideoYCbCrMatrix_ITU_R_709_2
        let hdr = await isHDRSource(track: track)
        print("[SDR] \(hdr ? "HDR→BT.709 톤매핑(롤오프)" : "SDR/필믹→BT.709 레이블")")
    }

    /// Pre-processes an HDR video file: filmic tone curve + local contrast + saturation → BT.709 SDR.
    ///
    /// - SDR source → original URL returned immediately (no re-encode).
    /// - HDR source → temp file with filmic pipeline; caller shadows `sourceURL` with the result.
    ///
    /// CIFilter chain (all ops share the same captured parameters → export = preview):
    ///   1. CIToneCurve  — S-curve: shadow deepen · midtone lift · highlight rolloff
    ///   2. CIUnsharpMask (radius 25px) — broad-radius local contrast ("clarity")
    ///   3. CIColorControls — saturation trim (default 1.01, nearly neutral)
    static func preprocessHDRToSDR(url: URL) async throws -> URL {
        let asset  = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first, await isHDRSource(track: track) else { return url }

        // Capture params to avoid capturing `self` (struct static) in the closure
        let lift = sdrMidtoneLift
        let ceil = sdrHighlightCeiling
        let clarity    = sdrClarity
        let saturation = sdrSaturation

        let comp = AVMutableVideoComposition(asset: asset) { request in
            var img: CIImage = request.sourceImage

            // 1. Filmic S-curve tone map
            //    • shadows:   0.25 → (0.25 − lift×0.4) — 미드로부터 아래를 살짝 눌러 콘트라스트 깊이 추가
            //    • midtones:  0.50 → (0.50 + lift)      — 미드톤 리프트 (HDR 밝기 보상)
            //    • upper-mid: 0.75 → (0.75 + lift×0.6) — 롤오프 시작
            //    • highlights: 1.00 → ceil              — 하이라이트 클리핑 방지
            let p0 = CIVector(x: 0.00, y: 0.00)
            let p1 = CIVector(x: 0.25, y: CGFloat(max(0.00, 0.25 - lift * 0.4)))
            let p2 = CIVector(x: 0.50, y: CGFloat(min(1.00, 0.50 + lift)))
            let p3 = CIVector(x: 0.75, y: CGFloat(min(1.00, 0.75 + lift * 0.6)))
            let p4 = CIVector(x: 1.00, y: CGFloat(min(1.00, ceil)))
            img = img.applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": p0, "inputPoint1": p1,
                "inputPoint2": p2, "inputPoint3": p3, "inputPoint4": p4
            ])

            // 2. Local contrast (clarity): broad-radius unsharp mask → HDR 펀치감 근사
            if clarity > 0 {
                img = img.applyingFilter("CIUnsharpMask", parameters: [
                    kCIInputRadiusKey:    25.0,
                    kCIInputIntensityKey: CGFloat(clarity)
                ])
            }

            // 3. Saturation (keep near-neutral; 1.01 is barely perceptible)
            if saturation != 1.0 {
                img = img.applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: CGFloat(saturation)
                ])
            }

            request.finish(with: img, context: nil)
        }
        comp.colorPrimaries        = AVVideoColorPrimaries_ITU_R_709_2
        comp.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        comp.colorYCbCrMatrix      = AVVideoYCbCrMatrix_ITU_R_709_2

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_sdr_pre_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality)
        else { throw ExportError.sessionFailed }
        session.outputURL        = outputURL
        session.outputFileType   = .mov
        session.videoComposition = comp

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
        print("[SDR] HDR→필믹 완료: lift=\(lift) ceil=\(ceil) clarity=\(clarity) sat=\(saturation)")
        return outputURL
    }

    // MARK: Export detection

    /// Returns true if this video was previously exported by MIMORunning's OneLiner export.
    /// Detection via embedded AVMetadata description "MIMO_ONELINER_V1".
    /// If Photos strips metadata on library save, returns false (silent miss is acceptable).
    static func isMIMOOneLinerExport(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        let meta  = (try? await asset.load(.commonMetadata)) ?? []
        for item in meta {
            guard item.identifier == .commonIdentifierDescription else { continue }
            if (try? await item.load(.stringValue)) == "MIMO_ONELINER_V1" { return true }
        }
        return false
    }

    // MARK: Typing speed

    /// Computes per-character display durations fitted to `pageTime`.
    /// 70 % of pageTime is used for typing; 30 % remains as a reading buffer.
    /// Individual character delays are clamped to [0.05, 0.8] s.
    static func typingDurations(chars: [Character], pageTime: Double) -> [Double] {
        let typable = max(1, chars.filter { !$0.isWhitespace && !$0.isNewline }.count)
        let base = max(0.05, min(0.8, (pageTime * 0.7) / Double(typable)))
        return chars.map { ch in
            if ch.isNewline    { return min(base * 0.5, 0.30) }
            if ch.isWhitespace { return min(base * 0.4, 0.10) }
            return base
        }
    }

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

    /// PHAsset(localIdentifier) → 포스터 프레임 (빠른 시트 배경 표시용, 트림 미적용)
    static func quickFrame(assetID: String) async -> UIImage? {
        guard let phAsset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetID], options: nil).firstObject
        else { return nil }
        return await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            var resumed = false
            PHImageManager.default().requestImage(
                for: phAsset, targetSize: CGSize(width: 540, height: 960),
                contentMode: .aspectFill, options: opts
            ) { img, info in
                // isDegraded=true는 저화질 임시 결과 → skip, 고화질만 resume
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded, !resumed else { return }
                resumed = true
                cont.resume(returning: img)
            }
        }
    }

    /// AVAsset의 특정 시점 UIImage 프레임 (시트 미리보기 트림 시작점용)
    static func frame(of asset: AVAsset, at time: Double) async -> UIImage? {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 540, height: 960)
        let t = CMTimeMakeWithSeconds(time, preferredTimescale: 600)
        return await withCheckedContinuation { cont in
            gen.generateCGImageAsynchronously(for: t) { img, _, _ in
                cont.resume(returning: img.map { UIImage(cgImage: $0) })
            }
        }
    }

    static func duration(of url: URL) async -> Double {
        (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
    }

    // MARK: Export (static overlay)

    static func exportVideo(sourceURL: URL, overlay: UIImage) async throws -> URL {
        let sourceURL   = try await preprocessHDRToSDR(url: sourceURL)
        let asset       = AVURLAsset(url: sourceURL)

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

        // SDR output: BT.709 — HDR sources tone-mapped with rolloff; preview = export.
        await applySDROutputProps(videoComposition, track: videoTrack)

        // CALayer overlay — pre-rendered by ImageRenderer in ShareCardScreen
        let parentLayer   = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: targetSize)
        parentLayer.isGeometryFlipped = true          // UIKit coordinate system

        let videoLayer    = CALayer()
        videoLayer.frame  = CGRect(origin: .zero, size: targetSize)

        let overlayLayer           = CALayer()
        overlayLayer.frame         = CGRect(origin: .zero, size: targetSize)
        overlayLayer.contents      = overlay.cgImage

        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        // Export
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_video_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHEVCHighestQuality)
        else { throw ExportError.sessionFailed }

        session.outputURL      = outputURL
        session.outputFileType = .mov
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

    // MARK: Export OneLiner typing animation
    //
    // Characters appear one-by-one over the video (타이핑 효과).
    // Each character type reveals the next glyph; cursor blinks during typing,
    // disappears when complete. Wordmark at top-left; optional date at bottom-right.
    //
    // Timing:
    //   • startDelay = 0.8s before first char
    //   • 0.13s per regular char, 0.05s per whitespace/newline
    //   • Auto-correction: if videoDuration < startDelay + totalTyping + 1.0s,
    //     scale all char durations so typing ends 1s before video end
    //   • Cursor: same color as text, 0.25s on/off blink, hidden when complete

    static func exportOneLinerTypingVideo(
        sourceURL: URL,
        text: String,
        fontChoice: OneLinerFont,
        textColor: OneLinerTextColor,
        position: CardPosition,
        activityDate: Date,
        showDate: Bool,
        muteAudio: Bool = false,
        maxDuration: Double? = nil   // nil = trimDuration (30s); pass total seconds for multi-clip
    ) async throws -> URL {

        let sourceURL   = try await preprocessHDRToSDR(url: sourceURL)
        let asset       = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw ExportError.noVideoTrack }

        let assetDuration      = try await asset.load(.duration)
        let naturalSize        = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let audioTracks        = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

        // ── 1. Timing ────────────────────────────────────────────────────────
        let trimEnd   = min(CMTimeGetSeconds(assetDuration), maxDuration ?? trimDuration)
        let timeRange = CMTimeRange(start: .zero,
                                    duration: CMTimeMakeWithSeconds(trimEnd, preferredTimescale: 600))
        let D = trimEnd

        let chars = Array(text)
        let N     = chars.count

        let startDelay: Double = 0.8
        let endMargin:  Double = 1.0
        let typingBudget = max(0.5, D - startDelay - endMargin)
        let durs = VideoExportService.typingDurations(chars: chars, pageTime: typingBudget)

        var charAppearTimes: [Double] = []
        var t = startDelay
        for dur in durs {
            charAppearTimes.append(t)
            t += dur
        }
        let typingEndTime = t

        // ── 2. Composition — scale-to-fill into 9:16 (full-bleed) ───────────
        // OneLiner output is 1080×1920 (9:16). Text is placed in the Instagram safe zone
        // (safeTop=250px, safeBottom=320px). This size is also the re-export fingerprint
        // (see isMIMOOneLinerExport).
        let oneLinerSize = CGSize(width: 1080, height: 1920)

        let displayRect  = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displayW     = abs(displayRect.width)
        let displayH     = abs(displayRect.height)
        let fillScale    = max(oneLinerSize.width / displayW, oneLinerSize.height / displayH)
        let txOff        = (oneLinerSize.width  - displayW * fillScale) / 2
        let tyOff        = (oneLinerSize.height - displayH * fillScale) / 2

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.compositionFailed }
        try compVideo.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        if !muteAudio, let audioTrack = audioTracks.first,
           let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compAudio.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        var tf = preferredTransform
        tf.tx -= displayRect.origin.x
        tf.ty -= displayRect.origin.y
        tf = tf.concatenating(CGAffineTransform(scaleX: fillScale, y: fillScale))
        tf = tf.concatenating(CGAffineTransform(translationX: txOff, y: tyOff))

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        layerInstruction.setTransform(tf, at: .zero)

        let vcInstruction = AVMutableVideoCompositionInstruction()
        vcInstruction.timeRange         = timeRange
        vcInstruction.layerInstructions = [layerInstruction]

        let videoComposition           = AVMutableVideoComposition()
        videoComposition.renderSize    = oneLinerSize
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComposition.instructions  = [vcInstruction]

        // SDR output: BT.709 — HDR sources tone-mapped with rolloff; preview = export.
        await applySDROutputProps(videoComposition, track: videoTrack)

        // ── 3. Layout constants ───────────────────────────────────────────────
        // Text is placed in the unified video safe zone (safeTop=180px, safeBottom=220px).
        // hPad (86.4px) already exceeds the horizontal safe margin (60px), so no separate h-safe needed.
        let W: CGFloat = oneLinerSize.width   // 1080
        let H: CGFloat = oneLinerSize.height  // 1920
        let vScale: CGFloat = W / 300.0       // 3.6

        let safeTop:    CGFloat = CardVisual.videoSafeTop    // 260 px
        let safeBottom: CGFloat = CardVisual.videoSafeBottom // 220 px
        // hPad (86.4px) > CardVisual.videoSafeHoriz (60px) — horiz safe zone satisfied.
        // 값 변경 시 CardVisual.videoSafeHoriz * vScale (= 60 * 3.6 = 216px) 이상 유지.
        let hPad:         CGFloat = 24 * vScale
        let wMarkTopPad:  CGFloat = 12 * vScale
        let wMarkFontPx:  CGFloat = 9  * vScale
        let wMarkZoneH:   CGFloat = wMarkTopPad + ceil(wMarkFontPx * 1.5) + 6 * vScale

        let fontSize:    CGFloat = OneLinerFont.basePt * fontChoice.sizeScale * vScale
        let lineSpacing: CGFloat = fontSize * 0.1
        let uiFont = fontChoice.uiFont(size: fontSize)
        let lineHeight:  CGFloat = uiFont.lineHeight + lineSpacing

        let nsAlign: NSTextAlignment
        switch position {
        case .topLeading,  .leading,  .bottomLeading:  nsAlign = .left
        case .topTrailing, .trailing, .bottomTrailing: nsAlign = .right
        default: nsAlign = .center
        }

        let pStyle = NSMutableParagraphStyle()
        pStyle.lineSpacing = lineSpacing
        pStyle.alignment   = nsAlign

        let textUIColor = textColor.uiColor
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: uiFont, .foregroundColor: textUIColor, .paragraphStyle: pStyle
        ]

        let textMaxW = W - 2 * hPad
        let fullBoundsH: CGFloat = {
            guard !text.isEmpty else { return lineHeight }
            let r = NSAttributedString(string: text, attributes: textAttrs)
                .boundingRect(with: CGSize(width: textMaxW, height: 4000),
                              options: [.usesLineFragmentOrigin, .usesFontLeading],
                              context: nil)
            return ceil(r.height)
        }()
        let textLayerH = fullBoundsH + lineSpacing + 20

        // Anchor each row to the Instagram safe zone — top: below safeTop AND wordmark,
        // bottom: above safeBottom, center: midpoint of safe zone.
        let textFrameY: CGFloat = position.isTop
            ? max(wMarkZoneH + 4 * vScale, safeTop + 4 * vScale)
            : position.isBottom
                ? H - safeBottom - textLayerH
                : (safeTop + (H - safeBottom)) / 2 - textLayerH / 2
        let textFrame = CGRect(x: hPad, y: textFrameY, width: textMaxW, height: textLayerH)

        // ── 4. Pre-render text frames (UIKit images with shadow) ─────────────
        let imgFormat = UIGraphicsImageRendererFormat()
        imgFormat.scale = 1.0
        imgFormat.opaque = false
        let imgRenderer = UIGraphicsImageRenderer(size: CGSize(width: textMaxW, height: textLayerH),
                                                  format: imgFormat)

        var textCGImages: [CGImage] = []
        for k in 0...N {
            let cgImg = imgRenderer.image { ctx in
                guard k > 0 else { return }
                ctx.cgContext.setLineJoin(.round)
                NSAttributedString(string: String(chars.prefix(k)), attributes: textAttrs)
                    .draw(in: CGRect(x: 0, y: 0, width: textMaxW, height: textLayerH))
            }.cgImage
            textCGImages.append(cgImg ?? UIGraphicsImageRenderer(
                size: CGSize(width: 1, height: 1), format: imgFormat).image { _ in }.cgImage!)
        }

        // ── 5. Pre-compute cursor positions ──────────────────────────────────
        let cursorW: CGFloat = max(3.0, vScale * 0.8)
        let cursorH: CGFloat = ceil(uiFont.capHeight + abs(uiFont.descender)) + 2

        func measureLastLine(_ s: String) -> CGFloat {
            let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
            let last = String(lines.last ?? "")
            guard !last.isEmpty else { return 0 }
            return ceil(NSAttributedString(string: last, attributes: [.font: uiFont]).size().width)
        }

        func cursorPos(_ k: Int) -> CGPoint {
            let visible   = String(chars.prefix(k))
            let lineCount = max(1, visible.filter { $0 == "\n" }.count + 1)
            let lastW     = measureLastLine(visible)
            let cy = textFrameY + CGFloat(lineCount - 1) * lineHeight
            let cx: CGFloat
            switch nsAlign {
            case .left:  cx = hPad + lastW + 2
            case .right: cx = hPad + textMaxW - lastW - cursorW - 4
            default:     cx = W / 2 + lastW / 2 + 2
            }
            return CGPoint(x: cx, y: cy)
        }

        // ── 6. Build CALayer tree ─────────────────────────────────────────────
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: oneLinerSize)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: oneLinerSize)

        parentLayer.addSublayer(videoLayer)

        func discreteAnim(keyPath: String,
                          keyTimes: [NSNumber],
                          values: [Any]) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: keyPath)
            a.beginTime             = AVCoreAnimationBeginTimeAtZero
            a.duration              = D
            a.calculationMode       = .discrete
            a.fillMode              = .both
            a.isRemovedOnCompletion = false
            a.keyTimes              = keyTimes
            a.values                = values
            return a
        }

        if N > 0 {
            let textLayer = CALayer()
            textLayer.frame           = textFrame
            textLayer.contentsGravity = .topLeft
            textLayer.masksToBounds   = false
            textLayer.contents        = textCGImages[0]

            var cKeyTimes: [NSNumber] = [0.0]
            var cValues: [Any]        = [textCGImages[0] as Any]
            for k in 1...N {
                let frac = max(0.0001, charAppearTimes[k - 1] / D)
                cKeyTimes.append(NSNumber(value: frac))
                cValues.append(textCGImages[k] as Any)
            }
            cKeyTimes.append(1.0)
            cValues.append(textCGImages[N] as Any)

            textLayer.add(discreteAnim(keyPath: "contents",
                                       keyTimes: cKeyTimes,
                                       values: cValues),
                          forKey: "contents")
            parentLayer.addSublayer(textLayer)

            let cursorLayer = CALayer()
            cursorLayer.backgroundColor = textUIColor.cgColor
            cursorLayer.bounds          = CGRect(x: 0, y: 0, width: cursorW, height: cursorH)
            cursorLayer.anchorPoint     = CGPoint(x: 0, y: 0)
            cursorLayer.position        = cursorPos(0)
            cursorLayer.opacity         = 0.0

            var pKeyTimes: [NSNumber] = [0.0]
            var pValues:   [NSValue]  = [NSValue(cgPoint: cursorPos(0))]
            for k in 1...N {
                pKeyTimes.append(NSNumber(value: max(0.0001, charAppearTimes[k - 1] / D)))
                pValues.append(NSValue(cgPoint: cursorPos(k)))
            }
            pKeyTimes.append(1.0)
            pValues.append(NSValue(cgPoint: cursorPos(N)))
            cursorLayer.add(discreteAnim(keyPath: "position",
                                         keyTimes: pKeyTimes,
                                         values: pValues),
                            forKey: "position")

            var opKeyTimes: [NSNumber] = [0.0]
            var opValues:   [Float]    = [0.0]
            var bt = startDelay
            var blinkOn = true
            while bt < typingEndTime {
                let frac = bt / D
                if frac > 0 && frac <= 1.0 {
                    opKeyTimes.append(NSNumber(value: frac))
                    opValues.append(blinkOn ? 1.0 : 0.0)
                }
                bt += 0.25
                blinkOn.toggle()
            }
            let endFrac = min(typingEndTime / D, 1.0)
            opKeyTimes.append(NSNumber(value: max(endFrac, Double(opKeyTimes.last ?? 0) + 0.0001)))
            opValues.append(0.0)
            opKeyTimes.append(1.0)
            opValues.append(0.0)

            cursorLayer.add(discreteAnim(keyPath: "opacity",
                                         keyTimes: opKeyTimes,
                                         values: opValues),
                            forKey: "opacity")
            parentLayer.addSublayer(cursorLayer)
        }

        // ── Wordmark ──────────────────────────────────────────────────────────
        let wMarkLayerH = ceil(wMarkFontPx * 1.5)
        let wMarkW      = W - 2 * hPad

        let wMarkRenderer = UIGraphicsImageRenderer(
            size: CGSize(width: wMarkW, height: wMarkLayerH), format: imgFormat)
        let wMarkImg = wMarkRenderer.image { ctx in
            let mimoAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: wMarkFontPx, weight: .black),
                .foregroundColor: UIColor.white,
                .kern: NSNumber(value: 2.0)
            ]
            let runAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: wMarkFontPx, weight: .bold),
                .foregroundColor: UIColor(red: 0x7C/255.0, green: 0x5C/255.0,
                                          blue: 0xFC/255.0, alpha: 1),
                .kern: NSNumber(value: 2.0)
            ]
            let combined = NSMutableAttributedString(
                attributedString: NSAttributedString(string: "MIMO", attributes: mimoAttrs))
            combined.append(NSAttributedString(string: " RUNNING", attributes: runAttrs))

            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1 * vScale),
                                    blur: 3 * vScale,
                                    color: UIColor.black.withAlphaComponent(0.4).cgColor)
            combined.draw(in: CGRect(x: 0, y: 0, width: wMarkW, height: wMarkLayerH))
        }

        let wMarkLayer = CALayer()
        wMarkLayer.frame           = CGRect(x: hPad, y: wMarkTopPad, width: wMarkW, height: wMarkLayerH)
        wMarkLayer.contents        = wMarkImg.cgImage
        wMarkLayer.contentsGravity = .topLeft
        wMarkLayer.masksToBounds   = false
        parentLayer.addSublayer(wMarkLayer)

        // ── Date stamp ────────────────────────────────────────────────────────
        if showDate {
            let df = DateFormatter()
            df.dateFormat = "yyyy. M. d."
            let dateStr = df.string(from: activityDate)

            let dateFontPx: CGFloat = 11 * vScale
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: dateFontPx, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let dateAttrStr = NSAttributedString(string: dateStr, attributes: dateAttrs)
            let dateSize    = dateAttrStr.size()
            let datePad: CGFloat = 14 * vScale
            let dateImgW = ceil(dateSize.width) + 4
            let dateImgH = ceil(dateSize.height) + 4

            let dateRenderer = UIGraphicsImageRenderer(
                size: CGSize(width: dateImgW, height: dateImgH), format: imgFormat)
            let dateImg = dateRenderer.image { ctx in
                ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1 * vScale),
                                        blur: 6 * vScale,
                                        color: UIColor.black.withAlphaComponent(0.4).cgColor)
                dateAttrStr.draw(in: CGRect(x: 0, y: 0, width: dateImgW, height: dateImgH))
            }

            let dateLayer = CALayer()
            // 날짜: 워드마크(MIMO RUNNING) 줄 오른쪽 끝에 정렬 → 하단 문구와 겹침 방지
            dateLayer.frame           = CGRect(x: W - hPad - dateImgW,
                                               y: wMarkTopPad + (wMarkLayerH - dateImgH) / 2,
                                               width: dateImgW,
                                               height: dateImgH)
            dateLayer.contents        = dateImg.cgImage
            dateLayer.contentsGravity = .topLeft
            dateLayer.masksToBounds   = false
            parentLayer.addSublayer(dateLayer)
        }

        // ── Attach animation tool ─────────────────────────────────────────────
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        // ── 7. Export ─────────────────────────────────────────────────────────
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_oneliner_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHEVCHighestQuality)
        else { throw ExportError.sessionFailed }

        session.outputURL        = outputURL
        session.outputFileType   = .mov
        session.videoComposition = videoComposition
        session.timeRange        = timeRange

        let exportFlag = AVMutableMetadataItem()
        exportFlag.identifier = .commonIdentifierDescription
        exportFlag.value      = "MIMO_ONELINER_V1" as NSString
        session.metadata      = [exportFlag]

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

    // MARK: Export OneLiner multi-page typing animation
    //
    // Slots are grouped into pages of 2. Each page types its text, holds briefly,
    // then fades out. The last page stays until the video ends. Timing is distributed
    // evenly across the video duration.
    //
    // - Parameter pages: Array of pages; each page is 1-2 non-empty slot strings.
    //   Joined with "\n" per page for rendering. Empty pages are skipped.

    static func exportOneLinerMultiPageVideo(
        sourceURL: URL,
        pages: [[String]],
        fontChoice: OneLinerFont,
        textColor: OneLinerTextColor,
        position: CardPosition,
        activityDate: Date,
        showDate: Bool,
        muteAudio: Bool = false,
        maxDuration: Double? = nil   // nil = trimDuration (30s); pass total seconds for multi-clip
    ) async throws -> URL {

        let nonEmpty = pages.filter { $0.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        guard !nonEmpty.isEmpty else {
            return try await exportOneLinerTypingVideo(
                sourceURL: sourceURL, text: "",
                fontChoice: fontChoice, textColor: textColor, position: position,
                activityDate: activityDate, showDate: showDate)
        }
        if nonEmpty.count == 1 {
            let text = nonEmpty[0].joined(separator: "\n")
            return try await exportOneLinerTypingVideo(
                sourceURL: sourceURL, text: text,
                fontChoice: fontChoice, textColor: textColor, position: position,
                activityDate: activityDate, showDate: showDate)
        }

        let sourceURL   = try await preprocessHDRToSDR(url: sourceURL)
        let asset       = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw ExportError.noVideoTrack }

        let assetDuration      = try await asset.load(.duration)
        let naturalSize        = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let audioTracks        = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

        let trimEnd   = min(CMTimeGetSeconds(assetDuration), maxDuration ?? trimDuration)
        let timeRange = CMTimeRange(start: .zero,
                                    duration: CMTimeMakeWithSeconds(trimEnd, preferredTimescale: 600))
        let D = trimEnd

        // ── Composition (identical setup to single-page) ──────────────────────
        let oneLinerSize = CGSize(width: 1080, height: 1920)
        let displayRect  = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displayW     = abs(displayRect.width)
        let displayH     = abs(displayRect.height)
        let fillScale    = max(oneLinerSize.width / displayW, oneLinerSize.height / displayH)
        let txOff        = (oneLinerSize.width  - displayW * fillScale) / 2
        let tyOff        = (oneLinerSize.height - displayH * fillScale) / 2

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.compositionFailed }
        try compVideo.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        if !muteAudio, let audioTrack = audioTracks.first,
           let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compAudio.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        var tf = preferredTransform
        tf.tx -= displayRect.origin.x
        tf.ty -= displayRect.origin.y
        tf = tf.concatenating(CGAffineTransform(scaleX: fillScale, y: fillScale))
        tf = tf.concatenating(CGAffineTransform(translationX: txOff, y: tyOff))

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        layerInstruction.setTransform(tf, at: .zero)
        let vcInstruction = AVMutableVideoCompositionInstruction()
        vcInstruction.timeRange         = timeRange
        vcInstruction.layerInstructions = [layerInstruction]
        let videoComposition           = AVMutableVideoComposition()
        videoComposition.renderSize    = oneLinerSize
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComposition.instructions  = [vcInstruction]

        // SDR output: BT.709 — HDR sources tone-mapped with rolloff; preview = export.
        await applySDROutputProps(videoComposition, track: videoTrack)

        // ── Layout constants (same as single-page) ────────────────────────────
        let W: CGFloat = oneLinerSize.width
        let H: CGFloat = oneLinerSize.height
        let vScale: CGFloat = W / 300.0

        let safeTop:    CGFloat = CardVisual.videoSafeTop
        let safeBottom: CGFloat = CardVisual.videoSafeBottom
        let hPad:         CGFloat = 24 * vScale
        let wMarkTopPad:  CGFloat = 12 * vScale
        let wMarkFontPx:  CGFloat = 9  * vScale
        let wMarkZoneH:   CGFloat = wMarkTopPad + ceil(wMarkFontPx * 1.5) + 6 * vScale

        let fontSize:    CGFloat = OneLinerFont.basePt * fontChoice.sizeScale * vScale
        let lineSpacing: CGFloat = fontSize * 0.1
        let uiFont = fontChoice.uiFont(size: fontSize)
        let lineHeight: CGFloat = uiFont.lineHeight + lineSpacing

        let nsAlign: NSTextAlignment
        switch position {
        case .topLeading,  .leading,  .bottomLeading:  nsAlign = .left
        case .topTrailing, .trailing, .bottomTrailing: nsAlign = .right
        default: nsAlign = .center
        }
        let pStyle = NSMutableParagraphStyle()
        pStyle.lineSpacing = lineSpacing
        pStyle.alignment   = nsAlign

        let textUIColor = textColor.uiColor
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: uiFont, .foregroundColor: textUIColor, .paragraphStyle: pStyle
        ]
        let textMaxW = W - 2 * hPad

        let imgFormat = UIGraphicsImageRendererFormat()
        imgFormat.scale = 1.0
        imgFormat.opaque = false

        let cursorW: CGFloat = max(3.0, vScale * 0.8)
        let cursorH: CGFloat = ceil(uiFont.capHeight + abs(uiFont.descender)) + 2

        func measureLastLine(_ s: String) -> CGFloat {
            let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
            let last = String(lines.last ?? "")
            guard !last.isEmpty else { return 0 }
            return ceil(NSAttributedString(string: last, attributes: [.font: uiFont]).size().width)
        }

        // ── CALayer tree ──────────────────────────────────────────────────────
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: oneLinerSize)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: oneLinerSize)

        parentLayer.addSublayer(videoLayer)

        func discreteAnim(keyPath: String, keyTimes: [NSNumber], values: [Any]) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: keyPath)
            a.beginTime             = AVCoreAnimationBeginTimeAtZero
            a.duration              = D
            a.calculationMode       = .discrete
            a.fillMode              = .both
            a.isRemovedOnCompletion = false
            a.keyTimes              = keyTimes
            a.values                = values
            return a
        }

        // ── Per-page rendering ────────────────────────────────────────────────
        let numPages   = nonEmpty.count
        let timePerPage = D / Double(numPages)
        let fadeTime    = 0.35   // fade-out duration (last page: no fade)
        let holdTime    = 0.40   // hold after typing before fade
        let startDelay  = 0.20   // brief pause before first char per page

        for (pageIdx, pageSlots) in nonEmpty.enumerated() {
            let isLastPage  = pageIdx == numPages - 1
            let pageStart   = Double(pageIdx) * timePerPage
            let pageEnd     = isLastPage ? D : Double(pageIdx + 1) * timePerPage

            let combinedText = pageSlots.joined(separator: "\n")
            let chars = Array(combinedText)
            let N = chars.count

            let budget   = max(0.1, timePerPage - startDelay - holdTime - (isLastPage ? 0 : fadeTime))
            let rawDurs = VideoExportService.typingDurations(chars: chars, pageTime: budget)

            var charAppearTimes: [Double] = []
            var t = pageStart + startDelay
            for d in rawDurs { charAppearTimes.append(t); t += d }
            let typingEndTime = t

            // Fade-out window
            let fadeStart = isLastPage ? D : min(typingEndTime + holdTime, pageEnd - fadeTime)
            let fadeEnd   = isLastPage ? D : min(pageEnd, fadeStart + fadeTime)

            // ── Text frame for this page ──────────────────────────────────────
            let textLayerH: CGFloat = {
                guard !combinedText.isEmpty else { return lineHeight }
                let r = NSAttributedString(string: combinedText, attributes: textAttrs)
                    .boundingRect(with: CGSize(width: textMaxW, height: 4000),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                                  context: nil)
                return ceil(r.height) + lineSpacing + 20
            }()
            let textFrameY: CGFloat = position.isTop
                ? max(wMarkZoneH + 4 * vScale, safeTop + 4 * vScale)
                : position.isBottom
                    ? H - safeBottom - textLayerH
                    : (safeTop + (H - safeBottom)) / 2 - textLayerH / 2
            let textFrame = CGRect(x: hPad, y: textFrameY, width: textMaxW, height: textLayerH)

            // ── Pre-render character images ────────────────────────────────────
            let imgRenderer = UIGraphicsImageRenderer(
                size: CGSize(width: textMaxW, height: textLayerH), format: imgFormat)
            var charImages: [CGImage] = []
            for k in 0...N {
                let cgImg = imgRenderer.image { ctx in
                    guard k > 0 else { return }
                    ctx.cgContext.setLineJoin(.round)
                    NSAttributedString(string: String(chars.prefix(k)), attributes: textAttrs)
                        .draw(in: CGRect(x: 0, y: 0, width: textMaxW, height: textLayerH))
                }.cgImage
                charImages.append(cgImg ?? UIGraphicsImageRenderer(
                    size: CGSize(width: 1, height: 1), format: imgFormat).image { _ in }.cgImage!)
            }

            // ── Page container layer (handles appear/fade via opacity) ─────────
            let pageLayer = CALayer()
            pageLayer.frame   = CGRect(origin: .zero, size: oneLinerSize)
            pageLayer.opacity = 0.0

            // Opacity keyframes: 0 → appear at pageStart → 1 → fade at fadeStart → 0
            let opAppear = max(0.0, min((pageStart + 0.05) / D, 1.0))
            var opKeyTimes: [NSNumber]
            var opValues:   [Float]
            if isLastPage {
                opKeyTimes = [0.0, NSNumber(value: max(0.0001, pageStart / D)), NSNumber(value: opAppear), 1.0]
                opValues   = [0.0, 0.0, 1.0, 1.0]
            } else {
                let fFadeStart = max(opAppear + 0.0001, fadeStart / D)
                let fFadeEnd   = max(fFadeStart + 0.0001, min(fadeEnd / D, 1.0))
                opKeyTimes = [0.0,
                              NSNumber(value: max(0.0001, pageStart / D)),
                              NSNumber(value: opAppear),
                              NSNumber(value: fFadeStart),
                              NSNumber(value: fFadeEnd),
                              1.0]
                opValues   = [0.0, 0.0, 1.0, 1.0, 0.0, 0.0]
            }
            pageLayer.add(discreteAnim(keyPath: "opacity", keyTimes: opKeyTimes, values: opValues),
                          forKey: "opacity")

            // ── Text layer ────────────────────────────────────────────────────
            if N > 0 {
                let textLayer = CALayer()
                textLayer.frame           = textFrame
                textLayer.contentsGravity = .topLeft
                textLayer.masksToBounds   = false
                textLayer.contents        = charImages[0]

                var cKeyTimes: [NSNumber] = [0.0]
                var cValues: [Any]        = [charImages[0] as Any]
                for k in 1...N {
                    let frac = max(0.0001, charAppearTimes[k - 1] / D)
                    cKeyTimes.append(NSNumber(value: frac))
                    cValues.append(charImages[k] as Any)
                }
                cKeyTimes.append(1.0)
                cValues.append(charImages[N] as Any)
                textLayer.add(discreteAnim(keyPath: "contents", keyTimes: cKeyTimes, values: cValues),
                              forKey: "contents")
                pageLayer.addSublayer(textLayer)

                // ── Cursor layer ──────────────────────────────────────────────
                let cursorLayer = CALayer()
                cursorLayer.backgroundColor = textUIColor.cgColor
                cursorLayer.bounds          = CGRect(x: 0, y: 0, width: cursorW, height: cursorH)
                cursorLayer.anchorPoint     = CGPoint(x: 0, y: 0)
                cursorLayer.opacity         = 0.0

                func cursorPos(_ k: Int) -> CGPoint {
                    let visible   = String(chars.prefix(k))
                    let lineCount = max(1, visible.filter { $0 == "\n" }.count + 1)
                    let lastW     = measureLastLine(visible)
                    let cy = textFrameY + CGFloat(lineCount - 1) * lineHeight
                    let cx: CGFloat
                    switch nsAlign {
                    case .left:  cx = hPad + lastW + 2
                    case .right: cx = hPad + textMaxW - lastW - cursorW - 4
                    default:     cx = W / 2 + lastW / 2 + 2
                    }
                    return CGPoint(x: cx, y: cy)
                }

                var pKeyTimes: [NSNumber] = [0.0]
                var pValues:   [NSValue]  = [NSValue(cgPoint: cursorPos(0))]
                for k in 1...N {
                    pKeyTimes.append(NSNumber(value: max(0.0001, charAppearTimes[k - 1] / D)))
                    pValues.append(NSValue(cgPoint: cursorPos(k)))
                }
                pKeyTimes.append(1.0)
                pValues.append(NSValue(cgPoint: cursorPos(N)))
                cursorLayer.add(discreteAnim(keyPath: "position", keyTimes: pKeyTimes, values: pValues),
                                forKey: "position")

                // Blink during typing, hide at typing end
                let cursorStartFrac = max(0.0001, (pageStart + startDelay) / D)
                let cursorEndFrac   = min(typingEndTime / D, 1.0)
                var blinkKeyTimes: [NSNumber] = [0.0, NSNumber(value: cursorStartFrac)]
                var blinkValues:   [Float]    = [0.0, 1.0]
                var bt = pageStart + startDelay + 0.25
                var blinkOn = false
                while bt < typingEndTime && bt / D < 1.0 {
                    blinkKeyTimes.append(NSNumber(value: bt / D))
                    blinkValues.append(blinkOn ? 1.0 : 0.0)
                    bt += 0.25
                    blinkOn.toggle()
                }
                let safeEndFrac = max(Double(blinkKeyTimes.last ?? 0) + 0.0001, cursorEndFrac)
                blinkKeyTimes.append(NSNumber(value: min(safeEndFrac, 1.0)))
                blinkValues.append(0.0)
                blinkKeyTimes.append(1.0)
                blinkValues.append(0.0)
                cursorLayer.add(discreteAnim(keyPath: "opacity", keyTimes: blinkKeyTimes, values: blinkValues),
                                forKey: "opacity")
                pageLayer.addSublayer(cursorLayer)
            }

            parentLayer.addSublayer(pageLayer)
        }

        // ── Wordmark (static, same as single-page) ────────────────────────────
        let wMarkLayerH = ceil(wMarkFontPx * 1.5)
        let wMarkW      = W - 2 * hPad
        let wMarkRenderer = UIGraphicsImageRenderer(
            size: CGSize(width: wMarkW, height: wMarkLayerH), format: imgFormat)
        let wMarkImg = wMarkRenderer.image { ctx in
            let mimoAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: wMarkFontPx, weight: .black),
                .foregroundColor: UIColor.white,
                .kern: NSNumber(value: 2.0)
            ]
            let runAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: wMarkFontPx, weight: .bold),
                .foregroundColor: UIColor(red: 0x7C/255.0, green: 0x5C/255.0, blue: 0xFC/255.0, alpha: 1),
                .kern: NSNumber(value: 2.0)
            ]
            let combined = NSMutableAttributedString(
                attributedString: NSAttributedString(string: "MIMO", attributes: mimoAttrs))
            combined.append(NSAttributedString(string: " RUNNING", attributes: runAttrs))
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1 * vScale),
                                    blur: 3 * vScale,
                                    color: UIColor.black.withAlphaComponent(0.4).cgColor)
            combined.draw(in: CGRect(x: 0, y: 0, width: wMarkW, height: wMarkLayerH))
        }
        let wMarkLayer = CALayer()
        wMarkLayer.frame           = CGRect(x: hPad, y: wMarkTopPad, width: wMarkW, height: wMarkLayerH)
        wMarkLayer.contents        = wMarkImg.cgImage
        wMarkLayer.contentsGravity = .topLeft
        wMarkLayer.masksToBounds   = false
        parentLayer.addSublayer(wMarkLayer)

        // ── Date stamp (static) ───────────────────────────────────────────────
        if showDate {
            let df = DateFormatter()
            df.dateFormat = "yyyy. M. d."
            let dateStr = df.string(from: activityDate)
            let dateFontPx: CGFloat = 11 * vScale
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: dateFontPx, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let dateAttrStr = NSAttributedString(string: dateStr, attributes: dateAttrs)
            let dateSize    = dateAttrStr.size()
            let datePad: CGFloat = 14 * vScale
            let dateImgW = ceil(dateSize.width) + 4
            let dateImgH = ceil(dateSize.height) + 4
            let dateRenderer = UIGraphicsImageRenderer(
                size: CGSize(width: dateImgW, height: dateImgH), format: imgFormat)
            let dateImg = dateRenderer.image { ctx in
                ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1 * vScale),
                                        blur: 6 * vScale,
                                        color: UIColor.black.withAlphaComponent(0.4).cgColor)
                dateAttrStr.draw(in: CGRect(x: 0, y: 0, width: dateImgW, height: dateImgH))
            }
            let dateLayer = CALayer()
            // 날짜: 워드마크(MIMO RUNNING) 줄 오른쪽 끝에 정렬 → 하단 문구와 겹침 방지
            dateLayer.frame           = CGRect(x: W - hPad - dateImgW,
                                               y: wMarkTopPad + (wMarkLayerH - dateImgH) / 2,
                                               width: dateImgW,
                                               height: dateImgH)
            dateLayer.contents        = dateImg.cgImage
            dateLayer.contentsGravity = .topLeft
            dateLayer.masksToBounds   = false
            parentLayer.addSublayer(dateLayer)
        }

        // ── Assemble & export ─────────────────────────────────────────────────
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_oneliner_mp_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHEVCHighestQuality)
        else { throw ExportError.sessionFailed }

        session.outputURL        = outputURL
        session.outputFileType   = .mov
        session.videoComposition = videoComposition
        session.timeRange        = timeRange

        let exportFlag = AVMutableMetadataItem()
        exportFlag.identifier = .commonIdentifierDescription
        exportFlag.value      = "MIMO_ONELINER_V1" as NSString
        session.metadata      = [exportFlag]

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

    // MARK: Export OneLiner clip-bound typing animation
    //
    // Each ClipRecipe's lines are constrained to that clip's window in the composed timeline.
    // Clip offsets = cumulative trimmedDuration — identical to what composeAndExport(recipes:) used.
    // Within a clip, lines are grouped into pages of 2 and distributed evenly across the clip window.
    // Last page of each clip stays until clipEnd; last page overall stays until video end.
    // Clips with no text produce no overlay — empty clips are silent gaps.

    static func exportOneLinerClipBoundVideo(
        sourceURL: URL,
        recipes: [ClipRecipe],
        fontChoice: OneLinerFont,
        textColor: OneLinerTextColor,
        position: CardPosition,
        activityDate: Date,
        showDate: Bool,
        muteAudio: Bool = false,
        metricChips: [VideoMetricChip] = [],
        videoTitle: String = "",
        titleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    ) async throws -> URL {

        // ── 0. Page plan ──────────────────────────────────────────────────────
        var clipOffsets: [Double] = []
        var runningOffset = 0.0
        for recipe in recipes {
            clipOffsets.append(runningOffset)
            runningOffset += recipe.trimmedDuration
        }
        let D = runningOffset   // total composed duration

        // Last clip that has non-empty text
        var lastTextClipIdx = -1
        for (i, recipe) in recipes.enumerated() { if recipe.hasText { lastTextClipIdx = i } }

        struct PageSpec {
            let text: String
            let winStart: Double      // seconds into composed timeline
            let winEnd: Double        // D for last overall; clipEnd for last in non-last clip
            let isLast: Bool          // true = stays until D, no fade
            let clipIdx: Int          // index into recipes[] for per-clip style
        }
        var pageSpecs: [PageSpec] = []

        for (clipIdx, recipe) in recipes.enumerated() {
            let clipStart = clipOffsets[clipIdx]
            let clipEnd   = clipStart + recipe.trimmedDuration
            let nonEmpty  = recipe.lines.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard !nonEmpty.isEmpty else { continue }

            let clipPages  = stride(from: 0, to: nonEmpty.count, by: 4).map { i in   // 한 페이지 최대 4줄
                Array(nonEmpty[i..<min(i + 4, nonEmpty.count)])
            }
            let nPages     = clipPages.count
            let tPerPage   = recipe.trimmedDuration / Double(nPages)
            let isLastClip = clipIdx == lastTextClipIdx

            for (pIdx, slots) in clipPages.enumerated() {
                let isLastInClip = pIdx == nPages - 1
                let isLast       = isLastClip && isLastInClip
                let winStart     = clipStart + Double(pIdx) * tPerPage
                let winEnd       = isLastInClip
                    ? (isLast ? D : clipEnd)
                    : clipStart + Double(pIdx + 1) * tPerPage
                let text         = slots.joined(separator: "\n")
                pageSpecs.append(PageSpec(text: text, winStart: winStart, winEnd: winEnd, isLast: isLast, clipIdx: clipIdx))
            }
        }

        guard !pageSpecs.isEmpty else {
            return try await exportOneLinerTypingVideo(
                sourceURL: sourceURL, text: "",
                fontChoice: fontChoice, textColor: textColor, position: position,
                activityDate: activityDate, showDate: showDate, muteAudio: muteAudio)
        }

        // ── 1. Asset ──────────────────────────────────────────────────────────
        let sourceURL   = try await preprocessHDRToSDR(url: sourceURL)
        let asset       = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw ExportError.noVideoTrack }
        let naturalSize   = try await videoTrack.load(.naturalSize)
        let prefTransform = try await videoTrack.load(.preferredTransform)
        let audioTracks   = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

        let timeRange = CMTimeRange(start: .zero,
                                    duration: CMTimeMakeWithSeconds(D, preferredTimescale: 600))

        // ── 2. Composition ────────────────────────────────────────────────────
        let oneLinerSize = CGSize(width: 1080, height: 1920)
        let displayRect  = CGRect(origin: .zero, size: naturalSize).applying(prefTransform)
        let displayW     = abs(displayRect.width)
        let displayH     = abs(displayRect.height)
        let fillScale    = max(oneLinerSize.width / displayW, oneLinerSize.height / displayH)
        let txOff        = (oneLinerSize.width  - displayW * fillScale) / 2
        let tyOff        = (oneLinerSize.height - displayH * fillScale) / 2

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.compositionFailed }
        try compVideo.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        if !muteAudio, let audioTrack = audioTracks.first,
           let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compAudio.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        var tf = prefTransform
        tf.tx -= displayRect.origin.x
        tf.ty -= displayRect.origin.y
        tf = tf.concatenating(CGAffineTransform(scaleX: fillScale, y: fillScale))
        tf = tf.concatenating(CGAffineTransform(translationX: txOff, y: tyOff))

        let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        layerInstr.setTransform(tf, at: .zero)
        let vcInstr = AVMutableVideoCompositionInstruction()
        vcInstr.timeRange         = timeRange
        vcInstr.layerInstructions = [layerInstr]
        let videoComp           = AVMutableVideoComposition()
        videoComp.renderSize    = oneLinerSize
        videoComp.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComp.instructions  = [vcInstr]

        // SDR output: BT.709 — HDR sources tone-mapped with rolloff; preview = export.
        await applySDROutputProps(videoComp, track: videoTrack)

        // ── 4. Content layer (shared with preview) ─────────────────────────
        let contentLayer = buildClipTextContentLayer(
            recipes: recipes, renderSize: oneLinerSize, totalDuration: D,
            activityDate: activityDate, showDate: showDate, metricChips: metricChips,
            videoTitle: videoTitle, titleStyle: titleStyle)

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: oneLinerSize)
        let exportParent = CALayer()
        exportParent.frame = CGRect(origin: .zero, size: oneLinerSize)
        exportParent.isGeometryFlipped = true
        exportParent.addSublayer(videoLayer)
        exportParent.addSublayer(contentLayer)


        // ── 8. Export ─────────────────────────────────────────────────────────
        videoComp.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: exportParent)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_oneliner_cb_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHEVCHighestQuality)
        else { throw ExportError.sessionFailed }

        session.outputURL        = outputURL
        session.outputFileType   = .mov
        session.videoComposition = videoComp
        session.timeRange        = timeRange

        let exportFlag = AVMutableMetadataItem()
        exportFlag.identifier = .commonIdentifierDescription
        exportFlag.value      = "MIMO_ONELINER_V1" as NSString
        session.metadata      = [exportFlag]

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

    // MARK: - buildClipTextContentLayer (shared: export + preview)
    //
    // Builds the text/overlay CALayer hierarchy for video clips WITHOUT isGeometryFlipped.
    // Export: caller wraps in a flipped exportParent + videoLayer.
    // Preview: caller attaches directly to AVSynchronizedLayer.

    static func buildClipTextContentLayer(
        recipes: [ClipRecipe],
        renderSize: CGSize,
        totalDuration D: Double,
        activityDate: Date,
        showDate: Bool,
        metricChips: [VideoMetricChip] = [],
        videoTitle: String = "",
        titleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    ) -> CALayer {
        let W = renderSize.width
        let H = renderSize.height
        let vScale: CGFloat   = W / 300.0
        let safeTop: CGFloat  = CardVisual.videoSafeTop
        let safeBot: CGFloat  = CardVisual.videoSafeBottom
        let hPad: CGFloat     = 24 * vScale
        let wMTopPad: CGFloat = 12 * vScale
        let wMFontPx: CGFloat = 9  * vScale
        let wMZoneH: CGFloat  = wMTopPad + ceil(wMFontPx * 1.5) + 6 * vScale
        let textMaxW: CGFloat = W - 2 * hPad
        let imgFormat   = UIGraphicsImageRendererFormat()
        imgFormat.scale = 1.0; imgFormat.opaque = false
        let cursorW: CGFloat  = max(3.0, vScale * 0.8)

        let contentLayer = CALayer()
        contentLayer.frame = CGRect(origin: .zero, size: renderSize)

        func discreteAnim(keyPath: String, keyTimes: [NSNumber], values: [Any]) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: keyPath)
            a.beginTime             = AVCoreAnimationBeginTimeAtZero
            a.duration              = D
            a.calculationMode       = .discrete
            a.fillMode              = .both
            a.isRemovedOnCompletion = false
            a.keyTimes              = keyTimes
            a.values                = values
            return a
        }
        func linearAnim(keyPath: String, keyTimes: [NSNumber], values: [Any]) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: keyPath)
            a.beginTime             = AVCoreAnimationBeginTimeAtZero
            a.duration              = D
            a.calculationMode       = .linear
            a.fillMode              = .both
            a.isRemovedOnCompletion = false
            a.keyTimes              = keyTimes
            a.values                = values
            return a
        }

        // ── Page plan ─────────────────────────────────────────────────────────
        var clipOffsets: [Double] = []
        var runningOffset = 0.0
        for recipe in recipes { clipOffsets.append(runningOffset); runningOffset += recipe.trimmedDuration }
        var lastTextClipIdx = -1
        for (i, recipe) in recipes.enumerated() { if recipe.hasText { lastTextClipIdx = i } }

        struct PageSpec {
            let text: String; let winStart: Double; let winEnd: Double
            let isLast: Bool; let clipIdx: Int
        }
        var pageSpecs: [PageSpec] = []
        for (clipIdx, recipe) in recipes.enumerated() {
            let clipStart = clipOffsets[clipIdx]
            let clipEnd   = clipStart + recipe.trimmedDuration
            let nonEmpty  = recipe.lines.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard !nonEmpty.isEmpty else { continue }
            let clipPages  = stride(from: 0, to: nonEmpty.count, by: 4).map { i in   // 한 페이지 최대 4줄
                Array(nonEmpty[i..<min(i + 4, nonEmpty.count)])
            }
            let nPages     = clipPages.count
            let tPerPage   = recipe.trimmedDuration / Double(nPages)
            let isLastClip = clipIdx == lastTextClipIdx
            for (pIdx, slots) in clipPages.enumerated() {
                let isLastInClip = pIdx == nPages - 1
                let isLast       = isLastClip && isLastInClip
                let winStart     = clipStart + Double(pIdx) * tPerPage
                let winEnd       = isLastInClip
                    ? (isLast ? D : clipEnd)
                    : clipStart + Double(pIdx + 1) * tPerPage
                pageSpecs.append(PageSpec(text: slots.joined(separator: "\n"),
                                          winStart: winStart, winEnd: winEnd, isLast: isLast,
                                          clipIdx: clipIdx))
            }
        }

        // ── Per-page text layers ───────────────────────────────────────────────
        let startDelay: Double = 0.20
        let holdTime:   Double = 0.40
        let fadeTime:   Double = 0.25

        for page in pageSpecs {
            let chars     = Array(page.text)
            let N         = chars.count
            let windowDur = page.winEnd - page.winStart

            let clip        = page.clipIdx < recipes.count ? recipes[page.clipIdx] : recipes[0]
            let fontSize    = OneLinerFont.basePt * clip.fontChoice.sizeScale * clip.sizeLevel.scale * vScale
            let uiFont      = clip.fontChoice.boldUIFont(size: fontSize)
            let plateLayout = clip.plateOn ? PlateLayout(uiFont: uiFont, vScale: vScale) : nil
            let lineSpacing = plateLayout?.lineSpacing ?? (fontSize * 0.1)
            let lineH       = uiFont.lineHeight + lineSpacing
            let nsAlign: NSTextAlignment = {
                switch clip.position {
                case .topLeading, .leading, .bottomLeading:    return .left
                case .topTrailing, .trailing, .bottomTrailing: return .right
                default: return .center
                }
            }()
            let pStyle = NSMutableParagraphStyle()
            pStyle.lineSpacing = lineSpacing; pStyle.alignment = nsAlign
            let textUIColor = clip.plateOn
                ? clip.plateColorPreset.textUIColor
                : clip.textColor.uiColor
            var textAttrs: [NSAttributedString.Key: Any] = [
                .font: uiFont, .foregroundColor: textUIColor, .paragraphStyle: pStyle
            ]
            // 합성 볼드: pen/brush만 적용(size 비례), gothic/round는 실제 볼드 웨이트 사용
            let synStroke = clip.fontChoice.syntheticBoldStroke(for: fontSize)
            if synStroke != 0 {
                textAttrs[.strokeWidth] = synStroke
                textAttrs[.strokeColor] = textUIColor
            }
            // 8방향 테두리: borderUIColor fill, 별도 borderAttrs (blur 0, lineJoin=round)
            let borderOffset: CGFloat = clip.hasBorder ? fontSize * clip.textColor.borderOffsetFactor : 0
            let borderAttrs: [NSAttributedString.Key: Any]? = clip.hasBorder ? [
                .font: uiFont,
                .foregroundColor: clip.textColor.borderUIColor,
                .paragraphStyle: pStyle
            ] : nil
            let cursorH: CGFloat = ceil(uiFont.capHeight + abs(uiFont.descender)) + 2
            func measureLastLine(_ s: String) -> CGFloat {
                let ls = s.split(separator: "\n", omittingEmptySubsequences: false)
                guard let last = ls.last, !last.isEmpty else { return 0 }
                return ceil(NSAttributedString(string: String(last), attributes: [.font: uiFont]).size().width)
            }

            // ── 타임라인 계산 ──────────────────────────────────────────────────
            let isFade  = clip.appearanceMode == .fade
            let isFlyIn = clip.appearanceMode == .flyIn
            var charAppearTimes: [Double] = []  // typing 전용
            let appearEnd: Double   // 텍스트 완전히 보이는 시점
            let fadeStart: Double
            let fadeEnd:   Double
            if isFade {
                let fi = page.winStart + startDelay + max(0.30, windowDur * 0.30)
                appearEnd = fi
                // 페이드 모드: 클립(페이지) 끝까지 유지, 마지막 순간에만 짧게 페이드아웃
                fadeStart = page.isLast ? D : max(fi + 0.05, page.winEnd - fadeTime)
                fadeEnd   = page.isLast ? D : min(page.winEnd, fadeStart + fadeTime)
            } else if isFlyIn {
                // 줄 수만큼 stagger 반영: 마지막 줄 시작 + 0.30 s
                let lineDelay_t   = 0.25
                let lineTexts_t   = page.text.components(separatedBy: "\n")
                let nonEmptyCnt_t = lineTexts_t.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                let slideEnd      = page.winStart + startDelay + Double(max(0, nonEmptyCnt_t - 1)) * lineDelay_t + 0.30
                appearEnd = slideEnd
                fadeStart = page.isLast ? D : max(slideEnd + 0.05, page.winEnd - fadeTime)
                fadeEnd   = page.isLast ? D : min(page.winEnd, fadeStart + fadeTime)
            } else {
                let budget  = max(0.1, windowDur - startDelay - holdTime - (page.isLast ? 0 : fadeTime))
                let rawDurs = VideoExportService.typingDurations(chars: chars, pageTime: budget)
                var tc = page.winStart + startDelay
                for d in rawDurs { charAppearTimes.append(tc); tc += d }
                appearEnd = tc
                fadeStart = page.isLast ? D : min(tc + holdTime, page.winEnd - fadeTime)
                fadeEnd   = page.isLast ? D : min(page.winEnd, fadeStart + fadeTime)
            }

            let textLayerH: CGFloat = {
                guard !page.text.isEmpty else { return lineH }
                let r = NSAttributedString(string: page.text, attributes: textAttrs)
                    .boundingRect(with: CGSize(width: textMaxW, height: 4000),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                return ceil(r.height) + lineSpacing + 20
            }()
            let textFrameY: CGFloat = clip.position.isTop
                ? max(wMZoneH + 4 * vScale, safeTop + 4 * vScale)
                : clip.position.isBottom
                    ? H - safeBot - textLayerH
                    : (safeTop + (H - safeBot)) / 2 - textLayerH / 2
            let textFrame = CGRect(x: hPad, y: textFrameY, width: textMaxW, height: textLayerH)

            let imgRenderer = UIGraphicsImageRenderer(
                size: CGSize(width: textMaxW, height: textLayerH), format: imgFormat)
            let fallbackImg = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: imgFormat)
                .image { _ in }.cgImage!
            // 페이드: 완성 이미지 1장. 타이핑: N+1장. 날아오기: 줄별 개별 렌더링(아래 isFlyIn 블록에서 처리).
            let renderRange = isFade ? [N] : (isFlyIn ? [] : Array(0...N))
            var charImages: [CGImage] = []
            for k in renderRange {
                let cgImg = imgRenderer.image { ctx in
                    guard k > 0 else { return }
                    ctx.cgContext.setLineJoin(.round)
                    let str  = String(chars.prefix(k))
                    let rect = CGRect(x: 0, y: 0, width: textMaxW, height: textLayerH)
                    if let ba = borderAttrs {
                        let bStr = NSAttributedString(string: str, attributes: ba)
                        let o = borderOffset
                        for (ox, oy): (CGFloat, CGFloat) in [(-o,-o),(o,-o),(-o,o),(o,o),(-o,0),(o,0),(0,-o),(0,o)] {
                            bStr.draw(in: rect.offsetBy(dx: ox, dy: oy))
                        }
                    }
                    NSAttributedString(string: str, attributes: textAttrs).draw(in: rect)
                }.cgImage
                charImages.append(cgImg ?? fallbackImg)
            }

            let pageLayer = CALayer()
            pageLayer.frame = CGRect(origin: .zero, size: renderSize); pageLayer.opacity = 0.0

            let opAppear = max(0.0, min((page.winStart + 0.05) / D, 1.0))
            let pgKeyTimes: [NSNumber]; let pgValues: [Float]
            if page.isLast {
                pgKeyTimes = [0.0, NSNumber(value: max(0.0001, page.winStart / D)),
                              NSNumber(value: opAppear), 1.0]
                pgValues   = [0.0, 0.0, 1.0, 1.0]
            } else {
                let fFadeStart = max(opAppear + 0.0001, fadeStart / D)
                let fFadeEnd   = max(fFadeStart + 0.0001, min(fadeEnd / D, 1.0))
                pgKeyTimes = [0.0, NSNumber(value: max(0.0001, page.winStart / D)),
                              NSNumber(value: opAppear), NSNumber(value: fFadeStart),
                              NSNumber(value: fFadeEnd), 1.0]
                pgValues   = [0.0, 0.0, 1.0, 1.0, 0.0, 0.0]
            }
            pageLayer.add(discreteAnim(keyPath: "opacity", keyTimes: pgKeyTimes, values: pgValues),
                          forKey: "opacity")

            if N > 0 {
                // 음영판 줄별 판: textLayer보다 먼저 추가, 애니메이션 동기화를 위해 참조 보관
                var plateLayers:      [CALayer] = []
                var plateLineIndices: [Int]     = []
                // 날아오기 모드는 줄별 루프 내에서 판+텍스트를 동시 생성.
                if !isFlyIn, let pl = plateLayout {
                    let platePadH = pl.padH
                    let platePadV = pl.padV
                    let cornerR   = pl.cornerR
                    let lineStep  = pl.lineStep
                    let plateH    = pl.plateH
                    let anchorX: CGFloat
                    let anchorPosX: CGFloat
                    switch nsAlign {
                    case .center: anchorX = 0.5; anchorPosX = hPad + textMaxW / 2
                    case .right:  anchorX = 1.0; anchorPosX = hPad + textMaxW
                    default:      anchorX = 0.0; anchorPosX = hPad
                    }
                    for (i, rawLine) in page.text.components(separatedBy: "\n").enumerated() {
                        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        let lineW  = min(ceil(NSAttributedString(string: trimmed, attributes: textAttrs).size().width), textMaxW)
                        let plateW = lineW + 2 * platePadH
                        let lineTopY = textFrame.minY + CGFloat(i) * lineStep
                        let pLayer = CALayer()
                        pLayer.anchorPoint     = CGPoint(x: anchorX, y: 0.5)
                        pLayer.position        = CGPoint(x: anchorPosX, y: lineTopY - platePadV + plateH / 2)
                        pLayer.bounds          = CGRect(x: 0, y: 0, width: plateW, height: plateH)
                        pLayer.backgroundColor = clip.plateColorPreset.plateUIColorWithAlpha.cgColor
                        pLayer.cornerRadius    = cornerR
                        pLayer.masksToBounds   = true
                        pageLayer.addSublayer(pLayer)
                        plateLayers.append(pLayer)
                        plateLineIndices.append(i)
                    }
                }

                let textLayer = CALayer()
                textLayer.frame           = textFrame
                textLayer.contentsGravity = .topLeft
                textLayer.masksToBounds   = false

                if isFade {
                    // ── 페이드 모드 ──────────────────────────────────────────────
                    textLayer.contents = charImages[0]
                    textLayer.opacity  = 0.0
                    let tiS = max(0.0001, (page.winStart + startDelay) / D)
                    let tiE = min(appearEnd / D, 1.0)
                    let fadeKT: [NSNumber] = [0.0, NSNumber(value: tiS), NSNumber(value: tiE), 1.0]
                    let fadeV:  [Any]      = [Float(0), Float(0), Float(1), Float(1)]
                    textLayer.add(linearAnim(keyPath: "opacity", keyTimes: fadeKT, values: fadeV),
                                  forKey: "textFade")
                    // 음영판도 함께 페이드인
                    for pLayer in plateLayers {
                        pLayer.opacity = 0.0
                        pLayer.add(linearAnim(keyPath: "opacity", keyTimes: fadeKT, values: fadeV),
                                   forKey: "plateFade")
                    }
                    // 팝: 페이드 완료 직후 1회 1.25→1.0 스프링 (반동 강화)
                    if clip.decorEffect == .pop {
                        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
                        pop.values          = [1.40, 1.14, 0.90, 1.05, 1.0]   // 반동 강화
                        pop.keyTimes        = [0.0,  0.3,  0.6,  0.82, 1.0] as [NSNumber]
                        pop.duration        = 0.45
                        pop.beginTime       = AVCoreAnimationBeginTimeAtZero + appearEnd
                        pop.fillMode        = .both
                        pop.isRemovedOnCompletion = false
                        pop.calculationMode = .linear
                        textLayer.add(pop, forKey: "pop")
                    }
                    // 흔들림 ±1.5° (주기 유지)
                    if clip.decorEffect == .wobble {
                        let wob = CAKeyframeAnimation(keyPath: "transform.rotation.z")
                        wob.values           = [0.0, 0.044, 0.0, -0.044, 0.0]  // ±2.5° (강화)
                        wob.keyTimes         = [0.0, 0.25,  0.5,  0.75,  1.0]
                        wob.duration         = 0.5
                        wob.repeatCount      = .infinity
                        wob.calculationMode  = .linear
                        wob.beginTime        = AVCoreAnimationBeginTimeAtZero
                        wob.fillMode         = .both
                        wob.isRemovedOnCompletion = false
                        textLayer.add(wob, forKey: "wobble")
                    }
                    pageLayer.addSublayer(textLayer)
                } else if isFlyIn {
                    // ── 날아오기 모드: 줄별 순차 ─────────────────────────────────
                    // 줄마다 독립 레이어, 0.25 s 간격 stagger.
                    let lineDelay:    Double  = 0.25
                    let flyDur:       Double  = 0.45   // 날아오기 속도 완화(느리게)
                    let flyVertical   = clip.flyDirection.isVertical
                    let flyKey        = flyVertical ? "transform.translation.y" : "transform.translation.x"
                    let slideX:       CGFloat = flyVertical ? H * 0.3 : (clip.flyDirection == .trailing ? W : -W)
                    let lineTexts     = page.text.components(separatedBy: "\n")
                    let lineRenderer  = UIGraphicsImageRenderer(
                        size: CGSize(width: textMaxW, height: ceil(lineH)), format: imgFormat)
                    let anchorX:    CGFloat
                    let anchorPosX: CGFloat
                    switch nsAlign {
                    case .center: anchorX = 0.5; anchorPosX = hPad + textMaxW / 2
                    case .right:  anchorX = 1.0; anchorPosX = hPad + textMaxW
                    default:      anchorX = 0.0; anchorPosX = hPad
                    }
                    var staggerIdx = 0
                    for (i, rawLine) in lineTexts.enumerated() {
                        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        let flyBegin = page.winStart + startDelay + Double(staggerIdx) * lineDelay
                        staggerIdx  += 1
                        let lineTopY = textFrame.minY + CGFloat(i) * lineH
                        // 판 레이어 (텍스트보다 먼저 → z-order 아래)
                        if let pl = plateLayout {
                            let lineW  = min(ceil(NSAttributedString(string: trimmed, attributes: textAttrs).size().width), textMaxW)
                            let pLayer = CALayer()
                            pLayer.anchorPoint     = CGPoint(x: anchorX, y: 0.5)
                            pLayer.position        = CGPoint(x: anchorPosX, y: lineTopY - pl.padV + pl.plateH / 2)
                            pLayer.bounds          = CGRect(x: 0, y: 0, width: lineW + 2 * pl.padH, height: pl.plateH)
                            pLayer.backgroundColor = clip.plateColorPreset.plateUIColorWithAlpha.cgColor
                            pLayer.cornerRadius    = pl.cornerR
                            pLayer.masksToBounds   = true
                            pageLayer.addSublayer(pLayer)
                            let pFly                     = CABasicAnimation(keyPath: flyKey)
                            pFly.beginTime               = AVCoreAnimationBeginTimeAtZero + flyBegin
                            pFly.duration                = flyDur
                            pFly.fromValue               = Float(slideX)
                            pFly.toValue                 = Float(0)
                            pFly.timingFunction          = CAMediaTimingFunction(name: .easeOut)
                            pFly.fillMode                = .both
                            pFly.isRemovedOnCompletion   = false
                            pLayer.add(pFly, forKey: "flyIn")
                        }
                        // 텍스트 레이어
                        let lineImg = lineRenderer.image { ctx in
                            ctx.cgContext.setLineJoin(.round)
                            let lRect = CGRect(x: 0, y: 0, width: textMaxW, height: ceil(lineH))
                            if let ba = borderAttrs {
                                let bStr = NSAttributedString(string: trimmed, attributes: ba)
                                let o = borderOffset
                                for (ox, oy): (CGFloat, CGFloat) in [(-o,-o),(o,-o),(-o,o),(o,o),(-o,0),(o,0),(0,-o),(0,o)] {
                                    bStr.draw(in: lRect.offsetBy(dx: ox, dy: oy))
                                }
                            }
                            NSAttributedString(string: trimmed, attributes: textAttrs).draw(in: lRect)
                        }.cgImage ?? fallbackImg
                        let lineLayer                    = CALayer()
                        lineLayer.frame                  = CGRect(x: textFrame.origin.x, y: lineTopY,
                                                                  width: textMaxW, height: ceil(lineH))
                        lineLayer.contentsGravity        = .topLeft
                        lineLayer.masksToBounds          = false
                        lineLayer.contents               = lineImg
                        let fly                          = CABasicAnimation(keyPath: flyKey)
                        fly.beginTime                    = AVCoreAnimationBeginTimeAtZero + flyBegin
                        fly.duration                     = flyDur
                        fly.fromValue                    = Float(slideX)
                        fly.toValue                      = Float(0)
                        fly.timingFunction               = CAMediaTimingFunction(name: .easeOut)
                        fly.fillMode                     = .both
                        fly.isRemovedOnCompletion        = false
                        lineLayer.add(fly, forKey: "flyIn")
                        pageLayer.addSublayer(lineLayer)
                    }
                } else {
                    // ── 타이핑 모드 ──────────────────────────────────────────────
                    textLayer.contents = charImages[0]
                    var cKeyTimes: [NSNumber] = [0.0]
                    var cValues:   [Any]      = [charImages[0] as Any]
                    for k in 1...N {
                        cKeyTimes.append(NSNumber(value: max(0.0001, charAppearTimes[k - 1] / D)))
                        cValues.append(charImages[k] as Any)
                    }
                    cKeyTimes.append(1.0); cValues.append(charImages[N] as Any)
                    textLayer.add(discreteAnim(keyPath: "contents", keyTimes: cKeyTimes, values: cValues),
                                  forKey: "contents")
                    pageLayer.addSublayer(textLayer)

                    // ── 커서 (타이핑 전용) ──────────────────────────────────────
                    let cursorLayer = CALayer()
                    cursorLayer.backgroundColor = textUIColor.cgColor
                    cursorLayer.bounds          = CGRect(x: 0, y: 0, width: cursorW, height: cursorH)
                    cursorLayer.anchorPoint     = CGPoint(x: 0, y: 0)
                    cursorLayer.opacity         = 0.0

                    func cursorPos(_ k: Int) -> CGPoint {
                        let visible   = String(chars.prefix(k))
                        let lineCount = max(1, visible.filter { $0 == "\n" }.count + 1)
                        let lastW     = measureLastLine(visible)
                        let cy2 = textFrameY + CGFloat(lineCount - 1) * lineH
                        let cx2: CGFloat
                        switch nsAlign {
                        case .left:  cx2 = hPad + lastW + 2
                        case .right: cx2 = hPad + textMaxW - lastW - cursorW - 4
                        default:     cx2 = W / 2 + lastW / 2 + 2
                        }
                        return CGPoint(x: cx2, y: cy2)
                    }

                    var pKeyTimes: [NSNumber] = [0.0]
                    var pValues:   [NSValue]  = [NSValue(cgPoint: cursorPos(0))]
                    for k in 1...N {
                        pKeyTimes.append(NSNumber(value: max(0.0001, charAppearTimes[k - 1] / D)))
                        pValues.append(NSValue(cgPoint: cursorPos(k)))
                    }
                    pKeyTimes.append(1.0); pValues.append(NSValue(cgPoint: cursorPos(N)))
                    cursorLayer.add(discreteAnim(keyPath: "position", keyTimes: pKeyTimes, values: pValues),
                                    forKey: "position")

                    let cursorStartFrac = max(0.0001, (page.winStart + startDelay) / D)
                    let cursorEndFrac   = min(appearEnd / D, 1.0)
                    var blinkKeyTimes: [NSNumber] = [0.0, NSNumber(value: cursorStartFrac)]
                    var blinkValues:   [Float]    = [0.0, 1.0]
                    var bt = page.winStart + startDelay + 0.25; var blinkOn = false
                    while bt < appearEnd && bt / D < 1.0 {
                        blinkKeyTimes.append(NSNumber(value: bt / D))
                        blinkValues.append(blinkOn ? 1.0 : 0.0)
                        bt += 0.25; blinkOn.toggle()
                    }
                    let safeEnd = max((blinkKeyTimes.last ?? 0).doubleValue + 0.0001, cursorEndFrac)
                    blinkKeyTimes.append(NSNumber(value: min(safeEnd, 1.0))); blinkValues.append(0.0)
                    blinkKeyTimes.append(1.0); blinkValues.append(0.0)
                    cursorLayer.add(discreteAnim(keyPath: "opacity",
                                                 keyTimes: blinkKeyTimes, values: blinkValues), forKey: "opacity")
                    pageLayer.addSublayer(cursorLayer)

                    // ── 음영판 타이핑 동기화: 판 폭이 글자를 따라 늘어남 ──────────────
                    if !plateLayers.isEmpty {
                        let textLines = page.text.components(separatedBy: "\n")
                        var lineCharStarts: [Int] = []
                        var lineCharEnds:   [Int] = []
                        var cur = 0
                        for line in textLines {
                            lineCharStarts.append(cur)
                            cur += line.count
                            lineCharEnds.append(cur)
                            cur += 1  // \n 건너뜀
                        }
                        let platePadH: CGFloat = 8 * vScale
                        for (j, pLayer) in plateLayers.enumerated() {
                            let lineIdx = plateLineIndices[j]
                            guard lineIdx < lineCharStarts.count else { continue }
                            let s  = lineCharStarts[lineIdx]
                            let e  = lineCharEnds[lineIdx]
                            let fH = pLayer.bounds.height
                            let fW = pLayer.bounds.width
                            var wKeyTimes: [NSNumber] = [0.0]
                            var wValues:   [Any]      = [NSValue(cgRect: CGRect(x: 0, y: 0, width: 0, height: fH))]
                            for k in 1...N {
                                let typed = max(0, min(k, e) - s)
                                let pW: CGFloat
                                if typed > 0 {
                                    let t = String(chars[s..<(s + typed)])
                                    let w = min(ceil(NSAttributedString(string: t, attributes: textAttrs).size().width), textMaxW)
                                    pW = w + 2 * platePadH
                                } else {
                                    pW = 0
                                }
                                wKeyTimes.append(NSNumber(value: max(0.0001, charAppearTimes[k - 1] / D)))
                                wValues.append(NSValue(cgRect: CGRect(x: 0, y: 0, width: pW, height: fH)))
                            }
                            wKeyTimes.append(1.0)
                            wValues.append(NSValue(cgRect: CGRect(x: 0, y: 0, width: fW, height: fH)))
                            pLayer.bounds = CGRect(x: 0, y: 0, width: 0, height: fH)
                            pLayer.add(discreteAnim(keyPath: "bounds", keyTimes: wKeyTimes, values: wValues), forKey: "plateBounds")
                        }
                    }
                }
            }
            contentLayer.addSublayer(pageLayer)
        }

        // ── Wordmark ───────────────────────────────────────────────────────────
        let wMLayerH = ceil(wMFontPx * 1.5)
        let wMarkW   = W - 2 * hPad
        let wMRenderer = UIGraphicsImageRenderer(
            size: CGSize(width: wMarkW, height: wMLayerH), format: imgFormat)
        let wMImg = wMRenderer.image { ctx in
            let mimoAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: wMFontPx, weight: .black),
                .foregroundColor: UIColor.white, .kern: NSNumber(value: 2.0)
            ]
            let runAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: wMFontPx, weight: .bold),
                .foregroundColor: UIColor(red: 0x7C/255.0, green: 0x5C/255.0,
                                          blue: 0xFC/255.0, alpha: 1),
                .kern: NSNumber(value: 2.0)
            ]
            let combined = NSMutableAttributedString(
                attributedString: NSAttributedString(string: "MIMO", attributes: mimoAttrs))
            combined.append(NSAttributedString(string: " RUNNING", attributes: runAttrs))
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1 * vScale),
                                    blur: 3 * vScale,
                                    color: UIColor.black.withAlphaComponent(0.4).cgColor)
            combined.draw(in: CGRect(x: 0, y: 0, width: wMarkW, height: wMLayerH))
        }
        let wMLayer = CALayer()
        wMLayer.frame           = CGRect(x: hPad, y: wMTopPad, width: wMarkW, height: wMLayerH)
        wMLayer.contents        = wMImg.cgImage
        wMLayer.contentsGravity = .topLeft
        wMLayer.masksToBounds   = false
        contentLayer.addSublayer(wMLayer)

        // ── Metric chips ───────────────────────────────────────────────────────
        if !metricChips.isEmpty {
            let chipFontPx: CGFloat = 10 * vScale
            let chipPadH:   CGFloat = 8  * vScale
            let chipPadV:   CGFloat = 4  * vScale
            let chipGap:    CGFloat = 6  * vScale
            let cornerR:    CGFloat = 10 * vScale
            let metricPad:  CGFloat = 14 * vScale
            let chipLineH:  CGFloat = ceil(chipFontPx * 1.6) + chipPadV * 2
            let chipY:      CGFloat = H - safeBot - metricPad - chipLineH
            var chipX:      CGFloat = hPad
            for chip in metricChips {
                let valAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: chipFontPx, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let lblAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: chipFontPx * 0.85, weight: .regular),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.70)
                ]
                let combined = NSMutableAttributedString(
                    attributedString: NSAttributedString(string: chip.value, attributes: valAttrs))
                combined.append(NSAttributedString(string: " \(chip.label)", attributes: lblAttrs))
                let txtSz  = combined.size()
                let chipW  = ceil(txtSz.width)  + chipPadH * 2
                let chipH  = ceil(txtSz.height) + chipPadV * 2
                let chipRenderer = UIGraphicsImageRenderer(
                    size: CGSize(width: chipW, height: chipH), format: imgFormat)
                let chipImg = chipRenderer.image { ctx in
                    let path = UIBezierPath(
                        roundedRect: CGRect(x: 0, y: 0, width: chipW, height: chipH),
                        cornerRadius: cornerR)
                    chip.uiColor.withAlphaComponent(0.30).setFill(); path.fill()
                    chip.uiColor.withAlphaComponent(0.50).setStroke()
                    path.lineWidth = max(1, vScale); path.stroke()
                    combined.draw(in: CGRect(x: chipPadH, y: chipPadV,
                                             width: chipW - chipPadH * 2, height: chipH - chipPadV * 2))
                }
                let chipLayer = CALayer()
                chipLayer.frame           = CGRect(x: chipX, y: chipY, width: chipW, height: chipH)
                chipLayer.contents        = chipImg.cgImage
                chipLayer.contentsGravity = .topLeft
                chipLayer.masksToBounds   = false
                contentLayer.addSublayer(chipLayer)
                chipX += chipW + chipGap
            }
        }

        // ── Date stamp ─────────────────────────────────────────────────────────
        if showDate {
            let df = DateFormatter(); df.dateFormat = "yyyy. M. d."
            let dateStr     = df.string(from: activityDate)
            let dateFontPx: CGFloat = 11 * vScale
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: dateFontPx, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let dateAttrStr = NSAttributedString(string: dateStr, attributes: dateAttrs)
            let dateSz      = dateAttrStr.size()
            let datePad: CGFloat = 14 * vScale
            let dateImgW = ceil(dateSz.width) + 4; let dateImgH = ceil(dateSz.height) + 4
            let dateRenderer = UIGraphicsImageRenderer(
                size: CGSize(width: dateImgW, height: dateImgH), format: imgFormat)
            let dateImg = dateRenderer.image { ctx in
                ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1 * vScale),
                                        blur: 6 * vScale,
                                        color: UIColor.black.withAlphaComponent(0.4).cgColor)
                dateAttrStr.draw(in: CGRect(x: 0, y: 0, width: dateImgW, height: dateImgH))
            }
            let dateLayer = CALayer()
            // 날짜: 워드마크(MIMO RUNNING) 줄 오른쪽 끝에 정렬 → 하단 문구와 겹침 방지
            dateLayer.frame           = CGRect(x: W - hPad - dateImgW,
                                               y: wMTopPad + (wMLayerH - dateImgH) / 2,
                                               width: dateImgW, height: dateImgH)
            dateLayer.contents        = dateImg.cgImage
            dateLayer.contentsGravity = .topLeft
            dateLayer.masksToBounds   = false
            contentLayer.addSublayer(dateLayer)
        }

        // ── Full-video title overlay ───────────────────────────────────────────
        if !videoTitle.isEmpty {
            let tFontPx  = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale * vScale
            let tUIFont  = titleStyle.fontChoice.uiFont(size: tFontPx)
            let tUIColor = titleStyle.textColor.uiColor
            let nsAlign: NSTextAlignment = {
                switch titleStyle.position {
                case .topLeading, .leading, .bottomLeading:    return .left
                case .topTrailing, .trailing, .bottomTrailing: return .right
                default: return .center
                }
            }()
            let pStyle = NSMutableParagraphStyle(); pStyle.alignment = nsAlign
            // 채움 attrs (합성 볼드 포함, 테두리 없을 때만)
            var tAttrs: [NSAttributedString.Key: Any] = [
                .font: tUIFont, .foregroundColor: tUIColor, .paragraphStyle: pStyle
            ]
            if !titleStyle.outline {
                let synStroke = titleStyle.fontChoice.syntheticBoldStroke(for: tFontPx)
                if synStroke != 0 {
                    tAttrs[.strokeWidth] = synStroke
                    tAttrs[.strokeColor] = tUIColor
                }
            }
            // 8방향 테두리 attrs (borderUIColor fill, blur 0, lineJoin=round) — §15.3
            let tBorderOffset: CGFloat = titleStyle.outline ? tFontPx * titleStyle.textColor.borderOffsetFactor : 0
            let tBorderAttrs: [NSAttributedString.Key: Any]? = titleStyle.outline ? [
                .font: tUIFont,
                .foregroundColor: titleStyle.textColor.borderUIColor,
                .paragraphStyle: pStyle
            ] : nil
            let attrStr   = NSAttributedString(string: videoTitle, attributes: tAttrs)
            let bound     = attrStr.boundingRect(with: CGSize(width: textMaxW, height: 4000),
                                                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                  context: nil)
            let tLayerH   = ceil(bound.height) + 20
            let tFrameY: CGFloat = titleStyle.position.isTop
                ? max(wMZoneH + 12 * vScale, safeTop * 0.6)   // 제목 위로: safeTop→0.6배
                : titleStyle.position.isBottom
                    ? H - safeBot - tLayerH
                    : (safeTop + (H - safeBot)) / 2 - tLayerH / 2
            let tRenderer = UIGraphicsImageRenderer(
                size: CGSize(width: textMaxW, height: tLayerH), format: imgFormat)
            let tImg = tRenderer.image { ctx in
                ctx.cgContext.setLineJoin(.round)
                let tRect = CGRect(x: 0, y: 0, width: textMaxW, height: tLayerH)
                if let ba = tBorderAttrs {
                    let bStr = NSAttributedString(string: videoTitle, attributes: ba)
                    let o = tBorderOffset
                    for (ox, oy): (CGFloat, CGFloat) in [(-o,-o),(o,-o),(-o,o),(o,o),(-o,0),(o,0),(0,-o),(0,o)] {
                        bStr.draw(in: tRect.offsetBy(dx: ox, dy: oy))
                    }
                }
                attrStr.draw(in: tRect)
            }
            let titleLayer = CALayer()
            titleLayer.frame           = CGRect(x: hPad, y: tFrameY, width: textMaxW, height: tLayerH)
            titleLayer.contents        = tImg.cgImage
            titleLayer.contentsGravity = .topLeft
            titleLayer.masksToBounds   = false
            titleLayer.opacity         = 0.0
            let fadeEnd = NSNumber(value: min(0.5 / D, 0.99))
            titleLayer.add(linearAnim(keyPath: "opacity",
                                      keyTimes: [0.0, 0.0001, fadeEnd, 1.0],
                                      values:   [Float(0), Float(0), Float(1), Float(1)]),
                           forKey: "titleFade")
            contentLayer.addSublayer(titleLayer)
        }

        return contentLayer
    }

    // MARK: - buildVideoPreviewItem
    //
    // Builds AVMutableComposition (no export) + buildClipTextContentLayer for instant preview.
    // Returns tempURL = nil since no black base video is needed for real video clips.

    static func buildVideoPreviewItem(
        recipes: [ClipRecipe],
        activityDate: Date,
        showDate: Bool,
        muteAudio: Bool = false,
        metricChips: [VideoMetricChip] = [],
        videoTitle: String = "",
        titleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    ) async throws -> (playerItem: AVPlayerItem, layer: CALayer, size: CGSize, duration: Double) {
        guard !recipes.isEmpty else { throw ExportError.compositionFailed }

        let oneLinerSize = CGSize(width: 1080, height: 1920)
        var clipOffsets: [Double] = []
        var offset = 0.0
        for r in recipes { clipOffsets.append(offset); offset += r.trimmedDuration / max(0.1, r.speed) }
        let D = offset

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.compositionFailed }

        // 음소거 ON이면 오디오 트랙 자체를 만들지 않음 — 컴포지션에 어떤 오디오도 안 들어감
        let compAudio: AVMutableCompositionTrack? = muteAudio ? nil :
            composition.addMutableTrack(withMediaType: .audio,
                                        preferredTrackID: kCMPersistentTrackID_Invalid)

        let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        var insertAt    = CMTime.zero
        var clipIdx     = 0
        var audioInserted = 0
        var firstVideoTrack: AVAssetTrack? = nil

        for recipe in recipes {
            // resolvedAsset: 재진입 시 PHImageManager가 해석한 AVAsset(AVComposition 포함) 우선 사용
            let asset: AVAsset = recipe.resolvedAsset ?? AVURLAsset(url: recipe.url)
            let vts   = try await asset.loadTracks(withMediaType: .video)
            guard let vt = vts.first else { clipIdx += 1; continue }
            if firstVideoTrack == nil { firstVideoTrack = vt }

            // 프리뷰: 필믹 재인코딩(preprocessHDRToSDR) 생략 — 원본 트랙 그대로 사용.
            //   · 임시 SDR 파일의 타이밍 불일치로 insertTimeRange가 -11800 던지던 문제 해결
            //   · export 세션 남발 제거 → 재생 빠르고 발열 없음
            //   · HDR→BT.709 톤매핑은 아래 applySDROutputProps의 709 태깅으로 AVFoundation이 처리
            //   (export 경로는 여전히 preprocessHDRToSDR 필믹 파이프라인 사용)
            let effectiveVT: AVAssetTrack = vt

            let natSz  = try await effectiveVT.load(.naturalSize)
            let prefTf = try await effectiveVT.load(.preferredTransform)

            let clipRange = CMTimeRange(
                start:    CMTimeMakeWithSeconds(recipe.trimStart, preferredTimescale: 600),
                duration: CMTimeMakeWithSeconds(recipe.trimmedDuration, preferredTimescale: 600))

            try compVideo.insertTimeRange(clipRange, of: effectiveVT, at: insertAt)

            // 음소거=true이면 compAudio=nil → 조건 자체가 false → 전 클립 오디오 삽입 없음
            // 오디오는 HDR 전처리 불필요 — 원본 asset 사용
            if !muteAudio,
               let ca = compAudio,
               let ats = try? await asset.loadTracks(withMediaType: .audio),
               let at  = ats.first {
                try? ca.insertTimeRange(clipRange, of: at, at: insertAt)
                audioInserted += 1
            }

            let displayRect = CGRect(origin: .zero, size: natSz).applying(prefTf)
            let dw = abs(displayRect.width); let dh = abs(displayRect.height)
            let fillScale = max(oneLinerSize.width / dw, oneLinerSize.height / dh)
            let txOff = (oneLinerSize.width  - dw * fillScale) / 2
            let tyOff = (oneLinerSize.height - dh * fillScale) / 2
            var tf = prefTf
            tf.tx -= displayRect.origin.x; tf.ty -= displayRect.origin.y
            tf = tf.concatenating(CGAffineTransform(scaleX: fillScale, y: fillScale))
            tf = tf.concatenating(CGAffineTransform(translationX: txOff, y: tyOff))
            layerInstr.setTransform(tf, at: insertAt)

            // 배속: 삽입 구간 리타임(출력 길이 = 트림 길이 / speed). 영상·오디오 동시.
            var outDur = clipRange.duration
            if abs(recipe.speed - 1.0) > 0.01 {
                outDur = CMTimeMultiplyByFloat64(clipRange.duration, multiplier: 1.0 / recipe.speed)
                let insertedRange = CMTimeRange(start: insertAt, duration: clipRange.duration)
                compVideo.scaleTimeRange(insertedRange, toDuration: outDur)
                compAudio?.scaleTimeRange(insertedRange, toDuration: outDur)
            }
            insertAt = CMTimeAdd(insertAt, outDur)
            clipIdx += 1
        }

        print("[MultiClip] 미리보기 음소거=\(muteAudio) 삽입오디오=\(audioInserted)개")

        let totalDuration = insertAt
        let vcInstr = AVMutableVideoCompositionInstruction()
        vcInstr.timeRange         = CMTimeRange(start: .zero, duration: totalDuration)
        vcInstr.layerInstructions = [layerInstr]

        let videoComp           = AVMutableVideoComposition()
        videoComp.renderSize    = oneLinerSize
        videoComp.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComp.instructions  = [vcInstr]
        // NO animationTool — live preview uses AVSynchronizedLayer

        // SDR output props: preview uses same BT.709 tone-mapping as export → preview = output.
        if let fTrack = firstVideoTrack {
            await applySDROutputProps(videoComp, track: fTrack)
        }

        let contentLayer = buildClipTextContentLayer(
            recipes: recipes, renderSize: oneLinerSize, totalDuration: D,
            activityDate: activityDate, showDate: showDate, metricChips: metricChips,
            videoTitle: videoTitle, titleStyle: titleStyle)

        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = videoComp

        return (playerItem, contentLayer, oneLinerSize, D)
    }
}
