import SwiftUI
import CoreLocation

// MARK: - Story Share Card (no photo — dark card)
//
// 사진 없는 다크 카드. 스토리(메모·무드) + 기록 데이터 + 루트 or 차트.
// 공유: ShareCardScreen에서 template == .photo 시 사용.

struct StoryShareCardView: View {
    let activity: Activity
    let routeCoordinates: [CLLocationCoordinate2D]
    let story: WorkoutStory
    var metrics: [ShareMetricItem] = []
    var raceName: String? = nil
    var chartPanel: CardChartPanel = .map
    var chartSplits: [SplitData] = []
    var chartHRSamples: [(offset: TimeInterval, bpm: Int)] = []
    var chartHRZones: [HRZoneData] = []
    var chartWorkoutSeries: [(offset: TimeInterval, value: Double)] = []
    var chartIntervalSegments: [IntervalSegment] = []
    var weather: WeatherSnapshot? = nil
    var shoeName: String? = nil
    /// 총평 5줄 — 비어 있으면(기본) 기존 지도/차트 자리 그대로. §5.8: scale만 다르고 컴포넌트는 하나.
    var summaryLines: [RunSummaryLine] = []

    private var distanceValue: String {
        let km = activity.distance / 1000
        return km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
    }
    private var startDateTimeString: String { activity.date.cardDateTimeString }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1E1428"), Color(hex: "0D0912")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 0) {
                            MIMOWordmark(size: 11, onMediaCard: true)
                        }

                        if let race = raceName { RaceBadge(name: race) }
                    }

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                // ── 총평(로고 아래) — §5.8: scale만 다르고 컴포넌트는 하나 ──
                if !summaryLines.isEmpty {
                    RunSummaryLinesView(lines: summaryLines, scale: 0.7, expandAll: true, fontBoost: 1)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                Spacer()

                if summaryLines.isEmpty, chartPanel == .map, !routeCoordinates.isEmpty {
                    HStack {
                        Spacer()
                        RouteLineArt(coordinates: routeCoordinates)
                            .frame(width: 110, height: 110)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                } else if summaryLines.isEmpty, chartPanel != .map {
                    HStack {
                        Spacer()
                        CardChartLabeledPanel(
                            panel: chartPanel, splits: chartSplits, hrSamples: chartHRSamples,
                            hrZones: chartHRZones, workoutSeries: chartWorkoutSeries,
                            intervalSegments: chartIntervalSegments
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                HStack(spacing: 0) {
                    HStack(spacing: 3) {
                        Text(activity.date.cardDateString)
                        Text(activity.date.weekdayString).foregroundStyle(Theme.time)
                        Text(activity.date.cardTimeString)
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.80))
                    if let w = weather {
                        HStack(spacing: 3) {
                            Image(systemName: w.systemIcon)
                                .font(.system(size: 8))
                            Text(activity.temperatureC.map { String(format: "%.0f°C", $0) } ?? w.formattedTemp)
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.leading, 6)
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
                .padding(.horizontal, 20)
                .padding(.bottom, 3)

                Rectangle()
                    .fill(Theme.violet.opacity(0.30))
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)

                HStack(alignment: .center, spacing: 0) {
                    let distW: CGFloat = metrics.count >= 5 ? 70 : 96
                    let distPt: CGFloat = metrics.count >= 5 ? 28 : 38
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(distanceValue)
                            .font(.system(size: distPt, weight: .black).width(.condensed))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("KM")
                            .font(.system(size: 10, weight: .bold).width(.condensed))
                            .foregroundStyle(Theme.violet)
                            .padding(.bottom, 2)
                    }
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(width: distW, alignment: .leading)
                    .padding(.leading, 20)

                    if !metrics.isEmpty {
                        Rectangle()
                            .fill(.white.opacity(0.07))
                            .frame(width: 0.5, height: 36)

                        let rows = metricsRows(metrics)
                        VStack(spacing: rows.count > 1 ? 3 : 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 0) {
                                    ForEach(row) { m in
                                        CardMetric(value: m.value, label: m.label, color: m.color,
                                                   valueSize: row.count >= 5 ? 11 : 12, labelSize: 8)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 300, height: 375)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
