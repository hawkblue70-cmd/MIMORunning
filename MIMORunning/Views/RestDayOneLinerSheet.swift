import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// MARK: - RestDayTemplate

private enum RestDayTemplate: String, CaseIterable {
    case story = "스토리"
    case video = "영상"
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
    @State private var videoPickerItems:   [PhotosPickerItem] = []
    @State private var videoFirstFrame:    UIImage?           = nil
    @State private var videoSlotTexts:     [String]           = []
    @State private var videoSlotCount:     Int                = 0
    @State private var videoClipCount:     Int                = 0   // number of clips selected
    @State private var videoTotalSeconds:  Double             = 0   // sum of all clip durations
    @State private var slotTexts:          [String]           = []  // per-photo (mirrors backgroundPhotos)
    @State private var orphanedTexts:      [String]           = []  // texts whose photo was removed
    @State private var draggingPhotoIndex: Int?               = nil
    @State private var selectedTemplate:  RestDayTemplate     = .story
    @State private var videoSourceURLs:   [URL]               = []
    @State private var isExportingVideo:  Bool                = false
    @State private var muteVideoAudio:    Bool                = false
    @State private var activeVideoSlot:   Int                = 0

    @FocusState private var fieldFocused: Bool

    // MARK: Computed
    private var isVideoMode: Bool { videoFirstFrame != nil }

    private var shareButtonActive: Bool {
        guard !isExportingVideo else { return false }
        switch selectedTemplate {
        case .video: return videoFirstFrame != nil && videoTotalSeconds <= MultiClipComposition.maxSeconds
        case .story:
            return true
        }
    }

    private var cardBackground: UIImage? {
        if selectedTemplate == .video { return videoFirstFrame }
        guard !backgroundPhotos.isEmpty else { return nil }
        return backgroundPhotos[min(selectedPhotoIndex, backgroundPhotos.count - 1)]
    }

