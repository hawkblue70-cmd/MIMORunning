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
    var shoeName: String? = nil
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
                footerRow
                    .padding(.horizontal, 41).padding(.bottom, 18)
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
        HStack {
            MIMOWordmark(size: 9)
            Spacer()
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
            if let weather = condition?.weather {
                Text("·")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Image(systemName: weather.systemIcon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(activity.temperatureC.map { String(format: "%.0f°C", $0) } ?? weather.formattedTemp)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
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

            case .splits:
                if let splits = detail?.splits, !splits.isEmpty {
                    SplitsPanelChart(splits: splits, compact: true, isLargeDisplay: false)
                } else { placeholder("chart.bar.fill") }

            case .heartRate:
                if !hrSamples.isEmpty {
                    HRSeriesPanelChart(samples: hrSamples, zones: detail?.hrZones ?? [], compact: true)
                } else { placeholder("heart.fill") }

            case .elevation:
                if let profile = detail?.altitudeProfile, !profile.isEmpty {
                    ElevationPanelChart(profile: profile, compact: true)
                } else { placeholder("mountain.2.fill") }

            case .intervals:
                if let segs = detail?.intervalSegments, !segs.isEmpty {
                    IntervalPanelChart(segments: segs, compact: true)
                } else { placeholder("repeat") }

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

    var chartAreaHeight: CGFloat {
        guard activePanel == .intervals,
              let segs = detail?.intervalSegments, !segs.isEmpty else { return 140 }
        return IntervalPanelChart.requiredHeight(segmentCount: segs.count, hasSummary: true)
    }

    var effectiveCardHeight: CGFloat {
        guard activePanel == .intervals,
              let segs = detail?.intervalSegments, !segs.isEmpty else { return Self.cardHeight }
        return (Self.cardHeight - 150) + chartAreaHeight
    }

    // 비율 유지: 가로 272×0.8=218, 세로 150×0.8=120 → 주변 여백 가로 27pt씩, 세로 15pt씩
    private var chartInnerWidth: CGFloat {
        guard activePanel == .intervals,
              let segs = detail?.intervalSegments, !segs.isEmpty else { return 218 }
        return Self.cardWidth - 28
    }

    private var chartInnerHeight: CGFloat {
        guard activePanel == .intervals,
              let segs = detail?.intervalSegments, !segs.isEmpty else { return 132 }
        return chartAreaHeight
    }

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
        var valueFontSize: CGFloat = 12  // 15pt × 0.8 (지도 축소 비율)
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
            items.append(.init(icon: "lungs.fill",      label: L.s("유산소", "Cardio"),               value: String(format: "%.1f mL/kg·m", vo2),   color: Theme.elevation, valueFontSize: 15))
        }
        if let cal = activity.calories {
            items.append(.init(icon: "flame.fill",      label: L.s("칼로리", "Cals"),          value: String(format: "%.0f kcal", cal),                color: Theme.calories))
        }
        if let elev = detail?.elevationGain, elev > 0 {
            items.append(.init(icon: "arrow.up.right",  label: L.s("고도 획득", "Elev. Gain"), value: String(format: "%.0f m", elev),                  color: Theme.elevation))
        }
        return Array(items.prefix(12))
    }

    private var metricsGrid: some View {
        let items = availableMetrics
        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 4
        ) {
            ForEach(0..<items.count, id: \.self) { i in
                metricCell(items[i])
            }
        }
    }

    private func metricCell(_ item: MetricItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(item.color)
                Text(item.label)
                    .font(.system(size: 8, weight: .medium))
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
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Footer

    private var footerRow: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color(hex: "3DFF7A").opacity(0.12))
                    .frame(width: 24, height: 24)
                Image(systemName: "figure.run")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(Color(hex: "3DFF7A"))
            }
            Spacer()
            if let shoe = shoeName, !shoe.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "shoe.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.60))
                    Text(shoe)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
        }
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
    @AppStorage("mapHRZoneMode") private var mapHRZoneMode: Bool = true

    @Query private var allStories: [WorkoutStory]
    @Query private var allShoes: [Shoe]

    private var story: WorkoutStory? { allStories.first { $0.workoutID == activity.id.uuidString } }
    private var shoeName: String? {
        guard let sid = story?.shoeID else { return nil }
        return allShoes.first { $0.id.uuidString == sid }?.displayName
    }

    private let cardW = DetailPanelShareCard.cardWidth
    private var cardH: CGFloat {
        guard activePanel == .intervals,
              let segs = detail?.intervalSegments, !segs.isEmpty else { return DetailPanelShareCard.cardHeight }
        let chartH = IntervalPanelChart.requiredHeight(segmentCount: segs.count, hasSummary: true)
        return (DetailPanelShareCard.cardHeight - 150) + chartH
    }

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
                        shoeName: shoeName,
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
            .navigationTitle(AppLanguage.shared.s("공유 카드", "Share Card"))
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
                Label(AppLanguage.shared.s("공유하기", "Share"), systemImage: "square.and.arrow.up")
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
            if mapHRZoneMode, let gradient = loadCachedGradientMapSnapshot() {
                mapSnapshot = gradient
            } else if let cached = loadCachedMapSnapshot() {
                mapSnapshot = cached
            } else {
                mapSnapshot = await makeMapSnapshot()
            }
        }
        let renderer = ImageRenderer(content:
            DetailPanelShareCard(
                activity: activity, detail: detail,
                activePanel: activePanel,
                hrSamples: hrSamples, panelSeriesData: panelSeriesData,
                shoeName: shoeName,
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

    private func loadCachedMapSnapshot() -> UIImage? {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_map_v13_\(activity.id.uuidString).jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func loadCachedGradientMapSnapshot() -> UIImage? {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_map_hrzone_v2_\(activity.id.uuidString).jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
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
        opts.size = CGSize(width: 218, height: 132)
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
            if let last = pts.last {
                let dot = UIBezierPath(ovalIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6))
                UIColor.white.setFill()
                dot.fill()
            }
        }
    }
}

