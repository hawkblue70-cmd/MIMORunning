import SwiftUI
import AVFoundation
import AVKit
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
    /// Full-video title shown in non-story clip previews (scaled to previewScale).
    var videoTitle:     String              = ""
    var titleStyle:     OneLinerTitleStyle  = OneLinerTitleStyle()

    @Environment(\.dismiss) private var dismiss

    // Local working copies — written back to recipes binding only on "완료"
    @State private var workingRecipes: [ClipRecipe] = []
    @State private var currentPage:    Int          = 0

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

    private var charLimit: Int { 20 }

    private var projectedCount: Int {
        guard currentRecipeValid else { return 0 }
        return projectedCountFor(workingRecipes[currentPage])
    }

    private func projectedCountFor(_ recipe: ClipRecipe) -> Int {
        if recipe.storedPhotoRef != nil || isStoryMode {
            return (hideTimePicker || isStoryMode || recipe.fullDuration >= 4.0) ? 2 : 1
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
                // 배경 탭 시 키보드 해제 — UIKit TapGestureRecognizer를 background UIView에 직접 설치.
                // SwiftUI simultaneousGesture는 편집 메뉴(붙여넣기 등) 탭도 가로채므로 사용 금지.
                // background UIView는 TextField 계층의 조상이 아니므로, TextField/메뉴 탭 시에는
                // UIKit hit-test 체인에서 제외되어 제스처가 발동하지 않음.
                .background(KeyboardDismissBackground())
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(hex: "0E0E18").ignoresSafeArea())
            .navigationTitle(AppLanguage.shared.s("클립 편집", "Edit Clip"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.shared.s("취소", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLanguage.shared.s("완료", "Done")) {
                        // Preserve resolvedAsset that may have been set by async resolveVideoClips
                        // while this sheet was open (binding was updated but workingRecipes was not).
                        var toSave = workingRecipes
                        for i in toSave.indices where i < recipes.count {
                            if toSave[i].resolvedAsset == nil, let resolved = recipes[i].resolvedAsset {
                                toSave[i].resolvedAsset = resolved
                            }
                        }
                        recipes = toSave
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
            for i in workingRecipes.indices {
                resolveClipInSheet(i)
                resolvePreviewFrame(i)  // PHAsset 포스터 프레임 → 해석 전 배경 즉시 표시
            }
        }
        .onChange(of: currentPage) { _, new in
            selectedClipIndex = new
            resolveClipInSheet(new)
            resolvePreviewFrame(new)
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
        let _ = sheetPreviewVersion  // @State 의존성 강제 등록 → version 변경 시 반드시 re-render
        let recipe = workingRecipes[i]
        if isStoryMode {
            let txt = recipe.lines
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
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
                hasBorder: recipe.hasBorder,
                plateOn: recipe.plateOn,
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
                // 영상/사진 배경 — 3상태: 표시가능(frames) / 실패(notFound) / 로딩중
                let assetID = recipe.assetIdentifier
                let isFailed = assetID.map { failedClipIDs.contains($0) } ?? false
                if let frame = sheetPreviewFrames[i] {
                    // ① 정지 프레임 확보됨 → 최우선 표시
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: maxH)
                        .clipped()
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
                    // ③ 해석 중 + 썸네일 있음 → 썸네일 + 스피너
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: maxH)
                        .clipped()
                        .overlay(ProgressView().tint(.white).scaleEffect(1.4))
                } else {
                    // ③ 해석 중 + 썸네일 없음 → 어두운 배경 + 스피너
                    Color(hex: "1A1A24")
                        .frame(width: w, height: maxH)
                        .overlay(ProgressView().tint(.white).scaleEffect(1.4))
                }
                if !displayText.isEmpty {
                    // previewScale = w/300: 비디오 vScale(1080/300)과 동일 기준으로 비율 맞춤
                    let previewScale: CGFloat = w / 300.0
                    let scale1080:    CGFloat = w / 1080.0  // 1080px → preview pt 변환
                    let base: CGFloat = OneLinerFont.basePt * recipe.fontChoice.sizeScale * recipe.sizeLevel.scale * previewScale
                    // export UIKit 세이프존과 동일 기준: safeTop=260px(+4), safeBot=270px @1080px
                    let topPad:    CGFloat = recipe.position.isTop    ? (CardVisual.videoSafeTop + 4) * scale1080 : 0
                    let bottomPad: CGFloat = recipe.position.isBottom ? CardVisual.videoSafeBottom   * scale1080 : 0
                    EffectTextView(
                        text:           displayText,
                        font:           recipe.fontChoice.boldSwiftUIFont(size: base),
                        lineSpacing:    base * 0.1,
                        alignment:      align,
                        color:          recipe.plateOn
                                            ? recipe.plateColorPreset.textSwiftColor
                                            : recipe.textColor.color,
                        appearanceMode:   recipe.appearanceMode,
                        decorEffect:      recipe.decorEffect,
                        hasBorder:        recipe.hasBorder,
                        plateOn:          recipe.plateOn,
                        flyDirection:     recipe.flyDirection,
                        plateBgColor:     recipe.plateColorPreset.plateBgColor,
                        syntheticBoldStroke: recipe.fontChoice.syntheticBoldStroke(for: base),
                        borderColor:  recipe.hasBorder ? recipe.textColor.borderSwiftColor : .clear,
                        borderOffset: recipe.hasBorder ? max(0.8, base * recipe.textColor.borderOffsetFactor) : 0
                    )
                    .padding(.horizontal, 24 * previewScale)
                    .padding(.top, topPad)
                    .padding(.bottom, bottomPad)
                    .frame(width: w, height: maxH, alignment: recipe.position.alignment)
                }
                // Full-video title overlay — same scale basis (w/300, w/1080) as clip text.
                if !videoTitle.isEmpty {
                    let tPS:       CGFloat  = w / 300.0
                    let tS1080:    CGFloat  = w / 1080.0
                    let tFontSize           = OneLinerFont.basePt * titleStyle.fontChoice.sizeScale * titleStyle.sizeLevel.scale * tPS
                    let tTopPad:   CGFloat  = titleStyle.position.isTop    ? (CardVisual.videoSafeTop + 4) * tS1080 : 0
                    let tBotPad:   CGFloat  = titleStyle.position.isBottom ? CardVisual.videoSafeBottom * tS1080 : 0
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
                    .padding(.horizontal, 10 * tPS)
                    .padding(.top, tTopPad)
                    .padding(.bottom, tBotPad)
                    .frame(width: w, height: maxH, alignment: titleStyle.position.alignment)
                    .allowsHitTesting(false)
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
                // 오른쪽: 크기 → 글꼴 → 색상 → 등장 방식 → 꾸밈/방향 → 가독성
                VStack(alignment: .leading, spacing: 5) {
                    sizeChips
                    fontChips
                    if currentRecipeValid && workingRecipes[currentPage].plateOn {
                        platePresetSwatches
                    } else {
                        colorCircles
                    }
                    // 스토리 = 정지 사진이므로 동적 속성(등장방식·꾸밈·방향) 숨김
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
                    readabilityChips
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
                Button {
                    guard currentRecipeValid else { return }
                    workingRecipes[currentPage].fontChoice = f
                    // 나눔펜 선택 시 테두리 OFF + 음영판 ON (펜=음영판 전용)
                    if f == .pen {
                        workingRecipes[currentPage].hasBorder = false
                        workingRecipes[currentPage].plateOn   = true
                    }
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

    // 가독성: 테두리·음영판 독립 토글 — 폰트 자동 전환 없음 (크기 계산과 완전 독립)
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

            // 음영판 토글
            let plateOn = currentRecipeValid && workingRecipes[currentPage].plateOn
            Button {
                guard currentRecipeValid else { return }
                workingRecipes[currentPage].plateOn.toggle()
                #if DEBUG
                sizeAuditLog("음영판 토글")
                #endif
            } label: {
                Text(AppLanguage.shared.s("음영판", "Plate"))
                    .font(.system(size: 12, weight: plateOn ? .semibold : .regular))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(plateOn ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08))
                    .foregroundStyle(plateOn ? Theme.violet : Color.white.opacity(0.55))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(
                        plateOn ? Theme.violet.opacity(0.55) : Color.clear, lineWidth: 1))
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

    // 음영판 프리셋: 판색(바깥 링) + 글자색(안 점) 쌍 선택 — plate 모드에서만 표시
    private var platePresetSwatches: some View {
        HStack(spacing: 8) {
            ForEach(PlateColorPreset.allCases, id: \.self) { preset in
                let isSel = currentRecipeValid && workingRecipes[currentPage].plateColorPreset == preset
                Button {
                    if currentRecipeValid { workingRecipes[currentPage].plateColorPreset = preset }
                } label: {
                    ZStack {
                        // 바깥 링: 판 색상
                        Circle()
                            .fill(preset.plateSwiftColor.opacity(preset.plateOpacity))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(
                                preset == .whiteBlack ? Color.gray.opacity(0.5) : Color.clear,
                                lineWidth: 1))
                        // 안 점: 글자 색상
                        Circle()
                            .fill(preset.textSwiftColor)
                            .frame(width: 8, height: 8)
                        // 선택 링
                        if isSel {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                                .frame(width: 28, height: 28)
                        }
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Replace media button

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
        print("[SizeAudit] \(label): \(r.fontChoice.rawValue)/\(r.sizeLevel.rawValue) border=\(r.hasBorder) plate=\(r.plateOn) → \(String(format: "%.2f", base))pt capH=\(String(format: "%.1f", capHpx))px@3x")
    }
    #endif

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
                if view is UITextField || view is UITextView { return false }
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
