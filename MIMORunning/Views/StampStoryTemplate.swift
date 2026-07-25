// 스탬프 카드 — 스토리(사진 1장) 미리보기·이미지 출력.
// 렌더는 StampCard 를 그대로 사용한다(미리보기와 결과 불일치 방지).
// ⚠️ 스탬프 카드 전용.

import SwiftUI

// MARK: - Brightness helper

/// 사진에서 position 에 해당하는 9칸 영역의 평균 밝기를 판정한다.
/// 상대 휘도(0.299R + 0.587G + 0.114B) > 0.55 이면 true(밝음)
func stampBackgroundIsBright(photo: UIImage?, position: CardPosition) -> Bool {
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
    /// 워드마크 우측에 표시할 날짜. nil이면 날짜 생략.
    var displayDate: Date? = nil

    private let renderWidth: CGFloat = 300
    private var resolved: StampPhotoConfig { configOverride ?? vm.currentConfig }

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
                    .frame(width: renderWidth, height: renderHeight)
                    .clipped()
            } else {
                Color(hex: "3A4038")
            }

            // 스탬프 오버레이
            StampCard(
                data: data,
                template: resolved.template,
                colorMode: resolved.colorMode,
                position: resolved.position,
                sizeLevel: resolved.sizeLevel,
                isBrightBackground: stampBackgroundIsBright(photo: photo, position: resolved.position),
                showHeartRate: resolved.showHeartRate,
                showCalories: resolved.showCalories,
                showTextOutline: resolved.showTextOutline,
                stampText: resolved.text,
                stampTextPosition: resolved.textPosition,
                stampTextFont: resolved.textFont,
                stampTextSize: resolved.textSize,
                stampTextColor: resolved.textColor,
                stampTextHasBorder: resolved.textHasBorder,
                wordmarkTopInset: 28
            )

            // 워드마크 + 날짜: 동일 줄, 로고 좌측 / 날짜 우측
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
                if let d = displayDate {
                    Spacer()
                    Text(d.oneLinerDateString)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .allowsHitTesting(false)
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
    /// 워드마크 우측에 표시할 날짜. nil이면 날짜 생략.
    var displayDate: Date? = nil

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
                    .frame(width: renderWidth, height: renderHeight)
                    .clipped()
            } else {
                Color(hex: "3A4038")
            }

            // 스탬프 레이어 (독립 애니메이션)
            StampCard(
                data: data, template: cfg.template, colorMode: cfg.colorMode,
                position: cfg.position, sizeLevel: cfg.sizeLevel,
                isBrightBackground: stampBackgroundIsBright(photo: photo, position: cfg.position),
                showHeartRate: cfg.showHeartRate, showCalories: cfg.showCalories,
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

            // 문구 레이어 (독립 애니메이션)
            if !cfg.text.isEmpty {
                StampCard(
                    data: data, template: cfg.template, colorMode: cfg.colorMode,
                    position: cfg.position, sizeLevel: cfg.sizeLevel,
                    isBrightBackground: stampBackgroundIsBright(photo: photo, position: cfg.position),
                    showHeartRate: cfg.showHeartRate, showCalories: cfg.showCalories,
                    showTextOutline: cfg.showTextOutline,
                    stampText: cfg.text, stampTextPosition: cfg.textPosition,
                    stampTextFont: cfg.textFont, stampTextSize: cfg.textSize,
                    stampTextColor: cfg.textColor, stampTextHasBorder: cfg.textHasBorder,
                    wordmarkTopInset: 28, renderOnlyText: true
                )
                .scaleEffect(scaleFor(textVisible, mode: cfg.textEntranceMode))
                .offset(offsetFor(textVisible, mode: cfg.textEntranceMode, dir: cfg.textFlyDirection))
                .opacity(cfg.textEntranceMode == .none ? 1 : (textVisible ? 1 : 0))
                .animation(animFor(cfg.textEntranceMode), value: textVisible)
            }

            // 워드마크 + 날짜
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
                if let d = displayDate {
                    Spacer()
                    Text(d.oneLinerDateString)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .allowsHitTesting(false)
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
                         configOverride: StampPhotoConfig? = nil,
                         displayDate: Date? = nil) -> UIImage? {
    FontLoader.registerBundledFonts()
    // StampCard uses Canvas views (brackets, waveforms). ImageRenderer produces a blank image
    // on the very first Canvas render. Calling uiImage twice forces the graphics context to
    // initialize fully before the actual export render.
    let view = StampStoryRenderView(photo: photo, data: data, vm: vm,
                                    cropOffsetX: cropOffsetX,
                                    configOverride: configOverride,
                                    displayDate: displayDate)
        .frame(width: 300, height: 375)
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = .init(width: 300, height: 375)
    renderer.scale = 3
    _ = renderer.uiImage   // warm-up: initializes Canvas graphics context
    return renderer.uiImage
}
