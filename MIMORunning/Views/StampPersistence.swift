// Stamp 카드 설정 저장·복원 (UserDefaults ↔ StampViewModel)
//
// 기존에는 PlaceableVideoTemplate.swift 하단에 배치되어 있었음.
// 스탬프 전용 Codable DTO + extension ShareCardScreen 저장/복원 메서드.

import SwiftUI
import AVFoundation

// MARK: - Stamp 스토리 속성 저장·복원

/// StampPhotoConfig를 UserDefaults에 저장하기 위한 Codable 래퍼.
/// CardPosition은 allCases 인덱스로 직렬화한다.
private struct StampConfigDTO: Codable {
    var template: String
    var colorMode: String
    var positionIdx: Int
    var sizeLevel: String
    var showHeartRate: Bool
    var showCalories: Bool
    var showTextOutline: Bool
    var showDate: Bool?          // 2026-09 추가 — 구 저장값에는 없음
    var text: String
    var textPositionIdx: Int
    var textFont: String
    var textSize: String
    var textColor: String
    var textHasBorder: Bool
    // 애니메이션 (영상·슬라이드 클립별 독립)
    var entranceMode: String
    var flyDirection: String
    var textEntranceMode: String
    var textFlyDirection: String

    init(_ cfg: StampPhotoConfig) {
        let posAll = Array(CardPosition.allCases)
        template         = cfg.template.rawValue
        colorMode        = cfg.colorMode.rawValue
        positionIdx      = posAll.firstIndex(of: cfg.position) ?? 0
        sizeLevel        = cfg.sizeLevel.rawValue
        showHeartRate    = cfg.showHeartRate
        showCalories     = false   // 더 이상 쓰지 않음. 필드는 구버전 저장값 디코딩을 위해 남긴다
        showTextOutline  = cfg.showTextOutline
        showDate         = cfg.showDate
        text             = cfg.text
        textPositionIdx  = posAll.firstIndex(of: cfg.textPosition) ?? 0
        textFont         = cfg.textFont.rawValue
        textSize         = cfg.textSize.rawValue
        textColor        = cfg.textColor.rawValue
        textHasBorder    = cfg.textHasBorder
        entranceMode     = cfg.entranceMode.rawValue
        flyDirection     = cfg.flyDirection.rawValue
        textEntranceMode = cfg.textEntranceMode.rawValue
        textFlyDirection = cfg.textFlyDirection.rawValue
    }

    func toConfig() -> StampPhotoConfig {
        let posAll = Array(CardPosition.allCases)
        return StampPhotoConfig(
            template:        StampTemplate.resolvingLegacy(template) ?? .passportStamp,
            colorMode:       StampColorMode(rawValue: colorMode) ?? .auto,
            position:        posAll.indices.contains(positionIdx) ? posAll[positionIdx] : .bottom,
            sizeLevel:       TextSizeLevel(rawValue: sizeLevel) ?? .medium,
            showHeartRate:   showHeartRate || StampTemplate.legacyImpliesHeartRate(template),
            showTextOutline: showTextOutline,
            showDate:        true,    // 열 때마다 ON(B안, 2026-09) — 저장값은 복원하지 않는다. 끄는 건 그 카드 동안만.
            text:            text,
            textPosition:    posAll.indices.contains(textPositionIdx) ? posAll[textPositionIdx] : .top,
            textFont:        OneLinerFont(rawValue: textFont) ?? .gothic,
            textSize:        TextSizeLevel(rawValue: textSize) ?? .medium,
            textColor:       OneLinerTextColor(rawValue: textColor) ?? .white,
            textHasBorder:   textHasBorder,
            entranceMode:     StampEntranceMode(rawValue: entranceMode) ?? .stamp,
            flyDirection:     FlyInDirection(rawValue: flyDirection) ?? .trailing,
            textEntranceMode: StampEntranceMode(rawValue: textEntranceMode) ?? .fade,
            textFlyDirection: FlyInDirection(rawValue: textFlyDirection) ?? .bottom
        )
    }
}

private struct StampPhotoConfigEntry: Codable {
    var index: Int
    var config: StampConfigDTO
}

extension ShareCardScreen {

    var stampPrefix: String { "stamp_\(activity.id.uuidString)_" }

