import SwiftUI

// MARK: - Previews

private let _previewRace = MRTargetRace(
    date: Calendar.current.date(byAdding: .day, value: 13, to: Date())!,
    distanceM: MRDistance.dF, name: "서울마라톤 2026")

#Preview("D-13 테이퍼 (■4)") {
    let card = MRRaceDayCard(
        race: _previewRace, phase: .tapering, daysLeft: 13,
        headline: "D-13 · 이제 쌓는 게 아니라 아끼는 시기입니다",
        lines: [
            "거리는 절반 가까이 줄이시되 **페이스는 그대로** 두세요. 완전히 쉬면 오히려 둔해집니다.",
            "여기서 늘려도 대회 날 몸에 남지 않습니다. 지금까지 쌓은 것이 다입니다.",
            "테이퍼 2주차 — 이번 주는 42km 정도로."
        ], splits: [])
    ScrollView { MRRaceDayView(card: card).padding(16) }
        .background(Color.black).preferredColorScheme(.dark)
}

#Preview("D-0 레이스데이 · 13.5% 갭 (■1·■2)") {
    let card = MRRaceDayCard(
        race: _previewRace, phase: .raceDay, daysLeft: 0,
        headline: "오늘입니다",
        lines: [
            "첫 5km를 7'10\"/km보다 빠르게 가지 마세요.",
            "172만 명 기록에서 초반 10% 과속은 완주 시간을 평균 37분 늘렸습니다. 세 명 중 한 명이 첫 5km를 가장 빠르게 달립니다.",
            "위 배분은 처음부터 끝까지 같은 페이스입니다. 초반에 빨라지는 쪽이 후반 감속으로 돌아옵니다.",
            "입력하신 목표는 4시간 20분인데 지금 몸으로는 4시간 55분 38초 부근입니다. 이번 대회에서 목표까지는 거리가 있습니다. 오늘 배분은 완주 기준입니다.",
            "좋은 레이스 되세요."
        ],
        splits: [(5,35.02),(10,70.05),(15,105.07),(21.0975,147.8),(25,175.1),(30,210.13),(35,245.15),(40,280.17),(42.195,295.19)])
    ScrollView { MRRaceDayView(card: card).padding(16) }
        .background(Color.black).preferredColorScheme(.dark)
}

// MARK: - View

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

            // 스플릿 표는 D-7부터 — 마지막 한 주에 배분을 정한다. D-14~D-8은 페이스 한 줄만(2주 전 표는 압박).
            if !card.splits.isEmpty, card.daysLeft <= 7 {
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
