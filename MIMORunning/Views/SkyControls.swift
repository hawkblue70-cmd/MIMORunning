import SwiftUI

// MARK: - Sky 카드 전용 설정 패널 View structs
//
// ⚠️ 이 파일은 Sky 카드(cardIndex == 4) 전용.
//    Athletic · OneLiner · Placeable · BigNumber · ECG · Ticket 카드 관련 코드 작성 금지.
//
// 파일별 담당:
//   SkyViewModel.swift  — 상태 (skyAccent 1개)
//   SkyControls.swift   — 악센트 칩 행 View struct (현재 파일)
//   SkyCard.swift       — 실제 카드 렌더링
//   SkyPalette.swift    — 팔레트 정의

// MARK: - SkyAccentRowView
//
// 악센트 색 선택 칩 행: 자동(흰색) / 바이올렛 / 골드.
// skyChipRow의 하단 부분 — lockedChip·canShowMiniMe 등 ShareCardView 의존 요소는 포함하지 않음.

struct SkyAccentRowView: View {
    @Bindable var vm:  SkyViewModel
    let onRender:      () async -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.none,   AppLanguage.shared.s("자동",     "Auto"),   .white)
                chip(.violet, AppLanguage.shared.s("바이올렛", "Violet"), Color(hex: "9B7DFF"))
                chip(.gold,   AppLanguage.shared.s("골드",     "Gold"),   Color(hex: "FFC74D"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
        }
    }

    private func chip(_ accent: CardAccent, _ label: String, _ color: Color) -> some View {
        let isSelected = vm.skyAccent == accent
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { vm.skyAccent = accent }
            Task { await onRender() }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? (accent == .none ? Color(hex: "3A3A44") : color.opacity(0.25))
                    : Color.white.opacity(0.08)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
