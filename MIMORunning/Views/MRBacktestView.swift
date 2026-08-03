import SwiftUI

private let mrBtAccent = Color(red: 0.48, green: 0.36, blue: 0.98)
private let mrBtCard   = Color(red: 0.11, green: 0.11, blue: 0.12)
private let mrBtGood   = Color(red: 0.30, green: 0.80, blue: 0.55)
private let mrBtWarn   = Color(red: 0.95, green: 0.68, blue: 0.25)

struct MRBacktestView: View {
    let rows: [MRBacktestRow]
    @State private var showAll = false

    private var scored: [MRBacktestRow] { rows.filter { $0.predictedMin != nil } }
    private var hit: Int { scored.filter(\.inBand).count }
    private var meanAbsErr: Double {
        let e = scored.compactMap(\.errorPct).map(abs)
        return e.isEmpty ? 0 : e.reduce(0, +) / Double(e.count)
    }
    // ⚠ 대회가 쌓이면 15건, 20건이 된다. 전부 나열하면 스크롤만 길어지고
    //   오래된 건 의미도 줄어든다(그 사이 몸이 바뀌었다).
    //   최근 5건만 보이고 나머지는 접는다.
    private var visible: [MRBacktestRow] {
        showAll ? Array(scored.reversed()) : Array(scored.reversed().prefix(5))
    }

    var body: some View {
        if !scored.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("예측이 얼마나 맞았나")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("각 기록을 **그 전날까지의 데이터만으로** 예측했다면 얼마였을지 다시 계산한 것입니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mrInk3)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 3) {
                    Text("\(hit)").font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("/ \(scored.count)").font(.system(size: 15))
                        .foregroundStyle(Color.mrInk3)
                        .padding(.bottom, 4)
                    Text("구간 안 · 평균 오차 \(String(format: "%.1f", meanAbsErr))%")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mrInk3)
                        .padding(.leading, 6).padding(.bottom, 5)
                }
                .padding(.top, 14)

                ForEach(visible) { r in
                    MRBacktestRowView(row: r).padding(.top, 14)
                }

