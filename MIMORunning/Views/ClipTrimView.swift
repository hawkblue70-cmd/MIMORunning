import SwiftUI
import AVFoundation

// MARK: - ClipTrimSheet
//
// Modal sheet: static first-frame preview + Instagram-style trim bar
// + per-clip text slot inputs below the bar.
// All edits (trim + lines) are committed atomically on "완료".

struct ClipTrimSheet: View {
    @Binding var recipe: ClipRecipe
    @Environment(\.dismiss) private var dismiss

    // Local copies; written back to recipe only on "완료"
    @State private var trimStart: Double = 0
    @State private var trimEnd:   Double = 0
    @State private var lines:     [String] = []

    /// Number of slots that the current local trim would produce.
    private var projectedCount: Int {
        max(1, min(20, Int(max(0.1, trimEnd - trimStart) / 3.0)))
    }

    /// Non-empty lines beyond projectedCount — warn user they'll be dropped.
    private var droppedWarning: String? {
        guard projectedCount < lines.count else { return nil }
        let wouldDrop = lines[projectedCount...]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !wouldDrop.isEmpty else { return nil }
        return AppLanguage.shared.s(
            "\(projectedCount + 1)번째 줄부터 표시되지 않아요",
            "Lines from \(projectedCount + 1) won't appear")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // ── Static preview ──────────────────────────
                    Group {
                        if let thumb = recipe.thumbnail {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 240)
                                .cornerRadius(10)
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray5))
                                .frame(height: 180)
                                .overlay(
                                    Image(systemName: "video")
                                        .font(.system(size: 36))
                                        .foregroundStyle(.secondary)
                                )
                        }
                    }
                    .padding(.horizontal)

                    // ── Duration readout ────────────────────────
                    let trimmed = max(0.1, trimEnd - trimStart)
                    Text(AppLanguage.shared.s(
                        "\(formatSec(trimStart)) – \(formatSec(trimEnd))  ·  \(formatSec(trimmed)) 사용",
                        "\(formatSec(trimStart)) – \(formatSec(trimEnd))  ·  \(formatSec(trimmed)) used"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    // ── Trim bar ─────────────────────────────────
                    TrimBarView(
                        duration:  recipe.fullDuration,
                        trimStart: $trimStart,
                        trimEnd:   $trimEnd
                    )
                    .padding(.horizontal)

                    // Drop warning — appears as user trims shorter
                    if let warning = droppedWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal)
                    }

                    Divider().padding(.horizontal)

                    // ── Text slot inputs ─────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLanguage.shared.s("문구", "Text"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

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
                                Text("\((i < lines.count ? lines[i] : "").count)/20")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(Color(hex: "6E6E78"))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color(hex: "1E1E28"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                        }

                        Text(AppLanguage.shared.s(
                            "각 줄이 영상에서 차례로 나타납니다",
                            "Each line appears in turn on the video"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Color(hex: "0E0E18").ignoresSafeArea())
            .navigationTitle(AppLanguage.shared.s("구간·문구 설정", "Trim & Text"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.shared.s("취소", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLanguage.shared.s("완료", "Done")) { commit() }
                        .bold()
                }
            }
        }
        .onAppear {
            trimStart = recipe.trimStart
            trimEnd   = recipe.trimEnd
            lines     = recipe.lines
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private func lineBinding(for i: Int) -> Binding<String> {
        Binding {
            i < lines.count ? lines[i] : ""
        } set: { newVal in
            let v = String(newVal.replacingOccurrences(of: "\n", with: "").prefix(20))
            while lines.count <= i { lines.append("") }
            lines[i] = v
        }
    }

    private func commit() {
        let count = projectedCount
        let finalLines: [String]
        if lines.count >= count {
            finalLines = Array(lines.prefix(count))
        } else {
            finalLines = lines + Array(repeating: "", count: count - lines.count)
        }
        recipe.trimStart = trimStart
        recipe.trimEnd   = trimEnd
        recipe.lines     = finalLines
        dismiss()
    }

    private func formatSec(_ s: Double) -> String {
        let i = Int(s)
        return "\(i / 60):\(String(format: "%02d", i % 60))"
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
