import SwiftUI
import CoreLocation

// MARK: - Photo card (photo background, unified athletic + story)
//
// 사용자 사진을 배경으로 쓰는 카드. 판·레이아웃은 Athletic/Story와 동일,
// 사진 위에 상단 스크림 + 하단 스크림을 씌워 가독성 확보.
// `photoOffset` @Binding으로 사진 위치를 부모(ShareCardScreen)가 제어.

struct PhotoShareCardView: View {
    let activity: Activity
    let photo: UIImage
    let metrics: [ShareMetricItem]
    var raceName: String? = nil
    var routeCoordinates: [CLLocationCoordinate2D] = []
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
    @Binding var photoOffset: CGSize
    @State private var gestureStart: CGSize = .zero

    private func maxOffset(for cardSize: CGSize) -> CGSize {
        let s = photo.size
        guard s.width > 0, s.height > 0 else { return .zero }
        let scale = max(cardSize.width / s.width, cardSize.height / s.height)
        return CGSize(
            width: max(0, (s.width * scale - cardSize.width) / 2),
            height: max(0, (s.height * scale - cardSize.height) / 2)
        )
    }

    private var distanceValue: String {
        let km = activity.distance / 1000
        return km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
    }
    private var startDateTimeString: String { activity.date.cardDateTimeString }

    var body: some View {
        let max = maxOffset(for: CGSize(width: 300, height: 375))
        ZStack {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 300, height: 375)
                .offset(photoOffset)
                .brightness(CardVisual.photoBrightnessBoost)

            CardVisual.topScrim
            CardVisual.bottomScrim

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
                .padding(.horizontal, 18)
                .padding(.top, 18)

                // ── 총평(로고 아래) — §5.8: scale만 다르고 컴포넌트는 하나 ──
                if !summaryLines.isEmpty {
                    RunSummaryLinesView(lines: summaryLines, scale: 0.7, expandAll: true, fontBoost: 1)
                        .padding(.horizontal, 18)
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
                .padding(.horizontal, 18)
                .padding(.bottom, 3)

                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(height: 0.5)
                    .padding(.horizontal, 18)

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
            .cardTextShadow()
            .frame(width: 300, height: 375, alignment: .topLeading)

            if max.width > 1 || max.height > 1 {
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                let h = abs(value.translation.width)
                                let v = abs(value.translation.height)
                                guard v > h else { return }
                                photoOffset = CGSize(
                                    width: min(max.width, Swift.max(-max.width,
                                               gestureStart.width + value.translation.width)),
                                    height: min(max.height, Swift.max(-max.height,
                                                gestureStart.height + value.translation.height))
                                )
                            }
                            .onEnded { value in
                                let h = abs(value.translation.width)
                                let v = abs(value.translation.height)
                                if v > h { gestureStart = photoOffset }
                            }
                    )
            }
        }
        .clipped()
        .frame(width: 300, height: 375)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onChange(of: photoOffset) { _, new in
            if new == .zero { gestureStart = .zero }
        }
    }
}
