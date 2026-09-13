import SwiftUI
import SwiftData
import PhotosUI
import StoreKit
#if canImport(ImagePlayground)
import ImagePlayground
#endif

// MARK: - File-private types

private struct BadgeInfo: Identifiable {
    let id: String
    let icon: String
    let title: String
    let achieved: Bool
    let achievedDate: Date?
}

private struct SelectedSummaryStats: Identifiable {
    let id = UUID()
    let stats: SummaryPeriodStats
}

// MARK: - MeView

struct MeView: View {
    var manager: HealthKitManager

    @EnvironmentObject private var engine: MREngineStore
    @Environment(CustomMiniMeStore.self) private var miniMeStore
    @Environment(RaceDetector.self) private var raceDetector
    @Environment(CrewNicknameManager.self) private var crewNicknameManager
    @Query(sort: \MyPlannedRace.dateString) private var plannedRaces: [MyPlannedRace]
    @Query private var shoes: [Shoe]
    @Query private var allStories: [WorkoutStory]
    @Query private var allSnapshots: [RacePlanSnapshot]
    @Query private var allArchives: [RaceArchive]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSummaryStats: SelectedSummaryStats? = nil
    @State private var showRaceSearch = false
    @State private var showAddShoe = false
    @State private var shoeToDelete: Shoe?
    @State private var shoeKmCache: [UUID: Double] = [:]
    @State private var cachedMonthStats: [SummaryPeriodStats] = []
    @State private var cachedYearStats: [SummaryPeriodStats] = []
    @State private var badgesCache: [BadgeInfo] = []
    @State private var lastStatsCacheKey: String = ""
    @State private var cachedMonthFormMetrics: [String: FormMetricsData] = [:]
    @AppStorage("distanceUnitMiles") private var useMiles = false
    @AppStorage("garminNoticeDismissed") private var garminNoticeDismissed = false
    @AppStorage("showRunning")  private var showRunning  = true
    @AppStorage("showWalking")  private var showWalking  = false
    @AppStorage("cloudKitSyncAvailable") private var cloudKitSyncAvailable = false
    @Query private var goalRecords: [UserGoalRecord]
    @State private var editingGoal: RaceGoalKind? = nil
    @State private var nicknameInput: String = ""
    @State private var nicknameSavedFlash = false
    @FocusState private var nicknameFieldFocused: Bool
    private let pro = ProManager.shared
#if DEBUG
    @State private var showDebug = false
    #endif

    /// 회복·테이퍼 주에 평균 강도가 평소보다 높을 때 플래너에 보이는 한 줄. 단계 판정은 MRWeekTable이 한다.
    private var recoveryEffortNote: String? {
        let idx = manager.effortIndex
        let runs = manager.activities.filter { $0.type == .running }
        let monday = EffortLoad.mondayStart(of: Date())
        let loadRuns = EffortLoad.runs(from: manager.activities, index: idx)
        guard let cur = EffortLoad.weekly(runs: loadRuns, weekStart: monday) else { return nil }
        // 서머타임 경계에서도 정확히 8주 전이 되도록 캘린더로 계산한다.
        let eightWeeksAgo = Calendar.current.date(byAdding: .day, value: -56, to: monday) ?? monday
        let past = runs.filter { $0.date >= eightWeeksAgo && $0.date < monday }.compactMap { idx.resolve($0.id)?.value }
        guard EffortLoad.recoveryWeekExceeds(meanEffort: cur.meanEffort, coverage: cur.coverage, eightWeekEfforts: past) else { return nil }
        return AppLanguage.shared.s("회복 주인데 평균 강도가 평소보다 높아요.", "Recovery week, but your average effort is above usual.")
    }

    // MARK: - Period stats

    private var runWalkActivities: [Activity] {
        manager.activities.filter { $0.type == .running || $0.type == .walking }
    }

    private func periodStats(monthOffset: Int) -> SummaryPeriodStats {
        let cal = Calendar.current
        let ref = cal.date(byAdding: .month, value: -monthOffset, to: Date()) ?? Date()
        let year  = cal.component(.year,  from: ref)
        let month = cal.component(.month, from: ref)
        let acts = runWalkActivities.filter {
            cal.component(.year,  from: $0.date) == year &&
            cal.component(.month, from: $0.date) == month
        }

        let prevRef = cal.date(byAdding: .month, value: -(monthOffset + 1), to: Date()) ?? Date()
        let prevYear  = cal.component(.year,  from: prevRef)
        let prevMonth = cal.component(.month, from: prevRef)
        let prevActs = runWalkActivities.filter {
            cal.component(.year,  from: $0.date) == prevYear &&
            cal.component(.month, from: $0.date) == prevMonth
        }
        let prevRuns = prevActs.filter { $0.type == .running }
        let prevDistKm = prevActs.reduce(0.0) { $0 + $1.distance / 1000 }
        let prevPaceSec: Double? = {
            let r = prevRuns.filter { $0.distance > 0 }
            guard !r.isEmpty else { return nil }
            let d = r.reduce(0.0) { $0 + $1.distance }
            let t = r.reduce(0.0) { $0 + $1.duration }
            return d > 0 ? t / (d / 1000) : nil
        }()

        var ytdKm: Double? = nil
        if monthOffset == 0 {
            let currYear = cal.component(.year, from: Date())
            let km = runWalkActivities.filter {
                cal.component(.year, from: $0.date) == currYear
            }.reduce(0.0) { $0 + $1.distance / 1000 }
            ytdKm = km > 0 ? km : nil
        }

        return SummaryPeriodStats(
            kind: .monthly(year: year, month: month),
            activities: acts,
            useMiles: useMiles,
            compDistanceKm: prevDistKm > 0 ? prevDistKm : nil,
            compRunCount: prevRuns.isEmpty ? nil : prevRuns.count,
            compAvgPaceSecPerKm: prevPaceSec,
            ytdDistanceKm: ytdKm
        )
    }

    private func yearStats(yearOffset: Int) -> SummaryPeriodStats {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date()) - yearOffset
        let acts = runWalkActivities.filter {
            cal.component(.year, from: $0.date) == year
        }

        let prevYear = year - 1
        let prevActs = runWalkActivities.filter {
            cal.component(.year, from: $0.date) == prevYear
        }
        let prevRuns = prevActs.filter { $0.type == .running }
        let prevDistKm = prevActs.reduce(0.0) { $0 + $1.distance / 1000 }
        let prevPaceSec: Double? = {
            let r = prevRuns.filter { $0.distance > 0 }
            guard !r.isEmpty else { return nil }
            let d = r.reduce(0.0) { $0 + $1.distance }
            let t = r.reduce(0.0) { $0 + $1.duration }
            return d > 0 ? t / (d / 1000) : nil
        }()

