// Placeable 카드 — 스토리 템플릿 미리보기·내보내기
//
// 4:5 스토리(단일 사진 배경 + OneLiner 문구 오버레이) 전용 코드.
// 저장·복원 → PlaceablePersistence.swift. PlaceableVideoTemplate.swift에서 스토리 전용 섹션을 분리.

import SwiftUI

extension ShareCardScreen {

    // MARK: - Placeable 스토리 미리보기
    //
    // placeableNonSlideCardPreview 의 else 분기에서 호출.
    // ZStack 내에서 복수 뷰를 emit — PlaceableCard (배경) + OneLinerCard (오버레이).

    @ViewBuilder
    var placeableStoryPreview: some View {
        let storyPhoto = photoFor(1)
        let storyCropX = placeableVM.placeableStoryCropOffsets[placeableCurrentPhotoIdx]  ?? 0.5
        let storyCropY = placeableVM.placeableStoryCropOffsetsY[placeableCurrentPhotoIdx] ?? 0.5
        let storyExcessX: CGFloat = {
            guard let p = storyPhoto else { return 0 }
            let s = max(300 / p.size.width, 375 / p.size.height)
            return max(0, p.size.width * s - 300)
        }()
        let storyExcessY: CGFloat = {
            guard let p = storyPhoto else { return 0 }
            let s = max(300 / p.size.width, 375 / p.size.height)
            return max(0, p.size.height * s - 375)
        }()
        PlaceableCard(
            activity: activity,
            detail: detail,
            routeCoords: routeCoords.isEmpty ? nil : routeCoords,
            photo: storyPhoto,
            date: activity.date,
            metricsPosition: placeableVM.placeableMetricsPosition,
            accent: placeableVM.placeableAccent,
            showWordmark: false,
            shoeName: displayShoeName,
            weather: condition?.weather,
            size: placeableVM.placeableSize,
            layout: placeableVM.placeableLayout,
            horizTextRow: placeableVM.placeableHorizTextRow,
            horizRoutePos: placeableVM.placeableHorizRoutePos,
            cropOffsetX: storyCropX,
            cropOffsetY: storyCropY
        )
        .simultaneousGesture(
            (storyExcessX > 0 || storyExcessY > 0) ? DragGesture(minimumDistance: 8)
                .onChanged { drag in
                    if placeableVM.storyCropDragBase == nil, placeableVM.storyCropDragBaseY == nil {
                        if storyExcessX > 0 {
                            // 가로 초과: 빠른 수평 스와이프는 카드 전환에 양보
                            guard abs(drag.predictedEndTranslation.width) <= abs(drag.translation.width) * 3.0 else { return }
                            placeableVM.storyCropDragBase = storyCropX
                        } else {
                            // 세로 초과: 수직 드래그, 카드 전환과 충돌 없음
                            placeableVM.storyCropDragBaseY = storyCropY
                        }
                    }
                    if storyExcessX > 0, let base = placeableVM.storyCropDragBase {
                        placeableVM.placeableStoryCropOffsets[placeableCurrentPhotoIdx] =
                            max(0, min(1, base - drag.translation.width / storyExcessX))
                    } else if storyExcessY > 0, let baseY = placeableVM.storyCropDragBaseY {
                        placeableVM.placeableStoryCropOffsetsY[placeableCurrentPhotoIdx] =
                            max(0, min(1, baseY - drag.translation.height / storyExcessY))
                    }
                }
                .onEnded { _ in
                    let didCrop = placeableVM.storyCropDragBase != nil || placeableVM.storyCropDragBaseY != nil
                    placeableVM.storyCropDragBase  = nil
                    placeableVM.storyCropDragBaseY = nil
                    if didCrop { savePlaceableStoryOverlay(); Task { await renderCard(showSpinner: false) } }
                }
            : nil
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
                showBackground: false,
                showWordmark: false,
                chartBottomReserved: 22,
                isStaticPreview: true
            )
            .frame(width: 300, height: 375)
            .allowsHitTesting(false)
        }
        // 워드마크: 상단 좌측 (날짜는 하단과 중복되므로 제거)
        HStack(spacing: 0) {
            MIMOWordmark(size: 11)
        }
        .cardTextShadow()
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    // MARK: - Placeable 정적 내보내기 뷰

    // text: 사진별 문구. nil이면 placeableCurrentText(현재 선택 사진 문구) 사용.
    // photoIndex: storyPhotos 인덱스 — cropOffsetX 조회에 사용.
    @ViewBuilder
    func placeableExportView(photo: UIImage?, text: String? = nil, photoIndex: Int = 0) -> some View {
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
                showWordmark: false,
                shoeName: displayShoeName,
                weather: condition?.weather,
                size: placeableVM.placeableSize,
                layout: placeableVM.placeableLayout,
                horizTextRow: placeableVM.placeableHorizTextRow,
                horizRoutePos: placeableVM.placeableHorizRoutePos,
                cropOffsetX: placeableVM.placeableStoryCropOffsets[photoIndex]  ?? 0.5,
                cropOffsetY: placeableVM.placeableStoryCropOffsetsY[photoIndex] ?? 0.5
            )
            if (template == .story || template == .video || template == .slide), !overlayText.isEmpty {
                OneLinerCard(
                    activity: activity,
                    text: overlayText,
                    position: placeableVM.placeableStoryPosition,
                    textColor: placeableVM.placeableStoryColor,
                    fontChoice: placeableVM.placeableStoryFont,
                    sizeLevel: placeableVM.placeableStorySize,
                    appearanceMode: .typing,
                    hasBorder: placeableVM.placeableStoryHasBorder,
                    showBackground: false,
                    showWordmark: false,
                    chartBottomReserved: 22,
                    isStaticPreview: true
                )
            }
            // 워드마크: 상단 좌측 (날짜는 하단과 중복되므로 제거)
            HStack(spacing: 0) {
                MIMOWordmark(size: 11)
            }
            .cardTextShadow()
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        }
        .frame(width: 300, height: 375)
    }

}
