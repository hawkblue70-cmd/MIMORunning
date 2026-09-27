import SwiftUI

/// 나 탭 참가 대회 · 기록 모드의 한 행.
///
/// 확정 러닝 행은 부모가 행 전체에 탭을 붙여 러닝 상세로 보낸다(여기서는 꺾쇠만 그림).
/// 러닝 없는 계획 아카이브 행은 흐리게 그린다.
struct RaceRecordRow: View {
    let row: RaceRecordList.Row
    var onTapPlan: (() -> Void)? = nil

    /// 구간 밖 — 성장 탭 예측 목록과 같은 주황
    private static let warn = Color(red: 0.95, green: 0.68, blue: 0.25)

    private var dateText: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: row.date)
        return String(format: "%d.%02d.%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private var hasSecondLine: Bool {
        row.prediction != nil || row.editionCount != nil || row.hasPlan
    }

    var body: some View {
        let L = AppLanguage.shared
        let dim = !row.opensRun
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(dateText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .layoutPriority(1)
                Text(row.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(dim ? Color.secondary : RaceBadge.color)
                    .lineLimit(1)
                Text(row.distanceLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(dim ? Color.secondary : Theme.violet)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((dim ? Color.secondary : Theme.violet).opacity(0.15))
                    .clipShape(Capsule())
                Spacer(minLength: 4)
                Text(row.finishMin.map { mrFormatDisplay($0) } ?? L.s("기록 없음", "No result"))
                    .font(.system(size: 14, weight: row.finishMin == nil ? .regular : .bold, design: .rounded))
                    .foregroundStyle(dim ? Color.secondary : Color.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .layoutPriority(1)
                if row.opensRun {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            if hasSecondLine {
                HStack(spacing: 6) {
                    if let p = row.prediction {
                        Text(L.s("예측 \(mrFormatDisplay(p.predictedMin))", "Predicted \(mrFormatDisplay(p.predictedMin))"))
                            .foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(p.inBand ? L.s("구간 안", "In range") : L.s("구간 밖", "Out of range"))
                            .foregroundStyle(p.inBand ? Theme.positive : Self.warn)
                    }
                    if let n = row.editionCount {
                        if row.prediction != nil {
                            Text("·").foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        Text(L.s("\(n)회째", "#\(n)"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if row.hasPlan {
                        Button { onTapPlan?() } label: {
                            Text(L.s("계획", "Plan"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L.s("계획 보기", "View plan"))
                    }
                }
                .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }
}
