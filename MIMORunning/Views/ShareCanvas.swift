import UIKit

/// 공유 이미지를 인스타그램 세로 피드 한도에 맞춰 얹는 캔버스.
///
/// 인스타그램 피드는 4:5(1080×1350)보다 긴 이미지의 **아래를 잘라낸다**.
/// 카드 높이가 제각각이어도 내보낸 이미지는 늘 이 비율이어야 잘리지 않는다.
///
/// §5.8 — 인사이트 카드(리듬·폼·퍼포먼스)와 러닝 흐름이 이 함수 **하나만** 쓴다.
/// 화면마다 따로 합성하면 같은 앱에서 내보낸 카드의 크기가 갈라진다.
enum ShareCanvas {

    /// 인스타그램 세로 피드 한도 — 이보다 길면 아래가 잘린다.
    static let instagramPortrait = CGSize(width: 1080, height: 1350)

    /// 카드 이미지를 캔버스에 맞춰 얹는다.
    ///
    /// - 카드가 캔버스보다 짧으면: 위에 붙이고 남는 아래를 `background`로 채운다.
    /// - 카드가 길면: 비율을 지켜 줄이고 가로 가운데에 놓는다 → **좌우 여백**이 생긴다.
    ///
    /// - Parameters:
    ///   - cornerRadius: 캔버스 픽셀 기준. 카드 배경이 캔버스 색과 다를 때(그라디언트 등)
    ///     0보다 큰 값을 주면 여백이 이음매가 아니라 카드 테두리로 읽힌다.
    static func fit(_ raw: UIImage,
                    background: UIColor,
                    cornerRadius: CGFloat = 0,
                    canvas: CGSize = instagramPortrait) -> UIImage {
        let ratio = min(canvas.width / raw.size.width, canvas.height / raw.size.height)
        let drawW = raw.size.width * ratio
        let drawH = raw.size.height * ratio
        let drawX = (canvas.width - drawW) / 2
        let drawY: CGFloat = 0   // 상단 정렬 — 카드가 짧으면 아래가 남는다

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            background.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))
            let rect = CGRect(x: drawX, y: drawY, width: drawW, height: drawH)
            if cornerRadius > 0, drawW < canvas.width {
                ctx.cgContext.saveGState()
                UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
                raw.draw(in: rect)
                ctx.cgContext.restoreGState()
            } else {
                raw.draw(in: rect)
            }
        }
    }
}
