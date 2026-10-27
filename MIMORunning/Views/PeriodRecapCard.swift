import SwiftUI
import Charts

// MARK: - 기간별 결산 공유 카드 (한 장에 모두, 4:5)

/// 총거리 + 보조 지표 · 일별(연 = 월별) 거리 막대 · 리듬 | VO2 추세 · 기록·대회(최대 2줄). 없는 칸은 빼고 남은 칸이 넓어진다.
/// 2026-10-28 사용자 결정: 묶음·한 장 카드 삭제, 기간 제목·부연(인사이트) 삭제 — 숫자만.
struct PeriodRecapAllInOneCard: View {
    let recap: PeriodRecap
    let stats: SummaryPeriodStats
    var miniMeImage: UIImage? = nil
    var theme: ShareTheme = .dark

    private var p: SummaryCardPalette { theme == .light ? .light : .dark }
    private var L: AppLanguage { AppLanguage.shared }

    var body: some View {
        SummaryCardChrome(title: stats.kind.title, subtitle: stats.kind.subtitle,
                          miniMeImage: miniMeImage, theme: theme) {
            // 총거리 + 보조 지표
            HStack(alignment: .bottom, spacing: 12) {
                SummaryHero(value: stats.distanceStr, unit: stats.distanceUnit,
                            label: L.s("총 거리", "TOTAL", ja: "総距離"), theme: theme)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    miniStat(stats.durationStr, L.s("운동 시간", "TIME", ja: "運動時間"), p.accentGold)
                    miniStat(L.s("\(stats.runCount)회", "\(stats.runCount)", ja: "\(stats.runCount)回"),
                             L.s("러닝", "RUNS", ja: "ラン"), p.brand)
                    if let pace = stats.avgPaceStr {
                        miniStat(pace, L.s("평균 페이스", "AVG PACE", ja: "平均ペース"), p.accentTeal)
                    }
                }
                .padding(.bottom, 2)
            }

            RecapDivider(theme: theme, top: 8, bottom: 6)

            // 일별 거리(연 = 월별) — 높이가 빠듯해 달력 칸·기록 줄을 줄여 4:5 한 장에 맞춘다
            RecapChartLabel(text: recap.isYear ? L.s("월별 거리", "MONTHLY DIST", ja: "月別距離")
                                               : L.s("일별 거리", "DAILY DIST", ja: "日別距離"),
                            unit: stats.useMiles ? "MI" : "KM", theme: theme)
            RecapDistanceBars(recap: recap, useMiles: stats.useMiles, theme: theme, height: 50)

            RecapDivider(theme: theme, top: 8, bottom: 6)

            // 리듬 | VO2 추세
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    RecapStreakLine(recap: recap, theme: theme)
                    RecapRhythmChart(recap: recap, useMiles: stats.useMiles, theme: theme,
                                     cellSize: 8, barHeight: 56)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let v = recap.vo2 {
                    Rectangle().fill(p.divider).frame(width: 0.5)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(recap.isYear ? L.s("VO2MAX 연초 → 연말", "VO2MAX · YEAR", ja: "VO2MAX 年初 → 年末")
                                              : L.s("VO2MAX 월초 → 월말", "VO2MAX · MONTH", ja: "VO2MAX 月初 → 月末"))
                                .font(.system(size: 8, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(p.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 0)
                            Text(RecapVO2Line.deltaText(v))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(p.textPrimary)
                        }
                        .padding(.bottom, 4)
                        RecapVO2Line(vo2: v, theme: theme, height: 56)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            // 기록 · 대회
            if !recap.prs.isEmpty || !recap.races.isEmpty {
                RecapDivider(theme: theme, top: 8, bottom: 6)
                RecapRecordRows(recap: recap, useMiles: stats.useMiles, theme: theme, maxRows: 2)
            }
            Spacer(minLength: 0)
        }
    }

    private func miniStat(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(color.opacity(0.75))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(p.textPrimary)
        }
    }
}

// MARK: - 조각

struct RecapDivider: View {
    var theme: ShareTheme = .dark
    var top: CGFloat = 10
    var bottom: CGFloat = 8

    var body: some View {
        let p: SummaryCardPalette = theme == .light ? .light : .dark
        Rectangle().fill(p.divider).frame(height: 0.5)
            .padding(.top, top).padding(.bottom, bottom)
    }
}

struct RecapChartLabel: View {
    let text: String
    var unit: String? = nil
    var theme: ShareTheme = .dark

    var body: some View {
        let p: SummaryCardPalette = theme == .light ? .light : .dark
        HStack {
            Text(text)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(p.textSecondary)
            Spacer()
            if let unit {
                Text(unit)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(p.axisLabel)
            }
        }
        .padding(.bottom, 5)
    }
}

/// 리듬 머리 — "달린 날 12일 · 연속 3일 · 4주" 한 줄
struct RecapStreakLine: View {
    let recap: PeriodRecap
    var theme: ShareTheme = .dark

