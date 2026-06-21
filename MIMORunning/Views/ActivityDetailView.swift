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
                        SplitsSection(splits: splits)
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
                print("[Insight] type=\(det.workoutType.koreanLabel)  theme=\(refined.theme)  title=\(refined.title)")
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
        panelSeriesData = []
        isLoadingPanelSeries = true
        switch panel {
        case .cadence:
            panelSeriesData = await manager.fetchCadenceTimeSeries(for: activity.id)
        case .power:
            panelSeriesData = await manager.fetchWorkoutTimeSeries(for: activity.id,
                                                                   identifier: .runningPower, unit: .watt())
        case .groundContact:
            panelSeriesData = await manager.fetchWorkoutTimeSeries(for: activity.id,
                                                                   identifier: .runningGroundContactTime,
                                                                   unit: .secondUnit(with: .milli))
        case .strideLength:
            panelSeriesData = await manager.fetchWorkoutTimeSeries(for: activity.id,
                                                                   identifier: .runningStrideLength, unit: .meter())
        case .verticalOscillation:
            panelSeriesData = await manager.fetchWorkoutTimeSeries(for: activity.id,
                                                                   identifier: .runningVerticalOscillation,
                                                                   unit: .meterUnit(with: .centi))
        default:
            break
        }
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
                SplitsPanelChart(splits: splits)
            } else {
                panelPlaceholder(icon: "chart.bar.fill", message: "스플릿 없음")
            }
        case .heartRate:
            if hrSamples.isEmpty {
                ProgressView().tint(Theme.violet)
            } else {
                HRSeriesPanelChart(samples: hrSamples)
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
                        color: .white, format: "%.0f", available: detail?.avgCadence != nil)
        case .power:
            seriesPanel(icon: "bolt.fill", label: "파워", unit: "W",
                        color: Theme.power, format: "%.0f", available: detail?.avgPower != nil)
        case .groundContact:
            seriesPanel(icon: "stopwatch", label: "지면 접촉", unit: "ms",
                        color: Theme.runningForm, format: "%.0f", available: detail?.avgGroundContactTime != nil)
        case .strideLength:
            seriesPanel(icon: "arrow.left.and.right", label: "보폭", unit: "m",
                        color: Theme.runningForm, format: "%.2f", available: detail?.avgStrideLength != nil)
        case .verticalOscillation:
            seriesPanel(icon: "arrow.up.and.down", label: "수직 진폭", unit: "cm",
                        color: Theme.runningForm, format: "%.1f", available: detail?.avgVerticalOscillation != nil)
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
                             color: Color, format: String, available: Bool) -> some View {
        if !available {
            panelPlaceholder(icon: icon, message: "\(label) 없음")
        } else if isLoadingPanelSeries {
            ProgressView().tint(color)
        } else if panelSeriesData.isEmpty {
            panelPlaceholder(icon: "chart.xyaxis.line", message: "데이터 없음")
        } else {
            MetricSeriesPanelChart(samples: panelSeriesData, label: label,
                                   unit: unit, color: color, format: format)
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
                    .foregroundStyle(Theme.violet)
                    .frame(width: 44, height: 44)
                    .background(Theme.violet.opacity(0.15))
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
            }
            .font(.caption.weight(.semibold))
            #if canImport(ImagePlayground)
            if #available(iOS 18.2, *), let photo = storyPhoto {
                MiniMeUpdateButton(storyPhoto: photo)
            }
            #endif
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
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
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
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
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

    private var minPace: Double { splits.map(\.paceSecPerKm).min() ?? 1 }
    private var maxPace: Double { splits.map(\.paceSecPerKm).max() ?? minPace }
    private var fastestIdx: Int? {
        splits.indices.min(by: { splits[$0].paceSecPerKm < splits[$1].paceSecPerKm })
    }

    private func barFraction(for split: SplitData) -> CGFloat {
        guard maxPace > minPace else { return 1.0 }
        return CGFloat(1.0 - (split.paceSecPerKm - minPace) / (maxPace - minPace) * 0.6)
    }

    private var hasHR: Bool { splits.contains(where: { $0.avgHeartRate != nil }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailSectionHeader(title: "구간 기록", subtitle: "\(splits.count)개 구간")

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("km")
                        .frame(width: 24, alignment: .leading)
                    Spacer()
                    Text("페이스")
                        .frame(width: 70, alignment: .trailing)
                    if hasHR {
                        Text("심박")
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                ForEach(Array(splits.enumerated()), id: \.element.id) { idx, split in
                    let isFastest = idx == fastestIdx
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 0.5)
                        HStack(spacing: 10) {
                            Text(split.distanceM < 990
                                 ? String(format: "%.0fm", split.distanceM)
                                 : "\(split.id)")
                                .font(.system(.subheadline, design: .rounded)
                                    .weight(isFastest ? .bold : .regular))
                                .foregroundStyle(isFastest ? Theme.violet : .white)
                                .frame(width: 24, alignment: .leading)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.06))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(isFastest ? Theme.pace : Theme.violet.opacity(0.55))
                                        .frame(width: geo.size.width * barFraction(for: split))
                                }
                            }
                            .frame(height: 8)

                            Text(split.formattedPace)
                                .font(.system(.subheadline, design: .rounded)
                                    .weight(isFastest ? .semibold : .regular))
                                .foregroundStyle(isFastest ? Theme.pace : .white)
                                .frame(width: 70, alignment: .trailing)

                            if hasHR {
                                Text(split.avgHeartRate.map { "\($0)" } ?? "—")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(split.avgHeartRate != nil
                                                     ? Theme.heartRate : Color.secondary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isFastest ? Theme.violet.opacity(0.06) : Color.clear)
                    }
                }
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - HR Zones Section

