import SwiftUI
import UIKit
import CoreLocation

// MARK: - SplitsPalette (dark / light theme for splits card)

private struct SplitsPalette {
    let isLight:         Bool
    let background:      Color
    let textPrimary:     Color
    let accentBar:       Color
    let accentLabel:     Color
    let wordmarkMIMO:    Color
    let wordmarkRunning: Color
    let barTrack:        Color
    let barFillStart:    Color
    let barFillEnd:      Color
    let bestBarStart:    Color
    let bestBarEnd:      Color
    let bestText:        Color
    let dividerStrong:   Color
    let dividerRow:      Color
    let dividerFooter:   Color
    let heartRate:       Color
    let cadence:         Color
    let power:           Color
    let hrZones:         [Color]
    let footerAvgPace:   Color
    let footerBest:      Color
    let footerTotal:     Color
    let dateWeekday:     Color
    let weather:         Color
    let shoe:            Color
    let avgDot:          Color
    let kmLabel:         Color
    let rowAlt:          Color?

    static let dark = SplitsPalette(
        isLight:         false,
        background:      Theme.background,
        textPrimary:     .white,
        accentBar:       Theme.violet,
        accentLabel:     Color(hex: "9B7FF5"),
        wordmarkMIMO:    .white,
        wordmarkRunning: Theme.violet,
        barTrack:        Color.white.opacity(0.09),
        barFillStart:    Color(hex: "9B7DFF"),
        barFillEnd:      Color(hex: "6845E8"),
        bestBarStart:    Color(hex: "FFC74D"),
        bestBarEnd:      Color(hex: "F2A33C"),
        bestText:        Color(hex: "FFC74D"),
        dividerStrong:   Theme.violet.opacity(0.35),
        dividerRow:      Color.white.opacity(0.06),
        dividerFooter:   Color.white.opacity(0.08),
        heartRate:       Theme.heartRate,
        cadence:         Color(hex: "60E8CC"),
        power:           Color(hex: "BEFA6A"),
        hrZones: [
            Color(hex: "4FC3F7"),
            Color(hex: "81C784"),
            Color(hex: "FFB74D"),
            Color(hex: "FF7043"),
            Color(hex: "E53935"),
        ],
        footerAvgPace:   Theme.pace,
        footerBest:      Color(hex: "FFC74D"),
        footerTotal:     Theme.violet,
        dateWeekday:     Theme.time,
        weather:         .white.opacity(0.60),
        shoe:            .white.opacity(0.50),
        avgDot:          Color(hex: "7A7A85"),
        kmLabel:         Color(hex: "6E6E78"),
        rowAlt:          nil
    )

    static let light = SplitsPalette(
        isLight:         true,
        background:      Color(hex: "FFFFFF"),
        textPrimary:     Color(hex: "111111"),
        accentBar:       Color(hex: "5B3FD9"),
        accentLabel:     Color(hex: "5B3FD9"),
        wordmarkMIMO:    Color(hex: "111111"),
        wordmarkRunning: Color(hex: "5B3FD9"),
        barTrack:        Color(hex: "EFEEEA"),
        barFillStart:    Color(hex: "7B5CE8"),
        barFillEnd:      Color(hex: "5B3FD9"),
        bestBarStart:    Color(hex: "F0AA00"),
        bestBarEnd:      Color(hex: "E8A000"),
        bestText:        Color(hex: "C77A00"),
        dividerStrong:   Color.black.opacity(0.10),
        dividerRow:      Color.black.opacity(0.05),
        dividerFooter:   Color.black.opacity(0.10),
        heartRate:       Color(hex: "E0242B"),
        cadence:         Color(hex: "0E7C8A"),
        power:           Color(hex: "1B7F3B"),
        hrZones: [
            Color(hex: "1565C0"),
            Color(hex: "00897B"),
            Color(hex: "C98A00"),
            Color(hex: "D9600A"),
            Color(hex: "E0242B"),
        ],
        footerAvgPace:   Color(hex: "0E7C8A"),
        footerBest:      Color(hex: "C77A00"),
        footerTotal:     Color(hex: "5B3FD9"),
        dateWeekday:     Color(hex: "C77A00"),
        weather:         Color(hex: "7A8794"),
        shoe:            Color(hex: "8A8A8A"),
        avgDot:          Color(hex: "AAAAAA"),
        kmLabel:         Color(hex: "999999"),
        rowAlt:          Color(hex: "FAFAF8")
    )
}

