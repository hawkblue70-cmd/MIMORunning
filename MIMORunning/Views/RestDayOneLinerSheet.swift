import SwiftUI
import SwiftData
import Combine
import Photos
import PhotosUI
import AVFoundation
import UIKit

// MARK: - RestDayTemplate

private enum RestDayTemplate: String, CaseIterable {
    case story = "스토리"
    case video = "영상"
    case slide = "슬라이드"
}

// MARK: - RestDayLoadGuard
// @StateObject: 뷰 생존 기간 동안 유지, re-render에 재설정 안 됨.
// @State보다 확실하게 loadEntry 1회 보장 (배칭 타이밍 이슈 없음).
private final class RestDayLoadGuard: ObservableObject {
    @Published var hasLoaded = false
}

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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    @Query private var allEntries: [OneLinerEntry]

    private var workoutID: String { OneLinerEntry.restDayWorkoutID(for: date) }

    private var gradientEntry: OneLinerEntry? {
        allEntries.first { $0.workoutID == workoutID && $0.mediaRef == nil }
    }
    private var photoEntries: [OneLinerEntry] {
        allEntries
            .filter { $0.workoutID == workoutID && $0.mediaRef?.hasPrefix("restphoto:") == true }
            .sorted { $0.createdAt < $1.createdAt }
    }
    private var videoTextEntry: OneLinerEntry? {
        allEntries.first { $0.workoutID == workoutID && $0.mediaRef == "videotexts" }
    }

    // MARK: State
    @State private var text:             String            = ""   // gradient-mode text
    @State private var fontChoice:       OneLinerFont      = .pen
    @State private var textColor:        OneLinerTextColor = .gold
    @State private var position:         CardPosition      = .bottom
    @State private var backgroundPhotos:   [UIImage]          = []
    @State private var photoPickerItems:   [PhotosPickerItem] = []
    @State private var selectedPhotoIndex: Int                = 0
    @State private var clipRecipes:           [ClipRecipe]       = []
    @State private var storyModeRecipes:      [ClipRecipe]       = []
    @State private var videoModeRecipes:      [ClipRecipe]       = []
    @State private var slideModeRecipes:      [ClipRecipe]       = []
    @State private var enabledMetricIDs:      Set<String>        = []
    @State private var savedClipLines:        [[String]]         = []
    @State private var currentClipIndex:      Int                = 0
    @State private var slotTexts:          [String]           = []
    @State private var orphanedTexts:      [String]           = []
    @State private var draggingPhotoIndex: Int?               = nil
    @State private var selectedTemplate:  RestDayTemplate     = .story
    @State private var isExportingVideo:  Bool                = false
    @State private var muteVideoAudio:    Bool                = false
    @State private var videoTitle:        String               = ""
    @State private var titleStyle:        OneLinerTitleStyle   = OneLinerTitleStyle()
    @State private var videoModeTitle:    String               = ""
    @State private var videoModeTitleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    @State private var slideModeTitle:    String               = ""
    @State private var slideModeTitleStyle: OneLinerTitleStyle = OneLinerTitleStyle()
    @StateObject private var loadGuard:  RestDayLoadGuard     = RestDayLoadGuard()
    @State private var previewPlayer:    OneLinerPreviewPlayer = OneLinerPreviewPlayer()
    @State private var exportError:     String?              = nil

    @FocusState private var fieldFocused: Bool

    // MARK: Computed
    private var isVideoMode: Bool { !clipRecipes.isEmpty }
    private var videoFirstFrame: UIImage? { clipRecipes.first?.thumbnail }
    private var videoTotalSeconds: Double { MultiClipComposition.totalDuration(recipes: clipRecipes) }
    private var videoClipCount: Int { clipRecipes.count }

    private var shareButtonActive: Bool {
        guard !isExportingVideo else { return false }
        switch selectedTemplate {
        case .video, .slide: return isVideoMode && videoTotalSeconds <= MultiClipComposition.maxSeconds
        case .story:         return true
        }
    }

    private var cardBackground: UIImage? {
        if selectedTemplate == .video || selectedTemplate == .slide || selectedTemplate == .story {
            let safeIdx = clipRecipes.indices.contains(currentClipIndex) ? currentClipIndex : 0
            return clipRecipes.indices.contains(safeIdx) ? clipRecipes[safeIdx].thumbnail : clipRecipes.first?.thumbnail
        }
        guard !backgroundPhotos.isEmpty else { return nil }
        return backgroundPhotos[min(selectedPhotoIndex, backgroundPhotos.count - 1)]
    }

    /// Text shown on the card preview.
    /// Story mode: joins all non-empty lines so both lines appear (matching export).
    /// Video/slide mode: shows first non-empty line only (video animation handles pagination).
    private var cardText: String {
        if selectedTemplate == .story {
            let safeIdx = clipRecipes.indices.contains(currentClipIndex) ? currentClipIndex : 0
            let clip = clipRecipes.indices.contains(safeIdx) ? clipRecipes[safeIdx] : clipRecipes.first
            return clip?.lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n") ?? ""
        }
        if selectedTemplate == .video || selectedTemplate == .slide {
            let safeIdx = clipRecipes.indices.contains(currentClipIndex) ? currentClipIndex : 0
            let clip = clipRecipes.indices.contains(safeIdx) ? clipRecipes[safeIdx] : clipRecipes.first
            return clip?.lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
        }
        if !backgroundPhotos.isEmpty, selectedPhotoIndex < slotTexts.count {
            return slotTexts[selectedPhotoIndex]
        }
        return ""
    }

    private var isClipMode: Bool { selectedTemplate == .video || selectedTemplate == .slide }
    private var isPhotoSlideMode: Bool { selectedTemplate == .slide || selectedTemplate == .story }

    // Per-clip preview style — used by OneLinerCard when in video/slide/story mode
    private var previewFont: OneLinerFont {
        if (isClipMode || selectedTemplate == .story), clipRecipes.indices.contains(currentClipIndex) {
            return clipRecipes[currentClipIndex].fontChoice
        }
        return fontChoice
    }
    private var previewTextColor: OneLinerTextColor {
        if (isClipMode || selectedTemplate == .story), clipRecipes.indices.contains(currentClipIndex) {
            return clipRecipes[currentClipIndex].textColor
        }
        return textColor
    }
    private var previewPosition: CardPosition {
        if (isClipMode || selectedTemplate == .story), clipRecipes.indices.contains(currentClipIndex) {
            return clipRecipes[currentClipIndex].position
        }
        return position
    }
    private var previewSizeLevel: TextSizeLevel {
        if (isClipMode || selectedTemplate == .story), clipRecipes.indices.contains(currentClipIndex) {
            return clipRecipes[currentClipIndex].sizeLevel
        }
        return .medium
    }
    private var previewAppearanceMode: AppearanceMode {
        if (isClipMode || selectedTemplate == .story), clipRecipes.indices.contains(currentClipIndex) {
            return clipRecipes[currentClipIndex].appearanceMode
        }
        return .typing
    }
    private var previewDecorEffect: DecorEffect {
        if (isClipMode || selectedTemplate == .story), clipRecipes.indices.contains(currentClipIndex) {
            return clipRecipes[currentClipIndex].decorEffect
        }
        return .none
    }
    private var previewHasBorder: Bool {
        guard (isClipMode || selectedTemplate == .story),
              clipRecipes.indices.contains(currentClipIndex) else { return false }
        return clipRecipes[currentClipIndex].hasBorder
    }
    private var previewPlateOn: Bool {
        guard (isClipMode || selectedTemplate == .story),
              clipRecipes.indices.contains(currentClipIndex) else { return false }
        return clipRecipes[currentClipIndex].plateOn
    }
    private var previewPlatePreset: PlateColorPreset {
        if (isClipMode || selectedTemplate == .story), clipRecipes.indices.contains(currentClipIndex) {
            return clipRecipes[currentClipIndex].plateColorPreset
        }
        return .blackWhite
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

    private var navStack: some View {
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
                    cardPreview.padding(.top, 16)
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
            OneLinerPreviewView(player: pl, contentLayer: cl, renderSize: previewPlayer.renderSize)
                .frame(width: CardPreviewFrame.width, height: CardPreviewFrame.height)
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
            // 영상/슬라이드 대기화면: OneLinerCard를 9:16(300×533)로 렌더 후 CardPreviewFrame 크기로 스케일
            //  → 라이브 프리뷰와 크기 일치 + 제목·문구·워드마크·날짜 모두 표시(제목 속성 편집 시 즉시 보임)
            OneLinerCard(
                displayDate: date,
                backgroundPhoto: cardBackground,
                text: cardText,
                position: previewPosition,
                textColor: previewTextColor,
                fontChoice: previewFont,
                sizeLevel: previewSizeLevel,
                appearanceMode: previewAppearanceMode,
                decorEffect: previewDecorEffect,
                hasBorder: previewHasBorder,
                plateOn: previewPlateOn,
                plateColorPreset: previewPlatePreset,
                showDate: true,
                captionMode: true,
                videoTitle: selectedTemplate != .story ? videoTitle : "",
                titleStyle: titleStyle,
                cardHeightOverride: 300.0 * 16.0 / 9.0
            )
            .scaleEffect(CardPreviewFrame.width / 300.0, anchor: .topLeading)
            .frame(width: CardPreviewFrame.width, height: CardPreviewFrame.height, alignment: .topLeading)
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
            .frame(maxWidth: .infinity)
        } else {
            OneLinerCard(
                displayDate: date,
                backgroundPhoto: cardBackground,
                text: cardText,
                position: previewPosition,
                textColor: previewTextColor,
                fontChoice: previewFont,
                sizeLevel: previewSizeLevel,
                appearanceMode: previewAppearanceMode,
                decorEffect: previewDecorEffect,
                hasBorder: previewHasBorder,
                plateOn: previewPlateOn,
                plateColorPreset: previewPlatePreset,
                showDate: true,
                captionMode: true,
                videoTitle: selectedTemplate != .story ? videoTitle : "",
                titleStyle: titleStyle
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
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var controlsArea: some View {
        VStack(spacing: 12) {
            templateTabs
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
                Text(AppLanguage.shared.s("공유하기", "Share")).fontWeight(.semibold)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(shareButtonActive ? Theme.violet : Theme.violet.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Single text field used in gradient (no-photo) mode.
    private var oneLinerTextField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(
                    AppLanguage.shared.s("오늘의 한마디", "Your one-liner"),
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(1...2)
                .focused($fieldFocused)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(Theme.violet)
                .onChange(of: text) { _, newVal in
                    let lines = newVal.components(separatedBy: "\n")
                    if lines.count > 2 {
                        text = String(lines.prefix(2).joined(separator: "\n").prefix(40)); return
                    }
                    if newVal.count > 40 { text = String(newVal.prefix(40)); return }
                    saveEntry()
                }
                Spacer(minLength: 0)
                Text("\(text.count)/40")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(hex: "6E6E78"))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(hex: "1E1E28"))
            .clipShape(RoundedRectangle(cornerRadius: 10))

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
    /// Shown in both photo mode (at the bottom of textSlotsView) and gradient mode.
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
        return HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 4) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(rows[row].indices, id: \.self) { col in
                            let pos = rows[row][col]
                            let isSelected = position == pos
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { position = pos }
                                saveEntry()
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
                HStack(spacing: 8) {
                    ForEach(OneLinerFont.allCases, id: \.self) { f in fontChip(f) }
                }
                HStack(spacing: 8) {
                    ForEach(OneLinerTextColor.allCases, id: \.self) { c in colorChip(c) }
                }
            }
        }
    }

    private func fontChip(_ font: OneLinerFont) -> some View {
        let isSelected = fontChoice == font
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { fontChoice = font }
            saveEntry()
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

    private func colorChip(_ tc: OneLinerTextColor) -> some View {
        let isSelected = textColor == tc
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { textColor = tc }
            saveEntry()
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
            availableMetrics: [],
            enabledMetricIDs: $enabledMetricIDs,
            onSave: handleRecipesChanged,
            isStoryMode: selectedTemplate == .story,
            videoTitle: $videoTitle,
            titleStyle: $titleStyle
        )
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
            if lines.count > 2 { v = String(lines.prefix(2).joined(separator: "\n").prefix(40)) }
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
        let f = DateFormatter()
        f.dateFormat = "M월 d일"; f.locale = Locale(identifier: "ko_KR")
        let e = DateFormatter()
        e.dateFormat = "MMM d";  e.locale = Locale(identifier: "en_US")
        return AppLanguage.shared.s(f.string(from: date), e.string(from: date))
             + " " + AppLanguage.shared.s("쉬는 날", "Rest Day")
    }

    private func loadEntry() {
        // 상태 초기화 — 다른 날짜로 시트가 재사용될 때 이전 날짜의 recipes가 남는 것 방지
        storyModeRecipes    = []
        videoModeRecipes    = []
        slideModeRecipes    = []
        clipRecipes         = []
        videoTitle          = ""
        titleStyle          = OneLinerTitleStyle()
        videoModeTitle      = ""
        videoModeTitleStyle = OneLinerTitleStyle()
        slideModeTitle      = ""
        slideModeTitleStyle = OneLinerTitleStyle()
        selectedTemplate    = .story
        currentClipIndex    = 0

        // Migrate legacy gradient entry for style only
        if let entry = gradientEntry {
            fontChoice = entry.font
            textColor  = entry.textColor
            position   = entry.position
            modelContext.delete(entry)
            try? modelContext.save()
        }

        guard let vEntry = videoTextEntry else { return }
        fontChoice = vEntry.font
        textColor  = vEntry.textColor
        position   = vEntry.position
        let raw = vEntry.text

        if raw.hasPrefix("v4recipes\n") {
            let jsonStr = String(raw.dropFirst("v4recipes\n".count))
            guard let data  = jsonStr.data(using: .utf8),
                  let store = try? JSONDecoder().decode(PerModeRecipeStore.self, from: data) else { return }
            storyModeRecipes = restoreRecipes(from: store.story)
            videoModeRecipes = restoreRecipes(from: store.video)
            slideModeRecipes = restoreRecipes(from: store.slide)
            if let videoSet = store.video {
                videoModeTitle      = videoSet.videoTitle
                videoModeTitleStyle = restoreTitleStyle(from: videoSet)
            }
            if let slideSet = store.slide {
                slideModeTitle      = slideSet.videoTitle
                slideModeTitleStyle = restoreTitleStyle(from: slideSet)
            }
            if let mode = RestDayTemplate(rawValue: store.activeMode) { selectedTemplate = mode }
            loadFromBackingStore(for: selectedTemplate)
            switch selectedTemplate {
            case .video: muteVideoAudio = store.video?.muteAudio ?? false
            case .slide: muteVideoAudio = store.slide?.muteAudio ?? false
            case .story: break
            }
        } else if raw.hasPrefix("v3recipes\n") {
            // Migration: single-mode save → slot into the right backing store
            let jsonStr = String(raw.dropFirst("v3recipes\n".count))
            guard let data  = jsonStr.data(using: .utf8),
                  let saved = try? JSONDecoder().decode(SavedRecipeSet.self, from: data),
                  !saved.clips.isEmpty else { return }
            muteVideoAudio = saved.muteAudio
            let restored = restoreRecipes(from: saved)
            let mode = saved.mode == "story" ? RestDayTemplate.story
                                             : (saved.isPhotoSlide ? .slide : .video)
            switch mode {
            case .story: storyModeRecipes = restored
            case .video: videoModeRecipes = restored
            case .slide: slideModeRecipes = restored
            }
            selectedTemplate = mode
            clipRecipes = restored
            currentClipIndex = 0
        } else if raw.hasPrefix("v2clips\n") {
            let section = String(raw.dropFirst("v2clips\n".count))
            savedClipLines = section
                .components(separatedBy: "\n---CLIP---\n")
                .map { $0.components(separatedBy: "\n") }
        } else {
            let linesArr = raw.components(separatedBy: "\n")
            if let first = linesArr.first, let count = Int(first), count > 0 {
                let texts = (0..<count).map { i in (i + 1) < linesArr.count ? linesArr[i + 1] : "" }
                savedClipLines = [texts]
            }
        }
    }

    private func applyStyle(to entry: OneLinerEntry) {
        entry.text      = text
        entry.font      = fontChoice
        entry.textColor = textColor
        entry.position  = position
        entry.showDate  = true
    }

    private func saveEntry() {
        syncActiveToBackingStore()

        let storySet = buildRecipeSet(from: storyModeRecipes, mode: "story")
        let videoSet = buildRecipeSet(from: videoModeRecipes, mode: nil,
                                      title: videoModeTitle, titleStyleParam: videoModeTitleStyle)
        let slideSet = buildRecipeSet(from: slideModeRecipes, mode: nil, isPhotoSlide: true,
                                      title: slideModeTitle, titleStyleParam: slideModeTitleStyle)

        if storySet != nil || videoSet != nil || slideSet != nil {
            let store = PerModeRecipeStore(
                story: storySet, video: videoSet, slide: slideSet,
                activeMode: selectedTemplate.rawValue)
            if let data = try? JSONEncoder().encode(store),
               let json = String(data: data, encoding: .utf8) {
                let payload = "v4recipes\n" + json
                if let existing = videoTextEntry {
                    existing.text = payload; existing.font = fontChoice
                    existing.textColor = textColor; existing.position = position
                    existing.showDate = true
                } else {
                    let entry = OneLinerEntry(workoutID: workoutID, mediaRef: "videotexts")
                    entry.text = payload; entry.font = fontChoice
                    entry.textColor = textColor; entry.position = position
                    entry.showDate = true
                    modelContext.insert(entry)
                }
            }
            try? modelContext.save()
            return
        }

        // No clips — videoTextEntry(v4recipes) 도 정리
        if let vEntry = videoTextEntry { modelContext.delete(vEntry) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = gradientEntry {
            if trimmed.isEmpty { modelContext.delete(existing) } else { applyStyle(to: existing) }
        } else if !trimmed.isEmpty {
            let entry = OneLinerEntry(workoutID: workoutID, mediaRef: nil)
            applyStyle(to: entry); modelContext.insert(entry)
        }
        try? modelContext.save()
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

    // MARK: - Clip state helpers

    private func clearClipState() {
        for recipe in storyModeRecipes + videoModeRecipes + slideModeRecipes {
            if let ref = recipe.thumbRef      { ClipThumbStore.delete(ref: ref) }
            if let ref = recipe.storedPhotoRef { OneLinerPhotoStore.delete(mediaRef: ref) }
            if let ref = recipe.clipVideoRef  { ClipVideoStore.delete(ref: ref) }
        }
        storyModeRecipes = []
        videoModeRecipes = []
        slideModeRecipes = []
        clipRecipes      = []
        muteVideoAudio   = false
        selectedTemplate = .story
        if let vEntry = videoTextEntry { modelContext.delete(vEntry); try? modelContext.save() }
    }

    private func markAsShared() {
        guard let vEntry = videoTextEntry else { return }
        if vEntry.text.hasPrefix("v4recipes\n") {
            let jsonStr = String(vEntry.text.dropFirst("v4recipes\n".count))
            guard let data  = jsonStr.data(using: .utf8),
                  var store = try? JSONDecoder().decode(PerModeRecipeStore.self, from: data) else { return }
            switch selectedTemplate {
            case .story: store.story?.isShared = true
            case .video: store.video?.isShared = true
            case .slide: store.slide?.isShared = true
            }
            if let newData = try? JSONEncoder().encode(store),
               let json    = String(data: newData, encoding: .utf8) {
                vEntry.text = "v4recipes\n" + json; try? modelContext.save()
            }
        } else if vEntry.text.hasPrefix("v3recipes\n") {
            let jsonStr = String(vEntry.text.dropFirst("v3recipes\n".count))
            guard let data  = jsonStr.data(using: .utf8),
                  var saved = try? JSONDecoder().decode(SavedRecipeSet.self, from: data) else { return }
            saved.isShared = true
            if let newData = try? JSONEncoder().encode(saved),
               let json    = String(data: newData, encoding: .utf8) {
                vEntry.text = "v3recipes\n" + json; try? modelContext.save()
            }
        }
    }

    private func switchTemplate(to newTemplate: RestDayTemplate) {
        guard newTemplate != selectedTemplate else { return }
        syncActiveToBackingStore()
        previewPlayer.pause()
        previewPlayer.invalidate()
        withAnimation(.easeInOut(duration: 0.15)) { selectedTemplate = newTemplate }
        loadFromBackingStore(for: newTemplate)
        // 영상/슬라이드로 전환 시 클립이 있으면 미리보기 자동 시작
        if (newTemplate == .video || newTemplate == .slide), !clipRecipes.isEmpty {
            buildPreview()
        }
    }

    private func syncActiveToBackingStore() {
        // 소스없음 클립(assetID·clipVideoRef·storedPhotoRef 모두 nil)은 배열에 영구 저장 금지
        let valid = clipRecipes.filter {
            $0.assetIdentifier != nil || $0.clipVideoRef != nil || $0.storedPhotoRef != nil
        }
        switch selectedTemplate {
        case .story:
            storyModeRecipes = valid
        case .video:
            videoModeRecipes = valid
            videoModeTitle = videoTitle
            videoModeTitleStyle = titleStyle
        case .slide:
            slideModeRecipes = valid
            slideModeTitle = videoTitle
            slideModeTitleStyle = titleStyle
        }
    }

    private func loadFromBackingStore(for template: RestDayTemplate) {
        switch template {
        case .story:
            clipRecipes = storyModeRecipes
            videoTitle  = ""
            titleStyle  = OneLinerTitleStyle()
        case .video:
            clipRecipes = videoModeRecipes
            videoTitle  = videoModeTitle
            titleStyle  = videoModeTitleStyle
        case .slide:
            clipRecipes = slideModeRecipes
            videoTitle  = slideModeTitle
            titleStyle  = slideModeTitleStyle
        }
        currentClipIndex = 0
        let srcs = clipRecipes.map { r -> String in
            if let id = r.assetIdentifier { return "assetID:\(id.prefix(8))" }
            if let ref = r.clipVideoRef   { return "clipVideoRef:\(ref.prefix(8))" }
            if let pr  = r.storedPhotoRef { return "photo:\(pr.prefix(8))" }
            return "소스없음"
        }
        print("[loadFromBackingStore] template=\(template) clips=\(clipRecipes.count) sources=\(srcs)")
    }

    private func buildRecipeSet(from recipes: [ClipRecipe], mode: String?,
                                isPhotoSlide: Bool = false,
                                title: String = "",
                                titleStyleParam: OneLinerTitleStyle = OneLinerTitleStyle()) -> SavedRecipeSet? {
        guard !recipes.isEmpty else { return nil }
        // 소스없음 클립은 저장 자체를 skip — 배열에 영구 기록 금지
        let validRecipes = recipes.filter {
            $0.assetIdentifier != nil || $0.clipVideoRef != nil || $0.storedPhotoRef != nil
        }
        guard !validRecipes.isEmpty else { return nil }
        let descs = validRecipes.map { r in
            SavedClipDescriptor(
                assetID: r.assetIdentifier, clipVideoRef: r.clipVideoRef,
                photoRef: r.storedPhotoRef,
                thumbRef: r.thumbRef, trimStart: r.trimStart,
                trimEnd: r.trimEnd, fullDuration: r.fullDuration,
                lines: r.lines,
                fontID: r.fontChoice.rawValue,
                colorID: r.textColor.rawValue,
                anchorIdx: CardPosition.allCases.firstIndex(of: r.position),
                sizeID: r.sizeLevel.rawValue,
                effectID: "\(r.appearanceMode.rawValue)|\(r.decorEffect.rawValue)|B\(r.hasBorder ? 1 : 0)P\(r.plateOn ? 1 : 0)|\(r.flyDirection.rawValue)",
                plateColorID: r.plateColorPreset.rawValue)
        }
        return SavedRecipeSet(
            isPhotoSlide: isPhotoSlide || (mode == "story"),
            muteAudio: mode == "story" ? false : muteVideoAudio,
            clips: descs, isShared: false, mode: mode,
            videoTitle: title,
            titleAnchorIdx: CardPosition.allCases.firstIndex(of: titleStyleParam.position),
            titleFontID: titleStyleParam.fontChoice.rawValue,
            titleColorID: titleStyleParam.textColor.rawValue,
            titleSizeID: titleStyleParam.sizeLevel.rawValue,
            titleOutline: titleStyleParam.outline)
    }

    private func restoreTitleStyle(from set: SavedRecipeSet) -> OneLinerTitleStyle {
        var style = OneLinerTitleStyle()
        if let idx = set.titleAnchorIdx, CardPosition.allCases.indices.contains(idx) {
            style.position = CardPosition.allCases[idx]
        }
        if let fid = set.titleFontID   { style.fontChoice = OneLinerFont.migrate(fid) }
        if let cid = set.titleColorID  { style.textColor  = OneLinerTextColor(rawValue: cid) ?? .white }
        if let sid = set.titleSizeID   { style.sizeLevel  = TextSizeLevel(rawValue: sid) ?? .medium }
        style.outline = set.titleOutline
        return style
    }

    private func restoreRecipes(from saved: SavedRecipeSet?) -> [ClipRecipe] {
        guard let saved, !saved.clips.isEmpty else { return [] }
        var restored: [ClipRecipe] = []
        for desc in saved.clips {
            let thumb: UIImage?
            if let pr = desc.photoRef { thumb = OneLinerPhotoStore.load(mediaRef: pr) }
            else if let tr = desc.thumbRef { thumb = ClipThumbStore.load(ref: tr) }
            else { thumb = nil }
            // 소스 결정: clipVideoRef(안정 복사본) → assetIdentifier(PHAsset 재해석) 순
            let recipeURL: URL
            if let ref = desc.clipVideoRef, let stableURL = ClipVideoStore.fileURL(ref: ref),
               FileManager.default.fileExists(atPath: stableURL.path) {
                // 앱 Documents 복사본 존재 → placeholder 없이 직접 사용
                recipeURL = stableURL
                print("[restoreRecipes] clip[\(restored.count)] clipVideoRef 안정 URL 사용")
            } else if desc.assetID != nil {
                // PHAsset localIdentifier 있음 → placeholder 생성 후 resolveVideoClips가 재취득
                recipeURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mimo_placeholder_\(UUID().uuidString)")
            } else {
                // 소스 없음 — 이 클립은 복구 불가. 저장 경로에서 필터되어야 함.
                recipeURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mimo_placeholder_\(UUID().uuidString)")
            }
            var recipe = ClipRecipe(url: recipeURL, fullDuration: desc.fullDuration,
                                   thumbnail: thumb)
            recipe.trimStart       = desc.trimStart
            recipe.trimEnd         = desc.trimEnd
            recipe.lines           = desc.lines
            recipe.assetIdentifier = desc.assetID
            recipe.clipVideoRef    = desc.clipVideoRef
            recipe.storedPhotoRef  = desc.photoRef
            recipe.thumbRef        = desc.thumbRef
            recipe.fontChoice = OneLinerFont.migrate(desc.fontID)
            recipe.textColor  = desc.colorID.flatMap { OneLinerTextColor(rawValue: $0) } ?? textColor
            if let idx = desc.anchorIdx, CardPosition.allCases.indices.contains(idx) {
                recipe.position = CardPosition.allCases[idx]
            } else {
                recipe.position = position
            }
            recipe.sizeLevel = desc.sizeID.flatMap { TextSizeLevel(rawValue: $0) } ?? .medium
            // effectID 형식: "appearanceMode|decorEffect|B{0|1}P{0|1}|flyDirection"
            // 레거시(구 comma-joined OneLinerEffect 포맷) 자동 마이그레이션: | 없으면 기본값 사용
            // parts[2] 마이그레이션: B접두사=신규, "0"/"1"/"none"/"outline"/"plate"=구 readabilityStyle
            if let eid = desc.effectID, eid.contains("|") {
                let parts = eid.split(separator: "|", maxSplits: 3).map(String.init)
                recipe.appearanceMode = parts.count > 0 ? (AppearanceMode(rawValue: parts[0]) ?? .typing) : .typing
                recipe.decorEffect    = parts.count > 1 ? (DecorEffect(rawValue: parts[1]) ?? .none) : .none
                if parts.count > 2 {
                    let r = parts[2]
                    if r.hasPrefix("B") {
                        // 신규 포맷: "B{0|1}P{0|1}"
                        recipe.hasBorder = r.contains("B1")
                        recipe.plateOn   = r.contains("P1")
                    } else {
                        // 레거시 마이그레이션: readabilityStyle enum rawValue
                        switch r {
                        case "1", "outline": recipe.hasBorder = true;  recipe.plateOn = false
                        case "plate":        recipe.hasBorder = false; recipe.plateOn = true
                        default:             recipe.hasBorder = false; recipe.plateOn = false
                        }
                    }
                }
                recipe.flyDirection = parts.count > 3 ? (FlyInDirection(rawValue: parts[3]) ?? .trailing) : .trailing
            } else {
                // 레거시 포맷: 기본값으로 초기화
                recipe.appearanceMode = .typing
                recipe.decorEffect    = .none
                recipe.hasBorder      = false
                recipe.plateOn        = false
            }
            recipe.plateColorPreset = desc.plateColorID.flatMap { PlateColorPreset(rawValue: $0) } ?? .blackWhite
            restored.append(recipe)
        }
        return restored
    }

    private func deletePhoto(at index: Int) {
        guard index < backgroundPhotos.count else { return }
        if index < photoEntries.count {
            let pe = photoEntries[index]
            OneLinerPhotoStore.delete(mediaRef: pe.mediaRef ?? "")
            modelContext.delete(pe)
            try? modelContext.save()
        }
        // Move this photo's text to orphaned (if non-empty)
        let removedText = index < slotTexts.count ? slotTexts[index] : ""
        backgroundPhotos.remove(at: index)
        if index < slotTexts.count { slotTexts.remove(at: index) }
        if !removedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            orphanedTexts.append(removedText)
        }
        if backgroundPhotos.isEmpty {
            photoPickerItems   = []
            selectedPhotoIndex = 0
        } else {
            selectedPhotoIndex = min(selectedPhotoIndex, backgroundPhotos.count - 1)
        }
    }

    @MainActor
    private func savePhotos(_ images: [UIImage]) {
        for pe in photoEntries {
            OneLinerPhotoStore.delete(mediaRef: pe.mediaRef ?? "")
            modelContext.delete(pe)
        }
        for (i, img) in images.enumerated() {
            guard let ref = OneLinerPhotoStore.save(img) else { continue }
            let entry = OneLinerEntry(workoutID: workoutID, mediaRef: ref)
            entry.text      = i < slotTexts.count ? slotTexts[i] : ""
            entry.font      = fontChoice
            entry.textColor = textColor
            entry.position  = position
            entry.showDate  = true
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }

    private func buildPreview() {
        guard !previewPlayer.isBuilding else { return }
        Task {
            if selectedTemplate == .video {
                // 영상 모드: PHAsset 재해석 후 AVPlayer 경로 (export와 동일 함수)
                var resolved = clipRecipes
                for i in resolved.indices {
                    guard resolved[i].resolvedAsset == nil,
                          !FileManager.default.fileExists(atPath: resolved[i].url.path),
                          let assetID = resolved[i].assetIdentifier else { continue }
                    do {
                        resolved[i].resolvedAsset = try await MultiClipComposition.resolveAVAsset(assetID: assetID)
                    } catch { }
                }
                await previewPlayer.buildForVideoClips(
                    recipes: resolved, activityDate: date, showDate: true,
                    muteAudio: muteVideoAudio, videoTitle: videoTitle, titleStyle: titleStyle)
            } else {
                // 슬라이드·스토리: 썸네일 기반 슬라이드 미리보기
                let photos = clipRecipes.compactMap { $0.thumbnail }
                guard !photos.isEmpty else { return }
                await previewPlayer.buildForPhotoSlides(
                    photos: photos, recipes: clipRecipes,
                    activityDate: date, showDate: true,
                    videoTitle: videoTitle, titleStyle: titleStyle)
            }
            previewPlayer.play()
        }
    }

    @MainActor
    private func renderCardForSharing() {
        // 스토리 템플릿: 클립 사진별 정지 카드 렌더링
        if selectedTemplate == .story, !clipRecipes.isEmpty {
            FontLoader.registerBundledFonts()
            var rendered: [UIImage] = []
            for recipe in clipRecipes {
                guard let photo = recipe.thumbnail else { continue }
                let txt = recipe.lines
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n")
                let card = OneLinerCard(
                    displayDate: date,
                    backgroundPhoto: photo,
                    text: txt,
                    position: recipe.position,
                    textColor: recipe.textColor,
                    fontChoice: recipe.fontChoice,
                    sizeLevel: recipe.sizeLevel,
                    appearanceMode: recipe.appearanceMode,
                    decorEffect: recipe.decorEffect,
                    hasBorder: recipe.hasBorder,
                    plateOn: recipe.plateOn,
                    plateColorPreset: recipe.plateColorPreset,
                    showDate: true,
                    captionMode: true
                )
                .frame(width: OneLinerCard.cardWidth, height: OneLinerCard.cardHeight)
                let renderer = ImageRenderer(content: card)
                renderer.scale = 3.0
                if let img = renderer.uiImage { rendered.append(img) }
            }
            if !rendered.isEmpty {
                markAsShared()
                presentShareSheet(images: rendered)
            }
            return
        }

        // 영상/슬라이드 템플릿: VideoExportService로 실제 .mov 출력
        if (selectedTemplate == .video || selectedTemplate == .slide), !clipRecipes.isEmpty {
            isExportingVideo = true
            Task {
                defer { isExportingVideo = false }
                do {
                    var recipes = clipRecipes

                    // Resolve recipe URLs that expired (temp files from previous session)
                    // Video clips: PHAsset → AVAsset 직접 해석 (AVComposition/슬로모션 포함)
                    var tempURLsToClean: [URL] = []
                    for i in recipes.indices {
                        guard !FileManager.default.fileExists(atPath: recipes[i].url.path) else { continue }
                        if let assetID = recipes[i].assetIdentifier {
                            recipes[i].resolvedAsset = try await MultiClipComposition.resolveAVAsset(assetID: assetID)
                        } else if let pr = recipes[i].storedPhotoRef,
                                  let img = OneLinerPhotoStore.load(mediaRef: pr) {
                            let tmpURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent("mimo_photoclip_\(UUID().uuidString).jpg")
                            if let d = img.jpegData(compressionQuality: 0.82) { try d.write(to: tmpURL) }
                            recipes[i].url = tmpURL
                            if recipes[i].thumbnail == nil { recipes[i].thumbnail = img }
                            tempURLsToClean.append(tmpURL)
                        } else {
                            // 해결 경로 없음: assetIdentifier도 없고 파일도 없음 → 영상 재선택 필요
                            throw ExportError.clipNotFound
                        }
                    }
                    defer { tempURLsToClean.forEach { try? FileManager.default.removeItem(at: $0) } }

                    if isPhotoSlideMode {
                        // Photo slide: single-pass CALayer composite (Ken Burns + text)
                        let photos = recipes.compactMap { $0.thumbnail }
                        guard !photos.isEmpty else { return }
                        let outputURL = try await PhotoSlideComposition.exportSlideWithText(
                            photos: photos, recipes: recipes,
                            fontChoice: fontChoice, textColor: textColor, position: position,
                            activityDate: date, showDate: true,
                            videoTitle: videoTitle, titleStyle: titleStyle)
                        markAsShared()
                        presentShareSheet(url: outputURL)
                    } else {
                        // Video clips: multi-clip compose or single-pass
                        let hasResolvedAssets = recipes.contains { $0.resolvedAsset != nil }
                        let needsCompose = recipes.count > 1 || recipes.contains { $0.isTrimmed } || hasResolvedAssets
                        let exportURL:  URL
                        var cleanupURL: URL? = nil
                        if needsCompose {
                            let (composed, _) = try await MultiClipComposition.composeAndExport(
                                recipes: recipes, muteAudio: muteVideoAudio)
                            exportURL  = composed
                            cleanupURL = composed
                        } else {
                            exportURL = recipes[0].url
                        }
                        defer { cleanupURL.map { try? FileManager.default.removeItem(at: $0) } }

                        let isMuted = muteVideoAudio
                        let outputURL = try await VideoExportService.exportOneLinerClipBoundVideo(
                            sourceURL: exportURL,
                            recipes: recipes,
                            fontChoice: fontChoice, textColor: textColor, position: position,
                            activityDate: date, showDate: true, muteAudio: isMuted,
                            videoTitle: videoTitle, titleStyle: titleStyle)
                        markAsShared()
                        presentShareSheet(url: outputURL)
                    }
                } catch ExportError.clipNotFound {
                    exportError = AppLanguage.shared.s(
                        "영상 파일을 찾을 수 없습니다. 영상을 삭제하고 다시 추가해주세요.",
                        "Video file not found. Please remove the clip and add it again.")
                } catch {
                    exportError = AppLanguage.shared.s(
                        "내보내기 중 오류가 발생했습니다: \(error.localizedDescription)",
                        "Export error: \(error.localizedDescription)")
                }
            }
            return
        }

        // 사진/그라데이션 템플릿: ImageRenderer로 정지 이미지 공유
        FontLoader.registerBundledFonts()
        let pairs: [(UIImage?, String)] = backgroundPhotos.count >= 2
            ? backgroundPhotos.enumerated().map { i, photo in
                  (photo, i < slotTexts.count ? slotTexts[i] : "")
              }
            : [(cardBackground, cardText)]

        var rendered: [UIImage] = []
        for (i, (photo, txt)) in pairs.enumerated() {
            // 인덱스별 recipe에서 음영판/테두리 설정을 가져와 반영 (없으면 현재 미리보기 값)
            let rp = i < clipRecipes.count ? clipRecipes[i] : nil
            let card = OneLinerCard(
                displayDate: date,
                backgroundPhoto: photo,
                text: txt,
                position: position,
                textColor: textColor,
                fontChoice: fontChoice,
                hasBorder: rp?.hasBorder ?? previewHasBorder,
                plateOn: rp?.plateOn ?? previewPlateOn,
                plateColorPreset: rp?.plateColorPreset ?? previewPlatePreset,
                showDate: true,
                captionMode: true
            )
            .frame(width: OneLinerCard.cardWidth, height: OneLinerCard.cardHeight)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 3.0
            if let img = renderer.uiImage { rendered.append(img) }
        }
        guard !rendered.isEmpty else { return }
        presentShareSheet(images: rendered)
    }

    /// Presents UIActivityViewController directly from the topmost VC.
    /// Avoids the SwiftUI .sheet + UIActivityViewController embedding hang.
    private func presentShareSheet(url: URL) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }

    private func presentShareSheet(images: [UIImage]) {
        let vc = UIActivityViewController(activityItems: images, applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        vc.popoverPresentationController?.sourceView = top.view  // required on iPad
        top.present(vc, animated: true)
    }
}

// MARK: - ExportError

private enum ExportError: Error {
    case clipNotFound   // 임시 파일 삭제됨 + assetIdentifier/storedPhotoRef 없음
}

// MARK: - PerModeRecipeStore

struct PerModeRecipeStore: Codable {
    var story:      SavedRecipeSet?
    var video:      SavedRecipeSet?
    var slide:      SavedRecipeSet?
    var activeMode: String   // RestDayTemplate.rawValue: "스토리" | "영상" | "슬라이드"
}

