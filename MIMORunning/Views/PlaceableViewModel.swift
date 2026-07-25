import SwiftUI

// MARK: - PlaceableSlideClipStyle
// 슬라이드 클립별 독립 스타일 — 폰트/색/위치/크기/애니메이션을 사진마다 개별 저장.

struct PlaceableSlideClipStyle: Codable {
    var fontID: String         = OneLinerFont.gothic.rawValue
    var colorID: String        = OneLinerTextColor.gold.rawValue
    var positionIdx: Int       = 0
    var sizeLevelID: String    = TextSizeLevel.large.rawValue
    var hasBorder: Bool        = true
    var plateOn: Bool          = false
    var platePresetID: String  = PlateColorPreset.blackWhite.rawValue
    var appearanceModeID: String = AppearanceMode.typing.rawValue
    var decorEffectID: String  = DecorEffect.none.rawValue
    var flyDirectionID: String = FlyInDirection.trailing.rawValue

    var font: OneLinerFont          { OneLinerFont(rawValue: fontID) ?? .gothic }
    var color: OneLinerTextColor    { OneLinerTextColor(rawValue: colorID) ?? .gold }
    var position: CardPosition      {
        let cases = Array(CardPosition.allCases)
        return cases.indices.contains(positionIdx) ? cases[positionIdx] : .bottom
    }
    var sizeLevel: TextSizeLevel    { TextSizeLevel(rawValue: sizeLevelID) ?? .large }
    var platePreset: PlateColorPreset { PlateColorPreset(rawValue: platePresetID) ?? .blackWhite }
    var appearanceMode: AppearanceMode { AppearanceMode(rawValue: appearanceModeID) ?? .typing }
    var decorEffect: DecorEffect    { DecorEffect(rawValue: decorEffectID) ?? .none }
    var flyDirection: FlyInDirection { FlyInDirection(rawValue: flyDirectionID) ?? .trailing }

    init() {}

    init(from vm: PlaceableViewModel) {
        fontID           = vm.placeableStoryFont.rawValue
        colorID          = vm.placeableStoryColor.rawValue
        positionIdx      = Array(CardPosition.allCases).firstIndex(of: vm.placeableStoryPosition) ?? 0
        sizeLevelID      = vm.placeableStorySize.rawValue
        hasBorder        = vm.placeableStoryHasBorder
        plateOn          = vm.placeableStoryPlateOn
        platePresetID    = vm.placeableStoryPlatePreset.rawValue
        appearanceModeID = vm.placeableSlideAppearance.rawValue
        decorEffectID    = vm.slideDecorEffect.rawValue
        flyDirectionID   = vm.slideFlyDirection.rawValue
    }
}

// MARK: - PlaceableViewModel
//
// Placeable 카드(cardIndex == 0)의 전용 상태 클래스.
// ShareCardView에서 @State private var placeableVM = PlaceableViewModel() 로 보유.
// PlaceableSection / Template 뷰에서 @Bindable var vm: PlaceableViewModel 으로 전달.
//
// ⚠️ 이 파일은 Placeable 카드 전용.
//    Athletic · OneLiner · BigNumber · Sky · ECG · Ticket 카드 관련 코드 작성 금지.

@Observable
@MainActor
final class PlaceableViewModel {

    // MARK: - Video / clip state

    var placeableVideoState: PlaceableVideoState = .init()
    var placeableClipRecipes: [ClipRecipe] = []
    var selectedPlaceableClipIndex: Int = 0
    var placeableMuteAudio: Bool = false
    /// 텍스트가 변경됐지만 아직 CALayer에 반영되지 않은 상태. play 전 rebuild 트리거용.
    var placeableVideoTextDirty: Bool = false
    var placeableEnabledMetricIDs: Set<String> = []
    var placeableVideoTitle: String = ""
    var placeableTitleStyle: OneLinerTitleStyle = .init()

    // MARK: - Layout / appearance

    var placeableMetricsPosition: CardPosition = .bottom
    var placeableAccent: CardAccent = .gold
    var placeableSize: PlaceableSize = .small
    var placeableLayout: PlaceableLayout = .horizontal
    var placeableHorizTextRow: HorizRow = .bottom
    var placeableHorizRoutePos: CardPosition = .center
    var horizGridMode: HorizGridMode = .text

