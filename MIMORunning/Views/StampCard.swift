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

    /// 촘촘한 묶음 — 15km 이하 1km, 30km 이하 2km, 그 이상 3km (줄 수 ≈ 15 이하).
    /// 요약 그리드+페이스+심박: 심박 곡선까지 붙어 세로가 길어 줄을 더 줄인다.
    static func compactBucketKm(totalKm: Double) -> Int {
        totalKm > 30 ? 3 : totalKm > 15 ? 2 : 1
    }

    /// 스플릿을 묶어 줄로 — 페이스는 합친 시간/거리, 심박은 심박 있는 구간의 시간 가중 평균.
    static func rows(_ splits: [StampSplit], bucket: (Double) -> Int = bucketKm(totalKm:)) -> [Row] {
        let total = splits.reduce(0) { $0 + $1.distanceM } / 1000
        let n = bucket(total)
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
    // 날씨·러닝화 — 플레이서블 스탬프 정보 줄 (없으면 그 항목만 생략)
    var weatherIcon: String?     = nil   // SF Symbol
    var weatherText: String?     = nil   // "18°C"
    var shoeName: String?        = nil
    /// 대회명 — 대회 확정 + 대회 칩 ON일 때만. 좌측 상단 로고 아래 뱃지(`StampHeaderMark`)
    var raceName: String?        = nil
    /// 심박 곡선(bpm) — 다듬고 줄인 값(`StampHRChart.prepare`). 요약 그리드+심박. 부족하면 그 스탬프를 고를 수 없다
    var hrSamples: [Double]?     = nil

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
            .map { StampSplit(distanceM: 1000, duration: $0.0, heartRate: $0.1) },
        weatherIcon: "sun.max",
        weatherText: "18°C",
        shoeName: "Pegasus 41",
        hrSamples: (0..<120).map { i in
            let t = Double(i) / 119
            return 128 + 18 * t + 4 * sin(t * 40) - (i < 6 ? Double(6 - i) * 5 : 0)
        }
    )
}

// MARK: - 날짜·시간 라벨 (워드마크 줄 오른쪽 · 스토리/영상/슬라이드/경로 영상 공용)

/// 스탬프 카드의 날짜·시간 라벨. `StampPhotoConfig.showDate`가 켜져 있을 때만 배치한다.
/// 스탬프 카드 좌측 상단 머리 — MIMO 워드마크 + (대회명 있으면) 대회 뱃지. 애슬레틱 카드와 같은 배치(로고 아래 6pt).
/// 스탬프의 모든 경로(사진·슬라이드·영상·경로 영상, 미리보기·출력)가 **이 뷰 하나만** 쓴다(§5.8).
/// 문구·스탬프가 뱃지를 덮지 않도록 각 경로의 위 여백에 `extraTopInset`을 더한다.
struct StampHeaderMark: View {
    let raceName: String?
    var onLight: Bool = false

    static let badgeGap: CGFloat = 6
    /// RaceBadge 한 줄(10pt bold) 높이 + 여유
    static let badgeHeight: CGFloat = 14

    /// 대회 뱃지가 있을 때 문구·스탬프를 아래로 미는 양
    static func extraTopInset(_ raceName: String?) -> CGFloat {
        raceName == nil ? 0 : badgeGap + badgeHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.badgeGap) {
            MIMOWordmark(size: 11, onMediaCard: true)
            if let r = raceName { RaceBadge(name: r, onLight: onLight) }
        }
    }
}

