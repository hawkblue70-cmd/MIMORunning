import SwiftUI
import AVFoundation
import Photos

// MARK: — 9:16 클립 미리보기 고정 규격
private let kClipW:     CGFloat = 211      // 너비 (375 × 9/16)
private let kClipH:     CGFloat = 375      // 높이
private let kClipScale: CGFloat = 211.0 / PlaceableCard.cardWidth   // ≈ 0.703
private let kClipFullH: CGFloat = 533      // PlaceableCard 전체 높이 (kClipH / kClipScale)
private let kClipOvlH:  CGFloat = 264      // 오버레이 높이 (PlaceableCard.cardHeight × kClipScale)
private let kClipTopM:  CGFloat = 22       // MIMO 워드마크 상단 여백
private let kClipBotM:  CGFloat = 14       // 데이터 카드 하단 여백

// MARK: - PlaceableVideoTextOverlay
//
// 영상 재생 중 현재 클립의 문구를 SwiftUI로 오버레이하는 뷰.
// 스탬프 카드의 AnimatedStampLayer와 동일한 패턴:
//   • .fade    → EffectTextView(isStaticPreview: false)가 opacity·pop·wobble 직접 처리
//   • .flyIn   → phase(0→1) 전환으로 opacity·offset 처리 (EffectTextView는 정적)
//   • .typing  → EffectTextView(isStaticPreview: false)의 타이핑 애니메이션
//   • loopCounter → 영상 루프·재생 시작 감지 → 뷰 재생성으로 애니메이션 재시작

private struct PlaceableVideoTextOverlay: View {
    let activity: Activity?
    let text: String
    let recipe: ClipRecipe
    let clipIdx: Int
    let previewW: CGFloat
    let cardH: CGFloat
    let previewProgress: Double
    let isVideoPlaying: Bool

