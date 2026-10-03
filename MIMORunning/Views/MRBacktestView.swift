import SwiftUI
import SwiftData

private let mrBtCard   = Color(red: 0.11, green: 0.11, blue: 0.12)

// MARK: - 아카이브 상세 (마크다운 전체 표시)

struct MRArchiveDetailView: View {
    let archive: RaceArchive
    /// 그 대회의 계획 스냅샷 — 있으면 진행 중 계획과 같은 주차표(`MRWeekTable`)로 보인다. 없으면 저장된 글 그대로.
    var snapshot: RacePlanSnapshot? = nil
    @EnvironmentObject private var engine: MREngineStore
    @Environment(\.dismiss) private var dismiss

    /// 저장된 글의 머리(실제 · 계획 시작 시점 예측 · 대회 직전 예측) — 제목 줄과 주차 절은 뺀다.
    private var headLines: [String] {
        let text = mrArchiveDisplayText(archive.markdown)
        let head = text.components(separatedBy: mrArchiveWeeklySectionHeader).first ?? text
        return head.split(separator: "\n").map(String.init)
            .filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let snap = snapshot, !snap.planWeeks.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(headLines, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .monospacedDigit()
                            }
                        }
                        // 진행 중 계획과 같은 표 — 대회일을 '오늘'로 보고 대회 주까지 끝난 주로 센다
                        MRWeekTable(weeks: [], runs: engine.runs, snapshotWeeks: snap.planWeeks,
                                    currentRaceLabels: ["5K", "10K", "하프", "풀"],
                                    hardRunStarts: engine.hardRunStarts.union(engine.intenseRuns.keys),
                                    pointRunTypes: engine.pointRunTypes,
                                    finishedRaceDate: snap.raceDate)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                } else {
                    Text(mrArchiveDisplayText(archive.markdown))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
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
            let hour = m.typicalHour.map { ", 보통 \($0)시쯤" } ?? ""
            return "주로 \(days)요일\(hour) 달립니다"
        }
    }

    private var evenDayText: String {
        let L = AppLanguage.shared
        if L.isEnglish {
            let hour = m.typicalHour.map { ", typically around \($0):00" } ?? ""
            return "Your runs are evenly spread across the week\(hour)"
        } else {
            let hour = m.typicalHour.map { ". 보통 \($0)시쯤입니다" } ?? ""
            return "특정 요일에 몰리지 않고 고르게 달립니다\(hour)"
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

                // VO2max 당해·작년 — 안정시 심박은 위의 RestingHRTrendCard가 추세로 보여준다(2026-10-02 중복 제거)
                if m.vo2max != nil {
                    HStack(spacing: 16) {
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
    private func metricPair(label: String, current: String, last: String?, unit: String,
                             note: String? = nil) -> some View {
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
            if let note {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.mrInk3)
                    .fixedSize(horizontal: false, vertical: true)
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
