import SwiftUI

// MARK: - ECG 카드 전용 설정 패널 View structs
//
// ⚠️ 이 파일은 ECG 카드(cardIndex == 5) 전용.
//    Athletic · OneLiner · Placeable · BigNumber · Sky · Ticket 카드 관련 코드 작성 금지.
//
// 파일별 담당:
//   ECGViewModel.swift   — 상태 (5개 변수)
//   ECGControls.swift    — 설정 패널 View struct (현재 파일)
//   ECGSignatureCard.swift — 실제 카드 렌더링
//   ECGWaveform.swift    — ECG 파형 그리기

// MARK: - ECGChipRowView
//
// 소스(페이스/심박) 라디오 + 악센트(바이올렛/골드/흰색) 선택 칩 행.

struct ECGChipRowView: View {
    @Bindable var vm:  ECGViewModel
    let onRender:      () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    sourceChip(label: AppLanguage.shared.s("페이스", "Pace"),
                               icon: "figure.run", isPace: true)
                    sourceChip(label: AppLanguage.shared.s("심박", "HR"),
                               icon: "heart.fill", isPace: false)
                        .opacity(vm.hrWaveform == nil ? 0.4 : 1.0)
                        .disabled(vm.hrWaveform == nil)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
            }
            accentRow
        }
    }

    private var accentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                accentChip(.violet, AppLanguage.shared.s("바이올렛", "Violet"), Color(hex: "9B7DFF"))
                accentChip(.gold,   AppLanguage.shared.s("골드",     "Gold"),   Color(hex: "FFC74D"))
                accentChip(.none,   AppLanguage.shared.s("흰색",     "White"),  .white)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
        }
    }

    private func accentChip(_ accent: CardAccent, _ label: String, _ color: Color) -> some View {
        let isSelected = vm.ecgAccent == accent
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { vm.ecgAccent = accent }
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

    private func sourceChip(label: String, icon: String, isPace: Bool) -> some View {
        let isSelected = vm.ecgShowPace == isPace
        let available  = isPace ? true : vm.hrWaveform != nil
        return Button {
            guard available else { return }
            withAnimation(.easeInOut(duration: 0.15)) { vm.ecgShowPace = isPace }
            Task { await onRender() }
        } label: {
            HStack(spacing: 4) {
                if isSelected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Theme.violet : Color.white.opacity(available ? 0.08 : 0.04))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
