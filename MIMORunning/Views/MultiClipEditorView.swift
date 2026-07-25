import SwiftUI
import Photos
import PhotosUI
import AVFoundation
import UIKit
import CoreLocation

// MARK: - MetricItem
// A metric that can be toggled as a chip in MultiClipEditorView and overlaid on video.

struct MetricItem: Identifiable {
    let id:      String
    let value:   String   // e.g. "10.2"
    let label:   String   // e.g. "km"
    let color:   Color
    let uiColor: UIColor
}

// MARK: - VideoMetricChip
// UIKit-only metric descriptor for video export overlay (no SwiftUI Color).

struct VideoMetricChip {
    let value:   String
    let label:   String
    let uiColor: UIColor
}

extension MetricItem {
    var asVideoChip: VideoMetricChip {
        VideoMetricChip(value: value, label: label, uiColor: uiColor)
    }
}

// MARK: - MultiClipEditorView
//
// Shared video/photo-slide clip editor used by both RestDayOneLinerSheet (no metrics)
// and ShareCardView OneLiner (metrics injected from activity).
//
// The parent owns [ClipRecipe], isPhotoSlideMode, muteAudio state and handles all
// persistence. This view manages picker presentation, clip strip UI, drag reorder,
// metric chip toggles, and ClipTrimSheet.

struct MultiClipEditorView: View {
    @Binding var recipes:           [ClipRecipe]
    @Binding var isPhotoSlideMode:  Bool
    @Binding var muteAudio:         Bool
    /// Which clip's style the controls below are editing.
    @Binding var selectedClipIndex: Int

    /// Line texts restored from DB — applied to freshly picked clips.
    let savedClipLines: [[String]]

    /// Available metric chips. Empty = rest-day (row hidden).
    let availableMetrics: [MetricItem]
    @Binding var enabledMetricIDs: Set<String>

    /// 경로 좌표 (M 미니맵). 빈 배열 = 없음(쉬는날).
    var routeCoords: [CLLocationCoordinate2D] = []
    /// 심박 샘플 (H 차트). 빈 배열 = 없음.
    var hrSamples: [(offset: TimeInterval, bpm: Int)] = []
    /// 스플릿 데이터 (S 차트). 빈 배열 = 없음.
    var splits: [SplitData] = []
    /// 기타 시계열 차트 데이터 (케이던스·지면접촉·보폭·수직진폭·고도·파워).
    var chartSeriesData: [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:]
    var hrZones: [HRZoneData] = []
    var intervalSegments: [IntervalSegment] = []

    /// Called after any change so the parent can persist.
    let onSave: () -> Void

    /// When true: photo-slide editor in story mode — hides duration row and mute button.
    var isStoryMode: Bool = false
    /// When false: hides the picker button row (parent handles photo selection itself).
    var showPickerButton: Bool = true
    /// When true: shows title section even when recipes is empty (slide mode — photos live in parent).
    var showTitleEvenWhenEmpty: Bool = false
    /// When false: hides the '전체 제목' section (e.g. Placeable — per-clip text only, no global title).
    var showTitle: Bool = true
    /// When false: tapping a clip only selects it (updates selectedClipIndex) without opening the edit sheet.
    /// Used in Placeable video where trim/text controls are inline below the strip.
    var openEditOnTap: Bool = true
    /// When false: hides the "(탭하면 상세 편집)" hint in the duration row.
    var showEditHint: Bool = true

    /// Full-video title (영상·슬라이드 only; hidden when isStoryMode).
    @Binding var videoTitle: String
    @Binding var titleStyle: OneLinerTitleStyle

    // Internal picker state
    @State private var videoPickerItems:      [PhotosPickerItem] = []
    @State private var photoSlidePickerItems: [PhotosPickerItem] = []
    @State private var showPhotoSlidePicker:  Bool               = false
    @State private var isEditing:             Bool = false
    @State private var draggingClipIndex:     Int? = nil

    // 영상 클립 PHAsset 비동기 해석 상태 (만료된 임시 URL 대체)
    @State private var resolvingIDs:    Set<String> = []
    @State private var failedIDs:       Set<String> = []
    @State private var showReAddAlert:  Bool = false

