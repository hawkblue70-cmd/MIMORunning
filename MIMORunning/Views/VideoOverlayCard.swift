import SwiftUI

// MARK: - Video Overlay Card
//
// 9:16 영상(1080×1920px) 위에 데이터를 얹는 오버레이 카드.
// ImageRenderer(scale 5)로 렌더링 → RouteVideoService·VideoExportService·ShareCardScreen 공용.
//
// ⚠️ CLAUDE.md §5.8 데이터 표시 통일성 규칙:
//   scale=1.0 기준값(폰트 pt, 차트 px, 여백 pt)을 절대로 변경하지 말 것.
//   카드별로 다른 크기가 필요한 경우 scale 파라미터만 조정할 것.
//
// scale 기준값 (scale=1.0)
//   워드마크: 11pt × scale
//   차트: 160×100pt
//   아이콘/레이블: 7pt/8pt  수평 패딩: 10pt

struct VideoOverlayCard: View {
    let distanceKm: String
    let date: Date
    let metrics: [ShareMetricItem]
    let raceName: String?
    let chartPanel: CardChartPanel
    let chartSplits: [SplitData]
    let chartHRSamples: [(offset: TimeInterval, bpm: Int)]
    var chartHRZones: [HRZoneData] = []
    let chartWorkoutSeries: [(offset: TimeInterval, value: Double)]
    let chartIntervalSegments: [IntervalSegment]
    let weather: WeatherSnapshot?
    var shoeName: String? = nil
    /// 총평 5줄 — 비어 있으면(기본) 기존 지도/차트 자리 그대로. §5.8: scale만 다르고 컴포넌트는 하나.
    var summaryLines: [RunSummaryLine] = []
    var scale: CGFloat = 1.0
    // nil = videoSafeTopRef/BottomRef * scale (Instagram safe zone 기본값)
    // 값 지정 시 해당 pt를 그대로 사용 (scale 미적용)
    var topInset: CGFloat? = nil
    var bottomInset: CGFloat? = nil

    var body: some View {
        ZStack {
            Color.clear

            CardVisual.bottomScrim

            VStack(alignment: .leading, spacing: 0) {

                // ── TOP: Wordmark (+ 대회 뱃지) ──
                HStack(alignment: .top, spacing: 4 * scale) {
                    VStack(alignment: .leading, spacing: 2 * scale) {
                        HStack(spacing: 0) {
                            MIMOWordmark(size: 11 * scale, onMediaCard: true)
                        }
                        if let race = raceName {
                            HStack(spacing: 2 * scale) {
                                Image(systemName: "flag.checkered")
                                    .font(.system(size: 8 * scale, weight: .semibold))
                                Text(race)
                                    .font(.system(size: 9 * scale, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 4 * scale)
                            .padding(.vertical, 2 * scale)
                            .background(Theme.violet.opacity(0.20))
                            .clipShape(Capsule())
                            .cardTextShadow()
                        }
                    }
                    Spacer(minLength: 3 * scale)
                }
                .padding(.top, topInset ?? (CardVisual.videoSafeTopRef * scale))

                // ── 총평(로고 아래, 비디오 세이프존 안) — §5.8: scale만 다르고 컴포넌트는 하나 ──
                if !summaryLines.isEmpty {
                    RunSummaryLinesView(lines: summaryLines, scale: scale * 0.7, expandAll: true, fontBoost: scale)
                        .padding(.top, 8 * scale)
                }

                Spacer()

                // ── MIDDLE: chart (right-aligned) — 총평이 켜지면 숨김(§5.8) ──
                if summaryLines.isEmpty, chartPanel != .map {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2 * scale) {
                            HStack(spacing: 2 * scale) {
                                Image(systemName: chartPanel.icon)
                                    .font(.system(size: 7 * scale))
                                Text(chartPanel.label)
                                    .font(.system(size: 8 * scale, weight: .semibold))
                                    .tracking(0.3)
                                if chartPanel == .intervals, let s = chartIntervalSegments.workSummaryText {
                                    Text(s)
                                        .font(.system(size: 8 * scale, weight: .semibold).monospacedDigit())
                                }
                            }
                            .foregroundStyle(Color.white.opacity(0.55))
                            CardChartPanelView(
                                panel: chartPanel, splits: chartSplits, hrSamples: chartHRSamples,
                                hrZones: chartHRZones, workoutSeries: chartWorkoutSeries,
                                intervalSegments: chartIntervalSegments,
                                chartSize: CGSize(width: 130 * scale, height: 83 * scale),
                                labelScale: scale
                            )
                        }
                    }
                    .padding(.horizontal, 20 * scale)
                    .padding(.bottom, 8 * scale)
                    .cardTextShadow()
                }

                // ── BOTTOM: date · divider · stats ──
                HStack(spacing: 0) {
                    HStack(spacing: 2 * scale) {
                        Text(date.cardDateString)
                        Text(date.weekdayString).foregroundStyle(Theme.time)
                        Text(date.cardTimeString)
                    }
                    .font(.system(size: 9 * scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.80))
                    if let w = weather {
                        HStack(spacing: 2 * scale) {
                            Image(systemName: w.systemIcon)
                                .font(.system(size: 8 * scale))
                            Text(w.formattedTemp)
                                .font(.system(size: 8 * scale, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.leading, 4 * scale)
                    }
                    if let shoe = shoeName {
                        Spacer()
                        HStack(spacing: 3 * scale) {
                            Image(systemName: "shoe.fill").font(.system(size: 8 * scale))
                            Text(shoe).font(.system(size: 9 * scale, weight: .medium)).lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .padding(.bottom, 2 * scale)
                .cardTextShadow()

                Rectangle()
                    .fill(Theme.violet.opacity(0.30))
                    .frame(height: 0.5)

                HStack(alignment: .center, spacing: 0) {
                    let distW: CGFloat = (metrics.count >= 5 ? 70 : 96) * scale
                    let distPt: CGFloat = (metrics.count >= 5 ? 28 : 38) * scale
                    HStack(alignment: .lastTextBaseline, spacing: 2 * scale) {
                        Text(distanceKm)
                            .font(.system(size: distPt, weight: .black).width(.condensed))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("KM")
                            .font(.system(size: 10 * scale, weight: .bold).width(.condensed))
                            .foregroundStyle(Theme.violet)
                            .padding(.bottom, 1 * scale)
                    }
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(width: distW, alignment: .leading)
                    .cardLargeTextShadow()

                    if !metrics.isEmpty {
                        Rectangle()
                            .fill(.white.opacity(0.07))
                            .frame(width: 0.5, height: 36 * scale)

                        let rows = metricsRows(metrics)
                        VStack(spacing: rows.count > 1 ? 3 * scale : 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 0) {
                                    ForEach(row) { m in
                                        VStack(spacing: 1) {
                                            Text(m.value)
                                                .font(.system(size: (row.count >= 5 ? 11 : 12) * scale,
                                                              weight: .bold, design: .rounded))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.6)
                                            Text(m.label)
                                                .font(.system(size: 8 * scale, weight: .semibold))
                                                .foregroundStyle(m.color)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6 * scale)
                        .frame(maxWidth: .infinity)
                        .cardTextShadow()
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2 * scale)
                .padding(.bottom, bottomInset ?? (CardVisual.videoSafeBottomRef * scale))
            }
            // 그림자는 텍스트 요소에만 개별 적용 — 로고에는 없음
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
