import SwiftUI
import AVFoundation
import Photos

// MARK: - PlaceableVideoTextOverlay
//
// 영상 재생 중 현재 클립의 문구를 SwiftUI로 오버레이하는 뷰.
// 스탬프 카드의 AnimatedStampLayer와 동일한 패턴:
//   • .fade / .flyIn  → phase(0→1) 전환으로 opacity·offset 애니메이션
//   • .typing         → EffectTextView(isStaticPreview: false)의 타이핑 애니메이션
//   • loopCounter     → 영상 루프·재생 시작 감지 → 뷰 재생성으로 애니메이션 재시작

private struct PlaceableVideoTextOverlay: View {
    let activity: Activity?
    let text: String
    let recipe: ClipRecipe
    let clipIdx: Int
    let pvScale: CGFloat
    let previewW: CGFloat
    let cardH: CGFloat
    let chartBottomReserved: CGFloat
    let chartTopReserved: CGFloat
    let previewProgress: Double
    let isVideoPlaying: Bool

    @State private var phase: Double = 0
    @State private var loopCounter: Int = 0

    private var videoCardH: CGFloat { PlaceableCard.cardWidth * 16.0 / 9.0 }

    private var animKey: String {
        "\(recipe.appearanceMode)-\(recipe.flyDirection)-\(loopCounter)-\(clipIdx)"
    }
    private var isFade:  Bool { recipe.appearanceMode == .fade }
    private var isFlyIn: Bool { recipe.appearanceMode == .flyIn }

    var body: some View {
        OneLinerCard(
            activity: activity,
            text: text,
            position:         recipe.position,
            textColor:        recipe.textColor,
            fontChoice:       recipe.fontChoice,
            sizeLevel:        recipe.sizeLevel,
            appearanceMode:   recipe.appearanceMode,
            decorEffect:      isFade ? recipe.decorEffect : .none,
            hasBorder:        recipe.hasBorder,
            plateOn:          recipe.plateOn,
            flyDirection:     recipe.flyDirection,
            plateColorPreset: recipe.plateColorPreset,
            showDate: false,
            showBackground: false,
            showWordmark: false,
            chartBottomReserved: chartBottomReserved,
            chartTopReserved: chartTopReserved,
            cardHeightOverride: videoCardH,
            isStaticPreview: !(recipe.appearanceMode == .typing)  // typing: EffectTextView 내장 애니메이션
        )
        .frame(width: PlaceableCard.cardWidth, height: videoCardH)
        .scaleEffect(pvScale, anchor: .center)
        .frame(width: previewW, height: cardH)
        .id("\(clipIdx)-\(loopCounter)")  // loopCounter 변경 시 뷰 재생성 → typing 타이핑 재시작
        .opacity(isFade || isFlyIn ? phase : 1.0)
        .offset(flyOffset)
        .allowsHitTesting(false)
        .task(id: animKey) {
            guard isFade || isFlyIn else { phase = 1.0; return }
            phase = 0.0
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            withAnimation(animCurve) { phase = 1.0 }
        }
        // 영상 루프백 감지: progress 0.85 이상 → 0.1 미만으로 급락
        .onChange(of: previewProgress) { old, new in
            if old > 0.85, new < 0.1 { loopCounter += 1 }
        }
        // 재생 버튼 누를 때 처음부터 시작하면 애니메이션 재시작
        .onChange(of: isVideoPlaying) { old, new in
            if !old, new, previewProgress < 0.1 { loopCounter += 1 }
        }
    }

    private var flyOffset: CGSize {
        guard isFlyIn else { return .zero }
        let t = (1.0 - phase) * 220.0 * pvScale
        switch recipe.flyDirection {
        case .leading:  return CGSize(width: -t, height: 0)
        case .trailing: return CGSize(width:  t, height: 0)
        case .bottom:   return CGSize(width: 0,  height: t)
        }
    }

    private var animCurve: Animation {
        switch recipe.appearanceMode {
        case .fade:  return .easeInOut(duration: 0.45)
        case .flyIn: return .spring(duration: 0.45, bounce: 0.20)
        default:     return .linear(duration: 0)
        }
    }
}