        return SummaryPeriodStats(
            kind: .yearly(year: year),
            activities: acts,
            useMiles: useMiles,
            compDistanceKm: prevDistKm > 0 ? prevDistKm : nil,
            compRunCount: prevRuns.isEmpty ? nil : prevRuns.count,
            compAvgPaceSecPerKm: prevPaceSec
        )
    }

    // MARK: - Cache refresh

    private func deletePastRaces() {
        let today = Calendar.current.startOfDay(for: Date())
        plannedRaces.filter { ($0.raceDate ?? .distantFuture) < today }.forEach { modelContext.delete($0) }
    }

    private func refreshStatsAndBadges() {
        let key = "\(manager.activities.count)-\(useMiles)"
        guard key != lastStatsCacheKey else { return }
        lastStatsCacheKey = key
        cachedMonthStats = [periodStats(monthOffset: 0), periodStats(monthOffset: 1), periodStats(monthOffset: 2)]
        cachedYearStats  = [yearStats(yearOffset: 0), yearStats(yearOffset: 1)]
        badgesCache      = computeBadges()
        cachedMonthFormMetrics = [:]  // 데이터 변경 시 폼 지표도 무효화
    }

    // 3지표를 디스크 캐시에서 1회만 읽어 월별 폼 지표 사전 계산
    private func refreshFormMetrics() async {
        guard !cachedMonthStats.isEmpty else { return }
        guard cachedMonthFormMetrics.isEmpty else { return }  // 이미 계산됐으면 즉시 리턴
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        async let cadFetch = manager.fetchMetricHistory(.cadence,      from: yearAgo)
        async let pwrFetch = manager.fetchMetricHistory(.power,        from: yearAgo)
        async let strFetch = manager.fetchMetricHistory(.strideLength, from: yearAgo)
        let (cad, pwr, str) = await (cadFetch, pwrFetch, strFetch)

        var result: [String: FormMetricsData] = [:]
        let cal = Calendar.current

        func avg(_ pts: [(date: Date, value: Double)], from s: Date, to e: Date) -> Double? {
            let f = pts.filter { $0.date >= s && $0.date < e }
            guard !f.isEmpty else { return nil }
            return f.map(\.value).reduce(0, +) / Double(f.count)
        }

        for stats in cachedMonthStats {
            guard case .monthly(let y, let m) = stats.kind else { continue }
            let start = cal.date(from: DateComponents(year: y, month: m)) ?? Date()
            let end   = cal.date(byAdding: .month, value: 1,  to: start) ?? Date()
            let prev  = cal.date(byAdding: .month, value: -1, to: start) ?? Date()
            result[stats.kind.title] = FormMetricsData(
                cadence:          avg(cad, from: start, to: end),
                prevCadence:      avg(cad, from: prev,  to: start),
                power:            avg(pwr, from: start, to: end),
                prevPower:        avg(pwr, from: prev,  to: start),
                strideLength:     avg(str, from: start, to: end),
                prevStrideLength: avg(str, from: prev,  to: start)
            )
        }
        cachedMonthFormMetrics = result
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        profileHeader
                        if manager.hasGarminSource && !garminNoticeDismissed {
                            garminNoticeSection
                        }
                        plannedRacesSection
                        raceGoalsSection
                        MRRacePlanSection(recoveryEffortNote: recoveryEffortNote)
                            .padding(.horizontal, 16)
                        statsSection
                        shoesSection
                        milestonesSection
                        crewNicknameSection
                        settingsSection
                        Spacer(minLength: 32)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle(AppLanguage.shared.s("나", "Me"))
            .navigationBarTitleDisplayMode(.large)
            .onAppear { manager.syncUserEfforts(from: allStories) }
        }
        .task {
            nicknameInput = crewNicknameManager.nickname ?? ""
            migrateGoalsIfNeeded()
            syncAndRecompute()
            await createArchivesIfNeeded()
            mrDeduplicateSnapshots(allSnapshots, context: modelContext)
            mrDeduplicateArchives(allArchives,   context: modelContext)
            refreshShoeKmCache()
            refreshStatsAndBadges()
            await refreshFormMetrics()
            deletePastRaces()
        }
        .onChange(of: manager.activities.count) {
            refreshShoeKmCache()
            refreshStatsAndBadges()
            Task { await refreshFormMetrics() }
        }
        .onChange(of: allStories.count) { refreshShoeKmCache() }
        .onChange(of: useMiles) { refreshStatsAndBadges() }
        .onChange(of: AppLanguage.shared.isEnglish) { _, _ in
            badgesCache = computeBadges()
            engine.recomputePlans()   // verdict·plan notes는 빌드 시 L.s()로 저장 → 재계산 필요
        }
        .onChange(of: racePlanKey) { syncAndRecompute() }
        .onChange(of: goalHash) { syncAndRecompute() }
        .onChange(of: engine.isReady) { if engine.isReady { syncAndRecompute() } }
        .sheet(isPresented: $showRaceSearch) {
            RaceSearchSheet(raceDetector: raceDetector, existing: Set(plannedRaces.map { $0.raceName + $0.dateString }))
        }
        .sheet(item: $editingGoal) { kind in
            GoalTimeEditSheet(kind: kind, current: binding(for: kind))
                .presentationDetents([.height(320)])
        }
    }

    private func binding(for kind: RaceGoalKind) -> Binding<String> {
        Binding(
            get: {
                switch kind {
                case .tenK: return self.goalRecords.first?.tenKGoal  ?? ""
                case .half: return self.goalRecords.first?.halfGoal ?? ""
                case .full: return self.goalRecords.first?.fullGoal ?? ""
                }
            },
            set: { self.setGoal(kind: kind, value: $0) }
        )
    }

    // MARK: - Planned races section

    private var plannedRacesSection: some View {
        let L = AppLanguage.shared
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.s("참가 대회", "My Races"))
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button { showRaceSearch = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.violet)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            if plannedRaces.isEmpty {
                Text(L.s("참가 예정 대회를 등록하세요", "Add races you plan to join"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
            } else {
                ForEach(plannedRaces) { race in
                    PlannedRaceRow(race: race, locked: isRaceLocked(race)) {
                        modelContext.delete(race)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Race Goals

    private var raceGoalsSection: some View {
        let L = AppLanguage.shared
        return VStack(alignment: .leading, spacing: 12) {
            Text(L.s("목표 기록", "Goal Times"))
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            HStack(spacing: 10) {
                ForEach(RaceGoalKind.allCases) { kind in
                    let goalStr = goalString(for: kind)
                    Button { editingGoal = kind } label: {
                        VStack(spacing: 6) {
                            Text(kind.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(goalStr.isEmpty ? L.s("미설정", "Set goal") : goalStr)
                                .font(.system(size: goalStr.isEmpty ? 12 : 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(goalStr.isEmpty ? Color.secondary.opacity(0.5) : Color.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(goalStr.isEmpty ? Color.white.opacity(0.08) : Theme.violet.opacity(0.30), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Engine sync

    private var racePlanKey: String {
        plannedRaces.map { "\($0.dateString)-\(Int($0.selectedDistanceKm * 1000))" }.joined(separator: "|")
    }

    private func isRaceLocked(_ race: MyPlannedRace) -> Bool {
        pro.isTrialExpired && race.addedAt >= pro.effectiveCutoffDate
    }

    private func syncAndRecompute() {
        engine.userInput.races = plannedRaces
            .filter { !isRaceLocked($0) }
            .compactMap { mrTargetRace(from: $0) }
        engine.userInput.goals = parseGoals()
        // 스냅샷이 있는 대회는 최초 저장 시점의 월요일을 고정 앵커로 사용.
        // 이로써 매 월요일마다 주차 구조가 재시작되는 문제를 방지한다.
        let anchors = Dictionary(
            allSnapshots.compactMap { snap -> (String, Date)? in
                guard let firstMonday = snap.planWeeks.first?.monday else { return nil }
                return (mrArchiveKey(raceDate: snap.raceDate, distanceM: snap.distanceM), firstMonday)
            },
            uniquingKeysWith: { a, _ in a }
        )
        engine.recomputePlans(snapshotAnchors: anchors)
        saveSnapshotsIfNeeded()
    }

    // UserDefaults(구버전) → SwiftData 1회 마이그레이션. 이미 레코드 있으면 스킵.
    private func migrateGoalsIfNeeded() {
        guard goalRecords.isEmpty else { return }
        let ud10k  = UserDefaults.standard.string(forKey: "goalTime10k")  ?? ""
        let udHalf = UserDefaults.standard.string(forKey: "goalTimeHalf") ?? ""
        let udFull = UserDefaults.standard.string(forKey: "goalTimeFull") ?? ""
        guard !ud10k.isEmpty || !udHalf.isEmpty || !udFull.isEmpty else { return }
        let rec = UserGoalRecord()
        rec.tenKGoal = ud10k
        rec.halfGoal = udHalf
        rec.fullGoal = udFull
        modelContext.insert(rec)
    }

    // 목표 저장: 레코드가 없으면 신규 생성, 있으면 업데이트
    private func setGoal(kind: RaceGoalKind, value: String) {
        let rec: UserGoalRecord
        if goalRecords.count > 1 {
            goalRecords.dropFirst().forEach { modelContext.delete($0) }
        }
        if let existing = goalRecords.first {
            rec = existing
        } else {
            rec = UserGoalRecord()
            modelContext.insert(rec)
        }
        switch kind {
        case .tenK: rec.tenKGoal = value
        case .half: rec.halfGoal = value
        case .full: rec.fullGoal = value
        }
        syncAndRecompute()
    }

    private func parseGoals() -> MRGoals {
        func sec(_ s: String) -> Int? {
            guard !s.isEmpty else { return nil }
            let p = s.split(separator: ":").compactMap { Int($0) }
            switch p.count {
            case 3: return p[0] * 3600 + p[1] * 60 + p[2]
            case 2: return p[0] * 60 + p[1]
            default: return nil
            }
        }
        let r = goalRecords.first
        return MRGoals(tenKSec: sec(r?.tenKGoal  ?? ""),
                       halfSec: sec(r?.halfGoal ?? ""),
                       fullSec: sec(r?.fullGoal ?? ""))
    }

    private func goalString(for kind: RaceGoalKind) -> String {
        let r = goalRecords.first
        switch kind {
        case .tenK: return r?.tenKGoal  ?? ""
        case .half: return r?.halfGoal ?? ""
        case .full: return r?.fullGoal ?? ""
        }
    }

    private var goalHash: String {
        let r = goalRecords.first
        return "\(r?.tenKGoal ?? "")|\(r?.halfGoal ?? "")|\(r?.fullGoal ?? "")"
    }

    // MARK: - 스냅샷·아카이브

    private func saveSnapshotsIfNeeded() {
        guard case .ready = engine.state else { return }
        let existingByKey = Dictionary(
            allSnapshots.map { (mrArchiveKey(raceDate: $0.raceDate, distanceM: $0.distanceM), $0) },
            uniquingKeysWith: { a, _ in a }
        )
        let cal          = Calendar.current
        let todayStart   = cal.startOfDay(for: Date())
        let daysSinceMon = (cal.component(.weekday, from: todayStart) + 5) % 7
        let thisMonday   = cal.date(byAdding: .day, value: -daysSinceMon, to: todayStart) ?? todayStart

        for check in engine.checks {
            let key  = mrArchiveKey(raceDate: check.race.date, distanceM: check.race.distanceM)
            let data = mrBuildSnapshotData(check: check)

            guard let existing = existingByKey[key] else {
                // 신규 스냅샷 저장
                let snap = RacePlanSnapshot(
                    raceDate: check.race.date,
                    raceName: check.race.name,
                    distanceM: check.race.distanceM,
                    projectedFinalMin: data.projectedFinalMin,
                    projectedNowMin: data.projectedNowMin,
                    goalMin: data.goalMin,
                    weeksJSON: data.weeksJSON,
                    metaJSON: data.metaJSON
                )
                modelContext.insert(snap)
                #if DEBUG
                print("[스냅샷] 저장: \(check.race.name) \(check.race.distanceM / 1000)km → \(mrFormatDisplay(data.projectedFinalMin))")
                #endif
                continue
            }

            // ── Trigger 0: 아직 시작하지 않은 계획 → 스냅샷 전체를 실시간 계획으로 교체 ──
            // "진행 중인 계획은 바꾸지 않는다"는 시작한 계획 얘기다. 시작 전 스냅샷은 앞선 대회 추가·삭제,
            // 튠업, 회복 블록 규칙 변화로 구조(시작일·주 수)가 통째로 바뀔 수 있다.
            // 예: 하프를 나중에 등록하면 풀 계획은 10K 다음 주가 아니라 하프 다음 주부터 시작해야 한다.
            if let firstMon = existing.planWeeks.first?.monday,
               cal.startOfDay(for: firstMon) > thisMonday {
                let liveFirst = check.plan.weeks.first.map { cal.startOfDay(for: $0.monday) }
                let liveStartMon = liveFirst ?? cal.startOfDay(for: firstMon)
                if liveStartMon != cal.startOfDay(for: firstMon)
                    || check.plan.weeks.count != existing.planWeeks.count {
                    existing.weeksJSON         = data.weeksJSON
                    existing.metaJSON          = data.metaJSON
                    existing.projectedFinalMin = data.projectedFinalMin
                    existing.projectedNowMin   = data.projectedNowMin
                    existing.goalMin           = data.goalMin
                    #if DEBUG
                    print("[스냅샷] 시작 전 계획 구조 변경 → 전체 갱신: \(check.race.name) \(existing.planWeeks.count)주")
                    #endif
                    continue
                }
            }

            // ── Trigger 3: 튠업 대회 추가·삭제 → 관련 미래 주만 실시간 계획으로 교체 ──
            // 과거 주는 그대로. 미래 주 중 실시간과 스냅샷의 "대회 주" 여부가 다른 주만 바꾼다.
            // (프로필 변화로 인한 미래 주 흔들림은 여전히 막는다 — 대회 주 관련만 손댄다.)
            do {
                let liveByMonday: [Date: MRPlanWeek] = Dictionary(
                    check.plan.weeks.map { (cal.startOfDay(for: $0.monday), $0) },
                    uniquingKeysWith: { a, _ in a }
                )
                var changed = 0
                let merged: [MRPlanWeekSummary] = existing.planWeeks.map { snap in
                    let snapMon = cal.startOfDay(for: snap.monday)
                    guard let live = liveByMonday[snapMon] else { return snap }
                    let follows = live.breakdown.contains("계획을 따릅니다")
                    // 지난 주는 원칙적으로 고정. 예외: 다른 대회(10K) 계획을 "따르는" 주는 그 계획의 고정된
                    // 과거 값을 그대로 가져오는 것이라 역사를 새로 쓰는 게 아니다 — 이행 기호가 실제 따른 계획 기준이 된다.
                    // 이번 주(진행 중)는 튠업 관련이면 갱신한다.
                    if snapMon < thisMonday && !follows { return snap }
                    let raceRelated = follows || live.phase == "대회 주" || snap.phase == "대회 주"
                        || live.breakdown.contains("대회") || snap.breakdown.contains("대회")
                    guard raceRelated,
                          live.phase != snap.phase || live.breakdown != snap.breakdown
                          || abs(live.longRunKm - snap.longRunKm) > 0.05 else { return snap }
                    changed += 1
                    return MRPlanWeekSummary(idx: snap.idx, monday: snap.monday, phase: live.phase,
                                             longRunKm: live.longRunKm, weeklyKm: live.weeklyKm,
                                             breakdown: live.breakdown)
                }
                if changed > 0 {
                    let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
                    if let wd = try? enc.encode(merged), let wj = String(data: wd, encoding: .utf8) {
                        existing.weeksJSON = wj
                    }
                    #if DEBUG
                    print("[스냅샷] 튠업 변경 → 미래 \(changed)주 갱신: \(check.race.name)")
                    #endif
                }
            }

            // ── Trigger 1: targetLongKm 규칙 변경 → 미래 주 조정 ──────────────
            // 프로필 변화(더 많이 달림)는 targetLongKm에 영향을 주지 않으므로 갱신 안 함.
            let liveTarget = check.plan.targetLongKm
            let snapTarget = existing.storedTargetLongKm ?? 21.0
            if abs(liveTarget - snapTarget) > 0.5 {
                let oldWeeks = existing.planWeeks
                if oldWeeks.isEmpty {
                    existing.weeksJSON = data.weeksJSON
                    existing.metaJSON  = data.metaJSON
                } else {
                    let liveByMonday: [Date: MRPlanWeek] = Dictionary(
                        check.plan.weeks.map { (cal.startOfDay(for: $0.monday), $0) },
                        uniquingKeysWith: { a, _ in a }
                    )
                    let merged: [MRPlanWeekSummary] = oldWeeks.map { snap in
                        let snapMon = cal.startOfDay(for: snap.monday)
                        if snapMon <= thisMonday { return snap }
                        if snap.phase == "회복" { return snap }
                        if snap.phase == "테이퍼" {
                            let newLr = (liveTarget * 0.65 * 10).rounded() / 10
                            let bd    = liveByMonday[snapMon]?.breakdown ?? snap.breakdown
                            return MRPlanWeekSummary(idx: snap.idx, monday: snap.monday,
                                                     phase: "테이퍼", longRunKm: newLr,
                                                     weeklyKm: snap.weeklyKm, breakdown: bd)
                        }
                        if snap.longRunKm > liveTarget {
                            let bd = liveByMonday[snapMon]?.breakdown ?? snap.breakdown
                            return MRPlanWeekSummary(idx: snap.idx, monday: snap.monday,
                                                     phase: "유지", longRunKm: liveTarget,
                                                     weeklyKm: snap.weeklyKm, breakdown: bd)
                        }
                        return snap
                    }
                    let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
                    if let wd = try? enc.encode(merged), let wj = String(data: wd, encoding: .utf8) {
                        existing.weeksJSON = wj
                    }
                    existing.metaJSON = data.metaJSON
                    #if DEBUG
                    print("[스냅샷] 규칙 변경 → 미래 주 갱신: \(check.race.name) targetLongKm \(snapTarget)→\(liveTarget)")
                    #endif
                }
            }

            // ── Trigger 2: 구버전 스냅샷(startingLongKm 없음) → 과거 주 일회성 보정 ──
            // targetLongKm 변화와 독립적으로 실행. 한 번 실행되면 metaJSON에 startingLongKm이
            // 기록되어 다음 실행에서는 이 블록에 진입하지 않는다.
            if existing.storedStartingLongKm == nil {
                let liveStart = check.plan.startingLongKm
                if liveStart > 1.0 {
                    // 등록 시점 이전 16주 구간에서 최장 런 → 계획 수립 당시 fitness 추산
                    let cutoffDate  = cal.startOfDay(for: existing.createdAt)
                    let lookback    = cal.date(byAdding: .day, value: -112, to: cutoffDate) ?? cutoffDate
                    let prevMaxLong = engine.runs
                        .filter { $0.start >= lookback && $0.start < cutoffDate }
                        .compactMap { $0.distanceKm }
                        .max() ?? 0

                    if prevMaxLong > 1.0 {
                        let originalStart = max(prevMaxLong, 5.0)
                        let scaleFactor   = originalStart / liveStart
                        if abs(scaleFactor - 1.0) > 0.03 {
                            let corrected: [MRPlanWeekSummary] = existing.planWeeks.map { snap in
                                let snapMon = cal.startOfDay(for: snap.monday)
                                guard snapMon <= thisMonday else { return snap }
                                guard snap.phase == "늘리기" || snap.phase == "유지" else { return snap }
                                let newLr = (snap.longRunKm * scaleFactor * 10).rounded() / 10
                                return MRPlanWeekSummary(idx: snap.idx, monday: snap.monday,
                                                         phase: snap.phase, longRunKm: newLr,
                                                         weeklyKm: snap.weeklyKm, breakdown: snap.breakdown)
                            }
                            let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
                            if let wd = try? enc.encode(corrected), let wj = String(data: wd, encoding: .utf8) {
                                existing.weeksJSON = wj
                                #if DEBUG
                                print("[스냅샷] 과거 주 보정: \(check.race.name) scale=\(String(format: "%.3f", scaleFactor)) original=\(String(format: "%.2f", originalStart)) live=\(String(format: "%.2f", liveStart))")
                                #endif
                            }
                        }
                    }
                }
                // startingLongKm 기록 — 다음 실행에서 migration 재실행 방지
                existing.metaJSON = data.metaJSON
            }
        }
    }

    private func createArchivesIfNeeded() async {
        guard case .ready = engine.state else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let existingArchiveKeys = Set(allArchives.map {
            mrArchiveKey(raceDate: $0.raceDate, distanceM: $0.distanceM)
        })

        // 지난 대회가 있는 스냅샷만 대상
        let pastSnapshots = allSnapshots.filter {
            Calendar.current.startOfDay(for: $0.raceDate) < today
        }

        for snap in pastSnapshots {
            let key = mrArchiveKey(raceDate: snap.raceDate, distanceM: snap.distanceM)
            guard !existingArchiveKeys.contains(key) else { continue }

            let daysSinceRace = Calendar.current.dateComponents([.day],
                from: Calendar.current.startOfDay(for: snap.raceDate), to: today).day ?? 0

            let run = mrFindRaceDayRun(runs: engine.runs,
                                        raceDate: snap.raceDate,
                                        distanceM: snap.distanceM)
            let hasRun = run != nil

            // 기록 없음 처리: 14일 지나도 기록이 없으면 "기록 없음"으로 저장
            guard hasRun || daysSinceRace >= 14 else { continue }

            let actualMin = run.map { $0.durationMin }

            // 대회 직전 예측: 지금 엔진의 예측 (아카이브 생성 시점 = 대회 직후)
            let label = mrLabelFor(distanceM: snap.distanceM)
            let preRaceMin = engine.predictions.first { $0.label == label }?.midMin

            let md = mrBuildArchiveMarkdown(
                snapshot: snap,
                actualMin: actualMin,
                preRaceProjectedMin: preRaceMin,
                runs: engine.runs
            )

            let archive = RaceArchive(
                raceDate: snap.raceDate,
                raceName: snap.raceName,
                distanceM: snap.distanceM,
                markdown: md,
                hasResult: hasRun,
                actualMin: actualMin ?? 0,
                snapshotProjectedFinalMin: snap.projectedFinalMin
            )
            modelContext.insert(archive)
            #if DEBUG
            print("[아카이브] 저장: \(snap.raceName) · 실제 \(actualMin.map { mrFormatDisplay($0) } ?? "없음")")
            #endif
        }
    }

    // MARK: - Garmin notice

    private var garminNoticeSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.violet)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLanguage.shared.s("가민 기기 감지됨", "Garmin Device Detected"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(AppLanguage.shared.s("심박·러닝폼·VO2max 등 일부 지표는 가민→애플 건강 앱 동기화가 필요해요. 동기화가 안 된 경우 해당 지표가 표시되지 않을 수 있어요.", "Some metrics (HR, running form, VO2max) require Garmin→Apple Health sync. They may not appear if sync is off."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                withAnimation(.easeOut) { garminNoticeDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.violet.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.violet.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Profile header (미니미 자리)

    private var profileHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                if let customImg = miniMeStore.image {
                    Image(uiImage: customImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 84, height: 84)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.violet.opacity(0.5), lineWidth: 2))
                } else {
                    Circle()
                        .fill(Theme.violet.opacity(0.15))
                        .frame(width: 84, height: 84)
                    Image(systemName: "figure.run")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Theme.violet)
                }
            }
            HStack(alignment: .center, spacing: 8) {
                Text(AppLanguage.shared.s("나의 러닝", "My Runs"))
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                #if canImport(ImagePlayground)
                if #available(iOS 18.2, *) {
                    MiniMeEditButton()
                }
                #endif
            }
            Text(AppLanguage.shared.s("\(manager.activities.count)개 활동 기록", "\(manager.activities.count) activities"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Stats section

    private var statsSection: some View {
        let s0 = cachedMonthStats.count > 0 ? cachedMonthStats[0] : periodStats(monthOffset: 0)
        let s1 = cachedMonthStats.count > 1 ? cachedMonthStats[1] : periodStats(monthOffset: 1)
        let s2 = cachedMonthStats.count > 2 ? cachedMonthStats[2] : periodStats(monthOffset: 2)
        let y0 = cachedYearStats.count > 0  ? cachedYearStats[0]  : yearStats(yearOffset: 0)
        let y1 = cachedYearStats.count > 1  ? cachedYearStats[1]  : yearStats(yearOffset: 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text(AppLanguage.shared.s("기간별 결산", "Period Summary"))
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            SummarySectionCard(stats: s0, manager: manager,
                               preloadedFormMetrics: cachedMonthFormMetrics[s0.kind.title]) { selectedSummaryStats = SelectedSummaryStats(stats: s0) }
                .padding(.horizontal, 16)
            SummarySectionCard(stats: s1, manager: manager,
                               preloadedFormMetrics: cachedMonthFormMetrics[s1.kind.title]) { selectedSummaryStats = SelectedSummaryStats(stats: s1) }
                .padding(.horizontal, 16)
            SummarySectionCard(stats: s2, manager: manager,
                               preloadedFormMetrics: cachedMonthFormMetrics[s2.kind.title]) { selectedSummaryStats = SelectedSummaryStats(stats: s2) }
                .padding(.horizontal, 16)
            SummarySectionCard(stats: y0, manager: manager) { selectedSummaryStats = SelectedSummaryStats(stats: y0) }
                .padding(.horizontal, 16)
            SummarySectionCard(stats: y1, manager: manager) { selectedSummaryStats = SelectedSummaryStats(stats: y1) }
                .padding(.horizontal, 16)
        }
        .sheet(item: $selectedSummaryStats) { sel in
            SummaryShareCardScreen(statsList: [sel.stats], miniMeImage: miniMeStore.image)
        }
    }

    // MARK: - Shoes section

    private func refreshShoeKmCache() {
        var dict: [UUID: Double] = [:]
        for shoe in shoes {
            let sid = shoe.id.uuidString
            let workoutIDs = Set(allStories.filter { $0.shoeID == sid }.map { $0.workoutID })
            guard !workoutIDs.isEmpty else { dict[shoe.id] = 0; continue }
            dict[shoe.id] = manager.activities
                .filter { workoutIDs.contains($0.id.uuidString) }
                .reduce(0) { $0 + $1.distance } / 1000
        }
        shoeKmCache = dict
    }

    private func cumulativeKm(for shoe: Shoe) -> Double {
        shoeKmCache[shoe.id] ?? 0
    }

    private var shoesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppLanguage.shared.s("신발", "Shoes"))
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    showAddShoe = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.violet)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            if shoes.isEmpty {
                Text(AppLanguage.shared.s("등록된 신발이 없어요. + 버튼으로 추가하세요.", "No shoes added. Tap + to add one."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shoes.enumerated()), id: \.element.id) { idx, shoe in
                        if idx > 0 { thinDivider }
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Theme.violet.opacity(0.15))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "shoe.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Theme.violet)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shoe.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(shoe.addedDate, format: .dateTime.year().month().day()
                                    .locale(AppLanguage.shared.isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "ko_KR")))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            let km = cumulativeKm(for: shoe)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(String(format: km >= 100 ? "%.0f" : "%.1f", km))
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .foregroundStyle(.white)
                                Text("km")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                shoeToDelete = shoe
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.red.opacity(0.6))
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
            }
        }
        .sheet(isPresented: $showAddShoe) {
            AddShoeSheet()
        }
        .alert(AppLanguage.shared.s("신발 삭제", "Delete Shoe"), isPresented: .init(
            get: { shoeToDelete != nil },
            set: { if !$0 { shoeToDelete = nil } }
        )) {
            Button(AppLanguage.shared.s("삭제", "Delete"), role: .destructive) {
                if let shoe = shoeToDelete { modelContext.delete(shoe) }
                shoeToDelete = nil
            }
            Button(AppLanguage.shared.s("취소", "Cancel"), role: .cancel) { shoeToDelete = nil }
        } message: {
            if let shoe = shoeToDelete {
                Text(AppLanguage.shared.s("'\(shoe.displayName)'을(를) 삭제하면 복구할 수 없어요.", "'\(shoe.displayName)' cannot be recovered after deletion."))
            }
        }
    }

    // MARK: - Milestones section

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLanguage.shared.s("마일스톤", "Milestones"))
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(badgesCache) { badge in
                    BadgeCell(badge: badge)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Crew section

    private var crewNicknameSection: some View {
        let L = AppLanguage.shared
        let isValid = crewNicknameManager.isValid(nicknameInput)
        return VStack(alignment: .leading, spacing: 12) {
            Text(L.s("크루", "Crew"))
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L.s("닉네임", "Nickname"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            L.s("크루에서 사용할 이름", "Name for crew"),
                            text: $nicknameInput
                        )
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($nicknameFieldFocused)

                        if !nicknameInput.isEmpty && !isValid {
                            Text(L.s("2~12자로 입력해주세요", "Enter 2–12 characters"))
                                .font(.caption2)
                                .foregroundStyle(Theme.heartRate)
                        }
                    }

                    Button(nicknameSavedFlash ? L.s("저장됨 ✓", "Saved ✓") : L.s("저장", "Save")) {
                        crewNicknameManager.save(nicknameInput)
                        nicknameFieldFocused = false
                        nicknameSavedFlash = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            nicknameSavedFlash = false
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isValid ? (nicknameSavedFlash ? Color.green : Theme.violet) : Color.secondary.opacity(0.4))
                    .disabled(!isValid)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)

        }
    }

    // MARK: - Settings section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLanguage.shared.s("설정", "Settings"))
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            // Subscription
            SubscriptionSectionCard()
                .padding(.horizontal, 16)

            // Activity type filter
            VStack(spacing: 0) {
                settingRow {
                    Text(AppLanguage.shared.s("활동 종류", "Activity Type"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                thinDivider
                settingRow {
                    Label(AppLanguage.shared.s("러닝", "Running"), systemImage: "figure.run").foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: $showRunning).labelsHidden().tint(Theme.violet)
                }
                thinDivider
                settingRow {
                    Label(AppLanguage.shared.s("걷기", "Walking"), systemImage: "figure.walk").foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: $showWalking).labelsHidden().tint(Theme.violet)
                }
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)

            // Display preferences
            VStack(spacing: 0) {
                settingRow {
                    Text(AppLanguage.shared.s("거리 단위", "Distance Unit")).foregroundStyle(.white)
                    Spacer()
                    Picker("", selection: $useMiles) {
                        Text("km").tag(false)
                        Text(AppLanguage.shared.s("마일", "mi")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                }
                thinDivider
                settingRow {
                    Text(AppLanguage.shared.s("언어", "Language")).foregroundStyle(.white)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { AppLanguage.shared.isEnglish },
                        set: { AppLanguage.shared.isEnglish = $0 }
                    )) {
                        Text("한국어").tag(false)
                        Text("English").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)

            // HealthKit
            VStack(spacing: 0) {
                settingRow {
                    Label(AppLanguage.shared.s("건강 앱", "Health App"), systemImage: "heart.text.square").foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(manager.authorizationStatus == .authorized
                                  ? Theme.elevation : Theme.heartRate)
                            .frame(width: 7, height: 7)
                        Text(manager.authorizationStatus == .authorized
                             ? AppLanguage.shared.s("연결됨", "Connected")
                             : AppLanguage.shared.s("미연결", "Not connected"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                thinDivider
                settingRow {
                    Label(AppLanguage.shared.s("iCloud 동기화", "iCloud Sync"), systemImage: "icloud")
                        .foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(cloudKitSyncAvailable ? Theme.elevation : Color.gray)
                            .frame(width: 7, height: 7)
                        Text(cloudKitSyncAvailable
                             ? AppLanguage.shared.s("사용 중", "Active")
                             : AppLanguage.shared.s("사용 안 함", "Inactive"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // DOB 없을 때만 수동 나이 입력 노출
                let noDOB = (manager.userDateOfBirth?.year ?? 0) <= 1900
                if noDOB {
                    thinDivider
                    settingRow {
                        @Bindable var mgr = manager
                        Label(AppLanguage.shared.s("나이 (존 계산)", "Age (Zone calc.)"),
                              systemImage: "person").foregroundStyle(.white)
                        Spacer()
                        Stepper(
                            manager.manualAge > 0 ? "\(manager.manualAge)" : AppLanguage.shared.s("미설정", "Not set"),
                            value: $mgr.manualAge, in: 0...90, step: 1
                        )
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                if manager.authorizationStatus != .authorized {
                    thinDivider
                    settingRow {
                        Button {
                            Task { await manager.requestAuthorization() }
                        } label: {
                            Text(AppLanguage.shared.s("권한 다시 요청", "Re-request Access"))
                                .font(.subheadline)
                                .foregroundStyle(Theme.violet)
                        }
                        Spacer()
                    }
                }
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)

            // App info
            VStack(spacing: 0) {
                settingRow {
                    Text(AppLanguage.shared.s("앱 버전", "App Version")).foregroundStyle(.white)
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .font(.caption).foregroundStyle(.secondary)
                }
                thinDivider
                settingRow {
                    Text(AppLanguage.shared.s("만든 곳", "Made by")).foregroundStyle(.white)
                    Spacer()
                    Text("MIMOPlanner").font(.caption).foregroundStyle(.secondary)
                }
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)

            #if DEBUG
            Button {
                showDebug = true
            } label: {
                Text("🛠 Debug")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
            }
            .sheet(isPresented: $showDebug) {
                MRDebugView()
                    .environmentObject(engine)
                    .environment(raceDetector)
                    .preferredColorScheme(.dark)
            }
            #endif
        }
    }

    private func settingRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    // MARK: - Badge computation

    private func computeBadges() -> [BadgeInfo] {
        let all = manager.activities.sorted { $0.date < $1.date }
        let runs = all.filter { $0.type == .running }

        func firstRun(over dist: Double) -> Activity? { runs.first { $0.distance >= dist } }

        let L = AppLanguage.shared
        var badges: [BadgeInfo] = [
            .init(id: "first_run", icon: "figure.run",  title: L.s("첫 러닝", "First Run"),
                  achieved: !runs.isEmpty,                        achievedDate: runs.first?.date),
            .init(id: "5k",   icon: "flag",        title: L.s("5K 완주", "5K Finish"),
                  achieved: firstRun(over:  5000) != nil,         achievedDate: firstRun(over:  5000)?.date),
            .init(id: "10k",  icon: "flag.fill",   title: L.s("10K 완주", "10K Finish"),
                  achieved: firstRun(over: 10000) != nil,         achievedDate: firstRun(over: 10000)?.date),
            .init(id: "half", icon: "medal",        title: L.s("하프 완주", "Half Finish"),
                  achieved: firstRun(over: 21097) != nil,         achievedDate: firstRun(over: 21097)?.date),
            .init(id: "full", icon: "trophy.fill",  title: L.s("풀 완주", "Full Finish"),
                  achieved: firstRun(over: 42195) != nil,         achievedDate: firstRun(over: 42195)?.date),
        ]

        // Cumulative distance (all activity types)
        var totalKm = 0.0
        var cumDates: [Int: Date] = [:]
        for a in all {
            totalKm += a.distance / 1000
            for t in [100, 300, 500, 1000] where cumDates[t] == nil && totalKm >= Double(t) {
                cumDates[t] = a.date
            }
        }
        badges += [
            .init(id: "cum100",  icon: "map",           title: L.s("누적 100km", "100km Total"),
                  achieved: cumDates[100]  != nil, achievedDate: cumDates[100]),
            .init(id: "cum300",  icon: "map.fill",       title: L.s("누적 300km", "300km Total"),
                  achieved: cumDates[300]  != nil, achievedDate: cumDates[300]),
            .init(id: "cum500",  icon: "globe.americas", title: L.s("누적 500km", "500km Total"),
                  achieved: cumDates[500]  != nil, achievedDate: cumDates[500]),
            .init(id: "cum1000", icon: "globe",          title: L.s("누적 1000km", "1000km Total"),
                  achieved: cumDates[1000] != nil, achievedDate: cumDates[1000]),
        ]

        // Week streak
        let maxStreak = computeMaxWeekStreak(runs: runs)
        badges += [
            .init(id: "streak4",  icon: "flame.fill", title: L.s("4주 연속", "4-Wk Streak"),  achieved: maxStreak >= 4,  achievedDate: nil),
            .init(id: "streak8",  icon: "bolt.fill",  title: L.s("8주 연속", "8-Wk Streak"),  achieved: maxStreak >= 8,  achievedDate: nil),
            .init(id: "streak12", icon: "crown.fill", title: L.s("12주 연속", "12-Wk Streak"), achieved: maxStreak >= 12, achievedDate: nil),
        ]

        return badges
    }

    private func computeMaxWeekStreak(runs: [Activity]) -> Int {
        guard !runs.isEmpty else { return 0 }
        let cal = Calendar.current
        let weekStarts = Set(runs.compactMap {
            cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.date))
        }).sorted()
        var maxStreak = 1, cur = 1
        for i in 1..<weekStarts.count {
            let days = cal.dateComponents([.day], from: weekStarts[i - 1], to: weekStarts[i]).day ?? 0
            if days == 7 { cur += 1 } else { cur = 1 }
            if cur > maxStreak { maxStreak = cur }
        }
        return maxStreak
    }
}

// MARK: - Summary section card (inline in Me tab)

private struct FormMetricsData {
    let cadence: Double?
    let prevCadence: Double?
    let power: Double?
    let prevPower: Double?
    let strideLength: Double?
    let prevStrideLength: Double?
    var hasAny: Bool { cadence != nil || power != nil || strideLength != nil }
}

private struct SummarySectionCard: View {
    let stats: SummaryPeriodStats
    let manager: HealthKitManager
    var preloadedFormMetrics: FormMetricsData? = nil
    let onShare: () -> Void

    @State private var formMetrics: FormMetricsData? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(stats.kind.subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.violet)
                }
                Spacer()
                Button(action: onShare) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                        Text({
                            if case .monthly = stats.kind {
                                return AppLanguage.shared.s("월말 결산", "Monthly")
                            }
                            return AppLanguage.shared.s("연말 결산", "Yearly")
                        }())
                        .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.violet)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.violet.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(stats.isEmpty)
                .opacity(stats.isEmpty ? 0.35 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            // Stats grid
            if stats.isEmpty {
                Text(AppLanguage.shared.s("이 기간에 기록된 활동이 없어요", "No activities for this period"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                HStack(spacing: 0) {
                    statCell(
                        value: stats.distanceStr + " " + stats.distanceUnit,
                        label: AppLanguage.shared.s("총 거리", "TOTAL"),
                        color: .white
                    )
                    cellDivider
                    statCell(
                        value: stats.durationStr,
                        label: AppLanguage.shared.s("운동 시간", "TIME"),
                        color: Theme.time
                    )
                    cellDivider
                    statCell(
                        value: AppLanguage.shared.s("\(stats.runCount)회", "\(stats.runCount)"),
                        label: AppLanguage.shared.s("러닝", "RUNS"),
                        color: Theme.violet
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if let pace = stats.avgPaceStr {
                    HStack(spacing: 6) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.pace.opacity(0.7))
                        Text(AppLanguage.shared.s("평균 페이스", "AVG PACE"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(pace)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        if let longest = stats.longestStr {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(AppLanguage.shared.s("최장 \(longest)", "Longest \(longest)"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                // Comparison strip
                if stats.compDistanceKm != nil {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        if let d = stats.distanceDeltaStr {
                            compChip(text: d, up: stats.distanceDeltaIsUp)
                        }
                        if let c = stats.runCountDeltaStr {
                            compChip(text: c, up: stats.runCount >= (stats.compRunCount ?? 0))
                        }
                        if let p = stats.paceDeltaStr {
                            compChip(text: p, up: p.contains(AppLanguage.shared.s("빨라짐", "faster")))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }

                // YTD
                if let ytd = stats.ytdStr {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.violet.opacity(0.7))
                        Text(ytd)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.violet.opacity(0.85))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }

                // Form metrics (워치 전용, 비동기 로드)
                if let fm = formMetrics, fm.hasAny {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    HStack(spacing: 0) {
                        if let cad = fm.cadence {
                            formMetricCell(value: "\(Int(cad.rounded()))spm",
                                           label: AppLanguage.shared.s("케이던스", "Cadence"),
                                           current: cad, prev: fm.prevCadence,
                                           higherBetter: true)
                        }
                        if let pwr = fm.power {
                            if fm.cadence != nil { formMetricDivider }
                            formMetricCell(value: "\(Int(pwr.rounded()))W",
                                           label: AppLanguage.shared.s("파워", "Power"),
                                           current: pwr, prev: fm.prevPower,
                                           higherBetter: true)
                        }
                        if let str = fm.strideLength {
                            if fm.cadence != nil || fm.power != nil { formMetricDivider }
                            formMetricCell(value: String(format: "%.2fm", str),
                                           label: AppLanguage.shared.s("보폭", "Stride"),
                                           current: str, prev: fm.prevStrideLength,
                                           higherBetter: true)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
            }

            Spacer(minLength: 14)
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .task(id: stats.kind.title) {
            // MeView에서 사전 계산된 데이터가 있으면 즉시 사용 — 디스크 재조회 없음
            if let pre = preloadedFormMetrics { formMetrics = pre; return }
            guard case .monthly(let y, let m) = stats.kind else { return }
            let cal = Calendar.current
            let start = cal.date(from: DateComponents(year: y, month: m)) ?? Date()
            let end   = cal.date(byAdding: .month, value: 1, to: start)  ?? Date()
            let prev  = cal.date(byAdding: .month, value: -1, to: start) ?? Date()

            async let cadFetch = manager.fetchMetricHistory(.cadence,      from: prev)
            async let pwrFetch = manager.fetchMetricHistory(.power,        from: prev)
            async let strFetch = manager.fetchMetricHistory(.strideLength, from: prev)
            let (cad, pwr, str) = await (cadFetch, pwrFetch, strFetch)

            func avg(_ pts: [(date: Date, value: Double)], from s: Date, to e: Date) -> Double? {
                let f = pts.filter { $0.date >= s && $0.date < e }
                guard !f.isEmpty else { return nil }
                return f.map(\.value).reduce(0, +) / Double(f.count)
            }

            formMetrics = FormMetricsData(
                cadence:          avg(cad, from: start, to: end),
                prevCadence:      avg(cad, from: prev,  to: start),
                power:            avg(pwr, from: start, to: end),
                prevPower:        avg(pwr, from: prev,  to: start),
                strideLength:     avg(str, from: start, to: end),
                prevStrideLength: avg(str, from: prev,  to: start)
            )
        }
        .onChange(of: preloadedFormMetrics?.cadence) {
            if let pre = preloadedFormMetrics { formMetrics = pre }
        }
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 0.5, height: 28)
            .padding(.horizontal, 10)
    }

    private func compChip(text: String, up: Bool) -> some View {
        let color: Color = up ? .green : Color(red: 1, green: 0.45, blue: 0.45)
        return Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func formMetricCell(value: String, label: String,
                                current: Double, prev: Double?,
                                higherBetter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(value)
                    .font(.system(size: 14, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let p = prev {
                    let up = current > p
                    let good = higherBetter ? up : !up
                    Image(systemName: up ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(good ? Color.green : Color(red: 1, green: 0.45, blue: 0.45))
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(minWidth: 72, alignment: .leading)
    }

    private var formMetricDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 0.5, height: 32)
            .padding(.horizontal, 12)
    }
}

// MARK: - Badge Cell

private struct BadgeCell: View {
    let badge: BadgeInfo

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(badge.achieved ? Theme.violet.opacity(0.18) : Color.white.opacity(0.05))
                    .frame(width: 52, height: 52)
                Image(systemName: badge.icon)
                    .font(.system(size: 22, weight: badge.achieved ? .semibold : .light))
                    .foregroundStyle(badge.achieved ? Theme.violet : Color.white.opacity(0.2))
            }
            Text(badge.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(badge.achieved ? .white : Color.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if let date = badge.achievedDate {
                    Text(shortDate(date))
                        .foregroundStyle(.secondary)
                } else if badge.achieved {
                    Text(AppLanguage.shared.s("달성", "Done")).foregroundStyle(Theme.violet.opacity(0.8))
                } else {
                    Text(AppLanguage.shared.s("미달성", "Locked")).foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func shortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yy.M.d"
        return fmt.string(from: date)
    }
}

// MARK: - MiniMe 편집 버튼 (iOS 18.2+, Apple Intelligence)

#if canImport(ImagePlayground)
@available(iOS 18.2, *)
private struct MiniMeEditButton: View {
    @Environment(CustomMiniMeStore.self) private var miniMeStore
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground

    @State private var pickerItem: PhotosPickerItem?
    @State private var sourceUIImage: UIImage?
    @State private var showPlayground = false

    var body: some View {
        if supportsImagePlayground {
            HStack(spacing: 6) {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(
                        miniMeStore.image != nil
                            ? AppLanguage.shared.s("다시 만들기", "Redo")
                            : AppLanguage.shared.s("만들기", "Create"),
                        systemImage: miniMeStore.image != nil ? "arrow.clockwise" : "sparkles"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.violet)
                }
                .buttonStyle(.plain)

                if miniMeStore.image != nil {
                    Button {
                        miniMeStore.clear()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                Task {
                    guard let item = newItem,
                          let data = try? await item.loadTransferable(type: Data.self),
                          let img = UIImage(data: data) else { return }
                    sourceUIImage = img
                    showPlayground = true
                }
            }
            .imagePlaygroundSheet(
                isPresented: $showPlayground,
                concepts: [.text("러너, 귀여운 캐릭터, 바이올렛 색깔, 만화체, 밝고 귀여운 스타일")],
                sourceImage: sourceUIImage.map { Image(uiImage: $0) }
            ) { url in
                if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                    miniMeStore.save(img)
                }
                showPlayground = false
                pickerItem = nil
                sourceUIImage = nil
            }
        }
    }
}
#endif

// MARK: - Subscription Card

struct SubscriptionSectionCard: View {
    private let pro = ProManager.shared

    private var product: Product? { pro.products.first(where: { $0.id == ProManager.sixMonthID }) }
    private var isEligibleForIntro: Bool { pro.introEligibility[ProManager.sixMonthID] == true }

    private var introOfferLabel: String {
        let L = AppLanguage.shared
        guard let offer = product?.subscription?.introductoryOffer else { return L.s("무료 체험", "Free Trial") }
        let v = offer.period.value
        switch offer.period.unit {
        case .day:   return L.s("\(v)일 무료", "\(v)-day free")
        case .week:  return L.s("\(v)주 무료", "\(v)-week free")
        case .month: return L.s("\(v)개월 무료", "\(v)-month free")
        case .year:  return L.s("\(v)년 무료", "\(v)-year free")
        @unknown default: return L.s("무료 체험", "Free Trial")
        }
    }

    @State private var isPurchasing = false

    var body: some View {
        VStack(spacing: 0) {
            // Header gradient band
            LinearGradient(
                colors: [Theme.violet, Color(hex: "5B3FD6")],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 4)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 14
            ))

            VStack(spacing: 14) {
                // Title row
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.violet)
                    Text("MIMO Pro")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    if pro.isPro {
                        Text(AppLanguage.shared.s("구독 중", "Active"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.violet.opacity(0.15))
                            .clipShape(Capsule())
                    } else if pro.isTrialActive {
                        Text(AppLanguage.shared.s("체험 \(pro.daysRemainingInTrial)일 남음", "Trial · \(pro.daysRemainingInTrial)d left"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    } else {
                        Text(AppLanguage.shared.s("체험 종료", "Trial Ended"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                // Subscription term label
                Text(AppLanguage.shared.s("6개월 자동 갱신 구독", "6-Month Auto-Renewing Subscription"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Price block
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(product?.displayPrice ?? "₩11,000")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(AppLanguage.shared.s("/ 6개월", "/ 6 months"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                    Spacer()
                    if isEligibleForIntro {
                        Text(introOfferLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.violet)
                    } else {
                        Text(AppLanguage.shared.s("월 ₩1,833", "₩1,833/mo"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                // CTA
                if !pro.isPro {
                    Button {
                        Task { await doPurchase() }
                    } label: {
                        Group {
                            if isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                Text(isEligibleForIntro
                                     ? AppLanguage.shared.s("무료로 시작하기", "Start Free")
                                     : AppLanguage.shared.s("구독하기", "Subscribe"))
                                    .font(.system(size: 15, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing || product == nil)
                    .opacity((isPurchasing || product == nil) ? 0.6 : 1)

                    Button {
                        Task { await pro.restorePurchases() }
                    } label: {
                        Text(AppLanguage.shared.s("구독 복원", "Restore Purchase"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }

                if let err = pro.purchaseError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(Theme.heartRate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let err = pro.productLoadError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(Theme.heartRate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Legal
                VStack(spacing: 6) {
                    Text(AppLanguage.shared.s("구독은 기간 종료 24시간 전까지 취소하지 않으면 자동 갱신됩니다. Apple ID 계정을 통해 관리할 수 있습니다.", "Subscription auto-renews unless cancelled at least 24 hours before the end of the period. Manage via Apple ID."))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Link(AppLanguage.shared.s("개인정보처리방침", "Privacy Policy"),
                             destination: URL(string: "https://mimoplanner.kr/privacy.html")!)
                        Text("·").foregroundStyle(.tertiary)
                        Link(AppLanguage.shared.s("이용약관", "Terms of Use"),
                             destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Theme.cardBackground)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 14,
                bottomTrailingRadius: 14, topTrailingRadius: 0
            ))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .task {
            await pro.loadProducts()
        }
    }

    private func doPurchase() async {
        guard let product else { return }
        isPurchasing = true
        _ = await pro.purchase(product)
        isPurchasing = false
    }
}

// MARK: - Add Shoe Sheet

private struct AddShoeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        field(label: AppLanguage.shared.s("신발 이름", "Shoe Name"), placeholder: AppLanguage.shared.s("예: Nike Pegasus 41", "e.g. Nike Pegasus 41"), text: $name)
                    }
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle(AppLanguage.shared.s("신발 추가", "Add Shoe"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("취소", "Cancel")) { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguage.shared.s("추가", "Add")) {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let shoe = Shoe(name: name.trimmingCharacters(in: .whitespaces), brand: "")
                        modelContext.insert(shoe)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? Color.white.opacity(0.3) : Theme.violet)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func field(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

// MARK: - Preview

#Preview("설정 - iCloud 동기화 행") {
    struct SyncCardPreview: View {
        @AppStorage("cloudKitSyncAvailable") private var iCloudOn = true
        var body: some View {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 24) {
                    // HealthKit + iCloud 카드 (실제 settingsSection과 동일 구조)
                    VStack(spacing: 0) {
                        row {
                            Label("건강 앱", systemImage: "heart.text.square").foregroundStyle(.white)
                            Spacer()
                            HStack(spacing: 5) {
                                Circle().fill(Theme.elevation).frame(width: 7, height: 7)
                                Text("연결됨").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        divider
                        row {
                            Label("iCloud 동기화", systemImage: "icloud").foregroundStyle(.white)
                            Spacer()
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(iCloudOn ? Theme.elevation : Color.gray)
                                    .frame(width: 7, height: 7)
                                Text(iCloudOn ? "사용 중" : "사용 안 함")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    // 토글로 두 상태 전환
                    Toggle("iCloudOn 시뮬레이션", isOn: $iCloudOn)
                        .tint(Theme.violet)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 40)
            }
        }

        private func row<C: View>(@ViewBuilder _ c: () -> C) -> some View {
            HStack { c() }.padding(.horizontal, 16).padding(.vertical, 13)
        }
        private var divider: some View {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5).padding(.horizontal, 16)
        }
    }
    return SyncCardPreview().preferredColorScheme(.dark)
}

// MARK: - Planned Race Row

private struct PlannedRaceRow: View {
    @Bindable var race: MyPlannedRace
    var locked: Bool = false
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                // 날짜 배지
                VStack(spacing: 2) {
                    if let d = race.raceDate {
                        Text(d, format: .dateTime.month(.abbreviated))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(race.isPast ? .secondary : Theme.violet)
                        Text(d, format: .dateTime.day())
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(race.isPast ? Color.secondary : Color.white)
                    } else {
                        Text("—")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 40)

                Rectangle()
                    .fill(race.isPast ? Color.white.opacity(0.12) : Theme.violet.opacity(0.40))
                    .frame(width: 1.5)
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(race.raceName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(race.isPast ? Color.secondary : Color.white)
                            .lineLimit(2)
                        if race.isPast {
                            Text(AppLanguage.shared.s("완료", "Done"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    HStack(spacing: 8) {
                        if let time = race.startTime, !time.isEmpty {
                            Label(time, systemImage: "clock")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        if !race.startPlace.isEmpty {
                            Label(race.startPlace, systemImage: "mappin")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.25))
                }
                .buttonStyle(.plain)
            }

            // 거리 선택 칩
            if !race.distancesKm.isEmpty {
                HStack(spacing: 6) {
                    ForEach(race.distancesKm, id: \.self) { km in
                        let selected = race.selectedDistanceKm == km
                        Button {
                            race.selectedDistanceKm = selected ? 0 : km
                        } label: {
                            Text(distanceLabel(km))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selected ? Theme.violet : Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 54)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(race.isPast ? Color.clear : Theme.violet.opacity(0.20), lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            if locked {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                    Text(AppLanguage.shared.s("훈련계획은 구독 후 이용 가능", "Training plan requires subscription"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .opacity(locked ? 0.75 : 1.0)
    }

    private func distanceLabel(_ km: Double) -> String {
        if km == 42.195  { return AppLanguage.shared.s("풀", "Full") }
        if km == 21.0975 { return AppLanguage.shared.s("하프", "Half") }
        let i = Int(km)
        return km == Double(i) ? "\(i)K" : "\(km)K"
    }
}

// MARK: - Race Search Sheet

struct RaceSearchSheet: View {
    let raceDetector: RaceDetector
    let existing: Set<String>

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var filteredRaces: [BundledRace] {
        let today = Calendar.current.startOfDay(for: Date())
        let words = query.trimmingCharacters(in: .whitespaces)
            .split(separator: " ").map(String.init)

        return raceDetector.races.filter { race in
            guard let d = race.date, d >= today else { return false }
            guard !existing.contains(race.name + race.dateString) else { return false }
            if words.isEmpty { return true }
            return words.allSatisfy { race.name.localizedCaseInsensitiveContains($0) }
        }
        .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(AppLanguage.shared.s("대회 이름 검색", "Search race name"), text: $query)
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    if filteredRaces.isEmpty {
                        Spacer()
                        Text(AppLanguage.shared.s("검색 결과 없음", "No results"))
                            .foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        List {
                            ForEach(filteredRaces) { race in
                                RaceSearchRow(race: race)
                                    .listRowBackground(Theme.cardBackground)
                                    .listRowSeparatorTint(Color.white.opacity(0.08))
                                    .contentShape(Rectangle())
                                    .onTapGesture { add(race) }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(AppLanguage.shared.s("대회 등록", "Add Race"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Theme.violet)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func add(_ race: BundledRace) {
        modelContext.insert(MyPlannedRace(from: race))
        dismiss()
    }
}

// MARK: - Race Search Row

private struct RaceSearchRow: View {
    let race: BundledRace

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 1) {
                if let d = race.date {
                    Text(d, format: .dateTime.month(.abbreviated))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.violet)
                    Text(d, format: .dateTime.day())
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(race.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let time = race.startTimeString, !time.isEmpty {
                        Label(time, systemImage: "clock")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Label(race.start, systemImage: "mappin")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !race.distancesKm.isEmpty {
                    let dist = race.distancesKm.map { km -> String in
                        if km == 42.195  { return AppLanguage.shared.s("풀", "Full") }
                        if km == 21.0975 { return AppLanguage.shared.s("하프", "Half") }
                        let i = Int(km)
                        return km == Double(i) ? "\(i)K" : "\(km)K"
                    }.joined(separator: " · ")
                    Text(dist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.pace.opacity(0.9))
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "plus.circle")
                .font(.system(size: 20))
                .foregroundStyle(Theme.violet)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Race Goal Types

enum RaceGoalKind: String, CaseIterable, Identifiable {
    case tenK, half, full
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tenK: return "10K"
        case .half: return AppLanguage.shared.s("하프", "Half")
        case .full: return AppLanguage.shared.s("풀", "Full")
        }
    }
}

// MARK: - Goal Time Edit Sheet

private struct GoalTimeEditSheet: View {
    let kind: RaceGoalKind
    @Binding var current: String
    @Environment(\.dismiss) private var dismiss

    @State private var hours = 0
    @State private var minutes = 30
    @State private var seconds = 0

    private var maxHours: Int { kind == .tenK ? 4 : 9 }

    var body: some View {
        let L = AppLanguage.shared
        NavigationStack {
            VStack(spacing: 20) {
                Text(kind.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    Picker(L.s("시간", "h"), selection: $hours) {
                        ForEach(0...maxHours, id: \.self) { h in
                            Text("\(h)\(L.s("시간", "h"))").tag(h)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker(L.s("분", "m"), selection: $minutes) {
                        ForEach(0...59, id: \.self) { m in
                            Text("\(m)\(L.s("분", "m"))").tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker(L.s("초", "s"), selection: $seconds) {
                        ForEach(0...59, id: \.self) { s in
                            Text("\(s)\(L.s("초", "s"))").tag(s)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 150)
            }
            .padding(.top, 8)
            .navigationTitle(L.s("목표 기록 설정", "Set Goal Time"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.s("취소", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.s("저장", "Save")) {
                        current = String(format: "%d:%02d:%02d", hours, minutes, seconds)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if !current.isEmpty {
                        Button(role: .destructive) {
                            current = ""
                            dismiss()
                        } label: {
                            Text(L.s("목표 삭제", "Remove Goal"))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .onAppear { parseCurrentTime() }
        }
        .preferredColorScheme(.dark)
    }

    private func parseCurrentTime() {
        let parts = current.split(separator: ":").compactMap { Int($0) }
        if parts.count == 3 {
            hours = parts[0]; minutes = parts[1]; seconds = parts[2]
        } else if parts.count == 2 {
            hours = 0; minutes = parts[0]; seconds = parts[1]
        } else {
            hours = kind == .tenK ? 0 : 1
            minutes = kind == .tenK ? 50 : 30
            seconds = 0
        }
    }
}

// MARK: - Preview: 크루 닉네임 섹션

#Preview("크루 닉네임") {
    struct CrewPreview: View {
        @State private var manager = CrewNicknameManager()
        @State private var input: String = ""

        var body: some View {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    Text("크루")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("닉네임")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                TextField("크루에서 사용할 이름", text: $input)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                if !input.isEmpty && !manager.isValid(input) {
                                    Text("2~12자로 입력해주세요")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.heartRate)
                                }
                            }
                            let isValid = manager.isValid(input)
                            let unchanged = input.trimmingCharacters(in: .whitespaces) == (manager.nickname ?? "")
                            Button("저장") { manager.save(input) }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isValid && !unchanged ? Theme.violet : Color.secondary.opacity(0.4))
                                .disabled(!isValid || unchanged)
                                .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    if let saved = manager.nickname {
                        Text("저장된 닉네임: \(saved)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 40)
            }
        }
    }
    return CrewPreview()
}
