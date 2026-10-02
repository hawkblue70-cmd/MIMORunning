import SwiftUI

/// 나 탭 대회 계획 카드 안 — "주차별 계획 보기" 다음. 예상 기록 기준 젤 보급 시점(경과 시간·km).
struct MRGelPlanView: View {
    let plan: MRGelPlan.Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MRGelPlan.title(plan))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)

            row(time: MRGelPlan.preStartLabel(), km: nil, kind: .regular)
            ForEach(Array(plan.stops.enumerated()), id: \.offset) { _, s in
                row(time: MRGelPlan.elapsed(s.minute), km: MRGelPlan.kmText(s.km), kind: s.kind)
            }

            Text(MRGelPlan.summary(plan))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            if plan.stops.contains(where: { $0.kind == .caffeine }) {
                Text(MRGelPlan.caffeineNote())
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(MRGelPlan.disclaimer())
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func row(time: String, km: String?, kind: MRGelPlan.Kind) -> some View {
        HStack(spacing: 8) {
            Text(time)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            if let km {
                Text(km)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            Text(MRGelPlan.gelName(kind))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(kind == .caffeine ? Theme.violetText : .white.opacity(0.75))
        }
        .accessibilityElement(children: .combine)
    }
}
