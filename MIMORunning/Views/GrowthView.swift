import SwiftUI
import Charts

// MARK: - File-private data models

private struct WeeklyKm: Identifiable {
    let id: Date
    let label: String
    let km: Double
}

private struct WeeklyMins: Identifiable {
    let id: Date
    let label: String
    let mins: Double
}

private struct MonthlyKm: Identifiable {
    let id: Date
    let label: String
    let km: Double
}

private struct MonthlyMins: Identifiable {
    let id: Date
    let label: String
    let mins: Double
}

private struct PacePoint: Identifiable {
    let id = UUID()
    let date: Date
    let speedKmh: Double   // higher = faster; Y axis naturally shows faster = higher
    let paceFormatted: String
}

private struct DayCell: Identifiable {
    let id: Date           // start of day
    let km: Double
    let isFuture: Bool
}

private struct WeekColumn: Identifiable {
    let id: Date           // Monday of this week
    let days: [DayCell]    // 7 elements: Mon[0] … Sun[6]
}

private struct PREntry: Identifiable {
    let id: String         // "5K", "10K", "half", "full"
    let label: String      // display label
    let activity: Activity
    var isNew: Bool { Date().timeIntervalSince(activity.date) < 30 * 86400 }
}

private struct MilestoneEvent: Identifiable {
    enum Kind { case first, distance, cumulative, longest }
    let id: String
    let date: Date
    let kind: Kind
    let title: String
    let detail: String
}

// MARK: - GrowthView

struct GrowthView: View {
    var manager: HealthKitManager

    @State private var showTimeMileage: Bool = false
    @State private var showMonthly: Bool = false
    @State private var selectedTrend: TrendMetric? = nil
    @State private var showBodyMass = false
    @State private var showBodyFat = false
    @AppStorage("distanceUnitMiles") private var useMiles = false

    // Cached chart data — refreshed only when activities change
    @State private var weeklyKmsCache: [WeeklyKm] = []
    @State private var weeklyMinsCache: [WeeklyMins] = []
    @State private var monthlyKmsCache: [MonthlyKm] = []
    @State private var monthlyMinsCache: [MonthlyMins] = []
    @State private var pacePointsCache: [PacePoint] = []
    @State private var heatmapColumnsCache: [WeekColumn] = []
    @State private var weekStreakCache: Int = 0
    @State private var metricAnalyses: [TrendMetric: (direction: TrendDirection, changeRatio: Double)] = [:]
    @State private var paceAnalysisCache: (direction: TrendDirection, changeRatio: Double) = (.insufficient, 0)
    @State private var hrAnalysisCache: (direction: TrendDirection, changeRatio: Double) = (.insufficient, 0)
    @State private var thisWeekLongestKmCache: Double = 0
    @State private var weeklyPatternCache: [WeeklyPattern] = []
    @State private var weeklyCommentText: String = ""
    @State private var weeklyCommentCache: [String: String] = [:]
    @State private var runsCache: [Activity] = []
    @State private var prEntriesCache: [PREntry] = []
    @State private var journeyMilestonesCache: [MilestoneEvent] = []
    @State private var thisWeekRunCountCache: Int = 0
    @State private var growthInsightBannerText: String? = nil
    @State private var showWeeklyShareCard = false

