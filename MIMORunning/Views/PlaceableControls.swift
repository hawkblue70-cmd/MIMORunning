import SwiftUI

// MARK: - Placeable 카드 전용 설정 패널 View structs
//
// ⚠️ 이 파일은 Placeable 카드(ShareCard.placeable) 전용.
//    Athletic · OneLiner 카드 관련 코드 작성 금지.
//
// 파일별 담당:
//   PlaceableViewModel.swift  — 상태 (26개 변수 + layout 계산)
//   PlaceableSection.swift    — 순수 UI 헬퍼 free functions
//   PlaceableControls.swift   — 설정 패널 View structs (현재 파일)
//   PlaceableCard.swift       — 실제 카드 렌더링

// MARK: - PlaceableStoryTextFieldView
//
// 스토리/슬라이드 템플릿: 사진 위 문구 입력 필드 (최대 30자).

struct PlaceableStoryTextFieldView: View {
    @Bindable var vm:         PlaceableViewModel
    let photoIndex:           Int
    let storyPhotosCount:     Int
    var focused:              FocusState<Bool>.Binding

    var body: some View {
        let textBinding = Binding<String>(
            get: { vm.placeableStoryTexts[photoIndex] ?? "" },
            set: { vm.placeableStoryTexts[photoIndex] = String($0.prefix(30)) }
        )
        let currentText = vm.placeableStoryTexts[photoIndex] ?? ""
        let placeholder = storyPhotosCount > 1
            ? AppLanguage.shared.s("\(photoIndex + 1)번 사진 문구", "Photo \(photoIndex + 1) caption")
            : AppLanguage.shared.s("사진 위에 문구", "Text on photo")

        HStack(spacing: 8) {
            TextField(placeholder, text: textBinding)
                .focused(focused)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(Theme.violet)
            Spacer(minLength: 0)
            Text("\(currentText.count)/30")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "6E6E78"))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: "1E1E28"))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
    }
}

// MARK: - PlaceableTrimRowView
//
// 영상 템플릿: 선택된 클립의 한마디 입력 + 트림 슬라이더.

struct PlaceableTrimRowView: View {
    @Bindable var vm:          PlaceableViewModel
    let onSaveVideoClips:      () -> Void
    let onLoadPreview:         () async -> Void
    @FocusState private var textFocused: Bool

    var body: some View {
        let idx = vm.selectedPlaceableClipIndex
        if vm.placeableClipRecipes.indices.contains(idx) {
            let r    = vm.placeableClipRecipes[idx]
            let dur  = max(0.1, r.fullDuration)
            let used = max(0.1, r.trimEnd - r.trimStart)
            let fmt: (Double) -> String = { s in
                let i = Int(s); return "\(i / 60):\(String(format: "%02d", i % 60))"
            }
            let lineBinding = Binding<String>(
                get: { vm.placeableVideoTexts[idx] ?? "" },
                set: { val in
                    guard vm.placeableClipRecipes.indices.contains(idx) else { return }
                    let capped = String(val.prefix(30))
                    // lines 즉시 업데이트: onDisappear 등 동기 경로의 save에 대비
                    if vm.placeableClipRecipes[idx].lines.isEmpty {
                        vm.placeableClipRecipes[idx].lines = [capped]
                    } else {
                        vm.placeableClipRecipes[idx].lines[0] = capped
                    }
                    // observable 프로퍼티 업데이트 → onChange(of: placeableVideoTexts) 자동 발화 → 자동 저장
                    vm.placeableVideoTexts[idx] = capped
                }
            )
            VStack(spacing: 6) {
                // 텍스트 필드: "문구" 탭 선택 시 chip row에 이미 표시되므로 여기서는 숨김
                if !vm.placeableStoryTabIsText {
                    let lineText = vm.placeableVideoTexts[idx] ?? ""
                    HStack(spacing: 8) {
                        TextField(
                            AppLanguage.shared.s(
                                vm.placeableClipRecipes.count > 1
                                    ? "\(idx + 1)번 클립 한마디"
                                    : "클립 한마디",
                                vm.placeableClipRecipes.count > 1
                                    ? "Clip \(idx + 1) caption"
                                    : "Caption"),
                            text: lineBinding
                        )
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .tint(Theme.violet)
                        .focused($textFocused)
                        .onSubmit { Task { await onLoadPreview() } }
                        .onChange(of: textFocused) { _, focused in
                            if !focused { Task { await onLoadPreview() } }
                        }
                        Spacer(minLength: 0)
                        Text("\(lineText.count)/30")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "6E6E78"))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(hex: "1E1E28"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24)
                }
                HStack {
                    Text("\(fmt(r.trimStart)) – \(fmt(r.trimEnd))  ·  \(fmt(used)) 사용")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                TrimBarView(
                    duration:  dur,
                    trimStart: Bindable(vm).placeableClipRecipes[idx].trimStart,
                    trimEnd:   Bindable(vm).placeableClipRecipes[idx].trimEnd,
                    onEditingEnded: {
                        onSaveVideoClips()
                        Task { await onLoadPreview() }
                    }
                )
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 4)
        }
    }
}

