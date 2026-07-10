import AVFoundation
import UIKit
import CoreGraphics

// MARK: - PhotoSlideComposition
//
// Converts [UIImage] + [ClipRecipe] → 1080×1920 MOV via a single AVAssetExportSession pass.
// Photo CALayers carry Ken Burns + cross-dissolve animations; text/wordmark/date layers
// are added on top using the same discrete-keyframe approach as VideoExportService.
//
// Ken Burns direction alternates to avoid consecutive same movement:
//   even index : scale 1.00→1.08, pan left  →right
//   odd  index : scale 1.08→1.00, pan right →left
//
// buildContentLayer() is shared between export (wrapped in flipped exportParent +
// AVVideoCompositionCoreAnimationTool) and live preview (used directly in AVSynchronizedLayer).

enum PhotoSlideComposition {

    static let photoDuration:    Double = 4.0   // kept for callers; individual clips use recipe.trimmedDuration
    static let maxPhotos:        Int    = 15

    private static let targetSize:       CGSize  = CGSize(width: 1080, height: 1920)
    private static let dissolveDuration: Double  = 0.3
    private static let kbEndScale:       CGFloat = 1.08
    private static let kbPanRange:       CGFloat = 60.0   // px of horizontal travel

    enum SlideError: Error { case noPhotos, writeFailed }

    // MARK: - exportSlideWithText
    //
    // Single-pass: black base video + buildContentLayer() + export.
    // Per-photo duration comes from recipe.trimmedDuration (default 4 s; user can pick 3/4/5 s).

    static func exportSlideWithText(
        photos: [UIImage],
        recipes: [ClipRecipe],
        fontChoice: OneLinerFont,
        textColor: OneLinerTextColor,
        position: CardPosition,
        activityDate: Date,
        showDate: Bool,
        metricChips: [VideoMetricChip] = [],
        videoTitle: String = "",
        titleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    ) async throws -> URL {

        let tStart = Date()
        guard !photos.isEmpty else { throw SlideError.noPhotos }

        let size       = targetSize
        let actualN    = min(photos.count, maxPhotos)
        let imgs       = Array(photos.prefix(actualN)).compactMap { scaleFill($0, to: size) }
        guard !imgs.isEmpty else { throw SlideError.noPhotos }
        let n          = imgs.count
        let useRecipes = Array(recipes.prefix(n))
        let D          = useRecipes.reduce(0.0) { $0 + $1.trimmedDuration }
        print("[Slide] 총\(n)장 D=\(String(format: "%.1f", D))s")
        for (i, r) in useRecipes.enumerated() {
            print("[Slide] 클립\(i): 설정=\(r.fullDuration)s trimStart=\(r.trimStart) trimEnd=\(r.trimEnd) 실제=\(String(format: "%.1f", r.trimmedDuration))s")
        }

        // ── 1. Black base video ─────────────────────────────────────────────────────────
        let baseURL = try await writeBlackBaseVideo(size: size, duration: D)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        // ── 2. Content layer (shared with preview) ──────────────────────────────────────
        var photoOffsets: [Double] = []
        var photoOffset = 0.0
        for r in useRecipes { photoOffsets.append(photoOffset); photoOffset += r.trimmedDuration }

        let contentLayer = buildContentLayer(
            scaledPhotos: imgs, useRecipes: useRecipes, totalDuration: D,
            photoOffsets: photoOffsets, renderSize: size,
            activityDate: activityDate, showDate: showDate, metricChips: metricChips,
            videoTitle: videoTitle, titleStyle: titleStyle)

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: size)
        let exportParent = CALayer()
        exportParent.frame = CGRect(origin: .zero, size: size)
        exportParent.isGeometryFlipped = true
        exportParent.addSublayer(videoLayer)
        exportParent.addSublayer(contentLayer)

