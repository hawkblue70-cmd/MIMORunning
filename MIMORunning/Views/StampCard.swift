// 스탬프 카드 렌더러. 미리보기와 영상 합성이 모두 이 뷰를 사용한다(렌더 경로 단일화).
// ⚠️ 스탬프 카드 전용. 다른 카드 코드 작성 금지.

import CoreLocation
import SwiftUI

// MARK: - StampData

/// km 스플릿 하나 — 요약 그리드+페이스의 세로 목록 재료.
struct StampSplit {
    let distanceM: Double
    let duration: TimeInterval
    let heartRate: Int?

    /// 세로 목록 한 줄 — 묶인 구간의 끝 거리·페이스·평균 심박
    struct Row {
        let endKm: Double
        let paceSecPerKm: Double
        let heartRate: Int?
    }

    /// 묶음 단위(km) — 총거리 16km 이하 1km, 40km 이하 2km, 그 이상 3km (줄 수 ≤ 20).
    static func bucketKm(totalKm: Double) -> Int {
        totalKm > 40 ? 3 : totalKm > 16 ? 2 : 1
    }

    /// 스플릿을 묶어 줄로 — 페이스는 합친 시간/거리, 심박은 심박 있는 구간의 시간 가중 평균.
    static func rows(_ splits: [StampSplit]) -> [Row] {
        let total = splits.reduce(0) { $0 + $1.distanceM } / 1000
        let n = bucketKm(totalKm: total)
        var out: [Row] = []
        var cum = 0.0
        for start in stride(from: 0, to: splits.count, by: n) {
            let chunk = splits[start ..< min(start + n, splits.count)]
            let dist = chunk.reduce(0) { $0 + $1.distanceM }
            let dur  = chunk.reduce(0) { $0 + $1.duration }
            guard dist > 0, dur > 0 else { continue }
            cum += dist / 1000
            let hrParts = chunk.compactMap { s in s.heartRate.map { (Double($0) * s.duration, s.duration) } }
            let hrDur = hrParts.reduce(0) { $0 + $1.1 }
            let hr = hrDur > 0 ? Int((hrParts.reduce(0) { $0 + $1.0 } / hrDur).rounded()) : nil
            out.append(Row(endKm: cum, paceSecPerKm: dur / (dist / 1000), heartRate: hr))
        }
        return out
    }
}

struct StampData {
    let distance: String
    let distanceUnit: String
    let pace: String
    let time: String
    let heartRate: String?
    let calories: String?
    let dateText: String
    let locationText: String
    let weekday: String
    // 지표 특화 (옵셔널 — 없으면 nil)
    var heartRateMax: String?    = nil   // "172"
    var hrZoneLabel: String?     = nil   // "Z4"
    var hrZoneIndex: Int?        = nil   // 0~4 (0-based)
    var hrZoneName: String?      = nil   // "THRESHOLD"
    var cadence: String?         = nil   // "182"
    /// 심박 칸의 라벨을 바꾼다. 기본은 평균("AVG HR") — 경로 영상은 그 시점의 값이라 "HR"로 쓴다.
    var heartRateLabel: String?  = nil
    /// 심박 숫자만 다른 색으로. 경로 영상이 그 시점 심박의 **존 색**을 넣는다(지도 경로선과 같은 색).
    var heartRateColor: Color?   = nil
    var elevGain: String?        = nil   // "142"
    var elevSeries: [Double]?    = nil   // 고도 곡선 (0~1 정규화)
    var hrSeries: [Double]?      = nil   // 심박 파형 (0~1 정규화)
    // 지명
    var placeName: String?       = nil   // "ANSAN"
    var placeRegion: String?     = nil   // "GYEONGGI"
    var coordText: String?       = nil   // "37.32°N 126.83°E"
    // 지도 배경
    var mapImage: UIImage?       = nil
    var routePoints: [CGPoint]?  = nil   // mapImage 좌표계의 경로점
    var routeCoordinates: [CLLocationCoordinate2D]? = nil   // 경로 라인아트용 원시 좌표
    // 날짜 라벨용 원본 날짜 (showDate 토글 시 워드마크 줄 오른쪽에 날짜·시간 표시)
    var date: Date?              = nil
    /// km 스플릿 (페이스·심박) — 요약 그리드+페이스 차트. 2개 미만이면 그 스탬프를 고를 수 없다
    var splits: [StampSplit]?    = nil

    static let sample = StampData(
        distance: "10.13",
        distanceUnit: "KM",
        pace: "6'11\"",
        time: "1:02:42",
        heartRate: "148",
        calories: "451",
        dateText: "JUL 15",
        locationText: "ANSAN · KR",
        weekday: "WED",
        heartRateMax: "172",
        hrZoneLabel: "Z4",
        hrZoneIndex: 3,
        hrZoneName: "THRESHOLD",
        cadence: "182",
        elevGain: "142",
        elevSeries: [0.10, 0.18, 0.32, 0.48, 0.65, 0.72, 0.60, 0.75, 0.80, 0.70, 0.62, 0.55],
        hrSeries: [0.5, 0.52, 0.6, 0.8, 1.0, 0.12, 0.62, 0.68, 0.72, 0.68, 0.62, 0.6, 0.5, 0.52, 0.6, 0.8, 1.0, 0.12, 0.62, 0.68],
        placeName: "ANSAN",
        placeRegion: "GYEONGGI",
        coordText: "37.32°N 126.83°E",
        routeCoordinates: [
            CLLocationCoordinate2D(latitude: 37.325, longitude: 126.818),
            CLLocationCoordinate2D(latitude: 37.328, longitude: 126.824),
            CLLocationCoordinate2D(latitude: 37.334, longitude: 126.827),
            CLLocationCoordinate2D(latitude: 37.340, longitude: 126.824),
            CLLocationCoordinate2D(latitude: 37.343, longitude: 126.818),
            CLLocationCoordinate2D(latitude: 37.340, longitude: 126.812),
            CLLocationCoordinate2D(latitude: 37.334, longitude: 126.809),
            CLLocationCoordinate2D(latitude: 37.328, longitude: 126.812),
            CLLocationCoordinate2D(latitude: 37.325, longitude: 126.818),
        ],
        splits: [(378, 138), (372, 144), (369, 147), (371, 149), (366, 150),
                 (374, 151), (368, 152), (363, 154), (360, 156), (352, 161)]
            .map { StampSplit(distanceM: 1000, duration: $0.0, heartRate: $0.1) }
    )
}

// MARK: - 날짜·시간 라벨 (워드마크 줄 오른쪽 · 스토리/영상/슬라이드/경로 영상 공용)