    private static let weekLabelFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
    private static let monthLabelFormatterKo: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M월"; return f
    }()
    private static let monthLabelFormatterEn: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM"; return f
    }()
    private static var monthLabelFormatter: DateFormatter {
        AppLanguage.shared.isEnglish ? monthLabelFormatterEn : monthLabelFormatterKo
    }

    private var runs: [Activity] { runsCache }

    private func refreshChartCache() {
        runsCache        = manager.activities.filter { $0.type == .running }
        weeklyKmsCache   = weeklyKms()
        weeklyMinsCache  = weeklyMins()
        monthlyKmsCache  = monthlyKms()
        monthlyMinsCache = monthlyMins()
        pacePointsCache  = pacePoints()
        let cols = heatmapColumns()
        heatmapColumnsCache = cols
        weekStreakCache  = weekStreak()

        // Pace trend from recent runs (sec/km values — down = faster = good)
        let paceSamples = runs.prefix(14).compactMap { $0.paceSecPerKm }.map { Double($0) }
        paceAnalysisCache = trendDirection(values: Array(paceSamples.reversed()))

        // HR trend from recent runs
        let hrSamples = runs.prefix(14).compactMap { $0.avgHeartRate }.map { Double($0) }
        hrAnalysisCache = trendDirection(values: Array(hrSamples.reversed()))

        // Longest run this week
        let cal = Calendar.current
        let nowComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        thisWeekLongestKmCache = runs
            .filter { cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.date) == nowComps }
            .map { $0.distance / 1000 }
            .max() ?? 0

        let ws = cal.date(from: nowComps) ?? Date()
        thisWeekRunCountCache   = runsCache.filter { $0.date >= ws }.count
        prEntriesCache          = prEntries()
        journeyMilestonesCache  = journeyMilestones()
        growthInsightBannerText = computeGrowthInsightText()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if manager.isLoading && manager.activities.isEmpty {
                    ProgressView().tint(Theme.violet)
                } else if runs.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            growthInsightBanner
                            weeklySection
                            paceSection
                            heatmapSection
                            weekSummarySection
                            metricTrendsSection
                            prSection
                            journeySection
                            Spacer(minLength: 32)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle(AppLanguage.shared.s("성장", "Growth"))
            .navigationBarTitleDisplayMode(.large)
        }
        .onChange(of: manager.activities) { Task { refreshChartCache(); await refreshMetricAnalyses() } }
        .task {
            refreshChartCache()
            let bucket = manager.userLevel.bucket
            showTimeMileage = (bucket == .beginner || bucket == .novice)
            await checkBodyDataAvailability()
            await refreshMetricAnalyses()
        }
        .sheet(item: $selectedTrend) { metric in
            MetricTrendView(
                metric: metric,
                currentValue: nil,
                manager: manager,
                age: userAge,
                isMale: manager.userIsMale
            )
        }
        .sheet(isPresented: $showWeeklyShareCard) {
            let style = weeklyPatternCache.first.map { weeklyPatternStyle(for: $0.key) }
            WeeklyGrowthShareCardScreen(
                km: weeklyKmsCache.last?.km ?? 0,
                mins: weeklyMinsCache.last?.mins ?? 0,
                count: thisWeekRunCount,
                streak: weekStreakCache,
                insightText: weeklyCommentText.isEmpty ? nil : weeklyCommentText,
                insightSymbol: style?.symbol,
                insightColor: style?.color,
                manager: manager
            )
        }
    }

    // MARK: - Helpers

    private var userAge: Int? {
        guard let comps = manager.userDateOfBirth,
              let year = comps.year else { return nil }
        return Calendar.current.component(.year, from: Date()) - year
    }

    // MARK: - Sections

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                SectionLabel(title: mileageTitle, subtitle: mileageSubtitle)
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    periodToggle
                    modeToggle
                }
            }
            mileageChartView
        }
    }

    private var mileageTitle: String {
        let L = AppLanguage.shared
        let period = showMonthly ? L.s("월간", "Monthly") : L.s("주간", "Weekly")
        let mode   = showTimeMileage ? L.s("시간", "Time") : L.s("거리", "Distance")
        return "\(period) \(mode)"
    }

    private var mileageSubtitle: String {
        let L = AppLanguage.shared
        if showMonthly {
            if showTimeMileage {
                return timeSummary(mins: monthlyMinsCache.last?.mins ?? 0, isMonth: true)
            } else {
                let km = monthlyKmsCache.last?.km ?? 0
                return km > 0
                    ? String(format: L.s("이번 달 %.1fkm", "This month %.1fkm"), km)
                    : L.s("이번 달 아직 없어요", "Nothing this month")
            }
        } else {
            if showTimeMileage {
                return timeSummary(mins: weeklyMinsCache.last?.mins ?? 0, isMonth: false)
            } else {
                return L.s("최근 8주 러닝 km", "Last 8 weeks (km)")
            }
        }
    }

    private var periodToggle: some View {
        let L = AppLanguage.shared
        return HStack(spacing: 0) {
            Button { showMonthly = false } label: {
                Text(L.s("주", "W"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(!showMonthly ? Color.white : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(!showMonthly ? Theme.violet : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Button { showMonthly = true } label: {
                Text(L.s("월", "M"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(showMonthly ? Color.white : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(showMonthly ? Theme.violet : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private var modeToggle: some View {
        let L = AppLanguage.shared
        return HStack(spacing: 0) {
            Button { showTimeMileage = false } label: {
                Text("km")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(showTimeMileage ? Color.secondary : Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(showTimeMileage ? Color.clear : Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Button { showTimeMileage = true } label: {
                Text(L.s("분", "min"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(showTimeMileage ? Color.white : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(showTimeMileage ? Theme.violet : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var mileageChartView: some View {
        let L = AppLanguage.shared
        if showMonthly {
            if showTimeMileage {
                if monthlyMinsCache.allSatisfy({ $0.mins == 0 }) {
                    EmptyChartPlaceholder(message: L.s("최근 12개월간 러닝 기록이 없어요", "No runs in the last 12 months"))
                } else {
                    MonthlyTimeChart(data: monthlyMinsCache)
                }
            } else {
                if monthlyKmsCache.allSatisfy({ $0.km == 0 }) {
                    EmptyChartPlaceholder(message: L.s("최근 12개월간 러닝 기록이 없어요", "No runs in the last 12 months"))
                } else {
                    MonthlyDistanceChart(data: monthlyKmsCache)
                }
            }
        } else {
            if showTimeMileage {
                if weeklyMinsCache.allSatisfy({ $0.mins == 0 }) {
                    EmptyChartPlaceholder(message: L.s("이번 8주간 러닝 기록이 없어요", "No runs in the last 8 weeks"))
                } else {
                    WeeklyTimeChart(data: weeklyMinsCache)
                }
            } else {
                if weeklyKmsCache.allSatisfy({ $0.km == 0 }) {
                    EmptyChartPlaceholder(message: L.s("이번 8주간 러닝 기록이 없어요", "No runs in the last 8 weeks"))
                } else {
                    WeeklyDistanceChart(data: weeklyKmsCache)
                }
            }
        }
    }

    private func timeSummary(mins: Double, isMonth: Bool = false) -> String {
        let L = AppLanguage.shared
        let total = Int(mins)
        let prefix = isMonth ? L.s("이번 달 ", "This month: ") : L.s("이번 주 ", "This week: ")
        guard total > 0 else { return "\(prefix)\(L.s("아직 없어요", "Nothing yet"))" }
        let h = total / 60
        let m = total % 60
        if L.isEnglish {
            return h > 0 ? "\(prefix)\(h)h \(m)m" : "\(prefix)\(m)m"
        } else {
            return h > 0 ? "\(prefix)\(h)시간 \(m)분" : "\(prefix)\(m)분"
        }
    }

    private var paceSection: some View {
        let L = AppLanguage.shared
        let points = pacePointsCache
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: L.s("페이스 추이", "Pace Trend"), subtitle: L.s("위로 갈수록 빠름", "Higher = faster"))
            if points.count < 2 {
                EmptyChartPlaceholder(message: L.s("비교하려면 러닝 2회 이상이 필요해요", "Need 2+ runs to compare"))
            } else {
                PaceTrendChart(points: points)
            }
        }
    }

    private var heatmapSection: some View {
        let columns = heatmapColumnsCache
        let streak = weekStreakCache
        let activeDays = activeDaysInHeatmap(columns: columns)
        let summary = heatmapSummary(streak: streak, activeDays: activeDays)
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: AppLanguage.shared.s("연속 달리기", "Streak"), subtitle: summary)
            RunHeatmap(columns: columns)
        }
    }

    private var thisWeekRunCount: Int { thisWeekRunCountCache }

    private func weekTimeFormatted(_ total: Int) -> String {
        guard total > 0 else { return "--" }
        let h = total / 60
        let m = total % 60
        let L = AppLanguage.shared
        if L.isEnglish { return h > 0 ? "\(h)h \(m)m" : "\(m)m" }
        return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
    }

    private var weekSummarySection: some View {
        let L = AppLanguage.shared
        let km   = weeklyKmsCache.last?.km ?? 0
        let mins = weeklyMinsCache.last?.mins ?? 0
        let count  = thisWeekRunCount
        let streak = weekStreakCache

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.s("이번 주", "This Week"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Text(L.s("월요일부터 지금까지", "Monday through today"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "8A8A92"))
                }
                if km > 0 || mins > 0 || count > 0 {
                    Spacer()
                    Button { showWeeklyShareCard = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundStyle(Theme.violet)
                    .padding(.top, 4)
                }
            }

            if km == 0 && mins == 0 && count == 0 {
                Text(L.s("이번 주 첫 러닝을 기다리고 있어요", "Waiting for your first run this week"))
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "8A8A92"))
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 8) {
                    WeekStatTile(
                        value: String(format: km >= 10 ? "%.1f km" : "%.2f km", km),
                        label: L.s("거리", "Distance")
                    )
                    WeekStatTile(
                        value: weekTimeFormatted(Int(mins)),
                        label: L.s("시간", "Time")
                    )
                    WeekStatTile(
                        value: L.s("\(count)회", "\(count)"),
                        label: L.s("횟수", "Runs")
                    )
                    if streak > 0 {
                        WeekStatTile(
                            value: L.s("\(streak)주", "\(streak)wk"),
                            label: L.s("연속", "Streak")
                        )
                    }
                }
            }
        }
    }

    private var metricTrendsSection: some View {
        let L = AppLanguage.shared
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let runningMetrics: [TrendMetric] = [
            .cadence, .power, .groundContactTime, .strideLength, .verticalOscillation, .vo2Max
        ]
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: L.s("주간 지표 추세", "Weekly Metric Trends"), subtitle: L.s("탭하면 상세 보기", "Tap for details"))
            weeklyPatternCommentCard
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(runningMetrics) { metric in
                    MetricSparkCard(metric: metric, manager: manager, usePounds: useMiles) {
                        selectedTrend = metric
                    }
                }
                if showBodyMass {
                    MetricSparkCard(metric: .bodyMass, manager: manager, usePounds: useMiles) {
                        selectedTrend = .bodyMass
                    }
                }
                if showBodyFat {
                    MetricSparkCard(metric: .bodyFatPercentage, manager: manager, usePounds: useMiles) {
                        selectedTrend = .bodyFatPercentage
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var weeklyPatternCommentCard: some View {
        if let pattern = weeklyPatternCache.first, !weeklyCommentText.isEmpty {
            let style = weeklyPatternStyle(for: pattern.key)
            HStack(spacing: 10) {
                Image(systemName: style.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(style.color)
                Text(weeklyCommentText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func weeklyPatternStyle(for key: String) -> (symbol: String, color: Color) {
        switch key {
        case "economy":    return ("bolt.fill",             Color(hex: "F5C542"))
        case "speed":      return ("hare.fill",             Color(hex: "5AC8FA"))
        case "form":       return ("figure.run",            Theme.violet)
        case "cardio":     return ("heart.fill",            Color(hex: "30D158"))
        case "easy":       return ("leaf.fill",             Color(hex: "34C759"))
        case "streak":     return ("flame.fill",            Color(hex: "FF9F0A"))
        case "consistent": return ("checkmark.circle.fill", Theme.violet)
        default:           return ("figure.walk",           Color(hex: "8A8A92"))
        }
    }

    private var prSection: some View {
        let L = AppLanguage.shared
        let entries = prEntriesCache
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: L.s("PR 타임라인", "PR Timeline"), subtitle: L.s("거리별 최고 기록", "Best by distance"))
            if entries.isEmpty {
                EmptyChartPlaceholder(message: L.s("표준 거리 완주 기록이 생기면 PR이 여기에 표시돼요", "Complete a standard distance to see your PR"))
            } else {
                PRGrid(entries: entries)
            }
        }
    }

    private var journeySection: some View {
        let L = AppLanguage.shared
        let events = journeyMilestonesCache
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: L.s("나의 여정", "My Journey"), subtitle: L.s("걷기에서 러닝으로", "From walking to running"))
            if events.isEmpty {
                EmptyChartPlaceholder(message: L.s("기록이 쌓이면 여정이 여기에 펼쳐져요", "Your journey will appear as you log more"))
            } else {
                JourneyTimeline(events: events)
            }
        }
    }

    // MARK: - Growth insight banner

    @ViewBuilder
    private var growthInsightBanner: some View {
        if let text = growthInsightText {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.violet)
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.violet.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.violet.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var growthInsightText: String? { growthInsightBannerText }

    private func computeGrowthInsightText() -> String? {
        let L = AppLanguage.shared
        let streak = weekStreakCache
        if streak >= 3 {
            return L.s("\(streak)주 연속 달리고 있어요 — 루틴이 자리 잡고 있어요",
                       "\(streak) weeks in a row — you're building a routine")
        }
        if streak == 2 {
            return L.s("2주 연속 달리고 있어요 — 이번 주도 이어가 봐요",
                       "2 weeks running — keep it up this week")
        }

        let thisKm = weeklyKmsCache.last?.km ?? 0
        let prevKm = weeklyKmsCache.dropLast().last?.km ?? 0
        if thisKm > prevKm, prevKm > 0 {
            let diff = thisKm - prevKm
            return String(format: L.s("이번 주 거리가 지난 주보다 +%.1fkm 늘었어요", "+%.1fkm more than last week"), diff)
        }

        if let recent = prEntriesCache.first(where: { $0.isNew }) {
            return L.s("\(recent.label) 신기록을 세웠어요", "New \(recent.label) PR")
        }

        let pts = pacePointsCache
        if pts.count >= 6 {
            let latestAvg = pts.suffix(3).map(\.speedKmh).reduce(0, +) / 3
            let earlierAvg = pts.prefix(3).map(\.speedKmh).reduce(0, +) / 3
            if earlierAvg > 0, latestAvg > earlierAvg * 1.02 {
                return L.s("최근 페이스가 꾸준히 빨라지고 있어요", "Your pace has been steadily improving")
            }
        }

        return nil
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(AppLanguage.shared.s("러닝을 시작하면\n성장 차트가 여기에 나타나요",
                                     "Start running and your\ngrowth chart will appear here"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Body data availability

    private func checkBodyDataAvailability() async {
        let since = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        async let bmTask = manager.fetchMetricHistory(.bodyMass, from: since)
        async let bfTask = manager.fetchMetricHistory(.bodyFatPercentage, from: since)
        let (bm, bf) = await (bmTask, bfTask)
        withAnimation(.easeInOut(duration: 0.3)) {
            showBodyMass = !bm.isEmpty
            showBodyFat  = !bf.isEmpty
        }
    }

    // MARK: - Metric trend analyses

    private func refreshMetricAnalyses() async {
        let since = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        let runningMetrics: [TrendMetric] = [
            .cadence, .power, .groundContactTime, .strideLength, .verticalOscillation, .vo2Max
        ]

        // Fetch all metric histories concurrently
        var fetched: [(TrendMetric, [Double])] = []
        await withTaskGroup(of: (TrendMetric, [Double]).self) { group in
            for metric in runningMetrics {
                group.addTask {
                    let pts = await self.manager.fetchMetricHistory(metric, from: since)
                    return (metric, pts.map(\.value))
                }
            }
            for await item in group {
                fetched.append(item)
            }
        }

        // Compute trend directions back on the main actor
        var results: [TrendMetric: (direction: TrendDirection, changeRatio: Double)] = [:]
        for (metric, values) in fetched {
            results[metric] = trendDirection(values: values)
        }
        metricAnalyses = results

        // Build WeeklyInsightInputs and detect patterns
        let cal = Calendar.current
        let nowComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let thisWeekRuns = runs.filter {
            cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.date) == nowComps
        }
        let inputs = WeeklyInsightInputs(
            paceDirection:       paceAnalysisCache.direction,
            hrDirection:         hrAnalysisCache.direction,
            cadence:             results[.cadence]?.direction             ?? .insufficient,
            power:               results[.power]?.direction               ?? .insufficient,
            strideLength:        results[.strideLength]?.direction         ?? .insufficient,
            groundContactTime:   results[.groundContactTime]?.direction    ?? .insufficient,
            vertOsc:             results[.verticalOscillation]?.direction  ?? .insufficient,
            vo2Max:              results[.vo2Max]?.direction               ?? .insufficient,
            paceChangeRatio:     paceAnalysisCache.changeRatio,
            hrChangeRatio:       hrAnalysisCache.changeRatio,
            metricChangeRatios:  results.mapValues { $0.changeRatio },
            weekStreak:          weekStreakCache,
            runCount:            thisWeekRuns.count,
            thisWeekDistanceKm:  thisWeekLongestKmCache
        )
        weeklyPatternCache = detectWeeklyPatterns(inputs)

        // ① 폴백 템플릿으로 즉시 표시
        let weekOfYear = Calendar.current.component(.weekOfYear, from: Date())
        guard let top = weeklyPatternCache.first else {
            weeklyCommentText = ""
            return
        }
        weeklyCommentText = top.template(for: weekOfYear, isEnglish: AppLanguage.shared.isEnglish)
        // ② 같은 주·같은 패턴이면 캐시 사용
        let cacheKey = "\(weekOfYear)_\(top.key)"
        if let cached = weeklyCommentCache[cacheKey] {
            weeklyCommentText = cached
            return
        }

        // ③ AI 강화 시도 (iOS 26+, 한국어, 사실 있을 때만)
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if let aiText = await InsightAIGenerator.generateWeeklyComment(
                patternKey: top.key, factSummary: top.factSummary
            ) {
                weeklyCommentText = aiText
                weeklyCommentCache[cacheKey] = aiText
            }
        }
        #endif
    }

    // MARK: - Journey milestones

    private func journeyMilestones() -> [MilestoneEvent] {
        let L = AppLanguage.shared
        let all = manager.activities.sorted { $0.date < $1.date }
        let allRuns = all.filter { $0.type == .running }
        var events: [MilestoneEvent] = []

        // 첫 기록 (any type)
        if let first = all.first {
            let typeLabel = first.type.label
            let title = L.isEnglish ? "First \(typeLabel)" : "첫 \(typeLabel)"
            events.append(.init(id: "first_any", date: first.date, kind: .first,
                                title: title, detail: first.formattedDistance))
        }

        // 첫 러닝 (only if different from very first activity)
        if let firstRun = allRuns.first, firstRun.id != all.first?.id {
            events.append(.init(id: "first_run", date: firstRun.date, kind: .first,
                                title: L.s("첫 러닝", "First Run"), detail: firstRun.formattedDistance))
        }

        // 거리별 첫 완주 (5K / 10K / 하프 / 풀)
        let distMilestones: [(Double, String, String)] = [
            (5000,  "first_5k",   L.s("첫 5K 완주",   "First 5K")),
            (10000, "first_10k",  L.s("첫 10K 완주",  "First 10K")),
            (21097, "first_half", L.s("첫 하프 완주",  "First Half")),
            (42195, "first_full", L.s("첫 풀 완주",    "First Full")),
        ]
        var coveredRunIDs = Set<UUID>()
        for (minDist, key, title) in distMilestones {
            if let a = allRuns.first(where: { $0.distance >= minDist }) {
                events.append(.init(id: key, date: a.date, kind: .distance,
                                    title: title, detail: a.formattedDistance))
                coveredRunIDs.insert(a.id)
            }
        }

        // 누적 거리 돌파 (모든 활동 기준: 걷기+러닝+하이킹)
        let thresholds: [Double] = [100, 300, 500, 1000]
        var totalKm = 0.0
        var nextThresh = 0
        for a in all {
            totalKm += a.distance / 1000
            while nextThresh < thresholds.count && totalKm >= thresholds[nextThresh] {
                let km = thresholds[nextThresh]
                events.append(.init(
                    id: "cum_\(Int(km))",
                    date: a.date,
                    kind: .cumulative,
                    title: L.s("누적 \(Int(km))km 돌파", "\(Int(km))km total"),
                    detail: String(format: L.s("총 %.0fkm", "Total %.0fkm"), totalKm)
                ))
                nextThresh += 1
            }
        }

        // 현재 최장 거리 (거리 마일스톤에 없는 경우만)
        if let longest = allRuns.max(by: { $0.distance < $1.distance }),
           longest.distance >= 5000,
           !coveredRunIDs.contains(longest.id) {
            events.append(.init(id: "longest", date: longest.date, kind: .longest,
                                title: L.s("현재 최장 거리", "Longest Run"), detail: longest.formattedDistance))
        }

        return events.sorted { $0.date < $1.date }
    }

    // MARK: - PR data

    private static var prBuckets: [(id: String, label: String, range: ClosedRange<Double>)] {
        let L = AppLanguage.shared
        return [
            ("5K",   "5K",                  4700...5500),
            ("10K",  "10K",                 9500...10500),
            ("half", L.s("하프", "Half"),   20000...22000),
            ("full", L.s("풀",   "Full"),   41000...43000),
        ]
    }

    private func prEntries() -> [PREntry] {
        Self.prBuckets.compactMap { bucket in
            let best = runs
                .filter { bucket.range.contains($0.distance) }
                .min(by: { $0.duration < $1.duration })
            guard let best else { return nil }
            return PREntry(id: bucket.id, label: bucket.label, activity: best)
        }
    }

    // MARK: - Weekly distance data

    private func weeklyKms() -> [WeeklyKm] {
        let cal = Calendar.current
        let now = Date()
        let starts: [Date] = (0..<8).reversed().compactMap { ago -> Date? in
            let ref = cal.date(byAdding: .weekOfYear, value: -ago, to: now)!
            return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ref))
        }
        var totals: [Date: Double] = Dictionary(uniqueKeysWithValues: starts.map { ($0, 0.0) })
        for a in runs {
            let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: a.date))!
            if totals[ws] != nil { totals[ws]! += a.distance / 1000 }
        }
        return starts.map { s in WeeklyKm(id: s, label: Self.weekLabelFormatter.string(from: s), km: totals[s] ?? 0) }
    }

    private func weeklyMins() -> [WeeklyMins] {
        let cal = Calendar.current
        let now = Date()
        let starts: [Date] = (0..<8).reversed().compactMap { ago -> Date? in
            let ref = cal.date(byAdding: .weekOfYear, value: -ago, to: now)!
            return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ref))
        }
        var totals: [Date: Double] = Dictionary(uniqueKeysWithValues: starts.map { ($0, 0.0) })
        for a in runs {
            let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: a.date))!
            if totals[ws] != nil { totals[ws]! += a.duration / 60 }
        }
        return starts.map { s in WeeklyMins(id: s, label: Self.weekLabelFormatter.string(from: s), mins: totals[s] ?? 0) }
    }

    // MARK: - Monthly distance data

    private func monthlyKms(count: Int = 12) -> [MonthlyKm] {
        let cal = Calendar.current
        let now = Date()
        let starts: [Date] = (0..<count).reversed().compactMap { ago in
            let ref = cal.date(byAdding: .month, value: -ago, to: now)!
            return cal.date(from: cal.dateComponents([.year, .month], from: ref))
        }
        var totals: [Date: Double] = Dictionary(uniqueKeysWithValues: starts.map { ($0, 0.0) })
        for a in runs {
            let ms = cal.date(from: cal.dateComponents([.year, .month], from: a.date))!
            if totals[ms] != nil { totals[ms]! += a.distance / 1000 }
        }
        return starts.map { s in MonthlyKm(id: s, label: Self.monthLabelFormatter.string(from: s), km: totals[s] ?? 0) }
    }

    private func monthlyMins(count: Int = 12) -> [MonthlyMins] {
        let cal = Calendar.current
        let now = Date()
        let starts: [Date] = (0..<count).reversed().compactMap { ago in
            let ref = cal.date(byAdding: .month, value: -ago, to: now)!
            return cal.date(from: cal.dateComponents([.year, .month], from: ref))
        }
        var totals: [Date: Double] = Dictionary(uniqueKeysWithValues: starts.map { ($0, 0.0) })
        for a in runs {
            let ms = cal.date(from: cal.dateComponents([.year, .month], from: a.date))!
            if totals[ms] != nil { totals[ms]! += a.duration / 60 }
        }
        return starts.map { s in MonthlyMins(id: s, label: Self.monthLabelFormatter.string(from: s), mins: totals[s] ?? 0) }
    }

    // MARK: - Pace data

    private func pacePoints(maxCount: Int = 20) -> [PacePoint] {
        runs
            .prefix(maxCount)
            .reversed()
            .compactMap { a -> PacePoint? in
                guard let sec = a.paceSecPerKm, sec > 0 else { return nil }
                return PacePoint(
                    date: a.date,
                    speedKmh: 3600.0 / sec,
                    paceFormatted: a.formattedPace ?? ""
                )
            }
    }

    // MARK: - Heatmap data

    private static let heatmapWeeks = 18

    private func heatmapColumns() -> [WeekColumn] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Monday of the current week (weekday: 1=Sun…7=Sat → Mon=0 offset)
        let todayWeekday = cal.component(.weekday, from: today)
        let daysFromMon = (todayWeekday + 5) % 7  // Mon=0, Sun=6
        let thisMonday = cal.date(byAdding: .day, value: -daysFromMon, to: today)!

        // First Monday of the heatmap
        let firstMonday = cal.date(byAdding: .weekOfYear,
                                   value: -(Self.heatmapWeeks - 1),
                                   to: thisMonday)!

        // Build km-per-day lookup
        var kmByDay: [Date: Double] = [:]
        for a in runs {
            let day = cal.startOfDay(for: a.date)
            kmByDay[day, default: 0] += a.distance / 1000
        }

        return (0..<Self.heatmapWeeks).map { w in
            let monday = cal.date(byAdding: .day, value: w * 7, to: firstMonday)!
            let days = (0..<7).map { d -> DayCell in
                let date = cal.date(byAdding: .day, value: d, to: monday)!
                return DayCell(id: date, km: kmByDay[date] ?? 0, isFuture: date > today)
            }
            return WeekColumn(id: monday, days: days)
        }
    }

    private func weekStreak() -> Int {
        let cal = Calendar.current
        let now = Date()
        var streak = 0
        var offset = 0
        while true {
            let ref = cal.date(byAdding: .weekOfYear, value: -offset, to: now)!
            let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ref))!
            let we = cal.date(byAdding: .weekOfYear, value: 1, to: ws)!
            if runs.contains(where: { $0.date >= ws && $0.date < we }) {
                streak += 1; offset += 1
            } else {
                break
            }
        }
        return streak
    }

    private func activeDaysInHeatmap(columns: [WeekColumn]) -> Int {
        columns.flatMap(\.days).filter { !$0.isFuture && $0.km > 0 }.count
    }

    private func heatmapSummary(streak: Int, activeDays: Int) -> String {
        let L = AppLanguage.shared
        if streak >= 2 {
            return L.s("\(streak)주 연속 · \(Self.heatmapWeeks)주간 \(activeDays)일 러닝",
                       "\(streak) weeks · \(activeDays) days in \(Self.heatmapWeeks) wks")
        } else if activeDays > 0 {
            return L.s("최근 \(Self.heatmapWeeks)주간 \(activeDays)일 러닝",
                       "\(activeDays) days in the last \(Self.heatmapWeeks) wks")
        } else {
            return L.s("최근 \(Self.heatmapWeeks)주간 기록 없음",
                       "No runs in the last \(Self.heatmapWeeks) wks")
        }
    }
}

// MARK: - Heatmap View

private struct RunHeatmap: View {
    let columns: [WeekColumn]

    private let cellSize: CGFloat = 12
    private let gap: CGFloat = 3
    private let labelW: CGFloat = 16

    // Mon, -, Wed, -, Fri, Sat, Sun  (blank on Tue/Thu to reduce clutter)
    private var dayLabels: [String] {
        AppLanguage.shared.isEnglish
            ? ["M", "", "W", "", "F", "Sa", "Su"]
            : ["월", "", "수", "", "금", "토", "일"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Grid: header + 7 rows
            VStack(alignment: .leading, spacing: gap) {
                weekHeaderRow
                ForEach(0..<7, id: \.self) { dayIdx in
                    dayRow(dayIdx: dayIdx)
                }
            }

            // Legend
            legend
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // Top row: sparse week-start labels
    private var weekHeaderRow: some View {
        HStack(spacing: gap) {
            Color.clear.frame(width: labelW, height: 10)
            ForEach(0..<columns.count, id: \.self) { w in
                if w == 0 || monthChanges(at: w) {
                    Text(shortDate(columns[w].id))
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: cellSize, alignment: .leading)
                        .fixedSize()
                        .allowsTightening(true)
                } else {
                    Color.clear.frame(width: cellSize, height: 10)
                }
            }
        }
    }

    // One day-of-week row across all week columns
    private func dayRow(dayIdx: Int) -> some View {
        HStack(spacing: gap) {
            Text(dayLabels[dayIdx])
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: labelW, height: cellSize, alignment: .trailing)

            ForEach(columns) { col in
                let cell = col.days[dayIdx]
                RoundedRectangle(cornerRadius: 2)
                    .fill(cellColor(km: cell.km, isFuture: cell.isFuture))
                    .frame(width: cellSize, height: cellSize)
            }
        }
    }

    // Color intensity scale (5 levels)
    private func cellColor(km: Double, isFuture: Bool) -> Color {
        if isFuture    { return Color.white.opacity(0.04) }
        if km == 0     { return Theme.violet.opacity(0.10) }
        if km < 3      { return Theme.violet.opacity(0.32) }
        if km < 6      { return Theme.violet.opacity(0.56) }
        if km < 10     { return Theme.violet.opacity(0.80) }
        return Theme.violet
    }

    // Color scale legend
    private var legend: some View {
        let L = AppLanguage.shared
        return HStack(spacing: 5) {
            Spacer()
            Text(L.s("적음", "Less"))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            ForEach([0.0, 2.0, 5.0, 8.0, 12.0], id: \.self) { km in
                RoundedRectangle(cornerRadius: 2)
                    .fill(cellColor(km: km, isFuture: false))
                    .frame(width: cellSize, height: cellSize)
            }
            Text(L.s("많음", "More"))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
    }

    // Show label when the month changes between two consecutive columns
    private func monthChanges(at w: Int) -> Bool {
        guard w > 0 else { return false }
        let cal = Calendar.current
        let prevMonth = cal.component(.month, from: columns[w - 1].id)
        let currMonth = cal.component(.month, from: columns[w].id)
        return prevMonth != currMonth
    }

    private static let shortDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
    private func shortDate(_ date: Date) -> String {
        Self.shortDateFmt.string(from: date)
    }
}

// MARK: - PR Grid

private struct PRGrid: View {
    let entries: [PREntry]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(entries) { entry in
                PRCard(entry: entry)
            }
        }
    }
}

private struct PRCard: View {
    let entry: PREntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(entry.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if entry.isNew {
                    Text("NEW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Text(entry.activity.formattedDuration)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                if let pace = entry.activity.formattedPace {
                    Text(pace + "/km")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.pace)
                }
                Text(shortDate(entry.activity.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.violet.opacity(0.35), lineWidth: 1)
        )
    }

    private static let shortDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yy.M.d"; return f
    }()
    private func shortDate(_ date: Date) -> String {
        Self.shortDateFmt.string(from: date)
    }
}

// MARK: - Journey Timeline

private struct JourneyTimeline: View {
    let events: [MilestoneEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                HStack(alignment: .top, spacing: 14) {
                    // Vertical node + connector
                    VStack(spacing: 0) {
                        Circle()
                            .fill(nodeColor(for: event.kind))
                            .frame(width: 10, height: 10)
                            .padding(.top, 4)
                        if idx < events.count - 1 {
                            Rectangle()
                                .fill(Theme.violet.opacity(0.25))
                                .frame(width: 1.5)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 10)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(dateString(event.date))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(event.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(event.detail)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(detailColor(for: event.kind))
                    }
                    .padding(.bottom, idx < events.count - 1 ? 20 : 0)

                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func nodeColor(for kind: MilestoneEvent.Kind) -> Color {
        switch kind {
        case .first:      return Theme.violet
        case .distance:   return Theme.violet
        case .cumulative: return Theme.pace
        case .longest:    return Theme.violet.opacity(0.65)
        }
    }

    private func detailColor(for kind: MilestoneEvent.Kind) -> Color {
        switch kind {
        case .cumulative: return Theme.pace
        default:          return Theme.violet
        }
    }

    private static let dateStringFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yy.M.d"; return f
    }()
    private func dateString(_ date: Date) -> String {
        Self.dateStringFmt.string(from: date)
    }
}

// MARK: - Weekly Distance Chart

private struct WeeklyDistanceChart: View {
    let data: [WeeklyKm]

    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("주", item.label),
                y: .value("거리(km)", item.km)
            )
            .foregroundStyle(item.km > 0 ? Theme.violet.gradient : Color.secondary.opacity(0.3).gradient)
            .cornerRadius(4)
        }
        .frame(height: 180)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    Text(value.as(String.self) ?? "")
                        .font(.caption2)
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    Text(String(format: "%.0f", value.as(Double.self) ?? 0))
                        .font(.caption2)
                }
                AxisGridLine()
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Weekly Time Chart

private struct WeeklyTimeChart: View {
    let data: [WeeklyMins]

    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("주", item.label),
                y: .value("시간(분)", item.mins)
            )
            .foregroundStyle(item.mins > 0 ? Theme.time.gradient : Color.secondary.opacity(0.3).gradient)
            .cornerRadius(4)
        }
        .frame(height: 180)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    Text(value.as(String.self) ?? "")
                        .font(.caption2)
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                if let mins = value.as(Double.self) {
                    AxisValueLabel {
                        Text(minsLabel(mins))
                            .font(.caption2)
                    }
                    AxisGridLine()
                }
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func minsLabel(_ mins: Double) -> String {
        let total = Int(mins)
        guard total > 0 else { return "0" }
        let h = total / 60
        let m = total % 60
        if h > 0 { return m > 0 ? "\(h)h\(m)m" : "\(h)h" }
        return "\(m)m"
    }
}

// MARK: - Monthly Distance Chart

private struct MonthlyDistanceChart: View {
    let data: [MonthlyKm]

    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("월", item.label),
                y: .value("거리(km)", item.km)
            )
            .foregroundStyle(item.km > 0 ? Theme.violet.gradient : Color.secondary.opacity(0.3).gradient)
            .cornerRadius(4)
        }
        .frame(height: 180)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    Text(value.as(String.self) ?? "")
                        .font(.system(size: 9))
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    Text(String(format: "%.0f", value.as(Double.self) ?? 0))
                        .font(.caption2)
                }
                AxisGridLine()
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Monthly Time Chart

private struct MonthlyTimeChart: View {
    let data: [MonthlyMins]

    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("월", item.label),
                y: .value("시간(분)", item.mins)
            )
            .foregroundStyle(item.mins > 0 ? Theme.time.gradient : Color.secondary.opacity(0.3).gradient)
            .cornerRadius(4)
        }
        .frame(height: 180)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    Text(value.as(String.self) ?? "")
                        .font(.system(size: 9))
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                if let mins = value.as(Double.self) {
                    AxisValueLabel {
                        Text(minsLabel(mins))
                            .font(.caption2)
                    }
                    AxisGridLine()
                }
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func minsLabel(_ mins: Double) -> String {
        let total = Int(mins)
        guard total > 0 else { return "0" }
        let h = total / 60
        let m = total % 60
        if h > 0 { return m > 0 ? "\(h)h\(m)m" : "\(h)h" }
        return "\(m)m"
    }
}

