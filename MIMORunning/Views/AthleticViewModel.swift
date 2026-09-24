import SwiftUI
import PhotosUI

// MARK: - AthleticViewModel
//
// Athletic 카드(ShareCard.athletic)의 전용 상태 클래스.
//
// ShareCardView에서 @State var athleticVM = AthleticViewModel() 로 보유.
//
// ⚠️ 이 파일은 Athletic 영상 클립 상태 전용.
//    OneLiner · Placeable 카드 관련 코드 작성 금지.

@Observable
@MainActor
final class AthleticViewModel {

    // MARK: - 멀티 클립 (최대 5개)

    var athleticClipRecipes:         [ClipRecipe]       = []
    var athleticPickerItems:         [PhotosPickerItem]  = []
    var selectedAthleticClipIndex:   Int                = 0

    // MARK: - 영상 미리보기

    var athleticVideoState:     PlaceableVideoState = PlaceableVideoState()
    var athleticPreviewBuilding: Bool               = false
    var athleticMuted:          Bool                = false
}