    private var totalSeconds: Double { MultiClipComposition.totalDuration(recipes: recipes) }
    private var safeClipIdx: Int {
        recipes.isEmpty ? 0 : min(max(0, selectedClipIndex), recipes.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pickerButtonRow
            if !recipes.isEmpty { clipStrip }
            if !recipes.isEmpty, isStoryMode  { storyHintRow }
            if !recipes.isEmpty, !isStoryMode { durationRow }
            // 영상·슬라이드 메인은 '전체 제목'만 — 지표(P/D/T/M/H)는 클립별(클립 편집기)에서
            // showTitleEvenWhenEmpty: 슬라이드 모드에서 photos가 storyPhotos에 있고 recipes는 비어있을 때
            if showTitle && !isStoryMode && (!recipes.isEmpty || showTitleEvenWhenEmpty) { titleSection }
        }
        // onDismiss: cleanup 전용(failedIDs, resolveVideoClips).
        // 저장은 ClipTrimSheet.onCommit → "완료" 직후 동기 실행으로 보장.
        .sheet(isPresented: $isEditing, onDismiss: {
            // ClipTrimSheet.Done이 workingRecipes를 쓰면서 resolvedAsset을 덮어쓸 수 있음.
            // 이전 실패 기록을 지워 재해석을 허용한다 (export가 성공 = 원본 존재).
            failedIDs.removeAll()
            resolveVideoClips()
        }) { clipTrimSheet }
        .onChange(of: videoPickerItems)      { _, items in loadVideoClips(items) }
        .onChange(of: photoSlidePickerItems) { _, items in loadPhotoSlides(items) }
        .alert(AppLanguage.shared.s("영상을 다시 추가해 주세요", "Re-add This Video"),
               isPresented: $showReAddAlert) {
            Button(AppLanguage.shared.s("확인", "OK"), role: .cancel) { }
        } message: {
            Text(AppLanguage.shared.s(
                "이 영상은 저장된 참조를 잃어 재생·export가 불가합니다.\n삭제 후 사진 보관함에서 다시 추가해 주세요.",
                "This video's reference was lost and can't be played or exported.\nPlease delete it and re-add from your photo library."))
        }
        .onAppear { resolveVideoClips() }
        .onChange(of: recipes.map { $0.assetIdentifier }) { _, _ in resolveVideoClips() }
    }

    @ViewBuilder
    private var clipTrimSheet: some View {
        ClipTrimSheet(
            recipes: $recipes,
            selectedClipIndex: $selectedClipIndex,
            hideTimePicker: isStoryMode,
            isStoryMode: isStoryMode,
            isPhotoSlideMode: isPhotoSlideMode,
            availableMetrics: availableMetrics,
            routeCoords: routeCoords,
            hrSamples: hrSamples,
            splits: splits,
            chartSeriesData: chartSeriesData,
            hrZones: hrZones,
            intervalSegments: intervalSegments,
            videoTitle: isStoryMode ? "" : videoTitle,
            titleStyle: titleStyle,
            onCommit: { newRecipes in
                // newRecipes = commitWorkingRecipes()가 방금 쓴 toSave.
                // @State 배치 처리 전에 binding을 직접 갱신하여 saveEntry가 최신 값을 읽도록 보장.
                recipes = newRecipes
                onSave()
            }
        )
    }

    // MARK: - Picker button row
    // 비어있을 때: 사진 아이콘 + 텍스트 버튼 (전체 폭)
    // 클립 있을 때: 뮤트 버튼만 (영상 전용) — 추가 버튼은 clipStrip 끝으로 이동

    @ViewBuilder
    private var pickerButtonRow: some View {
        // slide mode with showPickerButton=false → parent handles picker; render nothing
        if showPickerButton || !isPhotoSlideMode {
            HStack(spacing: 8) {
                if recipes.isEmpty { addEmptyButton }
            }
        }
    }

