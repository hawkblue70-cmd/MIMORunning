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

// MARK: - Palette

struct SummaryCardPalette {
    let background:    Color
    let accentBar:     Color
    let textPrimary:   Color
    let textSecondary: Color
    let divider:       Color
    let brand:         Color
    let boxFill:       Color
    let positive:      Color
    let negative:      Color
    let neutral:       Color
    let accentGold:    Color
    let accentTeal:    Color
    let watermark:     Color
    // 거리·연속 카드 전용
    let barChart:       Color   // 일간 거리 / 시간 막대
    let weeklyBarColor: Color   // 주간 거리 막대
    let monthlyBarColor:Color   // 월간 거리 막대
    let gridLine:       Color   // 차트 그리드선
    let axisLabel:      Color   // 축 숫자
    let heatEmpty:      Color   // 잔디 빈 칸
    let heatLow:        Color   // 잔디 1단계
    let heatMid:        Color   // 잔디 2단계
    let heatHigh:       Color   // 잔디 3단계
    let heatFull:       Color   // 잔디 4단계 (최대)

    static let dark = SummaryCardPalette(
        background:     Color(hex: "131320"),
        accentBar:      Color(hex: "7C5CFC"),
        textPrimary:    .white,
        textSecondary:  Color(hex: "8A8F99"),
        divider:        Color.white.opacity(0.14),
        brand:          Color(hex: "8B7FF0"),
        boxFill:        Color.white.opacity(0.06),
        positive:       Color(hex: "5CE08A"),
        negative:       Color(hex: "FF9A3C"),
        neutral:        Color(hex: "8A8F99"),
        accentGold:     Color(hex: "F5C542"),
        accentTeal:     Color(hex: "5CE5D5"),
        watermark:      Color(hex: "6B6B8A"),
        barChart:       Color(hex: "F5C542"),
        weeklyBarColor: Color(hex: "5CE5D5"),
        monthlyBarColor:Color(hex: "30D158"),
        gridLine:       Color.white.opacity(0.10),
        axisLabel:      Color(hex: "6B7280"),
        heatEmpty:      Color(hex: "FF9F0A").opacity(0.10),
        heatLow:        Color(hex: "FF9F0A").opacity(0.32),
        heatMid:        Color(hex: "FF9F0A").opacity(0.56),
        heatHigh:       Color(hex: "FF9F0A").opacity(0.80),
        heatFull:       Color(hex: "FF9F0A")
    )

    static let light = SummaryCardPalette(
        background:     Color(hex: "FFFFFF"),
        accentBar:      Color(hex: "5B3FD9"),
        textPrimary:    Color(hex: "0D0D0D"),
        textSecondary:  Color(hex: "8A8A8A"),
        divider:        Color.black.opacity(0.10),
        brand:          Color(hex: "5B3FD9"),
        boxFill:        Color(hex: "F7F6F3"),
        positive:       Color(hex: "1B7F3B"),
        negative:       Color(hex: "D9600A"),
        neutral:        Color(hex: "8A8A8A"),
        accentGold:     Color(hex: "C98A00"),
        accentTeal:     Color(hex: "0E7C8A"),
        watermark:      Color(hex: "B0AEA8"),
        barChart:       Color(hex: "C98A00"),
        weeklyBarColor: Color(hex: "0E7C8A"),
        monthlyBarColor:Color(hex: "248A3D"),
        gridLine:       Color.black.opacity(0.08),
        axisLabel:      Color(hex: "9A9A9A"),
        heatEmpty:      Color(hex: "FF9F0A").opacity(0.10),
        heatLow:        Color(hex: "FF9F0A").opacity(0.32),
        heatMid:        Color(hex: "FF9F0A").opacity(0.56),
        heatHigh:       Color(hex: "FF9F0A").opacity(0.80),
        heatFull:       Color(hex: "FF9F0A")
    )
}

// MARK: - Athletic share card (300 × 375, rendered via ImageRenderer)

struct SummaryShareCardView: View {
    let stats: SummaryPeriodStats
    var miniMeImage: UIImage? = nil
    var theme: ShareTheme = .dark

    private var p: SummaryCardPalette { theme == .light ? .light : .dark }