/// 스탬프 카드의 날짜·시간 라벨. `StampPhotoConfig.showDate`가 켜져 있을 때만 배치한다.
struct StampDateLabel: View {
    let date: Date
    var body: some View {
        Text(StampDateLabel.string(for: date))
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
    }
    /// 예: "2026. 9. 4 오후 6:16" (애슬레틱 카드 날짜 줄과 같은 포맷터)
    static func string(for date: Date) -> String {
        "\(date.cardDateString) \(date.cardTimeString)"
    }
}

// MARK: - Stamp Outline (4방향 그림자로 text-stroke 시뮬레이션)

extension View {
    // fill = 텍스트 주색(경로선과 동일), outline = 외곽 그림자색(경로 케이싱과 동일).
    // 8방향 0.45pt shadow가 외곽선처럼 보이고, foreground fill이 주색으로 드러남.
    func stampOutline(fill: Color, outline: Color) -> some View {
        let c = outline.opacity(0.50)
        return self.foregroundStyle(fill)
            .shadow(color: c, radius: 0.2, x:  0.45, y:  0)
            .shadow(color: c, radius: 0.2, x: -0.45, y:  0)
            .shadow(color: c, radius: 0.2, x:  0,    y:  0.45)
            .shadow(color: c, radius: 0.2, x:  0,    y: -0.45)
            .shadow(color: c, radius: 0.2, x:  0.45, y:  0.45)
            .shadow(color: c, radius: 0.2, x: -0.45, y: -0.45)
            .shadow(color: c, radius: 0.2, x:  0.45, y: -0.45)
            .shadow(color: c, radius: 0.2, x: -0.45, y:  0.45)
    }

    @ViewBuilder
    func stampTextOutline(show: Bool, fill: Color, outline: Color) -> some View {
        if show { self.stampOutline(fill: fill, outline: outline) }
        else    { self.foregroundStyle(fill) }
    }
}

// MARK: - Stamp Color Mapping

func stampColors(_ mode: StampColorMode, isBrightBackground: Bool) -> (fill: Color, outline: Color) {
    let violet = Theme.violet
    switch mode {
    case .brand: return (.white, violet)
    case .ink:   return (.black, .white)
    case .lime:  return (Color(hex: "C6FF00"), Color(hex: "14122B"))
    case .red:   return (Color(hex: "FF2E2E"), Color(hex: "14122B"))
    case .auto:  return isBrightBackground ? (.black, violet) : (.white, violet)
    }
}

// MARK: - Helpers

// 명시된 pt 크기는 medium(sizeLevel.scale == 0.8) 기준; 헬퍼로 레벨별 스케일. 결과는 정수 pt로 반올림.
private func sz(_ pt: CGFloat, _ scale: CGFloat) -> CGFloat { (pt * scale / 0.8).rounded() }

// MARK: - Shape helpers (Canvas 대체 — ImageRenderer 오프스크린에서 Canvas 첫 렌더 블랙 방지)

private struct BracketsShape: Shape {
    let inset: CGFloat; let bw: CGFloat; let bh: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // ┌
        p.move(to: CGPoint(x: rect.minX + inset + bw, y: rect.minY + inset))
        p.addLine(to: CGPoint(x: rect.minX + inset,   y: rect.minY + inset))
        p.addLine(to: CGPoint(x: rect.minX + inset,   y: rect.minY + inset + bh))
        // ┐
        p.move(to: CGPoint(x: rect.maxX - inset - bw, y: rect.minY + inset))
        p.addLine(to: CGPoint(x: rect.maxX - inset,   y: rect.minY + inset))
        p.addLine(to: CGPoint(x: rect.maxX - inset,   y: rect.minY + inset + bh))
        // └
        p.move(to: CGPoint(x: rect.minX + inset,      y: rect.maxY - inset - bh))
        p.addLine(to: CGPoint(x: rect.minX + inset,   y: rect.maxY - inset))
        p.addLine(to: CGPoint(x: rect.minX + inset + bw, y: rect.maxY - inset))
        // ┘
        p.move(to: CGPoint(x: rect.maxX - inset,      y: rect.maxY - inset - bh))
        p.addLine(to: CGPoint(x: rect.maxX - inset,   y: rect.maxY - inset))
        p.addLine(to: CGPoint(x: rect.maxX - inset - bw, y: rect.maxY - inset))
        return p
    }
}