// MARK: - Panel Selector Sheet

struct PanelSelectorSheet: View {
    let availablePanels: [DetailPanel]
    @Binding var selectedPanels: [DetailPanel]
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Text(AppLanguage.shared.s("최대 4개 선택 (순서가 배치 순서)", "Select up to 4 (order = layout)"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        ForEach(availablePanels, id: \.self) { panel in
                            let isSelected = selectedPanels.contains(panel)
                            let isDisabled = !isSelected && selectedPanels.count >= 4
                            Button {
                                guard !isDisabled else { return }
                                if isSelected {
                                    selectedPanels.removeAll { $0 == panel }
                                } else {
                                    selectedPanels.append(panel)
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        if isSelected {
                                            Circle()
                                                .fill(Theme.violet.opacity(0.20))
                                                .frame(width: 36, height: 36)
                                            Text("\(selectedPanels.firstIndex(of: panel).map { $0 + 1 } ?? 0)")
                                                .font(.system(size: 11, weight: .black))
                                                .foregroundStyle(Theme.violet)
                                                .offset(x: 12, y: -12)
                                        }
                                        Image(systemName: panel.icon)
                                            .font(.system(size: 20))
                                    }
                                    .frame(width: 36, height: 36)
                                    Text(panel.label)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(
                                    isSelected ? .white
                                    : isDisabled ? .white.opacity(0.25)
                                    : .white.opacity(0.70)
                                )
                                .background(
                                    isSelected ? Theme.violet
                                    : Color.white.opacity(isDisabled ? 0.04 : 0.08)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    Spacer()

                    Button {
                        dismiss()
                        onConfirm()
                    } label: {
                        Text(AppLanguage.shared.s("확인 (\(selectedPanels.count)/4)", "Confirm (\(selectedPanels.count)/4)"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(selectedPanels.isEmpty ? Theme.violet.opacity(0.4) : Theme.violet)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedPanels.isEmpty)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle(AppLanguage.shared.s("내보낼 차트 선택", "Select Charts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("취소", "Cancel")) { dismiss() }
                        .foregroundStyle(Theme.violet)
                }
            }
        }
    }
}

// MARK: - Detail Panel Grid4 Share Card

struct DetailPanelGrid4ShareCard: View {
    let activity: Activity
    let detail: ActivityDetail?
    let selectedPanels: [DetailPanel]
    let hrSamples: [(offset: TimeInterval, bpm: Int)]
    let panelSeriesCache: [DetailPanel: [(offset: TimeInterval, value: Double)]]
    var shoeName: String? = nil
    var condition: ActivityCondition? = nil
    var routeMapSnapshot: UIImage? = nil

    static let cardWidth:  CGFloat = 300
    static let cardHeight: CGFloat = 375

    private let hPad:   CGFloat = 12
    private let gap:    CGFloat = 4
    private let cellH:  CGFloat = 106
    private let chartH: CGFloat = 90

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.horizontal, hPad).padding(.top, 14)
                grid2x2
                    .padding(.horizontal, hPad).padding(.top, 8)
                Rectangle()
                    .fill(Theme.violet.opacity(0.30))
                    .frame(height: 0.5)
                    .padding(.horizontal, hPad).padding(.top, 6)
                metricsGrid
                    .padding(.horizontal, hPad).padding(.top, 5).padding(.bottom, 20)
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
        return ["일","월","화","수","목","금","토"][(weekday - 1) % 7]
    }

    private var headerRow: some View {
        HStack {
            MIMOWordmark(size: 9)
            Spacer()
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
        }
    }

    // MARK: 2×2 Grid

    private var grid2x2: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: gap), GridItem(.flexible(), spacing: gap)],
            spacing: gap
        ) {
            ForEach(0..<4, id: \.self) { i in
                if i < selectedPanels.count {
                    miniCell(selectedPanels[i])
                } else {
                    emptyCell
                }
            }
        }
    }

    @ViewBuilder
    private func miniCell(_ panel: DetailPanel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: panel.icon)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(accentColor(panel))
                Text(panel.label)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.80))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 14)   // 고정 높이 → 4개 차트 동일 크기 보장
            Group { miniChart(panel) }
                .frame(maxWidth: .infinity)
                .frame(height: chartH)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: cellH)
    }

    private var emptyCell: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.03))
            .frame(height: cellH)
    }

    @ViewBuilder
    private func miniChart(_ panel: DetailPanel) -> some View {
        switch panel {
        case .map:
            if let snap = routeMapSnapshot {
                Image(uiImage: snap)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if let coords = detail?.routeCoordinates, !coords.isEmpty {
                RouteLineArt(coordinates: coords, lineColor: Theme.violet, lineWidth: 1.2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { chartPlaceholder(panel.icon) }

        case .splits:
            if let splits = detail?.splits, !splits.isEmpty {
                SplitsPanelChart(splits: splits, compact: true, isLargeDisplay: false)
            } else { chartPlaceholder(panel.icon) }

        case .heartRate:
            if !hrSamples.isEmpty {
                HRSeriesPanelChart(samples: hrSamples, zones: detail?.hrZones ?? [], compact: true, labelScale: 0.85)
            } else { chartPlaceholder(panel.icon) }

        case .elevation:
            if let profile = detail?.altitudeProfile, !profile.isEmpty {
                ElevationPanelChart(profile: profile, compact: true)
            } else { chartPlaceholder(panel.icon) }

        case .intervals:
            if let segs = detail?.intervalSegments, !segs.isEmpty {
                IntervalPanelChart(segments: segs, compact: true)
            } else { chartPlaceholder(panel.icon) }

        case .combined:
            chartPlaceholder(panel.icon)

        case .cadence, .power, .groundContact, .strideLength, .verticalOscillation:
            let data = panelSeriesCache[panel] ?? []
            if !data.isEmpty {
                MetricBarPanelChart(
                    samples: data,
                    color: accentColor(panel),
                    unit: seriesUnit(panel),
                    format: seriesFormat(panel),
                    useRangeBar: seriesUseRangeBar(panel),
                    validMin: panel == .cadence ? 130 : 0,
                    barWidthOverride: 1,
                    compact: true
                )
            } else { chartPlaceholder(panel.icon) }
        }
    }

    private func chartPlaceholder(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 18))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Accent / series helpers

    private func accentColor(_ panel: DetailPanel) -> Color {
        switch panel {
        case .heartRate:                                  return Theme.heartRate
        case .cadence:                                    return Theme.cadence
        case .power:                                      return Theme.power
        case .elevation:                                  return Theme.elevation
        case .groundContact, .strideLength,
             .verticalOscillation:                        return Theme.runningForm
        default:                                          return Theme.violet
        }
    }

    private func seriesUnit(_ panel: DetailPanel) -> String {
        switch panel {
        case .cadence:             return "spm"
        case .power:               return "W"
        case .groundContact:       return "ms"
        case .strideLength:        return "m"
        case .verticalOscillation: return "cm"
        default:                   return ""
        }
    }

    private func seriesFormat(_ panel: DetailPanel) -> String {
        switch panel {
        case .strideLength:        return "%.2f"
        case .verticalOscillation: return "%.1f"
        default:                   return "%.0f"
        }
    }

    private func seriesUseRangeBar(_ panel: DetailPanel) -> Bool {
        switch panel {
        case .power, .groundContact, .strideLength, .verticalOscillation: return true
        default: return false
        }
    }

    // MARK: Metrics grid

    private struct MetricItem {
        let icon: String; let label: String; let value: String; let color: Color
        var valueFontSize: CGFloat = 12
    }

    private var availableMetrics: [MetricItem] {
        let L = AppLanguage.shared
        var items: [MetricItem] = []
        items.append(.init(icon: "ruler",               label: L.s("거리","Dist."),        value: activity.formattedDistance,               color: .white))
        items.append(.init(icon: "clock",               label: L.s("시간","Time"),          value: activity.formattedDuration,               color: Theme.time))
        if let pace = activity.formattedPace {
            items.append(.init(icon: "timer",           label: L.s("페이스","Pace"),        value: pace,                                     color: Theme.pace))
        }
        if let hr = activity.avgHeartRate {
            items.append(.init(icon: "heart.fill",      label: L.s("평균 심박","Avg HR"),   value: "\(hr) bpm",                             color: Theme.heartRate))
        }
        if let cad = detail?.avgCadence {
            items.append(.init(icon: "figure.run",      label: L.s("케이던스","Cadence"),   value: "\(cad) spm",                            color: Theme.cadence))
        }
        if let pwr = detail?.avgPower {
            items.append(.init(icon: "bolt.fill",            label: L.s("파워","Power"),          value: "\(pwr) W",                              color: Theme.power))
        }
        if let gct = detail?.avgGroundContactTime {
            items.append(.init(icon: "stopwatch",            label: L.s("지면 접촉","Gnd."),       value: "\(Int(gct.rounded())) ms",              color: Theme.runningForm))
        }
        if let sl = detail?.avgStrideLength {
            items.append(.init(icon: "arrow.left.and.right", label: L.s("보폭","Stride"),          value: String(format: "%.2f m", sl),            color: Theme.runningForm))
        }
        if let vo2 = detail?.vo2Max {
            items.append(.init(icon: "lungs.fill",           label: L.s("유산소","Cardio"),        value: String(format: "%.1f", vo2),             color: Theme.elevation, valueFontSize: 9))
        }
        if let cal = activity.calories {
            items.append(.init(icon: "flame.fill",           label: L.s("칼로리","Cals"),          value: String(format: "%.0f kcal", cal),        color: Theme.calories))
        }
        if let elev = detail?.elevationGain, elev > 0 {
            items.append(.init(icon: "arrow.up.right",       label: L.s("고도 획득","Elev."),      value: String(format: "%.0f m", elev),          color: Theme.elevation))
        }
        return Array(items.prefix(12))
    }

    private var metricsGrid: some View {
        let items = availableMetrics
        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 4
        ) {
            ForEach(0..<items.count, id: \.self) { i in
                metricCell(items[i])
            }
        }
    }

    private func metricCell(_ item: MetricItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(item.color)
                Text(item.label)
                    .font(.system(size: 8, weight: .medium))
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
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Footer

    private var footerRow: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color(hex: "3DFF7A").opacity(0.12))
                    .frame(width: 24, height: 24)
                Image(systemName: "figure.run")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(Color(hex: "3DFF7A"))
            }
            Spacer()
            if let shoe = shoeName, !shoe.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "shoe.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.60))
                    Text(shoe)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Detail Panel Grid4 Share Card Screen

