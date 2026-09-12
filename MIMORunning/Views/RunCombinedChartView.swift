import SwiftUI

// MARK: - RunCombinedChartView

struct RunCombinedChartView: View {
    let data: RunChartData
    let enabledLayers: Set<RunChartLayer>
    var chartHeight: CGFloat = 190
    /// When non-nil, that layer is shown at full opacity; all others fade to 0.15.
    var soloLayer: RunChartLayer? = nil
    /// 0–1 fraction of total distance. When non-nil, chart draws progressively up to this point.
    var playProgress: Double? = nil
    /// Called at the start of any drag gesture (used to stop playback from parent).
    var onInteraction: (() -> Void)? = nil
    /// Minimum vertical gap (pt) between right-side end-point labels. Default 11, use 9 when chart is short.
    var endLabelMinGap: CGFloat = 11

    @State private var selectedKm: Double? = nil

    @Environment(\.shareChartPalette) private var p

    private let padL: CGFloat = 26   // Z1–Z5 labels at x=0–22; plot starts at 26
    private var padR: CGFloat { playProgress != nil ? 8 : 40 }  // collapse right pad during playback (no end labels)
    private let padT: CGFloat = 26   // increased from 16: room for scrubber label above chart rect
    private let padB: CGFloat = 28   // 페이스 라벨 한 줄 + 시간·거리 한 줄 (예전 세 줄일 때 38)

    var body: some View {
        // 페이스 막대는 토글 대상이 아니다(타일 없음) — 데이터가 있으면 항상 그린다
        let activeLayers = data.availableLayers.filter { !$0.hasTile || enabledLayers.contains($0) }
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
                        drawGridLines(ctx: ctx, rect: rect, activeLayers: activeLayers)
                        drawWorkSegments(ctx: ctx, rect: rect)
                        drawPaceColumns(ctx: ctx, rect: rect, playProgress: playProgress)
                        drawElevation(ctx: ctx, rect: rect, activeLayers: activeLayers, playProgress: playProgress)
                        drawLines(ctx: ctx, rect: rect, activeLayers: activeLayers, playProgress: playProgress)
                        drawFadeMarker(ctx: ctx, rect: rect)
                        if playProgress == nil {
                            drawEndLabels(ctx: ctx, rect: rect, activeLayers: activeLayers)
                        }
                        drawHRAxisLabels(ctx: ctx, rect: rect, activeLayers: activeLayers)
                        drawXAxis(ctx: ctx, rect: rect)
                        if let progress = playProgress {
                            drawPlaybackScrubber(ctx: ctx, rect: rect, progress: progress)
                            drawPlaybackDots(ctx: ctx, rect: rect, activeLayers: activeLayers, progress: progress)
                        } else if let km = selectedKm {
                            drawCrosshair(ctx: ctx, rect: rect, km: km, activeLayers: activeLayers)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                onInteraction?()
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

    /// Returns 0-based zone index (0=Z1…4=Z5) for the given BPM, or -1 if no zone data.
    private func zoneIndex(for bpm: Double) -> Int {
        guard !data.hrZoneBands.isEmpty else { return -1 }
        let sorted = data.hrZoneBands.sorted { $0.lowerBPM < $1.lowerBPM }
        for band in sorted {
            if bpm < Double(band.upperBPM) { return max(0, min(4, band.zone - 1)) }
        }
        return max(0, min(4, (sorted.last?.zone ?? 1) - 1))
    }

    /// Zone color for a BPM value; falls back to Theme.heartRate when zone data is absent.
    /// ⚠ 심박은 항상 존 색이다 (사용자 확정). 다른 선과의 구분은 나머지 레이어 색으로 해결한다.
    private func zoneColor(for bpm: Double) -> Color {
        let idx = zoneIndex(for: bpm)
        return idx >= 0 ? p.hrZones[idx] : Theme.heartRate
    }

    /// Fixed vertical bands. Layer order top→bottom: power → cadence → verticalOsc → strideLength.
    /// Band positions are always computed as if all 4 line layers exist — toggling a layer
    /// only hides its line, never repositions the remaining ones.
    /// HR active  : heartRate (0.04, 0.96); line layers share 0.36–0.92 in 4 fixed slots.
    /// HR inactive: line layers share 0.08–0.92 in 4 fixed slots.
    /// Elevation  : always (0.42, 1.00) — fill/overlap allowed.
    private func bands(for activeLayers: [RunChartLayer]) -> [RunChartLayer: (top: Double, bottom: Double)] {
        var result: [RunChartLayer: (top: Double, bottom: Double)] = [:]

        // 위→아래. 지면접촉은 케이던스 바로 아래 — 둘은 한 쌍이다(케이던스↑ ↔ 접촉↓).
        let lineOrder: [RunChartLayer] = [.power, .cadence, .groundContact, .verticalOsc, .strideLength]
        let n   = lineOrder.count   // always 5 — fixed layout
        let gap = 0.03

        if activeLayers.contains(.heartRate) {
            result[.heartRate] = (top: 0.04, bottom: 0.96)
            let rangeStart = 0.36
            let totalRange = 0.56   // 0.92 – 0.36
            let bandH = (totalRange - gap * Double(n - 1)) / Double(n)
            for (i, layer) in lineOrder.enumerated() {
                let top = rangeStart + Double(i) * (bandH + gap)
                result[layer] = (top: top, bottom: top + bandH)
            }
        } else {
            let rangeStart = 0.08
            let totalRange = 0.84   // 0.92 – 0.08
            let bandH = (totalRange - gap * Double(n - 1)) / Double(n)
            for (i, layer) in lineOrder.enumerated() {
                let top = rangeStart + Double(i) * (bandH + gap)
                result[layer] = (top: top, bottom: top + bandH)
            }
        }

        result[.elevation] = (top: 0.42, bottom: 1.00)
        return result
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
            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 4.5,
                              y: p1.y + (p2.y - p0.y) / 4.5)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 4.5,
                              y: p2.y - (p3.y - p1.y) / 4.5)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
    }

