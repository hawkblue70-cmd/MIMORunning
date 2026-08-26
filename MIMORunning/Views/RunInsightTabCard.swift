import SwiftUI
import Charts
import SwiftData

// MARK: - Tab Enum

enum InsightTabKind: CaseIterable, Hashable {
    case rhythm, performance

    var title: String {
        AppLanguage.shared.s(
            self == .rhythm ? "리듬" : "퍼포먼스",
            self == .rhythm ? "Rhythm" : "Performance"
        )
    }
}

// MARK: - Insight Colors

private enum IC {
    static let green      = Color(hex: "5CE08A")
    static let greenBg    = Color(hex: "5CE08A").opacity(0.13)
    static let greenText  = Color(hex: "BFEFD0")
    static let violet     = Color(hex: "8B7FF0")
    static let violetBg   = Color(hex: "7C5CFC").opacity(0.15)
    static let violetText = Color(hex: "D5CEFF")
    static let label      = Color(hex: "8A8F99")
    static let hrRed      = Color(hex: "FF6B6B")
    static let cadCyan    = Color(hex: "5CE5D5")

    static let zoneColors: [Color] = [
        Color(hex: "4C8DFF"), Color(hex: "5CE08A"),
        Color(hex: "F5C542"), Color(hex: "FF9A3C"), Color(hex: "FF5247"),
    ]
    static func zone(_ id: Int) -> Color { zoneColors[min(max(id - 1, 0), 4)] }
}

// MARK: - Shared Subviews

private struct KPICell: View {
    let label: String
    let value: String
    var unit: String? = nil
    var color: Color = .white
    var context: String? = nil

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 15, weight: .medium)).foregroundStyle(color)
                if let u = unit {
                    Text(u).font(.system(size: 10)).foregroundStyle(IC.label)
                }
            }
            Text(label).font(.system(size: 8.5)).foregroundStyle(IC.label)
            if let ctx = context {
                Text(ctx).font(.system(size: 8)).foregroundStyle(IC.green)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ZoneDonutView: View {
    let zones: [HRZoneData]

    private let thickness: CGFloat = 10

    var body: some View {
        let visible = zones.filter { $0.fraction > 0.01 }
        let total   = max(1e-9, visible.map(\.fraction).reduce(0, +))
        let dominant = visible.max(by: { $0.fraction < $1.fraction })
        ZStack {
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = size.width / 2 - thickness / 2
                var bg = Path()
                bg.addArc(center: center, radius: r,
                          startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
                ctx.stroke(bg, with: .color(.white.opacity(0.08)),
                           style: StrokeStyle(lineWidth: thickness))
                var startDeg: Double = -90
                for zone in visible {
                    let sweep = 360 * zone.fraction / total
                    var arc = Path()
                    arc.addArc(center: center, radius: r,
                               startAngle: .degrees(startDeg),
                               endAngle:   .degrees(startDeg + sweep),
                               clockwise: false)
                    ctx.stroke(arc, with: .color(IC.zone(zone.id)),
                               style: StrokeStyle(lineWidth: thickness, lineCap: .butt))
                    startDeg += sweep
                }
            }
            if let dom = dominant {
                let pct = Int((dom.fraction / total * 100).rounded())
                VStack(spacing: 1) {
                    Text("\(pct)%")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(IC.zone(dom.id))
                    Text("Zone \(dom.id)")
                        .font(.system(size: 7.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }
}

private struct CadenceTrackView: View {
    let cadence: Int

    private let trackMin: CGFloat = 130
    private let trackMax: CGFloat = 200
    private let recMin:   CGFloat = 160
    private let recMax:   CGFloat = 175

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let range = trackMax - trackMin
            let bandX = w * (recMin - trackMin) / range
            let bandW = w * (recMax - recMin) / range
            let mfrac = max(0, min(1, (CGFloat(cadence) - trackMin) / range))
            let mX = w * mfrac

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(IC.green.opacity(0.32))
                    .frame(width: bandW, height: 10)
                    .offset(x: bandX)
                // shadow outline
                Circle()
                    .fill(Theme.cardBackground)
                    .frame(width: 13, height: 13)
                    .offset(x: max(0, min(w - 13, mX - 6.5)))
                Circle()
                    .fill(IC.cadCyan)
                    .frame(width: 11, height: 11)
                    .offset(x: max(0, min(w - 11, mX - 5.5)))
            }
        }
        .frame(height: 13)
    }
}

private struct CadenceRPMGaugeView: View {
    let cadence: Int

    private let trackMin = 140.0
    private let trackMax = 200.0
    private let recMin   = 160.0
    private let recMax   = 180.0
    private let thickness: CGFloat = 10

    // 140 → 180°(9시), 200 → 360°(3시), 상단 반원 시계방향
    private func angle(for value: Double) -> Double {
        let clamped = max(trackMin, min(trackMax, value))
        return 180 + (clamped - trackMin) / (trackMax - trackMin) * 180
    }

    var body: some View {
        let L = AppLanguage.shared
        VStack(alignment: .leading, spacing: 2) {
            Canvas { ctx, size in
                let cx = size.width / 2
                let cy = size.height - 2
                let center = CGPoint(x: cx, y: cy)
                let r = cx - thickness / 2 - 1

                // 배경 아크 (전체 반원)
                var bg = Path()
                bg.addArc(center: center, radius: r,
                          startAngle: .degrees(180), endAngle: .degrees(360),
                          clockwise: true)
                ctx.stroke(bg, with: .color(.white.opacity(0.09)),
                           style: StrokeStyle(lineWidth: thickness, lineCap: .round))

                // 권장 밴드 (160–180 spm)
                var band = Path()
                band.addArc(center: center, radius: r,
                            startAngle: .degrees(angle(for: recMin)),
                            endAngle:   .degrees(angle(for: recMax)),
                            clockwise: true)
                ctx.stroke(band, with: .color(Color(hex: "5CE08A").opacity(0.30)),
                           style: StrokeStyle(lineWidth: thickness, lineCap: .butt))

                // 현재값 아크
                let valEnd = angle(for: Double(cadence))
                var val = Path()
                val.addArc(center: center, radius: r,
                           startAngle: .degrees(180), endAngle: .degrees(valEnd),
                           clockwise: true)
                ctx.stroke(val, with: .color(Color(hex: "5CE5D5")),
                           style: StrokeStyle(lineWidth: thickness, lineCap: .round))

                // 바늘
                let needleLen = r - 4
                let rad = valEnd * .pi / 180.0
                let tip = CGPoint(x: center.x + needleLen * CGFloat(cos(rad)),
                                  y: center.y + needleLen * CGFloat(sin(rad)))
                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: tip)
                ctx.stroke(needle, with: .color(.white.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

                // 중심 원
                let dotR: CGFloat = 4
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR,
                                          width: dotR * 2, height: dotR * 2)),
                    with: .color(.white)
                )

                // 중앙 값 텍스트
                ctx.draw(
                    Text("\(cadence)")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color(hex: "5CE5D5")),
                    at: CGPoint(x: cx, y: cy - 24),
                    anchor: .center
                )
            }
            .frame(width: 110, height: 62)

            // 좌우 눈금
            HStack {
                Text("140").font(.system(size: 7.5)).foregroundStyle(Color(hex: "6B7280"))
                Spacer()
                Text("200").font(.system(size: 7.5)).foregroundStyle(Color(hex: "6B7280"))
            }
            .frame(width: 110)
            .padding(.top, 1)

            // 하단 메모
            Text(L.s("권장 160–180", "Rec. 160–180"))
                .font(.system(size: 8.5))
                .foregroundStyle(Color(hex: "8A8F99"))
        }
    }
}

