import SwiftUI
import Charts
import CoreLocation
import HealthKit
import PhotosUI
import Photos
import SwiftData

// struct AthleticCard → AthleticCard.swift


// CardWorkoutSeriesChart · CardIntervalChart · workSummaryText → CardCharts.swift


// PhotoShareCardView → PhotoCard.swift

// MARK: - Share Template

/// 카드 출력 형태. 이름 = 배경에 무엇을 쓰는지(§5.7 사진 모드 / 기록 전용 모드).
enum ShareTemplate: String, CaseIterable {
    case record      = "기록"     // 사진 없는 4:5 정지 카드
    case photo       = "사진"     // 사진 배경 4:5 정지 카드
    case video       = "영상"
    case slide       = "슬라이드"
    case routeVideo  = "경로 영상"

    var label: String {
        let L = AppLanguage.shared
        return switch self {
        case .record:     L.s("기록",      "Record")
        case .photo:      L.s("사진",      "Photo")
        case .video:      L.s("영상",      "Video")
        case .slide:      L.s("슬라이드",  "Slide")
        case .routeVideo: L.s("경로 영상", "Route Video")
        }
    }
}

// MARK: - Share Card (카드별 지원 템플릿 단일 소스)

enum HorizGridMode { case text, route }

/// 카드 만들기 캐러셀의 카드. 선언 순서 = 화면 순서(allCases).
enum ShareCard: Int, CaseIterable, Hashable {
    case stamp
    case placeable
    case oneLiner
    case athletic

    /// 상단 사진 스트립 선택을 함께 따르는 카드(스탬프는 자체 선택).
    static let photoLinked: [ShareCard] = [.placeable, .oneLiner, .athletic]

    /// 캐러셀 이름표
    var name: String {
        switch self {
        case .stamp:     return "Stamp"
        case .placeable: return "Placeable"
        case .oneLiner:  return "One Liner"
        case .athletic:  return "Athletic"
        }
    }

    /// 이 카드에서 활성화(탭 가능·흰색)로 표시할 템플릿 집합.
    /// templatePicker 활성화, onCardIndexChanged 자동전환, renderCard 분기의 단일 소스.
    var supportedTemplates: Set<ShareTemplate> {
        switch self {
        case .placeable: return [.photo, .video, .slide]
        case .oneLiner:  return [.photo, .video, .slide]
        case .athletic:  return [.record, .photo, .video, .slide, .routeVideo]
        case .stamp:     return [.photo, .video, .slide, .routeVideo]
        }
    }

    /// 카드 진입 시 현재 템플릿이 미지원이면 이 값으로 자동 전환.
    var defaultTemplate: ShareTemplate {
        switch self {
        case .placeable, .oneLiner, .stamp: return .photo
        default:                            return .record
        }
    }
}

// StoryShareCardView → StoryCard.swift

// VideoOverlayCard → VideoOverlayCard.swift

// MARK: - ShareCardScreen

struct ShareCardScreen: View {
    let activity: Activity
    let detail: ActivityDetail?
    let insight: InsightResult?
    var manager: HealthKitManager? = nil
    var condition: ActivityCondition? = nil
    /// 총평 5줄 — RunSummaryBuilder로 조립돼 들어온다. "총평" 칩이 켜졌을 때만 카드에 표시.
    var summaryLines: [RunSummaryLine] = []

    @Environment(\.modelContext) var modelContext
    @Environment(RaceDetector.self) private var raceDetector
    @Environment(CustomMiniMeStore.self) private var miniMeStore
    @Query private var allStories: [WorkoutStory]
    @Query private var allShoes: [Shoe]
    @Query var allOneLinerEntries: [OneLinerEntry]
    private var story: WorkoutStory? { allStories.first { $0.workoutID == activity.id.uuidString } }
    private var activeShoe: Shoe? {
        guard let sid = story?.shoeID else { return nil }
        return allShoes.first { $0.id.uuidString == sid }
    }
    var storyPhotos: [UIImage] { allPickedPhotos.isEmpty ? (story?.allPhotoImages ?? []) : allPickedPhotos }
    private var storyPhoto: UIImage? { storyPhotos.first }
    var oneLinerEntries: [OneLinerEntry] {
        OneLinerEntry.visible(from: allOneLinerEntries, workoutID: activity.id.uuidString)
    }

    private var confirmedRace: PersistedRaceMatch? {
        guard let m = raceDetector.matchFor(activityID: activity.id), m.isConfirmed else { return nil }
        return m
    }
    // Look up the BundledRace matching the confirmed match to get startTimeString
    private var confirmedBundledRace: BundledRace? {
        guard let match = confirmedRace else { return nil }
        return raceDetector.races.first {
            $0.name == match.raceName &&
            Calendar.current.isDate($0.date ?? .distantPast, inSameDayAs: match.raceDate)
        }
    }
    private var activeRaceName: String? { showRaceOnCard ? confirmedRace?.raceName : nil }

    // 잠금 칩 행(placeholder)에서만 참조
    private var canShowMiniMe: Bool { true }

    @State var storyShareImages: [UIImage] = []
    @AppStorage("mapHRZoneMode") private var mapHRZoneMode: Bool = true
    /// 사진·영상 카드 로고 칩 — 모든 카드 템플릿 공통. 시트를 열 때마다 ON(저장 안 함), 끄는 건 이 카드 동안만.
    /// 상태는 MediaLogoSetting.shared 하나(워드마크가 직접 관찰). 꺼도 로고 자리는 항상 잡혀 있어 다른 요소는 안 움직인다.
    private var showLogoOnCard: Bool { MediaLogoSetting.shared.isOn }

    @State private var previewImage: UIImage?
    @State private var isRendering = true
    @State var showShareSheet = false

    @State private var selectedPhoto: UIImage?
    @State private var selectedPhotoIndex: Int = 0
    @State private var allPickedPhotos: [UIImage] = []   // in-memory source of truth for sharing
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showStoryPhotoPicker = false
    @State private var photoOffset: CGSize = .zero
    @State private var photoOffsets: [Int: CGSize] = [:]
    @State var template: ShareTemplate = .photo
    @State private var enabledMetrics: Set<ShareMetric>
    @State private var showRaceOnCard = true
    /// "총평" 칩 — 기본 꺼짐. 켜지면 지도/차트 자리에 총평 5줄이 대신 들어간다(§5.8: 카드 4종·영상 오버레이 공용).
    @State private var showSummaryOnCard = false
    @State private var carouselPage = 0
    // Stamp card ViewModel
    @State var stampVM = StampViewModel()
    /// 로고 칩 "열 때마다 ON" — 이 시트 인스턴스에서 한 번만 리셋(사진 선택 등 되돌아올 때 재리셋 방지)
    @State private var didResetMediaLogo = false
    // Placeable card ViewModel
    @State var placeableVM = PlaceableViewModel()
    // OneLiner card ViewModel
    @State var oneLinerVM = OneLinerViewModel()
    // Athletic card ViewModel
    @State var athleticVM = AthleticViewModel()
    // Video
    @State var videoPickerItem: PhotosPickerItem?
    @State var sourceVideoURL: URL?
    @State var videoPreviewImage: UIImage?
    @State private var isExportingVideo = false
    @State private var exportedVideoFile: SharableVideoFile?
    @State private var videoExportError: String?
    @State private var showVideoExportError = false
    @State var isBatchExporting = false
    @State private var showExportedVideoWarning = false
    // Route video
    @State private var routeSnapshot: UIImage?
    @State private var routeSnapshotPoints: [CGPoint] = []
    @State private var routeVideoFile: SharableVideoFile?
    @State private var isExportingRouteVideo = false
    @State private var showRouteVideoShareSheet = false
    @State private var routeVideoProgress: Double = 0
    @State private var routePreviewProgress: CGFloat = 1.0   // 1.0=완성, 0=리셋(재생 시작)
    @State private var previewStampVisible: Bool = true
    @State private var previewTextVisible: Bool = true
    @State private var isRoutePreviewPlaying: Bool = false
    @State private var routePreviewPlayCount: Int = 0
    @State private var previewTextDelayTask: Task<Void, Never>?
    // Chart panel
    @State private var cardPanel: CardChartPanel = .map
    @State var shareHRSamples: [(offset: TimeInterval, bpm: Int)] = []
    @State private var shareWorkoutSeries: [(offset: TimeInterval, value: Double)] = []
    @State var chartSeriesData: [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:]
    // 현재 캐러셀 카드
    @State private var card: ShareCard = .stamp
    @State var cardPhotoIndex: [ShareCard: Int] = [:]
    @State var athleticCropOffsetX: CGFloat = 0.5
    @State private var athleticCropDragBase: CGFloat? = nil
    @State var athleticSlideCropOffsets: [Int: CGFloat] = [:]
    @State private var athleticSlideCropDragBase: CGFloat? = nil
    @State private var stampStoryCropDragBase: CGFloat? = nil
    @State var stampSlideCropDragBase: CGFloat? = nil
    @State var stampSlideCropOffsets: [Int: CGFloat] = [:]
    @State var stampSlideBrightMap: [Int: Bool] = [:]
    // 스탬프 지명·지도 비동기 캐시 (위치/경로 템플릿용)
    @State private var stampPlaceName: String?      = nil
    @State private var stampPlaceRegion: String?    = nil
    @State private var stampCoordText: String?      = nil
    @State private var stampMapImage: UIImage?      = nil
    @State private var stampRoutePoints: [CGPoint]? = nil

    private var isStamp: Bool      { card == .stamp }
    var isPlaceable: Bool  { card == .placeable }
    var isOneLiner: Bool   { card == .oneLiner }
    /// 현재 Placeable 카드에서 보여주는 사진 인덱스 (photoStrip 탭 기반)
    var placeableCurrentPhotoIdx: Int { cardPhotoIndex[.placeable] ?? 0 }
    /// 현재 사진에 연결된 Placeable 문구
    var placeableCurrentText: String { placeableVM.placeableStoryTexts[placeableCurrentPhotoIdx] ?? "" }
    // .athletic: 기본 템플릿 카드, 별도 판별 불필요

    /// Metric chips injected into MultiClipEditorView for the running day OneLiner.
    var oneLinerAvailableMetrics: [MetricItem] {
        var m: [MetricItem] = []
        let km = activity.distance / 1000
        let distVal = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
        m.append(MetricItem(id: "distance", value: distVal, label: "km",
                            color: Theme.violet, uiColor: UIColor(red: 0x7C/255, green: 0x5C/255,
                                                                   blue: 0xFC/255, alpha: 1)))
        if let pace = activity.formattedPace {
            m.append(MetricItem(id: "pace", value: pace, label: "/km",
                                color: Color.cyan, uiColor: UIColor.systemCyan))
        }
        // T = 소요시간
        let dur = Int(activity.duration)
        let timeVal = dur >= 3600
            ? String(format: "%d:%02d:%02d", dur / 3600, (dur % 3600) / 60, dur % 60)
            : String(format: "%d:%02d", dur / 60, dur % 60)
        m.append(MetricItem(id: "time", value: timeVal, label: "",
                            color: Color.yellow, uiColor: UIColor.systemYellow))
        // B = 평균 심박수
        if let hr = activity.avgHeartRate {
            m.append(MetricItem(id: "heartrate", value: "\(hr)", label: "bpm",
                                color: Theme.heartRate, uiColor: UIColor.systemRed))
        }
        return m
    }

    /// id → VideoMetricChip 조회 (클립별 P/D/T 오버레이용)
    private var oneLinerMetricLookup: [String: VideoMetricChip] {
        Dictionary(uniqueKeysWithValues: oneLinerAvailableMetrics.map {
            ($0.id, VideoMetricChip(value: $0.value, label: $0.label, uiColor: $0.uiColor))
        })
    }

    /// VideoMetricChip array for export — only enabled IDs, in display order.
    private var oneLinerActiveMetricChips: [VideoMetricChip] {
        oneLinerAvailableMetrics
            .filter { oneLinerVM.oneLinerEnabledMetricIDs.contains($0.id) }
            .map { $0.asVideoChip }
    }

    /// 슬라이드 레시피의 per-clip 메트릭 설정을 VideoMetricChip 배열로 변환.
    /// 한 클립이라도 해당 메트릭을 켜면 슬라이드 전체에 표시.
    private func metricChipsFromSlideRecipes(_ recipes: [ClipRecipe]) -> [VideoMetricChip] {
        let hasPace     = recipes.contains { $0.metricPace }
        let hasDistance = recipes.contains { $0.metricDistance }
        let hasTime     = recipes.contains { $0.metricTime }
        let lookup      = oneLinerMetricLookup
        var chips: [VideoMetricChip] = []
        if hasDistance, let c = lookup["distance"] { chips.append(c) }
        if hasPace,     let c = lookup["pace"]     { chips.append(c) }
        if hasTime,     let c = lookup["time"]     { chips.append(c) }
        return chips
    }

    /// Story/Slide 정적 카드용: photoIndex번 사진의 ClipRecipe를 entry에서 직접 읽어 반환.
    /// v3slide\n JSON 포맷 및 레거시 플레인텍스트 포맷 모두 지원.
    func photoRecipe(at photoIndex: Int, prefix: String = "photo:") -> ClipRecipe? {
        guard photoIndex < oneLinerVM.storyPhotoUUIDs.count else { return nil }
        let ref = "\(prefix)\(oneLinerVM.storyPhotoUUIDs[photoIndex])"
        guard let entry = oneLinerEntries.first(where: { $0.mediaRef == ref }),
              !entry.text.isEmpty else { return nil }

        var recipe = ClipRecipe(url: URL(fileURLWithPath: "/dev/null"), fullDuration: 4.0)
        if entry.text.hasPrefix("v3slide\n"),
           let data = entry.text.dropFirst("v3slide\n".count).data(using: .utf8),
           let desc = try? JSONDecoder().decode(SavedClipDescriptor.self, from: data) {
            recipe.lines      = desc.lines.map { line in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("v3slide") || t.hasPrefix("v3recipes")
                    || t.hasPrefix("v4recipes") || t.hasPrefix("v2clips")
                    || (t.count > 30 && t.hasPrefix("{") && t.hasSuffix("}")) { return "" }
                return line
            }
            recipe.fontChoice = OneLinerFont.migrate(desc.fontID)
            recipe.textColor  = desc.colorID.flatMap { OneLinerTextColor(rawValue: $0) } ?? .white
            if let aIdx = desc.anchorIdx, CardPosition.allCases.indices.contains(aIdx) {
                recipe.position = CardPosition.allCases[aIdx]
            }
            recipe.sizeLevel  = desc.sizeID.flatMap { TextSizeLevel(rawValue: $0) } ?? .large
            if let eid = desc.effectID, eid.contains("|") {
                let parts = eid.split(separator: "|", maxSplits: 3).map(String.init)
                recipe.appearanceMode = parts.count > 0 ? (AppearanceMode(rawValue: parts[0]) ?? .typing) : .typing
                recipe.decorEffect    = parts.count > 1 ? (DecorEffect(rawValue: parts[1]) ?? .none) : .none
                if parts.count > 2 {
                    recipe.hasBorder = parts[2].contains("B1")
                }
                recipe.flyDirection = parts.count > 3 ? (FlyInDirection(rawValue: parts[3]) ?? .trailing) : .trailing
            }
            recipe.metricPace      = desc.metricPace
            recipe.metricDistance  = desc.metricDistance
            recipe.metricTime      = desc.metricTime
            recipe.metricHeartRate = desc.metricHeartRate
            if let idx = desc.pdtAnchorIdx, CardPosition.allCases.indices.contains(idx) {
                recipe.pdtPosition = CardPosition.allCases[idx]
            }
            // 차트 오버레이 복원: chartTypeID 우선, 없으면 레거시 fallback
            if let ct = desc.chartTypeID, let type = ChartOverlayType(rawValue: ct) {
                recipe.chartOverlayType = type
            } else if desc.showRoute {
                recipe.chartOverlayType = .route
            } else if desc.showHRChart {
                recipe.chartOverlayType = .hrChart
            }
            if let idx = desc.routeAnchorIdx, CardPosition.allCases.indices.contains(idx) {
                recipe.routePosition = CardPosition.allCases[idx]
            }
            if let ps = desc.pdtSizeID2, let size = TextSizeLevel(rawValue: ps) {
                recipe.pdtSizeLevel = size
            }
            if let de = desc.dataEffectID, let mode = AppearanceMode(rawValue: de) {
                recipe.dataAppearanceMode = mode
            }
        } else {
            recipe.lines      = entry.text.components(separatedBy: "\n")
            recipe.fontChoice = entry.font
            recipe.textColor  = entry.textColor
            recipe.position   = entry.position
        }
        return recipe
    }

    private var slideStaticRecipe: ClipRecipe? {
        photoRecipe(at: cardPhotoIndex[.oneLiner] ?? 0, prefix: "slide:")
    }

    /// 스토리 카드 차트 예약 높이 — captionMode 텍스트·PDT칩이 차트와 겹치지 않도록.
    /// OneLinerCard.genericChartOverlay / HRLineChart 모두 botPad=10 기준으로 통일.
    func storyChartBottomReserved(for recipe: ClipRecipe?, cardHeight: CGFloat? = nil) -> CGFloat {
        guard let r = recipe else { return 0 }
        let cH: CGFloat = cardHeight ?? OneLinerCard.cardHeight  // 375 (story) or 533 (9:16 slide)
        let botPad: CGFloat = 10
        if r.showHRChart && !shareHRSamples.isEmpty { return cH * 0.264 + botPad }
        if r.chartOverlayType == .route, !routeCoords.isEmpty { return cH * 0.264 + botPad }
        if r.chartOverlayType == .intervals {
            let segs = detail?.intervalSegments ?? []
            if !segs.isEmpty {
                let displayCount = segs.count > 10 ? (segs.count + 1) / 2 : segs.count
                let panH: CGFloat = 16 + 8 + CGFloat(displayCount) * 6.5 + 10
                return panH + botPad
            }
        }
        if r.chartOverlayType == .splits {
            let fc = (detail?.splits ?? []).filter { $0.distanceM >= 900 }.count
            if fc >= 2 {
                let displayCount = fc > 21 ? (fc / 2) : fc
                // titleH(16) + colHH(8) + rows*rowH(7) + vPad*2(10) — splitsChartPanel과 동일
                let panH: CGFloat = 16 + 8 + CGFloat(displayCount) * 7 + 10
                return panH + botPad
            }
        }
        let gt = r.chartOverlayType
        if ![ChartOverlayType.none, .route, .hrChart, .splits, .intervals].contains(gt),
           let s = chartSeriesData[gt], s.count >= 2 { return cH * 0.264 + botPad }
        return 0
    }

    // Placeable story text overlay
    // OneLiner card
    @FocusState private var oneLinerFieldFocused: Bool
    @FocusState private var oneLinerFocusedLine: Int?
    @FocusState var placeableStoryFocused: Bool

    private var oneLinerIsPhotoSlide: Bool { template == .slide }
    /// 슬라이드 = storyPhotos, 영상 = oneLinerVM.oneLinerClipRecipes 기반 '사진/클립 있음' 여부
    private var oneLinerHasPhotos: Bool {
        oneLinerIsPhotoSlide ? !storyPhotos.isEmpty : !oneLinerVM.oneLinerClipRecipes.isEmpty
    }
    @State var previewPlayer: OneLinerPreviewPlayer    = OneLinerPreviewPlayer()

    var routeCoords: [CLLocationCoordinate2D] { detail?.routeCoordinates ?? [] }

    private var showHRGradientForRoute: Bool {
        mapHRZoneMode && activity.avgHeartRate != nil && shareHRSamples.count >= 10
    }

    private var shareZoneBounds: [(id: Int, minBPM: Int)] {
        guard !shareHRSamples.isEmpty else { return [] }
        if let mgr = manager {
            let k = mgr.computeHRZonesFromSamples(shareHRSamples)
            if !k.isEmpty { return k.sorted { $0.minBPM < $1.minBPM }.map { (id: $0.id, minBPM: $0.minBPM) } }
        }
        let peak = min(220, Int(Double(shareHRSamples.map(\.bpm).max() ?? 180) / 0.90))
        return [(1,0),(2,Int(Double(peak)*0.60)),(3,Int(Double(peak)*0.70)),
                (4,Int(Double(peak)*0.80)),(5,Int(Double(peak)*0.90))]
    }

    private var distanceKmString: String {
        let km = activity.distance / 1000
        return km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
    }
    private var insightTitle: String { insight?.title ?? AppLanguage.shared.s("오늘의 러닝", "Today's Run") }
    private var storyHasContent: Bool { story?.hasContent == true }
    /// 신발이 등록돼 있으면 항상 표시 (토글 없음)
    var displayShoeName: String? { activeShoe?.displayName }

    init(activity: Activity, detail: ActivityDetail?, insight: InsightResult?, manager: HealthKitManager? = nil,
         condition: ActivityCondition? = nil, summaryLines: [RunSummaryLine] = []) {
        self.activity = activity
        self.detail = detail
        self.insight = insight
        self.manager = manager
        self.condition = condition
        self.summaryLines = summaryLines
        _enabledMetrics = State(initialValue: Self.computeDefaultMetrics(activity: activity, detail: detail))
    }

    // MARK: - Metric computation

    private var allMetricItems: [ShareMetricItem] {
        var items: [ShareMetricItem] = []
        if let pace = activity.formattedPace {
            items.append(ShareMetricItem(id: .pace, value: pace, label: "/km", color: Theme.pace))
        }
        items.append(ShareMetricItem(id: .duration, value: activity.formattedDuration, label: AppLanguage.shared.s("시간", "TIME"), color: Theme.time))
        if let hr = activity.avgHeartRate {
            items.append(ShareMetricItem(id: .heartRate, value: "\(hr)", label: "bpm", color: Theme.heartRate))
        }
        if let cad = detail?.avgCadence {
            items.append(ShareMetricItem(id: .cadence, value: "\(cad)", label: "spm", color: Theme.runningForm))
        }
        if let vo2 = detail?.vo2Max {
            items.append(ShareMetricItem(id: .vo2Max, value: String(format: "%.0f", vo2), label: "VO₂max", color: Theme.violet))
        }
        if let cal = activity.calories {
            items.append(ShareMetricItem(id: .calories, value: String(format: "%.0f", cal), label: "kcal", color: Theme.calories))
        }
        return items
    }

    private var enabledMetricItems: [ShareMetricItem] {
        allMetricItems.filter { enabledMetrics.contains($0.id) }
    }

    /// 카드에 실제로 넘길 총평 줄 — 칩이 꺼져 있으면 항상 빈 배열(기존 렌더와 바이트 동일).
    private var cardSummaryLines: [RunSummaryLine] { showSummaryOnCard ? summaryLines : [] }

    private func workIntervals(from segs: [IntervalSegment]) -> [IntervalSegment] {
        let labeled = segs.filter { $0.stepLabel == "운동" }
        return labeled.isEmpty ? segs : labeled
    }

    private func isChartPanelAvailable(_ panel: CardChartPanel) -> Bool {
        switch panel {
        case .map:                  !routeCoords.isEmpty
        case .splits:               !(detail?.splits.isEmpty ?? true)
        case .heartRate:            activity.avgHeartRate != nil && manager != nil
        case .cadence:              detail?.avgCadence != nil && manager != nil
        case .groundContact:        detail?.avgGroundContactTime != nil && manager != nil
        case .strideLength:         detail?.avgStrideLength != nil && manager != nil
        case .power:                detail?.avgPower != nil && manager != nil
        case .verticalOscillation:  detail?.avgVerticalOscillation != nil && manager != nil
        case .elevation:            !(detail?.altitudeTimeProfile.isEmpty ?? true)
        case .intervals:            !(detail?.intervalSegments.isEmpty ?? true)
        }
    }

    private static func computeDefaultMetrics(activity: Activity, detail: ActivityDetail?) -> Set<ShareMetric> {
        var d: Set<ShareMetric> = [.pace, .duration]
        if activity.avgHeartRate != nil { d.insert(.heartRate) }
        if detail?.avgCadence != nil   { d.insert(.cadence) }
        return d
    }

