import SwiftUI

// MARK: - Ticket 카드 전용 설정 패널 View structs
//
// ⚠️ 이 파일은 Ticket 카드(cardIndex == 6) 전용.
//    Athletic · OneLiner · Placeable · BigNumber · Sky · ECG 카드 관련 코드 작성 금지.
//
// 파일별 담당:
//   TicketViewModel.swift  — 상태 (ticketDepartureName, ticketAccent)
//   TicketControls.swift   — 악센트 칩 행 View struct (현재 파일)
//   TicketCard.swift       — 실제 카드 렌더링

// MARK: - TicketAccentRowView
//
// 악센트 색 선택 칩 행: 자동(흰색) / 골드.
// 대회 티켓은 골드 고정 → ShareCardView에서 confirmedRace != nil 일 때 이 View를 숨김.

struct TicketAccentRowView: View {
    @Bindable var vm:  TicketViewModel
    let onRender:      () async -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.none, AppLanguage.shared.s("자동", "Auto"), .white)
                chip(.gold, AppLanguage.shared.s("골드", "Gold"), Color(hex: "FFC74D"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
        }
    }

    private func chip(_ accent: CardAccent, _ label: String, _ color: Color) -> some View {
        let isSelected = vm.ticketAccent == accent
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { vm.ticketAccent = accent }
            Task { await onRender() }
        } label: {
            HStack(spacing: 6) {
                if isSelected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                if accent != .none { Circle().fill(color).frame(width: 8, height: 8) }
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
