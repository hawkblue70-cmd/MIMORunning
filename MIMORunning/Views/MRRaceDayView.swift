import SwiftUI

struct MRRaceDayView: View {
    let card: MRRaceDayCard
    private let acc = Color(red: 0.48, green: 0.36, blue: 0.98)

    // ⚠ D-14 이내에만 오늘 화면에 올린다.
    //   D-90짜리 대회를 매일 카운트다운하면 압박이 된다.
    static func shouldShow(_ c: MRRaceDayCard) -> Bool {
        if case .building = c.phase { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.race.name)
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
            Text(card.headline)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(card.lines, id: \.self) { l in
                Text(.init(l))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 스플릿은 D-1 이후에만
            if !card.splits.isEmpty, card.daysLeft <= 1 {
                VStack(spacing: 0) {
                    ForEach(Array(card.splits.enumerated()), id: \.offset) { _, s in
                        HStack {
                            Text(String(format: "%.1fkm", s.km))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            Text(mrFormatHMS(s.time))
                                .foregroundStyle(.white)
                                .fontWeight(s.km >= 42 || s.km == 21.0975 ? .semibold : .regular)
                        }
                        .font(.system(size: 13, design: .rounded))
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(acc.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(acc.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