struct DetailPanelGrid4ShareCardScreen: View {
    let activity: Activity
    let detail: ActivityDetail?
    let availablePanels: [DetailPanel]
    let hrSamples: [(offset: TimeInterval, bpm: Int)]
    let panelSeriesCache: [DetailPanel: [(offset: TimeInterval, value: Double)]]
    var condition: ActivityCondition? = nil

    @State private var selectedPanels: [DetailPanel] = []
    @State private var previewImage: UIImage?
    @State private var isRendering = false
    @State private var showShareSheet = false
    @State private var routeMapSnapshot: UIImage?
    @Environment(\.dismiss) private var dismiss

    @Query private var allStories: [WorkoutStory]
    @Query private var allShoes:   [Shoe]

    private var story:    WorkoutStory? { allStories.first { $0.workoutID == activity.id.uuidString } }
    private var shoeName: String? {
        guard let sid = story?.shoeID else { return nil }
        return allShoes.first { $0.id.uuidString == sid }?.displayName
    }

    private let cardW = DetailPanelGrid4ShareCard.cardWidth
    private let cardH = DetailPanelGrid4ShareCard.cardHeight

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    chipRow
                        .padding(.top, 10)
                    Spacer()
                    DetailPanelGrid4ShareCard(
                        activity: activity, detail: detail,
                        selectedPanels: selectedPanels,
                        hrSamples: hrSamples,
                        panelSeriesCache: panelSeriesCache,
                        shoeName: shoeName,
                        condition: condition,
                        routeMapSnapshot: routeMapSnapshot
                    )
                    .frame(width: cardW, height: cardH, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Theme.violet.opacity(0.30), radius: 28, y: 10)

