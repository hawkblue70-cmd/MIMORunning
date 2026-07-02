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

// MARK: - Weekly Growth Share Card

struct WeeklyGrowthShareCard: View {
    let km: Double
    let mins: Double
    let count: Int
    let streak: Int
    let insightText: String?
    let insightSymbol: String?
    let insightColor: Color?
    let sparkData: [(metric: TrendMetric, points: [(date: Date, value: Double)])]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 0) {
                wordmarkRow
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                divider.padding(.top, 7)

                weekLabel
                    .padding(.horizontal, 20)
                    .padding(.top, 7)

                statTiles
                    .padding(.horizontal, 16)
                    .padding(.top, 7)

                if let text = insightText {
                    insightBanner(text: text)
                        .padding(.horizontal, 16)
                        .padding(.top, 7)
                }

                if !sparkData.isEmpty {
                    divider.padding(.top, 7)
                    sparkGrid
                        .padding(.horizontal, 16)
                        .padding(.top, 7)
                }

                Spacer(minLength: 5)

                footerRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 9)
            }
        }
    }

    // MARK: - Subviews

    private var wordmarkRow: some View {
        HStack(spacing: 0) {
            Text("MIMO")
                .font(.system(size: 11, weight: .black))
                .tracking(2)
                .foregroundStyle(.white)
            Text(" RUNNING")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.violet)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.violet.opacity(0.35))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    private var weekLabel: some View {
        Text(weekRangeString)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
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
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.40))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func insightBanner(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let sym = insightSymbol, let col = insightColor {
                Image(systemName: sym)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(col)
                    .padding(.top, 1)
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.violet.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // 2-column grid using HStack/VStack — LazyVGrid는 ImageRenderer 비호환
    private var sparkGrid: some View {
        let rows = stride(from: 0, to: sparkData.count, by: 2).map { i in
            Array(sparkData[i..<min(i + 2, sparkData.count)])
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
        let sparkColor: Color = sentiment == .good ? .green : Theme.violet
        let arrowColor: Color = sentiment == .good ? .green : Color(hex: "8A8A92")
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
                    .foregroundStyle(.white.opacity(0.50))
                Spacer()
                if let a = arrow {
                    Text(a)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(arrowColor)
                }
            }
            if let cur = dataPoints.last?.value {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(metric.formattedValue(cur))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let r = ratioStr {
                        Text(r)
                            .font(.system(size: 7))
                            .foregroundStyle(Color(hex: "6E6E78"))
                    }
                }
            }
            ShareSparkline(dataPoints: dataPoints, color: sparkColor)
                .frame(height: 16)
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footerRow: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color(hex: "3DFF7A").opacity(0.12))
                    .frame(width: 20, height: 20)
                Image(systemName: "figure.run")
                    .font(.system(size: 8, weight: .light))
                    .foregroundStyle(Color(hex: "3DFF7A"))
            }
            Spacer()
            Text("mimorunning")
                .font(.system(size: 8, weight: .medium))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.18))
        }
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
    @Environment(\.dismiss) private var dismiss

    private let cardW: CGFloat = 300
    private let cardH: CGFloat = 375

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer()
                    WeeklyGrowthShareCard(
                        km: km, mins: mins, count: count, streak: streak,
                        insightText: insightText,
                        insightSymbol: insightSymbol,
                        insightColor: insightColor,
                        sparkData: sparkData
                    )
                    .frame(width: cardW, height: cardH)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Theme.violet.opacity(0.30), radius: 28, y: 10)

                    Spacer(minLength: 24)

                    shareCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }
            }
            .navigationTitle(AppLanguage.shared.s("이번 주 공유", "Share This Week"))
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
                Label(AppLanguage.shared.s("공유하기", "Share"), systemImage: "square.and.arrow.up")
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
                sparkData: sparkData
            )
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

private struct MileageBarPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
}

struct MileageStreakShareCard: View {
    let showMonthly: Bool
    let showDaily: Bool
    let showTimeMileage: Bool
    let mileageSubtitle: String
    let barData: [(label: String, value: Double)]
    let heatmapColumns: [ShareHeatmapColumn]
    let streak: Int
    let activeDays: Int
    let heatmapWeekCount: Int