private struct WaveLineShape: Shape {
    let series: [Double]
    func path(in rect: CGRect) -> Path {
        guard series.count > 1 else { return Path() }
        var p = Path()
        for (i, v) in series.enumerated() {
            let pt = CGPoint(x: rect.width * CGFloat(i) / CGFloat(series.count - 1),
                             y: rect.height * (1.0 - v))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

private struct ElevFillShape: Shape {
    let series: [Double]
    func path(in rect: CGRect) -> Path {
        guard series.count > 1 else { return Path() }
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.height))
        for (i, v) in series.enumerated() {
            p.addLine(to: CGPoint(x: rect.width * CGFloat(i) / CGFloat(series.count - 1),
                                  y: rect.height * (1.0 - v)))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.closeSubpath()
        return p
    }
}

private struct ElevLineShape: Shape {
    let series: [Double]
    func path(in rect: CGRect) -> Path {
        guard series.count > 1 else { return Path() }
        var p = Path()
        for (i, v) in series.enumerated() {
            let pt = CGPoint(x: rect.width * CGFloat(i) / CGFloat(series.count - 1),
                             y: rect.height * (1.0 - v))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

private struct EQBarShape: Shape {
    let barHeights: [Double]
    func path(in rect: CGRect) -> Path {
        let count = barHeights.count
        guard count > 1 else { return Path() }
        let totalGap = rect.width * 0.4
        let barW = (rect.width - totalGap) / CGFloat(count)
        let gap = totalGap / CGFloat(count - 1)
        var p = Path()
        for i in 0..<count {
            let x = CGFloat(i) * (barW + gap)
            let h = rect.height * barHeights[i]
            p.addRoundedRect(in: CGRect(x: x, y: rect.height - h, width: barW, height: h),
                             cornerSize: CGSize(width: 1, height: 1))
        }
        return p
    }
}

// MARK: - Route Line Art

struct StampRouteArt: View {
    let coords: [CLLocationCoordinate2D]
    let lineWidth: CGFloat
    let color: Color       // 경로 선 색 (= stampColors의 fill)
    let casingColor: Color // 경로 케이싱 색 (= stampColors의 outline), lineWidth + 2.8pt

    var body: some View {
        GeometryReader { geo in
            let pts = Self.routePoints(Self.downsample(coords), in: geo.size)
            if pts.count > 1 {
                let dotR = lineWidth * 1.3
                let path = Self.buildPath(pts)
                ZStack(alignment: .topLeading) {
                    // 케이싱 (하단)
                    path.stroke(casingColor, style: StrokeStyle(lineWidth: lineWidth + 2.8,
                                                                 lineCap: .round, lineJoin: .round))
                    // 경로 선
                    path.stroke(color, style: StrokeStyle(lineWidth: lineWidth,
                                                           lineCap: .round, lineJoin: .round))
                    // 시작점 — 빈 원
                    Circle()
                        .stroke(color, lineWidth: max(0.5, lineWidth * 0.45))
                        .frame(width: dotR * 2, height: dotR * 2)
                        .position(pts[0])
                    // 끝점 — 채운 원
                    Circle()
                        .fill(color)
                        .frame(width: dotR * 2.2, height: dotR * 2.2)
                        .position(pts.last!)
                }
            }
        }
    }

    private static func buildPath(_ pts: [CGPoint]) -> Path {
        var p = Path()
        p.move(to: pts[0])
        pts.dropFirst().forEach { p.addLine(to: $0) }
        return p
    }

    static func routePoints(_ coords: [CLLocationCoordinate2D], in size: CGSize) -> [CGPoint] {
        guard coords.count > 1 else { return [] }
        let lats = coords.map(\.latitude); let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return [] }
        let latRange = maxLat - minLat
        let lonRange = maxLon - minLon
        let latScale = latRange > 0 ? size.height / latRange : size.height
        let lonScale = lonRange > 0 ? size.width  / lonRange : size.width
        let s = min(latScale, lonScale)
        let usedW = lonRange * s; let usedH = latRange * s
        let ox = (size.width - usedW) / 2; let oy = (size.height - usedH) / 2
        return coords.map {
            CGPoint(x: ox + ($0.longitude - minLon) * s,
                    y: oy + (maxLat - $0.latitude) * s)
        }
    }

    static func downsample(_ coords: [CLLocationCoordinate2D], maxCount: Int = 300) -> [CLLocationCoordinate2D] {
        guard coords.count > maxCount else { return coords }
        let step = max(1, coords.count / maxCount)
        return stride(from: 0, to: coords.count, by: step).map { coords[$0] }
    }

    static func isPortraitRoute(_ coords: [CLLocationCoordinate2D]) -> Bool {
        guard coords.count > 1 else { return true }
        let lats = coords.map(\.latitude); let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return true }
        let latDist = (maxLat - minLat) * 111_000.0
        let lonDist = (maxLon - minLon) * 111_000.0 * cos(((minLat + maxLat) / 2) * .pi / 180)
        return latDist >= lonDist
    }
}

// HR / 칼로리 푸터 문자열 (켜진 것만, " · " 연결)
private func stampMetricFooter(data: StampData, hr: Bool, cal: Bool) -> String? {
    var parts: [String] = []
    if hr,  let v = data.heartRate { parts.append("\(v) BPM") }
    if cal, let v = data.calories  { parts.append("\(v) CAL") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

// MARK: - StampCard

struct StampCard: View {
    let data: StampData
    let template: StampTemplate
    let colorMode: StampColorMode
    let position: CardPosition
    let sizeLevel: TextSizeLevel
    let isBrightBackground: Bool
    var showHeartRate: Bool = false
    var showCalories: Bool = false
    var showTextOutline: Bool = true
    var stampText: String = ""
    var stampTextPosition: CardPosition = .top
    var stampTextFont: OneLinerFont = .gothic
    var stampTextSize: TextSizeLevel = .medium
    var stampTextColor: OneLinerTextColor = .white
    var stampTextHasBorder: Bool = false
    /// 워드마크 아래로 문구를 밀어내는 추가 top 여백 (스토리 카드: 28pt, 기본: 14pt)
    var wordmarkTopInset: CGFloat = 14
    /// true 시 문구 레이어 숨김 — 스탬프만 렌더 (애니메이션 분리 출력용)
    var renderOnlyStamp: Bool = false
    /// true 시 스탬프 레이어 숨김 — 문구만 렌더 (애니메이션 분리 출력용)
    var renderOnlyText: Bool = false

    var body: some View {
        let (fill, outline) = stampColors(colorMode, isBrightBackground: isBrightBackground)
        // 스탬프별 절대 배율표 (StampTemplate.sizeScales) — 폭 기준 소 40%·중 55%·대 72%·특대 90%
        let scale = template.stampScale(for: sizeLevel)

        ZStack {
            if !renderOnlyText {
                if template.positionMode == .fixed {
                    stampContent(fill: fill, outline: outline, scale: scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // ImageRenderer에서 .frame(alignment:)의 bottom 앵커가 무시되는 SwiftUI 버그를
                    // 회피하기 위해 VStack/HStack/Spacer로 9격 위치 결정.
                    // 상단: top Spacer 없음, 하단: bottom Spacer 없음 (Spacer가 공간을 채움).
                    // 좌우 여백: 워드마크(패딩 14 + M 잉크 시작 ≈2.7)와 같은 선 → 로고 아래 스탬프가 왼쪽 정렬됨.
                    // 기울어진 스탬프는 삐져나오는 양(leadingOverhang)만큼 더 들여 잉크 끝을 맞춘다.
                    let sideInset = 14 + MIMOWordmark.inkLeadingInset(size: 11)
                    // fixedSize: 배율표가 폭 안에 들어오도록 보장하므로 줄바꿈 대신 자연 크기 유지
                    let stampPadded = stampContent(fill: fill, outline: outline, scale: scale)
                        .fixedSize()
                        .padding(EdgeInsets(
                            top: position.isTop ? wordmarkTopInset : 12,
                            leading: sideInset + template.leadingOverhang * scale,
                            bottom: 12,
                            trailing: sideInset + template.leadingOverhang * scale))
                    VStack(spacing: 0) {
                        if !position.isTop    { Spacer(minLength: 0) }
                        HStack(spacing: 0) {
                            if !position.isLeading   { Spacer(minLength: 0) }
                            stampPadded
                            if !position.isTrailing  { Spacer(minLength: 0) }
                        }
                        if !position.isBottom { Spacer(minLength: 0) }
                    }
                }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if !renderOnlyStamp, !stampText.isEmpty {
                // 문구도 워드마크 M의 왼쪽 선에 맞춤 (스탬프와 동일 기준)
                let textSideInset = 14 + MIMOWordmark.inkLeadingInset(size: 11)
                let textPadded = textOverlay
                    .padding(EdgeInsets(
                        top: stampTextPosition.isTop ? wordmarkTopInset : 14,
                        leading: textSideInset, bottom: 14, trailing: textSideInset))
                VStack(spacing: 0) {
                    if !stampTextPosition.isTop    { Spacer(minLength: 0) }
                    textPadded
                    if !stampTextPosition.isBottom { Spacer(minLength: 0) }
                }
            }
        }
    }

    @ViewBuilder
    private var textOverlay: some View {
        let fontSize = OneLinerFont.basePt * stampTextFont.sizeScale * stampTextSize.scale
        let textAlign: TextAlignment = stampTextPosition.isLeading ? .leading
            : stampTextPosition.isTrailing ? .trailing : .center
        EffectTextView(
            text: stampText,
            font: stampTextFont.swiftUIFont(size: fontSize),
            lineSpacing: fontSize * 0.1,
            alignment: textAlign,
            color: stampTextColor.color,
            appearanceMode: .typing,
            decorEffect: .none,
            hasBorder: stampTextHasBorder,
            syntheticBoldStroke: stampTextFont.syntheticBoldStroke(for: fontSize),
            borderColor: stampTextHasBorder ? stampTextColor.borderSwiftColor : .clear,
            borderOffset: stampTextHasBorder ? max(0.8, fontSize * stampTextColor.borderOffsetFactor) : 0,
            isStaticPreview: true
        )
    }

    @ViewBuilder
    private func stampContent(fill: Color, outline: Color, scale: CGFloat) -> some View {
        switch template {
        case .passportStamp:
            StampPassportView(data: data, fill: fill, outline: outline, scale: scale,
                              showTextOutline: showTextOutline)
        case .circleBadge:
            StampCircleBadgeView(data: data, fill: fill, outline: outline, scale: scale,
                                 showTextOutline: showTextOutline)
        case .scoreboard:
            StampScoreboardView(data: data, fill: fill, outline: outline, scale: scale,
                                showTextOutline: showTextOutline)
        case .labeledRows:
            StampLabeledRowsView(data: data, fill: fill, outline: outline, scale: scale,
                                 showHeartRate: showHeartRate, showCalories: showCalories,
                                 showTextOutline: showTextOutline)
        case .inlineTriple:
            StampInlineTripleView(data: data, fill: fill, outline: outline, scale: scale,
                                  showHeartRate: showHeartRate, showCalories: showCalories,
                                  showTextOutline: showTextOutline)
        case .distanceHero:
            StampDistanceHeroView(data: data, fill: fill, outline: outline, scale: scale,
                                  showHeartRate: showHeartRate, showCalories: showCalories,
                                  showTextOutline: showTextOutline)
        case .summaryGrid:
            // 심박·칼로리 토글을 받지 않는다 — 이 스탬프는 격자를 채우는 게 목적이라
            // 있는 지표를 모두(최대 6칸) 보여준다.
            StampSummaryGridView(data: data, fill: fill, outline: outline, scale: scale,
                                 showTextOutline: showTextOutline)
        case .summaryGridPace:
            // 요약 그리드 그대로 + 아래에 구간별 세로 목록(km · 막대 · 페이스 · 심박)
            VStack(alignment: .leading, spacing: sz(10, scale)) {
                StampSummaryGridView(data: data, fill: fill, outline: outline, scale: scale,
                                     showTextOutline: showTextOutline)
                if let splits = data.splits, splits.count >= 2 {
                    StampSplitRowsView(rows: StampSplit.rows(splits), fill: fill, outline: outline,
                                       scale: scale, showTextOutline: showTextOutline)
                }
            }
        case .hud:
            StampHUDView(data: data, fill: fill, outline: outline, scale: scale,
                         showHeartRate: showHeartRate, showCalories: showCalories,
                         showTextOutline: showTextOutline, position: position)
        case .hrWave:
            StampHRWaveView(data: data, fill: fill, outline: outline, scale: scale,
                            showTextOutline: showTextOutline)
        case .hrZone:
            StampHRZoneView(data: data, fill: fill, outline: outline, scale: scale,
                            showTextOutline: showTextOutline)
        case .elevProfile:
            StampElevProfileView(data: data, fill: fill, outline: outline, scale: scale,
                                 showTextOutline: showTextOutline)
        case .cadenceEq:
            StampCadenceEqView(data: data, fill: fill, outline: outline, scale: scale,
                               showTextOutline: showTextOutline)
        case .placeHeadline:
            StampPlaceHeadlineView(data: data, fill: fill, outline: outline, scale: scale,
                                   showTextOutline: showTextOutline)
        case .routeHero:
            StampRouteHeroView(data: data, fill: fill, outline: outline, scale: scale,
                               showTextOutline: showTextOutline)
        case .routeSide:
            StampRouteSideView(data: data, fill: fill, outline: outline, scale: scale,
                               showHeartRate: showHeartRate, showCalories: showCalories,
                               showTextOutline: showTextOutline)
        }
    }
}

// MARK: - Passport Stamp

private struct StampPassportView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    var body: some View {
        VStack(spacing: 3 * scale) {
            Text(data.locationText)
                .font(.system(size: 8 * scale, weight: .semibold, design: .monospaced))
                .tracking(2)

            HStack(alignment: .lastTextBaseline, spacing: 2 * scale) {
                Text(data.distance)
                    .font(.system(size: 19 * scale, weight: .black))
                    .tracking(-1.5)
                Text(data.distanceUnit)
                    .font(.system(size: 9 * scale, weight: .bold, design: .monospaced))
            }

            Text("\(data.pace)  \(data.time)  \(data.dateText)")
                .font(.system(size: 8 * scale, weight: .medium, design: .monospaced))
        }
        .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 10 * scale)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(outline, lineWidth: 2)
        )
        .rotationEffect(.degrees(-7))
    }
}

// MARK: - Circle Badge

/// 서클 배지. 심박은 토글 없이 페이스 줄 다음에 항상 표시한다
/// (예전에는 토글을 켜면 원 전체가 심박 표시로 바뀌어 거리가 사라졌다).
private struct StampCircleBadgeView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    var body: some View {
        let diameter: CGFloat = 104 * scale

        ZStack {
            Circle()
                .stroke(outline, lineWidth: 2)

            VStack(spacing: 3 * scale) {
                HStack(alignment: .lastTextBaseline, spacing: 2 * scale) {
                    Text(data.distance)
                        .font(.system(size: 19 * scale, weight: .black))
                        .tracking(-1.5)
                    Text(data.distanceUnit)
                        .font(.system(size: 8 * scale, weight: .bold, design: .monospaced))
                }

                Text("KM · CERTIFIED")
                    .font(.system(size: 8 * scale, weight: .semibold, design: .monospaced))

                Text("\(data.pace)  ·  \(data.time)")
                    .font(.system(size: 8 * scale, weight: .medium, design: .monospaced))

                if let hr = data.heartRate {
                    Text("\(hr) BPM")
                        .font(.system(size: 8 * scale, weight: .semibold, design: .monospaced))
                }
            }
            .lineLimit(1)
            .fixedSize()
            .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(-8))
    }
}

// MARK: - Scoreboard

private struct StampScoreboardView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    var body: some View {
        VStack(spacing: 3 * scale) {
            Text("SCOREBOARD")
                .font(.system(size: 18 * scale, weight: .semibold, design: .monospaced))
                .tracking(2)
                .lineLimit(1).fixedSize()

            HStack(alignment: .lastTextBaseline, spacing: 2 * scale) {
                Text(data.distance)
                    .font(.system(size: 26 * scale, weight: .black))
                    .tracking(-1.5)
                Text(data.distanceUnit)
                    .font(.system(size: 10 * scale, weight: .bold, design: .monospaced))
                    .tracking(4)
            }

            // 세 지표는 한 줄. 크기 배율표가 스탬프를 목표 폭에 맞추므로 줄이 길수록 글자가 작아진다
            // — 자간을 0으로 두고 구분자도 한 칸씩만 써서 폭을 아낀다.
            // 심박은 토글 없이 항상 — 있으면 뒤에 붙는다.
            HStack(alignment: .lastTextBaseline, spacing: 2 * scale) {
                Text(data.heartRate.map { "\(data.time) · \(data.pace) · \($0)" }
                     ?? "\(data.time) · \(data.pace)")
                    .font(.system(size: 22 * scale, weight: .semibold, design: .monospaced))
                if data.heartRate != nil {
                    // 단위는 작게 — 한 줄 폭이 곧 글자 크기라 세 글자도 아깝다
                    Text("BPM")
                        .font(.system(size: 12 * scale, weight: .semibold, design: .monospaced))
                }
            }
            .lineLimit(1).fixedSize()
        }
        .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Labeled Rows

private struct StampLabeledRowsView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    let showHeartRate: Bool
    let showCalories: Bool
    var showTextOutline: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: sz(2, scale)) {
            metricRow(label: "DIST", value: data.distance, unit: data.distanceUnit)
            metricRow(label: "PACE", value: data.pace)
            metricRow(label: "TIME", value: data.time)
            if let footer = stampMetricFooter(data: data, hr: showHeartRate, cal: showCalories) {
                Text(footer)
                    .font(.system(size: sz(10, scale), weight: .bold))
                    .tracking(1.2)
                    .opacity(0.85)
            }
        }
        .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
    }

    private func metricRow(label: String, value: String, unit: String? = nil) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: sz(4, scale)) {
            Text(label)
                .font(.system(size: sz(10, scale), weight: .bold))
                .tracking(1.6)
                .opacity(0.85)
            Text(value)
                .font(.system(size: sz(22, scale), weight: .black))
                .tracking(-1.5)
            if let u = unit {
                Text(u)
                    .font(.system(size: sz(11, scale), weight: .bold))
                    .baselineOffset(sz(4, scale))
            }
        }
    }
}