// MARK: - Splits share card (300 × dynamic height, rendered via ImageRenderer)

struct SplitsShareCardView: View {
    let activity: Activity
    let splits: [SplitData]
    var zones: [HRZoneData] = []
    var miniMeImage: UIImage? = nil
    var shoeName: String? = nil
    var weatherText: String? = nil
    var weatherIcon: String? = nil
    var theme: ShareTheme = .dark

    private var pal: SplitsPalette { theme == .light ? .light : .dark }

    // Scale factor 300/360 = 5/6 applied throughout
    // Base 4:5 (300×375), grows dynamically for more splits
    static func cardHeight(splitCount: Int) -> CGFloat {
        max(375, 198 + CGFloat(splitCount) * 18)
    }

    private var fastestIdx: Int? {
        splits.indices.min(by: { splits[$0].paceSecPerKm < splits[$1].paceSecPerKm })
    }

    private var avgPace: Double {
        guard !splits.isEmpty else { return 0 }
        return splits.map(\.paceSecPerKm).reduce(0, +) / Double(splits.count)
    }

    private var bestPace: Double? { splits.map(\.paceSecPerKm).min() }
    private var totalDistanceKm: Double { splits.reduce(0) { $0 + $1.distanceM } / 1000 }

    private var maxPaceSec: Double { splits.map(\.paceSecPerKm).max() ?? 1 }
    private var minPaceSec: Double { splits.map(\.paceSecPerKm).min() ?? 1 }

    private static let barW: CGFloat = 92

    // Slower pace (more sec/km) = longer bar — matches SplitBarRow
    private func barFraction(for pace: Double) -> CGFloat {
        let range = maxPaceSec - minPaceSec
        guard range > 0.5 else { return 0.65 }
        return CGFloat(0.28 + 0.72 * (pace - minPaceSec) / range)
    }

    private func kmLabel(for split: SplitData) -> String {
        if split.distanceM < 990 {
            return String(format: "%.1f", split.distanceM / 1000)
        }
        return split.id == 1 ? "1km" : "\(split.id)"
    }

