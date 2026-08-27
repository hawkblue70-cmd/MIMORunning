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

fileprivate enum CardNumberFont {
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

fileprivate func cardNumFont(_ size: CGFloat) -> Font {
    CardNumberFont.current.swiftUIFont(size)
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

    private let trackMin = 140.0, trackMax = 200.0
    private let recMin   = 160.0, recMax   = 180.0

    // 140→180°(9시), 200→360°(3시). clockwise:false 로 단거리 경로(상단 반원)
    private func ang(_ v: Double) -> Double {
        let c = max(trackMin, min(trackMax, v))
        return 180 + (c - trackMin) / (trackMax - trackMin) * 180
    }

    private var inRec: Bool { Double(cadence) >= recMin && Double(cadence) <= recMax }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Canvas { ctx, size in
                let cx    = size.width / 2
                let thick: CGFloat = 10
                let r     = cx - thick / 2 - 1
                let cy    = size.height - thick / 2 - 1
                let center = CGPoint(x: cx, y: cy)

                // 3구간 고정색 아크 — clockwise:false = 단거리(상단) 경로
                let segs: [(Double, Double, Color)] = [
                    (trackMin, recMin,   Color(hex: "5AC8FA")),  // 140-160 하늘색
                    (recMin,   recMax,   Color(hex: "7FD98A")),  // 160-180 초록(권장)
                    (recMax,   trackMax, Color(hex: "3A7BD5")),  // 180-200 파랑
                ]
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
                let needleColor: Color = inRec ? .white : Color(hex: "F0913C")
                let valRad = ang(Double(cadence)) * .pi / 180
                let needleLen = r
                let tip = CGPoint(x: center.x + needleLen * CGFloat(cos(valRad)),
                                  y: center.y + needleLen * CGFloat(sin(valRad)))
                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: tip)
                ctx.stroke(needle, with: .color(needleColor.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

                // 중심 원
                let dotR: CGFloat = 4
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR,
                                          width: dotR*2, height: dotR*2)),
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
                    Text("140").font(.system(size: 8)).foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    Text("200").font(.system(size: 8)).foregroundStyle(.white.opacity(0.65))
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
    var cadenceSeries: [(offset: TimeInterval, value: Double)] = []
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []

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
                cadenceSeries: cadenceSeries,
                hrSamples: hrSamples
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
                cadenceSeries: cadenceSeries,
                hrSamples: hrSamples
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

    @State private var heroBadge: AchievementBadgeKind? = nil
    @State private var heroBadgeLoaded = false

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
            guard !heroBadgeLoaded else { return }
            heroBadge = computeAchievementBadge(activity: activity, history: history)
            heroBadgeLoaded = true
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
                if let badge = heroBadge {
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
    private var rhythmRow: some View {
        let visibleZones = hrZones.filter { $0.fraction > 0.01 }
        let hasZones = !visibleZones.isEmpty
        let hasHR = hrSamples.count >= 5
        let sep = Color.white.opacity(0.1)

        // 2×2 그리드: [심박존 | 심박수] / [케이던스 | 유산소]
        VStack(spacing: 0) {
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
                // 케이던스 게이지 + 권장 문구
                VStack(alignment: .center, spacing: 4) {
                    if let cad = detail?.avgCadence {
                        CadenceRPMGaugeView(cadence: cad)
                        Color.clear.frame(height: 8)
                        Text(AppLanguage.shared.s("권장 케이던스 160–180", "Rec. Cadence 160–180"))
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .multilineTextAlignment(.center)
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

private struct PerformanceInsightCard: View {
    let activity: Activity
    var detail: ActivityDetail? = nil
    var history: [Activity] = []
    var age: Int? = nil
    var isMale: Bool? = nil
    let insights: [RunInsight]
    var workoutTypeFn: ((UUID) -> WorkoutType?)? = nil
    var isBackfilling: Bool = false

    @State private var heroBadge: AchievementBadgeKind? = nil
    @State private var heroBadgeLoaded = false

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
                    if dist != nil || isBackfilling {
                        Rectangle().fill(.white.opacity(0.08))
                            .frame(width: 0.5)
                            .padding(.vertical, 2)
                        if let d = dist {
                            distribHorizontalSection(items: d.items, weeks: d.weeks)
                                .frame(maxWidth: .infinity)
                        } else {
                            backfillingPlaceholder
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
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
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            guard !heroBadgeLoaded else { return }
            heroBadge = computeAchievementBadge(activity: activity, history: history)
            heroBadgeLoaded = true
        }
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
                    // 3줄: 배지 (없으면 예약 공간)
                    if let badge = heroBadge {
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
        let valid = splits.filter { $0.distanceM >= 900 }
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
                Text(String(format: "%.0fkm", totalKm)).font(.system(size: 6)).foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private struct TrainingDistItem {
        let label: String; let count: Int; let color: Color
    }

    private var trainingDistData: (items: [TrainingDistItem], weeks: Int)? {
        guard let fn = workoutTypeFn else { return nil }

        func evaluate(weeks: Int) -> [TrainingDistItem]? {
            let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: activity.date) ?? .distantPast
            var runs = history.filter { $0.type == .running && $0.date >= cutoff && $0.date <= activity.date }
            if activity.type == .running, !runs.contains(where: { $0.id == activity.id }) {
                runs.append(activity)
            }
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
        case .easy:                        return (L.s("이지런",    "Easy"),    Color(hex: "6B7280"))
        case .general:                     return (L.s("일반 러닝", "General"), Color(hex: "8A8A92"))
        }
    }

    @ViewBuilder
    private func distribHorizontalSection(items: [TrainingDistItem], weeks: Int) -> some View {
        let total = items.map(\.count).reduce(0, +)
        let maxCount = max(1, items.map(\.count).max() ?? 1)
        let L = AppLanguage.shared
        VStack(alignment: .leading, spacing: 5) {
            Text(L.s("훈련 배분 · \(weeks)주", "Training · \(weeks)w"))
                .font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(.white.opacity(0.90))
                .frame(maxWidth: .infinity, alignment: .center)
            ForEach(items, id: \.label) { item in
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(.system(size: 8)).foregroundStyle(IC.label)
                        .frame(width: 38, alignment: .leading)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(item.color.opacity(0.85))
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
            Text(L.s("총 \(total)회", "\(total) runs"))
                .font(.system(size: 8)).foregroundStyle(IC.label)
            if let wt = workoutTypeFn?(activity.id) {
                Text(L.s("오늘의 러닝은 \(wt.koreanLabel)입니다", "Today: \(wt.koreanLabel)"))
                    .font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.80))
            }
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
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []

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
        }
        .background(Theme.cardBackground)
    }

    private var exportHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            MIMOWordmark(size: 9)

            koreanDateTimeText
                .font(.system(size: 11))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
                cadenceSeries: cadenceSeries,
                hrSamples: hrSamples
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
