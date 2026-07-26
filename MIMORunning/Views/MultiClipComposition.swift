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

// MARK: - ChartOverlayType
//
// 클립 위에 표시할 차트 오버레이 단일 선택. .none = 없음.
// splits/cadence/groundContact/strideLength/verticalOscillation/elevation은 렌더러 미구현(disabled).

enum ChartOverlayType: String, CaseIterable, Codable {
    case none                = "none"
    case route               = "route"
    case hrChart             = "hrChart"
    case splits              = "splits"
    case cadence             = "cadence"
    case groundContact       = "groundContact" // enum 유지 (하위호환), UI 그리드 미노출
    case strideLength        = "strideLength"
    case verticalOscillation = "verticalOscillation"
    case elevation           = "elevation"
    case power               = "power"         // enum 유지 (하위호환), UI 그리드 미노출
    case intervals           = "intervals"

    var chartTitleKo: String {
        switch self {
        case .hrChart:             return "♥ 심박수"
        case .splits:              return "⚡ 스플릿"
        case .cadence:             return "🦵 케이던스"
        case .strideLength:        return "→ 보폭"
        case .verticalOscillation: return "↕ 수직진폭"
        case .elevation:           return "⛰ 고도"
        case .intervals:           return "↩ 인터벌"
        default:                   return ""
        }
    }
    var chartTitleEn: String {
        switch self {
        case .hrChart:             return "♥ HR"
        case .splits:              return "⚡ Splits"
        case .cadence:             return "Cadence"
        case .strideLength:        return "Stride"
        case .verticalOscillation: return "Vert. Osc."
        case .elevation:           return "Elevation"
        case .intervals:           return "↩ Intervals"
        default:                   return ""
        }
    }
    var lineUIColor: UIColor {
        switch self {
        case .cadence:             return UIColor(red: 0.486, green: 0.361, blue: 0.988, alpha: 0.90)
        case .strideLength:        return UIColor.systemTeal.withAlphaComponent(0.90)
        case .verticalOscillation: return UIColor.systemOrange.withAlphaComponent(0.90)
        case .elevation:           return UIColor.systemGreen.withAlphaComponent(0.90)
        default:                   return UIColor.white.withAlphaComponent(0.85)
        }
    }
    /// chart types shown in ClipTrimSheet grid (in order)
    static var visibleInGrid: [ChartOverlayType] {
        [.route, .hrChart, .splits, .cadence, .strideLength, .verticalOscillation, .elevation, .intervals]
    }

