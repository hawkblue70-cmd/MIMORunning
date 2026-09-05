import SwiftUI

// MARK: - BigNumber 카드 전용 설정 패널 View structs
//
// ⚠️ 이 파일은 BigNumber 카드(cardIndex == 3) 전용.
//    Athletic · OneLiner · Placeable · Sky · ECG · Ticket 카드 관련 코드 작성 금지.
//
// 파일별 담당:
//   BigNumberViewModel.swift  — 상태 (bigNumberShowMemo, bigNumberAccent)
//   BigNumberControls.swift   — 악센트 칩 행 View struct (현재 파일)
//   BigNumberCard.swift       — 실제 카드 렌더링
//
// 참고: bigNumberChipRow 전체는 story·heroMetric·allMetricItems 등
//       ShareCardView 의존성이 있어 ShareCardView에 유지.

// MARK: - BigNumberAccentRowView
//
// 악센트 색 선택 칩 행: 흰색(기본) / 바이올렛 / 골드.

struct BigNumberAccentRowView: View {
    @Bindable var vm:  BigNumberViewModel
    let onRender:      () async -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.none,   AppLanguage.shared.s("흰색",     "White"),  .white)
                chip(.violet, AppLanguage.shared.s("바이올렛", "Violet"), Color(hex: "9B7DFF"))
                chip(.gold,   AppLanguage.shared.s("골드",     "Gold"),   Color(hex: "FFC74D"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
        }
    }

    private func chip(_ accent: CardAccent, _ label: String, _ color: Color) -> some View {
        let isSelected = vm.bigNumberAccent == accent
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { vm.bigNumberAccent = accent }
            Task { await onRender() }
        } label: {
            HStack(spacing: 6) {
                if isSelected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
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
