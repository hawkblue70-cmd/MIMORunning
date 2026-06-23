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

private enum DetailPanel: String, CaseIterable {
    case map                 = "지도"
    case splits              = "스플릿"
    case heartRate           = "심박수"
    case cadence             = "케이던스"
    case groundContact       = "지면 접촉"
    case strideLength        = "보폭"
    case power               = "파워"
    case verticalOscillation = "수직진폭"
    case elevation           = "고도"
    case intervals           = "인터벌"

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
    @State private var activePanel: DetailPanel = .map
    @State private var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    @State private var panelSeriesData: [(offset: TimeInterval, value: Double)] = []
    @State private var panelSeriesCache: [DetailPanel: [(offset: TimeInterval, value: Double)]] = [:]
    @State private var isLoadingPanelSeries = false
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
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailHeader(
                        activity: activity,
                        confirmedRace: confirmedRaceMatch,
                        onRaceRevoke: {
                            raceDetector.removeMatch(activityID: activity.id)
                            recomputeInsightWithRaceMatch()
                        }
                    )
                    if activity.type == .running {
                        InsightCard(activity: activity, insight: insight, condition: condition,
                                    confirmedRace: confirmedRaceMatch)
                    }
                    StorySection(workoutID: activity.id.uuidString)
                    panelSection
                    panelChipRow
                    if showRaceBanner {
                        RaceDetectionBanner(
                            suggestion: raceSuggestion,
                            activityID: activity.id,
                            activityDistanceKm: activity.distance / 1000,
                            activityDate: activity.date,
                            onConfirmed: { recomputeInsightWithRaceMatch() },
                            onDismissed: {}
                        )
                    } else if isDismissedRace {
                        Button {
                            raceDetector.resetDismissed(activityID: activity.id)
                            Task { await runRaceAssessment() }
                        } label: {
                            Label("대회 기록 추가", systemImage: "flag.checkered")
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
                        IntervalSegmentsSection(segments: intervals)
                    }
                    if let splits = detail?.splits, !splits.isEmpty {
                        SplitsSection(splits: splits, zones: detail?.hrZones ?? [],
                                  activity: activity, allActivities: manager.activities)
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
                    recomputeInsightWithRaceMatch()
                },
                onCancel: {
                    raceDetector.markAsNotRace(activityID: activity.id)
                }
            )
        }
        .onChange(of: activePanel) { _, newPanel in
            if newPanel == .heartRate, hrSamples.isEmpty {
                Task { hrSamples = await manager.fetchHRTimeSeries(for: activity.id) }
            }
            switch newPanel {
            case .cadence, .power, .groundContact, .strideLength, .verticalOscillation:
                Task { await loadPanelSeries(for: newPanel) }
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

            // Phase 1: show a quick insight immediately (no workout-type yet)
            let initial = InsightEngine.compute(activity: activity, history: manager.activities,
                                                level: level,
                                                raceMatch: raceDetector.matchFor(activityID: activity.id))
            insight = initial

            // Phase 2: fetch detail — splits drive workout-type classification
            detail = await manager.fetchDetail(for: activity.id)
            isLoadingDetail = false

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
                recomputeInsightWithRaceMatch()
            } else {
                withAnimation(.easeIn) { raceSuggestion = suggestion }
            }

            // Phase 3: refine insight with workout type + splits + condition
            let refined: InsightResult
            if let det = detail {
                refined = InsightEngine.compute(
                    activity: activity,
                    history: manager.activities,
                    level: level,
                    workoutType: det.workoutType,
                    splits: det.splits,
                    intervalSegments: det.intervalSegments,
                    condition: fetchedCondition,
                    raceMatch: raceDetector.matchFor(activityID: activity.id)
                )
                withAnimation(.easeInOut(duration: 0.3)) { insight = refined }
            } else {
                refined = initial
            }

            // Phase 4: optional on-device AI rewrite (iOS 26+)
            if let aiResult = await InsightEngine.tryAIEnhance(refined) {
                withAnimation(.easeInOut(duration: 0.4)) { insight = aiResult }
            }
        }
    }

    private var userAge: Int? {
        guard let dob = manager.userDateOfBirth, let year = dob.year else { return nil }
        return Calendar.current.component(.year, from: Date()) - year
    }

    private func recomputeInsightWithRaceMatch() {
        let match = raceDetector.matchFor(activityID: activity.id)
        let recomputed = InsightEngine.compute(
            activity: activity,
            history: manager.activities,
            level: level,
            workoutType: detail?.workoutType ?? .general,
            splits: detail?.splits ?? [],
            intervalSegments: detail?.intervalSegments ?? [],
            condition: condition,
            raceMatch: match
        )
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
            recomputeInsightWithRaceMatch()
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
        // Return cached result immediately if available
        if let cached = panelSeriesCache[panel] {
            panelSeriesData = cached
            return
        }
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
                        RouteMapView(coordinates: coords)
                    } else {
                        panelPlaceholder(icon: "map.fill", message: "경로 없음")
                    }
                } else {
                    ZStack {
                        Theme.cardBackground
                        panelInnerContent
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(height: 220)
                    .padding(.horizontal, 16)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: activePanel)
        }
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
                panelPlaceholder(icon: "chart.bar.fill", message: "스플릿 없음")
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
                panelPlaceholder(icon: "mountain.2.fill", message: "고도 데이터 없음")
            }
        case .intervals:
            if let segs = detail?.intervalSegments, !segs.isEmpty {
                IntervalPanelChart(segments: segs)
            } else {
                panelPlaceholder(icon: "repeat", message: "인터벌 없음")
            }
        case .cadence:
            seriesPanel(icon: "figure.run", label: "케이던스", unit: "spm",
                        color: Theme.cadence, format: "%.0f", useRangeBar: false,
                        validMin: 130,
                        available: detail?.avgCadence != nil)
        case .power:
            seriesPanel(icon: "bolt.fill", label: "파워", unit: "W",
                        color: Theme.power, format: "%.0f", useRangeBar: true,
                        available: detail?.avgPower != nil)
        case .groundContact:
            seriesPanel(icon: "stopwatch", label: "지면 접촉", unit: "ms",
                        color: Theme.runningForm, format: "%.0f", useRangeBar: true,
                        available: detail?.avgGroundContactTime != nil)
        case .strideLength:
            seriesPanel(icon: "arrow.left.and.right", label: "보폭", unit: "m",
                        color: Theme.runningForm, format: "%.2f", useRangeBar: true,
                        available: detail?.avgStrideLength != nil)
        case .verticalOscillation:
            seriesPanel(icon: "arrow.up.and.down", label: "수직 진폭", unit: "cm",
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
            panelPlaceholder(icon: icon, message: "\(label) 없음")
        } else if isLoadingPanelSeries {
            ProgressView().tint(color)
        } else if panelSeriesData.isEmpty {
            panelPlaceholder(icon: "chart.xyaxis.line", message: "데이터 없음")
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
                            Text(panel.rawValue)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.type.label)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(activity.date, format: .dateTime.year().month().day().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                        Button("이 대회 아니에요", action: revoke)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── Top row: insight text (left) + MiniMe (right) ──
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("오늘의 인사이트")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.violet)
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(Theme.violet)
                    }
                    Text(insight?.title ?? "오늘의 러닝")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                    Text(insight?.detail ?? "인사이트 분석 준비 중")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .contentTransition(.opacity)
                    if let race = confirmedRace {
                        Label("대회 러닝 · \(race.raceName)", systemImage: "flag.checkered")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.violet.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.violet.opacity(0.3), lineWidth: 1))
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

            // ── Condition chips ──────────────────────────────
            if let cond = condition, cond.weather != nil || cond.sleepScore != nil {
                HStack(spacing: 6) {
                    if let w = cond.weather {
                        let wColor: Color = {
                            if w.isRainy { return Theme.pace }
                            if w.isHot   { return Theme.calories }
                            if w.isCold  { return .blue }
                            return .secondary
                        }()
                        ConditionChip(icon: w.systemIcon, label: w.formattedTemp, color: wColor)
                    }
                    if let slp = cond.sleepScore {
                        ConditionChip(
                            icon: "bed.double.fill",
                            label: "수면 \(slp.chipLabel)",
                            color: slp.isInsufficient ? Theme.time : .secondary
                        )
                    }
                }
            }
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
            .font(.caption.weight(.semibold))
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
                         ? "이 사진으로 미니미 만들기"
                         : "이 사진으로 미니미 업데이트")
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
            Image(systemName: icon).font(.system(size: 9))
            Text(label).font(.system(size: 10, weight: .medium))
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

    private var cameraPosition: MapCameraPosition {
        guard let minLat = coordinates.map(\.latitude).min(),
              let maxLat = coordinates.map(\.latitude).max(),
              let minLon = coordinates.map(\.longitude).min(),
              let maxLon = coordinates.map(\.longitude).max() else {
            return .automatic
        }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.004, (maxLat - minLat) * 1.5),
                longitudeDelta: max(0.004, (maxLon - minLon) * 1.5)
            )
        )
        return .region(region)
    }

    var body: some View {
        Map(initialPosition: cameraPosition) {
            MapPolyline(coordinates: coordinates)
                .stroke(Theme.violet, lineWidth: 4)
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
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
    }

    private var items: [Item] {
        switch activity.type {
        case .cycling:  return cyclingItems
        case .swimming: return swimmingItems
        default:        return generalItems
        }
    }

    private var generalItems: [Item] {
        var list: [Item] = [
            Item(icon: "ruler", label: "거리", value: activity.formattedDistance, color: .white),
            Item(icon: "clock", label: "시간", value: activity.formattedDuration, color: Theme.time),
        ]
        if let pace = activity.formattedPace {
            list.append(Item(icon: "timer", label: "페이스", value: pace, color: Theme.pace))
        }
        if let hr = activity.avgHeartRate {
            list.append(Item(icon: "heart.fill", label: "평균 심박", value: "\(hr) bpm", color: Theme.heartRate))
        }
        if activity.type == .running {
            if let cadence = detail?.avgCadence {
                list.append(Item(icon: "figure.run", label: "케이던스", value: "\(cadence) spm",
                                 color: .white, trendMetric: .cadence))
            }
            if let power = detail?.avgPower {
                list.append(Item(icon: "bolt.fill", label: "파워", value: "\(power) W",
                                 color: Theme.power, trendMetric: .power))
            }
            if let gct = detail?.avgGroundContactTime {
                list.append(Item(icon: "stopwatch", label: "지면 접촉",
                                 value: "\(Int(gct.rounded())) ms", color: Theme.runningForm,
                                 trendMetric: .groundContactTime))
            }
            if let stride = detail?.avgStrideLength {
                list.append(Item(icon: "arrow.left.and.right", label: "보폭",
                                 value: String(format: "%.2f m", stride), color: Theme.runningForm,
                                 trendMetric: .strideLength))
            }
            if let vo = detail?.avgVerticalOscillation {
                list.append(Item(icon: "arrow.up.and.down", label: "수직 진폭",
                                 value: String(format: "%.1f cm", vo), color: Theme.runningForm,
                                 trendMetric: .verticalOscillation))
            }
            if let vo2 = detail?.vo2Max {
                let rating = CardioFitnessClassifier.rating(vo2: vo2, age: age, isMale: isMale)
                let note = rating.map { "현재 추정 · \($0)" } ?? "현재 추정"
                list.append(Item(icon: "lungs.fill", label: "유산소 피트니스",
                                 value: String(format: "%.1f mL/kg·min", vo2),
                                 color: Theme.elevation, note: note, trendMetric: .vo2Max))
            }
        }
        if let cal = activity.calories {
            list.append(Item(icon: "flame.fill", label: "칼로리",
                             value: String(format: "%.0f kcal", cal), color: Theme.calories))
        }
        if let elev = detail?.elevationGain {
            list.append(Item(icon: "arrow.up.right", label: "고도 획득",
                             value: String(format: "%.0f m", elev), color: Theme.elevation))
        }
        return list
    }

    private var cyclingItems: [Item] {
        var list: [Item] = [
            Item(icon: "ruler", label: "거리", value: activity.formattedDistance, color: .white),
            Item(icon: "clock", label: "시간", value: activity.formattedDuration, color: Theme.time),
        ]
        let speedKmh = detail?.avgSpeed ?? activity.avgSpeedKmh
        if let speed = speedKmh {
            list.append(Item(icon: "speedometer", label: "평균 속도",
                             value: String(format: "%.1f km/h", speed), color: Theme.pace))
        }
        if let hr = activity.avgHeartRate {
            list.append(Item(icon: "heart.fill", label: "평균 심박", value: "\(hr) bpm", color: Theme.heartRate))
        }
        if let power = detail?.avgPower {
            list.append(Item(icon: "bolt.fill", label: "파워", value: "\(power) W", color: Theme.power))
        }
        if let cadence = detail?.avgCadence {
            list.append(Item(icon: "arrow.clockwise", label: "케이던스", value: "\(cadence) rpm", color: .white))
        }
        if let cal = activity.calories {
            list.append(Item(icon: "flame.fill", label: "칼로리",
                             value: String(format: "%.0f kcal", cal), color: Theme.calories))
        }
        if let elev = detail?.elevationGain {
            list.append(Item(icon: "arrow.up.right", label: "고도 획득",
                             value: String(format: "%.0f m", elev), color: Theme.elevation))
        }
        return list
    }

    private var swimmingItems: [Item] {
        var list: [Item] = [
            Item(icon: "ruler", label: "거리", value: activity.formattedDistance, color: .white),
            Item(icon: "clock", label: "시간", value: activity.formattedDuration, color: Theme.time),
        ]
        if let pace = activity.formattedPace100m {
            list.append(Item(icon: "timer", label: "페이스", value: "\(pace)/100m", color: Theme.pace))
        }
        if let hr = activity.avgHeartRate {
            list.append(Item(icon: "heart.fill", label: "평균 심박", value: "\(hr) bpm", color: Theme.heartRate))
        }
        if let laps = detail?.swimLapCount {
            list.append(Item(icon: "repeat", label: "랩", value: "\(laps)회", color: .white))
        }
        if let pool = detail?.poolLength {
            list.append(Item(icon: "arrow.left.and.right", label: "풀 길이",
                             value: "\(Int(pool))m", color: .white))
        }
        if let strokes = detail?.swimmingStrokeCount {
            list.append(Item(icon: "hand.draw", label: "총 스트로크",
                             value: "\(strokes)회", color: .white))
        }
        if let swolf = detail?.swolfScore {
            list.append(Item(icon: "waveform", label: "SWOLF",
                             value: String(format: "%.0f", swolf), color: Theme.pace))
        }
        if let cal = activity.calories {
            list.append(Item(icon: "flame.fill", label: "칼로리",
                             value: String(format: "%.0f kcal", cal), color: Theme.calories))
        }
        return list
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items) { item in
                MetricCell(icon: item.icon, label: item.label, value: item.value,
                           color: item.color, note: item.note)
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

    private var hasLabels: Bool { segments.contains { $0.stepLabel != nil } }
    private var hasHR: Bool { segments.contains { $0.avgHeartRate != nil } }
    private var hasDist: Bool { segments.contains { $0.distanceM != nil } }

    private var medianPace: Double? {
        guard !hasLabels else { return nil }
        let paces = segments.compactMap(\.paceSecPerKm).sorted()
        guard !paces.isEmpty else { return nil }
        return paces[paces.count / 2]
    }

    private func isWork(_ seg: IntervalSegment) -> Bool {
        if let label = seg.stepLabel { return label == "운동" }
        if let pace = seg.paceSecPerKm, let median = medianPace { return pace < median }
        return seg.id % 2 == 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailSectionHeader(title: "인터벌 구간", subtitle: "\(segments.count)개 구간")

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    if hasLabels {
                        Text("구간").frame(width: 56, alignment: .leading)
                    } else {
                        Text("#").frame(width: 20, alignment: .leading)
                    }
                    if hasDist { Text("거리").frame(width: 60, alignment: .trailing) }
                    Spacer()
                    Text("페이스").frame(width: 70, alignment: .trailing)
                    Text("시간").frame(width: 50, alignment: .trailing)
                    if hasHR { Text("심박").frame(width: 44, alignment: .trailing) }
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
                                Text(seg.stepLabel ?? "#\(seg.id)")
                                    .font(.system(size: 12, weight: work ? .bold : .regular))
                                    .foregroundStyle(work ? Theme.violet : Color.white.opacity(0.55))
                                    .frame(width: 56, alignment: .leading)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            } else {
                                Text("\(seg.id)")
                                    .font(.system(.subheadline, design: .rounded)
                                        .weight(work ? .bold : .regular))
                                    .foregroundStyle(work ? Theme.violet : Color.white.opacity(0.35))
                                    .frame(width: 20, alignment: .leading)
                            }
                            if hasDist {
                                Text(seg.formattedDistance ?? "—")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(work ? .white : Color.white.opacity(0.45))
                                    .frame(width: 60, alignment: .trailing)
                            }
                            Spacer()
                            Text(seg.formattedPace ?? "—")
                                .font(.system(.subheadline, design: .rounded)
                                    .weight(work ? .semibold : .regular))
                                .foregroundStyle(
                                    seg.formattedPace != nil
                                        ? (work ? Theme.violet : Color.white.opacity(0.40))
                                        : Color.secondary
                                )
                                .frame(width: 70, alignment: .trailing)
                            Text(seg.formattedDuration)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(work ? .secondary : Color.white.opacity(0.25))
                                .frame(width: 50, alignment: .trailing)
                            if hasHR {
                                Text(seg.avgHeartRate.map { "\($0)" } ?? "—")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(
                                        seg.avgHeartRate != nil
                                            ? (work ? Theme.heartRate : Theme.heartRate.opacity(0.45))
                                            : Color.secondary
                                    )
                                    .frame(width: 44, alignment: .trailing)
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
        .padding(.horizontal, 16)
    }
}

// MARK: - Splits Section

private struct SplitsSection: View {
    let splits: [SplitData]
    var zones: [HRZoneData] = []
    var activity: Activity? = nil
    var allActivities: [Activity] = []

    @Environment(CustomMiniMeStore.self) private var miniMeStore
    @State private var showSplitsShare = false

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
                DetailSectionHeader(title: "구간 기록", subtitle: "\(splits.count)개 구간")
                Spacer()
                if activity != nil {
                    Button { showSplitsShare = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption.weight(.semibold))
                            Text("공유")
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
                SplitsShareCardScreen(activity: act, splits: splits, zones: zones, miniMeImage: miniMeStore.image)
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
                        Text("최고")
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
        switch highlightKind {
        case .negativeSplit(let diff):
            return Text("후반이 전반보다 ").foregroundStyle(Color.white)
                 + Text("\(diff)초 더 빠르게").foregroundStyle(g)
                 + Text(" — 끝까지 밀어붙였네요.").foregroundStyle(Color.white)
        case .consistency(let spread):
            return Text("페이스 편차 단 ").foregroundStyle(Color.white)
                 + Text("\(spread)초").foregroundStyle(g)
                 + Text(", 흔들림 없었어요.").foregroundStyle(Color.white)
        case .recentBest(let n):
            return Text("최근 \(n)회 중 ").foregroundStyle(Color.white)
                 + Text("가장 빠른 평균 페이스").foregroundStyle(g)
                 + Text("예요.").foregroundStyle(Color.white)
        case .fallback:
            return Text("완주했어요. 오늘도 수고하셨어요.")
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
                SplitChip(label: "평균 페이스", value: formatPace(avgPaceSeconds), color: Theme.violet)
                SplitChip(label: "페이스 편차", value: "±\(Int(paceSpread.rounded()))초", color: Theme.violet)
                if let fastest = fastestSplit {
                    let km = fastest.distanceM >= 990 ? "\(fastest.id)km" : "마지막"
                    SplitChip(label: "최고 구간", value: "\(km) · \(fastest.formattedPace)", color: Self.gold)
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
            DetailSectionHeader(title: "심박 영역", subtitle: "존별 운동 시간")

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
                            Text("영역 \(zone.id)")
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
                    Text("각각의 심박수 영역에 머무르는 예상 시간입니다.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("Karvonen(심박 예비율) 공식 기반 · 최근 30일 최소 안정시 심박(RHR) + 나이별 최대심박(MHR) 추정 적용. 개인 체력 및 측정 조건에 따라 실제 영역과 다를 수 있습니다.")
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
                .font(.system(.title3, weight: .black))
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
                Label("스토리", systemImage: "quote.bubble")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showEditor = true
                } label: {
                    Label(story == nil ? "추가" : "편집",
                          systemImage: story == nil ? "plus" : "pencil")
                        .font(.caption.weight(.medium))
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
                    Label("없음", systemImage: "checkmark")
                } else {
                    Text("없음")
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
                Text(selectedShoe?.displayName ?? "신발 선택")
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
            .navigationTitle("스토리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") { save(); dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.violet)
                }
            }
            .task { loadExisting() }
        }
    }


    private var moodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("느낌")
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
            Text("한줄 메모")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("오늘의 러닝은...", text: $memo, axis: .vertical)
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
                Text("사진")
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
                        photoImages.isEmpty ? "사진 추가" : "더 추가",
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
            Label("이 기록 대회였나요?", systemImage: "flag.checkered")
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
                confirmButton(race: suggestion.primary, label: "예, 맞아요")
                denyButton(label: "아니요")
            }
        } else {
            // Multiple candidates — vertical pick list (up to 4 shown)
            Text("후보 대회를 선택하거나 직접 입력하세요")
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
                    Text("직접 입력")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.violet)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Theme.violet.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                denyButton(label: "아니요")
            }
        }
    }

    @ViewBuilder
    private func manualPromptContent() -> some View {
        HStack {
            Label("이 기록 대회였나요?", systemImage: "flag.checkered")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Spacer()
            Button { showManualSheet = true } label: {
                Text("대회 입력")
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
                        Text("대회 이름")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("예: 춘천 마라톤", text: $raceName)
                            .padding(14)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "ruler")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("기록 거리: \(formattedDistance)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("대회 기록 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") {
                        onCancel()
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
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
                        Text(String(format: "%.0f분", m))
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
        let bucketSize = totalDuration / 40
        return (0..<40).compactMap { i in
            let lo = Double(i) * bucketSize
            let hi = lo + bucketSize
            let isLast = i == 39
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
                    width: .fixed(5)
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
        .chartYScale(domain: lo...(buckets.map(\.max).max().map { $0 + 8 } ?? 200))
        .chartXScale(domain: 0...totalDurationMinutes)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 3 : 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let m = value.as(Double.self) {
                        Text(String(format: "%.0f분", m))
                            .font(compact ? .system(size: 6.5) : .caption2)
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
                            .font(compact ? .system(size: 6.5) : .caption2)
                            .foregroundStyle(Color.white.opacity(compact ? 0.80 : 0.6))
                    }
                }
            }
        }
        .padding(compact ? 4 : 12)
    }
}

