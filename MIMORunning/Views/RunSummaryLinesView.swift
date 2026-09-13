import SwiftUI

/// 총평 줄 묶음 — 색점 + 축 + 상태어. 리듬 카드 하단과 (추후) 공유 카드가 **이 컴포넌트 하나만** 쓴다(§5.8).
/// 크기는 `scale`로만 조절한다. scale=1 기준: 글자 10pt · 점 7pt · 좌우 여백 12pt · 상하 10pt · 축 열 52pt.
struct RunSummaryLinesView: View {
    let lines: [RunSummaryLine]
    var scale: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 7 * scale) {
                    Circle()
                        .fill(color(line.tone))
                        .frame(width: 7 * scale, height: 7 * scale)
                        .padding(.top, 3.5 * scale)
                    Text(line.axis)
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(1)
                        .frame(width: 52 * scale, alignment: .leading)
                        .layoutPriority(1)
                    Text("·")
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(Color.white.opacity(0.35))
                    Text(line.state)
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineSpacing(2 * scale)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12 * scale).padding(.vertical, 10 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
    }

    private func color(_ tone: RunSummaryLine.Tone) -> Color {
        tone == .good ? Theme.positive : Theme.caution
    }
}