private struct CadenceBar: Identifiable {
    let id: Int
    let value: Double
    let isOutlier: Bool
}

private struct CadenceEqualizerView: View {
    let bars: [CadenceBar]
    let avgCadence: Double
    let totalKm: Double

    private var normRange: (min: Double, range: Double) {
        let vals = bars.filter { !$0.isOutlier }.map(\.value)
        guard !vals.isEmpty else { return (avgCadence * 0.9, 20) }
        let lo = vals.min()!, hi = vals.max()!
        var r = hi - lo
        if r < 15 { r = 15 }
        return ((lo + hi) / 2 - r / 2, r)
    }

    private var steadyRatio: Double {
        let valid = bars.filter { !$0.isOutlier }
        guard !valid.isEmpty else { return 0 }
        let avg = avgCadence
        let steady = valid.filter { abs($0.value - avg) / max(1, avg) <= 0.05 }.count
        return Double(steady) / Double(valid.count)
    }

    var body: some View {
        let L = AppLanguage.shared
        let (nMin, nRange) = normRange
        VStack(alignment: .leading, spacing: 5) {
            // Header row
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.0f", avgCadence))
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(IC.cadCyan)
                Text("spm").font(.system(size: 9)).foregroundStyle(IC.label)
                Spacer()
                if steadyRatio >= 0.70 {
                    Text(L.s("일정하게 유지", "Steady"))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(IC.green)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(IC.green.opacity(0.16))
                        .clipShape(Capsule())
                }
            }
            // Equalizer bars
            Canvas { ctx, size in
                guard !bars.isEmpty else { return }
                let n = bars.count
                let gap: CGFloat = 7
                let barW = max(1, (size.width - gap * CGFloat(n - 1)) / CGFloat(n))
                func barH(_ v: Double) -> CGFloat {
                    let norm = max(0, min(1, (v - nMin) / max(1, nRange)))
                    return norm * 38 + 10
                }
                // background band avg ±5%
                let bandTopY = size.height - barH(avgCadence * 1.05)
                let bandBotY = size.height - barH(avgCadence * 0.95)
                if bandBotY > bandTopY {
                    ctx.fill(
                        Path(CGRect(x: 0, y: bandTopY,
                                   width: size.width, height: bandBotY - bandTopY)),
                        with: .color(Color(hex: "5CE08A").opacity(0.07))
                    )
                }
                // bars
                for (i, bar) in bars.enumerated() {
                    let x = CGFloat(i) * (barW + gap)
                    let displayVal = bar.isOutlier ? nMin : bar.value
                    let h = barH(displayVal)
                    let inBand = !bar.isOutlier &&
                        abs(bar.value - avgCadence) / max(1, avgCadence) <= 0.05
                    let col: Color = bar.isOutlier
                        ? Color(hex: "4A5560")
                        : inBand ? Color(hex: "5CE5D5") : Color(hex: "5CE5D5").opacity(0.45)
                    ctx.fill(
                        Path(roundedRect: CGRect(x: x, y: size.height - h, width: barW, height: h),
                             cornerRadius: 2.5),
                        with: .color(col)
                    )
                }
            }
            .frame(height: 52)
            // Bottom labels
            HStack {
                Text(L.s("시작", "Start"))
                    .font(.system(size: 7.5)).foregroundStyle(Color(hex: "6B7280"))
                Spacer()
                if totalKm > 10 {
                    let perBar = totalKm / Double(max(1, bars.count))
                    Text(L.s("구간당 \(String(format: "%.1f", perBar))km",
                             "\(String(format: "%.1f", perBar))km/bar"))
                        .font(.system(size: 7.5)).foregroundStyle(Color(hex: "6B7280"))
                    Spacer()
                }
                Text(L.s("종료", "End"))
                    .font(.system(size: 7.5)).foregroundStyle(Color(hex: "6B7280"))
            }
        }
    }
}

