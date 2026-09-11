import SwiftUI
import Charts
import CoreLocation
import MapKit
import SwiftData

// MARK: - Detail Panel Share Card

/// 경로 카드 팔레트 — 다크/라이트 두 벌.
/// 색은 여기서만 고르고, 레이아웃 코드는 하나를 공유한다.
struct RouteCardPalette {
    let background: LinearGradient
    let textPrimary: Color
    let textSecondary: Color
    let cellBackground: Color
    let divider: Color
    let wordmarkStroke: Bool

    static let dark = RouteCardPalette(
        background: LinearGradient(colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
        textPrimary: .white,
        textSecondary: .white.opacity(0.60),
        cellBackground: Theme.cardBackground,
        divider: Theme.violet.opacity(0.30),
        wordmarkStroke: false
    )

    static let light = RouteCardPalette(
        background: LinearGradient(colors: [Color(hex: "FFFFFF"), Color(hex: "F2F0F7")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
        textPrimary: Color(hex: "111111"),
        textSecondary: Color(hex: "5A5A66"),
        cellBackground: Color(hex: "FFFFFF"),
        divider: Color(hex: "5B3FD9").opacity(0.30),
        wordmarkStroke: true
    )
}

struct DetailPanelShareCard: View {
    let activity: Activity
    let detail: ActivityDetail?
    let activePanel: DetailPanel
    let hrSamples: [(offset: TimeInterval, bpm: Int)]
    let panelSeriesData: [(offset: TimeInterval, value: Double)]
    var mapSnapshot: UIImage? = nil
    var dateText: String = ""
    var condition: ActivityCondition? = nil
    var theme: ShareTheme = .dark

    private var pal: RouteCardPalette { theme == .light ? .light : .dark }

    static let cardWidth:  CGFloat = 300
    static let cardHeight: CGFloat = 375

    var body: some View {
        ZStack {
            pal.background
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.horizontal, 41).padding(.top, 20)
                panelTitleRow
                    .padding(.horizontal, 41).padding(.top, 5)
                chartArea
                    .frame(height: chartInnerHeight)
                    .frame(maxWidth: .infinity, minHeight: chartAreaHeight, maxHeight: chartAreaHeight, alignment: .center)
                    .padding(.horizontal, 41).padding(.top, 4)
                Rectangle()
                    .fill(pal.divider)
                    .frame(height: 0.5)
                    .padding(.horizontal, 41).padding(.top, 4)
                metricsGrid
                    .padding(.horizontal, 41).padding(.top, 4)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Header

    private var headerDateStr: String {
        let isEn = AppLanguage.shared.isEnglish
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: isEn ? "en_US" : "ko_KR")
        fmt.dateFormat = isEn ? "MMM d, yyyy" : "yyyy. M.d"
        return fmt.string(from: activity.date)
    }

    private var headerTimeStr: String {
        let isEn = AppLanguage.shared.isEnglish
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: isEn ? "en_US" : "ko_KR")
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return fmt.string(from: activity.date)
    }

    private var weekdayChar: String {
        let weekday = Calendar.current.component(.weekday, from: activity.date)
        if AppLanguage.shared.isEnglish {
            return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][(weekday - 1) % 7]
        }
        return ["일", "월", "화", "수", "목", "금", "토"][(weekday - 1) % 7]
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            MIMOWordmark(size: 9, strokeMIMO: pal.wordmarkStroke)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    Text(headerDateStr)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(pal.textPrimary)
                    Text(weekdayChar)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.time)
                    Text(headerTimeStr)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(pal.textPrimary)
                }
                // 날씨는 날짜 아래 같은 크기로 — 제목 줄에 섞이면 패널 이름과 경쟁한다
                if let weather = condition?.weather {
                    HStack(spacing: 3) {
                        Image(systemName: weather.systemIcon)
                            .font(.system(size: 9, weight: .medium))
                        Text(activity.temperatureC.map { String(format: "%.0f°C", $0) } ?? weather.formattedTemp)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(pal.textSecondary)
                }
            }
        }
    }

    private var panelTitleRow: some View {
        HStack(spacing: 4) {
            Image(systemName: activePanel.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accentColor)
            Text(activePanel.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(pal.textPrimary.opacity(0.80))
            Spacer()
        }
    }

    // MARK: Chart

    @ViewBuilder
    private var chartArea: some View {
        Group {
            switch activePanel {
            case .map:
                if let snapshot = mapSnapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else if let coords = detail?.routeCoordinates, !coords.isEmpty {
                    RouteLineArt(coordinates: coords, lineColor: Theme.violet, lineWidth: 1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { placeholder("map.fill") }

            case .heartRate:
                if !hrSamples.isEmpty {
                    HRSeriesPanelChart(samples: hrSamples, zones: detail?.hrZones ?? [], compact: true)
                } else { placeholder("heart.fill") }

            case .elevation:
                if let profile = detail?.altitudeProfile, !profile.isEmpty {
                    ElevationPanelChart(profile: profile, compact: true)
                } else { placeholder("mountain.2.fill") }

            case .combined:
                placeholder("chart.xyaxis.line")

            case .cadence, .power, .groundContact, .strideLength, .verticalOscillation:
                if !panelSeriesData.isEmpty {
                    MetricBarPanelChart(
                        samples: panelSeriesData,
                        color: accentColor,
                        unit: seriesUnit,
                        format: seriesFormat,
                        useRangeBar: seriesUseRangeBar,
                        validMin: activePanel == .cadence ? 130 : 0,
                        barWidthOverride: 2,
                        compact: true
                    )
                } else { placeholder(activePanel.icon) }
            }
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func placeholder(_ icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var chartAreaHeight: CGFloat { 176 }

    var effectiveCardHeight: CGFloat { Self.cardHeight }

    // 비율 유지: 가로 272×0.8=218, 세로 150×0.8=120 → 주변 여백 가로 27pt씩, 세로 15pt씩
    private var chartInnerWidth: CGFloat { 218 }

    private var chartInnerHeight: CGFloat { 168 }

    private var accentColor: Color {
        switch activePanel {
        case .heartRate:                                   return Theme.heartRate
        case .cadence:                                     return Theme.cadence
        case .power:                                       return Theme.power
        case .elevation:                                   return Theme.elevation
        case .groundContact, .strideLength,
             .verticalOscillation:                         return Theme.runningForm
        default:                                           return Theme.violet
        }
    }

    private var seriesUnit: String {
        switch activePanel {
        case .cadence:             return "spm"
        case .power:               return "W"
        case .groundContact:       return "ms"
        case .strideLength:        return "m"
        case .verticalOscillation: return "cm"
        default:                   return ""
        }
    }

    private var seriesFormat: String {
        switch activePanel {
        case .strideLength:        return "%.2f"
        case .verticalOscillation: return "%.1f"
        default:                   return "%.0f"
        }
    }

    private var seriesUseRangeBar: Bool {
        switch activePanel {
        case .power, .groundContact, .strideLength, .verticalOscillation: return true
        default: return false
        }
    }

    // MARK: Metrics grid

    private struct MetricItem {
        let icon: String
        let label: String
        let value: String
        let color: Color
        var valueFontSize: CGFloat = 8.5  // 지도를 키우려고 지표를 30% 줄였다
    }

    private var availableMetrics: [MetricItem] {
        let L = AppLanguage.shared
        var items: [MetricItem] = []

        // 거리는 지표 의미색이 없다 — 배경에 따라 읽히는 색으로 (라이트에서 흰색은 안 보인다)
        items.append(.init(icon: "ruler",               label: L.s("거리", "Dist."),           value: activity.formattedDistance,                      color: pal.textPrimary))
        items.append(.init(icon: "clock",               label: L.s("시간", "Time"),            value: activity.formattedDuration,                      color: Theme.time))
        if let pace = activity.formattedPace {
            items.append(.init(icon: "timer",           label: L.s("페이스", "Pace"),          value: pace,                                            color: Theme.pace))
        }
        if let hr = activity.avgHeartRate {
            items.append(.init(icon: "heart.fill",      label: L.s("평균 심박", "Avg HR"),     value: "\(hr) bpm",                                     color: Theme.heartRate))
        }
        if let cad = detail?.avgCadence {
            items.append(.init(icon: "figure.run",      label: L.s("케이던스", "Cadence"),     value: "\(cad) spm",                                    color: Theme.cadence))
        }
        if let pwr = detail?.avgPower {
            items.append(.init(icon: "bolt.fill",       label: L.s("파워", "Power"),           value: "\(pwr) W",                                      color: Theme.power))
        }
        if let gct = detail?.avgGroundContactTime {
            items.append(.init(icon: "stopwatch",       label: L.s("지면 접촉", "Gnd Contact"),value: "\(Int(gct.rounded())) ms",                      color: Theme.runningForm))
        }
        if let sl = detail?.avgStrideLength {
            items.append(.init(icon: "arrow.left.and.right", label: L.s("보폭", "Stride"),    value: String(format: "%.2f m", sl),                    color: Theme.runningForm))
        }
        if let vo = detail?.avgVerticalOscillation {
            items.append(.init(icon: "arrow.up.and.down", label: L.s("수직 진폭", "Vert. Osc."), value: String(format: "%.1f cm", vo),                color: Theme.runningForm))
        }
        if let vo2 = detail?.vo2Max {
            items.append(.init(icon: "lungs.fill",      label: L.s("유산소", "Cardio"),               value: String(format: "%.1f mL/kg·m", vo2),   color: Theme.elevation, valueFontSize: 10.5))
        }
        if let cal = activity.calories {
            items.append(.init(icon: "flame.fill",      label: L.s("칼로리", "Cals"),          value: String(format: "%.0f kcal", cal),                color: Theme.calories))
        }
        if let elev = detail?.elevationGain {
            items.append(.init(icon: "arrow.up.right",  label: L.s("고도 획득", "Elev. Gain"), value: String(format: "%.0f m", elev),                  color: Theme.elevation))
        }
        return Array(items.prefix(12))
    }

    private var metricsGrid: some View {
        let items = availableMetrics
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3),
                      GridItem(.flexible())],
            spacing: 3
        ) {
            ForEach(0..<items.count, id: \.self) { i in
                metricCell(items[i])
            }
        }
    }

    private func metricCell(_ item: MetricItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                Image(systemName: item.icon)
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundStyle(item.color)
                Text(item.label)
                    .font(.system(size: 6, weight: .medium))
                    .foregroundStyle(item.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(item.value)
                .font(.system(size: item.valueFontSize, weight: .black))
                .fontWidth(.condensed)
                .foregroundStyle(pal.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(pal.cellBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

}

// MARK: - Detail Panel Share Card Screen

struct DetailPanelShareCardScreen: View {
    let activity: Activity
    let detail: ActivityDetail?
    let activePanel: DetailPanel
    let hrSamples: [(offset: TimeInterval, bpm: Int)]
    let panelSeriesData: [(offset: TimeInterval, value: Double)]
    var condition: ActivityCondition? = nil

    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @State private var showShareSheet = false
    @State private var mapSnapshot: UIImage?
    /// 경로선을 심박 존 색으로 — 심박 기록이 있을 때만 의미가 있다
    @State private var useHRZoneColors = true
    @State private var cardTheme: ShareTheme = .dark
    @Environment(\.dismiss) private var dismiss

    private let cardW = DetailPanelShareCard.cardWidth
    private var cardH: CGFloat { DetailPanelShareCard.cardHeight }

    private var formattedDateText: String {
        let isEn = AppLanguage.shared.isEnglish
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: isEn ? "en_US" : "ko_KR")
        dateFmt.dateFormat = isEn ? "MMM d, yyyy" : "yyyy. M.d"
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: isEn ? "en_US" : "ko_KR")
        timeFmt.dateStyle = .none
        timeFmt.timeStyle = .short
        return "\(dateFmt.string(from: activity.date))  \(timeFmt.string(from: activity.date))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer()
                    DetailPanelShareCard(
                        activity: activity, detail: detail,
                        activePanel: activePanel,
                        hrSamples: hrSamples, panelSeriesData: panelSeriesData,
                        mapSnapshot: mapSnapshot,
                        dateText: formattedDateText,
                        condition: condition,
                        theme: cardTheme
                    )
                    .frame(width: cardW, height: cardH)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Theme.violet.opacity(0.30), radius: 28, y: 10)

                    Spacer(minLength: 16)

                    optionRow
                        .padding(.horizontal, 24)
                        .padding(.bottom, 14)

                    shareCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }
            }
            .navigationTitle(AppLanguage.shared.s("경로 내보내기 카드", "Route Card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Theme.violet)
                }
            }
        }
        .task { await renderCard() }
    }

    /// 카드 옵션 — 경로 색(심박 존/단색)과 카드 테마(다크/라이트)
    @ViewBuilder
    private var optionRow: some View {
        VStack(spacing: 8) {
            if hrSamples.count >= 10 {
                segmented(left: AppLanguage.shared.s("심박 존 색", "HR Zones"), leftOn: useHRZoneColors,
                          right: AppLanguage.shared.s("단색", "Solid"), rightOn: !useHRZoneColors) { wantsHR in
                    guard useHRZoneColors != wantsHR else { return }
                    useHRZoneColors = wantsHR
                    mapSnapshot = nil            // 색이 바뀌면 지도를 다시 그린다
                    Task { await renderCard() }
                }
            }
            segmented(left: AppLanguage.shared.s("다크", "Dark"), leftOn: cardTheme == .dark,
                      right: AppLanguage.shared.s("라이트", "Light"), rightOn: cardTheme == .light) { wantsDark in
                let next: ShareTheme = wantsDark ? .dark : .light
                guard cardTheme != next else { return }
                cardTheme = next
                Task { await renderCard() }
            }
        }
    }

    private func segmented(left: String, leftOn: Bool, right: String, rightOn: Bool,
                           onSelect: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 0) {
            segment(left, selected: leftOn) { onSelect(true) }
            segment(right, selected: rightOn) { onSelect(false) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func segment(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
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
    private var shareCTA: some View {
        if isRendering {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.violet)
                Text(AppLanguage.shared.s("카드 만드는 중...", "Creating card..."))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
        } else if previewImage != nil {
            Button { showShareSheet = true } label: {
                Label(AppLanguage.shared.s("카드 내보내기", "Export Card"), systemImage: "square.and.arrow.up")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .sheet(isPresented: $showShareSheet) {
                if let img = previewImage { ShareSheet(images: [img]) }
            }
        } else {
            Text(AppLanguage.shared.s("카드 생성에 실패했어요", "Card creation failed"))
                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 18)
        }
    }

    @MainActor
    private func renderCard() async {
        isRendering = true
        if activePanel == .map {
            // 카드용 지도는 화면(398×220)과 크기가 달라 캐시를 공유하지 않는다 — 카드 전용 캐시.
            if let cached = loadCachedMapSnapshot() {
                mapSnapshot = cached
            } else {
                mapSnapshot = await makeMapSnapshot()
                if let img = mapSnapshot { saveMapSnapshotToCache(img) }
            }
        }
        let renderer = ImageRenderer(content:
            DetailPanelShareCard(
                activity: activity, detail: detail,
                activePanel: activePanel,
                hrSamples: hrSamples, panelSeriesData: panelSeriesData,
                mapSnapshot: mapSnapshot,
                dateText: formattedDateText,
                condition: condition,
                theme: cardTheme
            )
            .frame(width: cardW, height: cardH)
        )
        renderer.scale = 3
        previewImage = renderer.uiImage
        isRendering = false
    }

    // MARK: Map snapshot helpers

    /// 카드 전용 지도 캐시 — 화면 지도(398×220)와 크기가 달라 따로 둔다.
    /// 마커 모양이 바뀌면 v를 올려 옛 스냅샷이 남지 않게 한다.
    private var cardMapCacheURL: URL {
        // 단색/심박존은 다른 그림이라 따로 캐시한다
        let variant = useHRZoneColors ? "hr" : "plain"
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_map_card_v3_\(variant)_\(activity.id.uuidString).jpg")
    }

    private func loadCachedMapSnapshot() -> UIImage? {
        guard let data = try? Data(contentsOf: cardMapCacheURL) else { return nil }
        return UIImage(data: data)
    }

    private func saveMapSnapshotToCache(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        try? data.write(to: cardMapCacheURL)
    }

    /// 경로 지도 — 심박이 있으면 존 색 그라데이션, 없으면 단색.
    /// 그리기는 활동 상세 지도와 같은 구현(RouteSnapshotRenderer)을 쓴다.
    private func makeMapSnapshot() async -> UIImage? {
        guard let coords = detail?.routeCoordinates, !coords.isEmpty else { return nil }
        let valid = RouteSnapshotRenderer.validCoordinates(coords)
        guard valid.count > 1,
              let opts = RouteSnapshotRenderer.options(coordinates: valid,
                                                       size: CGSize(width: 218, height: 168),
                                                       scale: 3),
              let snap = try? await MKMapSnapshotter(options: opts).start() else { return nil }

        let colors = useHRZoneColors ? await zoneColors(for: valid) : nil
        return RouteSnapshotRenderer.draw(on: snap, coordinates: valid, segmentColors: colors)
    }

    /// 좌표별 심박 존 색. 존 경계가 없으면 최고 심박에서 추정한다(상세 지도와 같은 폴백).
    private func zoneColors(for coords: [CLLocationCoordinate2D]) async -> [UIColor]? {
        guard hrSamples.count >= 10 else { return nil }
        let zones = detail?.hrZones ?? []
        let bounds: [(id: Int, minBPM: Int)] = zones.isEmpty
            ? {
                let peak = min(220, Int(Double(hrSamples.map(\.bpm).max() ?? 180) / 0.90))
                return [(1, 0), (2, Int(Double(peak) * 0.60)), (3, Int(Double(peak) * 0.70)),
                        (4, Int(Double(peak) * 0.80)), (5, Int(Double(peak) * 0.90))]
              }()
            : zones.sorted { $0.minBPM < $1.minBPM }.map { (id: $0.id, minBPM: $0.minBPM) }
        return RouteSnapshotRenderer.zoneColors(
            coordinates: coords,
            routeTimeOffsets: detail?.routeTimeOffsets ?? [],
            workoutDuration: activity.duration,
            hrSamples: hrSamples,
            zoneBounds: bounds)
    }
}

