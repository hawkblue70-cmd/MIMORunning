import SwiftUI
import UIKit

// MARK: - OneLinerViewModel
//
// OneLiner 카드(ShareCard.oneLiner)의 전용 상태 클래스.
// ShareCardView에서 @State var oneLinerVM = OneLinerViewModel() 로 보유.
// OneLiner 관련 자식 뷰에서 @Bindable var vm: OneLinerViewModel 으로 전달.
//
// ⚠️ 이 파일은 OneLiner 카드 전용.
//    Placeable · Athletic · BigNumber · Sky · ECG · Ticket 카드 관련 코드 작성 금지.

@Observable
@MainActor
final class OneLinerViewModel {

    // MARK: - Text / style state

    var oneLinerText:       String            = ""
    var oneLinerPosition:   CardPosition      = .center
    var oneLinerColor:      OneLinerTextColor = .white
    var oneLinerFont:       OneLinerFont      = .pen
    var oneLinerVideoTitle: String            = ""
    var oneLinerTitleStyle: OneLinerTitleStyle = OneLinerTitleStyle()

    // MARK: - Photo state

    /// Story/Slide 사진 UUID 배열 — OneLinerEntry.mediaRef("photo:UUID") 키로 사용.
    var storyPhotoUUIDs:         [String]        = []
    /// 링크된 PHAsset이 사진 앱에서 삭제된 경우 true.
    var oneLinerPhAssetDeleted:  Bool            = false
    /// PHAsset에서 불러온 고화질 이미지 (인덱스 → 이미지). SwiftData 썸네일 대신 렌더에 사용.
    var highQualityStoryPhotos:  [Int: UIImage]  = [:]
    /// PHAsset이 삭제된 스토리 사진의 인덱스 집합.
    var deletedPhotoIndices:     Set<Int>        = []

    // MARK: - Video / clip state

    /// 영상 다중 페이지 타이핑 애니메이션용 슬롯별 텍스트. 슬롯 1개당 텍스트 1개.
    var oneLinerVideoSlotTexts:  [String]        = ["", ""]
    /// 영상 길이(~3.5 s/슬롯)에서 자동 계산된 슬롯 수.
    var oneLinerVideoSlotCount:  Int             = 2
    /// 러닝 날 OneLiner용 멀티 클립 레시피 (비어있으면 단일 영상 경로 사용).
    var oneLinerClipRecipes:     [ClipRecipe]    = []
    /// 영상 템플릿 전환 시 클립 보존 백업 — 스토리/슬라이드로 전환해도 유지됨.
    var oneLinerVideoModeRecipes: [ClipRecipe]   = []
    var showOneLinerSheet:       Bool            = false
    var oneLinerMuteAudio:       Bool            = false
    var oneLinerEnabledMetricIDs: Set<String>    = []
    var currentOneLinerClipIndex: Int            = 0

    // MARK: - Story clip editor state

    var storyClipEditRecipes:    [ClipRecipe]    = []
    var storyClipEditIndex:      Int             = 0
    var showStoryClipEdit:       Bool            = false
    /// @Query 갱신 전 즉시 렌더용 캐시.
    var cachedStoryRecipes:      [ClipRecipe]    = []
    /// true = 슬라이드 모드에서 열림 / false = 스토리 모드에서 열림.
    var storyClipEditIsSlide:    Bool            = false
    /// 스토리 사진별 인메모리 가로 크롭 위치. 0=왼쪽, 0.5=중앙, 1=오른쪽.
    var oneLinerStoryCropOffsets: [Int: CGFloat] = [:]
    var oneLinerCropDragBase:     CGFloat?       = nil
}