    var body: some View {
        ZStack(alignment: .top) {
            p.background

            VStack(alignment: .leading, spacing: 0) {
                // Accent bar
                Rectangle()
                    .fill(p.accentBar)
                    .frame(height: 3)

                VStack(alignment: .leading, spacing: 0) {
                    // Wordmark + MiniMe
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 0) {
                                MIMOWordmark(size: 14, mimoColor: p.textPrimary, runColor: p.brand)
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
                        .foregroundStyle(p.textPrimary)
                    Text(stats.kind.subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(p.brand)
                        .padding(.top, 2)

                    // Divider
                    Rectangle()
                        .fill(p.divider)
                        .frame(height: 0.5)
                        .padding(.top, 13)
                        .padding(.bottom, 16)

                    // Hero distance
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(stats.distanceStr)
                            .font(.system(size: 55, weight: .black, design: .default).width(.compressed))
                            .foregroundStyle(p.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Text(stats.distanceUnit)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(p.brand)
                    }
                    Text(AppLanguage.shared.s("총 거리", "TOTAL"))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(p.textSecondary)

                    if let delta = stats.distanceDeltaStr {
                        HStack(spacing: 3) {
                            Image(systemName: stats.distanceDeltaIsUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(delta)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(p.neutral)
                        .padding(.top, 1)
                    }

                    Spacer(minLength: 0)

                    // Thin separator
                    Rectangle()
                        .fill(p.divider)
                        .frame(height: 0.5)
                        .padding(.top, 14)
                        .padding(.bottom, 12)

                    // Secondary stats
                    HStack(spacing: 0) {
                        secondaryCell(value: stats.durationStr,
                                      label: AppLanguage.shared.s("운동 시간", "TIME"),
                                      labelColor: p.accentGold)
                        cellDivider
                        secondaryCell(value: AppLanguage.shared.s("\(stats.runCount)회", "\(stats.runCount)"),
                                      label: AppLanguage.shared.s("러닝 횟수", "RUNS"),
                                      labelColor: p.brand)
                        if let pace = stats.avgPaceStr {
                            cellDivider
                            secondaryCell(value: pace,
                                          label: AppLanguage.shared.s("평균 페이스", "AVG PACE"),
                                          labelColor: p.accentTeal)
                        }
                    }

                    // Longest run
                    if let longest = stats.longestStr {
                        Rectangle()
                            .fill(p.divider)
                            .frame(height: 0.5)
                            .padding(.vertical, 9)
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(p.brand)
                            Text(AppLanguage.shared.s("최장 거리", "LONGEST"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(p.textSecondary)
                            Spacer()
                            Text(longest)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(p.textPrimary)
                        }
                    }

                    Spacer(minLength: 6)

                    if let ytd = stats.ytdStr {
                        Text(ytd)
                            .font(.system(size: 9, weight: .medium))
                            .tracking(0.5)
                            .foregroundStyle(p.brand.opacity(0.6))
                            .padding(.bottom, 3)
                    }

                    // Footer
                    HStack {
                        Spacer()
                        Image(systemName: "figure.run")
                            .font(.system(size: 7))
                            .foregroundStyle(p.brand.opacity(0.45))
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
                .overlay(Circle().stroke(p.brand.opacity(0.4), lineWidth: 1.2))
        } else {
            MiniMeView(variant: .celebrating, size: 43)
        }
    }

    private func secondaryCell(value: String, label: String, labelColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(p.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(labelColor.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(p.divider)
            .frame(width: 0.5, height: 27)
            .padding(.horizontal, 8)
    }
}

// MARK: - Share screen (presented as sheet)

struct SummaryShareCardScreen: View {
    let statsList: [SummaryPeriodStats]
    var miniMeImage: UIImage? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var summaryTheme: ShareTheme = .dark
    @State private var previewImages: [UIImage] = []
    @State private var isRendering = false
    @State private var activeShare: SingleShareConfig? = nil

    private struct SingleShareConfig: Identifiable {
        let id: Int
        let image: UIImage
    }

    private var isMonthly: Bool {
        if let first = statsList.first, case .monthly = first.kind { return true }
        return false
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(statsList.indices, id: \.self) { i in
                            VStack(spacing: 12) {
                                cardPreview(index: i)
                                themeToggle
                                    .padding(.horizontal, 24)
                                cardShareButton(index: i)
                                    .padding(.horizontal, 24)
                            }
                            .padding(.bottom, 32)
                        }
                        Spacer(minLength: 16)
                    }
                    .padding(.top, 20)
                }
            }
        }
        .task { await renderCards() }
        .onChange(of: summaryTheme) { Task { await renderCards() } }
        .sheet(item: $activeShare) { config in
            ShareSheet(images: [config.image])
        }
    }

    private var topBar: some View {
        HStack {
            Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(isMonthly
                 ? AppLanguage.shared.s("월말 결산 데이터", "Monthly Summary")
                 : AppLanguage.shared.s("연말 결산 데이터", "Yearly Summary"))
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Text(AppLanguage.shared.s("닫기", "Close")).foregroundStyle(.clear)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func cardPreview(index: Int) -> some View {
        if index < previewImages.count {
            Image(uiImage: previewImages[index])
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Theme.violet.opacity(0.25), radius: 24, y: 10)
        } else {
            SummaryShareCardView(stats: statsList[index], miniMeImage: miniMeImage, theme: summaryTheme)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 300, maxHeight: 375)
        }
    }

    private var themeToggle: some View {
        HStack(spacing: 0) {
            themeSegment(label: AppLanguage.shared.s("다크", "Dark"),
                         selected: summaryTheme == .dark) { summaryTheme = .dark }
            themeSegment(label: AppLanguage.shared.s("라이트", "Light"),
                         selected: summaryTheme == .light) { summaryTheme = .light }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func themeSegment(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Theme.violet : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Theme.violet.opacity(0.22) : Color.white.opacity(0.08))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }

    @ViewBuilder
    private func cardShareButton(index: Int) -> some View {
        if isRendering {
            ProgressView()
                .tint(Theme.violet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if index < previewImages.count {
            let title = statsList[index].kind.title
            Button {
                activeShare = SingleShareConfig(id: index, image: previewImages[index])
            } label: {
                Label(title + " " + AppLanguage.shared.s("러닝 마일리지 내보내기", "Running Mileage Export"),
                      systemImage: "square.and.arrow.up")
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
    private func renderCards() async {
        isRendering = true
        previewImages = []
        await Task.yield()
        var images: [UIImage] = []
        for stats in statsList {
            let card = SummaryShareCardView(stats: stats, miniMeImage: miniMeImage, theme: summaryTheme)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 3
            if let img = renderer.uiImage { images.append(img) }
        }
        previewImages = images
        isRendering = false
    }
}
