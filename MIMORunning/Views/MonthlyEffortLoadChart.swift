import SwiftUI
import Charts

/// 성장 탭 — 선택한 기간의 일별 sRPE 부하(AU). 막대 색 = 그날 평균 강도.
/// 기간은 기본이 "오늘까지 최근 30일", "<"로 이동하면 전월 달력 단위 — 일간 거리 차트와 같은 창을 따라간다.
/// 레이아웃(높이·패딩·축)은 DailyDistanceChart와 동일.
struct MonthlyEffortLoadChart: View {
    /// 롤링 최근 30일 또는 달력 한 달
    let window: EffortLoad.WindowLoad
    /// true = 오늘까지 최근 30일(헤더 문구만 달라진다)
    let isRolling: Bool

    private var L: AppLanguage { AppLanguage.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            chart
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var header: some View {
        let totalText = window.total.rounded().formatted(.number.grouping(.automatic))
        let title = isRolling
            ? L.s("최근 30일 부하 \(totalText) AU", "Last 30 days \(totalText) AU")
            : L.s("이달 부하 \(totalText) AU", "This month \(totalText) AU")
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Text(L.s("러닝 \(window.runCount)회 중 \(window.coveredCount)회 강도 있음",
                     "\(window.coveredCount) of \(window.runCount) runs rated"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        Chart(Array(window.dayStarts.indices), id: \.self) { i in
            BarMark(
                x: .value("날짜", window.dayStarts[i], unit: .day),
                y: .value("부하(AU)", value(i))
            )
            .foregroundStyle(barColor(i).gradient)
            .cornerRadius(2)
        }
        .frame(height: 180)
        .chartXScale(domain: window.start...window.end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: .dateTime.month(.defaultDigits).day())
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    Text(String(format: "%.0f", value.as(Double.self) ?? 0))
                        .font(.caption2)
                }
                AxisGridLine()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.s("일별 강도 부하", "Daily training load"))
        .accessibilityValue(accessibilityValue)
    }

    private func value(_ i: Int) -> Double {
        window.daily.indices.contains(i) ? window.daily[i] : 0
    }

    private func barColor(_ i: Int) -> Color {
        guard value(i) > 0 else { return Color.secondary.opacity(0.45) }
        let mean = window.dailyMeanEffort.indices.contains(i) ? window.dailyMeanEffort[i] : nil
        return EffortPalette.color(for: EffortResolver.clamp(mean ?? 5))
    }

    /// 부하가 있는 날만 "3일 280, 5일 270" 형태로 읽어 준다.
    private var accessibilityValue: String {
        let cal = Calendar.current
        let parts = window.dayStarts.indices.compactMap { i -> String? in
            guard value(i) > 0 else { return nil }
            let au = Int(value(i).rounded())
            let day = cal.component(.day, from: window.dayStarts[i])
            return L.s("\(day)일 \(au)", "day \(day) \(au)")
        }
        return parts.isEmpty ? L.s("기록 없음", "No load") : parts.joined(separator: ", ")
    }
}