// MARK: - Pace Trend Chart

private struct PaceTrendChart: View {
    let points: [PacePoint]

    var body: some View {
        Chart(points) { pt in
            AreaMark(
                x: .value("날짜", pt.date),
                y: .value("스피드", pt.speedKmh)
            )
            .foregroundStyle(Theme.pace.opacity(0.12).gradient)
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("날짜", pt.date),
                y: .value("스피드", pt.speedKmh)
            )
            .foregroundStyle(Theme.pace)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("날짜", pt.date),
                y: .value("스피드", pt.speedKmh)
            )
            .symbol(HollowCircle())
            .foregroundStyle(Theme.pace)
            .symbolSize(36)
        }
        .frame(height: 180)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: strideCount)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                    }
                }
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                if let speed = value.as(Double.self), speed > 0 {
                    let sec = 3600.0 / speed
                    let m = Int(sec) / 60
                    let s = Int(sec) % 60
                    AxisValueLabel {
                        Text(String(format: "%d'%02d\"", m, s))
                            .font(.caption2)
                    }
                    AxisGridLine()
                }
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var strideCount: Int {
        let span = points.last.map { $0.date.timeIntervalSince(points.first!.date) } ?? 0
        let days = Int(span / 86400)
        return max(1, days / 4)
    }
}

