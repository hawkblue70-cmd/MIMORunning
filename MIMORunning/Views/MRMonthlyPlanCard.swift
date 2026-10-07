import SwiftUI

// MARK: - 이번 달 계획 (설계: docs/superpowers/specs/2026-10-07-monthly-volume-goal-design.md)
//
// 월 목표를 받아 본인 기록으로 검토한 주차 계획을 보여 준다. 대회 계획과 별도 카드.
// ⚠ 확인 단계 — 아침 제안·스냅샷과 연결하지 않는다. 진행률·남은 km·달성률은 넣지 않는다.

private let mpCard = Color(red: 0.11, green: 0.11, blue: 0.12)

struct MRMonthlyPlanCard: View {
    @EnvironmentObject private var engine: MREngineStore
    /// 대회가 있어도 보여 준다 — 디버그 화면 확인용
    var force = false
    /// 0 = 목표 없음. 다음 달로 그대로 이어진다(매달 다시 검토만).
    @AppStorage("mimo.monthlyGoalKm") private var goalKm: Double = 0
    @State private var editing = false
    @State private var draft = ""

    private var plan: MRMonthlyPlan? {
        let pointTypes = engine.pointRunTypes.filter { MRPlanPoint.pointWorkoutTypes.contains($0.value) }
        let lastPoint = (Array(pointTypes.keys) + Array(engine.intenseRuns.keys)).filter { $0 < Date() }.max()
        let input = MRMonthlyPlanner.PointInput(
            habitEveryWeeks: engine.monthlyPlanPointHabit,
            paces: mrPointPaces(halfEquivMin: engine.halfEquivMin,
                                thresholdPace: engine.thresholdTrend?.current.paceSecPerKm),
            intervalHistory: engine.recentIntervals.last,
            lastPointStart: lastPoint,
            lastPointType: lastPoint.flatMap { engine.pointRunTypes[$0] })
        return MRMonthlyPlanner.build(goalKm: goalKm > 0 ? goalKm : nil, runs: engine.runs,
                                      asOf: Date(), point: input)
    }

    var body: some View {
        // 대회가 있으면 대회 계획만 — 월간 계획은 대회가 없을 때(2026-10-07 사용자 결정)
        if case .ready = engine.state, force || engine.userInput.upcomingRaces(asOf: Date()).isEmpty {
            content(plan)
                .alert(AppLanguage.shared.s("이번 달 목표 거리", "Monthly distance goal", ja: "今月の目標距離"),
                       isPresented: $editing) {
                    TextField("km", text: $draft).keyboardType(.numberPad)
                    Button(AppLanguage.shared.s("저장", "Save", ja: "保存")) {
                        if let v = Double(draft.trimmingCharacters(in: .whitespaces)), v > 0 { goalKm = v }
                    }
                    if goalKm > 0 {
                        Button(AppLanguage.shared.s("목표 해제", "Clear goal", ja: "目標を解除"), role: .destructive) { goalKm = 0 }
                    }
                    Button(AppLanguage.shared.s("취소", "Cancel", ja: "キャンセル"), role: .cancel) {}
                } message: {
                    Text(AppLanguage.shared.s("최근 기록으로 검토해 주 단위 계획으로 나눕니다.",
                                              "Checked against your recent runs and split into weeks.",
                                              ja: "最近の記録で確認し、週ごとの計画に分けます。"))
                }
        }
    }

    // MARK: - 본문

