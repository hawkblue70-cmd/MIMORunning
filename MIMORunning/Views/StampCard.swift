// 스탬프 카드 렌더러. 미리보기와 영상 합성이 모두 이 뷰를 사용한다(렌더 경로 단일화).
// ⚠️ 스탬프 카드 전용. 다른 카드 코드 작성 금지.

import CoreLocation
import SwiftUI

// MARK: - StampData

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
        ]
    )
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

// 명시된 pt 크기는 medium(sizeLevel.scale == 0.8) 기준; 헬퍼로 레벨별 스케일.
private func sz(_ pt: CGFloat, _ scale: CGFloat) -> CGFloat { pt * scale / 0.8 }

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
        // 스탬프 전용 scale: 공유 TextSizeLevel보다 한 단계 작게 (소→0.50, 중→0.65, 대→0.80, 특대→1.00)
        let scale: CGFloat = {
            switch sizeLevel {
            case .small:  return 0.50
            case .medium: return 0.65
            case .large:  return 0.80
            case .xlarge: return 1.00
            }
        }()

        ZStack {
            if !renderOnlyText {
                if template.positionMode == .fixed {
                    stampContent(fill: fill, outline: outline, scale: scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // ImageRenderer에서 .frame(alignment:)의 bottom 앵커가 무시되는 SwiftUI 버그를
                    // 회피하기 위해 VStack/HStack/Spacer로 9격 위치 결정.
                    // 상단: top Spacer 없음, 하단: bottom Spacer 없음 (Spacer가 공간을 채움).
                    let stampPadded = stampContent(fill: fill, outline: outline, scale: scale)
                        .padding(EdgeInsets(
                            top: position.isTop ? wordmarkTopInset : 12,
                            leading: 12, bottom: 12, trailing: 12))
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
                let textPadded = textOverlay
                    .padding(EdgeInsets(
                        top: stampTextPosition.isTop ? wordmarkTopInset : 14,
                        leading: 14, bottom: 14, trailing: 14))
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
        case .receipt:
            StampReceiptView(data: data, fill: fill, outline: outline, scale: scale,
                             showCalories: showCalories, showTextOutline: showTextOutline)
        case .scoreboard:
            StampScoreboardView(data: data, fill: fill, outline: outline, scale: scale,
                                showTextOutline: showTextOutline)
        case .labeledRows:
            StampLabeledRowsView(data: data, fill: fill, outline: outline, scale: scale,
                                 showHeartRate: showHeartRate, showCalories: showCalories,
                                 showTextOutline: showTextOutline)
        case .verticalLabel:
            StampVerticalLabelView(data: data, fill: fill, outline: outline, scale: scale,
                                   showHeartRate: showHeartRate, showCalories: showCalories,
                                   showTextOutline: showTextOutline)
        case .distanceHero:
            StampDistanceHeroView(data: data, fill: fill, outline: outline, scale: scale,
                                  showHeartRate: showHeartRate, showCalories: showCalories,
                                  showTextOutline: showTextOutline)
        case .mixedAlign:
            StampMixedAlignView(data: data, fill: fill, outline: outline, scale: scale,
                                showHeartRate: showHeartRate, showCalories: showCalories,
                                showTextOutline: showTextOutline)
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
        case .vitals:
            StampVitalsView(data: data, fill: fill, outline: outline, scale: scale,
                            showTextOutline: showTextOutline)
        case .hrBadge:
            StampHRBadgeView(data: data, fill: fill, outline: outline, scale: scale,
                             showTextOutline: showTextOutline)
        case .watchHud:
            StampWatchHUDView(data: data, fill: fill, outline: outline, scale: scale,
                              showTextOutline: showTextOutline)
        case .placeHeadline:
            StampPlaceHeadlineView(data: data, fill: fill, outline: outline, scale: scale,
                                   showTextOutline: showTextOutline)
        case .pinInline:
            StampPinInlineView(data: data, fill: fill, outline: outline, scale: scale,
                               showTextOutline: showTextOutline)
        case .routeHero:
            StampRouteHeroView(data: data, fill: fill, outline: outline, scale: scale,
                               showTextOutline: showTextOutline)
        case .routeRows:
            StampRouteRowsView(data: data, fill: fill, outline: outline, scale: scale,
                               showHeartRate: showHeartRate, showCalories: showCalories,
                               showTextOutline: showTextOutline)
        case .routeVertical:
            StampRouteVerticalView(data: data, fill: fill, outline: outline, scale: scale,
                                   showHeartRate: showHeartRate, showCalories: showCalories,
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
            }
            .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(-8))
    }
}

// MARK: - Receipt

private struct StampReceiptView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    let showCalories: Bool
    var showTextOutline: Bool = true

    var body: some View {
        VStack(spacing: 4 * scale) {
            Text("RUN RECEIPT")
                .font(.system(size: 11 * scale, weight: .bold, design: .monospaced))
                .tracking(2)
                .frame(maxWidth: .infinity, alignment: .center)

            dashedLine

            receiptRow(label: "DISTANCE", value: "\(data.distance) \(data.distanceUnit)")
            receiptRow(label: "PACE",     value: data.pace)
            receiptRow(label: "TIME",     value: data.time)
            if showCalories, let cal = data.calories {
                receiptRow(label: "CALS", value: "\(cal) KCAL")
            }

            dashedLine

            if showCalories, let cal = data.calories {
                receiptRow(label: "TOTAL", value: "\(cal) KCAL", bold: true)
            } else {
                receiptRow(label: "TOTAL", value: data.time, bold: true)
            }
        }
        .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 8 * scale)
        .frame(maxWidth: .infinity)
    }

    private var dashedLine: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(fill, style: StrokeStyle(lineWidth: 1, dash: [4 * scale, 3 * scale]))
        }
        .frame(height: 1)
    }

    private func receiptRow(label: String, value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11 * scale, weight: .regular, design: .monospaced))
            Spacer()
            Text(value)
                .font(.system(size: 11 * scale, weight: bold ? .bold : .regular,
                              design: .monospaced))
        }
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
                .font(.system(size: 9 * scale, weight: .semibold, design: .monospaced))
                .tracking(3)

            HStack(alignment: .lastTextBaseline, spacing: 2 * scale) {
                Text(data.distance)
                    .font(.system(size: 26 * scale, weight: .black))
                    .tracking(-1.5)
                Text(data.distanceUnit)
                    .font(.system(size: 10 * scale, weight: .bold, design: .monospaced))
                    .tracking(4)
            }

            Text("\(data.time)  ·  \(data.pace)")
                .font(.system(size: 11 * scale, weight: .semibold, design: .monospaced))
                .tracking(2)
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

