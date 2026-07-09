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

    static func duration(of url: URL) async -> Double {
        (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
    }

    // MARK: Export (static overlay)

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

        // Slight brightness boost on the video layer.
        let brightenLayer              = CALayer()
        brightenLayer.frame            = CGRect(origin: .zero, size: targetSize)
        brightenLayer.backgroundColor  = UIColor.white.cgColor
        brightenLayer.opacity          = CardVisual.videoBrightenLayerOpacity

        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(brightenLayer)
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
        muteAudio: Bool = false
    ) async throws -> URL {

        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw ExportError.noVideoTrack }

        let assetDuration      = try await asset.load(.duration)
        let naturalSize        = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let audioTracks        = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

        // ── 1. Timing ────────────────────────────────────────────────────────
        let trimEnd   = min(CMTimeGetSeconds(assetDuration), trimDuration)
        let timeRange = CMTimeRange(start: .zero,
                                    duration: CMTimeMakeWithSeconds(trimEnd, preferredTimescale: 600))
        let D = trimEnd

        let chars = Array(text)
        let N     = chars.count

        var durs: [Double] = chars.map { $0.isWhitespace ? 0.08 : 0.20 }
        let baseTotal = durs.reduce(0, +)
        let startDelay: Double = 0.8
        let endMargin:  Double = 1.0

        if N > 0 && D < startDelay + baseTotal + endMargin {
            let factor = max(0.02, (D - startDelay - endMargin) / baseTotal)
            durs = durs.map { $0 * factor }
        }

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

        let fontSize:    CGFloat = 20.0 * fontChoice.sizeScale * vScale
        let lineSpacing: CGFloat = fontSize * 0.4
        let uiFont = UIFont(name: fontChoice.fontName, size: fontSize)
                     ?? UIFont.systemFont(ofSize: fontSize)
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

        let shadowOffX = 1 * vScale
        let shadowOffY = 2 * vScale
        let shadowBlur = 5 * vScale

        var textCGImages: [CGImage] = []
        for k in 0...N {
            let cgImg = imgRenderer.image { ctx in
                guard k > 0 else { return }
                let ctxCG = ctx.cgContext
                ctxCG.setShadow(offset: CGSize(width: shadowOffX, height: shadowOffY),
                                blur: shadowBlur,
                                color: UIColor.black.withAlphaComponent(0.55).cgColor)
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

        let brightenLayer = CALayer()
        brightenLayer.frame           = CGRect(origin: .zero, size: oneLinerSize)
        brightenLayer.backgroundColor = UIColor.white.cgColor
        brightenLayer.opacity         = CardVisual.videoBrightenLayerOpacity

        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(brightenLayer)

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
                .font: UIFont.systemFont(ofSize: dateFontPx, weight: .light),
                .foregroundColor: UIColor.white.withAlphaComponent(0.55)
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
            dateLayer.frame           = CGRect(x: W - datePad - dateImgW,
                                               y: H - safeBottom - datePad - dateImgH,
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
        muteAudio: Bool = false
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

        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw ExportError.noVideoTrack }

        let assetDuration      = try await asset.load(.duration)
        let naturalSize        = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let audioTracks        = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

        let trimEnd   = min(CMTimeGetSeconds(assetDuration), trimDuration)
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

        let fontSize:    CGFloat = 20.0 * fontChoice.sizeScale * vScale
        let lineSpacing: CGFloat = fontSize * 0.4
        let uiFont = UIFont(name: fontChoice.fontName, size: fontSize)
                     ?? UIFont.systemFont(ofSize: fontSize)
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

        let shadowOffX = 1 * vScale
        let shadowOffY = 2 * vScale
        let shadowBlur = 5 * vScale

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

        let brightenLayer = CALayer()
        brightenLayer.frame           = CGRect(origin: .zero, size: oneLinerSize)
        brightenLayer.backgroundColor = UIColor.white.cgColor
        brightenLayer.opacity         = CardVisual.videoBrightenLayerOpacity

        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(brightenLayer)

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

            // Scale char timing to fit within page budget
            var rawDurs: [Double] = chars.map { $0.isNewline ? 0.30 : ($0.isWhitespace ? 0.08 : 0.20) }
            let rawTotal = rawDurs.reduce(0.0, +)
            let budget   = max(0.1, timePerPage - startDelay - holdTime - (isLastPage ? 0 : fadeTime))
            if rawTotal > budget && rawTotal > 0 {
                let factor = max(0.02, budget / rawTotal)
                rawDurs = rawDurs.map { $0 * factor }
            }

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
                    ctx.cgContext.setShadow(offset: CGSize(width: shadowOffX, height: shadowOffY),
                                           blur: shadowBlur,
                                           color: UIColor.black.withAlphaComponent(0.55).cgColor)
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
                .font: UIFont.systemFont(ofSize: dateFontPx, weight: .light),
                .foregroundColor: UIColor.white.withAlphaComponent(0.55)
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
            dateLayer.frame           = CGRect(x: W - datePad - dateImgW,
                                               y: H - safeBottom - datePad - dateImgH,
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
}
