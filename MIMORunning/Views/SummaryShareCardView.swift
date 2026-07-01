import SwiftUI

// MARK: - Period stats model

struct SummaryPeriodStats {
    enum Kind {
        case monthly(year: Int, month: Int)
        case yearly(year: Int)

        var title: String {
            let L = AppLanguage.shared
            if L.isEnglish {
                switch self {
                case .monthly(let y, let m):
                    let df = DateFormatter()
                    df.dateFormat = "MMMM yyyy"
                    df.locale = Locale(identifier: "en_US")
                    var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = 1
                    if let d = Calendar.current.date(from: comps) { return df.string(from: d) }
                    return "\(y)/\(m)"
                case .yearly(let y): return "\(y)"
                }
            }
            switch self {
            case .monthly(let y, let m): return "\(y)년 \(m)월"
            case .yearly(let y):        return "\(y)년"
            }
        }

        var subtitle: String {
            let L = AppLanguage.shared
            switch self {
            case .monthly(let y, let m):
                let cal = Calendar.current
                let now = Date()
                let currY = cal.component(.year,  from: now)
                let currM = cal.component(.month, from: now)
                if y == currY && m == currM { return L.s("이번 달 결산", "This Month") }
                let diff = (currY - y) * 12 + (currM - m)
                return diff == 1
                    ? L.s("지난달 결산", "Last Month")
                    : L.s("\(diff)달 전 결산", "\(diff) Months Ago")
            case .yearly(let y):
                let currY = Calendar.current.component(.year, from: Date())
                if y == currY { return L.s("올해 결산", "This Year") }
                return y == currY - 1
                    ? L.s("작년 결산", "Last Year")
                    : L.s("\(currY - y)년 전 결산", "\(currY - y) Years Ago")
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

    var compDistanceKm: Double? = nil
    var compRunCount: Int? = nil
    var compAvgPaceSecPerKm: Double? = nil
    var ytdDistanceKm: Double? = nil

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
        return h > 0 ? "\(h)h \(m)m" : AppLanguage.shared.s("\(m)분", "\(m)m")
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

    var distanceDeltaIsUp: Bool {
        totalDistanceKm >= (compDistanceKm ?? totalDistanceKm)
    }

    var distanceDeltaStr: String? {
        guard let prev = compDistanceKm, prev > 0 else { return nil }
        let delta = totalDistanceKm - prev
        let pct = delta / prev * 100
        let sign = delta >= 0 ? "+" : ""
        return String(format: "\(sign)%.1fkm (%.0f%%)", delta, pct)
    }

    var runCountDeltaStr: String? {
        guard let prev = compRunCount else { return nil }
        let delta = runCount - prev
        let sign = delta >= 0 ? "+" : ""
        return AppLanguage.shared.s("\(sign)\(delta)회", "\(sign)\(delta) runs")
    }

    var paceDeltaStr: String? {
        guard let curr = avgPacePerKmSec, let prev = compAvgPaceSecPerKm else { return nil }
        let delta = prev - curr
        let absDelta = Int((delta < 0 ? -delta : delta).rounded())
        guard absDelta >= 2 else { return nil }
        let m = absDelta / 60; let s = absDelta % 60
        let timeStr = m > 0 ? "\(m)′\(String(format: "%02d", s))″" : "\(s)″"
        return delta > 0
            ? AppLanguage.shared.s("\(timeStr) 빨라짐", "\(timeStr) faster")
            : AppLanguage.shared.s("\(timeStr) 느려짐", "\(timeStr) slower")
    }

    var ytdStr: String? {
        guard case .monthly = kind, let km = ytdDistanceKm, km > 0 else { return nil }
        return AppLanguage.shared.s(String(format: "올해 누적 %.0fkm", km), String(format: "YTD %.0fkm", km))
    }

    var isEmpty: Bool { activities.isEmpty }
}

// MARK: - Athletic share card (300 × 375, rendered via ImageRenderer)
// Scale applied: width 5/6 (fonts), height 375/520 ≈ 0.721 (vertical spacing)

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
                                    .font(.system(size: 8, weight: .black))
                                    .tracking(2)
                                    .foregroundStyle(.white)
                                Text(" RUNNING")
                                    .font(.system(size: 8, weight: .bold))
                                    .tracking(2)
                                    .foregroundStyle(Theme.violet)
                            }
                        }
                        Spacer()
                        miniMeContent
                            .frame(width: 43, height: 43)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 7)

                    // Period
                    Text(stats.kind.title)
                        .font(.system(size: 18, weight: .bold))
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
                        .padding(.top, 13)
                        .padding(.bottom, 16)

                    // Hero distance
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(stats.distanceStr)
                            .font(.system(size: 55, weight: .black, design: .default).width(.compressed))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Text(stats.distanceUnit)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.violet)
                    }
                    Text(AppLanguage.shared.s("총 거리", "TOTAL"))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.4))

                    if let delta = stats.distanceDeltaStr {
                        HStack(spacing: 3) {
                            Image(systemName: stats.distanceDeltaIsUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(delta)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(stats.distanceDeltaIsUp
                            ? Color.green
                            : Color(red: 1, green: 0.45, blue: 0.45))
                        .padding(.top, 1)
                    }

                    Spacer(minLength: 0)

                    // Thin separator
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.top, 14)
                        .padding(.bottom, 12)

                    // Secondary stats
                    HStack(spacing: 0) {
                        secondaryCell(value: stats.durationStr,    label: AppLanguage.shared.s("운동 시간", "TIME"),     color: Theme.time)
                        cellDivider
                        secondaryCell(value: AppLanguage.shared.s("\(stats.runCount)회", "\(stats.runCount)"), label: AppLanguage.shared.s("러닝 횟수", "RUNS"), color: Theme.violet)
                        if let pace = stats.avgPaceStr {
                            cellDivider
                            secondaryCell(value: pace, label: AppLanguage.shared.s("평균 페이스", "AVG PACE"), color: Theme.pace)
                        }
                    }

                    // Longest run
                    if let longest = stats.longestStr {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 0.5)
                            .padding(.vertical, 9)
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.violet)
                            Text(AppLanguage.shared.s("최장 거리", "LONGEST"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                            Spacer()
                            Text(longest)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }

                    Spacer(minLength: 6)

                    if let ytd = stats.ytdStr {
                        Text(ytd)
                            .font(.system(size: 9, weight: .medium))
                            .tracking(0.5)
                            .foregroundStyle(Theme.violet.opacity(0.6))
                            .padding(.bottom, 3)
                    }

                    // Footer
                    HStack {
                        Spacer()
                        Image(systemName: "figure.run")
                            .font(.system(size: 7))
                            .foregroundStyle(Theme.violet.opacity(0.35))
                    }
                    .padding(.bottom, 2)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 13)
            }
        }
        .frame(width: 300, height: 375)
    }

    @ViewBuilder
    private var miniMeContent: some View {
        if let img = miniMeImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 43, height: 43)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.violet.opacity(0.4), lineWidth: 1.2))
        } else {
            MiniMeView(variant: .celebrating, size: 43)
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
                .font(.system(size: 11, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(color.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 0.5, height: 27)
            .padding(.horizontal, 8)
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
            Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(AppLanguage.shared.s("결산 카드", "Summary Card"))
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            // Balance alignment
            Text(AppLanguage.shared.s("닫기", "Close")).foregroundStyle(.clear)
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
                Label(AppLanguage.shared.s("공유하기", "Share"), systemImage: "square.and.arrow.up")
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