                    Spacer(minLength: 20)

                    shareCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }
            }
            .navigationTitle(AppLanguage.shared.s("공유 카드", "Share Card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Theme.violet)
                }
            }
        }
        .onChange(of: selectedPanels) {
            Task { await renderCard() }
        }
        .onChange(of: hrSamples.count) {
            guard !selectedPanels.isEmpty else { return }
            Task { await renderCard() }
        }
        .onChange(of: panelSeriesCache.values.reduce(0) { $0 + $1.count }) {
            // 전체 샘플 수 변화(새 패널 추가 or 빈 캐시→데이터 갱신) 시 카드 재렌더
            guard !selectedPanels.isEmpty else { return }
            Task { await renderCard() }
        }
        .task {
            routeMapSnapshot = await makeMapSnapshotForGrid()
        }
    }

    // MARK: Chip row (4-4-2 고정)

    private var chipRow: some View {
        let row1 = Array(availablePanels.prefix(4))
        let row2 = Array(availablePanels.dropFirst(4).prefix(4))
        let row3 = Array(availablePanels.dropFirst(8))
        return VStack(alignment: .leading, spacing: 6) {
            chipLine(row1)
            if !row2.isEmpty { chipLine(row2) }
            if !row3.isEmpty { chipLine(row3) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    private func chipLine(_ panels: [DetailPanel]) -> some View {
        HStack(spacing: 8) {
            ForEach(panels, id: \.self) { panel in
                let isSelected = selectedPanels.contains(panel)
                let position   = selectedPanels.firstIndex(of: panel).map { $0 + 1 }
                let isDisabled = !isSelected && selectedPanels.count >= 4
                Button {
                    guard !isDisabled else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isSelected {
                            selectedPanels.removeAll { $0 == panel }
                        } else {
                            selectedPanels.append(panel)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if let pos = position {
                            Text("\(pos)")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Color.white.opacity(0.35))
                                .clipShape(Circle())
                        } else {
                            Image(systemName: panel.icon)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(panel.label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(
                        isSelected ? .white
                        : isDisabled ? .white.opacity(0.25)
                        : .white.opacity(0.70)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        isSelected ? Theme.violet
                        : Color.white.opacity(isDisabled ? 0.04 : 0.08)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Share CTA

    @ViewBuilder
    private var shareCTA: some View {
        if isRendering {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.violet)
                Text(AppLanguage.shared.s("카드 만드는 중...", "Creating card..."))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
        } else if selectedPanels.isEmpty {
            Text(AppLanguage.shared.s("위에서 차트를 선택해 주세요 (최대 4개)", "Select up to 4 charts above"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 18)
        } else if previewImage != nil {
            Button { showShareSheet = true } label: {
                Label(AppLanguage.shared.s("공유하기", "Share"), systemImage: "square.and.arrow.up")
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

    private func makeMapSnapshotForGrid() async -> UIImage? {
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
        opts.size = CGSize(width: 140, height: 90)
        opts.scale = 3
        opts.mapType = .mutedStandard
        opts.showsBuildings = false
        opts.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

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
            path.lineWidth = 2.5
            violetColor.withAlphaComponent(0.4).setStroke()
            path.stroke()
            path.lineWidth = 1.2
            violetColor.setStroke()
            path.stroke()
            if let last = pts.last {
                let dot = UIBezierPath(ovalIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5))
                UIColor.white.setFill()
                dot.fill()
            }
        }
    }

    @MainActor
    private func renderCard() async {
        guard !selectedPanels.isEmpty else { previewImage = nil; return }
        isRendering = true
        let renderer = ImageRenderer(content:
            DetailPanelGrid4ShareCard(
                activity: activity, detail: detail,
                selectedPanels: selectedPanels,
                hrSamples: hrSamples,
                panelSeriesCache: panelSeriesCache,
                shoeName: shoeName,
                condition: condition,
                routeMapSnapshot: routeMapSnapshot
            )
            .frame(width: cardW, height: cardH, alignment: .top)
        )
        renderer.scale = 3
        previewImage = renderer.uiImage
        isRendering = false
    }
}