    func saveStampConfig() {
        let ud = UserDefaults.standard
        let p  = stampPrefix
        if let data = try? JSONEncoder().encode(StampConfigDTO(stampVM.baseConfig)) {
            ud.set(data, forKey: p + "base")
        }
        let entries = stampVM.photoConfigs.map { StampPhotoConfigEntry(index: $0.key, config: StampConfigDTO($0.value)) }
        if let data = try? JSONEncoder().encode(entries) {
            ud.set(data, forKey: p + "photos")
        }
        // 영상 클립 저장 (assetIdentifier가 있는 항목만)
        let descs = stampVM.clipRecipes.compactMap { r -> SavedClipDescriptor? in
            guard let assetID = r.assetIdentifier else { return nil }
            return SavedClipDescriptor(
                assetID: assetID, clipVideoRef: nil, photoRef: nil, thumbRef: r.thumbRef,
                trimStart: r.trimStart, trimEnd: r.trimEnd, fullDuration: r.fullDuration,
                lines: [], speed: r.speed)
        }
        if descs.isEmpty {
            ud.removeObject(forKey: p + "videoClips")
        } else {
            let saved = SavedRecipeSet(isPhotoSlide: false, muteAudio: stampVM.muteAudio, clips: descs)
            if let data = try? JSONEncoder().encode(saved) { ud.set(data, forKey: p + "videoClips") }
        }
        // 스토리 사진별 크롭 오프셋
        let storyCropDict = Dictionary(uniqueKeysWithValues: stampVM.storyCropOffsets.map { (String($0.key), Double($0.value)) })
        if let data = try? JSONEncoder().encode(storyCropDict) { ud.set(data, forKey: p + "storyCropOffsets") }
        // 슬라이드 사진별 크롭 오프셋
        let slideCropDict = Dictionary(uniqueKeysWithValues: stampSlideCropOffsets.map { (String($0.key), Double($0.value)) })
        if let data = try? JSONEncoder().encode(slideCropDict) { ud.set(data, forKey: p + "slideCropOffsets") }
    }

    func loadStampConfig() {
        let ud = UserDefaults.standard
        let p  = stampPrefix
        if let data = ud.data(forKey: p + "base"),
           let dto  = try? JSONDecoder().decode(StampConfigDTO.self, from: data) {
            stampVM.baseConfig = dto.toConfig()
        }
        if let data    = ud.data(forKey: p + "photos"),
           let entries = try? JSONDecoder().decode([StampPhotoConfigEntry].self, from: data) {
            for entry in entries {
                stampVM.photoConfigs[entry.index] = entry.config.toConfig()
            }
        }
        // 스토리 사진별 크롭 오프셋 복원
        if let data = ud.data(forKey: p + "storyCropOffsets"),
           let dict = try? JSONDecoder().decode([String: Double].self, from: data) {
            stampVM.storyCropOffsets = Dictionary(uniqueKeysWithValues:
                dict.compactMap { k, v in Int(k).map { ($0, CGFloat(v)) } })
            stampVM.storyCropOffsetX = stampVM.storyCropOffsets[0] ?? 0.5
        }
        // 슬라이드 사진별 크롭 오프셋 복원
        if let data = ud.data(forKey: p + "slideCropOffsets"),
           let dict = try? JSONDecoder().decode([String: Double].self, from: data) {
            stampSlideCropOffsets = Dictionary(uniqueKeysWithValues:
                dict.compactMap { k, v in Int(k).map { ($0, CGFloat(v)) } })
        }
    }

    func loadStampClipRecipes() async {
        let ud = UserDefaults.standard
        let p  = stampPrefix
        guard let data  = ud.data(forKey: p + "videoClips"),
              let saved = try? JSONDecoder().decode(SavedRecipeSet.self, from: data),
              !saved.clips.isEmpty else { return }
        stampVM.muteAudio = saved.muteAudio
        var restored: [ClipRecipe] = []
        for desc in saved.clips {
            guard let assetID = desc.assetID,
                  let avAsset = try? await MultiClipComposition.resolveAVAsset(assetID: assetID)
            else { continue }
            let url = (avAsset as? AVURLAsset)?.url
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("mimo_stmp_\(UUID().uuidString).mov")
            // 디스크 저장 썸네일 우선 복원, 없으면 firstFrame 시도
            let thumb: UIImage?
            if let tr = desc.thumbRef, let stored = ClipThumbStore.load(ref: tr) {
                thumb = stored
            } else {
                thumb = await VideoExportService.firstFrame(of: url)
            }
            var recipe = ClipRecipe(url: url, fullDuration: desc.fullDuration, thumbnail: thumb)
            recipe.trimStart       = desc.trimStart
            recipe.trimEnd         = desc.trimEnd
            recipe.speed           = desc.speed
            recipe.assetIdentifier = assetID
            recipe.resolvedAsset   = avAsset
            recipe.thumbRef        = desc.thumbRef
            restored.append(recipe)
        }
        guard !restored.isEmpty else { return }
        stampVM.clipRecipes = restored
        let data2 = stampPreviewData
        await loadStampVideoPreview(data: data2)
    }
}
