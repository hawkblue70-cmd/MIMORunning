import SwiftUI
import Charts
import SwiftData

// MARK: - Tab Enum

enum InsightTabKind: CaseIterable, Hashable {
    case rhythm, form, performance, race

    var title: String {
        switch self {
        case .rhythm:      return AppLanguage.shared.s("리듬", "Rhythm")
        case .form:        return AppLanguage.shared.s("폼", "Form")
        case .performance: return AppLanguage.shared.s("퍼포먼스", "Performance")
        case .race:        return AppLanguage.shared.s("대회", "Race")
        }
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

    static let vo2Colors: [Color] = [
        Color(hex: "FF5247"),   // 낮음: 빨강
        Color(hex: "FF9A3C"),   // 평균이하: 주황
        Color(hex: "F5C542"),   // 평균이상: 노랑
        Color(hex: "5CE08A"),   // 높음: 녹색
    ]

    static let zoneColors: [Color] = [
        Color(hex: "4C8DFF"), Color(hex: "5CE08A"),
        Color(hex: "F5C542"), Color(hex: "FF9A3C"), Color(hex: "FF5247"),
    ]
    static func zone(_ id: Int) -> Color { zoneColors[min(max(id - 1, 0), 4)] }
}

// MARK: - Card Number Font

enum CardNumberFont {
    case systemHeavy, blackGothic
    static let current: CardNumberFont = .systemHeavy

    func swiftUIFont(_ size: CGFloat) -> Font {
        switch self {
        case .systemHeavy:
            return .system(size: size, weight: .heavy, design: .default).monospacedDigit()
        case .blackGothic:
            return .custom("AppleSDGothicNeo-Heavy", size: size)
        }
    }
}

func cardNumFont(_ size: CGFloat) -> Font {
    CardNumberFont.current.swiftUIFont(size)
}

// MARK: - Shared Subviews

struct KPICell: View {
    let label: String
    let value: String
    var unit: String? = nil
    var color: Color = .white
    var context: String? = nil

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(cardNumFont(15)).foregroundStyle(color)
                if let u = unit {
                    Text(u).font(.system(size: 10)).foregroundStyle(IC.label)
                }
            }
            Text(label).font(.system(size: 8.5)).foregroundStyle(.white.opacity(0.70))
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
                        .font(cardNumFont(20))
                        .foregroundStyle(IC.zone(dom.id))
                    Text("Zone \(dom.id)")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.75))
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
    var formBaseline: RunningFormBaseline? = nil
    var activity: Activity? = nil
    var isInterval: Bool = false

    private var cadenceStat: FormStat? {
        guard let act = activity, let bl = formBaseline else { return nil }
        return bl.baseline(for: act)?.cadence
    }

    /// 개인 분포 ±4σ 기반 동적 축. 최대 폭 70, 5 단위 반올림.
    private var axisRange: (min: Double, max: Double) {
        guard let s = cadenceStat else { return (140, 190) }
        let rawMax = max(190, ceil((s.median + 4 * s.sd) / 5) * 5)
        var rawMin = min(140, floor((s.median - 4 * s.sd) / 5) * 5)
        if rawMax - rawMin > 70 { rawMin = rawMax - 70 }
        return (rawMin, rawMax)
    }

    private var personalBand: (lower: Double, upper: Double, absoluteWarning: Double?) {
        if isInterval { return (170, 190, nil) }
        guard let act = activity, let bl = formBaseline else { return (160, 180, nil) }
        return bl.cadenceBand(for: act)
    }

    // 180°(9시) → 360°(3시), clockwise:false = 상단 반원
    private func ang(_ v: Double, axMin: Double, axMax: Double) -> Double {
        let c = max(axMin, min(axMax, v))
        return 180 + (c - axMin) / (axMax - axMin) * 180
    }

    var body: some View {
        let (axMin, axMax) = axisRange
        let (pLower, pUpper, absoluteWarning) = personalBand
        let c = Double(cadence)
        let nc: Color = (absoluteWarning != nil && c < 160) ? Color(hex: "FF6B6B")
            : (c >= pLower && c <= pUpper) ? .white
            : Color(hex: "F0913C")

        VStack(alignment: .leading, spacing: 6) {
            Canvas { ctx, size in
                let cx    = size.width / 2
                let thick: CGFloat = 10
                let r     = cx - thick / 2 - 1
                let cy    = size.height - thick / 2 - 1
                let center = CGPoint(x: cx, y: cy)

                // 3구간 아크 — 개인 밴드 기반, clockwise:false = 상단 반원
                let segs: [(Double, Double, Color)] = [
                    (axMin,  pLower, Color(hex: "5AC8FA")),
                    (pLower, pUpper, Color(hex: "7FD98A")),
                    (pUpper, axMax,  Color(hex: "3A7BD5")),
                ]
                for s in segs where s.0 < s.1 {
                    var arc = Path()
                    arc.addArc(center: center, radius: r,
                               startAngle: .degrees(ang(s.0, axMin: axMin, axMax: axMax)),
                               endAngle:   .degrees(ang(s.1, axMin: axMin, axMax: axMax)),
                               clockwise: false)
                    ctx.stroke(arc, with: .color(s.2),
                               style: StrokeStyle(lineWidth: thick, lineCap: .butt))
                }

                // 160 absoluteWarning 마커 — 개인 lower < 160 일 때만 표시
                if absoluteWarning != nil {
                    let wRad = ang(160, axMin: axMin, axMax: axMax) * .pi / 180
                    var mp = Path()
                    mp.move(to: CGPoint(x: center.x + (r - 7) * CGFloat(cos(wRad)),
                                        y: center.y + (r - 7) * CGFloat(sin(wRad))))
                    mp.addLine(to: CGPoint(x: center.x + (r + 7) * CGFloat(cos(wRad)),
                                           y: center.y + (r + 7) * CGFloat(sin(wRad))))
                    ctx.stroke(mp, with: .color(Color(hex: "FF6B6B")),
                               style: StrokeStyle(lineWidth: 2))
                    ctx.draw(
                        Text("160").font(.system(size: 8)).foregroundStyle(Color(hex: "FF6B6B")),
                        at: CGPoint(x: center.x + (r - 14) * CGFloat(cos(wRad)),
                                    y: center.y + (r - 14) * CGFloat(sin(wRad))),
                        anchor: .center
                    )
                }

                // 바늘
                let valRad = ang(c, axMin: axMin, axMax: axMax) * .pi / 180
                let tip = CGPoint(x: center.x + r * CGFloat(cos(valRad)),
                                  y: center.y + r * CGFloat(sin(valRad)))
                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: tip)
                ctx.stroke(needle, with: .color(nc.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

                // 중심 원
                let dotR: CGFloat = 4
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR,
                                          width: dotR * 2, height: dotR * 2)),
                    with: .color(.white)
                )

                // 값 텍스트
                ctx.draw(
                    Text("\(cadence)")
                        .font(cardNumFont(17))
                        .foregroundStyle(Color(hex: "5CE5D5")),
                    at: CGPoint(x: cx, y: cy - 34),
                    anchor: .center
                )
            }
            .frame(width: 128, height: 76)
            .overlay(alignment: .bottom) {
                HStack {
                    Text("\(Int(axMin))").font(.system(size: 8)).foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    Text("\(Int(axMax))").font(.system(size: 8)).foregroundStyle(.white.opacity(0.65))
                }
                .frame(width: 128)
                .offset(y: 10)
            }
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

    private let segColors: [Color] = IC.vo2Colors

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

private struct VO2RPMGaugeView: View {
    let fi: RunInsightEngine.VO2FitnessInfo
    let vo2: Double

    // 하드코딩 경계값으로 4구간 렌더 검증 (이후 fi 규준값으로 교체)
    private let bounds: [Double]   = [15, 26, 33, 41, 57]
    private let segColors: [Color] = [
        Color(hex: "E8564A"),  // 낮음
        Color(hex: "F0913C"),  // 평균이하
        Color(hex: "EDC84B"),  // 평균이상
        Color(hex: "7FD98A"),  // 높음
    ]
    private let segLabels   = ["낮음", "평균이하", "평균이상", "높음"]
    private let segLabelsEn = ["Low", "Below avg", "Above avg", "High"]

    // 15→180°(9시), 57→360°(3시). clockwise:false 로 단거리 경로(상단 반원)
    private func ang(_ v: Double) -> Double {
        180 + (min(max(v, 15), 57) - 15) / 42 * 180
    }

    private var zoneIndex: Int {
        for i in 0..<(bounds.count - 1) {
            if vo2 < bounds[i + 1] { return i }
        }
        return bounds.count - 2
    }

    var body: some View {
        let zIdx = zoneIndex
        let vc   = segColors[zIdx]
        let segs: [(Double, Double, Color)] = (0..<segColors.count).map {
            (bounds[$0], bounds[$0 + 1], segColors[$0])
        }

        VStack(alignment: .leading, spacing: 6) {
            Canvas { ctx, size in
                let cx    = size.width / 2
                let thick: CGFloat = 10
                let r     = cx - thick / 2 - 1
                let cy    = size.height - thick / 2 - 1
                let center = CGPoint(x: cx, y: cy)

                // 4구간 고정색 아크 — clockwise:false = 단거리(상단) 경로
                for s in segs {
                    var arc = Path()
                    arc.addArc(center: center, radius: r,
                               startAngle: .degrees(ang(s.0)),
                               endAngle:   .degrees(ang(s.1)),
                               clockwise: false)
                    ctx.stroke(arc, with: .color(s.2),
                               style: StrokeStyle(lineWidth: thick, lineCap: .butt))
                }

                // 바늘
                let valRad    = ang(vo2) * .pi / 180
                let needleLen = r
                let tip = CGPoint(x: center.x + needleLen * CGFloat(cos(valRad)),
                                  y: center.y + needleLen * CGFloat(sin(valRad)))
                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: tip)
                ctx.stroke(needle, with: .color(.white.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

                // 중심 원
                let dotR: CGFloat = 4
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR,
                                          width: dotR*2, height: dotR*2)),
                    with: .color(.white)
                )

                // 값 텍스트 — 현재값 구간 색
                ctx.draw(
                    Text(String(format: "%.0f", vo2))
                        .font(cardNumFont(17))
                        .foregroundStyle(vc),
                    at: CGPoint(x: cx, y: cy - 34),
                    anchor: .center
                )
            }
            .frame(width: 128, height: 76)
            .overlay(alignment: .bottom) {
                HStack {
                    Text("15").font(.system(size: 8)).foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    Text("57").font(.system(size: 8)).foregroundStyle(.white.opacity(0.65))
                }
                .frame(width: 128).offset(y: 10)
            }

        }
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

// MARK: - Achievement Badge

private enum AchievementBadgeKind {
    case longestEver
    case bestPace
    case longestThisMonth
    case streak(Int)

    var text: String {
        let L = AppLanguage.shared
        switch self {
        case .longestEver:      return L.s("🏅 최장 거리",    "🏅 All-time Longest")
        case .bestPace:         return L.s("⚡ 페이스 최고",   "⚡ Best Pace")
        case .longestThisMonth: return L.s("🏅 이번 달 최장", "🏅 Month Longest")
        case .streak(let n):    return L.s("🔥 \(n)일 연속",  "🔥 \(n)-day Streak")
        }
    }

    var bgColor: Color {
        switch self {
        case .longestEver, .longestThisMonth:
            return Color(red: 245/255, green: 197/255, blue: 66/255).opacity(0.18)
        case .bestPace:
            return Color(red: 139/255, green: 127/255, blue: 240/255).opacity(0.20)
        case .streak:
            return Color(red: 255/255, green: 154/255, blue: 60/255).opacity(0.18)
        }
    }

    var fgColor: Color {
        switch self {
        case .longestEver, .longestThisMonth: return Color(hex: "F5C542")
        case .bestPace:                       return Color(hex: "B5A9FF")
        case .streak:                         return Color(hex: "FF9A3C")
        }
    }
}

private func computeAchievementBadge(activity: Activity, history: [Activity]) -> AchievementBadgeKind? {
    let runs = history.filter { $0.type == .running && $0.id != activity.id }
    let km = activity.distance

    // 1. 최장 거리 (전체 기록)
    if !runs.isEmpty, km >= (runs.map(\.distance).max() ?? 0) {
        return .longestEver
    }

    // 2. 최고 페이스 (같은 거리대 ±20%)
    if let pace = activity.paceSecPerKm {
        let similar = runs.filter {
            $0.distance > 0 &&
            abs($0.distance - km) / max(1, km) <= 0.20 &&
            $0.paceSecPerKm != nil
        }
        if !similar.isEmpty, pace <= (similar.compactMap(\.paceSecPerKm).min() ?? .infinity) {
            return .bestPace
        }
    }

    // 3. 이번 달 최장 거리
    let cal = Calendar.current
    let monthRuns = runs.filter {
        cal.isDate($0.date, equalTo: activity.date, toGranularity: .month)
    }
    if !monthRuns.isEmpty, km >= (monthRuns.map(\.distance).max() ?? 0) {
        return .longestThisMonth
    }

    // 4. 연속 달리기 (3일 이상)
    let streak = computeRunningStreak(activity: activity, history: history)
    if streak >= 3 { return .streak(streak) }

    return nil
}

private func computeRunningStreak(activity: Activity, history: [Activity]) -> Int {
    let cal = Calendar.current
    let runDays = Set(
        history.filter { $0.type == .running }
               .map { cal.startOfDay(for: $0.date) }
    )
    var day = cal.startOfDay(for: activity.date)
    var count = 0
    while runDays.contains(day) {
        count += 1
        guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
        day = prev
    }
    return count
}

private struct AchievementBadgeView: View {
    let badge: AchievementBadgeKind

    var body: some View {
        Text(badge.text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(badge.fgColor)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(badge.bgColor)
            .clipShape(Capsule())
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
    var isClassifying: Bool = false
    var cadenceSeries: [(offset: TimeInterval, value: Double)] = []
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    var formBaseline: RunningFormBaseline? = nil
    var formBackfillProgress: (done: Int, total: Int)? = nil
    var heatModel: MRHeatModel? = nil
    var formShifts: [MRFormShift] = []
    var weatherSnapshot: WeatherSnapshot? = nil
    var confirmedRace: PersistedRaceMatch? = nil
    var confirmedRaces: [PersistedRaceMatch] = []
    var raceDetailFn: ((UUID) -> ActivityDetail?)? = nil
    /// 과거 러닝의 존 체류 시간 (강도 분포 · 4주 합산용). 리듬 카드 도넛과 같은 캐시 데이터.
    var hrZonesFn: ((UUID) -> [HRZoneData]?)? = nil
    /// 강도(sRPE) 조회 인덱스 — 퍼포먼스 탭의 7일 강도 부하용. 없으면 해당 반쪽 생략.
    var effortIndex: EffortIndex? = nil

    @State private var tab: InsightTabKind = .rhythm
    @State private var showExport = false

    /// 이 활동 기준으로 직전 4주간 러닝의 1회 평균 거리(km).
    /// RunFormCardView의 장거리 문맥 판단에 사용.
    private var typicalRunDistanceKm: Double? {
        let fourWeeksAgo = Calendar.current.date(byAdding: .day, value: -28, to: activity.date) ?? .distantPast
        let recent = history.filter {
            $0.type == .running && $0.id != activity.id &&
            $0.date >= fourWeeksAgo && $0.date < activity.date
        }
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0.0) { $0 + $1.distance } / Double(recent.count) / 1000.0
    }

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
                formBaseline: formBaseline,
                cadenceSeries: cadenceSeries,
                hrSamples: hrSamples,
                heatModel: heatModel,
                formShifts: formShifts,
                weatherSnapshot: weatherSnapshot,
                confirmedRace: confirmedRace,
                confirmedRaces: confirmedRaces,
                raceDetailFn: raceDetailFn,
                hrZonesFn: hrZonesFn,
                effortIndex: effortIndex
            )
        }
        .onAppear {
            if workoutTypeFn?(activity.id) == .race {
                tab = .race
            }
        }
    }

    private var sectionHeader: some View {
        let L = AppLanguage.shared
        let base = L.s("오늘의 러닝", "Today's Run")
        let effectiveLabel: String? = workoutTypeFn?(activity.id) == .race
            ? L.s("대회", "Race")
            : workoutTypeLabel
        let title = effectiveLabel.map { "\(base) · \($0)" } ?? base
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
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
            if let desc = workoutTypeDescription {
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    private var workoutTypeDescription: String? {
        guard let wt = workoutTypeFn?(activity.id) else { return nil }
        let L = AppLanguage.shared
        switch wt {
        case .buildUp:     return L.s("갈수록 페이스를 올리는 훈련", "Progressive acceleration training")
        case .tempo:       return L.s("젖산역치 근처를 일정하게 버티는 훈련", "Sustained threshold-pace run")
        case .interval:    return L.s("고강도와 회복을 반복하는 훈련", "High-intensity intervals with recovery")
        case .lsd:         return L.s("낮은 강도로 오래 달려 지구력을 쌓는 훈련", "Long slow run to build aerobic base")
        case .longRun:     return L.s("평소보다 긴 거리로 지구력을 늘리는 훈련", "Extended run to build endurance")
        case .distanceRun: return L.s("목표 거리를 채우는 훈련", "Race-pace long distance run")
        case .easy:        return L.s("편안한 페이스로 회복하는 러닝", "Easy recovery run")
        case .race:        return L.s("기록에 도전한 대회 러닝", "Race effort run")
        case .general:     return nil
        }
    }

    private var visibleTabs: [InsightTabKind] {
        let hasForm = detail?.avgCadence != nil
        let isRace  = workoutTypeFn?(activity.id) == .race
        return InsightTabKind.allCases.filter {
            ($0 != .form || hasForm) && ($0 != .race || isRace)
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 6) {
            ForEach(visibleTabs, id: \.self) { t in
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
        switch tab {
        case .rhythm:
            RhythmInsightCard(
                activity: activity, detail: detail,
                history: history, age: age, isMale: isMale,
                hrZones: hrZones, insights: insights,
                cadenceSeries: cadenceSeries,
                hrSamples: hrSamples,
                formBaseline: formBaseline,
                formBackfillProgress: formBackfillProgress,
                workoutTypeFn: workoutTypeFn
            )
        case .form:
            let formCadence: Int? = {
                guard workoutTypeFn?(activity.id) == .interval,
                      let segs = detail?.intervalSegments else { return detail?.avgCadence }
                let cads = segs.filter { $0.stepLabel == "운동" }.compactMap { $0.avgCadence }
                guard !cads.isEmpty else { return detail?.avgCadence }
                return Int((Double(cads.reduce(0, +)) / Double(cads.count)).rounded())
            }()
            let hasFormGap: Bool = {
                let cal = Calendar.current
                guard let threeMonthsAgo = cal.date(byAdding: .month, value: -3, to: activity.date) else { return false }
                let recent = history
                    .filter { $0.type == .running && $0.date >= threeMonthsAgo && $0.date <= activity.date }
                    .sorted { $0.date < $1.date }
                for i in 0..<(recent.count - 1) {
                    let gap = cal.dateComponents([.day], from: recent[i].date, to: recent[i + 1].date).day ?? 0
                    if gap >= 14 { return true }
                }
                return false
            }()
            RunFormCardView(
                activity: activity,
                splits: detail?.splits ?? [],
                avgCadence: formCadence,
                avgStrideLength: detail?.avgStrideLength,
                avgGroundContactTime: detail?.avgGroundContactTime,
                avgVerticalOscillation: detail?.avgVerticalOscillation,
                baseline: formBaseline,
                workoutType: workoutTypeFn?(activity.id) ?? .general,
                intervalSegments: detail?.intervalSegments ?? [],
                hrSamples: hrSamples,
                typicalDistanceKm: typicalRunDistanceKm,
                heatModel: heatModel,
                formShifts: formShifts,
                hasRecentGap: hasFormGap,
                weatherSnapshot: weatherSnapshot,
                historicalTemperatures: history.compactMap { $0.temperatureC }
            )
        case .performance:
            PerformanceInsightCard(
                activity: activity, detail: detail,
                history: history, age: age, isMale: isMale,
                insights: insights,
                workoutTypeFn: workoutTypeFn,
                hrZones: hrZones,
                hrZonesFn: hrZonesFn,
                isBackfilling: isBackfilling,
                isClassifying: isClassifying,
                effortIndex: effortIndex
            )
        case .race:
            RaceInsightCard(
                activity: activity, detail: detail,
                age: age, isMale: isMale,
                confirmedRace: confirmedRace,
                confirmedRaces: confirmedRaces,
                history: history,
                raceDetailFn: raceDetailFn
            )
        }
    }

    private var disclaimer: some View {
        let L = AppLanguage.shared
        return VStack(alignment: .leading, spacing: 6) {
            Text(L.s(
                "참고용 피트니스 인사이트입니다. 연령대 평균과 추정 최대심박은 개인차가 큰 추정치이며 의학적 판단이 아니에요. 유산소 피트니스 기준은 FRIEND(Fitness Registry and Importance of Exercise National Database)를 따릅니다.",
                "Reference-only fitness insights. Age-group norms and estimated max HR are rough estimates with high individual variation and are not medical advice. Cardio fitness norms follow FRIEND (Fitness Registry and Importance of Exercise National Database)."
            ))
            // L-2: 강도 분포 참고선의 근거와 한계 — 퍼포먼스 탭에서만. 기존 각주와 같은 크기·색, 강조 없음.
            if tab == .performance {
                Text(L.s(
                    "강도 분포의 점선은 지구력 종목 선수들에게서 반복 관찰된 분포입니다(저강도 80% · 중간 0~5% · 고강도 15~20%). 낮은 강도는 부담이 적어 오래 쌓을 수 있고, 높은 강도는 최대 능력을 올립니다. 가운데는 회복 부담에 비해 얻는 것이 적다고 알려져 있어요.\n\n주간 훈련량이 많은 선수를 관찰한 값이라 목표가 아니라 참고선입니다. 구간은 첫 젖산 역치(AT1)와 두 번째 역치(AT2)로 나눴고, 두 값은 안정시 심박과 추정 최대심박으로 계산한 추정치입니다.",
                    "The dotted lines in the intensity distribution show a pattern repeatedly observed in endurance athletes (low 80% · mid 0–5% · high 15–20%). Low intensity is easy to accumulate with little strain; high intensity raises maximal capacity. The middle is known to return less for its recovery cost.\n\nThese values come from athletes with high weekly volume, so they are a reference, not a target. The bands are split at the first lactate threshold (AT1) and the second (AT2), both estimated from resting HR and an age-estimated max HR."
                ))
            }
        }
        .font(.system(size: 9.5))
        .foregroundStyle(Color.secondary)
        .lineSpacing(2)
    }
}

// MARK: - HR Time Series View

private struct HRTimeSeriesView: View {
    let samples: [(offset: TimeInterval, bpm: Int)]
    var zones: [HRZoneData] = []

    private func movingMedian(_ data: [Int], window: Int) -> [Double] {
        guard !data.isEmpty else { return [] }
        return data.indices.map { i in
            let lo = max(0, i - window / 2)
            let hi = min(data.count - 1, i + window / 2)
            let slice = data[lo...hi].sorted()
            let m = slice.count / 2
            return slice.count % 2 == 0 && slice.count > 1
                ? Double(slice[m - 1] + slice[m]) / 2
                : Double(slice[m])
        }
    }

    private func movingAverage(_ data: [Double], window: Int) -> [Double] {
        guard !data.isEmpty else { return [] }
        return data.indices.map { i in
            let lo = max(0, i - window / 2)
            let hi = min(data.count - 1, i + window / 2)
            let slice = data[lo...hi]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    private func zoneColor(for bpm: Double) -> Color {
        guard !zones.isEmpty else { return Color(hex: "FF6B6B") }
        for z in zones.sorted(by: { $0.id < $1.id }) {
            if bpm <= Double(z.maxBPM) { return IC.zone(z.id) }
        }
        return IC.zone(5)
    }

    var body: some View {
        guard samples.count >= 5 else {
            return AnyView(
                Text(AppLanguage.shared.s("심박 데이터 없음", "No HR data"))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        // 2단 평활화: 이동 중앙값(9) → 이동 평균(25)
        let rawBPM = samples.map(\.bpm)
        let smoothed = movingAverage(movingMedian(rawBPM, window: 9), window: 25)

        // 오프셋과 결합 후 최대 200개로 다운샘플 (평활화 후 축소)
        var pts: [(offset: TimeInterval, bpm: Double)] = zip(samples.map(\.offset), smoothed)
            .map { (offset: $0, bpm: $1) }
        if pts.count > 200 {
            let step = Double(pts.count - 1) / 199.0
            pts = (0..<200).map { pts[Int((Double($0) * step).rounded())] }
        }

        let minBPM = smoothed.min() ?? 0
        let maxBPM = smoothed.max() ?? 1
        let valRange = max(1.0, maxBPM - minBPM)
        let totalDur = max(1.0, pts.last?.offset ?? 1)
        return AnyView(
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let xPad: CGFloat = 22
                let chartW = w - xPad
                let chartH = h - 14

                // 축선
                var xAxisPath = Path()
                xAxisPath.move(to: CGPoint(x: xPad, y: chartH))
                xAxisPath.addLine(to: CGPoint(x: w, y: chartH))
                ctx.stroke(xAxisPath, with: .color(.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 0.8))
                var yAxisPath = Path()
                yAxisPath.move(to: CGPoint(x: xPad, y: 0))
                yAxisPath.addLine(to: CGPoint(x: xPad, y: chartH))
                ctx.stroke(yAxisPath, with: .color(.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 0.8))

                // 화면 좌표 계산
                let cpts: [(x: CGFloat, y: CGFloat, bpm: Double)] = pts.map { s in
                    let x = xPad + CGFloat(s.offset / totalDur) * chartW
                    let y = chartH - CGFloat((s.bpm - minBPM) / valRange) * chartH
                    return (x: x, y: y, bpm: s.bpm)
                }

                // Catmull-Rom → 베지어 변환, 구간별 존 색
                if cpts.count >= 2 {
                    for i in 0..<(cpts.count - 1) {
                        let p0 = cpts[max(0, i - 1)]
                        let p1 = cpts[i]
                        let p2 = cpts[i + 1]
                        let p3 = cpts[min(cpts.count - 1, i + 2)]
                        let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 5,
                                          y: p1.y + (p2.y - p0.y) / 5)
                        let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 5,
                                          y: p2.y - (p3.y - p1.y) / 5)
                        var seg = Path()
                        seg.move(to: CGPoint(x: p1.x, y: p1.y))
                        seg.addCurve(to: CGPoint(x: p2.x, y: p2.y),
                                     control1: cp1, control2: cp2)
                        ctx.stroke(seg, with: .color(zoneColor(for: p1.bpm)),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    }
                }

                // 끝점 마커
                if let last = cpts.last {
                    let dotR: CGFloat = 3
                    ctx.fill(Path(ellipseIn: CGRect(x: last.x - dotR, y: last.y - dotR,
                                                     width: dotR * 2, height: dotR * 2)),
                             with: .color(zoneColor(for: last.bpm)))
                }

                // Y축 라벨
                ctx.draw(Text("\(Int(maxBPM.rounded()))").font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.70)),
                    at: CGPoint(x: xPad - 3, y: 0), anchor: .topTrailing)
                ctx.draw(Text("\(Int(minBPM.rounded()))").font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.70)),
                    at: CGPoint(x: xPad - 3, y: chartH), anchor: .bottomTrailing)

                // X축 라벨
                let fmt: (TimeInterval) -> String = { t in
                    let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
                }
                ctx.draw(Text("0:00").font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.70)),
                    at: CGPoint(x: xPad, y: h), anchor: .bottomLeading)
                ctx.draw(Text(fmt(totalDur / 2)).font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.70)),
                    at: CGPoint(x: xPad + chartW / 2, y: h), anchor: .bottom)
                ctx.draw(Text(fmt(totalDur)).font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.70)),
                    at: CGPoint(x: w, y: h), anchor: .bottomTrailing)
            }
        )
    }
}