    // MARK: - Binary search helper (playback performance)

    /// Returns the count of points with km ≤ maxKm (i.e., use `points.prefix(result)` for visible slice).
    private func binarySearchIndex(points: [RunChartPoint], upToKm maxKm: Double) -> Int {
        var lo = 0, hi = points.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].km <= maxKm { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // MARK: - Grid lines (구분선)

    private func drawGridLines(ctx: GraphicsContext, rect: CGRect, activeLayers: [RunChartLayer]) {
        let lineColor = p.gridLine
        let style = StrokeStyle(lineWidth: 1.0)

        // 가로선 1개 — 페이스 막대 위 / 차트 아래 경계
        var hPath = Path()
        hPath.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        hPath.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        ctx.stroke(hPath, with: .color(lineColor), style: style)

        // 세로선 1개 — 심박 레이블 오른쪽 / 차트 왼쪽 경계
        var vPath = Path()
        vPath.move(to: CGPoint(x: rect.minX, y: rect.minY))
        vPath.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        ctx.stroke(vPath, with: .color(lineColor), style: style)
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

    // MARK: - Elevation fill+line (neon green gradient fill)

    private func drawElevation(ctx: GraphicsContext, rect: CGRect, activeLayers: [RunChartLayer], playProgress: Double? = nil) {
        guard enabledLayers.contains(.elevation),
              let series = data.series[.elevation], !series.isEmpty else { return }

        let band   = bands(for: activeLayers)[.elevation] ?? (top: 0.34, bottom: 1.00)
        let allPts = series.points
        let visPts: ArraySlice<RunChartPoint>
        if let progress = playProgress, data.totalKm > 0 {
            let idx = binarySearchIndex(points: allPts, upToKm: progress * data.totalKm)
            visPts = allPts.prefix(idx)
        } else {
            visPts = allPts[...]
        }
        guard !visPts.isEmpty else { return }
        let cgPts = visPts.map { p in
            CGPoint(x: xFor(km: p.km, in: rect), y: yForBand(norm: p.norm, band: band, in: rect))
        }
        let linePath = smoothPath(points: cgPts)

        // Closed path for gradient fill
        var fillPath = linePath
        if let last = cgPts.last, let first = cgPts.first {
            fillPath.addLine(to: CGPoint(x: last.x,  y: rect.maxY))
            fillPath.addLine(to: CGPoint(x: first.x, y: rect.maxY))
            fillPath.closeSubpath()
        }

        let elevFillColor = p.elevFill
        let elevLineColor = p.elevation
        // Gradient top anchor = highest elevation point (lowest Y on screen)
        let topY = cgPts.map { $0.y }.min() ?? rect.minY

        if let solo = soloLayer, solo != .elevation {
            // Faded when another layer is soloed
            ctx.fill(fillPath, with: .color(elevFillColor.opacity(0.04)))
            ctx.stroke(linePath, with: .color(elevLineColor.opacity(0.12)),
                       style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
        } else {
            // Gradient fill: bright at peaks → transparent at baseline
            ctx.fill(fillPath, with: .linearGradient(
                Gradient(stops: [
                    .init(color: elevFillColor.opacity(p.elevFillMaxOp), location: 0.0),
                    .init(color: elevFillColor.opacity(p.elevFillMaxOp * 0.38), location: 0.52),
                    .init(color: elevFillColor.opacity(0.00), location: 1.0)
                ]),
                startPoint: CGPoint(x: rect.midX, y: topY),
                endPoint:   CGPoint(x: rect.midX, y: rect.maxY)
            ))
            // Elevation line on top
            ctx.stroke(linePath, with: .color(elevLineColor.opacity(0.95)),
                       style: StrokeStyle(lineWidth: max(0.8, 1.6 + p.lineWidthAdjust), lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: - Pace columns (time-proportional background)

    private func drawPaceColumns(ctx: GraphicsContext, rect: CGRect, playProgress: Double? = nil) {
        // 페이스 막대는 토글 대상이 아니다(타일 없음) — 저장된 enabledLayers에 페이스가 빠져 있어도 그린다.
        // 예전에 칩을 꺼둔 채 저장한 사용자는 칩이 사라진 뒤 되돌릴 방법이 없었다.
        guard !data.paceColumns.isEmpty else { return }

        let baseOp: Double = soloLayer == nil ? p.paceColFillOp : (soloLayer == .pace ? p.paceColFillOp * 1.7 : p.paceColFillOp * 0.36)
        let inset: CGFloat = 0.40   // 40% margin on each side → 60% fill
        let maxKm: Double? = playProgress.map { $0 * data.totalKm }

        for col in data.paceColumns {
            if let maxKm, col.startKm > maxKm { continue }
            let isInProgress: Bool = maxKm.map { col.startKm <= $0 && col.endKm > $0 } ?? false

            let fullW = CGFloat(col.endX - col.startX) * rect.width
            let w     = max(6, fullW * (1 - inset))
            let x     = rect.minX + CGFloat(col.startX) * rect.width + (fullW - w) / 2

            let h       = rect.height * CGFloat(0.20 + col.norm * 0.80)
            let barRect = CGRect(x: x, y: rect.maxY - h, width: w, height: h)
            let barPath = Path(roundedRect: barRect, cornerRadius: 2)
            let fillOp   = isInProgress ? baseOp * 0.5 : baseOp
            let borderOp = isInProgress ? p.paceColBorderOp * 0.5 : p.paceColBorderOp
            ctx.fill(barPath, with: .color(p.pace.opacity(fillOp)))
            ctx.stroke(barPath, with: .color(p.textPrimary.opacity(borderOp)),
                       style: StrokeStyle(lineWidth: p.paceColBorderWidth))

            // Label centred under column; skip if too narrow or in-progress bar
            if w >= 14, !isInProgress {
                ctx.draw(
                    Text(col.label)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(p.paceColLabelColor),
                    at: CGPoint(x: x + w / 2, y: rect.maxY + 3),
                    anchor: .top
                )
            }
        }
    }

    // MARK: - Line layers (HR: zone-colored segments; others: single-color smooth line)

    private func drawLines(ctx: GraphicsContext, rect: CGRect, activeLayers: [RunChartLayer], playProgress: Double? = nil) {
        let bandMap = bands(for: activeLayers)

        // Non-HR layers: bottom→top order, each with black casing then colour line
        for layer in [RunChartLayer.strideLength, .verticalOsc, .groundContact, .cadence, .power] {
            guard activeLayers.contains(layer),
                  let series = data.series[layer], !series.isEmpty,
                  let band   = bandMap[layer] else { continue }

            let allPts = series.points
            let visPts: ArraySlice<RunChartPoint>
            if let progress = playProgress, data.totalKm > 0 {
                let idx = binarySearchIndex(points: allPts, upToKm: progress * data.totalKm)
                visPts = allPts.prefix(idx)
            } else {
                visPts = allPts[...]
            }
            guard !visPts.isEmpty else { continue }
            let cgPts = visPts.map { p in
                CGPoint(x: xFor(km: p.km, in: rect), y: yForBand(norm: p.norm, band: band, in: rect))
            }
            let path = smoothPath(points: cgPts)

            let effectiveOp: Double
            if let solo = soloLayer { effectiveOp = (layer == solo) ? 1.0 : 0.15 }
            else                    { effectiveOp = layer.opacity }

            if case .line(let w) = layer.drawStyle {
                let lw = max(0.8, w + p.lineWidthAdjust)
                // Casing: outline drawn first
                ctx.stroke(path, with: .color(p.chartCasing),
                           style: StrokeStyle(lineWidth: lw + p.casingWidthAdd, lineCap: .round, lineJoin: .round))
                // Colour line on top
                ctx.stroke(path, with: .color(p.layerColor(layer).opacity(effectiveOp)),
                           style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            }
        }

        // HR drawn last (on top): zone-coloured with casing
        if activeLayers.contains(.heartRate),
           let series = data.series[.heartRate], !series.isEmpty,
           let band = bandMap[.heartRate] {
            let op: Double = soloLayer == nil ? 1.0 : (soloLayer == .heartRate ? 1.0 : 0.15)
            drawHRSegments(ctx: ctx, rect: rect, series: series, band: band, opacity: op, playProgress: playProgress)
        }
    }

    /// Draws the HR line as Catmull-Rom segments coloured by heart-rate zone.
    /// Two-pass: all casings first, then all colour lines — clean zone transitions.
    private func drawHRSegments(ctx: GraphicsContext, rect: CGRect,
                                 series: RunChartSeries,
                                 band: (top: Double, bottom: Double),
                                 opacity: Double,
                                 playProgress: Double? = nil) {
        let allPts = series.points
        let pts: [RunChartPoint]
        if let progress = playProgress, data.totalKm > 0 {
            let idx = binarySearchIndex(points: allPts, upToKm: progress * data.totalKm)
            pts = Array(allPts.prefix(idx))
        } else {
            pts = allPts
        }
        guard pts.count >= 2 else { return }

        let cgPts = pts.map { p -> CGPoint in
            CGPoint(x: xFor(km: p.km, in: rect), y: yForBand(norm: p.norm, band: band, in: rect))
        }
        let padded = [cgPts[0]] + cgPts + [cgPts[cgPts.count - 1]]

        // Collect zone-coloured path segments
        var zonePaths: [(path: Path, zone: Int)] = []
        var currentZone: Int = Int.min
        var currentPath = Path()
        var hasPath = false

        func flush() {
            guard hasPath else { return }
            zonePaths.append((path: currentPath, zone: currentZone))
            currentPath = Path()
            hasPath = false
        }

        for i in 0..<(pts.count - 1) {
            let midBPM = (pts[i].value + pts[i + 1].value) / 2
            let segZone = zoneIndex(for: midBPM)
            let p0 = padded[i], p1 = padded[i + 1], p2 = padded[i + 2], p3 = padded[i + 3]
            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 4.5, y: p1.y + (p2.y - p0.y) / 4.5)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 4.5, y: p2.y - (p3.y - p1.y) / 4.5)
            if segZone != currentZone {
                flush()
                currentZone = segZone
                currentPath.move(to: p1)
                hasPath = true
            }
            currentPath.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        flush()

        // Pass 1: all casings (thick, drawn first) — HR casing is +2.6pt, thicker than other layers
        for (path, _) in zonePaths {
            ctx.stroke(path, with: .color(p.chartCasing),
                       style: StrokeStyle(lineWidth: p.hrLineWidth + 2.6, lineCap: .round, lineJoin: .round))
        }
        // Pass 2: all coloured lines on top
        for (path, zone) in zonePaths {
            let c: Color = zone >= 0 ? p.hrZones[zone] : Theme.heartRate
            ctx.stroke(path, with: .color(c.opacity(opacity)),
                       style: StrokeStyle(lineWidth: p.hrLineWidth, lineCap: .round, lineJoin: .round))
        }

        // Zone transition tick marks — only when transitions are rare (≤ 3)
        var transitions: [(x: CGFloat, zone: Int)] = []
        for i in 0..<(pts.count - 2) {
            let z1 = zoneIndex(for: (pts[i].value + pts[i + 1].value) / 2)
            let z2 = zoneIndex(for: (pts[i + 1].value + pts[i + 2].value) / 2)
            if z1 != z2, z2 >= 0 {
                transitions.append((x: cgPts[i + 1].x, zone: z2))
            }
        }
        if transitions.count <= 3 {
            let tickBase = yForBand(norm: 0.0, band: band, in: rect)
            for (x, zone) in transitions {
                let col = p.hrZones[zone]
                var tick = Path()
                tick.move(to:    CGPoint(x: x, y: tickBase - 4))
                tick.addLine(to: CGPoint(x: x, y: tickBase))
                ctx.stroke(tick, with: .color(col.opacity(0.5 * opacity)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }

        // ⚠ 예전에는 심박 선 위에 등간격 점 5개를 찍었다. 데이터 의미가 없는 장식이라
        //   "저 점이 뭐지?"라는 질문만 만들었다. 재생 중 끝점(drawPlaybackDots)과
        //   십자선 점(drawCrosshair)만 남긴다.
    }

    // MARK: - Right-side end-point value labels (line layers + elevation)

    private func drawEndLabels(ctx: GraphicsContext, rect: CGRect, activeLayers: [RunChartLayer]) {
        var labelLayers = [RunChartLayer.heartRate, .cadence, .power, .groundContact, .strideLength, .verticalOsc]
            .filter { activeLayers.contains($0) }
        if activeLayers.contains(.elevation) { labelLayers.append(.elevation) }
        guard !labelLayers.isEmpty else { return }

        let bandMap = bands(for: activeLayers)
        struct Slot { let text: String; var y: CGFloat; let color: Color }

        var slots: [Slot] = labelLayers.compactMap { layer in
            guard let series = data.series[layer], !series.isEmpty,
                  let lastPt = series.points.last,
                  let band   = bandMap[layer] else { return nil }
            let text = (layer == .elevation)
                ? "\(Int(series.lastValue.rounded()))m"
                : layer.formatted(series.lastValue)
            let y: CGFloat = yForBand(norm: lastPt.norm, band: band, in: rect)
            let color: Color = (layer == .heartRate)
                ? zoneColor(for: series.lastValue)
                : p.layerColor(layer)
            return Slot(text: text, y: y, color: color)
        }

        // Sort top-to-bottom, nudge overlapping labels downward
        slots.sort { $0.y < $1.y }
        let minGap: CGFloat = endLabelMinGap
        for i in 1..<slots.count {
            if slots[i].y - slots[i-1].y < minGap {
                slots[i].y = slots[i-1].y + minGap
            }
        }

        let labelX = rect.maxX + 4

        // 이 열은 평균이 아니라 **러닝이 끝난 시점의 값**이다. 아래 타일은 평균이라 숫자가 달라
        // "둘이 안 맞는다"로 읽혔다. 열 머리에 작게 표시해 둔다.
        // (차트를 끌면 십자선이 그 지점 값을 따로 보여 준다 — 그쪽은 단위까지 붙는다.)
        ctx.draw(
            Text(AppLanguage.shared.s("끝값", "end"))
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(p.textPrimary.opacity(0.45)),
            at: CGPoint(x: labelX, y: rect.minY - 2),
            anchor: .bottomLeading
        )

        for slot in slots {
            let resolved = ctx.resolve(Text(slot.text)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(slot.color))
            let tSz = resolved.measure(in: CGSize(width: 100, height: 20))
            let textRect = CGRect(x: labelX, y: slot.y - tSz.height / 2,
                                  width: tSz.width, height: tSz.height)
            if p.valueLabelBgOp > 0 {
                let casing = ctx.resolve(Text(slot.text)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.white.opacity(p.valueLabelBgOp)))
                for (dx, dy) in [(-1.5,-1.5),(-1.5,0.0),(-1.5,1.5),(0.0,-1.5),(0.0,1.5),(1.5,-1.5),(1.5,0.0),(1.5,1.5)] as [(CGFloat,CGFloat)] {
                    ctx.draw(casing, in: textRect.offsetBy(dx: dx, dy: dy))
                }
            }
            ctx.draw(resolved, in: textRect)
        }
    }

    // MARK: - HR axis labels (left gutter, two ticks only)

    private func drawHRAxisLabels(ctx: GraphicsContext, rect: CGRect, activeLayers: [RunChartLayer]) {
        guard activeLayers.contains(.heartRate),
              let hrSeries = data.series[.heartRate] else { return }
        let bandMap = bands(for: activeLayers)
        guard let hrBand = bandMap[.heartRate] else { return }
        let axisStyle = p.axisLabelColor
        ctx.draw(
            Text("\(Int(hrSeries.maxValue.rounded()))").font(.system(size: 9, weight: .medium)).foregroundStyle(axisStyle),
            at: CGPoint(x: 22, y: yForBand(norm: 1.0, band: hrBand, in: rect)), anchor: .trailing
        )
        ctx.draw(
            Text("\(Int(hrSeries.minValue.rounded()))").font(.system(size: 9, weight: .medium)).foregroundStyle(axisStyle),
            at: CGPoint(x: 22, y: yForBand(norm: 0.0, band: hrBand, in: rect)), anchor: .trailing
        )
    }

    // MARK: - X axis ticks (time row above, distance row below)

    private func drawXAxis(ctx: GraphicsContext, rect: CGRect) {
        guard data.totalKm > 0 else { return }
        let km = data.totalKm
        func distLabel(_ v: Double) -> String {
            if v == 0 { return "0" }
            let r = v.rounded()
            return v == r ? "\(Int(r))km" : String(format: "%.1fkm", v)
        }
        let ticks: [(km: Double, anchor: UnitPoint)] = [
            (0,      .topLeading),
            (km / 2, .top),
            (km,     .topTrailing)
        ]
        // ⚠ 예전에는 시간 줄·거리 줄이 따로여서 km별 페이스 라벨까지 세 줄이었다.
        //   시간과 거리를 "34:33 · 5.0km" 한 줄로 합친다. 페이스 라벨(+3..+13)은 그대로.
        for tick in ticks {
            let x = xFor(km: tick.km, in: rect)
            let timeStr = formatElapsed(elapsedTime(atKm: tick.km))
            let label = tick.km == 0 ? timeStr : "\(timeStr) · \(distLabel(tick.km))"
            ctx.draw(
                Text(label)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(p.xAxisDistColor),
                at: CGPoint(x: x, y: rect.maxY + 16),
                anchor: tick.anchor
            )
        }
    }

    /// Interpolates elapsed time (seconds) at the given km position using paceColumns.
    private func elapsedTime(atKm km: Double) -> TimeInterval {
        guard data.totalKm > 0 else { return 0 }
        if km <= 0 { return 0 }
        if km >= data.totalKm { return data.totalDuration }

        // Accurate path: interpolate within pace columns
        if !data.paceColumns.isEmpty, data.totalDuration > 0 {
            for col in data.paceColumns {
                guard km >= col.startKm, km <= col.endKm else { continue }
                let span = col.endKm - col.startKm
                let frac = span > 0 ? (km - col.startKm) / span : 0.0
                return (col.startX + frac * (col.endX - col.startX)) * data.totalDuration
            }
        }

        // Fallback: linear interpolation
        guard data.totalDuration > 0 else { return 0 }
        return km / data.totalKm * data.totalDuration
    }

    /// Formats seconds as "M:SS" or "H:MM:SS".
    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    // MARK: - Playback: scrubber line + top label

    private func drawPlaybackScrubber(ctx: GraphicsContext, rect: CGRect, progress: Double) {
        guard data.totalKm > 0 else { return }
        let km = progress * data.totalKm
        let x  = xFor(km: km, in: rect)

        // Vertical scrubber line
        var line = Path()
        line.move(to: CGPoint(x: x, y: rect.minY))
        line.addLine(to: CGPoint(x: x, y: rect.maxY))
        ctx.stroke(line, with: .color(p.textPrimary.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 1.0, lineCap: .round))

        // Top label: "2.0km · 12:48" with black capsule background
        let elapsed   = elapsedTime(atKm: km)
        let labelText = String(format: "%.1fkm · %@", km, formatElapsed(elapsed))
        let goLeft    = progress > 0.70

        let bgH: CGFloat = 20
        let bgW: CGFloat = CGFloat(labelText.count) * 6.9 + 18
        // Place above the chart rect (padT = 26, bgH = 20 → sits at y ≈ 4..24, rect.minY = 26)
        let bgY: CGFloat = rect.minY - bgH - 2
        let bgX: CGFloat = goLeft ? x - bgW - 4 : x + 4

        let scrubberCapsRect = CGRect(x: bgX, y: bgY, width: bgW, height: bgH)
        ctx.fill(
            Path(roundedRect: scrubberCapsRect, cornerRadius: 10),
            with: .color(p.chartCasing)
        )
        if p.scrubberBorderOp > 0 {
            ctx.stroke(
                Path(roundedRect: scrubberCapsRect, cornerRadius: 10),
                with: .color(p.textPrimary.opacity(p.scrubberBorderOp)),
                style: StrokeStyle(lineWidth: 0.8)
            )
        }
        ctx.draw(
            Text(labelText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(p.textPrimary),
            at: CGPoint(x: bgX + bgW / 2, y: bgY + bgH / 2),
            anchor: .center
        )
    }

    // MARK: - Playback: endpoint dots + value labels

    private func drawPlaybackDots(ctx: GraphicsContext, rect: CGRect, activeLayers: [RunChartLayer], progress: Double) {
        guard data.totalKm > 0 else { return }
        let maxKm  = progress * data.totalKm
        let bandMap = bands(for: activeLayers)
        let goLeft  = progress > 0.70
        let scrubX  = xFor(km: maxKm, in: rect)
        let labelX: CGFloat    = goLeft ? scrubX - 7 : scrubX + 7

        struct DotInfo { var labelY: CGFloat; let text: String; let color: Color }
        var dotInfos: [DotInfo] = []

        let lineOrder: [RunChartLayer] = [.heartRate, .power, .cadence, .verticalOsc, .strideLength, .elevation]
        for layer in lineOrder {
            guard activeLayers.contains(layer),
                  let series = data.series[layer], !series.isEmpty,
                  let band   = bandMap[layer] else { continue }

            let allPts = series.points
            let idx = binarySearchIndex(points: allPts, upToKm: maxKm)
            guard idx > 0 else { continue }

            let pt   = allPts[idx - 1]
            let dotX = xFor(km: pt.km, in: rect)
            let dotY = yForBand(norm: pt.norm, band: band, in: rect)

            let color: Color
            let text: String
            if layer == .heartRate {
                color = zoneColor(for: pt.value)
                text  = "\(layer.formatted(pt.value)) \(layer.unit)"
            } else if layer == .elevation {
                color = p.elevation
                text  = "\(Int(pt.value.rounded())) m"
            } else {
                color = p.layerColor(layer)
                text  = "\(layer.formatted(pt.value)) \(layer.unit)"
            }

            // Dot: only HR gets a positional dot
            if layer == .heartRate {
                let r: CGFloat = 3.2
                let dotRect = CGRect(x: dotX - r, y: dotY - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: dotRect), with: .color(color))
                ctx.stroke(Path(ellipseIn: dotRect), with: .color(p.chartCasing),
                           style: StrokeStyle(lineWidth: 1.2))
            }

            dotInfos.append(DotInfo(labelY: dotY, text: text, color: color))
        }

        // Sort top→bottom, nudge overlapping labels, clamp to chart area
        dotInfos.sort { $0.labelY < $1.labelY }
        let minGap: CGFloat = 11
        for i in 1..<max(1, dotInfos.count) {
            if dotInfos[i].labelY - dotInfos[i-1].labelY < minGap {
                dotInfos[i].labelY = dotInfos[i-1].labelY + minGap
            }
        }
        for i in 0..<dotInfos.count {
            dotInfos[i].labelY = max(rect.minY + 14, min(rect.maxY - 4, dotInfos[i].labelY))
        }

        for info in dotInfos {
            let resolved = ctx.resolve(Text(info.text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(info.color))
            let tSz = resolved.measure(in: CGSize(width: 200, height: 20))
            let textOriginX: CGFloat = goLeft ? labelX - tSz.width : labelX
            let textRect = CGRect(x: textOriginX, y: info.labelY - tSz.height / 2,
                                  width: tSz.width, height: tSz.height)
            if p.valueLabelBgOp > 0 {
                let casing = ctx.resolve(Text(info.text)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(p.valueLabelBgOp)))
                for (dx, dy) in [(-1.5,-1.5),(-1.5,0.0),(-1.5,1.5),(0.0,-1.5),(0.0,1.5),(1.5,-1.5),(1.5,0.0),(1.5,1.5)] as [(CGFloat,CGFloat)] {
                    ctx.draw(casing, in: textRect.offsetBy(dx: dx, dy: dy))
                }
            }
            ctx.draw(resolved, in: textRect)
        }
    }

    // MARK: - Crosshair with inline labels

    private func drawCrosshair(ctx: GraphicsContext, rect: CGRect, km: Double, activeLayers: [RunChartLayer]) {
        let x = xFor(km: km, in: rect)
        let goLeft = x > rect.midX   // labels sit on the opposite side from where the finger is

        // Vertical line
        var linePath = Path()
        linePath.move(to: CGPoint(x: x, y: rect.minY))
        linePath.addLine(to: CGPoint(x: x, y: rect.maxY))
        ctx.stroke(linePath, with: .color(p.textPrimary.opacity(0.60)),
                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

        // Header: km · elapsed
        let elapsed  = elapsedTime(atKm: km)
        let hdrText  = String(format: "%.1fkm · %@", km, formatElapsed(elapsed))
        let hdrX: CGFloat = goLeft ? x - 6 : x + 6
        ctx.draw(
            Text(hdrText)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(p.textPrimary.opacity(0.95)),
            at: CGPoint(x: hdrX, y: rect.minY + 1),
            anchor: goLeft ? .topTrailing : .topLeading
        )

        // Inline dots + labels for line layers
        let bandMap  = bands(for: activeLayers)
        let labelX: CGFloat = goLeft ? x - 7 : x + 7

        struct Slot {
            var y: CGFloat
            let text: String
            let color: Color
            let hasDot: Bool
        }

        var slots: [Slot] = []

        // Pace: label near the pace bar area (bottom of chart), no dot
        if activeLayers.contains(.pace),
           let paceVal = nearestValue(km: km, layer: .pace) {
            let text = "\(RunChartLayer.pace.formatted(paceVal)) /km"
            slots.append(Slot(y: rect.maxY - 8, text: text, color: p.pace, hasDot: false))
        }

        // Line layers: dot only for HR (radius 3.2); others get label only
        let lineOrder: [RunChartLayer] = [.heartRate, .power, .cadence, .groundContact, .verticalOsc, .strideLength]
        for layer in lineOrder {
            guard activeLayers.contains(layer),
                  let series = data.series[layer], !series.isEmpty,
                  let band   = bandMap[layer],
                  let pt     = series.points.min(by: { abs($0.km - km) < abs($1.km - km) })
            else { continue }

            let y       = yForBand(norm: pt.norm, band: band, in: rect)
            let dotCol  = (layer == .heartRate) ? zoneColor(for: pt.value) : p.layerColor(layer)
            let text    = "\(layer.formatted(pt.value)) \(layer.unit)"
            slots.append(Slot(y: y, text: text, color: dotCol, hasDot: layer == .heartRate))
        }

        // Elevation: label only, no dot
        if activeLayers.contains(.elevation),
           let series = data.series[.elevation], !series.isEmpty,
           let band   = bandMap[.elevation],
           let pt     = series.points.min(by: { abs($0.km - km) < abs($1.km - km) }) {
            let y    = yForBand(norm: pt.norm, band: band, in: rect)
            let text = "\(Int(pt.value.rounded())) m"
            slots.append(Slot(y: y, text: text, color: p.elevation, hasDot: false))
        }

        // Sort top → bottom, then nudge overlapping slots apart
        slots.sort { $0.y < $1.y }
        let minGap: CGFloat = 12
        for i in 1..<slots.count {
            if slots[i].y - slots[i-1].y < minGap {
                slots[i].y = slots[i-1].y + minGap
            }
        }
        // Reverse pass prevents overflow at bottom
        for i in stride(from: slots.count - 2, through: 0, by: -1) {
            if slots[i+1].y - slots[i].y < minGap {
                slots[i].y = slots[i+1].y - minGap
            }
        }
        // Clamp to chart area
        for i in 0..<slots.count {
            slots[i].y = max(rect.minY + 14, min(rect.maxY - 4, slots[i].y))
        }

        // Draw HR dot only (radius 3.2, larger than before for emphasis)
        for slot in slots where slot.hasDot {
            let r: CGFloat = 3.2
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - (r + 1.5), y: slot.y - (r + 1.5),
                                       width: (r + 1.5) * 2, height: (r + 1.5) * 2)),
                with: .color(p.chartCasing)
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - r, y: slot.y - r, width: r * 2, height: r * 2)),
                with: .color(slot.color)
            )
        }

        // Draw labels
        for slot in slots {
            let resolved = ctx.resolve(Text(slot.text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(slot.color))
            let tSz = resolved.measure(in: CGSize(width: 200, height: 20))
            let textOriginX: CGFloat = goLeft ? labelX - tSz.width : labelX
            let textRect = CGRect(x: textOriginX, y: slot.y - tSz.height / 2,
                                  width: tSz.width, height: tSz.height)
            if p.valueLabelBgOp > 0 {
                let casing = ctx.resolve(Text(slot.text)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(p.valueLabelBgOp)))
                for (dx, dy) in [(-1.5,-1.5),(-1.5,0.0),(-1.5,1.5),(0.0,-1.5),(0.0,1.5),(1.5,-1.5),(1.5,0.0),(1.5,1.5)] as [(CGFloat,CGFloat)] {
                    ctx.draw(casing, in: textRect.offsetBy(dx: dx, dy: dy))
                }
            }
            ctx.draw(resolved, in: textRect)
        }
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
