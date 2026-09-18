import SwiftUI
import MapKit
import SwiftData
import PhotosUI
import Charts
import HealthKit
#if canImport(ImagePlayground)
import ImagePlayground
#endif

// MARK: - Detail Panel

enum DetailPanel: String, CaseIterable {
    case combined            = "종합"
    case map                 = "경로"
    case heartRate           = "심박수"
    case cadence             = "케이던스"
    case groundContact       = "지면접촉"
    case strideLength        = "보폭"
    case power               = "파워"
    case verticalOscillation = "수직진폭"
    case elevation           = "고도"

    var label: String {
        let L = AppLanguage.shared
        return switch self {
        case .map:                  L.s("경로",     "Route")
        case .combined:             L.s("종합",     "Combined")
        case .heartRate:            L.s("심박수",   "HR")
        case .cadence:              L.s("케이던스", "Cadence")
        case .groundContact:        L.s("지면접촉","Gnd Contact")
        case .strideLength:         L.s("보폭",     "Stride")
        case .power:                L.s("파워",     "Power")
        case .verticalOscillation:  L.s("수직진폭", "Vert. Osc.")
        case .elevation:            L.s("고도",     "Elevation")
        }
    }

    var icon: String {
        switch self {
        case .map:                  return "map.fill"
        case .combined:             return "chart.xyaxis.line"
        case .heartRate:            return "heart.fill"
        case .cadence:              return "figure.run"
        case .groundContact:        return "stopwatch"
        case .strideLength:         return "arrow.left.and.right"
        case .power:                return "bolt.fill"
        case .verticalOscillation:  return "arrow.up.and.down"
        case .elevation:            return "mountain.2.fill"
        }
    }
}

// MARK: - ActivityDetailView

struct ActivityDetailView: View {
    let activity: Activity
    var manager: HealthKitManager

    @State private var detail: ActivityDetail?
    @State private var insight: InsightResult?
    @State private var isLoadingDetail = true
    @State private var showShareCard = false
    @State private var condition: ActivityCondition?
    @State private var raceSuggestion: RaceSuggestion?
    @State private var showManualRaceEntry = false
    @State private var showRouteShareCard = false
    @State private var showChartShare = false
    /// 칩으로 고른 상세 패널. `.combined` = 선택 없음(종합은 상단에 고정 표시).
    @State private var activePanel: DetailPanel = .combined
    /// 진입 시 기본 패널(경로)을 한 번만 적용하기 위한 플래그.
    /// 사용자가 칩을 닫아 선택 없음으로 돌린 뒤 다시 자동 선택되면 안 된다.
    @State private var didApplyDefaultPanel = false
    @State private var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    @State private var hrFetchDone = false
    /// 운동 후 180초 심박 (종료 기준 오프셋) · 회복 결과. 자격 미달·샘플 없음이면 nil → 섹션 미표시.
    @State private var postHR: [MRRecoveryPoint] = []
    @State private var recoveryResult: MRRecoveryResult? = nil
    /// 리듬 카드 회복 한 줄 입력 — τ와 과거 분포 내 위치. 자격 미달·샘플 부족이면 nil로 남아 카드가 침묵한다.
    @State private var recoveryShape: MRRecoveryShape? = nil
    /// loadRecovery 진행 중 — HR 시리즈가 오는 자리마다 불러도 중복 조회가 되지 않게 한다.
    /// `recoveryResult == nil`만으로는 부족하다: 첫 await 전에 두 번째 진입이 그 가드를 통과한다.
    @State private var isLoadingRecovery = false
    /// 비동기 computeHRZonesForDate 결과 전용 상태. detail?.hrZones보다 우선.
    @State private var displayZones: [HRZoneData] = []
    @State private var isComputingZones = false
    @State private var panelSeriesData: [(offset: TimeInterval, value: Double)] = []
    @State private var panelSeriesCache: [DetailPanel: [(offset: TimeInterval, value: Double)]] = [:]
    @State private var isLoadingPanelSeries = false
    @State private var panelScrollTrigger: Int = 0
    @State private var hillMatch: HillMatch?
    @State private var chartData: RunChartData = .empty
    @State private var isLoadingChart = false
    @State private var runInsights: [RunInsight] = []
    /// 사용자 입력(중복 workoutID는 최신 우선) + Apple(manager 맵 > detail 캐시)
    private var effortIndex: EffortIndex { EffortIndex(stories: panelAllStories, apple: manager.effortMap) }
    private var appleEffortForRun: AppleEffort? { manager.appleEffort(for: activity.id) ?? detail?.appleEffort }
    /// 이 런의 강도 — 내 입력 > Apple
    private var resolvedEffort: ResolvedEffort? {
        EffortResolver.resolve(userValue: effortIndex.user[activity.id.uuidString], apple: appleEffortForRun)
    }
    /// 강도 입력 카드 헤더 아래 한 줄 — 같은 유형 평소 강도(8주, 3건 미만이면 12주).
    private var effortBaselineNote: String? {
        guard activity.type == .running, let t = detail?.workoutType else { return nil }
        let s = EffortBaseline.typeSummary(for: t, asOf: activity.date, history: manager.activities, index: effortIndex,
                                           typeOf: manager.workoutTypeLookup(), excluding: activity.id)
        let L = AppLanguage.shared
        guard let m = s.median else {
            return s.count > 0 ? L.s("\(t.koreanLabel) 평소 강도 — 아직 \(s.count)회(3회부터 계산)", "\(t.koreanLabel) usual effort — \(s.count) so far (needs 3)") : nil
        }
        let src = s.isUserBased ? L.s("내 입력 기준", "from my ratings") : L.s("Apple 값 포함", "incl. Apple")
        return L.s("\(t.koreanLabel) 평소 \(m) · \(s.windowWeeks)주 \(s.count)회 · \(src)", "\(t.koreanLabel) usual \(m) · \(s.count) in \(s.windowWeeks)w · \(src)")
    }
    @State private var runSegmentSource: RunSegmentSource = .none
    @State private var runFadeStartKm: Double? = nil
    @State private var isInsightBackfilling = false
    @State private var formBaseline: RunningFormBaseline? = FormBaselineEngine.peekFromCache()
    @State private var formShifts: [MRFormShift] = []
    /// 열람 중인 러닝의 케이던스 잔차(실제 − 페이스 예상값) — 폼 카드 추세 문단 마무리용
    @State private var formRunCadenceResidual: Double? = nil
    @State private var formBackfillTask: Task<Void, Never>?
    @State private var effortRefreshTask: Task<Void, Never>?
    @Environment(RaceDetector.self) private var raceDetector
    @Environment(\.scenePhase) private var scenePhase
    @Query private var panelAllStories: [WorkoutStory]
    @Query private var panelAllShoes: [Shoe]
    @AppStorage("mapHRZoneMode") private var mapHRZoneMode: Bool = true
    @EnvironmentObject private var engine: MREngineStore

    private var level: LevelBucket { manager.userLevel.bucket }

    /// displayZones(비동기 계산) 우선, 없으면 detail.hrZones, 최후 동기 폴백.
    /// 운동 후 심박 회복 로드 — 종료 심박이 자격(최대심박 70%)을 넘고 60초 샘플이 있을 때만 결과가 생긴다.
    private func loadRecovery() async {
        guard recoveryResult == nil, !isLoadingRecovery,
              let endHR = MRRecovery.endHR(series: hrSamples, duration: activity.duration),
              MRRecovery.isEligible(endHR: endHR, maxHR: manager.estimatedMaxHR.map(Double.init)) else { return }
        isLoadingRecovery = true
        defer { isLoadingRecovery = false }
        let post = await manager.fetchPostWorkoutHR(for: activity.id)
        postHR = post
        recoveryResult = MRRecovery.compute(endHR: endHR, post: post)
        #if DEBUG
        print(String(format: "[회복] 종료심박 %.0f · 종료 후 샘플 %d개 · HRR1 %@",
                     endHR, post.count, recoveryResult.map { String(format: "%.0f", $0.hrr1) } ?? "없음(60초 샘플 없음)"))
        #endif
        // 회복 한 줄(τ·분위)은 급하지 않다. recoveryTauHistory는 캐시가 비면 12개월 재구축이라,
        // 호출자가 기다리는 일(심박존 재계산 등)을 막지 않게 떼어낸다.
        guard let r = recoveryResult, let d = r.decay else { return }
        Task {
            let start = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
            let taus = await manager.recoveryTauHistory(from: start, excluding: activity.id)
            let shape = MRRecoveryShape(r, percentile: MRRecovery.tauPercentile(d.tau, history: taus))
            // 늦게 도착하므로 topCaptionH가 28→38로 한 프레임에 튄다 — 구분선·아래 요소가 끊겨 내려가지 않게 잇는다.
            withAnimation(.snappy) { recoveryShape = shape }
            #if DEBUG
            if let s = shape {
                print(String(format: "[회복:모양] τ %.0f초 · x %.2f · HR∞ %.0f · 분위 %@",
                             s.decay.tau, s.decay.ratio, s.decay.asymptote,
                             s.percentile.map { String(format: "%.2f", $0) } ?? "표본부족"))
            }
            #endif
        }
    }

    private var effectiveHRZones: [HRZoneData] {
        if !displayZones.isEmpty { return displayZones }
        let zones = detail?.hrZones ?? []
        if !zones.isEmpty { return zones }
        guard hrFetchDone, !hrSamples.isEmpty else { return [] }
        return manager.computeHRZonesFromSamples(hrSamples)
    }

    // 확정된 대회 기록은 .race로 고정 — RunInsightSection의 workoutTypeFn과 같은 규칙.
    private func summaryWorkoutType(for id: UUID) -> WorkoutType? {
        if let match = raceDetector.matchFor(activityID: id), match.isConfirmed { return .race }
        return manager.cachedWorkoutTypeForStats(for: id)
    }

    /// 총평 5줄 입력 조립 — RunInsightSection과 같은 값들로, 공유 카드 "총평" 칩 전용.
    private var summaryContext: RunSummaryBuilder.Context {
        RunSummaryBuilder.Context(
            activity: activity, detail: detail, history: manager.activities,
            hrZones: effectiveHRZones, hrSamples: hrSamples,
            formBaseline: formBaseline, formShifts: formShifts,
            workoutType: summaryWorkoutType(for: activity.id) ?? .general,
            workoutTypeFn: summaryWorkoutType,
            effortIndex: effortIndex, heatHRModel: engine.heatHR,
            age: userAge, isMale: manager.userIsMale, easyPaceLookup: engine.easyPaceLookup,
            planPhase: matchedPlanWeek()?.phase,
            raceDetailFn: manager.detailFromCache,
            hrZonesFn: manager.hrZonesFromCache
        )
    }

    private var shareSummaryLines: [RunSummaryLine] { RunSummaryBuilder.lines(summaryContext) }

    private var confirmedRaceMatch: PersistedRaceMatch? {
        guard let m = raceDetector.matchFor(activityID: activity.id), m.isConfirmed else { return nil }
        return m
    }

    private var showRaceBanner: Bool {
        guard activity.type == .running, !isLoadingDetail, raceSuggestion != nil else { return false }
        guard let m = raceDetector.matchFor(activityID: activity.id) else { return true }
        return !m.isConfirmed && !m.isDismissed
    }

    private var isDismissedRace: Bool {
        guard activity.type == .running, !isLoadingDetail else { return false }
        return raceDetector.matchFor(activityID: activity.id)?.isDismissed == true
    }

    private var panelShoeText: String? {
        let wid = activity.id.uuidString
        guard let sid = panelAllStories.first(where: { $0.workoutID == wid })?.shoeID else { return nil }
        return panelAllShoes.first { $0.id.uuidString == sid }?.displayName
    }