// MARK: - ShareCardScreen + Placeable 템플릿
//
// Placeable 카드(cardIndex == 0)의 미리보기·컨트롤·저장·내보내기 헬퍼.
// ShareCardScreen extension이므로 @State 등 부모 프로퍼티에 그대로 접근 가능.
//
// 파일별 담당:
//   PlaceableViewModel.swift      — @Observable 상태 (placeableVM)
//   PlaceableControls.swift       — 컨트롤 컴포넌트 (chip row, trim row 등)
//   PlaceableSection.swift        — 소형 UI 헬퍼 (free functions)
//   PlaceableVideoTemplate.swift  — 미리보기·저장·내보내기 (현재 파일)

extension ShareCardScreen {


    // MARK: - Placeable 카드 미리보기 (스토리·영상·슬라이드 분기)

    var placeableCardPreview: some View {
        AnyView(
            Group {
                if template == .slide {
                    let slideH    = cardSectionH
                    let slideW    = slideH * 9.0 / 16.0
                    let curIdx    = min(placeableCurrentPhotoIdx, max(0, storyPhotos.count - 1))
                    let slideExcess: CGFloat = {
                        guard storyPhotos.indices.contains(curIdx) else { return 0 }
                        let p = storyPhotos[curIdx]
                        let s = max(slideW / p.size.width, slideH / p.size.height)
                        return max(0, p.size.width * s - slideW)
                    }()
                    ZStack { placeableSlidePreview }
                        .gesture(
                            slideExcess > 0 ? DragGesture(minimumDistance: 1)
                                .onChanged { drag in
                                    if placeableVM.storyCropDragBase == nil {
                                        placeableVM.storyCropDragBase = placeableVM.placeableStoryCropOffsets[curIdx] ?? 0.5
                                    }
                                    guard let base = placeableVM.storyCropDragBase else { return }
                                    let newVal = max(0, min(1, base - drag.translation.width / slideExcess))
                                    placeableVM.placeableStoryCropOffsets[curIdx] = newVal
                                }
                                .onEnded { _ in
                                    placeableVM.storyCropDragBase = nil
                                    rebuildPlaceableSlidePreview()
                                }
                            : nil
                        )
                } else {
                    placeableNonSlideCardPreview
                }
            }
            .onTapGesture {
                if template == .video, previewPlayer.isReady {
                    if placeableVM.placeableVideoTextDirty {
                        Task { await loadPlaceablePreview(); previewPlayer.play() }
                    } else {
                        previewPlayer.togglePlayPause()
                    }
                } else if template == .slide, previewPlayer.isReady {
                    previewPlayer.togglePlayPause()
                }
            }
        )
    }

    @ViewBuilder
    var placeableNonSlideCardPreview: some View {
        ZStack {
            if template == .video, previewPlayer.isReady, previewPlayer.isPlaying,
               let vp = previewPlayer.player, let contentLayer = previewPlayer.contentLayer {
                let previewW: CGFloat  = cardSectionH * 9.0 / 16.0
                let pvScale:  CGFloat  = previewW / PlaceableCard.cardWidth
                let overlayH: CGFloat  = PlaceableCard.cardHeight * pvScale
                let cardH:    CGFloat  = cardSectionH
                let topMargin: CGFloat = cardH * 0.06
                let botMargin: CGFloat = cardH * 0.06

                // 검정 배경 (필러박스)
                Color.black

                // 영상 재생 — 비디오 레이어 (contentLayer는 차트/PDT 전용, 문구는 SwiftUI 오버레이 담당)
                OneLinerPreviewView(player: vp, contentLayer: contentLayer,
                                    renderSize: previewPlayer.renderSize)
                    .frame(width: previewW, height: cardH)
                    .overlay(alignment: .bottom) {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Theme.violet)
                                .frame(width: geo.size.width * previewPlayer.progress, height: 3)
                        }
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 10)
                    }

