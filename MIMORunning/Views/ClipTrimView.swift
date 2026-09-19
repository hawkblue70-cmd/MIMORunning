import SwiftUI
import UIKit
import AVFoundation
import AVKit
import PhotosUI
import CoreLocation

// MARK: - ClipTrimSheet
//
// Multi-clip edit sheet with swipeable preview carousel (TabView/page).
// All clips are copied locally on open; edits to workingRecipes are committed
// to the binding only on "완료". "취소" discards all changes.
// Swiping between clips auto-saves within the local session (no explicit commit step).

struct ClipTrimSheet: View {
    @Binding var recipes: [ClipRecipe]
    @Binding var selectedClipIndex: Int
    var hideTimePicker:    Bool = false
    var isStoryMode:       Bool = false
    /// true = 사진 슬라이드(9:16 출력) → 프리뷰를 실제 출력 비율로 표시
    var isPhotoSlideMode:  Bool = false
    /// 러닝 데이터 오버레이용 (운동한 날). 빈 값 = 쉬는날(토글 숨김).
    var availableMetrics: [MetricItem] = []
    var routeCoords:      [CLLocationCoordinate2D] = []
    var hrSamples:         [(offset: TimeInterval, bpm: Int)] = []
    var splits:            [SplitData] = []
    var chartSeriesData:   [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:]
    var hrZones:           [HRZoneData] = []
    var intervalSegments:  [IntervalSegment] = []
    /// Full-video title shown in non-story clip previews (scaled to previewScale).
    var videoTitle:     String              = ""
    var titleStyle:     OneLinerTitleStyle  = OneLinerTitleStyle()
    /// "완료" 직후 새 recipes를 직접 전달하는 콜백.
    /// clipRecipes @State 갱신을 기다리지 않고 toSave 값을 그대로 전달하여 저장 타이밍 문제를 우회한다.
    var onCommit: (([ClipRecipe]) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    // Local working copies — written back to recipes binding only on "완료"
    // init에서 즉시 초기화해 첫 렌더부터 currentRecipeValid == true 보장
    @State private var workingRecipes:      [ClipRecipe]
    @State private var currentPage:         Int
    @State private var userAddedLines:      Int = 0
    @State private var cropDragBase:        [Int: CGFloat] = [:]
    @State private var pageForward:         Bool = true

    init(
        recipes:           Binding<[ClipRecipe]>,
        selectedClipIndex: Binding<Int>,
        hideTimePicker:    Bool                              = false,
        isStoryMode:       Bool                              = false,
        isPhotoSlideMode:  Bool                              = false,
        availableMetrics:  [MetricItem]                     = [],
        routeCoords:       [CLLocationCoordinate2D]         = [],
        hrSamples:         [(offset: TimeInterval, bpm: Int)] = [],
        splits:            [SplitData]                       = [],
        chartSeriesData:   [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:],
        hrZones:           [HRZoneData]                      = [],
        intervalSegments:  [IntervalSegment]                 = [],
        videoTitle:        String                            = "",
        titleStyle:        OneLinerTitleStyle                = OneLinerTitleStyle(),
        onCommit:          (([ClipRecipe]) -> Void)?         = nil
    ) {
        _recipes           = recipes
        _selectedClipIndex = selectedClipIndex
        self.hideTimePicker   = hideTimePicker
        self.isStoryMode      = isStoryMode
        self.isPhotoSlideMode = isPhotoSlideMode
        self.availableMetrics = availableMetrics
        self.routeCoords      = routeCoords
        self.hrSamples        = hrSamples
        self.splits           = splits
        self.chartSeriesData  = chartSeriesData
        self.hrZones          = hrZones
        self.intervalSegments = intervalSegments
        self.videoTitle       = videoTitle
        self.titleStyle       = titleStyle
        self.onCommit         = onCommit
        let r   = recipes.wrappedValue
        let idx = max(0, min(selectedClipIndex.wrappedValue, r.count - 1))
        _workingRecipes = State(initialValue: r)
        _currentPage    = State(initialValue: idx)
    }

    // 단일 위치 그리드 모드: false = 문구, true = 데이터(러닝)
    @State private var gridDataMode: Bool = false

    // Single-clip replacement pickers
    @State private var replacePhotoPicker: [PhotosPickerItem] = []
    @State private var replaceVideoPicker: [PhotosPickerItem] = []

    // 시트 내 독립 PHAsset 해석 — 부모 binding 해석 완료 전 시트가 열려도 영상 표시
    @State private var resolvingIDs: Set<String> = []

    // 클립별 미리보기 정지 프레임 (AVAsset 해석 전 배경 표시용)
    @State private var sheetPreviewFrames:  [Int: UIImage] = [:]
    @State private var frameLoadingIdx:     Set<Int>       = []
    // 딕셔너리 @State 변경 시 SwiftUI re-render 보장: 캡처 카피에서 쓸 때 감지 강제
    @State private var sheetPreviewVersion: Int            = 0

    // 해석 실패(notFound) 클립 추적 — 무한 스피너 방지
    @State private var failedClipIDs:    Set<String> = []
    @State private var showReAddAlert:   Bool         = false

    // MARK: - Current-page accessors

    private var currentRecipeValid: Bool {
        workingRecipes.indices.contains(currentPage)
    }

    private var isPhotoClip: Bool {
        currentRecipeValid && workingRecipes[currentPage].storedPhotoRef != nil
    }

    private var charLimit: Int { 30 }

    private var projectedCount: Int {
        guard currentRecipeValid else { return 0 }
        return projectedCountFor(workingRecipes[currentPage])
    }

    private func projectedCountFor(_ recipe: ClipRecipe) -> Int {
        if recipe.storedPhotoRef != nil || isStoryMode {
            // Show rows 0...lastNonEmpty so user-added lines are never hidden on re-open
            let lastNonEmpty = recipe.lines.indices.reversed()
                .first { !recipe.lines[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return max(1, (lastNonEmpty ?? -1) + 1)
        }
        return min(10, max(2, Int(max(0.1, recipe.trimEnd - recipe.trimStart) / 6.0)))
    }

    private func textAlignmentFor(_ recipe: ClipRecipe) -> TextAlignment {
        switch recipe.position {
        case .topTrailing, .trailing, .bottomTrailing: return .trailing
        case .topLeading,  .leading,  .bottomLeading:  return .leading
        default: return .center
        }
    }

    // UIKit NSLayoutManager로 줄 바꿈 위치를 계산해 명시적 \n 삽입.
    // CALayer(UIKit)와 SwiftUI가 같은 폰트·크기에서 자폭을 다르게 측정하므로
    // 편집 프리뷰를 UIKit 기준으로 강제해 애니메이션 미리보기와 줄 바꿈을 맞춘다.
    private func uikitLineBreakText(_ text: String, uiFont: UIFont, maxWidth: CGFloat) -> String {
        text.components(separatedBy: "\n").map { para -> String in
            guard !para.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return para }
            let storage = NSTextStorage(string: para, attributes: [.font: uiFont])
            let manager = NSLayoutManager()
            storage.addLayoutManager(manager)
            let container = NSTextContainer(size: CGSize(width: maxWidth, height: 100_000))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            _ = manager.glyphRange(for: container)
            var lines: [String] = []
            var gi = 0
            while gi < manager.numberOfGlyphs {
                var gr = NSRange()
                manager.lineFragmentRect(forGlyphAt: gi, effectiveRange: &gr)
                let cr = manager.characterRange(forGlyphRange: gr, actualGlyphRange: nil)
                lines.append((para as NSString).substring(with: cr).trimmingCharacters(in: .newlines))
                gi = NSMaxRange(gr)
            }
            return lines.isEmpty ? para : lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func lineCount(at i: Int) -> Int {
        guard currentRecipeValid, i < workingRecipes[currentPage].lines.count else { return 0 }
        return workingRecipes[currentPage].lines[i].count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            editScrollView
                .scrollDismissesKeyboard(.interactively)
                .background(Color(hex: "0E0E18").ignoresSafeArea())
                .navigationTitle(AppLanguage.shared.s("클립 편집", "Edit Clip"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { clipEditToolbar }
        }
        .onAppear {
            // init의 State(initialValue:) 외에도 onAppear에서 재동기화:
            // SwiftUI가 시트 view identity를 재사용할 경우 init이 재호출되지 않아 State가
            // 이전 세션 값을 유지할 수 있음 → 매 진입마다 binding 최신값으로 덮어쓴다.
            let fresh  = recipes
            let newIdx = max(0, min(selectedClipIndex, max(0, fresh.count - 1)))
            workingRecipes = fresh
            currentPage    = newIdx
            gridDataMode   = false  // 이전 세션 data mode 잔류 방지 → 항상 문구 패널로 시작
            FontLoader.registerBundledFonts()
            for i in workingRecipes.indices {
                resolveClipInSheet(i)
                resolvePreviewFrame(i)  // PHAsset 포스터 프레임 → 해석 전 배경 즉시 표시
            }
        }
        .onChange(of: currentPage) { _, new in
            selectedClipIndex = new
            resolveClipInSheet(new)
            resolvePreviewFrame(new)
            userAddedLines = 0
        }
        .onChange(of: projectedCount) { _, _ in
            userAddedLines = 0
        }
        .onChange(of: replacePhotoPicker) { _, items in
            guard let item = items.first else { return }
            replacePhotoPicker = []
            replaceCurrentPhoto(item)
        }
        .onChange(of: replaceVideoPicker) { _, items in
            guard let item = items.first else { return }
            replaceVideoPicker = []
            replaceCurrentVideo(item)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .alert("영상을 다시 추가해 주세요", isPresented: $showReAddAlert) {
            Button("확인", role: .cancel) { }
        } message: {
            Text("이 클립의 원본 영상을 찾을 수 없습니다.\n아래 교체 버튼으로 새 영상을 선택해 주세요.")
        }
    }

    // MARK: - Body scroll content

    private var editScrollView: some View {
        ScrollView {
            VStack(spacing: 16) {
                previewCarousel
                VStack(spacing: 6) {
                    if workingRecipes.count > 1 { pageIndicator }
                    if isPhotoClip, !hideTimePicker { photoDurationPicker }
                    if !isPhotoClip, currentRecipeValid { trimSection }
                }
                Divider().padding(.horizontal)
                if currentRecipeValid { textInputSection }
                Divider().padding(.horizontal)
                styleSection
                Spacer(minLength: 16)
            }
            .padding(.top, 8)
            // 배경 탭 시 키보드 해제 — UIKit TapGestureRecognizer를 background UIView에 직접 설치.
            // SwiftUI simultaneousGesture는 편집 메뉴(붙여넣기 등) 탭도 가로채므로 사용 금지.
            .background(KeyboardDismissBackground())
        }
    }

    // MARK: - Preview carousel
    //
    // Story mode  → OneLinerCard (4:5) per page.
    // Video/slide → 9:16 explicit frame per page.
    // Swiping updates currentPage; editing controls below always reflect the current page.

    private var previewCarousel: some View {
        let carouselH: CGFloat = isStoryMode
            ? OneLinerCard.cardHeight + 16
            : CardPreviewFrame.height + 16
        return ZStack {
            clipPreviewPage(currentPage)
                .id(currentPage)
                .transition(.asymmetric(
                    insertion: .move(edge: pageForward ? .trailing : .leading),
                    removal:   .move(edge: pageForward ? .leading  : .trailing)
                ))
        }
        .frame(maxWidth: .infinity, minHeight: carouselH, maxHeight: carouselH)
        .contentShape(Rectangle())
        .clipped()
        // 가로 스와이프 → 페이지 이동 (simultaneousGesture로 crop과 동시 인식)
        // minimumDistance: 60 이상의 확실한 스와이프만 navigation으로 처리
        .simultaneousGesture(
            workingRecipes.count > 1 ? DragGesture(minimumDistance: 60)
                .onEnded { drag in
                    let w = drag.translation.width
                    let h = drag.translation.height
                    guard abs(w) > abs(h) * 1.5 else { return }
                    if w < -60, currentPage < workingRecipes.count - 1 {
                        navigate(to: currentPage + 1)
                    } else if w > 60, currentPage > 0 {
                        navigate(to: currentPage - 1)
                    }
                }
            : nil
        )
    }

    private func navigate(to idx: Int) {
        pageForward = idx >= currentPage
        withAnimation(.easeInOut(duration: 0.25)) { currentPage = idx }
    }

    @ViewBuilder
    private func clipPreviewPage(_ i: Int) -> some View {
        let _ = sheetPreviewVersion  // @State 의존성 강제 등록 → version 변경 시 반드시 re-render
        let recipe = workingRecipes[i]
        if isStoryMode {
            let txt = recipe.lines
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            let cW = OneLinerCard.cardWidth
            let cH = OneLinerCard.cardHeight
            // 차트가 하단에 표시될 때 문구를 차트 제외 공간에 배치하기 위한 예약 높이 계산
            let storyBotPad: CGFloat = 10  // chartBotPad (skipLeafOverlays=true, ps=1.0)
            let storyChartReserved: CGFloat = {
                if recipe.showHRChart && hrSamples.count >= 2 { return cH * 0.264 + storyBotPad }
                if recipe.chartOverlayType == .route && !routeCoords.isEmpty { return cH * 0.264 + storyBotPad }
                if recipe.chartOverlayType == .splits {
                    let fc = splits.filter { $0.distanceM >= 900 }.count
                    if fc >= 2 {
                        let dc = fc > 21 ? fc / 2 : fc
                        return 34 + CGFloat(dc) * 7 + storyBotPad  // ps=1.0 story mode
                    }
                }
                if recipe.chartOverlayType == .intervals {
                    let d = intervalSegments.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                    if d > 0 { return cH * 0.42 + storyBotPad }
                }
                let gt = recipe.chartOverlayType
                if ![.none, .route, .hrChart, .splits, .intervals].contains(gt),
                   let s = chartSeriesData[gt], s.count >= 2 { return cH * 0.264 + storyBotPad }
                return 0
            }()
            let storyCropExcess: CGFloat = {
                guard let t = workingRecipes[i].thumbnail else { return 0 }
                let s = max(cW / t.size.width, cH / t.size.height)
                return max(0, t.size.width * s - cW)
            }()
            ZStack {
                OneLinerCard(
                    backgroundPhoto: recipe.thumbnail,
                    cropOffsetX: workingRecipes[i].cropOffsetX,
                    text: txt,
                    position: recipe.position,
                    textColor: recipe.textColor,
                    fontChoice: recipe.fontChoice,
                    sizeLevel: recipe.sizeLevel,
                    appearanceMode: recipe.appearanceMode,
                    decorEffect: recipe.decorEffect,
                    hasBorder: recipe.hasBorder,
                    captionMode: true,
                    chartBottomReserved: storyChartReserved,
                    isStaticPreview: true,   // 편집 시트는 정적 표시 — 애니 없음
                    metricPace: recipe.metricPace,
                    metricDistance: recipe.metricDistance,
                    metricTime: recipe.metricTime,
                    metricHeartRate: recipe.metricHeartRate,
                    pdtPosition: recipe.pdtPosition,
                    pdtSizeLevel: recipe.pdtSizeLevel,
                    availableMetrics: availableMetrics,
                    showRoute: false,  // 경로는 dataPreviewOverlay 차트 패널이 처리 — 코너 미니맵 중복 방지
                    routeCoords: routeCoords,
                    routePosition: recipe.routePosition,
                    showHRChart: false,  // 차트 패널 오버레이가 처리 — 레거시 HR 흰선 억제
                    hrSamples: hrSamples
                )
                // 차트 패널 오버레이: splits/HR zone/경로/cadence 등 — PDT칩은 OneLinerCard가 담당
                dataPreviewOverlay(recipe, w: cW, maxH: cH, skipLeafOverlays: true)
                    .allowsHitTesting(false)
            }
            .highPriorityGesture(
                storyCropExcess > 0 ? DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        if cropDragBase[i] == nil { cropDragBase[i] = workingRecipes[i].cropOffsetX }
                        guard let base = cropDragBase[i] else { return }
                        workingRecipes[i].cropOffsetX = max(0, min(1,
                            base - drag.translation.width / storyCropExcess))
                    }
                    .onEnded { _ in cropDragBase.removeValue(forKey: i) }
                : nil
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .frame(maxWidth: .infinity)
        } else {
            let maxH: CGFloat  = CardPreviewFrame.width * 16 / 9  // 9:16 좌표계, 4:5 컨테이너에 축소 표시
            let w: CGFloat     = CardPreviewFrame.width
            let displayText    = recipe.lines
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            let align          = textAlignmentFor(recipe)
            ZStack {
                // 영상/사진 배경 — 3상태: 표시가능(frames) / 실패(notFound) / 로딩중
                let assetID = recipe.assetIdentifier
                let isFailed = assetID.map { failedClipIDs.contains($0) } ?? false
                if let frame = sheetPreviewFrames[i] {
                    // ① 정지 프레임 확보됨 → 최우선 표시
                    let fScale  = max(w / frame.size.width, maxH / frame.size.height)
                    let fImgW   = frame.size.width  * fScale
                    let fImgH   = frame.size.height * fScale
                    let fExcess = max(0, fImgW - w)
                    let cropX   = workingRecipes[i].cropOffsetX
                    Image(uiImage: frame)
                        .resizable()
                        .frame(width: fImgW, height: fImgH)
                        .offset(x: -(cropX * fExcess))
                        .frame(width: w, height: maxH, alignment: .topLeading)
                        .clipped()
                        .highPriorityGesture(
                            fExcess > 0 ? DragGesture(minimumDistance: 1)
                                .onChanged { drag in
                                    if cropDragBase[i] == nil { cropDragBase[i] = cropX }
                                    guard let base = cropDragBase[i] else { return }
                                    workingRecipes[i].cropOffsetX = max(0, min(1,
                                        base - drag.translation.width / fExcess))
                                }
                                .onEnded { _ in cropDragBase.removeValue(forKey: i) }
                            : nil
                        )
                } else if isFailed {
                    // ② 해석 실패(notFound) → 재추가 안내
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                        Text("이 영상은 다시 추가해 주세요")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Button("재추가") { showReAddAlert = true }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    .frame(width: w, height: maxH)
                    .background(Color(hex: "1A1A24"))
                } else if let thumb = recipe.thumbnail {
                    // ③ 사진/썸네일 표시 — 사진 클립은 바로 완료, 영상 클립은 해석 중 스피너
                    let tExcessCheck: CGFloat = {
                        let sc = max(w / thumb.size.width, maxH / thumb.size.height)
                        return max(0, thumb.size.width * sc - w)
                    }()
                    clipThumbnailView(thumb: thumb,
                                      isPhoto: recipe.storedPhotoRef != nil,
                                      w: w, h: maxH,
                                      cropOffsetX: recipe.cropOffsetX)
                    .highPriorityGesture(
                        tExcessCheck > 0 ? DragGesture(minimumDistance: 1)
                            .onChanged { drag in
                                if cropDragBase[i] == nil { cropDragBase[i] = recipe.cropOffsetX }
                                guard let base = cropDragBase[i] else { return }
                                workingRecipes[i].cropOffsetX = max(0, min(1,
                                    base - drag.translation.width / tExcessCheck))
                            }
                            .onEnded { _ in cropDragBase.removeValue(forKey: i) }
                        : nil
                    )
                } else {
                    // ④ 해석 중 + 썸네일 없음 → 어두운 배경 + 스피너
                    Color(hex: "1A1A24")
                        .frame(width: w, height: maxH)
                        .overlay(ProgressView().tint(.white).scaleEffect(1.4))
                }
                // ── 워드마크 — size는 scale 보정, top/leading은 CALayer·정적 대기화면과 동일 값 ─
                MIMOWordmark(size: 11 * maxH / CardPreviewFrame.height, onMediaCard: true)
                .padding(.top, 32)    // visual = 32 × scale ≈ 22.5pt (= CALayer wMTopPad 기준)
                .padding(.leading, 20) // visual = 20 × scale ≈ 14.1pt (= CALayer hPad 기준)
                .frame(width: w, height: maxH, alignment: .topLeading)
                .allowsHitTesting(false)
                // previewScale = w/300: 비디오 vScale(1080/300)과 동일 기준으로 비율 맞춤
                let previewScale: CGFloat = w / 300.0
                let scale1080:    CGFloat = w / 1080.0  // 1080px → preview pt 변환
                // 워드마크 존 높이: top(32) + MIMOWordmark 높이(size×2.3) + 하단 여백(6)
                let wMH: CGFloat = ceil(11.0 * 2.3)  // = 26pt (MIMOWordmark(size:11) 실제 높이)
                let base: CGFloat = OneLinerFont.basePt * recipe.fontChoice.sizeScale * recipe.sizeLevel.scale * previewScale
                // Chart-aware 9-grid: 차트 활성화 시 차트 제외한 공간에서 9포지션 작동
                let (clipHasChart, clipChartPanH): (Bool, CGFloat) = {
                    if recipe.showHRChart && hrSamples.count >= 2 { return (true, maxH * 0.264) }
                    if recipe.chartOverlayType == .route && !routeCoords.isEmpty { return (true, maxH * 0.264) }
                    if recipe.chartOverlayType == .splits {
                        let fc = splits.filter { $0.distanceM >= 900 }.count
                        if fc >= 2 {
                            let dc = fc > 21 ? fc / 2 : fc
                            return (true, (34 + CGFloat(dc) * 7) * previewScale)
                        }
                    }
                    if recipe.chartOverlayType == .intervals {
                        let d = intervalSegments.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                        if d > 0 { return (true, maxH * 0.42) }
                    }
                    let gt = recipe.chartOverlayType
                    if ![.none, .route, .hrChart, .splits, .intervals].contains(gt),
                       let s = chartSeriesData[gt], s.count >= 2 { return (true, maxH * 0.264) }
                    return (false, 0)
                }()
                // 제목·문구 겹침 방지: UIKit 실측으로 CALayer와 동일하게 계산
                let titleFontForStack = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale
                let titleHForStack: CGFloat = {
                    guard !videoTitle.isEmpty else { return 0 }
                    let tFont   = titleStyle.fontChoice.uiFont(size: titleFontForStack)
                    let maxW    = w - 40.0 * previewScale  // 20pt 양쪽
                    let tBounds = (videoTitle as NSString).boundingRect(
                        with: CGSize(width: maxW, height: 4000),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: tFont], context: nil)
                    return ceil(tBounds.height) + 20.0 * (w / 1080.0)  // CALayer tLayerH pt 환산
                }()
                // 데이터·문구 공통 기준: 워드마크+제목 아래 콘텐츠 존 시작
                let clipContentBase: CGFloat = {
                    let base = (32 + wMH + 6 + 4) * previewScale  // 68pt
                    var minTop = base
                    if !videoTitle.isEmpty && titleStyle.position.isTop && recipe.position.isTop {
                        minTop = max(minTop, 76 + titleHForStack + 8)
                    }
                    return minTop
                }()
                // 데이터 칩 절대 위치: 제목 있으면 maxH 28%, 없으면 워드마크 아래
                // export H * 0.28 = 537px, preview maxH * 0.28 = 149pt — 동일 28% 비율로 일치
                let chipAbsTop: CGFloat = (!videoTitle.isEmpty && titleStyle.position.isTop && recipe.pdtPosition.isTop)
                    ? maxH * 0.28
                    : clipContentBase
                // 문구 시작: 데이터 칩이 위쪽이면 칩 높이만큼 아래로 밀기
                let clipContentTop: CGFloat = {
                    guard recipe.position.isTop && recipe.pdtPosition.isTop &&
                          (recipe.metricPace || recipe.metricDistance || recipe.metricTime || recipe.metricHeartRate) else {
                        return clipContentBase
                    }
                    let chipH = 22.0 * previewScale * recipe.pdtSizeLevel.scale
                    return chipAbsTop + chipH + 8 * previewScale
                }()
                // 제목 하단 여백: H * 0.06 = export safeBot (~32pt). 차트가 있으면 차트 영역 확보.
                let titleBottomPad: CGFloat = clipHasChart
                    ? clipChartPanH + 36 * scale1080 + 8
                    : maxH * 0.06
                // 문구 하단 여백: H * 0.06 = export safeBot (~32pt). 아래-아래: 제목 위로 밀기.
                let clipEffBottomPad: CGFloat = clipHasChart
                    ? clipChartPanH + 36 * scale1080 + 8
                    : {
                        guard !videoTitle.isEmpty, titleStyle.position.isBottom, recipe.position.isBottom else { return maxH * 0.06 }
                        return maxH * 0.06 + titleHForStack + 8
                    }()
                let clipContentH: CGFloat   = max(0, maxH - clipContentTop - clipEffBottomPad)
                // 텍스트 없을 때도 위치를 미리볼 수 있도록 플레이스홀더 표시
                let effectiveDisplayText = displayText.isEmpty ? "···" : displayText
                // UIKit 기준 줄 바꿈을 미리 계산해 CALayer 애니메이션 미리보기와 일치시킨다.
                let previewText = displayText.isEmpty ? effectiveDisplayText
                    : uikitLineBreakText(effectiveDisplayText,
                                         uiFont: recipe.fontChoice.uiFont(size: base),
                                         maxWidth: w - 40 * previewScale)
                EffectTextView(
                    text:           previewText,
                    font:           recipe.fontChoice.boldSwiftUIFont(size: base),
                    lineSpacing:    base * 0.1,
                    alignment:      align,
                    color:          recipe.textColor.color,
                    appearanceMode:   recipe.appearanceMode,
                    decorEffect:      recipe.decorEffect,
                    hasBorder:        recipe.hasBorder,
                    flyDirection:     recipe.flyDirection,
                    syntheticBoldStroke: recipe.fontChoice.syntheticBoldStroke(for: base),
                    borderColor:  recipe.hasBorder ? recipe.textColor.borderSwiftColor : .clear,
                    borderOffset: recipe.hasBorder ? max(0.8, base * recipe.textColor.borderOffsetFactor) : 0
                )
                .padding(.horizontal, 20 * previewScale)
                .frame(width: w, height: clipContentH, alignment: recipe.position.alignment)
                .frame(width: w, height: maxH, alignment: .topLeading)
                .offset(y: clipContentTop)
                .opacity(displayText.isEmpty ? 0.35 : 1.0)
                // Full-video title overlay — same scale basis (w/300, w/1080) as clip text.
                if !videoTitle.isEmpty {
                    let tPS:       CGFloat  = w / 300.0
                    let tFontSize           = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale * tPS
                    // 제목 시작: 워드마크 존(32+wMH+6) + 12pt 여백 (= CALayer tFrameY 기준)
                    let titleContentTop: CGFloat = (32 + wMH + 6 + 12) * tPS
                    // 제목 하단은 절대값(titleBottomPad) 기준 — 문구 위치와 무관
                    let titleContentH: CGFloat   = max(0, maxH - titleContentTop - titleBottomPad)
                    let tTextAlign: TextAlignment = {
                        switch titleStyle.position {
                        case .topLeading, .leading, .bottomLeading:    return .leading
                        case .topTrailing, .trailing, .bottomTrailing: return .trailing
                        default: return .center
                        }
                    }()
                    let tColor       = titleStyle.textColor.color
                    let tSynStroke   = titleStyle.fontChoice.syntheticBoldStroke(for: tFontSize)
                    let tHasBorder   = titleStyle.outline
                    let tBorderColor = titleStyle.textColor.borderSwiftColor
                    let tFont        = titleStyle.fontChoice.swiftUIFont(size: tFontSize)
                    let tBorderOff: CGFloat = tHasBorder ? max(0.8, tFontSize * titleStyle.textColor.borderOffsetFactor) : 0
                    // 채움 Text (합성 볼드 포함, 테두리 없을 때만)
                    let tBaseText: Text = {
                        guard !tHasBorder && tSynStroke != 0 else {
                            return Text(videoTitle).font(tFont).foregroundStyle(tColor)
                        }
                        var attr = AttributedString(videoTitle)
                        attr.font = tFont; attr.foregroundColor = tColor
                        attr.uiKit.strokeWidth = tSynStroke; attr.uiKit.strokeColor = UIColor(tColor)
                        return Text(attr)
                    }()
                    // 8방향 오프셋 테두리 — EffectTextView와 동일 기법(§15.3)
                    Group {
                        if tHasBorder {
                            let o = tBorderOff
                            ZStack {
                                Group {
                                    Text(videoTitle).font(tFont).foregroundStyle(tBorderColor).offset(x: -o, y: -o)
                                    Text(videoTitle).font(tFont).foregroundStyle(tBorderColor).offset(x:  o, y: -o)
                                    Text(videoTitle).font(tFont).foregroundStyle(tBorderColor).offset(x: -o, y:  o)
                                    Text(videoTitle).font(tFont).foregroundStyle(tBorderColor).offset(x:  o, y:  o)
                                    Text(videoTitle).font(tFont).foregroundStyle(tBorderColor).offset(x: -o, y:  0)
                                    Text(videoTitle).font(tFont).foregroundStyle(tBorderColor).offset(x:  o, y:  0)
                                    Text(videoTitle).font(tFont).foregroundStyle(tBorderColor).offset(x:  0, y: -o)
                                    Text(videoTitle).font(tFont).foregroundStyle(tBorderColor).offset(x:  0, y:  o)
                                }
                                tBaseText
                            }
                        } else {
                            tBaseText
                        }
                    }
                    .multilineTextAlignment(tTextAlign)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 20 * tPS)   // CALayer hPad = 20 기준
                    .frame(width: w, height: titleContentH, alignment: titleStyle.position.alignment)
                    .frame(width: w, height: maxH, alignment: .topLeading)
                    .offset(y: titleContentTop)
                    .allowsHitTesting(false)
                }
                dataPreviewOverlay(recipe, w: w, maxH: maxH, chipTop: chipAbsTop)
            }
            .frame(width: w, height: maxH)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            // 9:16 콘텐츠를 4:5 컨테이너 안에 비례 축소 (≈211×375pt) — 영상·슬라이드 공통
            .scaleEffect(CardPreviewFrame.height / maxH)
            .frame(width: w * CardPreviewFrame.height / maxH,
                   height: CardPreviewFrame.height)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            Button {
                if currentPage > 0 { navigate(to: currentPage - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(currentPage > 0 ? .white : .white.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 3) {
                ForEach(workingRecipes.indices, id: \.self) { i in
                    Button { navigate(to: i) } label: {
                        Circle()
                            .fill(i == currentPage ? Color.white : Color.white.opacity(0.30))
                            .frame(width: i == currentPage ? 7 : 5,
                                   height: i == currentPage ? 7 : 5)
                            .animation(.easeInOut(duration: 0.15), value: currentPage)
                            .frame(width: 20, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                if currentPage < workingRecipes.count - 1 { navigate(to: currentPage + 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(currentPage < workingRecipes.count - 1 ? .white : .white.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Trim section (video clips)

    @ViewBuilder
    private var trimSection: some View {
        if currentRecipeValid {
            let r      = workingRecipes[currentPage]
            let trimmed = max(0.1, r.trimEnd - r.trimStart)
            HStack(spacing: 8) {
                Text(AppLanguage.shared.s(
                    "\(formatSec(r.trimStart)) – \(formatSec(r.trimEnd))  ·  \(formatSec(trimmed)) 사용",
                    "\(formatSec(r.trimStart)) – \(formatSec(r.trimEnd))  ·  \(formatSec(trimmed)) used"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                PhotosPicker(selection: $replaceVideoPicker,
                             maxSelectionCount: 1, matching: .videos,
                             photoLibrary: .shared()) {
                    Label(AppLanguage.shared.s("영상 교체", "Replace"),
                          systemImage: "video.badge.checkmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            TrimBarView(
                duration:  r.fullDuration,
                trimStart: $workingRecipes[currentPage].trimStart,
                trimEnd:   $workingRecipes[currentPage].trimEnd,
                onEditingEnded: { updateThumbnailAtTrimEnd(currentPage) }
            )
            .padding(.horizontal)

        }
    }

    // MARK: - Text inputs

    private var effectiveLineCount: Int {
        guard currentRecipeValid else { return max(1, projectedCount + userAddedLines) }
        // 이미 저장된 줄이 기본 cap보다 많으면 그만큼 표시 (사용자가 추가한 줄 보존)
        let savedCount = workingRecipes[currentPage].lines.count
        return min(3, max(savedCount, projectedCount) + userAddedLines)
    }

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<effectiveLineCount, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        TextField(
                            AppLanguage.shared.s("\(i + 1)번째 줄", "Line \(i + 1)"),
                            text: lineBinding(for: i),
                            axis: .vertical
                        )
                        .lineLimit(1...2)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .tint(Theme.violet)

                        Text("\(lineCount(at: i))/\(charLimit)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Color(hex: "6E6E78"))
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(hex: "1E1E28"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    if i == effectiveLineCount - 1 && effectiveLineCount < 3 {
                        Button { userAddedLines += 1 } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Theme.violet)
                                .frame(width: 36, height: 36)
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Style section (reads/writes workingRecipes[currentPage])

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                // 왼쪽: [문구|데이터] 토글 + 단일 위치 그리드 + (데이터 모드) P D T B + 모든 클립 적용
                unifiedGridColumn
                // 오른쪽: 문구 모드=텍스트 스타일, 데이터 모드=크기·효과·차트 선택
                if gridDataMode && hasRunData {
                    dataStylePanel
                } else {
                    textStylePanel
                }
            }
            .padding(.horizontal)
        }
    }

    // 문구 모드 오른쪽 패널 (기존 스타일 옵션)
    private var textStylePanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            sizeChips   // 소|중|대|특대|테두리
            if !isStoryMode, !isPhotoClip, currentRecipeValid { speedChips }
            fontChips
            colorCircles
            if !isStoryMode {
                appearanceChips
                if currentRecipeValid {
                    switch workingRecipes[currentPage].appearanceMode {
                    case .fade:  decorChips
                    case .flyIn: flyDirectionChips
                    default:     EmptyView()
                    }
                }
            }
        }
    }

    // 데이터 모드 오른쪽 패널
    // 구조: PDTB / [PDT] 소중대 → 등장방식 → 조건부 / 구분선 / [차트] 선택 → 등장방식 → 조건부
    private var dataStylePanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            if hasRunData { dataMetricPicker }
            pdtSizeChips
            if !isStoryMode {
                pdtAppearanceChips
                if currentRecipeValid {
                    switch workingRecipes[currentPage].pdtAppearanceMode {
                    case .fade:  pdtDecorChips
                    case .flyIn: pdtFlyDirectionChips
                    default:     EmptyView()
                    }
                }
            }
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 2)
            chartGridSection
            if !isStoryMode {
                chartAppearanceChips
                if currentRecipeValid {
                    switch workingRecipes[currentPage].dataAppearanceMode {
                    case .fade:  chartDecorChips
                    case .flyIn: chartFlyDirectionChips
                    default:     EmptyView()
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }


    // 배속 칩: 0.5x / 1x / 1.5x / 2x (현재 클립)
    private var speedChips: some View {
        let speeds: [Double] = [0.5, 1.0, 1.5, 2.0]
        return HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(speeds, id: \.self) { sp in
                let isSel = currentRecipeValid && abs(workingRecipes[currentPage].speed - sp) < 0.01
                Button { if currentRecipeValid { workingRecipes[currentPage].speed = sp } } label: {
                    Text(speedLabel(sp))
                        .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isSel ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08))
                        .foregroundStyle(isSel ? Theme.violet : Color.white.opacity(0.55))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(
                            isSel ? Theme.violet.opacity(0.55) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func speedLabel(_ s: Double) -> String {
        if s == s.rounded() { return "\(Int(s))x" }   // 1x, 2x
        return String(format: "%gx", s)               // 0.5x, 1.5x
    }

    // 오버레이 요소 종류 (위치 그리드 공용)
    private enum OverlayKind { case text, pdt, route }

    private func hasMetric(_ id: String) -> Bool { availableMetrics.contains { $0.id == id } }
    private var pdtEnabled: Bool {
        guard currentRecipeValid else { return false }
        let r = workingRecipes[currentPage]
        return r.metricPace || r.metricDistance || r.metricTime || r.metricHeartRate
    }

    // 겹침 허용 — 사용자가 직접 결정
    private func occupiedCells(excluding kind: OverlayKind) -> Set<CardPosition> { [] }

    private func positionValue(_ kind: OverlayKind) -> CardPosition {
        guard currentRecipeValid else { return .center }
        let r = workingRecipes[currentPage]
        switch kind {
        case .text:  return r.position
        case .pdt:   return r.pdtPosition
        case .route: return r.routePosition
        }
    }
    private func setPosition(_ pos: CardPosition, _ kind: OverlayKind) {
        guard currentRecipeValid else { return }
        switch kind {
        case .text:  workingRecipes[currentPage].position      = pos
        case .pdt:   workingRecipes[currentPage].pdtPosition   = pos
        case .route: workingRecipes[currentPage].routePosition = pos
        }
    }

    // 왼쪽 통합 컬럼: [문구|데이터] 토글 + 단일 위치 그리드
    private var unifiedGridColumn: some View {
        VStack(spacing: 8) {
            if hasRunData { gridModeToggle }
            positionGridFor(gridDataMode ? .pdt : .text)
        }
        .frame(minWidth: 90, alignment: .center)
    }

    // 문구 | 데이터 모드 토글 (그리드 위)
    private var gridModeToggle: some View {
        HStack(spacing: 4) {
            gridModeChip(AppLanguage.shared.s("문구", "Text"), on: !gridDataMode) {
                withAnimation(.easeInOut(duration: 0.12)) { gridDataMode = false }
            }
            gridModeChip(AppLanguage.shared.s("데이터", "Data"), on: gridDataMode) {
                withAnimation(.easeInOut(duration: 0.12)) { gridDataMode = true }
            }
        }
    }
    private func gridModeChip(_ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: on ? .semibold : .regular))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(on ? Theme.violet.opacity(0.22) : Color.white.opacity(0.08))
                .foregroundStyle(on ? Theme.violet : Color.white.opacity(0.55))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(on ? Theme.violet.opacity(0.55) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // 그리드 밑 P D T B 한 줄 (데이터 모드). 탭 = 켜기/끄기. 모두 PDT 공유 위치를 씀.
    // 차트(경로·심박수 등)는 오른쪽 패널 chartGridSection에서 단일 선택.
    private var dataMetricPicker: some View {
        HStack(spacing: 4) {
            if hasMetric("pace")      { smallMetric("P", isOn: recipeBool(\.metricPace),      isTarget: true) { toggleBool(\.metricPace)      } }
            if hasMetric("distance")  { smallMetric("D", isOn: recipeBool(\.metricDistance),  isTarget: true) { toggleBool(\.metricDistance)  } }
            if hasMetric("time")      { smallMetric("T", isOn: recipeBool(\.metricTime),      isTarget: true) { toggleBool(\.metricTime)      } }
            if hasMetric("heartrate") { smallMetric("B", isOn: recipeBool(\.metricHeartRate), isTarget: true) { toggleBool(\.metricHeartRate) } }
        }
    }
    private func smallMetric(_ letter: String, isOn: Bool, isTarget: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(letter)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 24, height: 24)
                .background(Circle().fill(isOn ? Theme.violet : Color.white.opacity(0.08)))
                .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.5))
                .overlay(Circle().strokeBorder(
                    isTarget && isOn ? Color.white : (isOn ? Theme.violet : Color.clear),
                    lineWidth: isTarget && isOn ? 1.6 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 데이터 모드 오른쪽 패널 컴포넌트

    // PDT 뱃지 크기 칩 (소/중/대)
    private var pdtSizeChips: some View {
        let sizes: [TextSizeLevel] = [.small, .medium, .large]
        return HStack(spacing: 6) {
            ForEach(sizes, id: \.self) { s in
                let isSel = currentRecipeValid && workingRecipes[currentPage].pdtSizeLevel == s
                Button { if currentRecipeValid { workingRecipes[currentPage].pdtSizeLevel = s } } label: {
                    Text(s.chipLabel)
                        .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isSel ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08))
                        .foregroundStyle(isSel ? Theme.violet : Color.white.opacity(0.55))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(isSel ? Theme.violet.opacity(0.55) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // 공통 애니메이션 칩 스타일
    private func animChipLabel(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(selected ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08))
                .foregroundStyle(selected ? Theme.violet : Color.white.opacity(0.55))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(selected ? Theme.violet.opacity(0.55) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // PDT 등장 방식 (페이드/날아오기)
    private var pdtAppearanceChips: some View {
        HStack(spacing: 6) {
            ForEach([AppearanceMode.fade, .flyIn], id: \.self) { mode in
                let isSel = currentRecipeValid && workingRecipes[currentPage].pdtAppearanceMode == mode
                animChipLabel(mode.chipLabel, selected: isSel) {
                    guard currentRecipeValid else { return }
                    workingRecipes[currentPage].pdtAppearanceMode = mode
                    if mode == .flyIn { workingRecipes[currentPage].pdtDecorEffect = .none }
                }
            }
        }
    }

    // PDT 꾸밈 효과 (페이드 모드에서만)
    private var pdtDecorChips: some View {
        HStack(spacing: 6) {
            ForEach(DecorEffect.allCases, id: \.self) { fx in
                let isSel = currentRecipeValid && workingRecipes[currentPage].pdtDecorEffect == fx
                animChipLabel(fx.chipLabel, selected: isSel) {
                    guard currentRecipeValid else { return }
                    workingRecipes[currentPage].pdtDecorEffect = fx
                }
            }
        }
    }

    // PDT 날아오기 방향
    private var pdtFlyDirectionChips: some View {
        HStack(spacing: 6) {
            ForEach(FlyInDirection.allCases, id: \.self) { dir in
                let isSel = currentRecipeValid && workingRecipes[currentPage].pdtFlyDirection == dir
                animChipLabel(dir.chipLabel, selected: isSel) {
                    guard currentRecipeValid else { return }
                    workingRecipes[currentPage].pdtFlyDirection = dir
                }
            }
        }
    }

    // 차트 등장 방식 (페이드/날아오기)
    private var chartAppearanceChips: some View {
        HStack(spacing: 6) {
            ForEach([AppearanceMode.fade, .flyIn], id: \.self) { mode in
                let isSel = currentRecipeValid && workingRecipes[currentPage].dataAppearanceMode == mode
                animChipLabel(mode.chipLabel, selected: isSel) {
                    guard currentRecipeValid else { return }
                    workingRecipes[currentPage].dataAppearanceMode = mode
                    if mode == .flyIn { workingRecipes[currentPage].chartDecorEffect = .none }
                }
            }
        }
    }

    // 차트 꾸밈 효과 (페이드 모드에서만)
    private var chartDecorChips: some View {
        HStack(spacing: 6) {
            ForEach(DecorEffect.allCases, id: \.self) { fx in
                let isSel = currentRecipeValid && workingRecipes[currentPage].chartDecorEffect == fx
                animChipLabel(fx.chipLabel, selected: isSel) {
                    guard currentRecipeValid else { return }
                    workingRecipes[currentPage].chartDecorEffect = fx
                }
            }
        }
    }

    // 차트 날아오기 방향
    private var chartFlyDirectionChips: some View {
        HStack(spacing: 6) {
            ForEach(FlyInDirection.allCases, id: \.self) { dir in
                let isSel = currentRecipeValid && workingRecipes[currentPage].chartFlyDirection == dir
                animChipLabel(dir.chipLabel, selected: isSel) {
                    guard currentRecipeValid else { return }
                    workingRecipes[currentPage].chartFlyDirection = dir
                }
            }
        }
    }

    // 차트 종류 그리드 (단일 선택, 2행 × 4열)
    // 미구현 차트는 비활성 표시 — 선택 불가하나 미래 지원 예고.
    private var chartGridSection: some View {
        // (타입, 레이블, 활성여부)
        let charts: [(ChartOverlayType, String, Bool)] = [
            (.route,               AppLanguage.shared.s("경로",   "Route"),   !routeCoords.isEmpty),
            (.hrChart,             AppLanguage.shared.s("심박수",  "HR"),      hrSamples.count >= 2),
            (.splits,              AppLanguage.shared.s("스플릿",  "Splits"),  !splits.isEmpty),
            (.cadence,             AppLanguage.shared.s("케이던스", "Cadnc"),  (chartSeriesData[.cadence]?.count ?? 0) >= 2),
            (.strideLength,        AppLanguage.shared.s("보폭",   "Stride"),  (chartSeriesData[.strideLength]?.count ?? 0) >= 2),
            (.verticalOscillation, AppLanguage.shared.s("수직진폭", "VO"),     (chartSeriesData[.verticalOscillation]?.count ?? 0) >= 2),
            (.elevation,           AppLanguage.shared.s("고도",   "Elev"),    (chartSeriesData[.elevation]?.count ?? 0) >= 2),
            (.intervals,           AppLanguage.shared.s("인터벌",  "Intvl"),   !intervalSegments.isEmpty),
        ]
        return VStack(alignment: .leading, spacing: 4) {
            chartRow(Array(charts[0..<4]))
            chartRow(Array(charts[4..<8]))
        }
    }

    private func chartRow(_ items: [(ChartOverlayType, String, Bool)]) -> some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                chartChip(type: items[i].0, label: items[i].1, available: items[i].2)
            }
        }
    }

    private func chartChip(type: ChartOverlayType, label: String, available: Bool) -> some View {
        let isSel = currentRecipeValid && workingRecipes[currentPage].chartOverlayType == type
        let fg: Color = available ? (isSel ? Theme.violet : Color.white.opacity(0.60)) : Color.white.opacity(0.22)
        let bg: Color = isSel ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08)
        let border: Color = isSel ? Theme.violet.opacity(0.55) : Color.clear
        let weight: Font.Weight = isSel ? .semibold : .regular
        return Button {
            guard available, currentRecipeValid else { return }
            let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
            workingRecipes[currentPage].chartOverlayType = isSel ? .none : type
        } label: {
            Text(label)
                .font(.system(size: 11, weight: weight))
                .lineLimit(1)
                .padding(.horizontal, 5).padding(.vertical, 4)
                .background(bg)
                .foregroundStyle(fg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    private func positionGridFor(_ kind: OverlayKind) -> some View {
        let rows: [[CardPosition]] = [
            [.topLeading,    .top,    .topTrailing],
            [.leading,       .center, .trailing],
            [.bottomLeading, .bottom, .bottomTrailing]
        ]
        let occupied = occupiedCells(excluding: kind)
        let sel      = positionValue(kind)
        return VStack(spacing: 4) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(rows[row].indices, id: \.self) { col in
                        let pos   = rows[row][col]
                        let isSel = currentRecipeValid && sel == pos
                        let isOcc = occupied.contains(pos)
                        Button {
                            guard !isOcc else { return }
                            withAnimation(.easeInOut(duration: 0.12)) { setPosition(pos, kind) }
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isSel ? Theme.violet
                                      : (isOcc ? Color.white.opacity(0.04) : Color(hex: "26262E")))
                                .frame(width: 23, height: 23)
                                .overlay(isOcc
                                    ? Image(systemName: "xmark").font(.system(size: 7))
                                        .foregroundStyle(.white.opacity(0.25))
                                    : nil)
                        }
                        .buttonStyle(.plain)
                        .disabled(isOcc)
                    }
                }
            }
        }
    }

    // MARK: - 러닝 데이터 오버레이 (운동한 날: P/D/T/M/H 토글 + 위치)

    private func recipeBool(_ kp: WritableKeyPath<ClipRecipe, Bool>) -> Bool {
        currentRecipeValid ? workingRecipes[currentPage][keyPath: kp] : false
    }
    private func toggleBool(_ kp: WritableKeyPath<ClipRecipe, Bool>) {
        guard currentRecipeValid else { return }
        let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
        workingRecipes[currentPage][keyPath: kp].toggle()
    }


    private var hasRunData: Bool { !availableMetrics.isEmpty || !routeCoords.isEmpty || hrSamples.count >= 2 }

    // 프리뷰 데이터 오버레이 (PDT칩·경로맵·차트 패널) — export 좌표와 동일 기준(safeTop/Bot @1080)
    // skipLeafOverlays=true: PDT칩·경로 미니맵 제외, 차트 패널만 렌더 (story 모드 오버레이용)
    @ViewBuilder
    private func dataPreviewOverlay(_ recipe: ClipRecipe, w: CGFloat, maxH: CGFloat,
                                    chipTop: CGFloat? = nil,
                                    skipLeafOverlays: Bool = false) -> some View {
        let ps    = w / 300.0
        let s1080 = w / 1080.0
        // story/video 공통: 좌우 동일 여백, 차트를 카드 바닥에 배치
        let chartPanelW: CGFloat = w - 20 * ps
        let chartBotPad: CGFloat = 10 * ps
        // PDT 칩: 워드마크 존 아래, 문구와 동일한 콘텐츠 존 안에 배치 (safeTop*s+14·export와 동일)
        // Chart-aware bottom: 차트 활성화 시 차트 상단 바로 위로 bottom 포지션 이동
        let (overlayHasChart, overlayChartPanH): (Bool, CGFloat) = {
            if recipe.showHRChart && hrSamples.count >= 2 { return (true, maxH * 0.264) }
            if recipe.chartOverlayType == .route && !routeCoords.isEmpty { return (true, maxH * 0.264) }
            if recipe.chartOverlayType == .splits {
                let fc = splits.filter { $0.distanceM >= 900 }.count
                if fc >= 2 {
                    let dc = fc > 21 ? fc / 2 : fc
                    return (true, (34 + CGFloat(dc) * 7) * ps)
                }
            }
            if recipe.chartOverlayType == .intervals {
                let d = intervalSegments.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                if d > 0 { return (true, maxH * 0.42) }
            }
            let gt = recipe.chartOverlayType
            if ![.none, .route, .hrChart, .splits, .intervals].contains(gt),
               let s = chartSeriesData[gt], s.count >= 2 { return (true, maxH * 0.264) }
            return (false, 0)
        }()
        let overlayEffBottomPad: CGFloat = overlayHasChart
            ? overlayChartPanH + chartBotPad + 8
            : maxH * 0.06
        if !skipLeafOverlays {
            if recipe.metricPace || recipe.metricDistance || recipe.metricTime || recipe.metricHeartRate {
                pdtChipsView(recipe, scale: ps)
                    .padding(.horizontal, 20 * ps)
                    .padding(.top,    recipe.pdtPosition.isTop    ? (chipTop ?? CardVisual.videoSafeTop * s1080 + 14 * ps) : 0)
                    .padding(.bottom, recipe.pdtPosition.isBottom ? overlayEffBottomPad : 0)
                    .frame(width: w, height: maxH, alignment: recipe.pdtPosition.alignment)
                    .allowsHitTesting(false)
            }
            if recipe.showRoute, recipe.chartOverlayType != .route, !routeCoords.isEmpty {
                RouteMiniMap(coords: routeCoords)
                    .frame(width: 54 * ps, height: 54 * ps)
                    .padding(.horizontal, 18 * ps)
                    .padding(.top,    recipe.routePosition.isTop    ? (CardVisual.videoSafeTop + 4) * s1080 : 0)
                    .padding(.bottom, recipe.routePosition.isBottom ? overlayEffBottomPad : 0)
                    .frame(width: w, height: maxH, alignment: recipe.routePosition.alignment)
                    .allowsHitTesting(false)
            }
        }
        if recipe.showHRChart, hrSamples.count >= 2 {
            let panW    = chartPanelW
            let panH    = maxH * 0.264
            let hrSrc   = hrSamples.filter { $0.bpm > 0 }
                .map { (offset: $0.offset, value: Double($0.bpm)) }
            let hrt0    = hrSrc.first?.offset ?? 0
            let hrdt    = max(1.0, (hrSrc.last?.offset ?? 1) - hrt0)
            let hrdtMin = hrdt / 60.0
            let hrBN    = 80
            let hrBSz   = hrdt / Double(hrBN)
            let hrBuckets: [(id: Int, avg: Double, lo: Double, hi: Double)] = (0..<hrBN).compactMap { i in
                let bLo  = hrt0 + Double(i) * hrBSz
                let bHi  = bLo + hrBSz
                let vals = hrSrc
                    .filter { $0.offset >= bLo && ($0.offset < bHi || (i == hrBN - 1 && $0.offset <= hrt0 + hrdt)) }
                    .map(\.value)
                guard !vals.isEmpty else { return nil }
                return (i, vals.reduce(0, +) / Double(vals.count), vals.min()!, vals.max()!)
            }
            let hrAvgAll = hrSrc.isEmpty ? 0.0 : hrSrc.map(\.value).reduce(0, +) / Double(hrSrc.count)
            // 범위 막대: 최저~최고 기준으로 Y 도메인 설정
            let oMin  = hrBuckets.map(\.lo).min() ?? 0
            let oMax  = hrBuckets.map(\.hi).max() ?? 1
            let hrRng = max(oMax - oMin, oMin * 0.02)
            let hrYLo = max(0, oMin - hrRng * 0.4)
            let hrYHi = oMax + hrRng * 0.2
            let hrYRange = max(1e-6, hrYHi - hrYLo)
            let sortedZones = hrZones.sorted { $0.minBPM < $1.minBPM }
            let zoneColor: (Double) -> Color = { bpm in
                var idx = 1
                for z in sortedZones { if bpm >= Double(z.minBPM) { idx = z.id } }
                switch idx {
                case 1:  return Color(red: 0.30, green: 0.55, blue: 1.00)
                case 2:  return Color(red: 0.20, green: 0.85, blue: 0.45)
                case 3:  return Color(red: 0.75, green: 0.88, blue: 0.20)
                case 4:  return Color(red: 1.00, green: 0.55, blue: 0.10)
                default: return Color(red: 1.00, green: 0.25, blue: 0.45)
                }
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12 * ps)
                    .fill(Color.black.opacity(0.30))
                VStack(alignment: .leading, spacing: 2 * ps) {
                    Text(AppLanguage.shared.s("♥ 심박수", "♥ HR"))
                        .font(.system(size: 10 * ps, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.top, 8 * ps)
                        .padding(.leading, 10 * ps)
                    Canvas { ctx, size in
                        guard !hrBuckets.isEmpty else { return }
                        let yLblW: CGFloat = 26 * ps
                        let xLblH: CGFloat = 11 * ps
                        let cw = max(1, size.width - yLblW)
                        let ch = max(1, size.height - xLblH)
                        let yMarkN = 4, xMarkN = 4
                        func pty(_ v: Double) -> CGFloat { ch * CGFloat(1 - (v - hrYLo) / hrYRange) }
                        let axisFont  = Font.system(size: 7 * ps, design: .monospaced)
                        let axisColor = Color.white.opacity(0.55)
                        // H grid + right Y labels (BPM)
                        for i in 0..<yMarkN {
                            let yVal = hrYLo + Double(i) * (hrYHi - hrYLo) / Double(yMarkN - 1)
                            let yp   = pty(yVal)
                            var gp = Path(); gp.move(to: CGPoint(x: 0, y: yp)); gp.addLine(to: CGPoint(x: cw, y: yp))
                            ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                            ctx.draw(Text(String(format: "%.0f", yVal)).font(axisFont).foregroundColor(axisColor),
                                     at: CGPoint(x: cw + 2, y: yp), anchor: .leading)
                        }
                        // V grid + bottom X labels (time)
                        for i in 0..<xMarkN {
                            let frac = Double(i) / Double(xMarkN - 1)
                            let xp   = CGFloat(frac) * cw
                            var gp = Path(); gp.move(to: CGPoint(x: xp, y: 0)); gp.addLine(to: CGPoint(x: xp, y: ch))
                            ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                            let xTxt = AppLanguage.shared.isEnglish
                                ? String(format: "%.0fm", frac * hrdtMin)
                                : String(format: "%.0f분", frac * hrdtMin)
                            var anch: UnitPoint = .top
                            if i == 0 { anch = .topLeading } else if i == xMarkN - 1 { anch = .topTrailing }
                            ctx.draw(Text(xTxt).font(axisFont).foregroundColor(axisColor),
                                     at: CGPoint(x: xp, y: ch + 2), anchor: anch)
                        }
                        // Zone-colored range bars (최저 lo → 최고 hi, floating)
                        let barGap = cw / CGFloat(hrBN)
                        let barW   = max(1.5, barGap - 0.8)
                        for b in hrBuckets {
                            let bx   = CGFloat(b.id) * barGap + (barGap - barW) / 2
                            let topY = pty(b.hi)
                            let botY = pty(b.lo)
                            let barH = max(1.5, botY - topY)
                            ctx.fill(Path(CGRect(x: bx, y: topY, width: barW, height: barH)),
                                     with: .color(zoneColor(b.avg).opacity(0.85)))
                        }
                        // Red dashed avg line + label
                        let avgY = pty(hrAvgAll)
                        var dashPath = Path(); var dx: CGFloat = 0
                        while dx < cw {
                            dashPath.move(to: CGPoint(x: dx, y: avgY))
                            dashPath.addLine(to: CGPoint(x: min(dx + 4, cw), y: avgY))
                            dx += 7
                        }
                        ctx.stroke(dashPath, with: .color(Color.red.opacity(0.75)), lineWidth: 1.2)
                        ctx.draw(
                            Text("avg \(Int(hrAvgAll))").font(Font.system(size: 7.5 * ps, weight: .medium))
                                .foregroundColor(Color.red.opacity(0.9)),
                            at: CGPoint(x: cw - 2, y: avgY - 1), anchor: .bottomTrailing)
                    }
                    .padding(.horizontal, 10 * ps)
                    .padding(.bottom, 4 * ps)
                }
            }
            .frame(width: panW, height: panH)
            .padding(.bottom, chartBotPad)
            .frame(width: w, height: maxH, alignment: .bottom)
            .allowsHitTesting(false)
        }
        if recipe.chartOverlayType == .route, !routeCoords.isEmpty {
            let panW = chartPanelW
            let panH = maxH * 0.264
            let lats = routeCoords.map { $0.latitude }, lons = routeCoords.map { $0.longitude }
            let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
            let rng  = max(1e-6, max(maxLat - minLat, maxLon - minLon))
            let padX = (rng - (maxLon - minLon)) / 2, padY = (rng - (maxLat - minLat)) / 2
            let routePt: (CLLocationCoordinate2D, CGSize) -> CGPoint = { c, size in
                let nx = CGFloat((c.longitude - minLon + padX) / rng)
                let ny = CGFloat((c.latitude  - minLat + padY) / rng)
                let inset: CGFloat = size.height * 0.06
                let dim = min(size.width, size.height) - inset * 2
                let xOff = (size.width - dim) / 2
                return CGPoint(x: xOff + inset + nx * dim, y: inset + (1 - ny) * dim)
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12 * ps)
                    .fill(Color.black.opacity(0.30))
                VStack(alignment: .leading, spacing: 2 * ps) {
                    Text(AppLanguage.shared.s("↗ 경로", "↗ Route"))
                        .font(.system(size: 10 * ps, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.top, 8 * ps)
                        .padding(.leading, 10 * ps)
                    Canvas { ctx, size in
                        var path = Path()
                        path.move(to: routePt(routeCoords[0], size))
                        for c in routeCoords.dropFirst() { path.addLine(to: routePt(c, size)) }
                        ctx.stroke(path, with: .color(.white.opacity(0.88)),
                                   style: StrokeStyle(lineWidth: 1.5 * ps, lineCap: .round, lineJoin: .round))
                        let dotR: CGFloat = 3.5 * ps
                        let sPt = routePt(routeCoords.first!, size)
                        ctx.fill(Path(ellipseIn: CGRect(x: sPt.x - dotR, y: sPt.y - dotR, width: dotR * 2, height: dotR * 2)),
                                 with: .color(.green.opacity(0.90)))
                        let ePt = routePt(routeCoords.last!, size)
                        ctx.fill(Path(ellipseIn: CGRect(x: ePt.x - dotR, y: ePt.y - dotR, width: dotR * 2, height: dotR * 2)),
                                 with: .color(.red.opacity(0.90)))
                    }
                    .padding(.horizontal, 10 * ps)
                    .padding(.bottom, 4 * ps)
                }
            }
            .frame(width: panW, height: panH)
            .padding(.bottom, chartBotPad)
            .frame(width: w, height: maxH, alignment: .bottom)
            .allowsHitTesting(false)
        }
        if recipe.chartOverlayType == .splits, !splits.isEmpty {
            let full = splits.filter { $0.distanceM >= 900 }
            if full.count >= 2 {
                let panW = chartPanelW
                let rowH: CGFloat    = 7 * ps
                let titleH: CGFloat  = 16 * ps
                let colHH: CGFloat   = 8 * ps
                let vPad: CGFloat    = 5 * ps

                // 21km 초과 시 2km 간격으로 표시
                let displaySplits = full.count > 21 ? full.filter { $0.id % 2 == 0 } : full
                let panH = titleH + colHH + CGFloat(displaySplits.count) * rowH + vPad * 2

                let paces      = displaySplits.map { $0.paceSecPerKm }
                let minP       = paces.min() ?? 0
                let maxP       = paces.max() ?? 1
                let rangeP     = max(1.0, maxP - minP)
                let avgP       = paces.reduce(0.0, +) / Double(paces.count)
                let fastestIdx = paces.indices.min(by: { paces[$0] < paces[$1] }) ?? 0

                let hasHR  = displaySplits.contains { $0.avgHeartRate != nil }
                let hasCad = displaySplits.contains { $0.avgCadence != nil }
                let hasPwr = displaySplits.contains { $0.avgPower != nil }

                let hPad: CGFloat  = 8 * ps
                let gap:  CGFloat  = 3 * ps
                let kmW:  CGFloat  = 18 * ps
                let colW: CGFloat  = 24 * ps  // 모든 데이터 열 균등 폭
                let fixedW  = 2 * hPad + kmW + 2 * gap + colW
                let optW    = (hasHR  ? gap + colW : 0)
                            + (hasCad ? gap + colW : 0)
                            + (hasPwr ? gap + colW : 0)
                let barAreaW = max(20 * ps, panW - fixedW - optW)

                let zoneColor: (Int?) -> Color = { hrOpt in
                    guard let hr = hrOpt,
                          let zid = self.hrZones.first(where: { hr >= $0.minBPM && hr <= $0.maxBPM })?.id
                    else { return Color.red.opacity(0.70) }
                    switch zid {
                    case 1: return Color(hex: "4FC3F7")
                    case 2: return Color(hex: "81C784")
                    case 3: return Color(hex: "FFB74D")
                    case 4: return Color(hex: "FF7043")
                    default: return Color(hex: "E53935")
                    }
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12 * ps)
                        .fill(Color.black.opacity(0.30))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(AppLanguage.shared.s("⚡ 스플릿", "⚡ Splits"))
                            .font(.system(size: 10 * ps, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(height: titleH)
                            .padding(.horizontal, hPad)
                        // 열 제목 행
                        HStack(spacing: gap) {
                            Spacer().frame(width: kmW)
                            Spacer().frame(width: barAreaW)
                            Text(AppLanguage.shared.s("페이스", "Pace"))
                                .font(.system(size: 5.5 * ps, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.75))
                                .frame(width: colW, alignment: .trailing)
                            if hasHR {
                                Text(AppLanguage.shared.s("심박", "HR"))
                                    .font(.system(size: 5.5 * ps, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.75))
                                    .frame(width: colW, alignment: .trailing)
                            }
                            if hasCad {
                                Text(AppLanguage.shared.s("케이던스", "Cad"))
                                    .font(.system(size: 5.5 * ps, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.75))
                                    .frame(width: colW, alignment: .trailing)
                            }
                            if hasPwr {
                                Text(AppLanguage.shared.s("파워", "Pwr"))
                                    .font(.system(size: 5.5 * ps, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.75))
                                    .frame(width: colW, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, hPad)
                        .frame(height: colHH)
                        ForEach(Array(displaySplits.enumerated()), id: \.element.id) { idx, split in
                            let isFastest = idx == fastestIdx
                            let pace = split.paceSecPerKm
                            let barFrac = CGFloat(0.28 + 0.72 * (pace - minP) / rangeP)
                            let barColor: Color = isFastest
                                ? Color(hex: "FFC74D")
                                : (pace <= avgP
                                    ? Color(red: 0.486, green: 0.361, blue: 0.988).opacity(0.85)
                                    : Color.white.opacity(0.30))
                            let zc = zoneColor(split.avgHeartRate)
                            HStack(spacing: gap) {
                                Text("\(split.id)k")
                                    .font(.system(size: 6.5 * ps, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.80))
                                    .frame(width: kmW, alignment: .trailing)
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.white.opacity(0.10))
                                        .frame(width: barAreaW, height: 3 * ps)
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(barColor)
                                        .frame(width: max(3, barAreaW * barFrac), height: 3 * ps)
                                }
                                .frame(width: barAreaW)
                                Text(split.formattedPace)
                                    .font(.system(size: 7 * ps, weight: .bold, design: .monospaced))
                                    .foregroundStyle(isFastest ? Color(hex: "FFC74D") : .white)
                                    .frame(width: colW, alignment: .trailing)
                                if hasHR {
                                    HStack(spacing: 1.5 * ps) {
                                        Circle()
                                            .fill(split.avgHeartRate != nil ? zc : Color.clear)
                                            .frame(width: 3.5 * ps, height: 3.5 * ps)
                                        Text(split.avgHeartRate.map { "\($0)" } ?? "—")
                                            .font(.system(size: 6.5 * ps, design: .monospaced))
                                            .foregroundStyle(split.avgHeartRate != nil ? zc : Color.white.opacity(0.45))
                                    }
                                    .frame(width: colW, alignment: .trailing)
                                }
                                if hasCad {
                                    Text(split.avgCadence.map { "\($0)" } ?? "—")
                                        .font(.system(size: 6.5 * ps, design: .monospaced))
                                        .foregroundStyle(Color(hex: "60E8CC"))
                                        .frame(width: colW, alignment: .trailing)
                                }
                                if hasPwr {
                                    Text(split.avgPower.map { "\($0)" } ?? "—")
                                        .font(.system(size: 6.5 * ps, design: .monospaced))
                                        .foregroundStyle(Color(hex: "BEFA6A"))
                                        .frame(width: colW, alignment: .trailing)
                                }
                            }
                            .padding(.horizontal, hPad)
                            .frame(height: rowH)
                        }
                        Spacer(minLength: vPad)
                    }
                }
                .frame(width: panW, height: panH)
                .padding(.bottom, chartBotPad)
                .frame(width: w, height: maxH, alignment: .bottom)
                .allowsHitTesting(false)
            }
        }
        if recipe.chartOverlayType == .intervals, !intervalSegments.isEmpty {
            let panW  = chartPanelW
            let panH  = maxH * 0.42
            let totalDur = intervalSegments.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            if totalDur > 0 {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12 * ps)
                        .fill(Color.black.opacity(0.30))
                    VStack(alignment: .leading, spacing: 2 * ps) {
                        Text(AppLanguage.shared.s("⚙ 인터벌", "⚙ Intervals"))
                            .font(.system(size: 10 * ps, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.top, 8 * ps)
                            .padding(.leading, 10 * ps)
                        Canvas { ctx, size in
                            let n = intervalSegments.count
                            let barGap: CGFloat = 2
                            let totalGapW = barGap * CGFloat(max(0, n - 1))
                            var xCursor: CGFloat = 0
                            for seg in intervalSegments {
                                let dur = seg.endDate.timeIntervalSince(seg.startDate)
                                let bW = (size.width - totalGapW) * CGFloat(dur / totalDur)
                                let isWork = seg.stepLabel == "운동"
                                let barColor: Color = isWork
                                    ? Color(red: 0.486, green: 0.361, blue: 0.988).opacity(0.9)
                                    : Color(white: 0.28).opacity(0.9)
                                let barPath = Path(roundedRect: CGRect(x: xCursor, y: 0, width: bW, height: size.height), cornerRadius: 3)
                                ctx.fill(barPath, with: .color(barColor))
                                xCursor += bW + barGap
                            }
                        }
                        .padding(.horizontal, 10 * ps)
                        .padding(.bottom, 8 * ps)
                    }
                }
                .frame(width: panW, height: panH)
                .padding(.bottom, chartBotPad)
                .frame(width: w, height: maxH, alignment: .bottom)
                .allowsHitTesting(false)
            }
        }
        let genericType = recipe.chartOverlayType
        if ![.none, .route, .hrChart, .splits, .intervals].contains(genericType),
           let series = chartSeriesData[genericType], series.count >= 2 {
            let panW = chartPanelW
            let panH = maxH * 0.264
            let lineColor = Color(uiColor: genericType.lineUIColor)
            let title = AppLanguage.shared.s(genericType.chartTitleKo, genericType.chartTitleEn)

            let useRangeBar = (genericType == .strideLength || genericType == .verticalOscillation
                                || genericType == .power || genericType == .groundContact)
            let isElevation = (genericType == .elevation)
            let src = series.filter { $0.value > 0 }
            let t0    = src.first?.offset ?? 0
            let dt    = max(1.0, (src.last?.offset ?? 1) - t0)
            let dtMin = dt / 60.0
            let bN    = 80
            let bSz   = dt / Double(bN)
            let buckets: [(id: Int, avg: Double, lo: Double, hi: Double)] = (0..<bN).compactMap { i in
                let bLo  = t0 + Double(i) * bSz
                let bHi  = bLo + bSz
                let vals = src
                    .filter { $0.offset >= bLo && ($0.offset < bHi || (i == bN - 1 && $0.offset <= t0 + dt)) }
                    .map(\.value)
                guard !vals.isEmpty else { return nil }
                return (i, vals.reduce(0, +) / Double(vals.count), vals.min()!, vals.max()!)
            }
            let avgAll = src.isEmpty ? 0.0 : src.map(\.value).reduce(0, +) / Double(src.count)
            let yLo: Double = {
                if useRangeBar {
                    let oMin = buckets.map(\.lo).min() ?? 0
                    let oMax = buckets.map(\.hi).max() ?? 1
                    let rng  = max(oMax - oMin, oMin * 0.02)
                    return max(0, oMin - rng * 0.4)
                } else {
                    let avgs = buckets.map(\.avg)
                    let lo2  = avgs.min() ?? 0; let hi2 = avgs.max() ?? 1
                    let rng  = max(hi2 - lo2, lo2 * 0.02)
                    return max(0, lo2 - rng * 0.6)
                }
            }()
            let yHi: Double = {
                if useRangeBar {
                    let oMin = buckets.map(\.lo).min() ?? 0
                    let oMax = buckets.map(\.hi).max() ?? 1
                    let rng  = max(oMax - oMin, oMin * 0.02)
                    return oMax + rng * 0.2
                } else {
                    let avgs = buckets.map(\.avg)
                    let lo2  = avgs.min() ?? 0; let hi2 = avgs.max() ?? 1
                    let rng  = max(hi2 - lo2, lo2 * 0.02)
                    return hi2 + rng * 0.2
                }
            }()
            let yRange = max(1e-6, yHi - yLo)
            let fmtY: (Double) -> String = { v in
                if isElevation { return String(format: "%.0fm", v) }
                if abs(v) >= 100 { return String(format: "%.0f", v) }
                if abs(v) >= 10  { return String(format: "%.1f", v) }
                return String(format: "%.2f", v)
            }
            let fmtXStr: (Double) -> String = { m in
                AppLanguage.shared.isEnglish ? String(format: "%.0fm", m) : String(format: "%.0f분", m)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12 * ps)
                    .fill(Color.black.opacity(0.30))
                VStack(alignment: .leading, spacing: 2 * ps) {
                    Text(title)
                        .font(.system(size: 10 * ps, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.top, 8 * ps)
                        .padding(.leading, 10 * ps)
                    Canvas { ctx, size in
                        guard !buckets.isEmpty || isElevation else { return }
                        // Reserve right margin for Y labels, bottom for X labels
                        let yLblW: CGFloat = 26 * ps
                        let xLblH: CGFloat = 11 * ps
                        let cw = max(1, size.width - yLblW)
                        let ch = max(1, size.height - xLblH)
                        let yMarkN = 4
                        let xMarkN = 4
                        func pty(_ v: Double) -> CGFloat { ch * CGFloat(1 - (v - yLo) / yRange) }
                        let axisFont = Font.system(size: 7 * ps, design: .monospaced)
                        let axisColor = Color.white.opacity(0.55)
                        // H grid lines + right Y labels
                        for i in 0..<yMarkN {
                            let yVal = yLo + Double(i) * (yHi - yLo) / Double(yMarkN - 1)
                            let yp   = pty(yVal)
                            var gp = Path()
                            gp.move(to: CGPoint(x: 0, y: yp))
                            gp.addLine(to: CGPoint(x: cw, y: yp))
                            ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                            ctx.draw(Text(fmtY(yVal)).font(axisFont).foregroundColor(axisColor),
                                     at: CGPoint(x: cw + 2, y: yp), anchor: .leading)
                        }
                        // V grid lines + bottom X labels
                        for i in 0..<xMarkN {
                            let frac = Double(i) / Double(xMarkN - 1)
                            let xp   = CGFloat(frac) * cw
                            var gp = Path()
                            gp.move(to: CGPoint(x: xp, y: 0))
                            gp.addLine(to: CGPoint(x: xp, y: ch))
                            ctx.stroke(gp, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
                            let xTxt  = fmtXStr(frac * dtMin)
                            var anch: UnitPoint = .top
                            if i == 0 { anch = .topLeading } else if i == xMarkN - 1 { anch = .topTrailing }
                            ctx.draw(Text(xTxt).font(axisFont).foregroundColor(axisColor),
                                     at: CGPoint(x: xp, y: ch + 2), anchor: anch)
                        }
                        // Chart
                        if isElevation {
                            let ptX: (Double) -> CGFloat = { t in CGFloat((t - t0) / dt) * cw }
                            var fillPath = Path()
                            fillPath.move(to: CGPoint(x: ptX(src[0].offset), y: ch))
                            fillPath.addLine(to: CGPoint(x: ptX(src[0].offset), y: pty(src[0].value)))
                            for pt in src.dropFirst() { fillPath.addLine(to: CGPoint(x: ptX(pt.offset), y: pty(pt.value))) }
                            fillPath.addLine(to: CGPoint(x: ptX(src.last!.offset), y: ch))
                            fillPath.closeSubpath()
                            ctx.fill(fillPath, with: .color(lineColor.opacity(0.30)))
                            var linePath = Path()
                            linePath.move(to: CGPoint(x: ptX(src[0].offset), y: pty(src[0].value)))
                            for pt in src.dropFirst() { linePath.addLine(to: CGPoint(x: ptX(pt.offset), y: pty(pt.value))) }
                            ctx.stroke(linePath, with: .color(lineColor), lineWidth: 1.5)
                        } else {
                            let barGap   = cw / CGFloat(bN)
                            let barW     = max(1.5, barGap - 0.8)
                            let baseline = pty(yLo)
                            for b in buckets {
                                let bx   = CGFloat(b.id) * barGap + (barGap - barW) / 2
                                let topY = useRangeBar ? pty(b.hi)  : pty(b.avg)
                                let botY = useRangeBar ? pty(b.lo) : baseline
                                let barH = max(1.5, botY - topY)
                                ctx.fill(Path(CGRect(x: bx, y: topY, width: barW, height: barH)),
                                         with: .color(lineColor.opacity(0.80)))
                            }
                            let avgY = pty(avgAll)
                            var dashPath = Path()
                            var x: CGFloat = 0
                            while x < cw {
                                dashPath.move(to: CGPoint(x: x, y: avgY))
                                dashPath.addLine(to: CGPoint(x: min(x + 4, cw), y: avgY))
                                x += 7
                            }
                            ctx.stroke(dashPath, with: .color(lineColor.opacity(0.60)), lineWidth: 1.2)
                        }
                    }
                    .padding(.horizontal, 10 * ps)
                    .padding(.bottom, 4 * ps)
                }
            }
            .frame(width: panW, height: panH)
            .padding(.bottom, chartBotPad)
            .frame(width: w, height: maxH, alignment: .bottom)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func pdtChipsView(_ recipe: ClipRecipe, scale: CGFloat) -> some View {
        let items: [MetricItem] = [
            recipe.metricDistance  ? availableMetrics.first { $0.id == "distance" }  : nil,
            recipe.metricPace      ? availableMetrics.first { $0.id == "pace" }      : nil,
            recipe.metricTime      ? availableMetrics.first { $0.id == "time" }      : nil,
            recipe.metricHeartRate ? availableMetrics.first { $0.id == "heartrate" } : nil
        ].compactMap { $0 }
        let sz = recipe.pdtSizeLevel.scale  // 소=0.65 중=0.8 대=1.0
        HStack(spacing: 6 * scale * sz) {
            ForEach(items) { m in
                HStack(spacing: 3 * scale * sz) {
                    Text(m.value)
                        .font(.system(size: 11 * scale * sz, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if !m.label.isEmpty {
                        Text(m.label)
                            .font(.system(size: 9 * scale * sz))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 8 * scale * sz).padding(.vertical, 4 * scale * sz)
                .background(RoundedRectangle(cornerRadius: 8 * scale * sz).fill(m.color.opacity(0.30)))
                .overlay(RoundedRectangle(cornerRadius: 8 * scale * sz)
                    .strokeBorder(m.color.opacity(0.55), lineWidth: max(0.5, scale)))
            }
        }
    }

    private var sizeChips: some View {
        let borderOn = currentRecipeValid && workingRecipes[currentPage].hasBorder
        return HStack(spacing: 6) {
            ForEach(TextSizeLevel.allCases, id: \.self) { s in
                let isSel = currentRecipeValid && workingRecipes[currentPage].sizeLevel == s
                Button { if currentRecipeValid { workingRecipes[currentPage].sizeLevel = s } } label: {
                    Text(s.chipLabel)
                        .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isSel ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08))
                        .foregroundStyle(isSel ? Theme.violet : Color.white.opacity(0.55))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(
                            isSel ? Theme.violet.opacity(0.55) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            // 테두리 — 특대 바로 옆
            Button {
                guard currentRecipeValid else { return }
                workingRecipes[currentPage].hasBorder.toggle()
                #if DEBUG
                sizeAuditLog("테두리 토글")
                #endif
            } label: {
                Text(AppLanguage.shared.s("테두리", "Border"))
                    .font(.system(size: 12, weight: borderOn ? .semibold : .regular))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(borderOn ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08))
                    .foregroundStyle(borderOn ? Theme.violet : Color.white.opacity(0.55))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(
                        borderOn ? Theme.violet.opacity(0.55) : Color.clear, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var fontChips: some View {
        HStack(spacing: 6) {
            ForEach(OneLinerFont.allCases, id: \.self) { f in
                let isSel = currentRecipeValid && workingRecipes[currentPage].fontChoice == f
                Button {
                    guard currentRecipeValid else { return }
                    workingRecipes[currentPage].fontChoice = f

                    #if DEBUG
                    sizeAuditLog("폰트 전환")
                    #endif
                } label: {
                    Text(f.chipLabel)
                        .font(f.swiftUIFont(size: 13))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isSel ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08))
                        .foregroundStyle(isSel ? Theme.violet : Color.white.opacity(0.70))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(
                            isSel ? Theme.violet.opacity(0.55) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // 등장 방식: 타이핑 / 페이드 / 날아오기 (택1)
    private var appearanceChips: some View {
        HStack(spacing: 6) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                let isSel = currentRecipeValid && workingRecipes[currentPage].appearanceMode == mode
                Button {
                    guard currentRecipeValid else { return }
                    workingRecipes[currentPage].appearanceMode = mode
                    // 타이핑·날아오기 전환 시 꾸밈 초기화 (페이드 전용)
                    if mode == .typing || mode == .flyIn { workingRecipes[currentPage].decorEffect = .none }
                } label: {
                    Text(mode.chipLabel)
                        .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isSel ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08))
                        .foregroundStyle(isSel ? Theme.violet : Color.white.opacity(0.55))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(
                            isSel ? Theme.violet.opacity(0.55) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // 방향: 왼쪽 / 오른쪽 — 날아오기 모드에서만 표시
    private var flyDirectionChips: some View {
        HStack(spacing: 6) {
            ForEach(FlyInDirection.allCases, id: \.self) { dir in
                let isSel = currentRecipeValid && workingRecipes[currentPage].flyDirection == dir
                Button {
                    guard currentRecipeValid else { return }
                    workingRecipes[currentPage].flyDirection = dir
                } label: {
                    Text(dir.chipLabel)
                        .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isSel ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08))
                        .foregroundStyle(isSel ? Theme.violet : Color.white.opacity(0.55))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(
                            isSel ? Theme.violet.opacity(0.55) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // 꾸밈: 없음 / 흔들림 / 팝 — 페이드 모드에서만 표시
    private var decorChips: some View {
        HStack(spacing: 6) {
            ForEach(DecorEffect.allCases, id: \.self) { fx in
                let isSel = currentRecipeValid && workingRecipes[currentPage].decorEffect == fx
                Button {
                    guard currentRecipeValid else { return }
                    workingRecipes[currentPage].decorEffect = fx
                } label: {
                    Text(fx.chipLabel)
                        .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isSel ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08))
                        .foregroundStyle(isSel ? Theme.violet : Color.white.opacity(0.55))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(
                            isSel ? Theme.violet.opacity(0.55) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // 가독성: 테두리 독립 토글 — 폰트 자동 전환 없음 (크기 계산과 완전 독립)
    private var readabilityChips: some View {
        HStack(spacing: 6) {
            // 테두리 토글 — 폰트·크기 유지. 크기는 sizeLevel·fontChoice만으로 결정.
            let borderOn = currentRecipeValid && workingRecipes[currentPage].hasBorder
            Button {
                guard currentRecipeValid else { return }
                workingRecipes[currentPage].hasBorder.toggle()
                #if DEBUG
                sizeAuditLog("테두리 토글")
                #endif
            } label: {
                Text(AppLanguage.shared.s("테두리", "Border"))
                    .font(.system(size: 12, weight: borderOn ? .semibold : .regular))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(borderOn ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08))
                    .foregroundStyle(borderOn ? Theme.violet : Color.white.opacity(0.55))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(
                        borderOn ? Theme.violet.opacity(0.55) : Color.clear, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var colorCircles: some View {
        HStack(spacing: 8) {
            ForEach(OneLinerTextColor.allCases, id: \.self) { c in
                let isSel = currentRecipeValid && workingRecipes[currentPage].textColor == c
                Button { if currentRecipeValid { workingRecipes[currentPage].textColor = c } } label: {
                    ZStack {
                        Circle()
                            .fill(c.color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(
                                c == .white ? Color.gray.opacity(0.4) : Color.clear,
                                lineWidth: 1))
                        if isSel {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Replace media button

    // MARK: - Clip thumbnail helper

    /// 썸네일 배경 표시. 사진 클립은 즉시 완료(스피너 없음), 영상 클립은 해석 중 스피너.
    @ViewBuilder
    private func clipThumbnailView(thumb: UIImage, isPhoto: Bool, w: CGFloat, h: CGFloat,
                                   cropOffsetX: CGFloat = 0.5) -> some View {
        let tScale  = max(w / thumb.size.width, h / thumb.size.height)
        let tImgW   = thumb.size.width  * tScale
        let tImgH   = thumb.size.height * tScale
        let tExcess = max(0, tImgW - w)
        let tOx     = -(cropOffsetX * tExcess)
        if isPhoto {
            Image(uiImage: thumb)
                .resizable()
                .frame(width: tImgW, height: tImgH)
                .offset(x: tOx)
                .frame(width: w, height: h, alignment: .topLeading).clipped()
        } else {
            Image(uiImage: thumb)
                .resizable()
                .frame(width: tImgW, height: tImgH)
                .offset(x: tOx)
                .frame(width: w, height: h, alignment: .topLeading).clipped()
                .overlay(ProgressView().tint(.white).scaleEffect(1.4))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var clipEditToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(AppLanguage.shared.s("취소", "Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(AppLanguage.shared.s("완료", "Done")) {
                commitWorkingRecipes()
                dismiss()
            }
            .bold()
        }
    }

    // MARK: - Thumbnail at trim end

    /// 트림 핸들 드래그 완료 시, 클립 스트립 썸네일을 trimEnd 시점 프레임으로 갱신.
    private func updateThumbnailAtTrimEnd(_ idx: Int) {
        guard workingRecipes.indices.contains(idx) else { return }
        let r = workingRecipes[idx]
        guard r.storedPhotoRef == nil else { return }   // 사진 클립은 정지 이미지라 갱신 불필요
        let snapTime = max(0.1, r.trimEnd)

        func applyNewThumbnail(_ img: UIImage) {
            guard self.workingRecipes.indices.contains(idx) else { return }
            let newRef = ClipThumbStore.save(img)
            self.workingRecipes[idx].thumbnail = img
            if let newRef { self.workingRecipes[idx].thumbRef = newRef }
        }

        if let avAsset = r.resolvedAsset {
            let gen = AVAssetImageGenerator(asset: avAsset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 400, height: 400)
            gen.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.3, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter  = CMTimeMakeWithSeconds(0.3, preferredTimescale: 600)
            let t = CMTimeMakeWithSeconds(snapTime, preferredTimescale: 600)
            gen.generateCGImageAsynchronously(for: t) { cgImg, _, _ in
                guard let cgImg else { return }
                let img = UIImage(cgImage: cgImg)
                DispatchQueue.main.async { applyNewThumbnail(img) }
            }
        } else if let ref = r.clipVideoRef, let url = ClipVideoStore.fileURL(ref: ref) {
            Task {
                if let img = await VideoExportService.frame(of: url, at: snapTime) {
                    await MainActor.run { applyNewThumbnail(img) }
                }
            }
        }
    }

    // MARK: - Commit

    /// 완료 버튼: workingRecipes를 binding에 커밋. 시트가 열려 있는 동안 부모가 async로 주입한
    /// resolvedAsset이 있으면 로컬 복사본에 병합하여 보존한다.
    private func commitWorkingRecipes() {
        var toSave = workingRecipes
        for i in toSave.indices where i < recipes.count {
            if toSave[i].resolvedAsset == nil, let resolved = recipes[i].resolvedAsset {
                toSave[i].resolvedAsset = resolved
            }
        }
        recipes = toSave
        // toSave를 직접 전달 — @State 갱신 배치 타이밍에 무관하게 새 값 즉시 사용 가능
        if onCommit != nil {
            onCommit?(toSave)
        } else {
        }
    }

    // MARK: - Sheet-local PHAsset resolution

    /// 시트가 독립적으로 workingRecipes에 resolvedAsset을 주입.
    /// 부모 resolveVideoClips() 완료 여부와 무관하게 시트 내에서 즉시 영상을 표시한다.
    private func resolveClipInSheet(_ i: Int) {
        guard workingRecipes.indices.contains(i) else { return }
        let r = workingRecipes[i]
        // 사진 클립이거나 이미 해석됨 → skip
        guard r.storedPhotoRef == nil, r.resolvedAsset == nil else { return }
        // clipVideoRef 안정 복사본이 있으면 AVURLAsset으로 직접 재생 가능 → skip
        if let ref = r.clipVideoRef, ClipVideoStore.fileExists(ref: ref) { return }
        // 실제 URL 파일이 이미 존재하면 → skip
        if FileManager.default.fileExists(atPath: r.url.path) { return }
        guard let assetID = r.assetIdentifier,
              !resolvingIDs.contains(assetID) else { return }

        resolvingIDs.insert(assetID)
        Task {
            do {
                let avAsset = try await MultiClipComposition.resolveAVAsset(assetID: assetID)
                await MainActor.run {
                    if let idx = workingRecipes.firstIndex(where: { $0.assetIdentifier == assetID }) {
                        workingRecipes[idx].resolvedAsset = avAsset
                        // AVAsset 확보 → 포스터 프레임을 trimStart 정확 프레임으로 교체
                        sheetPreviewFrames.removeValue(forKey: idx)
                        frameLoadingIdx.remove(idx)
                        resolvePreviewFrame(idx)
                    }
                    resolvingIDs.remove(assetID)
                }
            } catch {
                await MainActor.run {
                    resolvingIDs.remove(assetID)
                    failedClipIDs.insert(assetID)
                }
            }
        }
    }

    /// localIdentifier → 정지 프레임 해석.
    /// 콜백 안에서 DispatchQueue.main.async로 @State에 직접 대입 → SwiftUI 확실 갱신.
    /// AVAsset 미확보: PHImageManager.requestImage(포스터 프레임, 빠름)
    /// AVAsset 확보 후: AVAssetImageGenerator(trimStart 정확 프레임)
    private func resolvePreviewFrame(_ i: Int) {
        guard workingRecipes.indices.contains(i),
              !frameLoadingIdx.contains(i) else { return }
        let r = workingRecipes[i]
        guard r.storedPhotoRef == nil,
              r.assetIdentifier != nil || r.clipVideoRef != nil else { return }

        frameLoadingIdx.insert(i)
        // t=0 정확 요청 시 AVAssetImageGenerator가 빈 프레임 반환할 수 있음 → 최소 0.1s
        let snapTime = max(0.1, r.trimStart)

        // DispatchQueue.main.async로 @State에 직접 대입 (백그라운드 콜백 → 메인 스레드)
        let commitFrame: (UIImage?, String) -> Void = { img, _ in
            DispatchQueue.main.async {
                if let img { self.sheetPreviewFrames[i] = img }
                self.frameLoadingIdx.remove(i)
                self.sheetPreviewVersion &+= 1  // 딕셔너리 변경 → re-render 강제
            }
        }

        if let avAsset = r.resolvedAsset {
            // 정확: AVAssetImageGenerator trimStart 프레임
            let gen = AVAssetImageGenerator(asset: avAsset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 540, height: 960)
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter  = CMTimeMakeWithSeconds(0.5, preferredTimescale: 600)
            let t = CMTimeMakeWithSeconds(snapTime, preferredTimescale: 600)
            gen.generateCGImageAsynchronously(for: t) { cgImg, _, _ in
                commitFrame(cgImg.map { UIImage(cgImage: $0) }, "")
            }
        } else if let assetID = r.assetIdentifier {
            // 빠른: PHImageManager.requestImage 포스터 프레임
            guard let phAsset = PHAsset.fetchAssets(
                withLocalIdentifiers: [assetID], options: nil).firstObject else {
                frameLoadingIdx.remove(i)
                return
            }
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: phAsset,
                targetSize: CGSize(width: 540, height: 960),
                contentMode: .aspectFill,
                options: opts
            ) { img, info in
                // isDegraded = true이면 저화질 임시 결과 → skip, 고화질 결과만 사용
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded else { return }
                commitFrame(img, "")
            }
        } else if let ref = r.clipVideoRef, let url = ClipVideoStore.fileURL(ref: ref) {
            // clipVideoRef 안정 복사 → firstFrame (async/await 경로, main 보장됨)
            Task {
                let img = await VideoExportService.firstFrame(of: url)
                await MainActor.run {
                    if let img { sheetPreviewFrames[i] = img }
                    frameLoadingIdx.remove(i)
                }
            }
        } else {
            frameLoadingIdx.remove(i)
        }
    }

    private func replaceCurrentPhoto(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let img  = UIImage(data: data) else { return }
            let newRef  = OneLinerPhotoStore.save(img)
            let jpegURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("mimo_photoclip_\(UUID().uuidString).jpg")
            if let jpeg = img.jpegData(compressionQuality: 0.82) { try? jpeg.write(to: jpegURL) }
            await MainActor.run {
                guard workingRecipes.indices.contains(currentPage) else { return }
                if let old = workingRecipes[currentPage].storedPhotoRef {
                    OneLinerPhotoStore.delete(mediaRef: old)
                }
                // Preserve lines, style, duration — only swap the image
                workingRecipes[currentPage].url            = jpegURL
                workingRecipes[currentPage].thumbnail      = img
                workingRecipes[currentPage].storedPhotoRef = newRef
            }
        }
    }

    private func replaceCurrentVideo(_ item: PhotosPickerItem) {
        Task {
            guard let result = try? await item.loadTransferable(type: VideoPickerResult.self) else { return }
            let tempURL = result.url
            let newDur  = (try? await AVURLAsset(url: tempURL).load(.duration).seconds) ?? 0
            guard newDur > 0 else { return }
            let thumb   = await VideoExportService.firstFrame(of: tempURL)

            // 소스 결정: assetIdentifier 우선, 없으면 파일 복사
            let assetID = item.itemIdentifier
            var stableURL = tempURL
            var clipVideoRef: String? = nil
            var resolvedAsset: AVAsset? = nil

            if let id = assetID {
                resolvedAsset = try? await MultiClipComposition.resolveAVAsset(assetID: id)
            } else {
                let ref = ClipVideoStore.save(from: tempURL)
                clipVideoRef = ref
                stableURL = ref.flatMap { ClipVideoStore.fileURL(ref: $0) } ?? tempURL
            }
            await MainActor.run {
                guard workingRecipes.indices.contains(currentPage) else { return }
                // 이전 클립 파일 정리
                if let old = workingRecipes[currentPage].thumbRef     { ClipThumbStore.delete(ref: old) }
                if let old = workingRecipes[currentPage].clipVideoRef { ClipVideoStore.delete(ref: old) }
                // 새 소스 설정
                workingRecipes[currentPage].url             = stableURL
                workingRecipes[currentPage].thumbnail       = thumb
                workingRecipes[currentPage].thumbRef        = thumb.flatMap { ClipThumbStore.save($0) }
                workingRecipes[currentPage].assetIdentifier = assetID
                workingRecipes[currentPage].clipVideoRef    = clipVideoRef
                workingRecipes[currentPage].resolvedAsset   = resolvedAsset
                workingRecipes[currentPage].fullDuration    = newDur
                workingRecipes[currentPage].trimStart       = 0
                workingRecipes[currentPage].trimEnd         = newDur
                // Adjust lines array to new clip length
                let newCount = max(1, min(10, Int(newDur / 6.0)))
                let oldLines = workingRecipes[currentPage].lines
                workingRecipes[currentPage].lines = (0..<newCount).map { i in
                    i < oldLines.count ? oldLines[i] : ""
                }
            }
        }
    }

    // MARK: - Helpers

    private func lineBinding(for i: Int) -> Binding<String> {
        Binding {
            guard currentRecipeValid, i < workingRecipes[currentPage].lines.count else { return "" }
            return workingRecipes[currentPage].lines[i]
        } set: { newVal in
            guard currentRecipeValid else { return }
            let v = String(newVal.replacingOccurrences(of: "\n", with: "").prefix(charLimit))
            while workingRecipes[currentPage].lines.count <= i {
                workingRecipes[currentPage].lines.append("")
            }
            workingRecipes[currentPage].lines[i] = v
        }
    }

    private func formatSec(_ s: Double) -> String {
        let i = Int(s)
        return "\(i / 60):\(String(format: "%02d", i % 60))"
    }

    #if DEBUG
    // [SizeAudit] 폰트·가독성 전환 후 baseFontSize와 capH 픽셀을 출력.
    // 같은 sizeLevel에서 border/plate/none 전환 및 폰트 전환 이력과 무관하게 capH가 ±1px 이내여야 함.
    private func sizeAuditLog(_ label: String) {
        guard currentRecipeValid else { return }
        let r    = workingRecipes[currentPage]
        let base = OneLinerFont.basePt * r.fontChoice.sizeScale * r.sizeLevel.scale
        let capH30: CGFloat
        switch r.fontChoice {
        case .pen:         capH30 = 20.22
        case .gothic:      capH30 = 21.45
        case .blackGothic: capH30 = 21.03
        }
        let capHpx = capH30 * (base / 30.0) * 3
        print("[SizeAudit] \(label): \(r.fontChoice.rawValue)/\(r.sizeLevel.rawValue) border=\(r.hasBorder) → \(String(format: "%.2f", base))pt capH=\(String(format: "%.1f", capHpx))px@3x")
    }
    #endif

    @ViewBuilder
    private var photoDurationPicker: some View {
        if currentRecipeValid {
            let dur = workingRecipes[currentPage].trimmedDuration
            let photoCount = workingRecipes.filter { $0.storedPhotoRef != nil }.count
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ForEach([3.0, 4.0, 5.0], id: \.self) { sec in
                        Button {
                            workingRecipes[currentPage].fullDuration = sec
                            workingRecipes[currentPage].trimEnd      = sec
                            workingRecipes[currentPage].trimStart    = 0
                        } label: {
                            Text(AppLanguage.shared.s("\(Int(sec))초", "\(Int(sec)) s"))
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(dur == sec ? Theme.violet : Color(hex: "1E1E28"))
                                .foregroundStyle(dur == sec ? Color.white : Color.secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    PhotosPicker(selection: $replacePhotoPicker,
                                 maxSelectionCount: 1, matching: .images) {
                        Label(AppLanguage.shared.s("사진 교체", "Replace"),
                              systemImage: "photo.badge.arrow.down")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                // 사진이 2장 이상일 때: 현재 설정값을 전체에 일괄 적용하는 버튼
                if photoCount > 1 {
                    Button {
                        let sec = workingRecipes[currentPage].trimmedDuration
                        for i in workingRecipes.indices {
                            guard workingRecipes[i].storedPhotoRef != nil else { continue }
                            workingRecipes[i].fullDuration = sec
                            workingRecipes[i].trimEnd      = sec
                            workingRecipes[i].trimStart    = 0
                        }
                    } label: {
                        Label(AppLanguage.shared.s(
                                "전체 \(photoCount)장에 \(Int(dur))초 적용",
                                "Apply \(Int(dur))s to all \(photoCount) photos"),
                              systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

}

/// 초 → "m:ss" 형식 (TrimBarView 레이블 공용)
func trimFormatSec(_ s: Double) -> String {
    let i = Int(max(0, s))
    return "\(i / 60):\(String(format: "%02d", i % 60))"
}

// MARK: - TrimBarView
//
// Orange-highlighted range bar between two draggable handles.
// Handles move independently; minimum trim = 0.5 s.

struct TrimBarView: View {
    let duration: Double
    @Binding var trimStart: Double
    @Binding var trimEnd:   Double
    /// 드래그 완료 시 호출 — 미리보기 재빌드 트리거에 사용.
    var onEditingEnded: (() -> Void)? = nil

    private let barHeight: CGFloat = 24
    private let handleW:   CGFloat = 18
    private let minTrim:   Double  = 0.5

    var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let usable = totalW - handleW * 2

            let startX = handleW + CGFloat(trimStart / duration) * usable
            let endX   = handleW + CGFloat(trimEnd   / duration) * usable

            ZStack(alignment: .leading) {
                // Full track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray4))
                    .frame(height: 6)
                    .padding(.horizontal, handleW)

                // Active range
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: max(0, endX - startX), height: 6)
                    .offset(x: startX)

                // Start handle
                handle(symbol: "chevron.left")
                    .offset(x: startX - handleW)
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { v in
                            let raw = Double((v.location.x - handleW) / usable) * duration
                            trimStart = max(0, min(raw, trimEnd - minTrim))
                        }
                        .onEnded { _ in onEditingEnded?() }
                    )

                // End handle
                handle(symbol: "chevron.right")
                    .offset(x: endX - handleW)
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { v in
                            let raw = Double((v.location.x - handleW) / usable) * duration
                            trimEnd = min(duration, max(raw, trimStart + minTrim))
                        }
                        .onEnded { _ in onEditingEnded?() }
                    )
            }
            .frame(height: barHeight)
        }
        .frame(height: barHeight)
    }

    @ViewBuilder
    private func handle(symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.orange)
            .frame(width: handleW, height: barHeight)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - ClipVideoPreview
//
// AVAsset(해석 완료 포함) → AVPlayerLayer 재생 미리보기.
// 클립 에디터 카드 배경에 썸네일 대신 실제 영상을 표시.

struct ClipVideoPreview: UIViewRepresentable {
    let asset:     AVAsset
    let trimStart: Double

    func makeUIView(context: Context) -> UIView {
        let view   = UIView()
        view.backgroundColor = .black
        let item   = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        let layer  = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        context.coordinator.player = player
        player.seek(to: CMTimeMakeWithSeconds(trimStart, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        player.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.didReachEnd),
            name: .AVPlayerItemDidPlayToEndTime, object: item)
        player.play()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVPlayerLayer {
            layer.frame = uiView.bounds
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.player?.pause()
        NotificationCenter.default.removeObserver(coordinator)
    }

    func makeCoordinator() -> Coordinator { Coordinator(trimStart: trimStart) }

    final class Coordinator: NSObject {
        var player: AVPlayer?
        let trimStart: Double
        init(trimStart: Double) { self.trimStart = trimStart }

        @objc func didReachEnd() {
            player?.seek(to: CMTimeMakeWithSeconds(trimStart, preferredTimescale: 600),
                         toleranceBefore: .zero, toleranceAfter: .zero)
            player?.play()
        }
    }
}

// MARK: - KeyboardDismissBackground
//
// 배경 탭 → 키보드 해제 전용 UIViewRepresentable.
// UITapGestureRecognizer를 background UIView에 직접 설치하여,
// UITextField/UITextView 계층 탭(편집 메뉴 포함)은 hit-test 체인에서 제외되므로
// 제스처가 발동하지 않는다 — 편집 메뉴/커서 이동이 그대로 동작.

private struct KeyboardDismissBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.dismiss))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @objc func dismiss() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        func gestureRecognizer(
            _ gr: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            // belt-and-suspenders: 텍스트 필드/뷰 계층 터치는 명시적으로 거부
            var v: UIView? = touch.view
            while let view = v {
                if view is UITextField || view is UITextView || view is UIControl { return false }
                v = view.superview
            }
            return true
        }
        func gestureRecognizer(
            _ gr: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}

// MARK: - RouteMiniMap (경로 흰선 미니맵)

struct RouteMiniMap: View {
    let coords: [CLLocationCoordinate2D]
    var body: some View {
        GeometryReader { geo in
            Path { p in
                guard coords.count >= 2 else { return }
                let lats = coords.map { $0.latitude }
                let lons = coords.map { $0.longitude }
                let minLat = lats.min()!, maxLat = lats.max()!
                let minLon = lons.min()!, maxLon = lons.max()!
                // 종횡비 유지: 큰 범위를 기준으로 정규화 + 중앙 정렬
                let range = max(1e-6, max(maxLat - minLat, maxLon - minLon))
                let padX = (range - (maxLon - minLon)) / 2
                let padY = (range - (maxLat - minLat)) / 2
                let inset = min(geo.size.width, geo.size.height) * 0.1
                let dim = min(geo.size.width, geo.size.height) - inset * 2
                func pt(_ c: CLLocationCoordinate2D) -> CGPoint {
                    let nx = (c.longitude - minLon + padX) / range
                    let ny = (c.latitude  - minLat + padY) / range
                    return CGPoint(x: inset + nx * dim, y: inset + (1 - ny) * dim)   // 북쪽이 위
                }
                p.move(to: pt(coords[0]))
                for c in coords.dropFirst() { p.addLine(to: pt(c)) }
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.5), radius: 1)
        }
    }
}

// MARK: - HRLineChart (심박 흰색 라인차트)

struct HRLineChart: View {
    let samples: [(offset: TimeInterval, bpm: Int)]
    var body: some View {
        GeometryReader { geo in
            Path { p in
                guard samples.count >= 2 else { return }
                let bpms = samples.map { Double($0.bpm) }
                let minB = bpms.min()!, maxB = bpms.max()!
                let rangeB = max(1, maxB - minB)
                let t0 = samples.first!.offset, t1 = samples.last!.offset
                let dt = max(1, t1 - t0)
                func pt(_ i: Int) -> CGPoint {
                    let x = (samples[i].offset - t0) / dt * geo.size.width
                    let y = (1 - (Double(samples[i].bpm) - minB) / rangeB) * geo.size.height
                    return CGPoint(x: x, y: y)
                }
                p.move(to: pt(0))
                for i in 1..<samples.count { p.addLine(to: pt(i)) }
            }
            .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.4), radius: 1)
        }
    }
}
