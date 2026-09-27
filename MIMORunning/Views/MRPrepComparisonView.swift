import SwiftUI

/// 나 탭 대회 계획 — 지난 대회 같은 D-N 시점과 지금의 준비 비교(B단계). 펼친 대회 카드 바로 아래.
struct MRPrepComparisonView: View {
    let result: MRPrepComparison.Result

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MRPrepComparison.title(result))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
            ForEach(Array(MRPrepComparison.lines(result).enumerated()), id: \.offset) { _, line in
                HStack(spacing: 8) {
                    Text(line.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 58, alignment: .leading)
                    Text(line.now)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text(line.past)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if let g = line.gain {
                        Text(g)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.positive)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
