import SwiftUI

// MARK: - OneLiner 카드 전용 설정 패널 View structs
//
// ⚠️ 이 파일은 OneLiner 카드(cardIndex == 1) 전용.
//    Athletic · Placeable · BigNumber · Sky · ECG · Ticket 카드 관련 코드 작성 금지.
//
// 파일별 담당:
//   OneLinerViewModel.swift  — 상태 (24개 변수)
//   OneLinerControls.swift   — 설정 패널 View structs (현재 파일)
//   OneLinerCard.swift       — 실제 카드 렌더링
//   OneLinerPreviewPlayer.swift — 미리보기 플레이어

// MARK: - OneLinerTextFieldView
//
// 스토리·영상 템플릿: 한마디 텍스트 입력 + 라인 추가 버튼 (최대 3줄, 줄당 30자).

struct OneLinerTextFieldView: View {
    @Bindable var vm:    OneLinerViewModel
    var focusedLine:     FocusState<Int?>.Binding
    let onSave:          () -> Void
    let onRender:        () async -> Void

    private let lineCharLimit = 30

    private var lineCount: Int {
        max(1, vm.oneLinerText.components(separatedBy: "\n").count)
    }

    private func lineBinding(for index: Int) -> Binding<String> {
        Binding {
            let lines = vm.oneLinerText.components(separatedBy: "\n")
            return index < lines.count ? lines[index] : ""
        } set: { newVal in
            var lines = vm.oneLinerText.components(separatedBy: "\n")
            while lines.count <= index { lines.append("") }
            lines[index] = String(newVal.prefix(lineCharLimit))
            vm.oneLinerText = lines.prefix(lineCount).joined(separator: "\n")
            onSave()
            Task { await onRender() }
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(spacing: 6) {
                ForEach(0..<lineCount, id: \.self) { i in
                    let lineText: String = {
                        let lines = vm.oneLinerText.components(separatedBy: "\n")
                        return i < lines.count ? lines[i] : ""
                    }()
                    HStack(spacing: 8) {
                        TextField(
                            AppLanguage.shared.s(i == 0 ? "오늘의 한마디" : "\(i + 1)번째 줄",
                                                 i == 0 ? "Your one-liner" : "Line \(i + 1)"),
                            text: lineBinding(for: i)
                        )
                        .focused(focusedLine, equals: i)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .tint(Theme.violet)
                        Spacer(minLength: 0)
                        Text("\(lineText.count)/\(lineCharLimit)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "6E6E78"))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(hex: "1E1E28"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            if lineCount < 3 {
                Button {
                    vm.oneLinerText += "\n"
                    onSave()
                    Task { await onRender() }
                    let idx = lineCount - 1
                    Task { @MainActor in focusedLine.wrappedValue = idx }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.violet)
                        .frame(width: 36, height: 36)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
    }
}

// MARK: - OneLinerVideoSlotInputView
//
// 영상 슬롯별 텍스트 입력 (슬롯당 24자, 차례로 타이핑 애니메이션).

struct OneLinerVideoSlotInputView: View {
    @Bindable var vm:  OneLinerViewModel
    let onSave:        () -> Void
    let onRender:      () async -> Void

    var body: some View {
        let L = AppLanguage.shared
        VStack(spacing: 6) {
            ForEach(0..<vm.oneLinerVideoSlotCount, id: \.self) { idx in
                HStack(spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(hex: "6E6E78"))
                        .frame(width: 18, alignment: .trailing)
                    TextField(L.s("슬롯 \(idx + 1)", "Slot \(idx + 1)"),
                              text: Binding(
                        get: {
                            idx < vm.oneLinerVideoSlotTexts.count
                                ? vm.oneLinerVideoSlotTexts[idx] : ""
                        },
                        set: { newVal in
                            let capped = String(newVal.prefix(24))
                            if idx < vm.oneLinerVideoSlotTexts.count {
                                vm.oneLinerVideoSlotTexts[idx] = capped
                            }
                            vm.oneLinerText = vm.oneLinerVideoSlotTexts
                                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                .joined(separator: "\n")
                            onSave()
                            Task { await onRender() }
                        }
                    ))
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .tint(Theme.violet)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(hex: "1E1E28"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 24)

        Text(L.s("각 칸이 영상에서 차례로 타이핑됩니다", "Each slot types in sequence on the video"))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.bottom, 4)
    }
}

// MARK: - OneLinerGridAndChipsView
//
// 스토리·슬라이드 템플릿: 3×3 위치 그리드 + 폰트·색상 칩.

struct OneLinerGridAndChipsView: View {
    @Bindable var vm:            OneLinerViewModel
    let template:                ShareTemplate
    let hasSourceVideo:          Bool   // sourceVideoURL != nil || !oneLinerClipRecipes.isEmpty
    let onSave:                  () -> Void
    let onRender:                () async -> Void
    /// 영상 모드에서 클립별 스타일(위치·폰트·색상)이 변경될 때 호출. nil = 전역 모드(슬라이드·스토리).
    var onVideoStyleChange:      (() -> Void)? = nil

    private let rows: [[CardPosition]] = [
        [.topLeading, .top, .topTrailing],
        [.leading, .center, .trailing],
        [.bottomLeading, .bottom, .bottomTrailing]
    ]

    /// 영상 모드 선택 클립 인덱스. -1 = 전역 모드(슬라이드·스토리 또는 클립 없음).
    private var safeIdx: Int {
        guard template == .video, !vm.oneLinerClipRecipes.isEmpty else { return -1 }
        return min(vm.currentOneLinerClipIndex, vm.oneLinerClipRecipes.count - 1)
    }

    var body: some View {
        let shouldDisable = template == .video && !hasSourceVideo
        HStack(alignment: .center, spacing: 20) {
            // 3×3 위치 그리드
            VStack(spacing: 4) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(rows[row].indices, id: \.self) { col in
                            let pos = rows[row][col]
                            let isSelected: Bool = safeIdx >= 0
                                ? vm.oneLinerClipRecipes[safeIdx].position == pos
                                : vm.oneLinerPosition == pos
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if safeIdx >= 0 {
                                        vm.oneLinerClipRecipes[safeIdx].position = pos
                                        onVideoStyleChange?()
                                    } else {
                                        vm.oneLinerPosition = pos
                                    }
                                }
                                onSave()
                                Task { await onRender() }
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
            // 폰트 + 색상 칩
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(OneLinerFont.allCases, id: \.self) { f in
                        fontChip(f)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(OneLinerTextColor.allCases, id: \.self) { c in
                        colorChip(c)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .opacity(shouldDisable ? 0.35 : 1.0)
        .disabled(shouldDisable)
    }

    private func fontChip(_ font: OneLinerFont) -> some View {
        let isSelected: Bool = safeIdx >= 0
            ? vm.oneLinerClipRecipes[safeIdx].fontChoice == font
            : vm.oneLinerFont == font
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if safeIdx >= 0 {
                    vm.oneLinerClipRecipes[safeIdx].fontChoice = font
                    onVideoStyleChange?()
                } else {
                    vm.oneLinerFont = font
                }
            }
            onSave()
            Task { await onRender() }
        } label: {
            HStack(spacing: 4) {
                Text(font.chipLabel).font(.custom(font.fontName, size: 13))
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isSelected ? Color(hex: "3A3A44") : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func colorChip(_ textColor: OneLinerTextColor) -> some View {
        let isSelected: Bool = safeIdx >= 0
            ? vm.oneLinerClipRecipes[safeIdx].textColor == textColor
            : vm.oneLinerColor == textColor
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if safeIdx >= 0 {
                    vm.oneLinerClipRecipes[safeIdx].textColor = textColor
                    onVideoStyleChange?()
                } else {
                    vm.oneLinerColor = textColor
                }
            }
            onSave()
            Task { await onRender() }
        } label: {
            HStack(spacing: 6) {
                if textColor != .white { Circle().fill(textColor.color).frame(width: 8, height: 8) }
                Text(textColor.chipLabel).font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isSelected
                ? (textColor == .white ? Color(hex: "3A3A44") : textColor.color.opacity(0.25))
                : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
