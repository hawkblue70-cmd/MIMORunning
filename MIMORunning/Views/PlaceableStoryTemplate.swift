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
        let storyCropX = placeableVM.placeableStoryCropOffsets[placeableCurrentPhotoIdx] ?? 0.5
        let storyExcess: CGFloat = {
            guard let p = storyPhoto else { return 0 }
            let s = max(300 / p.size.width, 375 / p.size.height)
            return max(0, p.size.width * s - 300)
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
            cropOffsetX: storyCropX
        )
        .gesture(
            storyExcess > 0 ? DragGesture(minimumDistance: 1)
                .onChanged { drag in
                    if placeableVM.storyCropDragBase == nil {
                        placeableVM.storyCropDragBase = storyCropX
                    }
                    guard let base = placeableVM.storyCropDragBase else { return }
                    let newVal = max(0, min(1, base - drag.translation.width / storyExcess))
                    placeableVM.placeableStoryCropOffsets[placeableCurrentPhotoIdx] = newVal
                }
                .onEnded { _ in
                    placeableVM.storyCropDragBase = nil
                    Task { await renderCard(showSpinner: false) }
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
                showDate: false,
                showBackground: false,
                showWordmark: false,
                chartBottomReserved: placeableVM.storyBottomReserved,
                chartTopReserved: placeableVM.storyTopReserved,
                isStaticPreview: true
            )
            .frame(width: 300, height: 375)
            .allowsHitTesting(false)
        }
        // 워드마크 + 날짜: 스탬프 스토리와 동일한 단일 HStack
        HStack {
            HStack(spacing: 0) {
                Text("MIMO")
                    .font(.system(size: 9, weight: .black))
                    .tracking(2)
                    .foregroundStyle(.white)
                Text(" RUNNING")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.violet)
            }
            .cardTextShadow()
            Spacer()
            Text(activity.date.oneLinerDateString)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
        }
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
                cropOffsetX: placeableVM.placeableStoryCropOffsets[photoIndex] ?? 0.5
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
                    showDate: false,
                    showBackground: false,
                    showWordmark: false,
                    chartBottomReserved: placeableVM.storyBottomReserved,
                    chartTopReserved: placeableVM.storyTopReserved,
                    isStaticPreview: true
                )
            }
            // 워드마크 + 날짜: 스탬프 스토리와 동일한 단일 HStack
            HStack {
                HStack(spacing: 0) {
                    Text("MIMO")
                        .font(.system(size: 9, weight: .black))
                        .tracking(2)
                        .foregroundStyle(.white)
                    Text(" RUNNING")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.violet)
                }
                .cardTextShadow()
                Spacer()
                Text(activity.date.oneLinerDateString)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        }
        .frame(width: 300, height: 375)
    }

}
