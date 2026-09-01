import SwiftUI

private let mrBtAccent = Color(red: 0.48, green: 0.36, blue: 0.98)
private let mrBtCard   = Color(red: 0.11, green: 0.11, blue: 0.12)
private let mrBtGood   = Color(red: 0.30, green: 0.80, blue: 0.55)
private let mrBtWarn   = Color(red: 0.95, green: 0.68, blue: 0.25)

private func mrBtStandardLabel(km: Double) -> String? {
    let m = km * 1000
    let standards: [(Double, String)] = [
        (MRDistance.d5, "5K"), (MRDistance.d10, "10K"),
        (MRDistance.dH, "하프"), (MRDistance.dF, "풀")
    ]
    return standards.first { abs($0.0 - m) / $0.0 <= 0.02 }?.1
}

private func mrBtLocalizedLabel(_ raw: String) -> String {
    guard AppLanguage.shared.isEnglish else { return raw }
    switch raw {
    case "하프": return "Half"
    case "풀":   return "Full"
    default:     return raw
    }
}

struct MRBacktestView: View {
    let rows: [MRBacktestRow]
    let confirmedMatches: [PersistedRaceMatch]
    var archives: [RaceArchive] = []
    @State private var showAll = false
    @State private var selectedArchive: RaceArchive? = nil

    private var scored: [MRBacktestRow] { rows.filter { $0.predictedMin != nil } }
    private var hit: Int { scored.filter(\.inBand).count }
    private var meanAbsErr: Double {
        let e = scored.compactMap(\.errorPct).map(abs)
        return e.isEmpty ? 0 : e.reduce(0, +) / Double(e.count)
    }
    private var visible: [MRBacktestRow] {
        showAll ? Array(scored.reversed()) : Array(scored.reversed().prefix(5))
    }

    private func raceName(for row: MRBacktestRow) -> String? {
        let cal = Calendar.current
        return confirmedMatches.first {
            $0.isConfirmed &&
            cal.isDate($0.raceDate, inSameDayAs: row.date) &&
            mrBtStandardLabel(km: $0.distanceKm) == row.label
        }?.raceName
    }

    private func archive(for row: MRBacktestRow) -> RaceArchive? {
        let cal = Calendar.current
        return archives.first {
            cal.isDate($0.raceDate, inSameDayAs: row.date) &&
            abs($0.distanceM - mrDistanceFor(label: row.label)) / max($0.distanceM, 1) <= 0.02
        }
    }

    // 아카이브가 있지만 백테스트 행이 없는 것 (불참·예측 불가)
    private var unmatchedArchives: [RaceArchive] {
        let cal = Calendar.current
        let rowDays = Set(scored.map { cal.startOfDay(for: $0.date) })
        return archives
            .filter { !rowDays.contains(cal.startOfDay(for: $0.raceDate)) }
            .sorted { $0.raceDate > $1.raceDate }
    }

