// 스탬프 카드 전용 상태 클래스.
// ShareCardView에서 @State private var stampVM = StampViewModel() 로 보유.
// StampCard / StampControls / Stamp*Template 뷰에서 @Bindable 로 전달.
//
// ⚠️ 이 파일은 스탬프 카드 전용.
//    Placeable · OneLiner · Athletic · BigNumber · Sky · ECG · Ticket 관련 코드 작성 금지.

import SwiftUI

@Observable
@MainActor
final class StampViewModel {

    // MARK: - 템플릿 선택 (출력별로 따로 기억)

    var storyTemplate: StampTemplate = .passportStamp
    var videoTemplate: StampTemplate = .hud
    var slideSet: StampSet = .classic
    /// 슬라이드 장별 개별 변경분 (없으면 세트에서 순환 배정)
    var slideTemplates: [Int: StampTemplate] = [:]

    // MARK: - 표시 스타일

    var colorMode: StampColorMode = .auto
    var position: CardPosition = .bottom
    var sizeLevel: TextSizeLevel = .medium

    // MARK: - 지표 (거리·페이스·시간은 항상 표시, 나머지 선택)

    var showHeartRate: Bool = false
    var showCalories: Bool = false

    // MARK: - 미디어

    var storyPhoto: UIImage? = nil
    var clipRecipes: [ClipRecipe] = []
    var selectedClipIndex: Int = 0
    var muteAudio: Bool = false

    // MARK: - 출력 상태

    var isExporting: Bool = false
    var exportProgress: Double = 0
    var exportError: String? = nil

    // MARK: - 메서드

    /// 슬라이드 i번째 장에 쓸 템플릿 (개별 지정이 없으면 세트에서 순환 배정)
    func slideTemplate(at index: Int) -> StampTemplate {
        if let override = slideTemplates[index] { return override }
        let templates = slideSet.templates
        guard !templates.isEmpty else { return .passportStamp }
        return templates[index % templates.count]
    }

    /// 현재 템플릿이 색 선택을 허용하는지 (isColorFixed 반대)
    var allowsColorChoice: Bool {
        !storyTemplate.isColorFixed
    }

    /// 현재 템플릿이 위치 그리드를 보여줘야 하는지 (positionMode != .fixed)
    var showsPositionGrid: Bool {
        storyTemplate.positionMode != .fixed
    }
}