    @State private var phase: Double = 0
    @State private var loopCounter: Int = 0

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
            flyDirection:     recipe.flyDirection,
            showBackground: false,
            showWordmark: false,
            chartBottomReserved: 15,
            cardHeightOverride: cardH,
            cardWidthOverride: previewW,
            safeTopInset: 54,
            safeBottomInset: 14,
            horizontalPadding: 14,
            isStaticPreview: recipe.appearanceMode == .flyIn  // flyIn만 정적(외부 phase 제어), fade·typing은 EffectTextView 직접 처리
        )
        .frame(width: previewW, height: cardH)
        .id("\(clipIdx)-\(loopCounter)")  // loopCounter 변경 시 뷰 재생성 → typing 타이핑 재시작
        .opacity(isFlyIn ? phase : 1.0)   // fade는 EffectTextView가 내부 opacity 담당, flyIn만 외부 phase 사용
        .offset(flyOffset)
        .allowsHitTesting(false)
        .task(id: animKey) {
            guard isFlyIn else { phase = 1.0; return }  // fade·typing: EffectTextView가 처리하므로 phase 불필요
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
        let t = (1.0 - phase) * 220.0
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
                    let slideExcessX: CGFloat = {
                        guard storyPhotos.indices.contains(curIdx) else { return 0 }
                        let p = storyPhotos[curIdx]
                        let s = max(slideW / p.size.width, slideH / p.size.height)
                        return max(0, p.size.width * s - slideW)
                    }()
                    let slideExcessY: CGFloat = {
                        guard storyPhotos.indices.contains(curIdx) else { return 0 }
                        let p = storyPhotos[curIdx]
                        let s = max(slideW / p.size.width, slideH / p.size.height)
                        return max(0, p.size.height * s - slideH)
                    }()
                    ZStack { placeableSlidePreview }
                        .frame(width: kClipW, height: kClipH)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .simultaneousGesture(
                            (slideExcessX > 0 || slideExcessY > 0) ? DragGesture(minimumDistance: 8)
                                .onChanged { drag in
                                    if placeableVM.storyCropDragBase == nil, placeableVM.storyCropDragBaseY == nil {
                                        if slideExcessX > 0 {
                                            guard abs(drag.predictedEndTranslation.width) <= abs(drag.translation.width) * 3.0 else { return }
                                            placeableVM.storyCropDragBase = placeableVM.placeableStoryCropOffsets[curIdx] ?? 0.5
                                        } else {
                                            placeableVM.storyCropDragBaseY = placeableVM.placeableStoryCropOffsetsY[curIdx] ?? 0.5
                                        }
                                    }
                                    if slideExcessX > 0, let base = placeableVM.storyCropDragBase {
                                        placeableVM.placeableStoryCropOffsets[curIdx] =
                                            max(0, min(1, base - drag.translation.width / slideExcessX))
                                    } else if slideExcessY > 0, let baseY = placeableVM.storyCropDragBaseY {
                                        placeableVM.placeableStoryCropOffsetsY[curIdx] =
                                            max(0, min(1, baseY - drag.translation.height / slideExcessY))
                                    }
                                }
                                .onEnded { _ in
                                    let didCrop = placeableVM.storyCropDragBase != nil || placeableVM.storyCropDragBaseY != nil
                                    placeableVM.storyCropDragBase  = nil
                                    placeableVM.storyCropDragBaseY = nil
                                    if didCrop { savePlaceableStoryOverlay(); rebuildPlaceableSlidePreview() }
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
        // @Observable previewPlayer + placeableVM 속성을 ZStack 진입 전에 모두 스냅샷.
        // ZStack 클로저 안에서 observation이 중간 상태를 읽어 PAC 크래시가 발생하는 것을 방지.
        let pvIsReady    = previewPlayer.isReady
        let pvIsPlaying  = previewPlayer.isPlaying
        let pvPlayer     = previewPlayer.player
        let pvLayer      = previewPlayer.contentLayer
        let pvProgress   = previewPlayer.progress
        let pvDuration   = previewPlayer.duration
        let pvIsBuilding = previewPlayer.isBuilding
        let pvRenderSize = previewPlayer.renderSize
        // placeableVM 스냅샷 — 이하 ZStack 안에서 placeableVM.* 직접 접근 금지
        let pvClipRecipes     = placeableVM.placeableClipRecipes
        let pvSelIdx          = placeableVM.selectedPlaceableClipIndex
        let pvMetricsPos      = placeableVM.placeableMetricsPosition
        let pvAccent          = placeableVM.placeableAccent
        let pvSize            = placeableVM.placeableSize
        let pvLayout          = placeableVM.placeableLayout
        let pvHorizTextRow    = placeableVM.placeableHorizTextRow
        let pvHorizRoutePos   = placeableVM.placeableHorizRoutePos
        // 가로 레이아웃은 HorizTextRow, 세로는 metricsPosition으로 상단 여부 판단
        let cardIsTop: Bool = pvLayout == .horizontal
            ? pvHorizTextRow == .top
            : pvMetricsPos.isTop
        // 상단 배치: 하단 kClipBotM 여백 확보를 위해 카드 높이를 kClipBotM만큼 줄임
        // → 날짜(footer)가 항상 동일 위치(프리뷰 하단에서 kClipBotM+14pt)에 표시되도록 보정
        let pvCardInnerH: CGFloat = kClipH - kClipBotM              // 364: 상단 배치 시 스케일 후 카드 높이
        let pvCardFullH:  CGFloat = pvCardInnerH / kClipScale        // ≈518: heightOverride (스케일 역산)
        ZStack {
            if isPlaceable, template == .video, pvIsReady, pvIsPlaying,
               let vp = pvPlayer, let contentLayer = pvLayer {
                Color.black

                OneLinerPreviewView(player: vp, contentLayer: contentLayer,
                                    renderSize: pvRenderSize)
                    .frame(width: kClipW, height: kClipH)
                    .overlay(alignment: .bottom) {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Theme.violet)
                                .frame(width: geo.size.width * pvProgress, height: 3)
                        }
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 10)
                    }

                LinearGradient(colors: [.black.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: kClipW, height: 24)
                    .frame(width: kClipW, height: kClipH, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                    .frame(width: kClipW, height: 24)
                    .frame(width: kClipW, height: kClipH, alignment: .bottom)

                MIMOWordmark(size: 11)
                .shadow(color: .black.opacity(0.50), radius: 4, x: 0, y: 2)
                .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 1)
                .padding(.top, kClipTopM)
                .padding(.leading, 14)
                .frame(width: kClipW, height: kClipH, alignment: .topLeading)

                // 재생 중인 클립의 문구 — 스냅샷된 pvClipRecipes 사용
                let playingClipIdx: Int = {
                    guard !pvClipRecipes.isEmpty, pvDuration > 0 else {
                        return min(pvSelIdx, max(0, pvClipRecipes.count - 1))
                    }
                    let currentTime = pvProgress * pvDuration
                    var elapsed = 0.0
                    for (i, recipe) in pvClipRecipes.enumerated() {
                        elapsed += recipe.trimmedDuration / max(0.1, recipe.speed)
                        if currentTime < elapsed { return i }
                    }
                    return pvClipRecipes.count - 1
                }()
                let playRecipe = pvClipRecipes.indices.contains(playingClipIdx)
                    ? pvClipRecipes[playingClipIdx] : nil
                let playText = playRecipe?.lines.first ?? ""
                if !playText.isEmpty, let pr = playRecipe {
                    PlaceableVideoTextOverlay(
                        activity: activity,
                        text: playText,
                        recipe: pr,
                        clipIdx: playingClipIdx,
                        previewW: kClipW,
                        cardH: kClipH,
                        previewProgress: pvProgress,
                        isVideoPlaying: pvIsPlaying
                    )
                }

                PlaceableCard(
                    activity: activity,
                    detail: detail,
                    routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                    photo: nil,
                    date: activity.date,
                    metricsPosition: pvMetricsPos,
                    accent: pvAccent,
                    showBackground: false,
                    showWordmark: false,
                    shoeName: displayShoeName,
                    weather: condition?.weather,
                    size: pvSize,
                    layout: pvLayout,
                    horizTextRow: pvHorizTextRow,
                    horizRoutePos: pvHorizRoutePos,
                    heightOverride: cardIsTop ? pvCardFullH : nil
                )
                .frame(width: PlaceableCard.cardWidth, height: cardIsTop ? pvCardFullH : PlaceableCard.cardHeight)
                .scaleEffect(kClipScale, anchor: .center)
                .frame(width: kClipW, height: cardIsTop ? pvCardInnerH : kClipOvlH)
                .padding(.bottom, kClipBotM)
                .frame(width: kClipW, height: kClipH, alignment: .bottom)

            } else if template == .video {
                // 영상 템플릿 정지 대기: 재생 상태와 동일한 9:16 pillarbox 레이아웃
                let safeIdx_v = min(max(0, pvSelIdx), max(0, pvClipRecipes.count - 1))
                let vText = pvClipRecipes.indices.contains(safeIdx_v)
                    ? (pvClipRecipes[safeIdx_v].lines.first ?? "") : ""

                Color.black

                if let thumb = videoPreviewImage {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: kClipW, height: kClipH)
                        .clipped()
                }

                LinearGradient(colors: [.black.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: kClipW, height: 24)
                    .frame(width: kClipW, height: kClipH, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                    .frame(width: kClipW, height: 24)
                    .frame(width: kClipW, height: kClipH, alignment: .bottom)

                MIMOWordmark(size: 11)
                .shadow(color: .black.opacity(0.50), radius: 4, x: 0, y: 2)
                .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 1)
                .padding(.top, kClipTopM)
                .padding(.leading, 14)
                .frame(width: kClipW, height: kClipH, alignment: .topLeading)

                PlaceableCard(
                    activity: activity,
                    detail: detail,
                    routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                    photo: nil,
                    date: activity.date,
                    metricsPosition: pvMetricsPos,
                    accent: pvAccent,
                    showBackground: false,
                    showWordmark: false,
                    shoeName: displayShoeName,
                    weather: condition?.weather,
                    size: pvSize,
                    layout: pvLayout,
                    horizTextRow: pvHorizTextRow,
                    horizRoutePos: pvHorizRoutePos,
                    heightOverride: cardIsTop ? pvCardFullH : nil
                )
                .frame(width: PlaceableCard.cardWidth, height: cardIsTop ? pvCardFullH : PlaceableCard.cardHeight)
                .scaleEffect(kClipScale, anchor: .center)
                .frame(width: kClipW, height: cardIsTop ? pvCardInnerH : kClipOvlH)
                .padding(.bottom, kClipBotM)
                .frame(width: kClipW, height: kClipH, alignment: .bottom)

                if !vText.isEmpty {
                    // 클립별 독립 속성을 스냅샷된 pvClipRecipes에서 읽음
                    let vRecipe = pvClipRecipes[safeIdx_v]
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
                        flyDirection:     vRecipe.flyDirection,
                        showBackground: false,
                        showWordmark: false,
                        chartBottomReserved: 15,
                        cardHeightOverride: kClipH,
                        cardWidthOverride: kClipW,
                        safeTopInset: 54,
                        safeBottomInset: 14,
                        horizontalPadding: 14,
                        isStaticPreview: true
                    )
                    .frame(width: kClipW, height: kClipH)
                    .id(safeIdx_v)
                }

                if pvIsBuilding {
                    ProgressView().tint(.white)
                        .padding(14)
                        .background(.black.opacity(0.45))
                        .clipShape(Circle())
                } else if pvIsReady {
                    // Button 액션 클로저는 탭 시 실행되므로 placeableVM 직접 접근 가능
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
        // 설정 변경 시 이전 내보내기 캐시 무효화 — ShareLink가 구버전 영상을 재사용하지 않도록.
        invalidatePlaceableVideoExport()
        guard !placeableVM.placeableClipRecipes.isEmpty else {
            previewPlayer.invalidate()
            videoPreviewImage = nil
            sourceVideoURL = nil
            return
        }
        // 빌드 전 현재 문구·스타일을 디스크에 반드시 저장.
        // 텍스트 바인딩 onChange 타이밍 미스로 저장이 빠질 수 있는 엣지케이스 방지.
        savePlaceableVideoClips()

        let firstRecipe = placeableVM.placeableClipRecipes[0]
        videoPreviewImage = firstRecipe.thumbnail
        if let url = await resolvedURL(for: firstRecipe) {
            sourceVideoURL = url
            if videoPreviewImage == nil {
                videoPreviewImage = await VideoExportService.firstFrame(of: url)
            }
        }

        // 문구는 PlaceableVideoTextOverlay(SwiftUI)가 렌더 → 비디오 컴포지션에서는 lines 제외
        let recipesForPreview: [ClipRecipe] = placeableVM.placeableClipRecipes.map { r in
            var empty = r; empty.lines = []; return empty
        }
        await previewPlayer.buildForVideoClips(
            recipes:          recipesForPreview,
            showWordmark:     false,
            muteAudio:        placeableVM.placeableMuteAudio,
            safeTopOverride:  CardVisual.videoSafeTop,
            safeBotOverride:  CardVisual.videoSafeBottom,
            forCardIndex:     1
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
                var emptyRecipe = placeableVM.placeableClipRecipes[idx]
                emptyRecipe.lines = []
                await previewPlayer.buildForVideoClips(
                    recipes: [emptyRecipe], showWordmark: false,
                    safeTopOverride: CardVisual.videoSafeTop,
                    safeBotOverride: CardVisual.videoSafeBottom)
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
        // 텍스트 별도 저장 — 스토리/슬라이드(pso_*_textsArr)와 동일한 패턴.
        // placeableVideoTexts가 비어 있으면 pvc_*_texts를 건드리지 않음.
        // 이유: 세션 중 video 템플릿을 열지 않으면 texts가 메모리에 로드되지 않은 상태로
        // onDisappear가 발화 → 빈 {}로 덮어쓰면 이전에 저장된 텍스트가 손실됨.
        let textsToSave = Dictionary(uniqueKeysWithValues:
            placeableVM.placeableVideoTexts.compactMap { idx, t in t.isEmpty ? nil : (String(idx), t) })
        if !textsToSave.isEmpty {
            if let data = try? JSONEncoder().encode(textsToSave) {
                ud.set(data, forKey: p + "texts")
            }
        }
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
                effectID: "\(r.appearanceMode.rawValue)|\(r.decorEffect.rawValue)|B\(r.hasBorder ? 1 : 0)|\(r.flyDirection.rawValue)",
                speed: r.speed,
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
        let ud = UserDefaults.standard
        let p  = pvcPrefix

        // ① 클립: 메모리에 없을 때만 UserDefaults에서 복원
        if placeableVM.placeableClipRecipes.isEmpty {
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
                    }
                    recipe.flyDirection = parts.count > 3 ? (FlyInDirection(rawValue: parts[3]) ?? .trailing) : .trailing
                }
                recipe.speed      = desc.speed
                recipe.cropOffsetX = CGFloat(desc.cropOffsetX)
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

        // ② 텍스트: placeableVideoTexts가 비어 있을 때만 UserDefaults에서 복원.
        // 클립이 메모리에 있어도 propagateClips 등으로 texts가 초기화된 경우를 복구하는 안전망.
        // texts가 이미 채워져 있으면 사용자 입력 중일 수 있으므로 덮어쓰지 않음.
        guard !placeableVM.placeableClipRecipes.isEmpty,
              placeableVM.placeableVideoTexts.isEmpty else { return }
        if let data = ud.data(forKey: p + "texts"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            let indexedTexts = Dictionary(uniqueKeysWithValues:
                dict.compactMap { k, v in v.isEmpty ? nil : Int(k).map { ($0, v) } })
            if !indexedTexts.isEmpty {
                placeableVM.placeableVideoTexts = indexedTexts
                for (i, text) in indexedTexts where placeableVM.placeableClipRecipes.indices.contains(i) {
                    placeableVM.placeableClipRecipes[i].lines = [text]
                }
            } else {
                // pvc_*_texts가 빈 dict → clip.lines에서 복원 (onDisappear 덮어쓰기 보정)
                placeableVM.placeableVideoTexts = Dictionary(uniqueKeysWithValues:
                    placeableVM.placeableClipRecipes.enumerated().compactMap { i, r in r.lines.first.map { (i, $0) } })
            }
        } else {
            // 레거시 호환: pvc_*_texts 없으면 clip.lines에서 복원
            placeableVM.placeableVideoTexts = Dictionary(uniqueKeysWithValues:
                placeableVM.placeableClipRecipes.enumerated().compactMap { i, r in r.lines.first.map { (i, $0) } })
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

    /// 전역 문구 스타일(폰트·색상·크기·테두리)을 영상 클립 레시피 전체에 동기화.
    /// position 제외 — 클립별 독립 설정.
    func applyStyleToVideoClips() {
        guard template == .video else { return }
        // isPlaceable 체크 제거: placeableClipRecipes만 수정하므로 다른 카드에서 호출해도 안전
        // (다른 카드가 활성일 때도 Placeable 클립 스타일을 동기화해야 카드 전환 시 올바르게 표시됨)
        for i in placeableVM.placeableClipRecipes.indices {
            placeableVM.placeableClipRecipes[i].fontChoice       = placeableVM.placeableStoryFont
            placeableVM.placeableClipRecipes[i].textColor        = placeableVM.placeableStoryColor
            placeableVM.placeableClipRecipes[i].sizeLevel        = placeableVM.placeableStorySize
            placeableVM.placeableClipRecipes[i].hasBorder        = placeableVM.placeableStoryHasBorder
        }
    }


    // PlaceableCard(showBackground: false) → UIImage @3x — 슬라이드 영상 CALayer 오버레이용.
    // fullHeight=true 시 9:16 비율(300×533pt)로 렌더링 → 데이터 상단 배치 시 CALayer가 전체 프레임을 덮음.
    @MainActor
    func makePlaceableDataOverlay(fullHeight: Bool = false) -> UIImage? {
        let cardH: CGFloat = fullHeight
            ? PlaceableCard.cardWidth * 16.0 / 9.0
            : PlaceableCard.cardHeight
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
                horizRoutePos: placeableVM.placeableHorizRoutePos,
                heightOverride: fullHeight ? cardH : nil
            )
            .frame(width: PlaceableCard.cardWidth, height: cardH)
        )
        renderer.scale = 3.0
        return renderer.uiImage
    }
}
