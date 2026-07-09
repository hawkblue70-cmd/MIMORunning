import SwiftUI
import AVFoundation

// MARK: - ClipTrimSheet
//
// Modal sheet shown when the user taps a clip in the thumbnail strip.
// Shows a static first-frame preview + an Instagram-style trim bar.
// Trim values are written back via a Binding<ClipRecipe>.

struct ClipTrimSheet: View {
    @Binding var recipe: ClipRecipe
    @Environment(\.dismiss) private var dismiss

    // Local copy so changes are only committed on "완료"
    @State private var trimStart: Double = 0
    @State private var trimEnd:   Double = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // ── Static preview ──────────────────────────────
                Group {
                    if let thumb = recipe.thumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .clipped()
                            .cornerRadius(10)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray5))
                            .frame(height: 200)
                            .overlay(
                                Image(systemName: "video")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
                .padding(.horizontal)

                // ── Duration info ────────────────────────────────
                let trimmed = max(0.1, trimEnd - trimStart)
                Text(AppLanguage.shared.s(
                    "\(formatSec(trimStart)) – \(formatSec(trimEnd))  ·  \(formatSec(trimmed)) 사용",
                    "\(formatSec(trimStart)) – \(formatSec(trimEnd))  ·  \(formatSec(trimmed)) used"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                // ── Trim bar ─────────────────────────────────────
                TrimBarView(
                    duration:  recipe.fullDuration,
                    trimStart: $trimStart,
                    trimEnd:   $trimEnd
                )
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle(AppLanguage.shared.s("구간 설정", "Trim Clip"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.shared.s("취소", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLanguage.shared.s("완료", "Done")) {
                        recipe.trimStart = trimStart
                        recipe.trimEnd   = trimEnd
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .onAppear {
            trimStart = recipe.trimStart
            trimEnd   = recipe.trimEnd
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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

    private let barHeight: CGFloat  = 48
    private let handleW:   CGFloat  = 18
    private let minTrim:   Double   = 0.5    // seconds

    var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let usable = totalW - handleW * 2  // area between handle outer edges

            // Position of the inner edge of each handle
            let startX = handleW + CGFloat(trimStart / duration) * usable
            let endX   = handleW + CGFloat(trimEnd   / duration) * usable

            ZStack(alignment: .leading) {
                // ── Full-track background ─────────────────────
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray4))
                    .frame(height: 6)
                    .padding(.horizontal, handleW)

                // ── Active range highlight ────────────────────
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: max(0, endX - startX), height: 6)
                    .offset(x: startX)

                // ── Start handle ──────────────────────────────
                handle(symbol: "chevron.left")
                    .offset(x: startX - handleW)
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { v in
                            let raw = Double((v.location.x - handleW) / usable) * duration
                            let clamped = max(0, min(raw, trimEnd - minTrim))
                            trimStart = clamped
                        }
                    )

                // ── End handle ────────────────────────────────
                handle(symbol: "chevron.right")
                    .offset(x: endX - handleW)
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { v in
                            let raw = Double((v.location.x - handleW) / usable) * duration
                            let clamped = min(duration, max(raw, trimStart + minTrim))
                            trimEnd = clamped
                        }
                    )
            }
            .frame(height: barHeight)
            .coordinateSpace(name: "trimBar")
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