// MARK: - Inline Triple (라벨 없는 가로 3열: 거리 · 페이스 · 시간)

private struct StampInlineTripleView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    let showHeartRate: Bool
    let showCalories: Bool
    var showTextOutline: Bool = true

    var body: some View {
        // ⚠ lineLimit(1) 필수 — 이 뷰는 StampCard에서 .fixedSize()로 감싸지는데,
        //   베이스라인 정렬 HStack + 중첩 HStack 조합에서 SwiftUI가 이상적 폭을 실제보다
        //   좁게 잡아 "10.0"이 "10." / "0"으로 줄바꿈되고 푸터(심박·칼로리)가 카드 밖으로
        //   밀려나갔다. 한 줄 고정으로 자연 폭을 유지한다.
        VStack(alignment: .leading, spacing: sz(3, scale)) {
            HStack(alignment: .lastTextBaseline, spacing: sz(8, scale)) {
                HStack(alignment: .lastTextBaseline, spacing: sz(2, scale)) {
                    Text(data.distance)
                        .font(.system(size: sz(22, scale), weight: .black))
                        .tracking(-1.5)
                        .lineLimit(1).fixedSize()
                    Text(data.distanceUnit)
                        .font(.system(size: sz(10, scale), weight: .bold))
                        .baselineOffset(sz(3, scale))
                        .lineLimit(1).fixedSize()
                }
                divider
                Text(data.pace)
                    .font(.system(size: sz(22, scale), weight: .black))
                    .tracking(-1.5)
                    .lineLimit(1).fixedSize()
                divider
                Text(data.time)
                    .font(.system(size: sz(22, scale), weight: .black))
                    .tracking(-1.5)
                    .lineLimit(1).fixedSize()
            }
            if let footer = stampMetricFooter(data: data, hr: showHeartRate, cal: showCalories) {
                Text(footer)
                    .font(.system(size: sz(10, scale), weight: .bold))
                    .tracking(1.2)
                    .lineLimit(1).fixedSize()
                    .opacity(0.85)
            }
        }
        .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
    }

    /// 열 구분: 얇은 세로선 (텍스트 아웃라인과 같은 색)
    private var divider: some View {
        Rectangle()
            .fill(outline.opacity(0.7))
            .frame(width: max(1, sz(1, scale)), height: sz(16, scale))
            .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - sz(2, scale) }
    }
}