// MARK: - Vertical Label

private struct StampVerticalLabelView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    let showHeartRate: Bool
    let showCalories: Bool
    var showTextOutline: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: sz(9, scale)) {
            // 세로 "RUNNING": fixedSize → rotationEffect → frame으로 레이아웃 프레임 교체
            Text("RUNNING")
                .font(.system(size: sz(10, scale), weight: .bold))
                .tracking(3)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: sz(13, scale), height: sz(58, scale))

            VStack(alignment: .leading, spacing: sz(2, scale)) {
                HStack(alignment: .lastTextBaseline, spacing: sz(2, scale)) {
                    Text(data.distance)
                        .font(.system(size: sz(23, scale), weight: .black))
                        .tracking(-1.5)
                    Text(data.distanceUnit)
                        .font(.system(size: sz(11, scale), weight: .bold))
                }
                Text(data.pace)
                    .font(.system(size: sz(23, scale), weight: .black))
                    .tracking(-1.5)
                Text(data.time)
                    .font(.system(size: sz(23, scale), weight: .black))
                    .tracking(-1.5)
                if let footer = stampMetricFooter(data: data, hr: showHeartRate, cal: showCalories) {
                    Text(footer)
                        .font(.system(size: sz(10, scale), weight: .bold))
                        .tracking(1.2)
                        .opacity(0.85)
                }
            }
        }
        .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
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