                if scored.count > 5 {
                    Button(showAll ? "접기" : "전체 \(scored.count)건 보기") {
                        withAnimation { showAll.toggle() }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(mrBtAccent)
                    .padding(.top, 14)
                }

                // ⚠ 예측하지 못한 건도 숨기지 않는다.
                let skipped = rows.filter { $0.predictedMin == nil }
                if !skipped.isEmpty {
                    Text("\(skipped.count)건은 그 시점에 사전 기록이 부족해 예측하지 못했습니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mrInk3)
                        .padding(.top, 16)
                }

                Text("표본이 \(scored.count)건뿐입니다. 예측은 참고용이고, 특히 마라톤은 ±20분 이상 벌어질 수 있습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mrInk3)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(mrBtCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct MRBacktestRowView: View {
    let row: MRBacktestRow

    private var errColor: Color {
        guard let e = row.errorPct else { return .white }
        return abs(e) <= 3 ? mrBtGood : (abs(e) <= 8 ? mrBtAccent : mrBtWarn)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.date.formatted(.dateTime.year().month().day()
                                        .locale(Locale(identifier: "ko_KR"))))
                    .font(.system(size: 12)).foregroundStyle(Color.mrInk3)
                Text(row.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(mrBtAccent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(mrBtAccent.opacity(0.15)).clipShape(Capsule())
                Spacer()
                if let e = row.errorPct {
                    Text(String(format: "%+.1f%%", e))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(errColor)
                }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("실제").font(.system(size: 10)).foregroundStyle(Color.mrInk3)
                    Text(mrFormatDisplay(row.actualMin))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("예측").font(.system(size: 10)).foregroundStyle(Color.mrInk3)
                    Text(mrFormatDisplay(row.predictedMin ?? 0))
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Text(row.inBand ? "구간 안" : "구간 밖")
                    .font(.system(size: 11))
                    .foregroundStyle(row.inBand ? mrBtGood : mrBtWarn)
            }
            // 예측 구간과 실제의 위치를 막대로
            if let lo = row.loMin, let hi = row.hiMin, hi > lo {
                GeometryReader { g in
                    let x = min(max((row.actualMin - lo) / (hi - lo), 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(mrBtAccent.opacity(0.18))
                        Capsule().fill(.white)
                            .frame(width: 3).offset(x: g.size.width * x - 1.5)
                    }
                }
                .frame(height: 6)
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - 건강 습관 카드

struct MRHealthMetricsView: View {
    let m: MRHealthMetrics

    private let dayNames = ["", "일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        if m.sessions90 > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("러닝 습관")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                // 습관 요일 / 균등 메시지
                if !m.habitDays.isEmpty {
                    Text("주로 \(m.habitDays.map { dayNames[$0] }.joined(separator: "·"))요일에 나가시네요"
                         + (m.typicalHour.map { ", 보통 \($0)시쯤이고요" } ?? ""))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    Text("특정 요일에 몰리지 않고 고르게 나가시네요"
                         + (m.typicalHour.map { ". 보통 \($0)시쯤입니다" } ?? ""))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                }

                // 90일 통계
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("최근 90일")
                            .font(.system(size: 10)).foregroundStyle(Color.mrInk3)
                        Text("\(m.sessions90)회  \(Int(m.km90))km")
                            .font(.system(size: 13, design: .rounded)).foregroundStyle(.white)
                    }
                    if m.sessions90LY > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("작년 같은 기간")
                                .font(.system(size: 10)).foregroundStyle(Color.mrInk3)
                            Text("\(m.sessions90LY)회  \(Int(m.km90LY))km")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }

                // RHR / VO2max 당해·작년
                if m.restingHR != nil || m.vo2max != nil {
                    HStack(spacing: 16) {
                        if let rhr = m.restingHR {
                            metricPair(label: "안정시 심박",
                                       current: String(format: "%.0f", rhr),
                                       last: m.restingHRLY.map { String(format: "%.0f", $0) },
                                       unit: "bpm")
                        }
                        if let v = m.vo2max {
                            metricPair(label: "VO2max",
                                       current: String(format: "%.1f", v),
                                       last: m.vo2maxLY.map { String(format: "%.1f", $0) },
                                       unit: "")
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(mrBtCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private func metricPair(label: String, current: String, last: String?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(Color.mrInk3)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(current + (unit.isEmpty ? "" : " \(unit)"))
                    .font(.system(size: 13, design: .rounded)).foregroundStyle(.white)
                if let l = last {
                    Text("(작년 \(l))")
                        .font(.system(size: 11)).foregroundStyle(Color.mrInk3)
                }
            }
        }
    }
}

// MARK: - 드리프트 카드

struct MRDriftView: View {
    let drift: MRDriftModel

    var body: some View {
        // ⚠ 기온 범위 15°C 미만이면 15°C 기준값을 말할 수 없다 — 침묵.
        if drift.ok {
            VStack(alignment: .leading, spacing: 16) {
                Text("심박 드리프트")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.mrInk1)

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("선선한 날 15°C")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.mrInk3)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.1f", drift.bpmPer10MinAtRef))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.mrInk1)
                            Text("bpm/10분")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.mrInk3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if drift.bpmPer10MinPerDegC > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("더운 날 30°C")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.mrInk3)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.1f", drift.bpmPer10Min(atC: 30)))
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.mrInk1)
                                Text("bpm/10분")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.mrInk3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Text(String(format: "같은 페이스로 45분이면 심박이 %.0fbpm 올라갑니다",
                            drift.bpmPer10MinAtRef * 4.5))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mrInk2)
                    .fixedSize(horizontal: false, vertical: true)

                // ⚠ 근거 없는 해석을 붙이지 않는다. 관측값과 표본만 적는다.
                Text("최근 1년 \(drift.sessions)개 세션 · 기온 범위 \(Int(drift.tempSpanC))°C")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mrInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(mrBtCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
