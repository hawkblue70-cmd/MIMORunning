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
    @State private var showDate:    Bool             = true

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
                            showDate: showDate
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                        .padding(.top, 16)

                        // ── Controls ──────────────────────────────────────
                        VStack(spacing: 14) {
                            // Text input
                            oneLinerTextField

                            // Font + color row
                            fontColorRow

                            // Position grid
                            positionGrid

                            // Photo picker row
                            photoRow

                            // Date toggle
                            dateToggleRow
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

    private var fontColorRow: some View {
        HStack(spacing: 8) {
            ForEach(OneLinerFont.allCases, id: \.self) { f in
                Button {
                    fontChoice = f
                    saveEntry()
                } label: {
                    Text(f.chipLabel)
                        .font(.custom(f.fontName, size: 14))
                        .foregroundStyle(fontChoice == f ? Theme.violet : Color.white.opacity(0.7))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(fontChoice == f
                                    ? Theme.violet.opacity(0.12)
                                    : Color(hex: "1E1E28"))
                        .overlay(Capsule().strokeBorder(
                            fontChoice == f
                                ? Theme.violet.opacity(0.55)
                                : Color.white.opacity(0.15),
                            lineWidth: 1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            ForEach(OneLinerTextColor.allCases, id: \.self) { c in
                Button {
                    textColor = c
                    saveEntry()
                } label: {
                    Circle()
                        .fill(c.color)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(
                            textColor == c ? .white : .white.opacity(0.2),
                            lineWidth: textColor == c ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var positionGrid: some View {
        let cases = Array(CardPosition.allCases)
        let rows: [[CardPosition]] = stride(from: 0, to: cases.count, by: 3).map {
            Array(cases[$0..<min($0 + 3, cases.count)])
        }
        return VStack(spacing: 4) {
            ForEach(rows.indices, id: \.self) { rowIdx in
                HStack(spacing: 4) {
                    ForEach(rows[rowIdx], id: \.self) { pos in
                        Button {
                            position = pos
                            saveEntry()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(position == pos
                                          ? Theme.violet.opacity(0.25)
                                          : Color(hex: "1E1E28"))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                                        position == pos
                                            ? Theme.violet.opacity(0.6)
                                            : Color.white.opacity(0.1),
                                        lineWidth: 1))
                                Circle()
                                    .fill(position == pos ? Theme.violet : Color.white.opacity(0.3))
                                    .frame(width: 5, height: 5)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                                           alignment: pos.alignment)
                                    .padding(5)
                            }
                            .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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

    private var dateToggleRow: some View {
        Toggle(isOn: Binding(
            get: { showDate },
            set: { showDate = $0; saveEntry() }
        )) {
            Text(AppLanguage.shared.s("날짜 표시", "Show date"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
        .tint(Theme.violet)
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
        showDate  = entry.showDate
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
                existing.showDate  = showDate
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
        entry.showDate  = showDate
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
            showDate: showDate
        )
        .frame(width: OneLinerCard.cardWidth, height: OneLinerCard.cardHeight)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        shareImage = renderer.uiImage
        if shareImage != nil { showShareSheet = true }
    }
}
