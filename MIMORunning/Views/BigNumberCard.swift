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

    static let cardWidth: CGFloat  = 300
    static let cardHeight: CGFloat = 375

    private var secondaryMetrics: [HeroMetric] {
        let order: [HeroMetric] = [.distance, .duration, .pace, .heartRate]
        return Array(
            order
                .filter { $0 != heroMetric && $0.isAvailable(activity: activity, detail: detail) }
                .prefix(3)
        )
    }

    private let heroGradient = LinearGradient(
        colors: [Color(hex: "9B7DFF"), Color(hex: "6845E8")],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        ZStack {
            // ── Background ──────────────────────────────────────────
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

            // ── Content ─────────────────────────────────────────────
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

                // 2) Mood icon (gold) + Memo (white semibold)
                if mood != nil || memoText != nil {
                    HStack(alignment: .top, spacing: 6) {
                        if let mood = mood {
                            Image(systemName: mood.sfSymbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: "FFC74D"))
                        }
                        if let memo = memoText, !memo.isEmpty {
                            Text(memo)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }
                    }
                    .cardTextShadow()
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }

                // 3) Hero block — positioned at ~42% from top
                Spacer()

                VStack(spacing: 6) {
                    Text(heroMetric.formattedValue(activity: activity, detail: detail))
                        .font(.system(size: 96, weight: .black).monospacedDigit())
                        .tracking(-2)
                        .foregroundStyle(heroGradient)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .cardLargeTextShadow()

                    if !heroMetric.unit.isEmpty {
                        Text(heroMetric.unit)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .tracking(4)
                            .cardTextShadow()
                    }
                }
                .frame(maxWidth: .infinity)

                // Smaller spacer below hero → hero sits closer to upper half
                Spacer(minLength: 12).fixedSize()

                // 4) Secondary metrics + meta row
                VStack(alignment: .trailing, spacing: 8) {
                    if !secondaryMetrics.isEmpty {
                        HStack(spacing: 0) {
                            ForEach(Array(secondaryMetrics.enumerated()), id: \.offset) { idx, m in
                                if idx > 0 {
                                    Rectangle()
                                        .fill(Color(hex: "26262E").opacity(0.8))
                                        .frame(width: 1, height: 36)
                                }
                                VStack(spacing: 3) {
                                    Text(m.formattedValue(activity: activity, detail: detail))
                                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(Color(hex: "EDEDED"))
                                    Text(secondaryLabel(for: m))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color(hex: "6E6E78"))
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
                .padding(.bottom, 24)
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var metaRow: some View {
        if let w = weatherText {
            HStack(spacing: 4) {
                Image(systemName: weatherIcon ?? "thermometer.medium")
                    .font(.system(size: 9))
                Text("\(w) · \(dateText)")
            }
            .font(.system(size: 10))
            .foregroundStyle(Color.white.opacity(0.7))
            .cardTextShadow()
        } else {
            Text(dateText)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.7))
                .cardTextShadow()
        }
    }

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
        duration: 2545,
        distance: 10_020,
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