private struct VO2GaugeView: View {
    let fi: RunInsightEngine.VO2FitnessInfo
    let vo2: Double
    var prevVo2: Double? = nil

    private let segColors: [Color] = [
        Color.white.opacity(0.10), Color.white.opacity(0.14),
        Color(hex: "5CE08A").opacity(0.30), Color(hex: "5CE08A"),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let segW = (w - 6) / 4

            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(segColors[i])
                            .frame(width: segW, height: 7)
                    }
                }
                if let pv = prevVo2 {
                    let px = xPos(vo2: pv, w: w)
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 9, height: 9)
                        .offset(x: max(0, min(w - 9, px - 4.5)))
                }
                let cx = xPos(vo2: vo2, w: w)
                Circle()
                    .fill(Theme.cardBackground)
                    .frame(width: 13, height: 13)
                    .offset(x: max(0, min(w - 13, cx - 6.5)))
                Circle()
                    .fill(IC.green)
                    .frame(width: 11, height: 11)
                    .offset(x: max(0, min(w - 11, cx - 5.5)))
            }
        }
        .frame(height: 13)
    }

    private func xPos(vo2: Double, w: CGFloat) -> CGFloat {
        let highMax = max(55, fi.normHigh + (fi.normHigh - fi.normAboveAvg))
        let bounds = [0.0, fi.normBelowAvg, fi.normAboveAvg, fi.normHigh, highMax]
        for i in 0..<4 {
            let lo = bounds[i], hi = bounds[i + 1]
            if vo2 <= hi || i == 3 {
                let frac = hi > lo ? min(1.0, max(0.0, (vo2 - lo) / (hi - lo))) : 0.0
                return CGFloat((Double(i) + frac) / 4.0) * w
            }
        }
        return w * 0.98
    }
}

private struct MetricRow: View {
    let label: String
    let value: String
    var context: String? = nil
    var contextColor: Color = IC.label

    var body: some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(IC.label)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                if let ctx = context {
                    Text(ctx).font(.system(size: 9)).foregroundStyle(contextColor)
                }
            }
        }
    }
}

// MARK: - RunInsightTabCard (entry point)

struct RunInsightTabCard: View {
    let activity: Activity
    var detail: ActivityDetail? = nil
    var history: [Activity] = []
    var age: Int? = nil
    var isMale: Bool? = nil
    var hrZones: [HRZoneData] = []
    let insights: [RunInsight]
    var workoutTypeLabel: String? = nil
    var isAutoDetected: Bool = false
    var workoutTypeFn: ((UUID) -> WorkoutType?)? = nil
    var isBackfilling: Bool = false
    var cadenceSeries: [(offset: TimeInterval, value: Double)] = []

