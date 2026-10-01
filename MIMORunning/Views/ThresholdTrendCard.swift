import SwiftUI
import Charts

/// 성장 탭 '역치 페이스' — 최근 6개월 월말 기준 역치 페이스 추정 추세(빠를수록 위).
/// 값은 엔진(`mrThresholdTrend`)이 내고 여기선 그리기만. 표시 조건(중수 이상·3점 이상)은 GrowthView가 건다.
/// 카드 모양은 같은 섹션의 `MRFormObservationCard`(바탕·모서리·제목·본문·근거 글자)와 같게.
/// 설계: docs/superpowers/specs/2026-10-01-threshold-estimate-design.md
struct ThresholdTrendCard: View {
    let points: [MRThresholdEstimate]

    @State private var expanded = false

    var body: some View {
        let L = AppLanguage.shared
        let pts = points.sorted { $0.asOf < $1.asOf }
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

            if let last = pts.last {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(mrFormatPace(last.paceSecPerKm))/km")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.pace)
                    if let hr = last.hr {
                        Text(L.s(" · 역치 심박 \(Int(hr.rounded()))bpm", " · Threshold HR \(Int(hr.rounded()))bpm"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mrInk2)
                    }
                }
            }

            if let s = mrThresholdTrendSentence(pts) {
                Text(s)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.positive)
            }

            chart(pts)
                .frame(height: 100)

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

            if expanded, let basis = pts.last?.basis, !basis.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(basis, id: \.self) { b in
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

    /// y축 — 위가 빠름(반전). 값이 거의 같으면 1초 폭 축이 되어 작은 흔들림이 크게 보이므로 최소 ±10초를 확보한다.
    /// ⚠ 10초는 임의로 정함 — 추세 문장 문턱(3초)이 눈에 띄되 과장되지 않는 폭.
    private func yDomain(_ pts: [MRThresholdEstimate]) -> ClosedRange<Double> {
        let v = pts.map(\.paceSecPerKm)
        guard let lo = v.min(), let hi = v.max() else { return 0...1 }
        let mid = (lo + hi) / 2, half = max((hi - lo) / 2, 10)
        return (mid - half)...(mid + half)
    }

    /// 월별 라인 — y축 반전(페이스 초가 작을수록 = 빠를수록 위). 점 모양은 주간 지표 스파크라인과 같은 흰 테두리 점.
    private func chart(_ pts: [MRThresholdEstimate]) -> some View {
        Chart {
            ForEach(pts, id: \.asOf) { p in
                LineMark(x: .value("month", p.asOf), y: .value("pace", p.paceSecPerKm))
                    .foregroundStyle(Theme.pace)
                    .lineStyle(StrokeStyle(lineWidth: 2.0))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("month", p.asOf), y: .value("pace", p.paceSecPerKm))
                    .foregroundStyle(Color.white)
                    .symbolSize(Theme.sparkHaloSizeCompact)
                PointMark(x: .value("month", p.asOf), y: .value("pace", p.paceSecPerKm))
                    .foregroundStyle(Theme.pace)
                    .symbolSize(Theme.sparkHaloCoreSizeCompact)
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
        .chartXAxis {
            AxisMarks(values: pts.map(\.asOf)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.mrInk3)
            }
        }
    }
}
