import SwiftUI
import AVFoundation
import Photos

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

    // MARK: - Placeable 슬라이드 미리보기

    @ViewBuilder
    var placeableSlidePreview: some View {
        let previewW: CGFloat  = cardSectionH * 9.0 / 16.0
        let pvScale:  CGFloat  = previewW / PlaceableCard.cardWidth
        let overlayH: CGFloat  = PlaceableCard.cardHeight * pvScale
        let cardH:    CGFloat  = cardSectionH
        let topMargin: CGFloat = cardH * 0.03
        let botMargin: CGFloat = cardH * 0.03
        let firstText: String  = placeableVM.placeableStoryTexts[0] ?? ""

        if !storyPhotos.isEmpty {
            Color.black

            if previewPlayer.isReady && previewPlayer.isPlaying,
               let sp = previewPlayer.player,
               let sl = previewPlayer.contentLayer {
                OneLinerPreviewView(player: sp, contentLayer: sl,
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
            } else {
                Image(uiImage: storyPhotos[0])
                    .resizable()
                    .scaledToFill()
                    .frame(width: previewW, height: cardH)
                    .clipped()

                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: previewW, height: 24)
                    .frame(width: previewW, height: cardH, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
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

                if !firstText.isEmpty {
                    OneLinerCard(
                        activity: activity,
                        text: firstText,
                        position: placeableVM.placeableStoryPosition,
                        textColor: placeableVM.placeableStoryColor,
                        fontChoice: placeableVM.placeableStoryFont,
                        sizeLevel: placeableVM.placeableStorySize,
                        appearanceMode: placeableVM.placeableSlideAppearance,
                        hasBorder: placeableVM.placeableStoryHasBorder,
                        plateOn: placeableVM.placeableStoryPlateOn,
                        plateColorPreset: placeableVM.placeableStoryPlatePreset,
                        showDate: false,
                        showBackground: false,
                        showWordmark: false,
                        chartBottomReserved: placeableVM.storyBottomReserved,
                        chartTopReserved: placeableVM.storyTopReserved
                    )
                    .frame(width: PlaceableCard.cardWidth, height: PlaceableCard.cardHeight)
                    .scaleEffect(pvScale, anchor: .center)
                    .frame(width: previewW, height: cardH)
                }
            }

            if previewPlayer.isBuilding {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else {
                Button { previewPlayer.togglePlayPause() } label: {
                    Image(systemName: previewPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(previewPlayer.isPlaying ? 0 : 0.85))
                        .shadow(color: .black.opacity(0.5), radius: 8)
                }
                .buttonStyle(.plain)
            }
        } else {
            PlaceableCard(
                activity: activity, detail: detail,
                routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                photo: nil, date: activity.date,
                metricsPosition: placeableVM.placeableMetricsPosition, accent: placeableVM.placeableAccent,
                shoeName: displayShoeName, weather: condition?.weather,
                size: placeableVM.placeableSize, layout: placeableVM.placeableLayout,
                horizTextRow: placeableVM.placeableHorizTextRow, horizRoutePos: placeableVM.placeableHorizRoutePos
            )
            if !previewPlayer.isBuilding {
                VStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.violet.opacity(0.7))
                    Text(AppLanguage.shared.s("사진을 추가해 슬라이드 영상을 만들어보세요",
                                              "Add photos to create a slide video"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
    }

    // MARK: - Placeable 카드 미리보기 (스토리·영상·슬라이드 분기)

    var placeableCardPreview: some View {
        AnyView(
            Group {
                if template == .slide {
                    ZStack { placeableSlidePreview }
                } else {
                    placeableNonSlideCardPreview
                }
            }
            .onTapGesture {
                if template == .video, previewPlayer.isReady {
                    previewPlayer.togglePlayPause()
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
                let topMargin: CGFloat = cardH * 0.03
                let botMargin: CGFloat = cardH * 0.03
                let safeIdx_p = min(max(0, placeableVM.selectedPlaceableClipIndex),
                                    max(0, placeableVM.placeableClipRecipes.count - 1))
                let pText = placeableVM.placeableClipRecipes.indices.contains(safeIdx_p)
                    ? (placeableVM.placeableClipRecipes[safeIdx_p].lines.first ?? "") : ""

                // 검정 배경 (필러박스)
                Color.black

                // 영상 재생 (CALayer 워드마크·문구 애니메이션은 내부 AVSynchronizedLayer에서 동작)
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

                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: previewW, height: 24)
                    .frame(width: previewW, height: cardH, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
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

                // SwiftUI 데이터 오버레이: 정지 상태와 동일한 위치에 표시
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

                if !pText.isEmpty {
                    OneLinerCard(
                        activity: activity,
                        text: pText,
                        position: placeableVM.placeableStoryPosition,
                        textColor: placeableVM.placeableStoryColor,
                        fontChoice: placeableVM.placeableStoryFont,
                        sizeLevel: placeableVM.placeableStorySize,
                        appearanceMode: placeableVM.placeableSlideAppearance,
                        decorEffect:    placeableVM.slideDecorEffect,
                        hasBorder: placeableVM.placeableStoryHasBorder,
                        plateOn: placeableVM.placeableStoryPlateOn,
                        flyDirection:   placeableVM.slideFlyDirection,
                        plateColorPreset: placeableVM.placeableStoryPlatePreset,
                        showDate: false,
                        showBackground: false,
                        showWordmark: false,
                        chartBottomReserved: placeableVM.storyBottomReserved,
                        chartTopReserved: placeableVM.storyTopReserved
                    )
                    .frame(width: PlaceableCard.cardWidth, height: PlaceableCard.cardHeight)
                    .scaleEffect(pvScale, anchor: .center)
                    .frame(width: previewW, height: PlaceableCard.cardHeight * pvScale)
                }

            } else if template == .video {
                // 영상 템플릿 정지 대기: 재생 상태와 동일한 9:16 pillarbox 레이아웃
                let previewW: CGFloat  = cardSectionH * 9.0 / 16.0
                let pvScale:  CGFloat  = previewW / PlaceableCard.cardWidth
                let overlayH: CGFloat  = PlaceableCard.cardHeight * pvScale
                let cardH:    CGFloat  = cardSectionH
                let topMargin: CGFloat = cardH * 0.03
                let botMargin: CGFloat = cardH * 0.03
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

                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: previewW, height: 24)
                    .frame(width: previewW, height: cardH, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
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
                    OneLinerCard(
                        activity: activity,
                        text: vText,
                        position: placeableVM.placeableStoryPosition,
                        textColor: placeableVM.placeableStoryColor,
                        fontChoice: placeableVM.placeableStoryFont,
                        sizeLevel: placeableVM.placeableStorySize,
                        appearanceMode: placeableVM.placeableSlideAppearance,
                        decorEffect:    placeableVM.slideDecorEffect,
                        hasBorder: placeableVM.placeableStoryHasBorder,
                        plateOn: placeableVM.placeableStoryPlateOn,
                        flyDirection:   placeableVM.slideFlyDirection,
                        plateColorPreset: placeableVM.placeableStoryPlatePreset,
                        showDate: false,
                        showBackground: false,
                        showWordmark: false,
                        chartBottomReserved: placeableVM.storyBottomReserved,
                        chartTopReserved: placeableVM.storyTopReserved
                    )
                    .frame(width: PlaceableCard.cardWidth, height: PlaceableCard.cardHeight)
                    .scaleEffect(pvScale, anchor: .center)
                    .frame(width: previewW, height: PlaceableCard.cardHeight * pvScale)
                }

                if previewPlayer.isBuilding {
                    ProgressView().tint(.white)
                        .padding(14)
                        .background(.black.opacity(0.45))
                        .clipShape(Circle())
                } else if previewPlayer.isReady {
                    Button {
                        previewPlayer.play()
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.5), radius: 8)
                    }
                    .buttonStyle(.plain)
                }

            } else {
                // 스토리 템플릿: 4:5 그대로
                PlaceableCard(
                    activity: activity,
                    detail: detail,
                    routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                    photo: photoFor(0),
                    date: activity.date,
                    metricsPosition: placeableVM.placeableMetricsPosition,
                    accent: placeableVM.placeableAccent,
                    shoeName: displayShoeName,
                    weather: condition?.weather,
                    size: placeableVM.placeableSize,
                    layout: placeableVM.placeableLayout,
                    horizTextRow: placeableVM.placeableHorizTextRow,
                    horizRoutePos: placeableVM.placeableHorizRoutePos
                )
                if !placeableCurrentText.isEmpty {
                    OneLinerCard(
                        activity: activity,
                        text: placeableCurrentText,
                        position: placeableVM.placeableStoryPosition,
                        textColor: placeableVM.placeableStoryColor,
                        fontChoice: placeableVM.placeableStoryFont,
                        sizeLevel: placeableVM.placeableStorySize,
                        appearanceMode: .typing,
                        hasBorder: placeableVM.placeableStoryHasBorder,
                        plateOn: placeableVM.placeableStoryPlateOn,
                        plateColorPreset: placeableVM.placeableStoryPlatePreset,
                        showDate: false,
                        showBackground: false,
                        showWordmark: false,
                        chartBottomReserved: placeableVM.storyBottomReserved,
                        chartTopReserved: placeableVM.storyTopReserved
                    )
                    .frame(width: 300, height: 375)
                }
            }
        }
    }

    // MARK: - Placeable 정적 내보내기 뷰

    // text: 사진별 문구. nil이면 placeableCurrentText(현재 선택 사진 문구) 사용.
    @ViewBuilder
    func placeableExportView(photo: UIImage?, text: String? = nil) -> some View {
        let overlayText = text ?? placeableCurrentText
        ZStack {
            PlaceableCard(
                activity: activity,
                detail: detail,
                routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                photo: photo,
                date: activity.date,
                metricsPosition: placeableVM.placeableMetricsPosition,
                accent: placeableVM.placeableAccent,
                shoeName: displayShoeName,
                weather: condition?.weather,
                size: placeableVM.placeableSize,
                layout: placeableVM.placeableLayout,
                horizTextRow: placeableVM.placeableHorizTextRow,
                horizRoutePos: placeableVM.placeableHorizRoutePos
            )
            if (template == .story || template == .video), !overlayText.isEmpty {
                OneLinerCard(
                    activity: activity,
                    text: overlayText,
                    position: placeableVM.placeableStoryPosition,
                    textColor: placeableVM.placeableStoryColor,
                    fontChoice: placeableVM.placeableStoryFont,
                    sizeLevel: placeableVM.placeableStorySize,
                    appearanceMode: .typing,
                    hasBorder: placeableVM.placeableStoryHasBorder,
                    plateOn: placeableVM.placeableStoryPlateOn,
                    plateColorPreset: placeableVM.placeableStoryPlatePreset,
                    showDate: false,
                    showBackground: false,
                    chartBottomReserved: placeableVM.storyBottomReserved,
                    chartTopReserved: placeableVM.storyTopReserved
                )
            }
        }
        .frame(width: 300, height: 375)
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

    // MARK: - Placeable 미리보기 로드

    @MainActor
    func loadPlaceablePreview() async {
        guard !placeableVM.placeableClipRecipes.isEmpty else {
            previewPlayer.invalidate()
            videoPreviewImage = nil
            sourceVideoURL = nil
            return
        }

        if let thumb = await resolvedURL(for: placeableVM.placeableClipRecipes[0]) {
            sourceVideoURL = thumb
            if videoPreviewImage == nil {
                videoPreviewImage = await VideoExportService.firstFrame(of: thumb)
            }
        }

        let previewVScale: CGFloat       = VideoExportService.targetSize.width / PlaceableCard.cardWidth
        let previewOverlayPadPx: CGFloat = VideoExportService.targetSize.height * 0.03
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
            safeBotOverride:  previewSafeBotPx
        )
    }

    func fallbackToSingleClip() {
        Task { @MainActor in
            let idx = placeableVM.placeableClipRecipes.indices.contains(placeableVM.selectedPlaceableClipIndex)
                ? placeableVM.selectedPlaceableClipIndex : 0
            guard let srcURL = await resolvedURL(for: placeableVM.placeableClipRecipes[idx]) else { return }
            sourceVideoURL = srcURL
            videoPreviewImage = await VideoExportService.firstFrame(of: srcURL)
            if placeableVM.placeableClipRecipes.indices.contains(idx) {
                await previewPlayer.buildForVideoClips(
                    recipes: [placeableVM.placeableClipRecipes[idx]], activityDate: activity.date, showDate: false)
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

    // MARK: - Placeable 스토리 오버레이 저장·복원

    var psoPrefix: String { "pso_\(activity.id.uuidString)_" }

    func loadPlaceableStoryOverlay() {
        let ud = UserDefaults.standard
        let p  = psoPrefix
        if let data = ud.data(forKey: p + "textsArr"),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            placeableVM.placeableStoryTexts = Dictionary(uniqueKeysWithValues:
                arr.enumerated().compactMap { i, t in t.isEmpty ? nil : (i, t) })
        } else if let t = ud.string(forKey: p + "text"), !t.isEmpty {
            placeableVM.placeableStoryTexts = [0: t]
        }
        if let f = ud.string(forKey: p + "font"),  let fv = OneLinerFont(rawValue: f)         { placeableVM.placeableStoryFont        = fv }
        if let c = ud.string(forKey: p + "color"), let cv = OneLinerTextColor(rawValue: c)    { placeableVM.placeableStoryColor       = cv }
        if let s = ud.string(forKey: p + "size"),  let sv = TextSizeLevel(rawValue: s)        { placeableVM.placeableStorySize        = sv }
        let posIdx = ud.integer(forKey: p + "pos")
        let posAll = Array(CardPosition.allCases)
        if posIdx >= 0, posIdx < posAll.count { placeableVM.placeableStoryPosition = posAll[posIdx] }
        if let bv = ud.object(forKey: p + "border") as? Bool { placeableVM.placeableStoryHasBorder = bv }
        if let pv = ud.object(forKey: p + "plate")  as? Bool { placeableVM.placeableStoryPlateOn   = pv }
        if let pr = ud.string(forKey: p + "platePreset"), let pv = PlateColorPreset(rawValue: pr) { placeableVM.placeableStoryPlatePreset = pv }
    }

    func savePlaceableStoryOverlay() {
        let ud = UserDefaults.standard
        let p  = psoPrefix
        let maxIdx = placeableVM.placeableStoryTexts.keys.max() ?? 0
        var arr = Array(repeating: "", count: maxIdx + 1)
        for (idx, text) in placeableVM.placeableStoryTexts where idx <= maxIdx { arr[idx] = text }
        if let data = try? JSONEncoder().encode(arr) { ud.set(data, forKey: p + "textsArr") }
        ud.set(placeableVM.placeableStoryFont.rawValue,               forKey: p + "font")
        ud.set(placeableVM.placeableStoryColor.rawValue,              forKey: p + "color")
        ud.set(placeableVM.placeableStorySize.rawValue,               forKey: p + "size")
        let posAll = Array(CardPosition.allCases)
        ud.set(posAll.firstIndex(of: placeableVM.placeableStoryPosition) ?? 0, forKey: p + "pos")
        ud.set(placeableVM.placeableStoryHasBorder,                   forKey: p + "border")
        ud.set(placeableVM.placeableStoryPlateOn,                     forKey: p + "plate")
        ud.set(placeableVM.placeableStoryPlatePreset.rawValue,        forKey: p + "platePreset")
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

    // MARK: - Placeable 슬라이드·스타일 헬퍼

    /// Placeable 슬라이드용 ClipRecipe 배열 — 스토리 문구·스타일을 사진별로 매핑.
    func makePlaceableSlideRecipes(for photos: [UIImage]) -> [ClipRecipe] {
        photos.enumerated().map { i, photo in
            var r = ClipRecipe(url: URL(fileURLWithPath: ""),
                               fullDuration: PhotoSlideComposition.placeableSlideDuration,
                               thumbnail: photo)
            r.lines            = [placeableVM.placeableStoryTexts[i] ?? ""]
            r.fontChoice       = placeableVM.placeableStoryFont
            r.textColor        = placeableVM.placeableStoryColor
            r.position         = placeableVM.placeableStoryPosition
            r.sizeLevel        = placeableVM.placeableStorySize
            r.hasBorder        = placeableVM.placeableStoryHasBorder
            r.plateOn          = placeableVM.placeableStoryPlateOn
            r.plateColorPreset = placeableVM.placeableStoryPlatePreset
            r.appearanceMode   = placeableVM.placeableSlideAppearance
            r.decorEffect      = placeableVM.placeableSlideAppearance == .fade ? placeableVM.slideDecorEffect : .none
            r.flyDirection     = placeableVM.slideFlyDirection
            return r
        }
    }

    func applyAnimationToVideoClips() {
        for i in placeableVM.placeableClipRecipes.indices {
            placeableVM.placeableClipRecipes[i].appearanceMode = placeableVM.placeableSlideAppearance
            placeableVM.placeableClipRecipes[i].decorEffect    = placeableVM.placeableSlideAppearance == .fade ? placeableVM.slideDecorEffect : .none
            placeableVM.placeableClipRecipes[i].flyDirection   = placeableVM.slideFlyDirection
        }
    }

    /// 전역 문구 스타일(위치·폰트·색상·크기·테두리·음영판)을 영상 클립 레시피 전체에 동기화.
    func applyStyleToVideoClips() {
        guard isPlaceable, template == .video else { return }
        for i in placeableVM.placeableClipRecipes.indices {
            placeableVM.placeableClipRecipes[i].position        = placeableVM.placeableStoryPosition
            placeableVM.placeableClipRecipes[i].fontChoice       = placeableVM.placeableStoryFont
            placeableVM.placeableClipRecipes[i].textColor        = placeableVM.placeableStoryColor
            placeableVM.placeableClipRecipes[i].sizeLevel        = placeableVM.placeableStorySize
            placeableVM.placeableClipRecipes[i].hasBorder        = placeableVM.placeableStoryHasBorder
            placeableVM.placeableClipRecipes[i].plateOn          = placeableVM.placeableStoryPlateOn
            placeableVM.placeableClipRecipes[i].plateColorPreset = placeableVM.placeableStoryPlatePreset
        }
    }

    func rebuildPlaceableSlidePreview() {
        guard isPlaceable, template == .slide, !storyPhotos.isEmpty else { return }
        let photos = storyPhotos
        Task {
            let overlay = makePlaceableDataOverlay()
            let recipes = makePlaceableSlideRecipes(for: photos)
            await previewPlayer.buildForPhotoSlides(
                photos: photos, recipes: recipes,
                activityDate: activity.date, showDate: false,
                dataOverlayImage: overlay)
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
