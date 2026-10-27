import SwiftUI
import Charts

// MARK: - Period stats model

struct SummaryPeriodStats {
    enum Kind {
        case monthly(year: Int, month: Int)
        case yearly(year: Int)

        var title: String {
            let L = AppLanguage.shared
            if L.isJapanese {
                switch self {
                case .monthly(let y, let m): return "\(y)年\(m)月"
                case .yearly(let y):        return "\(y)年"
                }
            }
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
                if y == currY && m == currM { return L.s("이번 달 결산", "This Month", ja: "今月のまとめ") }
                let diff = (currY - y) * 12 + (currM - m)
                return diff == 1
                    ? L.s("지난달 결산", "Last Month", ja: "先月のまとめ")
                    : L.s("\(diff)달 전 결산", "\(diff) Months Ago", ja: "\(diff)か月前のまとめ")
            case .yearly(let y):
                let currY = Calendar.current.component(.year, from: Date())
                if y == currY { return L.s("올해 결산", "This Year", ja: "今年のまとめ") }
                return y == currY - 1
                    ? L.s("작년 결산", "Last Year", ja: "昨年のまとめ")
                    : L.s("\(currY - y)년 전 결산", "\(currY - y) Years Ago", ja: "\(currY - y)年前のまとめ")
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
        return h > 0 ? "\(h)h \(m)m" : AppLanguage.shared.s("\(m)분", "\(m)m", ja: "\(m)分")
    }

    var avgPaceStr: String? {
        guard let secs = avgPacePerKmSec else { return nil }
        let adjusted = useMiles ? secs * 1.60934 : secs
        let total = Int(adjusted.rounded())
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
        return AppLanguage.shared.s("\(sign)\(delta)회", "\(sign)\(delta) runs", ja: "\(sign)\(delta)回")
    }

    var paceDeltaStr: String? {
        guard let curr = avgPacePerKmSec, let prev = compAvgPaceSecPerKm else { return nil }
        let delta = prev - curr
        let absDelta = Int((delta < 0 ? -delta : delta).rounded())
        guard absDelta >= 2 else { return nil }
        let m = absDelta / 60; let s = absDelta % 60
        let timeStr = m > 0 ? "\(m)′\(String(format: "%02d", s))″" : "\(s)″"
        return delta > 0
            ? AppLanguage.shared.s("\(timeStr) 빨라짐", "\(timeStr) faster", ja: "\(timeStr)速くなった")
            : AppLanguage.shared.s("\(timeStr) 느려짐", "\(timeStr) slower", ja: "\(timeStr)遅くなった")
    }

    var ytdStr: String? {
        guard case .monthly = kind, let km = ytdDistanceKm, km > 0 else { return nil }
        return AppLanguage.shared.s(String(format: "올해 누적 %.0fkm", km), String(format: "YTD %.0fkm", km), ja: String(format: "今年の累計 %.0fkm", km))
    }

    var isEmpty: Bool { activities.isEmpty }

    var dailyDistanceEntries: [(day: Int, value: Double)] {
        guard case .monthly(let year, let month) = kind else { return [] }
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = 1
        guard let start = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: start) else { return [] }
        var kmByDay: [Date: Double] = [:]
        for a in activities where a.type == .running {
            let dayStart = cal.startOfDay(for: a.date)
            let dc = cal.dateComponents([.year, .month], from: dayStart)
            if dc.year == year && dc.month == month {
                kmByDay[dayStart, default: 0] += a.distance / 1000
            }
        }
        let factor = useMiles ? 0.621371 : 1.0
        return range.compactMap { d -> (Int, Double)? in
            guard let date = cal.date(byAdding: .day, value: d - 1, to: start) else { return nil }
            return (d, (kmByDay[date] ?? 0) * factor)
        }
    }

