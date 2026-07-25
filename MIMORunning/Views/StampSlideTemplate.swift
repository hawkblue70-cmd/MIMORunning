// 스탬프 카드 — 슬라이드(사진 여러 장). 장마다 세트에서 다른 스탬프를 배정한다.
// 색은 세트 전체가 동일(장마다 색이 바뀌면 산만해짐).
// ⚠️ 스탬프 카드 전용.

import SwiftUI
import AVFoundation

// MARK: - StampSlideRenderView

/// 슬라이드 i번째 장 미리보기 — StampStoryRenderView 를 세트 템플릿으로 재사용.
struct StampSlideRenderView: View {
    @Bindable var vm: StampViewModel
    let data: StampData
    var index: Int = 0

    var body: some View {
        let recipes = vm.clipRecipes
        let photos  = recipes.compactMap { $0.thumbnail }
        let photo   = index < photos.count ? photos[index] : nil
        let cropX   = index < recipes.count ? recipes[index].cropOffsetX : 0.5
        StampStoryRenderView(
            photo: photo, data: data, vm: vm,
            cropOffsetX: cropX,
            configOverride: vm.photoConfig(at: index)
        )
    }
}

// MARK: - Slide editor panel

/// 스탬프 슬라이드 전용 편집 패널 — 사진 스트립만 표시.
/// 스탬프 설정은 StampControlsView 팝업으로 통합 관리.
struct StampSlideEditorPanel: View {
    @Bindable var vm: StampViewModel
    var onSave: () -> Void

    var body: some View {
        MultiClipEditorView(
            recipes: Bindable(vm).clipRecipes,
            isPhotoSlideMode: .constant(true),
            muteAudio: .constant(false),
            selectedClipIndex: $vm.selectedClipIndex,
            savedClipLines: [],
            availableMetrics: [],
            enabledMetricIDs: .constant(Set<String>()),
            onSave: onSave,
            isStoryMode: true,
            showTitle: false,
            openEditOnTap: false,
            videoTitle: .constant(""),
            titleStyle: .constant(OneLinerTitleStyle())
        )
        .padding(.horizontal, 24)
    }
}

// MARK: - Slide export

enum StampSlideError: Error {
    case noPhotos
    case overlayCountMismatch
    case writeFailed
}