    @ViewBuilder
    private func content(_ plan: MRMonthlyPlan?) -> some View {
        let L = AppLanguage.shared
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(monthTitle(plan?.monthStart ?? Date()))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Button {
                    draft = goalKm > 0 ? String(Int(goalKm)) : ""
                    editing = true
                } label: {
                    Text(goalKm > 0 ? L.s("목표 \(Int(goalKm))km", "Goal \(Int(goalKm))km", ja: "目標 \(Int(goalKm))km")
                                    : L.s("목표 정하기", "Set goal", ja: "目標を設定"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.violetText)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.violet.opacity(0.18))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if let p = plan {
                Text(basisLine(p))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.60))

                if p.goalKm == nil {
                    Text(L.s("무리 없는 범위: 유지 \(km(p.maintainMonthKm)) ~ 최대 \(km(p.maxMonthKm))",
                             "Comfortable range: hold \(km(p.maintainMonthKm)) – max \(km(p.maxMonthKm))",
                             ja: "無理のない範囲: 維持 \(km(p.maintainMonthKm)) ~ 最大 \(km(p.maxMonthKm))"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.90))
                } else {
                    Text(L.s("계획 합계 \(km(p.projectedMonthKm))", "Planned total \(km(p.projectedMonthKm))",
                             ja: "計画の合計 \(km(p.projectedMonthKm))"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.90))
                }

                ForEach(Array(limitLines(p).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.violetText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    ForEach(Array(p.weeks.enumerated()), id: \.offset) { i, w in
                        if i > 0 { Divider().overlay(Color.white.opacity(0.06)) }
                        weekRow(w, usualRuns: p.usualRuns)
                    }
                }
                .padding(.top, 2)

                Text(L.s("확인용 — 아침 제안에는 반영되지 않습니다.",
                         "Preview only — not used in morning suggestions.",
                         ja: "確認用 — 朝の提案には反映されません。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.40))
            } else {
                Text(L.s("최근 12주 중 6주 이상 기록이 쌓이면 계획을 냅니다.",
                         "A plan appears once 6 of the last 12 weeks have runs.",
                         ja: "直近12週のうち6週以上の記録がたまると計画を出します。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mpCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func weekRow(_ w: MRMonthlyWeek, usualRuns: Int) -> some View {
        let L = AppLanguage.shared
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.s("\(md(w.monday)) 주", "Week of \(md(w.monday))", ja: "\(md(w.monday))週"))
                    .font(.system(size: 12, weight: w.isCurrent ? .bold : .regular))
                    .foregroundStyle(w.isCurrent ? Theme.violetText : .white.opacity(0.60))
                Spacer()
                if let p = w.plannedKm {
                    if w.isCurrent && w.actualKm > 0 {
                        Text(L.s("지금 \(km(w.actualKm)) · ", "so far \(km(w.actualKm)) · ", ja: "現在 \(km(w.actualKm)) · "))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Text(km(p))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Text(L.s("실제 \(km(w.actualKm))", "Actual \(km(w.actualKm))", ja: "実績 \(km(w.actualKm))"))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            if w.plannedKm != nil {
                Text(w.breakdown)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.80))
                if let pt = w.point {
                    Text(L.s("강도 훈련 · ", "Hard session · ", ja: "強度練習 · ") + pt.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.80))
                }
                if w.addedRun {
                    Text(L.s("주 \(w.runs)회(평소 \(usualRuns)회) — 이지 1회가 평소보다 길어지지 않게 한 번 더",
                             "\(w.runs) runs (usually \(usualRuns)) — one more so easy runs stay usual length",
                             ja: "週\(w.runs)回(普段\(usualRuns)回) — イージー1回が普段より長くならないよう1回追加"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.violetText)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - 문구

    private func basisLine(_ p: MRMonthlyPlan) -> String {
        let L = AppLanguage.shared
        return L.s("최근 4주 주 \(km(p.baseWeeklyKm)) · 12개월 최대 주 \(km(p.maxWeeklyKm52w)) · 주 \(p.usualRuns)회",
                   "Last 4 wks \(km(p.baseWeeklyKm))/wk · 12-mo max \(km(p.maxWeeklyKm52w))/wk · \(p.usualRuns) runs/wk",
                   ja: "直近4週 週\(km(p.baseWeeklyKm)) · 12か月最大 週\(km(p.maxWeeklyKm52w)) · 週\(p.usualRuns)回")
    }

    private func limitLines(_ p: MRMonthlyPlan) -> [String] {
        let L = AppLanguage.shared
        var out: [String] = []
        for l in p.limits {
            switch l {
            case .growth:
                out.append(L.s("주간 거리를 한 주에 10~15%씩 늘리면 이번 달은 \(km(p.projectedMonthKm))까지입니다.",
                               "Growing 10–15% a week, this month reaches \(km(p.projectedMonthKm)).",
                               ja: "週の距離を1週に10~15%ずつ増やすと、今月は\(km(p.projectedMonthKm))までです。"))
            case .experience(let cap):
                out.append(L.s("12개월 최대 주 \(km(p.maxWeeklyKm52w))를 넘는 목표라 이번 달은 주 \(km(cap))까지입니다.",
                               "The goal exceeds your 12-month max of \(km(p.maxWeeklyKm52w))/wk, so this month caps at \(km(cap))/wk.",
                               ja: "12か月最大の週\(km(p.maxWeeklyKm52w))を超える目標のため、今月は週\(km(cap))までです。"))
            case .frequency(let n, let maxKm, let plusOne):
                if let p1 = plusOne {
                    out.append(L.s("주 \(n)회로는 주 \(km(maxKm))까지입니다. 한 번 더 뛰면 주 \(km(p1))입니다.",
                                   "At \(n) runs a week the max is \(km(maxKm))/wk. One more run allows \(km(p1))/wk.",
                                   ja: "週\(n)回では週\(km(maxKm))までです。もう1回走ると週\(km(p1))です。"))
                } else {
                    out.append(L.s("주 \(n)회로는 주 \(km(maxKm))까지입니다.", "At \(n) runs a week the max is \(km(maxKm))/wk.",
                                   ja: "週\(n)回では週\(km(maxKm))までです。"))
                }
            }
        }
        if let next = p.nextMonthKm,
           let nm = Calendar.current.date(byAdding: .month, value: 1, to: p.monthStart) {
            let name = monthName(nm)
            out.append(L.s("이 흐름이면 \(name) \(km(next))입니다.", "At this pace, \(name) reaches \(km(next)).",
                           ja: "この流れなら\(name)は\(km(next))です。"))
        }
        return out
    }

    private func km(_ x: Double) -> String {
        x >= 100 ? "\(Int(x.rounded()))km" : "\(mrPointKmString((x * 10).rounded() / 10))km"
    }

    private func md(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: d)
    }

    private func monthName(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.shared.locale
        f.setLocalizedDateFormatFromTemplate("MMMM")
        return f.string(from: d)
    }

    private func monthTitle(_ d: Date) -> String {
        let name = monthName(d)
        return AppLanguage.shared.s("\(name) 계획", "\(name) plan", ja: "\(name)の計画")
    }
}
