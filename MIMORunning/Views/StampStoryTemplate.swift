// 스탬프 카드 — 스토리(사진 1장) 미리보기·이미지 출력.
// 렌더는 StampCard 를 그대로 사용한다(미리보기와 결과 불일치 방지).
// ⚠️ 스탬프 카드 전용.

import SwiftUI

// MARK: - Brightness helper

/// 사진에서 position 에 해당하는 9칸 영역의 평균 밝기를 판정한다.
/// 상대 휘도(0.299R + 0.587G + 0.114B) > 0.55 이면 true(밝음)
nonisolated func stampBackgroundIsBright(photo: UIImage?, position: CardPosition) -> Bool {
    guard let photo else { return false }
    let all = CardPosition.allCases
    guard let idx = all.firstIndex(of: position) else { return false }
    let row = idx / 3
    let col = idx % 3

    // 3×3 픽셀로 축소: UIImage 방향 자동 처리, 각 픽셀 = 해당 칸 평균색
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 3), format: format)
    let tiny = renderer.image { _ in
        photo.draw(in: CGRect(x: 0, y: 0, width: 3, height: 3))
    }

    guard let cgImg = tiny.cgImage,
          let cell = cgImg.cropping(to: CGRect(x: col, y: row, width: 1, height: 1)) else {
        return false
    }

    var px = [UInt8](repeating: 0, count: 4)
    guard let ctx = CGContext(data: &px, width: 1, height: 1,
                              bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return false
    }
    ctx.draw(cell, in: CGRect(x: 0, y: 0, width: 1, height: 1))

    let r = CGFloat(px[0]) / 255
    let g = CGFloat(px[1]) / 255
    let b = CGFloat(px[2]) / 255
    return (0.299 * r + 0.587 * g + 0.114 * b) > 0.55
}

// MARK: - StampStoryRenderView

/// 스탬프 카드 스토리 미리보기·출력 공용 뷰.
/// 미리보기에서도 이 뷰를 사용해 출력 결과와 항상 동일하게 보임.
struct StampStoryRenderView: View {
    let photo: UIImage?
    let data: StampData
    @Bindable var vm: StampViewModel
    var cropOffsetX: CGFloat = 0.5
    /// 이 사진에 적용할 속성 전체. nil이면 vm.currentConfig 사용 (selectedClipIndex 기반).
    var configOverride: StampPhotoConfig? = nil
    /// 렌더 높이: 스토리 4:5 = 375, 슬라이드 9:16 ≈ 533
    var renderHeight: CGFloat = 375

    private let renderWidth: CGFloat = 300
    private var resolved: StampPhotoConfig { configOverride ?? vm.currentConfig }

    // 배경 밝기 캐시 — photo+position 조합 변경 시 비동기 재계산
    // 뷰 body에서 직접 계산하면 풀해상도 사진 디코딩이 메인스레드를 블로킹하므로 분리.
    /// 사진이 없으면 흰 배경이라 처음부터 밝음 — 비동기 판정 전에 흰 글자가 한 번 번쩍이지 않게
    @State private var isBrightBackground: Bool = false
    private var effectiveBright: Bool { photo == nil ? true : isBrightBackground }

