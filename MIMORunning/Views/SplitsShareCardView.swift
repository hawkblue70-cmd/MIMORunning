import SwiftUI
import UIKit

// MARK: - Splits share card (360 × dynamic height, rendered via ImageRenderer)

struct SplitsShareCardView: View {
    let activity: Activity
    let splits: [SplitData]
    var zones: [HRZoneData] = []
    var miniMeImage: UIImage? = nil

    // Fixed overhead ≈ 238pt + 22pt per row, minimum 520
    static func cardHeight(splitCount: Int) -> CGFloat {
        max(520, 238 + CGFloat(splitCount) * 22)
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

    private var dateStr: String { activity.date.cardShortDateString }

    private func formatPace(_ secs: Double) -> String {
        let s = Int(secs)
        return String(format: "%d'%02d\"", s / 60, s % 60)
    }

    private func hrZoneNumber(for hr: Int) -> Int? {
        guard !zones.isEmpty else { return nil }
        return zones.first(where: { hr >= $0.minBPM && hr <= $0.maxBPM })?.id
    }

    private func hrZoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return Color(hex: "4FC3F7")
        case 2: return Color(hex: "81C784")
        case 3: return Color(hex: "FFB74D")
        case 4: return Color(hex: "FF7043")
        case 5: return Color(hex: "E53935")
        default: return .secondary
        }
    }

    // Shared style constants (mirrors SplitBarRow)
    private static let barW:     CGFloat = 110
    private static let gold      = Color(hex: "FFC74D")
    private static let goldDark  = Color(hex: "F2A33C")
    private static let violetHi  = Color(hex: "9B7DFF")
    private static let violetLo  = Color(hex: "6845E8")
    private static let cadColor  = Color(hex: "60E8CC")
    private static let pwrColor  = Color(hex: "BEFA6A")
    private static let avgDot    = Color(hex: "7A7A85")
    private static let kmColor   = Color(hex: "6E6E78")

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background

            VStack(alignment: .leading, spacing: 0) {
                // Violet accent bar
                Rectangle()
                    .fill(Theme.violet)
                    .frame(height: 3)

                VStack(alignment: .leading, spacing: 0) {
                    // Wordmark + MiniMe
                    HStack(alignment: .top) {
                        HStack(spacing: 0) {
                            Text("MIMO")
                                .font(.system(size: 9, weight: .black))
                                .tracking(2)
                                .foregroundStyle(.white)
                            Text(" RUNNING")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(Theme.violet)
                        }
                        Spacer()
                        miniMeContent
                            .frame(width: 44, height: 44)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                    // Date + title
                    Text(dateStr)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Text(AppLanguage.shared.s("구간 기록", "Splits"))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.violet)
                        .padding(.top, 2)

                    // Divider
                    Rectangle()
                        .fill(Theme.violet.opacity(0.35))
                        .frame(height: 0.5)
                        .padding(.top, 14)
                        .padding(.bottom, 4)

                    // Split rows
                    ForEach(Array(splits.enumerated()), id: \.element.id) { idx, split in
                        splitRow(split: split, idx: idx)
                    }

                    // Stats footer
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.top, 10)
                        .padding(.bottom, 10)

                    HStack(spacing: 0) {
                        footerStat(value: formatPace(avgPace), label: AppLanguage.shared.s("평균 페이스", "AVG PACE"), color: Theme.pace)
                        Spacer()
                        if let best = bestPace {
                            footerStat(value: formatPace(best), label: AppLanguage.shared.s("최고 구간", "BEST"), color: Self.gold)
                            Spacer()
                        }
                        footerStat(value: String(format: "%.1fkm", totalDistanceKm), label: AppLanguage.shared.s("총 거리", "TOTAL"), color: Theme.violet)
                    }

                    // Branding
                    HStack {
                        Spacer()
                        Image(systemName: "figure.run")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.violet.opacity(0.35))
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 360, height: Self.cardHeight(splitCount: splits.count))
    }

    @ViewBuilder
    private var miniMeContent: some View {
        if let img = miniMeImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.violet.opacity(0.4), lineWidth: 1.5))
        } else {
            MiniMeView(variant: .celebrating, size: 44)
        }
    }

    private func splitRow(split: SplitData, idx: Int) -> some View {
        let isFastest  = idx == fastestIdx
        let isSlowerAvg = split.paceSecPerKm > avgPace
        let avgFrac    = barFraction(for: avgPace)

        let barGradient: LinearGradient = isFastest
            ? LinearGradient(colors: [Self.gold, Self.goldDark],
                             startPoint: .leading, endPoint: .trailing)
            : LinearGradient(
                colors: [Self.violetHi.opacity(isSlowerAvg ? 0.75 : 1.0),
                         Self.violetLo.opacity(isSlowerAvg ? 0.75 : 1.0)],
                startPoint: .leading, endPoint: .trailing
            )

        return VStack(spacing: 0) {
            if idx > 0 {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
            }
            HStack(alignment: .center, spacing: 0) {
                // ① km label
                Text(kmLabel(for: split))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isFastest ? Self.gold : Self.kmColor)
                    .frame(width: 28, alignment: .leading)

                // ② bar + avg dotted marker
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.09))
                        .frame(width: Self.barW, height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barGradient)
                        .frame(width: max(10, Self.barW * barFraction(for: split.paceSecPerKm)), height: 6)
                    VStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(Self.avgDot.opacity(0.45))
                                .frame(width: 1.5, height: 2.5)
                        }
                    }
                    .offset(x: max(0, Self.barW * avgFrac - 0.75))
                }
                .frame(width: Self.barW, height: 16)
                .padding(.horizontal, 5)

                // ③ 페이스 · 심박 · 존 · 케이던스 · 파워
                HStack(spacing: 4) {
                    Text(split.formattedPace)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isFastest ? Self.gold : .white)
                    if let hr = split.avgHeartRate {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Theme.heartRate)
                        Text("\(hr)")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Theme.heartRate)
                        if let zone = hrZoneNumber(for: hr) {
                            Text("Z\(zone)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(hrZoneColor(zone))
                        }
                    }
                    if let cad = split.avgCadence {
                        (Text("\(cad)").font(.system(size: 10, design: .rounded)).foregroundStyle(Self.cadColor)
                         + Text("spm").font(.system(size: 9)).foregroundStyle(Self.cadColor.opacity(0.85)))
                    }
                    if let pwr = split.avgPower {
                        (Text("\(pwr)").font(.system(size: 10, design: .rounded)).foregroundStyle(Self.pwrColor)
                         + Text("W").font(.system(size: 9)).foregroundStyle(Self.pwrColor.opacity(0.85)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 1)
        }
    }

    private func footerStat(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9, weight: .medium))
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

    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?
    @State private var previewImage: UIImage?
    @State private var isRendering = false

    private var shareFilename: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        return "mimo_splits_\(fmt.string(from: activity.date)).png"
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 28) {
                        cardPreview
                        shareButton
                            .padding(.horizontal, 24)
                        Spacer(minLength: 32)
                    }
                    .padding(.top, 20)
                }
            }
        }
        .task { await renderCard() }
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
            let scale: CGFloat = 300.0 / 360.0
            SplitsShareCardView(activity: activity, splits: splits, zones: zones, miniMeImage: miniMeImage)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .scaleEffect(scale)
                .frame(width: 300, height: scale * SplitsShareCardView.cardHeight(splitCount: splits.count))
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if isRendering {
            ProgressView()
                .tint(Theme.violet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if let url = shareURL {
            ShareLink(item: url, preview: SharePreview(AppLanguage.shared.s("구간 기록", "Splits"))) {
                Label(AppLanguage.shared.s("공유하기", "Share"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @MainActor
    private func renderCard() async {
        isRendering = true
        let card = SplitsShareCardView(activity: activity, splits: splits, zones: zones, miniMeImage: miniMeImage)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let img = renderer.uiImage, let data = img.pngData() else {
            isRendering = false
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(shareFilename)
        try? data.write(to: url)
        previewImage = img
        shareURL = url
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

    static func cardHeight(segmentCount: Int) -> CGFloat {
        max(520, 258 + CGFloat(segmentCount) * 24)
    }

    private var hasLabels: Bool { segments.contains { $0.stepLabel != nil } }
    private var hasHR: Bool     { segments.contains { $0.avgHeartRate != nil } }
    private var hasDist: Bool   { segments.contains { $0.distanceM != nil } }

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
                        HStack(spacing: 0) {
                            Text("MIMO")
                                .font(.system(size: 9, weight: .black)).tracking(2).foregroundStyle(.white)
                            Text(" RUNNING")
                                .font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(Theme.violet)
                        }
                        Spacer()
                        miniMeContent.frame(width: 44, height: 44)
                    }
                    .padding(.top, 16).padding(.bottom, 10)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(activity.date.cardShortDateString)
                            .font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                        if let w = weatherText {
                            HStack(spacing: 3) {
                                Image(systemName: weatherIcon ?? "thermometer.medium")
                                    .font(.system(size: 14))
                                Text(w)
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundStyle(Color.white.opacity(0.60))
                        }
                    }
                    Text({
                        let base = AppLanguage.shared.s("인터벌 구간", "Interval Reps")
                        if let s = workSummaryText { return "\(base)  (\(s))" }
                        return base
                    }())
                        .font(.system(size: 12, weight: .semibold)).tracking(0.5)
                        .foregroundStyle(Theme.violet).padding(.top, 2)

                    // Column header
                    Rectangle().fill(Theme.violet.opacity(0.35)).frame(height: 0.5)
                        .padding(.top, 14).padding(.bottom, 6)

                    HStack(spacing: 0) {
                        Text(hasLabels ? AppLanguage.shared.s("구간", "Rep") : "#")
                            .frame(width: hasLabels ? 60 : 22, alignment: .leading)
                        if hasDist {
                            Text(AppLanguage.shared.s("거리", "Dist")).frame(width: 56, alignment: .trailing)
                        }
                        Spacer()
                        Text(AppLanguage.shared.s("페이스", "Pace")).frame(width: 62, alignment: .trailing)
                        Text(AppLanguage.shared.s("시간", "Time")).frame(width: 48, alignment: .trailing)
                        if hasHR {
                            Text(AppLanguage.shared.s("심박", "HR")).frame(width: 38, alignment: .trailing)
                        }
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .padding(.bottom, 4)

                    ForEach(segments) { seg in segmentRow(seg) }

                    // Footer
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                        .padding(.top, 10).padding(.bottom, 10)
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

                    HStack {
                        Spacer()
                        Image(systemName: "figure.highintensity.intervaltraining")
                            .font(.system(size: 8)).foregroundStyle(Theme.violet.opacity(0.35))
                    }
                    .padding(.top, 10).padding(.bottom, 2)
                }
                .padding(.horizontal, 22).padding(.bottom, 14)
            }
        }
        .frame(width: 360, height: Self.cardHeight(segmentCount: segments.count))
    }

    @ViewBuilder private var miniMeContent: some View {
        if let img = miniMeImage {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 44, height: 44).clipShape(Circle())
                .overlay(Circle().stroke(Theme.violet.opacity(0.4), lineWidth: 1.5))
        } else {
            MiniMeView(variant: .sprinting, size: 44)
        }
    }

    private func segmentRow(_ seg: IntervalSegment) -> some View {
        let work = isWork(seg)
        let isDim = seg.stepLabel == "준비운동" || seg.stepLabel == "정리운동"
        let paceColor: Color = work ? Theme.violet : Color.white.opacity(0.50)
        let labelW: CGFloat  = hasLabels ? 60 : 22

        return VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            HStack(spacing: 0) {
                if hasLabels {
                    Text(labelText(seg))
                        .font(.system(size: 11, weight: work ? .bold : .regular))
                        .foregroundStyle(work ? Theme.violet : Color.white.opacity(isDim ? 0.30 : 0.45))
                        .frame(width: labelW, alignment: .leading)
                        .lineLimit(1).minimumScaleFactor(0.8)
                } else {
                    Text("\(seg.id)")
                        .font(.system(size: 11, weight: work ? .bold : .regular, design: .rounded))
                        .foregroundStyle(work ? Theme.violet : Color.white.opacity(0.30))
                        .frame(width: labelW, alignment: .leading)
                }
                if hasDist {
                    Text(seg.formattedDistance ?? "—")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.white.opacity(isDim ? 0.28 : (work ? 0.90 : 0.55)))
                        .frame(width: 56, alignment: .trailing)
                }
                Spacer()
                Text(seg.formattedPace ?? "—")
                    .font(.system(size: 12, weight: work ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(seg.formattedPace != nil ? paceColor : Color.secondary)
                    .frame(width: 62, alignment: .trailing)
                Text(seg.formattedDuration)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color.white.opacity(isDim ? 0.28 : (work ? 0.75 : 0.38)))
                    .frame(width: 48, alignment: .trailing)
                if hasHR {
                    Text(seg.avgHeartRate.map { "\($0)" } ?? "—")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(seg.avgHeartRate != nil
                            ? Theme.heartRate.opacity(work ? 1.0 : 0.42)
                            : Color.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
            .padding(.vertical, 5)
            .background(work ? Theme.violet.opacity(0.08) : Color.clear)
        }
    }

    private func footerStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(label).font(.system(size: 9, weight: .medium)).tracking(0.3).foregroundStyle(color.opacity(0.7))
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

    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?
    @State private var previewImage: UIImage?
    @State private var isRendering = false

    private var shareFilename: String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd"
        return "mimo_intervals_\(fmt.string(from: activity.date)).png"
    }

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
        .task { await renderCard() }
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
            let scale: CGFloat = 300.0 / 360.0
            IntervalsShareCardView(activity: activity, segments: segments, miniMeImage: miniMeImage,
                                   weatherText: weatherText, weatherIcon: weatherIcon)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .scaleEffect(scale)
                .frame(width: 300, height: scale * IntervalsShareCardView.cardHeight(segmentCount: segments.count))
        }
    }

    @ViewBuilder private var shareButton: some View {
        if isRendering {
            ProgressView().tint(Theme.violet).frame(maxWidth: .infinity).padding(.vertical, 16)
        } else if let url = shareURL {
            ShareLink(item: url, preview: SharePreview(AppLanguage.shared.s("인터벌 구간", "Interval Reps"))) {
                Label(AppLanguage.shared.s("공유하기", "Share"), systemImage: "square.and.arrow.up")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Theme.violet).clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @MainActor
    private func renderCard() async {
        isRendering = true
        let card = IntervalsShareCardView(activity: activity, segments: segments, miniMeImage: miniMeImage,
                                          weatherText: weatherText, weatherIcon: weatherIcon)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let img = renderer.uiImage, let data = img.pngData() else { isRendering = false; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(shareFilename)
        try? data.write(to: url)
        previewImage = img
        shareURL = url
        isRendering = false
    }
}
