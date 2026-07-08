import SwiftUI
import SwiftData
import PhotosUI

// MARK: - RestDayOneLinerSheet
//
// OneLiner card editor for rest days (days with no workout activity).
// Stores entries with workoutID = "date:yyyy-MM-dd" — see OneLinerEntry.restDayWorkoutID(for:).
// Photo/gradient only (no video in this sheet; video is handled in the main ShareCardScreen).

struct RestDayOneLinerSheet: View {
    let date: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    @Query private var allEntries: [OneLinerEntry]

    private var workoutID: String { OneLinerEntry.restDayWorkoutID(for: date) }

    // Entry with mediaRef == nil = gradient background entry for this rest day
    private var gradientEntry: OneLinerEntry? {
        allEntries.first { $0.workoutID == workoutID && $0.mediaRef == nil }
    }

    // MARK: State
    @State private var text:        String           = ""
    @State private var fontChoice:  OneLinerFont     = .pen
    @State private var textColor:   OneLinerTextColor = .white
    @State private var position:    CardPosition     = .center
    @State private var backgroundPhoto: UIImage? = nil
    @State private var photoPickerItem: PhotosPickerItem? = nil

    @State private var shareImage:     UIImage? = nil
    @State private var showShareSheet: Bool     = false

    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0E0E18").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // ── Card preview ──────────────────────────────────
                        OneLinerCard(
                            displayDate: date,
                            backgroundPhoto: backgroundPhoto,
                            text: text,
                            position: position,
                            textColor: textColor,
                            fontChoice: fontChoice,
                            showDate: true
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                        .padding(.top, 16)

                        // ── Controls ──────────────────────────────────────
                        VStack(spacing: 12) {
                            // Text input
                            oneLinerTextField

                            // 9-position grid + font/color chips (identical to running-day layout)
                            gridAndChips

                            // Photo picker row
                            photoRow
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle(dateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguage.shared.s("닫기", "Close")) { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        renderCardForSharing()
                    } label: {
                        Label(AppLanguage.shared.s("공유", "Share"),
                              systemImage: "square.and.arrow.up")
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let img = shareImage {
                    ShareLink(item: Image(uiImage: img),
                              preview: SharePreview(
                                AppLanguage.shared.s("오늘의 한마디", "Today's One-liner"),
                                image: Image(uiImage: img)))
                }
            }
        }
        .onAppear { loadEntry() }
        .onChange(of: photoPickerItem) { _, item in
            Task {
                guard let item,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let img  = UIImage(data: data)
                else { return }
                backgroundPhoto = img
            }
        }
    }

    // MARK: - Sub-views

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
                        text = String(lines.prefix(2).joined(separator: "\n").prefix(40))
                        return
                    }
                    if newVal.count > 40 { text = String(newVal.prefix(40)); return }
                    saveEntry()
                }
                Spacer(minLength: 0)
                Text("\(text.count)/40")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(hex: "6E6E78"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(hex: "1E1E28"))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if text.components(separatedBy: "\n").count >= 2 {
                Text(AppLanguage.shared.s("두 줄까지 쓸 수 있어요", "Two lines maximum"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// 9-position anchor grid + font/color chips — mirrors running-day `oneLinerGridAndChips`.
    private var gridAndChips: some View {
        let rows: [[CardPosition]] = [
            [.topLeading,    .top,    .topTrailing],
            [.leading,       .center, .trailing],
            [.bottomLeading, .bottom, .bottomTrailing]
        ]
        return HStack(alignment: .center, spacing: 20) {
            // 3×3 compact grid (23×23 pt squares)
            VStack(spacing: 4) {
                ForEach(rows.indices, id: \.self) { rowIdx in
                    HStack(spacing: 4) {
                        ForEach(rows[rowIdx], id: \.self) { pos in
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

            // Font + color chips stacked
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
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
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
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isSelected
                        ? (tc == .white ? Color(hex: "3A3A44") : tc.color.opacity(0.25))
                        : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var photoRow: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                    Text(backgroundPhoto == nil
                         ? AppLanguage.shared.s("사진 배경 선택", "Add photo background")
                         : AppLanguage.shared.s("사진 변경", "Change photo"))
                        .font(.subheadline)
                }
                .foregroundStyle(Theme.violet)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.violet.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            if backgroundPhoto != nil {
                Button {
                    backgroundPhoto = nil
                    photoPickerItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private var dateTitle: String {
        let f = DateFormatter()
        f.dateFormat = "M월 d일"
        f.locale = Locale(identifier: "ko_KR")
        let enF = DateFormatter()
        enF.dateFormat = "MMM d"
        enF.locale = Locale(identifier: "en_US")
        return AppLanguage.shared.s(f.string(from: date), enF.string(from: date))
            + " " + AppLanguage.shared.s("쉬는 날", "Rest Day")
    }

    private func loadEntry() {
        guard let entry = gradientEntry else { return }
        text      = entry.text
        fontChoice  = entry.font
        textColor = entry.textColor
        position  = entry.position
    }

    private func saveEntry() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = gradientEntry {
            if trimmed.isEmpty {
                modelContext.delete(existing)
            } else {
                existing.text      = text
                existing.font      = fontChoice
                existing.textColor = textColor
                existing.position  = position
                existing.showDate  = true
            }
            try? modelContext.save()
            return
        }
        guard !trimmed.isEmpty else { return }
        let entry = OneLinerEntry(workoutID: workoutID, mediaRef: nil)
        entry.text      = text
        entry.font      = fontChoice
        entry.textColor = textColor
        entry.position  = position
        entry.showDate  = true
        modelContext.insert(entry)
        try? modelContext.save()
    }

    @MainActor
    private func renderCardForSharing() {
        let card = OneLinerCard(
            displayDate: date,
            backgroundPhoto: backgroundPhoto,
            text: text,
            position: position,
            textColor: textColor,
            fontChoice: fontChoice,
            showDate: true
        )
        .frame(width: OneLinerCard.cardWidth, height: OneLinerCard.cardHeight)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        shareImage = renderer.uiImage
        if shareImage != nil { showShareSheet = true }
    }
}
