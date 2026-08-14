// OneLiner 카드 렌더러 (타입·EffectTextView → OneLinerTypes.swift)
import SwiftUI
import UIKit
import CoreLocation

// MARK: - OneLinerCard
//
// Full-bleed photo or sky-gradient card with wordmark (MIMO / RUNNING) at top-left.
// The user's message is the only hero. Optional date stamp at bottom-trailing.
// Background priority: backgroundPhoto → SkyPalette gradient (activity start time).
// showBackground: false renders content-only with transparent background (for video overlay).

struct OneLinerCard: View {
    var activity: Activity? = nil
    /// Date used for the date stamp and gradient when `activity` is nil (rest-day mode).
    var displayDate: Date = Date()
    var backgroundPhoto: UIImage? = nil
    var cropOffsetX: CGFloat = 0.5
    var text: String = ""
    var position: CardPosition = .center
    var textColor: OneLinerTextColor = .white
    var fontChoice: OneLinerFont = .pen
    var sizeLevel: TextSizeLevel = .medium
    var appearanceMode: AppearanceMode = .typing
    var decorEffect:    DecorEffect    = .none
    var hasBorder:      Bool           = false
    var flyDirection:   FlyInDirection = .trailing
    var showDate: Bool = true
    var showBackground: Bool = true
    var showWordmark: Bool = true
    /// When true, text + date are pinned together at the bottom-left (caption layout).
    /// The `position` parameter is ignored in this mode.
    var captionMode: Bool = false
    /// 스토리 모드에서 차트 패널이 하단에 배치될 때 해당 영역 높이(pt). > 0이면 문구를 차트 위 공간에 배치.
    var chartBottomReserved: CGFloat = 0
    /// 스토리 모드에서 차트 패널이 상단에 배치될 때 해당 영역 높이(pt). > 0이면 문구를 차트 아래 공간에 배치.
    var chartTopReserved: CGFloat = 0
    /// Full-video title overlay (영상·슬라이드 미리보기). Empty = hidden.
    var videoTitle: String = ""
    var titleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    /// 카드 높이 오버라이드. nil=기본 375(4:5). 영상/슬라이드 미리보기는 실제 표시 높이를 전달.
    var cardHeightOverride: CGFloat? = nil
    /// 카드 폭 오버라이드. nil=기본 300pt. 영상·슬라이드 미리보기에서 scaleEffect 없이 실제
    /// 표시 폭으로 렌더할 때 사용. baseFontSize가 (cardWidthOverride/300) 비율로 스케일됨.
    var cardWidthOverride: CGFloat? = nil
    /// 위쪽 포지션 텍스트 안전 여백. 외부 워드마크가 있으면 호출처에서 반드시 명시.
    /// nil = showWordmark:true → 64pt 고정 / showWordmark:false → 42pt(4:5 기본).
    var safeTopInset: CGFloat? = nil
    /// 아래쪽 포지션 텍스트 안전 여백. 바닥에 붙지 않게 호출처에서 명시.
    /// nil = 0pt (chartBottomReserved로 대신 처리하는 경우 포함).
    var safeBottomInset: CGFloat? = nil
    /// 정지 미리보기 모드: 텍스트를 즉시 전체 표시. 타이핑 딜레이·페이드인·슬라이드인 없음.
    /// Placeable/OneLiner 영상 정지 상태에서 사용 — 실제 애니메이션은 재생 시 CALayer가 담당.
    var isStaticPreview: Bool = false

    // PDT metric chips (pace / distance / time / heartrate)
    var metricPace:      Bool = false
    var metricDistance:  Bool = false
    var metricTime:      Bool = false
    var metricHeartRate: Bool = false
    var pdtPosition:     CardPosition  = .bottomLeading
    var pdtSizeLevel:    TextSizeLevel = .medium
    var availableMetrics: [MetricItem] = []

    // Route minimap (M) and HR chart (H) — story mode overlays
    var showRoute:    Bool = false
    var routeCoords:  [CLLocationCoordinate2D] = []
    var routePosition: CardPosition = .bottomTrailing
    var showHRChart:  Bool = false
    var hrSamples:    [(offset: TimeInterval, bpm: Int)] = []
    var hrZones:      [HRZoneData]  = []
    // Generic chart overlay (elevation, cadence, splits, intervals, etc.)
    var chartOverlayType:   ChartOverlayType = .none
    var chartSeriesData:    [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:]
    var chartSplits:        [SplitData] = []
    var intervalSegments:   [IntervalSegment] = []

    private var cardDate: Date { activity?.date ?? displayDate }

    static let cardWidth:  CGFloat = 300
    static let cardHeight: CGFloat = 375

    private var actualCardWidth: CGFloat { cardWidthOverride ?? Self.cardWidth }
    private var baseFontSize: CGFloat {
        OneLinerFont.basePt * fontChoice.sizeScale * sizeLevel.scale
            * (actualCardWidth / Self.cardWidth)
    }
    private var lineSpacing:  CGFloat { baseFontSize * 0.1 }

    private var textAlignment: TextAlignment {
        switch position {
        case .topTrailing, .trailing, .bottomTrailing: return .trailing
        case .topLeading,  .leading,  .bottomLeading:  return .leading
        default: return .center
        }
    }

    // 위쪽·아래쪽 안전 여백 — 추론 없이 호출처가 safeTopInset/safeBottomInset으로 명시.
    // showWordmark=true: 워드마크 존(32+26+6)+여백(4) = 68pt (CALayer defaultTopY와 동일).
    // 기본값(nil): 상단 42pt(외부 워드마크 없는 4:5 기본) / 하단 0pt.
    // 제목(videoTitle)이 위쪽에 있으면 문구를 제목 아래로 밀기 — export(titleTopEndY)와 동일 논리.
    private var textTopInset: CGFloat {
        guard position.isTop else { return 0 }
        // 워드마크 존(32) + MIMOWordmark 높이(≈26) + 간격(6) + 여백(4) = 68pt
        let base: CGFloat = showWordmark ? 68 : (safeTopInset ?? 42)
        guard !videoTitle.isEmpty, titleStyle.position.isTop else { return base }
        // CALayer와 동일한 UIKit 실측: tLayerH_pt = ceil(bounds) + 20px*(300/1080)
        let titleFontSize = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale
        let tFont  = titleStyle.fontChoice.uiFont(size: titleFontSize)
        let maxW   = Self.cardWidth - 48.0  // 24pt 양쪽 여백 (= CALayer textMaxW 기준)
        let tBounds = (videoTitle as NSString).boundingRect(
            with: CGSize(width: maxW, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: tFont], context: nil)
        let tLayerH = ceil(tBounds.height) + 20.0 * (Self.cardWidth / 1080.0)  // 20px → pt 환산
        return max(base, 76 + tLayerH + 8)
    }

    private var textBottomInset: CGFloat {
        guard position.isBottom else { return 0 }
        if cardHeightOverride != nil {
            let s = Self.cardWidth / 1080.0
            let base = cardHeightOverride! * 0.06  // H * 0.06 = export safeBot (~32pt)
            guard !videoTitle.isEmpty, titleStyle.position.isBottom else { return base }
            // 아래-아래: 제목이 맨 아래, 문구가 바로 위 (UIKit 실측 높이 기준)
            let titleFontSize = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale
            let tFont  = titleStyle.fontChoice.uiFont(size: titleFontSize)
            let maxW   = Self.cardWidth - 48.0
            let tBounds = (videoTitle as NSString).boundingRect(
                with: CGSize(width: maxW, height: 4000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: tFont], context: nil)
            let tLayerH = ceil(tBounds.height) + 20.0 * s
            return base + tLayerH + 8
        }
        return safeBottomInset ?? 0
    }