    func photoFor(_ c: ShareCard) -> UIImage? {
        guard !storyPhotos.isEmpty else { return selectedPhoto }
        let idx = cardPhotoIndex[c] ?? 0
        // PHAsset-loaded high-res photo takes priority over SwiftData thumbnail
        if let hq = oneLinerVM.highQualityStoryPhotos[idx] { return hq }
        return idx < storyPhotos.count ? storyPhotos[idx] : storyPhotos.first
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(storyPhotos.indices, id: \.self) { i in
                    let isSelected = (cardPhotoIndex[card] ?? 0) == i
                    ZStack(alignment: .topTrailing) {
                        Button {
                            // 원라이너 스토리·슬라이드 모드: 탭 → 카드를 해당 사진으로 즉시 전환 후 ClipTrimSheet 열기
                            if isOneLiner, template == .photo || template == .slide {
                                for c in ShareCard.photoLinked { cardPhotoIndex[c] = i }
                                let isSlide = (template == .slide)
                                oneLinerVM.storyClipEditIsSlide = isSlide
                                // cachedStoryRecipes가 있으면 @Query 갱신 대기 없이 즉시 사용 — 직전 편집 결과 보존
                                let cached = oneLinerVM.cachedStoryRecipes
                                oneLinerVM.storyClipEditRecipes = (!cached.isEmpty && cached.count == storyPhotos.count)
                                    ? cached
                                    : makeStoryClipRecipes(isSlide: isSlide)
                                oneLinerVM.storyClipEditIndex = i
                                oneLinerVM.showStoryClipEdit = true
                            } else {
                                // 통일 선택: 모든 카드(Placeable/OneLiner/Athletic) 동시 적용
                                if isOneLiner {
                                    saveOneLinerSettings()
                                    oneLinerFieldFocused = false
                                    for c in ShareCard.photoLinked { cardPhotoIndex[c] = i }
                                    loadOneLinerSettingsFor(photoIndex: i)
                                } else {
                                    for c in ShareCard.photoLinked { cardPhotoIndex[c] = i }
                                    if isStamp {
                                        cardPhotoIndex[.stamp] = i
                                        // 슬라이드 모드: selectedClipIndex를 sync → 프리뷰·컨트롤이 올바른 사진 config 사용
                                        if template == .slide { stampVM.selectedClipIndex = i }
                                    }
                                }
                                Task { await renderCard(showSpinner: false) }
                            }
                        } label: {
                            Image(uiImage: storyPhotos[i])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 46, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Theme.violet : Color.clear, lineWidth: 2)
                                )
                                .overlay {
                                    if oneLinerVM.deletedPhotoIndices.contains(i) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.55))
                                            Image(systemName: "icloud.slash")
                                                .font(.system(size: 12)).foregroundStyle(.white)
                                        }
                                    }
                                }
                                // 슬라이드 모드: 좌하단 duration 배지
                                .overlay(alignment: .bottomLeading) {
                                    if template == .slide {
                                        let defaultSec = isOneLiner
                                            ? PhotoSlideComposition.photoDuration
                                            : PhotoSlideComposition.placeableSlideDuration
                                        // OneLiner: cachedStoryRecipes에서 per-clip 실제 duration 읽기
                                        let sec: Double = (isOneLiner && oneLinerVM.cachedStoryRecipes.indices.contains(i))
                                            ? oneLinerVM.cachedStoryRecipes[i].trimmedDuration
                                            : defaultSec
                                        Text("\(Int(sec.rounded()))s")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4).padding(.vertical, 2)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                            .padding(3)
                                    }
                                }
                                // 한마디 연결 여부 표시: 문구 있는 사진은 우하단 바이올렛 도트
                                .overlay(alignment: .bottomTrailing) {
                                    if isOneLiner, template != .slide, i < oneLinerVM.storyPhotoUUIDs.count {
                                        let ref = "photo:\(oneLinerVM.storyPhotoUUIDs[i])"
                                        let hasText = oneLinerEntries.contains {
                                            $0.mediaRef == ref &&
                                            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        }
                                        if hasText {
                                            Circle()
                                                .fill(Theme.violet)
                                                .frame(width: 9, height: 9)
                                                .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1))
                                                .offset(x: 3, y: 3)
                                        }
                                    } else if isPlaceable, template == .photo {
                                        if !(placeableVM.placeableStoryTexts[i] ?? "").isEmpty {
                                            Circle()
                                                .fill(Theme.violet)
                                                .frame(width: 9, height: 9)
                                                .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1))
                                                .offset(x: 3, y: 3)
                                        }
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        // X 삭제 버튼
                        Button { deleteStoryPhoto(at: i) } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "1A1A28").opacity(0.90))
                                    .frame(width: 18, height: 18)
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }
                if storyPhotos.isEmpty {
                    // 빈 상태: 사진 아이콘 + 텍스트 캡슐 버튼
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 5, matching: .images, photoLibrary: .shared()) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 17))
                            Text(AppLanguage.shared.s("사진 선택", "Select Photos"))
                                .font(.subheadline)
                        }
                        .foregroundStyle(Color.white.opacity(0.55))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                } else {
                    // 비어있지 않으면: 썸네일 바로 옆 + 버튼
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 5, matching: .images, photoLibrary: .shared()) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 46, height: 46)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.violet)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Chip toggle rows

    private var chipRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            // ── Row 1: 대회 칩 (대회 확정 시에만) ───────────────────
            if confirmedRace != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Race chip
                    if let race = confirmedRace {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { showRaceOnCard.toggle() }
                            Task { await renderCard(showSpinner: false) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "flag.checkered")
                                    .font(.system(size: 10))
                                Text(race.raceName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(showRaceOnCard ? Color.white : Color.white.opacity(0.4))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(showRaceOnCard ? Theme.violet : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
            }
            }

            // ── Row 2: metric chips ───────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // 총평 칩 — 페이스 칩 맨 앞. 요약 줄이 2줄 미만이면 차트 칩의 available 스타일처럼 비활성.
                    let summaryAvailable = summaryLines.count >= 2
                    Button {
                        guard summaryAvailable else { return }
                        withAnimation(.easeInOut(duration: 0.15)) { showSummaryOnCard.toggle() }
                        Task { await renderCard(showSpinner: false) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(AppLanguage.shared.s("총평", "Summary"))
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(summaryAvailable ? Color.white : Color.white.opacity(0.18))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            showSummaryOnCard ? Theme.violet
                            : Color.white.opacity(summaryAvailable ? 0.15 : 0.04)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!summaryAvailable)
                    ForEach(allMetricItems) { item in
                        let isOn = enabledMetrics.contains(item.id)
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if isOn { enabledMetrics.remove(item.id) }
                                else    { enabledMetrics.insert(item.id) }
                            }
                            Task { await renderCard(showSpinner: false) }
                        } label: {
                            HStack(spacing: 4) {
                                Text(item.id.chipLabel)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isOn ? Theme.violet : Color.white.opacity(0.15))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
            }

            // ── Row 3: chart panel chips ───
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CardChartPanel.allCases, id: \.self) { panel in
                        let available = isChartPanelAvailable(panel)
                        let isSelected = cardPanel == panel
                        Button {
                            guard available else { return }
                            cardPanel = panel
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: panel.icon)
                                    .font(.system(size: 10))
                                Text(panel.label)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(
                                available ? Color.white : Color.white.opacity(0.18)
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? Theme.violet
                                : Color.white.opacity(available ? 0.15 : 0.04)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Body helpers


    // MARK: - Placeable 템플릿 미리보기·저장·내보내기 → PlaceableVideoTemplate.swift

    @ViewBuilder
    private var stampCardPreview: some View {
        if template == .routeVideo {
            stampRouteVideoPreviewSection
        } else if template == .video {
            stampVideoPreviewSection
        } else if template == .slide {
            stampSlidePreviewSection
        } else if !storyPhotos.isEmpty {
            let selectedIdx = max(0, min(cardPhotoIndex[.stamp] ?? 0, storyPhotos.count - 1))
            let ph = storyPhotos[selectedIdx]
            let s      = max(300 / ph.size.width, 375 / ph.size.height)
            let excess = max(0, ph.size.width * s - 300)
            StampStoryRenderView(photo: ph, data: stampPreviewData, vm: stampVM,
                                 cropOffsetX: stampVM.storyCropOffsetX,
                                 configOverride: stampVM.photoConfig(at: selectedIdx))
                .gesture(excess > 0 ? DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        if stampStoryCropDragBase == nil { stampStoryCropDragBase = stampVM.storyCropOffsetX }
                        guard let base = stampStoryCropDragBase else { return }
                        stampVM.storyCropOffsetX = max(0, min(1,
                            base - drag.translation.width / excess))
                    }
                    .onEnded { _ in
                        stampStoryCropDragBase = nil
                        stampVM.storyCropOffsets[selectedIdx] = stampVM.storyCropOffsetX
                        saveStampConfig()
                    }
                : nil)
        } else {
            StampStoryRenderView(photo: nil, data: stampPreviewData, vm: stampVM)
        }
    }

    @ViewBuilder
    private var stampRouteVideoPreviewSection: some View {
        if routeCoords.isEmpty {
            ZStack {
                Color(hex: "0D0D12")
                VStack(spacing: 10) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.violet)
                    Text(AppLanguage.shared.s("야외 경로 없음", "No outdoor route"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let snap = routeSnapshot {
            let vidW: CGFloat = 375.0 * 9.0 / 16.0
            let inset: CGFloat = 375.0 * 0.05
            ZStack {
                Color.black
                RouteVideoFrameView(
                    snapshot: snap,
                    snapshotPoints: routeSnapshotPoints,
                    routeProgress: routePreviewProgress,
                    metrics: [],
                    distanceKm: distanceKmString,
                    duration: activity.formattedDuration,
                    date: activity.date,
                    showStats: false,
                    hrSamplesForRoute: shareHRSamples,
                    routeWorkoutDuration: activity.duration,
                    routeZoneBounds: shareZoneBounds,
                    showHRGradient: showHRGradientForRoute,
                    topInset: inset,
                    bottomInset: 14
                )
                .frame(width: vidW, height: 375)
                // 스탬프 레이어 — export와 동일하게 renderOnlyStamp로 분리, 입장 애니메이션 적용
                StampCard(
                    data: stampPreviewData,
                    template: stampVM.storyTemplate,
                    colorMode: stampVM.colorMode,
                    position: stampVM.position,
                    sizeLevel: stampVM.sizeLevel,
                    isBrightBackground: false,
                    showHeartRate: stampVM.showHeartRate,
                    showCalories: stampVM.showCalories,
                    showTextOutline: stampVM.showTextOutline,
                    stampText: stampVM.stampText,
                    stampTextPosition: stampVM.stampTextPosition,
                    stampTextFont: stampVM.stampTextFont,
                    stampTextSize: stampVM.stampTextSize,
                    stampTextColor: stampVM.stampTextColor,
                    stampTextHasBorder: stampVM.stampTextHasBorder,
                    wordmarkTopInset: 54,
                    renderOnlyStamp: true
                )
                .frame(width: vidW, height: 375)
                .clipped()
                .allowsHitTesting(false)
                .opacity(previewStampVisible ? 1 : 0)
                .scaleEffect(stampVM.stampEntranceMode == .stamp
                    ? (previewStampVisible ? 1 : 0.001) : 1)
                .offset(stampVM.stampEntranceMode == .flyIn && !previewStampVisible
                    ? stampPreviewFlyOffset(for: stampVM.stampFlyDirection, w: vidW, h: 375) : .zero)
                // 문구 레이어 — OneLinerCard. 스탬프·슬라이드 영상과 동일한 절대값 위치
                if !stampVM.stampText.isEmpty {
                    OneLinerCard(
                        text: stampVM.stampText,
                        position: stampVM.stampTextPosition,
                        textColor: stampVM.stampTextColor,
                        fontChoice: stampVM.stampTextFont,
                        sizeLevel: stampVM.stampTextSize,
                        appearanceMode: .typing,
                        decorEffect: .none,
                        hasBorder: stampVM.stampTextHasBorder,
                        showBackground: false,
                        showWordmark: false,
                        cardHeightOverride: 375,
                        cardWidthOverride: vidW,
                        safeTopInset: 54,
                        safeBottomInset: 14,
                        isStaticPreview: true
                    )
                    .frame(width: vidW, height: 375)
                    .clipped()
                    .allowsHitTesting(false)
                    .opacity(previewTextVisible ? 1 : 0)
                    .scaleEffect(stampVM.stampTextEntranceMode == .stamp
                        ? (previewTextVisible ? 1 : 0.001) : 1)
                    .offset(stampVM.stampTextEntranceMode == .flyIn && !previewTextVisible
                        ? stampPreviewFlyOffset(for: stampVM.stampTextFlyDirection, w: vidW, h: 375) : .zero)
                }
                // 로고(좌측 상단) — 영상·슬라이드 미리보기와 동일 size: 11
                MIMOWordmark(size: 11, onMediaCard: true)
                    .padding(.leading, vidW * 0.047)
                    .padding(.top, 375.0 * 0.06)
                    .frame(width: vidW, height: 375, alignment: .topLeading)
                if stampVM.showDate {
                    StampDateLabel(date: activity.date)
                        .padding(.trailing, vidW * 0.05)
                        .padding(.top, 375.0 * 0.06 + 8)
                        .frame(width: vidW, height: 375, alignment: .topTrailing)
                }
                // 미리보기 재생 버튼
                if !isRoutePreviewPlaying {
                    Button {
                        routePreviewProgress = 0
                        previewStampVisible = false
                        previewTextVisible = false
                        isRoutePreviewPlaying = true
                        routePreviewPlayCount += 1
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.5), radius: 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            ZStack {
                Color(hex: "0D0D12")
                VStack(spacing: 10) {
                    ProgressView().tint(Theme.violet)
                    Text(AppLanguage.shared.s("경로 준비 중…", "Loading route…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var stampPreviewData: StampData {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "MMM d"
        let dateText = df.string(from: activity.date).uppercased()
        df.dateFormat = "EEE"
        let weekday = df.string(from: activity.date).uppercased()

        // 지배적 심박 존 (시간이 가장 많은 존)
        let dominantZone = detail?.hrZones.max(by: { $0.seconds < $1.seconds })
        let hrZoneLabel  = dominantZone.map { "Z\($0.id)" }
        let hrZoneIndex  = dominantZone.map { $0.id - 1 }   // 0-based (0~4)
        let hrZoneName   = dominantZone?.name.uppercased()

        // 스플릿에서 최고 심박
        let hrMax = detail?.splits.compactMap(\.avgHeartRate).max().map { "\($0)" }

        // 스플릿 심박 → 0~1 정규화
        let hrSeries: [Double]? = {
            let vals = detail?.splits.compactMap(\.avgHeartRate) ?? []
            guard vals.count > 1,
                  let lo = vals.min(), let hi = vals.max(), hi > lo else { return nil }
            return vals.map { Double($0 - lo) / Double(hi - lo) }
        }()

        // 고도 프로파일 → 0~1 정규화
        let elevSeries: [Double]? = {
            let profile = detail?.altitudeProfile ?? []
            guard profile.count > 1 else { return nil }
            let alts = profile.map(\.altitude)
            guard let lo = alts.min(), let hi = alts.max(), hi > lo else { return nil }
            return alts.map { ($0 - lo) / (hi - lo) }
        }()

        var d = StampData(
            distance: distanceKmString,
            distanceUnit: "KM",
            pace: activity.formattedPace ?? "--'--\"",
            time: activity.formattedDuration,
            heartRate: activity.avgHeartRate.map { "\($0)" },
            calories: activity.calories.map { String(format: "%.0f", $0) },
            dateText: dateText,
            locationText: "KR",
            weekday: weekday
        )
        d.heartRateMax  = hrMax
        d.hrZoneLabel   = hrZoneLabel
        d.hrZoneIndex   = hrZoneIndex
        d.hrZoneName    = hrZoneName
        d.cadence       = detail?.avgCadence.map { "\($0)" }
        d.elevGain      = detail?.elevationGain.map { String(format: "%.0f", $0) }
        d.elevSeries    = elevSeries
        d.hrSeries      = hrSeries
        d.placeName     = stampPlaceName
        d.placeRegion   = stampPlaceRegion
        d.coordText     = stampCoordText
        d.mapImage           = stampMapImage
        d.routePoints        = stampRoutePoints
        d.routeCoordinates   = routeCoords.count >= 2 ? routeCoords : nil
        d.date               = activity.date
        return d
    }

    // MARK: - Stamp 지명·지도 비동기 프리페치 (1회, 중복 방지)

    func fetchStampPlaceIfNeeded() {
        guard stampPlaceName == nil, stampCoordText == nil,
              let coord = routeCoords.first else { return }
        Task {
            // coordText 즉시 설정
            let lat = coord.latitude, lon = coord.longitude
            let latStr = String(format: "%.2f°%@", abs(lat), lat >= 0 ? "N" : "S")
            let lonStr = String(format: "%.2f°%@", abs(lon), lon >= 0 ? "E" : "W")
            stampCoordText = "\(latStr) \(lonStr)"
            // 역지오코딩
            let location = CLLocation(latitude: lat, longitude: lon)
            if let results = try? await CLGeocoder().reverseGeocodeLocation(location),
               let pm = results.first {
                stampPlaceName   = (pm.locality ?? pm.administrativeArea)?.uppercased()
                stampPlaceRegion = pm.administrativeArea?.uppercased()
            }
        }
    }

    func fetchStampMapIfNeeded() {
        guard stampMapImage == nil, routeCoords.count > 1 else { return }
        Task {
            if let result = try? await RouteVideoExportService.mapSnapshot(coordinates: routeCoords) {
                stampMapImage   = result.image
                stampRoutePoints = result.points
            }
        }
    }

    @ViewBuilder
    private var oneLinerCardPreview: some View {
        if template == .video {
            // 211×375pt 고정 — Stamp·Placeable 영상과 동일한 좌표계, 스케일 계산 없음.
            let previewW: CGFloat = 211
            if card == .oneLiner, previewPlayer.isReady, previewPlayer.isPlaying,
               let pl = previewPlayer.player, let cl = previewPlayer.contentLayer {
                // 재생 중: 실제 영상 + CALayer 애니메이션 + SwiftUI 워드마크 오버레이
                OneLinerPreviewView(player: pl, contentLayer: cl, renderSize: previewPlayer.renderSize)
                    .frame(width: previewW, height: CardPreviewFrame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .bottom) {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Theme.violet)
                                .frame(width: geo.size.width * previewPlayer.progress, height: 3)
                                .animation(.linear(duration: 0.1), value: previewPlayer.progress)
                        }
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                    .overlay {
                        Button { previewPlayer.togglePlayPause() } label: {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.white.opacity(0))
                        }
                        .buttonStyle(.plain)
                    }
                    .overlay(alignment: .topLeading) {
                        MIMOWordmark(size: 11, onMediaCard: true)
                            .padding(.top, 22)
                            .padding(.leading, 14)
                    }
                    .onTapGesture { previewPlayer.togglePlayPause() }
            } else {
                // 정지·빌드 전: 정적 프리뷰 — 211×375pt 카드 직접 표시 (스케일 없음)
                oneLinerVideoPreviewCard
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .bottom) {
                        // 빌드 완료 상태면 진행 바 표시 (정지 위치 유지)
                        if previewPlayer.isReady {
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Theme.violet)
                                    .frame(width: geo.size.width * previewPlayer.progress, height: 3)
                            }
                            .frame(height: 3)
                            .clipShape(RoundedRectangle(cornerRadius: 1.5))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                        }
                    }
                    .overlay {
                        if previewPlayer.isBuilding {
                            ProgressView().tint(.white)
                                .padding(14)
                                .background(.black.opacity(0.45))
                                .clipShape(Circle())
                        } else if previewPlayer.isReady {
                            // 빌드 완료, 정지 중 — 재생 버튼
                            Button { previewPlayer.play() } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .shadow(color: .black.opacity(0.5), radius: 8)
                            }
                            .buttonStyle(.plain)
                        } else if !oneLinerVM.oneLinerClipRecipes.isEmpty {
                            // 미빌드 — 빌드 + 재생 버튼
                            Button { buildPreview() } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .shadow(color: .black.opacity(0.5), radius: 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        MIMOWordmark(size: 11, onMediaCard: true)
                            .padding(.top, 22)
                            .padding(.leading, 14)
                    }
            }
        } else if template == .slide {
            // 슬라이드: 재생 중일 때만 animated preview, 정지·미준비 시 정적 카드 + ▶ 버튼
            if card == .oneLiner, previewPlayer.isReady, previewPlayer.isPlaying,
               let pl = previewPlayer.player, let cl = previewPlayer.contentLayer {
                // 9:16 → 4:5 높이(375pt)에 비례 축소 (211×375pt)
                let previewW: CGFloat = 211
                OneLinerPreviewView(player: pl, contentLayer: cl, renderSize: previewPlayer.renderSize)
                    .frame(width: previewW, height: CardPreviewFrame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .bottom) {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Theme.violet)
                                .frame(width: geo.size.width * previewPlayer.progress, height: 3)
                                .animation(.linear(duration: 0.1), value: previewPlayer.progress)
                        }
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                    .overlay {
                        Button { previewPlayer.togglePlayPause() } label: {
                            Image(systemName: previewPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.white.opacity(previewPlayer.isPlaying ? 0 : 0.85))
                                .shadow(color: .black.opacity(0.5), radius: 8)
                        }
                        .buttonStyle(.plain)
                    }
                    .onTapGesture { previewPlayer.togglePlayPause() }
            } else {
                // 슬라이드 정적 대기 카드: 영상과 동일 211×375pt 직접 렌더 (scaleEffect 제거)
                let idx   = cardPhotoIndex[.oneLiner]
                let photo = idx.flatMap { storyPhotos.indices.contains($0) ? storyPhotos[$0] : nil }
                         ?? (!storyPhotos.isEmpty ? storyPhotos[0] : nil)
                // cachedStoryRecipes 우선 — @Query 갱신 지연 없이 편집 직후에도 즉시 반영
                let sr: ClipRecipe? = {
                    let i = cardPhotoIndex[.oneLiner] ?? 0
                    if !oneLinerVM.cachedStoryRecipes.isEmpty, oneLinerVM.cachedStoryRecipes.indices.contains(i) {
                        return oneLinerVM.cachedStoryRecipes[i]
                    }
                    return slideStaticRecipe
                }()
                let olSlidePhotoI = idx ?? 0
                let olSlideCropX = oneLinerVM.oneLinerStoryCropOffsets[olSlidePhotoI]
                    ?? CGFloat(sr?.cropOffsetX ?? 0.5)
                let olSlideExcessX: CGFloat = {
                    guard let p = photo else { return 0 }
                    let s = max(211.0 / p.size.width, 375.0 / p.size.height)
                    return max(0, p.size.width * s - 211.0)
                }()
                OneLinerCard(
                    activity: activity,
                    backgroundPhoto: photo,
                    cropOffsetX: olSlideCropX,
                    text: sr?.lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n") ?? "",
                    position: sr?.position ?? oneLinerVM.oneLinerPosition,
                    textColor: sr?.textColor ?? oneLinerVM.oneLinerColor,
                    fontChoice: sr?.fontChoice ?? oneLinerVM.oneLinerFont,
                    sizeLevel: sr?.sizeLevel ?? .large,
                    appearanceMode: sr?.appearanceMode ?? .typing,
                    decorEffect: sr?.decorEffect ?? .none,
                    hasBorder: sr?.hasBorder ?? false,
                    showWordmark: false,
                    chartBottomReserved: storyChartBottomReserved(for: sr, cardHeight: 375),
                    videoTitle: oneLinerVM.oneLinerVideoTitle,
                    titleStyle: oneLinerVM.oneLinerTitleStyle,
                    cardHeightOverride: 375,
                    cardWidthOverride: 211,
                    horizontalPadding: 14,
                    isStaticPreview: true,
                    metricPace: sr?.metricPace ?? false,
                    metricDistance: sr?.metricDistance ?? false,
                    metricTime: sr?.metricTime ?? false,
                    metricHeartRate: sr?.metricHeartRate ?? false,
                    pdtPosition: sr?.pdtPosition ?? .bottomLeading,
                    pdtSizeLevel: sr?.pdtSizeLevel ?? .medium,
                    availableMetrics: oneLinerAvailableMetrics,
                    showRoute: sr?.showRoute ?? false,
                    routeCoords: routeCoords,
                    routePosition: sr?.routePosition ?? .bottomTrailing,
                    showHRChart: sr?.showHRChart ?? false,
                    hrSamples: shareHRSamples,
                    hrZones: detail?.hrZones ?? [],
                    chartOverlayType: sr?.chartOverlayType ?? .none,
                    chartSeriesData: chartSeriesData,
                    chartSplits: detail?.splits ?? [],
                    intervalSegments: detail?.intervalSegments ?? []
                )
                .frame(width: 211, height: 375)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .simultaneousGesture(
                    !previewPlayer.isPlaying && olSlideExcessX > 1 ? DragGesture(minimumDistance: 1)
                        .onChanged { drag in
                            if oneLinerVM.oneLinerCropDragBase == nil {
                                oneLinerVM.oneLinerCropDragBase = olSlideCropX
                            }
                            guard let base = oneLinerVM.oneLinerCropDragBase else { return }
                            oneLinerVM.oneLinerStoryCropOffsets[olSlidePhotoI] = max(0, min(1,
                                base - drag.translation.width / olSlideExcessX))
                        }
                        .onEnded { _ in
                            oneLinerVM.oneLinerCropDragBase = nil
                            let newX = oneLinerVM.oneLinerStoryCropOffsets[olSlidePhotoI] ?? olSlideCropX
                            saveOneLinerCropX(photoIndex: olSlidePhotoI, offsetX: newX, isSlide: true)
                        }
                    : nil
                )
                .overlay {
                    if previewPlayer.isBuilding {
                        ProgressView().tint(.white)
                            .padding(14)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                    } else if previewPlayer.isReady {
                        // 빌드 완료, 정지 중 — buildPreview() 재호출 없이 바로 재생
                        Button { previewPlayer.play() } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.55), radius: 10)
                        }
                        .buttonStyle(.plain)
                    } else if oneLinerHasPhotos {
                        // 미빌드 — 빌드 후 재생 (사진 있을 때만)
                        Button { buildPreview() } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.55), radius: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .overlay(alignment: .topLeading) {
                    MIMOWordmark(size: 11, onMediaCard: true)
                        .padding(.top, 22)
                        .padding(.leading, 14)
                }
            }
        } else {
            let idx   = cardPhotoIndex[.oneLiner]
            let photoI = idx ?? 0
            let photo = idx.flatMap { storyPhotos.indices.contains($0) ? storyPhotos[$0] : nil }
                     ?? (!storyPhotos.isEmpty ? storyPhotos[0] : nil)
            // @Query 갱신 타이밍 이슈 우회: 편집 직후엔 oneLinerVM.cachedStoryRecipes 사용 (클로저로 계산)
            let pr: ClipRecipe? = {
                let i = photoI
                if !oneLinerVM.cachedStoryRecipes.isEmpty, oneLinerVM.cachedStoryRecipes.indices.contains(i) {
                    return oneLinerVM.cachedStoryRecipes[i]
                }
                return photoRecipe(at: i, prefix: "photo:")
            }()
            let cropX = oneLinerVM.oneLinerStoryCropOffsets[photoI]
                     ?? CGFloat(pr?.cropOffsetX ?? 0.5)
            let olExcessX: CGFloat = {
                guard let p = photo else { return 0 }
                let s = max(300.0 / p.size.width, 375.0 / p.size.height)
                return max(0, p.size.width * s - 300)
            }()
            OneLinerCard(
                activity: activity,
                backgroundPhoto: photo,
                cropOffsetX: cropX,
                text: pr?.lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n") ?? oneLinerVM.oneLinerText,
                position: pr?.position ?? oneLinerVM.oneLinerPosition,
                textColor: pr?.textColor ?? oneLinerVM.oneLinerColor,
                fontChoice: pr?.fontChoice ?? oneLinerVM.oneLinerFont,
                sizeLevel: pr?.sizeLevel ?? .large,
                appearanceMode: pr?.appearanceMode ?? .typing,
                decorEffect: pr?.decorEffect ?? .none,
                hasBorder: pr?.hasBorder ?? false,
                captionMode: true,
                chartBottomReserved: storyChartBottomReserved(for: pr),
                isStaticPreview: true,
                metricPace: pr?.metricPace ?? false,
                metricDistance: pr?.metricDistance ?? false,
                metricTime: pr?.metricTime ?? false,
                metricHeartRate: pr?.metricHeartRate ?? false,
                pdtPosition: pr?.pdtPosition ?? .bottomLeading,
                pdtSizeLevel: pr?.pdtSizeLevel ?? .medium,
                availableMetrics: oneLinerAvailableMetrics,
                showRoute: pr?.showRoute ?? false,
                routeCoords: routeCoords,
                routePosition: pr?.routePosition ?? .bottomTrailing,
                showHRChart: pr?.showHRChart ?? false,
                hrSamples: shareHRSamples,
                hrZones: detail?.hrZones ?? [],
                chartOverlayType: pr?.chartOverlayType ?? .none,
                chartSeriesData: chartSeriesData,
                chartSplits: detail?.splits ?? [],
                intervalSegments: detail?.intervalSegments ?? []
            )
            .simultaneousGesture(
                olExcessX > 0 ? DragGesture(minimumDistance: 8)
                    .onChanged { drag in
                        if oneLinerVM.oneLinerCropDragBase == nil {
                            guard abs(drag.predictedEndTranslation.width) <= abs(drag.translation.width) * 3.0 else { return }
                            oneLinerVM.oneLinerCropDragBase = cropX
                        }
                        guard let base = oneLinerVM.oneLinerCropDragBase else { return }
                        oneLinerVM.oneLinerStoryCropOffsets[photoI] =
                            max(0, min(1, base - drag.translation.width / olExcessX))
                    }
                    .onEnded { _ in
                        let didCrop = oneLinerVM.oneLinerCropDragBase != nil
                        oneLinerVM.oneLinerCropDragBase = nil
                        if didCrop { saveOneLinerCropX(photoIndex: photoI, offsetX: oneLinerVM.oneLinerStoryCropOffsets[photoI] ?? cropX) }
                    }
                : nil
            )
        }
    }

    private var oneLinerVideoPreviewCard: some View {
        // OneLinerCard at 211×375pt — Stamp·Placeable 영상과 동일한 좌표계. 스케일 없음.
        let clipRecipe = oneLinerVM.oneLinerClipRecipes.first
        let clipText: String = clipRecipe?.lines
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n") ?? oneLinerVM.oneLinerText
        let clipColor: OneLinerTextColor = clipRecipe?.textColor ?? oneLinerVM.oneLinerColor
        let clipFont: OneLinerFont = clipRecipe?.fontChoice ?? oneLinerVM.oneLinerFont
        let clipPos: CardPosition = clipRecipe?.position ?? oneLinerVM.oneLinerPosition
        let clipSize: TextSizeLevel = clipRecipe?.sizeLevel ?? .large
        let clipAppear: AppearanceMode = clipRecipe?.appearanceMode ?? .typing
        let clipDecor: DecorEffect = clipRecipe?.decorEffect ?? .none
        let clipBorder: Bool = clipRecipe?.hasBorder ?? false
        let clipFly: FlyInDirection = clipRecipe?.flyDirection ?? .trailing
        let clipChartBot: CGFloat = storyChartBottomReserved(for: clipRecipe, cardHeight: 375)
        let clipPace: Bool = clipRecipe?.metricPace ?? false
        let clipDist: Bool = clipRecipe?.metricDistance ?? false
        let clipTime: Bool = clipRecipe?.metricTime ?? false
        let clipHR: Bool = clipRecipe?.metricHeartRate ?? false
        let clipPdtPos: CardPosition = clipRecipe?.pdtPosition ?? .bottomLeading
        let clipPdtSize: TextSizeLevel = clipRecipe?.pdtSizeLevel ?? .medium
        let clipShowRoute: Bool = clipRecipe?.showRoute ?? false
        let clipRoutePos: CardPosition = clipRecipe?.routePosition ?? .bottomTrailing
        let clipHRChart: Bool = clipRecipe?.showHRChart ?? false
        let clipHRZones: [HRZoneData] = detail?.hrZones ?? []
        let clipChartType: ChartOverlayType = clipRecipe?.chartOverlayType ?? .none
        let clipSplits: [SplitData] = detail?.splits ?? []
        let clipIntervals: [IntervalSegment] = detail?.intervalSegments ?? []
        return OneLinerCard(
            activity: activity,
            backgroundPhoto: videoPreviewImage,
            text: clipText,
            position: clipPos,
            textColor: clipColor,
            fontChoice: clipFont,
            sizeLevel: clipSize,
            appearanceMode: clipAppear,
            decorEffect: clipDecor,
            hasBorder: clipBorder,
            flyDirection: clipFly,
            showWordmark: false,
            chartBottomReserved: clipChartBot,
            videoTitle: oneLinerVM.oneLinerVideoTitle,
            titleStyle: oneLinerVM.oneLinerTitleStyle,
            cardHeightOverride: 375,
            cardWidthOverride: 211,
            // safeTopInset 미전달 → OneLinerCard 자동 계산(68 × cardWScale = 47.8pt @ 211pt, CALayer 기준 일치)
            horizontalPadding: 14,
            isStaticPreview: true,
            metricPace: clipPace,
            metricDistance: clipDist,
            metricTime: clipTime,
            metricHeartRate: clipHR,
            pdtPosition: clipPdtPos,
            pdtSizeLevel: clipPdtSize,
            availableMetrics: oneLinerAvailableMetrics,
            showRoute: clipShowRoute,
            routeCoords: routeCoords,
            routePosition: clipRoutePos,
            showHRChart: clipHRChart,
            hrSamples: shareHRSamples,
            hrZones: clipHRZones,
            chartOverlayType: clipChartType,
            chartSeriesData: chartSeriesData,
            chartSplits: clipSplits,
            intervalSegments: clipIntervals
        )
        .frame(width: 211, height: 375)
        .clipped()
    }

    private var cardSection: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Stamp
                    stampCardPreview
                        .frame(width: 300, height: 375)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.25), radius: 28, y: 10)
                        .frame(width: w, height: 375)
                        .id(ShareCard.stamp)
                        // 스토리 모드: 상단 사진 스트립 선택이 바뀌면 selectedClipIndex 동기화
                        // → StampControlsView 문구 텍스트 필드가 올바른 사진 텍스트를 표시/편집
                        .onChange(of: cardPhotoIndex[.stamp] ?? 0) { _, newIdx in
                            if isStamp, template == .photo {
                                stampVM.selectedClipIndex = newIdx
                            }
                        }
                    // Placeable — 영상 템플릿은 9:16 넓게(480pt), 그 외 375pt
                    placeableCardPreview
                        .frame(width: 300, height: cardSectionH)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.3), radius: 28, y: 10)
                        .frame(width: w, height: cardSectionH)
                        .id(ShareCard.placeable)
                    // OneLiner (한마디) — 영상 선택 시 9:16 확장
                    AnyView(oneLinerCardPreview)
                        .frame(width: 300, height: oneLinerCardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.1), radius: 28, y: 10)
                        .frame(width: w, height: oneLinerCardHeight)
                        .id(ShareCard.oneLiner)
                    // Athletic (기본 템플릿 카드)
                    AnyView(cardPreview)
                        .frame(width: 300, height: 375)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Theme.violet.opacity(0.3), radius: 28, y: 10)
                        .animation(.easeInOut(duration: 0.2), value: template)
                        .frame(width: w, height: 375)
                        .id(ShareCard.athletic)
                }
            }
            .scrollDisabled(true)
            .frame(width: w, height: cardSectionH)
            .onAppear { scrollProxy.scrollTo(card, anchor: .center) }
            .onChange(of: card) { _, new in
                withAnimation(.easeInOut(duration: 0.3)) {
                    scrollProxy.scrollTo(new, anchor: .center)
                }
            }
            } // ScrollViewReader
        }
        .frame(height: cardSectionH)
        .animation(.easeInOut(duration: 0.3), value: cardSectionH)
    }

    private var cardPageDots: some View {
        HStack(spacing: 0) {
            // ← 이전 카드
            Button { navigateCard(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(card != ShareCard.allCases.first ? 0.55 : 0.15))
                    .frame(width: 36, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(card == ShareCard.allCases.first)

            Spacer(minLength: 0)

            // 카드 이름표 한 줄 — 탭으로 카드 직접 이동 가능
            HStack(spacing: 7) {
                ForEach(ShareCard.allCases, id: \.self) { pageDot($0) }
            }

            Spacer(minLength: 0)

            // → 다음 카드
            Button { navigateCard(by: +1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(card != ShareCard.allCases.last ? 0.55 : 0.15))
                    .frame(width: 36, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(card == ShareCard.allCases.last)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    private func navigateCard(by delta: Int) {
        let all = ShareCard.allCases
        guard let cur = all.firstIndex(of: card), all.indices.contains(cur + delta) else { return }
        card = all[cur + delta]  // onChange(of: card)가 ScrollViewReader로 애니메이션 처리
    }

    /// 카드 이름표 — 카드 전부를 한 줄에 이름으로 표시(4종이라 창·점 축약 없음).
    private func pageDot(_ c: ShareCard) -> some View {
        let isActive = card == c
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { card = c }
        } label: {
            // 선택 = 보라 채움 + 흰 글자 — 템플릿 피커·토글 칩과 같은 표시
            Text(c.name)
                .font(.system(size: 10, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? Color.white : Color(hex: "6E6E78"))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(isActive ? Theme.violet : Color.clear))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: card)
    }

    // MARK: - Locked chips

    @ViewBuilder
    private func lockedChip(_ label: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon).font(.system(size: 10))
            }
            Text(label).font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color(hex: "6E6E78"))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func activeChip(_ label: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon).font(.system(size: 10))
            }
            Text(label).font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.violet)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func availableChip(_ label: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon).font(.system(size: 10))
            }
            Text(label).font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.15))
        .clipShape(Capsule())
    }



    // Chip row for placeholder cards: all chips shown but locked/gray
    private var lockedAllChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                lockedChip(AppLanguage.shared.s("인사이트", "Insight"), icon: "sparkles")
                if canShowMiniMe {
                    lockedChip(AppLanguage.shared.s("미니미", "Mini-Me"))
                }
                ForEach(allMetricItems) { item in
                    lockedChip(item.id.chipLabel)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
        }
    }

    // 로고 칩 — 템플릿 피커 행 오른쪽 끝, 모든 카드 공통 한 자리(전역 설정). 대회 칩과 같은 스타일.
    private var logoChip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { MediaLogoSetting.shared.isOn.toggle() }
            Task { await renderCard(showSpinner: false) }
        } label: {
            HStack(spacing: 4) {
                Text(AppLanguage.shared.s("로고", "Logo"))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(showLogoOnCard ? Color.white : Color.white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(showLogoOnCard ? Theme.violet : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // Chip row selector — extracted from body to keep the body's type-check surface small.
    @ViewBuilder private var activeChipRow: some View {
        if isStamp                              { StampControlsView(vm: stampVM, template: template, data: stampPreviewData,
                                                    onLoadPreview: { await loadStampVideoPreview(data: stampPreviewData) }) }
        else if isPlaceable { placeableStoryModeChipRow }
        else if isOneLiner                      { oneLinerChipRow }
        else                                    { chipRow }
    }

    // Height of the card section: 9:16 (≈533pt) for slide/video templates, 375pt otherwise.
    private var oneLinerCardHeight: CGFloat {
        CardPreviewFrame.height  // 모든 템플릿 375pt — 영상/슬라이드 9:16은 비례 축소(≈211×375)
    }

    /// 카드 섹션 전체 높이 — 모든 카드 375pt (9:16 영상은 내부 필러박스)
    var cardSectionH: CGFloat {
        oneLinerCardHeight
    }

    // 문구가 연결된 사진(story template) 개수 — 2장 이상이면 일괄 저장 모드.
    private var linkedOneLinerPhotoCount: Int {
        guard isOneLiner, template == .photo else { return 0 }
        return oneLinerVM.storyPhotoUUIDs.indices.filter { i in
            let ref = "photo:\(oneLinerVM.storyPhotoUUIDs[i])"
            return oneLinerEntries.contains {
                $0.mediaRef == ref &&
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }.count
    }

    // MARK: - OneLiner chip row

    // Layout (top→bottom):
    //   [9-grid | font 3-chips (VStack) / color 3-chips]
    //   [재사용 칩 — 이 미디어에 entry가 없고 다른 entry가 있을 때만 표시]
    //   [text input field full-width]
    // 다른 카드와 동일하게 인라인 편집 — 쉬는날과 같은 MultiClipEditorView(스토리/영상/슬라이드 공용)
    private var oneLinerChipRow: some View {
        MultiClipEditorView(
            // 스토리 모드에서는 영상 클립을 표시하지 않음 — 사진 관리는 photoStrip이 담당
            recipes: template == .photo ? .constant([]) : Bindable(oneLinerVM).oneLinerClipRecipes,
            isPhotoSlideMode: Binding<Bool>(get: { template == .slide || template == .photo }, set: { _ in }),
            muteAudio: Bindable(oneLinerVM).oneLinerMuteAudio,
            selectedClipIndex: Bindable(oneLinerVM).currentOneLinerClipIndex,
            savedClipLines: [],
            availableMetrics: oneLinerAvailableMetrics,
            enabledMetricIDs: Bindable(oneLinerVM).oneLinerEnabledMetricIDs,
            routeCoords: routeCoords,
            hrSamples: shareHRSamples,
            splits: detail?.splits ?? [],
            chartSeriesData: chartSeriesData,
            hrZones: detail?.hrZones ?? [],
            intervalSegments: detail?.intervalSegments ?? [],
            onSave: {
                if previewPlayer.isReady || previewPlayer.isBuilding {
                    previewPlayer.pause()
                    previewPlayer.invalidate()
                }
                // 영상 템플릿: 첫 클립 썸네일만 업데이트 — buildPreview는 ▶ 버튼으로 수동 시작
                // (자동 빌드하면 스피너가 뜨며 정적 프리뷰의 텍스트·위치가 즉시 보이지 않음)
                if template == .video {
                    if let thumb = oneLinerVM.oneLinerClipRecipes.first?.thumbnail {
                        videoPreviewImage = thumb
                    }
                }
                // 설정 변경 → 이전 export 캐시 무효화 (onSave는 모든 클립 편집 완료 시 호출)
                exportedVideoFile = nil
                // 영상·슬라이드 모드에서 저장 — 스토리 전환 시 빈 배열로 덮어쓰기 방지
                if template == .video || template == .slide { saveOneLinerClipRecipes() }
            },
            isStoryMode: template == .photo,
            showPickerButton: template != .photo && template != .slide,
            showTitleEvenWhenEmpty: template == .slide && !storyPhotos.isEmpty,
            videoTitle: Bindable(oneLinerVM).oneLinerVideoTitle,
            titleStyle: Bindable(oneLinerVM).oneLinerTitleStyle
        )
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }

    // 2번째 카드 = 쉬는날 편집화면을 인라인으로 이식(embedded). 미리보기·편집폼·저장 모두 쉬는날과 동일.
    // 러닝 데이터(P/D/T/M/H)는 클립 편집 그리드 다음에 노출.
    private var oneLinerRestDayEditor: some View {
        RestDayOneLinerSheet(
            date: activity.date,
            activity: activity,
            availableMetrics: oneLinerAvailableMetrics,
            routeCoords: routeCoords,
            hrSamples: shareHRSamples,
            splits: detail?.splits ?? [],
            chartSeriesData: chartSeriesData,
            hrZones: detail?.hrZones ?? [],
            intervalSegments: detail?.intervalSegments ?? [],
            embedded: true,
            belowPreview: AnyView(cardPageDots)
        )
        .frame(maxWidth: .infinity)
        .frame(minHeight: 520)
    }

    // 메인 편집(클립 추가·스타일·데이터)은 쉬는날 방식 전용 시트로
    private var oneLinerEditButton: some View {
        Button { oneLinerVM.showOneLinerSheet = true } label: {
            Label(AppLanguage.shared.s("한마디 편집", "Edit one-liner"), systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Theme.violet)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    // → OneLinerControls.swift: OneLinerVideoSlotInputView
    @ViewBuilder
    private var oneLinerVideoSlotInput: some View {
        OneLinerVideoSlotInputView(
            vm: oneLinerVM,
            onSave:   { saveOneLinerSettings() },
            onRender: { await renderCard(showSpinner: false) }
        )
    }

    // 이 러닝의 고유 문구 풀 (같은 텍스트 중복 제거, 최신순).
    // 칩 줄 상시 표시에 사용.
    private var uniqueOneLinerEntries: [OneLinerEntry] {
        var seen = Set<String>()
        var result: [OneLinerEntry] = []
        for entry in oneLinerEntries.reversed() {   // reversed() = 최신 먼저
            let key = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && seen.insert(key).inserted {
                result.append(entry)
            }
        }
        return result   // 최신순 유지
    }

    // 문구 칩 줄: entry가 1개 이상이면 상시 표시.
    // · 현재 사진에 이미 적용된 문구 칩에는 체크 표시.
    // · 탭 → 현재 사진의 entry를 해당 문구로 교체(upsert 저장).
    // · 다중 사진 연재 모드(사진 2장 이상)에서는 숨김 — 각 사진마다 독립 입력이 의도된 설계.
    @ViewBuilder
    private var oneLinerReuseChipRow: some View {
        let isMultiPhotoStory = template == .photo && oneLinerVM.storyPhotoUUIDs.count > 1
        if !uniqueOneLinerEntries.isEmpty && !isMultiPhotoStory {
            let currentText = oneLinerVM.oneLinerText.trimmingCharacters(in: .whitespacesAndNewlines)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(uniqueOneLinerEntries) { entry in
                        let isCurrent = entry.text.trimmingCharacters(in: .whitespacesAndNewlines) == currentText
                        Button {
                            oneLinerVM.oneLinerText     = entry.text
                            oneLinerVM.oneLinerFont     = entry.font
                            oneLinerVM.oneLinerColor    = entry.textColor
                            oneLinerVM.oneLinerPosition = entry.position
                            saveOneLinerSettings()           // 현재 사진 entry에 upsert
                            Task { await renderCard(showSpinner: false) }
                        } label: {
                            HStack(spacing: 5) {
                                Text(entry.text.count > 10
                                     ? String(entry.text.prefix(10)) + "…"
                                     : entry.text)
                                    .font(.custom(entry.font.fontName, size: 13))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isCurrent ? Color.white : entry.textColor.color.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isCurrent ? Theme.violet : Color(hex: "1E1E28"))
                            .overlay(Capsule().strokeBorder(
                                isCurrent ? Color.clear : Color.white.opacity(0.15),
                                lineWidth: 1
                            ))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // → OneLinerControls.swift: OneLinerGridAndChipsView
    private var oneLinerGridAndChips: some View {
        OneLinerGridAndChipsView(
            vm:                  oneLinerVM,
            template:            template,
            hasSourceVideo:      sourceVideoURL != nil || !oneLinerVM.oneLinerClipRecipes.isEmpty,
            onSave:              { saveOneLinerSettings() },
            onRender:            { await renderCard(showSpinner: false) },
            onVideoStyleChange:  {
                guard isOneLiner, template == .video else { return }
                previewPlayer.invalidate()
                exportedVideoFile = nil
                buildPreview()
            }
        )
    }

    // → OneLinerControls.swift: OneLinerTextFieldView
    @ViewBuilder
    private var oneLinerTextField: some View {
        OneLinerTextFieldView(
            vm:          oneLinerVM,
            focusedLine: $oneLinerFocusedLine,
            onSave:      { saveOneLinerSettings() },
            onRender:    { await renderCard(showSpinner: false) }
        )
    }

    // 현재 카드가 지원하는 템플릿만, ShareTemplate 선언 순서대로.
    private var templateTabs: [ShareTemplate] {
        ShareTemplate.allCases.filter { card.supportedTemplates.contains($0) }
    }

    private var templatePicker: some View {
        HStack(spacing: 0) {
            ForEach(templateTabs, id: \.self) { t in
                let selected  = template == t
                Button {
                    if isOneLiner {
                        previewPlayer.pause()
                    }
                    withAnimation(.easeInOut(duration: 0.15)) { template = t }
                } label: {
                    // 세그먼트(항상 하나 선택)라 체크 없음 — 체크는 토글 칩의 기호. 선택은 같은 화면의
                    // 토글 칩과 같은 보라 채움 + 흰 글자. 5칸 + 로고 칩이면 칸 폭 ≈57pt라 한 줄 고정(최소 85%).
                    Text(t.label)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            selected
                                ? RoundedRectangle(cornerRadius: 8).fill(Theme.violet)
                                : nil
                        )
                }
            }
            // 로고 on/off — 피커 버튼들이 maxWidth: .infinity라 칩 폭만큼만 양보하고 한 줄 유지
            logoChip
                .fixedSize()
                .padding(.leading, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var bottomControls: some View {
        if template == .video, !isStamp {
            Text(AppLanguage.shared.s("영상 선택과 공유시 영상 길이에 따라 시간이 소요됩니다.", "Processing time varies by video length."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.bottom, 8)
        } else {
            Color.clear.frame(height: 20)
        }
    }

    // MARK: - Body helpers (extracted to prevent @ViewBuilder stack overflow)

    @ViewBuilder
    private var oneLinerControlPanel: some View {
        AnyView(templatePicker)
        Color.clear.frame(height: 8)
        AnyView(activeChipRow)
        if template == .photo || template == .slide {
            AnyView(photoStrip.padding(.bottom, 4))
            if template == .slide, !storyPhotos.isEmpty {
                // cachedStoryRecipes에 실제 per-clip duration이 있으면 합산, 없으면 photoDuration 기본값 사용
                let totalSec: Int = {
                    if oneLinerVM.cachedStoryRecipes.count == storyPhotos.count {
                        return Int(oneLinerVM.cachedStoryRecipes.reduce(0) { $0 + $1.trimmedDuration }.rounded())
                    }
                    return Int(Double(storyPhotos.count) * PhotoSlideComposition.photoDuration)
                }()
                Text(AppLanguage.shared.s("클립 \(storyPhotos.count)개 · \(totalSec)초 · 탭하면 상세 편집", "\(storyPhotos.count) clips · \(totalSec)s · Tap to edit"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
            }
        }
        AnyView(bottomControls)
    }

    @ViewBuilder
    private var placeableControlPanel: some View {
        AnyView(templatePicker)
        AnyView(activeChipRow.padding(.bottom, 3))
        if isPlaceable, template == .photo || template == .slide {
            AnyView(placeableStoryTextField)
        }
        if isPlaceable, template == .video, !placeableVM.placeableClipRecipes.isEmpty {
            AnyView(placeableTrimRow)
        }
        if isStamp, template == .video, !stampVM.clipRecipes.isEmpty {
            AnyView(stampTrimRow)
        }
        if template == .photo || (isStamp && template == .slide) {
            AnyView(photoStrip.padding(.bottom, 8))
        }
        if isPlaceable, template == .slide {
            AnyView(photoStrip.padding(.bottom, storyPhotos.isEmpty ? 4 : 0))
            if !storyPhotos.isEmpty {
                let clipCnt = storyPhotos.count
                let totalSec = Int(Double(clipCnt) * PhotoSlideComposition.placeableSlideDuration)
                Text(AppLanguage.shared.s(
                    "사진 \(clipCnt)장 · \(totalSec)초",
                    "\(clipCnt) photo(s) · \(totalSec)s"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
            }
        }
        // Athletic 슬라이드: 사진 스트립만 표시 (문구·데이터 그리드 없음)
        if !isOneLiner, !isPlaceable, !isStamp, template == .slide {
            AnyView(photoStrip.padding(.bottom, storyPhotos.isEmpty ? 4 : 0))
            if !storyPhotos.isEmpty {
                let clipCnt = storyPhotos.count
                let totalSec = Int(Double(clipCnt) * PhotoSlideComposition.placeableSlideDuration)
                Text(AppLanguage.shared.s(
                    "사진 \(clipCnt)장 · \(totalSec)초",
                    "\(clipCnt) photo(s) · \(totalSec)s"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
            }
        }
        if template == .video {
            if isPlaceable {
                AnyView(MultiClipEditorView(
                    recipes: Bindable(placeableVM).placeableClipRecipes,
                    isPhotoSlideMode: .constant(false),
                    muteAudio: Bindable(placeableVM).placeableMuteAudio,
                    selectedClipIndex: $placeableVM.selectedPlaceableClipIndex,
                    savedClipLines: [],
                    availableMetrics: [],
                    enabledMetricIDs: Bindable(placeableVM).placeableEnabledMetricIDs,
                    onSave: {
                        savePlaceableVideoClips()
                        Task { await loadPlaceablePreview() }
                    },
                    showTitle: false,
                    openEditOnTap: false,
                    videoTitle: Bindable(placeableVM).placeableVideoTitle,
                    titleStyle: Bindable(placeableVM).placeableTitleStyle
                )
                .padding(.horizontal, 24))
            } else if isStamp {
                AnyView(MultiClipEditorView(
                    recipes: Bindable(stampVM).clipRecipes,
                    isPhotoSlideMode: .constant(false),
                    muteAudio: Bindable(stampVM).muteAudio,
                    selectedClipIndex: $stampVM.selectedClipIndex,
                    savedClipLines: [],
                    availableMetrics: [],
                    enabledMetricIDs: .constant(Set<String>()),
                    onSave: {
                        exportedVideoFile = nil
                        Task { await loadStampVideoPreview(data: stampPreviewData) }
                    },
                    showTitle: false,
                    openEditOnTap: false,
                    showEditHint: false,
                    videoTitle: .constant(""),
                    titleStyle: .constant(OneLinerTitleStyle())
                )
                .padding(.horizontal, 24))
            } else {
                // Athletic 영상: 멀티 클립 (최대 5개) + 개별 트림 바
                AnyView(VStack(alignment: .leading, spacing: 10) {
                    // 썸네일 row
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Bindable(athleticVM).athleticClipRecipes) { $recipe in
                                let clipIdx = athleticVM.athleticClipRecipes.firstIndex(where: { $0.id == recipe.id }) ?? 0
                                let isSel   = athleticVM.selectedAthleticClipIndex == clipIdx
                                ZStack(alignment: .topTrailing) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Group {
                                            if let thumb = recipe.thumbnail {
                                                Image(uiImage: thumb)
                                                    .resizable().scaledToFill()
                                            } else {
                                                Rectangle()
                                                    .fill(Color.white.opacity(0.12))
                                            }
                                        }
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(isSel ? Theme.violet : Color.white.opacity(0.25), lineWidth: isSel ? 2.5 : 1.5))
                                        .onTapGesture { athleticVM.selectedAthleticClipIndex = clipIdx }
                                        let sec = recipe.trimEnd - recipe.trimStart
                                        Text(sec >= 10 ? "\(Int(sec))s" : String(format: "%.1fs", sec))
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4).padding(.vertical, 2)
                                            .background(Color.black.opacity(0.65))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                            .padding(3)
                                    }
                                    Button {
                                        let rid = recipe.id
                                        let removedIdx = athleticVM.athleticClipRecipes.firstIndex(where: { $0.id == rid }) ?? 0
                                        athleticVM.athleticClipRecipes.removeAll { $0.id == rid }
                                        athleticVM.selectedAthleticClipIndex = max(0, min(removedIdx, athleticVM.athleticClipRecipes.count - 1))
                                        if athleticVM.athleticClipRecipes.isEmpty {
                                            sourceVideoURL    = nil
                                            videoPreviewImage = nil
                                        } else {
                                            sourceVideoURL    = athleticVM.athleticClipRecipes.first?.url
                                            videoPreviewImage = athleticVM.athleticClipRecipes.first?.thumbnail
                                        }
                                        exportedVideoFile = nil
                                    } label: {
                                        ZStack {
                                            Circle().fill(Color.black.opacity(0.65)).frame(width: 18, height: 18)
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 5, y: -5)
                                }
                            }
                            // 빈 상태: 스탬프와 동일한 넓은 버튼 / 클립 있을 때: 인라인 + 버튼
                            if athleticVM.athleticClipRecipes.isEmpty {
                                PhotosPicker(
                                    selection: Bindable(athleticVM).athleticPickerItems,
                                    maxSelectionCount: 5,
                                    matching: .videos,
                                    photoLibrary: .shared()
                                ) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 17))
                                        Text(AppLanguage.shared.s("영상 선택", "Select Video"))
                                            .font(.subheadline)
                                    }
                                    .foregroundStyle(Color.white.opacity(0.55))
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            } else if athleticVM.athleticClipRecipes.count < 5 {
                                PhotosPicker(
                                    selection: Bindable(athleticVM).athleticPickerItems,
                                    maxSelectionCount: 5 - athleticVM.athleticClipRecipes.count,
                                    matching: .videos,
                                    photoLibrary: .shared()
                                ) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 52, height: 52)
                                        .overlay(Image(systemName: "plus")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Theme.violet))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    // 음소거 토글
                    Button {
                        athleticVM.athleticMuted.toggle()
                        athleticVM.athleticVideoState.player?.isMuted = athleticVM.athleticMuted
                        exportedVideoFile = nil
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: athleticVM.athleticMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .medium))
                            Text(AppLanguage.shared.s(
                                athleticVM.athleticMuted ? "음소거" : "소리 켜짐",
                                athleticVM.athleticMuted ? "Muted" : "Sound On"
                            ))
                            .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(athleticVM.athleticMuted ? .secondary : Theme.violet)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(athleticVM.athleticMuted ? Color.white.opacity(0.08) : Theme.violet.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 선택된 클립 트림 바
                    let selIdx = min(max(0, athleticVM.selectedAthleticClipIndex),
                                     athleticVM.athleticClipRecipes.count - 1)
                    if athleticVM.athleticClipRecipes.indices.contains(selIdx) {
                        let selRecipe = athleticVM.athleticClipRecipes[selIdx]
                        let maxSec = min(selRecipe.fullDuration, VideoExportService.trimDuration)
                        let used   = max(0.0, selRecipe.trimEnd - selRecipe.trimStart)
                        VStack(spacing: 4) {
                            Text(AppLanguage.shared.s(
                                "\(trimFormatSec(selRecipe.trimStart)) – \(trimFormatSec(selRecipe.trimEnd))  ·  \(trimFormatSec(used)) 사용",
                                "\(trimFormatSec(selRecipe.trimStart)) – \(trimFormatSec(selRecipe.trimEnd))  ·  \(trimFormatSec(used)) used"
                            ))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            TrimBarView(
                                duration: maxSec,
                                trimStart: Bindable(athleticVM).athleticClipRecipes[selIdx].trimStart,
                                trimEnd:   Bindable(athleticVM).athleticClipRecipes[selIdx].trimEnd,
                                onEditingEnded: { exportedVideoFile = nil }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8))
            }
        }
        AnyView(bottomControls)
    }

    // MARK: - Body

    // Extracted to keep the body modifier chain within Swift's type-check budget.
    private var bodyContent: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 4)
                    cardSection
                    cardPageDots
                    Color.clear.frame(height: 6)
                    if isOneLiner {
                        oneLinerControlPanel
                    } else {
                        placeableControlPanel
                    }
                    Color.clear.frame(height: 8)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            shareCTA
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .background(Theme.background.ignoresSafeArea())
        }
        .navigationTitle(AppLanguage.shared.s("카드 만들기", "Create Card"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // bodyWithSheets: sheet 표시 모디파이어를 분리해 타입체커 부담 감소
    private var bodyWithSheets: some View {
        bodyContent
        .sheet(isPresented: $showStoryPhotoPicker) {
            let pickerPhotos = allPickedPhotos.isEmpty ? storyPhotos : allPickedPhotos
            StoryPhotoPickerSheet(photos: pickerPhotos, selected: selectedPhoto) { picked, idx in
                selectedPhoto = picked
                selectedPhotoIndex = idx
                showStoryPhotoPicker = false
                Task { await renderCard() }
            }
        }
        .sheet(isPresented: Bindable(oneLinerVM).showStoryClipEdit, onDismiss: onStoryClipEditDismiss) {
            ClipTrimSheet(
                recipes: Bindable(oneLinerVM).storyClipEditRecipes,
                selectedClipIndex: Bindable(oneLinerVM).storyClipEditIndex,
                hideTimePicker: template == .photo,
                isStoryMode: template == .photo,
                isPhotoSlideMode: template == .slide,
                availableMetrics: oneLinerAvailableMetrics,
                routeCoords: routeCoords,
                hrSamples: shareHRSamples,
                splits: detail?.splits ?? [],
                chartSeriesData: chartSeriesData,
                hrZones: detail?.hrZones ?? [],
                intervalSegments: detail?.intervalSegments ?? [],
                videoTitle: oneLinerVM.oneLinerVideoTitle,
                titleStyle: oneLinerVM.oneLinerTitleStyle
            )
        }
    }

    // bodyWithPickerHandlers: picker/template/card 변경 핸들러 (타입체커 분산)
    private var bodyWithPickerHandlers: some View {
        bodyWithSheets
        .task { await onAppear() }
        .onChange(of: pickerItems) { _, newItems in onPickerItemsChanged(newItems) }
        .onChange(of: videoPickerItem) { _, newItem in onVideoPickerItemChanged(newItem) }
        .onChange(of: athleticVM.athleticPickerItems) { _, newItems in onAthleticPickerItemsChanged(newItems) }
        .onChange(of: template) { old, new in syncOneLinerVideoBacking(from: old, to: new); onTemplateChanged() }
        .onChange(of: cardPanel) { _, newPanel in
            Task {
                await loadChartData(for: newPanel)
                await renderCard(showSpinner: false)
            }
        }
        .onChange(of: card) { _, newCard in onCardChanged(newCard) }
        .onDisappear {
            // 뷰가 dismiss될 때 현재 영상 클립 문구·스타일을 UserDefaults에 저장.
            // 텍스트 필드 바인딩의 onChange 타이밍 이슈로 미저장된 경우 여기서 최종 보장.
            savePlaceableVideoClips()
        }
    }

    // bodyWithEventHandlers attaches onChange/task handlers; split from body to reduce
    // the modifier chain the Swift type-checker must evaluate in a single expression.
    private var bodyWithEventHandlers: some View {
        bodyWithPickerHandlers
        // Athletic 클립 변경 시 미리보기 플레이어 리셋 + SwiftData 저장
        .onChange(of: athleticVM.athleticClipRecipes.count) { _, _ in
            athleticVM.athleticVideoState.invalidate()
            saveAthleticClipRecipes()
        }
        // OneLiner 설정 변경 시 기존 export 무효화 + 영상 미리보기 즉시 재빌드
        // buildPreview() 내부에서 invalidate()를 호출하므로 별도 invalidate 불필요.
        // buildGeneration 메커니즘으로 마지막 변경만 최종 반영됨.
        .onChange(of: oneLinerVM.oneLinerText) { _, _ in
            guard isOneLiner, template == .video || template == .slide else { return }
            exportedVideoFile = nil
            if template == .video { buildPreview() }
        }
        .onChange(of: oneLinerVM.oneLinerPosition) { _, _ in
            guard isOneLiner, template == .video || template == .slide else { return }
            exportedVideoFile = nil
            if template == .video { buildPreview() }
        }
        .onChange(of: oneLinerVM.oneLinerColor) { _, _ in
            guard isOneLiner, template == .video || template == .slide else { return }
            exportedVideoFile = nil
            if template == .video { buildPreview() }
        }
        .onChange(of: oneLinerVM.oneLinerFont) { _, _ in
            guard isOneLiner, template == .video || template == .slide else { return }
            exportedVideoFile = nil
            if template == .video { buildPreview() }
        }
        .onChange(of: oneLinerVM.oneLinerClipRecipes.count) { _, _ in
            guard isOneLiner else { return }
            previewPlayer.invalidate()
            exportedVideoFile = nil
            if template == .video {
                if let thumb = oneLinerVM.oneLinerClipRecipes.first?.thumbnail {
                    videoPreviewImage = thumb
                }
                if !oneLinerVM.oneLinerClipRecipes.isEmpty {
                    buildPreview()
                }
            }
        }
        .onChange(of: stampVM.storyTemplate) { _, newTpl in
            guard isStamp else { return }
            if newTpl.requires.contains(.location) { fetchStampPlaceIfNeeded() }
            if newTpl.requires.contains(.route)    { fetchStampMapIfNeeded() }
        }
        .onChange(of: stampVM.clipRecipes.count) { _, _ in
            guard isStamp else { return }
            // 클립 수 변경 시 항상 저장 — template이 .video가 아닌 상태에서 클립을 추가해도 유지.
            saveStampConfig()
            guard template == .video else { return }
            previewPlayer.invalidate()
            exportedVideoFile = nil
            Task { await loadStampVideoPreview(data: stampPreviewData) }
        }
        .onChange(of: stampVM.muteAudio) { _, newVal in
            guard isStamp, template == .video else { return }
            previewPlayer.setMuted(newVal)
            saveStampConfig()
        }
        // OneLiner 카드의 사진이 바뀌면 새 사진의 entry 로드.
        // 저장은 Button 액션에서 cardPhotoIndex 변경 전에 처리.
        // Button 액션이 loadOneLinerSettingsFor를 먼저 호출하지만, 포커스 해제 타이밍에 따라
        // onChange도 발화할 수 있어 방어적으로 유지 — 중복 로드는 무해함.
        .onChange(of: cardPhotoIndex) { old, new in
            if isOneLiner, template == .photo, old[.oneLiner] != new[.oneLiner] {
                loadOneLinerSettingsFor(photoIndex: new[.oneLiner] ?? 0)
            }
            if isStamp, old[.stamp] != new[.stamp] {
                let idx = new[.stamp] ?? 0
                // selectedClipIndex가 photo 인덱스와 일치해야 currentConfig(get/set)가
                // 올바른 photoConfigs[idx]를 읽고 쓴다. story·slide 모두 동기화.
                stampVM.selectedClipIndex = idx
                if template == .photo { stampVM.storyCropOffsetX = stampVM.storyCropOffsets[idx] ?? 0.5 }
                // slide: 선택 사진의 시작 시각(+0.5s)으로 이동해 해당 사진이 미리보기에 보이게 함
                if template == .slide, previewPlayer.isReady {
                    let t = Double(idx) * PhotoSlideComposition.placeableSlideDuration + 0.5
                    previewPlayer.player?.seek(to: CMTimeMakeWithSeconds(t, preferredTimescale: 600),
                                               completionHandler: { _ in })
                }
            }
        }
    }

    // Placeable story overlay state 변경 → UserDefaults 저장. body에서 분리해 타입 체커 부담 경감.
    private var bodyWithStoryOverlayHandlers: some View {
        bodyWithEventHandlers
            .onChange(of: placeableVM.placeableStoryTexts)    { _, _ in savePlaceableStoryOverlay(); if isPlaceable { exportedVideoFile = nil }; Task { await renderCard(showSpinner: false) } }
            .onChange(of: placeableVM.placeableStoryFont)     { _, _ in savePlaceableStoryOverlay(); applyStyleToVideoClips(); if isPlaceable, template == .video { savePlaceableVideoClips() }; rebuildPlaceableSlidePreview(); if isPlaceable { exportedVideoFile = nil; if template == .video { Task { await loadPlaceablePreview() } } } }
            .onChange(of: placeableVM.placeableStoryColor)    { _, _ in savePlaceableStoryOverlay(); applyStyleToVideoClips(); if isPlaceable, template == .video { savePlaceableVideoClips() }; rebuildPlaceableSlidePreview(); if isPlaceable { exportedVideoFile = nil; if template == .video { Task { await loadPlaceablePreview() } } } }
            .onChange(of: placeableVM.placeableStorySize)     { _, _ in savePlaceableStoryOverlay(); applyStyleToVideoClips(); if isPlaceable, template == .video { savePlaceableVideoClips() }; rebuildPlaceableSlidePreview(); if isPlaceable { exportedVideoFile = nil; if template == .video { Task { await loadPlaceablePreview() } } } }
            .onChange(of: placeableVM.placeableStoryPosition) { _, _ in savePlaceableStoryOverlay(); applyStyleToVideoClips(); if isPlaceable, template == .video { savePlaceableVideoClips() }; rebuildPlaceableSlidePreview(); if isPlaceable { exportedVideoFile = nil; if template == .video { Task { await loadPlaceablePreview() } } } }
            .onChange(of: placeableVM.placeableStoryHasBorder)   { _, _ in savePlaceableStoryOverlay(); applyStyleToVideoClips(); if isPlaceable, template == .video { savePlaceableVideoClips() }; rebuildPlaceableSlidePreview(); if isPlaceable { exportedVideoFile = nil; if template == .video { Task { await loadPlaceablePreview() } } } }
            .onChange(of: placeableVM.placeableMuteAudio) { _, newVal in
                guard isPlaceable, template == .video else { return }
                // 토글 즉시 live player에 반영 — 재빌드 불필요
                previewPlayer.setMuted(newVal)
                savePlaceableVideoClips()
            }
            .onChange(of: placeableVM.placeableVideoTexts) { _, newTexts in
                // Stamp의 onChange(of: stampVM.photoConfigs) 패턴: 텍스트 변경 시 clip recipes에 동기화 → 저장
                guard template == .video else { return }
                for (idx, text) in newTexts {
                    guard placeableVM.placeableClipRecipes.indices.contains(idx) else { continue }
                    placeableVM.placeableClipRecipes[idx].lines = text.isEmpty ? [] : [text]
                }
                // ClipRecipe 기본 sizeLevel = .large 이므로, 텍스트 동기화 후 전역 스타일 즉시 적용
                applyStyleToVideoClips()
                placeableVM.placeableVideoTextDirty = true
                savePlaceableVideoClips()
                if isPlaceable { exportedVideoFile = nil }
            }
            .onChange(of: placeableVM.placeableClipRecipes.count) { _, _ in
                exportedVideoFile = nil
                applyAnimationToVideoClips()
                applyStyleToVideoClips()
                savePlaceableVideoClips()
                guard isPlaceable, template == .video else { return }
                Task { await loadPlaceablePreview() }
            }
            .onChange(of: storyPhotos.count) { _, _ in
                guard isPlaceable else { return }
                exportedVideoFile = nil
                // previewPlayer는 영상·슬라이드 공유 — 슬라이드 템플릿일 때만 빌드.
                guard template == .slide else { return }
                let photos = storyPhotos
                if !photos.isEmpty {
                    Task {
                        let overlayIsTop = placeableVM.placeableLayout == .horizontal
                            ? placeableVM.placeableHorizTextRow == .top
                            : placeableVM.placeableMetricsPosition.isTop
                        let overlay = makePlaceableDataOverlay(fullHeight: overlayIsTop)
                        let recipes = makePlaceableSlideRecipes(for: photos)
                        await previewPlayer.buildForPhotoSlides(
                            photos: photos, recipes: recipes,
                            dataOverlayImage: overlay,
                            dataOverlayIsTop: overlayIsTop,
                            fastBase: true)
                    }
                } else {
                    previewPlayer.invalidate()
                }
            }
            .onChange(of: placeableVM.placeableSlideAppearance) { _, _ in
                guard isPlaceable, template == .slide else { return }
                exportedVideoFile = nil
                let photos = storyPhotos
                guard !photos.isEmpty else { return }
                Task {
                    let overlayIsTop = placeableVM.placeableLayout == .horizontal
                        ? placeableVM.placeableHorizTextRow == .top
                        : placeableVM.placeableMetricsPosition.isTop
                    let overlay = makePlaceableDataOverlay(fullHeight: overlayIsTop)
                    let recipes = makePlaceableSlideRecipes(for: photos)
                    await previewPlayer.buildForPhotoSlides(
                        photos: photos, recipes: recipes,
                        dataOverlayImage: overlay,
                        dataOverlayIsTop: overlayIsTop,
                        fastBase: true)
                }
            }
            .onChange(of: placeableVM.selectedPlaceableClipIndex) { _, _ in
                // 단일 클립만: 선택 변경 → 해당 클립 로드. 멀티클립은 합쳐진 미리보기 유지.
                guard isPlaceable, template == .video, placeableVM.placeableClipRecipes.count <= 1 else { return }
                Task { await loadPlaceablePreview() }
            }
    }

    // Stamp 속성 변경 → UserDefaults 저장. bodyWithStoryOverlayHandlers 에서 분리(타입 체커 한계).
    // 애니메이션은 StampPhotoConfig 안에 포함되므로 photoConfigs/baseConfig 감시만으로 충분.
    private var bodyWithStampHandlers: some View {
        bodyWithStoryOverlayHandlers
            .onChange(of: stampVM.baseConfig)   { _, _ in
                guard isStamp else { return }
                saveStampConfig()
                if template == .video || template == .routeVideo { exportedVideoFile = nil }
                if template == .photo {
                    storyShareImages = []
                    previewImage = nil
                    // ImageRenderer 레이아웃 엔진을 새 position으로 reprime.
                    // renderCard()가 이전 position으로 파이프라인을 초기화한 뒤 position이 바뀌면,
                    // 다음 내보내기의 첫 번째 render가 stale 레이아웃을 반환하는 버그를 방지.
                    // photo: nil — 배경 없이 레이아웃만 초기화(빠름).
                    let cfg = stampVM.baseConfig
                    let wuView = StampStoryRenderView(
                        photo: nil, data: stampPreviewData, vm: stampVM,
                        cropOffsetX: stampVM.storyCropOffsetX,
                        configOverride: cfg).frame(width: 300, height: 375)
                    let wu = ImageRenderer(content: wuView)
                    wu.scale = 1
                    _ = wu.uiImage
                    _ = wu.uiImage
                }
            }
            .onChange(of: stampVM.photoConfigs) { _, _ in
                guard isStamp else { return }
                saveStampConfig()
                if template == .video || template == .routeVideo { exportedVideoFile = nil }
                if template == .photo {
                    storyShareImages = []
                    previewImage = nil
                }
            }
            .onChange(of: storyPhotos.count) { _, _ in
                guard isStamp else { return }
                exportedVideoFile = nil
                if template == .slide {
                    let data = stampPreviewData
                    Task { await loadStampSlidePreview(data: data) }
                } else {
                    // 스토리/영상 모드에서 사진이 바뀌면 프리빌드된 슬라이드 플레이어 무효화
                    previewPlayer.invalidate()
                }
            }
    }

    private var bodyWithSlideHandlers: some View {
        bodyWithStampHandlers
            .onChange(of: placeableVM.slideDecorEffect) { _, _ in
                guard isPlaceable, template == .slide, placeableVM.placeableSlideAppearance == .fade else { return }
                exportedVideoFile = nil
                let photos = storyPhotos
                guard !photos.isEmpty else { return }
                Task {
                    let overlayIsTop = placeableVM.placeableLayout == .horizontal
                        ? placeableVM.placeableHorizTextRow == .top
                        : placeableVM.placeableMetricsPosition.isTop
                    let overlay = makePlaceableDataOverlay(fullHeight: overlayIsTop)
                    let recipes = makePlaceableSlideRecipes(for: photos)
                    await previewPlayer.buildForPhotoSlides(
                        photos: photos, recipes: recipes,
                        dataOverlayImage: overlay,
                        dataOverlayIsTop: overlayIsTop,
                        fastBase: true)
                }
            }
            .onChange(of: placeableVM.slideFlyDirection) { _, _ in
                guard isPlaceable, template == .slide, placeableVM.placeableSlideAppearance == .flyIn else { return }
                exportedVideoFile = nil
                let photos = storyPhotos
                guard !photos.isEmpty else { return }
                Task {
                    let overlayIsTop = placeableVM.placeableLayout == .horizontal
                        ? placeableVM.placeableHorizTextRow == .top
                        : placeableVM.placeableMetricsPosition.isTop
                    let overlay = makePlaceableDataOverlay(fullHeight: overlayIsTop)
                    let recipes = makePlaceableSlideRecipes(for: photos)
                    await previewPlayer.buildForPhotoSlides(
                        photos: photos, recipes: recipes,
                        dataOverlayImage: overlay,
                        dataOverlayIsTop: overlayIsTop,
                        fastBase: true)
                }
            }
    }

    // Cross-card text propagation: 문구 입력 시 다른 카드의 빈 슬롯에 전이
    private var bodyWithTextPropHandlers: some View {
        bodyWithClipPropHandlers
            .onChange(of: oneLinerVM.oneLinerText) { _, new in
                guard !new.isEmpty else { return }
                propagateFirstText(new)
            }
            .onChange(of: placeableVM.placeableStoryTexts) { _, new in
                guard let first = new[0], !first.isEmpty else { return }
                propagateFirstText(first)
            }
            .onChange(of: stampVM.baseConfig) { _, new in
                guard !new.text.isEmpty else { return }
                propagateFirstText(new.text)
            }
    }

    // Cross-card clip propagation: 추가·삭제 모두 전파 (1/2)
    // ClipRecipe 는 UIImage? / AVAsset? 을 포함하므로 Equatable 불가 → .count(Int) 감시
    // count=0(전체 삭제)도 포함 — propagateClips 내부에서 빈 배열을 모두에 동기화
    private var bodyWithClipPropHandlers: some View {
        bodyWithClipPropHandlers2
            .onChange(of: oneLinerVM.oneLinerClipRecipes.count) { _, _ in
                propagateClips(oneLinerVM.oneLinerClipRecipes)
            }
            .onChange(of: placeableVM.placeableClipRecipes.count) { _, _ in
                propagateClips(placeableVM.placeableClipRecipes)
            }
    }

    // Cross-card clip propagation (2/2)
    private var bodyWithClipPropHandlers2: some View {
        bodyWithVideoAnimHandlers
            .onChange(of: athleticVM.athleticClipRecipes.count) { _, _ in
                propagateClips(athleticVM.athleticClipRecipes)
            }
            .onChange(of: stampVM.clipRecipes.count) { _, _ in
                propagateClips(stampVM.clipRecipes)
            }
    }

    private var bodyWithVideoAnimHandlers: some View {
        bodyWithSlideHandlers
            .onChange(of: placeableVM.placeableSlideAppearance) { _, _ in
                guard isPlaceable, template == .video else { return }
                exportedVideoFile = nil
                applyAnimationToVideoClips()
                Task { await loadPlaceablePreview() }
            }
            .onChange(of: placeableVM.slideDecorEffect) { _, _ in
                guard isPlaceable, template == .video, placeableVM.placeableSlideAppearance == .fade else { return }
                exportedVideoFile = nil
                applyAnimationToVideoClips()
                Task { await loadPlaceablePreview() }
            }
            .onChange(of: placeableVM.slideFlyDirection) { _, _ in
                guard isPlaceable, template == .video, placeableVM.placeableSlideAppearance == .flyIn else { return }
                exportedVideoFile = nil
                applyAnimationToVideoClips()
                Task { await loadPlaceablePreview() }
            }
    }

    // MARK: - Cross-card first text propagation
    // 카드 A에서 입력된 첫 번째 문구를 다른 카드의 비어있는 첫 번째 슬롯에만 채움 (덮어쓰기 금지).

    func propagateFirstText(_ text: String) {
        guard !text.isEmpty else { return }
        // OneLiner story/slide 텍스트
        if oneLinerVM.oneLinerText.isEmpty { oneLinerVM.oneLinerText = text }
        // Placeable: 첫 사진 텍스트
        if (placeableVM.placeableStoryTexts[0] ?? "").isEmpty { placeableVM.placeableStoryTexts[0] = text }
        // Stamp: 기본 텍스트
        if stampVM.baseConfig.text.isEmpty { stampVM.baseConfig.text = text }
        // OneLiner 영상 클립 — 빈 첫 번째 줄만
        for i in oneLinerVM.oneLinerClipRecipes.indices
            where (oneLinerVM.oneLinerClipRecipes[i].lines.first ?? "").isEmpty {
            oneLinerVM.oneLinerClipRecipes[i].lines = [text]
        }
        // Placeable 영상 클립 — 빈 첫 번째 줄만
        for i in placeableVM.placeableClipRecipes.indices
            where (placeableVM.placeableClipRecipes[i].lines.first ?? "").isEmpty {
            placeableVM.placeableClipRecipes[i].lines = [text]
        }
        // Athletic 영상 클립 — 빈 첫 번째 줄만
        for i in athleticVM.athleticClipRecipes.indices
            where (athleticVM.athleticClipRecipes[i].lines.first ?? "").isEmpty {
            athleticVM.athleticClipRecipes[i].lines = [text]
        }
    }

    // MARK: - Cross-card clip propagation
    // 클립 식별자(assetID / clipVideoRef) 기준으로 순서·개수가 다른 카드는 항상 덮어쓰기.
    // 빈 배열(전체 삭제)도 전파 — 어느 카드에서 삭제해도 모든 카드에 반영됨.
    // "같은 러닝 공유카드에서 선택한 클립은 모두 동일해야 한다"는 원칙을 보장.
    func propagateClips(_ recipes: [ClipRecipe]) {
        // 클립 식별자 배열 비교 (순서 포함, 빈 배열도 허용)
        func ids(_ rs: [ClipRecipe]) -> [String] {
            rs.map { $0.assetIdentifier ?? $0.clipVideoRef ?? $0.storedPhotoRef ?? $0.url.lastPathComponent }
        }
        let srcIds = ids(recipes)

        // OneLiner: 기존 클립별 문구(lines)를 assetID 기준으로 보존.
        // 소스 클립(Placeable 등)의 card-specific 문구를 덮어쓰지 않는다.
        if ids(oneLinerVM.oneLinerClipRecipes) != srcIds {
            let existingLinesByID = Dictionary(uniqueKeysWithValues:
                oneLinerVM.oneLinerClipRecipes.compactMap { r -> (String, [String])? in
                    let key = r.assetIdentifier ?? r.clipVideoRef ?? r.storedPhotoRef ?? r.url.lastPathComponent
                    return key.isEmpty ? nil : (key, r.lines)
                })
            var updated = recipes
            for i in updated.indices {
                let key = updated[i].assetIdentifier ?? updated[i].clipVideoRef ?? updated[i].storedPhotoRef ?? updated[i].url.lastPathComponent
                updated[i].lines = existingLinesByID[key] ?? []
            }
            oneLinerVM.oneLinerClipRecipes = updated
        }
        // Placeable: placeableVideoTexts가 정식 텍스트 소스 — 소스 클립의 lines로 덮어쓰면 안 됨.
        // 소스 클립(OneLiner 등)의 card-specific 문구가 placeableVideoTexts를 오염시키는 버그 방지.
        // clip.lines는 항상 placeableVideoTexts에서 복원.
        if ids(placeableVM.placeableClipRecipes) != srcIds {
            placeableVM.placeableClipRecipes = recipes
            for (i, text) in placeableVM.placeableVideoTexts where !text.isEmpty {
                guard placeableVM.placeableClipRecipes.indices.contains(i) else { continue }
                if placeableVM.placeableClipRecipes[i].lines.isEmpty {
                    placeableVM.placeableClipRecipes[i].lines = [text]
                } else {
                    placeableVM.placeableClipRecipes[i].lines[0] = text
                }
            }
            // 외부 소스에서 덮어쓴 후 Placeable 전용 스타일(sizeLevel·font·color·border)을 즉시 복원
            applyStyleToVideoClips()
        }
        if ids(athleticVM.athleticClipRecipes)   != srcIds { athleticVM.athleticClipRecipes   = recipes }
        if ids(stampVM.clipRecipes)              != srcIds { stampVM.clipRecipes              = recipes }
    }

    var body: some View {
        bodyWithTextPropHandlers
        .onAppear {
            guard !didResetMediaLogo else { return }
            didResetMediaLogo = true
            MediaLogoSetting.shared.resetForNewSheet()
        }
        .onChange(of: placeableVM.placeableMetricsPosition) { _, _ in
            guard isPlaceable else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: placeableVM.placeableAccent) { _, _ in
            guard isPlaceable else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: placeableVM.placeableSize) { _, _ in
            guard isPlaceable else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: placeableVM.placeableLayout) { _, _ in
            guard isPlaceable else { return }
            Task { await renderCard(showSpinner: false) }
        }
        .onChange(of: oneLinerVM.oneLinerVideoTitle) { _, _ in
            if isOneLiner { exportedVideoFile = nil }
            if isOneLiner, template == .video { buildPreview() } else { previewPlayer.invalidate() }
            if isOneLiner, template == .slide { saveOneLinerClipRecipes() }
        }
        .onChange(of: oneLinerVM.oneLinerTitleStyle) { _, _ in
            if isOneLiner { exportedVideoFile = nil }
            if isOneLiner, template == .video { buildPreview() } else { previewPlayer.invalidate() }
        }
        .interactiveDismissDisabled(previewPlayer.isBuilding)
        .task(id: routePreviewPlayCount) {
            guard routePreviewPlayCount > 0 else { return }
            await animateRouteVideoPreview()
        }
        .alert(AppLanguage.shared.s("이미 내보낸 영상이에요", "Already exported video"),
               isPresented: $showExportedVideoWarning) {
            Button(AppLanguage.shared.s("확인", "OK"), role: .cancel) { }
        } message: {
            Text(AppLanguage.shared.s(
                "원본 영상을 선택해 주세요. 내보낸 영상을 다시 선택하면 내용이 두 번 나타납니다.",
                "Please select the original video. Selecting an exported video again will duplicate the overlay."
            ))
        }
        .alert(AppLanguage.shared.s("내보내기 실패", "Export Failed"),
               isPresented: $showVideoExportError) {
            Button(AppLanguage.shared.s("확인", "OK"), role: .cancel) { showVideoExportError = false }
        } message: {
            Text(videoExportError ?? "")
        }
    }

    private func animateRouteVideoPreview() async {
        guard template == .routeVideo else { return }
        // 이전 텍스트 지연 태스크 취소
        previewTextDelayTask?.cancel()
        previewTextDelayTask = nil
        routePreviewProgress = 0.0
        previewStampVisible = false
        previewTextVisible = false
        var stampShown = false
        while !Task.isCancelled, routePreviewProgress <= 1.0 {
            try? await Task.sleep(nanoseconds: 100_000_000)  // 10Hz
            routePreviewProgress += 2.0 / 60.0
            // export stampStart=0.5s / 15s ≈ 3.3% → preview 5% 시점에 스탬프 등장
            if routePreviewProgress >= 0.05, !stampShown {
                stampShown = true
                withAnimation(stampPreviewAnimation(for: stampVM.stampEntranceMode)) {
                    previewStampVisible = true
                }
                // 스탬프 애니메이션 완료 후 문구 등장 (병렬 태스크)
                if !stampVM.stampText.isEmpty {
                    let delay = stampPreviewAnimDuration(for: stampVM.stampEntranceMode)
                    let textMode = stampVM.stampTextEntranceMode
                    previewTextDelayTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        withAnimation(stampPreviewAnimation(for: textMode)) {
                            previewTextVisible = true
                        }
                    }
                }
            }
        }
        if !Task.isCancelled { routePreviewProgress = 1.0 }
        isRoutePreviewPlaying = false
    }

    private func stampPreviewAnimation(for mode: StampEntranceMode) -> Animation {
        switch mode {
        case .none:  return .linear(duration: 0.01)
        case .fade:  return .easeIn(duration: 0.5)
        case .stamp: return .spring(response: 0.4, dampingFraction: 0.6)
        case .flyIn: return .easeOut(duration: 0.45)
        }
    }

    private func stampPreviewAnimDuration(for mode: StampEntranceMode) -> Double {
        switch mode {
        case .none:  return 0.05
        case .fade:  return 0.5
        case .stamp: return 0.6   // spring response=0.4 + damping settle time
        case .flyIn: return 0.45
        }
    }

    private func stampPreviewFlyOffset(for direction: FlyInDirection, w: CGFloat, h: CGFloat) -> CGSize {
        switch direction {
        case .leading:  return CGSize(width: -w, height: 0)
        case .trailing: return CGSize(width:  w, height: 0)
        case .bottom:   return CGSize(width:  0, height: h)
        }
    }

    // MARK: - Event handler helpers (extracted to keep body type-check budget manageable)

    private func onPickerItemsChanged(_ newItems: [PhotosPickerItem]) {
        photoOffset = .zero
        photoOffsets = [:]
        Task {
            guard !newItems.isEmpty else { return }
            var newImages: [UIImage] = []
            var newItemIDs: [String] = []
            for item in newItems {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    newImages.append(image)
                    // Prefer PHAsset localIdentifier if available; else generate a stable UUID
                    newItemIDs.append(item.itemIdentifier ?? UUID().uuidString)
                }
            }
            guard !newImages.isEmpty else { return }
            let existing = allPickedPhotos.isEmpty ? storyPhotos : allPickedPhotos
            let merged = Array((existing + newImages).prefix(5))
            selectedPhoto = merged[0]
            allPickedPhotos = merged
            // Extend oneLinerVM.storyPhotoUUIDs: preserve existing, append new
            let existingUUIDs = oneLinerVM.storyPhotoUUIDs.isEmpty
                ? (story?.sortedPhotoUUIDs ?? (0..<existing.count).map { _ in UUID().uuidString })
                : oneLinerVM.storyPhotoUUIDs
            let mergedUUIDs = Array((existingUUIDs + newItemIDs).prefix(5))
            oneLinerVM.storyPhotoUUIDs = mergedUUIDs
            persistStoryPhotos(merged, uuids: mergedUUIDs)
            let newIdx = min(existing.count, merged.count - 1)
            for c in ShareCard.photoLinked { cardPhotoIndex[c] = newIdx }
            if template == .slide { previewPlayer.invalidate() }
            await renderCard()
        }
    }

    private func onVideoPickerItemChanged(_ newItem: PhotosPickerItem?) {
        Task {
            guard let item = newItem,
                  let result = try? await item.loadTransferable(type: VideoPickerResult.self)
            else { return }

            // Block if this video was already exported by MIMORunning — re-using it
            // as a source would bake a second overlay on top of the first.
            if isOneLiner, await VideoExportService.isMIMOOneLinerExport(url: result.url) {
                showExportedVideoWarning = true
                videoPickerItem = nil
                return
            }

            sourceVideoURL = result.url

            // OneLiner 영상: 영상 길이에서 슬롯 수 자동 계산 (~3.5초/슬롯, 최소 2, 최대 20)
            if isOneLiner {
                let dur = (try? await AVURLAsset(url: result.url).load(.duration).seconds) ?? 7.0
                let count = max(2, min(20, Int(ceil(dur / 3.5))))
                let existing = oneLinerVM.oneLinerVideoSlotTexts
                oneLinerVM.oneLinerVideoSlotCount = count
                oneLinerVM.oneLinerVideoSlotTexts = (0..<count).map { i in
                    i < existing.count ? existing[i] : ""
                }
            }

            // PHAsset ID가 확정된 후 해당 영상의 저장된 OneLiner 설정 로드
            if isOneLiner { loadOneLinerSettings() }
            videoPreviewImage = await VideoExportService.firstFrame(of: result.url)
            // Placeable 영상: 프리뷰는 placeableVM.placeableClipRecipes.count onChange → loadPlaceablePreview() 에서 처리
            // 자동 합성 안 함 — 사용자가 미리보기로 배치 확인 후 직접 합성 버튼 탭
        }
    }

    private func onStoryClipEditDismiss() {
        saveStoryClipEdits(oneLinerVM.storyClipEditRecipes, isSlide: oneLinerVM.storyClipEditIsSlide)
        exportedVideoFile = nil
        for c in ShareCard.photoLinked { cardPhotoIndex[c] = oneLinerVM.storyClipEditIndex }
    }

    private func onAthleticPickerItemsChanged(_ newItems: [PhotosPickerItem]) {
        guard !newItems.isEmpty else { return }
        Task {
            var isFirst = true
            for item in newItems {
                guard let result = try? await item.loadTransferable(type: VideoPickerResult.self) else { continue }
                let url = result.url
                let dur = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 30.0
                let thumb = await VideoExportService.firstFrame(of: url)
                var r = ClipRecipe(url: url, fullDuration: dur, thumbnail: thumb)
                r.trimEnd = min(dur, VideoExportService.trimDuration)
                r.assetIdentifier = item.itemIdentifier  // PHAsset ID — 재진입 시 복원용
                athleticVM.athleticClipRecipes.append(r)
                // 첫 번째 클립 처리 직후 프리뷰 즉시 업데이트 (전체 루프 끝까지 기다리지 않음)
                if isFirst {
                    isFirst = false
                    if let t = thumb { videoPreviewImage = t }
                    sourceVideoURL = url
                    if template != .video { template = .video }
                }
            }
            athleticVM.athleticPickerItems = []
            // 프리뷰가 아직 없으면 레시피 첫 항목 썸네일로 보완
            if videoPreviewImage == nil {
                videoPreviewImage = athleticVM.athleticClipRecipes.first?.thumbnail
                sourceVideoURL    = athleticVM.athleticClipRecipes.first?.url
                if template != .video { template = .video }
            }
            exportedVideoFile = nil
            athleticVM.athleticVideoState.invalidate()
            saveAthleticClipRecipes()
        }
    }

    @MainActor
    private func buildAthleticPreview() async {
        guard !athleticVM.athleticClipRecipes.isEmpty, !athleticVM.athleticPreviewBuilding else { return }
        athleticVM.athleticPreviewBuilding = true
        defer { athleticVM.athleticPreviewBuilding = false }
        athleticVM.athleticVideoState.invalidate()
        if let result = try? await VideoExportService.buildConcatenatedPreviewItem(recipes: athleticVM.athleticClipRecipes) {
            athleticVM.athleticVideoState.loadPlayerItem(result.playerItem, duration: result.duration)
            athleticVM.athleticVideoState.player?.isMuted = athleticVM.athleticMuted
            athleticVM.athleticVideoState.togglePlayPause()
        }
    }

    @MainActor
    private func buildAthleticSlidePreview() async {
        guard !storyPhotos.isEmpty, !athleticVM.athleticPreviewBuilding else { return }
        athleticVM.athleticPreviewBuilding = true
        defer { athleticVM.athleticPreviewBuilding = false }

        let overlayImage: UIImage?
        let exportH: CGFloat = 384
        let exportInset = exportH * 0.05
        let km = activity.distance / 1000
        let distStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
        let overlayView = VideoOverlayCard(
            distanceKm: distStr,
            date: activity.date,
            metrics: Array(enabledMetricItems.prefix(6)),
            raceName: activeRaceName,
            chartPanel: cardPanel,
            chartSplits: detail?.splits ?? [],
            chartHRSamples: shareHRSamples,
            chartHRZones: detail?.hrZones ?? [],
            chartWorkoutSeries: shareWorkoutSeries,
            chartIntervalSegments: detail?.intervalSegments ?? [],
            weather: condition?.weather,
            shoeName: displayShoeName,
            summaryLines: cardSummaryLines,
            scale: 216.0 / 300.0,
            topInset: exportInset,
            bottomInset: 14
        )
        .frame(width: 216, height: exportH)
        .preferredColorScheme(.dark)
        let renderer = ImageRenderer(content: overlayView)
        renderer.scale = 5.0
        overlayImage = renderer.uiImage
        guard let overlayImage else { return }

        let offsets = storyPhotos.indices.map { i in athleticSlideCropOffsets[i] ?? 0.5 }
        guard let previewURL = try? await PhotoSlideComposition.exportAthleticSlide(
            photos: storyPhotos, cropOffsets: offsets, overlayImage: overlayImage,
            clipDuration: PhotoSlideComposition.placeableSlideDuration) else { return }

        athleticVM.athleticVideoState.invalidate()
        let asset = AVURLAsset(url: previewURL)
        let duration = (try? await asset.load(.duration))?.seconds
            ?? Double(storyPhotos.count) * PhotoSlideComposition.placeableSlideDuration
        let item = AVPlayerItem(asset: asset)
        athleticVM.athleticVideoState.loadPlayerItem(item, duration: duration)
        athleticVM.athleticVideoState.player?.isMuted = athleticVM.athleticMuted
        athleticVM.athleticVideoState.togglePlayPause()
    }

    private func onTemplateChanged() {
        routeVideoFile = nil
        isRoutePreviewPlaying = false
        routePreviewProgress = 1.0
        previewStampVisible = true
        previewTextVisible = true
        // Stamp 스토리 모드 진입 시 selectedClipIndex를 사진 인덱스와 동기화.
        // 영상 모드에서 non-0 클립이 선택된 채로 스토리로 전환하면 위치·템플릿 변경이
        // photoConfigs[selectedClipIndex]에 저장되지만 내보내기는 photoConfig(at: 0)을 읽어 값이 엇갈림.
        if isStamp, template == .photo {
            stampVM.selectedClipIndex = cardPhotoIndex[.stamp] ?? 0
        }
        // 템플릿 전환 시 이전 템플릿의 내보내기 결과를 항상 초기화
        // videoPreviewImage는 .video 진입 시 유지 (영상 클립 썸네일 보존)
        if isPlaceable {
            exportedVideoFile = nil
            if template != .video { videoPreviewImage = nil }
        } else {
            exportedVideoFile = nil
        }
        // Stop preview when leaving clip modes (story has no preview)
        if isOneLiner, template == .photo { previewPlayer.pause() }
        // Athletic: .video ↔ .slide 전환 시 videoState 초기화
        // (이전 템플릿 콘텐츠가 새 템플릿 프리뷰 영역에 잔존하는 것을 방지)
        if !isOneLiner, !isPlaceable, !isStamp, template == .video || template == .slide {
            athleticVM.athleticVideoState.invalidate()
        }
        // Placeable 영상 진입 시 문구 탭 기본 선택, 벗어날 때 플레이어 정지
        if isPlaceable, template == .video {
            placeableVM.placeableStoryTabIsText = true
            let hadClips = !placeableVM.placeableClipRecipes.isEmpty
            loadPlaceableVideoClips()
            // 클립이 이미 로드된 상태였으면 count 변화 없음 → onChange 미발화 → 수동 재빌드
            if hadClips { Task { await loadPlaceablePreview() } }
        }
        if isPlaceable, template != .video { previewPlayer.pause() }
        // Athletic 영상 템플릿 진입 시 레시피 복원 — sourceVideoURL이 있는데 recipes가 비어 있으면 재구성
        if !isPlaceable, !isOneLiner, template == .video,
           let url = sourceVideoURL, athleticVM.athleticClipRecipes.isEmpty {
            Task {
                let dur = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 30.0
                var r = ClipRecipe(url: url, fullDuration: dur, thumbnail: videoPreviewImage)
                r.trimEnd = min(dur, VideoExportService.trimDuration)
                athleticVM.athleticClipRecipes = [r]
            }
        }
        // Placeable 슬라이드: 즉시 전환 — 이전 player 초기화만, 빌드는 ▶ 탭 시 시작.
        // (Athletic 패턴과 동일: 탭 전환 시 사진 즉시 표시, 스피너 없음)
        if isPlaceable, template == .slide { previewPlayer.invalidate() }
        if isPlaceable, template != .slide { previewPlayer.pause() }
        // Stamp 영상: 진입 시 항상 초기화 후 재빌드.
        // [필수] 슬라이드→영상 전환 시 슬라이드 player가 previewPlayer에 잔존하면
        // stampVideoPreviewSection이 isReady=true를 감지해 슬라이드 내용을 영상 미리보기로 표시함.
        // 영상 탭 진입마다 invalidate → 올바른 영상 클립으로 재빌드.
        if isStamp, template == .video {
            previewPlayer.invalidate()
            if !stampVM.clipRecipes.isEmpty {
                let data = stampPreviewData
                Task { await loadStampVideoPreview(data: data) }
            }
        }
        // OneLiner 영상: 진입 시 클립이 있으면 프리뷰 빌드.
        // onChange(of: count)는 count가 바뀔 때만 발화 → count 불변 시 buildPreview 미발화 방지.
        if isOneLiner, template == .video, !oneLinerVM.oneLinerClipRecipes.isEmpty {
            buildPreview()
        }
        // OneLiner 슬라이드: 진입 시 영상 플레이어 초기화 — 영상 클립 잔상 방지.
        if isOneLiner, template == .slide { previewPlayer.invalidate() }
        // Stamp 슬라이드: 즉시 전환 — 빌드는 ▶ 탭 또는 카드 진입 시 프리빌드에 위임.
        // 영상 플레이어가 잔존하면 반드시 무효화해 음성 차단. 슬라이드 프리빌드는 유지.
        if isStamp, template == .slide, !previewPlayer.builtForPhotoSlide { previewPlayer.invalidate() }
        if template == .routeVideo, routeSnapshot == nil, !routeCoords.isEmpty {
            Task {
                if let result = try? await RouteVideoExportService.mapSnapshot(coordinates: routeCoords) {
                    routeSnapshot = result.image
                    routeSnapshotPoints = result.points
                }
            }
        }
        Task { await renderCard() }
    }

    private func onCardChanged(_ newCard: ShareCard) {
        // player를 직접 사용하는 카드(Stamp·Placeable·OneLiner)로 이동할 때만 초기화.
        // 같은 카드 복귀(예: Placeable→Athletic→Placeable)는 builtForCard가 같아 초기화 생략 → 영상 유지.
        // OneLiner 한정: 슬라이드↔영상 전환 후 다른 카드 경유 복귀 시 player 컨텐츠가 template과 불일치하면 초기화.
        if [.stamp, .placeable, .oneLiner].contains(newCard) {
            let cardMismatch = previewPlayer.builtForCard != newCard
            let oneLinerContentMismatch = newCard == .oneLiner
                && previewPlayer.builtForCard == .oneLiner
                && (template == .slide) != previewPlayer.builtForPhotoSlide
            if cardMismatch || oneLinerContentMismatch {
                previewPlayer.invalidate()
            }
        }
        // Athletic 진입 시 athleticVideoState 초기화 — 이전 카드의 영상이 오버레이와 겹쳐 보이는 버그 방지.
        if newCard == .athletic {
            athleticVM.athleticVideoState.invalidate()
        }
        routeVideoFile = nil
        exportedVideoFile = nil
        // 새 카드가 현재 템플릿을 지원하지 않으면 그 카드의 기본 템플릿으로 자동 전환.
        if !newCard.supportedTemplates.contains(template) {
            template = newCard.defaultTemplate
        }
        // OneLiner 카드 진입 시 현재 미디어(그라데이션 포함) 저장값 로드 (인라인 편집, 모달 없음)
        if newCard == .oneLiner {
            // 이전 카드(Placeable 등)의 videoPreviewImage가 OneLiner 정적 카드 배경으로 표시되는 것을 방지
            videoPreviewImage = nil
            // 슬라이드 진입: 다른 카드에 있을 때 template이 slide로 바뀌면 syncOneLinerVideoBacking의
            // guard isOneLiner가 스킵되어 oneLinerClipRecipes에 이전 영상 클립이 남을 수 있음 → 명시 정리
            if template == .slide {
                oneLinerVM.oneLinerClipRecipes = []
            }
            loadOneLinerSettings()
            // 클립 순서 동기화: 다른 카드에서 재정렬이 있었을 경우 OneLiner → 전체 반영
            if !oneLinerVM.oneLinerClipRecipes.isEmpty {
                propagateClips(oneLinerVM.oneLinerClipRecipes)
            }
            // 전파된(또는 복원된) 클립 썸네일 → 정적 배경 세팅 + 라이브 프리뷰 빌드
            if template == .video {
                if let thumb = oneLinerVM.oneLinerClipRecipes.first?.thumbnail {
                    videoPreviewImage = thumb
                }
                if !oneLinerVM.oneLinerClipRecipes.isEmpty {
                    buildPreview()
                }
            }
        }
        // Placeable 카드 복귀 시 클립 복원 + 스타일 동기화 + 미리보기 로드
        if newCard == .placeable {
            if template == .video { loadPlaceableVideoClips() }
            // 다른 카드에서 전환 시 applyStyleToVideoClips가 isPlaceable=false로 스킵됐을 수 있으므로 명시 호출
            applyStyleToVideoClips()
            if !placeableVM.placeableClipRecipes.isEmpty {
                if previewPlayer.builtForCard != .placeable {
                    // 다른 카드의 player이거나 초기화된 경우 → Placeable 영상 재빌드
                    Task { await loadPlaceablePreview() }
                } else {
                    // 같은 카드 복귀(예: Athletic 경유) → player 유지, 썸네일만 동기화
                    videoPreviewImage = placeableVM.placeableClipRecipes.first?.thumbnail
                }
            }
        }
        // Stamp 카드 진입 시 — 지명·지도 사전 로드 + 미리보기 재빌드
        if newCard == .stamp {
            // 스토리 모드 진입 시 selectedClipIndex 동기화 (onTemplateChanged와 동일 이유)
            if template == .photo {
                stampVM.selectedClipIndex = cardPhotoIndex[.stamp] ?? 0
            }
            fetchStampPlaceIfNeeded()
            fetchStampMapIfNeeded()
            if template == .photo, !storyPhotos.isEmpty {
                // 스크롤 애니메이션(0.3s) 완료 후 슬라이드 프리뷰를 백그라운드에서 미리 빌드.
                // 카드 전환 중 AVAssetWriter 초기화가 메인스레드를 블로킹하지 않도록 지연 실행.
                let data = stampPreviewData
                Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !previewPlayer.isReady, !previewPlayer.isBuilding else { return }
                    await loadStampSlidePreview(data: data)
                }
            } else if template == .slide, !storyPhotos.isEmpty {
                let data = stampPreviewData
                Task { await loadStampSlidePreview(data: data) }
            } else if template == .slide {
                previewPlayer.invalidate()
            } else if template == .video {
                // 다른 카드(OneLiner 등)가 metricChips·routeCoords 포함 contentLayer를 남긴 채로
                // Stamp 카드로 돌아오면 Athletic 데이터가 표시되는 버그 방지.
                previewPlayer.invalidate()
                if !stampVM.clipRecipes.isEmpty {
                    let data = stampPreviewData
                    Task {
                        await loadStampVideoPreview(data: data)
                        saveStampConfig()
                    }
                }
            }
        }
        // Athletic 카드 진입 시 — 클립이 있으면 영상 모드 복원, 없으면 SwiftData에서 복원
        if newCard == .athletic {
            if !athleticVM.athleticClipRecipes.isEmpty {
                template = .video
            } else {
                Task { await loadAthleticClipRecipes() }
            }
        }
        Task { await renderCard(showSpinner: false) }
    }

    // MARK: - Chart data loading

    private func loadChartData(for panel: CardChartPanel) async {
        guard let mgr = manager else { return }
        shareWorkoutSeries = []
        switch panel {
        case .heartRate:
            shareHRSamples = await mgr.fetchHRTimeSeries(for: activity.id)
        case .cadence:
            shareWorkoutSeries = await mgr.fetchCadenceTimeSeries(for: activity.id)
        case .power:
            shareWorkoutSeries = await mgr.fetchWorkoutTimeSeries(for: activity.id,
                identifier: .runningPower, unit: .watt())
        case .groundContact:
            shareWorkoutSeries = await mgr.fetchWorkoutTimeSeries(for: activity.id,
                identifier: .runningGroundContactTime, unit: .secondUnit(with: .milli))
        case .strideLength:
            shareWorkoutSeries = await mgr.fetchWorkoutTimeSeries(for: activity.id,
                identifier: .runningStrideLength, unit: .meter())
        case .verticalOscillation:
            shareWorkoutSeries = await mgr.fetchWorkoutTimeSeries(for: activity.id,
                identifier: .runningVerticalOscillation, unit: .meterUnit(with: .centi))
        case .elevation:
            shareWorkoutSeries = (detail?.altitudeTimeProfile ?? [])
                .map { (offset: $0.offset, value: $0.altitude) }
        default:
            break
        }
    }

    // MARK: - Card preview

    @ViewBuilder
    private var cardPreview: some View {
        switch template {
        case .record:
            AthleticCard(activity: activity, routeCoordinates: routeCoords,
                          metrics: enabledMetricItems,
                          raceName: activeRaceName,
                          chartPanel: cardPanel,
                          chartSplits: detail?.splits ?? [],
                          chartHRSamples: shareHRSamples,
                          chartHRZones: detail?.hrZones ?? [],
                          chartWorkoutSeries: shareWorkoutSeries,
                          chartIntervalSegments: detail?.intervalSegments ?? [],
                          weather: condition?.weather,
                          shoeName: displayShoeName,
                          photo: nil,
                          summaryLines: cardSummaryLines,
)
        case .photo:
            if let photo = photoFor(.athletic) {
                let s      = max(300 / photo.size.width, 375 / photo.size.height)
                let excess = max(0, photo.size.width * s - 300)
                AthleticCard(activity: activity, routeCoordinates: routeCoords,
                              metrics: enabledMetricItems,
                              raceName: activeRaceName,
                              chartPanel: cardPanel,
                              chartSplits: detail?.splits ?? [],
                              chartHRSamples: shareHRSamples,
                              chartHRZones: detail?.hrZones ?? [],
                              chartWorkoutSeries: shareWorkoutSeries,
                              chartIntervalSegments: detail?.intervalSegments ?? [],
                              weather: condition?.weather,
                              shoeName: displayShoeName,
                              photo: photo,
                              cropOffsetX: athleticCropOffsetX,
                              summaryLines: cardSummaryLines)
                    .gesture(excess > 0 ? DragGesture(minimumDistance: 1)
                        .onChanged { drag in
                            if athleticCropDragBase == nil { athleticCropDragBase = athleticCropOffsetX }
                            guard let base = athleticCropDragBase else { return }
                            athleticCropOffsetX = max(0, min(1,
                                base - drag.translation.width / excess))
                        }
                        .onEnded { _ in
                            athleticCropDragBase = nil
                            saveAthleticCropOffsets()
                        }
                    : nil)
            } else if let s = story {
                StoryShareCardView(activity: activity, routeCoordinates: routeCoords,
                                   story: s,
                                   metrics: enabledMetricItems,
                                   raceName: activeRaceName,
                                   chartPanel: cardPanel,
                                   chartSplits: detail?.splits ?? [],
                                   chartHRSamples: shareHRSamples,
                                   chartHRZones: detail?.hrZones ?? [],
                                   chartWorkoutSeries: shareWorkoutSeries,
                                   chartIntervalSegments: detail?.intervalSegments ?? [],
                                   weather: condition?.weather,
                                   shoeName: displayShoeName,
                                   summaryLines: cardSummaryLines,
)
            } else {
                AthleticCard(activity: activity, routeCoordinates: routeCoords,
                              metrics: enabledMetricItems,
                              raceName: activeRaceName,
                              chartPanel: cardPanel,
                              chartSplits: detail?.splits ?? [],
                              chartHRSamples: shareHRSamples,
                              chartHRZones: detail?.hrZones ?? [],
                              chartWorkoutSeries: shareWorkoutSeries,
                              chartIntervalSegments: detail?.intervalSegments ?? [],
                              weather: condition?.weather,
                              shoeName: displayShoeName,
                              summaryLines: cardSummaryLines)
            }
        case .video, .slide:
            videoPreviewCard
        case .routeVideo:
            routeVideoPreviewCard
        }
    }

    // MARK: - Route video preview card

    @ViewBuilder
    private var routeVideoPreviewCard: some View {
        if routeCoords.isEmpty {
            ZStack {
                Color(hex: "0D0D12")
                VStack(spacing: 10) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.violet)
                    Text(AppLanguage.shared.s("야외 경로 없음", "No outdoor route"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let snap = routeSnapshot {
            // 9:16 콘텐츠를 4:5 컨테이너 안에 필러박스로 표시 (양옆 검은 여백)
            let vidW: CGFloat = 375.0 * 9.0 / 16.0
            let inset: CGFloat = 375.0 * 0.05
            ZStack {
                Color.black
                RouteVideoFrameView(
                    snapshot: snap,
                    snapshotPoints: routeSnapshotPoints,
                    routeProgress: routePreviewProgress,
                    metrics: Array(enabledMetricItems.prefix(6)),
                    raceName: activeRaceName,
                    distanceKm: distanceKmString,
                    duration: activity.formattedDuration,
                    date: activity.date,
                    weather: condition?.weather,
                    shoeName: displayShoeName,
                    chartPanel: cardPanel,
                    chartSplits: detail?.splits ?? [],
                    chartHRSamples: shareHRSamples,
                    chartHRZones: detail?.hrZones ?? [],
                    chartWorkoutSeries: shareWorkoutSeries,
                    chartIntervalSegments: detail?.intervalSegments ?? [],
                    summaryLines: cardSummaryLines,
                    hrSamplesForRoute: shareHRSamples,
                    routeWorkoutDuration: activity.duration,
                    routeZoneBounds: shareZoneBounds,
                    showHRGradient: showHRGradientForRoute,
                    topInset: inset,
                    bottomInset: 14
                )
                .frame(width: vidW, height: 375)
                // 미리보기 재생 버튼 — 재생 중이 아닐 때만 표시
                if !isRoutePreviewPlaying {
                    Button {
                        routePreviewProgress = 0
                        previewStampVisible = false
                        previewTextVisible = false
                        isRoutePreviewPlaying = true
                        routePreviewPlayCount += 1
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.5), radius: 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            ZStack {
                Color(hex: "0D0D12")
                VStack(spacing: 10) {
                    ProgressView().tint(Theme.violet)
                    Text(AppLanguage.shared.s("경로 준비 중…", "Loading route…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Video preview card (9:16 placeholder with overlay preview)

    @ViewBuilder
    private var videoPreviewCard: some View {
        let km = activity.distance / 1000
        let distStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)

        // OneLiner: 카드 1(oneLinerCardPreview)이 contentLayer를 독점 소유.
        // 카드 2는 항상 정적 미리보기 + ▶ 버튼만 표시 → contentLayer 충돌(검은 화면) 방지.
        if isOneLiner, oneLinerHasPhotos {
            // 211×375pt 직접 표시 — Stamp·Placeable 영상과 동일한 좌표계, 스케일 없음.
            oneLinerVideoPreviewCard
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topLeading) {
                    MIMOWordmark(size: 11, onMediaCard: true)
                        .padding(.top, 22)
                        .padding(.leading, 14)
                }
                .overlay {
                    if isExportingVideo {
                        ZStack {
                            Color.black.opacity(0.55)
                            VStack(spacing: 8) {
                                ProgressView().tint(.white).scaleEffect(1.2)
                                Text(AppLanguage.shared.s("합성 중...", "Processing..."))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else if previewPlayer.isBuilding {
                        ProgressView().tint(.white)
                            .padding(14)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                    } else {
                        Button { buildPreview() } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.55), radius: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
        } else {
            let vidW: CGFloat    = 211.0   // 9:16 미리보기 폭 (375 × 9/16)
            ZStack {
                // Background: 레터박스 + 9:16 필러박스 영상
                Color.black
                // 슬라이드 템플릿: 재생 중일 때만 비디오 플레이어, 정지/대기 중엔 정적 사진
                if template == .slide {
                    if !isOneLiner, athleticVM.athleticVideoState.isReady,
                       athleticVM.athleticVideoState.isPlaying,
                       let avPlayer = athleticVM.athleticVideoState.player {
                        RawVideoPlayerView(player: avPlayer)
                            .frame(width: vidW, height: 375)
                    } else {
                        let idx   = cardPhotoIndex[.athletic] ?? 0
                        let cropX = athleticSlideCropOffsets[idx] ?? 0.5
                        if let photo = storyPhotos.indices.contains(idx) ? storyPhotos[idx] : storyPhotos.first {
                            let s      = max(vidW / photo.size.width, 375 / photo.size.height)
                            let iW     = photo.size.width  * s
                            let iH     = photo.size.height * s
                            let excess = max(0, iW - vidW)
                            Image(uiImage: photo)
                                .resizable()
                                .frame(width: iW, height: iH)
                                .offset(x: -(cropX * excess))
                                .frame(width: vidW, height: 375, alignment: .topLeading)
                                .clipped()
                                .brightness(CardVisual.videoBrightnessBoost)
                                .gesture(excess > 0 ? DragGesture(minimumDistance: 1)
                                    .onChanged { drag in
                                        if athleticSlideCropDragBase == nil { athleticSlideCropDragBase = cropX }
                                        guard let base = athleticSlideCropDragBase else { return }
                                        athleticSlideCropOffsets[idx] = max(0, min(1,
                                            base - drag.translation.width / excess))
                                    }
                                    .onEnded { _ in
                                        athleticSlideCropDragBase = nil
                                        saveAthleticCropOffsets()
                                        athleticVM.athleticVideoState.invalidate()
                                    }
                                : nil)
                        } else if !isExportingVideo {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Theme.violet)
                                Text(AppLanguage.shared.s("사진을 선택해 주세요", "Select photos"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                // 영상이 준비된 경우 RawVideoPlayerView를 썸네일 대신 배경으로 사용
                // (VideoOverlayCard 아래 배치하여 데이터 오버레이가 항상 위에 표시되도록)
                if !isOneLiner, athleticVM.athleticVideoState.isReady, let avPlayer = athleticVM.athleticVideoState.player {
                    RawVideoPlayerView(player: avPlayer)
                        .frame(width: vidW, height: 375)
                } else {
                    let previewThumb = videoPreviewImage ?? athleticVM.athleticClipRecipes.first?.thumbnail
                    if let preview = previewThumb {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: vidW, height: 375)
                            .clipped()
                            .brightness(CardVisual.videoBrightnessBoost)
                    } else if !isExportingVideo {
                        VStack(spacing: 10) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 32))
                                .foregroundStyle(Theme.violet)
                            Text(AppLanguage.shared.s("영상을 선택해 주세요", "Select a video"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                } // end template == .slide else

                // 데이터 오버레이: Athletic/OneLiner — VideoOverlayCard (상·하 5% 여백)
                // 슬라이드 재생 중에는 영상에 오버레이가 이미 합성되어 있으므로 정적 오버레이 숨김
                let slideIsPlaying = template == .slide && athleticVM.athleticVideoState.isPlaying
                let inset: CGFloat = 375 * 0.05   // 18.75pt
                if !slideIsPlaying { VideoOverlayCard(
                        distanceKm: distStr,
                        date: activity.date,
                        metrics: Array(enabledMetricItems.prefix(6)),
                        raceName: activeRaceName,
                        chartPanel: cardPanel,
                        chartSplits: detail?.splits ?? [],
                        chartHRSamples: shareHRSamples,
                        chartHRZones: detail?.hrZones ?? [],
                        chartWorkoutSeries: shareWorkoutSeries,
                        chartIntervalSegments: detail?.intervalSegments ?? [],
                        weather: condition?.weather,
                        shoeName: displayShoeName,
                        summaryLines: cardSummaryLines,
                        scale: vidW / 300.0,
                        topInset: inset,
                        bottomInset: 14
                    )
                    .frame(width: vidW, height: 375)
                    .allowsHitTesting(false)
                } // end if !slideIsPlaying

                // Export progress overlay
                if isExportingVideo {
                    Color.black.opacity(0.55)
                    VStack(spacing: 8) {
                        ProgressView().tint(.white).scaleEffect(1.2)
                        Text(AppLanguage.shared.s("합성 중...", "Processing..."))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                    }
                }

                // ▶ play button for OneLiner multi-clip preview
                if isOneLiner, oneLinerHasPhotos, !isExportingVideo {
                    if previewPlayer.isBuilding {
                        ProgressView().tint(.white)
                            .padding(14)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                    } else {
                        Button { buildPreview() } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.55), radius: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // ▶ Athletic 슬라이드 미리보기 컨트롤
                if !isOneLiner, template == .slide, !storyPhotos.isEmpty, !isExportingVideo {
                    if athleticVM.athleticVideoState.isReady {
                        Button { athleticVM.athleticVideoState.togglePlayPause() } label: {
                            Image(systemName: athleticVM.athleticVideoState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(athleticVM.athleticVideoState.isPlaying ? 0 : 0.85))
                                .shadow(color: .black.opacity(0.55), radius: 10)
                        }
                        .buttonStyle(.plain)
                    } else if athleticVM.athleticPreviewBuilding {
                        ProgressView().tint(.white)
                            .padding(14)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                    } else {
                        Button { Task { await buildAthleticSlidePreview() } } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.55), radius: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                // ▶ Athletic 멀티클립 미리보기 컨트롤 (플레이어는 배경 레이어에 있음)
                if !isOneLiner, template == .video, !athleticVM.athleticClipRecipes.isEmpty, !isExportingVideo {

                    if athleticVM.athleticVideoState.isReady {
                        Button {
                            athleticVM.athleticVideoState.togglePlayPause()
                        } label: {
                            Image(systemName: athleticVM.athleticVideoState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(athleticVM.athleticVideoState.isPlaying ? 0 : 0.85))
                                .shadow(color: .black.opacity(0.55), radius: 10)
                        }
                        .buttonStyle(.plain)
                    } else if athleticVM.athleticPreviewBuilding {
                        ProgressView().tint(.white)
                            .padding(14)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                    } else {
                        Button {
                            Task { await buildAthleticPreview() }
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.55), radius: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: vidW, height: 375)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }


    // MARK: - Share CTA

    @ViewBuilder
    private var shareCTA: some View {
        if template == .video || template == .slide {
            if isExportingVideo {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.violet)
                    Text(template == .slide
                         ? AppLanguage.shared.s("슬라이드 만드는 중...", "Creating slides...")
                         : AppLanguage.shared.s("영상 만드는 중...", "Exporting video..."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else if let vf = exportedVideoFile {
                ShareLink(item: vf, preview: SharePreview(
                    template == .slide
                        ? AppLanguage.shared.s("러닝 슬라이드", "Running Slides")
                        : AppLanguage.shared.s("러닝 영상", "Running Video")
                )) {
                    Label(
                        template == .slide
                            ? AppLanguage.shared.s("슬라이드 내보내기", "Export Slides")
                            : AppLanguage.shared.s("영상 내보내기", "Export Video"),
                        systemImage: "square.and.arrow.up"
                    )
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else if template == .slide, storyPhotos.isEmpty {
                Text(AppLanguage.shared.s("사진을 선택해 주세요", "Select photos first"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else if isStamp, template == .video, stampVM.clipRecipes.isEmpty {
                Text(AppLanguage.shared.s("영상을 선택해 주세요", "Select a video first"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                Button {
                    Task { await exportVideo() }
                } label: {
                    Label(template == .slide
                              ? AppLanguage.shared.s("슬라이드 내보내기", "Export Slides")
                              : AppLanguage.shared.s("영상 내보내기", "Export Video"),
                          systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        } else if template == .routeVideo {
            if routeCoords.isEmpty {
                Text(AppLanguage.shared.s("야외 러닝 경로가 있을 때\n사용할 수 있어요", "Available when an outdoor route exists"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else if isExportingRouteVideo {
                VStack(spacing: 10) {
                    ProgressView(value: routeVideoProgress)
                        .tint(Theme.violet)
                        .padding(.horizontal, 4)
                    Text(AppLanguage.shared.s("경로 영상 만드는 중… \(Int(routeVideoProgress * 100))%", "Creating route video… \(Int(routeVideoProgress * 100))%"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else if let vf = routeVideoFile {
                Button { showRouteVideoShareSheet = true } label: {
                    Label(AppLanguage.shared.s("경로 영상 내보내기", "Export Route Video"), systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .sheet(isPresented: $showRouteVideoShareSheet) {
                    VideoShareSheet(url: vf.url)
                }
            } else {
                Button {
                    Task { await exportRouteVideo() }
                } label: {
                    Label(AppLanguage.shared.s("경로 영상 내보내기", "Export Route Video"), systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(!routeSnapshotPoints.isEmpty ? Theme.violet : Color.gray.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(routeSnapshotPoints.isEmpty)
            }
        } else if isRendering {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.violet)
                Text(AppLanguage.shared.s("카드 만드는 중...", "Creating card..."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        } else if storyShareImages.count >= 1 {
            VStack(spacing: 10) {
                Button { showShareSheet = true } label: {
                    Label(AppLanguage.shared.s("카드 내보내기", "Export Card"),
                          systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(images: storyShareImages)
                }
            }
        } else if isStamp && template == .photo {
            Button {
                // 버튼 탭 시점(동기)에 baseConfig 캡처.
                // baseConfig는 position·template·colorMode 등 스타일 setter가 항상 최신값으로 갱신하지만,
                // stampText는 per-photo라 currentConfig에만 저장되고 baseConfig.text는 빈 문자열.
                // 두 값을 병합: 스타일은 baseConfig, 문구는 currentConfig.text.
                var exportCfg  = stampVM.baseConfig
                exportCfg.text = stampVM.currentConfig.text
                let exportCropX = stampVM.storyCropOffsetX
                Task { @MainActor in
                    // Warmup: 첫 번째 ImageRenderer 호출은 SwiftUI 파이프라인 미초기화로 잘못된 이미지를 반환함.
                    // 1회 워밍업 후 50ms 대기로 파이프라인 초기화 (slide 내보내기와 동일 패턴).
                    let wuPhoto = storyPhotos.first ?? storyPhoto
                    _ = makeStampStoryImage(photo: wuPhoto, data: stampPreviewData, vm: stampVM,
                                            cropOffsetX: exportCropX,
                                            configOverride: exportCfg)
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    guard isStamp, template == .photo else { return }

                    if storyPhotos.count > 1 {
                        // 다중 사진: 각 사진의 독립 config(위치·템플릿·문구 등) 사용.
                        // makeStampStoryImage 내부 2회 warmup이 사진마다 레이아웃을 정착시키므로
                        // 사진 간 stale 레이아웃 문제 없이 per-photo config 적용 가능.
                        var rendered: [UIImage] = []
                        for (i, photo) in storyPhotos.enumerated() {
                            let cfg = stampVM.photoConfig(at: i)
                            if let img = makeStampStoryImage(
                                photo: photo, data: stampPreviewData, vm: stampVM,
                                cropOffsetX: exportCropX,
                                configOverride: cfg) {
                                rendered.append(img)
                            }
                        }
                        if !rendered.isEmpty {
                            storyShareImages = rendered
                            // storyShareImages 설정으로 분기가 isStamp→storyShareImages≥1로 바뀜.
                            // 같은 tick에 showShareSheet=true를 설정하면 사라지는 뷰의 .sheet가 요청되어
                            // 화면이 검게 변하는 race condition 발생 → yield로 뷰 전환 완료 후 표시.
                            await Task.yield()
                            showShareSheet = true
                        }
                    } else if let img = makeStampStoryImage(
                        photo: storyPhoto, data: stampPreviewData, vm: stampVM,
                        cropOffsetX: exportCropX,
                        configOverride: exportCfg) {
                        // previewImage 대신 storyShareImages 사용 — onChange의 previewImage=nil 무관하게 안전.
                        storyShareImages = [img]
                        await Task.yield()
                        showShareSheet = true
                    }
                }
            } label: {
                Label(AppLanguage.shared.s("카드 내보내기", "Export Card"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .sheet(isPresented: $showShareSheet) {
                if !storyShareImages.isEmpty {
                    ShareSheet(images: storyShareImages)
                } else {
                    Text("🚨 이미지 없음").padding()
                }
            }
        } else if let img = previewImage {
            if isOneLiner && isBatchExporting {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.violet)
                    Text(AppLanguage.shared.s("합성 중...", "Processing..."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else if isOneLiner && template == .photo && !oneLinerVM.storyPhotoUUIDs.isEmpty {
                // 사진 연결 OneLiner: 문구 있는 사진 렌더링 후 공유 시트 표시
                let count = linkedOneLinerPhotoCount
                Button { Task { await batchExportOneLinerCards() } } label: {
                    Label(AppLanguage.shared.s("카드 내보내기", "Export Card"), systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(count == 0 ? Color.white.opacity(0.4) : .white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(count == 0 ? Theme.violet.opacity(0.35) : Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(count == 0)
            } else {
                let shareDisabled = isOneLiner && oneLinerVM.oneLinerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button { showShareSheet = true } label: {
                    Label(AppLanguage.shared.s("카드 내보내기", "Export Card"),
                          systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(shareDisabled ? Color.white.opacity(0.4) : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(shareDisabled ? Theme.violet.opacity(0.35) : Theme.violet)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(shareDisabled)
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(images: [img])
                }
            }
        } else {
            Text(AppLanguage.shared.s("카드 생성에 실패했어요", "Card creation failed"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
    }

    // MARK: - Render


    private func buildPreview() {
        Task {
            if oneLinerIsPhotoSlide {
                // 슬라이드: 쉬는날 카드와 동일하게 라이브 인메모리 레시피 우선 사용.
                // storyClipEditRecipes가 비어있으면(첫 실행·세션 재진입) SwiftData에서 복원.
                let photos = storyPhotos
                guard !photos.isEmpty else { return }
                let slideRecipes  = (oneLinerVM.storyClipEditRecipes.isEmpty || oneLinerVM.storyClipEditRecipes.count != photos.count)
                    ? makeStoryClipRecipes(isSlide: true)
                    : oneLinerVM.storyClipEditRecipes
                await previewPlayer.buildForPhotoSlides(
                    photos: photos, recipes: slideRecipes,
                    metricLookup: oneLinerMetricLookup,
                    routeCoords: routeCoords,
                    hrSamples: shareHRSamples,
                    splits: detail?.splits ?? [],
                    chartSeriesData: chartSeriesData,
                    hrZones: detail?.hrZones ?? [],
                    intervalSegments: detail?.intervalSegments ?? [],
                    videoTitle: oneLinerVM.oneLinerVideoTitle, titleStyle: oneLinerVM.oneLinerTitleStyle,
                    fastBase: true,
                    forCard: .oneLiner)
                // 슬라이드: 빌드 완료 즉시 재생 — ▶ 한 번으로 재생 시작
                previewPlayer.play()
            } else {
                // 영상: 실제 클립 재생 (export와 동일한 필믹 파이프라인 — resolvedAsset 사용)
                // showWordmark: false → CALayer 워드마크 끔. 재생 중 SwiftUI 오버레이가 표시.
                await previewPlayer.buildForVideoClips(
                    recipes: oneLinerVM.oneLinerClipRecipes,
                    showWordmark: false,
                    muteAudio: oneLinerVM.oneLinerMuteAudio,
                    metricChips: oneLinerActiveMetricChips,
                    metricLookup: oneLinerMetricLookup,
                    routeCoords: routeCoords,
                    hrSamples: shareHRSamples,
                    splits: detail?.splits ?? [],
                    chartSeriesData: chartSeriesData,
                    hrZones: detail?.hrZones ?? [],
                    intervalSegments: detail?.intervalSegments ?? [],
                    videoTitle: oneLinerVM.oneLinerVideoTitle, titleStyle: oneLinerVM.oneLinerTitleStyle,
                    safeTopOverride: 1920 * 0.06, safeBotOverride: 1920 * 0.06,
                    wordmarkTopPad: 1920 * 0.06,
                    forCard: .oneLiner)
            }
        }
    }

    private func presentShareSheet(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = scene.keyWindow?.rootViewController else { return }
        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }
        // 이미 UIActivityViewController가 표시 중이면 중복 표시 방지
        guard !(topVC is UIActivityViewController) else { return }
        // iPad: popover 앵커 없으면 크래시 → 화면 중앙 고정
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        topVC.present(activityVC, animated: true)
    }

    /// 플레이서블 영상 설정 변경 시 이전 내보내기 캐시를 무효화한다.
    /// PlaceableVideoTemplate.swift extension에서 접근할 수 있도록 internal로 선언.
    func invalidatePlaceableVideoExport() { exportedVideoFile = nil }

    @MainActor
    private func exportVideo() async {
        guard !isExportingVideo else { return }
        isExportingVideo = true
        exportedVideoFile = nil
        // 스피너가 먼저 렌더된 후 동기 작업(ImageRenderer 등)이 실행되도록 양보
        await Task.yield()

        // ── OneLiner 슬라이드 (storyPhotos 기반) ────────────────────────────
        if isOneLiner, oneLinerIsPhotoSlide {
            let photos = storyPhotos
            guard !photos.isEmpty else { isExportingVideo = false; return }
            do {
                // 편집된 문구·스타일 — 라이브 인메모리 우선, 없으면 SwiftData 복원
                let slideRecipes = (oneLinerVM.storyClipEditRecipes.isEmpty || oneLinerVM.storyClipEditRecipes.count != photos.count)
                    ? makeStoryClipRecipes(isSlide: true)
                    : oneLinerVM.storyClipEditRecipes
                let out = try await PhotoSlideComposition.exportSlideWithText(
                    photos: photos, recipes: slideRecipes,
                    metricLookup: oneLinerMetricLookup,
                    routeCoords: routeCoords,
                    hrSamples: shareHRSamples,
                    splits: detail?.splits ?? [],
                    chartSeriesData: chartSeriesData,
                    hrZones: detail?.hrZones ?? [],
                    intervalSegments: detail?.intervalSegments ?? [],
                    videoTitle: oneLinerVM.oneLinerVideoTitle, titleStyle: oneLinerVM.oneLinerTitleStyle)
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } catch { /* fall through */ }
            isExportingVideo = false
            return
        }

        // ── OneLiner multi-clip path (영상, running day) ────────────────────
        if isOneLiner, template == .video, !oneLinerVM.oneLinerClipRecipes.isEmpty {
            do {
                var recipes = oneLinerVM.oneLinerClipRecipes
                // URL이 없는 클립은 resolvedAsset이나 assetIdentifier로 재해석
                for i in recipes.indices {
                    guard !FileManager.default.fileExists(atPath: recipes[i].url.path) else { continue }
                    if recipes[i].resolvedAsset != nil { continue }
                    if let assetID = recipes[i].assetIdentifier {
                        recipes[i].resolvedAsset = try await MultiClipComposition.resolveAVAsset(assetID: assetID)
                    }
                }
                let chips   = oneLinerActiveMetricChips
                // resolvedAsset이 있으면 반드시 composeAndExport 경로 사용 (URL 직접 사용 금지)
                let hasResolvedAssets = recipes.contains { $0.resolvedAsset != nil }
                let needsCompose = recipes.count > 1 || recipes.contains { $0.isTrimmed }
                    || recipes.contains { abs($0.speed - 1.0) > 0.01 } || hasResolvedAssets
                let exportSrc: URL
                var cleanup: URL? = nil
                if needsCompose {
                    let (composed, _) = try await MultiClipComposition.composeAndExport(
                        recipes: recipes, muteAudio: oneLinerVM.oneLinerMuteAudio)
                    exportSrc = composed; cleanup = composed
                } else {
                    exportSrc = recipes[0].url
                }
                defer { cleanup.map { try? FileManager.default.removeItem(at: $0) } }
                let isMuted = oneLinerVM.oneLinerMuteAudio
                let out = try await VideoExportService.exportOneLinerClipBoundVideo(
                    sourceURL: exportSrc, recipes: recipes,
                    muteAudio: isMuted, metricChips: chips,
                    metricLookup: oneLinerMetricLookup,
                    routeCoords: routeCoords,
                    hrSamples: shareHRSamples,
                    splits: detail?.splits ?? [],
                    hrZones: detail?.hrZones ?? [],
                    intervalSegments: detail?.intervalSegments ?? [],
                    chartSeriesData: chartSeriesData,
                    videoTitle: oneLinerVM.oneLinerVideoTitle, titleStyle: oneLinerVM.oneLinerTitleStyle)
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } catch {
                videoExportError = AppLanguage.shared.s(
                    "내보내기 중 오류가 발생했습니다: \(error.localizedDescription)",
                    "Export error: \(error.localizedDescription)")
                showVideoExportError = true
            }
            isExportingVideo = false
            return
        }

        // ── Placeable 슬라이드 (storyPhotos 기반 사진 슬라이드 영상) ──────────
        if isPlaceable, template == .slide {
            let photos = storyPhotos
            guard !photos.isEmpty else { isExportingVideo = false; return }
            do {
                let overlayIsTop = placeableVM.placeableLayout == .horizontal
                    ? placeableVM.placeableHorizTextRow == .top
                    : placeableVM.placeableMetricsPosition.isTop
                let overlay = makePlaceableDataOverlay(fullHeight: overlayIsTop)
                let recipes = makePlaceableSlideRecipes(for: photos)
                let out = try await PhotoSlideComposition.exportSlideWithText(
                    photos: photos, recipes: recipes,
                    metricLookup: [:], routeCoords: [],
                    hrSamples: [], splits: [], chartSeriesData: [:],
                    hrZones: [], intervalSegments: [],
                    videoTitle: "", titleStyle: OneLinerTitleStyle(),
                    dataOverlayImage: overlay,
                    dataOverlayIsTop: overlayIsTop)
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } catch {
                videoExportError = AppLanguage.shared.s(
                    "내보내기 중 오류가 발생했습니다: \(error.localizedDescription)",
                    "Export error: \(error.localizedDescription)")
                showVideoExportError = true
            }
            isExportingVideo = false
            return
        }

        // ── Placeable 영상 합성 (sourceVideoURL 불필요 — 클립별 URL 직접 해석) ──
        if isPlaceable {
            guard !placeableVM.placeableClipRecipes.isEmpty else { isExportingVideo = false; return }

            // PlaceableCard overlay: 로고 상단 7.5%, 데이터·날짜 하단 7.5% 배치
            let scale: CGFloat = 216.0 / PlaceableCard.cardWidth  // 0.72
            let scaledH = PlaceableCard.cardHeight * scale          // ~270pt

            // 정적 오버레이: 그라디언트 + PlaceableCard 데이터 패널 (문구·워드마크 제외)
            // 워드마크는 textLayer(buildClipTextContentLayer)가 처리하므로 여기서는 렌더링하지 않음.
            let exportIsTop = placeableVM.placeableLayout == .horizontal
                ? placeableVM.placeableHorizTextRow == .top
                : placeableVM.placeableMetricsPosition.isTop
            let exportFullH: CGFloat = 384.0 / scale  // 9:16 전체 높이를 카드 좌표계로 환산
            let staticOverlayContent = ZStack {
                LinearGradient(colors: [.black.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: 216, height: 24).frame(width: 216, height: 384, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                    .frame(width: 216, height: 24).frame(width: 216, height: 384, alignment: .bottom)
                PlaceableCard(
                    activity: activity, detail: detail,
                    routeCoords: routeCoords.isEmpty ? nil : routeCoords,
                    photo: nil, date: activity.date,
                    metricsPosition: placeableVM.placeableMetricsPosition, accent: placeableVM.placeableAccent,
                    showBackground: false, showWordmark: false,
                    shoeName: displayShoeName, weather: condition?.weather,
                    size: placeableVM.placeableSize, layout: placeableVM.placeableLayout,
                    horizTextRow: placeableVM.placeableHorizTextRow, horizRoutePos: placeableVM.placeableHorizRoutePos,
                    heightOverride: exportIsTop ? exportFullH : nil
                )
                .frame(width: PlaceableCard.cardWidth, height: exportIsTop ? exportFullH : PlaceableCard.cardHeight)
                .scaleEffect(scale, anchor: .center)
                .frame(width: 216, height: exportIsTop ? 384 : scaledH)
                .padding(.bottom, exportIsTop ? 0 : 384 * 0.03)
                .frame(width: 216, height: 384, alignment: exportIsTop ? .center : .bottom)
            }
            .frame(width: 216, height: 384)
            let staticRenderer = ImageRenderer(content: staticOverlayContent)
            staticRenderer.scale = 5.0
            let staticOverlay = staticRenderer.uiImage

            // 문구 safe zone — 스토리처럼 데이터 위치와 독립적으로 자유 배치
            let safeBotPx = CardVisual.videoSafeBottom
            let safeTopPx = CardVisual.videoSafeTop

            // 클립별 오버레이 적용 후 연결
            // URL 해석 우선순위: 임시파일(PHPicker) → resolvedAsset(PHImageManager) → assetIdentifier 재해석
            var processedURLs: [URL] = []
            for recipe in placeableVM.placeableClipRecipes {
                var srcURL: URL = recipe.url
                if !FileManager.default.fileExists(atPath: recipe.url.path) {
                    if let urlAsset = recipe.resolvedAsset as? AVURLAsset {
                        srcURL = urlAsset.url
                    } else if let assetID = recipe.assetIdentifier,
                              let resolved = try? await MultiClipComposition.resolveAVAsset(assetID: assetID),
                              let urlAsset = resolved as? AVURLAsset {
                        srcURL = urlAsset.url
                    } else {
                        continue
                    }
                }
                // 클립 길이 = 트림 구간 / 배속
                let clipDur = recipe.trimmedDuration / max(0.1, recipe.speed)
                // 문구 애니메이션 CALayer — 빈 text도 레이어 생성(내용 없음으로 처리)
                let textLayer = VideoExportService.buildClipTextContentLayer(
                    recipes: [recipe],
                    renderSize: VideoExportService.targetSize,
                    totalDuration: clipDur,
                    safeTopOverride: safeTopPx,
                    safeBotOverride: safeBotPx,
                    wordmarkTopPad: VideoExportService.targetSize.height * 0.06)
                if let processed = try? await VideoExportService.exportPlaceableClipAnimated(
                    sourceURL: srcURL,
                    staticOverlay: staticOverlay,
                    textLayer: textLayer,
                    trimStart: recipe.trimStart, trimEnd: recipe.trimEnd,
                    muteAudio: placeableVM.placeableMuteAudio, speed: recipe.speed,
                    brightenHDR: true) {
                    processedURLs.append(processed)
                }
            }
            let exportedURL: URL?
            if processedURLs.count > 1 {
                exportedURL = try? await VideoExportService.concatenateURLs(processedURLs)
            } else {
                exportedURL = processedURLs.first
            }
            if let out = exportedURL {
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } else {
                videoExportError = AppLanguage.shared.s("영상 합성에 실패했습니다.", "Video export failed.")
                showVideoExportError = true
            }
            isExportingVideo = false
            return
        }

        // ── Athletic 멀티 클립 합성 (athleticVM.athleticClipRecipes 기반) ──────────────
        if !isOneLiner, !isPlaceable, !isStamp, template == .video, !athleticVM.athleticClipRecipes.isEmpty {
            let km = activity.distance / 1000
            let distStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
            // 미리보기와 동일한 9:16 비율(216×384pt)로 오버레이 렌더링
            // topInset/bottomInset = 5% (384 * 0.05 = 19.2pt) → 미리보기(375 * 0.05 = 18.75pt)와 동일 비율
            let exportH: CGFloat = 384
            let exportInset: CGFloat = exportH * 0.05
            let overlayView = VideoOverlayCard(
                distanceKm: distStr,
                date: activity.date,
                metrics: Array(enabledMetricItems.prefix(6)),
                raceName: activeRaceName,
                chartPanel: cardPanel,
                chartSplits: detail?.splits ?? [],
                chartHRSamples: shareHRSamples,
                chartHRZones: detail?.hrZones ?? [],
                chartWorkoutSeries: shareWorkoutSeries,
                chartIntervalSegments: detail?.intervalSegments ?? [],
                weather: condition?.weather,
                shoeName: displayShoeName,
                summaryLines: cardSummaryLines,
                scale: 216.0 / 300.0,
                topInset: exportInset,
                bottomInset: 14
            )
            .frame(width: 216, height: exportH)
            .preferredColorScheme(.dark)
            // Warmup: 첫 번째 ImageRenderer 호출로 SwiftUI 파이프라인 초기화.
            let wuR = ImageRenderer(content: overlayView); wuR.scale = 1.0; _ = wuR.uiImage
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50 ms
            guard !isOneLiner, !isPlaceable, !isStamp, template == .video else { isExportingVideo = false; return }
            let overlayRenderer = ImageRenderer(content: overlayView)
            overlayRenderer.scale = 5.0
            guard let overlayImage = overlayRenderer.uiImage else {
                isExportingVideo = false; return
            }
            var processedURLs: [URL] = []
            for recipe in athleticVM.athleticClipRecipes {
                var srcURL = recipe.url
                if !FileManager.default.fileExists(atPath: srcURL.path) {
                    if let urlAsset = recipe.resolvedAsset as? AVURLAsset {
                        srcURL = urlAsset.url
                    } else if let assetID = recipe.assetIdentifier,
                              let resolved = try? await MultiClipComposition.resolveAVAsset(assetID: assetID),
                              let urlAsset = resolved as? AVURLAsset {
                        srcURL = urlAsset.url
                    } else {
                        continue
                    }
                }
                if let u = try? await VideoExportService.exportClipWithOverlay(
                    sourceURL: srcURL, overlay: overlayImage,
                    trimStart: recipe.trimStart, trimEnd: recipe.trimEnd,
                    muteAudio: athleticVM.athleticMuted,
                    brightenHDR: true) {
                    processedURLs.append(u)
                }
            }
            let exportedURL: URL?
            if processedURLs.count > 1 {
                exportedURL = try? await VideoExportService.concatenateURLs(processedURLs)
            } else {
                exportedURL = processedURLs.first
            }
            if let out = exportedURL {
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } else {
                videoExportError = AppLanguage.shared.s("영상 합성에 실패했습니다.", "Video export failed.")
                showVideoExportError = true
            }
            isExportingVideo = false
            return
        }


        // ── Athletic 슬라이드 (사진 → 영상) ────────────────────────────────────
        if !isOneLiner, !isPlaceable, !isStamp, template == .slide, !storyPhotos.isEmpty {
            let km = activity.distance / 1000
            let distStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)
            let exportH: CGFloat = 384
            let exportInset: CGFloat = exportH * 0.05
            let overlayView = VideoOverlayCard(
                distanceKm: distStr,
                date: activity.date,
                metrics: Array(enabledMetricItems.prefix(6)),
                raceName: activeRaceName,
                chartPanel: cardPanel,
                chartSplits: detail?.splits ?? [],
                chartHRSamples: shareHRSamples,
                chartHRZones: detail?.hrZones ?? [],
                chartWorkoutSeries: shareWorkoutSeries,
                chartIntervalSegments: detail?.intervalSegments ?? [],
                weather: condition?.weather,
                shoeName: displayShoeName,
                summaryLines: cardSummaryLines,
                scale: 216.0 / 300.0,
                topInset: exportInset,
                bottomInset: 14
            )
            .frame(width: 216, height: exportH)
            .preferredColorScheme(.dark)
            // Warmup: 첫 번째 ImageRenderer 호출로 SwiftUI 파이프라인 초기화.
            let wuR = ImageRenderer(content: overlayView); wuR.scale = 1.0; _ = wuR.uiImage
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50 ms
            guard !isOneLiner, !isPlaceable, !isStamp, template == .slide, !storyPhotos.isEmpty else { isExportingVideo = false; return }
            let overlayRenderer = ImageRenderer(content: overlayView)
            overlayRenderer.scale = 5.0
            guard let overlayImage = overlayRenderer.uiImage else {
                isExportingVideo = false; return
            }
            let offsets = storyPhotos.indices.map { i in
                athleticSlideCropOffsets[i] ?? 0.5
            }
            if let out = try? await PhotoSlideComposition.exportAthleticSlide(
                photos: storyPhotos,
                cropOffsets: offsets,
                overlayImage: overlayImage,
                clipDuration: PhotoSlideComposition.placeableSlideDuration) {
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } else {
                videoExportError = AppLanguage.shared.s("슬라이드 영상 합성에 실패했습니다.", "Slide export failed.")
                showVideoExportError = true
            }
            isExportingVideo = false
            return
        }

        // ── Stamp 슬라이드 합성 (storyPhotos 사용 — story 모드와 동일 사진) ─────────
        if isStamp, template == .slide {
            // [필수] exportStampSlide sz(1080×1920)와 반드시 일치.
            // makeStampOverlayImage는 renderSize로 스탬프 pt 높이를 역산(height/width*300).
            let renderSz = CGSize(width: 1080, height: 1920)
            // Warmup: 첫 번째 ImageRenderer 호출은 SwiftUI 파이프라인 미초기화로 잘못된 이미지를 반환함.
            // 1회 워밍업 후 50ms 대기로 파이프라인 초기화 (story 모드 renderCard 동일 패턴).
            if let firstPhoto = storyPhotos.first {
                let firstCfg = stampVM.photoConfig(at: 0)
                let wuBright = stampBackgroundIsBright(photo: firstPhoto, position: firstCfg.position)
                _ = makeStampOverlayImage(data: stampPreviewData, vm: stampVM,
                                          isBright: wuBright, renderSize: renderSz,
                                          configOverride: firstCfg, renderOnlyStamp: true)
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50 ms — 파이프라인 안정화
                guard isStamp, template == .slide else { isExportingVideo = false; return }
            }
            var photos:       [UIImage]   = []
            var cropOffsets:      [CGFloat]             = []
            var overlays:         [UIImage]             = []
            var textOverlays:     [UIImage?]            = []
            var entranceModes:    [StampEntranceMode]   = []
            var flyDirections:    [FlyInDirection]      = []
            var textEntrModes:    [StampEntranceMode]   = []
            var textFlyDirs:      [FlyInDirection]      = []
            for (i, photo) in storyPhotos.enumerated() {
                // 사진별 config 전체(스탬프·위치·색상·문구·애니메이션 등) 독립 사용
                let cfg = stampVM.photoConfig(at: i)
                let isBright = stampBackgroundIsBright(photo: photo, position: cfg.position)
                guard let img = makeStampOverlayImage(
                    data: stampPreviewData, vm: stampVM,
                    isBright: isBright, renderSize: renderSz,
                    configOverride: cfg,
                    renderOnlyStamp: true)
                else { continue }
                photos.append(photo)
                cropOffsets.append(stampSlideCropOffsets[i] ?? 0.5)
                overlays.append(img)
                entranceModes.append(cfg.entranceMode)
                flyDirections.append(cfg.flyDirection)
                // 사진별 문구 오버레이 — 스탬프와 독립 애니메이션
                let textImg: UIImage? = cfg.text.isEmpty ? nil
                    : makeStampOverlayImage(
                        data: stampPreviewData, vm: stampVM,
                        isBright: isBright, renderSize: renderSz,
                        configOverride: cfg,
                        renderOnlyText: true)
                textOverlays.append(textImg)
                textEntrModes.append(cfg.textEntranceMode)
                textFlyDirs.append(cfg.textFlyDirection)
            }
            guard !photos.isEmpty else { isExportingVideo = false; return }
            let logoOverlay = makeStampLogoDateOverlay(renderSize: renderSz, date: stampVM.showDate ? activity.date : nil)
            if let out = try? await exportStampSlide(
                photos: photos,
                cropOffsets: cropOffsets,
                stampOverlays: overlays,
                entranceModes: entranceModes,
                flyDirections: flyDirections,
                textOverlays: textOverlays,
                textEntranceModes: textEntrModes,
                textFlyDirections: textFlyDirs,
                logoOverlay: logoOverlay,
                clipDuration: PhotoSlideComposition.placeableSlideDuration) {
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } else {
                videoExportError = AppLanguage.shared.s("슬라이드 합성에 실패했습니다.", "Slide export failed.")
                showVideoExportError = true
            }
            isExportingVideo = false
            return
        }

        // ── Stamp 영상 합성 (stampVM.clipRecipes 기반) ───────────────────────
        if isStamp, template == .video, !stampVM.clipRecipes.isEmpty {
            // 프리뷰 플레이어를 일시 정지해 AVAssetExportSession과 소스 파일 경합 방지
            previewPlayer.pause()
            let renderSz = VideoExportService.targetSize

            // Warmup: 첫 번째 ImageRenderer 호출은 SwiftUI 파이프라인 미초기화로 잘못된 이미지를 반환함.
            // logicalWidth: 영상 미리보기 컨테이너(375*9/16≈211pt)와 동일하게 → 미리보기·출력 크기 일치
            let stampVideoLogicalW: CGFloat = 375.0 * 9.0 / 16.0
            if let firstRecipe = stampVM.clipRecipes.first {
                let wuCfg = stampVM.photoConfig(at: 0)
                let wuBright = stampBackgroundIsBright(photo: firstRecipe.thumbnail, position: wuCfg.position)
                _ = makeStampOverlayImage(data: stampPreviewData, vm: stampVM,
                                          isBright: wuBright, renderSize: renderSz,
                                          configOverride: wuCfg, renderOnlyStamp: true,
                                          logicalWidth: stampVideoLogicalW)
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard isStamp, template == .video else { isExportingVideo = false; return }
            }

            let stampLogoImg = makeStampLogoOverlay(renderSize: renderSz, date: stampVM.showDate ? activity.date : nil)

            var processedURLs: [URL] = []
            for (i, recipe) in stampVM.clipRecipes.enumerated() {
                // 클립별 독립 config (스탬프·위치·색상·문구 등)
                let cfg      = stampVM.photoConfig(at: i)
                let isBright = stampBackgroundIsBright(photo: recipe.thumbnail, position: cfg.position)
                guard let stampImg = makeStampOverlayImage(
                    data: stampPreviewData, vm: stampVM,
                    isBright: isBright, renderSize: renderSz,
                    configOverride: cfg,
                    renderOnlyStamp: true,
                    logicalWidth: stampVideoLogicalW)
                else { continue }
                let textImg: UIImage? = cfg.text.isEmpty ? nil : makeStampOverlayImage(
                    data: stampPreviewData, vm: stampVM,
                    isBright: isBright, renderSize: renderSz,
                    configOverride: cfg,
                    renderOnlyText: true,
                    logicalWidth: stampVideoLogicalW)

                var srcURL: URL = recipe.url
                if !FileManager.default.fileExists(atPath: recipe.url.path) {
                    if let urlAsset = recipe.resolvedAsset as? AVURLAsset {
                        srcURL = urlAsset.url
                    } else if let assetID = recipe.assetIdentifier,
                              let resolved = try? await MultiClipComposition.resolveAVAsset(assetID: assetID),
                              let urlAsset = resolved as? AVURLAsset {
                        srcURL = urlAsset.url
                    } else {
                        continue
                    }
                }
                let clipDur = recipe.trimmedDuration / max(0.1, recipe.speed)
                let textLayer = VideoExportService.buildClipTextContentLayer(
                    recipes: [],
                    renderSize: renderSz,
                    totalDuration: clipDur,
                    showWordmark: false)
                let stampLayer = buildStampOverlayLayer(
                    from: stampImg, renderSize: renderSz,
                    mode: cfg.entranceMode,
                    flyDirection: cfg.flyDirection)
                textLayer.addSublayer(stampLayer)
                // 문구 독립 레이어 (있는 경우) — 스탬프 애니메이션 완료 후 등장
                if let tImg = textImg {
                    let stampAnimDur: Double = cfg.entranceMode == .none ? 0 : 0.60
                    let tl = buildStampOverlayLayer(
                        from: tImg, renderSize: renderSz,
                        mode: cfg.textEntranceMode,
                        flyDirection: cfg.textFlyDirection,
                        beginTimeOffset: stampAnimDur)
                    textLayer.addSublayer(tl)
                }
                // 로고 정적 레이어
                if let logo = stampLogoImg, let cgLogo = logo.cgImage {
                    let ll = CALayer()
                    ll.frame = CGRect(origin: .zero, size: renderSz)
                    ll.contents = cgLogo
                    ll.contentsGravity = .resize
                    ll.contentsScale = 1.0
                    textLayer.addSublayer(ll)
                }
                if let out = try? await VideoExportService.exportPlaceableClipAnimated(
                    sourceURL: srcURL, staticOverlay: nil,
                    textLayer: textLayer,
                    trimStart: recipe.trimStart, trimEnd: recipe.trimEnd,
                    muteAudio: stampVM.muteAudio, speed: recipe.speed,
                    brightenHDR: true) {
                    processedURLs.append(out)
                }
            }
            let stampExportedURL: URL? = processedURLs.count > 1
                ? (try? await VideoExportService.concatenateURLs(processedURLs))
                : processedURLs.first
            if let out = stampExportedURL {
                exportedVideoFile = SharableVideoFile(url: out)
                presentShareSheet(url: out)
            } else {
                videoExportError = AppLanguage.shared.s("영상 합성에 실패했습니다.", "Video export failed.")
                showVideoExportError = true
            }
            isExportingVideo = false
            return
        }

        // ── Single-source typing path (existing) ────────────────────────────
        guard let url = sourceVideoURL else { isExportingVideo = false; return }

        if isOneLiner {
            // Multi-slot mode (3+ slots = 2+ pages): group into pages of 2 and use multi-page export
            let filledSlots = oneLinerVM.oneLinerVideoSlotTexts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if oneLinerVM.oneLinerVideoSlotCount >= 3 && filledSlots.contains(where: { !$0.isEmpty }) {
                var pages: [[String]] = []
                var i = 0
                while i < filledSlots.count {
                    let s1 = filledSlots[i]
                    let s2 = i + 1 < filledSlots.count ? filledSlots[i + 1] : ""
                    let pair = [s1, s2].filter { !$0.isEmpty }
                    if !pair.isEmpty { pages.append(pair) }
                    i += 2
                }
                if pages.count > 1 {
                    if let out = try? await VideoExportService.exportOneLinerMultiPageVideo(
                        sourceURL: url,
                        pages: pages,
                        fontChoice: oneLinerVM.oneLinerFont,
                        textColor: oneLinerVM.oneLinerColor,
                        position: oneLinerVM.oneLinerPosition) {
                        exportedVideoFile = SharableVideoFile(url: out)
                    }
                    isExportingVideo = false
                    return
                }
            }
            // Single-text fallback: 2 slots or fewer, or all content resolves to 1 page
            if let out = try? await VideoExportService.exportOneLinerTypingVideo(
                sourceURL: url,
                text: oneLinerVM.oneLinerText,
                fontChoice: oneLinerVM.oneLinerFont,
                textColor: oneLinerVM.oneLinerColor,
                position: oneLinerVM.oneLinerPosition) {
                exportedVideoFile = SharableVideoFile(url: out)
            }
            isExportingVideo = false
            return
        }


        let km = activity.distance / 1000
        let distStr = km >= 10 ? String(format: "%.1f", km) : String(format: "%.2f", km)

        let overlayView = VideoOverlayCard(
            distanceKm: distStr,
            date: activity.date,
            metrics: Array(enabledMetricItems.prefix(6)),
            raceName: activeRaceName,
            chartPanel: cardPanel,
            chartSplits: detail?.splits ?? [],
            chartHRSamples: shareHRSamples,
            chartHRZones: detail?.hrZones ?? [],
            chartWorkoutSeries: shareWorkoutSeries,
            chartIntervalSegments: detail?.intervalSegments ?? [],
            weather: condition?.weather,
            shoeName: displayShoeName,
            summaryLines: cardSummaryLines,
            scale: 216.0 / 300.0,    // proportional to 300pt preview (= 0.72)
            topInset: 384.0 * 0.05,  // 5% = 19.2pt → 96px at scale 5 (preview 일치)
            bottomInset: 14
        )
        .frame(width: 216, height: 384)
        .preferredColorScheme(.dark)

        let overlayRenderer = ImageRenderer(content: overlayView)
        overlayRenderer.scale = 5.0   // 216 × 5 = 1080 px, 384 × 5 = 1920 px

        guard let overlayImage = overlayRenderer.uiImage else {
            isExportingVideo = false
            return
        }

        let trimStart = athleticVM.athleticClipRecipes.first?.trimStart ?? 0
        let trimEnd   = athleticVM.athleticClipRecipes.first?.trimEnd
        if let outputURL = try? await VideoExportService.exportVideo(
            sourceURL: url, overlay: overlayImage,
            startTime: trimStart, endTime: trimEnd) {
            exportedVideoFile = SharableVideoFile(url: outputURL)
        }
        isExportingVideo = false
    }

    @MainActor
    private func exportRouteVideo() async {
        guard let snap = routeSnapshot, !routeSnapshotPoints.isEmpty else { return }
        isExportingRouteVideo = true
        routeVideoProgress = 0
        routeVideoFile = nil
        do {
            let url: URL
            // stamp 경로 영상: 스탬프·문구를 별도 이미지로 렌더 → 각각 애니메이션 CALayer로 합성
            var exportStampLayers: [RouteVideoExportService.StampLayerConfig] = []
            if isStamp, template == .routeVideo {
                let previewVidW: CGFloat = 375.0 * 9.0 / 16.0
                let stampStart: Double = 0.5   // 영상 시작 후 0.5s (경로 그려지는 동안 오버레이)
                let stampAnimDuration: Double = 0.55
                let textStart: Double = stampStart + stampAnimDuration  // 스탬프 완료 후 문구 등장

                func renderStampImage(renderOnlyStamp: Bool, renderOnlyText: Bool) -> UIImage? {
                    if renderOnlyText {
                        // 문구: Placeable과 동일하게 300pt 기준 (줄바꿈·글자 크기 통일)
                        let textW = PlaceableCard.cardWidth
                        let textH = textW * 16.0 / 9.0
                        let textScale = RouteVideoExportService.renderScale * previewVidW / textW
                        let v = OneLinerCard(
                            text: stampVM.stampText,
                            position: stampVM.stampTextPosition,
                            textColor: stampVM.stampTextColor,
                            fontChoice: stampVM.stampTextFont,
                            sizeLevel: stampVM.stampTextSize,
                            appearanceMode: .typing,
                            decorEffect: .none,
                            hasBorder: stampVM.stampTextHasBorder,
                            showBackground: false,
                            showWordmark: false,
                            cardHeightOverride: textH,
                            safeTopInset: 77,
                            isStaticPreview: true
                        )
                        .frame(width: textW, height: textH)
                        let r = ImageRenderer(content: v)
                        r.scale = textScale
                        return r.uiImage
                    }
                    let v = StampCard(
                        data: stampPreviewData,
                        template: stampVM.storyTemplate,
                        colorMode: stampVM.colorMode,
                        position: stampVM.position,
                        sizeLevel: stampVM.sizeLevel,
                        isBrightBackground: false,
                        showHeartRate: stampVM.showHeartRate,
                        showCalories: stampVM.showCalories,
                        showTextOutline: stampVM.showTextOutline,
                        stampText: stampVM.stampText,
                        stampTextPosition: stampVM.stampTextPosition,
                        stampTextFont: stampVM.stampTextFont,
                        stampTextSize: stampVM.stampTextSize,
                        stampTextColor: stampVM.stampTextColor,
                        stampTextHasBorder: stampVM.stampTextHasBorder,
                        wordmarkTopInset: 54,
                        renderOnlyStamp: renderOnlyStamp,
                        renderOnlyText: false
                    )
                    .frame(width: previewVidW, height: 375.0)
                    .preferredColorScheme(.dark)
                    let r = ImageRenderer(content: v)
                    r.scale = RouteVideoExportService.renderScale
                    return r.uiImage
                }

                // 스탬프 레이어
                if let img = renderStampImage(renderOnlyStamp: true, renderOnlyText: false) {
                    exportStampLayers.append(RouteVideoExportService.StampLayerConfig(
                        image: img,
                        entranceMode: stampVM.stampEntranceMode,
                        flyDirection: stampVM.stampFlyDirection,
                        startTime: stampStart,
                        animDuration: 0.55
                    ))
                }
                // 문구 레이어 (문구가 있을 때만)
                if !stampVM.stampText.isEmpty,
                   let img = renderStampImage(renderOnlyStamp: false, renderOnlyText: true) {
                    exportStampLayers.append(RouteVideoExportService.StampLayerConfig(
                        image: img,
                        entranceMode: stampVM.stampTextEntranceMode,
                        flyDirection: stampVM.stampTextFlyDirection,
                        startTime: textStart,
                        animDuration: 0.45
                    ))
                }
                // 로고 정적 레이어 — stamp 모드에서만 필요 (VideoOverlayCard 없이 합성 시)
                if let logoImg = makeStampLogoOverlay(renderSize: VideoExportService.targetSize, date: stampVM.showDate ? activity.date : nil) {
                    exportStampLayers.append(RouteVideoExportService.StampLayerConfig(
                        image: logoImg,
                        entranceMode: .none,
                        flyDirection: .trailing,
                        startTime: 0,
                        animDuration: 0.0
                    ))
                }
            }

            url = try await RouteVideoExportService.exportFast(
                snapshot: snap,
                snapshotPoints: routeSnapshotPoints,
                distanceKm: distanceKmString,
                duration: activity.formattedDuration,
                date: activity.date,
                metrics: Array(enabledMetricItems.prefix(6)),
                raceName: activeRaceName,
                routeMarkerImage: miniMeStore.image,
                weather: condition?.weather,
                shoeName: displayShoeName,
                chartPanel: cardPanel,
                chartSplits: detail?.splits ?? [],
                chartHRSamples: shareHRSamples,
                chartHRZones: detail?.hrZones ?? [],
                chartWorkoutSeries: shareWorkoutSeries,
                chartIntervalSegments: detail?.intervalSegments ?? [],
                summaryLines: cardSummaryLines,
                totalDistanceM: activity.distance,
                hrSamplesForRoute: shareHRSamples,
                routeWorkoutDuration: activity.duration,
                showHRGradient: showHRGradientForRoute,
                stampLayers: exportStampLayers,
                progressHandler: { p in routeVideoProgress = p }
            )
            routeVideoFile = SharableVideoFile(url: url)
            showRouteVideoShareSheet = true
        } catch { }
        isExportingRouteVideo = false
    }

    // Extracted from .task {} to keep the closure trivial and avoid type-checker timeouts.
    @MainActor
    private func onAppear() async {
        // Restore selected photo from stored data on re-entry (e.g. after app restart).
        // Without this, selectedPhoto stays nil and the legacy all-cards branch fires.
        if !storyPhotos.isEmpty {
            for c in ShareCard.photoLinked where cardPhotoIndex[c] == nil {
                cardPhotoIndex[c] = 0
            }
        }
        // Load stable photo UUIDs from SwiftData (used by OneLinerEntry cross-references)
        if oneLinerVM.storyPhotoUUIDs.isEmpty {
            oneLinerVM.storyPhotoUUIDs = story?.sortedPhotoUUIDs ?? []
        }
        // Pre-populate oneLinerVM.cachedStoryRecipes from disk so preview shows saved state immediately,
        // avoiding a visible flash before the first edit dismiss populates the cache.
        if oneLinerVM.cachedStoryRecipes.isEmpty, !oneLinerVM.storyPhotoUUIDs.isEmpty {
            oneLinerVM.cachedStoryRecipes = makeStoryClipRecipes(isSlide: template == .slide)
        }
        // Auto-select first available panel when no route
        if routeCoords.isEmpty && cardPanel == .map {
            let first = CardChartPanel.allCases.first { isChartPanelAvailable($0) }
            cardPanel = first ?? .splits
        }
        deduplicateOneLinerEntries()
        loadOneLinerSettings()
        loadPlaceableStoryOverlay()
        // isPlaceable 무관하게 항상 로드 — 함수 내부에 isEmpty guard 있어 이중 로드 없음.
        // Placeable(UserDefaults)·OneLiner(SwiftData) 중 어느 저장소에 클립이 있어도
        // 초기 진입 카드와 무관하게 propagateClips가 작동하도록 미리 채움.
        if template == .video {
            loadPlaceableVideoClips()
            // 로드 직후 전역 스타일(sizeLevel 등)을 클립에 즉시 동기화.
            // onChange(of: count)는 비동기 발화라 로드~첫 렌더 사이 sizeLevel 불일치 발생 가능.
            applyStyleToVideoClips()
        }
        // 두 저장소에서 로드한 클립 순서가 다를 경우 즉시 동기화
        // onChange(of: count)는 카운트 불변 시 발화 안 하므로 여기서 명시적으로 처리
        if let clips = [placeableVM.placeableClipRecipes, oneLinerVM.oneLinerClipRecipes]
                .first(where: { !$0.isEmpty }) {
            propagateClips(clips)
        }
        loadStampConfig()
        loadAthleticCropOffsets()
        if isStamp { await loadStampClipRecipes() }
        // Stamp 저장소가 비어있어도 propagate된 클립이 있으면 프리뷰 빌드 + 저장소 동기화
        if isStamp, template == .video, !stampVM.clipRecipes.isEmpty {
            let data = stampPreviewData
            await loadStampVideoPreview(data: data)
            saveStampConfig()
        }
        await loadHighQualityPhotos()
        // Placeable 슬라이드: 자동 빌드 없음 — ▶ 버튼을 눌러야 빌드·재생 시작 (스탬프 슬라이드 패턴).
        if isStamp, template == .slide, !storyPhotos.isEmpty {
            let data = stampPreviewData
            Task { await loadStampSlidePreview(data: data) }
        }
        // HR 시계열 미리 로드 — 공유 카드 경로 그라데이션용 (패널 무관)
        if activity.avgHeartRate != nil, let mgr = manager, shareHRSamples.isEmpty {
            shareHRSamples = await mgr.fetchHRTimeSeries(for: activity.id)
        }
        // 차트 시계열 fetch (케이던스·지면접촉·보폭·수직진폭·파워 + 고도)
        if chartSeriesData.isEmpty, let mgr = manager {
            async let cadence = mgr.fetchCadenceTimeSeries(for: activity.id)
            async let stride  = mgr.fetchWorkoutTimeSeries(for: activity.id, identifier: .runningStrideLength, unit: .meter())
            async let vo      = mgr.fetchWorkoutTimeSeries(for: activity.id, identifier: .runningVerticalOscillation, unit: .meterUnit(with: .centi))
            var newData: [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:]
            let (cad, strRes, voRes) = await (cadence, stride, vo)
            if cad.count    >= 2 { newData[.cadence]             = cad    }
            if strRes.count >= 2 { newData[.strideLength]        = strRes }
            if voRes.count  >= 2 { newData[.verticalOscillation] = voRes  }
            // 고도: ActivityDetail에서 바로 가져옴
            if let alt = detail?.altitudeTimeProfile, alt.count >= 2 {
                newData[.elevation] = alt.map { (offset: $0.offset, value: $0.altitude) }
            }
            chartSeriesData = newData
        }
        await renderCard()
    }

    // MARK: - Athletic 클립 저장/복원 (영상·슬라이드 템플릿 전용)

    private var athleticClipsEntry: OneLinerEntry? {
        allOneLinerEntries.first {
            $0.workoutID == activity.id.uuidString && $0.mediaRef == "athletic:clips"
        }
    }

    private func saveAthleticClipRecipes() {
        let validRecipes = athleticVM.athleticClipRecipes.filter { $0.assetIdentifier != nil }
        if validRecipes.isEmpty {
            if let entry = athleticClipsEntry {
                modelContext.delete(entry)
                try? modelContext.save()
            }
            return
        }
        let descs = validRecipes.map { r in
            SavedClipDescriptor(
                assetID: r.assetIdentifier, clipVideoRef: nil,
                photoRef: nil, thumbRef: r.thumbRef,
                trimStart: r.trimStart, trimEnd: r.trimEnd, fullDuration: r.fullDuration,
                lines: [], fontID: nil, colorID: nil, anchorIdx: nil, sizeID: nil,
                effectID: nil, speed: 1.0, cropOffsetX: 0.0,
                metricPace: false, metricDistance: false, metricTime: false, metricHeartRate: false,
                pdtAnchorIdx: nil, showRoute: false, routeAnchorIdx: nil, showHRChart: false,
                chartTypeID: nil, pdtSizeID2: nil, dataEffectID: nil)
        }
        let saved = SavedRecipeSet(
            isPhotoSlide: false, muteAudio: athleticVM.athleticMuted, clips: descs,
            videoTitle: "", titleAnchorIdx: nil, titleFontID: nil, titleColorID: nil,
            titleSizeID: nil, titleOutline: false)
        guard let data = try? JSONEncoder().encode(saved),
              let json = String(data: data, encoding: .utf8) else { return }
        let payload = "v4recipes\n" + json
        if let existing = athleticClipsEntry {
            existing.text = payload
        } else {
            let entry = OneLinerEntry(workoutID: activity.id.uuidString, mediaRef: "athletic:clips")
            entry.text = payload
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }

    private func loadAthleticClipRecipes() async {
        guard let entry = athleticClipsEntry,
              entry.text.hasPrefix("v4recipes\n"),
              let data = entry.text.dropFirst("v4recipes\n".count).data(using: .utf8),
              let saved = try? JSONDecoder().decode(SavedRecipeSet.self, from: data),
              !saved.clips.isEmpty else { return }
        athleticVM.athleticMuted = saved.muteAudio
        var restored: [ClipRecipe] = []
        for desc in saved.clips {
            guard let assetID = desc.assetID,
                  let avAsset = try? await MultiClipComposition.resolveAVAsset(assetID: assetID)
            else { continue }
            let url = (avAsset as? AVURLAsset)?.url
                ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("mimo_ath_\(UUID().uuidString).mov")
            // ClipThumbStore 디스크 캐시 우선 — PHAsset이 AVURLAsset이 아닌 경우에도 썸네일 표시
            let thumb: UIImage?
            if let tr = desc.thumbRef, let stored = ClipThumbStore.load(ref: tr) {
                thumb = stored
            } else {
                thumb = await VideoExportService.firstFrame(of: url)
            }
            var recipe = ClipRecipe(url: url, fullDuration: desc.fullDuration, thumbnail: thumb)
            recipe.trimStart      = desc.trimStart
            recipe.trimEnd        = desc.trimEnd
            recipe.assetIdentifier = assetID
            recipe.resolvedAsset  = avAsset
            restored.append(recipe)
        }
        guard !restored.isEmpty else { return }
        athleticVM.athleticClipRecipes = restored
        if let firstThumb = restored.first?.thumbnail {
            videoPreviewImage = firstThumb
        }
        // sourceVideoURL이 nil이면 guard let url = sourceVideoURL (exportVideo) 에서 조기 종료됨
        if sourceVideoURL == nil {
            sourceVideoURL = restored.first?.url
        }
        if template != .video { template = .video }
    }

    @MainActor
    func renderCard(showSpinner: Bool = true) async {
        // Placeable card: static image render. 스토리 다사진이면 전체 storyShareImages 생성.
        if card == .placeable {
            if showSpinner { isRendering = true }
            storyShareImages = []
            previewImage = nil
            if template == .photo, storyPhotos.count > 1 {
                // 각 사진마다 해당 사진의 문구를 넣어 렌더링
                var rendered: [UIImage] = []
                for (i, photo) in storyPhotos.enumerated() {
                    let t = placeableVM.placeableStoryTexts[i] ?? ""
                    let r = ImageRenderer(content: placeableExportView(photo: photo, text: t, photoIndex: i))
                    r.scale = 3
                    if let img = r.uiImage { rendered.append(img) }
                }
                storyShareImages = rendered
                // 미리보기는 현재 선택 사진
                let curIdx = placeableCurrentPhotoIdx
                previewImage = rendered.indices.contains(curIdx) ? rendered[curIdx] : rendered.first
            } else {
                let photo = template == .video ? videoPreviewImage : photoFor(.placeable)
                let renderer = ImageRenderer(content: placeableExportView(photo: photo))
                renderer.scale = 3
                previewImage = renderer.uiImage
            }
            isRendering = false
            return
        }


        // OneLiner card
        if card == .oneLiner {
            if showSpinner { isRendering = true }
            storyShareImages = []
            previewImage = nil
            let idx   = cardPhotoIndex[.oneLiner]
            let photo = idx.flatMap { storyPhotos.indices.contains($0) ? storyPhotos[$0] : nil }
                     ?? (!storyPhotos.isEmpty ? storyPhotos[0] : nil)
            // @Query 갱신 타이밍 이슈 우회: 편집 직후엔 oneLinerVM.cachedStoryRecipes 사용
            let pr: ClipRecipe?
            let prIdx = idx ?? 0
            if !oneLinerVM.cachedStoryRecipes.isEmpty, oneLinerVM.cachedStoryRecipes.indices.contains(prIdx) {
                pr = oneLinerVM.cachedStoryRecipes[prIdx]
            } else {
                pr = photoRecipe(at: prIdx, prefix: template == .slide ? "slide:" : "photo:")
            }
            let cropX = oneLinerVM.oneLinerStoryCropOffsets[prIdx]
                     ?? CGFloat(pr?.cropOffsetX ?? 0.5)
            let text  = pr?.lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n") ?? oneLinerVM.oneLinerText
            let card = OneLinerCard(
                activity: activity,
                backgroundPhoto: photo,
                cropOffsetX: cropX,
                text: text,
                position: pr?.position ?? oneLinerVM.oneLinerPosition,
                textColor: pr?.textColor ?? oneLinerVM.oneLinerColor,
                fontChoice: pr?.fontChoice ?? oneLinerVM.oneLinerFont,
                sizeLevel: pr?.sizeLevel ?? .large,
                appearanceMode: pr?.appearanceMode ?? .typing,
                decorEffect: pr?.decorEffect ?? .none,
                hasBorder: pr?.hasBorder ?? false,
                captionMode: true,
                chartBottomReserved: storyChartBottomReserved(for: pr),
                isStaticPreview: true,   // ImageRenderer는 onAppear/애니 없이 초기 상태만 캡처 → 즉시 표시 필요
                metricPace: pr?.metricPace ?? false,
                metricDistance: pr?.metricDistance ?? false,
                metricTime: pr?.metricTime ?? false,
                metricHeartRate: pr?.metricHeartRate ?? false,
                pdtPosition: pr?.pdtPosition ?? .bottomLeading,
                pdtSizeLevel: pr?.pdtSizeLevel ?? .medium,
                availableMetrics: oneLinerAvailableMetrics,
                showRoute: pr?.showRoute ?? false,
                routeCoords: routeCoords,
                routePosition: pr?.routePosition ?? .bottomTrailing,
                showHRChart: pr?.showHRChart ?? false,
                hrSamples: shareHRSamples,
                hrZones: detail?.hrZones ?? [],
                chartOverlayType: pr?.chartOverlayType ?? .none,
                chartSeriesData: chartSeriesData,
                chartSplits: detail?.splits ?? [],
                intervalSegments: detail?.intervalSegments ?? []
            )
            let renderer = ImageRenderer(content: card.frame(width: 300, height: 375))
            renderer.scale = 3
            previewImage = renderer.uiImage
            isRendering = false
            return
        }

        // Stamp card: on-demand export via makeStampStoryImage() in the share button.
        // For story template, pre-render here (async context) so the SwiftUI ImageRenderer
        // pipeline is warmed before the user taps share.  First-ever ImageRenderer call for
        // a view tree produces a black image; the 50 ms gap after the warm-up render lets
        // the pipeline fully initialize, making the synchronous share-button render correct.
        if isStamp {
            if template == .photo {
                // 이전 다중-사진 내보내기 캐시를 무효화. 여기를 지나면 내보내기 버튼이 항상 fresh 렌더 경로를 탐.
                storyShareImages = []
                previewImage = nil
                let photo = storyPhotos.first
                // baseConfig는 position·template 등 스타일 setter가 항상 최신값으로 갱신하지만,
                // stampText는 per-photo라 currentConfig에만 저장되고 baseConfig.text는 빈 문자열.
                // 두 값을 병합: 스타일은 baseConfig, 문구는 currentConfig.text.
                var cfg = stampVM.baseConfig
                cfg.text = stampVM.currentConfig.text
                let wuView = StampStoryRenderView(
                    photo: photo, data: stampPreviewData, vm: stampVM,
                    cropOffsetX: stampVM.storyCropOffsetX,
                    configOverride: cfg).frame(width: 300, height: 375)
                let wu = ImageRenderer(content: wuView)
                wu.scale = 1
                _ = wu.uiImage
                try? await Task.sleep(nanoseconds: 50_000_000)   // 50 ms — let pipeline settle
                guard isStamp, template == .photo else { return } // guard: card may have changed
                previewImage = makeStampStoryImage(
                    photo: photo, data: stampPreviewData, vm: stampVM,
                    cropOffsetX: stampVM.storyCropOffsetX,
                    configOverride: cfg)
            }
            isRendering = false; return
        }

        guard template != .video && template != .routeVideo else { return }
        if showSpinner { isRendering = true }
        storyShareImages = []
        previewImage = nil

        // Use in-memory array if available (avoids @Query timing gap); fall back to disk on restart.
        // Athletic card + story template: render athletic card with selected photo background.
        // Share only the single rendered card (no extra plain photos).
        if template == .photo, let selPhoto = photoFor(.athletic) {
            let renderer = ImageRenderer(content:
                AthleticCard(activity: activity, routeCoordinates: routeCoords,
                              metrics: enabledMetricItems,
                              raceName: activeRaceName,
                              chartPanel: cardPanel,
                              chartSplits: detail?.splits ?? [],
                              chartHRSamples: shareHRSamples,
                              chartHRZones: detail?.hrZones ?? [],
                              chartWorkoutSeries: shareWorkoutSeries,
                              chartIntervalSegments: detail?.intervalSegments ?? [],
                              weather: condition?.weather,
                              shoeName: displayShoeName,
                              photo: selPhoto,
                              cropOffsetX: athleticCropOffsetX,
                              summaryLines: cardSummaryLines)
                    .frame(width: 300, height: 375)
            )
            renderer.scale = 3
            guard let cardImg = renderer.uiImage else { isRendering = false; return }
            previewImage = cardImg
            storyShareImages = []
            isRendering = false
            return
        }


        let renderer = ImageRenderer(content: renderableCard())
        renderer.scale = 3
        guard let img = renderer.uiImage else {
            isRendering = false
            return
        }
        previewImage = img
        isRendering = false
    }

    @ViewBuilder
    private func renderableCard() -> some View {
        switch template {
        case .record:
            AthleticCard(activity: activity, routeCoordinates: routeCoords,
                          metrics: enabledMetricItems,
                          raceName: activeRaceName,
                          chartPanel: cardPanel,
                          chartSplits: detail?.splits ?? [],
                          chartHRSamples: shareHRSamples,
                          chartHRZones: detail?.hrZones ?? [],
                          chartWorkoutSeries: shareWorkoutSeries,
                          chartIntervalSegments: detail?.intervalSegments ?? [],
                          weather: condition?.weather,
                          shoeName: displayShoeName,
                          photo: nil,
                          summaryLines: cardSummaryLines,
)
                .frame(width: 300, height: 375)
        case .photo:
            if let photo = photoFor(.oneLiner) {
                PhotoShareCardView(activity: activity, photo: photo,
                                   metrics: enabledMetricItems, raceName: activeRaceName,
                                   routeCoordinates: routeCoords,
                                   chartPanel: cardPanel,
                                   chartSplits: detail?.splits ?? [],
                                   chartHRSamples: shareHRSamples,
                                   chartHRZones: detail?.hrZones ?? [],
                                   chartWorkoutSeries: shareWorkoutSeries,
                                   chartIntervalSegments: detail?.intervalSegments ?? [],
                                   weather: condition?.weather,
                                   shoeName: displayShoeName,
                                   summaryLines: cardSummaryLines,
                                   photoOffset: .constant(photoOffset))
                    .frame(width: 300, height: 375)
            } else if let s = story {
                StoryShareCardView(activity: activity, routeCoordinates: routeCoords,
                                   story: s,
                                   metrics: enabledMetricItems,
                                   raceName: activeRaceName,
                                   chartPanel: cardPanel,
                                   chartSplits: detail?.splits ?? [],
                                   chartHRSamples: shareHRSamples,
                                   chartHRZones: detail?.hrZones ?? [],
                                   chartWorkoutSeries: shareWorkoutSeries,
                                   chartIntervalSegments: detail?.intervalSegments ?? [],
                                   weather: condition?.weather,
                                   shoeName: displayShoeName,
                                   summaryLines: cardSummaryLines,
)
                    .frame(width: 300, height: 375)
            } else {
                AthleticCard(activity: activity, routeCoordinates: routeCoords,
                              metrics: enabledMetricItems,
                              raceName: activeRaceName,
                              chartPanel: cardPanel,
                              chartSplits: detail?.splits ?? [],
                              chartHRSamples: shareHRSamples,
                              chartHRZones: detail?.hrZones ?? [],
                              chartWorkoutSeries: shareWorkoutSeries,
                              chartIntervalSegments: detail?.intervalSegments ?? [],
                              weather: condition?.weather,
                              shoeName: displayShoeName,
                              summaryLines: cardSummaryLines)
                    .frame(width: 300, height: 375)
            }
        case .video, .slide, .routeVideo:
            EmptyView()
        }
    }

    // MARK: - Photo persistence

    private func persistStoryPhotos(_ images: [UIImage], uuids: [String]? = nil) {
        let capped = Array(images.prefix(5))
        guard !capped.isEmpty else { return }
        let makePhoto: (Int, UIImage) -> StoryPhoto? = { idx, img in
            guard let data = StoryPhoto.thumbnailData(from: img) else { return nil }
            #if DEBUG
            let sizeKB = data.count / 1024
            print("[StoryPhoto] 저장 크기=\(sizeKB)kB\(sizeKB <= 300 ? " ✓300KB 이하" : " ⚠️300KB 초과")")
            #endif
            let uuid = uuids?[safe: idx] ?? UUID().uuidString
            return StoryPhoto(data: data, index: idx, uuid: uuid)
        }
        if let s = story {
            for photo in s.photos ?? [] { modelContext.delete(photo) }
            s.photos = nil
            let newPhotos = capped.enumerated().compactMap { makePhoto($0.offset, $0.element) }
            newPhotos.forEach { modelContext.insert($0) }
            s.photos = newPhotos.isEmpty ? nil : newPhotos
            s.updatedAt = Date()
        } else {
            let s = WorkoutStory(workoutID: activity.id.uuidString)
            modelContext.insert(s)
            let newPhotos = capped.enumerated().compactMap { makePhoto($0.offset, $0.element) }
            newPhotos.forEach { modelContext.insert($0) }
            s.photos = newPhotos
        }
        try? modelContext.save()
    }

    // MARK: - High-quality photo loading from PHAsset

    /// Loads full-res images from Photos library for cross-session rendering quality.
    /// PHAsset localIdentifiers contain "/"; random UUIDs don't — used to distinguish.
    private func loadHighQualityPhotos() async {
        guard let sortedPhotos = story?.photos?.sorted(by: { $0.index < $1.index }) else { return }
        for (idx, photo) in sortedPhotos.enumerated() {
            guard photo.photoUUID.contains("/") else { continue }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [photo.photoUUID], options: nil)
            if assets.count == 0 {
                oneLinerVM.deletedPhotoIndices.insert(idx)
                continue
            }
            guard let asset = assets.firstObject else { continue }
            if let img = await loadImageFromPHAsset(asset) {
                oneLinerVM.highQualityStoryPhotos[idx] = img
            }
        }
    }

    private func loadImageFromPHAsset(_ asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat  // called exactly once
            options.isNetworkAccessAllowed = false      // local only; iCloud-only → nil
            options.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1800, height: 1800),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                cont.resume(returning: image)
            }
        }
    }

    private func clearStoryPhoto() {
        if let s = story {
            for photo in s.photos ?? [] { modelContext.delete(photo) }
            s.photos = nil
            s.updatedAt = Date()
            try? modelContext.save()
        }
    }

    /// 썸네일 X 버튼 — 특정 인덱스의 사진을 스토리에서 삭제하고 카드 인덱스를 정리.
    private func deleteStoryPhoto(at index: Int) {
        let allPhotos = allPickedPhotos.isEmpty ? storyPhotos : allPickedPhotos
        guard index < allPhotos.count else { return }
        var newPhotos = allPhotos
        newPhotos.remove(at: index)

        var newUUIDs = oneLinerVM.storyPhotoUUIDs
        if index < newUUIDs.count { newUUIDs.remove(at: index) }
        oneLinerVM.storyPhotoUUIDs = newUUIDs

        // oneLinerVM.highQualityStoryPhotos 인덱스 재매핑
        var remapped: [Int: UIImage] = [:]
        for (k, v) in oneLinerVM.highQualityStoryPhotos where k != index {
            remapped[k > index ? k - 1 : k] = v
        }
        oneLinerVM.highQualityStoryPhotos = remapped

        // oneLinerVM.deletedPhotoIndices 재매핑
        oneLinerVM.deletedPhotoIndices = Set(oneLinerVM.deletedPhotoIndices.compactMap { idx -> Int? in
            if idx == index { return nil }
            return idx > index ? idx - 1 : idx
        })

        if newPhotos.isEmpty {
            allPickedPhotos = []
            clearStoryPhoto()
            for c in ShareCard.photoLinked { cardPhotoIndex[c] = nil }
        } else {
            allPickedPhotos = newPhotos
            persistStoryPhotos(newPhotos, uuids: newUUIDs)
            // 삭제된 인덱스 기준으로 카드 인덱스 보정
            for c in ShareCard.photoLinked {
                guard let idx = cardPhotoIndex[c] else { continue }
                if idx >= newPhotos.count { cardPhotoIndex[c] = max(0, newPhotos.count - 1) }
                else if idx > index { cardPhotoIndex[c] = idx - 1 }
            }
        }
        if template == .slide { previewPlayer.invalidate() }
        Task { await renderCard() }
    }

}

// MARK: - Story photo picker sheet (stored photos only)

private struct StoryPhotoPickerSheet: View {
    let photos: [UIImage]
    let selected: UIImage?
    let onSelect: (UIImage, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { idx, photo in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(photo, idx) }

                            if photo == selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Theme.violet)
                                    .background(Circle().fill(.white).padding(2))
                                    .padding(6)
                            }
                        }
                    }
                }
                .padding(4)
            }
            .navigationTitle(AppLanguage.shared.s("사진 선택", "Select Photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.shared.s("취소", "Cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// struct ShareSheet → ShareSheet.swift

// 영상 파일을 공유하고 완료/취소 후 onComplete 호출 (임시 파일 삭제용)
// MARK: - Collection safe subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
