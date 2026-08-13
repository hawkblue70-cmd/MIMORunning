// Placeable 카드 — 슬라이드 템플릿 미리보기·저장·빌드
//
// 슬라이드 영상(사진 여러 장 + Ken Burns 효과)에 특화된 코드.
// PlaceableVideoTemplate.swift에서 슬라이드 전용 섹션을 분리.

import SwiftUI

// MARK: — 9:16 클립 미리보기 고정 규격
private let kClipW:     CGFloat = 211      // 너비 (375 × 9/16)
private let kClipH:     CGFloat = 375      // 높이
private let kClipScale: CGFloat = 211.0 / PlaceableCard.cardWidth   // ≈ 0.703
private let kClipFullH: CGFloat = 533      // PlaceableCard 전체 높이 (kClipH / kClipScale)
private let kClipOvlH:  CGFloat = 264      // 오버레이 높이 (PlaceableCard.cardHeight × kClipScale)
private let kClipTopM:  CGFloat = 22       // MIMO 워드마크 상단 여백
private let kClipBotM:  CGFloat = 11       // 데이터 카드 하단 여백


// MARK: - 슬라이드 문구 오버레이 (사진 전환마다 진입 애니메이션)
// bgIdx 변경 시 .id(bgIdx)로 뷰를 재생성 → @State phase 리셋 → .task 재실행
private struct SlideTextOverlay: View {
    let activity: Activity?
    let text: String
    let style: PlaceableSlideClipStyle
    let previewW: CGFloat
    let cardH: CGFloat
    let isPlaying: Bool

    @State private var phase: Double = 0
    // 이미 진입 애니메이션을 재생했는지 추적 (일시정지→재개 시 중복 애니 방지)
    @State private var hasAnimated: Bool = false

    private var isFade:  Bool { style.appearanceMode == .fade }
    private var isFlyIn: Bool { style.appearanceMode == .flyIn }

    var body: some View {
        OneLinerCard(
            activity: activity,
            text: text,
            position: style.position,
            textColor: style.color,
            fontChoice: style.font,
            sizeLevel: style.sizeLevel,
            appearanceMode: style.appearanceMode,
            decorEffect: isFade ? style.decorEffect : .none,
            hasBorder: style.hasBorder,
            flyDirection: style.flyDirection,
            showDate: false,
            showBackground: false,
            showWordmark: false,
            chartBottomReserved: 15,
            cardHeightOverride: cardH,
            cardWidthOverride: previewW,
            safeTopInset: 54,
            safeBottomInset: 14,
            isStaticPreview: !(style.appearanceMode == .typing)
        )
        .frame(width: previewW, height: cardH)
        .opacity(isFade || isFlyIn ? phase : 1.0)
        .offset(flyOffset)
        .allowsHitTesting(false)
        .task {
            if isPlaying, isFade || isFlyIn {
                // 슬라이드 전환(bgIdx 변경)으로 뷰가 재생성된 경우 — 즉시 애니메이션
                hasAnimated = true
                phase = 0.0
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }
                withAnimation(animCurve) { phase = 1.0 }
            } else {
                // 정지 상태로 진입 — 즉시 표시, 아직 애니 미재생 상태로 표시
                phase = 1.0
                hasAnimated = false
            }
        }
        .onChange(of: isPlaying) { _, newVal in
            // 재생 시작 시점에 첫 번째 슬라이드의 애니메이션 트리거
            // (bgIdx=0이라 뷰 재생성 없이 isPlaying만 바뀌는 경우)
            guard newVal, !hasAnimated, isFade || isFlyIn else { return }
            hasAnimated = true
            phase = 0.0
            Task {
                try? await Task.sleep(for: .seconds(0.3))
                withAnimation(animCurve) { phase = 1.0 }
            }
        }
    }

    private var flyOffset: CGSize {
        guard isFlyIn else { return .zero }
        let t = (1.0 - phase) * 220.0
        switch style.flyDirection {
        case .leading:  return CGSize(width: -t, height: 0)
        case .trailing: return CGSize(width:  t, height: 0)
        case .bottom:   return CGSize(width: 0,  height: t)
        }
    }

    private var animCurve: Animation {
        switch style.appearanceMode {
        case .fade:  return .easeInOut(duration: 0.45)
        case .flyIn: return .spring(duration: 0.45, bounce: 0.20)
        default:     return .linear(duration: 0)
        }
    }
}

extension ShareCardScreen {

    // MARK: - Placeable 슬라이드 미리보기