    // MARK: - Slide clip styles (클립별 독립 스타일)

    var placeableSlideClipStyles: [Int: PlaceableSlideClipStyle] = [:]

    /// 인덱스의 클립 스타일 — 저장값 없으면 현재 전역값으로 폴백.
    func slideClipStyle(for index: Int) -> PlaceableSlideClipStyle {
        placeableSlideClipStyles[index] ?? PlaceableSlideClipStyle(from: self)
    }

    /// 전역 스타일 props → 지정 클립 인덱스 저장.
    func saveGlobalsToSlideClip(_ index: Int) {
        placeableSlideClipStyles[index] = PlaceableSlideClipStyle(from: self)
    }

    /// 지정 클립 인덱스 스타일(없으면 기본값) → 전역 스타일 props에 동기화.
    func syncGlobalsToSlideClip(_ index: Int) {
        let s = slideClipStyle(for: index)
        placeableStoryFont        = s.font
        placeableStoryColor       = s.color
        placeableStoryPosition    = s.position
        placeableStorySize        = s.sizeLevel
        placeableStoryHasBorder   = s.hasBorder
        placeableStoryPlateOn     = s.plateOn
        placeableStoryPlatePreset = s.platePreset
        placeableSlideAppearance  = s.appearanceMode
        slideDecorEffect          = s.decorEffect
        slideFlyDirection         = s.flyDirection
    }

    // MARK: - Story text overlay

    var placeableStoryTexts: [Int: String] = [:]
    var placeableStoryFont: OneLinerFont = .gothic
    var placeableStoryColor: OneLinerTextColor = .gold
    var placeableStoryPosition: CardPosition = .bottom
    var placeableStorySize: TextSizeLevel = .large
    var placeableStoryHasBorder: Bool = true
    var placeableStoryPlateOn: Bool = false
    var placeableStoryPlatePreset: PlateColorPreset = .blackWhite
    var placeableStoryTabIsText: Bool = false
    /// 사진별 좌우 크롭 위치. 0=왼쪽, 0.5=중앙, 1=오른쪽. 가로 사진에만 유효.
    var placeableStoryCropOffsets: [Int: CGFloat] = [:]
    var storyCropDragBase: CGFloat? = nil

    // MARK: - Slide animation

    var placeableSlideAppearance: AppearanceMode = .typing
    var slideDecorEffect: DecorEffect = .none
    var slideFlyDirection: FlyInDirection = .trailing

    // MARK: - Actions

    // 가로 레이아웃에서 데이터 행이 변경될 때 경로 위치 충돌 방지.
    func handleHorizTextRowChange(_ newRow: HorizRow) {
        guard posRow(placeableHorizRoutePos) == newRow else { return }
        switch newRow {
        case .top, .bottom: placeableHorizRoutePos = .center
        case .middle:       placeableHorizRoutePos = .bottom
        }
    }

    // MARK: - Computed layout insets (story text overlay)

    // OneLinerCard 내부에서 각 값에 8pt를 추가로 더함.
    var storyBottomReserved: CGFloat {
        let vf: CGFloat = placeableSize == .large ? 24 : 17
        let lineH = ceil(vf * 1.3)
        if placeableLayout == .horizontal {
            switch placeableHorizTextRow {
            case .bottom: return 14 + 26 + lineH - 8
            case .top:    return 14 + 50 - 8
            case .middle: return 0
            }
        } else {
            if placeableMetricsPosition.isBottom {
                let labelH = ceil(CGFloat(placeableSize == .large ? 12 : 8) * 1.2)
                return 14 + 26 + (lineH + 12 + labelH) * 3 - 8
            }
            return 0
        }
    }

    var storyTopReserved: CGFloat {
        let vf: CGFloat = placeableSize == .large ? 24 : 17
        let lineH = ceil(vf * 1.3)
        if placeableLayout == .horizontal {
            switch placeableHorizTextRow {
            case .top:    return 14 + 50 + lineH - 8
            case .bottom: return 14 + 26 - 8
            case .middle: return 0
            }
        } else {
            if placeableMetricsPosition.isTop {
                let labelH = ceil(CGFloat(placeableSize == .large ? 12 : 8) * 1.2)
                return 14 + 50 + (lineH + 12 + labelH) * 3 - 8
            }
            return 0
        }
    }
}