/// 사진 배열 + 사진별 스탬프 오버레이 이미지 → 1080×1920 슬라이드 영상.
/// PhotoSlideComposition.exportAthleticSlide 와 동일한 구조이나,
/// 오버레이를 정적 1장이 아닌 사진별로 분리하고 도장 등장 애니메이션을 더한다.
/// entranceModes/flyDirections/textEntranceModes/textFlyDirections 는 사진별 배열.
/// 배열이 짧으면 마지막 값으로 채운다.
func exportStampSlide(
    photos: [UIImage],
    cropOffsets: [CGFloat] = [],
    stampOverlays: [UIImage],
    entranceModes: [StampEntranceMode],
    flyDirections: [FlyInDirection] = [],
    textOverlays: [UIImage?] = [],
    textEntranceModes: [StampEntranceMode] = [],
    textFlyDirections: [FlyInDirection] = [],
    logoOverlay: UIImage? = nil,
    clipDuration: Double
) async throws -> URL {
    guard !photos.isEmpty else { throw StampSlideError.noPhotos }
    guard stampOverlays.count == photos.count else { throw StampSlideError.overlayCountMismatch }

    func val<T>(_ arr: [T], _ i: Int, _ def: T) -> T {
        arr.isEmpty ? def : arr[min(i, arr.count - 1)]
    }

    let sz       = CGSize(width: 1080, height: 1920)
    let total    = Double(photos.count) * clipDuration
    let dissolve = 0.3   // PhotoSlideComposition.dissolveDuration 과 동일

    // ── 1. Black base video ────────────────────────────────────────────
    let baseURL = try await PhotoSlideComposition.writeBlackBaseVideo(size: sz, duration: total)
    defer { try? FileManager.default.removeItem(at: baseURL) }

    // ── 2. CALayer tree ────────────────────────────────────────────────
    let contentLayer = CALayer()
    contentLayer.frame = CGRect(origin: .zero, size: sz)

    func linearAnim(_ keyPath: String, keyTimes: [NSNumber], values: [Any]) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.beginTime             = AVCoreAnimationBeginTimeAtZero
        a.duration              = total
        a.calculationMode       = .linear
        a.fillMode              = .both
        a.isRemovedOnCompletion = false
        a.keyTimes              = keyTimes
        a.values                = values
        return a
    }

    // Ken Burns constants — matches PhotoSlideComposition private values
    let kbEndScale: CGFloat = 1.08
    let kbPanRange: CGFloat = 60.0
    let cx = sz.width / 2
    let cy = sz.height / 2

    for (i, photo) in photos.enumerated() {
        let cropX = i < cropOffsets.count ? cropOffsets[i] : 0.5
        let cg = PhotoSlideComposition.scaleFill(photo, to: sz, cropOffsetX: cropX)
        let sf = Double(i) * clipDuration / total
        let ef = Double(i + 1) * clipDuration / total

        // Photo layer: Ken Burns + cross-dissolve
        let pl             = CALayer()
        pl.frame           = CGRect(origin: .zero, size: sz)
        pl.contents        = cg
        pl.contentsGravity = .resize

        // Ken Burns — mirrors PhotoSlideComposition.kenBurns(idx:progress:)
        let startSc: CGFloat
        let endSc: CGFloat
        let startPanX: CGFloat
        let endPanX: CGFloat
        if i % 2 == 0 {
            startSc   = 1.0;              endSc   = kbEndScale
            startPanX = -kbPanRange / 2;  endPanX = kbPanRange / 2
        } else {
            startSc   = kbEndScale;       endSc   = 1.0
            startPanX = kbPanRange / 2;   endPanX = -kbPanRange / 2
        }

        let scKT: [NSNumber] = [NSNumber(value: sf), NSNumber(value: ef), 1.0]
        pl.add(linearAnim("transform.scale", keyTimes: scKT,
                          values: [NSNumber(value: Float(startSc)),
                                   NSNumber(value: Float(endSc)),
                                   NSNumber(value: Float(endSc))]),
               forKey: "kbScale")
        pl.add(linearAnim("position", keyTimes: scKT,
                          values: [NSValue(cgPoint: CGPoint(x: cx + startPanX, y: cy)),
                                   NSValue(cgPoint: CGPoint(x: cx + endPanX,   y: cy)),
                                   NSValue(cgPoint: CGPoint(x: cx + endPanX,   y: cy))]),
               forKey: "kbPos")

        // Cross-dissolve opacity
        let opKT: [NSNumber]
        let opVal: [Float]
        let fisFrac = max(sf - dissolve / total, 0.0)
        let fosFrac = ef - dissolve / total
        if i == 0 {
            opKT  = [0.0, NSNumber(value: fosFrac), NSNumber(value: ef), 1.0]
            opVal = [1.0, 1.0, 0.0, 0.0]
        } else if i == photos.count - 1 {
            opKT  = [0.0, NSNumber(value: fisFrac), NSNumber(value: sf), 1.0]
            opVal = [0.0, 0.0, 1.0, 1.0]
        } else {
            opKT  = [0.0, NSNumber(value: fisFrac), NSNumber(value: sf),
                     NSNumber(value: fosFrac), NSNumber(value: ef), 1.0]
            opVal = [0.0, 0.0, 1.0, 1.0, 0.0, 0.0]
        }
        pl.add(linearAnim("opacity", keyTimes: opKT, values: opVal), forKey: "opacity")
        contentLayer.addSublayer(pl)

        // 등장 애니메이션을 레이어에 주입하는 재사용 클로저
        // (스탬프·문구 레이어 각각 독립 모드로 호출. delay=스탬프 완료 후 등장 지연(초))
        let addEntranceAnim: (CALayer, StampEntranceMode, FlyInDirection, Double) -> Void = { layer, mode, dir, delay in
            let isLast  = i == photos.count - 1
            let effSf   = sf + delay / total     // 실제 등장 시작 시각 (지연 적용)
            let p1 = effSf + 0.15 / total
            let p2 = effSf + (0.15 + 0.45 * 0.40) / total
            let p3 = effSf + (0.15 + 0.45 * 0.70) / total
            let p4 = effSf + 0.60 / total

            // 등장 후 사진 crossfade 에 맞춰 사라지는 공통 opacity 키프레임
            let aOpKT: [NSNumber]
            let aOpVal: [Float]
            if isLast {
                aOpKT  = [0.0, NSNumber(value: effSf), NSNumber(value: p1),
                          NSNumber(value: p2), 1.0]
                aOpVal = [0.0, 0.0, 0.0, 1.0, 1.0]
            } else {
                aOpKT  = [0.0, NSNumber(value: effSf), NSNumber(value: p1),
                          NSNumber(value: p2), NSNumber(value: fosFrac),
                          NSNumber(value: ef), 1.0]
                aOpVal = [0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0]
            }

            switch mode {

            case .stamp:
                let scKT: [NSNumber] = [
                    0.0, NSNumber(value: effSf), NSNumber(value: p1),
                    NSNumber(value: p2), NSNumber(value: p3), NSNumber(value: p4), 1.0
                ]
                layer.add(linearAnim("transform.scale", keyTimes: scKT,
                                     values: [Float(1.0), Float(0.01), Float(1.6),
                                              Float(0.92), Float(1.04), Float(1.0), Float(1.0)]),
                          forKey: "stampScale")
                let rad = Float(-4.0 * Double.pi / 180.0)
                layer.add(linearAnim("transform.rotation.z",
                                     keyTimes: [0.0, NSNumber(value: effSf), NSNumber(value: p1),
                                                NSNumber(value: p3), NSNumber(value: p4), 1.0],
                                     values: [Float(0), Float(0), rad, Float(0), Float(0), Float(0)]),
                          forKey: "stampRot")
                layer.add(linearAnim("opacity", keyTimes: aOpKT, values: aOpVal),
                          forKey: "stampOpacity")

            case .fade:
                let fadeOpKT: [NSNumber]
                let fadeOpVal: [Float]
                if isLast {
                    fadeOpKT  = [0.0, NSNumber(value: effSf), NSNumber(value: p4), 1.0]
                    fadeOpVal = [0.0, 0.0, 1.0, 1.0]
                } else {
                    fadeOpKT  = [0.0, NSNumber(value: effSf), NSNumber(value: p4),
                                 NSNumber(value: fosFrac), NSNumber(value: ef), 1.0]
                    fadeOpVal = [0.0, 0.0, 1.0, 1.0, 0.0, 0.0]
                }
                layer.add(linearAnim("opacity", keyTimes: fadeOpKT, values: fadeOpVal),
                          forKey: "stampOpacity")

            case .flyIn:
                let transKey: String
                let startOffset: Double
                switch dir {
                case .leading:  transKey = "transform.translation.x"; startOffset = -Double(sz.width)
                case .trailing: transKey = "transform.translation.x"; startOffset =  Double(sz.width)
                case .bottom:   transKey = "transform.translation.y"; startOffset =  Double(sz.height)
                }
                let pFly    = effSf + 0.52 / total
                let pSettle = effSf + 0.60 / total
                layer.add(linearAnim(transKey,
                                     keyTimes: [0.0, NSNumber(value: effSf), NSNumber(value: p1),
                                                NSNumber(value: pFly), NSNumber(value: pSettle), 1.0],
                                     values: [NSNumber(value: startOffset),
                                              NSNumber(value: startOffset),
                                              NSNumber(value: startOffset),
                                              NSNumber(value: startOffset * -0.06),
                                              0.0, 0.0] as [NSNumber]),
                          forKey: "stampFlyTrans")
                layer.add(linearAnim("opacity", keyTimes: aOpKT, values: aOpVal),
                          forKey: "stampOpacity")

            case .none:
                // 비애니메이션: 사진과 동일한 opacity 따라감
                layer.add(linearAnim("opacity", keyTimes: opKT, values: opVal), forKey: "opacity")
            }
        }

        // 스탬프 오버레이 레이어
        guard let cgOverlay = stampOverlays[i].cgImage else { continue }
        let sl             = CALayer()
        sl.frame           = CGRect(origin: .zero, size: sz)
        sl.contents        = cgOverlay
        sl.contentsGravity = .resize
        sl.contentsScale   = 1.0
        let stampMode = val(entranceModes, i, .stamp)
        addEntranceAnim(sl, stampMode, val(flyDirections, i, .trailing), 0.0)
        contentLayer.addSublayer(sl)

        // 문구 오버레이 레이어 (선택 — textOverlays 미전달 시 건너뜀)
        // 스탬프 애니메이션(0.60s) 완료 후 등장
        if i < textOverlays.count,
           let textImg = textOverlays[i],
           let cgText = textImg.cgImage {
            let tl             = CALayer()
            tl.frame           = CGRect(origin: .zero, size: sz)
            tl.contents        = cgText
            tl.contentsGravity = .resize
            tl.contentsScale   = 1.0
            let stampAnimDur   = stampMode == .none ? 0.0 : 0.60
            addEntranceAnim(tl, val(textEntranceModes, i, .fade), val(textFlyDirections, i, .bottom), stampAnimDur)
            contentLayer.addSublayer(tl)
        }
    }

    // ── 2-끝. 워드마크·날짜 정적 레이어 (모든 슬라이드 위에 항상 표시) ───────
    if let logo = logoOverlay, let cgLogo = logo.cgImage {
        let ll             = CALayer()
        ll.frame           = CGRect(origin: .zero, size: sz)
        ll.contents        = cgLogo
        ll.contentsGravity = .resize
        ll.contentsScale   = 1.0
        contentLayer.addSublayer(ll)
    }

    // ── 3. Composition (exportAthleticSlide 와 동일 구조) ─────────────
    let videoLayer          = CALayer()
    videoLayer.frame        = CGRect(origin: .zero, size: sz)
    let exportParent        = CALayer()
    exportParent.frame      = CGRect(origin: .zero, size: sz)
    exportParent.isGeometryFlipped = true
    exportParent.addSublayer(videoLayer)
    exportParent.addSublayer(contentLayer)

    let bgAsset  = AVURLAsset(url: baseURL)
    let bgTracks = try await bgAsset.loadTracks(withMediaType: .video)
    guard let bgTrack = bgTracks.first else { throw StampSlideError.writeFailed }
    let bgRange  = try await bgTrack.load(.timeRange)

    let comp = AVMutableComposition()
    guard let ct = comp.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw StampSlideError.writeFailed }
    try ct.insertTimeRange(bgRange, of: bgTrack, at: .zero)

    let vcInstr               = AVMutableVideoCompositionInstruction()
    vcInstr.timeRange         = bgRange
    vcInstr.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: ct)]

    let videoComp              = AVMutableVideoComposition()
    videoComp.renderSize       = sz
    videoComp.frameDuration    = CMTimeMake(value: 1, timescale: 30)
    videoComp.instructions     = [vcInstr]
    videoComp.animationTool    = AVVideoCompositionCoreAnimationTool(
        postProcessingAsVideoLayer: videoLayer, in: exportParent)

    // ── 4. Export ──────────────────────────────────────────────────────
    let outURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("mimo_stamp_slide_\(UUID().uuidString).mov")
    try? FileManager.default.removeItem(at: outURL)

    guard let session = AVAssetExportSession(
        asset: comp, presetName: AVAssetExportPresetHEVCHighestQuality)
    else { throw StampSlideError.writeFailed }

    session.outputURL        = outURL
    session.outputFileType   = .mov
    session.videoComposition = videoComp
    session.timeRange        = bgRange

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        session.exportAsynchronously {
            switch session.status {
            case .completed: cont.resume()
            case .failed:    cont.resume(throwing: session.error ?? StampSlideError.writeFailed)
            case .cancelled: cont.resume(throwing: StampSlideError.writeFailed)
            default:         cont.resume(throwing: StampSlideError.writeFailed)
            }
        }
    }
    return outURL
}
