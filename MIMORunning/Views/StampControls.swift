// 스탬프 카드 전용 편집 컨트롤.
// 스토리·영상·슬라이드 모두 동일한 단일 템플릿 선택 + 색상·위치·크기 인라인 표시.
// ⚠️ 스탬프 카드 전용. 다른 카드 코드 작성 금지.

import SwiftUI

// MARK: - StampControlsView

struct StampControlsView: View {
    @Bindable var vm: StampViewModel
    let template: ShareTemplate
    var data: StampData = .sample
    var onLoadPreview: (() async -> Void)? = nil
    @State private var showTemplatePicker = false
    @State private var controlTab: StampControlTab = .stamp
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // (a) 템플릿 선택 버튼
            Button { showTemplatePicker = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.stamp")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.violet)
                    Text(vm.storyTemplate.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            // (b) [스탬프|문구] 탭 + 그리드 + 스타일 — Placeable PlaceableStoryModeChipRowView 동일 구조
            HStack(alignment: .top, spacing: 20) {
                // 왼쪽: 탭 + 그리드
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        controlTabChip(AppLanguage.shared.s("스탬프", "Stamp"), on: controlTab == .stamp) {
                            withAnimation(.easeInOut(duration: 0.12)) { controlTab = .stamp }
                        }
                        controlTabChip(AppLanguage.shared.s("문구", "Text"), on: controlTab == .text) {
                            withAnimation(.easeInOut(duration: 0.12)) { controlTab = .text }
                        }
                    }
                    if controlTab == .stamp { stampPositionGrid }
                    else                   { textPositionGrid }
                }

                // 오른쪽: 스타일 컨트롤 — maxWidth .infinity 로 남은 너비 전부 사용 (칩 압축 방지)
                Group {
                    if controlTab == .stamp { stampStyleControls }
                    else                   { textStyleControls }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)

            // (c) 문구 입력 필드 (문구 탭일 때만) — Placeable PlaceableStoryTextFieldView 동일 구조
            if controlTab == .text {
                HStack(spacing: 8) {
                    TextField(template == .routeVideo
                                  ? AppLanguage.shared.s("경로 영상 제목", "Route video title")
                                  : AppLanguage.shared.s("사진 위에 문구", "Text on photo"),
                              text: $vm.stampText)
                        .focused($textFocused)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .tint(Theme.violet)
                        .onChange(of: vm.stampText) { _, new in
                            if new.count > 30 { vm.stampText = String(new.prefix(30)) }
                        }
                    Spacer(minLength: 0)
                    Text("\(vm.stampText.count)/30")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "6E6E78"))
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "1E1E28"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showTemplatePicker) {
            StampVisualPickerSheet(vm: vm, data: data, template: template)
        }
        .onChange(of: vm.storyTemplate) { _, newTpl in
            if newTpl.positionMode == .band3,
               vm.position != .top && vm.position != .center && vm.position != .bottom {
                vm.position = .center
            }
        }
    }

    // MARK: - 스탬프 탭 스타일 (오른쪽)

    private var stampStyleControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 색상 스와치 + 음소거(영상)
            HStack(spacing: 8) {
                ForEach(StampColorMode.allCases, id: \.rawValue) { mode in
                    colorSwatch(mode)
                }
                if template == .video { muteChip }
            }
            // 크기 + 데이터 테두리
            HStack(spacing: 4) {
                sizeChip(.small)
                sizeChip(.medium)
                sizeChip(.large)
                sizeChip(.xlarge)
                textOutlineChip
            }
            // 토글 행: 심박 · 칼로리 · 날짜(스토리)
            // ⚠ 칩을 위 크기 행에 붙이면 오른쪽 컬럼 폭(≈230pt)을 넘겨
            //   라벨이 "…"로 잘린다. 토글끼리 아랫줄로 분리한다.
            // 요약 그리드는 있는 지표를 전부 보여주므로 심박·칼로리 토글이 없다.
            let metricToggles = vm.storyTemplate != .summaryGrid
            if (metricToggles && (data.heartRate != nil || data.calories != nil)) || template == .story {
                HStack(spacing: 6) {
                    if metricToggles, data.heartRate != nil { heartRateChip }
                    if metricToggles, data.calories  != nil { caloriesChip }
                    if template == .story                   { dateChip }
                }
            }
            // 배속 — 영상, 클립이 있을 때
            if template == .video, !vm.clipRecipes.isEmpty {
                let idx      = min(vm.selectedClipIndex, vm.clipRecipes.count - 1)
                let curSpeed = vm.clipRecipes[idx].speed
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach([0.5, 1.0, 1.5, 2.0] as [Double], id: \.self) { sp in
                        let isSel = abs(curSpeed - sp) < 0.01
                        Button {
                            let i = min(vm.selectedClipIndex, vm.clipRecipes.count - 1)
                            vm.clipRecipes[i].speed = sp
                            Task { await onLoadPreview?() }
                        } label: { smallChip(String(format: "%gx", sp), isSelected: isSel) }
                        .buttonStyle(.plain)
                    }
                    dateChip   // 영상: 2x 다음
                }
            } else if template == .video {
                HStack(spacing: 6) { dateChip }   // 클립이 없을 때도 날짜 칩은 노출
            }
            // 애니메이션 모드 — 영상·슬라이드·경로 영상
            if template == .video || template == .slide || template == .routeVideo {
                HStack(spacing: 6) {
                    ForEach(StampEntranceMode.allCases, id: \.rawValue) { mode in
                        let isSel = vm.stampEntranceMode == mode
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                vm.stampEntranceMode = mode
                            }
                        } label: { smallChip(mode.chipLabel, isSelected: isSel) }
                        .buttonStyle(.plain)
                    }
                    if template == .slide || template == .routeVideo {
                        dateChip   // 슬라이드·경로 영상: '없음' 옆
                    }
                }
                // 방향 선택 — flyIn 모드일 때만
                if vm.stampEntranceMode == .flyIn {
                    HStack(spacing: 6) {
                        ForEach(FlyInDirection.allCases, id: \.rawValue) { dir in
                            let isSel = vm.stampFlyDirection == dir
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    vm.stampFlyDirection = dir
                                }
                            } label: { smallChip(dir.chipLabel, isSelected: isSel) }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 문구 탭 스타일 (오른쪽) — 크기→폰트→색상→테두리 (Placeable textStyleControls 동일 순서)

    private var textStyleControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 크기 + 테두리
            HStack(spacing: 4) {
                ForEach(TextSizeLevel.allCases, id: \.self) { sz in
                    let isSel = vm.stampTextSize == sz
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.stampTextSize = sz }
                    } label: { smallChip(sz.chipLabel, isSelected: isSel) }
                    .buttonStyle(.plain)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { vm.stampTextHasBorder.toggle() }
                } label: {
                    smallChip(AppLanguage.shared.s("테두리", "Outline"), isSelected: vm.stampTextHasBorder)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: vm.stampTextHasBorder)
            }
            HStack(spacing: 6) {
                ForEach(OneLinerFont.allCases, id: \.self) { f in
                    let isSel = vm.stampTextFont == f
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.stampTextFont = f }
                    } label: { smallChip(f.chipLabel, isSelected: isSel) }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                ForEach(OneLinerTextColor.allCases, id: \.self) { c in
                    let isSel = vm.stampTextColor == c
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.stampTextColor = c }
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
            // 문구 애니메이션 모드 — 영상·슬라이드·경로 영상
            if template == .video || template == .slide || template == .routeVideo {
                HStack(spacing: 6) {
                    ForEach(StampEntranceMode.allCases, id: \.rawValue) { mode in
                        let isSel = vm.stampTextEntranceMode == mode
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                vm.stampTextEntranceMode = mode
                            }
                        } label: { smallChip(mode.chipLabel, isSelected: isSel) }
                        .buttonStyle(.plain)
                    }
                }
                // 방향 선택 — flyIn 모드일 때만
                if vm.stampTextEntranceMode == .flyIn {
                    HStack(spacing: 6) {
                        ForEach(FlyInDirection.allCases, id: \.rawValue) { dir in
                            let isSel = vm.stampTextFlyDirection == dir
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    vm.stampTextFlyDirection = dir
                                }
                            } label: { smallChip(dir.chipLabel, isSelected: isSel) }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 스탬프 위치 그리드

    @ViewBuilder
    private var stampPositionGrid: some View {
        let positions = CardPosition.allCases
        if vm.storyTemplate.positionMode == .band3 {
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { row in
                    let pos = positions[row * 3 + 1]
                    let isSelected = vm.position == pos
                    Button { vm.position = pos } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? Theme.violet : Color(hex: "26262E"))
                            .frame(width: 23, height: 23)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
            }
        } else {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { col in
                    VStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { row in
                            let pos = positions[row * 3 + col]
                            let isSelected = vm.position == pos
                            Button {
                                vm.position = pos
                            } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isSelected ? Theme.violet : Color(hex: "26262E"))
                                    .frame(width: 23, height: 23)
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: isSelected)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 문구 위치 그리드

    private let gridRows: [[CardPosition]] = [
        [.topLeading,    .top,    .topTrailing],
        [.leading,       .center, .trailing],
        [.bottomLeading, .bottom, .bottomTrailing]
    ]

    private var textPositionGrid: some View {
        VStack(spacing: 4) {
            ForEach(gridRows.indices, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(gridRows[row].indices, id: \.self) { col in
                        let pos = gridRows[row][col]
                        let isSel = vm.stampTextPosition == pos
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { vm.stampTextPosition = pos }
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isSel ? Theme.violet : Color(hex: "26262E"))
                                .frame(width: 23, height: 23)
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: isSel)
                    }
                }
            }
        }
    }

    // MARK: - 칩 헬퍼

    private func controlTabChip(_ label: String, on: Bool,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? .white : .white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(on ? Theme.violet : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: on)
    }

    private func smallChip(_ label: String, isSelected: Bool) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Theme.violet : Color.white.opacity(0.08))
            .clipShape(Capsule())
    }

    private var textOutlineChip: some View {
        let isOn = vm.showTextOutline
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { vm.showTextOutline.toggle() }
        } label: {
            Text(AppLanguage.shared.s("테두리", "Outline"))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(isOn ? .white : .white.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isOn ? Theme.violet : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }

    /// 심박 토글 — 서클 배지(심박 변형)·HUD(LIVE 줄)·행 라벨 등 심박 푸터를 켠다.
    private var heartRateChip: some View {
        let isOn = vm.showHeartRate
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { vm.showHeartRate.toggle() }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "heart.fill").font(.system(size: 9))
                Text(AppLanguage.shared.s("심박", "HR"))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? .white : .white.opacity(0.55))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isOn ? Theme.violet : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }

    /// 칼로리 토글 — 심박과 같은 자리의 푸터·격자 칸을 켠다.
    /// `showCalories`는 뷰모델과 스탬프 뷰에 원래 있었는데 켜는 UI가 없어 항상 꺼진 상태였다.
    private var caloriesChip: some View {
        let isOn = vm.showCalories
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { vm.showCalories.toggle() }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill").font(.system(size: 9))
                Text(AppLanguage.shared.s("칼로리", "Cals"))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? .white : .white.opacity(0.55))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isOn ? Theme.violet : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }

    /// 날짜·시간 토글 — 워드마크 줄 오른쪽에 "2026. 9. 4 오후 6:16" 표시 (스토리·영상·슬라이드·경로 영상)
    private var dateChip: some View {
        let isOn = vm.showDate
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { vm.showDate.toggle() }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "calendar").font(.system(size: 9))
                Text(AppLanguage.shared.s("날짜", "Date"))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? .white : .white.opacity(0.55))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isOn ? Theme.violet : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }

    private var muteChip: some View {
        let isMuted = vm.muteAudio
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { vm.muteAudio.toggle() }
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                .font(.system(size: 11))
                .foregroundStyle(isMuted ? .white : .white.opacity(0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isMuted ? Theme.violet : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isMuted)
    }

    private func sizeChip(_ level: TextSizeLevel) -> some View {
        let isSelected = vm.sizeLevel == level
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { vm.sizeLevel = level }
        } label: {
            Text(level.chipLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Theme.violet : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - 색상 스와치

    private func colorSwatch(_ mode: StampColorMode) -> some View {
        let isSelected = vm.colorMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { vm.colorMode = mode }
        } label: {
            ZStack {
                swatchCircle(mode).frame(width: 24, height: 24)
                if mode == .auto {
                    Text("A").font(.system(size: 9, weight: .black)).foregroundStyle(.white)
                }
            }
            .padding(2)
            .overlay(Circle().stroke(isSelected ? Theme.violet : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    @ViewBuilder
    private func swatchCircle(_ mode: StampColorMode) -> some View {
        // 원안=fill색(그림자/채움), 바깥 링=outline색(글자색) — stampColors 반환값과 동일
        switch mode {
        case .auto:
            Circle().fill(Color(hex: "3A3A4A"))   // 자동: "A" 텍스트는 colorSwatch에서 오버레이
        case .brand:
            // fill=white, outline=violet → 흰 원 + 바이올렛 링
            Circle().fill(Color.white)
                .padding(3)
                .background(Circle().fill(Theme.violet))
        case .ink:
            // fill=black, outline=white → 검정 원 + 흰 링
            Circle().fill(Color.black)
                .padding(3)
                .background(Circle().fill(Color.white))
        case .lime:
            // fill=lime, outline=navy → 라임 원 + 남색 링
            Circle().fill(Color(hex: "C6FF00"))
                .padding(3)
                .background(Circle().fill(Color(hex: "14122B")))
        case .red:
            // fill=red, outline=navy → 레드 원 + 남색 링
            Circle().fill(Color(hex: "FF2E2E"))
                .padding(3)
                .background(Circle().fill(Color(hex: "14122B")))
        }
    }
}

// MARK: - StampVisualPickerSheet

struct StampVisualPickerSheet: View {
    @Bindable var vm: StampViewModel
    var data: StampData = .sample
    var template: ShareTemplate = .story
    @Environment(\.dismiss) private var dismiss

    private let naturalW: CGFloat = 300
    private let naturalH: CGFloat = 180

    // 현재 activity 데이터가 충족하지 못하는 템플릿 제외 + isVideoOnly 필터
    private var filteredTemplates: [StampTemplate] {
        StampTemplate.allCases.filter { tpl in
            let videoOK = !tpl.isVideoOnly || template == .video
            let dataOK: Bool = {
                for req in tpl.requires {
                    switch req {
                    case .none:      break
                    case .heartRate: if data.heartRate  == nil { return false }
                    case .hrZone:    if data.hrZoneIndex == nil { return false }
                    case .cadence:   if data.cadence    == nil { return false }
                    // 고도 0(트랙·평지)이면 프로파일이 평평해 그릴 그림이 없다
                    case .elevation: if (data.elevGain.flatMap(Double.init) ?? 0) <= 0 { return false }
                    case .location:
                        if data.placeName == nil && data.coordText == nil { return false }
                    case .route:
                        let hasMap   = data.routePoints != nil || data.mapImage != nil
                        let hasCoord = (data.routeCoordinates?.count ?? 0) >= 2
                        if !hasMap && !hasCoord { return false }
                    }
                }
                return true
            }()
            return videoOK && dataOK
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let hPad: CGFloat = 16
                let gap:  CGFloat = 12
                let cellW = max(0, (geo.size.width - hPad * 2 - gap) / 2)
                let cellH = cellW * (naturalH / naturalW)
                let scale = cellW / naturalW

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        ForEach(filteredTemplates) { tpl in
                            StampPreviewCell(
                                tpl: tpl, vm: vm,
                                data: data,
                                isSel: vm.storyTemplate == tpl,
                                cellW: cellW, cellH: cellH,
                                scale: scale,
                                naturalW: naturalW, naturalH: naturalH
                            ) {
                                vm.storyTemplate = tpl
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, hPad)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(AppLanguage.shared.s("스탬프 선택", "Select Stamp"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguage.shared.s("완료", "Done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - StampPreviewCell

private struct StampPreviewCell: View {
    let tpl:      StampTemplate
    @Bindable var vm: StampViewModel
    var data:     StampData = .sample
    let isSel:    Bool
    let cellW:    CGFloat
    let cellH:    CGFloat
    let scale:    CGFloat
    let naturalW: CGFloat
    let naturalH: CGFloat
    let onTap:    () -> Void

    @State private var cachedImg: UIImage? = nil
    private var renderKey: String { "\(tpl.rawValue)-\(vm.colorMode.rawValue)" }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: "1A1828"))

                    if let img = cachedImg {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: cellW, height: cellH)
                            .clipped()
                    } else {
                        // 렌더 완료 전에는 단순 플레이스홀더만 표시.
                        // 라이브 StampCard는 shadow 8개 × 텍스트 수 = 스크롤 중 심각한 MainActor 블로킹.
                        ProgressView()
                            .tint(.white.opacity(0.25))
                    }
                }
                .frame(width: cellW, height: cellH)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSel ? Theme.violet : Color.white.opacity(0.12),
                                lineWidth: isSel ? 2.5 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isSel {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.violet)
                            .padding(6)
                    }
                }

                Text(tpl.displayName)
                    .font(.system(size: 11, weight: isSel ? .semibold : .regular))
                    .foregroundStyle(isSel ? Theme.violet : .white.opacity(0.7))
                    .lineLimit(1)
                    .frame(width: cellW)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSel)
        .task(id: renderKey) {
            await renderCell()
        }
    }

    @MainActor
    private func renderCell() async {
        cachedImg = nil
        await Task.yield()
        guard !Task.isCancelled else { return }

        // MainActor에서 뷰 값 생성 (vm 접근 필요)
        // showTextOutline: false → 텍스트 1개당 shadow 8개 제거 → 렌더 2~4x 빠름
        let card = StampCard(
            data: data,
            template: tpl,
            colorMode: vm.colorMode,
            position: vm.position,
            sizeLevel: .large,
            isBrightBackground: false,
            showHeartRate: false,
            showCalories: false,
            showTextOutline: false
        )
        .frame(width: naturalW, height: naturalH)
        .background(Color(hex: "1A1828"))

        // ImageRenderer를 백그라운드 스레드에서 실행 → MainActor 해방 → 스크롤 끊김 없음
        // Swift 5 모드: @MainActor 경고는 발생하지만 컴파일·실행 정상 (Core Graphics는 스레드 안전)
        let img: UIImage? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let renderer = ImageRenderer(content: card)
                renderer.scale = 2.0
                continuation.resume(returning: renderer.uiImage)
            }
        }

        guard !Task.isCancelled else { return }
        cachedImg = img
    }
}