// MARK: - PlaceableChipRowView
//
// 애슬레틱 템플릿용: 위치 그리드(3×3) + 레이아웃·크기·액센트 칩.
// 가로 레이아웃에서는 글자/경로 이중 모드 탭을 제공.

struct PlaceableChipRowView: View {
    @Bindable var vm:    PlaceableViewModel
    let template:        ShareTemplate
    let onRender:        () async -> Void

    private let rows: [[CardPosition]] = [
        [.topLeading, .top, .topTrailing],
        [.leading, .center, .trailing],
        [.bottomLeading, .bottom, .bottomTrailing]
    ]
    private let accents: [(CardAccent, String, Color)] = [
        (.none,   AppLanguage.shared.s("흰색",     "White"),  Color.white),
        (.violet, AppLanguage.shared.s("바이올렛", "Violet"), Color(hex: "9B7DFF")),
        (.gold,   AppLanguage.shared.s("골드",     "Gold"),   Color(hex: "FFC74D"))
    ]
    private let sizes: [(PlaceableSize, String)] = [
        (.large, AppLanguage.shared.s("크게", "Large")),
        (.small, AppLanguage.shared.s("작게", "Small"))
    ]
    private let layouts: [(PlaceableLayout, String)] = [
        (.vertical,   AppLanguage.shared.s("세로", "Vert")),
        (.horizontal, AppLanguage.shared.s("가로", "Horiz"))
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            positionGrid
            styleControls
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }

