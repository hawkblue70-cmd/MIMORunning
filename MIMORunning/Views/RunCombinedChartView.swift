import SwiftUI

// MARK: - RunCombinedChartView

struct RunCombinedChartView: View {
    let data: RunChartData
    let enabledLayers: Set<RunChartLayer>
    var chartHeight: CGFloat = 190
    /// When non-nil, that layer is shown at full opacity; all others fade to 0.15.
    var soloLayer: RunChartLayer? = nil

    @State private var selectedKm: Double? = nil

    private let padL: CGFloat = 6
    private let padR: CGFloat = 40   // reserved for right-side end-point labels
    private let padT: CGFloat = 16
    private let padB: CGFloat = 18

    var body: some View {
        let activeLayers = data.availableLayers.filter { enabledLayers.contains($0) }
        if activeLayers.isEmpty {
            emptyPlaceholder
        } else {
            GeometryReader { geo in
                let rect = CGRect(
                    x: padL, y: padT,
                    width: geo.size.width - padL - padR,
                    height: chartHeight - padT - padB
                )
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        drawZoneBands(ctx: ctx, rect: rect, activeLayers: activeLayers)
                        drawWorkSegments(ctx: ctx, rect: rect)
                        drawElevation(ctx: ctx, rect: rect, activeLayers: activeLayers)
                        drawPaceBars(ctx: ctx, rect: rect)
                        drawLines(ctx: ctx, rect: rect, activeLayers: activeLayers)
                        drawFadeMarker(ctx: ctx, rect: rect)
                        drawEndLabels(ctx: ctx, rect: rect, activeLayers: activeLayers)
                        drawPaceLabels(ctx: ctx, rect: rect)
                        drawXAxis(ctx: ctx, rect: rect)
                        if let km = selectedKm {
                            drawCrosshair(ctx: ctx, rect: rect, km: km)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                guard data.totalKm > 0 else { return }
                                let raw = (v.location.x - rect.minX) / rect.width * data.totalKm
                                selectedKm = max(0, min(data.totalKm, raw))
                            }
                            .onEnded { v in
                                guard data.totalKm > 0 else { return }
                                let raw = (v.location.x - rect.minX) / rect.width * data.totalKm
                                if raw < 0 || raw > data.totalKm { selectedKm = nil }
                            }
                    )

                    if let km = selectedKm {
                        tooltipView(km: km, rect: rect, totalWidth: geo.size.width, activeLayers: activeLayers)
                    }
                }
            }
            .frame(height: chartHeight)
        }
    }

    // MARK: - Empty state

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("표시할 데이터가 없어요")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: chartHeight)
    }

    // MARK: - Coordinate helpers

    private func xFor(km: Double, in rect: CGRect) -> CGFloat {
        guard data.totalKm > 0 else { return rect.minX }
        return rect.minX + CGFloat(km / data.totalKm) * rect.width
    }

    /// Maps norm (0–1) into a vertical band.
    /// band.top / band.bottom are fractions of chart height (0 = top, 1 = bottom).
    private func yForBand(norm: Double, band: (top: Double, bottom: Double), in rect: CGRect) -> CGFloat {
        let t = band.top + (1.0 - norm) * (band.bottom - band.top)
        return rect.minY + CGFloat(t) * rect.height
    }

    /// Line layers use their own band unless ≤2 line layers are active — then full height (0.08, 0.92).
    private func lineBand(for layer: RunChartLayer, activeLayers: [RunChartLayer]) -> (top: Double, bottom: Double) {
        let lineCount = activeLayers.filter { $0 != .pace && $0 != .elevation }.count
        return lineCount <= 2 ? (0.08, 0.92) : layer.band
    }

    // MARK: - Catmull-Rom smooth path

    private func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }
        path.move(to: points[0])
        guard points.count >= 2 else { return path }
        if points.count == 2 { path.addLine(to: points[1]); return path }

        // Duplicate endpoints so boundary segments get proper tangents
        let pts = [points[0]] + points + [points[points.count - 1]]
        path = Path()
        path.move(to: pts[1])
        for i in 1..<(pts.count - 2) {
            let p0 = pts[i - 1], p1 = pts[i], p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6.0,
                              y: p1.y + (p2.y - p0.y) / 6.0)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6.0,
                              y: p2.y - (p3.y - p1.y) / 6.0)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
    }

    // MARK: - Fade start marker

    private func drawFadeMarker(ctx: GraphicsContext, rect: CGRect) {
        guard let km = data.fadeStartKm, data.totalKm > 0 else { return }
        let x = xFor(km: km, in: rect)
        var path = Path()
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        ctx.stroke(path, with: .color(.orange.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        ctx.draw(
            Text("감속 시작").font(.system(size: 8)).foregroundStyle(Color.orange.opacity(0.7)),
            at: CGPoint(x: x + 3, y: rect.minY + 2), anchor: .topLeading
        )
    }

    // MARK: - Work segment bands

    private func drawWorkSegments(ctx: GraphicsContext, rect: CGRect) {
        guard !data.workSegments.isEmpty, data.totalKm > 0 else { return }
        for seg in data.workSegments {
            let x1 = xFor(km: seg.startKm, in: rect)
            let x2 = xFor(km: seg.endKm,   in: rect)
            guard x2 > x1 else { continue }
            ctx.fill(Path(CGRect(x: x1, y: rect.minY, width: x2 - x1, height: rect.height)),
                     with: .color(.white.opacity(0.05)))
        }
    }

    // MARK: - HR zone bands (aligned to HR layer band)

    private func drawZoneBands(ctx: GraphicsContext, rect: CGRect, activeLayers: [RunChartLayer]) {
        guard !data.hrZoneBands.isEmpty, activeLayers.contains(.heartRate) else { return }
        let range = data.hrMax - data.hrMin
        guard range > 0 else { return }

        let hrBand = lineBand(for: .heartRate, activeLayers: activeLayers)
        for band in data.hrZoneBands {
            let lo   = (Double(band.lowerBPM) - data.hrMin) / range
            let hi   = (Double(band.upperBPM) - data.hrMin) / range
            let yTop = yForBand(norm: hi, band: hrBand, in: rect)
            let yBot = yForBand(norm: lo, band: hrBand, in: rect)
            let h    = max(0, yBot - yTop)
            let idx  = max(0, min(4, band.zone - 1))
            ctx.fill(Path(CGRect(x: rect.minX, y: yTop, width: rect.width, height: h)),
                     with: .color(Theme.hrZoneColors[idx].opacity(0.028)))
            ctx.draw(
                Text("Z\(band.zone)").font(.system(size: 6.5)).foregroundStyle(Color.secondary.opacity(0.5)),
                at: CGPoint(x: rect.minX + 4, y: (yTop + yBot) / 2), anchor: .leading
            )
        }
    }

    // MARK: - Elevation fill (Catmull-Rom)

    private func drawElevation(ctx: GraphicsContext, rect: CGRect, activeLayers: [RunChartLayer]) {
        guard enabledLayers.contains(.elevation),
              let series = data.series[.elevation], !series.isEmpty else { return }

        let band  = RunChartLayer.elevation.band
        let cgPts = series.points.map { p in
            CGPoint(x: xFor(km: p.km, in: rect), y: yForBand(norm: p.norm, band: band, in: rect))
        }

        var curvePath = smoothPath(points: cgPts)
        if let last = cgPts.last, let first = cgPts.first {
            curvePath.addLine(to: CGPoint(x: last.x,  y: rect.maxY))
            curvePath.addLine(to: CGPoint(x: first.x, y: rect.maxY))
            curvePath.closeSubpath()
        }

        let opacity: Double
        if let solo = soloLayer { opacity = (solo == .elevation) ? 0.20 : 0.04 }
        else                    { opacity = RunChartLayer.elevation.opacity }
        ctx.fill(curvePath, with: .color(Theme.elevation.opacity(opacity)))
    }

    // MARK: - Pace bars

    private func drawPaceBars(ctx: GraphicsContext, rect: CGRect) {
        guard enabledLayers.contains(.pace),
              let series = data.series[.pace], !series.isEmpty else { return }

        let baseOp: Double      = soloLayer == nil ? 0.20 : (soloLayer == .pace ? 0.28 : 0.06)
        let highlightOp: Double = soloLayer == nil ? 0.38 : (soloLayer == .pace ? 0.38 : 0.06)

        let pts = series.points
        for (i, p) in pts.enumerated() {
            let leftKm  = i == 0             ? 0            : (pts[i-1].km + p.km) / 2
            let rightKm = i == pts.count - 1 ? data.totalKm : (p.km + pts[i+1].km) / 2
            let fullW   = xFor(km: rightKm, in: rect) - xFor(km: leftKm, in: rect)
            let barW    = fullW * 0.62
            let barH    = CGFloat(p.norm) * rect.height
            let cx      = xFor(km: p.km, in: rect)
            let barRect = CGRect(x: cx - barW / 2, y: rect.maxY - barH, width: barW, height: barH)
            let op      = (i == series.minIndex || i == series.maxIndex) ? highlightOp : baseOp
            ctx.fill(Path(roundedRect: barRect, cornerRadius: 1), with: .color(Theme.pace.opacity(op)))
        }
    }

    // MARK: - Line layers (Catmull-Rom, band-aware, solo-aware)

    private func drawLines(ctx: GraphicsContext, rect: CGRect, activeLayers: [RunChartLayer]) {
        for layer in [RunChartLayer.heartRate, .cadence, .power] {
            guard activeLayers.contains(layer),
                  let series = data.series[layer], !series.isEmpty else { continue }

            let band  = lineBand(for: layer, activeLayers: activeLayers)
            let cgPts = series.points.map { p in
                CGPoint(x: xFor(km: p.km, in: rect), y: yForBand(norm: p.norm, band: band, in: rect))
            }
            let path  = smoothPath(points: cgPts)

            let effectiveOp: Double
            if let solo = soloLayer { effectiveOp = (layer == solo) ? 1.0 : 0.15 }
            else                    { effectiveOp = layer.opacity }

            if case .line(let w) = layer.drawStyle {
                ctx.stroke(path, with: .color(layer.color.opacity(effectiveOp)),
                           style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            }
        }
    }

    // MARK: - Right-side end-point value labels

    private func drawEndLabels(ctx: GraphicsContext, rect: CGRect, activeLayers: [RunChartLayer]) {
        let lineLayers = [RunChartLayer.heartRate, .cadence, .power].filter { activeLayers.contains($0) }
        guard !lineLayers.isEmpty else { return }

        struct Slot { let layer: RunChartLayer; let text: String; var y: CGFloat }

        var slots: [Slot] = lineLayers.compactMap { layer in
            guard let series = data.series[layer], !series.isEmpty,
                  let lastPt = series.points.last else { return nil }
            let band = lineBand(for: layer, activeLayers: activeLayers)
            return Slot(layer: layer,
                        text: layer.formatted(series.lastValue),
                        y: yForBand(norm: lastPt.norm, band: band, in: rect))
        }

        // Sort top-to-bottom, nudge overlapping labels downward
        slots.sort { $0.y < $1.y }
        let minGap: CGFloat = 10
        for i in 1..<slots.count {
            if slots[i].y - slots[i-1].y < minGap {
                slots[i].y = slots[i-1].y + minGap
            }
        }

        let labelX = rect.maxX + 4
        for slot in slots {
            ctx.draw(
                Text(slot.text).font(.system(size: 8, weight: .medium)).foregroundStyle(slot.layer.color),
                at: CGPoint(x: labelX, y: slot.y), anchor: .leading
            )
        }
    }

    // MARK: - Pace fastest / slowest labels

    private func drawPaceLabels(ctx: GraphicsContext, rect: CGRect) {
        guard enabledLayers.contains(.pace),
              let series = data.series[.pace], !series.isEmpty else { return }

        let pts = series.points
        func draw(index: Int?, label: String, color: Color) {
            guard let idx = index, idx < pts.count else { return }
            let p  = pts[idx]
            let cx = max(rect.minX + 12, min(rect.maxX - 12, xFor(km: p.km, in: rect)))
            ctx.draw(
                Text("\(RunChartLayer.pace.formatted(p.value)) \(label)")
                    .font(.system(size: 8, weight: .medium)).foregroundStyle(color),
                at: CGPoint(x: cx, y: rect.maxY - CGFloat(p.norm) * rect.height - 3),
                anchor: .bottom
            )
        }
        draw(index: series.minIndex, label: "최고", color: Theme.pace)
        draw(index: series.maxIndex, label: "최저", color: .orange)
    }

    // MARK: - X axis ticks

    private func drawXAxis(ctx: GraphicsContext, rect: CGRect) {
        guard data.totalKm > 0 else { return }
        let km = data.totalKm
        func label(_ v: Double) -> String {
            if v == 0 { return "0" }
            let r = v.rounded()
            return v == r ? "\(Int(r))km" : String(format: "%.1fkm", v)
        }
        let ticks: [(km: Double, anchor: UnitPoint)] = [
            (0,      .topLeading),
            (km / 2, .top),
            (km,     .topTrailing)
        ]
        for tick in ticks {
            ctx.draw(
                Text(label(tick.km)).font(.system(size: 7)).foregroundStyle(Color.secondary),
                at: CGPoint(x: xFor(km: tick.km, in: rect), y: rect.maxY + 4),
                anchor: tick.anchor
            )
        }
    }

    // MARK: - Crosshair

    private func drawCrosshair(ctx: GraphicsContext, rect: CGRect, km: Double) {
        let x = xFor(km: km, in: rect)
        var path = Path()
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        ctx.stroke(path, with: .color(Color.white.opacity(0.25)), lineWidth: 1)
    }

    // MARK: - Tooltip

    @ViewBuilder
    private func tooltipView(
        km: Double, rect: CGRect, totalWidth: CGFloat, activeLayers: [RunChartLayer]
    ) -> some View {
        let tipW: CGFloat = 126
        let rawX     = xFor(km: km, in: rect)
        let leftEdge = max(padL, min(totalWidth - padR - tipW, rawX - tipW / 2))

        VStack(alignment: .leading, spacing: 3) {
            Text(String(format: "%.1fkm", km))
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
            ForEach(activeLayers, id: \.id) { layer in
                if let val = nearestValue(km: km, layer: layer) {
                    HStack(spacing: 4) {
                        Circle().fill(layer.color).frame(width: 6, height: 6)
                        Text("\(layer.shortLabel) \(layer.formatted(val)) \(layer.unit)")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(8)
        .frame(width: tipW, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .offset(x: leftEdge, y: padT)
        .allowsHitTesting(false)
    }

    private func nearestValue(km: Double, layer: RunChartLayer) -> Double? {
        guard let series = data.series[layer], !series.isEmpty else { return nil }
        return series.points.min(by: { abs($0.km - km) < abs($1.km - km) })?.value
    }
}

// MARK: - Preview

#Preview {
    let totalKm = 10.0
    let n = 100

    let hrPoints: [RunChartPoint] = (0..<n).map { i in
        let km   = Double(i) / Double(n - 1) * totalKm
        let norm = 0.4 + 0.35 * sin(Double(i) / 10.0)
        return RunChartPoint(km: km, value: 140 + norm * 30, norm: norm)
    }
    let hrSeries = RunChartSeries(layer: .heartRate, points: hrPoints,
                                  minValue: 130, maxValue: 175, avgValue: 152,
                                  lastValue: 158)

    let pacePoints: [RunChartPoint] = (0..<10).map { i in
        let km   = Double(i) + 0.5
        let raw  = 370.0 + Double(i) * 4 - (i == 3 ? 30 : 0) + (i == 8 ? 25 : 0)
        let norm = 1.0 - (raw - 340) / 50.0
        return RunChartPoint(km: km, value: raw, norm: max(0.1, min(1, norm)))
    }
    let paceSeries = RunChartSeries(layer: .pace, points: pacePoints,
                                    minValue: 340, maxValue: 420, avgValue: 370,
                                    minIndex: 3, maxIndex: 8, lastValue: 395)

    let elevPoints: [RunChartPoint] = (0..<n).map { i in
        let km   = Double(i) / Double(n - 1) * totalKm
        let norm = 0.1 + 0.45 * abs(sin(Double(i) / 15.0))
        return RunChartPoint(km: km, value: 50 + norm * 120, norm: norm)
    }
    let elevSeries = RunChartSeries(layer: .elevation, points: elevPoints,
                                    minValue: 50, maxValue: 170, avgValue: 95)

    let cadencePoints: [RunChartPoint] = (0..<n).map { i in
        let km   = Double(i) / Double(n - 1) * totalKm
        let norm = 0.55 + 0.2 * cos(Double(i) / 8.0)
        return RunChartPoint(km: km, value: 160 + norm * 20, norm: norm)
    }
    let cadenceSeries = RunChartSeries(layer: .cadence, points: cadencePoints,
                                       minValue: 155, maxValue: 185, avgValue: 168,
                                       lastValue: 172)

    let chartData = RunChartData(
        totalKm: totalKm,
        series: [.heartRate: hrSeries, .pace: paceSeries,
                 .elevation: elevSeries, .cadence: cadenceSeries],
        hrZoneBands: [
            (zone: 1, lowerBPM: 100, upperBPM: 120),
            (zone: 2, lowerBPM: 120, upperBPM: 140),
            (zone: 3, lowerBPM: 140, upperBPM: 160),
            (zone: 4, lowerBPM: 160, upperBPM: 175)
        ],
        hrMin: 100, hrMax: 175,
        availableLayers: [.heartRate, .pace, .elevation, .cadence]
    )

    return ZStack {
        Theme.background.ignoresSafeArea()
        RunCombinedChartView(data: chartData, enabledLayers: Set(RunChartLayer.allCases))
            .padding(.horizontal, 16)
    }
    .preferredColorScheme(.dark)
}
