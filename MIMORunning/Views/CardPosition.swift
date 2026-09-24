import SwiftUI

// 카드 위 9칸 위치 — 스탬프·원라이너·휴식일 카드·영상 합성 공용.
// (플레이서블 카드 삭제 때 PlaceableCard.swift에서 옮김)

// MARK: - CardPosition

enum CardPosition: CaseIterable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading:     .topLeading
        case .top:            .top
        case .topTrailing:    .topTrailing
        case .leading:        .leading
        case .center:         .center
        case .trailing:       .trailing
        case .bottomLeading:  .bottomLeading
        case .bottom:         .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }

    /// Returns the position diagonally/cardinally opposite — used to auto-place route art.
    func opposite() -> CardPosition {
        switch self {
        case .leading:       .trailing
        case .trailing:      .leading
        case .top:           .bottom
        case .bottom:        .top
        case .topLeading:    .bottomTrailing
        case .topTrailing:   .bottomLeading
        case .bottomLeading: .topTrailing
        case .bottomTrailing:.topLeading
        case .center:        .bottom
        }
    }

    var isTop:    Bool { self == .topLeading    || self == .top    || self == .topTrailing }
    var isBottom: Bool { self == .bottomLeading || self == .bottom || self == .bottomTrailing }
    var isLeading: Bool { self == .topLeading   || self == .leading || self == .bottomLeading }
    var isTrailing: Bool { self == .topTrailing || self == .trailing || self == .bottomTrailing }
}