    var body: some View {
        let p: SummaryCardPalette = theme == .light ? .light : .dark
        let L = AppLanguage.shared
        VStack(alignment: .leading, spacing: 2) {
            Text(L.s("리듬", "RHYTHM", ja: "リズム"))
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(p.textSecondary)
            Text(L.s("달린 날 \(recap.runDays)일 · 연속 \(recap.longestDayStreak)일 · \(recap.longestWeekStreak)주",
                     "\(recap.runDays) days · streak \(recap.longestDayStreak)d · \(recap.longestWeekStreak)wk",
                     ja: "走った日 \(recap.runDays)日 · 連続 \(recap.longestDayStreak)日 · \(recap.longestWeekStreak)週"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(p.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.bottom, 5)
    }
}

/// 리듬 차트 — 월 = 월요일 시작 달력 잔디(칸 색 = 그날 거리, 그 달 최대 대비 4단계), 연 = 주간 거리 막대
struct RecapRhythmChart: View {
    let recap: PeriodRecap
    let useMiles: Bool
    var theme: ShareTheme = .dark
    var cellSize: CGFloat = 10
    var barHeight: CGFloat = 70

    private var p: SummaryCardPalette { theme == .light ? .light : .dark }

    var body: some View {
        if recap.isYear { weeklyBars } else { monthCalendar }
    }

    private var monthCalendar: some View {
        let cal = InsightEngine.weekCalendar
        let maxKm = recap.dayKm.values.max() ?? 1
        let firstWeekday = (cal.component(.weekday, from: recap.start) + 5) % 7   // 월=0 … 일=6
        let dayCount = cal.range(of: .day, in: .month, for: recap.start)?.count ?? 30
        let cells: [Int?] = Array(repeating: nil, count: firstWeekday) + (1...dayCount).map { Optional($0) }
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        let gap = cellSize * 0.3
        return VStack(alignment: .leading, spacing: gap * 0.7) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { c in
                        let day = c < rows[r].count ? rows[r][c] : nil
                        RoundedRectangle(cornerRadius: cellSize * 0.2)
                            .fill(day.map { heatColor(km: kmOn(day: $0, cal: cal), max: maxKm) } ?? .clear)
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }

    private func kmOn(day: Int, cal: Calendar) -> Double {
        guard let d = cal.date(byAdding: .day, value: day - 1, to: recap.start) else { return 0 }
        return recap.dayKm[cal.startOfDay(for: d)] ?? 0
    }

    private func heatColor(km: Double, max: Double) -> Color {
        guard km > 0, max > 0 else { return p.heatEmpty }
        switch km / max {
        case ..<0.25: return p.heatLow
        case ..<0.5:  return p.heatMid
        case ..<0.75: return p.heatHigh
        default:      return p.heatFull
        }
    }

    private var weeklyBars: some View {
        let factor = useMiles ? 0.621371 : 1.0
        let data = recap.weekKm.enumerated().map { (i: $0.offset, km: $0.element.km * factor) }
        return Chart(data, id: \.i) { d in
            BarMark(x: .value("주", d.i), y: .value("거리", d.km), width: .fixed(2))
                .foregroundStyle(d.km > 0 ? p.weeklyBarColor.gradient : Color.clear.gradient)
                .cornerRadius(1)
        }
        .chartXScale(domain: -1...max(52, data.count))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 2)) { value in
                AxisValueLabel {
                    Text(String(format: "%.0f", value.as(Double.self) ?? 0))
                        .font(.system(size: 7))
                        .foregroundStyle(p.axisLabel)
                }
                AxisGridLine().foregroundStyle(p.gridLine)
            }
        }
        .frame(height: barHeight)
    }
}

/// 거리 막대 — 월 = 그 달 날짜별, 연 = 1~12월
struct RecapDistanceBars: View {
    let recap: PeriodRecap
    let useMiles: Bool
    var theme: ShareTheme = .dark
    var height: CGFloat = 50

    private static let monthAbbr = ["", "J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    private var data: [(x: Int, km: Double)] {
        let cal = InsightEngine.weekCalendar
        let factor = useMiles ? 0.621371 : 1.0
        if recap.isYear {
            var byMonth: [Int: Double] = [:]
            for (day, km) in recap.dayKm { byMonth[cal.component(.month, from: day), default: 0] += km }
            return (1...12).map { ($0, (byMonth[$0] ?? 0) * factor) }
        }
        let count = cal.range(of: .day, in: .month, for: recap.start)?.count ?? 30
        return (1...count).map { d in
            let day = cal.date(byAdding: .day, value: d - 1, to: recap.start).map { cal.startOfDay(for: $0) }
            return (d, (day.flatMap { recap.dayKm[$0] } ?? 0) * factor)
        }
    }