    private var brightnessKey: String {
        let posIdx = CardPosition.allCases.firstIndex(of: resolved.position) ?? 0
        return "\(photo.map { ObjectIdentifier($0).hashValue } ?? 0)_\(posIdx)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 배경 (가로 사진 크롭 지원)
            if let photo {
                let s   = max(renderWidth / photo.size.width, renderHeight / photo.size.height)
                let iW  = photo.size.width  * s
                let iH  = photo.size.height * s
                let ox  = -(cropOffsetX * max(0, iW - renderWidth))
                Image(uiImage: photo)
                    .resizable()
                    .frame(width: iW, height: iH)
                    .offset(x: ox)
                    .frame(width: renderWidth, height: renderHeight, alignment: .topLeading)
                    .clipped()
            } else {
                // 사진 없음 = 흰 배경 (나이키 방식) — 스탬프 자동 색은 검정, 사진을 고르면 흰색으로 바뀐다
                Color.white
            }

            // 스탬프 레이어
            StampCard(
                data: data,
                template: resolved.template,
                colorMode: resolved.colorMode,
                position: resolved.position,
                sizeLevel: resolved.sizeLevel,
                isBrightBackground: effectiveBright,
                showHeartRate: resolved.showHeartRate,
                showCalories: false,
                showTextOutline: resolved.showTextOutline,
                stampText: resolved.text,
                stampTextPosition: resolved.textPosition,
                stampTextFont: resolved.textFont,
                stampTextSize: resolved.textSize,
                stampTextColor: resolved.textColor,
                stampTextHasBorder: resolved.textHasBorder,
                wordmarkTopInset: 42,
                renderOnlyStamp: true
            )
            // 문구 레이어 — OneLinerCard(영상·슬라이드와 동일 컴포넌트·폰트 공식)
            if !resolved.text.isEmpty {
                OneLinerCard(
                    text: resolved.text,
                    position: resolved.textPosition,
                    textColor: resolved.textColor,
                    fontChoice: resolved.textFont,
                    sizeLevel: resolved.textSize,
                    appearanceMode: .typing,
                    decorEffect: .none,
                    hasBorder: resolved.textHasBorder,
                    showBackground: false,
                    showWordmark: false,
                    cardHeightOverride: renderHeight,
                    safeTopInset: renderHeight > 400 ? 77 : 42,
                    safeBottomInset: 20,
                    isStaticPreview: true
                )
            }

            // 워드마크: 좌측 상단 (+ 날짜 토글 시 같은 줄 오른쪽에 날짜·시간)
            MIMOWordmark(size: 11, onMediaCard: true)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .frame(width: renderWidth, height: renderHeight, alignment: .topLeading)
                .allowsHitTesting(false)
            if resolved.showDate, let d = data.date {
                StampDateLabel(date: d, onLight: photo == nil)
                    .padding(.horizontal, 14)
                    .padding(.top, 14 + 8)   // 워드마크(25pt) 세로 중앙 근처
                    .frame(width: renderWidth, height: renderHeight, alignment: .topTrailing)
                    .allowsHitTesting(false)
            }
        }
        .task(id: brightnessKey) {
            let p = photo
            let pos = resolved.position
            let result = await Task.detached(priority: .userInitiated) {
                stampBackgroundIsBright(photo: p, position: pos)
            }.value
            isBrightBackground = result
        }
    }
}

// MARK: - StampAnimPreviewCard

/// 슬라이드 미리보기 전용. animTrigger 변경 시 스탬프·문구 등장 애니메이션을 SwiftUI로 재생.
/// 스탬프와 문구를 별도 레이어로 분리해 각각 독립 애니메이션 적용.
struct StampAnimPreviewCard: View {
    let photo: UIImage?
    let data: StampData
    @Bindable var vm: StampViewModel
    var cropOffsetX: CGFloat = 0.5
    var configOverride: StampPhotoConfig? = nil
    var renderHeight: CGFloat = 375
    /// 부모에서 increment → 애니메이션 재생
    var animTrigger: Int = 0

    @State private var stampVisible: Bool = true
    @State private var textVisible:  Bool = true

    private let renderWidth: CGFloat = 300
    private var cfg: StampPhotoConfig { configOverride ?? vm.currentConfig }

