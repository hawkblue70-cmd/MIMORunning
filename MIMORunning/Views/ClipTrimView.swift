import SwiftUI
import AVFoundation
import PhotosUI

// MARK: - ClipTrimSheet
//
// Multi-clip edit sheet with swipeable preview carousel (TabView/page).
// All clips are copied locally on open; edits to workingRecipes are committed
// to the binding only on "완료". "취소" discards all changes.
// Swiping between clips auto-saves within the local session (no explicit commit step).

struct ClipTrimSheet: View {
    @Binding var recipes: [ClipRecipe]
    @Binding var selectedClipIndex: Int
    var hideTimePicker: Bool = false
    var isStoryMode:    Bool = false

    @Environment(\.dismiss) private var dismiss

    // Local working copies — written back to recipes binding only on "완료"
    @State private var workingRecipes: [ClipRecipe] = []
    @State private var currentPage:    Int          = 0

    // Single-clip replacement pickers
    @State private var replacePhotoPicker: [PhotosPickerItem] = []
    @State private var replaceVideoPicker: [PhotosPickerItem] = []

    // MARK: - Current-page accessors

    private var currentRecipeValid: Bool {
        workingRecipes.indices.contains(currentPage)
    }

    private var isPhotoClip: Bool {
        currentRecipeValid && workingRecipes[currentPage].storedPhotoRef != nil
    }

    private var charLimit: Int { 20 }

    private var projectedCount: Int {
        guard currentRecipeValid else { return 0 }
        return projectedCountFor(workingRecipes[currentPage])
    }

    private func projectedCountFor(_ recipe: ClipRecipe) -> Int {
        if recipe.storedPhotoRef != nil {
            return (hideTimePicker || recipe.fullDuration >= 4.0) ? 2 : 1
        }
        return max(1, min(20, Int(max(0.1, recipe.trimEnd - recipe.trimStart) / 3.0)))
    }

    private var droppedWarning: String? {
        guard currentRecipeValid else { return nil }
        let r = workingRecipes[currentPage]
        if isPhotoClip {
            guard !hideTimePicker, r.fullDuration < 4.0 else { return nil }
            let slot2 = r.lines.count > 1 ? r.lines[1] : ""
            guard !slot2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return AppLanguage.shared.s(
                "3초에서는 두 번째 줄이 표시되지 않아요",
                "Second line won't appear at 3 s")
        }
        guard projectedCount < r.lines.count else { return nil }
        let wouldDrop = r.lines[projectedCount...]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !wouldDrop.isEmpty else { return nil }
        return AppLanguage.shared.s(
            "\(projectedCount + 1)번째 줄부터 표시되지 않아요",
            "Lines from \(projectedCount + 1) won't appear")
    }

    private func textAlignmentFor(_ recipe: ClipRecipe) -> TextAlignment {
        switch recipe.position {
        case .topTrailing, .trailing, .bottomTrailing: return .trailing
        case .topLeading,  .leading,  .bottomLeading:  return .leading
        default: return .center
        }
    }