        // ── 3. Composition ──────────────────────────────────────────────────────────────
        let bgAsset  = AVURLAsset(url: baseURL)
        let bgTracks = try await bgAsset.loadTracks(withMediaType: .video)
        guard let bgTrack = bgTracks.first else { throw SlideError.writeFailed }
        let bgRange  = try await bgTrack.load(.timeRange)

        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw SlideError.writeFailed }
        try compTrack.insertTimeRange(bgRange, of: bgTrack, at: .zero)

        let vcInstr = AVMutableVideoCompositionInstruction()
        vcInstr.timeRange         = bgRange
        vcInstr.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)]

        let videoComp           = AVMutableVideoComposition()
        videoComp.renderSize    = size
        videoComp.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComp.instructions  = [vcInstr]
        videoComp.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: exportParent)

        // ── 4. Export ───────────────────────────────────────────────────────────────────
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_slide_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHEVCHighestQuality)
        else { throw SlideError.writeFailed }

        session.outputURL        = outputURL
        session.outputFileType   = .mov
        session.videoComposition = videoComp
        session.timeRange        = bgRange

        let exportFlag = AVMutableMetadataItem()
        exportFlag.identifier = .commonIdentifierDescription
        exportFlag.value      = "MIMO_ONELINER_V1" as NSString
        session.metadata      = [exportFlag]

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed: cont.resume()
                case .failed:    cont.resume(throwing: session.error ?? SlideError.writeFailed)
                case .cancelled: cont.resume(throwing: SlideError.writeFailed)
                default:         cont.resume(throwing: SlideError.writeFailed)
                }
            }
        }

        let elapsed = Date().timeIntervalSince(tStart)
        print("[MultiClip] type=photo 사진수=\(n) 합산=\(Int(D))초 합성시간=\(String(format: "%.2f", elapsed))s")

        return outputURL
    }

    // MARK: - buildPreviewItem
    //
    // Builds an AVPlayerItem (black base) + the same contentLayer used by export.
    // Returns tempURL so caller can delete the base video file when done.
    // The contentLayer goes directly into AVSynchronizedLayer (no isGeometryFlipped needed).

    static func buildPreviewItem(
        photos: [UIImage],
        recipes: [ClipRecipe],
        activityDate: Date,
        showDate: Bool,
        metricChips: [VideoMetricChip] = [],
        videoTitle: String = "",
        titleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    ) async throws -> (playerItem: AVPlayerItem, layer: CALayer, size: CGSize,
                       duration: Double, tempURL: URL) {
        guard !photos.isEmpty else { throw SlideError.noPhotos }

        let size       = targetSize
        let n          = min(photos.count, maxPhotos)
        let imgs       = Array(photos.prefix(n)).compactMap { scaleFill($0, to: size) }
        guard !imgs.isEmpty else { throw SlideError.noPhotos }
        let useRecipes = Array(recipes.prefix(imgs.count))
        let D          = useRecipes.reduce(0.0) { $0 + $1.trimmedDuration }

        var photoOffsets: [Double] = []
        var photoOffset = 0.0
        for r in useRecipes { photoOffsets.append(photoOffset); photoOffset += r.trimmedDuration }

        let contentLayer = buildContentLayer(
            scaledPhotos: imgs, useRecipes: useRecipes, totalDuration: D,
            photoOffsets: photoOffsets, renderSize: size,
            activityDate: activityDate, showDate: showDate, metricChips: metricChips,
            videoTitle: videoTitle, titleStyle: titleStyle)

        let baseURL = try await writeBlackBaseVideo(size: size, duration: D)

        let bgAsset  = AVURLAsset(url: baseURL)
        let bgTracks = try await bgAsset.loadTracks(withMediaType: .video)
        guard let bgTrack = bgTracks.first else {
            try? FileManager.default.removeItem(at: baseURL)
            throw SlideError.writeFailed
        }
        let bgRange = try await bgTrack.load(.timeRange)

        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            try? FileManager.default.removeItem(at: baseURL)
            throw SlideError.writeFailed
        }
        try compTrack.insertTimeRange(bgRange, of: bgTrack, at: .zero)

        let vcInstr = AVMutableVideoCompositionInstruction()
        vcInstr.timeRange         = bgRange
        vcInstr.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)]

        let videoComp           = AVMutableVideoComposition()
        videoComp.renderSize    = size
        videoComp.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComp.instructions  = [vcInstr]
        // NO animationTool — live preview uses AVSynchronizedLayer

        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = videoComp

        return (playerItem, contentLayer, size, D, baseURL)
    }

    // MARK: - buildContentLayer (shared: export + preview)
    //
    // Builds the full CALayer hierarchy WITHOUT isGeometryFlipped.
    // Export: caller wraps in a flipped exportParent + videoLayer.
    // Preview: caller attaches directly to AVSynchronizedLayer.
    //
    // Per-photo timing uses photoOffsets[] + recipe.trimmedDuration so variable
    // durations (3 s / 4 s / 5 s) are handled correctly.

    static func buildContentLayer(
        scaledPhotos: [CGImage],
        useRecipes: [ClipRecipe],
        totalDuration D: Double,
        photoOffsets: [Double],
        renderSize: CGSize,
        activityDate: Date,
        showDate: Bool,
        metricChips: [VideoMetricChip] = [],
        videoTitle: String = "",
        titleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    ) -> CALayer {
        let size = renderSize
        let W    = size.width
        let H    = size.height
        let n    = scaledPhotos.count

        let vScale: CGFloat   = W / 300.0
        let safeTop: CGFloat  = CardVisual.videoSafeTop
        let safeBot: CGFloat  = CardVisual.videoSafeBottom
        let hPad: CGFloat     = 24 * vScale
        let wMTopPad: CGFloat = 12 * vScale
        let wMFontPx: CGFloat = 9  * vScale
        let wMZoneH: CGFloat  = wMTopPad + ceil(wMFontPx * 1.5) + 6 * vScale
        let textMaxW: CGFloat = W - 2 * hPad
        let shadowOffX = 1 * vScale; let shadowOffY = 2 * vScale; let shadowBlur = 5 * vScale
        let imgFormat   = UIGraphicsImageRendererFormat()
        imgFormat.scale = 1.0; imgFormat.opaque = false
        let cursorW: CGFloat = max(3.0, vScale * 0.8)

        let contentLayer = CALayer()
        contentLayer.frame = CGRect(origin: .zero, size: size)

        func linearAnim(_ keyPath: String, keyTimes: [NSNumber], values: [Any]) -> CAKeyframeAnimation {
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
        func discreteAnim(_ keyPath: String, keyTimes: [NSNumber], values: [Any]) -> CAKeyframeAnimation {
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

        // ── Photo layers (Ken Burns + cross-dissolve) ──────────────────────────────────
        for i in 0..<n {
            let photoStart  = photoOffsets[i]
            let photoDurI   = useRecipes[i].trimmedDuration
            let photoEnd    = photoStart + photoDurI
            let isLastPhoto = i == n - 1
            let sf          = photoStart / D
            let ef          = photoEnd   / D

            let photoLayer = CALayer()
            photoLayer.frame           = CGRect(origin: .zero, size: size)
            photoLayer.contents        = scaledPhotos[i]
            photoLayer.contentsGravity = .resize

            let (startScale, startPanX) = kenBurns(idx: i, progress: 0.0)
            let (endScale,   endPanX)   = kenBurns(idx: i, progress: 1.0)

            let scKeyTimes: [NSNumber] = [NSNumber(value: sf), NSNumber(value: ef), 1.0]
            photoLayer.add(
                linearAnim("transform.scale",
                           keyTimes: scKeyTimes,
                           values: [NSNumber(value: Float(startScale)),
                                    NSNumber(value: Float(endScale)),
                                    NSNumber(value: Float(endScale))]),
                forKey: "kbScale")

            let cx = W / 2; let cy = H / 2
            photoLayer.add(
                linearAnim("position",
                           keyTimes: scKeyTimes,
                           values: [NSValue(cgPoint: CGPoint(x: cx + startPanX, y: cy)),
                                    NSValue(cgPoint: CGPoint(x: cx + endPanX,   y: cy)),
                                    NSValue(cgPoint: CGPoint(x: cx + endPanX,   y: cy))]),
                forKey: "kbPos")

            let opKeyTimes: [NSNumber]
            let opValues:   [Float]
            if i == 0 {
                if isLastPhoto {
                    opKeyTimes = [0.0, 1.0]; opValues = [1.0, 1.0]
                } else {
                    let fosFrac = (photoEnd - dissolveDuration) / D
                    let foeFrac = photoEnd / D
                    opKeyTimes = [0.0, NSNumber(value: fosFrac), NSNumber(value: foeFrac), 1.0]
                    opValues   = [1.0, 1.0, 0.0, 0.0]
                }
            } else {
                let fisFrac = max((photoStart - dissolveDuration) / D, 0.0)
                let fieFrac = photoStart / D
                if isLastPhoto {
                    opKeyTimes = [0.0, NSNumber(value: fisFrac), NSNumber(value: fieFrac), 1.0]
                    opValues   = [0.0, 0.0, 1.0, 1.0]
                } else {
                    let fosFrac = (photoEnd - dissolveDuration) / D
                    let foeFrac = photoEnd / D
                    opKeyTimes = [0.0, NSNumber(value: fisFrac), NSNumber(value: fieFrac),
                                  NSNumber(value: fosFrac), NSNumber(value: foeFrac), 1.0]
                    opValues   = [0.0, 0.0, 1.0, 1.0, 0.0, 0.0]
                }
            }
            photoLayer.add(linearAnim("opacity", keyTimes: opKeyTimes, values: opValues),
                           forKey: "opacity")
            contentLayer.addSublayer(photoLayer)
        }

        // ── Text overlay ───────────────────────────────────────────────────────────────
        var clipOffsets: [Double] = []
        var runningOffset = 0.0
        for recipe in useRecipes { clipOffsets.append(runningOffset); runningOffset += recipe.trimmedDuration }
        var lastTextClipIdx = -1
        for (i, r) in useRecipes.enumerated() { if r.hasText { lastTextClipIdx = i } }

        struct PageSpec {
            let text: String; let winStart: Double; let winEnd: Double; let isLast: Bool
            let clipIdx: Int
        }
        var pageSpecs: [PageSpec] = []
        for (clipIdx, recipe) in useRecipes.enumerated() {
            let clipStart = clipOffsets[clipIdx]
            let clipEnd   = clipStart + recipe.trimmedDuration
            // 3 s photo clips: only use first slot (second slot is preserved in recipe.lines but not shown)
            let effectiveLines = recipe.trimmedDuration < 3.5
                ? Array(recipe.lines.prefix(1))
                : recipe.lines
            let nonEmpty = effectiveLines.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard !nonEmpty.isEmpty else { continue }
            let clipPages  = stride(from: 0, to: nonEmpty.count, by: 2).map { i in
                Array(nonEmpty[i..<min(i + 2, nonEmpty.count)])
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

        let startDelay: Double = 0.20
        let holdTime:   Double = 0.40
        let fadeTime:   Double = 0.25

        for page in pageSpecs {
            let chars     = Array(page.text)
            let N         = chars.count
            let windowDur = page.winEnd - page.winStart

            let clip        = page.clipIdx < useRecipes.count ? useRecipes[page.clipIdx] : useRecipes[0]
            let fontSize    = 20.0 * clip.fontChoice.sizeScale * clip.sizeLevel.scale * vScale
            let lineSpacing = fontSize * 0.1
            let uiFont      = clip.fontChoice.uiFont(size: fontSize)
            let lineH       = uiFont.lineHeight + lineSpacing
            let nsAlign: NSTextAlignment = {
                switch clip.position {
                case .topLeading, .leading, .bottomLeading:    return .left
                case .topTrailing, .trailing, .bottomTrailing: return .right
                default: return .center
                }
            }()
            let pStyle = NSMutableParagraphStyle()
            pStyle.lineSpacing = lineSpacing
            pStyle.alignment   = nsAlign
            let textUIColor = clip.textColor.uiColor
            var textAttrs: [NSAttributedString.Key: Any] = [
                .font: uiFont, .foregroundColor: textUIColor, .paragraphStyle: pStyle
            ]
            if clip.outline {
                textAttrs[.strokeWidth] = CGFloat(-1.8)
                textAttrs[.strokeColor] = UIColor.black.withAlphaComponent(0.6)
            } else {
                textAttrs[.strokeWidth] = CGFloat(-3.5)
                textAttrs[.strokeColor] = textUIColor
            }
            let cursorH: CGFloat = ceil(uiFont.capHeight + abs(uiFont.descender)) + 2
            func measureLastLine(_ s: String) -> CGFloat {
                let ls = s.split(separator: "\n", omittingEmptySubsequences: false)
                guard let last = ls.last, !last.isEmpty else { return 0 }
                return ceil(NSAttributedString(string: String(last), attributes: [.font: uiFont]).size().width)
            }

            // ── 타임라인 계산 ──────────────────────────────────────────────────
            let isFade = clip.appearanceMode == .fade
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
            // 페이드: 완성 이미지 1장(index 0=full). 타이핑: N+1장(0=공백, 1…N=누적).
            let renderRange = isFade ? [N] : Array(0...N)
            var charImages: [CGImage] = []
            for k in renderRange {
                let cgImg = imgRenderer.image { ctx in
                    guard k > 0 else { return }
                    ctx.cgContext.setShadow(offset: CGSize(width: shadowOffX, height: shadowOffY),
                                            blur: shadowBlur,
                                            color: UIColor.black.withAlphaComponent(0.55).cgColor)
                    NSAttributedString(string: String(chars.prefix(k)), attributes: textAttrs)
                        .draw(in: CGRect(x: 0, y: 0, width: textMaxW, height: textLayerH))
                }.cgImage
                charImages.append(cgImg ?? fallbackImg)
            }

            let pageLayer = CALayer()
            pageLayer.frame   = CGRect(origin: .zero, size: size)
            pageLayer.opacity = 0.0

            let opAppear = max(0.0, min((page.winStart + 0.05) / D, 1.0))
            let pgKeyTimes: [NSNumber]
            let pgValues:   [Float]
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
            pageLayer.add(discreteAnim("opacity", keyTimes: pgKeyTimes, values: pgValues),
                          forKey: "opacity")

            if N > 0 {
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
                    textLayer.add(linearAnim("opacity",
                                             keyTimes: [0.0, NSNumber(value: tiS), NSNumber(value: tiE), 1.0],
                                             values:   [Float(0), Float(0), Float(1), Float(1)]),
                                  forKey: "textFade")
                    // 팝: 페이드 완료 직후 1회 1.2→1.0 스프링
                    if clip.decorEffect == .pop {
                        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
                        pop.values          = [1.2, 1.08, 0.96, 1.02, 1.0]
                        pop.keyTimes        = [0.0, 0.3,  0.6,  0.82, 1.0] as [NSNumber]
                        pop.duration        = 0.42
                        pop.beginTime       = AVCoreAnimationBeginTimeAtZero + appearEnd
                        pop.fillMode        = .both
                        pop.isRemovedOnCompletion = false
                        pop.calculationMode = .linear
                        textLayer.add(pop, forKey: "pop")
                    }
                    // 흔들림
                    if clip.decorEffect == .wobble {
                        let wob = CAKeyframeAnimation(keyPath: "transform.rotation.z")
                        wob.values           = [0.0, 0.014, 0.0, -0.014, 0.0]  // ±0.8°
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
                    textLayer.add(discreteAnim("contents", keyTimes: cKeyTimes, values: cValues),
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
                    cursorLayer.add(discreteAnim("position", keyTimes: pKeyTimes, values: pValues),
                                    forKey: "position")

                    let cursorStartFrac = max(0.0001, (page.winStart + startDelay) / D)
                    let cursorEndFrac   = min(appearEnd / D, 1.0)
                    var blinkKeyTimes: [NSNumber] = [0.0, NSNumber(value: cursorStartFrac)]
                    var blinkValues:   [Float]    = [0.0, 1.0]
                    var bt = page.winStart + startDelay + 0.25
                    var blinkOn = false
                    while bt < appearEnd && bt / D < 1.0 {
                        blinkKeyTimes.append(NSNumber(value: bt / D))
                        blinkValues.append(blinkOn ? 1.0 : 0.0)
                        bt += 0.25; blinkOn.toggle()
                    }
                    let safeEnd = max((blinkKeyTimes.last?.doubleValue ?? 0.0) + 0.0001, cursorEndFrac)
                    blinkKeyTimes.append(NSNumber(value: min(safeEnd, 1.0))); blinkValues.append(0.0)
                    blinkKeyTimes.append(1.0); blinkValues.append(0.0)
                    cursorLayer.add(discreteAnim("opacity", keyTimes: blinkKeyTimes, values: blinkValues),
                                    forKey: "opacity")
                    pageLayer.addSublayer(cursorLayer)
                }
            }
            contentLayer.addSublayer(pageLayer)
        }

        // ── Wordmark ───────────────────────────────────────────────────────────────────
        let wMLayerH  = ceil(wMFontPx * 1.5)
        let wMarkW    = W - 2 * hPad
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

        // ── Metric chips ───────────────────────────────────────────────────────────────
        if !metricChips.isEmpty {
            let chipFontPx: CGFloat = 10 * vScale
            let chipPadH:   CGFloat = 8  * vScale
            let chipPadV:   CGFloat = 4  * vScale
            let chipGap:    CGFloat = 6  * vScale
            let cornerR:    CGFloat = 10 * vScale
            let metricPad:  CGFloat = 14 * vScale
            let chipLineH:  CGFloat = ceil(chipFontPx * 1.6) + chipPadV * 2
            let chipY: CGFloat      = H - safeBot - metricPad - chipLineH
            var chipX: CGFloat      = hPad
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

        // ── Full-video title overlay ───────────────────────────────────────────────────
        if !videoTitle.isEmpty {
            let tFontPx  = 20.0 * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale * vScale
            let tUIFont  = titleStyle.fontChoice.uiFont(size: tFontPx)
            let tUIColor = titleStyle.textColor.uiColor
            let pStyle2  = NSMutableParagraphStyle()
            pStyle2.alignment = .center
            var tAttrs: [NSAttributedString.Key: Any] = [
                .font: tUIFont, .foregroundColor: tUIColor, .paragraphStyle: pStyle2
            ]
            if titleStyle.outline {
                tAttrs[.strokeWidth] = CGFloat(-1.8)
                tAttrs[.strokeColor] = UIColor.black.withAlphaComponent(0.6)
            }
            let tAttrStr  = NSAttributedString(string: videoTitle, attributes: tAttrs)
            let tBounds   = tAttrStr.boundingRect(
                with: CGSize(width: textMaxW, height: 4000),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            let tLayerH   = ceil(tBounds.height) + 20
            let tFrameY: CGFloat = titleStyle.position.isTop
                ? max(wMZoneH + 4 * vScale, safeTop + 4 * vScale)
                : titleStyle.position.isBottom
                    ? H - safeBot - tLayerH
                    : (safeTop + (H - safeBot)) / 2 - tLayerH / 2
            let tRenderer = UIGraphicsImageRenderer(
                size: CGSize(width: textMaxW, height: tLayerH), format: imgFormat)
            let tImg = tRenderer.image { ctx in
                ctx.cgContext.setShadow(
                    offset: CGSize(width: shadowOffX, height: shadowOffY),
                    blur: shadowBlur,
                    color: UIColor.black.withAlphaComponent(0.55).cgColor)
                tAttrStr.draw(in: CGRect(x: 0, y: 0, width: textMaxW, height: tLayerH))
            }
            let titleLayer = CALayer()
            titleLayer.frame           = CGRect(x: hPad, y: tFrameY, width: textMaxW, height: tLayerH)
            titleLayer.contents        = tImg.cgImage
            titleLayer.contentsGravity = .topLeft
            titleLayer.masksToBounds   = false
            titleLayer.opacity         = 0.0
            let fadeEnd = NSNumber(value: min(0.5 / D, 0.99))
            titleLayer.add(linearAnim("opacity",
                                      keyTimes: [0.0, 0.0001, fadeEnd, 1.0],
                                      values:   [Float(0), Float(0), Float(1), Float(1)]),
                           forKey: "titleFade")
            contentLayer.addSublayer(titleLayer)
        }

        // ── Date stamp ─────────────────────────────────────────────────────────────────
        if showDate {
            let df = DateFormatter()
            df.dateFormat = "yyyy. M. d."
            let dateStr     = df.string(from: activityDate)
            let dateFontPx: CGFloat = 11 * vScale
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: dateFontPx, weight: .light),
                .foregroundColor: UIColor.white.withAlphaComponent(0.55)
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
            dateLayer.frame           = CGRect(x: W - datePad - dateImgW,
                                               y: H - safeBot - datePad - dateImgH,
                                               width: dateImgW, height: dateImgH)
            dateLayer.contents        = dateImg.cgImage
            dateLayer.contentsGravity = .topLeft
            dateLayer.masksToBounds   = false
            contentLayer.addSublayer(dateLayer)
        }

        return contentLayer
    }

    // MARK: - writeBlackBaseVideo

    static func writeBlackBaseVideo(size: CGSize, duration: Double) async throws -> URL {
        let fps: Int32 = 30
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_slidebg_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                  kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let buf = pb else { throw SlideError.writeFailed }

        CVPixelBufferLockBaseAddress(buf, [])
        if let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buf),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) {
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        CVPixelBufferUnlockBaseAddress(buf, [])

        let frameCount = Int(ceil(duration * Double(fps)))
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input  = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 0.85]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for i in 0..<frameCount {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
        }
        input.markAsFinished()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? SlideError.writeFailed
        }
        return url
    }

    // MARK: - Ken Burns

    private static func kenBurns(idx: Int, progress: Double) -> (scale: CGFloat, panX: CGFloat) {
        let p = CGFloat(progress)
        if idx % 2 == 0 {
            return (1.0 + (kbEndScale - 1.0) * p, -kbPanRange / 2 + kbPanRange * p)
        } else {
            return (kbEndScale - (kbEndScale - 1.0) * p, kbPanRange / 2 - kbPanRange * p)
        }
    }

    // MARK: - Scale-fill helper

    static func scaleFill(_ image: UIImage, to size: CGSize) -> CGImage? {
        let s  = max(size.width / image.size.width, size.height / image.size.height)
        let sw = image.size.width  * s
        let sh = image.size.height * s
        let ox = (size.width  - sw) / 2
        let oy = (size.height - sh) / 2
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(x: ox, y: oy, width: sw, height: sh))
        }.cgImage
    }
}
