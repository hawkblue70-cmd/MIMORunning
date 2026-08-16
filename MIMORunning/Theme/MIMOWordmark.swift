import SwiftUI

/// MIMO Running 확정 로고 워드마크 (CONCEPT 01 시안 그대로)
/// 시안을 투명 벡터급 PNG(Assets: "MIMOWordmark")로 넣어 100% 동일하게 렌더.
/// 색·간격·스우시는 이미지에 고정. 크기만 `size`로 조절.
struct MIMOWordmark: View {
    /// 로고 크기 기준값(대략 MIMO 대문자 높이). 전체 높이 ≈ size × 2.2
    var size: CGFloat = 16

    // 아래 두 값은 옛 호출부 호환용(이미지 방식에선 미사용)
    var mimoColor: Color = .white
    var runColor: Color = Theme.violet

    var body: some View {
        Image("MIMOWordmark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: size * 2.3)
            .shadow(color: .black.opacity(0.14), radius: size * 0.045, x: 0, y: 0)   // 아래로 안 떨어지는 은은한 글로우
            .accessibilityLabel("MIMO Running")
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [Color(hex: "9EC6F0"), Color(hex: "CFE0F5")],
                       startPoint: .top, endPoint: .bottom)
        MIMOWordmark(size: 22)
    }
}