    @State private var tab: InsightTabKind = .rhythm
    @State private var showExport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            tabPicker
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            cardContent
                .padding(.horizontal, 16)
            disclaimer
                .padding(.horizontal, 16)
                .padding(.top, 10)
        }
        .sheet(isPresented: $showExport) {
            InsightExportSheet(
                activity: activity, detail: detail, history: history,
                age: age, isMale: isMale, hrZones: hrZones,
                insights: insights, startTab: tab,
                workoutTypeFn: workoutTypeFn,
                cadenceSeries: cadenceSeries
            )
        }
    }

    private var sectionHeader: some View {
        let L = AppLanguage.shared
        let base = L.s("오늘의 러닝", "Today's Run")
        let title = workoutTypeLabel.map { "\(base) · \($0)" } ?? base
        return HStack {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .medium))
                if isAutoDetected {
                    Text(L.s("자동 감지", "Auto"))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { showExport = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up.on.square")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L.s("내보내기", "Export"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.violet)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.violet.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 6) {
            ForEach(InsightTabKind.allCases, id: \.self) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { tab = t }
                } label: {
                    Text(t.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tab == t ? Theme.violet : Color.white.opacity(0.50))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(tab == t ? Theme.violet.opacity(0.22) : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        if tab == .rhythm {
            RhythmInsightCard(
                activity: activity, detail: detail,
                history: history, age: age, isMale: isMale,
                hrZones: hrZones, insights: insights,
                cadenceSeries: cadenceSeries
            )
        } else {
            PerformanceInsightCard(
                activity: activity, detail: detail,
                history: history, age: age, isMale: isMale,
                insights: insights,
                workoutTypeFn: workoutTypeFn,
                isBackfilling: isBackfilling
            )
        }
    }

    private var disclaimer: some View {
        let L = AppLanguage.shared
        return Text(L.s(
            "참고용 피트니스 인사이트입니다. 연령대 평균과 추정 최대심박은 개인차가 큰 추정치이며 의학적 판단이 아니에요. 유산소 피트니스 기준은 FRIEND(Fitness Registry and Importance of Exercise National Database)를 따릅니다.",
            "Reference-only fitness insights. Age-group norms and estimated max HR are rough estimates with high individual variation and are not medical advice. Cardio fitness norms follow FRIEND (Fitness Registry and Importance of Exercise National Database)."
        ))
        .font(.system(size: 9.5))
        .foregroundStyle(Color.secondary)
        .lineSpacing(2)
    }
}

// MARK: - Rhythm Card

private struct RhythmInsightCard: View {
    let activity: Activity
    var detail: ActivityDetail? = nil
    var history: [Activity] = []
    var age: Int? = nil
    var isMale: Bool? = nil
    var hrZones: [HRZoneData] = []
    let insights: [RunInsight]
    var cadenceSeries: [(offset: TimeInterval, value: Double)] = []

    var body: some View {
        let hasZones = !hrZones.filter({ $0.fraction > 0.01 }).isEmpty
        return VStack(alignment: .leading, spacing: 14) {
            heroSection
            divider
            kpiRow
            if hasZones {
                divider
                zoneDonutSection        // 도넛 + 판정 + RPM 게이지 (우측)
            } else if let cad = detail?.avgCadence {
                divider
                CadenceRPMGaugeView(cadence: cad)   // 존 없을 때 전체 폭 게이지
            }
            if let info = vo2Info, let vo2 = detail?.vo2Max {
                divider
                cardioSection(info: info, vo2: vo2)
            }
            if let line = oneLiner {
                divider
                oneLiner(text: line, bg: IC.greenBg, fg: IC.greenText, accent: IC.green)
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // buildCadenceBars — 퍼포먼스 카드에서 CadenceEqualizerView 재사용 예정
    func buildCadenceBars(
        from samples: [(offset: TimeInterval, value: Double)]
    ) -> [CadenceBar] {
        guard samples.count >= 5 else { return [] }
        let target = min(20, samples.count)
        var bars: [CadenceBar] = []
        for i in 0..<target {
            let lo = i * samples.count / target
            let hi = (i + 1) * samples.count / target
            let chunk = samples[lo..<hi].map(\.value).sorted()
            let mid = chunk.count / 2
            let median = chunk.count % 2 == 0 && chunk.count > 1
                ? (chunk[mid - 1] + chunk[mid]) / 2
                : chunk[mid]
            bars.append(CadenceBar(id: i, value: median, isOutlier: median < 100))
        }
        return bars
    }

    private var heroSection: some View {
        let km = activity.distance / 1000
        let kmStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
        return VStack(alignment: .leading, spacing: 3) {
            Text(AppLanguage.shared.s("오늘", "Today"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(IC.label)
                .tracking(1.2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(kmStr)
                    .font(.system(size: 40, weight: .medium))
                    .tracking(-1.8)
                Text("km").font(.system(size: 16)).foregroundStyle(IC.label)
            }
            .foregroundStyle(Color.white)
            if let ctx = distanceContext {
                Text(ctx).font(.system(size: 10)).foregroundStyle(IC.green)
            }
        }
    }

    private var kpiRow: some View {
        HStack(spacing: 0) {
            KPICell(label: AppLanguage.shared.s("시간", "Time"),
                    value: activity.formattedDuration)
            kpiSep
            KPICell(label: AppLanguage.shared.s("페이스", "Pace"),
                    value: activity.formattedPace ?? "--'--\"")
            kpiSep
            if let hr = activity.avgHeartRate {
                KPICell(label: AppLanguage.shared.s("심박", "HR"),
                        value: "\(hr)", unit: "bpm", color: IC.hrRed)
            } else {
                KPICell(label: AppLanguage.shared.s("심박", "HR"),
                        value: "--", color: .secondary)
            }
            kpiSep
            if let cad = detail?.avgCadence {
                KPICell(label: AppLanguage.shared.s("케이던스", "Cadence"),
                        value: "\(cad)", unit: "spm", color: IC.cadCyan)
            } else {
                KPICell(label: AppLanguage.shared.s("케이던스", "Cadence"),
                        value: "--", color: .secondary)
            }
        }
    }

    @ViewBuilder
    private var zoneDonutSection: some View {
        HStack(alignment: .top, spacing: 14) {
            ZoneDonutView(zones: hrZones)
                .frame(width: 86, height: 86)
            VStack(alignment: .leading, spacing: 6) {
                Text(zoneVerdictLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(zoneVerdictColor)
                if let cad = detail?.avgCadence {
                    CadenceRPMGaugeView(cadence: cad)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var zoneVerdictLabel: String {
        let L = AppLanguage.shared
        let visible = hrZones.filter { $0.fraction > 0.01 }
        let total = max(1e-9, visible.map(\.fraction).reduce(0, +))
        let z2frac = (hrZones.first(where: { $0.id == 2 })?.fraction ?? 0) / total
        if z2frac >= 0.60 { return L.s("딱 좋은 강도였어요", "Just the right intensity") }
        guard let dom = visible.max(by: { $0.fraction < $1.fraction }) else { return "" }
        switch dom.id {
        case 1: return L.s("가벼운 회복 강도였어요", "Light recovery run")
        case 2: return L.s("딱 좋은 강도였어요", "Just the right intensity")
        case 3: return L.s("템포 성향으로 달렸어요", "Tempo-paced run")
        default: return L.s("고강도 구간이 많았어요", "High-intensity effort")
        }
    }

    private var zoneVerdictColor: Color {
        let visible = hrZones.filter { $0.fraction > 0.01 }
        let total = max(1e-9, visible.map(\.fraction).reduce(0, +))
        let z2frac = (hrZones.first(where: { $0.id == 2 })?.fraction ?? 0) / total
        if z2frac >= 0.60 { return IC.zone(2) }
        guard let dom = visible.max(by: { $0.fraction < $1.fraction }) else { return IC.label }
        return IC.zone(dom.id)
    }

    private func cadenceSection(_ cadence: Int) -> some View {
        let L = AppLanguage.shared
        let inRange = (160...175).contains(cadence)
        let statusText = inRange
            ? L.s("권장 범위 안이에요", "In recommended range")
            : cadence < 160
                ? L.s("권장 범위보다 낮아요", "Below recommended range")
                : L.s("권장 범위보다 높아요", "Above recommended range")
        let statusColor: Color = inRange ? IC.green : IC.label

        return VStack(alignment: .leading, spacing: 6) {
            Text(AppLanguage.shared.s("케이던스", "Cadence"))
                .font(.system(size: 10)).foregroundStyle(IC.label)
            CadenceTrackView(cadence: cadence)
            HStack {
                Text("130").font(.system(size: 8.5)).foregroundStyle(IC.label)
                Spacer()
                Text(statusText).font(.system(size: 9)).foregroundStyle(statusColor)
                Spacer()
                Text("195+").font(.system(size: 8.5)).foregroundStyle(IC.label)
            }
        }
    }

    private func cardioSection(info: RunInsightEngine.VO2FitnessInfo, vo2: Double) -> some View {
        let L = AppLanguage.shared
        let g = info.genderLabel.isEmpty ? "" : " \(info.genderLabel)"
        let note = L.s("\(info.ageDecade)\(g) 기준 · 높음은 \(Int(info.normHigh)) 이상",
                       "\(info.ageDecade)\(g) · High ≥ \(Int(info.normHigh))")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1f", vo2))
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(IC.green)
                Text("mL/kg·min").font(.system(size: 9)).foregroundStyle(IC.label)
                Spacer()
                Text(info.levelLabel)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(IC.green)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(IC.green.opacity(0.18))
                    .clipShape(Capsule())
            }
            VO2GaugeView(fi: info, vo2: vo2)
            HStack(spacing: 0) {
                ForEach([L.s("낮음", "Low"), L.s("평균이하", "Below"), L.s("평균이상", "Above"), L.s("높음", "High")], id: \.self) { l in
                    Text(l).font(.system(size: 7.5)).foregroundStyle(IC.label).frame(maxWidth: .infinity)
                }
            }
            Text(note).font(.system(size: 9)).foregroundStyle(IC.label)
        }
    }

    @ViewBuilder
    private func oneLiner(text: String, bg: Color, fg: Color, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("✦").font(.system(size: 10)).foregroundStyle(accent)
            Text(text).font(.system(size: 10.5)).foregroundStyle(fg).lineSpacing(2)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
    }

    private var kpiSep: some View {
        Rectangle().fill(Color.white.opacity(0.10)).frame(width: 0.5, height: 40)
    }

    // MARK: Computed

    private var distanceContext: String? {
        let recent = history
            .filter { $0.type == .running && $0.id != activity.id && $0.date < activity.date }
            .sorted { $0.date > $1.date }
        let sample = (Array(recent.prefix(9)) + [activity]).sorted { $0.distance > $1.distance }
        guard sample.count >= 5 else { return nil }
        guard let rank = sample.firstIndex(where: { $0.id == activity.id }).map({ $0 + 1 }),
              rank <= 3 else { return nil }
        let L = AppLanguage.shared
        if rank == 1 {
            return L.s("↑ 최근 \(sample.count)회 중 가장 긴 거리", "↑ Longest of last \(sample.count) runs")
        }
        return L.s("↑ 최근 \(sample.count)회 중 \(rank)번째로 긴 거리", "↑ #\(rank) of last \(sample.count) by distance")
    }

    private var vo2Info: RunInsightEngine.VO2FitnessInfo? {
        guard let vo2 = detail?.vo2Max, let a = age else { return nil }
        return RunInsightEngine.vo2FitnessInfo(vo2: vo2, age: a, isMale: isMale)
    }

    private var oneLiner: String? {
        for cat: InsightCategory in [.cardio, .efficiency, .intensity, .endurance] {
            if let m = insights.first(where: { $0.category == cat })?.message { return m }
        }
        return insights.first?.message
    }
}

// MARK: - Performance Card

private struct PerformanceInsightCard: View {
    let activity: Activity
    var detail: ActivityDetail? = nil
    var history: [Activity] = []
    var age: Int? = nil
    var isMale: Bool? = nil
    let insights: [RunInsight]
    var workoutTypeFn: ((UUID) -> WorkoutType?)? = nil
    var isBackfilling: Bool = false

    private struct HRTrendPt: Identifiable {
        let id = UUID()
        let index: Int
        let hr: Double
        let isToday: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroSection
            divider
            kpiRow
            let trend = hrTrendPts
            if trend.count >= 2 {
                divider
                hrEffSection(trend)
            }
            if let info = vo2Info, let vo2 = detail?.vo2Max {
                divider
                cardioSection(info: info, vo2: vo2)
            }
            let hasMetrics = paceConsistencySec != nil || backHalfPct != nil
            let base = weeklyBase
            if hasMetrics || base.weeklyLoadKm > 0 {
                divider
                metricsSection(base: base)
            }
            if let dist = trainingDistData {
                divider
                distribSection(items: dist.items, weeks: dist.weeks)
            } else if isBackfilling {
                divider
                backfillingPlaceholder
            }
            if let line = oneLiner {
                divider
                oneLiner(text: line, bg: IC.violetBg, fg: IC.violetText, accent: IC.violet)
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var heroSection: some View {
        let km = activity.distance / 1000
        let kmStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
        return VStack(alignment: .leading, spacing: 3) {
            Text(AppLanguage.shared.s("오늘", "Today"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(IC.label)
                .tracking(1.2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(kmStr)
                    .font(.system(size: 40, weight: .medium))
                    .tracking(-1.8)
                Text("km").font(.system(size: 16)).foregroundStyle(IC.label)
            }
            .foregroundStyle(Color.white)
            if let ctx = heroContext {
                Text(ctx).font(.system(size: 10)).foregroundStyle(IC.green)
            }
        }
    }

    private var kpiRow: some View {
        HStack(spacing: 0) {
            KPICell(label: AppLanguage.shared.s("시간", "Time"),
                    value: activity.formattedDuration)
            kpiSep
            KPICell(label: AppLanguage.shared.s("페이스", "Pace"),
                    value: activity.formattedPace ?? "--'--\"")
            kpiSep
            if let hr = activity.avgHeartRate {
                let ctx: String? = hrDelta.map { d in
                    AppLanguage.shared.s("동일 페이스 −\(d)bpm", "−\(d)bpm vs similar")
                }
                KPICell(label: AppLanguage.shared.s("심박", "HR"),
                        value: "\(hr)", unit: "bpm", color: IC.hrRed,
                        context: ctx)
            } else {
                KPICell(label: AppLanguage.shared.s("심박", "HR"),
                        value: "--", color: .secondary)
            }
            kpiSep
            if let cad = detail?.avgCadence {
                KPICell(label: AppLanguage.shared.s("케이던스", "Cadence"),
                        value: "\(cad)", unit: "spm", color: IC.cadCyan)
            } else {
                KPICell(label: AppLanguage.shared.s("케이던스", "Cadence"),
                        value: "--", color: .secondary)
            }
        }
    }

    private func hrEffSection(_ pts: [HRTrendPt]) -> some View {
        let historical = pts.filter { !$0.isToday }
        let todayPt = pts.first(where: { $0.isToday })
        let improving = historical.last.map { $0.hr > (todayPt?.hr ?? 0) } ?? false
        let L = AppLanguage.shared
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let d = hrDelta, d > 0 {
                    Text("−\(d) bpm")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(IC.green)
                    Text(L.s("같은 페이스 기준", "vs. similar pace"))
                        .font(.system(size: 9)).foregroundStyle(IC.label)
                } else {
                    Text(L.s("심박 효율 추이", "HR Efficiency Trend"))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                }
                Spacer()
                Text(L.s("↓ 낮을수록 좋아요", "↓ lower is better"))
                    .font(.system(size: 8.5)).foregroundStyle(IC.label)
            }
            Chart {
                ForEach(pts) { pt in
                    LineMark(x: .value("idx", pt.index), y: .value("HR", pt.hr))
                        .foregroundStyle(Color.white.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    if pt.isToday {
                        PointMark(x: .value("idx", pt.index), y: .value("HR", pt.hr))
                            .foregroundStyle(IC.green.opacity(0.30))
                            .symbolSize(180)
                        PointMark(x: .value("idx", pt.index), y: .value("HR", pt.hr))
                            .foregroundStyle(IC.green)
                            .symbolSize(64)
                    } else {
                        PointMark(x: .value("idx", pt.index), y: .value("HR", pt.hr))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .symbolSize(20)
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis(.hidden)
            .frame(height: 60)

            HStack {
                if let f = historical.first {
                    Text(L.s("8주 전 \(Int(f.hr))", "8w ago \(Int(f.hr))"))
                        .font(.system(size: 8.5)).foregroundStyle(IC.label)
                }
                Spacer()
                if let t = todayPt {
                    Text(L.s("오늘 \(Int(t.hr))", "Today \(Int(t.hr))"))
                        .font(.system(size: 8.5))
                        .foregroundStyle(improving ? IC.green : IC.label)
                }
            }
        }
    }

    private func cardioSection(info: RunInsightEngine.VO2FitnessInfo, vo2: Double) -> some View {
        let L = AppLanguage.shared
        let g = info.genderLabel.isEmpty ? "" : " \(info.genderLabel)"
        let note = L.s("\(info.ageDecade)\(g) 기준 · 높음은 \(Int(info.normHigh)) 이상",
                       "\(info.ageDecade)\(g) · High ≥ \(Int(info.normHigh))")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1f", vo2))
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(IC.green)
                Text("mL/kg·min").font(.system(size: 9)).foregroundStyle(IC.label)
                Spacer()
                Text(info.levelLabel)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(IC.green)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(IC.green.opacity(0.18))
                    .clipShape(Capsule())
            }
            VO2GaugeView(fi: info, vo2: vo2)
            HStack(spacing: 0) {
                ForEach([L.s("낮음", "Low"), L.s("평균이하", "Below"), L.s("평균이상", "Above"), L.s("높음", "High")], id: \.self) { l in
                    Text(l).font(.system(size: 7.5)).foregroundStyle(IC.label).frame(maxWidth: .infinity)
                }
            }
            Text(note).font(.system(size: 9)).foregroundStyle(IC.label)
        }
    }

    private func metricsSection(base: RunBaseline) -> some View {
        let L = AppLanguage.shared
        return VStack(spacing: 8) {
            if let sd = paceConsistencySec {
                MetricRow(label: L.s("페이스 일관성", "Pace Consistency"),
                          value: "±\(sd)" + L.s("초", "s"))
            }
            if let pct = backHalfPct {
                MetricRow(label: L.s("후반 유지율", "Back-Half Retention"),
                          value: String(format: "%.0f%%", pct))
            }
            if base.weeklyLoadKm > 0 {
                let prevCtx: String? = base.prevWeeklyLoadKm > 0
                    ? L.s("지난주 \(String(format: "%.1f", base.prevWeeklyLoadKm))km",
                          "Last wk \(String(format: "%.1f", base.prevWeeklyLoadKm))km")
                    : nil
                MetricRow(label: L.s("이번 주 훈련량", "Weekly Load"),
                          value: String(format: "%.1fkm", base.weeklyLoadKm),
                          context: prevCtx)
            }
        }
    }

    @ViewBuilder
    private func oneLiner(text: String, bg: Color, fg: Color, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("✦").font(.system(size: 10)).foregroundStyle(accent)
            Text(text).font(.system(size: 10.5)).foregroundStyle(fg).lineSpacing(2)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
    }

    private var kpiSep: some View {
        Rectangle().fill(Color.white.opacity(0.10)).frame(width: 0.5, height: 40)
    }

    // MARK: Computed

    private var heroContext: String? {
        if let eff = insights.first(where: { $0.category == .efficiency && $0.tone == .good }),
           let h = eff.highlights.first {
            return "↑ " + AppLanguage.shared.s(
                "비슷한 페이스 대비 \(h) 낮은 심박",
                "HR \(h) lower at similar pace"
            )
        }
        let recent = history
            .filter { $0.type == .running && $0.id != activity.id && $0.date < activity.date }
            .sorted { $0.date > $1.date }
        let sample = (Array(recent.prefix(9)) + [activity]).sorted { $0.distance > $1.distance }
        guard sample.count >= 5 else { return nil }
        guard let rank = sample.firstIndex(where: { $0.id == activity.id }).map({ $0 + 1 }),
              rank <= 3 else { return nil }
        let L = AppLanguage.shared
        return rank == 1
            ? L.s("↑ 최근 \(sample.count)회 중 가장 긴 거리", "↑ Longest of last \(sample.count) runs")
            : L.s("↑ 최근 \(sample.count)회 중 \(rank)번째로 긴 거리", "↑ #\(rank) of last \(sample.count)")
    }

    private var hrTrendPts: [HRTrendPt] {
        guard let curHR = activity.avgHeartRate,
              let curPace = activity.paceSecPerKm, curPace > 0 else { return [] }
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: activity.date) ?? .distantPast
        let similar = history.filter {
            $0.type == .running && $0.id != activity.id &&
            $0.date >= cutoff && $0.date < activity.date &&
            $0.avgHeartRate != nil &&
            abs(($0.paceSecPerKm ?? .infinity) - curPace) <= 15.0
        }.sorted { $0.date < $1.date }
        guard similar.count >= 2 else { return [] }
        var pts = similar.prefix(7).enumerated().map { i, r in
            HRTrendPt(index: i, hr: Double(r.avgHeartRate!), isToday: false)
        }
        pts.append(HRTrendPt(index: pts.count, hr: Double(curHR), isToday: true))
        return pts
    }

    private var hrDelta: Int? {
        guard let curHR = activity.avgHeartRate else { return nil }
        let pts = hrTrendPts.filter { !$0.isToday }
        guard !pts.isEmpty else { return nil }
        let avg = pts.map(\.hr).reduce(0, +) / Double(pts.count)
        let d = Int((avg - Double(curHR)).rounded())
        return d >= 3 ? d : nil
    }

    private var vo2Info: RunInsightEngine.VO2FitnessInfo? {
        guard let vo2 = detail?.vo2Max, let a = age else { return nil }
        return RunInsightEngine.vo2FitnessInfo(vo2: vo2, age: a, isMale: isMale)
    }

    private var paceConsistencySec: Int? {
        guard let splits = detail?.splits, splits.count >= 3 else { return nil }
        let paces = splits.map { $0.paceSecPerKm }
        let mean = paces.reduce(0, +) / Double(paces.count)
        guard mean > 0 else { return nil }
        let sd = (paces.map { pow($0 - mean, 2) }.reduce(0, +) / Double(paces.count)).squareRoot()
        return Int(sd.rounded())
    }

    private var backHalfPct: Double? {
        guard let splits = detail?.splits, splits.count >= 4 else { return nil }
        let half = splits.count / 2
        let fAvg = splits[..<half].map { $0.paceSecPerKm }.reduce(0, +) / Double(half)
        let bAvg = splits[half...].map { $0.paceSecPerKm }.reduce(0, +) / Double(splits.count - half)
        guard fAvg > 0 else { return nil }
        return bAvg / fAvg * 100
    }

    private var weeklyBase: RunBaseline {
        RunInsightEngine.baseline(for: activity, history: history)
    }

    private struct TrainingDistItem {
        let label: String; let count: Int; let color: Color
    }

    private var trainingDistData: (items: [TrainingDistItem], weeks: Int)? {
        guard let fn = workoutTypeFn else { return nil }

        func evaluate(weeks: Int) -> [TrainingDistItem]? {
            let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: activity.date) ?? .distantPast
            let runs = history.filter { $0.type == .running && $0.date >= cutoff && $0.date <= activity.date }
            let known = runs.filter { fn($0.id) != nil }
            guard known.count >= 8 else { return nil }
            var groups: [String: (count: Int, color: Color)] = [:]
            for run in known {
                guard let type = fn(run.id) else { continue }
                let b = displayBucket(for: type)
                if let ex = groups[b.label] { groups[b.label] = (ex.count + 1, ex.color) }
                else { groups[b.label] = (1, b.color) }
            }
            guard !groups.isEmpty else { return nil }
            return groups.map { TrainingDistItem(label: $0.key, count: $0.value.count, color: $0.value.color) }
                .sorted { $0.count > $1.count }
        }

        if let items = evaluate(weeks: 4) { return (items, 4) }
        if let items = evaluate(weeks: 8) { return (items, 8) }
        return nil
    }

    private func displayBucket(for type: WorkoutType) -> (label: String, color: Color) {
        let L = AppLanguage.shared
        switch type {
        case .interval:                    return (L.s("인터벌", "Interval"), Color(hex: "FF9A3C"))
        case .tempo, .buildUp:             return (L.s("템포",   "Tempo"),    Color(hex: "F5C542"))
        case .lsd, .longRun, .distanceRun: return (L.s("LSD",   "LSD"),      Color(hex: "8B7FF0"))
        case .easy, .general:              return (L.s("데일리런", "Daily"),   Color(hex: "6B7280"))
        }
    }

    @ViewBuilder
    private func distribSection(items: [TrainingDistItem], weeks: Int) -> some View {
        let total = items.map(\.count).reduce(0, +)
        let L = AppLanguage.shared
        let maxCount = max(1, items.map(\.count).max() ?? 1)
        VStack(alignment: .leading, spacing: 8) {
            Text(L.s("훈련 배분 · 최근 \(weeks)주 \(total)회",
                     "Training Mix · \(weeks)w · \(total) runs"))
                .font(.system(size: 10)).foregroundStyle(IC.label)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(items, id: \.label) { item in
                    VStack(spacing: 4) {
                        Text("\(item.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(item.color)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.color.opacity(0.85))
                            .frame(height: max(8, 44 * CGFloat(item.count) / CGFloat(maxCount)))
                        Text(item.label)
                            .font(.system(size: 8))
                            .foregroundStyle(IC.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 72)
        }
    }

    private var backfillingPlaceholder: some View {
        HStack(spacing: 6) {
            ProgressView().tint(IC.label).scaleEffect(0.7)
            Text(AppLanguage.shared.s("훈련 유형 분석 중…", "Analyzing run types…"))
                .font(.system(size: 10)).foregroundStyle(IC.label)
        }
    }

    private var oneLiner: String? {
        for cat: InsightCategory in [.efficiency, .endurance, .load, .cardio] {
            if let m = insights.first(where: { $0.category == cat })?.message { return m }
        }
        return insights.first?.message
    }
}

// MARK: - Export Sheet

struct InsightExportSheet: View {
    let activity: Activity
    var detail: ActivityDetail? = nil
    var history: [Activity] = []
    var age: Int? = nil
    var isMale: Bool? = nil
    var hrZones: [HRZoneData] = []
    let insights: [RunInsight]
    var startTab: InsightTabKind = .rhythm
    var workoutTypeFn: ((UUID) -> WorkoutType?)? = nil
    var cadenceSeries: [(offset: TimeInterval, value: Double)] = []

    @Query private var allStories: [WorkoutStory]
    @Query private var allShoes: [Shoe]

    private var shoeName: String? {
        let sid = allStories.first(where: { $0.workoutID == activity.id.uuidString })?.shoeID
        guard let sid else { return nil }
        return allShoes.first { $0.id.uuidString == sid }?.displayName
    }

    @State private var tab: InsightTabKind = .rhythm
    @State private var exportImage: UIImage? = nil
    @State private var isRendering = false
    @State private var showShare = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabSwitcher.padding(.vertical, 14).padding(.horizontal, 20)
                Divider().opacity(0.2)
                ScrollView {
                    cardPreview.padding(20)
                }
                Spacer(minLength: 0)
                shareBar
            }
            .background(Color(hex: "0D0D0F"))
            .navigationTitle(AppLanguage.shared.s("인사이트 내보내기", "Export Insight"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            tab = startTab
            renderCard()
        }
        .onChange(of: tab) { _, _ in renderCard() }
        .sheet(isPresented: $showShare) {
            if let img = exportImage { ShareSheet(images: [img]) }
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(InsightTabKind.allCases, id: \.self) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tab = t }
                } label: {
                    Text(t.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tab == t ? Theme.violet : Color.white.opacity(0.50))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(tab == t ? Theme.violet.opacity(0.22) : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var cardPreview: some View {
        exportCardView
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }

    private var exportCardView: some View {
        VStack(spacing: 0) {
            exportHeader
            cardBody
            exportFooter
        }
        .background(Theme.cardBackground)
    }

    private var exportHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            MIMOWordmark(size: 9)

            Spacer()

            koreanDateTimeText
                .font(.system(size: 9))
                .lineLimit(1)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let temp = activity.temperatureC {
                    HStack(spacing: 4) {
                        Image(systemName: weatherIcon(for: temp))
                            .font(.system(size: 9))
                        Text(String(format: "%.0f°", temp))
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color(hex: "2C1F0E"))
                    .clipShape(Capsule())
                }
                if let sn = shoeName {
                    HStack(spacing: 3) {
                        Image(systemName: "shoe")
                            .font(.system(size: 8))
                        Text(sn)
                            .font(.system(size: 8))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var koreanDateTimeText: Text {
        let ko = Locale(identifier: "ko_KR")
        let fDate = DateFormatter(); fDate.locale = ko; fDate.dateFormat = "yyyy. M. d "
        let fDay  = DateFormatter(); fDay.locale  = ko; fDay.dateFormat  = "EEEE"
        let fTime = DateFormatter(); fTime.locale = ko; fTime.dateFormat = " a h:mm"
        return Text(fDate.string(from: activity.date)).foregroundStyle(.white.opacity(0.65))
             + Text(fDay.string(from: activity.date)).foregroundStyle(Color.yellow)
             + Text(fTime.string(from: activity.date)).foregroundStyle(.white.opacity(0.65))
    }

    private func weatherIcon(for tempC: Double) -> String {
        if let h = activity.humidityPercent, h >= 80 { return "cloud.rain.fill" }
        if tempC >= 28 { return "sun.max.fill" }
        if tempC <= 2  { return "snowflake" }
        return "cloud.sun.fill"
    }

    @ViewBuilder
    private var cardBody: some View {
        if tab == .rhythm {
            RhythmInsightCard(
                activity: activity, detail: detail,
                history: history, age: age, isMale: isMale,
                hrZones: hrZones, insights: insights,
                cadenceSeries: cadenceSeries
            )
        } else {
            PerformanceInsightCard(
                activity: activity, detail: detail,
                history: history, age: age, isMale: isMale,
                insights: insights,
                workoutTypeFn: workoutTypeFn
            )
        }
    }

    private var exportFooter: some View {
        Text(AppLanguage.shared.s(
            "참고용 피트니스 인사이트. 의학적 판단이 아니에요.",
            "Reference-only fitness insights. Not medical advice."
        ))
        .font(.system(size: 8.5))
        .foregroundStyle(IC.label)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var shareBar: some View {
        Button {
            renderCard()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showShare = true
            }
        } label: {
            HStack(spacing: 8) {
                if isRendering {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(AppLanguage.shared.s("공유하기", "Share"))
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.violet)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.bottom, 32).padding(.top, 12)
    }

    @MainActor
    private func renderCard() {
        isRendering = true
        let renderer = ImageRenderer(content:
            exportCardView
                .frame(width: 360)
                .background(Theme.cardBackground)
        )
        renderer.scale = 3
        exportImage = renderer.uiImage
        isRendering = false
    }
}