private struct MetricBarPanelChart: View {
    let samples: [(offset: TimeInterval, value: Double)]
    let color: Color
    let unit: String
    let format: String
    var useRangeBar: Bool = false  // true: floating min~max bars (Apple style), false: avg-from-baseline
    var validMin: Double = 0

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
        let count = 40
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
                        width: .fixed(5)
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
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        if let m = value.as(Double.self) {
                            Text(String(format: "%.0f분", m)).font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: format, v)).font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
            .padding(12)

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

private struct ElevationPanelChart: View {
    let profile: [(distanceKm: Double, altitude: Double)]

    private struct Bucket: Identifiable {
        let id: Int
        let midKm: Double
        let avg: Double
    }

    private var buckets: [Bucket] {
        guard !profile.isEmpty else { return [] }
        let maxKm = profile.map(\.distanceKm).max() ?? 1
        let bucketSize = maxKm / 40
        return (0..<40).compactMap { i in
            let lo = Double(i) * bucketSize
            let hi = lo + bucketSize
            let isLast = i == 39
            let vals = profile
                .filter { $0.distanceKm >= lo && ($0.distanceKm < hi || (isLast && $0.distanceKm <= hi)) }
                .map(\.altitude)
            guard !vals.isEmpty else { return nil }
            return Bucket(id: i, midKm: (lo + hi) / 2,
                          avg: vals.reduce(0, +) / Double(vals.count))
        }
    }