    var monthlyDistanceEntries: [(month: Int, value: Double)] {
        guard case .yearly(let year) = kind else { return [] }
        let cal = Calendar.current
        var kmByMonth: [Int: Double] = [:]
        for a in activities where a.type == .running {
            let mo = cal.component(.month, from: a.date)
            let yr = cal.component(.year, from: a.date)
            if yr == year { kmByMonth[mo, default: 0] += a.distance / 1000 }
        }
        let factor = useMiles ? 0.621371 : 1.0
        return (1...12).map { m in (m, (kmByMonth[m] ?? 0) * factor) }
    }
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
        positive:       Theme.positive,
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

// MARK: - Common chrome (결산 카드 · 결산 묶음 슬라이드 공용)

/// 결산 카드 틀 — 384×480(4:5, 인스타 피드 묶음이 잘리지 않게 2026-10-28 폭 300→384, 높이·글자 크기는 그대로), 위 보라 막대 · 워드마크 + 미니미 · 기간 이름 · 구분선 · 내용 · 아래 러너 표시.
/// 결산 카드와 묶음 슬라이드가 모두 이 틀 하나를 쓴다(데이터 표시 통일성 — 장마다 머리를 따로 그리지 않는다).
struct SummaryCardChrome<Content: View>: View {
    let title: String
    let subtitle: String
    var miniMeImage: UIImage? = nil
    /// 미니미를 본문에서 크게 쓰는 장(제목 장)은 머리 미니미를 뺀다
    var showsMiniMe: Bool = true
    var theme: ShareTheme = .dark
    @ViewBuilder let content: () -> Content

    static var size: CGSize { CGSize(width: 384, height: 480) }

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
                        MIMOWordmark(size: 14, strokeMIMO: theme == .light)
                        Spacer()
                        if showsMiniMe {
                            SummaryMiniMe(image: miniMeImage, size: 43, theme: theme)
                        }
                    }
                    .frame(height: 43, alignment: .top)
                    .padding(.top, 12)
                    .padding(.bottom, 7)

                    // Period
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(p.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(p.brand)
                        .padding(.top, 2)

                    // Divider
                    Rectangle()
                        .fill(p.divider)
                        .frame(height: 0.5)
                        .padding(.top, 10)
                        .padding(.bottom, 10)

                    content()

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
        .frame(width: SummaryCardChrome<EmptyView>.size.width, height: SummaryCardChrome<EmptyView>.size.height)
        .environment(\.colorScheme, theme == .dark ? .dark : .light)
    }
}

/// 결산 카드 미니미 — 사용자 이미지가 있으면 원형, 없으면 마스코트(축하)
struct SummaryMiniMe: View {
    let image: UIImage?
    let size: CGFloat
    var theme: ShareTheme = .dark

    var body: some View {
        let p: SummaryCardPalette = theme == .light ? .light : .dark
        if let img = image {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(p.brand.opacity(0.4), lineWidth: 1.2 * size / 43))
        } else {
            MiniMeView(variant: .celebrating, size: size)
        }
    }
}

// MARK: - Period summary card (384 × 480, rendered via ImageRenderer)

struct SummaryShareCardView: View {
    let stats: SummaryPeriodStats
    var miniMeImage: UIImage? = nil
    var theme: ShareTheme = .dark

    private var p: SummaryCardPalette { theme == .light ? .light : .dark }