// MARK: - Mixed Align

private struct StampMixedAlignView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    let showHeartRate: Bool
    let showCalories: Bool
    var showTextOutline: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: sz(4, scale)) {
            Text("RUN")
                .font(.system(size: sz(10, scale), weight: .bold))
                .tracking(1.6)
                .opacity(0.85)

            HStack(alignment: .lastTextBaseline, spacing: sz(3, scale)) {
                Text(data.distance)
                    .font(.system(size: sz(26, scale), weight: .black))
                    .tracking(-1.5)
                Text(data.distanceUnit)
                    .font(.system(size: sz(11, scale), weight: .bold))
            }

            VStack(alignment: .trailing, spacing: sz(1, scale)) {
                Text(data.pace)
                    .font(.system(size: sz(18, scale), weight: .black))
                    .tracking(-1.5)
                Text(data.time)
                    .font(.system(size: sz(18, scale), weight: .black))
                    .tracking(-1.5)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

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

    var body: some View {
        ZStack(alignment: position.alignment) {
            // 네 모서리 브래킷
            BracketsShape(inset: sz(12, scale), bw: sz(14, scale), bh: sz(12, scale))
                .stroke(outline.opacity(0.9),
                        style: StrokeStyle(lineWidth: max(1, sz(1.5, scale)), lineCap: .square))

            // 데이터 블록 — position.alignment에 따라 배치됨
            VStack(spacing: sz(4, scale)) {
                Text("● REC · TRACKING")
                    .font(.system(size: sz(9, scale), weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .opacity(0.85)

                HStack(alignment: .lastTextBaseline, spacing: sz(2, scale)) {
                    Text(data.distance)
                        .font(.system(size: sz(23, scale), weight: .black))
                        .tracking(-1.5)
                    Text(data.distanceUnit)
                        .font(.system(size: sz(11, scale), weight: .bold))
                }

                Text("\(data.pace)   \(data.time)")
                    .font(.system(size: sz(11, scale), weight: .medium, design: .monospaced))

                if let footer = stampMetricFooter(data: data, hr: showHeartRate, cal: showCalories) {
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

// MARK: - Vitals Panel

private struct StampVitalsView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: sz(3, scale)) {
            Text("▓ VITALS ▓")
                .font(.system(size: sz(9, scale), weight: .bold, design: .monospaced))
                .tracking(2)
                .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)

            Rectangle()
                .fill(outline.opacity(0.35))
                .frame(height: 0.5)

            if let hr = data.heartRate {
                vitalsRow("HR", value: "\(hr) BPM")
            }
            if let cad = data.cadence {
                vitalsRow("CAD", value: "\(cad) SPM")
            }
            if let elev = data.elevGain {
                vitalsRow("ELEV", value: "↑\(elev) M")
            }
            vitalsRow("DIST", value: "\(data.distance) \(data.distanceUnit)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func vitalsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: sz(9, scale), weight: .bold, design: .monospaced))
                .tracking(1.5)
                .opacity(0.7)
                .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
            Spacer()
            Text(value)
                .font(.system(size: sz(9, scale), weight: .medium, design: .monospaced))
                .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
        }
    }
}

// MARK: - HR Badge (Circle)

private struct StampHRBadgeView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    var body: some View {
        let diameter: CGFloat = sz(104, scale)
        ZStack {
            Circle()
                .stroke(outline, lineWidth: 2)

            VStack(spacing: sz(2, scale)) {
                Image(systemName: "heart.fill")
                    .font(.system(size: sz(14, scale)))
                    .foregroundStyle(Color(hex: "FF2E2E"))

                Text(data.heartRate ?? "—")
                    .font(.system(size: sz(22, scale), weight: .black))
                    .foregroundStyle(Color(hex: "FF2E2E"))

                Text("BPM · \(data.distance) \(data.distanceUnit)")
                    .font(.system(size: sz(8, scale), weight: .medium, design: .monospaced))
                    .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
            }
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(-8))
    }
}

// MARK: - Watch HUD (isVideoOnly, fixed)

private struct StampWatchHUDView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // 상단 바
            HStack(spacing: sz(4, scale)) {
                Text("MIMO WATCH")
                    .font(.system(size: sz(8, scale), weight: .black, design: .monospaced))
                    .tracking(1.5)
                    .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
                Spacer()
                HStack(spacing: sz(3, scale)) {
                    Circle()
                        .fill(Color(hex: "22E07A"))
                        .frame(width: sz(5, scale), height: sz(5, scale))
                    Text("LIVE")
                        .font(.system(size: sz(8, scale), weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "22E07A"))
                }
            }
            .padding(.horizontal, sz(14, scale))
            .padding(.top, sz(18, scale))

            Spacer()

            // 거리 메인
            HStack(alignment: .lastTextBaseline, spacing: sz(2, scale)) {
                Text(data.distance)
                    .font(.system(size: sz(34, scale), weight: .black))
                    .tracking(-1.5)
                Text(data.distanceUnit)
                    .font(.system(size: sz(12, scale), weight: .bold))
            }
            .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)

            Spacer()

            // 하단 메트릭 한 줄
            let parts: [String] = [
                data.heartRate.map { "♥\($0)" },
                data.cadence.map   { "\($0)spm" },
                data.pace,
                data.time
            ].compactMap { $0 }

            Text(parts.joined(separator: "  "))
                .font(.system(size: sz(9, scale), weight: .medium, design: .monospaced))
                .tracking(1)
                .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
                .padding(.horizontal, sz(14, scale))
                .padding(.bottom, sz(18, scale))
        }
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

// MARK: - Pin Inline

private struct StampPinInlineView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    var body: some View {
        let name = (data.placeName ?? data.coordText ?? "UNKNOWN").uppercased()
        VStack(alignment: .leading, spacing: sz(3, scale)) {
            Text("📍 \(name)  \(data.distance)\(data.distanceUnit)")
                .font(.system(size: sz(14, scale), weight: .black))
                .tracking(-0.5)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text("\(data.pace) · \(data.time)")
                .font(.system(size: sz(10, scale), weight: .medium, design: .monospaced))
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
            }
            .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
            .padding(.top, sz(8, scale))
        }
    }
}

