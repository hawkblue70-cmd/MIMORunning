import SwiftUI
import Charts

// MARK: - Static Sparkline (ImageRenderer-safe — no async loading)

private struct ShareSparkline: View {
    let dataPoints: [(date: Date, value: Double)]
    let color: Color

    var body: some View {
        if dataPoints.count >= 2 {
            let values = dataPoints.map(\.value)
            let minVal = values.min() ?? 0
            let maxVal = values.max() ?? 1
            let spread = maxVal - minVal
            let yPad   = spread > 0 ? spread * 0.4 : max(maxVal * 0.05, 1.0)

            Chart(dataPoints, id: \.date) { pt in
                LineMark(
                    x: .value("D", pt.date),
                    y: .value("V", pt.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("D", pt.date),
                    y: .value("V", pt.value)
                )
                .symbol(HollowCircle())
                .foregroundStyle(color)
                .symbolSize(10)
            }
            .chartYScale(domain: (minVal - yPad)...(maxVal + yPad))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        } else {
            Color.clear
        }
    }
}

// MARK: - WeeklyPalette (dark / light theme for weekly share card)

private struct WeeklyPalette {
    let isLight:         Bool
    let background:      Color          // solid color; dark uses gradient separately
    let textPrimary:     Color
    let textSecondary:   Color
    let wordmarkMIMO:    Color
    let wordmarkRunning: Color
    let divider:         Color
    let weekLabel:       Color
    let tileBg:          Color
    let tileValue:       Color
    let tileLabel:       Color
    let sparkBg:         Color
    let sparkMetricLabel: Color
    let sparkValue:      Color
    let sparkRatio:      Color
    let insightBg:       Color
    let insightText:     Color
    let insightIcon:     Color
    let trendGood:       Color
    let trendBad:        Color
    let trendNeutral:    Color
    let runnerIcon:      Color
    let runnerIconBg:    Color
    let watermark:       Color

    static let dark = WeeklyPalette(
        isLight:          false,
        background:       Color(hex: "0D0D12"),
        textPrimary:      .white,
        textSecondary:    .white.opacity(0.50),
        wordmarkMIMO:     .white,
        wordmarkRunning:  Color(hex: "8B7FF0"),
        divider:          Theme.violet.opacity(0.35),
        weekLabel:        .white.opacity(0.75),
        tileBg:           Color.white.opacity(0.07),
        tileValue:        .white,
        tileLabel:        .white.opacity(0.40),
        sparkBg:          Color.white.opacity(0.05),
        sparkMetricLabel: .white.opacity(0.50),
        sparkValue:       .white,
        sparkRatio:       Color(hex: "6E6E78"),
        insightBg:        Theme.violet.opacity(0.16),
        insightText:      Color(hex: "D5CEFF"),
        insightIcon:      Color(hex: "8B7FF0"),
        trendGood:        Color(hex: "5CE08A"),
        trendBad:         Color(hex: "FF9A3C"),
        trendNeutral:     Color(hex: "8B7FF0"),
        runnerIcon:       Color(hex: "5CE08A"),
        runnerIconBg:     Color(hex: "5CE08A").opacity(0.12),
        watermark:        Color(hex: "5A5F6B")
    )

    static let light = WeeklyPalette(
        isLight:          true,
        background:       Color(hex: "FFFFFF"),
        textPrimary:      Color(hex: "111111"),
        textSecondary:    Color(hex: "8A8A8A"),
        wordmarkMIMO:     Color(hex: "111111"),
        wordmarkRunning:  Color(hex: "5B3FD9"),
        divider:          Color.black.opacity(0.10),
        weekLabel:        Color(hex: "111111").opacity(0.75),
        tileBg:           Color(hex: "F4F3EF"),
        tileValue:        Color(hex: "111111"),
        tileLabel:        Color(hex: "8A8A8A"),
        sparkBg:          Color(hex: "F7F6F3"),
        sparkMetricLabel: Color(hex: "8A8A8A"),
        sparkValue:       Color(hex: "111111"),
        sparkRatio:       Color(hex: "8A8A8A"),
        insightBg:        Color(hex: "F0EDFC"),
        insightText:      Color(hex: "3D2E8A"),
        insightIcon:      Color(hex: "5B3FD9"),
        trendGood:        Color(hex: "1B7F3B"),
        trendBad:         Color(hex: "D9600A"),
        trendNeutral:     Color(hex: "5B3FD9"),
        runnerIcon:       Color(hex: "1B7F3B"),
        runnerIconBg:     Color(hex: "1B7F3B").opacity(0.12),
        watermark:        Color(hex: "B0AEA8")
    )
}

// MARK: - Weekly Growth Share Card

struct WeeklyGrowthShareCard: View {
    let km: Double
    let mins: Double
    let count: Int
    let streak: Int
    let insightText: String?
    let insightSymbol: String?
    let insightColor: Color?   // kept for API compat; palette drives icon color
    let sparkData: [(metric: TrendMetric, points: [(date: Date, value: Double)])]
    var theme: ShareTheme = .dark
    /// true 이면 체중·체지방을 sparkGrid에서 제외 (내보내기 전용)
    var excludeBodyMetrics: Bool = false

