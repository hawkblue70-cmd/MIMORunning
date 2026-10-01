import SwiftUI
import Charts

/// 성장 탭 '역치 페이스' — 큰 숫자는 현재 추정(기록·심박 교차), 점은 최근 12개월 강한 러닝을 60분 대회 페이스로 환산한 값.
/// 선이 아니라 점인 이유는 `MRThresholdTrendResult` 참고. 굵은 점 = 큰 숫자의 기준 기록, 점선 = 큰 숫자.
/// 값은 엔진(`mrThresholdTrend`)이 내고 여기선 그리기만. 표시 조건(중수 이상·3점 이상)은 GrowthView가 건다.
/// 카드 모양은 같은 섹션의 `MRFormObservationCard`(바탕·모서리·제목·본문·근거 글자)와 같게.
/// 설계: docs/superpowers/specs/2026-10-01-threshold-estimate-design.md
struct ThresholdTrendCard: View {
    let trend: MRThresholdTrendResult

    @State private var expanded = false

    private var basisLines: [String] { trend.current.basis }

    var body: some View {
        let L = AppLanguage.shared
        let pts = trend.points
        let current = trend.current
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "speedometer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mrInk3)
                Text(L.s("역치 페이스", "Threshold Pace"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(mrFormatPace(current.paceSecPerKm))/km")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.pace)
                if let hr = current.hr {
                    Text(L.s(" · 역치 심박 \(Int(hr.rounded()))bpm", " · Threshold HR \(Int(hr.rounded()))bpm"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mrInk2)
                }
            }

            if let s = trend.sentence {
                Text(s)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.positive)
            }

            chart(pts)
                .frame(height: 100)

            Text(L.s("점: 최근 12개월 강한 러닝을 60분 대회 페이스로 환산 · 굵은 점이 지금 기준 기록",
                     "Dots: hard runs in the last 12 months as 1-hour race pace · bold dot is the current anchor"))
                .font(.system(size: 11))
                .foregroundStyle(Color.mrInk3)
                .fixedSize(horizontal: false, vertical: true)

            // 설명 줄 — 탭하면 최신 시점 근거줄을 펼친다
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 4) {
                    Text(L.s("오래 버틸 수 있는 가장 빠른 페이스(약 1시간 대회 페이스) · 본인 기록으로 낸 추정",
                             "The fastest pace you can hold for a long time (about 1-hour race pace) · estimated from your runs"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mrInk3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.mrInk3)
                }
            }
            .buttonStyle(.plain)

            if expanded, !basisLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(basisLines, id: \.self) { b in
                        Text("· " + b)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mrInk3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// y축 — 위가 빠름(반전). 점과 큰 숫자가 모두 들어오게, 최소 ±10초.
    /// ⚠ 10초는 임의로 정함 — 문장 문턱(3초)이 눈에 띄되 과장되지 않는 폭.
    private func yDomain(_ pts: [MRThresholdEffortPoint]) -> ClosedRange<Double> {
        let v = pts.map(\.paceSecPerKm) + [trend.current.paceSecPerKm]
        guard let lo = v.min(), let hi = v.max() else { return 0...1 }
        let mid = (lo + hi) / 2, half = max((hi - lo) / 2, 10)
        return (mid - half)...(mid + half)
    }

    /// 강한 러닝 점 — 기준 기록은 굵게, 나머지는 옅게. 점선 = 큰 숫자. 선으로 잇지 않는다(각 점이 독립된 기록).
    private func chart(_ pts: [MRThresholdEffortPoint]) -> some View {
        Chart {
            RuleMark(y: .value("current", trend.current.paceSecPerKm))
                .foregroundStyle(Theme.pace.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                if p.isAnchor {
                    PointMark(x: .value("date", p.date), y: .value("pace", p.paceSecPerKm))
                        .foregroundStyle(Color.white)
                        .symbolSize(Theme.sparkHaloSizeCompact * 1.6)
                    PointMark(x: .value("date", p.date), y: .value("pace", p.paceSecPerKm))
                        .foregroundStyle(Theme.pace)
                        .symbolSize(Theme.sparkHaloCoreSizeCompact * 1.6)
                } else {
                    PointMark(x: .value("date", p.date), y: .value("pace", p.paceSecPerKm))
                        .foregroundStyle(Theme.pace.opacity(0.45))
                        .symbolSize(Theme.sparkHaloCoreSizeCompact)
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false, reversed: true, dataType: Double.self) { inferred in
            let d = yDomain(pts)
            inferred.append(contentsOf: [d.lowerBound, d.upperBound])
        })
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(mrFormatPace(d)).font(.system(size: 9)).foregroundStyle(Color.mrInk3)
                    }
                }
            }
        }
        .chartXScale(range: .plotDimension(padding: 14))   // 양 끝 점의 달 라벨이 잘려 빠지지 않게
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.mrInk3)
            }
        }
    }
}