// MARK: - Metric Spark Card

private struct MetricSparkCard: View {
    let metric: TrendMetric
    let manager: HealthKitManager
    let usePounds: Bool
    let onTap: () -> Void

    @State private var dataPoints: [(date: Date, value: Double)] = []
    @State private var isLoading = true

    private var currentValue: Double? { dataPoints.last?.value }

    private var isNeutral: Bool {
        metric == .bodyMass || metric == .bodyFatPercentage
    }

    private var analysis: (direction: TrendDirection, changeRatio: Double) {
        trendDirection(values: dataPoints.map(\.value))
    }

    private var sentiment: TrendSentiment {
        trendSentiment(direction: analysis.direction,
                       lowerIsBetter: metric.lowerIsBetter,
                       isNeutral: isNeutral)
    }

    private var arrowText: String? {
        switch analysis.direction {
        case .up:   return "↑"
        case .down: return "↓"
        default:    return nil
        }
    }

    private var arrowColor: Color {
        switch sentiment {
        case .good:    return .green
        case .bad:     return Color(hex: "8A8A92")
        case .neutral: return Color(hex: "6E6E78")
        }
    }

    private var sparklineColor: Color {
        sentiment == .good ? .green : Theme.violet
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(metric.koreanLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let arrow = arrowText {
                        Text(arrow)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(arrowColor)
                    }
                }
                if isLoading {
                    Color.clear
                        .frame(height: 56)
                        .overlay(ProgressView().scaleEffect(0.7).tint(Theme.violet))
                } else if let cur = currentValue {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(metric.formattedValue(cur, usePounds: usePounds))
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if analysis.direction != .insufficient { // TODO: 점검 후 제거
                            let ratio = analysis.changeRatio
                            let sign: String = ratio >= 0 ? "+" : "−"
                            Text(String(format: "%@%.1f%%", sign, abs(ratio * 100)))
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "6E6E78"))
                                .lineLimit(1)
                        }
                    }
                    sparkline
                } else {
                    Text(AppLanguage.shared.s("데이터 없음", "No Data"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(height: 36)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .task {
            let from = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
            dataPoints = await manager.fetchMetricHistory(metric, from: from, usePounds: usePounds)
            isLoading = false
        }
    }

    @ViewBuilder
    private var sparkline: some View {
        if dataPoints.count >= 2 {
            let values  = dataPoints.map(\.value)
            let minVal  = values.min() ?? 0
            let maxVal  = values.max() ?? 1
            let spread  = maxVal - minVal
            let padding = spread > 0 ? spread * 0.4 : max(maxVal * 0.05, 1.0)

            Chart(dataPoints, id: \.date) { pt in
                LineMark(
                    x: .value("날짜", pt.date),
                    y: .value(metric.unit, pt.value)
                )
                .foregroundStyle(sparklineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("날짜", pt.date),
                    y: .value(metric.unit, pt.value)
                )
                .symbol(HollowCircle())
                .foregroundStyle(sparklineColor)
                .symbolSize(14)
            }
            .chartYScale(domain: (minVal - padding)...(maxVal + padding))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 32)
        } else {
            Color.clear.frame(height: 32)
        }
    }
}

