import SwiftUI
import Charts

// MARK: - Run Form Card

struct RunFormCardView: View {
    let activity: Activity
    var splits: [SplitData] = []
    var avgCadence: Int? = nil
    var avgStrideLength: Double? = nil
    var avgGroundContactTime: Double? = nil
    var avgVerticalOscillation: Double? = nil
    var baseline: RunningFormBaseline? = nil
    var workoutType: WorkoutType = .general

    // MARK: - Nested Types

    enum MetricDir { case cadence, stride, groundContact, verticalOsc }
    enum MetricStatus { case inRange, above, below, unknown }

    struct ChainChild: Identifiable {
        let id: Int
        let label: String
        let rawValue: Double
        let formatted: String
        let unit: String
        let stat: FormStat?
        let dir: MetricDir
        let isRef: Bool
    }

    struct FormSeries {
        struct Point: Identifiable {
            let id: Int   // 1-based km number
            let value: Double
            let outOfRange: Bool
        }
        let label: String
        let unit: String
        let points: [Point]
        let bandLo: Double?
        let bandHi: Double?
        let firstAvg: Double?
        let secondAvg: Double?
        let dir: MetricDir
        let lineColor: Color

        var yDomain: ClosedRange<Double> {
            var lo = points.map(\.value).min() ?? 0
            var hi = points.map(\.value).max() ?? 1
            if let b = bandLo { lo = min(lo, b) }
            if let b = bandHi { hi = max(hi, b) }
            let span = hi - lo
            let pad = span > 0 ? span * 0.10 : 1.0
            return (lo - pad)...(hi + pad)
        }
    }

    // MARK: - Computed

    private var bb: BandBaseline? { baseline?.baseline(for: activity) }
    private var isInterval: Bool { workoutType == .interval }
    private let lineColor = Color.white.opacity(0.20)

    private var fullSplits: [SplitData] {
        splits.filter { $0.distanceM >= 900 }
    }

    private var showTrendSection: Bool {
        guard !isInterval, fullSplits.count >= 3 else { return false }
        return fullSplits.contains {
            $0.avgCadence != nil || $0.avgStrideLength != nil || $0.avgGroundContactTime != nil
        }
    }