// MARK: - Distance Hero

private struct StampDistanceHeroView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    let showHeartRate: Bool
    let showCalories: Bool
    var showTextOutline: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: sz(2, scale)) {
            Text("RUN")
                .font(.system(size: sz(10, scale), weight: .bold))
                .tracking(1.6)
                .opacity(0.85)
            Text(data.distance)
                .font(.system(size: sz(37, scale), weight: .black))
                .tracking(-1.5)
            Text("\(data.distanceUnit) · \(data.pace) · \(data.time)")
                .font(.system(size: sz(10, scale), weight: .bold))
                .tracking(1.2)
                .opacity(0.85)
            if let footer = stampMetricFooter(data: data, hr: showHeartRate, cal: showCalories) {
                Text(footer)
                    .font(.system(size: sz(10, scale), weight: .bold))
                    .tracking(1.2)
                    .opacity(0.85)
            }
        }
        .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
    }
}

// MARK: - Summary Grid (큰 기울임 거리 + 라벨 붙은 3열 지표 격자)

private struct StampSummaryGridView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    private struct Metric: Identifiable {
        let id = UUID()
        let value: String
        let unit: String?
        let label: String
        /// 숫자만 다른 색으로 — nil이면 스탬프 색 그대로
        var color: Color? = nil
    }

    /// 있는 데이터만 — 없는 지표는 칸을 만들지 않는다.
    ///
    /// 다른 스탬프와 달리 심박·칼로리 토글을 보지 않는다. 이 스탬프는 격자를 채우는 게 목적이라
    /// 기본값이 "있는 것 전부"(최대 6칸)다. 심박을 넣을지 말지는 나머지 스탬프에서 고른다.
    private var metrics: [Metric] {
        var m: [Metric] = [
            Metric(value: data.pace, unit: nil, label: "AVG PACE"),
            Metric(value: data.time, unit: nil, label: "TIME"),
        ]
        if let v = data.calories  { m.append(Metric(value: v, unit: "CAL", label: "CALORIES")) }
        if let v = data.elevGain  { m.append(Metric(value: v, unit: "M",   label: "ELEV GAIN")) }
        if let v = data.heartRate {
            m.append(Metric(value: v, unit: "BPM", label: data.heartRateLabel ?? "AVG HR",
                            color: data.heartRateColor))
        }
        if let v = data.cadence   { m.append(Metric(value: v, unit: "SPM", label: "CADENCE")) }
        return Array(m.prefix(6))
    }

    /// 열 폭은 고정 — 칸 수가 달라져도 위아래 행의 왼쪽 선이 맞는다.
    private var columnWidth: CGFloat { sz(54, scale) }
    private var columnGap: CGFloat { sz(8, scale) }

    var body: some View {
        let items = metrics
        let cols = min(3, max(1, items.count))
        let rows: [[Metric]] = stride(from: 0, to: items.count, by: 3).map {
            Array(items[$0 ..< min($0 + 3, items.count)])
        }
        VStack(alignment: .leading, spacing: sz(12, scale)) {
            VStack(alignment: .leading, spacing: sz(1, scale)) {
                Text(data.distance)
                    .font(.system(size: sz(52, scale), weight: .black).width(.compressed))
                    .italic()
                    .tracking(sz(-1, scale))
                    .lineLimit(1).fixedSize()
                Text(data.distanceUnit)
                    .font(.system(size: sz(8, scale), weight: .semibold))
                    .tracking(1.4)
                    .opacity(0.62)
                    .lineLimit(1).fixedSize()
            }
            VStack(alignment: .leading, spacing: sz(7, scale)) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(alignment: .top, spacing: columnGap) {
                        ForEach(rows[r]) { cell($0) }
                        // 마지막 행이 3칸을 못 채워도 폭이 줄지 않게 빈 칸을 채운다
                        if rows[r].count < cols {
                            ForEach(0 ..< (cols - rows[r].count), id: \.self) { _ in
                                Color.clear.frame(width: columnWidth, height: 1)
                            }
                        }
                    }
                }
            }
        }
        .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
    }

    @ViewBuilder
    private func cell(_ m: Metric) -> some View {
        VStack(alignment: .leading, spacing: sz(1, scale)) {
            HStack(alignment: .lastTextBaseline, spacing: sz(2, scale)) {
                Text(m.value)
                    .font(.system(size: sz(16, scale), weight: .black).width(.compressed))
                    .italic()
                    .foregroundStyle(m.color ?? fill)
                    .lineLimit(1).fixedSize()
                if let u = m.unit {
                    Text(u)
                        .font(.system(size: sz(8, scale), weight: .bold))
                        .lineLimit(1).fixedSize()
                }
            }
            Text(m.label)
                .font(.system(size: sz(7, scale), weight: .semibold))
                .tracking(0.9)
                .opacity(0.62)
                .lineLimit(1).fixedSize()
        }
        .frame(width: columnWidth, alignment: .leading)
    }
}

