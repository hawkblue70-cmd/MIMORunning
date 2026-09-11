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
    /// 셀 테두리 — 라이트는 흰 셀이 밝은 배경에 묻혀 경계가 필요하다
    let cellBorder: Color
    let divider: Color
    let wordmarkStroke: Bool
    /// 밝은 배경인가 — 지표 색을 라이트용으로 고를 때 쓴다(구간 카드와 같은 팔레트).
    let isLight: Bool

    /// 지표 셀 스타일 — 앱 상세·구간 카드와 같은 셀 컴포넌트에 넘긴다.
    var metricCellStyle: RunMetricCellStyle {
        isLight ? .light(textPrimary: textPrimary, surface: cellBackground)
                : .dark(textPrimary: textPrimary, surface: cellBackground)
    }

    static let dark = RouteCardPalette(
        background: LinearGradient(colors: [Color(hex: "1A1130"), Color(hex: "0D0D12")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
        textPrimary: .white,
        textSecondary: .white.opacity(0.60),
        cellBackground: Theme.cardBackground,
        cellBorder: .clear,
        divider: Theme.violet.opacity(0.30),
        wordmarkStroke: false,
        isLight: false
    )

    static let light = RouteCardPalette(
        background: LinearGradient(colors: [Color(hex: "FFFFFF"), Color(hex: "F2F0F7")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
        textPrimary: Color(hex: "111111"),
        textSecondary: Color(hex: "5A5A66"),
        cellBackground: Color(hex: "FFFFFF"),
        cellBorder: .black.opacity(0.10),
        divider: Color(hex: "5B3FD9").opacity(0.30),
        wordmarkStroke: true,
        isLight: true
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
    var age: Int? = nil
    var isMale: Bool? = nil
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

    /// 항목 목록도 색도 앱 상세·구간 카드와 같은 출처를 쓴다 — 카드마다 따로 만들지 않는다.
    private var metricItems: [RunMetricItem] {
        RunMetricItem.list(activity: activity, detail: detail, age: age, isMale: isMale)
            .prefix(12)
            .map { $0.recolored($0.kind.shareColor(isLight: pal.isLight, textPrimary: pal.textPrimary)) }
    }

    private var metricsGrid: some View {
        RunMetricGrid(items: metricItems, style: pal.metricCellStyle, scale: 0.46, showsNote: false)
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
    /// 유산소 피트니스 등급 문구에 쓰인다 — 앱 상세 격자와 같은 목록을 쓰므로 같이 넘긴다.
    var age: Int? = nil
    var isMale: Bool? = nil

    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @State private var showShareSheet = false
    @State private var mapSnapshot: UIImage?
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
                        age: age, isMale: isMale,
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

    /// 카드 테마 — 경로선은 늘 심박 존 색(심박이 없으면 자동으로 단색)이라 선택지가 없다
    private var optionRow: some View {
        segmented(left: AppLanguage.shared.s("다크", "Dark"), leftOn: cardTheme == .dark,
                  right: AppLanguage.shared.s("라이트", "Light"), rightOn: cardTheme == .light) { wantsDark in
            let next: ShareTheme = wantsDark ? .dark : .light
            guard cardTheme != next else { return }
            cardTheme = next
            Task { await renderCard() }
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
                age: age, isMale: isMale,
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
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_map_card_v4_\(activity.id.uuidString).jpg")
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

        // 심박 존 색이 기본. 심박이 없거나 시간대가 어긋나면 zoneColors가 nil을 돌려주고 단색이 된다.
        let colors = await zoneColors(for: valid)
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

