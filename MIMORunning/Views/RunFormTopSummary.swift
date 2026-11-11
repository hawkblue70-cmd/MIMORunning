import SwiftUI

/// 폼 탭 맨 위 요약 — 큰 거리 + 러닝화 + 시간·페이스·케이던스·보폭.
/// 폼 탭과 밸런스 탭이 **이 뷰 하나**를 쓴다(§5.8: 같은 정보를 두 레이아웃으로 그리지 않는다, 2026-11-11).
struct RunFormTopSummary: View {
    @Environment(\.insightLight) private var insightLight
    @Environment(\.insightCompact) private var compact
    private var ink: InsightInk { InsightInk(light: insightLight) }

    let activity: Activity
    var splits: [SplitData] = []
    var altitudeProfile: [(distanceKm: Double, altitude: Double)] = []
    var avgCadence: Int? = nil
    var avgStrideLength: Double? = nil
    var intervalSegments: [IntervalSegment] = []
    var isInterval: Bool = false
    /// 이 러닝에 고른 러닝화 — 없으면 줄 없음
    var shoeName: String? = nil

    /// 상세 데이터에서 바로 — 인터벌 케이던스는 운동 구간 평균(폼 탭과 같은 값)
    static func make(activity: Activity, detail: ActivityDetail?, workoutType: WorkoutType,
                     shoeName: String?) -> RunFormTopSummary {
        let isInterval = workoutType == .interval
        let cadence: Int? = {
            guard isInterval,
                  let wc = IntervalSegment.workAverage(detail?.intervalSegments ?? [], { $0.avgCadence.map(Double.init) })
            else { return detail?.avgCadence }
            return Int(wc.rounded())
        }()
        return RunFormTopSummary(activity: activity, splits: detail?.splits ?? [],
                                 altitudeProfile: detail?.altitudeProfile ?? [],
                                 avgCadence: cadence, avgStrideLength: detail?.avgStrideLength,
                                 intervalSegments: detail?.intervalSegments ?? [],
                                 isInterval: isInterval, shoeName: shoeName)
    }

    private var flatEquivalentText: String? {
        GradeAdjustedPace.kpiText(splits: splits, altitudeProfile: altitudeProfile,
                                  actualPaceSecPerKm: activity.paceSecPerKm)
    }

    private var kpiSep: some View {
        Rectangle().fill(ink.fg(0.10)).frame(width: 0.5, height: 40)
    }

    var body: some View {
        let km = activity.distance / 1000
        let kmStr = mrRunKm(km)
        return VStack(alignment: .leading, spacing: compact ? 5 : 10) {
            HStack(alignment: .top, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(kmStr)
                        .font(cardNumFont(40))
                        .tracking(-1.6)
                    Text("km")
                        .font(.system(size: 16))
                        .foregroundStyle(ink.pick(Color(hex: "8A8F99"), Color(hex: "757575")))
                }
                .foregroundStyle(ink.primary)
                // 러닝화 — 오른쪽 맨 위, 리듬·퍼포먼스와 같은 연두(카드 한 장만 내보내도 보이게)
                if let shoe = shoeName, !shoe.isEmpty {
                    Spacer(minLength: 4)
                    Text(shoe)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(ink.pick(Theme.power, Color(hex: "5A8F00")))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, 4)
                }
            }
            HStack(spacing: 0) {
                KPICell(label: AppLanguage.shared.s("시간", "Time", ja: "時間"),
                        value: activity.formattedDuration)
                kpiSep
                KPICell(label: AppLanguage.shared.s("페이스", "Pace", ja: "ペース"),
                        value: activity.formattedPace ?? "--'--\"",
                        context: flatEquivalentText, contextColor: ink.fg(0.58))
                if let cad = avgCadence {
                    kpiSep
                    KPICell(label: AppLanguage.shared.s("케이던스", "Cadence", ja: "ケイデンス"),
                            value: "\(cad)", unit: "spm",
                            color: ink.cadence,
                            context: isInterval ? AppLanguage.shared.s("전력 구간", "work segs", ja: "本練習区間") : nil)
                }
                // 인터벌은 케이던스와 같은 전력 구간 값 — 케이던스 184(전력)에 보폭 0.98(전체)처럼 짝이 어긋나지 않게
                let displayStride: Double? = isInterval
                    ? (IntervalSegment.workAverage(intervalSegments, \.computedStride) ?? avgStrideLength)
                    : avgStrideLength
                if let sl = displayStride {
                    kpiSep
                    KPICell(label: AppLanguage.shared.s("보폭", "Stride", ja: "ストライド"),
                            value: String(format: "%.2f", sl), unit: "m",
                            color: ink.primary,
                            context: isInterval ? AppLanguage.shared.s("전력 구간", "work segs", ja: "本練習区間") : nil)
                }
            }
        }
    }
}