    private var panelDateText: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: AppLanguage.shared.s("ko_KR", "en_US"))
        df.dateFormat = AppLanguage.shared.s("yyyy. M. d", "MMM d, yyyy")
        return df.string(from: activity.date)
    }

    private var panelWeekdayText: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: AppLanguage.shared.s("ko_KR", "en_US"))
        df.dateFormat = "EEEE"
        return df.string(from: activity.date)
    }

    private var panelTimeText: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: AppLanguage.shared.s("ko_KR", "en_US"))
        df.dateFormat = AppLanguage.shared.s("a h:mm", "h:mm a")
        return df.string(from: activity.date)
    }

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > 500   // iPad full-screen detection
            ZStack {
                Theme.background.ignoresSafeArea()
                if isWide {
                    // iPad: constrain content to 430pt centered
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        detailContent.frame(width: 430)
                        Spacer(minLength: 0)
                    }
                } else {
                    detailContent
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { formBackfillTask?.cancel() }
        }
        .onDisappear {
            formBackfillTask?.cancel()
            effortRefreshTask?.cancel()
        }
    }

    private var detailContent: some View {
        ScrollViewReader { proxy in
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailHeader(
                        activity: activity,
                        confirmedRace: confirmedRaceMatch,
                        onRaceRevoke: {
                            raceDetector.removeMatch(activityID: activity.id)
                            Task { await recomputeInsightWithRaceMatch() }
                        }
                    )
                    if activity.type == .running {
                        InsightCard(activity: activity, insight: insight, condition: condition,
                                    confirmedRace: confirmedRaceMatch, hillMatch: hillMatch,
                                    effortValue: resolvedEffort?.value)
                    }
                    StorySection(workoutID: activity.id.uuidString,
                                 activityType: activity.type,
                                 effort: resolvedEffort,
                                 appleValue: appleEffortForRun?.effective.map { EffortResolver.clamp($0) },
                                 baselineNote: effortBaselineNote)
                    combinedShareHeader
                    combinedPanelSection
                    Group {
                        RunInsightSection(
                            insights: runInsights,
                            workoutTypeLabel: detail?.workoutType.koreanLabel,
                            isAutoDetected: runSegmentSource == .detected,
                            activity: activity,
                            detail: detail,
                            history: manager.activities,
                            age: userAge,
                            isMale: manager.userIsMale,
                            hrMax: engine.phys.hrMax?.value,
                            hrZones: effectiveHRZones,
                            workoutTypeFn: { [rd = raceDetector, m = manager] id in
                                // 확정된 대회 기록은 .race로 고정 — 거리주 등 훈련 분류 덮어씀
                                if let match = rd.matchFor(activityID: id), match.isConfirmed { return .race }
                                return m.cachedWorkoutTypeForStats(for: id)
                            },
                            hrZonesFn: { [m = manager] id in m.hrZonesFromCache(id) },
                            isBackfilling: isInsightBackfilling || manager.isWorkoutTypeReclassifying,
                            isClassifying: manager.isOnDemandClassifying,
                            cadenceSeries: panelSeriesCache[.cadence] ?? [],
                            hrSamples: hrSamples,
                            formBaseline: formBaseline,
                            formBackfillProgress: manager.formBackfillProgress,
                            heatModel: engine.heat,
                            heatHRModel: engine.heatHR,
                            formShifts: formShifts,
                            formRunCadenceResidual: formRunCadenceResidual,
                            weatherSnapshot: condition?.weather,
                            confirmedRace: confirmedRaceMatch,
                            confirmedRaces: raceDetector.matches.values.filter(\.isConfirmed),
                            raceDetailFn: { [manager] id in manager.detailFromCache(id) },
                            effortIndex: effortIndex,
                            easyPaceLookup: engine.easyPaceLookup,
                            planPhase: matchedPlanWeek()?.phase,
                            recoveryShape: recoveryShape
                        )
                    }
                    // 표시할 상세 지표가 하나도 없으면(걷기 등) 섹션째 숨긴다.
                    // 로딩 중에는 유지 — 칩이 사라졌다 나타나는 깜빡임 방지.
                    if isLoadingDetail || !selectablePanels.isEmpty {
                        detailPanelsHeader
                            .id("panelAnchor")
                        panelChipRow
                        selectedPanelSection
                    }
                    if showRaceBanner {
                        RaceDetectionBanner(
                            suggestion: raceSuggestion,
                            activityID: activity.id,
                            activityDistanceKm: activity.distance / 1000,
                            activityDate: activity.date,
                            onConfirmed: { Task { await recomputeInsightWithRaceMatch() } },
                            onDismissed: {}
                        )
                    } else if isDismissedRace {
                        Button {
                            raceDetector.resetDismissed(activityID: activity.id)
                            Task { await runRaceAssessment() }
                        } label: {
                            Label(AppLanguage.shared.s("대회 기록 추가", "Add Race Record"), systemImage: "flag.checkered")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                    MetricGrid(activity: activity, detail: detail, age: userAge,
                               isMale: manager.userIsMale)
                    if let intervals = detail?.intervalSegments, !intervals.isEmpty {
                        IntervalSegmentsSection(segments: intervals, activity: activity, condition: condition,
                                                firstCoordinate: detail?.routeCoordinates.first)
                    }
                    if let splits = detail?.splits, !splits.isEmpty {
                        SplitsSection(splits: splits, zones: detail?.hrZones ?? [],
                                  activity: activity, allActivities: manager.activities,
                                  condition: condition,
                                  firstCoordinate: detail?.routeCoordinates.first,
                                  runMetrics: RunMetricItem.list(activity: activity, detail: detail,
                                                                 age: userAge, isMale: manager.userIsMale))
                    }
                    let zones = effectiveHRZones
                    if !zones.isEmpty {
                        HRZonesSection(zones: zones)
                    } else if isComputingZones {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text(AppLanguage.shared.s("심박 존 계산 중…", "Computing zones…"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    } else if !manager.hasDOBSource && hrFetchDone {
                        // DOB/수동나이 없어서 존 계산 불가 → 안내
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.caption).foregroundStyle(Theme.violet)
                            Text(AppLanguage.shared.s(
                                "정확한 존 계산을 위해 건강 앱에 생년월일을 입력하거나, '나' 탭에서 나이를 설정해 주세요.",
                                "For accurate HR zones, add your date of birth in the Health app or set your age in the Me tab."))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    Spacer(minLength: 32)
                }
                .padding(.top, 8)
            }
        }
        .onChange(of: manager.manualAge) {
            // 수동 나이 변경 시 존 재계산
            guard !hrSamples.isEmpty else { return }
            Task {
                isComputingZones = true
                let computed = await manager.computeHRZonesForDate(activity.date, samples: hrSamples)
                displayZones = computed
                if !computed.isEmpty { detail?.hrZones = computed }
                isComputingZones = false
            }
        }
        .navigationTitle(activity.type.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showShareCard = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(AppLanguage.shared.s("카드 만들기", "Create Card"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.violet)
                    .clipShape(Capsule())
                }
                .disabled(isLoadingDetail)
            }
        }
        .navigationDestination(isPresented: $showShareCard) {
            ShareCardScreen(activity: activity, detail: detail, insight: insight, manager: manager, condition: condition,
                             summaryLines: shareSummaryLines)
        }
        .sheet(isPresented: $showManualRaceEntry) {
            ManualRaceSheet(
                distanceKm: activity.distance / 1000,
                onSave: { name in
                    raceDetector.addManual(activityID: activity.id, name: name,
                                           distanceKm: activity.distance / 1000, date: activity.date)
                    Task { await recomputeInsightWithRaceMatch() }
                },
                onCancel: {
                    raceDetector.markAsNotRace(activityID: activity.id)
                }
            )
        }
        .sheet(isPresented: $showRouteShareCard) {
            DetailPanelShareCardScreen(
                activity: activity, detail: detail,
                activePanel: .map,
                hrSamples: hrSamples, panelSeriesData: [],
                condition: condition,
                age: userAge, isMale: manager.userIsMale
            )
        }
        .sheet(isPresented: $showChartShare) {
            RunChartShareSheet(
                data: chartData,
                distanceText: activity.formattedDistance,
                durationText: activity.formattedDuration,
                weatherText: activity.weatherBadgeText,
                weatherIcon: condition?.weather?.systemIcon,
                dateText: panelDateText,
                weekdayText: panelWeekdayText,
                startTimeText: panelTimeText,
                shoeText: panelShoeText,
                paceText: activity.formattedPace,
                totalDuration: activity.duration,
                routeCoordinates: detail?.routeCoordinates ?? []
            )
        }
        .onChange(of: activePanel) { _, newPanel in
            if newPanel == .heartRate, !hrFetchDone {
                Task {
                    hrSamples = await manager.fetchHRTimeSeries(for: activity.id)
                    hrFetchDone = true
                    await loadRecovery()
                    // provisional 재조회로 hrSamples가 갱신됐을 수 있음 → displayZones 재계산
                    if displayZones.isEmpty || (detail?.hrZones ?? []).isEmpty {
                        let computed = await manager.computeHRZonesForDate(activity.date, samples: hrSamples)
                        if !computed.isEmpty {
                            displayZones = computed
                            detail?.hrZones = computed
                        }
                    }
                }
            }
            switch newPanel {
            case .combined:
                Task { await loadCombinedChart() }
            case .cadence, .power, .groundContact, .strideLength, .verticalOscillation:
                // synchronous cache hit — no Task, no frame delay
                if let cached = panelSeriesCache[newPanel] {
                    panelSeriesData = cached
                    isLoadingPanelSeries = false
                } else {
                    Task { await loadPanelSeries(for: newPanel) }
                }
            default:
                break
            }
        }
        .onChange(of: panelAllStories.map(\.effortRPE)) { _, _ in
            manager.syncUserEfforts(from: panelAllStories)
        }
        .onChange(of: effortIndex.user[activity.id.uuidString]) { _, _ in
            guard !isLoadingDetail else { return }
            runInsights = []
            loadInsights()
        }
        .task {
            // Release any stale in-flight claim left by a prior cancelled task for this activity
            await InsightCache.shared.releaseRefinedCompute(activity.id)
            // Non-running activities: just fetch detail, no insight computation
            guard activity.type == .running else {
                detail = await manager.fetchDetail(for: activity.id)
                isLoadingDetail = false
                loadInsights()
                Task { await loadCombinedChart() }
                return
            }

            manager.syncUserEfforts(from: panelAllStories)

            let lang = AppLanguage.shared.isEnglish ? "en" : "ko"

            // Check cache first — show immediately if available (insight stays nil → loading state otherwise)
            let cachedInsight = await InsightCache.shared.result(for: activity.id, isRefined: true, language: lang)
            if let c = cachedInsight { insight = c }

            // Fetch detail regardless (route map, splits, hill annotation)
            detail = await manager.fetchDetail(for: activity.id)
            isLoadingDetail = false
            applyDefaultPanelIfNeeded()
            // Apple 강도 재조회 — 로딩 완료를 막지 않도록 분리 실행(뷰 이탈 시 취소)
            effortRefreshTask?.cancel()
            effortRefreshTask = Task {
                let before = appleEffortForRun?.effective
                let e = await manager.refreshEffort(for: activity.id)
                guard !Task.isCancelled else { return }
                if let e { detail?.appleEffort = e }
                if e?.effective != before, !isLoadingDetail {
                    runInsights = []
                    loadInsights()
                }
            }
            loadInsights()
            Task { await loadCombinedChart() }
            // @MainActor 컨텍스트에서 raceDetector 접근 — Task 진입 전에 미리 수집
            // triple criterion: raceDetector || workoutType 캐시 || 버전-무관 영속 키
            let persistedRaceIDs = manager.persistedConfirmedRaceIDs()
            let confirmedRaceIDs: Set<UUID> = Set(
                manager.activities.compactMap { a -> UUID? in
                    let byDetector = raceDetector.matchFor(activityID: a.id)?.isConfirmed == true
                    let byCache    = manager.cachedWorkoutTypeForStats(for: a.id) == .race
                    let byPersist  = persistedRaceIDs.contains(a.id)
                    guard byDetector || byCache || byPersist else { return nil }
                    return a.id
                }
            )
            #if DEBUG
            print("[Baseline:계산] raceDetector 준비 = \(raceDetector.isReady) · 대회 제외 \(confirmedRaceIDs.count)건")
            if !raceDetector.isReady { print("[Baseline:계산] raceDetector 미준비 — 영속 키 \(persistedRaceIDs.count)건으로 대체") }
            #endif
            // 확인된 대회 ID를 workoutType 캐시 + 영속 키에 함께 저장
            manager.markConfirmedRaces(confirmedRaceIDs)
            // 전체 매치 JSON도 영속 저장 — 백테스트 폴백용 (raceDetector 미준비 시)
            let confirmedMatchArray = Array(confirmedRaceIDs).compactMap { raceDetector.matchFor(activityID: $0) }
            manager.updatePersistedRaceMatches(confirmedMatchArray)
            let allFormInputs      = manager.formInputs
            let excludedRaceInputs = allFormInputs.filter { confirmedRaceIDs.contains($0.activityID) }
            let nonRaceInputs      = allFormInputs.filter { !confirmedRaceIDs.contains($0.activityID) }
            #if DEBUG
            // 대회 ID → km 맵: raceDetector 접근은 @MainActor에서만 (task 클로저 진입 전)
            let raceKmByID: [UUID: Double] = confirmedRaceIDs.reduce(into: [:]) { d, id in
                if let m = raceDetector.matchFor(activityID: id) { d[id] = m.distanceKm }
            }
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let excludedDesc = excludedRaceInputs.map { inp -> String in
                let km = raceKmByID[inp.activityID] ?? (manager.activities.first { $0.id == inp.activityID }?.distance ?? 0) / 1000
                let label: String
                if abs(km - 42.195) < 3      { label = "풀코스" }
                else if abs(km - 21.0975) < 2 { label = "하프" }
                else if abs(km - 10) < 1      { label = "10km" }
                else if abs(km - 5) < 0.5     { label = "5km" }
                else                           { label = String(format: "%.1fkm", km) }
                return "\(df.string(from: inp.date))(\(label))"
            }.joined(separator: " · ")
            print("[Baseline:뷰] 대회 제외 \(excludedRaceInputs.count)건 — 판별 기준: raceDetector.isConfirmed||workoutType==.race")
            if !excludedRaceInputs.isEmpty { print("[Baseline:뷰] 대회 제외 목록: \(excludedDesc)") }
            #endif
            Task {
                // 대회(confirmed race)는 baseline 계산에서 제외 — 마라톤 페이스가 느린 구간 왜곡 방지
                let baseline = await FormBaselineEngine.loadOrCompute(inputs: nonRaceInputs,
                                                                       excludedRaceInputs: excludedRaceInputs)
                #if DEBUG
                print("[Baseline:뷰] 결과 bands=\(baseline.bands.count)")
                #endif
                formBaseline = baseline
                let formResult = await computeFormShifts()
                formShifts = formResult.shifts
                formRunCadenceResidual = formResult.runCadenceResidual
            }
            Task {
                isInsightBackfilling = true
                await manager.backfillWorkoutTypesAroundActivity(activity)  // 열람 런 기준 4주 창
                await manager.backfillHRZonesAroundActivity(activity)      // 강도 분포용 존 캐시 보충
                isInsightBackfilling = false
            }
            formBackfillTask = Task {
                let newCount = await manager.backfillFormMetrics()
                guard !Task.isCancelled, newCount > 0 else { return }
                FormBaselineEngine.clearCache()
                let raceIDsForRefresh: Set<UUID> = Set(
                    manager.activities.compactMap { a -> UUID? in
                        let byDetector = raceDetector.matchFor(activityID: a.id)?.isConfirmed == true
                        let byCache    = manager.cachedWorkoutTypeForStats(for: a.id) == .race
                        guard byDetector || byCache else { return nil }
                        return a.id
                    }
                )
                let allFormRefresh      = manager.formInputs
                let excludedRaceRefresh = allFormRefresh.filter { raceIDsForRefresh.contains($0.activityID) }
                let nonRaceRefresh      = allFormRefresh.filter { !raceIDsForRefresh.contains($0.activityID) }
                let refreshed = await FormBaselineEngine.loadOrCompute(inputs: nonRaceRefresh,
                                                                        excludedRaceInputs: excludedRaceRefresh)
                formBaseline = refreshed
                #if DEBUG
                print("[Baseline:재계산] 백필 후 갱신 — 새 항목 \(newCount)건, bands=\(refreshed.bands.count)")
                #endif
            }

            // 존 분포: detail?.hrZones 우선, 없으면 HR 시리즈로 비동기 재계산 → displayZones
            isComputingZones = true
            let detailZones = detail?.hrZones ?? []
            if !detailZones.isEmpty {
                displayZones = detailZones
                isComputingZones = false
            } else {
                // queryHRZones가 실패했거나 v3 캐시 미생성 → HR 시리즈로 직접 계산
                if hrSamples.isEmpty {
                    let earlyHR = await manager.fetchHRTimeSeries(for: activity.id)
                    if !earlyHR.isEmpty {
                        hrSamples = earlyHR; hrFetchDone = true
                        Task { await loadRecovery() }   // hrSamples가 생기는 두 자리 중 하나. 중복은 isLoadingRecovery가 막는다.
                    }
                }
                let computed = await manager.computeHRZonesForDate(activity.date, samples: hrSamples)
                displayZones = computed
                if !computed.isEmpty { detail?.hrZones = computed }
                isComputingZones = false
            }

            hillMatch = HillSpotDetector.shared.assess(
                routeCoords: detail?.routeCoordinates ?? [],
                elevationGain: detail?.elevationGain
            ).first(where: { $0.matched })
            let firstCoord = detail?.routeCoordinates.first

            // Start race detection (always needed for badge UI)
            async let raceFetch: RaceSuggestion? = raceDetector.assess(
                activityID: activity.id,
                date: activity.date,
                distanceKm: activity.distance / 1000,
                startCoord: firstCoord,
                routeCoords: detail?.routeCoordinates ?? []
            )

            if cachedInsight != nil {
                // Fast path: insight cached — fetch condition + race for display, no generation
                let fetchedCondition = await manager.fetchCondition(for: activity, firstCoordinate: firstCoord)
                let suggestion = await raceFetch
                withAnimation(.easeIn(duration: 0.2)) { condition = fetchedCondition }
                if let s = suggestion, s.strength == .strong {
                    raceDetector.confirm(activityID: activity.id, race: s.primary,
                                         activityDistanceKm: activity.distance / 1000)
                } else {
                    withAnimation(.easeIn) { raceSuggestion = suggestion }
                }
                // AI enhancement pass (idempotent — skips if already enhanced)
                if let aiResult = await InsightEngine.tryAIEnhance(cachedInsight!) {
                    await InsightCache.shared.cache(aiResult, for: activity.id, isRefined: true, language: lang)
                    withAnimation(.easeInOut(duration: 0.4)) { insight = aiResult }
                }
                return
            }

            // Slow path: no cache — wait for condition (max 3 s) then generate exactly once
            // insight remains nil during this wait → loading state in UI
            let fetchedCondition: ActivityCondition? = await withTaskGroup(of: ActivityCondition?.self) { group in
                group.addTask { await manager.fetchCondition(for: activity, firstCoordinate: firstCoord) }
                group.addTask {
                    try? await Task.sleep(for: .seconds(3))
                    return nil
                }
                let result = await group.next() ?? nil
                group.cancelAll()
                return result
            }
            let suggestion = await raceFetch
            withAnimation(.easeIn(duration: 0.2)) { condition = fetchedCondition }

            // Confirm strong race before generation so the single compute includes it
            if let s = suggestion, s.strength == .strong {
                raceDetector.confirm(activityID: activity.id, race: s.primary,
                                     activityDistanceKm: activity.distance / 1000)
            } else {
                withAnimation(.easeIn) { raceSuggestion = suggestion }
            }

            // Exactly one generation: guarded by in-flight claim
            guard await InsightCache.shared.claimRefinedCompute(activity.id) else { return }
            let result = await InsightEngine.computeBackground(
                activity: activity,
                history: manager.activities,
                level: level,
                workoutType: detail?.workoutType ?? .general,
                splits: detail?.splits ?? [],
                intervalSegments: detail?.intervalSegments ?? [],
                condition: fetchedCondition,
                raceMatch: raceDetector.matchFor(activityID: activity.id),
                detail: detail,
                historyComplete: manager.isHistoryLoadComplete,
                typeOf: manager.workoutTypeLookup(),
                heatHR: engine.heatHR
            )
            // 엔진이 아직 준비 전이면(engine.isReady == false) heatHR이 항등 모델일 수 있다 —
            // 화면엔 보여주되 디스크 캐시에는 굳히지 않는다. 준비되면 아래 onChange(of: engine.isReady)가 다시 계산한다.
            await InsightCache.shared.cache(result, for: activity.id, isRefined: true, language: lang, persist: engine.isReady)
            await InsightCache.shared.releaseRefinedCompute(activity.id)
            withAnimation(.easeInOut(duration: 0.3)) { insight = result }

            // AI rewrite (idempotent — skips if aiEnhanced == true)
            if let aiResult = await InsightEngine.tryAIEnhance(result) {
                await InsightCache.shared.cache(aiResult, for: activity.id, isRefined: true, language: lang, persist: engine.isReady)
                withAnimation(.easeInOut(duration: 0.4)) { insight = aiResult }
            }
        }
        .onChange(of: engine.isReady) { wasReady, nowReady in
            // 엔진이 방금 준비됐다면(false→true) 그 전에 계산해 화면에 걸어둔 인사이트는
            // 항등 열지수 모델로 계산됐을 수 있다 — 실제 heatHR로 다시 계산해 교체한다.
            guard !wasReady, nowReady, activity.type == .running, insight != nil else { return }
            Task {
                let lang = AppLanguage.shared.isEnglish ? "en" : "ko"
                await InsightCache.shared.invalidate(activity.id)
                let result = await InsightEngine.computeBackground(
                    activity: activity, history: manager.activities, level: level,
                    workoutType: detail?.workoutType ?? .general,
                    splits: detail?.splits ?? [],
                    intervalSegments: detail?.intervalSegments ?? [],
                    condition: condition,
                    raceMatch: raceDetector.matchFor(activityID: activity.id),
                    detail: detail,
                    historyComplete: manager.isHistoryLoadComplete,
                    typeOf: manager.workoutTypeLookup(),
                    heatHR: engine.heatHR
                )
                await InsightCache.shared.cache(result, for: activity.id, isRefined: true, language: lang, persist: engine.isReady)
                withAnimation(.easeInOut(duration: 0.3)) { insight = result }
                if let aiResult = await InsightEngine.tryAIEnhance(result) {
                    await InsightCache.shared.cache(aiResult, for: activity.id, isRefined: true, language: lang, persist: engine.isReady)
                    withAnimation(.easeInOut(duration: 0.4)) { insight = aiResult }
                }
            }
        }
        .onChange(of: AppLanguage.shared.isEnglish) { _, _ in
            Task {
                let lang = AppLanguage.shared.isEnglish ? "en" : "ko"
                if let cached = await InsightCache.shared.result(for: activity.id, isRefined: true, language: lang) {
                    withAnimation { insight = cached }
                } else if activity.type == .running {
                    let result = await InsightEngine.computeBackground(
                        activity: activity, history: manager.activities, level: level,
                        workoutType: detail?.workoutType ?? .general,
                        splits: detail?.splits ?? [],
                        intervalSegments: detail?.intervalSegments ?? [],
                        condition: condition,
                        raceMatch: raceDetector.matchFor(activityID: activity.id),
                        detail: detail,
                        historyComplete: manager.isHistoryLoadComplete,
                        typeOf: manager.workoutTypeLookup(),
                        heatHR: engine.heatHR
                    )
                    await InsightCache.shared.cache(result, for: activity.id, isRefined: true, language: lang, persist: engine.isReady)
                    withAnimation { insight = result }
                }
                runInsights = []
                loadInsights()
            }
        }
        .onChange(of: panelScrollTrigger) {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo("panelAnchor", anchor: .top)
            }
        }
        }   // ScrollViewReader
    }

    private var userAge: Int? {
        guard let dob = manager.userDateOfBirth, let year = dob.year else { return nil }
        return Calendar.current.component(.year, from: Date()) - year
    }

    private func recomputeInsightWithRaceMatch() async {
        let lang = AppLanguage.shared.isEnglish ? "en" : "ko"
        await InsightCache.shared.invalidate(activity.id)
        let match = raceDetector.matchFor(activityID: activity.id)
        let recomputed = await InsightEngine.computeBackground(
            activity: activity,
            history: manager.activities,
            level: level,
            workoutType: detail?.workoutType ?? .general,
            splits: detail?.splits ?? [],
            intervalSegments: detail?.intervalSegments ?? [],
            condition: condition,
            raceMatch: match,
            detail: detail,
            historyComplete: manager.isHistoryLoadComplete,
            typeOf: manager.workoutTypeLookup(),
            heatHR: engine.heatHR
        )
        let isRefined = detail != nil
        await InsightCache.shared.cache(recomputed, for: activity.id, isRefined: isRefined, language: lang, persist: engine.isReady)
        withAnimation(.easeInOut(duration: 0.3)) { insight = recomputed }
    }

    private func runRaceAssessment() async {
        let routeCoords = detail?.routeCoordinates ?? []
        let suggestion = await raceDetector.assess(
            activityID: activity.id,
            date: activity.date,
            distanceKm: activity.distance / 1000,
            startCoord: routeCoords.first,
            routeCoords: routeCoords
        )
        if let s = suggestion, s.strength == .strong {
            raceDetector.confirm(activityID: activity.id, race: s.primary,
                                 activityDistanceKm: activity.distance / 1000)
            await recomputeInsightWithRaceMatch()
        } else {
            withAnimation(.easeIn) { raceSuggestion = suggestion }
        }
    }

    private func currentValue(for metric: TrendMetric) -> Double? {
        guard let det = detail else { return nil }
        switch metric {
        case .cadence:             return det.avgCadence.map { Double($0) }
        case .power:               return det.avgPower.map { Double($0) }
        case .groundContactTime:   return det.avgGroundContactTime
        case .strideLength:        return det.avgStrideLength
        case .verticalOscillation: return det.avgVerticalOscillation
        case .vo2Max:              return det.vo2Max
        case .hrRecovery1:         return recoveryResult?.hrr1
        case .easyEffortPace:      return nil
        case .bodyMass, .bodyFatPercentage: return nil
        }
    }

    private func loadPanelSeries(for panel: DetailPanel) async {
        panelSeriesData = []
        isLoadingPanelSeries = true
        let fetched: [(offset: TimeInterval, value: Double)]
        switch panel {
        case .cadence:
            fetched = await manager.fetchCadenceTimeSeries(for: activity.id)
        case .power:
            fetched = await manager.fetchWorkoutTimeSeries(for: activity.id,
                                                           identifier: .runningPower, unit: .watt())
        case .groundContact:
            fetched = await manager.fetchWorkoutTimeSeries(for: activity.id,
                                                           identifier: .runningGroundContactTime,
                                                           unit: .secondUnit(with: .milli))
        case .strideLength:
            fetched = await manager.fetchWorkoutTimeSeries(for: activity.id,
                                                           identifier: .runningStrideLength, unit: .meter())
        case .verticalOscillation:
            fetched = await manager.fetchWorkoutTimeSeries(for: activity.id,
                                                           identifier: .runningVerticalOscillation,
                                                           unit: .meterUnit(with: .centi))
        default:
            fetched = []
        }
        panelSeriesCache[panel] = fetched
        // discard result if user already switched to another panel
        guard activePanel == panel else { return }
        panelSeriesData = fetched
        isLoadingPanelSeries = false
    }

    private func loadSeriesIntoCache(_ panel: DetailPanel) async {
        let fetched: [(offset: TimeInterval, value: Double)]
        switch panel {
        case .cadence:
            fetched = await manager.fetchCadenceTimeSeries(for: activity.id)
        case .power:
            fetched = await manager.fetchWorkoutTimeSeries(for: activity.id, identifier: .runningPower, unit: .watt())
        case .groundContact:
            fetched = await manager.fetchWorkoutTimeSeries(for: activity.id,
                                                           identifier: .runningGroundContactTime,
                                                           unit: .secondUnit(with: .milli))
        case .strideLength:
            fetched = await manager.fetchWorkoutTimeSeries(for: activity.id,
                                                           identifier: .runningStrideLength, unit: .meter())
        case .verticalOscillation:
            fetched = await manager.fetchWorkoutTimeSeries(for: activity.id,
                                                           identifier: .runningVerticalOscillation,
                                                           unit: HKUnit.meterUnit(with: .centi))
        default:
            return
        }
        if !fetched.isEmpty { panelSeriesCache[panel] = fetched }
    }

    /// 이 러닝이 속한 주의 대회 플랜 주차 — 주간 목표 km(기존)과 플랜 단계(총평 훈련부하 줄)가 함께 쓴다.
    /// 계획이 둘 이상 겹치는 주는 MRPlanGovernance 규칙(대회일이 가장 이른 계획, 그 대회 주까지)으로 하나만 고른다.
    private func matchedPlanWeek() -> MRPlanWeek? { governingPlan()?.week }

    /// 이 러닝이 속한 주를 다스리는 (계획, 주차). 스냅샷이 있으면 주차표와 같은 숫자.
    private func governingPlan() -> (plan: MRRacePlan, week: MRPlanWeek)? {
        engine.governingPlanWeek(for: activity.date)
    }

    /// 계획이 둘 이상일 때만 필(pill)에 붙는 라벨("10K 계획") — 한 계획뿐이면 nil (문구 변화 없음).
    private func governingPlanLabel() -> String? {
        guard engine.plans.count > 1, let g = governingPlan() else { return nil }
        return mrLabelFor(distanceM: g.plan.distanceM)
    }

    private func loadInsights() {
        guard runInsights.isEmpty else { return }

        // 이 러닝이 속한 주의 계획 목표 km 검색
        let governing = governingPlan()
        let planWeeklyTargetKm: Double? = governing?.week.weeklyKm
        let planLabel: String? = governingPlanLabel()
        #if DEBUG
        do {
            let mon = MRPlanGovernance.weekMonday(of: activity.date)
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let rows = engine.plans.map { pl -> String in
                let wk = pl.weeks.first { Calendar.current.startOfDay(for: $0.monday) == mon }
                let km = wk.map { String(format: "%.1f", $0.weeklyKm) } ?? "nil"
                return "\(mrLabelFor(distanceM: pl.distanceM)) \(f.string(from: pl.raceDate)) → \(km)"
            }
            let chosen = governing.map { "\(mrLabelFor(distanceM: $0.plan.distanceM)) \(String(format: "%.1f", $0.week.weeklyKm))km" } ?? "없음"
            print("[주간목표] \(f.string(from: mon)) 주 · 계획별 주간km: [\(rows.joined(separator: " · "))] → 다스리는 계획: \(chosen)")
        }
        #endif

        // 최근 8주 같은 유형 기준선 — body 평가 대신 여기서 1회 계산
        let effortBaseline: Int? = {
            guard activity.type == .running else { return nil }
            let samples = EffortBaseline.samples(current: activity, history: manager.activities,
                                                 index: effortIndex, typeOf: manager.workoutTypeLookup())
            return EffortBaseline.median(for: detail?.workoutType ?? .general, samples: samples)
        }()

        let result = RunInsightEngine.insights(
            for: activity,
            detail: detail,
            history: manager.activities,
            age: userAge,
            isMale: manager.userIsMale,
            restingHR: manager.restingHeartRate,
            hrSamples: hrSamples,
            hrMax: engine.phys.hrMax?.value,
            lt1HR: engine.phys.lt1HR?.value,
            lt1SD: engine.phys.lt1SD,
            easyCeilingHR: engine.phys.easyCeilingHR,
            heat: engine.heat,
            heatHR: engine.heatHR,
            planWeeklyTargetKm: planWeeklyTargetKm,
            planLabel: planLabel,
            effort: activity.type == .running ? resolvedEffort : nil,
            effortBaseline: effortBaseline
        )
        runInsights = result.insights
        runSegmentSource = result.segmentSource
        runFadeStartKm = result.fadeStartKm
    }

    /// 폼 추세(케이던스·GCT)와 함께 **이 러닝**의 케이던스 잔차를 돌려준다 — 추세 문단 마무리 문장용.
    private func computeFormShifts() async -> (shifts: [MRFormShift], runCadenceResidual: Double?) {
        guard !engine.runs.isEmpty else { return ([], nil) }
        // 열람 중인 러닝 기준 직전 1년 데이터만 가져온다 — 4년 전 러닝도 그 시점 폼을 본다
        let asOf = activity.date
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: asOf) ?? .distantPast
        // vo는 추세 판정에서 제외 — Apple Watch 측정 오차 MAPE 19%로 신뢰도 낮음
        async let cadFetch = manager.fetchMetricHistory(.cadence, from: oneYearAgo)
        async let gctFetch = manager.fetchMetricHistory(.groundContactTime, from: oneYearAgo)
        let (cadData, gctData) = await (cadFetch, gctFetch)

        let cal = Calendar.current
        let speedByDate = mrFormSpeedByDate(engine.runs)
        let now = asOf

        func buildObs(_ pts: [(date: Date, value: Double)]) -> [MRFormObs] {
            pts.compactMap { pt in
                let day = cal.startOfDay(for: pt.date)
                guard let speed = speedByDate[day] else { return nil }
                return MRFormObs(date: day, speedMPerMin: speed, metricValue: pt.value)
            }
        }

        var shifts: [MRFormShift] = []
        var runCadenceResidual: Double? = nil
        for (metric, obs) in [(mrFormMetrics[1], buildObs(cadData)),
                               (mrFormMetrics[2], buildObs(gctData))] {
            let residuals = mrFormResiduals(obs: obs, asOf: now)
            if metric.key == "cadence" {
                runCadenceResidual = mrFormRunResidual(residuals, on: activity.date)
                #if DEBUG
                if let r = runCadenceResidual {
                    print(String(format: "[폼:잔차] 이 러닝 케이던스 잔차 %+.1fspm (관측 %d개)", r, residuals.count))
                } else {
                    print("[폼:잔차] 이 러닝 케이던스 잔차 없음 (당일 관측 없음 또는 잔차 미계산, 관측 \(residuals.count)개)")
                }
                #endif
            }
            if let shift = mrFormShift(residuals, metric: metric, asOf: now, obs: obs) {
                shifts.append(shift)
            }
        }
        return (shifts, runCadenceResidual)
    }

    private func loadCombinedChart() async {
        guard chartData.availableLayers.isEmpty, !isLoadingChart else { return }
        isLoadingChart = true
        defer { isLoadingChart = false }

        async let hr     = manager.fetchHRTimeSeries(for: activity.id)
        async let cad    = manager.fetchCadenceTimeSeries(for: activity.id)
        async let pow    = manager.fetchWorkoutTimeSeries(for: activity.id,
                                                          identifier: .runningPower,
                                                          unit: .watt())
        async let stride = manager.fetchWorkoutTimeSeries(for: activity.id,
                                                          identifier: .runningStrideLength,
                                                          unit: .meter())
        async let vosc   = manager.fetchWorkoutTimeSeries(for: activity.id,
                                                          identifier: .runningVerticalOscillation,
                                                          unit: HKUnit.meterUnit(with: .centi))
        async let gct    = manager.fetchWorkoutTimeSeries(for: activity.id,
                                                          identifier: .runningGroundContactTime,
                                                          unit: HKUnit.secondUnit(with: .milli))
        let (h, c, p, s, v, g) = await (hr, cad, pow, stride, vosc, gct)
        // 패널 탭 전환 시 재조회 방지 — 이미 가져온 시리즈를 패널 캐시에 등록
        if !h.isEmpty {
            hrSamples = h; hrFetchDone = true
            // HR 시리즈가 실제로 들어온 자리에서 회복을 부른다. 심박 패널 탭의 호출은
            // 여기서 hrFetchDone이 먼저 켜져 영영 닿지 않았다 — 회복 한 줄도 HRRecoveryPanelChart도 죽어 있었다.
            Task { await loadRecovery() }
        }
        if !c.isEmpty { panelSeriesCache[.cadence] = c }
        if !p.isEmpty { panelSeriesCache[.power] = p }
        if !s.isEmpty { panelSeriesCache[.strideLength] = s }
        if !v.isEmpty { panelSeriesCache[.verticalOscillation] = v }
        if !g.isEmpty { panelSeriesCache[.groundContact] = g }
        chartData = RunChartBuilder.build(
            activity: activity,
            detail: detail,
            hrSamples: h,
            cadenceSamples: c,
            powerSamples: p,
            strideSamples: s,
            vertOscSamples: v,
            gctSamples: g,
            fadeStartKm: runFadeStartKm
        )
    }

    // MARK: - Panel availability

    private func isAvailable(_ panel: DetailPanel) -> Bool {
        guard !isLoadingDetail else { return false }
        switch panel {
        case .combined:             return true
        case .map:                  return !(detail?.routeCoordinates ?? []).isEmpty
        case .heartRate:            return activity.avgHeartRate != nil
        case .cadence:              return detail?.avgCadence != nil
        case .groundContact:        return detail?.avgGroundContactTime != nil
        case .strideLength:         return detail?.avgStrideLength != nil
        case .power:                return detail?.avgPower != nil
        case .verticalOscillation:  return detail?.avgVerticalOscillation != nil
        case .elevation:            return !(detail?.altitudeProfile ?? []).isEmpty
        }
    }

    /// 상세 데이터 기본 표시는 경로. 야외 경로가 없는 기록(실내런 등)은 선택 없음으로 둔다.
    private func applyDefaultPanelIfNeeded() {
        guard !didApplyDefaultPanel else { return }
        didApplyDefaultPanel = true
        guard isAvailable(.map) else { return }
        activePanel = .map
    }

    /// 칩으로 고를 수 있는 패널 — 종합(고정 표시) 제외, 데이터 있는 것만
    private var selectablePanels: [DetailPanel] {
        DetailPanel.allCases.filter { $0 != .combined && isAvailable($0) }
    }

    // MARK: - Panel section (replaces mapSection)

    private var loadingPanelPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Theme.cardBackground)
            .frame(height: 220)
            .overlay { ProgressView().tint(Theme.violet) }
            .padding(.horizontal, 16)
    }

    /// 종합 차트 — 칩 선택과 무관하게 **항상** 표시한다.
    @ViewBuilder
    private var combinedPanelSection: some View {
        if isLoadingDetail {
            loadingPanelPlaceholder
        } else {
            combinedPanelContent
        }
    }

    /// 칩으로 고른 상세 패널. `activePanel == .combined` 은 "선택 없음"을 뜻하며 아무것도 그리지 않는다.
    @ViewBuilder
    private var selectedPanelSection: some View {
        if activePanel != .combined {
            Group {
                if isLoadingDetail {
                    loadingPanelPlaceholder
                } else if activePanel == .map {
                    if let coords = detail?.routeCoordinates, !coords.isEmpty {
                        RouteMapView(
                            coordinates: coords,
                            activityID: activity.id,
                            activityDate: activity.date,
                            manager: manager,
                            routeTimeOffsets: detail?.routeTimeOffsets ?? [],
                            workoutDuration: activity.duration,
                            hasHRData: activity.avgHeartRate != nil,
                            showHRZones: $mapHRZoneMode
                        )
                    } else {
                        panelPlaceholder(icon: "map.fill", message: AppLanguage.shared.s("경로 없음", "No Route"))
                    }
                } else {
                    ZStack {
                        Theme.cardBackground
                        panelInnerContent
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(height: panelContentHeight)
                    .padding(.horizontal, 16)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: activePanel)
        }
    }

    private var panelContentHeight: CGFloat { 220 }

    @ViewBuilder
    private var panelInnerContent: some View {
        switch activePanel {
        case .map:
            EmptyView()
        case .combined:
            EmptyView()   // 종합은 combinedPanelContent로 상단에 고정 표시
        case .heartRate:
            if !hrFetchDone {
                ProgressView().tint(Theme.violet)
            } else {
                let minExpected = max(Int(activity.duration / 60), 1)
                if hrSamples.count >= minExpected {
                    VStack(spacing: 10) {
                        HRSeriesPanelChart(samples: hrSamples, zones: effectiveHRZones, workoutDuration: activity.duration)
                        if let r = recoveryResult {
                            HRRecoveryPanelChart(points: postHR, result: r)
                        }
                    }
                } else {
                    hrSeriesSparseView
                }
            }
        case .elevation:
            if let profile = detail?.altitudeProfile, !profile.isEmpty {
                ElevationPanelChart(profile: profile)
            } else {
                panelPlaceholder(icon: "mountain.2.fill", message: AppLanguage.shared.s("고도 데이터 없음", "No Elevation Data"))
            }
        case .cadence:
            seriesPanel(icon: "figure.run", label: AppLanguage.shared.s("케이던스", "Cadence"), unit: "spm",
                        color: Theme.cadence, format: "%.0f", useRangeBar: false,
                        validMin: 130,
                        overrideAvg: detail?.avgCadence.map { Double($0) },
                        available: detail?.avgCadence != nil)
        case .power:
            seriesPanel(icon: "bolt.fill", label: AppLanguage.shared.s("파워", "Power"), unit: "W",
                        color: Theme.power, format: "%.0f", useRangeBar: true,
                        available: detail?.avgPower != nil)
        case .groundContact:
            seriesPanel(icon: "stopwatch", label: AppLanguage.shared.s("지면접촉", "Gnd Contact"), unit: "ms",
                        color: Theme.runningForm, format: "%.0f", useRangeBar: true,
                        available: detail?.avgGroundContactTime != nil)
        case .strideLength:
            seriesPanel(icon: "arrow.left.and.right", label: AppLanguage.shared.s("보폭", "Stride"), unit: "m",
                        color: Theme.runningForm, format: "%.2f", useRangeBar: true,
                        available: detail?.avgStrideLength != nil)
        case .verticalOscillation:
            seriesPanel(icon: "arrow.up.and.down", label: AppLanguage.shared.s("수직 진폭", "Vert. Osc."), unit: "cm",
                        color: Theme.runningForm, format: "%.1f", useRangeBar: true,
                        available: detail?.avgVerticalOscillation != nil)
        }
    }

    @ViewBuilder
    private var combinedPanelContent: some View {
        if isLoadingChart && chartData.availableLayers.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 190)
        } else {
            RunCombinedPanelView(
                data: chartData,
                distanceText: activity.formattedDistance,
                durationText: activity.formattedDuration,
                weatherText: activity.weatherBadgeText,
                weatherIcon: condition?.weather?.systemIcon,
                dateText: panelDateText,
                weekdayText: panelWeekdayText,
                startTimeText: panelTimeText,
                shoeText: panelShoeText,
                paceText: activity.formattedPace
            )
        }
    }

    private func panelPlaceholder(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var hrSeriesSparseView: some View {
        let L = AppLanguage.shared
        VStack(spacing: 12) {
            if let avg = activity.avgHeartRate {
                Text("\(avg)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.heartRate)
                + Text(" bpm")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.heartRate.opacity(0.7))
            }
            Text(L.s("이 운동의 상세 심박 기록이 없어요",
                     "No detailed HR data for this workout"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func seriesPanel(icon: String, label: String, unit: String,
                             color: Color, format: String, useRangeBar: Bool = false,
                             validMin: Double = 0, overrideAvg: Double? = nil,
                             available: Bool) -> some View {
        if !available {
            panelPlaceholder(icon: icon, message: AppLanguage.shared.s("\(label) 없음", "No \(label)"))
        } else if isLoadingPanelSeries {
            ProgressView().tint(color)
        } else if panelSeriesData.isEmpty {
            panelPlaceholder(icon: "chart.xyaxis.line", message: AppLanguage.shared.s("데이터 없음", "No Data"))
        } else {
            MetricBarPanelChart(samples: panelSeriesData, color: color,
                                unit: unit, format: format, useRangeBar: useRangeBar,
                                validMin: validMin, overrideAvg: overrideAvg)
        }
    }

    // MARK: - Panel chip row (below MetricGrid)

    private var panelChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 종합은 상단에 고정 표시하므로 칩에서 제외한다
                ForEach(DetailPanel.allCases.filter { $0 != .combined }, id: \.self) { panel in
                    let available = isAvailable(panel)
                    let selected  = activePanel == panel
                    Button {
                        guard available else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            // 같은 칩을 다시 누르면 닫는다 (.combined = 선택 없음)
                            activePanel = selected ? .combined : panel
                        }
                        panelScrollTrigger += 1
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: panel.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(panel.label)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(
                            selected ? .white
                            : available ? Color.white.opacity(0.70)
                            : Color.white.opacity(0.25)
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selected ? Theme.violet
                            : Color.white.opacity(available ? 0.08 : 0.04)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    /// 종합 차트 헤더 — 종합은 고정 표시라 칩과 무관하게 항상 이 이름·버튼이다.
    private var combinedShareHeader: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: DetailPanel.combined.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.violet)
                Text(DetailPanel.combined.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            exportChip(title: AppLanguage.shared.s("차트 내보내기", "Export Chart")) {
                showChartShare = true
            }
        }
        .padding(.horizontal, 16)
    }

    /// 상세 지표 섹션 헤더 — 칩 줄 위 제목 + 경로 내보내기.
    /// 경로 외 지표는 여기서 내보내지 않는다 — 심박·케이던스·폼은 인사이트 카드에,
    /// 구간은 구간 기록에, 인터벌은 인터벌 섹션에 각자 내보내기가 있다.
    private var detailPanelsHeader: some View {
        HStack {
            Text(AppLanguage.shared.s("오늘의 러닝 상세 데이터", "Today's Run Details"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            if isAvailable(.map) {
                exportChip(title: AppLanguage.shared.s("경로 내보내기", "Export Route")) {
                    showRouteShareCard = true
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func exportChip(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up.on.square")
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .foregroundStyle(Theme.violet)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.violet.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header

private struct DetailHeader: View {
    let activity: Activity
    var confirmedRace: PersistedRaceMatch? = nil
    var onRaceRevoke: (() -> Void)? = nil

    private var dateText: Text {
        let df = DateFormatter()
        df.locale = Locale(identifier: AppLanguage.shared.s("ko_KR", "en_US"))
        if AppLanguage.shared.isEnglish {
            df.dateFormat = "EEEE"
            let weekday = df.string(from: activity.date)
            df.dateFormat = ", MMMM d, yyyy  h:mm a"
            let rest = df.string(from: activity.date)
            return Text(weekday).foregroundStyle(Theme.time) + Text(rest)
        } else {
            df.dateFormat = "yyyy년 M월 d일"
            let datePart = df.string(from: activity.date)
            df.dateFormat = " EEEE"
            let weekday = df.string(from: activity.date)
            df.dateFormat = "  a h:mm"
            let timePart = df.string(from: activity.date)
            return Text(datePart) + Text(weekday).foregroundStyle(Theme.time) + Text(timePart)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: activity.type.icon)
                    .font(.title2)
                    .foregroundStyle(Color(hex: "3DFF7A"))
                    .frame(width: 44, height: 44)
                    .background(Color(hex: "3DFF7A").opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.type.label)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    dateText
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            if let race = confirmedRace {
                HStack(spacing: 8) {
                    Label(race.raceName, systemImage: "flag.checkered")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.violet)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.violet.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.violet.opacity(0.35), lineWidth: 1))
                    if let revoke = onRaceRevoke {
                        Button(AppLanguage.shared.s("이 대회 아니에요", "Not a Race"), action: revoke)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Insight placeholder card

private struct InsightCard: View {
    let activity: Activity
    let insight: InsightResult?
    var condition: ActivityCondition? = nil
    var confirmedRace: PersistedRaceMatch? = nil
    var hillMatch: HillMatch? = nil
    var effortValue: Int? = nil

    private var displayDetail: String {
        guard let ins = insight else { return AppLanguage.shared.s("인사이트 분석 준비 중", "Analyzing…") }
        if ins.theme == .adverseCondition, let e = effortValue {
            return ins.detail + AppLanguage.shared.s(" · 체감 강도 \(e)", " · effort \(e)/10")
        }
        return ins.detail
    }

    @Environment(CustomMiniMeStore.self) private var miniMeStore
    @Query private var allStories: [WorkoutStory]

    private var storyPhoto: UIImage? {
        allStories.first { $0.workoutID == activity.id.uuidString }?.allPhotoImages.first
    }

    private var statsLine: String {
        var parts = [activity.formattedDistance, activity.formattedDuration]
        if let pace = activity.formattedPace { parts.insert(pace, at: 1) }
        return parts.joined(separator: " · ")
    }

    private var miniMeVariant: MiniMeVariant {
        guard let insight else { return .running }
        return MiniMeVariant.from(theme: insight.theme, workoutType: insight.workoutType)
    }

    // ── 컨디션 행: 날씨 칩 + 수면 칩(등급) + 러닝 의견 ──
    @ViewBuilder
    private var conditionRow: some View {
        if let cond = condition, cond.weather != nil || cond.sleepScore != nil {
            HStack(alignment: .center, spacing: 6) {
                if let w = cond.weather {
                    // ⚠ 숫자·색상 모두 HK 메타데이터(activity.temperatureC)로 통일.
                    //   condition?.weather는 외부 API라 값이 다를 수 있다 — 아이콘만 차용.
                    let hkTemp = activity.temperatureC
                    let wColor: Color = {
                        if w.isRainy            { return Theme.pace }
                        if (hkTemp ?? 0) >= 28  { return Theme.calories }
                        if (hkTemp ?? 99) <= 2  { return .blue }
                        return .secondary
                    }()
                    let tempLabel = hkTemp.map { String(format: "%.0f°C", $0) } ?? w.formattedTemp
                    ConditionChip(icon: w.systemIcon, label: tempLabel, color: wColor)
                }
                if let slp = cond.sleepScore {
                    // 등급 라벨 칩 (숫자 없음 — Apple Health 스타일)
                    ConditionChip(
                        icon: "bed.double.fill",
                        label: AppLanguage.shared.s(
                            "수면 \(slp.chipLabel)",
                            "Sleep \(slp.chipLabel)"
                        ),
                        color: slp.isInsufficient ? Theme.time : .secondary
                    )
                    // 등급별 러닝 의견
                    Text(slp.grade.runningComment)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── Top row: insight text (left) + MiniMe (right) ──
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(AppLanguage.shared.s("오늘의 인사이트", "Today's Insight"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.violet)
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(Theme.violet)
                    }
                    Text(insight?.title ?? AppLanguage.shared.s("오늘의 러닝", "Today's Run"))
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                    Text(displayDetail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .contentTransition(.opacity)
                    if let race = confirmedRace {
                        Label(AppLanguage.shared.s("대회 러닝 · \(race.raceName)", "Race · \(race.raceName)"), systemImage: "flag.checkered")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.violet.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.violet.opacity(0.3), lineWidth: 1))
                    }
                    if let hill = hillMatch {
                        Label(AppLanguage.shared.s("\(hill.spot.name) · 언덕", "\(hill.spot.name) · Hill"),
                              systemImage: "mountain.2.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "FFC74D"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(hex: "FFC74D").opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(hex: "FFC74D").opacity(0.3), lineWidth: 1))
                    }
                }

                // MiniMe — contextual overlays + animations once insight is loaded
                if insight != nil {
                    ContextualMiniMeView(
                        customImage: miniMeStore.image,
                        variant: miniMeVariant,
                        size: 58
                    )
                    .padding(.top, 2)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }

            // ── Condition row (weather chip + sleep/recovery line) ──
            conditionRow
            HStack(spacing: 4) {
                Text(activity.formattedDistance)
                    .foregroundStyle(Theme.violet)
                if let pace = activity.formattedPace {
                    Text("·").foregroundStyle(.tertiary)
                    Text(pace).foregroundStyle(Theme.pace)
                }
                Text("·").foregroundStyle(.tertiary)
                Text(activity.formattedDuration).foregroundStyle(Theme.time)
                if let hr = activity.avgHeartRate {
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(hr)bpm").foregroundStyle(Theme.heartRate)
                }
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.violet.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - MiniMe update from story photo (iOS 18.2+)

#if canImport(ImagePlayground)
@available(iOS 18.2, *)
private struct MiniMeUpdateButton: View {
    let storyPhoto: UIImage

    @Environment(CustomMiniMeStore.self) private var miniMeStore
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @State private var showPlayground = false

    var body: some View {
        if supportsImagePlayground {
            Button {
                showPlayground = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: miniMeStore.image == nil ? "sparkles" : "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text(miniMeStore.image == nil
                         ? AppLanguage.shared.s("이 사진으로 미니미 만들기", "Create Mini-Me from photo")
                         : AppLanguage.shared.s("이 사진으로 미니미 업데이트", "Update Mini-Me from photo"))
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(Theme.violet)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.violet.opacity(0.10))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .imagePlaygroundSheet(
                isPresented: $showPlayground,
                concepts: [.text("러너, 귀여운 캐릭터, 바이올렛 색깔, 만화체, 밝고 귀여운 스타일")],
                sourceImage: Image(uiImage: storyPhoto)
            ) { url in
                if let data = try? Data(contentsOf: url),
                   let img = UIImage(data: data) {
                    miniMeStore.save(img)
                }
                showPlayground = false
            }
        }
    }
}
#endif

// MARK: - Condition chip

private struct ConditionChip: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(label).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Route map

// MARK: - Route markers (지도 스냅샷 공용)

/// 경로 지도 위 마커 — 시작(흰 링) · km(흰 알약 라벨) · 도착(골드).
/// ⚠ 활동 상세 지도(기본·심박존)와 경로 공유 카드가 **이 타입 하나만** 쓴다.
/// 마커를 새로 그리는 코드를 따로 만들면 화면과 공유 결과가 갈라진다.
enum RouteMarkers {
    // MARK: - Kilometer markers

    /// 경로 누적 거리(m).
    static func totalRouteMeters(_ coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count > 1 else { return 0 }
        var total = 0.0
        var prev = CLLocation(latitude: coords[0].latitude, longitude: coords[0].longitude)
        for c in coords.dropFirst() {
            let cur = CLLocation(latitude: c.latitude, longitude: c.longitude)
            let d = cur.distance(from: prev)
            if d.isFinite { total += d }
            prev = cur
        }
        return total
    }

    /// 누적 거리가 간격의 배수를 넘는 지점의 좌표 = 그 km 지점.
    /// 도착점과 겹치는 마지막 마커는 뺀다(경로 영상 computeKmMarkers와 같은 규칙).
    static func kilometerMarks(_ coords: [CLLocationCoordinate2D], stepKm: Double, totalMeters: Double)
        -> [(km: Int, coord: CLLocationCoordinate2D, index: Int)] {
        guard coords.count > 1, stepKm > 0 else { return [] }
        let stepM = stepKm * 1000
        var result: [(km: Int, coord: CLLocationCoordinate2D, index: Int)] = []
        var accum = 0.0
        var next = stepM
        var prev = CLLocation(latitude: coords[0].latitude, longitude: coords[0].longitude)
        for (i, c) in coords.enumerated().dropFirst() {
            let cur = CLLocation(latitude: c.latitude, longitude: c.longitude)
            let d = cur.distance(from: prev)
            prev = cur
            guard d.isFinite else { continue }
            accum += d
            while accum >= next {
                if next < totalMeters - stepM * 0.5 {
                    result.append((km: Int((next / 1000).rounded()), coord: c, index: i))
                }
                next += stepM
            }
        }
        return result
    }

    /// 시작점 마커 — 경로 영상과 같은 형식(속 빈 흰 링).
    /// 영상은 CALayer 테두리(안쪽으로 그려짐)라 바깥 지름이 10 — 여기선 stroke가 경로 중심
    /// 기준이므로 반지름을 lineWidth 절반만큼 줄여 바깥 지름을 맞춘다.
    static func drawStartMarker(at point: CGPoint) {
        let lineWidth: CGFloat = 1.5
        let ringR: CGFloat = 5 - lineWidth / 2
        let ring = UIBezierPath(ovalIn: CGRect(x: point.x - ringR, y: point.y - ringR,
                                               width: ringR * 2, height: ringR * 2))
        ring.lineWidth = lineWidth
        UIColor.white.setStroke()
        ring.stroke()
    }

    /// 도착점 마커 — 경로 영상과 같은 형식(골드 글로우 + 골드 점).
    /// 지도 스냅샷 두 종류(기본·심박존)가 이 함수 하나만 쓴다.
    static func drawFinishMarker(at point: CGPoint) {
        let gold = UIColor(Color(hex: "FFC74D"))
        let glowR: CGFloat = 9
        gold.withAlphaComponent(0.40).setFill()
        UIBezierPath(ovalIn: CGRect(x: point.x - glowR, y: point.y - glowR,
                                    width: glowR * 2, height: glowR * 2)).fill()
        let dotR: CGFloat = 5
        gold.setFill()
        UIBezierPath(ovalIn: CGRect(x: point.x - dotR, y: point.y - dotR,
                                    width: dotR * 2, height: dotR * 2)).fill()
    }

    /// 경로 위 km 지점 라벨. 애플 피트니스처럼 **점 없이 라벨만** 경로 위에 얹는다.
    /// 라벨 이미지는 `makeKmMarkerLabelImage`(경로 영상과 공용) — 지도는 흰 알약·검정 글씨에
    /// 기준 크기의 0.65배. 220pt 지도에서는 영상 크기 그대로면 너무 크다.
    /// 서로 겹치거나 시작·도착 마커를 가리는 라벨은 건너뛴다.
    /// 지도 스냅샷 두 종류(기본·심박존)가 이 함수 하나만 쓴다.
    static func drawKilometerMarkers(on snap: MKMapSnapshotter.Snapshot,
                                      coords: [CLLocationCoordinate2D]) {
        let total = totalRouteMeters(coords)
        guard total >= 1000 else { return }
        let step = mapMarkerStepKm(totalMeters: total)
        let marks = kilometerMarks(coords, stepKm: step, totalMeters: total)
        guard !marks.isEmpty else { return }

        let bounds = CGRect(origin: .zero, size: snap.image.size)
        let inset: CGFloat = 4
        // 시작(링 r5)·도착(글로우 r9) 마커 자리를 미리 잡아 라벨이 그 위를 덮지 않게 한다
        var placed: [CGRect] = []
        if let first = coords.first {
            let p = snap.point(for: first)
            placed.append(CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
        }
        if let last = coords.last {
            let p = snap.point(for: last)
            placed.append(CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20))
        }

        // 화면 배율만큼 크게 만들고 그릴 때 되돌린다 — 1x 이미지를 3x 컨텍스트에 늘리면 글자가 뭉갠다
        let screenScale = max(1, UIScreen.main.scale)
        let gap: CGFloat = 3

        for mark in marks {
            let pt = snap.point(for: mark.coord)
            guard bounds.contains(pt) else { continue }
            guard let labelImg = makeKmMarkerLabelImage(km: mark.km,
                                                        renderScale: 0.65 * screenScale,
                                                        style: .light) else { continue }
            let label = UIImage(cgImage: labelImg, scale: screenScale, orientation: .up)
            let lw = label.size.width
            let lh = label.size.height

            // 진행 방향 기준 **오른쪽**에 붙인다. 왕복 코스는 갈 때와 올 때 방향이 반대라
            // 라벨이 경로 양쪽으로 갈라져 서로 겹치지 않는다.
            let dir = routeDirection(on: snap, coords: coords, at: mark.index)
            let center = kmLabelCenter(at: pt, direction: dir,
                                       labelSize: CGSize(width: lw, height: lh), gap: gap)

            // 지도 밖으로 나가지 않게 가장자리에서 밀어 넣는다
            var rect = CGRect(x: center.x - lw / 2, y: center.y - lh / 2, width: lw, height: lh)
            rect.origin.x = min(max(rect.minX, inset), bounds.maxX - lw - inset)
            rect.origin.y = min(max(rect.minY, inset), bounds.maxY - lh - inset)

            // 그래도 겹치면 건너뛴다
            guard !placed.contains(where: { $0.insetBy(dx: -2, dy: -2).intersects(rect) }) else { continue }
            placed.append(rect)

            label.draw(in: rect)
        }
    }

    /// 화면 좌표 기준 진행 방향(정규화). 좌표가 조밀해 앞뒤 점이 거의 같은 자리면
    /// 6pt 이상 떨어진 점을 찾을 때까지 넓혀 노이즈에 휘둘리지 않게 한다.
    /// 경로선을 그린 뒤 호출 — km 라벨 → 시작 링 → 도착 골드 순으로 얹는다.
    /// `startPoint`/`endPoint`는 이미 화면 좌표로 변환된 경로의 첫/끝 점.
    static func drawAll(on snap: MKMapSnapshotter.Snapshot,
                        coords: [CLLocationCoordinate2D],
                        endPoint: CGPoint?, startPoint: CGPoint?) {
        drawKilometerMarkers(on: snap, coords: coords)
        if let startPoint { drawStartMarker(at: startPoint) }
        if let endPoint { drawFinishMarker(at: endPoint) }
    }

    static func routeDirection(on snap: MKMapSnapshotter.Snapshot,
                                coords: [CLLocationCoordinate2D], at index: Int) -> CGVector {
        let fallback = CGVector(dx: 1, dy: 0)
        guard coords.indices.contains(index) else { return fallback }
        let p0 = snap.point(for: coords[index])
        let minSpan: CGFloat = 6

        func normalized(_ dx: CGFloat, _ dy: CGFloat) -> CGVector? {
            let len = hypot(dx, dy)
            guard len >= minSpan else { return nil }
            return CGVector(dx: dx / len, dy: dy / len)
        }
        // 앞쪽 우선 — 진행 방향
        var j = index + 1
        while j < coords.count {
            let p = snap.point(for: coords[j])
            if let v = normalized(p.x - p0.x, p.y - p0.y) { return v }
            j += 1
        }
        // 끝에 가까우면 뒤쪽으로 (들어온 방향 = 진행 방향)
        var i = index - 1
        while i >= 0 {
            let p = snap.point(for: coords[i])
            if let v = normalized(p0.x - p.x, p0.y - p.y) { return v }
            i -= 1
        }
        return fallback
    }

}

/// 진행 방향 기준 **오른쪽**에 라벨을 놓을 때의 라벨 중심점.
/// 왕복 코스는 갈 때와 올 때 진행 방향이 반대라 라벨이 경로 양쪽으로 갈라져 겹치지 않는다.
/// UIKit 좌표(y가 아래로 증가) 기준 — 방향 (dx,dy)의 오른쪽 법선은 (-dy,dx).
func kmLabelCenter(at point: CGPoint, direction: CGVector,
                   labelSize: CGSize, gap: CGFloat) -> CGPoint {
    let len = hypot(direction.dx, direction.dy)
    guard len > 0.0001 else {
        return CGPoint(x: point.x, y: point.y + labelSize.height / 2 + gap)
    }
    let nx = -direction.dy / len
    let ny =  direction.dx / len
    // 라벨 중심에서 경계까지 거리 — 법선 방향에 따라 가로/세로 중 먼저 닿는 쪽
    var t = CGFloat.greatestFiniteMagnitude
    if abs(nx) > 0.0001 { t = min(t, (labelSize.width  / 2) / abs(nx)) }
    if abs(ny) > 0.0001 { t = min(t, (labelSize.height / 2) / abs(ny)) }
    if !t.isFinite { t = labelSize.height / 2 }
    return CGPoint(x: point.x + nx * (t + gap), y: point.y + ny * (t + gap))
}

/// 지도 km 마커 간격. 1km마다 찍으면 촘촘해지는 거리에서는 2km·3km(그 이상은 5·10km)로 넓힌다.
/// 기준: 지도에 마커가 10개를 넘지 않게.
func mapMarkerStepKm(totalMeters: Double) -> Double {
    let totalKm = totalMeters / 1000
    for step in [1.0, 2.0, 3.0, 5.0, 10.0] where totalKm / step <= 10 { return step }
    return 10
}

private struct RouteMapView: View {
    let coordinates: [CLLocationCoordinate2D]
    let activityID: UUID
    let activityDate: Date
    let manager: HealthKitManager       // HR 차트와 동일한 소스: manager.fetchHRTimeSeries
    var routeTimeOffsets: [TimeInterval] = []
    var workoutDuration: TimeInterval = 0
    var hasHRData: Bool = false
    @Binding var showHRZones: Bool

    @State private var snapshot: UIImage?
    @State private var hrZoneSnapshot: UIImage?
    @State private var isGeneratingHRSnapshot = false
    @State private var localHRSamples: [(offset: TimeInterval, bpm: Int)] = []
    @State private var hrLoadDone = false

    private var canShowZones: Bool { hrLoadDone && localHRSamples.count >= 10 }

    var body: some View {
        ZStack {
            if showHRZones && hasHRData {
                if let img = hrZoneSnapshot {
                    mapImage(img)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(hex: "0D0D12"))
                        .frame(height: 220)
                        .overlay { ProgressView().tint(isGeneratingHRSnapshot ? Theme.heartRate : Theme.violet) }
                }
            } else {
                if let img = snapshot {
                    mapImage(img)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(hex: "0D0D12"))
                        .frame(height: 220)
                        .overlay { ProgressView().tint(Theme.violet) }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if hasHRData {
                modeChip
                    .padding(10)
            }
        }
        .padding(.horizontal, 16)
        .task(id: activityID) {
            // 1) 기본 지도 스냅샷
            if snapshot == nil {
                if let cached = loadFromDisk() {
                    snapshot = cached
                } else if let generated = await makeSnapshot() {
                    snapshot = generated
                    saveToDisk(generated)
                }
            }
            // 2) 디스크에 이미 완성된 존 스냅샷이 있으면 즉시 로드
            if hrZoneSnapshot == nil, let cached = loadHRZoneFromDisk() {
                hrZoneSnapshot = cached
            }
            // 3) HR 시계열 로드 — HR 차트와 동일 소스(fetchHRTimeSeries)
            if hasHRData { await loadLocalHRSamples() }
            // 4) 존 모드가 이미 켜져 있고 샘플 충분하면 생성
            if showHRZones, hrZoneSnapshot == nil, canShowZones {
                await generateHRZoneSnapshot()
            }
        }
        .onChange(of: showHRZones) { _, newValue in
            guard newValue, hrZoneSnapshot == nil else { return }
            if canShowZones {
                Task { await generateHRZoneSnapshot() }
            }
        }
    }

    private func mapImage(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var modeChip: some View {
        HStack(spacing: 0) {
            chipButton(AppLanguage.shared.s("심박존", "HR Zones"),
                       selected: showHRZones && canShowZones,
                       loading: (!hrLoadDone && hasHRData) || (showHRZones && isGeneratingHRSnapshot)) {
                if canShowZones { showHRZones = true }
            }
            chipButton(AppLanguage.shared.s("기본", "Default"), selected: !showHRZones) { showHRZones = false }
        }
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private func chipButton(_ label: String, selected: Bool, loading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if loading { ProgressView().scaleEffect(0.65).tint(.white) }
                Text(label)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : .white.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selected ? Color.white.opacity(0.2) : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Disk cache

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(RouteMapCache.plainPrefix)\(RouteMapCache.plainVersion)_\(activityID.uuidString).jpg")
    }

    private var hrZoneCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(RouteMapCache.zonePrefix)\(RouteMapCache.zoneVersion)_\(activityID.uuidString).jpg")
    }

    private func loadFromDisk() -> UIImage? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(_ image: UIImage) {
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: cacheURL)
        }
    }

    private func loadHRZoneFromDisk() -> UIImage? {
        guard let data = try? Data(contentsOf: hrZoneCacheURL) else { return nil }
        return UIImage(data: data)
    }

    private func saveHRZoneToDisk(_ image: UIImage) {
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: hrZoneCacheURL)
        }
    }

    // MARK: - Snapshot generation (default — violet single line)

    private func makeSnapshot() async -> UIImage? {
        // Filter out invalid GPS fixes (e.g. (0,0) cold-start spikes that inflate bounding box)
        let valid = coordinates.filter { CLLocationCoordinate2DIsValid($0) && abs($0.latitude) > 1 && abs($0.longitude) > 1 }
        guard valid.count > 1 else { return nil }

        let lats = valid.map(\.latitude)
        let lons = valid.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }

        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.004, (maxLat - minLat) * 1.4),
                longitudeDelta: max(0.004, (maxLon - minLon) * 1.4)
            )
        )
        // Cap at 398pt so snapshot fits inside 430pt iPad container (16pt padding each side)
        let snapWidth = min(398, max(300, UIScreen.main.bounds.width - 32))
        opts.size = CGSize(width: snapWidth, height: 220)
        opts.scale = UIScreen.main.scale
        // 내보내는 경로 카드와 같은 지도로 보이게 — 스타일은 RouteSnapshotRenderer 한 곳에서 정한다
        RouteSnapshotRenderer.applyRouteMapStyle(opts)

        guard let snap = try? await MKMapSnapshotter(options: opts).start() else { return nil }

        // snap.point(for:) returns logical-point coordinates matching snap.image.size (Apple documented).
        // Use valid-only coordinates so invalid GPS spikes don't shift points off-screen.
        let step = max(1, valid.count / 300)
        let pts = stride(from: 0, to: valid.count, by: step).map { snap.point(for: valid[$0]) }

        let violetColor = UIColor(red: 0x7C / 255.0, green: 0x5C / 255.0, blue: 0xFC / 255.0, alpha: 1.0)
        // Use default format (no explicit scale) — matches Apple's documented snapshot drawing pattern
        return UIGraphicsImageRenderer(size: snap.image.size).image { _ in
            snap.image.draw(at: .zero)
            guard pts.count > 1 else { return }

            let path = UIBezierPath()
            path.move(to: pts[0])
            for pt in pts.dropFirst() { path.addLine(to: pt) }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            // Glow
            path.lineWidth = 3
            violetColor.withAlphaComponent(0.4).setStroke()
            path.stroke()

            // Main line
            path.lineWidth = 1.5
            violetColor.setStroke()
            path.stroke()

            RouteMarkers.drawAll(on: snap, coords: valid, endPoint: pts.last, startPoint: pts.first)

        }
    }

    // MARK: - HR 시계열 로드 (HR 차트와 동일 소스)

    private func loadLocalHRSamples() async {
        let samples = await manager.fetchHRTimeSeries(for: activityID)
        localHRSamples = samples
        hrLoadDone = true
        if samples.count < 10 { return }
        // 로드 완료 후 칩이 이미 켜져 있으면 생성
        if showHRZones, hrZoneSnapshot == nil {
            await generateHRZoneSnapshot()
        }
    }

    // MARK: - HR zone snapshot

    private func generateHRZoneSnapshot() async {
        guard !isGeneratingHRSnapshot else { return }
        isGeneratingHRSnapshot = true
        defer { isGeneratingHRSnapshot = false }
        if let cached = loadHRZoneFromDisk() { hrZoneSnapshot = cached; return }
        if let generated = await makeHRZoneSnapshot() {
            hrZoneSnapshot = generated
            saveHRZoneToDisk(generated)
        }
    }

    private func makeHRZoneSnapshot() async -> UIImage? {
        // enumerated() preserves original index for routeTimeOffsets lookup
        let indexed = Array(coordinates.enumerated().filter {
            CLLocationCoordinate2DIsValid($0.element) && abs($0.element.latitude) > 1 && abs($0.element.longitude) > 1
        })
        guard indexed.count > 1, !localHRSamples.isEmpty else { return nil }

        // 존 경계: 러닝 날짜 기준 직전 30일 RHR → Karvonen, 없으면 %MHR — computeHRZonesForDate가 일원화
        let zones = await manager.computeHRZonesForDate(activityDate, samples: localHRSamples)
        let zoneBounds: [(id: Int, minBPM: Int)] = zones.isEmpty
            ? { let peak = min(220, Int(Double(localHRSamples.map(\.bpm).max() ?? 180) / 0.90))
                return [(1,0),(2,Int(Double(peak)*0.60)),(3,Int(Double(peak)*0.70)),(4,Int(Double(peak)*0.80)),(5,Int(Double(peak)*0.90))] }()
            : zones.sorted { $0.minBPM < $1.minBPM }.map { (id: $0.id, minBPM: $0.minBPM) }

        let lats = indexed.map { $0.element.latitude }
        let lons = indexed.map { $0.element.longitude }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }

        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.004, (maxLat - minLat) * 1.4),
                longitudeDelta: max(0.004, (maxLon - minLon) * 1.4)
            )
        )
        let snapWidth = min(398, max(300, UIScreen.main.bounds.width - 32))
        opts.size = CGSize(width: snapWidth, height: 220)
        opts.scale = UIScreen.main.scale
        // 내보내는 경로 카드와 같은 지도로 보이게 — 스타일은 RouteSnapshotRenderer 한 곳에서 정한다
        RouteSnapshotRenderer.applyRouteMapStyle(opts)

        guard let snap = try? await MKMapSnapshotter(options: opts).start() else { return nil }

        let step = max(1, indexed.count / 300)
        struct ZP { let pt: CGPoint; let bpm: Int; let matched: Bool }
        var points: [ZP] = []
        for i in stride(from: 0, to: indexed.count, by: step) {
            let (origIdx, coord) = indexed[i]
            let pt = snap.point(for: coord)
            let offset = origIdx < routeTimeOffsets.count
                ? routeTimeOffsets[origIdx]
                : Double(origIdx) * workoutDuration / max(Double(coordinates.count - 1), 1)
            let (bpm, matched) = smoothedBPM(at: offset)
            points.append(ZP(pt: pt, bpm: bpm, matched: matched))
        }

        // 매칭 성공률 확인 — 좌표-샘플 시간대 불일치 감지
        let matchedCount = points.filter(\.matched).count
        guard matchedCount > 0 else { return nil }

        let sortedBounds = zoneBounds.sorted { $0.minBPM < $1.minBPM }
        return UIGraphicsImageRenderer(size: snap.image.size).image { _ in
            snap.image.draw(at: .zero)
            guard points.count > 1 else { return }
            // 글로우 패스 전체 먼저 → 코어 패스 위에 올림
            for i in 0..<(points.count - 1) {
                let color = gradientUIColor(bpm: (points[i].bpm + points[i+1].bpm) / 2, bounds: sortedBounds)
                let seg = UIBezierPath()
                seg.move(to: points[i].pt); seg.addLine(to: points[i+1].pt)
                seg.lineCapStyle = .round; seg.lineWidth = 3.5
                color.withAlphaComponent(0.35).setStroke(); seg.stroke()
            }
            for i in 0..<(points.count - 1) {
                let color = gradientUIColor(bpm: (points[i].bpm + points[i+1].bpm) / 2, bounds: sortedBounds)
                let seg = UIBezierPath()
                seg.move(to: points[i].pt); seg.addLine(to: points[i+1].pt)
                seg.lineCapStyle = .round; seg.lineWidth = 1.5
                color.setStroke(); seg.stroke()
            }
            RouteMarkers.drawAll(on: snap, coords: indexed.map(\.element),
                                 endPoint: points.last?.pt, startPoint: points.first?.pt)

        }
    }

    // 5초 이동평균 심박 반환 — matched=true면 윈도우 샘플 있음, false면 최근접 폴백
    private func smoothedBPM(at offset: TimeInterval) -> (bpm: Int, matched: Bool) {
        let window = localHRSamples.filter { abs($0.offset - offset) <= 2.5 }
        if window.isEmpty {
            guard let nearest = localHRSamples.min(by: { abs($0.offset - offset) < abs($1.offset - offset) }) else { return (60, false) }
            return (nearest.bpm, false)
        }
        return (window.reduce(0) { $0 + $1.bpm } / window.count, true)
    }

    // 존 경계 BPM → 그라데이션 UIColor (인접 존 색 사이 선형 보간)
    private func gradientUIColor(bpm: Int, bounds: [(id: Int, minBPM: Int)]) -> UIColor {
        let sorted = bounds.sorted { $0.minBPM < $1.minBPM }
        let colors = Theme.hrZoneColors.map { UIColor($0) }
        guard sorted.count >= 2, !colors.isEmpty else { return UIColor(Theme.violet) }
        if bpm <= sorted[0].minBPM { return colors[0] }
        for i in 0..<(sorted.count - 1) {
            let lo = sorted[i].minBPM, hi = sorted[i+1].minBPM
            guard hi > lo, bpm < hi else { continue }
            let t = CGFloat(bpm - lo) / CGFloat(hi - lo)
            return lerpUIColor(colors[min(i, colors.count-1)], colors[min(i+1, colors.count-1)], t)
        }
        return colors[min(sorted.count-1, colors.count-1)]
    }

    private func lerpUIColor(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat=0, g1: CGFloat=0, b1: CGFloat=0, a1: CGFloat=0
        var r2: CGFloat=0, g2: CGFloat=0, b2: CGFloat=0, a2: CGFloat=0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let tc = max(0, min(1, t))
        return UIColor(red: r1+(r2-r1)*tc, green: g1+(g2-g1)*tc, blue: b1+(b2-b1)*tc, alpha: 1)
    }
}

// MARK: - Metric grid

private struct MetricGrid: View {
    let activity: Activity
    let detail: ActivityDetail?
    let age: Int?
    let isMale: Bool?

    // 항목 목록은 RunMetricItem.list 한 곳에서만 만든다 — 공유 카드와 같은 목록을 쓴다.
    private var items: [RunMetricItem] {
        RunMetricItem.list(activity: activity, detail: detail, age: age, isMale: isMale)
    }

    var body: some View {
        // 셀은 공유 카드들과 같은 컴포넌트를 쓴다 — 크기만 scale로 조정(§5.8).
        RunMetricGrid(items: items, style: .appDark, scale: 1.0)
        .padding(.horizontal, 16)
        #if DEBUG
        // 화면이 실제로 그리는 항목 — 매니저의 activities가 아니라 이 뷰가 받은 activity 기준.
        // 둘이 다를 수 있어서(값 복사) 캐시 로그만으로는 빈칸의 이유를 못 가린다.
        .onAppear {
            let hr  = activity.avgHeartRate.map(String.init) ?? "없음"
            let cal = activity.calories.map { String(Int($0)) } ?? "없음"
            print("[격자] \(items.count)개 그림 — \(items.map(\.label).joined(separator: " "))")
            print("[격자] 이 뷰가 받은 activity: 심박 \(hr) · 칼로리 \(cal) · 유형 \(activity.type)")
        }
        #endif
    }
}

// MARK: - Detail Section Header

private struct DetailSectionHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline).foregroundStyle(.white)
            Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.55))
        }
    }
}

// MARK: - Interval Segments Section

private struct IntervalSegmentsSection: View {
    let segments: [IntervalSegment]
    var activity: Activity? = nil
    var condition: ActivityCondition? = nil
    var firstCoordinate: CLLocationCoordinate2D? = nil

    @Environment(CustomMiniMeStore.self) private var miniMeStore
    @State private var showIntervalsShare = false
    @Query private var allStories: [WorkoutStory]
    @Query private var allShoes: [Shoe]

    private var shoeName: String? {
        guard let wid = activity?.id.uuidString,
              let sid = allStories.first(where: { $0.workoutID == wid })?.shoeID else { return nil }
        return allShoes.first { $0.id.uuidString == sid }?.displayName
    }

    private var hasLabels: Bool { segments.contains { $0.stepLabel != nil } }
    private var hasHR: Bool { segments.contains { $0.avgHeartRate != nil } }
    private var hasDist: Bool { segments.contains { $0.distanceM != nil } }
    private var hasCadence: Bool { segments.contains { $0.avgCadence != nil } }

    private var medianPace: Double? {
        guard !hasLabels else { return nil }
        let paces = segments.compactMap(\.paceSecPerKm).sorted()
        guard !paces.isEmpty else { return nil }
        return paces[paces.count / 2]
    }

    private func localizedStepLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let L = AppLanguage.shared
        switch raw {
        case "준비운동": return L.s("준비운동", "Warmup")
        case "운동":     return L.s("운동",     "Work")
        case "회복":     return L.s("회복",     "Recovery")
        case "정리운동": return L.s("정리운동", "Cooldown")
        case "구간":     return L.s("구간",     "Interval")
        default:         return raw
        }
    }

    private func isWork(_ seg: IntervalSegment) -> Bool {
        if let label = seg.stepLabel { return label == "운동" }
        if let pace = seg.paceSecPerKm, let median = medianPace { return pace < median }
        return seg.id % 2 == 1
    }

    private static let standardDistances = [100, 200, 300, 400, 500, 600, 800, 1000, 1200, 1500, 1600, 2000, 3000, 4000, 5000]

    private func recognizedDistanceM(_ d: Double) -> Int {
        let tolerance = 0.08
        if let snap = Self.standardDistances.first(where: { abs(Double($0) - d) / Double($0) <= tolerance }) { return snap }
        return d >= 200 ? Int((d / 100).rounded()) * 100 : Int((d / 50).rounded()) * 50
    }

    private var workSummaryText: String? {
        let workSegs = segments.filter { isWork($0) }
        guard !workSegs.isEmpty else { return nil }
        let distances = workSegs.compactMap(\.distanceM)
        guard distances.count == workSegs.count else { return nil }
        let snapped = distances.map { recognizedDistanceM($0) }
        guard let dominant = snapped.sorted().first(where: { d in snapped.filter { $0 == d }.count == snapped.count }) else {
            // mixed distances — find most common
            let counts = Dictionary(grouping: snapped, by: { $0 }).mapValues(\.count)
            guard let (dist, cnt) = counts.max(by: { $0.value < $1.value }), cnt > 1 else { return nil }
            let label = dist >= 1000
                ? (dist % 1000 == 0 ? "\(dist / 1000)km" : String(format: "%.1fkm", Double(dist) / 1000))
                : "\(dist)m"
            return AppLanguage.shared.s("\(label)×\(cnt)회", "\(label)×\(cnt)")
        }
        let label = dominant >= 1000
            ? (dominant % 1000 == 0 ? "\(dominant / 1000)km" : String(format: "%.1fkm", Double(dominant) / 1000))
            : "\(dominant)m"
        return AppLanguage.shared.s("\(label)×\(workSegs.count)회", "\(label)×\(workSegs.count)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                DetailSectionHeader(
                    title: AppLanguage.shared.s("인터벌 구간", "Interval Reps"),
                    subtitle: {
                        let base = AppLanguage.shared.s("\(segments.count)개 구간", "\(segments.count) reps")
                        if let s = workSummaryText { return "\(base) (\(s))" }
                        return base
                    }()
                )
                Spacer()
                if activity != nil {
                    Button { showIntervalsShare = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption.weight(.semibold))
                            Text(AppLanguage.shared.s("공유", "Share"))
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Theme.violet)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.violet.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        if hasLabels {
                            Text(AppLanguage.shared.s("구간", "Rep")).frame(width: 56, alignment: .leading)
                        } else {
                            Text("#").frame(width: 20, alignment: .leading)
                        }
                        if hasDist { Text(AppLanguage.shared.s("거리", "Dist.")).frame(width: 60, alignment: .trailing) }
                        Spacer(minLength: 8)
                        Text(AppLanguage.shared.s("페이스", "Pace")).frame(width: 70, alignment: .trailing)
                        Text(AppLanguage.shared.s("시간", "Time")).frame(width: 50, alignment: .trailing)
                        if hasHR { Text(AppLanguage.shared.s("심박", "HR")).frame(width: 44, alignment: .trailing) }
                        if hasCadence { Text(AppLanguage.shared.s("케이던스", "Cad.")).frame(width: 50, alignment: .trailing) }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    ForEach(segments) { seg in
                        let work = isWork(seg)
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 0.5)
                            HStack(spacing: 8) {
                                if hasLabels {
                                    Text(localizedStepLabel(seg.stepLabel) ?? "#\(seg.id)")
                                        .font(.system(.subheadline, design: .rounded).weight(work ? .bold : .regular))
                                        .foregroundStyle(work ? Theme.violet : Color.white.opacity(0.55))
                                        .frame(width: 56, alignment: .leading)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                } else {
                                    Text("\(seg.id)")
                                        .font(.system(.subheadline, design: .rounded).weight(work ? .bold : .regular))
                                        .foregroundStyle(work ? Theme.violet : Color.white.opacity(0.45))
                                        .frame(width: 20, alignment: .leading)
                                }
                                if hasDist {
                                    Text(seg.formattedDistance ?? "—")
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(work ? .white : Color.white.opacity(0.45))
                                        .frame(width: 60, alignment: .trailing)
                                }
                                Spacer(minLength: 8)
                                Text(seg.formattedPace ?? "—")
                                    .font(.system(.callout, design: .rounded).weight(work ? .semibold : .regular))
                                    .foregroundStyle(
                                        seg.formattedPace != nil
                                            ? (work ? Theme.violet : Color.white.opacity(0.40))
                                            : Color.secondary
                                    )
                                    .frame(width: 70, alignment: .trailing)
                                Text(seg.formattedDuration)
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundStyle(work ? .secondary : Color.white.opacity(0.25))
                                    .frame(width: 50, alignment: .trailing)
                                if hasHR {
                                    Text(seg.avgHeartRate.map { "\($0)" } ?? "—")
                                        .font(.system(.callout, design: .rounded).weight(.medium))
                                        .foregroundStyle(
                                            seg.avgHeartRate != nil
                                                ? (work ? Theme.heartRate : Theme.heartRate.opacity(0.45))
                                                : Color.secondary
                                        )
                                        .frame(width: 44, alignment: .trailing)
                                }
                                if hasCadence {
                                    Text(seg.avgCadence.map { "\($0)" } ?? "—")
                                        .font(.system(.callout, design: .rounded).weight(.medium))
                                        .foregroundStyle(
                                            seg.avgCadence != nil
                                                ? (work ? Theme.cadence : Theme.cadence.opacity(0.45))
                                                : Color.secondary
                                        )
                                        .frame(width: 50, alignment: .trailing)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(work ? Theme.violet.opacity(0.07) : Color.clear)
                        }
                    }
                }
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showIntervalsShare) {
            if let act = activity {
                IntervalsShareCardScreen(activity: act, segments: segments, miniMeImage: miniMeStore.image,
                                        weatherText: act.temperatureC.map { String(format: "%.0f°C", $0) },
                                        weatherIcon: condition?.weather?.systemIcon,
                                        shoeName: shoeName,
                                        firstCoordinate: firstCoordinate)
            }
        }
    }
}

