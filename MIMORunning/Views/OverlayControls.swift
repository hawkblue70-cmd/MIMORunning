// 오버레이 카드 편집 컨트롤.
// [사진 1 | 사진 2 | 문구] 탭 + 9칸 위치 그리드(다른 요소가 차지한 칸은 흐리게·선택 불가) + 탭별 스타일.
// 문구 스타일·입력 필드는 스탬프 카드와 같은 컴포넌트(StampTextStyleControls·StampTextInputField).
// ⚠️ 오버레이 카드 전용.

import SwiftUI
import PhotosUI

struct OverlayControlsView: View {
    @Bindable var vm: OverlayViewModel
    let template: ShareTemplate

    @State private var target: OverlayTarget = .photo(0)
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickingIndex: Int = 0
    @State private var isLoadingPhoto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 20) {
                // 왼쪽: 탭 + 그리드
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        tabChip(AppLanguage.shared.s("사진 1", "Photo 1", ja: "写真1"), .photo(0))
                        tabChip(AppLanguage.shared.s("사진 2", "Photo 2", ja: "写真2"), .photo(1))
                        tabChip(AppLanguage.shared.s("문구", "Text", ja: "テキスト"), .text)
                    }
                    positionGrid
                }
                // 오른쪽: 탭별 스타일
                Group {
                    switch target {
                    case .photo(let i): photoControls(i)
                    case .text:         StampTextStyleControls(vm: vm.media, template: template)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)

            if target == .text {
                StampTextInputField(vm: vm.media, template: template)
            }
        }
        .padding(.vertical, 8)
        // 문구가 처음 생기면 칸을 차지한다 — 사진과 겹치면 가까운 빈 칸으로
        .onChange(of: vm.media.stampText.isEmpty) { _, isEmpty in
            if !isEmpty { vm.resolveCollision(for: .text) }
        }
        // 영상: 문구는 클립마다 따로라 클립을 바꾸면 그 클립 문구 위치가 사진과 겹칠 수 있다
        .onChange(of: vm.media.selectedClipIndex) { _, _ in
            vm.resolveCollision(for: .text)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            let idx = pickingIndex
            isLoadingPhoto = true
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                let img  = data.flatMap { UIImage(data: $0) }
                await MainActor.run {
                    if let img { vm.setPhoto(img, at: idx) }
                    isLoadingPhoto = false
                    pickerItem = nil
                }
            }
        }
    }

    // MARK: - 위치 그리드

    private var positionGrid: some View {
        let blocked = vm.blockedPositions(for: target)
        let current = vm.position(of: target)
        let all = CardPosition.allCases
        return VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { col in
                        let pos = all[row * 3 + col]
                        let isSel = current == pos
                        let isBlocked = blocked.contains(pos)
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { vm.setPosition(pos, for: target) }
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isSel ? Theme.violet : Color(hex: "26262E"))
                                .frame(width: 23, height: 23)
                                .overlay {
                                    // 다른 요소가 있는 칸 — 흐린 점으로 표시, 누를 수 없음
                                    if isBlocked {
                                        Circle().fill(Color.white.opacity(0.25)).frame(width: 6, height: 6)
                                    }
                                }
                                .opacity(isBlocked ? 0.45 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(isBlocked)
                        .animation(.easeInOut(duration: 0.15), value: isSel)
                    }
                }
            }
        }
    }

    // MARK: - 사진 탭

    @ViewBuilder
    private func photoControls(_ i: Int) -> some View {
        let slot = vm.slots[i]
        VStack(alignment: .leading, spacing: 6) {
            // 사진 선택·변경·삭제
            HStack(spacing: 8) {
                PhotosPicker(selection: Binding(
                    get: { pickerItem },
                    set: { pickingIndex = i; pickerItem = $0 }
                ), matching: .images) {
                    HStack(spacing: 6) {
                        if let img = slot.image {
                            Image(uiImage: img)
                                .resizable().scaledToFill()
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else if isLoadingPhoto, pickingIndex == i {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            Image(systemName: "photo.badge.plus").font(.system(size: 12))
                        }
                        Text(slot.image == nil
                             ? AppLanguage.shared.s("사진 선택", "Choose", ja: "写真を選択")
                             : AppLanguage.shared.s("바꾸기", "Change", ja: "変更"))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.violet.opacity(slot.image == nil ? 1 : 0.35))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                if slot.image != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.setPhoto(nil, at: i) }
                    } label: {
                        stampSmallChip(AppLanguage.shared.s("빼기", "Remove", ja: "外す"), isSelected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            // 크기 — 카드 폭 기준 10·20·30%
            HStack(spacing: 4) {
                ForEach(OverlaySizeLevel.allCases, id: \.self) { sz in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.slots[i].size = sz }
                    } label: { stampSmallChip(sz.chipLabel, isSelected: slot.size == sz) }
                    .buttonStyle(.plain)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { vm.media.showDate.toggle() }
                } label: {
                    stampSmallChip(AppLanguage.shared.s("날짜", "Date", ja: "日付"), isSelected: vm.media.showDate)
                }
                .buttonStyle(.plain)
            }
            // 등장 애니메이션 — 영상만 (사진 두 장이 함께 등장)
            if template == .video {
                HStack(spacing: 6) {
                    ForEach(StampEntranceMode.allCases, id: \.rawValue) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { vm.media.stampEntranceMode = mode }
                        } label: { stampSmallChip(mode.chipLabel, isSelected: vm.media.stampEntranceMode == mode) }
                        .buttonStyle(.plain)
                    }
                }
                if vm.media.stampEntranceMode == .flyIn {
                    HStack(spacing: 6) {
                        ForEach(FlyInDirection.allCases, id: \.rawValue) { dir in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { vm.media.stampFlyDirection = dir }
                            } label: { stampSmallChip(dir.chipLabel, isSelected: vm.media.stampFlyDirection == dir) }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 칩

    private func tabChip(_ label: String, _ t: OverlayTarget) -> some View {
        let on = target == t
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) { target = t }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(on ? .white : .white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(on ? Theme.violet : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: on)
    }
}