    // 비어있을 때 표시하는 큰 추가 버튼 (사진 아이콘 통일)
    @ViewBuilder
    private var addEmptyButton: some View {
        if isPhotoSlideMode {
            Button {
                photoSlidePickerItems = []
                showPhotoSlidePicker  = true
            } label: { emptyButtonFace }
            .buttonStyle(.plain)
            .photosPicker(isPresented: $showPhotoSlidePicker,
                          selection: $photoSlidePickerItems,
                          maxSelectionCount: PhotoSlideComposition.maxPhotos,
                          matching: .images, photoLibrary: .shared())
        } else {
            PhotosPicker(selection: $videoPickerItems,
                         maxSelectionCount: 10, matching: .videos,
                         photoLibrary: .shared()) { emptyButtonFace }
            .buttonStyle(.plain)
        }
    }

    private var emptyButtonFace: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 17))
            Text(isPhotoSlideMode
                 ? AppLanguage.shared.s("사진 선택", "Select Photos")
                 : AppLanguage.shared.s("영상 선택", "Select Video"))
                .font(.subheadline)
        }
        .foregroundStyle(Color.white.opacity(0.55))
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // 클립 스트립 끝에 인라인으로 붙는 + 추가 버튼
    @ViewBuilder
    private var addInlineButton: some View {
        let canAdd = isPhotoSlideMode
            ? recipes.count < PhotoSlideComposition.maxPhotos
            : totalSeconds < MultiClipComposition.maxSeconds
        if showPickerButton, canAdd {
            let btnFace = RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.violet))
            if isPhotoSlideMode {
                Button {
                    photoSlidePickerItems = []
                    showPhotoSlidePicker  = true
                } label: { btnFace }
                .buttonStyle(.plain)
                .photosPicker(isPresented: $showPhotoSlidePicker,
                              selection: $photoSlidePickerItems,
                              maxSelectionCount: PhotoSlideComposition.maxPhotos,
                              matching: .images, photoLibrary: .shared())
            } else {
                PhotosPicker(selection: $videoPickerItems,
                             maxSelectionCount: 10, matching: .videos,
                             photoLibrary: .shared()) { btnFace }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Clip strip

    private var clipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(recipes.indices, id: \.self) { i in
                    let isDragging = draggingClipIndex == i
                    ZStack(alignment: .topTrailing) {
                        clipButton(index: i)
                        Button { removeClip(at: i) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, Color.black.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                    .scaleEffect(isDragging ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isDragging)
                    .highPriorityGesture(dragGesture(for: i))
                }
                // 클립 바로 옆에 + 추가 버튼 (비어있을 때는 pickerButtonRow에 표시)
                addInlineButton
            }
            .padding(.vertical, 4)
        }
    }

    private func clipButton(index i: Int) -> some View {
        let avail = clipAvailability(recipes[i])
        let isSelected = safeClipIdx == i
        let isNoSource = avail == .noSource
        return Button {
            if isNoSource {
                showReAddAlert = true
            } else {
                selectedClipIndex = i
                if openEditOnTap { isEditing = true }
            }
        } label: {
            Group {
                if let thumb = recipes[i].thumbnail {
                    Image(uiImage: thumb).resizable().scaledToFill()
                        .overlay(isNoSource ? Color.black.opacity(0.45) : Color.clear)
                } else {
                    Rectangle().fill(Color(.systemGray5))
                        .overlay(Image(systemName: isPhotoSlideMode ? "photo" : "video")
                                     .foregroundStyle(.secondary))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                isSelected   ? Theme.violet :
                isNoSource   ? Color.yellow.opacity(0.7) :
                avail == .deleted   ? Color.red.opacity(0.5) :
                avail == .resolving ? Color.white.opacity(0.35) :
                recipes[i].isTrimmed ? Color.orange.opacity(0.7) : Color.white.opacity(0.2),
                lineWidth: isSelected ? 2.5 : 1.5))
            .overlay(alignment: .bottom) {
                if isNoSource {
                    Text(AppLanguage.shared.s("재추가 필요", "Re-add"))
                        .font(.system(size: 7, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Color.yellow.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 2)).padding(.bottom, 3)
                } else if avail == .deleted {
                    Text(AppLanguage.shared.s("원본 없음", "Missing"))
                        .font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Color.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 2)).padding(.bottom, 3)
                } else if avail == .resolving {
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(.white)
                        .padding(.bottom, 3)
                } else if !isStoryMode {
                    Text("\(Int(recipes[i].trimmedDuration / max(0.1, recipes[i].speed)))s")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Color.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 3)).padding(.bottom, 3)
                }
            }
            .overlay(alignment: .topLeading) {
                if recipes[i].hasText {
                    Circle().fill(Theme.violet).frame(width: 7, height: 7).padding(3)
                }
            }
            .opacity(avail == .deleted ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func dragGesture(for i: Int) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                if draggingClipIndex == nil { draggingClipIndex = i }
                guard let from = draggingClipIndex else { return }
                let step: CGFloat = 60
                if v.translation.width > step / 2, from < recipes.count - 1 {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        recipes.swapAt(from, from + 1); draggingClipIndex = from + 1
                    }
                } else if v.translation.width < -step / 2, from > 0 {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        recipes.swapAt(from, from - 1); draggingClipIndex = from - 1
                    }
                }
            }
            .onEnded { _ in withAnimation { draggingClipIndex = nil }; onSave() }
    }

    // MARK: - Story hint row

    private var storyHintRow: some View {
        Text(AppLanguage.shared.s(
            "사진 \(recipes.count)장  (탭하면 상세 편집)",
            "\(recipes.count) photos  (tap to edit)"))
            .font(.caption).foregroundStyle(.secondary)
    }


    // MARK: - Duration row

    private var durationRow: some View {
        let exceeded = totalSeconds > MultiClipComposition.maxSeconds
        let overBy   = Int(totalSeconds) - Int(MultiClipComposition.maxSeconds)
        return Group {
            if exceeded {
                Text(AppLanguage.shared.s(
                    "전체 60초를 넘어요 — \(overBy)초 초과",
                    "Over 60s limit — \(overBy)s too long"))
                    .font(.caption).foregroundStyle(.red)
            } else if showEditHint {
                Text(AppLanguage.shared.s(
                    "클립 \(recipes.count)개 · \(Int(totalSeconds))초  (탭하면 상세 편집)",
                    "\(recipes.count) clips · \(Int(totalSeconds))s  (tap to edit)"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(AppLanguage.shared.s(
                    "클립 \(recipes.count)개 · \(Int(totalSeconds))초",
                    "\(recipes.count) clips · \(Int(totalSeconds))s"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Metric chips

    private func metricLetter(_ id: String) -> String {
        switch id {
        case "pace":     return "P"
        case "distance": return "D"
        case "time":     return "T"
        default:         return String(id.prefix(1)).uppercased()
        }
    }

    // 지표 = P/D/T 대문자 원문자 토글 배지 (값은 영상 오버레이에 표시)
    private var metricChipsRow: some View {
        HStack(spacing: 10) {
            ForEach(availableMetrics) { m in
                let on = enabledMetricIDs.contains(m.id)
                Button {
                    if on { enabledMetricIDs.remove(m.id) } else { enabledMetricIDs.insert(m.id) }
                    onSave()
                } label: {
                    Text(metricLetter(m.id))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(on ? m.color.opacity(0.9) : Color.white.opacity(0.08)))
                        .foregroundStyle(on ? .white : Color.white.opacity(0.5))
                        .overlay(Circle().strokeBorder(on ? m.color : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Title section (영상·슬라이드 only)

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isPhotoSlideMode {
                // 슬라이드: 눈에 띄는 박스형 입력 + 섹션 레이블
                HStack {
                    Text(AppLanguage.shared.s("문구 (선택)", "Caption (optional)"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                TextField(AppLanguage.shared.s("영상에 넣을 문구를 입력하세요", "Enter a caption for the video"),
                          text: $videoTitle,
                          axis: .vertical)
                    .lineLimit(1...3)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .tint(Theme.violet)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onChange(of: videoTitle) { _, _ in onSave() }
            } else {
                // 영상: 기존 미니멀 스타일
                Divider()
                TextField(AppLanguage.shared.s("전체 제목 (선택)", "Title (optional)"),
                          text: $videoTitle,
                          axis: .vertical)
                    .lineLimit(1...2)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .tint(Theme.violet)
                    .onChange(of: videoTitle) { _, _ in onSave() }
            }
            HStack(alignment: .top, spacing: 10) {
                titlePositionGrid
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 0) {
                        titleSizeChips
                        Spacer(minLength: 8)
                        if !isPhotoSlideMode {
                            Button { muteAudio.toggle(); onSave() } label: {
                                Image(systemName: muteAudio ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .foregroundStyle(muteAudio ? Color.secondary : Theme.violet)
                                    .font(.system(size: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    titleFontChips
                    titleColorCircles
                    titleOutlineChip
                }
            }
        }
    }

    private var titlePositionGrid: some View {
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
                        let isSel = titleStyle.position == pos
                        Button {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                titleStyle.position = pos
                                onSave()
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

    private var titleSizeChips: some View {
        HStack(spacing: 6) {
            ForEach(TextSizeLevel.allCases, id: \.self) { s in
                let isSel = titleStyle.sizeLevel == s
                Button { titleStyle.sizeLevel = s; onSave() } label: {
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

    private var titleFontChips: some View {
        HStack(spacing: 6) {
            ForEach(OneLinerFont.allCases, id: \.self) { f in
                let isSel = titleStyle.fontChoice == f
                Button { titleStyle.fontChoice = f; onSave() } label: {
                    Text(f.chipLabel)
                        .font(f.swiftUIFont(size: 13))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isSel ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08))
                        .foregroundStyle(isSel ? Theme.violet : Color.white.opacity(0.70))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(isSel ? Theme.violet.opacity(0.55) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var titleColorCircles: some View {
        HStack(spacing: 8) {
            ForEach(OneLinerTextColor.allCases, id: \.self) { c in
                let isSel = titleStyle.textColor == c
                Button { titleStyle.textColor = c; onSave() } label: {
                    ZStack {
                        Circle().fill(c.color).frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(c == .white ? Color.gray.opacity(0.4) : Color.clear, lineWidth: 1))
                        if isSel {
                            Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var titleOutlineChip: some View {
        let isSel = titleStyle.outline
        return Button { titleStyle.outline.toggle(); onSave() } label: {
            Text(AppLanguage.shared.s("외곽선", "Outline"))
                .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(isSel ? Theme.violet.opacity(0.20) : Color.white.opacity(0.08))
                .foregroundStyle(isSel ? Theme.violet : Color.white.opacity(0.55))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isSel ? Theme.violet.opacity(0.55) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Clip management

    private func removeClip(at index: Int) {
        guard index < recipes.count else { return }
        let r = recipes[index]
        if let ref = r.thumbRef      { ClipThumbStore.delete(ref: ref) }
        if let ref = r.storedPhotoRef { OneLinerPhotoStore.delete(mediaRef: ref) }
        recipes.remove(at: index)
        if recipes.isEmpty {
            muteAudio         = false
            selectedClipIndex = 0
        } else {
            selectedClipIndex = min(selectedClipIndex, recipes.count - 1)
        }
        onSave()
    }

    // MARK: - Availability

    // .noSource: assetIdentifier·clipVideoRef 모두 없음 — 구 포맷 저장본이어서 복구 불가
    private enum ClipAvailability { case available, resolving, resolvable, deleted, noSource }
    private func clipAvailability(_ r: ClipRecipe) -> ClipAvailability {
        // 실제 파일 존재 확인 (디렉토리 제외)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: r.url.path, isDirectory: &isDir), !isDir.boolValue {
            // 파일이 존재해도 placeholder 이름이면 소스 없음으로 간주
            let name = r.url.lastPathComponent
            if name.hasPrefix("mimo_placeholder_") { }  // fall through
            else { return .available }
        }
        // AVAsset 비동기 해석 결과가 이미 있으면 resolvable
        if r.resolvedAsset != nil { return .resolvable }
        // PHAsset 기반 해석 중 → 로딩 표시 (원본 없음 조기 단정 금지)
        if let id = r.assetIdentifier {
            if resolvingIDs.contains(id) { return .resolving }
            if failedIDs.contains(id)   { return .deleted }
            if PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).count > 0 { return .resolvable }
            return .deleted
        }
        // 영상 앱-내 복사본 (assetIdentifier 없는 경우 폴백)
        if let ref = r.clipVideoRef, ClipVideoStore.fileExists(ref: ref) { return .available }
        // 사진 로컬 저장본
        if let pr = r.storedPhotoRef, OneLinerPhotoStore.fileExists(mediaRef: pr) { return .resolvable }
        // 복구 가능한 참조가 전혀 없음 → 재추가 필요 (구 포맷 저장본 등)
        return .noSource
    }

    // MARK: - Async loaders

    private func loadVideoClips(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var loaded: [ClipRecipe] = []
            var runningTotal = MultiClipComposition.totalDuration(recipes: recipes)
            for item in items {
                guard runningTotal < MultiClipComposition.maxSeconds else { break }
                guard let result = try? await item.loadTransferable(type: VideoPickerResult.self)
                else { continue }
                let tempURL = result.url
                let dur = (try? await AVURLAsset(url: tempURL).load(.duration).seconds) ?? 0
                guard dur > 0 else { continue }
                let thumb = await VideoExportService.firstFrame(of: tempURL)

                var recipe: ClipRecipe

                if let assetID = item.itemIdentifier {
                    // PHPicker(photoLibrary: .shared()) → assetIdentifier 사용 가능
                    // 임시 URL로 레시피 생성 후 즉시 AVAsset 해석 → resolvedAsset 바인딩
                    recipe = ClipRecipe(url: tempURL, fullDuration: dur, thumbnail: thumb)
                    recipe.assetIdentifier = assetID
                    if let avAsset = try? await MultiClipComposition.resolveAVAsset(assetID: assetID) {
                        recipe.resolvedAsset = avAsset
                    }
                } else {
                    // 라이브러리 밖(AirDrop 등): 임시 파일을 앱 Documents로 복사 → 안정 URL 확보
                    let ref = ClipVideoStore.save(from: tempURL)
                    let stableURL = ref.flatMap { ClipVideoStore.fileURL(ref: $0) } ?? tempURL
                    recipe = ClipRecipe(url: stableURL, fullDuration: dur, thumbnail: thumb)
                    recipe.clipVideoRef = ref
                }

                if let th = thumb { recipe.thumbRef = ClipThumbStore.save(th) }
                let clipIdx = recipes.count + loaded.count
                recipe.flyDirection = (clipIdx % 2 == 0) ? .trailing : .leading
                if let prev = loaded.last ?? recipes.last {
                    recipe.fontChoice = prev.fontChoice
                    recipe.textColor  = prev.textColor
                    recipe.position   = prev.position
                    recipe.sizeLevel  = prev.sizeLevel
                }
                loaded.append(recipe)
                runningTotal += dur
            }
            guard !loaded.isEmpty else { return }
            let firstNewIdx = recipes.count
            await MainActor.run {
                recipes.append(contentsOf: loaded)
                selectedClipIndex = firstNewIdx
                isPhotoSlideMode = false
                onSave()
            }
        }
    }

    private func loadPhotoSlides(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            // Cap at maxPhotos total
            let remaining = PhotoSlideComposition.maxPhotos - recipes.count
            guard remaining > 0 else { return }
            var loaded: [ClipRecipe] = []
            for item in Array(items.prefix(remaining)) {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let img  = UIImage(data: data) else { continue }
                let photoRef = OneLinerPhotoStore.save(img)
                let jpegURL  = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mimo_photoclip_\(UUID().uuidString).jpg")
                if let jpeg = img.jpegData(compressionQuality: 0.82) { try? jpeg.write(to: jpegURL) }
                var recipe = ClipRecipe(url: jpegURL,
                                        fullDuration: PhotoSlideComposition.photoDuration, thumbnail: img)
                recipe.storedPhotoRef = photoRef
                recipe.lines = ["", ""]
                let clipIdx = recipes.count + loaded.count
                recipe.flyDirection = (clipIdx % 2 == 0) ? .trailing : .leading
                if let prev = loaded.last ?? recipes.last {
                    recipe.fontChoice = prev.fontChoice
                    recipe.textColor  = prev.textColor
                    recipe.position   = prev.position
                    recipe.sizeLevel  = prev.sizeLevel
                }
                loaded.append(recipe)
            }
            guard !loaded.isEmpty else { return }
            let firstNewIdx = recipes.count
            await MainActor.run {
                recipes.append(contentsOf: loaded)
                selectedClipIndex = firstNewIdx
                isPhotoSlideMode = true
                onSave()
            }
        }
    }

    // MARK: - PHAsset 비동기 해석 (리스트 전환·재진입 시 만료 URL 복원)

    private func resolveVideoClips() {
        for i in recipes.indices {
            guard let assetID = recipes[i].assetIdentifier else { continue }
            // clipVideoRef 안정 복사본이 있으면 PHAsset 해석 불필요
            if let ref = recipes[i].clipVideoRef, ClipVideoStore.fileExists(ref: ref) { continue }
            let urlOK = FileManager.default.fileExists(atPath: recipes[i].url.path)
            guard !urlOK,
                  recipes[i].resolvedAsset == nil,
                  !resolvingIDs.contains(assetID),
                  !failedIDs.contains(assetID) else { continue }
            resolvingIDs.insert(assetID)
            Task {
                do {
                    let avAsset = try await MultiClipComposition.resolveAVAsset(assetID: assetID)
                    await MainActor.run {
                        if let idx = recipes.firstIndex(where: { $0.assetIdentifier == assetID }) {
                            recipes[idx].resolvedAsset = avAsset
                        }
                        resolvingIDs.remove(assetID)
                    }
                } catch {
                    await MainActor.run {
                        failedIDs.insert(assetID)
                        resolvingIDs.remove(assetID)
                    }
                }
            }
        }
    }
}

// MARK: - OneLinerPhotoStore
// Saves rest-day background photos and photo-slide source images to app Documents.
// mediaRef format: "restphoto:<uuid>.jpg"

enum OneLinerPhotoStore {
    private static var dir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = docs.appendingPathComponent("OneLinerPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static let prefix = "restphoto:"

    static func save(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.82) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do { try data.write(to: dir.appendingPathComponent(name)) } catch { return nil }
        return prefix + name
    }

    static func load(mediaRef: String) -> UIImage? {
        guard mediaRef.hasPrefix(prefix) else { return nil }
        let name = String(mediaRef.dropFirst(prefix.count))
        return UIImage(contentsOfFile: dir.appendingPathComponent(name).path)
    }

    static func delete(mediaRef: String) {
        guard mediaRef.hasPrefix(prefix) else { return }
        let name = String(mediaRef.dropFirst(prefix.count))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }

    static func fileExists(mediaRef: String) -> Bool {
        guard mediaRef.hasPrefix(prefix) else { return false }
        let name = String(mediaRef.dropFirst(prefix.count))
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
    }
}

// MARK: - ClipThumbStore
// 200 px mini-thumbnails for video clips (display when temp URL expires).
// mediaRef format: "clipthumb:<uuid>.jpg"

enum ClipThumbStore {
    private static var dir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = docs.appendingPathComponent("ClipThumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static let prefix = "clipthumb:"

    static func save(_ image: UIImage) -> String? {
        let thumb = image.scaledToFit(maxSide: 200)
        guard let data = thumb.jpegData(compressionQuality: 0.55) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do { try data.write(to: dir.appendingPathComponent(name)) } catch { return nil }
        return prefix + name
    }

    static func load(ref: String) -> UIImage? {
        guard ref.hasPrefix(prefix) else { return nil }
        let name = String(ref.dropFirst(prefix.count))
        return UIImage(contentsOfFile: dir.appendingPathComponent(name).path)
    }

    static func delete(ref: String) {
        guard ref.hasPrefix(prefix) else { return }
        let name = String(ref.dropFirst(prefix.count))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }

    static func fileExists(ref: String) -> Bool {
        guard ref.hasPrefix(prefix) else { return false }
        let name = String(ref.dropFirst(prefix.count))
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
    }
}

// MARK: - SavedRecipeSet / SavedClipDescriptor
// v3recipes JSON payload — shared by RestDayOneLinerSheet and ShareCardView.

struct SavedRecipeSet: Codable {
    var isPhotoSlide: Bool
    var muteAudio:    Bool
    var clips:        [SavedClipDescriptor]
    var isShared:     Bool    = false
    var mode:         String? = nil   // "story" | nil (video/slide inferred from isPhotoSlide)
    // Full-video title overlay (영상·슬라이드 only)
    var videoTitle:     String  = ""
    var titleAnchorIdx: Int?    = nil
    var titleFontID:    String? = nil
    var titleColorID:   String? = nil
    var titleSizeID:    String? = nil
    var titleOutline:   Bool    = false
}

struct SavedClipDescriptor: Codable {
    var assetID:      String?
    var clipVideoRef: String? = nil  // ClipVideoStore ref — fallback when assetID unavailable
    var photoRef:     String?
    var thumbRef:     String?
    var trimStart:    Double
    var trimEnd:      Double
    var fullDuration: Double
    var lines:        [String]
    // Per-clip style — nil means legacy save (parent will apply migration)
    var fontID:    String? = nil   // OneLinerFont.rawValue
    var colorID:   String? = nil   // OneLinerTextColor.rawValue
    var anchorIdx: Int?    = nil   // index into CardPosition.allCases
    var sizeID:    String? = nil   // TextSizeLevel.rawValue
    var effectID:     String? = nil   // "appearanceMode|decorEffect|outline(0/1)" e.g. "fade|pop|0"
    var plateColorID: String? = nil   // PlateColorPreset.rawValue
    var speed:        Double  = 1.0   // 재생 배속 (하위호환: 미존재 시 1.0)
    var cropOffsetX:  Double  = 0.5   // 가로 크롭 위치 (하위호환: 미존재 시 0.5=중앙)
    // 러닝 데이터 오버레이 (운동한 날, 클립별) — 하위호환 기본값
    var metricPace:      Bool = false
    var metricDistance:  Bool = false
    var metricTime:      Bool = false
    var metricHeartRate: Bool = false
    var pdtAnchorIdx:    Int? = nil    // CardPosition.allCases index
    var showRoute:      Bool = false   // 하위호환 레거시 (chartTypeID 우선)
    var routeAnchorIdx: Int? = nil
    var showHRChart:    Bool = false   // 하위호환 레거시 (chartTypeID 우선)
    // 신규 데이터 오버레이 필드 (하위호환: nil = 레거시 fallback)
    var chartTypeID:   String? = nil   // ChartOverlayType.rawValue
    var pdtSizeID2:    String? = nil   // TextSizeLevel.rawValue (PDT 뱃지 크기)
    var dataEffectID:  String? = nil   // AppearanceMode.rawValue (데이터 등장 방식)
}

// MARK: - ClipVideoStore
// Stable app-Documents storage for video clips whose PHAsset localIdentifier is unavailable.
// Only used as fallback; PHAsset-based resolution is always preferred.

enum ClipVideoStore {
    static let prefix = "clipvideo:"
    private static var dir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = docs.appendingPathComponent("ClipVideos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func save(from url: URL) -> String? {
        let name = UUID().uuidString + ".mov"
        let dest = dir.appendingPathComponent(name)
        do { try FileManager.default.copyItem(at: url, to: dest) } catch { return nil }
        return prefix + name
    }
    static func fileURL(ref: String) -> URL? {
        guard ref.hasPrefix(prefix) else { return nil }
        let name = String(ref.dropFirst(prefix.count))
        return dir.appendingPathComponent(name)
    }
    static func fileExists(ref: String) -> Bool {
        guard let url = fileURL(ref: ref) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    static func delete(ref: String) {
        guard let url = fileURL(ref: ref) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - UIImage scale helper

extension UIImage {
    func scaledToFit(maxSide: CGFloat) -> UIImage {
        let scale = maxSide / max(size.width, size.height)
        guard scale < 1.0 else { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