// MARK: - Split Rows (요약 그리드+페이스 — 구간마다 한 줄: km · 막대 · 페이스 · 심박)

private struct StampSplitRowsView: View {
    let rows: [StampSplit.Row]
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    /// 요약 그리드 3열 폭(54×3 + 8×2)과 같게 — 격자 왼쪽·오른쪽 선에 맞춘다.
    private var width: CGFloat { sz(178, scale) }
    private var kmW: CGFloat { sz(18, scale) }
    private var paceW: CGFloat { sz(32, scale) }   // 9pt 페이스가 칸을 넘치면 가운데로 밀려 열이 흔들린다
    private var hrW: CGFloat { sz(20, scale) }
    private var colGap: CGFloat { sz(5, scale) }
    private var rowH: CGFloat { sz(10, scale) }   // 페이스 9pt가 윗줄과 붙지 않게
    private var hasHR: Bool { rows.contains { $0.heartRate != nil } }
    private var barMax: CGFloat {
        width - kmW - paceW - colGap * 3 - (hasHR ? hrW + colGap : 0)
    }

    /// 막대 길이 비율 0.35~1.0 — 빠를수록 길다. 모두 같으면 0.7.
    private func ratio(_ pace: Double) -> CGFloat {
        let p = rows.map(\.paceSecPerKm)
        guard let lo = p.min(), let hi = p.max(), hi > lo else { return 0.7 }
        return CGFloat(0.35 + 0.65 * (hi - pace) / (hi - lo))
    }

    private var fastest: Double? { rows.map(\.paceSecPerKm).min() }

    private func kmLabel(_ km: Double) -> String {
        abs(km - km.rounded()) < 0.05 ? "\(Int(km.rounded()))" : String(format: "%.1f", km)
    }

    private func paceText(_ sec: Double) -> String {
        let t = Int(sec.rounded())
        return String(format: "%d'%02d\"", t / 60, t % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: sz(3, scale)) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    let r = rows[i]
                    HStack(spacing: colGap) {
                        Text(kmLabel(r.endKm))
                            .font(.system(size: sz(7, scale), weight: .semibold).monospacedDigit())
                            .opacity(0.62)
                            .frame(width: kmW, alignment: .leading)
                        // 가장 빠른 구간만 페이스 색(청록) — 어디서 빨랐는지 한눈에
                        Rectangle()
                            .fill(r.paceSecPerKm == fastest ? Theme.pace : fill.opacity(0.85))
                            .frame(width: barMax * ratio(r.paceSecPerKm), height: sz(5, scale))
                            .frame(width: barMax, alignment: .leading)
                        Text(paceText(r.paceSecPerKm))
                            .font(.system(size: sz(9, scale), weight: .black).width(.compressed).monospacedDigit())
                            .italic()
                            .fixedSize()
                            .frame(width: paceW, alignment: .trailing)
                        if hasHR {
                            Text(r.heartRate.map { "\($0)" } ?? "–")
                                .font(.system(size: sz(8, scale), weight: .semibold).monospacedDigit())
                                .opacity(0.62)
                                .fixedSize()
                                .frame(width: hrW, alignment: .trailing)
                        }
                    }
                    .lineLimit(1)
                    .frame(height: rowH)
                }
            }
            HStack(spacing: colGap) {
                Text("KM").frame(width: kmW, alignment: .leading)
                Spacer(minLength: 0)
                Text("PACE").frame(width: paceW, alignment: .trailing)
                if hasHR { Text("HR").frame(width: hrW, alignment: .trailing) }
            }
            .font(.system(size: sz(7, scale), weight: .semibold))
            .tracking(0.9)
            .lineLimit(1)
            .opacity(0.62)
        }
        .frame(width: width, alignment: .leading)
        .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
    }
}

// MARK: - HUD