    private func lineCount(at i: Int) -> Int {
        guard currentRecipeValid, i < workingRecipes[currentPage].lines.count else { return 0 }
        return workingRecipes[currentPage].lines[i].count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // ── Preview carousel ──────────────────────────
                    previewCarousel

                    // ── 점 + 재생시간 칩: 간격 좁게 ─────────────
                    VStack(spacing: 6) {
                        if workingRecipes.count > 1 { pageIndicator }
                        if isPhotoClip, !hideTimePicker { photoDurationPicker }
                        if !isPhotoClip, currentRecipeValid { trimSection }
                    }

                    Divider().padding(.horizontal)

                    // ── Text inputs ───────────────────────────────
                    if currentRecipeValid { textInputSection }

                    Divider().padding(.horizontal)

                    // ── Style controls ────────────────────────────
                    styleSection

                    Spacer(minLength: 16)
                }
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Color(hex: "0E0E18").ignoresSafeArea())
            .navigationTitle(AppLanguage.shared.s("클립 편집", "Edit Clip"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.shared.s("취소", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLanguage.shared.s("완료", "Done")) {
                        recipes = workingRecipes
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .onAppear {
            workingRecipes = recipes
            currentPage    = max(0, min(selectedClipIndex, recipes.count - 1))
            FontLoader.registerBundledFonts()
        }
        .onChange(of: currentPage) { _, new in
            selectedClipIndex = new
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
        return TabView(selection: $currentPage) {
            ForEach(workingRecipes.indices, id: \.self) { i in
                clipPreviewPage(i)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: carouselH)
    }

    @ViewBuilder
    private func clipPreviewPage(_ i: Int) -> some View {
        let recipe = workingRecipes[i]
        if isStoryMode {
            let txt = recipe.lines
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
            OneLinerCard(
                displayDate: Date(),
                backgroundPhoto: recipe.thumbnail,
                text: txt,
                position: recipe.position,
                textColor: recipe.textColor,
                fontChoice: recipe.fontChoice,
                sizeLevel: recipe.sizeLevel,
                appearanceMode: recipe.appearanceMode,
                decorEffect: recipe.decorEffect,
                outline: recipe.outline,
                showDate: true,
                captionMode: true
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]),
                                  antialiased: false)
                    .foregroundStyle(.white.opacity(0.22))
                    .padding(14)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .frame(maxWidth: .infinity)
        } else {
            let maxH: CGFloat  = CardPreviewFrame.height
            let w: CGFloat     = CardPreviewFrame.width
            let count          = projectedCountFor(recipe)
            let displayText    = (0..<count)
                .map { j in j < recipe.lines.count ? recipe.lines[j] : "" }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            let align          = textAlignmentFor(recipe)
            ZStack {
                if let thumb = recipe.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: maxH)
                        .clipped()
                        .contentShape(Rectangle())
                } else {
                    Color(hex: "1A1A24")
                        .overlay(
                            Image(systemName: recipe.storedPhotoRef != nil ? "photo" : "video")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                        )
                }
                if !displayText.isEmpty {
                    // previewScale = w/300: 비디오 vScale(1080/300)과 동일 기준으로 비율 맞춤
                    let previewScale: CGFloat = w / 300.0
                    let scale1080:    CGFloat = w / 1080.0  // 1080px → preview pt 변환
                    let base: CGFloat = 20 * recipe.fontChoice.sizeScale * recipe.sizeLevel.scale * previewScale
                    // export UIKit 세이프존과 동일 기준: safeTop=260px(+4), safeBot=270px @1080px
                    let topPad:    CGFloat = recipe.position.isTop    ? (CardVisual.videoSafeTop + 4) * scale1080 : 0
                    let bottomPad: CGFloat = recipe.position.isBottom ? CardVisual.videoSafeBottom   * scale1080 : 0
                    EffectTextView(
                        text:           displayText,
                        font:           recipe.fontChoice.swiftUIFont(size: base),
                        lineSpacing:    base * 0.1,
                        alignment:      align,
                        color:          recipe.textColor.color,
                        appearanceMode: recipe.appearanceMode,
                        decorEffect:    recipe.decorEffect,
                        outline:        recipe.outline
                    )
                    .padding(.horizontal, 24 * previewScale)
                    .padding(.top, topPad)
                    .padding(.bottom, bottomPad)
                    .frame(width: w, height: maxH, alignment: recipe.position.alignment)
                }
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]),
                                  antialiased: false)
                    .foregroundStyle(.white.opacity(0.22))
                    .padding(14)
                    .allowsHitTesting(false)
            }
            .frame(width: w, height: maxH)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(workingRecipes.indices, id: \.self) { i in
                Circle()
                    .fill(i == currentPage ? Color.white : Color.white.opacity(0.30))
                    .frame(width: i == currentPage ? 7 : 5,
                           height: i == currentPage ? 7 : 5)
                    .animation(.easeInOut(duration: 0.15), value: currentPage)
            }
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
                             maxSelectionCount: 1, matching: .videos) {
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
                trimEnd:   $workingRecipes[currentPage].trimEnd
            )
            .padding(.horizontal)

            if let warning = droppedWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Text inputs

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<projectedCount, id: \.self) { i in
                HStack(spacing: 8) {
                    TextField(
                        AppLanguage.shared.s("\(i + 1)번째 줄", "Line \(i + 1)"),
                        text: lineBinding(for: i)
                    )
                    .lineLimit(1)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .tint(Theme.violet)

                    Spacer(minLength: 0)
                    Text("\(lineCount(at: i))/\(charLimit)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Color(hex: "6E6E78"))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(hex: "1E1E28"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Style section (reads/writes workingRecipes[currentPage])

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLanguage.shared.s("스타일", "Style"))
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)

            HStack(alignment: .top, spacing: 12) {
                // 왼쪽: 위치 그리드
                positionGrid
                // 오른쪽: 크기 → 글꼴 → 색상 → 등장 방식 → 꾸밈/외곽선
                VStack(alignment: .leading, spacing: 5) {
                    sizeChips
                    fontChips
                    colorCircles
                    appearanceChips
                    if currentRecipeValid && workingRecipes[currentPage].appearanceMode == .fade {
                        HStack(spacing: 6) {
                            decorChips
                            outlineChip
                        }
                    } else {
                        outlineChip
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var positionGrid: some View {
        let rows: [[CardPosition]] = [
            [.topLeading,    .top,    .topTrailing],
            [.leading,       .center, .trailing],
            [.bottomLeading, .bottom, .bottomTrailing]
        ]
        return VStack(spacing: 4) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(rows[row].indices, id: \.self) { col in
                        let pos   = rows[row][col]
                        let isSel = currentRecipeValid && workingRecipes[currentPage].position == pos
                        Button {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                if currentRecipeValid { workingRecipes[currentPage].position = pos }
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isSel ? Theme.violet : Color(hex: "26262E"))
                                .frame(width: 23, height: 23)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var sizeChips: some View {
        HStack(spacing: 6) {
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
        }
    }

    private var fontChips: some View {
        HStack(spacing: 6) {
            ForEach(OneLinerFont.allCases, id: \.self) { f in
                let isSel = currentRecipeValid && workingRecipes[currentPage].fontChoice == f
                Button { if currentRecipeValid { workingRecipes[currentPage].fontChoice = f } } label: {
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

    // 등장 방식: 타이핑 / 페이드 (택1)
    private var appearanceChips: some View {
        HStack(spacing: 6) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                let isSel = currentRecipeValid && workingRecipes[currentPage].appearanceMode == mode
                Button {
                    guard currentRecipeValid else { return }
                    workingRecipes[currentPage].appearanceMode = mode
                    // 타이핑으로 전환 시 꾸밈 초기화
                    if mode == .typing { workingRecipes[currentPage].decorEffect = .none }
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

    // 외곽선: 독립 토글 (타이핑·페이드 양쪽 유효)
    private var outlineChip: some View {
        let isSel = currentRecipeValid && workingRecipes[currentPage].outline
        return Button {
            guard currentRecipeValid else { return }
            workingRecipes[currentPage].outline.toggle()
        } label: {
            Text(AppLanguage.shared.s("외곽선", "Outline"))
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
            let url    = result.url
            let newDur = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            guard newDur > 0 else { return }
            let thumb  = await VideoExportService.firstFrame(of: url)
            await MainActor.run {
                guard workingRecipes.indices.contains(currentPage) else { return }
                if let old = workingRecipes[currentPage].thumbRef { ClipThumbStore.delete(ref: old) }
                workingRecipes[currentPage].url             = url
                workingRecipes[currentPage].thumbnail       = thumb
                workingRecipes[currentPage].thumbRef        = thumb.flatMap { ClipThumbStore.save($0) }
                workingRecipes[currentPage].assetIdentifier = item.itemIdentifier
                workingRecipes[currentPage].fullDuration    = newDur
                workingRecipes[currentPage].trimStart       = 0
                workingRecipes[currentPage].trimEnd         = newDur
                // Adjust lines array to new clip length
                let newCount = max(1, min(20, Int(newDur / 3.0)))
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

    @ViewBuilder
    private var photoDurationPicker: some View {
        if currentRecipeValid {
            let dur = workingRecipes[currentPage].fullDuration
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
            .padding(.horizontal)

            if let warning = droppedWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal)
            }
        }
    }

}

// MARK: - TrimBarView
//
// Orange-highlighted range bar between two draggable handles.
// Handles move independently; minimum trim = 0.5 s.

struct TrimBarView: View {
    let duration: Double
    @Binding var trimStart: Double
    @Binding var trimEnd:   Double

    private let barHeight: CGFloat = 48
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
                    )

                // End handle
                handle(symbol: "chevron.right")
                    .offset(x: endX - handleW)
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { v in
                            let raw = Double((v.location.x - handleW) / usable) * duration
                            trimEnd = min(duration, max(raw, trimStart + minTrim))
                        }
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
