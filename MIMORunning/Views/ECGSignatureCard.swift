import SwiftUI

// MARK: - ECGSignatureCard
// Data source : ECGWaveform (pace or HR from this workout's HealthKit series).
// Reused      : CardVisual.cardTextShadow / cardLargeTextShadow.
// §7 compliance: waveform is intra-workout relative normalization — no absolute fitness judgment.
// Accent      : .violet (default) → violet gradient; .gold → gold gradient + white peak dot;
//               .none → solid white line + gold peak dot.

/// "심전도 시그니처" share card — 300 × 375 pt dark card.
/// Waveform (pace or HR) drawn as accent-coloured line in a centred 35%-height band.
struct ECGSignatureCard: View {
    let activity: Activity
    let waveform: ECGWaveform
    var weather:  WeatherSnapshot? = nil
    var shoeName: String?          = nil
    var accent:   CardAccent       = .violet

    static let cardWidth:  CGFloat = 300
    static let cardHeight: CGFloat = 375

    // Waveform band: vertical centre of card, 35 % of height.
    // bandTop == bandBottom section height (symmetric).
    private var bandHeight: CGFloat { Self.cardHeight * 0.35 }
    private var bandTop:    CGFloat { (Self.cardHeight - bandHeight) / 2 }

    // Waveform x-space: 6% inset on each side so the line never touches card edges.
    // Grid background ignores the inset and fills the full card.
    private var waveInset: CGFloat { Self.cardWidth * 0.06 }          // 18 pt

    // Peak indicator position in card-space coordinates (respects waveInset)
    private var peakX: CGFloat {
        let drawW = Self.cardWidth - 2 * waveInset
        return waveInset + CGFloat(waveform.peakIndex) / CGFloat(ECGWaveform.bucketCount - 1) * drawW
    }
    private var peakY: CGFloat {
        guard waveform.peakIndex < waveform.points.count else { return bandTop }
        return bandTop + bandHeight * (1.0 - waveform.points[waveform.peakIndex])
    }

    // Badge placement: above the dot normally; left/right when peak is near a card edge.
    // Uses a conservative half-width estimate (30 pt) to keep the badge inside 12 pt margins.
    private var badgePlacement: (x: CGFloat, y: CGFloat) {
        let idx   = waveform.peakIndex
        let total = ECGWaveform.bucketCount   // 100
        let halfW: CGFloat = 40              // safe upper bound for badge half-width (value text widens badge)
        let dotR:  CGFloat = 3
        let gap:   CGFloat = 5
        if idx >= Int(Double(total) * 0.9) {
            // Near right edge → badge to the left, vertically centred on dot
            return (x: peakX - dotR - gap - halfW, y: peakY)
        } else if idx < Int(Double(total) * 0.1) {
            // Near left edge → badge to the right, vertically centred on dot
            return (x: peakX + dotR + gap + halfW, y: peakY)
        } else {
            // Above the dot; clamp x so badge stays ≥ 12 pt from card edges
            let minX = 12.0 + halfW
            let maxX = Self.cardWidth - 12.0 - halfW
            return (x: max(minX, min(maxX, peakX)), y: max(20, peakY - 16))
        }
    }

