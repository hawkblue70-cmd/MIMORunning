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

/// 경로 카드 모양 — 경로 1: 지도 풀블리드 + 글자 오버레이(2026-09-16). 경로 2: 둥근 패널 안 지도 + 상단 헤더(그 전 카드).
/// 경로 3·4는 아직 정하지 않았다.
enum RouteCardStyle: Int, CaseIterable, Identifiable {
    case hero = 1
    case classic = 2
    var id: Int { rawValue }
    var label: String { AppLanguage.shared.s("경로 \(rawValue)", "Route \(rawValue)") }
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
    /// 출발 지점의 지역명("경기도 안산시") — 역지오코딩 결과. 없으면 줄을 생략한다.
    var placeName: String? = nil
    /// 지도 패널일 때의 카드 모양. 차트 패널에는 영향 없다.
    var routeStyle: RouteCardStyle = .hero

    private var pal: RouteCardPalette { theme == .light ? .light : .dark }

    static let cardWidth:  CGFloat = 300
    static let cardHeight: CGFloat = 375
    /// 지도 패널의 지도 높이 — 카드 위 70%를 지도가 꽉 채운다(애플 피트니스 요약과 같은 구조). 아래는 지표 3열 2행.
    static let mapHeroHeight: CGFloat = 262
    static let mapHeroSize = CGSize(width: cardWidth, height: mapHeroHeight)
    /// 경로는 지도 높이의 이 비율 위쪽에만 — 그 아래는 글자 자리(애플 피트니스 요약과 같은 배치).
    static let mapRouteBottomLimit: Double = 0.6

    var body: some View {
        ZStack {
            pal.background
            if activePanel == .map && routeStyle == .hero {
                mapHeroLayout
            } else {
                panelLayout
            }
        }
    }