private struct StampHUDView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    let showHeartRate: Bool
    let showCalories: Bool
    var showTextOutline: Bool = true
    /// 9셀 그리드에서 데이터 블록 배치 위치 (Canvas 브래킷은 항상 전체 프레임)
    var position: CardPosition = .center

    /// 심박 토글 + 심박 데이터 → 워치 스타일(LIVE 헤더, ♥심박·케이던스 줄). 구 "워치 HUD" 병합.
    private var liveMode: Bool { showHeartRate && data.heartRate != nil }

    var body: some View {
        ZStack(alignment: position.alignment) {
            // 네 모서리 브래킷
            BracketsShape(inset: sz(12, scale), bw: sz(14, scale), bh: sz(12, scale))
                .stroke(outline.opacity(0.9),
                        style: StrokeStyle(lineWidth: max(1, sz(1.5, scale)), lineCap: .square))

            // 데이터 블록 — position.alignment에 따라 배치됨
            VStack(spacing: sz(4, scale)) {
                if liveMode {
                    HStack(spacing: sz(3, scale)) {
                        Circle()
                            .fill(Color(hex: "22E07A"))
                            .frame(width: sz(5, scale), height: sz(5, scale))
                        Text("LIVE · TRACKING")
                            .font(.system(size: sz(9, scale), weight: .semibold, design: .monospaced))
                            .tracking(2)
                    }
                    .opacity(0.85)
                } else {
                    Text("● REC · TRACKING")
                        .font(.system(size: sz(9, scale), weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .opacity(0.85)
                }

                HStack(alignment: .lastTextBaseline, spacing: sz(2, scale)) {
                    Text(data.distance)
                        .font(.system(size: sz(23, scale), weight: .black))
                        .tracking(-1.5)
                    Text(data.distanceUnit)
                        .font(.system(size: sz(11, scale), weight: .bold))
                }

                Text("\(data.pace)   \(data.time)")
                    .font(.system(size: sz(11, scale), weight: .medium, design: .monospaced))

                if liveMode {
                    // 워치 스타일 한 줄: ♥심박  케이던스spm  (칼로리 토글 시 CAL 추가)
                    let parts: [String] = [
                        data.heartRate.map { "♥\($0)" },
                        data.cadence.map   { "\($0)spm" },
                        showCalories ? data.calories.map { "\($0)cal" } : nil
                    ].compactMap { $0 }
                    Text(parts.joined(separator: "  "))
                        .font(.system(size: sz(10, scale), weight: .bold, design: .monospaced))
                        .tracking(1)
                        .opacity(0.85)
                } else if let footer = stampMetricFooter(data: data, hr: false, cal: showCalories) {
                    Text(footer)
                        .font(.system(size: sz(10, scale), weight: .bold))
                        .tracking(1.2)
                        .opacity(0.85)
                }
            }
            .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
            .padding(sz(16, scale))
        }
    }
}

// MARK: - HR Wave

private struct StampHRWaveView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    private let hrRed = Color(hex: "FF2E2E")

    var body: some View {
        VStack(spacing: sz(4, scale)) {
            waveCanvas
                .frame(width: sz(120, scale), height: sz(30, scale))

            HStack(alignment: .lastTextBaseline, spacing: sz(3, scale)) {
                Text(data.heartRate ?? "—")
                    .font(.system(size: sz(28, scale), weight: .black))
                    .foregroundStyle(hrRed)
                VStack(alignment: .leading, spacing: sz(1, scale)) {
                    Text("BPM")
                        .font(.system(size: sz(8, scale), weight: .bold, design: .monospaced))
                        .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
                    if let max = data.heartRateMax {
                        Text("\(max) MAX")
                            .font(.system(size: sz(8, scale), weight: .medium, design: .monospaced))
                            .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
                    }
                }
            }

            Text("\(data.distance) \(data.distanceUnit) · \(data.pace)")
                .font(.system(size: sz(9, scale), weight: .medium, design: .monospaced))
                .tracking(1.2)
                .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
        }
    }

    private var waveCanvas: some View {
        WaveLineShape(series: data.hrSeries ?? defaultSeries)
            .stroke(Color(hex: "FF2E2E"),
                    style: StrokeStyle(lineWidth: max(1, sz(1.5, scale)), lineCap: .round, lineJoin: .round))
    }

    // ECG 톱니 더미 파형
    private var defaultSeries: [Double] {
        [0.5, 0.5, 0.5, 0.55, 0.85, 1.0, 0.08, 0.62, 0.68, 0.66,
         0.5, 0.5, 0.5, 0.55, 0.85, 1.0, 0.08, 0.62, 0.68, 0.66]
    }
}

// MARK: - HR Zone

private struct StampHRZoneView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    private let zoneOrange = Color(hex: "FF8A1F")

    var body: some View {
        VStack(spacing: sz(4, scale)) {
            Text("ZONE")
                .font(.system(size: sz(9, scale), weight: .bold, design: .monospaced))
                .tracking(2)
                .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)

            Text(data.hrZoneLabel ?? "Z—")
                .font(.system(size: sz(36, scale), weight: .black))
                .foregroundStyle(zoneOrange)

            // 5-bar zone gauge
            HStack(spacing: sz(3, scale)) {
                ForEach(0..<5, id: \.self) { i in
                    let isSel = i == (data.hrZoneIndex ?? -1)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isSel ? zoneOrange : Color.white.opacity(0.22))
                        .frame(width: sz(14, scale), height: sz(8, scale))
                }
            }

            let parts = [data.heartRate.map { "\($0) BPM" }, data.hrZoneName]
                .compactMap { $0 }
                .joined(separator: " · ")
            if !parts.isEmpty {
                Text(parts)
                    .font(.system(size: sz(9, scale), weight: .medium, design: .monospaced))
                    .tracking(1)
                    .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
            }
        }
    }
}

// MARK: - Elevation Profile

private struct StampElevProfileView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: sz(4, scale)) {
            elevCanvas
                .frame(width: sz(120, scale), height: sz(40, scale))

            HStack(alignment: .lastTextBaseline, spacing: sz(2, scale)) {
                Text("↑\(data.elevGain ?? "—")")
                    .font(.system(size: sz(20, scale), weight: .black))
                    .foregroundStyle(Color(hex: "C6FF00"))
                Text("M")
                    .font(.system(size: sz(9, scale), weight: .bold, design: .monospaced))
                    .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
            }

            Text("ELEV GAIN · \(data.distance) \(data.distanceUnit)")
                .font(.system(size: sz(9, scale), weight: .medium, design: .monospaced))
                .tracking(1.2)
                .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
        }
    }

    private var elevCanvas: some View {
        let series = data.elevSeries ?? defaultSeries
        let lime = Color(hex: "C6FF00")
        return ZStack {
            ElevFillShape(series: series).fill(lime.opacity(0.18))
            ElevLineShape(series: series)
                .stroke(lime, style: StrokeStyle(lineWidth: max(1, sz(1.5, scale)), lineCap: .round, lineJoin: .round))
        }
    }

    private var defaultSeries: [Double] {
        [0.10, 0.18, 0.32, 0.48, 0.65, 0.72, 0.60, 0.75, 0.80, 0.70, 0.62, 0.55]
    }
}

