import SwiftUI
import Charts

/// 성장 탭 '같은 페이스 심박' — 평소 페이스 띠(본인 km 페이스 중앙값 ±10초) km의 심박을 15°C·띠 가운데 페이스로 환산.
/// 주별 점(옅게) + 최근 4주 중앙값 선(굵게), 주마다 갱신(2026-11-10 사용자 B안 — 전엔 월별).
/// 방향 판정은 하지 않는다 — 처음 달과 최근 달 숫자만 나란히, 설명은 늘 같은 문장(안정시 심박 카드와 같은 원칙, 2026-11-03).
/// 값은 엔진(`MRTempoEfficiency.usualTrend`)이 내고 여기선 그리기만. 4주 선 점이 8개 미만이면 엔진이 nil → 카드 없음.
/// 근거: 표준화된 최대하 속도의 심박 변화 ↔ 유산소 체력 변화(Int J Sports Med 2023 체계적 문헌고찰).
/// 카드 모양은 `RestingHRTrendCard`(바탕·모서리·제목·본문·근거 글자)와 같게.
struct UsualPaceHRCard: View {
    let trend: MRTempoEfficiency.UsualTrend

    var body: some View {
        let L = AppLanguage.shared
        let pace = mrFormatPace(trend.centerPace)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mrInk3)
                Text(L.s("같은 페이스 심박", "HR at your usual pace", ja: "同じペースの心拍"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(trend.latest.hr.rounded()))bpm")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.heartRate)
                Text(L.s(" · \(pace) 페이스, 최근 4주", " · at \(pace), last 4 weeks", ja: " · \(pace)ペース、直近4週"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mrInk2)
            }

            // 처음 4주 → 최근 4주 숫자만 — "좋아짐/나빠짐" 판정어 없음. 날짜 = 그 4주의 마지막 주
            let a = Self.dayName(trend.first.weekStart), b = Self.dayName(trend.latest.weekStart)
            let f = Int(trend.first.hr.rounded()), l = Int(trend.latest.hr.rounded())
            Text(L.s("\(a) 주 \(f) → \(b) 주 \(l) · 4주 중앙값, 주마다 갱신",
                     "Week of \(a) \(f) → week of \(b) \(l) · 4-week median, updated weekly",
                     ja: "\(a)の週 \(f) → \(b)の週 \(l) · 4週の中央値、毎週更新"))
                .font(.system(size: 13))
                .foregroundStyle(Color.mrInk2)

            // 늘 같은 일반 설명 — 데이터에 따라 바뀌지 않는다
            Text(L.s("같은 페이스에서 심박이 낮아지면 같은 노력으로 더 빨리 달릴 수 있다는 뜻입니다. 더위·피로·수면에 따라 몇 bpm씩 흔들립니다.",
                     "A lower HR at the same pace means you can run faster for the same effort. It moves a few bpm with heat, fatigue and sleep.",
                     ja: "同じペースで心拍が下がれば、同じ努力でより速く走れるということです。暑さ・疲労・睡眠で数bpm揺れます。"))
                .font(.system(size: 12))
                .foregroundStyle(Color.mrInk2)
                .fixedSize(horizontal: false, vertical: true)

            chart
                .frame(height: 100)

            Text(L.s("점: 2번 이상 뛴 주 · 선: 최근 4주(5번 이상) · \(mrFormatPace(trend.band.lowerBound))~\(mrFormatPace(trend.band.upperBound)) km만 · 15°C·\(pace) 기준으로 환산 · 1·2km와 10km 뒤, 인터벌·대회 제외",
                     "Dots: weeks with 2+ runs · line: last 4 weeks (5+ runs) · Only km at \(mrFormatPace(trend.band.lowerBound))–\(mrFormatPace(trend.band.upperBound)) · adjusted to 15°C and \(pace) · excludes km 1–2, after km 10, intervals and races",
                     ja: "点: 2回以上走った週 · 線: 直近4週(5回以上) · \(mrFormatPace(trend.band.lowerBound))〜\(mrFormatPace(trend.band.upperBound))のkmのみ · 15°C・\(pace)基準に換算 · 1・2kmと10km以降、インターバル・レースを除く"))
                .font(.system(size: 11))
                .foregroundStyle(Color.mrInk3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// y축 — 최소 ±5bpm(안정시 심박 카드와 같은 폭, 몇 bpm 흔들림이 과장되지 않게)
    private var yDomain: ClosedRange<Double> {
        let v = trend.weeks.map(\.hr) + trend.rolling.map(\.hr)
        guard let lo = v.min(), let hi = v.max() else { return 0...1 }
        let mid = (lo + hi) / 2, half = max((hi - lo) / 2 + 1, 5)
        return (mid - half)...(mid + half)
    }

    /// "6/2" — 주 시작(월요일)
    static func dayName(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 1)/\(c.day ?? 1)"
    }

    private static let monthLabel: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yy.M"; return f
    }()

    private var chart: some View {
        Chart {
            // 주별 점 — 옅게(러닝 1~4번이라 흔들림이 크다)
            ForEach(trend.weeks, id: \.weekStart) { w in
                PointMark(x: .value("week", w.weekStart), y: .value("bpm", w.hr))
                    .foregroundStyle(Theme.heartRate.opacity(0.35))
                    .symbolSize(18)
            }
            // 최근 4주 중앙값 선 — 굵게
            ForEach(trend.rolling, id: \.weekStart) { w in
                LineMark(x: .value("week", w.weekStart), y: .value("bpm", w.hr))
                    .foregroundStyle(Theme.heartRate)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let last = trend.rolling.last {
                PointMark(x: .value("week", last.weekStart), y: .value("bpm", last.hr))
                    .foregroundStyle(Theme.heartRate)
                    .symbolSize(Theme.sparkHaloCoreSizeCompact)
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text("\(Int(d))").font(.system(size: 9)).foregroundStyle(Color.mrInk3)
                    }
                }
            }
        }
        .chartXScale(range: .plotDimension(padding: 12))
        .chartXAxis {
            // 달 첫날마다 라벨 — 주 점이 촘촘해 라벨은 달 단위로
            AxisMarks(values: .stride(by: .month)) { v in
                AxisValueLabel(anchor: .top) {
                    if let d = v.as(Date.self) {
                        Text(Self.monthLabel.string(from: d))
                            .font(.system(size: 9))
                            .foregroundStyle(Color.mrInk3)
                    }
                }
            }
        }
    }
}