    @ViewBuilder
    var placeableSlidePreview: some View {
        let cardIsTop: Bool = placeableVM.placeableLayout == .horizontal
            ? placeableVM.placeableHorizTextRow == .top
            : placeableVM.placeableMetricsPosition.isTop
        // currentText는 bgIdx 확정 후 블록 내에서 계산

        if !storyPhotos.isEmpty {
            // ① 배경: 선택 사진 항상 표시 (Stamp 슬라이드와 동일 패턴)
            //    [필수] isPlaying 여부와 무관하게 항상 렌더 — 재생 중 검은 화면 방지.
            //    isReady 조건만으로 OneLinerPreviewView를 표시하면 AVPlayerLayer 흑색이 정적 사진을 덮음.
            // 재생 중: progress 기반 인덱스, 정지: 선택된 인덱스 (stamp 슬라이드와 동일 패턴)
            let bgIdx    = previewPlayer.isPlaying
                ? min(Int(previewPlayer.progress * Double(storyPhotos.count)), storyPhotos.count - 1)
                : min(placeableCurrentPhotoIdx, storyPhotos.count - 1)
            let sp0      = storyPhotos[bgIdx]
            let sCropX   = placeableVM.placeableStoryCropOffsets[bgIdx]  ?? 0.5
            let sCropY   = placeableVM.placeableStoryCropOffsetsY[bgIdx] ?? 0.5
            let sp0Scale = max(kClipW / sp0.size.width, kClipH / sp0.size.height)
            let sp0ImgW  = sp0.size.width  * sp0Scale
            let sp0ImgH  = sp0.size.height * sp0Scale
            let sp0Ox    = -(sCropX * max(0, sp0ImgW - kClipW))
            let sp0Oy    = -(sCropY * max(0, sp0ImgH - kClipH))
            // Ken Burns: PhotoSlideComposition.kenBurns와 동일한 상수·공식으로 SwiftUI 구동
            let kbEndScale: CGFloat = 1.08
            let kbPanRange: CGFloat = 60.0          // PhotoSlideComposition.kbPanRange 동일
            let photoDur     = PhotoSlideComposition.placeableSlideDuration
            let totalDur     = photoDur * Double(max(1, storyPhotos.count))
            let photoStartT  = photoDur * Double(bgIdx)
            let photoProgress = CGFloat(max(0, min(1,
                (previewPlayer.progress * totalDur - photoStartT) / photoDur)))
            let kbScale: CGFloat = bgIdx % 2 == 0
                ? 1.0 + (kbEndScale - 1.0) * photoProgress
                : kbEndScale - (kbEndScale - 1.0) * photoProgress
            // Pan: 1080px 공간 → previewW 비율 변환 (PhotoSlideComposition.kenBurns 동일 공식)
            let kbPanX: CGFloat = {
                let panPt = kbPanRange * (kClipW / 1080)
                return bgIdx % 2 == 0
                    ? -panPt / 2 + panPt * photoProgress
                    :  panPt / 2 - panPt * photoProgress
            }()
            let isKB = previewPlayer.isPlaying
            // 현재 장(bgIdx)의 문구 — 재생 중에도 사진마다 올바른 텍스트 표시
            let currentText = placeableVM.placeableStoryTexts[bgIdx] ?? ""

            Color.black  // 필러박스 배경
                // 슬라이드 진입/사진 전환 시 전역 스타일 ↔ 클립 스타일 동기화
                .onChange(of: template, initial: true) { _, new in
                    guard new == .slide else { return }
                    placeableVM.syncGlobalsToSlideClip(placeableCurrentPhotoIdx)
                }
                .onChange(of: placeableCurrentPhotoIdx) { old, new in
                    guard template == .slide else { return }
                    placeableVM.saveGlobalsToSlideClip(old)
                    placeableVM.syncGlobalsToSlideClip(new)
                }
                // 스타일 컨트롤 변경 시 현재 클립에 즉시 저장
                .onChange(of: placeableVM.placeableStoryFont)        { _, _ in guard template == .slide else { return }; placeableVM.saveGlobalsToSlideClip(placeableCurrentPhotoIdx) }
                .onChange(of: placeableVM.placeableStoryColor)       { _, _ in guard template == .slide else { return }; placeableVM.saveGlobalsToSlideClip(placeableCurrentPhotoIdx) }
                .onChange(of: placeableVM.placeableStoryPosition)    { _, _ in guard template == .slide else { return }; placeableVM.saveGlobalsToSlideClip(placeableCurrentPhotoIdx) }
                .onChange(of: placeableVM.placeableStorySize)        { _, _ in guard template == .slide else { return }; placeableVM.saveGlobalsToSlideClip(placeableCurrentPhotoIdx) }
                .onChange(of: placeableVM.placeableStoryHasBorder)   { _, _ in guard template == .slide else { return }; placeableVM.saveGlobalsToSlideClip(placeableCurrentPhotoIdx) }
                .onChange(of: placeableVM.placeableSlideAppearance)  { _, _ in guard template == .slide else { return }; placeableVM.saveGlobalsToSlideClip(placeableCurrentPhotoIdx) }
                .onChange(of: placeableVM.slideDecorEffect)          { _, _ in guard template == .slide else { return }; placeableVM.saveGlobalsToSlideClip(placeableCurrentPhotoIdx) }
                .onChange(of: placeableVM.slideFlyDirection)         { _, _ in guard template == .slide else { return }; placeableVM.saveGlobalsToSlideClip(placeableCurrentPhotoIdx) }

            Image(uiImage: sp0)
                .resizable()
                .frame(width: sp0ImgW, height: sp0ImgH)
                .scaleEffect(isKB ? kbScale : 1.0, anchor: .center)
                .offset(x: sp0Ox + (isKB ? kbPanX : 0), y: sp0Oy)
                .frame(width: kClipW, height: kClipH, alignment: .topLeading)
                .clipped()
                .id(bgIdx)
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))

