import SwiftUI
import SwiftData

// MARK: - 이번 달 계획 (설계: docs/superpowers/specs/2026-10-07-monthly-volume-goal-design.md)
//
// 월 목표를 받아 본인 기록으로 검토한 주차 계획을 보여 준다. 대회 계획과 별도 카드.
// 주차표는 대회 계획과 같은 컴포넌트(`MRWeekTable`) — 수행 기호·실제(노랑)·러닝 목록·글자 색이 같다.
// ⚠ 아침 제안·대회 스냅샷과 연결하지 않는다. 진행률·남은 km·달성률은 넣지 않는다.

private let mpCard = Color(red: 0.11, green: 0.11, blue: 0.12)

struct MRMonthlyPlanCard: View {
    @EnvironmentObject private var engine: MREngineStore
    /// 대회가 있어도 보여 준다 — 디버그 화면 확인용
    var force = false
    /// 러닝 종류(템포런·롱런…) 읽기용 — 월간 훈련일지 막대 색. nil이면 강도 훈련 유형만.
    var manager: HealthKitManager? = nil
    /// 주차표 러닝 줄 → 러닝 상세. nil이면 줄은 누를 수 없다.
    var onTapRun: ((MRWorkout) -> Void)? = nil
    @State private var shareJourney: MRRaceJourney?
    /// 0 = 목표 없음. 다음 달로 그대로 이어진다(매달 다시 검토만).
    @AppStorage("mimo.monthlyGoalKm") private var goalKm: Double = 0
    @State private var editing = false
    @State private var draft = ""
    @State private var frozen: [MRMonthlyFrozenWeek] = MRMonthlyPlanStore.load()
    /// 대회 계획 스냅샷 — 계획 기간(첫 주 ~ 대회일)과 겹치는 달은 월간 계획을 쉰다(2026-10-07 사용자 결정)
    @Query private var raceSnapshots: [RacePlanSnapshot]
    /// 화살표로 고른 달(1일). nil = 볼 수 있는 가장 최근 달
    @State private var selectedMonth: Date? = nil

    // MARK: - 달 넘기기