    // 위치 그리드 (왼쪽)
    @ViewBuilder private var positionGrid: some View {
        if vm.placeableLayout == .horizontal {
            VStack(spacing: 6) {
                horizModeTab
                gridCells
            }
        } else {
            VStack(spacing: 2) {
                if template == .photo {
                    Text(AppLanguage.shared.s("데이터", "Data"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                gridCells
            }
        }
    }

    // 가로 레이아웃 전용: 글자/경로 모드 탭
    private var horizModeTab: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { vm.horizGridMode = .text }
            } label: {
                Text(AppLanguage.shared.s("글자", "Text"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(vm.horizGridMode == .text ? .white : .white.opacity(0.4))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(vm.horizGridMode == .text ? Theme.violet.opacity(0.85) : Color.clear)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { vm.horizGridMode = .route }
            } label: {
                Text(AppLanguage.shared.s("경로", "Route"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(vm.horizGridMode == .route ? .white : .white.opacity(0.4))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(vm.horizGridMode == .route ? Color(hex: "5BA4FF").opacity(0.85) : Color.clear)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // 3×3 그리드 셀
    private var gridCells: some View {
        VStack(spacing: 4) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(rows[row].indices, id: \.self) { col in
                        let pos = rows[row][col]
                        let pr  = posRow(pos)
                        if vm.placeableLayout == .horizontal {
                            if vm.horizGridMode == .text {
                                let isRowSel = pr == vm.placeableHorizTextRow
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        vm.placeableHorizTextRow = pr
                                        vm.handleHorizTextRowChange(pr)
                                    }
                                    Task { await onRender() }
                                } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(isRowSel ? Theme.violet : Color(hex: "26262E"))
                                        .frame(width: 23, height: 23)
                                }
                                .buttonStyle(.plain)
                            } else {
                                let isLocked = pr == vm.placeableHorizTextRow
                                let isSel    = vm.placeableHorizRoutePos == pos
                                if isLocked {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(hex: "1C1C22"))
                                        .frame(width: 23, height: 23)
                                } else {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) { vm.placeableHorizRoutePos = pos }
                                        Task { await onRender() }
                                    } label: {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(isSel ? Color(hex: "5BA4FF") : Color(hex: "26262E"))
                                            .frame(width: 23, height: 23)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            let isSelected = vm.placeableMetricsPosition == pos
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { vm.placeableMetricsPosition = pos }
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
        }
    }

    // 레이아웃·크기·액센트 칩 (오른쪽)
    private var styleControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(layouts.indices, id: \.self) { i in
                    let (lyt, label) = layouts[i]
                    let isSelected = vm.placeableLayout == lyt
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.placeableLayout = lyt }
                        Task { await onRender() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(label).font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(isSelected ? Color(hex: "3A3A44") : Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                ForEach(sizes.indices, id: \.self) { i in
                    let (sz, label) = sizes[i]
                    let isSelected = vm.placeableSize == sz
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.placeableSize = sz }
                        Task { await onRender() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(label).font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(isSelected ? Color(hex: "3A3A44") : Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                ForEach(accents.indices, id: \.self) { i in
                    let (accent, label, color) = accents[i]
                    let isSelected = vm.placeableAccent == accent
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.placeableAccent = accent }
                        Task { await onRender() }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text(label).font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(isSelected
                            ? (accent == .none ? Color(hex: "3A3A44") : color.opacity(0.25))
                            : Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - PlaceableStoryModeChipRowView
//
// 스토리/슬라이드/영상 템플릿: [데이터|문구] 탭 + 위치·스타일 설정 패널.

struct PlaceableStoryModeChipRowView: View {
    @Bindable var vm:          PlaceableViewModel
    let template:              ShareTemplate
    let onRender:              () async -> Void
    let onSaveVideoClips:      () -> Void
    let onLoadPreview:         () async -> Void
    @FocusState private var clipTextFocused: Bool

    private let rows: [[CardPosition]] = [
        [.topLeading, .top, .topTrailing],
        [.leading, .center, .trailing],
        [.bottomLeading, .bottom, .bottomTrailing]
    ]
    private let accents: [(CardAccent, String, Color)] = [
        (.none,   AppLanguage.shared.s("흰색",     "White"),  Color.white),
        (.violet, AppLanguage.shared.s("바이올렛", "Violet"), Color(hex: "9B7DFF")),
        (.gold,   AppLanguage.shared.s("골드",     "Gold"),   Color(hex: "FFC74D"))
    ]
    private let sizes: [(PlaceableSize, String)] = [
        (.large, AppLanguage.shared.s("크게", "Large")),
        (.small, AppLanguage.shared.s("작게", "Small"))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                leftGrid
                if vm.placeableStoryTabIsText { textStyleControls }
                else                          { dataStyleControls }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
            // 영상 + 문구 탭: 입력 필드를 테두리/음영판 아래에 배치
            if template == .video, vm.placeableStoryTabIsText, !vm.placeableClipRecipes.isEmpty {
                let idx = min(vm.selectedPlaceableClipIndex, vm.placeableClipRecipes.count - 1)
                let lineBinding = Binding<String>(
                    get: { vm.placeableVideoTexts[idx] ?? "" },
                    set: { val in
                        guard idx < vm.placeableClipRecipes.count else { return }
                        let capped = String(val.prefix(30))
                        if vm.placeableClipRecipes[idx].lines.isEmpty {
                            vm.placeableClipRecipes[idx].lines = [capped]
                        } else {
                            vm.placeableClipRecipes[idx].lines[0] = capped
                        }
                        vm.placeableVideoTexts[idx] = capped
                    }
                )
                HStack(spacing: 8) {
                    TextField(
                        vm.placeableClipRecipes.count > 1
                            ? AppLanguage.shared.s("\(idx + 1)번 클립 한마디", "Clip \(idx + 1) caption")
                            : AppLanguage.shared.s("클립 한마디", "Caption"),
                        text: lineBinding
                    )
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .tint(Theme.violet)
                    .focused($clipTextFocused)
                    .onSubmit { Task { await onLoadPreview() } }
                    .onChange(of: clipTextFocused) { _, focused in
                        if !focused { Task { await onLoadPreview() } }
                    }
                    Spacer(minLength: 0)
                    Text("\((vm.placeableVideoTexts[idx] ?? "").count)/30")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "6E6E78"))
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "1E1E28"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
        }
    }

    // 왼쪽: [데이터|문구] 탭 + 위치 그리드
    @ViewBuilder private var leftGrid: some View {
        VStack(spacing: 8) {
            // [데이터 | 문구] 탭 칩
            HStack(spacing: 4) {
                placeableStoryTabChip(AppLanguage.shared.s("데이터", "Data"), on: !vm.placeableStoryTabIsText) {
                    withAnimation(.easeInOut(duration: 0.12)) { vm.placeableStoryTabIsText = false }
                }
                placeableStoryTabChip(AppLanguage.shared.s("문구", "Text"), on: vm.placeableStoryTabIsText) {
                    withAnimation(.easeInOut(duration: 0.12)) { vm.placeableStoryTabIsText = true }
                }
            }
            // 데이터 탭 + 가로 레이아웃: 글자/경로 서브 모드 탭
            if !vm.placeableStoryTabIsText, vm.placeableLayout == .horizontal {
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.horizGridMode = .text }
                    } label: {
                        Text(AppLanguage.shared.s("글자", "Text"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(vm.horizGridMode == .text ? .white : .white.opacity(0.4))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(vm.horizGridMode == .text ? Theme.violet.opacity(0.85) : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.horizGridMode = .route }
                    } label: {
                        Text(AppLanguage.shared.s("경로", "Route"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(vm.horizGridMode == .route ? .white : .white.opacity(0.4))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(vm.horizGridMode == .route ? Color(hex: "5BA4FF").opacity(0.85) : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            // 3×3 위치 그리드
            VStack(spacing: 4) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(rows[row].indices, id: \.self) { col in
                            let pos = rows[row][col]
                            gridCell(pos: pos)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func gridCell(pos: CardPosition) -> some View {
        if vm.placeableStoryTabIsText {
            if template == .video, !vm.placeableClipRecipes.isEmpty {
                // 영상: 선택된 클립별 독립 위치
                let safeIdx = min(vm.selectedPlaceableClipIndex, vm.placeableClipRecipes.count - 1)
                let isSel = vm.placeableClipRecipes[safeIdx].position == pos
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        vm.placeableClipRecipes[safeIdx].position = pos
                    }
                    onSaveVideoClips()
                    Task { await onLoadPreview() }
                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSel ? Theme.violet : Color(hex: "26262E"))
                        .frame(width: 23, height: 23)
                }
                .buttonStyle(.plain)
            } else {
                // 스토리·슬라이드: 전역 위치
                let isSel = vm.placeableStoryPosition == pos
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { vm.placeableStoryPosition = pos }
                    Task { await onRender() }
                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSel ? Theme.violet : Color(hex: "26262E"))
                        .frame(width: 23, height: 23)
                }
                .buttonStyle(.plain)
            }
        } else if vm.placeableLayout == .horizontal {
            // 데이터 위치 — 가로: 이중 모드
            let pr = posRow(pos)
            if vm.horizGridMode == .text {
                let isRowSel = pr == vm.placeableHorizTextRow
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        vm.placeableHorizTextRow = pr
                        vm.handleHorizTextRowChange(pr)
                    }
                    Task { await onRender() }
                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isRowSel ? Theme.violet : Color(hex: "26262E"))
                        .frame(width: 23, height: 23)
                }
                .buttonStyle(.plain)
            } else {
                let isLocked = pr == vm.placeableHorizTextRow
                let isSel    = vm.placeableHorizRoutePos == pos
                if isLocked {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "1C1C22"))
                        .frame(width: 23, height: 23)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.placeableHorizRoutePos = pos }
                        Task { await onRender() }
                    } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSel ? Color(hex: "5BA4FF") : Color(hex: "26262E"))
                            .frame(width: 23, height: 23)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            // 데이터 위치 — 세로
            let isSel = vm.placeableMetricsPosition == pos
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { vm.placeableMetricsPosition = pos }
                Task { await onRender() }
            } label: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSel ? Theme.violet : Color(hex: "26262E"))
                    .frame(width: 23, height: 23)
            }
            .buttonStyle(.plain)
        }
    }

    // 오른쪽: 문구 스타일 컨트롤
    private var textStyleControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 크기 + 테두리
            HStack(spacing: 6) {
                ForEach(TextSizeLevel.allCases, id: \.self) { sz in
                    let isSel = vm.placeableStorySize == sz
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.placeableStorySize = sz }
                        Task { await onRender() }
                    } label: { placeableStorySmallChip(sz.chipLabel, isSelected: isSel) }
                    .buttonStyle(.plain)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { vm.placeableStoryHasBorder.toggle() }
                    Task { await onRender() }
                } label: { placeableStorySmallChip(AppLanguage.shared.s("테두리", "Outline"), isSelected: vm.placeableStoryHasBorder) }
                .buttonStyle(.plain)
            }
            // 배속 + 음소거 (영상, 선택된 클립)
            if template == .video, !vm.placeableClipRecipes.isEmpty {
                let safeIdx = min(vm.selectedPlaceableClipIndex, vm.placeableClipRecipes.count - 1)
                let curSpeed = vm.placeableClipRecipes[safeIdx].speed
                HStack(spacing: 3) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach([0.5, 1.0, 1.5, 2.0] as [Double], id: \.self) { sp in
                        let isSel = abs(curSpeed - sp) < 0.01
                        Button {
                            let idx = min(vm.selectedPlaceableClipIndex, vm.placeableClipRecipes.count - 1)
                            vm.placeableClipRecipes[idx].speed = sp
                            onSaveVideoClips()
                            Task { await onLoadPreview() }
                        } label: {
                            placeableStorySmallChip(String(format: "%gx", sp), isSelected: isSel)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.placeableMuteAudio.toggle() }
                    } label: {
                        Image(systemName: vm.placeableMuteAudio ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(vm.placeableMuteAudio ? Color.orange : Color.white.opacity(0.75))
                            .frame(width: 28, height: 24)
                            .background(vm.placeableMuteAudio ? Color.orange.opacity(0.18) : Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            // 폰트
            HStack(spacing: 6) {
                ForEach(OneLinerFont.allCases, id: \.self) { f in
                    let isSel = vm.placeableStoryFont == f
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.placeableStoryFont = f }
                        Task { await onRender() }
                    } label: { placeableStorySmallChip(f.chipLabel, isSelected: isSel) }
                    .buttonStyle(.plain)
                }
            }
            // 색상
            HStack(spacing: 8) {
                    ForEach(OneLinerTextColor.allCases, id: \.self) { c in
                        let isSel = vm.placeableStoryColor == c
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { vm.placeableStoryColor = c }
                            Task { await onRender() }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(c.color)
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(
                                        c == .white ? Color.gray.opacity(0.4) : Color.clear,
                                        lineWidth: 1))
                                if isSel {
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                                        .frame(width: 24, height: 24)
                                }
                            }
                            .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                }
            // 애니메이션 (슬라이드·영상)
            if template == .slide || template == .video {
                // 영상: 선택된 클립별 독립 / 슬라이드: 전역
                let safeIdx: Int = (template == .video && !vm.placeableClipRecipes.isEmpty)
                    ? min(vm.selectedPlaceableClipIndex, vm.placeableClipRecipes.count - 1)
                    : -1
                let curAppearance: AppearanceMode = safeIdx >= 0
                    ? vm.placeableClipRecipes[safeIdx].appearanceMode
                    : vm.placeableSlideAppearance
                HStack(spacing: 6) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        let isSel = curAppearance == mode
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if safeIdx >= 0 { vm.placeableClipRecipes[safeIdx].appearanceMode = mode }
                                else { vm.placeableSlideAppearance = mode }
                            }
                            if safeIdx >= 0 { onSaveVideoClips(); Task { await onLoadPreview() } }
                        } label: { placeableStorySmallChip(mode.chipLabel, isSelected: isSel) }
                        .buttonStyle(.plain)
                    }
                }
                if curAppearance == .fade {
                    let curDecor: DecorEffect = safeIdx >= 0
                        ? vm.placeableClipRecipes[safeIdx].decorEffect
                        : vm.slideDecorEffect
                    HStack(spacing: 6) {
                        ForEach(DecorEffect.allCases, id: \.self) { effect in
                            let isSel = curDecor == effect
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if safeIdx >= 0 { vm.placeableClipRecipes[safeIdx].decorEffect = effect }
                                    else { vm.slideDecorEffect = effect }
                                }
                                if safeIdx >= 0 { onSaveVideoClips(); Task { await onLoadPreview() } }
                            } label: { placeableStorySmallChip(effect.chipLabel, isSelected: isSel) }
                            .buttonStyle(.plain)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if curAppearance == .flyIn {
                    let curDir: FlyInDirection = safeIdx >= 0
                        ? vm.placeableClipRecipes[safeIdx].flyDirection
                        : vm.slideFlyDirection
                    HStack(spacing: 6) {
                        ForEach(FlyInDirection.allCases, id: \.self) { dir in
                            let isSel = curDir == dir
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if safeIdx >= 0 { vm.placeableClipRecipes[safeIdx].flyDirection = dir }
                                    else { vm.slideFlyDirection = dir }
                                }
                                if safeIdx >= 0 { onSaveVideoClips(); Task { await onLoadPreview() } }
                            } label: { placeableStorySmallChip(dir.chipLabel, isSelected: isSel) }
                            .buttonStyle(.plain)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // 오른쪽: 데이터 스타일 컨트롤 (레이아웃 + 크기 + 액센트)
    private var dataStyleControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach([(PlaceableLayout.vertical, AppLanguage.shared.s("세로", "Vert")),
                         (PlaceableLayout.horizontal, AppLanguage.shared.s("가로", "Horiz"))],
                        id: \.0) { lyt, label in
                    let isSel = vm.placeableLayout == lyt
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.placeableLayout = lyt }
                        Task { await onRender() }
                    } label: { placeableStorySmallChip(label, isSelected: isSel) }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                ForEach(sizes.indices, id: \.self) { i in
                    let (sz, label) = sizes[i]
                    let isSel = vm.placeableSize == sz
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.placeableSize = sz }
                        Task { await onRender() }
                    } label: { placeableStorySmallChip(label, isSelected: isSel) }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                ForEach(accents.indices, id: \.self) { i in
                    let (accent, label, color) = accents[i]
                    let isSel = vm.placeableAccent == accent
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.placeableAccent = accent }
                        Task { await onRender() }
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text(label).font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(isSel ? Color.white : Color.white.opacity(0.5))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(isSel ? (accent == .none ? Color(hex: "3A3A44") : color.opacity(0.25)) : Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
