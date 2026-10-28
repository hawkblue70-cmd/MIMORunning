import SwiftUI
import Charts

// MARK: - 기간별 결산 카드 (나 탭 = 공유 출력, 4:5)

/// 케이던스·파워·보폭 월 평균과 지난달 평균(워치 전용, 월만)
struct SummaryFormMetrics {
    let cadence: Double?
    let prevCadence: Double?
    let power: Double?
    let prevPower: Double?
    let strideLength: Double?
    let prevStrideLength: Double?
    var hasAny: Bool { cadence != nil || power != nil || strideLength != nil }
}

/// 나 탭 카드 — 공유 카드(`PeriodRecapAllInOneCard`)를 폭에 맞춰 줄여 그대로 보인다. 보이는 화면 = 내보낸 이미지.
struct PeriodSummaryInlineCard: View {
    let stats: SummaryPeriodStats
    let recap: PeriodRecap?
    var form: SummaryFormMetrics? = nil
    var miniMeImage: UIImage? = nil

    var body: some View {
        let size = SummaryCardChrome<EmptyView>.size
        Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { g in
                    Group {
                        if let recap {
                            PeriodRecapAllInOneCard(recap: recap, stats: stats, form: form, miniMeImage: miniMeImage)
                        } else {
                            PeriodRecapEmptyCard(stats: stats, miniMeImage: miniMeImage)
                        }
                    }
                    .scaleEffect(g.size.width / size.width, anchor: .topLeading)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// 러닝이 없는 기간 — 같은 틀에 한 줄
struct PeriodRecapEmptyCard: View {
    let stats: SummaryPeriodStats
    var miniMeImage: UIImage? = nil
    var theme: ShareTheme = .dark

    var body: some View {
        let p: SummaryCardPalette = theme == .light ? .light : .dark
        SummaryCardChrome(title: stats.kind.title, subtitle: stats.kind.subtitle,
                          miniMeImage: miniMeImage, theme: theme) {
            Spacer(minLength: 0)
            Text(AppLanguage.shared.s("이 기간에 기록된 러닝이 없습니다", "No runs for this period", ja: "この期間に記録されたランはありません"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(p.textSecondary)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }
}

/// 배치(2026-10-28 사용자 지정): ① 총거리(72pt) | 운동 시간·러닝·평균 페이스·최장 ② 지난 기간 대비·올해 누적
/// ③ 일별(연 = 월별) 거리 막대 | 유산소(VO2max 변화값)·케이던스·파워·보폭 ④ 기록·대회(제목·줄 큰 글자). 잔디·차트 없음.
/// 없는 칸은 빼고 남은 칸이 넓어진다. 나 탭 카드와 공유 출력이 이 하나를 쓴다(인사이트 문장 없음).
struct PeriodRecapAllInOneCard: View {
    let recap: PeriodRecap
    let stats: SummaryPeriodStats
    var form: SummaryFormMetrics? = nil
    var miniMeImage: UIImage? = nil
    var theme: ShareTheme = .dark

    private var p: SummaryCardPalette { theme == .light ? .light : .dark }
    private var L: AppLanguage { AppLanguage.shared }

    var body: some View {
        SummaryCardChrome(title: stats.kind.title, subtitle: stats.kind.subtitle,
                          miniMeImage: miniMeImage, theme: theme) {
            // ① 총거리(큰 숫자) | 운동 시간·러닝·평균 페이스·최장
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(stats.distanceStr)
                            .font(.system(size: 72, weight: .black).width(.compressed))
                            .foregroundStyle(p.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(stats.distanceUnit)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(p.brand)
                    }
                    Text(L.s("총 거리", "TOTAL", ja: "総距離"))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(p.textSecondary)
                }
                .layoutPriority(1)

                VStack(alignment: .leading, spacing: 5) {
                    miniStat(stats.durationStr, L.s("운동 시간", "TIME", ja: "運動時間"), p.accentGold)
                    miniStat(L.s("\(stats.runCount)회", "\(stats.runCount)", ja: "\(stats.runCount)回"),
                             L.s("러닝", "RUNS", ja: "ラン"), p.brand)
                    if let pace = stats.avgPaceStr {
                        miniStat(pace, L.s("평균 페이스", "AVG PACE", ja: "平均ペース"), p.accentTeal)
                    }
                    if let longest = stats.longestStr {
                        miniStat(longest, L.s("최장", "LONGEST", ja: "最長"), p.textSecondary)
                    }
                }
                .padding(.top, 8)

                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)

            // ② 지난 기간 대비 · 올해 누적
            comparisonLine

            RecapDivider(theme: theme, top: 8, bottom: 6)

            // ③ 일별(연 = 월별) 거리 막대 | 러닝 데이터 값 — 유산소(VO2max 변화, 차트 없음)·케이던스·파워·보폭
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    RecapChartLabel(text: recap.isYear ? L.s("월별 거리", "MONTHLY DIST", ja: "月別距離")
                                                       : L.s("일별 거리", "DAILY DIST", ja: "日別距離"),
                                    unit: stats.useMiles ? "MI" : "KM", theme: theme, size: 10)
                    RecapDistanceBars(recap: recap, useMiles: stats.useMiles, theme: theme, height: 128)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                if recap.vo2 != nil || form?.hasAny == true {
                    Rectangle().fill(p.divider).frame(width: 0.5)
                    VStack(alignment: .leading, spacing: 10) {
                        if let v = recap.vo2 {
                            let delta = (v.delta * 10).rounded() / 10
                            formCell(delta == 0 ? "±0.0" : String(format: "%+.1f", delta),
                                     L.s("유산소", "VO2MAX", ja: "VO2MAX"), v.end, nil)
                        }
                        if let form { formCells(form) }
                    }
                    .padding(.top, 18)
                    .frame(width: 112, alignment: .leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            // ⑤ 기록 · 대회
            if !recap.prs.isEmpty || !recap.races.isEmpty {
                RecapDivider(theme: theme, top: 8, bottom: 6)
                RecapRecordRows(recap: recap, useMiles: stats.useMiles, theme: theme, maxRows: 2)
            }
            Spacer(minLength: 0)
        }
    }

    /// 지난 기간 대비(거리·횟수·페이스) + 올해 누적(이번 달만)
    @ViewBuilder
    private var comparisonLine: some View {
        let chips: [(String, Bool)] = [
            stats.distanceDeltaStr.map { ($0, stats.distanceDeltaIsUp) },
            stats.runCountDeltaStr.map { ($0, stats.runCount >= (stats.compRunCount ?? 0)) },
            stats.paceDeltaStr.map { ($0, $0.contains(L.s("빨라짐", "faster", ja: "速くなった"))) },
        ].compactMap { $0 }
        if !chips.isEmpty || stats.ytdStr != nil {
            HStack(spacing: 5) {
                if !chips.isEmpty {
                    Text(recap.isYear ? L.s("작년 대비", "VS LAST YEAR", ja: "昨年比") : L.s("지난달 대비", "VS LAST MONTH", ja: "先月比"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(p.textSecondary)
                    ForEach(chips.indices, id: \.self) { i in
                        let up = chips[i].1
                        let color = up ? p.positive : p.negative
                        Text(chips[i].0)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(color.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Spacer(minLength: 0)
                if let ytd = stats.ytdStr {
                    Text(ytd)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(p.brand)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func formCells(_ form: SummaryFormMetrics) -> some View {
        if let v = form.cadence {
            formCell("\(Int(v.rounded()))spm", L.s("케이던스", "CADENCE", ja: "ケイデンス"), v, form.prevCadence)
        }
        if let v = form.power {
            formCell("\(Int(v.rounded()))W", L.s("파워", "POWER", ja: "パワー"), v, form.prevPower)
        }
        if let v = form.strideLength {
            formCell(String(format: "%.2fm", v), L.s("보폭", "STRIDE", ja: "ストライド"), v, form.prevStrideLength)
        }
    }

    private func formCell(_ value: String, _ label: String, _ cur: Double, _ prev: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(p.textSecondary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(p.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let prev, prev != cur {
                let up = cur > prev
                Image(systemName: up ? "arrow.up" : "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(up ? p.positive : p.negative)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniStat(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color.opacity(0.85))
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
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
    var size: CGFloat = 8
    var color: Color? = nil

    var body: some View {
        let p: SummaryCardPalette = theme == .light ? .light : .dark
        HStack {
            Text(text)
                .font(.system(size: size, weight: .semibold))
                .tracking(size <= 8 ? 0.6 : 0.2)
                .foregroundStyle(color ?? p.textSecondary)
            Spacer()
            if let unit {
                Text(unit)
                    .font(.system(size: max(7, size - 1), weight: .medium))
                    .foregroundStyle(p.axisLabel)
            }
        }
        .padding(.bottom, 5)
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
            BarMark(x: .value("날", d.x), y: .value("거리", d.km), width: .fixed(isYear ? 18 : 7))
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
                            theme: theme, size: 13, color: p.textPrimary)
            VStack(spacing: 8) {
                ForEach(prs.indices, id: \.self) { prRow(prs[$0]) }
                ForEach(races.indices, id: \.self) { raceRow(races[$0]) }
            }
        }
    }

    private func prRow(_ pr: PeriodRecap.PR) -> some View {
        HStack(spacing: 6) {
            Text(pr.label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(p.textPrimary)
            Text(pr.isFirst ? L.s("첫 완주", "FIRST", ja: "初完走") : L.s("최고 기록", "PB", ja: "自己ベスト"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(p.brand)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(p.brand.opacity(0.14))
                .clipShape(Capsule())
            Spacer()
            timeAndDate(pr.duration, pr.date)
        }
    }

    private func raceRow(_ race: PeriodRecap.Race) -> some View {
        HStack(spacing: 6) {
            Text(race.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(raceDistance(race.distanceKm))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(p.textSecondary)
            Spacer()
            timeAndDate(race.duration, race.date)
        }
    }

    private func timeAndDate(_ duration: TimeInterval, _ date: Date) -> some View {
        HStack(spacing: 6) {
            Text(PeriodRecap.fmtDuration(duration))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(p.textPrimary)
            Text(dateStr(date))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(p.textSecondary)
                .frame(width: 40, alignment: .trailing)
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