// MARK: - Route Rows

private struct StampRouteRowsView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    let showHeartRate: Bool
    let showCalories: Bool
    var showTextOutline: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StampRouteArt(
                coords: data.routeCoordinates ?? [],
                lineWidth: max(1, sz(2.4, scale)),
                color: fill,
                casingColor: outline
            )
            .frame(width: sz(34, scale), height: sz(44, scale))
            .padding(.bottom, sz(7, scale))

            StampLabeledRowsView(data: data, fill: fill, outline: outline, scale: scale,
                                 showHeartRate: showHeartRate, showCalories: showCalories,
                                 showTextOutline: showTextOutline)
        }
    }
}

// MARK: - Route Vertical

private struct StampRouteVerticalView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    let showHeartRate: Bool
    let showCalories: Bool
    var showTextOutline: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StampRouteArt(
                coords: data.routeCoordinates ?? [],
                lineWidth: max(1, sz(2.4, scale)),
                color: fill,
                casingColor: outline
            )
            .frame(width: sz(34, scale), height: sz(42, scale))
            .padding(.bottom, sz(7, scale))

            StampVerticalLabelView(data: data, fill: fill, outline: outline, scale: scale,
                                   showHeartRate: showHeartRate, showCalories: showCalories,
                                   showTextOutline: showTextOutline)
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