// MARK: - Splits Section

private struct SplitsSection: View {
    let splits: [SplitData]
    var zones: [HRZoneData] = []
    var activity: Activity? = nil
    var allActivities: [Activity] = []
    var condition: ActivityCondition? = nil
    var firstCoordinate: CLLocationCoordinate2D? = nil
    /// 상단 지표 그리드와 같은 목록 — "구간 러닝 데이터" 카드에 그대로 실린다
    var runMetrics: [RunMetricItem] = []

    @Environment(CustomMiniMeStore.self) private var miniMeStore
    @State private var shareVariant: SplitsCardVariant? = nil
    @Query private var allStories: [WorkoutStory]
    @Query private var allShoes: [Shoe]

    private var shoeName: String? {
        guard let wid = activity?.id.uuidString,
              let sid = allStories.first(where: { $0.workoutID == wid })?.shoeID else { return nil }
        return allShoes.first { $0.id.uuidString == sid }?.displayName
    }

    private var fastestIdx: Int? {
        splits.indices.min(by: { splits[$0].paceSecPerKm < splits[$1].paceSecPerKm })
    }
    private var minPace: Double { splits.map(\.paceSecPerKm).min() ?? 0 }
    private var maxPace: Double { splits.map(\.paceSecPerKm).max() ?? 0 }
    private var avgPace: Double {
        guard !splits.isEmpty else { return 0 }
        return splits.map(\.paceSecPerKm).reduce(0, +) / Double(splits.count)
    }