    private var dateStr: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy. M. d"
        return df.string(from: activity.date)
    }

    private func formatPace(_ secs: Double) -> String {
        let s = Int(secs)
        return String(format: "%d'%02d\"", s / 60, s % 60)
    }

    private func hrZoneNumber(for hr: Int) -> Int? {
        guard !zones.isEmpty else { return nil }
        return zones.first(where: { hr >= $0.minBPM && hr <= $0.maxBPM })?.id
    }

    private func hrZoneColor(_ zone: Int) -> Color {
        guard zone >= 1 && zone <= pal.hrZones.count else { return .secondary }
        return pal.hrZones[zone - 1]
    }

    var body: some View {
        ZStack(alignment: .top) {
            pal.background

            VStack(alignment: .leading, spacing: 0) {
                // Accent bar
                Rectangle()
                    .fill(pal.accentBar)
                    .frame(height: 3)

                VStack(alignment: .leading, spacing: 0) {
                    // Wordmark + MiniMe
                    HStack(alignment: .top) {
                        MIMOWordmark(size: 8)
                        Spacer()
                        miniMeContent
                            .frame(width: 37, height: 37)
                    }
                    .padding(.top, 13)
                    .padding(.bottom, 8)

                    // Date + weather + title
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(dateStr)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(pal.textPrimary)
                        Text(activity.date.weekdayCharKo)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(pal.dateWeekday)
                        if let w = weatherText {
                            HStack(spacing: 3) {
                                Image(systemName: weatherIcon ?? "thermometer.medium")
                                    .font(.system(size: 9))
                                Text(w)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(pal.weather)
                        }
                    }
                    Text(AppLanguage.shared.s("구간 기록", "Splits"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(pal.accentLabel)
                        .padding(.top, 2)

                    // Divider
                    Rectangle()
                        .fill(pal.dividerStrong)
                        .frame(height: 0.5)
                        .padding(.top, 12)
                        .padding(.bottom, 3)

                    // Split rows
                    ForEach(Array(splits.enumerated()), id: \.element.id) { idx, split in
                        splitRow(split: split, idx: idx)
                    }

                    // Stats footer
                    Rectangle()
                        .fill(pal.dividerFooter)
                        .frame(height: 0.5)
                        .padding(.top, 8)
                        .padding(.bottom, 8)

                    HStack(spacing: 0) {
                        footerStat(value: formatPace(avgPace), label: AppLanguage.shared.s("평균 페이스", "AVG PACE"), color: pal.footerAvgPace)
                        Spacer()
                        if let best = bestPace {
                            footerStat(value: formatPace(best), label: AppLanguage.shared.s("최고 구간", "BEST"), color: pal.footerBest)
                            Spacer()
                        }
                        footerStat(value: String(format: "%.1fkm", totalDistanceKm), label: AppLanguage.shared.s("총 거리", "TOTAL"), color: pal.footerTotal)
                    }

                    // Branding
                    HStack(spacing: 5) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 7))
                            .foregroundStyle(pal.accentBar.opacity(0.45))
                        Spacer()
                        if let shoe = shoeName {
                            HStack(spacing: 3) {
                                Image(systemName: "shoe.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(pal.shoe.opacity(0.8))
                                Text(shoe)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(pal.shoe)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 300, height: Self.cardHeight(splitCount: splits.count))
    }

    @ViewBuilder
    private var miniMeContent: some View {
        if let img = miniMeImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 37, height: 37)
                .clipShape(Circle())
                .overlay(Circle().stroke(pal.accentBar.opacity(0.4), lineWidth: 1.2))
        } else {
            MiniMeView(variant: .celebrating, size: 37)
        }
    }

    private func splitRow(split: SplitData, idx: Int) -> some View {
        let isFastest   = idx == fastestIdx
        let isSlowerAvg = split.paceSecPerKm > avgPace
        let avgFrac     = barFraction(for: avgPace)

        let barGradient: LinearGradient = isFastest
            ? LinearGradient(colors: [pal.bestBarStart, pal.bestBarEnd],
                             startPoint: .leading, endPoint: .trailing)
            : LinearGradient(
                colors: [pal.barFillStart.opacity(isSlowerAvg ? 0.75 : 1.0),
                         pal.barFillEnd.opacity(isSlowerAvg ? 0.75 : 1.0)],
                startPoint: .leading, endPoint: .trailing
            )

        return VStack(spacing: 0) {
            if idx > 0 {
                Rectangle()
                    .fill(pal.dividerRow)
                    .frame(height: 0.5)
            }
            HStack(alignment: .center, spacing: 0) {
                // ① km label
                Text(kmLabel(for: split))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(isFastest ? pal.bestText : pal.kmLabel)
                    .frame(width: 23, alignment: .leading)

                // ② bar + avg dotted marker
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(pal.barTrack)
                        .frame(width: Self.barW, height: 5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barGradient)
                        .frame(width: max(8, Self.barW * barFraction(for: split.paceSecPerKm)), height: 5)
                    VStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(pal.avgDot.opacity(0.45))
                                .frame(width: 1.5, height: 2)
                        }
                    }
                    .offset(x: max(0, Self.barW * avgFrac - 0.75))
                }
                .frame(width: Self.barW, height: 13)
                .padding(.horizontal, 4)

                // ③ 페이스 · 심박 · 존 · 케이던스 · 파워
                HStack(spacing: 3) {
                    Text(split.formattedPace)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(isFastest ? pal.bestText : pal.textPrimary)
                    if let hr = split.avgHeartRate {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(pal.heartRate)
                        Text("\(hr)")
                            .font(.system(size: 8, design: .rounded))
                            .foregroundStyle(pal.heartRate)
                        if let zone = hrZoneNumber(for: hr) {
                            Text("Z\(zone)")
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundStyle(hrZoneColor(zone))
                        }
                    }
                    if let cad = split.avgCadence {
                        (Text("\(cad)").font(.system(size: 8, design: .rounded)).foregroundStyle(pal.cadence)
                         + Text("spm").font(.system(size: 7)).foregroundStyle(pal.cadence.opacity(0.85)))
                    }
                    if let pwr = split.avgPower {
                        (Text("\(pwr)").font(.system(size: 8, design: .rounded)).foregroundStyle(pal.power)
                         + Text("W").font(.system(size: 7)).foregroundStyle(pal.power.opacity(0.85)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 1)
            .background(pal.isLight && idx % 2 == 1 ? (pal.rowAlt ?? Color.clear) : Color.clear)
        }
    }

    private func footerStat(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(pal.textPrimary)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(color.opacity(0.7))
        }
    }
}

// MARK: - Share screen (presented as sheet)

struct SplitsShareCardScreen: View {
    let activity: Activity
    let splits: [SplitData]
    var zones: [HRZoneData] = []
    var miniMeImage: UIImage? = nil
    var shoeName: String? = nil
    var weatherText: String? = nil
    var weatherIcon: String? = nil
    var firstCoordinate: CLLocationCoordinate2D? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var previewImage: UIImage?
    @State private var isRendering = false
    @State private var showShareSheet = false
    @State private var resolvedWeatherText: String?
    @State private var resolvedWeatherIcon: String?
    @State private var splitsTheme: ShareTheme = .dark

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 20) {
                        cardPreview
                        themeToggle
                            .padding(.horizontal, 24)
                        shareButton
                            .padding(.horizontal, 24)
                        Spacer(minLength: 32)
                    }
                    .padding(.top, 20)
                }
            }
        }
        .task { await resolveWeatherAndRender() }
        .onChange(of: splitsTheme) {
            Task { await renderCard() }
        }
    }

    private var topBar: some View {
        HStack {
            Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(AppLanguage.shared.s("구간 기록 카드", "Splits Card"))
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Text(AppLanguage.shared.s("닫기", "Close")).foregroundStyle(.clear)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var themeToggle: some View {
        HStack(spacing: 0) {
            themeSegment(label: AppLanguage.shared.s("다크", "Dark"), selected: splitsTheme == .dark) {
                splitsTheme = .dark
            }
            themeSegment(label: AppLanguage.shared.s("라이트", "Light"), selected: splitsTheme == .light) {
                splitsTheme = .light
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func themeSegment(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Theme.violet : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Theme.violet.opacity(0.22) : Color.white.opacity(0.08))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }

    @ViewBuilder
    private var cardPreview: some View {
        if let img = previewImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Theme.violet.opacity(0.25), radius: 24, y: 10)
        } else {
            SplitsShareCardView(activity: activity, splits: splits, zones: zones, miniMeImage: miniMeImage, shoeName: shoeName, weatherText: resolvedWeatherText, weatherIcon: resolvedWeatherIcon, theme: splitsTheme)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Theme.violet.opacity(0.25), radius: 24, y: 10)
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if isRendering {
            ProgressView()
                .tint(Theme.violet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if previewImage != nil {
            Button { showShareSheet = true } label: {
                Label(AppLanguage.shared.s("카드 내보내기", "Export Card"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .sheet(isPresented: $showShareSheet) {
                if let img = previewImage { ShareSheet(images: [img]) }
            }
        }
    }

    @MainActor
    private func resolveWeatherAndRender() async {
        resolvedWeatherText = weatherText
        resolvedWeatherIcon = weatherIcon
        if resolvedWeatherText == nil {
            let cached = await ConditionCache.shared.condition(for: activity.id)
            if let cached, let w = cached.weather {
                resolvedWeatherText = w.formattedTemp
                resolvedWeatherIcon = w.systemIcon
            } else if firstCoordinate != nil {
                let w = await ConditionService.fetchWeather(date: activity.date, coordinate: firstCoordinate)
                if let w {
                    resolvedWeatherText = w.formattedTemp
                    resolvedWeatherIcon = w.systemIcon
                    var cond = cached ?? ActivityCondition()
                    cond.weather = w
                    await ConditionCache.shared.cache(cond, for: activity.id)
                }
            }
        }
        await renderCard()
    }

    @MainActor
    private func renderCard() async {
        isRendering = true
        let card = SplitsShareCardView(activity: activity, splits: splits, zones: zones, miniMeImage: miniMeImage, shoeName: shoeName, weatherText: resolvedWeatherText, weatherIcon: resolvedWeatherIcon, theme: splitsTheme)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        previewImage = renderer.uiImage
        isRendering = false
    }
}

// MARK: - Intervals share card (360 × dynamic height)

struct IntervalsShareCardView: View {
    let activity: Activity
    let segments: [IntervalSegment]
    var miniMeImage: UIImage? = nil
    var weatherText: String? = nil
    var weatherIcon: String? = nil
    var shoeName: String? = nil

    // Base 4:5 (300×375), grows dynamically for more segments
    static func cardHeight(segmentCount: Int) -> CGFloat {
        max(375, 215 + CGFloat(segmentCount) * 20)
    }

    private var hasLabels:   Bool { segments.contains { $0.stepLabel != nil } }
    private var hasHR:       Bool { segments.contains { $0.avgHeartRate != nil } }
    private var hasDist:     Bool { segments.contains { $0.distanceM != nil } }
    private var hasCadence:  Bool { segments.contains { $0.avgCadence != nil } }

    private var workSegments: [IntervalSegment] {
        let labeled = segments.filter { $0.stepLabel == "운동" }
        if !labeled.isEmpty { return labeled }
        let paces = segments.compactMap(\.paceSecPerKm).sorted()
        guard !paces.isEmpty else { return segments }
        let median = paces[paces.count / 2]
        return segments.filter { ($0.paceSecPerKm ?? .greatestFiniteMagnitude) < median }
    }

    private var fastestWorkPace: Double? { workSegments.compactMap(\.paceSecPerKm).min() }
    private var avgWorkPace: Double? {
        let paces = workSegments.compactMap(\.paceSecPerKm)
        guard !paces.isEmpty else { return nil }
        return paces.reduce(0, +) / Double(paces.count)
    }

    private func isWork(_ seg: IntervalSegment) -> Bool {
        if let label = seg.stepLabel { return label == "운동" }
        let paces = segments.compactMap(\.paceSecPerKm).sorted()
        guard !paces.isEmpty, let pace = seg.paceSecPerKm else { return seg.id % 2 == 1 }
        return pace < paces[paces.count / 2]
    }

    private func labelText(_ seg: IntervalSegment) -> String {
        let L = AppLanguage.shared
        switch seg.stepLabel {
        case "준비운동": return L.s("준비운동", "Warmup")
        case "운동":     return L.s("운동",     "Work")
        case "회복":     return L.s("회복",     "Rest")
        case "정리운동": return L.s("정리운동", "Cooldown")
        case let s?:     return s
        default:         return "#\(seg.id)"
        }
    }

    private func formatPace(_ secs: Double) -> String {
        let s = Int(secs); return String(format: "%d'%02d\"", s / 60, s % 60)
    }

    private static let standardDistances = [100, 200, 300, 400, 500, 600, 800, 1000, 1200, 1500, 1600, 2000, 3000, 4000, 5000]

    private func recognizedDistanceM(_ d: Double) -> Int {
        let tolerance = 0.08
        if let snap = Self.standardDistances.first(where: { abs(Double($0) - d) / Double($0) <= tolerance }) { return snap }
        return d >= 200 ? Int((d / 100).rounded()) * 100 : Int((d / 50).rounded()) * 50
    }

    private var workSummaryText: String? {
        let workSegs = workSegments
        guard !workSegs.isEmpty else { return nil }
        let distances = workSegs.compactMap(\.distanceM)
        guard distances.count == workSegs.count else { return nil }
        let snapped = distances.map { recognizedDistanceM($0) }
        let counts = Dictionary(grouping: snapped, by: { $0 }).mapValues(\.count)
        guard let (dist, cnt) = counts.max(by: { $0.value < $1.value }), cnt > 1 || counts.count == 1 else { return nil }
        let label = dist >= 1000
            ? (dist % 1000 == 0 ? "\(dist / 1000)km" : String(format: "%.1fkm", Double(dist) / 1000))
            : "\(dist)m"
        return AppLanguage.shared.s("\(label)×\(cnt)회", "\(label)×\(cnt)")
    }

    private static let gold = Color(hex: "FFC74D")

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Theme.violet).frame(height: 3)

                VStack(alignment: .leading, spacing: 0) {
                    // Wordmark + MiniMe
                    HStack(alignment: .top) {
                        MIMOWordmark(size: 8)
                        Spacer()
                        miniMeContent.frame(width: 37, height: 37)
                    }
                    .padding(.top, 13).padding(.bottom, 8)

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text({
                            let df = DateFormatter(); df.dateFormat = "yyyy. M. d"
                            return df.string(from: activity.date)
                        }())
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        if let w = weatherText {
                            HStack(spacing: 3) {
                                Image(systemName: weatherIcon ?? "thermometer.medium")
                                    .font(.system(size: 8))
                                Text(w)
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundStyle(Color.white.opacity(0.60))
                        }
                    }
                    Text({
                        let base = AppLanguage.shared.s("인터벌 구간", "Interval Reps")
                        if let s = workSummaryText { return "\(base)  (\(s))" }
                        return base
                    }())
                        .font(.system(size: 10, weight: .semibold)).tracking(0.5)
                        .foregroundStyle(Theme.violet).padding(.top, 2)

                    // Column header
                    Rectangle().fill(Theme.violet.opacity(0.35)).frame(height: 0.5)
                        .padding(.top, 12).padding(.bottom, 5)

                    HStack(spacing: 0) {
                        Text(hasLabels ? AppLanguage.shared.s("구간", "Rep") : "#")
                            .frame(width: hasLabels ? 50 : 18, alignment: .leading)
                        if hasDist {
                            Text(AppLanguage.shared.s("거리", "Dist")).frame(width: 47, alignment: .trailing)
                        }
                        Spacer()
                        Text(AppLanguage.shared.s("페이스", "Pace")).frame(width: 52, alignment: .trailing)
                        Text(AppLanguage.shared.s("시간", "Time")).frame(width: 40, alignment: .trailing)
                        if hasHR {
                            Text(AppLanguage.shared.s("심박", "HR")).frame(width: 28, alignment: .trailing)
                        }
                        if hasCadence {
                            Text(AppLanguage.shared.s("케이던스", "Cad.")).frame(width: 30, alignment: .trailing)
                        }
                    }
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.bottom, 3)

                    ForEach(segments) { seg in segmentRow(seg) }

                    // Footer
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                        .padding(.top, 8).padding(.bottom, 8)
                    HStack(spacing: 0) {
                        footerStat("\(workSegments.count)", AppLanguage.shared.s("워크 구간", "WORK REPS"), Theme.violet)
                        Spacer()
                        if let best = fastestWorkPace {
                            footerStat(formatPace(best), AppLanguage.shared.s("최고 구간", "BEST"), Self.gold)
                            Spacer()
                        }
                        if let avg = avgWorkPace {
                            footerStat(formatPace(avg), AppLanguage.shared.s("평균 워크", "AVG WORK"), Theme.pace)
                        }
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "figure.highintensity.intervaltraining")
                            .font(.system(size: 7)).foregroundStyle(Theme.violet.opacity(0.45))
                        Spacer()
                        if let shoe = shoeName {
                            HStack(spacing: 3) {
                                Image(systemName: "shoe.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.white.opacity(0.45))
                                Text(shoe)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 8).padding(.bottom, 2)
                }
                .padding(.horizontal, 18).padding(.bottom, 12)
            }
        }
        .frame(width: 300, height: Self.cardHeight(segmentCount: segments.count))
    }

    @ViewBuilder private var miniMeContent: some View {
        if let img = miniMeImage {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 37, height: 37).clipShape(Circle())
                .overlay(Circle().stroke(Theme.violet.opacity(0.4), lineWidth: 1.2))
        } else {
            MiniMeView(variant: .sprinting, size: 37)
        }
    }

    private func segmentRow(_ seg: IntervalSegment) -> some View {
        let work = isWork(seg)
        let isDim = seg.stepLabel == "준비운동" || seg.stepLabel == "정리운동"
        let paceColor: Color = work ? Theme.violet : Color.white.opacity(0.50)
        let labelW: CGFloat  = hasLabels ? 50 : 18

        return VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            HStack(spacing: 0) {
                if hasLabels {
                    Text(labelText(seg))
                        .font(.system(size: 10, weight: work ? .bold : .regular))
                        .foregroundStyle(work ? Theme.violet : Color.white.opacity(isDim ? 0.30 : 0.45))
                        .frame(width: labelW, alignment: .leading)
                        .lineLimit(1).minimumScaleFactor(0.8)
                } else {
                    Text("\(seg.id)")
                        .font(.system(size: 10, weight: work ? .bold : .regular, design: .rounded))
                        .foregroundStyle(work ? Theme.violet : Color.white.opacity(0.45))
                        .frame(width: labelW, alignment: .leading)
                }
                if hasDist {
                    Text(seg.formattedDistance ?? "—")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Color.white.opacity(isDim ? 0.28 : (work ? 0.90 : 0.55)))
                        .frame(width: 47, alignment: .trailing)
                }
                Spacer()
                Text(seg.formattedPace ?? "—")
                    .font(.system(size: 10, weight: work ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(seg.formattedPace != nil ? paceColor : Color.secondary)
                    .frame(width: 52, alignment: .trailing)
                Text(seg.formattedDuration)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Color.white.opacity(isDim ? 0.28 : (work ? 0.75 : 0.38)))
                    .frame(width: 40, alignment: .trailing)
                if hasHR {
                    Text(seg.avgHeartRate.map { "\($0)" } ?? "—")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(seg.avgHeartRate != nil
                            ? Theme.heartRate.opacity(work ? 1.0 : 0.42)
                            : Color.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
                if hasCadence {
                    Text(seg.avgCadence.map { "\($0)" } ?? "—")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(seg.avgCadence != nil
                            ? Theme.cadence.opacity(work ? 1.0 : 0.42)
                            : Color.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }
            .padding(.vertical, 4)
            .background(work ? Theme.violet.opacity(0.08) : Color.clear)
        }
    }

    private func footerStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(label).font(.system(size: 8, weight: .medium)).tracking(0.3).foregroundStyle(color.opacity(0.7))
        }
    }
}

// MARK: - Intervals share screen

struct IntervalsShareCardScreen: View {
    let activity: Activity
    let segments: [IntervalSegment]
    var miniMeImage: UIImage? = nil
    var weatherText: String? = nil
    var weatherIcon: String? = nil
    var shoeName: String? = nil
    var firstCoordinate: CLLocationCoordinate2D? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var previewImage: UIImage?
    @State private var isRendering = false
    @State private var showShareSheet = false
    @State private var resolvedWeatherText: String?
    @State private var resolvedWeatherIcon: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 28) {
                        cardPreview
                        shareButton.padding(.horizontal, 24)
                        Spacer(minLength: 32)
                    }
                    .padding(.top, 20)
                }
            }
        }
        .task { await resolveWeatherAndRender() }
    }

    private var topBar: some View {
        HStack {
            Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                .font(.body).foregroundStyle(.secondary)
            Spacer()
            Text(AppLanguage.shared.s("인터벌 카드", "Intervals Card"))
                .font(.headline).foregroundStyle(.white)
            Spacer()
            Text(AppLanguage.shared.s("닫기", "Close")).foregroundStyle(.clear)
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 14)
    }

    @ViewBuilder private var cardPreview: some View {
        if let img = previewImage {
            Image(uiImage: img).resizable().scaledToFit()
                .frame(maxWidth: 300)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Theme.violet.opacity(0.25), radius: 24, y: 10)
        } else {
            IntervalsShareCardView(activity: activity, segments: segments, miniMeImage: miniMeImage,
                                   weatherText: resolvedWeatherText, weatherIcon: resolvedWeatherIcon, shoeName: shoeName)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Theme.violet.opacity(0.25), radius: 24, y: 10)
        }
    }

    @ViewBuilder private var shareButton: some View {
        if isRendering {
            ProgressView().tint(Theme.violet).frame(maxWidth: .infinity).padding(.vertical, 16)
        } else if previewImage != nil {
            Button { showShareSheet = true } label: {
                Label(AppLanguage.shared.s("카드 내보내기", "Export Card"), systemImage: "square.and.arrow.up")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Theme.violet).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .sheet(isPresented: $showShareSheet) {
                if let img = previewImage { ShareSheet(images: [img]) }
            }
        }
    }

    @MainActor
    private func resolveWeatherAndRender() async {
        resolvedWeatherText = weatherText
        resolvedWeatherIcon = weatherIcon
        if resolvedWeatherText == nil {
            let cached = await ConditionCache.shared.condition(for: activity.id)
            if let cached, let w = cached.weather {
                resolvedWeatherText = w.formattedTemp
                resolvedWeatherIcon = w.systemIcon
            } else if firstCoordinate != nil {
                let w = await ConditionService.fetchWeather(date: activity.date, coordinate: firstCoordinate)
                if let w {
                    resolvedWeatherText = w.formattedTemp
                    resolvedWeatherIcon = w.systemIcon
                    var cond = cached ?? ActivityCondition()
                    cond.weather = w
                    await ConditionCache.shared.cache(cond, for: activity.id)
                }
            }
        }
        await renderCard()
    }

    @MainActor
    private func renderCard() async {
        isRendering = true
        let card = IntervalsShareCardView(activity: activity, segments: segments, miniMeImage: miniMeImage,
                                          weatherText: resolvedWeatherText, weatherIcon: resolvedWeatherIcon, shoeName: shoeName)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        previewImage = renderer.uiImage
        isRendering = false
    }
}
