// 스탬프 카드 전용 상태 클래스.
// ShareCardView에서 @State private var stampVM = StampViewModel() 로 보유.
// StampCard / StampControls / Stamp*Template 뷰에서 @Bindable 로 전달.
//
// ⚠️ 이 파일은 스탬프 카드 전용.
//    Placeable · OneLiner · Athletic 관련 코드 작성 금지.

import SwiftUI

@Observable
@MainActor
final class StampViewModel {

    // MARK: - Per-photo Configs

    /// 사진 인덱스 → 스탬프 속성 전체. story/slide 에서 사진마다 독립 저장.
    var photoConfigs: [Int: StampPhotoConfig] = [:]

    /// 새 사진 진입 시 초기값. 스타일 속성 변경 시 함께 갱신(마지막 사용 스타일 유지).
    var baseConfig: StampPhotoConfig = .init()

    /// 현재 선택 사진의 config (읽기·쓰기)
    var currentConfig: StampPhotoConfig {
        get { photoConfigs[selectedClipIndex] ?? baseConfig }
        set { photoConfigs[selectedClipIndex] = newValue }
    }

    /// 특정 인덱스의 config 반환 (없으면 baseConfig)
    func photoConfig(at index: Int) -> StampPhotoConfig {
        photoConfigs[index] ?? baseConfig
    }

    // MARK: - 템플릿 (스토리·슬라이드·비디오 공통, per-photo)

    var storyTemplate: StampTemplate {
        get { currentConfig.template }
        set {
            var c = currentConfig; c.template = newValue; currentConfig = c
            baseConfig.template = newValue  // 새 사진도 이 템플릿에서 시작
            clampSizeForTemplate(newValue)
        }
    }

    /// 특대가 없는 스탬프로 바꾸면 크기 칩도 대(large)로 — 숨겨진 칩이 선택된 채로 남지 않게.
    private func clampSizeForTemplate(_ t: StampTemplate) {
        if !t.supportsXLarge, sizeLevel == .xlarge { sizeLevel = .large }
    }

    /// videoTemplate — 비디오 모드 별칭 (selectedClipIndex 기반, 동일 동작)
    var videoTemplate: StampTemplate {
        get { currentConfig.template }
        set {
            var c = currentConfig; c.template = newValue; currentConfig = c
            baseConfig.template = newValue
            clampSizeForTemplate(newValue)
        }
    }

    func photoTemplate(at index: Int) -> StampTemplate { photoConfig(at: index).template }

    // MARK: - 스타일 속성 (per-photo + baseConfig 갱신)

    var colorMode: StampColorMode {
        get { currentConfig.colorMode }
        set { var c = currentConfig; c.colorMode = newValue; currentConfig = c; baseConfig.colorMode = newValue }
    }

    var position: CardPosition {
        get { currentConfig.position }
        set { var c = currentConfig; c.position = newValue; currentConfig = c; baseConfig.position = newValue }
    }

    var sizeLevel: TextSizeLevel {
        get { currentConfig.sizeLevel }
        set { var c = currentConfig; c.sizeLevel = newValue; currentConfig = c; baseConfig.sizeLevel = newValue }
    }

    var showHeartRate: Bool {
        get { currentConfig.showHeartRate }
        set { var c = currentConfig; c.showHeartRate = newValue; currentConfig = c; baseConfig.showHeartRate = newValue }
    }

    /// 칼로리 표시는 켜는 UI가 없다 — 토글은 심박 하나뿐이다.
    /// 예전에 잠깐 있던 칩으로 true가 저장된 설정이 남아 있어도 꺼진 것으로 본다.
    /// (요약 그리드는 이 값을 보지 않고 있는 지표를 전부 넣는다.)
    var showCalories: Bool { false }

    /// 흰 배경(사진 없는 사진 탭) 전용 테두리 — 기본 꺼짐, 저장 안 함(시트 열 때마다 꺼짐).
    /// 사진·영상용 showTextOutline과 분리해 흰 배경에서 끈 것이 사진·영상으로 번지지 않게 한다.
    var whiteBgTextOutline: Bool = false