    var body: some View {
        let L = AppLanguage.shared
        let hasContent = !scored.isEmpty || !archives.isEmpty
        if hasContent {
            VStack(alignment: .leading, spacing: 0) {
                Text(L.s("예측이 얼마나 맞았나", "Prediction Accuracy"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(L.s("각 기록을 **그 전날까지의 데이터만으로** 예측했다면 얼마였을지 다시 계산한 것입니다.",
                         "Each result re-calculated using **only data from before** that race."))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mrInk3)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)

                if !scored.isEmpty {
                    HStack(spacing: 3) {
                        Text("\(hit)").font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("/ \(scored.count)").font(.system(size: 15))
                            .foregroundStyle(Color.mrInk3)
                            .padding(.bottom, 4)
                        Text(L.s("구간 안 · 평균 오차 \(String(format: "%.1f", meanAbsErr))%",
                                 "In range · Avg error \(String(format: "%.1f", meanAbsErr))%"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mrInk3)
                            .padding(.leading, 6).padding(.bottom, 5)
                    }
                    .padding(.top, 14)

                    ForEach(visible) { r in
                        let arch = archive(for: r)
                        MRBacktestRowView(row: r,
                                         raceName: raceName(for: r),
                                         archive: arch) {
                            selectedArchive = arch
                        }
                        .padding(.top, 14)
                    }

                    if scored.count > 5 {
                        Button(showAll ? L.s("접기", "Collapse") : L.s("전체 \(scored.count)건 보기", "Show all \(scored.count)")) {
                            withAnimation { showAll.toggle() }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(mrBtAccent)
                        .padding(.top, 14)
                    }

                    let skipped = rows.filter { $0.predictedMin == nil }
                    if !skipped.isEmpty {
                        Text(L.s("\(skipped.count)건은 그 시점에 사전 기록이 부족해 예측하지 못했습니다.",
                                 "\(skipped.count) race(s) lacked sufficient prior data for prediction."))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mrInk3)
                            .padding(.top, 16)
                    }

                    Text(L.s("표본이 \(scored.count)건뿐입니다. 예측은 참고용이고, 특히 마라톤은 ±20분 이상 벌어질 수 있습니다.",
                             "Only \(scored.count) sample(s). Estimates only — marathons can vary by ±20 min or more."))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mrInk3)
                        .padding(.top, 10)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 백테스트에 짝 없는 아카이브 (불참·예측 불가)
                if !unmatchedArchives.isEmpty {
                    Text(scored.isEmpty ? L.s("기록 없는 대회", "Races without times") : L.s("예측 없이 참가한 대회", "Races with no prediction"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 20)

                    ForEach(unmatchedArchives, id: \.raceDate) { arch in
                        Button {
                            selectedArchive = arch
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(arch.raceName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                    HStack(spacing: 6) {
                                        Text(arch.raceDate.formatted(.dateTime.year().month().day()
                                                                     .locale(L.isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "ko_KR"))))
                                            .font(.system(size: 11)).foregroundStyle(Color.mrInk3)
                                        Text(mrBtLocalizedLabel(mrLabelFor(distanceM: arch.distanceM)))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(mrBtAccent)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(mrBtAccent.opacity(0.15)).clipShape(Capsule())
                                    }
                                }
                                Spacer()
                                if arch.hasResult {
                                    Text(mrFormatDisplay(arch.actualMin))
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundStyle(.white)
                                } else {
                                    Text(L.s("기록 없음", "No result"))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.mrInk3)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.mrInk3)
                                    .padding(.leading, 4)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(mrBtCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .sheet(item: $selectedArchive) { arch in
                MRArchiveDetailView(archive: arch)
            }
        }
    }
}

// 거리 레이블 → 미터 역변환
private func mrDistanceFor(label: String) -> Double {
    switch label {
    case "5K":  return MRDistance.d5
    case "10K": return MRDistance.d10
    case "하프": return MRDistance.dH
    case "풀":  return MRDistance.dF
    default:    return 0
    }
}

struct MRBacktestRowView: View {
    let row: MRBacktestRow
    var raceName: String? = nil
    var archive: RaceArchive? = nil
    var onTapArchive: (() -> Void)? = nil

    private var errColor: Color {
        guard let e = row.errorPct else { return .white }
        return abs(e) <= 3 ? mrBtGood : (abs(e) <= 8 ? mrBtAccent : mrBtWarn)
    }

    var body: some View {
        let L = AppLanguage.shared
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.date.formatted(.dateTime.year().month().day()
                                        .locale(L.isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "ko_KR"))))
                    .font(.system(size: 12)).foregroundStyle(Color.mrInk3)
                Text(mrBtLocalizedLabel(row.label))
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
                // 아카이브 있으면 꺾쇠
                if archive != nil {
                    Button(action: onTapArchive ?? {}) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(mrBtAccent.opacity(0.7))
                            .padding(.leading, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let name = raceName ?? archive?.raceName {
                Text(name)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.yellow)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L.s("실제", "Actual")).font(.system(size: 10)).foregroundStyle(Color.mrInk3)
                    Text(mrFormatDisplay(row.actualMin))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    if let arch = archive {
                        if arch.reconstructed {
                            // 소급 재구성: 당시 앱 예측이 아님
                            Text(L.s("소급 계획 예측", "Projected (retroactive)")).font(.system(size: 10)).foregroundStyle(Color.mrInk3)
                            Text(mrFormatDisplay(arch.snapshotProjectedFinalMin))
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                            Text(L.s("지금 모델로 소급 계산", "Recalculated with current model"))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.mrInk3.opacity(0.7))
                        } else {
                            // 실제 아카이브: 당시 앱이 예측한 값
                            Text(L.s("그때 앱 예측", "App's prediction at the time")).font(.system(size: 10)).foregroundStyle(Color.mrInk3)
                            Text(mrFormatDisplay(arch.snapshotProjectedFinalMin))
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    } else {
                        // 아카이브 없음: 현재 모델 역산
                        Text(L.s("예측", "Predicted")).font(.system(size: 10)).foregroundStyle(Color.mrInk3)
                        Text(mrFormatDisplay(row.predictedMin ?? 0))
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(L.s("지금 모델로 역산", "Back-calculated with current model"))
                            .font(.system(size: 9))
                            .foregroundStyle(Color.mrInk3.opacity(0.7))
                    }
                }
                Spacer()
                Text(row.inBand ? L.s("구간 안", "In range") : L.s("구간 밖", "Out of range"))
                    .font(.system(size: 11))
                    .foregroundStyle(row.inBand ? mrBtGood : mrBtWarn)
            }
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
        .contentShape(Rectangle())
        .onTapGesture { if archive != nil { onTapArchive?() } }
    }
}

// MARK: - 아카이브 상세 (마크다운 전체 표시)

struct MRArchiveDetailView: View {
    let archive: RaceArchive
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(archive.markdown)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(Color(red: 0.07, green: 0.07, blue: 0.08))
            .navigationTitle(archive.raceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLanguage.shared.s("닫기", "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - 건강 습관 카드

struct MRHealthMetricsView: View {
    let m: MRHealthMetrics

    private var dayNames: [String] {
        AppLanguage.shared.isEnglish
            ? ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            : ["", "일", "월", "화", "수", "목", "금", "토"]
    }

    private var habitDayText: String {
        let L = AppLanguage.shared
        if L.isEnglish {
            let days = m.habitDays.map { dayNames[$0] }.joined(separator: ", ")
            let hour = m.typicalHour.map { ", typically around \($0):00" } ?? ""
            return "You usually run on \(days)\(hour)"
        } else {
            let days = m.habitDays.map { dayNames[$0] }.joined(separator: "·")
            let hour = m.typicalHour.map { ", 보통 \($0)시쯤이고요" } ?? ""
            return "주로 \(days)요일에 나가시네요\(hour)"
        }
    }

    private var evenDayText: String {
        let L = AppLanguage.shared
        if L.isEnglish {
            let hour = m.typicalHour.map { ", typically around \($0):00" } ?? ""
            return "Your runs are evenly spread across the week\(hour)"
        } else {
            let hour = m.typicalHour.map { ". 보통 \($0)시쯤입니다" } ?? ""
            return "특정 요일에 몰리지 않고 고르게 나가시네요\(hour)"
        }
    }

    var body: some View {
        let L = AppLanguage.shared
        if m.sessions90 > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text(L.s("러닝 습관", "Running Habit"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                // 습관 요일 / 균등 메시지
                Text(!m.habitDays.isEmpty ? habitDayText : evenDayText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))

                // 90일 통계
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.s("최근 90일", "Last 90 days"))
                            .font(.system(size: 10)).foregroundStyle(Color.mrInk3)
                        Text(L.s("\(m.sessions90)회  \(Int(m.km90))km", "\(m.sessions90) runs  \(Int(m.km90)) km"))
                            .font(.system(size: 13, design: .rounded)).foregroundStyle(.white)
                    }
                    if m.sessions90LY > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.s("작년 같은 기간", "Same period last yr"))
                                .font(.system(size: 10)).foregroundStyle(Color.mrInk3)
                            Text(L.s("\(m.sessions90LY)회  \(Int(m.km90LY))km", "\(m.sessions90LY) runs  \(Int(m.km90LY)) km"))
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }

                // RHR / VO2max 당해·작년
                if m.restingHR != nil || m.vo2max != nil {
                    HStack(spacing: 16) {
                        if let rhr = m.restingHR {
                            metricPair(label: L.s("안정시 심박", "Resting HR"),
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
                    Text(AppLanguage.shared.s("(작년 \(l))", "(last yr \(l))"))
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
        let L = AppLanguage.shared
        if drift.ok {
            VStack(alignment: .leading, spacing: 16) {
                Text(L.s("심박 드리프트", "HR Drift"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.mrInk1)

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.s("선선한 날 15°C", "Cool day 15°C"))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.mrInk3)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.1f", drift.bpmPer10MinAtRef))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.mrInk1)
                            Text(L.s("bpm/10분", "bpm/10 min"))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.mrInk3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if drift.bpmPer10MinPerDegC > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.s("더운 날 30°C", "Hot day 30°C"))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.mrInk3)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.1f", drift.bpmPer10Min(atC: 30)))
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.mrInk1)
                                Text(L.s("bpm/10분", "bpm/10 min"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.mrInk3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Text(String(format: L.s("같은 페이스로 45분이면 심박이 %.0fbpm 올라갑니다",
                                        "At the same pace for 45 min, HR rises by %.0f bpm"),
                            drift.bpmPer10MinAtRef * 4.5))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mrInk2)
                    .fixedSize(horizontal: false, vertical: true)

                // ⚠ 근거 없는 해석을 붙이지 않는다. 관측값과 표본만 적는다.
                Text(L.s("최근 1년 \(drift.sessions)개 세션 · 기온 범위 \(Int(drift.tempSpanC))°C",
                         "Past year · \(drift.sessions) sessions · \(Int(drift.tempSpanC))°C range"))
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
