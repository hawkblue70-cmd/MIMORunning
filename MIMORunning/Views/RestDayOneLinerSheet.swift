import SwiftUI
import SwiftData
import Combine
import Photos
import PhotosUI
import AVFoundation
import UIKit
import CoreLocation

// MARK: - RestDayOneLinerSheet
//
// OneLiner card editor for rest days.
// workoutID = "date:yyyy-MM-dd"  (see OneLinerEntry.restDayWorkoutID)
//
// Text slot model:
//   • slotTexts[i]   — text for backgroundPhotos[i]  (parallel array)
//   • orphanedTexts  — texts whose photo was deleted; reused when new photos arrive

struct RestDayOneLinerSheet: View {
    let date: Date

    // 운동한 날 지원 (nil = 쉬는날). 있으면 러닝 데이터 오버레이 토글까지 노출.
    var activity:         Activity? = nil
    var availableMetrics: [MetricItem] = []
    var routeCoords:      [CLLocationCoordinate2D] = []
    var hrSamples:         [(offset: TimeInterval, bpm: Int)] = []
    var splits:            [SplitData] = []
    var chartSeriesData:   [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:]
    var hrZones:           [HRZoneData] = []
    var intervalSegments:  [IntervalSegment] = []
    /// true = 공유 카드(2번째 카드)에 인라인으로 심을 때. 시트 껍데기(NavigationStack·닫기 툴바) 제거.
    var embedded:         Bool = false
    /// 미리보기 바로 아래에 끼워 넣을 뷰(공유 카드의 페이지 점 등). embedded일 때만 사용.
    var belowPreview:     AnyView? = nil

    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss)      private var dismiss

    @Query var allEntries: [OneLinerEntry]

    // 운동한 날이면 activity.id, 쉬는날이면 date 기반 ID로 저장 분리.
    var workoutID: String {
        activity.map { $0.id.uuidString } ?? OneLinerEntry.restDayWorkoutID(for: date)
    }

    var gradientEntry: OneLinerEntry? {
        allEntries.first { $0.workoutID == workoutID && $0.mediaRef == nil }
    }
    var photoEntries: [OneLinerEntry] {
        allEntries
            .filter { $0.workoutID == workoutID && $0.mediaRef?.hasPrefix("restphoto:") == true }
            .sorted { $0.createdAt < $1.createdAt }
    }
    var videoTextEntry: OneLinerEntry? {
        allEntries.first { $0.workoutID == workoutID && $0.mediaRef == "videotexts" }
    }

    // MARK: State
    @State var text:             String            = ""   // gradient-mode text
    @State var fontChoice:       OneLinerFont      = .pen
    @State var textColor:        OneLinerTextColor = .gold
    @State var position:         CardPosition      = .bottom
    @State var backgroundPhotos:   [UIImage]          = []
    @State var photoPickerItems:   [PhotosPickerItem] = []
    @State var selectedPhotoIndex: Int                = 0
    @State var clipRecipes:           [ClipRecipe]       = []
    @State var storyModeRecipes:      [ClipRecipe]       = []
    @State var videoModeRecipes:      [ClipRecipe]       = []
    @State var slideModeRecipes:      [ClipRecipe]       = []
    @State var enabledMetricIDs:      Set<String>        = []
    @State var savedClipLines:        [[String]]         = []
    @State var currentClipIndex:      Int                = 0
    @State var slotTexts:          [String]           = []
    @State var orphanedTexts:      [String]           = []
    @State var draggingPhotoIndex: Int?               = nil
    @State var selectedTemplate:  RestDayTemplate     = .story
    @State var isExportingVideo:  Bool                = false
    @State var muteVideoAudio:    Bool                = false
    @State var videoTitle:        String               = ""
    @State var titleStyle:        OneLinerTitleStyle   = OneLinerTitleStyle()
    @State var videoModeTitle:    String               = ""
    @State var videoModeTitleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    @State var slideModeTitle:    String               = ""
    @State var slideModeTitleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    @StateObject private var loadGuard:  RestDayLoadGuard     = RestDayLoadGuard()
    @State var previewPlayer:    OneLinerPreviewPlayer = OneLinerPreviewPlayer()
    @State var exportError:     String?              = nil
    @State var cropDragBase:    CGFloat?             = nil

    @FocusState private var fieldFocused: Bool
    @FocusState private var focusedLineIndex: Int?

    // MARK: Computed
    var isVideoMode: Bool { !clipRecipes.isEmpty }
    var videoFirstFrame: UIImage? { clipRecipes.first?.thumbnail }
    var videoTotalSeconds: Double { MultiClipComposition.totalDuration(recipes: clipRecipes) }
    var videoClipCount: Int { clipRecipes.count }

    var shareButtonActive: Bool {
        guard !isExportingVideo else { return false }
        switch selectedTemplate {
        case .video, .slide: return isVideoMode && videoTotalSeconds <= MultiClipComposition.maxSeconds
        case .story:         return true
        }
    }

    var cardBackground: UIImage? {
        if selectedTemplate == .video || selectedTemplate == .slide || selectedTemplate == .story {
            let safeIdx = clipRecipes.indices.contains(currentClipIndex) ? currentClipIndex : 0
            return clipRecipes.indices.contains(safeIdx) ? clipRecipes[safeIdx].thumbnail : clipRecipes.first?.thumbnail
        }
        guard !backgroundPhotos.isEmpty else { return nil }
        return backgroundPhotos[min(selectedPhotoIndex, backgroundPhotos.count - 1)]
    }

    /// Text shown on the card preview.
    /// Joins all non-empty lines so the static preview matches what the user entered.
    var cardText: String {
        if selectedTemplate == .story || selectedTemplate == .video || selectedTemplate == .slide {
            let safeIdx = clipRecipes.indices.contains(currentClipIndex) ? currentClipIndex : 0
            let clip = clipRecipes.indices.contains(safeIdx) ? clipRecipes[safeIdx] : clipRecipes.first
            return clip?.lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n") ?? ""
        }
        if !backgroundPhotos.isEmpty, selectedPhotoIndex < slotTexts.count {
            return slotTexts[selectedPhotoIndex]
        }
        return ""
    }

    var isClipMode: Bool { selectedTemplate == .video || selectedTemplate == .slide }
    var isPhotoSlideMode: Bool { selectedTemplate == .slide || selectedTemplate == .story }
    /// 팝업 없이 인라인으로 편집하는 모드 (쉬는날 전체 — 러닝 데이터 없음)
    var isInlineEditMode: Bool { true }

    /// availableMetrics → VideoMetricChip 조회 (export의 per-clip P/D/T/B 칩 렌더링용)
    var metricLookup: [String: VideoMetricChip] {
        Dictionary(uniqueKeysWithValues: availableMetrics.map {
            ($0.id, VideoMetricChip(value: $0.value, label: $0.label, uiColor: $0.uiColor))
        })
    }

    // Per-clip preview style — used by OneLinerCard when in video/slide/story mode
    var previewFont: OneLinerFont {
        if (isClipMode || selectedTemplate == .story), clipRecipes.indices.contains(currentClipIndex) {
            return clipRecipes[currentClipIndex].fontChoice
        }
        return fontChoice
    }
    var previewTextColor: OneLinerTextColor {
        if (isClipMode || selectedTemplate == .story), clipRecipes.indices.contains(currentClipIndex) {
            return clipRecipes[currentClipIndex].textColor
        }
        return textColor
    }
    var previewPosition: CardPosition {
        if (isClipMode || selectedTemplate == .story), clipRecipes.indices.contains(currentClipIndex) {
            return clipRecipes[currentClipIndex].position
        }
        return position
    }
    var previewSizeLevel: TextSizeLevel {
        if (isClipMode || selectedTemplate == .story), clipRecipes.indices.contains(currentClipIndex) {
            return clipRecipes[currentClipIndex].sizeLevel
        }
        return .medium
    }
    var previewAppearanceMode: AppearanceMode {
        if (isClipMode || selectedTemplate == .story), clipRecipes.indices.contains(currentClipIndex) {
            return clipRecipes[currentClipIndex].appearanceMode
        }
        return .typing
    }
    var previewDecorEffect: DecorEffect {
        if (isClipMode || selectedTemplate == .story), clipRecipes.indices.contains(currentClipIndex) {
            return clipRecipes[currentClipIndex].decorEffect
        }
        return .none
    }
    var previewHasBorder: Bool {
        guard (isClipMode || selectedTemplate == .story),
              clipRecipes.indices.contains(currentClipIndex) else { return false }
        return clipRecipes[currentClipIndex].hasBorder
    }
    // 슬라이드/영상 미리보기(9:16)에서 현재 클립의 차트가 차지하는 하단 높이(pt).
    // captionContent가 이 값으로 텍스트를 차트 위로 밀어 올려 겹침을 방지한다.
    var isClipChartBottomReserved: CGFloat {
        guard clipRecipes.indices.contains(currentClipIndex) else { return 0 }
        let recipe = clipRecipes[currentClipIndex]
        let pH: CGFloat = CardPreviewFrame.width * 16 / 9
        let botPad: CGFloat = 10
        if recipe.showHRChart && hrSamples.count >= 2 { return pH * 0.264 + botPad }
        if recipe.chartOverlayType == .route && !routeCoords.isEmpty { return pH * 0.264 + botPad }
        if recipe.chartOverlayType == .splits {
            let fc = splits.filter { $0.distanceM >= 900 }.count
            if fc >= 2 {
                let dc = fc > 21 ? fc / 2 : fc
                return 34 + CGFloat(dc) * 7 + botPad
            }
        }
        if recipe.chartOverlayType == .intervals {
            let d = intervalSegments.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            if d > 0 { return pH * 0.42 + botPad }
        }
        let gt = recipe.chartOverlayType
        if ![.none, .route, .hrChart, .splits, .intervals].contains(gt),
           let s = chartSeriesData[gt], s.count >= 2 { return pH * 0.264 + botPad }
        return 0
    }

    // MARK: Body
    var body: some View { mainContent }

    @ViewBuilder
    private var mainContent: some View {
        navStack
            .interactiveDismissDisabled(previewPlayer.isReady)
            .onAppear {
                // @StateObject 가드: re-render·child-sheet 닫힘에 재실행 방지. @State보다 확실.
                guard !loadGuard.hasLoaded else { return }
                loadGuard.hasLoaded = true
                loadEntry()
            }
            .onChange(of: allEntries) { old, _ in
                // SwiftData 비동기 초기 로드 폴백: 첫 쿼리 결과가 빈 배열로 온 뒤 갱신될 때만 허용.
                guard old.isEmpty, !loadGuard.hasLoaded else { return }
                loadGuard.hasLoaded = true
                loadEntry()
            }
            .onChange(of: photoPickerItems) { _, items in handlePhotoPicker(items) }
            .onChange(of: clipRecipes.count) { _, _ in
                previewPlayer.invalidate()
            }
            .onChange(of: videoTitle)     { _, _ in previewPlayer.invalidate() }
            .onChange(of: titleStyle)     { _, _ in previewPlayer.invalidate() }
            .onChange(of: muteVideoAudio) { _, muted in previewPlayer.setMuted(muted) }
            .alert(AppLanguage.shared.s("내보내기 실패", "Export Failed"),
                   isPresented: Binding(get: { exportError != nil },
                                        set: { if !$0 { exportError = nil } })) {
                Button(AppLanguage.shared.s("확인", "OK"), role: .cancel) { exportError = nil }
            } message: {
                if let msg = exportError { Text(msg) }
            }
    }

    @ViewBuilder
    private var navStack: some View {
        if embedded {
            // 공유 카드에 인라인 심기: NavigationStack·닫기 툴바 없이 편집 본문만.
            // 영상 미리보기 중이면 닫기 대신 미리보기 종료 버튼만 상단에 노출.
            VStack(spacing: 0) {
                if previewPlayer.isReady {
                    HStack {
                        Button(AppLanguage.shared.s("미리보기 닫기", "Close preview")) {
                            previewPlayer.pause()
                            previewPlayer.invalidate()
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.top, 4)
                }
                scrollArea
                shareBar
            }
        } else {
            NavigationStack {
                VStack(spacing: 0) {
                    scrollArea
                    shareBar
                }
                .navigationTitle(dateTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(AppLanguage.shared.s("닫기", "Close")) {
                            if previewPlayer.isReady {
                                previewPlayer.pause()
                                previewPlayer.invalidate()
                            } else {
                                dismiss()
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var shareBar: some View {
        Button { renderCardForSharing() } label: { shareButtonLabel }
            .disabled(!shareButtonActive)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(hex: "0E0E18"))
    }

    // MARK: - Sub-views

    private var scrollArea: some View {
        ZStack {
            Color(hex: "0E0E18").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    cardPreview
                        .frame(height: OneLinerCard.cardHeight)
                        .padding(.top, 16)
                    if let belowPreview { belowPreview }   // 공유 카드 페이지 점(미리보기 바로 밑)
                    controlsArea
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }

    @ViewBuilder
    private var cardPreview: some View {
        if previewPlayer.isReady,
           let pl = previewPlayer.player,
           let cl = previewPlayer.contentLayer {
            // 9:16 영상을 4:5 높이에 맞게 비례 축소 (211×375pt) — 아래 편집 영역이 가려지지 않도록
            let previewW: CGFloat = 211
            OneLinerPreviewView(player: pl, contentLayer: cl, renderSize: previewPlayer.renderSize)
                .frame(width: previewW, height: OneLinerCard.cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
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
                .contentShape(Rectangle())
                .onTapGesture { previewPlayer.togglePlayPause() }
                .frame(maxWidth: .infinity)
        } else if isClipMode {
            // 9:16 카드를 4:5 높이(375pt)에 맞게 비례 축소 — 라이브 프리뷰와 동일한 높이 유지
            let pH: CGFloat = CardPreviewFrame.width * 16 / 9
            let scale: CGFloat = OneLinerCard.cardHeight / pH
            let scaledW: CGFloat = CardPreviewFrame.width * scale
            let clipRecipe = clipRecipes.indices.contains(currentClipIndex) ? clipRecipes[currentClipIndex] : nil
            let safeClipIdx = clipRecipes.indices.contains(currentClipIndex) ? currentClipIndex : 0
            let clipCropX   = clipRecipe?.cropOffsetX ?? 0.5
            let clipExcess: CGFloat = {
                guard let t = cardBackground else { return 0 }
                let s: CGFloat = t.size.height >= t.size.width
                    ? pH / t.size.height
                    : CardPreviewFrame.width / t.size.width
                return max(0, t.size.width * s - CardPreviewFrame.width) * scale
            }()
            OneLinerCard(
                backgroundPhoto: cardBackground,
                cropOffsetX: clipCropX,
                text: cardText,
                position: previewPosition,
                textColor: previewTextColor,
                fontChoice: previewFont,
                sizeLevel: previewSizeLevel,
                appearanceMode: previewAppearanceMode,
                decorEffect: previewDecorEffect,
                hasBorder: previewHasBorder,
                captionMode: true,
                chartBottomReserved: isClipChartBottomReserved,
                videoTitle: selectedTemplate != .story ? videoTitle : "",
                titleStyle: titleStyle,
                cardHeightOverride: pH,
                routeCoords: routeCoords,
                showHRChart: clipRecipe?.showHRChart ?? false,
                hrSamples: hrSamples,
                hrZones: hrZones,
                chartOverlayType: clipRecipe?.chartOverlayType ?? .none,
                chartSeriesData: chartSeriesData,
                chartSplits: splits,
                intervalSegments: intervalSegments
            )
            .frame(width: CardPreviewFrame.width, height: pH)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            .overlay(alignment: .center) {
                if previewPlayer.isBuilding {
                    ProgressView().tint(.white)
                        .padding(16)
                        .background(.black.opacity(0.45))
                        .clipShape(Circle())
                } else if isVideoMode {
                    Button { buildPreview() } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.55), radius: 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .scaleEffect(scale)
            .frame(width: scaledW, height: OneLinerCard.cardHeight)
            .gesture(
                clipExcess > 0 ? DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        if cropDragBase == nil { cropDragBase = clipCropX }
                        guard let base = cropDragBase,
                              clipRecipes.indices.contains(safeClipIdx) else { return }
                        clipRecipes[safeClipIdx].cropOffsetX = max(0, min(1,
                            base - drag.translation.width / clipExcess))
                    }
                    .onEnded { _ in
                        cropDragBase = nil
                        handleRecipesChanged()
                    }
                : nil
            )
            .frame(maxWidth: .infinity)
        } else {
            let storySafeIdx = clipRecipes.indices.contains(currentClipIndex) ? currentClipIndex : 0
            let storyCropX   = clipRecipes.indices.contains(storySafeIdx) ? clipRecipes[storySafeIdx].cropOffsetX : 0.5
            let storyExcess: CGFloat = {
                guard let t = cardBackground else { return 0 }
                let s: CGFloat = t.size.height >= t.size.width
                    ? OneLinerCard.cardHeight / t.size.height
                    : OneLinerCard.cardWidth  / t.size.width
                return max(0, t.size.width * s - OneLinerCard.cardWidth)
            }()
            OneLinerCard(
                backgroundPhoto: cardBackground,
                cropOffsetX: storyCropX,
                text: cardText,
                position: previewPosition,
                textColor: previewTextColor,
                fontChoice: previewFont,
                sizeLevel: previewSizeLevel,
                appearanceMode: previewAppearanceMode,
                decorEffect: previewDecorEffect,
                hasBorder: previewHasBorder,
                captionMode: true,
                videoTitle: selectedTemplate != .story ? videoTitle : "",
                titleStyle: titleStyle,
                isStaticPreview: true
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            .overlay(alignment: .center) {
                if previewPlayer.isBuilding {
                    ProgressView().tint(.white)
                        .padding(16)
                        .background(.black.opacity(0.45))
                        .clipShape(Circle())
                } else if isClipMode && isVideoMode {
                    Button { buildPreview() } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.55), radius: 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .gesture(
                storyExcess > 0 ? DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        if cropDragBase == nil { cropDragBase = storyCropX }
                        guard let base = cropDragBase,
                              clipRecipes.indices.contains(storySafeIdx) else { return }
                        clipRecipes[storySafeIdx].cropOffsetX = max(0, min(1,
                            base - drag.translation.width / storyExcess))
                    }
                    .onEnded { _ in
                        cropDragBase = nil
                        handleRecipesChanged()
                    }
                : nil
            )
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var controlsArea: some View {
        VStack(spacing: 12) {
            templateTabs
            if !clipRecipes.isEmpty { gridAndChips }
            if isInlineEditMode, !clipRecipes.isEmpty { storyClipTextInput }
            templateMediaRow
        }
    }

    private var shareButtonLabel: some View {
        HStack(spacing: 8) {
            if isExportingVideo {
                ProgressView().tint(.white)
                Text(AppLanguage.shared.s("내보내는 중...", "Exporting...")).fontWeight(.semibold)
            } else {
                Image(systemName: "square.and.arrow.up")
                Text(selectedTemplate == .slide
                     ? AppLanguage.shared.s("슬라이드 내보내기", "Export Slides")
                     : selectedTemplate == .video
                     ? AppLanguage.shared.s("영상 내보내기", "Export Video")
                     : AppLanguage.shared.s("스토리 내보내기", "Export Story"))
                    .fontWeight(.semibold)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(shareButtonActive ? Theme.violet : Theme.violet.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private let textLineCharLimit = 30
    private var textLineCount: Int { max(1, text.components(separatedBy: "\n").count) }

    /// Binding for an individual line within `text` (newline-joined).
    private func textLineBinding(for index: Int) -> Binding<String> {
        Binding {
            let lines = text.components(separatedBy: "\n")
            return index < lines.count ? lines[index] : ""
        } set: { newVal in
            var lines = text.components(separatedBy: "\n")
            while lines.count <= index { lines.append("") }
            lines[index] = String(newVal.prefix(textLineCharLimit))
            text = lines.prefix(textLineCount).joined(separator: "\n")
            saveEntry()
        }
    }

    /// Single text field used in gradient (no-photo) mode.
    private var oneLinerTextField: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(spacing: 6) {
                ForEach(0..<textLineCount, id: \.self) { i in
                    let lineText = { () -> String in
                        let lines = text.components(separatedBy: "\n")
                        return i < lines.count ? lines[i] : ""
                    }()
                    HStack(spacing: 8) {
                        TextField(
                            AppLanguage.shared.s(i == 0 ? "오늘의 한마디" : "\(i + 1)번째 줄",
                                                 i == 0 ? "Your one-liner" : "Line \(i + 1)"),
                            text: textLineBinding(for: i)
                        )
                        .focused($focusedLineIndex, equals: i)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .tint(Theme.violet)
                        Spacer(minLength: 0)
                        Text("\(lineText.count)/\(textLineCharLimit)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Color(hex: "6E6E78"))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(hex: "1E1E28"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if textLineCount < 3 {
                Button {
                    text += "\n"
                    saveEntry()
                    let idx = textLineCount - 1
                    Task { @MainActor in focusedLineIndex = idx }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.violet)
                        .frame(width: 36, height: 36)
                }
            }
        }
    }

    /// Per-photo text slots (photo mode). One row per photo + orphaned rows below.
    @ViewBuilder
    private var textSlotsView: some View {
        VStack(spacing: 8) {
            ForEach(slotTexts.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        // Tiny thumbnail — tap to select this photo on the card
                        Button { selectedPhotoIndex = i } label: {
                            Image(uiImage: backgroundPhotos[i])
                                .resizable().scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(
                                            selectedPhotoIndex == i
                                            ? Theme.violet : Color.white.opacity(0.15),
                                            lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)

                        TextField(
                            AppLanguage.shared.s("사진 \(i + 1) 문구", "Caption \(i + 1)"),
                            text: slotTextBinding(for: i),
                            axis: .vertical
                        )
                        .lineLimit(1...2)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .tint(Theme.violet)

                        Spacer(minLength: 0)
                        Text("\(i < slotTexts.count ? slotTexts[i].count : 0)/40")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Color(hex: "6E6E78"))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(selectedPhotoIndex == i
                                ? Color(hex: "1E2238") : Color(hex: "1E1E28"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .onTapGesture { selectedPhotoIndex = i }
                }
            }
            orphanedSlotsView
        }
    }

    /// Orphaned text slots — texts that remain after their photo was deleted.
    @ViewBuilder
    private var orphanedSlotsView: some View {
        ForEach(orphanedTexts.indices, id: \.self) { i in
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(hex: "2A2A34"))
                        .frame(width: 32, height: 32)
                    Image(systemName: "photo.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                TextField(
                    AppLanguage.shared.s("보관된 문구", "Saved caption"),
                    text: orphanedTextBinding(for: i),
                    axis: .vertical
                )
                .lineLimit(1...2)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
                .tint(Theme.violet)

                Spacer(minLength: 0)

                Button { orphanedTexts.remove(at: i) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white.opacity(0.6), Color(hex: "2A2A34"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(hex: "181820"))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var templateTabs: some View {
        HStack(spacing: 0) {
            ForEach(RestDayTemplate.allCases, id: \.self) { tmpl in
                let isSelected = selectedTemplate == tmpl
                Button { switchTemplate(to: tmpl) } label: {
                    HStack(spacing: 4) {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(tmpl.rawValue)
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(isSelected ? .white : Color.white.opacity(0.45))
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? Color(hex: "26262E") : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var gridAndChips: some View {
        let rows: [[CardPosition]] = [
            [.topLeading, .top, .topTrailing],
            [.leading, .center, .trailing],
            [.bottomLeading, .bottom, .bottomTrailing]
        ]
        let safeIdx = clipRecipes.indices.contains(currentClipIndex) ? currentClipIndex : -1
        let hasClip = safeIdx >= 0 && (isClipMode || isInlineEditMode)
        return HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 4) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(rows[row].indices, id: \.self) { col in
                            let pos = rows[row][col]
                            let isSelected: Bool = hasClip
                                ? clipRecipes[safeIdx].position == pos
                                : position == pos
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if hasClip { clipRecipes[safeIdx].position = pos; handleRecipesChanged() }
                                    else { position = pos; saveEntry() }
                                }
                            } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isSelected ? Theme.violet : Color(hex: "26262E"))
                                    .frame(width: 23, height: 23)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if isInlineEditMode, hasClip {
                    HStack(spacing: 4) {
                        ForEach(TextSizeLevel.allCases, id: \.self) { sz in storySizeChip(sz, safeIdx: safeIdx) }
                        storyBorderChip(safeIdx: safeIdx)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(OneLinerFont.allCases, id: \.self) { f in fontChip(f, hasClip: hasClip, safeIdx: safeIdx) }
                }
                if isInlineEditMode, hasClip {
                    HStack(spacing: 10) {
                        ForEach(OneLinerTextColor.allCases, id: \.self) { c in storyColorSwatch(c, safeIdx: safeIdx) }
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach(OneLinerTextColor.allCases, id: \.self) { c in colorChip(c, hasClip: hasClip, safeIdx: safeIdx) }
                    }
                }
                if isClipMode, hasClip {
                    HStack(spacing: 4) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            storyAppearanceModeChip(mode, safeIdx: safeIdx)
                        }
                        if selectedTemplate == .video {
                            Spacer(minLength: 4)
                            Button {
                                muteVideoAudio.toggle()
                                handleRecipesChanged()
                            } label: {
                                Image(systemName: muteVideoAudio ? "speaker.slash.fill" : "speaker.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(muteVideoAudio ? .white : .white.opacity(0.55))
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(muteVideoAudio ? Color(hex: "3A3A44") : Color.white.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if clipRecipes.indices.contains(safeIdx),
                       clipRecipes[safeIdx].appearanceMode == .flyIn {
                        HStack(spacing: 4) {
                            ForEach(FlyInDirection.allCases, id: \.self) { dir in
                                storyFlyDirectionChip(dir, safeIdx: safeIdx)
                            }
                        }
                    }
                }
            }
        }
    }

    private func fontChip(_ font: OneLinerFont, hasClip: Bool, safeIdx: Int) -> some View {
        let isSelected: Bool = hasClip
            ? clipRecipes[safeIdx].fontChoice == font
            : fontChoice == font
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if hasClip { clipRecipes[safeIdx].fontChoice = font; handleRecipesChanged() }
                else { fontChoice = font; saveEntry() }
            }
        } label: {
            HStack(spacing: 4) {
                if isSelected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(font.chipLabel).font(.custom(font.fontName, size: 13))
            }
            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.5))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isSelected ? Color(hex: "3A3A44") : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func colorChip(_ tc: OneLinerTextColor, hasClip: Bool, safeIdx: Int) -> some View {
        let isSelected: Bool = hasClip
            ? clipRecipes[safeIdx].textColor == tc
            : textColor == tc
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if hasClip { clipRecipes[safeIdx].textColor = tc; handleRecipesChanged() }
                else { textColor = tc; saveEntry() }
            }
        } label: {
            HStack(spacing: 6) {
                if isSelected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                if tc != .white { Circle().fill(tc.color).frame(width: 8, height: 8) }
                Text(tc.chipLabel).font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.5))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isSelected
                        ? (tc == .white ? Color(hex: "3A3A44") : tc.color.opacity(0.25))
                        : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var templateMediaRow: some View {
        MultiClipEditorView(
            recipes: $clipRecipes,
            isPhotoSlideMode: .constant(isPhotoSlideMode),
            muteAudio: $muteVideoAudio,
            selectedClipIndex: $currentClipIndex,
            savedClipLines: savedClipLines,
            availableMetrics: availableMetrics,
            enabledMetricIDs: $enabledMetricIDs,
            routeCoords: routeCoords,
            hrSamples: hrSamples,
            splits: splits,
            chartSeriesData: chartSeriesData,
            hrZones: hrZones,
            intervalSegments: intervalSegments,
            onSave: handleRecipesChanged,
            isStoryMode: selectedTemplate == .story,
            showTitle: false,
            openEditOnTap: false,
            showEditHint: false,
            videoTitle: $videoTitle,
            titleStyle: $titleStyle
        )
    }

    // MARK: - Story mode inline text input

    @ViewBuilder
    private var storyClipTextInput: some View {
        let safeIdx = clipRecipes.indices.contains(currentClipIndex) ? currentClipIndex : 0
        if clipRecipes.indices.contains(safeIdx) {
            let currentText = clipRecipes[safeIdx].lines.first ?? ""
            let textBinding = Binding<String>(
                get: {
                    guard clipRecipes.indices.contains(safeIdx) else { return "" }
                    return clipRecipes[safeIdx].lines.first ?? ""
                },
                set: { val in
                    guard clipRecipes.indices.contains(safeIdx) else { return }
                    clipRecipes[safeIdx].lines = [String(val.prefix(30))]
                    handleRecipesChanged()
                }
            )
            HStack(spacing: 8) {
                TextField(AppLanguage.shared.s("사진 위에 문구", "Text on photo"),
                          text: textBinding)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .tint(Theme.violet)
                Spacer(minLength: 0)
                Text("\(currentText.count)/30")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(hex: "6E6E78"))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(hex: "1E1E28"))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Story mode size/border chip helpers

    private func storySizeChip(_ sz: TextSizeLevel, safeIdx: Int) -> some View {
        let isSelected = clipRecipes.indices.contains(safeIdx) && clipRecipes[safeIdx].sizeLevel == sz
        return Button {
            guard clipRecipes.indices.contains(safeIdx) else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                clipRecipes[safeIdx].sizeLevel = sz
                handleRecipesChanged()
            }
        } label: {
            Text(sz.chipLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(isSelected ? Theme.violet : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func storyBorderChip(safeIdx: Int) -> some View {
        let isOn = clipRecipes.indices.contains(safeIdx) && clipRecipes[safeIdx].hasBorder
        return Button {
            guard clipRecipes.indices.contains(safeIdx) else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                clipRecipes[safeIdx].hasBorder.toggle()
                handleRecipesChanged()
            }
        } label: {
            Text(AppLanguage.shared.s("테두리", "Outline"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? .white : .white.opacity(0.55))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(isOn ? Theme.violet : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func storyColorSwatch(_ tc: OneLinerTextColor, safeIdx: Int) -> some View {
        let isSelected = clipRecipes.indices.contains(safeIdx) && clipRecipes[safeIdx].textColor == tc
        return Button {
            guard clipRecipes.indices.contains(safeIdx) else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                clipRecipes[safeIdx].textColor = tc
                handleRecipesChanged()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(tc.color)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(
                        tc == .white ? Color.gray.opacity(0.4) : Color.clear,
                        lineWidth: 1))
                if isSelected {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func storyAppearanceModeChip(_ mode: AppearanceMode, safeIdx: Int) -> some View {
        let isSelected = clipRecipes.indices.contains(safeIdx) && clipRecipes[safeIdx].appearanceMode == mode
        return Button {
            guard clipRecipes.indices.contains(safeIdx) else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                clipRecipes[safeIdx].appearanceMode = mode
                handleRecipesChanged()
            }
        } label: {
            Text(mode.chipLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(isSelected ? Theme.violet : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func storyFlyDirectionChip(_ dir: FlyInDirection, safeIdx: Int) -> some View {
        let isSelected = clipRecipes.indices.contains(safeIdx) && clipRecipes[safeIdx].flyDirection == dir
        return Button {
            guard clipRecipes.indices.contains(safeIdx) else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                clipRecipes[safeIdx].flyDirection = dir
                handleRecipesChanged()
            }
        } label: {
            Text(dir.chipLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(isSelected ? Color(hex: "3A3A44") : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bindings

    /// Binding for photo-mode text slots. Updates slotTexts and persists on each keystroke.
    private func slotTextBinding(for index: Int) -> Binding<String> {
        Binding {
            guard index < slotTexts.count else { return "" }
            return slotTexts[index]
        } set: { newVal in
            var v = newVal
            let lines = v.components(separatedBy: "\n")
            if lines.count > 3 { v = String(lines.prefix(3).joined(separator: "\n").prefix(40)) }
            if v.count > 40   { v = String(v.prefix(40)) }
            guard index < slotTexts.count else { return }
            slotTexts[index]   = v
            selectedPhotoIndex = index
            saveEntry()
        }
    }

    /// Binding for orphaned text slots.
    private func orphanedTextBinding(for index: Int) -> Binding<String> {
        Binding {
            guard index < orphanedTexts.count else { return "" }
            return orphanedTexts[index]
        } set: { newVal in
            guard index < orphanedTexts.count else { return }
            orphanedTexts[index] = String(newVal.prefix(40))
        }
    }

    // MARK: - Helpers

    private func handlePhotoPicker(_ items: [PhotosPickerItem]) {
        Task { @MainActor in
            var images: [UIImage] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let img  = UIImage(data: data) else { continue }
                images.append(img)
            }
            guard !images.isEmpty else { return }

            var pool = slotTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                     + orphanedTexts
            if pool.isEmpty {
                let seed = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                           ? (gradientEntry?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                           : text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !seed.isEmpty { pool = [seed] }
            }
            slotTexts     = images.map { _ in pool.isEmpty ? "" : pool.removeFirst() }
            orphanedTexts = pool

            if isVideoMode { text = "" }
            clipRecipes = []
            backgroundPhotos   = images
            selectedPhotoIndex = 0
            savePhotos(images)
        }
    }

    private var dateTitle: String {
        let d = activity?.date ?? date
        let f = DateFormatter()
        f.dateFormat = "M월 d일"; f.locale = Locale(identifier: "ko_KR")
        let e = DateFormatter()
        e.dateFormat = "MMM d";  e.locale = Locale(identifier: "en_US")
        let base = AppLanguage.shared.s(f.string(from: d), e.string(from: d))
        // 운동한 날 = "오늘의 한마디", 쉬는날 = "쉬는 날"
        let suffix = activity != nil
            ? AppLanguage.shared.s("오늘의 한마디", "Today's One-liner")
            : AppLanguage.shared.s("쉬는 날", "Rest Day")
        return base + " " + suffix
    }

    private func handleRecipesChanged() {
        // Invalidate stale video preview whenever clip content changes so the
        // card preview reflects the latest edits immediately.
        if previewPlayer.isReady || previewPlayer.isBuilding {
            previewPlayer.pause()
            previewPlayer.invalidate()
        }
        saveEntry()
    }

    private func switchTemplate(to newTemplate: RestDayTemplate) {
        guard newTemplate != selectedTemplate else { return }
        syncActiveToBackingStore()
        previewPlayer.pause()
        previewPlayer.invalidate()
        withAnimation(.easeInOut(duration: 0.15)) { selectedTemplate = newTemplate }
        loadFromBackingStore(for: newTemplate)
        // 스토리→슬라이드: 스토리 사진이 있으면 항상 슬라이드에 동기화
        // 슬라이드→스토리: 슬라이드 사진이 있고 스토리가 비어있을 때만 복사 (스토리 독립 편집 보존)
        if newTemplate == .slide, !storyModeRecipes.isEmpty {
            clipRecipes = storyModeRecipes
            slideModeRecipes = storyModeRecipes
            saveEntry()
        } else if newTemplate == .story, clipRecipes.isEmpty, !slideModeRecipes.isEmpty {
            clipRecipes = slideModeRecipes
            storyModeRecipes = slideModeRecipes
            saveEntry()
        }
    }
}