    // Faster pace = fewer seconds per km = longer bar. Range: 0.28 (slowest) … 1.0 (fastest).
    private func barFraction(for pace: Double) -> Double {
        let range = maxPace - minPace
        guard range > 0.5 else { return 0.65 }
        return 0.28 + 0.72 * (maxPace - pace) / range
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailSectionHeader(title: AppLanguage.shared.s("구간 기록", "Splits"),
                               subtitle: AppLanguage.shared.s("\(splits.count)개 구간", "\(splits.count) splits"))
            if activity != nil {
                HStack(spacing: 8) {
                    exportButton(title: AppLanguage.shared.s("구간 러닝 데이터 내보내기", "Export Splits + Run Data"),
                                 variant: .runData)
                    exportButton(title: AppLanguage.shared.s("구간 심박영역 내보내기", "Export Splits + HR Zones"),
                                 variant: .hrZones)
                }
            }
            SplitsHighlightCard(splits: splits, activity: activity, allActivities: allActivities)
            VStack(spacing: 0) {
                ForEach(Array(splits.enumerated()), id: \.element.id) { idx, split in
                    SplitBarRow(
                        split: split,
                        isFastest: idx == fastestIdx,
                        isSlowerThanAvg: split.paceSecPerKm > avgPace,
                        barFraction: barFraction(for: split.paceSecPerKm),
                        avgFraction: barFraction(for: avgPace),
                        showTopDivider: idx > 0,
                        zones: zones
                    )
                }
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 16)
        .sheet(item: $shareVariant) { variant in
            if let act = activity {
                SplitsShareCardScreen(activity: act, splits: splits, zones: zones, miniMeImage: miniMeStore.image, shoeName: shoeName,
                                      weatherText: act.temperatureC.map { String(format: "%.0f°C", $0) },
                                      weatherIcon: condition?.weather?.systemIcon,
                                      firstCoordinate: firstCoordinate,
                                      variant: variant,
                                      runMetrics: runMetrics)
            }
        }
    }