private struct HRZonesSection: View {
    let zones: [HRZoneData]

    private static let zoneColors: [Color] = [
        Color.red.opacity(0.35),
        Color.red.opacity(0.52),
        Color.red.opacity(0.68),
        Color.red.opacity(0.84),
        Color.red,
    ]

    private func color(for zone: HRZoneData) -> Color {
        Self.zoneColors[min(zone.id - 1, Self.zoneColors.count - 1)]
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m)분 \(s)초" : "\(s)초"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailSectionHeader(title: "심박존", subtitle: "존별 운동 시간")

            VStack(spacing: 10) {
                ForEach(zones) { zone in
                    HStack(spacing: 10) {
                        Text(zone.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(color(for: zone))
                            .frame(width: 60, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.06))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color(for: zone))
                                    .frame(width: geo.size.width * zone.fraction)
                            }
                        }
                        .frame(height: 18)

                        Text(formattedTime(zone.seconds))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }

                if let first = zones.first, let last = zones.last {
                    HStack {
                        Spacer()
                        Text("최대심박 기준 \(first.minBPM)–\(last.maxBPM) bpm")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let note {
                Text(note)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
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
        case .great: Theme.violet
        case .okay:  Theme.time
        case .tough: Theme.heartRate
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
            }
            if !story.memo.isEmpty {
                Text(story.memo)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(4)
            }
            if photos.count == 1 {
                Image(uiImage: photos[0])
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .clipped()
            } else if photos.count > 1 {
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
                        VStack(spacing: 6) {
                            Image(systemName: m.sfSymbol)
                                .font(.title2)
                                .foregroundStyle(mood == m ? moodColor(m) : Color.white.opacity(0.3))
                            Text(m.label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(mood == m ? moodColor(m) : Color.white.opacity(0.3))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
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
        case .great: Theme.violet
        case .okay:  Theme.time
        case .tough: Theme.heartRate
        }
    }

    private func loadExisting() {
        guard let s = existingStory else { return }
        memo = s.memo
        mood = s.mood
        photoImages = s.allPhotoImages
    }

    private func save() {
        // Delete old photo files
        if let s = existingStory {
            for fn in s.photoFilenames { WorkoutStory.deletePhoto(named: fn) }
        }
        // Save current images to Documents
        let filenames = photoImages.enumerated().compactMap { idx, img in
            WorkoutStory.savePhoto(img, workoutID: workoutID, index: idx)
        }
        if let s = existingStory {
            s.memo = memo
            s.mood = mood
            s.photoFilenames = filenames
            s.photoData = nil
            s.updatedAt = Date()
        } else {
            modelContext.insert(WorkoutStory(workoutID: workoutID, memo: memo, mood: mood,
                                             photoFilenames: filenames))
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

private struct SplitsPanelChart: View {
    let splits: [SplitData]

    var body: some View {
        Chart {
            ForEach(splits) { split in
                BarMark(x: .value("km", split.id), y: .value("pace", split.paceSecPerKm))
                    .foregroundStyle(
                        split.id == splits.min(by: { $0.paceSecPerKm < $1.paceSecPerKm })?.id
                        ? Theme.pace.gradient : Theme.violet.opacity(0.65).gradient
                    )
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

private struct HRSeriesPanelChart: View {
    let samples: [(offset: TimeInterval, bpm: Int)]

    var body: some View {
        Chart {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
                LineMark(x: .value("분", s.offset / 60), y: .value("bpm", s.bpm))
                    .foregroundStyle(Theme.heartRate.gradient)
                    .interpolationMethod(.catmullRom)
                AreaMark(x: .value("분", s.offset / 60), y: .value("bpm", s.bpm))
                    .foregroundStyle(Theme.heartRate.opacity(0.12).gradient)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let m = value.as(Double.self) {
                        Text(String(format: "%.0f분", m)).font(.caption2).foregroundStyle(.secondary)
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
        .padding(12)
    }
}

private struct MetricSeriesPanelChart: View {
    let samples: [(offset: TimeInterval, value: Double)]
    let label: String
    let unit: String
    let color: Color
    let format: String

    private var avgValue: Double? {
        guard !samples.isEmpty else { return nil }
        return samples.map(\.value).reduce(0, +) / Double(samples.count)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Chart {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
                    LineMark(x: .value("분", s.offset / 60), y: .value(label, s.value))
                        .foregroundStyle(color.gradient)
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("분", s.offset / 60), y: .value(label, s.value))
                        .foregroundStyle(color.opacity(0.12).gradient)
                        .interpolationMethod(.catmullRom)
                }
                if let avg = avgValue {
                    RuleMark(y: .value("평균", avg))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(color.opacity(0.55))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        if let m = value.as(Double.self) {
                            Text(String(format: "%.0f분", m)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: format, v)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(12)

            if let avg = avgValue {
                HStack(spacing: 3) {
                    Text(String(format: format, avg))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    Text("avg \(unit)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
        }
    }
}

private struct ElevationPanelChart: View {
    let profile: [(distanceKm: Double, altitude: Double)]

    var body: some View {
        Chart {
            ForEach(Array(profile.enumerated()), id: \.offset) { _, pt in
                LineMark(x: .value("km", pt.distanceKm), y: .value("m", pt.altitude))
                    .foregroundStyle(Theme.elevation)
                    .interpolationMethod(.catmullRom)
                AreaMark(x: .value("km", pt.distanceKm), y: .value("m", pt.altitude))
                    .foregroundStyle(Theme.elevation.opacity(0.18).gradient)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let km = value.as(Double.self) {
                        Text(String(format: "%.1f", km)).font(.caption2).foregroundStyle(.secondary)
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