    /// 지도 패널 — 테두리 없이 지도를 카드 폭으로 펼치고, 그 위에 지역·러닝 종류·거리·시간·날씨를 얹는다.
    /// 이 카드는 다크만 — 지도가 늘 어둡고 흰 글자가 얹히므로 화면에서 라이트 선택지를 주지 않는다.
    private var mapHeroLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let snapshot = mapSnapshot {
                        Image(uiImage: snapshot).resizable().scaledToFill()
                    } else if let coords = detail?.routeCoordinates, !coords.isEmpty {
                        ZStack {
                            Color(hex: "14121C")
                            RouteLineArt(coordinates: coords, lineColor: Theme.violet, lineWidth: 1.5)
                                .padding(30)
                        }
                    } else {
                        Color(hex: "14121C")
                    }
                }
                .frame(width: Self.cardWidth, height: Self.mapHeroHeight)
                .clipped()
                // 위쪽은 지도 원색 그대로(경로가 밝게), 가운데부터 아래로 스크림 — 애플 피트니스 요약과 같은 밝기 곡선
                .overlay(alignment: .bottom) {
                    LinearGradient(stops: [.init(color: .black.opacity(0), location: 0),
                                           .init(color: .black.opacity(0.45), location: 0.45),
                                           .init(color: .black.opacity(0.86), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 165)
                }

                MIMOWordmark(size: 9, strokeMIMO: false)
                    .padding(.leading, 16).padding(.top, 16)

                // 아래 24pt는 스냅샷의 Apple Maps 표기 자리 — 글자가 그 위에 얹히지 않게 비운다
                mapHeroText
                    .padding(.leading, 16).padding(.bottom, 26)
                    .frame(width: Self.cardWidth, height: Self.mapHeroHeight, alignment: .bottomLeading)
            }
            .frame(width: Self.cardWidth, height: Self.mapHeroHeight)

            // 지표는 상자 하나 안에 — 칸마다 상자를 두지 않고(셀 배경 투명) 격자를 통째로 감싼다. 3열 2행
            // 배율 0.78: 값 15.6pt · 라벨 9.4pt — 애플 요약처럼 값이 라벨의 두 배 가까이 크다
            RunMetricGrid(items: mapHeroMetricItems, style: mapHeroCellStyle,
                          scale: 0.78, showsNote: false, columns: 3)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background {
                    let r = RoundedRectangle(cornerRadius: 14)
                    r.fill(pal.cellBackground)
                        .overlay(r.stroke(pal.cellBorder, lineWidth: pal.isLight ? 0.5 : 0))
                }
                .padding(.horizontal, 14).padding(.top, 10)
            Spacer(minLength: 0)
        }
    }

    /// 지도 위 글자 묶음 — 지역 · 러닝 종류 · 거리 · (시작~종료 · 날씨 · 습도 한 줄).
    private var mapHeroText: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let placeName, !placeName.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "location.circle").font(.system(size: 9, weight: .semibold))
                    Text(placeName).font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.85))
            }
            Text(detail?.workoutType.koreanLabel ?? activity.type.label)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(distanceValue)
                    .font(.system(size: 26, weight: .heavy)).fontWidth(.condensed).tracking(-0.5)
                Text("KM")
                    .font(.system(size: 12, weight: .bold)).tracking(1)
            }
            .foregroundStyle(BigNumberStyle.heroGradient(.violet))
            .padding(.top, -2)
            // 날짜 · 날씨 · 습도를 한 줄에 — "날씨"·"습도" 제목 없이 아이콘과 값만. 줄이 하나 줄어 묶음이 아래로 내려간다
            HStack(spacing: 5) {
                Text(heroTimeRangeText)
                if let t = heroTempText {
                    Text("·")
                    HStack(spacing: 2) {
                        Image(systemName: condition?.weather?.systemIcon ?? "thermometer.medium")
                            .font(.system(size: 8, weight: .semibold))
                        Text(t)
                    }
                }
                if let h = heroHumidityText {
                    Text("·")
                    HStack(spacing: 2) {
                        Image(systemName: "humidity").font(.system(size: 8, weight: .semibold))
                        Text(h)
                    }
                }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(1).minimumScaleFactor(0.85)
            .padding(.top, 2)
        }
    }

    /// 지도형 격자 셀 — 같은 셀 컴포넌트, 배경·테두리만 없앤다(상자는 격자 바깥에 하나).
    private var mapHeroCellStyle: RunMetricCellStyle {
        RunMetricCellStyle(isLight: pal.isLight, textPrimary: pal.textPrimary,
                           cellBackground: .clear, cellBorder: .clear)
    }

    private var distanceValue: String {
        let km = activity.distance / 1000
        return km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
    }

    private var heroTempText: String? {
        if let t = activity.temperatureC { return String(format: "%.0f°", t) }
        if let w = condition?.weather { return String(format: "%.0f°", w.tempC) }
        return nil
    }

    private var heroHumidityText: String? {
        activity.humidityPercent.map { String(format: "%.0f%%", $0) }
    }

    /// "2026년 9월 16일 오후 6:48~7:39" — 종료가 같은 오전/오후면 시:분만 붙인다.
    private var heroTimeRangeText: String {
        let isEn = AppLanguage.shared.isEnglish
        let locale = Locale(identifier: isEn ? "en_US" : "ko_KR")
        let start = activity.date
        let end = start.addingTimeInterval(activity.duration)
        let dateFmt = DateFormatter(); dateFmt.locale = locale
        dateFmt.dateFormat = isEn ? "MMM d, yyyy" : "yyyy년 M월 d일"
        let timeFmt = DateFormatter(); timeFmt.locale = locale
        timeFmt.dateStyle = .none; timeFmt.timeStyle = .short
        let hourFmt = DateFormatter(); hourFmt.locale = locale
        hourFmt.dateFormat = "h:mm"
        let cal = Calendar.current
        let samePeriod = (cal.component(.hour, from: start) < 12) == (cal.component(.hour, from: end) < 12)
            && cal.isDate(start, inSameDayAs: end)
        let endText = samePeriod ? hourFmt.string(from: end) : timeFmt.string(from: end)
        return "\(dateFmt.string(from: start)) \(timeFmt.string(from: start))~\(endText)"
    }

    /// 지도 패널 아래 격자 — 거리는 위 히어로에 있으니 빼고, 3열 2행 여섯 칸.
    /// 순서는 누구나 읽는 것부터: 시간·페이스·심박·케이던스·칼로리·고도, 그 뒤 파워·폼(있으면 밀려 들어온다).
    private var mapHeroMetricItems: [RunMetricItem] {
        let priority: [RunMetricKind] = [.time, .pace, .heartRate, .cadence, .calories, .elevation,
                                         .power, .form, .cardio]
        func rank(_ k: RunMetricKind) -> Int { priority.firstIndex(of: k) ?? priority.count }
        let all = RunMetricItem.list(activity: activity, detail: detail, age: age, isMale: isMale)
            .filter { $0.kind != .distance }
        return Array(all.enumerated()
            .sorted { (rank($0.element.kind), $0.offset) < (rank($1.element.kind), $1.offset) }
            .map(\.element)
            .prefix(6)
            .map { $0.recolored($0.kind.shareColor(isLight: pal.isLight, textPrimary: pal.textPrimary)) })
    }

    /// 차트 패널(심박·고도·케이던스 …) — 축과 라벨이 있어 둥근 패널 안에 그린다.
    private var panelLayout: some View {
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
    /// 카드 모양별 지도 스냅샷 — 크기·지도 스타일이 달라 따로 만든다.
    @State private var mapSnapshots: [RouteCardStyle: UIImage] = [:]
    @State private var placeName: String?
    @State private var cardTheme: ShareTheme = .dark
    @State private var routeStyle: RouteCardStyle = .hero
    @Environment(\.dismiss) private var dismiss

    private let cardW = DetailPanelShareCard.cardWidth
    private var cardH: CGFloat { DetailPanelShareCard.cardHeight }
    /// 경로 1(풀블리드)은 다크 고정 — 토글도 숨긴다. 경로 2와 차트 카드는 다크/라이트를 고른다.
    private var isDarkOnly: Bool { activePanel == .map && routeStyle == .hero }
    private var mapSnapshot: UIImage? { mapSnapshots[routeStyle] }
    private var effectiveTheme: ShareTheme { isDarkOnly ? .dark : cardTheme }

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
                        theme: effectiveTheme,
                        placeName: placeName,
                        routeStyle: routeStyle
                    )
                    .frame(width: cardW, height: cardH)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Theme.violet.opacity(0.30), radius: 28, y: 10)

                    Spacer(minLength: 16)

                    if !isDarkOnly {
                        optionRow
                            .padding(.horizontal, 24)
                            .padding(.bottom, 14)
                    }

                    shareCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, activePanel == .map ? 12 : 36)

                    // 카드 모양 선택은 화면 맨 아래 — 내보내기 버튼 밑
                    if activePanel == .map {
                        styleRow
                            .padding(.horizontal, 24)
                            .padding(.bottom, 36)
                    }
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

    /// 카드 모양 — 경로 1 / 경로 2. 바꾸면 그 모양의 스냅샷(없으면 새로 찍음)으로 다시 그린다.
    private var styleRow: some View {
        segmented(left: RouteCardStyle.hero.label, leftOn: routeStyle == .hero,
                  right: RouteCardStyle.classic.label, rightOn: routeStyle == .classic) { wantsHero in
            let next: RouteCardStyle = wantsHero ? .hero : .classic
            guard routeStyle != next else { return }
            routeStyle = next
            Task { await renderCard() }
        }
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
            // 카드용 지도는 화면(398×220)과 크기가 달라 캐시를 공유하지 않는다 — 카드 모양별 전용 캐시.
            if mapSnapshots[routeStyle] == nil {
                if let cached = loadCachedMapSnapshot(style: routeStyle) {
                    mapSnapshots[routeStyle] = cached
                } else if let img = await makeMapSnapshot(style: routeStyle) {
                    mapSnapshots[routeStyle] = img
                    saveMapSnapshotToCache(img, style: routeStyle)
                }
            }
            if placeName == nil { placeName = await reverseGeocodedPlaceName() }
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
                theme: effectiveTheme,
                placeName: placeName,
                routeStyle: routeStyle
            )
            .frame(width: cardW, height: cardH)
        )
        renderer.scale = 3
        previewImage = renderer.uiImage
        isRendering = false
    }

    // MARK: Map snapshot helpers

    /// 카드 전용 지도 캐시 — 화면 지도(398×220)와 크기가 달라 따로 둔다. 카드 모양별로 파일이 다르다.
    /// 마커 모양이 바뀌면 v를 올려 옛 스냅샷이 남지 않게 한다. 경로 2는 예전 키(v4)를 그대로 써 이미 찍어 둔 스냅샷을 재사용한다.
    private func cardMapCacheURL(style: RouteCardStyle) -> URL {
        let v = style == .hero ? "v9" : "v4"
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_map_card_\(v)_\(activity.id.uuidString).jpg")
    }

    private func loadCachedMapSnapshot(style: RouteCardStyle) -> UIImage? {
        guard let data = try? Data(contentsOf: cardMapCacheURL(style: style)) else { return nil }
        return UIImage(data: data)
    }

    private func saveMapSnapshotToCache(_ image: UIImage, style: RouteCardStyle) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        try? data.write(to: cardMapCacheURL(style: style))
    }

    /// 경로 지도 — 심박이 있으면 존 색 그라데이션, 없으면 단색.
    /// 그리기는 활동 상세 지도와 같은 구현(RouteSnapshotRenderer)을 쓴다.
    /// - 경로 1: 300×262 · 다크 standard · POI 제외 · 경로는 위 60% · 기본 선 굵기 · km 알약 없음
    /// - 경로 2: 218×168 · muted 기본 · 경로 가운데 · 상세 화면과 같은 선·km 마커
    private func makeMapSnapshot(style: RouteCardStyle) async -> UIImage? {
        guard let coords = detail?.routeCoordinates, !coords.isEmpty else { return nil }
        let valid = RouteSnapshotRenderer.validCoordinates(coords)
        guard valid.count > 1 else { return nil }
        let colors = await zoneColors(for: valid)

        switch style {
        case .hero:
            guard let opts = RouteSnapshotRenderer.options(coordinates: valid,
                                                           size: DetailPanelShareCard.mapHeroSize,
                                                           scale: 3,
                                                           routeBottomLimit: DetailPanelShareCard.mapRouteBottomLimit)
            else { return nil }
            // 지도는 늘 다크 — 흰 글자를 위에 얹는다. muted가 아닌 standard: 도로·물이 살아 있어야 애플 요약처럼 보인다
            opts.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
            opts.mapType = .standard
            // 관심 지점(학교·상점·공원 이름)은 뺀다 — 도로명·행정구역명은 MapKit에 끄는 옵션이 없어 남는다
            opts.pointOfInterestFilter = .excludingAll
            guard let snap = try? await MKMapSnapshotter(options: opts).start() else { return nil }
            // 선은 상세 화면과 같은 굵기(애플 요약처럼 얇게), km 알약은 끈다 — 이 폭에서는 경로보다 마커가 커 보인다.
            return RouteSnapshotRenderer.draw(on: snap, coordinates: valid, segmentColors: colors,
                                              lineScale: 1, showKmMarkers: false)

        case .classic:
            guard let opts = RouteSnapshotRenderer.options(coordinates: valid,
                                                           size: CGSize(width: 218, height: 168),
                                                           scale: 3),
                  let snap = try? await MKMapSnapshotter(options: opts).start() else { return nil }
            return RouteSnapshotRenderer.draw(on: snap, coordinates: valid, segmentColors: colors)
        }
    }

    /// 출발 지점의 "시/도 + 시/군/구" — 스탬프 카드와 같은 역지오코딩. 실패하면 nil(줄 생략).
    private func reverseGeocodedPlaceName() async -> String? {
        guard let first = detail?.routeCoordinates.first(where: { CLLocationCoordinate2DIsValid($0) && abs($0.latitude) > 1 })
        else { return nil }
        let location = CLLocation(latitude: first.latitude, longitude: first.longitude)
        guard let pm = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let parts = [pm.administrativeArea, pm.locality].compactMap { $0 }
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: " ")
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

