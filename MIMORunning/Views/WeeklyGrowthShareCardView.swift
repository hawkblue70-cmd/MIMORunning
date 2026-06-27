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
                    .padding(.top, 18)

                divider.padding(.top, 10)

                weekLabel
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                statTiles
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                if let text = insightText {
                    insightBanner(text: text)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }

                if !sparkData.isEmpty {
                    divider.padding(.top, 10)
                    sparkGrid
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }

                Spacer(minLength: 8)

                footerRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
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
        .padding(.vertical, 8)
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
        .padding(.vertical, 8)
        .background(Theme.violet.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // 2-column grid using HStack/VStack — LazyVGrid는 ImageRenderer 비호환
    private var sparkGrid: some View {
        let rows = stride(from: 0, to: sparkData.count, by: 2).map { i in
            Array(sparkData[i..<min(i + 2, sparkData.count)])
        }
        return VStack(spacing: 6) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 6) {
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

        return VStack(alignment: .leading, spacing: 3) {
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
                .frame(height: 24)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footerRow: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color(hex: "3DFF7A").opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: "figure.run")
                    .font(.system(size: 12, weight: .light))
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
    let manager: HealthKitManager

    @State private var sparkData: [(metric: TrendMetric, points: [(date: Date, value: Double)])] = []
    @State private var shareURL: URL?
    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @Environment(\.dismiss) private var dismiss

    private let cardW: CGFloat = 300
    private let cardH: CGFloat = 560

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
            await fetchSparkData()
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
        } else if let url = shareURL, let img = previewImage {
            ShareLink(
                item: url,
                preview: SharePreview(
                    AppLanguage.shared.s("이번 주 성장", "This Week's Growth"),
                    image: Image(uiImage: img)
                )
            ) {
                Label(AppLanguage.shared.s("공유하기", "Share"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
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
        guard let img = renderer.uiImage, let data = img.pngData() else {
            isRendering = false; return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_weekly_growth.png")
        try? data.write(to: url)
        previewImage = img
        shareURL = url
        isRendering = false
    }
}