                LinearGradient(colors: [.black.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: previewW, height: 24)
                    .frame(width: previewW, height: cardH, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                    .frame(width: previewW, height: 24)
                    .frame(width: previewW, height: cardH, alignment: .bottom)

                HStack(spacing: 0) {
                    Text("MIMO")
                        .font(.system(size: 9 * pvScale, weight: .black))
                        .tracking(2)
                        .foregroundStyle(.white)
                    Text(" RUNNING")
                        .font(.system(size: 9 * pvScale, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.violet)
                }
                .shadow(color: .black.opacity(0.50), radius: 4, x: 0, y: 2)
                .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 1)
                .padding(.top, topMargin)
                .padding(.leading, 14 * pvScale)
                .frame(width: previewW, height: cardH, alignment: .topLeading)

                // 재생 중인 클립의 문구 — 스탬프 카드와 동일한 SwiftUI 오버레이 + 애니메이션 방식
                let playingClipIdx: Int = {
                    guard !placeableVM.placeableClipRecipes.isEmpty,
                          previewPlayer.duration > 0 else {
                        return min(placeableVM.selectedPlaceableClipIndex,
                                   max(0, placeableVM.placeableClipRecipes.count - 1))
                    }
                    let currentTime = previewPlayer.progress * previewPlayer.duration
                    var elapsed = 0.0
                    for (i, recipe) in placeableVM.placeableClipRecipes.enumerated() {
                        elapsed += recipe.trimmedDuration / max(0.1, recipe.speed)
                        if currentTime < elapsed { return i }
                    }
                    return placeableVM.placeableClipRecipes.count - 1
                }()
                let playRecipe = placeableVM.placeableClipRecipes.indices.contains(playingClipIdx)
                    ? placeableVM.placeableClipRecipes[playingClipIdx] : nil
                let playText = playRecipe?.lines.first ?? ""
                if !playText.isEmpty, let pr = playRecipe {
                    PlaceableVideoTextOverlay(
                        activity: activity,
                        text: playText,
                        recipe: pr,
                        clipIdx: playingClipIdx,
                        pvScale: pvScale,
                        previewW: previewW,
                        cardH: cardH,
                        chartBottomReserved: PlaceableCard.cardWidth * (16.0 / 9.0) * 0.06 + placeableVM.storyBottomReserved,
                        chartTopReserved: placeableVM.storyTopReserved,
                        previewProgress: previewPlayer.progress,
                        isVideoPlaying: previewPlayer.isPlaying
                    )
                }

                // SwiftUI 데이터 오버레이: PlaceableCard
                PlaceableCard(
                    activity: activity,
                    detail: detail,
                    routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                    photo: nil,
                    date: activity.date,
                    metricsPosition: placeableVM.placeableMetricsPosition,
                    accent: placeableVM.placeableAccent,
                    showBackground: false,
                    showWordmark: false,
                    shoeName: displayShoeName,
                    weather: condition?.weather,
                    size: placeableVM.placeableSize,
                    layout: placeableVM.placeableLayout,
                    horizTextRow: placeableVM.placeableHorizTextRow,
                    horizRoutePos: placeableVM.placeableHorizRoutePos
                )
                .frame(width: PlaceableCard.cardWidth, height: PlaceableCard.cardHeight)
                .scaleEffect(pvScale, anchor: .center)
                .frame(width: previewW, height: overlayH)
                .padding(.bottom, botMargin)
                .frame(width: previewW, height: cardH, alignment: .bottom)

            } else if template == .video {
                // 영상 템플릿 정지 대기: 재생 상태와 동일한 9:16 pillarbox 레이아웃
                let previewW: CGFloat  = cardSectionH * 9.0 / 16.0
                let pvScale:  CGFloat  = previewW / PlaceableCard.cardWidth
                let overlayH: CGFloat  = PlaceableCard.cardHeight * pvScale
                let cardH:    CGFloat  = cardSectionH
                let topMargin: CGFloat = cardH * 0.06
                let botMargin: CGFloat = cardH * 0.06
                let safeIdx_v = min(max(0, placeableVM.selectedPlaceableClipIndex),
                                    max(0, placeableVM.placeableClipRecipes.count - 1))
                let vText = placeableVM.placeableClipRecipes.indices.contains(safeIdx_v)
                    ? (placeableVM.placeableClipRecipes[safeIdx_v].lines.first ?? "") : ""

                Color.black

                if let thumb = videoPreviewImage {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: previewW, height: cardH)
                        .clipped()
                }

                LinearGradient(colors: [.black.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: previewW, height: 24)
                    .frame(width: previewW, height: cardH, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                    .frame(width: previewW, height: 24)
                    .frame(width: previewW, height: cardH, alignment: .bottom)

                HStack(spacing: 0) {
                    Text("MIMO")
                        .font(.system(size: 9 * pvScale, weight: .black))
                        .tracking(2)
                        .foregroundStyle(.white)
                    Text(" RUNNING")
                        .font(.system(size: 9 * pvScale, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.violet)
                }
                .shadow(color: .black.opacity(0.50), radius: 4, x: 0, y: 2)
                .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 1)
                .padding(.top, topMargin)
                .padding(.leading, 14 * pvScale)
                .frame(width: previewW, height: cardH, alignment: .topLeading)

                PlaceableCard(
                    activity: activity,
                    detail: detail,
                    routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                    photo: nil,
                    date: activity.date,
                    metricsPosition: placeableVM.placeableMetricsPosition,
                    accent: placeableVM.placeableAccent,
                    showBackground: false,
                    showWordmark: false,
                    shoeName: displayShoeName,
                    weather: condition?.weather,
                    size: placeableVM.placeableSize,
                    layout: placeableVM.placeableLayout,
                    horizTextRow: placeableVM.placeableHorizTextRow,
                    horizRoutePos: placeableVM.placeableHorizRoutePos
                )
                .frame(width: PlaceableCard.cardWidth, height: PlaceableCard.cardHeight)
                .scaleEffect(pvScale, anchor: .center)
                .frame(width: previewW, height: overlayH)
                .padding(.bottom, botMargin)
                .frame(width: previewW, height: cardH, alignment: .bottom)

                if !vText.isEmpty {
                    // 9:16 좌표계로 내보내기와 동일한 위치에 글자·음영판 표시
                    // 클립별 독립 속성(position·animation)을 recipe에서 직접 읽어 정적 프리뷰와 출력 일치.
                    // .id(safeIdx_v): 클립 전환 시 SwiftUI 뷰 재생성 → 애니메이션 재실행 보장.
                    let videoCardH  = PlaceableCard.cardWidth * 16.0 / 9.0  // ≈533pt
                    let vRecipe     = placeableVM.placeableClipRecipes[safeIdx_v]
                    OneLinerCard(
                        activity: activity,
                        text: vText,
                        position:         vRecipe.position,
                        textColor:        vRecipe.textColor,
                        fontChoice:       vRecipe.fontChoice,
                        sizeLevel:        vRecipe.sizeLevel,
                        appearanceMode:   vRecipe.appearanceMode,
                        decorEffect:      vRecipe.decorEffect,
                        hasBorder:        vRecipe.hasBorder,
                        plateOn:          vRecipe.plateOn,
                        flyDirection:     vRecipe.flyDirection,
                        plateColorPreset: vRecipe.plateColorPreset,
                        showDate: false,
                        showBackground: false,
                        showWordmark: false,
                        chartBottomReserved: PlaceableCard.cardWidth * (16.0 / 9.0) * 0.06 + placeableVM.storyBottomReserved,
                        chartTopReserved: placeableVM.storyTopReserved,
                        cardHeightOverride: videoCardH,
                        isStaticPreview: true
                    )
                    .frame(width: PlaceableCard.cardWidth, height: videoCardH)
                    .scaleEffect(pvScale, anchor: .center)
                    .frame(width: previewW, height: cardH)
                    .id(safeIdx_v)
                }

                if previewPlayer.isBuilding {
                    ProgressView().tint(.white)
                        .padding(14)
                        .background(.black.opacity(0.45))
                        .clipShape(Circle())
                } else if previewPlayer.isReady {
                    Button {
                        if placeableVM.placeableVideoTextDirty {
                            Task { await loadPlaceablePreview(); previewPlayer.play() }
                        } else {
                            previewPlayer.play()
                        }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.5), radius: 8)
                    }
                    .buttonStyle(.plain)
                }

            } else {
                placeableStoryPreview
            }
        }
    }

    // MARK: - Placeable 컨트롤 뷰 헬퍼

    // → PlaceableControls.swift: PlaceableStoryModeChipRowView
    var placeableStoryModeChipRow: some View {
        PlaceableStoryModeChipRowView(
            vm:               placeableVM,
            template:         template,
            onRender:         { await renderCard(showSpinner: false) },
            onSaveVideoClips: { savePlaceableVideoClips() },
            onLoadPreview:    { await loadPlaceablePreview() }
        )
    }

    var placeableStoryTextField: some View {
        PlaceableStoryTextFieldView(
            vm:               placeableVM,
            photoIndex:       placeableCurrentPhotoIdx,
            storyPhotosCount: storyPhotos.count,
            focused:          $placeableStoryFocused
        )
    }

    // → PlaceableControls.swift: PlaceableTrimRowView
    @ViewBuilder var placeableTrimRow: some View {
        PlaceableTrimRowView(
            vm:               placeableVM,
            onSaveVideoClips: { savePlaceableVideoClips() },
            onLoadPreview:    { await loadPlaceablePreview() }
        )
    }

    // → PlaceableControls.swift: PlaceableChipRowView
    var placeableChipRow: some View {
        PlaceableChipRowView(
            vm:       placeableVM,
            template: template,
            onRender: { await renderCard(showSpinner: false) }
        )
    }

    // MARK: - Placeable 영상 클립별 트림 행 (Athletic 스타일: 클립마다 레이블 + 슬라이더)

    @ViewBuilder
    var placeableVideoTrimRows: some View {
        let idx = min(max(0, placeableVM.selectedPlaceableClipIndex),
                      placeableVM.placeableClipRecipes.count - 1)
        if placeableVM.placeableClipRecipes.indices.contains(idx) {
            let recipe = placeableVM.placeableClipRecipes[idx]
            let maxSec = min(recipe.fullDuration, VideoExportService.trimDuration)
            let used   = max(0.0, recipe.trimEnd - recipe.trimStart)
            VStack(spacing: 4) {
                Text(AppLanguage.shared.s(
                    "\(trimFormatSec(recipe.trimStart)) – \(trimFormatSec(recipe.trimEnd))  ·  \(trimFormatSec(used)) 사용",
                    "\(trimFormatSec(recipe.trimStart)) – \(trimFormatSec(recipe.trimEnd))  ·  \(trimFormatSec(used)) used"
                ))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                TrimBarView(
                    duration: maxSec,
                    trimStart: Bindable(placeableVM).placeableClipRecipes[idx].trimStart,
                    trimEnd:   Bindable(placeableVM).placeableClipRecipes[idx].trimEnd,
                    onEditingEnded: {
                        savePlaceableVideoClips()
                        Task { await loadPlaceablePreview() }
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Placeable 미리보기 로드

    @MainActor
    func loadPlaceablePreview() async {
        guard !placeableVM.placeableClipRecipes.isEmpty else {
            previewPlayer.invalidate()
            videoPreviewImage = nil
            sourceVideoURL = nil
            return
        }

        let firstRecipe = placeableVM.placeableClipRecipes[0]
        videoPreviewImage = firstRecipe.thumbnail
        if let url = await resolvedURL(for: firstRecipe) {
            sourceVideoURL = url
            if videoPreviewImage == nil {
                videoPreviewImage = await VideoExportService.firstFrame(of: url)
            }
        }

        let previewVScale: CGFloat       = VideoExportService.targetSize.width / PlaceableCard.cardWidth
        let previewOverlayPadPx: CGFloat = VideoExportService.targetSize.height * 0.06
        let previewSafeBotPx: CGFloat    = max(CardVisual.videoSafeBottom,
                                               previewOverlayPadPx + placeableVM.storyBottomReserved * previewVScale)
        let previewSafeTopPx: CGFloat    = max(CardVisual.videoSafeTop,
                                               previewOverlayPadPx + placeableVM.storyTopReserved    * previewVScale)
        await previewPlayer.buildForVideoClips(
            recipes:          placeableVM.placeableClipRecipes,
            activityDate:     activity.date,
            showDate:         false,
            muteAudio:        placeableVM.placeableMuteAudio,
            safeTopOverride:  previewSafeTopPx,
            safeBotOverride:  previewSafeBotPx,
            wordmarkTopPad:   VideoExportService.targetSize.height * 0.06
        )
        // 빌드 중 mute 토글이 발생했을 경우 현재 상태를 재적용
        previewPlayer.setMuted(placeableVM.placeableMuteAudio)
        placeableVM.placeableVideoTextDirty = false
    }

    func fallbackToSingleClip() {
        Task { @MainActor in
            let idx = placeableVM.placeableClipRecipes.indices.contains(placeableVM.selectedPlaceableClipIndex)
                ? placeableVM.selectedPlaceableClipIndex : 0
            guard let srcURL = await resolvedURL(for: placeableVM.placeableClipRecipes[idx]) else { return }
            sourceVideoURL = srcURL
            videoPreviewImage = await VideoExportService.firstFrame(of: srcURL)
            if placeableVM.placeableClipRecipes.indices.contains(idx) {
                let previewVScale: CGFloat       = VideoExportService.targetSize.width / PlaceableCard.cardWidth
                let previewOverlayPadPx: CGFloat = VideoExportService.targetSize.height * 0.06
                let previewSafeBotPx: CGFloat    = max(CardVisual.videoSafeBottom,
                                                       previewOverlayPadPx + placeableVM.storyBottomReserved * previewVScale)
                let previewSafeTopPx: CGFloat    = max(CardVisual.videoSafeTop,
                                                       previewOverlayPadPx + placeableVM.storyTopReserved    * previewVScale)
                await previewPlayer.buildForVideoClips(
                    recipes: [placeableVM.placeableClipRecipes[idx]], activityDate: activity.date, showDate: false,
                    safeTopOverride: previewSafeTopPx,
                    safeBotOverride: previewSafeBotPx,
                    wordmarkTopPad:  VideoExportService.targetSize.height * 0.06)
            }
        }
    }

    func resolvedURL(for r: ClipRecipe) async -> URL? {
        if FileManager.default.fileExists(atPath: r.url.path) { return r.url }
        if let ua = r.resolvedAsset as? AVURLAsset { return ua.url }
        if let aid = r.assetIdentifier,
           let av = try? await MultiClipComposition.resolveAVAsset(assetID: aid),
           let ua = av as? AVURLAsset { return ua.url }
        return nil
    }
    // MARK: - Placeable 영상 클립 저장·복원

    var pvcPrefix: String { "pvc_\(activity.id.uuidString)_" }

    func savePlaceableVideoClips() {
        let ud = UserDefaults.standard
        let p  = pvcPrefix
        let valid = placeableVM.placeableClipRecipes.filter { $0.assetIdentifier != nil || $0.clipVideoRef != nil }
        guard !valid.isEmpty else { ud.removeObject(forKey: p + "clips"); return }
        let descs = valid.map { r in
            SavedClipDescriptor(
                assetID: r.assetIdentifier, clipVideoRef: r.clipVideoRef,
                photoRef: nil, thumbRef: r.thumbRef,
                trimStart: r.trimStart, trimEnd: r.trimEnd, fullDuration: r.fullDuration,
                lines: r.lines,
                fontID: r.fontChoice.rawValue, colorID: r.textColor.rawValue,
                anchorIdx: CardPosition.allCases.firstIndex(of: r.position),
                sizeID: r.sizeLevel.rawValue,
                effectID: "\(r.appearanceMode.rawValue)|\(r.decorEffect.rawValue)|B\(r.hasBorder ? 1 : 0)P\(r.plateOn ? 1 : 0)|\(r.flyDirection.rawValue)",
                plateColorID: r.plateColorPreset.rawValue, speed: r.speed,
                cropOffsetX: Double(r.cropOffsetX),
                metricPace: false, metricDistance: false,
                metricTime: false, metricHeartRate: false,
                pdtAnchorIdx: nil, showRoute: false, routeAnchorIdx: nil,
                showHRChart: false, chartTypeID: nil, pdtSizeID2: nil, dataEffectID: nil)
        }
        if let data = try? JSONEncoder().encode(descs) { ud.set(data, forKey: p + "clips") }
        ud.set(placeableVM.placeableMuteAudio, forKey: p + "mute")
    }

    func loadPlaceableVideoClips() {
        guard placeableVM.placeableClipRecipes.isEmpty else { return }
        let ud = UserDefaults.standard
        let p  = pvcPrefix
        guard let data  = ud.data(forKey: p + "clips"),
              let descs = try? JSONDecoder().decode([SavedClipDescriptor].self, from: data),
              !descs.isEmpty else { return }
        placeableVM.placeableMuteAudio = ud.bool(forKey: p + "mute")
        var restored: [ClipRecipe] = []
        for desc in descs {
            let thumb: UIImage? = desc.thumbRef.flatMap { ClipThumbStore.load(ref: $0) }
            let recipeURL: URL
            if let ref = desc.clipVideoRef,
               let stableURL = ClipVideoStore.fileURL(ref: ref),
               FileManager.default.fileExists(atPath: stableURL.path) {
                recipeURL = stableURL
            } else {
                recipeURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mimo_pvc_\(UUID().uuidString)")
            }
            var recipe = ClipRecipe(url: recipeURL, fullDuration: desc.fullDuration, thumbnail: thumb)
            recipe.trimStart       = desc.trimStart
            recipe.trimEnd         = desc.trimEnd
            recipe.lines           = desc.lines
            recipe.assetIdentifier = desc.assetID
            recipe.clipVideoRef    = desc.clipVideoRef
            recipe.thumbRef        = desc.thumbRef
            recipe.fontChoice      = OneLinerFont.migrate(desc.fontID)
            recipe.textColor       = desc.colorID.flatMap { OneLinerTextColor(rawValue: $0) } ?? .white
            if let idx = desc.anchorIdx, CardPosition.allCases.indices.contains(idx) {
                recipe.position = CardPosition.allCases[idx]
            }
            recipe.sizeLevel = desc.sizeID.flatMap { TextSizeLevel(rawValue: $0) } ?? .medium
            if let eid = desc.effectID, eid.contains("|") {
                let parts = eid.split(separator: "|", maxSplits: 3).map(String.init)
                recipe.appearanceMode = parts.count > 0 ? (AppearanceMode(rawValue: parts[0]) ?? .typing) : .typing
                recipe.decorEffect    = parts.count > 1 ? (DecorEffect(rawValue: parts[1]) ?? .none) : .none
                if parts.count > 2 {
                    let r = parts[2]
                    recipe.hasBorder = r.contains("B1")
                    recipe.plateOn   = r.contains("P1")
                }
                recipe.flyDirection = parts.count > 3 ? (FlyInDirection(rawValue: parts[3]) ?? .trailing) : .trailing
            }
            recipe.plateColorPreset = desc.plateColorID.flatMap { PlateColorPreset(rawValue: $0) } ?? .blackWhite
            recipe.speed            = desc.speed
            recipe.cropOffsetX      = CGFloat(desc.cropOffsetX)
            restored.append(recipe)
        }
        placeableVM.placeableClipRecipes = restored
        if let firstThumb = restored.first?.thumbnail { videoPreviewImage = firstThumb }
        if let first = restored.first {
            placeableVM.placeableSlideAppearance = first.appearanceMode
            placeableVM.slideDecorEffect         = first.decorEffect
            placeableVM.slideFlyDirection        = first.flyDirection
        }
    }

    // MARK: - Placeable 스타일·애니메이션 동기화

    func applyAnimationToVideoClips() {
        // 영상 모드: 클립별 독립 애니메이션 — 전역 덮어쓰기 금지
        guard template != .video else { return }
        for i in placeableVM.placeableClipRecipes.indices {
            placeableVM.placeableClipRecipes[i].appearanceMode = placeableVM.placeableSlideAppearance
            placeableVM.placeableClipRecipes[i].decorEffect    = placeableVM.placeableSlideAppearance == .fade ? placeableVM.slideDecorEffect : .none
            placeableVM.placeableClipRecipes[i].flyDirection   = placeableVM.slideFlyDirection
        }
    }

    /// 전역 문구 스타일(폰트·색상·크기·테두리·음영판)을 영상 클립 레시피 전체에 동기화.
    /// position 제외 — 클립별 독립 설정.
    func applyStyleToVideoClips() {
        guard isPlaceable, template == .video else { return }
        for i in placeableVM.placeableClipRecipes.indices {
            placeableVM.placeableClipRecipes[i].fontChoice       = placeableVM.placeableStoryFont
            placeableVM.placeableClipRecipes[i].textColor        = placeableVM.placeableStoryColor
            placeableVM.placeableClipRecipes[i].sizeLevel        = placeableVM.placeableStorySize
            placeableVM.placeableClipRecipes[i].hasBorder        = placeableVM.placeableStoryHasBorder
            placeableVM.placeableClipRecipes[i].plateOn          = placeableVM.placeableStoryPlateOn
            placeableVM.placeableClipRecipes[i].plateColorPreset = placeableVM.placeableStoryPlatePreset
        }
    }


    // PlaceableCard(showBackground: false) → UIImage @3x — 슬라이드 영상 CALayer 오버레이용.
    @MainActor
    func makePlaceableDataOverlay() -> UIImage? {
        let renderer = ImageRenderer(content:
            PlaceableCard(
                activity: activity,
                detail: detail,
                routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                photo: nil,
                date: activity.date,
                metricsPosition: placeableVM.placeableMetricsPosition,
                accent: placeableVM.placeableAccent,
                showBackground: false,
                showWordmark: false,
                shoeName: displayShoeName,
                weather: condition?.weather,
                size: placeableVM.placeableSize,
                layout: placeableVM.placeableLayout,
                horizTextRow: placeableVM.placeableHorizTextRow,
                horizRoutePos: placeableVM.placeableHorizRoutePos
            )
            .frame(width: PlaceableCard.cardWidth, height: PlaceableCard.cardHeight)
        )
        renderer.scale = 3.0
        return renderer.uiImage
    }
}
