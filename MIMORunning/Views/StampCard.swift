// 스탬프 카드 렌더러. 미리보기와 영상 합성이 모두 이 뷰를 사용한다(렌더 경로 단일화).
// ⚠️ 스탬프 카드 전용. 다른 카드 코드 작성 금지.

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
        coordText: "37.32°N 126.83°E"
    )
}

// MARK: - Stamp Outline (4방향 그림자로 text-stroke 시뮬레이션)

extension View {
    // shadow가 더 넓게 퍼져 "채움"처럼 보이고, foreground가 좁아 "외곽선"처럼 보인다.
    // → fill(배경색)을 shadow로, outline(외곽 텍스트색)을 foreground로 올바르게 배치.
    // 8방향 0.45pt + opacity 0.5: 완전한 커버리지 유지하면서 번짐 최소화.
    func stampOutline(fill: Color, outline: Color) -> some View {
        let c = fill.opacity(0.50)
        return self.foregroundStyle(outline)
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
        else    { self.foregroundStyle(outline) }
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
                    ZStack(alignment: position.alignment) {
                        Color.clear
                        stampContent(fill: fill, outline: outline, scale: scale)
                            .padding(12)
                    }
                }
            } else {
                Color.clear   // 문구만 렌더 시에도 프레임 유지
            }

            if !renderOnlyStamp, !stampText.isEmpty {
                ZStack(alignment: stampTextPosition.alignment) {
                    Color.clear
                    textOverlay
                        .padding(EdgeInsets(
                            top: stampTextPosition.isTop ? wordmarkTopInset : 14,
                            leading: 14, bottom: 14, trailing: 14))
                }
            }
        }
    }

    @ViewBuilder
    private var textOverlay: some View {
        let fontSize = OneLinerFont.basePt * stampTextFont.sizeScale * stampTextSize.scale
        if stampTextHasBorder {
            let bc = stampTextColor.borderSwiftColor.opacity(0.70)
            Text(stampText)
                .font(stampTextFont.swiftUIFont(size: fontSize))
                .foregroundStyle(stampTextColor.color)
                .shadow(color: bc, radius: 0.25, x:  0.5, y:  0)
                .shadow(color: bc, radius: 0.25, x: -0.5, y:  0)
                .shadow(color: bc, radius: 0.25, x:  0,   y:  0.5)
                .shadow(color: bc, radius: 0.25, x:  0,   y: -0.5)
                .shadow(color: bc, radius: 0.25, x:  0.5, y:  0.5)
                .shadow(color: bc, radius: 0.25, x: -0.5, y: -0.5)
                .shadow(color: bc, radius: 0.25, x:  0.5, y: -0.5)
                .shadow(color: bc, radius: 0.25, x: -0.5, y:  0.5)
                .multilineTextAlignment(.center)
        } else {
            Text(stampText)
                .font(stampTextFont.swiftUIFont(size: fontSize))
                .foregroundStyle(stampTextColor.color)
                .multilineTextAlignment(.center)
        }
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
        case .mapBackground:
            StampMapBackgroundView(data: data, fill: fill, outline: outline, scale: scale,
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
            // 네 모서리 브래킷 (Canvas) — 항상 전체 프레임을 채움
            Canvas { ctx, size in
                let inset: CGFloat = sz(12, scale)
                let bw:    CGFloat = sz(14, scale)
                let bh:    CGFloat = sz(12, scale)
                let lw:    CGFloat = max(1, sz(1.5, scale))

                var path = Path()

                // 좌상 ┌
                path.move(to:    CGPoint(x: inset + bw, y: inset))
                path.addLine(to: CGPoint(x: inset,      y: inset))
                path.addLine(to: CGPoint(x: inset,      y: inset + bh))

                // 우상 ┐
                path.move(to:    CGPoint(x: size.width - inset - bw, y: inset))
                path.addLine(to: CGPoint(x: size.width - inset,      y: inset))
                path.addLine(to: CGPoint(x: size.width - inset,      y: inset + bh))

                // 좌하 └
                path.move(to:    CGPoint(x: inset, y: size.height - inset - bh))
                path.addLine(to: CGPoint(x: inset, y: size.height - inset))
                path.addLine(to: CGPoint(x: inset + bw, y: size.height - inset))

                // 우하 ┘
                path.move(to:    CGPoint(x: size.width - inset,      y: size.height - inset - bh))
                path.addLine(to: CGPoint(x: size.width - inset,      y: size.height - inset))
                path.addLine(to: CGPoint(x: size.width - inset - bw, y: size.height - inset))

                ctx.stroke(path, with: .color(outline.opacity(0.9)),
                           style: StrokeStyle(lineWidth: lw, lineCap: .square))
            }

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
        let series = data.hrSeries ?? defaultSeries
        return Canvas { ctx, size in
            guard series.count > 1 else { return }
            var path = Path()
            for (i, v) in series.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(series.count - 1)
                let y = size.height * (1.0 - v)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else       { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(Color(hex: "FF2E2E")),
                       style: StrokeStyle(lineWidth: max(1, sz(1.5, scale)), lineCap: .round, lineJoin: .round))
        }
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
        return Canvas { ctx, size in
            guard series.count > 1 else { return }
            let lime = Color(hex: "C6FF00")
            var fill = Path()
            fill.move(to: CGPoint(x: 0, y: size.height))
            for (i, v) in series.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(series.count - 1)
                let y = size.height * (1.0 - v)
                fill.addLine(to: CGPoint(x: x, y: y))
            }
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(lime.opacity(0.18)))
            var line = Path()
            for (i, v) in series.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(series.count - 1)
                let y = size.height * (1.0 - v)
                if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                else       { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(line, with: .color(lime),
                       style: StrokeStyle(lineWidth: max(1, sz(1.5, scale)), lineCap: .round, lineJoin: .round))
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
        Canvas { ctx, size in
            let count = barHeights.count
            let totalGap = size.width * 0.4
            let barW = (size.width - totalGap) / CGFloat(count)
            let gap = totalGap / CGFloat(count - 1)
            for i in 0..<count {
                let x = CGFloat(i) * (barW + gap)
                let h = size.height * barHeights[i]
                let rect = CGRect(x: x, y: size.height - h, width: barW, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.white.opacity(0.82)))
            }
        }
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

// MARK: - Map Background (fixed)

private struct StampMapBackgroundView: View {
    let data: StampData
    let fill: Color
    let outline: Color
    let scale: CGFloat
    var showTextOutline: Bool = true

    var body: some View {
        ZStack(alignment: .bottom) {
            // 지도 배경
            if let img = data.mapImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipped()

                // 경로 라인 오버레이
                if let pts = data.routePoints, pts.count > 1 {
                    GeometryReader { geo in
                        let sx = geo.size.width / img.size.width
                        let sy = geo.size.height / img.size.height
                        Path { path in
                            for (i, pt) in pts.enumerated() {
                                let p = CGPoint(x: pt.x * sx, y: pt.y * sy)
                                if i == 0 { path.move(to: p) }
                                else       { path.addLine(to: p) }
                            }
                        }
                        .stroke(Color(hex: "FF2E2E"),
                                style: StrokeStyle(lineWidth: sz(2.5, scale), lineCap: .round, lineJoin: .round))
                    }
                }
            } else {
                Color(hex: "1A2030")
            }

            // 하단 그라데이션 + 레이블
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.70)],
                           startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: sz(2, scale)) {
                if let name = data.placeName ?? data.coordText {
                    Text(name.uppercased())
                        .font(.system(size: sz(18, scale), weight: .black))
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
                Text("\(data.distance) \(data.distanceUnit)  \(data.pace)  \(data.time)")
                    .font(.system(size: sz(9, scale), weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .opacity(0.92)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .padding(.horizontal, sz(14, scale))
            .padding(.bottom, sz(16, scale))
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
