import SwiftUI
import Charts
import SwiftData

// MARK: - File-private data models

private struct WeeklyKm: Identifiable {
    let id: Date
    let label: String
    let km: Double
}

private struct WeeklyMins: Identifiable {
    let id: Date
    let label: String
    let mins: Double
}

private struct PacePoint: Identifiable {
    let id = UUID()
    let date: Date
    let speedKmh: Double   // higher = faster; Y axis naturally shows faster = higher
    let paceFormatted: String
}

private struct DayCell: Identifiable {
    let id: Date           // start of day
    let km: Double
    let isFuture: Bool
}

private struct WeekColumn: Identifiable {
    let id: Date           // Monday of this week
    let days: [DayCell]    // 7 elements: Mon[0] … Sun[6]
}

private struct PREntry: Identifiable {
    let id: String         // "5K", "10K", "half", "full"
    let label: String      // display label
    let activity: Activity
    var isNew: Bool { Date().timeIntervalSince(activity.date) < 30 * 86400 }
}

private struct MilestoneEvent: Identifiable {
    enum Kind { case first, distance, cumulative, longest }
    let id: String
    let date: Date
    let kind: Kind
    let title: String
    let detail: String
}

private struct BodyMassPeakData {
    let currentKg: Double
    let peakKg: Double
    let peakDate: Date
    let diffKg: Double   // peakKg - currentKg (양수 = 최고치보다 가볍다)
    let diffPct: Double  // |diff| / peak * 100
    let isLighter: Bool  // currentKg < peakKg
}

private struct BodyMassStabilityData {
    let minKg: Double
    let maxKg: Double
    let stdDev: Double
    let count: Int
}

// MARK: - GrowthView

struct GrowthView: View {
    var manager: HealthKitManager
    @EnvironmentObject private var engine: MREngineStore
    @Environment(RaceDetector.self) private var raceDetector
    @Query private var allArchives: [RaceArchive]
    @Query private var allStories: [WorkoutStory]

    @State private var showDaily: Bool = true
    @State private var dailyMonth: Date = Date()
    /// 러닝 흐름 카드가 그리는 버킷(일/주).
    @State private var recordBarsCache: [RecordBar] = []
    @State private var selectedTrend: TrendMetric? = nil
    @State private var showBodyMass = false
    @State private var showBodyFat = false
    @AppStorage("distanceUnitMiles") private var useMiles = false

    // Cached chart data — refreshed only when activities change
    @State private var weeklyKmsCache: [WeeklyKm] = []
    @State private var weeklyMinsCache: [WeeklyMins] = []
    @State private var pacePointsCache: [PacePoint] = []
    @State private var heatmapColumnsCache: [WeekColumn] = []
    @State private var metricAnalyses: [TrendMetric: (direction: TrendDirection, changeRatio: Double)] = [:]
    @State private var metricDataPoints: [TrendMetric: [(date: Date, value: Double)]] = [:]
    @State private var weeklySparkData: [(metric: TrendMetric, points: [(date: Date, value: Double)])] = []
    @State private var paceAnalysisCache: (direction: TrendDirection, changeRatio: Double) = (.insufficient, 0)
    @State private var hrAnalysisCache: (direction: TrendDirection, changeRatio: Double) = (.insufficient, 0)
    @State private var thisWeekLongestKmCache: Double = 0
    @State private var weeklyPatternCache: [WeeklyPattern] = []
    @State private var weeklyCommentText: String = ""
    @State private var weeklyCommentCache: [String: String] = [:]
    @State private var isRefreshingMetrics = false
    @State private var lastAnalyzedRunCount: Int = -1
    @State private var formObservation: (text: String, basis: String, isStable: Bool)? = nil
    /// 운동 후 심박 회복 관찰 — 좋아진 쪽만 문구가 생긴다 (MRRecovery.observation)
    @State private var recoveryObservation: (text: String, basis: String)? = nil
    /// 같은 강도(본인 이지런 기준 이하) 페이스 추이 관찰 — 빨라진 쪽만 (EffortPaceTrend.observation)
    @State private var effortPaceObservation: (text: String, basis: String)? = nil
    @State private var formComputedForRunCount: Int? = nil  // ■2: 동일 run count 재계산 방지
    @State private var lastChartRefreshCount: Int = -1
    @State private var runsCache: [Activity] = []
    /// 유형별 평소 강도 표 — 강도 입력이 바뀔 때만 다시 계산한다(body 평가 비용 회피).
    @State private var effortTypeRowsCache: [EffortBaseline.TypeSummary] = []
    @State private var prEntriesCache: [PREntry] = []
    @State private var journeyMilestonesCache: [MilestoneEvent] = []
    @State private var thisWeekRunCountCache: Int = 0
    @State private var growthInsightBannerText: String? = nil
    @State private var showWeeklyShareCard = false
    @State private var showMileageStreakShareCard = false
    @State private var displayGaps: [(start: Date, end: Date, days: Int, prePace: Double?, postPace: Double?)] = []
    @State private var isGapExpanded: Bool = false

    // MARK: 몸의 변화 섹션 state
    @State private var bodyMassPeakData: BodyMassPeakData? = nil
    @State private var bodyMassStabilityData: BodyMassStabilityData? = nil
    @State private var shouldShowHealthStory: Bool = false
    @State private var healthStoryIndex: Int = 0
    @State private var healthStoryRecorded: Bool = false

    private static let healthStoryIndexKey = "mimo.bodyChange.healthStory.index"

    // 자료 구조가 바뀔 때만 올린다. 템플릿 문구 변경은 stableHash가 자동 처리.
    private static let weeklyCommentVersion = 11
    private static let debugBypassCache = false
    private static let debugBypassDailyLimit = false

    /// FNV-1a 32-bit — Swift의 hashValue는 실행마다 달라지므로 쓰지 않는다.
    private static func stableHash(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return h
    }
    // 2026-07 검증: 온디바이스 모델이 3요소 총평 규격을 재시도에도 못 맞춤
    // (감사합니다 종결, 동일 출력 반복). 템플릿 확정. 모델 개선 시 true로 재평가.
    private static let useAITotalComment = false
    @State private var weeklySummary: WeeklySummary? = nil
    @State private var lastWeeklyCommentInputKey: String = ""