    private static let cellSize: CGFloat = 7
    private static let cellGap:  CGFloat = 2
    private static let labelW:   CGFloat = 10

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 0) {
                wordmarkRow
                    .padding(.horizontal, 20)
                    .padding(.top, 13)

                divider.padding(.top, 7)

                mileageTitleRow
                    .padding(.horizontal, 20)
                    .padding(.top, 7)

                barChart
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
        HStack(spacing: 0) {
            Text("MIMO")
                .font(.system(size: 11, weight: .black))
                .tracking(2)
                .foregroundStyle(.white)
            Text(" RUNNING")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.violet)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.violet.opacity(0.35))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    // MARK: Mileage section
    private var mileageTitleRow: some View {
        let L = AppLanguage.shared
        let period: String
        if showDaily {
            period = L.s("일간", "Daily")
        } else {
            period = showMonthly ? L.s("월간", "Monthly") : L.s("주간", "Weekly")
        }
        let mode = (showDaily || !showTimeMileage) ? L.s("거리", "Distance") : L.s("시간", "Time")
        return VStack(alignment: .leading, spacing: 1) {
            Text("\(period) \(mode)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            Text(mileageSubtitle)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.50))
        }
    }

    private var barChart: some View {
        let items = barData.map { MileageBarPoint(label: $0.label, value: $0.value) }
        let color: Color = (showDaily || showTimeMileage) ? Theme.time : Theme.violet
        return Chart(items) { item in
            BarMark(
                x: .value("x", item.label),
                y: .value("y", item.value)
            )
            .foregroundStyle(item.value > 0 ? color.gradient : Color.secondary.opacity(0.25).gradient)
            .cornerRadius(3)
        }
        .frame(height: 85)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    Text(value.as(String.self) ?? "")
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(yLabel(v))
                            .font(.system(size: 7))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
        }
        .padding(7)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func yLabel(_ v: Double) -> String {
        if !showDaily && showTimeMileage {
            let h = Int(v) / 60; let m = Int(v) % 60
            return h > 0 ? "\(h)h" : "\(m)m"
        } else {
            return String(format: "%.0f", v)
        }
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
        return VStack(alignment: .leading, spacing: 1) {
            Text(L.s("연속 달리기", "Streak"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.70))
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.40))
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
                            .foregroundStyle(.white.opacity(0.40))
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
                        .foregroundStyle(.white.opacity(0.35))
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
                    .foregroundStyle(.white.opacity(0.35))
                ForEach([0.0, 2.0, 5.0, 8.0, 12.0], id: \.self) { km in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cellColor(km: km, isFuture: false))
                        .frame(width: cs, height: cs)
                }
                Text(AppLanguage.shared.s("많음", "More"))
                    .font(.system(size: 6))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(7)
        .background(Color.white.opacity(0.04))
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
        if isFuture { return Color.white.opacity(0.04) }
        if km == 0  { return Theme.violet.opacity(0.10) }
        if km < 3   { return Theme.violet.opacity(0.32) }
        if km < 6   { return Theme.violet.opacity(0.56) }
        if km < 10  { return Theme.violet.opacity(0.80) }
        return Theme.violet
    }

    // MARK: Footer
    private var footerRow: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color(hex: "3DFF7A").opacity(0.12))
                    .frame(width: 20, height: 20)
                Image(systemName: "figure.run")
                    .font(.system(size: 8, weight: .light))
                    .foregroundStyle(Color(hex: "3DFF7A"))
            }
            Spacer()
            Text("mimorunning")
                .font(.system(size: 8, weight: .medium))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.18))
        }
    }
}

// MARK: - Mileage + Streak share screen

struct MileageStreakShareCardScreen: View {
    let showMonthly: Bool
    let showDaily: Bool
    let showTimeMileage: Bool
    let mileageSubtitle: String
    let barData: [(label: String, value: Double)]
    let heatmapColumns: [ShareHeatmapColumn]
    let streak: Int
    let activeDays: Int
    let heatmapWeekCount: Int

    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @State private var showShareSheet = false
    @Environment(\.dismiss) private var dismiss

    private let cardW: CGFloat = 300
    private let cardH: CGFloat = 375

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer()
                    MileageStreakShareCard(
                        showMonthly: showMonthly,
                        showDaily: showDaily,
                        showTimeMileage: showTimeMileage,
                        mileageSubtitle: mileageSubtitle,
                        barData: barData,
                        heatmapColumns: heatmapColumns,
                        streak: streak,
                        activeDays: activeDays,
                        heatmapWeekCount: heatmapWeekCount
                    )
                    .frame(width: cardW, height: cardH)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Theme.violet.opacity(0.30), radius: 28, y: 10)

                    Spacer(minLength: 24)

                    shareCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }
            }
            .navigationTitle(AppLanguage.shared.s("거리 · 연속 공유", "Mileage & Streak"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Theme.violet)
                }
            }
        }
        .task { await renderCard() }
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
                Label(AppLanguage.shared.s("공유하기", "Share"), systemImage: "square.and.arrow.up")
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
                showMonthly: showMonthly,
                showDaily: showDaily,
                showTimeMileage: showTimeMileage,
                mileageSubtitle: mileageSubtitle,
                barData: barData,
                heatmapColumns: heatmapColumns,
                streak: streak,
                activeDays: activeDays,
                heatmapWeekCount: heatmapWeekCount
            )
            .frame(width: cardW, height: cardH)
        )
        renderer.scale = 3
        previewImage = renderer.uiImage
        isRendering = false
    }
}
