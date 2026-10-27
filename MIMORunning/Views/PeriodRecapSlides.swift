import SwiftUI
import Charts

// MARK: - 기간별 결산 공유 묶음 슬라이드

/// 묶음 순서: 결산 카드(총거리) → 리듬 → 기록·대회 → 성장 추세 → 기간 제목. 데이터 없는 장은 뺀다.
enum PeriodRecapSlide: Hashable {
    case rhythm, records, trend, headline
}

extension PeriodRecap {
    var slides: [PeriodRecapSlide] {
        var s: [PeriodRecapSlide] = [.rhythm]
        if !prs.isEmpty || !races.isEmpty { s.append(.records) }
        if vo2 != nil { s.append(.trend) }
        s.append(.headline)
        return s
    }
}

/// 장 하나 — 틀은 결산 카드와 같은 `SummaryCardChrome`, 글자 크기·여백도 결산 카드 값(히어로 55 · 보조 16/11 · 줄 12/13)
struct PeriodRecapSlideView: View {
    let slide: PeriodRecapSlide
    let recap: PeriodRecap
    let stats: SummaryPeriodStats
    var miniMeImage: UIImage? = nil
    var theme: ShareTheme = .dark

    private var p: SummaryCardPalette { theme == .light ? .light : .dark }
    private var L: AppLanguage { AppLanguage.shared }

    var body: some View {
        SummaryCardChrome(title: stats.kind.title, subtitle: subtitle,
                          miniMeImage: miniMeImage, showsMiniMe: slide != .headline, theme: theme) {
            switch slide {
            case .rhythm:   rhythm
            case .records:  records
            case .trend:    trend
            case .headline: headline
            }
        }
    }

    private var subtitle: String {
        let part: String
        switch slide {
        case .rhythm:   part = L.s("리듬", "RHYTHM", ja: "リズム")
        case .records:  part = L.s("기록 · 대회", "RECORDS · RACES", ja: "記録 · レース")
        case .trend:    part = L.s("성장 추세", "TREND", ja: "成長の推移")
        case .headline: part = L.s("한 줄 정리", "IN ONE LINE", ja: "ひとことで")
        }
        return stats.kind.subtitle + " · " + part
    }

    // MARK: 리듬

    @ViewBuilder
    private var rhythm: some View {
        SummaryHero(value: "\(recap.runDays)", unit: L.s("일", "days", ja: "日"),
                    label: L.s("달린 날", "DAYS RUN", ja: "走った日"), theme: theme)
        RecapDivider(theme: theme, top: 10, bottom: 8)
        RecapStreakCells(recap: recap, theme: theme)
        RecapDivider(theme: theme, top: 10, bottom: 6)
        RecapRhythmChart(recap: recap, useMiles: stats.useMiles, theme: theme,
                         cellSize: 20, barHeight: 100)
        Spacer(minLength: 0)
    }

    // MARK: 기록 · 대회

    @ViewBuilder
    private var records: some View {
        RecapRecordRows(recap: recap, useMiles: stats.useMiles, theme: theme,
                        maxPRs: 4, maxRaces: recap.prs.isEmpty ? 8 : 5)
        Spacer(minLength: 0)
    }

    // MARK: 성장 추세 (VO2 — 추세만)