    var body: some View {
        let p: SummaryCardPalette = theme == .light ? .light : .dark
        let pts = data
        let isYear = recap.isYear
        Chart(pts, id: \.x) { d in
            BarMark(x: .value("날", d.x), y: .value("거리", d.km), width: .fixed(isYear ? 14 : 5))
                .foregroundStyle(d.km > 0 ? p.monthlyBarColor.gradient : Color.clear.gradient)
                .cornerRadius(2)
        }
        .chartXScale(domain: isYear ? 0...13 : 0...32)
        .chartXAxis {
            AxisMarks(values: isYear ? [1, 3, 5, 7, 9, 11] : [1, 7, 14, 21, 28]) { value in
                AxisValueLabel {
                    let v = value.as(Int.self) ?? 0
                    Text(isYear ? (v > 0 && v < Self.monthAbbr.count ? Self.monthAbbr[v] : "") : "\(v)")
                        .font(.system(size: 7))
                        .foregroundStyle(p.axisLabel)
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 2)) { value in
                AxisValueLabel {
                    Text(String(format: "%.0f", value.as(Double.self) ?? 0))
                        .font(.system(size: 7))
                        .foregroundStyle(p.axisLabel)
                }
                AxisGridLine().foregroundStyle(p.gridLine)
            }
        }
        .frame(height: height)
    }
}

/// VO2max 선 — 눈금 없이 추세만, 첫·끝 점 표시
struct RecapVO2Line: View {
    let vo2: PeriodRecap.VO2Trend
    var theme: ShareTheme = .dark
    var height: CGFloat = 70

    static func deltaText(_ v: PeriodRecap.VO2Trend) -> String {
        let delta = (v.delta * 10).rounded() / 10
        return delta == 0 ? "±0.0" : String(format: "%+.1f", delta)
    }

    var body: some View {
        let p: SummaryCardPalette = theme == .light ? .light : .dark
        let pts = vo2.points
        let lo = (pts.map(\.value).min() ?? 0) - 1
        let hi = (pts.map(\.value).max() ?? 0) + 1
        Chart(pts.indices, id: \.self) { i in
            LineMark(x: .value("날짜", pts[i].date), y: .value("VO2", pts[i].value))
                .interpolationMethod(.monotone)
                .foregroundStyle(p.accentTeal)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            PointMark(x: .value("날짜", pts[i].date), y: .value("VO2", pts[i].value))
                .symbolSize(i == 0 || i == pts.count - 1 ? 30 : 0)
                .foregroundStyle(p.accentTeal)
        }
        .chartYScale(domain: lo...hi)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)   // 절댓값 눈금 없이 추세만
        .frame(height: height)
    }
}

/// 최고 기록 · 대회 줄 — 긴 거리 기록부터, 남은 줄에 대회. 넘친 건수는 머리 오른쪽 '외 N건'.
struct RecapRecordRows: View {
    let recap: PeriodRecap
    let useMiles: Bool
    var theme: ShareTheme = .dark
    var maxRows: Int = 4

    private var p: SummaryCardPalette { theme == .light ? .light : .dark }
    private var L: AppLanguage { AppLanguage.shared }

    var body: some View {
        // 기록이 줄을 다 차지하지 않게 — 대회가 있으면 기록은 최대 maxRows−1
        let prCap = recap.races.isEmpty ? maxRows : max(1, maxRows - 1)
        let prs = Array(recap.prs.reversed().prefix(prCap))
        let races = Array(recap.races.prefix(maxRows - prs.count))
        let hidden = (recap.prs.count - prs.count) + (recap.races.count - races.count)
        VStack(alignment: .leading, spacing: 0) {
            RecapChartLabel(text: L.s("기록 · 대회", "RECORDS · RACES", ja: "記録 · レース"),
                            unit: hidden > 0 ? L.s("외 \(hidden)건", "+\(hidden) more", ja: "ほか\(hidden)件") : nil,
                            theme: theme)
            VStack(spacing: 6) {
                ForEach(prs.indices, id: \.self) { prRow(prs[$0]) }
                ForEach(races.indices, id: \.self) { raceRow(races[$0]) }
            }
        }
    }

    private func prRow(_ pr: PeriodRecap.PR) -> some View {
        HStack(spacing: 6) {
            Text(pr.label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(p.textPrimary)
            Text(pr.isFirst ? L.s("첫 완주", "FIRST", ja: "初完走") : L.s("최고 기록", "PB", ja: "自己ベスト"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(p.brand)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(p.brand.opacity(0.14))
                .clipShape(Capsule())
            Spacer()
            timeAndDate(pr.duration, pr.date)
        }
    }

    private func raceRow(_ race: PeriodRecap.Race) -> some View {
        HStack(spacing: 6) {
            Text(race.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(p.textPrimary)
                .lineLimit(1)
            Text(raceDistance(race.distanceKm))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(p.textSecondary)
            Spacer()
            timeAndDate(race.duration, race.date)
        }
    }

    private func timeAndDate(_ duration: TimeInterval, _ date: Date) -> some View {
        HStack(spacing: 6) {
            Text(PeriodRecap.fmtDuration(duration))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(p.textPrimary)
            Text(dateStr(date))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(p.textSecondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func raceDistance(_ km: Double) -> String {
        switch km {
        case 41...43: return L.s("풀", "Full", ja: "フル")
        case 20...22: return L.s("하프", "Half", ja: "ハーフ")
        default:
            return useMiles ? String(format: "%.1fmi", km * 0.621371)
                            : (km == km.rounded() ? String(format: "%.0fK", km) : String(format: "%.1fkm", km))
        }
    }

    private func dateStr(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }
}