    private static let weekLabelFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
    private static let monthLabelFormatterKo: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M월"; return f
    }()
    private static let monthLabelFormatterEn: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM"; return f
    }()
    private static var monthLabelFormatter: DateFormatter {
        AppLanguage.shared.isEnglish ? monthLabelFormatterEn : monthLabelFormatterKo
    }

    private var runs: [Activity] { runsCache }

    private static let _mondayCal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2  // Monday
        c.locale = Locale.current
        return c
    }()
    private var mondayCal: Calendar { Self._mondayCal }

    private func refreshChartCache() {
        let currentCount = manager.activities.count
        guard currentCount != lastChartRefreshCount else { return }
        lastChartRefreshCount = currentCount
        runsCache        = manager.activities.filter { $0.type == .running }
        weeklyKmsCache   = weeklyKms()
        weeklyMinsCache  = weeklyMins()
        refreshRecordBars()
        pacePointsCache  = pacePoints()
        let cols = heatmapColumns()
        heatmapColumnsCache = cols

        // Pace/HR trend — 날짜 기반(-14일): 6개 폼 지표·구성 게이트와 동일 윈도우
        let trendWindow14 = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        let paceHrWindow = runs.filter { $0.date >= trendWindow14 }
        let paceSamples = paceHrWindow.compactMap { $0.paceSecPerKm }.map { Double($0) }
        paceAnalysisCache = trendDirection(values: Array(paceSamples.reversed()))
        let hrSamples = paceHrWindow.compactMap { $0.avgHeartRate }.map { Double($0) }
        hrAnalysisCache = trendDirection(values: Array(hrSamples.reversed()))

        // Longest run this week
        let cal = mondayCal
        let nowComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        thisWeekLongestKmCache = runs
            .filter { cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.date) == nowComps }
            .map { $0.distance / 1000 }
            .max() ?? 0

        let ws = cal.date(from: nowComps) ?? Date()
        thisWeekRunCountCache   = runsCache.filter { $0.date >= ws }.count
        prEntriesCache          = prEntries()
        journeyMilestonesCache  = journeyMilestones()
        refreshEffortTypeRows()
        growthInsightBannerText = computeGrowthInsightText()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if manager.isLoading && manager.activities.isEmpty {
                    ProgressView().tint(Theme.violet)
                } else if runs.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // ⚠ 성장 탭의 주어는 **사용자**다. 맨 위가 앱의 성적표면 안 된다.
                            //   다만 대회 직후 2주는 "앱이 맞췄나"가 가장 궁금한 시점이므로 위로 올린다.
                            weekSummarySection
                            MRAdviceCardView()
                                // 상세·유형 캐시가 갱신되면 롱런 피로 요약을 다시 넘긴다 (메모는 이미 무효화됨).
                                // ⚠ 바깥 modifier 체인에 onChange를 하나 더 붙이면 타입체커가 시간 초과한다 — 여기에 둔다.
                                .onChange(of: manager.workoutTypeRevision) { _, _ in
                                    engine.updateAdvice(strengthPerWeek: manager.strengthPerWeek4w,
                                                        fatigue: manager.longRunFatigueSummaries())
                                }
                            heatmapSection
                            weeklySection
                                // 강도 입력이 바뀌면 강도 의존 캐시(기록 막대·유형별 평소 강도·추세)를 다시 계산
                                .onChange(of: allStories.map(\.effortRPE)) { _, _ in
                                    effortInputsChanged()
                                }
                            // 훈련 강도 부하 상태 카드는 제거 — 같은 7일 부하는 활동 상세 퍼포먼스 카드가 보여준다.
                            if !effortTypeRowsCache.isEmpty {
                                EffortTypeBaselineCard(rows: effortTypeRowsCache)
                            }
                            metricTrendsSection
                            MRHealthMetricsView(m: engine.healthMetrics)
                            bodyChangeSectionView
                            gapSection
                            MRDriftView(drift: engine.drift)
                            prSection
                            journeySection
                            MRBacktestView(rows: engine.backtest, confirmedMatches: Array(raceDetector.matches.values), archives: allArchives)
                            Spacer(minLength: 32)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    .onAppear {
                        // 상세에서 강도를 고치고 돌아오거나(활동 수 불변) 앱을 새로 켠 직후(.task가 동기화보다 먼저 돈 경우)에도
                        // 강도 의존 캐시(유형별 평소 강도·기록 막대)가 최신 입력을 반영하도록 동기화 뒤 재계산
                        manager.syncUserEfforts(from: allStories)
                        refreshRecordBars()
                        refreshEffortTypeRows()
                        // refreshBacktest 진입부 폴백용 — 모든 호출 경로에서 대회 목록 보장
                        engine.persistedMatchesProvider = { [manager] in manager.persistedConfirmedMatches() }
                        // raceDetector 미준비 → 영속 키 폴백. 준비 완료 → onChange가 정식 목록으로 재실행
                        let matches: [PersistedRaceMatch] = raceDetector.isReady
                            ? Array(raceDetector.matches.values)
                            : manager.persistedConfirmedMatches()
                        engine.updateConfirmedMatches(matches, raceDetectorReady: raceDetector.isReady)
                        engine.computeBacktestIfNeeded()
                        engine.updateAdvice(strengthPerWeek: manager.strengthPerWeek4w,
                                            fatigue: manager.longRunFatigueSummaries())
                        if !engine.runs.isEmpty {
                            let gaps = Self.computeDisplayGaps(runs: engine.runs)
                            displayGaps = gaps
                        }
                    }
                }
            }
            .navigationTitle(AppLanguage.shared.s("성장", "Growth"))
            .navigationBarTitleDisplayMode(.large)
        }
        .onChange(of: raceDetector.isReady) { _, ready in
            guard ready else { return }
            // raceDetector 로드 완료 후 대회 목록을 갱신 — 캐시 키가 바뀌면 백테스트 자동 재계산
            engine.updateConfirmedMatches(Array(raceDetector.matches.values), raceDetectorReady: true)
        }
        .onChange(of: manager.activities.count) { _, _ in
            Task { refreshChartCache(); await refreshMetricAnalyses() }
        }
        // engine.runs가 나중에 채워질 때(race condition) 폼 관찰 재시도
        .onChange(of: engine.runs.count) { _, newCount in
            guard newCount > 0 else { return }
            let gaps = Self.computeDisplayGaps(runs: engine.runs)
            displayGaps = gaps
            // 로그는 computeDisplayGaps 내부에서 출력됨
            guard formComputedForRunCount != newCount else { return }
            Task { await refreshFormObservation() }
        }
        // engine 준비 완료 시 패턴·코멘트 재계산 (engine.streakWeeks 등이 0이었을 수 있음)
        .onChange(of: engine.isReady) { _, isReady in
            guard isReady else { return }
            lastAnalyzedRunCount = -1
            Task { refreshChartCache(); await refreshMetricAnalyses() }
        }
        .onChange(of: dailyMonth) { _, _ in
            refreshRecordBars()
        }
        .onChange(of: AppLanguage.shared.isEnglish) { _, _ in
            // 언어가 바뀌면 캐시된 현지화 문자열을 즉시 재계산한다.
            journeyMilestonesCache = journeyMilestones()
            prEntriesCache = prEntries()
            // 패턴 코멘트: 가드를 초기화하고 재분석
            lastAnalyzedRunCount = -1
            lastWeeklyCommentInputKey = ""
            Task { await refreshMetricAnalyses() }
            // 폼 관찰 텍스트
            formComputedForRunCount = 0
            Task { await refreshFormObservation() }
        }
        .task {
            manager.syncUserEfforts(from: allStories)   // 강도 의존 캐시 계산 전에 사용자 입력부터
            refreshChartCache()
            await checkBodyDataAvailability()
            await refreshMetricAnalyses()
        }
        .onAppear {
            // .task는 첫 진입 1회만 실행 — 탭 재진입 시 신체 측정·몸의 변화 최신화
            // ⚠ loadBodyChangeSectionData는 여기서만 호출한다.
            //   .task에서도 호출하면 두 Task가 경쟁하여 healthStory를 기록한 직후
            //   두 번째 완료 Task가 canShow=false를 덮어쓸 수 있다.
            MRAdviceLogStore.runMigrationIfNeeded()
            // 일간 모드 기본 창은 "오늘까지 최근 30일" — 자정을 넘겨 탭에 다시 들어오면 창을 다시 잡는다.
            if showDaily, recordBarsCache.first?.id != dailyWindow(for: dailyMonth).start {
                refreshRecordBars()
            }
            Task { await checkBodyDataAvailability() }
            Task { await loadBodyChangeSectionData() }
        }
        .sheet(item: $selectedTrend) { metric in
            MetricTrendView(
                metric: metric,
                currentValue: nil,
                manager: manager,
                age: userAge,
                isMale: manager.userIsMale
            )
        }
        .sheet(isPresented: $showMileageStreakShareCard) {
            MileageStreakShareCardScreen(
                bars: recordBarsCache,
                period: recordPeriod,
                windowStart: recordWindow(for: recordPeriod).start,
                windowEnd: recordWindow(for: recordPeriod).end,
                periodLabel: recordPeriodLabel,
                flowComment: recordFlowComment,
                heatmapColumns: shareHeatmapColumns,
                streak: engine.streakWeeks,
                activeDays: activeDaysInHeatmap(columns: heatmapColumnsCache),
                heatmapWeekCount: Self.heatmapWeeks,
                screenTitle: mileageScreenTitle
            )
        }
        .sheet(isPresented: $showWeeklyShareCard) {
            let style = weeklyPatternCache.first.map { weeklyPatternStyle(for: $0.key) }
            WeeklyGrowthShareCardScreen(
                km: weeklyKmsCache.last?.km ?? 0,
                mins: weeklyMinsCache.last?.mins ?? 0,
                count: thisWeekRunCount,
                streak: engine.streakWeeks,
                insightText: weeklyCommentText.isEmpty ? nil : weeklyCommentText,
                insightSymbol: style?.symbol,
                insightColor: style?.color,
                preloadedSparkData: weeklySparkData.isEmpty ? nil : weeklySparkData,
                manager: manager
            )
        }
    }

    // MARK: - Helpers

    private var userAge: Int? {
        guard let comps = manager.userDateOfBirth,
              let year = comps.year else { return nil }
        return Calendar.current.component(.year, from: Date()) - year
    }

    // MARK: - Share card data helpers

    private var shareHeatmapColumns: [ShareHeatmapColumn] {
        heatmapColumnsCache.map { col in
            ShareHeatmapColumn(
                id: col.id,
                days: col.days.map { ShareHeatmapDay(km: $0.km, isFuture: $0.isFuture) }
            )
        }
    }

    // MARK: - 폼 스타일 관찰

    private func computeFormObservation(
        cadData: [(date: Date, value: Double)],
        gctData: [(date: Date, value: Double)]
    ) -> (text: String, basis: String, isStable: Bool)? {
        // engine.runs가 아직 비어있으면 계산하지 않는다.
        // (manager.activities와 engine.runs는 독립된 async 흐름 — race condition 방어)
        guard !engine.runs.isEmpty else {
            #if DEBUG
            print("[폼] engine.runs 미충전 — 스킵 (engine.state=\(engine.state))")
            #endif
            return nil
        }

        // engine.runs에서 유효한 야외 정상 런만 추출 (startOfDay → speed 맵)
        // ⚠ r.date는 startOfDay(midnight)이고,
        //   fetchMetricHistory는 workout.startDate(정확한 시각)를 반환한다.
        //   buildObs에서 pt.date도 startOfDay로 정규화해야 키가 맞는다.
        let cal = Calendar.current
        let speedByDate = mrFormSpeedByDate(engine.runs)
        #if DEBUG
        print("[폼] 호출 runs=\(engine.runs.count) 유효속도맵=\(speedByDate.count)")
        #endif

        func buildObs(_ pts: [(date: Date, value: Double)]) -> [MRFormObs] {
            pts.compactMap { pt in
                let day = cal.startOfDay(for: pt.date)   // 정규화 — fetchMetricHistory는 exact timestamp 반환
                guard let speed = speedByDate[day] else { return nil }
                return MRFormObs(date: day, speedMPerMin: speed, metricValue: pt.value)
            }
        }

        let now = Date()
        // vo는 추세 판정에서 제외 — Apple Watch 측정 오차 MAPE 19%로 신뢰도 낮음
        var shifts: [MRFormShift] = []
        for (metric, obs) in [(mrFormMetrics[1], buildObs(cadData)),
                              (mrFormMetrics[2], buildObs(gctData))] {
            let residuals = mrFormResiduals(obs: obs, asOf: now)
            if let shift = mrFormShift(residuals, metric: metric, asOf: now, obs: obs) {
                shifts.append(shift)
            }
        }

        // 케이던스 이동을 조언 엔진에 넘긴다 — 엔진이 폼 계산을 중복하지 않는다.
        engine.updateAdvice(strengthPerWeek: manager.strengthPerWeek4w,
                            cadenceShift: .some(shifts.first { $0.metric.key == "cadence" }))

        // 최근 3개월 안에 14일 이상 공백이 있으면 추세 판단 불가
        let hasGapInWindow: Bool = {
            let threeMonthsAgo = cal.date(byAdding: .month, value: -3, to: now) ?? .distantPast
            let recent = engine.runs.filter { $0.date >= threeMonthsAgo }.sorted { $0.date < $1.date }
            for i in 0..<(recent.count - 1) {
                let gap = cal.dateComponents([.day], from: recent[i].date, to: recent[i + 1].date).day ?? 0
                if gap >= 14 { return true }
            }
            return false
        }()
        guard let result = mrFormObservation(shifts, hasRecentGap: hasGapInWindow) else { return nil }
        return (text: result.text, basis: result.basis, isStable: result.isStable)
    }

    // MARK: - Sections

    // MARK: - 기록 카드 (거리·시간·부하·페이스 통합)

    private var recordPeriod: RecordPeriod {
        showDaily ? .day : .week
    }

    /// 기록 카드의 x축 창. 일간은 dailyWindow(월 이동), 주간 12주. (월간은 성장 탭에서 쓰지 않는다)
    private func recordWindow(for period: RecordPeriod) -> (start: Date, end: Date) {
        let now = Date()
        switch period {
        case .day:
            return dailyWindow(for: dailyMonth)
        default:
            let cal = mondayCal
            let thisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            let start = cal.date(byAdding: .weekOfYear, value: -11, to: thisWeek) ?? thisWeek
            let end = cal.date(byAdding: .day, value: 7, to: thisWeek) ?? thisWeek
            return (start, end)
        }
    }

    /// 기간·러닝·강도 입력이 바뀔 때만 다시 만든다.
    private func refreshRecordBars() {
        let period = recordPeriod
        let win = recordWindow(for: period)
        let effortOf: (UUID) -> Int? = { [manager] id in manager.effortIndex.resolve(id)?.value }
        recordBarsCache = RecordSeries.bars(
            activities: runsCache,
            effortOf: effortOf,
            start: win.start, end: win.end, period: period
        )
    }

    /// 유형별 평소 강도 표 갱신 — 러닝 캐시·강도 입력이 바뀔 때.
    private func refreshEffortTypeRows() {
        effortTypeRowsCache = EffortBaseline.typeTable(asOf: Date(), history: runsCache,
                                                       index: manager.effortIndex,
                                                       typeOf: manager.workoutTypeLookup())
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                SectionLabel(title: mileageTitle, subtitle: mileageSubtitle)
                Spacer()
                HStack(spacing: 10) {
                    Button { showMileageStreakShareCard = true } label: {
                        Label(AppLanguage.shared.s("흐름 내보내기", "Export Flow"),
                              systemImage: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.violet)
                    periodToggle
                }
            }
            if showDaily {
                dailyMonthNavRow
            }
            recordChartView
        }
    }

    private var mileageTitle: String {
        AppLanguage.shared.s("러닝 흐름", "Running Flow")
    }

    private var mileageScreenTitle: String {
        AppLanguage.shared.s("러닝 흐름", "Running Flow")
    }

    /// 공유 카드에 찍는 기간 라벨 — "최근 30일" / "8월" / "최근 12주"
    private var recordPeriodLabel: String {
        showDaily ? dailyMonthLabel : AppLanguage.shared.s("최근 12주", "Last 12 weeks")
    }

    private var dailyMonthLabel: String {
        let cal = Calendar.current
        if isAtCurrentMonth { return AppLanguage.shared.s("최근 30일", "Last 30 days") }
        let comps = cal.dateComponents([.year, .month], from: dailyMonth)
        if AppLanguage.shared.isEnglish {
            let df = DateFormatter(); df.locale = Locale(identifier: "en_US"); df.dateFormat = "MMMM yyyy"
            return df.string(from: dailyMonth)
        }
        return "\(comps.year ?? 2025)년 \(comps.month ?? 1)월"
    }

    private func isCurrentMonth(_ date: Date) -> Bool {
        let cal = Calendar.current
        let dc = cal.dateComponents([.year, .month], from: date)
        let nc = cal.dateComponents([.year, .month], from: Date())
        return dc.year == nc.year && dc.month == nc.month
    }

    private var isAtCurrentMonth: Bool { isCurrentMonth(dailyMonth) }

    /// 일간 모드 표시 창 — 기본(현재 달)은 **오늘까지 최근 30일** 롤링,
    /// "<"로 뒤로 가면 그 달의 달력 단위. 거리·부하·페이스 세 차트가 같은 창을 쓴다.
    private func dailyWindow(for month: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        if isCurrentMonth(month) {
            let today = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: 1, to: today) ?? today
            let start = cal.date(byAdding: .day, value: -30, to: end) ?? end
            return (start, end)
        }
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let days = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        let end = cal.date(byAdding: .day, value: days, to: start) ?? start
        return (start, end)
    }

    /// 제목 아래 안내 문구는 차트 각주와 중복이라 비운다.
    private var mileageSubtitle: String { "" }

    /// 일/주 전환 — 선택 강조는 브랜드색을 쓴다.
    /// 예전에는 일=Theme.time(노랑), 주=Theme.cadence(청록)로 **지표 의미색**을 끌어다 썼다.
    /// 케이던스를 노랑으로 옮기자 두 칩이 같은 노랑이 돼 버려서 드러난 문제다.
    private var periodToggle: some View {
        let L = AppLanguage.shared
        let isWeekly = !showDaily
        return HStack(spacing: 0) {
            Button { showDaily = true; refreshRecordBars() } label: {
                Text(L.s("일", "D"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(showDaily ? Color.white : Color.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(showDaily ? Theme.violet : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Button { showDaily = false; refreshRecordBars() } label: {
                Text(L.s("주", "W"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isWeekly ? Color.white : Color.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(isWeekly ? Theme.violet : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private var dailyMonthNavRow: some View {
        HStack(spacing: 16) {
            Button {
                dailyMonth = Calendar.current.date(byAdding: .month, value: -1, to: dailyMonth) ?? dailyMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.violet)
            }
            Text(dailyMonthLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Button {
                guard !isAtCurrentMonth else { return }
                dailyMonth = Calendar.current.date(byAdding: .month, value: 1, to: dailyMonth) ?? dailyMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isAtCurrentMonth ? Theme.violet.opacity(0.45) : Theme.violet)
            }
        }
    }

    /// 거리 막대(색 = 그 구간 평균 강도) · 페이스 · 심박을 각자 실제 축으로 위아래로 쌓는 기록 차트.
    private var recordChartView: some View {
        let period = recordPeriod
        let win = recordWindow(for: period)
        return RecordBarChart(
            bars: recordBarsCache,
            period: period,
            start: win.start,
            end: win.end,
            emptyMessage: recordEmptyMessage,
            flowComment: recordFlowComment
        )
    }

    /// 차트 아래 흐름 문장 — 앞뒤 절반 비교 규칙 엔진(`RecordFlowInsight`). 캐시된 버킷만 훑어 가볍다.
    /// 앱 화면 전용이며 공유 카드에는 넣지 않는다.
    private var recordFlowComment: RecordFlowInsight.Result {
        RecordFlowInsight.evaluate(
            .init(bars: recordBarsCache,
                  period: recordPeriod,
                  easyCutoff: manager.easyEffortCutoff() ?? EffortPaceTrend.fallbackCutoff),
            periodLabel: recordPeriodLabel
        )
    }

    private var recordEmptyMessage: String {
        let L = AppLanguage.shared
        switch recordPeriod {
        case .day:
            return isAtCurrentMonth
                ? L.s("최근 30일 러닝 기록이 없어요", "No runs in the last 30 days")
                : L.s("이 달에 러닝 기록이 없어요", "No runs this month")
        case .week:
            return L.s("이번 12주간 러닝 기록이 없어요", "No runs in the last 12 weeks")
        case .month:
            return L.s("최근 12개월간 러닝 기록이 없어요", "No runs in the last 12 months")
        }
    }

    private var heatmapSection: some View {
        let L = AppLanguage.shared
        let columns = heatmapColumnsCache
        let streak = engine.streakWeeks
        let activeDays = activeDaysInHeatmap(columns: columns)
        let weekKm = weeklyKmsCache.last?.km ?? 0
        let prevKm = weeklyKmsCache.dropLast().last?.km ?? 0
        let weekDelta: Double? = prevKm > 0 ? weekKm - prevKm : nil
        let weekCount = thisWeekRunCount

        return VStack(alignment: .leading, spacing: 12) {
            Text(L.s("연속 달리기", "Streak"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            // ⚠ 한 줄 요약 대신 라벨+값 배치 — 글씨 크기를 유지하면서 숫자가 충돌하지 않는다.
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.s("연속", "Streak"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(streak >= 2 ? L.s("\(streak)주", "\(streak)wk") : L.s("1주", "1wk"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.s("최근 \(Self.heatmapWeeks)주간", "\(Self.heatmapWeeks) wks"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(L.s("\(activeDays)일", "\(activeDays)d"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.s("이번 주", "This Week"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(L.s("\(weekCount)회 \(Int(weekKm))km", "\(weekCount)× \(Int(weekKm))km"))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        if let d = weekDelta, abs(d) >= 1 {
                            Text(String(format: "%@%.0f", d >= 0 ? "+" : "", d))
                                .font(.system(size: 12))
                                .foregroundStyle(d >= 0
                                    ? Color(red: 0.30, green: 0.80, blue: 0.55)
                                    : .white.opacity(0.45))
                        }
                    }
                }
                Spacer()
            }
            .padding(.top, 4)

            RunHeatmap(columns: columns)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var thisWeekRunCount: Int { thisWeekRunCountCache }

    private func weekTimeFormatted(_ total: Int) -> String {
        guard total > 0 else { return "--" }
        let h = total / 60
        let m = total % 60
        let L = AppLanguage.shared
        if L.isEnglish { return h > 0 ? "\(h)h \(m)m" : "\(m)m" }
        return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
    }

    private var weekSummarySection: some View {
        let L = AppLanguage.shared
        let km   = weeklyKmsCache.last?.km ?? 0
        let mins = weeklyMinsCache.last?.mins ?? 0
        let count  = thisWeekRunCount
        let streak = engine.streakWeeks

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.s("이번 주", "This Week"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Text(L.s("월요일부터 지금까지", "Monday through today"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "8A8A92"))
                }
                Spacer()
                Button { showWeeklyShareCard = true } label: {
                    Label(L.s("카드 내보내기", "Export Card"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Theme.violet)
                .padding(.top, 4)
            }

            if km == 0 && mins == 0 && count == 0 {
                Text(L.s("이번 주 첫 러닝을 기다리고 있어요", "Waiting for your first run this week"))
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "8A8A92"))
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 8) {
                    WeekStatTile(
                        value: String(format: km >= 10 ? "%.1f km" : "%.2f km", km),
                        label: L.s("거리", "Distance")
                    )
                    WeekStatTile(
                        value: weekTimeFormatted(Int(mins)),
                        label: L.s("시간", "Time")
                    )
                    WeekStatTile(
                        value: L.s("\(count)회", "\(count)"),
                        label: L.s("횟수", "Runs")
                    )
                    if streak > 0 {
                        WeekStatTile(
                            value: L.s("\(streak)주", "\(streak)wk"),
                            label: L.s("연속", "Streak")
                        )
                    }
                }
            }
        }
    }

    private var metricTrendsSection: some View {
        let L = AppLanguage.shared
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let runningMetrics: [TrendMetric] = [
            .cadence, .power, .groundContactTime, .strideLength, .verticalOscillation, .vo2Max, .hrRecovery1,
            .easyEffortPace
        ]
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: L.s("주간 지표 추세", "Weekly Metric Trends"), subtitle: L.s("최근 7일 대비 직전 7일", "Last 7 days vs prior 7 days"))
            if let obs = formObservation {
                MRFormObservationCard(text: obs.text, basis: obs.basis, isStable: obs.isStable)
            }
            if let rec = recoveryObservation {
                MRFormObservationCard(text: rec.text, basis: rec.basis, isStable: true,
                                      title: L.s("회복", "Recovery"), icon: "heart.circle")
            }
            if let ep = effortPaceObservation {
                MRFormObservationCard(text: ep.text, basis: ep.basis, isStable: true,
                                      title: L.s("쉬운 날 페이스", "Easy-Effort Pace"),
                                      icon: "gauge.with.dots.needle.33percent")
            }
            weeklyPatternCommentCard
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(runningMetrics) { metric in
                    MetricSparkCard(metric: metric, manager: manager, usePounds: useMiles,
                                    preloadedPoints: metricDataPoints[metric]) {
                        selectedTrend = metric
                    }
                }
                if showBodyMass {
                    MetricSparkCard(metric: .bodyMass, manager: manager, usePounds: useMiles,
                                    preloadedPoints: metricDataPoints[.bodyMass]) {
                        selectedTrend = .bodyMass
                    }
                }
                if showBodyFat {
                    MetricSparkCard(metric: .bodyFatPercentage, manager: manager, usePounds: useMiles,
                                    preloadedPoints: metricDataPoints[.bodyFatPercentage]) {
                        selectedTrend = .bodyFatPercentage
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var weeklyPatternCommentCard: some View {
        if let pattern = weeklyPatternCache.first, !weeklyCommentText.isEmpty {
            let style = weeklyPatternStyle(for: pattern.key)
            let woy = mondayCal.component(.weekOfYear, from: Date())
            let headline = pattern.shortName(for: woy, isEnglish: AppLanguage.shared.isEnglish)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: style.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(style.color)
                    Text(headline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                Text(weeklyCommentText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "AEAEB2"))
                if !pattern.basis.isEmpty {
                    Text(pattern.basis)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "636366"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func weeklyPatternStyle(for key: String) -> (symbol: String, color: Color) {
        switch key {
        case "economy":           return ("bolt.fill",                    Color(hex: "F5C542"))
        case "speed":             return ("hare.fill",                    Color(hex: "5AC8FA"))
        case "form":              return ("figure.run",                   Theme.violet)
        case "cardio":            return ("heart.fill",                   Color(hex: "30D158"))
        case "easy":              return ("leaf.fill",                    Color(hex: "34C759"))
        case "streak":            return ("flame.fill",                   Color(hex: "FF9F0A"))
        case "consistent":        return ("checkmark.circle.fill",        Theme.violet)
        case "fatigueSign":       return ("moon.fill",                    Color(hex: "FF9F0A"))
        case "overstride":        return ("figure.walk",                  Color(hex: "FFD60A"))
        case "economyPlus":       return ("sparkle",                      Color(hex: "5AC8FA"))
        case "propulsion":        return ("arrow.up.forward.circle.fill", Theme.violet)
        case "turnover":          return ("arrow.clockwise.circle.fill",  Color(hex: "64D2FF"))
        case "compositionChange": return ("chart.bar.fill",               Color(hex: "FF9F0A"))
        case "heatAdjusted":      return ("thermometer.sun.fill",         Color(hex: "FF9F0A"))
        case "driftWeek":         return ("waveform.path.ecg",            Color(hex: "FF453A"))
        case "hrPaceWeek":        return ("bolt.heart.fill",              Color(hex: "5AC8FA"))
        default:                  return ("figure.walk",                  Color(hex: "8A8A92"))
        }
    }

    private var prSection: some View {
        let L = AppLanguage.shared
        let entries = prEntriesCache
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: L.s("PR 타임라인", "PR Timeline"), subtitle: L.s("거리별 최고 기록", "Best by distance"))
            if entries.isEmpty {
                EmptyChartPlaceholder(message: L.s("표준 거리 완주 기록이 생기면 PR이 여기에 표시돼요", "Complete a standard distance to see your PR"))
            } else {
                PRGrid(entries: entries)
            }
        }
    }

    private var journeySection: some View {
        let L = AppLanguage.shared
        let events = journeyMilestonesCache
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: L.s("나의 여정", "My Journey"), subtitle: L.s("걷기에서 러닝으로", "From walking to running"))
            if events.isEmpty {
                EmptyChartPlaceholder(message: L.s("기록이 쌓이면 여정이 여기에 펼쳐져요", "Your journey will appear as you log more"))
            } else {
                JourneyTimeline(events: events)
            }
        }
    }

    // MARK: - Growth insight banner

    @ViewBuilder
    private var growthInsightBanner: some View {
        if let text = growthInsightText {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.violet)
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.violet.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.violet.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var growthInsightText: String? { growthInsightBannerText }

    private func computeGrowthInsightText() -> String? {
        let L = AppLanguage.shared
        let streak = engine.streakWeeks
        if streak >= 3 {
            return L.s("\(streak)주 연속 달리고 있어요 — 루틴이 자리 잡고 있어요",
                       "\(streak) weeks in a row — you're building a routine")
        }
        if streak == 2 {
            return L.s("2주 연속 달리고 있어요 — 이번 주도 이어가 봐요",
                       "2 weeks running — keep it up this week")
        }

        let thisKm = weeklyKmsCache.last?.km ?? 0
        let prevKm = weeklyKmsCache.dropLast().last?.km ?? 0
        if thisKm > prevKm, prevKm > 0 {
            let diff = thisKm - prevKm
            return String(format: L.s("이번 주 거리가 지난 주보다 +%.1fkm 늘었어요", "+%.1fkm more than last week"), diff)
        }

        if let recent = prEntriesCache.first(where: { $0.isNew }) {
            return L.s("\(recent.label) 신기록을 세웠어요", "New \(recent.label) PR")
        }

        let pts = pacePointsCache
        if pts.count >= 6 {
            let latestAvg = pts.suffix(3).map(\.speedKmh).reduce(0, +) / 3
            let earlierAvg = pts.prefix(3).map(\.speedKmh).reduce(0, +) / 3
            if earlierAvg > 0, latestAvg > earlierAvg * 1.02 {
                return L.s("최근 페이스가 꾸준히 빨라지고 있어요", "Your pace has been steadily improving")
            }
        }

        return nil
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(AppLanguage.shared.s("러닝을 시작하면\n성장 차트가 여기에 나타나요",
                                     "Start running and your\ngrowth chart will appear here"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Body data availability

    private func checkBodyDataAvailability() async {
        // 탭 진입마다 캐시를 지워 HealthKit 최신 신체 측정값 반영
        manager.invalidateBodyMetricHistoryCache()
        let since = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        async let bmTask = manager.fetchMetricHistory(.bodyMass, from: since)
        async let bfTask = manager.fetchMetricHistory(.bodyFatPercentage, from: since)
        let (bm, bf) = await (bmTask, bfTask)
        withAnimation(.easeInOut(duration: 0.3)) {
            showBodyMass = !bm.isEmpty
            showBodyFat  = !bf.isEmpty
        }
        // 카드가 preloadedPoints를 통해 즉시 최신 데이터를 표시할 수 있도록 미리 채움
        let window14 = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        if !bm.isEmpty { metricDataPoints[.bodyMass]             = bm.filter { $0.date >= window14 } }
        if !bf.isEmpty { metricDataPoints[.bodyFatPercentage]    = bf.filter { $0.date >= window14 } }
    }

    // MARK: - Metric trend analyses

    /// 강도 입력이 바뀌었을 때 — 매니저 동기화(강도 파생 캐시 무효화)에 더해
    /// 두 재계산 가드를 풀어, 같은 세션 안에서 바로 다시 계산되게 한다.
    /// (두 곳에서 호출되지만 각 refresh 함수가 자체 가드로 중복 실행을 막는다.)
    private func effortInputsChanged() {
        manager.syncUserEfforts(from: allStories)
        refreshRecordBars()
        refreshEffortTypeRows()
        lastAnalyzedRunCount = -1
        formComputedForRunCount = nil
        Task {
            await refreshMetricAnalyses()
            await refreshFormObservation()
        }
    }

    private func refreshMetricAnalyses() async {
        // engine 미준비 시 스킵 — lastAnalyzedRunCount를 업데이트하지 않아
        // onChange(of: engine.isReady)가 준비 후 재시도를 보장한다
        guard engine.isReady else {
            #if DEBUG
            print("[패턴] engine 미준비 — 분석 스킵")
            #endif
            return
        }
        guard !isRefreshingMetrics else { return }
        let currentCount = runsCache.count
        guard currentCount != lastAnalyzedRunCount else { return }
        // runsCache 미충전 시 스킵 — lastAnalyzedRunCount를 업데이트하지 않아 재시도 보장
        guard currentCount > 0 else {
            #if DEBUG
            print("[패턴] runsCache 미충전 — 분석 스킵")
            #endif
            return
        }
        // 런이 새로 추가됐을 때만 캐시 무효화 (첫 실행은 제외)
        if currentCount > lastAnalyzedRunCount && lastAnalyzedRunCount >= 0 {
            manager.invalidateRunningMetricHistoryCache()
        }
        isRefreshingMetrics = true
        defer {
            isRefreshingMetrics = false
            lastAnalyzedRunCount = currentCount
        }

        let since = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        let runningMetrics: [TrendMetric] = [
            .cadence, .power, .groundContactTime, .strideLength, .verticalOscillation, .vo2Max, .hrRecovery1,
            .easyEffortPace
        ]
        // 체성분 2개도 함께 — 이번주 공유 카드용 sparkData 사전 구성
        let allWeeklyMetrics: [TrendMetric] = runningMetrics + [.bodyMass, .bodyFatPercentage]

        // Fetch all 8 metric histories concurrently — running cards + weekly share card
        var fetched: [(TrendMetric, [(date: Date, value: Double)])] = []
        await withTaskGroup(of: (TrendMetric, [(date: Date, value: Double)]).self) { group in
            for metric in allWeeklyMetrics {
                group.addTask {
                    let pts = await self.manager.fetchMetricHistory(metric, from: since)
                    return (metric, pts)
                }
            }
            for await item in group {
                fetched.append(item)
            }
        }

        let fetchedMap = Dictionary(uniqueKeysWithValues: fetched)

        // Compute trend directions and store full data for running spark cards
        var results: [TrendMetric: (direction: TrendDirection, changeRatio: Double)] = [:]
        var points: [TrendMetric: [(date: Date, value: Double)]] = [:]
        for metric in runningMetrics {
            guard let pts = fetchedMap[metric] else { continue }
            results[metric] = trendDirection(values: pts.map(\.value))
            points[metric] = pts
        }
        metricAnalyses = results
        metricDataPoints = points

        // Build weekly share card sparkData (display order, non-empty only)
        weeklySparkData = allWeeklyMetrics.compactMap { m in
            guard let pts = fetchedMap[m], !pts.isEmpty else { return nil }
            return (metric: m, points: pts)
        }

        // 폼 스타일 관찰 — 1년 데이터가 필요하므로 별도 fetch
        // engine.runs가 비어있으면 스킵 (computeFormObservation 내부 guard와 이중 방어)
        await refreshFormObservation()

        // Build WeeklyInsightInputs and detect patterns
        let cal = mondayCal
        let nowComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let thisWeekRuns = runs.filter {
            cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.date) == nowComps
        }

        // 구성 변화 게이트용 — 이번/직전 2주 고강도(인터벌/템포) 횟수
        let twoWeeksAgo  = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        let fourWeeksAgo = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? .distantPast
        let intenseTypes: Set<WorkoutType> = [.interval, .tempo]
        let thisWindowRuns = runs.filter { $0.date >= twoWeeksAgo }
        let prevWindowRuns = runs.filter { $0.date >= fourWeeksAgo && $0.date < twoWeeksAgo }
        let thisWindowIntenseCount = thisWindowRuns.filter {
            manager.cachedWorkoutType(for: $0.id).map { intenseTypes.contains($0) } ?? false
        }.count
        let prevWindowIntenseCount = prevWindowRuns.filter {
            manager.cachedWorkoutType(for: $0.id).map { intenseTypes.contains($0) } ?? false
        }.count

        // p21·p22·p23 입력: engine.runs 기반 (Activity가 아닌 MRWorkout)
        // ⚠ "이번 주"(ISO 주) 대신 "최근 7일"을 쓴다.
        //   월요일 첫 러닝 전이면 이번 주 런이 0개라 p21/p22 조건을 항상 미달한다.
        let sevenDaysAgo  = Calendar.current.date(byAdding: .day, value: -7,  to: Date()) ?? .distantPast
        let eightWeeksAgo = Calendar.current.date(byAdding: .day, value: -56, to: Date()) ?? .distantPast
        let recent7dRuns = engine.runs.filter { $0.start >= sevenDaysAgo }

        // p21: 최근 7일 야외 런 평균 기온 ≥20°C + heat.ok + ≥3 런 + 보정 차 ≥10초
        let heat = engine.heat
        let (heatOk, heatAvgTempC, heatActualPaceSec, heatRefPaceSec, heatBasisText): (Bool, Double, Double, Double, String) = {
            let outdoor = recent7dRuns.filter { !$0.indoor && $0.tempC != nil }
            guard heat.ok, recent7dRuns.count >= 3, !outdoor.isEmpty else { return (false, 0, 0, 0, "") }
            let temps = outdoor.compactMap(\.tempC)
            let avgTemp = temps.reduce(0, +) / Double(temps.count)
            guard avgTemp >= 20 else { return (false, 0, 0, 0, "") }
            // (b) 런별로 각자 기온으로 보정 후 평균
            // hot² 항 때문에 평균기온 1회 보정(a)과 결과가 다르다.
            var actualPaces: [Double] = []
            var refPaces: [Double] = []
            for r in outdoor {
                guard let d = r.distanceKm, d > 0, let t = r.tempC else { continue }
                let pace = r.durationMin * 60.0 / d
                actualPaces.append(pace)
                refPaces.append(pace * heat.toRef(timeMin: 1.0, tempC: t))
            }
            guard !actualPaces.isEmpty else { return (false, 0, 0, 0, "") }
            let avgPace    = actualPaces.reduce(0, +) / Double(actualPaces.count)
            let avgRefPace = refPaces.reduce(0, +) / Double(refPaces.count)
            // 10초 미만 차이는 말할 가치 없음 → 미발동
            guard abs(avgPace - avgRefPace) >= 10 else { return (false, 0, 0, 0, "") }
            // 이번 계산에 실제로 적용된 보정률 → 사용자가 검산 가능
            let corrPct = (avgPace - avgRefPace) / avgPace * 100
            let tempStr = String(format: "%.0f", avgTemp)
            let corrStr = String(format: "%.1f", corrPct)
            let basis = "본인 러닝 \(heat.n)회로 계산 · \(tempStr)°C에서 \(corrStr)% 보정"
            return (true, avgTemp, avgPace, avgRefPace, basis)
        }()
        #if DEBUG
        let _dbgOutdoor = recent7dRuns.filter { !$0.indoor && $0.tempC != nil }
        let _dbgTemps   = _dbgOutdoor.compactMap(\.tempC)
        let _dbgAvgTemp = _dbgTemps.isEmpty ? "기온없음" : String(format: "%.1f°C", _dbgTemps.reduce(0,+)/Double(_dbgTemps.count))
        print("[패턴] p21 heatAdjusted — 최근 7일 런 \(recent7dRuns.count)회(≥3 \(recent7dRuns.count >= 3 ? "✓":"✗")), 야외평균기온 \(_dbgAvgTemp)(≥20 \((_dbgTemps.reduce(0,+)/max(1,Double(_dbgTemps.count))) >= 20 ? "✓":"✗")), heat.ok=\(heat.ok) → \(heatOk ? "발동":"미발동")")
        #endif

        // p22: 최근 7일 야외 롱런(≥40분) + drift.ok + 기온 ≥20°C
        let drift = engine.drift
        let (driftOk, driftBpmActual, driftBpmRef, driftTempC): (Bool, Double, Double, Double) = {
            let longOutdoor = recent7dRuns.filter { !$0.indoor && $0.tempC != nil && $0.durationMin >= 40 }
            guard drift.ok, !longOutdoor.isEmpty else { return (false, 0, 0, 0) }
            let temps = longOutdoor.compactMap(\.tempC)
            let avgTemp = temps.reduce(0, +) / Double(temps.count)
            guard avgTemp >= 20 else { return (false, 0, 0, 0) }
            return (true, drift.bpmPer10Min(atC: avgTemp), drift.bpmPer10MinAtRef, avgTemp)
        }()

        // p23: 최근 4주 vs 직전 4주 정규화 페이스(150bpm 기준) 차 ≥5초
        let hrPaceDeltaSec: Double? = {
            guard engine.hrPace.ok, recent7dRuns.count >= 3 else { return nil }
            func normPace(_ rs: [MRWorkout]) -> Double? {
                let valid = rs.filter {
                    $0.hrAvg != nil && $0.distanceKm != nil && !$0.isInterval && !$0.indoor && $0.durationMin >= 20
                }
                guard valid.count >= 3 else { return nil }
                let refHR = 150.0
                let scaled = valid.compactMap { r -> Double? in
                    guard let hr = r.hrAvg, let d = r.distanceKm, d > 0, hr > 0 else { return nil }
                    let pace = r.durationMin * 60.0 / d
                    return pace * (hr / refHR)   // 150bpm 기준으로 정규화
                }
                guard !scaled.isEmpty else { return nil }
                return scaled.reduce(0, +) / Double(scaled.count)
            }
            let recentRuns = engine.runs.filter { $0.start >= fourWeeksAgo }
            let prevRuns   = engine.runs.filter { $0.start >= eightWeeksAgo && $0.start < fourWeeksAgo }
            guard let recentNorm = normPace(recentRuns),
                  let prevNorm   = normPace(prevRuns) else { return nil }
            let delta = prevNorm - recentNorm   // 양수 = 최근이 더 빠름
            return abs(delta) >= 5 ? delta : nil
        }()

        let inputs = WeeklyInsightInputs(
            paceDirection:         paceAnalysisCache.direction,
            hrDirection:           hrAnalysisCache.direction,
            cadence:               results[.cadence]?.direction             ?? .insufficient,
            power:                 results[.power]?.direction               ?? .insufficient,
            strideLength:          results[.strideLength]?.direction         ?? .insufficient,
            groundContactTime:     results[.groundContactTime]?.direction    ?? .insufficient,
            vertOsc:               results[.verticalOscillation]?.direction  ?? .insufficient,
            vo2Max:                results[.vo2Max]?.direction               ?? .insufficient,
            paceChangeRatio:       paceAnalysisCache.changeRatio,
            hrChangeRatio:         hrAnalysisCache.changeRatio,
            metricChangeRatios:    results.mapValues { $0.changeRatio },
            weekStreak:            engine.streakWeeks,
            runCount:              thisWeekRuns.count,
            thisWeekDistanceKm:    thisWeekLongestKmCache,
            thisWindowIntenseCount: thisWindowIntenseCount,
            prevWindowIntenseCount: prevWindowIntenseCount,
            prevWindowRunCount:    prevWindowRuns.count,
            heatOk:               heatOk,
            heatAvgTempC:         heatAvgTempC,
            heatActualPaceSec:    heatActualPaceSec,
            heatRefPaceSec:       heatRefPaceSec,
            heatBasisText:        heatBasisText,
            driftOk:              driftOk,
            driftBpmActual:       driftBpmActual,
            driftBpmRef:          driftBpmRef,
            driftTempC:           driftTempC,
            hrPaceDeltaSec:       hrPaceDeltaSec
        )
        // ■4 engine.runs 미충전 시 encourage(p99) 오발 방지
        //   engine.isReady 가드만으로는 runs가 완전히 채워지지 않은 타이밍을 막지 못한다.
        //   runsCache(manager 기반)와 engine.runs는 별개 캐시라 race가 발생할 수 있다.
        guard !engine.runs.isEmpty else {
            weeklyPatternCache = []
            weeklyCommentText = ""
            return
        }
        weeklyPatternCache = applyPatternRepeatGuard(detectWeeklyPatterns(inputs))
        #if DEBUG
        let _allKeys = weeklyPatternCache.map { "\($0.key)(p\($0.priority))" }
        print("[패턴] 발동 \(_allKeys.count)개: \(_allKeys.joined(separator: ", "))")
        #endif
        InsightEngine.updateFatigueSignal(active: false)  // fatigueSign 패턴 제거됨
        weeklySummary = assembleWeeklySummary(
            patterns: weeklyPatternCache,
            inputs: inputs,
            thisWindowRuns: thisWindowRuns,
            recentWeeklyKms: weeklyKmsCache.suffix(4).map { $0.km }
        )

        // ① 폴백 템플릿으로 즉시 표시
        let weekOfYear = mondayCal.component(.weekOfYear, from: Date())
        guard let summary = weeklySummary else {
            weeklyCommentText = ""
            return
        }
        // p21/p22/p23는 WeeklySummary 3문장 구조가 아닌 패턴 자체 템플릿을 쓴다.
        let standaloneKeys: Set<String> = ["heatAdjusted", "driftWeek", "hrPaceWeek"]
        if let top = weeklyPatternCache.first, standaloneKeys.contains(top.key) {
            weeklyCommentText = top.template(for: weekOfYear, isEnglish: AppLanguage.shared.isEnglish)
        } else {
            weeklyCommentText = summary.template(for: weekOfYear, isEnglish: AppLanguage.shared.isEnglish)
        }

        // ② 같은 주·같은 패턴이면 메모리 캐시 사용
        let year = mondayCal.component(.year, from: Date())
        // 템플릿 해시: 문구를 한 글자만 고쳐도 키가 자동으로 바뀐다.
        // · 패턴 koTemplates/enTemplates (동적 값 포함) + WeeklySummary 폴백 문장 → 정렬 후 FNV-1a
        // · 동적 값(페이스·기온 등)이 바뀌어도 키가 갱신되므로 데이터 변경 시 자동 재생성.
        var _hashSources = weeklyPatternCache.flatMap { $0.koTemplates + $0.enTemplates }
        _hashSources.append(summary.template(for: weekOfYear, isEnglish: false))
        _hashSources.append(summary.template(for: weekOfYear, isEnglish: true))
        let _tHash = String(format: "%08x", Self.stableHash(_hashSources.sorted().joined(separator: "|")))
        let langSuffix = AppLanguage.shared.isEnglish ? "_en" : "_ko"
        let cacheKey = "v\(Self.weeklyCommentVersion)_\(_tHash)_\(year)W\(weekOfYear)_\(summary.topPatternKey)\(langSuffix)"

        // 중복 실행 방지: 직전 호출과 동일 입력이면 AI 재시도 스킵 (onChange 이중 실행 등 방어)
        let inputKey = "\(cacheKey)|\(summary.aiFacts)"
        guard inputKey != lastWeeklyCommentInputKey else {
            #if DEBUG
            print("[WeeklyComment] 중복 입력 스킵 key=\(cacheKey)")
            #endif
            return
        }
        lastWeeklyCommentInputKey = inputKey

        if !Self.debugBypassCache, let cached = weeklyCommentCache[cacheKey] {
            #if DEBUG
            print("[WeeklyComment] 경로=② 메모리 캐시히트 key=\(cacheKey)")
            #endif
            weeklyCommentText = cached
            return
        }

        // ③ 디스크(UserDefaults) 캐시 — 앱 재시작 후에도 AI 재실행 방지
        let udKey = "\(MRModelVersion.prefix)mimo_weekly_comment_\(cacheKey)"
        let udDateKey = "\(udKey)_date"
        if !Self.debugBypassCache, let persisted = UserDefaults.standard.string(forKey: udKey) {
            #if DEBUG
            let savedDate = UserDefaults.standard.object(forKey: udDateKey) as? Date
            let dateStr = savedDate.map { ISO8601DateFormatter().string(from: $0) } ?? "날짜 미기록"
            print("[WeeklyComment] 경로=③ 디스크 캐시히트 key=\(cacheKey) 저장일시=\(dateStr)")
            #endif
            weeklyCommentText = persisted
            weeklyCommentCache[cacheKey] = persisted
            return
        }

        // ★ 쓰기 차단 — engine 미준비 상태의 불완전한 패턴은 디스크에 저장하지 않는다.
        // (engine.isReady 후 onChange가 재계산을 트리거함)
        guard engine.isReady else {
            #if DEBUG
            print("[WeeklyComment] ★ 쓰기 차단: engine 미준비 — 메모리만 표시")
            #endif
            return
        }
        #if DEBUG
        print("[WeeklyComment] 경로=① 새 템플릿 생성 key=\(cacheKey) pattern=\(summary.topPatternKey)")
        #endif

        // 이번 주 패턴 히스토리 기록 (주당 1회 — 새 템플릿 생성 경로에서만)
        let patternHistoryKey = "mimo_weekly_pattern_history"
        let weekRecordKey = "mimo_weekly_pattern_recorded_\(year)W\(weekOfYear)"
        if !UserDefaults.standard.bool(forKey: weekRecordKey) {
            var history = (UserDefaults.standard.array(forKey: patternHistoryKey) as? [String]) ?? []
            history.append(summary.topPatternKey)
            if history.count > 5 { history = Array(history.suffix(5)) }
            UserDefaults.standard.set(history, forKey: patternHistoryKey)
            UserDefaults.standard.set(true, forKey: weekRecordKey)
        }

        // ④ 하루 1회 한도 — 오늘 이미 AI가 실행됐으면 재실행 금지
        let today = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        let dailyRunKey = "mimo_weekly_comment_ai_ran_\(today)"
        if !Self.debugBypassCache && !Self.debugBypassDailyLimit
            && UserDefaults.standard.bool(forKey: dailyRunKey) {
            #if DEBUG
            print("[WeeklyComment] AI=④ 오늘 이미 실행됨 → 템플릿 디스크 저장")
            print("[WeeklyComment] 저장 문장=\"\(weeklyCommentText)\"")
            #endif
            weeklyCommentCache[cacheKey] = weeklyCommentText
            UserDefaults.standard.set(weeklyCommentText, forKey: udKey)
            UserDefaults.standard.set(Date(), forKey: udDateKey)
            return
        }

        // ⑤ 총평 AI 경로 (useAITotalComment = true 일 때만 시도)
        if Self.useAITotalComment {
            #if canImport(FoundationModels)
            if #available(iOS 26, *) {
                let isAvail = InsightAIGenerator.isAvailable
                let willTry = isAvail && !summary.aiFacts.isEmpty && !AppLanguage.shared.isEnglish
                #if DEBUG
                print("[WeeklyComment] AI=⑤ 사용가능=\(isAvail) 시도=\(willTry) 패턴=\(summary.topPatternKey)")
                #endif
                if willTry, let aiText = await InsightAIGenerator.generateWeeklyComment(
                    patternKey: summary.shortNamePatternKey, factSummary: summary.aiFacts
                ) {
                    #if DEBUG
                    print("[WeeklyComment] AI=⑤ 성공")
                    print("  [AI원문]       \"\(aiText)\"")
                    print("  [폴백 템플릿]  \"\(weeklyCommentText)\"")
                    #endif
                    weeklyCommentText = aiText
                    weeklyCommentCache[cacheKey] = aiText
                    UserDefaults.standard.set(aiText, forKey: udKey)
                    UserDefaults.standard.set(Date(), forKey: udDateKey)
                    UserDefaults.standard.set(true, forKey: dailyRunKey)
                } else {
                    #if DEBUG
                    let skipReason = willTry ? "검증탈락·미지원" : "AI 비대상(\(summary.topPatternKey))"
                    print("[WeeklyComment] AI=⑤ \(skipReason)")
                    print("  [템플릿 저장]  \"\(weeklyCommentText)\"")
                    #endif
                    weeklyCommentCache[cacheKey] = weeklyCommentText
                    UserDefaults.standard.set(weeklyCommentText, forKey: udKey)
                    UserDefaults.standard.set(Date(), forKey: udDateKey)
                    if willTry { UserDefaults.standard.set(true, forKey: dailyRunKey) }
                }
            } else {
                weeklyCommentCache[cacheKey] = weeklyCommentText
                UserDefaults.standard.set(weeklyCommentText, forKey: udKey)
                UserDefaults.standard.set(Date(), forKey: udDateKey)
            }
            #else
            weeklyCommentCache[cacheKey] = weeklyCommentText
            UserDefaults.standard.set(weeklyCommentText, forKey: udKey)
            UserDefaults.standard.set(Date(), forKey: udDateKey)
            #endif
        } else {
            weeklyCommentCache[cacheKey] = weeklyCommentText
            UserDefaults.standard.set(weeklyCommentText, forKey: udKey)
            UserDefaults.standard.set(Date(), forKey: udDateKey)
        }
    }

    // MARK: - Form observation (engine.runs 의존 — engine 준비 후 실행)

    /// 폼 스타일 관찰.
    /// - engine.runs 미충전 시 스킵 (빈 결과가 formObservation에 쓰이는 것 방지)
    /// - 동일 runs.count 재호출 시 스킵 (이중실행 방지: 안정 분기 기록 후 즉시 재호출하면 4주 rule에 막힘)
    /// - nil 결과(침묵)는 기존 formObservation을 덮어쓰지 않음
    private func refreshFormObservation() async {
        guard !engine.runs.isEmpty else { return }
        guard formComputedForRunCount != engine.runs.count else {
            #if DEBUG
            print("[폼] 이미 계산됨 runs=\(engine.runs.count) — 스킵")
            #endif
            return
        }
        formComputedForRunCount = engine.runs.count
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        // vo는 추세 판정에서 제외 — Apple Watch 측정 오차 MAPE 19%로 신뢰도 낮음
        async let cadFetch = manager.fetchMetricHistory(.cadence, from: oneYearAgo)
        async let gctFetch = manager.fetchMetricHistory(.groundContactTime, from: oneYearAgo)
        let (cadData, gctData) = await (cadFetch, gctFetch)
        // nil(침묵)은 기존 결과를 유지 — 안정 분기 기록 직후 재호출로 덮어쓰이는 것을 방지
        if let result = computeFormObservation(cadData: cadData, gctData: gctData) {
            formObservation = result
        }

        // 같은 강도 페이스 추이 — 본인 이지런 강도 이하 러닝의 페이스를 폼 판정기(3개월 vs 3개월, MDC)로 본다
        let easyPts = await manager.fetchMetricHistory(.easyEffortPace, from: oneYearAgo)
        let easyCutoff = manager.easyEffortCutoff()
        if let shift = mrFormShift(EffortPaceTrend.residuals(points: easyPts), metric: EffortPaceTrend.metric, asOf: Date()),
           let o = EffortPaceTrend.observation(shift: shift,
                                               cutoff: easyCutoff ?? EffortPaceTrend.fallbackCutoff,
                                               isPersonal: easyCutoff != nil) {
            effortPaceObservation = o
        }

        // 운동 후 심박 회복 추세 — 종료 심박을 회귀로 통제한 잔차를 폼과 같은 판정기(MDC)로 본다
        let hist = await manager.fetchRecoveryHistory(from: oneYearAgo)
        let obs = hist.map { MRRecovery.Obs(date: $0.date, endHR: $0.endHR, hrr1: $0.hrr1, tempC: $0.tempC) }
        let residuals = MRRecovery.residuals(obs: obs, asOf: Date())
        if let shift = mrFormShift(residuals, metric: MRRecovery.metric, asOf: Date()) {
            #if DEBUG
            // 기온 보정 전 Δ를 나란히 — "여름이라 나빠 보이는 것"인지 바로 구분하기 위해
            let rawShift = mrFormShift(MRRecovery.residuals(obs: obs, asOf: Date(), useTemp: false),
                                       metric: MRRecovery.metric, asOf: Date())
            print(String(format: "[회복] 관측 %d(기온 있음 %d) · 잔차 Δ%+.1f (기온 보정 전 %@) · MDC %.1f · 연속 %d주 · %@",
                         obs.count, obs.filter { $0.tempC != nil }.count, shift.delta,
                         rawShift.map { String(format: "%+.1f", $0.delta) } ?? "—",
                         shift.mdc, shift.weeksConsistent,
                         MRRecovery.observation(shift: shift) == nil ? "침묵" : "표시"))
            #endif
            if let o = MRRecovery.observation(shift: shift) { recoveryObservation = o }
        } else {
            #if DEBUG
            print("[회복] 관측 \(obs.count) · 판정 불가 (잔차 \(residuals.count)개, 3개월씩 20개 필요)")
            #endif
        }
    }

    // MARK: - Pattern repeat guard

    /// 동일 패턴이 3주 연속 최상위에 오면 차순위로 교체. streak·consistent 는 면제.
    private func applyPatternRepeatGuard(_ patterns: [WeeklyPattern]) -> [WeeklyPattern] {
        guard patterns.count > 1, let top = patterns.first else { return patterns }
        guard top.key != "streak" && top.key != "consistent" else { return patterns }
        let historyKey = "mimo_weekly_pattern_history"
        let history = (UserDefaults.standard.array(forKey: historyKey) as? [String]) ?? []
        let recent = Array(history.suffix(3))
        guard recent.count == 3 && recent.allSatisfy({ $0 == top.key }) else { return patterns }
        // 최상위를 맨 뒤로 밀고 차순위를 앞으로
        return Array(patterns.dropFirst()) + [top]
    }

    // MARK: - Journey milestones

    private func journeyMilestones() -> [MilestoneEvent] {
        let L = AppLanguage.shared
        let all = manager.activities.sorted { $0.date < $1.date }
        let allRuns = all.filter { $0.type == .running }
        var events: [MilestoneEvent] = []

        // 첫 기록 (any type)
        if let first = all.first {
            let typeLabel = first.type.label
            let title = L.isEnglish ? "First \(typeLabel)" : "첫 \(typeLabel)"
            events.append(.init(id: "first_any", date: first.date, kind: .first,
                                title: title, detail: first.formattedDistance))
        }

        // 첫 러닝 (only if different from very first activity)
        if let firstRun = allRuns.first, firstRun.id != all.first?.id {
            events.append(.init(id: "first_run", date: firstRun.date, kind: .first,
                                title: L.s("첫 러닝", "First Run"), detail: firstRun.formattedDistance))
        }

        // 거리별 첫 완주 (5K / 10K / 하프 / 풀)
        let distMilestones: [(Double, String, String)] = [
            (5000,  "first_5k",   L.s("첫 5K 완주",   "First 5K")),
            (10000, "first_10k",  L.s("첫 10K 완주",  "First 10K")),
            (21097, "first_half", L.s("첫 하프 완주",  "First Half")),
            (42195, "first_full", L.s("첫 풀 완주",    "First Full")),
        ]
        var coveredRunIDs = Set<UUID>()
        for (minDist, key, title) in distMilestones {
            if let a = allRuns.first(where: { $0.distance >= minDist }) {
                events.append(.init(id: key, date: a.date, kind: .distance,
                                    title: title, detail: a.formattedDistance))
                coveredRunIDs.insert(a.id)
            }
        }

        // 누적 거리 돌파 (모든 활동 기준: 걷기+러닝+하이킹)
        let thresholds: [Double] = [100, 300, 500, 1000]
        var totalKm = 0.0
        var nextThresh = 0
        for a in all {
            totalKm += a.distance / 1000
            while nextThresh < thresholds.count && totalKm >= thresholds[nextThresh] {
                let km = thresholds[nextThresh]
                events.append(.init(
                    id: "cum_\(Int(km))",
                    date: a.date,
                    kind: .cumulative,
                    title: L.s("누적 \(Int(km))km 돌파", "\(Int(km))km total"),
                    detail: String(format: L.s("총 %.0fkm", "Total %.0fkm"), totalKm)
                ))
                nextThresh += 1
            }
        }

        // 현재 최장 거리 (거리 마일스톤에 없는 경우만)
        if let longest = allRuns.max(by: { $0.distance < $1.distance }),
           longest.distance >= 5000,
           !coveredRunIDs.contains(longest.id) {
            events.append(.init(id: "longest", date: longest.date, kind: .longest,
                                title: L.s("현재 최장 거리", "Longest Run"), detail: longest.formattedDistance))
        }

        return events.sorted { $0.date < $1.date }
    }

    // MARK: - PR data

    private static var prBuckets: [(id: String, label: String, range: ClosedRange<Double>)] {
        let L = AppLanguage.shared
        return [
            ("5K",   "5K",                  4700...5500),
            ("10K",  "10K",                 9500...10500),
            ("half", L.s("하프", "Half"),   20000...22000),
            ("full", L.s("풀",   "Full"),   41000...43000),
        ]
    }

    private func prEntries() -> [PREntry] {
        Self.prBuckets.compactMap { bucket in
            let best = runs
                .filter { bucket.range.contains($0.distance) }
                .min(by: { $0.duration < $1.duration })
            guard let best else { return nil }
            return PREntry(id: bucket.id, label: bucket.label, activity: best)
        }
    }

    // MARK: - Weekly distance data

    private func weeklyKms() -> [WeeklyKm] {
        let cal = mondayCal
        let now = Date()
        let starts: [Date] = (0..<12).reversed().compactMap { ago -> Date? in
            guard let ref = cal.date(byAdding: .weekOfYear, value: -ago, to: now) else { return nil }
            return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ref))
        }
        var totals: [Date: Double] = Dictionary(starts.map { ($0, 0.0) }, uniquingKeysWith: { old, _ in old })
        for a in runs {
            guard let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: a.date)) else { continue }
            totals[ws] = totals[ws].map { $0 + a.distance / 1000 }
        }
        return starts.map { s in WeeklyKm(id: s, label: Self.weekLabelFormatter.string(from: s), km: totals[s] ?? 0) }
    }

    private func weeklyMins() -> [WeeklyMins] {
        let cal = mondayCal
        let now = Date()
        let starts: [Date] = (0..<12).reversed().compactMap { ago -> Date? in
            guard let ref = cal.date(byAdding: .weekOfYear, value: -ago, to: now) else { return nil }
            return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ref))
        }
        var totals: [Date: Double] = Dictionary(starts.map { ($0, 0.0) }, uniquingKeysWith: { old, _ in old })
        for a in runs {
            guard let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: a.date)) else { continue }
            totals[ws] = totals[ws].map { $0 + a.duration / 60 }
        }
        return starts.map { s in WeeklyMins(id: s, label: Self.weekLabelFormatter.string(from: s), mins: totals[s] ?? 0) }
    }

    // MARK: - Pace data

    private func pacePoints(maxCount: Int = 20) -> [PacePoint] {
        runs
            .prefix(maxCount)
            .reversed()
            .compactMap { a -> PacePoint? in
                guard let sec = a.paceSecPerKm, sec > 0 else { return nil }
                return PacePoint(
                    date: a.date,
                    speedKmh: 3600.0 / sec,
                    paceFormatted: a.formattedPace ?? ""
                )
            }
    }

    // MARK: - Heatmap data

    private static let heatmapWeeks = 18

    private func heatmapColumns() -> [WeekColumn] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Monday of the current week (weekday: 1=Sun…7=Sat → Mon=0 offset)
        let todayWeekday = cal.component(.weekday, from: today)
        let daysFromMon = (todayWeekday + 5) % 7  // Mon=0, Sun=6
        let thisMonday = cal.date(byAdding: .day, value: -daysFromMon, to: today) ?? today

        // First Monday of the heatmap
        let firstMonday = cal.date(byAdding: .weekOfYear,
                                   value: -(Self.heatmapWeeks - 1),
                                   to: thisMonday) ?? thisMonday

        // Build km-per-day lookup
        var kmByDay: [Date: Double] = [:]
        for a in runs {
            let day = cal.startOfDay(for: a.date)
            kmByDay[day, default: 0] += a.distance / 1000
        }

        return (0..<Self.heatmapWeeks).map { w in
            let monday = cal.date(byAdding: .day, value: w * 7, to: firstMonday) ?? firstMonday
            let days = (0..<7).map { d -> DayCell in
                let date = cal.date(byAdding: .day, value: d, to: monday) ?? monday
                return DayCell(id: date, km: kmByDay[date] ?? 0, isFuture: date > today)
            }
            return WeekColumn(id: monday, days: days)
        }
    }

    private func activeDaysInHeatmap(columns: [WeekColumn]) -> Int {
        columns.flatMap(\.days).filter { !$0.isFuture && $0.km > 0 }.count
    }

    private func heatmapSummary(streak: Int, activeDays: Int) -> String {
        let L = AppLanguage.shared
        if streak >= 2 {
            return L.s("\(streak)주 연속 · \(Self.heatmapWeeks)주간 \(activeDays)일 러닝",
                       "\(streak) weeks · \(activeDays) days in \(Self.heatmapWeeks) wks")
        } else if activeDays > 0 {
            return L.s("최근 \(Self.heatmapWeeks)주간 \(activeDays)일 러닝",
                       "\(activeDays) days in the last \(Self.heatmapWeeks) wks")
        } else {
            return L.s("최근 \(Self.heatmapWeeks)주간 기록 없음",
                       "No runs in the last \(Self.heatmapWeeks) wks")
        }
    }

    // MARK: - 쉬어간 기간

    private static func computeDisplayGaps(runs: [MRWorkout], minDays: Int = 14, maxDays: Int = 365)
        -> [(start: Date, end: Date, days: Int, prePace: Double?, postPace: Double?)] {
        guard runs.count >= 2 else { return [] }
        let sorted = runs.sorted { $0.date < $1.date }
        let window = 28.0 * 86_400.0
        #if DEBUG
        var skippedTooLong = 0
        var skippedNoPace = 0
        #endif
        var out: [(start: Date, end: Date, days: Int, prePace: Double?, postPace: Double?)] = []
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i], b = sorted[i + 1]
            let gap = Calendar.current.dateComponents([.day], from: a.date, to: b.date).day ?? 0
            guard gap >= minDays else { continue }
            // ① 상한: 365일 초과 공백은 훈련 공백이 아닌 시작 전 시기로 분류
            guard gap <= maxDays else {
                #if DEBUG
                skippedTooLong += 1
                #endif
                continue
            }
            // ② 전후 페이스 데이터 계산 (없으면 목록 제외)
            let preRuns  = sorted.prefix(i + 1).filter { a.date.timeIntervalSince($0.date) < window }
            let postRuns = sorted.dropFirst(i + 1).filter { $0.date.timeIntervalSince(b.date) < window }
            let prePaces  = preRuns.compactMap(\.paceSecPerKm).filter { $0 <= 720 }
            let postPaces = postRuns.compactMap(\.paceSecPerKm).filter { $0 <= 720 }
            guard !prePaces.isEmpty && !postPaces.isEmpty else {
                #if DEBUG
                skippedNoPace += 1
                #endif
                continue
            }
            let prePace  = prePaces.reduce(0, +) / Double(prePaces.count)
            let postPace = postPaces.reduce(0, +) / Double(postPaces.count)
            out.append((start: a.date, end: b.date, days: gap, prePace: prePace, postPace: postPace))
        }
        #if DEBUG
        logGapDiagnostic(gaps: out, skippedTooLong: skippedTooLong, skippedNoPace: skippedNoPace)
        #endif
        return out
    }

    #if DEBUG
    private static func logGapDiagnostic(
        gaps: [(start: Date, end: Date, days: Int, prePace: Double?, postPace: Double?)],
        skippedTooLong: Int = 0,
        skippedNoPace: Int = 0
    ) {
        print("[공백] 기준 = 14일 이상 · 365일 이하 · 전후 데이터 모두 필요")
        var skipParts: [String] = []
        if skippedTooLong > 0 { skipParts.append("365일 초과 \(skippedTooLong)건") }
        if skippedNoPace > 0  { skipParts.append("전후 데이터 불완전 \(skippedNoPace)건") }
        if !skipParts.isEmpty { print("[공백] 제외 = " + skipParts.joined(separator: " · ")) }
        guard !gaps.isEmpty else { print("[공백] 0건"); return }
        print("[공백] \(gaps.count)건:")
        let ymd: (Date) -> String = { d in
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
        }
        let pf: (Double?) -> String = { sec in
            guard let s = sec else { return "—" }
            return String(format: "%d'%02d\"", Int(s) / 60, Int(s) % 60)
        }
        for gap in gaps {
            print("[공백] \(ymd(gap.start)) ~ \(ymd(gap.end)) (\(gap.days)일) | 전 페이스 \(pf(gap.prePace)) · 후 페이스 \(pf(gap.postPace))")
        }
    }
    #endif

    @ViewBuilder
    private var gapSection: some View {
        if !displayGaps.isEmpty {
            let L = AppLanguage.shared
            VStack(alignment: .leading, spacing: 10) {
                // 헤더: 항상 표시, 탭하면 토글
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isGapExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.s("쉬어간 기간 · \(displayGaps.count)회", "Rest Periods · \(displayGaps.count)"))
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(L.s("14일 이상 러닝 없음", "14+ day running gaps"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isGapExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                // 목록: 펼쳐졌을 때만 표시 (최신순)
                if isGapExpanded {
                    let pf: (Double) -> String = { sec in
                        let s = Int(sec.rounded())
                        return String(format: "%d'%02d\"", s / 60, s % 60)
                    }
                    let reversedGaps = displayGaps.reversed()
                    VStack(spacing: 0) {
                        ForEach(Array(reversedGaps.enumerated()), id: \.offset) { idx, gap in
                            HStack(alignment: .center, spacing: 8) {
                                Text(gapMonthLabel(gap.start))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                                Text(L.s("\(gap.days)일", "\(gap.days) days"))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color(hex: "AEAEB2"))
                                Spacer()
                                if let pre = gap.prePace, let post = gap.postPace {
                                    Text(L.s("복귀 후 \(pf(post)) · 쉬기 전 \(pf(pre))",
                                             "After \(pf(post)) · Before \(pf(pre))"))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(hex: "8E8E93"))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            if idx < displayGaps.count - 1 {
                                Rectangle()
                                    .fill(Color(hex: "3A3A3C"))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 14)
                            }
                        }
                    }
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func gapMonthLabel(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "''yy.MM"
        return df.string(from: date)
    }

    // MARK: - 몸의 변화 섹션

    private func loadBodyChangeSectionData() async {
        let allMass = await manager.fetchBodyMassAllTime()

        let cal = Calendar.current
        let now = Date()

        // 체중 카드들
        bodyMassPeakData      = nil
        bodyMassStabilityData = nil
        if allMass.count >= 8 {
            let currentKg = allMass.last!.value
            let peakEntry = allMass.max(by: { $0.value < $1.value })!
            let diffKg    = peakEntry.value - currentKg
            let diffPct   = abs(diffKg) / peakEntry.value * 100

            if diffPct >= 3.0 {
                bodyMassPeakData = BodyMassPeakData(
                    currentKg: currentKg,
                    peakKg: peakEntry.value,
                    peakDate: peakEntry.date,
                    diffKg: diffKg,
                    diffPct: diffPct,
                    isLighter: currentKg < peakEntry.value
                )
                let pc = cal.dateComponents([.year, .month], from: peakEntry.date)
                #if DEBUG
                print("[몸] 체중 최고 \(String(format: "%.1f", peakEntry.value))kg(\(pc.year ?? 0)년 \(pc.month ?? 0)월) · 현재 \(String(format: "%.1f", currentKg))kg · 차이 \(String(format: "%.1f", diffKg))kg \(String(format: "%.1f", diffPct))%")
                #endif
            }

            let sixMonthsAgo = cal.date(byAdding: .month, value: -6, to: now) ?? .distantPast
            let recent6m     = allMass.filter { $0.date >= sixMonthsAgo }
            if recent6m.count >= 8 {
                let vals   = recent6m.map { $0.value }
                let sd     = bodyChangeStdDev(vals)
                let branch = sd < 0.8 ? "A" : (sd <= 2.0 ? "B" : "C")
                bodyMassStabilityData = BodyMassStabilityData(
                    minKg: vals.min() ?? 0,
                    maxKg: vals.max() ?? 0,
                    stdDev: sd,
                    count: recent6m.count
                )
                #if DEBUG
                print("[몸] 6개월 SD \(String(format: "%.1f", sd))kg · 측정 \(recent6m.count)회 · 문장 갈래 \(branch)")
                #endif
            }
        }

        // 4. 건강 이야기 (4주 주기) — MRAdviceLog.canShow 사용
        let idx      = UserDefaults.standard.integer(forKey: Self.healthStoryIndexKey)
        let storyKey = idx == 0 ? "health.story.a" : "health.story.b"
        let log      = MRAdviceLogStore.load()
        let (canShow, reason) = log.canShow(storyKey, minDays: 28)
        shouldShowHealthStory = canShow
        healthStoryIndex      = idx
        healthStoryRecorded   = false
        #if DEBUG
        let storyLabel = idx == 0 ? "(a)" : "(b)"
        print("[몸] 건강 이야기 — 조건 확인 \(storyLabel) · canShow=\(canShow)/\(reason)")
        #endif
    }

    // MARK: 몸의 변화 섹션 View

    @ViewBuilder
    private var bodyChangeSectionView: some View {
        let hasAny = bodyMassPeakData != nil
            || bodyMassStabilityData != nil
            || shouldShowHealthStory
        if hasAny {
            let L = AppLanguage.shared
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(
                    title: L.s("몸의 변화", "Body Changes"),
                    subtitle: L.s("측정 기록 기반", "Based on health records")
                )
                if let pk  = bodyMassPeakData      { bodyMassPeakCard(pk) }
                if let st  = bodyMassStabilityData  { bodyMassStabilityCard(st) }
                if shouldShowHealthStory            { healthStoryCardView }
            }
        }
    }

    @ViewBuilder
    private func bodyMassPeakCard(_ data: BodyMassPeakData) -> some View {
        let L      = AppLanguage.shared
        let curStr = String(format: "%.1f", data.currentKg)
        let pkStr  = String(format: "%.1f", data.peakKg)
        let dKgStr = String(format: "%.1f", abs(data.diffKg))
        let dPctStr = String(format: "%.1f", data.diffPct)

        let peakDateStr: String = {
            let comps = Calendar.current.dateComponents([.year, .month], from: data.peakDate)
            if L.isEnglish {
                let df = DateFormatter(); df.locale = Locale(identifier: "en_US"); df.dateFormat = "MMM yyyy"
                return df.string(from: data.peakDate)
            }
            return "\(comps.year ?? 0)년 \(comps.month ?? 0)월"
        }()

        let titleText: String = {
            if L.isEnglish {
                return data.isLighter
                    ? "You are \(dKgStr) kg lighter than your recorded peak."
                    : "Your weight is \(dKgStr) kg heavier than your recorded peak."
            } else {
                return data.isLighter
                    ? "지금 체중은 기록이 있는 기간의 최고치보다 \(dKgStr)kg 가볍습니다"
                    : "지금 체중은 기록이 있는 기간의 최고치보다 \(dKgStr)kg 무겁습니다"
            }
        }()
        let basisText = L.s(
            "기록이 있는 기간의 최고치 기준입니다. 그 전은 알 수 없습니다.",
            "Based on your recorded peak. Earlier history is unknown."
        )

        VStack(alignment: .leading, spacing: 6) {
            Text(L.s("최고치 대비", "vs. Recorded Peak"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(titleText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            // Table
            VStack(alignment: .leading, spacing: 3) {
                bodyMassRow(label: L.s("최고", "Peak"),
                            value: "\(pkStr) kg",
                            note: "(\(peakDateStr))")
                bodyMassRow(label: L.s("지금", "Now"),
                            value: "\(curStr) kg",
                            note: nil)
                bodyMassRow(label: L.s("차이", "Diff"),
                            value: "\(data.isLighter ? "−" : "+")\(dKgStr) kg",
                            note: "· \(dPctStr)%")
            }
            .padding(.top, 2)

            Text(basisText)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "636366"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func bodyMassRow(label: String, value: String, note: String?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "8A8A92"))
                .frame(width: 28, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            if let n = note {
                Text(n)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "8A8A92"))
            }
        }
    }

    @ViewBuilder
    private func bodyMassStabilityCard(_ data: BodyMassStabilityData) -> some View {
        let L      = AppLanguage.shared
        let minStr = String(format: "%.1f", data.minKg)
        let maxStr = String(format: "%.1f", data.maxKg)
        let sdStr  = String(format: "%.1f", data.stdDev)

        let titleText = L.s(
            "체중이 \(minStr) ~ \(maxStr)kg 사이에서 유지되고 있어요",
            "Your weight has stayed between \(minStr) and \(maxStr) kg"
        )
        let sdSentence: String = {
            if data.stdDev < 0.8 {
                return L.s("흔들림이 거의 없습니다.", "Very stable — barely any fluctuation.")
            } else if data.stdDev <= 2.0 {
                return L.s("평소 범위 안에서 오르내리고 있어요.", "Normal day-to-day variation.")
            } else {
                return L.s("최근 폭이 조금 넓습니다.", "The range has been a bit wider lately.")
            }
        }()
        let basisText = L.s(
            "측정 \(data.count)회 · 표준편차 \(sdStr) kg · 최근 6개월",
            "\(data.count) readings · SD \(sdStr) kg · last 6 months"
        )

        VStack(alignment: .leading, spacing: 6) {
            Text(L.s("유지", "Stability"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(titleText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text(sdSentence)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "AEAEB2"))
            Text(basisText)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "636366"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var healthStoryCardView: some View {
        let L = AppLanguage.shared
        let storyA = (
            headline: L.s(
                "체중이 크게 줄지 않아도 달리기만으로 간 지방이 줄었습니다.",
                "Running alone reduces liver fat — even without significant weight loss."
            ),
            body: L.s(
                "무작위 배정 연구 14편 551명에서 운동군의 평균 체중 감소는 2.8%뿐이었는데도, 간 지방이 30% 이상 줄어든 사람이 3.5배 많았습니다.",
                "Across 14 randomized trials (551 people), the exercise group lost just 2.8% of body weight on average — yet were 3.5× more likely to reduce liver fat by 30% or more."
            ),
            cite: "Stine 2023, Am J Gastroenterol"
        )
        let storyB = (
            headline: L.s(
                "주 1시간 미만 달려도 주 3시간 이상 달리는 사람과 같은 이득을 얻었습니다.",
                "Running less than 1 hour per week yields the same benefit as 3+ hours."
            ),
            body: L.s(
                "55,137명을 15년 추적한 연구에서 러너는 전체 사망 위험이 30%, 심혈관 사망 위험이 45% 낮았고 평균 3년 더 살았습니다.",
                "In a 15-year study of 55,137 adults, runners had 30% lower all-cause mortality and 45% lower cardiovascular mortality, living an average of 3 years longer."
            ),
            cite: "Lee 2014, J Am Coll Cardiol"
        )
        let story = healthStoryIndex == 0 ? storyA : storyB

        VStack(alignment: .leading, spacing: 6) {
            Text(L.s("건강 이야기", "Health Insight"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(story.headline)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(story.body)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "AEAEB2"))
                .fixedSize(horizontal: false, vertical: true)
            Text(story.cite)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "636366"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            guard shouldShowHealthStory && !healthStoryRecorded else { return }
            healthStoryRecorded = true
            let key = healthStoryIndex == 0 ? "health.story.a" : "health.story.b"
            var log = MRAdviceLogStore.load()
            log.markShown(key)
            MRAdviceLogStore.save(log)
            let next = (healthStoryIndex + 1) % 2
            UserDefaults.standard.set(next, forKey: Self.healthStoryIndexKey)
            #if DEBUG
            let label = healthStoryIndex == 0 ? "(a)" : "(b)"
            print("[몸] 건강 이야기 \(label) 기록 완료 — 다음 표시 \(next == 0 ? "(a)" : "(b)")")
            #endif
        }
    }

    // MARK: 몸의 변화 헬퍼

    private func bodyChangeStdDev(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count - 1)
        return variance.squareRoot()
    }
}

// MARK: - Heatmap View

private struct RunHeatmap: View {
    let columns: [WeekColumn]

    private let cellSize: CGFloat = 12
    private let gap: CGFloat = 3
    private let labelW: CGFloat = 16

    // Mon, -, Wed, -, Fri, Sat, Sun  (blank on Tue/Thu to reduce clutter)
    private var dayLabels: [String] {
        AppLanguage.shared.isEnglish
            ? ["M", "", "W", "", "F", "Sa", "Su"]
            : ["월", "", "수", "", "금", "토", "일"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Grid: header + 7 rows
            VStack(alignment: .leading, spacing: gap) {
                weekHeaderRow
                ForEach(0..<7, id: \.self) { dayIdx in
                    dayRow(dayIdx: dayIdx)
                }
            }

            // Legend
            legend
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // Top row: sparse week-start labels
    private var weekHeaderRow: some View {
        HStack(spacing: gap) {
            Color.clear.frame(width: labelW, height: 10)
            ForEach(0..<columns.count, id: \.self) { w in
                if w == 0 || monthChanges(at: w) {
                    Text(shortDate(columns[w].id))
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: cellSize, alignment: .leading)
                        .fixedSize()
                        .allowsTightening(true)
                } else {
                    Color.clear.frame(width: cellSize, height: 10)
                }
            }
        }
    }

    // One day-of-week row across all week columns
    private func dayRow(dayIdx: Int) -> some View {
        HStack(spacing: gap) {
            Text(dayLabels[dayIdx])
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: labelW, height: cellSize, alignment: .trailing)

            ForEach(columns) { col in
                let cell = col.days[dayIdx]
                RoundedRectangle(cornerRadius: 2)
                    .fill(cellColor(km: cell.km, isFuture: cell.isFuture))
                    .frame(width: cellSize, height: cellSize)
            }
        }
    }

    // Color intensity scale (5 levels)
    private func cellColor(km: Double, isFuture: Bool) -> Color {
        let streak = Color(hex: "FF9F0A")
        if isFuture    { return Color.white.opacity(0.04) }
        if km == 0     { return streak.opacity(0.10) }
        if km < 3      { return streak.opacity(0.32) }
        if km < 6      { return streak.opacity(0.56) }
        if km < 10     { return streak.opacity(0.80) }
        return streak
    }

    // Color scale legend
    private var legend: some View {
        let L = AppLanguage.shared
        return HStack(spacing: 5) {
            Spacer()
            Text(L.s("적음", "Less"))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            ForEach([0.0, 2.0, 5.0, 8.0, 12.0], id: \.self) { km in
                RoundedRectangle(cornerRadius: 2)
                    .fill(cellColor(km: km, isFuture: false))
                    .frame(width: cellSize, height: cellSize)
            }
            Text(L.s("많음", "More"))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
    }

    // Show label when the month changes between two consecutive columns
    private func monthChanges(at w: Int) -> Bool {
        guard w > 0 else { return false }
        let cal = Calendar.current
        let prevMonth = cal.component(.month, from: columns[w - 1].id)
        let currMonth = cal.component(.month, from: columns[w].id)
        return prevMonth != currMonth
    }

    private static let shortDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
    private func shortDate(_ date: Date) -> String {
        Self.shortDateFmt.string(from: date)
    }
}

// MARK: - PR Grid

private struct PRGrid: View {
    let entries: [PREntry]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(entries) { entry in
                PRCard(entry: entry)
            }
        }
    }
}

private struct PRCard: View {
    let entry: PREntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(entry.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if entry.isNew {
                    Text("NEW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Text(entry.activity.formattedDuration)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                if let pace = entry.activity.formattedPace {
                    Text(pace + "/km")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.pace)
                }
                Text(shortDate(entry.activity.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.violet.opacity(0.35), lineWidth: 1)
        )
    }

    private static let shortDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yy.M.d"; return f
    }()
    private func shortDate(_ date: Date) -> String {
        Self.shortDateFmt.string(from: date)
    }
}

// MARK: - Journey Timeline

private struct JourneyTimeline: View {
    let events: [MilestoneEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                HStack(alignment: .top, spacing: 14) {
                    // Vertical node + connector
                    VStack(spacing: 0) {
                        Circle()
                            .fill(nodeColor(for: event.kind))
                            .frame(width: 10, height: 10)
                            .padding(.top, 4)
                        if idx < events.count - 1 {
                            Rectangle()
                                .fill(Theme.violet.opacity(0.25))
                                .frame(width: 1.5)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 10)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(dateString(event.date))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(event.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(event.detail)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(detailColor(for: event.kind))
                    }
                    .padding(.bottom, idx < events.count - 1 ? 20 : 0)

                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func nodeColor(for kind: MilestoneEvent.Kind) -> Color {
        switch kind {
        case .first:      return Theme.violet
        case .distance:   return Theme.violet
        case .cumulative: return Theme.pace
        case .longest:    return Theme.violet.opacity(0.65)
        }
    }

    private func detailColor(for kind: MilestoneEvent.Kind) -> Color {
        switch kind {
        case .cumulative: return Theme.pace
        default:          return Theme.violet
        }
    }

    private static let dateStringFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yy.M.d"; return f
    }()
    private func dateString(_ date: Date) -> String {
        Self.dateStringFmt.string(from: date)
    }
}

// MARK: - Weekly Distance Chart

// MARK: - Metric Spark Card

private struct MetricSparkCard: View {
    let metric: TrendMetric
    let manager: HealthKitManager
    let usePounds: Bool
    var preloadedPoints: [(date: Date, value: Double)]? = nil
    let onTap: () -> Void

    @State private var dataPoints: [(date: Date, value: Double)] = []
    @State private var isLoading = true

    private var currentValue: Double? { dataPoints.last?.value }

    private var isNeutral: Bool {
        metric == .bodyMass || metric == .bodyFatPercentage
    }

    // MDC₉₅ = 1.96 × SD × √(1/n_recent + 1/n_base) — 절대값 비교, % 아님
    // ⚠ % 기반 문턱은 CV가 작은 지표(케이던스)는 너무 민감하고
    //   CV가 큰 지표(VO2max)는 너무 둔감하다. 절대 스케일이 공정하다.
    private var mdcTest: (isSignificant: Bool, ratio: Double)? {
        guard dataPoints.count >= 4 else { return nil }
        let values = dataPoints.map(\.value)
        let half = values.count / 2
        guard half > 0 else { return nil }
        let base   = Array(values.prefix(half))
        let recent = Array(values.suffix(values.count - half))
        let rMean  = recent.reduce(0, +) / Double(recent.count)
        let bMean  = base.reduce(0, +)   / Double(base.count)
        let mean   = values.reduce(0, +) / Double(values.count)
        let sd     = values.count > 1
            ? (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count - 1)).squareRoot()
            : 0
        let mdc95  = 1.96 * sd * (1.0 / Double(recent.count) + 1.0 / Double(base.count)).squareRoot()
        let delta  = rMean - bMean
        let ratio  = bMean != 0 ? delta / abs(bMean) : 0
        return (isSignificant: abs(delta) >= mdc95, ratio: ratio)
    }

    private var sparklineColor: Color {
        isNeutral ? Color(hex: "6E6E78") : metric.sparkColor
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(metric.koreanLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if isLoading {
                    Color.clear
                        .frame(height: 56)
                        .overlay(ProgressView().scaleEffect(0.7).tint(Theme.violet))
                } else if let cur = currentValue {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(metric.formattedValue(cur, usePounds: usePounds))
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(isNeutral ? Color.secondary : .white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if !isNeutral, let t = mdcTest {
                            if t.isSignificant {
                                let sign: String = t.ratio >= 0 ? "+" : "−"
                                let isGood = metric.lowerIsBetter ? t.ratio < 0 : t.ratio > 0
                                Text(String(format: "%@%.1f%%", sign, abs(t.ratio * 100)))
                                    .font(.system(size: 11))
                                    .foregroundStyle(isGood ? metric.sparkColor : Color(hex: "FF9F0A"))
                                    .lineLimit(1)
                            } else {
                                Text(AppLanguage.shared.s("변화 없음", "No change"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.white.opacity(0.30))
                                    .lineLimit(1)
                            }
                        }
                    }
                    sparkline
                } else {
                    Text(AppLanguage.shared.s("데이터 없음", "No Data"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(height: 36)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .task {
            if let pre = preloadedPoints {
                // 부모가 이미 불러온 데이터 사용 — 중복 조회 없음
                dataPoints = pre
                isLoading = false
            } else {
                // bodyMass / bodyFatPercentage 등 부모가 로드하지 않는 지표만 자체 조회
                let from = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
                dataPoints = await manager.fetchMetricHistory(metric, from: from, usePounds: usePounds)
                isLoading = false
            }
        }
        .onChange(of: preloadedPoints?.count) {
            // 부모의 refreshMetricAnalyses 완료 후 데이터가 늦게 도착하면 반영
            if let pre = preloadedPoints {
                dataPoints = pre
                isLoading = false
            }
        }
    }

    @ViewBuilder
    private var sparkline: some View {
        if dataPoints.count >= 2 {
            let values  = dataPoints.map(\.value)
            let minVal  = values.min() ?? 0
            let maxVal  = values.max() ?? 1
            let spread  = maxVal - minVal
            let padding = spread > 0 ? spread * 0.4 : max(maxVal * 0.05, 1.0)

            Chart(dataPoints, id: \.date) { pt in
                LineMark(
                    x: .value("날짜", pt.date),
                    y: .value(metric.unit, pt.value)
                )
                .foregroundStyle(sparklineColor)
                .lineStyle(StrokeStyle(lineWidth: 2.0))
                .interpolationMethod(.catmullRom)

                // 점은 폼 카드 미니 차트의 강조 점과 같은 모양 — 흰 테두리 위에 선 색 속.
                // (폼 카드에서 평소 범위를 벗어난 구간에 찍는 그 점)
                PointMark(
                    x: .value("날짜", pt.date),
                    y: .value(metric.unit, pt.value)
                )
                .foregroundStyle(Color.white)
                .symbolSize(Theme.sparkHaloSize)
                PointMark(
                    x: .value("날짜", pt.date),
                    y: .value(metric.unit, pt.value)
                )
                .foregroundStyle(sparklineColor)
                .symbolSize(Theme.sparkHaloCoreSize)
            }
            .chartYScale(domain: (minVal - padding)...(maxVal + padding))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 36)
        } else {
            Color.clear.frame(height: 32)
        }
    }
}

// MARK: - Shared sub-views

private struct SectionLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct EmptyChartPlaceholder: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Week Stat Tile

private struct WeekStatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "8A8A92"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("안정 문장 카드") {
    ZStack {
        Theme.background.ignoresSafeArea()
        MRFormObservationCard(
            text: "최근 14일간 케이던스와 보폭이 안정적으로 유지되고 있어요. 큰 변화 없이 꾸준한 달리기 스타일이 자리를 잡고 있습니다.",
            basis: "14일 창·분석 지표 6개(케이던스·파워·지면접촉·보폭·수직진폭·VO2max) 중 5개 이상 ±5% 이내 → 안정 판정",
            isStable: true
        )
        .padding(16)
    }
    .preferredColorScheme(.dark)
}

#Preview("주간 패턴 — p21 기온 보정 (8월 시뮬레이션)") {
    let woy = Calendar.current.component(.weekOfYear, from: Date())
    let pattern = WeeklyPattern(
        priority: 21, key: "heatAdjusted",
        factSummary: "28°C, 실제 6'21\"/km → 15°C 환산 6'06\"/km",
        basis: "본인 러닝 493회로 계산 · 28°C에서 4.5% 보정",
        shortNames: ["더운 날의 러닝", "기온 보정 페이스"],
        koTemplates: [
            "최근 7일 평균 6'21\"/km, 기온은 28°C였어요. 15°C였다면 6'06\" 정도예요.",
            "28°C에서 6'21\"/km로 달렸어요. 같은 몸으로 15°C에서 뛰면 6'06\"쯤 됩니다.",
            "이번 더위에서 6'21\"/km. 기온을 걷어내면 6'06\" 수준이에요.",
            "28°C의 최근 7일, 평균 6'21\"/km — 같은 노력이라면 15°C에서 6'06\"예요.",
        ],
        enTemplates: ["28°C week, 6'21\"/km avg — same effort at 15°C would be 6'06\"."]
    )
    let commentText = pattern.template(for: woy, isEnglish: false)
    let symbol = "thermometer.sun.fill"
    let iconColor = Color(hex: "FF9F0A")

    ZStack {
        Theme.background.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(pattern.shortName(for: woy, isEnglish: AppLanguage.shared.isEnglish))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            Text(commentText)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "AEAEB2"))
            if !pattern.basis.isEmpty {
                Text(pattern.basis)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "636366"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(16)
    }
    .preferredColorScheme(.dark)
}

#Preview("주간 지표 추세 카드") {
    // 판정기 UI 검증용 — good(초록)·neutral(회색)·bad(8A8A92) 색상과 변화율 % 확인
    let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    let cases: [(label: String, value: String, arrow: String?, arrowColor: Color, ratio: String?, lineColor: Color)] = [
        ("케이던스",      "178 spm",      "↑", .green,              "+6.2%",  .green),
        ("파워",         "245 W",        "↓", Color(hex:"8A8A92"), "−3.1%",  Theme.violet),
        ("지면 접촉 시간","248 ms",       "↓", .green,              "−4.8%",  .green),
        ("보폭",         "1.28 m",       nil, Color(hex:"6E6E78"), "+0.8%",  Theme.violet),
        ("수직 진폭",    "8.4 cm",       "↑", Color(hex:"8A8A92"), "+5.5%",  Theme.violet),
        ("유산소 피트니스","42.3 mL/kg·min","↑",.green,             "+7.1%",  .green),
        ("체중",         "72.4 kg",      nil, Color(hex:"6E6E78"), "+1.2%",  Theme.violet),
        ("체지방률",      "19.9%",        nil, Color(hex:"6E6E78"), "−0.3%",  Theme.violet),
    ]
    return ZStack {
        Theme.background.ignoresSafeArea()
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(cases, id: \.label) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(c.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            Spacer()
                            if let a = c.arrow { Text(a).font(.system(size: 10, weight: .bold)).foregroundStyle(c.arrowColor) }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(c.value).font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                            if let r = c.ratio { Text(r).font(.system(size: 11)).foregroundStyle(Color(hex: "6E6E78")) }
                        }
                        RoundedRectangle(cornerRadius: 2).fill(c.lineColor).frame(height: 2).padding(.top, 4)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(16)
        }
    }
}

#Preview("이번 주 누적 블록") {
    ZStack {
        Theme.background.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("이번 주")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text("월요일부터 지금까지")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "8A8A92"))
            }
            HStack(spacing: 8) {
                WeekStatTile(value: "18.4 km", label: "거리")
                WeekStatTile(value: "2시간 3분", label: "시간")
                WeekStatTile(value: "3회", label: "횟수")
                WeekStatTile(value: "4주", label: "연속")
            }
        }
        .padding(16)
    }
}