    private var domainLo: Double {
        let alts = buckets.map(\.avg)
        guard let lo = alts.min(), let hi = alts.max() else { return 0 }
        let range = max(hi - lo, 5)
        return lo - range * 0.6
    }

    private var yDomain: ClosedRange<Double> {
        let alts = buckets.map(\.avg)
        guard let lo = alts.min(), let hi = alts.max() else { return 0...100 }
        let range = max(hi - lo, 5)
        return (lo - range * 0.6)...(hi + range * 0.2)
    }

    var body: some View {
        let baseline = domainLo
        Chart {
            ForEach(buckets) { b in
                BarMark(
                    x: .value("km", b.midKm),
                    yStart: .value("바닥", baseline),
                    yEnd: .value("고도", b.avg),
                    width: .fixed(5)
                )
                .foregroundStyle(Theme.elevation.opacity(0.85))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let km = value.as(Double.self) {
                        Text(String(format: "%.1fkm", km)).font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.0fm", v)).font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(12)
    }
}

private struct IntervalPanelChart: View {
    let segments: [IntervalSegment]

    private var paced: [(id: Int, pace: Double, isWork: Bool)] {
        let allPaces = segments.compactMap(\.paceSecPerKm).sorted()
        let median = allPaces.isEmpty ? nil : allPaces[allPaces.count / 2]
        return segments.compactMap { seg in
            guard let pace = seg.paceSecPerKm else { return nil }
            let work: Bool
            if let label = seg.stepLabel { work = label == "운동" }
            else if let m = median { work = pace < m }
            else { work = seg.id % 2 == 1 }
            return (id: seg.id, pace: pace, isWork: work)
        }
    }

    var body: some View {
        Chart {
            ForEach(paced, id: \.id) { item in
                BarMark(x: .value("구간", item.id), y: .value("페이스", item.pace))
                    .foregroundStyle(item.isWork ? Theme.violet.gradient : Color.white.opacity(0.20).gradient)
                    .cornerRadius(3)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let sec = value.as(Double.self) {
                        Text(String(format: "%d'", Int(sec) / 60)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let n = value.as(Int.self) { Text("\(n)").font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
        .padding(12)
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
            Text("이번 달 · \(data.count)개 기록")
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