    private func exportButton(title: String, variant: SplitsCardVariant) -> some View {
        Button {
            shareVariant = variant
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up.on.square")
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Theme.violet)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Theme.violet.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SplitBarRow: View {
    let split: SplitData
    let isFastest: Bool
    let isSlowerThanAvg: Bool
    let barFraction: Double
    let avgFraction: Double
    let showTopDivider: Bool
    var zones: [HRZoneData] = []

    private var hrZoneNumber: Int? {
        guard let hr = split.avgHeartRate, !zones.isEmpty else { return nil }
        return zones.first(where: { hr >= $0.minBPM && hr <= $0.maxBPM })?.id
    }

    private static let barWidth: CGFloat = 110

    private static let gold        = Color(hex: "FFC74D")
    private static let goldDark    = Color(hex: "F2A33C")
    private static let violetHi    = Color(hex: "9B7DFF")
    private static let violetLo    = Color(hex: "6845E8")
    private static let track       = Color.white.opacity(0.09)
    private static let kmColor     = Color(hex: "6E6E78")
    private static let hrColor     = Color(hex: "8A8A92")
    private static let cadColor    = Color(hex: "60E8CC")
    private static let pwrColor    = Color(hex: "BEFA6A")
    private static let avgDotColor = Color(hex: "7A7A85")

    private var kmLabel: String {
        if split.distanceM < 990 {
            return String(format: "%.1f", split.distanceM / 1000)
        }
        return split.id == 1 ? "1km" : "\(split.id)"
    }

    private func hrZoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return Color(hex: "4FC3F7")
        case 2: return Color(hex: "81C784")
        case 3: return Color(hex: "FFB74D")
        case 4: return Color(hex: "FF7043")
        case 5: return Color(hex: "E53935")
        default: return .secondary
        }
    }

    private var barGradient: LinearGradient {
        if isFastest {
            return LinearGradient(colors: [Self.gold, Self.goldDark],
                                  startPoint: .leading, endPoint: .trailing)
        }
        let a: Double = isSlowerThanAvg ? 0.75 : 1.0
        return LinearGradient(colors: [Self.violetHi.opacity(a), Self.violetLo.opacity(a)],
                              startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showTopDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
            }
            HStack(alignment: .center, spacing: 0) {
                // ① km label
                Text(kmLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isFastest ? Self.gold : Self.kmColor)
                    .frame(width: 28, alignment: .leading)

                // ② 고정 너비 바 + 평균 점선
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Self.track)
                        .frame(width: Self.barWidth, height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barGradient)
                        .frame(width: max(10, Self.barWidth * barFraction), height: 6)
                    VStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(Self.avgDotColor.opacity(0.45))
                                .frame(width: 1.5, height: 2.5)
                        }
                    }
                    .offset(x: max(0, Self.barWidth * avgFraction - 0.75))
                }
                .frame(width: Self.barWidth, height: 16)
                .padding(.horizontal, 5)

                // ③ 한 줄: 최고 · 페이스 · 심박 · 존 · 케이던스 · 파워
                HStack(spacing: 4) {
                    if isFastest {
                        Text(AppLanguage.shared.s("최고", "Best"))
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Self.gold)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1.5)
                            .background(Self.gold.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text(split.formattedPace)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isFastest ? Self.gold : .white)
                    if let hr = split.avgHeartRate {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Theme.heartRate)
                        Text("\(hr)")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Theme.heartRate)
                    }
                    if let zone = hrZoneNumber {
                        Text("Z\(zone)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(hrZoneColor(zone))
                    }
                    if let cad = split.avgCadence {
                        Text("\(cad)") .font(.system(size: 10, design: .rounded)) .foregroundStyle(Self.cadColor)
                        + Text("spm") .font(.system(size: 9))                     .foregroundStyle(Self.cadColor.opacity(0.85))
                    }
                    if let pwr = split.avgPower {
                        Text("\(pwr)") .font(.system(size: 10, design: .rounded)) .foregroundStyle(Self.pwrColor)
                        + Text("W")   .font(.system(size: 9))                     .foregroundStyle(Self.pwrColor.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
        }
    }
}

// MARK: - Splits Highlight Card

private struct SplitsHighlightCard: View {
    let splits: [SplitData]
    var activity: Activity? = nil
    var allActivities: [Activity] = []

    private static let gold = Color(hex: "FFC74D")

    private var avgPaceSeconds: Double {
        guard !splits.isEmpty else { return 0 }
        return splits.map(\.paceSecPerKm).reduce(0,+) / Double(splits.count)
    }
    private var fastestSplit: SplitData? { splits.min(by: { $0.paceSecPerKm < $1.paceSecPerKm }) }
    private var paceSpread: Double {
        guard let lo = splits.map(\.paceSecPerKm).min(),
              let hi = splits.map(\.paceSecPerKm).max() else { return 0 }
        return hi - lo
    }

