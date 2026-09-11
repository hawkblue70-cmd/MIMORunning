import SwiftUI
import Charts
import CoreLocation
import MapKit
import SwiftData

// MARK: - Detail Panel Share Card

struct DetailPanelShareCard: View {
    let activity: Activity
    let detail: ActivityDetail?
    let activePanel: DetailPanel
    let hrSamples: [(offset: TimeInterval, bpm: Int)]
    let panelSeriesData: [(offset: TimeInterval, value: Double)]
    var mapSnapshot: UIImage? = nil
    var dateText: String = ""
    var condition: ActivityCondition? = nil

    static let cardWidth:  CGFloat = 300
    static let cardHeight: CGFloat = 375

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
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
                    .fill(Theme.violet.opacity(0.30))
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
            MIMOWordmark(size: 9)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    Text(headerDateStr)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                    Text(weekdayChar)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.time)
                    Text(headerTimeStr)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                }
                // 날씨는 날짜 아래 같은 크기로 — 제목 줄에 섞이면 패널 이름과 경쟁한다
                if let weather = condition?.weather {
                    HStack(spacing: 3) {
                        Image(systemName: weather.systemIcon)
                            .font(.system(size: 9, weight: .medium))
                        Text(activity.temperatureC.map { String(format: "%.0f°C", $0) } ?? weather.formattedTemp)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.60))
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
                .foregroundStyle(.white.opacity(0.80))
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

        items.append(.init(icon: "ruler",               label: L.s("거리", "Dist."),           value: activity.formattedDistance,                      color: .white))
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
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Theme.cardBackground)
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
                        condition: condition
                    )
                    .frame(width: cardW, height: cardH)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Theme.violet.opacity(0.30), radius: 28, y: 10)

                    Spacer(minLength: 24)

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
                condition: condition
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
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_map_card_v2_\(activity.id.uuidString).jpg")
    }

    private func loadCachedMapSnapshot() -> UIImage? {
        guard let data = try? Data(contentsOf: cardMapCacheURL) else { return nil }
        return UIImage(data: data)
    }

    private func saveMapSnapshotToCache(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        try? data.write(to: cardMapCacheURL)
    }

    private func makeMapSnapshot() async -> UIImage? {
        guard let coords = detail?.routeCoordinates, !coords.isEmpty else { return nil }
        let valid = coords.filter { CLLocationCoordinate2DIsValid($0) && abs($0.latitude) > 1 && abs($0.longitude) > 1 }
        guard valid.count > 1 else { return nil }

        let lats = valid.map(\.latitude)
        let lons = valid.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }

        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.004, (maxLat - minLat) * 1.4),
                                   longitudeDelta: max(0.004, (maxLon - minLon) * 1.4))
        )
        opts.size = CGSize(width: 218, height: 168)
        opts.scale = 3
        opts.mapType = .mutedStandard
        opts.showsBuildings = false

        guard let snap = try? await MKMapSnapshotter(options: opts).start() else { return nil }

        let step = max(1, valid.count / 300)
        let pts = stride(from: 0, to: valid.count, by: step).map { snap.point(for: valid[$0]) }
        let violetColor = UIColor(red: 0x7C / 255.0, green: 0x5C / 255.0, blue: 0xFC / 255.0, alpha: 1.0)

        return UIGraphicsImageRenderer(size: snap.image.size).image { _ in
            snap.image.draw(at: .zero)
            guard pts.count > 1 else { return }
            let path = UIBezierPath()
            path.move(to: pts[0])
            for pt in pts.dropFirst() { path.addLine(to: pt) }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.lineWidth = 3
            violetColor.withAlphaComponent(0.4).setStroke()
            path.stroke()
            path.lineWidth = 1.5
            violetColor.setStroke()
            path.stroke()
            // 마커는 활동 상세 지도와 같은 구현을 쓴다 — 화면과 공유 결과가 갈라지지 않게
            RouteMarkers.drawAll(on: snap, coords: valid,
                                 endPoint: pts.last, startPoint: pts.first)
        }
    }
}

