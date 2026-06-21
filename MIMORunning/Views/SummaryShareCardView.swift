import SwiftUI

// MARK: - Period stats model

struct SummaryPeriodStats {
    enum Kind {
        case monthly(year: Int, month: Int)
        case yearly(year: Int)

        var title: String {
            switch self {
            case .monthly(let y, let m): return "\(y)년 \(m)월"
            case .yearly(let y):        return "\(y)년"
            }
        }

        var subtitle: String {
            switch self {
            case .monthly: return "이번 달 결산"
            case .yearly:  return "올해 결산"
            }
        }

        var shareFilename: String {
            switch self {
            case .monthly(let y, let m): return "mimo_summary_\(y)_\(m).png"
            case .yearly(let y):         return "mimo_summary_\(y).png"
            }
        }
    }

    let kind: Kind
    let activities: [Activity]
    let useMiles: Bool

    var runCount: Int { activities.filter { $0.type == .running }.count }
    var totalDistanceKm: Double { activities.reduce(0) { $0 + $1.distance / 1000 } }
    var totalDuration: TimeInterval { activities.reduce(0) { $0 + $1.duration } }

    private var avgPacePerKmSec: Double? {
        let runs = activities.filter { $0.type == .running && $0.distance > 0 }
        guard !runs.isEmpty else { return nil }
        let totalDist = runs.reduce(0) { $0 + $1.distance }
        let totalTime = runs.reduce(0) { $0 + $1.duration }
        guard totalDist > 0 else { return nil }
        return totalTime / (totalDist / 1000)
    }

    private var longestRunKm: Double? {
        activities.filter { $0.type == .running }.map { $0.distance / 1000 }.max()
    }

    var distanceStr: String {
        useMiles
            ? String(format: "%.1f", totalDistanceKm * 0.621371)
            : String(format: "%.1f", totalDistanceKm)
    }

    var distanceUnit: String { useMiles ? "mi" : "km" }

    var durationStr: String {
        let h = Int(totalDuration) / 3600
        let m = (Int(totalDuration) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)분"
    }

    var avgPaceStr: String? {
        guard let secs = avgPacePerKmSec else { return nil }
        let adjusted = useMiles ? secs * 1.60934 : secs
        let total = Int(adjusted)
        return "\(total / 60)'\(String(format: "%02d", total % 60))\""
    }

    var longestStr: String? {
        guard let km = longestRunKm, km > 0.1 else { return nil }
        return useMiles
            ? String(format: "%.1f mi", km * 0.621371)
            : String(format: "%.1f km", km)
    }

    var isEmpty: Bool { activities.isEmpty }
}

// MARK: - Athletic share card (360 × 520, rendered via ImageRenderer)

struct SummaryShareCardView: View {
    let stats: SummaryPeriodStats
    var miniMeImage: UIImage? = nil

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background

            VStack(alignment: .leading, spacing: 0) {
                // Violet accent bar
                Rectangle()
                    .fill(Theme.violet)
                    .frame(height: 3)

                VStack(alignment: .leading, spacing: 0) {
                    // Wordmark + MiniMe
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
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
                        }
                        Spacer()
                        miniMeContent
                            .frame(width: 52, height: 52)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                    // Period
                    Text(stats.kind.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text(stats.kind.subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.violet)
                        .padding(.top, 2)

                    // Divider
                    Rectangle()
                        .fill(Theme.violet.opacity(0.35))
                        .frame(height: 0.5)
                        .padding(.top, 18)
                        .padding(.bottom, 22)

                    // Hero distance
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(stats.distanceStr)
                            .font(.system(size: 66, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Text(stats.distanceUnit)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.violet)
                    }
                    Text("총 거리")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.4))

                    Spacer(minLength: 0)

                    // Thin separator
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.top, 20)
                        .padding(.bottom, 16)

                    // Secondary stats
                    HStack(spacing: 0) {
                        secondaryCell(value: stats.durationStr,    label: "운동 시간",   color: Theme.time)
                        cellDivider
                        secondaryCell(value: "\(stats.runCount)회", label: "러닝 횟수",  color: Theme.violet)
                        if let pace = stats.avgPaceStr {
                            cellDivider
                            secondaryCell(value: pace, label: "평균 페이스", color: Theme.pace)
                        }
                    }

                    // Longest run
                    if let longest = stats.longestStr {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 0.5)
                            .padding(.vertical, 12)
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.violet)
                            Text("최장 거리")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                            Spacer()
                            Text(longest)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }

                    Spacer(minLength: 12)

                    // Footer
                    HStack {
                        Text("미모러닝")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.2))
                        Spacer()
                        Image(systemName: "figure.run")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.violet.opacity(0.35))
                    }
                    .padding(.bottom, 2)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
        }
        .frame(width: 360, height: 520)
    }

    @ViewBuilder
    private var miniMeContent: some View {
        if let img = miniMeImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.violet.opacity(0.4), lineWidth: 1.5))
        } else {
            MiniMeView(variant: .celebrating, size: 52)
        }
    }

    private func secondaryCell(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(color.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 0.5, height: 30)
            .padding(.horizontal, 10)
    }
}

// MARK: - Share screen (presented as sheet)

struct SummaryShareCardScreen: View {
    let stats: SummaryPeriodStats
    var miniMeImage: UIImage? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?
    @State private var previewImage: UIImage?
    @State private var isRendering = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 28) {
                        cardPreview
                        shareButton
                            .padding(.horizontal, 24)
                        Spacer(minLength: 32)
                    }
                    .padding(.top, 20)
                }
            }
        }
        .task { await renderCard() }
    }

    private var topBar: some View {
        HStack {
            Button("닫기") { dismiss() }
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text("결산 카드")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            // Balance alignment
            Text("닫기").foregroundStyle(.clear)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var cardPreview: some View {
        if let img = previewImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Theme.violet.opacity(0.25), radius: 24, y: 10)
        } else {
            SummaryShareCardView(stats: stats, miniMeImage: miniMeImage)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 300, maxHeight: 435)
                .scaleEffect(300.0 / 360.0)
                .frame(maxWidth: 300, maxHeight: 435)
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if isRendering {
            ProgressView()
                .tint(Theme.violet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if let url = shareURL {
            ShareLink(item: url, preview: SharePreview(stats.kind.title)) {
                Label("공유하기", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @MainActor
    private func renderCard() async {
        isRendering = true
        let card = SummaryShareCardView(stats: stats, miniMeImage: miniMeImage)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let img = renderer.uiImage, let data = img.pngData() else {
            isRendering = false
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(stats.kind.shareFilename)
        try? data.write(to: url)
        previewImage = img
        shareURL = url
        isRendering = false
    }
}
