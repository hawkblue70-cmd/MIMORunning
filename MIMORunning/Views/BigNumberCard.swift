import SwiftUI

struct BigNumberCard: View {
    let activity: Activity
    let detail: ActivityDetail?
    let heroMetric: HeroMetric
    var mood: Mood? = nil
    var memoText: String? = nil
    var weatherText: String? = nil
    var weatherIcon: String? = nil
    let dateText: String
    var photo: UIImage? = nil

    // Matches ShareCardView / StoryShareCardView render size
    static let cardWidth: CGFloat  = 300
    static let cardHeight: CGFloat = 375

    // All metrics except hero, available first, up to 3
    private var secondaryMetrics: [HeroMetric] {
        let order: [HeroMetric] = [.distance, .duration, .pace, .heartRate]
        return Array(
            order
                .filter { $0 != heroMetric && $0.isAvailable(activity: activity, detail: detail) }
                .prefix(3)
        )
    }

    var body: some View {
        ZStack {
            // ── Background ─────────────────────────────────────────
            if let photo = photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.cardWidth, height: Self.cardHeight)
                    .clipped()
            } else {
                Color(hex: "141118")
            }

            CardVisual.topScrim
            CardVisual.bottomScrim

            // ── Content layout ─────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {

                // 1) Wordmark
                HStack(spacing: 0) {
                    Text("MIMO")
                        .font(.system(size: 9, weight: .black))
                        .tracking(2)
                        .foregroundStyle(.white)
                    Text(" RUNNING")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.violet)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // 2) Mood icon + Memo
                if mood != nil || memoText != nil {
                    HStack(alignment: .top, spacing: 6) {
                        if let mood = mood {
                            Image(systemName: mood.sfSymbol)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        if let memo = memoText, !memo.isEmpty {
                            Text(memo)
                                .font(.system(size: 14, weight: .regular, design: .serif).italic())
                                .lineLimit(2)
                        }
                    }
                    .foregroundStyle(.white)
                    .cardTextShadow()
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }

                // 3) Hero block — vertically balanced between top block and bottom bar
                Spacer()

                VStack(spacing: 4) {
                    Text(heroMetric.formattedValue(activity: activity, detail: detail))
                        .font(.system(size: 76, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .cardLargeTextShadow()

                    if !heroMetric.unit.isEmpty {
                        Text(heroMetric.unit)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.violet)
                            .tracking(2)
                            .cardTextShadow()
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()

                // 4) Secondary metrics + meta row
                VStack(alignment: .trailing, spacing: 8) {
                    if !secondaryMetrics.isEmpty {
                        HStack(spacing: 0) {
                            ForEach(secondaryMetrics) { m in
                                VStack(spacing: 3) {
                                    Text(m.formattedValue(activity: activity, detail: detail))
                                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                                        .foregroundStyle(.white)
                                    Text(secondaryLabel(for: m))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .cardTextShadow()
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    metaRow
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // Weather icon + temp · date, or date only
    @ViewBuilder
    private var metaRow: some View {
        if let w = weatherText {
            HStack(spacing: 4) {
                Image(systemName: weatherIcon ?? "thermometer.medium")
                    .font(.system(size: 9))
                Text("\(w) · \(dateText)")
            }
            .font(.system(size: 10))
            .foregroundStyle(Color(hex: "8A8A92"))
            .cardTextShadow()
        } else {
            Text(dateText)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "8A8A92"))
                .cardTextShadow()
        }
    }

    // Labels match basic card bottom row
    private func secondaryLabel(for metric: HeroMetric) -> String {
        let L = AppLanguage.shared
        switch metric {
        case .distance:  return "KM"
        case .pace:      return "/km"
        case .duration:  return L.s("시간", "TIME")
        case .heartRate: return "bpm"
        }
    }
}

#Preview {
    let activity = Activity(
        id: UUID(),
        type: .running,
        date: Date(),
        duration: 2545,      // → "42:25"
        distance: 10_020,    // 10.02 km (metres)
        calories: 520,
        avgHeartRate: 152
    )
    BigNumberCard(
        activity: activity,
        detail: nil,
        heroMetric: .distance,
        mood: .great,
        memoText: "오늘은 날씨도 좋고 페이스도 잘 나왔다",
        weatherText: "22°C",
        dateText: "2026. 6. 26  오전 7:30"
    )
    .padding()
    .background(Color.black)
}
