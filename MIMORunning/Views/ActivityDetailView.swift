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
    case map                 = "경로"
    case splits              = "스플릿"
    case heartRate           = "심박수"
    case cadence             = "케이던스"
    case groundContact       = "지면 접촉"
    case strideLength        = "보폭"
    case power               = "파워"
    case verticalOscillation = "수직진폭"
    case elevation           = "고도"
    case intervals           = "인터벌"

    var label: String {
        let L = AppLanguage.shared
        return switch self {
        case .map:                  L.s("경로",     "Route")
        case .splits:               L.s("스플릿",   "Splits")
        case .heartRate:            L.s("심박수",   "HR")
        case .cadence:              L.s("케이던스", "Cadence")
        case .groundContact:        L.s("지면 접촉","Gnd Contact")
        case .strideLength:         L.s("보폭",     "Stride")
        case .power:                L.s("파워",     "Power")
        case .verticalOscillation:  L.s("수직진폭", "Vert. Osc.")
        case .elevation:            L.s("고도",     "Elevation")
        case .intervals:            L.s("인터벌",   "Intervals")
        }
    }

    var icon: String {
        switch self {
        case .map:                  return "map.fill"
        case .splits:               return "chart.bar.fill"
        case .heartRate:            return "heart.fill"
        case .cadence:              return "figure.run"
        case .groundContact:        return "stopwatch"
        case .strideLength:         return "arrow.left.and.right"
        case .power:                return "bolt.fill"
        case .verticalOscillation:  return "arrow.up.and.down"
        case .elevation:            return "mountain.2.fill"
        case .intervals:            return "repeat"
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
    @State private var showPanelShareCard = false
    @State private var activePanel: DetailPanel = .map
    @State private var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    @State private var panelSeriesData: [(offset: TimeInterval, value: Double)] = []
    @State private var panelSeriesCache: [DetailPanel: [(offset: TimeInterval, value: Double)]] = [:]
    @State private var isLoadingPanelSeries = false
    @State private var hillMatch: HillMatch?
    @Environment(RaceDetector.self) private var raceDetector

    private var level: LevelBucket { manager.userLevel.bucket }

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
    }

    private var detailContent: some View {
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
                                    confirmedRace: confirmedRaceMatch, hillMatch: hillMatch)
                    }
                    StorySection(workoutID: activity.id.uuidString)
                    panelShareHeader
                    panelSection
                    panelChipRow
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
                                  firstCoordinate: detail?.routeCoordinates.first)
                    }
                    if let zones = detail?.hrZones, !zones.isEmpty {
                        HRZonesSection(zones: zones)
                    }
                    Spacer(minLength: 32)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle(activity.type.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showShareCard = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .foregroundStyle(Theme.violet)
                .disabled(isLoadingDetail)
            }
        }
        .navigationDestination(isPresented: $showShareCard) {
            ShareCardScreen(activity: activity, detail: detail, insight: insight, manager: manager, condition: condition)
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
        .sheet(isPresented: $showPanelShareCard) {
            DetailPanelShareCardScreen(
                activity: activity, detail: detail,
                activePanel: activePanel,
                hrSamples: hrSamples, panelSeriesData: panelSeriesData,
                condition: condition
            )
        }
        .onChange(of: activePanel) { _, newPanel in
            if newPanel == .heartRate, hrSamples.isEmpty {
                Task { hrSamples = await manager.fetchHRTimeSeries(for: activity.id) }
            }
            switch newPanel {
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
        .task {
            // Non-running activities: just fetch detail, no insight computation
            guard activity.type == .running else {
                detail = await manager.fetchDetail(for: activity.id)
                isLoadingDetail = false
                return
            }

            let lang = AppLanguage.shared.isEnglish ? "en" : "ko"

            // Phase 1: quick insight off main thread (no workout-type yet)
            let initial: InsightResult
            if let cached = await InsightCache.shared.result(for: activity.id, isRefined: false, language: lang) {
                initial = cached
            } else {
                let computed = await InsightEngine.computeBackground(
                    activity: activity, history: manager.activities, level: level,
                    raceMatch: raceDetector.matchFor(activityID: activity.id))
                await InsightCache.shared.cache(computed, for: activity.id, isRefined: false, language: lang)
                initial = computed
            }
            // If refined cache already exists, show it immediately to avoid Phase 1 → Phase 3 flash
            if let refinedCached = await InsightCache.shared.result(for: activity.id, isRefined: true, language: lang) {
                insight = refinedCached
            } else {
                insight = initial
            }

            // Phase 2: fetch detail — splits drive workout-type classification
            detail = await manager.fetchDetail(for: activity.id)
            isLoadingDetail = false

            hillMatch = HillSpotDetector.shared.assess(
                routeCoords: detail?.routeCoordinates ?? [],
                elevationGain: detail?.elevationGain
            ).first(where: { $0.matched })

            // Phase 2b: fetch condition (weather archive + sleep) using first route point
            let firstCoord = detail?.routeCoordinates.first
            async let conditionFetch = manager.fetchCondition(for: activity, firstCoordinate: firstCoord)

            // Phase 2c: assess race match (async, region-aware, route-informed)
            async let raceFetch: RaceSuggestion? = raceDetector.assess(
                activityID: activity.id,
                date: activity.date,
                distanceKm: activity.distance / 1000,
                startCoord: firstCoord,
                routeCoords: detail?.routeCoordinates ?? []
            )
            let (fetchedCondition, suggestion) = await (conditionFetch, raceFetch)
            withAnimation(.easeIn(duration: 0.2)) { condition = fetchedCondition }

            // Strong match → auto-confirm immediately (user can revoke via badge button)
            if let s = suggestion, s.strength == .strong {
                raceDetector.confirm(activityID: activity.id, race: s.primary,
                                     activityDistanceKm: activity.distance / 1000)
                await recomputeInsightWithRaceMatch()
            } else {
                withAnimation(.easeIn) { raceSuggestion = suggestion }
            }

            // Phase 3: refine insight off main thread with workout type + splits + condition
            let refined: InsightResult
            if let det = detail {
                if let cached = await InsightCache.shared.result(for: activity.id, isRefined: true, language: lang) {
                    refined = cached
                    // Already showing this result — no animation needed (avoids flash)
                } else {
                    let computed = await InsightEngine.computeBackground(
                        activity: activity,
                        history: manager.activities,
                        level: level,
                        workoutType: det.workoutType,
                        splits: det.splits,
                        intervalSegments: det.intervalSegments,
                        condition: fetchedCondition,
                        raceMatch: raceDetector.matchFor(activityID: activity.id),
                        detail: det
                    )
                    await InsightCache.shared.cache(computed, for: activity.id, isRefined: true, language: lang)
                    refined = computed
                    withAnimation(.easeInOut(duration: 0.3)) { insight = refined }
                }
            } else {
                refined = initial
            }

            // Phase 4: optional on-device AI rewrite (iOS 26+)
            // tryAIEnhance returns nil if already enhanced (aiEnhanced == true) — runs once per activity.
            if let aiResult = await InsightEngine.tryAIEnhance(refined) {
                await InsightCache.shared.cache(aiResult, for: activity.id, isRefined: true, language: lang)
                withAnimation(.easeInOut(duration: 0.4)) { insight = aiResult }
            }
        }
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
            detail: detail
        )
        let isRefined = detail != nil
        await InsightCache.shared.cache(recomputed, for: activity.id, isRefined: isRefined, language: lang)
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

    // MARK: - Panel availability

    private func isAvailable(_ panel: DetailPanel) -> Bool {
        guard !isLoadingDetail else { return false }
        switch panel {
        case .map:                  return !(detail?.routeCoordinates ?? []).isEmpty
        case .splits:               return !(detail?.splits ?? []).isEmpty
        case .heartRate:            return activity.avgHeartRate != nil
        case .cadence:              return detail?.avgCadence != nil
        case .groundContact:        return detail?.avgGroundContactTime != nil
        case .strideLength:         return detail?.avgStrideLength != nil
        case .power:                return detail?.avgPower != nil
        case .verticalOscillation:  return detail?.avgVerticalOscillation != nil
        case .elevation:            return !(detail?.altitudeProfile ?? []).isEmpty
        case .intervals:            return !(detail?.intervalSegments ?? []).isEmpty
        }
    }

    // MARK: - Panel section (replaces mapSection)

    @ViewBuilder
    private var panelSection: some View {
        if isLoadingDetail {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
                .frame(height: 220)
                .overlay { ProgressView().tint(Theme.violet) }
                .padding(.horizontal, 16)
        } else {
            Group {
                if activePanel == .map {
                    if let coords = detail?.routeCoordinates, !coords.isEmpty {
                        RouteMapView(coordinates: coords, activityID: activity.id)
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

    private var panelContentHeight: CGFloat {
        if activePanel == .intervals, let segs = detail?.intervalSegments, !segs.isEmpty {
            return IntervalPanelChart.requiredHeight(segmentCount: segs.count, hasSummary: true)
        }
        return 220
    }

    @ViewBuilder
    private var panelInnerContent: some View {
        switch activePanel {
        case .map:
            EmptyView()
        case .splits:
            if let splits = detail?.splits, !splits.isEmpty {
                SplitsPanelChart(splits: splits, compact: true, isLargeDisplay: true)
            } else {
                panelPlaceholder(icon: "chart.bar.fill", message: AppLanguage.shared.s("스플릿 없음", "No Splits"))
            }
        case .heartRate:
            if hrSamples.isEmpty {
                ProgressView().tint(Theme.violet)
            } else {
                HRSeriesPanelChart(samples: hrSamples, zones: detail?.hrZones ?? [])
            }
        case .elevation:
            if let profile = detail?.altitudeProfile, !profile.isEmpty {
                ElevationPanelChart(profile: profile)
            } else {
                panelPlaceholder(icon: "mountain.2.fill", message: AppLanguage.shared.s("고도 데이터 없음", "No Elevation Data"))
            }
        case .intervals:
            if let segs = detail?.intervalSegments, !segs.isEmpty {
                IntervalPanelChart(segments: segs)
            } else {
                panelPlaceholder(icon: "repeat", message: AppLanguage.shared.s("인터벌 없음", "No Intervals"))
            }
        case .cadence:
            seriesPanel(icon: "figure.run", label: AppLanguage.shared.s("케이던스", "Cadence"), unit: "spm",
                        color: Theme.cadence, format: "%.0f", useRangeBar: false,
                        validMin: 130,
                        available: detail?.avgCadence != nil)
        case .power:
            seriesPanel(icon: "bolt.fill", label: AppLanguage.shared.s("파워", "Power"), unit: "W",
                        color: Theme.power, format: "%.0f", useRangeBar: true,
                        available: detail?.avgPower != nil)
        case .groundContact:
            seriesPanel(icon: "stopwatch", label: AppLanguage.shared.s("지면 접촉", "Gnd Contact"), unit: "ms",
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

    private func panelPlaceholder(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func seriesPanel(icon: String, label: String, unit: String,
                             color: Color, format: String, useRangeBar: Bool = false,
                             validMin: Double = 0,
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
                                validMin: validMin)
        }
    }

    // MARK: - Panel chip row (below MetricGrid)

    private var panelChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DetailPanel.allCases, id: \.self) { panel in
                    let available = isAvailable(panel)
                    let selected  = activePanel == panel
                    Button {
                        guard available else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { activePanel = panel }
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

    private var panelShareHeader: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: activePanel.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.violet)
                Text(activePanel.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button { showPanelShareCard = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                    Text(AppLanguage.shared.s("공유", "Share"))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.violet)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.violet.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Header

private struct DetailHeader: View {
    let activity: Activity
    var confirmedRace: PersistedRaceMatch? = nil
    var onRaceRevoke: (() -> Void)? = nil

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
                    Text({
                        let df = DateFormatter()
                        df.locale = Locale(identifier: AppLanguage.shared.s("ko_KR", "en_US"))
                        df.dateFormat = AppLanguage.shared.s(
                            "yyyy년 M월 d일 EEEE  a h:mm",
                            "EEEE, MMMM d, yyyy  h:mm a"
                        )
                        return df.string(from: activity.date)
                    }())
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

    private var effectiveHRV: HRVRecovery? {
        condition?.hrvRecovery
    }

    private func pick(_ options: [String]) -> String {
        let seed = Int(abs(activity.date.timeIntervalSinceReferenceDate))
        return options[seed % options.count]
    }

    private func recoveryLine(sleep: SleepScore, hrv: HRVRecovery) -> String {
        let L = AppLanguage.shared
        let sleepGood = sleep.score >= 70
        switch hrv.level {
        case .high:
            return pick([
                L.s("컨디션이 좋은 날이었네요", "Your body was primed today"),
                L.s("회복이 잘 된 좋은 날이었어요", "Well-rested and ready to go"),
            ])
        case .normal:
            return sleepGood
                ? pick([
                    L.s("잘 회복된 상태로 달렸어요", "You ran well-recovered"),
                    L.s("회복이 잘 된 상태였어요", "Your body was nicely recovered"),
                  ])
                : pick([
                    L.s("수면은 짧았지만 회복은 괜찮았어요", "Short sleep, but recovery held up"),
                    L.s("수면이 적었어도 회복 상태는 나쁘지 않았어요", "Less sleep, but recovery was decent"),
                  ])
        case .low:
            return sleepGood
                ? pick([
                    L.s("잘 잤지만 회복은 평소보다 더뎠을 수 있어요", "Good sleep, but recovery may have lagged a bit"),
                    L.s("수면은 충분했어도 회복이 조금 더 필요했을 수 있어요", "Enough sleep, but recovery may have needed more time"),
                  ])
                : pick([
                    L.s("평소보다 피로가 남아있었을 수 있어요 (가볍게도 좋아요)", "Some lingering fatigue — easy effort works too"),
                    L.s("몸이 평소보다 조금 더 피로했을 수 있어요", "Your body may have carried a bit more fatigue"),
                  ])
        case .insufficient:
            return L.s("잘 회복된 상태로 달렸어요", "You ran well-recovered")
        }
    }

    // ── 컨디션 행: 날씨 칩 + (수면+HRV 통합 문구 or 수면 칩) ──
    @ViewBuilder
    private var conditionRow: some View {
        let hrv = effectiveHRV
        let validHRV: HRVRecovery? = {
            guard let h = hrv, h.level != .insufficient else { return nil }
            return h
        }()
        if let cond = condition, cond.weather != nil || cond.sleepScore != nil {
            HStack(alignment: .center, spacing: 6) {
                if let w = cond.weather {
                    let wColor: Color = {
                        if w.isRainy { return Theme.pace }
                        if w.isHot   { return Theme.calories }
                        if w.isCold  { return .blue }
                        return .secondary
                    }()
                    ConditionChip(icon: w.systemIcon, label: w.formattedTemp, color: wColor)
                }
                if let slp = cond.sleepScore, let vh = validHRV {
                    Text(recoveryLine(sleep: slp, hrv: vh))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else if let slp = cond.sleepScore {
                    ConditionChip(
                        icon: "bed.double.fill",
                        label: AppLanguage.shared.s("수면 \(slp.chipLabel)", "Sleep \(slp.chipLabel)"),
                        color: slp.isInsufficient ? Theme.time : .secondary
                    )
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
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                    Text(insight?.detail ?? AppLanguage.shared.s("인사이트 분석 준비 중", "Analyzing…"))
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

private struct RouteMapView: View {
    let coordinates: [CLLocationCoordinate2D]
    let activityID: UUID

    @State private var snapshot: UIImage?

    var body: some View {
        ZStack {
            if let img = snapshot {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "0D0D12"))
                    .frame(height: 220)
                    .overlay { ProgressView().tint(Theme.violet) }
            }
        }
        .padding(.horizontal, 16)
        .task(id: activityID) {
            guard snapshot == nil else { return }
            if let cached = loadFromDisk() {
                snapshot = cached
            } else if let generated = await makeSnapshot() {
                snapshot = generated
                saveToDisk(generated)
            }
        }
    }

    // MARK: - Disk cache

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mimo_map_v7_\(activityID.uuidString).jpg")
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

    // MARK: - Snapshot generation

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
        opts.mapType = .mutedStandard
        opts.showsBuildings = false

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

            // End dot
            if let last = pts.last {
                let dot = UIBezierPath(ovalIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6))
                UIColor.white.setFill()
                dot.fill()
            }
        }
    }
}

// MARK: - Metric grid

private struct MetricGrid: View {
    let activity: Activity
    let detail: ActivityDetail?
    let age: Int?
    let isMale: Bool?

    private struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let value: String
        let color: Color
        var note: String? = nil
        var trendMetric: TrendMetric? = nil
        var compactValue: Bool = false  // true → title3, false → title2
    }

    private var items: [Item] {
        switch activity.type {
        case .cycling:  return cyclingItems
        case .swimming: return swimmingItems
        default:        return generalItems
        }
    }

    private var generalItems: [Item] {
        let L = AppLanguage.shared
        var list: [Item] = [
            Item(icon: "ruler", label: L.s("거리", "Dist."), value: activity.formattedDistance, color: .white),
            Item(icon: "clock", label: L.s("시간", "Time"), value: activity.formattedDuration, color: Theme.time),
        ]
        if let pace = activity.formattedPace {
            list.append(Item(icon: "timer", label: L.s("페이스", "Pace"), value: pace, color: Theme.pace))
        }
        if let hr = activity.avgHeartRate {
            list.append(Item(icon: "heart.fill", label: L.s("평균 심박", "Avg HR"), value: "\(hr) bpm", color: Theme.heartRate))
        }
        if activity.type == .running {
            if let cadence = detail?.avgCadence {
                list.append(Item(icon: "figure.run", label: L.s("케이던스", "Cadence"), value: "\(cadence) spm",
                                 color: .white, trendMetric: .cadence))
            }
            if let power = detail?.avgPower {
                list.append(Item(icon: "bolt.fill", label: L.s("파워", "Power"), value: "\(power) W",
                                 color: Theme.power, trendMetric: .power))
            }
            if let gct = detail?.avgGroundContactTime {
                list.append(Item(icon: "stopwatch", label: L.s("지면 접촉", "Gnd Contact"),
                                 value: "\(Int(gct.rounded())) ms", color: Theme.runningForm,
                                 trendMetric: .groundContactTime))
            }
            if let stride = detail?.avgStrideLength {
                list.append(Item(icon: "arrow.left.and.right", label: L.s("보폭", "Stride"),
                                 value: String(format: "%.2f m", stride), color: Theme.runningForm,
                                 trendMetric: .strideLength))
            }
            if let vo = detail?.avgVerticalOscillation {
                list.append(Item(icon: "arrow.up.and.down", label: L.s("수직 진폭", "Vert. Osc."),
                                 value: String(format: "%.1f cm", vo), color: Theme.runningForm,
                                 trendMetric: .verticalOscillation))
            }
            if let vo2 = detail?.vo2Max {
                let rating = CardioFitnessClassifier.rating(vo2: vo2, age: age, isMale: isMale)
                let note = rating.map { L.s("현재 추정 · \($0)", "Curr. Est. · \($0)") } ?? L.s("현재 추정", "Curr. Est.")
                list.append(Item(icon: "lungs.fill", label: L.s("유산소 피트니스", "Cardio Fitness"),
                                 value: String(format: "%.1f mL/kg·min", vo2),
                                 color: Theme.elevation, note: note, trendMetric: .vo2Max, compactValue: true))
            }
        }
        if let cal = activity.calories {
            list.append(Item(icon: "flame.fill", label: L.s("칼로리", "Cals"),
                             value: String(format: "%.0f kcal", cal), color: Theme.calories))
        }
        if let elev = detail?.elevationGain {
            list.append(Item(icon: "arrow.up.right", label: L.s("고도 획득", "Elev. Gain"),
                             value: String(format: "%.0f m", elev), color: Theme.elevation))
        }
        return list
    }

    private var cyclingItems: [Item] {
        let L = AppLanguage.shared
        var list: [Item] = [
            Item(icon: "ruler", label: L.s("거리", "Dist."), value: activity.formattedDistance, color: .white),
            Item(icon: "clock", label: L.s("시간", "Time"), value: activity.formattedDuration, color: Theme.time),
        ]
        let speedKmh = detail?.avgSpeed ?? activity.avgSpeedKmh
        if let speed = speedKmh {
            list.append(Item(icon: "speedometer", label: L.s("평균 속도", "Avg Speed"),
                             value: String(format: "%.1f km/h", speed), color: Theme.pace))
        }
        if let hr = activity.avgHeartRate {
            list.append(Item(icon: "heart.fill", label: L.s("평균 심박", "Avg HR"), value: "\(hr) bpm", color: Theme.heartRate))
        }
        if let power = detail?.avgPower {
            list.append(Item(icon: "bolt.fill", label: L.s("파워", "Power"), value: "\(power) W", color: Theme.power))
        }
        if let cadence = detail?.avgCadence {
            list.append(Item(icon: "arrow.clockwise", label: L.s("케이던스", "Cadence"), value: "\(cadence) rpm", color: .white))
        }
        if let cal = activity.calories {
            list.append(Item(icon: "flame.fill", label: L.s("칼로리", "Cals"),
                             value: String(format: "%.0f kcal", cal), color: Theme.calories))
        }
        if let elev = detail?.elevationGain {
            list.append(Item(icon: "arrow.up.right", label: L.s("고도 획득", "Elev. Gain"),
                             value: String(format: "%.0f m", elev), color: Theme.elevation))
        }
        return list
    }

    private var swimmingItems: [Item] {
        let L = AppLanguage.shared
        var list: [Item] = [
            Item(icon: "ruler", label: L.s("거리", "Dist."), value: activity.formattedDistance, color: .white),
            Item(icon: "clock", label: L.s("시간", "Time"), value: activity.formattedDuration, color: Theme.time),
        ]
        if let pace = activity.formattedPace100m {
            list.append(Item(icon: "timer", label: L.s("페이스", "Pace"), value: "\(pace)/100m", color: Theme.pace))
        }
        if let hr = activity.avgHeartRate {
            list.append(Item(icon: "heart.fill", label: L.s("평균 심박", "Avg HR"), value: "\(hr) bpm", color: Theme.heartRate))
        }
        if let laps = detail?.swimLapCount {
            list.append(Item(icon: "repeat", label: L.s("랩", "Laps"), value: L.s("\(laps)회", "\(laps)"), color: .white))
        }
        if let pool = detail?.poolLength {
            list.append(Item(icon: "arrow.left.and.right", label: L.s("풀 길이", "Pool Length"),
                             value: "\(Int(pool))m", color: .white))
        }
        if let strokes = detail?.swimmingStrokeCount {
            list.append(Item(icon: "hand.draw", label: L.s("총 스트로크", "Strokes"),
                             value: L.s("\(strokes)회", "\(strokes)"), color: .white))
        }
        if let swolf = detail?.swolfScore {
            list.append(Item(icon: "waveform", label: "SWOLF",
                             value: String(format: "%.0f", swolf), color: Theme.pace))
        }
        if let cal = activity.calories {
            list.append(Item(icon: "flame.fill", label: L.s("칼로리", "Cals"),
                             value: String(format: "%.0f kcal", cal), color: Theme.calories))
        }
        return list
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items) { item in
                MetricCell(icon: item.icon, label: item.label, value: item.value,
                           color: item.color, note: item.note, compactValue: item.compactValue)
            }
        }
        .padding(.horizontal, 16)
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
                                        .foregroundStyle(work ? Theme.violet : Color.white.opacity(0.35))
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
                                        weatherText: condition?.weather?.formattedTemp,
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

    @Environment(CustomMiniMeStore.self) private var miniMeStore
    @State private var showSplitsShare = false
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

    // Slower pace = more seconds per km = longer bar. Range: 0.28 (fastest) … 1.0 (slowest).
    private func barFraction(for pace: Double) -> Double {
        let range = maxPace - minPace
        guard range > 0.5 else { return 0.65 }
        return 0.28 + 0.72 * (pace - minPace) / range
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                DetailSectionHeader(title: AppLanguage.shared.s("구간 기록", "Splits"),
                                   subtitle: AppLanguage.shared.s("\(splits.count)개 구간", "\(splits.count) splits"))
                Spacer()
                if activity != nil {
                    Button { showSplitsShare = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption.weight(.semibold))
                            Text(AppLanguage.shared.s("공유", "Share"))
                                .font(.caption.weight(.semibold))
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
        .sheet(isPresented: $showSplitsShare) {
            if let act = activity {
                SplitsShareCardScreen(activity: act, splits: splits, zones: zones, miniMeImage: miniMeStore.image, shoeName: shoeName,
                                      weatherText: condition?.weather?.formattedTemp,
                                      weatherIcon: condition?.weather?.systemIcon,
                                      firstCoordinate: firstCoordinate)
            }
        }
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

    // Apple Fitness zone colors: Z1 blue → Z2 cyan → Z3 lime → Z4 orange → Z5 pink
    private static let zoneColors: [Color] = [
        Color(red: 0.30, green: 0.60, blue: 1.00),  // Z1 Blue
        Color(red: 0.20, green: 0.85, blue: 0.85),  // Z2 Cyan
        Color(red: 0.70, green: 1.00, blue: 0.10),  // Z3 Lime
        Color(red: 1.00, green: 0.60, blue: 0.15),  // Z4 Orange
        Color(red: 1.00, green: 0.30, blue: 0.55),  // Z5 Pink
    ]

    private func zoneColor(_ id: Int) -> Color {
        Self.zoneColors[min(id - 1, 4)]
    }

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
                                .foregroundStyle(hasTime ? color : color.opacity(0.35))
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
                        .foregroundStyle(.tertiary)
                    Text(AppLanguage.shared.s("Karvonen(심박 예비율) 공식 기반 · 최근 30일 최소 안정시 심박(RHR) + 나이별 최대심박(MHR) 추정 적용. 개인 체력 및 측정 조건에 따라 실제 영역과 다를 수 있습니다.", "Based on Karvonen (HRR) formula · Uses lowest resting HR over last 30 days + age-estimated max HR. Zones may differ from actual values."))
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
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
    @State private var showEditor = false
    @Query private var stories: [WorkoutStory]
    @Query private var shoes: [Shoe]
    @Environment(\.modelContext) private var modelContext
    private var story: WorkoutStory? { stories.first }
    private var selectedShoe: Shoe? {
        guard let sid = story?.shoeID else { return nil }
        return shoes.first { $0.id.uuidString == sid }
    }

    init(workoutID: String) {
        self.workoutID = workoutID
        let wid = workoutID
        _stories = Query(filter: #Predicate<WorkoutStory> { $0.workoutID == wid })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !shoes.isEmpty {
                shoePicker
            }
            HStack {
                Label(AppLanguage.shared.s("스토리", "Story"), systemImage: "quote.bubble")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showEditor = true
                } label: {
                    Label(story == nil ? AppLanguage.shared.s("추가", "Add") : AppLanguage.shared.s("편집", "Edit"),
                          systemImage: story == nil ? "plus" : "pencil")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.violet)
                }
            }
            if let s = story {
                StoryDisplay(story: s)
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showEditor) {
            StoryEditorSheet(workoutID: workoutID)
        }
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
}

private struct StoryDisplay: View {
    let story: WorkoutStory

    private var photos: [UIImage] { story.allPhotoImages }
    private var moodColor: Color {
        switch story.mood {
        case .fantastic: Theme.power
        case .great:     Theme.violet
        case .okay:      Theme.time
        case .tough:     Color.orange
        case .terrible:  Theme.heartRate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: story.mood.sfSymbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(moodColor)
                Text(story.mood.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(moodColor)
                Spacer()
                #if canImport(ImagePlayground)
                if #available(iOS 18.2, *), let photo = photos.first {
                    MiniMeUpdateButton(storyPhoto: photo)
                }
                #endif
            }
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

private struct StoryEditorSheet: View {
    let workoutID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var stories: [WorkoutStory]
    private var existingStory: WorkoutStory? { stories.first }

    @State private var memo = ""
    @State private var mood: Mood = .okay
    @State private var photoImages: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    private let maxPhotos = 10

    init(workoutID: String) {
        self.workoutID = workoutID
        let wid = workoutID
        _stories = Query(filter: #Predicate<WorkoutStory> { $0.workoutID == wid })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        moodPicker
                        memoField
                        photoSection
                    }
                    .padding(16)
                }
            }
            .navigationTitle(AppLanguage.shared.s("스토리", "Story"))
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


    private var moodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLanguage.shared.s("느낌", "Mood"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(Mood.allCases, id: \.self) { m in
                    Button { mood = m } label: {
                        VStack(spacing: 5) {
                            Image(systemName: m.sfSymbol)
                                .font(.system(size: 20))
                                .foregroundStyle(mood == m ? moodColor(m) : Color.white.opacity(0.3))
                            Text(m.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(mood == m ? moodColor(m) : Color.white.opacity(0.3))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(mood == m ? moodColor(m).opacity(0.15) : Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(mood == m ? moodColor(m).opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
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
                        photoImages.append(contentsOf: loaded.prefix(available))
                        pickerItems = []
                    }
                }
            }
        }
    }

    private func moodColor(_ m: Mood) -> Color {
        switch m {
        case .fantastic: Theme.power
        case .great:     Theme.violet
        case .okay:      Theme.time
        case .tough:     Color.orange
        case .terrible:  Theme.heartRate
        }
    }

    private func loadExisting() {
        guard let s = existingStory else { return }
        memo = s.memo
        mood = s.mood
        photoImages = s.allPhotoImages
    }

    private func save() {
        if let s = existingStory {
            // Remove old StoryPhoto records
            for photo in s.photos ?? [] { modelContext.delete(photo) }
            s.photos = nil
            // Save new photos as StoryPhoto
            let newPhotos = photoImages.enumerated().compactMap { idx, img -> StoryPhoto? in
                guard let data = img.jpegData(compressionQuality: 0.75) else { return nil }
                return StoryPhoto(data: data, index: idx)
            }
            newPhotos.forEach { modelContext.insert($0) }
            s.photos = newPhotos.isEmpty ? nil : newPhotos
            s.memo = memo
            s.mood = mood
            s.updatedAt = Date()
        } else {
            let story = WorkoutStory(workoutID: workoutID, memo: memo, mood: mood)
            modelContext.insert(story)
            let newPhotos = photoImages.enumerated().compactMap { idx, img -> StoryPhoto? in
                guard let data = img.jpegData(compressionQuality: 0.75) else { return nil }
                return StoryPhoto(data: data, index: idx)
            }
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

    // MARK: - Compact line chart (공유 모드)

    private struct LinePoint: Identifiable {
        let id: Int
        let midMinute: Double
        let invPace: Double   // offset - pace: 빠를수록 큰 값 → 차트 위쪽
        let realPace: Double
        let isFastest: Bool
    }

    private var lineData: (points: [LinePoint], totalMinutes: Double) {
        let offset = minPace + maxPace
        var cum: Double = 0
        var pts: [LinePoint] = []
        for (idx, split) in splits.enumerated() {
            let mid = (cum + split.duration / 2) / 60
            pts.append(LinePoint(
                id: idx,
                midMinute: mid,
                invPace: offset - split.paceSecPerKm,
                realPace: split.paceSecPerKm,
                isFastest: idx == fastestIdx
            ))
            cum += split.duration
        }
        return (pts, cum / 60)
    }

    private func paceLabel(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d'%02d\"", s / 60, s % 60)
    }

    @ViewBuilder
    private var compactLineChart: some View {
        let (pts, totalMin) = lineData
        if pts.count < 2 {
            EmptyView()
        } else {
        let offset   = minPace + maxPace
        let pad      = max((maxPace - minPace) * 0.22, 12.0)
        let domLo    = minPace - pad          // invPace for slowest + padding below
        let domHi    = maxPace + pad          // invPace for fastest + padding above
        let avgInv   = offset - avgPace
        let fastest  = pts.first(where: { $0.isFastest })
        let xStep: Double = totalMin <= 20 ? 5 : totalMin <= 50 ? 10 : 15

        Chart {
            ForEach(pts) { p in
                AreaMark(
                    x: .value("분", p.midMinute),
                    yStart: .value("pace", p.invPace),
                    yEnd: .value("base", domLo)
                )
                .foregroundStyle(LinearGradient(
                    colors: [Self.panelVioletHi.opacity(0.30), Self.panelVioletHi.opacity(0.0)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.catmullRom)
            }
            ForEach(pts) { p in
                LineMark(
                    x: .value("분", p.midMinute),
                    y: .value("pace", p.invPace)
                )
                .foregroundStyle(Self.panelVioletHi)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
            if let fp = fastest {
                PointMark(x: .value("분", fp.midMinute), y: .value("pace", fp.invPace))
                    .foregroundStyle(Self.panelGold)
                    .symbolSize(18)
                    .annotation(position: .top, alignment: .center) {
                        Text(paceLabel(fp.realPace))
                            .font(.system(size: isLargeDisplay ? 13 : 7, weight: .semibold))
                            .foregroundStyle(Self.panelGold)
                    }
            }
            RuleMark(y: .value("평균", avgInv))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .foregroundStyle(Color.white.opacity(0.35))
                .annotation(position: .bottom, alignment: .trailing) {
                    Text("avg " + paceLabel(avgPace))
                        .font(.system(size: isLargeDisplay ? 11 : 6.5))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
        }
        .chartYScale(domain: domLo...domHi)
        .chartXScale(domain: 0...totalMin)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel {
                    if let v = val.as(Double.self) {
                        let real = offset - v
                        if real > 60 {
                            Text(paceLabel(real))
                                .font(.system(size: isLargeDisplay ? 11 : 6))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: stride(from: xStep, through: totalMin, by: xStep).map { $0 }) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel {
                    if let m = val.as(Double.self) {
                        Text(AppLanguage.shared.isEnglish
                             ? String(format: "%.0fm", m)
                             : String(format: "%.0f분", m))
                            .font(.system(size: isLargeDisplay ? 11 : 6))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        } // end else
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

struct HRSeriesPanelChart: View {
    let samples: [(offset: TimeInterval, bpm: Int)]
    var zones: [HRZoneData] = []
    var compact: Bool = false

    private static let zoneColors: [Color] = [
        Color(red: 0.30, green: 0.60, blue: 1.00),
        Color(red: 0.20, green: 0.85, blue: 0.85),
        Color(red: 0.70, green: 1.00, blue: 0.10),
        Color(red: 1.00, green: 0.60, blue: 0.15),
        Color(red: 1.00, green: 0.30, blue: 0.55),
    ]

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
        return Self.zoneColors[min(z.id - 1, 4)]
    }

    private var validSamples: [(offset: TimeInterval, bpm: Int)] {
        samples.filter { $0.offset >= 0 }
    }

    private var totalDurationMinutes: Double {
        max(validSamples.map(\.offset).max() ?? 1, 1) / 60
    }

    private var buckets: [Bucket] {
        guard !validSamples.isEmpty else { return [] }
        let totalDuration = max(validSamples.map(\.offset).max() ?? 1, 1)
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
                          min: vals.min()!,
                          max: vals.max()!,
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
                            .font(.system(size: 9, weight: .medium))
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
                            .font(compact ? .system(size: 8) : .caption2)
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
                            .font(compact ? .system(size: 8) : .caption2)
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
                          avg: avg, min: vals.min()!, max: vals.max()!)
        }
    }

    private var barWidth: CGFloat { barWidthOverride ?? 3 }

    private var avgValue: Double? {
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
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    Text("avg \(unit)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    if useRangeBar, let lo = overallMin, let hi = overallMax {
                        Text("·")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text("\(String(format: format, lo))~\(String(format: format, hi))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
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
            let maxBarW = min(100, max(20, geo.size.width - indexW - typeW - labelW - spacing * 3 - 24))
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
        let startDate = data.map(\.date).min() ?? Calendar.current.date(byAdding: .month, value: -1, to: Date())!

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