    var showTextOutline: Bool {
        get { currentConfig.showTextOutline }
        set { var c = currentConfig; c.showTextOutline = newValue; currentConfig = c; baseConfig.showTextOutline = newValue }
    }

    var showDate: Bool {
        get { currentConfig.showDate }
        set { var c = currentConfig; c.showDate = newValue; currentConfig = c; baseConfig.showDate = newValue }
    }

    // MARK: - 문구 텍스트 오버레이 (per-photo, baseConfig 갱신 없음)

    var stampText: String {
        get { currentConfig.text }
        set { var c = currentConfig; c.text = newValue; currentConfig = c }
    }

    func photoText(at index: Int) -> String { photoConfig(at: index).text }

    var stampTextPosition: CardPosition {
        get { currentConfig.textPosition }
        set { var c = currentConfig; c.textPosition = newValue; currentConfig = c; baseConfig.textPosition = newValue }
    }

    var stampTextFont: OneLinerFont {
        get { currentConfig.textFont }
        set { var c = currentConfig; c.textFont = newValue; currentConfig = c; baseConfig.textFont = newValue }
    }

    var stampTextSize: TextSizeLevel {
        get { currentConfig.textSize }
        set { var c = currentConfig; c.textSize = newValue; currentConfig = c; baseConfig.textSize = newValue }
    }

    var stampTextColor: OneLinerTextColor {
        get { currentConfig.textColor }
        set { var c = currentConfig; c.textColor = newValue; currentConfig = c; baseConfig.textColor = newValue }
    }

    var stampTextHasBorder: Bool {
        get { currentConfig.textHasBorder }
        set { var c = currentConfig; c.textHasBorder = newValue; currentConfig = c; baseConfig.textHasBorder = newValue }
    }

    // MARK: - 미디어

    var storyCropOffsetX: CGFloat = 0.5
    /// 사진 인덱스별 가로 크롭 위치 — 사진 전환 시 각자 독립 유지.
    var storyCropOffsets: [Int: CGFloat] = [:]
    var storyPhoto: UIImage? = nil
    var clipRecipes: [ClipRecipe] = []
    var selectedClipIndex: Int = 0 {
        didSet {
            // 첫 진입 시 baseConfig 스냅샷 저장 → 이후 다른 사진 변경이 소급 적용되는 것을 방지
            if photoConfigs[selectedClipIndex] == nil {
                photoConfigs[selectedClipIndex] = baseConfig
            }
        }
    }
    var muteAudio: Bool = false

    // MARK: - 애니메이션 옵션 (현재 클립 기준, per-clip)

    var stampEntranceMode: StampEntranceMode {
        get { currentConfig.entranceMode }
        set { var c = currentConfig; c.entranceMode = newValue; currentConfig = c; baseConfig.entranceMode = newValue }
    }
    var stampFlyDirection: FlyInDirection {
        get { currentConfig.flyDirection }
        set { var c = currentConfig; c.flyDirection = newValue; currentConfig = c; baseConfig.flyDirection = newValue }
    }
    var stampAnimated: Bool { stampEntranceMode != .none }

    var stampTextEntranceMode: StampEntranceMode {
        get { currentConfig.textEntranceMode }
        set { var c = currentConfig; c.textEntranceMode = newValue; currentConfig = c; baseConfig.textEntranceMode = newValue }
    }
    var stampTextFlyDirection: FlyInDirection {
        get { currentConfig.textFlyDirection }
        set { var c = currentConfig; c.textFlyDirection = newValue; currentConfig = c; baseConfig.textFlyDirection = newValue }
    }

    // MARK: - 출력 상태

    var isExporting: Bool = false
    var exportProgress: Double = 0
    var exportError: String? = nil

    // MARK: - 헬퍼

    var allowsColorChoice: Bool { !storyTemplate.isColorFixed }
    var showsPositionGrid: Bool { storyTemplate.positionMode != .fixed }
}