    // Peak value formatted for display: "172" for HR, "5'02"" for pace.
    private var peakValueText: String {
        switch waveform.source {
        case .heartRate:
            return "\(Int(waveform.peakValue.rounded()))"
        case .pace:
            let secs = Int(waveform.peakValue.rounded())
            return "\(secs / 60)'\(String(format: "%02d", secs % 60))\""
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(hex: "0D0D12")

            // Full-card Canvas: ECG grid + waveform + peak dot
            Canvas { ctx, size in
                // 1. Grid (#26262E @ 30 %, spacing = cardWidth / 12 ≈ 25 pt)
                let spacing = size.width / 12
                var gridPath = Path()
                var gx: CGFloat = spacing
                while gx < size.width {
                    gridPath.move(to: CGPoint(x: gx, y: 0))
                    gridPath.addLine(to: CGPoint(x: gx, y: size.height))
                    gx += spacing
                }
                var gy: CGFloat = spacing
                while gy < size.height {
                    gridPath.move(to: CGPoint(x: 0, y: gy))
                    gridPath.addLine(to: CGPoint(x: size.width, y: gy))
                    gy += spacing
                }
                ctx.stroke(gridPath, with: .color(Color(hex: "26262E").opacity(0.30)), lineWidth: 0.5)

                // 2. Waveform in the centre 35 % band (6% inset on each side)
                let pts  = waveform.points
                guard pts.count > 1 else { return }
                let bH    = size.height * 0.35
                let bTop  = (size.height - bH) / 2
                let inset = size.width * 0.06
                let drawW = size.width - 2 * inset
                var wavePath = Path()
                let xStep = drawW / CGFloat(pts.count - 1)
                for (i, v) in pts.enumerated() {
                    let px = inset + CGFloat(i) * xStep
                    let py = bTop + bH * (1.0 - v)
                    if i == 0 { wavePath.move(to: CGPoint(x: px, y: py)) }
                    else       { wavePath.addLine(to: CGPoint(x: px, y: py)) }
                }

                // Glow + peak dot colour are accent-driven
                let glowColor: Color
                let peakDotColor: Color
                switch accent {
                case .gold:
                    glowColor    = Color(hex: "FFC74D").opacity(0.25)
                    peakDotColor = .white
                case .none:
                    glowColor    = Color.white.opacity(0.18)
                    peakDotColor = Color(hex: "FFC74D")
                case .violet:
                    glowColor    = Color(hex: "9B7DFF").opacity(0.25)
                    peakDotColor = Color(hex: "FFC74D")
                }
                ctx.stroke(wavePath, with: .color(glowColor),
                           style: StrokeStyle(lineWidth: 9, lineJoin: .round))

                // Main line: solid white for .none; horizontal gradient for .violet / .gold
                if accent == .none {
                    ctx.stroke(wavePath, with: .color(.white),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                } else {
                    let c1 = accent == .gold ? Color(hex: "FFC74D") : Color(hex: "9B7DFF")
                    let c2 = accent == .gold ? Color(hex: "F2A33C") : Color(hex: "6845E8")
                    let strokedPath = wavePath.strokedPath(
                        StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    ctx.drawLayer { layer in
                        layer.clip(to: strokedPath)
                        layer.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .linearGradient(
                                Gradient(colors: [c1, c2]),
                                startPoint: CGPoint(x: 0,          y: size.height / 2),
                                endPoint:   CGPoint(x: size.width, y: size.height / 2)
                            )
                        )
                    }
                }

                // 3. Peak dot + glow (x uses same inset/drawW as waveform)
                let n  = CGFloat(ECGWaveform.bucketCount - 1)
                let pX = inset + CGFloat(waveform.peakIndex) / n * drawW
                let pY = bTop + bH * (1.0 - pts[waveform.peakIndex])
                ctx.fill(Path(ellipseIn: CGRect(x: pX - 8, y: pY - 8, width: 16, height: 16)),
                         with: .color(peakDotColor.opacity(0.35)))
                ctx.fill(Path(ellipseIn: CGRect(x: pX - 3, y: pY - 3, width: 6,  height: 6)),
                         with: .color(peakDotColor))
            }
            .allowsHitTesting(false)

            // Text content laid out in three vertical sections
            VStack(spacing: 0) {
                // ── Top section: wordmark + distance ───────────────────────
                // ⚠ frame(maxWidth:)에 alignment가 없으면 이 VStack이 가장 넓은 자식(거리) 폭으로 줄어든 채
                //   카드 가운데에 놓여 로고가 왼쪽 여백(20pt)이 아니라 카드 중앙 근처로 밀려났다(실기기).
                //   로고는 다른 카드와 같이 좌상단 20pt, 거리는 지금처럼 가운데.
                VStack(alignment: .leading, spacing: 0) {
                    wordmarkRow
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                    Spacer()
                    distanceView
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: bandTop)

                // ── Middle: waveform band (Canvas draws here) ───────────────
                Color.clear.frame(height: bandHeight)

                // ── Bottom section: stats + date ────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    statsRow
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    Spacer()
                    bottomRow
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
                .frame(height: bandTop)
            }
            .frame(maxWidth: .infinity)

            // Source label: top-left of waveform band, 8pt above the band
            Text(waveform.source == .heartRate ? "HEART RATE" : "PACE")
                .font(.system(size: 9, weight: .medium))
                .tracking(3)
                .foregroundStyle(Color(hex: "6E6E78"))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 20)
                .padding(.top, bandTop - 20)
                .allowsHitTesting(false)

            // Peak badge: above dot normally; left/right when near a card edge
            let p = badgePlacement
            peakBadge
                .position(x: p.x, y: p.y)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Subviews

    private var wordmarkRow: some View {
        MIMOWordmark(size: 11, onMediaCard: true)
    }

    @ViewBuilder
    private var distanceView: some View {
        let km      = activity.distance / 1000
        let distStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Text(distStr)
                .font(.system(size: 64, weight: .bold).width(.condensed))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("km")
                .font(.system(size: 20, weight: .medium).width(.condensed))
                .foregroundStyle(Color(hex: "EDEDED").opacity(0.8))
        }
        .cardLargeTextShadow()
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: activity.formattedDuration, label: AppLanguage.shared.s("시간", "TIME"))
            if let pace = activity.formattedPace {
                statDivider
                statCell(value: pace, label: "/km")
            }
            if let hr = activity.avgHeartRate {
                statDivider
                statCell(value: "\(hr)", label: "bpm")
            }
        }
        .cardTextShadow()
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .semibold).width(.condensed))
                .foregroundStyle(Color(hex: "EDEDED"))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Color(hex: "6E6E78"))
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color(hex: "6E6E78").opacity(0.4))
            .frame(width: 0.5, height: 24)
            .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var bottomRow: some View {
        HStack(spacing: 3) {
            Text(activity.date.cardDateString)
            Text(activity.date.weekdayString).foregroundStyle(Theme.time)
            Text(activity.date.cardTimeString)
            if let w = weather {
                Text("·").opacity(0.4)
                Image(systemName: w.systemIcon).font(.system(size: 8))
                Text(activity.temperatureC.map { String(format: "%.0f°C", $0) } ?? w.formattedTemp).font(.system(size: 8, weight: .medium))
            }
            if let shoe = shoeName {
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "shoe.fill").font(.system(size: 8))
                    Text(shoe).font(.system(size: 9, weight: .medium)).lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.75))
            }
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.60))
        .cardTextShadow()
    }

    private var peakBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 7, weight: .bold))
            Text(AppLanguage.shared.s("최고 \(peakValueText)", "BEST \(peakValueText)"))
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(hex: "FFC74D"))
        .clipShape(Capsule())
    }
}
