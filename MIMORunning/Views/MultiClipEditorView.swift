import SwiftUI
import Photos
import PhotosUI
import AVFoundation
import UIKit

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

    /// Called after any change so the parent can persist.
    let onSave: () -> Void

    /// When true: photo-slide editor in story mode — hides duration row and mute button.
    var isStoryMode: Bool = false

    /// Full-video title (영상·슬라이드 only; hidden when isStoryMode).
    @Binding var videoTitle: String
    @Binding var titleStyle: OneLinerTitleStyle

    // Internal picker state
    @State private var videoPickerItems:      [PhotosPickerItem] = []
    @State private var photoSlidePickerItems: [PhotosPickerItem] = []
    @State private var isEditing:             Bool = false
    @State private var draggingClipIndex:     Int? = nil

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
            if !availableMetrics.isEmpty { metricChipsRow }
            if !isStoryMode, !recipes.isEmpty { titleSection }
        }
        .sheet(isPresented: $isEditing) {
            ClipTrimSheet(
                recipes: $recipes,
                selectedClipIndex: $selectedClipIndex,
                hideTimePicker: isStoryMode,
                isStoryMode: isStoryMode
            )
        }
        .onChange(of: isEditing)             { _, v in if !v { onSave() } }
        .onChange(of: videoPickerItems)      { _, items in loadVideoClips(items) }
        .onChange(of: photoSlidePickerItems) { _, items in loadPhotoSlides(items) }
    }

    // MARK: - Picker button row

    private var pickerButtonRow: some View {
        HStack(spacing: 8) {
            if isPhotoSlideMode {
                PhotosPicker(selection: $photoSlidePickerItems,
                             maxSelectionCount: PhotoSlideComposition.maxPhotos, matching: .images) {
                    HStack(spacing: 5) {
                        Image(systemName: "photo.stack.fill")
                        Text(recipes.isEmpty
                             ? AppLanguage.shared.s("사진 선택", "Select Photos")
                             : AppLanguage.shared.s("사진 추가", "Add Photos"))
                            .font(.subheadline)
                    }
                    .foregroundStyle(recipes.isEmpty ? Color.white.opacity(0.55) : Theme.violet)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(recipes.isEmpty ? Color.white.opacity(0.06) : Theme.violet.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                PhotosPicker(selection: $videoPickerItems,
                             maxSelectionCount: 10, matching: .videos) {
                    HStack(spacing: 5) {
                        Image(systemName: "video.badge.plus")
                        Text(recipes.isEmpty
                             ? AppLanguage.shared.s("영상 선택", "Select Videos")
                             : AppLanguage.shared.s("영상 추가", "Add Videos"))
                            .font(.subheadline)
                    }
                    .foregroundStyle(recipes.isEmpty ? Color.white.opacity(0.55) : Theme.violet)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(recipes.isEmpty ? Color.white.opacity(0.06) : Theme.violet.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if !recipes.isEmpty, !isPhotoSlideMode, !isStoryMode {
                Button { muteAudio.toggle(); onSave() } label: {
                    Image(systemName: muteAudio ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(muteAudio ? Color.secondary : Theme.violet)
                        .font(.title3)
                }
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
            }
            .padding(.vertical, 4)
        }
    }

    private func clipButton(index i: Int) -> some View {
        let avail = clipAvailability(recipes[i])
        let isSelected = safeClipIdx == i
        return Button { selectedClipIndex = i; isEditing = true } label: {
            Group {
                if let thumb = recipes[i].thumbnail {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color(.systemGray5))
                        .overlay(Image(systemName: isPhotoSlideMode ? "photo" : "video")
                                     .foregroundStyle(.secondary))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                isSelected ? Theme.violet :
                (avail == .deleted ? Color.red.opacity(0.5) :
                recipes[i].isTrimmed ? Color.orange.opacity(0.7) : Color.white.opacity(0.2)),
                lineWidth: isSelected ? 2.5 : 1.5))
            .overlay(alignment: .bottom) {
                if avail == .deleted {
                    Text(AppLanguage.shared.s("원본 없음", "Missing"))
                        .font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Color.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 2)).padding(.bottom, 3)
                } else if !isStoryMode {
                    Text("\(Int(recipes[i].trimmedDuration))s")
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
            "사진 \(recipes.count)장  (탭하면 편집)",
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
            } else {
                Text(AppLanguage.shared.s(
                    "클립 \(recipes.count)개 · \(Int(totalSeconds))초  (탭하면 편집)",
                    "\(recipes.count) clips · \(Int(totalSeconds))s  (tap to edit)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Metric chips

    private var metricChipsRow: some View {
        HStack(spacing: 6) {
            ForEach(availableMetrics) { m in
                let on = enabledMetricIDs.contains(m.id)
                Button {
                    if on { enabledMetricIDs.remove(m.id) } else { enabledMetricIDs.insert(m.id) }
                    onSave()
                } label: {
                    HStack(spacing: 4) {
                        if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                        Text(m.value).font(.system(size: 12, weight: .semibold).monospacedDigit())
                        Text(m.label).font(.system(size: 10)).opacity(0.7)
                    }
                    .foregroundStyle(on ? .white : Color.white.opacity(0.5))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(on ? m.color.opacity(0.35) : Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(on ? m.color.opacity(0.6) : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Title section (영상·슬라이드 only)

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            TextField(AppLanguage.shared.s("전체 제목 (선택)", "Title (optional)"),
                      text: $videoTitle)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .tint(Theme.violet)
                .onChange(of: videoTitle) { _, _ in onSave() }
            HStack(alignment: .top, spacing: 10) {
                titlePositionGrid
                VStack(alignment: .leading, spacing: 5) {
                    titleSizeChips
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

    private enum ClipAvailability { case available, resolvable, deleted }
    private func clipAvailability(_ r: ClipRecipe) -> ClipAvailability {
        if FileManager.default.fileExists(atPath: r.url.path) { return .available }
        if let id = r.assetIdentifier,
           PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).count > 0 { return .resolvable }
        if let pr = r.storedPhotoRef, OneLinerPhotoStore.fileExists(mediaRef: pr) { return .resolvable }
        return .deleted
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
                let url = result.url
                let dur = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
                guard dur > 0 else { continue }
                let thumb = await VideoExportService.firstFrame(of: url)
                var recipe = ClipRecipe(url: url, fullDuration: dur, thumbnail: thumb)
                recipe.assetIdentifier = item.itemIdentifier
                if let th = thumb { recipe.thumbRef = ClipThumbStore.save(th) }
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
            print("[OneLinerVideo] 추가=\(loaded.count)클립 전체합산=\(Int(runningTotal))초")
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
            print("[OneLinerVideo] type=photo 추가=\(loaded.count)장 전체=\(recipes.count + loaded.count)장")
            await MainActor.run {
                recipes.append(contentsOf: loaded)
                selectedClipIndex = firstNewIdx
                isPhotoSlideMode = true
                onSave()
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
    var effectID:  String? = nil   // "appearanceMode|decorEffect|outline(0/1)" e.g. "fade|pop|0"
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
