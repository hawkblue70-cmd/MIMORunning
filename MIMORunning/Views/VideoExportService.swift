import AVFoundation
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreLocation

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
    }

    /// Stamps BT.2020 + HLG HDR output properties on `vc`.
    /// animationTool이 이 설정을 지원하는지 실험적 경로 — 성공 시 HDR 출력, 실패 시 export 에러.
    private static func applyHDROutputProps(_ vc: AVMutableVideoComposition) {
        vc.colorPrimaries        = AVVideoColorPrimaries_ITU_R_2020
        vc.colorTransferFunction = AVVideoTransferFunction_ITU_R_2100_HLG
        vc.colorYCbCrMatrix      = AVVideoYCbCrMatrix_ITU_R_2020
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

    static func frame(of url: URL, at time: Double) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        generator.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.3, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTimeMakeWithSeconds(0.3, preferredTimescale: 600)
        let t = CMTimeMakeWithSeconds(max(0.1, time), preferredTimescale: 600)
        return await withCheckedContinuation { cont in
            generator.generateCGImageAsynchronously(for: t) { img, _, _ in
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

    // MARK: Concatenate clips (overlay 없이 연결만) — Placeable 멀티클립 전처리
    static func concatenateClipsRaw(recipes: [ClipRecipe]) async throws -> URL {
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.compositionFailed }
        let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var insertTime = CMTime.zero
        for r in recipes {
            // URL 해석: 임시파일 → resolvedAsset → assetIdentifier 재해석
            var resolvedURL: URL = r.url
            if !FileManager.default.fileExists(atPath: r.url.path) {
                if let urlAsset = r.resolvedAsset as? AVURLAsset {
                    resolvedURL = urlAsset.url
                } else if let assetID = r.assetIdentifier,
                          let resolved = try? await MultiClipComposition.resolveAVAsset(assetID: assetID),
                          let urlAsset = resolved as? AVURLAsset {
                    resolvedURL = urlAsset.url
                } else {
                    continue
                }
            }
            let asset  = AVURLAsset(url: resolvedURL)
            guard let vt = try? await asset.loadTracks(withMediaType: .video).first else { continue }
            let dur    = (try? await asset.load(.duration)) ?? .zero
            let start  = CMTime(seconds: r.trimStart, preferredTimescale: 600)
            let end    = CMTime(seconds: min(r.trimEnd, dur.seconds), preferredTimescale: 600)
            let range  = CMTimeRange(start: start, end: end)
            try compVideo.insertTimeRange(range, of: vt, at: insertTime)
            if let at = try? await asset.loadTracks(withMediaType: .audio).first {
                try? compAudio?.insertTimeRange(range, of: at, at: insertTime)
            }
            insertTime = CMTimeAdd(insertTime, CMTimeSubtract(end, start))
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("placeable_concat_\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw ExportError.sessionFailed }
        session.outputURL      = outURL
        session.outputFileType = .mp4
        await session.export()
        if let err = session.error { throw err }
        return outURL
    }

    /// In-memory concatenated AVPlayerItem from multiple clips with per-clip preferredTransform.
    /// No file export — used for Placeable multi-clip preview only.
    static func buildConcatenatedPreviewItem(recipes: [ClipRecipe]) async throws -> (playerItem: AVPlayerItem, duration: Double) {
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.compositionFailed }
        let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        var insertTime = CMTime.zero

        for r in recipes {
            var resolvedURL: URL = r.url
            if !FileManager.default.fileExists(atPath: r.url.path) {
                if let ua = r.resolvedAsset as? AVURLAsset {
                    resolvedURL = ua.url
                } else if let assetID = r.assetIdentifier,
                          let resolved = try? await MultiClipComposition.resolveAVAsset(assetID: assetID),
                          let ua = resolved as? AVURLAsset {
                    resolvedURL = ua.url
                } else {
                    continue
                }
            }

            let asset = AVURLAsset(url: resolvedURL)
            guard let vt = try? await asset.loadTracks(withMediaType: .video).first else { continue }
            let dur      = (try? await asset.load(.duration)) ?? .zero
            let clipStart = CMTime(seconds: max(0, r.trimStart), preferredTimescale: 600)
            let clipEnd   = CMTime(seconds: min(r.trimEnd, dur.seconds), preferredTimescale: 600)
            guard clipEnd > clipStart else { continue }
            let srcRange  = CMTimeRange(start: clipStart, end: clipEnd)
            let clipDur   = CMTimeSubtract(clipEnd, clipStart)
            let spVal     = max(0.1, r.speed)
            let scaledDur = abs(spVal - 1.0) > 0.01
                ? CMTimeMultiplyByFloat64(clipDur, multiplier: 1.0 / spVal)
                : clipDur

            try compVideo.insertTimeRange(srcRange, of: vt, at: insertTime)
            if let at = try? await asset.loadTracks(withMediaType: .audio).first {
                try? compAudio?.insertTimeRange(srcRange, of: at, at: insertTime)
            }

            // 배속 적용 (scaleTimeRange: 삽입 직후, transform 설정 전)
            if abs(spVal - 1.0) > 0.01 {
                let insertedRange = CMTimeRange(start: insertTime, duration: clipDur)
                compVideo.scaleTimeRange(insertedRange, toDuration: scaledDur)
                compAudio?.scaleTimeRange(insertedRange, toDuration: scaledDur)
            }

            // Per-clip preferredTransform → fill 1080×1920
            let naturalSize        = (try? await vt.load(.naturalSize)) ?? .zero
            let preferredTransform = (try? await vt.load(.preferredTransform)) ?? .identity
            let transformedRect    = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
            let displayW = abs(transformedRect.width)
            let displayH = abs(transformedRect.height)
            if displayW > 0, displayH > 0 {
                let fillScale = max(targetSize.width / displayW, targetSize.height / displayH)
                let txOff = (targetSize.width  - displayW * fillScale) / 2
                let tyOff = (targetSize.height - displayH * fillScale) / 2
                var t = preferredTransform
                t.tx -= transformedRect.origin.x
                t.ty -= transformedRect.origin.y
                t = t.concatenating(CGAffineTransform(scaleX: fillScale, y: fillScale))
                t = t.concatenating(CGAffineTransform(translationX: txOff, y: tyOff))
                layerInstruction.setTransform(t, at: insertTime)
            }
            insertTime = CMTimeAdd(insertTime, scaledDur)
        }

        guard CMTimeGetSeconds(insertTime) > 0 else { throw ExportError.compositionFailed }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange         = CMTimeRange(start: .zero, duration: insertTime)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition           = AVMutableVideoComposition()
        videoComposition.renderSize    = targetSize
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComposition.instructions  = [instruction]

        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = videoComposition
        return (playerItem: playerItem, duration: CMTimeGetSeconds(insertTime))
    }

    // MARK: Export (static overlay)

    /// Trims a single clip to trimStart…trimEnd and composites a static overlay.
    /// Used for Placeable per-clip export where each clip carries its own text.
    ///
    /// HDR 소스(iPhone 15+ Dolby Vision/HLG) 처리 방식:
    ///   · SDR 소스 → 기존 필믹 파이프라인(preprocessHDRToSDR) → BT.709 SDR 출력.
    ///   · HDR 소스 → preprocessHDRToSDR 생략, AVFoundation 내장 HDR→BT.709 톤매핑 사용.
    ///     프리뷰(buildConcatenatedPreviewItem)도 동일 경로를 사용하므로 출력이 프리뷰 밝기와 근접.
    ///     animationTool 오버레이 합성은 sRGB 공간에서 처리되나(CALayer 제약),
    ///     텍스트·로고는 반투명 오버레이이므로 시각적으로 허용 범위.
    static func exportClipWithOverlay(sourceURL: URL, overlay: UIImage,
                                      trimStart: Double, trimEnd: Double,
                                      muteAudio: Bool = false,
                                      speed: Double = 1.0,
                                      brightenHDR: Bool = false,
                                      outputHDR: Bool = false) async throws -> URL {
        let rawAsset  = AVURLAsset(url: sourceURL)
        let rawTracks = try await rawAsset.loadTracks(withMediaType: .video)
        guard let rawVideoTrack = rawTracks.first else { throw ExportError.noVideoTrack }
        let sourceIsHDR = await isHDRSource(track: rawVideoTrack)

        // outputHDR + HDR source: 원본 HDR 유지, BT.2020+HLG 속성으로 출력 시도 (experimental)
        // SDR source: preprocessHDRToSDR 내부 guard에서 즉시 반환 (처리 없음)
        // HDR + brightenHDR=true: 필믹 S-커브 파이프라인 적용 → 밝은 SDR 출력
        // HDR + brightenHDR=false: 원본 HDR → applySDROutputProps BT.709 톤매핑 (기본)
        let preparedURL: URL
        if outputHDR && sourceIsHDR {
            preparedURL = sourceURL  // HDR 원본 그대로 유지
        } else {
            preparedURL = (!sourceIsHDR || brightenHDR)
                ? try await preprocessHDRToSDR(url: sourceURL)
                : sourceURL
        }
        let asset       = AVURLAsset(url: preparedURL)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw ExportError.noVideoTrack }

        let assetDur  = CMTimeGetSeconds(try await asset.load(.duration))
        let start     = CMTime(seconds: max(0, trimStart), preferredTimescale: 600)
        let end       = CMTime(seconds: min(trimEnd, assetDur), preferredTimescale: 600)
        let srcRange   = CMTimeRange(start: start, end: end)           // asset timeline
        let compDur    = CMTimeSubtract(end, start)
        let spVal      = max(0.1, speed)
        let scaledDur  = abs(spVal - 1.0) > 0.01
            ? CMTimeMultiplyByFloat64(compDur, multiplier: 1.0 / spVal)
            : compDur
        let compRange  = CMTimeRange(start: .zero, duration: scaledDur)  // 배속 적용된 composition timeline

        let naturalSize        = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedRect    = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displayWidth       = abs(transformedRect.width)
        let displayHeight      = abs(transformedRect.height)
        let scaleX             = targetSize.width  / displayWidth
        let scaleY             = targetSize.height / displayHeight
        let fillScale          = max(scaleX, scaleY)
        let txOffset           = (targetSize.width  - displayWidth  * fillScale) / 2
        let tyOffset           = (targetSize.height - displayHeight * fillScale) / 2

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.compositionFailed }
        try compVideo.insertTimeRange(srcRange, of: videoTrack, at: .zero)
        if abs(spVal - 1.0) > 0.01 {
            compVideo.scaleTimeRange(CMTimeRange(start: .zero, duration: compDur), toDuration: scaledDur)
        }
        if !muteAudio,
           let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
           let audioTrack  = audioTracks.first,
           let compAudio   = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compAudio.insertTimeRange(srcRange, of: audioTrack, at: .zero)
            if abs(spVal - 1.0) > 0.01 {
                compAudio.scaleTimeRange(CMTimeRange(start: .zero, duration: compDur), toDuration: scaledDur)
            }
        }

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        var t  = preferredTransform
        t.tx  -= transformedRect.origin.x
        t.ty  -= transformedRect.origin.y
        t      = t.concatenating(CGAffineTransform(scaleX: fillScale, y: fillScale))
        t      = t.concatenating(CGAffineTransform(translationX: txOffset, y: tyOffset))
        layerInstruction.setTransform(t, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange         = compRange
        instruction.layerInstructions = [layerInstruction]

        let videoComposition              = AVMutableVideoComposition()
        videoComposition.renderSize       = targetSize
        videoComposition.frameDuration    = CMTimeMake(value: 1, timescale: 30)
        videoComposition.instructions     = [instruction]
        if outputHDR && sourceIsHDR {
            applyHDROutputProps(videoComposition)
        } else {
            await applySDROutputProps(videoComposition, track: videoTrack)
        }

        let parentLayer  = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: targetSize)
        parentLayer.isGeometryFlipped = true
        let videoLayer    = CALayer(); videoLayer.frame   = CGRect(origin: .zero, size: targetSize)
        let overlayLayer  = CALayer(); overlayLayer.frame = CGRect(origin: .zero, size: targetSize)
        overlayLayer.contents = overlay.cgImage
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_clipexport_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)
        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHEVCHighestQuality)
        else { throw ExportError.sessionFailed }
        session.outputURL        = outputURL
        session.outputFileType   = .mov
        session.videoComposition = videoComposition
        session.timeRange        = compRange

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

    /// Exports a Placeable card clip with a static data overlay + animated text layer.
    /// The textLayer is built by `buildClipTextContentLayer` and contains CALayer animations
    /// that play over the clip's full duration (typing / fade / flyIn).
    static func exportPlaceableClipAnimated(
        sourceURL:     URL,
        staticOverlay: UIImage?,
        textLayer:     CALayer?,
        trimStart:     Double,
        trimEnd:       Double,
        muteAudio:     Bool   = false,
        speed:         Double = 1.0,
        brightenHDR:   Bool   = false
    ) async throws -> URL {
        let rawAsset  = AVURLAsset(url: sourceURL)
        let rawTracks = try await rawAsset.loadTracks(withMediaType: .video)
        guard let rawVideoTrack = rawTracks.first else { throw ExportError.noVideoTrack }
        let sourceIsHDR = await isHDRSource(track: rawVideoTrack)
        // exportClipWithOverlay와 동일한 로직:
        // SDR: preprocessHDRToSDR 내부 guard에서 즉시 반환 (처리 없음)
        // HDR + brightenHDR=true: 필믹 S-커브 파이프라인 적용 → 밝은 SDR 출력
        // HDR + brightenHDR=false: 원본 HDR → applySDROutputProps BT.709 톤매핑 (기본)
        let preparedURL = (!sourceIsHDR || brightenHDR)
            ? try await preprocessHDRToSDR(url: sourceURL)
            : sourceURL
        let asset       = AVURLAsset(url: preparedURL)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw ExportError.noVideoTrack }

        let assetDur  = CMTimeGetSeconds(try await asset.load(.duration))
        let start     = CMTime(seconds: max(0, trimStart), preferredTimescale: 600)
        let end       = CMTime(seconds: min(trimEnd, assetDur), preferredTimescale: 600)
        let srcRange  = CMTimeRange(start: start, end: end)
        let compDur   = CMTimeSubtract(end, start)
        let spVal     = max(0.1, speed)
        let scaledDur = abs(spVal - 1.0) > 0.01
            ? CMTimeMultiplyByFloat64(compDur, multiplier: 1.0 / spVal)
            : compDur
        let compRange = CMTimeRange(start: .zero, duration: scaledDur)

        let naturalSize        = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedRect    = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displayWidth       = abs(transformedRect.width)
        let displayHeight      = abs(transformedRect.height)
        let fillScale          = max(targetSize.width / displayWidth, targetSize.height / displayHeight)
        let txOffset           = (targetSize.width  - displayWidth  * fillScale) / 2
        let tyOffset           = (targetSize.height - displayHeight * fillScale) / 2

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.compositionFailed }
        try compVideo.insertTimeRange(srcRange, of: videoTrack, at: .zero)
        if abs(spVal - 1.0) > 0.01 {
            compVideo.scaleTimeRange(CMTimeRange(start: .zero, duration: compDur), toDuration: scaledDur)
        }
        if !muteAudio,
           let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
           let audioTrack  = audioTracks.first,
           let compAudio   = composition.addMutableTrack(
               withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compAudio.insertTimeRange(srcRange, of: audioTrack, at: .zero)
            if abs(spVal - 1.0) > 0.01 {
                compAudio.scaleTimeRange(CMTimeRange(start: .zero, duration: compDur), toDuration: scaledDur)
            }
        }

        var t  = preferredTransform
        t.tx  -= transformedRect.origin.x
        t.ty  -= transformedRect.origin.y
        t      = t.concatenating(CGAffineTransform(scaleX: fillScale, y: fillScale))
        t      = t.concatenating(CGAffineTransform(translationX: txOffset, y: tyOffset))
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        layerInstruction.setTransform(t, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange         = compRange
        instruction.layerInstructions = [layerInstruction]

        let videoComposition           = AVMutableVideoComposition()
        videoComposition.renderSize    = targetSize
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComposition.instructions  = [instruction]
        await applySDROutputProps(videoComposition, track: videoTrack)

        let parentLayer = CALayer()
        parentLayer.frame             = CGRect(origin: .zero, size: targetSize)
        parentLayer.isGeometryFlipped = true
        let videoLayer = CALayer(); videoLayer.frame = CGRect(origin: .zero, size: targetSize)
        parentLayer.addSublayer(videoLayer)

        if let overlay = staticOverlay {
            let ol = CALayer(); ol.frame = CGRect(origin: .zero, size: targetSize)
            ol.contents = overlay.cgImage
            parentLayer.addSublayer(ol)
        }
        if let tl = textLayer {
            parentLayer.addSublayer(tl)
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_plcanim_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)
        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHEVCHighestQuality)
        else { throw ExportError.sessionFailed }
        session.outputURL        = outputURL
        session.outputFileType   = .mov
        session.videoComposition = videoComposition
        session.timeRange        = compRange

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

    /// Concatenates already-processed clip URLs (no trim, no overlay).
    static func concatenateURLs(_ urls: [URL]) async throws -> URL {
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.compositionFailed }
        // 오디오 트랙은 실제 오디오 콘텐츠가 있을 때만 생성 (빈 트랙은 export 실패 원인)
        var compAudio: AVMutableCompositionTrack? = nil
        var insertTime = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let vt = try? await asset.loadTracks(withMediaType: .video).first else { continue }
            let dur   = (try? await asset.load(.duration)) ?? .zero
            let range = CMTimeRange(start: .zero, duration: dur)
            try compVideo.insertTimeRange(range, of: vt, at: insertTime)
            if let at = try? await asset.loadTracks(withMediaType: .audio).first {
                if compAudio == nil {
                    compAudio = composition.addMutableTrack(
                        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                try? compAudio?.insertTimeRange(range, of: at, at: insertTime)
            }
            insertTime = CMTimeAdd(insertTime, dur)
        }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_concat_urls_\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw ExportError.sessionFailed }
        session.outputURL      = outURL
        session.outputFileType = .mp4
        await session.export()
        if let err = session.error { throw err }
        return outURL
    }

    static func exportVideo(sourceURL: URL, overlay: UIImage,
                            startTime: Double = 0, endTime: Double? = nil) async throws -> URL {
        let sourceURL   = try await preprocessHDRToSDR(url: sourceURL)
        let asset       = AVURLAsset(url: sourceURL)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw ExportError.noVideoTrack }

        let duration    = try await asset.load(.duration)
        let assetSec    = CMTimeGetSeconds(duration)
        let clampedEnd  = min(assetSec, endTime ?? trimDuration)
        let clampedStart = max(0, min(startTime, clampedEnd))
        let timeRange   = CMTimeRange(
            start:    CMTimeMakeWithSeconds(clampedStart, preferredTimescale: 600),
            duration: CMTimeMakeWithSeconds(clampedEnd - clampedStart, preferredTimescale: 600)
        )

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
        // hPad (72px) > CardVisual.videoSafeHoriz (60px) — horiz safe zone satisfied.
        // 14pt preview × (1080/211) = 71.6px → 20 * vScale = 72px (미리보기 14pt와 비례 일치).
        // wMarkTopPad: 32 * vScale = 115px → preview scale 0.195 × 115 = 22.5pt (ClipTrimView .top 32 기준 일치).
        let hPad:         CGFloat = 20 * vScale
        let wMarkTopPad:  CGFloat = 32 * vScale
        let wMarkFontPx:  CGFloat = 11 * vScale
        let wMarkZoneH:   CGFloat = wMarkTopPad + ceil(wMarkFontPx * 2.3) + 6 * vScale

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
        let wMarkLayerH = ceil(wMarkFontPx * 2.3)
        let wMarkLayer = CALayer()
        // 사진·영상 공유물 로고 정책(MIMOWordmark.showsOnMediaCards) — 빈 레이어는 그대로 붙여 다른 레이어 좌표 불변
        if MIMOWordmark.showsOnMediaCards, let wmImg = UIImage(named: "MIMOWordmark") {
            let imgW = wMarkLayerH * wmImg.size.width / max(wmImg.size.height, 1)
            wMarkLayer.frame           = CGRect(x: hPad, y: wMarkTopPad, width: imgW, height: wMarkLayerH)
            wMarkLayer.contents        = wmImg.cgImage
            wMarkLayer.contentsGravity = .resizeAspect
            wMarkLayer.masksToBounds   = false
        }
        parentLayer.addSublayer(wMarkLayer)

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
        muteAudio: Bool = false,
        maxDuration: Double? = nil   // nil = trimDuration (30s); pass total seconds for multi-clip
    ) async throws -> URL {

        let nonEmpty = pages.filter { $0.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        guard !nonEmpty.isEmpty else {
            return try await exportOneLinerTypingVideo(
                sourceURL: sourceURL, text: "",
                fontChoice: fontChoice, textColor: textColor, position: position)
        }
        if nonEmpty.count == 1 {
            let text = nonEmpty[0].joined(separator: "\n")
            return try await exportOneLinerTypingVideo(
                sourceURL: sourceURL, text: text,
                fontChoice: fontChoice, textColor: textColor, position: position)
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
        let hPad:         CGFloat = 20 * vScale
        let wMarkTopPad:  CGFloat = 32 * vScale
        let wMarkFontPx:  CGFloat = 11 * vScale
        let wMarkZoneH:   CGFloat = wMarkTopPad + ceil(wMarkFontPx * 2.3) + 6 * vScale

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
        let wMarkLayerH = ceil(wMarkFontPx * 2.3)
        let wMarkLayer = CALayer()
        // 사진·영상 공유물 로고 정책(MIMOWordmark.showsOnMediaCards) — 빈 레이어는 그대로 붙여 다른 레이어 좌표 불변
        if MIMOWordmark.showsOnMediaCards, let wmImg = UIImage(named: "MIMOWordmark") {
            let imgW = wMarkLayerH * wmImg.size.width / max(wmImg.size.height, 1)
            wMarkLayer.frame           = CGRect(x: hPad, y: wMarkTopPad, width: imgW, height: wMarkLayerH)
            wMarkLayer.contents        = wmImg.cgImage
            wMarkLayer.contentsGravity = .resizeAspect
            wMarkLayer.masksToBounds   = false
        }
        parentLayer.addSublayer(wMarkLayer)

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
        muteAudio: Bool = false,
        metricChips: [VideoMetricChip] = [],
        metricLookup: [String: VideoMetricChip] = [:],
        routeCoords: [CLLocationCoordinate2D] = [],
        hrSamples: [(offset: TimeInterval, bpm: Int)] = [],
        splits: [SplitData] = [],
        hrZones: [HRZoneData] = [],
        intervalSegments: [IntervalSegment] = [],
        chartSeriesData: [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:],
        videoTitle: String = "",
        titleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    ) async throws -> URL {

        // ── 0. Page plan ──────────────────────────────────────────────────────
        var clipOffsets: [Double] = []
        var runningOffset = 0.0
        for recipe in recipes {
            clipOffsets.append(runningOffset)
            runningOffset += recipe.trimmedDuration / max(0.1, recipe.speed)
        }
        let D = runningOffset   // total composed duration (speed-adjusted)

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
            let clipEnd   = clipStart + recipe.trimmedDuration / max(0.1, recipe.speed)
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

        // Note: no fallback to exportOneLinerTypingVideo — buildClipTextContentLayer renders
        // charts/chips independently of text, so proceed even when pageSpecs is empty.

        // ── 1. Asset ──────────────────────────────────────────────────────────
        let sourceURL   = try await preprocessHDRToSDR(url: sourceURL)
        let asset       = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw ExportError.noVideoTrack }
        let naturalSize      = try await videoTrack.load(.naturalSize)
        let prefTransform    = try await videoTrack.load(.preferredTransform)
        let trackTimeRange   = try await videoTrack.load(.timeRange)
        let audioTracks      = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

        // 실제 트랙 길이를 기준으로 삽입 범위 결정. D(Double) 반올림 오차나 배속으로
        // 구성 영상이 D보다 짧을 수 있어 끝 부분이 검게 나오는 문제를 방지.
        let timeRange = CMTimeRange(
            start: .zero,
            duration: min(trackTimeRange.duration, CMTimeMakeWithSeconds(D, preferredTimescale: 600)))

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
            metricChips: metricChips,
            metricLookup: metricLookup, routeCoords: routeCoords, hrSamples: hrSamples,
            splits: splits, hrZones: hrZones, intervalSegments: intervalSegments,
            chartSeriesData: chartSeriesData, videoTitle: videoTitle, titleStyle: titleStyle,
            safeTopOverride: oneLinerSize.height * 0.06, safeBotOverride: oneLinerSize.height * 0.06,
            wordmarkTopPad: oneLinerSize.height * 0.06)

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
        showWordmark: Bool = true,
        metricChips: [VideoMetricChip] = [],
        metricLookup: [String: VideoMetricChip] = [:],
        routeCoords: [CLLocationCoordinate2D] = [],
        hrSamples: [(offset: TimeInterval, bpm: Int)] = [],
        splits: [SplitData] = [],
        hrZones: [HRZoneData] = [],
        intervalSegments: [IntervalSegment] = [],
        chartSeriesData: [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:],
        videoTitle: String = "",
        titleStyle: OneLinerTitleStyle = OneLinerTitleStyle(),
        safeTopOverride: CGFloat? = nil,
        safeBotOverride: CGFloat? = nil,
        wordmarkTopPad: CGFloat? = nil
    ) -> CALayer {
        let W = renderSize.width
        let H = renderSize.height
        let vScale: CGFloat   = W / 300.0
        let safeTop: CGFloat  = safeTopOverride ?? CardVisual.videoSafeTop
        let safeBot: CGFloat  = safeBotOverride ?? CardVisual.videoSafeBottom
        let hPad: CGFloat     = 20 * vScale
        let wMTopPad: CGFloat = wordmarkTopPad ?? (32 * vScale)
        let wMFontPx: CGFloat = 11 * vScale
        let wMZoneH: CGFloat  = wMTopPad + ceil(wMFontPx * 2.3) + 6 * vScale
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

        // ── Precompute title metrics (위-위: 문구를 제목 아래로, 아래-아래: 문구를 제목 위로) ─
        let titleTopEndY: CGFloat = {
            guard !videoTitle.isEmpty, titleStyle.position.isTop else { return 0 }
            let tFontPx  = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale * vScale
            let tUIFont  = titleStyle.fontChoice.uiFont(size: tFontPx)
            let tAttrs: [NSAttributedString.Key: Any] = [.font: tUIFont, .foregroundColor: UIColor.white]
            let tBounds  = NSAttributedString(string: videoTitle, attributes: tAttrs).boundingRect(
                with: CGSize(width: textMaxW, height: 4000),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            let tLayerH  = ceil(tBounds.height) + 20
            let tFrameY  = wMZoneH + 12 * vScale
            return tFrameY + tLayerH + 8 * vScale
        }()
        // 아래-아래 쌓기: 제목이 맨 아래일 때 문구를 제목 위로 밀 여분 높이
        let titleBotEndH: CGFloat = {
            guard !videoTitle.isEmpty, titleStyle.position.isBottom else { return 0 }
            let tFontPx  = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale * vScale
            let tUIFont  = titleStyle.fontChoice.uiFont(size: tFontPx)
            let tAttrs: [NSAttributedString.Key: Any] = [.font: tUIFont, .foregroundColor: UIColor.white]
            let tBounds  = NSAttributedString(string: videoTitle, attributes: tAttrs).boundingRect(
                with: CGSize(width: textMaxW, height: 4000),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            return ceil(tBounds.height) + 20 + 8 * vScale  // tLayerH + 간격
        }()

        // ── Page plan ─────────────────────────────────────────────────────────
        var clipOffsets: [Double] = []
        var runningOffset = 0.0
        for recipe in recipes { clipOffsets.append(runningOffset); runningOffset += recipe.trimmedDuration / max(0.1, recipe.speed) }
        var lastTextClipIdx = -1
        for (i, recipe) in recipes.enumerated() { if recipe.hasText { lastTextClipIdx = i } }

        struct PageSpec {
            let text: String; let winStart: Double; let winEnd: Double
            let isLast: Bool; let clipIdx: Int
        }
        var pageSpecs: [PageSpec] = []
        for (clipIdx, recipe) in recipes.enumerated() {
            let clipStart = clipOffsets[clipIdx]
            let clipEnd   = clipStart + recipe.trimmedDuration / max(0.1, recipe.speed)
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
        let holdTime:   Double = 0.40
        let fadeTime:   Double = 0.25

        for page in pageSpecs {
            let chars     = Array(page.text)
            let N         = chars.count
            let windowDur = page.winEnd - page.winStart

            let clip        = page.clipIdx < recipes.count ? recipes[page.clipIdx] : recipes[0]
            // 등장 순서: PDTB(즉시) → 문구(30%~1s) → 차트(60%~2s)
            let clipDur     = clip.trimmedDuration / max(0.1, clip.speed)
            let startDelay  = min(1.0, clipDur * 0.30)
            let fontSize    = OneLinerFont.basePt * clip.fontChoice.sizeScale * clip.sizeLevel.scale * vScale
            let uiFont      = clip.fontChoice.boldUIFont(size: fontSize)
            let lineSpacing: CGFloat = fontSize * 0.1
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
            let textUIColor = clip.textColor.uiColor
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
                let fi = page.winStart + startDelay
                let fadeInDur: Double = 0.35  // 서서히 등장하는 시간 (350ms)
                appearEnd = fi + fadeInDur
                // 페이드 모드: fadeInDur 동안 서서히 등장, 클립 끝에 짧게 페이드아웃
                fadeStart = page.isLast ? D : max(appearEnd + 0.05, page.winEnd - fadeTime)
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

            // textContentH: 실제 렌더링 텍스트 높이 (센터링 기준)
            // textLayerH: 렌더 이미지 프레임 높이 (+ 하단 여유 패딩)
            let textContentH: CGFloat = {
                guard !page.text.isEmpty else { return lineH }
                let r = NSAttributedString(string: page.text, attributes: textAttrs)
                    .boundingRect(with: CGSize(width: textMaxW, height: 4000),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                return ceil(r.height)
            }()
            let textLayerH: CGFloat = page.text.isEmpty ? lineH : textContentH + lineSpacing + 20
            // Chart-aware 9-grid: 차트 활성화 시 차트 제외한 공간에서 9포지션 작동
            let (pageChartActive, pageChartPanH): (Bool, CGFloat) = {
                if clip.showHRChart && hrSamples.count >= 2 { return (true, H * 0.22) }
                if clip.chartOverlayType == .route && routeCoords.count >= 2 { return (true, H * 0.22) }
                if clip.chartOverlayType == .splits && splits.filter({ $0.distanceM >= 900 }).count >= 2 { return (true, H * 0.22) }
                if clip.chartOverlayType == .intervals {
                    let d = intervalSegments.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                    if d > 0 { return (true, H * 0.35) }
                }
                let gt = clip.chartOverlayType
                if ![.none, .route, .hrChart, .splits, .intervals].contains(gt),
                   let s = chartSeriesData[gt], s.count >= 2 { return (true, H * 0.22) }
                return (false, 0)
            }()
            let clipEffBot: CGFloat = pageChartActive
                ? pageChartPanH + safeBot + 12 * vScale + 8 * vScale
                : clip.position.isBottom && titleBotEndH > 0
                    ? safeBot + titleBotEndH  // 아래-아래: 제목 위로 문구 밀기
                    : safeBot
            let defaultTopY = max(wMZoneH + 4 * vScale, safeTop + 4 * vScale)
            let textFrameY: CGFloat = clip.position.isTop
                ? (titleTopEndY > 0 ? titleTopEndY : defaultTopY)
                : clip.position.isBottom
                    ? H - clipEffBot - textLayerH
                    : max(defaultTopY, min(H - clipEffBot - textLayerH,
                                          H / 2 - textContentH / 2))
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
                    let drawOpts: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
                    if let ba = borderAttrs {
                        let bStr = NSAttributedString(string: str, attributes: ba)
                        let o = borderOffset
                        for (ox, oy): (CGFloat, CGFloat) in [(-o,-o),(o,-o),(-o,o),(o,o),(-o,0),(o,0),(0,-o),(0,o)] {
                            bStr.draw(with: rect.offsetBy(dx: ox, dy: oy), options: drawOpts, context: nil)
                        }
                    }
                    NSAttributedString(string: str, attributes: textAttrs).draw(with: rect, options: drawOpts, context: nil)
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
                    // 줄별 실제 높이(줄바꿈 고려) + 누적 Y 오프셋 사전 계산
                    let flyDrawOpts: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
                    var flyLineHs: [CGFloat] = []
                    var flyLineYs: [CGFloat] = []
                    var flyCumY: CGFloat = 0
                    for rawLine in lineTexts {
                        let tr = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        if tr.isEmpty { flyLineHs.append(0); flyLineYs.append(flyCumY); continue }
                        let r = NSAttributedString(string: tr, attributes: textAttrs)
                            .boundingRect(with: CGSize(width: textMaxW, height: 4000),
                                          options: flyDrawOpts, context: nil)
                        let h = max(ceil(r.height) + 4, lineH)
                        flyLineHs.append(h); flyLineYs.append(flyCumY)
                        flyCumY += h + lineSpacing
                    }
                    var staggerIdx = 0
                    for (i, rawLine) in lineTexts.enumerated() {
                        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        let flyBegin = page.winStart + startDelay + Double(staggerIdx) * lineDelay
                        staggerIdx  += 1
                        let lineTopY  = textFrame.minY + flyLineYs[i]
                        let actualLineH = flyLineHs[i]
                        // 텍스트 레이어 — 줄별 실제 높이로 렌더링 (음영판 배경 베이크 포함)
                        let lineRenderer = UIGraphicsImageRenderer(
                            size: CGSize(width: textMaxW, height: actualLineH), format: imgFormat)
                        let lineImg = lineRenderer.image { ctx in
                            ctx.cgContext.setLineJoin(.round)
                            let lRect = CGRect(x: 0, y: 0, width: textMaxW, height: actualLineH)
                            if let ba = borderAttrs {
                                let bStr = NSAttributedString(string: trimmed, attributes: ba)
                                let o = borderOffset
                                for (ox, oy): (CGFloat, CGFloat) in [(-o,-o),(o,-o),(-o,o),(o,o),(-o,0),(o,0),(0,-o),(0,o)] {
                                    bStr.draw(with: lRect.offsetBy(dx: ox, dy: oy), options: flyDrawOpts, context: nil)
                                }
                            }
                            NSAttributedString(string: trimmed, attributes: textAttrs)
                                .draw(with: lRect, options: flyDrawOpts, context: nil)
                        }.cgImage ?? fallbackImg
                        let lineLayer                    = CALayer()
                        lineLayer.frame                  = CGRect(x: textFrame.origin.x, y: lineTopY,
                                                                  width: textMaxW, height: actualLineH)
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
                        // 수직 방향: fly 전에 화면 내에 위치하므로 시작 전까지 숨김
                        if flyVertical {
                            let t = max(0.0001, flyBegin / D)
                            lineLayer.add(linearAnim(keyPath: "opacity",
                                keyTimes: [0.0, NSNumber(value: t - 0.0001), NSNumber(value: t), 1.0],
                                values: [Float(0), Float(0), Float(1), Float(1)]), forKey: "revealOnFly")
                        }
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

                }
            }
            contentLayer.addSublayer(pageLayer)
        }

        // ── Wordmark ───────────────────────────────────────────────────────────
        let wMLayerH = ceil(wMFontPx * 2.3)
        // 사진·영상 공유물 로고 정책(MIMOWordmark.showsOnMediaCards) — 나머지 레이어는 wMZoneH 상수 기준이라 위치 불변
        if showWordmark, MIMOWordmark.showsOnMediaCards, let wmImg = UIImage(named: "MIMOWordmark") {
            let imgW = wMLayerH * wmImg.size.width / max(wmImg.size.height, 1)
            let wMLayer = CALayer()
            wMLayer.frame           = CGRect(x: hPad, y: wMTopPad, width: imgW, height: wMLayerH)
            wMLayer.contents        = wmImg.cgImage
            wMLayer.contentsGravity = .resizeAspect
            wMLayer.masksToBounds   = false
            wMLayer.opacity         = 0.0
            let wMFadeEnd = NSNumber(value: min(0.3 / D, 0.99))
            wMLayer.add(linearAnim(keyPath: "opacity",
                keyTimes: [0.0, 0.0001, wMFadeEnd, 1.0],
                values:   [Float(0), Float(0), Float(1), Float(1)]),
                forKey: "wMFade")
            contentLayer.addSublayer(wMLayer)
        }

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
                ? wMZoneH + 12 * vScale   // 워드마크 존 하단 + 여유 → 항상 로고 아래
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

        // ── 러닝 데이터 오버레이 (per-clip: PDT칩 / 경로 M / 심박 H), 클립 시간창에만 표시 ──
        func frameFor(_ pos: CardPosition, size: CGSize, effBot: CGFloat = safeBot) -> CGRect {
            let x: CGFloat = pos.isLeading  ? hPad
                          : pos.isTrailing ? (W - hPad - size.width)
                          : (W - size.width) / 2
            let chipTopY: CGFloat = (!videoTitle.isEmpty && titleStyle.position.isTop) ? H * 0.28 : safeTop
            let y: CGFloat = pos.isTop     ? chipTopY  // 제목 있으면 H 28%, 없으면 워드마크 아래
                          : pos.isBottom  ? (H - effBot - size.height)
                          : (safeTop + (H - effBot) - size.height) / 2
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }
        func applyDataAnim(_ layer: CALayer, start: Double, end: Double, delay: Double = 0,
                           mode: AppearanceMode = .fade,
                           decorEffect: DecorEffect = .none,
                           flyDirection: FlyInDirection = .trailing) {
            layer.opacity = 0
            let visStart = start + delay
            let clipDur  = max(0.001, end - visStart)
            let fadeDur  = min(0.4, clipDur * 0.25)
            let s  = max(0.0, min(1.0, visStart / D))
            let s2 = min(1.0, max(s  + 0.001, (visStart + fadeDur) / D))
            // When this layer covers the very end of the video, skip the fade-out so the last
            // frame stays fully visible (prevents chart disappearing + black last frame).
            if end >= D - 0.5 {
                layer.add(linearAnim(keyPath: "opacity",
                    keyTimes: [0, NSNumber(value: s), NSNumber(value: s2), 1],
                    values: [Float(0), Float(0), Float(1), Float(1)]),
                    forKey: "runDataOpacity")
            } else {
                let e2 = min(1.0, max(s2 + 0.001, (end - fadeDur * 0.5) / D))
                let e  = min(1.0, max(e2 + 0.001, end / D))
                layer.add(linearAnim(keyPath: "opacity",
                    keyTimes: [0, NSNumber(value: s), NSNumber(value: s2), NSNumber(value: e2), NSNumber(value: e), 1],
                    values: [Float(0), Float(0), Float(1), Float(1), Float(0), Float(0)]),
                    forKey: "runDataOpacity")
            }
            if mode == .flyIn {
                let slideW  = max(layer.bounds.width  * 0.6, 50 * vScale)
                let slideH  = max(layer.bounds.height * 2.0, 80 * vScale)
                let finalX  = layer.position.x
                let finalY  = layer.position.y
                let kt: [NSNumber] = [0, NSNumber(value: s), NSNumber(value: s2), 1]
                switch flyDirection {
                case .leading:
                    layer.add(linearAnim(keyPath: "position.x", keyTimes: kt,
                        values: [finalX - slideW, finalX - slideW, finalX, finalX]), forKey: "runDataSlide")
                case .trailing:
                    layer.add(linearAnim(keyPath: "position.x", keyTimes: kt,
                        values: [finalX + slideW, finalX + slideW, finalX, finalX]), forKey: "runDataSlide")
                case .bottom:
                    layer.add(linearAnim(keyPath: "position.y", keyTimes: kt,
                        values: [finalY + slideH, finalY + slideH, finalY, finalY]), forKey: "runDataSlide")
                }
            } else {
                let appearEnd = visStart + fadeDur
                switch decorEffect {
                case .pop:
                    let pop = CAKeyframeAnimation(keyPath: "transform.scale")
                    pop.values = [1.40, 1.14, 0.90, 1.05, 1.0]
                    pop.keyTimes = [0.0, 0.3, 0.6, 0.82, 1.0] as [NSNumber]
                    pop.duration = 0.45
                    pop.beginTime = AVCoreAnimationBeginTimeAtZero + appearEnd
                    pop.fillMode = .both; pop.isRemovedOnCompletion = false; pop.calculationMode = .linear
                    layer.add(pop, forKey: "runDataPop")
                case .wobble:
                    let wob = CAKeyframeAnimation(keyPath: "transform.rotation.z")
                    wob.values = [0.0, 0.044, 0.0, -0.044, 0.0]
                    wob.keyTimes = [0.0, 0.25, 0.5, 0.75, 1.0] as [NSNumber]
                    wob.duration = 0.5; wob.repeatCount = .infinity; wob.calculationMode = .linear
                    wob.beginTime = AVCoreAnimationBeginTimeAtZero + appearEnd
                    wob.fillMode = .both; wob.isRemovedOnCompletion = false
                    layer.add(wob, forKey: "runDataWobble")
                case .none:
                    break
                }
            }
        }
        func renderChipRow(_ chips: [VideoMetricChip], sizeScale: CGFloat = 1.0) -> UIImage? {
            guard !chips.isEmpty else { return nil }
            let fPx: CGFloat = 11 * vScale * sizeScale, padH = 8 * vScale * sizeScale, padV = 4 * vScale * sizeScale
            let gap = 6 * vScale * sizeScale, cr = 9 * vScale * sizeScale
            struct Piece { let s: NSAttributedString; let w: CGFloat; let h: CGFloat; let c: UIColor }
            var ps: [Piece] = []
            for chip in chips {
                let vAt: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: fPx, weight: .bold), .foregroundColor: UIColor.white]
                let lAt: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fPx * 0.85, weight: .regular), .foregroundColor: UIColor.white.withAlphaComponent(0.75)]
                let m = NSMutableAttributedString(attributedString: NSAttributedString(string: chip.value, attributes: vAt))
                if !chip.label.isEmpty { m.append(NSAttributedString(string: " \(chip.label)", attributes: lAt)) }
                let sz = m.size()
                ps.append(Piece(s: m, w: ceil(sz.width) + padH * 2, h: ceil(sz.height) + padV * 2, c: chip.uiColor))
            }
            let totalW = ps.reduce(0) { $0 + $1.w } + gap * CGFloat(max(0, ps.count - 1))
            let totalH = ps.map { $0.h }.max() ?? 0
            let rnd = UIGraphicsImageRenderer(size: CGSize(width: ceil(totalW), height: ceil(totalH)), format: imgFormat)
            return rnd.image { _ in
                var x: CGFloat = 0
                for p in ps {
                    let rect = CGRect(x: x, y: 0, width: p.w, height: p.h)
                    let path = UIBezierPath(roundedRect: rect, cornerRadius: cr)
                    p.c.withAlphaComponent(0.30).setFill(); path.fill()
                    p.c.withAlphaComponent(0.55).setStroke(); path.lineWidth = max(1, vScale); path.stroke()
                    p.s.draw(in: CGRect(x: x + padH, y: padV, width: p.w - padH * 2, height: p.h - padV * 2))
                    x += p.w + gap
                }
            }
        }
        func renderRouteImage(_ coords: [CLLocationCoordinate2D], side: CGFloat) -> UIImage? {
            guard coords.count >= 2 else { return nil }
            let lats = coords.map { $0.latitude }, lons = coords.map { $0.longitude }
            let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
            let range = max(1e-6, max(maxLat - minLat, maxLon - minLon))
            let padX = (range - (maxLon - minLon)) / 2, padY = (range - (maxLat - minLat)) / 2
            let inset = side * 0.12, dim = side - inset * 2
            func pt(_ c: CLLocationCoordinate2D) -> CGPoint {
                let nx = (c.longitude - minLon + padX) / range
                let ny = (c.latitude  - minLat + padY) / range
                return CGPoint(x: inset + nx * dim, y: inset + (1 - ny) * dim)
            }
            let rnd = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: imgFormat)
            return rnd.image { ctx in
                let cg = ctx.cgContext
                cg.setLineWidth(2 * vScale); cg.setLineCap(.round); cg.setLineJoin(.round)
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setShadow(offset: .zero, blur: 2 * vScale, color: UIColor.black.withAlphaComponent(0.5).cgColor)
                cg.move(to: pt(coords[0]))
                for c in coords.dropFirst() { cg.addLine(to: pt(c)) }
                cg.strokePath()
            }
        }
        // 차트 패널 공통 크기: 좌우여백 동일, 높이=26.4%(인터벌=42%)
        let panW: CGFloat = W - 20 * vScale
        let panH: CGFloat = H * 0.264
        let intervalPanH: CGFloat = H * 0.42
        let panPad: CGFloat = 14 * vScale
        let panCR:  CGFloat = 12 * vScale

        func renderRoutePanel(_ coords: [CLLocationCoordinate2D]) -> UIImage? {
            guard coords.count >= 2 else { return nil }
            let lats = coords.map { $0.latitude }, lons = coords.map { $0.longitude }
            let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
            let range = max(1e-6, max(maxLat - minLat, maxLon - minLon))
            let padX = (range - (maxLon - minLon)) / 2, padY = (range - (maxLat - minLat)) / 2

            let titleH: CGFloat = 12 * vScale
            let chartX: CGFloat = panPad
            let chartW: CGFloat = panW - chartX - panPad
            let chartY: CGFloat = panPad + titleH
            let chartH: CGFloat = panH - chartY - panPad
            let inset:  CGFloat = chartH * 0.06
            let dim     = min(chartW, chartH) - inset * 2
            let xOff    = (chartW - dim) / 2

            func pt(_ c: CLLocationCoordinate2D) -> CGPoint {
                let nx = CGFloat((c.longitude - minLon + padX) / range)
                let ny = CGFloat((c.latitude  - minLat + padY) / range)
                return CGPoint(x: chartX + xOff + inset + nx * dim,
                               y: chartY + inset + (1 - ny) * dim)
            }

            let titleFont  = UIFont.systemFont(ofSize: 10 * vScale, weight: .semibold)
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont,
                                                              .foregroundColor: UIColor.white.withAlphaComponent(0.9)]
            let rnd = UIGraphicsImageRenderer(size: CGSize(width: panW, height: panH), format: imgFormat)
            return rnd.image { ctx in
                let cg = ctx.cgContext
                let bg = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: panW, height: panH), cornerRadius: panCR)
                UIColor.black.withAlphaComponent(0.30).setFill(); bg.fill()
                (AppLanguage.shared.s("↗ 경로", "↗ Route") as NSString)
                    .draw(at: CGPoint(x: chartX, y: panPad), withAttributes: titleAttrs)
                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.88).cgColor)
                cg.setLineWidth(2 * vScale); cg.setLineCap(.round); cg.setLineJoin(.round)
                cg.move(to: pt(coords[0]))
                for c in coords.dropFirst() { cg.addLine(to: pt(c)) }
                cg.strokePath()
                let dotR: CGFloat = 4 * vScale
                let sPt = pt(coords.first!); let ePt = pt(coords.last!)
                cg.setFillColor(UIColor.systemGreen.withAlphaComponent(0.90).cgColor)
                cg.fillEllipse(in: CGRect(x: sPt.x - dotR, y: sPt.y - dotR, width: dotR * 2, height: dotR * 2))
                cg.setFillColor(UIColor.systemRed.withAlphaComponent(0.90).cgColor)
                cg.fillEllipse(in: CGRect(x: ePt.x - dotR, y: ePt.y - dotR, width: dotR * 2, height: dotR * 2))
            }
        }

        func renderHRPanel(_ samples: [(offset: TimeInterval, bpm: Int)], zones: [HRZoneData] = []) -> UIImage? {
            // Convert to Double for bucketing
            let src = samples.map { (offset: $0.offset, value: Double($0.bpm)) }.filter { $0.value > 0 }
            guard src.count >= 2 else { return nil }

            let t0    = src.first!.offset
            let dt    = max(1.0, src.last!.offset - t0)
            let dtMin = dt / 60.0
            let bN    = 80
            let bSz   = dt / Double(bN)

            struct HRBucket { let id: Int; let avg: Double; let lo: Double; let hi: Double }
            let buckets: [HRBucket] = (0..<bN).compactMap { i in
                let lo   = t0 + Double(i) * bSz
                let hi   = lo + bSz
                let vals = src
                    .filter { $0.offset >= lo && ($0.offset < hi || (i == bN - 1 && $0.offset <= t0 + dt)) }
                    .map(\.value)
                guard !vals.isEmpty else { return nil }
                return HRBucket(id: i,
                                avg: vals.reduce(0, +) / Double(vals.count),
                                lo:  vals.min()!,
                                hi:  vals.max()!)
            }
            guard !buckets.isEmpty else { return nil }

            let avgBpm = src.map(\.value).reduce(0, +) / Double(src.count)

            // Y domain (range bars)
            let oMin  = buckets.map(\.lo).min()!
            let oMax  = buckets.map(\.hi).max()!
            let rng   = max(oMax - oMin, oMin * 0.02)
            let yLo   = max(0, oMin - rng * 0.4)
            let yHi   = oMax + rng * 0.2
            let yRange = max(1, yHi - yLo)

            // Zone bar colors (Z1→Z5: blue, green, yellow-green, orange, pink)
            let zoneBarColors: [UIColor] = [
                UIColor(red: 0.30, green: 0.55, blue: 1.00, alpha: 0.85),
                UIColor(red: 0.20, green: 0.85, blue: 0.45, alpha: 0.85),
                UIColor(red: 0.75, green: 0.88, blue: 0.20, alpha: 0.85),
                UIColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 0.85),
                UIColor(red: 1.00, green: 0.25, blue: 0.45, alpha: 0.85),
            ]
            let defaultBarColor = UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 0.85)
            func zoneBarColor(for bpm: Double) -> UIColor {
                guard !zones.isEmpty else { return defaultBarColor }
                for zone in zones.sorted(by: { $0.id < $1.id }) {
                    if bpm <= Double(zone.maxBPM) {
                        let idx = min(zone.id - 1, zoneBarColors.count - 1)
                        return idx >= 0 ? zoneBarColors[idx] : defaultBarColor
                    }
                }
                return zoneBarColors.last ?? defaultBarColor
            }

            // Layout (right Y labels, bottom X labels — same as renderGenericChartPanel)
            let axisFont  = UIFont.monospacedDigitSystemFont(ofSize: 8 * vScale, weight: .regular)
            let axisColor = UIColor.white.withAlphaComponent(0.55)
            let axisAttrs: [NSAttributedString.Key: Any] = [.font: axisFont, .foregroundColor: axisColor]
            let yLblW: CGFloat = ("180" as NSString).size(withAttributes: axisAttrs).width + 5 * vScale
            let titleH: CGFloat = 12 * vScale
            let xLblH:  CGFloat = 12 * vScale
            let chartX: CGFloat = panPad
            let chartW: CGFloat = panW - chartX - yLblW - panPad
            let chartY: CGFloat = panPad + titleH
            let chartH: CGFloat = panH - chartY - xLblH - panPad * 0.5

            func ptY(_ bpm: Double) -> CGFloat { chartY + CGFloat(1 - (bpm - yLo) / yRange) * chartH }

            let yMarkCount = 4
            let yStep = (yHi - yLo) / Double(yMarkCount - 1)
            let xMarkCount = 4

            let rnd = UIGraphicsImageRenderer(size: CGSize(width: panW, height: panH), format: imgFormat)
            return rnd.image { ctx in
                let cg = ctx.cgContext

                let bg = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: panW, height: panH), cornerRadius: panCR)
                UIColor.black.withAlphaComponent(0.30).setFill(); bg.fill()

                let titleFont  = UIFont.systemFont(ofSize: 10 * vScale, weight: .semibold)
                let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont,
                                                                  .foregroundColor: UIColor.white.withAlphaComponent(0.9)]
                (AppLanguage.shared.s("♥ 심박수", "♥ HR") as NSString).draw(at: CGPoint(x: chartX, y: panPad),
                                                                              withAttributes: titleAttrs)

                // H grid + right Y labels
                for i in 0..<yMarkCount {
                    let yVal = yLo + Double(i) * yStep
                    let yPos = ptY(yVal)
                    cg.setStrokeColor(UIColor.white.withAlphaComponent(0.10).cgColor)
                    cg.setLineWidth(0.5)
                    cg.move(to: CGPoint(x: chartX, y: yPos))
                    cg.addLine(to: CGPoint(x: chartX + chartW, y: yPos))
                    cg.strokePath()
                    let text = "\(Int(yVal.rounded()))"
                    let sz   = (text as NSString).size(withAttributes: axisAttrs)
                    let ly   = min(chartY + chartH - sz.height, max(chartY, yPos - sz.height / 2))
                    (text as NSString).draw(at: CGPoint(x: chartX + chartW + 3 * vScale, y: ly), withAttributes: axisAttrs)
                }

                // V grid + bottom X labels
                for i in 0..<xMarkCount {
                    let frac = Double(i) / Double(xMarkCount - 1)
                    let xPos = chartX + CGFloat(frac) * chartW
                    let tMin = frac * dtMin
                    cg.setStrokeColor(UIColor.white.withAlphaComponent(0.10).cgColor)
                    cg.setLineWidth(0.5)
                    cg.move(to: CGPoint(x: xPos, y: chartY))
                    cg.addLine(to: CGPoint(x: xPos, y: chartY + chartH))
                    cg.strokePath()
                    let text = AppLanguage.shared.isEnglish
                        ? String(format: "%.0fm", tMin)
                        : String(format: "%.0f분", tMin)
                    let sz   = (text as NSString).size(withAttributes: axisAttrs)
                    var lx   = xPos - sz.width / 2
                    if i == 0 { lx = xPos }
                    if i == xMarkCount - 1 { lx = xPos - sz.width }
                    (text as NSString).draw(at: CGPoint(x: lx, y: chartY + chartH + 2 * vScale), withAttributes: axisAttrs)
                }

                // Zone-colored range bars
                let barGap = chartW / CGFloat(bN)
                let barW   = max(1.5 * vScale, barGap - 0.8 * vScale)
                for bucket in buckets {
                    let bx   = chartX + CGFloat(bucket.id) * barGap + (barGap - barW) / 2
                    let topY = ptY(bucket.hi)
                    let botY = ptY(bucket.lo)
                    cg.setFillColor(zoneBarColor(for: bucket.avg).cgColor)
                    cg.fill(CGRect(x: bx, y: topY, width: barW, height: max(1.5 * vScale, botY - topY)))
                }

                // Avg dashed line (red)
                let avgY    = ptY(avgBpm)
                let redLine = UIColor(red: 1, green: 0.35, blue: 0.35, alpha: 0.70)
                cg.setStrokeColor(redLine.cgColor)
                cg.setLineWidth(1.2 * vScale)
                cg.setLineDash(phase: 0, lengths: [5 * vScale, 3 * vScale])
                cg.move(to: CGPoint(x: chartX, y: avgY))
                cg.addLine(to: CGPoint(x: chartX + chartW, y: avgY))
                cg.strokePath()
                cg.setLineDash(phase: 0, lengths: [])

                // "avg NNN" label (red, right side)
                let avgText  = "avg \(Int(avgBpm.rounded()))"
                let avgAttrs: [NSAttributedString.Key: Any] = [.font: axisFont,
                                                                .foregroundColor: UIColor(red: 1, green: 0.35, blue: 0.35, alpha: 0.90)]
                let avgSz    = (avgText as NSString).size(withAttributes: avgAttrs)
                let avgLy    = min(chartY + chartH - avgSz.height, max(chartY, avgY - avgSz.height / 2))
                (avgText as NSString).draw(at: CGPoint(x: chartX + chartW + 3 * vScale, y: avgLy), withAttributes: avgAttrs)
            }
        }

        func renderSplitsPanel(_ splits: [SplitData], hrZones: [HRZoneData]) -> UIImage? {
            let full = splits.filter { $0.distanceM >= 900 }
            guard full.count >= 2 else { return nil }

            let displaySplits = full.count > 21 ? full.filter { $0.id % 2 == 0 } : full
            guard !displaySplits.isEmpty else { return nil }

            let paces      = displaySplits.map { $0.paceSecPerKm }
            let minP       = paces.min()!
            let rangeP     = max(1.0, (paces.max()!) - minP)
            let fastestIdx = paces.indices.min(by: { paces[$0] < paces[$1] }) ?? 0

            let hasHR  = displaySplits.contains { $0.avgHeartRate != nil }
            let hasCad = displaySplits.contains { $0.avgCadence != nil }
            let hasPwr = displaySplits.contains { $0.avgPower != nil }

            let hPadV: CGFloat = 8  * vScale
            let gapV:  CGFloat = 3  * vScale
            let kmW:   CGFloat = 18 * vScale
            let colW:  CGFloat = 24 * vScale
            let rowH:  CGFloat = 7  * vScale
            let titleH: CGFloat = 16 * vScale
            let colHH:  CGFloat = 8  * vScale
            let vPadV:  CGFloat = 5  * vScale

            let fixedW = 2 * hPadV + kmW + 2 * gapV + colW
            let optW   = (hasHR  ? gapV + colW : 0)
                       + (hasCad ? gapV + colW : 0)
                       + (hasPwr ? gapV + colW : 0)
            let barAreaW = max(20 * vScale, panW - fixedW - optW)
            let imgH = titleH + colHH + CGFloat(displaySplits.count) * rowH + vPadV * 2

            // Colors
            let gold   = UIColor(red: 1.000, green: 0.780, blue: 0.302, alpha: 1.0)
            let cyan   = UIColor(red: 0.376, green: 0.910, blue: 0.800, alpha: 1.0)
            let lime   = UIColor(red: 0.745, green: 0.980, blue: 0.416, alpha: 1.0)
            func zoneUIColor(_ hr: Int?) -> UIColor {
                guard let hr = hr,
                      let zid = hrZones.first(where: { hr >= $0.minBPM && hr <= $0.maxBPM })?.id
                else { return UIColor.red.withAlphaComponent(0.70) }
                switch zid {
                case 1: return UIColor(red: 0.310, green: 0.765, blue: 0.969, alpha: 1)
                case 2: return UIColor(red: 0.506, green: 0.780, blue: 0.518, alpha: 1)
                case 3: return UIColor(red: 1.000, green: 0.718, blue: 0.302, alpha: 1)
                case 4: return UIColor(red: 1.000, green: 0.439, blue: 0.263, alpha: 1)
                default: return UIColor(red: 0.898, green: 0.224, blue: 0.208, alpha: 1)
                }
            }

            let rnd = UIGraphicsImageRenderer(size: CGSize(width: panW, height: imgH), format: imgFormat)
            return rnd.image { _ in
                // Background
                let bg = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: panW, height: imgH), cornerRadius: panCR)
                UIColor.black.withAlphaComponent(0.40).setFill(); bg.fill()

                // Title
                let titleFont = UIFont.systemFont(ofSize: 10 * vScale, weight: .semibold)
                let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor.white.withAlphaComponent(0.9)]
                let titleStr = AppLanguage.shared.s("⚡ 스플릿", "⚡ Splits") as NSString
                let tSz = titleStr.size(withAttributes: titleAttrs)
                titleStr.draw(at: CGPoint(x: hPadV, y: (titleH - tSz.height) / 2), withAttributes: titleAttrs)

                // Column headers
                let hdrFont  = UIFont.systemFont(ofSize: 5.5 * vScale, weight: .medium)
                let hdrAttrs: [NSAttributedString.Key: Any] = [.font: hdrFont, .foregroundColor: UIColor.white.withAlphaComponent(0.75)]
                let hdrY = titleH + (colHH - hdrFont.lineHeight) / 2
                let paceColX = hPadV + kmW + gapV + barAreaW + gapV
                func drawRightAligned(_ str: String, x: CGFloat, y: CGFloat, w: CGFloat, attrs: [NSAttributedString.Key: Any]) {
                    let s = str as NSString; let sz = s.size(withAttributes: attrs)
                    s.draw(at: CGPoint(x: x + w - sz.width, y: y), withAttributes: attrs)
                }
                drawRightAligned(AppLanguage.shared.s("페이스", "Pace"), x: paceColX, y: hdrY, w: colW, attrs: hdrAttrs)
                var hdrCurX = paceColX + colW + gapV
                if hasHR  { drawRightAligned(AppLanguage.shared.s("심박", "HR"),   x: hdrCurX, y: hdrY, w: colW, attrs: hdrAttrs); hdrCurX += colW + gapV }
                if hasCad { drawRightAligned(AppLanguage.shared.s("케이던스", "Cad"), x: hdrCurX, y: hdrY, w: colW, attrs: hdrAttrs); hdrCurX += colW + gapV }
                if hasPwr { drawRightAligned(AppLanguage.shared.s("파워", "Pwr"),    x: hdrCurX, y: hdrY, w: colW, attrs: hdrAttrs) }

                // Data rows
                let kmFont   = UIFont.monospacedDigitSystemFont(ofSize: 6.5 * vScale, weight: .medium)
                let paceFont = UIFont.monospacedDigitSystemFont(ofSize: 7   * vScale, weight: .bold)
                let dataFont = UIFont.monospacedDigitSystemFont(ofSize: 6.5 * vScale, weight: .regular)

                for (idx, split) in displaySplits.enumerated() {
                    let rowY = titleH + colHH + CGFloat(idx) * rowH
                    let midY = rowY + rowH / 2

                    let isFastest = idx == fastestIdx
                    let pace = split.paceSecPerKm
                    let barFrac = CGFloat(0.28 + 0.72 * (pace - minP) / rangeP)
                    let barColor: UIColor = isFastest ? gold
                        // 페이스 색(청록), 빠를수록 진하게 — 앱 구간 기록과 같은 규칙(Theme.splitBarOpacity)
                        : Theme.splitBarLoUI.withAlphaComponent(
                            Theme.splitBarOpacity(speed: rangeP > 0 ? 1 - (pace - minP) / rangeP : 0.5))

                    // km label (right-aligned in kmW)
                    let kmStr = "\(split.id)k" as NSString
                    let kmAttrs: [NSAttributedString.Key: Any] = [.font: kmFont, .foregroundColor: UIColor.white.withAlphaComponent(0.80)]
                    let kmSz = kmStr.size(withAttributes: kmAttrs)
                    kmStr.draw(at: CGPoint(x: hPadV + kmW - kmSz.width, y: midY - kmSz.height / 2), withAttributes: kmAttrs)

                    // Pace bar
                    let barX = hPadV + kmW + gapV
                    let barBg = UIBezierPath(roundedRect: CGRect(x: barX, y: midY - 1.5 * vScale, width: barAreaW, height: 3 * vScale), cornerRadius: vScale)
                    UIColor.white.withAlphaComponent(0.10).setFill(); barBg.fill()
                    let barFilled = UIBezierPath(roundedRect: CGRect(x: barX, y: midY - 1.5 * vScale, width: max(3, barAreaW * barFrac), height: 3 * vScale), cornerRadius: vScale)
                    barColor.setFill(); barFilled.fill()

                    // Pace time (right-aligned in colW)
                    let paceStr = split.formattedPace as NSString
                    let paceAttrs: [NSAttributedString.Key: Any] = [.font: paceFont, .foregroundColor: isFastest ? gold : UIColor.white]
                    let paceSz = paceStr.size(withAttributes: paceAttrs)
                    paceStr.draw(at: CGPoint(x: paceColX + colW - paceSz.width, y: midY - paceSz.height / 2), withAttributes: paceAttrs)

                    var dataCurX = paceColX + colW + gapV

                    // HR + zone dot
                    if hasHR {
                        if let hr = split.avgHeartRate {
                            let zc = zoneUIColor(hr)
                            let dotR = 1.75 * vScale
                            let dotPath = UIBezierPath(ovalIn: CGRect(x: dataCurX, y: midY - dotR, width: dotR * 2, height: dotR * 2))
                            zc.setFill(); dotPath.fill()
                            let hrStr = "\(hr)" as NSString
                            let hrAttrs: [NSAttributedString.Key: Any] = [.font: dataFont, .foregroundColor: zc]
                            let hrSz = hrStr.size(withAttributes: hrAttrs)
                            hrStr.draw(at: CGPoint(x: dataCurX + colW - hrSz.width, y: midY - hrSz.height / 2), withAttributes: hrAttrs)
                        }
                        dataCurX += colW + gapV
                    }

                    // Cadence
                    if hasCad {
                        let s = (split.avgCadence.map { "\($0)" } ?? "—") as NSString
                        let a: [NSAttributedString.Key: Any] = [.font: dataFont, .foregroundColor: cyan]
                        let sz = s.size(withAttributes: a)
                        s.draw(at: CGPoint(x: dataCurX + colW - sz.width, y: midY - sz.height / 2), withAttributes: a)
                        dataCurX += colW + gapV
                    }

                    // Power
                    if hasPwr {
                        let s = (split.avgPower.map { "\($0)" } ?? "—") as NSString
                        let a: [NSAttributedString.Key: Any] = [.font: dataFont, .foregroundColor: lime]
                        let sz = s.size(withAttributes: a)
                        s.draw(at: CGPoint(x: dataCurX + colW - sz.width, y: midY - sz.height / 2), withAttributes: a)
                    }
                }
            }
        }

        func renderIntervalPanel(_ segments: [IntervalSegment]) -> UIImage? {
            guard segments.count >= 2 else { return nil }
            let totalDuration = segments.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            guard totalDuration > 0 else { return nil }

            let violet   = UIColor(red: 0.486, green: 0.361, blue: 0.988, alpha: 0.90)
            let darkGray = UIColor(white: 0.28, alpha: 0.90)
            let lblFont  = UIFont.monospacedDigitSystemFont(ofSize: 8 * vScale, weight: .regular)

            let titleH: CGFloat   = 13 * vScale
            let barAreaX: CGFloat = panPad
            let barAreaY: CGFloat = panPad + titleH + 4 * vScale
            let barAreaW: CGFloat = panW - barAreaX - panPad
            let barAreaH: CGFloat = intervalPanH - barAreaY - panPad
            let barGap: CGFloat   = 2 * vScale
            let totalGapW         = barGap * CGFloat(max(0, segments.count - 1))

            let rnd = UIGraphicsImageRenderer(size: CGSize(width: panW, height: intervalPanH), format: imgFormat)
            return rnd.image { ctx in
                let cg = ctx.cgContext

                // Background
                let bg = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: panW, height: intervalPanH), cornerRadius: panCR)
                UIColor.black.withAlphaComponent(0.30).setFill(); bg.fill()

                // Title
                let titleFont = UIFont.systemFont(ofSize: 10 * vScale, weight: .semibold)
                let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor.white.withAlphaComponent(0.9)]
                (AppLanguage.shared.s("⚙ 인터벌", "⚙ Intervals") as NSString).draw(at: CGPoint(x: barAreaX, y: panPad), withAttributes: titleAttrs)

                var xCursor: CGFloat = barAreaX
                for seg in segments {
                    let dur      = seg.endDate.timeIntervalSince(seg.startDate)
                    let fraction = CGFloat(dur / totalDuration)
                    let bW       = (barAreaW - totalGapW) * fraction
                    let isWork   = seg.stepLabel == "운동"
                    let barColor = isWork ? violet : darkGray

                    let barRect = CGRect(x: xCursor, y: barAreaY, width: bW, height: barAreaH)
                    let barPath = UIBezierPath(roundedRect: barRect, cornerRadius: 4 * vScale)
                    barColor.setFill(); barPath.fill()

                    // Text inside bar (only if wide enough)
                    if bW > 28 * vScale {
                        var lines: [String] = []
                        if let distM = seg.distanceM, distM > 0 {
                            let pSec = dur / (distM / 1000)
                            lines.append("\(Int(pSec) / 60)'\(String(format: "%02d", Int(pSec) % 60))\"")
                        }
                        if let hr = seg.avgHeartRate  { lines.append("\(hr)♥") }
                        if let cd = seg.avgCadence    { lines.append("\(cd)spm") }

                        let lineH: CGFloat = 9 * vScale
                        let totalTextH = CGFloat(lines.count) * lineH + CGFloat(max(0, lines.count - 1)) * 2 * vScale
                        var ty = barAreaY + (barAreaH - totalTextH) / 2
                        for line in lines {
                            let attrs: [NSAttributedString.Key: Any] = [.font: lblFont, .foregroundColor: UIColor.white.withAlphaComponent(0.9)]
                            let sz = (line as NSString).size(withAttributes: attrs)
                            (line as NSString).draw(at: CGPoint(x: xCursor + (bW - sz.width) / 2, y: ty), withAttributes: attrs)
                            ty += lineH + 2 * vScale
                        }
                    }
                    xCursor += bW + barGap
                }
                _ = cg  // suppress unused warning
            }
        }

        for (clipIdx, recipe) in recipes.enumerated() {
            let cStart = clipOffsets[clipIdx]
            let cEnd   = cStart + recipe.trimmedDuration / max(0.1, recipe.speed)
            // Chart-aware 9-grid: 차트 활성화 시 차트 제외한 공간에서 9포지션 작동
            let (recipeChartActive, recipeChartPanH): (Bool, CGFloat) = {
                if recipe.showHRChart && hrSamples.count >= 2 { return (true, H * 0.264) }
                if recipe.chartOverlayType == .route && routeCoords.count >= 2 { return (true, H * 0.264) }
                if recipe.chartOverlayType == .splits {
                    let fc = splits.filter { $0.distanceM >= 900 }.count
                    if fc >= 2 {
                        let dc = fc > 21 ? fc / 2 : fc
                        return (true, (34 + CGFloat(dc) * 7) * vScale)
                    }
                }
                if recipe.chartOverlayType == .intervals {
                    let d = intervalSegments.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                    if d > 0 { return (true, H * 0.42) }
                }
                let gt = recipe.chartOverlayType
                if ![.none, .route, .hrChart, .splits, .intervals].contains(gt),
                   let s = chartSeriesData[gt], s.count >= 2 { return (true, H * 0.264) }
                return (false, 0)
            }()
            let recipeEffBot: CGFloat = recipeChartActive
                ? recipeChartPanH + safeBot + 8 * vScale   // safeBot + 8*vScale gap above chart
                : safeBot
            // PDT 칩
            let pdt: [VideoMetricChip] = [
                recipe.metricDistance  ? metricLookup["distance"]  : nil,
                recipe.metricPace      ? metricLookup["pace"]      : nil,
                recipe.metricTime      ? metricLookup["time"]      : nil,
                recipe.metricHeartRate ? metricLookup["heartrate"] : nil
            ].compactMap { $0 }
            if !pdt.isEmpty, let img = renderChipRow(pdt, sizeScale: recipe.pdtSizeLevel.scale) {
                let sz = img.size
                let layer = CALayer()
                layer.frame = frameFor(recipe.pdtPosition, size: sz, effBot: recipeEffBot)
                layer.contents = img.cgImage; layer.contentsGravity = .topLeft
                let pdtDelay = min(2.0, (cEnd - cStart) * 0.40)
                applyDataAnim(layer, start: cStart, end: cEnd, delay: pdtDelay,
                              mode: recipe.pdtAppearanceMode, decorEffect: recipe.pdtDecorEffect, flyDirection: recipe.pdtFlyDirection)
                contentLayer.addSublayer(layer)
            }
            // 차트 패널 — 등장 순서: 워드마크(0s) → 문구(30%) → 러닝데이터(40%) → 차트(60%)
            let chartDelay: Double = min(3.0, (cEnd - cStart) * 0.60)
            if recipe.showHRChart, hrSamples.count >= 2,
               let img = renderHRPanel(hrSamples, zones: hrZones) {
                let layer = CALayer()
                layer.frame = CGRect(x: (W - panW) / 2, y: H - safeBot - panH, width: panW, height: panH)
                layer.contents = img.cgImage; layer.contentsGravity = .topLeft
                applyDataAnim(layer, start: cStart, end: cEnd, delay: chartDelay,
                              mode: recipe.dataAppearanceMode, decorEffect: recipe.chartDecorEffect, flyDirection: recipe.chartFlyDirection)
                contentLayer.addSublayer(layer)
            }
            if recipe.chartOverlayType == .splits, !splits.isEmpty {
                let full = splits.filter { $0.distanceM >= 900 }
                if full.count >= 2, let img = renderSplitsPanel(splits, hrZones: hrZones) {
                    let dc = full.count > 21 ? full.count / 2 : full.count
                    let splitsPanH = (34 + CGFloat(dc) * 7) * vScale
                    let layer = CALayer()
                    layer.frame = CGRect(x: (W - panW) / 2, y: H - safeBot - splitsPanH, width: panW, height: splitsPanH)
                    layer.contents = img.cgImage; layer.contentsGravity = .topLeft
                    applyDataAnim(layer, start: cStart, end: cEnd, delay: chartDelay,
                                  mode: recipe.dataAppearanceMode, decorEffect: recipe.chartDecorEffect, flyDirection: recipe.chartFlyDirection)
                    contentLayer.addSublayer(layer)
                }
            }
            if recipe.chartOverlayType == .intervals, !intervalSegments.isEmpty,
               let img = renderIntervalPanel(intervalSegments) {
                let layer = CALayer()
                layer.frame = CGRect(x: (W - panW) / 2, y: H - safeBot - intervalPanH, width: panW, height: intervalPanH)
                layer.contents = img.cgImage; layer.contentsGravity = .topLeft
                applyDataAnim(layer, start: cStart, end: cEnd, delay: chartDelay,
                              mode: recipe.dataAppearanceMode, decorEffect: recipe.chartDecorEffect, flyDirection: recipe.chartFlyDirection)
                contentLayer.addSublayer(layer)
            }
            if recipe.chartOverlayType == .route, routeCoords.count >= 2,
               let img = renderRoutePanel(routeCoords) {
                let layer = CALayer()
                layer.frame = CGRect(x: (W - panW) / 2, y: H - safeBot - panH, width: panW, height: panH)
                layer.contents = img.cgImage; layer.contentsGravity = .topLeft
                applyDataAnim(layer, start: cStart, end: cEnd, delay: chartDelay,
                              mode: recipe.dataAppearanceMode, decorEffect: recipe.chartDecorEffect, flyDirection: recipe.chartFlyDirection)
                contentLayer.addSublayer(layer)
            }
            let genericType = recipe.chartOverlayType
            if ![.none, .route, .hrChart, .splits, .intervals].contains(genericType),
               let series = chartSeriesData[genericType],
               let img = ChartOverlayType.renderGenericChartPanel(
                   type: genericType, series: series,
                   panW: panW, panH: panH, panPad: panPad, panCR: panCR, vScale: vScale) {
                let layer = CALayer()
                layer.frame = CGRect(x: (W - panW) / 2, y: H - safeBot - panH, width: panW, height: panH)
                layer.contents = img.cgImage; layer.contentsGravity = .topLeft
                applyDataAnim(layer, start: cStart, end: cEnd, delay: chartDelay,
                              mode: recipe.dataAppearanceMode, decorEffect: recipe.chartDecorEffect, flyDirection: recipe.chartFlyDirection)
                contentLayer.addSublayer(layer)
            }
        }

        return contentLayer
    }

    // MARK: - buildVideoPreviewItem
    //
    // Builds AVMutableComposition (no export) + buildClipTextContentLayer for instant preview.
    // Returns tempURL = nil since no black base video is needed for real video clips.

    static func buildVideoPreviewItem(
        recipes: [ClipRecipe],
        showWordmark: Bool = true,
        muteAudio: Bool = false,
        metricChips: [VideoMetricChip] = [],
        metricLookup: [String: VideoMetricChip] = [:],
        routeCoords: [CLLocationCoordinate2D] = [],
        hrSamples: [(offset: TimeInterval, bpm: Int)] = [],
        splits: [SplitData] = [],
        hrZones: [HRZoneData] = [],
        intervalSegments: [IntervalSegment] = [],
        chartSeriesData: [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:],
        videoTitle: String = "",
        titleStyle: OneLinerTitleStyle = OneLinerTitleStyle(),
        safeTopOverride: CGFloat? = nil,
        safeBotOverride: CGFloat? = nil,
        wordmarkTopPad: CGFloat? = nil,
        dataOverlayImage: UIImage? = nil,
        fullSizeOverlayImage: UIImage? = nil
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
            // 자산 해석 우선순위:
            // 1) resolvedAsset(메모리 캐시, PHImageManager 반환 AVAsset/AVComposition)
            // 2) 파일이 실제 존재하는 URL
            // 3) assetIdentifier로 PHAsset 즉시 해석 (이전 세션 복원 클립, resolvedAsset 없음)
            // 4) clipVideoRef 안정 복사본 URL
            // 5) 해석 불가 → throw 대신 이 클립만 skip (buildConcatenatedPreviewItem과 동일 정책)
            let asset: AVAsset
            if let resolved = recipe.resolvedAsset {
                asset = resolved
            } else if FileManager.default.fileExists(atPath: recipe.url.path) {
                asset = AVURLAsset(url: recipe.url)
            } else if let assetID = recipe.assetIdentifier,
                      let resolved = try? await MultiClipComposition.resolveAVAsset(assetID: assetID) {
                asset = resolved
            } else if let ref = recipe.clipVideoRef,
                      let stableURL = ClipVideoStore.fileURL(ref: ref),
                      FileManager.default.fileExists(atPath: stableURL.path) {
                asset = AVURLAsset(url: stableURL)
            } else {
                clipIdx += 1
                continue
            }
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
            showWordmark: showWordmark,
            metricChips: metricChips,
            metricLookup: metricLookup, routeCoords: routeCoords, hrSamples: hrSamples,
            splits: splits, hrZones: hrZones, intervalSegments: intervalSegments,
            chartSeriesData: chartSeriesData, videoTitle: videoTitle, titleStyle: titleStyle,
            safeTopOverride: safeTopOverride, safeBotOverride: safeBotOverride,
            wordmarkTopPad: wordmarkTopPad)

        // PlaceableCard 데이터 오버레이 — 텍스트 레이어 아래에 배치(index 0)
        // → SwiftUI 오버레이 없이도 미리보기에서 데이터가 보이고, 텍스트가 가려지지 않음
        if let overlayImg = dataOverlayImage, let cgImg = overlayImg.cgImage {
            let W = oneLinerSize.width; let H = oneLinerSize.height
            let cardLayerH: CGFloat = 375.0 * (W / 300.0)  // PlaceableCard.cardHeight * vScale
            let cardMargin: CGFloat = H * 0.03
            let dataLayer             = CALayer()
            dataLayer.frame           = CGRect(x: 0, y: H - cardLayerH - cardMargin,
                                               width: W, height: cardLayerH)
            dataLayer.contents        = cgImg
            dataLayer.contentsGravity = .resize
            dataLayer.masksToBounds   = false
            contentLayer.insertSublayer(dataLayer, at: 0)
        }

        // 풀사이즈 오버레이 (스탬프 카드 전용) — 1080×1920 전체 크기로 contentLayer 위에 올림
        if let overlayImg = fullSizeOverlayImage, let cgImg = overlayImg.cgImage {
            let stampLayer             = CALayer()
            stampLayer.frame           = CGRect(origin: .zero, size: oneLinerSize)
            stampLayer.contents        = cgImg
            stampLayer.contentsGravity = .resize
            stampLayer.masksToBounds   = false
            stampLayer.contentsScale   = 1.0
            contentLayer.addSublayer(stampLayer)
        }

        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = videoComp

        return (playerItem, contentLayer, oneLinerSize, D)
    }
}
