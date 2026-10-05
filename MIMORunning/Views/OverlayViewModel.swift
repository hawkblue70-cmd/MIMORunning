// 오버레이 카드 전용 상태.
// 문구·클립·크롭·등장 애니메이션은 스탬프 파이프라인을 그대로 쓰도록 StampViewModel 인스턴스(media)에 둔다
// (스탬프 카드의 stampVM과는 별개 인스턴스 — 두 카드 설정이 섞이지 않는다).
// media.currentConfig의 스탬프 칸(template·색상·크기)은 쓰지 않고, entranceMode는 오버레이 사진 레이어의 등장에 쓴다.
// 저장하지 않는다 — 시트를 닫으면 오버레이 사진·위치는 초기화.
// ⚠️ 오버레이 카드 전용.

import SwiftUI

@Observable
@MainActor
final class OverlayViewModel {

    /// 문구·클립·크롭·애니메이션 — 스탬프 렌더·출력 함수에 그대로 넘긴다.
    let media = StampViewModel()

    /// 오버레이 사진 2칸. 기본 위치는 아래 왼쪽·아래 오른쪽(문구 기본 위치는 위 가운데).
    var slots: [OverlayPhotoSlot] = [
        OverlayPhotoSlot(image: nil, position: .bottomLeading),
        OverlayPhotoSlot(image: nil, position: .bottomTrailing),
    ]

    var hasAnyPhoto: Bool { slots.contains { $0.image != nil } }

    // MARK: - 위치 점유 (겹침 금지)

    private var hasText: Bool { !media.stampText.isEmpty }

    /// target이 놓인 칸. 사진이 없거나 문구가 비면 칸을 차지하지 않는다(nil).
    private func occupiedPosition(of target: OverlayTarget) -> CardPosition? {
        switch target {
        case .photo(let i):
            guard slots.indices.contains(i), slots[i].image != nil else { return nil }
            return slots[i].position
        case .text:
            return hasText ? media.stampTextPosition : nil
        }
    }

    private var allTargets: [OverlayTarget] { [.photo(0), .photo(1), .text] }

    /// target 외 다른 요소가 차지한 칸 — 그리드에서 고를 수 없게 흐리게 표시.
    func blockedPositions(for target: OverlayTarget) -> Set<CardPosition> {
        Set(allTargets.filter { $0 != target }.compactMap { occupiedPosition(of: $0) })
    }

    func position(of target: OverlayTarget) -> CardPosition {
        switch target {
        case .photo(let i): return slots[i].position
        case .text:         return media.stampTextPosition
        }
    }

    func setPosition(_ pos: CardPosition, for target: OverlayTarget) {
        guard !blockedPositions(for: target).contains(pos) else { return }
        switch target {
        case .photo(let i): slots[i].position = pos
        case .text:         media.stampTextPosition = pos
        }
    }

    /// target이 새로 칸을 차지하게 됐을 때(사진 선택·문구 입력) 다른 요소와 겹치면 빈 칸으로 옮긴다.
    /// 지금 칸에서 가까운 순서(같은 줄 → 이웃 줄)로 찾는다.
    func resolveCollision(for target: OverlayTarget) {
        guard occupiedPosition(of: target) != nil else { return }
        let blocked = blockedPositions(for: target)
        let cur = position(of: target)
        guard blocked.contains(cur) else { return }
        let all = CardPosition.allCases
        guard let ci = all.firstIndex(of: cur) else { return }
        let (cr, cc) = (ci / 3, ci % 3)
        let free = all.enumerated()
            .filter { !blocked.contains($0.element) }
            .sorted { a, b in
                let da = abs(a.offset / 3 - cr) * 3 + abs(a.offset % 3 - cc)
                let db = abs(b.offset / 3 - cr) * 3 + abs(b.offset % 3 - cc)
                return da < db
            }
        if let next = free.first?.element {
            switch target {
            case .photo(let i): slots[i].position = next
            case .text:         media.stampTextPosition = next
            }
        }
    }

    // MARK: - 사진

    func setPhoto(_ image: UIImage?, at index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index].image = image?.overlayDownscaled()
        resolveCollision(for: .photo(index))
    }
}