    // Generic binned-bar chart panel (UIKit/CoreGraphics) — matches MetricBarPanelChart style.
    // Called from VideoExportService + PhotoSlideComposition.
    // useRangeBar=true (stride/VO): floating min~max bars. false (cadence): domainLo→avg bars.
    // elevation: area/line chart. All charts include X/Y axis labels + grid lines.
    static func renderGenericChartPanel(
        type: ChartOverlayType,
        series: [(offset: TimeInterval, value: Double)],
        panW: CGFloat, panH: CGFloat,
        panPad: CGFloat, panCR: CGFloat,
        vScale: CGFloat
    ) -> UIImage? {
        let useRangeBar: Bool
        switch type {
        case .strideLength, .verticalOscillation, .power, .groundContact: useRangeBar = true
        default: useRangeBar = false
        }
        let isElevation = (type == .elevation)

        let src = series.filter { $0.value > 0 }
        guard src.count >= 2 else { return nil }

        let t0    = src.first!.offset
        let dt    = max(1.0, src.last!.offset - t0)
        let dtMin = dt / 60.0
        let bN    = 80
        let bSz   = dt / Double(bN)

        struct Bucket { let id: Int; let avg: Double; let lo: Double; let hi: Double }
        let buckets: [Bucket] = (0..<bN).compactMap { i in
            let lo   = t0 + Double(i) * bSz
            let hi   = lo + bSz
            let vals = src
                .filter { $0.offset >= lo && ($0.offset < hi || (i == bN - 1 && $0.offset <= t0 + dt)) }
                .map(\.value)
            guard !vals.isEmpty else { return nil }
            return Bucket(id: i,
                          avg: vals.reduce(0, +) / Double(vals.count),
                          lo:  vals.min()!,
                          hi:  vals.max()!)
        }
        guard !buckets.isEmpty else { return nil }

        let avgAll = src.map(\.value).reduce(0, +) / Double(src.count)

        // Y domain
        let yLo: Double
        let yHi: Double
        if useRangeBar {
            let oMin = buckets.map(\.lo).min()!
            let oMax = buckets.map(\.hi).max()!
            let rng  = max(oMax - oMin, oMin * 0.02)
            yLo = max(0, oMin - rng * 0.4)
            yHi = oMax + rng * 0.2
        } else {
            let avgs = buckets.map(\.avg)
            let lo2  = avgs.min()!, hi2 = avgs.max()!
            let rng  = max(hi2 - lo2, lo2 * 0.02)
            yLo = max(0, lo2 - rng * 0.6)
            yHi = hi2 + rng * 0.2
        }
        let yRange = max(1e-6, yHi - yLo)

        // Number formatting
        let fmtY: (Double) -> String = { v in
            if isElevation { return String(format: "%.0fm", v) }
            if abs(v) >= 100 { return String(format: "%.0f", v) }
            if abs(v) >= 10  { return String(format: "%.1f", v) }
            return String(format: "%.2f", v)
        }
        let fmtX: (Double) -> String = { m in
            AppLanguage.shared.isEnglish
                ? String(format: "%.0fm", m)
                : String(format: "%.0f분", m)
        }

        // Fonts & colors
        let axisFont  = UIFont.monospacedDigitSystemFont(ofSize: 8 * vScale, weight: .regular)
        let axisColor = UIColor.white.withAlphaComponent(0.55)
        let axisAttrs: [NSAttributedString.Key: Any] = [.font: axisFont, .foregroundColor: axisColor]
        let lineColor = type.lineUIColor

        // Right-side Y label width
        let yLblW: CGFloat = [fmtY(yLo), fmtY(yHi), fmtY((yLo + yHi) / 2)]
            .map { ($0 as NSString).size(withAttributes: axisAttrs).width }
            .max()! + 5 * vScale

        let titleH: CGFloat = 12 * vScale
        let xLblH:  CGFloat = 12 * vScale
        let chartX: CGFloat = panPad
        let chartW: CGFloat = panW - chartX - yLblW - panPad
        let chartY: CGFloat = panPad + titleH
        let chartH: CGFloat = panH - chartY - xLblH - panPad * 0.5

        func ptY(_ v: Double) -> CGFloat { chartY + CGFloat(1 - (v - yLo) / yRange) * chartH }

        let yMarkCount = 4
        let yStep = (yHi - yLo) / Double(yMarkCount - 1)
        let xMarkCount = 4

        let imgFmt = UIGraphicsImageRendererFormat()
        imgFmt.scale = 1.0; imgFmt.opaque = false
        let rnd = UIGraphicsImageRenderer(size: CGSize(width: panW, height: panH), format: imgFmt)
        return rnd.image { ctx in
            let cg = ctx.cgContext

            // Background
            let bg = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: panW, height: panH), cornerRadius: panCR)
            UIColor.black.withAlphaComponent(0.40).setFill(); bg.fill()