    var body: some View {
        ZStack(alignment: .top) {
            // 배경
            if let photo {
                let s  = max(renderWidth / photo.size.width, renderHeight / photo.size.height)
                let iW = photo.size.width  * s
                let iH = photo.size.height * s
                let ox = -(cropOffsetX * max(0, iW - renderWidth))
                Image(uiImage: photo)
                    .resizable()
                    .frame(width: iW, height: iH)
                    .offset(x: ox)
                    .frame(width: renderWidth, height: renderHeight, alignment: .topLeading)
                    .clipped()
            } else {
                // 사진 없음 = 흰 배경 (나이키 방식) — 스탬프 자동 색은 검정, 사진을 고르면 흰색으로 바뀐다
                Color.white
            }

            // 스탬프 레이어 (독립 애니메이션)
            StampCard(
                data: data, template: cfg.template, colorMode: cfg.colorMode,
                position: cfg.position, sizeLevel: cfg.sizeLevel,
                isBrightBackground: photo == nil ? true : stampBackgroundIsBright(photo: photo, position: cfg.position),
                showHeartRate: cfg.showHeartRate, showCalories: false,
                showTextOutline: cfg.showTextOutline,
                stampText: cfg.text, stampTextPosition: cfg.textPosition,
                stampTextFont: cfg.textFont, stampTextSize: cfg.textSize,
                stampTextColor: cfg.textColor, stampTextHasBorder: cfg.textHasBorder,
                renderOnlyStamp: true
            )
            .scaleEffect(scaleFor(stampVisible, mode: cfg.entranceMode))
            .offset(offsetFor(stampVisible, mode: cfg.entranceMode, dir: cfg.flyDirection))
            .opacity(cfg.entranceMode == .none ? 1 : (stampVisible ? 1 : 0))
            .animation(animFor(cfg.entranceMode), value: stampVisible)

            // 문구 레이어 — OneLinerCard(영상·슬라이드와 동일 컴포넌트·폰트 공식)
            if !cfg.text.isEmpty {
                OneLinerCard(
                    text: cfg.text,
                    position: cfg.textPosition,
                    textColor: cfg.textColor,
                    fontChoice: cfg.textFont,
                    sizeLevel: cfg.textSize,
                    appearanceMode: .typing,
                    decorEffect: .none,
                    hasBorder: cfg.textHasBorder,
                    showBackground: false,
                    showWordmark: false,
                    cardHeightOverride: renderHeight,
                    safeTopInset: renderHeight > 400 ? 77 : 42,
                    safeBottomInset: 20,
                    isStaticPreview: true
                )
                .scaleEffect(scaleFor(textVisible, mode: cfg.textEntranceMode))
                .offset(offsetFor(textVisible, mode: cfg.textEntranceMode, dir: cfg.textFlyDirection))
                .opacity(cfg.textEntranceMode == .none ? 1 : (textVisible ? 1 : 0))
                .animation(animFor(cfg.textEntranceMode), value: textVisible)
            }

            // 워드마크 (+ 날짜 토글 시 같은 줄 오른쪽에 날짜·시간)
            MIMOWordmark(size: 11, onMediaCard: true)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .frame(width: renderWidth, height: renderHeight, alignment: .topLeading)
                .allowsHitTesting(false)
            if cfg.showDate, let d = data.date {
                StampDateLabel(date: d, onLight: photo == nil)
                    .padding(.horizontal, 14)
                    .padding(.top, 14 + 8)
                    .frame(width: renderWidth, height: renderHeight, alignment: .topTrailing)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: animTrigger) { _, _ in playAnim() }
    }

    // MARK: - Animation helpers

    private func scaleFor(_ visible: Bool, mode: StampEntranceMode) -> CGFloat {
        mode == .stamp && !visible ? 0.01 : 1.0
    }

    private func offsetFor(_ visible: Bool, mode: StampEntranceMode, dir: FlyInDirection) -> CGSize {
        guard mode == .flyIn, !visible else { return .zero }
        switch dir {
        case .leading:  return CGSize(width: -renderWidth, height: 0)
        case .trailing: return CGSize(width:  renderWidth, height: 0)
        case .bottom:   return CGSize(width: 0, height: renderHeight)
        }
    }

    private func animFor(_ mode: StampEntranceMode) -> Animation {
        switch mode {
        case .stamp: return .spring(response: 0.4, dampingFraction: 0.5)
        case .fade:  return .easeIn(duration: 0.4)
        case .flyIn: return .spring(response: 0.45, dampingFraction: 0.75)
        case .none:  return .linear(duration: 0)
        }
    }

    private func playAnim() {
        // 즉시 숨김 (애니메이션 없이)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { stampVisible = false; textVisible = false }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)   // 80ms
            withAnimation(animFor(cfg.entranceMode)) { stampVisible = true }
            try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms
            withAnimation(animFor(cfg.textEntranceMode)) { textVisible = true }
        }
    }
}

// MARK: - Image export

/// StampStoryRenderView 를 300×375pt @3x 이미지로 렌더한다.
@MainActor
func makeStampStoryImage(photo: UIImage?, data: StampData, vm: StampViewModel,
                         cropOffsetX: CGFloat = 0.5,
                         configOverride: StampPhotoConfig? = nil) -> UIImage? {
    FontLoader.registerBundledFonts()
    let view = StampStoryRenderView(photo: photo, data: data, vm: vm,
                                    cropOffsetX: cropOffsetX,
                                    configOverride: configOverride)
        .frame(width: 300, height: 375)
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = .init(width: 300, height: 375)
    renderer.scale = 3
    _ = renderer.uiImage   // 첫 호출은 SwiftUI 파이프라인 미초기화로 잘못된 이미지를 반환할 수 있음 — 버림
    _ = renderer.uiImage   // 두 번째 워밍업 — VStack/HStack Spacer 레이아웃이 완전히 정착되도록
    return renderer.uiImage
}
