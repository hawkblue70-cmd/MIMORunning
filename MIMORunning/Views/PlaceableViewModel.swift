import SwiftUI

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

    // MARK: - Slide animation

    var placeableSlideAppearance: AppearanceMode = .typing
    var slideDecorEffect: DecorEffect = .none
    var slideFlyDirection: FlyInDirection = .trailing
}
