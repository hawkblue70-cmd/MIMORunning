import SwiftUI

// MARK: - Placeable 카드 전용 소형 UI 헬퍼
//
// 자유 함수(free function) 형태로 정의. @State 접근 없음 — 순수 파라미터 기반.
// ShareCardView 내부에서 self. 없이 직접 호출.
//
// ⚠️ 이 파일은 Placeable 카드 전용.
//    Athletic · OneLiner · BigNumber · Sky · ECG · Ticket 관련 코드 작성 금지.
//
// 파일별 담당:
//   PlaceableViewModel.swift      — Placeable 전용 @State (26개 변수) + layout 계산
//   PlaceableSection.swift        — 소형 UI 헬퍼 (현재 파일)
//   PlaceableVideoTemplate.swift  — 영상 템플릿 미리보기·설정·내보내기 (추후 이전)
//   PlaceableStoryTemplate.swift  — 스토리 템플릿 미리보기·설정·내보내기 (추후 이전)
//   PlaceableSlideTemplate.swift  — 슬라이드 템플릿 미리보기·설정·내보내기 (추후 이전)

// [문구 | 데이터] 탭 칩 — Placeable 스토리 템플릿 상단 탭 전용.
func placeableStoryTabChip(_ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label)
            .font(.system(size: 11, weight: on ? .semibold : .regular))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(on ? Theme.violet.opacity(0.22) : Color.white.opacity(0.08))
            .foregroundStyle(on ? Theme.violet : Color.white.opacity(0.55))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(on ? Theme.violet.opacity(0.55) : .clear, lineWidth: 1))
    }
    .buttonStyle(.plain)
}

// 소형 선택 칩 — Placeable 스토리 설정 옵션용 (폰트·색상·크기 등).
func placeableStorySmallChip(_ label: String, isSelected: Bool) -> some View {
    HStack(spacing: 4) {
        if isSelected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
        Text(label).font(.caption.weight(.semibold))
    }
    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
    .padding(.horizontal, 8).padding(.vertical, 6)
    .background(isSelected ? Theme.violet : Color.white.opacity(0.08))
    .clipShape(Capsule())
}

// CardPosition → HorizRow 변환 유틸리티 — Placeable 가로 레이아웃 전용.
func posRow(_ pos: CardPosition) -> HorizRow {
    if pos.isTop    { return .top }
    if pos.isBottom { return .bottom }
    return .middle
}
