import SwiftUI

/// 인사이트 내보내기 이미지 맨 아래 "아침 제안" 블록 — 설계 2026-10-15 §4.
/// 그날 아침 판정 → 실제 / 다음 날 아침 판정(없으면 → 다음 방향). 수치 줄은 `showData`일 때만.
/// 4:5 캔버스에 맞춰 전체가 축소되므로 줄 수를 묶어 둔다: 판정 1 + 이유(·수치) ≤2 + 실제 1 + 다음 판정 1 + 이유 1 = 최대 6줄.
struct InsightMorningSection: View {
    let morning: InsightMorning
    var showData: Bool = false

    var body: some View {
        let L = AppLanguage.shared
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                .padding(.bottom, 8)
            Text(L.s("아침 제안", "Morning suggestion", ja: "朝の提案"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.bottom, 5)

            if let e = morning.morningOf {
                entryRows(e, icon: "sun.max.fill", detailLines: 2)
            }
            if let a = morning.actual {
                Text("→ " + L.s("실제: ", "Actual: ", ja: "実際: ") + a)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.top, 3)
            }
            if let n = morning.nextMorning {
                entryRows(n, icon: "moon.fill", detailLines: 1)
                    .padding(.top, 7)
            } else if let d = morning.nextDirection {
                Text("→ " + L.s("다음: ", "Next: ", ja: "次: ") + d)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 12)
    }

    @ViewBuilder
    private func entryRows(_ e: InsightMorning.Entry, icon: String, detailLines: Int) -> some View {
        let color = InsightMorning.level(from: e.level)?.displayColor ?? Color.white
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9))
            Text("\(e.label) · \(InsightMorning.verdict(fromLine: e.line))")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .foregroundStyle(color)
        let detail = [e.why, showData ? e.data : ""].filter { !$0.isEmpty }.joined(separator: " ")   // 홈 둘째 줄과 같은 이음(why + " " + 수치)
        if !detail.isEmpty {
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(detailLines).minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2).padding(.leading, 14)
        }
    }
}