    private enum HighlightKind {
        case negativeSplit(diff: Int)
        case consistency(spread: Int)
        case recentBest(n: Int)
        case fallback
    }
    private var highlightKind: HighlightKind {
        // 1. Negative split — need ≥4 splits for meaningful halves
        if splits.count >= 4 {
            let half = splits.count / 2
            let firstAvg  = splits.prefix(half).map(\.paceSecPerKm).reduce(0,+) / Double(half)
            let backCount = splits.count - half
            let secondAvg = splits.suffix(backCount).map(\.paceSecPerKm).reduce(0,+) / Double(backCount)
            let diff = firstAvg - secondAvg   // positive → second half faster
            if diff >= 5 { return .negativeSplit(diff: Int(diff.rounded())) }
        }
        // 2. Pace consistency
        if splits.count >= 2 && paceSpread < 20 {
            return .consistency(spread: Int(paceSpread.rounded()))
        }
        // 3. Recent similar-distance comparison
        if let act = activity, let currentPace = act.paceSecPerKm {
            let targetDist = act.distance
            let similar = allActivities.filter { a in
                a.id != act.id && a.type == act.type &&
                abs(a.distance - targetDist) / max(targetDist, 1) < 0.15 &&
                a.paceSecPerKm != nil && a.date < act.date
            }.sorted { $0.date > $1.date }
            if similar.count >= 2 {
                let recentPaces = similar.prefix(5).compactMap(\.paceSecPerKm)
                let recentAvg = recentPaces.reduce(0,+) / Double(recentPaces.count)
                if currentPace < recentAvg { return .recentBest(n: min(similar.count, 5)) }
            }
        }
        return .fallback
    }

    private var isFallback: Bool { if case .fallback = highlightKind { return true }; return false }

    private var messageText: Text {
        let g = Self.gold
        let L = AppLanguage.shared
        switch highlightKind {
        case .negativeSplit(let diff):
            return L.isEnglish
                ? Text("Second half ").foregroundStyle(Color.white)
                  + Text("\(diff)s faster").foregroundStyle(g)
                  + Text(" — you pushed through.").foregroundStyle(Color.white)
                : Text("후반이 전반보다 ").foregroundStyle(Color.white)
                  + Text("\(diff)초 더 빠르게").foregroundStyle(g)
                  + Text(" — 끝까지 밀어붙였네요.").foregroundStyle(Color.white)
        case .consistency(let spread):
            return L.isEnglish
                ? Text("Pace deviation only ").foregroundStyle(Color.white)
                  + Text("\(spread)s").foregroundStyle(g)
                  + Text(" — rock solid.").foregroundStyle(Color.white)
                : Text("페이스 편차 단 ").foregroundStyle(Color.white)
                  + Text("\(spread)초").foregroundStyle(g)
                  + Text(", 흔들림 없었어요.").foregroundStyle(Color.white)
        case .recentBest(let n):
            return L.isEnglish
                ? Text("Fastest avg pace in your last ").foregroundStyle(Color.white)
                  + Text("\(n) runs").foregroundStyle(g)
                  + Text(".").foregroundStyle(Color.white)
                : Text("최근 \(n)회 중 ").foregroundStyle(Color.white)
                  + Text("가장 빠른 평균 페이스").foregroundStyle(g)
                  + Text("예요.").foregroundStyle(Color.white)
        case .fallback:
            return Text(L.s("완주했어요. 오늘도 수고하셨어요.", "Finished. Great work today."))
                .foregroundStyle(Color.secondary)
        }
    }

