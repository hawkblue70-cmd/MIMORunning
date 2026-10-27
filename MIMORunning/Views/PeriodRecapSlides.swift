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
        hero(value: "\(recap.runDays)", unit: L.s("일", "days", ja: "日"),
             label: L.s("달린 날", "DAYS RUN", ja: "走った日"))

        separator
        HStack(spacing: 0) {
            secondaryCell(value: L.s("\(recap.longestDayStreak)일", "\(recap.longestDayStreak)d", ja: "\(recap.longestDayStreak)日"),
                          label: L.s("최장 연속", "BEST STREAK", ja: "最長連続"), labelColor: p.accentGold)
            cellDivider
            secondaryCell(value: L.s("\(recap.longestWeekStreak)주", "\(recap.longestWeekStreak)wk", ja: "\(recap.longestWeekStreak)週"),
                          label: L.s("연속 주", "WEEK STREAK", ja: "連続週"), labelColor: p.brand)
            cellDivider
            secondaryCell(value: "\(recap.weeksRan)/\(recap.weekKm.count)",
                          label: L.s("달린 주", "WEEKS RUN", ja: "走った週"), labelColor: p.accentTeal)
        }

        Rectangle().fill(p.divider).frame(height: 0.5)
            .padding(.top, 10).padding(.bottom, 6)
        chartLabel(recap.isYear ? L.s("주간 거리", "WEEKLY DIST", ja: "週別距離")
                                : L.s("달린 날", "RUN DAYS", ja: "走った日"),
                   unit: recap.isYear ? stats.distanceUnit.uppercased() : nil)
        if recap.isYear {
            weeklyBars
        } else {
            monthCalendar
        }
        Spacer(minLength: 0)
    }

    /// 월 달력 — 월요일 시작 7칸, 칸 색 = 그날 거리(그 달 최대 대비 4단계)
    private var monthCalendar: some View {
        let cal = InsightEngine.weekCalendar
        let maxKm = recap.dayKm.values.max() ?? 1
        let firstWeekday = (cal.component(.weekday, from: recap.start) + 5) % 7   // 월=0 … 일=6
        let dayCount = cal.range(of: .day, in: .month, for: recap.start)?.count ?? 30
        let cells: [Int?] = Array(repeating: nil, count: firstWeekday) + (1...dayCount).map { Optional($0) }
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        let size: CGFloat = 20
        let dayNames = L.isEnglish ? ["M", "T", "W", "T", "F", "S", "S"]
                     : L.isJapanese ? ["月", "火", "水", "木", "金", "土", "日"]
                     : ["월", "화", "수", "목", "금", "토", "일"]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Text(dayNames[i])
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(p.axisLabel)
                        .frame(width: size)
                }
            }
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { c in
                        let day = c < rows[r].count ? rows[r][c] : nil
                        RoundedRectangle(cornerRadius: 4)
                            .fill(day.map { heatColor(km: kmOn(day: $0, cal: cal), max: maxKm) } ?? .clear)
                            .frame(width: size, height: size)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
        let factor = stats.useMiles ? 0.621371 : 1.0
        let data = recap.weekKm.enumerated().map { (i: $0.offset, km: $0.element.km * factor) }
        return Chart(data, id: \.i) { d in
            BarMark(x: .value("주", d.i), y: .value("거리", d.km), width: .fixed(3))
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
        .frame(height: 100)
    }

    // MARK: 기록 · 대회

    @ViewBuilder
    private var records: some View {
        if !recap.prs.isEmpty {
            chartLabel(L.s("최고 기록", "PERSONAL BESTS", ja: "自己ベスト"), unit: nil)
            VStack(spacing: 8) {
                ForEach(recap.prs.indices, id: \.self) { i in
                    let pr = recap.prs[i]
                    HStack(spacing: 6) {
                        Text(pr.label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(p.textPrimary)
                        Text(pr.isFirst ? L.s("첫 완주", "FIRST", ja: "初完走") : L.s("최고 기록", "PB", ja: "自己ベスト"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(p.brand)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(p.brand.opacity(0.14))
                            .clipShape(Capsule())
                        Spacer()
                        Text(PeriodRecap.fmtDuration(pr.duration))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(p.textPrimary)
                        Text(dateStr(pr.date))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(p.textSecondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
            .padding(.bottom, 12)
        }
        if !recap.races.isEmpty {
            if !recap.prs.isEmpty {
                Rectangle().fill(p.divider).frame(height: 0.5).padding(.bottom, 8)
            }
            let shown = Array(recap.races.prefix(recap.prs.isEmpty ? 8 : 5))
            chartLabel(L.s("대회 \(recap.races.count)회", "RACES · \(recap.races.count)", ja: "レース \(recap.races.count)回"), unit: nil)
            VStack(spacing: 8) {
                ForEach(shown.indices, id: \.self) { i in
                    let race = shown[i]
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(race.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(p.textPrimary)
                                .lineLimit(1)
                            Text(raceDistance(race.distanceKm))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(p.textSecondary)
                        }
                        Spacer()
                        Text(PeriodRecap.fmtDuration(race.duration))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(p.textPrimary)
                        Text(dateStr(race.date))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(p.textSecondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                if recap.races.count > shown.count {
                    Text(L.s("외 \(recap.races.count - shown.count)회", "+\(recap.races.count - shown.count) more", ja: "ほか\(recap.races.count - shown.count)回"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(p.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        Spacer(minLength: 0)
    }

    private func raceDistance(_ km: Double) -> String {
        switch km {
        case 41...43: return L.s("풀", "Full", ja: "フル")
        case 20...22: return L.s("하프", "Half", ja: "ハーフ")
        default:
            return stats.useMiles ? String(format: "%.1fmi", km * 0.621371)
                                  : (km == km.rounded() ? String(format: "%.0fK", km) : String(format: "%.1fkm", km))
        }
    }

    private func dateStr(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    // MARK: 성장 추세 (VO2 — 추세만)

    @ViewBuilder
    private var trend: some View {
        if let v = recap.vo2 {
            let delta = (v.delta * 10).rounded() / 10
            hero(value: delta == 0 ? "±0.0" : String(format: "%+.1f", delta), unit: nil,
                 label: recap.isYear ? L.s("VO2MAX 연초 → 연말", "VO2MAX · START → END OF YEAR", ja: "VO2MAX 年初 → 年末")
                                     : L.s("VO2MAX 월초 → 월말", "VO2MAX · START → END OF MONTH", ja: "VO2MAX 月初 → 月末"))

            Rectangle().fill(p.divider).frame(height: 0.5)
                .padding(.top, 10).padding(.bottom, 6)
            chartLabel(L.s("VO2MAX 추세", "VO2MAX TREND", ja: "VO2MAX 推移"), unit: nil)
            let lo = (v.points.map(\.value).min() ?? 0) - 1
            let hi = (v.points.map(\.value).max() ?? 0) + 1
            Chart(v.points.indices, id: \.self) { i in
                LineMark(x: .value("날짜", v.points[i].date), y: .value("VO2", v.points[i].value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(p.accentTeal)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                PointMark(x: .value("날짜", v.points[i].date), y: .value("VO2", v.points[i].value))
                    .symbolSize(i == 0 || i == v.points.count - 1 ? 30 : 0)
                    .foregroundStyle(p.accentTeal)
            }
            .chartYScale(domain: lo...hi)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)   // 절댓값 눈금 없이 추세만
            .frame(height: 100)

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

    // MARK: 공용 조각 — 결산 카드와 같은 값

    private func hero(value: String, unit: String?, label: String) -> some View {
        SummaryHero(value: value, unit: unit, label: label, theme: theme)
    }

    private var separator: some View {
        Rectangle().fill(p.divider).frame(height: 0.5)
            .padding(.top, 10).padding(.bottom, 8)
    }

    private func chartLabel(_ text: String, unit: String?) -> some View {
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

    private func secondaryCell(value: String, label: String, labelColor: Color) -> some View {
        SummarySecondaryCell(value: value, label: label, labelColor: labelColor, theme: theme)
    }

    private var cellDivider: some View { SummaryCellDivider(theme: theme) }
}