// MARK: - Cadence Equalizer

private struct StampCadenceEqView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    private let barHeights: [Double] = [0.4, 0.65, 0.85, 1.0, 0.9, 0.7, 0.88, 0.95, 0.75, 0.60, 0.50, 0.40]

    var body: some View {
        VStack(spacing: sz(4, scale)) {
            Text("CADENCE")
                .font(.system(size: sz(9, scale), weight: .bold, design: .monospaced))
                .tracking(2)
                .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)

            HStack(alignment: .lastTextBaseline, spacing: sz(2, scale)) {
                Text(data.cadence ?? "—")
                    .font(.system(size: sz(26, scale), weight: .black))
                Text("SPM")
                    .font(.system(size: sz(9, scale), weight: .bold, design: .monospaced))
            }
            .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)

            eqCanvas
                .frame(width: sz(84, scale), height: sz(22, scale))

            Text("\(data.distance) \(data.distanceUnit) · \(data.pace)")
                .font(.system(size: sz(9, scale), weight: .medium, design: .monospaced))
                .tracking(1.2)
                .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
        }
    }

    private var eqCanvas: some View {
        EQBarShape(barHeights: barHeights).fill(Color.white.opacity(0.82))
    }
}

// MARK: - Place Headline

private struct StampPlaceHeadlineView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    var body: some View {
        let name = (data.placeName ?? data.coordText ?? "UNKNOWN").uppercased()
        VStack(alignment: .leading, spacing: sz(3, scale)) {
            Text(name)
                .font(.system(size: sz(26, scale), weight: .black))
                .tracking(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            let region = [data.placeRegion, "KR"].compactMap { $0 }.joined(separator: " · ")
            if !region.isEmpty {
                Text(region)
                    .font(.system(size: sz(9, scale), weight: .bold, design: .monospaced))
                    .tracking(2)
                    .opacity(0.8)
            }

            HStack(alignment: .lastTextBaseline, spacing: sz(2, scale)) {
                Text(data.distance)
                    .font(.system(size: sz(20, scale), weight: .black))
                Text(data.distanceUnit)
                    .font(.system(size: sz(9, scale), weight: .bold))
            }

            Text("\(data.pace) · \(data.time)")
                .font(.system(size: sz(9, scale), weight: .medium, design: .monospaced))
                .tracking(1.2)
                .opacity(0.8)
        }
        .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
    }
}

// MARK: - Route Hero

private struct StampRouteHeroView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StampRouteArt(
                coords: data.routeCoordinates ?? [],
                lineWidth: max(1, sz(2.6, scale)),
                color: fill,
                casingColor: outline
            )
            .frame(width: sz(46, scale), height: sz(60, scale))
            .padding(.bottom, sz(7, scale))

            Text(data.distance)
                .font(.system(size: sz(38, scale), weight: .heavy))
                .tracking(-1.5)
                .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)

            Text("KM")
                .font(.system(size: sz(9, scale), weight: .bold))
                .tracking(1.6)
                .opacity(0.85)
                .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
                .padding(.top, sz(3, scale))

            HStack(alignment: .top, spacing: sz(20, scale)) {
                VStack(alignment: .leading, spacing: sz(1, scale)) {
                    Text(data.time)
                        .font(.system(size: sz(17, scale), weight: .heavy))
                        .tracking(-0.5)
                    Text("TIME")
                        .font(.system(size: sz(8, scale), weight: .bold))
                        .tracking(1.6)
                        .opacity(0.85)
                }
                VStack(alignment: .leading, spacing: sz(1, scale)) {
                    Text(data.pace)
                        .font(.system(size: sz(17, scale), weight: .heavy))
                        .tracking(-0.5)
                    Text("AVG PACE")
                        .font(.system(size: sz(8, scale), weight: .bold))
                        .tracking(1.6)
                        .opacity(0.85)
                }
                // 심박은 토글 없이 항상 — 있으면 페이스 옆 열로 붙는다.
                if let hr = data.heartRate {
                    VStack(alignment: .leading, spacing: sz(1, scale)) {
                        Text(hr)
                            .font(.system(size: sz(17, scale), weight: .heavy))
                            .tracking(-0.5)
                        Text("AVG HR")
                            .font(.system(size: sz(8, scale), weight: .bold))
                            .tracking(1.6)
                            .opacity(0.85)
                    }
                }
            }
            .lineLimit(1)
            .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
            .padding(.top, sz(8, scale))
        }
    }
}

// MARK: - Route Side

private struct StampRouteSideView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    let showHeartRate: Bool
    let showCalories: Bool
    var showTextOutline: Bool = true

    var body: some View {
        let isPortrait = StampRouteArt.isPortraitRoute(data.routeCoordinates ?? [])
        let art = StampRouteArt(
            coords: data.routeCoordinates ?? [],
            lineWidth: max(1, sz(2.6, scale)),
            color: fill,
            casingColor: outline
        )
        .frame(width: sz(44, scale), height: sz(70, scale))
        let hero = StampDistanceHeroView(data: data, fill: fill, outline: outline, scale: scale,
                                         showHeartRate: showHeartRate, showCalories: showCalories,
                                         showTextOutline: showTextOutline)
        if isPortrait {
            HStack(alignment: .center, spacing: sz(12, scale)) {
                hero
                art
            }
        } else {
            VStack(alignment: .leading, spacing: sz(8, scale)) {
                art
                hero
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let d = StampData.sample
    let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    ScrollView {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(StampTemplate.allCases) { template in
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.25))

                    StampCard(
                        data: d,
                        template: template,
                        colorMode: .brand,
                        position: .center,
                        sizeLevel: .medium,
                        isBrightBackground: false,
                        showHeartRate: true,
                        showCalories: true
                    )

                    VStack {
                        Spacer()
                        Text(template.displayName)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.bottom, 6)
                    }
                }
                .frame(height: template == .hud ? 240 : 200)
                .clipped()
            }
        }
        .padding()
    }
    .background(Color.black)
}

// MARK: - 자연 폭 측정 (DEBUG · 크기 규칙 상수표 작성용)
#if DEBUG
extension StampCard {
    /// scale 1에서 스탬프 콘텐츠의 자연 크기. 결과는 StampTemplate.naturalWidth 상수표에 반영한다.
    @MainActor
    static func measureNaturalSize(template: StampTemplate, data: StampData) -> CGSize {
        let card = StampCard(data: data, template: template, colorMode: .brand, position: .center,
                             sizeLevel: .xlarge, isBrightBackground: false,
                             showHeartRate: false, showCalories: false, showTextOutline: false)
        let view = card.stampContent(fill: .white, outline: .black, scale: 1.0).fixedSize()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage?.size ?? .zero
    }
}
#endif
