import SwiftUI
import Charts

/// 성장 탭 — 선택한 달의 일별 sRPE 부하(AU). 막대 색 = 그날 평균 강도.
/// 일간 거리 차트 바로 아래에 붙어 같은 달을 따라간다. 레이아웃(높이·패딩·축)은 DailyDistanceChart와 동일.
struct MonthlyEffortLoadChart: View {
    /// 해당 월 1일 00:00 ~ 다음 달 1일 00:00
    let window: EffortLoad.WindowLoad

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
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L.s("이달 부하 \(totalText) AU", "This month \(totalText) AU"))
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
        Chart(Array(window.daily.indices), id: \.self) { i in
            BarMark(
                x: .value("일", i + 1),
                y: .value("부하(AU)", window.daily[i])
            )
            .foregroundStyle(barColor(i).gradient)
            .cornerRadius(2)
        }
        .frame(height: 180)
        .chartXScale(domain: 1...31)
        .chartXAxis {
            AxisMarks(values: [1, 7, 14, 21, 28]) { value in
                AxisValueLabel {
                    Text("\(value.as(Int.self) ?? 0)")
                        .font(.caption2)
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
        .accessibilityLabel(L.s("월간 강도 부하", "Monthly training load"))
        .accessibilityValue(accessibilityValue)
    }

    private func barColor(_ i: Int) -> Color {
        guard window.daily.indices.contains(i), window.daily[i] > 0 else {
            return Color.secondary.opacity(0.45)
        }
        let mean = window.dailyMeanEffort.indices.contains(i) ? window.dailyMeanEffort[i] : nil
        return EffortPalette.color(for: EffortResolver.clamp(mean ?? 5))
    }

    /// 부하가 있는 날만 "3일 280, 5일 270" 형태로 읽어 준다.
    private var accessibilityValue: String {
        let parts = window.daily.indices.compactMap { i -> String? in
            guard window.daily[i] > 0 else { return nil }
            let au = Int(window.daily[i].rounded())
            return L.s("\(i + 1)일 \(au)", "day \(i + 1) \(au)")
        }
        return parts.isEmpty ? L.s("기록 없음", "No load") : parts.joined(separator: ", ")
    }
}