// MARK: - Shared sub-views

private struct SectionLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyChartPlaceholder: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Week Stat Tile

private struct WeekStatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "8A8A92"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("주간 지표 추세 카드") {
    // 판정기 UI 검증용 — good(초록)·neutral(회색)·bad(8A8A92) 색상과 변화율 % 확인
    let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    let cases: [(label: String, value: String, arrow: String?, arrowColor: Color, ratio: String?, lineColor: Color)] = [
        ("케이던스",      "178 spm",      "↑", .green,              "+6.2%",  .green),
        ("파워",         "245 W",        "↓", Color(hex:"8A8A92"), "−3.1%",  Theme.violet),
        ("지면 접촉 시간","248 ms",       "↓", .green,              "−4.8%",  .green),
        ("보폭",         "1.28 m",       nil, Color(hex:"6E6E78"), "+0.8%",  Theme.violet),
        ("수직 진폭",    "8.4 cm",       "↑", Color(hex:"8A8A92"), "+5.5%",  Theme.violet),
        ("유산소 피트니스","42.3 mL/kg·min","↑",.green,             "+7.1%",  .green),
        ("체중",         "72.4 kg",      nil, Color(hex:"6E6E78"), "+1.2%",  Theme.violet),
        ("체지방률",      "19.9%",        nil, Color(hex:"6E6E78"), "−0.3%",  Theme.violet),
    ]
    return ZStack {
        Theme.background.ignoresSafeArea()
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(cases, id: \.label) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(c.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            Spacer()
                            if let a = c.arrow { Text(a).font(.system(size: 10, weight: .bold)).foregroundStyle(c.arrowColor) }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(c.value).font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                            if let r = c.ratio { Text(r).font(.system(size: 11)).foregroundStyle(Color(hex: "6E6E78")) } // TODO: 점검 후 제거
                        }
                        RoundedRectangle(cornerRadius: 2).fill(c.lineColor).frame(height: 2).padding(.top, 4)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(16)
        }
    }
}

#Preview("이번 주 누적 블록") {
    ZStack {
        Theme.background.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("이번 주")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text("월요일부터 지금까지")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "8A8A92"))
            }
            HStack(spacing: 8) {
                WeekStatTile(value: "18.4 km", label: "거리")
                WeekStatTile(value: "2시간 3분", label: "시간")
                WeekStatTile(value: "3회", label: "횟수")
                WeekStatTile(value: "4주", label: "연속")
            }
        }
        .padding(16)
    }
}