    @ViewBuilder
    private var trend: some View {
        if let v = recap.vo2 {
            SummaryHero(value: RecapVO2Line.deltaText(v), unit: nil,
                        label: recap.isYear ? L.s("VO2MAX 연초 → 연말", "VO2MAX · START → END OF YEAR", ja: "VO2MAX 年初 → 年末")
                                            : L.s("VO2MAX 월초 → 월말", "VO2MAX · START → END OF MONTH", ja: "VO2MAX 月初 → 月末"),
                        theme: theme)
            RecapDivider(theme: theme, top: 10, bottom: 6)
            RecapChartLabel(text: L.s("VO2MAX 추세", "VO2MAX TREND", ja: "VO2MAX 推移"), theme: theme)
            RecapVO2Line(vo2: v, theme: theme, height: 100)
            Text(L.s("워치 VO2max 표본 \(v.points.count)개 · 변화만 표시",
                     "\(v.points.count) watch VO2max samples · change only",
                     ja: "ウォッチVO2max \(v.points.count)件 · 変化のみ表示"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(p.textSecondary)
                .padding(.top, 6)
        }
        Spacer(minLength: 0)
    }

    // MARK: 기간 제목 + 미니미

    @ViewBuilder
    private var headline: some View {
        Spacer(minLength: 0)
        VStack(spacing: 14) {
            SummaryMiniMe(image: miniMeImage, size: 120, theme: theme)
            Text(recap.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(p.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(recap.detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(p.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        Spacer(minLength: 0)
        Text(L.s("총 \(stats.distanceStr)\(stats.distanceUnit) · \(recap.runCount)회",
                 "\(stats.distanceStr)\(stats.distanceUnit) · \(recap.runCount) runs",
                 ja: "合計\(stats.distanceStr)\(stats.distanceUnit) · \(recap.runCount)回"))
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(p.brand)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)
    }
}

// MARK: - 한 장에 모두 (4:5)

/// 묶음 다섯 장 내용을 한 장에 — 제목 줄 · 총거리 + 보조 지표 · 리듬 | VO2 추세 · 기록·대회.
/// 조각은 묶음 장과 같은 공용 뷰를 쓰고, 칸이 좁은 곳(달력 칸·차트 높이·줄 수)만 인자로 줄인다. 없는 칸은 빼고 남은 칸이 넓어진다.
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
            // ⑤ 기간 제목 + 부연
            Text(recap.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(p.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(recap.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(p.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            RecapDivider(theme: theme, top: 8, bottom: 6)

            // ① 총거리 + 보조 지표
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

            // ② 리듬 | ④ VO2 추세
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    RecapStreakLine(recap: recap, theme: theme)
                    RecapRhythmChart(recap: recap, useMiles: stats.useMiles, theme: theme,
                                     cellSize: 8, barHeight: 56, compact: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let v = recap.vo2 {
                    Rectangle().fill(p.divider).frame(width: 0.5)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("VO2MAX")
                                .font(.system(size: 8, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(p.textSecondary)
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

            // ③ 기록 · 대회
            if !recap.prs.isEmpty || !recap.races.isEmpty {
                RecapDivider(theme: theme, top: 8, bottom: 6)
                RecapRecordRows(recap: recap, useMiles: stats.useMiles, theme: theme,
                                maxPRs: 2, maxRaces: recap.prs.isEmpty ? 3 : 3 - min(2, recap.prs.count), compact: true)
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

// MARK: - 공용 조각 (묶음 장 · 한 장에 모두)

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

/// 최장 연속 · 연속 주 · 달린 주 — 보조 칸 세 개
struct RecapStreakCells: View {
    let recap: PeriodRecap
    var theme: ShareTheme = .dark

    var body: some View {
        let p: SummaryCardPalette = theme == .light ? .light : .dark
        let L = AppLanguage.shared
        HStack(spacing: 0) {
            SummarySecondaryCell(value: L.s("\(recap.longestDayStreak)일", "\(recap.longestDayStreak)d", ja: "\(recap.longestDayStreak)日"),
                                 label: L.s("최장 연속", "BEST STREAK", ja: "最長連続"), labelColor: p.accentGold, theme: theme)
            SummaryCellDivider(theme: theme)
            SummarySecondaryCell(value: L.s("\(recap.longestWeekStreak)주", "\(recap.longestWeekStreak)wk", ja: "\(recap.longestWeekStreak)週"),
                                 label: L.s("연속 주", "WEEK STREAK", ja: "連続週"), labelColor: p.brand, theme: theme)
            SummaryCellDivider(theme: theme)
            SummarySecondaryCell(value: "\(recap.weeksRan)/\(recap.weekKm.count)",
                                 label: L.s("달린 주", "WEEKS RUN", ja: "走った週"), labelColor: p.accentTeal, theme: theme)
        }
    }
}

/// 한 장에 모두용 리듬 머리 — "달린 날 12일 · 최장 연속 3일 · 연속 4주" 한 줄
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
    var cellSize: CGFloat = 20
    var barHeight: CGFloat = 100
    /// true면 차트 라벨·요일 머리를 뺀다(한 장에 모두)
    var compact: Bool = false

    private var p: SummaryCardPalette { theme == .light ? .light : .dark }
    private var L: AppLanguage { AppLanguage.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !compact {
                RecapChartLabel(text: recap.isYear ? L.s("주간 거리", "WEEKLY DIST", ja: "週別距離")
                                                   : L.s("달린 날", "RUN DAYS", ja: "走った日"),
                                unit: recap.isYear ? (useMiles ? "MI" : "KM") : nil, theme: theme)
            }
            if recap.isYear { weeklyBars } else { monthCalendar }
        }
    }

    private var monthCalendar: some View {
        let cal = InsightEngine.weekCalendar
        let maxKm = recap.dayKm.values.max() ?? 1
        let firstWeekday = (cal.component(.weekday, from: recap.start) + 5) % 7   // 월=0 … 일=6
        let dayCount = cal.range(of: .day, in: .month, for: recap.start)?.count ?? 30
        let cells: [Int?] = Array(repeating: nil, count: firstWeekday) + (1...dayCount).map { Optional($0) }
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        let gap = cellSize * 0.3
        let dayNames = L.isEnglish ? ["M", "T", "W", "T", "F", "S", "S"]
                     : L.isJapanese ? ["月", "火", "水", "木", "金", "土", "日"]
                     : ["월", "화", "수", "목", "금", "토", "일"]
        return VStack(alignment: .leading, spacing: gap * 0.7) {
            if !compact {
                HStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(dayNames[i])
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(p.axisLabel)
                            .frame(width: cellSize)
                    }
                }
            }
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
        .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
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
            BarMark(x: .value("주", d.i), y: .value("거리", d.km), width: .fixed(compact ? 2 : 3))
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

/// VO2max 선 — 눈금 없이 추세만, 첫·끝 점 표시
struct RecapVO2Line: View {
    let vo2: PeriodRecap.VO2Trend
    var theme: ShareTheme = .dark
    var height: CGFloat = 100

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

/// 최고 기록 · 대회 줄 — 묶음 장은 줄 수 넉넉히, 한 장에 모두는 몇 줄만(넘치면 '외 N')
struct RecapRecordRows: View {
    let recap: PeriodRecap
    let useMiles: Bool
    var theme: ShareTheme = .dark
    var maxPRs: Int = 4
    var maxRaces: Int = 5
    /// true면 최고 기록·대회를 한 목록으로(머리 라벨 하나)
    var compact: Bool = false

    private var p: SummaryCardPalette { theme == .light ? .light : .dark }
    private var L: AppLanguage { AppLanguage.shared }

    var body: some View {
        let prs = Array(recap.prs.reversed().prefix(maxPRs))     // 긴 거리부터
        let races = Array(recap.races.prefix(maxRaces))
        let hiddenPRs = recap.prs.count - prs.count
        let hiddenRaces = recap.races.count - races.count
        VStack(alignment: .leading, spacing: 0) {
            if compact {
                // 넘친 건수는 줄을 더 쓰지 않고 머리 오른쪽에
                let hidden = hiddenPRs + hiddenRaces
                RecapChartLabel(text: L.s("기록 · 대회", "RECORDS · RACES", ja: "記録 · レース"),
                                unit: hidden > 0 ? L.s("외 \(hidden)건", "+\(hidden) more", ja: "ほか\(hidden)件") : nil,
                                theme: theme)
                VStack(spacing: 6) {
                    ForEach(prs.indices, id: \.self) { prRow(prs[$0]) }
                    ForEach(races.indices, id: \.self) { raceRow(races[$0]) }
                }
            } else {
                if !prs.isEmpty {
                    RecapChartLabel(text: L.s("최고 기록", "PERSONAL BESTS", ja: "自己ベスト"), theme: theme)
                    VStack(spacing: 8) {
                        ForEach(prs.indices, id: \.self) { prRow(prs[$0]) }
                        more(hiddenPRs)
                    }
                    .padding(.bottom, 12)
                }
                if !races.isEmpty {
                    if !prs.isEmpty {
                        Rectangle().fill(p.divider).frame(height: 0.5).padding(.bottom, 8)
                    }
                    RecapChartLabel(text: L.s("대회 \(recap.races.count)회", "RACES · \(recap.races.count)", ja: "レース \(recap.races.count)回"),
                                    theme: theme)
                    VStack(spacing: 8) {
                        ForEach(races.indices, id: \.self) { raceRow(races[$0]) }
                        more(hiddenRaces)
                    }
                }
            }
        }
    }

    private func prRow(_ pr: PeriodRecap.PR) -> some View {
        HStack(spacing: 6) {
            Text(pr.label)
                .font(.system(size: compact ? 12 : 13, weight: .bold))
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
            if compact {
                Text(race.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
                Text(raceDistance(race.distanceKm))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(p.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(race.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(p.textPrimary)
                        .lineLimit(1)
                    Text(raceDistance(race.distanceKm))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(p.textSecondary)
                }
            }
            Spacer()
            timeAndDate(race.duration, race.date)
        }
    }

    private func timeAndDate(_ duration: TimeInterval, _ date: Date) -> some View {
        HStack(spacing: 6) {
            Text(PeriodRecap.fmtDuration(duration))
                .font(.system(size: compact ? 13 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(p.textPrimary)
            Text(dateStr(date))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(p.textSecondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func more(_ n: Int) -> some View {
        if n > 0 {
            Text(L.s("외 \(n)건", "+\(n) more", ja: "ほか\(n)件"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(p.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
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
