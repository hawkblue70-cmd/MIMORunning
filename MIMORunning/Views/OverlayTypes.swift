// 오버레이 카드 공용 타입·레이어.
// 기본 사진(또는 영상) 위에 사진 2장을 작게 얹는다. 크기는 카드 폭 기준 25·30·35%.
// OverlayPhotosLayer 하나를 사진 미리보기·사진 출력·영상 미리보기·영상 출력이 함께 쓴다(§5.8 단일 컴포넌트).
// ⚠️ 오버레이 카드 전용.

import SwiftUI

// MARK: - Size

/// 오버레이 사진 긴 변 = 카드 폭 × 비율 (원본 비율 유지, 잘림 없음). 사진 4:5(300pt)·영상 9:16(211pt) 모두 같은 비율.
enum OverlaySizeLevel: Int, CaseIterable, Equatable {
    case p25 = 25, p30 = 30, p35 = 35

    var fraction: CGFloat { CGFloat(rawValue) / 100 }
    var chipLabel: String { "\(rawValue)%" }
}

// MARK: - Control target

/// 컨트롤 탭 — 위치 그리드가 어느 요소를 움직이는지.
enum OverlayTarget: Hashable {
    case photo(Int)   // 0, 1
    case text
}

// MARK: - Slot

/// 오버레이 사진 한 칸. 사진이 없으면 그리지 않고 위치도 차지하지 않는다.
struct OverlayPhotoSlot: Equatable {
    var image: UIImage?
    var position: CardPosition
    var size: OverlaySizeLevel = .p30

    static func == (a: OverlayPhotoSlot, b: OverlayPhotoSlot) -> Bool {
        a.image === b.image && a.position == b.position && a.size == b.size
    }
}

// MARK: - Layer (단일 컴포넌트)

/// 오버레이 사진 레이어. 캔버스 전체를 덮는 투명 뷰 — 사진마다 9칸 위치에 원본 비율 그대로(흰 테두리) 놓는다.
/// 여백은 같은 카드의 문구(OneLinerCard)와 같은 값을 받는다: 위=워드마크 아래, 아래·좌우=문구 여백.
struct OverlayPhotosLayer: View {
    let slots: [OverlayPhotoSlot]
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    var horizontalPadding: CGFloat = 14

    var body: some View {
        ZStack {
            ForEach(slots.indices, id: \.self) { i in
                if let img = slots[i].image {
                    photo(img, longSide: canvasWidth * slots[i].size.fraction)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: slots[i].position.alignment)
                }
            }
        }
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .padding(.horizontal, horizontalPadding)
        .frame(width: canvasWidth, height: canvasHeight)
        .allowsHitTesting(false)
    }

    /// 원본 비율 유지 — 긴 변(테두리 포함)을 longSide에 맞추고 짧은 변은 비율대로. 세로·가로 사진 모두
    /// 같은 범위(longSide 정사각) 안에 들어와 9칸 배치가 예측 가능하다. 얇은 흰 테두리 + 그림자.
    /// 테두리·모서리·그림자는 긴 변에 비례해 크기가 달라도 같은 모양.
    private func photo(_ img: UIImage, longSide: CGFloat) -> some View {
        let border = max(0.75, longSide * 0.018)
        let aspect = img.size.height > 0 ? img.size.width / img.size.height : 1   // 폭/높이
        let inner  = longSide - border * 2
        let w = aspect >= 1 ? inner : inner * aspect
        let h = aspect >= 1 ? inner / aspect : inner
        return Image(uiImage: img)
            .resizable()
            .frame(width: w, height: h)
            .padding(border)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: longSide * 0.04))
            .shadow(color: .black.opacity(0.35), radius: max(2, longSide * 0.05), y: 1)
    }
}

// MARK: - Image (영상 출력용)

/// 오버레이 사진 레이어를 영상 캔버스(1080×1920 px) 크기 투명 이미지로 렌더한다.
/// logicalWidth·Height = 영상 미리보기 규격(211×375pt) — 미리보기와 같은 레이아웃을 배율만 키워 그린다.
@MainActor
func makeOverlayPhotosImage(slots: [OverlayPhotoSlot], renderSize: CGSize,
                            logicalWidth: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> UIImage? {
    let logicalHeight = renderSize.height / renderSize.width * logicalWidth
    let view = OverlayPhotosLayer(slots: slots, canvasWidth: logicalWidth, canvasHeight: logicalHeight,
                                  topInset: topInset, bottomInset: bottomInset)
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = .init(width: logicalWidth, height: logicalHeight)
    renderer.scale = renderSize.width / logicalWidth
    renderer.isOpaque = false
    _ = renderer.uiImage   // 첫 호출은 SwiftUI 파이프라인 미초기화로 잘못된 이미지를 반환할 수 있음 — 버림
    return renderer.uiImage
}

// MARK: - Downscale

extension UIImage {
    /// 오버레이 원본은 최대 35% 폭(1080px 영상에서 378px)이라 긴 변 1200px이면 충분 — 메모리 절약.
    func overlayDownscaled(maxSide: CGFloat = 1200) -> UIImage {
        let longSide = max(size.width, size.height)
        guard longSide > maxSide else { return self }
        let s = maxSide / longSide
        let newSize = CGSize(width: (size.width * s).rounded(), height: (size.height * s).rounded())
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: fmt).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