    private var formSeries: [FormSeries] {
        let L = AppLanguage.shared
        let fs = fullSplits
        guard fs.count >= 3 else { return [] }
        let mid = fs.count / 2
        let firstHalf  = Array(fs.prefix(mid))
        let secondHalf = Array(fs.suffix(from: mid))

        func avg(_ vals: [Double?]) -> Double? {
            let v = vals.compactMap { $0 }
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        let isOOB: (Double, FormStat?, MetricDir) -> Bool = { v, stat, dir in
            guard let stat else { return false }
            let rv = self.roundedDisplay(v, dir: dir)
            let lo = self.roundedDisplay(stat.lower, dir: dir)
            let hi = self.roundedDisplay(stat.upper, dir: dir)
            return rv < lo || rv > hi
        }

        var result: [FormSeries] = []

        // Cadence
        let cadPairs: [(Int, Double)] = fs.compactMap { s in s.avgCadence.map { (s.id, Double($0)) } }
        if !cadPairs.isEmpty {
            let stat = bb?.cadence
            result.append(FormSeries(
                label: L.s("케이던스", "Cadence"), unit: "spm",
                points: cadPairs.map { km, v in .init(id: km, value: v, outOfRange: isOOB(v, stat, .cadence)) },
                bandLo: stat.map { roundedDisplay($0.lower, dir: .cadence) },
                bandHi: stat.map { roundedDisplay($0.upper, dir: .cadence) },
                firstAvg:  avg(firstHalf.map  { $0.avgCadence.map(Double.init) }),
                secondAvg: avg(secondHalf.map { $0.avgCadence.map(Double.init) }),
                dir: .cadence, lineColor: Color(hex: "5CE5D5")
            ))
        }

        // Stride
        let slPairs: [(Int, Double)] = fs.compactMap { s in s.avgStrideLength.map { (s.id, $0) } }
        if !slPairs.isEmpty {
            let stat = bb?.strideLength
            result.append(FormSeries(
                label: L.s("보폭", "Stride"), unit: "m",
                points: slPairs.map { km, v in .init(id: km, value: v, outOfRange: isOOB(v, stat, .stride)) },
                bandLo: stat.map { roundedDisplay($0.lower, dir: .stride) },
                bandHi: stat.map { roundedDisplay($0.upper, dir: .stride) },
                firstAvg:  avg(firstHalf.map(\.avgStrideLength)),
                secondAvg: avg(secondHalf.map(\.avgStrideLength)),
                dir: .stride, lineColor: Color.white.opacity(0.78)
            ))
        }

        // GCT
        let gctPairs: [(Int, Double)] = fs.compactMap { s in s.avgGroundContactTime.map { (s.id, $0) } }
        if !gctPairs.isEmpty {
            let stat = bb?.groundContact
            result.append(FormSeries(
                label: L.s("지면접촉", "GCT"), unit: "ms",
                points: gctPairs.map { km, v in .init(id: km, value: v, outOfRange: isOOB(v, stat, .groundContact)) },
                bandLo: stat.map { roundedDisplay($0.lower, dir: .groundContact) },
                bandHi: stat.map { roundedDisplay($0.upper, dir: .groundContact) },
                firstAvg:  avg(firstHalf.map(\.avgGroundContactTime)),
                secondAvg: avg(secondHalf.map(\.avgGroundContactTime)),
                dir: .groundContact, lineColor: Color(hex: "FC9A56")
            ))
        }

        return result
    }

    private var chainChildren: [ChainChild] {
        let L = AppLanguage.shared
        var items: [ChainChild] = []
        var n = 0
        if let sl = avgStrideLength {
            items.append(ChainChild(id: n, label: L.s("보폭", "Stride"),
                rawValue: sl, formatted: String(format: "%.2f", sl), unit: "m",
                stat: bb?.strideLength, dir: .stride, isRef: false)); n += 1
        }
        if let gct = avgGroundContactTime {
            items.append(ChainChild(id: n, label: L.s("지면접촉", "GCT"),
                rawValue: gct, formatted: String(format: "%.0f", gct), unit: "ms",
                stat: bb?.groundContact, dir: .groundContact, isRef: false)); n += 1
        }
        if let vo = avgVerticalOscillation {
            items.append(ChainChild(id: n, label: L.s("수직진폭", "Vert Osc"),
                rawValue: vo, formatted: String(format: "%.1f", vo), unit: "cm",
                stat: bb?.verticalOsc, dir: .verticalOsc, isRef: true))
        }
        return items
    }

    // MARK: - Display Rounding Helpers

    private func roundedDisplay(_ v: Double, dir: MetricDir) -> Double {
        switch dir {
        case .cadence, .groundContact: return v.rounded()
        case .stride:                  return (v * 100).rounded() / 100
        case .verticalOsc:             return (v * 10).rounded() / 10
        }
    }

    private func metricFmt(_ v: Double, dir: MetricDir) -> String {
        switch dir {
        case .cadence:       return String(format: "%.0f", v)
        case .stride:        return String(format: "%.2f", v)
        case .groundContact: return String(format: "%.0f", v)
        case .verticalOsc:   return String(format: "%.1f", v)
        }
    }

    private func metricStatus(rawValue: Double, stat: FormStat?, dir: MetricDir) -> MetricStatus {
        guard let stat else { return .unknown }
        let rv = roundedDisplay(rawValue, dir: dir)
        let lo = roundedDisplay(stat.lower, dir: dir)
        let hi = roundedDisplay(stat.upper, dir: dir)
        if rv >= lo && rv <= hi { return .inRange }
        return rv > hi ? .above : .below
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topSummary
            divider
            causalChain
            divider
            if showTrendSection {
                splitFormTrendSection
                divider
            }
            placeholderSection(
                title: AppLanguage.shared.s("주법 판정", "Running Form"),
                icon: "figure.run"
            )
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            logChain()
            logTrend()
        }
    }