    private var pal: WeeklyPalette { theme == .light ? .light : .dark }

    private var visibleSparkData: [(metric: TrendMetric, points: [(date: Date, value: Double)])] {
        excludeBodyMetrics
            ? sparkData.filter { $0.metric != .bodyMass && $0.metric != .bodyFatPercentage }
            : sparkData
    }

    var body: some View {
        ZStack {
            // Dark uses gradient; light uses solid white
            if pal.isLight {
                pal.background
            } else {
                LinearGradient(
                    colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    wordmarkRow
                    Spacer()
                    weekLabel
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                divider.padding(.top, 10)

            Text(AppLanguage.shared.s("주간 트렌드", "Weekly Trend"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(pal.wordmarkRunning)
                .padding(.horizontal, 20)
                .padding(.top, 6)

            statTiles
                .padding(.horizontal, 16)
                .padding(.top, 7)

                if let text = insightText {
                    insightBanner(text: text)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }

                if !visibleSparkData.isEmpty {
                    divider.padding(.top, 10)
                    sparkGrid
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }

                Spacer(minLength: 10)
            }
        }
    }

    // MARK: - Subviews

    private var wordmarkRow: some View {
        MIMOWordmark(size: 9, strokeMIMO: pal.isLight)
    }

    private var divider: some View {
        Rectangle()
            .fill(pal.divider)
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    private var weekLabel: some View {
        Text(weekRangeString)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(pal.weekLabel)
    }

    private var statTiles: some View {
        HStack(spacing: 6) {
            weekTile(value: kmString,
                     label: AppLanguage.shared.s("거리", "Distance"))
            weekTile(value: timeString,
                     label: AppLanguage.shared.s("시간", "Time"))
            weekTile(value: AppLanguage.shared.s("\(count)회", "\(count)"),
                     label: AppLanguage.shared.s("횟수", "Runs"))
            if streak > 0 {
                weekTile(value: AppLanguage.shared.s("\(streak)주", "\(streak)wk"),
                         label: AppLanguage.shared.s("연속", "Streak"))
            }
        }
    }

    private func weekTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(pal.tileValue)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(pal.tileLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(pal.tileBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func insightBanner(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let sym = insightSymbol {
                Image(systemName: sym)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(pal.insightIcon)
                    .padding(.top, 1)
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(pal.insightText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(pal.insightBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // 2-column grid using HStack/VStack — LazyVGrid는 ImageRenderer 비호환
    private var sparkGrid: some View {
        let rows = stride(from: 0, to: visibleSparkData.count, by: 2).map { i in
            Array(visibleSparkData[i..<min(i + 2, visibleSparkData.count)])
        }
        return VStack(spacing: 4) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(0..<rows[r].count, id: \.self) { i in
                        sparkCell(metric: rows[r][i].metric, dataPoints: rows[r][i].points)
                    }
                    if rows[r].count == 1 { Spacer() }
                }
            }
        }
    }

    private func sparkCell(metric: TrendMetric,
                            dataPoints: [(date: Date, value: Double)]) -> some View {
        let analysis  = trendDirection(values: dataPoints.map(\.value))
        let isNeutral = metric == .bodyMass || metric == .bodyFatPercentage
        let sentiment = trendSentiment(direction: analysis.direction,
                                       lowerIsBetter: metric.lowerIsBetter,
                                       isNeutral: isNeutral)
        // 좋아짐/나빠짐/중립 판정에 따라 색 통일
        let trendColor: Color = {
            switch sentiment {
            case .good:    return pal.trendGood
            case .bad:     return pal.trendBad
            default:       return pal.trendNeutral
            }
        }()
        let arrow: String? = {
            switch analysis.direction {
            case .up:   return "↑"
            case .down: return "↓"
            default:    return nil
            }
        }()
        let ratio = analysis.changeRatio
        let ratioStr: String? = analysis.direction != .insufficient
            ? String(format: "%@%.1f%%", ratio >= 0 ? "+" : "−", abs(ratio * 100))
            : nil

        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(metric.koreanLabel)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(pal.sparkMetricLabel)
                Spacer()
                if let a = arrow {
                    Text(a)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(trendColor)
                }
            }
            if let cur = dataPoints.last?.value {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(metric.formattedValue(cur))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(pal.sparkValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let r = ratioStr {
                        Text(r)
                            .font(.system(size: 7))
                            .foregroundStyle(pal.sparkRatio)
                    }
                }
            }
            ShareSparkline(dataPoints: dataPoints, color: metric.sparkColor)
                .frame(height: 18)
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(pal.sparkBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Computed helpers

    private var weekRangeString: String {
        let cal     = Calendar.current
        let today   = Date()
        let weekday = cal.component(.weekday, from: today)
        let daysFromMon = (weekday + 5) % 7   // Mon=0, Tue=1 … Sun=6
        guard let monday = cal.date(byAdding: .day, value: -daysFromMon, to: today),
              let sunday = cal.date(byAdding: .day, value: 6, to: monday) else {
            return ""
        }
        let year = cal.component(.year,  from: monday)
        let mMon = cal.component(.month, from: monday)
        let dMon = cal.component(.day,   from: monday)
        let mSun = cal.component(.month, from: sunday)
        let dSun = cal.component(.day,   from: sunday)

        if AppLanguage.shared.isEnglish {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US")
            df.dateFormat = "MMM d"
            if mMon == mSun {
                return "\(df.string(from: monday)) – \(dSun), \(year)"
            } else {
                return "\(df.string(from: monday)) – \(df.string(from: sunday)), \(year)"
            }
        }
        if mMon == mSun {
            return "\(year). \(mMon). \(dMon) ~ \(dSun)"
        } else {
            return "\(year). \(mMon). \(dMon) ~ \(mSun). \(dSun)"
        }
    }

    private var kmString: String {
        km >= 10
            ? String(format: "%.1fkm", km)
            : String(format: "%.2fkm", km)
    }

    private var timeString: String {
        let total = Int(mins)
        let h = total / 60
        let m = total % 60
        if AppLanguage.shared.isEnglish { return h > 0 ? "\(h)h \(m)m" : "\(m)m" }
        return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
    }
}

// MARK: - Weekly Growth Share Card Screen

struct WeeklyGrowthShareCardScreen: View {
    let km: Double
    let mins: Double
    let count: Int
    let streak: Int
    let insightText: String?
    let insightSymbol: String?
    let insightColor: Color?
    /// GrowthView가 이미 로드한 스파크 데이터 — nil이면 자체 조회 폴백
    var preloadedSparkData: [(metric: TrendMetric, points: [(date: Date, value: Double)])]? = nil
    let manager: HealthKitManager

    @State private var sparkData: [(metric: TrendMetric, points: [(date: Date, value: Double)])] = []
    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @State private var showShareSheet = false
    @State private var weeklyTheme: ShareTheme = .dark
    @Environment(\.dismiss) private var dismiss

    private let cardW: CGFloat = 300
    private let cardH: CGFloat = 375

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer()

                    // Card preview — always the live view for instant theme switching
                    WeeklyGrowthShareCard(
                        km: km, mins: mins, count: count, streak: streak,
                        insightText: insightText,
                        insightSymbol: insightSymbol,
                        insightColor: insightColor,
                        sparkData: sparkData,
                        theme: weeklyTheme,
                        excludeBodyMetrics: true
                    )
                    .environment(\.colorScheme, weeklyTheme == .dark ? .dark : .light)
                    .frame(width: cardW, height: cardH)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Theme.violet.opacity(0.30), radius: 28, y: 10)

                    Spacer(minLength: 20)

                    themeToggle
                        .padding(.horizontal, 24)

                    Spacer(minLength: 12)

                    shareCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }
            }
            .navigationTitle(AppLanguage.shared.s("이번주 러닝 데이터", "This Week's Running"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Theme.violet)
                }
            }
        }
        .task {
            // 부모가 이미 로드한 데이터 사용 — 재조회 없음
            // 없으면(앱 초기 실행 직후 시트를 매우 빠르게 열었을 때) 자체 조회 폴백
            if let preloaded = preloadedSparkData {
                sparkData = preloaded
            } else {
                await fetchSparkData()
            }
            await renderCard()
        }
        .onChange(of: weeklyTheme) {
            Task { await renderCard() }
        }
    }

    // MARK: - Theme toggle

    private var themeToggle: some View {
        HStack(spacing: 0) {
            themeSegment(label: AppLanguage.shared.s("다크", "Dark"), selected: weeklyTheme == .dark) {
                weeklyTheme = .dark
            }
            themeSegment(label: AppLanguage.shared.s("라이트", "Light"), selected: weeklyTheme == .light) {
                weeklyTheme = .light
            }
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

    // MARK: - Share CTA

    @ViewBuilder
    private var shareCTA: some View {
        if isRendering {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.violet)
                Text(AppLanguage.shared.s("카드 만드는 중...", "Creating card..."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        } else if previewImage != nil {
            Button { showShareSheet = true } label: {
                Label(AppLanguage.shared.s("이번주 러닝 내보내기", "Export This Week"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .sheet(isPresented: $showShareSheet) {
                if let img = previewImage { ShareSheet(images: [img]) }
            }
        } else {
            Text(AppLanguage.shared.s("카드 생성에 실패했어요", "Card creation failed"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
    }

    // MARK: - Fetch spark data (all 8 metrics, show only those with data)

    private func fetchSparkData() async {
        let since = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        let metrics: [TrendMetric] = [
            .cadence, .power, .groundContactTime, .strideLength,
            .verticalOscillation, .vo2Max, .bodyMass, .bodyFatPercentage
        ]

        var result: [(TrendMetric, [(date: Date, value: Double)])] = []
        await withTaskGroup(of: (TrendMetric, [(date: Date, value: Double)]).self) { group in
            for m in metrics {
                group.addTask {
                    let pts = await self.manager.fetchMetricHistory(m, from: since)
                    return (m, pts)
                }
            }
            for await item in group { result.append(item) }
        }

        // Preserve display order, skip metrics with no data
        sparkData = metrics.compactMap { m in
            guard let found = result.first(where: { $0.0 == m }), !found.1.isEmpty else {
                return nil
            }
            return (metric: m, points: found.1)
        }
    }

    // MARK: - Render

    @MainActor
    private func renderCard() async {
        isRendering = true
        let renderer = ImageRenderer(content:
            WeeklyGrowthShareCard(
                km: km, mins: mins, count: count, streak: streak,
                insightText: insightText,
                insightSymbol: insightSymbol,
                insightColor: insightColor,
                sparkData: sparkData,
                theme: weeklyTheme,
                excludeBodyMetrics: true
            )
            .environment(\.colorScheme, weeklyTheme == .dark ? .dark : .light)
            .frame(width: cardW, height: cardH)
        )
        renderer.scale = 3
        previewImage = renderer.uiImage
        isRendering = false
    }
}

// MARK: - Heatmap share data types

struct ShareHeatmapDay {
    let km: Double
    let isFuture: Bool
}

struct ShareHeatmapColumn: Identifiable {
    let id: Date
    let days: [ShareHeatmapDay]
}

// MARK: - Mileage + Streak combined share card

/// 성장 탭 "러닝 흐름" 카드를 그대로 내보내는 공유 카드.
/// §5.8 — 차트는 `RecordBarChart`(exportMode) **하나**를 재사용한다. 별도 레이아웃 금지.
struct MileageStreakShareCard: View {
    let bars: [RecordBar]
    let period: RecordPeriod
    let windowStart: Date
    let windowEnd: Date
    /// "최근 30일" / "8월" / "최근 12주"
    let periodLabel: String
    let heatmapColumns: [ShareHeatmapColumn]
    let streak: Int
    let activeDays: Int
    let heatmapWeekCount: Int
    var theme: ShareTheme = .dark

    private var p: SummaryCardPalette { theme == .light ? .light : .dark }

    private static let cellSize: CGFloat = 10
    private static let cellGap:  CGFloat = 2
    private static let labelW:   CGFloat = 10

    var body: some View {
        ZStack {
            if theme == .light {
                p.background
            } else {
                LinearGradient(
                    colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            VStack(alignment: .leading, spacing: 0) {
                wordmarkRow
                    .padding(.horizontal, 20)
                    .padding(.top, 13)

                divider.padding(.top, 7)

                flowTitleRow
                    .padding(.horizontal, 20)
                    .padding(.top, 7)

                recordChart
                    .padding(.horizontal, 14)
                    .padding(.top, 6)

                divider.padding(.top, 9)

                streakTitleBlock
                    .padding(.horizontal, 20)
                    .padding(.top, 9)

                heatmapGrid
                    .padding(.horizontal, 14)
                    .padding(.top, 6)

                Spacer(minLength: 6)

                footerRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
        }
    }

    // MARK: Wordmark
    private var wordmarkRow: some View {
        MIMOWordmark(size: 9, strokeMIMO: theme == .light)
    }

    private var divider: some View {
        Rectangle()
            .fill(p.divider)
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    // MARK: 러닝 흐름 (성장 탭과 동일한 컴포넌트)
    private var flowTitleRow: some View {
        HStack(alignment: .center) {
            Text(AppLanguage.shared.s("러닝 흐름", "Running Flow"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(p.textPrimary)
            Spacer()
            Text(periodLabel)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(p.textPrimary)
        }
    }

    /// §5.8 — 성장 탭 카드와 **같은 컴포넌트**. 크기·상호작용만 내보내기 모드로.
    private var recordChart: some View {
        RecordBarChart(
            bars: bars,
            period: period,
            start: windowStart,
            end: windowEnd,
            exportMode: true,
            cardBackground: p.boxFill
        )
    }

    // MARK: Streak section
    private var streakTitleBlock: some View {
        let L = AppLanguage.shared
        let detail: String
        if streak >= 2 {
            detail = L.s("\(streak)주 연속 · \(heatmapWeekCount)주간 \(activeDays)일",
                         "\(streak)wk · \(activeDays)d / \(heatmapWeekCount)wk")
        } else if activeDays > 0 {
            detail = L.s("\(heatmapWeekCount)주간 \(activeDays)일 러닝",
                         "\(activeDays) days / \(heatmapWeekCount) wks")
        } else {
            detail = L.s("\(heatmapWeekCount)주간 기록 없음", "No runs in \(heatmapWeekCount) wks")
        }
        return HStack(alignment: .center) {
            Text(L.s("연속 달리기", "Streak"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(p.textPrimary)
            Spacer()
            Text(detail)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(p.textPrimary)
        }
    }

    private var heatmapGrid: some View {
        let cs  = Self.cellSize
        let gap = Self.cellGap
        let lw  = Self.labelW
        return VStack(alignment: .leading, spacing: gap) {
            // Week-start date header
            HStack(spacing: gap) {
                Color.clear.frame(width: lw, height: 8)
                ForEach(Array(heatmapColumns.enumerated()), id: \.offset) { idx, col in
                    if idx == 0 || heatmapMonthChanges(at: idx) {
                        Text(heatmapShortDate(col.id))
                            .font(.system(size: 6, weight: .medium))
                            .foregroundStyle(p.textSecondary)
                            .frame(width: cs, alignment: .leading)
                            .fixedSize()
                    } else {
                        Color.clear.frame(width: cs, height: 8)
                    }
                }
            }
            // Day rows
            ForEach(0..<7, id: \.self) { dayIdx in
                HStack(spacing: gap) {
                    Text(heatmapDayLabels[dayIdx])
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(p.textSecondary)
                        .frame(width: lw, height: cs, alignment: .trailing)
                    ForEach(heatmapColumns) { col in
                        let cell = col.days[dayIdx]
                        RoundedRectangle(cornerRadius: 2)
                            .fill(cellColor(km: cell.km, isFuture: cell.isFuture))
                            .frame(width: cs, height: cs)
                    }
                }
            }
            // Legend
            HStack(spacing: 4) {
                Spacer()
                Text(AppLanguage.shared.s("적음", "Less"))
                    .font(.system(size: 6))
                    .foregroundStyle(p.textSecondary)
                ForEach([0.0, 2.0, 5.0, 8.0, 12.0], id: \.self) { km in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cellColor(km: km, isFuture: false))
                        .frame(width: cs, height: cs)
                }
                Text(AppLanguage.shared.s("많음", "More"))
                    .font(.system(size: 6))
                    .foregroundStyle(p.textSecondary)
            }
        }
        .padding(7)
        .background(p.boxFill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var heatmapDayLabels: [String] {
        AppLanguage.shared.isEnglish
            ? ["M", "", "W", "", "F", "Sa", "Su"]
            : ["월", "", "수", "", "금", "토", "일"]
    }

    private func heatmapMonthChanges(at idx: Int) -> Bool {
        guard idx > 0 else { return false }
        let cal = Calendar.current
        return cal.component(.month, from: heatmapColumns[idx - 1].id)
            != cal.component(.month, from: heatmapColumns[idx].id)
    }

    private static let heatmapDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    private func heatmapShortDate(_ date: Date) -> String {
        Self.heatmapDateFmt.string(from: date)
    }

    private func cellColor(km: Double, isFuture: Bool) -> Color {
        if isFuture { return theme == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.04) }
        if km == 0  { return p.heatEmpty }
        if km < 3   { return p.heatLow }
        if km < 6   { return p.heatMid }
        if km < 10  { return p.heatHigh }
        return p.heatFull
    }

    // MARK: Footer
    private var footerRow: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(p.positive.opacity(0.15))
                    .frame(width: 20, height: 20)
                Image(systemName: "figure.run")
                    .font(.system(size: 8, weight: .light))
                    .foregroundStyle(p.positive)
            }
        }
    }
}

// MARK: - Mileage + Streak share screen

struct MileageStreakShareCardScreen: View {
    let bars: [RecordBar]
    let period: RecordPeriod
    let windowStart: Date
    let windowEnd: Date
    let periodLabel: String
    let heatmapColumns: [ShareHeatmapColumn]
    let streak: Int
    let activeDays: Int
    let heatmapWeekCount: Int
    var screenTitle: String = AppLanguage.shared.s("러닝 흐름", "Running Flow")

    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @State private var showShareSheet = false
    @State private var cardTheme: ShareTheme = .dark
    @Environment(\.dismiss) private var dismiss

    private let cardW: CGFloat = 300
    /// 러닝 흐름 차트(내보내기 모드 ≈235) + 잔디(≈118) + 머리·구분선·푸터가 잘리지 않는 높이
    private let cardH: CGFloat = 500

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer()
                    MileageStreakShareCard(
                        bars: bars,
                        period: period,
                        windowStart: windowStart,
                        windowEnd: windowEnd,
                        periodLabel: periodLabel,
                        heatmapColumns: heatmapColumns,
                        streak: streak,
                        activeDays: activeDays,
                        heatmapWeekCount: heatmapWeekCount,
                        theme: cardTheme
                    )
                    .environment(\.colorScheme, cardTheme == .dark ? .dark : .light)
                    .frame(width: cardW, height: cardH)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Theme.violet.opacity(0.30), radius: 28, y: 10)

                    Spacer(minLength: 20)

                    themeToggle
                        .padding(.horizontal, 24)

                    Spacer(minLength: 12)

                    shareCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Theme.violet)
                }
            }
        }
        .task { await renderCard() }
        .onChange(of: cardTheme) { Task { await renderCard() } }
    }

    // MARK: - Theme toggle

    private var themeToggle: some View {
        HStack(spacing: 0) {
            themeSegment(label: AppLanguage.shared.s("다크", "Dark"),
                         selected: cardTheme == .dark) { cardTheme = .dark }
            themeSegment(label: AppLanguage.shared.s("라이트", "Light"),
                         selected: cardTheme == .light) { cardTheme = .light }
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
    private var shareCTA: some View {
        if isRendering {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.violet)
                Text(AppLanguage.shared.s("카드 만드는 중...", "Creating card..."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        } else if previewImage != nil {
            Button { showShareSheet = true } label: {
                Label(AppLanguage.shared.s("흐름 내보내기", "Export Flow"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .sheet(isPresented: $showShareSheet) {
                if let img = previewImage { ShareSheet(images: [img]) }
            }
        } else {
            Text(AppLanguage.shared.s("카드 생성에 실패했어요", "Card creation failed"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
    }

    @MainActor
    private func renderCard() async {
        isRendering = true
        let renderer = ImageRenderer(content:
            MileageStreakShareCard(
                bars: bars,
                period: period,
                windowStart: windowStart,
                windowEnd: windowEnd,
                periodLabel: periodLabel,
                heatmapColumns: heatmapColumns,
                streak: streak,
                activeDays: activeDays,
                heatmapWeekCount: heatmapWeekCount,
                theme: cardTheme
            )
            .environment(\.colorScheme, cardTheme == .dark ? .dark : .light)
            .frame(width: cardW, height: cardH)
        )
        renderer.scale = 3
        previewImage = renderer.uiImage
        isRendering = false
    }
}
