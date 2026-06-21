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

    private var runs: [Activity] {
        manager.activities.filter { $0.type == .running }
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
                            weeklySection
                            paceSection
                            heatmapSection
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
            .navigationTitle("성장")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            let bucket = manager.userLevel.bucket
            showTimeMileage = (bucket == .beginner || bucket == .novice)
            await checkBodyDataAvailability()
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
        let period = showMonthly ? "월간" : "주간"
        let mode   = showTimeMileage ? "시간" : "거리"
        return "\(period) \(mode)"
    }

    private var mileageSubtitle: String {
        if showMonthly {
            if showTimeMileage {
                return timeSummary(mins: monthlyMins().last?.mins ?? 0, isMonth: true)
            } else {
                let km = monthlyKms().last?.km ?? 0
                return km > 0 ? String(format: "이번 달 %.1fkm", km) : "이번 달 아직 없어요"
            }
        } else {
            if showTimeMileage {
                return timeSummary(mins: weeklyMins().last?.mins ?? 0, isMonth: false)
            } else {
                return "최근 8주 러닝 km"
            }
        }
    }

    private var periodToggle: some View {
        HStack(spacing: 0) {
            Button { showMonthly = false } label: {
                Text("주")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(!showMonthly ? Color.white : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(!showMonthly ? Theme.violet : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Button { showMonthly = true } label: {
                Text("월")
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
        HStack(spacing: 0) {
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
                Text("분")
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
        if showMonthly {
            if showTimeMileage {
                let data = monthlyMins()
                if data.allSatisfy({ $0.mins == 0 }) {
                    EmptyChartPlaceholder(message: "최근 12개월간 러닝 기록이 없어요")
                } else {
                    MonthlyTimeChart(data: data)
                }
            } else {
                let data = monthlyKms()
                if data.allSatisfy({ $0.km == 0 }) {
                    EmptyChartPlaceholder(message: "최근 12개월간 러닝 기록이 없어요")
                } else {
                    MonthlyDistanceChart(data: data)
                }
            }
        } else {
            if showTimeMileage {
                let data = weeklyMins()
                if data.allSatisfy({ $0.mins == 0 }) {
                    EmptyChartPlaceholder(message: "이번 8주간 러닝 기록이 없어요")
                } else {
                    WeeklyTimeChart(data: data)
                }
            } else {
                let data = weeklyKms()
                if data.allSatisfy({ $0.km == 0 }) {
                    EmptyChartPlaceholder(message: "이번 8주간 러닝 기록이 없어요")
                } else {
                    WeeklyDistanceChart(data: data)
                }
            }
        }
    }

    private func timeSummary(mins: Double, isMonth: Bool = false) -> String {
        let total = Int(mins)
        let prefix = isMonth ? "이번 달 " : "이번 주 "
        guard total > 0 else { return "\(prefix)아직 없어요" }
        let h = total / 60
        let m = total % 60
        return h > 0 ? "\(prefix)\(h)시간 \(m)분" : "\(prefix)\(m)분"
    }

    private var paceSection: some View {
        let points = pacePoints()
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "페이스 추이", subtitle: "위로 갈수록 빠름")
            if points.count < 2 {
                EmptyChartPlaceholder(message: "비교하려면 러닝 2회 이상이 필요해요")
            } else {
                PaceTrendChart(points: points)
            }
        }
    }

    private var heatmapSection: some View {
        let columns = heatmapColumns()
        let streak = weekStreak()
        let activeDays = activeDaysInHeatmap(columns: columns)
        let summary = heatmapSummary(streak: streak, activeDays: activeDays)
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "연속 달리기", subtitle: summary)
            RunHeatmap(columns: columns)
        }
    }

    private var metricTrendsSection: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let runningMetrics: [TrendMetric] = [
            .cadence, .power, .groundContactTime, .strideLength, .verticalOscillation, .vo2Max
        ]
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "지표 추세", subtitle: "탭하면 상세 보기")
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

    private var prSection: some View {
        let entries = prEntries()
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "PR 타임라인", subtitle: "거리별 최고 기록")
            if entries.isEmpty {
                EmptyChartPlaceholder(message: "표준 거리 완주 기록이 생기면 PR이 여기에 표시돼요")
            } else {
                PRGrid(entries: entries)
            }
        }
    }

    private var journeySection: some View {
        let events = journeyMilestones()
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "나의 여정", subtitle: "걷기에서 러닝으로")
            if events.isEmpty {
                EmptyChartPlaceholder(message: "기록이 쌓이면 여정이 여기에 펼쳐져요")
            } else {
                JourneyTimeline(events: events)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("러닝을 시작하면\n성장 차트가 여기에 나타나요")
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

    // MARK: - Journey milestones

    private func journeyMilestones() -> [MilestoneEvent] {
        let all = manager.activities.sorted { $0.date < $1.date }
        let allRuns = all.filter { $0.type == .running }
        var events: [MilestoneEvent] = []

        // 첫 기록 (any type)
        if let first = all.first {
            events.append(.init(id: "first_any", date: first.date, kind: .first,
                                title: "첫 \(first.type.label)", detail: first.formattedDistance))
        }

        // 첫 러닝 (only if different from very first activity)
        if let firstRun = allRuns.first, firstRun.id != all.first?.id {
            events.append(.init(id: "first_run", date: firstRun.date, kind: .first,
                                title: "첫 러닝", detail: firstRun.formattedDistance))
        }

        // 거리별 첫 완주 (5K / 10K / 하프 / 풀)
        let distMilestones: [(Double, String, String)] = [
            (5000,  "first_5k",   "첫 5K 완주"),
            (10000, "first_10k",  "첫 10K 완주"),
            (21097, "first_half", "첫 하프 완주"),
            (42195, "first_full", "첫 풀 완주"),
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
                    title: "누적 \(Int(km))km 돌파",
                    detail: String(format: "총 %.0fkm", totalKm)
                ))
                nextThresh += 1
            }
        }

        // 현재 최장 거리 (거리 마일스톤에 없는 경우만)
        if let longest = allRuns.max(by: { $0.distance < $1.distance }),
           longest.distance >= 5000,
           !coveredRunIDs.contains(longest.id) {
            events.append(.init(id: "longest", date: longest.date, kind: .longest,
                                title: "현재 최장 거리", detail: longest.formattedDistance))
        }

        return events.sorted { $0.date < $1.date }
    }

    // MARK: - PR data

    private static let prBuckets: [(id: String, label: String, range: ClosedRange<Double>)] = [
        ("5K",   "5K",    4700...5500),
        ("10K",  "10K",   9500...10500),
        ("half", "하프",  20000...22000),
        ("full", "풀",    41000...43000),
    ]

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
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return starts.map { s in WeeklyKm(id: s, label: fmt.string(from: s), km: totals[s] ?? 0) }
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
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return starts.map { s in WeeklyMins(id: s, label: fmt.string(from: s), mins: totals[s] ?? 0) }
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
        let fmt = DateFormatter()
        fmt.dateFormat = "M월"
        return starts.map { s in MonthlyKm(id: s, label: fmt.string(from: s), km: totals[s] ?? 0) }
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
        let fmt = DateFormatter()
        fmt.dateFormat = "M월"
        return starts.map { s in MonthlyMins(id: s, label: fmt.string(from: s), mins: totals[s] ?? 0) }
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
        if streak >= 2 {
            return "\(streak)주 연속 · \(Self.heatmapWeeks)주간 \(activeDays)일 러닝"
        } else if activeDays > 0 {
            return "최근 \(Self.heatmapWeeks)주간 \(activeDays)일 러닝"
        } else {
            return "최근 \(Self.heatmapWeeks)주간 기록 없음"
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
    private let dayLabels = ["월", "", "수", "", "금", "토", "일"]

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
        HStack(spacing: 5) {
            Spacer()
            Text("적음")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            ForEach([0.0, 2.0, 5.0, 8.0, 12.0], id: \.self) { km in
                RoundedRectangle(cornerRadius: 2)
                    .fill(cellColor(km: km, isFuture: false))
                    .frame(width: cellSize, height: cellSize)
            }
            Text("많음")
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

    private func shortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return fmt.string(from: date)
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

    private func shortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yy.M.d"
        return fmt.string(from: date)
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

    private func dateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yy.M.d"
        return fmt.string(from: date)
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

    private var trendDirection: Double? {
        guard dataPoints.count >= 4 else { return nil }
        let half = dataPoints.count / 2
        let older = dataPoints.prefix(half).map(\.value).reduce(0, +) / Double(half)
        let newer = dataPoints.suffix(half).map(\.value).reduce(0, +) / Double(half)
        guard older > 0 else { return nil }
        let delta = (newer - older) / older
        return abs(delta) > 0.01 ? delta : nil
    }

    private var trendArrow: String? {
        guard let d = trendDirection else { return nil }
        return d > 0 ? "↑" : "↓"
    }

    private var sparkColor: Color {
        guard let arrow = trendArrow,
              metric != .bodyMass && metric != .bodyFatPercentage else { return Theme.violet }
        let up = arrow == "↑"
        return (metric.lowerIsBetter ? !up : up) ? .green : Color(red: 1, green: 0.4, blue: 0.4)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(metric.koreanLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let arrow = trendArrow {
                        Text(arrow)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(sparkColor)
                    }
                }
                if isLoading {
                    Color.clear
                        .frame(height: 56)
                        .overlay(ProgressView().scaleEffect(0.7).tint(Theme.violet))
                } else if let cur = currentValue {
                    Text(metric.formattedValue(cur, usePounds: usePounds))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    sparkline
                } else {
                    Text("데이터 없음")
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
            let from = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
            dataPoints = await manager.fetchMetricHistory(metric, from: from, usePounds: usePounds)
            isLoading = false
        }
    }

    @ViewBuilder
    private var sparkline: some View {
        if dataPoints.count >= 2 {
            Chart(dataPoints, id: \.date) { pt in
                LineMark(
                    x: .value("날짜", pt.date),
                    y: .value(metric.unit, pt.value)
                )
                .foregroundStyle(sparkColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
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