    var body: some View {
        SummaryCardChrome(title: stats.kind.title, subtitle: stats.kind.subtitle,
                          miniMeImage: miniMeImage, theme: theme) {
                    // Hero distance
                    SummaryHero(value: stats.distanceStr, unit: stats.distanceUnit,
                                label: AppLanguage.shared.s("총 거리", "TOTAL", ja: "総距離"), theme: theme)

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
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                    // Secondary stats
                    HStack(spacing: 0) {
                        secondaryCell(value: stats.durationStr,
                                      label: AppLanguage.shared.s("운동 시간", "TIME", ja: "運動時間"),
                                      labelColor: p.accentGold)
                        cellDivider
                        secondaryCell(value: AppLanguage.shared.s("\(stats.runCount)회", "\(stats.runCount)", ja: "\(stats.runCount)回"),
                                      label: AppLanguage.shared.s("러닝 횟수", "RUNS", ja: "ラン回数"),
                                      labelColor: p.brand)
                        if let pace = stats.avgPaceStr {
                            cellDivider
                            secondaryCell(value: pace,
                                          label: AppLanguage.shared.s("평균 페이스", "AVG PACE", ja: "平均ペース"),
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
                            Text(AppLanguage.shared.s("최장 거리", "LONGEST", ja: "最長距離"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(p.textSecondary)
                            Spacer()
                            Text(longest)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(p.textPrimary)
                        }
                    }

                    // Distance chart: daily (월별 결산) / monthly (연간 결산)
                    let dailyData   = stats.dailyDistanceEntries
                    let monthData   = stats.monthlyDistanceEntries
                    let showDaily   = dailyData.contains(where: { $0.value > 0 })
                    let showMonthly = monthData.contains(where: { $0.value > 0 })
                    if showDaily || showMonthly {
                        Rectangle()
                            .fill(p.divider)
                            .frame(height: 0.5)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                        HStack {
                            Text(showDaily
                                 ? AppLanguage.shared.s("일간 거리", "DAILY DIST", ja: "日別距離")
                                 : AppLanguage.shared.s("월간 거리", "MONTHLY DIST", ja: "月別距離"))
                                .font(.system(size: 8, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(p.textSecondary)
                            Spacer()
                            Text(stats.distanceUnit.uppercased())
                                .font(.system(size: 7, weight: .medium))
                                .foregroundStyle(p.axisLabel)
                        }
                        .padding(.bottom, 3)
                        if showDaily {
                            SummaryDailyDistanceChart(data: dailyData, palette: p)
                        } else {
                            SummaryMonthlyDistanceChart(data: monthData, palette: p)
                        }
                    }

                    Spacer(minLength: 0)

                    if let ytd = stats.ytdStr {
                        Text(ytd)
                            .font(.system(size: 9, weight: .medium))
                            .tracking(0.5)
                            .foregroundStyle(p.brand.opacity(0.6))
                            .padding(.bottom, 3)
                    }
        }
    }

    private func secondaryCell(value: String, label: String, labelColor: Color) -> some View {
        SummarySecondaryCell(value: value, label: label, labelColor: labelColor, theme: theme)
    }

    private var cellDivider: some View { SummaryCellDivider(theme: theme) }
}

// MARK: - 결산 카드 · 묶음 슬라이드 공용 조각 (값을 한 곳에서만 정한다)

/// 큰 숫자(55 콘덴스드) + 단위(18 보라) + 라벨(11)
struct SummaryHero: View {
    let value: String
    var unit: String? = nil
    let label: String
    var theme: ShareTheme = .dark

    var body: some View {
        let p: SummaryCardPalette = theme == .light ? .light : .dark
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 55, weight: .black, design: .default).width(.compressed))
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let unit {
                    Text(unit)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(p.brand)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(p.textSecondary)
        }
    }
}

/// 보조 지표 칸(값 16 · 라벨 11)
struct SummarySecondaryCell: View {
    let value: String
    let label: String
    let labelColor: Color
    var theme: ShareTheme = .dark

    var body: some View {
        let p: SummaryCardPalette = theme == .light ? .light : .dark
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
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SummaryCellDivider: View {
    var theme: ShareTheme = .dark

    var body: some View {
        let p: SummaryCardPalette = theme == .light ? .light : .dark
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
    /// 묶음 슬라이드 내용 — 있으면 '한 장 / 묶음'을 고를 수 있다(첫 장 = 결산 카드)
    var recap: PeriodRecap? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var summaryTheme: ShareTheme = .dark
    @State private var previewImages: [UIImage] = []
    /// 묶음 2번째 장부터(리듬·기록·추세·제목) — 첫 장은 previewImages[0]
    @State private var slideImages: [UIImage] = []
    /// 한 장(결산 카드) · 묶음(여러 장) · 한 장에 모두(묶음 내용을 4:5 한 장에)
    private enum ShareMode { case single, bundle, allInOne }
    @State private var shareMode: ShareMode = .single
    @State private var allInOneImage: UIImage? = nil
    @State private var isRendering = false
    @State private var activeShare: SingleShareConfig? = nil

    private struct SingleShareConfig: Identifiable {
        let id: Int
        let images: [UIImage]
    }

    private var bundleImages: [UIImage] { Array(previewImages.prefix(1)) + slideImages }

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
                        if recap != nil {
                            bundleToggle
                                .padding(.horizontal, 24)
                                .padding(.bottom, 12)
                        }
                        if shareMode == .allInOne, recap != nil {
                            VStack(spacing: 12) {
                                allInOnePreview
                                themeToggle
                                    .padding(.horizontal, 24)
                                allInOneShareButton
                                    .padding(.horizontal, 24)
                            }
                            .padding(.bottom, 32)
                        } else if shareMode == .bundle, recap != nil {
                            VStack(spacing: 12) {
                                bundlePreview
                                themeToggle
                                    .padding(.horizontal, 24)
                                bundleShareButton
                                    .padding(.horizontal, 24)
                            }
                            .padding(.bottom, 32)
                        } else {
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
            ShareSheet(images: config.images)
        }
    }

    private var topBar: some View {
        HStack {
            Button(AppLanguage.shared.s("닫기", "Close", ja: "閉じる")) { dismiss() }
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(isMonthly
                 ? AppLanguage.shared.s("월말 결산 데이터", "Monthly Summary", ja: "月末のまとめデータ")
                 : AppLanguage.shared.s("연말 결산 데이터", "Yearly Summary", ja: "年末のまとめデータ"))
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Text(AppLanguage.shared.s("닫기", "Close", ja: "閉じる")).foregroundStyle(.clear)
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
            // 렌더 전 — 출력 크기(384×480)를 미리보기 폭 300에 맞춰 줄여 보인다
            SummaryShareCardView(stats: statsList[index], miniMeImage: miniMeImage, theme: summaryTheme)
                .environment(\.colorScheme, summaryTheme == .dark ? .dark : .light)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .scaleEffect(300 / 384)
                .frame(width: 300, height: 375)
        }
    }

    private var themeToggle: some View {
        HStack(spacing: 0) {
            themeSegment(label: AppLanguage.shared.s("다크", "Dark", ja: "ダーク"),
                         selected: summaryTheme == .dark) { summaryTheme = .dark }
            themeSegment(label: AppLanguage.shared.s("라이트", "Light", ja: "ライト"),
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
                activeShare = SingleShareConfig(id: index, images: [previewImages[index]])
            } label: {
                Label(title + " " + AppLanguage.shared.s("러닝 마일리지 내보내기", "Running Mileage Export", ja: "走行距離を書き出す"),
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
                .environment(\.colorScheme, summaryTheme == .dark ? .dark : .light)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 3
            if let img = renderer.uiImage { images.append(img) }
        }
        previewImages = images
        var slides: [UIImage] = []
        if let recap, let stats = statsList.first {
            for slide in recap.slides {
                let view = PeriodRecapSlideView(slide: slide, recap: recap, stats: stats,
                                                miniMeImage: miniMeImage, theme: summaryTheme)
                    .environment(\.colorScheme, summaryTheme == .dark ? .dark : .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                if let img = renderer.uiImage { slides.append(img) }
            }
        }
        slideImages = slides
        allInOneImage = nil
        if let recap, let stats = statsList.first {
            let view = PeriodRecapAllInOneCard(recap: recap, stats: stats, miniMeImage: miniMeImage, theme: summaryTheme)
                .environment(\.colorScheme, summaryTheme == .dark ? .dark : .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            allInOneImage = renderer.uiImage
        }
        isRendering = false
    }

    /// 한 장 | 묶음 N장 | 한 장에 모두
    private var bundleToggle: some View {
        let L = AppLanguage.shared
        let n = 1 + (recap?.slides.count ?? 0)
        return HStack(spacing: 0) {
            themeSegment(label: L.s("한 장", "Single", ja: "1枚"), selected: shareMode == .single) { shareMode = .single }
            themeSegment(label: L.s("묶음 \(n)장", "Set of \(n)", ja: "まとめ\(n)枚"), selected: shareMode == .bundle) { shareMode = .bundle }
            themeSegment(label: L.s("한 장에 모두", "All in one", ja: "1枚に全部"), selected: shareMode == .allInOne) { shareMode = .allInOne }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    /// 묶음 미리보기 — 내보낼 이미지 그대로 좌우로 넘긴다(미리보기 = 출력)
    @ViewBuilder
    private var bundlePreview: some View {
        let images = bundleImages
        if isRendering || images.isEmpty {
            ProgressView()
                .tint(Theme.violet)
                .frame(width: 300, height: 375)
        } else {
            TabView {
                ForEach(images.indices, id: \.self) { i in
                    Image(uiImage: images[i])
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.bottom, 28)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 403)
        }
    }

    @ViewBuilder
    private var allInOnePreview: some View {
        if !isRendering, let img = allInOneImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Theme.violet.opacity(0.25), radius: 24, y: 10)
        } else {
            ProgressView()
                .tint(Theme.violet)
                .frame(width: 300, height: 375)
        }
    }

    @ViewBuilder
    private var allInOneShareButton: some View {
        if !isRendering, let img = allInOneImage {
            Button {
                activeShare = SingleShareConfig(id: -2, images: [img])
            } label: {
                Label(AppLanguage.shared.s("한 장에 모두 내보내기", "Export all-in-one", ja: "1枚にまとめて書き出す"),
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

    @ViewBuilder
    private var bundleShareButton: some View {
        if !isRendering, !bundleImages.isEmpty {
            let images = bundleImages
            Button {
                activeShare = SingleShareConfig(id: -1, images: images)
            } label: {
                Label(AppLanguage.shared.s("\(images.count)장 한꺼번에 내보내기", "Export \(images.count) images",
                                           ja: "\(images.count)枚まとめて書き出す"),
                      systemImage: "square.and.arrow.up.on.square")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

// MARK: - Monthly distance chart (yearly summary card)

private struct SummaryMonthlyDistanceChart: View {
    let data: [(month: Int, value: Double)]
    let palette: SummaryCardPalette

    private static let monthAbbr = ["", "J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    var body: some View {
        Chart(data.indices, id: \.self) { i in
            BarMark(
                x: .value("월", data[i].month),
                y: .value("거리", data[i].value),
                width: .fixed(14)
            )
            .foregroundStyle(data[i].value > 0 ? palette.monthlyBarColor.gradient : Color.clear.gradient)
            .cornerRadius(2)
        }
        .chartXScale(domain: 1...12)
        .chartXAxis {
            AxisMarks(values: [1, 3, 5, 7, 9, 11]) { value in
                AxisValueLabel {
                    let m = value.as(Int.self) ?? 0
                    Text(m > 0 && m < Self.monthAbbr.count ? Self.monthAbbr[m] : "")
                        .font(.system(size: 7))
                        .foregroundStyle(palette.axisLabel)
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 2)) { value in
                AxisValueLabel {
                    Text(String(format: "%.0f", value.as(Double.self) ?? 0))
                        .font(.system(size: 7))
                        .foregroundStyle(palette.axisLabel)
                }
                AxisGridLine()
                    .foregroundStyle(palette.gridLine)
            }
        }
        .frame(height: 100)
    }
}

// MARK: - Daily distance chart (summary card)

private struct SummaryDailyDistanceChart: View {
    let data: [(day: Int, value: Double)]
    let palette: SummaryCardPalette

    var body: some View {
        Chart(data.indices, id: \.self) { i in
            BarMark(
                x: .value("일", data[i].day),
                y: .value("거리", data[i].value),
                width: .fixed(5)
            )
            .foregroundStyle(data[i].value > 0 ? palette.monthlyBarColor.gradient : Color.clear.gradient)
            .cornerRadius(2)
        }
        .chartXScale(domain: 1...31)
        .chartXAxis {
            AxisMarks(values: [1, 7, 14, 21, 28]) { value in
                AxisValueLabel {
                    Text("\(value.as(Int.self) ?? 0)")
                        .font(.system(size: 7))
                        .foregroundStyle(palette.axisLabel)
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 2)) { value in
                AxisValueLabel {
                    Text(String(format: "%.0f", value.as(Double.self) ?? 0))
                        .font(.system(size: 7))
                        .foregroundStyle(palette.axisLabel)
                }
                AxisGridLine()
                    .foregroundStyle(palette.gridLine)
            }
        }
        .frame(height: 100)
    }
}