struct StampDateLabel: View {
    let date: Date
    /// 흰 배경(사진 없는 스탬프 카드) — 검은 글자, 그림자 없음
    var onLight: Bool = false
    var body: some View {
        Text(StampDateLabel.string(for: date))
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(onLight ? Color.black : Color.white)
            .shadow(color: .black.opacity(onLight ? 0 : 0.4), radius: 2, x: 0, y: 1)
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

        // 대회 뱃지가 로고 아래에 붙으면 그만큼 위 여백을 늘린다 — 문구·스탬프가 뱃지를 덮지 않게
        let topInset = wordmarkTopInset + StampHeaderMark.extraTopInset(data.raceName)

        ZStack {
            if !renderOnlyText {
                if template.positionMode == .fixed {
                    stampContent(fill: fill, outline: outline, scale: scale, topClearance: topInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if template.fitsCardHeight {
                    fittedTallStamp(fill: fill, outline: outline, scale: scale, topInset: topInset)
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
                            top: position.isTop ? topInset : 12,
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
                        top: stampTextPosition.isTop ? topInset : 14,
                        leading: textSideInset, bottom: 14, trailing: textSideInset))
                VStack(spacing: 0) {
                    if !stampTextPosition.isTop    { Spacer(minLength: 0) }
                    textPadded
                    if !stampTextPosition.isBottom { Spacer(minLength: 0) }
                }
            }
        }
    }

    /// 세로로 긴 스탬프 — 위(로고 아래)·아래 여백 안에 들어가는 가장 큰 배율로 그린다.
    /// 배율표 값부터 5%씩 줄여 가며 ViewThatFits가 처음 들어가는 것을 고른다(레이아웃만이라 ImageRenderer에서도 같다).
    /// 들어갈 높이를 통째로 잡고 그 안에서 위·가운데·아래로 정렬하므로 9칸 위치는 그대로 따른다.
    private func fittedTallStamp(fill: Color, outline: Color, scale: CGFloat, topInset: CGFloat) -> some View {
        let sideInset = 14 + MIMOWordmark.inkLeadingInset(size: 11)
        let vAlign: VerticalAlignment = position.isTop ? .top : position.isBottom ? .bottom : .center
        let candidates = (0...10).map { scale * (1 - 0.05 * CGFloat($0)) }   // 100% → 50%
        return GeometryReader { geo in
            let avail = max(0, geo.size.height - topInset - 12)
            HStack(spacing: 0) {
                if !position.isLeading { Spacer(minLength: 0) }
                ViewThatFits(in: .vertical) {
                    ForEach(candidates.indices, id: \.self) { i in
                        stampContent(fill: fill, outline: outline, scale: candidates[i])
                            .fixedSize()
                    }
                }
                .frame(height: avail, alignment: Alignment(horizontal: .leading, vertical: vAlign))
                if !position.isTrailing { Spacer(minLength: 0) }
            }
            .padding(EdgeInsets(top: topInset, leading: sideInset, bottom: 12, trailing: sideInset))
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
    private func stampContent(fill: Color, outline: Color, scale: CGFloat, topClearance: CGFloat = 0) -> some View {
        switch template {
        case .passportStamp:
            StampPassportView(data: data, fill: fill, outline: outline, scale: scale,
                              showTextOutline: showTextOutline)
        case .placeable:
            StampPlaceableView(data: data, fill: fill, outline: outline, scale: scale,
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
        case .summaryGridPaceHR:
            // 요약 그리드 + 구간 목록(15·30km 묶음) + 심박 곡선 — 세 스탬프의 같은 부품을 그대로 쌓는다
            VStack(alignment: .leading, spacing: sz(10, scale)) {
                StampSummaryGridView(data: data, fill: fill, outline: outline, scale: scale,
                                     showTextOutline: showTextOutline)
                if let splits = data.splits, splits.count >= 2 {
                    StampSplitRowsView(rows: StampSplit.rows(splits, bucket: StampSplit.compactBucketKm(totalKm:)),
                                       fill: fill, outline: outline,
                                       scale: scale, showTextOutline: showTextOutline)
                }
                if let hr = data.hrSamples, hr.count >= StampHRChart.minSamples {
                    StampHRChartView(samples: hr, timeText: data.time, fill: fill, outline: outline,
                                     scale: scale, showTextOutline: showTextOutline)
                }
            }
        case .summaryGridHR:
            // 요약 그리드 그대로 + 아래에 심박 곡선(최저·평균·최고 라벨, 평균 점선)
            VStack(alignment: .leading, spacing: sz(10, scale)) {
                StampSummaryGridView(data: data, fill: fill, outline: outline, scale: scale,
                                     showTextOutline: showTextOutline)
                if let hr = data.hrSamples, hr.count >= StampHRChart.minSamples {
                    StampHRChartView(samples: hr, timeText: data.time, fill: fill, outline: outline,
                                     scale: scale, showTextOutline: showTextOutline)
                }
            }
        case .hud:
            StampHUDView(data: data, fill: fill, outline: outline, scale: scale,
                         showHeartRate: showHeartRate, showCalories: showCalories,
                         showTextOutline: showTextOutline, position: position,
                         topClearance: topClearance)
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

// MARK: - Placeable (삭제된 플레이서블 카드의 데이터 블록을 스탬프로 — 라벨 위 값: 거리·시간·페이스 + 날씨·러닝화)

private struct StampPlaceableView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    /// 러닝화 이름이 길면 스탬프 폭을 밀어내므로 18자에서 자른다
    private var shoe: String? {
        guard let s = data.shoeName, !s.isEmpty else { return nil }
        return s.count > 18 ? String(s.prefix(17)) + "…" : s
    }

    private var route: [CLLocationCoordinate2D] { data.routeCoordinates ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: sz(8, scale)) {
            // 기록 3줄 + 오른쪽 경로 선(경로가 있을 때만) — 플레이서블 카드의 "지표 반대편 경로"를 한 덩어리로
            HStack(alignment: .center, spacing: sz(14, scale)) {
                VStack(alignment: .leading, spacing: sz(8, scale)) {
                    row(label: "DIST", value: data.distance, unit: data.distanceUnit.lowercased())
                    row(label: "TIME", value: data.time)
                    row(label: "PACE", value: data.pace, unit: "/km")
                }
                if route.count >= 2 {
                    let portrait = StampRouteArt.isPortraitRoute(route)
                    StampRouteArt(coords: route, lineWidth: max(1, sz(2.2, scale)),
                                  color: fill, casingColor: outline)
                        .frame(width: sz(portrait ? 56 : 72, scale), height: sz(portrait ? 90 : 60, scale))
                }
            }
            if data.weatherText != nil || shoe != nil {
                HStack(spacing: sz(4, scale)) {
                    if let t = data.weatherText {
                        if let icon = data.weatherIcon {
                            Image(systemName: icon).font(.system(size: sz(8, scale)))
                        }
                        Text(t)
                    }
                    if data.weatherText != nil, shoe != nil { Text("·") }
                    if let shoe { Text(shoe) }
                }
                .font(.system(size: sz(9, scale), weight: .medium))
                .opacity(0.85)
                .lineLimit(1).fixedSize()
            }
        }
        .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
    }

    private func row(label: String, value: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: sz(9, scale), weight: .semibold))
                .fontWidth(.condensed)
                .tracking(1.5)
                .lineLimit(1).fixedSize()
            HStack(alignment: .lastTextBaseline, spacing: sz(3, scale)) {
                Text(value)
                    .font(.system(size: sz(20, scale), weight: .heavy).italic().monospacedDigit())
                    .fontWidth(.condensed)
                    .lineLimit(1).fixedSize()
                if let unit {
                    Text(unit)
                        .font(.system(size: sz(11, scale), weight: .semibold).italic())
                        .fontWidth(.condensed)
                        .opacity(0.70)
                        .lineLimit(1).fixedSize()
                }
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

    /// 거리 숫자·라벨(KM·AVG PACE·TIME…) — 스탬프 색, 라벨은 굵게 100%(2026-10-06: 62% 흐림이라 사진 위에서 묻혔다).
    /// 한때 흰색 고정이었으나 색상 칩(잉크·라임·레드)이 이 부분에 안 먹어 스탬프 색으로 되돌렸다(2026-10-07).
    private var labelColor: Color { fill }

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
            // 심박 숫자는 심박 빨강(지표 의미색) — 경로 영상은 그 시점 존 색이 우선
            m.append(Metric(value: v, unit: "BPM", label: data.heartRateLabel ?? "AVG HR",
                            color: data.heartRateColor ?? Theme.heartRate))
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
                    .foregroundStyle(labelColor)
                    .lineLimit(1).fixedSize()
                Text(data.distanceUnit)
                    .font(.system(size: sz(8, scale), weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(labelColor)
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
                .font(.system(size: sz(7, scale), weight: .bold))
                .tracking(0.9)
                .foregroundStyle(labelColor)
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

    /// 머리(KM·PACE·HR)·km 열 — 스탬프 색 굵게 100%(색상 칩을 따른다). 구간 심박 숫자는 심박 빨강
    private var labelColor: Color { fill }

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
                            .font(.system(size: sz(7, scale), weight: .bold).monospacedDigit())
                            .foregroundStyle(labelColor)
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
                                .font(.system(size: sz(8, scale), weight: .bold).monospacedDigit())
                                .foregroundStyle(Theme.heartRate)
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
            .font(.system(size: sz(7, scale), weight: .bold))
            .tracking(0.9)
            .lineLimit(1)
            .foregroundStyle(labelColor)
        }
        .frame(width: width, alignment: .leading)
        .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
    }
}

// MARK: - HR Chart (요약 그리드+심박 — 실제 심박 곡선 · 최저/평균/최고 · 평균 점선)

enum StampHRChart {
    /// 이보다 적으면 곡선이 아니라 몇 개 점이라 스탬프를 고를 수 없다.
    static let minSamples = 30
    /// 그리는 점 수 — 178pt 폭에 이 정도면 촘촘하면서 가볍다.
    static let points = 120
    /// 이동평균 창(초) — 원시 샘플의 계단·튐을 다듬는다(작은 크기에서 지저분해 보이지 않게).
    static let smoothingWindow: TimeInterval = 15

    /// (경과 초, bpm) → 15초 이동평균 → 시간축 균등 120구간 평균. 샘플이 적으면 nil.
    static func prepare(_ samples: [(offset: TimeInterval, bpm: Int)]) -> [Double]? {
        let s = samples.sorted { $0.offset < $1.offset }
        guard s.count >= minSamples, let t0 = s.first?.offset, let t1 = s.last?.offset, t1 > t0 else { return nil }
        // 이동평균 (두 포인터)
        var smoothed: [(t: TimeInterval, v: Double)] = []
        smoothed.reserveCapacity(s.count)
        var lo = 0, sum = 0.0
        for hi in s.indices {
            sum += Double(s[hi].bpm)
            while s[hi].offset - s[lo].offset > smoothingWindow { sum -= Double(s[lo].bpm); lo += 1 }
            smoothed.append((s[hi].offset, sum / Double(hi - lo + 1)))
        }
        // 시간축 균등 구간 평균 — 빈 구간은 앞 값을 잇는다
        let span = t1 - t0
        var buckets = [Double](repeating: 0, count: points)
        var counts  = [Int](repeating: 0, count: points)
        for p in smoothed {
            let i = min(points - 1, Int((p.t - t0) / span * Double(points)))
            buckets[i] += p.v; counts[i] += 1
        }
        var out: [Double] = []
        var last = smoothed[0].v
        for i in 0..<points {
            if counts[i] > 0 { last = buckets[i] / Double(counts[i]) }
            out.append(last)
        }
        return out
    }
}

private struct HRLineShape: Shape {
    let values: [Double]
    let lo: Double
    let hi: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard values.count > 1, hi > lo else { return p }
        for (i, v) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = rect.maxY - rect.height * CGFloat((v - lo) / (hi - lo))
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

private struct HRLevelShape: Shape {
    let fraction: CGFloat   // 0 = 아래, 1 = 위
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.maxY - rect.height * fraction
        p.move(to: CGPoint(x: rect.minX, y: y))
        p.addLine(to: CGPoint(x: rect.maxX, y: y))
        return p
    }
}

private struct StampHRChartView: View {
    let samples: [Double]
    let timeText: String
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    /// 요약 그리드 3열 폭과 같게 (StampSplitRowsView와 같은 값)
    private var width: CGFloat { sz(178, scale) }
    private var chartH: CGFloat { sz(52, scale) }
    private var labelW: CGFloat { sz(16, scale) }
    private var gap: CGFloat { sz(4, scale) }

    private var minV: Double { samples.min() ?? 0 }
    private var maxV: Double { samples.max() ?? 0 }
    private var avgV: Double { samples.reduce(0, +) / Double(max(1, samples.count)) }
    /// 위아래 6% 여유 — 선이 테두리에 붙지 않게
    private var lo: Double { minV - (maxV - minV) * 0.06 }
    private var hi: Double { maxV + (maxV - minV) * 0.06 }
    private func frac(_ v: Double) -> CGFloat { hi > lo ? CGFloat((v - lo) / (hi - lo)) : 0.5 }
    /// 범례(세로축 숫자·HR·시간) — 스탬프 색 굵게 100%(색상 칩을 따른다). 곡선만 심박 빨강
    private var legend: Color { fill }

    private func yLabel(_ v: Double) -> some View {
        Text("\(Int(v.rounded()))")
            .font(.system(size: sz(7, scale), weight: .bold).monospacedDigit())
            .fixedSize()
            .frame(width: labelW, alignment: .trailing)
            .frame(height: sz(8, scale))
            .offset(y: chartH * (1 - frac(v)) - sz(4, scale))   // 라벨 가운데를 그 값 높이에
    }

    var body: some View {
        // 평균 라벨이 최저·최고 라벨과 겹치면 숨긴다(점선은 그대로)
        let avgGap = min(frac(maxV) - frac(avgV), frac(avgV) - frac(minV)) * chartH
        let showAvgLabel = avgGap >= sz(8, scale)
        VStack(alignment: .leading, spacing: sz(3, scale)) {
            HStack(alignment: .top, spacing: gap) {
                ZStack(alignment: .topTrailing) {
                    yLabel(maxV)
                    if showAvgLabel { yLabel(avgV) }
                    yLabel(minV)
                }
                .frame(width: labelW, height: chartH, alignment: .topTrailing)
                .stampTextOutline(show: showTextOutline, fill: legend, outline: outline)

                ZStack {
                    HRLevelShape(fraction: frac(avgV))
                        .stroke(fill.opacity(0.55),
                                style: StrokeStyle(lineWidth: max(0.5, sz(0.8, scale)), dash: [sz(2, scale), sz(2, scale)]))
                    HRLineShape(values: samples, lo: lo, hi: hi)
                        .stroke(Theme.heartRate,
                                style: StrokeStyle(lineWidth: max(1, sz(1.4, scale)), lineCap: .round, lineJoin: .round))
                        .shadow(color: CardVisual.routeShadowColor, radius: max(1, sz(1.5, scale)), y: 0.5)
                }
                .frame(height: chartH)
            }
            HStack(spacing: gap) {
                Text("HR")
                Spacer(minLength: 0)
                Text(timeText).monospacedDigit()
            }
            .padding(.leading, labelW + gap)
            .font(.system(size: sz(7, scale), weight: .bold))
            .tracking(0.9)
            .lineLimit(1)
            .stampTextOutline(show: showTextOutline, fill: legend, outline: outline)
        }
        .frame(width: width, alignment: .leading)
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
    /// 위쪽 배치 시 데이터 블록이 피해야 할 로고(+대회 뱃지) 아래 선
    var topClearance: CGFloat = 0

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
            .padding(.top, position.isTop ? max(0, topClearance - sz(16, scale)) : 0)
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
                        // 빈 칸은 스탬프 색 — 흰색 고정이면 흰 배경(사진 없음)에서 사라진다
                        .fill(isSel ? zoneOrange : fill.opacity(0.22))
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

            // 숫자·곡선 모두 스탬프 색 — 라임 고정이면 흰 배경(사진 없음)에서 거의 안 보인다
            HStack(alignment: .lastTextBaseline, spacing: sz(2, scale)) {
                Text("↑\(data.elevGain ?? "—")")
                    .font(.system(size: sz(20, scale), weight: .black))
                Text("M")
                    .font(.system(size: sz(9, scale), weight: .bold, design: .monospaced))
            }
            .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)

            Text("ELEV GAIN · \(data.distance) \(data.distanceUnit)")
                .font(.system(size: sz(9, scale), weight: .medium, design: .monospaced))
                .tracking(1.2)
                .stampTextOutline(show: showTextOutline, fill: fill, outline: outline)
        }
    }

    private var elevCanvas: some View {
        let series = data.elevSeries ?? defaultSeries
        return ZStack {
            ElevFillShape(series: series).fill(fill.opacity(0.18))
            ElevLineShape(series: series)
                .stroke(fill, style: StrokeStyle(lineWidth: max(1, sz(1.5, scale)), lineCap: .round, lineJoin: .round))
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
        // 스탬프 색 — 흰색 고정이면 흰 배경(사진 없음)에서 사라진다
        EQBarShape(barHeights: barHeights).fill(fill.opacity(0.82))
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