    private func formatPace(_ sec: Double) -> String {
        let s = Int(sec.rounded())
        return "\(s / 60)'\(String(format: "%02d", s % 60))\""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            messageText
                .font(.system(size: 14, weight: isFallback ? .regular : .semibold))

            HStack(spacing: 8) {
                SplitChip(label: AppLanguage.shared.s("평균 페이스", "Avg Pace"), value: formatPace(avgPaceSeconds), color: Theme.violet)
                SplitChip(label: AppLanguage.shared.s("페이스 편차", "Deviation"),
                          value: AppLanguage.shared.s("±\(Int(paceSpread.rounded()))초", "±\(Int(paceSpread.rounded()))s"),
                          color: Theme.violet)
                if let fastest = fastestSplit {
                    let km = fastest.distanceM >= 990 ? "\(fastest.id)km" : AppLanguage.shared.s("마지막", "Last")
                    SplitChip(label: AppLanguage.shared.s("최고 구간", "Best Split"), value: "\(km) · \(fastest.formattedPace)", color: Self.gold)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Theme.violet.opacity(0.18), Color(hex: "6845E8").opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.violet.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SplitChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - HR Zones Section

private struct HRZonesSection: View {
    let zones: [HRZoneData]

    private func zoneColor(_ id: Int) -> Color { Theme.hrZoneColor(id) }

    private func formattedZoneTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func bpmRangeText(_ zone: HRZoneData) -> String {
        if zone.id == 1 { return "<\(zone.maxBPM)BPM" }
        if zone.id == 5 { return "\(zone.minBPM)+BPM" }
        return "\(zone.minBPM)~\(zone.maxBPM)BPM"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailSectionHeader(title: AppLanguage.shared.s("심박 영역", "HR Zones"),
                               subtitle: AppLanguage.shared.s("존별 운동 시간", "Time per zone"))

            VStack(spacing: 0) {
                ForEach(Array(zones.enumerated()), id: \.element.id) { idx, zone in
                    let color = zoneColor(zone.id)
                    let hasTime = zone.seconds > 0
                    VStack(spacing: 0) {
                        if idx > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 0.5)
                        }
                        HStack(spacing: 8) {
                            // Zone label
                            Text(AppLanguage.shared.s("영역 \(zone.id)", "Z\(zone.id)"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(hasTime ? color : color.opacity(0.45))
                                .frame(width: 44, alignment: .leading)

                            // Bar — RoundedRectangle so tiny fractions stay as short bars, not dots
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.09))
                                        .frame(height: 7)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    if hasTime {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(color)
                                            .frame(width: max(8, geo.size.width * zone.fraction),
                                                   height: 7)
                                            .frame(maxHeight: .infinity)
                                    }
                                }
                            }
                            .frame(height: 20)

                            // Time in zone
                            Text(formattedZoneTime(zone.seconds))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(hasTime ? Color.white : Color.white.opacity(0.25))
                                .frame(width: 40, alignment: .trailing)

                            // BPM range
                            Text(bpmRangeText(zone))
                                .font(.system(size: 10))
                                .foregroundStyle(hasTime ? Color.white.opacity(0.55) : Color.white.opacity(0.2))
                                .frame(width: 82, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 1)
                    }
                }

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 0.5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLanguage.shared.s("각각의 심박수 영역에 머무르는 예상 시간입니다.", "Estimated time spent in each heart rate zone."))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(AppLanguage.shared.s("Karvonen(심박 예비율) 공식 기반 · 최근 30일 최소 휴식 시 심박수(RHR) + 나이별 최대심박(MHR) 추정 적용. 개인 체력 및 측정 조건에 따라 실제 영역과 다를 수 있습니다.", "Based on Karvonen (HRR) formula · Uses lowest resting HR over last 30 days + age-estimated max HR. Zones may differ from actual values."))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Metric Cell

private struct MetricCell: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    var note: String? = nil
    var compactValue: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(compactValue ? .title3 : .title2, weight: .black))
                .fontWidth(.condensed)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let note {
                Text(note)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Story Section

private struct StorySection: View {
    let workoutID: String
    let activityType: ActivityType
    /// 상위(ActivityDetailView)에서 해석된 값 — 해석 경로를 한 곳으로 유지한다.
    let effort: ResolvedEffort?
    let appleValue: Int?
    /// 같은 유형 평소 강도 한 줄(없으면 nil) — 상위에서 계산해 넘긴다.
    let baselineNote: String?
    @State private var showEditor = false
    @Query private var stories: [WorkoutStory]
    @Query private var shoes: [Shoe]
    @Query private var allOneLinerEntries: [OneLinerEntry]
    @Environment(\.modelContext) private var modelContext
    private var story: WorkoutStory? { stories.first }
    /// 강도 탭만으로 생성된 스토리(메모·사진 없음)는 일기 없음으로 본다.
    private var hasJournal: Bool { story?.hasContent ?? false }
    private var selectedShoe: Shoe? {
        guard let sid = story?.shoeID else { return nil }
        return shoes.first { $0.id.uuidString == sid }
    }
    /// 스토리에 존재하지 않는 photo UUID를 가진 OneLinerEntry를 DB에서 삭제.
    private func cleanupOrphanedEntries() {
        // 스토리가 없거나 사진 관계가 아직 로드되지 않았으면(nil) 아무것도 지우지 않는다.
        // nil을 "유효한 사진 없음"으로 취급하면 멀쩡한 엔트리가 삭제된다.
        guard let s = story, let photos = s.photos else { return }
        let validPhotoUUIDs = Set(photos.sorted { $0.index < $1.index }.map { $0.photoUUID })
        let orphaned = allOneLinerEntries.filter { entry in
            guard entry.workoutID == workoutID,
                  let ref = entry.mediaRef, ref.hasPrefix("photo:") else { return false }
            let uuid = String(ref.dropFirst("photo:".count))
            return !validPhotoUUIDs.contains(uuid)
        }
        guard !orphaned.isEmpty else { return }
        orphaned.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    init(workoutID: String, activityType: ActivityType, effort: ResolvedEffort?, appleValue: Int?,
         baselineNote: String? = nil) {
        self.workoutID = workoutID
        self.activityType = activityType
        self.effort = effort
        self.appleValue = appleValue
        self.baselineNote = baselineNote
        let wid = workoutID
        _stories = Query(filter: #Predicate<WorkoutStory> { $0.workoutID == wid })
        _allOneLinerEntries = Query(filter: #Predicate<OneLinerEntry> { $0.workoutID == wid })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !shoes.isEmpty {
                shoePicker
            }
            if activityType == .running {
                effortCard
            }
            HStack {
                Label(AppLanguage.shared.s("오늘의 러닝 일기", "Running Journal"), systemImage: "quote.bubble")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showEditor = true
                } label: {
                    Label(hasJournal ? AppLanguage.shared.s("편집", "Edit") : AppLanguage.shared.s("추가", "Add"),
                          systemImage: hasJournal ? "pencil" : "plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.violet)
                }
            }
            if let s = story, hasJournal {
                StoryDisplay(story: s)
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showEditor) {
            StoryEditorSheet(workoutID: workoutID)
        }
        .task { cleanupOrphanedEntries() }
        .onChange(of: story?.updatedAt) { _, _ in cleanupOrphanedEntries() }
    }

    private var shoePicker: some View {
        Menu {
            Button {
                assignShoe(nil)
            } label: {
                if selectedShoe == nil {
                    Label(AppLanguage.shared.s("없음", "None"), systemImage: "checkmark")
                } else {
                    Text(AppLanguage.shared.s("없음", "None"))
                }
            }
            ForEach(shoes) { shoe in
                Button {
                    assignShoe(shoe)
                } label: {
                    if selectedShoe?.id == shoe.id {
                        Label(shoe.displayName, systemImage: "checkmark")
                    } else {
                        Text(shoe.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "shoe.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(selectedShoe != nil ? Theme.violet : .secondary)
                Text(selectedShoe?.displayName ?? AppLanguage.shared.s("신발 선택", "Select Shoe"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectedShoe != nil ? .white : .secondary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        selectedShoe != nil ? Theme.violet.opacity(0.35) : Color.white.opacity(0.07),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func assignShoe(_ shoe: Shoe?) {
        let newID = shoe?.id.uuidString
        if let s = story {
            s.shoeID = newID
        } else if let newID {
            let s = WorkoutStory(workoutID: workoutID)
            s.shoeID = newID
            modelContext.insert(s)
        }
        try? modelContext.save()
    }

    private var effortCard: some View {
        EffortScaleView(
            resolved: effort,
            appleValue: appleValue,
            onSet: { setEffort($0) },
            onResetToApple: { setEffort(nil) },
            baselineNote: baselineNote
        )
    }

    private func setEffort(_ value: Int?) {
        if let s = story {
            // updatedAt은 갱신하지 않는다 — 강도 최신성은 effortUpdatedAt이 담고,
            // updatedAt은 cleanupOrphanedEntries(삭제 경로) 트리거이기 때문.
            s.effortRPE = value
            s.effortUpdatedAt = value == nil ? nil : Date()
        } else if let value {
            let s = WorkoutStory(workoutID: workoutID)
            s.effortRPE = value
            s.effortUpdatedAt = Date()
            modelContext.insert(s)
        }
        try? modelContext.save()
    }
}

private struct StoryDisplay: View {
    let story: WorkoutStory

    private var photos: [UIImage] { story.allPhotoImages }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 기분 칩은 운동 강도 입력과 중복되어 제거. 미니미 갱신 버튼만 남긴다.
            #if canImport(ImagePlayground)
            if #available(iOS 18.2, *), let photo = photos.first {
                HStack {
                    Spacer()
                    MiniMeUpdateButton(storyPhoto: photo)
                }
            }
            #endif
            if !story.memo.isEmpty {
                Text(story.memo)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(4)
            }
            if photos.count >= 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { _, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 130, height: 130)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .clipped()
                        }
                    }
                }
                .frame(height: 130)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - OneLinerGroup

/// 같은 텍스트를 공유하는 entry 묶음. 리스트에서 한 줄로 표시.
private struct OneLinerGroup: Identifiable {
    /// 중복 제거 키 = 트리밍된 텍스트
    let id: String
    /// 대표 entry (최신) — 폰트·색·미디어삭제 여부 결정
    let representative: OneLinerEntry
    /// 이 그룹에 속한 전체 entry
    let entries: [OneLinerEntry]

    /// 사진·영상에 연결된 entry 수 (nil mediaRef 제외)
    var photoCount: Int { entries.filter { $0.mediaRef != nil }.count }
}

// MARK: - OneLinerListDisplay

private struct OneLinerListDisplay: View {
    let entries: [OneLinerEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var recentlyDeleted: [OneLinerEntry] = []
    @State private var showUndo = false
    @State private var groupToConfirm: OneLinerGroup?

    // entries는 createdAt 오름차순 — 첫 등장 순서를 그룹 순서로 유지
    private var groups: [OneLinerGroup] {
        var seen  = Set<String>()
        var order = [String]()
        var map   = [String: [OneLinerEntry]]()
        for entry in entries {
            let key = entry.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if seen.insert(key).inserted { order.append(key) }
            map[key, default: []].append(entry)
        }
        return order.compactMap { key -> OneLinerGroup? in
            guard let group = map[key], !group.isEmpty else { return nil }
            let rep = group.max(by: { $0.createdAt < $1.createdAt })!
            return OneLinerGroup(id: key, representative: rep, entries: group)
        }
    }

    // List는 ScrollView 안에서 자체 높이 계산을 못함 → 명시적으로 지정
    private var listHeight: CGFloat {
        let twoLine = groups.filter { $0.id.contains("\n") || $0.id.count > 20 }.count
        return CGFloat(groups.count - twoLine) * 54 + CGFloat(twoLine) * 72
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(groups) { group in
                    OneLinerGroupRow(group: group)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 14))
                        .swipeActions(edge: .trailing, allowsFullSwipe: group.entries.count == 1) {
                            Button(role: .destructive) { requestDelete(group) } label: {
                                Label(AppLanguage.shared.s("삭제", "Delete"), systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: listHeight)

            if showUndo {
                HStack(spacing: 0) {
                    Text(AppLanguage.shared.s("삭제됨  ·  ", "Deleted  ·  "))
                        .foregroundStyle(.white)
                    Button(AppLanguage.shared.s("되돌리기", "Undo")) { undoDelete() }
                        .foregroundStyle(Theme.violet)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "26262E"))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.2), value: showUndo)
        .alert(
            AppLanguage.shared.s("문구 삭제", "Delete One-Liner"),
            isPresented: Binding(
                get: { groupToConfirm != nil },
                set: { if !$0 { groupToConfirm = nil } }
            ),
            presenting: groupToConfirm
        ) { group in
            Button(AppLanguage.shared.s("모두 삭제", "Delete All"), role: .destructive) {
                commitDelete(group)
            }
            Button(AppLanguage.shared.s("취소", "Cancel"), role: .cancel) {}
        } message: { group in
            let n = group.entries.count
            Text(AppLanguage.shared.s(
                "사진 \(n)장에 적용된 문구예요. 모두 삭제할까요?",
                "Applied to \(n) photos. Delete all?"
            ))
        }
    }

    private func requestDelete(_ group: OneLinerGroup) {
        if group.entries.count == 1 {
            // 단일 항목: 즉시 삭제 + 3초 undo
            commitDelete(group)
            showUndo = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                showUndo = false
            }
        } else {
            // 다중 항목: 확인 다이얼로그
            groupToConfirm = group
        }
    }

    private func commitDelete(_ group: OneLinerGroup) {
        recentlyDeleted = group.entries
        group.entries.forEach { modelContext.delete($0) }
        try? modelContext.save()
        groupToConfirm = nil
    }

    private func undoDelete() {
        recentlyDeleted.forEach { modelContext.insert($0) }
        try? modelContext.save()
        showUndo = false
        recentlyDeleted = []
    }
}

// MARK: - OneLinerGroupRow

private struct OneLinerGroupRow: View {
    let group: OneLinerGroup

    private var rep: OneLinerEntry { group.representative }

    private var mediaDeleted: Bool {
        rep.phAssetLocalIdentifier != nil && !rep.isPHAssetAvailable
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(mediaDeleted
                      ? Color.orange.opacity(0.7)
                      : rep.textColor.color.opacity(rep.textColor == .white ? 0.55 : 0.85))
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(rep.previewText)
                    .font(.custom(rep.font.fontName, size: 17))
                    .foregroundStyle(rep.textColor.color)
                    .lineLimit(3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                // 2장 이상 사진에 적용된 경우 병기
                if group.photoCount >= 2 {
                    Text(AppLanguage.shared.s("사진 \(group.photoCount)장", "\(group.photoCount) photos"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if mediaDeleted {
                    Text(AppLanguage.shared.s("원본이 삭제되었어요", "Original deleted"))
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }
        }
    }
}

private struct StoryEditorSheet: View {
    let workoutID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var stories: [WorkoutStory]
    @Query private var oneLinerEntries: [OneLinerEntry]
    private var existingStory: WorkoutStory? { stories.first }

    @State private var memo = ""
    @State private var photoImages: [UIImage] = []
    /// photoImages와 1:1 병렬 배열 — 기존 사진은 원본 UUID 보존, 신규 사진은 새 UUID 부여.
    @State private var photoUUIDs: [String] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    private let maxPhotos = 10

    init(workoutID: String) {
        self.workoutID = workoutID
        let wid = workoutID
        _stories = Query(filter: #Predicate<WorkoutStory> { $0.workoutID == wid })
        _oneLinerEntries = Query(filter: #Predicate<OneLinerEntry> { $0.workoutID == wid })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        memoField
                        photoSection
                    }
                    .padding(16)
                }
            }
            .navigationTitle(AppLanguage.shared.s("러닝 일기", "Running Journal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("취소", "Cancel")) { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguage.shared.s("저장", "Save")) { save(); dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.violet)
                }
            }
            .task { loadExisting() }
        }
    }


    private var memoField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLanguage.shared.s("한줄 메모", "Note"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(AppLanguage.shared.s("오늘의 러닝은...", "How was today's run?"), text: $memo, axis: .vertical)
                .lineLimit(1...4)
                .padding(14)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppLanguage.shared.s("사진", "Photos"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(photoImages.count)/\(maxPhotos)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !photoImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photoImages.enumerated()), id: \.offset) { idx, img in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .clipped()
                                Button {
                                    if idx < photoUUIDs.count { photoUUIDs.remove(at: idx) }
                                    photoImages.remove(at: idx)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white)
                                        .background(Color.black.opacity(0.5), in: Circle())
                                }
                                .padding(5)
                            }
                        }
                    }
                }
                .frame(height: 130)
            }

            if photoImages.count < maxPhotos {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: maxPhotos - photoImages.count,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(
                        photoImages.isEmpty ? AppLanguage.shared.s("사진 추가", "Add Photo") : AppLanguage.shared.s("더 추가", "Add More"),
                        systemImage: photoImages.isEmpty ? "photo.badge.plus" : "plus.square"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.violet)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.violet.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .onChange(of: pickerItems) { _, items in
                    Task {
                        var loaded: [UIImage] = []
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let img = UIImage(data: data) {
                                loaded.append(img)
                            }
                        }
                        let available = maxPhotos - photoImages.count
                        let addCount = min(loaded.count, available)
                        photoImages.append(contentsOf: loaded.prefix(addCount))
                        photoUUIDs.append(contentsOf: (0..<addCount).map { _ in UUID().uuidString })
                        pickerItems = []
                    }
                }
            }
        }
    }

    private func loadExisting() {
        guard let s = existingStory else { return }
        memo = s.memo
        photoImages = s.allPhotoImages
        photoUUIDs = s.sortedPhotoUUIDs
    }

    private func save() {
        // 저장 시 UUID 보존: 기존 사진은 원본 UUID 유지, 신규 사진은 새 UUID 사용.
        // 이렇게 하면 OneLinerEntry.mediaRef 링크가 깨지지 않는다.
        let makePhoto: (Int, UIImage) -> StoryPhoto? = { idx, img in
            guard let data = img.jpegData(compressionQuality: 0.75) else { return nil }
            let uuid = idx < self.photoUUIDs.count ? self.photoUUIDs[idx] : UUID().uuidString
            return StoryPhoto(data: data, index: idx, uuid: uuid)
        }
        if let s = existingStory {
            // 삭제된 사진의 OneLinerEntry 제거: 기존 UUID 중 새 목록에 없는 것을 찾아 삭제.
            let oldUUIDs = s.sortedPhotoUUIDs
            let newUUIDs = Set(photoUUIDs.prefix(photoImages.count))
            for oldUUID in oldUUIDs where !newUUIDs.contains(oldUUID) {
                let ref = "photo:\(oldUUID)"
                if let entry = oneLinerEntries.first(where: { $0.mediaRef == ref }) {
                    modelContext.delete(entry)
                }
            }
            // StoryPhoto 교체 (UUID는 위에서 보존됨)
            for photo in s.photos ?? [] { modelContext.delete(photo) }
            s.photos = nil
            let newPhotos = photoImages.enumerated().compactMap { makePhoto($0.offset, $0.element) }
            newPhotos.forEach { modelContext.insert($0) }
            s.photos = newPhotos.isEmpty ? nil : newPhotos
            s.memo = memo
            s.updatedAt = Date()
        } else {
            // 기분(mood)은 운동 강도 입력과 중복되어 UI에서 제거 — 모델 필드는 CloudKit 호환을 위해 유지(기본값 .okay)
            let story = WorkoutStory(workoutID: workoutID, memo: memo)
            modelContext.insert(story)
            let newPhotos = photoImages.enumerated().compactMap { makePhoto($0.offset, $0.element) }
            newPhotos.forEach { modelContext.insert($0) }
            story.photos = newPhotos.isEmpty ? nil : newPhotos
        }
        try? modelContext.save()
    }
}

// MARK: - Race Detection Banner

private struct RaceDetectionBanner: View {
    let suggestion: RaceSuggestion?   // nil → manual prompt; weak → suggest candidate(s)
    let activityID: UUID
    let activityDistanceKm: Double
    let activityDate: Date
    let onConfirmed: () -> Void
    let onDismissed: () -> Void

    @Environment(RaceDetector.self) private var detector
    @State private var showManualSheet = false

    // All candidates for multi-pick UI
    private var allCandidates: [BundledRace] {
        guard let s = suggestion else { return [] }
        return [s.primary] + s.alternatives
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let s = suggestion {
                weakSuggestionContent(suggestion: s)
            } else {
                manualPromptContent()
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.violet.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, 16)
        .sheet(isPresented: $showManualSheet) {
            ManualRaceSheet(
                distanceKm: activityDistanceKm,
                onSave: { name in
                    detector.addManual(activityID: activityID, name: name,
                                       distanceKm: activityDistanceKm, date: activityDate)
                    onConfirmed()
                },
                onCancel: {
                    detector.markAsNotRace(activityID: activityID)
                    onDismissed()
                }
            )
        }
    }

    @ViewBuilder
    private func weakSuggestionContent(suggestion: RaceSuggestion) -> some View {
        HStack {
            Label(AppLanguage.shared.s("이 기록 대회였나요?", "Was this a race?"), systemImage: "flag.checkered")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.violet)
            Spacer()
            dismissButton()
        }

        if allCandidates.count == 1 {
            // Single candidate — simple confirm/deny
            Text(suggestion.primary.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Text(suggestion.primary.region + " · " + suggestion.primary.start)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 10) {
                confirmButton(race: suggestion.primary, label: AppLanguage.shared.s("예, 맞아요", "Yes, this one"))
                denyButton(label: AppLanguage.shared.s("아니요", "No"))
            }
        } else {
            // Multiple candidates — vertical pick list (up to 4 shown)
            Text(AppLanguage.shared.s("후보 대회를 선택하거나 직접 입력하세요", "Select a race or enter manually"))
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach(allCandidates.prefix(4)) { race in
                    Button {
                        detector.confirm(activityID: activityID, race: race,
                                         activityDistanceKm: activityDistanceKm)
                        onConfirmed()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(race.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(race.region)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.violet.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                Button { showManualSheet = true } label: {
                    Text(AppLanguage.shared.s("직접 입력", "Enter Manually"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.violet)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Theme.violet.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                denyButton(label: AppLanguage.shared.s("아니요", "No"))
            }
        }
    }

    @ViewBuilder
    private func manualPromptContent() -> some View {
        HStack {
            Label(AppLanguage.shared.s("이 기록 대회였나요?", "Was this a race?"), systemImage: "flag.checkered")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Spacer()
            Button { showManualSheet = true } label: {
                Text(AppLanguage.shared.s("대회 입력", "Enter Race"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.violet)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.violet.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            dismissButton().padding(.leading, 8)
        }
    }

    @ViewBuilder
    private func confirmButton(race: BundledRace, label: String) -> some View {
        Button {
            detector.confirm(activityID: activityID, race: race,
                             activityDistanceKm: activityDistanceKm)
            onConfirmed()
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Theme.violet)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func denyButton(label: String) -> some View {
        Button {
            detector.markAsNotRace(activityID: activityID)
            onDismissed()
        } label: {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dismissButton() -> some View {
        Button {
            detector.markAsNotRace(activityID: activityID)
            onDismissed()
        } label: {
            Image(systemName: "xmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Manual Race Entry Sheet

private struct ManualRaceSheet: View {
    let distanceKm: Double
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var raceName = ""

    private var formattedDistance: String {
        distanceKm >= 10
            ? String(format: "%.1f km", distanceKm)
            : String(format: "%.2f km", distanceKm)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLanguage.shared.s("대회 이름", "Race Name"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(AppLanguage.shared.s("예: 춘천 마라톤", "e.g. Boston Marathon"), text: $raceName)
                            .padding(14)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "ruler")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(AppLanguage.shared.s("기록 거리: \(formattedDistance)", "Distance: \(formattedDistance)"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle(AppLanguage.shared.s("대회 기록 추가", "Add Race Record"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("취소", "Cancel")) {
                        onCancel()
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguage.shared.s("저장", "Save")) {
                        onSave(raceName)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(raceName.isEmpty ? Color.secondary : Theme.violet)
                    .disabled(raceName.isEmpty)
                }
            }
        }
    }
}

// MARK: - Panel Chart Views

struct SplitsPanelChart: View {
    let splits: [SplitData]
    var compact: Bool = false
    var isLargeDisplay: Bool = false
    var labelScale: CGFloat = 1.0

    private var fastestIdx: Int? {
        splits.indices.min(by: { splits[$0].paceSecPerKm < splits[$1].paceSecPerKm })
    }
    private var minPace: Double { splits.map(\.paceSecPerKm).min() ?? 0 }
    private var maxPace: Double { splits.map(\.paceSecPerKm).max() ?? 0 }
    private var avgPace: Double {
        guard !splits.isEmpty else { return 0 }
        return splits.map(\.paceSecPerKm).reduce(0, +) / Double(splits.count)
    }
    private func barFraction(for pace: Double) -> Double {
        let range = maxPace - minPace
        guard range > 0.5 else { return 0.65 }
        return 0.28 + 0.72 * (pace - minPace) / range
    }

    // MARK: - Grouped splits (≤15km→1km, ≤30km→2km, >30km→3km)

    private var displayGroupSize: Int {
        let km = splits.map(\.distanceM).reduce(0, +) / 1000
        if km <= 15 { return 1 }
        if km <= 30 { return 2 }
        return 3
    }

    private var displaySplits: [SplitData] {
        let g = displayGroupSize
        guard g > 1 else { return splits }
        var result: [SplitData] = []
        var i = 0
        while i < splits.count {
            let end = min(i + g, splits.count)
            let chunk = splits[i..<end]
            let totalDist = chunk.map(\.distanceM).reduce(0, +)
            let totalDur  = chunk.map(\.duration).reduce(0, +)
            result.append(SplitData(
                id: end,
                distanceM: totalDist,
                duration: totalDur,
                avgHeartRate: nil, avgCadence: nil, avgPower: nil,
                avgGroundContactTime: nil, avgStrideLength: nil, avgVerticalOscillation: nil
            ))
            i = end
        }
        return result
    }

    // Row height × count for layout decision
    private static let rowHeight: CGFloat = 12
    private static let rowSpacing: CGFloat = 1

    var body: some View {
        if compact {
            compactLineChart
        } else {
            // 15 rows × (12 + 1) = 195pt ≤ 200pt inner area — no scroll needed up to 15 splits
            let totalHeight = CGFloat(splits.count) * (Self.rowHeight + Self.rowSpacing)
            let needsScroll = totalHeight > 195
            let rows = ForEach(Array(splits.enumerated()), id: \.element.id) { idx, split in
                panelRow(idx: idx, split: split)
            }
            if needsScroll {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Self.rowSpacing) { rows }.padding(10)
                }
            } else {
                VStack(spacing: Self.rowSpacing) { rows }.padding(10)
            }
        }
    }

    // MARK: - Compact vertical bar chart (panel + share card)

    @ViewBuilder
    private var compactLineChart: some View {
        if splits.isEmpty {
            EmptyView()
        } else if isLargeDisplay {
            panelVerticalBarChart
        } else {
            shareCardVerticalBarChart
        }
    }

    // MARK: Panel vertical bar chart

    @ViewBuilder
    private var panelVerticalBarChart: some View {
        let ds: [SplitData] = displaySplits
        let dMax: Double = ds.map(\.paceSecPerKm).max() ?? 0
        let dAvg: Double = ds.isEmpty ? 0 : ds.map(\.paceSecPerKm).reduce(0, +) / Double(ds.count)
        let dFastIdx: Int? = ds.indices.min(by: { ds[$0].paceSecPerKm < ds[$1].paceSecPerKm })
        let dRange: Double = dMax - (ds.map(\.paceSecPerKm).min() ?? 0)
        let paceH:   CGFloat = 16
        let kmH:     CGFloat = 14
        let vPad:    CGFloat = 12  // top + bottom
        let spacing: CGFloat = 5

        GeometryReader { geo in
            let n = max(ds.count, 1)
            let hPad: CGFloat = 14
            let available = geo.size.width - hPad * 2
            let barW: CGFloat = max(14, min(40, (available - spacing * CGFloat(n - 1)) / CGFloat(n)))
            // barH = 막대만의 높이, colH = 페이스 텍스트 + 간격 + 막대 총 컬럼 높이
            let barH  = max(44, geo.size.height - paceH - 3 - kmH - 5 - vPad)
            let colH  = barH + paceH + 3
            let avgH: CGFloat = dRange > 0.5
                ? barH * CGFloat(0.18 + 0.82 * (dMax - dAvg) / dRange)
                : barH * 0.6

            VStack(spacing: 0) {
                // 막대 + 페이스 라벨
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(ds.enumerated()), id: \.element.id) { idx, split in
                        let isFastest  = idx == dFastIdx
                        let isSlower   = split.paceSecPerKm > dAvg
                        let bH: CGFloat = dRange > 0.5
                            ? barH * CGFloat(0.18 + 0.82 * (dMax - split.paceSecPerKm) / dRange)
                            : barH * 0.6
                        let fillGradient = isFastest
                            ? LinearGradient(colors: [Self.panelGoldDark, Self.panelGold],
                                             startPoint: .bottom, endPoint: .top)
                            : isSlower
                            ? LinearGradient(colors: [Color.white.opacity(0.11), Color.white.opacity(0.17)],
                                             startPoint: .bottom, endPoint: .top)
                            : LinearGradient(colors: [Self.panelVioletLo, Self.panelVioletHi],
                                             startPoint: .bottom, endPoint: .top)
                        VStack(spacing: 3) {
                            Spacer(minLength: 0)
                            Text(split.formattedPace)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(isFastest ? Self.panelGold : .white.opacity(0.78))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(height: paceH)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(fillGradient)
                                .frame(width: barW, height: max(bH, 6))
                        }
                        .frame(width: barW, height: colH)
                    }
                }
                .padding(.horizontal, hPad)
                .frame(height: colH)
                .overlay(alignment: .top) {
                    // 평균 페이스 점선 — 전체 폭에 걸쳐 하나만
                    GeometryReader { lineGeo in
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0.5))
                            path.addLine(to: CGPoint(x: lineGeo.size.width, y: 0.5))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 3]))
                        .foregroundStyle(Self.panelKmColor.opacity(0.6))
                    }
                    .frame(height: 1)
                    .padding(.top, colH - avgH)
                    .allowsHitTesting(false)
                }

                // km 라벨
                HStack(spacing: spacing) {
                    ForEach(Array(ds.enumerated()), id: \.element.id) { idx, split in
                        Text(split.distanceM < 990
                             ? String(format: "%.1f", split.distanceM / 1000)
                             : "\(split.id)")
                            .font(.system(size: 10, weight: idx == dFastIdx ? .bold : .regular, design: .rounded))
                            .foregroundStyle(idx == dFastIdx ? Self.panelGold : Self.panelKmColor)
                            .frame(width: barW, height: kmH)
                    }
                }
                .padding(.horizontal, hPad)
                .padding(.top, 5)
            }
            .padding(.vertical, vPad / 2)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Share card vertical bar chart

    @ViewBuilder
    private var shareCardVerticalBarChart: some View {
        let ds: [SplitData] = displaySplits
        let dMin: Double = ds.map(\.paceSecPerKm).min() ?? 0
        let dMax: Double = ds.map(\.paceSecPerKm).max() ?? 0
        let dAvg: Double = ds.isEmpty ? 0 : ds.map(\.paceSecPerKm).reduce(0, +) / Double(ds.count)
        let dFastIdx: Int? = ds.indices.min(by: { ds[$0].paceSecPerKm < ds[$1].paceSecPerKm })
        let dRange: Double = dMax - dMin
        let avgSec = Int(dAvg)
        let avgLabel: String = "avg \(avgSec / 60)'\(String(format: "%02d", avgSec % 60))\""
        GeometryReader { geo in
            let hPad: CGFloat = 8
            let vPad: CGFloat = 4
            let spacing: CGFloat = max(1, 2 * labelScale)
            let n = max(ds.count, 1)
            let available = geo.size.width - hPad * 2
            let barW = max(2, (available - spacing * CGFloat(n - 1)) / CGFloat(n) - 2)
            let paceFs: CGFloat = max(5.5, 7 * labelScale)
            let paceH: CGFloat = paceFs * 4
            let kmH: CGFloat = paceFs + 3
            let chartH = max(15, geo.size.height - paceH - kmH - vPad * 2 - spacing * 2)
            let computedAvgH: CGFloat = dRange > 0.5
                ? chartH * CGFloat(0.18 + 0.82 * (dMax - dAvg) / dRange)
                : chartH * 0.6
            // avg 텍스트 y 위치: 상단패딩 + 페이스라벨 높이 + 간격 + (차트에서 avg선까지)
            let avgTextY: CGFloat = vPad + paceH + spacing + (chartH - computedAvgH) - paceFs

            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(ds.enumerated()), id: \.element.id) { idx, split in
                        let isFastest = idx == dFastIdx
                        let isSlowerAvg = split.paceSecPerKm > dAvg
                        let bH: CGFloat = dRange > 0.5
                            ? chartH * CGFloat(0.18 + 0.82 * (dMax - split.paceSecPerKm) / dRange)
                            : chartH * 0.6
                        let barOpacity: Double = (!isFastest && isSlowerAvg) ? 0.58 : 1.0
                        let fillGradient = isFastest
                            ? LinearGradient(colors: [Self.panelGoldDark, Self.panelGold],
                                             startPoint: .bottom, endPoint: .top)
                            : LinearGradient(colors: [Self.panelVioletLo.opacity(barOpacity),
                                                      Self.panelVioletHi.opacity(barOpacity)],
                                             startPoint: .bottom, endPoint: .top)
                        VStack(spacing: max(1.5, 2 * labelScale)) {
                            Text(split.formattedPace)
                                .font(.system(size: paceFs, weight: .semibold, design: .rounded))
                                .foregroundStyle(isFastest ? Self.panelGold : .clear)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(width: paceH, height: barW + 2)
                                .rotationEffect(.degrees(-90))
                                .frame(width: barW + 2, height: paceH)
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: max(1.5, 2 * labelScale))
                                    .fill(Color.white.opacity(0.07))
                                    .frame(width: barW, height: chartH)
                                RoundedRectangle(cornerRadius: max(1.5, 2 * labelScale))
                                    .fill(fillGradient)
                                    .frame(width: barW, height: max(bH, 4))
                                Rectangle()
                                    .fill(Color.white.opacity(0.28))
                                    .frame(width: barW, height: 0.5)
                                    .offset(y: -computedAvgH)
                            }
                            .frame(width: barW, height: chartH)
                            .clipped()
                            Text(split.distanceM < 990
                                 ? String(format: "%.1f", split.distanceM / 1000)
                                 : "\(split.id)")
                                .font(.system(size: paceFs, weight: isFastest ? .bold : .regular, design: .rounded))
                                .foregroundStyle(isFastest ? Self.panelGold : Self.panelKmColor)
                                .frame(width: barW + 2)
                        }
                    }
                }
                .padding(.horizontal, hPad)
                .padding(.top, vPad)
                .padding(.bottom, vPad)
                .frame(width: geo.size.width, alignment: .bottom)

                // 평균 페이스 라벨 — 평균선 오른쪽 끝 가로 표시
                Text(avgLabel)
                    .font(.system(size: max(5, paceFs - 0.5), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.trailing, hPad + 2)
                    .frame(width: geo.size.width, alignment: .trailing)
                    .offset(y: avgTextY)
            }
        }
    }

    // MARK: - Normal row (앱 내 상세)

    private static let panelGold      = Color(hex: "FFC74D")
    private static let panelGoldDark  = Color(hex: "F2A33C")
    private static let panelVioletHi  = Color(hex: "9B7DFF")
    private static let panelVioletLo  = Color(hex: "6845E8")
    private static let panelTrack     = Color(hex: "26262E")
    private static let panelKmColor   = Color(hex: "6E6E78")
    private static let panelAvgDot    = Color(hex: "7A7A85")

    @ViewBuilder
    private func panelRow(idx: Int, split: SplitData) -> some View {
        let isFastest   = idx == fastestIdx
        let isSlowerAvg = split.paceSecPerKm > avgPace
        let barOpacity  = (!isFastest && isSlowerAvg) ? 0.75 : 1.0
        let fillGradient: LinearGradient = isFastest
            ? LinearGradient(colors: [Self.panelGold, Self.panelGoldDark],
                             startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [Self.panelVioletHi.opacity(barOpacity),
                                      Self.panelVioletLo.opacity(barOpacity)],
                             startPoint: .leading, endPoint: .trailing)

        HStack(spacing: 0) {
            Text(split.distanceM < 990
                 ? String(format: "%.0fm", split.distanceM)
                 : "\(split.id)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(isFastest ? Self.panelGold : Self.panelKmColor)
                .frame(width: 18, alignment: .leading)

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.panelTrack)
                        .frame(height: 6).frame(maxHeight: .infinity)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillGradient)
                        .frame(width: max(8, w * barFraction(for: split.paceSecPerKm)), height: 6)
                        .frame(maxHeight: .infinity)
                    Rectangle()
                        .fill(Self.panelAvgDot.opacity(0.45))
                        .frame(width: 1, height: 10).frame(maxHeight: .infinity)
                        .offset(x: max(0, w * barFraction(for: avgPace) - 0.5))
                }
            }
            .frame(height: Self.rowHeight)
            .padding(.horizontal, 5)

            Text(split.formattedPace)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(isFastest ? Self.panelGold : .white)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - 운동 후 심박수 (회복)

/// 종료 후 3분 심박 — 10초 버킷 min–max 막대, 1분·2분 회복량 라벨. Apple 피트니스의 "운동 후 심박수"와 같은 구도.
struct HRRecoveryPanelChart: View {
    let points: [MRRecoveryPoint]
    let result: MRRecoveryResult

    private struct Bucket: Identifiable {
        let id: Int
        let midSec: Double
        let min: Double
        let max: Double
    }

    private var buckets: [Bucket] {
        let size = 10.0
        let n = Int(MRRecovery.postWindowSec / size)
        return (0..<n).compactMap { i in
            let lo = Double(i) * size, hi = lo + size
            let v = points.filter { $0.offset >= lo && $0.offset < hi }.map { Double($0.bpm) }
            guard !v.isEmpty else { return nil }
            return Bucket(id: i, midSec: (lo + hi) / 2, min: v.min()!, max: v.max()!)
        }
    }

    var body: some View {
        let L = AppLanguage.shared
        let lo = max((buckets.map(\.min).min() ?? 60) - 8, 40)
        let hi = max(buckets.map(\.max).max() ?? 200, result.endHR) + 4
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L.s("운동 후 심박수", "Post-Workout HR"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(L.isEnglish
                     ? String(format: "−%.0f bpm in 1 min", result.hrr1)
                     : String(format: "1분 만에 −%.0f bpm", result.hrr1))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.heartRate)
                Spacer()
            }
            .padding(.horizontal, 12)
            Chart {
                ForEach(buckets) { b in
                    BarMark(x: .value("초", b.midSec),
                            yStart: .value("최저", b.min),
                            yEnd: .value("최고", b.max),
                            width: .fixed(3))
                    .foregroundStyle(Theme.heartRate.opacity(0.85))
                }
                RuleMark(x: .value("1분", 60))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .annotation(position: .top, alignment: .leading) {
                        Text(String(format: "1%@ −%.0f", L.isEnglish ? "m" : "분", result.hrr1))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                if let h2 = result.hrr2 {
                    RuleMark(x: .value("2분", 120))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.white.opacity(0.25))
                        .annotation(position: .top, alignment: .leading) {
                            Text(String(format: "2%@ −%.0f", L.isEnglish ? "m" : "분", h2))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXScale(domain: 0...MRRecovery.postWindowSec)
            .chartXAxis {
                AxisMarks(values: [0, 60, 120, 180]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        if let s = value.as(Double.self) {
                            Text(s == 0 ? (L.isEnglish ? "end" : "종료")
                                        : String(format: L.isEnglish ? "%.0fm" : "%.0f분", s / 60))
                                .font(.caption2)
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            Text("\(Int(v))").font(.caption2).foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                }
            }
            .frame(height: 110)
            .padding(.horizontal, 12)
        }
    }
}

struct HRSeriesPanelChart: View {
    let samples: [(offset: TimeInterval, bpm: Int)]
    var zones: [HRZoneData] = []
    var compact: Bool = false
    var workoutDuration: TimeInterval? = nil
    var labelScale: CGFloat = 1.0

    private struct Bucket: Identifiable {
        let id: Int
        let midMinute: Double
        let min: Double
        let max: Double
        let avg: Double
        let color: Color
    }

    private func zoneColor(for bpm: Double) -> Color {
        guard !zones.isEmpty else { return Theme.heartRate }
        let ibpm = Int(bpm)
        let zone = zones.first { z in
            z.id == zones.last?.id ? ibpm >= z.minBPM : (ibpm >= z.minBPM && ibpm <= z.maxBPM)
        }
        guard let z = zone else { return Theme.heartRate }
        return Theme.hrZoneColor(z.id)
    }

    private var validSamples: [(offset: TimeInterval, bpm: Int)] {
        samples.filter { $0.offset >= 0 }
    }

    private var totalDurationMinutes: Double {
        let sampleMax = validSamples.map(\.offset).max() ?? 1
        let duration = workoutDuration.map { max($0, sampleMax) } ?? sampleMax
        return max(duration, 1) / 60
    }

    private var buckets: [Bucket] {
        guard !validSamples.isEmpty else { return [] }
        let sampleMax = validSamples.map(\.offset).max() ?? 1
        let totalDuration = workoutDuration.map { max($0, sampleMax) } ?? sampleMax
        // always 80 bars; bucket duration scales with run length
        let numBuckets = 80
        let bucketSize = totalDuration / Double(numBuckets)
        return (0..<numBuckets).compactMap { i in
            let lo = Double(i) * bucketSize
            let hi = lo + bucketSize
            let isLast = i == numBuckets - 1
            let vals = validSamples
                .filter { $0.offset >= lo && ($0.offset < hi || (isLast && $0.offset <= hi)) }
                .map { Double($0.bpm) }
            guard !vals.isEmpty else { return nil }
            let avg = vals.reduce(0, +) / Double(vals.count)
            return Bucket(id: i,
                          midMinute: (lo + hi) / 2 / 60,
                          min: vals.min() ?? 0,
                          max: vals.max() ?? 0,
                          avg: avg,
                          color: zoneColor(for: avg))
        }
    }

    private var overallAvg: Double {
        guard !buckets.isEmpty else { return 0 }
        return buckets.map(\.avg).reduce(0, +) / Double(buckets.count)
    }

    private var domainLo: Double {
        let minVal = buckets.map(\.min).min() ?? 60
        return max(minVal - 8, 40)
    }

    private var peakBucketID: Int? {
        buckets.max(by: { $0.max < $1.max })?.id
    }

    private var barWidth: CGFloat { 3 }

    var body: some View {
        let lo = domainLo
        let avg = overallAvg
        let peakID = peakBucketID
        Chart {
            ForEach(buckets) { b in
                BarMark(
                    x: .value("분", b.midMinute),
                    yStart: .value("최저", b.min),
                    yEnd: .value("최고", b.max),
                    width: .fixed(compact ? 2 : barWidth)
                )
                .foregroundStyle(b.color.opacity(0.85))
                .annotation(position: .top, alignment: .center) {
                    if !compact, b.id == peakID {
                        Text("\(Int(b.max))")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            if avg > 0 {
                RuleMark(y: .value("평균", avg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Theme.heartRate.opacity(0.7))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(String(format: "avg %.0f", avg))
                            .font(.system(size: compact ? 9 * labelScale : 9, weight: .medium))
                            .foregroundStyle(Theme.heartRate.opacity(0.8))
                    }
            }
        }
        .chartYScale(domain: lo...(buckets.map(\.max).max().map { $0 + 4 } ?? 200))
        .chartXScale(domain: 0...totalDurationMinutes)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 3 : 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let m = value.as(Double.self) {
                        Text(AppLanguage.shared.isEnglish
                             ? String(format: "%.0fm", m)
                             : String(format: "%.0f분", m))
                            .font(compact ? .system(size: 8 * labelScale) : .caption2)
                            .foregroundStyle(Color.white.opacity(compact ? 0.75 : 0.6))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 3 : 4)) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let v = val.as(Double.self) {
                        Text("\(Int(v))")
                            .font(compact ? .system(size: 8 * labelScale) : .caption2)
                            .foregroundStyle(Color.white.opacity(compact ? 0.80 : 0.6))
                    }
                }
            }
        }
        .padding(compact ? 2 : 12)
    }
}

struct MetricBarPanelChart: View {
    let samples: [(offset: TimeInterval, value: Double)]
    let color: Color
    let unit: String
    let format: String
    var useRangeBar: Bool = false  // true: floating min~max bars (Apple style), false: avg-from-baseline
    var validMin: Double = 0
    var barWidthOverride: CGFloat? = nil
    var compact: Bool = false
    /// 지표 타일 값을 그대로 표시해 두 화면의 평균이 일치하도록 강제. nil이면 차트 샘플 산술 평균 사용.
    var overrideAvg: Double? = nil

    private struct Bucket: Identifiable {
        let id: Int
        let midMinute: Double
        let avg: Double
        let min: Double
        let max: Double
    }

    private var buckets: [Bucket] {
        let src = samples.filter { $0.value > validMin }
        guard !src.isEmpty else { return [] }
        let total = max(src.map(\.offset).max() ?? 1, 1)
        // 80 bars; bucket duration scales with run length
        let count = 80
        let size  = total / Double(count)
        return (0..<count).compactMap { i in
            let lo   = Double(i) * size
            let hi   = lo + size
            let vals = src
                .filter { $0.offset >= lo && ($0.offset < hi || (i == count - 1 && $0.offset <= hi)) }
                .map(\.value)
            guard !vals.isEmpty else { return nil }
            let avg = vals.reduce(0, +) / Double(vals.count)
            return Bucket(id: i, midMinute: (lo + hi) / 2 / 60,
                          avg: avg, min: vals.min() ?? 0, max: vals.max() ?? 0)
        }
    }

    private var barWidth: CGFloat { barWidthOverride ?? 3 }

    private var avgValue: Double? {
        if let ov = overrideAvg { return ov }
        let valid = samples.filter { $0.value > validMin }.map(\.value)
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    private var overallMin: Double? { buckets.map(\.min).min() }
    private var overallMax: Double? { buckets.map(\.max).max() }

    private var domainLo: Double {
        if useRangeBar {
            guard let lo = overallMin, let hi = overallMax else { return max(0, (avgValue ?? 0) * 0.9) }
            let range = max(hi - lo, lo * 0.02)
            return max(0, lo - range * 0.4)
        } else {
            let avgs = buckets.map(\.avg)
            guard let lo = avgs.min(), let hi = avgs.max() else { return max(0, (avgValue ?? 0) * 0.9) }
            let range = max(hi - lo, lo * 0.02)
            return max(0, lo - range * 0.6)
        }
    }

    private var yDomain: ClosedRange<Double> {
        if useRangeBar {
            guard let lo = overallMin, let hi = overallMax else {
                let c = avgValue ?? 0; return max(0, c * 0.9)...(c * 1.1)
            }
            let range = max(hi - lo, lo * 0.02)
            return max(0, lo - range * 0.4)...(hi + range * 0.2)
        } else {
            let avgs = buckets.map(\.avg)
            guard let lo = avgs.min(), let hi = avgs.max() else {
                let c = avgValue ?? 0; return max(0, c * 0.9)...(c * 1.1)
            }
            let range = max(hi - lo, lo * 0.02)
            return max(0, lo - range * 0.6)...(hi + range * 0.2)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            let baseline = domainLo
            Chart {
                ForEach(buckets) { b in
                    BarMark(
                        x: .value("분", b.midMinute),
                        yStart: .value("시작", useRangeBar ? b.min : baseline),
                        yEnd: .value("끝", useRangeBar ? b.max : b.avg),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(color.opacity(0.85))
                }
                if let avg = avgValue {
                    RuleMark(y: .value("평균", avg))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(color.opacity(0.55))
                }
            }
            .chartYScale(domain: yDomain)
            .chartXScale(domain: 0...((buckets.last?.midMinute ?? 1) + 0.5))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: compact ? 3 : 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        if let m = value.as(Double.self) {
                            Text(AppLanguage.shared.isEnglish
                                 ? String(format: "%.0fm", m)
                                 : String(format: "%.0f분", m))
                                .font(compact ? .system(size: 8) : .caption2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: compact ? 3 : 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: format, v))
                                .font(compact ? .system(size: 8) : .caption2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
            .padding(compact ? 6 : 12)

            if let avg = avgValue {
                HStack(spacing: 4) {
                    Text(String(format: format, avg))
                        .font(.system(size: compact ? 9 : 11, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    Text("avg \(unit)")
                        .font(.system(size: compact ? 8 : 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    if useRangeBar, let lo = overallMin, let hi = overallMax {
                        Text("·")
                            .font(.system(size: compact ? 8 : 9))
                            .foregroundStyle(.secondary)
                        Text("\(String(format: format, lo))~\(String(format: format, hi))")
                            .font(.system(size: compact ? 8 : 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, compact ? 8 : 14)
                .padding(.top, compact ? 6 : 10)
            }
        }
    }
}

struct ElevationPanelChart: View {
    let profile: [(distanceKm: Double, altitude: Double)]
    var compact: Bool = false

    private struct Point: Identifiable {
        let id: Int
        let km: Double
        let alt: Double
    }

    // Smooth to ~100 evenly-spaced points; avoids GPS gaps causing empty buckets
    private var points: [Point] {
        guard profile.count > 1 else { return [] }
        let targetCount = min(profile.count, 100)
        let step = max(1, profile.count / targetCount)
        return Swift.stride(from: 0, to: profile.count, by: step).enumerated().map { idx, i in
            Point(id: idx, km: profile[i].distanceKm, alt: profile[i].altitude)
        }
    }

    private var altitudes: [Double] { points.map(\.alt) }

    private var yDomain: ClosedRange<Double> {
        guard let lo = altitudes.min(), let hi = altitudes.max() else { return 0...100 }
        let range = max(hi - lo, 5)
        return (lo - range * 0.5)...(hi + range * 0.2)
    }

    private var baseline: Double {
        guard let lo = altitudes.min(), let hi = altitudes.max() else { return 0 }
        let range = max(hi - lo, 5)
        return lo - range * 0.5
    }

    var body: some View {
        let base = baseline
        Chart {
            ForEach(points) { p in
                AreaMark(
                    x: .value("km", p.km),
                    yStart: .value("바닥", base),
                    yEnd: .value("고도", p.alt)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.elevation.opacity(0.6), Theme.elevation.opacity(0.15)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("km", p.km),
                    y: .value("고도", p.alt)
                )
                .foregroundStyle(Theme.elevation)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: 0...(points.last?.km ?? 1))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 3 : 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let km = value.as(Double.self) {
                        Text(String(format: "%.1fkm", km))
                            .font(compact ? .system(size: 8) : .caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 3 : 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.0fm", v))
                            .font(compact ? .system(size: 8) : .caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(compact ? 6 : 12)
    }
}

struct IntervalPanelChart: View {
    let segments: [IntervalSegment]
    var compact: Bool = false

    private struct Row: Identifiable {
        let id: Int
        let isWork: Bool
        let typeLabel: String      // 준비/운동/회복/정리
        let formattedPace: String?
        let avgHeartRate: Int?
        let avgCadence: Int?
        let barRatio: Double    // 0–1, fastest work interval = 1.0
        let formattedDuration: String
    }

    private func shortLabel(_ stepLabel: String?, isWork: Bool) -> String {
        switch stepLabel {
        case "준비운동": return "준비"
        case "운동":    return "운동"
        case "회복":    return "회복"
        case "정리운동": return "정리"
        default:        return isWork ? "운동" : "회복"
        }
    }

    // Standard interval distances (m) — snap GPS measurement within ±8%
    private static let standardDistances = [
        100, 200, 300, 400, 500, 600, 800,
        1000, 1200, 1500, 1600, 2000, 3000, 4000, 5000
    ]

    private func recognizedDistanceM(_ d: Double) -> Int {
        let tolerance = 0.08
        if let snap = Self.standardDistances.first(where: { abs(Double($0) - d) / Double($0) <= tolerance }) {
            return snap
        }
        // fallback: round to nearest 100m (≥200m) or nearest 50m
        return d >= 200 ? Int((d / 100).rounded()) * 100 : Int((d / 50).rounded()) * 50
    }

    private func formattedRoundedDist(_ d: Double) -> String {
        let r = recognizedDistanceM(d)
        return r >= 1000 ? (r % 1000 == 0 ? "\(r / 1000)km" : String(format: "%.1fkm", Double(r) / 1000)) : "\(r)m"
    }

    // "400m×5회" summary for work intervals
    private var workSummary: String? {
        let allPaces = segments.compactMap(\.paceSecPerKm).sorted()
        let medianPace = allPaces.isEmpty ? nil : allPaces[allPaces.count / 2]

        let workSegs = segments.filter { seg -> Bool in
            if let label = seg.stepLabel { return label == "운동" }
            if let m = medianPace, let p = seg.paceSecPerKm { return p < m }
            return seg.id % 2 == 1
        }
        guard !workSegs.isEmpty else { return nil }

        // group by rounded distance
        var groups: [(dist: String, count: Int)] = []
        for seg in workSegs {
            guard let d = seg.distanceM else { continue }
            let label = formattedRoundedDist(d)
            if let idx = groups.firstIndex(where: { $0.dist == label }) {
                groups[idx].count += 1
            } else {
                groups.append((label, 1))
            }
        }
        guard !groups.isEmpty else { return nil }
        return groups.map { "\($0.dist)×\($0.count)회" }.joined(separator: " · ")
    }

    private var rows: [Row] {
        let allPaces = segments.compactMap(\.paceSecPerKm).sorted()
        let medianPace = allPaces.isEmpty ? nil : allPaces[allPaces.count / 2]
        let fastestPace = allPaces.first   // smallest sec/km = fastest
        let maxDuration = segments.map(\.duration).max() ?? 1

        return segments.map { seg in
            let isWork: Bool
            if let label = seg.stepLabel { isWork = label == "운동" }
            else if let m = medianPace, let p = seg.paceSecPerKm { isWork = p < m }
            else { isWork = seg.id % 2 == 1 }

            let barRatio: Double
            if let pace = seg.paceSecPerKm, let fastest = fastestPace, fastest > 0 {
                barRatio = fastest / pace   // faster = larger ratio = longer bar
            } else {
                barRatio = min(1.0, seg.duration / maxDuration) * 0.35
            }

            return Row(id: seg.id, isWork: isWork,
                       typeLabel: shortLabel(seg.stepLabel, isWork: isWork),
                       formattedPace: seg.formattedPace,
                       avgHeartRate: seg.avgHeartRate,
                       avgCadence: seg.avgCadence,
                       barRatio: barRatio,
                       formattedDuration: seg.formattedDuration)
        }
    }

    private var hasCadence: Bool { segments.contains { $0.avgCadence != nil } }

    // 9pt font line height ~11pt, VStack spacing 0 between rows
    // base = summary(16+pad) + header(12+pad) + vertical padding(16)
    static func requiredHeight(segmentCount: Int, hasSummary: Bool) -> CGFloat {
        let rowH: CGFloat = 11
        let baseH: CGFloat = hasSummary ? 44 : 26
        return baseH + CGFloat(segmentCount) * rowH
    }

    // Fixed sub-column widths — same for header and data rows (guarantees column alignment)
    private let paceW: CGFloat = 30
    private let dotW:  CGFloat = 6
    private let hrW:   CGFloat = 34   // "149bpm" at 9pt
    private let cadW:  CGFloat = 34   // "172spm" at 9pt

    var body: some View {
        GeometryReader { geo in
            let typeW:  CGFloat = 26
            let labelW: CGFloat = paceW + dotW + hrW + (hasCadence ? dotW + cadW : 0)
            let indexW: CGFloat = 14
            let spacing: CGFloat = 6
            let maxBarW = max(20, geo.size.width - indexW - typeW - labelW - spacing * 3 - 24)
            let L = AppLanguage.shared
            let content = VStack(alignment: .leading, spacing: 0) {
                if let summary = workSummary {
                    Text(summary)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.violet)
                        .padding(.bottom, 2)
                }

                // Column header — exact same sub-widths as data rows for alignment
                HStack(spacing: spacing) {
                    Color.clear.frame(width: indexW)
                    Color.clear.frame(width: typeW)
                    Color.clear.frame(width: maxBarW, height: 1)
                    HStack(spacing: 0) {
                        Text(L.s("페이스", "Pace"))
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .frame(width: paceW, alignment: .trailing)
                        Color.clear.frame(width: dotW)
                        Text(L.s("심박수", "HR"))
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .frame(width: hrW, alignment: .trailing)
                        if hasCadence {
                            Color.clear.frame(width: dotW)
                            Text(L.s("케이던스", "Cad"))
                                .lineLimit(1).minimumScaleFactor(0.75)
                                .frame(width: cadW, alignment: .trailing)
                        }
                    }
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white)
                }
                .padding(.bottom, 2)

                ForEach(rows) { row in
                    HStack(spacing: spacing) {
                        // interval index
                        Text("\(row.id)")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: indexW, alignment: .leading)

                        // segment type label
                        Text(row.typeLabel)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(row.isWork ? Theme.violet.opacity(0.9) : Color.white.opacity(0.55))
                            .frame(width: typeW, alignment: .leading)

                        // horizontal bar — 8pt height
                        ZStack(alignment: .leading) {
                            Color.clear.frame(width: maxBarW, height: 8)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(row.isWork ? Theme.violet : Color.white.opacity(0.18))
                                .frame(width: max(4, maxBarW * row.barRatio), height: 8)
                        }

                        // pace · HR · cadence — fixed sub-widths for column alignment
                        HStack(spacing: 0) {
                            if let pace = row.formattedPace {
                                Text(pace)
                                    .foregroundStyle(row.isWork ? .white : Color.white.opacity(0.55))
                                    .frame(width: paceW, alignment: .trailing)
                            } else {
                                Text(row.formattedDuration)
                                    .foregroundStyle(Color.white.opacity(0.55))
                                    .frame(width: paceW, alignment: .trailing)
                            }
                            Text("·")
                                .foregroundStyle(.tertiary)
                                .frame(width: dotW, alignment: .center)
                            Text(row.avgHeartRate.map { "\($0)bpm" } ?? "—")
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .foregroundStyle(row.avgHeartRate != nil
                                    ? Theme.heartRate.opacity(0.85) : Color.secondary)
                                .frame(width: hrW, alignment: .trailing)
                            if hasCadence {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                    .frame(width: dotW, alignment: .center)
                                Text(row.avgCadence.map { "\($0)spm" } ?? "—")
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                    .foregroundStyle(row.avgCadence != nil
                                        ? Theme.cadence.opacity(0.85) : Color.secondary)
                                    .frame(width: cadW, alignment: .trailing)
                            }
                        }
                        .font(.system(size: 9).monospacedDigit())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if compact {
                content
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    content
                }
            }
        }
    }
}

private struct InlineTrendChart: View {
    let metric: TrendMetric
    let data: [(date: Date, value: Double)]
    let age: Int?
    let isMale: Bool?
    let currentValue: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(AppLanguage.shared.s("이번 달 · \(data.count)개 기록", "This month · \(data.count) records"))
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 10)
            chart.padding(12)
        }
    }

    @ViewBuilder
    private var chart: some View {
        if metric == .vo2Max, let a = age, let m = isMale {
            vo2Chart(age: a, isMale: m)
        } else {
            baseChart
        }
    }

    private var baseChart: some View {
        Chart {
            ForEach(data, id: \.date) { pt in
                LineMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .foregroundStyle(Theme.violet).interpolationMethod(.catmullRom)
                PointMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .symbol(HollowCircle()).foregroundStyle(Theme.violet)
                    .symbolSize(data.count > 15 ? 12 : 28)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel().foregroundStyle(Color.secondary).font(.caption2)
            }
        }
    }

    private func vo2Chart(age: Int, isMale: Bool) -> some View {
        let vals = data.map(\.value)
        let dMin = vals.min() ?? 20.0
        let dMax = vals.max() ?? 55.0
        let t = CardioFitnessClassifier.thresholds(age: age, isMale: isMale)
        let yMin = min(dMin - 2, t.belowAvg - 3)
        let yMax = max(dMax + 2, t.high + 3)
        let bands = CardioFitnessClassifier.bands(age: age, isMale: isMale, yMin: yMin, yMax: yMax)
        let startDate = data.map(\.date).min() ?? Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()

        return Chart {
            ForEach(bands) { band in
                RectangleMark(xStart: .value("", startDate), xEnd: .value("", Date()),
                              yStart: .value("", band.low), yEnd: .value("", band.high))
                    .foregroundStyle(band.color.opacity(0.10))
            }
            ForEach(data, id: \.date) { pt in
                LineMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .foregroundStyle(Theme.violet).interpolationMethod(.catmullRom)
                PointMark(x: .value("날짜", pt.date), y: .value(metric.unit, pt.value))
                    .symbol(HollowCircle()).foregroundStyle(Theme.violet).symbolSize(20)
            }
        }
        .chartYScale(domain: yMin...yMax)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel().foregroundStyle(Color.secondary).font(.caption2)
            }
        }
    }
}
