import SwiftUI

/// 성장 탭 — 유형별 "평소 강도" 표. 절대 임계 대신 본인 중앙값을 보여준다.
/// 각 행: 유형 · 중앙값(3회 이상일 때만) · 창/표본 수 · 수동 입력 기준 여부.
struct EffortTypeBaselineCard: View {
    let rows: [EffortBaseline.TypeSummary]

    private var L: AppLanguage { AppLanguage.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.s("유형별 평소 강도", "Usual effort by run type"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(L.s("최근 8주 중앙값 · 3회 미만이면 12주", "8-week median · 12 weeks if under 3"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.type) { row in
                    rowView(row)
                }
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func rowView(_ row: EffortBaseline.TypeSummary) -> some View {
        HStack(spacing: 8) {
            Text(row.type.koreanLabel)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
            if let m = row.median {
                Text("\(m) · \(EffortBand(value: m).label)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EffortPalette.color(for: m))
            } else {
                Text("—")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(L.s("\(row.windowWeeks)주 \(row.count)회", "\(row.count) in \(row.windowWeeks)w"))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            if row.isUserBased {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Theme.violet)
                        .frame(width: 4, height: 4)
                    Text(L.s("내 입력", "Mine"))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