    /// Text shown on the card preview; uses per-photo slot in photo mode.
    /// Gradient (no-photo) mode shows no text since the input was removed.
    /// Video mode: shows the currently focused slot's text; falls back to first non-empty.
    private var cardText: String {
        if selectedTemplate == .video {
            let active = videoSlotTexts.indices.contains(activeVideoSlot) ? videoSlotTexts[activeVideoSlot] : ""
            if !active.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return active }
            return videoSlotTexts.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
        }
        if !backgroundPhotos.isEmpty, selectedPhotoIndex < slotTexts.count {
            return slotTexts[selectedPhotoIndex]
        }
        return ""
    }

    // MARK: Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Color(hex: "0E0E18").ignoresSafeArea()
                    ScrollView {
                        VStack(spacing: 20) {
                            OneLinerCard(
                                displayDate: date,
                                backgroundPhoto: cardBackground,
                                text: cardText,
                                position: position,
                                textColor: textColor,
                                fontChoice: fontChoice,
                                showDate: true,
                                captionMode: true
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                            .padding(.top, 16)

                            VStack(spacing: 12) {
                                gridAndChips
                                templateTabs

                                if selectedTemplate == .video {
                                    if videoSlotCount > 0 { videoSlotInputs }
                                } else {
                                    // .story — 사진이 있을 때만 텍스트 입력 표시
                                    if !backgroundPhotos.isEmpty {
                                        textSlotsView
                                    }
                                }

                                templateMediaRow
                            }
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

                // Fixed bottom share button
                Button { renderCardForSharing() } label: { shareButtonLabel }
                .disabled(!shareButtonActive)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(hex: "0E0E18"))
            }
            .navigationTitle(dateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { loadEntry() }
        .onChange(of: allEntries) { oldValue, _ in
            guard oldValue.isEmpty, text.isEmpty, backgroundPhotos.isEmpty else { return }
            loadEntry()
        }
        .onChange(of: photoPickerItems) { _, items in
            Task { @MainActor in
                var images: [UIImage] = []
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let img  = UIImage(data: data) else { continue }
                    images.append(img)
                }
                guard !images.isEmpty else { return }

                // Pool = all existing slot texts + orphaned texts.
                // Gradient text is offered as a seed if the pool is otherwise empty.
                var pool = slotTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                         + orphanedTexts
                if pool.isEmpty {
                    let seed = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                               ? (gradientEntry?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                               : text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seed.isEmpty { pool = [seed] }
                }

                // Each new photo takes one text from the pool (or gets "").
                slotTexts     = images.map { _ in pool.isEmpty ? "" : pool.removeFirst() }
                orphanedTexts = pool          // leftovers stay as orphans

                if isVideoMode { text = "" }
                videoFirstFrame = nil
                videoPickerItems = []
                videoSourceURLs  = []
                // videoSlotTexts·videoSlotCount는 영상 상태와 독립 — 사진 선택 시 건드리지 않음
                backgroundPhotos   = images
                selectedPhotoIndex = 0
                savePhotos(images)
            }
        }
        .onChange(of: videoPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                // Load each picker item to a temp URL (sequentially — stable order)
                var urls: [URL] = []
                for item in items {
                    guard let result = try? await item.loadTransferable(type: VideoPickerResult.self)
                    else { continue }
                    urls.append(result.url)
                }
                guard !urls.isEmpty else { return }
                let loadedURLs = urls   // immutable copy for concurrent use

                // First frame preview from first clip
                async let firstFrame = VideoExportService.firstFrame(of: loadedURLs[0])

                // Total duration (load in parallel via MultiClipComposition helper)
                let totalSeconds = await MultiClipComposition.totalDuration(urls: loadedURLs)
                let count        = max(1, min(20, Int(totalSeconds / 3.0)))

                print("[OneLinerVideo] 클립수=\(loadedURLs.count) 합산=\(Int(totalSeconds))초 칸=\(count)개 생성")

                // 사진 상태는 독립 보존 — 영상 선택 시 건드리지 않음
                videoFirstFrame   = await firstFrame
                videoSourceURLs   = loadedURLs
                videoClipCount    = loadedURLs.count
                videoTotalSeconds = totalSeconds
                videoSlotCount    = count
                // 기존 문구 유지: 새 슬롯 수 범위 안은 보존, 초과분 삭제
                let prev = videoSlotTexts
                videoSlotTexts    = (0..<count).map { i in i < prev.count ? prev[i] : "" }
                text              = ""
                selectedTemplate  = .video
            }
        }
    }

    // MARK: - Sub-views

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

    /// Video slot inputs (video mode).
    private var videoSlotInputs: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<videoSlotCount, id: \.self) { i in
                HStack(spacing: 8) {
                    TextField(
                        AppLanguage.shared.s("\(i + 1)번째 줄", "Line \(i + 1)"),
                        text: slotBinding(for: i)
                    )
                    .lineLimit(1)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .tint(Theme.violet)
                    Spacer(minLength: 0)
                    Text("\(i < videoSlotTexts.count ? videoSlotTexts[i].count : 0)/20")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Color(hex: "6E6E78"))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(hex: "1E1E28"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text(AppLanguage.shared.s("각 칸이 영상에서 차례로 나타납니다", "Each line appears in turn"))
                .font(.caption2).foregroundStyle(.secondary)
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
        if selectedTemplate == .story {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(backgroundPhotos.indices, id: \.self) { i in
                        let isDragging = draggingPhotoIndex == i
                        ZStack(alignment: .topTrailing) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { selectedPhotoIndex = i }
                            } label: {
                                Image(uiImage: backgroundPhotos[i])
                                    .resizable().scaledToFill()
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(
                                                selectedPhotoIndex == i
                                                ? Theme.violet : Color.white.opacity(0.2),
                                                lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)

                            Button { deletePhoto(at: i) } label: {
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
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    if draggingPhotoIndex == nil { draggingPhotoIndex = i }
                                    guard let from = draggingPhotoIndex else { return }
                                    let dx = value.translation.width
                                    let step: CGFloat = 60
                                    if dx > step / 2, from < backgroundPhotos.count - 1 {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            backgroundPhotos.swapAt(from, from + 1)
                                            if from < slotTexts.count, from + 1 < slotTexts.count {
                                                slotTexts.swapAt(from, from + 1)
                                            }
                                            draggingPhotoIndex = from + 1
                                            selectedPhotoIndex = from + 1
                                        }
                                    } else if dx < -step / 2, from > 0 {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            backgroundPhotos.swapAt(from, from - 1)
                                            if from < slotTexts.count, from - 1 < slotTexts.count {
                                                slotTexts.swapAt(from, from - 1)
                                            }
                                            draggingPhotoIndex = from - 1
                                            selectedPhotoIndex = from - 1
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        draggingPhotoIndex = nil
                                    }
                                    savePhotos(backgroundPhotos)
                                }
                        )
                    }
                    // 사진 추가 인라인 + 버튼
                    PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 10, matching: .images) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "1E1E28"))
                                .frame(width: 52, height: 52)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                )
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.violet)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        } else if selectedTemplate == .video {
            HStack(spacing: 10) {
                // Thumbnail — first frame of first clip
                if let frame = videoFirstFrame {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: frame)
                            .resizable().scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Theme.violet, lineWidth: 1.5))
                        if videoClipCount > 1 {
                            Text("\(videoClipCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(Theme.violet.opacity(0.85))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .offset(x: 4, y: 4)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Multi-select picker
                    PhotosPicker(selection: $videoPickerItems,
                                 maxSelectionCount: 10,
                                 matching: .videos) {
                        HStack(spacing: 6) {
                            Image(systemName: "video.badge.plus")
                            Text(videoFirstFrame == nil
                                 ? AppLanguage.shared.s("영상 선택", "Select videos")
                                 : AppLanguage.shared.s("영상 변경", "Change videos"))
                                .font(.subheadline)
                        }
                        .foregroundStyle(Theme.violet)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.violet.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    // Clip count + duration label / 60s warning
                    if videoClipCount > 0 {
                        let exceeded = videoTotalSeconds > MultiClipComposition.maxSeconds
                        let overBy   = Int(videoTotalSeconds) - Int(MultiClipComposition.maxSeconds)
                        if exceeded {
                            Text(AppLanguage.shared.s(
                                "전체 60초를 넘어요 — \(overBy)초 초과",
                                "Over 60s limit — \(overBy)s too long"))
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text(AppLanguage.shared.s(
                                "클립 \(videoClipCount)개 · \(Int(videoTotalSeconds))초",
                                "\(videoClipCount) clips · \(Int(videoTotalSeconds))s"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 0)

                if videoFirstFrame != nil {
                    Button { muteVideoAudio.toggle() } label: {
                        Image(systemName: muteVideoAudio ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(muteVideoAudio ? Color.secondary : Theme.violet)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    Button {
                        videoFirstFrame   = nil
                        videoPickerItems  = []
                        videoSourceURLs   = []
                        videoClipCount    = 0
                        videoTotalSeconds = 0
                        text              = ""
                        muteVideoAudio    = false
                        // videoSlotTexts·videoSlotCount는 유지 — 영상 재선택 시 복원됨
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary).font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // .athletic: no media picker
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

    /// Binding for video slot texts.
    private func slotBinding(for index: Int) -> Binding<String> {
        Binding {
            guard index < videoSlotTexts.count else { return "" }
            return videoSlotTexts[index]
        } set: { newVal in
            let cleaned = String(newVal.replacingOccurrences(of: "\n", with: "").prefix(20))
            guard index < videoSlotTexts.count else { return }
            activeVideoSlot = index
            videoSlotTexts[index] = cleaned
            text = videoSlotTexts.filter { !$0.isEmpty }.joined(separator: "\n")
            saveEntry()
        }
    }

    // MARK: - Helpers

    private var dateTitle: String {
        let f = DateFormatter()
        f.dateFormat = "M월 d일"; f.locale = Locale(identifier: "ko_KR")
        let e = DateFormatter()
        e.dateFormat = "MMM d";  e.locale = Locale(identifier: "en_US")
        return AppLanguage.shared.s(f.string(from: date), e.string(from: date))
             + " " + AppLanguage.shared.s("쉬는 날", "Rest Day")
    }

    private func loadEntry() {
        // gradient 엔트리는 더 이상 사용하지 않으므로 스타일만 복원 후 삭제
        if let entry = gradientEntry {
            fontChoice = entry.font
            textColor  = entry.textColor
            position   = entry.position
            modelContext.delete(entry)
            try? modelContext.save()
        }
        // 영상 슬롯 문구 복원 (영상 자체는 재선택 필요, 문구는 DB에서 유지)
        if let vEntry = videoTextEntry {
            let lines = vEntry.text.components(separatedBy: "\n")
            if let first = lines.first, let count = Int(first), count > 0 {
                videoSlotCount = count
                videoSlotTexts = (0..<count).map { i in (i + 1) < lines.count ? lines[i + 1] : "" }
                fontChoice     = vEntry.font
                textColor      = vEntry.textColor
                position       = vEntry.position
            }
        }

        let stored = photoEntries
        guard !stored.isEmpty else { return }
        Task { @MainActor in
            let images = stored.compactMap { OneLinerPhotoStore.load(mediaRef: $0.mediaRef ?? "") }
            guard !images.isEmpty else { return }
            backgroundPhotos   = images
            slotTexts          = stored.prefix(images.count).map { $0.text }
            selectedPhotoIndex = 0
            selectedTemplate   = .story
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
        // Video mode — slot count + texts stored as "<count>\n<slot0>\n<slot1>..."
        if videoSlotCount > 0 {
            let payload = "\(videoSlotCount)\n" + videoSlotTexts.joined(separator: "\n")
            if let existing = videoTextEntry {
                existing.text      = payload
                existing.font      = fontChoice
                existing.textColor = textColor
                existing.position  = position
                existing.showDate  = true
            } else {
                let entry = OneLinerEntry(workoutID: workoutID, mediaRef: "videotexts")
                entry.text      = payload
                entry.font      = fontChoice
                entry.textColor = textColor
                entry.position  = position
                entry.showDate  = true
                modelContext.insert(entry)
            }
            try? modelContext.save()
            return
        }

        if backgroundPhotos.isEmpty {
            // Gradient mode — update gradient entry only
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = gradientEntry {
                if trimmed.isEmpty { modelContext.delete(existing) } else { applyStyle(to: existing) }
            } else if !trimmed.isEmpty {
                let entry = OneLinerEntry(workoutID: workoutID, mediaRef: nil)
                applyStyle(to: entry); modelContext.insert(entry)
            }
        } else {
            // Photo mode — font/color/position apply to all; text is per-slot
            for (i, pe) in photoEntries.enumerated() {
                pe.font      = fontChoice
                pe.textColor = textColor
                pe.position  = position
                pe.showDate  = true
                if i < slotTexts.count { pe.text = slotTexts[i] }
            }
        }
        try? modelContext.save()
    }

    private func switchTemplate(to template: RestDayTemplate) {
        guard template != selectedTemplate else { return }
        saveEntry()   // 전환 전 현재 상태(영상 문구 포함) 즉시 저장
        withAnimation(.easeInOut(duration: 0.15)) { selectedTemplate = template }
        // 사진·영상 상태는 각각 독립 보존 — 탭 전환 시 삭제하지 않음
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

    @MainActor
    private func renderCardForSharing() {
        // 영상 템플릿: VideoExportService로 실제 .mov 출력
        if selectedTemplate == .video, !videoSourceURLs.isEmpty {
            isExportingVideo = true
            Task {
                defer { isExportingVideo = false }
                do {
                    // Multi-clip: compose clips first (rotation+stitch), then overlay typing animation.
                    // Single-clip: skip compose step to avoid the extra encode pass.
                    let exportURL:  URL
                    var cleanupURL: URL? = nil
                    if videoSourceURLs.count > 1 {
                        let (composed, _) = try await MultiClipComposition.composeAndExport(
                            urls: videoSourceURLs, muteAudio: muteVideoAudio)
                        exportURL  = composed
                        cleanupURL = composed
                    } else {
                        exportURL = videoSourceURLs[0]
                    }
                    defer { cleanupURL.map { try? FileManager.default.removeItem(at: $0) } }

                    // For multi-clip the composed file is the full duration; don't trim it.
                    let maxDur: Double? = videoSourceURLs.count > 1 ? videoTotalSeconds : nil
                    // Audio is already handled by composeAndExport for multi-clip.
                    let isMuted = videoSourceURLs.count > 1 ? false : muteVideoAudio

                    let outputURL: URL
                    if videoSlotCount > 1 {
                        let count = videoSlotTexts.count
                        let pages = stride(from: 0, to: count, by: 2).map {
                            Array(videoSlotTexts[$0..<min($0 + 2, count)])
                        }
                        outputURL = try await VideoExportService.exportOneLinerMultiPageVideo(
                            sourceURL: exportURL, pages: pages,
                            fontChoice: fontChoice, textColor: textColor, position: position,
                            activityDate: date, showDate: true,
                            muteAudio: isMuted, maxDuration: maxDur)
                    } else {
                        outputURL = try await VideoExportService.exportOneLinerTypingVideo(
                            sourceURL: exportURL, text: videoSlotTexts.first ?? "",
                            fontChoice: fontChoice, textColor: textColor, position: position,
                            activityDate: date, showDate: true,
                            muteAudio: isMuted, maxDuration: maxDur)
                    }
                    presentShareSheet(url: outputURL)
                } catch {
                    // export failed — silently ignore (user can retry)
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
        for (photo, txt) in pairs {
            let card = OneLinerCard(
                displayDate: date,
                backgroundPhoto: photo,
                text: txt,
                position: position,
                textColor: textColor,
                fontChoice: fontChoice,
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

// MARK: - OneLinerPhotoStore

/// Saves rest-day background photos as JPEG files in <Documents>/OneLinerPhotos/.
/// mediaRef format: "restphoto:<uuid>.jpg"
private enum OneLinerPhotoStore {
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
}