            // ③ SwiftUI 데이터 오버레이: 항상 표시 (재생 중에도 정적 카드 표시)
            //    OneLinerPreviewView(AVPlayerLayer) 제거 → 검은 화면 방지.
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
                heightOverride: cardIsTop ? kClipFullH : nil
            )
            .frame(width: PlaceableCard.cardWidth, height: cardIsTop ? kClipFullH : PlaceableCard.cardHeight)
            .scaleEffect(kClipScale, anchor: .center)
            .frame(width: kClipW, height: cardIsTop ? kClipH : kClipOvlH)
            .padding(.bottom, cardIsTop ? 0 : kClipBotM)
            .frame(width: kClipW, height: kClipH, alignment: cardIsTop ? .center : .bottom)

            if !currentText.isEmpty {
                SlideTextOverlay(
                    activity: activity,
                    text: currentText,
                    style: placeableVM.slideClipStyle(for: bgIdx),
                    previewW: kClipW,
                    cardH: kClipH,
                    isPlaying: previewPlayer.isPlaying
                )
                .id(bgIdx)
            }

            // 진행 바: 재생 중 또는 재생 후 표시
            if previewPlayer.isPlaying || previewPlayer.progress > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Theme.violet)
                        .frame(width: geo.size.width * previewPlayer.progress, height: 3)
                }
                .frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
                .padding(.horizontal, 8)
                .animation(.linear(duration: 0.1), value: previewPlayer.progress)
                .frame(width: kClipW, height: kClipH, alignment: .bottom)
                .padding(.bottom, 10)
            }

            // ④ 재생 버튼 / 빌드 스피너 (스탬프 슬라이드와 동일 패턴)
            // 미빌드 → ▶ 누르면 빌드 시작 후 자동 재생 / 빌드 중 → 스피너 / 준비됨 → 재생·일시정지
            if previewPlayer.isBuilding {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .padding(14)
                    .background(.black.opacity(0.45))
                    .clipShape(Circle())
            } else if previewPlayer.isReady {
                Button { previewPlayer.togglePlayPause() } label: {
                    Image(systemName: previewPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(previewPlayer.isPlaying ? 0 : 0.85))
                        .shadow(color: .black.opacity(0.5), radius: 8)
                }
                .buttonStyle(.plain)
            } else {
                Button { rebuildPlaceableSlidePreview(thenPlay: true) } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.85))
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

    // MARK: - Placeable 슬라이드 레시피·리빌드

    /// Placeable 슬라이드용 ClipRecipe 배열 — 스토리 문구·스타일을 사진별로 매핑.
    func makePlaceableSlideRecipes(for photos: [UIImage]) -> [ClipRecipe] {
        photos.enumerated().map { i, photo in
            var r = ClipRecipe(url: URL(fileURLWithPath: ""),
                               fullDuration: PhotoSlideComposition.placeableSlideDuration,
                               thumbnail: photo)
            let style          = placeableVM.slideClipStyle(for: i)
            r.lines            = [placeableVM.placeableStoryTexts[i] ?? ""]
            r.fontChoice       = style.font
            r.textColor        = style.color
            r.position         = style.position
            r.sizeLevel        = style.sizeLevel
            r.hasBorder        = style.hasBorder
            r.appearanceMode   = style.appearanceMode
            r.decorEffect      = style.appearanceMode == .fade ? style.decorEffect : .none
            r.flyDirection     = style.flyDirection
            r.cropOffsetX      = placeableVM.placeableStoryCropOffsets[i]  ?? 0.5
            r.cropOffsetY      = placeableVM.placeableStoryCropOffsetsY[i] ?? 0.5
            return r
        }
    }

    func rebuildPlaceableSlidePreview(thenPlay: Bool = false) {
        guard isPlaceable, template == .slide, !storyPhotos.isEmpty else { return }
        let photos = storyPhotos
        Task {
            let overlayIsTop = placeableVM.placeableLayout == .horizontal
                ? placeableVM.placeableHorizTextRow == .top
                : placeableVM.placeableMetricsPosition.isTop
            let overlay = makePlaceableDataOverlay(fullHeight: overlayIsTop)
            let recipes = makePlaceableSlideRecipes(for: photos)
            await previewPlayer.buildForPhotoSlides(
                photos: photos, recipes: recipes,
                activityDate: activity.date, showDate: false,
                dataOverlayImage: overlay,
                dataOverlayIsTop: overlayIsTop,
                forCardIndex: 1)
            if thenPlay { previewPlayer.play() }
        }
    }
}