    // MARK: - Top Summary

    private var topSummary: some View {
        let km = activity.distance / 1000
        let kmStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(kmStr)
                    .font(cardNumFont(40))
                    .tracking(-1.6)
                Text("km")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "8A8F99"))
            }
            .foregroundStyle(Color.white)
            HStack(spacing: 0) {
                KPICell(label: AppLanguage.shared.s("시간", "Time"),
                        value: activity.formattedDuration)
                kpiSep
                KPICell(label: AppLanguage.shared.s("페이스", "Pace"),
                        value: activity.formattedPace ?? "--'--\"")
                if let cad = avgCadence {
                    kpiSep
                    KPICell(label: AppLanguage.shared.s("케이던스", "Cadence"),
                            value: "\(cad)", unit: "spm",
                            color: Color(hex: "5CE5D5"))
                }
                if let sl = avgStrideLength {
                    kpiSep
                    KPICell(label: AppLanguage.shared.s("보폭", "Stride"),
                            value: String(format: "%.2f", sl), unit: "m",
                            color: Color.white)
                }
            }
        }
    }

    // MARK: - Causal Chain

    @ViewBuilder
    private var causalChain: some View {
        let L = AppLanguage.shared
        let children = chainChildren
        VStack(alignment: .leading, spacing: 0) {
            if let cad = avgCadence {
                rootNodeView(label: L.s("케이던스", "Cadence"),
                             rawValue: Double(cad), formatted: "\(cad)", unit: "spm",
                             stat: bb?.cadence, dir: .cadence)
            }
            ForEach(children) { child in
                connectorView
                childNodeView(child: child)
            }
            if let paceStr = activity.formattedPace {
                resultArrowView
                resultNodeView(label: L.s("페이스", "Pace"), value: paceStr)
            }
            if let sentence = narrative {
                Color.clear.frame(height: 10)
                Text(sentence)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Chain Node Views

    private func rootNodeView(label: String, rawValue: Double, formatted: String,
                              unit: String, stat: FormStat?, dir: MetricDir) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.50))
                Text(formatted).font(cardNumFont(22)).foregroundStyle(Color.white)
                Text(unit).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.45))
            }
            if !isInterval, let stat { rangeRow(rawValue: rawValue, stat: stat, dir: dir) }
        }
    }

    private func childNodeView(child: ChainChild) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: 14)
                .overlay {
                    Rectangle().fill(lineColor).frame(width: 0.5).frame(width: 14, alignment: .center)
                }
            Color.clear.frame(width: 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(child.label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.50))
                    if child.isRef {
                        Text(AppLanguage.shared.s("(참고)", "(ref)"))
                            .font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.30))
                    }
                    Text(child.formatted)
                        .font(cardNumFont(20))
                        .foregroundStyle(child.isRef ? Color.white.opacity(0.50) : Color.white)
                    Text(child.unit).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.45))
                }
                if !child.isRef && !isInterval, let stat = child.stat {
                    rangeRow(rawValue: child.rawValue, stat: stat, dir: child.dir)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectorView: some View {
        HStack(spacing: 0) {
            ZStack {
                Rectangle().fill(lineColor).frame(width: 0.5, height: 14).frame(width: 14, alignment: .center)
                Rectangle().fill(lineColor).frame(width: 8, height: 0.5).frame(width: 14, alignment: .trailing)
            }
            .frame(width: 14, height: 14)
            Spacer()
        }
    }

    private var resultArrowView: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .top) {
                Rectangle().fill(lineColor).frame(width: 0.5, height: 12).frame(width: 14, alignment: .center)
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 8, weight: .thin)).foregroundStyle(lineColor)
                    .frame(width: 14, alignment: .center).padding(.top, 10)
            }
            .frame(width: 14, height: 18)
            Spacer()
        }
    }

    private func resultNodeView(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.50))
            Text(value).font(cardNumFont(26)).foregroundStyle(Theme.violet)
        }
    }

    // MARK: - Range Row

    private func rangeRow(rawValue: Double, stat: FormStat, dir: MetricDir) -> some View {
        let lo = roundedDisplay(stat.lower, dir: dir)
        let hi = roundedDisplay(stat.upper, dir: dir)
        let rv = roundedDisplay(rawValue, dir: dir)
        let loStr = metricFmt(lo, dir: dir), hiStr = metricFmt(hi, dir: dir)
        let (badgeText, badgeColor) = badgeInfo(rv: rv, lo: lo, hi: hi, dir: dir)
        return HStack(spacing: 5) {
            Text(AppLanguage.shared.s("평소 \(loStr)–\(hiStr)", "Typical \(loStr)–\(hiStr)"))
                .font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.38))
            if let b = badgeText, let c = badgeColor {
                Text(b).font(.system(size: 9, weight: .medium)).foregroundStyle(c)
            }
        }
    }

    private func badgeInfo(rv: Double, lo: Double, hi: Double, dir: MetricDir) -> (String?, Color?) {
        let L = AppLanguage.shared
        let green = Color(hex: "7FD98A"); let muted = Color.white.opacity(0.75)
        if rv >= lo && rv <= hi { return (L.s("✓ 평소 범위", "✓ Typical"), Color.white.opacity(0.50)) }
        let above = rv > hi
        switch dir {
        case .cadence:      return above ? (L.s("↑ 평소보다 높음", "↑ Above typical"), green)  : (L.s("↓ 평소보다 낮음", "↓ Below typical"), muted)
        case .stride:       return above ? (L.s("↑ 평소보다 큼",   "↑ Above typical"), muted)  : (L.s("↓ 평소보다 작음", "↓ Below typical"), muted)
        case .groundContact:return above ? (L.s("↑ 평소보다 길음", "↑ Above typical"), muted)  : (L.s("↓ 평소보다 짧음", "↓ Below typical"), green)
        case .verticalOsc:  return (nil, nil)
        }
    }

    // MARK: - Split Form Trend

    @ViewBuilder
    private var splitFormTrendSection: some View {
        let all = formSeries
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(all.enumerated()), id: \.offset) { idx, s in
                    if idx > 0 {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
                    }
                    formSeriesRow(s)
                }
            }
        }
    }

    private func formSeriesRow(_ s: FormSeries) -> some View {
        let fs = fullSplits
        let n = fs.last?.id ?? 1
        let mid = fs.count / 2
        let midX = Double(mid) + 0.5
        let showOdd = n > 8
        let xVals: [Double] = showOdd
            ? Array(stride(from: 1.0, through: Double(n), by: 2.0))
            : (1...max(1, n)).map(Double.init)

        return VStack(alignment: .leading, spacing: 5) {
            // Header: metric name + change indicator
            HStack(alignment: .firstTextBaseline) {
                Text(s.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.50))
                Spacer()
                if let f = s.firstAvg, let sec = s.secondAvg {
                    trendChangeBadge(dir: s.dir, unit: s.unit, firstAvg: f, secondAvg: sec)
                }
            }

            // Sparkline chart
            Chart {
                // Normal-range band
                if let lo = s.bandLo, let hi = s.bandHi {
                    RectangleMark(
                        xStart: .value("", 0.5),
                        xEnd: .value("", Double(n) + 0.5),
                        yStart: .value("", lo),
                        yEnd: .value("", hi)
                    )
                    .foregroundStyle(Color.white.opacity(0.08))
                }

                // Midpoint divider
                RuleMark(x: .value("", midX))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                    .foregroundStyle(Color.white.opacity(0.15))

                // Line
                ForEach(s.points) { pt in
                    LineMark(
                        x: .value("km", Double(pt.id)),
                        y: .value("val", pt.value)
                    )
                    .foregroundStyle(s.lineColor)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                }

                // In-range small dots
                ForEach(s.points.filter { !$0.outOfRange }) { pt in
                    PointMark(x: .value("km", Double(pt.id)), y: .value("val", pt.value))
                        .foregroundStyle(s.lineColor.opacity(0.45))
                        .symbolSize(12)
                }

                // Out-of-range: white halo then colored inner
                ForEach(s.points.filter(\.outOfRange)) { pt in
                    PointMark(x: .value("km", Double(pt.id)), y: .value("val", pt.value))
                        .foregroundStyle(Color.white)
                        .symbolSize(64)
                }
                ForEach(s.points.filter(\.outOfRange)) { pt in
                    PointMark(x: .value("km", Double(pt.id)), y: .value("val", pt.value))
                        .foregroundStyle(s.lineColor)
                        .symbolSize(32)
                }
            }
            .chartYScale(domain: s.yDomain)
            .chartXScale(domain: 0.5...(Double(n) + 0.5))
            .chartXAxis {
                AxisMarks(values: xVals) { val in
                    AxisValueLabel(centered: false) {
                        if let v = val.as(Double.self) {
                            Text("\(Int(v))")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.white.opacity(0.30))
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 52)
        }
    }

    private func trendChangeBadge(dir: MetricDir, unit: String, firstAvg: Double, secondAvg: Double) -> some View {
        let diff = secondAvg - firstAvg
        let fmtNum: (Double) -> String = { v in metricFmt(v, dir: dir) }
        let diffUnit = dir == .groundContact ? "ms" : ""
        let sign: String = diff > 0.0005 ? "+" : diff < -0.0005 ? "−" : "±"
        let label = "\(fmtNum(firstAvg)) → \(fmtNum(secondAvg)) (\(sign)\(fmtNum(abs(diff)))\(diffUnit))"
        let green = Color(hex: "7FD98A")
        let muted = Color.white.opacity(0.70)
        let color: Color
        switch dir {
        case .cadence:       color = diff > 0.0005 ? green : muted
        case .groundContact: color = diff < -0.0005 ? green : muted
        default:             color = muted
        }
        return Text(label)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(color)
    }

    // MARK: - Narrative

    private var narrative: String? {
        let L = AppLanguage.shared
        guard let cad = avgCadence else { return nil }
        let cadD = Double(cad)
        let paceStr = activity.formattedPace ?? "--"
        let cadStr  = "\(cad)"
        let slStr   = avgStrideLength.map { String(format: "%.2f", $0) }
        let gctStr  = avgGroundContactTime.map { String(format: "%.0f", $0) }

        if cadD < 160 {
            return L.s("보폭이 큰 편이에요. 발걸음을 조금 빠르게 하면 무릎 부담이 줄어요.",
                        "Your stride is on the long side. A slightly faster cadence can reduce knee stress.")
        }
        guard bb != nil else {
            return slStr.map { L.s("케이던스 \(cadStr)spm으로 보폭 \($0)m를 만들어 \(paceStr) 페이스가 나왔어요.",
                                   "A cadence of \(cadStr) spm and \($0) m stride produced a \(paceStr) pace.") }
                ?? L.s("케이던스 \(cadStr)spm으로 \(paceStr) 페이스가 나왔어요.",
                        "A cadence of \(cadStr) spm produced a \(paceStr) pace.")
        }

        let cadStatus = metricStatus(rawValue: cadD, stat: bb?.cadence, dir: .cadence)
        let gctStatus: MetricStatus = avgGroundContactTime.map {
            metricStatus(rawValue: $0, stat: bb?.groundContact, dir: .groundContact)
        } ?? .unknown

        if let g = gctStr {
            if gctStatus == .below {
                return cadStatus == .inRange
                    ? L.s("평소 리듬대로 \(cadStr)spm을 유지하면서 지면접촉이 \(g)ms로 짧았어요. 탄력 있게 뛰었어요.",
                           "Holding your usual \(cadStr) spm rhythm, ground contact stayed short at \(g) ms — a springy run.")
                    : L.s("발걸음이 평소보다 빠르게 돌아 지면접촉이 \(g)ms로 짧아졌어요. 효율적인 주법이에요.",
                           "A faster-than-usual cadence shortened ground contact to \(g) ms — an efficient form.")
            }
            if gctStatus == .above {
                return L.s("지면 접촉 시간이 평소보다 길었어요. 발을 좀 더 빠르게 들어올리면 효율이 오를 수 있어요.",
                            "Ground contact time was longer than usual. A quicker lift-off may improve efficiency.")
            }
        }
        if cadStatus == .below {
            let sfx = slStr.map { " \($0)m" } ?? ""
            return L.s("발걸음이 평소보다 느려 보폭\(sfx)으로 페이스를 만들었어요. 무릎 부담이 조금 더 클 수 있어요.",
                        "A slower-than-usual cadence meant relying more on stride length. This can increase knee load.")
        }
        if cadStatus == .above {
            return L.s("발걸음이 평소보다 빨랐어요. 작은 보폭으로 페이스를 만들어 관절에 부담이 적은 주법이에요.",
                        "Cadence was above your usual pace. Smaller stride, less joint load — an efficient run.")
        }
        return slStr.map { L.s("케이던스 \(cadStr)spm, 보폭 \($0)m로 평소와 비슷한 \(paceStr) 페이스가 나왔어요.",
                               "Cadence \(cadStr) spm and stride \($0) m produced the usual \(paceStr) pace.") }
            ?? L.s("케이던스 \(cadStr)spm으로 평소와 비슷하게 \(paceStr) 페이스를 달렸어요.",
                    "A cadence of \(cadStr) spm produced the usual \(paceStr) pace.")
    }

    // MARK: - Log

    private func logChain() {
        #if DEBUG
        func pf(_ s: Double) -> String { String(format: "%d'%02d\"", Int(s) / 60, Int(s) % 60) }
        func rng(_ s: FormStat?, _ fmt: String) -> String {
            guard let s else { return "기준없음" }
            return String(format: "\(fmt)–\(fmt)(폭\(fmt))", s.lower, s.upper, s.upper - s.lower)
        }
        let cStr  = avgCadence.map { "\($0)" } ?? "-"
        let slStr = avgStrideLength.map  { String(format: "%.2f", $0) } ?? "-"
        let gctStr = avgGroundContactTime.map { String(format: "%.0f", $0) } ?? "-"
        let voStr  = avgVerticalOscillation.map { String(format: "%.1f", $0) } ?? "-"
        let pace   = activity.paceSecPerKm.map { pf($0) } ?? "--"
        print("[폼:사슬] C=\(cStr)(\(rng(bb?.cadence, "%.0f"))) 보폭=\(slStr)(\(rng(bb?.strideLength, "%.2f")))")
        print("         GCT=\(gctStr)(\(rng(bb?.groundContact, "%.0f"))) VO=\(voStr) 페이스=\(pace)")
        print("         → \"\(narrative ?? "-")\"")
        #endif
    }

    private func logTrend() {
        #if DEBUG
        let all = formSeries
        guard !all.isEmpty else { return }
        var line = "[폼:추이] splits=\(fullSplits.count)"
        for s in all {
            if let f = s.firstAvg, let sec = s.secondAvg {
                let diff = sec - f
                let sign = diff > 0 ? "+" : ""
                line += " \(s.label) \(metricFmt(f, dir: s.dir))→\(metricFmt(sec, dir: s.dir))(\(sign)\(metricFmt(diff, dir: s.dir)))"
            }
        }
        let oobParts = all.compactMap { s -> String? in
            let n = s.points.filter(\.outOfRange).count
            return n > 0 ? "\(s.label) \(n)개" : nil
        }
        line += " | 띠밖 지점: " + (oobParts.isEmpty ? "없음" : oobParts.joined(separator: " "))
        print(line)
        #endif
    }

    // MARK: - Helpers

    private var kpiSep: some View {
        Rectangle().fill(Color.white.opacity(0.10)).frame(width: 0.5, height: 40)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
    }

    @ViewBuilder
    private func placeholderSection(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.25))
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }
}