// MARK: - Week Strip

private struct WeekStripView: View {
    let activity: Activity
    let history: [Activity]

    private let cellSize: CGFloat = 12
    private let gap: CGFloat = 3
    private let streakColor = Color(hex: "FF9F0A")

    private struct DayInfo: Identifiable {
        let id: Int
        let km: Double
        let isFuture: Bool
        let isToday: Bool
    }

    private var dayInfos: [DayInfo] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: activity.date)
        let weekday = cal.component(.weekday, from: today) // 1=Sun...7=Sat
        let daysFromMonday = (weekday + 5) % 7             // 0=Mon...6=Sun
        guard let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: today) else { return [] }
        var kmByDay: [Date: Double] = [:]
        for act in history {
            let day = cal.startOfDay(for: act.date)
            kmByDay[day, default: 0] += act.distance / 1000
        }
        kmByDay[today, default: 0] += activity.distance / 1000
        return (0..<7).compactMap { i -> DayInfo? in
            guard let day = cal.date(byAdding: .day, value: i, to: monday) else { return nil }
            return DayInfo(id: i,
                           km: kmByDay[day] ?? 0,
                           isFuture: day > today,
                           isToday: day == today)
        }
    }

    private func cellColor(km: Double, isFuture: Bool) -> Color {
        if isFuture { return Color.white.opacity(0.04) }
        if km == 0  { return streakColor.opacity(0.10) }
        if km < 3   { return streakColor.opacity(0.32) }
        if km < 6   { return streakColor.opacity(0.56) }
        if km < 10  { return streakColor.opacity(0.80) }
        return streakColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: gap) {
                ForEach(dayInfos) { info in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cellColor(km: info.km, isFuture: info.isFuture))
                        .frame(width: cellSize, height: cellSize)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(info.isToday ? Color.white.opacity(0.70) : Color.clear,
                                        lineWidth: 1)
                        )
                }
            }
            HStack(spacing: gap) {
                ForEach(dayInfos) { info in
                    Text(info.isToday ? AppLanguage.shared.s("오늘", "Today") : "")
                        .font(.system(size: 6, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: cellSize)
                }
            }
        }
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
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    var formBaseline: RunningFormBaseline? = nil
    var formBackfillProgress: (done: Int, total: Int)? = nil
    var workoutTypeFn: ((UUID) -> WorkoutType?)? = nil

    @State private var heroBadge: AchievementBadgeKind? = nil
    @State private var heroBadgeLoaded = false
    @State private var _wtfParts: [(text: String, color: Color)]? = nil
    #if DEBUG
    nonisolated(unsafe) private static var _formKindLogLastId: UUID? = nil
    nonisolated(unsafe) private static var _distCtxLogLastId: UUID? = nil
    #endif

    // 직전 4주 러닝 1회 평균 거리(km). 거리 문맥 판단에 사용.
    private var typicalRunDistanceKm: Double? {
        let fourWeeksAgo = Calendar.current.date(byAdding: .day, value: -28, to: activity.date) ?? .distantPast
        let recent = history.filter {
            $0.type == .running && $0.id != activity.id &&
            $0.date >= fourWeeksAgo && $0.date < activity.date
        }
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0.0) { $0 + $1.distance } / Double(recent.count) / 1000.0
    }

    private var rhythmIsLongDistanceContext: Bool {
        let wt = workoutTypeFn?(activity.id) ?? .general
        return isLongDistanceRunContext(activity: activity, workoutType: wt,
                                        recentAvgDistanceKm: typicalRunDistanceKm)
    }

    var body: some View {
        let hasRhythmRow = !hrZones.filter({ $0.fraction > 0.01 }).isEmpty
            || detail?.avgCadence != nil
            || (vo2Info != nil && detail?.vo2Max != nil)
            || hrSamples.count >= 5
        return VStack(alignment: .leading, spacing: 14) {
            heroSection
            divider
            kpiRow
            if hasRhythmRow {
                divider
                rhythmRow
            }
            if let line = oneLiner {
                divider
                oneLiner(text: line, bg: IC.greenBg, fg: IC.greenText, accent: IC.green)
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            #if DEBUG
            logIntervalSegments()
            if Self._distCtxLogLastId != activity.id {
                Self._distCtxLogLastId = activity.id
                let distKm = activity.distance / 1000
                let typical = typicalRunDistanceKm
                let typicalStr = typical.map { String(format: "%.1f", $0) } ?? "-"
                let pctStr: String = typical.map { t in t > 0 ? "\(Int(distKm / t * 100 + 0.5))%" : "-" } ?? "-"
                let wt = workoutTypeFn?(activity.id) ?? .general
                let msg = rhythmIsLongDistanceContext ? "→ 문맥 적용 (지표 배지·해석 생략)" : "→ 미적용"
                print("[폼:거리문맥] \(String(format: "%.1f", distKm))km / 4주평균 \(typicalStr)km (\(pctStr)) type=\(wt.koreanLabel)  \(msg)")
            }
            #endif
            guard !heroBadgeLoaded else { return }
            heroBadge = computeAchievementBadge(activity: activity, history: history)
            heroBadgeLoaded = true
            _wtfParts = buildWorkoutTypeFormParts()
        }
        .onChange(of: formBaseline?.computedAt) { _, _ in
            _wtfParts = buildWorkoutTypeFormParts()
        }
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
        let coords = detail?.routeCoordinates ?? []
        let hasRoute = coords.count >= 2
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                WeekStripView(activity: activity, history: history)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(kmStr)
                        .font(cardNumFont(40))
                        .tracking(-1.6)
                    Text("km").font(.system(size: 16)).foregroundStyle(IC.label)
                }
                .foregroundStyle(Color.white)
                if let ctx = distanceContext {
                    Text(ctx).font(.system(size: 10)).foregroundStyle(IC.green)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                // @State 미설정(ImageRenderer) 시 인라인 계산으로 폴백
                if let badge = heroBadge ?? computeAchievementBadge(activity: activity, history: history) {
                    AchievementBadgeView(badge: badge)
                }
                if hasRoute {
                    StampRouteArt(
                        coords: coords,
                        lineWidth: 2.2,
                        color: Color(hex: "5CE08A"),
                        casingColor: Theme.cardBackground
                    )
                    .frame(width: 52, height: 62)
                }
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
            if let workCad = intervalWorkCadence {
                KPICell(label: AppLanguage.shared.s("케이던스 (전력 구간)", "Cadence (work)"),
                        value: "\(Int(workCad.rounded()))", unit: "spm", color: IC.cadCyan)
            } else if let cad = detail?.avgCadence {
                KPICell(label: AppLanguage.shared.s("케이던스", "Cadence"),
                        value: "\(cad)", unit: "spm", color: IC.cadCyan)
            } else {
                KPICell(label: AppLanguage.shared.s("케이던스", "Cadence"),
                        value: "--", color: .secondary)
            }
        }
    }

    @ViewBuilder
    private var rhythmRow: some View {
        let visibleZones = hrZones.filter { $0.fraction > 0.01 }
        let hasZones = !visibleZones.isEmpty
        let hasHR = hrSamples.count >= 5
        let sep = Color.white.opacity(0.1)

        // 2×2 그리드: [심박존 | 심박수] / [케이던스 | 유산소]
        VStack(spacing: 0) {
            Color.clear.frame(height: 0).onAppear {
                #if DEBUG
                if let bl = formBaseline {
                    if let band = bl.band(for: activity) {
                        let hasBl = bl.bands[band] != nil
                        let blMark = hasBl ? "" : " ⚠ 기준선 없음"
                        print("[Baseline:카드] formBaseline=있음, band=\(band.rawValue)\(blMark), summaryParts=\(formSummaryParts?.count ?? -1)")
                    } else if let pace = activity.paceSecPerKm {
                        func pf(_ s: Double) -> String { String(format: "%d'%02d\"", Int(s)/60, Int(s)%60) }
                        let cap = bl.cutoffs.verySlowMax < .greatestFiniteMagnitude ? pf(bl.cutoffs.verySlowMax) : "∞"
                        print("[Baseline:카드] band=범위밖 (\(pf(pace)) > 상한 \(cap)) — 폼 판정 생략")
                    }
                } else {
                    print("[Baseline:카드] formBaseline=nil, summaryParts=\(formSummaryParts?.count ?? -1)")
                }
                #endif
            }
            // 상단 행: 심박존(좌) + 심박수 HR 시계열(우)
            HStack(alignment: .center, spacing: 0) {
                // 심박존 도넛
                VStack(alignment: .center, spacing: 4) {
                    if hasZones {
                        ZoneDonutView(zones: hrZones)
                            .frame(width: 100, height: 100)
                        Color.clear.frame(height: 8)
                        Text(zoneVerdictLabel)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(zoneVerdictColor)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

                // 세로 구분선
                Rectangle().fill(sep).frame(width: 0.5)

                // 심박수 HR 시계열 + 판정 문구
                VStack(alignment: .center, spacing: 3) {
                    if hasHR {
                        HRTimeSeriesView(
                            samples: hrSamples,
                            zones: hasZones ? hrZones : []
                        )
                        .padding(.horizontal, 6)
                        .frame(height: 86)
                        if let v = hrVerdictText {
                            Text(v.text)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(v.color)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            // 가로 구분선
            Rectangle().fill(sep).frame(height: 0.5)

            // 하단 행: 케이던스(좌) + 유산소 VO2(우)
            HStack(alignment: .center, spacing: 0) {
                // 케이던스 게이지 + 기준 문구
                // 인터벌은 고강도 구간 평균을 바늘에 반영, 개인 비교 문구 숨김
                // 장거리 문맥이면 formBaseline을 nil로 전달 → 바늘이 절대 기준(160–180)으로만 판단 (흰색)
                VStack(alignment: .center, spacing: 4) {
                    let displayCad = intervalWorkCadence.map { Int($0.rounded()) } ?? detail?.avgCadence
                    if let cad = displayCad {
                        let gaugeBaseline: RunningFormBaseline? = rhythmIsLongDistanceContext ? nil : formBaseline
                        CadenceRPMGaugeView(cadence: cad, formBaseline: gaugeBaseline, activity: activity,
                                            isInterval: workoutTypeFn?(activity.id) == .interval)
                        Color.clear.frame(height: 8)
                        Text(cadenceBottomLabel)
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                        // 장거리 문맥이면 상대 평가 문구 생략 (절대 기준 위반 시 cadenceVerdictInfo가 처리)
                        if workoutTypeFn?(activity.id) != .interval && !rhythmIsLongDistanceContext {
                            let v = cadenceVerdictInfo(cad: cad)
                            Text(v.text)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(v.color)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

                // 세로 구분선
                Rectangle().fill(sep).frame(width: 0.5)

                // 유산소 VO2 게이지 + FRIEND DB + 등급 문구
                VStack(alignment: .center, spacing: 4) {
                    if let info = vo2Info, let vo2 = detail?.vo2Max {
                        VO2RPMGaugeView(fi: info, vo2: vo2)
                        Color.clear.frame(height: 8)
                        let sub = vo2SubLabel(fi: info, vo2: vo2)
                        Text(sub.text)
                            .font(.system(size: 8.5))
                            .foregroundStyle(sub.color)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            // 폼 종합 요약 — 백필 중이면 진행 표시, 아니면 기준선 기반 요약 + 종류별 판정
            if let progress = formBackfillProgress {
                Rectangle().fill(sep).frame(height: 0.5)
                formBackfillProgressLine(progress)
            } else {
                let summaryParts = formSummaryParts
                let typeParts = workoutTypeFormParts
                if summaryParts != nil || typeParts != nil {
                    Rectangle().fill(sep).frame(height: 0.5)
                    if let p = summaryParts { formSummaryLine(parts: p) }
                    if let p = typeParts   { formSummaryLine(parts: p) }
                }
            }
        }
    }

    // MARK: Form Summary

    /// 4지표 종합 요약 파트 목록. 기준선 없으면 nil → 줄 전체 숨김.
    /// 수직진폭은 판정 제외 (구간 간 방향성 없음).
    private var formSummaryParts: [(text: String, color: Color)]? {
        // 인터벌: 전체 평균 페이스가 회복 구간을 포함해 구간을 대표하지 못함 → PaceBand 기반 요약 전체 생략
        // 대회: 훈련 기준선 비교 전체 생략 (대회 탭의 RaceInsightCard가 전용 분석 담당)
        guard workoutTypeFn?(activity.id) != .interval,
              workoutTypeFn?(activity.id) != .race else { return nil }
        guard let bl = formBaseline,
              let bb = bl.baseline(for: activity),
              let det = detail else { return nil }

        let L = AppLanguage.shared

        // 장거리 문맥: 케이던스 절대 기준(160) 위반이 아니면 거리 문맥 한 줄로 대체
        if rhythmIsLongDistanceContext {
            let hasAbsViolation = det.avgCadence.map { $0 < 160 } ?? false
            if !hasAbsViolation {
                let distKm = activity.distance / 1000
                let distKmStr = String(format: "%.0f", distKm)
                // 전반/후반 평균 계산 — 실제 변화를 사실 서술
                let fullSplits = det.splits.filter { $0.distanceM >= 900 }
                let splitMid = fullSplits.count / 2
                let fHalf = Array(fullSplits.prefix(splitMid))
                let sHalf = Array(fullSplits.suffix(fullSplits.count - splitMid))
                var korParts: [String] = []
                var engParts: [String] = []
                let fCads = fHalf.compactMap { $0.avgCadence }
                let sCads = sHalf.compactMap { $0.avgCadence }
                if !fCads.isEmpty, !sCads.isEmpty {
                    let fc = Int((Double(fCads.reduce(0, +)) / Double(fCads.count)).rounded())
                    let sc = Int((Double(sCads.reduce(0, +)) / Double(sCads.count)).rounded())
                    korParts.append("케이던스 \(fc)→\(sc)spm")
                    engParts.append("cadence \(fc)→\(sc) spm")
                }
                let fSLs = fHalf.compactMap { $0.avgStrideLength }
                let sSLs = sHalf.compactMap { $0.avgStrideLength }
                if !fSLs.isEmpty, !sSLs.isEmpty {
                    let fs2 = fSLs.reduce(0, +) / Double(fSLs.count)
                    let ss2 = sSLs.reduce(0, +) / Double(sSLs.count)
                    korParts.append("보폭 \(String(format: "%.2f", fs2))→\(String(format: "%.2f", ss2))m")
                    engParts.append("stride \(String(format: "%.2f", fs2))→\(String(format: "%.2f", ss2)) m")
                }
                let text: String
                if !korParts.isEmpty {
                    if let typical = typicalRunDistanceKm, distKm > typical * 1.30 {
                        let delta = distKm - typical
                        text = L.s(
                            "평소보다 \(String(format: "%.1f", delta))km 긴 러닝이에요. \(korParts.joined(separator: ", "))로 줄었어요.",
                            "This run is \(String(format: "%.1f", delta)) km longer than usual — \(engParts.joined(separator: ", ")).")
                    } else {
                        text = L.s(
                            "\(distKmStr)km를 뛰면서 \(korParts.joined(separator: ", "))로 줄었어요.",
                            "\(distKmStr) km run — \(engParts.joined(separator: ", ")).")
                    }
                } else {
                    let cadStr = det.avgCadence.map { "\($0)" } ?? "--"
                    text = det.avgStrideLength.map {
                        L.s("케이던스 \(cadStr)spm, 보폭 \(String(format: "%.2f", $0))m로 달렸어요.",
                            "Ran with cadence \(cadStr) spm and stride \(String(format: "%.2f", $0)) m.")
                    } ?? L.s("케이던스 \(cadStr)spm으로 달렸어요.", "Ran with cadence \(cadStr) spm.")
                }
                return [(text: text, color: Color.white.opacity(0.75))]
            }
        }

        struct Dev { let label: String; let magnitude: Double; let isAbsWarn: Bool }
        var devs: [Dev] = []

        // 케이던스
        if let stat = bb.cadence, let cad = det.avgCadence {
            let c = Double(cad)
            if c < stat.lower || c > stat.upper {
                let delta = Int((c - stat.median).rounded())
                let sign = delta >= 0 ? "+" : ""
                let mag = abs(c - stat.median) / max(stat.sd, 1)
                devs.append(Dev(
                    label: L.s("케이던스 \(sign)\(delta)spm", "Cadence \(sign)\(delta)spm"),
                    magnitude: mag, isAbsWarn: c < 160
                ))
            }
        }

        // 보폭
        if let stat = bb.strideLength, let sl = det.avgStrideLength {
            if sl < stat.lower || sl > stat.upper {
                let delta = sl - stat.median
                let sign = delta >= 0 ? "+" : ""
                let mag = abs(delta) / max(stat.sd, 0.001)
                devs.append(Dev(
                    label: L.s("보폭 \(sign)\(String(format: "%.2f", delta))m",
                                "Stride \(sign)\(String(format: "%.2f", delta))m"),
                    magnitude: mag, isAbsWarn: false
                ))
            }
        }

        // 지면접촉 (수직진폭 제외)
        if let stat = bb.groundContact, let gc = det.avgGroundContactTime {
            if gc < stat.lower || gc > stat.upper {
                let delta = Int((gc - stat.median).rounded())
                let sign = delta >= 0 ? "+" : ""
                let mag = abs(gc - stat.median) / max(stat.sd, 1)
                devs.append(Dev(
                    label: L.s("지면접촉 \(sign)\(delta)ms", "Contact \(sign)\(delta)ms"),
                    magnitude: mag, isAbsWarn: gc > 300
                ))
            }
        }

        devs.sort { $0.magnitude > $1.magnitude }
        let top = Array(devs.prefix(2))

        let interp = formInterpretation(bb: bb, det: det)

        var parts: [(text: String, color: Color)] = []
        parts.append((L.s("비슷한 페이스 기준", "Similar pace baseline"), Color.white.opacity(0.55)))

        for dev in top {
            parts.append((" · ", Color.white.opacity(0.55)))
            let c: Color = dev.isAbsWarn ? Color(hex: "FF6B6B") : Color.white.opacity(0.75)
            parts.append((dev.label, c))
        }

        parts.append((" · ", Color.white.opacity(0.55)))
        parts.append(interp)

        return parts
    }

    /// 폼 해석 문구: 가장 의미 있는 신호 하나를 우선순위대로 반환.
    /// 수직진폭 제외. 케이던스 절대 기준(160 미만)은 항상 최우선.
    private func formInterpretation(bb: BandBaseline, det: ActivityDetail) -> (text: String, color: Color) {
        let L = AppLanguage.shared

        // 1. 케이던스 절대 기준 (최우선)
        if let cad = det.avgCadence, cad < 160 {
            return (L.s("보폭이 큰 편이에요", "Wide stride tendency"), Color(hex: "FF6B6B"))
        }

        // 2. 지면접촉 (가장 민감한 상대 신호)
        if let stat = bb.groundContact, let gc = det.avgGroundContactTime {
            let delta = gc - stat.median
            if delta <= -10 { return (L.s("탄력 있게 뛰었어요", "Springy stride today"), Color(hex: "7FD98A")) }
            if delta >= 10  { return (L.s("다소 무거운 날이었어요", "Heavier than usual"), Color.white.opacity(0.75)) }
        }

        // 3. 케이던스 상대 신호
        if let stat = bb.cadence, let cad = det.avgCadence {
            let delta = Double(cad) - stat.median
            if delta >= 3  { return (L.s("발걸음이 경쾌했어요", "Lively footstrike"), Color(hex: "7FD98A")) }
            if delta <= -3 { return (L.s("발걸음이 평소보다 느렸어요", "Slower turnover"), Color.white.opacity(0.75)) }
        }

        // 4. 보폭
        if let stat = bb.strideLength, let sl = det.avgStrideLength {
            let delta = sl - stat.median
            if delta >= 0.03  { return (L.s("보폭이 시원하게 나왔어요", "Great stride length"), Color(hex: "7FD98A")) }
            if delta <= -0.03 { return (L.s("보폭이 짧았어요", "Shorter stride"), Color.white.opacity(0.75)) }
        }

        // 5. 심박
        if let stat = bb.heartRate, let hr = activity.avgHeartRate {
            let delta = Double(hr) - stat.median
            if delta <= -4 { return (L.s("같은 페이스인데 심박이 낮았어요", "Lower HR for this pace"), Color(hex: "7FD98A")) }
            if delta >= 5  { return (L.s("평소보다 심박이 높았어요", "Higher HR than usual"), Color.white.opacity(0.75)) }
        }

        return (L.s("폼이 평소대로 안정적이었어요", "Form right on baseline"), Color(hex: "7FD98A"))
    }

    /// 러닝 종류별 전·후반 폼 판정. splits 4개 미만이거나 판정 불필요 종류면 nil.
    /// SplitData에 per-split ground contact가 없으므로 케이던스 드롭을 형태 지표로 사용.
    private var workoutTypeFormParts: [(text: String, color: Color)]? { _wtfParts ?? buildWorkoutTypeFormParts() }

    private func buildWorkoutTypeFormParts() -> [(text: String, color: Color)]? {
        guard let det = detail else { return nil }
        // workoutTypeFn 우선, nil이면 detail.workoutType으로 직접 폴백
        // (ImageRenderer는 .onAppear 없이 캐시 미스 가능성 → detail.workoutType이 항상 안전)
        let wt = workoutTypeFn?(activity.id) ?? det.workoutType
        // 인터벌은 Form 탭의 IntervalFatigueCard에서 처리 — Rhythm 탭 종류별 판정 생략
        guard wt != .interval else { return nil }
        // 대회: RaceInsightCard가 전용 분석 담당
        guard wt != .race else { return nil }

        let L = AppLanguage.shared
        let fullSplits = det.splits.filter { $0.distanceM >= 900 }
        let typePrefix: (text: String, color: Color) = (wt.koreanLabel + " · ", Color.white.opacity(0.5))

        #if DEBUG
        func pf(_ s: Double) -> String { String(format: "%d'%02d\"", Int(s)/60, Int(s)%60) }
        let wtName = wt.koreanLabel
        // 같은 activity.id 로 여러 탭 인스턴스가 중복 호출될 때 1회만 출력
        let _fkDbg: Bool = {
            if Self._formKindLogLastId == activity.id { return false }
            Self._formKindLogLastId = activity.id
            return true
        }()
        func print(_ msg: String) { if _fkDbg { Swift.print(msg) } }
        #endif

        func halfAvgPace(_ s: [SplitData]) -> Double? {
            let p = s.map(\.paceSecPerKm); guard !p.isEmpty else { return nil }
            return p.reduce(0, +) / Double(p.count)
        }
        func halfAvgCadence(_ s: [SplitData]) -> Double? {
            let c = s.compactMap(\.avgCadence).map(Double.init); guard !c.isEmpty else { return nil }
            return c.reduce(0, +) / Double(c.count)
        }
        func halfAvgGCT(_ s: [SplitData]) -> Double? {
            let g = s.compactMap(\.avgGroundContactTime); guard !g.isEmpty else { return nil }
            return g.reduce(0, +) / Double(g.count)
        }

        switch wt {
        case .buildUp:
            guard fullSplits.count >= 4 else {
                #if DEBUG
                print("[Form:종류] 생략 — splits \(fullSplits.count)개 (4개 미만), type=\(wtName)")
                #endif
                return nil
            }
            let half = fullSplits.count / 2
            let second = Array(fullSplits.suffix(fullSplits.count - half))
            guard let sp = halfAvgPace(second),
                  let sc = halfAvgCadence(second) else {
                #if DEBUG
                print("[Form:종류] 생략 — 후반 페이스/케이던스 없음, type=\(wtName)")
                #endif
                return nil
            }
            guard let baseline = formBaseline else {
                #if DEBUG
                print("[Form:종류] 생략 — baseline 없음, type=\(wtName)")
                #endif
                return nil
            }
            guard let band = baseline.cutoffs.band(of: sp) else {
                #if DEBUG
                print("[Form:종류] 생략 — 후반 페이스 범위밖, type=\(wtName)")
                #endif
                return nil
            }
            guard let bandBl = baseline.bands[band],
                  let cadStat = bandBl.cadence,
                  bandBl.sampleCount >= FormBaselineEngine.minSamples else {
                #if DEBUG
                print("[Form:종류] 생략 — 후반 구간 baseline 부족, type=\(wtName) band=\(band.rawValue)")
                #endif
                return nil
            }
            let expectedCad = cadStat.median
            let result: (text: String, color: Color)
            if sc >= expectedCad {
                result = (L.s("후반에 발걸음까지 끌어올렸어요", "Cadence lifted in the second half — great buildup"), Color(hex: "7FD98A"))
            } else if sc <= expectedCad - 2 {
                result = (L.s("페이스를 주로 보폭으로 올렸어요. 발걸음을 함께 올리면 무릎 부담이 줄어요", "Stride-led buildup — adding cadence reduces knee load"), Color(hex: "FFD166"))
            } else {
                result = (L.s("평소 패턴대로 페이스를 올렸어요", "Paced up in your usual pattern"), Color.white.opacity(0.75))
            }
            #if DEBUG
            print("[Form:종류] type=\(wtName) 후반P=\(pf(sp)) 구간=\(band.rawValue) 기대C=\(Int(expectedCad)) 실제C=\(Int(sc)) → \"\(result.text)\"")
            #endif
            return [typePrefix, result]

        case .tempo:
            guard fullSplits.count >= 4 else {
                #if DEBUG
                print("[Form:종류] 생략 — splits \(fullSplits.count)개 (4개 미만), type=\(wtName)")
                #endif
                return nil
            }
            let half = fullSplits.count / 2
            let first = Array(fullSplits.prefix(half))
            let second = Array(fullSplits.suffix(fullSplits.count - half))
            let result: (text: String, color: Color)
            if let fg = halfAvgGCT(first), let sg = halfAvgGCT(second) {
                let gctRise = sg - fg
                if gctRise <= -7 {
                    result = (L.s("후반으로 갈수록 지면접촉이 짧아졌어요. 템포 페이스가 잘 맞았어요",
                                  "Ground contact shortened — tempo pace was well-matched"), Color(hex: "7FD98A"))
                } else if gctRise < 8 {
                    result = (L.s("후반까지 폼이 흔들리지 않았어요. 역치 페이스가 몸에 익었어요", "Form held — tempo pace feels natural"), Color(hex: "7FD98A"))
                } else {
                    let rise = Int(gctRise.rounded())
                    result = (L.s("후반에 지면접촉이 +\(rise)ms 늘었어요. 템포 페이스가 살짝 빠를 수 있어요",
                                  "Ground contact +\(rise)ms in second half — pace may be slightly high"), Color(hex: "FFD166"))
                }
                #if DEBUG
                let fp0 = halfAvgPace(first).map { pf($0) } ?? "-"
                let sp0 = halfAvgPace(second).map { pf($0) } ?? "-"
                let sign = gctRise >= 0 ? "+" : ""
                print("[Form:종류] type=\(wtName) splits=\(fullSplits.count) 전반P=\(fp0) 후반P=\(sp0) 전반GCT=\(Int(fg)) 후반GCT=\(Int(sg)) 차이=\(sign)\(Int(gctRise.rounded()))ms (GCT기준) → \"\(result.text)\"")
                #endif
            } else if let fc = halfAvgCadence(first), let sc = halfAvgCadence(second) {
                let cadDrop = fc - sc
                if cadDrop < 2 {
                    result = (L.s("후반까지 폼이 흔들리지 않았어요. 역치 페이스가 몸에 익었어요", "Form held — tempo pace feels natural"), Color(hex: "7FD98A"))
                } else {
                    let drop = Int(cadDrop.rounded())
                    result = (L.s("후반에 발걸음이 \(drop)spm 줄었어요. 템포 페이스가 살짝 빠를 수 있어요",
                                  "Cadence dropped \(drop)spm — pace may be slightly high"), Color(hex: "FFD166"))
                }
                #if DEBUG
                let fp0 = halfAvgPace(first).map { pf($0) } ?? "-"
                let sp0 = halfAvgPace(second).map { pf($0) } ?? "-"
                print("[Form:종류] type=\(wtName) splits=\(fullSplits.count) 전반P=\(fp0) 후반P=\(sp0) 전반C=\(Int(fc)) 후반C=\(Int(sc)) 차이=\(Int((fc-sc).rounded())) (케이던스 폴백·GCT없음) → \"\(result.text)\"")
                #endif
            } else {
                #if DEBUG
                print("[Form:종류] 생략 — GCT/케이던스 모두 없음, type=\(wtName)")
                #endif
                return nil
            }
            return [typePrefix, result]

        case .lsd, .longRun:
            guard fullSplits.count >= 4 else {
                #if DEBUG
                print("[Form:종류] 생략 — splits \(fullSplits.count)개 (4개 미만), type=\(wtName)")
                #endif
                return nil
            }
            let half = fullSplits.count / 2
            let first = Array(fullSplits.prefix(half))
            let second = Array(fullSplits.suffix(fullSplits.count - half))
            let result: (text: String, color: Color)
            if let fg = halfAvgGCT(first), let sg = halfAvgGCT(second) {
                let gctRise = sg - fg
                if gctRise <= -7 {
                    result = (L.s("장거리인데 후반으로 갈수록 지면접촉이 짧아졌어요", "Ground contact shortened through the long run"), Color(hex: "7FD98A"))
                } else if gctRise < 10 {
                    result = (L.s("장거리인데 후반까지 폼이 버텼어요", "Form held through the long run"), Color(hex: "7FD98A"))
                } else {
                    result = (L.s("후반에 폼이 조금 무거워졌어요", "Form got a bit heavier in the second half"), Color.white.opacity(0.75))
                }
                #if DEBUG
                let fp0 = halfAvgPace(first).map { pf($0) } ?? "-"
                let sp0 = halfAvgPace(second).map { pf($0) } ?? "-"
                let sign = gctRise >= 0 ? "+" : ""
                print("[Form:종류] type=\(wtName) splits=\(fullSplits.count) 전반P=\(fp0) 후반P=\(sp0) 전반GCT=\(Int(fg)) 후반GCT=\(Int(sg)) 차이=\(sign)\(Int(gctRise.rounded()))ms (GCT기준) → \"\(result.text)\"")
                #endif
            } else if let fc = halfAvgCadence(first), let sc = halfAvgCadence(second) {
                let cadDrop = fc - sc
                if cadDrop < 2 {
                    result = (L.s("장거리인데 후반까지 폼이 버텼어요", "Form held through the long run"), Color(hex: "7FD98A"))
                } else {
                    result = (L.s("후반에 폼이 조금 무거워졌어요", "Form got a bit heavier in the second half"), Color.white.opacity(0.75))
                }
                #if DEBUG
                let fp0 = halfAvgPace(first).map { pf($0) } ?? "-"
                let sp0 = halfAvgPace(second).map { pf($0) } ?? "-"
                print("[Form:종류] type=\(wtName) splits=\(fullSplits.count) 전반P=\(fp0) 후반P=\(sp0) 전반C=\(Int(fc)) 후반C=\(Int(sc)) 차이=\(Int((fc-sc).rounded())) (케이던스 폴백·GCT없음) → \"\(result.text)\"")
                #endif
            } else {
                #if DEBUG
                print("[Form:종류] 생략 — GCT/케이던스 모두 없음, type=\(wtName)")
                #endif
                return nil
            }
            return [typePrefix, result]

        case .interval:
            let allSegs = det.intervalSegments
            let workSegs = allSegs.filter { $0.stepLabel == "운동" }
            let cadences = workSegs.compactMap(\.avgCadence).map(Double.init)
            guard cadences.count >= 3 else {
                #if DEBUG
                if allSegs.isEmpty {
                    print("[Form:종류] type=\(wtName) 생략 — 세그먼트 없음")
                } else {
                    print("[Form:종류] type=\(wtName) 생략 — 고강도 구간 \(cadences.count)회 (3회 미만)")
                }
                #endif
                return nil
            }
            let n = cadences.count
            let mean = cadences.reduce(0, +) / Double(n)
            guard mean > 0 else { return nil }
            let sd = sqrt(cadences.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(n))

            // (A) 추세: 선형회귀 기울기(spm/회)
            let xMean = Double(n - 1) / 2
            let slopeNum = cadences.enumerated().reduce(0.0) { acc, e in
                acc + (Double(e.offset) - xMean) * (e.element - mean)
            }
            let slopeDen = cadences.enumerated().reduce(0.0) { acc, e in
                acc + (Double(e.offset) - xMean) * (Double(e.offset) - xMean)
            }
            let slope = slopeDen > 0 ? slopeNum / slopeDen : 0.0

            let result: (text: String, color: Color)
            let branch: String

            if slope <= -1.5 {
                result = (L.s("반복이 진행될수록 발걸음이 느려졌어요", "Cadence faded as reps progressed"), Color.white.opacity(0.75))
                branch = "(A) 기울기 하락"
            } else if slope >= 1.0 {
                result = (L.s("뒤로 갈수록 발걸음이 더 살아났어요", "Cadence grew stronger through the reps"), Color(hex: "7FD98A"))
                branch = "(A) 기울기 상승"
            } else if sd > 2.0 {
                // (B) 산포 — 추세 평탄할 때만
                result = (L.s("회차마다 발걸음 편차가 있었어요", "Cadence varied across reps"), Color.white.opacity(0.75))
                branch = "(B) 산포"
            } else {
                // (C) 수준 — baseline 최고 구간(fast) 중앙 케이던스와 비교
                let fastCadMedian: Double? = formBaseline.flatMap { bl in
                    guard let bandBl = bl.bands[.fast],
                          let stat = bandBl.cadence,
                          bandBl.sampleCount >= FormBaselineEngine.minSamples else { return nil }
                    return stat.median
                }
                if let ref = fastCadMedian {
                    let diff = Int((mean - ref).rounded())
                    if mean >= ref + 3 {
                        result = (L.s("\(n)회 내내 균일했고, 발걸음이 평소 최고보다 \(diff) spm 높았어요",
                                      "\(n) reps consistent — cadence \(diff) spm above personal best band"), Color(hex: "7FD98A"))
                        branch = "(C) 수준↑↑"
                    } else if mean >= ref {
                        result = (L.s("\(n)회 내내 균일했고, 평소 최고 수준까지 올렸어요",
                                      "\(n) reps consistent — matched personal best cadence band"), Color(hex: "7FD98A"))
                        branch = "(C) 수준↑"
                    } else if mean < ref - 2 {
                        result = (L.s("전력 구간인데 발걸음이 평소만큼 올라오지 않았어요",
                                      "Hard effort, but cadence didn't reach usual high"), Color.white.opacity(0.75))
                        branch = "(C) 수준↓"
                    } else {
                        result = (L.s("\(n)회 반복 내내 발걸음이 균일했어요", "Cadence consistent across \(n) reps"), Color(hex: "7FD98A"))
                        branch = "(C) 기준 내"
                    }
                } else {
                    result = (L.s("\(n)회 반복 내내 발걸음이 균일했어요", "Cadence consistent across \(n) reps"), Color(hex: "7FD98A"))
                    branch = "(C) baseline없음→폴백"
                }
            }
            #if DEBUG
            let fastRef = formBaseline.flatMap { $0.bands[.fast]?.cadence }.map { Int($0.median) } ?? -1
            print("[Form:종류] type=\(wtName) 구간=\(n)회 평균C=\(Int(mean)) SD=\(String(format: "%.1f", sd)) 기울기=\(String(format: "%.1f", slope))/회 최고구간중앙=\(fastRef) → \(branch) \"\(result.text)\"")
            #endif
            return [typePrefix, result]

        case .distanceRun:
            guard fullSplits.count >= 4 else {
                #if DEBUG
                print("[Form:종류] 생략 — splits \(fullSplits.count)개 (4개 미만), type=\(wtName)")
                #endif
                return nil
            }
            let half = fullSplits.count / 2
            let first = Array(fullSplits.prefix(half))
            let second = Array(fullSplits.suffix(fullSplits.count - half))
            guard let fp = halfAvgPace(first), let sp = halfAvgPace(second) else {
                #if DEBUG
                print("[Form:종류] 생략 — 페이스 splits 없음, type=\(wtName)")
                #endif
                return nil
            }
            let paceDelta = sp - fp
            var result: (text: String, color: Color)
            if paceDelta <= 0 {
                result = (L.s("후반에도 페이스가 떨어지지 않았어요", "Pace held through the finish"), Color(hex: "7FD98A"))
            } else if paceDelta <= 25 {
                result = (L.s("후반에 페이스가 \(Int(paceDelta.rounded()))초 떨어졌어요", "Pace slipped \(Int(paceDelta.rounded()))s in second half"), Color.white.opacity(0.75))
            } else {
                result = (L.s("후반 페이스가 많이 떨어졌어요. 초반이 빨랐을 수 있어요", "Big pace drop — may have gone out too fast"), Color(hex: "FFD166"))
            }
            // ⓪ GCT 개선 구절 — 페이스 하락이 있어도 접지 단축이면 덧붙임
            let fGCT = halfAvgGCT(first); let sGCT = halfAvgGCT(second)
            if let fg = fGCT, let sg = sGCT, (sg - fg) <= -7 {
                let delta = Int(abs((sg - fg).rounded()))
                result = (result.text + L.s(" 지면접촉은 \(delta)ms 짧아졌고요.", " Ground contact shortened by \(delta) ms though."),
                          result.color)
            }
            #if DEBUG
            let gctNote = (fGCT != nil && sGCT != nil)
                ? " GCT\(Int(fGCT!))→\(Int(sGCT!))ms(\(sGCT! - fGCT! >= 0 ? "+" : "")\(Int((sGCT! - fGCT!).rounded())))"
                : ""
            print("[Form:종류] type=\(wtName) splits=\(fullSplits.count) 전반P=\(pf(fp)) 후반P=\(pf(sp)) 차이=\(Int(paceDelta.rounded()))초\(gctNote) → \"\(result.text)\"")
            #endif
            return [typePrefix, result]

        case .general:
            guard fullSplits.count >= 4 else {
                #if DEBUG
                print("[Form:종류] 생략 — splits \(fullSplits.count)개 (4개 미만), type=\(wtName)")
                #endif
                return nil
            }
            let half = fullSplits.count / 2
            let first = Array(fullSplits.prefix(half))
            let second = Array(fullSplits.suffix(fullSplits.count - half))
            let paces = fullSplits.map(\.paceSecPerKm)
            let mean = paces.reduce(0, +) / Double(paces.count)
            var cv = 0.0
            if mean > 0 {
                let sd = sqrt(paces.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(paces.count))
                cv = sd / mean * 100
            }
            // 분기⓪ GCT 우선, 없으면 케이던스 폴백 (임계값 2)
            let fGCT = halfAvgGCT(first); let sGCT = halfAvgGCT(second)
            let firstCad = halfAvgCadence(first); let secondCad = halfAvgCadence(second)
            let formHeavy: Bool
            let formImproved: Bool   // ⓪ 후반 GCT ≤ -7ms — 개선
            let formHeavyMethod: String
            if let fg = fGCT, let sg = sGCT {
                formHeavy    = (sg - fg) >= 10
                formImproved = (sg - fg) <= -7
                let sign = (sg - fg) >= 0 ? "+" : ""
                formHeavyMethod = "GCT \(Int(fg))→\(Int(sg))ms(\(sign)\(Int((sg - fg).rounded())))"
            } else {
                let cadDrop: Double = (firstCad != nil && secondCad != nil) ? (firstCad! - secondCad!) : 0
                formHeavy    = cadDrop >= 2
                formImproved = false  // 케이던스만으론 개선 판정 안 함
                formHeavyMethod = "케이던스폴백 \(firstCad.map{Int($0)} ?? 0)→\(secondCad.map{Int($0)} ?? 0)(\(Int(cadDrop.rounded()))spm)"
            }
            let result: (text: String, color: Color)?
            let branch: Int
            if formImproved {
                result = (L.s("후반으로 갈수록 지면접촉이 짧아졌어요", "Ground contact shortened as the run progressed"), Color(hex: "7FD98A"))
                branch = 0
            } else if formHeavy {
                result = (L.s("후반에 폼이 조금 무거워졌어요", "Form got a bit heavier in the second half"), Color.white.opacity(0.75))
                branch = 1
            } else if cv > 5 {
                result = (L.s("페이스 기복이 있었어요", "Pace varied through the run"), Color.white.opacity(0.75))
                branch = 2
            } else if cv <= 3 {
                result = (L.s("처음부터 끝까지 고르게 달렸어요", "Even effort from start to finish"), Color(hex: "7FD98A"))
                branch = 3
            } else {
                result = nil
                branch = 4
            }
            #if DEBUG
            if branch == 4 {
                print("[Form:종류] type=\(wtName) CV=\(String(format: "%.1f", cv))% \(formHeavyMethod) → 분기④ 출력없음")
            } else {
                print("[Form:종류] type=\(wtName) CV=\(String(format: "%.1f", cv))% \(formHeavyMethod) → 분기\(branch) \"\(result!.text)\"")
            }
            #endif
            return result.map { [typePrefix, $0] }

        case .easy:
            let visibleZones = hrZones.filter { $0.fraction > 0.01 }
            guard !visibleZones.isEmpty else {
                #if DEBUG
                print("[Form:종류] 생략 — hrZones 없음, type=\(wtName)")
                #endif
                return nil
            }
            let totalFrac = visibleZones.map(\.fraction).reduce(0, +)
            let z2BelowFrac = hrZones.filter { $0.id <= 2 }.map(\.fraction).reduce(0, +)
            let ratio = totalFrac > 0 ? z2BelowFrac / totalFrac : 0
            let pct = Int((ratio * 100).rounded())
            let result: (text: String, color: Color)
            if ratio >= 0.80 {
                result = (L.s("제대로 이지 페이스를 지켰어요", "Great easy pacing — Z1–Z2 \(pct)%"), Color(hex: "7FD98A"))
            } else if ratio >= 0.50 {
                result = (L.s("중간중간 심박이 올라갔어요", "Heart rate drifted up at times"), Color.white.opacity(0.75))
            } else {
                result = (L.s("이지런인데 심박이 꽤 높았어요. 더 천천히 뛰어도 좋아요", "HR ran high — try slower for true easy effort"), Color(hex: "FFD166"))
            }
            #if DEBUG
            print("[Form:종류] type=\(wtName) Z2이하비율=\(pct)% → \"\(result.text)\"")
            #endif
            return [typePrefix, result]

        case .race:
            // 대회 분석은 Race 탭의 RaceInsightCard가 담당 — 여기서는 생략
            return nil
        }
    }

    // 인터벌에서 회복 구간을 제외한 고강도 구간만의 평균 케이던스
    private var intervalWorkCadence: Double? {
        guard workoutTypeFn?(activity.id) == .interval, let det = detail else { return nil }
        let cadences = det.intervalSegments
            .filter { $0.stepLabel == "운동" }
            .compactMap(\.avgCadence)
            .map(Double.init)
        guard !cadences.isEmpty else { return nil }
        return cadences.reduce(0, +) / Double(cadences.count)
    }

    #if DEBUG
    private func logIntervalSegments() {
        guard workoutTypeFn?(activity.id) == .interval,
              let det = detail, !det.intervalSegments.isEmpty else { return }
        let segs = det.intervalSegments
        let workCount = segs.filter { $0.stepLabel == "운동" }.count
        let recCount  = segs.filter { $0.stepLabel == "회복" }.count
        let cal = Calendar.current
        let dc  = cal.dateComponents([.month, .day], from: activity.date)
        print("[인터벌:세그먼트] \(dc.month ?? 0)/\(dc.day ?? 0) 총 \(segs.count)구간 (운동 \(workCount) / 회복 \(recCount))")
        var workIdx = 0, recIdx = 0
        for seg in segs {
            let lbl     = seg.stepLabel ?? "미분류"
            let isWork  = lbl == "운동"
            let isRec   = lbl == "회복"
            if isWork { workIdx += 1 }
            if isRec  { recIdx  += 1 }
            let idx     = isWork ? workIdx : isRec ? recIdx : 0
            let tag     = idx > 0 ? "\(lbl)\(idx)" : lbl
            let pace    = seg.formattedPace ?? "-"
            let cad     = seg.avgCadence.map { "\($0)" } ?? "-"
            let avgHR   = seg.avgHeartRate.map { "\($0)" } ?? "-"
            let dur     = "\(Int(seg.duration))s"
            // HR 시작→종료: hrSamples의 offset은 워크아웃 시작 기준 초(秒)
            let segStart = seg.startDate.timeIntervalSince(activity.date)
            let segEnd   = seg.endDate.timeIntervalSince(activity.date)
            let window   = hrSamples.filter { $0.offset >= segStart && $0.offset <= segEnd }
            let hrStr: String = {
                if window.count >= 2 {
                    return "\(window.first!.bpm)→\(window.last!.bpm)(avg \(avgHR))"
                }
                return avgHR
            }()
            print("  \(tag) 페이스 \(pace) C=\(cad) 보폭=- GCT=- 심박=\(hrStr) 지속=\(dur)")
        }
    }
    #endif

    private func formSummaryLine(parts: [(text: String, color: Color)]) -> some View {
        parts.reduce(Text("")) { acc, p in
            acc + Text(p.text).foregroundStyle(p.color)
        }
        .font(.system(size: 9))
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func formBackfillProgressLine(_ progress: (done: Int, total: Int)) -> some View {
        let L = AppLanguage.shared
        return Text(L.s(
            "폼 데이터 분석 중… \(progress.done)/\(progress.total)",
            "Analyzing form data… \(progress.done)/\(progress.total)"
        ))
        .font(.system(size: 8.5))
        .foregroundStyle(Color.white.opacity(0.4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var cadenceBottomLabel: String {
        let L = AppLanguage.shared
        // 인터벌은 band 기반 범위를 표시하지 않음
        if workoutTypeFn?(activity.id) == .interval {
            return L.s("전력 구간 권장 170–190", "Work cadence rec. 170–190")
        }
        guard let bb = formBaseline?.baseline(for: activity),
              let stat = bb.cadence else {
            return L.s("권장 케이던스 160–180", "Rec. Cadence 160–180")
        }
        let lo = Int(stat.lower.rounded())
        let hi = Int(stat.upper.rounded())
        return L.s("비슷한 페이스 기준 · \(lo)–\(hi)", "Similar pace · \(lo)–\(hi)")
    }

    private func cadenceVerdictInfo(cad: Int) -> (text: String, color: Color) {
        let L = AppLanguage.shared
        guard let bl = formBaseline else {
            let inRange = (160...175).contains(cad)
            let text = inRange
                ? L.s("권장 범위 안이에요", "In recommended range")
                : cad < 160
                    ? L.s("권장 범위보다 낮아요", "Below recommended range")
                    : L.s("권장 범위보다 높아요", "Above recommended range")
            return (text, inRange ? IC.green : IC.label)
        }
        let (lower, upper, warning) = bl.cadenceBand(for: activity)
        let c = Double(cad)
        if warning != nil && c < 160 {
            return (L.s("보폭이 큰 편이에요", "Wide stride"), IC.hrRed)
        }
        if c >= lower && c <= upper {
            return (L.s("평소 범위예요", "Typical range"), IC.green)
        }
        if c > upper {
            return (L.s("평소보다 빨랐어요", "Higher than usual"), Color(hex: "3A7BD5"))
        }
        return (L.s("평소보다 낮았어요", "Lower than usual"), Color(hex: "5AC8FA"))
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
        case 3: return L.s("심박은 템포 구간에 머물렀어요", "Heart rate stayed in tempo zone")
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
        let refNote = L.s("\(info.ageDecade)\(g) 기준 · FRIEND DB",
                          "\(info.ageDecade)\(g) · FRIEND DB")
        let levelLabels = [L.s("낮음", "Low"), L.s("평균이하", "Below"),
                           L.s("평균이상", "Above"), L.s("높음", "High")]
        let thresholds = ["<\(Int(info.normBelowAvg))",
                          "\(Int(info.normBelowAvg))–\(Int(info.normAboveAvg))",
                          "\(Int(info.normAboveAvg))–\(Int(info.normHigh))",
                          "≥\(Int(info.normHigh))"]
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
                ForEach(0..<4, id: \.self) { i in
                    VStack(spacing: 2) {
                        Text(levelLabels[i])
                            .font(.system(size: 7.5))
                            .foregroundStyle(IC.vo2Colors[i])
                        Text(thresholds[i])
                            .font(.system(size: 7))
                            .foregroundStyle(IC.label)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(refNote).font(.system(size: 9)).foregroundStyle(IC.label)
        }
    }

    @ViewBuilder
    private func oneLiner(text: String, bg: Color, fg: Color, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("✦").font(.system(size: 10)).foregroundStyle(accent)
            Text(text).font(.system(size: 10)).foregroundStyle(fg).lineSpacing(2)
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

    private var hrVerdictText: (text: String, color: Color)? {
        guard hrSamples.count >= 10 else { return nil }
        let L = AppLanguage.shared
        let n = hrSamples.count
        let half = n / 2
        let avgFirst  = hrSamples.prefix(half).map { Double($0.bpm) }.reduce(0, +) / Double(half)
        let avgSecond = hrSamples.suffix(n - half).map { Double($0.bpm) }.reduce(0, +) / Double(n - half)
        let diff = avgSecond - avgFirst
        if let a = age {
            let peakBPM = Double(hrSamples.map(\.bpm).max() ?? 0)
            if peakBPM / Double(220 - a) >= 0.90 {
                return (L.s("최고 강도까지 올렸어요", "Pushed to max intensity"), Color(hex: "FF9A3C"))
            }
        }
        if diff >= 8  { return (L.s("후반에 심박이 올랐어요", "HR climbed in the 2nd half"), Color(hex: "FF9A3C")) }
        if diff <= -5 { return (L.s("후반에 여유가 있었어요", "Plenty left in the 2nd half"), Color(hex: "4C8DFF")) }
        return (L.s("끝까지 안정적이었어요", "Steady throughout"), Color(hex: "5CE08A"))
    }

    private func vo2SubLabel(fi: RunInsightEngine.VO2FitnessInfo, vo2: Double) -> (text: String, color: Color) {
        let L = AppLanguage.shared
        let bounds: [Double]   = [15, 26, 33, 41, 57]
        let levelColors: [Color] = [Color(hex: "E8564A"), Color(hex: "F0913C"), Color(hex: "EDC84B"), Color(hex: "7FD98A")]
        let levelNames = [L.s("낮음","Low"), L.s("평균이하","Below avg"), L.s("평균이상","Above avg"), L.s("높음","High")]
        var idx = bounds.count - 2
        for i in 0..<(bounds.count - 1) { if vo2 < bounds[i + 1] { idx = i; break } }
        let g = fi.genderLabel.isEmpty ? "" : " \(fi.genderLabel)"
        let valStr = String(format: "%.1f", vo2)
        return (L.s("\(valStr)은 \(fi.ageDecade)\(g) 기준 \(levelNames[idx])",
                    "\(valStr) is \(levelNames[idx]) for \(fi.ageDecade)\(g)"), levelColors[idx])
    }

    private var oneLiner: String? {
        let L = AppLanguage.shared
        // 1) 연속 기록
        let streak = computeRunningStreak(activity: activity, history: history)
        if streak >= 3 {
            return L.s("\(streak)일 연속 달리고 있어요", "\(streak) consecutive days")
        }
        // 1.5) 장거리 폼 유지 — 명시 태그된 .longRun/.lsd는 formSummaryLine이 담당
        let _curWT = workoutTypeFn?(activity.id) ?? .general
        if _curWT != .longRun && _curWT != .lsd && rhythmIsLongDistanceContext, let det = detail {
            let full = det.splits.filter { $0.distanceM >= 900 }
            if full.count >= 4 {
                let half = full.count / 2
                let s1 = Array(full.prefix(half))
                let s2 = Array(full.suffix(full.count - half))
                func avgGCT(_ s: [SplitData]) -> Double? {
                    let v = s.compactMap(\.avgGroundContactTime)
                    return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
                }
                func avgCad(_ s: [SplitData]) -> Double? {
                    let v = s.compactMap(\.avgCadence).map(Double.init)
                    return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
                }
                let formHeld: Bool
                if let g1 = avgGCT(s1), let g2 = avgGCT(s2) { formHeld = g2 - g1 < 10 }
                else if let c1 = avgCad(s1), let c2 = avgCad(s2) { formHeld = c1 - c2 < 2 }
                else { formHeld = false }
                if formHeld {
                    return L.s("장거리인데 후반까지 폼이 버텼어요", "Form held through the long run")
                }
            }
        }
        // 2) 거리 기록
        if let ctx = distanceContext { return ctx }
        // 3) 강도 배분 조언 (고강도 ≥ 40%)
        let visible = hrZones.filter { $0.fraction > 0.01 }
        if !visible.isEmpty {
            let tot = visible.map(\.fraction).reduce(0, +)
            let highFrac = visible.filter { $0.id >= 4 }.map(\.fraction).reduce(0, +) / max(1e-9, tot)
            if highFrac >= 0.40 {
                return L.s("고강도 구간이 많았어요. 다음엔 여유롭게 가도 좋아요",
                           "High-intensity run. An easy run next time is great.")
            }
        }
        // 4) 그 외 — efficiency/intensity/endurance 인사이트
        for cat: InsightCategory in [.efficiency, .intensity, .endurance] {
            if let m = insights.first(where: { $0.category == cat })?.message { return m }
        }
        return L.s("편안한 강도로 잘 쌓고 있어요", "Building fitness at a comfortable pace")
    }
}

// MARK: - Performance Card

/// 강도 분포 세로 막대 위에 그리는 가로 문헌값 눈금 한 줄.
private struct IntensityTickLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

private struct PerformanceInsightCard: View {
    let activity: Activity
    var detail: ActivityDetail? = nil
    var history: [Activity] = []
    var age: Int? = nil
    var isMale: Bool? = nil
    let insights: [RunInsight]
    var workoutTypeFn: ((UUID) -> WorkoutType?)? = nil
    /// 이 러닝의 존 분포 (리듬 카드 도넛과 동일 소스)
    var hrZones: [HRZoneData] = []
    /// 과거 러닝의 존 분포 조회 — 강도 분포 4주 합산용
    var hrZonesFn: ((UUID) -> [HRZoneData]?)? = nil
    var isBackfilling: Bool = false
    var isClassifying: Bool = false
    /// 강도(sRPE) 조회 인덱스 — 7일 강도 부하용. 없으면 강도 분포만 전체 폭.
    var effortIndex: EffortIndex? = nil

    @State private var heroBadge: AchievementBadgeKind? = nil
    @State private var heroBadgeLoaded = false
    @State private var _distResult: (items: [TrainingDistItem], weeks: Int, totalRuns: Int, todayBucket: String?)? = nil
    @State private var _intensityResult: IntensityTimeData? = nil
    @State private var _distComputed = false

    /// 7일 강도 부하 묶음 — 창 + 이 러닝의 AU + 4주 평균 대비 라벨.
    private struct SevenDayLoad {
        let window: EffortLoad.WindowLoad
        let thisRunAU: Double?
        let acuteChronic: EffortLoad.RatioLabel?
        /// 성장 탭 상태 카드에서 옮겨온 한 줄: 단조도 → 4주 평균 대비(유지는 침묵)
        let sentence: EffortLoad.SentenceKind?
    }

    /// 이 러닝 날짜로 끝나는 7일 부하(오늘이 아니라 그 러닝 기준). 강도 기록이 없으면 nil → 오른쪽 반쪽 생략.
    private var sevenDayLoad: SevenDayLoad? {
        guard let idx = effortIndex else { return nil }
        let cal = Calendar.current
        let dayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: activity.date)) ?? activity.date
        let since = cal.date(byAdding: .day, value: -36, to: activity.date) ?? .distantPast
        var acts = history.filter { $0.date >= since && $0.date < dayEnd }
        // history가 이 러닝을 포함하지 않는 호출부에서도 이 러닝이 창에 들어가야 한다.
        if !acts.contains(where: { $0.id == activity.id }) { acts.append(activity) }
        let runs = EffortLoad.runs(from: acts, index: idx)
        let w = EffortLoad.window(runs: runs, endingBefore: dayEnd, days: 7)
        guard w.coveredCount > 0 else { return nil }
        let thisAU = idx.resolve(activity.id).map { EffortLoad.sessionAU(effort: $0.value, durationMin: activity.duration / 60) }
        let ac = EffortLoad.rollingAcuteChronic(runs: runs, asOf: activity.date)?.label
        let sentence = EffortLoad.rollingSentenceKind(runs: runs, asOf: activity.date)

        // 유형별 평소 강도 눈금은 그리지 않는다 — 이 카드는 러닝 유형을 표시하지 않아 눈금의 뜻을 알 수 없다(성장 탭과 같은 표시 방식).
        return SevenDayLoad(window: w, thisRunAU: thisAU, acuteChronic: ac, sentence: sentence)
    }

    private struct HRTrendPt: Identifiable {
        let id = UUID()
        let index: Int
        let hr: Double
        let isToday: Bool
    }

    private struct SplitBarItem {
        let index: Int
        let paceSecPerKm: Double
        let distanceM: Double
        let isFirstHalf: Bool
    }

    private enum ScatterGroup { case past, recent, today }
    private struct ScatterPt {
        let pace: Double
        let hr: Double
        let group: ScatterGroup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroSection
            divider
            kpiRow
            let scatter = scatterData
            let dist = trainingDistData
            if scatter.count >= 6 {
                divider
                HStack(alignment: .top, spacing: 10) {
                    hrScatterSection(data: scatter)
                        .frame(maxWidth: .infinity)
                    if dist != nil || isBackfilling || isClassifying {
                        Rectangle().fill(.white.opacity(0.08))
                            .frame(width: 0.5)
                            .padding(.vertical, 2)
                        if let d = dist {
                            distribHorizontalSection(items: d.items, weeks: d.weeks, totalRuns: d.totalRuns, todayBucket: d.todayBucket)
                                .frame(maxWidth: .infinity)
                        } else {
                            backfillingPlaceholder
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            if let intensDist = intensityDistData {
                divider
                intensityDistSection(data: intensDist)
            }
            let iSegs  = intervalChartData
            let voInf  = vo2Info
            let voDet  = detail?.vo2Max
            if let s = iSegs {
                divider
                if let vi = voInf, let vd = voDet {
                    HStack(alignment: .top, spacing: 10) {
                        cardioSection(info: vi, vo2: vd).frame(maxWidth: .infinity)
                        Rectangle().fill(.white.opacity(0.08)).frame(width: 0.5).padding(.vertical, 2)
                        intervalBarSection(segments: s).frame(maxWidth: .infinity)
                    }
                } else {
                    intervalBarSection(segments: s)
                }
            } else if let splitData = splitChartData, voInf == nil || voDet == nil {
                // VO2 없을 때만 full-width 스플릿 차트 표시 (VO2 있으면 cardioSection 우측에 compact로 표시)
                divider
                splitPaceSection(data: splitData)
            }
            if iSegs == nil, let vi = voInf, let vd = voDet {
                divider
                cardioSection(info: vi, vo2: vd)
            }
            if let line = oneLiner {
                divider
                oneLiner(text: line, bg: IC.violetBg, fg: IC.violetText, accent: IC.violet)
            }
            if let ri = returnInsight {
                if ri.hrRecovered {
                    divider
                    returnRecoveredRow
                } else {
                    divider
                    returnInsightRow(ri)
                }
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            guard !heroBadgeLoaded else { return }
            heroBadge = computeAchievementBadge(activity: activity, history: history)
            heroBadgeLoaded = true
            if !isBackfilling && !isClassifying {
                recomputeDistributions()
            }
            _distComputed = true
        }
        .onChange(of: isBackfilling) { _, newValue in
            if !newValue && !isClassifying { recomputeDistributions() }
        }
        .onChange(of: isClassifying) { _, newValue in
            if !newValue && !isBackfilling { recomputeDistributions() }
        }
    }

    /// 훈련 배분(유형 기준)과 강도 분포(존 시간 기준)를 같은 시점에 계산 — 창(weeks)을 공유한다.
    private func recomputeDistributions() {
        _distResult = computeTrainingDistData()
        _intensityResult = _distResult.flatMap { computeIntensityTimeData(weeks: $0.weeks) }
    }

    private var heroSection: some View {
        let km = activity.distance / 1000
        let kmStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
        let coords = detail?.routeCoordinates ?? []
        let hasRoute = coords.count >= 2
        let base = weeklyBase
        let wkKm = String(format: "%.1f", base.weeklyLoadKm)
        let moKm = String(format: "%.1f", monthlyLoadKm)
        let L = AppLanguage.shared

        return HStack(alignment: .top, spacing: 12) {
            // 히어로 거리 블록 (왼쪽)
            VStack(alignment: .leading, spacing: 3) {
                WeekStripView(activity: activity, history: history)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(kmStr)
                        .font(cardNumFont(40))
                        .tracking(-1.6)
                    Text("km").font(.system(size: 16)).foregroundStyle(IC.label)
                }
                .foregroundStyle(Color.white)
                if let ctx = heroContext {
                    Text(ctx).font(.system(size: 10)).foregroundStyle(IC.green)
                }
            }
            Spacer(minLength: 8)
            // 우측: 3줄 블록 + 경로 아트 (세로 중앙 정렬)
            HStack(alignment: .center, spacing: 8) {
                // 3줄 블록
                VStack(alignment: .trailing, spacing: 5) {
                    // 1줄: 이번 주
                    HStack(spacing: 4) {
                        Text(L.s("이번 주", "This wk"))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.70))
                        Text(wkKm)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text("km")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.white.opacity(0.70))
                    }
                    // 2줄: 이번 달
                    HStack(spacing: 4) {
                        Text(L.s("이번 달", "This mo"))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.70))
                        Text(moKm)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text("km")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.white.opacity(0.70))
                    }
                    // 3줄: 배지 — @State 미설정(ImageRenderer) 시 인라인 계산으로 폴백
                    if let badge = heroBadge ?? computeAchievementBadge(activity: activity, history: history) {
                        AchievementBadgeView(badge: badge)
                    } else {
                        Color.clear.frame(height: 22)
                    }
                }
                // 경로 아트 (최우측)
                if hasRoute {
                    StampRouteArt(
                        coords: coords,
                        lineWidth: 2.2,
                        color: Color(hex: "8B7FF0"),
                        casingColor: Theme.cardBackground
                    )
                    .frame(width: 44, height: 46)
                }
            }
        }
    }

    private var monthlyLoadKm: Double {
        let cal = Calendar.current
        guard let startOfMonth = cal.date(
            from: cal.dateComponents([.year, .month], from: activity.date)
        ) else { return 0 }
        var seen = Set<UUID>()
        var total = 0.0
        for act in (history + [activity]) where act.type == .running {
            guard act.date >= startOfMonth, act.date <= activity.date else { continue }
            if seen.insert(act.id).inserted { total += act.distance / 1000 }
        }
        return total
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
    private func hrScatterSection(data: [ScatterPt]) -> some View {
        let L = AppLanguage.shared
        let paces = data.map(\.pace)
        let hrs   = data.map(\.hr)
        let rawPMin = paces.min() ?? 300
        let rawPMax = paces.max() ?? 400
        let rawHMin = hrs.min() ?? 120
        let rawHMax = hrs.max() ?? 180
        let pSpan = max(1.0, rawPMax - rawPMin)
        let hSpan = max(1.0, rawHMax - rawHMin)
        let pMin  = rawPMin - pSpan * 0.05
        let pMax  = rawPMax + pSpan * 0.05
        let hMin  = rawHMin - hSpan * 0.05
        let hMax  = rawHMax + hSpan * 0.05

        let pastPts   = data.filter { $0.group == .past }
        let recentPts = data.filter { $0.group == .recent }
        let todayPts  = data.filter { $0.group == .today }

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 0) {
                Spacer()
                if let d = hrDelta, d > 0 {
                    (Text(L.s("심박 효율: ", "HR Efficiency: "))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.90))
                    + Text("↓\(d) bpm")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(IC.green)
                    + Text(L.s(" (동일 페이스 기준)", " (vs. similar pace)"))
                        .font(.system(size: 8)).foregroundStyle(.white.opacity(0.55)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                } else {
                    Text(L.s("심박 효율", "HR Efficiency"))
                        .font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(.white.opacity(0.90))
                }
                Spacer()
            }
            Canvas { ctx, size in
                let w = size.width
                let canvasH = size.height
                let botPad:   CGFloat = 14
                let topPad:   CGFloat = 3
                let chartW = w
                let chartH = canvasH - botPad - topPad

                let cx: (Double) -> CGFloat = { pace in
                    let denom = pMax - pMin
                    let norm = denom < 1 ? 0.5 : (pMax - pace) / denom
                    return CGFloat(norm) * chartW
                }
                let cy: (Double) -> CGFloat = { hr in
                    let denom = hMax - hMin
                    let norm = denom < 1 ? 0.5 : (hr - hMin) / denom
                    return topPad + chartH - CGFloat(norm) * chartH
                }

                // Axis lines
                var xAxis = Path()
                xAxis.move(to: CGPoint(x: 0, y: topPad + chartH))
                xAxis.addLine(to: CGPoint(x: w, y: topPad + chartH))
                ctx.stroke(xAxis, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 0.8))
                var yAxis = Path()
                yAxis.move(to: CGPoint(x: 0, y: topPad))
                yAxis.addLine(to: CGPoint(x: 0, y: topPad + chartH))
                ctx.stroke(yAxis, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 0.8))

                // Arrow: past centroid → recent centroid
                if pastPts.count >= 3 && recentPts.count >= 3 {
                    let pCX = pastPts.map { cx($0.pace) }.reduce(0, +) / CGFloat(pastPts.count)
                    let pCY = pastPts.map { cy($0.hr) }.reduce(0, +) / CGFloat(pastPts.count)
                    let rCX = recentPts.map { cx($0.pace) }.reduce(0, +) / CGFloat(recentPts.count)
                    let rCY = recentPts.map { cy($0.hr) }.reduce(0, +) / CGFloat(recentPts.count)

                    var arrowLine = Path()
                    arrowLine.move(to: CGPoint(x: pCX, y: pCY))
                    arrowLine.addLine(to: CGPoint(x: rCX, y: rCY))
                    ctx.stroke(arrowLine, with: .color(IC.green.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    let dxF = rCX - pCX
                    let dyF = rCY - pCY
                    let lenF = sqrt(dxF * dxF + dyF * dyF)
                    if lenF > 2 {
                        let nx = dxF / lenF
                        let ny = dyF / lenF
                        let al: CGFloat = 6
                        let aa = 0.4
                        let cosA = CGFloat(cos(aa))
                        let sinA = CGFloat(sin(aa))
                        var head = Path()
                        head.move(to: CGPoint(x: rCX, y: rCY))
                        head.addLine(to: CGPoint(x: rCX - al * (nx * cosA + ny * sinA),
                                                  y: rCY - al * (ny * cosA - nx * sinA)))
                        head.move(to: CGPoint(x: rCX, y: rCY))
                        head.addLine(to: CGPoint(x: rCX - al * (nx * cosA - ny * sinA),
                                                  y: rCY - al * (ny * cosA + nx * sinA)))
                        ctx.stroke(head, with: .color(IC.green.opacity(0.5)),
                                   style: StrokeStyle(lineWidth: 1))
                    }
                }

                // Past dots (white)
                for pt in pastPts {
                    let r: CGFloat = 3.4
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: cx(pt.pace)-r, y: cy(pt.hr)-r, width: r*2, height: r*2)),
                        with: .color(.white.opacity(0.55))
                    )
                }
                // Recent dots (violet)
                for pt in recentPts {
                    let r: CGFloat = 3.8
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: cx(pt.pace)-r, y: cy(pt.hr)-r, width: r*2, height: r*2)),
                        with: .color(IC.violet)
                    )
                }
                // Today dot (green + ring) — drawn last
                for pt in todayPts {
                    let rO: CGFloat = 8.6
                    let rI: CGFloat = 5.4
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: cx(pt.pace)-rO, y: cy(pt.hr)-rO, width: rO*2, height: rO*2)),
                        with: .color(IC.green.opacity(0.35)), style: StrokeStyle(lineWidth: 1)
                    )
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: cx(pt.pace)-rI, y: cy(pt.hr)-rI, width: rI*2, height: rI*2)),
                        with: .color(IC.green)
                    )
                }

                // Y-axis labels — inside chart, top-left / bottom-left
                ctx.draw(
                    Text("\(Int(rawHMax))").font(.system(size: 8)).foregroundStyle(.white.opacity(0.70)),
                    at: CGPoint(x: 3, y: topPad + 1), anchor: .topLeading
                )
                ctx.draw(
                    Text("\(Int(rawHMin))").font(.system(size: 8)).foregroundStyle(.white.opacity(0.70)),
                    at: CGPoint(x: 3, y: topPad + chartH - 1), anchor: .bottomLeading
                )

                // X-axis labels (slow left / fast right — x-axis is inverted)
                func fmtPace(_ sec: Double) -> String {
                    let m = Int(sec) / 60; let s = Int(sec) % 60
                    return String(format: "%d'%02d\"", m, s)
                }
                ctx.draw(
                    Text(fmtPace(rawPMax)).font(.system(size: 8)).foregroundStyle(.white.opacity(0.70)),
                    at: CGPoint(x: 3, y: topPad + chartH + 3), anchor: .topLeading
                )
                ctx.draw(
                    Text(fmtPace(rawPMin)).font(.system(size: 8)).foregroundStyle(.white.opacity(0.70)),
                    at: CGPoint(x: w - 3, y: topPad + chartH + 3), anchor: .topTrailing
                )
            }
            .frame(height: 110)

            // 범례
            HStack(spacing: 0) {
                Spacer()
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.white.opacity(0.55)).frame(width: 6, height: 6)
                        Text(L.s("8주 전", "8w ago")).font(.system(size: 8)).foregroundStyle(.white.opacity(0.70))
                    }
                    HStack(spacing: 4) {
                        Circle().fill(IC.violet).frame(width: 6, height: 6)
                        Text(L.s("최근", "Recent")).font(.system(size: 8)).foregroundStyle(.white.opacity(0.70))
                    }
                    HStack(spacing: 4) {
                        Circle().fill(IC.green).frame(width: 6, height: 6)
                        Text(L.s("오늘", "Today")).font(.system(size: 8)).foregroundStyle(.white.opacity(0.70))
                    }
                }
                Spacer()
            }
        }
    }

    private func cardioSection(info: RunInsightEngine.VO2FitnessInfo, vo2: Double) -> some View {
        let L = AppLanguage.shared
        let g = info.genderLabel.isEmpty ? "" : " \(info.genderLabel)"
        let bounds: [Double] = [15, 26, 33, 41, 57]
        let levelColors: [Color] = [Color(hex: "E8564A"), Color(hex: "F0913C"), Color(hex: "EDC84B"), Color(hex: "7FD98A")]
        let levelNames = [L.s("낮음","Low"), L.s("평균이하","Below avg"), L.s("평균이상","Above avg"), L.s("높음","High")]
        var gradeIdx = bounds.count - 2
        for i in 0..<(bounds.count - 1) { if vo2 < bounds[i + 1] { gradeIdx = i; break } }
        let valStr = String(format: "%.1f", vo2)
        let gradeText = L.s("\(valStr)은 \(info.ageDecade)\(g) 기준 \(levelNames[gradeIdx])",
                            "\(valStr) is \(levelNames[gradeIdx]) for \(info.ageDecade)\(g)")
        let gradeColor = levelColors[gradeIdx]
        let splitData = splitChartData
        return HStack(alignment: .top, spacing: 10) {
            // 좌: VO2 반원 게이지
            VStack(alignment: .center, spacing: 3) {
                Text(L.s("유산소 피트니스", "Aerobic Fitness"))
                    .font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(.white.opacity(0.90))
                VO2RPMGaugeView(fi: info, vo2: vo2)
                Color.clear.frame(height: 12)
                Text(gradeText)
                    .font(.system(size: 8.5)).foregroundStyle(gradeColor)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            // 우: 스플릿 페이스 차트 (축소)
            if let sd = splitData {
                Rectangle().fill(.white.opacity(0.1))
                    .frame(width: 0.5)
                    .padding(.vertical, 4)
                splitPaceCompact(data: sd)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func metricsSection(base: RunBaseline) -> some View {
        let L = AppLanguage.shared
        let prevCtx: String? = base.prevWeeklyLoadKm > 0
            ? L.s("지난주 \(String(format: "%.1f", base.prevWeeklyLoadKm))km",
                  "Last wk \(String(format: "%.1f", base.prevWeeklyLoadKm))km")
            : nil
        return MetricRow(label: L.s("이번 주 훈련량", "Weekly Load"),
                         value: String(format: "%.1fkm", base.weeklyLoadKm),
                         context: prevCtx)
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

    private var scatterData: [ScatterPt] {
        let cal = Calendar.current
        let cutoff8w = cal.date(byAdding: .weekOfYear, value: -8, to: activity.date) ?? .distantPast
        let cutoff4w = cal.date(byAdding: .weekOfYear, value: -4, to: activity.date) ?? .distantPast
        var result: [ScatterPt] = []
        if let tp = activity.paceSecPerKm, tp > 0, let th = activity.avgHeartRate {
            result.append(ScatterPt(pace: tp, hr: Double(th), group: .today))
        }
        let eligible = history
            .filter {
                $0.type == .running &&
                $0.id != activity.id &&
                $0.date >= cutoff8w && $0.date < activity.date &&
                $0.distance / 1000 >= 3 &&
                $0.avgHeartRate != nil &&
                $0.paceSecPerKm != nil
            }
            .filter {
                guard let wt = workoutTypeFn?($0.id) else { return true }
                return wt != .interval && wt != .buildUp
            }
            .sorted { $0.date > $1.date }
            .prefix(39)
        for act in eligible {
            let grp: ScatterGroup = act.date >= cutoff4w ? .recent : .past
            result.append(ScatterPt(pace: act.paceSecPerKm!, hr: Double(act.avgHeartRate!), group: grp))
        }
        return result
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

    @ViewBuilder
    private func intervalBarSection(segments: [IntervalSegment]) -> some View {
        let L = AppLanguage.shared
        let workPaces = segments.filter { $0.stepLabel == "운동" }.compactMap { $0.paceSecPerKm }
        let maxPace = workPaces.max() ?? 1
        let paceRange = max(1.0, (workPaces.max() ?? 1) - (workPaces.min() ?? 0))
        let warmCool = segments.filter { let l = $0.stepLabel ?? ""; return !l.isEmpty && l != "운동" && l != "회복" }
        let mainSegs = segments.filter { $0.stepLabel == "운동" || $0.stepLabel == "회복" }

        VStack(alignment: .leading, spacing: 4) {
            Text(L.s("인터벌 구간", "Interval Segments"))
                .font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(.white.opacity(0.90))
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                // 준비운동·정리운동 — one compact line
                if !warmCool.isEmpty {
                    let wcText = warmCool.map { seg -> String in
                        let lbl = seg.stepLabel ?? ""
                        if let p = seg.paceSecPerKm {
                            return "\(lbl) \(String(format: "%d'%02d\"", Int(p)/60, Int(p)%60))"
                        }
                        return lbl
                    }.joined(separator: "  ·  ")
                    Text(wcText)
                        .font(.system(size: 7.5))
                        .foregroundStyle(.white.opacity(0.75))
                        .monospacedDigit()
                }

                // 운동·회복 rows
                ForEach(Array(mainSegs.enumerated()), id: \.0) { _, seg in
                    let isWork = seg.stepLabel == "운동"
                    let paceStr = seg.paceSecPerKm.map { String(format: "%d'%02d\"", Int($0)/60, Int($0)%60) } ?? ""
                    let norm: Double = {
                        guard let pace = seg.paceSecPerKm else { return 0.08 }
                        return max(0.08, (maxPace - pace) / paceRange)
                    }()
                    if isWork {
                        HStack(spacing: 6) {
                            Text("운동")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(Color(hex: "5CE08A"))
                                .frame(width: 24, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(.white.opacity(0.06))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(hex: "5CE08A"))
                                        .frame(width: max(4, geo.size.width * CGFloat(norm)))
                                }
                            }
                            .frame(height: 6)
                            Text(paceStr)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.90))
                                .monospacedDigit()
                                .frame(width: 38, alignment: .trailing)
                        }
                    } else {
                        // 회복 — label 숨김, 얇은 dim 바만
                        HStack(spacing: 6) {
                            Color.clear.frame(width: 24)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(.white.opacity(0.04))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(.white.opacity(0.12))
                                        .frame(width: geo.size.width * 0.12)
                                }
                            }
                            .frame(height: 4)
                            Color.clear.frame(width: 38)
                        }
                    }
                }
            }
        }
    }

    private var weeklyBase: RunBaseline {
        RunInsightEngine.baseline(for: activity, history: history)
    }

    private var splitChartData: [SplitBarItem]? {
        if let wt = workoutTypeFn?(activity.id), wt == .interval { return nil }
        guard let splits = detail?.splits else { return nil }
        // 900m 이상 정규 스플릿 + 마지막 부분 스플릿(300m 이상)은 포함 — 막판 스퍼트가 빠지지 않게
        let sorted = splits.sorted { $0.id < $1.id }
        let valid = sorted.enumerated().filter { i, s in
            s.distanceM >= 900 || (i == sorted.count - 1 && s.distanceM >= 300)
        }.map(\.element)
        guard valid.count >= 4 else { return nil }
        let maxBars = 16
        let total = valid.count
        if total <= maxBars {
            let half = total / 2
            return valid.enumerated().map { i, s in
                SplitBarItem(index: i, paceSecPerKm: s.paceSecPerKm,
                             distanceM: s.distanceM, isFirstHalf: i < half)
            }
        } else {
            let half = maxBars / 2
            let groupSize = Double(total) / Double(maxBars)
            return (0..<maxBars).map { b in
                let start = Int((Double(b) * groupSize).rounded())
                let end   = min(total, Int((Double(b + 1) * groupSize).rounded()))
                let group = Array(valid[start..<end])
                let avgPace  = group.map { $0.paceSecPerKm }.reduce(0, +) / Double(group.count)
                let totalDist = group.map { $0.distanceM }.reduce(0, +)
                return SplitBarItem(index: b, paceSecPerKm: avgPace,
                                    distanceM: totalDist, isFirstHalf: b < half)
            }
        }
    }

    private var intervalChartData: [IntervalSegment]? {
        guard let wt = workoutTypeFn?(activity.id), wt == .interval else { return nil }
        let segs = (detail?.intervalSegments ?? []).filter { $0.paceSecPerKm != nil }
        guard segs.count >= 2 else { return nil }
        return segs
    }

    @ViewBuilder
    private func splitPaceSection(data: [SplitBarItem]) -> some View {
        let L = AppLanguage.shared
        let paces = data.map(\.paceSecPerKm)
        let minPace = paces.min() ?? 0
        let maxPace = paces.max() ?? 1
        let paceRange = max(1.0, maxPace - minPace)
        let avgPace = paces.reduce(0, +) / Double(paces.count)
        let half = data.filter(\.isFirstHalf).count
        let fPaces = data.prefix(half).map(\.paceSecPerKm)
        let bPaces = data.suffix(data.count - half).map(\.paceSecPerKm)
        let fAvg = fPaces.isEmpty ? avgPace : fPaces.reduce(0, +) / Double(fPaces.count)
        let bAvg = bPaces.isEmpty ? avgPace : bPaces.reduce(0, +) / Double(bPaces.count)
        let backPct = bAvg > 0 ? fAvg / bAvg * 100 : 100.0
        let sdSec: Int = {
            let variance = paces.map { pow($0 - avgPace, 2) }.reduce(0, +) / Double(paces.count)
            return Int(variance.squareRoot().rounded())
        }()
        let totalKm = data.map(\.distanceM).reduce(0, +) / 1000

        let backColor: Color = backPct > 100 ? IC.green
                               : backPct >= 95 ? IC.green
                               : backPct >= 90 ? .white.opacity(0.7)
                               : Color(hex: "FF9A3C")
        let backSuffix: String = backPct > 100
            ? L.s(" · 네거티브 스플릿", " · Negative split")
            : backPct < 90 ? L.s(" · 후반 감속", " · Fade") : ""

        VStack(alignment: .leading, spacing: 5) {
            Canvas { ctx, size in
                let w = size.width
                let chartH = size.height
                let xPad: CGFloat = 4
                let n = data.count
                let slotW = (w - xPad) / CGFloat(n)
                let barW  = slotW * 0.62
                let barGap = (slotW - barW) / 2

                func normBarH(_ pace: Double) -> CGFloat {
                    let norm = paceRange > 0 ? (maxPace - pace) / paceRange : 0.5
                    return 12 + CGFloat(norm) * 30
                }

                let halfCount = data.filter(\.isFirstHalf).count
                let halfX = xPad + CGFloat(halfCount) * slotW

                // (a) 전·후반 배경
                ctx.fill(Path(CGRect(x: xPad, y: 0, width: halfX - xPad, height: chartH)),
                         with: .color(.white.opacity(0.03)))
                ctx.fill(Path(CGRect(x: halfX, y: 0, width: w - halfX, height: chartH)),
                         with: .color(Color(hex: "5BB8FF").opacity(0.06)))

                // (b) 막대
                for bar in data {
                    let bx = xPad + CGFloat(bar.index) * slotW + barGap
                    let bh = normBarH(bar.paceSecPerKm)
                    let by = chartH - bh
                    let opacity: Double = bar.paceSecPerKm < avgPace - 3 ? 0.85
                                          : bar.paceSecPerKm <= avgPace + 3 ? 0.65
                                          : 0.45
                    ctx.fill(
                        Path(roundedRect: CGRect(x: bx, y: by, width: barW, height: bh),
                             cornerRadius: 2),
                        with: .color(Color(hex: "5BB8FF").opacity(opacity))
                    )
                }

                // (c) 평균 점선
                let avgBH = normBarH(avgPace)
                let avgLineY = chartH - avgBH
                var dashPath = Path()
                dashPath.move(to: CGPoint(x: xPad, y: avgLineY))
                dashPath.addLine(to: CGPoint(x: w - 24, y: avgLineY))
                ctx.stroke(dashPath, with: .color(Color(hex: "5BB8FF").opacity(0.7)),
                           style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                ctx.draw(
                    Text(L.s("평균", "avg"))
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color(hex: "5BB8FF").opacity(0.8)),
                    at: CGPoint(x: w - 10, y: avgLineY),
                    anchor: .center
                )

                // (d) 축선
                var xAxis = Path()
                xAxis.move(to: CGPoint(x: xPad, y: chartH))
                xAxis.addLine(to: CGPoint(x: w, y: chartH))
                ctx.stroke(xAxis, with: .color(.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 0.8))
                var yAxis = Path()
                yAxis.move(to: CGPoint(x: xPad, y: 0))
                yAxis.addLine(to: CGPoint(x: xPad, y: chartH))
                ctx.stroke(yAxis, with: .color(.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 0.8))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 75)

            // x축 라벨
            HStack {
                Text("1").font(.system(size: 6.5)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(L.s("전반 │ 후반", "1H │ 2H"))
                    .font(.system(size: 6.5)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(String(format: "%.0fkm", totalKm))
                    .font(.system(size: 6.5)).foregroundStyle(.white.opacity(0.5))
            }

            // 페이스 편차 가로 막대
            let sdColor: Color = sdSec <= 8 ? IC.green
                               : sdSec <= 15 ? Color(hex: "F5C542")
                               : Color(hex: "FF9A3C")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(L.s("편차", "SD"))
                        .font(.system(size: 8.5)).foregroundStyle(IC.label)
                        .frame(width: 22, alignment: .leading)
                    GeometryReader { geo in
                        let fill = min(1.0, CGFloat(sdSec) / 25.0)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2.5).fill(.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 2.5).fill(sdColor.opacity(0.8))
                                .frame(width: max(4, geo.size.width * fill))
                        }
                    }
                    .frame(height: 7)
                    Text("±\(sdSec)" + L.s("초", "s"))
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(sdColor)
                        .frame(width: 30, alignment: .trailing)
                }
                HStack {
                    Spacer()
                    Text(L.s("후반 유지", "2H retention")
                         + " " + String(format: "%.0f%%", backPct) + backSuffix)
                        .font(.system(size: 9)).foregroundStyle(backColor)
                }
            }
        }
    }

    @ViewBuilder
    private func splitPaceCompact(data: [SplitBarItem]) -> some View {
        let L = AppLanguage.shared
        let paces = data.map(\.paceSecPerKm)
        let avgPace = paces.reduce(0, +) / Double(paces.count)
        let totalKm = data.map(\.distanceM).reduce(0, +) / 1000
        let sdSec: Int = {
            let variance = paces.map { pow($0 - avgPace, 2) }.reduce(0, +) / Double(paces.count)
            return Int(variance.squareRoot().rounded())
        }()

        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .trailing) {
                Text(L.s("페이스 분포", "Pace Distribution"))
                    .font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(.white.opacity(0.90))
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("±\(sdSec)" + L.s("초", "s"))
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            }
            Canvas { ctx, size in
                let w = size.width
                let chartH = size.height
                let xPad: CGFloat = 2
                let slotTarget: CGFloat = 9
                let barCount = max(4, min(data.count, Int((w - xPad) / slotTarget)))

                // Inline downsample: group original bars into barCount buckets
                let displayBars: [(pace: Double, isFirstHalf: Bool)]
                if data.count <= barCount {
                    displayBars = data.map { ($0.paceSecPerKm, $0.isFirstHalf) }
                } else {
                    let gs = Double(data.count) / Double(barCount)
                    let halfB = barCount / 2
                    displayBars = (0..<barCount).map { b in
                        let start = Int((Double(b) * gs).rounded())
                        let end = min(data.count, Int((Double(b + 1) * gs).rounded()))
                        let group = Array(data[start..<end])
                        let avg = group.map { $0.paceSecPerKm }.reduce(0, +) / Double(group.count)
                        return (pace: avg, isFirstHalf: b < halfB)
                    }
                }

                let dPaces = displayBars.map(\.pace)
                let dMin = dPaces.min() ?? 0
                let dMax = dPaces.max() ?? 1
                let dRange = max(1.0, dMax - dMin)
                let dAvg = dPaces.reduce(0, +) / Double(dPaces.count)
                let n = displayBars.count
                let slotW = (w - xPad) / CGFloat(n)
                let barW  = slotW * 0.65
                let barGap = (slotW - barW) / 2

                func normBarH(_ pace: Double) -> CGFloat {
                    let norm = dRange > 0 ? (dMax - pace) / dRange : 0.5
                    return 8 + CGFloat(norm) * (chartH - 12)
                }

                let halfCount = displayBars.filter(\.isFirstHalf).count
                let halfX = xPad + CGFloat(halfCount) * slotW

                ctx.fill(Path(CGRect(x: xPad, y: 0, width: halfX - xPad, height: chartH)),
                         with: .color(.white.opacity(0.03)))
                ctx.fill(Path(CGRect(x: halfX, y: 0, width: w - halfX, height: chartH)),
                         with: .color(Color(hex: "5BB8FF").opacity(0.06)))

                for (i, bar) in displayBars.enumerated() {
                    let bx = xPad + CGFloat(i) * slotW + barGap
                    let bh = normBarH(bar.pace)
                    let opacity: Double = bar.pace < dAvg - 3 ? 0.85
                                        : bar.pace <= dAvg + 3 ? 0.65 : 0.45
                    ctx.fill(
                        Path(roundedRect: CGRect(x: bx, y: chartH - bh, width: barW, height: bh),
                             cornerRadius: 1.5),
                        with: .color(Color(hex: "5BB8FF").opacity(opacity))
                    )
                }

                let avgBH = normBarH(dAvg)
                let avgY  = chartH - avgBH
                var dash = Path()
                dash.move(to: CGPoint(x: xPad, y: avgY))
                dash.addLine(to: CGPoint(x: w - 32, y: avgY))
                ctx.stroke(dash, with: .color(Color(hex: "5BB8FF").opacity(0.6)),
                           style: StrokeStyle(lineWidth: 0.7, dash: [3, 2]))
                let fmtAvg = String(format: "%d'%02d\"", Int(dAvg) / 60, Int(dAvg) % 60)
                ctx.draw(
                    Text(fmtAvg).font(.system(size: 7)).foregroundStyle(Color(hex: "5BB8FF").opacity(0.85)),
                    at: CGPoint(x: w, y: avgY), anchor: .trailing
                )

                var xAxis = Path()
                xAxis.move(to: CGPoint(x: xPad, y: chartH))
                xAxis.addLine(to: CGPoint(x: w, y: chartH))
                ctx.stroke(xAxis, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 0.7))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)

            HStack {
                Text("1").font(.system(size: 6)).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(L.s("전반│후반", "1H│2H")).font(.system(size: 6)).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(totalKm.truncatingRemainder(dividingBy: 1) < 0.05
                     ? String(format: "%.0fkm", totalKm) : String(format: "%.1fkm", totalKm))
                    .font(.system(size: 6)).foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private struct TrainingDistItem {
        let label: String; let count: Int; let color: Color
    }

    // MARK: - Intensity Distribution Types

    private enum IntensityTier: CaseIterable {
        case easy, medium, hard
        var label: String {
            let L = AppLanguage.shared
            switch self {
            case .easy:   return L.s("저강도", "Low")
            case .medium: return L.s("중간",   "Mid")
            case .hard:   return L.s("고강도", "High")
            }
        }
        static func of(_ type: WorkoutType) -> IntensityTier {
            switch type {
            case .lsd, .easy:                              return .easy
            case .general, .distanceRun, .longRun, .buildUp: return .medium
            case .tempo, .interval, .race:                 return .hard
            }
        }
    }

    /// 심박 존 체류 시간 기준 강도 분포 (K-1). 회차가 아니라 시간 합산.
    private struct IntensityTimeData {
        let weeks: Int
        let policy: MRIntensityTime.Zone4Policy
        let result: MRIntensityTime.Result
        // ② 회차 기준 연속 알림 (K-7) — 유형이 이지런인 러닝의 주간 회차. 시간 기준 분포와는 별개 지표.
        /// 창 안에서 유형이 확인된 러닝 수
        let classified: Int
        /// 창 안에서 유형이 이지런(easy 티어)인 러닝 수
        let easyCount: Int
        /// 이지런 0회인 주가 현재 주부터 연속 몇 주인가
        let easyStreak: Int
        /// 유형 미확보 주에서 멈춤 → "N주 이상"
        let easyStreakAtLeast: Bool
        /// 알림 표시 조건 — 기존 방식 유지: 분류 12회 이상 · 이지런 비율 20% 미만
        var easyAlert: Bool { classified >= 12 && Double(easyCount) / Double(max(1, classified)) < 0.20 }
    }

    private var trainingDistData: (items: [TrainingDistItem], weeks: Int, totalRuns: Int, todayBucket: String?)? {
        _distResult ?? computeTrainingDistData()
    }

    /// ImageRenderer는 onAppear를 트리거하지 않으므로 _intensityResult가 nil인 채 렌더된다.
    /// trainingDistData와 동일한 폴백 패턴으로 nil이어도 즉시 계산한다.
    private var intensityDistData: IntensityTimeData? {
        if let r = _intensityResult { return r }
        return trainingDistData.flatMap { computeIntensityTimeData(weeks: $0.weeks) }
    }

    private func computeTrainingDistData() -> (items: [TrainingDistItem], weeks: Int, totalRuns: Int, todayBucket: String?)? {
        guard let fn = workoutTypeFn else { return nil }

        // 오늘 런: fn 미캐시여도 detail이 있으면 workoutType 사용
        func typeFor(_ run: Activity) -> WorkoutType? {
            if let t = fn(run.id) { return t }
            if run.id == activity.id, let det = detail { return det.workoutType }
            return nil
        }

        func evaluate(weeks: Int) -> (items: [TrainingDistItem], totalRuns: Int, todayBucket: String?)? {
            let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: activity.date) ?? .distantPast
            var runs = history.filter { $0.type == .running && $0.date >= cutoff && $0.date <= activity.date }
            if activity.type == .running, !runs.contains(where: { $0.id == activity.id }) {
                runs.append(activity)
            }

            #if DEBUG
            let df = DateFormatter(); df.dateFormat = "M/d"
            let dfFull = DateFormatter(); dfFull.dateFormat = "yyyy-MM-dd"
            let windowStart = dfFull.string(from: cutoff)
            let windowEnd   = dfFull.string(from: activity.date)
            let knownCount = runs.filter { typeFor($0) != nil }.count
            let uncachedRuns = runs.filter { typeFor($0) == nil }
            print("[훈련배분] 창 \(windowStart) ~ \(windowEnd) (열람 런 기준 \(weeks)주)")
            print("[훈련배분] \(weeks)주 러닝 \(runs.count)건 / 유형캐시 있음 \(knownCount)건 / 집계 \(knownCount)건")
            if !uncachedRuns.isEmpty {
                let dates = uncachedRuns.map { df.string(from: $0.date) }.joined(separator: ", ")
                print("[훈련배분] 캐시 없는 \(uncachedRuns.count)건 = \(dates)")
            }
            #endif

            let known = runs.filter { typeFor($0) != nil }
            guard known.count >= 8 else { return nil }

            var groups: [String: (count: Int, color: Color)] = [:]
            var todayBucket: String? = nil
            for run in known {
                guard let type = typeFor(run) else { continue }
                let b = displayBucket(for: type)
                if run.id == activity.id { todayBucket = b.label }
                if let ex = groups[b.label] { groups[b.label] = (ex.count + 1, ex.color) }
                else { groups[b.label] = (1, b.color) }
            }

            #if DEBUG
            var typeGroups: [String: [String]] = [:]
            for run in known {
                guard let type = typeFor(run) else { continue }
                let b = displayBucket(for: type)
                let comps = Calendar.current.dateComponents([.month, .day], from: run.date)
                typeGroups[b.label, default: []].append("\(comps.month ?? 0)/\(comps.day ?? 0)")
            }
            for (label, dates) in typeGroups.sorted(by: { $0.value.count > $1.value.count }) {
                print("[훈련배분] \(label): \(dates.joined(separator: ", "))")
            }
            #endif

            guard !groups.isEmpty else { return nil }
            let items = groups.map { TrainingDistItem(label: $0.key, count: $0.value.count, color: $0.value.color) }
                .sorted { $0.count > $1.count }
            return (items, runs.count, todayBucket)
        }

        if let r = evaluate(weeks: 4) { return (r.items, 4, r.totalRuns, r.todayBucket) }
        if let r = evaluate(weeks: 8) { return (r.items, 8, r.totalRuns, r.todayBucket) }
        return nil
    }

    // MARK: - Intensity Distribution (심박 존 체류 시간 · K-1)

    /// Zone 4 처리 (K-4 채택) — AT2 심박값(HRR 85%)에서 분할. 러닝별 RHR 기준.
    private static let intensityZone4Policy: MRIntensityTime.Zone4Policy = .at2Split
    /// [강도분포:주간] 로그 창 (K-8 참고용 — 존 캐시가 있는 주만 숫자가 나온다)
    private static let intensityWeeklyLogWeeks = 26

    /// 이 러닝은 카드에 이미 들어온 존(도넛과 동일), 과거 러닝은 캐시 조회. 새로 계산하지 않는다.
    /// AT2 분할 정보가 없는 구버전 존은 건너뛴다 (캐시 보충 경로가 채움).
    private func cachedZones(for run: Activity) -> [HRZoneData]? {
        func ok(_ z: [HRZoneData]?) -> [HRZoneData]? {
            guard let z, !z.isEmpty, MRIntensityTime.hasAT2Split(z) else { return nil }
            return z
        }
        if run.id == activity.id {
            if let z = ok(hrZones) { return z }
            if let z = ok(detail?.hrZones) { return z }
        }
        return ok(hrZonesFn?(run.id))
    }

    private func intensityInput(_ run: Activity) -> MRIntensityTime.RunInput {
        MRIntensityTime.RunInput(id: run.id, date: run.date, hasHR: run.avgHeartRate != nil) { [self] in
            cachedZones(for: run)
        }
    }

    private func computeIntensityTimeData(weeks: Int) -> IntensityTimeData? {
        let policy = Self.intensityZone4Policy
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: activity.date) ?? .distantPast
        var runs = history.filter { $0.type == .running && $0.date >= cutoff && $0.date <= activity.date }
        if activity.type == .running, !runs.contains(where: { $0.id == activity.id }) {
            runs.append(activity)
        }
        let inputs = runs.map(intensityInput)
        let result = MRIntensityTime.aggregate(runs: inputs, policy: policy)

        var fullRuns = history.filter { $0.type == .running }
        if activity.type == .running, !fullRuns.contains(where: { $0.id == activity.id }) {
            fullRuns.append(activity)
        }

        // ② 회차 기준 연속 알림 (K-7) — 유형 캐시로 이지런 회차를 센다. 시간 기준과 분리.
        func typeFor(_ run: Activity) -> WorkoutType? {
            if let t = workoutTypeFn?(run.id) { return t }
            if run.id == activity.id, let det = detail { return det.workoutType }
            return nil
        }
        let typed = runs.compactMap(typeFor)
        let easyCount = typed.filter { IntensityTier.of($0) == .easy }.count
        let (easyStreak, easyAtLeast) = consecutiveEasyZeroWeeks(fullHistory: fullRuns, typeFor: typeFor)

        #if DEBUG
        // 주 단위 저강도 시간 비율 로그는 지연 조회 — 캐시 있는 주만 실제로 읽힌다
        logIntensityDistribution(weeks: weeks, runs: runs, inputs: inputs, fullInputs: fullRuns.map(intensityInput),
                                 result: result, policy: policy)
        #endif

        guard result.runsWithZones >= 8 else {
            #if DEBUG
            print("[강도분포] → 미표시 (존 있는 러닝 \(result.runsWithZones)회 < 8)")
            #endif
            return nil
        }
        return IntensityTimeData(weeks: weeks, policy: policy, result: result,
                                 classified: typed.count, easyCount: easyCount,
                                 easyStreak: easyStreak, easyStreakAtLeast: easyAtLeast)
    }

    /// 「연속 N주째」— 유형이 이지런인 러닝이 0회인 주를 현재 주부터 ISO 역순으로 센다 (K-7 · 기존 방식).
    ///   - 러닝 없는 주 → 끊김
    ///   - 러닝은 있으나 유형 미확보 → 판정보류, "N주 이상"
    ///   - 이지런 1회 이상 → 끊김
    private func consecutiveEasyZeroWeeks(fullHistory: [Activity], typeFor: (Activity) -> WorkoutType?) -> (count: Int, isAtLeast: Bool) {
        let isoCal = MRIntensityTime.isoCalendar
        var count = 0
        var isAtLeast = false
        #if DEBUG
        var logParts: [String] = []
        #endif
        for weekOffset in 0..<52 {
            guard let ref = isoCal.date(byAdding: .weekOfYear, value: -weekOffset, to: activity.date) else { break }
            let wy = isoCal.component(.weekOfYear,        from: ref)
            let yr = isoCal.component(.yearForWeekOfYear, from: ref)
            let wStr = "\(yr)-W\(String(format: "%02d", wy))"
            let allWeekRuns = fullHistory.filter {
                $0.date <= activity.date &&
                isoCal.component(.weekOfYear,        from: $0.date) == wy &&
                isoCal.component(.yearForWeekOfYear, from: $0.date) == yr
            }
            let typedWeekRuns = allWeekRuns.filter { typeFor($0) != nil }
            if allWeekRuns.isEmpty {
                #if DEBUG
                logParts.append("\(wStr) 런없음 ✗")
                #endif
                break
            }
            if typedWeekRuns.isEmpty {
                isAtLeast = true
                #if DEBUG
                logParts.append("\(wStr) 러닝\(allWeekRuns.count)건·유형없음 → 판정보류")
                #endif
                break
            }
            let easyCount = typedWeekRuns.filter { typeFor($0).map { IntensityTier.of($0) == .easy } ?? false }.count
            if easyCount > 0 {
                #if DEBUG
                logParts.append("\(wStr) 이지런\(easyCount) ✗")
                #endif
                break
            }
            count += 1
            #if DEBUG
            logParts.append("\(wStr) 이지런0 ✓")
            #endif
        }
        #if DEBUG
        let suffix = isAtLeast ? " 이상" : ""
        print("[강도분포] 연속 판정 — 이지런 회차 기준 · 주 단위 역순 검사 (ISO)\n    \(logParts.joined(separator: " / "))\n    → \(count)주째\(suffix)")
        #endif
        return (count, isAtLeast)
    }

    #if DEBUG
    private func logIntensityDistribution(weeks: Int, runs: [Activity], inputs: [MRIntensityTime.RunInput],
                                          fullInputs: [MRIntensityTime.RunInput],
                                          result: MRIntensityTime.Result,
                                          policy: MRIntensityTime.Zone4Policy) {
        let df = DateFormatter(); df.dateFormat = "M/d"
        func mins(_ sec: Double) -> String { Int((sec / 60).rounded()).formatted() }
        func pct(_ f: Double) -> Int { Int((f * 100).rounded()) }
        func line(_ b: MRIntensityTime.Buckets) -> String {
            "저강도 \(mins(b.lowSec))분(\(pct(b.lowFrac))%) · 중간 \(mins(b.midSec))분(\(pct(b.midFrac))%) · 고강도 \(mins(b.highSec))분(\(pct(b.highFrac))%)"
        }

        print("[강도분포] 기준 = 심박 존 체류 시간 (\(weeks)주)")
        if let z = cachedZones(for: activity), z.count == 5 {
            let z1 = z[0], z2 = z[1], z3 = z[2], z4 = z[3], z5 = z[4]
            print("[강도분포] 존 경계 Zone1<\(z2.minBPM) / Zone2 \(z2.minBPM)-\(z2.maxBPM) / Zone3 \(z3.minBPM)-\(z3.maxBPM) / Zone4 \(z4.minBPM)-\(z4.maxBPM) / Zone5 \(z5.minBPM)+ (이 러닝 기준 · 러닝별 RHR로 조금씩 다름)")
            let at2 = z4.splitBPM.map(String.init) ?? "?"
            let scheme = z1.minBPM > 0 ? "HRR 85%" : "%MHR 90% 폴백"
            print("[강도분포] AT1=\(z2.maxBPM) · AT2=\(at2) (\(scheme)) · 저강도 ~\(z2.maxBPM) / 중간 \(z3.minBPM)~\(z4.splitBPM.map { "\($0 - 1)" } ?? "?") / 고강도 \(at2)~ · \(policy.label)")
        } else {
            print("[강도분포] 존 경계 — 이 러닝의 존 데이터 없음 (\(policy.label))")
        }
        print("[강도분포] \(result.runsTotal)회 중 심박 존 있음 \(result.runsWithZones)회 · 총 \(mins(result.buckets.totalSec))분")
        print("           \(line(result.buckets))")
        for alt in MRIntensityTime.Zone4Policy.allCases where alt != policy {
            let b = MRIntensityTime.aggregate(runs: inputs, policy: alt).buckets
            print("[강도분포] 대안 비교 — \(alt.label): \(line(b))")
        }
        if !result.runsNoHR.isEmpty {
            let dates = result.runsNoHR.map { df.string(from: $0.date) }.joined(separator: ", ")
            print("[강도분포] 심박 없음 \(result.runsNoHR.count)건 분모 제외 = \(dates)")
        }
        if !result.runsZonesMissing.isEmpty {
            let dates = result.runsZonesMissing.map { df.string(from: $0.date) }.joined(separator: ", ")
            print("[강도분포] 심박 있으나 존 캐시 없음 \(result.runsZonesMissing.count)건 분모 제외 = \(dates)")
        }

        // 참고 — 이전 기준(유형 → 쉬움/중간/강함 회차)
        if let fn = workoutTypeFn {
            func typeFor(_ run: Activity) -> WorkoutType? {
                if let t = fn(run.id) { return t }
                if run.id == activity.id, let det = detail { return det.workoutType }
                return nil
            }
            var c: [IntensityTier: Int] = [:]
            var unclassified = 0
            for r in runs {
                if let t = typeFor(r) { c[IntensityTier.of(t), default: 0] += 1 } else { unclassified += 1 }
            }
            let unc = unclassified > 0 ? " (분류 중 \(unclassified)건)" : ""
            print("[강도분포] 참고 — 유형 기준으로는 쉬움\(c[.easy] ?? 0) 중간\(c[.medium] ?? 0) 강함\(c[.hard] ?? 0) 였음\(unc)")
        }

        // 주 단위 저강도 시간 비율 (K-8 참고 — 연속 판정에는 쓰지 않음)
        let weekly = MRIntensityTime.weeklyLowFractions(
            runs: fullInputs, anchor: activity.date, weeks: Self.intensityWeeklyLogWeeks, policy: policy)
        let weekParts = weekly.map { w -> String in
            guard let lf = w.lowFrac else { return "\(w.shortLabel) -" }
            return "\(w.shortLabel) \(pct(lf))%\(w.inProgress ? "(진행중)" : "")"
        }
        var weeklyLog = "[강도분포:주간] 최근 \(Self.intensityWeeklyLogWeeks)주 저강도 시간 비율 (존 캐시 있는 주만)\n      \(weekParts.joined(separator: " · "))"
        if let sm = MRIntensityTime.summary(of: weekly) {
            weeklyLog += "\n      중앙값 \(pct(sm.median))% · 최소 \(pct(sm.min))% · 최대 \(pct(sm.max))% (완료 주 \(sm.count)개 · 진행 중 주 제외)"
        }
        print(weeklyLog)
    }
    #endif

    private func displayBucket(for type: WorkoutType) -> (label: String, color: Color) {
        let L = AppLanguage.shared
        switch type {
        case .interval:    return (L.s("인터벌",   "Interval"),  Color(hex: "FF9A3C"))
        case .tempo:       return (L.s("템포런",   "Tempo"),     Color(hex: "F5C542"))
        case .buildUp:     return (L.s("빌드업",   "Build-Up"),  Color(hex: "FFD166"))
        case .distanceRun: return (L.s("거리주",   "Dist.Run"),  Color(hex: "5BB8FF"))
        case .lsd:         return (L.s("LSD",      "LSD"),       Color(hex: "8B7FF0"))
        case .longRun:     return (L.s("롱런",     "Long Run"),  Color(hex: "7C5CFC"))
        case .easy:        return (L.s("이지런",   "Easy"),      Color(hex: "6B7280"))
        case .race:        return (L.s("대회",     "Race"),      Theme.violet)
        case .general:     return (L.s("일반 러닝","General"),   Color(hex: "8A8A92"))
        }
    }

    @ViewBuilder
    private func distribHorizontalSection(items: [TrainingDistItem], weeks: Int, totalRuns: Int, todayBucket: String?) -> some View {
        let classified = items.map(\.count).reduce(0, +)
        let unclassified = totalRuns - classified
        let maxCount = max(1, items.map(\.count).max() ?? 1)
        let L = AppLanguage.shared
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(L.s("이 러닝 기준 \(weeks)주 · \(totalRuns)회", "Before this run · \(weeks)w · \(totalRuns)"))
                    .font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(.white.opacity(0.90))
                if unclassified > 0 {
                    Text(L.s("분류 중 \(unclassified)건", "+\(unclassified) pending"))
                        .font(.system(size: 8)).foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            ForEach(items, id: \.label) { item in
                let isToday = item.label == todayBucket
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Text(item.label)
                            .font(.system(size: 8)).foregroundStyle(isToday ? .white : IC.label)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        if isToday {
                            Text(L.s("(오늘)", "(today)"))
                                .font(.system(size: 7)).foregroundStyle(item.color)
                        }
                    }
                    .frame(width: 46, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(item.color.opacity(isToday ? 1.0 : 0.85))
                                .frame(width: max(4, geo.size.width * CGFloat(item.count) / CGFloat(maxCount)))
                        }
                    }
                    .frame(height: 8)
                    Text("\(item.count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(item.color)
                        .frame(width: 14, alignment: .trailing)
                }
            }
            if unclassified > 0 {
                Text(L.s("총 \(totalRuns)회 (분류 중 \(unclassified)건)", "\(totalRuns) runs (\(unclassified) pending)"))
                    .font(.system(size: 8)).foregroundStyle(IC.label)
            } else {
                Text(L.s("총 \(totalRuns)회", "\(totalRuns) runs"))
                    .font(.system(size: 8)).foregroundStyle(IC.label)
            }
        }
    }

    /// 강도 분포(4주, 세로 막대 + 문헌값 눈금) · 이 러닝 날짜 기준 7일 강도 부하 반반 배치.
    /// 강도 기록이 없으면 오른쪽 반쪽을 생략하고 왼쪽을 전체 폭으로 둔다.
    @ViewBuilder
    private func intensityDistSection(data: IntensityTimeData) -> some View {
        let load = sevenDayLoad
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                intensityColumnsView(data: data)
                    .frame(maxWidth: .infinity)
                if let load {
                    Rectangle().fill(.white.opacity(0.10))
                        .frame(width: 0.5)
                        .padding(.vertical, 2)
                    sevenDayLoadView(load: load)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// 강도 분포 · 4주 — 저/중/고 세로 막대. 축은 0…max(관측 최대, 참고선 최대)로 잡아 눈금이 항상 보이게 한다.
    @ViewBuilder
    private func intensityColumnsView(data: IntensityTimeData) -> some View {
        let L = AppLanguage.shared
        let b = data.result.buckets
        // L-1 참고선 — 지구력 종목 문헌값. 목표·권장이 아니라 참고선. (lo == hi 면 눈금 하나, 아니면 옷은 밴드 + 양끝 눈금)
        let rows: [(tier: IntensityTier, sec: Double, frac: Double, refLo: Double, refHi: Double)] = [
            (.easy,   b.lowSec,  b.lowFrac,  0.80, 0.80),
            (.medium, b.midSec,  b.midFrac,  0.00, 0.05),
            (.hard,   b.highSec, b.highFrac, 0.15, 0.20),
        ]
        let excluded = data.result.runsNoHR.count + data.result.runsZonesMissing.count
        let totalMin = Int((b.totalSec / 60).rounded())
        // 상단 여유 6% — 80% 눈금이 프레임 위로 잘리지 않게.
        let axisFrac = max(0.80, b.lowFrac, b.midFrac, b.highFrac) * 1.06
        let barH: CGFloat = 56
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(L.s("강도 분포 · \(data.weeks)주 · 심박 존 \(totalMin)분", "Intensity · \(data.weeks)w · \(totalMin) min in HR zones"))
                    .font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1).minimumScaleFactor(0.8)
                if excluded > 0 {
                    Text(L.s("심박 없음 \(excluded)건 제외", "\(excluded) w/o HR excluded"))
                        .font(.system(size: 8)).foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            // 막대 폭은 오른쪽 7일 부하 막대와 동일(반폭 기준 7등분) — 남는 폭에 참고선 설명 2줄
            GeometryReader { geo in
                let gap: CGFloat = 3
                // 오른쪽 7일 부하와 같은 슬롯 폭(반폭 7등분)의 85% — 두 차트 막대를 조금 가늘게
                let barW = max(8, (geo.size.width - gap * 6) / 7 * 0.85)
                HStack(alignment: .bottom, spacing: gap) {
                    Spacer(minLength: 0)   // 왼쪽 여백은 유동, 오른쪽 여백은 최대 16 → 묶음이 오른쪽으로 치우친다
                    ForEach(rows, id: \.tier) { row in
                        let pct = Int((row.frac * 100).rounded())
                        let mins = Int((row.sec / 60).rounded())
                        VStack(spacing: 3) {
                            Text("\(pct)%")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(intensityColor(row.tier))
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Text(L.s("\(mins)분", "\(mins)m"))
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1).minimumScaleFactor(0.6)
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2.5).fill(.white.opacity(0.06))
                                // 참고 범위 밴드 — 옅은 흰색, 경고색 없음, 미달 강조 없음
                                if row.refHi > row.refLo {
                                    Rectangle()
                                        .fill(.white.opacity(0.10))
                                        .frame(height: barH * CGFloat((row.refHi - row.refLo) / axisFrac))
                                        .offset(y: -barH * CGFloat(row.refLo / axisFrac))
                                }
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(intensityColor(row.tier).opacity(0.85))
                                    .frame(height: max(2, barH * CGFloat(row.frac / axisFrac)))
                                // 가로 점선 — 0 지점은 막대 밑바닥이라 생략
                                ForEach(Array(Set([row.refLo, row.refHi]).filter { $0 > 0 }.sorted()), id: \.self) { r in
                                    IntensityTickLine()
                                        .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [1.5, 1.5]))
                                        .frame(height: 1)
                                        .offset(y: -barH * CGFloat(r / axisFrac))
                                }
                            }
                            .frame(height: barH)
                            Text(row.tier.label)
                                .font(.system(size: 8)).foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(width: barW)
                    }
                    // 남는 폭: 점선 설명 2줄 (막대 밑바닥에 맞춰 아래 정렬)
                    VStack(alignment: .leading, spacing: 2) {
                        Spacer(minLength: 0)
                        Text(L.s("점선 - 문헌값", "dashed - reference"))
                        Text(L.s("(지구력 종목)", "(endurance)"))
                        Spacer().frame(height: 14)   // 하단 유형 라벨 높이만큼 띄워 막대 밑바닥에 맞춘다
                    }
                    .font(.system(size: 8)).foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.leading, 4)
                    .fixedSize()
                    Spacer(minLength: 0).frame(maxWidth: 16)
                }
                .frame(width: geo.size.width)
            }
            .frame(height: barH + 3 + 11 + 3 + 11 + 3 + 11)
            // 오른쪽 "이 러닝 N AU …" 캡션과 같은 위치(차트 바로 아래)
            // ① 시간 기준 (K-2) — 사실 한 줄. 평가어·참고선 없음. 연속 개념 없음.
            let lowPct = Int((b.lowFrac * 100).rounded())
            Text(L.s(
                "최근 \(data.weeks)주 훈련 시간의 \(lowPct)%가 저강도예요.",
                "\(lowPct)% of your training time in the last \(data.weeks) weeks was low intensity."
            ))
            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
            // ② 회차 기준 (K-7) — 유형이 이지런인 러닝의 회차. «19%인데 왜 0회?»로 읽히지 않게 라벨로 구분.
            if data.easyAlert {
                let w = data.easyStreak, atLeast = data.easyStreakAtLeast
                let streakSuffix: String = {
                    guard w > 1 || (w == 1 && atLeast) else { return "" }
                    return L.s(" · \(w)주\(atLeast ? " 이상" : "")째", " · \(w)\(atLeast ? "+" : "") wk in a row")
                }()
                Text(L.s(
                    "이지런으로 계획한 러닝 \(data.easyCount)회\(streakSuffix)",
                    "Runs planned as easy: \(data.easyCount)\(streakSuffix)"
                ))
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            }

        }
    }

    /// 이 러닝 날짜로 끝나는 7일 강도 부하 — 일별 막대, 이 러닝 날은 테두리 강조.
    @ViewBuilder
    private func sevenDayLoadView(load: SevenDayLoad) -> some View {
        let L = AppLanguage.shared
        let cal = Calendar.current
        let w = load.window
        let maxAU = max(w.daily.max() ?? 0, 1)
        // 왼쪽 강도 분포(막대 56 + 위 두 줄 텍스트 28)와 같은 높이 — 요일 라벨이 유형 라벨과 나란히 온다
        let barH: CGFloat = 56 + 28
        let runDay = cal.startOfDay(for: activity.date)
        VStack(alignment: .leading, spacing: 5) {
            Text(L.s("강도 부하 · 7일", "Training load · 7d"))
                .font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(.white.opacity(0.90))
                .lineLimit(1).minimumScaleFactor(0.8)
            GeometryReader { geo in
            let slotW = (geo.size.width - 3 * 6) / 7
            let barW = max(8, slotW * 0.85)   // 왼쪽 강도 분포 막대와 같은 폭
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(w.dayStarts.enumerated()), id: \.offset) { i, day in
                    let au = w.daily.indices.contains(i) ? w.daily[i] : 0
                    let isRunDay = cal.isDate(day, inSameDayAs: runDay)
                    VStack(spacing: 3) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.06))
                            if au > 0 {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(dayLoadColor(w, i))
                                    .frame(height: max(3, barH * CGFloat(au / maxAU)))
                            }
                        }
                        .frame(width: barW, height: barH)
                        .overlay {
                            if isRunDay {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                            }
                        }
                        Text(weekdayInitial(day, calendar: cal))
                            .font(.system(size: 8, weight: isRunDay ? .bold : .regular))
                            .foregroundStyle(isRunDay ? Color.white.opacity(0.90) : IC.label)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            }
            .frame(height: barH + 3 + 11)
            Text(sevenDayLoadCaption(load))
                .font(.system(size: 8)).foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
            if let kind = load.sentence {
                Text(sevenDayLoadSentence(kind))
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dayLoadColor(_ w: EffortLoad.WindowLoad, _ i: Int) -> Color {
        let mean = w.dailyMeanEffort.indices.contains(i) ? w.dailyMeanEffort[i] : nil
        return EffortPalette.color(for: EffortResolver.clamp(mean ?? 5))
    }

    private func weekdayInitial(_ date: Date, calendar: Calendar) -> String {
        let ko = ["일", "월", "화", "수", "목", "금", "토"]
        let en = ["S", "M", "T", "W", "T", "F", "S"]
        let i = max(0, min(6, calendar.component(.weekday, from: date) - 1))
        return AppLanguage.shared.s(ko[i], en[i])
    }

    /// "이 러닝 109 AU · 7일 1,047 AU · 4주 평균 대비 낮음" — 없는 조각은 빠진다.
    /// 단조도 / 4주 평균 대비 문장 — "부상·위험" 표현 없음(Impellizzeri 2020)
    private func sevenDayLoadSentence(_ kind: EffortLoad.SentenceKind) -> String {
        let L = AppLanguage.shared
        switch kind {
        case .monotony: return L.s("부하 편차가 거의 없었어요. 쉬운 날과 힘든 날을 나눠 보세요.",
                                   "Very little variation in load. Try separating easy and hard days.")
        case .veryHigh: return L.s("최근 4주 평균보다 부하가 많이 높은 주예요.", "A much heavier week than your 4-week average.")
        case .high:     return L.s("평소보다 조금 높은 주예요.", "A slightly heavier week than usual.")
        case .low:      return L.s("회복 쪽으로 기운 주예요.", "A lighter, recovery-leaning week.")
        }
    }

    private func sevenDayLoadCaption(_ load: SevenDayLoad) -> String {
        let L = AppLanguage.shared
        func au(_ v: Double) -> String { Int(v.rounded()).formatted(.number.grouping(.automatic)) }
        var parts: [String] = []
        if let t = load.thisRunAU {
            parts.append(L.s("이 러닝 \(au(t)) AU", "This run \(au(t)) AU"))
        }
        parts.append(L.s("7일 \(au(load.window.total)) AU", "7d \(au(load.window.total)) AU"))
        if let ac = load.acuteChronic {
            let t: String
            switch ac {
            case .low:      t = L.s("낮음", "lower")
            case .steady:   t = L.s("유지", "steady")
            case .high:     t = L.s("높음", "higher")
            case .veryHigh: t = L.s("크게 높음", "much higher")
            }
            parts.append(L.s("4주 평균 대비 \(t)", "vs 4-wk avg \(t)"))
        }
        return parts.joined(separator: " · ")
    }

    private func intensityColor(_ tier: IntensityTier) -> Color {
        switch tier {
        case .easy:   return Color(hex: "#6BAED6")   // 연한 파랑 — 쉬움
        case .medium: return Color(hex: "#4A7FC1")   // 중간 파랑
        case .hard:   return Color(hex: "#2C4E8A")   // 진한 파랑 — 강함
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
        let L = AppLanguage.shared
        for cat: InsightCategory in [.efficiency, .endurance, .load, .cardio] {
            guard let m = insights.first(where: { $0.category == cat })?.message else { continue }
            if cat == .cardio && (age == nil || isMale == nil) {
                return L.s("애플 건강 앱에서 나이와 성별 입력 필요합니다.", "Enter age & gender in Apple Health.")
            }
            return m
        }
        return insights.first?.message
    }

    // MARK: - Return insight (복귀 인사이트)

    private struct ReturnInsightInfo {
        let gapDays: Int
        let preGapHR: Double?
        let todayHR: Double?
        let isExpiredByTime: Bool
        let hrRecovered: Bool
    }

    private var returnInsight: ReturnInsightInfo? {
        guard activity.type == .running else { return nil }
        let cal = Calendar.current
        let sorted = history.filter { $0.type == .running }.sorted { $0.date < $1.date }
        guard let idx = sorted.firstIndex(where: { $0.id == activity.id }), idx > 0 else {
            #if DEBUG
            let runCount = history.filter { $0.type == .running }.count
            print("[복귀] 미발동: history 러닝 \(runCount)회, activity.id 찾기 실패 또는 첫 러닝")
            #endif
            return nil
        }

        let prev = sorted[idx - 1]
        let gapFromPrev = cal.dateComponents([.day], from: prev.date, to: activity.date).day ?? 0

        // ── 1번째 복귀 러닝: "N일 만의 러닝이에요" ───────────────────────────
        if gapFromPrev >= 14 {
            let preGapRuns = sorted.filter {
                $0.date < prev.date && $0.date >= prev.date.addingTimeInterval(-28 * 86_400)
            }
            let preGapHR: Double? = preGapRuns.count >= 3 ? {
                if let todayPace = activity.paceSecPerKm {
                    let matched = preGapRuns.filter {
                        guard let p = $0.paceSecPerKm else { return false }
                        return abs(p - todayPace) / todayPace <= 0.20
                    }
                    if matched.count >= 2 {
                        let hrs = matched.compactMap { $0.avgHeartRate }
                        if !hrs.isEmpty { return Double(hrs.reduce(0, +)) / Double(hrs.count) }
                    }
                }
                let hrs = preGapRuns.compactMap { $0.avgHeartRate }
                return hrs.isEmpty ? nil : Double(hrs.reduce(0, +)) / Double(hrs.count)
            }() : nil
            let daysSince = cal.dateComponents([.day], from: activity.date, to: Date()).day ?? 0
            #if DEBUG
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let matchedCount: Int = {
                guard let todayPace = activity.paceSecPerKm else { return 0 }
                return preGapRuns.filter {
                    guard let p = $0.paceSecPerKm else { return false }
                    return abs(p - todayPace) / todayPace <= 0.20
                }.count
            }()
            print("[복귀] 직전 러닝 \(df.string(from: prev.date)) · 간격 \(gapFromPrev)일 (기준 14일) → 발동")
            print("[복귀] 공백 전 4주: 러닝 \(preGapRuns.count)회 · 같은 페이스 심박 \(matchedCount)회 · 공백 전 심박 \(preGapHR.map { String(Int($0)) } ?? "없음")")
            if let today = activity.avgHeartRate {
                if let pre = preGapHR {
                    let diff = today - Int(pre)
                    print("[복귀] 오늘 심박 \(today) vs 공백 전 \(Int(pre)) → \(diff >= 0 ? "+" : "")\(diff)bpm")
                } else {
                    print("[복귀] 오늘 심박 \(today) · 공백 전 심박 없음 (공백 전 런 \(preGapRuns.count)회 < 3 or HR data 없음)")
                }
            } else {
                print("[복귀] 오늘 심박 없음")
            }
            #endif
            return ReturnInsightInfo(
                gapDays: gapFromPrev,
                preGapHR: preGapHR,
                todayHR: activity.avgHeartRate.map(Double.init),
                isExpiredByTime: daysSince >= 28,
                hrRecovered: false  // 첫 복귀 런에서는 심박 회복 메시지 절대 표시 안 함
            )
        }

        // ── 2회차 이상 복귀 러닝: "심박이 돌아왔어요" ──────────────────────
        // 최근 28일 안에 ≥14일 공백이 있었고, 그 복귀 후 2번째 이상 런인 경우에만 평가
        for i in stride(from: idx - 1, through: 1, by: -1) {
            let daysSinceI = cal.dateComponents([.day], from: sorted[i].date, to: activity.date).day ?? 0
            guard daysSinceI <= 28 else { break }
            let prevToI = cal.dateComponents([.day], from: sorted[i - 1].date, to: sorted[i].date).day ?? 0
            guard prevToI >= 14 else { continue }
            // sorted[i]가 첫 복귀 런 — activity는 2회차 이상
            let preGapEnd = sorted[i - 1]
            let preGapRuns = sorted.filter {
                $0.date < preGapEnd.date && $0.date >= preGapEnd.date.addingTimeInterval(-28 * 86_400)
            }
            guard preGapRuns.count >= 3 else { return nil }
            let preGapHR: Double? = {
                if let todayPace = activity.paceSecPerKm {
                    let matched = preGapRuns.filter {
                        guard let p = $0.paceSecPerKm else { return false }
                        return abs(p - todayPace) / todayPace <= 0.20
                    }
                    if matched.count >= 2 {
                        let hrs = matched.compactMap { $0.avgHeartRate }
                        if !hrs.isEmpty { return Double(hrs.reduce(0, +)) / Double(hrs.count) }
                    }
                }
                let hrs = preGapRuns.compactMap { $0.avgHeartRate }
                return hrs.isEmpty ? nil : Double(hrs.reduce(0, +)) / Double(hrs.count)
            }()
            guard let pre = preGapHR else { return nil }
            // 첫 복귀 런부터 현재까지 (2회 이상) — 심박 평균이 공백 전 대비 ≤+3bpm이면 회복
            let postRuns = sorted.filter { $0.date >= sorted[i].date && $0.date <= activity.date }
            guard postRuns.count >= 2 else { return nil }
            let postHRs = postRuns.compactMap { $0.avgHeartRate }
            guard !postHRs.isEmpty else { return nil }
            let postAvgHR = Double(postHRs.reduce(0, +)) / Double(postHRs.count)
            guard (postAvgHR - pre) <= 3 else { return nil }
            let daysSince = cal.dateComponents([.day], from: sorted[i].date, to: Date()).day ?? 0
            return ReturnInsightInfo(
                gapDays: prevToI,
                preGapHR: preGapHR,
                todayHR: activity.avgHeartRate.map(Double.init),
                isExpiredByTime: daysSince >= 28,
                hrRecovered: true
            )
        }
        return nil
    }

    private var returnRecoveredRow: some View {
        let L = AppLanguage.shared
        return HStack(spacing: 8) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "30D158"))
            Text(L.s("심박이 공백 전 수준으로 돌아왔어요", "Your HR is back to pre-break levels"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "30D158"))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(hex: "1A3020"))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func returnInsightRow(_ ri: ReturnInsightInfo) -> some View {
        let L = AppLanguage.shared
        let blue = Color(hex: "0A84FF")
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(blue)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(L.s("\(ri.gapDays)일 만의 러닝이에요", "First run in \(ri.gapDays) days"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if let pre = ri.preGapHR, let today = ri.todayHR {
                    Text(L.s("공백 전 같은 페이스에서 심박 \(Int(pre.rounded()))이었는데 오늘은 \(Int(today.rounded()))이에요",
                             "Pre-gap HR was \(Int(pre.rounded())) at this pace — today \(Int(today.rounded()))"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
                if ri.gapDays >= 28 {
                    Text(L.s("체력이 돌아오는 데 보통 공백만큼의 시간이 걸려요. 2~3주에 걸쳐 천천히 올려도 괜찮아요",
                             "Fitness takes about as long as the break to return. Build back gradually over 2–3 weeks."))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(blue.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Race Insight Card

private struct RaceInsightCard: View {
    let activity: Activity
    var detail: ActivityDetail? = nil
    var age: Int? = nil
    var isMale: Bool? = nil
    var confirmedRace: PersistedRaceMatch? = nil
    var confirmedRaces: [PersistedRaceMatch] = []
    var history: [Activity] = []
    var raceDetailFn: ((UUID) -> ActivityDetail?)? = nil

    // MARK: Types

    private enum FormEndurance {
        case held         // 폼 유지: cad ≤2% AND stride ≤3%
        case mid          // 중간: 사실만
        case collapsed    // 후반 붕괴: cad or stride >5%
        case noData
    }

    private enum LimitFactor {
        case cardio       // 심폐 제한: HR ≥90% AND 폼 유지
        case endurance    // 지구력 제한: HR <90% AND 폼 붕괴
        case balanced     // 균형: HR ≥90% AND 폼 붕괴
        case managed      // 잘 된 레이스: HR <90% AND 폼 유지/중간
        case noData
    }

    // MARK: Body

    var body: some View {
        let L = AppLanguage.shared
        VStack(alignment: .leading, spacing: 14) {
            // ── 헤더: 대회명 + 거리
            if let race = confirmedRace {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.violet)
                    Text(race.raceName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.4))
                    Text(distanceDivision(km: race.distanceKm))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.violet)
                    Spacer()
                }
            }

            // ── KPI row
            HStack(spacing: 0) {
                KPICell(label: L.s("시간", "Time"), value: activity.formattedDuration)
                kpiSep
                KPICell(label: L.s("페이스", "Pace"),
                        value: activity.formattedPace ?? "--'--\"")
                kpiSep
                if let hr = activity.avgHeartRate {
                    let maxHR = estimatedMaxHR
                    let pct = maxHR > 0 ? Int((Double(hr) / Double(maxHR) * 100).rounded()) : 0
                    KPICell(label: L.s("심박", "HR"),
                            value: "\(hr)", unit: "bpm", color: IC.hrRed,
                            context: maxHR > 0 ? "max \(pct)%" : nil)
                } else {
                    KPICell(label: L.s("심박", "HR"), value: "--", color: .secondary)
                }
                kpiSep
                if let cad = detail?.avgCadence {
                    KPICell(label: L.s("케이던스", "Cadence"),
                            value: "\(cad)", unit: "spm", color: IC.cadCyan)
                } else {
                    KPICell(label: L.s("케이던스", "Cadence"), value: "--", color: .secondary)
                }
            }

            // ── 폼 유지력 섹션
            let fe = formEndurance
            if fe != .noData {
                Color.white.opacity(0.1).frame(height: 0.5)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.s("폼 유지력", "Form Endurance"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                    formEnduranceRow(fe)
                }
            }

            // ── 제한 요인 섹션
            let lf = limitingFactor
            if lf != .noData {
                Color.white.opacity(0.1).frame(height: 0.5)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.s("제한 요인", "Limiting Factor"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                    limitingFactorRow(lf)
                }
            }

            // ── [10] 대회에서 지면접촉이 짧아지는 현상 인정
            if let note = gctNote {
                Color.white.opacity(0.1).frame(height: 0.5)
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(IC.greenText)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(IC.greenBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // ── 대회 간 비교 (같은 거리 2개 이상)
            let sdr = sameDistanceRaces
            if !sdr.isEmpty {
                Color.white.opacity(0.1).frame(height: 0.5)
                crossRaceSection(sdr)
            }

            // ── 거리별 붕괴 곡선 (3개 이상 대회, 2개 이상 부문)
            let dcRows = distanceCollapseRows
            if !dcRows.isEmpty && dcRows.contains(where: { $0.form != .noData }) {
                Color.white.opacity(0.1).frame(height: 0.5)
                distanceCollapseSection(dcRows)
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Subviews

    private var kpiSep: some View {
        Color.white.opacity(0.12).frame(width: 0.5, height: 28)
    }

    @ViewBuilder
    private func formEnduranceRow(_ fe: FormEndurance) -> some View {
        let L = AppLanguage.shared
        let (text, color): (String, Color) = {
            switch fe {
            case .held:
                return (L.s("후반까지 폼이 유지됐어요 — 케이던스·보폭 변화 모두 안정적이었어요",
                            "Form held to the finish — cadence and stride stayed stable"), IC.green)
            case .collapsed:
                return (L.s("후반에 폼이 무너졌어요 — 케이던스나 보폭이 5% 이상 줄었어요",
                            "Form broke down in the second half — cadence or stride dropped over 5%"), Color(hex: "FF9A3C"))
            case .mid:
                return (L.s("폼이 일부 흔들렸지만 붕괴 수준은 아니었어요",
                            "Form wobbled slightly but didn't fully collapse"), Color.white.opacity(0.7))
            case .noData:
                return ("", .clear)
            }
        }()
        if !text.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: fe == .held ? "checkmark.circle.fill" : (fe == .collapsed ? "exclamationmark.circle.fill" : "minus.circle.fill"))
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(color)
            }
        }
        if let detail = formHalvesDetail {
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.leading, 18)
        }
    }

    @ViewBuilder
    private func limitingFactorRow(_ lf: LimitFactor) -> some View {
        let L = AppLanguage.shared
        let (icon, text, color): (String, String, Color) = {
            switch lf {
            case .cardio:
                return ("lungs.fill",
                        L.s("심폐 제한 — 심박이 최대에 가까웠고 폼은 유지됐어요. 심폐가 먼저 한계에 닿은 레이스예요",
                            "Cardio-limited — HR near max but form held. Your cardiovascular system hit the ceiling first"),
                        IC.hrRed)
            case .endurance:
                return ("figure.run",
                        L.s("지구력 제한 — 심박 여유가 있었지만 폼이 무너졌어요. 근육 지구력이 먼저 소진됐어요",
                            "Endurance-limited — HR had headroom but form collapsed. Muscular endurance gave out first"),
                        Color(hex: "FF9A3C"))
            case .balanced:
                return ("arrow.left.arrow.right",
                        L.s("심폐·지구력 동시 한계 — 심박도 높고 폼도 무너졌어요. 두 시스템 모두 한계에 도달한 레이스예요",
                            "Both systems maxed — high HR and form breakdown. Cardio and endurance hit the wall together"),
                        Color(hex: "F5C542"))
            case .managed:
                return ("checkmark.seal.fill",
                        L.s("잘 관리된 레이스 — 심박 여유가 있었고 폼도 유지됐어요",
                            "Well-managed effort — HR had room and form held throughout"),
                        IC.green)
            case .noData:
                return ("", "", .clear)
            }
        }()
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(color)
                    Text(text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(color)
                }
                if let suggestion = limitingFactorSuggestion(lf) {
                    Text(suggestion)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.leading, 18)
                }
            }
        }
    }

    private func limitingFactorSuggestion(_ lf: LimitFactor) -> String? {
        let L = AppLanguage.shared
        switch lf {
        case .endurance:
            return L.s(
                "다음 대회 전 30km 이상 롱런을 2~3회 넣으면 감속 지점을 뒤로 밀 수 있어요.",
                "Adding 2–3 long runs of 30 km+ before your next race can push your fade point back."
            )
        case .cardio:
            return L.s(
                "폼이 끝까지 버텼으니 다음엔 조금 더 공격적인 목표 페이스를 잡아봐도 좋겠어요.",
                "Your form held to the end — you can afford to set a slightly more aggressive goal pace next time."
            )
        case .balanced, .managed, .noData:
            return nil
        }
    }

    @ViewBuilder
    private func crossRaceSection(_ races: [(match: PersistedRaceMatch, activity: Activity)]) -> some View {
        let L = AppLanguage.shared
        VStack(alignment: .leading, spacing: 6) {
            Text(L.s("같은 거리 대회 비교", "Same Distance Races"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            ForEach(Array(races.enumerated()), id: \.offset) { _, entry in
                let cal = Calendar.current
                let comps = cal.dateComponents([.year, .month], from: entry.activity.date)
                let label = "\(comps.year ?? 0). \(comps.month ?? 0)"
                HStack(spacing: 0) {
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(width: 56, alignment: .leading)
                    Text(entry.activity.formattedPace ?? "--'--\"")
                        .font(cardNumFont(12))
                        .foregroundStyle(entry.activity.id == activity.id ? Theme.violet : Color.white.opacity(0.85))
                        .frame(width: 56, alignment: .trailing)
                    Text("/km")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .padding(.leading, 2)
                    Spacer()
                    if let hr = entry.activity.avgHeartRate {
                        Text("\(hr) bpm")
                            .font(.system(size: 10))
                            .foregroundStyle(IC.hrRed.opacity(entry.activity.id == activity.id ? 1.0 : 0.6))
                    }
                }
            }
        }
    }

    // MARK: Computed

    private var estimatedMaxHR: Int {
        guard let a = age else { return 0 }
        // Tanaka formula: 208 − 0.7 × age
        return Int((208.0 - 0.7 * Double(a)).rounded())
    }

    private var formEndurance: FormEndurance {
        guard let splits = detail?.splits else { return .noData }
        let full = splits.filter { $0.distanceM >= 900 }
        guard full.count >= 4 else { return .noData }
        let half = full.count / 2
        let s1 = Array(full.prefix(half))
        let s2 = Array(full.suffix(full.count - half))

        func avgCad(_ arr: [SplitData]) -> Double? {
            let v = arr.compactMap(\.avgCadence).map(Double.init)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        func avgStride(_ arr: [SplitData]) -> Double? {
            let v = arr.compactMap(\.avgStrideLength)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }

        let cadOk: Bool?
        if let c1 = avgCad(s1), let c2 = avgCad(s2), c1 > 0 {
            let drop = (c1 - c2) / c1 * 100   // positive = fewer steps in 2nd half
            if drop > 5    { cadOk = false }
            else if drop <= 2 { cadOk = true }
            else           { cadOk = nil }
        } else { cadOk = nil }

        let strideOk: Bool?
        if let sl1 = avgStride(s1), let sl2 = avgStride(s2), sl1 > 0 {
            let drop = (sl1 - sl2) / sl1 * 100
            if drop > 5    { strideOk = false }
            else if drop <= 3 { strideOk = true }
            else           { strideOk = nil }
        } else { strideOk = nil }

        if cadOk == nil && strideOk == nil { return .noData }
        if cadOk == false || strideOk == false { return .collapsed }
        if cadOk == true && (strideOk == true || strideOk == nil) { return .held }
        if strideOk == true && cadOk == nil { return .held }
        return .mid
    }

    private var formHalvesDetail: String? {
        guard let splits = detail?.splits else { return nil }
        let full = splits.filter { $0.distanceM >= 900 }
        guard full.count >= 4 else { return nil }
        let half = full.count / 2
        let s1 = Array(full.prefix(half))
        let s2 = Array(full.suffix(full.count - half))

        func avgCad(_ arr: [SplitData]) -> Double? {
            let v = arr.compactMap(\.avgCadence).map(Double.init)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        func avgStride(_ arr: [SplitData]) -> Double? {
            let v = arr.compactMap(\.avgStrideLength)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }

        var parts: [String] = []
        if let c1 = avgCad(s1), let c2 = avgCad(s2), c1 > 0 {
            let drop = (c1 - c2) / c1 * 100
            let sign = drop >= 0 ? "-" : "+"
            parts.append("케이던스 \(sign)\(String(format: "%.1f", abs(drop)))%")
        }
        if let sl1 = avgStride(s1), let sl2 = avgStride(s2), sl1 > 0 {
            let drop = (sl1 - sl2) / sl1 * 100
            let sign = drop >= 0 ? "-" : "+"
            parts.append("보폭 \(sign)\(String(format: "%.1f", abs(drop)))%")
        }
        guard !parts.isEmpty else { return nil }
        return "전반 → 후반: " + parts.joined(separator: " · ")
    }

    private var limitingFactor: LimitFactor {
        guard let hr = activity.avgHeartRate else { return .noData }
        let maxHR = estimatedMaxHR
        guard maxHR > 0 else { return .noData }
        let pct = Double(hr) / Double(maxHR)
        let isHighHR = pct >= 0.90
        let fe = formEndurance
        if fe == .noData { return .noData }
        let formOk = fe == .held || fe == .mid
        switch (isHighHR, formOk) {
        case (true,  true):  return .cardio
        case (false, false): return .endurance
        case (true,  false): return .balanced
        case (false, true):  return .managed
        }
    }

    private var gctNote: String? {
        guard let gct = detail?.avgGroundContactTime else { return nil }
        let L = AppLanguage.shared
        // 대회에서는 집중 효과로 지면접촉이 짧아지는 경향을 인정 — 절대값 기준 (<230ms = 탄력 있는 구간)
        if gct < 230 {
            return L.s(
                "대회에서는 평소보다 지면접촉이 짧아져요. 집중이 잘 됐다는 신호예요.",
                "Ground contact tends to shorten in races. A sign your focus was dialed in."
            )
        }
        return nil
    }

    private var sameDistanceRaces: [(match: PersistedRaceMatch, activity: Activity)] {
        guard let myRace = confirmedRace else { return [] }
        let myKm = myRace.distanceKm
        // 같은 거리(±15%) 확인된 대회들을 날짜 오름차순
        let sameDistMatches = confirmedRaces
            .filter { $0.isConfirmed && abs($0.distanceKm - myKm) / max(myKm, 1) <= 0.15 }
            .sorted { $0.raceDate < $1.raceDate }
        guard sameDistMatches.count >= 2 else { return [] }
        // history에서 해당 활동 찾기
        let historyByID = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
        return sameDistMatches.compactMap { m -> (match: PersistedRaceMatch, activity: Activity)? in
            guard let act = historyByID[m.activityID] else { return nil }
            return (match: m, activity: act)
        }
    }

    private func distanceDivision(km: Double) -> String {
        if abs(km - 42.195) < 1.0  { return AppLanguage.shared.s("풀코스", "Full") }
        if abs(km - 21.0975) < 0.5 { return AppLanguage.shared.s("하프", "Half") }
        if abs(km - 10) < 0.5      { return "10K" }
        if abs(km - 5) < 0.3       { return "5K" }
        return String(format: "%.0fkm", km)
    }

    // MARK: Distance Collapse

    private struct DCRow {
        let division: String
        let km: Double
        let raceDate: Date
        let form: FormEndurance
        let cadDrop: Double?    // positive = drop %
        let strideDrop: Double? // positive = drop %
        let isCurrent: Bool
    }

    private static func splitFormData(
        _ splits: [SplitData]
    ) -> (form: FormEndurance, cadDrop: Double?, strideDrop: Double?) {
        let full = splits.filter { $0.distanceM >= 900 }
        guard full.count >= 4 else { return (.noData, nil, nil) }
        let half = full.count / 2
        let s1 = Array(full.prefix(half))
        let s2 = Array(full.suffix(full.count - half))

        func avgCad(_ arr: [SplitData]) -> Double? {
            let v = arr.compactMap(\.avgCadence).map(Double.init)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        func avgStride(_ arr: [SplitData]) -> Double? {
            let v = arr.compactMap(\.avgStrideLength)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }

        var cadDrop: Double?    = nil
        var strideDrop: Double? = nil
        let cadOk: Bool?
        if let c1 = avgCad(s1), let c2 = avgCad(s2), c1 > 0 {
            let drop = (c1 - c2) / c1 * 100
            cadDrop = drop
            if drop > 5       { cadOk = false }
            else if drop <= 2 { cadOk = true  }
            else              { cadOk = nil   }
        } else { cadOk = nil }

        let strideOk: Bool?
        if let sl1 = avgStride(s1), let sl2 = avgStride(s2), sl1 > 0 {
            let drop = (sl1 - sl2) / sl1 * 100
            strideDrop = drop
            if drop > 5       { strideOk = false }
            else if drop <= 3 { strideOk = true  }
            else              { strideOk = nil   }
        } else { strideOk = nil }

        if cadOk == nil && strideOk == nil   { return (.noData,    cadDrop, strideDrop) }
        if cadOk == false || strideOk == false { return (.collapsed, cadDrop, strideDrop) }
        if cadOk == true && (strideOk == true || strideOk == nil) { return (.held, cadDrop, strideDrop) }
        if strideOk == true && cadOk == nil  { return (.held,      cadDrop, strideDrop) }
        return (.mid, cadDrop, strideDrop)
    }

    private var distanceCollapseRows: [DCRow] {
        let confirmed = confirmedRaces.filter(\.isConfirmed)
        guard confirmed.count >= 3 else { return [] }
        var divMap: [String: PersistedRaceMatch] = [:]
        for race in confirmed {
            let div = distanceDivision(km: race.distanceKm)
            if let ex = divMap[div] { if race.raceDate > ex.raceDate { divMap[div] = race } }
            else { divMap[div] = race }
        }
        // 열람 중인 대회는 해당 부문의 대표로 항상 우선 사용
        if let myRace = confirmed.first(where: { $0.activityID == activity.id }) {
            divMap[distanceDivision(km: myRace.distanceKm)] = myRace
        }
        guard divMap.count >= 2 else { return [] }
        return divMap.values
            .sorted { $0.distanceKm < $1.distanceKm }
            .map { race -> DCRow in
                let isCurrent = race.activityID == activity.id
                // 현재 활동은 파라미터 detail 사용, 나머지는 클로저로 로드 (ImageRenderer에서도 안전)
                let actDetail = isCurrent ? self.detail : raceDetailFn?(race.activityID)
                let r = actDetail.map { Self.splitFormData($0.splits) }
                return DCRow(
                    division:   distanceDivision(km: race.distanceKm),
                    km:         race.distanceKm,
                    raceDate:   race.raceDate,
                    form:       r?.form      ?? .noData,
                    cadDrop:    r?.cadDrop,
                    strideDrop: r?.strideDrop,
                    isCurrent:  isCurrent
                )
            }
    }

    @ViewBuilder
    private func distanceCollapseSection(_ rows: [DCRow]) -> some View {
        let L = AppLanguage.shared
        let cal = Calendar.current
        VStack(alignment: .leading, spacing: 8) {
            Text(L.s("거리별 폼 유지력 (전체 기록)", "Form by Distance (All Races)"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            // 열 제목
            HStack(spacing: 6) {
                Text(L.s("부문", "Dist."))
                    .frame(width: 44, alignment: .leading)
                Text(L.s("날짜", "Date"))
                    .frame(width: 44, alignment: .leading)
                Text(L.s("케이던스", "Cadence"))
                    .foregroundStyle(Theme.cadence.opacity(0.65))
                    .frame(width: 54, alignment: .leading)
                Text(L.s("보폭", "Stride"))
                    .foregroundStyle(Theme.strideLength.opacity(0.65))
                    .frame(width: 46, alignment: .leading)
                Spacer()
                Text(L.s("상태", "Status"))
            }
            .font(.system(size: 9))
            .foregroundStyle(Color.white.opacity(0.4))
            .padding(.bottom, 1)
            ForEach(rows, id: \.division) { row in
                let comps = cal.dateComponents([.year, .month], from: row.raceDate)
                let dateStr = "\(comps.year ?? 0).\(comps.month ?? 0)"
                HStack(spacing: 6) {
                    Text(row.division)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(row.isCurrent ? Theme.violet : Color.white.opacity(0.85))
                        .frame(width: 44, alignment: .leading)
                    Text(dateStr)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.50))
                        .frame(width: 44, alignment: .leading)
                    if let cd = row.cadDrop, let sd = row.strideDrop {
                        let cadSign = cd >= 0 ? "−" : "+"
                        let strSign = sd >= 0 ? "−" : "+"
                        Text("\(cadSign)\(String(format: "%.1f", abs(cd)))%")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Theme.cadence.opacity(0.80))
                            .frame(width: 54, alignment: .leading)
                        Text("\(strSign)\(String(format: "%.1f", abs(sd)))%")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Theme.strideLength.opacity(0.80))
                            .frame(width: 46, alignment: .leading)
                    } else {
                        Text("–")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color.white.opacity(0.30))
                            .frame(width: 54, alignment: .leading)
                        Text("–")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color.white.opacity(0.30))
                            .frame(width: 46, alignment: .leading)
                    }
                    Spacer()
                    distanceFormBadge(row.form)
                }
            }
            if let note = collapseNarrative(rows) {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func distanceFormBadge(_ form: FormEndurance) -> some View {
        let L = AppLanguage.shared
        let (label, color): (String, Color) = {
            switch form {
            case .held:      return (L.s("유지", "Held"),  IC.green)
            case .mid:       return (L.s("중간", "Mid"),   Color(hex: "F5C542"))
            case .collapsed: return (L.s("붕괴", "Broke"), Color(hex: "FF9A3C"))
            case .noData:    return ("–",                  Color.white.opacity(0.30))
            }
        }()
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func collapseNarrative(_ rows: [DCRow]) -> String? {
        let L = AppLanguage.shared
        let held = rows.filter { $0.form == .held || $0.form == .mid }
        let coll = rows.filter { $0.form == .collapsed }
        guard !held.isEmpty || !coll.isEmpty else { return nil }
        if !held.isEmpty && !coll.isEmpty {
            let hStr = held.map(\.division).joined(separator: "·")
            let cStr = coll.map(\.division).joined(separator: "·")
            let maxHeldKm  = held.map(\.km).max() ?? 0
            let minCollKm  = coll.map(\.km).min() ?? Double.infinity
            if maxHeldKm < minCollKm {
                // 유지 거리가 모두 붕괴 거리보다 짧음 → 명확한 한계선 존재
                return L.s(
                    "\(hStr)에서는 폼이 끝까지 유지됐는데 \(cStr)에서는 무너졌어요. 지금 버틸 수 있는 거리는 그 사이에 있어요.",
                    "Form held in \(hStr) but broke in \(cStr). Your current sustainable distance is somewhere between them."
                )
            } else {
                return L.s(
                    "\(hStr)에서는 폼을 유지했고 \(cStr)에서는 무너졌어요.",
                    "Form held in \(hStr) but broke in \(cStr)."
                )
            }
        }
        if !coll.isEmpty {
            let cStr = coll.map(\.division).joined(separator: "·")
            return L.s(
                "\(cStr)에서 폼이 무너졌어요. 근육 지구력이 이 거리의 한계에 왔어요.",
                "Form broke in \(cStr). Muscular endurance reached its limit at this distance."
            )
        }
        // 전부 유지 — 데이터 미완성 행이 없을 때만 "더 긴 거리" 제안
        let hStr = held.map(\.division).joined(separator: "·")
        let allHaveData = rows.allSatisfy { $0.form != .noData }
        if held.count == 1 {
            return L.s("\(hStr)에서 폼을 유지했어요.", "Form held in \(hStr).")
        } else if allHaveData {
            return L.s(
                "\(hStr) 모두 폼을 유지했어요. 더 긴 거리에도 도전할 준비가 됐어요.",
                "Form held in all of \(hStr). You may be ready to push to a longer distance."
            )
        } else {
            return L.s("\(hStr) 모두 폼을 유지했어요.", "Form held in all of \(hStr).")
        }
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
    var formBaseline: RunningFormBaseline? = nil
    var cadenceSeries: [(offset: TimeInterval, value: Double)] = []
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    var heatModel: MRHeatModel? = nil
    var formShifts: [MRFormShift] = []
    var weatherSnapshot: WeatherSnapshot? = nil
    var confirmedRace: PersistedRaceMatch? = nil
    var confirmedRaces: [PersistedRaceMatch] = []
    var raceDetailFn: ((UUID) -> ActivityDetail?)? = nil
    var hrZonesFn: ((UUID) -> [HRZoneData]?)? = nil
    /// 강도(sRPE) 조회 인덱스 — 퍼포먼스 탭의 7일 강도 부하용.
    var effortIndex: EffortIndex? = nil

    @Query private var allStories: [WorkoutStory]
    @Query private var allShoes: [Shoe]

    private var shoeName: String? {
        let sid = allStories.first(where: { $0.workoutID == activity.id.uuidString })?.shoeID
        guard let sid else { return nil }
        return allShoes.first { $0.id.uuidString == sid }?.displayName
    }

    private var typicalRunDistanceKm: Double? {
        let fourWeeksAgo = Calendar.current.date(byAdding: .day, value: -28, to: activity.date) ?? .distantPast
        let recent = history.filter {
            $0.type == .running && $0.id != activity.id &&
            $0.date >= fourWeeksAgo && $0.date < activity.date
        }
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0.0) { $0 + $1.distance } / Double(recent.count) / 1000.0
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

    private var visibleTabs: [InsightTabKind] {
        let hasForm = detail?.avgCadence != nil
        let isRace  = workoutTypeFn?(activity.id) == .race
        return InsightTabKind.allCases.filter {
            ($0 != .form || hasForm) && ($0 != .race || isRace)
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(visibleTabs, id: \.self) { t in
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
        }
        .background(Theme.cardBackground)
    }

    private var exportWorkoutTypeLabel: String? {
        let wt = workoutTypeFn?(activity.id) ?? detail?.workoutType
        guard let wt else { return nil }
        return wt.koreanLabel
    }

    private var exportHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            MIMOWordmark(size: 9)

            VStack(alignment: .center, spacing: 3) {
                dateTimeText
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let label = exportWorkoutTypeLabel {
                    Text(label)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Theme.violet)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.violet.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

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

    private var dateTimeText: Text {
        let isEn = AppLanguage.shared.isEnglish
        let localeId = isEn ? "en_US" : "ko_KR"
        let loc = Locale(identifier: localeId)
        let fDate = DateFormatter(); fDate.locale = loc
        fDate.dateFormat = isEn ? "MMM d, yyyy " : "yyyy. M. d "
        let fDay  = DateFormatter(); fDay.locale  = loc; fDay.dateFormat = "EEE"
        let fTime = DateFormatter(); fTime.locale = loc
        fTime.dateFormat = isEn ? " h:mm a" : " a h:mm"
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
        switch tab {
        case .rhythm:
            RhythmInsightCard(
                activity: activity, detail: detail,
                history: history, age: age, isMale: isMale,
                hrZones: hrZones, insights: insights,
                cadenceSeries: cadenceSeries,
                hrSamples: hrSamples,
                formBaseline: formBaseline,
                workoutTypeFn: workoutTypeFn
            )
        case .form:
            let exportFormCadence: Int? = {
                guard workoutTypeFn?(activity.id) == .interval,
                      let segs = detail?.intervalSegments else { return detail?.avgCadence }
                let cads = segs.filter { $0.stepLabel == "운동" }.compactMap { $0.avgCadence }
                guard !cads.isEmpty else { return detail?.avgCadence }
                return Int((Double(cads.reduce(0, +)) / Double(cads.count)).rounded())
            }()
            let exportFormHasGap: Bool = {
                let cal = Calendar.current
                guard let threeMonthsAgo = cal.date(byAdding: .month, value: -3, to: activity.date) else { return false }
                let recent = history
                    .filter { $0.type == .running && $0.date >= threeMonthsAgo && $0.date <= activity.date }
                    .sorted { $0.date < $1.date }
                for i in 0..<(recent.count - 1) {
                    let gap = cal.dateComponents([.day], from: recent[i].date, to: recent[i + 1].date).day ?? 0
                    if gap >= 14 { return true }
                }
                return false
            }()
            RunFormCardView(
                activity: activity,
                splits: detail?.splits ?? [],
                avgCadence: exportFormCadence,
                avgStrideLength: detail?.avgStrideLength,
                avgGroundContactTime: detail?.avgGroundContactTime,
                avgVerticalOscillation: detail?.avgVerticalOscillation,
                baseline: formBaseline,
                workoutType: workoutTypeFn?(activity.id) ?? .general,
                intervalSegments: detail?.intervalSegments ?? [],
                hrSamples: hrSamples,
                typicalDistanceKm: typicalRunDistanceKm,
                heatModel: heatModel,
                formShifts: formShifts,
                hasRecentGap: exportFormHasGap,
                weatherSnapshot: weatherSnapshot,
                historicalTemperatures: history.compactMap { $0.temperatureC }
            )
        case .performance:
            PerformanceInsightCard(
                activity: activity, detail: detail,
                history: history, age: age, isMale: isMale,
                insights: insights,
                workoutTypeFn: workoutTypeFn,
                hrZones: hrZones,
                hrZonesFn: hrZonesFn,
                effortIndex: effortIndex
            )
        case .race:
            RaceInsightCard(
                activity: activity, detail: detail,
                age: age, isMale: isMale,
                confirmedRace: confirmedRace,
                confirmedRaces: confirmedRaces,
                history: history,
                raceDetailFn: raceDetailFn
            )
        }
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

        // 1) 카드를 자연 높이로 렌더
        let renderer = ImageRenderer(content:
            exportCardView
                .frame(width: 360)
                .background(Theme.cardBackground)
        )
        renderer.scale = 3
        guard let raw = renderer.uiImage else { isRendering = false; return }

        // 2) 인스타그램 4:5 캔버스 (1080×1350px) 에 맞춤 합성
        //    - 카드가 짧으면 하단을 배경색으로 채움
        //    - 카드가 길면 비율 유지 축소 후 가운데 배치
        let canvas = CGSize(width: 1080, height: 1350)
        let bgColor = UIColor(Theme.cardBackground)

        let scale = min(canvas.width / raw.size.width, canvas.height / raw.size.height)
        let drawW = raw.size.width * scale
        let drawH = raw.size.height * scale
        let drawX = (canvas.width - drawW) / 2
        let drawY: CGFloat = 0  // 상단 정렬

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        exportImage = UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            bgColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))
            raw.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        }
        isRendering = false
    }
}