    /// 월간 계획을 쓰기 시작한 달 — 그 전 달은 지금 목표로 다시 계산한 값이라 보여 주지 않는다
    static let firstMonth = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1))!

    private func monthRange(_ start: Date) -> (start: Date, end: Date) {
        (start, Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start)
    }

    private var currentMonthStart: Date {
        Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    }

    /// 대회 계획 기간(첫 계획 주 월요일 ~ 대회일)과 겹치는가. 계획 없는 등록 대회는 대회일만.
    private func overlapsRace(_ start: Date) -> Bool {
        if force { return false }   // 디버그 확인용 카드 — 대회 달도 보여 준다
        let cal = Calendar.current
        let r = monthRange(start)
        let byPlan = raceSnapshots.contains { snap in
            guard let first = snap.planWeeks.map(\.monday).min(),
                  let planEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: snap.raceDate)) else { return false }
            return cal.startOfDay(for: first) < r.end && planEnd > r.start
        }
        return byPlan || engine.userInput.races.contains { $0.date >= r.start && $0.date < r.end }
    }

    /// 지난 달 — 고정된 주차(이번 달과 겹치는 주) 1부터 번호
    private func frozenWeeks(_ start: Date) -> [MRMonthlyFrozenWeek] {
        let cal = Calendar.current
        let r = monthRange(start)
        return frozen.filter { f in
            let mon = cal.startOfDay(for: f.monday)
            let end = cal.date(byAdding: .day, value: 7, to: mon) ?? mon
            return mon < r.end && end > r.start
        }.sorted { $0.monday < $1.monday }
    }

    /// 넘겨 볼 수 있는 달 — 10월부터, 대회 계획과 겹치지 않고, 이번 달이거나 고정된 주차가 있는 달
    private var months: [Date] {
        let cal = Calendar.current
        var out: [Date] = []
        var m = max(Self.firstMonth, MRMonthlyPlanStore.firstKeptMonth())   // 12개월까지만
        while m <= currentMonthStart {
            if !overlapsRace(m) && (m == currentMonthStart || !frozenWeeks(m).isEmpty) { out.append(m) }
            m = cal.date(byAdding: .month, value: 1, to: m) ?? currentMonthStart.addingTimeInterval(1)
        }
        return out
    }

    private var goal: Double? { goalKm > 0 ? goalKm : nil }

    /// 강도 훈련 입력 — `before` 이전 기록만 본다(지난 주 계획을 그 주 월요일 기준으로 다시 낼 때).
    private func pointInput(before: Date) -> MRMonthlyPlanner.PointInput {
        let pointTypes = engine.pointRunTypes.filter { MRPlanPoint.pointWorkoutTypes.contains($0.value) }
        let lastPoint = (Array(pointTypes.keys) + Array(engine.intenseRuns.keys)).filter { $0 < before }.max()
        return MRMonthlyPlanner.PointInput(
            habitEveryWeeks: engine.monthlyPlanPointHabit,
            paces: mrPointPaces(halfEquivMin: engine.halfEquivMin,
                                thresholdPace: engine.thresholdTrend?.current.paceSecPerKm),
            intervalHistory: engine.recentIntervals.last,
            lastPointStart: lastPoint,
            lastPointType: lastPoint.flatMap { engine.pointRunTypes[$0] })
    }

    private func buildPlan() -> MRMonthlyPlan? {
        MRMonthlyPlanner.build(goalKm: goal, runs: engine.runs, asOf: Date(), point: pointInput(before: Date()))
    }

    /// 지난 주 계획이 고정돼 있지 않으면 — 그 주 월요일(이번 달 1일이 더 늦으면 1일) 기준으로 다시 낸다. 그 전 기록만 쓴다.
    private func backfill(_ monday: Date, monthStart: Date) -> MRMonthlyWeek? {
        let asOf = max(monday, monthStart)
        let before = engine.runs.filter { $0.start < asOf }
        let p = MRMonthlyPlanner.build(goalKm: goal, runs: before, asOf: asOf, point: pointInput(before: asOf))
        return p?.weeks.first { Calendar.current.isDate($0.monday, inSameDayAs: monday) }
    }

    /// 주차표 줄 — 지난 주는 고정값(없으면 다시 낸 값), 이번 주는 같은 목표로 고정한 값(없으면 라이브), 다음 주부터 라이브.
    private func tableWeeks(_ plan: MRMonthlyPlan) -> [MRPlanWeekSummary] {
        let cal = Calendar.current
        let thisMonday = MRPlanGovernance.weekMonday(of: Date())
        return plan.weeks.enumerated().compactMap { i, w in
            let stored = frozen.first { cal.isDate($0.monday, inSameDayAs: w.monday) }
            if w.monday < thisMonday {
                if let s = stored { return withIdx(s.summary, i + 1) }
                return backfill(w.monday, monthStart: plan.monthStart)?.summary(idx: i + 1)
            }
            if w.monday == thisMonday, let s = stored, s.goalKm == goalKm { return withIdx(s.summary, i + 1) }
            return w.summary(idx: i + 1)
        }
    }

    private func monthJourney(_ p: MRMonthlyPlan) -> MRRaceJourney? {
        let weeks = tableWeeks(p)
        guard let end = Calendar.current.date(byAdding: .month, value: 1, to: p.monthStart) else { return nil }
        let from = weeks.first?.monday ?? p.monthStart
        let L = AppLanguage.shared
        return MRRaceJourney.makeMonth(
            title: L.s("\(monthName(p.monthStart)) 훈련일지", "\(monthName(p.monthStart)) training log",
                       ja: "\(monthName(p.monthStart))の練習日誌"),
            monthStart: p.monthStart, monthEnd: end, goalKm: p.goalKm, planTotalKm: p.projectedMonthKm,
            planWeeks: weeks, bars: monthBars(p.monthStart, end), runs: engine.runs,
            types: MRRaceJourney.runTypes(manager: manager, runs: engine.runs, from: from,
                                          to: Date().addingTimeInterval(86_400), fallback: engine.pointRunTypes),
            hardStarts: engine.hardRunStarts.union(engine.intenseRuns.keys), pointTypes: engine.pointRunTypes)
    }

    /// 러닝 흐름 월 차트 재료 — 성장 탭 refreshRecordBars와 같은 집계(러닝·강도 입력, 일 단위). manager 없으면 빈 배열.
    private func monthBars(_ start: Date, _ end: Date) -> [RecordBar] {
        guard let m = manager else { return [] }
        return RecordSeries.bars(activities: m.activities.filter { $0.type == .running },
                                 effortOf: { m.effortIndex.resolve($0)?.value },
                                 start: start, end: end, period: .day)
    }

    private func withIdx(_ s: MRPlanWeekSummary, _ idx: Int) -> MRPlanWeekSummary {
        MRPlanWeekSummary(idx: idx, monday: s.monday, phase: s.phase, longRunKm: s.longRunKm,
                          weeklyKm: s.weeklyKm, breakdown: s.breakdown, point: s.point)
    }

    /// 이번 주·지난 주를 고정 — 지난 주는 한 번 고정하면 그대로, 이번 주는 목표가 바뀌면 다시.
    private func freeze() {
        guard case .ready = engine.state, !overlapsRace(currentMonthStart), let plan = buildPlan() else { return }
        let cal = Calendar.current
        let thisMonday = MRPlanGovernance.weekMonday(of: Date())
        var store = frozen
        var changed = false
        for s in tableWeeks(plan) where s.monday <= thisMonday {
            let idx = store.firstIndex { cal.isDate($0.monday, inSameDayAs: s.monday) }
            let entry = MRMonthlyFrozenWeek(monday: s.monday, goalKm: goalKm, summary: s)
            if let i = idx {
                if s.monday == thisMonday && store[i].goalKm != goalKm { store[i] = entry; changed = true }
            } else {
                store.append(entry); changed = true
            }
        }
        if changed {
            MRMonthlyPlanStore.save(store)
            frozen = store
        }
    }

    var body: some View {
        // 대회가 있으면 대회 계획만 — 월간 계획은 대회가 없을 때(2026-10-07 사용자 결정)
        if case .ready = engine.state, force || engine.userInput.upcomingRaces(asOf: Date()).isEmpty {
            monthBody
                .onAppear { freeze() }
                .onChange(of: goalKm) { freeze() }
                .onChange(of: engine.runs.count) { freeze() }
                .sheet(item: $shareJourney) { j in MRRaceJourneyShareScreen(journey: j) }
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
    private var monthBody: some View {
        let list = months
        let shown = selectedMonth.flatMap { m in list.contains(m) ? m : nil } ?? list.last
        if let m = shown {
            if m == currentMonthStart {
                content(buildPlan(), list: list, month: m)
            } else {
                pastContent(m, list: list)
            }
        } else {
            // 이번 달이 대회 계획과 겹치고 넘겨 볼 달도 없을 때
            cardShell {
                Text(monthTitle(currentMonthStart))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(AppLanguage.shared.s("대회가 있는 달은 월간 계획을 쉽니다. 다음 달 1일부터 다시 시작합니다.",
                                          "Monthly plans pause in race months and restart on the 1st of next month.",
                                          ja: "レースがある月は月間計画を休みます。来月1日から再開します。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }

    private func cardShell<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { c() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(mpCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// ‹ 10월 계획 › — 참가 대회 기록의 연도 넘기기와 같은 방식
    private func monthNav(_ month: Date, list: [Date]) -> some View {
        let i = list.firstIndex(of: month) ?? 0
        return HStack(spacing: 6) {
            Button { selectedMonth = list[max(i - 1, 0)] } label: {
                Image(systemName: "chevron.left").frame(width: 24, height: 24)
            }
            .disabled(i == 0)
            .opacity(i == 0 ? 0.25 : 1)
            .accessibilityLabel(AppLanguage.shared.s("이전 달", "Previous month", ja: "前の月"))
            Text(monthTitle(month))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Button { selectedMonth = list[min(i + 1, list.count - 1)] } label: {
                Image(systemName: "chevron.right").frame(width: 24, height: 24)
            }
            .disabled(i >= list.count - 1)
            .opacity(i >= list.count - 1 ? 0.25 : 1)
            .accessibilityLabel(AppLanguage.shared.s("다음 달", "Next month", ja: "次の月"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.violetText)
    }

    /// 지난 달 — 고정된 주차로 주차표·계획 합계·훈련일지만. 목표는 그달에 고정된 값(바꿀 수 없음).
    @ViewBuilder
    private func pastContent(_ month: Date, list: [Date]) -> some View {
        let L = AppLanguage.shared
        let cal = Calendar.current
        let r = monthRange(month)
        let fw = frozenWeeks(month)
        let weeks = fw.enumerated().map { withIdx($0.element.summary, $0.offset + 1) }
        let goalPast = fw.last { $0.goalKm > 0 }?.goalKm
        let planTotal = weeks.reduce(0.0) { acc, w in
            let days = (0..<7).filter { i in
                guard let d = cal.date(byAdding: .day, value: i, to: w.monday) else { return false }
                return d >= r.start && d < r.end
            }.count
            return acc + w.weeklyKm * Double(days) / 7
        }
        cardShell {
            HStack(alignment: .center) {
                monthNav(month, list: list)
                Spacer(minLength: 8)
                if let g = goalPast {
                    Text(L.s("목표 \(Int(g))km", "Goal \(Int(g))km", ja: "目標 \(Int(g))km"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            Text(L.s("계획 합계 \(km(planTotal))", "Planned total \(km(planTotal))", ja: "計画の合計 \(km(planTotal))"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
            MRWeekTable(weeks: [], runs: engine.runs, snapshotWeeks: weeks,
                        hardRunStarts: engine.hardRunStarts, pointRunTypes: engine.pointRunTypes,
                        onTapRun: onTapRun, showsProjection: false)
                .id(month)
                .padding(.top, 4)
            if goalPast != nil {
                exportButton {
                    shareJourney = MRRaceJourney.makeMonth(
                        title: L.s("\(monthName(month)) 훈련일지", "\(monthName(month)) training log",
                                   ja: "\(monthName(month))の練習日誌"),
                        monthStart: r.start, monthEnd: r.end, goalKm: goalPast, planTotalKm: planTotal,
                        planWeeks: weeks, bars: monthBars(r.start, r.end), now: r.end.addingTimeInterval(-1), runs: engine.runs,
                        types: MRRaceJourney.runTypes(manager: manager, runs: engine.runs,
                                                      from: weeks.first?.monday ?? r.start, to: r.end.addingTimeInterval(7 * 86_400),
                                                      fallback: engine.pointRunTypes),
                        hardStarts: engine.hardRunStarts.union(engine.intenseRuns.keys), pointTypes: engine.pointRunTypes)
                }
            }
        }
    }

    private func exportButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(AppLanguage.shared.s("훈련일지 내보내기", "Export training log", ja: "練習日誌を書き出す"),
                  systemImage: "square.and.arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.violet)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func content(_ plan: MRMonthlyPlan?, list: [Date], month: Date) -> some View {
        let L = AppLanguage.shared
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                monthNav(month, list: list)
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
                    .foregroundStyle(.white.opacity(0.72))

                if p.goalKm == nil {
                    Text(L.s("무리 없는 범위: 유지 \(km(p.maintainMonthKm)) ~ 최대 \(km(p.maxMonthKm))",
                             "Comfortable range: hold \(km(p.maintainMonthKm)) – max \(km(p.maxMonthKm))",
                             ja: "無理のない範囲: 維持 \(km(p.maintainMonthKm)) ~ 最大 \(km(p.maxMonthKm))"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                } else {
                    Text(L.s("계획 합계 \(km(p.projectedMonthKm))", "Planned total \(km(p.projectedMonthKm))",
                             ja: "計画の合計 \(km(p.projectedMonthKm))"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }

                ForEach(Array(limitLines(p).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.violetText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 대회 계획과 같은 주차표 — 수행 기호·실제 노랑·행 탭 → 러닝 목록 → 러닝 상세
                MRWeekTable(weeks: [], runs: engine.runs, snapshotWeeks: tableWeeks(p),
                            hardRunStarts: engine.hardRunStarts, pointRunTypes: engine.pointRunTypes,
                            onTapRun: onTapRun, showsProjection: false)
                    .padding(.top, 4)

                // 월 목표가 있을 때 — 대회 준비 카드와 같은 방식의 월간 훈련일지(2026-10-07 사용자 요청)
                if p.goalKm != nil {
                    exportButton { shareJourney = monthJourney(p) }
                }

                Text(L.s("아침 제안에는 반영되지 않습니다.",
                         "Not used in morning suggestions.",
                         ja: "朝の提案には反映されません。"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                Text(L.s("최근 12주 중 6주 이상 기록이 쌓이면 계획을 냅니다.",
                         "A plan appears once 6 of the last 12 weeks have runs.",
                         ja: "直近12週のうち6週以上の記録がたまると計画を出します。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mpCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
