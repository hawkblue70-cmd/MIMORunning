import SwiftUI
import Charts

/// 성장 탭 '후반 내구성' — 최근 롱런들이 후반에 무엇이 먼저 무너졌나(내 취약점)와 후반 효율 하락 추세.
/// 러닝 한 건의 판정은 총평 '후반' 줄과 같은 `LateRunDiagnosis`. 진단된 러닝이 2회 미만이면 그리지 않는다.
struct LateRunDurabilityCard: View {
    let points: [LateRunPoint]

    private static let cardBG = Color(red: 0.11, green: 0.11, blue: 0.12)   // 심박 드리프트 카드와 같은 바탕

    static func color(_ k: LateRunDiagnosis.Kind) -> Color {
        switch k {
        case .held:     return Theme.positive
        case .cardio:   return Color(hex: "FF453A")
        case .legs:     return Color(hex: "FF9A3C")
        case .energy:   return Color(hex: "F5C542")
        case .combined: return Color(hex: "BF5AF2")
        }
    }

    static func icon(_ k: LateRunDiagnosis.Kind) -> String {
        switch k {
        case .held:     return "checkmark"
        case .cardio:   return "lungs.fill"
        case .legs:     return "figure.run"
        case .energy:   return "bolt.slash.fill"
        case .combined: return "arrow.left.arrow.right"
        }
    }

    static func shortName(_ k: LateRunDiagnosis.Kind) -> String {
        let L = AppLanguage.shared
        switch k {
        case .held:     return L.s("유지", "Held")
        case .cardio:   return L.s("심박", "HR")
        case .legs:     return L.s("다리", "Legs")
        case .energy:   return L.s("힘 빠짐", "Low")
        case .combined: return L.s("함께", "Both")
        }
    }

    /// 유지 + 후반 가속이면 '가속'(같은 초록) — 추세 차트에 점이 없는 이유를 줄에서 보이게
    static func icon(_ p: LateRunPoint) -> String {
        p.kind == .held && p.isFastFinish ? "arrow.up.right" : icon(p.kind)
    }

    static func shortName(_ p: LateRunPoint) -> String {
        p.kind == .held && p.isFastFinish ? AppLanguage.shared.s("가속", "Faster") : shortName(p.kind)
    }

    var body: some View {
        let L = AppLanguage.shared
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.s("후반 내구성", "Late-Run Durability"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.mrInk1)

                if let s = LateRunPoint.sentence(points) {
                    Text(s)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mrInk2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                kindStrip

                let chartPts = points.filter { $0.decouplingPct != nil }
                if chartPts.count >= 3 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.s("최근 \(LateRunPoint.windowWeeks)주 · 후반에 같은 속도에 드는 심박 증가(중반 대비)",
                                 "Last \(LateRunPoint.windowWeeks) weeks · extra HR for the same speed, late vs mid"))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.mrInk3)
                        chart(chartPts)
                            .frame(height: 120)
                        if let t = LateRunPoint.trendSentence(points) {
                            Text(t)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.mrInk2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text(L.s("최근 \(LateRunPoint.windowWeeks)주 60분 이상 러닝 \(points.count)회 · 인터벌·빌드업·템포 제외 · 5% 아래면 후반까지 유지 · 가속 = 후반 10초/km 이상 빨라짐(차트 제외)",
                         "Last \(LateRunPoint.windowWeeks) weeks · \(points.count) runs over 60 min · excl. intervals, build-ups, tempo · under 5% = held · Faster = late 10+ s/km quicker (not charted)"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mrInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.cardBG)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    /// 최근 러닝(최대 6회, 오래된 → 최근)의 유형 — 아이콘 · 이름 · 날짜 · 거리
    private var kindStrip: some View {
        let recent = Array(points.suffix(LateRunPoint.recentCount))
        let df: DateFormatter = { let f = DateFormatter(); f.dateFormat = "M/d"; return f }()
        return HStack(spacing: 0) {
            ForEach(recent) { p in
                VStack(spacing: 4) {
                    ZStack {
                        Circle().fill(Self.color(p.kind).opacity(0.18))
                        Image(systemName: Self.icon(p))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Self.color(p.kind))
                    }
                    .frame(width: 30, height: 30)
                    Text(Self.shortName(p))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Self.color(p.kind))
                        .lineLimit(1)
                    Text(df.string(from: p.date))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color.mrInk3)
                    Text(String(format: "%.0fkm", p.distanceKm))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.mrInk3)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func chart(_ pts: [LateRunPoint]) -> some View {
        Chart {
            RuleMark(y: .value("threshold", LateRunDiagnosis.decouplingThresholdPct))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.white.opacity(0.35))
            ForEach(pts) { p in
                LineMark(x: .value("date", p.date), y: .value("pct", p.decouplingPct ?? 0))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("date", p.date), y: .value("pct", p.decouplingPct ?? 0))
                    .foregroundStyle(Self.color(p.kind))
                    .symbolSize(36)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text("\(Int(d.rounded()))%").font(.system(size: 9)).foregroundStyle(Color.mrInk3)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: false)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.mrInk3)
            }
        }
    }
}
