// 오버레이 카드 — 사진(4:5)·영상(9:16) 미리보기와 사진 출력.
// 렌더는 스탬프 카드의 StampStoryRenderView·stampClipsVideoPreview·makeStampStoryImage를 그대로 쓰고,
// 스탬프 자리에만 OverlayPhotosLayer를 넣는다(미리보기 = 출력, §5.8).
// 여백은 같은 화면의 문구와 같은 값: 사진 위 42pt·아래 20pt, 영상 위 54pt·아래 14pt (+대회 뱃지 높이).
// ⚠️ 오버레이 카드 전용.

import SwiftUI

extension ShareCardScreen {

    /// 로고 줄(대회 뱃지·날짜)용 데이터 — 러닝 지표는 그리지 않는다(A안).
    var overlayPreviewData: StampData {
        var d = stampPreviewData
        d.raceName = confirmedRaceName
        return d
    }

    /// 오버레이 사진 레이어 — 사진·영상 미리보기·출력 공용. 캔버스 폭·여백만 다르다.
    func overlayPhotosLayer(isVideo: Bool) -> AnyView {
        let extra = StampHeaderMark.extraTopInset(overlayPreviewData.raceName)
        return AnyView(OverlayPhotosLayer(
            slots: overlayVM.slots,
            canvasWidth: isVideo ? 375.0 * 9.0 / 16.0 : 300,
            canvasHeight: 375,
            topInset: (isVideo ? 54 : 42) + extra,
            bottomInset: isVideo ? 14 : 20))
    }

    /// 사진 템플릿의 기본 사진 — 상단 사진 스트립 선택(다른 카드와 같은 선택)을 따른다.
    var overlayBasePhoto: UIImage? {
        guard !storyPhotos.isEmpty else { return nil }
        let idx = max(0, min(cardPhotoIndex[.overlay] ?? 0, storyPhotos.count - 1))
        return storyPhotos[idx]
    }

    // MARK: - 미리보기

    @ViewBuilder
    var overlayCardPreview: some View {
        if template == .video {
            stampClipsVideoPreview(vm: overlayVM.media, data: overlayPreviewData,
                                   replacementLayer: overlayPhotosLayer(isVideo: true))
        } else {
            overlayPhotoPreview
        }
    }

    @ViewBuilder
    private var overlayPhotoPreview: some View {
        let media = overlayVM.media
        if let ph = overlayBasePhoto {
            let s       = max(300 / ph.size.width, 375 / ph.size.height)
            let excess  = max(0, ph.size.width * s - 300)
            let excessY = max(0, ph.size.height * s - 375)
            StampStoryRenderView(photo: ph, data: overlayPreviewData, vm: media,
                                 cropOffsetX: media.storyCropOffsetX,
                                 cropOffsetY: media.storyCropOffsetY,
                                 configOverride: media.currentConfig,
                                 replacementLayer: overlayPhotosLayer(isVideo: false))
                // 가로로 긴 사진은 좌우, 세로로 긴 사진은 위아래로 끌어 크롭 위치 조절 (스탬프 카드와 같은 동작)
                .gesture(excess > 0 || excessY > 0 ? DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        if overlayCropDragBase == nil {
                            overlayCropDragBase = CGPoint(x: media.storyCropOffsetX, y: media.storyCropOffsetY)
                        }
                        guard let base = overlayCropDragBase else { return }
                        if excess > 0 {
                            media.storyCropOffsetX = max(0, min(1, base.x - drag.translation.width / excess))
                        }
                        if excessY > 0 {
                            media.storyCropOffsetY = max(0, min(1, base.y - drag.translation.height / excessY))
                        }
                    }
                    .onEnded { _ in overlayCropDragBase = nil }
                : nil)
        } else {
            StampStoryRenderView(photo: nil, data: overlayPreviewData, vm: media,
                                 configOverride: media.currentConfig,
                                 replacementLayer: overlayPhotosLayer(isVideo: false))
        }
    }

    // MARK: - 사진 출력

    /// 미리보기와 같은 StampStoryRenderView를 300×375pt @3x로 렌더.
    func makeOverlayStoryImage() async -> UIImage? {
        let media = overlayVM.media
        let photo = overlayBasePhoto
        let cfg   = media.currentConfig
        let layer = overlayPhotosLayer(isVideo: false)
        // 첫 ImageRenderer 호출은 잘못된 이미지를 낼 수 있어 워밍업 후 50ms 대기(스탬프와 같은 패턴)
        _ = makeStampStoryImage(photo: photo, data: overlayPreviewData, vm: media,
                                cropOffsetX: media.storyCropOffsetX,
                                cropOffsetY: media.storyCropOffsetY,
                                configOverride: cfg, replacementLayer: layer)
        try? await Task.sleep(nanoseconds: 50_000_000)
        return makeStampStoryImage(photo: photo, data: overlayPreviewData, vm: media,
                                   cropOffsetX: media.storyCropOffsetX,
                                   cropOffsetY: media.storyCropOffsetY,
                                   configOverride: cfg, replacementLayer: layer)
    }
}