            // Title
            let titleFont  = UIFont.systemFont(ofSize: 10 * vScale, weight: .semibold)
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont,
                                                              .foregroundColor: UIColor.white.withAlphaComponent(0.9)]
            let titleStr = AppLanguage.shared.s(type.chartTitleKo, type.chartTitleEn)
            (titleStr as NSString).draw(at: CGPoint(x: chartX, y: panPad), withAttributes: titleAttrs)

            // Horizontal grid lines + right Y labels
            for i in 0..<yMarkCount {
                let yVal = yLo + Double(i) * yStep
                let yPos = ptY(yVal)
                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.10).cgColor)
                cg.setLineWidth(0.5)
                cg.move(to: CGPoint(x: chartX, y: yPos))
                cg.addLine(to: CGPoint(x: chartX + chartW, y: yPos))
                cg.strokePath()
                let text = fmtY(yVal)
                let sz   = (text as NSString).size(withAttributes: axisAttrs)
                let ly   = min(chartY + chartH - sz.height, max(chartY, yPos - sz.height / 2))
                (text as NSString).draw(at: CGPoint(x: chartX + chartW + 3 * vScale, y: ly), withAttributes: axisAttrs)
            }

            // Vertical grid lines + bottom X labels
            for i in 0..<xMarkCount {
                let frac = Double(i) / Double(xMarkCount - 1)
                let xPos = chartX + CGFloat(frac) * chartW
                let tMin = frac * dtMin
                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.10).cgColor)
                cg.setLineWidth(0.5)
                cg.move(to: CGPoint(x: xPos, y: chartY))
                cg.addLine(to: CGPoint(x: xPos, y: chartY + chartH))
                cg.strokePath()
                let text = fmtX(tMin)
                let sz   = (text as NSString).size(withAttributes: axisAttrs)
                var lx   = xPos - sz.width / 2
                if i == 0 { lx = xPos }
                if i == xMarkCount - 1 { lx = xPos - sz.width }
                (text as NSString).draw(at: CGPoint(x: lx, y: chartY + chartH + 2 * vScale),
                                        withAttributes: axisAttrs)
            }

            // Chart content
            if isElevation {
                // Area/line chart (matches ElevationPanelChart)
                let ptX: (TimeInterval) -> CGFloat = { t in chartX + CGFloat((t - t0) / dt) * chartW }
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let gradColors = [lineColor.withAlphaComponent(0.35).cgColor,
                                  lineColor.withAlphaComponent(0.04).cgColor] as CFArray
                let gradient   = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0, 1])!

                let fillPath = CGMutablePath()
                fillPath.move(to: CGPoint(x: ptX(src[0].offset), y: chartY + chartH))
                fillPath.addLine(to: CGPoint(x: ptX(src[0].offset), y: ptY(src[0].value)))
                for pt in src.dropFirst() { fillPath.addLine(to: CGPoint(x: ptX(pt.offset), y: ptY(pt.value))) }
                fillPath.addLine(to: CGPoint(x: ptX(src.last!.offset), y: chartY + chartH))
                fillPath.closeSubpath()
                cg.saveGState()
                cg.addPath(fillPath); cg.clip()
                cg.drawLinearGradient(gradient,
                                      start: CGPoint(x: chartX, y: chartY),
                                      end:   CGPoint(x: chartX, y: chartY + chartH),
                                      options: [])
                cg.restoreGState()

                cg.setLineWidth(1.5 * vScale); cg.setLineCap(.round); cg.setLineJoin(.round)
                cg.setStrokeColor(lineColor.cgColor)
                cg.move(to: CGPoint(x: ptX(src[0].offset), y: ptY(src[0].value)))
                for pt in src.dropFirst() { cg.addLine(to: CGPoint(x: ptX(pt.offset), y: ptY(pt.value))) }
                cg.strokePath()

            } else {
                // Bar chart
                let barGap   = chartW / CGFloat(bN)
                let barW     = max(1.5 * vScale, barGap - 0.8 * vScale)
                let baseline = ptY(yLo)

                cg.setFillColor(lineColor.withAlphaComponent(0.80).cgColor)
                for bucket in buckets {
                    let bx = chartX + CGFloat(bucket.id) * barGap + (barGap - barW) / 2
                    if useRangeBar {
                        let topY = ptY(bucket.hi)
                        let botY = ptY(bucket.lo)
                        cg.fill(CGRect(x: bx, y: topY, width: barW, height: max(1.5 * vScale, botY - topY)))
                    } else {
                        let topY = ptY(bucket.avg)
                        cg.fill(CGRect(x: bx, y: topY, width: barW, height: max(1.5 * vScale, baseline - topY)))
                    }
                }

                // Avg dashed line
                let avgY = ptY(avgAll)
                cg.setStrokeColor(lineColor.withAlphaComponent(0.60).cgColor)
                cg.setLineWidth(1.2 * vScale)
                cg.setLineDash(phase: 0, lengths: [5 * vScale, 3 * vScale])
                cg.move(to: CGPoint(x: chartX, y: avgY))
                cg.addLine(to: CGPoint(x: chartX + chartW, y: avgY))
                cg.strokePath()
                cg.setLineDash(phase: 0, lengths: [])
            }
        }
    }
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
    // 기본값: 고딕 · 노란색(골드) · 대 · 타이핑 · 테두리(hasBorder)
    var fontChoice: OneLinerFont      = .gothic
    var textColor:  OneLinerTextColor = .gold
    var position:   CardPosition      = .bottom
    var sizeLevel:  TextSizeLevel     = .large
    var appearanceMode:   AppearanceMode   = .typing
    var decorEffect:      DecorEffect      = .none
    var hasBorder: Bool = true
    var flyDirection:     FlyInDirection   = .trailing
    /// 재생 배속. 1.0=원본. 0.5(슬로우)~2.0(패스트). 출력 길이 = trimmedDuration / speed.
    var speed:            Double            = 1.0
    /// 가로(landscape) 콘텐츠 좌우 크롭 위치. 0=왼쪽, 0.5=중앙, 1=오른쪽.
    var cropOffsetX:      CGFloat           = 0.5

    // ── 러닝 데이터 오버레이 (운동한 날 전용, 클립별) ─────────────────
    // P/D/T/B = 가로 그룹(pdtPosition 한 위치). 차트는 chartOverlayType 단일 선택(경로/심박수/기타).
    var metricPace:      Bool              = false   // P
    var metricDistance:  Bool              = false   // D
    var metricTime:      Bool              = false   // T
    var metricHeartRate: Bool              = false   // B
    var pdtPosition:     CardPosition      = .top
    var pdtSizeLevel:    TextSizeLevel     = .medium  // PDT 뱃지 크기 (소/중/대)
    var pdtAppearanceMode:  AppearanceMode = .fade    // PDT 등장 방식 (PDTB 전용)
    var pdtDecorEffect:     DecorEffect    = .none    // PDT 꾸밈 (페이드 모드)
    var pdtFlyDirection:    FlyInDirection = .trailing // PDT 날아오기 방향
    var dataAppearanceMode: AppearanceMode = .fade    // 차트 등장 방식
    var chartDecorEffect:   DecorEffect    = .none    // 차트 꾸밈 (페이드 모드)
    var chartFlyDirection:  FlyInDirection = .trailing // 차트 날아오기 방향
    var chartOverlayType: ChartOverlayType = .none    // 차트 오버레이 단일 선택
    var routePosition:  CardPosition = .bottomTrailing

    // 하위호환 computed 접근자 — 기존 코드가 showRoute/showHRChart를 읽고 쓸 수 있도록 유지
    var showRoute: Bool {
        get { chartOverlayType == .route }
        set { chartOverlayType = newValue ? .route : (chartOverlayType == .route ? .none : chartOverlayType) }
    }
    var showHRChart: Bool {
        get { chartOverlayType == .hrChart }
        set { chartOverlayType = newValue ? .hrChart : (chartOverlayType == .hrChart ? .none : chartOverlayType) }
    }

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
        recipes.reduce(0) { $0 + $1.trimmedDuration / max(0.1, $1.speed) }
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
                scaleFillTransform(naturalSize: natSz, preferredTransform: prefTf,
                                   cropOffsetX: recipe.cropOffsetX),
                at: insertAt)

            // 배속: 삽입된 구간을 리타임(출력 길이 = 트림 길이 / speed). 영상·오디오 동시.
            var outDur = clipRange.duration
            if abs(recipe.speed - 1.0) > 0.01 {
                outDur = CMTimeMultiplyByFloat64(clipRange.duration, multiplier: 1.0 / recipe.speed)
                let insertedRange = CMTimeRange(start: insertAt, duration: clipRange.duration)
                compVideo.scaleTimeRange(insertedRange, toDuration: outDur)
                compAudio?.scaleTimeRange(insertedRange, toDuration: outDur)
            }

            clips.append(ClipDescriptor(url: recipe.url, duration: recipe.trimmedDuration / recipe.speed,
                                        trimStart: recipe.trimStart, trimEnd: recipe.trimEnd))
            insertAt = CMTimeAdd(insertAt, outDur)
            clipIdx += 1
        }
        guard !clips.isEmpty else { throw MCError.noVideoTrack }


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
                                            preferredTransform: CGAffineTransform,
                                            cropOffsetX: CGFloat = 0.5) -> CGAffineTransform {
        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let dw    = abs(displayRect.width)
        let dh    = abs(displayRect.height)
        let scale = max(targetSize.width / dw, targetSize.height / dh)
        let txOff = (targetSize.width  - dw * scale) * cropOffsetX
        let tyOff = (targetSize.height - dh * scale) / 2

        var tf = preferredTransform
        tf.tx -= displayRect.origin.x
        tf.ty -= displayRect.origin.y
        tf = tf.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        tf = tf.concatenating(CGAffineTransform(translationX: txOff, y: tyOff))
        return tf
    }
}