    var body: some View {
        ZStack {
            // ── Background ─────────────────────────────────────
            if showBackground { background }

            // ── Wordmark: MIMO (white) + RUNNING (violet) ──────
            if showWordmark {
                if captionMode { captionWordmarkRow } else { wordmark }
            }

            // ── Full-video title (영상·슬라이드 정지 미리보기) ─
            if !videoTitle.isEmpty { titleOverlay }

            // ── PDT metric chips (페이스·거리·시간·심박) ────────
            if metricPace || metricDistance || metricTime || metricHeartRate {
                pdtChipsOverlay
            }

            // ── 경로 미니맵 (M) — chartOverlayType == .route일 때는 차트 패널이 처리 ─
            if showRoute, chartOverlayType != .route, !routeCoords.isEmpty {
                RouteMiniMap(coords: routeCoords)
                    .frame(width: 54, height: 54)
                    .padding(.horizontal, 18)
                    .padding(.top, routePosition.isTop
                        ? (cardHeightOverride != nil ? CardVisual.videoSafeTop * (Self.cardWidth / 1080) + 14 : 28)
                        : 4)
                    .padding(.bottom, routePosition.isBottom
                        ? (cardHeightOverride != nil ? CardVisual.videoSafeBottom * (Self.cardWidth / 1080) : 24)
                        : 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: routePosition.alignment)
                    .allowsHitTesting(false)
            }

            // ── 심박 차트 (H) ──────────────────────────────────
            if showHRChart, hrSamples.count >= 2 {
                if cardHeightOverride != nil {
                    // 9:16 모드: zone-colored range bar chart (dataPreviewOverlay와 동일 크기)
                    let cardH   = cardHeightOverride ?? Self.cardHeight
                    let panW    = Self.cardWidth - 20
                    let panH    = cardH * 0.264
                    let hrSrc   = hrSamples.filter { $0.bpm > 0 }
                        .map { (offset: $0.offset, value: Double($0.bpm)) }
                    let hrt0    = hrSrc.first?.offset ?? 0
                    let hrdt    = max(1.0, (hrSrc.last?.offset ?? 1) - hrt0)
                    let hrdtMin = hrdt / 60.0
                    let hrBN    = 80
                    let hrBSz   = hrdt / Double(hrBN)
                    let hrBuckets: [(id: Int, avg: Double, lo: Double, hi: Double)] = (0..<hrBN).compactMap { i in
                        let bLo  = hrt0 + Double(i) * hrBSz
                        let bHi  = bLo + hrBSz
                        let vals = hrSrc
                            .filter { $0.offset >= bLo && ($0.offset < bHi || (i == hrBN-1 && $0.offset <= hrt0+hrdt)) }
                            .map(\.value)
                        guard !vals.isEmpty else { return nil }
                        return (i, vals.reduce(0,+)/Double(vals.count), vals.min()!, vals.max()!)
                    }
                    let hrAvgAll = hrSrc.isEmpty ? 0.0 : hrSrc.map(\.value).reduce(0,+) / Double(hrSrc.count)
                    let oMin  = hrBuckets.map(\.lo).min() ?? 0
                    let oMax  = hrBuckets.map(\.hi).max() ?? 1
                    let hrRng = max(oMax - oMin, oMin * 0.02)
                    let hrYLo = max(0, oMin - hrRng * 0.4)
                    let hrYHi = oMax + hrRng * 0.2
                    let hrYRange = max(1e-6, hrYHi - hrYLo)
                    let sortedZones = hrZones.sorted { $0.minBPM < $1.minBPM }
                    let zoneColor: (Double) -> Color = { bpm in
                        var idx = 1
                        for z in sortedZones { if bpm >= Double(z.minBPM) { idx = z.id } }
                        switch idx {
                        case 1:  return Color(red: 0.30, green: 0.55, blue: 1.00)
                        case 2:  return Color(red: 0.20, green: 0.85, blue: 0.45)
                        case 3:  return Color(red: 0.75, green: 0.88, blue: 0.20)
                        case 4:  return Color(red: 1.00, green: 0.55, blue: 0.10)
                        default: return Color(red: 1.00, green: 0.25, blue: 0.45)
                        }
                    }
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.30))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLanguage.shared.s("♥ 심박수", "♥ HR"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.top, 8)
                                .padding(.leading, 10)
                            Canvas { ctx, size in
                                guard !hrBuckets.isEmpty else { return }
                                let yLblW: CGFloat = 26
                                let xLblH: CGFloat = 11
                                let cw = max(1, size.width - yLblW)
                                let ch = max(1, size.height - xLblH)
                                let yMarkN = 4, xMarkN = 4
                                func pty(_ v: Double) -> CGFloat { ch * CGFloat(1-(v-hrYLo)/hrYRange) }
                                let axisFont  = Font.system(size: 7, design: .monospaced)
                                let axisColor = Color.white.opacity(0.55)
                                for i in 0..<yMarkN {
                                    let yVal = hrYLo + Double(i)*(hrYHi-hrYLo)/Double(yMarkN-1)
                                    let yp = pty(yVal)
                                    var gp = Path(); gp.move(to: .init(x:0,y:yp)); gp.addLine(to: .init(x:cw,y:yp))
                                    ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                                    ctx.draw(Text(String(format:"%.0f",yVal)).font(axisFont).foregroundColor(axisColor),
                                             at: .init(x:cw+2,y:yp), anchor: .leading)
                                }
                                for i in 0..<xMarkN {
                                    let frac = Double(i)/Double(xMarkN-1)
                                    let xp = CGFloat(frac)*cw
                                    var gp = Path(); gp.move(to: .init(x:xp,y:0)); gp.addLine(to: .init(x:xp,y:ch))
                                    ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                                    let xTxt = AppLanguage.shared.isEnglish
                                        ? String(format:"%.0fm",frac*hrdtMin)
                                        : String(format:"%.0f분",frac*hrdtMin)
                                    var anch: UnitPoint = .top
                                    if i == 0 { anch = .topLeading } else if i == xMarkN-1 { anch = .topTrailing }
                                    ctx.draw(Text(xTxt).font(axisFont).foregroundColor(axisColor),
                                             at: .init(x:xp,y:ch+2), anchor: anch)
                                }
                                let barGap = cw / CGFloat(hrBN)
                                let barW   = max(1.5, barGap - 0.8)
                                for b in hrBuckets {
                                    let bx = CGFloat(b.id)*barGap+(barGap-barW)/2
                                    let topY = pty(b.hi); let botY = pty(b.lo)
                                    let barH = max(1.5, botY - topY)
                                    ctx.fill(Path(CGRect(x:bx,y:topY,width:barW,height:barH)),
                                             with: .color(zoneColor(b.avg).opacity(0.85)))
                                }
                                let avgY = pty(hrAvgAll)
                                var dashPath = Path(); var dx: CGFloat = 0
                                while dx < cw {
                                    dashPath.move(to: .init(x:dx,y:avgY))
                                    dashPath.addLine(to: .init(x:min(dx+4,cw),y:avgY))
                                    dx += 7
                                }
                                ctx.stroke(dashPath, with: .color(Color.red.opacity(0.75)), lineWidth: 1.2)
                                ctx.draw(
                                    Text("avg \(Int(hrAvgAll))").font(Font.system(size:7.5,weight:.medium))
                                        .foregroundColor(Color.red.opacity(0.9)),
                                    at: .init(x:cw-2,y:avgY-1), anchor: .bottomTrailing)
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 4)
                        }
                    }
                    .frame(width: panW, height: panH)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                } else {
                    // 4:5 모드: zone-colored bar chart (편집화면과 동일)
                    let panW4  = Self.cardWidth - 20
                    let panH4  = Self.cardHeight * 0.264
                    let hrSrc4 = hrSamples.filter { $0.bpm > 0 }
                        .map { (offset: $0.offset, value: Double($0.bpm)) }
                    let hrt04    = hrSrc4.first?.offset ?? 0
                    let hrdt4    = max(1.0, (hrSrc4.last?.offset ?? 1) - hrt04)
                    let hrdtMin4 = hrdt4 / 60.0
                    let hrBN4    = 80
                    let hrBSz4   = hrdt4 / Double(hrBN4)
                    let hrBuckets4: [(id: Int, avg: Double, lo: Double, hi: Double)] = (0..<hrBN4).compactMap { i in
                        let bLo  = hrt04 + Double(i) * hrBSz4
                        let bHi  = bLo + hrBSz4
                        let vals = hrSrc4
                            .filter { $0.offset >= bLo && ($0.offset < bHi || (i == hrBN4-1 && $0.offset <= hrt04+hrdt4)) }
                            .map(\.value)
                        guard !vals.isEmpty else { return nil }
                        return (i, vals.reduce(0,+)/Double(vals.count), vals.min()!, vals.max()!)
                    }
                    let hrAvgAll4 = hrSrc4.isEmpty ? 0.0 : hrSrc4.map(\.value).reduce(0,+) / Double(hrSrc4.count)
                    let oMin4  = hrBuckets4.map(\.lo).min() ?? 0
                    let oMax4  = hrBuckets4.map(\.hi).max() ?? 1
                    let hrRng4 = max(oMax4 - oMin4, oMin4 * 0.02)
                    let hrYLo4 = max(0, oMin4 - hrRng4 * 0.4)
                    let hrYHi4 = oMax4 + hrRng4 * 0.2
                    let hrYRange4 = max(1e-6, hrYHi4 - hrYLo4)
                    let sortedZones4 = hrZones.sorted { $0.minBPM < $1.minBPM }
                    let zoneColor4: (Double) -> Color = { bpm in
                        var idx = 1
                        for z in sortedZones4 { if bpm >= Double(z.minBPM) { idx = z.id } }
                        switch idx {
                        case 1:  return Color(red: 0.30, green: 0.55, blue: 1.00)
                        case 2:  return Color(red: 0.20, green: 0.85, blue: 0.45)
                        case 3:  return Color(red: 0.75, green: 0.88, blue: 0.20)
                        case 4:  return Color(red: 1.00, green: 0.55, blue: 0.10)
                        default: return Color(red: 1.00, green: 0.25, blue: 0.45)
                        }
                    }
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.30))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLanguage.shared.s("♥ 심박수", "♥ HR"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.top, 8)
                                .padding(.leading, 10)
                            Canvas { ctx, size in
                                guard !hrBuckets4.isEmpty else { return }
                                let yLblW: CGFloat = 26
                                let xLblH: CGFloat = 11
                                let cw = max(1, size.width - yLblW)
                                let ch = max(1, size.height - xLblH)
                                let yMarkN = 4, xMarkN = 4
                                func pty(_ v: Double) -> CGFloat { ch * CGFloat(1-(v-hrYLo4)/hrYRange4) }
                                let axisFont  = Font.system(size: 7, design: .monospaced)
                                let axisColor = Color.white.opacity(0.55)
                                for i in 0..<yMarkN {
                                    let yVal = hrYLo4 + Double(i)*(hrYHi4-hrYLo4)/Double(yMarkN-1)
                                    let yp = pty(yVal)
                                    var gp = Path(); gp.move(to: .init(x:0,y:yp)); gp.addLine(to: .init(x:cw,y:yp))
                                    ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                                    ctx.draw(Text(String(format:"%.0f",yVal)).font(axisFont).foregroundColor(axisColor),
                                             at: .init(x:cw+2,y:yp), anchor: .leading)
                                }
                                for i in 0..<xMarkN {
                                    let frac = Double(i)/Double(xMarkN-1)
                                    let xp = CGFloat(frac)*cw
                                    var gp = Path(); gp.move(to: .init(x:xp,y:0)); gp.addLine(to: .init(x:xp,y:ch))
                                    ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                                    let xTxt = AppLanguage.shared.isEnglish
                                        ? String(format:"%.0fm",frac*hrdtMin4)
                                        : String(format:"%.0f분",frac*hrdtMin4)
                                    var anch: UnitPoint = .top
                                    if i == 0 { anch = .topLeading } else if i == xMarkN-1 { anch = .topTrailing }
                                    ctx.draw(Text(xTxt).font(axisFont).foregroundColor(axisColor),
                                             at: .init(x:xp,y:ch+2), anchor: anch)
                                }
                                let barGap = cw / CGFloat(hrBN4)
                                let barW   = max(1.5, barGap - 0.8)
                                for b in hrBuckets4 {
                                    let bx = CGFloat(b.id)*barGap+(barGap-barW)/2
                                    let topY = pty(b.hi); let botY = pty(b.lo)
                                    let barH = max(1.5, botY - topY)
                                    ctx.fill(Path(CGRect(x:bx,y:topY,width:barW,height:barH)),
                                             with: .color(zoneColor4(b.avg).opacity(0.85)))
                                }
                                let avgY = pty(hrAvgAll4)
                                var dashPath = Path(); var dx: CGFloat = 0
                                while dx < cw {
                                    dashPath.move(to: .init(x:dx,y:avgY))
                                    dashPath.addLine(to: .init(x:min(dx+4,cw),y:avgY))
                                    dx += 7
                                }
                                ctx.stroke(dashPath, with: .color(Color.red.opacity(0.75)), lineWidth: 1.2)
                                ctx.draw(
                                    Text("avg \(Int(hrAvgAll4))").font(Font.system(size:7.5,weight:.medium))
                                        .foregroundColor(Color.red.opacity(0.9)),
                                    at: .init(x:cw-2,y:avgY-1), anchor: .bottomTrailing)
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 4)
                        }
                    }
                    .frame(width: panW4, height: panH4)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                }
            }

            // ── 경로 차트 패널 (chartOverlayType == .route) ───────
            if chartOverlayType == .route, !routeCoords.isEmpty {
                let cardH   = cardHeightOverride ?? Self.cardHeight
                let panW    = Self.cardWidth - 20
                let panH    = cardH * 0.264
                let lats    = routeCoords.map { $0.latitude }
                let lons    = routeCoords.map { $0.longitude }
                let minLat  = lats.min()!, maxLat = lats.max()!
                let minLon  = lons.min()!, maxLon = lons.max()!
                let rng     = max(1e-6, max(maxLat - minLat, maxLon - minLon))
                let padX    = (rng - (maxLon - minLon)) / 2
                let padY    = (rng - (maxLat - minLat)) / 2
                let routePt: (CLLocationCoordinate2D, CGSize) -> CGPoint = { c, size in
                    let nx   = CGFloat((c.longitude - minLon + padX) / rng)
                    let ny   = CGFloat((c.latitude  - minLat + padY) / rng)
                    let ins: CGFloat = size.height * 0.06
                    let dim  = min(size.width, size.height) - ins * 2
                    let xOff = (size.width - dim) / 2
                    return CGPoint(x: xOff + ins + nx * dim, y: ins + (1 - ny) * dim)
                }
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLanguage.shared.s("↗ 경로", "↗ Route"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.top, 8)
                            .padding(.leading, 10)
                        Canvas { ctx, size in
                            var path = Path()
                            path.move(to: routePt(routeCoords[0], size))
                            for c in routeCoords.dropFirst() { path.addLine(to: routePt(c, size)) }
                            ctx.stroke(path, with: .color(.white.opacity(0.88)),
                                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            let dotR: CGFloat = 3.5
                            let sPt = routePt(routeCoords.first!, size)
                            ctx.fill(Path(ellipseIn: CGRect(x: sPt.x - dotR, y: sPt.y - dotR,
                                                            width: dotR * 2, height: dotR * 2)),
                                     with: .color(.green.opacity(0.90)))
                            let ePt = routePt(routeCoords.last!, size)
                            ctx.fill(Path(ellipseIn: CGRect(x: ePt.x - dotR, y: ePt.y - dotR,
                                                            width: dotR * 2, height: dotR * 2)),
                                     with: .color(.red.opacity(0.90)))
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                    }
                }
                .frame(width: panW, height: panH)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            }

            // ── 일반 차트 오버레이 (고도·케이던스 등) ─────────────
            if !showHRChart, ![.none, .route, .hrChart].contains(chartOverlayType) {
                genericChartOverlay
            }

            // ── Hero text + date ───────────────────────────────
            if captionMode {
                captionContent
            } else {
                if text.isEmpty {
                    if showBackground {
                        Text(AppLanguage.shared.s("한마디를 입력해 주세요", "Enter your one-liner"))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    // 문구 블록 (날짜는 아래에서 우상단 별도 배치)
                    EffectTextView(
                        text: text, font: fontChoice.swiftUIFont(size: baseFontSize),
                        lineSpacing: lineSpacing, alignment: textAlignment,
                        color: textColor.color,
                        appearanceMode: appearanceMode,
                        decorEffect: decorEffect,
                        hasBorder: hasBorder,
                        flyDirection: flyDirection,
                        syntheticBoldStroke: fontChoice.syntheticBoldStroke(for: baseFontSize),
                        borderColor: hasBorder ? textColor.borderSwiftColor : .clear,
                        borderOffset: hasBorder ? max(0.8, baseFontSize * textColor.borderOffsetFactor) : 0,
                        isStaticPreview: isStaticPreview
                    )
                    .padding(.horizontal, cardHeightOverride != nil ? 24 : 14)  // 9:16 = CALayer hPad 24 기준
                    .padding(.top, textTopInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
                    .padding(.bottom, max(textBottomInset, chartBottomReserved > 0 ? chartBottomReserved + 8 : 0))
                    .padding(.top,    chartTopReserved    > 0 ? chartTopReserved    + 8 : 0)
                    .offset(y: position == .center
                        ? ((chartBottomReserved > 0 ? chartBottomReserved + 8 : 0) -
                           (chartTopReserved    > 0 ? chartTopReserved    + 8 : 0)) / 2
                        : 0)
                    if showDate {
                        // 날짜: 워드마크(MIMO RUNNING) 줄 오른쪽 → 문구와 겹침 방지
                        Text(cardDate.oneLinerDateString)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.trailing, 14)
                            .padding(.top, 32)
                    }
                }
            }
        }
        .frame(width: actualCardWidth, height: cardHeightOverride ?? Self.cardHeight)
    }

    // Full-video title overlay — 9위치(3×3 그리드) 완전 반영.
    // Paddings use the same scale1080 basis as ClipTrimView (safeTop=260px, safeBottom=270px @1080px).
    private var titleOverlay: some View {
        let scale1080: CGFloat = Self.cardWidth / 1080.0   // 300/1080 ≈ 0.2778
        let fontSize   = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale
        // 영상(non-captionMode): tFrameY = 76pt (wMZoneH+12, VideoExportService 기준)
        // 슬라이드(captionMode):  tFrameY = 68pt (defaultTopY, PhotoSlideComposition 기준)
        let topPad: CGFloat = titleStyle.position.isTop
            ? (captionMode ? (32 + ceil(11.0 * 2.3) + 6 + 4) : (32 + ceil(11.0 * 2.3) + 6 + 12))
            : 0
        let bottomPad: CGFloat = titleStyle.position.isBottom
            ? (cardHeightOverride != nil ? cardHeightOverride! * 0.06 : CardVisual.videoSafeBottom * scale1080)
            : 0
        let titleTextAlign: TextAlignment = {
            switch titleStyle.position {
            case .topLeading, .leading, .bottomLeading:    return .leading
            case .topTrailing, .trailing, .bottomTrailing: return .trailing
            default: return .center
            }
        }()
        return makeTitleView(videoTitle, fontSize: fontSize)
            .multilineTextAlignment(titleTextAlign)
            .lineLimit(2)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 24)   // CALayer hPad = 24 기준
            .padding(.top, topPad)
            .padding(.bottom, bottomPad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: titleStyle.position.alignment)
            .allowsHitTesting(false)
    }

    /// 제목 채움 Text (테두리 없을 때 합성 볼드 포함).
    private func makeTitleBaseText(_ string: String, fontSize: CGFloat) -> Text {
        let synStroke = titleStyle.fontChoice.syntheticBoldStroke(for: fontSize)
        let tColor    = titleStyle.textColor.color
        let tFont     = titleStyle.fontChoice.swiftUIFont(size: fontSize)
        guard synStroke != 0 else {
            return Text(string).font(tFont).foregroundStyle(tColor)
        }
        var attr = AttributedString(string)
        attr.font = tFont; attr.foregroundColor = tColor
        attr.uiKit.strokeWidth = synStroke; attr.uiKit.strokeColor = UIColor(tColor)
        return Text(attr)
    }

    /// 제목 테두리색 Text (8방향 배경용).
    private func makeTitleBorderText(_ string: String, fontSize: CGFloat) -> Text {
        Text(string)
            .font(titleStyle.fontChoice.swiftUIFont(size: fontSize))
            .foregroundStyle(titleStyle.textColor.borderSwiftColor)
    }

    /// 제목 뷰 — 테두리는 8방향 오프셋 ZStack (EffectTextView와 동일 기법, §15.3).
    @ViewBuilder
    private func makeTitleView(_ string: String, fontSize: CGFloat) -> some View {
        let hasBorder = titleStyle.outline
        let o: CGFloat = hasBorder ? max(0.8, fontSize * titleStyle.textColor.borderOffsetFactor) : 0
        if hasBorder {
            ZStack {
                Group {
                    makeTitleBorderText(string, fontSize: fontSize).offset(x: -o, y: -o)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x:  o, y: -o)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x: -o, y:  o)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x:  o, y:  o)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x: -o, y:  0)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x:  o, y:  0)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x:  0, y: -o)
                    makeTitleBorderText(string, fontSize: fontSize).offset(x:  0, y:  o)
                }
                makeTitleBaseText(string, fontSize: fontSize)
            }
        } else {
            makeTitleBaseText(string, fontSize: fontSize)
        }
    }

    // UIKit NSLayoutManager로 줄바꿈 위치를 미리 계산해 \n 삽입.
    // CALayer 렌더러(영상 출력)와 SwiftUI EffectTextView의 줄바꿈이 일치하도록 맞춤.
    private func uikitLineBreakText(_ text: String, uiFont: UIFont, maxWidth: CGFloat) -> String {
        text.components(separatedBy: "\n").map { para -> String in
            guard !para.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return para }
            let storage   = NSTextStorage(string: para, attributes: [.font: uiFont])
            let manager   = NSLayoutManager()
            storage.addLayoutManager(manager)
            let container = NSTextContainer(size: CGSize(width: maxWidth, height: 100_000))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            _ = manager.glyphRange(for: container)
            var lines: [String] = []; var gi = 0
            while gi < manager.numberOfGlyphs {
                var gr = NSRange()
                manager.lineFragmentRect(forGlyphAt: gi, effectiveRange: &gr)
                let cr = manager.characterRange(forGlyphRange: gr, actualGlyphRange: nil)
                lines.append((para as NSString).substring(with: cr).trimmingCharacters(in: .newlines))
                gi = NSMaxRange(gr)
            }
            return lines.isEmpty ? para : lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    // Text just above date — the text+date unit moves together to `position`.
    // Horizontal alignment follows the position column; vertical follows the row.
    @ViewBuilder
    private var captionContent: some View {
        let isTrailing = (position == .topTrailing || position == .trailing || position == .bottomTrailing)
        let hAlign: HorizontalAlignment = position.isLeading ? .leading : isTrailing ? .trailing : .center
        let tAlign: TextAlignment       = position.isLeading ? .leading : isTrailing ? .trailing : .center
        // 9:16 클립 모드에서는 UIKit 줄바꿈을 미리 계산해 CALayer 출력과 일치시킴
        let clipText: String = (cardHeightOverride != nil && !text.isEmpty)
            ? uikitLineBreakText(text, uiFont: fontChoice.uiFont(size: baseFontSize), maxWidth: Self.cardWidth - 48)
            : text
        let s = Self.cardWidth / 1080.0
        let captionTopPad: CGFloat = {
            if cardHeightOverride != nil {
                // 9:16 클립 모드: 워드마크 존(32+26+6) + 여백(4) = 68pt (CALayer defaultTopY 기준)
                let clipTop = (32.0 + ceil(11.0 * 2.3) + 6 + 4) * (Self.cardWidth / 300.0)
                var minTop = clipTop
                if !videoTitle.isEmpty && titleStyle.position.isTop && position.isTop {
                    // UIKit 실측으로 CALayer titleTopEndY와 동일하게 계산
                    let titleFont = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale
                    let tFont  = titleStyle.fontChoice.uiFont(size: titleFont)
                    let maxW   = Self.cardWidth - 48.0
                    let tBounds = (videoTitle as NSString).boundingRect(
                        with: CGSize(width: maxW, height: 4000),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: tFont], context: nil)
                    let tLayerH = ceil(tBounds.height) + 20.0 * (Self.cardWidth / 1080.0)
                    // 슬라이드(captionMode): 제목 tFrameY = 68pt(defaultTopY). 영상: 76pt(tFrameY).
                    let titleTop: CGFloat = captionMode ? clipTop : 76
                    minTop = max(minTop, titleTop + tLayerH + 8)
                }
                // PDT 칩이 위쪽일 때: 문구가 칩 영역 아래에 오도록 밀기
                if (metricPace || metricDistance || metricTime || metricHeartRate),
                   pdtPosition.isTop, position.isTop {
                    // 제목 있으면 cardHeight 28% 절대 위치, 없으면 워드마크 아래
                    let chipTop: CGFloat = (!videoTitle.isEmpty && titleStyle.position.isTop)
                        ? cardHeightOverride! * 0.28
                        : CardVisual.videoSafeTop * (Self.cardWidth / 1080) + 14
                    let chipH   = 22.0 * pdtSizeLevel.scale
                    minTop = max(minTop, chipTop + chipH + 8)
                }
                return minTop
            }
            // 4:5 일반 모드
            if !videoTitle.isEmpty && titleStyle.position.isTop && position.isTop {
                let titleFont = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale
                let tFont  = titleStyle.fontChoice.uiFont(size: titleFont)
                let maxW   = Self.cardWidth - 48.0
                let tBounds = (videoTitle as NSString).boundingRect(
                    with: CGSize(width: maxW, height: 4000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: tFont], context: nil)
                let tLayerH = ceil(tBounds.height) + 20.0 * (Self.cardWidth / 1080.0)
                return max(32, 64 + tLayerH + 8)
            }
            // captionWordmarkRow가 상단 14pt에 배치될 때(showWordmark=true) 하단은 39.3pt
            // → 42pt로 2.7pt 여백 확보 (외부 워드마크 기준 textTopInset=42와 동일 논리).
            let base4: CGFloat = position.isTop ? (showWordmark ? 42 : 30) : 12
            // 4:5 captionMode: PDT 칩이 위쪽이면 칩 아래로 문구 밀기
            // (4:5 칩 top=28pt; 22*sz ≈ SwiftUI 시스템폰트 11pt*sz 실제 행높이+패딩)
            if captionMode && position.isTop && pdtPosition.isTop &&
               (metricPace || metricDistance || metricTime || metricHeartRate) {
                let chipH = 22.0 * pdtSizeLevel.scale
                return max(base4, 28 + chipH + 8)
            }
            return base4
        }()
        // 차트 있으면 차트 위로 배치; 없으면 9:16은 CALayer 안전 여백, 4:5는 기존값
        let captionBotPad: CGFloat = chartBottomReserved > 0
            ? chartBottomReserved + 8
            : cardHeightOverride != nil
                ? {
                    let base = cardHeightOverride! * 0.06  // H * 0.06 = export safeBot (~32pt)
                    guard !videoTitle.isEmpty, titleStyle.position.isBottom, position.isBottom else { return base }
                    // 아래-아래: 제목이 맨 아래, 문구가 바로 위 (UIKit 실측)
                    let titleFontSize = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale
                    let tFont  = titleStyle.fontChoice.uiFont(size: titleFontSize)
                    let maxW   = Self.cardWidth - 48.0
                    let tBounds = (videoTitle as NSString).boundingRect(
                        with: CGSize(width: maxW, height: 4000),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: tFont], context: nil)
                    let tLayerH = ceil(tBounds.height) + 20.0 * s
                    return base + tLayerH + 8
                  }()
                : (position.isBottom ? 34 : 12)
        VStack(alignment: hAlign, spacing: 4) {
            if text.isEmpty {
                if showBackground {
                    Text(AppLanguage.shared.s("한마디를 입력해 주세요", "Enter your one-liner"))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.45))
                }
            } else {
                EffectTextView(
                    text: clipText, font: fontChoice.swiftUIFont(size: baseFontSize),
                    lineSpacing: lineSpacing, alignment: tAlign,
                    color: textColor.color,
                    appearanceMode: appearanceMode,
                    decorEffect: decorEffect,
                    hasBorder: hasBorder,
                    flyDirection: flyDirection,
                    syntheticBoldStroke: fontChoice.syntheticBoldStroke(for: baseFontSize),
                    borderColor: hasBorder ? textColor.borderSwiftColor : .clear,
                    borderOffset: hasBorder ? max(0.8, baseFontSize * textColor.borderOffsetFactor) : 0,
                    isStaticPreview: isStaticPreview
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
        .padding(.horizontal, cardHeightOverride != nil ? 24 : 14)  // 9:16 = CALayer hPad 24 기준
        .padding(.top, captionTopPad)
        .padding(.bottom, captionBotPad)
        .offset(y: position == .center ? (captionBotPad - captionTopPad) / 2 : 0)
    }


    @ViewBuilder
    private var background: some View {
        if let photo = backgroundPhoto {
            let cH = cardHeightOverride ?? Self.cardHeight
            // 항상 카드를 완전히 채우도록 w/h 중 큰 스케일 사용 (레터박스 없음)
            let s: CGFloat = max(cH / photo.size.height, Self.cardWidth / photo.size.width)
            let iW = photo.size.width  * s
            let iH = photo.size.height * s
            let ox = -(cropOffsetX * max(0, iW - Self.cardWidth))
            Image(uiImage: photo)
                .resizable()
                .frame(width: iW, height: iH)
                .offset(x: ox)
                .frame(width: Self.cardWidth, height: cH)
                .clipped()
        } else {
            LinearGradient(
                colors: SkyPalette.colors(for: cardDate),
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(Color.black.opacity(0.12))
        }
    }

    @ViewBuilder
    private var genericChartOverlay: some View {
        let cardH = cardHeightOverride ?? Self.cardHeight
        let ps    = Self.cardWidth / 300.0   // always 1.0; kept for formula consistency
        let panW  = Self.cardWidth - 20 * ps
        let panH  = cardH * 0.264
        let lineColor: Color = Color(uiColor: chartOverlayType.lineUIColor)
        let title = AppLanguage.shared.s(chartOverlayType.chartTitleKo, chartOverlayType.chartTitleEn)
        let isElevation = (chartOverlayType == .elevation)

        if chartOverlayType == .intervals, !intervalSegments.isEmpty {
            intervalChartPanel(segments: intervalSegments, panW: panW)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
        } else if chartOverlayType == .splits {
            let filtered = chartSplits.filter { $0.distanceM >= 900 }
            if filtered.count >= 2 {
                splitsChartPanel(splits: filtered, panW: panW)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
        } else if let series = chartSeriesData[chartOverlayType], series.count >= 2 {
            let src   = series.filter { $0.value > 0 }
            let t0    = src.first?.offset  ?? 0
            let dt    = max(1.0, (src.last?.offset  ?? 1) - t0)
            let dtMin = dt / 60.0
            let bN    = 80
            let bSz   = dt / Double(bN)
            let buckets: [(id: Int, avg: Double, lo: Double, hi: Double)] = (0..<bN).compactMap { i in
                let bLo  = t0 + Double(i) * bSz
                let bHi  = bLo + bSz
                let vals = src.filter { $0.offset >= bLo && ($0.offset < bHi || (i == bN-1 && $0.offset <= t0+dt)) }.map(\.value)
                guard !vals.isEmpty else { return nil }
                return (i, vals.reduce(0,+)/Double(vals.count), vals.min()!, vals.max()!)
            }
            let avgAll = src.isEmpty ? 0.0 : src.map(\.value).reduce(0,+)/Double(src.count)
            let useRangeBar = [ChartOverlayType.strideLength, .verticalOscillation, .power, .groundContact].contains(chartOverlayType)
            let avgs = buckets.map(\.avg)
            let lo2 = (useRangeBar ? buckets.map(\.lo) : avgs).min() ?? 0
            let hi2 = (useRangeBar ? buckets.map(\.hi) : avgs).max() ?? 1
            let rng = max(hi2 - lo2, lo2 * 0.02)
            let yLo = max(0, lo2 - rng * (useRangeBar ? 0.4 : 0.6))
            let yHi = hi2 + rng * 0.2
            let yRange = max(1e-6, yHi - yLo)
            let fmtY: (Double) -> String = { v in
                isElevation ? String(format: "%.0fm", v)
                : abs(v) >= 100 ? String(format: "%.0f", v)
                : abs(v) >= 10  ? String(format: "%.1f", v)
                : String(format: "%.2f", v)
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12 * ps).fill(Color.black.opacity(0.30))
                VStack(alignment: .leading, spacing: 2 * ps) {
                    Text(title)
                        .font(.system(size: 10 * ps, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.top, 8 * ps)
                        .padding(.leading, 10 * ps)
                    Canvas { ctx, size in
                        guard !buckets.isEmpty || isElevation else { return }
                        let yLblW: CGFloat = 26 * ps
                        let xLblH: CGFloat = 11 * ps
                        let cw = max(1, size.width - yLblW)
                        let ch = max(1, size.height - xLblH)
                        func pty(_ v: Double) -> CGFloat { ch * CGFloat(1-(v-yLo)/yRange) }
                        let axisFont  = Font.system(size: 7*ps, design: .monospaced)
                        let axisColor = Color.white.opacity(0.55)
                        for i in 0..<4 {
                            let yVal = yLo + Double(i)*(yHi-yLo)/3.0
                            let yp   = pty(yVal)
                            var gp = Path(); gp.move(to: .init(x:0,y:yp)); gp.addLine(to: .init(x:cw,y:yp))
                            ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                            ctx.draw(Text(fmtY(yVal)).font(axisFont).foregroundColor(axisColor),
                                     at: .init(x:cw+2,y:yp), anchor: .leading)
                        }
                        for i in 0..<4 {
                            let frac = Double(i)/3.0
                            let xp   = CGFloat(frac)*cw
                            var gp = Path(); gp.move(to: .init(x:xp,y:0)); gp.addLine(to: .init(x:xp,y:ch))
                            ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                            let xTxt = AppLanguage.shared.isEnglish
                                ? String(format:"%.0fm", frac*dtMin)
                                : String(format:"%.0f분", frac*dtMin)
                            var anch: UnitPoint = .top
                            if i == 0 { anch = .topLeading } else if i == 3 { anch = .topTrailing }
                            ctx.draw(Text(xTxt).font(axisFont).foregroundColor(axisColor),
                                     at: .init(x:xp,y:ch+2), anchor: anch)
                        }
                        if isElevation {
                            let ptX: (Double) -> CGFloat = { CGFloat(($0-t0)/dt)*cw }
                            var fill = Path()
                            fill.move(to: .init(x:ptX(src[0].offset),y:ch))
                            fill.addLine(to: .init(x:ptX(src[0].offset),y:pty(src[0].value)))
                            for pt in src.dropFirst() { fill.addLine(to: .init(x:ptX(pt.offset),y:pty(pt.value))) }
                            fill.addLine(to: .init(x:ptX(src.last!.offset),y:ch)); fill.closeSubpath()
                            ctx.fill(fill, with: .color(lineColor.opacity(0.30)))
                            var line = Path()
                            line.move(to: .init(x:ptX(src[0].offset),y:pty(src[0].value)))
                            for pt in src.dropFirst() { line.addLine(to: .init(x:ptX(pt.offset),y:pty(pt.value))) }
                            ctx.stroke(line, with: .color(lineColor), lineWidth: 1.5)
                        } else {
                            let barGap = cw/CGFloat(bN); let barW = max(1.5,barGap-0.8)
                            let base   = pty(yLo)
                            for b in buckets {
                                let bx   = CGFloat(b.id)*barGap+(barGap-barW)/2
                                let topY = useRangeBar ? pty(b.hi) : pty(b.avg)
                                let botY = useRangeBar ? pty(b.lo) : base
                                ctx.fill(Path(CGRect(x:bx,y:topY,width:barW,height:max(1.5,botY-topY))),
                                         with: .color(lineColor.opacity(0.80)))
                            }
                            let avgY = pty(avgAll)
                            var dash = Path(); var x: CGFloat = 0
                            while x < cw { dash.move(to:.init(x:x,y:avgY)); dash.addLine(to:.init(x:min(x+4,cw),y:avgY)); x+=7 }
                            ctx.stroke(dash, with: .color(lineColor.opacity(0.60)), lineWidth: 1.2)
                        }
                    }
                    .padding(.horizontal, 10 * ps)
                    .padding(.bottom, 4 * ps)
                }
            }
            .frame(width: panW, height: panH)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        }
    }

    /// 편집화면(ClipTrimView.dataPreviewOverlay)과 동일한 스플릿 차트 — 행 구성 완전 일치.
    @ViewBuilder
    private func splitsChartPanel(splits: [SplitData], panW: CGFloat) -> some View {
        let ps: CGFloat = 1.0
        let rowH:   CGFloat = 7 * ps
        let titleH: CGFloat = 16 * ps
        let colHH:  CGFloat = 8  * ps
        let vPad:   CGFloat = 5  * ps

        let displaySplits: [SplitData] = splits.count > 21 ? splits.filter { $0.id % 2 == 0 } : splits
        let panH = titleH + colHH + CGFloat(displaySplits.count) * rowH + vPad * 2

        let paces      = displaySplits.map { $0.paceSecPerKm }
        let minP       = paces.min() ?? 0
        let maxP       = paces.max() ?? 1
        let rangeP     = max(1.0, maxP - minP)
        let avgP       = paces.reduce(0.0, +) / Double(paces.count)
        let fastestIdx = paces.indices.min(by: { paces[$0] < paces[$1] }) ?? 0

        let hasHR  = displaySplits.contains { $0.avgHeartRate != nil }
        let hasCad = displaySplits.contains { $0.avgCadence   != nil }
        let hasPwr = displaySplits.contains { $0.avgPower     != nil }

        let hPad:    CGFloat = 8  * ps
        let gap:     CGFloat = 3  * ps
        let kmW:     CGFloat = 18 * ps
        let colW:    CGFloat = 24 * ps
        let fixedW   = 2 * hPad + kmW + 2 * gap + colW
        let optW     = (hasHR  ? gap + colW : 0) + (hasCad ? gap + colW : 0) + (hasPwr ? gap + colW : 0)
        let barAreaW = max(20 * ps, panW - fixedW - optW)

        let zoneColor: (Int?) -> Color = { hrOpt in
            guard let hr = hrOpt,
                  let zid = hrZones.first(where: { hr >= $0.minBPM && hr <= $0.maxBPM })?.id
            else { return Color.red.opacity(0.70) }
            switch zid {
            case 1: return Color(hex: "4FC3F7")
            case 2: return Color(hex: "81C784")
            case 3: return Color(hex: "FFB74D")
            case 4: return Color(hex: "FF7043")
            default: return Color(hex: "E53935")
            }
        }

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12 * ps).fill(Color.black.opacity(0.30))
            VStack(alignment: .leading, spacing: 0) {
                Text(AppLanguage.shared.s("⚡ 스플릿", "⚡ Splits"))
                    .font(.system(size: 10 * ps, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(height: titleH)
                    .padding(.horizontal, hPad)
                // 열 제목 행
                HStack(spacing: gap) {
                    Spacer().frame(width: kmW)
                    Spacer().frame(width: barAreaW)
                    Text(AppLanguage.shared.s("페이스", "Pace"))
                        .font(.system(size: 5.5 * ps, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: colW, alignment: .trailing)
                    if hasHR {
                        Text(AppLanguage.shared.s("심박", "HR"))
                            .font(.system(size: 5.5 * ps, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: colW, alignment: .trailing)
                    }
                    if hasCad {
                        Text(AppLanguage.shared.s("케이던스", "Cad"))
                            .font(.system(size: 5.5 * ps, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: colW, alignment: .trailing)
                    }
                    if hasPwr {
                        Text(AppLanguage.shared.s("파워", "Pwr"))
                            .font(.system(size: 5.5 * ps, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: colW, alignment: .trailing)
                    }
                }
                .padding(.horizontal, hPad)
                .frame(height: colHH)
                ForEach(Array(displaySplits.enumerated()), id: \.element.id) { idx, split in
                    let isFastest = idx == fastestIdx
                    let pace = split.paceSecPerKm
                    let barFrac = CGFloat(0.28 + 0.72 * (pace - minP) / rangeP)
                    let barColor: Color = isFastest
                        ? Color(hex: "FFC74D")
                        : (pace <= avgP
                            ? Color(red: 0.486, green: 0.361, blue: 0.988).opacity(0.85)
                            : Color.white.opacity(0.45))
                    let zc = zoneColor(split.avgHeartRate)
                    HStack(spacing: gap) {
                        Text("\(split.id)k")
                            .font(.system(size: 6.5 * ps, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.80))
                            .frame(width: kmW, alignment: .trailing)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.10))
                                .frame(width: barAreaW, height: 3 * ps)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(barColor)
                                .frame(width: max(3, barAreaW * barFrac), height: 3 * ps)
                        }
                        .frame(width: barAreaW)
                        Text(split.formattedPace)
                            .font(.system(size: 7 * ps, weight: .bold, design: .monospaced))
                            .foregroundStyle(isFastest ? Color(hex: "FFC74D") : .white)
                            .frame(width: colW, alignment: .trailing)
                        if hasHR {
                            HStack(spacing: 1.5 * ps) {
                                Circle()
                                    .fill(split.avgHeartRate != nil ? zc : Color.clear)
                                    .frame(width: 3.5 * ps, height: 3.5 * ps)
                                Text(split.avgHeartRate.map { "\($0)" } ?? "—")
                                    .font(.system(size: 6.5 * ps, design: .monospaced))
                                    .foregroundStyle(split.avgHeartRate != nil ? zc : Color.white.opacity(0.45))
                            }
                            .frame(width: colW, alignment: .trailing)
                        }
                        if hasCad {
                            Text(split.avgCadence.map { "\($0)" } ?? "—")
                                .font(.system(size: 6.5 * ps, design: .monospaced))
                                .foregroundStyle(Color(hex: "60E8CC"))
                                .frame(width: colW, alignment: .trailing)
                        }
                        if hasPwr {
                            Text(split.avgPower.map { "\($0)" } ?? "—")
                                .font(.system(size: 6.5 * ps, design: .monospaced))
                                .foregroundStyle(Color(hex: "BEFA6A"))
                                .frame(width: colW, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, hPad)
                    .frame(height: rowH)
                }
                Spacer(minLength: vPad)
            }
        }
        .frame(width: panW, height: panH)
    }

    /// 참조 이미지(활동 상세)와 동일한 인터벌 테이블 패널
    @ViewBuilder
    private func intervalChartPanel(segments: [IntervalSegment], panW: CGFloat) -> some View {
        let ps: CGFloat  = 1.0
        let rowH: CGFloat  = 6.5 * ps
        let titleH: CGFloat = 16 * ps
        let colHH: CGFloat  = 8  * ps
        let vPad: CGFloat   = 5  * ps

        let displaySegs: [IntervalSegment] = segments.count > 10
            ? segments.filter { ($0.id % 2) == 1 }
            : segments
        let panH: CGFloat = titleH + colHH + CGFloat(displaySegs.count) * rowH + vPad * 2

        let hasHR  = displaySegs.contains { $0.avgHeartRate != nil }
        let hasCad = displaySegs.contains { $0.avgCadence   != nil }

        // 바 너비: duration 비례
        let maxDur = displaySegs.map(\.duration).max() ?? 1.0

        // "400m×5회" 요약 계산
        let workSegs = segments.filter { $0.stepLabel == "운동" }
        let summaryText: String? = {
            let dists = workSegs.compactMap(\.distanceM)
            guard dists.count == workSegs.count, !workSegs.isEmpty else { return nil }
            let snapped = dists.map { d -> Int in
                d >= 1000 ? Int((d / 100).rounded()) * 100 : Int((d / 50).rounded()) * 50
            }
            let counts = Dictionary(grouping: snapped, by: { $0 }).mapValues(\.count)
            guard let (dist, cnt) = counts.max(by: { $0.value < $1.value }), cnt > 0 else { return nil }
            let lbl = dist >= 1000
                ? (dist % 1000 == 0 ? "\(dist/1000)km" : String(format: "%.1fkm", Double(dist)/1000))
                : "\(dist)m"
            return AppLanguage.shared.s("\(lbl)×\(cnt)회", "\(lbl)×\(cnt)")
        }()

        let hPad:   CGFloat = 8  * ps
        let gap:    CGFloat = 3  * ps
        let lblW:   CGFloat = 30 * ps   // "2 운동" 스타일
        let colW:   CGFloat = 22 * ps
        let barAreaW = max(16 * ps, panW - 2 * hPad - lblW - gap - colW
                          - (hasHR  ? gap + colW : 0)
                          - (hasCad ? gap + colW : 0))

        let zoneColor: (Int?) -> Color = { hrOpt in
            guard let hr = hrOpt,
                  let zid = hrZones.first(where: { hr >= $0.minBPM && hr <= $0.maxBPM })?.id
            else { return Color.red.opacity(0.70) }
            switch zid {
            case 1: return Color(hex: "4FC3F7")
            case 2: return Color(hex: "81C784")
            case 3: return Color(hex: "FFB74D")
            case 4: return Color(hex: "FF7043")
            default: return Color(hex: "E53935")
            }
        }

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12 * ps).fill(Color.black.opacity(0.30))
            VStack(alignment: .leading, spacing: 0) {
                // 제목 행
                HStack(spacing: 4 * ps) {
                    Text(AppLanguage.shared.s("⚙ 인터벌", "⚙ Interval"))
                        .font(.system(size: 10 * ps, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    if let s = summaryText {
                        Text(s)
                            .font(.system(size: 7 * ps, weight: .regular))
                            .foregroundStyle(Color(red: 0.486, green: 0.361, blue: 0.988))
                    }
                    Spacer()
                }
                .frame(height: titleH)
                .padding(.horizontal, hPad)
                // 열 헤더
                HStack(spacing: gap) {
                    Spacer().frame(width: lblW)
                    Spacer().frame(width: barAreaW)
                    Text(AppLanguage.shared.s("페이스", "Pace"))
                        .font(.system(size: 5.5 * ps, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: colW, alignment: .trailing)
                    if hasHR {
                        Text(AppLanguage.shared.s("심박", "HR"))
                            .font(.system(size: 5.5 * ps, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: colW, alignment: .trailing)
                    }
                    if hasCad {
                        Text(AppLanguage.shared.s("케이던스", "Cad"))
                            .font(.system(size: 5.5 * ps, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: colW, alignment: .trailing)
                    }
                }
                .padding(.horizontal, hPad)
                .frame(height: colHH)
                // 데이터 행
                ForEach(displaySegs) { seg in
                    let isWork  = seg.stepLabel == "운동"
                    let barFrac = CGFloat(seg.duration / maxDur)
                    let minFrac: CGFloat = 0.10
                    let drawFrac = minFrac + (1 - minFrac) * barFrac
                    let barColor: Color = isWork
                        ? Color(red: 0.486, green: 0.361, blue: 0.988)
                        : Color(white: 0.30)
                    let shortLabel: String = {
                        switch seg.stepLabel {
                        case "준비운동": return AppLanguage.shared.s("준비", "WU")
                        case "운동":     return AppLanguage.shared.s("운동", "Work")
                        case "회복":     return AppLanguage.shared.s("회복", "Rec")
                        case "정리운동": return AppLanguage.shared.s("정리", "CD")
                        default:         return seg.stepLabel ?? "-"
                        }
                    }()
                    let zc = zoneColor(seg.avgHeartRate)
                    HStack(spacing: gap) {
                        // 번호 + 레이블
                        HStack(spacing: 2 * ps) {
                            Text("\(seg.id)")
                                .font(.system(size: 5.5 * ps, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.45))
                                .frame(width: 10 * ps, alignment: .trailing)
                            Text(shortLabel)
                                .font(.system(size: 6.5 * ps, weight: isWork ? .semibold : .regular))
                                .foregroundStyle(isWork
                                    ? Color(red: 0.686, green: 0.561, blue: 1.0)
                                    : .white.opacity(0.60))
                                .frame(width: lblW - 12 * ps, alignment: .leading)
                        }
                        .frame(width: lblW)
                        // 가로 바
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: barAreaW, height: 3 * ps)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(barColor.opacity(isWork ? 0.85 : 0.55))
                                .frame(width: max(3, barAreaW * drawFrac), height: 3 * ps)
                        }
                        .frame(width: barAreaW)
                        // 페이스
                        Text(seg.formattedPace ?? "—")
                            .font(.system(size: 6.5 * ps, weight: isWork ? .bold : .regular, design: .monospaced))
                            .foregroundStyle(isWork ? Color(hex: "FFC74D") : .white.opacity(0.65))
                            .frame(width: colW, alignment: .trailing)
                        // 심박 (옵션)
                        if hasHR {
                            HStack(spacing: 1.5 * ps) {
                                Circle()
                                    .fill(seg.avgHeartRate != nil ? zc : Color.clear)
                                    .frame(width: 3.5 * ps, height: 3.5 * ps)
                                Text(seg.avgHeartRate.map { "\($0)" } ?? "—")
                                    .font(.system(size: 6 * ps, design: .monospaced))
                                    .foregroundStyle(seg.avgHeartRate != nil ? zc : .white.opacity(0.45))
                            }
                            .frame(width: colW, alignment: .trailing)
                        }
                        // 케이던스 (옵션)
                        if hasCad {
                            Text(seg.avgCadence.map { "\($0)" } ?? "—")
                                .font(.system(size: 6 * ps, design: .monospaced))
                                .foregroundStyle(Color(hex: "60E8CC"))
                                .frame(width: colW, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, hPad)
                    .frame(height: rowH)
                }
                Spacer(minLength: vPad)
            }
        }
        .frame(width: panW, height: panH)
    }

    private var pdtChipsOverlay: some View {
        let items: [MetricItem] = [
            metricDistance  ? availableMetrics.first { $0.id == "distance" }  : nil,
            metricPace      ? availableMetrics.first { $0.id == "pace" }      : nil,
            metricTime      ? availableMetrics.first { $0.id == "time" }      : nil,
            metricHeartRate ? availableMetrics.first { $0.id == "heartrate" } : nil
        ].compactMap { $0 }
        let sz = pdtSizeLevel.scale  // 소=0.65 중=0.8 대=1.0
        return HStack(spacing: 6 * sz) {
            ForEach(items) { m in
                HStack(spacing: 3 * sz) {
                    Text(m.value)
                        .font(.system(size: 11 * sz, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    if !m.label.isEmpty {
                        Text(m.label)
                            .font(.system(size: 9 * sz))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 8 * sz)
                .padding(.vertical, 4 * sz)
                .background(RoundedRectangle(cornerRadius: 8 * sz).fill(m.color.opacity(0.30)))
                .overlay(RoundedRectangle(cornerRadius: 8 * sz)
                    .strokeBorder(m.color.opacity(0.55), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, cardHeightOverride != nil ? 20 : 14)
        .padding(.top, pdtPosition.isTop
            ? (cardHeightOverride != nil
                ? (!videoTitle.isEmpty && titleStyle.position.isTop
                    ? cardHeightOverride! * 0.28
                    : CardVisual.videoSafeTop * (Self.cardWidth / 1080) + 14)
                : 28)
            : 4)
        .padding(.bottom, pdtPosition.isBottom
            ? (cardHeightOverride != nil
                ? cardHeightOverride! * 0.06
                : (chartBottomReserved > 0 ? chartBottomReserved + 4 : 24))
            : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pdtPosition.alignment)
        .allowsHitTesting(false)
    }

    private var wordmark: some View {
        MIMOWordmark(size: 11)
            .cardTextShadow()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 24)   // CALayer hPad = 24 기준
            .padding(.top, 32)
    }

    // captionMode 전용: 워드마크 + 날짜를 단일 HStack으로, 14pt 위 여백 (스탬프·플레이서블 스토리와 동일)
    private var captionWordmarkRow: some View {
        HStack {
            MIMOWordmark(size: 11)
                .cardTextShadow()
            if showDate {
                Spacer()
                Text(cardDate.oneLinerDateString)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SizeAudit (DEBUG)
//
// 3폰트 × 4사이즈 × 3애니메이션에서 정착 시 cap height가 동일한지 검증.
// 앱 기동 후 콘솔에서 "[SizeAudit]" 검색 → 같은 sizeLevel의 capH(px)가 ±1px 이내여야 함.
// 실행: OneLinerCard 프리뷰 or 임의 onAppear에서 OneLinerSizeAudit.run() 호출.

#if DEBUG
enum OneLinerSizeAudit {
    static func run(screenScale: CGFloat = 3) {
        // 애니메이션 독립성: 최종 정착 scale은 항상 1.0.
        // typing=offset 없음 / fade=opacity만 / flyIn=offset만 → 잔여 scale 변형 없음.
        let animLabel = ["typing", "fade", "flyIn"]
        print("[SizeAudit] === 폰트 × 사이즈 capH 정착값 (px @ \(Int(screenScale))x) ===")
        print("[SizeAudit] 애니메이션(\(animLabel.joined(separator: "/"))): 최종 scale=1.0, 정착값 동일 여부 확인")

        // capH@30pt 실측값 (CoreText)
        let capH30: [OneLinerFont: CGFloat] = [
            .pen:         20.22,
            .gothic:      21.45,
            .blackGothic: 21.03,
        ]

        for level in TextSizeLevel.allCases {
            var row = "[SizeAudit] \(level.chipLabel)(\(level.rawValue)): "
            var capHValues: [CGFloat] = []
            for font in OneLinerFont.allCases {
                let pt    = OneLinerFont.basePt * font.sizeScale * level.scale
                let capHpt = (capH30[font] ?? 20.22) * (pt / 30.0)
                let capHpx = capHpt * screenScale
                capHValues.append(capHpx)
                row += "\(font.rawValue)=\(String(format: "%.1f", capHpx))px  "
            }
            let spread = (capHValues.max() ?? 0) - (capHValues.min() ?? 0)
            row += spread <= 1.0 ? "✓" : "⚠️ spread=\(String(format: "%.1f", spread))px"
            print(row)
        }
    }
}
#endif

// MARK: - Date helper

extension Date {
    var oneLinerDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy. M. d."
        return f.string(from: self)
    }
}

// MARK: - Previews

private func _registerFonts() { FontLoader.registerBundledFonts() }

private let _previewActivity = Activity(
    id: UUID(),
    type: .running,
    date: Date(),
    duration: 3724,
    distance: 6010,
    calories: nil,
    avgHeartRate: nil
)

#Preview("펜 / 그라데이션 배경") {
    let _ = _registerFonts()
    #if DEBUG
    let _ = OneLinerSizeAudit.run()
    #endif
    OneLinerCard(
        activity: _previewActivity,
        text: "꽃밭을 달리는데\n난 땀밭",
        position: .center,
        textColor: .white,
        fontChoice: .pen
    )
    .frame(width: 300, height: 375)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .preferredColorScheme(.dark)
}

#Preview("개구 / 골드 / 상단") {
    let _ = _registerFonts()
    OneLinerCard(
        activity: _previewActivity,
        text: "꽃밭을 달리는데\n난 땀밭",
        position: .top,
        textColor: .gold,
        fontChoice: .gothic
    )
    .frame(width: 300, height: 375)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .preferredColorScheme(.dark)
}

#Preview("블랙고딕 / 하단 좌측") {
    let _ = _registerFonts()
    OneLinerCard(
        activity: _previewActivity,
        text: "꽃밭을 달리는데\n난 땀밭",
        position: .bottomLeading,
        textColor: .violet,
        fontChoice: .blackGothic
    )
    .frame(width: 300, height: 375)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .preferredColorScheme(.dark)
}
